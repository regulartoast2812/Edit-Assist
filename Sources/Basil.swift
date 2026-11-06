import AppKit
import SwiftUI

/// Basil, the recipe helper: a basil-green blob in a chef's hat with a red neckerchief and a wooden spoon. Working: he
/// stirs. Personal, not Crossian's: he finds recipes on YouTube and keeps them in your Obsidian vault (2026-11-06).
struct PixelBasil: View {
    /// The helper's colour, the body's: their page and sidebar button take it.
    static let theme = Color(red: 120 / 255, green: 196 / 255, blue: 96 / 255)
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["....HHHHH.......", "...HHHHHHH......", "...HHHHHHH......", "....hhhhh.......",
                       "..GGGGGGGGG.....", "..GKGGGGKGG..W..", "..GGGGGGGGG..W..", "..GGGMMMGGG..W..",
                       "..RRRRRRRRR.GWG.", "..GGGGGGGGGGGG..", "...GGGGGGGGG....", "....D....D......"]
    static let blink = ["....HHHHH.......", "...HHHHHHH......", "...HHHHHHH......", "....hhhhh.......",
                        "..GGGGGGGGG.....", "..GGGGGGGGG..W..", "..GGGGGGGGG..W..", "..GGGMMMGGG..W..",
                        "..RRRRRRRRR.GWG.", "..GGGGGGGGGGGG..", "...GGGGGGGGG....", "....D....D......"]
    static let working: [[String]] = [
        ["....HHHHH.......", "...HHHHHHH......", "...HHHHHHH...s..", "....hhhhh.......",
         "..GGGGGGGGG.....", "..GKGGGGKGG.W...", "..GGGGGGGGG.W...", "..GGGMMMGGG..W..",
         "..RRRRRRRRR.GWG.", "..GGGGGGGGGGGG..", "...GGGGGGGGG....", "....D....D......"],
        ["....HHHHH.......", "...HHHHHHH...s..", "...HHHHHHH......", "....hhhhh.......",
         "..GGGGGGGGG.....", "..GKGGGGKGG..W..", "..GGGGGGGGG..W..", "..GGGMMMGGG..W..",
         "..RRRRRRRRR.GWG.", "..GGGGGGGGGGGG..", "...GGGGGGGGG....", "....D....D......"],
        ["....HHHHH....s..", "...HHHHHHH......", "...HHHHHHH......", "....hhhhh.......",
         "..GGGGGGGGG.....", "..GKGGGGKGG...W.", "..GGGGGGGGG...W.", "..GGGMMMGGG..W..",
         "..RRRRRRRRR.GWG.", "..GGGGGGGGGGGG..", "...GGGGGGGGG....", "....D....D......"],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["H": Color(red: 245 / 255, green: 245 / 255, blue: 240 / 255), "h": Color(red: 200 / 255, green: 200 / 255, blue: 195 / 255),
                                "G": Self.theme, "K": Color(red: 25 / 255, green: 40 / 255, blue: 25 / 255),
                                "M": Color(red: 60 / 255, green: 110 / 255, blue: 50 / 255), "R": Color(red: 215 / 255, green: 70 / 255, blue: 60 / 255),
                                "W": Color(red: 190 / 255, green: 140 / 255, blue: 85 / 255), "D": Color(red: 70 / 255, green: 120 / 255, blue: 60 / 255),
                                "s": Color(white: 0.85, opacity: 0.7)],
                       pixel: pixel, busyUntil: busyUntil, previewOnHover: previewOnHover)
            .accessibilityLabel("Basil")
    }
}

/// Basil in the sidebar, stirring while he searches or writes.
struct BasilIcon: View {
    @ObservedObject var desk: BasilDesk
    var body: some View { PixelBasil(pixel: 1.25, busyUntil: desk.busy ? .distantFuture : nil) }
}

/// Basil's page, one dashboard that works together (you asked for no tabs, 2026-11-06): the chat on the left, Find (YouTube,
/// yours or what Basil searched from the chat) and your recipes in the middle, Saved and your own recipe on the right.
/// A video goes from Find or the chat into Saved; a saved one is written into your recipes; a recipe can be asked about.
/// Narrower windows put the right column under the middle one, then the chat on top.
struct BasilPage: View {
    @ObservedObject var desk: BasilDesk
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
    private let accent = PixelBasil.theme

