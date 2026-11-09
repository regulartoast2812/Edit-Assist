import Foundation

/// Sage's media tools (2026-11-09, ported from Vault Agent): the note logic, what the tools print, and the process runner.
/// Temp folders only, never your vault; nothing is downloaded.
extension Checks {
    static func sageMedia(_ check: Check) async throws {
        typealias M = SageMedia

        // Which links.
        let text = """
        ---
        source: https://www.youtube.com/watch?v=abc123
        ---
        See https://youtu.be/xyz, and https://www.instagram.com/reel/DAb/. Also https://m.facebook.com/watch?v=9.
        Article: https://example.com/youtube.com/story and https://notyoutube.com/v. Again https://youtu.be/xyz.
        Picture ![a](https://cdn.site.com/a/b%20c.JPG?w=200) and https://img.site.com/p.webp).
        """
        check(M.videoURLs(text) == ["https://www.youtube.com/watch?v=abc123", "https://youtu.be/xyz", "https://www.instagram.com/reel/DAb/", "https://m.facebook.com/watch?v=9"],
              "Fetch media takes the video sites' links (frontmatter too, subdomains, each once, the sentence's full stop left off), never an article")
        check(M.imageURLs(text) == ["https://cdn.site.com/a/b%20c.JPG?w=200", "https://img.site.com/p.webp"], "Picture links are found by their extension, a query allowed")
        check(M.label("https://www.tiktok.com/@a/video/1?token=secret") == "tiktok.com/@a/video/1", "A link is named by its site and path, never its query")

        // The note.
        let (front, body) = M.splitFrontmatter("---\ntitle: Pho\n---\nBody\n")
        check(front == "---\ntitle: Pho\n---\n" && body == "Body\n" && M.splitFrontmatter("No front\n---\n").frontmatter.isEmpty, "The frontmatter is split from the body")
        check(M.withBanner("---\ntitle: Pho\n---\n", "Pho 1.jpg") == "---\ntitle: Pho\nbanner: \"[[Pho 1.jpg]]\"\n---\n"
              && M.withBanner("", "a.jpg") == "---\nbanner: \"[[a.jpg]]\"\n---\n"
              && M.withBanner("---\nbanner:\ntitle: x\n---\n", "a.jpg") == "---\nbanner: \"[[a.jpg]]\"\ntitle: x\n---\n"
              && M.withBanner("---\nbanner: \"[[mine.png]]\"\n---\n", "a.jpg") == "---\nbanner: \"[[mine.png]]\"\n---\n",
              "The thumbnail becomes the banner only when the note has none: an empty banner is filled, yours stays")
        check(M.banner("---\nbanner: \"[[Pho 1.jpg]]\"\n---\nx") == "Pho 1.jpg" && M.banner("no banner") == nil, "The banner is read back from the frontmatter")
        check(M.embedding("Watch [the clip](https://youtu.be/xyz) or ![](https://youtu.be/xyz) or <https://youtu.be/xyz> or https://youtu.be/xyz.", url: "https://youtu.be/xyz", file: "Pho 1.mp4")
              == "Watch ![[Pho 1.mp4]] or ![[Pho 1.mp4]] or ![[Pho 1.mp4]] or ![[Pho 1.mp4]].",
              "A link to the video, however written, becomes its ![[embed]]")
        check(M.embedding("Two: https://youtu.be/xyzw and https://youtu.be/xyz/", url: "https://youtu.be/xyz", file: "a.mp4") == "![[a.mp4]]\n\nTwo: https://youtu.be/xyzw and https://youtu.be/xyz/",
              "A longer link that starts with the same address is left alone")
        check(M.embedding("Notes only\n", url: "https://youtu.be/q", file: "N 1.mp4") == "![[N 1.mp4]]\n\nNotes only\n"
              && M.embedding("![[N 1.mp4]]\n\nNotes\n", url: "https://youtu.be/q", file: "N 1.mp4") == "![[N 1.mp4]]\n\nNotes\n",
              "A source only in the frontmatter: the embed goes at the top of the body, once")
        check(M.embedding("[$1](https://a.com/x.png)", url: "https://a.com/x.png", file: "$1 \\ odd.png") == "![[$1 \\ odd.png]]", "A file name with $ or \\ is put in as it is")
        check(M.fileStem(note: "Pho: the \"best\"/bowl", position: 2) == "Pho- the -best--bowl 2" && M.fileStem(note: "  ", position: 1) == "video 1",
              "A video is named after its note, made safe for every system, and its link's place")
        check(M.isVideo("pho 1.MP4", stem: "Pho 1") && !M.isVideo("Pho 1.jpg", stem: "Pho 1") && !M.isVideo("Pho 12.mp4", stem: "Pho 1") && M.isThumbnail("Pho 1.jpg", stem: "Pho 1"),
              "A video and its thumbnail are known by Fetch media's name for them")
        check(M.embeds("![[a.mp4]] ![[b.png|300]] [[c]]") == ["a.mp4", "b.png"], "The files a note embeds are read, sizes aside")
        let media = M.mediaEmbeds("![[Pho 1.mp4]] ![[pic.png]] ![[talk.m4a|x]] ![[clip.mov#t=5]]")
        check(media.map(\.link) == ["Pho 1.mp4", "talk.m4a", "clip.mov"] && media[1].anchor == "![[talk.m4a|x]]", "Transcribe finds the video and sound the note embeds, as written")

        // The transcript.
        check(M.insertingTranscript("Intro\nhttps://youtu.be/xyz\nMore", anchor: "https://youtu.be/xyz", label: "youtu.be/xyz", transcript: "Hello there.")
              == "Intro\nhttps://youtu.be/xyz\n\n## Transcript\n\nHello there.\nMore", "The transcript goes right under its source")
        check(M.insertingTranscript("![[a.mp4]]\n\n## Transcript\n\nOld", anchor: "![[a.mp4]]", label: "a.mp4", transcript: "New") == nil,
              "A source that already has its transcript is left as it is")
        check(M.insertingTranscript("Body text\n\n", anchor: "https://x.com/a", label: "x.com/a", transcript: "Words") == "Body text\n\n## Transcript\n\nWords\n"
              && M.insertingTranscript("B\n\n## Transcript\n\nOne\n", anchor: "https://x.com/b", label: "x.com/b", transcript: "Two") == "B\n\n## Transcript\n\nOne\n\n### Transcript — x.com/b\n\nTwo\n"
              && M.insertingTranscript("B\n\n### Transcript — x.com/b\n\nTwo\n", anchor: "https://x.com/b", label: "x.com/b", transcript: "Three") == nil,
              "A source only in the frontmatter: the transcript goes at the end, under its own name when there's one already")

        // Files.
        check(M.attachmentFolder(setting: "Attachments", note: "Food/Pho.md") == "Attachments" && M.attachmentFolder(setting: nil, note: "Food/Pho.md") == ""
              && M.attachmentFolder(setting: "/", note: "Pho.md") == "" && M.attachmentFolder(setting: "./", note: "Food/Soup/Pho.md") == "Food/Soup"
              && M.attachmentFolder(setting: "./media", note: "Food/Pho.md") == "Food/media" && M.attachmentFolder(setting: "./media", note: "Pho.md") == "media"
              && M.attachmentFolder(setting: "/Files/", note: "Pho.md") == "Files",
              "Attachments go where app.json's attachmentFolderPath says, as Obsidian reads it")
        check(M.availableName("a.png", taken: []) == "a.png" && M.availableName("a.png", taken: ["A.png", "a 1.png"]) == "a 2.png", "A picture never goes over a file: a name is picked as Obsidian picks it")
        check(M.imageName("https://x.com/i/b%20c.JPG?w=1", contentType: "image/jpeg") == "b c.JPG" && M.imageName("https://x.com/render?id=1", contentType: "image/jpeg; q=1") == "render.jpg"
              && M.imageName("https://x.com/a:b", contentType: "image/svg+xml") == "a_b.svg",
              "A downloaded picture is named from its link, its type giving the extension when the link has none")
        let listed = ["Attachments/Pho 1.mp4", "Old/Pho 1.mp4", "Attachments/Bun 1.mp4"].map { Study.VaultItem(path: $0, folder: false) }
        check(M.embedName("Attachments/Bun 1.mp4", items: listed, from: "Food/Bun.md") == "Bun 1.mp4"
              && M.embedName("Attachments/Pho 1.mp4", items: listed, from: "Old/Pho.md") == "Attachments/Pho 1.mp4",
              "An embed is the file's name, or its path when the name would find another file")
        var fetched = M.Fetched()
        fetched.videos = [("https://youtu.be/xyz", "Pho 1.mp4")]
        fetched.thumbnails = ["Pho 1.jpg", "Pho 2.jpg"]
        fetched.images = [("https://a.com/p.png", "p.png"), ("https://a.com/gone.png", "gone.png")]
        check(fetched.applied(to: "---\ntitle: Pho\n---\nhttps://youtu.be/xyz and ![](https://a.com/p.png)\n")
              == "---\ntitle: Pho\nbanner: \"[[Pho 1.jpg]]\"\n---\n![[Pho 1.mp4]] and ![[p.png]]\n",
              "What was fetched goes into the note as it reads when written: the first thumbnail as banner, each link an embed")

        // What the tools print.
        check(M.ytDlpLine("[download]  45.3% of  218.53KiB at  1.10MiB/s ETA 00:05") == .progress(45.3, "45.3% of 218.53KiB at 1.10MiB/s ETA 00:05")
              && M.ytDlpLine("[download] 100% of  302.04KiB in 00:00:00 at 2.55MiB/s") == .step("100% of 302.04KiB in 00:00:00 at 2.55MiB/s")
              && M.ytDlpLine("[download] Destination: /v/Attachments/Zoo 1.f395.mp4") == .destination("/v/Attachments/Zoo 1.f395.mp4")
              && M.ytDlpLine("[ExtractAudio] Destination: /t/abc.m4a") == .destination("/t/abc.m4a")
              && M.ytDlpLine("[Merger] Merging formats into \"Zoo 1.mp4\"") == .step("Merging formats into \"Zoo 1.mp4\"")
              && M.ytDlpLine("ERROR: [youtube] aaaaaaaaaaa: This video is unavailable") == .error("This video is unavailable")
              && M.ytDlpLine("ERROR: Unable to download webpage") == .error("Unable to download webpage")
              && M.ytDlpLine("WARNING: Your yt-dlp version (2026.07.04) is older than 90 days!") == .noise
              && M.ytDlpLine("         Run \"yt-dlp --update\" or \"yt-dlp -U\" to update.") == .noise
              && M.ytDlpLine("[info] Video Thumbnail 44 does not exist") == .noise,
              "yt-dlp's lines are read: progress, files, steps and errors shown; warnings and its own chatter not")
        let instagram = ["WARNING: [Instagram] DAb: Instagram API is not granting access",
                         "ERROR: [Instagram] DAb: Instagram sent an empty media response. Check if this post is accessible in your browser without being logged-in. If it is not, then use --cookies-from-browser or --cookies for the authentication. See  https://github.com/yt-dlp/yt-dlp/wiki/FAQ for how to manually pass cookies."]
        check(M.wantsCookies(instagram) && !M.wantsCookies(["ERROR: [youtube] a: This video is unavailable"]), "A login gate is tried again with a browser's cookies; a missing video is not")
        let cut = M.failure(instagram) ?? ""
        check(cut.hasPrefix("Instagram sent an empty media response. Check if") && cut.hasSuffix("authentication.") && cut.count <= 201
              && M.failure(["[youtube] x: Downloading webpage", "ERROR: [youtube] x: Private video"]) == "Private video"
              && M.failure(["something went sideways"]) == "something went sideways" && M.failure([]) == nil
              && M.failure(["ERROR: [youtube] x: The page needs to be reloaded.. The page needs to be reloaded."]) == "The page needs to be reloaded.",
              "Why yt-dlp failed is its last error, cut after a sentence")
        check(M.cookieBrowsers(defaultBrowser: "com.brave.Browser") == ["brave", "chrome", "opera", "firefox", "safari"]
              && M.cookieBrowsers(defaultBrowser: "com.apple.Safari") == ["safari", "chrome", "brave", "opera", "firefox"]
              && M.cookieBrowsers(defaultBrowser: nil) == ["chrome", "brave", "opera", "firefox", "safari"]
              && M.cookieBrowsers(defaultBrowser: "com.google.Chrome", installed: { ["chrome", "safari"].contains($0) }) == ["chrome", "safari"],
              "Your default browser's cookies are tried first, then Vault Agent's order, only browsers this Mac has")
        check(M.shellPath("yt-dlp not found\n") == nil && M.shellPath("Welcome!\n/opt/homebrew/bin/yt-dlp\n") == "/opt/homebrew/bin/yt-dlp", "Only a path counts from the login shell's which")
        check(M.pythonVersion("Python 3.11.9").map { $0.major * 100 + $0.minor } == 311 && M.pythonVersion("nope") == nil
              && M.suitsWhisper((3, 12)) && !M.suitsWhisper((3, 9)) && !M.suitsWhisper((3, 13)),
              "WhisperX is installed with a Python 3.10 to 3.12; macOS's 3.9 isn't used")
        check(M.installLine("Collecting whisperx") == "Collecting whisperx" && M.installLine("  Using cached torch-2.5.1.whl (63 MB)") == nil
              && M.installLine("Successfully installed a-1 b-2 c-3 d-4 e-5") == "Successfully installed 5 packages" && M.installLine("Requirement already satisfied: x") == nil,
              "pip's useful lines are shown, long lists counted")
        check(M.whisperLine(">>Performing transcription...") == "Performing transcription..." && M.whisperLine("Progress: 45.00%...") == "Progress: 45.00%..."
              && M.whisperLine("model.bin:  45%|████▌     | 220M/484M [00:10<00:12, 21.0MB/s]") == "model.bin: 45% 220M/484M [00:10<00:12, 21.0MB/s]"
              && M.whisperLine("/x/site-packages/pyannote/audio/core/io.py:43: UserWarning: torchaudio._backend is deprecated") == nil
              && M.whisperLine("RuntimeError: ffmpeg was not found") == "RuntimeError: ffmpeg was not found",
              "WhisperX's steps, progress and errors are shown; library warnings not")
        check(M.whisperFailure(["Lightning upgraded", "ValueError: invalid compute type", "done"]) == "ValueError: invalid compute type", "Why WhisperX failed is its last error-like line")
        check(M.stillWorking(42) == "Still working: 42 s so far…" && M.stillWorking(100.4) == "Still working: 1 min 40 s so far…", "A quiet tool is said to be still working, with how long")
        var gate = M.LineGate()
        let t0 = Date(timeIntervalSince1970: 0)
        let passed = [gate.pass("1%", progress: true, now: t0), gate.pass("2%", progress: true, now: t0 + 1), gate.pass("Merging", progress: false, now: t0 + 1.2),
                      gate.pass("Merging", progress: false, now: t0 + 1.3), gate.pass("3%", progress: true, now: t0 + 2.1), gate.pass("100%", progress: true, done: true, now: t0 + 2.2)]
        check(passed == ["1%", nil, "Merging", nil, "3%", "100%"], "Progress reaches the screen at most every two seconds, and its end; steps always, never twice in a row")

        // On a temp vault: the note's place, a video already there, nothing to transcribe. No tool is run.
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("sage-media-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: vault) }
        let keep = vault.appendingPathComponent(".kept", isDirectory: true)
        func put(_ path: String, _ text: String) throws {
            let file = vault.appendingPathComponent(path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }
        try put(".obsidian/app.json", #"{"attachmentFolderPath":"./media"}"#)
        try put("Food/Pho.md", "---\r\nsource: https://youtu.be/xyz\r\n---\r\nA bowl.\r\n")
        try put("Food/media/Pho 1.mp4", "mp4")
        try put("Food/Plain.md", "Nothing here.\n")
        let place = try M.Place(note: vault.appendingPathComponent("Food/Pho.md"), vault: vault)
        check(place.path == "Food/Pho.md" && place.name == "Pho" && place.attachmentFolder == "Food/media" && place.attachmentPath("x.png") == "Food/media/x.png",
              "A note's place: its path, its name and its attachments folder from app.json")
        check((try? M.Place(note: fm.temporaryDirectory.appendingPathComponent("elsewhere.md"), vault: vault)) == nil, "A note outside the vault is refused")
        let said = Collected()
        let fetchedReport = try await M.fetch(note: vault.appendingPathComponent("Food/Pho.md"), vault: vault, keep: keep) { said.add($0) }
        let pho = try Data(contentsOf: vault.appendingPathComponent("Food/Pho.md"))
        check(String(decoding: pho, as: UTF8.self) == "---\r\nsource: https://youtu.be/xyz\r\n---\r\n![[Pho 1.mp4]]\r\n\r\nA bowl.\r\n"
              && fetchedReport.changed == ["Food/Pho.md"] && fetchedReport.lines == ["Added to the note: [[Pho 1.mp4]]"]
              && said.lines.contains("Using [[Pho 1.mp4]], already in the vault.") && (try? fm.contentsOfDirectory(atPath: keep.path))?.count == 1,
              "Fetch media uses a video already in the attachments (no yt-dlp), embeds it, keeps the note's CRLF lines and copies it first")
        let again = try await M.fetch(note: vault.appendingPathComponent("Food/Pho.md"), vault: vault, keep: keep) { _ in }
        check(again.changed.isEmpty && again.lines == ["No new supported media URLs were found in the note."], "Fetching again changes nothing")
        let none = try await M.transcribe(note: vault.appendingPathComponent("Food/Plain.md"), vault: vault, keep: keep) { _ in }
        check(none.lines == ["No supported social links or localized video embeds found in this note."] && none.changed.isEmpty
              && (try? String(contentsOf: vault.appendingPathComponent("Food/Plain.md"), encoding: .utf8)) == "Nothing here.\n",
              "Transcribe with nothing to transcribe says so and leaves the note alone")

        // The process runner: lines streamed, the status, and cancelling stops the process.
        let lines = Collected()
        let echoed = try await M.Tools.run("/bin/sh", ["-c", "printf 'one\\ntwo\\rthree\\n'; echo err >&2; exit 3"]) { lines.add($0) }
        check(echoed.status == 3 && Set(echoed.lines) == ["one", "two", "three", "err"] && Set(lines.lines) == ["one", "two", "three", "err"],
              "A tool's lines (stdout and stderr, \\r too) are streamed as it prints them, with its exit status")
        let started = Date()
        let sleeper = Task { try await M.Tools.run("/bin/sleep", ["30"]) }
        try await Task.sleep(nanoseconds: 300_000_000)
        sleeper.cancel()
        let stopped: Bool
        do { _ = try await sleeper.value; stopped = false } catch is CancellationError { stopped = true }
        check(stopped && Date().timeIntervalSince(started) < 5, "Cancelling the task stops the tool")
        let timed = try await M.Tools.run("/bin/sleep", ["30"], timeout: 0.3)
        check(timed.status != 0 && Date().timeIntervalSince(started) < 8, "A tool that runs past its time is stopped")
        let echoWorks = await M.Tools.works("/bin/echo", ["x"]), missingWorks = await M.Tools.works("/nonexistent/yt-dlp", ["--version"])
        check(echoWorks && !missingWorks, "A tool counts only when it runs")
    }

    private final class Collected: @unchecked Sendable {
        private var kept: [String] = []
        private let lock = NSLock()
        func add(_ line: String) { lock.lock(); kept.append(line); lock.unlock() }
        var lines: [String] { lock.lock(); defer { lock.unlock() }; return kept }
    }
}
