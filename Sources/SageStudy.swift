import Foundation

/// Sage's logic, free of the Mac (Foundation only), so the Windows app can take it as it is (2026-11-06): finding recipe
/// videos with YouTube's Data API on your key, reading the recipe a video links to (the page's schema.org Recipe, which
/// recipe sites publish for programs to read), and the recipe notes in your Obsidian vault: written as Markdown with a
/// YAML header, read back and tracked by their `status`. Personal: nothing here touches Crossian's work.
/// How it fits together for the port: docs/sage/README.md.
enum Study {
    // MARK: YouTube (Data API v3: a search costs 100 of the key's 10,000 free units a day, a video's details 1)

    static let api = URL(string: "https://www.googleapis.com/youtube/v3/")!

    struct Video: Identifiable, Equatable, Codable {
        var id: String
        var title = "", channel = "", published = "", description = ""
        var thumbnail: URL?
        var duration = ""
        var views: Int?
        /// Likes and comments, for Pick's signals (2026-11-06); left out of saved.json when unknown.
        var likes: Int?
        var comments: Int?
        var url: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    }

    static func url(_ path: String, _ items: [(String, String)], key: String) -> URL {
        var parts = URLComponents(url: api.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        parts.queryItems = (items + [("key", key)]).map { URLQueryItem(name: $0.0, value: $0.1) }
        return parts.url!
    }

    /// Videos for the words, most relevant first.
    static func searchURL(_ words: String, key: String, count: Int = 24) -> URL {
        url("search", [("part", "snippet"), ("type", "video"), ("maxResults", "\(count)"), ("q", words), ("safeSearch", "none")], key: key)
    }

    /// A video saved in the app to review: dropped on the save area or picked by Sage. Its recipe is written into the vault
    /// only when you ask (`written` is then the note's path).
    struct Saved: Codable, Equatable, Identifiable {
        /// A YouTube video, or a web page.
        var video: Video?
        var page: Page?
        /// Why Sage picked it; empty for one you saved.
        var why = ""
        var added = Date()
        var written = ""
        /// The topic it was saved in (nil: saved before there were topics, so the first one).
        var topic: UUID?

        var id: String { video?.id ?? page?.url.absoluteString ?? "" }
        var title: String { video?.title ?? (page.map { $0.title.isEmpty ? $0.url.absoluteString : $0.title } ?? "") }
        var link: URL? { video?.url ?? page?.url }
        var thumbnail: URL? { video?.thumbnail ?? page?.image }
        var origin: String { video.map { [$0.channel, $0.duration].filter { !$0.isEmpty }.joined(separator: " · ") } ?? page?.site ?? "" }

        init(video: Video? = nil, page: Page? = nil, why: String = "", topic: UUID? = nil) {
            self.video = video; self.page = page; self.why = why; self.topic = topic
        }
    }

    /// Your words as a recipe search: "chicken" finds songs and farm videos, "chicken recipe" finds cooking.
    static func recipeSearch(_ words: String) -> String {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = words.lowercased()
        return ["recipe", "how to", "cook", "bake", "make"].contains(where: lowered.contains) ? words : words + " recipe"
    }

    // MARK: Video details (Pick for me lives in SagePick.swift)

    /// Each video's title, channel, description, length and views.
    static func videosURL(_ ids: [String], key: String) -> URL {
        url("videos", [("part", "snippet,contentDetails,statistics"), ("id", ids.joined(separator: ",")), ("maxResults", "50")], key: key)
    }

    /// The video ids in a search answer, in its order.
    static func ids(inSearch data: Data) -> [String] {
        items(data).compactMap { ($0["id"] as? [String: Any])?["videoId"] as? String }
    }

    static func videos(in data: Data) -> [Video] {
        items(data).compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let snippet = item["snippet"] as? [String: Any] ?? [:]
            let thumbnails = snippet["thumbnails"] as? [String: Any] ?? [:]
            let thumbnail = ["high", "medium", "default"].lazy.compactMap { (thumbnails[$0] as? [String: Any])?["url"] as? String }.first
            let statistics = item["statistics"] as? [String: Any]
            let count = { (key: String) in (statistics?[key] as? String).flatMap { Int($0) } }
            return Video(id: id, title: text(snippet["title"]), channel: text(snippet["channelTitle"]), published: String(text(snippet["publishedAt"]).prefix(10)),
                         description: text(snippet["description"]), thumbnail: thumbnail.flatMap(URL.init(string:)),
                         duration: duration((item["contentDetails"] as? [String: Any])?["duration"] as? String ?? ""),
                         views: count("viewCount"), likes: count("likeCount"), comments: count("commentCount"))
        }
    }

