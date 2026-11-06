import AppKit
import Foundation
import Security

/// Basil's work: your YouTube key (Keychain), the recipes folder you chose in your vault, what he found and what he is writing.
/// Everything he decides is in `Kitchen`; this is the Mac around it.
@MainActor final class BasilDesk: ObservableObject {
    @Published private(set) var folder: URL?
    @Published private(set) var recipes: [Kitchen.Entry] = []
    @Published private(set) var results: [Kitchen.Video] = []
    /// What the results are for, and whether Basil searched it from the chat.
    @Published private(set) var resultsFor = ""
    @Published private(set) var resultsByBasil = false
    @Published private(set) var searching = false
    /// The videos being written ("words" for your own).
    @Published private(set) var writing: Set<String> = []
    @Published private(set) var hasKey = BasilDesk.key != nil
    @Published private(set) var checkingKey = false
    @Published var failure: String?
    /// The last note written, to open.
    @Published private(set) var written: URL?
    /// Every conversation with him, kept in basil/chats.json beside projects.json.
    @Published private(set) var conversations: [Kitchen.Conversation] = []
    /// The one open; nil is a new chat, made when you send its first message.
    @Published var current: UUID?
    /// The conversation he is answering in.
    @Published private(set) var thinkingIn: UUID?
    var thinking: Bool { thinkingIn != nil }
    /// The open conversation's messages.
    var chat: [Kitchen.Message] { conversations.first { $0.id == current }?.messages ?? [] }
    /// The videos you saved to review (dropped on the save area, or Basil's picks), newest first; kept in basil/saved.json.
    @Published private(set) var saved: [Kitchen.Saved] = []
    /// Why writing a saved video's recipe failed, by video.
    @Published private(set) var refused: [String: String] = [:]
    /// Basil choosing recipe videos for you.
    @Published private(set) var picking = false

    var busy: Bool { searching || thinking || picking || !writing.isEmpty }
    /// The videos already in the vault, by their link.
    var sources: Set<String> { Set(recipes.map(\.source).filter { !$0.isEmpty }) }

    init() {
        folder = UserDefaults.standard.string(forKey: "basilFolder").map { URL(fileURLWithPath: $0, isDirectory: true) }
        conversations = (try? Data(contentsOf: Self.chatsFile)).flatMap { try? JSONDecoder().decode([Kitchen.Conversation].self, from: $0) } ?? []
        // The single chat kept before there was a history becomes its first conversation.
        if conversations.isEmpty, let old = (try? Data(contentsOf: Self.oldChatFile)).flatMap({ try? JSONDecoder().decode([Kitchen.Message].self, from: $0) }), !old.isEmpty {
            conversations = [Kitchen.Conversation(messages: old, created: old.first?.date ?? Date(), updated: old.last?.date ?? Date())]
            saveChats()
            try? FileManager.default.removeItem(at: Self.oldChatFile)
        }
        current = conversations.max { $0.updated < $1.updated }?.id
        saved = (try? Data(contentsOf: Self.savedFile)).flatMap { try? JSONDecoder().decode([Kitchen.Saved].self, from: $0) } ?? []
    }

    nonisolated static var savedFile: URL { Studio.folder.appendingPathComponent("basil/saved.json") }

    nonisolated static var chatsFile: URL { Studio.folder.appendingPathComponent("basil/chats.json") }
    nonisolated static var oldChatFile: URL { Studio.folder.appendingPathComponent("basil/chat.json") }

    // MARK: Key and folder

    private static let service = "Edit Assist YouTube"
    static var key: String? {
        get {
            var result: AnyObject?
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecAttrAccount as String: "api-key", kSecReturnData as String: true]
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
            SecItemDelete(query as CFDictionary)
            guard let newValue, let data = newValue.data(using: .utf8) else { return }
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    /// Kept only once YouTube takes it (one video's details: 1 unit).
    func save(key: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        checkingKey = true; failure = nil
        Task {
            defer { checkingKey = false }
            do {
                _ = try await fetch(Kitchen.videosURL(["wwapBsT0oc8"], key: key))
                Self.key = key; hasKey = true
            } catch { failure = describe(error) }
        }
    }

    func forgetKey() { Self.key = nil; hasKey = false; results = [] }

    @discardableResult func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = L("Choose the folder in your Obsidian vault for recipes")
        panel.prompt = L("Use this folder")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        UserDefaults.standard.set(url.path, forKey: "basilFolder")
        folder = url
        reload()
        return true
    }

    /// The notes in the folder, read off the main thread.
    func reload() {
        guard let folder else { recipes = []; return }
        Task {
            let found = await Task.detached { Kitchen.entries(in: folder) }.value
            if self.folder == folder { recipes = found }
        }
    }

    // MARK: Chat

