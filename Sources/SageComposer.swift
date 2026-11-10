import AppKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// Sage's message box (2026-11-10, you asked for one like Claude's that takes media and @ tags as Kino's prompt does):
/// a rounded box in his colour while you write, the text growing a few lines then scrolling, files attached above it
/// (+, dropped on the box or the chat, or pasted), and a row under it: + to attach, / for his commands, his model, and
/// send (Stop while he works). Return sends, Shift+Return starts a line. Typing @ lists the vault's notes and files
/// (Kino's list, `KinoTagPicker`); the one picked shows as a pill and is kept as its [[link]]. What a tag and an
/// attached file are, and what Sage is told about them, is in SageComposerText.swift.

/// What you're writing to Sage: the text (tags as [[links]]), the files attached, and the box's state.
@MainActor final class SageComposerModel: ObservableObject {
    @Published var text = ""
    @Published var files: [URL] = []
    @Published var focused = false
    @Published var height: CGFloat = SagePromptView.minHeight
    /// The vault Sage works in: a note of it dropped or pasted in is tagged (he reads it), not attached.
    var workVault: () -> URL? = { nil }
    weak var editor: NSTextView?

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && files.isEmpty }

    /// Files dropped, pasted or picked: a note of the vault becomes a tag; anything else is attached, once.
    func attach(_ urls: [URL]) {
        let vault = workVault()
        for url in urls where url.isFileURL {
            let url = url.standardizedFileURL
            if let vault, Study.isInside(url, vault), Study.isReadable(url.path) {
                tag(Study.relative(url, to: vault))
            } else if !files.contains(url) {
                files.append(url)
            }
        }
    }

    /// A tag added at the end of what's written.
    func tag(_ path: String) {
        let spaced = text.isEmpty || text.last?.isWhitespace == true
        text += (spaced ? "" : " ") + Study.tagText(path) + " "
        focus()
    }

    /// One of his commands put at the start (in place of one already there).
    func command(_ name: String) {
        let rest = Study.slash(text)?.extra ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = "/\(name) " + rest
        focus()
    }

    func clear() { text = ""; files = [] }

    func focus() {
        guard let editor, let window = editor.window else { return }
        window.makeFirstResponder(editor)
    }

    /// The + button: any files, several at once.
    func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = L("Attach")
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in self?.attach(urls); self?.focus() }
        }
    }

    /// The file URLs in a drop, loaded, then attached.
    func attach(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        for provider in files {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in self.attach([url]) }
            }
        }
        return true
    }
}

/// The box itself.
struct SageComposer: View {
    @ObservedObject var desk: SageDesk
    @ObservedObject var vault: SageVaultDesk
    @ObservedObject var model: SageComposerModel
    var send: () -> Void
    @State private var dropping = false
    private let accent = PixelSage.theme

