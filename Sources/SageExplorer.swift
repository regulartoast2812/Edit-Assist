import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Sage's file explorer (2026-11-08 in Creative Assist, brought to the Mac 2026-11-09): the vault's tree as a better
/// Obsidian explorer. The tree, its pinned and recent notes, searching names or text, sorting, Notebook Navigator's folder
/// icons and colours, keys, drag and drop, renaming in place, the quick switcher (Cmd+O), the path above the note with a
/// menu on each folder, hover previews (Cmd), and a note at the bottom of the tree with Undo for every change.
struct SageExplorer: View {
    @ObservedObject var desk: SageDesk
    @ObservedObject var vault: SageVaultDesk
    @Binding var filter: String
    @StateObject private var look = SageTreeLook()

    @State private var search = ""
    /// Search the notes' text, not only their names.
    @State private var searchText = false
    @State private var textHits: [(item: Study.VaultItem, line: String)]?
    /// Rows picked with Option+click or Shift+click, to move, open or delete together.
    @State private var picked: Set<String> = []
    @State private var anchor: String?
    /// The row the keys are on.
    @State private var cursor: String?
    @State private var hovered: String?
    @State private var renameText = ""
    @State private var renameStarted = Date.distantPast
    @State private var flashKey: String?
    @State private var flashLevel = 0.0
    @State private var offset: CGFloat = 0
    @State private var viewport: CGFloat = 400
    @State private var dropTarget: String?
    @State private var dragPaths: [String] = []
    @State private var toast: (text: String, undo: Bool, count: Int)?
    @State private var typed = ""
    @State private var typedAt = Date.distantPast
    @State private var monitors: [Any] = []
    @State private var followed: String?
    @FocusState private var treeFocused: Bool
    @FocusState private var renameFocused: Bool
    private let accent = PixelSage.theme

    init(desk: SageDesk, vault: SageVaultDesk, filter: Binding<String>) {
        self.desk = desk; self.vault = vault; self._filter = filter
    }

    // MARK: The pane: its bar, the search, the tree

