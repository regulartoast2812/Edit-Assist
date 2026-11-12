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

    /// The `views:` list as lines: the file's lines, where the list's items start and end, each item's lines, and the
    /// items' indent. nil when the list can't be read item by item (one `- ` per view, every view a map).
    private static func viewItems(_ text: String) -> (lines: [String], first: Int, end: Int, items: [[String]], indent: Int)? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let head = lines.firstIndex(where: { matches(#"^views:\s*(#.*)?$"#, $0) }) else { return nil }
        func indent(_ line: String) -> Int { line.prefix { $0 == " " }.count }
        guard let first = lines[(head + 1)...].firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let n = indent(lines[first])
        guard lines[first].dropFirst(n).hasPrefix("- ") else { return nil }
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
        guard items.count == views.count, views.allSatisfy({ $0 is YamlMap }) else { return nil }
        return (lines, first, end, items, n)
    }

    private static func joined(_ lines: [String], like text: String) -> String { lines.joined(separator: text.contains("\r\n") ? "\r\n" : "\n") }

    /// The base with its views in a new order (2026-11-12, you asked: drag the view tabs to arrange them): `order` holds
    /// each view's place in the file now, in the order wanted. Only the `views:` list's items move, each with its own
    /// lines (comments included); nil when the list can't be read item by item, or `order` isn't every view once.
    static func reorderViews(_ text: String, order: [Int]) -> String? {
        guard let v = viewItems(text), order.sorted() == Array(0..<v.items.count) else { return nil }
        if order == Array(0..<v.items.count) { return text }
        return joined(Array(v.lines[..<v.first]) + order.flatMap { v.items[$0] } + Array(v.lines[v.end...]), like: text)
    }

    /// What a base view's menus change (2026-11-12, you asked: "full featured" views, as Obsidian's): the view's name,
    /// layout, a copy, removing it, a new one; a column's sort, place, and whether it's shown.
    enum BaseViewChange: Equatable, Sendable {
        case rename(String)
        case layout(String)
        case duplicate
        case delete
        case add(String)
        /// One column as the view's sort (desc or not), or nil to stop sorting by it.
        case sort(column: String, descending: Bool?)
        case move(column: String, by: Int)
        case hide(column: String)
        case show(column: String)
    }

    /// A YAML scalar as a base writes it: bare when that reads back the same, else in double quotes.
    static func viewScalar(_ text: String) -> String {
        if matches(#"^[A-Za-z0-9_][A-Za-z0-9_ .()/-]*$"#, text), !text.hasSuffix(" "), yamlScalar(text) as? String == text { return text }
        let data = (try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "\"\(text)\""
    }

    /// The base with one view changed (`index` its place in the views: list), only that view's lines touched, or nil when
    /// the list can't be read item by item or the change can't apply (the last view isn't removed).
    static func changeView(_ text: String, index: Int, _ change: BaseViewChange) -> String? {
        guard let v = viewItems(text), v.items.indices.contains(index),
              let view = ((yaml(text) as? YamlMap)?["views"] as? [Any?])?[index] as? YamlMap else { return nil }
        let n = v.indent, k = n + 2, pad = String(repeating: " ", count: k)
        var items = v.items, item = items[index]
        func indent(_ line: String) -> Int { line.prefix { $0 == " " }.count }
        // Where a key's lines are in the item: its line and the deeper (or list) lines under it.
        func range(_ key: String, in item: [String]) -> Range<Int>? {
            guard let at = item.indices.first(where: { i in
                let body = i == 0 ? item[0].dropFirst(n + 2) : (indent(item[i]) == k ? item[i].dropFirst(k) : "")
                return body.hasPrefix(key + ":")
            }) else { return nil }
            var end = at + 1
            while end < item.count, !item[end].trimmingCharacters(in: .whitespaces).isEmpty,
                  indent(item[end]) > k || indent(item[end]) == k && item[end].dropFirst(k).hasPrefix("- ") { end += 1 }
            return at..<end
        }
        func set(_ key: String, _ lines: [String]?, in item: inout [String]) {
            let fresh = (lines ?? []).map { pad + $0 }
            if let r = range(key, in: item) {
                var put = fresh
                if r.lowerBound == 0 {
                    if put.isEmpty {
                        guard r.upperBound < item.count, indent(item[r.upperBound]) == k else { return }
                        item[r.upperBound] = String(repeating: " ", count: n) + "- " + item[r.upperBound].dropFirst(k)
                    } else { put[0] = String(repeating: " ", count: n) + "- " + put[0].dropFirst(k) }
                }
                item.replaceSubrange(r, with: put)
            } else if !fresh.isEmpty {
                var at = item.count
                while at > 1, item[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
                item.insert(contentsOf: fresh, at: at)
            }
        }
        let order = ((view["order"] as? [Any?]) ?? []).map { baseText($0) }
        let bare = !order.contains { $0.hasPrefix("note.") }
        func raw(_ id: String) -> String { order.first { columnID($0) == id } ?? (id.hasPrefix("note.") && bare ? String(id.dropFirst(5)) : id) }
        func orderLines(_ list: [String]) -> [String] { ["order:"] + list.map { "  - " + viewScalar($0) } }
        var shown = order.filter { !columnID($0).isEmpty }
        if shown.isEmpty, case .show = change {} else if shown.isEmpty { shown = ["file.name"] }
        switch change {
        case .rename(let name):
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            set("name", ["name: " + viewScalar(name)], in: &item)
        case .layout(let type):
            guard ["table", "cards"].contains(type) else { return nil }
            set("type", ["type: " + type], in: &item)
        case .duplicate:
            var copy = item
            let names = (((yaml(text) as? YamlMap)?["views"] as? [Any?]) ?? []).compactMap { ($0 as? YamlMap)?["name"] }.map { baseText($0) }
            let base = baseText(view["name"]).isEmpty ? "View" : baseText(view["name"])
            var name = base + " copy", i = 2
            while names.contains(name) { name = base + " copy \(i)"; i += 1 }
            set("name", ["name: " + viewScalar(name)], in: &copy)
            while copy.count > 1, copy.last!.trimmingCharacters(in: .whitespaces).isEmpty { copy.removeLast() }
            items.insert(copy, at: index + 1)
        case .delete:
            guard items.count > 1 else { return nil }
            items.remove(at: index)
        case .add(let type):
            guard ["table", "cards"].contains(type) else { return nil }
            let names = (((yaml(text) as? YamlMap)?["views"] as? [Any?]) ?? []).compactMap { ($0 as? YamlMap)?["name"] }.map { baseText($0) }
            let base = type == "cards" ? "Cards" : "Table"
            var name = base, i = 2
            while names.contains(name) { name = "\(base) \(i)"; i += 1 }
            let lead = String(repeating: " ", count: n)
            items.insert([lead + "- type: " + type, pad + "name: " + viewScalar(name)] + orderLines(shown).map { pad + $0 }, at: index + 1)
        case let .sort(column, descending):
            let sorts = ((view["sort"] as? [Any?]) ?? []).compactMap { $0 as? YamlMap }
            var kept = sorts.filter { columnID(baseText($0["property"])) != column }.map { (baseText($0["property"]), baseText($0["direction"]).uppercased() == "DESC") }
            if let descending { kept = [(raw(column), descending)] }
            set("sort", kept.isEmpty ? nil : ["sort:"] + kept.flatMap { ["  - property: " + viewScalar($0.0), "    direction: " + ($0.1 ? "DESC" : "ASC")] }, in: &item)
        case let .move(column, by):
            guard let at = shown.firstIndex(where: { columnID($0) == column }), shown.indices.contains(at + by) else { return nil }
            shown.swapAt(at, at + by)
            set("order", orderLines(shown), in: &item)
        case .hide(let column):
            let left = shown.filter { columnID($0) != column }
            guard !left.isEmpty, left.count < shown.count else { return nil }
            set("order", orderLines(left), in: &item)
        case .show(let column):
            guard !shown.contains(where: { columnID($0) == column }) else { return nil }
            set("order", orderLines(shown + [raw(column)]), in: &item)
        }
        if case .duplicate = change {} else if case .delete = change {} else if case .add = change {} else { items[index] = item }
        return joined(Array(v.lines[..<v.first]) + items.flatMap { $0 } + Array(v.lines[v.end...]), like: text)
    }
}
