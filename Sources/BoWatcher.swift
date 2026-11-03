import AppKit
import Foundation
import SQLite3

/// Bo keeps Google Drive for Desktop syncing: every minute he checks that it is running and that each account's drive
/// answers, and restarts Google Drive himself when it is stuck (2026-11-03, asked for as a constant job, restarting on
/// his own). Three signs count: Google Drive not running; a drive that does not answer a listing within 15 s for three
/// minutes running; and Finder not taking Drive's changes (below). Other errors in Drive's own log are shown, never acted
/// on: it holds hundreds of harmless ones.
///
/// Finder not taking Drive's changes (2026-11-03): Drive hands what changed in the cloud to macOS's File Provider
/// (fileproviderd), which shows it in Finder. When fileproviderd stops confirming them, Drive logs "Slow working set
/// change acknowledgment: N sec" with N growing; the drive still answers, but new folders never appear (a shared
/// drive's folder made on Oct 30 was missing on Nov 3, N at 26 hours). Restarting Google Drive alone does not help:
/// Bo quits Drive, restarts fileproviderd (macOS starts it again at once), and opens Drive.
///
/// Drive stuck quitting (2026-11-03): Drive began one of its own restarts at 07:48 and was still half-quit at 09:30,
/// syncing nothing, answering every quit with "Dropping Quit request … since we are already quitting" and ignoring
/// SIGTERM. A quit begun five minutes ago with Drive still running counts as stuck; a restart that cannot quit Drive
/// ends it with SIGKILL.
///
/// Finder missing what Drive has (2026-11-03): Finder's own copy of an account can break, and no restart mends it.
/// Drive's database listed 160 items at the top of a shared drive and Finder 117, a folder made days before among the
/// missing, while Drive and Finder both looked healthy. Every 15 minutes Bo compares the top of each drive; a gap that has
/// not closed in 15 minutes asks you, in a dialog, to disconnect the account and sign in again (Google's way to rebuild
/// it). For three hours after an account is connected, or after you say you are doing it, Bo leaves Drive alone: a
/// rebuild looks like every sign above.
///
/// Never in the middle of your own changes (2026-11-03): Bo force-quit Drive while it showed "Preparing to disconnect
/// account", and the disconnect never happened. Within 20 minutes of Drive's settings being open, he restarts nothing.
/// And the Finder restart is tried once in three hours: when the changes stall again after it, Finder's copy is broken,
/// and Bo asks you to reconnect the account instead.
///
/// A disconnect that hangs: "Preparing to disconnect account" with nothing changing in Drive's windows for 10 minutes
/// brings up Bo's dialog, whose button restarts Google Drive (quit, forced if need be) so you can try again. Only Drive's
/// own disconnect rebuilds Finder's copy: it lives in ~/Library/Application Support/FileProvider, which only Drive can
/// remove, so moving Drive's own folder aside would not.
/// He also keeps track of what Drive keeps on this Mac (its cache, old logs, files it could not upload) and says when
/// clearing is worth it (2026-11-03); he never deletes anything himself. Clearing the cache is done Google's way,
/// disconnecting the account and signing in again, which keeps files that have not uploaded yet.
@MainActor
final class BoWatcher: ObservableObject {
    struct Drive: Identifiable {
        let url: URL
        /// The account, from the folder's name ("GoogleDrive-name@domain").
        var account: String { String(url.lastPathComponent.dropFirst("GoogleDrive-".count)) }
        /// Nil while checking for the first time.
        var answered: Bool?
        var milliseconds: Int?
        var id: URL { url }
    }
    struct Event: Identifiable { let id = UUID(); let time: Date; let text: String }