    /// The left of the notes stage: the vault's name and its tools, the search, a status filter if one is on, and the tree.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            head
            TextField(L("Search your vault"), text: $search).textFieldStyle(.roundedBorder).controlSize(.small)
            if !filter.isEmpty { filterChip } else if !search.trimmingCharacters(in: .whitespaces).isEmpty { searchScope }
            tree
        }
        .padding(10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .bottom) { toastView }
        .onAppear { look.read(vault); listen() }
        .onDisappear { monitors.forEach(NSEvent.removeMonitor); monitors = [] }
        .onChange(of: vault.version) { _, _ in look.read(vault) }
        .onChange(of: vault.settings.folderColors) { _, _ in look.read(vault) }
        .onChange(of: desk.topicID) { _, _ in filter = ""; search = "" }
        .onChange(of: search) { _, _ in runTextSearch() }
        .onChange(of: searchText) { _, _ in runTextSearch() }
        .onChange(of: vault.said?.count) { _, _ in
            guard let said = vault.said else { return }
            toast = said
            let count = said.count
            Task { try? await Task.sleep(for: .seconds(said.undo ? 8 : 5)); if toast?.count == count { withAnimation(.easeOut(duration: 0.2)) { toast = nil } } }
        }
        .onChange(of: vault.renaming) { _, path in
            guard let path else { return }
            filter = ""; search = ""
            renameText = vault.item(path).map { $0.folder ? $0.name : $0.title } ?? (path as NSString).lastPathComponent
            renameStarted = Date()
            vault.openFolders(above: path)
            DispatchQueue.main.async { renameFocused = true }
        }
        .sheet(isPresented: Binding(get: { vault.switcher != nil }, set: { if !$0 { vault.switcher = nil } })) {
            SageSwitcher(vault: vault)
        }
    }

    var head: some View {
        HStack(spacing: 2) {
            if let root = vault.vault {
                Label(root.lastPathComponent, systemImage: "books.vertical").font(.system(size: 12, weight: .semibold)).lineLimit(1).help(root.path)
            }
            Spacer(minLength: 4)
            tool("square.and.pencil", L("New note (⌘N)")) { newNoteHere(nil) }
            tool("folder.badge.plus", L("New folder")) { newFolderIn("") }
            Menu {
                sortItem(L("File name (A to Z)"), "alphabetical"); sortItem(L("File name (Z to A)"), "alphabeticalReverse")
                sortItem(L("Modified (new to old)"), "byModifiedTime"); sortItem(L("Modified (old to new)"), "byModifiedTimeReverse")
                sortItem(L("Created (new to old)"), "byCreatedTime"); sortItem(L("Created (old to new)"), "byCreatedTimeReverse")
                Divider()
                checkItem(L("Folders first"), vault.settings.foldersFirst) { vault.setFoldersFirst(!vault.settings.foldersFirst) }
                checkItem(L("Notes only (hide pictures and other files)"), vault.settings.notesOnly) { vault.setNotesOnly(!vault.settings.notesOnly) }
            } label: { Image(systemName: "arrow.up.arrow.down").font(.system(size: 11)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 22).help(L("Sort and show"))
            tool("scope", vault.settings.follow ? L("Following the open file: the tree opens to it. Click to stop") : L("Follow the open file: the tree opens to it"),
                 tint: vault.settings.follow ? accent : nil) { vault.setFollow(!vault.settings.follow) }
            tool("arrow.down.right.and.arrow.up.left", L("Close every folder")) { vault.collapseAll() }
                .contextMenu {
                    Button(L("Close every folder")) { vault.collapseAll() }
                    Button(L("Close all but the open file's")) { vault.collapseOthers() }
                }
            Menu {
                Button(L("Quick switcher…  (⌘O)")) { vault.switcher = .open }
                Button(L("Close all but the open file's folders")) { vault.collapseOthers() }
                Button(L("Undo the last change")) { vault.undo() }.disabled(vault.changes.isEmpty)
                Divider()
                Button(L("Show in Finder")) { if let root = vault.vault { NSWorkspace.shared.open(root) } }
                Button(L("Read it again")) { vault.reload() }
                Button(L("Choose another vault…")) { vault.chooseVault() }
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 11)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 22).help(L("Vault"))
        }.foregroundStyle(.secondary)
    }

    func tool(_ symbol: String, _ tip: String, tint: Color? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11.5)).foregroundStyle(tint ?? Color.secondary).frame(width: 22, height: 20).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(tip).accessibilityLabel(tip)
    }

    func sortItem(_ text: String, _ order: String) -> some View { checkItem(text, vault.sort == order) { vault.setSort(order) } }

    @ViewBuilder func checkItem(_ text: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { if on { Label(text, systemImage: "checkmark") } else { Text(text) } }
    }

    /// Search in names or in the notes' text.
    var searchScope: some View {
        HStack(spacing: 2) {
            part(L("Names"), !searchText) { searchText = false }
            part(L("Text in notes"), searchText) { searchText = true }
        }
    }

    func part(_ text: String, _ on: Bool, _ pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            Text(text).font(.system(size: 11, weight: on ? .semibold : .regular)).foregroundStyle(on ? Color.primary : Color.secondary)
                .padding(.horizontal, 9).padding(.vertical, 3).background(on ? accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
    }

    /// The status filter from the header's counts, and a way off it.
    var filterChip: some View {
        HStack(spacing: 4) {
            Circle().fill(SagePage.statusColor(filter)).frame(width: 6, height: 6)
            Text("\(desk.topic.name): \(L(SagePage.statusName(filter)))").font(.system(size: 11))
            Button { filter = "" } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 16, height: 16) }
                .buttonStyle(.plain).help(L("Show the whole vault"))
        }
        .padding(.leading, 8).padding(.vertical, 2).padding(.trailing, 2)
        .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: The rows

    /// What a row is: a heading of the pinned or recent notes, a folder or file of the tree (or of a section, or found),
    /// a topic note under a status filter, or a line of text.
    enum Kind {
        case heading(section: String, title: String, symbol: String, count: Int, open: Bool)
        case divider, empty, muted(String)
        case folder(Study.VaultItem)
        case file(Study.VaultItem, section: String?)
        case topic(Study.Entry)
        case foundFolder(Study.VaultItem, marks: [Int])
        case foundFile(Study.VaultItem, marks: [Int]?, snippet: String?)
    }

    struct Row: Identifiable {
        var id: String
        var kind: Kind
        var depth = 0
        var height: CGFloat = 26
        /// The folders it's in, outermost first, for the lines down the tree.
        var ancestors: [String] = []
        /// For an open folder: the index of the last row it holds (to pin it while they're in sight).
        var end = -1

        var item: Study.VaultItem? {
            switch kind {
            case .folder(let item), .file(let item, _), .foundFolder(let item, _), .foundFile(let item, _, _): return item
            default: return nil
            }
        }
        var section: String? {
            switch kind {
            case .file(_, let section): return section
            case .foundFolder, .foundFile: return "search"
            default: return nil
            }
        }
        /// A row the keys move between.
        var actionable: Bool {
            switch kind { case .folder, .file, .topic, .foundFolder, .foundFile: return true; default: return false }
        }
        var name: String {
            switch kind {
            case .folder(let item), .foundFolder(let item, _): return item.name
            case .file(let item, _), .foundFile(let item, _, _): return item.title
            case .topic(let entry): return entry.title
            default: return ""
            }
        }
    }

    var mode: String { !filter.isEmpty ? "filter" : search.trimmingCharacters(in: .whitespaces).isEmpty ? "tree" : "search" }

    /// The rows, worked out again only when something they show changed (not on every step of a scroll).
    func cachedRows() -> [Row] {
        let s = vault.settings
        let key = [String(vault.version), vault.sort, "\(s.foldersFirst)\(s.notesOnly)\(s.pinnedOpen)\(s.recentOpen)\(vault.reading)\(searchText)",
                   s.expanded.joined(separator: "\u{1}"), s.pinned.joined(separator: "\u{1}"), s.recent.joined(separator: "\u{1}"),
                   search, filter, String(textHits?.count ?? -1), textHits?.first?.item.path ?? "", desk.recipes.map(\.id).joined(separator: "\u{1}"),
                   desk.recipes.map(\.status).joined(), desk.folder?.path ?? ""].joined(separator: "\u{2}")
        if let cached = look.rowCache, cached.key == key { return cached.rows }
        let made = rows()
        look.rowCache = (key, made)
        return made
    }

    /// Every row shown, in order.
    func rows() -> [Row] {
        var rows: [Row] = []
        func muted(_ text: String) { rows.append(Row(id: "muted:\(rows.count)", kind: .muted(text), height: 34)) }
        if vault.reading && vault.items.isEmpty { muted(L("Reading your vault…")); return rows }
        if !filter.isEmpty {
            for entry in shownRecipes { rows.append(Row(id: "note:" + entry.file.path, kind: .topic(entry), height: 42)) }
            if rows.isEmpty { muted(desk.folder == nil ? L("This topic has no folder yet: its notes go where you choose when the first is written.") : L("No notes are marked “%@”.", L(SagePage.statusName(filter)))) }
            return rows
        }
        let words = search.trimmingCharacters(in: .whitespaces)
        if !words.isEmpty { return found(words) }
        section(&rows, "pinned", L("PINNED"), "pin", vault.settings.pinned, vault.pinnedOpen)
        section(&rows, "recent", L("RECENT"), "clock", Array(vault.settings.recent.filter { !vault.isPinned($0) }.prefix(6)), vault.recentOpen)
        func walk(_ folder: String, _ depth: Int, _ ancestors: [String]) {
            for item in vault.children(of: folder) {
                if item.folder {
                    let index = rows.count
                    rows.append(Row(id: item.path, kind: .folder(item), depth: depth, ancestors: ancestors))
                    if vault.isOpen(item.path) {
                        let before = rows.count
                        walk(item.path, depth + 1, ancestors + [item.path])
                        if rows.count == before { rows.append(Row(id: "empty:" + item.path, kind: .empty, depth: depth + 1, height: 22, ancestors: ancestors + [item.path])) }
                        rows[index].end = rows.count - 1
                    }
                } else {
                    rows.append(Row(id: item.path, kind: .file(item, section: nil), depth: depth, ancestors: ancestors))
                }
            }
        }
        walk("", 0, [])
        if vault.items.isEmpty { muted(L("This vault is empty.")) }
        return rows
    }

    /// Pinned or recent notes above the tree: a heading that folds, and a row for each (with where it is).
    func section(_ rows: inout [Row], _ id: String, _ title: String, _ symbol: String, _ paths: [String], _ open: Bool) {
        let items = paths.compactMap(vault.item)
        guard !items.isEmpty else { return }
        rows.append(Row(id: "head:" + id, kind: .heading(section: id, title: title, symbol: symbol, count: items.count, open: open), height: 24))
        if open { for item in items { rows.append(Row(id: id + ":" + item.path, kind: .file(item, section: id), height: item.parent.isEmpty ? 26 : 40)) } }
        rows.append(Row(id: "divider:" + id, kind: .divider, height: 9))
    }

    /// Search results: folders whose name has the words, then files by name (fuzzy, best first), or by the text inside.
    func found(_ words: String) -> [Row] {
        var rows: [Row] = []
        if searchText {
            guard let hits = textHits else { return [Row(id: "muted:searching", kind: .muted(L("Searching your notes…")), height: 34)] }
            for hit in hits { rows.append(Row(id: hit.item.path, kind: .foundFile(hit.item, marks: nil, snippet: hit.line), height: hit.item.parent.isEmpty ? 40 : 54)) }
            if rows.isEmpty { rows.append(Row(id: "muted:none", kind: .muted(L("No note says that.")), height: 34)) }
            return rows
        }
        for folder in vault.items.filter({ $0.folder && $0.name.localizedCaseInsensitiveContains(words) }).prefix(8) {
            rows.append(Row(id: "search:" + folder.path, kind: .foundFolder(folder, marks: Self.matchAt(folder.name, words))))
        }
        let files = vault.items.filter { !$0.folder && vault.shown($0) }
            .compactMap { item in Study.fuzzy(words, item.title).map { (item: item, match: $0) } }
            .sorted { $0.match.score != $1.match.score ? $0.match.score > $1.match.score : Study.natural($0.item.title, $1.item.title) < 0 }
            .prefix(200)
        for (item, match) in files { rows.append(Row(id: item.path, kind: .foundFile(item, marks: match.at, snippet: nil), height: item.parent.isEmpty ? 26 : 40)) }
        if rows.isEmpty { rows.append(Row(id: "muted:none", kind: .muted(L("Nothing in the vault is called that. Try “Text in notes”.")), height: 34)) }
        return rows
    }

    static func matchAt(_ text: String, _ words: String) -> [Int] {
        guard let range = text.range(of: words, options: .caseInsensitive) else { return [] }
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        return Array(start ..< start + text[range].count)
    }

    var shownRecipes: [Study.Entry] {
        desk.recipes.filter { entry in
            (filter.isEmpty || entry.status == filter)
                && (search.isEmpty || entry.title.localizedCaseInsensitiveContains(search) || entry.tags.contains { $0.localizedCaseInsensitiveContains(search) }
                    || entry.cuisine.localizedCaseInsensitiveContains(search))
        }
    }

    /// The notes' text, kept while a note is unchanged, for searching inside them.
    @MainActor private static var textCache: [String: (modified: Date, text: String)] = [:]

    func runTextSearch() {
        textHits = nil
        let words = search.trimmingCharacters(in: .whitespaces)
        guard searchText, !words.isEmpty, let root = vault.vault else { return }
        let items = vault.items.filter { !$0.folder && $0.ext == ".md" }
        let cache = Self.textCache
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard search.trimmingCharacters(in: .whitespaces) == words, searchText else { return }
            let (hits, read) = await Task.detached { () -> ([(item: Study.VaultItem, line: String)], [String: (modified: Date, text: String)]) in
                var hits: [(item: Study.VaultItem, line: String)] = [], read: [String: (modified: Date, text: String)] = [:]
                for item in items {
                    if hits.count >= 100 { break }
                    var text: String
                    if let kept = cache[item.path], kept.modified == item.modified { text = kept.text } else {
                        text = (try? String(contentsOf: root.appendingPathComponent(item.path), encoding: .utf8)) ?? ""
                        read[item.path] = (item.modified, text)
                    }
                    guard let at = text.range(of: words, options: .caseInsensitive) else { continue }
                    let start = text[..<at.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
                    let end = text[at.upperBound...].firstIndex(of: "\n") ?? text.endIndex
                    var line = text[start ..< end].trimmingCharacters(in: .whitespaces)
                    if line.count > 140, let hit = line.range(of: words, options: .caseInsensitive) {
                        let from = max(0, line.distance(from: line.startIndex, to: hit.lowerBound) - 50)
                        let chars = Array(line)
                        line = (from > 0 ? "…" : "") + String(chars[from ..< min(chars.count, from + 140)])
                    }
                    text = ""
                    hits.append((item, line))
                }
                return (hits, read)
            }.value
            for (path, kept) in read { Self.textCache[path] = kept }
            guard search.trimmingCharacters(in: .whitespaces) == words, searchText else { return }
            textHits = hits
        }
    }

    // MARK: The tree

    /// The open file's path, the row marked in Sage's colour.
    var marked: String? { vault.note.map { vault.inVault($0) ?? $0.path } }

    var tree: some View {
        let rows = cachedRows()
        var tops: [CGFloat] = [], y: CGFloat = 0
        for row in rows { tops.append(y); y += row.height + 1 }
        let open = marked
        return GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(rows) { row in rowView(row, open: open).frame(height: row.height).id(row.id) }
                    }
                    .padding(.bottom, toast == nil ? 4 : 60)
                    .background(GeometryReader { inner in
                        Color.clear.preference(key: TreeOffset.self, value: -inner.frame(in: .named("sage-tree")).minY)
                    })
                    .onDrop(of: [.fileURL], delegate: TreeDrop(explorer: self, folder: "", key: nil))
                }
                .coordinateSpace(name: "sage-tree")
                .onPreferenceChange(TreeOffset.self) { offset = $0 }
                .onAppear { viewport = outer.size.height }
                .onChange(of: outer.size.height) { _, height in viewport = height }
                .overlay(alignment: .top) { if mode == "tree" { sticky(rows, tops) { key in scroll(proxy, rows, tops, to: key, flash: true, pinnedAbove: true) } } }
                .onChange(of: vault.spotlight?.count) { _, _ in
                    guard let path = vault.spotlight?.path else { return }
                    filter = ""; search = ""
                    DispatchQueue.main.async { let rows = self.cachedRows(); scroll(proxy, rows, Self.tops(rows), to: path, flash: true) }
                }
                .onChange(of: vault.note) { _, _ in
                    // Following the open file: when it changes, its row is brought into sight (no flash, no jump if it's there).
                    guard vault.settings.follow, let open = marked, open != followed else { followed = marked; return }
                    followed = open
                    DispatchQueue.main.async { let rows = self.cachedRows(); scroll(proxy, rows, Self.tops(rows), to: open, flash: false) }
                }
                .onChange(of: vault.renaming) { _, path in
                    guard let path else { return }
                    DispatchQueue.main.async { let rows = self.cachedRows(); scroll(proxy, rows, Self.tops(rows), to: path, flash: false) }
                }
                .onChange(of: cursor) { _, key in
                    guard let key, treeFocused else { return }
                    let rows = self.cachedRows()
                    scroll(proxy, rows, Self.tops(rows), to: key, flash: false)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($treeFocused)
        .onKeyPress(phases: .down) { press in keys(press, rows) }
    }

    static func tops(_ rows: [Row]) -> [CGFloat] {
        var tops: [CGFloat] = [], y: CGFloat = 0
        for row in rows { tops.append(y); y += row.height + 1 }
        return tops
    }

    /// A row brought into sight: straight there, centred, when it isn't (no slow scroll), then lit when asked; a row in
    /// sight stays where it is.
    func scroll(_ proxy: ScrollViewProxy, _ rows: [Row], _ tops: [CGFloat], to key: String, flash: Bool, pinnedAbove: Bool = false) {
        guard let index = rows.firstIndex(where: { Study.same($0.id, key) }) else { return }
        let top = tops[index] - offset, margin: CGFloat = flash ? 24 : 0
        if pinnedAbove || top < margin || top + rows[index].height > viewport - margin {
            proxy.scrollTo(rows[index].id, anchor: pinnedAbove ? .top : .center)
        }
        if flash { light(rows[index].id) }
    }

    /// A row lit in Sage's colour that fades back to how it was (held, then eased out; a plain blink with reduced motion).
    func light(_ key: String) {
        flashKey = key
        if !SageColors.motion {
            flashLevel = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { if flashKey == key { flashLevel = 0 } }
            return
        }
        flashLevel = 0
        withAnimation(.easeOut(duration: 0.14)) { flashLevel = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) { if flashKey == key { withAnimation(.easeInOut(duration: 1.14)) { flashLevel = 0 } } }
    }

    @ViewBuilder func rowView(_ row: Row, open: String?) -> some View {
        switch row.kind {
        case .muted(let text):
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 6).frame(maxWidth: .infinity, alignment: .leading)
        case .divider:
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1).padding(.horizontal, 4)
        case .empty:
            HStack(spacing: 0) {
                guides(row, open: open)
                Text(L("Empty")).font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 6)
                Spacer(minLength: 0)
            }
        case let .heading(section, title, symbol, count, isOpen):
            Button {
                withAnimation(SageColors.motion ? .easeOut(duration: 0.18) : nil) { if section == "pinned" { vault.pinnedOpen = !isOpen } else { vault.recentOpen = !isOpen } }
                vault.objectWillChange.send()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold)).rotationEffect(.degrees(isOpen ? 90 : 0)).frame(width: 12)
                    Image(systemName: symbol).font(.system(size: 9))
                    Text(title).font(.system(size: 9, weight: .bold)).tracking(1.5)
                    Text("\(count)").font(.system(size: 9.5))
                    Spacer(minLength: 0)
                }.foregroundStyle(.secondary).padding(.horizontal, 4).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(L(section == "pinned" ? "pinned notes" : "recent notes"))
        case .topic(let entry):
            topicRow(entry, open: open)
        default:
            if let item = row.item { itemRow(row, item, open: open) }
        }
    }

    /// The lines down the left of what each open folder holds, lit for the folders the open file is in.
    func guides(_ row: Row, open: String?) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row.ancestors.enumerated()), id: \.offset) { _, folder in
                let lit = open.map { $0.lowercased().hasPrefix(folder.lowercased() + "/") } ?? false
                Rectangle().fill(lit ? (look.folderHue(folder, vault).map { $0.opacity(0.55) } ?? accent.opacity(0.45)) : Color.white.opacity(0.07))
                    .frame(width: 1).padding(.leading, 11).padding(.trailing, 7)
            }
        }
    }

    /// A row of the tree (or a section, or a search): a real button (Return, Space, VoiceOver and right-click all work),
    /// eased hover, and the open file marked in Sage's colour.
    func itemRow(_ row: Row, _ item: Study.VaultItem, open: String?) -> some View {
        let key = row.id
        let isMarked = open.map { Study.same($0, key) } ?? false
        let isPicked = row.section == nil && picked.contains(item.path)
        let isDrop = dropTarget.map { Study.same($0, item.path) && item.folder } ?? false
        let isCursor = treeFocused && cursor == key
        let rest: Color = isMarked ? accent.opacity(0.22) : isPicked ? accent.opacity(0.13) : (item.folder ? look.tint(item.path) : nil) ?? .clear
        return Button { click(row) } label: {
            HStack(spacing: 0) {
                if row.section == nil { guides(row, open: open) }
                rowContent(row, item)
            }
            .padding(.leading, 4).padding(.trailing, 6)
            .frame(maxHeight: .infinity)
            .background(rest)
            .background(hovered == key || isCursor ? Color.white.opacity(0.06) : .clear)
            .background(isDrop ? accent.opacity(0.2) : .clear)
            .overlay(flashKey == key ? accent.opacity(0.45 * flashLevel) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(isDrop ? accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.folder ? item.name : item.title)
        .help(item.folder ? "" : Self.dates(item))
        .onHover { on in
            if on { hovered = key; if !item.folder && NSEvent.modifierFlags.contains(.command) { vault.preview = .init(path: item.path, at: nil) } }
            else if hovered == key { hovered = nil; if vault.preview?.at == nil { vault.preview = nil } }
        }
        .popover(isPresented: Binding(get: { hovered == key && vault.preview?.at == nil && vault.preview.map { Study.same($0.path, item.path) } == true },
                                      set: { if !$0, vault.preview?.at == nil { vault.preview = nil } }), arrowEdge: .trailing) {
            SageNotePreview(vault: vault)
        }
        .contextMenu { menu(row, item) }
        .onDrag {
            dragPaths = picked.contains(item.path) ? Array(picked) : [item.path]
            return NSItemProvider(object: vault.full(item.path) as NSURL)
        }
        .onDrop(of: [.fileURL], delegate: TreeDrop(explorer: self, folder: item.folder ? item.path : item.parent, key: item.folder ? item.path : nil))
    }

    @ViewBuilder func rowContent(_ row: Row, _ item: Study.VaultItem) -> some View {
        switch row.kind {
        case .folder:
            let isOpen = vault.isOpen(item.path)
            Image(systemName: "chevron.right").font(.system(size: 7.5, weight: .bold)).foregroundStyle(.secondary)
                .rotationEffect(.degrees(isOpen ? 90 : 0)).frame(width: 14)
            folderIcon(item, open: isOpen).padding(.leading, 1).padding(.trailing, 6)
            label(item.path, item.name, nil, shown: SageTreeLook.shown(item.name))
            Spacer(minLength: 4)
            if let topicFolder = desk.folder.flatMap(vault.inVault), Study.same(topicFolder, item.path) {
                Image(systemName: "square.and.pencil").font(.system(size: 10)).foregroundStyle(accent)
                    .help(L("Sage writes “%@” notes here", desk.topic.name)).padding(.leading, 6).padding(.trailing, 2)
            }
            if let count = look.counts(vault)[item.path.lowercased()], count > 0 {
                Text("\(count)").font(.system(size: 10)).foregroundStyle(.secondary).opacity(0.7).padding(.leading, 6).padding(.trailing, 2)
            }
        case .file(_, let section):
            SageIconView(icon: look.fileIcon(item, vault)).padding(.leading, section == nil ? 14 : 0).padding(.trailing, 5)
            if section != nil && !item.parent.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    label(nil, item.title, nil, shown: SageTreeLook.shown(item.title))
                    where_(item)
                }
            } else {
                label(section == nil ? item.path : nil, item.title, nil, shown: SageTreeLook.shown(item.title))
            }
            Spacer(minLength: 4)
            if section == nil && vault.isPinned(item.path) { Image(systemName: "pin").font(.system(size: 9)).foregroundStyle(.secondary).padding(.leading, 6) }
            typeBadge(item)
        case .foundFolder(_, let marks):
            Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 15).padding(.trailing, 6)
            label(nil, item.name, marks)
            Text(item.parent.replacingOccurrences(of: "/", with: " / ")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).padding(.leading, 6)
            Spacer(minLength: 0)
        case .foundFile(_, let marks, let snippet):
            SageIconView(icon: look.fileIcon(item, vault)).padding(.trailing, 5)
            VStack(alignment: .leading, spacing: 1) {
                label(item.path, item.title, marks, shown: marks == nil ? SageTreeLook.shown(item.title) : nil)
                if !item.parent.isEmpty { where_(item) }
                if let snippet { Self.snippet(snippet, search.trimmingCharacters(in: .whitespaces)) }
            }
            Spacer(minLength: 4)
            typeBadge(item)
        default: EmptyView()
        }
    }

    func where_(_ item: Study.VaultItem) -> some View {
        Text(item.parent.replacingOccurrences(of: "/", with: " / ")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).padding(.leading, 2)
    }

    @ViewBuilder func typeBadge(_ item: Study.VaultItem) -> some View {
        if item.ext != ".md" {
            Text(item.ext.dropFirst().uppercased()).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 4).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 3)).padding(.leading, 6)
        }
    }

    @ViewBuilder func folderIcon(_ item: Study.VaultItem, open: Bool) -> some View {
        if let emoji = look.folderIcon(item.path) ?? Study.leadingEmoji(item.name)?.emoji {
            Text(emoji).font(.system(size: 11.5)).frame(width: 15)
        } else {
            Image(systemName: open ? "folder.fill" : "folder").font(.system(size: 12)).foregroundStyle(look.hueColor(item.path, vault)).frame(width: 15)
        }
    }

    /// A row's name: in place, a box to rename it; else its name, the letters a search matched lit.
    @ViewBuilder func label(_ path: String?, _ text: String, _ marks: [Int]?, shown: String? = nil) -> some View {
        if let path, let renaming = vault.renaming, Study.same(path, renaming) {
            TextField(L("New name"), text: $renameText)
                .textFieldStyle(.plain).font(.system(size: 12.5))
                .padding(.horizontal, 3).padding(.vertical, 1)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(accent))
                .focused($renameFocused)
                .onSubmit { finishRename(path, keep: true) }
                .onExitCommand { finishRename(path, keep: false) }
                .onChange(of: renameFocused) { _, focused in
                    guard !focused, vault.renaming.map({ Study.same($0, path) }) == true else { return }
                    // The note just opened can take the keyboard as it loads: give it back once, early on.
                    if Date().timeIntervalSince(renameStarted) < 1.5 { DispatchQueue.main.async { renameFocused = true }; return }
                    finishRename(path, keep: true)
                }
                .accessibilityLabel(L("New name"))
        } else {
            Self.lit(shown ?? text, marks ?? [], accent).font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail).opacity(0.9)
        }
    }

    /// Text with the letters at `marks` (character offsets) lit in Sage's colour.
    static func lit(_ text: String, _ marks: [Int], _ accent: Color) -> Text {
        guard !marks.isEmpty else { return Text(text) }
        let on = Set(marks)
        var result = AttributedString()
        for (i, c) in text.enumerated() {
            var piece = AttributedString(String(c))
            if on.contains(i) { piece.foregroundColor = accent; piece.inlinePresentationIntent = .stronglyEmphasized }
            result += piece
        }
        return Text(result)
    }

    static func snippet(_ text: String, _ words: String) -> some View {
        var shown = AttributedString(text)
        if !words.isEmpty, let range = text.range(of: words, options: .caseInsensitive) {
            var hit = AttributedString(String(text[range]))
            hit.backgroundColor = PixelSage.theme.opacity(0.28)
            hit.foregroundColor = .primary
            shown = AttributedString(String(text[..<range.lowerBound])) + hit + AttributedString(String(text[range.upperBound...]))
        }
        return Text(shown).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).padding(.leading, 2).padding(.top, 1)
    }

    static func dates(_ item: Study.VaultItem) -> String {
        func ago(_ date: Date) -> String {
            let span = Date().timeIntervalSince(date)
            if span < 60 { return L("just now") }
            if span < 3600 { return L("%@ min ago", "\(Int(span / 60))") }
            if span < 86_400 { return L("%@ h ago", "\(Int(span / 3600))") }
            let days = Int(span / 86_400)
            if days < 30 { return days == 1 ? L("1 day ago") : L("%@ days ago", "\(days)") }
            return day(date)
        }
        func day(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; return f.string(from: date) }
        return "\(item.path)\n" + L("Edited %@ · created %@", ago(item.modified), day(item.created))
    }

    /// A topic note under a status filter: its picture, title and status, as the old topic list showed it.
    func topicRow(_ entry: Study.Entry, open: String?) -> some View {
        let key = vault.inVault(entry.file) ?? entry.file.path
        let isMarked = open.map { Study.same($0, key) } ?? false
        let recipes = desk.topic.kind == .recipes
        return Button {
            treeFocused = true; cursor = "note:" + entry.file.path
            if NSEvent.modifierFlags.contains(.command) { vault.openInNewTab(entry.file) } else { vault.show(entry.file) }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    if let picture = entry.picture {
                        AsyncImage(url: picture) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.05) }
                    } else {
                        accent.opacity(0.18).overlay(Image(systemName: recipes ? "fork.knife" : "doc.text").font(.system(size: 11)).foregroundStyle(accent))
                    }
                }.frame(width: 52, height: 30).clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    HStack(spacing: 4) {
                        if !entry.status.isEmpty { Circle().fill(SagePage.statusColor(entry.status)).frame(width: 6, height: 6) }
                        Text([entry.status.isEmpty ? "" : L(SagePage.statusName(entry.status)), recipes ? entry.cuisine : entry.added].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(5)
            .background(isMarked ? accent.opacity(0.22) : hovered == "note:" + entry.file.path ? .white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.title)
        .onHover { on in if on { hovered = "note:" + entry.file.path } else if hovered == "note:" + entry.file.path { hovered = nil } }
        .contextMenu { Button(L("Open in new tab")) { vault.openInNewTab(entry.file) } }
    }

    // MARK: The folders you're in, pinned above the tree while you scroll

    /// Open folders whose row has gone above the top while what they hold is still in sight, outermost first (four at
    /// most); each slides up and away as its last rows go by.
    @ViewBuilder func sticky(_ rows: [Row], _ tops: [CGFloat], go: @escaping (String) -> Void) -> some View {
        let chain = stickyChain(rows, tops)
        if !chain.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(chain.enumerated()), id: \.offset) { i, link in
                    stickyRow(rows[link.index], last: i == chain.count - 1, go: go).offset(y: link.shift)
                }
            }
        }
    }

    func stickyChain(_ rows: [Row], _ tops: [CGFloat]) -> [(index: Int, shift: CGFloat)] {
        guard offset >= 2 else { return [] }
        var found: [(index: Int, top: CGFloat, bottom: CGFloat)] = []
        for (index, row) in rows.enumerated() where row.end > index {
            let top = tops[index] - offset
            guard top < 0 else { continue }
            let bottom = tops[row.end] + rows[row.end].height - offset
            if bottom > 0 { found.append((index, top, bottom)) }
        }
        found.sort { rows[$0.index].depth < rows[$1.index].depth }
        var chain: [(index: Int, bottom: CGFloat)] = [], line: CGFloat = 0
        for f in found {
            if chain.count >= 4 { break }
            if let last = chain.last, !rows[f.index].ancestors.contains(rows[last.index].id) { continue }
            // Its row must be under the folders already pinned (else it is still in sight below them).
            if f.top >= line - 0.5 && !chain.isEmpty { continue }
            if f.bottom <= line + 4 { continue }
            chain.append((f.index, f.bottom))
            line += 27
        }
        var y: CGFloat = 0, result: [(index: Int, shift: CGFloat)] = []
        for link in chain {
            result.append((link.index, min(0, link.bottom - (y + 27))))
            y += 27
        }
        return result
    }

    func stickyRow(_ row: Row, last: Bool, go: @escaping (String) -> Void) -> some View {
        let item = row.item ?? Study.VaultItem(path: row.id, folder: true)
        return Button { go(row.id) } label: {
            HStack(spacing: 0) {
                Image(systemName: "chevron.right").font(.system(size: 7.5, weight: .bold)).foregroundStyle(.secondary).rotationEffect(.degrees(90)).frame(width: 14)
                folderIcon(item, open: true).padding(.leading, 1).padding(.trailing, 6)
                Text(SageTreeLook.shown(item.name)).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 4 + CGFloat(row.depth) * 19).padding(.trailing, 6)
            .frame(height: 26)
            .background(Color(nsColor: .windowBackgroundColor))
            .background(hovered == "sticky:" + row.id ? Color.white.opacity(0.05) : .clear)
            .overlay(alignment: .bottom) { if last { Rectangle().fill(.black.opacity(0.35)).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(row.id)\n" + L("Click to go to it"))
        .accessibilityLabel(L("In %@", item.name))
        .onHover { on in if on { hovered = "sticky:" + row.id } else if hovered == "sticky:" + row.id { hovered = nil } }
        .contextMenu { if let item = row.item { folderMenu(item) } }
    }

    // MARK: A row: open, pick, drag, drop, the keys and the right-click

    func click(_ row: Row) {
        treeFocused = true
        cursor = row.id
        guard let item = row.item else { return }
        let mods = NSEvent.modifierFlags
        if mods.contains(.option) { pick(item.path, toggle: true); return }
        if mods.contains(.shift) { pickTo(item.path); return }
        if mods.contains(.command) && !item.folder { vault.openInNewTab(path: item.path); return }
        if !picked.isEmpty { picked = [] }
        anchor = item.path
        activate(row)
    }

    /// What a row does when pressed: a folder opens or closes, a file opens here, a folder found by a search is shown in the tree.
    func activate(_ row: Row) {
        switch row.kind {
        case .folder(let item): setOpen(item.path, !vault.isOpen(item.path))
        case .file(let item, _), .foundFile(let item, _, _): vault.show(path: item.path)
        case .foundFolder(let item, _): vault.showInTree(item.path)
        case .topic(let entry): vault.show(entry.file)
        default: break
        }
    }

    func setOpen(_ folder: String, _ open: Bool) {
        withAnimation(SageColors.motion ? .easeOut(duration: 0.18) : nil) { vault.setOpen(folder, open) }
        vault.objectWillChange.send()
    }

    func pick(_ path: String, toggle: Bool) {
        if toggle { if picked.contains(path) { picked.remove(path) } else { picked.insert(path) } }
        anchor = path
    }

    func pickTo(_ path: String) {
        let order = cachedRows().filter { $0.section == nil }.compactMap { $0.item?.path }
        guard let anchor, let from = order.firstIndex(where: { Study.same($0, anchor) }), let to = order.firstIndex(where: { Study.same($0, path) }) else { pick(path, toggle: true); return }
        for p in order[min(from, to) ... max(from, to)] { picked.insert(p) }
    }

    // MARK: Menus

    @ViewBuilder func menu(_ row: Row, _ item: Study.VaultItem) -> some View {
        if picked.count > 1 && picked.contains(item.path) { pickedMenu() }
        else if item.folder { folderMenu(item) }
        else { fileMenu(item) }
    }

    @ViewBuilder func fileMenu(_ item: Study.VaultItem) -> some View {
        let full = vault.full(item.path)
        let link = item.ext == ".md" ? "[[\(item.title)]]" : "[[\(item.name)]]"
        Button(L("Open in new tab")) { vault.openInNewTab(path: item.path) }
        Button(vault.isPinned(item.path) ? L("Unpin") : L("Pin to the top")) { vault.togglePin(item.path) }
        Divider()
        Button(L("Rename…  (F2)")) { vault.renaming = item.path }
        Button(L("Duplicate")) { vault.duplicate(item.path) }
        Button(L("Move to…")) { vault.switcher = .move([item.path]) }
        Button(L("Delete  (⌘⌫)")) { vault.delete([item.path]) }
        Divider()
        Button(L("Copy link")) { Self.copy(link) }
        Button(L("Copy path")) { Self.copy(item.path) }
        Button(L("Open in Obsidian")) { Self.openInObsidian(full) }
        Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([full]) }
    }

    @ViewBuilder func folderMenu(_ folder: Study.VaultItem) -> some View {
        let templates = self.templates()
        let topicFolder = desk.folder.flatMap(vault.inVault).map { Study.same($0, folder.path) } ?? false
        Button(L("New note")) { newNoteHere(folder.path) }
        Menu(L("New note from template")) {
            ForEach(templates, id: \.path) { template in Button(template.title) { newNoteHere(folder.path, template: template.path) } }
        }.disabled(templates.isEmpty)
        Button(L("New folder")) { newFolderIn(folder.path) }
        Divider()
        Button(L("Rename…  (F2)")) { vault.renaming = folder.path }
        Button(L("Move to…")) { vault.switcher = .move([folder.path]) }
        Button(L("Delete  (⌘⌫)")) { vault.delete([folder.path]) }
        Divider()
        colorMenu(folder.path)
        checkItem(L("Write “%@” notes here", desk.topic.name), topicFolder) { vault.writeHere(folder.path) }
        Button(L("Copy path")) { Self.copy(folder.path) }
        Button(L("Show in Finder")) { NSWorkspace.shared.open(vault.full(folder.path)) }
    }

    /// The colour menu on a folder: automatic (its own), one of the eight, or none.
    func colorMenu(_ path: String) -> some View {
        let chosen = vault.folderColor(path)
        return Menu(L("Colour")) {
            checkItem(L("Automatic (its top folder's, or the colour of a folder it's in)"), chosen == nil) { vault.setFolderColor(path, nil) }
            Divider()
            ForEach(SageColors.hueNames, id: \.self) { name in checkItem(L(name.prefix(1).uppercased() + name.dropFirst()), chosen == name) { vault.setFolderColor(path, name) } }
            Divider()
            checkItem(L("None"), chosen == "none") { vault.setFolderColor(path, "none") }
        }
    }

    @ViewBuilder func pickedMenu() -> some View {
        let paths = Array(picked)
        let files = paths.filter { vault.item($0).map { !$0.folder } ?? false }
        Button(L("Open %@ in new tabs", "\(files.count)")) { for file in files { vault.openInNewTab(path: file, behind: true) } }.disabled(files.isEmpty)
        Button(L("Move %@ to…", "\(paths.count)")) { vault.switcher = .move(paths) }
        Button(L("Delete %@", "\(paths.count)")) { vault.delete(paths); picked = [] }
        Divider()
        Button(L("Let go of them  (Esc)")) { picked = [] }
    }

    static func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }

    /// Opens a file in Obsidian (it must be inside a vault Obsidian knows); without Obsidian, the file as it is.
    static func openInObsidian(_ file: URL) {
        var parts = URLComponents(); parts.scheme = "obsidian"; parts.host = "open"
        parts.queryItems = [URLQueryItem(name: "path", value: file.path)]
        if let url = parts.url, NSWorkspace.shared.urlForApplication(toOpen: url) != nil { NSWorkspace.shared.open(url) } else { NSWorkspace.shared.open(file) }
    }

    /// The notes in your Templates folder (core Templates' templates.json).
    func templates() -> [Study.VaultItem] {
        guard let folder = vault.templatesFolder else { return [] }
        return vault.items.filter { !$0.folder && $0.ext == ".md" && $0.path.lowercased().hasPrefix(folder.lowercased() + "/") }
            .sorted { Study.natural($0.title, $1.title) < 0 }
    }

    /// A new note: in the folder given, else where the vault puts new notes (app.json newFileLocation), opened and named in place.
    func newNoteHere(_ folder: String?, template: String? = nil) {
        filter = ""; search = ""
        vault.newNoteHere(folder, template: template)
    }

    func newFolderIn(_ parent: String) {
        filter = ""; search = ""
        if let made = vault.newFolder(in: parent) { vault.renaming = made }
    }

    // MARK: Renaming in place

    func finishRename(_ path: String, keep: Bool) {
        guard let renaming = vault.renaming, Study.same(renaming, path) else { return }
        vault.renaming = nil
        let name = renameText.trimmingCharacters(in: .whitespaces)
        let was = vault.item(path).map { $0.folder ? $0.name : $0.title } ?? ""
        if keep && name != was && !name.isEmpty { vault.rename(path, to: name) }
        treeFocused = true
    }

    // MARK: Keys in the tree

    func keys(_ press: KeyPress, _ all: [Row]) -> KeyPress.Result {
        if vault.renaming != nil { return .ignored }
        let rows = all.filter(\.actionable)
        guard !rows.isEmpty else { return .ignored }
        let index = cursor.flatMap { key in rows.firstIndex { $0.id == key } } ?? -1
        let row = index >= 0 ? rows[index] : nil
        let command = press.modifiers.contains(.command), shift = press.modifiers.contains(.shift)
        func go(_ i: Int) -> KeyPress.Result { cursor = rows[min(max(0, i), rows.count - 1)].id; return .handled }
        switch press.key {
        case .downArrow:
            let result = go(index + 1)
            if shift, index + 1 < rows.count, let path = rows[index + 1].item?.path { pickTo(path) }
            return result
        case .upArrow:
            let result = go(index < 0 ? 0 : index - 1)
            if shift, index > 0, let path = rows[index - 1].item?.path { pickTo(path) }
            return result
        case .home: return go(0)
        case .end: return go(rows.count - 1)
        case .rightArrow:
            guard let row, case .folder(let item) = row.kind else { return .ignored }
            if !vault.isOpen(item.path) { setOpen(item.path, true); return .handled }
            return go(index + 1)
        case .leftArrow:
            guard let row else { return .ignored }
            if case .folder(let item) = row.kind, vault.isOpen(item.path) { setOpen(item.path, false); return .handled }
            if let parent = row.item?.parent, !parent.isEmpty, row.section == nil, let up = rows.firstIndex(where: { $0.id == parent }) { return go(up) }
            return .handled
        case .return:
            guard let row else { return .ignored }
            if command, let item = row.item, !item.folder { vault.openInNewTab(path: item.path); return .handled }
            activate(row)
            return .handled
        case .escape:
            if !picked.isEmpty { picked = []; return .handled }
            return .ignored
        case .deleteForward:
            return deleteKey(row)
        case .delete where command:
            return deleteKey(row)
        default: break
        }
        // F2 renames, as in Creative Assist.
        if let f2 = UnicodeScalar(UInt32(NSF2FunctionKey)), press.characters == String(Character(f2)), let row, row.section == nil, let item = row.item {
            vault.renaming = item.path; return .handled
        }
        if command {
            switch press.characters.lowercased() {
            case "z": vault.undo(); return .handled
            case "a": for r in rows where r.section == nil { if let path = r.item?.path { picked.insert(path) } }; return .handled
            case "o": vault.switcher = .open; return .handled
            case "n": newNoteHere(nil); return .handled
            default: return .ignored
            }
        }
        // Typing a name's first letters goes to it.
        guard !press.modifiers.contains(.option), !press.modifiers.contains(.control), let letter = press.characters.first, letter.isLetter || letter.isNumber || letter == " " else { return .ignored }
        typed = Date().timeIntervalSince(typedAt) < 0.9 ? typed + String(letter) : String(letter)
        typedAt = Date()
        for k in 0 ..< rows.count {
            let i = (max(index, 0) + (typed.count == 1 ? 1 : 0) + k) % rows.count
            if rows[i].name.lowercased().hasPrefix(typed.lowercased()) { return go(i) }
        }
        return .handled
    }

    func deleteKey(_ row: Row?) -> KeyPress.Result {
        let paths = !picked.isEmpty ? Array(picked) : row?.section == nil ? [row?.item?.path].compactMap { $0 } : []
        guard !paths.isEmpty else { return .ignored }
        vault.delete(paths)
        picked = []
        return .handled
    }

    // MARK: Cmd held over a note: its preview; the middle button: a new tab

    func listen() {
        guard monitors.isEmpty else { return }
        let flags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            if event.modifierFlags.contains(.command) {
                if let key = hovered, let item = vault.item(key), !item.folder { vault.preview = .init(path: item.path, at: nil) }
            } else if vault.preview?.at == nil, vault.preview != nil {
                vault.preview = nil
            }
            return event
        }
        let middle = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
            if event.buttonNumber == 2, let key = hovered {
                if let item = vault.item(key), !item.folder { vault.openInNewTab(path: item.path); return nil }
                if key.hasPrefix("note:") { vault.openInNewTab(URL(fileURLWithPath: String(key.dropFirst(5)))); return nil }
                if let colon = key.firstIndex(of: ":"), let item = vault.item(String(key[key.index(after: colon)...])), !item.folder { vault.openInNewTab(path: item.path); return nil }
            }
            return event
        }
        monitors = [flags, middle].compactMap { $0 }
    }

    // MARK: The note at the bottom: what changed, and Undo

    @ViewBuilder var toastView: some View {
        if let toast {
            let undone = toast.text.hasPrefix(L("Undone: %@", ""))
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: toast.undo || undone ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").font(.system(size: 12))
                    .foregroundStyle(toast.undo || undone ? accent : .orange)
                Text(toast.text).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if toast.undo {
                    Button(L("Undo")) { withAnimation { self.toast = nil }; vault.undo() }.controlSize(.small).help(L("⌘Z in the tree"))
                }
            }
            .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .padding(10)
            .transition(SageColors.motion ? .move(edge: .bottom).combined(with: .opacity) : .opacity)
        }
    }
}

