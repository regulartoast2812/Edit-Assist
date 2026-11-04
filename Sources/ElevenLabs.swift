import AppKit
import AVFoundation
import Foundation
import Security

/// Tala's ElevenLabs account: the API key (in the Keychain, never in UserDefaults or projects.json), the plan and its
/// characters, the voices in the account's My Voices and the text-to-speech models, read when Tala's page opens, not on
/// launch. A voice-over is one MP3 per script, from Tala's copy of it with your audio tags, saved in a folder you pick
/// once; credits are spent only when you press Make. No voice settings: the tags direct the delivery (2026-11-04).
@MainActor
final class TalaVoice: ObservableObject {
    struct Account: Equatable {
        var tier: String
        var used: Int
        var limit: Int
        var resets: Date?
        var left: Int { max(0, limit - used) }
    }
    struct Voice: Identifiable, Equatable {
        let id: String
        let name: String
        let category: String
        /// Accent, gender, age and use case, as ElevenLabs labels the voice.
        let labels: [String]
        let preview: URL?
    }
    struct Model: Identifiable, Equatable {
        let id: String
        let name: String
        let description: String
        /// Characters one request takes.
        let maxCharacters: Int
        /// Credits per character: Flash costs half.
        let creditsPerCharacter: Double
    }
    enum Connection: Equatable {
        case noKey, checking, connected, rejected(String), offline(String)
        /// ElevenLabs knows the key, but it lacks a permission Tala needs (its id, e.g. voices_read).
        case missing(String)
    }

    @Published private(set) var connection: Connection = .noKey
    @Published private(set) var account: Account?
    @Published private(set) var voices: [Voice] = []
    @Published private(set) var models: [Model] = []
    @Published var voiceID = UserDefaults.standard.string(forKey: "talaVoice") ?? "" {
        didSet { UserDefaults.standard.set(voiceID, forKey: "talaVoice") }
    }
    /// Eleven v4 until you pick another: it follows the audio tags that direct Tala's voice-overs.
    @Published var modelID = UserDefaults.standard.string(forKey: "talaModel") ?? "eleven_v4" {
        didSet { UserDefaults.standard.set(modelID, forKey: "talaModel") }
    }
    /// Where voice-overs are saved, picked once.
    @Published private(set) var folder = UserDefaults.standard.string(forKey: "talaFolder").map { URL(fileURLWithPath: $0, isDirectory: true) }
    /// Tala's copy of the open script, and which script it is.
    @Published private(set) var copy: TalaCopy?
    private var copyScript: UUID?
    /// The part being made, counted from 1, while a voice-over is made.
    @Published private(set) var making: (part: Int, of: Int)?
    @Published private(set) var made: URL?
    @Published private(set) var failure: String?
    /// The voice sample or voice-over playing.
    @Published private(set) var playing: String?
    private var player: AVPlayer?
    private var ended: NSObjectProtocol?
    private var loaded = false
    /// Tala's copies, one file per script, next to projects.json.
    private let copies: URL

    init() {
        let data = ProcessInfo.processInfo.environment["EDIT_ASSIST_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Edit Assist", isDirectory: true)
        copies = data.appendingPathComponent("tala", isDirectory: true)
        if ElevenLabs.key != nil { connection = .checking }
    }

    var model: Model? { models.first { $0.id == modelID } }

