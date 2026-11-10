import Foundation

/// Sage's message box (2026-11-10, you asked for a composer like Claude's that takes media and @ tags as Kino's prompt
/// does): what a tag is in the text, which notes the @ list offers, where attached files are kept, and what Sage is told
/// about both. Foundation only, for the Windows port; the box itself is in SageComposer.swift. Checked in
/// Tests/SageComposerChecks.swift on temp folders.
extension Study {
    // MARK: Tags: a note or file of the vault named in a message, kept as Obsidian's [[link]] to its path

    /// How a tagged note or file is written in the message: a link to its path in the vault, a note without ".md"
    /// ("[[Research/Speed ramps]]", "[[Attachments/shot.png]]").
    static func tagText(_ path: String) -> String {
        "[[" + (extensionOf(path) == ".md" ? String(path.dropLast(3)) : path) + "]]"
    }

    private static let tagPattern = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]+?)\]\]"#)

    /// The [[links]] in a message, in order: where each is and what it names.
    static func tagLinks(in text: String) -> [(range: Range<String.Index>, link: String)] {
        tagPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let whole = Range(match.range, in: text), let link = Range(match.range(at: 1), in: text) else { return nil }
            return (whole, String(text[link]))
        }
    }

    /// The vault's files a message's links name, each once, in the order named; folders and links to nothing left out.
    static func tagged(_ text: String, in items: [VaultItem]) -> [VaultItem] {
        var found: [VaultItem] = []
        for tag in tagLinks(in: text) {
            guard let item = resolve(tag.link, in: items), !item.folder, !found.contains(where: { same($0.path, item.path) }) else { continue }
            found.append(item)
        }
        return found
    }

    /// What a tag's pill shows: the name after "|" when the link gives one, else the file's name (a note without ".md").
    static func tagName(_ link: String) -> String {
        if let bar = link.firstIndex(of: "|") {
            let alias = link[link.index(after: bar)...].trimmingCharacters(in: .whitespaces)
            if !alias.isEmpty { return alias }
        }
        let target = String(link.split(separator: "|", omittingEmptySubsequences: false).first ?? "")
        let name = (target as NSString).lastPathComponent
        return extensionOf(name) == ".md" ? String(name.dropLast(3)) : name
    }

    /// The message as a title or a list shows it: each link as its name ("summarise [[Notes/Foo]]" → "summarise Foo").
    static func tagsShown(_ text: String) -> String {
        var result = text
        for tag in tagLinks(in: text).reversed() { result.replaceSubrange(tag.range, with: tagName(tag.link)) }
        return result
    }

    /// Files whose text the chat's brain can read itself; any other tagged file (a picture, a PDF, a video) is looked at
    /// by Sage with his full tools.
    static let readableTypes = [".md", ".canvas", ".base", ".txt", ".json", ".csv"]
    static func isReadable(_ path: String) -> Bool { readableTypes.contains(extensionOf((path as NSString).lastPathComponent)) }

    /// What the @ list offers for the words typed after @: the vault's files matched as the quick switcher matches them
    /// (`fuzzy`), notes before other files and the ones you opened lately first; with nothing typed, your recent notes,
    /// then the newest. Folders aren't offered.
    static func tagChoices(_ query: String, in items: [VaultItem], recent: [String], count: Int = 8) -> [VaultItem] {
        let words = query.trimmingCharacters(in: .whitespaces)
        var rank: [String: Int] = [:]
        for (index, path) in recent.enumerated() where rank[path.lowercased()] == nil { rank[path.lowercased()] = index }
        var scored: [(item: VaultItem, score: Int)] = []
        for item in items where !item.folder {
            var match = fuzzy(words, item.title)?.score
            if match == nil, words.contains("/") { match = fuzzy(words, item.path).map { $0.score - 30 } }
            guard let match else { continue }
            let note = item.ext == ".md"
            let recency = rank[item.path.lowercased()].map { 60 - $0 * 6 } ?? 0
            scored.append((item, match + recency + (note ? 40 : 0)))
        }
        return Array(scored.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.item.modified != b.item.modified { return a.item.modified > b.item.modified }
            return natural(a.item.title, b.item.title) < 0
        }.prefix(count).map(\.item))
    }

    // MARK: Attached files

    /// What an attached file is, for how it's shown (a picture or a video as a thumbnail, anything else as a chip) and how
    /// Sage is told to look at it.
    enum AttachmentKind: String { case picture, video, audio, pdf, file }

    static let attachedVideoTypes = videoTypes.union([".mkv", ".avi"])
    static let attachedSoundTypes = soundTypes.union([".aiff"])

    static func attachmentKind(_ path: String) -> AttachmentKind {
        let ext = extensionOf((path as NSString).lastPathComponent)
        if pictureTypes.contains(ext) || [".heic", ".tif", ".tiff"].contains(ext) { return .picture }
        if attachedVideoTypes.contains(ext) { return .video }
        if attachedSoundTypes.contains(ext) { return .audio }
        return ext == ".pdf" ? .pdf : .file
    }

    /// Where files attached from outside the vault are copied, so Sage's CLI can read them: attachments/<yyyy-MM-dd>/ in
    /// his folder (the day in your time zone).
    static func attachmentFolder(in place: URL, on date: Date) -> URL {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return place.appendingPathComponent("attachments", isDirectory: true).appendingPathComponent(day.string(from: date), isDirectory: true)
    }

    /// Whether `file` is `folder` or inside it, links followed.
    static func isInside(_ file: URL, _ folder: URL) -> Bool {
        func under(_ path: String, _ base: String) -> Bool { path == base || path.hasPrefix(base.hasSuffix("/") ? base : base + "/") }
        let file = file.standardizedFileURL, folder = folder.standardizedFileURL
        return under(file.path, folder.path) || under(file.resolvingSymlinksInPath().path, folder.resolvingSymlinksInPath().path)
    }

    /// A name no file in the folder has: the file's own, else "name 2.ext", "name 3.ext"… as Finder numbers copies.
    static func freeName(_ name: String, taken: (String) -> Bool) -> String {
        guard taken(name) else { return name }
        let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
        for number in 2 ... 9999 {
            let candidate = "\(stem) \(number)" + (ext.isEmpty ? "" : "." + ext)
            if !taken(candidate) { return candidate }
        }
        return UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
    }

    /// The files attached to a message as Sage keeps them with the chat: one inside the vault, or already in his
    /// attachments folder, stays where it is; any other is copied into the day's attachments folder under a free name
    /// (a clone on APFS: no extra space until one changes). The paths kept, in order, and the names that couldn't be.
    static func keepAttachments(_ files: [URL], vault: URL?, place: URL, date: Date = Date()) -> (paths: [String], failed: [String]) {
        let fm = FileManager.default
        let folder = attachmentFolder(in: place, on: date)
        let root = place.appendingPathComponent("attachments", isDirectory: true)
        var paths: [String] = [], failed: [String] = []
        for file in files {
            let file = file.standardizedFileURL
            guard fm.fileExists(atPath: file.path) else { failed.append(file.lastPathComponent); continue }
            if let vault, isInside(file, vault) { paths.append(file.path); continue }
            if isInside(file, root) { paths.append(file.path); continue }
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = freeName(file.lastPathComponent) { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
                let copy = folder.appendingPathComponent(name)
                try fm.copyItem(at: file, to: copy)
                paths.append(copy.path)
            } catch {
                failed.append(file.lastPathComponent)
            }
        }
        return (paths, failed)
    }

    /// A picture pasted from the clipboard, named as macOS names a screenshot: "Pasted image 2026-11-10 at 14.03.22.png".
    static func pastedName(_ date: Date) -> String {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Pasted image \(stamp.string(from: date)).png"
    }

    // MARK: What Sage is told

    /// The chat's brain is told which notes you tagged (their text follows as "My note <path>"); nothing when none.
    static func taggedPrompt(_ paths: [String]) -> String {
        guard !paths.isEmpty else { return "" }
        return "\nIn my last message, [[links]] tag these files in my vault (paths inside the vault); the text of each note is given below as \"My note <path>\", "
            + "so answer about them without looking them up again:\n" + paths.map { "- \($0)" }.joined(separator: "\n") + "\n"
    }

    /// What Sage's CLI is told about a message's tags and attached files: each with its full path, and how to look at it.
    /// Empty when the message has neither.
    static func composerContext(tagged: [String], files: [String], vault: URL?) -> String {
        var text = ""
        if !files.isEmpty {
            text += "\n\n[Files I attached] Look at each before you answer, with your Read tool (it shows you pictures as images and reads PDFs); "
                + "they are mine to work from, kept outside the vault unless the path is inside it:\n"
            text += files.map { path in
                let how: String
                switch attachmentKind(path) {
                case .picture: how = "picture: look at it"
                case .video: how = "video: you can't watch it directly; take frames or the sound with ffmpeg if you need them"
                case .audio: how = "sound: transcribe or inspect it with your tools if you need to"
                case .pdf: how = "PDF: read it"
                case .file: how = "file"
                }
                return "- \(path) (\(how))"
            }.joined(separator: "\n")
        }
        if !tagged.isEmpty {
            text += "\n\n[Notes and files I tagged] My message names these files of the vault as [[links]] (path in the vault, then the full path); read them as needed:\n"
            text += tagged.map { path in "- \(path)" + (vault.map { " — " + $0.appendingPathComponent(path).path } ?? "") }.joined(separator: "\n")
        }
        return text
    }

    /// The request a message with attached files (or tagged pictures, PDFs, videos) becomes for Sage's CLI: your words
    /// (or, with none, to look at what you attached), then the files.
    static func composerRequest(_ text: String, tagged: [String], files: [String], vault: URL?) -> String {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (words.isEmpty ? "Look at what I attached and tell me what it is and anything worth noting." : words)
            + composerContext(tagged: tagged, files: files, vault: vault)
    }
}
