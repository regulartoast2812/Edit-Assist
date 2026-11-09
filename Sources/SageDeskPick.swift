import Foundation

/// The desk's side of Pick for me and the mini player (2026-11-07, Windows-first in Creative Assist; brought back to the
/// Mac 2026-11-09). What Pick decides is in SagePick.swift; the player's page in SagePlayer.swift.
extension SageDesk {
    /// For checking Pick's page without a YouTube key or a brain call: a folder holding angles.json (the angles answer),
    /// videos.json (YouTube's videos answer) and scores.json (the scoring answer), such as Tests/Fixtures/Sage. Read only; set
    /// with the environment variable EDIT_ASSIST_SAGE_PICK_FIXTURE. Unset (always, for you), Pick asks YouTube and the brain.
    static let pickFixture: URL? = ProcessInfo.processInfo.environment["EDIT_ASSIST_SAGE_PICK_FIXTURE"].flatMap { path in
        var folder: ObjCBool = false
        return !path.isEmpty && FileManager.default.fileExists(atPath: path, isDirectory: &folder) && folder.boolValue ? URL(fileURLWithPath: path, isDirectory: true) : nil
    }

    var canPick: Bool { hasKey || Self.pickFixture != nil }

    // MARK: The mini player

    /// Plays the video in Sage's mini player; another video swaps it.
    func play(_ video: Study.Video) {
        guard Study.isVideoID(video.id) else { return }
        playing = video
    }

    func closePlayer() { if playing != nil { playing = nil } }

    // MARK: Pick for me

    /// Pick for me, as a curator (the rubric and its reasons: SagePick.swift): search angles from the brain, up to three searches
    /// merged and deduped with their details, the hard filters, every remaining video scored by the brain, then code keeps
    /// only those over the bar, one per channel and no two alike, at most five. Saving none is a fine outcome; `lastPick`
    /// holds what it saved and passed over, each with why.
    func pick(_ words: String) {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.key, fixture = Self.pickFixture
        guard !words.isEmpty, key != nil || fixture != nil, !picking, !searching else { return }
        picking = true; failure = nil; lastPick = nil; pickSteps = []; results = []; resultsFor = ""
        let topic = topic
        // With the fixture each step lingers a moment, so the live steps can be seen and checked.
        func step(_ text: String) async throws {
            pickSteps.append(text)
            if fixture != nil { try await Task.sleep(nanoseconds: 1_500_000_000) }
        }
        func answer(_ name: String) -> [String: Any]? { fixture.flatMap { try? Data(contentsOf: $0.appendingPathComponent(name)) }.flatMap(Study.json) }
        Task {
            defer { picking = false }
            do {
                // 1. Search angles (a failed or junk answer still leaves your own words to search).
                try await step(L("Thinking of search angles…"))
                var asked: [String: Any]?
                do { asked = fixture != nil ? answer("angles.json") : try await HelperBrain.ask(Study.anglesPrompt(words, topic: topic), schema: Study.anglesSchema) }
                catch { asked = nil }
                let angles = Study.angles(from: asked, words: words, topic: topic)

                // 2. The searches, merged, with each video's details.
                try await step(angles.searches.count == 1 ? L("Searching YouTube…") : L("Searching %@ angles…", angles.searches.count))
                let found: [Study.Video]
                if let fixture { found = Study.videos(in: (try? Data(contentsOf: fixture.appendingPathComponent("videos.json"))) ?? Data()) }
                else { found = try await videos(searching: angles.searches, key: key ?? "") }
                try await step(L("Looking at %@ videos…", found.count))

                // 3. The hard filters, then the brain's marks for every video left.
                var (kept, dropped) = Study.screen(found, topic: topic, words: words, saved: Set(savedHere.map(\.id)), written: sources, wantsShort: angles.wantsShort)
                let scoring = Array(kept.prefix(Study.Rubric.mostScored))
                dropped += kept.dropFirst(Study.Rubric.mostScored).map {
                    Study.Passed(video: $0, reason: Study.Says("Not scored: Sage looks closely at %@ at most", [.plain(String(Study.Rubric.mostScored))]))
                }
                // What you already have here (saved, or written into a note), so a pick never repeats what it covers.
                var have: [Study.Video] = [], seen: Set<String> = []
                for video in savedHere.compactMap(\.video) + found.filter({ sources.contains($0.url.absoluteString) }) where seen.insert(video.id).inserted { have.append(video) }
                var marks: [String: Study.Marks] = [:]
                if !scoring.isEmpty {
                    try await step(scoring.count == 1 ? L("Scoring 1 video…") : L("Scoring %@ videos…", scoring.count))
                    let scored = fixture != nil ? answer("scores.json")
                        : try await HelperBrain.ask(Study.scorePrompt(words, topic: topic, videos: scoring, have: have), schema: Study.scoreSchema, timeout: 300)
                    marks = Study.marks(from: scored, videos: scoring, have: have.map(\.id))
                }

                // 4. The choice: only what clears the bar is saved, best on top.
                let outcome = Study.choose(ask: words, searches: angles.searches, lookedAt: found, candidates: scoring, screened: dropped, marks: marks,
                                           timely: angles.timely, today: Date(), have: have)
                for chosen in outcome.picked.reversed() { save(chosen.video, why: chosen.why, in: topic.id) }
                pickSteps.append(L("Saved %@ of %@ looked at", outcome.picked.count, outcome.lookedAt))
                if self.topic.id == topic.id { lastPick = outcome }
            } catch is CancellationError {
            } catch { failure = describe(error) }
        }
    }

    /// Up to three searches (100 units each), merged in turn so each angle's best come first, then their details (1 unit per 50).
    private func videos(searching searches: [String], key: String) async throws -> [Study.Video] {
        var lists: [[String]] = []
        for search in searches.prefix(3) {
            // The day's searches running out after the first: go on with what was found.
            do { lists.append(Study.ids(inSearch: try await fetch(Study.searchURL(search, key: key, count: 20)))) }
            catch where !lists.isEmpty { break }
        }
        let ids = Study.merged(lists)
        var videos: [Study.Video] = []
        for start in stride(from: 0, to: ids.count, by: 50) {
            videos += Study.videos(in: try await fetch(Study.videosURL(Array(ids[start ..< min(start + 50, ids.count)]), key: key)))
        }
        return ids.compactMap { id in videos.first { $0.id == id } }
    }

    /// Closes Pick's outcome (Find shows search results again).
    func clearPick() { lastPick = nil; pickSteps = [] }
}
