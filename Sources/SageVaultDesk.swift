import AppKit
import CoreServices
import Foundation

/// A tab in the notes stage (2026-11-08 in Creative Assist), as in Obsidian: the file it shows, and where you've been in
/// it (back and forward, for this run only).
struct SageTab: Identifiable, Equatable {
    let id = UUID()
    var file: URL
    var back: [URL] = []
    var forward: [URL] = []
}

/// One change you made to the vault from the tree, kept so it can be undone: files moved (and the notes whose links were
/// rewritten for it), files deleted (each copied first), files made.
struct FileChange: Identifiable {
    let id = UUID()
    var said = ""
    var moves: [(from: String, to: String)] = []
    var edits: [(file: String, before: String, after: String)] = []
    var deleted: [(path: String, kept: URL)] = []
    var made: [(path: String, text: String)] = []
}

/// Sage's notes stage (2026-11-07 in Creative Assist, brought back to the Mac 2026-11-09): your whole Obsidian vault as
/// Obsidian's file explorer shows it, the files open in tabs, and the changes you make to it from the tree. What it
/// decides about files is in `Study` (SageVault.swift, SageFiles.swift); this keeps what you chose, in sage/notes.json
/// beside Sage's other files.
@MainActor final class SageVaultDesk: ObservableObject {
    /// What the notes stage remembers (Creative Assist's sage.json; the Mac keeps it apart from UserDefaults' stage and topic).
    struct Settings: Codable {
        /// The Obsidian vault the notes stage browses; nil until you choose it.
        var vault: String?
        /// The folders open in the vault's tree, by their path from the vault.
        var expanded: [String] = []
        /// The notes open as tabs (full paths), in order, and which one is shown.
        var tabs: [String] = []
        var activeTab = 0
        /// The explorer as you set it: its sort (nil: the vault's), folders first, notes only, whether it follows the open
        /// file, the notes you pinned and opened lately, and which of those sections are open.
        var sort: String?
        var foldersFirst = true
        var notesOnly = false
        var follow = true
        var pinned: [String] = []
        var recent: [String] = []
        var pinnedOpen = true
        var recentOpen = true
        /// Colours you gave folders in Sage's tree (red … pink, or "none"), by their path in the vault.
        var folderColors: [String: String] = [:]
        /// The vault's tree as wide as you dragged it (nil: as it starts, 250 points).
        var treeWidth: Double?

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            vault = try c.decodeIfPresent(String.self, forKey: .vault)
            expanded = try c.decodeIfPresent([String].self, forKey: .expanded) ?? []
            tabs = try c.decodeIfPresent([String].self, forKey: .tabs) ?? []
            activeTab = try c.decodeIfPresent(Int.self, forKey: .activeTab) ?? 0
            sort = try c.decodeIfPresent(String.self, forKey: .sort)
            foldersFirst = try c.decodeIfPresent(Bool.self, forKey: .foldersFirst) ?? true
            notesOnly = try c.decodeIfPresent(Bool.self, forKey: .notesOnly) ?? false
            follow = try c.decodeIfPresent(Bool.self, forKey: .follow) ?? true
            pinned = try c.decodeIfPresent([String].self, forKey: .pinned) ?? []
            recent = try c.decodeIfPresent([String].self, forKey: .recent) ?? []
            pinnedOpen = try c.decodeIfPresent(Bool.self, forKey: .pinnedOpen) ?? true
            recentOpen = try c.decodeIfPresent(Bool.self, forKey: .recentOpen) ?? true
            folderColors = try c.decodeIfPresent([String: String].self, forKey: .folderColors) ?? [:]
            treeWidth = try c.decodeIfPresent(Double.self, forKey: .treeWidth)
        }
    }

    weak var desk: SageDesk?
    @Published private(set) var settings: Settings
    @Published private(set) var tabs: [SageTab] = []
    @Published private(set) var activeTab = 0
    /// Everything in the vault the explorer shows, and its sort.
    @Published private(set) var items: [Study.VaultItem] = []
    @Published private(set) var explorerOrder = "alphabetical"
    /// Your vault's look in Obsidian (theme, accent, fonts, snippets, reading-view settings), read from the vault.
    @Published private(set) var look = Study.Look()
    /// Goes up each time the vault is read again, so the tree is rebuilt only then.
    @Published private(set) var version = 0
    @Published private(set) var reading = false
    /// The vault the picker would start in, offered before you choose one.
    @Published private(set) var suggested: URL?
    /// A folder or file to bring into sight in the tree and light (the path, and a count so the same one lights again).
    @Published private(set) var spotlight: (path: String, count: Int)?
    /// The last change made, to say it and offer Undo; or why one couldn't be made.
    @Published private(set) var said: (text: String, undo: Bool, count: Int)?

    /// What the tree and the note view share on screen: a note previewed (Cmd held over a row in the tree or a link in a
    /// note; `at` is where in the note view, nil beside the tree), the quick switcher (to open a file, or to pick the folder
    /// files move to), and the row being renamed in place.
    struct Preview: Equatable { var path: String; var at: CGPoint? }
    enum Switcher: Equatable { case open, move([String]) }
    @Published var preview: Preview?
    @Published var switcher: Switcher?
    @Published var renaming: String?

    /// Tabs closed this run, the last first, to open again (Cmd+Shift+T).
    private var closed: [(file: URL, at: Int)] = []
    var canReopen: Bool { !closed.isEmpty }
    /// A tab you closed goes away: the note view lets go of its page.
    var onTabClosed: ((UUID) -> Void)?
    var changes: [FileChange] = []

    private let settingsFile: URL
    private var stream: FSEventStreamRef?
    private var watching: URL?
    private var rescan: DispatchWorkItem?

    init(place: URL) {
        settingsFile = place.appendingPathComponent("notes.json")
        settings = (try? Data(contentsOf: settingsFile)).flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
        tabs = settings.tabs.filter { !$0.isEmpty }.map { SageTab(file: URL(fileURLWithPath: $0)) }
        activeTab = min(max(0, settings.activeTab), max(0, tabs.count - 1))
    }

    /// Where a note you edit is kept as it was first (for 30 days), in Sage's own folder.
    var editsKept: URL { settingsFile.deletingLastPathComponent().appendingPathComponent("edited", isDirectory: true) }

    private func save() {
        settings.tabs = tabs.map(\.file.path)
        settings.activeTab = activeTab
        try? FileManager.default.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(settings).write(to: settingsFile, options: .atomic)
    }

    // MARK: The vault

    /// The vault you chose, while it is still one (a folder holding .obsidian).
    var vault: URL? {
        guard let path = settings.vault, FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".obsidian")) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Asks for the vault; a folder inside one is taken as its vault. False when you cancel or it is no vault.
    @discardableResult func chooseVault() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = L("Choose your Obsidian vault")
        panel.prompt = L("Use this vault")
        panel.directoryURL = vault ?? suggested
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return use(url)
    }

    @discardableResult func use(_ folder: URL) -> Bool {
        guard let found = Study.vault(of: folder) else {
            desk?.failure = L("That folder isn't in an Obsidian vault: a vault has an .obsidian folder."); return false
        }
        let path = found.standardizedFileURL.path
        if path != settings.vault {
            settings.vault = path; settings.expanded = []
            // Tabs from another vault close (a topic's own notes stay).
            let recipes = Set(desk?.recipes.map(\.file.standardizedFileURL.path) ?? [])
            let gone = tabs.filter { !$0.file.standardizedFileURL.path.hasPrefix(path + "/") && !recipes.contains($0.file.standardizedFileURL.path) }
            tabs.removeAll { tab in gone.contains { $0.id == tab.id } }
            gone.forEach { onTabClosed?($0.id) }
            activeTab = min(activeTab, max(0, tabs.count - 1))
            save()
        }
        desk?.failure = nil
        reload()
        return true
    }

    /// The vault read off the main thread (its files, explorer sort and look), then watched for changes.
    func reload() {
        guard let vault else {
            items = []; stopWatching()
            // The one to offer: the topic folder's vault, else one found in Documents (a short walk, off the main thread).
            if suggested == nil {
                let folder = desk?.folder
                Task {
                    let found = await Task.detached { folder.flatMap(Study.vault(of:)) ?? Self.findVault() }.value
                    suggested = found
                }
            }
            return
        }
        if items.isEmpty { reading = true }
        Task {
            let (found, order, look) = await Task.detached { (Study.vaultItems(vault), Study.explorerOrder(vault), Study.look(vault: vault)) }.value
            reading = false
            guard self.vault == vault else { return }
            items = found; explorerOrder = order; self.look = look; version += 1
            if let open = note { reveal(open) }
            watch(vault)
        }
    }

    /// The vault read at once, on this thread, without watching it (the checks, on a temp vault).
    func readNow() {
        guard let vault else { items = []; return }
        items = Study.vaultItems(vault); explorerOrder = Study.explorerOrder(vault); look = Study.look(vault: vault); version += 1
    }

    /// An Obsidian vault (a folder holding .obsidian) in Documents, iCloud's Obsidian folder or the home folder, up to 3
    /// levels down. A vault named like Obsidian's own folder wins over a test vault elsewhere.
    nonisolated static func findVault() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let places = [home.appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents"), home.appendingPathComponent("Documents"), home]
        var found: [URL] = []
        func look(_ folder: URL, _ depth: Int) {
            guard depth <= 3 else { return }
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".obsidian").path) { found.append(folder); return }
            for child in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? [] {
                let name = child.lastPathComponent
                if ["node_modules", "Library", "Applications", "Pictures", "Music", "Movies"].contains(name) { continue }
                if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { look(child, depth + 1) }
            }
        }
        for place in places where FileManager.default.fileExists(atPath: place.path) { look(place, place == home ? 2 : 0) }
        return found.min { a, b in
            let ao = a.path.localizedCaseInsensitiveContains("obsidian"), bo = b.path.localizedCaseInsensitiveContains("obsidian")
            return ao != bo ? ao : a.path.count < b.path.count
        }
    }

    /// The vault watched with FSEvents; many changes at once (a sync, a move) are read once, 0.6 s after the last.
    /// .obsidian counts (a theme or setting changed, but not workspace.json); other hidden folders (.trash, .git) don't.
    private func watch(_ vault: URL) {
        if stream != nil && watching == vault { return }
        stopWatching()
        let root = vault.standardizedFileURL.path
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let desk = Unmanaged<SageVaultDesk>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            DispatchQueue.main.async { MainActor.assumeIsolated { desk.heard(Array(list.prefix(count))) } }
        }
        guard let made = FSEventStreamCreate(nil, callback, &context, [root] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                             FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)) else { return }
        FSEventStreamSetDispatchQueue(made, .main)
        FSEventStreamStart(made)
        stream = made; watching = vault
    }

    private func heard(_ paths: [String]) {
        guard let root = watching?.standardizedFileURL.path else { return }
        let counts = paths.contains { full in
            let relative = full.count > root.count ? String(full.dropFirst(root.count + 1)) : ""
            if relative.hasPrefix(".obsidian/workspace") { return false }
            return !relative.hasPrefix(".") || relative.hasPrefix(".obsidian")
        }
        guard counts else { return }
        rescan?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.reload() } }
        rescan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func stopWatching() {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        stream = nil; watching = nil
    }

    /// A file's path from the vault ("Quests/Edit Assist.md"), or nil when it is not in the vault.
    func inVault(_ file: URL) -> String? {
        guard let vault else { return nil }
        let root = vault.standardizedFileURL.path, full = file.standardizedFileURL.path
        guard full.count > root.count + 1, full.lowercased().hasPrefix(root.lowercased() + "/") else { return nil }
        return String(full.dropFirst(root.count + 1))
    }

    func full(_ path: String) -> URL { (vault ?? URL(fileURLWithPath: "/")).appendingPathComponent(path) }

    func item(_ path: String) -> Study.VaultItem? { items.first { Study.same($0.path, path) } }

    // MARK: The tree

    var expanded: [String] { settings.expanded }
    func isOpen(_ folder: String) -> Bool { settings.expanded.contains(folder) }

    /// Opens or closes a folder in the tree; remembered.
    @discardableResult func toggle(_ folder: String) -> Bool {
        let open = !settings.expanded.contains(folder)
        if open { settings.expanded.append(folder) } else { settings.expanded.removeAll { $0 == folder } }
        save()
        return open
    }

    func setOpen(_ folder: String, _ open: Bool) { if isOpen(folder) != open { toggle(folder) } }

    /// Closes every folder.
    func collapseAll() { settings.expanded = []; save(); version += 1 }

    /// Closes every folder but those the open file is in.
    func collapseOthers() {
        settings.expanded = []
        if let open = note, let path = inVault(open) { settings.expanded = folders(above: path) }
        save(); version += 1
    }

    /// The folders a path is in, the outermost first ("A/B/c.md" → "A", "A/B").
    func folders(above path: String) -> [String] {
        let parts = path.components(separatedBy: "/")
        return parts.count < 2 ? [] : (1 ..< parts.count).map { parts[..<$0].joined(separator: "/") }
    }

    /// Opens the folders a file is in, as Obsidian reveals the active file.
    private func reveal(_ file: URL) {
        guard let path = inVault(file) else { return }
        seen(path)
        guard settings.follow else { return }
        for folder in folders(above: path) where !settings.expanded.contains(folder) { settings.expanded.append(folder) }
    }

    /// Opens the folders a file or folder is in (not itself), so its row shows; true when one opened.
    @discardableResult func openFolders(above path: String) -> Bool {
        let missing = folders(above: path).filter { !settings.expanded.contains($0) }
        settings.expanded += missing
        if !missing.isEmpty { save() }
        return !missing.isEmpty
    }

    /// Opens a folder and those it is in, as when you open it yourself.
    func revealFolder(_ path: String) {
        for folder in folders(above: path) + [path] where !settings.expanded.contains(folder) { settings.expanded.append(folder) }
        save()
    }

    /// A folder or file shown in the tree: the folders it's in open, then the tree brings its row into sight and lights it.
    func showInTree(_ path: String) {
        openFolders(above: path)
        spotlight = (path, (spotlight?.count ?? 0) + 1)
    }

    /// The sort: yours, else the vault's (workspace.json), as Obsidian names them.
    var sort: String { settings.sort ?? explorerOrder }
    func setSort(_ sort: String) { settings.sort = sort; save(); version += 1 }
    func setFoldersFirst(_ on: Bool) { settings.foldersFirst = on; save(); version += 1 }
    func setNotesOnly(_ on: Bool) { settings.notesOnly = on; save(); version += 1 }
    func setFollow(_ on: Bool) {
        settings.follow = on; save()
        if on, let open = note { reveal(open); save() }
        version += 1
    }
    var pinnedOpen: Bool { get { settings.pinnedOpen } set { settings.pinnedOpen = newValue; save() } }
    var recentOpen: Bool { get { settings.recentOpen } set { settings.recentOpen = newValue; save() } }
    var treeWidth: Double? { get { settings.treeWidth } set { settings.treeWidth = newValue; save() } }

    /// The files the tree shows: all of them, or with "Notes only" just notes, canvases and bases (and folders).
    func shown(_ item: Study.VaultItem) -> Bool { item.folder || !settings.notesOnly || [".md", ".canvas", ".base"].contains(item.ext) }

    /// What a folder holds as the tree shows it: the sort, folders first (or mixed in by name), notes only.
    func children(of folder: String) -> [Study.VaultItem] {
        let here = Study.children(items, folder: folder, order: sort).filter(shown)
        guard !settings.foldersFirst else { return here }
        return here.sorted(by: Study.fileOrder(sort))
    }

    /// A file you opened, first among the recent ones (eight kept).
    private func seen(_ path: String) {
        if let first = settings.recent.first, Study.same(first, path) { return }
        settings.recent.removeAll { Study.same($0, path) }
        settings.recent.insert(path, at: 0)
        if settings.recent.count > 8 { settings.recent.removeLast(settings.recent.count - 8) }
    }

    /// The colour you gave a folder ("red" … "pink", "none"), or nil: its own colour, or the one it inherits.
    func folderColor(_ path: String) -> String? { settings.folderColors.first { Study.same($0.key, path) }?.value }
    func setFolderColor(_ path: String, _ color: String?) {
        settings.folderColors = settings.folderColors.filter { !Study.same($0.key, path) }
        if let color { settings.folderColors[path] = color }
        save(); version += 1
    }

    func isPinned(_ path: String) -> Bool { settings.pinned.contains { Study.same($0, path) } }
    func togglePin(_ path: String) {
        if isPinned(path) { settings.pinned.removeAll { Study.same($0, path) } } else { settings.pinned.append(path) }
        save(); version += 1
    }

    /// The topic's notes are written in this vault folder from now on.
    func writeHere(_ folder: String) { desk?.use(folder: full(folder)) }

    // MARK: Tabs (2026-11-08): more than one note open, as in Obsidian.

    /// The tab shown, or nil when none is open.
    var tab: SageTab? { tabs.isEmpty ? nil : tabs[min(max(0, activeTab), tabs.count - 1)] }

    /// The file open in the notes stage: the shown tab's.
    var note: URL? { tab?.file }

    /// A file opened in the shown tab (the one it showed goes on the tab's back list), or in a first tab.
    func open(_ file: URL) {
        if let index = tabs.indices.contains(activeTab) ? activeTab : nil {
            guard tabs[index].file.standardizedFileURL.path.lowercased() != file.standardizedFileURL.path.lowercased() else { focus(index); return }
            tabs[index].back.append(tabs[index].file)
            tabs[index].forward = []
            tabs[index].file = file
        } else {
            tabs.append(SageTab(file: file))
            activeTab = tabs.count - 1
        }
        focus(activeTab)
    }

    /// A file shown in the notes stage (a topic note, a note just written, a file in the vault).
    func show(_ file: URL) { open(file) }
    func show(path: String) { open(full(path)) }

    private func focus(_ index: Int) {
        activeTab = min(max(0, index), max(0, tabs.count - 1))
        if let tab { reveal(tab.file) }
        save()
        if desk?.stage != "notes" { desk?.stage = "notes" }
    }

    /// A file opened in a new tab beside the shown one (shown at once unless `behind`).
    func openInNewTab(_ file: URL, behind: Bool = false) {
        let at = tabs.isEmpty ? 0 : min(max(0, activeTab), tabs.count - 1) + 1
        tabs.insert(SageTab(file: file), at: at)
        if behind { if at <= activeTab { activeTab += 1 }; save() } else { focus(at) }
    }

    func openInNewTab(path: String, behind: Bool = false) { openInNewTab(full(path), behind: behind) }

    func showTab(_ id: UUID) { if let index = tabs.firstIndex(where: { $0.id == id }) { focus(index) } }

    /// The tab after (1) or before (-1) the shown one, round the end.
    func cycleTab(_ step: Int) {
        guard tabs.count > 1 else { return }
        focus(((activeTab + step) % tabs.count + tabs.count) % tabs.count)
    }

    /// A tab closed; when it was the shown one, the one to its right is shown (else the one to its left).
    func closeTab(_ id: UUID) { closeTabs([id]) }
    func closeOtherTabs(_ keep: UUID) { closeTabs(tabs.map(\.id).filter { $0 != keep }, show: keep) }
    func closeTabsToTheRight(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        closeTabs(tabs.dropFirst(index + 1).map(\.id), show: id)
    }

    private func closeTabs(_ closing: [UUID], show: UUID? = nil) {
        guard !closing.isEmpty else { return }
        let shown = tab?.id
        var at = shown.flatMap { id in tabs.firstIndex { $0.id == id } } ?? 0
        for id in closing {
            guard let index = tabs.firstIndex(where: { $0.id == id }) else { continue }
            closed.insert((tabs[index].file, index), at: 0)
            tabs.remove(at: index)
            if index < at { at -= 1 }
        }
        if closed.count > 30 { closed.removeLast(closed.count - 30) }
        if let show, let index = tabs.firstIndex(where: { $0.id == show }) { activeTab = index }
        else if let shown, let index = tabs.firstIndex(where: { $0.id == shown }) { activeTab = index }
        else { activeTab = min(max(0, at), max(0, tabs.count - 1)) }
        save()
        closing.forEach { onTabClosed?($0) }
        if let tab { reveal(tab.file); save() }
    }

    /// The last tab you closed, open again where it was.
    func reopenClosedTab() {
        guard !closed.isEmpty else { return }
        let (file, at) = closed.removeFirst()
        let index = min(max(0, at), tabs.count)
        tabs.insert(SageTab(file: file), at: index)
        focus(index)
    }

    /// A tab dragged to another place in the row.
    func moveTab(_ id: UUID, to: Int) {
        guard let from = tabs.firstIndex(where: { $0.id == id }) else { return }
        let shown = tab?.id
        let moving = tabs.remove(at: from)
        tabs.insert(moving, at: min(max(0, to), tabs.count))
        if let shown, let index = tabs.firstIndex(where: { $0.id == shown }) { activeTab = index }
        save()
    }

    var canGoBack: Bool { !(tab?.back.isEmpty ?? true) }
    var canGoForward: Bool { !(tab?.forward.isEmpty ?? true) }

    /// The file the shown tab had before (Cmd+[), or the one you came back from (Cmd+]).
    func goBack() { step(back: true) }
    func goForward() { step(back: false) }

    private func step(back: Bool) {
        guard tabs.indices.contains(activeTab) else { return }
        var tab = tabs[activeTab]
        guard let to = back ? tab.back.popLast() : tab.forward.popLast() else { return }
        if back { tab.forward.append(tab.file) } else { tab.back.append(tab.file) }
        tab.file = to
        tabs[activeTab] = tab
        reveal(to)
        save()
    }

    /// Tabs, recent and pinned notes and open folders follow files that moved.
    func repath(_ moves: [String: String]) {
        func moved(_ file: URL) -> URL { inVault(file).map { full(Study.movedPath($0, moves)) } ?? file }
        for index in tabs.indices {
            tabs[index].file = moved(tabs[index].file)
            tabs[index].back = tabs[index].back.map(moved)
            tabs[index].forward = tabs[index].forward.map(moved)
        }
        settings.recent = settings.recent.map { Study.movedPath($0, moves) }
        settings.pinned = settings.pinned.map { Study.movedPath($0, moves) }
        settings.expanded = settings.expanded.map { Study.movedPath($0, moves) }
        if !settings.folderColors.isEmpty {
            settings.folderColors = Dictionary(settings.folderColors.map { (Study.movedPath($0.key, moves), $0.value) }, uniquingKeysWith: { a, _ in a })
        }
        save()
    }

    /// Tabs showing files that are gone go back to the file they had before (as Obsidian's tab does when its file is
    /// deleted, it never shows a missing note); a tab with nothing to go back to closes. Gone files leave every tab's history.
    func leaveGone(_ gone: (String) -> Bool) {
        func isGone(_ file: URL) -> Bool { inVault(file).map(gone) ?? false }
        var closing: [UUID] = []
        for index in tabs.indices {
            tabs[index].back.removeAll(where: isGone)
            tabs[index].forward.removeAll(where: isGone)
            guard isGone(tabs[index].file) else { continue }
            if let before = tabs[index].back.popLast() { tabs[index].file = before; tabs[index].forward = [] } else { closing.append(tabs[index].id) }
        }
        settings.pinned.removeAll(where: gone)
        settings.recent.removeAll(where: gone)
        if !closing.isEmpty { closeTabs(closing) } else {
            if let tab { reveal(tab.file) }
            save()
        }
    }

    /// Said at the bottom of the tree (with Undo when it can be undone).
    func say(_ text: String, undo: Bool = false) { said = (text, undo, (said?.count ?? 0) + 1) }
    func dismissSaid() { said = nil }
}