    /// Your message, then his answer: up to three rounds, each of which may search YouTube or read notes before he answers.
    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        let id = current ?? UUID()
        if current == nil { conversations.append(Kitchen.Conversation(id: id)); current = id }
        append(Kitchen.Message(fromBasil: false, text: text), to: id)
        thinkingIn = id; failure = nil
        Task {
            defer { thinkingIn = nil }
            // The conversation asked in, even if you open another meanwhile.
            var chat: [Kitchen.Message] { conversations.first { $0.id == id }?.messages ?? [] }
            var found: [Kitchen.Video]?, searched = "", read: [Kitchen.Entry] = [], texts: [(title: String, text: String)] = []
            do {
                for round in 0 ..< 3 {
                    let prompt = Kitchen.chatPrompt(chat: chat, recipes: recipes, folder: folder != nil, canSearch: Self.key != nil, found: found, searched: searched,
                                                    read: texts, last: round == 2)
                    let reply = Kitchen.reply(from: try await HelperBrain.ask(prompt, schema: Kitchen.chatSchema))
                    var looked = false
                    if !reply.youtube.isEmpty, reply.youtube != searched, let key = Self.key, round < 2 {
                        searched = reply.youtube
                        found = try await videos(for: reply.youtube, key: key, count: 12)
                        // What he found shows in Find too, to save from.
                        results = found ?? []; resultsFor = reply.youtube; resultsByBasil = true
                        looked = true
                    }
                    let wanted = Kitchen.named(reply.notes, in: recipes).filter { !read.contains($0) }
                    if !wanted.isEmpty, round < 2 {
                        let more = await Task.detached { wanted.map { (title: $0.title, text: (try? String(contentsOf: $0.file, encoding: .utf8)) ?? "") } }.value
                        read += wanted; texts += more
                        looked = true
                    }
                    if looked { continue }
                    let shown = reply.show.compactMap { id in found?.first { $0.id == id } ?? chat.last { $0.fromBasil && !$0.videos.isEmpty }?.videos.first { $0.id == id } }
                    append(Kitchen.Message(fromBasil: true, text: reply.text.isEmpty ? L("I couldn't find an answer to that.") : reply.text,
                                           videos: Array(shown.prefix(6)), notes: read.map(\.file.path)), to: id)
                    return
                }
            } catch { failure = describe(error) }
        }
    }

    /// A new, empty chat; the one you were in stays in the history.
    func newChat() { current = nil }

    func delete(_ id: UUID) {
        guard thinkingIn != id else { return }
        conversations.removeAll { $0.id == id }
        if current == id { current = conversations.max { $0.updated < $1.updated }?.id }
        saveChats()
    }

    private func append(_ message: Kitchen.Message, to id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].messages.append(message)
        conversations[index].updated = message.date
        saveChats()
    }

    private func saveChats() {
        let file = Self.chatsFile
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(conversations).write(to: file, options: .atomic)
    }

    // MARK: YouTube

    /// Search, then each video's details, in the search's order.
    private func videos(for words: String, key: String, count: Int = 24) async throws -> [Kitchen.Video] {
        let ids = Kitchen.ids(inSearch: try await fetch(Kitchen.searchURL(words, key: key, count: count)))
        guard !ids.isEmpty else { return [] }
        let videos = Kitchen.videos(in: try await fetch(Kitchen.videosURL(ids, key: key)))
        return ids.compactMap { id in videos.first { $0.id == id } }
    }

    func search(_ words: String) {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, let key = Self.key, !searching else { return }
        searching = true; failure = nil
        Task {
            defer { searching = false }
            do {
                let query = Kitchen.recipeSearch(words)
                results = try await videos(for: query, key: key); resultsFor = query; resultsByBasil = false
            } catch { failure = describe(error) }
        }
    }

    /// The video's recipe as a note: from the recipe page it links to when there is one, else from its description.
    // MARK: Saved videos

    /// Kept in the app to review; nothing is written yet, so no vault is needed.
    func save(_ video: Kitchen.Video, why: String = "") {
        guard !saved.contains(where: { $0.id == video.id }) else { return }
        saved.insert(Kitchen.Saved(video: video, why: why), at: 0)
        saveSaved()
    }

    /// A video dragged onto the save area, by its id: from the results or the chat.
    func save(id: String) {
        guard let video = results.first(where: { $0.id == id }) ?? conversations.lazy.flatMap(\.messages).flatMap(\.videos).first(where: { $0.id == id }) else { return }
        save(video)
    }

    func remove(_ item: Kitchen.Saved) { saved.removeAll { $0.id == item.id }; refused[item.id] = nil; saveSaved() }

    /// The saved videos whose recipe isn't written yet.
    var unwritten: [Kitchen.Saved] { saved.filter { $0.written.isEmpty } }

    /// Writes the video's recipe into the vault (asking for the folder the first time).
    func write(_ video: Kitchen.Video) {
        guard !writing.contains(video.id), folder != nil || chooseFolder() else { return }
        Task { await writeRecipe(video) }
    }

    /// Writes every saved video not written yet, one after another.
    func writeAll() {
        let waiting = unwritten.filter { !writing.contains($0.id) }
        guard !waiting.isEmpty, folder != nil || chooseFolder() else { return }
        Task { for item in waiting { await writeRecipe(item.video) } }
    }

    private func writeRecipe(_ video: Kitchen.Video) async {
        guard let folder, !writing.contains(video.id) else { return }
        writing.insert(video.id); refused[video.id] = nil; failure = nil
        defer { writing.remove(video.id) }
        do {
            var page: (url: URL, data: [String: Any])?
            for link in Kitchen.links(in: video.description) {
                if let data = await recipePage(link) { page = (link, data); break }
            }
            let answer = try await HelperBrain.ask(Kitchen.prompt(for: video, page: page?.data), schema: Kitchen.schema)
            var recipe = Kitchen.recipe(from: answer)
            if recipe.title.isEmpty { recipe.title = video.title }
            recipe.source = video.url.absoluteString; recipe.channel = video.channel; recipe.page = page?.url.absoluteString ?? ""
            let file = try save(recipe, in: folder)
            if let index = saved.firstIndex(where: { $0.id == video.id }) { saved[index].written = file.path; saveSaved() }
        } catch {
            if saved.contains(where: { $0.id == video.id }) { refused[video.id] = describe(error) } else { failure = describe(error) }
        }
    }

    private func saveSaved() {
        let file = Self.savedFile
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(saved).write(to: file, options: .atomic)
    }

    /// Basil searches recipes for your words, picks the real recipe videos worth saving (at most five), and saves them here to review.
    func pick(_ words: String) {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, let key = Self.key, !picking, !searching else { return }
        picking = true; failure = nil
        Task {
            defer { picking = false }
            do {
                let query = Kitchen.recipeSearch(words)
                results = try await videos(for: query, key: key); resultsFor = query; resultsByBasil = false
                let kept = Set(saved.map(\.id))
                let fresh = results.filter { !sources.contains($0.url.absoluteString) && !kept.contains($0.id) }
                guard !fresh.isEmpty else { return }
                let answer = try await HelperBrain.ask(Kitchen.pickPrompt(query, videos: fresh, count: 5), schema: Kitchen.pickSchema)
                let picks = Kitchen.picks(from: answer, among: fresh, count: 5)
                if picks.isEmpty { failure = L("Basil found no real recipe among these videos. Try other words."); return }
                for pick in picks.reversed() {
                    if let video = fresh.first(where: { $0.id == pick.id }) { save(video, why: pick.why) }
                }
            } catch { failure = describe(error) }
        }
    }

    /// A recipe from your own words.
    func write(words: String) {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !writing.contains("words"), folder != nil || chooseFolder(), let folder else { return }
        writing.insert("words"); failure = nil
        Task {
            defer { writing.remove("words") }
            do {
                let recipe = Kitchen.recipe(from: try await HelperBrain.ask(Kitchen.prompt(for: words), schema: Kitchen.schema))
                try save(recipe, in: folder)
            } catch { failure = describe(error) }
        }
    }

    /// Written as a new note, never over one already there.
    @discardableResult private func save(_ recipe: Kitchen.Recipe, in folder: URL) throws -> URL {
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let file = folder.appendingPathComponent(Kitchen.fileName(for: recipe.title, taken: taken))
        let added = Date().formatted(.iso8601.year().month().day())
        try Data(Kitchen.note(recipe, added: added).utf8).write(to: file, options: .withoutOverwriting)
        written = file
        reload()
        return file
    }

    /// Where a recipe stands, written into its note's header.
    func set(_ status: String, for entry: Kitchen.Entry) {
        guard let data = try? Data(contentsOf: entry.file) else { return }
        let text = Kitchen.setting("status", to: status, in: String(decoding: data, as: UTF8.self))
        do { try Data(text.utf8).write(to: entry.file, options: .atomic); reload() } catch { failure = error.localizedDescription }
    }

    // MARK: Network

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            let reason = Kitchen.failure(in: data)
            if reason == "quotaExceeded" { throw AssistError.message(L("Today's YouTube searches are used up (about 100 a day on a free key); they come back at midnight Pacific time.")) }
            throw AssistError.message(L("YouTube: %@", reason ?? "HTTP \(status)"))
        }
        return data
    }

    /// The page's schema.org Recipe, or nil (not a recipe page, refused, or too slow).
    private func recipePage(_ url: URL) async -> [String: Any]? {
        guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15)),
              ((response as? HTTPURLResponse)?.statusCode ?? 0) < 400, data.count < 8_000_000 else { return nil }
        return Kitchen.recipeData(inHTML: String(decoding: data, as: UTF8.self))
    }

    private func describe(_ error: Error) -> String {
        if case AssistError.message(let text) = error { return text }
        return error.localizedDescription
    }
}
