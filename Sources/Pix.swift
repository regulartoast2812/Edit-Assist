import SwiftUI

/// Pix, the CTA and image helper: a light lavender blob with Bob Ross's big curly perm and a full beard up to his hair, holding a paintbrush upright
/// (a full Bob Ross did not fit with the other blobs, 2026-11-03). Working: he sweeps the brush and dabs of paint appear.
struct PixelPix: View {
    /// The helper's colour, the body's: their page and sidebar button take it.
    static let theme = Color(red: 222 / 255, green: 210 / 255, blue: 250 / 255)
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["...AAaAAAA......", ".AAaAAAAAaAA..P.", "AAAAAAaAAAAAA.R.", "AAaOOOOOOOAaA.R.",
                       "AAOOOOOOOOOAA.F.", "AaBOKOOOKOBAA.H.", ".ABOKOOOKOBA..H.", "..BBOOOOOBB...H.",
                       "..BBBBBBBBBOOOH.", "...BBBBBBB....H.", "....D...D.....H.", "................"]
    static let blink = ["...AAaAAAA......", ".AAaAAAAAaAA..P.", "AAAAAAaAAAAAA.R.", "AAaOOOOOOOAaA.R.",
                        "AAOOOOOOOOOAA.F.", "AaBOOOOOOOBAA.H.", ".ABOKOOOKOBA..H.", "..BBOOOOOBB...H.",
                        "..BBBBBBBBBOOOH.", "...BBBBBBB....H.", "....D...D.....H.", "................"]
    static let working: [[String]] = [
        ["...AAaAAAA......", ".AAaAAAAAaAA..PG", "AAAAAAaAAAAAA.R.", "AAaOOOOOOOAaA.R.",
         "AAOOOOOOOOOAA.F.", "AaBOKOOOKOBAA.H.", ".ABOKOOOKOBA..H.", "..BBOOOOOBB...H.",
         "..BBBBBBBBBOOOH.", "...BBBBBBB....H.", "....D...D.....H.", "................"],
        ["...AAaAAAA......", ".AAaAAAAAaAA...P", "AAAAAAaAAAAAA..R", "AAaOOOOOOOAaA..R",
         "AAOOOOOOOOOAA..F", "AaBOKOOOKOBAA..H", ".ABOKOOOKOBA...H", "..BBOOOOOBB....H",
         "..BBBBBBBBBOOOOH", "...BBBBBBB.....H", "....D...D......H", "................"],
        ["...AAaAAAA......", ".AAaAAAAAaAA..PG", "AAAAAAaAAAAAA.R.", "AAaOOOOOOOAaA.RY",
         "AAOOOOOOOOOAA.F.", "AaBOKOOOKOBAA.H.", ".ABOKOOOKOBA..H.", "..BBOOOOOBB...H.",
         "..BBBBBBBBBOOOH.", "...BBBBBBB....H.", "....D...D.....H.", "................"],
        ["...AAaAAAA......", ".AAaAAAAAaAA.P.G", "AAAAAAaAAAAAARL.", "AAaOOOOOOOAaAR.Y",
         "AAOOOOOOOOOAAF..", "AaBOKOOOKOBAAH..", ".ABOKOOOKOBA.H..", "..BBOOOOOBB..H..",
         "..BBBBBBBBBOOH..", "...BBBBBBB...H..", "....D...D....H..", "................"],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["A": Color(red: 150 / 255, green: 95 / 255, blue: 55 / 255), "a": Color(red: 115 / 255, green: 70 / 255, blue: 40 / 255),
                                "O": Color(red: 222 / 255, green: 210 / 255, blue: 250 / 255), "K": Color(red: 30 / 255, green: 25 / 255, blue: 25 / 255),
                                "B": Color(red: 120 / 255, green: 75 / 255, blue: 45 / 255), "D": Color(red: 190 / 255, green: 175 / 255, blue: 232 / 255),
                                "P": Color(red: 90 / 255, green: 175 / 255, blue: 110 / 255), "R": Color(red: 45 / 255, green: 40 / 255, blue: 40 / 255),
                                "F": Color(red: 170 / 255, green: 170 / 255, blue: 175 / 255), "H": Color(red: 180 / 255, green: 130 / 255, blue: 70 / 255),
                                "G": Color(red: 90 / 255, green: 175 / 255, blue: 110 / 255), "Y": Color(red: 1, green: 214 / 255, blue: 80 / 255),
                                "L": Color(red: 110 / 255, green: 170 / 255, blue: 235 / 255)],
                       pixel: pixel, busyUntil: busyUntil, previewOnHover: previewOnHover)
            .accessibilityLabel("Pix")
    }
}

