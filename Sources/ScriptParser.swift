import Foundation

enum ScriptParser {
    // Character offsets, not bytes; preserve punctuation and Unicode in the source.
    static func parse(_ markdown: String) throws -> [ScriptLine] {
        let chars = Array(markdown.replacingOccurrences(of: "\r\n", with: "\n"))
        var lines: [ScriptLine] = []
        var output = ""
        var spans: [TextSpan] = []
        var bold = false
        var start = 0
        var i = 0
        func closeSpan() {
            let end = output.count
            if end > start {
                let text = String(Array(output)[start..<end])
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    spans.append(TextSpan(start: start, end: end, text: text))
                }
            }
        }
        func closeLine() {
            if bold { closeSpan() }
            if !output.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(ScriptLine(id: lines.count, text: output, highlights: spans))
            }
            output = ""; spans = []; start = 0
        }
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count, ["*", "\\"].contains(chars[i + 1]) {
                output.append(chars[i + 1]); i += 2; continue
            }
            if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                if bold { closeSpan() } else { start = output.count }
                bold.toggle(); i += 2; continue
            }
            if chars[i] == "\n" { closeLine() } else { output.append(chars[i]) }
            i += 1
        }
        guard !bold else { throw AssistError.message("A bold phrase is missing its closing ** marker.") }
        closeLine()
        return lines
    }
}
