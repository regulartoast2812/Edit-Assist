import Foundation

/// Sage's message box (2026-11-10): @ tags kept as [[links]] and read back as the vault's files, the @ list's order,
/// attached files kept with the chat (copied out of the way, named as Finder names copies), and what Sage is told.
/// Temp folders only, never your vault.
extension Checks {
    @MainActor static func sageComposer(_ check: Check) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("sage-composer-\(UUID().uuidString)", isDirectory: true).standardizedFileURL
        defer { try? fm.removeItem(at: root) }
        let vault = root.appendingPathComponent("Vault", isDirectory: true), place = root.appendingPathComponent("sage", isDirectory: true)
        let outside = root.appendingPathComponent("Desktop", isDirectory: true)
        for folder in [vault.appendingPathComponent("Notes"), vault.appendingPathComponent("Pics"), outside, place] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        // Tags: written as links to the file's path, read back as the vault's files.
        check(Study.tagText("Research/Speed ramps.md") == "[[Research/Speed ramps]]" && Study.tagText("Pics/shot.png") == "[[Pics/shot.png]]",
              "A tag is kept as a [[link]] to its path in the vault, a note without .md, any other file with its extension")
        check(Study.tagLinks(in: "compare [[A]] with [[Notes/B]]").map(\.link) == ["A", "Notes/B"] && Study.tagLinks(in: "[[no\nlink]] [[ x").isEmpty,
              "The links in a message are found in order; nothing across a line or left open")
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [Study.VaultItem(path: "A.md", folder: false, modified: day), Study.VaultItem(path: "Notes", folder: true),
                     Study.VaultItem(path: "Notes/B.md", folder: false, modified: day.addingTimeInterval(60)),
                     Study.VaultItem(path: "Notes/Speed ramps.md", folder: false, modified: day.addingTimeInterval(-60)),
                     Study.VaultItem(path: "Pics/speed.png", folder: false, modified: day.addingTimeInterval(120)),
                     Study.VaultItem(path: "Pics/Board.canvas", folder: false, modified: day.addingTimeInterval(-120))]
        check(Study.tagged("compare [[A]] with [[B]], [[A]] again, [[Missing]], [[Notes]] and [[speed.png]]", in: items).map(\.path) == ["A.md", "Notes/B.md", "Pics/speed.png"],
              "A message's tags are the vault's files they name, each once, in order; folders and links to nothing left out")
        check(Study.tagName("Notes/B") == "B" && Study.tagName("Pics/x.png") == "x.png" && Study.tagName("Notes/B|Bee") == "Bee" && Study.tagName("Notes/B.md") == "B",
              "A pill shows the note's name (a file's with its extension), or the name a link gives after |")
        check(Study.tagsShown("summarise [[Notes/Foo]] and [[Pics/x.png]]") == "summarise Foo and x.png" && Study.tagsShown("no tags") == "no tags",
              "A message with tags reads with their names in titles and lists")
        var titled = Study.Conversation()
        titled.messages = [Study.Message(fromSage: false, text: "summarise [[Notes/Foo]]")]
        var filesOnly = Study.Conversation()
        var picture = Study.Message(fromSage: false, text: "")
        picture.files = ["/x/attachments/2026-11-10/Pasted image.png"]
        filesOnly.messages = [picture]
        check(titled.title == "summarise Foo" && filesOnly.title == "Pasted image.png", "A chat is titled by its first message with tags as names, or by its first file when it has no words")
        check(Study.isReadable("A.md") && Study.isReadable("Pics/Board.canvas") && !Study.isReadable("Pics/speed.png") && !Study.isReadable("doc.pdf"),
              "Notes, canvases and bases are read by the chat itself; pictures, PDFs and videos go to Sage's full tools")

        // The @ list: the vault's files as the quick switcher matches them, notes first, your recent ones first.
        check(Study.tagChoices("", in: items, recent: ["Notes/Speed ramps.md"]).map(\.path) == ["Notes/Speed ramps.md", "Notes/B.md", "A.md", "Pics/speed.png", "Pics/Board.canvas"],
              "With nothing typed after @: your recent notes, then the other notes newest first, then other files; no folders")
        check(Study.tagChoices("speed", in: items, recent: []).map(\.path) == ["Notes/Speed ramps.md", "Pics/speed.png"],
              "A word typed after @ matches names as the quick switcher does, a note before a picture that matches as well")
        check(Study.tagChoices("spdrm", in: items, recent: []).first?.path == "Notes/Speed ramps.md" && Study.tagChoices("zzz", in: items, recent: []).isEmpty
              && Study.tagChoices("pics/bo", in: items, recent: []).first?.path == "Pics/Board.canvas",
              "Letters in order find a note (Obsidian's fuzzy search), a folder path finds its files, nothing matching lists nothing")
        check(Study.tagChoices("", in: items, recent: [], count: 2).count == 2, "The @ list is kept short")

