import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// Sage's note view (2026-11-07 in Creative Assist, brought back 2026-11-09): the open file drawn as Obsidian draws it, in
// a WKWebView per tab, with the tab row and the bar above it. Windows' WebView2 mapped made-up hosts to folders; here one
// WKURLSchemeHandler serves sage://sage/ — the pages Sage makes (kept in memory, never handed over as a string, so no page
// is too big), the vault's files, and Obsidian's own app.css, fonts and icons.

/// Serves the note view's pages, the vault and Obsidian's files under sage://sage/ (one origin, so fonts and pictures load).
@MainActor final class SageScheme: NSObject, WKURLSchemeHandler {
    static let shared = SageScheme()
    /// The pages made for the tabs, by name; a page goes when its tab lets go of it.
    var pages: [String: Data] = [:]
    /// The vault served under /vault/ (one at a time, the one the notes stage browses).
    var vault: URL?
    /// Obsidian's files copied from the installed Obsidian (Study.obsidianStyle), served under /obsidian/.
    var obsidian: URL?
    private var stopped: Set<ObjectIdentifier> = []

    /// Obsidian's look read once a run, off the main thread, into Sage's cache folder.
    static let obsidianFiles: Task<URL?, Never> = Task.detached {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Edit Assist/sage-obsidian", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        return Study.obsidianStyle(cache: cache)
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        let path = url.path
        func file(under root: URL?, _ prefix: String) -> URL? {
            guard let root else { return nil }
            let rest = String(path.dropFirst(prefix.count))
            let found = root.appendingPathComponent(rest).standardizedFileURL
            // Only what's inside its folder: a "../" never reaches anything else on the Mac.
            return found.path.hasPrefix(root.standardizedFileURL.path + "/") ? found : nil
        }
        if path.hasPrefix("/page/"), let data = pages[String(path.dropFirst("/page/".count))] {
            answer(task, url: url, data: data, type: "text/html; charset=utf-8")
            return
        }
        let target = path.hasPrefix("/vault/") ? file(under: vault, "/vault/") : path.hasPrefix("/obsidian/") ? file(under: obsidian, "/obsidian/") : nil
        guard let target else { task.didFailWithError(URLError(.fileDoesNotExist)); return }
        let id = ObjectIdentifier(task)
        let type = UTType(filenameExtension: target.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        // A video or sound in a note asks for its bytes a range at a time (2026-11-09): answered with just that range.
        let range = task.request.value(forHTTPHeaderField: "Range").flatMap(Study.byteRange)
        Task.detached {
            var data: Data?, total = 0
            if let range, let handle = try? FileHandle(forReadingFrom: target) {
                total = Int((try? handle.seekToEnd()) ?? 0)
                let end = min(range.upperBound ?? total - 1, total - 1)
                if range.lowerBound <= end {
                    try? handle.seek(toOffset: UInt64(range.lowerBound))
                    data = try? handle.read(upToCount: end - range.lowerBound + 1)
                }
                try? handle.close()
            } else {
                data = try? Data(contentsOf: target, options: .mappedIfSafe)
            }
            let part = range.map { ($0.lowerBound, total) }
            await MainActor.run {
                guard !self.stopped.contains(id) else { self.stopped.remove(id); return }
                if let data { self.answer(task, url: url, data: data, type: type, part: part) } else { task.didFailWithError(URLError(.fileDoesNotExist)) }
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { stopped.insert(ObjectIdentifier(task)) }

    private func answer(_ task: WKURLSchemeTask, url: URL, data: Data, type: String, part: (from: Int, total: Int)? = nil) {
        var headers = ["Content-Type": type, "Content-Length": "\(data.count)", "Accept-Ranges": "bytes"]
        if let part { headers["Content-Range"] = "bytes \(part.from)-\(part.from + data.count - 1)/\(part.total)" }
        let response = HTTPURLResponse(url: url, statusCode: part == nil ? 200 : 206, httpVersion: "HTTP/1.1",
                                       headerFields: headers.merging(["Access-Control-Allow-Origin": "*",
                                                    // Obsidian's own files never change within a version: kept, not fetched again for every note.
                                                    "Cache-Control": url.path.hasPrefix("/obsidian/") ? "max-age=86400, immutable" : "no-cache"], uniquingKeysWith: { $1 }))!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    /// One configuration for every tab's web view: the scheme, and nothing in a note runs (notes are drawn from escaped
    /// Markdown; only Sage's own page script runs).
    static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(SageScheme.shared, forURLScheme: Study.pageScheme)
        configuration.websiteDataStore = .nonPersistent()
        return configuration
    }
}

/// A tab's page: its web view, what it shows, and what the page says back (a block edited, a task ticked, a canvas
/// saved, a link followed, a key pressed). One per tab, so a tab keeps where you were and what you're editing.
@MainActor final class SageNotePage: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let web: WKWebView
    /// Why the file couldn't be shown, said in the pane (never the page before it, never a pop-up).
    @Published private(set) var problem: String?
    /// Editing or reading as you chose it (Cmd+E or the bar's button); until you choose, the vault's default view.
    @Published private(set) var editChoice: Bool?
    var follow: (URL, Bool) -> Void = { _, _ in }
    var command: (String) -> Void = { _ in }
    var preview: (String, CGPoint?) -> Void = { _, _ in }
    let keep: URL

    private var shownKey = "", lookKey = "", expected: URL?, page: String?
    private var file: URL?, vault: URL?, path: String?
    private var look = Study.Look(), dark = true
    private var items: [Study.VaultItem] = []
    private var isNote = false, blockOpen = false, reloadWaiting = false
    private static var count = 0

    init(keep: URL) {
        self.keep = keep
        web = WKWebView(frame: .zero, configuration: SageScheme.configuration())
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        web.allowsBackForwardNavigationGestures = false
        web.configuration.userContentController.add(Relay(self), name: "sage")
    }

    /// The message handler holds the page weakly, so a page let go is freed.
    private final class Relay: NSObject, WKScriptMessageHandler {
        weak var page: SageNotePage?
        init(_ page: SageNotePage) { self.page = page }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            MainActor.assumeIsolated { page?.userContentController(controller, didReceive: message) }
        }
    }

    func editing(_ look: Study.Look) -> Bool { editChoice ?? look.editByDefault }

    func setEditing(_ on: Bool) {
        Task {
            await flush()
            editChoice = on
            shownKey = ""
            if let file { show(file, look: look, dark: dark, vault: vault, items: items, path: path) }
        }
    }

    private func key(_ file: URL) -> String {
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        return "\(file.path)|\(modified)|\(lookKey)|\(items.count)"
    }

    /// The file read off the main thread and made into its page: a note (with its pictures, when it is in the vault), a
    /// Base, a canvas, a picture, or a PDF in WebKit's own viewer. Redrawn only when the file, the vault or its look
    /// changed; the same note changed on disk is redrawn in place, and not while you're editing a part of it.
    func show(_ file: URL, look: Study.Look, dark: Bool, vault: URL?, items: [Study.VaultItem], path: String?) {
        let ext = file.pathExtension.lowercased()
        let editing = ext == "md" && self.editing(look)
        let newLookKey = "\(look.css.count)|\(look.accent)|\(dark)|\(look.properties)|\(look.inlineTitle)|\(look.readable)|\(look.types.count)|\(vault?.path ?? "")|\(editing)"
        let same = isNote && file.standardizedFileURL == self.file?.standardizedFileURL && newLookKey == lookKey
        lookKey = newLookKey; self.items = items
        let wanted = key(file)
        if wanted == shownKey { return }
        if same && blockOpen { reloadWaiting = true; return }
        Task {
            if blockOpen { await flush() }
            self.file = file; self.vault = vault; self.path = path; self.look = look; self.dark = dark
            shownKey = wanted
            if same { sendBody(); return }
            isNote = false
            let appFolder = await SageScheme.obsidianFiles.value
            guard shownKey == wanted else { return }
            SageScheme.shared.obsidian = appFolder
            if let vault { SageScheme.shared.vault = vault }
            let app = appFolder == nil ? nil : Study.obsidianBase
            let inVault = vault != nil && path != nil
            if ext == "pdf", inVault, let path {
                problem = nil
                load(URL(string: Study.vaultAddress(path))!)
                return
            }
            let note = ext == "md" || !inVault
            let html = await Task.detached { () -> String in
                let served = inVault ? Study.vaultBase : nil
                var plain = look
                plain.inlineTitle = false
                do {
                    var page: String
                    if note {
                        page = Study.notePage(try Study.readNote(file).text, look: look, dark: dark, title: file.deletingPathExtension().lastPathComponent, app: app, editing: editing, vault: served)
                    } else if ext == "base", let vault {
                        // A Base's views and a canvas, drawn as in Obsidian (Study.baseHTML, canvasHTML).
                        page = Study.filePage(Study.baseHTML(try String(contentsOf: file, encoding: .utf8), vault: vault, items: items, address: Study.vaultAddress, selfPath: path),
                                              type: "bases", look: look, dark: dark, app: app, vault: served)
                    } else if ext == "canvas", let vault, let path {
                        page = Study.filePage(Study.canvasHTML(try String(contentsOf: file, encoding: .utf8), canvasPath: path, height: "100%", vault: vault, items: items,
                                                               address: Study.vaultAddress, standalone: true), type: "canvas", look: look, dark: dark, app: app, vault: served)
                    } else if Study.isPicture(file.path), let path {
                        page = Study.notePage("![[\(path)]]", look: plain, dark: dark, app: app, vault: served)
                    } else {
                        page = Study.notePage("> [!note] \(file.lastPathComponent)\n> " + L("Sage can't show this kind of file here: open it in Obsidian, or in its own app from Finder."),
                                              look: plain, dark: dark, app: app, vault: served)
                    }
                    if inVault, let vault { page = Study.withVault(page, vault: vault, items: items, from: path, address: Study.vaultAddress) }
                    return page
                } catch {
                    // Couldn't be read or drawn: said in the page, never a pop-up and never the page before it.
                    return Study.notePage("> [!warning] " + L("Sage couldn't show %@", file.lastPathComponent) + "\n> \(error.localizedDescription)", look: plain, dark: dark, app: app, vault: served)
                }
            }.value
            guard shownKey == wanted else { return }
            isNote = note && ext == "md"
            blockOpen = false; reloadWaiting = false
            Self.count += 1
            let name = "page-\(Self.count).html"
            if let old = page { SageScheme.shared.pages[old] = nil }
            page = name
            SageScheme.shared.pages[name] = Data(html.utf8)
            problem = nil
            load(URL(string: Study.pagesBase + name)!)
        }
    }

    private func load(_ url: URL) {
        expected = url
        current = web.load(URLRequest(url: url))
    }

    /// The load under way: a failure of an earlier one (cut off by this one) isn't this page's.
    private var current: WKNavigation?

    /// A closed tab's page let go: what's unsaved is saved first, then its page goes.
    func release() async {
        await flush()
        if let page { SageScheme.shared.pages[page] = nil }
        page = nil
        web.stopLoading()
    }

    // MARK: Navigation: only the page Sage loads; a link you press is followed by Sage, never in the page.

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "about" || (url == expected && action.navigationType != .linkActivated) { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        switch action.navigationType {
        case .linkActivated:
            // Cmd or the middle button: a new tab, as in Obsidian.
            let newTab = action.modifierFlags.contains(.command) || action.buttonNumber == 2
            if url.scheme == "sage-note" || url.scheme == "http" || url.scheme == "https" { follow(url, newTab) }
        case .backForward: command("back")
        default: break
        }
    }

    /// "Open Link in New Window", or a link the page opens in a window of its own: a new tab.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, ["sage-note", "http", "https"].contains(url.scheme ?? "") { follow(url, true) }
        return nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error, navigation) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error, navigation) }

    private func failed(_ error: Error, _ navigation: WKNavigation?) {
        let error = error as NSError
        // Cut off by a newer load, or a navigation Sage turned away himself (WebKit's 102, "Frame load interrupted"):
        // neither means this page failed (2026-11-09: it showed over notes that had loaded).
        if error.code == NSURLErrorCancelled || (error.domain == "WebKitErrorDomain" && error.code == 102) { return }
        if let navigation, let current, navigation !== current { return }
        // A page that couldn't load says so: the one before it is never left showing as if it were this one.
        problem = L("Sage couldn't show %@ (%@). Open it again from the tree, or in Obsidian.", file?.lastPathComponent ?? "", error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        shownKey = ""
        if let file { show(file, look: look, dark: dark, vault: vault, items: items, path: path) }
    }

    // MARK: What the page says

    private func post(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message), let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.sageReceive && window.sageReceive(\(json))")
    }

    /// The note's blocks drawn again and sent to the page, which puts them in place (where you were stays put).
    private func sendBody(_ text: String? = nil) {
        guard let file else { return }
        let (look, items, path, vault) = (self.look, self.items, self.path, self.vault)
        Task {
            let (html, lines) = await Task.detached { () -> (String, [String]) in
                let note = text ?? ((try? Study.readNote(file).text) ?? "")
                var sizer = Study.noteSizer(note, look: look, title: file.deletingPathExtension().lastPathComponent)
                if let vault, let path { sizer = Study.withVault(sizer, vault: vault, items: items, from: path, address: Study.vaultAddress) }
                return (sizer, note.components(separatedBy: "\n"))
            }.value
            guard file == self.file else { return }
            post(["type": "body", "html": html, "lines": lines])
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "edit": edit(body)
        // A canvas edited in place, a note's text changed on its card, a card's Markdown drawn.
        case "canvas-save": canvasSave(body)
        case "canvas-note": canvasNote(body)
        case "render": render(body)
        case "task": tick((body["line"] as? NSNumber)?.intValue ?? -1)
        case "redraw": sendBody()
        case "mode": setEditing(!editing(look))
        // A card in a base, or a canvas's Open: the same as pressing a link to it.
        case "follow":
            if let href = body["href"] as? String, href.hasPrefix("sage-note:") || href.hasPrefix("https://") || href.hasPrefix("http://"), let url = URL(string: href) ?? URL(string: href.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") {
                follow(url, body["newTab"] as? Bool ?? false)
            }
        // Cmd+W, Ctrl+Tab, Cmd+Shift+T, Cmd+[ and ] pressed in the page: the tabs' own.
        case "key": if let key = body["key"] as? String { command(key) }
        case "preview":
            if let href = body["href"] as? String, let x = (body["x"] as? NSNumber)?.doubleValue, let y = (body["y"] as? NSNumber)?.doubleValue { preview(href, CGPoint(x: x, y: y)) }
        case "preview-end": preview("", nil)
        case "editing":
            blockOpen = body["on"] as? Bool ?? false
            if !blockOpen && reloadWaiting, let file {
                reloadWaiting = false
                shownKey = key(file)
                sendBody()
            }
        default: break
        }
    }

    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    private static func number(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? -2 }

    /// A block you changed, written into the note (while you type, `live`: the page is told where it is now; when you
    /// leave it, redrawn). Only those lines, only if they still read as they did; the note kept first (Study.writeNote).
    private func edit(_ message: [String: Any]) {
        guard isNote, let file else { return }
        let live = message["live"] as? Bool ?? false
        let text = message["text"] as? String ?? ""
        do {
            let was = try Study.readNote(file)
            guard let edited = Study.editLines(was.text, from: Self.number(message["from"]), to: Self.number(message["to"]), original: message["original"] as? String ?? "", text: text) else {
                // The note changed under you (in Obsidian, say): nothing is written over it, and what you typed is kept for you.
                copy(text)
                post(["type": "notice", "text": L("This part of the note changed elsewhere (in Obsidian?), so it wasn't saved. What you typed is on the clipboard.")])
                if !live { sendBody() }
                return
            }
            if edited.text != was.text { try Study.writeNote(file, text: edited.text, was: was, keep: keep) }
            shownKey = key(file)
            if live { post(["type": "placed", "from": edited.from, "to": edited.to, "lines": edited.text.components(separatedBy: "\n")]) } else { sendBody(edited.text) }
        } catch {
            copy(text)
            post(["type": "notice", "text": L("Couldn't save the note (%@). What you typed is on the clipboard.", error.localizedDescription)])
        }
    }

    private var isCanvas: Bool { file?.pathExtension.lowercased() == "canvas" }

    /// The canvas's nodes and arrows as you left them, written only over the version the page was drawn from.
    private func canvasSave(_ message: [String: Any]) {
        guard isCanvas, let file, let nodes = message["nodes"] as? [Any], let edges = message["edges"] as? [Any] else { return }
        do {
            guard let hash = try Study.saveCanvas(file, nodes: nodes, edges: edges, expected: message["base"] as? String ?? "", keep: keep) else {
                post(["type": "notice", "text": L("This canvas changed elsewhere (in Obsidian?), so your last change wasn't saved. It's shown as the file has it now.")])
                shownKey = ""
                show(file, look: look, dark: dark, vault: vault, items: items, path: path)
                return
            }
            shownKey = key(file)
            post(["type": "canvas-saved", "hash": hash])
        } catch { post(["type": "notice", "text": L("Couldn't save the canvas: %@", error.localizedDescription)]) }
    }

    /// A note's text changed on its canvas card: written into the note (only if it still read so), the card redrawn.
    private func canvasNote(_ message: [String: Any]) {
        guard isCanvas, let vault, let path = message["file"] as? String, let id = message["id"] as? String else { return }
        let full = vault.appendingPathComponent(path).standardizedFileURL
        guard full.path.hasPrefix(vault.standardizedFileURL.path + "/") else { return }
        let original = message["original"] as? String ?? "", text = message["text"] as? String ?? ""
        let (items, from) = (self.items, self.path)
        do {
            var saved = try Study.saveNoteBody(full, original: original, text: text, keep: keep)
            if saved == nil {
                copy(text)
                post(["type": "notice", "text": L("That note changed elsewhere (in Obsidian?), so it wasn't saved. What you typed is on the clipboard.")])
                saved = try Study.readNote(full).text
            }
            let note = saved ?? ""
            let name = full.deletingPathExtension().lastPathComponent
            Task {
                let html = await Task.detached { Study.withVault(Study.canvasNoteHTML(name: name, note: note), vault: vault, items: items, from: from, address: Study.vaultAddress) }.value
                post(["type": "canvas-card", "id": id, "html": html, "body": Study.split(note).body])
            }
        } catch { post(["type": "notice", "text": L("Couldn't save the note: %@", error.localizedDescription)]) }
    }

    /// A card's Markdown drawn as the rest of the page is (links, pictures, embeds).
    private func render(_ message: [String: Any]) {
        guard let key = message["key"] as? String else { return }
        let markdown = message["md"] as? String ?? ""
        let (vault, items, from) = (self.vault, self.items, self.path)
        Task {
            let html = await Task.detached { () -> String in
                let drawn = Study.markdown(markdown)
                return vault.map { Study.withVault(drawn, vault: $0, items: items, from: from, address: Study.vaultAddress) } ?? drawn
            }.value
            post(["type": "rendered", "key": key, "html": html])
        }
    }

    /// A task ticked or cleared in the note, as Obsidian does in either view.
    private func tick(_ line: Int) {
        guard isNote, let file else { return }
        do {
            let was = try Study.readNote(file)
            if let ticked = Study.toggleTask(was.text, line: line) {
                try Study.writeNote(file, text: ticked, was: was, keep: keep)
                shownKey = key(file)
                sendBody(ticked)
            } else { sendBody(was.text) }
        } catch { post(["type": "notice", "text": L("Couldn't save the note: %@", error.localizedDescription)]); sendBody() }
    }

    /// What you're still typing, saved before something else is shown.
    func flush() async {
        guard blockOpen else { return }
        blockOpen = false
        guard let json = try? await web.evaluateJavaScript("window.sageFlush ? window.sageFlush() : ''") as? String, !json.isEmpty,
              var edit = Study.json(Data(json.utf8)) else { return }
        edit["live"] = true
        self.edit(edit)
    }
}