    var body: some View {
        ThinScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let failure = desk.failure { status(false, failure) }
                columns
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { proxy in Color.clear.onAppear { width = proxy.size.width }.onChange(of: proxy.size.width) { _, new in width = new } })
        }.scrollIndicators(.automatic)
        .onAppear { desk.reload() }
    }

    @ViewBuilder var columns: some View {
        if width >= 1180 {
            HStack(alignment: .top, spacing: 14) {
                chatColumn.frame(width: 360)
                middle.frame(maxWidth: .infinity)
                right.frame(width: 290)
            }
        } else if width >= 820 {
            HStack(alignment: .top, spacing: 14) {
                chatColumn.frame(width: 330)
                VStack(spacing: 14) { middle; right }.frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 14) { chatColumn; middle; right }
        }
    }

    // MARK: Header

    /// One line: Basil, your counts (each one filters your recipes), the vault and the YouTube key.
    var header: some View {
        let count = { (status: String) in desk.recipes.filter { $0.status == status }.count }
        return HStack(spacing: 10) {
            PixelBasil(pixel: 2.5, busyUntil: desk.busy ? .distantFuture : nil, previewOnHover: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(md: L("Your recipe helper")).font(.system(size: 13, weight: .semibold))
                Text(L("Personal: nothing to do with your work")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Divider().frame(height: 26).padding(.horizontal, 4)
            stat(desk.recipes.count, L("recipes"), "", .primary)
            stat(count("to try"), L("to try"), "to try", .secondary)
            stat(count("made"), L("made"), "made", .green)
            stat(count("favourite"), L("favourites"), "favourite", .pink)
            stat(desk.unwritten.count, L("saved to write"), nil, accent)
            Spacer(minLength: 8)
            vaultChip
            keyChip
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    /// A count; pressing it shows those recipes (nil: not a recipe filter).
    func stat(_ value: Int, _ name: String, _ status: String?, _ color: Color) -> some View {
        Button { if let status { filter = filter == status && !status.isEmpty ? "" : status } } label: {
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
                .help(L("Choose the folder in your vault where recipes go. Basil reads the notes in it and writes new ones there; he never writes anywhere else."))
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
                     "It's free: about **100 searches a day**. Basil keeps it in your Mac's **Keychain**"], numbered: true, size: 11)
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
        let shown = Kitchen.find(findChat, in: desk.conversations)
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
                                Text(L(Kitchen.ago(conversation.updated))).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
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
                Text(L("Your chats with Basil are kept here.")).font(.system(size: 10)).foregroundStyle(.secondary)
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
                        Text(md: L("Ask Basil for a recipe, a cooking question, or what's in your notes. He searches YouTube and reads your notes when he needs to."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    }
                    ForEach(desk.chat) { message($0) }
                    if answering {
                        HStack(spacing: 8) {
                            PixelBasil(pixel: 1.25, busyUntil: .distantFuture).frame(width: 22)
                            Text(L("Basil is thinking…")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }.id("thinking")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }
            .frame(height: 560)
            .onAppear { reader.scrollTo(desk.chat.last?.id, anchor: .bottom) }
            .onChange(of: desk.current) { _, _ in reader.scrollTo(desk.chat.last?.id, anchor: .bottom) }
            .onChange(of: desk.chat.count) { _, _ in withAnimation { reader.scrollTo(desk.chat.last?.id, anchor: .bottom) } }
            .onChange(of: answering) { _, answering in if answering { withAnimation { reader.scrollTo("thinking", anchor: .bottom) } } }
        }
        HStack(alignment: .bottom, spacing: 8) {
            TextField(L("Message Basil"), text: $draft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1 ... 5).onSubmit(send)
            Button(L("Send"), action: send).disabled(desk.thinking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func send() {
        guard !desk.thinking else { return }
        desk.send(draft); draft = ""
    }

    func message(_ message: Kitchen.Message) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.fromBasil { PixelBasil(pixel: 1.25).frame(width: 22) } else { Spacer(minLength: 40) }
            VStack(alignment: message.fromBasil ? .leading : .trailing, spacing: 8) {
                Text(message.text).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(message.fromBasil ? accent.opacity(0.12) : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                if !message.notes.isEmpty {
                    HStack(spacing: 6) {
                        Text(L("Read:")).font(.system(size: 10)).foregroundStyle(.secondary)
                        ForEach(message.notes, id: \.self) { path in
                            let file = URL(fileURLWithPath: path)
                            Button { open(file) } label: { Label(file.deletingPathExtension().lastPathComponent, systemImage: "doc.text") }
                                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(accent).help(L("Open in Obsidian"))
                        }
                    }
                }
                if !message.videos.isEmpty {
                    VStack(spacing: 6) { ForEach(message.videos) { row($0) } }
                }
            }
            if message.fromBasil { Spacer(minLength: 0) }
        }.id(message.id)
    }

    // MARK: Find and your recipes (middle)

    var middle: some View {
        VStack(alignment: .leading, spacing: 14) {
            find
            recipes
        }
    }

    var find: some View {
        panel(L("FIND RECIPES ON YOUTUBE"), trailing: { EmptyView() }) {
            if !desk.hasKey {
                Text(md: L("Add your **YouTube key** to search; until then Basil still chats, and you can write your own recipes."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                keyForm
            } else {
                HStack(spacing: 8) {
                    TextField(L("A dish or an ingredient, e.g. chicken adobo"), text: $words).textFieldStyle(.roundedBorder)
                        .onSubmit { desk.search(words) }
                    Button(L("Search")) { desk.search(words) }.disabled(words.isEmpty || desk.searching || desk.picking)
                    Button { desk.pick(words) } label: { Label(L("Pick for me"), systemImage: "sparkles") }
                        .disabled(words.isEmpty || desk.searching || desk.picking)
                        .help(L("Basil searches recipes for your words and saves the real recipe videos worth reviewing (up to 5)"))
                }
                if desk.searching || desk.picking {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(desk.picking ? L("Basil is picking…") : L("Searching…")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                } else if !desk.resultsFor.isEmpty {
                    Label(desk.resultsByBasil ? L("Basil searched “%@” in the chat", desk.resultsFor) : L("Results for “%@”", desk.resultsFor),
                          systemImage: desk.resultsByBasil ? "bubble.left" : "magnifyingglass")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if desk.results.isEmpty {
                    Text(L("Search a dish, or let Basil pick: what you find can be dragged into Saved.")).font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 14) {
                        ForEach(desk.results) { video in card(video) }
                    }
                }
            }
        }
    }

    var recipes: some View {
        let shown = desk.recipes.filter { entry in
            (filter.isEmpty || entry.status == filter)
                && (search.isEmpty || entry.title.localizedCaseInsensitiveContains(search) || entry.tags.contains { $0.localizedCaseInsensitiveContains(search) }
                    || entry.cuisine.localizedCaseInsensitiveContains(search))
        }
        return panel(L("YOUR RECIPES"), trailing: {
            if desk.folder != nil {
                Picker("", selection: $filter) {
                    Text(L("All")).tag("")
                    ForEach(Kitchen.statuses, id: \.self) { Text(L(Self.statusName($0))).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
            }
        }) {
            if desk.folder == nil {
                Text(md: L("Choose the folder in your vault where recipes go. Basil reads the notes in it and writes new ones there; he never writes anywhere else."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L("Choose your recipes folder…")) { _ = desk.chooseFolder() }
            } else {
                TextField(L("Search your recipes"), text: $search).textFieldStyle(.roundedBorder).controlSize(.small).frame(maxWidth: 300)
                if desk.recipes.isEmpty {
                    Text(L("No recipes in this folder yet. Find one on YouTube or write your own.")).font(.system(size: 11)).foregroundStyle(.secondary)
                } else if shown.isEmpty {
                    Text(L("No recipe matches.")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    ForEach(shown) { entry in recipeCard(entry) }
                }
            }
        }
    }

    /// A recipe as a card: its video's picture, title, cuisine and status (changed from its menu).
    func recipeCard(_ entry: Kitchen.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let picture = Kitchen.thumbnail(of: entry.source) {
                    AsyncImage(url: picture) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.05) }
                } else {
                    LinearGradient(colors: [accent.opacity(0.35), accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Image(systemName: "fork.knife").font(.system(size: 22)).foregroundStyle(.white.opacity(0.6)))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .topLeading) {
                if !entry.status.isEmpty {
                    Text(L(Self.statusName(entry.status))).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Self.statusColor(entry.status).opacity(0.85), in: Capsule()).foregroundStyle(.black.opacity(0.8)).padding(5)
                }
            }
            .onTapGesture { open(entry.file) }
            Text(entry.title).font(.system(size: 12, weight: .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(([entry.cuisine] + entry.tags.filter { $0 != "recipe" }.prefix(2).map { "#" + $0 }).filter { !$0.isEmpty }.joined(separator: "  "))
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 8) {
                Menu {
                    ForEach(Kitchen.statuses, id: \.self) { status in Button(L(Self.statusName(status))) { desk.set(status, for: entry) } }
                } label: { Text(entry.status.isEmpty ? L("No status") : L(Self.statusName(entry.status))) }
                .menuStyle(.borderlessButton).fixedSize().font(.system(size: 10))
                Spacer()
                Button { desk.send(L("Tell me about my recipe “%@”: what's in it, and tips for making it.", entry.title)) } label: { Image(systemName: "bubble.left") }
                    .buttonStyle(.plain).help(L("Ask Basil about it")).disabled(desk.thinking)
                if let source = URL(string: entry.source), source.scheme?.hasPrefix("http") == true {
                    Button { NSWorkspace.shared.open(source) } label: { Image(systemName: "play.rectangle") }.buttonStyle(.plain).help(L("Watch the video"))
                }
                Button { open(entry.file) } label: { Image(systemName: "arrow.up.forward.app") }.buttonStyle(.plain).help(L("Open in Obsidian"))
            }.foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
    }

    static func statusName(_ status: String) -> String { ["to try": "To try", "made": "Made", "favourite": "Favourite"][status] ?? status }
    static func statusColor(_ status: String) -> Color { ["made": .green, "favourite": .pink, "to try": .yellow][status] ?? .secondary }

    // MARK: Saved and your own (right)

    var right: some View {
        VStack(alignment: .leading, spacing: 14) {
            shelf
            panel(L("WRITE YOUR OWN"), trailing: { EmptyView() }) {
                Text(md: L("Type or paste a recipe as you have it (from memory, a website, a message); Basil tidies it into a note and keeps your amounts."))
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $own).font(.system(size: 12)).frame(height: 140).scrollContentBackground(.hidden)
                    .padding(6).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                HStack(spacing: 8) {
                    Button(L("Write recipe")) { desk.write(words: own) }
                        .disabled(own.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || desk.writing.contains("words")).controlSize(.small)
                    if desk.writing.contains("words") { ProgressView().controlSize(.mini); Text(L("Writing…")).font(.system(size: 10)) }
                }
                if let written = desk.written {
                    Button { open(written) } label: { Label(L("Written: %@", written.deletingPathExtension().lastPathComponent), systemImage: "checkmark.circle.fill") }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(accent).lineLimit(1).help(L("Open in Obsidian"))
                }
            }
        }
    }

    /// Videos saved in the app to review: drop one here (from the results or the chat), and Basil's picks land here too.
    /// A recipe is written into the vault only when you press Write recipe (or Write all).
    var shelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("SAVED")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                let waiting = desk.unwritten.filter { !desk.writing.contains($0.id) }.count
                if waiting > 1 {
                    Button(L("Write all (%@)", waiting)) { desk.writeAll() }.controlSize(.small)
                        .help(L("Write the recipe of every saved video not written yet into your vault"))
                }
            }
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 20)).foregroundStyle(dropping ? accent : .secondary)
                Text(L("Drag videos here to save them")).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(accent.opacity(dropping ? 0.14 : 0.03), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(dropping ? accent : .secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            ForEach(desk.saved) { item in saved(item) }
        }
        .padding(12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        .dropDestination(for: String.self) { ids, _ in
            ids.forEach(desk.save(id:))
            return !ids.isEmpty
        } isTargeted: { dropping = $0 }
    }

    func saved(_ item: Kitchen.Saved) -> some View {
        HStack(alignment: .top, spacing: 8) {
            AsyncImage(url: item.video.thumbnail) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.05) }
                .frame(width: 64, height: 36).clipShape(RoundedRectangle(cornerRadius: 4))
                .onTapGesture { NSWorkspace.shared.open(item.video.url) }.help(L("Watch the video"))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.video.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                if !item.why.isEmpty {
                    Label(item.why, systemImage: "sparkles").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3)
                }
                if desk.writing.contains(item.id) {
                    HStack(spacing: 4) { ProgressView().controlSize(.mini); Text(L("Writing…")).font(.system(size: 10)).foregroundStyle(.secondary) }
                } else if !item.written.isEmpty {
                    let file = URL(fileURLWithPath: item.written)
                    Button { open(file) } label: { Label(L("Written: %@", file.deletingPathExtension().lastPathComponent), systemImage: "checkmark.circle.fill") }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(accent).lineLimit(1).help(L("Open in Obsidian"))
                } else {
                    if let reason = desk.refused[item.id] {
                        Label(reason, systemImage: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(.orange).lineLimit(3)
                    }
                    Button(L("Write recipe")) { desk.write(item.video) }.controlSize(.mini)
                }
            }
            Spacer(minLength: 0)
            Button { desk.remove(item) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.secondary)
                .help(L("Remove from saved")).disabled(desk.writing.contains(item.id))
        }
    }

    /// A video in the chat: small, with Save; dragged into Saved like a card.
    func row(_ video: Kitchen.Video) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: video.thumbnail) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.05) }
                .frame(width: 72, height: 40).clipShape(RoundedRectangle(cornerRadius: 4))
                .onTapGesture { NSWorkspace.shared.open(video.url) }.help(L("Watch the video"))
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                Text([video.channel, video.duration].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            saveButton(video)
        }
        .padding(6).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .draggable(video.id) {
            Text(video.title).font(.system(size: 11)).lineLimit(1).padding(6).background(accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Save, or where the video already is.
    @ViewBuilder func saveButton(_ video: Kitchen.Video) -> some View {
        if desk.writing.contains(video.id) {
            ProgressView().controlSize(.mini)
        } else if desk.sources.contains(video.url.absoluteString) {
            Label(L("In your vault"), systemImage: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(accent).labelStyle(.iconOnly).help(L("In your vault"))
        } else if desk.saved.contains(where: { $0.id == video.id }) {
            Image(systemName: "bookmark.fill").font(.system(size: 11)).foregroundStyle(accent).help(L("Saved"))
        } else {
            Button { desk.save(video) } label: { Image(systemName: "bookmark") }.buttonStyle(.plain).help(L("Save"))
        }
    }

    func card(_ video: Kitchen.Video) -> some View {
        let kept = desk.sources.contains(video.url.absoluteString)
        return VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: video.thumbnail) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.05) }
                .aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(alignment: .bottomTrailing) {
                    if !video.duration.isEmpty {
                        Text(video.duration).font(.system(size: 9, weight: .semibold).monospacedDigit()).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 3)).padding(5)
                    }
                }
                .onTapGesture { NSWorkspace.shared.open(video.url) }
            Text(video.title).font(.system(size: 12, weight: .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text([video.channel, video.views.map { L("%@ views", $0.formatted(.number.notation(.compactName))) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 8) {
                if desk.writing.contains(video.id) {
                    ProgressView().controlSize(.small); Text(L("Writing…")).font(.system(size: 11))
                } else if kept {
                    Label(L("In your vault"), systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(accent)
                } else if desk.saved.contains(where: { $0.id == video.id }) {
                    Label(L("Saved"), systemImage: "bookmark.fill").font(.system(size: 11)).foregroundStyle(accent)
                } else {
                    Button { desk.save(video) } label: { Label(L("Save"), systemImage: "bookmark") }.controlSize(.small)
                }
                Spacer()
                Button { NSWorkspace.shared.open(video.url) } label: { Image(systemName: "play.rectangle") }.buttonStyle(.plain).help(L("Watch the video"))
            }
        }
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
