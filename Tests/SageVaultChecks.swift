import Foundation

/// Sage's vault browser, files and editing (2026-11-09, brought back from Creative Assist): checked on temp folders, never your vault.
extension Checks {
    typealias Check = (_ condition: @autoclosure () -> Bool, _ name: String) -> Void

    @MainActor static func sageVault(_ check: Check) throws {
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("sage-vault-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: vault) }
        func put(_ path: String, _ text: String) throws {
            let file = vault.appendingPathComponent(path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }
        try put(".obsidian/app.json", #"{"propertiesInDocument":"hidden","showInlineTitle":false,"trashOption":"local"}"#)
        try put(".obsidian/workspace.json", #"{"left":{"children":[{"type":"leaf","state":{"type":"file-explorer","state":{"sortOrder":"alphabeticalReverse"}}}]}}"#)
        try put("Attachments/pho bowl.png", "png")
        try put("Attachments/notes.zip", "zip")
        try put(".trash/gone.md", "gone")
        try put("K/K10.md", ""); try put("K/K2.md", ""); try put("K/Deep/Broth.md", "")
        try put("Soups/Pho.md", "# Pho")
        let items = Study.vaultItems(vault)
        check(items.contains { $0.path == "Attachments/pho bowl.png" } && items.contains { $0.path == "K/Deep" && $0.folder } && !items.contains { $0.path.hasPrefix(".") }
              && !items.contains { $0.path.hasSuffix(".zip") },
              "The vault is listed as Obsidian's explorer lists it: no hidden folders, no unknown file types")
        check(Study.explorerOrder(vault) == "alphabeticalReverse" && Study.explorerOrder(fm.temporaryDirectory) == "alphabetical"
              && Study.children(items, folder: "K", order: "alphabetical").map(\.title) == ["Deep", "K2", "K10"]
              && Study.children(items, folder: "K", order: "alphabeticalReverse").map(\.title) == ["Deep", "K10", "K2"],
              "The explorer's order: folders first, names as a person reads them, the vault's sort from workspace.json")
        check(Study.resolve("Broth", in: items)?.path == "K/Deep/Broth.md" && Study.resolve("Deep/Broth#Stock|soup", in: items)?.path == "K/Deep/Broth.md"
              && Study.resolve("Pho", in: items)?.path == "Soups/Pho.md" && Study.resolve("pho bowl.png", in: items)?.path == "Attachments/pho bowl.png"
              && Study.resolve("Nothing", in: items) == nil
              && Study.relative("../Attachments/pho%20bowl.png", from: "K/Deep/Broth.md") == "K/Attachments/pho bowl.png" && Study.relative("../../../x.png", from: "K/a.md") == nil,
              "A [[link]] finds its file as Obsidian does: by name anywhere, by path, nearest first; headings and aliases aside")
        check(Study.vaultAddress("Soups/Phở bò#1.md") == "sage://sage/vault/Soups/Ph%E1%BB%9F%20b%C3%B2%231.md", "The note view finds a vault file at its own address")

        // Links follow a moved or renamed file, as Obsidian's "update internal links" does.
        let files = [
            "A/Plan.md": "See [[Pho]], [[Pho#Broth|the broth]] and ![[Soups/Pho]] and [[Soups/Pho.md]]. Also [pic](../Media/bowl%20one.png) and [x](Soups/Pho.md)",
            "Soups/Pho.md": "Pho. Back to [[Plan]]. Picture: ![b](../Media/bowl%20one.png)",
            "Soups/Bun.md": "Bun, near [[Pho]]",
            "Media/bowl one.png": "",
        ]
        let listed = files.keys.map { Study.VaultItem(path: $0, folder: false) } + ["A", "Soups", "Media"].map { Study.VaultItem(path: $0, folder: true) }
        let read = { (path: String) in files[path] }
        let renamed = Dictionary(uniqueKeysWithValues: Study.relink(listed, moves: ["Soups/Pho.md": "Soups/Phở bò.md"], read: read).map { ($0.path, $0.text) })
        check(renamed["A/Plan.md"] == "See [[Phở bò]], [[Phở bò#Broth|the broth]] and ![[Soups/Phở bò]] and [[Soups/Phở bò.md]]. Also [pic](../Media/bowl%20one.png) and [x](Soups/Ph%E1%BB%9F%20b%C3%B2.md)"
              && renamed["Soups/Bun.md"] == "Bun, near [[Phở bò]]" && renamed["Soups/Pho.md"] == nil,
              "A renamed note's links follow it, every way they were written, alias and heading kept")
        let moved = Dictionary(uniqueKeysWithValues: Study.relink(listed, moves: ["Soups/Pho.md": "Food/Soups/Pho.md"], read: read).map { ($0.path, $0.text) })
        check(moved["A/Plan.md"]?.hasPrefix("See [[Pho]], [[Pho#Broth|the broth]] and ![[Food/Soups/Pho]] and [[Food/Soups/Pho.md]]") == true
              && moved["A/Plan.md"]?.hasSuffix("[x](Food/Soups/Pho.md)") == true
              && moved["Soups/Pho.md"] == "Pho. Back to [[Plan]]. Picture: ![b](../../Media/bowl%20one.png)" && moved["Soups/Bun.md"] == nil,
              "A moved note: links by name stay, by path follow, its own relative links are redone")
        let folder = Dictionary(uniqueKeysWithValues: Study.relink(listed, moves: ["Soups": "Recipes/Soups"], read: read).map { ($0.path, $0.text) })
        check(folder["A/Plan.md"]?.contains("![[Recipes/Soups/Pho]]") == true && Study.movedPath("Soups/Bun.md", ["Soups": "Recipes/Soups"]) == "Recipes/Soups/Bun.md"
              && Study.movedPath("Soupsy/x.md", ["Soups": "R"]) == "Soupsy/x.md" && Study.relativeFrom("A/B/n.md", "A/C/x.png") == "../C/x.png",
              "A moved folder takes what's inside it, and the links to it follow")

        check(Study.nameProblem("Pho bò") == nil && Study.nameProblem("a/b") != nil && Study.nameProblem("x:") != nil && Study.nameProblem(" ") != nil
              && Study.nameProblem(".hidden") != nil && Study.nameProblem("CON") != nil && Study.nameProblem("a#b") != nil && Study.nameProblem("ends.") != nil
              && Study.nameRule("a:b")?.value == ":",
              "New names are checked as the Mac, Windows and Obsidian need")
        let taken: Set<String> = ["Untitled.md", "Untitled 1.md"]
        check(Study.freeName(taken: taken.contains, stem: "Untitled", extension: ".md") == "Untitled 2.md" && Study.freeName(taken: taken.contains, stem: "Pho", extension: ".md") == "Pho.md",
              "A free name is found for a new note")
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 11, day: 8, hour: 9, minute: 5).date!
        check(Study.applyTemplate("# {{title}}\n{{date}} {{time}} {{date:YYYY/MM/DD}} {{ date:dddd, MMMM D }}", title: "Pho", now: now, dateFormat: "DD-MM-YYYY")
              == "# Pho\n08-11-2026 09:05 2026/11/08 Sunday, November 8" && Study.momentPattern("YYYY-MM-DD [week] HH:mm") == "yyyy-MM-dd 'week' HH:mm",
              "A note from a template fills in {{title}}, {{date}} and {{time}} in Obsidian's formats")
        if let whole = Study.fuzzy("brand", "Brand Equity"), let scattered = Study.fuzzy("bre", "Brand Equity"),
           let early = Study.fuzzy("eq", "Brand Equity"), let late = Study.fuzzy("eq", "Frequency of brand equity") {
            check(whole.at == [0, 1, 2, 3, 4] && scattered.at == [0, 1, 6] && whole.score > scattered.score && Study.fuzzy("xyz", "Brand") == nil && early.score > late.score,
                  "The quick switcher matches as Obsidian's does: letters in order, whole words first")
        } else { check(false, "The quick switcher matches as Obsidian's does: letters in order, whole words first") }
        let names = ["Business", "Content & Copywriting", "Creative Strategy", "Lead Generation", "Metrics", "Performance Marketing", "Sales", "Strategy",
                     "Branding", "Library", "Quests", "Personal", "Clippings", "Creators", "Inbox", "Templates", "System", "Attachments"]
        check(Study.hue("Strategy") == Study.hue("strategy") && Study.hue("Strategy") == Study.hue("🗺️ Strategy") && Study.hue(" Strategy ") == Study.hue("Strategy")
              && Set(names.map(Study.hue)).count >= 6 && names.map(Study.hue).allSatisfy { (0 ..< 8).contains($0) },
              "A name keeps one colour everywhere, whatever its case or leading emoji; names spread over all eight")
        check(Study.leadingEmoji("🗺️ Strategy").map { $0 == ("🗺️", "Strategy") } == true && Study.leadingEmoji("📋 Inbox")?.name == "Inbox"
              && Study.leadingEmoji("Strategy") == nil && Study.leadingEmoji("🗺️") == nil && Study.leadingEmoji("2026 plan") == nil,
              "A leading emoji is told from the name after it")

        // The tree's changes to the vault: a move rewrites the links to it and can be undone; delete goes to the vault's trash, kept first.
        let place = fm.temporaryDirectory.appendingPathComponent("sage-place-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: place) }
        try put("A/Plan.md", "See [[Soups/Pho]]")
        let desk = SageVaultDesk(place: place)
        desk.use(vault)
        desk.readNow()
        check(desk.inVault(vault.appendingPathComponent("A/Plan.md")) == "A/Plan.md" && desk.inVault(fm.temporaryDirectory) == nil, "Files are known by their path in the vault")
        let movedOK = desk.move(["Soups/Pho.md"], into: "K")
        let plan = try String(contentsOf: vault.appendingPathComponent("A/Plan.md"), encoding: .utf8)
        check(movedOK && fm.fileExists(atPath: vault.appendingPathComponent("K/Pho.md").path) && plan == "See [[K/Pho]]"
              && fm.fileExists(atPath: place.appendingPathComponent("edited").path),
              "Moving a note from the tree takes the links to it along, the note as it was kept first")
        desk.readNow()
        check(!desk.move(["K/Deep"], into: "K/Deep") && fm.fileExists(atPath: vault.appendingPathComponent("K/Deep/Broth.md").path)
              && !desk.move(["K/K2.md"], into: "K") && desk.changes.count == 1,
              "Nothing moves into itself, and a move to where it already is changes nothing")
        try put("Soups/K10.md", "other")
        desk.readNow()
        check(!desk.move(["K/K10.md"], into: "Soups") && fm.fileExists(atPath: vault.appendingPathComponent("K/K10.md").path), "Nothing is moved over something already there")
        desk.readNow(); _ = desk.undo()
        check(fm.fileExists(atPath: vault.appendingPathComponent("Soups/Pho.md").path)
              && ((try? String(contentsOf: vault.appendingPathComponent("A/Plan.md"), encoding: .utf8)) ?? "") == "See [[Soups/Pho]]",
              "Undo puts a moved note back and its links as they were")
        desk.readNow()
        check(desk.rename("Soups/Pho.md", to: "Phở") && fm.fileExists(atPath: vault.appendingPathComponent("Soups/Phở.md").path)
              && ((try? String(contentsOf: vault.appendingPathComponent("A/Plan.md"), encoding: .utf8)) ?? "") == "See [[Soups/Phở]]" && !desk.rename("Soups/Phở.md", to: "a:b"),
              "Renaming keeps the .md and the links; a name the vault can't hold is refused")
        desk.readNow()
        desk.delete(["Soups/Phở.md"])
        let trashed = (try? fm.contentsOfDirectory(atPath: vault.appendingPathComponent(".trash").path)) ?? []
        check(!fm.fileExists(atPath: vault.appendingPathComponent("Soups/Phở.md").path) && trashed.contains("Phở.md")
              && fm.fileExists(atPath: place.appendingPathComponent("edited/deleted").path),
              "Delete follows the vault's trash setting (its .trash), a copy kept first")
        desk.readNow(); _ = desk.undo()
        check(fm.fileExists(atPath: vault.appendingPathComponent("Soups/Phở.md").path), "Undo brings a deleted note back from its copy")
        desk.readNow()
        let made = desk.newNote(in: "K")
        check(made == "K/Untitled.md" && desk.note?.lastPathComponent == "Untitled.md" && desk.tabs.count == 1, "A new note is made where asked and opens in a tab")
        desk.openInNewTab(path: "K/K2.md")
        desk.openInNewTab(path: "K/K10.md", behind: true)
        check(desk.tabs.map(\.file.lastPathComponent) == ["Untitled.md", "K2.md", "K10.md"] && desk.note?.lastPathComponent == "K2.md", "Notes open in tabs beside the one shown, or behind it")
        desk.show(path: "Soups/Phở.md")
        desk.goBack()
        check(desk.note?.lastPathComponent == "K2.md" && desk.canGoForward, "Each tab has back and forward")
        let shown = desk.tab!.id
        desk.closeTab(shown)
        check(desk.note?.lastPathComponent == "K10.md" && desk.canReopen, "Closing the shown tab shows the one to its right")
        desk.reopenClosedTab()
        check(desk.note?.lastPathComponent == "K2.md" && desk.tabs.count == 3, "A closed tab opens again where it was")
        let again = SageVaultDesk(place: place)
        check(again.tabs.map(\.file.lastPathComponent) == ["Untitled.md", "K2.md", "K10.md"] && again.note?.lastPathComponent == "K2.md", "The tabs are kept for the next time")
    }
}
