import CryptoKit
import Foundation

/// Sage's Obsidian Bases, canvases and Vault Agent's file embeds (2026-11-08, built first in Creative Assist, the Windows
/// app, and brought back on 2026-11-09). Foundation only, so the checks compile it as it is.
///
/// What Obsidian draws from more than one file: a Base (.base, a YAML file of filters, formulas and views over the vault's
/// notes, drawn as a table or cards), a canvas (.canvas, JSON cards and arrows, drawn pannable as the Vault Agent plugin
/// draws it), and Vault Agent's ```file-embed blocks (a canvas, a web page, a CSV, code or any file shown inside a note).
/// Read only: nothing here writes, except a canvas or a note's text you edited (saveCanvas, saveNoteBody).
extension Study {
    // MARK: YAML: what .base files and note properties use (block maps and lists, quoted and plain values, [flow] lists)

    /// A YAML map, its keys in the order they were written.
    struct YamlMap {
        var pairs: [(key: String, value: Any?)] = []
        var keys: [String] { pairs.map(\.key) }
        var isEmpty: Bool { pairs.isEmpty }
        subscript(key: String) -> Any? { pairs.first { $0.key == key }?.value ?? nil }
        func has(_ key: String) -> Bool { pairs.contains { $0.key == key } }
        mutating func set(_ key: String, _ value: Any?) {
            if let index = pairs.firstIndex(where: { $0.key == key }) { pairs[index].value = value } else { pairs.append((key, value)) }
        }
        /// Case aside, as a note's properties are read.
        func value(ignoringCase key: String) -> Any? { pairs.first { same($0.key, key) }?.value ?? nil }
        func has(ignoringCase key: String) -> Bool { pairs.contains { same($0.key, key) } }
        mutating func set(ignoringCase key: String, _ value: Any?) {
            if let index = pairs.firstIndex(where: { same($0.key, key) }) { pairs[index].value = value } else { pairs.append((key, value)) }
        }
    }

