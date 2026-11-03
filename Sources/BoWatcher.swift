import AppKit
import Foundation

/// Bo keeps Google Drive for Desktop syncing: every minute he checks that it is running and that each account's drive
/// answers, and restarts Google Drive himself when it is stuck (2026-11-03, asked for as a constant job, restarting on
/// his own). Only two signs count: Google Drive not running, and a drive that does not answer a listing within 15 s
/// for three minutes running. Errors in Drive's own log are shown, never acted on: it holds hundreds of harmless ones.
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
    @Published private(set) var logErrors = 0
    @Published private(set) var events: [Event] = []
    /// Bo moves while he checks or restarts.
    @Published private(set) var busyUntil: Date?
    /// Also written to the activity log.
    var onLog: ((String) -> Void)?
    private var timer: Timer?
    private var checking = false
    private var stuckSince: Date?
    private var lastRestart: Date?
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
        Task.detached(priority: .utility) { [weak self] in
            var results: [(URL, Bool, Int)] = []
            for root in roots { results.append(Self.answers(root)) }
            let errors = Self.recentLogErrors()
            await MainActor.run { self?.finish(results, errors: errors) }
        }
    }

    private func finish(_ results: [(URL, Bool, Int)], errors: Int) {
        checking = false
        lastCheck = Date()
        logErrors = errors
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

    /// Error lines in Google Drive's log in the last 15 minutes (lines start "2026-11-03T01:48:43.787ZE").
    nonisolated static func recentLogErrors() -> Int {
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/DriveFS/Logs/drive_fs.txt")
        guard let handle = try? FileHandle(forReadingFrom: log) else { return 0 }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 400_000 ? size - 400_000 : 0)
        guard let data = try? handle.readToEnd() else { return 0 }
        let since = Date().addingTimeInterval(-900)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return String(decoding: data, as: UTF8.self).split(separator: "\n").reduce(0) { count, line in
            guard line.count > 25, let z = line.firstIndex(of: "Z"), line.index(after: z) < line.endIndex, line[line.index(after: z)] == "E",
                  let time = formatter.date(from: String(line[...z])), time > since else { return count }
            return count + 1
        }
    }
}
