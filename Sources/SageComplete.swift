import Foundation

/// (2026-11-13, you asked) Word completion as you type: the word being typed is finished in grey and Tab takes it.
/// (2026-11-13, you asked: useful from the start, not only once the vault is a dictionary; the vault's own in [[ ]])
/// - Everywhere: general language only. English from common words (Resources/Words/en-complete.tsv), Vietnamese from
///   its syllables and which follows which (SageSpell's tables), so "nghiên c" → "cứu"; a word whose start is a letter
///   off is offered whole ("missisi → Mississippi").
/// - Inside [[: the vault's notes, most linked first, "]]" closing it.
/// The vault's words and pairs are still read for autocorrect. Foundation only, so the Windows port keeps it as it is.
final class SageWords: @unchecked Sendable {
    static let shared = SageWords()

    struct Model {
        var keys: [String] = []                      // every known word, lowercased, sorted
        var spelling: [String: String] = [:]         // how the word is written (lowercase when it's ever written so)
        var count: [String: Int] = [:]
        var after: [String: [String: Int]] = [:]     // word before → word → times
        var notes: [String] = []                     // the vault's note names, lowercased, sorted
        var noteName: [String: String] = [:]         // lowercased → as named
        var linked: [String: Int] = [:]              // lowercased name → times [[linked]]

        static let shortest = 4                      // words shorter than this aren't worth finishing
    }
    /// (2026-11-13, you asked: Mississippi wasn't offered) Common English words beyond the vault's, as written
    /// (Resources/Words/en-complete.tsv: subtitles' commonest, names with their capital).
    struct Dictionary {
        var keys: [String] = []
        var spelling: [String: String] = [:]
        var count: [String: Int] = [:]
        var total = 1
    }
    /// A finish: `word` written in place of the `replace` UTF-16 units typed; `shown` is the grey text after the caret
    /// (the rest of the word, or "→ word" when what was typed is a letter off).
    struct Completion: Equatable { var word: String; var replace: Int; var shown: String }

    private let lock = NSLock()
    private var model = Model()
    private var vault: URL?
    private var built = Date.distantPast
    private var building = false
    private var dictionary = Dictionary()
    private var dictionaryAsked = false

