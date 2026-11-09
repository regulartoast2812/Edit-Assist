import Foundation

/// Sage's file explorer, the part without AppKit (2026-11-08 in Creative Assist, brought back 2026-11-09): links kept
/// right when files move, names, templates and the quick switcher's matching. The checks compile it as it is.
extension Study {
    // MARK: Moving and renaming: links follow, as Obsidian's "Automatically update internal links" does

    /// Where a path is after the moves (a file moved, or inside a folder that moved); itself when untouched.
    static func movedPath(_ path: String, _ moves: [String: String]) -> String {
        if let to = moves[path] ?? moves.first(where: { same($0.key, path) })?.value { return to }
        for (from, into) in moves where path.lowercased().hasPrefix(from.lowercased() + "/") { return into + path.dropFirst(from.count) }
        return path
    }

    /// The notes whose links change when files move (`moves`: old path → new path, a file or a folder), with their new text,
    /// by the note's path before the move. A [[link]] to a moved file is rewritten the way it was written: by path when it
    /// had one, by name when it was a name (kept as it is when the name still finds the file). Headings (#), blocks (^) and
    /// aliases (|) stay. A Markdown link [text](path) is recomputed from where the note is now, relative when it was.
    static func relink(_ items: [VaultItem], moves: [String: String], read: (String) -> String?) -> [(path: String, text: String)] {
        let after = items.map { item -> VaultItem in var moved = item; moved.path = movedPath(item.path, moves); return moved }
        var changed: [(path: String, text: String)] = []
        for note in items where !note.folder && note.ext == ".md" {
            guard let text = read(note.path) else { continue }
            let notePath = note.path, noteAfter = movedPath(notePath, moves)
            var result = substitute(#"(!?)\[\[([^\]\|#\^\n]*)([#\^][^\]\|\n]*)?(\|[^\]\n]*)?\]\]"#, in: text) { g in
                let target = g[2]
                if target.trimmingCharacters(in: .whitespaces).isEmpty { return g[0] }
                guard let found = resolve(target, in: items, from: notePath) else { return g[0] }
                let moved = movedPath(found.path, moves)
                if moved == found.path { return g[0] }
                let withExtension = !found.ext.isEmpty && target.lowercased().hasSuffix(found.ext)
                func shown(_ path: String) -> String { withExtension || !path.lowercased().hasSuffix(".md") ? path : String(path.dropLast(3)) }
                let written: String
                if target.contains("/") { written = shown(moved) } else {
                    let name = VaultItem(path: moved, folder: false).name
                    // By name when the name still finds this file from the note, else by path.
                    written = resolve(shown(name), in: after, from: noteAfter).map { same($0.path, moved) } == true ? shown(name) : shown(moved)
                }
                return written == target ? g[0] : "\(g[1])[[\(written)\(g[3])\(g[4])]]"
            }
            result = substitute(#"(!?\[[^\]\n]*\]\()(<[^>\n]+>|[^)\s]+)(\))"#, in: result) { g in
                let raw = g[2]
                let angled = raw.hasPrefix("<")
                let url = angled ? String(raw.dropFirst().dropLast()) : raw
                if matches(#"^[a-z][a-z0-9+.-]*:"#, url, options: .caseInsensitive) || url.hasPrefix("#") { return g[0] }
                let hash = url.firstIndex(of: "#")
                let anchor = hash.map { String(url[$0...]) } ?? ""
                let bare = hash.map { String(url[..<$0]) } ?? url
                let decoded = bare.removingPercentEncoding ?? bare
                let absolute = decoded.hasPrefix("/")
                let path = absolute ? String(decoded.drop { $0 == "/" }) : relative(decoded, from: notePath)
                var found = path.flatMap { path in items.first { !$0.folder && same($0.path, path) } }
                // Not beside the note: Obsidian then finds it as it finds a [[link]] (from the vault, or by name).
                var byVault = false
                if found == nil, !absolute, let named = resolve(decoded, in: items, from: notePath) { found = named; byVault = true }
                guard let found else { return g[0] }
                let moved = movedPath(found.path, moves)
                if moved == found.path && (noteAfter == notePath || byVault || absolute) { return g[0] }
                let link = absolute ? "/" + moved
                    : byVault ? (decoded.contains("/") ? moved : VaultItem(path: moved, folder: false).name)
                    : relativeFrom(noteAfter, moved)
                if link == decoded { return g[0] }
                var allowed = CharacterSet.urlPathAllowed
                allowed.remove(charactersIn: "/?#;%&=+$,@:")
                let encoded = angled ? link : link.components(separatedBy: "/").map { $0 == ".." ? $0 : ($0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0) }.joined(separator: "/")
                return g[1] + (angled ? "<" + encoded + anchor + ">" : encoded + anchor) + g[3]
            }
            if result != text { changed.append((notePath, result)) }
        }
        return changed
    }

    /// A path written relative to the folder a note is in ("../Attachments/a.png").
    static func relativeFrom(_ notePath: String, _ target: String) -> String {
        let from = notePath.contains("/") ? VaultItem(path: notePath, folder: false).parent.components(separatedBy: "/") : []
        let to = target.components(separatedBy: "/")
        var common = 0
        while common < from.count && common < to.count - 1 && same(from[common], to[common]) { common += 1 }
        return (Array(repeating: "..", count: from.count - common) + to.dropFirst(common)).joined(separator: "/")
    }

    // MARK: Names

    /// Why a name can't be a file's name in the vault (the Mac's rules, Obsidian's, and Windows' so a vault synced to a
    /// PC keeps working), or nil when it can. In English; `nameRule` gives it as a sentence to translate and its value.
    static func nameProblem(_ name: String) -> String? {
        nameRule(name).map { rule in rule.value.map { rule.text.replacingOccurrences(of: "%@", with: $0) } ?? rule.text }
    }

    static func nameRule(_ name: String) -> (text: String, value: String?)? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return ("A name can't be empty.", nil) }
        if let bad = name.first(where: { "\\/:*?\"<>|".contains($0) }) { return ("A name can't have “%@” in it.", String(bad)) }
        if name.hasPrefix(".") { return ("A name starting with “.” would be hidden.", nil) }
        if name.hasSuffix(".") || name.hasSuffix(" ") { return ("A name can't end with a dot or a space.", nil) }
        if matches(#"^(con|prn|aux|nul|com\d|lpt\d)(\..*)?$"#, name, options: .caseInsensitive) { return ("Windows keeps “%@” for itself.", name) }
        if name.contains("[[") || name.contains("]]") || name.contains("#") || name.contains("^") || name.contains("|") { return ("Links can't point at a name with #, ^, | or [[ ]] in it.", nil) }
        return nil
    }