/// Pix in the sidebar, at work while he makes a job or answers you.
struct PixIcon: View {
    @ObservedObject var desk: PixDesk
    var body: some View { PixelPix(pixel: 1.25, busyUntil: desk.working != nil || desk.thinking ? .distantFuture : nil) }
}

/// Pix's page (2026-11-04): his jobs from Don's brief (only the CTA queued by itself), what he made, and a chat where
/// you ask for more; the jobs he proposes there are queued only when you press them. The CTA is an SVG that opens
/// editable in Illustrator, as your CTA files are; schematics and pictures come from GPT Image on your OpenAI key.
struct PixPage: View {
    @ObservedObject var desk: PixDesk
    @ObservedObject var don: DonReader
    let project: Project
    @State private var draft = ""
    @State private var attached: [URL] = []
    @State private var keyDraft = ""
    @State private var history = false
    @State private var width: CGFloat = 1400
    private let accent = PixelPix.theme

    var body: some View {
        ThinScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PixelPix(pixel: 4, busyUntil: desk.working != nil || desk.thinking ? .distantFuture : nil, previewOnHover: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(md: L("Your CTA and image helper")).font(.system(size: 13, weight: .semibold))
                    Bullets(["Takes his jobs from **Don's brief**: the **CTA** is queued by itself",
                             "Designs the CTA as an **SVG** that opens editable in **Illustrator**",
                             "Makes product **schematics** and pictures with **GPT Image** when you queue them"], size: 11)
                }
            }
            // The chat on the side, as Sage's is (you asked for it, 2026-11-06); narrow windows put it under the jobs.
            if width >= 900 {
                HStack(alignment: .top, spacing: 14) {
                    chatColumn.frame(width: width >= 1300 ? 380 : 330)
                    work.frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 18) { work; chatColumn }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { proxy in Color.clear.onAppear { width = proxy.size.width }.onChange(of: proxy.size.width) { _, new in width = new } })
        }.scrollIndicators(.automatic)
        .onAppear { open(project.openScript.id); desk.checkKey() }
        .onChange(of: project.openScript.id) { _, id in open(id) }
    }

    var work: some View {
        VStack(alignment: .leading, spacing: 18) {
            if don.brief == nil { briefMissing }
            section(L("JOBS"), trailing: project.openScript.name) { jobs }
            section(L("GPT IMAGE")) { openAI }
        }
    }

    /// The chat in a column of its own: this script's chat, its earlier ones in a list (newest first), and New chat.
    var chatColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L("CHAT WITH PIX")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Button { history.toggle() } label: { Image(systemName: "clock.arrow.circlepath") }.buttonStyle(.plain).help(L("Past chats"))
                    .disabled(desk.board.past.isEmpty)
                    .popover(isPresented: $history, arrowEdge: .bottom) { pastChats.padding(10).frame(width: 300) }
                Button { desk.newChat() } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.plain).help(L("New chat"))
                    .disabled(desk.board.chat.isEmpty || desk.thinking)
            }.foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) { chat }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    /// The script's earlier chats: titled by your first message, with how long ago; one pressed opens to carry on.
    var pastChats: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Earlier chats on %@", project.openScript.name)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(desk.board.past) { chat in
                        Button { desk.openChat(chat.id); history = false } label: {
                            HStack(spacing: 6) {
                                Text(chat.title.isEmpty ? L("Pictures only") : chat.title).font(.system(size: 11)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(L(Study.ago(chat.updated))).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(desk.thinking)
                        .contextMenu { Button(L("Delete chat"), role: .destructive) { desk.deleteChat(chat.id) } }
                    }
                }
            }.frame(maxHeight: 380)
        }
    }

    private func open(_ id: UUID) { desk.load(script: id); don.load(script: id); don.load(project: project.id); attached = [] }

    @ViewBuilder var briefMissing: some View {
        HStack(spacing: 10) {
            PixelDon(pixel: 1.25, busyUntil: don.reading != nil ? .distantFuture : nil).frame(width: 22)
            if don.reading != nil {
                Text(md: L("Don is reading the script…")).font(.system(size: 12))
            } else {
                Text(md: L("Don hasn't read this script yet: Pix takes his jobs from Don's brief.")).font(.system(size: 12))
                Button(L("Ask Don to read it")) { don.read(project) }
                    .controlSize(.small).disabled(don.source(project).lines.isEmpty)
            }
            Spacer(minLength: 0)
        }
        .padding(10).background(PixelDon.theme.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        if let failure = don.failure { status(false, failure) }
    }

    // MARK: Jobs

    @ViewBuilder var jobs: some View {
        if desk.board.jobs.isEmpty {
            Text(md: L("No jobs yet. Don's brief queues the CTA; ask Pix below for anything else.")).font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 6) {
                ForEach(desk.board.jobs) { job($0) }
            }
        }
    }

    func job(_ job: PixJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: Self.icon(job.kind)).foregroundStyle(accent).frame(width: 18)
                Text(job.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                state(job)
                if job.state == .done || job.state == .failed {
                    Button(L("Make again")) { desk.again(job) }.controlSize(.small)
                }
                if job.state != .working {
                    Button { pick { desk.add($0, to: job) } } label: { Image(systemName: "photo.badge.plus") }
                        .buttonStyle(.borderless).help(L("Add product pictures"))
                }
                if job.state != .working {
                    Button { desk.remove(job) } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help(L("Remove from the list (what was made stays in Downloads)"))
                }
            }
            if !job.detail.isEmpty, job.kind != .schematic || job.state != .done {
                Text(job.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3)
            }
            if job.state == .needsPictures {
                Text(md: L("Waiting for product pictures: drop them here, press the picture button, or send them in the chat.")).font(.system(size: 11))
                    .foregroundStyle(accent)
            }
            if !job.pictures.isEmpty { thumbs(job.pictures.compactMap(desk.picture), size: 30) }
            if let note = job.note, !note.isEmpty {
                Text(note).font(.system(size: 10)).foregroundStyle(job.state == .failed ? .orange : .secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(job.outputs.reversed(), id: \.self) { output(URL(fileURLWithPath: $0)) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(job.state == .working ? accent.opacity(0.12) : .white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard job.state != .working else { return false }
            files(providers) { desk.add($0, to: job) }
            return true
        }
    }

    @ViewBuilder func state(_ job: PixJob) -> some View {
        switch job.state {
        case .working:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(L(job.kind == .cta ? "Designing…" : "Making…")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        case .queued: tag(L("Queued"), .secondary)
        case .needsPictures: tag(L("Needs pictures"), accent)
        case .done: tag(L("Done"), accent)
        case .failed: tag(L("Failed"), .orange)
        }
    }

    func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.12), in: Capsule())
    }

    /// A made file: its name, and buttons to open it where it is worked on and to find it.
    func output(_ url: URL) -> some View {
        let exists = FileManager.default.fileExists(atPath: url.path)
        return HStack(spacing: 8) {
            Thumb(url: url, size: 40)
            Text(url.lastPathComponent).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(exists ? .primary : .secondary)
            Spacer(minLength: 4)
            if exists {
                if url.pathExtension == "svg" {
                    Button(L("Open in Illustrator")) { Self.openInIllustrator(url) }.controlSize(.small)
                } else {
                    Button(L("Open")) { NSWorkspace.shared.open(url) }.controlSize(.small)
                }
                Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }.controlSize(.small)
            } else {
                Text(L("Moved or deleted")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    static func icon(_ kind: PixJob.Kind) -> String {
        switch kind {
        case .cta: return "rectangle.split.3x1"
        case .schematic: return "cube.transparent"
        case .picture: return "photo"
        }
    }

    static func openInIllustrator(_ url: URL) {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.adobe.illustrator") {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Chat

    @ViewBuilder var chat: some View {
        HStack(spacing: 6) {
            Text(md: L("Ask Pix for a CTA change, a schematic or a picture. He proposes the job; you queue it.")).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Menu {
                Picker(L("Thinks with"), selection: $desk.brain) {
                    ForEach(HelperBrain.providers) { provider in
                        Text(provider == .codex ? "Codex (OpenAI)" : provider.rawValue).tag(provider)
                    }
                }.pickerStyle(.inline)
                if !desk.board.chat.isEmpty {
                    Divider()
                    Button(L("Clear the chat")) { desk.clearChat() }.disabled(desk.thinking)
                }
            } label: {
                Text(L("Thinks with %@", desk.brain == .codex ? "Codex" : desk.brain.rawValue)).font(.system(size: 10))
            }.menuStyle(.borderlessButton).fixedSize()
            .help(L("Don and Pix think with this CLI, signed in on this Mac. Highlight runs keep their own."))
        }
        if desk.brain.executable == nil { status(false, L("%@ CLI is not installed on this Mac.", desk.brain.rawValue)) }
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(desk.board.chat) { message($0) }
                    if desk.thinking {
                        HStack(spacing: 8) {
                            PixelPix(pixel: 1.25, busyUntil: .distantFuture).frame(width: 22)
                            Text(L("Pix is thinking…")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }.id("thinking")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }
            .frame(height: 520)
            .onAppear { reader.scrollTo(desk.board.chat.last?.id) }
            .onChange(of: desk.board.chat.count) { _, _ in withAnimation { reader.scrollTo(desk.board.chat.last?.id, anchor: .bottom) } }
            .onChange(of: desk.thinking) { _, thinking in if thinking { withAnimation { reader.scrollTo("thinking", anchor: .bottom) } } }
        }
        if !attached.isEmpty {
            HStack(spacing: 6) {
                ForEach(attached, id: \.self) { url in
                    ZStack(alignment: .topTrailing) {
                        Thumb(url: url, size: 36)
                        Button { attached.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).offset(x: 5, y: -5)
                    }
                }
            }
        }
        HStack(alignment: .bottom, spacing: 8) {
            Button { pick { attached += $0 } } label: { Image(systemName: "paperclip") }
                .buttonStyle(.borderless).help(L("Attach pictures"))
            TextField(L("Message Pix"), text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1 ... 5)
                .onSubmit(send)
            Button(L("Send"), action: send)
                .disabled(desk.thinking || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attached.isEmpty))
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            files(providers) { attached += $0 }
            return true
        }
    }

    private func send() {
        guard !desk.thinking else { return }
        desk.send(draft, pictures: attached, project: project.name, name: project.openScript.name)
        draft = ""; attached = []
    }

    func message(_ message: PixMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.fromPix { PixelPix(pixel: 1.25).frame(width: 22) } else { Spacer(minLength: 60) }
            VStack(alignment: message.fromPix ? .leading : .trailing, spacing: 6) {
                if !message.text.isEmpty {
                    Text(message.text).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(message.fromPix ? accent.opacity(0.12) : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                }
                if !message.pictures.isEmpty { thumbs(message.pictures.compactMap(desk.picture), size: 48) }
                ForEach(message.proposals) { proposal in
                    let taken = message.taken.contains(proposal.id)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: Self.icon(proposal.kind)).foregroundStyle(accent).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(proposal.title).font(.system(size: 11, weight: .medium))
                            if !proposal.detail.isEmpty { Text(proposal.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(4) }
                            if proposal.kind != .cta { Text(md: L("Made with **GPT Image**: costs OpenAI credit")).font(.system(size: 9)).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 6)
                        if taken { tag(L("Queued"), accent) } else { Button(L("Queue")) { desk.queue(proposal, from: message.id) }.controlSize(.small) }
                    }
                    .padding(8).frame(maxWidth: 420, alignment: .leading)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if message.fromPix { Spacer(minLength: 60) }
        }.id(message.id)
    }

    // MARK: OpenAI

    @ViewBuilder var openAI: some View {
        switch desk.key {
        case .ready:
            status(true, L("Connected to OpenAI · %@", desk.imageModel ?? "GPT Image"))
            Button(L("Remove key"), role: .destructive) { desk.disconnect() }.controlSize(.small)
        case .checking:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Checking with OpenAI…")).font(.system(size: 12)) }
        case .none, .failed:
            if case .failed(let reason) = desk.key {
                status(false, reason)
                Button(L("Try again")) { desk.checkKey() }.controlSize(.small)
            }
            Text(md: L("Schematics and pictures need an **OpenAI API key** (the CTA does not).")).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField(L("OpenAI API key"), text: $keyDraft).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                    .onSubmit(connect)
                Button(L("Connect"), action: connect).disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(L("Get a key")) { NSWorkspace.shared.open(URL(string: "https://platform.openai.com/api-keys")!) }
            }
            Text(md: L("The key is kept in your Mac's **Keychain**, never in your projects.")).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func connect() {
        guard !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        desk.connect(key: keyDraft); keyDraft = ""
    }

    // MARK: Parts

    func thumbs(_ urls: [URL], size: CGFloat) -> some View {
        HStack(spacing: 4) { ForEach(urls, id: \.self) { Thumb(url: $0, size: size) } }
    }

    /// Pictures chosen in an open panel.
    func pick(_ chosen: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = L("Add")
        if panel.runModal() == .OK { chosen(panel.urls) }
    }

    /// Picture files dropped from Finder.
    func files(_ providers: [NSItemProvider], _ dropped: @escaping ([URL]) -> Void) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, NSImage(contentsOf: url) != nil else { return }
                DispatchQueue.main.async { dropped([url]) }
            }
        }
    }

    func section<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(md: title).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                if let trailing { Text(trailing).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    func status(_ good: Bool?, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: good == nil ? "info.circle" : good == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(good == nil ? Color.secondary : good == true ? accent : .orange)
            Text(md: text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A small picture of a file, read once off the main thread; a plain icon when it cannot be drawn.
struct Thumb: View {
    let url: URL
    var size: CGFloat = 40
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else { Image(systemName: "doc").foregroundStyle(.secondary) }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 5))
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
        .task(id: url) {
            let url = url, side = size * 2
            image = await Task.detached { () -> NSImage? in
                guard let data = HelperBrain.jpeg(url, longest: side) else { return nil }
                return NSImage(data: data)
            }.value
        }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
    }
}