/// Each open tab's page, kept so a tab keeps where you were and what you're editing; past six, the one shown least
/// recently is let go (its tab stays, and draws again when shown).
@MainActor final class SageNotePages {
    static let shared = SageNotePages()
    private var pages: [UUID: SageNotePage] = [:]
    private var recent: [UUID] = []

    func page(for tab: UUID, keep: URL) -> SageNotePage {
        let page = pages[tab] ?? SageNotePage(keep: keep)
        pages[tab] = page
        recent.removeAll { $0 == tab }
        recent.insert(tab, at: 0)
        for old in recent.dropFirst(6) { release(old) }
        return page
    }

    func existing(_ tab: UUID) -> SageNotePage? { pages[tab] }

    /// A tab's page let go (the tab closed, or not shown for a while).
    func release(_ tab: UUID) {
        recent.removeAll { $0 == tab }
        guard let page = pages.removeValue(forKey: tab) else { return }
        Task { await page.release() }
    }
}

/// The shown tab's web view in the SwiftUI page (the others are kept, out of the window).
struct SageWebHost: NSViewRepresentable {
    let web: WKWebView

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard web.superview !== view else { return }
        view.subviews.forEach { $0.removeFromSuperview() }
        web.removeFromSuperview()
        web.frame = view.bounds
        web.autoresizingMask = [.width, .height]
        view.addSubview(web)
    }
}