    /// A name not taken in the folder: "Untitled", then "Untitled 1", "Untitled 2"…
    static func freeName(taken: (String) -> Bool, stem: String, extension ext: String) -> String {
        if !taken(stem + ext) { return stem + ext }
        var i = 1
        while taken("\(stem) \(i)\(ext)") { i += 1 }
        return "\(stem) \(i)\(ext)"
    }

    // MARK: Templates (Obsidian's core Templates: {{title}}, {{date}}, {{time}}, with its moment.js formats)

    static func applyTemplate(_ template: String, title: String, now: Date, dateFormat: String = "YYYY-MM-DD", timeFormat: String = "HH:mm") -> String {
        substitute(#"\{\{\s*(title|date|time)\s*(?::([^}]*))?\}\}"#, in: template, options: .caseInsensitive) { g in
            let format = g[2].trimmingCharacters(in: .whitespaces)
            switch g[1].lowercased() {
            case "title": return title
            case "date": return moment(now, format.isEmpty ? dateFormat : format)
            default: return moment(now, format.isEmpty ? timeFormat : format)
            }
        }
    }

    /// A date written in a moment.js format ("DD-MM-YYYY HH:mm"), through Foundation's date patterns ("dd-MM-yyyy HH:mm").
    static func moment(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = momentPattern(format)
        return formatter.string(from: date)
    }

