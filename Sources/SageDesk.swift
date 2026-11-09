import AppKit
import Foundation
import Security

/// Sage's work: your topics (each with its folder in your vault), your YouTube key (Keychain), what he found, what you
/// saved, what he is writing, and your chats with him. Everything he decides is in `Study`; this is the Mac around it.
/// Kept in sage/ beside projects.json (Basil's basil/ is moved there the first time).
@MainActor final class SageDesk: ObservableObject {
    /// What you research, each with its folder and note style; the one open.
    @Published private(set) var topics: [Study.Topic] = []
    @Published private(set) var topicID: UUID?
    /// The open topic's notes.
    @Published private(set) var recipes: [Study.Entry] = []
    @Published var results: [Study.Video] = []
    /// What the results are for, and whether Sage searched it from the chat.
    @Published var resultsFor = ""
    @Published private(set) var resultsBySage = false
    /// Which half of the page shows beside the chat: research (Find, Saved, Write your own) or notes (your notes, one open).
    @Published var stage = UserDefaults.standard.string(forKey: "sageStage") ?? UserDefaults.standard.string(forKey: "basilStage") ?? "research" {
        didSet { UserDefaults.standard.set(stage, forKey: "sageStage") }
    }
    /// The note open in the notes stage.
    @Published var note: URL?
    /// Your vault's look in Obsidian (theme, accent, fonts, snippets), read with the topic's folder.
    @Published private(set) var look = Study.Look()
    @Published private(set) var searching = false
    /// Sources being read or written, by id ("words" for your own).
    @Published private(set) var writing: Set<String> = []
    @Published private(set) var adding = false
    @Published private(set) var hasKey = SageDesk.key != nil
    @Published private(set) var checkingKey = false
    @Published var failure: String?
    /// The last note written, to open.
    @Published private(set) var written: URL?
    /// Every conversation with him, kept in sage/chats.json.
    @Published private(set) var conversations: [Study.Conversation] = []
    /// The one open; nil is a new chat, made when you send its first message.
    @Published var current: UUID?
    /// The conversation he is answering in.
    @Published private(set) var thinkingIn: UUID?
    var thinking: Bool { thinkingIn != nil }
    /// The open conversation's messages.
    var chat: [Study.Message] { conversations.first { $0.id == current }?.messages ?? [] }
    /// Everything you saved to review (videos and pages, from Find, the chat or Sage's picks), newest first; kept in sage/saved.json.
    @Published private(set) var saved: [Study.Saved] = []
    /// Why writing a saved source failed, by id.
    @Published private(set) var refused: [String: String] = [:]
    /// Sage choosing videos for you.
    @Published var picking = false
    /// What the last Pick did: what it saved and why, and what it passed over and why not. Cleared by a new search.
    @Published var lastPick: Study.PickOutcome?
    /// Pick's steps so far, the last one the step it is on ("Searching 3 angles…").
    @Published var pickSteps: [String] = []
    /// The video playing in the mini player, or nil when it is closed (SageDeskPick.swift).
    @Published var playing: Study.Video?
    /// The mini player shown large over the stage (true) or docked small in the corner (false).
    @Published var playerExpanded = UserDefaults.standard.bool(forKey: "sagePlayerExpanded") {
        didSet { UserDefaults.standard.set(playerExpanded, forKey: "sagePlayerExpanded") }
    }

    /// The vault you had Sage connect from the chat (Obsidian's list); empty: the one the topic's folder is in (SageActions.swift).
    @Published var vaultPath = UserDefaults.standard.string(forKey: "sageVault") ?? "" {
        didSet { UserDefaults.standard.set(vaultPath, forKey: "sageVault") }
    }
    /// What he did for each of his messages, to undo it (this run only).
    @Published var undos: [UUID: [SageUndo]] = [:]
    var busy: Bool { searching || thinking || picking || adding || !writing.isEmpty }
    var topic: Study.Topic { topics.first { $0.id == topicID } ?? topics.first ?? Study.Topic(name: "Research") }
    var folder: URL? { topic.folder.isEmpty ? nil : URL(fileURLWithPath: topic.folder, isDirectory: true) }
    /// The sources already in the topic's notes, by their link.
    var sources: Set<String> { Set(recipes.map(\.source).filter { !$0.isEmpty }) }
    /// What you saved in the open topic.
    var savedHere: [Study.Saved] { saved.filter { $0.topic == topic.id } }