/// A view that takes only the middle button (a tab or row closes or opens in a new tab with it); every other click passes through.
struct MiddleClick: NSViewRepresentable {
    let action: () -> Void
    final class Catcher: NSView {
        var action: () -> Void = {}
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let type = NSApp.currentEvent?.type, type == .otherMouseDown || type == .otherMouseUp else { return nil }
            return super.hitTest(point)
        }
        override func otherMouseUp(with event: NSEvent) { if event.buttonNumber == 2 { action() } }
    }
    func makeNSView(context: Context) -> Catcher { Catcher() }
    func updateNSView(_ view: Catcher, context: Context) { view.action = action }
}

// MARK: The viewer: tabs, the bar, the page

/// The notes stage's right side: the tab row, the bar (back and forward, where it is, what can be done with it) and the
/// open file's page.
struct SageViewer: View {
    @ObservedObject var desk: SageDesk
    @ObservedObject var vault: SageVaultDesk
    @Environment(\.colorScheme) private var scheme
    /// Bumped when a page's editing changes, so the bar redraws.
    @State private var editingShown = false
    private let accent = PixelSage.theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !vault.tabs.isEmpty { tabRow }
            if let tab = vault.tab, FileManager.default.fileExists(atPath: tab.file.path) {
                let page = SageNotePages.shared.page(for: tab.id, keep: vault.editsKept)
                bar(tab.file, page: page)
                SageViewerPage(desk: desk, vault: vault, page: page, tab: tab, dark: vault.look.dark ?? (scheme == .dark))
                    .id(tab.id)
            } else {
                // A tab whose file was moved or deleted says so, and can be closed.
                VStack(spacing: 8) {
                    Image(systemName: "doc.richtext").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text(vault.tab.map { L("“%@” isn't there any more: it was moved or deleted.", Self.title($0.file)) } ?? L("Choose a note on the left to read it."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let tab = vault.tab { Button { vault.closeTab(tab.id) } label: { Label(L("Close this tab"), systemImage: "xmark") }.controlSize(.small) }
                }.frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
            }
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .onAppear { vault.onTabClosed = { SageNotePages.shared.release($0) } }
    }

    static func title(_ file: URL) -> String { file.pathExtension.lowercased() == "md" ? file.deletingPathExtension().lastPathComponent : file.lastPathComponent }

    static func symbol(_ file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "md": return "doc.text"
        case "base": return "tablecells"
        case "canvas": return "square.grid.3x3.square"
        case "pdf": return "doc.richtext"
        default: return Study.isPicture(file.path) ? "photo" : "doc"
        }
    }