    var body: some View {
        let lit = model.focused || dropping
        VStack(alignment: .leading, spacing: 0) {
            if !model.files.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.files, id: \.self) { url in
                            SageAttachmentTile(url: url, accent: accent) { model.files.removeAll { $0 == url } }
                        }
                    }.padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2)
                }
            }
            ZStack(alignment: .topLeading) {
                SagePromptView(model: model, choices: { words in Study.tagChoices(words, in: vault.items, recent: vault.settings.recent) },
                               resolve: { link in Study.resolve(link, in: vault.items).flatMap { $0.folder ? nil : $0 } },
                               root: vault.vault, submit: send)
                    .frame(height: model.height)
                if model.text.isEmpty {
                    Text(L("Message Sage")).font(.system(size: 13)).foregroundStyle(.tertiary)
                        .padding(.leading, 9).padding(.top, SagePromptView.inset.height).allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 4).padding(.top, 4)
            controls
        }
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(lit ? accent : Color.secondary.opacity(0.3), lineWidth: lit ? 1.5 : 1))
        .animation(.easeOut(duration: 0.12), value: lit)
        .onDrop(of: [.fileURL], isTargeted: $dropping) { model.attach($0) }
        .onAppear { let desk = desk; model.workVault = { [weak desk] in desk?.workVault } }
    }

    /// + (attach), / (his commands), his model, and send or Stop.
    var controls: some View {
        HStack(spacing: 2) {
            Button { model.pick() } label: { Image(systemName: "plus").font(.system(size: 13, weight: .medium)).frame(width: 26, height: 24) }
                .buttonStyle(.plain).modifier(SageHoverLit()).help(L("Attach files: pictures, videos, PDFs, anything (or drop or paste them here)"))
            Menu {
                ForEach(Study.quickCommands.filter(\.slash), id: \.name) { command in
                    Button { model.command(command.name) } label: { Label("/\(command.name)  ·  \(L(command.label))", systemImage: SageQuickBar.symbol(command.name)) }
                        .help(L(command.description))
                }
            } label: {
                Text("/").font(.system(size: 14, weight: .semibold, design: .rounded)).frame(width: 26, height: 24)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().modifier(SageHoverLit())
            .help(L("Sage's commands on the open note (or a note you tag with @)"))
            SageModelMenu(desk: desk).padding(.leading, 4).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            if desk.agentRun != nil {
                Button { desk.stopAgent() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26).background(accent, in: Circle())
                }
                .buttonStyle(.plain).help(L("Stops Sage and the commands he started")).accessibilityLabel(L("Stop"))
            } else {
                let can = !desk.thinking && !model.isEmpty
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(can ? 1 : 0.6))
                        .frame(width: 26, height: 26).background(accent.opacity(can ? 1 : 0.35), in: Circle())
                }
                .buttonStyle(.plain).disabled(!can).help(L("Send (Return); a new line with Shift+Return")).accessibilityLabel(L("Send"))
            }
        }
        .padding(.horizontal, 6).padding(.bottom, 6).padding(.top, 2)
    }
}

/// A file attached to the message being written: a picture or video as its thumbnail, anything else as a chip; × takes it off.
struct SageAttachmentTile: View {
    let url: URL
    let accent: Color
    var remove: () -> Void

    var body: some View {
        let kind = Study.attachmentKind(url.path)
        Group {
            if kind == .picture || kind == .video {
                KinoThumb(url: url, width: 56, height: 56, corner: 8)
                    .overlay { if kind == .video { Image(systemName: "play.fill").font(.system(size: 13)).foregroundStyle(.white).shadow(radius: 2) } }
            } else {
                SageFileChip(url: url, accent: accent).frame(height: 56)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 18, height: 18).background(Color.black.opacity(0.7), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.3)))
            }
            .buttonStyle(.plain).offset(x: 6, y: -6).help(L("Remove"))
        }
        .padding(.top, 6).padding(.trailing, 6)
        .help(url.path)
        .onTapGesture(count: 2) { SageQuickLook.shared.show([url], at: 0) }
    }
}

/// A file that isn't a picture or video: its kind's icon, its name and type.
struct SageFileChip: View {
    let url: URL
    let accent: Color

    static func symbol(_ kind: Study.AttachmentKind) -> String {
        switch kind {
        case .picture: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .file: return "doc"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: Self.symbol(Study.attachmentKind(url.path))).font(.system(size: 14)).foregroundStyle(accent)
                .frame(width: 30, height: 30).background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(url.pathExtension.uppercased()).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: 190, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The files a message of yours carries: pictures and videos as thumbnails (Quick Look on a click, ‹ › between them),
/// other files as chips (shown in Finder on a click).
struct SageMessageFiles: View {
    let paths: [String]
    let accent: Color

    var body: some View {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        let media = urls.filter { [.picture, .video].contains(Study.attachmentKind($0.path)) }
        let others = urls.filter { ![.picture, .video].contains(Study.attachmentKind($0.path)) }
        VStack(alignment: .trailing, spacing: 6) {
            if !media.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(media.enumerated()), id: \.offset) { index, url in
                        let gone = !FileManager.default.fileExists(atPath: url.path)
                        KinoThumb(url: url, width: media.count == 1 ? 160 : 76, height: media.count == 1 ? 110 : 76, corner: 8)
                            .overlay { if Study.attachmentKind(url.path) == .video { Image(systemName: "play.circle.fill").font(.system(size: 20)).foregroundStyle(.white).shadow(radius: 3) } }
                            .opacity(gone ? 0.4 : 1)
                            .contentShape(Rectangle())
                            .onTapGesture { if !gone { SageQuickLook.shared.show(media, at: index) } }
                            .contextMenu { menu(url) }
                            .help(gone ? L("“%@” isn't there any more: it was moved or deleted.", url.lastPathComponent) : url.lastPathComponent)
                    }
                }
            }
            ForEach(others, id: \.self) { url in
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { SageFileChip(url: url, accent: accent) }
                    .buttonStyle(.plain).contextMenu { menu(url) }.help(L("Show in Finder"))
            }
        }
    }

    @ViewBuilder func menu(_ url: URL) -> some View {
        Button(L("Open")) { NSWorkspace.shared.open(url) }
        Button(L("Quick Look")) { SageQuickLook.shared.show([url], at: 0) }
        Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}

