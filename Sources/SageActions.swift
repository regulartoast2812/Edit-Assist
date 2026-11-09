import Foundation

/// Sage does things for you from the chat (you asked for it, 2026-11-09): he connects your vault (from Obsidian's own
/// list of vaults), sets a topic's folder, makes, renames and opens topics; finds and reads any note in the vault; and
/// writes, adds to, marks, moves and renames notes. Each change says what it did and can be undone, a step at a time,
/// only while nothing has changed it since. Nothing here deletes a note. Foundation only, like `Study`.
extension Study {
    // MARK: Obsidian's vaults

    /// A vault Obsidian knows (its list in obsidian.json): Sage reads the list only when you ask him to connect one.
    struct KnownVault: Equatable {
        var name: String, path: String
        var open = false
    }

    static var obsidianList: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
    }

    /// The vaults in Obsidian's list, the one it has open first.
    static func knownVaults(in data: Data) -> [KnownVault] {
        guard let vaults = json(data)?["vaults"] as? [String: Any] else { return [] }
        return vaults.values.compactMap { $0 as? [String: Any] }.compactMap { vault -> KnownVault? in
            guard let path = vault["path"] as? String, !path.isEmpty else { return nil }
            return KnownVault(name: URL(fileURLWithPath: path).lastPathComponent, path: path, open: vault["open"] as? Bool ?? false)
        }.sorted { ($0.open ? 0 : 1, $0.name.lowercased()) < ($1.open ? 0 : 1, $1.name.lowercased()) }
    }

    /// The vault your words mean: its name or path; with none (or words that match none), the only one, else the one
    /// Obsidian has open.
    static func vault(named words: String, in known: [KnownVault]) -> KnownVault? {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !words.isEmpty, let found = known.first(where: { $0.path.lowercased() == words || $0.name.lowercased() == words })
            ?? known.first(where: { $0.name.lowercased().contains(words) || words.contains($0.name.lowercased()) }) { return found }
        return known.count == 1 ? known[0] : known.first(where: \.open)
    }

    // MARK: The whole vault

    /// A note anywhere in the vault: its path in the vault ("Cooking/Adobo.md") and its name.
    struct VaultNote: Equatable {
        var path: String
        var title: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
    }

    /// Every note and folder in the vault, by their paths in it (hidden folders, .obsidian and .trash left out).
    static func contents(ofVault vault: URL, limit: Int = 40000) -> (notes: [VaultNote], folders: [String]) {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let walker = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return ([], []) }
        var notes: [VaultNote] = [], folders: [String] = []
        for case let url as URL in walker {
            if notes.count + folders.count >= limit { break }
            let path = relative(url, to: vault)
            if (try? url.resourceValues(forKeys: Set(keys)).isDirectory) == true { folders.append(path) }
            else if url.pathExtension.lowercased() == "md" { notes.append(VaultNote(path: path)) }
        }
        return (notes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }, folders.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    /// A file's path in the vault.
    static func relative(_ url: URL, to vault: URL) -> String {
        let base = vault.standardizedFileURL.resolvingSymlinksInPath().path, path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : path
    }

    /// A note found for your words, and the line in it that has them (empty when its name matched).
    struct Hit: Equatable {
        var path: String, line = ""
    }

    /// Notes whose name or folder has your words (the most words first), then notes whose text has all of them (with the
    /// line it's on), at most `count`. Reading notes stops at the deadline, so a big vault never keeps you waiting.
    static func find(_ words: String, in notes: [VaultNote], vault: URL, count: Int = 15, until deadline: Date = Date().addingTimeInterval(5)) -> [Hit] {
        let terms = words.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 1 }
        guard !terms.isEmpty else { return [] }
        let named = notes.map { note in (note, terms.filter { note.path.lowercased().contains($0) }.count) }.filter { $0.1 > 0 }
        var hits = named.sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0.path.count < $1.0.path.count) }.prefix(count).map { Hit(path: $0.0.path) }
        let taken = Set(hits.map(\.path))
        for note in notes where !taken.contains(note.path) {
            if hits.count >= count || Date() > deadline { break }
            let file = vault.appendingPathComponent(note.path)
            guard ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) < 500_000, let data = try? Data(contentsOf: file) else { continue }
            let text = String(decoding: data, as: UTF8.self), lowered = text.lowercased()
            guard terms.allSatisfy({ lowered.contains($0) }) else { continue }
            let line = text.split(whereSeparator: \.isNewline).first { line in terms.contains { line.lowercased().contains($0) } }
            hits.append(Hit(path: note.path, line: line.map { String($0.trimmingCharacters(in: .whitespaces).prefix(160)) } ?? ""))
        }
        return hits
    }

    /// The note your words name: its path in the vault, or its name (as a [[link]] would), case aside.
    static func resolve(_ words: String, in notes: [VaultNote]) -> VaultNote? {
        var name = words.trimmingCharacters(in: CharacterSet(charactersIn: " []\"'“”\n")).lowercased()
        if name.hasSuffix(".md") { name = String(name.dropLast(3)) }
        if let bar = name.firstIndex(of: "|") { name = String(name[..<bar]) }
        guard !name.isEmpty else { return nil }
        return notes.first { $0.path.lowercased() == name + ".md" }
            ?? notes.first { $0.title.lowercased() == name }
            ?? notes.first { $0.path.lowercased().hasSuffix("/" + name + ".md") }
    }

    /// The folder your words name, by its path in the vault or its name; "" is the vault itself. Nil when there is none.
    static func folder(_ words: String, in folders: [String]) -> String? {
        let name = words.trimmingCharacters(in: CharacterSet(charactersIn: " /\"'“”")).lowercased()
        if name.isEmpty { return "" }
        return folders.first { $0.lowercased() == name } ?? folders.first { ($0 as NSString).lastPathComponent.lowercased() == name }
    }

    /// A folder path from your words that no file system refuses: each part cleaned as a file name is.
    static func folderPath(_ words: String) -> String {
        words.split(separator: "/").map { part in
            part.map { "<>:\"\\|?*#^[]".contains($0) || $0.isNewline ? " " : $0 }.reduce(into: "") { $0.append($1) }
                .split(separator: " ").joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        }.filter { !$0.isEmpty }.joined(separator: "/")
    }

    // MARK: What he can do

    /// One thing to do: what (`kind`), on what (`target`: a note, a folder or a topic), to what (`value`), with what text.
    struct Action: Equatable {
        var kind = "", target = "", value = "", text = ""
    }

    static let actionKinds = ["connect_vault", "open_topic", "new_topic", "rename_topic", "set_folder", "write_note", "append", "set_status", "move", "rename", "show", "agent"]

    static var actionSchema: [String: Any] {
        let text: [String: Any] = ["type": "string"]
        let properties: [String: Any] = ["kind": ["type": "string", "enum": actionKinds], "target": text, "value": text, "text": text]
        return ["type": "array", "items": ["type": "object", "additionalProperties": false, "required": properties.keys.sorted(), "properties": properties]]
    }

    static func actions(from answer: [String: Any]) -> [Action] {
        (answer["actions"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.compactMap { item in
            let text = { (key: String) in (item[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            let kind = text("kind")
            guard actionKinds.contains(kind) else { return nil }
            return Action(kind: kind, target: text("target"), value: text("value"), text: (item["text"] as? String ?? "").trimmingCharacters(in: .newlines))
        }
    }

    /// What he can do, what he has, and what he looked up or did this turn: added to the chat's question.
    static func abilitiesPrompt(vault: String, known: [KnownVault], topics: [Topic], current: Topic, folders: [String],
                                findWords: String, found: [Hit]?, read: [(path: String, text: String)], done: [String], last: Bool) -> String {
        var text = """

        You can also do things for me in my Obsidian vault and in this app. Put them in `actions` only when I ask for them (or clearly \
        agree to one you offered), never on your own; otherwise leave `actions` empty. Each action has `kind`, `target`, `value` and \
        `text` (use "" for what it doesn't need). Paths are inside the vault, with "/" between folders.
        - connect_vault: connect my vault. value = its name or path from Obsidian's list below ("" = the one Obsidian has open).
        - open_topic: switch to a topic. value = its name.
        - new_topic: make a topic and switch to it. value = its name; text = "recipes" for a recipe topic, else "general"; target = its \
        folder in the vault (optional; made if missing).
        - rename_topic: target = the topic's name ("" = this one); value = the new name.
        - set_folder: set a topic's folder in the vault, where its notes are kept and written. target = the topic ("" = this one); \
        value = the folder's path (made if missing).
        - write_note: write a new note. value = its title; text = the note in Markdown (a YAML header is added when it has none); \
        target = the folder ("" = this topic's folder). An existing note is never overwritten.
        - append: add to the end of a note. target = the note (its path or name); text = the Markdown to add.
        - set_status: target = the note; value = its status (for this topic: \(current.statuses.joined(separator: ", "))).
        - move: target = the note; value = the folder to move it to (made if missing).
        - rename: target = the note; value = its new name. Links to it in other notes follow, as Obsidian does.
        - show: open a note in the Notes stage. target = the note.
        - agent: hand the work to your agent, which has real tools in my vault (Vault Agent's: it reads, edits and writes any \
        files, runs commands, searches across notes, browses the web, and follows my vault's CLAUDE.md conventions and memories). \
        Use it when I ask for something your own actions can't do: process, rewrite or clean up a note, fix its frontmatter, add \
        links, edit several notes, research across many files, fetch something from the web into a note, remember something for \
        later. text = the whole instruction for it, self-contained (which note, by its path, and everything it needs from our \
        chat); target and value = "". Put it alone in `actions` and say in `reply`, in a few words, that you're handing it over.
        You can't delete notes or folders: if I ask, say so and offer to move them instead. When I ask for something you aren't \
        sure about (which note, which folder), ask me first instead of guessing.

        To look in the whole vault, put words in `find` (searches note names and their text) and/or paths in `read` (notes to \
        read in full, at most 5); you then get them and answer again.

        """
        if vault.isEmpty {
            text += known.isEmpty
                ? "No vault is connected and Obsidian lists none on this Mac: if I want one, tell me to choose a topic's folder at the top of the page.\n"
                : "No vault is connected yet. Obsidian's list of vaults:\n" + known.map { "- \($0.name) | \($0.path)\($0.open ? " | open in Obsidian" : "")" }.joined(separator: "\n") + "\n"
        } else {
            text += "My vault: \(vault)\n"
            if !folders.isEmpty {
                let shown = folders.filter { $0.split(separator: "/").count <= 3 }.prefix(300)
                text += "Its folders (\(folders.count) in all\(shown.count < folders.count ? ", up to 3 deep" : "")):\n" + shown.map { "- \($0)" }.joined(separator: "\n") + "\n"
            }
        }
        text += "My topics:\n" + topics.map { "- \($0.name) | \($0.kind == .recipes ? "recipes" : "general") | folder: \($0.folder.isEmpty ? "not chosen" : $0.folder)\($0.id == current.id ? " | open now" : "")" }.joined(separator: "\n") + "\n"
        if let found {
            text += "\nIn my vault for \"\(findWords)\":\n" + (found.isEmpty ? "(nothing found)" : found.map { "- \($0.path)\($0.line.isEmpty ? "" : " | \($0.line)")" }.joined(separator: "\n")) + "\n"
        }
        for note in read { text += "\nMy note \(note.path):\n" + String(note.text.prefix(8000)) + "\n" }
        if !done.isEmpty {
            text += "\nWhat you did this turn (tell me in `reply`, plainly; say what failed and why; don't do it again):\n" + done.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if last { text += "\nAnswer now: leave `find`, `read` and `actions` empty.\n" }
        return text
    }

    // MARK: Changing notes, safely

    /// A note's text, and whether it starts with a byte-order mark (kept when it's written again).
    static func noteText(_ data: Data) -> (text: String, bom: Bool) {
        let bom = data.starts(with: [0xEF, 0xBB, 0xBF])
        return (String(decoding: bom ? data.dropFirst(3) : data[...], as: UTF8.self), bom)
    }

    static func noteData(_ text: String, bom: Bool) -> Data { (bom ? Data([0xEF, 0xBB, 0xBF]) : Data()) + Data(text.utf8) }

    /// The note with text added at its end after a blank line, in the note's own line endings.
    static func adding(_ more: String, to text: String) -> String {
        let crlf = text.contains("\r\n")
        var body = text
        while let last = body.last, last.isNewline { body.removeLast() }
        let result = (body.isEmpty ? "" : body + "\n\n") + more.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .newlines) + "\n"
        return crlf ? result.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n") : result
    }

    /// The note with one header value set (`setting`), in the note's own line endings.
    static func setting(_ key: String, to value: String, keepingEndingsIn text: String) -> String {
        guard text.contains("\r\n") else { return setting(key, to: value, in: text) }
        return setting(key, to: value, in: text.replacingOccurrences(of: "\r\n", with: "\n")).replacingOccurrences(of: "\n", with: "\r\n")
    }

    /// Links to a renamed note follow it, as Obsidian's "update internal links" does: [[Old]], [[Old|shown]], [[Old#part]],
    /// ![[Old]] and [[folder/Old]] (its folder kept). Other links and text are left as written.
    static func relinked(_ text: String, from old: String, to new: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]\|#\n]+)([#|][^\]\n]*)?\]\]"#) else { return text }
        let result = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).reversed() {
            let range = match.range(at: 1)
            let target = (text as NSString).substring(with: range)
            let markdown = target.lowercased().hasSuffix(".md")
            let name = markdown ? String(target.dropLast(3)) : target
            let folder = (name as NSString).deletingLastPathComponent, last = (name as NSString).lastPathComponent
            guard last.trimmingCharacters(in: .whitespaces).lowercased() == old.lowercased() else { continue }
            result.replaceCharacters(in: range, with: (folder.isEmpty ? "" : folder + "/") + new + (markdown ? ".md" : ""))
        }
        return result as String
    }

    /// Writes a note's new text in one step through a hidden file beside it, so the note keeps its dates.
    static func replace(_ file: URL, with data: Data) throws {
        let temp = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).sage-\(UUID().uuidString.prefix(8))")
        try data.write(to: temp)
        do { _ = try FileManager.default.replaceItemAt(file, withItemAt: temp) } catch { try? FileManager.default.removeItem(at: temp); throw error }
    }

    /// A copy of the note as it was, kept before Sage first changes it (in `folder`/edited/, 30 days).
    static func keep(_ data: Data, of file: URL, in folder: URL, now: Date = Date()) {
        let edited = folder.appendingPathComponent("edited", isDirectory: true)
        try? FileManager.default.createDirectory(at: edited, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate, .withTime]).replacingOccurrences(of: ":", with: "")
        try? data.write(to: edited.appendingPathComponent("\(stamp) \(file.lastPathComponent)"))
        let old = now.addingTimeInterval(-30 * 86_400)
        for item in (try? FileManager.default.contentsOfDirectory(at: edited, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let date = try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < old { try? FileManager.default.removeItem(at: item) }
        }
    }

    /// A change to the vault, kept to undo it.
    enum Change: Equatable {
        case created(URL, Data)
        case edited(URL, before: Data, after: Data)
        case moved(from: URL, to: URL)
        case madeFolder(URL)
        /// A file that was there before (its bytes) and isn't now: the agent removed it.
        case removed(URL, Data)

        var file: URL {
            switch self {
            case let .created(file, _), let .edited(file, _, _), let .moved(_, file), let .madeFolder(file), let .removed(file, _): return file
            }
        }
    }

    /// Undoes one change if nothing has changed it since (the note still reads as Sage left it, the moved note is still
    /// where he put it, the folder he made is still empty); false, leaving it as it is, when something has.
    static func undo(_ change: Change) -> Bool {
        let manager = FileManager.default
        switch change {
        case let .created(file, data):
            guard (try? Data(contentsOf: file)) == data else { return false }
            return (try? manager.removeItem(at: file)) != nil
        case let .edited(file, before, after):
            guard (try? Data(contentsOf: file)) == after else { return false }
            return (try? replace(file, with: before)) != nil
        case let .moved(from, to):
            guard manager.fileExists(atPath: to.path), !manager.fileExists(atPath: from.path) else { return false }
            return (try? manager.moveItem(at: to, to: from)) != nil
        case let .madeFolder(folder):
            guard let items = try? manager.contentsOfDirectory(atPath: folder.path), items.allSatisfy({ $0.hasPrefix(".") }) else { return false }
            return (try? manager.removeItem(at: folder)) != nil
        case let .removed(file, data):
            guard !manager.fileExists(atPath: file.path) else { return false }
            try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            return (try? data.write(to: file, options: .withoutOverwriting)) != nil
        }
    }

    /// Makes the folder (and the ones it's in) when missing; the changes made, the outermost first (undone innermost first).
    static func make(_ folder: URL) throws -> [Change] {
        var missing: [URL] = [], place = folder.standardizedFileURL
        while !FileManager.default.fileExists(atPath: place.path) { missing.insert(place, at: 0); place = place.deletingLastPathComponent() }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return missing.map { .madeFolder($0) }
    }
}

// MARK: - The desk doing it

/// A step Sage can undo: a change to the vault, or to the app's topics and vault.
enum SageUndo: Equatable {
    case file(Study.Change)
    case topicAdded(UUID)
    case topicRenamed(UUID, from: String)
    case topicFolder(UUID, from: String)
    case vault(from: String)
}

@MainActor
extension SageDesk {
    /// The vault he works in: the Notes stage's (chosen there or connected from the chat), else the one a topic's folder is in.
    var workVault: URL? {
        if let chosen = vault.vault { return chosen }
        return folder.flatMap(Study.vault(of:)) ?? topics.lazy.compactMap { $0.folder.isEmpty ? nil : Study.vault(of: URL(fileURLWithPath: $0.folder, isDirectory: true)) }.first
    }

    /// Obsidian's list of vaults, read when the chat needs it.
    nonisolated static func knownVaults() -> [Study.KnownVault] {
        (try? Data(contentsOf: Study.obsidianList)).map(Study.knownVaults(in:)) ?? []
    }

    /// The vault's notes and folders, read off the main thread.
    func vaultContents() async -> (notes: [Study.VaultNote], folders: [String]) {
        guard let vault = workVault else { return ([], []) }
        return await Task.detached { Study.contents(ofVault: vault) }.value
    }

    func topicNamed(_ words: String) -> Study.Topic? {
        let name = words.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.isEmpty { return topic }
        return topics.first { $0.name.lowercased() == name } ?? topics.first { $0.name.lowercased().contains(name) || name.contains($0.name.lowercased()) }
    }

    /// Does what he was asked: what happened (for you and, in English, for him), and how to undo it.
    func perform(_ actions: [Study.Action]) async -> (shown: [String], told: [String], undo: [SageUndo]) {
        var shown: [String] = [], told: [String] = [], undo: [SageUndo] = []
        var contents = await vaultContents()
        var kept = Set<String>()
        // A line said both ways: in your language on screen, in English to him.
        func say(_ format: String, _ values: CustomStringConvertible...) {
            var english = format
            for value in values { if let slot = english.range(of: "%@") { english.replaceSubrange(slot, with: value.description) } }
            told.append(english)
            var local = L(format)
            for value in values { if let slot = local.range(of: "%@") { local.replaceSubrange(slot, with: value.description) } }
            shown.append(local)
        }
        func folderURL(_ path: String, in vault: URL) -> URL { path.isEmpty ? vault : vault.appendingPathComponent(path, isDirectory: true) }
        /// The note changed in one step, a copy kept first.
        func change(_ file: URL, _ edit: (String) -> String) throws -> Bool {
            let data = try Data(contentsOf: file)
            let (text, bom) = Study.noteText(data)
            let after = Study.noteData(edit(text), bom: bom)
            guard after != data else { return false }
            if !kept.contains(file.path) { Study.keep(data, of: file, in: Self.place); kept.insert(file.path) }
            try Study.replace(file, with: after)
            undo.append(.file(.edited(file, before: data, after: after)))
            return true
        }

        for action in actions {
            let vault = workVault
            do {
                switch action.kind {
                case "connect_vault":
                    let known = Self.knownVaults()
                    guard let found = Study.vault(named: action.value, in: known) else {
                        say(known.isEmpty ? "Couldn't connect a vault: Obsidian lists none on this Mac" : "Couldn't tell which vault “%@” is", action.value); continue
                    }
                    guard FileManager.default.fileExists(atPath: found.path) else { say("Couldn't connect “%@”: its folder isn't there (%@)", found.name, found.path); continue }
                    let before = self.vault.vault?.path ?? ""
                    guard self.vault.use(URL(fileURLWithPath: found.path, isDirectory: true)) else { say("Couldn't connect “%@”: it isn't an Obsidian vault (no .obsidian folder)", found.name); continue }
                    undo.append(.vault(from: before))
                    contents = await vaultContents()
                    say("Connected your vault “%@”", found.name)

                case "open_topic":
                    guard let topic = topicNamed(action.value) else { say("Couldn't find the topic “%@”", action.value); continue }
                    open(topic: topic.id)
                    say("Opened the topic “%@”", topic.name)

                case "new_topic":
                    let name = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    if let existing = topics.first(where: { $0.name.lowercased() == name.lowercased() }) {
                        open(topic: existing.id); say("The topic “%@” was there already: opened it", existing.name); continue
                    }
                    add(topic: name, kind: action.text.lowercased().hasPrefix("recipe") ? .recipes : .general)
                    undo.append(.topicAdded(topic.id))
                    say("Made the topic “%@”", name)
                    if !action.target.isEmpty, let vault {
                        let path = Study.folder(action.target, in: contents.folders) ?? Study.folderPath(action.target)
                        undo += try Study.make(folderURL(path, in: vault)).map(SageUndo.file)
                        setFolder(folderURL(path, in: vault).path, for: topic.id)
                        say("Set “%@”'s folder to %@", name, path.isEmpty ? L("the vault") : path)
                    }

                case "rename_topic":
                    let name = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, let topic = topicNamed(action.target) else { say("Couldn't find the topic “%@”", action.target); continue }
                    undo.append(.topicRenamed(topic.id, from: topic.name))
                    rename(topic: topic.id, to: name)
                    say("Renamed the topic “%@” to “%@”", topic.name, name)

                case "set_folder":
                    guard let vault else { say("Couldn't set a folder: no vault is connected"); continue }
                    guard let topic = topicNamed(action.target) else { say("Couldn't find the topic “%@”", action.target); continue }
                    let path = Study.folder(action.value, in: contents.folders) ?? Study.folderPath(action.value)
                    let made = try Study.make(folderURL(path, in: vault))
                    undo += made.map(SageUndo.file)
                    undo.append(.topicFolder(topic.id, from: topic.folder))
                    setFolder(folderURL(path, in: vault).path, for: topic.id)
                    if !made.isEmpty { contents = await vaultContents() }
                    if !made.isEmpty { say("Made the folder %@", path) }
                    say("Set “%@”'s folder to %@", topic.name, path.isEmpty ? L("the vault") : path)

                case "write_note":
                    guard let vault else { say("Couldn't write “%@”: no vault is connected", action.value); continue }
                    let title = action.value.isEmpty ? L("Untitled") : action.value
                    let place: URL
                    if action.target.isEmpty, let folder { place = folder } else {
                        place = folderURL(Study.folder(action.target, in: contents.folders) ?? Study.folderPath(action.target), in: vault)
                    }
                    undo += try Study.make(place).map(SageUndo.file)
                    var text = action.text
                    if !text.hasPrefix("---") {
                        let inTopic = place.standardizedFileURL.path == folder?.standardizedFileURL.path
                        var header = "---\ntitle: \(Study.quoted(title))\n"
                        if inTopic, let status = topic.statuses.first { header += "status: \(status)\n" }
                        header += "added: \(Date().formatted(.iso8601.year().month().day()))\n---\n\n"
                        text = header + text
                    }
                    if !text.hasSuffix("\n") { text += "\n" }
                    let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: place.path)) ?? [])
                    let file = place.appendingPathComponent(Study.fileName(for: title, taken: taken))
                    let data = Data(text.utf8)
                    try data.write(to: file, options: .withoutOverwriting)
                    undo.append(.file(.created(file, data)))
                    contents.notes.append(Study.VaultNote(path: Study.relative(file, to: vault)))
                    say("Wrote “%@” in %@", file.deletingPathExtension().lastPathComponent, Study.relative(place, to: vault).isEmpty || place == vault ? L("the vault") : Study.relative(place, to: vault))

                case "append", "set_status", "show", "move", "rename":
                    guard let vault else { say("Couldn't find “%@”: no vault is connected", action.target); continue }
                    guard let note = Study.resolve(action.target, in: contents.notes) else { say("Couldn't find the note “%@”", action.target); continue }
                    let file = vault.appendingPathComponent(note.path)
                    switch action.kind {
                    case "append":
                        guard !action.text.isEmpty else { continue }
                        _ = try change(file) { Study.adding(action.text, to: $0) }
                        say("Added to “%@”", note.title)
                    case "set_status":
                        let status = action.value.lowercased()
                        guard !status.isEmpty else { continue }
                        let changed = try change(file) { Study.setting("status", to: status, keepingEndingsIn: $0) }
                        say(changed ? "Marked “%@” %@" : "“%@” was already %@", note.title, status)
                    case "show":
                        show(file)
                        say("Opened “%@” in Notes", note.title)
                    case "move":
                        let path = Study.folder(action.value, in: contents.folders) ?? Study.folderPath(action.value)
                        let place = folderURL(path, in: vault)
                        guard place.standardizedFileURL.path != file.deletingLastPathComponent().standardizedFileURL.path else { say("“%@” is in %@ already", note.title, path.isEmpty ? L("the vault") : path); continue }
                        undo += try Study.make(place).map(SageUndo.file)
                        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: place.path)) ?? [])
                        guard !taken.contains(where: { $0.lowercased() == file.lastPathComponent.lowercased() }) else { say("Couldn't move “%@”: %@ has a note with that name", note.title, path.isEmpty ? L("the vault") : path); continue }
                        let moved = place.appendingPathComponent(file.lastPathComponent)
                        try FileManager.default.moveItem(at: file, to: moved)
                        undo.append(.file(.moved(from: file, to: moved)))
                        contents = await vaultContents()
                        self.vault.repath([note.path: Study.relative(moved, to: vault)])
                        say("Moved “%@” to %@", note.title, path.isEmpty ? L("the vault") : path)
                    default: // rename
                        let place = file.deletingLastPathComponent()
                        let taken = Set(((try? FileManager.default.contentsOfDirectory(atPath: place.path)) ?? []).filter { $0.lowercased() != file.lastPathComponent.lowercased() })
                        let name = Study.fileName(for: action.value, taken: taken)
                        let renamed = place.appendingPathComponent(name)
                        let new = (name as NSString).deletingPathExtension
                        guard new != note.title else { continue }
                        try FileManager.default.moveItem(at: file, to: renamed)
                        undo.append(.file(.moved(from: file, to: renamed)))
                        // Its header's title follows when it was the old name.
                        if Study.header(of: Study.noteText((try? Data(contentsOf: renamed)) ?? Data()).text)["title"]?.first == note.title {
                            _ = try change(renamed) { Study.setting("title", to: Study.quoted(new), keepingEndingsIn: $0) }
                        }
                        // Links to it in other notes follow.
                        var relinked = 0
                        let others = contents.notes.filter { $0.path != note.path }
                        let old = note.title
                        for other in others {
                            let otherFile = vault.appendingPathComponent(other.path)
                            guard let data = try? Data(contentsOf: otherFile), String(decoding: data, as: UTF8.self).range(of: "[[", options: .literal) != nil,
                                  String(decoding: data, as: UTF8.self).range(of: old, options: .caseInsensitive) != nil else { continue }
                            if try change(otherFile, { Study.relinked($0, from: old, to: new) }) { relinked += 1 }
                        }
                        contents = await vaultContents()
                        self.vault.repath([note.path: Study.relative(renamed, to: vault)])
                        say(relinked == 0 ? "Renamed “%@” to “%@”" : "Renamed “%@” to “%@” (links in %@ notes follow it)", old, new, relinked)
                    }
                default: continue
                }
            } catch {
                say("Couldn't do “%@” for “%@”: %@", action.kind.replacingOccurrences(of: "_", with: " "), action.target.isEmpty ? action.value : action.target, error.localizedDescription)
            }
        }
        if undo.contains(where: { if case .file = $0 { return true }; return false }) { reload() }
        return (shown, told, undo)
    }

    /// Undoes what he did for one message, the last step first; a step something has changed since is left as it is.
    func undo(_ message: UUID) {
        guard let steps = undos.removeValue(forKey: message), let id = current else { return }
        var left: [String] = []
        for step in steps.reversed() {
            switch step {
            case let .file(change):
                if !Study.undo(change) { left.append(change.file.lastPathComponent) }
                if case let .moved(from, to) = change, let root = workVault { vault.repath([Study.relative(to, to: root): Study.relative(from, to: root)]) }
            case let .topicAdded(topic): remove(topic: topic)
            case let .topicRenamed(topic, from): rename(topic: topic, to: from)
            case let .topicFolder(topic, from): setFolder(from, for: topic)
            case let .vault(from): if !from.isEmpty { vault.use(URL(fileURLWithPath: from, isDirectory: true)) }
            }
        }
        reload()
        append(Study.Message(fromSage: true, text: left.isEmpty ? L("Undone.") : L("Undone, except what has changed since: %@", left.joined(separator: ", "))), to: id)
    }
}