private struct TreeOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Drag and drop on the tree: rows from the tree move into the folder (a file's own folder when dropped on a file, the
/// vault's top on empty space); files from Finder are copied in. A closed folder held over opens (as in Notebook
/// Navigator and Finder).
private struct TreeDrop: DropDelegate {
    let explorer: SageExplorer
    let folder: String
    let key: String?

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropEntered(info: DropInfo) {
        explorer.enterDrop(folder, opens: key)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: explorer.dragPathsNow.isEmpty ? .copy : .move)
    }

    func dropExited(info: DropInfo) { explorer.leaveDrop(folder) }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        explorer.leaveDrop(folder)
        let target = folder
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { MainActor.assumeIsolated { explorer.drop(urls, into: target) } }
        return true
    }
}

extension SageExplorer {
    var dragPathsNow: [String] { dragPaths }

    func enterDrop(_ folder: String, opens key: String?) {
        dropTarget = folder.isEmpty ? nil : folder
        guard let key, !vault.isOpen(key) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            if dropTarget.map({ Study.same($0, key) }) == true { setOpen(key, true) }
        }
    }

    func leaveDrop(_ folder: String) {
        if dropTarget.map({ Study.same($0, folder) }) == true { dropTarget = nil }
    }

    /// Dropped: files of this vault move (all the rows picked when one of them was dragged), files from elsewhere are copied in.
    func drop(_ urls: [URL], into folder: String) {
        var inside: [String] = [], outside: [URL] = []
        for url in urls { if let path = vault.inVault(url) { inside.append(path) } else { outside.append(url) } }
        if !inside.isEmpty {
            let paths = inside.contains(where: { path in dragPaths.contains { Study.same($0, path) } }) && dragPaths.count > inside.count ? dragPaths : inside
            // Nothing moves into where it already is, into itself, or into a folder inside it.
            let moving = paths.filter { p in
                !Study.same(Study.VaultItem(path: p, folder: false).parent, folder) && !Study.same(p, folder) && !folder.lowercased().hasPrefix(p.lowercased() + "/")
            }
            if !moving.isEmpty { vault.move(moving, into: folder) }
            picked = []
        }
        if !outside.isEmpty { vault.copyIn(outside, into: folder) }
        dragPaths = []
    }
}

