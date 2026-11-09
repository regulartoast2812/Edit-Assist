import Foundation

// "Pick for me" as a curator (2026-11-06, Windows-first in Creative Assist's SagePick.cs; brought back to the Mac 2026-11-09).
// Foundation only, like `Study`.
//
// The old pick ran one search, showed the brain ~24 results and asked for "at most 5, best first": it nearly always saved
// five. Now Sage works like a curator:
//   1. Angles: one no-tools brain call turns your words and the topic into up to 2 more search angles (3 searches at most:
//      each costs 100 of the key's 10,000 daily units). Their results are merged, deduped and their details fetched.
//   2. Screen (code, before the brain): Shorts and very short videos, what you already saved or wrote, reuploads/duplicates
//      (same title), and titles that are music, reactions or compilations (mukbangs and eating shows for recipes) are dropped.
//   3. Score (brain, no tools, strict schema): every remaining video is marked 0-5 on four parts of a rubric, with a reason
//      and a reject reason when it fails.
//   4. Choose (code): the final score is the weighted rubric plus small signals (like/view ratio, views against the other
//      results, recency when the topic moves fast); only those over the bar are kept, one per channel and no two covering the
//      same thing, at most five. Saving none is a fine answer: the outcome says why.
extension Study {
    // MARK: The rubric (every weight and bar in one place)

    /// How Sage judges a video. The four parts are marked 0-5 by the brain; code turns them into a score out of 100.
    enum Rubric {
        /// Does it answer exactly what was asked (not the general subject)? Weighs most: a great video on the wrong thing is useless.
        static let relevance = 0.40
        /// Does it really teach or show something (method, reasoning, worked example), with depth?
        static let substance = 0.25
        /// Is the source someone who knows (a practitioner, an expert, a trusted channel), not a content farm?
        static let credibility = 0.20
        /// Is the time well spent: information per minute, no long intros, padding or sponsor talk?
        static let density = 0.15

        /// The bar: a video must score at least this (out of 100). All 3s ("fine") is 60 and does not pass; 4,4,3,3 is 73 and does.
        static let bar = 70.0
        /// Below this relevance (0-5) a video is off the ask, whatever else it does well.
        static let minRelevance = 3
        /// The most Sage saves at once.
        static let most = 5
        /// The most videos the brain scores in one call (the prompt stays a sane size); the rest are passed over as unscored.
        static let mostScored = 40
        /// Shorter than this (seconds) is a Short or a teaser, unless the ask clearly wants short videos.
        static let minSeconds = 120

        /// Small signals on top of the rubric, in points out of 100: each is at most this much either way.
        static let likesSignal = 3.0, viewsSignal = 3.0, recencySignal = 4.0
    }

    /// Words for the screen (a reason, why nothing was saved): an English template with %@ slots and what goes in them, so
    /// the page can show it in your language (`text(L)`) and checks read it in English. A verbatim part (a title, a channel,
    /// the brain's own words) is put in as it is.
    struct Says: Equatable {
        var template: String
        var values: [Says] = []
        var verbatim = false

        init(_ template: String, _ values: [Says] = []) { self.template = template; self.values = values }
        static func plain(_ text: String) -> Says { var says = Says(text); says.verbatim = true; return says }

        func text(_ translate: (String) -> String = { $0 }) -> String {
            if verbatim { return template }
            let pieces = translate(template).components(separatedBy: "%@")
            var text = pieces[0]
            for (index, piece) in pieces.dropFirst().enumerated() { text += (index < values.count ? values[index].text(translate) : "%@") + piece }
            return text
        }

        var english: String { text() }
    }

    // MARK: 1. Search angles (one brain call)

    struct Angles: Equatable {
        var searches: [String]
        var wantsShort: Bool
        var timely: Bool
    }

    private static func strict(_ properties: [String: Any]) -> [String: Any] {
        ["type": "object", "additionalProperties": false, "required": properties.keys.sorted(), "properties": properties]
    }

    static var anglesSchema: [String: Any] {
        strict(["angles": ["type": "array", "items": ["type": "string"]], "short": ["type": "boolean"], "timely": ["type": "boolean"]])
    }

