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

    private let lock = NSLock()
    private var model = Model()
    private var vault: URL?
    private var built = Date.distantPast
    private var building = false

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

    /// The rest of the word the text ends in, or nil.
    func complete(_ before: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return Self.complete(before, in: model)
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

    /// The rest of the word `before` ends in: the word the vault writes most after the one before it, else the commonest
    /// (seen twice at least). Nothing for under two letters typed, or a finish under two letters.
    static func complete(_ before: String, in model: Model) -> String? {
        let text = before.precomposedStringWithCanonicalMapping
        guard let last = text.last, last.isLetter || last.isNumber else { return nil }
        let all = words(String(text.suffix(200)))
        guard let typed = all.last, text.hasSuffix(typed), typed.count >= 2 else { return nil }
        let prefix = typed.lowercased(), previous = all.count > 1 ? all[all.count - 2].lowercased() : nil
        let follows = previous.flatMap { model.after[$0] } ?? [:]
        var low = 0, high = model.keys.count
        while low < high { let mid = (low + high) / 2; if model.keys[mid] < prefix { low = mid + 1 } else { high = mid } }
        var best: (word: String, score: Int)?
        var i = low
        while i < model.keys.count, i < low + 500, model.keys[i].hasPrefix(prefix) {
            let key = model.keys[i]; i += 1
            guard key.count >= max(typed.count + 2, Model.shortest) else { continue }
            let paired = follows[key] ?? 0, seen = model.count[key] ?? 0
            guard paired > 0 || seen >= 2 else { continue }
            let score = paired * 1_000_000 + seen
            if best == nil || score > best!.score { best = (key, score) }
        }
        guard let word = best.map({ model.spelling[$0.word] ?? $0.word }) else { return nil }
        let rest = String(word.dropFirst(typed.count))
        // Typed in capitals (two or more): finished in capitals.
        return typed.count >= 2 && typed == typed.uppercased() && typed != typed.lowercased() ? rest.uppercased() : rest
    }
}
