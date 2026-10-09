import Foundation
import Darwin

enum CLIProvider: String, CaseIterable, Identifiable {
    case codex = "Codex", claude = "Claude", antigravity = "Antigravity"
    var id: String { rawValue }
    /// The Antigravity CLI installs its binary as `agy`.
    var command: String { self == .antigravity ? "agy" : rawValue.lowercased() }
    static var savedDefault: String {
        let saved = UserDefaults.standard.string(forKey: "cliProvider") ?? "Codex"
        if let known = CLIProvider(rawValue: saved) { return known.rawValue }
        // Gemini was replaced by Antigravity, but Antigravity needs a tool call per image and runs
        // about 30s a step against Claude's 8s, so a never-configured user gets the fastest installed
        // provider instead. Antigravity stays one click away in Assistant CLI.
        for candidate in [CLIProvider.claude, .codex, .antigravity] where candidate.executable != nil {
            return candidate.rawValue
        }
        return CLIProvider.claude.rawValue
    }
    static var searchPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", ProcessInfo.processInfo.environment["PATH"] ?? ""].joined(separator: ":")
    }
    var executable: URL? {
        for directory in Self.searchPath.split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory)).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: path.path) { return path }
        }
        return nil
    }
    /// Measured on this machine with one screenshot per decision.
    var speedNote: String {
        switch self {
        case .codex: return "Fast. Images are attached directly, so extra screenshots cost little."
        case .claude: return "Fastest measured here, about 8-10s a step, and unaffected by how many screenshots you send."
        case .antigravity: return "Slowest for this app: it cannot take images inline, so it opens each screenshot with a tool call first. Roughly 30s a step on the default model, about 11s on gemini-3.8-flash-low."
        }
    }
    var fastestModel: String? { self == .antigravity ? "gemini-3.8-flash-low" : nil }
    var loginHint: String {
        switch self {
        case .codex: return "codex login"
        case .claude: return "claude auth login"
        case .antigravity: return "agy"
        }
    }
}

struct CLIRequest {
    var executable: URL
    var arguments: [String]
    var input: Data
    var outputFile: URL?
    var environment: [String: String] = [:]
}