    /// Opens Tala's copy of the script (the first time, made from the script's words).
    func load(script id: UUID, text script: String) {
        guard copyScript != id else { return }
        copyScript = id; made = nil; failure = nil
        let file = copies.appendingPathComponent("\(id.uuidString).json")
        copy = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(TalaCopy.self, from: $0) } ?? TalaCopy(script: script)
    }

    /// Saves your edit of the copy.
    func edit(_ text: String) {
        guard var copy, copy.text != text else { return }
        copy.text = text
        save(copy)
    }

    /// Starts the copy again from the script as it is now; the tags in it are lost.
    func recopy(_ script: String) {
        save(TalaCopy(script: script))
    }

    private func save(_ copy: TalaCopy) {
        self.copy = copy
        guard let copyScript else { return }
        try? FileManager.default.createDirectory(at: copies, withIntermediateDirectories: true)
        try? JSONEncoder().encode(copy).write(to: copies.appendingPathComponent("\(copyScript.uuidString).json"), options: .atomic)
    }

    /// Asks for the folder voice-overs go to.
    @discardableResult
    func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder; panel.prompt = L("Save voice-overs here")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        folder = url
        UserDefaults.standard.set(url.path, forKey: "talaFolder")
        return true
    }

    /// Makes the voice-over of Tala's copy, in parts when it is longer than the model takes at once, and saves it as one MP3.
    func make(project: String, script: String) {
        guard making == nil, let key = ElevenLabs.key, let text = copy?.text.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              !voiceID.isEmpty, let model else { return }
        if folder == nil, !chooseFolder() { return }
        guard let folder else { return }
        let parts = ElevenLabs.parts(text, max: model.maxCharacters)
        let voice = voiceID
        failure = nil; made = nil; stopPreview()
        making = (1, parts.count)
        Task {
            do {
                var audio = Data()
                for (index, part) in parts.enumerated() {
                    making = (index + 1, parts.count)
                    audio += try await ElevenLabs.speak(part, voice: voice, model: model.id,
                                                        previous: index > 0 ? String(parts[index - 1].suffix(500)) : nil,
                                                        next: index + 1 < parts.count ? String(parts[index + 1].prefix(500)) : nil, key: key)
                }
                let file = ElevenLabs.file(project: project, script: script, in: folder)
                try audio.write(to: file, options: .atomic)
                made = file
            } catch ElevenLabs.Failure.missing(let permission) {
                failure = L("this key is missing **%@**: turn it on for the key in ElevenLabs", ElevenLabs.permissionName(permission))
            } catch ElevenLabs.Failure.rejected(let detail) {
                failure = detail
            } catch {
                failure = error.localizedDescription
            }
            making = nil
            if let data = try? await ElevenLabs.get("/v1/user/subscription", key: key) { account = (try? ElevenLabs.account(from: data)) ?? account }
        }
    }

    /// Saves the key once ElevenLabs knows it, even when it lacks a permission: ElevenLabs shows a key only once, so
    /// one dropped then could not be pasted again after you add the permission (2026-11-04). A wrong key is not kept.
    func connect(key: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        connection = .checking
        Task {
            switch await read(key: key) {
            case .connected, .missing: ElevenLabs.key = key
            default: break
            }
        }
    }

    func disconnect() {
        ElevenLabs.key = nil
        stopPreview()
        connection = .noKey; account = nil; voices = []; models = []
    }

    /// The first look, when Tala's page opens.
    func open() {
        guard !loaded else { return }
        refresh()
    }

    /// Reads the account, voices and models again with the saved key.
    func refresh() {
        guard let key = ElevenLabs.key else { connection = .noKey; return }
        connection = .checking
        Task { await read(key: key) }
    }

    @discardableResult
    private func read(key: String) async -> Connection {
        do {
            // The plan needs the key's User permission; a key restricted without it still works for voices.
            async let subscription = ElevenLabs.get("/v1/user/subscription", key: key)
            async let modelList = ElevenLabs.get("/v1/models", key: key)
            var found: [Voice] = [], token: String?
            repeat {
                var path = "/v2/voices?page_size=100&sort=name&sort_direction=asc&include_total_count=false"
                if let token { path += "&next_page_token=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)" }
                let page = try ElevenLabs.voices(from: await ElevenLabs.get(path, key: key))
                found += page.voices; token = page.next
            } while token != nil && found.count < 1000
            voices = found
            if voices.first(where: { $0.id == voiceID }) == nil { voiceID = voices.first?.id ?? "" }
            account = try? ElevenLabs.account(from: await subscription)
            models = (try? ElevenLabs.models(from: await modelList)).flatMap { $0.isEmpty ? nil : $0 } ?? ElevenLabs.knownModels
            loaded = true
            if !models.isEmpty, model == nil { modelID = models.first { $0.id == "eleven_v4" }?.id ?? models[0].id }
            connection = .connected
        } catch ElevenLabs.Failure.missing(let permission) {
            connection = .missing(permission)
        } catch ElevenLabs.Failure.rejected(let detail) {
            connection = .rejected(detail)
        } catch {
            connection = .offline(error.localizedDescription)
        }
        return connection
    }

    /// Plays the voice's sample from ElevenLabs (free: samples cost no credits). Again to stop.
    func preview(_ voice: Voice) {
        guard let url = voice.preview else { return }
        play(url, id: voice.id)
    }

    /// Plays the voice-over just made. Again to stop.
    func playMade() {
        guard let made else { return }
        play(made, id: made.path)
    }

    private func play(_ url: URL, id: String) {
        if playing == id { stopPreview(); return }
        stopPreview()
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        playing = id
        ended = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopPreview() }
        }
        player?.play()
    }

    func stopPreview() {
        player?.pause(); player = nil; playing = nil
        if let ended { NotificationCenter.default.removeObserver(ended) }
        ended = nil
    }
}