extension SageTreeLook {
    /// How many files each folder holds (all the way down), as the tree shows them.
    func counts(_ vault: SageVaultDesk) -> [String: Int] {
        let key = "\(vault.version)|\(vault.settings.notesOnly)|\(vault.items.count)"
        if let cached = SageTreeLook.countCache, cached.key == key { return cached.counts }
        var counts: [String: Int] = [:]
        for item in vault.items where !item.folder && vault.shown(item) {
            var p = item.parent
            while !p.isEmpty { counts[p.lowercased(), default: 0] += 1; p = Study.VaultItem(path: p, folder: true).parent }
        }
        SageTreeLook.countCache = (key, counts)
        return counts
    }
    @MainActor static var countCache: (key: String, counts: [String: Int])?
}

extension SageVaultDesk {
    /// A new note (Cmd+N in the tree or the note): in the folder given, else where the vault puts new notes (app.json
    /// newFileLocation), from a template when one is given, opened and named in place in the tree.
    func newNoteHere(_ folder: String?, template: String? = nil) {
        if let made = newNote(in: folder ?? newNoteFolder, template: template) {
            openFolders(above: made)
            renaming = made
        }
    }
}

// MARK: Hover preview (hold Cmd over a note in the tree, or a link in a note)

/// The note held under Cmd, as a card: its title, when it was edited and made, and the start of its text (1,800
/// characters). Beside the tree it's a popover; for a link in a note, the note view places it where the link is.
struct SageNotePreview: View {
    @ObservedObject var vault: SageVaultDesk