    // MARK: Tabs (2026-11-08): more than one note open, as in Obsidian.

    var tabRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(vault.tabs.enumerated()), id: \.element.id) { index, tab in chip(tab, index: index) }
                }
            }
            .onChange(of: vault.tab?.id) { _, id in if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) } } }
        }
    }

    /// A tab: its file's name, a close button (on the open tab and on hover), the open one lit. Click shows it, the middle
    /// button closes it, right-click has the rest, and dragging it onto another tab moves it there.
    func chip(_ tab: SageTab, index: Int) -> some View {
        SageTabChip(vault: vault, tab: tab, index: index, active: tab.id == vault.tab?.id, accent: accent)
            .id(tab.id)
    }

    // MARK: The bar

    func bar(_ file: URL, page: SageNotePage) -> some View {
        let entry = desk.recipes.first { $0.file.standardizedFileURL == file.standardizedFileURL }
        let recipes = desk.topic.kind == .recipes
        return HStack(spacing: 10) {
            // Back and forward in this tab, as in Obsidian's view header (Cmd+[ and Cmd+], the mouse's side buttons).
            HStack(spacing: 6) {
                Button { vault.goBack() } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).disabled(!vault.canGoBack).opacity(vault.canGoBack ? 1 : 0.35).help(L("Back (⌘[)"))
                Button { vault.goForward() } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).disabled(!vault.canGoForward).opacity(vault.canGoForward ? 1 : 0.35).help(L("Forward (⌘])"))
            }
            // Where it is, as Obsidian's title bar shows it: its folders, then its name; each shows where it is in the tree.
            if vault.inVault(file) != nil { SagePathBar(vault: vault, file: file) } else {
                Text(Self.title(file)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let entry {
                Menu {
                    ForEach(desk.topic.statuses, id: \.self) { status in Button(L(SagePage.statusName(status))) { desk.set(status, for: entry) } }
                } label: { Label(entry.status.isEmpty ? L("No status") : L(SagePage.statusName(entry.status)), systemImage: "circle.fill") }
                .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11)).tint(SagePage.statusColor(entry.status))
                Button { desk.send(recipes ? L("Tell me about my recipe “%@”: what's in it, and tips for making it.", entry.title)
                                           : L("Tell me about my note “%@”: the main points, and what to look into next.", entry.title)) } label: { Image(systemName: "bubble.left") }
                    .buttonStyle(.plain).help(L("Ask Sage about it")).disabled(desk.thinking)
                if let source = URL(string: entry.source), source.scheme?.hasPrefix("http") == true {
                    Button { NSWorkspace.shared.open(source) } label: { Image(systemName: Study.videoID(of: entry.source) == nil ? "safari" : "play.rectangle") }
                        .buttonStyle(.plain).help(Study.videoID(of: entry.source) == nil ? L("Open the page") : L("Watch the video"))
                }
            }
            // Editing or reading, as Obsidian's view switch (Cmd+E).
            if file.pathExtension.lowercased() == "md" {
                let editing = page.editing(vault.look)
                Button { page.setEditing(!editing); editingShown.toggle() } label: { Image(systemName: editing ? "pencil" : "book") }
                    .buttonStyle(.plain)
                    .help(editing ? L("Editing: click any part of the note to change it. Read only (⌘E)") : L("Reading. Edit the note (⌘E)"))
                    .id(editingShown)
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([file]) } label: { Image(systemName: "folder") }.buttonStyle(.plain).help(L("Show in Finder"))
            Button { SageExplorer.openInObsidian(file) } label: { Label(L("Open in Obsidian"), systemImage: "arrow.up.forward.app") }.controlSize(.small)
        }
        .foregroundStyle(.secondary)
    }
}