/// ElevenLabs' API (https://elevenlabs.io/docs/api-reference), read as of 2026-11-04. The key goes in the xi-api-key header.
enum ElevenLabs {
    enum Failure: Error { case rejected(String), missing(String) }
    static let base = URL(string: "https://api.elevenlabs.io")!
    private static let service = "Edit Assist ElevenLabs"

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

    /// When the key may not read the models: ElevenLabs' text-to-speech models and their limits as of 2026-11-04.
    static let knownModels: [TalaVoice.Model] = [
        .init(id: "eleven_multilingual_v2", name: "Eleven Multilingual v2", description: "Lifelike and consistent; the most stable for long voice-overs.", maxCharacters: 10_000, creditsPerCharacter: 1),
        .init(id: "eleven_v4", name: "Eleven v4", description: "The most expressive and emotive.", maxCharacters: 10_000, creditsPerCharacter: 1),
        .init(id: "eleven_v3", name: "Eleven v3", description: "Expressive, dramatic delivery.", maxCharacters: 5_000, creditsPerCharacter: 1),
        .init(id: "eleven_flash_v2_5", name: "Eleven Flash v2.5", description: "Fast and half the credits.", maxCharacters: 40_000, creditsPerCharacter: 0.5),
    ]

    static func get(_ path: String, key: String) async throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: base)!, timeoutInterval: 20)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        try check(status, data)
        return data
    }

    /// Throws for a refused request: a key without a permission, a wrong key, or anything else ElevenLabs answers.
    static func check(_ status: Int, _ data: Data) throws {
        guard !(200 ..< 300).contains(status) else { return }
        let reason = message(in: data) ?? "HTTP \(status)"
        if let permission = missingPermission(in: reason) { throw Failure.missing(permission) }
        if status == 401 || status == 403 { throw Failure.rejected(reason) }
        throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: reason])
    }

    /// "The API key you used is missing the permission voices_read to execute this operation." → voices_read.
    static func missingPermission(in message: String) -> String? {
        message.firstMatch(of: #/missing the permission (\w+)/#).map { String($0.1) }
    }

    /// A permission as ElevenLabs' key screen names it: voices_read → Voices (Read), text_to_speech → Text to Speech.
    static func permissionName(_ id: String) -> String {
        var words = id.split(separator: "_").map(String.init)
        let access = ["read", "write"].contains(words.last ?? "") ? words.removeLast().capitalized : nil
        let name = words.enumerated().map { $0.offset > 0 && ["to", "and", "of"].contains($0.element) ? $0.element : $0.element.capitalized }
            .joined(separator: " ")
        return access.map { "\(name) (\($0))" } ?? name
    }

    /// ElevenLabs' reason for an error: {"detail": {"status": …, "message": …}} or {"detail": "…"}.
    static func message(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let detail = json["detail"] as? [String: Any] { return detail["message"] as? String ?? detail["status"] as? String }
        return json["detail"] as? String
    }

    static func account(from data: Data) throws -> TalaVoice.Account {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
        return .init(tier: json["tier"] as? String ?? "", used: json["character_count"] as? Int ?? 0, limit: json["character_limit"] as? Int ?? 0,
                     resets: (json["next_character_count_reset_unix"] as? Double).map(Date.init(timeIntervalSince1970:)))
    }

    static func voices(from data: Data) throws -> (voices: [TalaVoice.Voice], next: String?) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let list = json["voices"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        let voices = list.compactMap { voice -> TalaVoice.Voice? in
            guard let id = voice["voice_id"] as? String else { return nil }
            let labels = voice["labels"] as? [String: String] ?? [:]
            return .init(id: id, name: voice["name"] as? String ?? id, category: voice["category"] as? String ?? "",
                         labels: ["accent", "gender", "age", "use_case"].compactMap { labels[$0] }.filter { !$0.isEmpty }
                             .map { $0.replacingOccurrences(of: "_", with: " ") },
                         preview: (voice["preview_url"] as? String).flatMap(URL.init(string:)))
        }
        let more = json["has_more"] as? Bool ?? false
        return (voices, more ? json["next_page_token"] as? String : nil)
    }

    /// The models that make speech from text.
    static func models(from data: Data) throws -> [TalaVoice.Model] {
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        return list.compactMap { model in
            guard let id = model["model_id"] as? String, model["can_do_text_to_speech"] as? Bool == true,
                  model["requires_alpha_access"] as? Bool != true else { return nil }
            return .init(id: id, name: model["name"] as? String ?? id, description: model["description"] as? String ?? "",
                         maxCharacters: model["maximum_text_length_per_request"] as? Int ?? model["max_characters_request_subscribed_user"] as? Int ?? 0,
                         creditsPerCharacter: (model["model_rates"] as? [String: Any])?["character_cost_multiplier"] as? Double ?? 1)
        }
    }

    /// The words a voice-over of the script says: its lines without bold marks.
    static func spoken(_ script: String) -> String {
        ((try? ScriptParser.parse(script)) ?? []).map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The audio tags in a text: [excited], [whispers], … (ElevenLabs' way of directing the delivery, in v3 and v4).
    static func tags(in text: String) -> [Range<String.Index>] {
        text.ranges(of: #/\[[^\[\]\n]{1,60}\]/#)
    }

    /// Eleven v3 and v4 follow audio tags; older models may read them out loud (2026-11-04).
    static func understandsTags(_ modelID: String) -> Bool {
        modelID.hasPrefix("eleven_v3") || modelID.hasPrefix("eleven_v4")
    }

    /// The text in parts a request takes, cut between lines, else between sentences, else between words, so no part
    /// stops mid-word. Each part is sent with the text around it, so the voice carries on as one read.
    static func parts(_ text: String, max: Int) -> [String] {
        guard max > 0, text.count > max else { return [text] }
        var parts: [String] = [], current = ""
        func add(_ piece: String, joiner: String) {
            if current.isEmpty { current = piece }
            else if current.count + joiner.count + piece.count <= max { current += joiner + piece }
            else { parts.append(current); current = piece }
        }
        for line in text.components(separatedBy: "\n") {
            // A line's first piece keeps its line break; the rest of it joins with spaces.
            var joiner = "\n"
            func piece(_ text: String) { add(text, joiner: joiner); joiner = " " }
            if line.count <= max { piece(line); continue }
            // Sentences: each ends at . ! or ? followed by a space.
            var sentences: [String] = [], sentence = ""
            for (index, character) in zip(line.indices, line) {
                if character == " ", let last = sentence.last, ".!?".contains(last), line.index(after: index) < line.endIndex {
                    sentences.append(sentence); sentence = ""
                } else { sentence.append(character) }
            }
            sentences.append(sentence)
            for sentence in sentences.filter({ !$0.isEmpty }) {
                if sentence.count <= max { piece(sentence); continue }
                for word in sentence.split(separator: " ").map(String.init) {
                    var word = word
                    while word.count > max { piece(String(word.prefix(max))); word = String(word.dropFirst(max)) }
                    piece(word)
                }
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// Speech for one part, as 44.1 kHz MP3 (the format every plan gets; MP3 parts play back to back when joined).
    static func speak(_ text: String, voice: String, model: String, previous: String?, next: String?, key: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "/v1/text-to-speech/\(voice)?output_format=mp3_44100_128", relativeTo: base)!, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["text": text, "model_id": model]
        if let previous { body["previous_text"] = previous }
        if let next { body["next_text"] = next }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        return data
    }

    /// "<project> - <script> - voice-over.mp3" in the folder, numbered rather than replacing an earlier one.
    static func file(project: String, script: String, in folder: URL) -> URL {
        let clean = { (name: String) in name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-").trimmingCharacters(in: .whitespaces) }
        let stem = [clean(project), clean(script), "voice-over"].filter { !$0.isEmpty }.joined(separator: " - ")
        var url = folder.appendingPathComponent(stem + ".mp3"), number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(stem) \(number).mp3"); number += 1
        }
        return url
    }
}

/// Tala's copy of one script: the words to voice with your audio tags, and the script's words it was made from, to tell
/// when the script changed after. Kept apart from the script so the highlight runs never see a tag (2026-11-04).
struct TalaCopy: Codable, Equatable {
    var text: String
    var from: String

    init(script: String) {
        text = ElevenLabs.spoken(script); from = text
    }

    /// The script's words are no longer the ones the copy was made from.
    func outdated(by script: String) -> Bool { ElevenLabs.spoken(script) != from }
}