    /// YouTube's ISO 8601 length as a clock: PT1H2M3S → 1:02:03, PT75S → 1:15.
    static func duration(_ iso: String) -> String {
        var seconds = 0, number = 0
        for character in iso {
            if let digit = character.wholeNumberValue { number = number * 10 + digit; continue }
            switch character {
            case "H": seconds += number * 3600
            case "M": seconds += number * 60
            case "S": seconds += number
            default: break
            }
            number = 0
        }
        guard seconds > 0 else { return "" }
        let (h, m, s) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// YouTube's reason for a refused call ("API key not valid…", "quota exceeded"), or nil.
    static func failure(in data: Data) -> String? {
        let error = (json(data))?["error"] as? [String: Any]
        let reason = ((error?["errors"] as? [[String: Any]])?.first?["reason"] as? String) ?? ""
        if reason == "quotaExceeded" { return "quotaExceeded" }
        return error?["message"] as? String
    }

    // MARK: The recipe a video links to

    /// Sites that never hold the recipe itself.
    static let notRecipes = ["youtube.com", "youtu.be", "instagram.com", "facebook.com", "tiktok.com", "twitter.com", "x.com", "threads.net",
                             "amazon.", "amzn.", "patreon.com", "pinterest.", "spotify.com", "apple.com", "discord.", "linktr.ee", "shopmy.", "ltk.app"]

    /// The links in a description that could be the recipe, in order, at most `count`.
    static func links(in text: String, count: Int = 4) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen: Set<String> = []
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { $0.url }
            .filter { url in
                guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host?.lowercased() else { return false }
                return !notRecipes.contains { host == $0 || host.hasSuffix("." + $0) || ($0.hasSuffix(".") && host.contains($0)) }
                    && seen.insert(url.absoluteString).inserted
            }
            .prefix(count).map { $0 }
    }

    /// The schema.org Recipe in a page's JSON-LD, as the page wrote it, or nil.
    static func recipeData(inHTML html: String) -> [String: Any]? {
        var rest = html[...]
        while let open = rest.range(of: "application/ld+json", options: .caseInsensitive),
              let start = rest[open.upperBound...].range(of: ">"),
              let end = rest[start.upperBound...].range(of: "</script>", options: .caseInsensitive) {
            let block = String(rest[start.upperBound ..< end.lowerBound])
            if let found = (try? JSONSerialization.jsonObject(with: Data(block.utf8))).flatMap(recipe(in:)) { return found }
            rest = rest[end.upperBound...]
        }
        return nil
    }

    private static func recipe(in object: Any) -> [String: Any]? {
        if let list = object as? [Any] { return list.lazy.compactMap(recipe(in:)).first }
        guard let object = object as? [String: Any] else { return nil }
        let type = object["@type"]
        if (type as? String) == "Recipe" || (type as? [String])?.contains("Recipe") == true { return object }
        return object["@graph"].flatMap(recipe(in:))
    }

    // MARK: Writing a recipe (with the helper brain: one call, no tools, a strict schema)

    struct Recipe: Equatable, Codable {
        var title = "", servings = "", prep = "", cook = "", total = "", cuisine = "", course = ""
        var tags: [String] = [], ingredients: [String] = [], steps: [String] = [], notes: [String] = []
        /// Where it came from: the video, its channel, the recipe page read.
        var source = "", channel = "", page = ""
    }

    static var schema: [String: Any] {
        let text: [String: Any] = ["type": "string"], list: [String: Any] = ["type": "array", "items": text]
        let properties: [String: Any] = ["title": text, "servings": text, "prep": text, "cook": text, "total": text, "cuisine": text, "course": text,
                                         "tags": list, "ingredients": list, "steps": list, "notes": list]
        return ["type": "object", "additionalProperties": false, "required": properties.keys.sorted(), "properties": properties]
    }

