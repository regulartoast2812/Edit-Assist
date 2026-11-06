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

/// Basil's page: your recipes in the vault (tracked by status), recipe videos found on YouTube and written down, and a
/// recipe from your own words.
struct BasilPage: View {
    @ObservedObject var desk: BasilDesk
    @AppStorage("basilTab") private var tab = "recipes"
    @State private var words = ""
    @State private var search = ""
    @State private var filter = ""
    @State private var key = ""
    @State private var own = ""
    private let accent = PixelBasil.theme

    var body: some View {
        ThinScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    PixelBasil(pixel: 4, busyUntil: desk.busy ? .distantFuture : nil, previewOnHover: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(md: L("Your recipe helper")).font(.system(size: 13, weight: .semibold))
                        Bullets(["Finds **recipes on YouTube** and writes them down for you",
                                 "Keeps them in your **Obsidian vault**, tracked: to try, made, favourite",
                                 "**Personal**: nothing to do with your work"], size: 11)
                    }
                }
                if let folder = desk.folder {
                    Picker("", selection: $tab) {
                        Text(L("Recipes")).tag("recipes")
                        Text(L("YouTube")).tag("youtube")
                        Text(L("Write")).tag("write")
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                    if let failure = desk.failure { status(false, failure) }
                    if let written = desk.written {
                        HStack(spacing: 8) {
                            status(true, L("Written: **%@**", written.deletingPathExtension().lastPathComponent))
                            Button(L("Open in Obsidian")) { open(written) }.controlSize(.small)
                        }
                    }
                    switch tab {
                    case "youtube": youtube
                    case "write": writePage
                    default: recipes(folder)
                    }
                } else {
                    section(L("OBSIDIAN")) {
                        Text(md: L("Choose the folder in your vault where recipes go. Basil reads the notes in it and writes new ones there; he never writes anywhere else."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button(L("Choose your recipes folder…")) { desk.chooseFolder() }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.automatic)
        .onAppear { desk.reload() }
    }

    // MARK: Recipes

    func recipes(_ folder: URL) -> some View {
        let shown = desk.recipes.filter { entry in
            (filter.isEmpty || entry.status == filter)
                && (search.isEmpty || entry.title.localizedCaseInsensitiveContains(search) || entry.tags.contains { $0.localizedCaseInsensitiveContains(search) }
                    || entry.cuisine.localizedCaseInsensitiveContains(search))
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField(L("Search your recipes"), text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Picker("", selection: $filter) {
                    Text(L("All")).tag("")
                    ForEach(Kitchen.statuses, id: \.self) { Text(L(Self.statusName($0))).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                Text(folder.lastPathComponent).font(.system(size: 10)).foregroundStyle(.secondary).help(folder.path)
                Button { NSWorkspace.shared.activateFileViewerSelecting([folder]) } label: { Image(systemName: "folder") }.help(L("Show in Finder"))
                Button(L("Change…")) { desk.chooseFolder() }
            }.controlSize(.small)
            if desk.recipes.isEmpty {
                Text(L("No recipes in this folder yet. Find one on YouTube or write your own.")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(shown) { entry in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(([entry.cuisine] + entry.tags.filter { $0 != "recipe" }.map { "#" + $0 }).filter { !$0.isEmpty }.joined(separator: "  "))
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Menu {
                            ForEach(Kitchen.statuses, id: \.self) { status in Button(L(Self.statusName(status))) { desk.set(status, for: entry) } }
                        } label: {
                            Text(entry.status.isEmpty ? L("No status") : L(Self.statusName(entry.status)))
                        }.fixedSize().controlSize(.small).tint(Self.statusColor(entry.status))
                        if let source = URL(string: entry.source), source.scheme?.hasPrefix("http") == true {
                            Button { NSWorkspace.shared.open(source) } label: { Image(systemName: "play.rectangle") }.buttonStyle(.plain).help(L("Watch the video"))
                        }
                        Button { open(entry.file) } label: { Image(systemName: "arrow.up.forward.app") }.buttonStyle(.plain).help(L("Open in Obsidian"))
                    }.padding(.vertical, 6)
                    Divider().opacity(0.4)
                }
            }
        }
    }

    static func statusName(_ status: String) -> String { ["to try": "To try", "made": "Made", "favourite": "Favourite"][status] ?? status }
    static func statusColor(_ status: String) -> Color { ["made": .green, "favourite": .pink][status] ?? .secondary }

    // MARK: YouTube

    @ViewBuilder var youtube: some View {
        if !desk.hasKey {
            section(L("YOUTUBE KEY")) {
                Bullets(["Open **console.cloud.google.com**, make a project and turn on **YouTube Data API v3**",
                         "Under **Credentials**, create an **API key** and paste it here",
                         "It's free: about **100 searches a day**. Basil keeps it in your Mac's **Keychain**"], numbered: true, size: 11)
                HStack(spacing: 8) {
                    SecureField(L("API key"), text: $key).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    Button(L("Save key")) { desk.save(key: key) }.disabled(key.isEmpty || desk.checkingKey)
                    if desk.checkingKey { ProgressView().controlSize(.small) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField(L("A dish or an ingredient, e.g. chicken adobo"), text: $words).textFieldStyle(.roundedBorder).frame(maxWidth: 420)
                        .onSubmit { desk.search(words) }
                    Button(L("Search")) { desk.search(words) }.disabled(words.isEmpty || desk.searching)
                    if desk.searching { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(L("Forget key"), role: .destructive) { desk.forgetKey() }.controlSize(.small).buttonStyle(.link)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 16) {
                    ForEach(desk.results) { video in card(video) }
                }
            }
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
                } else {
                    Button(L("Write recipe")) { desk.write(video) }.controlSize(.small)
                }
                Spacer()
                Button { NSWorkspace.shared.open(video.url) } label: { Image(systemName: "play.rectangle") }.buttonStyle(.plain).help(L("Watch the video"))
            }
        }
    }

    // MARK: Your own

    var writePage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(md: L("Type or paste a recipe as you have it (from memory, a website, a message); Basil tidies it into a note and keeps your amounts."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $own).font(.system(size: 12)).frame(minHeight: 260).scrollContentBackground(.hidden)
                .padding(8).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 8) {
                Button(L("Write recipe")) { desk.write(words: own) }.disabled(own.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || desk.writing.contains("words"))
                if desk.writing.contains("words") { ProgressView().controlSize(.small); Text(L("Writing…")).font(.system(size: 11)) }
            }
        }
    }

    // MARK: Parts

    /// Opens the note in Obsidian (it must be inside a vault Obsidian knows).
    func open(_ file: URL) {
        var parts = URLComponents(); parts.scheme = "obsidian"; parts.host = "open"
        parts.queryItems = [URLQueryItem(name: "path", value: file.path)]
        if let url = parts.url, NSWorkspace.shared.urlForApplication(toOpen: url) != nil { NSWorkspace.shared.open(url) } else { NSWorkspace.shared.open(file) }
    }

    func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(md: title).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
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
