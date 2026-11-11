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
}