    init(vault: SageVaultDesk) { self.vault = vault }

    var body: some View {
        if let preview = vault.preview, let item = vault.item(preview.path), !item.folder {
            let text = Self.text(item, vault)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 14, weight: .semibold))
                Text(SageExplorer.dates(item).components(separatedBy: "\n").last ?? "").font(.system(size: 10.5)).foregroundStyle(.secondary)
                Divider().padding(.vertical, 6)
                ScrollView {
                    Group {
                        if item.ext == ".md" {
                            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if body.isEmpty { Text(L("*Empty note*")).italic().foregroundStyle(.secondary) }
                            else { Text((try? AttributedString(markdown: body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(body)) }
                        } else {
                            Text(L("%@ file", String(item.ext.dropFirst()).uppercased())).foregroundStyle(.secondary)
                        }
                    }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }.scrollIndicators(.hidden).frame(maxHeight: 340)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(width: 400, alignment: .leading)
            .allowsHitTesting(false)
        }
    }

    static func text(_ item: Study.VaultItem, _ vault: SageVaultDesk) -> String {
        guard item.ext == ".md", let note = try? Study.readNote(vault.full(item.path)) else { return "" }
        var body = Study.split(note.text).body
        if body.count > 1800 { body = String(body.prefix(1800)) + "…" }
        return body
    }
}

