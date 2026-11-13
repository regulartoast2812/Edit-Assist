import Foundation

/// (2026-11-13, you asked: our own autocorrect, Vietnamese and English, on the Mac and Windows; Vietnamese typed without
/// accents gets them, for academic writing) When a word is ended (a space or punctuation), it is put right:
/// - Vietnamese typed without accents gets them ("khong co gi" → "không có gì"), the run of words read together so each
///   word fits the ones beside it (word pairs counted in Vietnamese Wikipedia and news, Resources/Words), words before
///   it in the run fixed again once the run shows it's Vietnamese ("co the nghien" → "có thể nghiên").
/// - Telex typed with the input method off: "vieetj" → "việt".
/// - A misspelt syllable or English word: the closest one a letter or two off that clearly wins.
/// Never: a word you put back (Backspace right after; remembered), code, [[links]], #tags, links, words with digits,
/// ALL CAPS, a capitalised English word mid-sentence, the properties at the top of a note. Foundation only.
final class SageSpell: @unchecked Sendable {
    struct Tables {
        var vi: [String: Int] = [:]              // Vietnamese syllable → times
        var groups: [String: [String]] = [:]     // syllable without its marks → the syllables, commonest first
        var pairs: [String: Int] = [:]           // "syllable syllable" → times
        var triples: [String: Int] = [:]         // "syllable syllable syllable" → times
        var en: [String: Int] = [:]              // English word → times
        var viTotal = 1
    }
    /// What to change in the text given: `old` at UTF-16 offset `start` becomes `new`.
    struct Fix: Equatable { var start: Int; var old: String; var new: String }

    static let shared = SageSpell()
    private let lock = NSLock()
    private var tables = Tables()
    private var kept: Set<String> = []
    private var keptFile: URL?
    private var asked = false
    private var recent: Recent?
    /// The syllables the last fix gave accents to, still open to a better reading as the next words come, while the
    /// text before the word being typed still ends as that fix left it (`tail`).
    struct Recent { var tail: String; var words: Set<String> }

