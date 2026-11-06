import Foundation

/// Sage researches any topic, not only recipes (you asked for it, 2026-11-06): topics, each with its own vault folder and
/// note style; web pages as sources beside YouTube; and the general research note. Foundation only, like `Study`.
extension Study {
    // MARK: Topics

    /// What you research: Recipes (ingredients and steps; to try, made, favourite) or a general topic (summary, key points,
    /// details, quotes, open questions; to read, read, key). Each has its own folder in your vault.
    struct Topic: Codable, Equatable, Identifiable {
        enum Kind: String, Codable, CaseIterable { case general, recipes }
        var id = UUID()
        var name: String
        var kind = Kind.general
        /// The topic's folder in your vault; empty until you choose it (asked when a note is first written).
        var folder = ""

        var statuses: [String] { kind == .recipes ? ["to try", "made", "favourite"] : ["to read", "read", "key"] }
    }

    /// Searches for a topic: recipe topics look for recipes, others search your words as they are.
    static func search(_ words: String, in topic: Topic) -> String {
        topic.kind == .recipes ? recipeSearch(words) : words.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Web pages

    /// A web page as a source: what it says it is, and its readable text.
    struct Page: Codable, Equatable {
        var url: URL
        var title = "", site = "", description = ""
        var image: URL?
        /// The page's words without its menus, scripts and styles (at most 40,000 characters).
        var text = ""
    }

    /// Your words as a web link to read, or nil when they are not one.
    static func link(_ words: String) -> URL? {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.contains(" "), let url = URL(string: words.hasPrefix("www.") ? "https://" + words : words),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.contains(".") == true else { return nil }
        return url
    }

    /// A page read from its HTML: its title, site, description and picture as it declares them, and its readable text
    /// (an <article> or <main> when it has one; scripts, styles, menus, headers and footers left out).
    static func page(fromHTML html: String, url: URL) -> Page {
        let meta = { (name: String) -> String in
            for pattern in [#"<meta[^>]+(?:property|name)=["']\#(name)["'][^>]+content=["']([^"']*)["']"#,
                            #"<meta[^>]+content=["']([^"']*)["'][^>]+(?:property|name)=["']\#(name)["']"#] {
                if let found = first(pattern, in: html) { return decodedEntities(found) }
            }
            return ""
        }
        var page = Page(url: url)
        page.title = meta("og:title")
        if page.title.isEmpty, let title = first(#"<title[^>]*>([\s\S]*?)</title>"#, in: html) { page.title = decodedEntities(title).trimmingCharacters(in: .whitespacesAndNewlines) }
        page.site = meta("og:site_name").isEmpty ? (url.host ?? "").replacingOccurrences(of: "www.", with: "") : meta("og:site_name")
        page.description = meta("og:description").isEmpty ? meta("description") : meta("og:description")
        page.image = URL(string: meta("og:image"), relativeTo: url)?.absoluteURL
        var body = html
        for tag in ["article", "main"] {
            if let inner = first("<\(tag)[^>]*>([\\s\\S]*)</\(tag)>", in: html), inner.count > 500 { body = inner; break }
        }
        page.text = String(readable(body).prefix(40000))
        return page
    }

    /// HTML as plain text: blocks on lines of their own, tags taken out, entities decoded, spaces collapsed.
    static func readable(_ html: String) -> String {
        var text = html
        for tag in ["script", "style", "noscript", "svg", "nav", "header", "footer", "aside", "form", "iframe", "template"] {
            text = text.replacingOccurrences(of: "<\(tag)\\b[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<(br|/p|/div|/li|/h[1-6]|/tr|/section|/blockquote)\\b[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<li\\b[^>]*>", with: "\n• ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = decodedEntities(text)
        let lines = text.components(separatedBy: "\n").map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" }).joined(separator: " ") }
        var kept: [String] = []
        for line in lines where !line.isEmpty || kept.last?.isEmpty == false { kept.append(line) }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first capture of the pattern in the text, or nil.
    private static func first(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func decodedEntities(_ text: String) -> String {
        var result = decoded(text).replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&rsquo;", with: "’").replacingOccurrences(of: "&lsquo;", with: "‘").replacingOccurrences(of: "&ldquo;", with: "“")
            .replacingOccurrences(of: "&rdquo;", with: "”").replacingOccurrences(of: "&mdash;", with: "—").replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&hellip;", with: "…")
        // Numeric entities (&#8217;).
        while let range = result.range(of: "&#[0-9]{2,6};", options: .regularExpression) {
            let number = Int(result[range].dropFirst(2).dropLast()) ?? 32
            result.replaceSubrange(range, with: String(UnicodeScalar(number).map(Character.init) ?? " "))
        }
        return result
    }

    // MARK: The general research note (one brain call, no tools, a strict schema)

    struct Brief: Equatable {
        var title = "", summary = ""
        var points: [String] = [], details: [String] = [], quotes: [String] = [], questions: [String] = [], tags: [String] = []
        /// Where it came from: the video or page, its channel or site, a page the video links to, the picture.
        var source = "", channel = "", page = "", image = ""
    }

    static var briefSchema: [String: Any] {
        let text: [String: Any] = ["type": "string"], list: [String: Any] = ["type": "array", "items": text]
        let properties: [String: Any] = ["title": text, "summary": text, "points": list, "details": list, "quotes": list, "questions": list, "tags": list]
        return ["type": "object", "additionalProperties": false, "required": properties.keys.sorted(), "properties": properties]
    }

    static func briefRules(_ topic: String) -> String {
        """
        Write it as a research note for my topic "\(topic)": a short plain title (what it is about, no clickbait), a summary of 2–4 \
        sentences, the key points as short lines (the ideas, steps, numbers or settings worth keeping), details as a few short paragraphs \
        for what needs more room, quotes worth keeping word for word (only words the material really has), open questions it leaves, and \
        2–6 lowercase tags. Use only what the material says: never invent facts, numbers or quotes. When the material is thin (a video's \
        description only), say so in the summary and keep the note short. Leave a field empty ("" or []) when there is nothing for it. \
        Write in English.
        """
    }

    /// The question for a video: its title, channel and description, and a page it links to when one was read.
    static func briefPrompt(for video: Video, linked: Page?, topic: String) -> String {
        var text = "From this YouTube video, write a research note.\n" + briefRules(topic) + "\n\nVideo title: \(video.title)\nChannel: \(video.channel)\nLength: \(video.duration)\n"
            + "Description:\n" + String(video.description.prefix(6000))
        if let linked { text += "\n\nA page the video links to (\(linked.url.absoluteString)), \(linked.title):\n" + String(linked.text.prefix(15000)) }
        return text
    }

    static func briefPrompt(for page: Page, topic: String) -> String {
        "From this web page, write a research note.\n" + briefRules(topic) + "\n\nPage: \(page.title)\nSite: \(page.site)\nAddress: \(page.url.absoluteString)\n"
            + (page.description.isEmpty ? "" : "It describes itself: \(page.description)\n") + "Its text:\n" + String(page.text.prefix(30000))
    }

    static func briefPrompt(for words: String, topic: String) -> String {
        "Turn what I wrote or pasted (my notes, a transcript, an article) into a research note. " + briefRules(topic)
            + " Here the material is my own words or what I pasted: keep its facts and wording where it matters.\n\n" + String(words.prefix(30000))
    }

    static func brief(from answer: [String: Any]) -> Brief {
        let text = { (key: String) in (answer[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let list = { (key: String) in (answer[key] as? [Any] ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
        return Brief(title: text("title"), summary: text("summary"), points: list("points"), details: list("details"),
                     quotes: list("quotes").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”")) }, questions: list("questions"), tags: list("tags").map(tag))
    }

    /// The research note as Obsidian reads it: the header (properties), the video or the page's picture, then its sections.
    static func note(_ brief: Brief, topic: String, status: String = "to read", added: String) -> String {
        var header: [(String, String)] = [("title", quoted(brief.title)), ("status", status), ("topic", quoted(topic))]
        for (key, value) in [("source", brief.source), ("channel", brief.channel), ("page", brief.page), ("image", brief.image)] where !value.isEmpty {
            header.append((key, quoted(value)))
        }
        var text = "---\n" + header.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        let tags = ["research"] + brief.tags.filter { $0 != "research" && !$0.isEmpty }
        text += "\ntags:\n" + tags.map { "  - \($0)" }.joined(separator: "\n") + "\nadded: \(added)\n---\n\n"
        if brief.source.contains("youtube.com/watch") { text += "![](\(brief.source))\n\n" } else if !brief.image.isEmpty { text += "![](\(brief.image))\n\n" }
        if !brief.summary.isEmpty { text += "## Summary\n\n\(brief.summary)\n\n" }
        if !brief.points.isEmpty { text += "## Key points\n\n" + brief.points.map { "- \($0)" }.joined(separator: "\n") + "\n\n" }
        if !brief.details.isEmpty { text += "## Details\n\n" + brief.details.joined(separator: "\n\n") + "\n\n" }
        if !brief.quotes.isEmpty { text += "## Quotes\n\n" + brief.quotes.map { "> \($0)" }.joined(separator: "\n>\n") + "\n\n" }
        if !brief.questions.isEmpty { text += "## Open questions\n\n" + brief.questions.map { "- \($0)" }.joined(separator: "\n") + "\n\n" }
        let sources = [brief.source, brief.page].filter { !$0.isEmpty }
        if !sources.isEmpty { text += "## Sources\n\n" + sources.map { "- \($0)" }.joined(separator: "\n") + "\n" }
        return text
    }

    // MARK: Picks for any topic

    static func pickPrompt(_ words: String, videos: [Video], count: Int, topic: Topic) -> String {
        guard topic.kind == .general else { return pickPrompt(words, videos: videos, count: count) }
        return """
        I'm researching "\(topic.name)" and searched YouTube for "\(words)". Pick the videos most worth saving to learn from, best first, at \
        most \(count). Prefer clear, substantial, credible explanations or demonstrations that match what I searched; leave out clickbait, \
        reactions, compilations, music, Shorts with nothing to learn and anything off the subject, and prefer different angles over the same \
        one twice. For each pick give its id and in `why` one short line on what it covers and why it's worth saving. If none is worth it, \
        return no picks.

        The results (id | title | channel | length | views | description):
        """ + "\n" + videos.map { video($0, description: 300) }.joined(separator: "\n")
    }
}
