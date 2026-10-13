import Foundation

/// Finds newer builds of Edit Assist on GitHub and installs one with the same installer as the terminal
/// command. Each channel has a small file in the repository, updates/stable.json and updates/beta.json,
/// written by release.sh when it publishes: the version, its build number and where to download it.
/// A stable build follows the stable file; a beta build follows both, so testers also get a stable
/// release that is newer than their beta.
struct AvailableUpdate: Equatable {
    var version: String
    var build: Int
    var channel: String
    var label: String { channel == "beta" ? "\(version) beta (build \(build))" : version }
}

enum Updater {
    static let repo = "regulartoast2812/Edit-Assist"
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0 }
    static var channel: String { Bundle.main.infoDictionary?["EditAssistChannel"] as? String ?? "stable" }
    static var current: String { channel == "beta" ? "\(version) beta (build \(build))" : "\(version) (build \(build))" }

    /// The newest build on this app's channels, if it is newer than this one.
    static func check() async throws -> AvailableUpdate? {
        var found: [AvailableUpdate] = []
        for name in channel == "beta" ? ["stable", "beta"] : ["stable"] {
            // A query string past GitHub's raw-file cache, so a release shows up within moments.
            guard let url = URL(string: "https://raw.githubusercontent.com/\(repo)/main/updates/\(name).json?t=\(Int(Date().timeIntervalSince1970))") else { continue }
            var request = URLRequest(url: url); request.timeoutInterval = 15; request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let file = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = file["version"] as? String, let build = file["build"] as? Int else { continue }
            found.append(AvailableUpdate(version: version, build: build, channel: file["channel"] as? String ?? name))
        }
        return found.filter { $0.build > build }.max { $0.build < $1.build }
    }

    /// Runs install.sh (from the beta channel when the update is a beta) in the background: it downloads
    /// the release, quits this app, replaces it and opens the new one. Its output goes to a log.
    static func install(_ update: AvailableUpdate) throws {
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Edit Assist update.log")
        let flag = update.channel == "beta" ? " -s -- --beta" : ""
        let command = "curl -fsSL https://raw.githubusercontent.com/\(repo)/main/install.sh | bash\(flag) > '\(log.path)' 2>&1"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // Detached, so it carries on after it quits this app.
        process.arguments = ["-c", "nohup bash -c \"\(command)\" >/dev/null 2>&1 &"]
        try process.run()
        process.waitUntilExit()
    }
}