    /// A moment.js format as a Unicode date pattern: tokens mapped, [escaped] text and other letters quoted.
    static func momentPattern(_ format: String) -> String {
        let tokens: [(String, String)] = [("YYYY", "yyyy"), ("YY", "yy"), ("MMMM", "MMMM"), ("MMM", "MMM"), ("MM", "MM"), ("M", "M"), ("DD", "dd"), ("D", "d"),
                                          ("dddd", "EEEE"), ("ddd", "EEE"), ("HH", "HH"), ("H", "H"), ("hh", "hh"), ("h", "h"), ("mm", "mm"), ("m", "m"),
                                          ("ss", "ss"), ("s", "s"), ("A", "a"), ("a", "a")]
        var pattern = "", rest = Substring(format)
        func quote(_ text: Substring) -> String { "'" + text.replacingOccurrences(of: "'", with: "''") + "'" }
        while let c = rest.first {
            if c == "[", let close = rest.firstIndex(of: "]") {
                let inner = rest[rest.index(after: rest.startIndex) ..< close]
                if !inner.isEmpty { pattern += quote(inner) }
                rest = rest[rest.index(after: close)...]
                continue
            }
            if let token = tokens.first(where: { rest.hasPrefix($0.0) }) {
                pattern += token.1
                rest = rest.dropFirst(token.0.count)
                continue
            }
            pattern += c.isLetter ? quote(rest.prefix(1)) : String(c)
            rest = rest.dropFirst()
        }
        return pattern
    }

    // MARK: The quick switcher's matching

    /// How well `text` matches what you typed, letters in order and not side by side (Obsidian's fuzzy search): higher is
    /// better, nil when it doesn't match. Letters at the start of a word, in a run, or at the start count more. The
    /// places matched (character offsets), to show them.
    static func fuzzy(_ query: String, _ text: String) -> (score: Int, at: [Int])? {
        let query = query.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return (0, []) }
        let chars = Array(text), length = chars.count
        if let whole = text.range(of: query, options: .caseInsensitive) {
            // The words typed together found together: best, and best of all at the start.
            let start = text.distance(from: text.startIndex, to: whole.lowerBound)
            let wordStart = start == 0 || !(chars[start - 1].isLetter || chars[start - 1].isNumber)
            return (1000 - start * 2 + (wordStart ? 200 : 0) - length / 4, Array(start ..< start + query.count))
        }
        var at: [Int] = [], score = 0, from = 0, previous = -2
        for c in query where !c.isWhitespace {
            let lower = c.lowercased()
            guard let found = (from ..< length).first(where: { chars[$0].lowercased() == lower }) else { return nil }
            score += 10
            if found == previous + 1 { score += 15 }
            if found == 0 || !(chars[found - 1].isLetter || chars[found - 1].isNumber) { score += 20 }
            at.append(found)
            previous = found
            from = found + 1
        }
        return (score - ((at.last ?? 0) - (at.first ?? 0)) - length / 4, at)
    }

    // MARK: Colour (2026-11-08): a name keeps one colour everywhere: its folder in the tree, its group or value in a base

    /// Which of Obsidian's eight colours (0 red, 1 orange, 2 yellow, 3 green, 4 cyan, 5 blue, 6 purple, 7 pink) a name gets
    /// when nothing sets one: the same name always the same colour, a leading emoji and case ignored. The same number as
    /// Creative Assist gives it (FNV-1a over UTF-16), so a vault looks the same on both.
    static func hue(_ name: String) -> Int {
        let text = (leadingEmoji(name)?.name ?? name).trimmingCharacters(in: .whitespaces).lowercased()
        var hash: UInt32 = 2166136261
        for unit in text.utf16 { hash ^= UInt32(unit); hash = hash &* 16777619 }
        // FNV's low bits are weak for short names: fold the high ones in.
        hash ^= hash >> 15
        hash = hash &* 2246822519
        hash ^= hash >> 13
        return Int(hash % 8)
    }

    /// An emoji a name starts with ("🗺️ Strategy"), and the rest of the name; nil when it starts with none.
    static func leadingEmoji(_ name: String) -> (emoji: String, name: String)? {
        guard let first = name.first, let code = first.unicodeScalars.first?.value else { return nil }
        let emoji = (0x1F000 ... 0x1FAFF).contains(code) || (0x2600 ... 0x27BF).contains(code) || (0x2B00 ... 0x2BFF).contains(code)
            || (0x2190 ... 0x21FF).contains(code) || (0x2300 ... 0x23FF).contains(code) || first.unicodeScalars.contains { $0.value == 0xFE0F }
        guard emoji else { return nil }
        let rest = name.dropFirst().drop { $0.isWhitespace }
        return rest.isEmpty ? nil : (String(first), String(rest))
    }
}
