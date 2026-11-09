import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Sage, the research helper: a sage-green blob with a sage leaf on top, round glasses and a notebook. Working: he writes,
/// the lines filling his notebook, and the leaf sways. Basil, the recipe helper, grown into him (you asked for it, 2026-11-06):
/// personal, not Crossian's; he researches your topics on YouTube and the web and keeps notes in your Obsidian vault.
struct PixelSage: View {
    /// The helper's colour, the body's: their page and sidebar button take it.
    static let theme = Color(red: 150 / 255, green: 186 / 255, blue: 134 / 255)
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["......LL........", ".....LL.........", "...GGGGGGGG.....", "..GGGGGGGGGG....",
                       "..GFFFGGFFFG....", "..GFKFFFFKFG....", "..GFFFGGFFFG....", "..GGGGMMGGGGNNN.",
                       "..GGGGGGGGGGNnN.", "..GGGGGGGGGGNnN.", "...GGGGGGGGGNNN.", "....D....D......"]
    static let blink = ["......LL........", ".....LL.........", "...GGGGGGGG.....", "..GGGGGGGGGG....",
                        "..GFFFGGFFFG....", "..GFFFFFFFFG....", "..GFFFGGFFFG....", "..GGGGMMGGGGNNN.",
                        "..GGGGGGGGGGNnN.", "..GGGGGGGGGGNnN.", "...GGGGGGGGGNNN.", "....D....D......"]
    static let working: [[String]] = [
        [".......LL.......", ".....LL.........", "...GGGGGGGG.....", "..GGGGGGGGGG....",
         "..GFFFGGFFFG....", "..GFFFFFFFFG....", "..GFKFGGFKFG....", "..GGGGMMGGGGNNN.",
         "..GGGGGGGGGGNnN.", "..GGGGGGGGGGNNN.", "...GGGGGGGGGNNN.", "....D....D......"],
        ["......LL........", ".....LL.........", "...GGGGGGGG.....", "..GGGGGGGGGG....",
         "..GFFFGGFFFG....", "..GFFFFFFFFG....", "..GFKFGGFKFG....", "..GGGGMMGGGGNNN.",
         "..GGGGGGGGGGNnN.", "..GGGGGGGGGGNnN.", "...GGGGGGGGGNNN.", "....D....D......"],
        [".....LL.........", "......LL........", "...GGGGGGGG.....", "..GGGGGGGGGG....",
         "..GFFFGGFFFG....", "..GFFFFFFFFG....", "..GFKFGGFKFG....", "..GGGGMMGGGGNNN.",
         "..GGGGGGGGGGNnN.", "..GGGGGGGGGGNnN.", "...GGGGGGGGGNnN.", "....D....D......"],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["G": Self.theme, "L": Color(red: 88 / 255, green: 132 / 255, blue: 76 / 255),
                                "F": Color(red: 40 / 255, green: 42 / 255, blue: 46 / 255), "K": Color(red: 235 / 255, green: 240 / 255, blue: 230 / 255),
                                "M": Color(red: 90 / 255, green: 120 / 255, blue: 80 / 255), "N": Color(red: 240 / 255, green: 232 / 255, blue: 210 / 255),
                                "n": Color(red: 140 / 255, green: 130 / 255, blue: 110 / 255), "D": Color(red: 104 / 255, green: 136 / 255, blue: 92 / 255)],
                       pixel: pixel, busyUntil: busyUntil, previewOnHover: previewOnHover)
            .accessibilityLabel("Sage")
    }
}

/// Sage in the sidebar, writing while he searches, reads or writes.
struct SageIcon: View {
    @ObservedObject var desk: SageDesk
    var body: some View { PixelSage(pixel: 1.25, busyUntil: desk.busy ? .distantFuture : nil) }
}

