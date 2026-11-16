import Foundation

// The tag and link menus while you write a note, and Ask Sage about a passage (2026-11-16, ported from Creative Assist's
// SageSuggest.cs and SageAsk.cs, 2026-11-14/15): "#" and letters lists the vault's tags, "[[" its notes, filtered as you
// type (the page posts "suggest"); the toolbar's and "/" menu's Ask Sage posts "ai-edit". Foundation only, so the checks
// compile it as it is.
extension Study {
    // MARK: Ask Sage about a passage

    /// The kinds the page sends, with what each asks of the passage (nil: not a change to the note).
    private static let passageKinds: [String: (said: String, change: String?)] = [
        "improve": ("Improve the writing", "Improve its writing: clearer, smoother, the same meaning and voice."),
        "proofread": ("Proofread", "Proofread it: fix spelling, grammar and punctuation only; don't reword anything else."),
        "shorter": ("Make it shorter", "Make it shorter, keeping what matters."),
        "longer": ("Make it longer", "Make it longer: fill it out with detail that fits the rest of the note."),
        "simpler": ("Simplify the language", "Simplify its language so it reads easily, the same meaning."),
        "explain": ("Explain this", nil),
        "ask": ("Ask about this", nil),
        "write": ("Write here", nil),
        "continue": ("Continue writing", nil),
    ]

    static func isPassageKind(_ kind: String) -> Bool { passageKinds[kind] != nil }

    /// What the chat shows you asked: the kind (or your words) and the note.
    static func passageSaid(_ kind: String, prompt: String, name: String) -> String {
        let what = (kind == "ask" || kind == "write") && !prompt.isEmpty ? "“\(prompt)”" : passageKinds[kind].map { L($0.said) } ?? kind
        return L("%@ in “%@”", what, name)
    }

    /// What Sage's agent is asked about a passage of the note at `path` (from the vault): changed in place as asked (only
    /// that passage), explained or answered in the chat (no file changed), or written after it.
    static func passageRequest(path: String, kind: String, passage: String, prompt: String) -> String {
        let quoted = "<<<\n\(passage.trimmingCharacters(in: CharacterSet(charactersIn: "\n")))\n>>>"
        let keep = "Keep its Markdown (links, formatting, callouts) and my voice, and change nothing else in the note or the vault."
        switch kind {
        case "explain": return "Explain this passage from my note \"\(path)\" in plain words, in your reply. Don't change any file.\n\n\(quoted)"
        case "ask": return "About this passage from my note \"\(path)\": \(prompt)\nAnswer in your reply. If (and only if) that asks for a change, change only this passage in the note. \(keep)\n\n\(quoted)"
        case "write": return "In my note \"\(path)\", write this right after the passage below (it ends where I am): \(prompt)\nAdd only that, written as the note is. \(keep)\n\n\(quoted)"
        case "continue": return "In my note \"\(path)\", continue writing right after the passage below (it ends where I am): a paragraph or so more, going on from it as I would. \(keep)\n\n\(quoted)"
        default: return "In my note \"\(path)\", find this passage and rewrite only it. \(passageKinds[kind]?.change ?? "") \(keep)\n\n\(quoted)"
        }
    }

    // MARK: Tags and links