    /// A map (YamlMap, keys in order), a list ([Any?]), a string or nil.
    static func yaml(_ text: String) -> Any? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#") && trimmed != "---"
            }
            .map { (indent: $0.prefix { $0 == " " }.count, text: $0.trimmingCharacters(in: .whitespaces)) }
        let reader = YamlReader(lines: lines)
        return lines.isEmpty ? nil : reader.block(lines[0].indent)
    }

    private final class YamlReader {
        var lines: [(indent: Int, text: String)]
        var at = 0
        init(lines: [(indent: Int, text: String)]) { self.lines = lines }

        func isItem(_ text: String) -> Bool { text == "-" || text.hasPrefix("- ") }

        func block(_ indent: Int) -> Any? {
            guard at < lines.count else { return nil }
            return isItem(lines[at].text) ? list(indent) : map(indent)
        }

        func list(_ indent: Int) -> [Any?] {
            var list: [Any?] = []
            while at < lines.count && lines[at].indent == indent && isItem(lines[at].text) {
                let text = lines[at].text
                let rest = String(text.dropFirst().drop { $0 == " " || $0 == "\t" })
                if rest.isEmpty {
                    at += 1
                    list.append(at < lines.count && lines[at].indent > indent ? block(lines[at].indent) : nil)
                    continue
                }
                if Study.yamlKey(rest) != nil {
                    // "- key: value" starts a map whose keys line up with "key".
                    let inner = indent + (text.count - rest.count)
                    lines[at] = (inner, rest)
                    list.append(map(inner))
                    continue
                }
                at += 1
                list.append(Study.yamlScalar(rest))
            }
            return list
        }

        func map(_ indent: Int) -> YamlMap {
            var map = YamlMap()
            while at < lines.count && lines[at].indent == indent && !lines[at].text.hasPrefix("- ") && lines[at].text != "-" {
                let text = lines[at].text
                let key = Study.yamlKey(text)
                at += 1
                guard let key else { continue }
                let value = text[text.index(after: key.end)...].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty && !["|", ">", "|-", ">-"].contains(value) { map.set(key.key, Study.yamlScalar(value)); continue }
                if at < lines.count && lines[at].indent > indent { map.set(key.key, block(lines[at].indent)) }
                else if at < lines.count && lines[at].indent == indent && lines[at].text.hasPrefix("- ") { map.set(key.key, list(indent)) }
                else { map.set(key.key, nil) }
            }
            return map
        }
    }

    /// "key: value" → the key and where its colon is; nil when the line isn't one (an expression, a plain value).
    static func yamlKey(_ text: String) -> (key: String, end: String.Index)? {
        if let first = text.first, first == "\"" || first == "'" {
            guard let close = text[text.index(after: text.startIndex)...].firstIndex(of: first) else { return nil }
            let colon = text.index(after: close)
            guard colon < text.endIndex, text[colon] == ":" else { return nil }
            let after = text.index(after: colon)
            guard after == text.endIndex || text[after] == " " else { return nil }
            return (String(text[text.index(after: text.startIndex) ..< close]), colon)
        }
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            if "(\"'[{=!<>".contains(c) { return nil }
            if c == ":" {
                let next = text.index(after: index)
                if next == text.endIndex || text[next] == " " {
                    return index == text.startIndex ? nil : (text[..<index].trimmingCharacters(in: .whitespaces), index)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    static func yamlScalar(_ raw: String) -> Any? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "null" || value == "~" { return nil }
        if value.count >= 2 && value.hasPrefix("\"") && value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\\", with: "\\")
        }
        if value.count >= 2 && value.hasPrefix("'") && value.hasSuffix("'") { return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
        if value.hasPrefix("[") && value.hasSuffix("]") && !value.hasPrefix("[[") {
            let items: [Any?] = splitTop(String(value.dropFirst().dropLast()), ",").map { yamlScalar($0) }
            return items.filter { ($0 as? String) != "" }
        }
        return value
    }

    /// The text split at `separator`, but not inside quotes or brackets.
    static func splitTop(_ text: String, _ separator: Character) -> [String] {
        var parts: [String] = [], depth = 0, quote: Character?, current = ""
        var skip = false
        for c in text {
            if skip { current.append(c); skip = false; continue }
            if let open = quote {
                if c == "\\" { skip = true } else if c == open { quote = nil }
                current.append(c)
                continue
            }
            if c == "\"" || c == "'" { quote = c }
            else if "([{".contains(c) { depth += 1 }
            else if ")]}".contains(c) { depth -= 1 }
            else if c == separator && depth == 0 { parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines)); current = ""; continue }
            current.append(c)
        }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return parts
    }

    // MARK: The vault's notes, as Bases sees them

    /// A file with its properties, the files it links to (by path, or "?name" when no file has that name) and its tags.
    struct BaseNote: @unchecked Sendable {
        var item: VaultItem
        var props: YamlMap
        /// The files it links to, in the order first met (case aside, as Obsidian compares paths).
        var links: [String]
        var linkSet: Set<String>
        var tags: [String]
        /// A property by name, case aside.
        func prop(_ name: String) -> Any? { props.value(ignoringCase: name) }
        func hasProp(_ name: String) -> Bool { props.has(ignoringCase: name) }
        func links(to key: String) -> Bool { linkSet.contains(key.lowercased()) }
    }

    private final class NoteCache: @unchecked Sendable {
        private var notes: [String: (modified: Date, note: BaseNote)] = [:]
        private let lock = NSLock()
        func get(_ key: String) -> (modified: Date, note: BaseNote)? { lock.lock(); defer { lock.unlock() }; return notes[key] }
        func set(_ key: String, _ value: (modified: Date, note: BaseNote)) { lock.lock(); defer { lock.unlock() }; notes[key] = value }
    }
    private static let noteCache = NoteCache()

    private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }
    private static let wikiLink = regex(#"\[\[([^\]\|#\^\n]+)"#)
    private static let inlineTag = regex(#"(?<=^|\s)#([\p{L}\p{N}_/-]*[\p{L}_/-][\p{L}\p{N}_/-]*)"#)
    private static let wikiValue = regex(#"^\[\[([^\]]+)\]\]$"#)
    private static let plainValue = regex(#"^[^\d\[\]#/:][^\[\]/:]{0,23}$"#)
    private static let fileEmbedSlot = regex(#"<div class="block-language-file-embed" data-sage-embed="([^"]*)" data-sage-height="(\d*)"></div>"#)
    private static let otherEmbed = regex(#"<span class="internal-embed"(?: alt="([^"]*)")?><a class="internal-link" href="sage-note:([^"]*)">[^<]*</a></span>"#)

    /// The groups of the first match of a compiled expression ("" for a group not matched), or nil.
    private static func groups(_ regex: NSRegularExpression, _ text: String) -> [String]? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0 ..< match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }

    private static func allGroups(_ regex: NSRegularExpression, _ text: String) -> [[String]] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0 ..< match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with: ([String]) -> String) -> String {
        var result = "", last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text) else { continue }
            let groups = (0 ..< match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
            result += text[last ..< whole.lowerBound] + with(groups)
            last = whole.upperBound
        }
        return result + text[last...]
    }

    /// Finds a [[link]]'s file by path or name, as Obsidian does (the shortest path when names repeat).
    final class LinkFinder: @unchecked Sendable {
        private var byName: [String: String] = [:], byPath: [String: String] = [:]
        init(_ items: [VaultItem]) {
            let files = items.filter { !$0.folder }.enumerated().sorted { $0.element.path.utf16.count != $1.element.path.utf16.count ? $0.element.path.utf16.count < $1.element.path.utf16.count : $0.offset < $1.offset }
            for (_, item) in files {
                let bare = item.ext == ".md" ? String(item.path.dropLast(3)) : item.path
                if byPath[bare.lowercased()] == nil { byPath[bare.lowercased()] = item.path }
                if byPath[item.path.lowercased()] == nil { byPath[item.path.lowercased()] = item.path }
                let name = (item.ext == ".md" ? String(item.name.dropLast(3)) : item.name).lowercased()
                if byName[name] == nil { byName[name] = item.path }
            }
        }
        /// The file's path, or "?name" when there's none.
        func key(_ link: String) -> String {
            var target = String(link.split(separator: "|", omittingEmptySubsequences: false).first ?? "")
            target = String(target.split(separator: "#", omittingEmptySubsequences: false).first ?? "")
            target = target.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\", with: "/")
            while target.hasPrefix("/") { target.removeFirst() }
            if target.hasPrefix("[[") { target = String(target.dropFirst(2)); while target.hasSuffix("]") { target.removeLast() } }
            if let path = byPath[target.lowercased()] { return path }
            let name = target.lastIndex(of: "/").map { String(target[target.index(after: $0)...]) } ?? target
            if let path = byName[name.lowercased()] { return path }
            if name.lowercased().hasSuffix(".md"), let path = byName[String(name.dropLast(3)).lowercased()] { return path }
            return "?" + name.lowercased()
        }
    }

    /// Every file in the vault as Bases sees it; notes read once and kept until they change.
    static func baseNotes(vault: URL, items: [VaultItem], finder: LinkFinder) -> [BaseNote] {
        var notes: [BaseNote] = []
        for item in items where !item.folder {
            let cacheKey = vault.standardizedFileURL.path + "|" + item.path.lowercased()
            if let kept = noteCache.get(cacheKey), kept.modified == item.modified { notes.append(kept.note); continue }
            var props = YamlMap(), links: [String] = [], linkSet: Set<String> = [], tags: [String] = []
            if item.ext == ".md" {
                let text = (baseRead(vault.appendingPathComponent(item.path)) ?? "").replacingOccurrences(of: "\r\n", with: "\n")
                let (header, body) = split(text)
                if !header.isEmpty, let map = yaml(header) as? YamlMap {
                    for (key, value) in map.pairs { props.set(ignoringCase: key, value) }
                }
                for match in allGroups(wikiLink, text) {
                    let key = finder.key(match[1])
                    if linkSet.insert(key.lowercased()).inserted { links.append(key) }
                }
                if props.has(ignoringCase: "tags") {
                    let listed = props.value(ignoringCase: "tags")
                    for tag in (listed as? [Any?]) ?? [listed] {
                        let text = baseText(tag)
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            tags.append(String(text.trimmingCharacters(in: .whitespacesAndNewlines).drop { $0 == "#" }))
                        }
                    }
                }
                for match in allGroups(inlineTag, body) { tags.append(match[1]) }
            }
            let note = BaseNote(item: item, props: props, links: links, linkSet: linkSet, tags: tags)
            noteCache.set(cacheKey, (item.modified, note))
            notes.append(note)
        }
        return notes
    }

    /// What a note is, for its icon in Sage's tree: a clipping of a YouTube video ("video") or of a web page ("web"), a
    /// quote, a course; plus the icon and colour its own properties give it (Notebook Navigator's "icon" and "color"
    /// fields), when they do.
    static func noteKind(_ note: BaseNote) -> (kind: String?, icon: String?, color: String?) {
        var kind: String?
        let s = note.prop("source")
        let source = note.hasProp("source") ? baseText((s as? [Any?])?.first ?? s).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if source.range(of: "youtube.com", options: .caseInsensitive) != nil || source.range(of: "youtu.be", options: .caseInsensitive) != nil { kind = "video" }
        else if source.lowercased().hasPrefix("http") { kind = "web" }
        if note.hasProp("categories") {
            let c = note.prop("categories")
            for category in (c as? [Any?]) ?? [c] {
                let trimmed = baseText(category).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                let name = String(trimmed.split(separator: "|", omittingEmptySubsequences: false).first ?? "")
                if same(name, "Quotes") { kind = "quote" } else if same(name, "Courses") { kind = "course" }
            }
        }
        let icon = note.hasProp("icon") ? baseText(note.prop("icon")).trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let color = note.hasProp("color") ? baseText(note.prop("color")).trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return (kind, icon?.isEmpty == false ? icon : nil, color?.isEmpty == false ? color : nil)
    }

    /// A note's kind (noteKind) from its path and text, for a file read on its own.
    static func fileKind(path: String, text: String?) -> (kind: String?, icon: String?, color: String?) {
        var props = YamlMap()
        if let text {
            let (header, _) = split(text.replacingOccurrences(of: "\r\n", with: "\n"))
            if !header.isEmpty, let map = yaml(header) as? YamlMap { for (key, value) in map.pairs { props.set(ignoringCase: key, value) } }
        }
        return noteKind(BaseNote(item: VaultItem(path: path, folder: false), props: props, links: [], linkSet: [], tags: []))
    }

    // MARK: Bases' formulas: Obsidian's expression language, the part the vault's bases use

    struct LinkValue { var target: String; var display: String? }
    struct FileValue { var note: BaseNote }
    private enum BaseScope { case note, formula }

    private struct FormulaProblem: Error { var message: String }

    private final class BaseContext {
        let note: BaseNote, finder: LinkFinder, selfNote: BaseNote?
        let formulas: [String: (BaseContext) throws -> Any?]
        private var done: [String: Any?] = [:]
        private var working: Set<String> = []
        init(_ note: BaseNote, _ finder: LinkFinder, _ formulas: [String: (BaseContext) throws -> Any?], _ selfNote: BaseNote?) {
            self.note = note; self.finder = finder; self.formulas = formulas; self.selfNote = selfNote
        }
        func formula(_ name: String) -> Any? {
            let key = name.lowercased()
            if let value = done[key] { return value }
            guard let formula = formulas[key], working.insert(key).inserted else { return nil }
            let value = (try? formula(self)) ?? nil
            working.remove(key)
            done[key] = value
            return value
        }
    }

    private typealias Compiled = (BaseContext) throws -> Any?

    /// An expression ("file.inFolder(\"Quests\") && Type == \"Clipping\"") made into a function of a note.
    private static func baseExpression(_ text: String) throws -> Compiled {
        let parser = FormulaParser(tokens: try baseTokens(text))
        let parsed = try parser.or()
        if parser.at < parser.tokens.count { throw FormulaProblem(message: "Unexpected “\(parser.tokens[parser.at].text)”") }
        return parsed
    }

    private final class FormulaParser {
        let tokens: [(kind: Character, text: String)]
        var at = 0
        init(tokens: [(kind: Character, text: String)]) { self.tokens = tokens }

        func peek() -> (kind: Character, text: String) { at < tokens.count ? tokens[at] : ("\0", "") }
        func take(_ op: String) -> Bool {
            if at < tokens.count && tokens[at].kind == "o" && tokens[at].text == op { at += 1; return true }
            return false
        }
        func expect(_ op: String) throws { if !take(op) { throw FormulaProblem(message: "Expected “\(op)”") } }

        func or() throws -> Compiled {
            var left = try and()
            while take("||") { let a = left, b = try and(); left = { c in if Study.truthy(try a(c)) { return true }; return Study.truthy(try b(c)) } }
            return left
        }
        func and() throws -> Compiled {
            var left = try equality()
            while take("&&") { let a = left, b = try equality(); left = { c in if !Study.truthy(try a(c)) { return false }; return Study.truthy(try b(c)) } }
            return left
        }
        func equality() throws -> Compiled {
            var left = try relation()
            while true {
                if take("==") { let a = left, b = try relation(); left = { c in Study.baseSame(try a(c), try b(c), c.finder) } }
                else if take("!=") { let a = left, b = try relation(); left = { c in !Study.baseSame(try a(c), try b(c), c.finder) } }
                else { return left }
            }
        }
        func relation() throws -> Compiled {
            let left = try sum()
            for op in ["<=", ">=", "<", ">"] where take(op) {
                let a = left, b = try sum()
                return { c in
                    let x = try a(c), y = try b(c)
                    if x == nil || y == nil { return false }
                    let order = Study.baseOrder(x, y)
                    switch op { case "<": return order < 0; case ">": return order > 0; case "<=": return order <= 0; default: return order >= 0 }
                }
            }
            return left
        }
        func sum() throws -> Compiled {
            var left = try product()
            while true {
                if take("+") {
                    let a = left, b = try product()
                    left = { c in
                        let x = try a(c), y = try b(c)
                        if let n = Study.number(x), let m = Study.number(y), !(x is String), !(y is String) { return n + m }
                        return Study.baseText(x) + Study.baseText(y)
                    }
                } else if take("-") {
                    let a = left, b = try product(); left = { c in (Study.number(try a(c)) ?? 0) - (Study.number(try b(c)) ?? 0) }
                } else { return left }
            }
        }
        func product() throws -> Compiled {
            var left = try unary()
            while true {
                if take("*") { let a = left, b = try unary(); left = { c in (Study.number(try a(c)) ?? 0) * (Study.number(try b(c)) ?? 0) } }
                else if take("/") {
                    let a = left, b = try unary()
                    left = { c in guard let d = Study.number(try b(c)), d != 0 else { return nil }; return (Study.number(try a(c)) ?? 0) / d }
                } else if take("%") {
                    let a = left, b = try unary()
                    left = { c in guard let d = Study.number(try b(c)), d != 0 else { return nil }; return (Study.number(try a(c)) ?? 0).truncatingRemainder(dividingBy: d) }
                } else { return left }
            }
        }
        func unary() throws -> Compiled {
            if take("!") { let a = try unary(); return { c in !Study.truthy(try a(c)) } }
            if take("-") { let a = try unary(); return { c in -(Study.number(try a(c)) ?? 0) } }
            return try postfix()
        }
        func arguments() throws -> [Compiled] {
            var args: [Compiled] = []
            if take(")") { return args }
            repeat { args.append(try or()) } while take(",")
            try expect(")")
            return args
        }
        func postfix() throws -> Compiled {
            var (value, name) = try primary()
            while true {
                if take(".") {
                    let member = peek()
                    if member.kind != "n" { throw FormulaProblem(message: "Expected a name after “.”") }
                    at += 1
                    let target = value, m = member.text
                    if take("(") { let args = try arguments(); value = { c in try Study.baseMethod(try target(c), m, args, c) } }
                    else { value = { c in Study.baseMember(try target(c), m, c) } }
                    name = nil
                } else if take("[") {
                    let index = try or()
                    try expect("]")
                    let target = value
                    value = { c in
                        let t = try target(c), i = try index(c)
                        if let list = t as? [Any?], let n = Study.number(i), n >= 0, n < Double(list.count) { return list[Int(n)] }
                        return Study.baseMember(t, Study.baseText(i), c)
                    }
                    name = nil
                } else if let function = name, take("(") {
                    let args = try arguments()
                    value = { c in try Study.baseCall(function, args, c) }
                    name = nil
                } else { return value }
            }
        }
        func primary() throws -> (Compiled, String?) {
            let token = peek()
            at += 1
            switch token.kind {
            case "d":
                guard let n = Double(token.text) else { throw FormulaProblem(message: "“\(token.text)” isn't a number") }
                return ({ _ in n }, nil)
            case "s":
                let s = token.text
                return ({ _ in s }, nil)
            case "n":
                let word = token.text
                let value: Compiled
                switch word {
                case "true": value = { _ in true }
                case "false": value = { _ in false }
                case "null": value = { _ in nil }
                case "file": value = { c in FileValue(note: c.note) }
                case "this": value = { c in c.selfNote.map { FileValue(note: $0) } }
                case "note": value = { _ in BaseScope.note }
                case "formula": value = { _ in BaseScope.formula }
                default: value = { c in c.note.prop(word) }
                }
                return (value, word)
            case "o" where token.text == "(":
                let inner = try or()
                try expect(")")
                return (inner, nil)
            case "o" where token.text == "[":
                var items: [Compiled] = []
                if !take("]") { repeat { items.append(try or()) } while take(","); try expect("]") }
                return ({ c in try items.map { try $0(c) } as [Any?] }, nil)
            default: break
            }
            throw FormulaProblem(message: token.kind == "\0" ? "The formula ends too soon" : "Unexpected “\(token.text)”")
        }
    }

    private static func isNameStart(_ c: Character) -> Bool {
        c.isLetter || c == "_" || c == "$" || c.unicodeScalars.first.map { $0.properties.generalCategory == .otherSymbol || $0.value > 0xFFFF } == true
    }
    private static func isNamePart(_ c: Character) -> Bool {
        isNameStart(c) || c.isNumber || c.unicodeScalars.first.map { $0.properties.generalCategory == .nonspacingMark } == true
    }

    private static func baseTokens(_ text: String) throws -> [(kind: Character, text: String)] {
        var tokens: [(kind: Character, text: String)] = []
        let chars = Array(text)
        var i = 0
        func digit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c == "\"" || c == "'" {
                var word = "", j = i + 1
                while j < chars.count && chars[j] != c {
                    if chars[j] == "\\" && j + 1 < chars.count {
                        j += 1
                        word.append(chars[j] == "n" ? "\n" : chars[j] == "t" ? "\t" : chars[j])
                    } else { word.append(chars[j]) }
                    j += 1
                }
                tokens.append(("s", word))
                i = j + 1
                continue
            }
            let afterOperator = tokens.isEmpty || (tokens[tokens.count - 1].kind == "o" && tokens[tokens.count - 1].text != ")" && tokens[tokens.count - 1].text != "]")
            if digit(c) || (c == "." && i + 1 < chars.count && digit(chars[i + 1]) && afterOperator) {
                var j = i
                while j < chars.count && (digit(chars[j]) || chars[j] == ".") { j += 1 }
                tokens.append(("d", String(chars[i ..< j])))
                i = j
                continue
            }
            if isNameStart(c) {
                var j = i
                while j < chars.count && isNamePart(chars[j]) { j += 1 }
                tokens.append(("n", String(chars[i ..< j])))
                i = j
                continue
            }
            let two = i + 1 < chars.count ? String(chars[i ... i + 1]) : ""
            if ["==", "!=", "<=", ">=", "&&", "||"].contains(two) { tokens.append(("o", two)); i += 2; continue }
            if "+-*/%!<>()[],.".contains(c) { tokens.append(("o", String(c))); i += 1; continue }
            throw FormulaProblem(message: "Unexpected “\(c)”")
        }
        return tokens
    }

    private static func baseMember(_ target: Any?, _ name: String, _ c: BaseContext) -> Any? {
        switch target {
        case let scope as BaseScope: return scope == .note ? c.note.prop(name) : c.formula(name)
        case let file as FileValue:
            let item = file.note.item
            switch name {
            case "name", "fullname": return item.name
            case "basename": return item.ext.isEmpty ? item.name : String(item.name.dropLast(item.ext.count))
            case "path": return item.path
            case "folder": return item.parent
            case "ext": return String(item.ext.drop { $0 == "." })
            case "ctime": return item.created
            case "mtime": return item.modified
            case "tags": return file.note.tags.map { "#" + $0 } as [Any?]
            case "links": return file.note.links.map { LinkValue(target: $0, display: nil) } as [Any?]
            case "properties": return file.note.props.keys as [Any?]
            case "file": return file
            default: return nil
            }
        case let s as String: return name == "length" ? Double(s.utf16.count) : nil
        case let list as [Any?]: return name == "length" ? Double(list.count) : nil
        case let link as LinkValue: return name == "path" ? link.target : nil
        default: return nil
        }
    }

    private static func baseMethod(_ target: Any?, _ name: String, _ args: [Compiled], _ c: BaseContext) throws -> Any? {
        func arg(_ i: Int) throws -> Any? { i < args.count ? try args[i](c) : nil }
        switch target {
        case let file as FileValue:
            let item = file.note.item
            switch name {
            case "inFolder":
                let folder = baseText(try arg(0)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return folder.isEmpty || same(item.parent, folder) || item.parent.lowercased().hasPrefix(folder.lowercased() + "/")
            case "hasLink":
                guard !args.isEmpty, let linked = linkKey(try arg(0), c.finder) else { return false }
                return file.note.links(to: linked)
            case "hasTag":
                for a in args {
                    let t = String(baseText(try a(c)).drop { $0 == "#" })
                    if file.note.tags.contains(where: { same($0, t) || $0.lowercased().hasPrefix(t.lowercased() + "/") }) { return true }
                }
                return false
            case "hasProperty": return file.note.hasProp(baseText(try arg(0)))
            case "asLink":
                let display = baseText(try arg(0))
                return LinkValue(target: item.path, display: display.isEmpty ? nil : display)
            default: return nil
            }
        case let list as [Any?]:
            switch name {
            case "contains": let x = try arg(0); return list.contains { baseSame($0, x, c.finder) }
            case "containsAny":
                for a in args { let x = try a(c); if list.contains(where: { baseSame($0, x, c.finder) }) { return true } }
                return false
            case "containsAll":
                for a in args { let x = try a(c); if !list.contains(where: { baseSame($0, x, c.finder) }) { return false } }
                return true
            case "isEmpty": return list.isEmpty
            case "join": return list.map(baseText).joined(separator: baseText(try arg(0)))
            case "sort": return stableSorted(list) { baseOrder($0, $1) }
            case "reverse": return Array(list.reversed())
            case "unique":
                var seen: Set<String> = [], unique: [Any?] = []
                for value in list where seen.insert(distinctKey(value)).inserted { unique.append(value) }
                return unique
            case "toString": return list.map(baseText).joined(separator: ", ")
            default: return nil
            }
        case nil:
            return name == "isEmpty" ? true : nil
        default: break
        }
        let s = baseText(target)
        switch name {
        case "contains": let x = baseText(try arg(0)); return x.isEmpty || s.contains(x)
        case "containsAny":
            for a in args { let x = baseText(try a(c)); if x.isEmpty || s.contains(x) { return true } }
            return false
        case "containsAll":
            for a in args { let x = baseText(try a(c)); if !x.isEmpty && !s.contains(x) { return false } }
            return true
        case "startsWith": return s.hasPrefix(baseText(try arg(0)))
        case "endsWith": return s.hasSuffix(baseText(try arg(0)))
        case "replace":
            let find = baseText(try arg(0))
            guard !find.isEmpty, let range = s.range(of: find, options: .literal) else { return s }
            return s.replacingCharacters(in: range, with: baseText(try arg(1)))
        case "lower": return s.lowercased()
        case "upper": return s.uppercased()
        case "title":
            // As .NET's ToTitleCase: each word's first letter up and the rest down, a word all in capitals kept.
            return s.components(separatedBy: " ").map { word in
                word.isEmpty || (word == word.uppercased() && word != word.lowercased()) ? word : word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }.joined(separator: " ")
        case "trim": return s.trimmingCharacters(in: .whitespacesAndNewlines)
        case "isEmpty": return s.isEmpty
        case "split":
            let separator = baseText(try arg(0))
            return (separator.isEmpty ? [s] : s.components(separatedBy: separator)) as [Any?]
        case "slice":
            let chars = Array(s)
            let from = Int(min(max(number(try arg(0)) ?? 0, 0), Double(chars.count)))
            let to = args.count > 1 ? Int(min(max(number(try arg(1)) ?? Double(chars.count), Double(from)), Double(chars.count))) : chars.count
            return String(chars[from ..< to])
        case "toString": return s
        default: return nil
        }
    }

    private static func baseCall(_ name: String, _ args: [Compiled], _ c: BaseContext) throws -> Any? {
        func arg(_ i: Int) throws -> Any? { i < args.count ? try args[i](c) : nil }
        switch name {
        case "if": return truthy(try arg(0)) ? try arg(1) : try arg(2)
        case "link": return LinkValue(target: baseText(try arg(0)), display: args.count > 1 ? baseText(try arg(1)) : nil)
        case "list": let value = try arg(0); return (value as? [Any?]) ?? [value]
        case "number": return number(try arg(0))
        case "date": return parseDate(baseText(try arg(0)))
        case "now": return Date()
        case "today": return Calendar.current.startOfDay(for: Date())
        case "max": return try args.compactMap { number(try $0(c)) }.max()
        case "min": return try args.compactMap { number(try $0(c)) }.min()
        default: return nil
        }
    }

    /// A date as Bases' date() reads one (ISO dates, with or without a time), in local time.
    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
                       "yyyy-MM-dd", "yyyy/MM/dd", "MM/dd/yyyy", "MM/dd/yyyy HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func stableSorted(_ list: [Any?], by order: (Any?, Any?) -> Int) -> [Any?] {
        list.enumerated().sorted { a, b in
            let c = order(a.element, b.element)
            return c != 0 ? c < 0 : a.offset < b.offset
        }.map(\.element)
    }

    private static func distinctKey(_ value: Any?) -> String {
        switch value {
        case nil: return "nil"
        case let s as String: return "s" + s
        case let d as Double: return "d\(d)"
        case let b as Bool: return "b\(b)"
        case let link as LinkValue: return "l" + link.target + "|" + (link.display ?? "")
        case let file as FileValue: return "f" + file.note.item.path
        default: return "o" + baseText(value)
        }
    }

    static func truthy(_ value: Any?) -> Bool {
        switch value {
        case nil: return false
        case let b as Bool: return b
        case let d as Double: return d != 0
        case let s as String: return !s.isEmpty
        case let l as [Any?]: return !l.isEmpty
        default: return true
        }
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let b as Bool: return b ? 1 : 0
        case let s as String:
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard matches(#"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#, trimmed) else { return nil }
            return Double(trimmed)
        default: return nil
        }
    }

    /// A number as .NET writes it (10, 2.5).
    static func numberText(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d == d.rounded() && abs(d) < 1e15 { return String(Int64(d)) }
        return "\(d)"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()
    private static let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm"; return formatter
    }()

    static func baseText(_ value: Any?) -> String {
        switch value {
        case nil: return ""
        case let s as String: return s
        case let d as Double: return numberText(d)
        case let b as Bool: return b ? "true" : "false"
        case let t as Date:
            let parts = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: t)
            return parts.hour == 0 && parts.minute == 0 && parts.second == 0 && (parts.nanosecond ?? 0) == 0 ? dayFormatter.string(from: t) : minuteFormatter.string(from: t)
        case let l as [Any?]: return l.map(baseText).joined(separator: ", ")
        case let link as LinkValue: return link.display ?? link.target
        case let file as FileValue: return file.note.item.path
        case let some?: return "\(some)"
        }
    }

    /// What a value points at, when it's a link, a file, or a [[link]] written as text; else nil.
    private static func linkKey(_ value: Any?, _ finder: LinkFinder) -> String? {
        switch value {
        case let link as LinkValue: return finder.key(link.target)
        case let file as FileValue: return file.note.item.path
        case let s as String:
            if let m = groups(wikiValue, s.trimmingCharacters(in: .whitespacesAndNewlines)) { return finder.key(m[1]) }
            return finder.key(s)
        default: return nil
        }
    }

    /// Bases' ==: links by the file they point at, lists item by item, numbers as numbers, else as text.
    private static func baseSame(_ a: Any?, _ b: Any?, _ finder: LinkFinder) -> Bool {
        guard let a, let b else {
            if a == nil && b == nil { return true }
            let one = a ?? b
            return (one as? String) == "" || (one as? [Any?])?.isEmpty == true
        }
        if let x = a as? [Any?], let y = b as? [Any?] { return x.count == y.count && zip(x, y).allSatisfy { baseSame($0, $1, finder) } }
        if a is LinkValue || a is FileValue || b is LinkValue || b is FileValue {
            guard let x = linkKey(a, finder), let y = linkKey(b, finder) else { return linkKey(a, finder) == nil && linkKey(b, finder) == nil }
            return same(x, y)
        }
        if let sa = a as? String, let sb = b as? String, groups(wikiValue, sa.trimmingCharacters(in: .whitespaces)) != nil, groups(wikiValue, sb.trimmingCharacters(in: .whitespaces)) != nil {
            guard let x = linkKey(sa, finder), let y = linkKey(sb, finder) else { return false }
            return same(x, y)
        }
        if a is Double || b is Double || a is Bool || b is Bool {
            guard let n = number(a), let m = number(b) else { return false }
            return n == m
        }
        return baseText(a) == baseText(b)
    }

    /// Sort order: numbers and dates as such, text as a person reads it (2 before 10), nothing last.
    private static func baseOrder(_ a: Any?, _ b: Any?) -> Int {
        guard let a, let b else { return a == nil ? (b == nil ? 0 : 1) : -1 }
        if let da = a as? Date, let db = b as? Date { return da == db ? 0 : (da < db ? -1 : 1) }
        if !(a is String) && !(b is String), let na = number(a), let nb = number(b) { return na == nb ? 0 : (na < nb ? -1 : 1) }
        return natural(baseText(a).lowercased(), baseText(b).lowercased())
    }

    // MARK: Views

    private struct BaseColumn { var id: String, title: String, width: Int? }

    /// A Base drawn as Obsidian draws it: a bar with its views (each a table or cards) and how many notes each shows, then
    /// the views, only the first shown (the page switches them). `view` picks the one shown first (an embed's #name).
    static func baseHTML(_ baseText: String, vault: URL, items: [VaultItem], address: (String) -> String, selfPath: String? = nil, view: String? = nil, embedded: Bool = false) -> String {
        let root = yaml(baseText) as? YamlMap ?? YamlMap()
        let finder = LinkFinder(items)
        let notes = baseNotes(vault: vault, items: items, finder: finder)
        let selfNote = selfPath.flatMap { path in notes.first { same($0.item.path, path) } }
        var problems: [String] = []
        func compile(_ expression: String) -> Compiled? {
            do { return try baseExpression(expression) } catch {
                problems.append("\(expression): \((error as? FormulaProblem)?.message ?? error.localizedDescription)")
                return nil
            }
        }
        var formulas: [String: Compiled] = [:]
        if let formulaMap = root["formulas"] as? YamlMap {
            for (name, expression) in formulaMap.pairs { if let compiled = compile(Study.baseText(expression)) { formulas[name.lowercased()] = compiled } }
        }
        var names: [String: String] = [:]
        if let propertyMap = root["properties"] as? YamlMap {
            for (id, settings) in propertyMap.pairs {
                if let s = settings as? YamlMap { let shown = Study.baseText(s["displayName"]); if !shown.isEmpty { names[columnID(id).lowercased()] = shown } }
            }
        }
        func name(of id: String) -> String? { names[id.lowercased()] }

        func filter(_ node: Any?) -> (BaseContext) -> Bool {
            switch node {
            case nil: return { _ in true }
            case let expression as String:
                let compiled = compile(expression)
                return { c in compiled != nil && truthy(safe { try compiled!(c) }) }
            case let group as YamlMap:
                var parts: [(BaseContext) -> Bool] = []
                for (kind, inner) in group.pairs {
                    let filters = ((inner as? [Any?]) ?? [inner]).map(filter)
                    switch kind {
                    case "or": parts.append { c in filters.contains { $0(c) } }
                    case "not": parts.append { c in !filters.contains { $0(c) } }
                    default: parts.append { c in filters.allSatisfy { $0(c) } }
                    }
                }
                return { c in parts.allSatisfy { $0(c) } }
            case let list as [Any?]:
                let all = list.map(filter)
                return { c in all.allSatisfy { $0(c) } }
            default: return { _ in true }
            }
        }
        let global = filter(root["filters"])
        var views = ((root["views"] as? [Any?]) ?? []).compactMap { $0 as? YamlMap }
        if views.isEmpty { var table = YamlMap(); table.set("type", "table"); table.set("name", "Table"); views.append(table) }

        var drawn: [(name: String, type: String, count: Int, html: String)] = []
        // A column's chips each in a colour of their own: in name order, a value whose colour is taken takes the next free
        // one. Worked out over the whole base, so a value keeps its colour in every view.
        var everyone: [BaseContext]?
        var chipHues: [String: [String: Int]] = [:]
        func chipHue(_ id: String, _ value: String) -> Int {
            let key = id.lowercased()
            if chipHues[key] == nil {
                if everyone == nil { everyone = notes.map { BaseContext($0, finder, formulas, selfNote) }.filter { global($0) } }
                let values = everyone!.compactMap { context in safe { columnValue(context, id) } as? String }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                chipHues[key] = spreadHues(values)
            }
            return chipHues[key]?.first { same($0.key, value) }?.value ?? hue(value)
        }
        for settings in views {
            let type = Study.baseText(settings["type"]) == "cards" ? "cards" : "table"
            let given = Study.baseText(settings["name"])
            let viewName = given.isEmpty ? (type == "cards" ? "Cards" : "Table") : given
            let viewFilter = filter(settings["filters"])
            var rows: [BaseContext] = []
            for note in notes {
                let context = BaseContext(note, finder, formulas, selfNote)
                if global(context) && viewFilter(context) { rows.append(context) }
            }
            let widths = settings["columnSize"] as? YamlMap ?? YamlMap()
            var seenColumns: Set<String> = []
            var columns: [BaseColumn] = ((settings["order"] as? [Any?]) ?? []).map { columnID(Study.baseText($0)) }.filter { !$0.isEmpty && seenColumns.insert($0).inserted }.map { id in
                let width = widths.pairs.first { columnID($0.key) == id }.flatMap { number($0.value) }.map { Int($0) }
                return BaseColumn(id: id, title: name(of: id) ?? columnTitle(id), width: width)
            }
            if columns.isEmpty { columns.append(BaseColumn(id: "file.name", title: "file name", width: nil)) }
            var cells: [ObjectIdentifier: [String: Any?]] = [:]
            func cell(_ c: BaseContext, _ id: String) -> Any? {
                if let row = cells[ObjectIdentifier(c)], let value = row[id] { return value }
                let value = safe { columnValue(c, id) }
                cells[ObjectIdentifier(c), default: [:]][id] = .some(value)
                return value
            }
            let sorts: [(id: String, down: Bool)] = ((settings["sort"] as? [Any?]) ?? []).compactMap { $0 as? YamlMap }
                .map { (columnID(Study.baseText($0["property"])), Study.baseText($0["direction"]).uppercased() == "DESC") }
                .filter { !$0.id.isEmpty }
            var ordered: [BaseContext]
            if sorts.isEmpty {
                ordered = rows.enumerated().sorted { a, b in
                    let x = a.element.note.item.path.lowercased(), y = b.element.note.item.path.lowercased()
                    return x != y ? Array(x.utf16).lexicographicallyPrecedes(Array(y.utf16)) : a.offset < b.offset
                }.map(\.element)
            } else {
                ordered = rows.enumerated().sorted { a, b in
                    for (id, down) in sorts {
                        let x = cell(a.element, id), y = cell(b.element, id)
                        let order = x == nil || y == nil ? baseOrder(x, y) : (down ? -baseOrder(x, y) : baseOrder(x, y))
                        if order != 0 { return order < 0 }
                    }
                    return a.offset < b.offset
                }.map(\.element)
            }
            if let limit = number(settings["limit"]), limit > 0 { ordered = Array(ordered.prefix(Int(limit))) }
            let count = ordered.count
            var groups: [(title: String?, rows: [BaseContext])] = []
            var groupID: String?
            if let groupBy = settings["groupBy"] as? YamlMap, case let byID = columnID(Study.baseText(groupBy["property"])), !byID.isEmpty {
                groupID = byID
                let down = Study.baseText(groupBy["direction"]).uppercased() == "DESC"
                var keyed: [(key: String, rows: [BaseContext])] = []
                for row in ordered {
                    let key = Study.baseText(cell(row, byID))
                    if let index = keyed.firstIndex(where: { $0.key == key }) { keyed[index].rows.append(row) } else { keyed.append((key, [row])) }
                }
                keyed.sort { a, b in
                    if a.key.isEmpty || b.key.isEmpty { return !a.key.isEmpty && b.key.isEmpty }
                    let order = (down ? -1 : 1) * natural(a.key.lowercased(), b.key.lowercased())
                    return order < 0
                }
                groups = keyed.map { ($0.key, $0.rows) }
            } else { groups = [(nil, ordered)] }

            var html = ""
            let groupTitle = groupID.map { name(of: $0) ?? columnTitle($0) } ?? ""
            // Each group in the colour its name gets everywhere (Study.hue, as its folder in Sage's tree).
            func heading(_ group: (title: String?, rows: [BaseContext])) -> String {
                var value = "<div class=\"bases-group-value\"><span class=\"sage-base-none\">None</span></div>"
                if let t = group.title, !t.isEmpty {
                    let tone = hue(baseShown(t))
                    value = "<span class=\"sage-hue-dot sage-hue-\(tone)\"></span><div class=\"bases-group-value sage-hued sage-hue-\(tone)\">\(valueHTML(t, finder, address, items))</div>"
                }
                return "<div class=\"bases-group-heading mod-collapsible\"><div class=\"collapse-icon\" data-sage-icon=\"lucide-chevron-right\"></div>"
                    + "<div class=\"bases-group-property\">\(escape(groupTitle))</div>" + value + "<div class=\"bases-group-count\">\(group.rows.count)</div></div>"
            }
            // A column of a few short words repeated (a type, a status, a topic) shows each as a chip in its colour.
            let chips = Set(columns.filter { column in column.id != "file.name" && column.id != "file.basename" && column.id != groupID && categorical(ordered.map { row in cell(row, column.id) }) }.map(\.id))
            func value(_ row: BaseContext, _ id: String, _ value: Any?) -> String {
                if chips.contains(id), let s = value as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    return "<span class=\"sage-chip sage-hue-\(chipHue(id, trimmed))\">\(escape(trimmed))</span>"
                }
                return cellHTML(row, id, value, finder, address, items)
            }
            if type == "table" {
                html += "<table class=\"sage-base-table\"><colgroup>"
                for column in columns { html += column.width.map { "<col style=\"width: \($0)px\">" } ?? "<col>" }
                html += "</colgroup><thead><tr>"
                for column in columns {
                    html += "<th class=\"sage-base-th\(column.id.hasPrefix("formula.") ? " mod-formula" : column.id.hasPrefix("file.") ? " mod-implicit" : "")\">"
                        + "<span class=\"bases-table-header-icon\" data-sage-icon=\"\(columnIcon(column.id))\"></span>\(escape(column.title))</th>"
                }
                html += "</tr></thead>"
                for group in groups {
                    html += "<tbody>"
                    if group.title != nil { html += "<tr class=\"sage-base-group-row\"><td colspan=\"\(columns.count)\">\(heading(group))</td></tr>" }
                    for row in group.rows {
                        html += "<tr class=\"sage-base-row\">"
                        for column in columns { html += "<td><div class=\"sage-base-cell bases-rendered-value\">\(value(row, column.id, cell(row, column.id)))</div></td>" }
                        html += "</tr>"
                    }
                    html += "</tbody>"
                }
                html += "</table>"
            } else {
                let image = Study.baseText(settings["image"])
                let imageID = image.isEmpty ? nil : columnID(image)
                let cover = number(settings["coverHeight"]).map { Int($0) } ?? 140
                let shown = columns.filter { $0.id != "file.name" && $0.id != imageID }
                html += "<div class=\"sage-base-cards\" style=\"--sage-cover: \(cover)px\">"
                for group in groups {
                    if group.title != nil { html += heading(group) }
                    html += "<div class=\"sage-base-cards-group\">"
                    for row in group.rows {
                        let picture = imageID.flatMap { coverAddress(cell(row, $0), finder, address) }
                        html += "<div class=\"sage-base-card\" data-sage-href=\"sage-note:\(attribute(row.note.item.path))\">"
                        if imageID != nil {
                            html += picture.map { "<div class=\"sage-card-cover\" style=\"background-image: url('\(attribute($0))')\"></div>" } ?? "<div class=\"sage-card-cover\"></div>"
                        }
                        html += "<div class=\"sage-card-prop is-title\"><div class=\"sage-card-line\">\(escape(baseMember(FileValue(note: row.note), "basename", row) as? String ?? ""))</div></div>"
                        for column in shown {
                            let v = cell(row, column.id)
                            html += "<div class=\"sage-card-prop\"><div class=\"sage-card-label\">\(escape(column.title))</div>"
                                + "<div class=\"sage-card-line\">\(v == nil || Study.baseText(v).isEmpty ? "<span class=\"sage-base-none\">—</span>" : value(row, column.id, v))</div></div>"
                        }
                        html += "</div>"
                    }
                    html += "</div>"
                }
                html += "</div>"
            }
            drawn.append((viewName, type, count, html))
        }

        let first = max(0, view.flatMap { view in drawn.firstIndex { same($0.name, view) } } ?? 0)
        var page = "<div class=\"sage-base\(embedded ? " bases-embed" : "")\" data-sage-base><div class=\"bases-header\"><div class=\"bases-toolbar\">"
        page += "<div class=\"sage-base-tabs\">"
        for (i, d) in drawn.enumerated() {
            page += "<div role=\"button\" tabindex=\"0\" class=\"sage-base-tab\(i == first ? " is-active" : "")\" data-sage-view-tab=\"\(i)\" data-sage-count=\"\(d.count)\">"
                + "<span data-sage-icon=\"\(d.type == "cards" ? "lucide-layout-grid" : "lucide-table")\"></span>\(escape(d.name))</div>"
        }
        page += "</div><div class=\"bases-toolbar-result-count\">\(drawn[first].count) \(drawn[first].count == 1 ? "result" : "results")</div></div></div>"
        if !problems.isEmpty {
            var distinct: [String] = []
            for problem in problems where !distinct.contains(problem) { distinct.append(problem) }
            page += "<div class=\"bases-formula-error sage-base-problem\">Sage couldn't read part of this base: \(escape(distinct.prefix(3).joined(separator: "; ")))</div>"
        }
        for (i, d) in drawn.enumerated() {
            page += "<div class=\"bases-view sage-base-view\" data-view-type=\"\(d.type)\" data-sage-view=\"\(i)\"\(i == first ? "" : " hidden")>\(d.html)</div>"
        }
        return page + "</div>"
    }

    private static func safe(_ run: () throws -> Any?) -> Any? { (try? run()) ?? nil }

    /// A colour for each of a few values, its own (Study.hue) unless a value before it in name order has it, then the next
    /// free one (while any is free).
    static func spreadHues(_ values: [String]) -> [String: Int] {
        var hues: [String: Int] = [:], used: Set<Int> = [], seen: Set<String> = [], distinct: [String] = []
        for value in values where seen.insert(value.lowercased()).inserted { distinct.append(value) }
        for value in distinct.sorted(by: { $0.lowercased() == $1.lowercased() ? false : Array($0.lowercased().utf16).lexicographicallyPrecedes(Array($1.lowercased().utf16)) }) {
            var tone = hue(value)
            var tries = 0
            while tries < 8 && used.count < 8 && used.contains(tone) { tone = (tone + 1) % 8; tries += 1 }
            used.insert(tone)
            hues[value] = tone
        }
        return hues
    }

    /// A link's name as shown ("[[Notes/Pho|the pho]]" → "the pho", "[[Notes/Pho]]" → "Pho"); other text as it is.
    private static func baseShown(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = groups(wikiValue, text) else { return text }
        var inner = m[1]
        if let bar = inner.firstIndex(of: "|") { return String(inner[inner.index(after: bar)...]) }
        inner = String(inner.split(separator: "#", omittingEmptySubsequences: false).first ?? "")
        return inner.lastIndex(of: "/").map { String(inner[inner.index(after: $0)...]) } ?? inner
    }

    /// Values that read as a few kinds of thing (short words, not links, dates or numbers, at most a dozen of them, some
    /// repeated), drawn as chips.
    static func categorical(_ values: [Any?]) -> Bool {
        var words: [String] = []
        for value in values {
            if value == nil || (value as? String) == "" { continue }
            guard let s = value as? String, groups(plainValue, s.trimmingCharacters(in: .whitespacesAndNewlines)) != nil else { return false }
            words.append(s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        if words.count < 3 { return false }
        let kinds = Set(words).count
        return kinds <= 12 && kinds < words.count
    }

    /// "Author" and "note.Author" are the same column; file. and formula. columns keep their names.
    private static func columnID(_ raw: String) -> String {
        var id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.hasPrefix("note.") { id = String(id.dropFirst(5)) }
        return id.hasPrefix("file.") || id.hasPrefix("formula.") || id.isEmpty ? id : "note." + id
    }

    private static func columnTitle(_ id: String) -> String {
        if id == "file.name" || id == "file.basename" { return "file name" }
        if id.hasPrefix("file.") { return "file " + id.dropFirst(5) }
        if id.hasPrefix("formula.") { return String(id.dropFirst(8)) }
        return id.hasPrefix("note.") ? String(id.dropFirst(5)) : id
    }

    private static func columnIcon(_ id: String) -> String {
        switch id {
        case "file.name", "file.basename", "file.path": return "lucide-file"
        case "file.folder": return "lucide-folder"
        case "file.ctime", "file.mtime": return "lucide-clock"
        case "file.tags": return "lucide-tags"
        default:
            if id.hasPrefix("file.") { return "lucide-file" }
            if id.hasPrefix("formula.") { return "lucide-square-function" }
            return "lucide-text"
        }
    }

    private static func columnValue(_ c: BaseContext, _ id: String) -> Any? {
        if id.hasPrefix("formula.") { return c.formula(String(id.dropFirst(8))) }
        if id.hasPrefix("file.") { return baseMember(FileValue(note: c.note), String(id.dropFirst(5)), c) }
        return c.note.prop(id.hasPrefix("note.") ? String(id.dropFirst(5)) : id)
    }

    private static func cellHTML(_ row: BaseContext, _ id: String, _ value: Any?, _ finder: LinkFinder, _ address: (String) -> String, _ items: [VaultItem]) -> String {
        if id == "file.name" || id == "file.basename" {
            let item = row.note.item
            return "<a data-href=\"\(attribute(item.path))\" href=\"sage-note:\(attribute(item.path))\" class=\"internal-link\">\(escape(item.title))</a>"
        }
        return valueHTML(value, finder, address, items)
    }

    private static func valueHTML(_ value: Any?, _ finder: LinkFinder, _ address: (String) -> String, _ items: [VaultItem]) -> String {
        switch value {
        case nil: return ""
        case let list as [Any?]: return list.map { valueHTML($0, finder, address, items) }.joined(separator: "<span class=\"sage-base-comma\">, </span>")
        case let link as LinkValue: return linkHTML(finder.key(link.target), link.display ?? link.target)
        case let file as FileValue: return linkHTML(file.note.item.path, file.note.item.title)
        case let b as Bool: return "<input type=\"checkbox\" class=\"metadata-input-checkbox\" disabled\(b ? " checked" : "")>"
        case let t as Date: return escape(baseText(t))
        case let s as String:
            if let m = groups(wikiValue, s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                let inner = m[1]
                let shown = inner.firstIndex(of: "|").map { String(inner[inner.index(after: $0)...]) } ?? String(inner.split(separator: "#", omittingEmptySubsequences: false).first ?? "")
                return linkHTML(finder.key(inner), shown)
            }
            if s.hasPrefix("http://") || s.hasPrefix("https://") { return "<a class=\"external-link\" rel=\"noopener nofollow\" href=\"\(attribute(s))\">\(escape(s))</a>" }
            return inline(s)
        default: return inline(baseText(value))
        }
    }

    private static func linkHTML(_ key: String, _ shown: String) -> String {
        let missing = key.hasPrefix("?")
        let target = missing ? shown : key
        var name = shown.lastIndex(of: "/").map { String(shown[shown.index(after: $0)...]) } ?? shown
        if name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
        return "<a data-href=\"\(attribute(target))\" href=\"sage-note:\(attribute(target))\" class=\"internal-link\(missing ? " is-unresolved" : "")\">\(escape(name))</a>"
    }

    /// A card's cover: a picture in the vault ([[x.jpg]] or its path) or on the web.
    private static func coverAddress(_ raw: Any?, _ finder: LinkFinder, _ address: (String) -> String) -> String? {
        var value = raw
        if let list = value as? [Any?] { value = list.first ?? nil }
        let text = baseText(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return text }
        guard let key = linkKey(value is String ? text : value, finder), !key.hasPrefix("?"), isPicture(key) else { return nil }
        return address(key)
    }

    // MARK: JSON that keeps its keys in order (a canvas is written back as Obsidian wrote it)

    /// A JSON value with its object keys in order and its numbers as written.
    indirect enum OrderedJSON: Equatable {
        case object([(String, OrderedJSON)]), array([OrderedJSON]), string(String), number(String), bool(Bool), null

        static func == (a: OrderedJSON, b: OrderedJSON) -> Bool {
            switch (a, b) {
            case let (.object(x), .object(y)): return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
            case let (.array(x), .array(y)): return x == y
            case let (.string(x), .string(y)), let (.number(x), .number(y)): return x == y
            case let (.bool(x), .bool(y)): return x == y
            case (.null, .null): return true
            default: return false
            }
        }

        subscript(key: String) -> OrderedJSON? {
            if case let .object(pairs) = self { return pairs.first { $0.0 == key }?.1 }
            return nil
        }
        var string: String? { if case let .string(s) = self { return s }; return nil }
        var double: Double? { if case let .number(n) = self { return Double(n) }; return nil }
        var array: [OrderedJSON]? { if case let .array(a) = self { return a }; return nil }
        var keys: [String] { if case let .object(pairs) = self { return pairs.map(\.0) }; return [] }

        /// Parsed from JSON text; nil when it isn't JSON.
        static func parse(_ text: String) -> OrderedJSON? {
            var reader = JSONReader(scalars: Array(text.unicodeScalars))
            guard let value = reader.value() else { return nil }
            reader.space()
            return reader.at == reader.scalars.count ? value : nil
        }

        /// From what JSONSerialization or a web view's message gives (dictionaries lose their order: keys follow `like`'s,
        /// then the order Obsidian writes them in, then by name).
        static func from(_ value: Any?, like: OrderedJSON? = nil) -> OrderedJSON {
            switch value {
            case nil, is NSNull: return .null
            case let json as OrderedJSON: return json
            case let s as String: return .string(s)
            case let n as NSNumber:
                if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
                return .number(Study.jsonNumber(n.doubleValue))
            case let b as Bool: return .bool(b)
            case let d as Double: return .number(Study.jsonNumber(d))
            case let i as Int: return .number(String(i))
            case let list as [Any?]:
                return .array(list.map { from($0) })
            case let list as [Any]:
                return .array(list.map { from($0) })
            case let object as [String: Any]:
                let known = like?.keys ?? []
                let canonical = ["id", "type", "text", "file", "subpath", "url", "label", "fromNode", "fromSide", "fromEnd", "toNode", "toSide", "toEnd", "x", "y", "width", "height", "color",
                                 "background", "backgroundStyle"]
                let keys = object.keys.sorted { a, b in
                    let ka = known.firstIndex(of: a), kb = known.firstIndex(of: b)
                    if ka != nil || kb != nil { return ka != nil && kb != nil ? ka! < kb! : ka != nil }
                    let ca = canonical.firstIndex(of: a), cb = canonical.firstIndex(of: b)
                    if ca != nil || cb != nil { return ca != nil && cb != nil ? ca! < cb! : ca != nil }
                    return a < b
                }
                return .object(keys.map { ($0, from(object[$0], like: like?[$0])) })
            default: return .string("\(value!)")
            }
        }

        /// Written compactly as JSON.stringify writes it; `html` also escapes what could end a <script> (<, >, &, ').
        func written(html: Bool = false) -> String {
            switch self {
            case let .object(pairs): return "{" + pairs.map { Study.jsonString($0.0, html: html) + ":" + $0.1.written(html: html) }.joined(separator: ",") + "}"
            case let .array(items): return "[" + items.map { $0.written(html: html) }.joined(separator: ",") + "]"
            case let .string(s): return Study.jsonString(s, html: html)
            case let .number(n): return n
            case let .bool(b): return b ? "true" : "false"
            case .null: return "null"
            }
        }

        /// Written indented by two spaces ("key": value), as a JSON file is shown.
        func indented(_ depth: Int = 0) -> String {
            let pad = String(repeating: "  ", count: depth + 1), end = String(repeating: "  ", count: depth)
            switch self {
            case let .object(pairs):
                return pairs.isEmpty ? "{}" : "{\n" + pairs.map { pad + Study.jsonString($0.0, html: false) + ": " + $0.1.indented(depth + 1) }.joined(separator: ",\n") + "\n" + end + "}"
            case let .array(items):
                return items.isEmpty ? "[]" : "[\n" + items.map { pad + $0.indented(depth + 1) }.joined(separator: ",\n") + "\n" + end + "]"
            default: return written()
            }
        }
    }

    private struct JSONReader {
        let scalars: [Unicode.Scalar]
        var at = 0
        mutating func space() { while at < scalars.count, [" ", "\n", "\r", "\t"].contains(scalars[at]) { at += 1 } }
        mutating func value() -> OrderedJSON? {
            space()
            guard at < scalars.count else { return nil }
            switch scalars[at] {
            case "{":
                at += 1
                var pairs: [(String, OrderedJSON)] = []
                space()
                if at < scalars.count, scalars[at] == "}" { at += 1; return .object(pairs) }
                while true {
                    space()
                    guard let key = string() else { return nil }
                    space()
                    guard at < scalars.count, scalars[at] == ":" else { return nil }
                    at += 1
                    guard let item = value() else { return nil }
                    if let index = pairs.firstIndex(where: { $0.0 == key }) { pairs[index].1 = item } else { pairs.append((key, item)) }
                    space()
                    guard at < scalars.count else { return nil }
                    if scalars[at] == "," { at += 1; continue }
                    if scalars[at] == "}" { at += 1; return .object(pairs) }
                    return nil
                }
            case "[":
                at += 1
                var items: [OrderedJSON] = []
                space()
                if at < scalars.count, scalars[at] == "]" { at += 1; return .array(items) }
                while true {
                    guard let item = value() else { return nil }
                    items.append(item)
                    space()
                    guard at < scalars.count else { return nil }
                    if scalars[at] == "," { at += 1; continue }
                    if scalars[at] == "]" { at += 1; return .array(items) }
                    return nil
                }
            case "\"": return string().map { .string($0) }
            case "t": return word("true") ? .bool(true) : nil
            case "f": return word("false") ? .bool(false) : nil
            case "n": return word("null") ? .null : nil
            default:
                let start = at
                while at < scalars.count, "+-0123456789.eE".unicodeScalars.contains(scalars[at]) { at += 1 }
                let text = String(String.UnicodeScalarView(scalars[start ..< at]))
                return Double(text) == nil ? nil : .number(text)
            }
        }
        mutating func word(_ w: String) -> Bool {
            let letters = Array(w.unicodeScalars)
            guard at + letters.count <= scalars.count, Array(scalars[at ..< at + letters.count]) == letters else { return false }
            at += letters.count
            return true
        }
        mutating func string() -> String? {
            guard at < scalars.count, scalars[at] == "\"" else { return nil }
            at += 1
            var out = String.UnicodeScalarView()
            var pendingHigh: UInt32?
            while at < scalars.count {
                let c = scalars[at]
                at += 1
                if c == "\"" { return String(out) }
                if c != "\\" { out.append(c); continue }
                guard at < scalars.count else { return nil }
                let e = scalars[at]
                at += 1
                switch e {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "b": out.append("\u{8}")
                case "f": out.append("\u{c}")
                case "u":
                    guard at + 4 <= scalars.count, let code = UInt32(String(String.UnicodeScalarView(scalars[at ..< at + 4])), radix: 16) else { return nil }
                    at += 4
                    if (0xD800 ... 0xDBFF).contains(code) { pendingHigh = code; continue }
                    if (0xDC00 ... 0xDFFF).contains(code), let high = pendingHigh {
                        pendingHigh = nil
                        if let scalar = Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (code - 0xDC00)) { out.append(scalar) }
                        continue
                    }
                    if let scalar = Unicode.Scalar(code) { out.append(scalar) }
                default: out.append(e)
                }
            }
            return nil
        }
    }

    /// A string as JSON.stringify writes it; `html` also escapes <, >, & and ' (and the line separators) for a <script>.
    static func jsonString(_ text: String, html: Bool) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{8}": out += "\\b"
            case "\u{c}": out += "\\f"
            default:
                if scalar.value < 0x20 || (html && ["<", ">", "&", "'", "\u{2028}", "\u{2029}"].contains(scalar)) {
                    out += String(format: "\\u%04X", scalar.value)
                } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    /// A number as JSON.stringify writes it (40, 2.5).
    static func jsonNumber(_ d: Double) -> String {
        if d == d.rounded() && abs(d) < 1e15 { return String(Int64(d)) }
        return "\(d)"
    }

    // MARK: Canvases, as Vault Agent's ```file-embed draws them (Helpers: .obsidian/plugins/vault-agent/src/canvas-embed.ts)

    private struct CanvasNode { var id: String, type: String, x: Double, y: Double, w: Double, h: Double, color: String?, text: String?, file: String?, url: String?, label: String? }

    private static func px(_ v: Double) -> String {
        let rounded = (v * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int64(rounded)) }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    /// A .canvas drawn read only and pannable, with the plugin's own classes (so its styles.css dresses it): groups under
    /// cards, notes as a card with their title, properties and text, pictures bare, arrows as curves, a bar with zoom,
    /// Fit and Open. The page pans and zooms it (PageScript).
    static func canvasHTML(_ json: String, canvasPath: String, height: String, vault: URL, items: [VaultItem], address: (String) -> String, depth: Int = 0, standalone: Bool = false) -> String {
        guard let data = OrderedJSON.parse(json), case .object = data else {
            return "<div class=\"va-file-embed-missing\">file-embed: “\(escape(canvasPath))” isn't valid canvas JSON</div>"
        }
        let nodes: [CanvasNode] = (data["nodes"]?.array ?? []).compactMap { n in
            guard case .object = n else { return nil }
            return CanvasNode(id: n["id"]?.string ?? "", type: n["type"]?.string ?? "text", x: n["x"]?.double ?? 0, y: n["y"]?.double ?? 0, w: n["width"]?.double ?? 0,
                              h: n["height"]?.double ?? 0, color: n["color"]?.string, text: n["text"]?.string, file: n["file"]?.string, url: n["url"]?.string, label: n["label"]?.string)
        }
        if nodes.isEmpty { return "<div class=\"va-file-embed-missing\">file-embed: empty canvas</div>" }
        let pad = 80.0
        let minX = nodes.map(\.x).min()! - pad
        let minY = nodes.map(\.y).min()! - pad
        let worldW = nodes.map { $0.x + $0.w }.max()! - minX + pad
        let worldH = nodes.map { $0.y + $0.h }.max()! - minY + pad
        func rgb(_ hex: String) -> String { let n = Int(hex, radix: 16) ?? 0; return "\((n >> 16) & 255), \((n >> 8) & 255), \(n & 255)" }
        func preset(_ color: String?) -> Bool { color.map { $0.count == 1 && ("1" ... "6").contains($0) } ?? false }
        // A preset colour (1–6) is resolved by the page from your theme, as the plugin does; a hex one here.
        func colorAttributes(_ color: String?, _ what: String) -> String {
            if preset(color) { return " data-sage-preset=\"\(color!)\" data-sage-color-on=\"\(what)\"" }
            if let color, let hex = firstMatch("^#?([0-9a-fA-F]{6})$", in: color) {
                return what == "node" ? " style=\"--va-node-rgb: \(rgb(hex[1]))\"" : " style=\"stroke: rgb(\(rgb(hex[1])))\""
            }
            return ""
        }
        func colored(_ color: String?) -> Bool { preset(color) || (color.map { matches("^#?[0-9a-fA-F]{6}$", $0) } ?? false) }

        let finder = LinkFinder(items)
        var notes: [(String, OrderedJSON)] = []
        var world = "", labels = ""
        for n in nodes.filter({ $0.type == "group" }) + nodes.filter({ $0.type != "group" }) {
            let place = "left: \(px(n.x - minX))px; top: \(px(n.y - minY))px; width: \(px(n.w))px; height: \(px(n.h))px;"
            let isColored = colored(n.color) ? " is-colored" : ""
            let color = colorAttributes(n.color, "node")
            let style = color.contains("style=") ? color.replacingOccurrences(of: " style=\"", with: " style=\"\(place) ") : " style=\"\(place)\"\(color)"
            if n.type == "group" {
                world += "<div class=\"va-canvas-node va-canvas-group\(isColored)\" data-id=\"\(attribute(n.id))\"\(style)></div>"
                if let label = n.label, !label.isEmpty {
                    labels += "<div class=\"va-canvas-label va-canvas-group-label\(isColored)\" data-for=\"\(attribute(n.id))\" style=\"left: \(px(n.x - minX))px; top: \(px(n.y - minY))px;\"\(color.contains("style=") ? "" : color)>\(escape(label))</div>"
                }
                continue
            }
            let key = n.type == "file" ? n.file.map { finder.key($0) } : nil
            if let key, !key.hasPrefix("?"), isPicture(key) {
                let alt = ((key as NSString).lastPathComponent as NSString).deletingPathExtension
                world += "<div class=\"va-canvas-node va-canvas-file is-image\(isColored)\" data-id=\"\(attribute(n.id))\"\(style)><img src=\"\(attribute(address(key)))\" alt=\"\(attribute(alt))\" draggable=\"false\"></div>"
                continue
            }
            var content = ""
            if n.type == "text" { content += markdown(n.text ?? "") }
            else if n.type == "file", let file = n.file {
                var name = (file.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
                if name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
                labels += "<a class=\"va-canvas-label va-canvas-file-label\" data-for=\"\(attribute(n.id))\" href=\"sage-note:\(attribute(file))\" style=\"left: \(px(n.x - minX))px; top: \(px(n.y - minY))px;\">\(escape(name))</a>"
                if let key, key.lowercased().hasSuffix(".md"), depth < 2, let read = baseRead(vault.appendingPathComponent(key)) {
                    content += canvasNoteHTML(name: name, note: read)
                    notes.append((n.id, .object([("file", .string(key)), ("body", .string(split(read.replacingOccurrences(of: "\r\n", with: "\n")).body))])))
                } else { content += markdown("![[\(file)]]") }
            } else if n.type == "link", let url = n.url {
                content += "<a class=\"external-link\" rel=\"noopener nofollow\" href=\"\(attribute(url))\">\(escape(url))</a>"
            }
            world += "<div class=\"va-canvas-node va-canvas-\(attribute(n.type))\(isColored)\" data-id=\"\(attribute(n.id))\"\(style)><div class=\"va-canvas-node-content markdown-rendered\">\(content)</div></div>"
        }

        var byID: [String: CanvasNode] = [:]
        for n in nodes where byID[n.id] == nil { byID[n.id] = n }
        var edges = "", edgeLabels = ""
        for e in data["edges"]?.array ?? [] {
            guard case .object = e, let a = byID[e["fromNode"]?.string ?? ""], let b = byID[e["toNode"]?.string ?? ""] else { continue }
            let dx = b.x + b.w / 2 - (a.x + a.w / 2)
            let dy = b.y + b.h / 2 - (a.y + a.h / 2)
            let guess = abs(dx) > abs(dy) ? (dx > 0 ? ("right", "left") : ("left", "right")) : (dy > 0 ? ("bottom", "top") : ("top", "bottom"))
            func anchor(_ n: CanvasNode, _ side: String) -> (x: Double, y: Double, dx: Double, dy: Double) {
                switch side {
                case "top": return (n.x + n.w / 2, n.y, 0, -1)
                case "bottom": return (n.x + n.w / 2, n.y + n.h, 0, 1)
                case "left": return (n.x, n.y + n.h / 2, -1, 0)
                default: return (n.x + n.w, n.y + n.h / 2, 1, 0)
                }
            }
            let p = anchor(a, e["fromSide"]?.string ?? guess.0)
            let q = anchor(b, e["toSide"]?.string ?? guess.1)
            let off = min(220, max(40, ((q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)).squareRoot() * 0.4))
            let c1 = (x: p.x + p.dx * off, y: p.y + p.dy * off)
            let c2 = (x: q.x + q.dx * off, y: q.y + q.dy * off)
            let color = e["color"]?.string
            let arrowEnd = (e["toEnd"]?.string ?? "arrow") == "arrow"
            let arrowStart = e["fromEnd"]?.string == "arrow"
            edges += "<path class=\"va-canvas-edge\" d=\"M \(px(p.x - minX)) \(px(p.y - minY)) C \(px(c1.x - minX)) \(px(c1.y - minY)), \(px(c2.x - minX)) \(px(c2.y - minY)), \(px(q.x - minX)) \(px(q.y - minY))\""
                + "\(colorAttributes(color, "edge"))\(arrowEnd ? " data-sage-arrow-end" : "")\(arrowStart ? " data-sage-arrow-start" : "")/>"
            if let label = e["label"]?.string, !label.isEmpty {
                edgeLabels += "<div class=\"va-canvas-edge-label\" style=\"left: \(px((p.x + 3 * c1.x + 3 * c2.x + q.x) / 8 - minX))px; top: \(px((p.y + 3 * c1.y + 3 * c2.y + q.y) / 8 - minY))px;\">\(escape(label))</div>"
            }
        }
        // A canvas opened on its own can be edited, as in Obsidian: the page gets its nodes and arrows as the file has
        // them (and each note card's text), and which version of the file it was drawn from.
        let editable = !standalone ? "" : " data-sage-editable"
        var model = ""
        if standalone {
            let state = OrderedJSON.object([
                ("path", .string(canvasPath)), ("hash", .string(canvasHash(json))), ("minX", .number(jsonNumber(minX))), ("minY", .number(jsonNumber(minY))),
                ("nodes", .array(data["nodes"]?.array ?? [])), ("edges", .array(data["edges"]?.array ?? [])),
                ("notes", .object(notes)),
            ])
            model = "<script type=\"application/json\" class=\"sage-canvas-data\">" + state.written(html: true) + "</script>"
        }
        return "<div class=\"va-canvas-embed\" data-sage-canvas\(editable) style=\"height: \(attribute(height));\">\(model)<div class=\"va-canvas-world\" style=\"width: \(px(worldW))px; height: \(px(worldH))px;\">"
            + "<svg class=\"va-canvas-edges\" width=\"\(px(worldW))\" height=\"\(px(worldH))\">\(edges)</svg>\(world)\(edgeLabels)\(labels)</div>"
            + "<div class=\"va-canvas-toolbar\"><button data-sage-zoom=\"1.25\" aria-label=\"Zoom in\">+</button><button data-sage-zoom=\"0.8\" aria-label=\"Zoom out\">−</button>"
            + "<button data-sage-fit aria-label=\"Fit to view\">Fit</button>"
            // Open is for a canvas shown inside a note; one opened on its own is already open.
            + (standalone ? "" : "<button data-sage-href=\"sage-note:\(attribute(canvasPath))\" aria-label=\"Open full canvas\">Open</button>") + "</div></div>"
    }

    /// A note's card on a canvas, as the plugin draws it: its title, its properties, its text.
    static func canvasNoteHTML(name: String, note: String) -> String {
        var html = "<div class=\"va-canvas-inline-title\">\(escape(name))</div>"
        let (header, body) = split(note.replacingOccurrences(of: "\r\n", with: "\n"))
        if !header.isEmpty, let props = yaml(header) as? YamlMap {
            html += "<div class=\"va-canvas-props\">"
            for (k, v) in props.pairs where k != "position" {
                html += "<div class=\"va-canvas-prop\"><div class=\"va-canvas-prop-key\">\(escape(k))</div><div class=\"va-canvas-prop-value\">"
                    + "\(inline((v as? [Any?]).map { $0.map(baseText).joined(separator: " · ") } ?? baseText(v)))</div></div>"
            }
            html += "</div>"
        }
        return html + "<div class=\"sage-canvas-note-body\">" + markdown(body) + "</div>"
    }

    // MARK: Editing a canvas (2026-11-08): you change it in Sage as in Obsidian; the file is written as Obsidian writes it.

    /// Which version of a canvas file the page was drawn from (so a save can't go over a change made in Obsidian).
    static func canvasHash(_ json: String) -> String {
        let digest = SHA256.hash(data: Data(json.replacingOccurrences(of: "\r\n", with: "\n").utf8))
        return String(digest.map { String(format: "%02X", $0) }.joined().prefix(16))
    }

    /// A canvas as Obsidian writes it: tab-indented, each node and arrow on its own line, other keys kept in their place.
    static func canvasJSON(_ root: OrderedJSON, nodes: [OrderedJSON], edges: [OrderedJSON]) -> String {
        var keys = root.keys
        if !keys.contains("nodes") { keys.insert("nodes", at: 0) }
        if !keys.contains("edges") { keys.insert("edges", at: (keys.firstIndex(of: "nodes") ?? 0) + 1) }
        func value(_ key: String) -> String {
            let list: [OrderedJSON]? = key == "nodes" ? nodes : key == "edges" ? edges : root[key]?.array
            if let list { return list.isEmpty ? "[]" : "[\n" + list.map { "\t\t" + $0.written() }.joined(separator: ",\n") + "\n\t]" }
            return root[key]?.written() ?? "null"
        }
        return "{\n" + keys.map { "\t\(jsonString($0, html: false)):\(value($0))" }.joined(separator: ",\n") + "\n}"
    }

    /// The canvas's nodes and arrows written as you changed them, only if the file is still the version the page had (else
    /// nil: it changed in Obsidian meanwhile). The canvas as it was is kept first, as a note is. The new version's hash.
    /// `nodes` and `edges` come from the page (dictionaries, whose keys follow the order the file had them in).
    static func saveCanvas(_ file: URL, nodes: [Any], edges: [Any], expected: String, keep: URL?) throws -> String? {
        let was = try readNote(file)
        if canvasHash(was.text) != expected { return nil }
        let root = OrderedJSON.parse(was.text) ?? .object([])
        func like(_ list: [OrderedJSON]?) -> [String: OrderedJSON] {
            var byID: [String: OrderedJSON] = [:]
            for item in list ?? [] { if let id = item["id"]?.string, byID[id] == nil { byID[id] = item } }
            return byID
        }
        func ordered(_ list: [Any], _ was: [OrderedJSON]?) -> [OrderedJSON] {
            let old = like(was)
            return list.map { item in
                let id = (item as? [String: Any])?["id"] as? String ?? (item as? OrderedJSON)?["id"]?.string
                return OrderedJSON.from(item, like: id.flatMap { old[$0] } ?? was?.first)
            }
        }
        let json = canvasJSON(root, nodes: ordered(nodes, root["nodes"]?.array), edges: ordered(edges, root["edges"]?.array))
        if json != was.text { try writeNote(file, text: json, was: was, keep: keep) }
        return canvasHash(json)
    }

    /// A note's text (all below its properties) written as you changed it on its canvas card; nil when it changed meanwhile.
    static func saveNoteBody(_ file: URL, original: String, text: String, keep: URL?) throws -> String? {
        let was = try readNote(file)
        let start = bodyStart(was.text)
        let lines = was.text.components(separatedBy: "\n")
        let edited = start >= lines.count
            ? editLines(was.text, from: lines.count, to: lines.count - 1, original: "", text: text)
            : editLines(was.text, from: start, to: lines.count - 1, original: original.replacingOccurrences(of: "\r\n", with: "\n"), text: text.replacingOccurrences(of: "\r\n", with: "\n"))
        guard let done = edited else { return nil }
        if done.text != was.text { try writeNote(file, text: done.text, was: was, keep: keep) }
        return done.text
    }

    /// A file's text (a BOM dropped), or nil when it can't be read.
    static func baseRead(_ file: URL) -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return String(decoding: data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...], as: UTF8.self)
    }

    // MARK: Vault Agent's ```file-embed, and Obsidian's ![[embeds]] of notes, bases, canvases and PDFs

    private static let codeLanguages: [String: String] = [
        "json": "json", "js": "javascript", "mjs": "javascript", "ts": "typescript", "jsx": "jsx", "tsx": "tsx", "py": "python",
        "rb": "ruby", "go": "go", "rs": "rust", "java": "java", "kt": "kotlin", "swift": "swift", "c": "c", "h": "c", "cpp": "cpp",
        "cs": "csharp", "php": "php", "sh": "bash", "zsh": "bash", "ps1": "powershell", "bat": "batch", "sql": "sql", "css": "css",
        "scss": "scss", "xml": "xml", "svg": "xml", "yaml": "yaml", "yml": "yaml", "toml": "toml", "ini": "ini", "lua": "lua", "r": "r",
    ]

    private static func plainAttribute(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
    }

    /// The page with what it embeds drawn in: Vault Agent's file-embed blocks (a canvas, a web page, a CSV or TSV as a
    /// table, code, text, else as an ![[embed]]), and ![[embeds]] of a note (its text), a base (its views), a canvas or a
    /// PDF; then its pictures (withPictures). `from` is the note's path in the vault.
    /// Video and sound files a note can play in place.
    static let videoTypes: Set<String> = [".mp4", ".mov", ".m4v", ".webm", ".ogv"]
    static let soundTypes: Set<String> = [".mp3", ".wav", ".m4a", ".ogg", ".flac", ".aac"]

    /// A Range header's bytes ("bytes=0-1023", "bytes=500-"): where it starts, and where it ends when it says.
    static func byteRange(_ header: String) -> (lowerBound: Int, upperBound: Int?)? {
        guard header.hasPrefix("bytes="), !header.contains(",") else { return nil }
        let parts = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let from = Int(parts[0]) else { return nil }
        return (from, parts[1].isEmpty ? nil : Int(parts[1]))
    }

    static func withVault(_ html: String, vault: URL, items: [VaultItem], from: String?, address: (String) -> String, depth: Int = 0) -> String {
        var page = replace(fileEmbedSlot, in: html) { m in
            let target = plainAttribute(m[1])
            let height = Int(m[2])
            guard let found = resolve(target, in: items, from: from) ?? onDisk(vault, target, from), !found.folder else {
                return "<div class=\"block-language-file-embed\"><div class=\"va-file-embed-missing\">file-embed: can't find “\(escape(target))”</div></div>"
            }
            return "<div class=\"block-language-file-embed\">" + fileEmbed(found, height, vault, items, address, depth) + "</div>"
        }
        page = replace(otherEmbed, in: page) { m in
            let link = plainAttribute(m[2])
            guard let found = resolve(link, in: items, from: from), !found.folder, !isPicture(found.path), depth < 2 else { return m[0] }
            let full = vault.appendingPathComponent(found.path)
            let subpath = link.firstIndex(of: "#").map { String(link[link.index(after: $0)...]) }
            switch found.ext {
            case ".base":
                guard let text = baseRead(full) else { return m[0] }
                return "<div class=\"internal-embed bases-embed is-loaded\" src=\"\(attribute(link))\">\(baseHTML(text, vault: vault, items: items, address: address, selfPath: from, view: subpath, embedded: true))</div>"
            case ".canvas":
                guard let canvas = baseRead(full) else { return m[0] }
                return "<div class=\"internal-embed canvas-embed is-loaded\" src=\"\(attribute(link))\">\(canvasHTML(canvas, canvasPath: found.path, height: "400px", vault: vault, items: items, address: address, depth: depth + 1))</div>"
            case ".pdf":
                return "<div class=\"internal-embed pdf-embed is-loaded\" src=\"\(attribute(link))\"><iframe class=\"sage-pdf\" src=\"\(attribute(address(found.path)))\"></iframe></div>"
            case _ where videoTypes.contains(found.ext):
                // Plays in the note, as in Obsidian (2026-11-09).
                return "<div class=\"internal-embed media-embed is-loaded\" src=\"\(attribute(link))\"><video controls preload=\"metadata\" src=\"\(attribute(address(found.path)))\"></video></div>"
            case _ where soundTypes.contains(found.ext):
                return "<div class=\"internal-embed media-embed is-loaded\" src=\"\(attribute(link))\"><audio controls preload=\"metadata\" src=\"\(attribute(address(found.path)))\"></audio></div>"
            case ".md":
                guard let note = baseRead(full) else { return m[0] }
                let (_, body) = split(note.replacingOccurrences(of: "\r\n", with: "\n"))
                let inner = withVault(markdown(body), vault: vault, items: items, from: found.path, address: address, depth: depth + 1)
                return "<span class=\"internal-embed markdown-embed inline-embed is-loaded\" src=\"\(attribute(link))\"><div class=\"markdown-embed-content\">"
                    + "<div class=\"markdown-preview-view markdown-rendered\"><div class=\"markdown-preview-sizer markdown-preview-section\">\(inner)</div></div></div>"
                    + "<a class=\"markdown-embed-link\" href=\"sage-note:\(attribute(found.path))\" aria-label=\"Open link\" data-sage-icon=\"lucide-link\"></a></span>"
            default: return m[0]
            }
        }
        return withPictures(page, items: items, from: from, address: address)
    }

    /// A file the explorer doesn't list (a .csv, .py or .html while "Detect all file extensions" is off), found as the
    /// plugin finds it: by its path in the vault, beside the note, or by its name anywhere outside hidden folders.
    private static func onDisk(_ vault: URL, _ raw: String, _ from: String?) -> VaultItem? {
        let root = vault.standardizedFileURL.resolvingSymlinksInPath().path
        func item(_ full: URL) -> VaultItem? {
            let path = full.standardizedFileURL.resolvingSymlinksInPath().path
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), !isFolder.boolValue,
                  path.lowercased().hasPrefix(root.lowercased() + "/") else { return nil }
            let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            return VaultItem(path: String(path.dropFirst(root.count + 1)), folder: false, modified: values?.contentModificationDate ?? .distantPast, created: values?.creationDate ?? .distantPast)
        }
        var target = raw.replacingOccurrences(of: "\\", with: "/")
        while target.hasPrefix("/") { target.removeFirst() }
        if target.isEmpty || target.components(separatedBy: "/").contains("..") { return nil }
        let base = URL(fileURLWithPath: root, isDirectory: true)
        if let exact = item(base.appendingPathComponent(target)) { return exact }
        if let from, let slash = from.lastIndex(of: "/"), let beside = item(base.appendingPathComponent(String(from[..<slash])).appendingPathComponent(target)) { return beside }
        let name = (target as NSString).lastPathComponent
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        var found: [URL] = []
        for case let url as URL in walker where same(url.lastPathComponent, name) { found.append(url) }
        return found.sorted { $0.path.count < $1.path.count }.lazy.compactMap(item).first
    }

    private static func fileEmbed(_ file: VaultItem, _ height: Int?, _ vault: URL, _ items: [VaultItem], _ address: (String) -> String, _ depth: Int) -> String {
        let ext = String(file.ext.drop { $0 == "." })
        let full = vault.appendingPathComponent(file.path)
        if ext == "html" || ext == "htm" {
            return "<iframe class=\"va-file-embed-frame\" src=\"\(attribute(address(file.path)))\" title=\"\(attribute(file.title))\" height=\"\(height ?? 800)\" sandbox=\"allow-scripts allow-popups allow-forms\"></iframe>"
        }
        if ext == "canvas" {
            return baseRead(full).map { canvasHTML($0, canvasPath: file.path, height: "\(height ?? 600)px", vault: vault, items: items, address: address, depth: depth + 1) } ?? ""
        }
        let table: Character? = ext == "csv" ? "," : ext == "tsv" ? "\t" : nil
        if table != nil || ["txt", "log", "text"].contains(ext) || codeLanguages[ext.lowercased()] != nil {
            var text = baseRead(full) ?? ""
            let box = "<div class=\"va-file-embed-scroll\" style=\"max-height: \(height ?? 500)px\">"
            if let table {
                let rows = delimited(text, separator: table)
                if rows.isEmpty { return box + "<div class=\"va-file-embed-missing\">file-embed: empty file</div></div>" }
                var html = box + "<table class=\"va-file-embed-table\"><thead><tr>"
                for cell in rows[0] { html += "<th>\(escape(cell))</th>" }
                html += "</tr></thead><tbody>"
                for row in rows.dropFirst().prefix(2000) {
                    html += "<tr>"
                    for cell in row { html += "<td>\(escape(cell))</td>" }
                    html += "</tr>"
                }
                html += "</tbody></table>"
                if rows.count - 1 > 2000 { html += "<div class=\"va-file-embed-note\">Showing first 2000 of \(rows.count - 1) rows.</div>" }
                return html + "</div>"
            }
            guard let language = codeLanguages[ext.lowercased()] else { return box + "<pre class=\"va-file-embed-text\">\(escape(text))</pre></div>" }
            if ext == "json", let parsed = OrderedJSON.parse(text) { text = parsed.indented() }
            return box + "<pre class=\"language-\(language)\"><code class=\"language-\(language) is-loaded\">\(escape(text))</code></pre></div>"
        }
        return withVault(markdown("![[\(file.path)]]"), vault: vault, items: items, from: nil, address: address, depth: depth + 1)
    }

    /// A CSV or TSV's rows: quoted fields, "" inside them, and line breaks inside quotes, as the plugin reads them.
    static func delimited(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = String.UnicodeScalarView(), quoted = false
        var scalars = Array(text.unicodeScalars)
        while scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        let sep = separator.unicodeScalars.first!
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if quoted {
                if c == "\"" && i + 1 < scalars.count && scalars[i + 1] == "\"" { field.append("\""); i += 1 }
                else if c == "\"" { quoted = false }
                else { field.append(c) }
            } else if c == "\"" && field.isEmpty { quoted = true }
            else if c == sep { row.append(String(field)); field = String.UnicodeScalarView() }
            else if c == "\n" || c == "\r" {
                if c == "\r" && i + 1 < scalars.count && scalars[i + 1] == "\n" { i += 1 }
                row.append(String(field)); field = String.UnicodeScalarView()
                rows.append(row); row = []
            } else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(String(field)); rows.append(row) }
        return rows.filter { $0.contains { !$0.isEmpty } }
    }
}