/// Your sent words with each tag a link in Sage's colour that opens its note in Notes.
struct SageSentText: View {
    let text: String
    let accent: Color
    var open: (String) -> Void

    static func attributed(_ text: String, accent: Color) -> AttributedString {
        var result = AttributedString()
        var last = text.startIndex
        for tag in Study.tagLinks(in: text) {
            result += AttributedString(String(text[last ..< tag.range.lowerBound]))
            var pill = AttributedString("\u{2009}" + Study.tagName(tag.link) + "\u{2009}")
            var link = URLComponents()
            link.scheme = "sage-tag"; link.host = "open"; link.queryItems = [URLQueryItem(name: "link", value: tag.link)]
            pill.link = link.url
            pill.foregroundColor = accent
            pill.backgroundColor = accent.opacity(0.16)
            pill.font = .system(size: 12, weight: .semibold)
            result += pill
            last = tag.range.upperBound
        }
        result += AttributedString(String(text[last...]))
        return result
    }

    var body: some View {
        Text(Self.attributed(text, accent: accent)).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "sage-tag" else { return .systemAction }
                if let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "link" })?.value { open(link) }
                return .handled
            })
    }
}

// MARK: The text

/// The message's text: an NSTextView (as Kino's prompt) whose tags are pills (`KinoTagAttachment`, kept as their
/// [[link]]), with Kino's @ list under the caret for the vault's notes and files, and / at the start for his commands.
struct SagePromptView: NSViewRepresentable {
    @ObservedObject var model: SageComposerModel
    /// The notes and files the @ list offers for the words typed after @.
    let choices: (String) -> [Study.VaultItem]
    /// The vault's file a [[link]] names, if any (only those become pills).
    let resolve: (String) -> Study.VaultItem?
    let root: URL?
    var submit: () -> Void

