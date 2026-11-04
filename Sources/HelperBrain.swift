import AppKit
import Foundation
import Security

/// What Don and Pix think with: a CLI already signed in on this Mac, Claude by default and Codex (OpenAI's) as the
/// backup you can switch to (2026-11-04). Highlight runs keep their own Assistant CLI setting; nothing here sends
/// desktop input. Each question is one call with no tools, answered as one JSON object matching a schema.
enum HelperBrain {
    static let providers: [CLIProvider] = [.claude, .codex]
    static var provider: CLIProvider {
        get { UserDefaults.standard.string(forKey: "helperBrain").flatMap(CLIProvider.init(rawValue:)).flatMap { providers.contains($0) ? $0 : nil } ?? .claude }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "helperBrain") }
    }

    /// Asks once and returns the answer's JSON object. Pictures are sent as JPEGs no longer than 1568 px.
    static func ask(_ prompt: String, schema: [String: Any], pictures: [URL] = [], timeout: TimeInterval = 180) async throws -> [String: Any] {
        let provider = provider
        guard let executable = provider.executable else {
            throw AssistError.message(L("%@ CLI is not installed. Choose the other one in the chat, or install it.", provider.rawValue))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("edit-assist-helper-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let schemaData = try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        let schemaPath = directory.appendingPathComponent("schema.json")
        try schemaData.write(to: schemaPath)
        var images: [(URL, Data)] = []
        for (index, picture) in pictures.prefix(8).enumerated() {
            guard let jpeg = jpeg(picture) else { continue }
            let url = directory.appendingPathComponent("picture-\(index + 1).jpg")
            try jpeg.write(to: url)
            images.append((url, jpeg))
        }
        let text = prompt + "\nDo not use tools, run commands or change files. Return only one JSON object matching this schema: "
            + String(decoding: schemaData, as: UTF8.self)
            + (images.isEmpty ? "" : "\nThe pictures attached, in order: " + images.map(\.0.lastPathComponent).joined(separator: ", "))
        var request: CLIRequest
        switch provider {
        case .codex:
            let output = directory.appendingPathComponent("answer.json")
            var args = ["exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--color", "never",
                        "-c", "features.shell_tool=false", "-c", "web_search=\"disabled\"", "--output-schema", schemaPath.path, "--output-last-message", output.path]
            for (url, _) in images { args += ["--image", url.path] }
            request = CLIRequest(executable: executable, arguments: args + ["-"], input: Data(text.utf8), outputFile: output)
        default:
            var content: [[String: Any]] = [["type": "text", "text": text]]
            for (url, data) in images {
                content += [["type": "text", "text": url.lastPathComponent],
                            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()]]]
            }
            var input = try JSONSerialization.data(withJSONObject: ["type": "user", "message": ["role": "user", "content": content]])
            input.append(10)
            request = CLIRequest(executable: executable, arguments: ["--print", "--safe-mode", "--tools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
                                                                   "--no-session-persistence", "--input-format", "stream-json", "--output-format", "stream-json",
                                                                   "--verbose", "--json-schema", String(decoding: schemaData, as: UTF8.self)], input: input)
        }
        let data = try await CLIProcess.run(request, directory: directory, timeout: timeout)
        return try answer(data, provider: provider)
    }

    /// The JSON object in a CLI's output: Claude's result event (structured, or its text), Codex's last message.
    static func answer(_ data: Data, provider: CLIProvider) throws -> [String: Any] {
        var payload = data
        if provider == .claude {
            let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                ?? String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap {
                    (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
                }.last { $0["type"] as? String == "result" }
            guard let result, result["is_error"] as? Bool != true else {
                throw AssistError.message(L("Claude CLI could not answer. Check its sign-in or usage limits in Terminal."))
            }
            if let structured = result["structured_output"] as? [String: Any] { return structured }
            guard let text = result["result"] as? String else { throw AssistError.message(L("Claude returned no answer.")) }
            payload = Data(CLIClient.unfence(text).utf8)
        } else {
            payload = Data(CLIClient.unfence(String(decoding: data, as: UTF8.self)).utf8)
        }
        guard let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else {
            throw AssistError.message(L("%@ answered with something that is not JSON.", provider.rawValue))
        }
        return object
    }

    /// A picture as a JPEG for the CLI, its long edge at most 1568 px.
    static func jpeg(_ url: URL, longest: CGFloat = 1568) -> Data? {
        guard let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, longest / CGFloat(max(cg.width, cg.height)))
        let width = Int(CGFloat(cg.width) * scale), height = Int(CGFloat(cg.height) * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(.white); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    /// A strict object schema (Codex wants every property required and nothing else allowed).
    static func object(_ properties: [String: Any]) -> [String: Any] {
        ["type": "object", "additionalProperties": false, "required": properties.keys.sorted(), "properties": properties]
    }
    static let string: [String: Any] = ["type": "string"]
}

/// Pix's pictures and schematics, made with OpenAI's GPT Image on your API key (kept in the Keychain, never in
/// UserDefaults or projects.json). Every picture costs OpenAI credit, so one is made only for a job you queued.
enum OpenAIImages {
    static let base = URL(string: "https://api.openai.com/v1/")!
    private static let service = "Edit Assist OpenAI"

    /// The API key in the login Keychain; nil removes it.
    static var key: String? {
        get {
            var result: AnyObject?
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecAttrAccount as String: "api-key", kSecReturnData as String: true]
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecAttrAccount as String: "api-key"]
            SecItemDelete(query as CFDictionary)
            guard let newValue, let data = newValue.data(using: .utf8) else { return }
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    /// The newest full GPT Image model the key can use ("gpt-image-1.5" over "gpt-image-1"; never a mini), or nil.
    static func newestModel(in data: Data) -> String? {
        let ids = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["data"] as? [[String: Any]] ?? []
        let version = { (id: String) -> [Int]? in
            guard id.hasPrefix("gpt-image-") else { return nil }
            let parts = id.dropFirst("gpt-image-".count).split(separator: ".").map { Int($0) }
            return parts.contains(nil) || parts.isEmpty ? nil : parts.compactMap { $0 }
        }
        return ids.compactMap { $0["id"] as? String }.filter { version($0) != nil }
            .max { version($0)!.lexicographicallyPrecedes(version($1)!) }
    }

    /// Checks the key and finds the model to use; throws OpenAI's reason for a refused key.
    static func model(key: String) async throws -> String {
        var request = URLRequest(url: base.appendingPathComponent("models"), timeoutInterval: 20)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        return newestModel(in: data) ?? "gpt-image-1"
    }

    /// One picture as PNG data: from the reference pictures when there are any (edits), else from the words alone.
    static func make(prompt: String, pictures: [URL], size: String, model: String, key: String, fidelity: Bool = true) async throws -> Data {
        var request: URLRequest
        if pictures.isEmpty {
            request = URLRequest(url: base.appendingPathComponent("images/generations"), timeoutInterval: 300)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "prompt": prompt, "size": size, "quality": "high", "n": 1])
        } else {
            request = URLRequest(url: base.appendingPathComponent("images/edits"), timeoutInterval: 300)
            let boundary = "EditAssist-" + UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            func field(_ name: String, _ value: String) {
                body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
            }
            for (name, value) in [("model", model), ("prompt", prompt), ("size", size), ("quality", "high"), ("n", "1")] { field(name, value) }
            if fidelity { field("input_fidelity", "high") }
            for (index, picture) in pictures.prefix(16).enumerated() {
                guard let jpeg = HelperBrain.jpeg(picture, longest: 2048) else { continue }
                body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image[]\"; filename=\"picture-\(index + 1).jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
                body.append(jpeg); body.append(Data("\r\n".utf8))
            }
            body.append(Data("--\(boundary)--\r\n".utf8))
            request.httpBody = body
        }
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Not every GPT Image model takes input_fidelity: asked again without it.
        if status == 400, fidelity, !pictures.isEmpty, message(in: data)?.contains("input_fidelity") == true {
            return try await make(prompt: prompt, pictures: pictures, size: size, model: model, key: key, fidelity: false)
        }
        try check(status, data)
        return try png(from: data)
    }

    /// The picture in an images answer (GPT Image always answers in base64).
    static func png(from data: Data) throws -> Data {
        guard let first = (((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["data"] as? [[String: Any]])?.first,
              let encoded = first["b64_json"] as? String, let picture = Data(base64Encoded: encoded) else {
            throw AssistError.message(L("OpenAI answered without a picture."))
        }
        return picture
    }

    static func check(_ status: Int, _ data: Data) throws {
        guard !(200 ..< 300).contains(status) else { return }
        let reason = message(in: data) ?? "HTTP \(status)"
        throw AssistError.message(status == 401 ? L("OpenAI did not accept the key: %@", reason) : L("OpenAI: %@", reason))
    }

    static func message(in data: Data) -> String? {
        (((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
    }
}