/// Sage's page, one dashboard that works together (you asked for no tabs, 2026-11-06): the topic you research on top, the chat
/// on the left, and beside it two stages: Research (Find on YouTube or a web link, Saved, Write your own) and Notes (the
/// topic's notes, the open one drawn as Obsidian draws it). A source goes from Find or the chat into Saved; a saved one is
/// written into the topic's folder and opens in Notes; a note can be asked about. Narrower windows stack the columns.
struct SagePage: View {
    @ObservedObject var desk: SageDesk
    @State private var draft = ""
    @State private var dropping = false
    @State private var findChat = ""
    @State private var history = false
    @State private var words = ""
    @State private var search = ""
    @State private var filter = ""
    @State private var key = ""
    @State private var own = ""
    @State private var addingKey = false
    @State private var width: CGFloat = 1400
    /// The page's visible height and where the columns start in it: the chat and the notes stage reach down to the window's
    /// bottom edge instead of stopping at a fixed height (2026-11-09: a tall window left empty space under them).
    @State private var visibleHeight: CGFloat = 900
    @State private var columnsTop: CGFloat = 120
    var columnsHeight: CGFloat { max(460, visibleHeight - columnsTop - 14) }
    /// The topic sheet: a new topic, or the open one renamed.
    @State private var topicSheet = false
    @State private var renaming = false
    @State private var topicName = ""
    @State private var topicKind = Study.Topic.Kind.general
    /// The columns as you dragged them (0: as they start), and the width of the one being dragged while its line moves.
    @AppStorage("sageChatWidth") private var chatWidthKept = 0.0
    @AppStorage("sageSavedWidth") private var savedWidthKept = 0.0
    @State private var chatDrag: CGFloat?
    @State private var savedDrag: CGFloat?
    @State private var dragStart: CGFloat?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let accent = PixelSage.theme