    static let inset = NSSize(width: 4, height: 7)
    static let minHeight: CGFloat = 34
    static let maxHeight: CGFloat = 180

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = OverlayScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let editor = SagePromptTextView()
        editor.isRichText = true
        editor.importsGraphics = false
        editor.usesFontPanel = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.drawsBackground = false
        editor.insertionPointColor = NSColor(PixelSage.theme)
        editor.textContainerInset = Self.inset
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.typingAttributes = Coordinator.plain
        editor.delegate = context.coordinator
        let coordinator = context.coordinator
        editor.files = { [weak coordinator] urls in coordinator?.parent.model.attach(urls) }
        editor.focusChanged = { [weak coordinator] focused in
            DispatchQueue.main.async { if coordinator?.parent.model.focused != focused { coordinator?.parent.model.focused = focused } }
        }
        editor.resized = { [weak coordinator] view in coordinator?.measure(view) }
        editor.textStorage?.setAttributedString(coordinator.rendered(model.text))
        scroll.documentView = editor
        model.editor = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView, let storage = view.textStorage else { return }
        if model.editor !== view { model.editor = view }
        if KinoPromptView.Coordinator.written(storage) != model.text {
            // Changed from outside (sent and cleared, a tag dropped in, a command put first): drawn again, the caret at the end.
            storage.setAttributedString(coordinator.rendered(model.text))
            view.setSelectedRange(NSRange(location: storage.length, length: 0))
            view.typingAttributes = Coordinator.plain
            coordinator.measure(view)
        }
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) { coordinator.picker.hide() }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SagePromptView
        let picker = KinoTagPicker()
        /// Where the @ or / you pressed Escape on is: no list for it again.
        private var dismissed: Int?
        private var busy = false
        static let font = NSFont.systemFont(ofSize: 13)
        static var plain: [NSAttributedString.Key: Any] {
            let lines = NSMutableParagraphStyle()
            lines.lineSpacing = 3
            return [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: lines]
        }
        static var tint: NSColor { NSColor(PixelSage.theme) }
        init(_ parent: SagePromptView) { self.parent = parent }

        /// A tag's pill: the note's name (a file's with its extension), kept as the link written.
        func pill(_ link: String) -> NSAttributedString {
            let name = NSAttributedString(string: Study.tagName(link), attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: Self.tint])
            let made = NSMutableAttributedString(attachment: KinoTagAttachment(written: "[[" + link + "]]", text: name, tint: Self.tint))
            made.addAttributes(Self.plain, range: NSRange(location: 0, length: made.length))
            return made
        }

        /// The text kept, each [[link]] to a file of the vault as its pill.
        func rendered(_ text: String) -> NSAttributedString {
            let result = NSMutableAttributedString()
            var last = text.startIndex
            for tag in Study.tagLinks(in: text) where parent.resolve(tag.link) != nil {
                result.append(NSAttributedString(string: String(text[last ..< tag.range.lowerBound]), attributes: Self.plain))
                result.append(pill(tag.link))
                last = tag.range.upperBound
            }
            result.append(NSAttributedString(string: String(text[last...]), attributes: Self.plain))
            return result
        }

        /// The box's height for its text: one line up to a few, then it scrolls.
        func measure(_ view: NSTextView) {
            guard let layout = view.layoutManager, let container = view.textContainer else { return }
            layout.ensureLayout(for: container)
            let used = ceil(layout.usedRect(for: container).height + view.textContainerInset.height * 2)
            let height = min(max(used, SagePromptView.minHeight), SagePromptView.maxHeight)
            let model = parent.model
            if abs(model.height - height) > 0.5 { DispatchQueue.main.async { model.height = height } }
        }

        func textDidEndEditing(_ notification: Notification) { picker.hide() }
        func textDidChange(_ notification: Notification) {
            guard !busy, let view = notification.object as? NSTextView else { return }
            typedOut(view)
            parent.model.text = KinoPromptView.Coordinator.written(view.textStorage ?? NSAttributedString())
            measure(view)
            suggest(view)
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !busy, let view = notification.object as? NSTextView else { return }
            suggest(view)
        }
        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            if picker.shown {
                switch selector {
                case #selector(NSResponder.moveDown(_:)): picker.move(1); return true
                case #selector(NSResponder.moveUp(_:)): picker.move(-1); return true
                case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                    if let item = picker.chosen { pick(item, in: view) }
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    dismissed = (typing(view, after: "@") ?? typing(view, after: "/"))?.range.location
                    picker.hide()
                    return true
                default: return false
                }
            }
            // Return sends; Shift+Return (SagePromptTextView) and Option+Return start a new line.
            if selector == #selector(NSResponder.insertNewline(_:)), !view.hasMarkedText() {
                parent.submit()
                return true
            }
            return false
        }

        /// The @ (or a / at the start) and what is typed after it, up to the cursor, when the cursor is in one.
        func typing(_ view: NSTextView, after mark: Character) -> (range: NSRange, text: String)? {
            let selection = view.selectedRange()
            guard selection.length == 0 else { return nil }
            let string = view.string as NSString
            var start = selection.location
            // After @: a name or a path (any letters but spaces and brackets); after /: a command's letters.
            let stops = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "@[]\u{FFFC}"))
            func allowed(_ scalar: UnicodeScalar) -> Bool { mark == "/" ? CharacterSet.letters.contains(scalar) : !stops.contains(scalar) }
            while start > 0, let scalar = UnicodeScalar(string.character(at: start - 1)), allowed(scalar), selection.location - start < 60 { start -= 1 }
            guard start > 0, string.character(at: start - 1) == mark.utf16.first! else { return nil }
            let at = start - 1
            let words = string.substring(with: NSRange(location: start, length: selection.location - start))
            if mark == "/" {
                // His commands are read only at the start of the message.
                guard string.substring(to: at).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, words.allSatisfy(\.isLetter) else { return nil }
            } else if at > 0, let before = UnicodeScalar(string.character(at: at - 1)), !CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "(\u{FFFC}")).contains(before) {
                // An @ inside a word (mail@x) starts nothing.
                return nil
            }
            return (NSRange(location: at, length: selection.location - at), words)
        }

        func suggest(_ view: NSTextView) {
            if let query = typing(view, after: "@") {
                guard dismissed != query.range.location else { return }
                let found = parent.choices(query.text)
                show(found.map { item in
                    let kind = Study.attachmentKind(item.path)
                    let icon = [".md": "doc.text", ".canvas": "rectangle.3.group", ".base": "tablecells"][item.ext] ?? SageFileChip.symbol(kind)
                    return KinoTagPicker.Item(id: "@" + item.path, title: item.title, detail: item.parent.isEmpty ? "/" : item.parent, tint: Self.tint,
                                              url: (kind == .picture || kind == .video) ? parent.root?.appendingPathComponent(item.path) : nil, icon: icon)
                }, at: query.range, in: view)
            } else if let query = typing(view, after: "/") {
                guard dismissed != query.range.location else { return }
                let words = query.text.lowercased()
                let found = Study.quickCommands.filter { $0.slash && (words.isEmpty || $0.name.hasPrefix(words) || L($0.label).lowercased().hasPrefix(words)) }
                show(found.map { KinoTagPicker.Item(id: "/" + $0.name, title: L($0.label), detail: "/" + $0.name, tint: Self.tint, icon: SageQuickBar.symbol($0.name)) },
                     at: query.range, in: view)
            } else {
                dismissed = nil
                picker.hide()
            }
        }
        private func show(_ items: [KinoTagPicker.Item], at range: NSRange, in view: NSTextView) {
            guard !items.isEmpty else { picker.hide(); return }
            let caret = view.firstRect(forCharacterRange: NSRange(location: range.location, length: 0), actualRange: nil)
            picker.show(items, under: caret, in: view.window) { [weak self, weak view] item in
                guard let self, let view else { return }
                self.pick(item, in: view)
            }
        }

        func pick(_ item: KinoTagPicker.Item, in view: NSTextView) {
            picker.hide()
            if item.id.hasPrefix("/") {
                guard let query = typing(view, after: "/") else { return }
                replace(query.range, with: NSAttributedString(string: item.id + " ", attributes: Self.plain), in: view)
            } else if let query = typing(view, after: "@") {
                let path = String(item.id.dropFirst())
                let link = String(Study.tagText(path).dropFirst(2).dropLast(2))
                let string = view.string as NSString
                let end = NSMaxRange(query.range)
                let spaced = end < string.length && CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(string.character(at: end)) ?? " ")
                let made = NSMutableAttributedString(attributedString: pill(link))
                if !spaced { made.append(NSAttributedString(string: " ", attributes: Self.plain)) }
                replace(query.range, with: made, in: view, caret: spaced ? 1 : 0)
            }
        }

        private func replace(_ range: NSRange, with made: NSAttributedString, in view: NSTextView, caret extra: Int = 0) {
            guard let storage = view.textStorage, view.shouldChangeText(in: range, replacementString: made.string) else { return }
            busy = true
            storage.replaceCharacters(in: range, with: made)
            view.didChangeText()
            view.setSelectedRange(NSRange(location: range.location + made.length + extra, length: 0))
            busy = false
            view.typingAttributes = Self.plain
            parent.model.text = KinoPromptView.Coordinator.written(storage)
            measure(view)
        }

        /// A [[link]] to a file of the vault typed out whole (or pasted) becomes its pill.
        func typedOut(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let string = view.string
            for tag in Study.tagLinks(in: string).reversed() where parent.resolve(tag.link) != nil {
                let range = NSRange(tag.range, in: string)
                guard view.shouldChangeText(in: range, replacementString: "\u{FFFC}") else { continue }
                let at = view.selectedRange()
                busy = true
                storage.replaceCharacters(in: range, with: pill(tag.link))
                view.didChangeText()
                busy = false
                let shift = range.length - 1
                view.setSelectedRange(NSRange(location: at.location >= NSMaxRange(range) ? at.location - shift : min(at.location, range.location + 1), length: 0))
            }
            view.typingAttributes = Self.plain
        }
    }
}