    /// Loads the tables (Resources/Words) and the words you kept, once, in the background.
    func prepare(words: URL?, kept file: URL?) {
        lock.lock()
        if asked { lock.unlock(); return }
        asked = true
        keptFile = file
        lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            let made = words.map(Self.load) ?? Tables()
            let kept = file.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                .map { Set($0.split(separator: "\n").map { String($0).precomposedStringWithCanonicalMapping }) } ?? []
            self.lock.lock()
            self.tables = made; self.kept.formUnion(kept)
            self.lock.unlock()
        }
    }

    func correct(_ before: String) -> Fix? {
        lock.lock(); let tables = self.tables, kept = self.kept; lock.unlock()
        guard !tables.vi.isEmpty else { return nil }
        lock.lock(); var recent = self.recent; lock.unlock()
        let fix = Self.correct(before, tables: tables, vault: SageWords.shared.snapshot(), kept: kept, recent: &recent)
        lock.lock(); self.recent = recent; lock.unlock()
        return fix
    }

    /// The words of `old` that `new` changed (a fix put back: those are kept as typed).
    static func changed(_ old: String, _ new: String) -> [String] {
        let a = old.split(separator: " "), b = new.split(separator: " ")
        return a.indices.filter { $0 >= b.count || a[$0] != b[$0] }.map { String(a[$0]) }
    }

    /// A word you put back: never corrected again (kept in sage/kept-words.txt).
    func keep(_ words: [String]) {
        let new = words.map { $0.lowercased().precomposedStringWithCanonicalMapping }.filter { !$0.isEmpty }
        lock.lock()
        let added = new.filter { kept.insert($0).inserted }
        let file = keptFile, all = kept
        lock.unlock()
        guard !added.isEmpty, let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (all.sorted().joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: Tables

    static func load(_ folder: URL) -> Tables {
        func rows(_ name: String) -> [(String, Int)] {
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap { line in
                guard let tab = line.lastIndex(of: "\t"), let n = Int(line[line.index(after: tab)...]) else { return nil }
                return (String(line[..<tab]), n)
            }
        }
        var t = Tables()
        for (w, n) in rows("vi-syllables.tsv") { t.vi[w] = n; t.groups[fold(w), default: []].append(w); t.viTotal += n }
        for (p, n) in rows("vi-pairs.tsv") { t.pairs[p] = n }
        for (p, n) in rows("vi-triples.tsv") { t.triples[p] = n }
        for (w, n) in rows("en-words.tsv") { t.en[w] = n }
        return t
    }

    // MARK: Vietnamese marks

    private static let toneMarks: [Unicode.Scalar: Character] = ["\u{300}": "f", "\u{301}": "s", "\u{309}": "r", "\u{303}": "x", "\u{323}": "j"]

    /// Without any mark: "Được" → "Duoc".
    static func fold(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.decomposedStringWithCanonicalMapping.unicodeScalars where u.properties.generalCategory != .nonspacingMark {
            out.append(u == "đ" ? "d" : u == "Đ" ? "D" : u)
        }
        return String(out)
    }
    /// Without its tone, its other marks kept: "được" → "đươc".
    static func toneless(_ s: String) -> String {
        String(String.UnicodeScalarView(s.decomposedStringWithCanonicalMapping.unicodeScalars.filter { toneMarks[$0] == nil }))
            .precomposedStringWithCanonicalMapping
    }
    /// Its tone as Telex types it (s f r x j), or nil.
    static func tone(_ s: String) -> Character? {
        s.decomposedStringWithCanonicalMapping.unicodeScalars.lazy.compactMap { toneMarks[$0] }.first
    }

    /// A word typed in Telex with the input method off ("vieetj", "dduowcj"), as the syllable it spells, if one.
    static func telex(_ lower: String, _ t: Tables) -> String? {
        let vowels = Set("aeiouy")
        func marks(_ s: String) -> String {
            var s = s
            if s.hasPrefix("dd") { s = "đ" + s.dropFirst(2) }
            for (a, b) in [("uow", "ươ"), ("uwow", "ươ"), ("aa", "â"), ("aw", "ă"), ("ee", "ê"), ("oo", "ô"), ("ow", "ơ"), ("uw", "ư"), ("w", "ư")] {
                s = s.replacingOccurrences(of: a, with: b)
            }
            return s
        }
        func spelt(_ bare: String, _ key: Character?) -> String? {
            t.groups[fold(bare)]?.first { toneless($0) == bare && tone($0) == key }
        }
        let chars = Array(lower)
        var tries: [(String, Character?)] = [(lower, nil)]
        for (i, c) in chars.enumerated() where "sfrxj".contains(c) && i > 0 && chars[..<i].contains(where: { vowels.contains($0) }) {
            var rest = chars; rest.remove(at: i)
            tries.insert((String(rest), c), at: 0)
        }
        for (bare, key) in tries {
            let m = marks(bare)
            if m == lower && key == nil { continue }
            if let found = spelt(m, key) { return found }
        }
        return nil
    }

    // MARK: Correcting

    static let enders: Set<Character> = Set(" \n\t.,;:!?)]}\"”")
    private static let breakers = Set(".!?\n")

    static func correct(_ before: String, tables t: Tables, vault: SageWords.Model, kept: Set<String>, recent: inout Recent?) -> Fix? {
        let text = before.precomposedStringWithCanonicalMapping
        let chars = Array(text)
        guard chars.count >= 2, let last = chars.last, enders.contains(last) else { return nil }
        let earlier = recent
        recent = nil
        var offsets = [0]; offsets.reserveCapacity(chars.count + 1)
        for c in chars { offsets.append(offsets.last! + c.utf16.count) }
        // Not in code, a [[link]], the properties at the top, a code block.
        let lineStart = (chars.lastIndex(of: "\n").map { $0 + 1 }) ?? 0
        let line = String(chars[lineStart...])
        if line.filter({ $0 == "`" }).count % 2 == 1 { return nil }
        if let open = line.range(of: "[[", options: .backwards), !line[open.upperBound...].contains("]]") { return nil }
        let lines = text.components(separatedBy: "\n")
        if lines.first == "---", !lines.dropFirst().dropLast().contains("---") { return nil }
        if lines.filter({ $0.hasPrefix("```") || $0.hasPrefix("~~~") }).count % 2 == 1 { return nil }

        // The words of the run ending at the cursor: single spaces between, nothing else.
        func letter(_ c: Character) -> Bool { c.isLetter }
        func word(endingAt end: Int) -> Word? {
            var i = end
            while i > 0, letter(chars[i - 1]) || ((chars[i - 1] == "'" || chars[i - 1] == "’") && i >= 2 && letter(chars[i - 2]) && i < end) { i -= 1 }
            guard i < end else { return nil }
            if i > 0, "#@/\\_.[:=-+*~`|<>".contains(chars[i - 1]) || chars[i - 1].isNumber { return nil }
            return Word(from: i, to: end, text: String(chars[i ..< end]))
        }
        guard let current = word(endingAt: chars.count - 1) else { return nil }
        var run = [current]
        while run.count < 7, let first = run.first, first.from >= 2, chars[first.from - 1] == " ", let w = word(endingAt: first.from - 1) {
            run.insert(w, at: 0)
        }

        func lower(_ s: String) -> String { s.lowercased() }
        func marked(_ s: String) -> Bool { fold(s) != s }
        func english(_ l: String) -> Bool { t.en[l] != nil }
        func caps(_ s: String) -> Bool { s.count >= 2 && s == s.uppercased() && s != s.lowercased() }
        func known(_ l: String) -> Bool { t.vi[l] != nil || t.en[l] != nil || (vault.count[l] ?? 0) >= 2 || kept.contains(l) }
        func startsSentence(_ w: Word) -> Bool {
            var i = w.from - 1
            while i >= 0, chars[i] == " " || chars[i] == "\"" || chars[i] == "(" || chars[i] == "*" { i -= 1 }
            return i < 0 || breakers.contains(chars[i]) || chars[i] == "#" || chars[i] == ">"
        }
        func cased(_ new: String, like old: String) -> String {
            guard let f = old.first, f.isUppercase else { return new }
            return new.prefix(1).uppercased() + new.dropFirst()
        }

        // Is it Vietnamese? Its own marks, else the nearest word before that tells, else whether it's English.
        let cur = current.text, lc = lower(cur)
        let telexed = (!known(lc) && !caps(cur)) ? telex(lc, t) : nil
        let mine = !english(lc) && (t.groups[lc] != nil || telexed != nil)
        var vietnamese = marked(cur)
        // The sentence so far tells (up to 12 words back, over numbers and commas).
        var sentenceStart = current.from
        while sentenceStart > 0, !breakers.contains(chars[sentenceStart - 1]) { sentenceStart -= 1 }
        var told: Bool?
        for w in SageWords.words(String(chars[sentenceStart ..< current.from])).suffix(12).reversed() {
            let l = lower(w)
            let named = w.first?.isUppercase == true   // a name tells nothing
            if (marked(w) && t.vi[l] != nil) || (!named && !english(l) && t.groups[l] != nil && l.count >= 2) { told = true; break }
            if english(l) && t.groups[fold(l)] == nil { told = false; break }
        }
        if !vietnamese { vietnamese = told == true ? !(t.groups[lc] == nil && known(lc)) : mine }

        // The current word first: a Telex word, a misspelt syllable or English word.
        var words = run.map { $0.text }
        var fixed = Array(repeating: false, count: run.count)    // positions the run's reading mustn't touch
        for (i, w) in run.enumerated() {
            let l = lower(w.text)
            if kept.contains(l) || caps(w.text) || marked(w.text) || t.groups[fold(l)] == nil { fixed[i] = true }
            if i < run.count - 1, marked(w.text), !kept.contains(l), let earlier, earlier.words.contains(l),
               String(chars[..<current.from]).hasSuffix(earlier.tail), t.groups[fold(l)] != nil { fixed[i] = false }
            if i < run.count - 4 { fixed[i] = true }   // older words are the reading's context, no longer open
        }
        let n = run.count - 1
        func score(_ a: String?, _ b: String) -> Double {
            let uni = log(Double(t.vi[b] ?? 0) + 0.5) - log(Double(t.viTotal))
            guard let a, t.vi[a] != nil else { return uni }
            let together = Double(t.pairs[a + " " + b] ?? 0) + Double(vault.after[a]?[b] ?? 0) * 5
            return together > 0 ? log(together / Double(t.vi[a] ?? 1)) : log(0.05) + uni
        }
        if !kept.contains(lc), !caps(cur), lc.count >= 1 {
            if vietnamese {
                if let telexed {
                    words[n] = cased(telexed, like: cur); fixed[n] = true
                } else if (marked(cur) && t.vi[lc] == nil && vault.count[lc] == nil) || (!marked(cur) && !known(lc) && t.groups[lc] == nil && lc.count >= 3) {
                    let left = n > 0 ? lower(words[n - 1]) : nil, mineBare = toneless(lc)
                    var best: [(String, Double)] = []
                    for e in Set([fold(lc)] + edits(fold(lc), letters: "abcdeghiklmnopqrstuvxy")) {
                        for c in t.groups[e]?.prefix(8) ?? [] where c != lc {
                            best.append((c, score(left, c) + (toneless(c) == mineBare ? 2.3 : 0) + (e == fold(lc) ? 1.6 : 0)))
                        }
                    }
                    best.sort { $0.1 > $1.1 }
                    if let top = best.first, best.count == 1 || top.1 - best[1].1 > 1.1 {
                        words[n] = cased(top.0, like: cur); fixed[n] = marked(top.0)
                    }
                }
            } else if !known(lc), lc.count >= 3, !(cur.first?.isUppercase == true && !startsSentence(current)) {
                func found(_ list: Set<String>) -> [(String, Int)] {
                    list.compactMap { e in
                        let seen = (t.en[e] ?? 0) + ((vault.count[e] ?? 0) >= 2 ? (vault.count[e] ?? 0) * 50 : 0)
                        return seen > 0 ? (e, seen) : nil
                    }.sorted { $0.1 > $1.1 }
                }
                let near = Set(edits(lc, letters: "abcdefghijklmnopqrstuvwxyz"))
                var best = found(near)
                if best.isEmpty, (6...12).contains(lc.count) { best = found(Set(near.flatMap { edits($0, letters: "abcdefghijklmnopqrstuvwxyz") })) }
                if let top = best.first, best.count == 1 || top.1 >= best[1].1 * 3 {
                    return change(run, upTo: n, [String](words.dropLast()) + [cased(top.0, like: cur)], chars, offsets)
                }
                return nil
            }
        }
        guard vietnamese else { return nil }

        // The run read together: each accentless syllable the reading that fits the words beside it best. English words
        // only once the run is surely Vietnamese (a word with accents in it, or two that aren't English).
        let sure = told == true || words.contains { marked($0) && t.vi[lower($0)] != nil }
            || words.indices.filter { !fixed[$0] && !english(lower(words[$0])) }.count >= 2
        // In an English sentence one word alone (a name, a borrowed word) is left as typed.
        for (i, w) in words.enumerated() where !fixed[i] && !sure && (english(lower(w)) || told == false) { fixed[i] = true }
        guard fixed.contains(false) else { return change(run, upTo: n, words, chars, offsets) }
        let options: [[String]] = words.enumerated().map { i, w in
            fixed[i] ? [lower(w)] : Array((t.groups[fold(lower(w))] ?? [lower(w)]).prefix(8))
        }
        // Each word scored on the two before it where the three were seen together, else on the one before.
        func score3(_ a: String?, _ b: String?, _ c: String) -> Double {
            guard let a, let b, let ab = t.pairs[a + " " + b] else { return score(b, c) }
            if let abc = t.triples[a + " " + b + " " + c] { return log(Double(abc) / Double(ab)) }
            return log(0.4) + score(b, c)
        }
        var paths: [(score: Double, words: [String])] = options[0].map { (score(nil, $0), [$0]) }
        for i in 1 ..< options.count {
            var best: [String: (score: Double, words: [String])] = [:]
            for path in paths {
                for c in options[i] {
                    let next = (score: path.score + score3(path.words.dropLast().last, path.words.last, c), words: path.words + [c])
                    let key = (path.words.last ?? "") + " " + c
                    if best[key].map({ next.score > $0.score }) ?? true { best[key] = next }
                }
            }
            paths = Array(best.values)
        }
        let read = paths.max { $0.score < $1.score }!.words
        for i in words.indices where !fixed[i] { words[i] = cased(read[i], like: words[i]) }
        let fix = change(run, upTo: n, words, chars, offsets)
        var after = text
        if let fix { after = ((text as NSString).replacingCharacters(in: NSRange(location: fix.start, length: (fix.old as NSString).length), with: fix.new)) }
        recent = Recent(tail: String(after.suffix(80)), words: Set(words.indices.filter { !fixed[$0] }.map { lower(words[$0]) }))
        return fix
    }

    private struct Word { var from: Int; var to: Int; var text: String }   // indexes into the text's characters

    /// The fix from the first word that changed to the end of the run (single spaces between its words).
    private static func change(_ run: [Word], upTo n: Int, _ words: [String], _ chars: [Character], _ offsets: [Int]) -> Fix? {
        guard let first = run.indices.first(where: { run[$0].text != words[$0] }) else { return nil }
        let from = run[first].from, to = run[n].to
        return Fix(start: offsets[from], old: String(chars[from ..< to]), new: words[first ... n].joined(separator: " "))
    }

    /// The words a letter off: one dropped, two swapped, one changed, one added.
    static func edits(_ w: String, letters: String) -> [String] {
        let c = Array(w), l = Array(letters)
        var out: [String] = []
        for i in 0 ... c.count {
            if i < c.count { var d = c; d.remove(at: i); out.append(String(d)) }
            if i + 1 < c.count { var s = c; s.swapAt(i, i + 1); out.append(String(s)) }
            for x in l {
                if i < c.count, x != c[i] { var r = c; r[i] = x; out.append(String(r)) }
                var a = c; a.insert(x, at: i); out.append(String(a))
            }
        }
        return out
    }
}