    nonisolated static var place: URL { Studio.folder.appendingPathComponent("sage", isDirectory: true) }
    nonisolated static var savedFile: URL { place.appendingPathComponent("saved.json") }
    nonisolated static var chatsFile: URL { place.appendingPathComponent("chats.json") }
    nonisolated static var topicsFile: URL { place.appendingPathComponent("topics.json") }

    init() {
        // Basil's things become Sage's: his folder, and his recipes folder as the Recipes topic.
        let old = Studio.folder.appendingPathComponent("basil", isDirectory: true)
        if !FileManager.default.fileExists(atPath: Self.place.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: Self.place)
        }
        topics = (try? Data(contentsOf: Self.topicsFile)).flatMap { try? JSONDecoder().decode([Study.Topic].self, from: $0) } ?? []
        if topics.isEmpty {
            let recipes = UserDefaults.standard.string(forKey: "basilFolder")
            let hadBasil = recipes != nil || FileManager.default.fileExists(atPath: Self.savedFile.path) || FileManager.default.fileExists(atPath: Self.chatsFile.path)
            topics = hadBasil ? [Study.Topic(name: "Recipes", kind: .recipes, folder: recipes ?? "")] : [Study.Topic(name: "Research")]
            saveTopics()
        }
        topicID = UserDefaults.standard.string(forKey: "sageTopic").flatMap(UUID.init(uuidString:)).flatMap { id in topics.contains { $0.id == id } ? id : nil } ?? topics.first?.id
        conversations = (try? Data(contentsOf: Self.chatsFile)).flatMap { try? JSONDecoder().decode([Study.Conversation].self, from: $0) } ?? []
        current = conversations.max { $0.updated < $1.updated }?.id
        saved = (try? Data(contentsOf: Self.savedFile)).flatMap { try? JSONDecoder().decode([Study.Saved].self, from: $0) } ?? []
        // Saved before there were topics: the first topic's.
        if saved.contains(where: { $0.topic == nil }), let first = topics.first?.id {
            for index in saved.indices where saved[index].topic == nil { saved[index].topic = first }
            saveSaved()
        }
    }

    // MARK: Topics

    func open(topic id: UUID) {
        guard topics.contains(where: { $0.id == id }) else { return }
        topicID = id
        UserDefaults.standard.set(id.uuidString, forKey: "sageTopic")
        note = nil; recipes = []; results = []; resultsFor = ""
        reload()
    }

    /// A new topic, opened; its folder is chosen when its first note is written.
    func add(topic name: String, kind: Study.Topic.Kind) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let topic = Study.Topic(name: name, kind: kind)
        topics.append(topic); saveTopics()
        open(topic: topic.id)
    }

    func rename(topic id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[index].name = name; saveTopics()
    }

    /// Takes the topic off the list with what you saved in it; its notes stay in your vault.
    func remove(topic id: UUID) {
        guard topics.count > 1 else { return }
        topics.removeAll { $0.id == id }; saveTopics()
        saved.removeAll { $0.topic == id }; saveSaved()
        if topicID == id, let first = topics.first?.id { open(topic: first) }
    }

    /// A topic's folder set from the chat (a path; empty: none).
    func setFolder(_ path: String, for id: UUID) {
        guard let index = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[index].folder = path; saveTopics()
        if id == topic.id { reload() }
    }

    private func saveTopics() {
        try? FileManager.default.createDirectory(at: Self.place, withIntermediateDirectories: true)
        try? JSONEncoder().encode(topics).write(to: Self.topicsFile, options: .atomic)
    }

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
                _ = try await fetch(Study.videosURL(["wwapBsT0oc8"], key: key))
                Self.key = key; hasKey = true
            } catch { failure = describe(error) }
        }
    }

    func forgetKey() { Self.key = nil; hasKey = false; results = [] }

    /// The open topic's folder in your vault.
    @discardableResult func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = L("Choose the folder in your Obsidian vault for “%@”", topic.name)
        panel.prompt = L("Use this folder")
        guard panel.runModal() == .OK, let url = panel.url, let index = topics.firstIndex(where: { $0.id == topic.id }) else { return false }
        topics[index].folder = url.path; saveTopics()
        reload()
        return true
    }

    /// The topic's notes, read off the main thread, with the vault's look.
    func reload() {
        guard let folder else { recipes = []; return }
        let id = topic.id
        Task {
            let (found, look) = await Task.detached { (Study.entries(in: folder), Study.vault(of: folder).map(Study.look(vault:)) ?? Study.Look()) }.value
            if topic.id == id { recipes = found; self.look = look }
        }
    }

    // MARK: Chat

    /// Your message, then his answer: up to four rounds, each of which may search YouTube, read notes, look in the whole
    /// vault or do what you asked (SageActions.swift) before he answers.
    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        let id = current ?? UUID()
        if current == nil { conversations.append(Study.Conversation(id: id)); current = id }
        append(Study.Message(fromSage: false, text: text), to: id)
        thinkingIn = id; failure = nil
        Task {
            defer { thinkingIn = nil }
            // The conversation asked in, even if you open another meanwhile.
            var chat: [Study.Message] { conversations.first { $0.id == id }?.messages ?? [] }
            var found: [Study.Video]?, searched = "", read: [Study.Entry] = [], texts: [(title: String, text: String)] = []
            var hits: [Study.Hit]?, findWords = "", vaultRead: [(path: String, text: String)] = []
            var shownDone: [String] = [], toldDone: [String] = [], steps: [SageUndo] = []
            let known = await Task.detached { SageDesk.knownVaults() }.value
            var contents = await vaultContents()
            do {
                let rounds = 4
                for round in 0 ..< rounds {
                    let last = round == rounds - 1
                    let topic = self.topic
                    let prompt = Study.chatPrompt(chat: chat, recipes: recipes, folder: folder != nil, canSearch: Self.key != nil, found: found, searched: searched,
                                                  read: texts, last: last, topic: topic)
                        + Study.abilitiesPrompt(vault: vault?.path ?? "", known: known, topics: topics, current: topic, folders: contents.folders,
                                                findWords: findWords, found: hits, read: vaultRead, done: toldDone, last: last)
                    let answer = try await HelperBrain.ask(prompt, schema: Study.chatSchema)
                    let reply = Study.reply(from: answer)
                    var looked = false
                    if !last {
                        if !reply.youtube.isEmpty, reply.youtube != searched, let key = Self.key {
                            searched = reply.youtube
                            found = try await videos(for: reply.youtube, key: key, count: 12)
                            // What he found shows in Find too, to save from.
                            results = found ?? []; resultsFor = reply.youtube; resultsBySage = true
                            looked = true
                        }
                        let wanted = Study.named(reply.notes, in: recipes).filter { !read.contains($0) }
                        if !wanted.isEmpty {
                            let more = await Task.detached { wanted.map { (title: $0.title, text: (try? String(contentsOf: $0.file, encoding: .utf8)) ?? "") } }.value
                            read += wanted; texts += more
                            looked = true
                        }
                        if let vault {
                            let words = (answer["find"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !words.isEmpty, words != findWords {
                                let notes = contents.notes
                                findWords = words
                                hits = await Task.detached { Study.find(words, in: notes, vault: vault) }.value
                                looked = true
                            }
                            let paths = (answer["read"] as? [Any] ?? []).compactMap { $0 as? String }
                            let notes = paths.compactMap { Study.resolve($0, in: contents.notes) }.filter { note in !vaultRead.contains { $0.path == note.path } }.prefix(5)
                            if !notes.isEmpty {
                                let more = await Task.detached { notes.map { (path: $0.path, text: Study.noteText((try? Data(contentsOf: vault.appendingPathComponent($0.path))) ?? Data()).text) } }.value
                                vaultRead += more
                                looked = true
                            }
                        }
                        let actions = Study.actions(from: answer)
                        if !actions.isEmpty {
                            let outcome = await perform(actions)
                            shownDone += outcome.shown; toldDone += outcome.told; steps += outcome.undo
                            contents = await vaultContents()
                            looked = true
                        }
                    }
                    if looked { continue }
                    let known = { (id: String) in found?.first { $0.id == id } ?? chat.reversed().lazy.flatMap(\.videos).first { $0.id == id } }
                    let shown = reply.show.compactMap(known)
                    for video in reply.save.compactMap(known).reversed() { save(video) }
                    let readPaths = read.map(\.file.path) + vaultRead.compactMap { note in vault.map { $0.appendingPathComponent(note.path).path } }
                    var message = Study.Message(fromSage: true, text: reply.text.isEmpty ? (shownDone.isEmpty ? L("I couldn't find an answer to that.") : L("Done.")) : reply.text,
                                                videos: Array(shown.prefix(6)), notes: readPaths)
                    message.done = shownDone.isEmpty ? nil : shownDone
                    if !steps.isEmpty { undos[message.id] = steps }
                    append(message, to: id)
                    return
                }
            } catch {
                failure = describe(error)
                // What he did before it failed stays said, with its undo.
                if !shownDone.isEmpty {
                    var message = Study.Message(fromSage: true, text: L("Done."))
                    message.done = shownDone
                    if !steps.isEmpty { undos[message.id] = steps }
                    append(message, to: id)
                }
            }
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

    func append(_ message: Study.Message, to id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].messages.append(message)
        conversations[index].updated = message.date
        saveChats()
    }

    private func saveChats() {
        try? FileManager.default.createDirectory(at: Self.place, withIntermediateDirectories: true)
        try? JSONEncoder().encode(conversations).write(to: Self.chatsFile, options: .atomic)
    }

    // MARK: Finding

    /// Search, then each video's details, in the search's order.
    func videos(for words: String, key: String, count: Int = 24) async throws -> [Study.Video] {
        let ids = Study.ids(inSearch: try await fetch(Study.searchURL(words, key: key, count: count)))
        guard !ids.isEmpty else { return [] }
        let videos = Study.videos(in: try await fetch(Study.videosURL(ids, key: key)))
        return ids.compactMap { id in videos.first { $0.id == id } }
    }

    func search(_ words: String) {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, let key = Self.key, !searching else { return }
        searching = true; failure = nil; lastPick = nil
        let query = Study.search(words, in: topic)
        Task {
            defer { searching = false }
            do { results = try await videos(for: query, key: key); resultsFor = query; resultsBySage = false } catch { failure = describe(error) }
        }
    }

    // Pick for me: SageDeskPick.swift.

    // MARK: Saved

    /// Kept in the app to review; nothing is written yet, so no vault is needed.
    func save(_ video: Study.Video, why: String = "", in topic: UUID? = nil) {
        let topic = topic ?? self.topic.id
        guard !saved.contains(where: { $0.id == video.id && $0.topic == topic }) else { return }
        saved.insert(Study.Saved(video: video, why: why, topic: topic), at: 0)
        saveSaved()
    }

    /// A web page saved: read now (its title, picture and text), so writing it later needs no second visit.
    func add(page url: URL) {
        let topic = topic.id
        guard !saved.contains(where: { $0.id == url.absoluteString && $0.topic == topic }), !adding else { return }
        adding = true; failure = nil
        Task {
            defer { adding = false }
            do {
                let page = try await read(url)
                saved.insert(Study.Saved(page: page, topic: topic), at: 0)
                saveSaved()
            } catch { failure = L("Could not read that page: %@", describe(error)) }
        }
    }

    /// Something dropped on the save area: a video's id (from Find or the chat) or a web link (from your browser).
    func save(id: String) {
        if let video = results.first(where: { $0.id == id }) ?? conversations.lazy.flatMap(\.messages).flatMap(\.videos).first(where: { $0.id == id }) {
            save(video)
        } else if let url = Study.link(id) {
            if let video = Study.videoID(of: url.absoluteString) { save(video: video, link: url) } else { add(page: url) }
        }
    }

    /// A YouTube link dropped or pasted: saved as the video, with its details when the key allows.
    private func save(video id: String, link: URL) {
        let topic = topic.id
        guard let key = Self.key else { save(Study.Video(id: id, title: link.absoluteString), in: topic); return }
        Task {
            let video = (try? Study.videos(in: await fetch(Study.videosURL([id], key: key))).first) ?? Study.Video(id: id, title: link.absoluteString)
            save(video, in: topic)
        }
    }

    func remove(_ item: Study.Saved) { saved.removeAll { $0.id == item.id && $0.topic == item.topic }; refused[item.id] = nil; saveSaved() }

    /// What is saved in the open topic and not written yet.
    var unwritten: [Study.Saved] { savedHere.filter { $0.written.isEmpty } }

    /// Writes the saved source's note into the topic's folder (asking for the folder the first time).
    func write(_ item: Study.Saved) {
        guard !writing.contains(item.id), folder != nil || chooseFolder() else { return }
        Task { await writeNote(item) }
    }

    /// A video from Find or the chat, written straight away.
    func write(_ video: Study.Video) { write(Study.Saved(video: video, topic: topic.id)) }

    /// Writes everything saved here and not written yet, one after another.
    func writeAll() {
        let waiting = unwritten.filter { !writing.contains($0.id) }
        guard !waiting.isEmpty, folder != nil || chooseFolder() else { return }
        Task { for item in waiting { await writeNote(item) } }
    }

    private func writeNote(_ item: Study.Saved) async {
        guard let folder, !writing.contains(item.id) else { return }
        let topic = topic
        writing.insert(item.id); refused[item.id] = nil; failure = nil
        defer { writing.remove(item.id) }
        do {
            let text: String, title: String
            if topic.kind == .recipes {
                var recipe = try await recipe(of: item)
                if recipe.title.isEmpty { recipe.title = item.title }
                text = Study.note(recipe, added: today); title = recipe.title
            } else {
                var brief = try await brief(of: item, topic: topic)
                if brief.title.isEmpty { brief.title = item.title }
                text = Study.note(brief, topic: topic.name, added: today); title = brief.title
            }
            let file = try save(text, titled: title, in: folder)
            if let index = saved.firstIndex(where: { $0.id == item.id && $0.topic == item.topic }) { saved[index].written = file.path; saveSaved() }
        } catch {
            if saved.contains(where: { $0.id == item.id }) { refused[item.id] = describe(error) } else { failure = describe(error) }
        }
    }

    /// A recipe from a video (the recipe page it links to when there is one) or a page (its schema.org Recipe, else its text).
    private func recipe(of item: Study.Saved) async throws -> Study.Recipe {
        var recipe: Study.Recipe
        if let video = item.video {
            var page: (url: URL, data: [String: Any])?
            for link in Study.links(in: video.description) {
                if let data = await recipePage(link) { page = (link, data); break }
            }
            recipe = Study.recipe(from: try await HelperBrain.ask(Study.prompt(for: video, page: page?.data), schema: Study.schema))
            recipe.source = video.url.absoluteString; recipe.channel = video.channel; recipe.page = page?.url.absoluteString ?? ""
        } else if let page = item.page {
            let structured = await recipePage(page.url)
            let material = structured.flatMap { try? JSONSerialization.data(withJSONObject: $0) }.map { String(decoding: $0, as: UTF8.self) } ?? page.text
            recipe = Study.recipe(from: try await HelperBrain.ask(Study.prompt(for: "From the recipe page \(page.title) (\(page.site)):\n" + material), schema: Study.schema))
            recipe.source = page.url.absoluteString; recipe.channel = page.site
        } else { throw AssistError.message(L("Nothing to write from.")) }
        return recipe
    }

    /// A research note from a video (with a page it links to, when one reads) or a page.
    private func brief(of item: Study.Saved, topic: Study.Topic) async throws -> Study.Brief {
        var brief: Study.Brief
        if let video = item.video {
            var linked: Study.Page?
            for link in Study.links(in: video.description) {
                if let page = try? await read(link), page.text.count > 600 { linked = page; break }
            }
            brief = Study.brief(from: try await HelperBrain.ask(Study.briefPrompt(for: video, linked: linked, topic: topic.name), schema: Study.briefSchema))
            brief.source = video.url.absoluteString; brief.channel = video.channel; brief.page = linked?.url.absoluteString ?? ""
        } else if let page = item.page {
            brief = Study.brief(from: try await HelperBrain.ask(Study.briefPrompt(for: page, topic: topic.name), schema: Study.briefSchema))
            brief.source = page.url.absoluteString; brief.channel = page.site; brief.image = page.image?.absoluteString ?? ""
        } else { throw AssistError.message(L("Nothing to write from.")) }
        return brief
    }

    private func saveSaved() {
        try? FileManager.default.createDirectory(at: Self.place, withIntermediateDirectories: true)
        try? JSONEncoder().encode(saved).write(to: Self.savedFile, options: .atomic)
    }

    /// A note from your own words or what you pasted (a recipe, notes, a transcript), in the topic's style.
    func write(words: String) {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !writing.contains("words"), folder != nil || chooseFolder(), let folder else { return }
        let topic = topic
        writing.insert("words"); failure = nil
        Task {
            defer { writing.remove("words") }
            do {
                if topic.kind == .recipes {
                    let recipe = Study.recipe(from: try await HelperBrain.ask(Study.prompt(for: words), schema: Study.schema))
                    try save(Study.note(recipe, added: today), titled: recipe.title, in: folder)
                } else {
                    let brief = Study.brief(from: try await HelperBrain.ask(Study.briefPrompt(for: words, topic: topic.name), schema: Study.briefSchema))
                    try save(Study.note(brief, topic: topic.name, added: today), titled: brief.title, in: folder)
                }
            } catch { failure = describe(error) }
        }
    }

    private var today: String { Date().formatted(.iso8601.year().month().day()) }

    /// Written as a new note, never over one already there; it opens in the notes stage.
    @discardableResult private func save(_ text: String, titled title: String, in folder: URL) throws -> URL {
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let file = folder.appendingPathComponent(Study.fileName(for: title, taken: taken))
        try Data(text.utf8).write(to: file, options: .withoutOverwriting)
        written = file
        note = file; stage = "notes"
        reload()
        return file
    }

    /// A note opened in the notes stage.
    func show(_ file: URL) { note = file; stage = "notes" }

    /// Where a note stands, written into its header.
    func set(_ status: String, for entry: Study.Entry) {
        guard let data = try? Data(contentsOf: entry.file) else { return }
        let text = Study.setting("status", to: status, in: String(decoding: data, as: UTF8.self))
        do { try Data(text.utf8).write(to: entry.file, options: .atomic); reload() } catch { failure = error.localizedDescription }
    }

    // MARK: Network

    func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            let reason = Study.failure(in: data)
            if reason == "quotaExceeded" { throw AssistError.message(L("Today's YouTube searches are used up (about 100 a day on a free key); they come back at midnight Pacific time.")) }
            throw AssistError.message(L("YouTube: %@", reason ?? "HTTP \(status)"))
        }
        return data
    }

    /// A web page read plainly, as any program asks for it; one that refuses is reported, not worked around.
    private func read(_ url: URL) async throws -> Study.Page {
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 400).contains(status) else { throw AssistError.message(L("the site answered %@", "HTTP \(status)")) }
        guard data.count < 10_000_000 else { throw AssistError.message(L("the page is too large")) }
        return Study.page(fromHTML: String(decoding: data, as: UTF8.self), url: response.url ?? url)
    }

    /// The page's schema.org Recipe, or nil (not a recipe page, refused, or too slow).
    private func recipePage(_ url: URL) async -> [String: Any]? {
        guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15)),
              ((response as? HTTPURLResponse)?.statusCode ?? 0) < 400, data.count < 8_000_000 else { return nil }
        return Study.recipeData(inHTML: String(decoding: data, as: UTF8.self))
    }

    func describe(_ error: Error) -> String {
        if case AssistError.message(let text) = error { return text }
        return error.localizedDescription
    }
}