    static let bundleID = "com.google.drivefs"
    @Published private(set) var running = false
    @Published private(set) var drives: [Drive] = []
    @Published private(set) var lastCheck: Date?
    /// Drive's log errors of the last 24 hours, by kind, every kind listed.
    @Published private(set) var errors: [ErrorCount] = ErrorKind.allCases.map { ErrorCount(kind: $0) }
    /// How long Finder has left Drive's changes unconfirmed, by account number, from Drive's latest log line.
    @Published private(set) var finderLag: [String: Int] = [:]
    /// Drives whose top Finder shows less of than Drive's database has, found every 15 minutes.
    @Published private(set) var finderMissing: [Missing] = []
    /// Set when the gap has lasted: the dialog asking you to disconnect and reconnect the account.
    @Published var reconnect: Reconnect?
    /// Something Bo watches for is wrong right now (see `onFire`).
    @Published private(set) var trouble = false
    /// Bo panics, fire and all: Drive not running or not answering, Finder not taking its changes or missing what it
    /// has, Drive stuck quitting or disconnecting, or a dialog of his waiting for you.
    var onFire: Bool { trouble || reconnect != nil || disconnectStuck != nil }
    /// Since when Drive has shown "Preparing to disconnect account" without anything changing, once 10 minutes have passed.
    @Published var disconnectStuck: Date?
    /// Until when Bo leaves Drive alone: you are rebuilding an account.
    @Published private(set) var holdUntil: Date? = (UserDefaults.standard.object(forKey: "boHoldUntil") as? Date).flatMap { $0 > Date() ? $0 : nil }
    /// When each drive's gap was first seen, and how big it was.
    private var gapSince: [String: (time: Date, missing: Int)] = [:]
    /// What Drive keeps on this Mac; measured every 15 minutes.
    @Published private(set) var storage: Storage?
    /// How much the caches grew, and since when Bo has been measuring them.
    @Published private(set) var cacheGrowth: (bytes: Int64, since: Date)?
    @Published private(set) var events: [Event] = []
    /// Bo moves while he checks or restarts.
    @Published private(set) var busyUntil: Date?
    /// Also written to the activity log.
    var onLog: ((String) -> Void)?
    private var timer: Timer?
    private var checking = false
    private var stuckSince: Date?
    private var lastRestart: Date?
    private var lastMeasure: Date?
    /// Drive's settings were open at the last check (noted once).
    private var settingsOpen = false
    /// When Bo last restarted File Provider for Finder not taking changes: once in three hours.
    private var lastFinderRestart: Date?
    private static let answerWithin: TimeInterval = 15, stuckFor: TimeInterval = 180, restartsApart: TimeInterval = 1800
    /// Changes unconfirmed this long mean Finder has stopped taking them; a few minutes happen when Drive is busy.
    nonisolated static let finderStuckAfter = 1800

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.check() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.check() }
    }

    func check() {
        guard !checking else { return }
        checking = true
        busyUntil = Date().addingTimeInterval(2)
        running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).contains { !$0.isTerminated }
        let roots = ((try? FileManager.default.contentsOfDirectory(at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage"),
                                                                   includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("GoogleDrive-") }.sorted { $0.path < $1.path }
        if drives.map(\.url) != roots { drives = roots.map { Drive(url: $0) } }
        let measure = lastMeasure.map { Date().timeIntervalSince($0) > 900 } ?? true
        if measure { lastMeasure = Date() }
        let known = Self.knownAccounts
        Task.detached(priority: .utility) { [weak self] in
            var results: [(URL, Bool, Int)] = []
            for root in roots { results.append(Self.answers(root)) }
            let errors = Self.readErrors()
            let (lag, quitting, settings, disconnecting) = Self.readDriveLog()
            let storage = measure ? Self.measure(known: known) : nil
            // Accounts by email: the ones Bo remembers, and any the measuring just found.
            var emails = known
            for account in storage?.accounts ?? [] { if let email = account.email { emails[account.id] = email } }
            let missing = measure ? Self.compareFinder(emails: emails) : nil
            await MainActor.run { self?.finish(results, errors: errors, lag: lag, quitting: quitting, settings: settings,
                                                         disconnecting: disconnecting, storage: storage, missing: missing) }
        }
    }

    private func finish(_ results: [(URL, Bool, Int)], errors: [ErrorCount], lag: [String: Int], quitting: Date?, settings: Date?,
                        disconnecting: Date?, storage: Storage?, missing: [Missing]?) {
        checking = false
        lastCheck = Date()
        self.errors = errors
        finderLag = lag
        if let storage { measured(storage) }
        if let missing { compared(missing) }
        drives = results.map { Drive(url: $0.0, answered: $0.1, milliseconds: $0.2) }
        let now = Date()
        trouble = !running || drives.contains { $0.answered == false }
            || lag.contains { $0.value >= Self.finderStuckAfter && !Self.isNew($0.key) }
            || quitting.map { now.timeIntervalSince($0) > 300 } ?? false
            || disconnecting.map { now.timeIntervalSince($0) >= 600 } ?? false
            || !finderMissing.isEmpty
        // Half-quit and stuck there: Drive restarts itself after a sign-out, an update or a settings change, and froze
        // doing so on 2026-11-03. Before the hold and the settings rule: a half-quit Drive does nothing and finishes
        // nothing you started, so ending it is always right. Not again while a restart of Bo's is still going.
        if let quitting, running, Date().timeIntervalSince(quitting) > 300, busyUntil.map({ Date() > $0 }) ?? true {
            restart(because: "Google Drive has been stuck quitting since \(quitting.formatted(date: .omitted, time: .shortened))")
            return
        }
        // Before the hold: you are reconnecting, and this is the step that can hang.
        if let disconnecting, running, Date().timeIntervalSince(disconnecting) >= 600 {
            if disconnectStuck == nil, (UserDefaults.standard.object(forKey: "boDisconnectLater") as? Date).map({ Date() > $0 }) ?? true {
                disconnectStuck = disconnecting
                note("Google Drive has been preparing to disconnect since \(disconnecting.formatted(date: .omitted, time: .shortened)) without moving")
            }
        } else if disconnectStuck != nil {
            disconnectStuck = nil
        }
        if let holdUntil {
            if Date() < holdUntil { return }
            self.holdUntil = nil; UserDefaults.standard.removeObject(forKey: "boHoldUntil")
            note("Done waiting for Google Drive to rebuild")
        }
        if let settings, Date().timeIntervalSince(settings) < 1200 {
            if !settingsOpen { settingsOpen = true; note("Google Drive's settings are open: not restarting it while you change them") }
            return
        }
        settingsOpen = false
        if !running {
            // Not running at all: open it, at most once every half hour (you may have quit it on purpose just now).
            if lastRestart.map({ Date().timeIntervalSince($0) > Self.restartsApart }) ?? true { open(because: "Google Drive was not running") }
            return
        }
        // A freshly connected account is still being built: its changes queue up for Finder, and that is not stuck.
        let behind = lag.filter { $0.value >= Self.finderStuckAfter && !Self.isNew($0.key) }
        if !behind.isEmpty, lastRestart.map({ Date().timeIntervalSince($0) > Self.restartsApart }) ?? true {
            let names = behind.keys.sorted().map { accountName($0) }.joined(separator: ", ")
            if lastFinderRestart.map({ Date().timeIntervalSince($0) < 3 * 3600 }) ?? false {
                // Stalled again after a restart: a restart does not mend it. Ask for the rebuild, once.
                if reconnect == nil, (UserDefaults.standard.object(forKey: "boReconnectLater") as? Date).map({ Date() > $0 }) ?? true,
                   let account = behind.keys.sorted().first {
                    reconnect = Reconnect(account: account, email: Self.knownAccounts[account] ?? storage?.accounts.first { $0.id == account }?.email,
                                          missing: finderMissing.filter { $0.account == account })
                    note("Finder stalled again on \(names)'s changes after a restart: asked you to reconnect it")
                }
                return
            }
            lastFinderRestart = Date()
            restart(because: "Finder has not taken \(names)'s changes for \(Self.duration(behind.values.max() ?? 0))", fileProvider: true)
            return
        }
        let stuck = drives.filter { $0.answered == false }
        guard !stuck.isEmpty else {
            if stuckSince != nil { note("Google Drive answers again") }
            stuckSince = nil; return
        }
        if stuckSince == nil {
            stuckSince = Date()
            note("\(stuck.map(\.account).joined(separator: ", ")) not answering; restarting Google Drive if it is still stuck in 3 minutes")
        }
        if let since = stuckSince, Date().timeIntervalSince(since) >= Self.stuckFor,
           lastRestart.map({ Date().timeIntervalSince($0) > Self.restartsApart }) ?? true {
            restart(because: "\(stuck.map(\.account).joined(separator: ", ")) did not answer for 3 minutes")
        }
    }

    /// Quits Google Drive (forced after 20 s), then opens it again; with `fileProvider`, restarts macOS's fileproviderd
    /// in between, so it takes Drive's changes again.
    private func restart(because reason: String, fileProvider: Bool = false) {
        lastRestart = Date(); stuckSince = nil
        Self.recordRestart()
        busyUntil = Date().addingTimeInterval(45)
        note("Restarting Google Drive: \(reason)")
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
        apps.forEach { $0.terminate() }
        Task { @MainActor in
            for _ in 0 ..< 40 where apps.contains(where: { !$0.isTerminated }) { try? await Task.sleep(for: .milliseconds(500)) }
            apps.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
            for _ in 0 ..< 20 where apps.contains(where: { !$0.isTerminated }) { try? await Task.sleep(for: .milliseconds(500)) }
            if apps.contains(where: { !$0.isTerminated }) {
                // Stuck quitting, it ignores even SIGTERM: SIGKILL, for it and its helper process.
                let kill = Process()
                kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill"); kill.arguments = ["-9", "-f", "Google Drive.app/Contents/MacOS/Google Drive"]
                kill.standardOutput = FileHandle.nullDevice; kill.standardError = FileHandle.nullDevice
                if (try? kill.run()) != nil { kill.waitUntilExit() }
                self.note("Google Drive would not quit: ended it")
                try? await Task.sleep(for: .seconds(2))
            }
            if fileProvider {
                // Yours, not the system's: macOS starts a new one as soon as anything asks for it.
                let kill = Process()
                kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall"); kill.arguments = ["fileproviderd"]
                kill.standardOutput = FileHandle.nullDevice; kill.standardError = FileHandle.nullDevice
                if (try? kill.run()) != nil { kill.waitUntilExit() }
                self.note(kill.terminationStatus == 0 ? "Restarted macOS's File Provider (fileproviderd)" : "Could not restart macOS's File Provider")
                try? await Task.sleep(for: .seconds(3))
            }
            try? await Task.sleep(for: .seconds(2))
            self.launch()
        }
    }

    private func open(because reason: String) {
        lastRestart = Date()
        busyUntil = Date().addingTimeInterval(10)
        note("Opening Google Drive: \(reason)")
        launch()
    }

    private func launch() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            note("Google Drive is not installed"); return
        }
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            if let error { Task { @MainActor in self.note("Could not open Google Drive: \(error.localizedDescription)") } }
        }
    }

    private func note(_ text: String) {
        events.insert(Event(time: Date(), text: text), at: 0)
        if events.count > 30 { events.removeLast(events.count - 30) }
        onLog?("Bo: \(text)")
    }

    /// Lists the drive's top folder in a separate process, so a drive that hangs blocks only that process.
    nonisolated static func answers(_ root: URL) -> (URL, Bool, Int) {
        let began = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ls")
        process.arguments = [root.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        guard (try? process.run()) != nil else { return (root, false, 0) }
        let answered = done.wait(timeout: .now() + answerWithin) == .success && process.terminationStatus == 0
        if process.isRunning { process.terminate() }
        return (root, answered, Int(Date().timeIntervalSince(began) * 1000))
    }

    // MARK: Finder missing what Drive has

    struct Missing: Identifiable, Equatable {
        let account: String
        let email: String?
        let drive: String
        /// Items at the top of the drive in Drive's database, and in Finder.
        let inDrive: Int, inFinder: Int
        var id: String { account + "/" + drive }
        var gap: Int { inDrive - inFinder }
    }
    struct Reconnect: Identifiable, Equatable {
        let account: String
        let email: String?
        let missing: [Missing]
        var id: String { account }
    }

    /// An account connected less than three hours ago: Drive is still building it (its folder is made on connecting).
    nonisolated static func isNew(_ account: String, now: Date = Date()) -> Bool {
        let created = (try? support.appendingPathComponent(account).resourceValues(forKeys: [.creationDateKey]))?.creationDate
        return created.map { now.timeIntervalSince($0) < 3 * 3600 } ?? true
    }

    /// The drives Finder shows less of than Drive has: at least 3 items and a tenth of the drive. Drives Drive has not
    /// loaded yet (0 items in its database) and Finder listings that did not finish are left out.
    nonisolated static func gaps(account: String, email: String?, drive: [String: Int], finder: [String: Int?]) -> [Missing] {
        drive.compactMap { name, inDrive in
            guard inDrive > 0, let listed = finder[name], let inFinder = listed else { return nil }
            let gap = inDrive - inFinder
            return gap >= 3 && Double(gap) >= Double(inDrive) * 0.1
                ? Missing(account: account, email: email, drive: name, inDrive: inDrive, inFinder: inFinder) : nil
        }.sorted { $0.gap > $1.gap }
    }

    /// Items at the top of My Drive and each shared drive, in Drive's database (read only, as Drive keeps writing it).
    /// A database Drive keeps locked (not in WAL mode, as the Gmail one on 2026-11-03) is read as immutable instead: no
    /// locks, so it may be a moment behind, which is fine for counting.
    nonisolated static func driveCounts(account: String) -> [String: Int] {
        let path = support.appendingPathComponent("\(account)/metadata_sqlite_db").path
        return counts(at: "file:\(path)?mode=ro") ?? counts(at: "file:\(path)?mode=ro&immutable=1") ?? [:]
    }

    nonisolated static func counts(at uri: String) -> [String: Int]? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 3000)
        let sql = """
            SELECT r.local_title, (SELECT count(*) FROM stable_parents p JOIN items i ON i.stable_id = p.item_stable_id
                                    WHERE p.parent_stable_id = r.stable_id AND i.trashed = 0 AND i.is_tombstone = 0)
            FROM items r WHERE r.is_folder = 1 AND r.trashed = 0 AND r.is_tombstone = 0
              AND r.stable_id NOT IN (SELECT item_stable_id FROM stable_parents)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        var counts: [String: Int] = [:]
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { return nil }
            guard let title = sqlite3_column_text(statement, 0) else { continue }
            counts[String(cString: title)] = Int(sqlite3_column_int64(statement, 1))
        }
        return counts
    }

    /// Items Finder lists in a folder (hidden ones aside), in a separate process with a time limit like `answers`: nil
    /// when it does not finish.
    nonisolated static func finderCount(_ folder: URL) -> Int? {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("bo-ls-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: out) }
        guard let handle = try? FileHandle(forWritingTo: out) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ls"); process.arguments = [folder.path]
        process.standardOutput = handle; process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        guard (try? process.run()) != nil else { return nil }
        let finished = done.wait(timeout: .now() + 20) == .success
        if process.isRunning { process.terminate() }
        try? handle.close()
        guard finished, process.terminationStatus == 0, let text = try? String(contentsOf: out, encoding: .utf8) else { return nil }
        return text.split(separator: "\n").filter { !$0.hasPrefix(".") }.count
    }

    /// Each connected account's drives compared, Drive's database against Finder; accounts still being built are left out.
    nonisolated static func compareFinder(emails: [String: String]) -> [Missing] {
        let cloud = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage")
        var missing: [Missing] = []
        for (account, email) in emails where !isNew(account) {
            let root = cloud.appendingPathComponent("GoogleDrive-\(email)")
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let drive = driveCounts(account: account)
            var finder: [String: Int?] = [:]
            for name in drive.keys where drive[name, default: 0] > 0 {
                finder[name] = finderCount(name == "My Drive" ? root.appendingPathComponent("My Drive")
                                                              : root.appendingPathComponent("Shared drives").appendingPathComponent(name))
            }
            missing += gaps(account: account, email: email, drive: drive, finder: finder)
        }
        return missing
    }

    /// A gap that has lasted 15 minutes without closing asks for a rebuild, unless you said not now.
    private func compared(_ found: [Missing]) {
        finderMissing = found
        let now = Date()
        gapSince = found.reduce(into: [:]) { kept, gap in
            let before = gapSince[gap.id]
            kept[gap.id] = before.map { $0.missing <= gap.gap ? $0 : (now, gap.gap) } ?? (now, gap.gap)
        }
        let lasting = found.filter { gap in gapSince[gap.id].map { now.timeIntervalSince($0.time) >= 900 } ?? false }
        guard reconnect == nil, holdUntil == nil, let first = lasting.first,
              (UserDefaults.standard.object(forKey: "boReconnectLater") as? Date).map({ now > $0 }) ?? true else { return }
        let account = lasting.filter { $0.account == first.account }
        reconnect = Reconnect(account: first.account, email: first.email, missing: account)
        note("Finder is missing \(account.reduce(0) { $0 + $1.gap }) items Google Drive has in \(first.email ?? first.account): asked you to reconnect it")
    }

    /// You are disconnecting and reconnecting: Google Drive opens, and Bo leaves it alone for three hours.
    func reconnecting() {
        reconnect = nil
        let until = Date().addingTimeInterval(3 * 3600)
        holdUntil = until; UserDefaults.standard.set(until, forKey: "boHoldUntil")
        gapSince = [:]
        note("Waiting while you reconnect Google Drive (until \(until.formatted(date: .omitted, time: .shortened)))")
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// From the stuck-disconnect dialog: restarts Google Drive now, whatever the hold, so you can try the disconnect again.
    func restartForDisconnect() {
        disconnectStuck = nil
        restart(because: "you asked, its disconnect was stuck")
    }

    /// Wait longer: asked again in ten minutes if it has still not moved.
    func disconnectWait() {
        disconnectStuck = nil
        UserDefaults.standard.set(Date().addingTimeInterval(600), forKey: "boDisconnectLater")
    }

    /// Not now: asked again in six hours if the gap is still there.
    func reconnectLater() {
        reconnect = nil
        UserDefaults.standard.set(Date().addingTimeInterval(6 * 3600), forKey: "boReconnectLater")
    }

    func accountName(_ id: String) -> String {
        storage?.accounts.first { $0.id == id }?.name ?? Self.knownAccounts[id] ?? "Account …\(id.suffix(4))"
    }

    nonisolated static func duration(_ seconds: Int) -> String {
        seconds >= 5400 ? "\(Int((Double(seconds) / 3600).rounded())) hours" : seconds >= 120 ? "\(seconds / 60) minutes" : "\(seconds) seconds"
    }

    /// How long each account's changes have waited for Finder, from Drive's current log: "Slow working set change
    /// acknowledgment: N sec" while it waits, "Slow working set change acknowledged after N sec" once Finder took them.
    /// The latest of the two decides; still waiting, the wait goes on growing after Drive stops writing it (it went quiet
    /// for hours on 2026-11-03 with the changes still not taken).
    nonisolated static func finderLags(in text: String, now: Date) -> [String: Int] {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let pattern = try! NSRegularExpression(pattern: #"^(\S+Z)\S \[[^\]]*core_(\d+)\].*Slow working set change (acknowledgment: (\d+) sec|acknowledged after)"#,
                                               options: .anchorsMatchLines)
        var lags: [String: Int] = [:]
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let time = Range(match.range(at: 1), in: text).flatMap({ formatter.date(from: String(text[$0])) }),
                  let account = Range(match.range(at: 2), in: text).map({ String(text[$0]) }) else { continue }
            if let seconds = Range(match.range(at: 4), in: text).flatMap({ Int(text[$0]) }) {
                lags[account] = seconds + max(0, Int(now.timeIntervalSince(time)))
            } else {
                lags[account] = nil
            }
        }
        return lags
    }

    /// When Drive began quitting, if it did since it started: each launch writes a new log, so any such line is this run's.
    nonisolated static func quittingSince(in text: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for line in text.split(separator: "\n") where line.contains("StopAllAccounts with") && line.contains("initiated") || line.contains("Quit initiated") {
            if let z = line.firstIndex(of: "Z"), let time = formatter.date(from: String(line[...z])) { return time }
        }
        return nil
    }

    /// When Drive's settings were last on screen: its log writes each change to its windows ("preferences_dialog", the
    /// "Preparing to disconnect account" dialog) under the time of the line before.
    nonisolated static func settingsShown(in text: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var time: Date?, shown: Date?
        for line in text.split(separator: "\n") {
            if line.first == "2", let z = line.firstIndex(of: "Z"), let stamp = formatter.date(from: String(line[...z])) { time = stamp }
            if line.contains("preferences_dialog") || line.contains("disconnect account") || line.contains("Disconnect account") { shown = time ?? shown }
        }
        return shown
    }

    /// When Drive began showing "Preparing to disconnect account", if nothing in its windows has changed since: each change
    /// to them is a new "UpdateViewViaDifferencer" line, so a newer one means it moved on (done, cancelled, next step).
    nonisolated static func disconnectWaiting(in text: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var time: Date?, update: Date?, preparing: Date?
        for line in text.split(separator: "\n") {
            if line.first == "2", let z = line.firstIndex(of: "Z"), let stamp = formatter.date(from: String(line[...z])) {
                time = stamp
                if line.contains("UpdateViewViaDifferencer") { update = stamp }
            }
            if line.contains("Preparing to disconnect account") { preparing = update ?? time }
        }
        // Drive redraws the dialog a few times as it opens (twice within 0.15 s on 2026-11-03): only a change a minute
        // or more later means it moved on.
        guard let preparing, let update, update.timeIntervalSince(preparing) < 60 else { return nil }
        return preparing
    }

    /// Drive's current log, the whole of it since Drive started (the last confirmation can be hours back).
    nonisolated static func readDriveLog(now: Date = Date()) -> (lags: [String: Int], quitting: Date?, settings: Date?, disconnecting: Date?) {
        guard let handle = try? FileHandle(forReadingFrom: support.appendingPathComponent("Logs/drive_fs.txt")) else { return ([:], nil, nil, nil) }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 40_000_000 ? size - 40_000_000 : 0)
        let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        return (finderLags(in: text, now: now), quittingSince(in: text), settingsShown(in: text), disconnectWaiting(in: text))
    }

    // MARK: What Drive keeps on this Mac

    struct Storage: Equatable {
        struct Account: Identifiable, Equatable {
            /// Drive's number for the account, the name of its folder.
            let id: String
            let email: String?
            let bytes: Int64
            var name: String { email ?? "Account …\(id.suffix(4))" }
        }
        var accounts: [Account] = []
        var logBytes: Int64 = 0, logFiles = 0
        /// Files Drive could not upload and set aside in lost_and_found.
        var unuploadedFiles = 0, unuploadedBytes: Int64 = 0
        var free: Int64?
        var cacheBytes: Int64 { accounts.reduce(0) { $0 + $1.bytes } }
    }

    nonisolated static let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/DriveFS")

    /// Times Bo restarted Google Drive, kept across launches.
    static var restarts: [Double] { UserDefaults.standard.array(forKey: "boRestarts") as? [Double] ?? [] }
    /// Keeps the last 50. An Array, not the slice suffix gives: UserDefaults takes only property lists, and a slice
    /// crashed the app on every launch (2026-11-03).
    static func recordRestart(at time: Date = Date()) {
        UserDefaults.standard.set(Array((restarts + [time.timeIntervalSince1970]).suffix(50)), forKey: "boRestarts")
    }
        var restartsToday: Int { Self.restarts.filter { Date().timeIntervalSince1970 - $0 < 86_400 }.count }
    /// Account emails by Drive's number, remembered: they are only in the log, and logs are replaced.
    static var knownAccounts: [String: String] { UserDefaults.standard.dictionary(forKey: "boAccounts") as? [String: String] ?? [:] }

    private func measured(_ found: Storage) {
        storage = found
        var known = Self.knownAccounts
        for account in found.accounts { if let email = account.email { known[account.id] = email } }
        UserDefaults.standard.set(known, forKey: "boAccounts")
        // One sample a day, a month kept: the growth shown is over the last week.
        var samples = (UserDefaults.standard.array(forKey: "boCacheSamples") as? [[Double]] ?? []).filter { $0.count == 2 }
        let now = Date().timeIntervalSince1970
        if samples.last.map({ now - $0[0] > 86_400 }) ?? true { samples.append([now, Double(found.cacheBytes)]) }
        samples = Array(samples.suffix(30))
        UserDefaults.standard.set(samples, forKey: "boCacheSamples")
        if let first = samples.first(where: { now - $0[0] <= 7 * 86_400 }) {
            cacheGrowth = (found.cacheBytes - Int64(first[1]), Date(timeIntervalSince1970: first[0]))
        }
    }

    /// Sizes of Drive's folders. Only Application Support is read, never the drives themselves: walking a drive can
    /// download files or hang.
    nonisolated static func measure(known: [String: String]) -> Storage {
        let files = FileManager.default
        var storage = Storage()
        let emails = known.merging(accountEmails()) { $1 }
        let folders = (try? files.contentsOfDirectory(at: support, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for folder in folders where folder.lastPathComponent.allSatisfy(\.isNumber) && folder.lastPathComponent.count > 10 {
            storage.accounts.append(.init(id: folder.lastPathComponent, email: emails[folder.lastPathComponent], bytes: size(of: folder).bytes))
        }
        storage.accounts.sort { $0.bytes > $1.bytes }
        (storage.logBytes, storage.logFiles) = size(of: support.appendingPathComponent("Logs"))
        (storage.unuploadedBytes, storage.unuploadedFiles) = size(of: support.appendingPathComponent("lost_and_found"))
        storage.free = (try? files.homeDirectoryForCurrentUser.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        return storage
    }

    nonisolated static func size(of folder: URL) -> (bytes: Int64, files: Int) {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) else { return (0, 0) }
        var bytes: Int64 = 0, count = 0
        for case let url as URL in walk {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            bytes += Int64(values.totalFileAllocatedSize ?? 0); count += 1
        }
        return (bytes, count)
    }

    /// "id: gdrive-<number>, displayName: <email>," in the current log, written when Drive starts.
    nonisolated static func accountEmails() -> [String: String] {
        guard let handle = try? FileHandle(forReadingFrom: support.appendingPathComponent("Logs/drive_fs.txt")) else { return [:] }
        defer { try? handle.close() }
        let text = String(decoding: (try? handle.read(upToCount: 6_000_000)) ?? Data(), as: UTF8.self)
        var found: [String: String] = [:]
        let pattern = try! NSRegularExpression(pattern: #"id: gdrive-(\d+), displayName: ([^,\s]+@[^,\s]+),"#)
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let id = Range(match.range(at: 1), in: text), let email = Range(match.range(at: 2), in: text) { found[String(text[id])] = String(text[email]) }
        }
        return found
    }

    /// When clearing something is worth it. Google gives no sizes, so these are Bo's: a cache over 2 GB, Drive stuck
    /// three times in a day (a fresh cache usually ends that), or the Mac short of room.
    enum Advice: Identifiable, Equatable {
        enum Reason: Equatable { case big, stuck(Int), lowSpace }
        case clearCache(Storage.Account, Reason)
        case oldLogs(bytes: Int64, files: Int)
        case unuploaded(files: Int, bytes: Int64)
        case lowSpace(free: Int64)
        var id: String {
            switch self {
            case .clearCache(let account, _): "cache-\(account.id)"
            case .oldLogs: "logs"
            case .unuploaded: "unuploaded"
            case .lowSpace: "space"
            }
        }
    }
    nonisolated static let cacheLimit: Int64 = 2_000_000_000, logLimit: Int64 = 500_000_000, lowSpace: Int64 = 20_000_000_000

    nonisolated static func advice(_ storage: Storage, restartsToday: Int) -> [Advice] {
        var advice: [Advice] = []
        let short = storage.free.map { $0 < lowSpace } ?? false
        for account in storage.accounts {
            if account.bytes > cacheLimit { advice.append(.clearCache(account, .big)) }
            else if restartsToday >= 3, account == storage.accounts.first { advice.append(.clearCache(account, .stuck(restartsToday))) }
            else if short, account.bytes > 500_000_000 { advice.append(.clearCache(account, .lowSpace)) }
        }
        if storage.unuploadedFiles > 0 { advice.append(.unuploaded(files: storage.unuploadedFiles, bytes: storage.unuploadedBytes)) }
        if storage.logBytes > logLimit { advice.append(.oldLogs(bytes: storage.logBytes, files: storage.logFiles)) }
        if short, let free = storage.free { advice.append(.lowSpace(free: free)) }
        return advice
    }
    var advice: [Advice] { storage.map { Self.advice($0, restartsToday: restartsToday) } ?? [] }

    // MARK: Errors in Drive's log, by kind

    enum ErrorKind: String, CaseIterable, Identifiable {
        case connection, server, access, sync, mac, crash, noise
        var id: String { rawValue }
    }
    struct ErrorCount: Identifiable, Equatable {
        let kind: ErrorKind
        var day = 0, hour = 0
        var last: Date?
        /// The newest such line, without its time.
        var example = ""
        var id: ErrorKind { kind }
    }

    /// What an error line is about, from its words; nil for the request headers Drive writes under a failed request.
    nonisolated static func kind(of message: Substring) -> ErrorKind? {
        let text = message.lowercased()
        func any(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        if text.contains("dumptolog") {
            // One line per failed request carries its status; the lines after it are its headers.
            guard let range = text.range(of: #"request 0x[0-9a-f]+: \d{3}"#, options: .regularExpression),
                  let code = Int(text[range].suffix(3)) else { return nil }
            return code == 429 || code >= 500 ? .server : code == 401 || code == 403 ? .access : nil
        }
        if any(["crash report", "crashpad"]) { return .crash }
        // Drive reporting its own usage to Google (clearcut, metrics) or fetching its own settings (phenotype, feature
        // config): not your files, whatever words it uses ("Failed to sync").
        if any(["clearcut", "metrics", "phenotype", "feature_config"]) { return .noise }
        if any(["offline", "network", "timeout", "too slow", "couldn’t connect", "couldn't connect", "failed to send request", "curl code",
                "broken pipe", "connection reset", "could not resolve"]) { return .connection }
        if any(["unauthenticated", "permission_denied", "permission denied", "access denied", "forbidden", "hidden shared drive",
                "invalid_grant", "invalid credentials", "sign in again"]) { return .access }
        if any(["upload", "conflict", "quota", "storage limit", "out of space", "no space left", "lost_and_found", "lost and found",
                "failed to sync", "sync error"]) { return .sync }
        if any(["nsfileprovider", "file_provider", "fileprovider", "nscocoaerror", "operation not permitted"]) { return .mac }
        return .noise
    }

    /// Counts error lines ("2026-11-03T01:48:43.787ZE [thread] file.cc:12:Function message") of the last 24 hours.
    nonisolated static func countErrors(in text: String, now: Date, into counts: inout [ErrorKind: ErrorCount]) {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for line in text.split(separator: "\n") {
            guard line.count > 26, let z = line.firstIndex(of: "Z"), line.index(after: z) < line.endIndex, line[line.index(after: z)] == "E",
                  let time = formatter.date(from: String(line[...z])), now.timeIntervalSince(time) < 86_400, time <= now.addingTimeInterval(60) else { continue }
            let message = line[line.index(z, offsetBy: 2)...]
            guard let kind = kind(of: message) else { continue }
            var count = counts[kind] ?? ErrorCount(kind: kind)
            count.day += 1
            if now.timeIntervalSince(time) < 3600 { count.hour += 1 }
            if count.last.map({ time >= $0 }) ?? true {
                count.last = time
                // Without the thread: "[123:core_456] file.cc:12:Function message" reads as "file.cc:12:Function message".
                let words = message.drop { $0 != "]" }.dropFirst().drop { $0 == " " }
                count.example = String((words.isEmpty ? message : words).prefix(300))
            }
            counts[kind] = count
        }
    }

    /// The last day of Drive's logs: the current one and any replaced in that time (Drive starts a new one each launch).
    nonisolated static func readErrors(now: Date = Date()) -> [ErrorCount] {
        let logs = support.appendingPathComponent("Logs")
        let files = ((try? FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []).filter {
            $0.lastPathComponent.hasPrefix("drive_fs") && $0.pathExtension == "txt"
                && ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).flatMap { $0 }.map { now.timeIntervalSince($0) < 86_400 } ?? false)
        }
        var counts: [ErrorKind: ErrorCount] = [:]
        for file in files {
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 8_000_000 ? size - 8_000_000 : 0)
            countErrors(in: String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self), now: now, into: &counts)
            try? handle.close()
        }
        return ErrorKind.allCases.map { counts[$0] ?? ErrorCount(kind: $0) }
    }
}