/// A tab in the row (its own view, so hovering one redraws only it).
struct SageTabChip: View {
    @ObservedObject var vault: SageVaultDesk
    let tab: SageTab
    let index: Int
    let active: Bool
    let accent: Color
    @State private var hover = false
    @State private var dropping = false

    var body: some View {
        let name = SageViewer.title(tab.file)
        HStack(spacing: 6) {
            Image(systemName: SageViewer.symbol(tab.file)).font(.system(size: 10)).foregroundStyle(active ? accent : .secondary)
            Text(name).font(.system(size: 12, weight: active ? .medium : .regular)).foregroundStyle(active ? .primary : .secondary).lineLimit(1).frame(maxWidth: 170, alignment: .leading)
            Button { vault.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 8.5, weight: .semibold)).frame(width: 16, height: 16) }
                .buttonStyle(.plain).foregroundStyle(.secondary).opacity(active || hover ? 1 : 0).help(L("Close (⌘W)"))
                .accessibilityLabel(L("Close %@", name))
        }
        .padding(.leading, 10).padding(.trailing, 5).padding(.vertical, 5)
        .background(active ? Color.white.opacity(0.085) : hover ? Color.white.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(dropping ? accent.opacity(0.6) : active ? Color.white.opacity(0.07) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { vault.showTab(tab.id) }
        .overlay(MiddleClick { vault.closeTab(tab.id) })
        .onHover { hover = $0 }
        .help(vault.inVault(tab.file) ?? tab.file.path)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(active ? L("%@ (open tab)", name) : name)
        .accessibilityAddTraits(.isButton)
        .onDrag { NSItemProvider(object: "sage-tab:\(tab.id.uuidString)" as NSString) }
        .onDrop(of: [.plainText], isTargeted: $dropping) { providers in
            providers.first?.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String, text.hasPrefix("sage-tab:"), let id = UUID(uuidString: String(text.dropFirst("sage-tab:".count))) else { return }
                Task { @MainActor in withAnimation(.easeOut(duration: 0.2)) { vault.moveTab(id, to: index) } }
            }
            return true
        }
        .contextMenu {
            let path = vault.inVault(tab.file)
            Button(L("Close")) { vault.closeTab(tab.id) }
            Button(L("Close other tabs")) { vault.closeOtherTabs(tab.id) }.disabled(vault.tabs.count < 2)
            Button(L("Close tabs to the right")) { vault.closeTabsToTheRight(tab.id) }.disabled(index >= vault.tabs.count - 1)
            Button(L("Reopen closed tab")) { vault.reopenClosedTab() }.disabled(!vault.canReopen)
            Divider()
            Button(L("Show in the vault")) { vault.showTab(tab.id); if let path { vault.showInTree(path) } }.disabled(path == nil)
            Button(L("Open in Obsidian")) { SageExplorer.openInObsidian(tab.file) }
            Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([tab.file]) }
            Button(L("Copy path")) { SageExplorer.copy(path ?? tab.file.path) }
        }
    }
}