    static func anglesPrompt(_ words: String, topic: Topic) -> String {
        "I want to find YouTube videos worth learning from. My topic is \"\(topic.name)\""
            + (topic.kind == .recipes ? " (recipes: I want real recipes I can cook from)" : "") + " and I asked for: \"\(words.trimmingCharacters(in: .whitespacesAndNewlines))\".\n"
            + "Give at most 2 extra YouTube search phrases in `angles` that would find the best videos for exactly what I asked from different "
            + "angles (e.g. a tutorial phrasing, an expert's term for it, a deeper or more specific take), 2-8 words each, not repeating my own "
            + "words. Set `short` true only if I clearly want short videos (a quick tip, a Short, under a minute); otherwise false. Set `timely` "
            + "true if what I asked changes fast so newer videos matter (software versions, news, prices, current tools); otherwise false."
    }

    /// Text as its words (letters and digits), lowercased.
    static func wordList(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    /// The searches to run: your own words first (as the topic searches them), then the brain's angles that differ from them,
    /// at most three in all. A junk answer still leaves your own search.
    static func angles(from answer: [String: Any]?, words asked: String, topic: Topic) -> Angles {
        var searches = [search(asked, in: topic)]
        let key = { (text: String) in wordList(text).joined(separator: " ") }
        for angle in answer?["angles"] as? [Any] ?? [] {
            guard let raw = (angle as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count > 1, raw.count <= 120 else { continue }
            let phrase = search(raw, in: topic)
            if searches.contains(where: { key($0) == key(phrase) }) { continue }
            searches.append(phrase)
            if searches.count == 3 { break }
        }
        return Angles(searches: searches, wantsShort: isTrue(answer?["short"]), timely: isTrue(answer?["timely"]))
    }

    /// A JSON true (not a number or text that looks like one).
    private static func isTrue(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }

    /// The searches' ids merged: taken in turn from each angle (so each one's best come first), each id once.
    static func merged(_ angles: [[String]]) -> [String] {
        var merged: [String] = [], seen: Set<String> = []
        var rank = 0
        while angles.contains(where: { rank < $0.count }) {
            for ids in angles where rank < ids.count && seen.insert(ids[rank]).inserted { merged.append(ids[rank]) }
            rank += 1
        }
        return merged
    }

    // MARK: 2. Screening in code

    /// A video Sage looked at and passed over, with why.
    struct Passed: Equatable {
        var video: Video
        var reason: Says
        var score: Double?
    }

    /// Title words that mark music, reactions and compilations (not something to learn from), unless your ask uses them.
    static let notLessons = ["official music video", "music video", "official video", "official audio", "lyric video", "lyrics", "karaoke",
                             "reaction", "reacts", "react to", "reacting", "compilation", "funny moments", "best moments", "tiktok", "meme", "#shorts"]
    /// The recipe rubric's title rules: eating, not cooking.
    static let notRecipesTitles = ["mukbang", "eating show", "asmr eating", "eating challenge", "food challenge", "taste test", "reaction", "reacts",
                                   "compilation", "#shorts", "music video", "lyrics"]

    private static func replacing(_ pattern: String, in text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
    }

    /// A title as words, for telling reuploads apart: case, marks and tags like (Official), [4K], (reupload) aside.
    static func titleKey(_ title: String) -> String {
        let text = replacing(#"#\w+"#, in: replacing(#"[\(\[][^\)\]]{0,30}[\)\]]"#, in: title.lowercased()))
        return wordList(text).filter { !["reupload", "re", "upload", "full", "hd", "4k"].contains($0) }.joined(separator: " ")
    }

    /// A clock ("1:02:03", "9:00") as seconds; 0 when unknown.
    static func seconds(_ clock: String) -> Int {
        var total = 0
        for part in clock.split(separator: ":", omittingEmptySubsequences: false) {
            guard let number = Int(part) else { return 0 }
            total = total * 60 + number
        }
        return total
    }

    private static func unhashed(_ word: String) -> String { word.hasPrefix("#") ? String(word.dropFirst()) : word }

    /// The hard filters, before the brain sees anything: Shorts and very short videos (unless the ask wants short), what is
    /// already saved here or written into your notes, reuploads (the same title again: the one with more views stays), and
    /// titles that are music, reactions or compilations (for recipes: mukbangs and eating shows too).
    static func screen(_ found: [Video], topic: Topic, words: String, saved: Set<String>, written: Set<String>, wantsShort: Bool) -> (kept: [Video], dropped: [Passed]) {
        var kept: [Video] = [], dropped: [Passed] = []
        let asked = (words + " " + topic.name).lowercased()
        let rules = (topic.kind == .recipes ? notRecipesTitles : notLessons).filter { !asked.contains(unhashed($0)) }
        // The most-viewed copy of each title is the one considered; others are reuploads.
        var best: [String: Video] = [:]
        for video in found {
            let key = titleKey(video.title)
            guard !key.isEmpty else { continue }
            if let held = best[key], (held.views ?? 0) >= (video.views ?? 0) { continue }
            best[key] = video
        }
        var ids: Set<String> = []
        for video in found {
            guard ids.insert(video.id).inserted else { continue }
            let title = video.title.lowercased()
            let length = seconds(video.duration)
            var reason: Says?
            if saved.contains(video.id) { reason = Says("Already in Saved") }
            else if written.contains(video.url.absoluteString) { reason = Says("Already in your notes") }
            else if let original = best[titleKey(video.title)], original.id != video.id {
                reason = Says("Same video as “%@” (%@): a reupload or duplicate", [.plain(original.title), .plain(original.channel)])
            } else if !wantsShort && (title.contains("#shorts") || (length > 0 && length < Rubric.minSeconds)) {
                reason = length > 0 ? Says("Too short (%@) to teach much", [.plain(video.duration)]) : Says("A Short")
            } else if let word = rules.first(where: title.contains) {
                reason = topic.kind == .recipes ? Says("Not a recipe to cook from (“%@”)", [.plain(unhashed(word))]) : Says("Not a lesson: looks like %@", [Says(kind(word))])
            }
            if let reason { dropped.append(Passed(video: video, reason: reason)) } else { kept.append(video) }
        }
        return (kept, dropped)
    }

    private static func kind(_ word: String) -> String {
        switch word {
        case "reaction", "reacts", "react to", "reacting": return "a reaction video"
        case "compilation", "funny moments", "best moments", "tiktok", "meme": return "a compilation"
        case "#shorts": return "a Short"
        default: return "music"
        }
    }

    // MARK: 3. Scoring (one brain call over every candidate)

    /// The brain's marks for one video (each 0-5), what it covers, and why it is worth it or not.
    struct Marks: Equatable {
        var relevance: Int, substance: Int, credibility: Int, density: Int
        var covers: String, sameAs: String, why: String, reject: String
    }

    static var scoreSchema: [String: Any] {
        let mark: [String: Any] = ["type": "integer"], text: [String: Any] = ["type": "string"]
        let item = strict(["id": text, "relevance": mark, "substance": mark, "credibility": mark, "density": mark, "covers": text, "same_as": text,
                           "why": text, "reject": text])
        return strict(["scores": ["type": "array", "items": item]])
    }

    /// The scoring question. `have` is what you already saved or wrote in the topic: not scored, but a video covering the same is named in `same_as`.
    static func scorePrompt(_ words: String, topic: Topic, videos: [Video], have: [Video] = []) -> String {
        let recipes = topic.kind == .recipes
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let ask = recipes ? "I'm looking for recipes to cook: \"\(words)\" (my topic \"\(topic.name)\")."
                          : "I'm researching \"\(topic.name)\" and asked for: \"\(words)\"."
        let rubric = recipes
            ? "- relevance: is it a recipe for exactly what I asked (the dish or ingredient), that I could cook from?\n"
                + "- substance: a real recipe with a method and amounts (in the video, its description or a linked recipe page); not a mukbang, taste test, vlog or 'what I eat in a day'.\n"
                + "- credibility: a cook who knows (a chef, a trusted recipe channel or site), not a content farm.\n"
                + "- density: gets to the cooking; no long intro, padding or sponsor talk.\n"
            : "- relevance: does it answer exactly what I asked, not just the general subject?\n"
                + "- substance: does it really teach or show it (method, reasoning, worked examples), with depth?\n"
                + "- credibility: is the source someone who knows (a practitioner, an expert, a trusted channel), not clickbait or a content farm?\n"
                + "- density: is it information-dense, without long intros, padding, hype or sponsor talk?\n"
        return ask + " Judge EVERY video below for whether it is worth saving to learn from. Be a strict curator: most search results are "
            + "not worth my time, and saving none is a fine answer. Mark each from 0 to 5 (5 = excellent, 3 = fine, 0 = not at all), using only "
            + "the title, channel, length, numbers and description given:\n" + rubric
            + "For each video give its exact id; `covers` as a short phrase of what it is about (e.g. \"speed ramps in Premiere\"); `same_as` as "
            + "the id of a better video below that covers the same thing, or \"\"; `why` as one short line on what it offers; and `reject` as one "
            + "short line on why it is not worth saving, or \"\" when it is.\n\nThe videos (id | title | channel | length | views | likes | "
            + "published | description):\n" + videos.map(scoreLine).joined(separator: "\n")
            + (have.isEmpty ? "" : "\n\nAlready in my Saved or my notes (don't score these; when a video above covers the same thing as one of these, "
                + "put this one's id in its `same_as`):\n" + have.prefix(40).map { "- id \($0.id) | \($0.title) | \($0.channel)" }.joined(separator: "\n"))
    }

    private static func scoreLine(_ v: Video) -> String {
        let about = String(v.description.prefix(280)).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        return "- id \(v.id) | \(v.title) | \(v.channel) | \(v.duration.isEmpty ? "?" : v.duration) | \(v.views.map(String.init) ?? "?") views | "
            + "\(v.likes.map(String.init) ?? "?") likes | \(v.published.isEmpty ? "?" : v.published) | \(about)"
    }

    /// The brain's marks by id: only for videos it was shown, once each, each mark clamped to 0-5 (numbers given as text read
    /// too); `same_as` only when it names another of them or one you already have.
    static func marks(from answer: [String: Any]?, videos: [Video], have: [String] = []) -> [String: Marks] {
        let ids = Set(videos.map(\.id)), known = ids.union(have)
        var marks: [String: Marks] = [:]
        for item in answer?["scores"] as? [Any] ?? [] {
            guard let o = item as? [String: Any], var id = (o["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            while id.hasPrefix("#") { id.removeFirst() }
            if id.hasPrefix("id ") { id = String(id.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard ids.contains(id), marks[id] == nil else { continue }
            let line = { (key: String) in (o[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            let same = line("same_as")
            marks[id] = Marks(relevance: mark(o["relevance"]), substance: mark(o["substance"]), credibility: mark(o["credibility"]), density: mark(o["density"]),
                              covers: line("covers"), sameAs: known.contains(same) && same != id ? same : "", why: line("why"), reject: line("reject"))
        }
        return marks
    }

    private static func mark(_ value: Any?) -> Int {
        var number = 0.0
        if let given = value as? NSNumber, CFGetTypeID(given) != CFBooleanGetTypeID() { number = given.doubleValue }
        else if let text = value as? String { number = Double(text.trimmingCharacters(in: .whitespaces)) ?? 0 }
        return Int(min(max((number.isFinite ? number : 0).rounded(.toNearestOrEven), 0), 5))
    }

    // MARK: 4. Choosing (code)

    /// The rubric as a score out of 100, from the weights above.
    static func rubricScore(_ m: Marks) -> Double {
        let raw = (Double(m.relevance) * Rubric.relevance + Double(m.substance) * Rubric.substance + Double(m.credibility) * Rubric.credibility
                   + Double(m.density) * Rubric.density) / 5 * 100
        return (raw * 10).rounded(.toNearestOrEven) / 10
    }

    private static func clamped(_ value: Double, _ low: Double, _ high: Double) -> Double { min(max(value, low), high) }

    /// The small signals on top of the rubric, in points: liked well for its views (a like/view ratio around 2-5% is usual),
    /// watched more than the other results (against the same channel's other results when it has some, else all of them),
    /// and, when the topic moves fast, how new it is. Each is a nudge of a few points, never enough to pass a weak video.
    static func signals(_ video: Video, among all: [Video], timely: Bool, today: Date) -> Double {
        var points = 0.0
        let views = video.views ?? 0
        if views > 500, let likes = video.likes {
            points += clamped((Double(likes) / Double(views) - 0.025) / 0.025, -1, 1) * Rubric.likesSignal
        }
        if views > 0 {
            let same = all.filter { $0.channel == video.channel && ($0.views ?? 0) > 0 }
            let others = (same.count >= 2 ? same : all.filter { ($0.views ?? 0) > 0 }).map { log10(Double($0.views ?? 1)) }.sorted()
            if others.count >= 2 { points += clamped((log10(Double(views)) - others[others.count / 2]) / 1.5, -1, 1) * Rubric.viewsSignal }
        }
        if timely, let published = day(video.published) {
            let years = today.timeIntervalSince(published) / 86_400 / 365
            points += years < 1 ? Rubric.recencySignal : years > 3 ? -Rubric.recencySignal : 0
        }
        return points
    }

    /// "2026-11-06" as that day's start where you are.
    static func day(_ text: String) -> Date? {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX"); format.dateFormat = "yyyy-MM-dd"
        return format.date(from: String(text.prefix(10)))
    }

    /// What Pick did: the ask, the searches, how many it looked at, what it saved (with why) and what it passed over (with why not).
    struct PickOutcome: Equatable, Identifiable {
        var id = UUID()
        var ask = ""
        var searches: [String] = []
        var lookedAt = 0
        var picked: [Chosen] = []
        var passedOver: [Passed] = []
        /// Why nothing was saved, when nothing was.
        var why: Says?
        var headline: String { "Saved \(picked.count) of \(lookedAt) looked at" }
    }

    struct Chosen: Equatable {
        var video: Video
        var score: Double
        var why: String
        var covers: String
    }

    /// The final choice: each scored video's score (rubric + signals); a brain reject, relevance under the minimum or a score
    /// under the bar passes it over; then, best first, at most one per channel and none covering what a better pick covers,
    /// at most five, and none covering what you already have (`have`: saved or written in the topic). Unscored videos are
    /// passed over. Zero picks is a fine outcome: `why` says what fell short.
    static func choose(ask: String, searches: [String], lookedAt: [Video], candidates: [Video], screened: [Passed], marks: [String: Marks],
                       timely: Bool, today: Date, have: [Video] = []) -> PickOutcome {
        var outcome = PickOutcome(ask: ask, searches: searches, lookedAt: lookedAt.count)
        var passed: [Passed] = []
        var scored: [(video: Video, marks: Marks, score: Double)] = []
        for video in candidates {
            guard let m = marks[video.id] else { passed.append(Passed(video: video, reason: Says("Sage didn't score it"))); continue }
            let score = clamped(rubricScore(m) + signals(video, among: lookedAt, timely: timely, today: today), 0, 100).rounded(.toNearestOrEven)
            let points = Says.plain(String(Int(score)))
            if !m.reject.isEmpty { passed.append(Passed(video: video, reason: .plain(m.reject), score: score)) }
            else if m.relevance < Rubric.minRelevance {
                passed.append(Passed(video: video, reason: m.why.isEmpty ? Says("Off what you asked for") : Says("Off the ask: %@", [.plain(m.why)]), score: score))
            } else if score < Rubric.bar {
                passed.append(Passed(video: video, reason: m.why.isEmpty ? Says("Below the bar (%@/100)", [points]) : Says("Below the bar (%@/100): %@", [points, .plain(m.why)]), score: score))
            } else { scored.append((video, m, score)) }
        }
        // Best first; equal scores keep the order YouTube gave.
        let ranked = scored.enumerated().sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }.map(\.element)
        for (video, m, score) in ranked {
            let sameChannel = outcome.picked.first { !$0.video.channel.isEmpty && $0.video.channel.caseInsensitiveCompare(video.channel) == .orderedSame }
            let sameThing = outcome.picked.first { m.sameAs == $0.video.id || marks[$0.video.id]?.sameAs == video.id || alike($0.covers, m.covers) }
            let already = m.sameAs.isEmpty ? nil : have.first { $0.id == m.sameAs }
            if let already { passed.append(Passed(video: video, reason: Says("Good, but covers the same as “%@”, which you already have", [.plain(already.title)]), score: score)) }
            else if let sameChannel { passed.append(Passed(video: video, reason: Says("Good, but one video per channel: “%@” ranked higher", [.plain(sameChannel.video.title)]), score: score)) }
            else if let sameThing { passed.append(Passed(video: video, reason: Says("Good, but covers the same as “%@”, which ranked higher", [.plain(sameThing.video.title)]), score: score)) }
            else if outcome.picked.count >= Rubric.most { passed.append(Passed(video: video, reason: Says("Good, but %@ better ones were saved", [.plain(String(Rubric.most))]), score: score)) }
            else { outcome.picked.append(Chosen(video: video, score: score, why: m.why, covers: m.covers)) }
        }
        // Passed over: the closest calls first (scored, highest first), then what the filters dropped.
        outcome.passedOver = passed.enumerated().sorted { ($0.element.score ?? -1) != ($1.element.score ?? -1) ? ($0.element.score ?? -1) > ($1.element.score ?? -1) : $0.offset < $1.offset }
            .map(\.element) + screened
        if outcome.picked.isEmpty {
            var nearest: Passed?
            for item in passed where item.score != nil && (nearest == nil || item.score! > nearest!.score!) { nearest = item }
            if lookedAt.isEmpty { outcome.why = Says("YouTube found nothing for these words. Try other words.") }
            else if candidates.isEmpty { outcome.why = Says("All %@ were filtered out (%@). Try other words.", [.plain(String(lookedAt.count)), mostly(screened)]) }
            else if let nearest, let score = nearest.score, score >= Rubric.bar {
                var but = nearest.reason
                but.template = lowerFirst(but.template.replacingOccurrences(of: "Good, but ", with: ""))
                outcome.why = Says("Nothing new worth saving. Best: “%@” at %@/100, but %@", [.plain(nearest.video.title), .plain(String(Int(score))), but])
            } else if let nearest, let score = nearest.score {
                outcome.why = Says("Nothing cleared the bar (%@/100). Closest: “%@” at %@: %@",
                                   [.plain(String(Int(Rubric.bar))), .plain(nearest.video.title), .plain(String(Int(score))), nearest.reason])
            } else { outcome.why = Says("Sage couldn't score these videos. Try again.") }
        }
        return outcome
    }

    private static func lowerFirst(_ text: String) -> String { text.isEmpty ? text : text.prefix(1).lowercased() + text.dropFirst() }

    /// The filters' most common reason, for "all were filtered out".
    private static func mostly(_ screened: [Passed]) -> Says {
        var counts: [(head: String, count: Int)] = []
        for item in screened {
            let head = item.reason.template.components(separatedBy: CharacterSet(charactersIn: "(:“")).first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            if let index = counts.firstIndex(where: { $0.head == head }) { counts[index].count += 1 } else { counts.append((head, 1)) }
        }
        var top: (head: String, count: Int)?
        for entry in counts where top == nil || entry.count > top!.count { top = entry }
        return top.map { Says("mostly: %@", [Says($0.head)]) } ?? .plain("")
    }

    /// Two "covers" phrases about the same thing: most of their words shared (short words aside).
    static func alike(_ a: String, _ b: String) -> Bool {
        let bag = { (text: String) in Set(wordList(text).filter { $0.count > 2 && !["the", "and", "for", "how", "with"].contains($0) }) }
        let x = bag(a), y = bag(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return Double(x.intersection(y).count) / Double(x.union(y).count) >= 0.6
    }
}
