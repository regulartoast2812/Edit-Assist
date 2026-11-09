import Foundation

/// Sage's chat drawn as Markdown (2026-11-09, you asked: as Vault Agent's panel draws its replies): headings, bullets and
/// numbered lists (nested, with task boxes), quotes, code blocks, tables and rules as blocks; bold, italic, inline code and
/// links inside them, [[wikilinks]] as links that open the note in Notes. The blocks are worked out here (Foundation, so
/// the checks can read them); the page draws them (SageAgentView.swift).
extension Study {
    enum ChatBlock: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(level: Int, text: String, checked: Bool?)
        case numbered(level: Int, number: String, text: String)
        case quote(String)
        case code(language: String, text: String)
        case table(rows: [[String]])
        case rule
    }

    /// The address a [[wikilink]] gets in the chat: sage-note:Name (with its #heading).
    static let noteLinkScheme = "sage-note"

    static func chatBlocks(_ text: String) -> [ChatBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [ChatBlock] = [], paragraph: [String] = [], quote: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))); quote = [] }
        }
        func indentLevel(_ line: String) -> Int {
            let spaces = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            return spaces / 2
        }
        func cells(_ line: String) -> [String] {
            var row = line.trimmingCharacters(in: .whitespaces)
            if row.hasPrefix("|") { row.removeFirst() }
            if row.hasSuffix("|") { row.removeLast() }
            return row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        func isSeparator(_ line: String) -> Bool {
            let row = cells(line)
            return !row.isEmpty && row.allSatisfy { cell in !cell.isEmpty && cell.allSatisfy { "-:".contains($0) } && cell.contains("-") }
        }
        var index = 0
        while index < lines.count {
            let line = lines[index], trimmed = line.trimmingCharacters(in: .whitespaces)
            defer { index += 1 }
            // A fenced code block, to its closing fence (or the end).
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let fence = String(trimmed.prefix(3)), language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) { code.append(lines[index]); index += 1 }
                blocks.append(.code(language: language, text: code.joined(separator: "\n")))
                continue
            }
            if trimmed.isEmpty { flush(); continue }
            if let hashes = trimmed.firstIndex(where: { $0 != "#" }), hashes != trimmed.startIndex,
               trimmed.distance(from: trimmed.startIndex, to: hashes) <= 6, trimmed[hashes] == " " {
                flush()
                blocks.append(.heading(level: trimmed.distance(from: trimmed.startIndex, to: hashes), text: trimmed[hashes...].trimmingCharacters(in: .whitespaces)))
                continue
            }
            let bare = trimmed.replacingOccurrences(of: " ", with: "")
            if bare.count >= 3, let first = bare.first, "-*_".contains(first), bare.allSatisfy({ $0 == first }) { flush(); blocks.append(.rule); continue }
            if trimmed.hasPrefix(">") {
                if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            if trimmed.hasPrefix("|"), index + 1 < lines.count, isSeparator(lines[index + 1]) {
                flush()
                var rows = [cells(line)]
                index += 2
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") { rows.append(cells(lines[index])); index += 1 }
                index -= 1
                blocks.append(.table(rows: rows))
                continue
            }
            if let marker = trimmed.first, "-*+".contains(marker), trimmed.dropFirst().first == " " {
                flush()
                var item = String(trimmed.dropFirst(2))
                var checked: Bool?
                if item.hasPrefix("[ ] ") { checked = false; item.removeFirst(4) } else if item.lowercased().hasPrefix("[x] ") { checked = true; item.removeFirst(4) }
                blocks.append(.bullet(level: indentLevel(line), text: item, checked: checked))
                continue
            }
            let digits = trimmed.prefix { $0.isNumber }
            if !digits.isEmpty, digits.count <= 3, trimmed.dropFirst(digits.count).first.map({ ".)".contains($0) }) == true,
               trimmed.dropFirst(digits.count + 1).first == " " {
                flush()
                blocks.append(.numbered(level: indentLevel(line), number: String(digits), text: String(trimmed.dropFirst(digits.count + 2))))
                continue
            }
            // Text indented under a list item belongs to it.
            if paragraph.isEmpty, quote.isEmpty, line.hasPrefix("  "), let last = blocks.last {
                switch last {
                case let .bullet(level, text, checked): blocks[blocks.count - 1] = .bullet(level: level, text: text + "\n" + trimmed, checked: checked); continue
                case let .numbered(level, number, text): blocks[blocks.count - 1] = .numbered(level: level, number: number, text: text + "\n" + trimmed); continue
                default: break
                }
            }
            if !quote.isEmpty { flush() }
            paragraph.append(trimmed)
        }
        flush()
        return blocks
    }

    /// One block's text ready for the inline Markdown reader: [[Note]], [[Note#Part]] and [[Note|shown]] become links to the
    /// note (sage-note:), ![[embeds]] the same, and bare web addresses become links.
    static func chatInline(_ text: String) -> String {
        var result = substitute(#"!?\[\[([^\]\|\n]+?)(\|([^\]\n]*))?\]\]"#, in: text) { g in
            let target = g[1].trimmingCharacters(in: .whitespaces)
            let shown = g[3].isEmpty ? target : g[3]
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "#?%()[] ")
            let address = target.addingPercentEncoding(withAllowedCharacters: allowed) ?? target
            return "[\(shown.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]"))](\(noteLinkScheme):\(address))"
        }
        result = substitute(#"(^|[\s(])(https?://[^\s<>()\[\]]+[^\s<>()\[\].,;:!?'"])"#, in: result) { g in "\(g[1])<\(g[2])>" }
        return result
    }

    /// The note a sage-note: link names ("Pho#Broth" → "Pho"), or nil for any other link.
    static func noteLinkTarget(_ url: URL) -> String? {
        guard url.scheme == noteLinkScheme else { return nil }
        let raw = url.absoluteString.dropFirst(noteLinkScheme.count + 1)
        let name = (String(raw).removingPercentEncoding ?? String(raw))
        let bare = name.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? name
        return bare.trimmingCharacters(in: .whitespaces).isEmpty ? nil : bare.trimmingCharacters(in: .whitespaces)
    }
}
