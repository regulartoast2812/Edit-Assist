import Foundation

/// Obsidian's Properties editor in Sage's note view (2026-11-10, you asked: clicking the properties turned them into raw
/// YAML). Foundation only, like the rest of `Study`: a property's value set, renamed or removed, a list's items, a type
/// kept in .obsidian/types.json. Only that property's lines change; the rest of the frontmatter stays byte for byte, a
/// value keeps its quotes where it had them, and lists are written as Obsidian writes them (`key:` then `  - item`).
extension Study {
    /// One change made in the Properties table.
    enum PropertyChange: Equatable, Sendable {
        /// The value as typed (quotes off): one value, or a list's items. `plain`: a number, tick, date or time, written
        /// as it is; text is quoted when YAML would read it as something else. A key not there yet is added at the end.
        case set(key: String, values: [String], list: Bool, plain: Bool)
        case rename(key: String, to: String)
        case remove(key: String)
        /// The value's shape for a new type: a value becomes a one-item list, a one-item list a value (more items stay).
        case retype(key: String, list: Bool)
    }

    enum PropertyResult: Equatable, Sendable {
        case written(String)
        case unchanged
        /// The frontmatter doesn't read as it did when the page was drawn: nothing is written over it.
        case changed
        /// A rename to a name another property has.
        case taken
        /// A value over several lines (a block, a map) the table can't show whole: it's changed as YAML.
        case complex
    }

    /// A property's lines in the frontmatter (counted from its first line, 0), its key as written before the colon.
    struct PropertySpan: Equatable, Sendable {
        var key: String
        var from: Int
        var to: Int
        var complex: Bool
    }

