import AppKit
import Foundation

/// Sage's media tools (2026-11-09, from the Vault Agent plugin): Fetch media downloads the social videos and pictures a
/// note links to into the vault's attachments, puts an embed where each link was and uses the video's thumbnail as the
/// note's banner; Transcribe writes a "## Transcript" under the note's source, transcribed on this Mac with WhisperX.
///
/// The interface the rest of Sage calls. The note logic is in SageMediaText.swift (checked); this file runs the tools:
/// yt-dlp, ffmpeg and WhisperX as processes off the main thread, their useful lines streamed to `progress`, each one
/// stopped when the task is cancelled. Every note change goes through `Study.writeNote` (a copy kept first, one step).
enum SageMedia {
    /// What a run did, for the chat: what it says when done (what was added, what failed and why), and the files it made
    /// or changed (paths in the vault). The steps on the way went to `progress`.
    struct Report: Equatable {
        var lines: [String] = []
        var changed: [String] = []
    }

    /// Downloads and localizes the media the note links to. `progress` is told each step as it happens.
    static func fetch(note: URL, vault: URL, progress: @escaping @Sendable (String) -> Void) async throws -> Report {
        try await fetch(note: note, vault: vault, keep: Study.editsKept(in: SageDesk.place), progress: progress)
    }

    /// Transcribes the note's video or audio (its source, or media embedded in it) and writes the transcript into the note.
    static func transcribe(note: URL, vault: URL, progress: @escaping @Sendable (String) -> Void) async throws -> Report {
        try await transcribe(note: note, vault: vault, keep: Study.editsKept(in: SageDesk.place), progress: progress)
    }

