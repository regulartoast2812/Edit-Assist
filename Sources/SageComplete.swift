import Foundation

/// (2026-11-13, you asked) Word completion as you type, from the vault's own words: the word being typed is finished in
/// grey and Tab takes it. The words are read from the vault's notes off the main thread and counted, with which word
/// follows which, so the likeliest finish after the word before wins (Vietnamese as well as English). Foundation only,
/// so the Windows port keeps it as it is; the boxes that show the grey text are the platform's.
final class SageWords: @unchecked Sendable {
    static let shared = SageWords()

    struct Model {
        var keys: [String] = []                      // every known word, lowercased, sorted
        var spelling: [String: String] = [:]         // how the word is written (lowercase when it's ever written so)
        var count: [String: Int] = [:]
        var after: [String: [String: Int]] = [:]     // word before → word → times

        static let shortest = 4                      // words shorter than this aren't worth finishing
    }
    /// (2026-11-13, you asked: Mississippi wasn't offered) Common English words beyond the vault's, as written
    /// (Resources/Words/en-complete.tsv: subtitles' commonest, names with their capital).
    struct Dictionary {
        var keys: [String] = []
        var spelling: [String: String] = [:]
        var count: [String: Int] = [:]
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
            made.spelling[key] = word; made.count[key] = n
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
            let made = Self.model(Self.notes(in: vault))
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

    /// The finish of the word the text ends in, or nil.
    func complete(_ before: String) -> Completion? {
        lock.lock(); defer { lock.unlock() }
        return Self.complete(before, in: model, dictionary: dictionary)
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
        for text in texts {
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

    /// The finish of the word `before` ends in. Ranked: written after the word before it in the vault, then seen in the
    /// vault, then how common it is in English; a vault word needs to be seen twice, an English one three letters typed.
    /// Nothing starts so (four letters typed or more): the likeliest word whose start is a letter off ("missisi" →
    /// Mississippi), shown whole. Nothing for under two letters typed, or a finish under two letters.
    static func complete(_ before: String, in model: Model, dictionary: Dictionary = Dictionary()) -> Completion? {
        let text = before.precomposedStringWithCanonicalMapping
        guard let last = text.last, last.isLetter || last.isNumber else { return nil }
        let all = words(String(text.suffix(200)))
        guard let typed = all.last, text.hasSuffix(typed), typed.count >= 2 else { return nil }
        let prefix = typed.lowercased(), previous = all.count > 1 ? all[all.count - 2].lowercased() : nil
        let follows = previous.flatMap { model.after[$0] } ?? [:]
        var best: (key: String, score: Double)?
        func consider(_ key: String, fuzzy: Bool) {
            guard key.count >= max(typed.count + (fuzzy ? 1 : 2), Model.shortest), key != prefix else { return }
            let paired = follows[key] ?? 0, seen = model.count[key] ?? 0, common = dictionary.count[key] ?? 0
            guard paired > 0 || seen >= 2 || (common > 0 && typed.count >= 3) else { return }
            if fuzzy && seen < 2 && common < 50 { return }
            let score = Double(paired) * 100 + Double(min(seen, 1000)) * 5 + log10(Double(common) + 1)
            if best == nil || score > best!.score { best = (key, score) }
        }
        func search(_ start: String, fuzzy: Bool) {
            for keys in [model.keys, dictionary.keys] {
                var low = 0, high = keys.count
                while low < high { let mid = (low + high) / 2; if keys[mid] < start { low = mid + 1 } else { high = mid } }
                var i = low
                while i < keys.count, i < low + 500, keys[i].hasPrefix(start) { consider(keys[i], fuzzy: fuzzy); i += 1 }
            }
        }
        search(prefix, fuzzy: false)
        if best == nil, typed.count >= 4, prefix.allSatisfy({ $0.isASCII }) {
            for start in Set(SageSpell.edits(prefix, letters: "abcdefghijklmnopqrstuvwxyz")) where start.count >= 3 { search(start, fuzzy: true) }
        }
        guard let key = best?.key else { return nil }
        var word = model.spelling[key].flatMap { $0 == key ? dictionary.spelling[key] : $0 } ?? dictionary.spelling[key] ?? key
        if typed.count >= 2 && typed == typed.uppercased() && typed != typed.lowercased() { word = word.uppercased() }   // typed in capitals
        else if typed.first?.isUppercase == true { word = word.prefix(1).uppercased() + word.dropFirst() }               // a sentence's first word
        let starts = word.lowercased().hasPrefix(prefix)
        let shown = starts ? String(word.dropFirst(typed.count)) : "  → " + word
        return Completion(word: word, replace: typed.utf16.count, shown: shown)
    }
}