    static let rules = """
    Write it as a recipe note: a short plain title (the dish, no channel name, no "BEST"/"EASY"), servings, prep, cook and total \
    time as short text ("4", "10 min", "1 hr 20 min"), cuisine and course in a word or two, 2–6 lowercase tags (dish type, main \
    ingredient, cuisine, diet), each ingredient with its amount as one line, each step as one short instruction, and notes for tips, \
    swaps or storage. Use only what the material says: never invent amounts, times or steps. Leave a field empty ("" or []) when the \
    material doesn't give it, and when the recipe is incomplete say what is missing in one note. Write in English, in metric and US \
    units as the material gives them.
    """

    /// The question for a video: its title, channel, description and the recipe page it links to, if one was read.
    static func prompt(for video: Video, page: [String: Any]?) -> String {
        var text = "From this YouTube video, write down its recipe.\n" + rules + "\n\nVideo title: \(video.title)\nChannel: \(video.channel)\n"
            + "Description:\n" + String(video.description.prefix(6000))
        if let page, let data = try? JSONSerialization.data(withJSONObject: page, options: [.sortedKeys]) {
            text += "\n\nThe recipe page the video links to, as its schema.org Recipe (the most exact source; prefer its amounts):\n"
                + String(String(decoding: data, as: UTF8.self).prefix(20000))
        }
        return text
    }

    /// The question for your own words: a recipe you describe, paste or remember.
    static func prompt(for words: String) -> String {
        "Turn what I wrote into a recipe note. " + rules + " Here the material is my own words: you may tidy them, but keep my amounts and steps.\n\n"
            + String(words.prefix(20000))
    }

