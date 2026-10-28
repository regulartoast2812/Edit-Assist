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

/// The script as one run of words in reading order, each knowing which bold phrase it belongs to (by its index among
/// all bold phrases, the order of `Store.targets`) and which word of that phrase it is. A caption read on screen is
/// placed in it (`locate`), so the bold words of that very part of the script are the ones styled: matching phrases
/// anywhere on screen styled "Fabric" inside "Soft fabric" and "wire" twice on one word when a word repeats (2026-10-28).
struct ScriptMap {
    struct Word: Equatable { var text: String; var phrase: Int?; var index: Int }
    private(set) var words: [Word] = []
    /// Where each phrase's first word is.
    private(set) var phraseStart: [Int: Int] = [:]
    let vocabulary: Set<String>

    /// Words as the matcher reads them: runs of letters and digits, lowercased, two characters or more.
    init(lines: [ScriptLine]) {
        var all: [Word] = []
        var starts: [Int: Int] = [:]
        var phrase = 0
        for line in lines {
            let chars = Array(line.text)
            var counts: [Int: Int] = [:]
            var i = 0
            while i < chars.count {
                guard chars[i].isLetter || chars[i].isNumber else { i += 1; continue }
                let start = i
                while i < chars.count, chars[i].isLetter || chars[i].isNumber { i += 1 }
                let text = String(chars[start ..< i]).lowercased()
                guard text.count > 1 else { continue }
                // A word touched by a bold range belongs to it, whole (bold that starts inside a word covers the word).
                let k = line.highlights.firstIndex { $0.start < i && $0.end > start }
                let p = k.map { phrase + $0 }
                let n = p.map { counts[$0, default: 0] } ?? 0
                if let p { counts[p] = n + 1; if n == 0 { starts[p] = all.count } }
                all.append(Word(text: text, phrase: p, index: n))
            }
            phrase += line.highlights.count
        }
        words = all; phraseStart = starts
        vocabulary = Set(all.map(\.text))
    }

    /// A read word against a script word: the same, one look-alike letter (lookalikes), one letter off in a longer
    /// word, or a punctuation mark read as a digit after it ("lift3" for "lift?").
    static func same(_ read: String, _ word: String, lookalikes: Set<String>) -> Bool {
        if read == word { return true }
        let a = Array(read), b = Array(word)
        if a.count == b.count + 1, read.hasPrefix(word), a.last?.isNumber == true, !word.allSatisfy(\.isNumber) { return true }
        guard !word.allSatisfy(\.isNumber), !read.allSatisfy(\.isNumber) else { return false }
        if a.count == b.count {
            let differing = zip(a, b).filter { $0 != $1 }
            if differing.count == 1, let pair = differing.first, lookalikes.contains(String([pair.0, pair.1])) || b.count >= 5 { return true }
        }
        return false
    }

    /// Where a caption's words start in the script: the place where most of them line up (at least two and 60%; a
    /// one-word caption only where that word is), nearest to `cursor` going forward when places tie.
    func locate(_ caption: [String], near cursor: Int, same: (String, String) -> Bool) -> Int? {
        let m = caption.count, n = words.count
        guard m > 0, n > 0 else { return nil }
        let need = m == 1 ? 1 : max(2, Int((Double(m) * 0.6).rounded(.up)))
        var best: (score: Int, distance: Int, start: Int)?
        for s in 0 ..< n {
            var score = 0
            for i in 0 ..< m where s + i < n && same(caption[i], words[s + i].text) { score += 1 }
            if m == 1 && caption[0] != words[s].text { continue }
            guard score >= need else { continue }
            let distance = s >= cursor ? s - cursor : (cursor - s) * 3
            if best == nil || score > best!.score || (score == best!.score && distance < best!.distance) { best = (score, distance, s) }
        }
        return best?.start
    }

    /// A caption word that is two script words read as one ("rightup"), split back so the words line up.
    func split(_ read: String) -> [String]? {
        guard !vocabulary.contains(read), read.count >= 4 else { return nil }
        for cut in 2 ... read.count - 2 {
            let head = String(read.prefix(cut)), tail = String(read.dropFirst(cut))
            if vocabulary.contains(head), vocabulary.contains(tail) { return [head, tail] }
        }
        return nil
    }
}