// MARK: The quick switcher (Cmd+O): any file or folder by a few of its letters

/// The quick switcher: type a few letters of a note, a folder, a file or a note's alias; recent ones first when nothing's
/// typed. Return opens it here, Cmd+Return in a new tab, Esc closes. Moving (vault.switcher is .move), it picks a folder to
/// move those files into.
struct SageSwitcher: View {
    @ObservedObject var vault: SageVaultDesk
    @State private var query = ""
    @State private var chosen = 0
    @State private var aliases: [String: [String]] = [:]
    @FocusState private var focused: Bool
    private let accent = PixelSage.theme

    init(vault: SageVaultDesk) { self.vault = vault }

    var moving: [String]? { if case .move(let paths) = vault.switcher { return paths } else { return nil } }

    struct Choice { var item: Study.VaultItem; var alias: String?; var score: Int; var at: [Int] }

    var choices: [Choice] {
        let words = query.trimmingCharacters(in: .whitespaces)
        let pool: [Study.VaultItem] = moving != nil ? [Study.VaultItem(path: "", folder: true)] + vault.items.filter(\.folder) : vault.items.filter(vault.shown)
        var recent: [String: Int] = [:]
        for (i, p) in vault.settings.recent.enumerated() where recent[p.lowercased()] == nil { recent[p.lowercased()] = i }
        var scored: [Choice] = []
        for item in pool {
            let name = item.path.isEmpty ? L("The vault (top level)") : item.title
            var match = Study.fuzzy(words, name)
            var alias: String?
            if match == nil, let names = aliases[item.path.lowercased()] {
                for a in names { if let m = Study.fuzzy(words, a) { match = (m.score - 5, []); alias = a; break } }
            }
            if match == nil, words.contains("/"), let byPath = Study.fuzzy(words, item.path) { match = (byPath.score - 30, []) }
            guard let match else { continue }
            let score = match.score + (recent[item.path.lowercased()].map { 60 - $0 * 6 } ?? 0) + (item.ext == ".md" ? 4 : 0)
            scored.append(Choice(item: item, alias: alias, score: score, at: match.at))
        }
        return Array(scored.sorted { $0.score != $1.score ? $0.score > $1.score : Study.natural($0.item.title, $1.item.title) < 0 }.prefix(12))
    }