/// The shown tab's page, with what it couldn't show and a link's preview over it.
struct SageViewerPage: View {
    @ObservedObject var desk: SageDesk
    @ObservedObject var vault: SageVaultDesk
    @ObservedObject var page: SageNotePage
    let tab: SageTab
    let dark: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            SageWebHost(web: page.web)
                .opacity(page.problem == nil ? 1 : 0)
            if let problem = page.problem {
                Text(problem).font(.system(size: 12)).foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let preview = vault.preview, let at = preview.at {
                SageNotePreview(vault: vault)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08)))
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
                    .offset(x: at.x + 12, y: at.y + 18)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06)))
        .onAppear { wire(); draw() }
        .onChange(of: drawKey) { _, _ in draw() }
    }

    /// What, when changed, draws the page again (the page itself skips a redraw that changes nothing).
    var drawKey: String { "\(tab.file.path)|\(vault.version)|\(dark)|\(vault.look.css.count)|\(vault.look.accent)" }

    private func draw() {
        let path = vault.inVault(tab.file)
        page.show(tab.file, look: vault.vault == nil ? desk.look : vault.look, dark: dark, vault: path != nil ? vault.vault : nil, items: vault.items, path: path)
    }

    private func wire() {
        let vault = vault, desk = desk, id = tab.id
        page.follow = { url, newTab in SageViewerPage.follow(url, newTab: newTab, vault: vault, desk: desk) }
        page.command = { command in
            guard vault.tab?.id == id else { return }
            SageViewerPage.run(command, vault: vault)
        }
        page.preview = { href, at in
            guard let at, href.hasPrefix("sage-note:"), vault.vault != nil else { vault.preview = nil; return }
            let name = String(href.dropFirst("sage-note:".count)).removingPercentEncoding ?? ""
            let from = vault.note.flatMap(vault.inVault)
            if let found = Study.resolve(name, in: vault.items, from: from), !found.folder { vault.preview = .init(path: found.path, at: at) }
        }
    }

    private static var lastRun = (command: "", at: Date.distantPast)

    /// A tab shortcut, from the page or the keyboard in the stage.
    static func run(_ command: String, vault: SageVaultDesk) {
        // The page and the stage can both hear one key press (the page's script, the stage's shortcut): it counts once.
        let now = Date()
        if command == lastRun.command && now.timeIntervalSince(lastRun.at) < 0.25 { return }
        lastRun = (command, now)
        switch command {
        case "close": if let tab = vault.tab { vault.closeTab(tab.id) }
        case "next": vault.cycleTab(1)
        case "previous": vault.cycleTab(-1)
        case "reopen": vault.reopenClosedTab()
        case "back": vault.goBack()
        case "forward": vault.goForward()
        case "switcher": vault.switcher = .open
        case "new-note": vault.newNoteHere(nil)
        default: break
        }
    }

    /// A link pressed in the note: a [[wikilink]] opens that file here (found as Obsidian finds it), a web link in the
    /// browser. With `newTab` (Cmd or the middle button, or a card's), in a new tab beside this one.
    static func follow(_ url: URL, newTab: Bool, vault: SageVaultDesk, desk: SageDesk) {
        if url.scheme == "sage-note" {
            let name = String(url.absoluteString.dropFirst("sage-note:".count)).removingPercentEncoding ?? ""
            let from = vault.note.flatMap(vault.inVault)
            if vault.vault != nil, let found = Study.resolve(name, in: vault.items, from: from) {
                if newTab { vault.openInNewTab(path: found.path) } else { vault.show(path: found.path) }
                return
            }
            let bare = (name as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
            if let entry = Study.named([bare], in: desk.recipes, count: 1).first
                ?? desk.recipes.first(where: { $0.file.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(bare) == .orderedSame }) {
                if newTab { vault.openInNewTab(entry.file) } else { vault.show(entry.file) }
            }
        } else if ["http", "https"].contains(url.scheme ?? "") {
            // A YouTube video plays in Sage's own player (2026-11-09: opening the browser for it was "terrible"); a page
            // still opens in your browser.
            if let id = Study.videoID(of: url.absoluteString), Study.isVideoID(id) {
                let title = vault.note.map { $0.deletingPathExtension().lastPathComponent } ?? ""
                desk.play(Study.Video(id: id, title: title, thumbnail: URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")))
                return
            }
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: The notes stage

/// The notes stage: your vault as Obsidian's explorer and reading view show it (2026-11-07 in Creative Assist). Before a
/// vault is chosen, the one Sage found, or another; then the tree and the open file beside it, the line between them
/// dragged to size the tree.
struct SageNotesStage: View {
    @ObservedObject var desk: SageDesk
    @ObservedObject var vault: SageVaultDesk
    @Binding var filter: String
    var height: CGFloat = 720
    @State private var treeWidth: CGFloat?
    @State private var dragStart: CGFloat?

    var body: some View {
        Group {
            if vault.vault == nil { noVault } else {
                HStack(alignment: .top, spacing: 0) {
                    SageExplorer(desk: desk, vault: vault, filter: $filter)
                        .frame(width: width)
                    divider
                    SageViewer(desk: desk, vault: vault)
                }
                .frame(height: height)
                .background(keys)
            }
        }
        .onAppear { vault.reload() }
    }

    private var width: CGFloat { treeWidth ?? vault.treeWidth.map { CGFloat($0) } ?? 250 }

    /// The line between the tree and the note: dragged to size the tree, remembered.
    private var divider: some View {
        Rectangle().fill(Color.clear).frame(width: 12).contentShape(Rectangle())
            .overlay(Rectangle().fill(.white.opacity(0.06)).frame(width: 1))
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { drag in
                    let start = dragStart ?? width
                    dragStart = start
                    treeWidth = min(560, max(180, start + drag.translation.width))
                }
                .onEnded { _ in
                    dragStart = nil
                    if let treeWidth { vault.treeWidth = Double(treeWidth) }
                })
    }

    /// Cmd+W, Ctrl+Tab (and Shift), Cmd+Shift+T, Cmd+[ and ], Cmd+O while the notes are shown (the page sends its own).
    private var keys: some View {
        ZStack {
            Button("") { SageViewerPage.run("close", vault: vault) }.keyboardShortcut("w", modifiers: .command)
            Button("") { SageViewerPage.run("reopen", vault: vault) }.keyboardShortcut("t", modifiers: [.command, .shift])
            Button("") { SageViewerPage.run("next", vault: vault) }.keyboardShortcut(.tab, modifiers: .control)
            Button("") { SageViewerPage.run("previous", vault: vault) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
            Button("") { SageViewerPage.run("back", vault: vault) }.keyboardShortcut("[", modifiers: .command)
            Button("") { SageViewerPage.run("forward", vault: vault) }.keyboardShortcut("]", modifiers: .command)
            Button("") { SageViewerPage.run("switcher", vault: vault) }.keyboardShortcut("o", modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    /// Before a vault is chosen: the one Sage found, or another.
    private var noVault: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("YOUR VAULT")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
            Text(md: L("Choose your **Obsidian vault**. Sage shows it as Obsidian does: your folders and notes, read with your theme, snippets and settings."))
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Text(L("He only reads it here. All he ever writes is a new note in a topic's folder, never over one that's there; what you change in a note or in the tree is yours, and can be undone."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let found = vault.suggested { Text(found.path).font(.system(size: 10.5)).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                if let found = vault.suggested {
                    Button { vault.use(found) } label: { Label(L("Use “%@”", found.lastPathComponent), systemImage: "checkmark.circle") }.buttonStyle(.borderedProminent).tint(PixelSage.theme)
                }
                Button(vault.suggested != nil ? L("Choose another…") : L("Choose your vault…")) { vault.chooseVault() }
            }.padding(.top, 14)
        }
        .padding(12).frame(maxWidth: 640, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