/// The message's text view: Shift+Return starts a line; copies its pills as their [[links]]; pastes plain text, or files
/// and pictures as attachments; files dropped on it are attached, not written in.
final class SagePromptTextView: NSTextView {
    var files: (([URL]) -> Void)?
    var focusChanged: ((Bool) -> Void)?
    var resized: ((NSTextView) -> Void)?

    override func keyDown(with event: NSEvent) {
        if [36, 76].contains(event.keyCode), event.modifierFlags.contains(.shift), !hasMarkedText() {
            insertNewlineIgnoringFieldEditor(nil)
            return
        }
        super.keyDown(with: event)
    }
    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { focusChanged?(true) }
        return became
    }
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { focusChanged?(false) }
        return resigned
    }
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { resized?(self) }
    }

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return super.copy(sender) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(KinoPromptView.Coordinator.written(storage.attributedSubstring(from: range)), forType: .string)
    }
    override func cut(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        copy(sender)
        delete(sender)
    }

    // Pasting: copied files are attached; a picture on the clipboard (a screenshot, an image copied from a page) is
    // saved as a PNG and attached; text is pasted plain.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { super.readablePasteboardTypes + [.fileURL, .png, .tiff] }
    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            files?(urls)
            return
        }
        let text = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let onlyLink = text.map { !$0.contains("\n") && ($0.hasPrefix("http://") || $0.hasPrefix("https://")) } ?? true
        if let type = board.availableType(from: [.png, .tiff]), onlyLink, let data = board.data(forType: type),
           let png = type == .png ? data : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EditAssist-Sage-pasted", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(Study.freeName(Study.pastedName(Date())) { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) })
            if (try? png.write(to: file)) != nil { files?([file]); return }
        }
        pasteAsPlainText(sender)
    }

    // Dropping: files are attached (a note of the vault tagged); text is written in as usual.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [.fileURL, .string] }
    override func updateDragTypeRegistration() {
        unregisterDraggedTypes()
        registerForDraggedTypes([.fileURL, .string])
    }
    private func dropped(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropped(sender).isEmpty ? super.draggingEntered(sender) : .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dropped(sender).isEmpty ? super.draggingUpdated(sender) : .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { dropped(sender).isEmpty ? super.prepareForDragOperation(sender) : true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = dropped(sender)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        files?(urls)
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if let sender, !dropped(sender).isEmpty { return }
        super.concludeDragOperation(sender)
    }
}

// MARK: Quick Look

/// Pictures and videos from the chat in Quick Look (Space-bar style, ‹ › between a message's). It takes the panel by
/// sitting in the key window's responder chain, after the window, as the panel looks for its controller there.
final class SageQuickLook: NSResponder, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = SageQuickLook()
    private var urls: [URL] = []

    func show(_ urls: [URL], at index: Int) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        if let window = NSApp.keyWindow ?? NSApp.mainWindow, !inChain(of: window) {
            nextResponder = window.nextResponder
            window.nextResponder = self
        }
        panel.updateController()
        if panel.dataSource !== self { panel.dataSource = self; panel.delegate = self }
        panel.reloadData()
        panel.currentPreviewItemIndex = min(max(0, index), urls.count - 1)
        panel.makeKeyAndOrderFront(nil)
    }

    private func inChain(of window: NSWindow) -> Bool {
        var responder: NSResponder? = window.nextResponder
        while let current = responder { if current === self { return true }; responder = current.nextResponder }
        return false
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { !urls.isEmpty }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self; panel.delegate = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { if panel.dataSource === self { panel.dataSource = nil; panel.delegate = nil } }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { urls[index] as NSURL }
}