enum CLIClient {
    static func prepare(settings: AISettings, context: String, screenshot: Data?, previous: Data?, style: Data?, directory: URL, attachments: [Data] = []) throws -> CLIRequest {
        guard let provider = CLIProvider(rawValue: settings.provider), let executable = provider.executable else {
            throw AssistError.message("\(settings.provider) CLI is not installed or could not be found.")
        }
        let schemaData = try JSONSerialization.data(withJSONObject: AIClient.schema, options: [.sortedKeys])
        let schema = String(decoding: schemaData, as: UTF8.self)
        let schemaPath = directory.appendingPathComponent("decision-schema.json")
        try schemaData.write(to: schemaPath)
        var images: [(String, URL, Data)] = []
        for (name, image) in [("style-reference", style), ("previous-observation", previous), ("latest-observation", screenshot)] {
            if let image {
                let url = directory.appendingPathComponent(name + ".png")
                try image.write(to: url)
                images.append((name, url, image))
            }
        }
        for (index, image) in attachments.prefix(4).enumerated() {
            let name = "user-reference-\(index + 1)"
            let url = directory.appendingPathComponent(name + ".png")
            try image.write(to: url)
            images.append((name, url, image))
        }
        // Antigravity cannot receive images inline, so it is allowed exactly one tool to read them.
        let toolClause = provider == .antigravity
            ? "Use the view_file tool only, and only to view the image files listed below. Never run commands, write files, browse the web, or read anything else."
            : "Do not use tools, execute commands, or change files."
        let prompt = WorkflowPrompt.system + "\n" + toolClause + " Return only one JSON object matching this schema: " + schema + "\n" + context + "\nImage order: " + images.map(\.0).joined(separator: ", ")
        // Antigravity's CLI default is a heavy reasoning model: measured at 28-61s a step against
        // 11s for the flash model, which is the difference between usable and not for one click.
        var model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty, let fast = provider.fastestModel { model = fast }
        var args: [String]
        var input = Data(prompt.utf8)
        var output: URL?
        var environment: [String: String] = [:]
        switch provider {
        case .codex:
            output = directory.appendingPathComponent("decision.json")
            args = ["exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--color", "never", "-c", "features.shell_tool=false", "-c", "web_search=\"disabled\"", "--output-schema", schemaPath.path, "--output-last-message", output!.path]
            if !model.isEmpty { args += ["--model", model] }
            for (_, url, _) in images { args += ["--image", url.path] }
            args += ["-"]
        case .claude:
            args = ["--print", "--safe-mode", "--tools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}", "--no-session-persistence", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--json-schema", schema]
            if !model.isEmpty { args += ["--model", model] }
            var content: [[String: Any]] = [["type": "text", "text": prompt]]
            for (name, _, data) in images {
                content += [["type": "text", "text": name], ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": data.base64EncodedString()]]]
            }
            input = try JSONSerialization.data(withJSONObject: ["type": "user", "message": ["role": "user", "content": content]])
            input.append(10)
        case .antigravity:
            // stream-json takes text blocks only, so images are written beside the request and
            // read with view_file. The prompt travels on stdin, which has no argument-size limit.
            let dataDirectory = directory.appendingPathComponent("antigravity-data", isDirectory: true)
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            let settings: [String: Any] = ["permissions": ["allow": ["view_file(*)"]]]
            try JSONSerialization.data(withJSONObject: settings).write(to: dataDirectory.appendingPathComponent("settings.json"))
            let listing = images.map { "\($0.0) -> \($0.1.lastPathComponent)" }.joined(separator: "\n")
            let viewing = images.isEmpty ? "" : "\nView each of these image files in the working directory before deciding, in this order:\n" + listing
            args = ["--print=", "--input-format", "stream-json", "--output-format", "stream-json",
                    "--json-schema", schemaPath.path, "--disable-slash-commands"]
            if !model.isEmpty { args += ["--model", model] }
            let message: [String: Any] = ["event": "user", "message": ["role": "user",
                "content": [["type": "text", "text": prompt + viewing]]]]
            input = try JSONSerialization.data(withJSONObject: message)
            input.append(10)
            // Keep the request's permissions local; the user's own CLI settings are never touched.
            environment["ANTIGRAVITY_EXECUTABLE_DATA_DIR"] = dataDirectory.path
        }
        return CLIRequest(executable: executable, arguments: args, input: input, outputFile: output, environment: environment)
    }

    static func decode(_ data: Data, provider: String) throws -> Decision {
        var envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if provider == "Claude", envelope == nil {
            envelope = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap {
                (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
            }.last { $0["type"] as? String == "result" }
        }
        var payload = data
        if provider == "Claude" {
            guard envelope?["is_error"] as? Bool != true else { throw AssistError.message("Claude CLI could not complete the request. Check its login or usage limits in Terminal.") }
            if let structured = envelope?["structured_output"] as? [String: Any] {
                payload = try JSONSerialization.data(withJSONObject: structured)
            } else if let result = envelope?["result"] as? String { payload = Data(unfence(result).utf8) }
            else { throw AssistError.message("Claude returned no structured decision.") }
        } else if provider == "Antigravity" {
            // stream-json prints one NDJSON event per line; plain json prints the result object alone.
            var result = envelope
            if let final = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap({
                (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
            }).last(where: { $0["event"] as? String == "result" })?["result"] as? [String: Any] {
                result = final
            }
            guard let result, result["error"] == nil, (result["status"] as? String) != "ERROR" else {
                throw AssistError.message("Antigravity CLI could not complete the request. Check its login or usage limits in Terminal.")
            }
            if let structured = result["structured_output"] as? [String: Any] {
                payload = try JSONSerialization.data(withJSONObject: structured)
            } else if let response = result["response"] as? String, !response.isEmpty {
                payload = Data(unfence(response).utf8)
            } else {
                let denied = (result["denied_actions"] as? [[String: Any]])?.compactMap { $0["action"] as? String } ?? []
                throw AssistError.message(denied.isEmpty
                    ? "Antigravity returned no structured decision."
                    : "Antigravity needed tools that Edit Assist does not allow (\(denied.joined(separator: ", "))). No desktop action was sent.")
            }
        }
        let decision = try JSONDecoder().decode(Decision.self, from: payload)
        try ActionPolicy.validate(decision.action)
        guard decision.confidence.isFinite, (0...1).contains(decision.confidence) else { throw AssistError.message("Invalid model confidence.") }
        return decision
    }

    static func unfence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: "\n")
        guard lines.count > 2 else { return trimmed }
        lines.removeFirst(); lines.removeLast()
        return lines.joined(separator: "\n")
    }

    static func decide(settings: AISettings, context: String, screenshot: Data?, previous: Data?, style: Data?, attachments: [Data] = []) async throws -> Decision {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("edit-assist-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = try prepare(settings: settings, context: context, screenshot: screenshot, previous: previous, style: style, directory: directory, attachments: attachments)
        // A healthy step is 8-30s; a wedged one should surface quickly, not after two and a half minutes.
        let result = try await CLIProcess.run(request, directory: directory, timeout: 75)
        try Task.checkCancellation()
        return try decode(result, provider: settings.provider)
    }
}

enum CLIProcess {
    static func loginRequired(_ text: String) -> Bool {
        text.contains("Opening authentication page in your browser. Do you want to continue?") ||
        text.contains("\"error\":\"authentication_failed\"") ||
        text.contains("Not logged in · Please run /login")
    }
    static func loginError(_ executable: URL) -> AssistError {
        let provider = CLIProvider.allCases.first { $0.command == executable.lastPathComponent }
        return .message("\(provider?.rawValue ?? executable.lastPathComponent) CLI needs sign-in. Run ‘\(provider?.loginHint ?? executable.lastPathComponent)’ in Terminal, then retry. No API key is needed in Edit Assist.")
    }
    static func run(_ request: CLIRequest, directory: URL, timeout: TimeInterval) async throws -> Data {
        let input = directory.appendingPathComponent("stdin")
        let output = directory.appendingPathComponent("stdout")
        let errors = directory.appendingPathComponent("stderr")
        try request.input.write(to: input)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let stdin = try FileHandle(forReadingFrom: input)
        let stdout = try FileHandle(forWritingTo: output)
        let stderr = try FileHandle(forWritingTo: errors)
        defer { try? stdin.close(); try? stdout.close(); try? stderr.close() }
        let process = Process()
        let worker = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("CLIWorker")
        guard FileManager.default.isExecutableFile(atPath: worker.path) else { throw AssistError.message("The CLI worker is missing. Rebuild or reinstall Edit Assist.") }
        process.executableURL = worker
        process.arguments = [request.executable.path] + request.arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = CLIProvider.searchPath
        for (key, value) in request.environment { environment[key] = value }
        // Keep existing CLI authentication; don't inherit a parent agent's nesting marker.
        environment.removeValue(forKey: "CLAUDECODE")
        process.environment = environment
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
        try Task.checkCancellation()
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while process.isRunning {
                try Task.checkCancellation()
                if Date() >= deadline { throw AssistError.message("The CLI did not respond within \(Int(timeout)) seconds. Check its login and model in Terminal, then retry.") }
                for url in [output, errors] {
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    if size > 16_000_000 { throw AssistError.message("CLI output exceeded the response limit.") }
                    if size < 64_000, let text = try? String(contentsOf: url, encoding: .utf8), loginRequired(text) {
                        throw loginError(request.executable)
                    }
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            try Task.checkCancellation()
        } catch {
            let pid = process.processIdentifier
            if process.isRunning {
                if getpgid(pid) == pid { kill(-pid, SIGKILL) } else { kill(pid, SIGKILL) }
                // waitUntilExit can miss an exit that lands between these calls and block forever.
                let limit = Date().addingTimeInterval(2)
                while process.isRunning, Date() < limit { usleep(10_000) }
            }
            throw error
        }
        guard process.terminationStatus == 0 else {
            let diagnostic = ((try? String(contentsOf: output, encoding: .utf8)) ?? "") + ((try? String(contentsOf: errors, encoding: .utf8)) ?? "")
            if loginRequired(diagnostic) { throw loginError(request.executable) }
            // Never expose arbitrary CLI stderr, which can contain credentials or private configuration.
            throw AssistError.message("\(request.executable.lastPathComponent) CLI exited with code \(process.terminationStatus). Open that CLI in Terminal to check sign-in, model availability or usage limits. No desktop action was sent.")
        }
        let result = try Data(contentsOf: request.outputFile ?? output)
        guard !result.isEmpty else { throw AssistError.message("The CLI returned an empty decision.") }
        return result
    }
}
