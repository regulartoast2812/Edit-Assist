import AppKit
import Foundation

/// Bo keeps Google Drive for Desktop syncing: every minute he checks that it is running and that each account's drive
/// answers, and restarts Google Drive himself when it is stuck (2026-11-03, asked for as a constant job, restarting on
/// his own). Only two signs count: Google Drive not running, and a drive that does not answer a listing within 15 s
/// for three minutes running. Errors in Drive's own log are shown, never acted on: it holds hundreds of harmless ones.
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
    private static let answerWithin: TimeInterval = 15, stuckFor: TimeInterval = 180, restartsApart: TimeInterval = 1800

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
            let storage = measure ? Self.measure(known: known) : nil
            await MainActor.run { self?.finish(results, errors: errors, storage: storage) }
        }
    }

    private func finish(_ results: [(URL, Bool, Int)], errors: [ErrorCount], storage: Storage?) {
        checking = false
        lastCheck = Date()
        self.errors = errors
        if let storage { measured(storage) }
        drives = results.map { Drive(url: $0.0, answered: $0.1, milliseconds: $0.2) }
        if !running {
            // Not running at all: open it, at most once every half hour (you may have quit it on purpose just now).
            if lastRestart.map({ Date().timeIntervalSince($0) > Self.restartsApart }) ?? true { open(because: "Google Drive was not running") }
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

    /// Quits Google Drive (forced after 20 s), then opens it again.
    private func restart(because reason: String) {
        lastRestart = Date(); stuckSince = nil
        UserDefaults.standard.set((Self.restarts + [Date().timeIntervalSince1970]).suffix(50), forKey: "boRestarts")
        busyUntil = Date().addingTimeInterval(25)
        note("Restarting Google Drive: \(reason)")
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
        apps.forEach { $0.terminate() }
        Task { @MainActor in
            for _ in 0 ..< 40 where apps.contains(where: { !$0.isTerminated }) { try? await Task.sleep(for: .milliseconds(500)) }
            apps.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
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
