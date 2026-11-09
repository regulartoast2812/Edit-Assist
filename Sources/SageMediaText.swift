import Foundation

/// Sage's media tools, the part without processes or the network (2026-11-09, ported from the Vault Agent plugin's
/// view.ts): which links are videos or pictures, how a note changes when one is fetched or transcribed, and what yt-dlp,
/// pip and WhisperX print. Foundation only, so the checks compile it as it is (Tests/SageMediaChecks.swift).
extension SageMedia {
    // MARK: Which links

    /// The video sites Fetch media and Transcribe take (Vault Agent's list). yt-dlp reads many more, but an ordinary
    /// article link in a note must never be taken for a video.
    static let videoSites = ["youtube.com", "youtu.be", "facebook.com", "fb.watch", "fb.me", "instagram.com", "instagr.am",
                             "tiktok.com", "x.com", "twitter.com", "reddit.com", "v.redd.it", "twitch.tv", "vimeo.com",
                             "dailymotion.com", "streamable.com"]

    /// The video links in the note, frontmatter included (a processed note often keeps its source there), each once, in
    /// order, without the punctuation that ends a sentence.
    static func videoURLs(_ text: String) -> [String] {
        var found: [String] = []
        for raw in allMatches(#"https?://[^\s<>()\[\]{}"']+"#, in: text, options: [.caseInsensitive]) {
            let url = raw.replacingOccurrences(of: #"[.,!?;:]+$"#, with: "", options: .regularExpression)
            guard let host = URL(string: url)?.host?.lowercased() else { continue }
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if videoSites.contains(where: { bare == $0 || bare.hasSuffix("." + $0) }), !found.contains(url) { found.append(url) }
        }
        return found
    }

    /// The links to pictures (a picture file's extension, a query allowed), each once, in order.
    static func imageURLs(_ text: String) -> [String] {
        var found: [String] = []
        for url in allMatches(#"https?://[^\s)>"']+?\.(?:png|jpe?g|gif|webp|bmp|svg|avif)(?:\?[^\s)>"']*)?"#, in: text, options: [.caseInsensitive])
        where !found.contains(url) { found.append(url) }
        return found
    }

    static func allMatches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    /// A short label for a link in what Sage says: the site and the start of its path, never the query (it can hold tokens).
    static func label(_ url: String) -> String {
        guard let parsed = URL(string: url), let host = parsed.host else { return "video" }
        return (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host) + String(parsed.path.prefix(80))
    }

    // MARK: The note

    /// The note's YAML frontmatter (with its closing line) and the rest. Frontmatter is only ever added to, never rewritten.
    static func splitFrontmatter(_ text: String) -> (frontmatter: String, body: String) {
        guard let range = text.range(of: #"^---\r?\n[\s\S]*?\n---\r?\n?"#, options: .regularExpression), range.lowerBound == text.startIndex else { return ("", text) }
        return (String(text[range]), String(text[range.upperBound...]))
    }

    /// The banner set to the picture only when the note has none (an empty `banner:` counts as none); a banner you chose stays.
    static func withBanner(_ frontmatter: String, _ picture: String) -> String {
        let banner = "banner: \"[[\(picture)]]\""
        if frontmatter.isEmpty { return "---\n\(banner)\n---\n" }
        if let empty = frontmatter.range(of: #"(?im)^banner[ \t]*:[ \t]*$"#, options: .regularExpression) { return frontmatter.replacingCharacters(in: empty, with: banner) }
        if frontmatter.range(of: #"(?im)^banner[ \t]*:"#, options: .regularExpression) != nil { return frontmatter }
        guard let end = frontmatter.range(of: #"\n---\r?\n?\z"#, options: .regularExpression) else { return frontmatter }
        return frontmatter.replacingCharacters(in: end, with: "\n\(banner)\n---\n")
    }

    /// The picture the note's banner shows, if it is a [[link]].
    static func banner(_ text: String) -> String? {
        Study.firstMatch(#"^banner:\s*["']?\[\[([^\]]+)\]\]["']?\s*$"#, in: splitFrontmatter(text).frontmatter, options: [.anchorsMatchLines, .caseInsensitive])?[1]
    }

    /// The files the note embeds (![[name]], alias aside).
    static func embeds(_ text: String) -> Set<String> {
        Set(allMatches(#"!\[\[[^\]|]+(?:\|[^\]]*)?\]\]"#, in: text).map { String($0.dropFirst(3).dropLast(2).split(separator: "|", omittingEmptySubsequences: false)[0]).trimmingCharacters(in: .whitespaces) })
    }

    /// The link put in place of a URL: a Markdown link or picture to it, an <autolink> and the bare URL all become
    /// ![[file]]. When the body never shows the URL (it's only in the frontmatter), the embed goes at the top of the body,
    /// unless the body already embeds that file. The bare URL is taken only where it ends, so a longer link that starts
    /// with it is left alone.
    static func embedding(_ body: String, url: String, file: String) -> String {
        let embed = "![[\(file)]]"
        let escaped = NSRegularExpression.escapedPattern(for: url)
        let template = NSRegularExpression.escapedTemplate(for: embed)
        var result = body.replacingOccurrences(of: #"!?\[[^\]]*\]\("# + escaped + #"\)"#, with: template, options: .regularExpression)
        result = result.replacingOccurrences(of: "<" + escaped + ">", with: template, options: .regularExpression)
        result = result.replacingOccurrences(of: escaped + #"(?![A-Za-z0-9/_\-%=&?#~+@])(?!\.[A-Za-z0-9])"#, with: template, options: .regularExpression)
        if result == body && !embeds(body).contains(file) { result = embed + "\n\n" + body }
        return result
    }

    /// What Fetch media names a video and its thumbnail: the note's name made safe for every system, then the link's place.
    static func fileStem(note: String, position: Int) -> String {
        let safe = note.replacingOccurrences(of: #"[<>:"/\\|?*\x{0000}-\x{001F}]"#, with: "-", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return "\(safe.isEmpty ? "video" : safe) \(position)"
    }

    static let videoTypes = ["mp4", "m4v", "mkv", "webm", "mov"]
    static let mediaTypes = ["mp4", "m4v", "mov", "mkv", "webm", "avi", "mp3", "m4a", "wav", "ogg", "opus", "flac"]

    /// A file with that stem and a video's extension ("Pho 1.mp4" for "Pho 1"), case aside.
    static func isVideo(_ name: String, stem: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return videoTypes.contains(ext) && (name as NSString).deletingPathExtension.caseInsensitiveCompare(stem) == .orderedSame
    }

    /// The thumbnail yt-dlp wrote for that stem.
    static func isThumbnail(_ name: String, stem: String) -> Bool {
        ["jpg", "jpeg", "png", "webp"].contains((name as NSString).pathExtension.lowercased()) && (name as NSString).deletingPathExtension.caseInsensitiveCompare(stem) == .orderedSame
    }

    /// The video and sound files the note embeds, with the embed as written (a transcript goes below it).
    static func mediaEmbeds(_ text: String) -> [(link: String, anchor: String)] {
        var found: [(String, String)] = []
        for anchor in allMatches(#"!\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]*)?\]\]"#, in: text) {
            guard let link = Study.firstMatch(#"^!\[\[([^\]|#]+)"#, in: anchor)?[1].trimmingCharacters(in: .whitespaces),
                  mediaTypes.contains((link as NSString).pathExtension.lowercased()) else { continue }
            found.append((link, anchor))
        }
        return found
    }

    /// The transcript under its source (the URL or the embed), unless one is already there: nil then. A source only in the
    /// frontmatter keeps it there, and the transcript goes at the end of the body (under its own name when the note
    /// already has a transcript).
    static func insertingTranscript(_ body: String, anchor: String, label: String, transcript: String) -> String? {
        if let found = body.range(of: anchor) {
            let after = body[found.upperBound...]
            if after.range(of: #"^\s*##\s*Transcript\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
            return String(body[..<found.upperBound]) + "\n\n## Transcript\n\n\(transcript)" + after
        }
        if body.contains("### Transcript — \(label)") { return nil }
        let heading = body.range(of: #"(^|\n)##\s*Transcript\b"#, options: [.regularExpression, .caseInsensitive]) != nil ? "### Transcript — \(label)" : "## Transcript"
        return body.replacingOccurrences(of: #"\s+\z"#, with: "", options: .regularExpression) + "\n\n\(heading)\n\n\(transcript)\n"
    }

    // MARK: Files

    /// The folder new attachments go into, from the vault's top, as Obsidian reads app.json's `attachmentFolderPath`:
    /// none or "/" is the vault's top, "./" the note's own folder, "./x" a folder under it, anything else a folder in the vault.
    static func attachmentFolder(setting: String?, note: String) -> String {
        let here = note.lastIndex(of: "/").map { String(note[..<$0]) } ?? ""
        let value = (setting ?? "/").trimmingCharacters(in: .whitespaces)
        func clean(_ path: String) -> String { path.split(separator: "/").filter { $0 != "." && !$0.isEmpty }.joined(separator: "/") }
        if value == "." || value == "./" { return here }
        if value.hasPrefix("./") { return clean(here + "/" + value.dropFirst(2)) }
        return clean(value)
    }

    /// A name not yet taken in the folder, as Obsidian picks one ("a.png", then "a 1.png", "a 2.png").
    static func availableName(_ name: String, taken: Set<String>) -> String {
        let lower = Set(taken.map { $0.lowercased() })
        guard lower.contains(name.lowercased()) else { return name }
        let ext = (name as NSString).pathExtension, base = (name as NSString).deletingPathExtension
        var n = 1
        while lower.contains((ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)").lowercased()) { n += 1 }
        return ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
    }

    /// A downloaded picture's name: the URL's last part, given the extension its type says when it has no picture's own;
    /// characters no system allows made "_".
    static func imageName(_ url: String, contentType: String?) -> String {
        var base = "image"
        if let last = URL(string: url)?.path.split(separator: "/").last { base = String(last).removingPercentEncoding ?? String(last) }
        if base.range(of: #"\.(png|jpe?g|gif|webp|bmp|svg|avif)$"#, options: [.regularExpression, .caseInsensitive]) == nil {
            let sub = contentType?.split(separator: "/").dropFirst().first.map(String.init) ?? "png"
            var ext = String(sub.split(separator: ";").first ?? "png").trimmingCharacters(in: .whitespaces)
            ext = ext.replacingOccurrences(of: "jpeg", with: "jpg").replacingOccurrences(of: "svg+xml", with: "svg")
            base += "." + (ext.isEmpty ? "png" : ext)
        }
        let cleaned = base.replacingOccurrences(of: #"[\\/:*?"<>|]"#, with: "_", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? "image-\(Int(Date().timeIntervalSince1970)).png" : cleaned
    }

    /// How a file is named in an embed: its name when that finds it from the note (Obsidian's shortest form), else its path.
    static func embedName(_ path: String, items: [Study.VaultItem], from note: String) -> String {
        let name = Study.VaultItem(path: path, folder: false).name
        guard let found = Study.resolve(name, in: items, from: note) else { return name }
        return Study.same(found.path, path) ? name : path
    }

    // MARK: What the tools print

    /// One line of yt-dlp's output, read.
    enum YtDlpLine: Equatable {
        /// "[download]  45.3% of 218.53KiB at 1.10MiB/s ETA 00:05": the percent and the line without its tag.
        case progress(Double, String)
        /// Where a file is being written ("[download] Destination: …", "[ExtractAudio] Destination: …").
        case destination(String)
        /// A step worth saying: a download finished, formats merged, audio extracted, already downloaded.
        case step(String)
        /// "ERROR: …", without the tag and the site and id before the message.
        case error(String)
        /// Warnings, the extractor's own steps, thumbnails it tried, files it tidied away.
        case noise
    }

    static func ytDlpLine(_ raw: String) -> YtDlpLine {
        if raw.first == " " || raw.first == "\t" { return .noise }   // a warning's continuation
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return .noise }
        if line.hasPrefix("ERROR:") {
            var message = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            message = message.replacingOccurrences(of: #"^\[[^\]]+\]\s*(?:[^:\s]+:\s+)?"#, with: "", options: .regularExpression)
            return .error(message)
        }
        if let g = Study.firstMatch(#"^\[download\]\s+(\d+(?:\.\d+)?)%\s+of\s+(.*)$"#, in: line) {
            let rest = g[2].replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let percent = Double(g[1]) ?? 0
            if rest.contains(" in ") { return .step("\(g[1])% of \(rest)") }  // "100% of 302KiB in 00:00:00": the file is done
            return .progress(percent, "\(g[1])% of \(rest)")
        }
        if let g = Study.firstMatch(#"^\[(?:download|ExtractAudio)\]\s+Destination:\s+(.+)$"#, in: line) { return .destination(g[1]) }
        if let g = Study.firstMatch(#"^\[Merger\]\s+(.+)$"#, in: line) { return .step(g[1]) }
        if let g = Study.firstMatch(#"^\[download\]\s+(.+ has already been downloaded.*)$"#, in: line) { return .step(g[1]) }
        return .noise
    }

    /// The line that says why yt-dlp failed: its last error, else its last line (nil when it said nothing). Cut short:
    /// yt-dlp's errors run on with advice about its own options.
    static func failure(_ lines: [String]) -> String? {
        var errors: [String] = []
        for line in lines { if case let .error(message) = ytDlpLine(line) { errors.append(message) } }
        let picked = errors.last
            ?? lines.last { $0.range(of: #"error|unable|failed|unavailable"#, options: [.regularExpression, .caseInsensitive]) != nil }
            ?? lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return picked.map { short(onceEach($0.trimmingCharacters(in: .whitespaces))) }
    }

    /// A message with each sentence once ("The page needs to be reloaded.. The page needs to be reloaded." is one).
    static func onceEach(_ text: String) -> String {
        var sentences: [String] = []
        for part in text.replacingOccurrences(of: #"\.{2,}(?=\s|$)"#, with: ".", options: .regularExpression).components(separatedBy: ". ") {
            let sentence = part.hasSuffix(".") ? String(part.dropLast()) : part
            if sentences.last != sentence { sentences.append(sentence) }
        }
        return sentences.joined(separator: ". ") + (text.hasSuffix(".") ? "." : "")
    }

    /// At most about 200 characters, cut after a sentence when one ends in time.
    static func short(_ text: String, _ limit: Int = 200) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        if let stop = head.range(of: ". ", options: .backwards), head.distance(from: head.startIndex, to: stop.lowerBound) > 40 { return String(head[..<stop.lowerBound]) + "." }
        return head + "…"
    }

    /// A login or bot gate: yt-dlp is tried again with a browser's cookies (Instagram, Facebook and TikTok often ask).
    static func wantsCookies(_ lines: [String]) -> Bool {
        lines.contains { $0.range(of: #"needs to be reloaded|sign.?in|log.?in|bot|cookies"#, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    /// The browsers whose cookies yt-dlp tries, your default browser first (by its bundle id), then Vault Agent's order;
    /// only those `installed` says are on this Mac (each try costs yt-dlp's whole start, about 15 s).
    static func cookieBrowsers(defaultBrowser: String?, installed: (String) -> Bool = { _ in true }) -> [String] {
        let known = ["com.google.chrome": "chrome", "company.thebrowser.browser": "chrome", "org.chromium.chromium": "chromium",
                     "com.brave.browser": "brave", "com.operasoftware.opera": "opera", "org.mozilla.firefox": "firefox",
                     "com.apple.safari": "safari", "com.microsoft.edgemac": "edge", "com.vivaldi.vivaldi": "vivaldi"]
        var browsers: [String] = []
        for name in [defaultBrowser.flatMap { known[$0.lowercased()] }].compactMap({ $0 }) + ["chrome", "brave", "opera", "firefox", "safari"]
        where !browsers.contains(name) && installed(name) { browsers.append(name) }
        return browsers
    }

    /// The bundle id of the app whose cookies yt-dlp reads under that name.
    static let browserApps = ["chrome": "com.google.Chrome", "chromium": "org.chromium.Chromium", "brave": "com.brave.Browser", "opera": "com.operasoftware.Opera",
                              "firefox": "org.mozilla.firefox", "safari": "com.apple.Safari", "edge": "com.microsoft.edgemac", "vivaldi": "com.vivaldi.Vivaldi"]

    /// The path `which` printed in a login shell (zsh prints "x not found" on the same stream, so only a path counts).
    static func shellPath(_ output: String) -> String? {
        output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.hasPrefix("/") }
    }

    /// "Python 3.11.9" → (3, 11).
    static func pythonVersion(_ output: String) -> (major: Int, minor: Int)? {
        guard let g = Study.firstMatch(#"Python\s+(\d+)\.(\d+)"#, in: output), let major = Int(g[1]), let minor = Int(g[2]) else { return nil }
        return (major, minor)
    }

    /// A Python WhisperX installs on with pip: 3.10 to 3.12 (torch has no wheels for newer ones yet, and WhisperX
    /// needs 3.10 or newer).
    static func suitsWhisper(_ version: (major: Int, minor: Int)) -> Bool { version.major == 3 && (10 ... 12).contains(version.minor) }

    /// A line of pip's or uv's install worth saying (what it's collecting, downloading, installing; errors). Long lists cut.
    static func installLine(_ raw: String) -> String? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = ["Collecting ", "Downloading ", "Downloaded ", "Installing collected packages", "Successfully installed", "Building wheel",
                      "Resolved ", "Prepared ", "Installed ", "Using CPython", "Using Python", "Creating virtual environment", "ERROR", "error:"]
        guard wanted.contains(where: { line.hasPrefix($0) }) else { return nil }
        if line.hasPrefix("Successfully installed") {
            let count = line.split(separator: " ").count - 2
            return count > 3 ? "Successfully installed \(count) packages" : line
        }
        return short(line, 160)
    }

    /// A line of WhisperX's worth saying: its steps (">>Performing transcription…"), the language it heard, how far it
    /// is, a model being downloaded (tqdm's bar), errors. Library warnings are left out.
    static func whisperLine(_ raw: String) -> String? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix(">>") { return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        if line.hasPrefix("Detected language") || line.hasPrefix("Progress:") { return line }
        if line.range(of: #"\d+%\|"#, options: .regularExpression) != nil {
            // tqdm: "model.bin:  45%|████▌     | 220M/484M [00:10<00:12, 21.0MB/s]" without the bar.
            return line.replacingOccurrences(of: #"\|[^|]*\|"#, with: " ", options: .regularExpression).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        }
        if line.range(of: #"^(\w+Error|Error|Exception|RuntimeError|Traceback)"#, options: .regularExpression) != nil { return short(line) }
        return nil
    }

    /// Why WhisperX failed, from what it printed: its last error-like line, else its last line.
    static func whisperFailure(_ lines: [String]) -> String? {
        let picked = lines.last { $0.range(of: #"error|exception|failed|unsupported|not found|invalid"#, options: [.regularExpression, .caseInsensitive]) != nil }
            ?? lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return picked.map { short($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Said when a tool has been quiet a while: how long it has run, in minutes and seconds.
    static func stillWorking(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        return whole < 60 ? L("Still working: %@ s so far…", whole) : L("Still working: %@ min %@ s so far…", whole / 60, whole % 60)
    }

    /// What reaches your screen of a tool's lines: every useful step, and a progress line at most every two seconds (and
    /// its last, at 100%), the same line never twice in a row.
    struct LineGate {
        var every: TimeInterval = 2
        private var lastProgress: Date?
        private var lastLine: String?

        init(every: TimeInterval = 2) { self.every = every }

        mutating func pass(_ line: String, progress: Bool, done: Bool = false, now: Date = Date()) -> String? {
            guard line != lastLine else { return nil }
            if progress && !done, let last = lastProgress, now.timeIntervalSince(last) < every { return nil }
            if progress { lastProgress = now }
            lastLine = line
            return line
        }
    }
}