    /// Reads the English list once, in the background.
    func prepare(dictionary file: URL?) {
        lock.lock()
        if dictionaryAsked { lock.unlock(); return }
        dictionaryAsked = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            let made = file.flatMap { try? String(contentsOf: $0, encoding: .utf8) }.map(Self.dictionary) ?? Dictionary()
            self.lock.lock(); self.dictionary = made; self.lock.unlock()
        }
    }

    static func dictionary(_ text: String) -> Dictionary {
        var made = Dictionary()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count == 2, let n = Int(parts[1]) else { continue }
            let word = String(parts[0]), key = word.lowercased()
            made.spelling[key] = word; made.count[key] = n; made.total += n
        }
        made.keys = made.count.keys.sorted()
        return made
    }

    /// Reads the vault's words (again when it's another vault, or ten minutes on), in the background.
    func learn(vault: URL) {
        lock.lock()
        let fresh = self.vault == vault && Date().timeIntervalSince(built) < 600
        if building || fresh { lock.unlock(); return }
        building = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            var made = Self.model(Self.notes(in: vault))
            for name in Self.names(in: vault) { made.noteName[name.lowercased()] = name }
            made.notes = made.noteName.keys.sorted()
            self.lock.lock()
            self.model = made; self.vault = vault; self.built = Date(); self.building = false
            self.lock.unlock()
        }
    }

    /// The words as last read (autocorrect keeps the vault's own words and pairs).
    func snapshot() -> Model {
        lock.lock(); defer { lock.unlock() }
        return model
    }

    /// The finish of the word the text ends in, or nil; `closed`: "]]" follows the caret.
    func complete(_ before: String, closed: Bool = false) -> Completion? {
        lock.lock(); let model = self.model, dictionary = self.dictionary; lock.unlock()
        return Self.complete(before, closed: closed, english: dictionary, vi: SageSpell.shared.snapshot(), vault: model)
    }

    /// The names [[links]] use for the vault's files: a note without .md, another file with its extension (at most 20000).
    static func names(in vault: URL) -> [String] {
        guard let walk = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [String] = []
        for case let url as URL in walk where !url.hasDirectoryPath {
            if out.count >= 20000 { break }
            out.append(url.pathExtension.lowercased() == "md" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent)
        }
        return out
    }

    /// The vault's notes, as text (hidden folders skipped; at most 4000 notes, 1 MB each).
    static func notes(in vault: URL) -> [String] {
        guard let walk = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: [.fileSizeKey],
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var texts: [String] = []
        for case let url as URL in walk where url.pathExtension.lowercased() == "md" {
            if texts.count >= 4000 { break }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_000_000 { continue }
            if let text = try? String(contentsOf: url, encoding: .utf8) { texts.append(text) }
        }
        return texts
    }

    /// The words of a text, as written: letters and digits (with an apostrophe inside), each with a letter.
    static func words(_ text: String) -> [String] {
        var out: [String] = [], word = ""
        func end() {
            while word.last == "'" || word.last == "’" { word.removeLast() }
            if word.contains(where: { $0.isLetter }) { out.append(word) }
            word = ""
        }
        for ch in text.precomposedStringWithCanonicalMapping {
            if ch.isLetter || ch.isNumber || ((ch == "'" || ch == "’") && !word.isEmpty) { word.append(ch) } else if !word.isEmpty { end() }
        }
        if !word.isEmpty { end() }
        return out
    }

    static func model(_ texts: [String]) -> Model {
        var model = Model()
        let link = try! NSRegularExpression(pattern: "\\[\\[([^\\]|#\\n]+)")
        for text in texts {
            for m in link.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(m.range(at: 1), in: text) {
                    model.linked[(String(text[r]) as NSString).lastPathComponent.lowercased(), default: 0] += 1
                }
            }
            var previous: String?
            for word in words(text) {
                let key = word.lowercased()
                model.count[key, default: 0] += 1
                if model.spelling[key] == nil || word == key { model.spelling[key] = word }
                if let previous { model.after[previous, default: [:]][key, default: 0] += 1 }
                previous = key
            }
        }
        model.keys = model.count.keys.sorted()
        return model
    }

    /// The finish of the text's last word (see the type's note), or nil.
    static func complete(_ before: String, closed: Bool = false, english: Dictionary, vi: SageSpell.Tables, vault: Model) -> Completion? {
        let text = before.precomposedStringWithCanonicalMapping
        let line = text.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        if let open = line.range(of: "[[", options: .backwards), !line[open.upperBound...].contains("]") {
            return link(String(line[open.upperBound...]), closed: closed, vault: vault)
        }
        guard let last = text.last, last.isLetter else { return nil }
        let all = words(String(text.suffix(200)))
        guard let typed = all.last, text.hasSuffix(typed), typed.allSatisfy(\.isLetter) else { return nil }
        let lower = typed.lowercased()
        // The sentence so far: the nearest word that tells the language, and the word just before (one space apart).
        let sentence = String(text.dropLast(typed.count))
        let start = sentence.lastIndex(where: { ".!?\n".contains($0) }).map { sentence.index(after: $0) } ?? sentence.startIndex
        let before = words(String(sentence[start...])).map { $0.lowercased() }
        func vietnamese(_ w: String) -> Bool? {
            if SageSpell.fold(w) != w { return vi.vi[w] != nil ? true : nil }
            if vi.en[w] != nil { return false }
            return vi.groups[w] != nil ? true : nil
        }
        let told = before.reversed().lazy.compactMap(vietnamese).first
        let joined = sentence.hasSuffix(" ") && !sentence.hasSuffix("  ")
        let previous = joined ? before.last : nil
        let earlier = joined && before.count >= 2 && sentence.dropLast().hasSuffix(" " + (before.last ?? "")) ? before[before.count - 2] : nil

        var made: Completion?
        let viBest = told == false && SageSpell.fold(lower) == lower ? nil : syllable(lower, after: previous, earlier: earlier, vi: vi)
        let enBest = told == true ? nil : word(lower, english: english, known: vi.en)
        if let v = viBest, let e = enBest { made = (told == true || v.score >= e.score) ? v.made : e.made }
        else { made = viBest?.made ?? enBest?.made ?? (told == true ? word(lower, english: english, known: vi.en)?.made : nil) }
        guard var made else { return nil }
        if typed.count >= 2 && typed == typed.uppercased() && typed != lower { made.word = made.word.uppercased() }
        else if typed.first?.isUppercase == true { made.word = made.word.prefix(1).uppercased() + made.word.dropFirst() }
        made.replace = typed.utf16.count
        made.shown = made.word.lowercased().hasPrefix(lower) ? String(made.word.dropFirst(typed.count)) : "  → " + made.word
        return made
    }

    /// Inside [[: the vault's note whose name starts so (else has a word starting so), most linked, then shortest.
    static func link(_ typed: String, closed: Bool, vault: Model) -> Completion? {
        let key = typed.lowercased()
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty, !key.contains("|"), !key.contains("#") else { return nil }
        var best: (name: String, score: Int)?
        func consider(_ name: String, _ bonus: Int) {
            let score = bonus + (vault.linked[name] ?? 0) * 100 - name.count
            if best == nil || score > best!.score { best = (name, score) }
        }
        var low = 0, high = vault.notes.count
        while low < high { let mid = (low + high) / 2; if vault.notes[mid] < key { low = mid + 1 } else { high = mid } }
        var i = low
        while i < vault.notes.count, i < low + 2000, vault.notes[i].hasPrefix(key) { consider(vault.notes[i], 1_000_000); i += 1 }
        if best == nil { for name in vault.notes where name.contains(" " + key) { consider(name, 0) } }
        guard let found = best, let name = vault.noteName[found.name] else { return nil }
        let end = closed ? "" : "]]"
        let starts = found.name.hasPrefix(key)
        return Completion(word: name + end, replace: typed.utf16.count,
                          shown: starts ? String(name.dropFirst(typed.count)) + end : "  → " + name + end)
    }

    /// Vietnamese: the syllable starting as typed (marks typed must match) likeliest after the one before, carried on by
    /// the syllable nearly always written after it ("phương ph" → "pháp"; "nghiên c" → "cứu"). One letter typed is enough
    /// after a syllable it often follows.
    static func syllable(_ typed: String, after previous: String?, earlier: String? = nil, vi: SageSpell.Tables) -> (made: Completion, score: Double)? {
        let f = SageSpell.fold(typed), plain = f == typed, bare = SageSpell.toneless(typed), mark = SageSpell.tone(typed)
        guard !vi.folds.isEmpty, !f.isEmpty else { return nil }
        // A word typed with its marks is that syllable; without, any of its readings ("co": có, cô, co…).
        func readings(_ w: String?) -> [String] { w.map { p in SageSpell.fold(p) != p ? (vi.vi[p] != nil ? [p] : []) : (vi.groups[p] ?? []) } ?? [] }
        let befores = readings(previous), befores2 = readings(earlier)
        let beforeTimes = Double(max(befores.reduce(0) { $0 + (vi.vi[$1] ?? 0) }, 1))
        var twoTimes: [String: Int] = [:]      // "earlier previous" → times, for the three-syllable counts
        for a in befores2 { for b in befores { if let n = vi.pairs[a + " " + b] { twoTimes[a + " " + b] = n } } }
        let twoTotal = twoTimes.values.reduce(0, +)
        let total = log(Double(vi.viTotal))
        var best: (word: String, score: Double)?
        var low = 0, high = vi.folds.count
        while low < high { let mid = (low + high) / 2; if vi.folds[mid] < f { low = mid + 1 } else { high = mid } }
        var i = low
        while i < vi.folds.count, i < low + 400, vi.folds[i].hasPrefix(f) {
            // A syllable as long as what's typed is it, accents aside (autocorrect gives those): when it's likeliest, no finish.
            for s in vi.groups[vi.folds[i]] ?? [] where s.count >= typed.count {
                if !plain && !s.hasPrefix(typed) && !(SageSpell.toneless(s).hasPrefix(bare) && (mark == nil || mark == SageSpell.tone(s))) { continue }
                // After the two before it when those three are counted, else after the one before (its readings together).
                var paired = Double(befores.reduce(0) { $0 + (vi.pairs[$1 + " " + s] ?? 0) }) / beforeTimes
                let three = twoTimes.keys.reduce(0) { $0 + (vi.triples[$1 + " " + s] ?? 0) }
                if three > 0 { paired = max(paired, Double(three) / Double(twoTotal)) }
                if typed.count < 2 && paired < 0.03 && s.count > typed.count { continue }
                let score = paired > 0 ? log(paired) : log(0.02) + log(Double(vi.vi[s] ?? 1)) - total
                if best == nil || score > best!.score { best = (s, score) }
            }
            i += 1
        }
        guard let found = best, found.word.count > typed.count else { return nil }
        var word = found.word
        if let n = vi.next[word], n.times >= 30, Double(n.times) >= 0.4 * Double(vi.vi[word] ?? .max) { word += " " + n.word }
        return (Completion(word: word, replace: 0, shown: ""), found.score)
    }

    /// English: the commonest word starting as typed (three letters typed at least, four in all), none when the word
    /// typed is commoner itself ("the"); with none and four typed, the commonest whose start is a letter off.
    static func word(_ typed: String, english: Dictionary, known: [String: Int] = [:]) -> (made: Completion, score: Double)? {
        guard typed.count >= 3, typed.allSatisfy({ $0.isASCII }), !english.keys.isEmpty else { return nil }
        var best: (key: String, n: Int)?
        func search(_ start: String, least: Int) {
            var low = 0, high = english.keys.count
            while low < high { let mid = (low + high) / 2; if english.keys[mid] < start { low = mid + 1 } else { high = mid } }
            var i = low
            while i < english.keys.count, i < low + 500, english.keys[i].hasPrefix(start) {
                let key = english.keys[i], n = english.count[key] ?? 0; i += 1
                if key == typed || key.count >= max(typed.count + 1, Model.shortest), n >= least,
                   best == nil || n > best!.n { best = (key, n) }
            }
        }
        search(typed, least: 1)
        if best == nil, typed.count >= 4 {
            for start in Set(SageSpell.edits(typed, letters: "abcdefghijklmnopqrstuvwxyz")) where start.count >= 3 { search(start, least: 50) }
        }
        guard let best, best.key != typed, (known[typed] ?? 0) < best.n else { return nil }
        return (Completion(word: english.spelling[best.key] ?? best.key, replace: 0, shown: ""), log(Double(best.n)) - log(Double(english.total)))
    }
}
