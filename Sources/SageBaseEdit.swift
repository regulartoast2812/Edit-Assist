import Foundation

/// Editing a Base's table in place (2026-11-11, you asked: "full on editing setups for .base files, text edit, drop down,
/// copy paste"). Foundation only, like the rest of `Study`. A cell is one property of one note; it is written as the
/// Properties table writes it (`changeProperty`: only that property's lines, quotes kept, the note kept first through
/// `writeNote`), and only if the note's value still reads as the table showed it, so an edit made in Obsidian since is
/// never written over. Formula and file columns are read only.
extension Study {
    /// One cell changed: the note (vault path), the column's property, the values it showed (`was`) and the new ones.
    struct BaseCellEdit: Equatable, Sendable {
        var path: String
        var key: String
        var was: [String]
        var values: [String]
        var list: Bool
        var plain: Bool
    }

    enum BaseCellResult: Equatable, Sendable {
        case written(String)
        case unchanged
        /// The note's value isn't what the table showed (changed elsewhere): nothing written.
        case changed
        /// A value over several lines (a block, a map) the cell can't show whole.
        case complex
    }

    /// A property's values as a cell holds them: a list's items, one value, or none (empty text counts as none).
    static func cellValues(_ value: Any?) -> [String] {
        let all: [Any?] = (value as? [Any?]) ?? [value]
        return all.compactMap { item -> String? in
            if item == nil || item is YamlMap { return nil }
            let text = baseText(item)
            return text.isEmpty ? nil : text
        }
    }

    /// The note with one cell's property set, under the name the note already writes it with (case aside, as Obsidian
    /// matches property names), else the column's.
    static func changeCell(_ note: String, _ edit: BaseCellEdit) -> BaseCellResult {
        let props = yaml(split(note).header) as? YamlMap
        guard cellValues(props?.value(ignoringCase: edit.key)) == edit.was.filter({ !$0.isEmpty }) else { return .changed }
        let front = frontmatterLines(note)
        let spans = propertySpans(front?.lines ?? [])
        let key = spans.first { unquoted($0.key).lowercased() == edit.key.lowercased() }?.key ?? edit.key
        let values = edit.values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        switch changeProperty(note, drawn: front.map { $0.lines.joined(separator: "\n") }, .set(key: key, values: values, list: edit.list, plain: edit.plain)) {
        case .written(let text): return .written(text)
        case .complex: return .complex
        case .changed, .taken: return .changed
        case .unchanged: return .unchanged
        }
    }

    /// How a column's cells are edited: the vault's type for the property (types.json), else what its values look like.
    /// "select" is a few repeated words (drawn as chips): a menu of the values the vault already uses, or a new one.
    static func cellKind(key: String, type: String?, values: [Any?], chips: Bool) -> String {
        switch type?.lowercased() {
        case "multitext", "tags", "aliases": return "list"
        case "number": return "number"
        case "checkbox": return "checkbox"
        case "date": return "date"
        case "datetime": return "datetime"
        case "text": return chips ? "select" : "text"
        default: break
        }
        if ["tags", "aliases", "cssclasses"].contains(key.lowercased()) || values.contains(where: { $0 is [Any?] }) { return "list" }
        let texts = values.compactMap { $0 as? String }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if chips { return "select" }
        guard !texts.isEmpty else { return "text" }
        if texts.allSatisfy({ ["true", "false"].contains($0.lowercased()) }) { return "checkbox" }
        if texts.allSatisfy({ Double($0) != nil }) { return "number" }
        if texts.allSatisfy({ matches(#"^\d{4}-\d{2}-\d{2}$"#, $0) }) { return "date" }
        if texts.allSatisfy({ matches(#"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2})?$"#, $0) }) { return "datetime" }
        return "text"
    }

    /// The vault's property types (.obsidian/types.json), as the note view reads them.
    static func vaultTypes(_ vault: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: vault.appendingPathComponent(".obsidian/types.json")), let kept = json(data)?["types"] as? [String: Any] else { return [:] }
        return kept.compactMapValues { $0 as? String }
    }

    /// The base with its views in a new order (2026-11-12, you asked: drag the view tabs to arrange them): `order` holds
    /// each view's place in the file now, in the order wanted. Only the `views:` list's items move, each with its own
    /// lines (comments included); nil when the list can't be read item by item, or `order` isn't every view once.
    static func reorderViews(_ text: String, order: [Int]) -> String? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let head = lines.firstIndex(where: { matches(#"^views:\s*(#.*)?$"#, $0) }) else { return nil }
        func indent(_ line: String) -> Int { line.prefix { $0 == " " }.count }
        guard let first = lines[(head + 1)...].firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let n = indent(lines[first])
        guard lines[first].dropFirst(n).hasPrefix("-") else { return nil }
        var end = first
        while end < lines.count {
            let line = lines[end], blank = line.trimmingCharacters(in: .whitespaces).isEmpty || indent(line) >= n && line.dropFirst(indent(line)).hasPrefix("#")
            if !blank, indent(line) < n || indent(line) == n && !line.dropFirst(n).hasPrefix("-") { break }
            end += 1
        }
        while end > first, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
        var items: [[String]] = []
        for line in lines[first..<end] {
            if indent(line) == n, line.dropFirst(n).hasPrefix("-") { items.append([line]) } else { items[items.count - 1].append(line) }
        }
        let views = ((yaml(text) as? YamlMap)?["views"] as? [Any?]) ?? []
        guard items.count == views.count, views.allSatisfy({ $0 is YamlMap }), order.sorted() == Array(0..<items.count) else { return nil }
        if order == Array(0..<items.count) { return text }
        let moved = Array(lines[..<first]) + order.flatMap { items[$0] } + Array(lines[end...])
        return moved.joined(separator: text.contains("\r\n") ? "\r\n" : "\n")
    }
}