    var body: some View {
        ThinScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let failure = desk.failure { status(false, failure) }
                columns.background(GeometryReader { proxy in
                    Color.clear.preference(key: SageColumnsTop.self, value: proxy.frame(in: .named("sage-page")).minY)
                })
            }
            .coordinateSpace(name: "sage-page")
            .onPreferenceChange(SageColumnsTop.self) { top in if abs(top - columnsTop) > 0.5 { columnsTop = top } }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { proxy in Color.clear.onAppear { width = proxy.size.width }.onChange(of: proxy.size.width) { _, new in width = new } })
            // Room under the panels for the docked player, so nothing is stuck under it.
            .padding(.bottom, desk.playing != nil && !desk.playerExpanded ? SagePlayerBox.dockedHeight + 12 : 0)
        }.scrollIndicators(.automatic)
        .background(GeometryReader { proxy in
            Color.clear.onAppear { visibleHeight = proxy.size.height }.onChange(of: proxy.size.height) { _, new in visibleHeight = new }
        })
        .overlay(alignment: .bottomTrailing) { player }
        .onAppear { desk.reload() }
        // Leaving Sage stops the video.
        .onDisappear { desk.closePlayer() }
        .onChange(of: desk.topicID) { _, _ in filter = ""; search = "" }
        .sheet(isPresented: $topicSheet) { topicForm }
    }

    /// The chat, and beside it the stage: research or notes. The line between them is yours to drag (remembered).
    @ViewBuilder var columns: some View {
        if width >= 900 {
            HStack(alignment: .top, spacing: 0) {
                chatColumn.frame(width: chatWidth)
                stage.frame(maxWidth: .infinity).padding(.leading, 14)
                    .overlay(alignment: .leading) { SageColumnLine { moved in drag(moved, from: chatWidth, into: $chatDrag) { chatWidthKept = Double(chatWidth) } } }
            }
        } else {
            VStack(spacing: 14) { chatColumn; stage }
        }
    }

    /// Two stages share the space beside the chat: Research (find and save videos, write your own) and Notes (your
    /// recipes, the one open drawn as Obsidian draws it). Writing a recipe opens it in Notes.
    var stage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker("", selection: $desk.stage) {
                    Label(L("Research"), systemImage: "magnifyingglass").tag("research")
                    Label(L("Notes"), systemImage: "doc.richtext").tag("notes")
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
                Text(desk.stage == "notes" ? (desk.vault.vault.map { L("Your vault “%@”, read as in Obsidian", $0.lastPathComponent) } ?? L("Your notes on “%@”, read as in Obsidian", desk.topic.name)) : L("Find videos and pages, save the good ones, write them up"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
            if desk.stage == "notes" { notesStage } else { researchStage }
        }
    }

    /// Find and Saved side by side once the stage beside the chat has room for both (it grows as you narrow the chat).
    @ViewBuilder var researchStage: some View {
        if stageWidth >= 820 {
            HStack(alignment: .top, spacing: 0) {
                find.frame(maxWidth: .infinity)
                right.frame(width: savedWidth).padding(.leading, 14)
                    .overlay(alignment: .leading) { SageColumnLine { moved in drag(moved.map { -$0 }, from: savedWidth, into: $savedDrag) { savedWidthKept = Double(savedWidth) } } }
            }
        } else {
            VStack(spacing: 14) { find; right }
        }
    }

    // MARK: Columns and the mini player

    var chatWidth: CGFloat {
        let given = chatDrag ?? (chatWidthKept > 0 ? chatWidthKept : width >= 1300 ? 360 : 320)
        return min(max(given, 260), max(260, min(680, width - 14 - 420)))
    }
    /// The stage's width beside the chat (the whole page when they stack).
    var stageWidth: CGFloat { width >= 900 ? width - chatWidth - 14 : width }
    var savedWidth: CGFloat {
        min(max(savedDrag ?? (savedWidthKept > 0 ? savedWidthKept : 290), 220), max(220, min(620, stageWidth - 14 - 300)))
    }

    /// A column's line dragged `moved` points (nil: let go): the column's width follows live, and is kept when let go.
    private func drag(_ moved: CGFloat?, from current: CGFloat, into width: Binding<CGFloat?>, keep: () -> Void) {
        if let moved {
            if dragStart == nil { dragStart = current }
            width.wrappedValue = (dragStart ?? current) + moved
        } else {
            if width.wrappedValue != nil { keep() }
            width.wrappedValue = nil; dragStart = nil
        }
    }

    /// The mini player: docked over the page's bottom-right corner, or expanded over the whole stage beside the chat; above
    /// everything, never inside a scrolling panel.
    @ViewBuilder var player: some View {
        ZStack(alignment: .bottomTrailing) {
            if let video = desk.playing {
                SagePlayerBox(desk: desk, video: video, accent: accent)
                    .padding(.leading, desk.playerExpanded && width >= 900 ? chatWidth + 14 : 0)
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .move(edge: .bottom))))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: desk.playing == nil)
    }

    // MARK: Header

    /// One line: Sage, the topic, its counts (each one filters its notes), the vault folder and the YouTube key.
    var header: some View {
        let topic = desk.topic
        let count = { (status: String) in desk.recipes.filter { $0.status == status }.count }
        return HStack(spacing: 10) {
            PixelSage(pixel: 2.5, busyUntil: desk.busy ? .distantFuture : nil, previewOnHover: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(md: L("Your research helper")).font(.system(size: 13, weight: .semibold))
                Text(L("Personal: nothing to do with your work")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Divider().frame(height: 26).padding(.horizontal, 4)
            topicMenu
            stat(desk.recipes.count, topic.kind == .recipes ? L("recipes") : L("notes"), "", .primary)
            ForEach(topic.statuses, id: \.self) { status in stat(count(status), L(Self.statusPlural(status)), status, Self.statusColor(status)) }
            stat(desk.unwritten.count, L("saved to write"), nil, accent)
            Spacer(minLength: 8)
            vaultChip
            keyChip
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    /// The topic you research: pick another, make a new one, rename or remove this one.
    var topicMenu: some View {
        Menu {
            ForEach(desk.topics) { topic in
                Button { desk.open(topic: topic.id) } label: {
                    if topic.id == desk.topic.id { Label(topic.name, systemImage: "checkmark") } else { Text(topic.name) }
                }
            }
            Divider()
            Button(L("New topic…")) { topicName = ""; topicKind = .general; renaming = false; topicSheet = true }
            Button(L("Rename topic…")) { topicName = desk.topic.name; renaming = true; topicSheet = true }
            Button(L("Remove topic"), role: .destructive) { desk.remove(topic: desk.topic.id) }.disabled(desk.topics.count < 2)
        } label: {
            Label(desk.topic.name, systemImage: desk.topic.kind == .recipes ? "fork.knife" : "books.vertical")
        }
        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 13, weight: .semibold))
        .help(L("The topic you research: each has its own folder in your vault and its own kind of note"))
    }

    var topicForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(renaming ? L("Rename topic") : L("New topic")).font(.system(size: 14, weight: .semibold))
            TextField(L("Topic, e.g. Editing techniques"), text: $topicName).textFieldStyle(.roundedBorder).onSubmit(saveTopic)
            if !renaming {
                Picker(L("Notes"), selection: $topicKind) {
                    Text(L("Research notes")).tag(Study.Topic.Kind.general)
                    Text(L("Recipes")).tag(Study.Topic.Kind.recipes)
                }.pickerStyle(.segmented)
                Text(topicKind == .recipes ? L("Ingredients and steps; tracked as to try, made, favourite.")
                                           : L("Summary, key points, details, quotes and open questions; tracked as to read, read, key."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(L("Cancel")) { topicSheet = false }.keyboardShortcut(.cancelAction)
                Button(renaming ? L("Rename") : L("Create")) { saveTopic() }.keyboardShortcut(.defaultAction)
                    .disabled(topicName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(18).frame(width: 420)
    }

    private func saveTopic() {
        if renaming { desk.rename(topic: desk.topic.id, to: topicName) } else { desk.add(topic: topicName, kind: topicKind) }
        topicSheet = false
    }

    /// A count; pressing it shows those recipes (nil: not a recipe filter).
    func stat(_ value: Int, _ name: String, _ status: String?, _ color: Color) -> some View {
        Button { if let status { filter = filter == status && !status.isEmpty ? "" : status; desk.stage = "notes" } } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)").font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(color)
                Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(status != nil && filter == status && !(status ?? "").isEmpty ? accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).disabled(status == nil)
    }

    @ViewBuilder var vaultChip: some View {
        if let folder = desk.folder {
            Menu {
                Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                Button(L("Change…")) { _ = desk.chooseFolder() }
            } label: { Label(folder.lastPathComponent, systemImage: "books.vertical") }
            .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11)).help(folder.path)
        } else {
            Button { _ = desk.chooseFolder() } label: { Label(L("Choose vault folder"), systemImage: "books.vertical") }.controlSize(.small)
                .help(L("Choose the folder in your vault for this topic. Sage reads the notes in it and writes new ones there; he never writes anywhere else."))
        }
    }

    @ViewBuilder var keyChip: some View {
        if desk.hasKey {
            Menu {
                Button(L("Forget key"), role: .destructive) { desk.forgetKey() }
            } label: { Label(L("YouTube"), systemImage: "checkmark.circle.fill") }
            .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11)).tint(accent)
        } else {
            Button { addingKey = true } label: { Label(L("Add YouTube key"), systemImage: "key") }.controlSize(.small)
                .popover(isPresented: $addingKey, arrowEdge: .bottom) { keyForm.padding(14).frame(width: 420) }
        }
    }

    var keyForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Bullets(["Open **console.cloud.google.com**, make a project and turn on **YouTube Data API v3**",
                     "Under **Credentials**, create an **API key** and paste it here",
                     "It's free: about **100 searches a day**. Sage keeps it in your Mac's **Keychain**"], numbered: true, size: 11)
            HStack(spacing: 8) {
                SecureField(L("API key"), text: $key).textFieldStyle(.roundedBorder)
                Button(L("Save key")) { desk.save(key: key) }.disabled(key.isEmpty || desk.checkingKey)
                if desk.checkingKey { ProgressView().controlSize(.small) }
            }
        }
        .onChange(of: desk.hasKey) { _, has in if has { addingKey = false; key = "" } }
    }

    // MARK: Chat (left)

    var chatColumn: some View {
        panel(L("CHAT"), trailing: {
            HStack(spacing: 6) {
                SageModelMenu(desk: desk)
                Button { history.toggle() } label: { Image(systemName: "clock.arrow.circlepath") }.buttonStyle(.plain).help(L("Past chats"))
                    .popover(isPresented: $history, arrowEdge: .bottom) { historyList.padding(10).frame(width: 300) }
                Button { desk.newChat() } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.plain).help(L("New chat")).disabled(desk.current == nil)
            }.foregroundStyle(.secondary)
        }) {
            Text(desk.conversations.first { $0.id == desk.current }.map { $0.title.isEmpty ? L("New chat") : $0.title } ?? L("New chat"))
                .font(.system(size: 12, weight: .semibold)).lineLimit(1)
            conversation
        }
    }

    /// Past conversations, newest first, as Claude Code lists its sessions: titled by your first message, with how long ago.
    var historyList: some View {
        let shown = Study.find(findChat, in: desk.conversations)
        return VStack(alignment: .leading, spacing: 8) {
            TextField(L("Search chats"), text: $findChat).textFieldStyle(.roundedBorder).controlSize(.small)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(shown) { conversation in
                        let open = conversation.id == desk.current
                        Button { desk.current = conversation.id; history = false } label: {
                            HStack(spacing: 6) {
                                Text(conversation.title.isEmpty ? L("New chat") : conversation.title)
                                    .font(.system(size: 11, weight: open ? .semibold : .regular)).lineLimit(1)
                                Spacer(minLength: 4)
                                if desk.thinkingIn == conversation.id { ProgressView().controlSize(.mini) }
                                Text(L(Study.ago(conversation.updated))).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(open ? accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(L("Delete chat"), role: .destructive) { desk.delete(conversation.id) }.disabled(desk.thinkingIn == conversation.id)
                        }
                    }
                }
            }.frame(maxHeight: 380)
            if desk.conversations.isEmpty {
                Text(L("Your chats with Sage are kept here.")).font(.system(size: 10)).foregroundStyle(.secondary)
            } else if shown.isEmpty {
                Text(L("No chat has these words.")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder var conversation: some View {
        if HelperBrain.provider.executable == nil { status(false, L("%@ CLI is not installed on this Mac.", HelperBrain.provider.rawValue)) }
        let answering = desk.thinkingIn != nil && desk.thinkingIn == desk.current
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if desk.chat.isEmpty {
                        Text(md: L("Ask Sage about “%@”: a question, what to watch, or what's in your notes. He searches YouTube and your whole vault when he needs to, and when you ask he connects your vault, sets up topics and writes, adds to, marks, moves or renames notes (each with Undo).", desk.topic.name))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                        Text(md: L("As an agent he works in your vault with real tools, as Vault Agent does. On the open note: **/process**, **/summarize**, **/review**, **/categorize**, **/links**, **/rename**, **/fetch**, **/transcribe**; **/memory** opens his memories. Words after a command are added to it."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(desk.chat) { message($0) }
                    if answering && desk.agentMessage == nil {
                        HStack(spacing: 8) {
                            PixelSage(pixel: 1.25, busyUntil: .distantFuture).frame(width: 22)
                            Text(L("Sage is thinking…")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }.id("thinking")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }
            // The chat panel fills the columns' height: its title rows, the box and the padding take about 118 pt.
            .frame(height: max(300, columnsHeight - 118))
            .onAppear { reader.scrollTo(desk.chat.last?.id, anchor: .bottom) }
            .onChange(of: desk.current) { _, _ in reader.scrollTo(desk.chat.last?.id, anchor: .bottom) }
            .onChange(of: desk.chat.count) { _, _ in withAnimation { reader.scrollTo(desk.chat.last?.id, anchor: .bottom) } }
            .onChange(of: answering) { _, answering in if answering { withAnimation { reader.scrollTo("thinking", anchor: .bottom) } } }
            // A run's reply and steps stream in: the chat follows them.
            .onChange(of: (desk.chat.last?.text.count ?? 0) + (desk.chat.last?.steps?.count ?? 0)) { _, _ in
                if desk.agentMessage != nil { reader.scrollTo(desk.chat.last?.id, anchor: .bottom) }
            }
        }
        HStack(alignment: .bottom, spacing: 8) {
            TextField(L("Message Sage"), text: $draft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1 ... 5).onSubmit(send)
            if desk.agentRun != nil {
                Button { desk.stopAgent() } label: { Label(L("Stop"), systemImage: "stop.fill") }.help(L("Stops the agent and the commands it started"))
            } else {
                Button(L("Send"), action: send).disabled(desk.thinking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func send() {
        guard !desk.thinking else { return }
        desk.send(draft); draft = ""
    }

    func message(_ message: Study.Message) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.fromSage { PixelSage(pixel: 1.25).frame(width: 22) } else { Spacer(minLength: 40) }
            VStack(alignment: message.fromSage ? .leading : .trailing, spacing: 8) {
                if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Group {
                        // His replies drawn as Markdown, as Vault Agent's panel draws them; yours as you typed them.
                        if message.fromSage { SageMarkdown(text: message.text) { desk.openLink($0) } } else {
                            Text(message.text).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(message.fromSage ? accent.opacity(0.12) : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                }
                if message.ask != nil { SageModelQuestion(desk: desk, message: message, accent: accent) }
                if let run = message.run { SageRunCard(desk: desk, message: message, run: run, accent: accent) }
                if !message.notes.isEmpty {
                    HStack(spacing: 6) {
                        Text(L("Read:")).font(.system(size: 10)).foregroundStyle(.secondary)
                        ForEach(message.notes, id: \.self) { path in
                            let file = URL(fileURLWithPath: path)
                            Button { desk.show(file) } label: { Label(file.deletingPathExtension().lastPathComponent, systemImage: "doc.text") }
                                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(accent).help(L("Read it in Notes"))
                        }
                    }
                }
                if let done = message.done, !done.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(done.enumerated()), id: \.offset) { _, line in
                            Label(line, systemImage: line.hasPrefix(L("Couldn't")) ? "exclamationmark.circle" : "checkmark.circle")
                                .font(.system(size: 10)).foregroundStyle(line.hasPrefix(L("Couldn't")) ? Color.orange : accent)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if desk.undos[message.id] != nil {
                            Button(L("Undo")) { desk.undo(message.id) }.buttonStyle(.link).font(.system(size: 10))
                                .help(L("Puts back what he did here, the last step first; anything changed since is left as it is"))
                        }
                    }
                }
                if !message.videos.isEmpty {
                    VStack(spacing: 6) { ForEach(message.videos) { row($0) } }
                }
            }
            if message.fromSage { Spacer(minLength: 0) }
        }.id(message.id)
    }

    // MARK: Find and your recipes (middle)

    var find: some View {
        let recipes = desk.topic.kind == .recipes
        let link = Study.link(words)
        return panel(L("FIND"), trailing: { EmptyView() }) {
            HStack(spacing: 8) {
                TextField(recipes ? L("A dish or an ingredient, or a recipe page's link") : L("What to learn about, or a web page's link"), text: $words)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if let link { desk.save(id: link.absoluteString); words = "" } else { desk.search(words) } }
                if let link {
                    Button { desk.save(id: link.absoluteString); words = "" } label: { Label(Study.videoID(of: link.absoluteString) == nil ? L("Save page") : L("Save video"), systemImage: "bookmark") }
                        .disabled(desk.adding)
                } else {
                    Button(L("Search")) { desk.search(words) }.disabled(words.isEmpty || desk.searching || desk.picking || !desk.hasKey)
                    Button { desk.pick(words) } label: { Label(L("Pick for me"), systemImage: "sparkles") }
                        .disabled(words.isEmpty || desk.searching || desk.picking || !desk.canPick)
                        .help(L("Sage searches a few angles, judges every video against his rubric and saves only those that clear his bar (none to 5), saying why"))
                }
            }
            if !desk.hasKey && link == nil {
                Text(md: L("Add your **YouTube key** to search YouTube; web page links work without it, and Sage still chats."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                keyForm
            }
            if desk.picking {
                SagePickSteps(steps: desk.pickSteps, accent: accent)
            } else if let outcome = desk.lastPick {
                SagePickOutcome(desk: desk, outcome: outcome, accent: accent) { card($0.video, why: $0.why, score: $0.score) }
            } else if desk.searching || desk.adding {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(desk.adding ? L("Reading the page…") : L("Searching…")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else if !desk.resultsFor.isEmpty {
                Label(desk.resultsBySage ? L("Sage searched “%@” in the chat", desk.resultsFor) : L("Results for “%@”", desk.resultsFor),
                      systemImage: desk.resultsBySage ? "bubble.left" : "magnifyingglass")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if desk.picking || desk.lastPick != nil {
            } else if desk.results.isEmpty {
                Text(L("Search YouTube, let Sage pick, or paste a page's link: drag what's worth keeping into Saved.")).font(.system(size: 11)).foregroundStyle(.secondary)
                if !recipes {
                    Text(L("Sage reads a video from its title, description and the pages it links to. For a talk, paste its transcript (YouTube: ⋯ → Show transcript) into Write your own."))
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 10) {
                    ForEach(Array(desk.results.enumerated()), id: \.element.id) { index, video in card(video).sageEnter("find:\(desk.resultsFor):\(video.id)", index: index) }
                }
            }
        }
    }

    // MARK: Notes stage

    /// Your vault as Obsidian's explorer and reading view show it, the files open in tabs (SageNoteView.swift, 2026-11-09).
    /// The stage's picker row takes about 40 pt of the columns' height; the notes take the rest.
    var notesStage: some View { SageNotesStage(desk: desk, vault: desk.vault, filter: $filter, height: max(420, columnsHeight - 40)) }

    static func statusName(_ status: String) -> String {
        ["to try": "To try", "made": "Made", "favourite": "Favourite", "to read": "To read", "read": "Read", "key": "Key"][status] ?? status
    }
    /// The status as the header counts it ("3 favourites").
    static func statusPlural(_ status: String) -> String { ["favourite": "favourites", "key": "key"][status] ?? status }
    static func statusColor(_ status: String) -> Color {
        ["made": .green, "favourite": .pink, "to try": .yellow, "read": .green, "key": .orange, "to read": .yellow][status] ?? .secondary
    }

    // MARK: Saved and your own (right)

    var right: some View {
        VStack(alignment: .leading, spacing: 14) {
            shelf
            panel(L("WRITE YOUR OWN"), trailing: { EmptyView() }) {
                Text(md: desk.topic.kind == .recipes ? L("Type or paste a recipe as you have it (from memory, a website, a message); Sage tidies it into a note and keeps your amounts.")
                                                     : L("Paste your notes, an article or a video's transcript (YouTube: ⋯ → Show transcript); Sage writes it up as a research note."))
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $own).font(.system(size: 12)).frame(height: 140).scrollContentBackground(.hidden)
                    .padding(6).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                HStack(spacing: 8) {
                    Button(desk.topic.kind == .recipes ? L("Write recipe") : L("Write note")) { desk.write(words: own) }
                        .disabled(own.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || desk.writing.contains("words")).controlSize(.small)
                    if desk.writing.contains("words") { ProgressView().controlSize(.mini); Text(L("Writing…")).font(.system(size: 10)) }
                }
                if let written = desk.written {
                    Button { desk.show(written) } label: { Label(L("Written: %@", written.deletingPathExtension().lastPathComponent), systemImage: "checkmark.circle.fill") }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(accent).lineLimit(1).help(L("Read it in Notes"))
                }
            }
        }
    }

    /// What you saved in this topic to review: videos dropped here (from Find or the chat), web links dragged from your
    /// browser, and Sage's picks. A note is written into the topic's folder only when you press Write (or Write all).
    var shelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("SAVED")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                let waiting = desk.unwritten.filter { !desk.writing.contains($0.id) }.count
                if waiting > 1 {
                    Button(L("Write all (%@)", waiting)) { desk.writeAll() }.controlSize(.small)
                        .help(L("Write a note for everything saved here and not written yet"))
                }
            }
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 20)).foregroundStyle(dropping ? accent : .secondary)
                Text(L("Drag videos or web links here to save them")).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(accent.opacity(dropping ? 0.14 : 0.03), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(dropping ? accent : .secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            ForEach(Array(desk.savedHere.enumerated()), id: \.element.id) { index, item in
                saved(item).padding(4).sageLift(.white.opacity(0.05), corner: 7).padding(.horizontal, -4)
                    .sageEnter("saved:\(item.topic?.uuidString ?? ""):\(item.id)", index: index)
            }
        }
        .padding(12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        // A video's id from Find or the chat, or a link dragged from your browser.
        .onDrop(of: [.url, .plainText], isTargeted: $dropping) { providers in
            for provider in providers {
                if provider.canLoadObject(ofClass: URL.self) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in desk.save(id: url.absoluteString) } } }
                } else {
                    _ = provider.loadObject(ofClass: String.self) { text, _ in if let text { Task { @MainActor in desk.save(id: text) } } }
                }
            }
            return !providers.isEmpty
        }
    }

    func saved(_ item: Study.Saved) -> some View {
        HStack(alignment: .top, spacing: 8) {
            let thumbnail = ZStack {
                if let picture = item.thumbnail {
                    AsyncImage(url: picture) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.05) }
                } else {
                    accent.opacity(0.18).overlay(Image(systemName: item.page != nil ? "safari" : "play.rectangle").font(.system(size: 13)).foregroundStyle(accent))
                }
            }
            .frame(width: 64, height: 36).clipShape(RoundedRectangle(cornerRadius: 4))
            if let video = item.video, Study.isVideoID(video.id) {
                SagePlayable(desk: desk, video: video, glyph: 9, accent: accent) { thumbnail }
            } else {
                thumbnail.onTapGesture { if let link = item.link { NSWorkspace.shared.open(link) } }.help(item.page != nil ? L("Open the page") : L("Watch the video"))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                if !item.origin.isEmpty { Text(item.origin).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1) }
                if !item.why.isEmpty {
                    Label(item.why, systemImage: "sparkles").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3)
                }
                if desk.writing.contains(item.id) {
                    HStack(spacing: 4) { ProgressView().controlSize(.mini); Text(L("Writing…")).font(.system(size: 10)).foregroundStyle(.secondary) }
                } else if !item.written.isEmpty {
                    let file = URL(fileURLWithPath: item.written)
                    Button { desk.show(file) } label: { Label(L("Written: %@", file.deletingPathExtension().lastPathComponent), systemImage: "checkmark.circle.fill") }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(accent).lineLimit(1).help(L("Read it in Notes"))
                } else {
                    if let reason = desk.refused[item.id] {
                        Label(reason, systemImage: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(.orange).lineLimit(3)
                    }
                    Button(desk.topic.kind == .recipes ? L("Write recipe") : L("Write note")) { desk.write(item) }.controlSize(.mini)
                }
            }
            Spacer(minLength: 0)
            Button { desk.remove(item) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.secondary)
                .help(L("Remove from saved")).disabled(desk.writing.contains(item.id))
        }
    }

    /// A video in the chat: small, with Save; dragged into Saved like a card.
    func row(_ video: Study.Video) -> some View {
        HStack(spacing: 8) {
            SagePlayable(desk: desk, video: video, glyph: 10, accent: accent) {
                AsyncImage(url: video.thumbnail) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.05) }
                    .frame(width: 72, height: 40.5).clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                Text([video.channel, video.duration].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            saveButton(video)
        }
        .padding(6).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        .sageLift(.white.opacity(0.08), corner: 7)
        .contentShape(Rectangle())
        .draggable(video.id) {
            Text(video.title).font(.system(size: 11)).lineLimit(1).padding(6).background(accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Save, or where the video already is.
    @ViewBuilder func saveButton(_ video: Study.Video) -> some View {
        if desk.writing.contains(video.id) {
            ProgressView().controlSize(.mini)
        } else if desk.sources.contains(video.url.absoluteString) {
            Label(L("In your vault"), systemImage: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(accent).labelStyle(.iconOnly).help(L("In your vault"))
        } else if desk.savedHere.contains(where: { $0.id == video.id }) {
            Image(systemName: "bookmark.fill").font(.system(size: 11)).foregroundStyle(accent).help(L("Saved"))
        } else {
            Button { desk.save(video) } label: { Image(systemName: "bookmark") }.buttonStyle(.plain).help(L("Save"))
        }
    }

    /// A video found (or picked: with Sage's why and score): its picture plays it here.
    func card(_ video: Study.Video, why: String = "", score: Double? = nil) -> some View {
        let kept = desk.sources.contains(video.url.absoluteString)
        return VStack(alignment: .leading, spacing: 6) {
            SagePlayable(desk: desk, video: video, glyph: 18, accent: accent) {
                AsyncImage(url: video.thumbnail) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.05) }
                    .aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .overlay(alignment: .bottomTrailing) {
                if !video.duration.isEmpty {
                    Text(video.duration).font(.system(size: 9, weight: .semibold).monospacedDigit()).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 3)).padding(5).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if let score {
                    Text("\(Int(score))").font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(.black).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(accent.opacity(0.92), in: RoundedRectangle(cornerRadius: 4)).padding(5).help(L("Sage's score out of 100"))
                }
            }
            Text(video.title).font(.system(size: 12, weight: .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text([video.channel, video.views.map { L("%@ views", $0.formatted(.number.notation(.compactName))) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            if !why.isEmpty {
                Text("✦ " + why).font(.system(size: 10.5)).lineLimit(4).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            HStack(spacing: 8) {
                if desk.writing.contains(video.id) {
                    ProgressView().controlSize(.small); Text(L("Writing…")).font(.system(size: 11))
                } else if kept {
                    Label(L("In your vault"), systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(accent)
                } else if desk.savedHere.contains(where: { $0.id == video.id }) {
                    Label(L("Saved"), systemImage: "bookmark.fill").font(.system(size: 11)).foregroundStyle(accent)
                } else {
                    Button { desk.save(video) } label: { Label(L("Save"), systemImage: "bookmark") }.controlSize(.small)
                }
                Spacer()
                Button { NSWorkspace.shared.open(video.url) } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.plain).help(L("Open on YouTube"))
            }
        }
        .padding(6)
        .sageLift(.white.opacity(0.05))
        .contentShape(Rectangle())
        // Dragged onto the save area by its id.
        .draggable(video.id) {
            Text(video.title).font(.system(size: 11)).lineLimit(1).padding(6).background(accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: Parts

    /// Opens the note in Obsidian (it must be inside a vault Obsidian knows).
    func open(_ file: URL) {
        var parts = URLComponents(); parts.scheme = "obsidian"; parts.host = "open"
        parts.queryItems = [URLQueryItem(name: "path", value: file.path)]
        if let url = parts.url, NSWorkspace.shared.urlForApplication(toOpen: url) != nil { NSWorkspace.shared.open(url) } else { NSWorkspace.shared.open(file) }
    }

    /// A column's card: its title in small capitals, something on the right of it, then its content.
    func panel<Trailing: View, Content: View>(_ title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                trailing()
            }
            content()
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    func status(_ good: Bool?, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: good == nil ? "info.circle" : good == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(good == nil ? Color.secondary : good == true ? accent : .orange)
            Text(md: text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Where the Sage page's columns start in its scrolled content.
struct SageColumnsTop: PreferenceKey {
    static let defaultValue: CGFloat = 120
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