    /// Fetch media, the note kept as it was in `keep` before it changes (the checks keep it in a temp folder).
    static func fetch(note: URL, vault: URL, keep: URL, progress: @escaping @Sendable (String) -> Void) async throws -> Report {
        let place = try Place(note: note, vault: vault)
        var report = Report()
        let start = try Study.readNote(note)
        var fetched = Fetched()
        var made: [String] = []
        var failed = false
        func say(_ line: String, failure: Bool = false) { progress(line); if failure { report.lines.append(line); failed = true } }

        // 1. Social videos, with yt-dlp.
        progress(L("Looking for supported social-video links…"))
        let urls = videoURLs(start.text)
        if !urls.isEmpty {
            progress(urls.count == 1 ? L("Found 1 video link.") : L("Found %@ video links.", urls.count))
            do {
                // yt-dlp is looked for only when a video isn't in the vault yet.
                var ytdlp: String?, ffmpeg: String?
                var items = Study.vaultItems(vault)
                for (index, url) in urls.enumerated() {
                    try Task.checkCancellation()
                    let stem = fileStem(note: place.name, position: index + 1)
                    let listing = place.attachmentNames()
                    if let existing = listing.first(where: { isVideo($0, stem: stem) }) {
                        fetched.videos.append((url, embedName(place.attachmentPath(existing), items: items, from: place.path)))
                        say(L("Using %@, already in the vault.", "[[\(existing)]]"))
                        continue
                    }
                    if ytdlp == nil {
                        ytdlp = try await Tools.ytDlp(vault: vault, progress: progress)
                        ffmpeg = await Tools.ffmpeg(progress: progress)
                        try FileManager.default.createDirectory(at: place.attachments, withIntermediateDirectories: true)
                    }
                    say(L("Downloading video %@ of %@: %@", index + 1, urls.count, label(url)))
                    let before = Set(listing)
                    let args = ["--no-playlist", "--newline", "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
                                "--merge-output-format", "mp4", "--write-thumbnail", "--convert-thumbnails", "jpg",
                                "-o", place.attachments.appendingPathComponent("\(stem).%(ext)s").path]
                    // What yt-dlp left of a failed or stopped download (a .part, a thumbnail) goes; the link stays as it was.
                    func tidy() {
                        for name in place.attachmentNames() where !before.contains(name) && name.lowercased().hasPrefix(stem.lowercased()) {
                            try? FileManager.default.removeItem(at: place.attachments.appendingPathComponent(name))
                        }
                    }
                    let outcome: Outcome
                    do { outcome = try await Tools.download(ytdlp!, args, url: url, ffmpeg: ffmpeg, in: vault, progress: progress) } catch { tidy(); throw error }
                    let new = place.attachmentNames().filter { !before.contains($0) }
                    guard outcome.status == 0 else {
                        tidy()
                        say(L("Couldn't download video %@: %@", index + 1, failure(outcome.lines) ?? L("unknown error")), failure: true)
                        continue
                    }
                    // Only a real video yt-dlp made replaces the link: never a guess.
                    let videos = new.filter { videoTypes.contains(($0 as NSString).pathExtension.lowercased()) }
                    guard let video = videos.first(where: { $0.lowercased().hasPrefix(stem.lowercased()) }) ?? videos.first else {
                        say(L("yt-dlp finished but made no video for %@: the link is left as it was.", label(url)), failure: true)
                        continue
                    }
                    made.append(place.attachmentPath(video))
                    items = Study.vaultItems(vault)
                    fetched.videos.append((url, embedName(place.attachmentPath(video), items: items, from: place.path)))
                    if let thumbnail = new.first(where: { isThumbnail($0, stem: stem) }) {
                        made.append(place.attachmentPath(thumbnail))
                        fetched.thumbnails.append(embedName(place.attachmentPath(thumbnail), items: items, from: place.path))
                        say(L("Saved %@ and %@.", "[[\(video)]]", "[[\(thumbnail)]]"))
                    } else {
                        say(L("Saved %@.", "[[\(video)]]"))
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                say(L("yt-dlp isn't available: %@", error.localizedDescription), failure: true)
            }
        }

        // 2. Pictures linked from the body as the videos left it.
        try Task.checkCancellation()
        progress(L("Looking for external image links…"))
        let images = imageURLs(splitFrontmatter(fetched.applied(to: start.text)).body)
        for (index, url) in images.enumerated() {
            try Task.checkCancellation()
            say(L("Downloading image %@ of %@: %@", index + 1, images.count, label(url)))
            do {
                let name = try await Tools.downloadImage(url, into: place)
                made.append(place.attachmentPath(name))
                fetched.images.append((url, embedName(place.attachmentPath(name), items: Study.vaultItems(vault), from: place.path)))
                say(L("Saved %@.", "[[\(name)]]"))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                say(L("Couldn't download image %@: %@", index + 1, error.localizedDescription), failure: true)
            }
        }

        // 3. The note, as it reads now (you may have typed in it while the videos came down).
        let now = try Study.readNote(note)
        let text = fetched.applied(to: now.text)
        if text != now.text {
            try Study.writeNote(note, text: text, was: now, keep: keep)
            report.changed.append(place.path)
        }
        report.changed.insert(contentsOf: made, at: 0)

        let added = embeds(text).subtracting(embeds(now.text)).sorted()
        if !added.isEmpty {
            report.lines.insert(L("Added to the note: %@", added.map { "[[\($0)]]" }.joined(separator: ", ")), at: 0)
        } else if !failed {
            report.lines.append(L("No new supported media URLs were found in the note."))
        }
        if let banner = banner(text), banner != SageMedia.banner(now.text) { report.lines.append(L("Banner set to %@.", "[[\(banner)]]")) }
        return report
    }

    /// Transcribe, the note kept as it was in `keep` before it changes.
    static func transcribe(note: URL, vault: URL, keep: URL, progress: @escaping @Sendable (String) -> Void) async throws -> Report {
        let place = try Place(note: note, vault: vault)
        var report = Report()
        let start = try Study.readNote(note)
        let body = splitFrontmatter(start.text).body

        // A note Fetch media went through no longer shows its link in the body: its ![[video]] is transcribed instead,
        // straight from the vault. A link whose video is already embedded (by Fetch media's name for it) is skipped.
        let items = Study.vaultItems(vault)
        var local: [(label: String, anchor: String, file: URL)] = []
        for (link, anchor) in mediaEmbeds(body) {
            let file = Study.resolve(link, in: items, from: place.path).map { vault.appendingPathComponent($0.path) }
                ?? [vault.appendingPathComponent(link), place.attachments.appendingPathComponent(link)].first { FileManager.default.fileExists(atPath: $0.path) }
            guard let file, FileManager.default.fileExists(atPath: file.path), !local.contains(where: { $0.file == file }) else { continue }
            local.append((file.lastPathComponent, anchor, file))
        }
        let remote = videoURLs(start.text).enumerated().filter { index, _ in
            !local.contains { $0.file.deletingPathExtension().lastPathComponent == fileStem(note: place.name, position: index + 1) }
        }.map(\.element)
        if local.isEmpty && remote.isEmpty {
            let line = L("No supported social links or localized video embeds found in this note.")
            progress(line); report.lines.append(line)
            return report
        }

        let python: String
        do {
            python = try await Tools.whisperPython(progress: progress)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let line = L("Couldn't prepare transcription: %@", error.localizedDescription)
            progress(line); report.lines.append(line)
            return report
        }

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("edit-assist-transcribe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }   // the audio downloaded for it never stays

        typealias Target = (label: String, anchor: String, file: URL?, url: String?)
        let targets: [Target] = local.map { ($0.label, $0.anchor, $0.file, nil) } + remote.map { (label($0), $0, nil, $0) }
        var ytdlp: String?, ffmpeg: String?
        var content = body
        var added: [(anchor: String, label: String, transcript: String)] = []
        if !Tools.hasWhisperModel { progress(L("The first transcription also downloads WhisperX's speech model (about 500 MB).")) }
        for (index, target) in targets.enumerated() {
            try Task.checkCancellation()
            // Already transcribed under it: said before minutes go into downloading and transcribing it again.
            if insertingTranscript(content, anchor: target.anchor, label: target.label, transcript: "") == nil {
                progress(L("A transcript already exists for item %@.", index + 1)); continue
            }
            var media = target.file
            if let url = target.url {
                do {
                    if ytdlp == nil { ytdlp = try await Tools.ytDlp(vault: vault, progress: progress); ffmpeg = await Tools.ffmpeg(progress: progress) }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let line = L("yt-dlp isn't available: %@", error.localizedDescription)
                    progress(line); report.lines.append(line)
                    continue
                }
                progress(L("Downloading audio %@ of %@: %@", index + 1, targets.count, target.label))
                let before = Set((try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? [])
                let outcome = try await Tools.download(ytdlp!, ["--no-playlist", "--newline", "-x", "--audio-format", "m4a", "-o", temp.appendingPathComponent("%(id)s.%(ext)s").path],
                                                       url: url, ffmpeg: ffmpeg, in: temp, progress: progress)
                guard outcome.status == 0 else {
                    let line = L("Couldn't download audio %@: %@", index + 1, failure(outcome.lines) ?? L("unknown error"))
                    progress(line); report.lines.append(line)
                    continue
                }
                let audio = ((try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? []).first {
                    !before.contains($0) && ["m4a", "mp3", "wav", "ogg", "opus", "webm"].contains(($0 as NSString).pathExtension.lowercased())
                }
                guard let audio else {
                    let line = L("No audio file found for item %@.", index + 1)
                    progress(line); report.lines.append(line)
                    continue
                }
                media = temp.appendingPathComponent(audio)
            }
            guard let media, FileManager.default.fileExists(atPath: media.path) else {
                let line = L("Couldn't find media for item %@.", index + 1)
                progress(line); report.lines.append(line)
                continue
            }
            let downloaded = target.url != nil
            defer { if downloaded { try? FileManager.default.removeItem(at: media) } }

            progress(L("Transcribing item %@ of %@ (this may take a while)…", index + 1, targets.count))
            let ran = try await Tools.whisper(python, media: media, output: temp, progress: progress)
            let text = temp.appendingPathComponent(media.deletingPathExtension().lastPathComponent + ".txt")
            defer { try? FileManager.default.removeItem(at: text) }
            guard ran.status == 0, FileManager.default.fileExists(atPath: text.path) else {
                let line = L("Transcription failed for item %@: %@", index + 1, whisperFailure(ran.lines) ?? L("WhisperX did not produce a transcript file."))
                progress(line); report.lines.append(line)
                continue
            }
            let transcript = ((try? String(contentsOf: text, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { progress(L("No speech was detected for item %@.", index + 1)); continue }
            guard let updated = insertingTranscript(content, anchor: target.anchor, label: target.label, transcript: transcript) else {
                progress(L("A transcript already exists for item %@.", index + 1)); continue
            }
            content = updated
            added.append((target.anchor, target.label, transcript))
            progress(L("Transcript added for item %@.", index + 1))
        }

        if !added.isEmpty {
            // The note as it reads now: a transcript can take many minutes, and you may have typed in it meanwhile.
            let now = try Study.readNote(note)
            var (frontmatter, current) = splitFrontmatter(now.text)
            for item in added { if let updated = insertingTranscript(current, anchor: item.anchor, label: item.label, transcript: item.transcript) { current = updated } }
            frontmatter += current
            if frontmatter != now.text {
                try Study.writeNote(note, text: frontmatter, was: now, keep: keep)
                report.changed.append(place.path)
            }
        }
        report.lines.insert(added.isEmpty ? L("No transcript was added.") : added.count == 1 ? L("Added 1 transcript to the note.") : L("Added %@ transcripts to the note.", added.count), at: 0)
        return report
    }
}

// MARK: The note and its attachments

extension SageMedia {
    /// The note in its vault: its path and name, and the folder its attachments go into (app.json's attachmentFolderPath).
    struct Place {
        let vault: URL
        let path: String
        let name: String
        let attachmentFolder: String
        var attachments: URL { attachmentFolder.isEmpty ? vault : vault.appendingPathComponent(attachmentFolder, isDirectory: true) }

        init(note: URL, vault: URL) throws {
            let top = vault.resolvingSymlinksInPath().standardizedFileURL.path
            let file = note.resolvingSymlinksInPath().standardizedFileURL.path
            guard file.hasPrefix(top + "/") else { throw AssistError.message(L("The note isn't in the vault.")) }
            self.vault = vault
            path = String(file.dropFirst(top.count + 1))
            name = note.deletingPathExtension().lastPathComponent
            attachmentFolder = SageMedia.attachmentFolder(setting: Study.appSetting(vault, "attachmentFolderPath") as? String, note: path)
        }

        func attachmentNames() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: attachments.path)) ?? [] }
        func attachmentPath(_ name: String) -> String { attachmentFolder.isEmpty ? name : attachmentFolder + "/" + name }
    }

    /// What Fetch media got, put into a note's text: thumbnails as the banner (only when it has none), each link made an
    /// embed. Applied to the note as it reads when written, so typing during a download is kept.
    struct Fetched {
        var videos: [(url: String, file: String)] = []
        var thumbnails: [String] = []
        var images: [(url: String, file: String)] = []

        func applied(to text: String) -> String {
            var (frontmatter, body) = splitFrontmatter(text)
            for thumbnail in thumbnails { frontmatter = withBanner(frontmatter, thumbnail) }
            for video in videos { body = embedding(body, url: video.url, file: video.file) }
            for image in images where body.contains(image.url) { body = embedding(body, url: image.url, file: image.file) }
            return frontmatter + body
        }
    }
}

// MARK: Running the tools

extension SageMedia {
    /// What a process did: its exit status and its last lines (stdout and stderr together), for saying why it failed.
    struct Outcome {
        var status: Int32
        var lines: [String]
    }

    enum Tools {
        static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
        /// Edit Assist's own tools (a yt-dlp or uv it downloaded) and WhisperX runtime, in its Application Support folder.
        static var ownBin: URL { Studio.folder.appendingPathComponent("bin", isDirectory: true) }
        static var ownWhisper: URL { Studio.folder.appendingPathComponent("whisperx", isDirectory: true) }
        /// The runtime Vault Agent installs for itself; used as it is when there.
        static var vaultAgentWhisper: URL { home.appendingPathComponent("Library/Application Support/Obsidian/Vault Agent/whisperx/bin/python") }

        private static let found = Found()
        private final class Found: @unchecked Sendable {
            private let lock = NSLock()
            private var paths: [String: String] = [:]
            subscript(key: String) -> String? {
                get { lock.lock(); defer { lock.unlock() }; return paths[key] }
                set { lock.lock(); paths[key] = newValue; lock.unlock() }
            }
        }

        // MARK: yt-dlp, ffmpeg

        /// A yt-dlp that runs (`--version`): your shell's, Homebrew's, ~/.local/bin's, Vault Agent's in the vault, the one
        /// Edit Assist downloaded; else the standalone macOS build is downloaded once into Edit Assist's folder.
        static func ytDlp(vault: URL, progress: @escaping @Sendable (String) -> Void) async throws -> String {
            if let known = found["yt-dlp"], await works(known, ["--version"]) { return known }
            progress(L("Looking for yt-dlp…"))
            // Not ~/Library/Python's pip copies, which Vault Agent also tried: on this Mac that one runs on macOS's Python
            // 3.9, which yt-dlp no longer supports, so it is stuck on an old version (2025.10.14) and was found first.
            let candidates = [await shellWhich("yt-dlp"), "/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", home.appendingPathComponent(".local/bin/yt-dlp").path,
                              vault.appendingPathComponent(".obsidian/plugins/vault-agent/bin/yt-dlp").path, ownBin.appendingPathComponent("yt-dlp").path].compactMap { $0 }
            for candidate in unique(candidates) where await works(candidate, ["--version"]) { found["yt-dlp"] = candidate; return candidate }

            let destination = ownBin.appendingPathComponent("yt-dlp")
            try await fetchFile(URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!, to: destination, what: "yt-dlp", progress: progress)
            guard await works(destination.path, ["--version"]) else { throw AssistError.message(L("yt-dlp was downloaded but doesn't run.")) }
            progress(L("yt-dlp is ready."))
            found["yt-dlp"] = destination.path
            return destination.path
        }

        /// ffmpeg, found the same way (yt-dlp merges video and sound with it, and takes the audio out for Transcribe).
        static func ffmpeg(progress: @escaping @Sendable (String) -> Void) async -> String? {
            if let known = found["ffmpeg"], await works(known, ["-version"]) { return known }
            let candidates = [await shellWhich("ffmpeg"), "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", home.appendingPathComponent(".local/bin/ffmpeg").path].compactMap { $0 }
            for candidate in unique(candidates) where await works(candidate, ["-version"]) { found["ffmpeg"] = candidate; return candidate }
            progress(L("ffmpeg wasn't found: a video may come without its sound, and audio can't be taken out for a transcript."))
            return nil
        }

        /// yt-dlp on one link, its useful lines shown; tried again with a browser's cookies when the site wants you signed
        /// in (your default browser first, only browsers this Mac has). The error kept is the last one that isn't about the cookies themselves.
        static func download(_ ytdlp: String, _ args: [String], url: String, ffmpeg: String?, in folder: URL, progress: @escaping @Sendable (String) -> Void) async throws -> Outcome {
            let base = args + (ffmpeg.map { ["--ffmpeg-location", $0] } ?? [])
            var outcome = try await runYtDlp(ytdlp, base + [url], in: folder, progress: progress)
            if outcome.status != 0 && wantsCookies(outcome.lines) {
                let installed: (String) -> Bool = { name in browserApps[name].map { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil } ?? false }
                for browser in cookieBrowsers(defaultBrowser: defaultBrowser(), installed: installed) {
                    try Task.checkCancellation()
                    progress(L("The site wants you signed in: trying %@'s cookies…", browser))
                    let retry = try await runYtDlp(ytdlp, base + ["--cookies-from-browser", browser, url], in: folder, progress: progress)
                    if retry.status == 0 { outcome = retry; break }
                    if !retry.lines.contains(where: { $0.range(of: "keychain|cookies", options: [.regularExpression, .caseInsensitive]) != nil }) { outcome.lines = retry.lines }
                }
            }
            return outcome
        }

        private static func runYtDlp(_ ytdlp: String, _ args: [String], in folder: URL, progress: @escaping @Sendable (String) -> Void) async throws -> Outcome {
            let gate = Gate()
            return try await beating(gate, progress) { try await run(ytdlp, args, in: folder) { raw in
                switch ytDlpLine(raw) {
                case let .progress(percent, text): if let line = gate.pass(text, progress: true, done: percent >= 100) { progress(line) }
                case let .destination(path): if let line = gate.pass(L("Writing %@", (path as NSString).lastPathComponent), progress: false) { progress(line) }
                case let .step(text): if let line = gate.pass(text, progress: false) { progress(line) }
                case .error, .noise: break
                }
            } }
        }

        /// The bundle id of the browser that opens web links.
        static func defaultBrowser() -> String? {
            NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!).flatMap { Bundle(url: $0)?.bundleIdentifier }
        }

        // MARK: Pictures

        /// A picture link saved into the attachments folder under a name not taken there; the name. Only a picture
        /// counts: an error status or a web page in its place is refused.
        static func downloadImage(_ url: String, into place: Place) async throws -> String {
            guard let address = URL(string: url) else { throw AssistError.message(L("That isn't a web address.")) }
            var request = URLRequest(url: address)
            request.timeoutInterval = 60
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            if let status = http?.statusCode, !(200 ..< 300).contains(status) { throw AssistError.message(L("The site answered %@.", "HTTP \(status)")) }
            let type = http?.value(forHTTPHeaderField: "Content-Type")
            if type?.lowercased().hasPrefix("text/html") == true || data.isEmpty { throw AssistError.message(L("The address gave a web page, not a picture.")) }
            try FileManager.default.createDirectory(at: place.attachments, withIntermediateDirectories: true)
            let name = availableName(imageName(url, contentType: type), taken: Set(place.attachmentNames()))
            try data.write(to: place.attachments.appendingPathComponent(name), options: .withoutOverwriting)
            return name
        }

        // MARK: WhisperX

        /// A Python that imports WhisperX: Vault Agent's runtime, Edit Assist's own, or a python3 that has it; else Edit
        /// Assist's own is made (once; it can take many minutes, and says each step).
        static func whisperPython(progress: @escaping @Sendable (String) -> Void) async throws -> String {
            if let known = found["whisperx"], await importsWhisper(known) { return known }
            progress(L("Looking for WhisperX…"))
            let own = ownWhisper.appendingPathComponent("bin/python").path
            var candidates = [vaultAgentWhisper.path, own]
            candidates += [await shellWhich("python3"), "/opt/homebrew/bin/python3", "/usr/local/bin/python3", appleCommandLinePython].compactMap { $0 }
            for candidate in unique(candidates) where await importsWhisper(candidate) { found["whisperx"] = candidate; return candidate }

            progress(L("Setting up transcription on this Mac, one time: a private WhisperX in Edit Assist's folder. This can take ten minutes or more."))
            var uv: String?
            if !FileManager.default.fileExists(atPath: own) {
                if let base = await pythonForVenv() {
                    progress(L("Making a Python %@ environment for WhisperX…", base.version))
                    let gate = Gate()
                    let made = try await beating(gate, progress) { try await run(base.python, ["-m", "venv", ownWhisper.path], timeout: 600, line: installLines(progress, gate)) }
                    guard made.status == 0 else { throw AssistError.message(L("Couldn't make the Python environment: %@", whisperFailure(made.lines) ?? L("unknown error"))) }
                } else {
                    // No Python 3.10–3.12 here (macOS's own is 3.9): uv brings a private Python 3.11, as Vault Agent does.
                    uv = try await uvTool(progress: progress)
                    progress(L("Getting Python 3.11 for WhisperX (one time)…"))
                    let gate = Gate(), tool = uv!
                    let made = try await beating(gate, progress) { try await run(tool, ["venv", ownWhisper.path, "--python", "3.11"], env: uvEnvironment, timeout: 1800, line: installLines(progress, gate)) }
                    guard made.status == 0 else { throw AssistError.message(L("Couldn't install Python for transcription: %@", whisperFailure(made.lines) ?? L("unknown error"))) }
                }
            }
            if !(await importsWhisper(own)) {
                progress(L("Installing WhisperX and its speech-recognition parts (one time; several hundred MB)…"))
                let installed: Outcome
                if await works(own, ["-m", "pip", "--version"]) {
                    let gate = Gate()
                    installed = try await beating(gate, progress) { try await run(own, ["-m", "pip", "install", "--progress-bar", "off", "whisperx"], timeout: 7200, line: installLines(progress, gate)) }
                } else {
                    let tool: String
                    if let uv { tool = uv } else { tool = try await uvTool(progress: progress) }
                    let gate = Gate()
                    installed = try await beating(gate, progress) { try await run(tool, ["pip", "install", "--python", own, "whisperx"], env: uvEnvironment, timeout: 7200, line: installLines(progress, gate)) }
                }
                guard installed.status == 0 else { throw AssistError.message(L("Couldn't install WhisperX: %@", whisperFailure(installed.lines) ?? L("unknown error"))) }
            }
            progress(L("Checking WhisperX starts…"))
            guard await importsWhisper(own) else { throw AssistError.message(L("WhisperX installed but could not be started.")) }
            progress(L("Transcription is set up."))
            found["whisperx"] = own
            return own
        }

        /// WhisperX on one file, a .txt of the same name written into `output`. CPU with int8 (its float16 default crashes
        /// on a Mac), the small model, Silero's voice detection (pyannote's breaks with newer PyTorch), as Vault Agent runs it.
        static func whisper(_ python: String, media: URL, output: URL, progress: @escaping @Sendable (String) -> Void) async throws -> Outcome {
            let args = ["-m", "whisperx", media.path, "--output_dir", output.path, "--output_format", "txt", "--model", "small",
                        "--device", "cpu", "--compute_type", "int8", "--vad_method", "silero"]
            let gate = Gate()
            let show: @Sendable (String) -> Void = { raw in
                guard let line = whisperLine(raw) else { return }
                let isProgress = line.hasPrefix("Progress:") || line.contains("%")
                if let passed = gate.pass(line, progress: isProgress, done: line.contains("100%") || line.contains("100.00%")) { progress(passed) }
            }
            return try await beating(gate, progress) {
                let ran = try await run(python, args + ["--print_progress", "True"], in: output, line: show)
                // An older WhisperX without --print_progress: run it as Vault Agent does.
                if ran.status != 0, ran.lines.contains(where: { $0.contains("unrecognized arguments") && $0.contains("print_progress") }) {
                    return try await run(python, args, in: output, line: show)
                }
                return ran
            }
        }

        /// Whether WhisperX's small model is already downloaded (Hugging Face's cache), to say the first run fetches it.
        static var hasWhisperModel: Bool {
            let hub = ProcessInfo.processInfo.environment["HF_HOME"].map { URL(fileURLWithPath: $0).appendingPathComponent("hub") } ?? home.appendingPathComponent(".cache/huggingface/hub")
            return FileManager.default.fileExists(atPath: hub.appendingPathComponent("models--Systran--faster-whisper-small").path)
        }

        static func importsWhisper(_ python: String) async -> Bool { await works(python, ["-c", "import whisperx"], timeout: 300) }

        /// macOS's own python3 only when the command-line tools are there: without them, running it asks to install them.
        static var appleCommandLinePython: String? {
            FileManager.default.fileExists(atPath: "/Library/Developer/CommandLineTools/usr/bin/python3") ? "/usr/bin/python3" : nil
        }

        /// A python3 of 3.10 to 3.12 to make the environment with, and its version.
        static func pythonForVenv() async -> (python: String, version: String)? {
            var candidates = [await shellWhich("python3")].compactMap { $0 }
            for minor in [12, 11, 10] {
                for folder in ["/opt/homebrew/bin", "/usr/local/bin", "/Library/Frameworks/Python.framework/Versions/3.\(minor)/bin"] { candidates.append("\(folder)/python3.\(minor)") }
            }
            candidates += ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", appleCommandLinePython].compactMap { $0 }
            for candidate in unique(candidates) where FileManager.default.isExecutableFile(atPath: candidate) {
                guard let ran = try? await run(candidate, ["--version"], timeout: 60), ran.status == 0,
                      let version = pythonVersion(ran.lines.joined(separator: "\n")), suitsWhisper(version) else { continue }
                return (candidate, "\(version.major).\(version.minor)")
            }
            return nil
        }

        /// uv (Astral's Python installer): one already here, else its release downloaded once into Edit Assist's folder
        /// (the archive itself, not its install script, so nothing outside Edit Assist's folders is changed).
        static func uvTool(progress: @escaping @Sendable (String) -> Void) async throws -> String {
            let own = ownBin.appendingPathComponent("uv").path
            let candidates = [home.appendingPathComponent(".local/bin/uv").path, "/opt/homebrew/bin/uv", "/usr/local/bin/uv", await shellWhich("uv"), own].compactMap { $0 }
            for candidate in unique(candidates) where await works(candidate, ["--version"]) { return candidate }
            #if arch(arm64)
            let archive = "uv-aarch64-apple-darwin"
            #else
            let archive = "uv-x86_64-apple-darwin"
            #endif
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("edit-assist-uv-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: temp) }
            let tarball = temp.appendingPathComponent("\(archive).tar.gz")
            try await fetchFile(URL(string: "https://github.com/astral-sh/uv/releases/latest/download/\(archive).tar.gz")!, to: tarball, what: "uv", progress: progress)
            let unpacked = try await run("/usr/bin/tar", ["-xzf", tarball.path, "-C", temp.path], timeout: 120)
            let binary = temp.appendingPathComponent("\(archive)/uv")
            guard unpacked.status == 0, FileManager.default.fileExists(atPath: binary.path) else { throw AssistError.message(L("Couldn't unpack uv.")) }
            try FileManager.default.createDirectory(at: ownBin, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(atPath: own)
            try FileManager.default.moveItem(at: binary, to: URL(fileURLWithPath: own))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: own)
            guard await works(own, ["--version"]) else { throw AssistError.message(L("uv was downloaded but doesn't run.")) }
            return own
        }

        /// uv keeps the Python it brings and its downloads in Edit Assist's folders, not in ~/.local (a cache you set for uv is kept).
        static var uvEnvironment: [String: String] {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            return ["UV_PYTHON_INSTALL_DIR": Studio.folder.appendingPathComponent("uv-python").path,
                    "UV_CACHE_DIR": ProcessInfo.processInfo.environment["UV_CACHE_DIR"] ?? caches.appendingPathComponent("Edit Assist/uv").path, "UV_NO_MODIFY_PATH": "1"]
        }

        /// The body run while a line is said whenever the tool has been quiet for 20 s ("Still working: 1 min 40 s so
        /// far…"): WhisperX downloads its model and pip builds without a word, and the first run takes many minutes.
        static func beating<T>(_ gate: Gate, _ progress: @escaping @Sendable (String) -> Void, _ body: () async throws -> T) async throws -> T {
            let started = Date()
            let beat = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if Task.isCancelled { break }
                    if gate.quiet >= 20 { gate.touch(); progress(stillWorking(Date().timeIntervalSince(started))) }
                }
            }
            defer { beat.cancel() }
            return try await body()
        }

        private static func installLines(_ progress: @escaping @Sendable (String) -> Void, _ gate: Gate) -> @Sendable (String) -> Void {
            return { raw in
                guard let line = installLine(raw) else { return }
                let busy = ["Collecting", "Downloading", "Downloaded", "Prepared", "Building", "Using"].contains { line.hasPrefix($0) }
                if let passed = gate.pass(line, progress: busy) { progress(passed) }
            }
        }

        // MARK: Downloads

        /// A file downloaded from the web (a tool's release), saying its size and each quarter of it, made runnable, with macOS's
        /// quarantine flag removed so Gatekeeper doesn't stop its first run.
        static func fetchFile(_ url: URL, to destination: URL, what: String, progress: @escaping @Sendable (String) -> Void) async throws {
            let (bytes, response) = try await URLSession.shared.bytes(from: url)
            if let status = (response as? HTTPURLResponse)?.statusCode, !(200 ..< 300).contains(status) {
                throw AssistError.message(L("The download of %@ answered %@.", what, "HTTP \(status)"))
            }
            let total = response.expectedContentLength
            let megabytes = total > 0 ? "\(Int((Double(total) / 1_000_000).rounded()))" : "20"
            progress(L("Downloading %@, one time (about %@ MB)…", what, megabytes))
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let partial = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).download")
            FileManager.default.createFile(atPath: partial.path, contents: nil)
            let handle = try FileHandle(forWritingTo: partial)
            var buffer = Data(), written: Int64 = 0, quarter: Int64 = 1
            do {
                for try await byte in bytes {
                    buffer.append(byte)
                    if buffer.count >= 1 << 16 {
                        try handle.write(contentsOf: buffer); written += Int64(buffer.count); buffer.removeAll(keepingCapacity: true)
                        if total > 0, quarter < 4, written >= total * quarter / 4 {
                            quarter += 1
                            progress(L("%@: %@ of %@ MB", what, "\(written / 1_000_000)", megabytes))
                        }
                    }
                }
                try handle.write(contentsOf: buffer)
                try handle.close()
            } catch {
                try? handle.close(); try? FileManager.default.removeItem(at: partial)
                throw error
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: partial, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            removexattr(destination.path, "com.apple.quarantine", 0)
        }

        // MARK: Processes

        /// Whether the tool runs and exits 0 with these arguments.
        static func works(_ tool: String, _ args: [String], timeout: TimeInterval = 120) async -> Bool {
            guard FileManager.default.isExecutableFile(atPath: tool) else { return false }
            return (try? await run(tool, args, timeout: timeout))?.status == 0
        }

        /// Where your login shell finds a command (its PATH: Homebrew, pyenv, conda, your dotfiles).
        static func shellWhich(_ command: String) async -> String? {
            let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
            guard let ran = try? await run(shell, ["-lc", "which \(command)"], timeout: 15) else { return nil }
            return shellPath(ran.lines.joined(separator: "\n"))
        }

        static func unique(_ paths: [String]) -> [String] {
            var seen: Set<String> = [], kept: [String] = []
            for path in paths where seen.insert(path).inserted { kept.append(path) }
            return kept
        }

        /// The environment a tool runs with: this app's, with the usual tool folders on PATH (an app started from the Dock
        /// gets none of your shell's), Python's output unbuffered so its lines come as they're printed.
        static func environment(_ extra: [String: String]) -> [String: String] {
            var env = ProcessInfo.processInfo.environment
            let current = (env["PATH"] ?? "").split(separator: ":").map(String.init)
            let folders = [ownBin.path, home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"] + current + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            env["PATH"] = unique(folders).joined(separator: ":")
            env["PYTHONUNBUFFERED"] = "1"
            env["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"
            env.merge(extra) { $1 }
            return env
        }

        /// Runs a tool off the main thread, each line it prints (stdout and stderr) handed to `line` as it comes. Cancelling
        /// the task stops it (SIGTERM, then SIGKILL after 3 s), and so does the timeout; a cancelled run throws.
        static func run(_ tool: String, _ args: [String], in folder: URL? = nil, env: [String: String] = [:], timeout: TimeInterval? = nil,
                        line: (@Sendable (String) -> Void)? = nil) async throws -> Outcome {
            try Task.checkCancellation()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = args
            if let folder { process.currentDirectoryURL = folder }
            process.environment = environment(env)
            process.standardInput = FileHandle.nullDevice
            let collected = Collected()
            let drained = DispatchGroup()
            let pipes = [Pipe(), Pipe()]
            process.standardOutput = pipes[0]
            process.standardError = pipes[1]
            for pipe in pipes {
                drained.enter()
                let splitter = LineSplitter { text in collected.add(text); line?(text) }
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        if splitter.finish() { drained.leave() }
                    } else {
                        splitter.feed(data)
                    }
                }
            }
            let control = Control(process)
            let status: Int32 = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                    process.terminationHandler = { finished in
                        // Wait for the last lines (not forever: a child it left behind can hold the pipe open).
                        DispatchQueue.global().async {
                            _ = drained.wait(timeout: .now() + 2)
                            continuation.resume(returning: finished.terminationStatus)
                        }
                    }
                    do {
                        try process.run()
                    } catch {
                        for pipe in pipes { pipe.fileHandleForReading.readabilityHandler = nil }
                        continuation.resume(throwing: error)
                        return
                    }
                    control.started()
                    if let timeout { DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { control.stop() } }
                }
            } onCancel: {
                control.stop()
            }
            if Task.isCancelled { throw CancellationError() }
            return Outcome(status: status, lines: collected.lines)
        }
    }

    /// LineGate shared by a process's line handler (called on its pipes' queues).
    final class Gate: @unchecked Sendable {
        private var gate = LineGate()
        private var said = Date()
        private let lock = NSLock()
        func pass(_ line: String, progress: Bool, done: Bool = false) -> String? {
            lock.lock(); defer { lock.unlock() }
            let passed = gate.pass(line, progress: progress, done: done)
            if passed != nil { said = Date() }
            return passed
        }
        /// Seconds since a line last reached you; `touch` counts a line said around the gate.
        var quiet: TimeInterval { lock.lock(); defer { lock.unlock() }; return Date().timeIntervalSince(said) }
        func touch() { lock.lock(); said = Date(); lock.unlock() }
    }

    /// The last 400 lines a process printed.
    final class Collected: @unchecked Sendable {
        private var kept: [String] = []
        private let lock = NSLock()
        func add(_ line: String) { lock.lock(); kept.append(line); if kept.count > 400 { kept.removeFirst(kept.count - 400) }; lock.unlock() }
        var lines: [String] { lock.lock(); defer { lock.unlock() }; return kept }
    }

    /// Bytes from a pipe cut into lines at \n or \r (a progress bar redraws its line with \r).
    final class LineSplitter: @unchecked Sendable {
        private var buffer = Data()
        private var finished = false
        private let emit: (String) -> Void
        init(_ emit: @escaping (String) -> Void) { self.emit = emit }

        func feed(_ data: Data) {
            buffer.append(data)
            while let end = buffer.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                let text = String(decoding: buffer[buffer.startIndex ..< end], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex ... end)
                if !text.trimmingCharacters(in: .whitespaces).isEmpty { emit(text) }
            }
        }

        /// The last line without an end; true the first time only (the pipe's end can be seen twice).
        func finish() -> Bool {
            guard !finished else { return false }
            finished = true
            let text = String(decoding: buffer, as: UTF8.self)
            if !text.trimmingCharacters(in: .whitespaces).isEmpty { emit(text) }
            buffer.removeAll()
            return true
        }
    }

    /// Stops a process however it's asked to (cancel or timeout), even before it has started.
    final class Control: @unchecked Sendable {
        private let process: Process
        private let lock = NSLock()
        private var running = false, stopping = false
        init(_ process: Process) { self.process = process }

        func started() {
            lock.lock(); running = true; let stop = stopping; lock.unlock()
            if stop { kill() }
        }

        func stop() {
            lock.lock(); stopping = true; let go = running; lock.unlock()
            if go { kill() }
        }

        private func kill() {
            guard process.isRunning else { return }
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [process] in if process.isRunning { Darwin.kill(pid, SIGKILL) } }
        }
    }
}