    private static let tagInText = try! NSRegularExpression(pattern: #"(?<=^|[\s(,])#([\p{L}\p{N}_/-]*[\p{L}_/-][\p{L}\p{N}_/-]*)"#, options: [.anchorsMatchLines])
    private static let fence = try! NSRegularExpression(pattern: #"^(```|~~~).*?^\1"#, options: [.anchorsMatchLines, .dotMatchesLineSeparators])
    private static let inlineCode = try! NSRegularExpression(pattern: #"`[^`\n]*`"#)

    /// The tags of a note's text, as Obsidian counts them: #tags in the text (not in code, not a heading's #, not a number
    /// like #1) and the frontmatter's tags (a list or one line, with or without #).
    static func tagsOf(_ text: String) -> [String] {
        var tags: [String] = [], body = text
        if text.hasPrefix("---"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3) ..< text.endIndex) {
            let head = header(of: String(text[..<end.upperBound]) + "\n")
            for key in ["tags", "tag"] {
                for value in head[key] ?? [] {
                    for one in value.split(whereSeparator: { $0 == "," || $0 == " " }) {
                        let tag = String(one).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                        if !tag.isEmpty, tag.range(of: #"[\p{L}_/-]"#, options: .regularExpression) != nil { tags.append(tag) }
                    }
                }
            }
            body = String(text[end.upperBound...])
        }
        func strip(_ re: NSRegularExpression, _ s: String) -> String { re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "") }
        body = strip(inlineCode, strip(fence, body))
        for m in tagInText.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            if let r = Range(m.range(at: 1), in: body) { tags.append(String(body[r])) }
        }
        return tags
    }

    /// The vault's tags with how often each is used, most used first (notes read up to 1 MB each).
    static func vaultTags(_ vault: URL, items: [VaultItem]) -> [(tag: String, count: Int)] {
        var counts: [String: (tag: String, count: Int)] = [:]
        for item in items where !item.folder && item.ext == ".md" {
            let file = vault.appendingPathComponent(item.path)
            guard ((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) <= 1_000_000,
                  let data = try? Data(contentsOf: file) else { continue }
            for tag in tagsOf(String(decoding: data, as: UTF8.self)) {
                let key = tag.lowercased()
                counts[key] = counts[key].map { ($0.tag, $0.count + 1) } ?? (tag, 1)
            }
        }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending }
    }

    /// How well `name` answers what's typed: its start (0), a word's start (1), anywhere (2), not at all (-1).
    private static func fit(_ name: String, _ typed: String) -> Int {
        if typed.isEmpty { return 0 }
        guard let r = name.range(of: typed, options: .caseInsensitive) else { return -1 }
        if r.lowerBound == name.startIndex { return 0 }
        let escaped = NSRegularExpression.escapedPattern(for: typed)
        return name.range(of: #"(^|[\s\-_/(.])"# + escaped, options: [.regularExpression, .caseInsensitive]) != nil ? 1 : 2
    }

    /// The tags for what's typed after "#": the best fits first, then the most used.
    static func suggestTags(_ typed: String, tags: [(tag: String, count: Int)], most: Int = 12) -> [(tag: String, count: Int)] {
        let fitted = tags.enumerated().map { (i: $0.offset, t: $0.element, fit: fit($0.element.tag, typed)) }.filter { $0.fit >= 0 }
        return fitted.sorted { $0.fit != $1.fit ? $0.fit < $1.fit : $0.t.count != $1.t.count ? $0.t.count > $1.t.count : $0.i < $1.i }.prefix(most).map(\.t)
    }

    /// The files for what's typed after "[[": notes by name (a picture, a PDF, a canvas or a base with its extension), the
    /// best fits first, then the ones changed last; with nothing typed, the last changed. Each with what the link writes
    /// (its name, or its path when another file has the same name) and its folder.
    static func suggestLinks(_ typed: String, items: [VaultItem], most: Int = 12) -> [(text: String, link: String, folder: String)] {
        let typed = typed.trimmingCharacters(in: .whitespaces)
        let files = items.filter { !$0.folder }
        var names: [String: Int] = [:]
        for f in files { names[f.title.lowercased(), default: 0] += 1 }
        let fitted = files.map { item -> (item: VaultItem, fit: Int) in
            let a = fit(item.title, typed), b = fit(item.path, typed)
            return (item, min(a >= 0 ? a : 9, b >= 0 ? b + 3 : 9))
        }.filter { $0.fit < 9 }
        return fitted.sorted { $0.fit != $1.fit ? $0.fit < $1.fit : $0.item.modified > $1.item.modified }.prefix(most).map { x in
            let shared = (names[x.item.title.lowercased()] ?? 0) > 1
            return (x.item.title, shared ? (x.item.ext == ".md" ? String(x.item.path.dropLast(3)) : x.item.path) : x.item.title, x.item.parent)
        }
    }
}