    var body: some View {
        let shown = choices
        VStack(alignment: .leading, spacing: 0) {
            TextField(moving.map { $0.count == 1 ? L("Move “%@” to…", SageVaultDesk.name($0[0])) : L("Move %@ items to…", "\($0.count)") } ?? L("Find a note, a folder or a file…"), text: $query)
                .textFieldStyle(.plain).font(.system(size: 15)).padding(.horizontal, 14).padding(.vertical, 10)
                .focused($focused)
                .accessibilityLabel(moving != nil ? L("Move to folder") : L("Quick switcher"))
                .onChange(of: query) { _, _ in chosen = 0 }
                .onKeyPress(.downArrow) { chosen = min(shown.count - 1, chosen + 1); return .handled }
                .onKeyPress(.upArrow) { chosen = max(0, chosen - 1); return .handled }
                .onKeyPress(.return) { choose(shown, newTab: NSEvent.modifierFlags.contains(.command)); return .handled }
                .onExitCommand { vault.switcher = nil }
            Divider()
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, choice in
                    Button { chosen = index; choose(shown, newTab: NSEvent.modifierFlags.contains(.command)) } label: { line(choice, on: index == chosen) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.item.path.isEmpty ? L("The vault") : choice.item.title)
                        .onHover { if $0 { chosen = index } }
                }
                if shown.isEmpty {
                    Text(moving != nil ? L("No folder is called that.") : L("Nothing in the vault is called that.")).font(.system(size: 12)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(6)
            Text(moving != nil ? L("↑↓ to choose · Return to move here · Esc to close") : L("↑↓ to choose · Return to open · ⌘Return in a new tab · Esc to close"))
                .font(.system(size: 10.5)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 10).padding(.top, 2)
        }
        .frame(width: 580)
        .onAppear { focused = true; readAliases() }
    }

    func line(_ choice: Choice, on: Bool) -> some View {
        let item = choice.item
        let place = (choice.alias.map { L("alias “%@”", $0) + " · " } ?? "")
            + (!item.parent.isEmpty ? item.parent.replacingOccurrences(of: "/", with: " / ") : item.path.isEmpty ? "" : L("top of the vault"))
        return HStack(spacing: 10) {
            if item.folder {
                Image(systemName: item.path.isEmpty ? "books.vertical" : "folder").font(.system(size: 13))
                    .foregroundStyle(item.path.isEmpty ? Color.secondary : SageColors.hues[Study.hue(item.path.components(separatedBy: "/")[0])].color).frame(width: 18)
            } else {
                Image(systemName: SagePathBar.symbol(item)).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                SageExplorer.lit(item.path.isEmpty ? L("The vault (top level)") : item.title, choice.at, accent).font(.system(size: 13)).lineLimit(1)
                if !place.isEmpty { Text(place).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(on ? accent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }

    func choose(_ shown: [Choice], newTab: Bool) {
        guard shown.indices.contains(chosen) else { return }
        let item = shown[chosen].item
        let moving = self.moving
        vault.switcher = nil
        if let moving { vault.move(moving, into: item.path); return }
        if item.folder { vault.showInTree(item.path) }
        else if newTab { vault.openInNewTab(path: item.path) }
        else { vault.show(path: item.path) }
    }

    /// The notes' aliases (their "aliases" property), read off the main thread.
    func readAliases() {
        guard let root = vault.vault else { return }
        let items = vault.items
        Task {
            aliases = await Task.detached {
                var found: [String: [String]] = [:]
                for note in Study.baseNotes(vault: root, items: items, finder: Study.LinkFinder(items)) {
                    guard let value = note.prop("aliases") else { continue }
                    let names = ((value as? [Any?]) ?? [value]).compactMap { $0.map { "\($0)" } }.filter { !$0.isEmpty }
                    if !names.isEmpty { found[note.item.path.lowercased()] = names }
                }
                return found
            }.value
        }
    }
}

// MARK: The path above the note: each folder shows where it is in the tree, its › lists what it holds

/// The path above the note: each folder (and the file) shows where it is in the tree when pressed (the tree's search and
/// status filter make way for it); the › after a folder lists what's in it, to go sideways without the tree. Too long for
/// the bar, the middle folders fold into “…”, then the first, then the last; the file's name stays.
struct SagePathBar: View {
    @ObservedObject var vault: SageVaultDesk
    let file: URL

    init(vault: SageVaultDesk, file: URL) { self.vault = vault; self.file = file }

    var shownName: String { file.pathExtension.lowercased() == "md" ? file.deletingPathExtension().lastPathComponent : file.lastPathComponent }

    var body: some View {
        Group {
            if let path = vault.inVault(file) {
                let parts = path.components(separatedBy: "/")
                let folders = (0 ..< parts.count - 1).map { (name: parts[$0], path: parts[...$0].joined(separator: "/")) }
                let order = Self.foldOrder(folders.count)
                // How many folders fold is worked out from the names' widths (`folded`), once per size: a ViewThatFits laid
                // out every way of folding on every layout pass, and inside the page's scroll view that was most of what a
                // click on a note cost (2026-11-09).
                GeometryReader { space in
                    line(folders, hidden: Set(order.prefix(Self.folded(folders.map(\.name), name: shownName, order: order, width: space.size.width))), path: path)
                        .frame(width: space.size.width, height: space.size.height, alignment: .leading)
                }
                .frame(height: 20)
            } else {
                Text(shownName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
        }.help(file.path)
    }

    /// How many folders (in `order`) fold into “…” for the path to fit the width: the fewest that do, all when none do.
    static func folded(_ names: [String], name: String, order: [Int], width: CGFloat) -> Int {
        let chevron: CGFloat = 14, dots = textWidth("…") + chevron
        let last = textWidth(name, bold: true)
        for hidden in 0 ... order.count {
            let gone = Set(order.prefix(hidden))
            let shown = names.indices.filter { !gone.contains($0) }.reduce(CGFloat(0)) { $0 + textWidth(names[$1]) + chevron }
            if shown + (gone.isEmpty ? 0 : dots) + last <= width { return hidden }
        }
        return order.count
    }

    /// A name's width in the bar's font, measured once and kept.
    static func textWidth(_ text: String, bold: Bool = false) -> CGFloat {
        let key = (bold ? "b:" : "r:") + text
        if let known = widths[key] { return known }
        let measured = ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: bold ? .semibold : .regular)]).width)
        widths[key] = measured
        return measured
    }
    @MainActor private static var widths: [String: CGFloat] = [:]

    /// What folds first when the bar is too narrow: the middle folders, then the first, then the last.
    static func foldOrder(_ count: Int) -> [Int] {
        var order = count > 2 ? Array(1 ..< count - 1).sorted { abs(Double($0) - Double(count - 1) / 2) < abs(Double($1) - Double(count - 1) / 2) } : []
        if count >= 1 { order.append(0) }
        if count >= 2 { order.append(count - 1) }
        return order
    }

    /// A part of the path: a folder, or one “…” for every folded folder, wherever they are.
    enum Part { case folder(name: String, path: String), folded([(name: String, path: String)]) }

    func line(_ folders: [(name: String, path: String)], hidden: Set<Int>, path: String) -> some View {
        var parts: [Part] = []
        let folded = folders.enumerated().filter { hidden.contains($0.offset) }.map(\.element)
        for (i, folder) in folders.enumerated() {
            if !hidden.contains(i) { parts.append(.folder(name: folder.name, path: folder.path)) }
            else if case .folded = parts.last {} else if !parts.contains(where: { if case .folded = $0 { return true } else { return false } }) { parts.append(.folded(folded)) }
        }
        return HStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case let .folder(name, folderPath):
                    crumb(name, folderPath, last: false)
                    chevron(folderPath)
                case let .folded(list):
                    Menu {
                        ForEach(list, id: \.path) { f in Button(f.name) { vault.showInTree(f.path) } }
                    } label: { Text("…").font(.system(size: 12)).foregroundStyle(.secondary) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help(list.map(\.name).joined(separator: " / ")).accessibilityLabel(L("Folded folders"))
                    chevron(list[list.count - 1].path)
                }
            }
            crumb(shownName, path, last: true)
        }.lineLimit(1)
    }

    func crumb(_ text: String, _ target: String, last: Bool) -> some View {
        Crumb(text: text, last: last) { vault.showInTree(target) }
            .help(last ? L("Show it in the tree") : L("Show “%@” in the tree", text))
    }

    struct Crumb: View {
        let text: String
        let last: Bool
        let action: () -> Void
        @State private var over = false
        var body: some View {
            Button(action: action) {
                Text(text).font(.system(size: 12, weight: last ? .semibold : .regular)).foregroundStyle(last || over ? Color.primary : Color.secondary)
                    .underline(over).lineLimit(1).truncationMode(.middle)
            }.buttonStyle(.plain).onHover { over = $0 }
        }
    }

    /// The › after a folder in the path: what's in that folder (its folders open onto theirs). The menu is built when you
    /// click it, and each folder's submenu when you open it (`SageFolderMenu`): a SwiftUI Menu built all of them, three
    /// folders deep, on every redraw of the page, which made notes take seconds to open (2026-11-09).
    func chevron(_ folder: String) -> some View {
        Button { SageFolderMenu.show(folder, vault: vault) } label: {
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 3).frame(maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain).fixedSize()
        .help(L("What's in this folder")).accessibilityLabel(L("What's in %@", (folder as NSString).lastPathComponent))
    }

    /// A file's icon by its type, where the tree's look (each note's kind) isn't at hand.
    static func symbol(_ item: Study.VaultItem) -> String {
        switch item.ext {
        case ".md": return "doc.text"
        case ".canvas": return "rectangle.3.group"
        case ".base": return "tablecells"
        case ".pdf": return "doc.richtext"
        case _ where Study.pictureTypes.contains(item.ext): return "photo"
        case ".mp3", ".wav", ".m4a", ".ogg", ".flac": return "waveform"
        case ".mp4", ".mov", ".webm", ".mkv", ".ogv": return "film"
        default: return "doc"
        }
    }
}

/// A folder's contents as a menu, filled in only when it opens (so a submenu costs nothing until you point at it).
@MainActor final class SageFolderMenu: NSObject, NSMenuDelegate {
    private weak var vault: SageVaultDesk?
    private let folder: String, depth: Int
    private var built = false
    private var submenus: [SageFolderMenu] = []