    /// The frontmatter's lines (between the `---` lines) and the line its closing `---` is on; nil when there is none.
    static func frontmatterLines(_ note: String) -> (lines: [String], end: Int)? {
        let lines = note.components(separatedBy: "\n")
        func fence(_ line: String) -> Bool { line.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r")) == "---" }
        guard fence(lines[0]), let end = lines.indices.dropFirst().first(where: { fence(lines[$0]) }) else { return nil }
        return (Array(lines[1 ..< end]), end)
    }

    /// The frontmatter as the page was drawn from it (nil when the note has none).
    static func frontmatter(of note: String) -> String? {
        frontmatterLines(note.replacingOccurrences(of: "\r\n", with: "\n")).map { $0.lines.joined(separator: "\n") }
    }

    /// Each top-level property and its lines: the key's line, then its list items and anything indented under it.
    static func propertySpans(_ header: [String]) -> [PropertySpan] {
        var spans: [PropertySpan] = [], i = 0
        while i < header.count {
            let line = header[i]
            guard let first = line.first, first != " ", first != "\t", first != "#", first != "-", let colon = line.firstIndex(of: ":") else { i += 1; continue }
            let rest = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            // A block (| >), a map ({), an anchor or tag, or a flow list carried over lines: not one line the table shows whole.
            var complex = ["|", ">", "{", "&", "!", "*"].contains { rest.hasPrefix($0) } || (rest.hasPrefix("[") && !rest.hasPrefix("[[") && !rest.hasSuffix("]"))
                || (rest.hasPrefix("\"") && (rest.count < 2 || !rest.hasSuffix("\""))) || (rest.hasPrefix("'") && (rest.count < 2 || !rest.hasSuffix("'")))
            var j = i + 1
            while j < header.count, let next = header[j].first, next == " " || next == "\t" || header[j] == "-" || header[j].hasPrefix("- ") {
                let item = header[j].trimmingCharacters(in: .whitespaces)
                if item == "-" || item.hasPrefix("- ") {
                    let raw = item.dropFirst(1).trimmingCharacters(in: .whitespaces)
                    // An item that is itself a map or a list, or items under a key that already had a value.
                    if !rest.isEmpty || (raw.hasPrefix("[") && !raw.hasPrefix("[[")) || raw.hasPrefix("{")
                        || (!raw.hasPrefix("\"") && !raw.hasPrefix("'") && (raw.contains(": ") || raw.hasSuffix(":"))) { complex = true }
                } else if !item.isEmpty { complex = true }
                j += 1
            }
            spans.append(PropertySpan(key: String(line[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: " \t")), from: i, to: j - 1, complex: complex))
            i = j
        }
        return spans
    }

    /// A list written on one line (`[a, "b, c"]`), split at the commas outside quotes, each item as written.
    static func flowItems(_ text: String) -> [String] {
        var items: [String] = [], current = "", quote: Character?
        var inside = text.trimmingCharacters(in: .whitespaces)
        guard inside.hasPrefix("["), inside.hasSuffix("]") else { return [] }
        inside = String(inside.dropFirst().dropLast())
        var escaped = false
        for c in inside {
            if let q = quote {
                current.append(c)
                if q == "\"" && c == "\\" && !escaped { escaped = true; continue }
                if c == q && !escaped { quote = nil }
                escaped = false
            } else if c == "\"" || c == "'" { quote = c; current.append(c) }
            else if c == "," { items.append(current.trimmingCharacters(in: .whitespaces)); current = "" }
            else { current.append(c) }
        }
        items.append(current.trimmingCharacters(in: .whitespaces))
        return items.filter { !$0.isEmpty }
    }

    /// Whether YAML would read the text as something other than that text (a number, true, a date, a list, a comment…).
    static func needsQuotes(_ text: String) -> Bool {
        guard let first = text.first, let last = text.last else { return false }
        if first.isWhitespace || last.isWhitespace || text.contains("\n") || text.contains("\t") { return true }
        if "[]{},&*!|>'\"%@`#".contains(first) { return true }
        // "-", "?" and ":" start a list item, a key or a value only before a space (or alone).
        if "-?:".contains(first) && (text.count == 1 || text.dropFirst().first!.isWhitespace) { return true }
        if text.contains(": ") || text.contains(" #") || last == ":" { return true }
        let lower = text.lowercased()
        if ["true", "false", "yes", "no", "on", "off", "null", "~", "y", "n", ".nan", ".inf", "-.inf", "+.inf"].contains(lower) { return true }
        if Double(text.replacingOccurrences(of: "_", with: "")) != nil || matches(#"^0[xo][0-9a-fA-F]+$"#, text) { return true }
        return matches(#"^\d{4}-\d{1,2}-\d{1,2}"#, text)
    }

    /// A value as it is written after `key: `, keeping the quotes it had (`old`, as written) where it had them.
    static func propertyScalar(_ value: String, old: String? = nil, plain: Bool = false) -> String {
        if plain && !value.contains("\n") && !value.contains(": ") && !value.contains(" #") { return value }
        if let old, old.hasPrefix("'"), old.hasSuffix("'"), old.count >= 2, !value.contains("\n") { return "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
        if let old, old.hasPrefix("\""), old.hasSuffix("\""), old.count >= 2 { return quoted(value) }
        return needsQuotes(value) ? quoted(value) : value
    }

    /// A property's name as written before its colon (quoted when YAML needs it, or kept quoted as typed).
    static func propertyKey(_ key: String) -> String {
        if key.count >= 2, (key.hasPrefix("\"") && key.hasSuffix("\"")) || (key.hasPrefix("'") && key.hasSuffix("'")) { return key }
        return needsQuotes(key) || key.contains(":") ? quoted(key) : key
    }

    /// The note with one property changed, only if its frontmatter still reads `drawn` (nil: the page was drawn from a
    /// note without one). A note without frontmatter gets one for its first property; removing the last takes it away.
    static func changeProperty(_ note: String, drawn: String?, _ change: PropertyChange) -> PropertyResult {
        var lines = note.components(separatedBy: "\n")
        let front = frontmatterLines(note)
        guard front.map({ $0.lines.joined(separator: "\n") }) == drawn else { return .changed }
        let header = front?.lines ?? []
        let spans = propertySpans(header)
        func named(_ key: String) -> PropertySpan? { spans.first { $0.key == key } }
        func keyPart(_ span: PropertySpan) -> String { let line = header[span.from]; return String(line[..<line.firstIndex(of: ":")!]) }
        func rest(_ span: PropertySpan) -> String {
            let line = header[span.from]
            return line[line.index(after: line.firstIndex(of: ":")!)...].trimmingCharacters(in: .whitespaces)
        }
        // A property's items as written (a block list's, a flow list's, or its one value) and the block list's indent.
        func items(_ span: PropertySpan) -> (raw: [String], indent: String?) {
            let value = rest(span)
            if !value.isEmpty { return value.hasPrefix("[") && !value.hasPrefix("[[") ? (flowItems(value), nil) : ([value], nil) }
            var raw: [String] = [], indent: String?
            for line in span.to > span.from ? Array(header[(span.from + 1) ... span.to]) : [] {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed == "-" || trimmed.hasPrefix("- ") else { continue }
                if indent == nil { indent = String(line.prefix { $0 == " " || $0 == "\t" }) }
                raw.append(trimmed.dropFirst(1).trimmingCharacters(in: .whitespaces))
            }
            return (raw, indent)
        }
        func listed(_ span: PropertySpan) -> Bool {
            let value = rest(span)
            return (value.hasPrefix("[") && !value.hasPrefix("[[")) || span.to > span.from
        }
        func replace(_ span: PropertySpan, with new: [String]) -> PropertyResult {
            let old = Array(header[span.from ... span.to])
            if new == old { return .unchanged }
            lines.replaceSubrange(span.from + 1 ... span.to + 1, with: new)
            return .written(lines.joined(separator: "\n"))
        }

        switch change {
        case let .set(key, values, list, plain):
            let values = values.map { $0.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ") }
            let span = named(key)
            if let span, span.complex { return .complex }
            let head = span.map(keyPart) ?? propertyKey(key)
            let old: (raw: [String], indent: String?) = span.map(items) ?? ([], nil)
            // The same values in the same shape (or nothing either way): nothing to write.
            if let span, old.raw.map(unquoted) == values, listed(span) == list || values.isEmpty { return .unchanged }
            var new: [String]
            if list {
                if values.isEmpty { new = [head + ": []"] } else {
                    // Items already there keep how they were written; new ones follow the list's quotes, else Obsidian's.
                    var unused = old.raw
                    let allQuoted = !old.raw.isEmpty && old.raw.allSatisfy { $0.hasPrefix("\"") }
                    let indent = old.indent ?? "  "
                    new = [head + ":"] + values.map { value in
                        if let at = unused.firstIndex(where: { unquoted($0) == value }) { return indent + "- " + unused.remove(at: at) }
                        return indent + "- " + (allQuoted ? quoted(value) : propertyScalar(value, plain: plain))
                    }
                }
            } else {
                let value = values.first ?? ""
                new = [value.isEmpty ? head + ":" : head + ": " + propertyScalar(value, old: old.raw.count == 1 ? old.raw[0] : nil, plain: plain)]
            }
            if let span { return replace(span, with: new) }
            // A new property: at the end of the frontmatter, or in a new one at the top of the note.
            if let front { lines.insert(contentsOf: new, at: front.end) } else { lines.insert(contentsOf: ["---"] + new + ["---"], at: 0) }
            return .written(lines.joined(separator: "\n"))

        case let .rename(key, to):
            let name = to.trimmingCharacters(in: .whitespaces)
            guard let span = named(key), !name.isEmpty else { return .unchanged }
            if name == key { return .unchanged }
            if spans.contains(where: { $0.from != span.from && unquoted($0.key).lowercased() == unquoted(name).lowercased() }) { return .taken }
            let line = header[span.from]
            return replace(span, with: [propertyKey(name) + String(line[line.firstIndex(of: ":")!...])] + header[(span.from + 1) ..< (span.to + 1)])

        case let .remove(key):
            guard let span = named(key), let front else { return .unchanged }
            lines.removeSubrange(span.from + 1 ... span.to + 1)
            // The last property gone: the frontmatter goes too.
            if lines[1 ..< front.end - (span.to - span.from + 1)].allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                lines.removeSubrange(0 ... front.end - (span.to - span.from + 1))
            }
            return .written(lines.joined(separator: "\n"))

        case let .retype(key, list):
            guard let span = named(key), !span.complex else { return .unchanged }
            let head = keyPart(span), old = items(span)
            if list {
                guard !listed(span), let value = old.raw.first else { return .unchanged }
                return replace(span, with: [head + ":", "  - " + value])
            }
            guard listed(span), old.raw.count <= 1 else { return .unchanged }
            return replace(span, with: [old.raw.first.map { head + ": " + $0 } ?? head + ":"])
        }
    }

    // MARK: A property's type, kept by the vault as Obsidian keeps it

    /// types.json with one property's type set (its entry found case aside, as Obsidian matches names), written as
    /// Obsidian writes it (two-space JSON), its other entries in their order. Nil when the file isn't JSON.
    static func typesJSON(_ text: String?, key: String, type: String) -> String? {
        func string(_ s: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes]) else { return "\"\"" }
            return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
        }
        var object: [String: Any] = [:]
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let read = json(Data(text.utf8)) else { return nil }
            object = read
        }
        var types = object["types"] as? [String: Any] ?? [:]
        let name = types.keys.first { $0 == key } ?? types.keys.first { $0.caseInsensitiveCompare(key) == .orderedSame } ?? key
        types[name] = type
        object["types"] = types
        guard object.count == 1, types.values.allSatisfy({ $0 is String }) else {
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            return data.map { String(decoding: $0, as: UTF8.self) }
        }
        // The names in the order the file has them, then the new one.
        var order: [String] = []
        if let text, let regex = try? NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)"\s*:"#) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text),
                      let decoded = (try? JSONSerialization.jsonObject(with: Data("[\"\(text[range])\"]".utf8))) as? [String], let found = decoded.first,
                      types[found] != nil, !order.contains(found) else { continue }
                order.append(found)
            }
        }
        order += types.keys.filter { !order.contains($0) }.sorted()
        if order.isEmpty { return "{\n  \"types\": {}\n}" }
        return "{\n  \"types\": {\n" + order.map { "    \(string($0)): \(string(types[$0] as? String ?? ""))" }.joined(separator: ",\n") + "\n  }\n}"
    }

    /// A property's type set in the vault's .obsidian/types.json (written in one step).
    static func setPropertyType(_ key: String, to type: String, vault: URL) throws {
        let file = vault.appendingPathComponent(".obsidian/types.json")
        let old = try? String(contentsOf: file, encoding: .utf8)
        guard let text = typesJSON(old, key: key, type: type) else {
            throw NSError(domain: "Sage", code: 1, userInfo: [NSLocalizedDescriptionKey: L("The vault's property types (.obsidian/types.json) couldn't be read, so they weren't changed.")])
        }
        try Data(text.utf8).write(to: file, options: .atomic)
    }

    /// The words the Properties table shows (its menu and its add button), in your language.
    static var propertyWords: [String: String] {
        ["add": L("Add property"), "type": L("Property type"), "text": L("Text"), "multitext": L("List"), "number": L("Number"), "checkbox": L("Checkbox"),
         "date": L("Date"), "datetime": L("Date & time"), "remove": L("Remove"), "yaml": L("Edit the properties as YAML")]
    }
}