        // Attached files: what they are, where they're kept, how copies are named.
        check(Study.attachmentKind("a.PNG") == .picture && Study.attachmentKind("b.heic") == .picture && Study.attachmentKind("c.MOV") == .video
              && Study.attachmentKind("d.mp3") == .audio && Study.attachmentKind("e.pdf") == .pdf && Study.attachmentKind("f.zip") == .file && Study.attachmentKind("README") == .file,
              "An attached file is a picture, a video, a sound, a PDF or another file, by its extension")
        let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 14, minute: 3, second: 22))!
        check(Study.attachmentFolder(in: place, on: noon) == place.appendingPathComponent("attachments/2026-11-10", isDirectory: true),
              "Files attached from outside the vault are kept in sage/attachments/<day>/")
        check(Study.pastedName(noon) == "Pasted image 2026-11-10 at 14.03.22.png", "A pasted picture is named as macOS names a screenshot")
        let taken: Set<String> = ["a.png", "a 2.png", "README"]
        check(Study.freeName("a.png") { taken.contains($0) } == "a 3.png" && Study.freeName("README") { taken.contains($0) } == "README 2"
              && Study.freeName("new.pdf") { taken.contains($0) } == "new.pdf",
              "A copy takes the file's own name, else the first free \"name 2.ext\", as Finder numbers copies")
        check(Study.isInside(vault.appendingPathComponent("Notes/B.md"), vault) && !Study.isInside(root.appendingPathComponent("Vault2/x.md"), vault),
              "Inside the vault means under its folder, not a folder whose name starts the same")

        let inVault = vault.appendingPathComponent("Pics/speed.png")
        try Data([1, 2, 3]).write(to: inVault)
        let shot = outside.appendingPathComponent("shot.png"), other = root.appendingPathComponent("shot.png"), report = outside.appendingPathComponent("report.pdf")
        try Data([4, 5]).write(to: shot); try Data([6]).write(to: other); try Data([7, 8, 9]).write(to: report)
        let kept = Study.keepAttachments([inVault, shot, other, report, outside.appendingPathComponent("gone.mov")], vault: vault, place: place, date: noon)
        let folder = Study.attachmentFolder(in: place, on: noon)
        check(kept.paths == [inVault.path, folder.appendingPathComponent("shot.png").path, folder.appendingPathComponent("shot 2.png").path, folder.appendingPathComponent("report.pdf").path]
              && kept.failed == ["gone.mov"],
              "A file in the vault is kept where it is; one from outside is copied into the day's folder, a second of the same name as \"name 2\"; a missing one is said")
        check((try? Data(contentsOf: folder.appendingPathComponent("shot 2.png"))) == Data([6]) && (try? Data(contentsOf: shot)) == Data([4, 5]) && fm.fileExists(atPath: report.path),
              "The copies hold the files' bytes, and the originals are left where they were")
        let again = Study.keepAttachments([folder.appendingPathComponent("shot.png")], vault: vault, place: place, date: noon.addingTimeInterval(86_400))
        check(again.paths == [folder.appendingPathComponent("shot.png").path] && !fm.fileExists(atPath: Study.attachmentFolder(in: place, on: noon.addingTimeInterval(86_400)).path),
              "A file already in Sage's attachments (pasted earlier) is not copied again")

        // What Sage is told.
        check(Study.taggedPrompt([]).isEmpty && Study.taggedPrompt(["Notes/B.md", "A.md"]).contains("tag these files in my vault") && Study.taggedPrompt(["Notes/B.md"]).contains("\n- Notes/B.md\n"),
              "The chat's brain is told the paths of the notes tagged (their text comes as notes it read)")
        let context = Study.composerContext(tagged: ["Notes/B.md"], files: [folder.appendingPathComponent("shot.png").path, folder.appendingPathComponent("report.pdf").path, "/x/clip.mov"], vault: vault)
        check(context.contains("[Files I attached]") && context.contains("Read tool") && context.contains("- \(folder.appendingPathComponent("shot.png").path) (picture: look at it)")
              && context.contains("report.pdf (PDF: read it)") && context.contains("clip.mov (video:")
              && context.contains("[Notes and files I tagged]") && context.contains("- Notes/B.md — \(vault.appendingPathComponent("Notes/B.md").path)"),
              "Sage's CLI is told each attached file's full path and how to look at it, and each tag's path in the vault and on disk")
        check(Study.composerContext(tagged: [], files: [], vault: vault).isEmpty, "A plain message adds nothing to Sage's request")
        let request = Study.composerRequest("  what's in this?  ", tagged: [], files: ["/a/b.png"], vault: nil)
        check(request.hasPrefix("what's in this?\n\n[Files I attached]") && Study.composerRequest("", tagged: [], files: ["/a/b.png"], vault: nil).hasPrefix("Look at what I attached"),
              "A message with files goes to the CLI as your words, then the files; with no words, to look at them")
        var settings = Study.AgentSettings()
        settings.claudeModel = "opus"
        let arguments = Study.claudeArguments(settings, session: "S1", resume: false, folders: [place.appendingPathComponent("attachments").path])
        check(arguments.contains("--add-dir") && arguments[arguments.firstIndex(of: "--add-dir")! + 1] == place.appendingPathComponent("attachments").path
              && Array(arguments.suffix(2)) == ["--session-id", "S1"] && !Study.claudeArguments(settings, session: "S1", resume: false).contains("--add-dir"),
              "Claude may read Sage's attachments folder when a request has files there; otherwise its arguments are as before")

        // Kept with the chat: old chats (no files) still read; new ones keep their files.
        let old = #"{"id":"6B1E6E0C-8C47-4F59-9C59-3D0D7E7B1E11","fromSage":false,"text":"hi","videos":[],"notes":[],"date":0}"#
        let decoded = try JSONDecoder().decode(Study.Message.self, from: Data(old.utf8))
        let round = try JSONDecoder().decode(Study.Message.self, from: JSONEncoder().encode(picture))
        check(decoded.files == nil && decoded.text == "hi" && round.files == picture.files, "A message's files are kept in chats.json, and chats from before still open")
    }
}