    init(vault: SageVaultDesk, folder: String, depth: Int) { self.vault = vault; self.folder = folder; self.depth = depth }

    /// Opens the folder's menu under the pointer; it stays open until you pick or leave it.
    static func show(_ folder: String, vault: SageVaultDesk) {
        let menu = NSMenu()
        let filler = SageFolderMenu(vault: vault, folder: folder, depth: 0)
        menu.delegate = filler
        filler.fill(menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        _ = filler
    }

    func menuNeedsUpdate(_ menu: NSMenu) { fill(menu) }

    private func fill(_ menu: NSMenu) {
        guard !built, let vault else { return }
        built = true
        menu.removeAllItems()
        if depth > 0 {
            menu.addItem(SageMenuItem(title: L("Show in the tree")) { [weak vault, folder] in vault?.showInTree(folder) })
            menu.addItem(.separator())
        }
        let kids = vault.children(of: folder)
        if kids.isEmpty {
            let empty = NSMenuItem(title: L("Empty"), action: nil, keyEquivalent: ""); empty.isEnabled = false
            menu.addItem(empty)
        }
        for item in kids.prefix(60) {
            let entry = SageMenuItem(title: item.folder ? item.name : item.title) { [weak vault] in
                if item.folder { vault?.showInTree(item.path) } else { vault?.show(path: item.path) }
            }
            entry.image = NSImage(systemSymbolName: item.folder ? "folder" : SagePathBar.symbol(item), accessibilityDescription: nil)
            if item.folder, depth < 3, !vault.children(of: item.path).isEmpty {
                let submenu = NSMenu()
                let filler = SageFolderMenu(vault: vault, folder: item.path, depth: depth + 1)
                submenu.delegate = filler
                submenus.append(filler)
                // A placeholder, so the submenu opens and asks to be filled.
                submenu.addItem(NSMenuItem(title: "…", action: nil, keyEquivalent: ""))
                entry.submenu = submenu
            }
            menu.addItem(entry)
        }
    }
}

/// A menu item that runs a closure.
final class SageMenuItem: NSMenuItem {
    private let run: () -> Void
    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(go), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
    @objc private func go() { run() }
}