    static func recipe(from answer: [String: Any]) -> Recipe {
        let text = { (key: String) in (answer[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let list = { (key: String) in (answer[key] as? [Any] ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
        return Recipe(title: text("title"), servings: text("servings"), prep: text("prep"), cook: text("cook"), total: text("total"),
                      cuisine: text("cuisine"), course: text("course"), tags: list("tags").map(tag), ingredients: list("ingredients"),
                      steps: list("steps").map(unnumbered), notes: list("notes"))
    }

    /// A tag Obsidian takes: lowercase, words joined by "-", no "#".
    static func tag(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "#", with: "").split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" && $0 != "/" })
            .joined(separator: "-")
    }

    /// A step without the number a list will give it ("1. Mix" → "Mix").
    static func unnumbered(_ step: String) -> String {
        let digits = step.prefix { $0.isNumber }
        guard !digits.isEmpty, case let rest = step.dropFirst(digits.count), let mark = rest.first, ".)".contains(mark) else { return step }
        return rest.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    // MARK: Notes in the vault

    /// Where a recipe stands: the `status` in its note's header.
    static let statuses = ["to try", "made", "favourite"]

    /// The note as Obsidian reads it: a YAML header (properties), the video embedded, then ingredients, steps and notes.
    static func note(_ recipe: Recipe, status: String = "to try", added: String) -> String {
        var header: [(String, String)] = [("title", quoted(recipe.title)), ("status", status)]
        for (key, value) in [("source", recipe.source), ("channel", recipe.channel), ("page", recipe.page), ("servings", recipe.servings),
                             ("prep", recipe.prep), ("cook", recipe.cook), ("total", recipe.total), ("cuisine", recipe.cuisine), ("course", recipe.course)]
        where !value.isEmpty { header.append((key, quoted(value))) }
        var text = "---\n" + header.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        let tags = ["recipe"] + recipe.tags.filter { $0 != "recipe" && !$0.isEmpty }
        text += "\ntags:\n" + tags.map { "  - \($0)" }.joined(separator: "\n") + "\nadded: \(added)\n---\n\n"
        if recipe.source.contains("youtube.com/watch") { text += "![](\(recipe.source))\n\n" }
        if !recipe.ingredients.isEmpty { text += "## Ingredients\n\n" + recipe.ingredients.map { "- \($0)" }.joined(separator: "\n") + "\n\n" }
        if !recipe.steps.isEmpty { text += "## Steps\n\n" + recipe.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n") + "\n\n" }
        if !recipe.notes.isEmpty { text += "## Notes\n\n" + recipe.notes.map { "- \($0)" }.joined(separator: "\n") + "\n" }
        return text
    }

    /// A YAML string in double quotes.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ") + "\""
    }

    /// The YAML header's values: one-line values (quotes taken off) and lists (`- a` lines or `[a, b]`).
    static func header(of text: String) -> [String: [String]] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---", let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return [:] }
        var values: [String: [String]] = [:], last: String?
        for line in lines[1 ..< end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- "), let key = last { values[key, default: []].append(unquoted(String(trimmed.dropFirst(2)))); continue }
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            last = key
            if value.hasPrefix("[") && value.hasSuffix("]") {
                values[key] = value.dropFirst().dropLast().split(separator: ",").map { unquoted($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
            } else {
                values[key] = value.isEmpty ? [] : [unquoted(value)]
            }
        }
        return values
    }

    static func unquoted(_ value: String) -> String {
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
        }
        if value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") { return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
        return value
    }

    /// The note with one header value set (added when missing; a header made when the note has none). The rest is kept as written.
    static func setting(_ key: String, to value: String, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let line = "\(key): \(value)"
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) else {
            return "---\n\(line)\n---\n" + text
        }
        if let index = lines[1 ..< end].firstIndex(where: { $0.hasPrefix(key + ":") }) {
            // A list value under the key goes with it.
            var after = index + 1
            while after < end, lines[after].trimmingCharacters(in: .whitespaces).hasPrefix("- "), lines[after].hasPrefix(" ") || lines[after].hasPrefix("-") { after += 1 }
            lines.replaceSubrange(index ..< after, with: [line])
        } else {
            lines.insert(line, at: end)
        }
        return lines.joined(separator: "\n")
    }

    /// A recipe note in the folder, as its header tells it.
    struct Entry: Identifiable, Equatable {
        var file: URL
        var id: String { file.path }
        var title: String, status: String, tags: [String], source: String, cuisine: String, added: String
        var modified: Date
        /// The note's picture: a page's, when it isn't a video.
        var image = ""
        /// The video's channel or the page's site, as the note's header gives it.
        var channel = ""
        /// The video's picture, else the page's.
        var picture: URL? { thumbnail(of: source) ?? URL(string: image) }
    }

    static func entry(_ file: URL, text: String, modified: Date) -> Entry {
        let header = header(of: text)
        let value = { (key: String) in header[key]?.first ?? "" }
        let title = value("title").isEmpty ? file.deletingPathExtension().lastPathComponent : value("title")
        return Entry(file: file, title: title, status: value("status").lowercased(), tags: (header["tags"] ?? []).map(tag), source: value("source"),
                     cuisine: value("cuisine"), added: value("added"), modified: modified, image: value("image"), channel: value("channel"))
    }

    /// Every note in the recipes folder you chose and the folders in it (Obsidian's own and hidden ones left out), newest first.
    static func entries(in folder: URL) -> [Entry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [Entry] = []
        for case let file as URL in walker {
            if file.lastPathComponent == ".obsidian" { walker.skipDescendants(); continue }
            guard file.pathExtension.lowercased() == "md", let data = try? Data(contentsOf: file) else { continue }
            let modified = (try? file.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            found.append(entry(file, text: String(decoding: data, as: UTF8.self), modified: modified))
        }
        return found.sorted { $0.modified > $1.modified }
    }

    /// A file name for the recipe that no file system refuses (Windows' too) and no note in the folder has already.
    static func fileName(for title: String, taken: Set<String>) -> String {
        let cleaned = title.map { "<>:\"/\\|?*#^[]".contains($0) || $0.isNewline ? " " : $0 }.reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        let base = String((cleaned.isEmpty ? "Recipe" : cleaned).prefix(120))
        let lowered = Set(taken.map { $0.lowercased() })
        var name = base + ".md", number = 2
        while lowered.contains(name.lowercased()) { name = "\(base) \(number).md"; number += 1 }
        return name
    }

    // MARK: Chat (the brain answers in rounds: it can ask for a YouTube search or notes to read, then answers with them)

    struct Message: Codable, Equatable, Identifiable {
        var id = UUID()
        var fromSage: Bool
        var text: String
        /// The videos he shows with his answer.
        var videos: [Video] = []
        /// The notes he read for it.
        var notes: [String] = []
        var date = Date()
        /// What he did for it in your vault and the app (SageActions.swift), as said on screen.
        var done: [String]? = nil
    }

    /// One conversation in the chat's history: titled by your first message (empty until you write one), newest first in the list.
    struct Conversation: Codable, Equatable, Identifiable {
        var id = UUID()
        var messages: [Message] = []
        var created = Date()
        var updated = Date()

        var title: String {
            let first = messages.first { !$0.fromSage }?.text ?? ""
            let line = first.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !line.isEmpty else { return "" }
            return line.count > 60 ? String(line.prefix(57)).trimmingCharacters(in: .whitespaces) + "…" : line
        }
    }

    /// The conversations with your words in their title or any message, newest first.
    static func find(_ words: String, in conversations: [Conversation]) -> [Conversation] {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return conversations.filter { words.isEmpty || $0.title.localizedCaseInsensitiveContains(words) || $0.messages.contains { $0.text.localizedCaseInsensitiveContains(words) } }
            .sorted { $0.updated > $1.updated }
    }

    /// How long ago, as the list shows it: now, 8m, 1h, 3d, 2w, then the date.
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<(7 * 86_400): return "\(Int(seconds / 86_400))d"
        case ..<(35 * 86_400): return "\(Int(seconds / (7 * 86_400)))w"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    struct Reply: Equatable {
        var text = "", youtube = ""
        var notes: [String] = [], show: [String] = []
        /// Videos you asked him to save, by id: kept in the app's Saved list.
        var save: [String] = []
        var looksUp: Bool { !youtube.isEmpty || !notes.isEmpty }
    }

    static var chatSchema: [String: Any] {
        let text: [String: Any] = ["type": "string"], list: [String: Any] = ["type": "array", "items": text]
        let properties: [String: Any] = ["reply": text, "youtube": text, "notes": list, "show": list, "save": list, "find": text, "read": list, "actions": actionSchema]
        return ["type": "object", "additionalProperties": false, "required": properties.keys.sorted(), "properties": properties]
    }

    static func reply(from answer: [String: Any]) -> Reply {
        let text = { (key: String) in (answer[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let list = { (key: String) in (answer[key] as? [Any] ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
        return Reply(text: text("reply"), youtube: text("youtube"), notes: list("notes"), show: list("show"), save: list("save"))
    }

    /// The notes the brain named, matched by title (case and spacing aside), at most `count`.
    static func named(_ titles: [String], in recipes: [Entry], count: Int = 5) -> [Entry] {
        let key = { (text: String) in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ") }
        var found: [Entry] = []
        for title in titles {
            let wanted = key(title)
            if let entry = recipes.first(where: { key($0.title) == wanted }) ?? recipes.first(where: { !wanted.isEmpty && key($0.title).contains(wanted) }),
               !found.contains(entry) { found.append(entry) }
        }
        return Array(found.prefix(count))
    }

    /// One round's question: who Sage is, your recipe notes, the chat so far, and what he looked up this turn.
    /// `last` is the final round: he answers with what he has.
    static func chatPrompt(chat: [Message], recipes: [Entry], folder: Bool, canSearch: Bool, found: [Video]?, searched: String,
                           read: [(title: String, text: String)], last: Bool, topic: Topic = Topic(name: "Recipes", kind: .recipes)) -> String {
        let cooking = topic.kind == .recipes
        var text = (cooking ? """
        You are Sage, a research helper; right now we're on my topic "\(topic.name)": recipes. You find recipe videos on YouTube, answer cooking questions, and look things up in my own recipe notes (an Obsidian vault). Answer my last message in `reply`: plain text, short and practical, no Markdown headings. Use what you know about cooking; for my notes and YouTube, use only what you were given.

        To look something up first, put it in `youtube` (search words for recipe videos, e.g. "chicken adobo recipe") and/or `notes` (titles from my notes list to read in full), with `reply` saying in a few words what you are looking up. You then get the results and answer again. Look up only what the question needs; a cooking question you can answer needs no lookup.
        """ : """
        You are Sage, a research helper; right now we're researching my topic "\(topic.name)". You find videos on YouTube worth learning from, answer my questions, and look things up in my own notes on this topic (an Obsidian vault). Answer my last message in `reply`: plain text, clear and to the point, no Markdown headings. Use what you know; for my notes and YouTube, use only what you were given, and say when you are not sure.

        To look something up first, put it in `youtube` (search words, e.g. "premiere pro speed ramp tutorial") and/or `notes` (titles from my notes list to read in full), with `reply` saying in a few words what you are looking up. You then get the results and answer again. Look up only what the question needs; a question you can answer needs no lookup.
        """) + "\n" + """
        To show videos from a search with your answer, put their ids in `show` (at most 6, best first) and say in `reply` why each is worth it. Otherwise leave `show` empty.
        When I ask you to save videos (keep them, put them in Saved, save the first two…), put their ids in `save`: the app keeps them in its \
        Saved list for me to review and write down. You can save any video from the results or the ones you showed earlier; never say you \
        can't save. Leave `save` empty otherwise.

        """
        if last { text += "Answer now with what you have: leave `youtube` and `notes` empty.\n\n" }
        if !canSearch { text += "YouTube search is not set up (no API key): don't search; if I want videos, tell me to add the YouTube key at the top of the page.\n\n" }
        if !folder {
            text += "This topic's folder in my vault is not chosen yet, so there are no notes in this topic: if I ask you to, set it (set_folder, below), or tell me I can choose it at the top of the page.\n\n"
        } else {
            text += "My notes in this topic (title | status | \(cooking ? "cuisine" : "-") | tags), \(recipes.count) in all:\n"
            text += recipes.prefix(400).map { "- \($0.title) | \($0.status.isEmpty ? "-" : $0.status) | \($0.cuisine.isEmpty ? "-" : $0.cuisine) | \($0.tags.joined(separator: ", "))" }
                .joined(separator: "\n") + (recipes.isEmpty ? "(none yet)" : "") + "\n\n"
        }
        // The videos shown last stay at hand for questions about them.
        if let shown = chat.last(where: { $0.fromSage && !$0.videos.isEmpty })?.videos {
            text += "Videos you showed earlier:\n" + shown.map { video($0, description: 800) }.joined(separator: "\n") + "\n\n"
        }
        text += "The chat so far:\n" + chat.suffix(20).map { ($0.fromSage ? "Sage: " : "Me: ") + String($0.text.prefix(3000)) }.joined(separator: "\n") + "\n"
        if let found {
            text += "\nYouTube results for \"\(searched)\":\n" + (found.isEmpty ? "(nothing found)" : found.map { video($0, description: 400) }.joined(separator: "\n")) + "\n"
        }
        for note in read { text += "\nMy note \"\(note.title)\":\n" + String(note.text.prefix(6000)) + "\n" }
        return text
    }

    static func video(_ video: Video, description: Int) -> String {
        let views = video.views.map { " | \($0) views" } ?? ""
        let about = video.description.prefix(description).replacingOccurrences(of: "\n", with: " ")
        return "- id \(video.id) | \(video.title) | \(video.channel) | \(video.duration)\(views) | \(about)"
    }

    // MARK: Small parts

    static func json(_ data: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
    static func items(_ data: Data) -> [[String: Any]] { json(data)?["items"] as? [[String: Any]] ?? [] }
    static func text(_ value: Any?) -> String { decoded(value as? String ?? "") }

    /// The picture of a recipe's video, from the note's `source` link (watch?v=, youtu.be/ or shorts/), or nil.
    static func thumbnail(of source: String) -> URL? {
        videoID(of: source).flatMap { URL(string: "https://i.ytimg.com/vi/\($0)/mqdefault.jpg") }
    }

    /// The video's id in a YouTube link (watch?v=, youtu.be/ or shorts/), or nil.
    static func videoID(of source: String) -> String? {
        guard let url = URL(string: source), let host = url.host?.lowercased() else { return nil }
        var id: String?
        if host.hasSuffix("youtu.be") { id = url.pathComponents.dropFirst().first }
        else if host.hasSuffix("youtube.com") {
            id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
                ?? (url.pathComponents.count > 2 && url.pathComponents[1] == "shorts" ? url.pathComponents[2] : nil)
        }
        guard let id, !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return id
    }

    /// YouTube's titles come HTML-escaped ("Mac &amp; Cheese").
    static func decoded(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (code, character) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">")] {
            result = result.replacingOccurrences(of: code, with: character)
        }
        return result
    }
}
