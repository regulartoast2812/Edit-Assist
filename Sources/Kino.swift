import AVFoundation
import AVKit
import ImageIO
import QuickLookThumbnailing
import SwiftUI
import WebKit

/// Kino, the AI video helper: an orange blob in a red director's beret, holding a clapperboard. Working: the clapper
/// opens and snaps shut, and sparks of AI fly off it.
struct PixelKino: View {
    /// The helper's colour, the body's: their page and sidebar button take it.
    static let theme = Color(red: 250 / 255, green: 160 / 255, blue: 70 / 255)
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["..RRRRRr........", ".RRRRRRR........", "..OOOOOOO.......", ".OOOOOOOOOO.....",
                       ".OOOOOOOOOO.....", ".OOKOOOOKOOWBWBW", ".OOKOOOOKOOBBBBB", ".OOOOOOOOOOBWWWB",
                       ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.......", "................"]
    static let blink = ["..RRRRRr........", ".RRRRRRR........", "..OOOOOOO.......", ".OOOOOOOOOO.....",
                        ".OOOOOOOOOO.....", ".OOOOOOOOOOWBWBW", ".OOKOOOOKOOBBBBB", ".OOOOOOOOOOBWWWB",
                        ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.......", "................"]
    static let working: [[String]] = [
        ["..RRRRRr....S...", ".RRRRRRR.......W", "..OOOOOOO.....B.", ".OOOOOOOOOO..W..",
         ".OOOOOOOOOO.B...", ".OOKOOOOKOOW....", ".OOKOOOOKOOBBBBB", ".OOOOOOOOOOBWWWB",
         ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.......", "................"],
        ["..RRRRRr....s...", ".RRRRRRR........", "..OOOOOOO.......", ".OOOOOOOOOO...S.",
         ".OOOOOOOOOO.....", ".OOKOOOOKOOWBWBW", ".OOKOOOOKOOBBBBB", ".OOOOOOOOOOBWWWB",
         ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.......", "................"],
        ["..RRRRRr........", ".RRRRRRR.......W", "..OOOOOOO.....B.", ".OOOOOOOOOO.sW..",
         ".OOOOOOOOOO.B...", ".OOOKOOOOKOW....", ".OOOKOOOOKOBBBBB", ".OOOOOOOOOOBWWWB",
         ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D....S..", "................"],
        ["..RRRRRr........", ".RRRRRRR........", "..OOOOOOO...S...", ".OOOOOOOOOO.....",
         ".OOOOOOOOOO.....", ".OOOKOOOOKOWBWBW", ".OOOKOOOOKOBBBBB", ".OOOOOOOOOOBWWWB",
         ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.....s.", "................"],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["O": Color(red: 250 / 255, green: 160 / 255, blue: 70 / 255), "D": Color(red: 205 / 255, green: 131 / 255, blue: 57 / 255),
                                "R": Color(red: 215 / 255, green: 55 / 255, blue: 60 / 255), "r": Color(red: 160 / 255, green: 35 / 255, blue: 45 / 255),
                                "K": Color(red: 25 / 255, green: 25 / 255, blue: 28 / 255), "B": Color(red: 95 / 255, green: 95 / 255, blue: 108 / 255),
                                "W": Color(red: 240 / 255, green: 240 / 255, blue: 240 / 255), "S": Color(red: 1, green: 230 / 255, blue: 120 / 255),
                                "s": Color(red: 150 / 255, green: 220 / 255, blue: 1)],
                       pixel: pixel, busyUntil: busyUntil, previewOnHover: previewOnHover)
            .accessibilityLabel("Kino")
    }
}

/// Kino's page (2026-11-05; the shots as cards since the same day). The media on the left, empty until you drop or add
/// files, in the order you pick. The shots one under another, as the team's generator (KlingDom Forge) shows its jobs, each
/// a card read left to right as it is made: its files in their places, the prompt and settings, its takes. Unlike the
/// Forge, every place the model has room for is shown, each file's role is in colour, and what stops a shot is said on it.
/// Drop files anywhere on a card to put them in it, on a place to give them that role. A role has one colour everywhere: on
/// the file, on its @tag in the prompt and in what is sent; red is for what is wrong, green for ready, Kino's orange for
/// what is chosen. What every shot shares, the accounts and the research open from the top bar.
struct KinoPage: View {
    @ObservedObject var desk: KinoDesk
    let project: Project
    @State private var reading: KinoResearch?
    @State private var hovered: KinoResearch?
    @State private var showingResearch = false
    @State private var showingAccounts = false
    @State private var showingEveryShot = false
    @State private var search = ""
    @State private var folded: Set<String> = []
    /// Files dragged over the shots' list, outside any shot's files: dropped, they make a new shot.
    @State private var newTargeted = false
    private let accent = PixelKino.theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            GeometryReader { page in
                // The outputs beside the shots once there is a shot or a take; narrower in a small window.
                let outputs: CGFloat = desk.shots.isEmpty && desk.takes.isEmpty ? 0 : page.size.width >= 1300 ? 300 : 250
                HStack(alignment: .top, spacing: 14) {
                    KinoMediaBin(desk: desk).frame(width: KinoMediaBin.width)
                    GeometryReader { size in
                        ScrollViewReader { proxy in
                            ThinScrollView {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    if desk.shots.isEmpty { welcome.padding(.bottom, 8) }
                                    ForEach(shown, id: \.self) { code in
                                        KinoShotCard(desk: desk, code: code, width: size.size.width,
                                                     folded: Binding(get: { folded.contains(code) },
                                                                     set: { if $0 { folded.insert(code) } else { folded.remove(code) } }),
                                                     openAccounts: { showingAccounts = true }, openEveryShot: { showingEveryShot = true })
                                            .id(code)
                                    }
                                    if shown.isEmpty && !desk.shots.isEmpty {
                                        Text(L("No shot or file has “%@”", search)).font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 20)
                                    }
                                    KinoNewShot(desk: desk)
                                }
                                .padding(.bottom, 24)
                                // Files dropped anywhere but on a shot's files make a new shot of them.
                                .frame(minHeight: size.size.height, alignment: .top)
                                .contentShape(Rectangle())
                                .kinoDrop($newTargeted) { desk.newShot(with: $0) }
                            }
                            .overlay(alignment: .bottom) {
                                if newTargeted {
                                    Label(L("Drop for a new shot, %@", desk.nextShot), systemImage: "plus")
                                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                                        .padding(.horizontal, 14).frame(height: 32).background(accent, in: Capsule())
                                        .shadow(color: .black.opacity(0.4), radius: 10, y: 3).padding(.bottom, 16)
                                        .allowsHitTesting(false).transition(.opacity)
                                }
                            }
                            .animation(.easeOut(duration: 0.12), value: newTargeted)
                            .onChange(of: newTargeted) { _, inside in desk.dragged(inside) }
                            // A shot made by a drop or by New shot is scrolled to.
                            .onChange(of: desk.shots.count) { old, new in
                                if new > old, let code = desk.selected { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(code, anchor: .top) } }
                            }
                            // A take played from the outputs brings its shot into view, scrolling only as far as it takes.
                            .onChange(of: desk.watching) { _, path in
                                if let code = desk.takes.first(where: { $0.path == path })?.shot, shown.contains(code) {
                                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(code) }
                                }
                            }
                        }
                    }
                    if outputs > 0 { KinoOutputs(desk: desk).frame(width: outputs) }
                }
            }
        }
        .onAppear { desk.open(project: project.id) }
        .onChange(of: project.id) { _, id in search = ""; folded = []; desk.open(project: id) }
        // Files moved or deleted in Finder show when you come back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in desk.refresh() }
        .sheet(item: $reading) { KinoResearchSheet(doc: $0) }
    }

    /// The shots whose code, prompt or files have the words searched for.
    var shown: [String] {
        let words = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !words.isEmpty else { return desk.shots }
        return desk.shots.filter { code in
            code.lowercased().contains(words) || desk.shot(code).prompt.lowercased().contains(words)
                || desk.files(in: code).contains { $0.url.lastPathComponent.lowercased().contains(words) }
        }
    }

    var header: some View {
        let codes = desk.shots
        let takes = codes.map { desk.settings($0).takes }.reduce(0, +)
        return HStack(spacing: 10) {
            PixelKino(pixel: 1.6)
            Text(L("Kino")).font(.system(size: 13, weight: .semibold))
            Text(L("%@ shots · %@ files", codes.count, desk.media.count)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            if codes.count > 1 {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    TextField(L("Find a shot or a file"), text: $search).textFieldStyle(.plain).font(.system(size: 11.5))
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10.5)).foregroundStyle(.tertiary) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).frame(width: 200, height: 26)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
            Button { showingEveryShot.toggle() } label: { Label(L("Every shot"), systemImage: "slider.horizontal.3") }
                .help(L("What every shot's prompt says, and the settings every shot starts from"))
                .popover(isPresented: $showingEveryShot, arrowEdge: .bottom) { KinoEveryShot(desk: desk).padding(18).frame(width: 440) }
            Button { showingResearch.toggle() } label: { Label(L("Research"), systemImage: "books.vertical") }
                .popover(isPresented: $showingResearch, arrowEdge: .bottom) { research.padding(6).frame(width: 340) }
            Button { showingAccounts.toggle() } label: {
                Label(L("Accounts"), systemImage: "key")
                    .overlay(alignment: .topLeading) {
                        if desk.missingKey(codes) || (!desk.hasHiggsfield && !desk.hasKling) {
                            Circle().fill(.red).frame(width: 6, height: 6).offset(x: -2, y: -1)
                        }
                    }
            }
            .help(L("Higgsfield and Kling keys"))
            .popover(isPresented: $showingAccounts, arrowEdge: .bottom) { KinoAccounts(desk: desk).padding(16).frame(width: 300) }
            if !codes.isEmpty {
                Button {} label: { Label(L("Run all · %@ takes", takes), systemImage: "play.fill") }.disabled(true).help(desk.blocker(codes))
            }
        }
    }

    /// What Kino does and how to start, with the research beside it: shown until there is a shot.
    var welcome: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) { start; Spacer(minLength: 0); research.frame(width: 320) }
            VStack(alignment: .leading, spacing: 24) { start; research.frame(maxWidth: 420) }
        }
        .padding(.top, 6)
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 14) {
            PixelKino(pixel: 4, previewOnHover: true)
            Text(L("Start with your media")).font(.system(size: 24, weight: .bold, design: .rounded))
            Text(L("Drop pictures, videos and sounds on the left, or onto New shot below."))
                .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Bullets(["Files named **K1**, **K1.1** and **K1.2** go straight into shot K1, each under its own **@tag**",
                     "Drag a file onto a shot's files to use it there, or onto the space around the shots for a new one; one picture can be in many shots",
                     "Give each file a **role**, write what happens, and Kino shows what he would send"], numbered: true, size: 11.5)
                .frame(maxWidth: 440, alignment: .leading)
        }
    }

    private var research: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(md: L("RESEARCH")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Text(L("As of %@", KinoResearch.asOf.formatted(date: .abbreviated, time: .omitted)))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.bottom, 2)
            ForEach(KinoResearch.allCases) { doc in
                Button { showingResearch = false; reading = doc } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: doc.icon).font(.system(size: 12)).foregroundStyle(accent).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L(doc.title)).font(.system(size: 12, weight: .semibold))
                            Text(L(doc.summary)).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary).padding(.top, 3)
                    }
                    .padding(8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.white.opacity(hovered == doc ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 7))
                .onHover { inside in hovered = inside ? doc : (hovered == doc ? nil : hovered) }
            }
        }
        .padding(8).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// What every shot starts from: the words said in every prompt, the settings, and the shots that have their own.
struct KinoEveryShot: View {
    @ObservedObject var desk: KinoDesk
    private let accent = PixelKino.theme
    var body: some View {
        let own = desk.shots.filter { desk.shot($0).settings != nil }
        let settings = Binding(get: { desk.batch.settings }, set: { desk.setBatchSettings($0) })
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Every shot")).font(.system(size: 17, weight: .bold, design: .rounded))
                Text(L("What each shot starts from. Change a shot and only that shot changes.")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            KinoSection(title: L("SAID IN EVERY PROMPT"), note: L("Before each shot's own words")) {
                TextField(L("The product's facts and the look: Easyshape jeans, smooth waistband, metal buckle…"),
                          text: Binding(get: { desk.batch.shared }, set: { desk.setShared($0) }), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 12.5)).lineLimit(3...8)
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            }
            KinoSection(title: L("SETTINGS")) {
                VStack(alignment: .leading, spacing: 9) {
                    KinoModelPicker(settings: settings)
                    KinoSettingsBar(settings: settings)
                    HStack(spacing: 8) {
                        Text(L("Takes")).font(.system(size: 11)).foregroundStyle(.secondary)
                        KinoTakesPicker(settings: settings)
                    }
                    Text(L(KinoModel.named(desk.batch.settings.model).note)).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !own.isEmpty {
                KinoSection(title: L("SHOTS WITH THEIR OWN SETTINGS")) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(own, id: \.self) { code in
                            HStack(spacing: 10) {
                                Text(code).font(.system(size: 12, weight: .bold)).foregroundStyle(accent)
                                Text(KinoSummary.settings(desk.settings(code))).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Button(L("Use every shot's")) { desk.setSettings(nil, for: code) }.buttonStyle(.link).font(.system(size: 11))
                            }
                            .padding(.vertical, 6)
                            if code != own.last { Divider() }
                        }
                    }
                }
            }
        }
    }
}

/// The media you put in: empty until you drop files or folders here (or press Add), in the order you pick, filtered by kind
/// when there is more than one. Each shows the shots it is in; drag one onto a shot or a place in it, or press its + to
/// put it in the shot you last worked on.
struct KinoMediaBin: View {
    @ObservedObject var desk: KinoDesk
    @AppStorage("kinoMediaSort") private var sort = KinoSort.name
    @State private var kind: KinoKind?
    @State private var targeted = false
    static let width: CGFloat = 272
    private let accent = PixelKino.theme
    var body: some View {
        let all = desk.media(sorted: sort)
        let kinds = [KinoKind.image, .video, .audio].filter { kind in all.contains { $0.kind == kind } }
        let showing = kinds.contains(kind ?? .image) && kind != nil ? kind : nil
        let shown = all.filter { showing == nil || $0.kind == showing }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 6) {
                Text(L("MEDIA")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                if !all.isEmpty { Text("\(all.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary) }
                Spacer()
                if all.count > 1 {
                    Menu {
                        Picker(L("Sort by"), selection: $sort) { ForEach(KinoSort.allCases, id: \.self) { Text(L($0.title)).tag($0) } }
                            .pickerStyle(.inline)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down").font(.system(size: 9, weight: .semibold))
                            Text(L(sort.title)).font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(.secondary).padding(.horizontal, 7).frame(height: 22)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .help(L("Sort the media"))
                }
                Button { desk.choose() } label: { Label(L("Add"), systemImage: "plus") }.controlSize(.small)
            }
            if kinds.count > 1 {
                KinoPills(options: [KinoModel.Option(id: "", title: L("All %@", all.count))] + kinds.map { kind in
                    let count = all.filter { $0.kind == kind }.count
                    return KinoModel.Option(id: kind.rawValue, title: L(kind == .image ? "Pictures %@" : kind == .video ? "Videos %@" : "Sounds %@", count))
                }, selected: showing?.rawValue ?? "", stretch: true) { kind = KinoKind(rawValue: $0) }
            }
            if all.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 26, weight: .light)).foregroundStyle(targeted ? accent : .secondary)
                    Text(L("Drop pictures, videos and sounds")).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.center)
                    Text(md: L("Or a folder of them. Files named **K1**, **K1.1**… go straight into their shot."))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).strokeBorder(targeted ? accent : .white.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                .contentShape(Rectangle())
                .onTapGesture { desk.choose() }
            } else {
                ThinScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(KinoMediaTile.width), spacing: 10), count: 3), alignment: .leading, spacing: 10) {
                        ForEach(shown) { file in
                            KinoMediaTile(file: file, shots: desk.shots(using: file.id), missing: desk.missing.contains(file.id),
                                          seconds: desk.durations[file.id], target: desk.selected,
                                          put: { if let target = desk.selected { desk.add([file.url], into: target) } }, remove: { desk.remove(file.id) })
                        }
                    }
                    .padding(.bottom, 8)
                }
                Text(L("Drop more here, or drag a file onto a shot")).font(.system(size: 10)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(accent.opacity(targeted && !all.isEmpty ? 0.9 : 0), lineWidth: 2))
        .kinoDrop($targeted) { desk.add($0) }
    }
}

/// A file in the media: its picture, the shot it is in on its corner, its name. Drag it onto a shot, or into Premiere.
struct KinoMediaTile: View {
    let file: KinoFile
    let shots: [String]
    let missing: Bool
    let seconds: Double?
    /// The shot you last worked on, which the + puts the file in.
    let target: String?
    let put: () -> Void
    let remove: () -> Void
    static let width: CGFloat = 74
    @State private var hovering = false
    private let accent = PixelKino.theme
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KinoThumb(url: file.url, width: Self.width, height: 92, corner: 7)
                .opacity(missing ? 0.35 : 1)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(hovering ? 0.4 : 0.07), lineWidth: hovering ? 1.5 : 1))
                .overlay(alignment: .bottomTrailing) { KinoLength(kind: file.kind, seconds: seconds, compact: true) }
                .overlay(alignment: .topLeading) {
                    if missing {
                        KinoBadge(text: L("Missing"), color: .red)
                    } else if let first = shots.first {
                        KinoBadge(text: shots.count > 1 ? "\(first) +\(shots.count - 1)" : first, color: accent)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if hovering, let target, !shots.contains(target), !missing {
                        Button(action: put) {
                            Image(systemName: "plus").font(.system(size: 9, weight: .heavy)).foregroundStyle(.black)
                                .frame(width: 18, height: 18).background(accent, in: Circle())
                        }
                        .buttonStyle(.plain).padding(4).help(L("Put it in %@", target))
                    }
                }
            Text(file.url.lastPathComponent).font(.system(size: 10)).foregroundStyle(shots.isEmpty ? .primary : .secondary)
                .lineLimit(1).truncationMode(.middle)
        }
        .frame(width: Self.width, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(file.url) }
        .onDrag { NSItemProvider(contentsOf: file.url) ?? NSItemProvider() }
        .help(file.url.path(percentEncoded: false) + "\n" + (shots.isEmpty ? L("Not in a shot") : L("In %@", shots.joined(separator: ", "))))
        .contextMenu {
            Button(L("Open")) { NSWorkspace.shared.open(file.url) }
            Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            if let target, !shots.contains(target) { Button(L("Put it in %@", target), action: put) }
            Divider()
            Button(L("Remove from Kino"), action: remove)
        }
    }
}

/// A small label on a picture's corner: the shot a file is in, a file gone missing.
struct KinoBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.system(size: 9, weight: .bold)).foregroundStyle(color == .red ? .white : .black).lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 1.5).background(color, in: Capsule()).padding(4)
    }
}

/// A video's or a sound's length, in the corner of its picture.
struct KinoLength: View {
    let kind: KinoKind
    let seconds: Double?
    var compact = false
    var body: some View {
        if kind != .image {
            Label(seconds.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " s" } ?? "",
                  systemImage: kind == .video ? "video.fill" : "waveform")
                .font(.system(size: compact ? 8.5 : 9.5, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                .labelStyle(KinoTightLabel())
                .padding(.horizontal, compact ? 4 : 6).padding(.vertical, 2).background(.black.opacity(0.65), in: Capsule()).padding(compact ? 3 : 5)
        }
    }
}

/// Files dragged onto a part of Kino's page, from Finder or from Kino's own media and shots, as file URLs: the same way
/// Tala's and Pix's pages take them.
extension View {
    func kinoDrop(_ targeted: Binding<Bool>, _ dropped: @escaping ([URL]) -> Void) -> some View {
        onDrop(of: [.fileURL], isTargeted: targeted) { providers in
            var urls = [URL?](repeating: nil, count: providers.count)
            let group = DispatchGroup()
            for (index, provider) in providers.enumerated() {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    DispatchQueue.main.async { urls[index] = url; group.leave() }
                }
            }
            group.notify(queue: .main) {
                let found = urls.compactMap { $0 }
                if !found.isEmpty { dropped(found) }
            }
            return !providers.isEmpty
        }
    }
}

/// A row of choices in one rounded track, the chosen one in Kino's colour (the Forge's settings, as pills).
struct KinoPills: View {
    let options: [KinoModel.Option]
    let selected: String
    /// The choices share the width they are given.
    var stretch = false
    let pick: (String) -> Void
    private let accent = PixelKino.theme
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.id) { option in
                let on = option.id == selected
                Button { pick(option.id) } label: {
                    Text(option.title).font(.system(size: 11, weight: on ? .semibold : .medium)).lineLimit(1)
                        .foregroundStyle(on ? accent : .secondary)
                        .padding(.horizontal, 9).frame(maxWidth: stretch ? .infinity : nil).frame(height: 22)
                        .background(on ? accent.opacity(0.17) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06)))
        .fixedSize(horizontal: !stretch, vertical: true)
    }
}

/// The model, as pills: Kling O3, Seedance and Motion Control through Higgsfield, Kling 4.0 from Kling.
struct KinoModelPicker: View {
    @Binding var settings: KinoSettings
    var body: some View {
        let current = settings.fitted(to: KinoModel.named(settings.model))
        KinoPills(options: KinoModel.all.map { KinoModel.Option(id: $0.id, title: $0.pill) }, selected: current.model) { id in
            settings = current.fitted(to: KinoModel.named(id))
        }
        .help(KinoModel.all.map { "\($0.name) (\($0.service.rawValue)): \(L($0.note))" }.joined(separator: "\n"))
    }
}

/// How many takes a run makes.
struct KinoTakesPicker: View {
    @Binding var settings: KinoSettings
    var body: some View {
        KinoPills(options: (1...4).map { KinoModel.Option(id: "\($0)", title: "×\($0)") }, selected: "\(settings.takes)") { value in
            settings.takes = Int(value) ?? 1
        }
        .help(L("Takes a run makes"))
    }
}

/// The settings the chosen model takes, and only those: its length, picture size, shape and sound.
struct KinoSettingsBar: View {
    @Binding var settings: KinoSettings
    /// The video a shot edits, whose length the take has: no length to pick then.
    var lengthFrom: String? = nil
    private let accent = PixelKino.theme
    var body: some View {
        let model = KinoModel.named(settings.model)
        let current = settings.fitted(to: model)
        FlowLayout(spacing: 8) {
            if let lengthFrom {
                plain(L("As long as @%@", lengthFrom), icon: "timer")
            } else if let range = model.seconds {
                Menu {
                    Button(L("Auto (%@ s)", model.defaultSeconds)) { settings = with(current) { $0.seconds = nil } }
                    Divider()
                    ForEach(Array(range), id: \.self) { value in Button("\(value) s") { settings = with(current) { $0.seconds = value } } }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "timer").font(.system(size: 10))
                        Text(current.seconds.map { "\($0) s" } ?? L("Auto (%@ s)", model.defaultSeconds)).font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .bold)).opacity(0.6)
                    }
                    .foregroundStyle(.primary.opacity(0.85)).padding(.horizontal, 9).frame(height: 26)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06)))
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help(L("How long each take is"))
            }
            if !model.qualities.isEmpty {
                KinoPills(options: model.qualities, selected: current.quality) { id in settings = with(current) { $0.quality = id } }
            }
            if !model.aspects.isEmpty {
                KinoPills(options: model.aspects.map { KinoModel.Option(id: $0, title: $0 == "adaptive" ? L("Auto") : $0) }, selected: current.aspect) { value in
                    settings = with(current) { $0.aspect = value }
                }
            }
            if model.sound == true {
                Button { settings = with(current) { $0.sound.toggle() } } label: {
                    Label(L(current.sound ? "Sound on" : "Sound off"), systemImage: current.sound ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(current.sound ? accent : .secondary)
                        .padding(.horizontal, 9).frame(height: 26)
                        .background(current.sound ? accent.opacity(0.17) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if model.id == "kling-4.0" {
                plain(L("Always makes sound"), icon: "speaker.wave.2")
            }
        }
    }

    func with(_ settings: KinoSettings, _ change: (inout KinoSettings) -> Void) -> KinoSettings {
        var settings = settings
        change(&settings)
        return settings
    }

    func plain(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 9).frame(height: 26)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1)))
    }
}

/// Whether a shot can run: ready (green), empty or not written yet (grey), or how many things to fix (red).
struct KinoState: View {
    let plan: KinoPlan
    /// No files and no prompt yet.
    var empty = false
    var body: some View {
        let issues = KinoSummary.issues(plan)
        Group {
            if empty {
                Label(L("Empty"), systemImage: "circle.dashed").foregroundStyle(.secondary)
            } else if !issues.isEmpty {
                Label(issues.count == 1 ? L("1 to fix") : L("%@ to fix", issues.count), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            } else if KinoSummary.unwritten(plan) {
                Label(L("To write"), systemImage: "circle.dashed").foregroundStyle(.secondary)
            } else {
                Label(L("Ready"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .font(.system(size: 10.5, weight: .medium)).labelStyle(KinoTightLabel())
    }
}

struct KinoTightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon.font(.system(size: 9)); configuration.title }
    }
}

/// A part of a panel: its heading, a note or control on the right, then what it holds.
struct KinoSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.trailing = trailing; self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                trailing()
            }
            content()
        }
    }
}

extension KinoSection where Trailing == Text {
    init(title: String, note: String = "", @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { Text(note).font(.system(size: 10.5)).foregroundStyle(.tertiary) }, content: content)
    }
}

/// The words the cards use: what a shot does, said by its roles, and its settings in one line.
enum KinoSummary {
    @MainActor static func what(_ desk: KinoDesk, _ code: String) -> String {
        let files = desk.files(in: code)
        func first(_ role: KinoRole) -> KinoFile? { files.first { desk.role(of: $0, in: code) == role } }
        if let edit = first(.edit) { return L("Edits @%@", edit.handle) }
        if let motion = first(.motion) {
            return desk.settings(code).model == "kling-motion" ? L("Moves from @%@", motion.handle) : L("Camera from @%@", motion.handle)
        }
        if let start = first(.start) { return L("Opens on @%@", start.handle) }
        let looks = files.filter { desk.role(of: $0, in: code) == .look }
        if looks.count == 1 { return L("Looks like @%@", looks[0].handle) }
        if looks.count > 1 { return L("Looks from %@ pictures", looks.count) }
        return L("From words only")
    }

    static func settings(_ settings: KinoSettings) -> String {
        let model = KinoModel.named(settings.model)
        let current = settings.fitted(to: model)
        let quality = model.qualities.first { $0.id == current.quality }?.title
        let aspect = model.aspects.isEmpty ? nil : current.aspect == "adaptive" ? L("Follows the files") : current.aspect
        return [model.short, aspect, quality, "×\(current.takes)"].compactMap { $0 }.joined(separator: " · ")
    }

    /// What is wrong with a shot, without its prompt not being written yet: a shot you have not got to is not wrong.
    static func issues(_ plan: KinoPlan) -> [String] { plan.problems.filter { $0 != L("Write what happens in the shot") } }
    static func unwritten(_ plan: KinoPlan) -> Bool { plan.problems.contains(L("Write what happens in the shot")) }
}

extension KinoModel {
    /// The name without its version in brackets, where a line is short: "Kling O3".
    var short: String { name.components(separatedBy: " (").first ?? name }
    /// The name on its pill.
    var pill: String {
        switch id {
        case "seedance-2.5": "Seedance"
        case "kling-motion": "Motion Control"
        case "kling-4.0": "Kling 4.0"
        default: short
        }
    }
}

extension KinoRole {
    /// One colour per role, the same on the file, on its @tag in the prompt and in what is sent. Red is kept for what is
    /// wrong, green for ready, Kino's orange for what is chosen.
    var tint: NSColor {
        switch self {
        case .look: .systemBlue
        case .start, .end: .systemTeal
        case .motion: .systemPurple
        case .edit: .systemYellow
        case .sound: .systemMint
        case .unused: .secondaryLabelColor
        }
    }
    var color: Color { Color(nsColor: tint) }
    /// The role on a file's picture, where there is little room.
    var short: String {
        switch self {
        case .look: "Look"
        case .start: "Start"
        case .end: "End"
        case .motion: "Motion"
        case .edit: "Edit"
        case .sound: "Sound"
        case .unused: "Left out"
        }
    }
}

/// Up to three of a shot's pictures, fanned like prints on a desk, on a folded card.
struct KinoFan: View {
    let files: [KinoFile]
    var body: some View {
        let shown = Array(files.prefix(3))
        ZStack(alignment: .leading) {
            if shown.isEmpty {
                RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 22, height: 30)
            }
            ForEach(Array(shown.enumerated().reversed()), id: \.element.id) { index, file in
                KinoThumb(url: file.url, width: 22, height: 30, corner: 4)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.5), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 1.5, x: 1)
                    .offset(x: CGFloat(index) * 7)
            }
        }
        .frame(width: 38, alignment: .leading)
    }
}

/// One shot, as a card in the list. Its header: the fold arrow, the code and what the shot does, the model, the takes, whether
/// it can run, and its menu. Under it, left to right: its files, each with its role on it, and one + box to add more; the
/// prompt with the settings and Run under it; its takes. Narrow, the files go above the prompt and the takes are left to the
/// header's count. Files dropped anywhere on the card, or on the +, join the shot with their usual role (the first picture
/// opens it). While files are dragged over the card, a box for each place the model still has room for (end frame, video to
/// edit…) shows after them, to drop on for that role; the role is part of what is sent (its slot and endpoint), not only
/// words in the prompt (docs/kino/kling.md §4).
struct KinoShotCard: View {
    @ObservedObject var desk: KinoDesk
    let code: String
    /// The list's width, which decides how the card is laid out.
    let width: CGFloat
    @Binding var folded: Bool
    let openAccounts: () -> Void
    let openEveryShot: () -> Void
    @State private var targeted = false
    /// How many of the card's own boxes and files files are dragged over.
    @State private var over = 0
    /// The places shown while files are dragged over the card; kept a moment after, so moving between them does not hide them.
    @State private var places = false
    @State private var showingRequest = false
    private let accent = PixelKino.theme
    /// Room for four places a row, five when the list is wide.
    var inputsWidth: CGFloat { width >= 1000 ? 5 * KinoFileTile.width + 4 * 8 : 4 * KinoFileTile.width + 3 * 8 }

    var body: some View {
        let plan = desk.plan(code)
        let files = desk.files(in: code)
        let chosen = desk.selected == code
        VStack(alignment: .leading, spacing: 14) {
            header(plan, files)
            if !folded {
                if width >= 780 {
                    HStack(alignment: .top, spacing: 20) {
                        drops(inputs(plan, files).frame(width: inputsWidth, alignment: .leading).frame(maxHeight: .infinity, alignment: .top))
                        middle(plan, files).frame(maxWidth: .infinity, alignment: .leading)
                        if width >= 1080 { KinoTakeList(desk: desk, code: code).frame(width: 148) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 16) { drops(inputs(plan, files).frame(maxWidth: .infinity, alignment: .leading)); middle(plan, files) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background {
            // Pressing the card where nothing else takes the press picks it: the + on a file in the media puts it here.
            RoundedRectangle(cornerRadius: 12).fill(chosen ? accent.opacity(0.05) : Color.white.opacity(0.032))
                .contentShape(Rectangle()).onTapGesture { desk.selected = code }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(chosen ? accent.opacity(0.45) : .white.opacity(0.07), lineWidth: 1))
        .onChange(of: targeted || over > 0) { _, dragging in
            desk.dragged(dragging)
            if dragging { withAnimation(.easeOut(duration: 0.15)) { places = true }; return }
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                if !(targeted || over > 0) { withAnimation(.easeOut(duration: 0.15)) { places = false } }
            }
        }
    }

    func header(_ plan: KinoPlan, _ files: [KinoFile]) -> some View {
        let settings = Binding(get: { desk.settings(code) }, set: { desk.setSettings($0, for: code) })
        let prompt = desk.shot(code).prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.15)) { folded.toggle() } } label: {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(folded ? 0 : 90)).frame(width: 18, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(folded ? L("Unfold %@", code) : L("Fold %@", code))
            if folded { KinoFan(files: files.filter { desk.role(of: $0, in: code) != .unused }) }
            Text(code).font(.system(size: 15, weight: .bold, design: .rounded)).fixedSize()
            Text(folded && !prompt.isEmpty ? prompt : KinoSummary.what(desk, code))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                .frame(minWidth: 40, alignment: .leading).layoutPriority(-1)
            Spacer(minLength: 8)
            if folded {
                Text(KinoSummary.settings(desk.settings(code))).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            } else if width >= 780 {
                KinoModelPicker(settings: settings)
                KinoTakesPicker(settings: settings)
            } else {
                Menu {
                    ForEach(KinoModel.all) { model in
                        Button(model.name) { settings.wrappedValue = settings.wrappedValue.fitted(to: model) }
                    }
                } label: { Text(KinoModel.named(desk.settings(code).model).pill).font(.system(size: 11, weight: .medium)) }
                .fixedSize()
                KinoTakesPicker(settings: settings)
            }
            let takes = desk.takes(of: code)
            if !takes.isEmpty {
                // Plays the take not watched yet, else the newest, in the outputs.
                Button { desk.watch((takes.first { !$0.seen } ?? takes.last)?.path) } label: {
                    HStack(spacing: 4) {
                        if takes.contains(where: { !$0.seen }) { Circle().fill(accent).frame(width: 6, height: 6) }
                        Image(systemName: "play.fill").font(.system(size: 8))
                        Text(takes.count == 1 ? L("1 take") : L("%@ takes", takes.count)).font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(.secondary).padding(.horizontal, 7).frame(height: 22)
                    .background(.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain).help(L("Watch in the outputs"))
            }
            KinoState(plan: plan, empty: files.isEmpty && desk.shot(code).prompt.isEmpty).frame(minWidth: 62, alignment: .trailing)
            Menu {
                Button(L("What Kino sends")) { showingRequest = true }
                if desk.shot(code).settings != nil { Button(L("Use every shot's settings")) { desk.setSettings(nil, for: code) } }
                Button(L("Add files…")) { desk.choose(into: code) }
                Divider()
                Button(L("Remove %@", code), role: .destructive) { desk.removeShot(code) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .popover(isPresented: $showingRequest, arrowEdge: .bottom) { KinoRequestView(desk: desk, code: code).padding(16).frame(width: 520) }
        }
    }

    /// The shot's files in their places' order, files left out last; one + box while the model has room, and while files are
    /// dragged over the card, a box for each place it has room for.
    func inputs(_ plan: KinoPlan, _ files: [KinoFile]) -> some View {
        let model = KinoModel.named(desk.settings(code).model)
        let roles = desk.roles(code)
        let slots = KinoSlot.all(model: model.id, files: files, roles: roles)
        let most = KinoSlot.most(model: model.id, files: files, roles: roles)
        let used = files.filter { roles[$0.handle] != .unused }
        let room = [(KinoKind.image, "pictures", "picture"), (.video, "videos", "video"), (.audio, "sounds", "sound")].compactMap { kind, many, one -> String? in
            guard let most = most[kind] else { return nil }
            let count = used.filter { $0.kind == kind }.count
            return most == 1 ? L("%@ of 1 " + one, count) : L("%@ of %@ " + many, count, most)
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if desk.dragging {
                    Text(L("DROP TO ADD TO %@", code)).font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(accent)
                } else {
                    Text(L("IN THIS SHOT")).font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
                }
                Text(room.joined(separator: " · ")).font(.system(size: 9.5, weight: .medium).monospacedDigit()).foregroundStyle(.tertiary).lineLimit(1)
            }
            let empty = slots.filter { if case .empty = $0 { true } else { false } }
            let shown = slots.filter { if case .file = $0 { true } else { false } }
            FlowLayout(spacing: 8) {
                // The files, the + box (nil) while the model has room, then the places for each role while files are dragged in.
                let items: [KinoSlot?] = shown + (empty.isEmpty ? [] : [nil]) + (places ? empty : [])
                ForEach(Array(items.enumerated()), id: \.offset) { _, slot in
                    switch slot {
                    case nil:
                        KinoAddSlot(drop: { desk.add($0, into: code); desk.selected = code }, choose: { desk.choose(into: code) }, hovered: hovered)
                    case .file(let file)?:
                        let role = roles[file.handle] ?? .look
                        let index = plan.inputs.firstIndex { $0.handle == file.handle }
                        KinoFileTile(file: file, role: role, seconds: desk.durations[file.id], number: index.map { $0 + 1 },
                                     sentAs: index.map { plan.inputs[$0].tag }, missing: desk.missing.contains(file.id), shot: code,
                                     choose: { desk.setRole($0, of: file, in: code) },
                                     takeOut: { desk.takeOut(file, of: code) },
                                     drop: { desk.add($0, into: code, as: role == .unused ? nil : role); desk.selected = code }, hovered: hovered)
                    case .empty(let role)?:
                        KinoEmptySlot(role: role, motionControl: model.id == "kling-motion",
                                      drop: { desk.add($0, into: code, as: role); desk.selected = code }, choose: { desk.choose(into: code, as: role) },
                                      hovered: hovered)
                    }
                }
            }
        }
    }

    func hovered(_ inside: Bool) { over = max(0, over + (inside ? 1 : -1)) }

    /// The shot's files take a drop, into this shot; while files are dragged over the shots, they are outlined to show it.
    func drops(_ content: some View) -> some View {
        let inside = targeted || over > 0
        return content
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(accent.opacity(inside ? 0.08 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(inside ? 1 : desk.dragging ? 0.45 : 0),
                                                                   style: StrokeStyle(lineWidth: inside ? 2 : 1.2, dash: inside ? [] : [6, 4])))
            .contentShape(Rectangle())
            .kinoDrop($targeted) { desk.add($0, into: code); desk.selected = code }
            .padding(-8)
            .animation(.easeOut(duration: 0.12), value: desk.dragging)
    }

    /// The prompt, what stops the shot or what Kino changes on the way, then the settings and Run.
    func middle(_ plan: KinoPlan, _ files: [KinoFile]) -> some View {
        let model = KinoModel.named(desk.settings(code).model)
        let text = desk.shot(code).prompt
        let roles = desk.roles(code)
        // Every file of the shot can be named in the prompt; one left out shows grey.
        let tags = files.map { file in
            let role = roles[file.handle] ?? .look
            let sent = plan.inputs.contains { $0.handle == file.handle }
            return KinoPromptTag(handle: file.handle, name: file.name, url: file.url, tint: sent ? role.tint : .secondaryLabelColor, role: L(role.short))
        }
        let issues = KinoSummary.issues(plan)
        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                KinoPromptView(text: Binding(get: { desk.shot(code).prompt }, set: { desk.setPrompt($0, for: code) }), tags: tags,
                               began: { desk.selected = code })
                if text.isEmpty {
                    Text(md: L("What happens in the shot. Type **@** to name a file: \"@%@ is held up to the camera…\"", files.first?.name ?? code))
                        .font(.system(size: 13)).foregroundStyle(.tertiary).padding(.horizontal, 13).padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 112)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.07)))
            .overlay(alignment: .bottomTrailing) {
                if let limit = model.promptLimit, plan.prompt.count > limit * 3 / 4 {
                    Text(L("%@ of %@ characters sent", plan.prompt.count.formatted(), limit.formatted())).font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(plan.prompt.count > limit ? Color.red : Color(nsColor: .tertiaryLabelColor)).padding(7)
                }
            }
            if !desk.batch.shared.isEmpty {
                Button(action: openEveryShot) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "text.badge.plus").font(.system(size: 9.5))
                        Text(L("Every shot adds")).font(.system(size: 10.5, weight: .semibold))
                        Text(desk.batch.shared).font(.system(size: 10.5)).lineLimit(1)
                    }
                    .foregroundStyle(.secondary).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(L("Change what every shot's prompt says"))
            }
            if !issues.isEmpty || !plan.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(issues, id: \.self) { line($0, icon: "exclamationmark.triangle.fill", color: .red) }
                    ForEach(plan.notes, id: \.self) { line($0, icon: "info.circle", color: .secondary) }
                }
            }
            HStack(alignment: .center, spacing: 10) {
                KinoSettingsBar(settings: Binding(get: { desk.settings(code) }, set: { desk.setSettings($0, for: code) }),
                                lengthFrom: plan.seconds == nil ? files.first { roles[$0.handle] == .edit }?.handle : nil)
                Spacer(minLength: 0)
                run(plan)
            }
        }
    }

    func line(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon).font(.system(size: 9.5)).foregroundStyle(color)
            Text(md: text).font(.system(size: 11)).foregroundStyle(color == .red ? Color.primary : Color.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Run, and what it waits for under it. Disabled until sending is built.
    func run(_ plan: KinoPlan) -> some View {
        let takes = desk.settings(code).takes
        return VStack(alignment: .trailing, spacing: 4) {
            Button {} label: {
                Label(takes > 1 ? L("Run %@ · %@ takes", code, takes) : L("Run %@", code), systemImage: "play.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(accent.opacity(0.55))
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain).disabled(true).help(desk.blocker([code]))
            if desk.missingKey([code]) {
                Button(desk.blocker([code]), action: openAccounts).buttonStyle(.link).font(.system(size: 10))
            } else {
                Text(KinoSummary.issues(plan).isEmpty && KinoSummary.unwritten(plan) ? L("Write what happens in the shot first") : desk.blocker([code]))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .fixedSize()
    }
}

/// What Kino would send for a shot: where it goes, each file's slot and name, and the prompt as the service reads it.
struct KinoRequestView: View {
    @ObservedObject var desk: KinoDesk
    let code: String
    var body: some View {
        let plan = desk.plan(code)
        let roles = desk.roles(code)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("What Kino sends for %@", code)).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(plan.endpoint).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1)
            }
            if !plan.inputs.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    ForEach(plan.inputs, id: \.handle) { input in
                        GridRow {
                            Text("@" + input.handle).font(.system(size: 11, weight: .semibold)).foregroundStyle((roles[input.handle] ?? .unused).color)
                            Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                            Text(input.tag).font(.system(size: 11))
                            Text(input.slot).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            ScrollView {
                Text(plan.prompt.isEmpty ? " " : plan.prompt).font(.system(size: 11, design: .monospaced)).lineSpacing(2).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            .frame(maxHeight: 260)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// A file in its shot: its picture framed in its role's colour, the order it is sent in, its role on the picture (press it
/// to change it); the prompt names it by typing @. Drag it onto another shot to use it there too, or into Premiere; drop files on it to add them in the same role (on a start or end frame, they take its place).
struct KinoFileTile: View {
    let file: KinoFile
    let role: KinoRole
    let seconds: Double?
    /// Its place in what is sent (1 is sent first), and the name the service gives it.
    let number: Int?
    let sentAs: String?
    let missing: Bool
    let shot: String
    let choose: (KinoRole) -> Void
    let takeOut: () -> Void
    let drop: ([URL]) -> Void
    /// Files dragged onto it or off it.
    var hovered: (Bool) -> Void = { _ in }
    static let width: CGFloat = 80
    static let height: CGFloat = 100
    @State private var hovering = false
    @State private var targeted = false
    var body: some View {
        let off = role == .unused
        VStack(alignment: .leading, spacing: 4) {
            KinoThumb(url: file.url, width: Self.width, height: Self.height, corner: 8)
                .opacity(off || missing ? 0.32 : 1)
                .overlay {
                    if targeted {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(PixelKino.theme, lineWidth: 2.5)
                    } else if off {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    } else {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(role.color, lineWidth: 2)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if missing {
                        KinoBadge(text: L("Missing"), color: .red)
                    } else if let number {
                        Text("\(number)").font(.system(size: 9.5, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16).background(.black.opacity(0.6), in: Circle()).padding(4)
                            .help(sentAs.map { L("Sent as %@", $0) } ?? "")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if hovering {
                        Button(action: takeOut) {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 17, height: 17).background(.black.opacity(0.7), in: Circle())
                        }
                        .buttonStyle(.plain).padding(4).help(L("Take out of %@", shot))
                    } else {
                        KinoLength(kind: file.kind, seconds: seconds, compact: true)
                    }
                }
                .overlay(alignment: .bottom) {
                    Menu {
                        ForEach(KinoRole.choices(file.kind)) { option in
                            Button { choose(option) } label: {
                                if option == role { Label(L(option.title), systemImage: "checkmark") } else { Text(L(option.title)) }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: role.icon).font(.system(size: 8))
                            Text(L(role.short)).font(.system(size: 9.5, weight: .semibold)).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 6.5, weight: .bold)).opacity(0.7)
                        }
                        .foregroundStyle(off ? Color.primary : .white).padding(.horizontal, 6).frame(height: 18)
                        .background(off ? Color.black.opacity(0.6) : Color(nsColor: role.tint.shadow(withLevel: 0.25) ?? role.tint), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .padding(.bottom, 5).help(L(role.detail))
                }
                .onTapGesture(count: 2) { NSWorkspace.shared.open(file.url) }
        }
        .frame(width: Self.width, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: file.url) ?? NSItemProvider() }
        .kinoDrop($targeted, drop)
        .onChange(of: targeted) { _, inside in hovered(inside) }
        .help(file.url.lastPathComponent)
        .contextMenu {
            ForEach(KinoRole.choices(file.kind)) { option in
                Button { choose(option) } label: {
                    if option == role { Label(L(option.title), systemImage: "checkmark") } else { Text(L(option.title)) }
                }
            }
            Divider()
            Button(L("Open")) { NSWorkspace.shared.open(file.url) }
            Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            Divider()
            Button(L("Take out of %@", shot), action: takeOut)
        }
    }
}

/// An empty place in a shot: a dashed box with a + in its role's colour, saying what goes there. A file dropped on it
/// joins the shot in that role; pressing it opens the file chooser.
struct KinoEmptySlot: View {
    let role: KinoRole
    let motionControl: Bool
    let drop: ([URL]) -> Void
    let choose: () -> Void
    var hovered: (Bool) -> Void = { _ in }
    @State private var targeted = false
    @State private var hovering = false
    var body: some View {
        let title = motionControl ? (role == .look ? L("The person") : L("The performance")) : L(role.title)
        let kind = switch role { case .look, .start, .end: L("A picture"); case .motion, .edit: L("A video"); default: L("A sound") }
        VStack(spacing: 5) {
            Image(systemName: "plus").font(.system(size: 17, weight: .light))
            Text(title).font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(kind).font(.system(size: 9)).opacity(0.7)
        }
        .foregroundStyle(role.color.opacity(targeted || hovering ? 1 : 0.8))
        .padding(6)
        .frame(width: KinoFileTile.width, height: KinoFileTile.height)
        .background(RoundedRectangle(cornerRadius: 8).fill(role.color.opacity(targeted ? 0.18 : hovering ? 0.09 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(role.color.opacity(targeted ? 1 : 0.55),
                                                               style: StrokeStyle(lineWidth: targeted ? 2 : 1.3, dash: targeted ? [] : [5, 3.5])))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: choose)
        .kinoDrop($targeted, drop)
        .onChange(of: targeted) { _, inside in hovered(inside) }
        .help(L(role.detail))
    }
}

/// The box that adds files to a shot: drop files on it or press it to choose them. Each takes its usual role, which its
/// pill changes; dragged over the card, the places for other roles show beside it.
struct KinoAddSlot: View {
    let drop: ([URL]) -> Void
    let choose: () -> Void
    var hovered: (Bool) -> Void = { _ in }
    @State private var targeted = false
    @State private var hovering = false
    private let accent = PixelKino.theme
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "plus").font(.system(size: 18, weight: .light))
            Text(L("Add")).font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(targeted || hovering ? accent : Color.secondary)
        .frame(width: KinoFileTile.width, height: KinoFileTile.height)
        .background(RoundedRectangle(cornerRadius: 8).fill(accent.opacity(targeted ? 0.14 : hovering ? 0.06 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? accent : hovering ? accent.opacity(0.6) : .white.opacity(0.2),
                                                               style: StrokeStyle(lineWidth: targeted ? 2 : 1.3, dash: targeted ? [] : [5, 3.5])))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: choose)
        .kinoDrop($targeted, drop)
        .onChange(of: targeted) { _, inside in hovered(inside) }
        .help(L("Drop files, or press to choose them. Drag a file over the shot to see its other places: end frame, video to edit…"))
    }
}

/// A shot's takes, one under another as the Forge lists its outputs: a frame in the shot's shape for each the run makes.
/// Filled once sending is built.
struct KinoTakeList: View {
    @ObservedObject var desk: KinoDesk
    let code: String
    var body: some View {
        let settings = desk.settings(code)
        let takes = desk.takes(of: code)
        let ratio: CGFloat = switch settings.aspect { case "16:9": 16 / 9; case "21:9": 21 / 9; case "1:1": 1; case "4:3": 4 / 3; case "3:4": 3 / 4; default: 9 / 16 }
        let box = CGSize(width: ratio < 1 ? 26 : 40, height: ratio < 1 ? 26 / ratio : 40 / ratio)
        VStack(alignment: .leading, spacing: 6) {
            Text(L("TAKES")).font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(.secondary).padding(.bottom, 2)
            ForEach(Array(takes.enumerated()), id: \.element.id) { index, take in
                let playing = desk.watching == take.path
                Button { desk.watch(take.path) } label: {
                    HStack(spacing: 8) {
                        KinoThumb(url: URL(fileURLWithPath: take.path), width: box.width, height: box.height, corner: 4)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L("Take %@", index + 1)).font(.system(size: 11, weight: .medium))
                            Text(desk.missing.contains(take.path) ? L("No longer on this Mac") : take.seen ? L("Watched") : L("New"))
                                .font(.system(size: 9.5)).foregroundStyle(take.seen ? .tertiary : .secondary)
                        }
                        Spacer(minLength: 0)
                        if !take.seen { Circle().fill(PixelKino.theme).frame(width: 6, height: 6) }
                    }
                    .padding(6).contentShape(Rectangle())
                    .background((playing ? PixelKino.theme.opacity(0.12) : .white.opacity(0.03)), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain).help(L("Watch in the outputs"))
            }
            ForEach(takes.count..<max(takes.count, settings.takes), id: \.self) { index in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.03))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .frame(width: box.width, height: box.height)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Take %@", index + 1)).font(.system(size: 11, weight: .medium))
                        Text(L("Not made yet")).font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(6).background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 7))
            }
            if takes.isEmpty {
                Text(L("Each take shows here as soon as it is made, to watch and drag into Premiere."))
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            }
        }
    }
}

/// The takes to watch, the newest first, as the Forge shows its outputs beside the jobs: press one to play it here (it
/// counts as watched), drag it into Premiere or onto a shot to edit it there. Picking a shot brings its takes into view.
/// Until Kino sends, finished videos dropped here are the takes, each with the shot its name has (K3.1 O1 with K3).
struct KinoOutputs: View {
    @ObservedObject var desk: KinoDesk
    @State private var targeted = false
    private let accent = PixelKino.theme
    var body: some View {
        let takes = desk.takes
        let fresh = takes.filter { !$0.seen }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(L("OUTPUTS")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                if !takes.isEmpty { Text("\(takes.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary) }
                Spacer()
                if fresh > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(accent).frame(width: 6, height: 6)
                        Text(L("%@ new", fresh)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 22)
            if takes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle").font(.system(size: 26, weight: .light)).foregroundStyle(targeted ? accent : .secondary)
                    Text(L("Takes to watch")).font(.system(size: 12, weight: .semibold))
                    Text(md: L("Each take shows here as it is made. Until Kino sends, drop finished videos here: **K3 O1** goes with shot K3."))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).strokeBorder(targeted ? accent : .white.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            } else {
                ScrollViewReader { proxy in
                    ThinScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(takes) { take in KinoOutputTile(desk: desk, take: take).id(take.path) }
                        }
                        .padding(.bottom, 8)
                    }
                    .onChange(of: desk.watching) { _, path in
                        if let path { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(path) } }
                    }
                    .onChange(of: desk.selected) { _, code in
                        if let newest = takes.first(where: { $0.shot == code }) { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(newest.path) } }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(accent.opacity(targeted && !takes.isEmpty ? 0.9 : 0), lineWidth: 2))
        .kinoDrop($targeted) { desk.addTakes($0) }
    }
}

/// One take in the outputs: its shot and number, the model, its picture until you press it, then the player.
struct KinoOutputTile: View {
    @ObservedObject var desk: KinoDesk
    let take: KinoTake
    @State private var poster: NSImage?
    @State private var hovering = false
    private let accent = PixelKino.theme
    static let height: CGFloat = 320
    var body: some View {
        let url = URL(fileURLWithPath: take.path)
        let playing = desk.watching == take.path
        let missing = desk.missing.contains(take.path)
        let chosen = take.shot != nil && take.shot == desk.selected
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text([take.model.map { KinoModel.named($0).name }, desk.durations[take.path].map { $0.formatted(.number.precision(.fractionLength(0...1))) + " s" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if missing {
                    KinoBadge(text: L("Missing"), color: .red).padding(-4)
                } else if take.seen {
                    Label(L("Watched"), systemImage: "checkmark").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary).labelStyle(KinoTightLabel())
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(accent).frame(width: 6, height: 6)
                        Text(L("New")).font(.system(size: 10, weight: .semibold)).foregroundStyle(accent)
                    }
                }
            }
            ZStack {
                Rectangle().fill(.black)
                if playing && !missing {
                    KinoPlayer(url: url)
                } else {
                    if let poster { Image(nsImage: poster).resizable().scaledToFit().opacity(missing ? 0.35 : 1) }
                    if !missing {
                        Image(systemName: "play.fill").font(.system(size: 18)).foregroundStyle(.white)
                            .frame(width: 46, height: 46).background(.black.opacity(hovering ? 0.7 : 0.5), in: Circle())
                    }
                }
            }
            .frame(maxWidth: .infinity).frame(height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { if !playing && !missing { desk.watch(take.path) } }
        }
        .padding(10)
        .background(.white.opacity(playing ? 0.07 : 0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(playing ? accent : chosen ? accent.opacity(0.4) : .white.opacity(0.07), lineWidth: playing ? 1.5 : 1))
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .help(take.path)
        .task(id: take.path) { poster = await KinoThumb.load(url, side: Self.height) }
        .contextMenu {
            Button(playing ? L("Stop") : L("Play")) { desk.watch(playing ? nil : take.path) }.disabled(missing)
            Button(L("Open")) { NSWorkspace.shared.open(url) }.disabled(missing)
            Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }.disabled(missing)
            if let target = desk.selected { Button(L("Put it in %@", target)) { desk.add([url], into: target) }.disabled(missing) }
            Divider()
            Button(L("Remove from the outputs")) { desk.removeTake(take.path) }
        }
    }

    /// K3 · Take 2; the file's name when it is in no shot.
    var title: String {
        guard let code = take.shot, let number = desk.number(of: take) else { return URL(fileURLWithPath: take.path).lastPathComponent }
        return L("%@ · Take %@", code, number)
    }
}

/// A take playing, with the system's own controls (scrub, sound, full screen); it starts as it shows and stops as it goes.
struct KinoPlayer: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        view.player = AVPlayer(url: url)
        view.player?.play()
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if (view.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            view.player = AVPlayer(url: url)
            view.player?.play()
        }
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player?.pause(); view.player = nil }
}

/// The last card: drop files on it to make a shot of them, or press it for an empty one.
struct KinoNewShot: View {
    @ObservedObject var desk: KinoDesk
    @State private var targeted = false
    @State private var hovering = false
    private let accent = PixelKino.theme
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus").font(.system(size: 15, weight: .medium)).foregroundStyle(targeted || hovering ? accent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("New shot")).font(.system(size: 12.5, weight: .semibold))
                Text(L("Drop files here to make a shot of them, or press for an empty one")).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18).frame(maxWidth: .infinity, minHeight: 60)
        .background(RoundedRectangle(cornerRadius: 12).fill(accent.opacity(targeted ? 0.1 : hovering ? 0.04 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(targeted ? accent : .white.opacity(0.16), style: StrokeStyle(lineWidth: targeted ? 2 : 1.2, dash: targeted ? [] : [6, 4])))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { desk.newShot() }
        .kinoDrop($targeted) { desk.newShot(with: $0) }
    }
}

/// The two accounts. Higgsfield runs Seedance, Kling O3 and Motion Control under one key; Kling's own API has Kling 4.0.
/// Keys go in the Keychain; nothing checks them until Kino sends his first job.
struct KinoAccounts: View {
    @ObservedObject var desk: KinoDesk
    @State private var klingKey = ""
    @State private var keyID = ""
    @State private var secret = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            account("Higgsfield", L("Seedance 2.5, Kling O3 and Motion Control"), saved: desk.hasHiggsfield,
                    remove: desk.removeHiggsfield, site: "https://console.higgsfield.ai") {
                TextField(L("Key ID"), text: $keyID).textFieldStyle(.roundedBorder)
                SecureField(L("Key secret"), text: $secret).textFieldStyle(.roundedBorder)
                Button(L("Save")) { desk.saveHiggsfield(id: keyID, secret: secret); keyID = ""; secret = "" }
                    .disabled(keyID.trimmingCharacters(in: .whitespaces).isEmpty || secret.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Divider()
            account("Kling", L("Kling 4.0 Omni, from Kling itself"), saved: desk.hasKling,
                    remove: { desk.saveKling(nil) }, site: "https://kling.ai/dev/api-key") {
                SecureField(L("API key"), text: $klingKey).textFieldStyle(.roundedBorder).onSubmit(saveKling)
                Button(L("Save"), action: saveKling).disabled(klingKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(md: L("Keys are kept in your Mac's **Keychain**, never in your projects."))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveKling() { desk.saveKling(klingKey); klingKey = "" }

    func account<Fields: View>(_ name: String, _ what: String, saved: Bool, remove: @escaping () -> Void, site: String,
                               @ViewBuilder fields: () -> Fields) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: saved ? "checkmark.circle.fill" : "key").font(.system(size: 11)).foregroundStyle(saved ? Color.green : .secondary)
                Text(name).font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Button(L("Get a key")) { NSWorkspace.shared.open(URL(string: site)!) }.buttonStyle(.link).font(.system(size: 10.5))
            }
            Text(what).font(.system(size: 10.5)).foregroundStyle(.secondary)
            if saved {
                HStack(spacing: 8) {
                    Text(L("Key saved · checked on the first run")).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Remove"), role: .destructive, action: remove).controlSize(.small)
                }
            } else {
                fields().controlSize(.small)
            }
        }
    }
}

/// A file's picture, made by Kino: a frame from a video (a tenth of the way in, past a black first frame), a picture
/// scaled down, Quick Look for anything else; the kind's symbol while it loads or when there is none (a sound). Kept
/// while the app runs.
struct KinoThumb: View {
    let url: URL
    let width: CGFloat
    let height: CGFloat
    var corner: CGFloat = 6
    @State private var image: NSImage?
    private static let cache = NSCache<NSString, NSImage>()
    var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.05))
            if let image {
                Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
            } else {
                Image(systemName: { switch KinoKind(url) { case .image: "photo"; case .video: "film"; case .audio: "waveform"; case nil: "doc" } }())
                    .font(.system(size: max(10, min(width, height) * 0.2))).foregroundStyle(.tertiary)
            }
        }
        .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: corner))
        .task(id: url) {
            let made = await Self.load(url, side: max(width, height))
            withAnimation(.easeOut(duration: 0.15)) { image = made }
        }
    }

    static func load(_ url: URL, side: CGFloat) async -> NSImage? {
        let key = "\(url.path)|\(Int(side))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let pixels = side * 2
        var made: CGImage?
        switch KinoKind(url) {
        case .image:
            made = await Task.detached(priority: .utility) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary)
            }.value
        case .video:
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: pixels, height: pixels)
            let length = (try? await asset.load(.duration)).map(\.seconds) ?? 0
            let at = CMTime(seconds: length.isFinite && length > 0 ? min(1.5, length * 0.1) : 0, preferredTimescale: 600)
            made = try? await generator.image(at: at).image
        case .audio, nil:
            return nil
        }
        if made == nil {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: 2, representationTypes: .thumbnail)
            made = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
        }
        guard let made else { return nil }
        let image = NSImage(cgImage: made, size: NSSize(width: made.width, height: made.height))
        cache.setObject(image, forKey: key)
        return image
    }
}

/// A shot's prompt as you write it: the tag of each file the shot sends in its role's colour, any other @tag in red and
/// underlined (it names no file this shot sends). A file's tag button puts its tag where the cursor is.
/// A file the prompt can name: its tag, what the pill shows (the file's name), and its role's colour.
struct KinoPromptTag: Equatable {
    let handle: String
    let name: String
    let url: URL
    let tint: NSColor
    let role: String
}

/// The shot's prompt. The text kept and sent names files by tag (@K4-size); here each named file shows as a pill with its
/// name in its role's colour, as the Forge shows them, and goes as one piece when deleted. Typing @ lists the shot's files
/// to pick from (arrows and Return, or a click; Escape keeps the @ as typed); a tag typed out whole becomes a pill after a
/// space. A tag that names no file of the shot stays text, in red.
struct KinoPromptView: NSViewRepresentable {
    @Binding var text: String
    let tags: [KinoPromptTag]
    /// When you start writing in it.
    var began: (() -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = OverlayScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = KinoPromptTextView()
        editor.isRichText = true
        editor.importsGraphics = false
        editor.usesFontPanel = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.drawsBackground = false
        editor.insertionPointColor = NSColor(PixelKino.theme)
        editor.textContainerInset = NSSize(width: 8, height: 12)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.typingAttributes = Coordinator.plain
        editor.delegate = context.coordinator
        editor.textStorage?.setAttributedString(context.coordinator.rendered(text))
        context.coordinator.color(editor)
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let changed = coordinator.parent.tags != tags
        coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView, let storage = view.textStorage else { return }
        if Coordinator.written(storage) != text || changed {
            // Changed from outside (another project, a file renamed or its role changed): drawn again from the text.
            let at = view.selectedRange()
            storage.setAttributedString(coordinator.rendered(text))
            view.setSelectedRange(NSRange(location: min(at.location, storage.length), length: 0))
            coordinator.color(view)
        }
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) { coordinator.picker.hide() }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: KinoPromptView
        let picker = KinoTagPicker()
        /// The @ you pressed Escape on: no list for it again.
        private var dismissed: Int?
        private var busy = false
        static let font = NSFont.systemFont(ofSize: 13)
        static var plain: [NSAttributedString.Key: Any] {
            let lines = NSMutableParagraphStyle()
            lines.lineSpacing = 5
            return [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: lines]
        }
        init(_ parent: KinoPromptView) { self.parent = parent }

        func known(_ handle: String) -> KinoPromptTag? { parent.tags.first { $0.handle.lowercased() == handle.lowercased() } }

        /// The text as kept, each pill written as its @tag.
        static func written(_ text: NSAttributedString) -> String {
            var out = ""
            text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                if let pill = value as? KinoTagAttachment {
                    out += String(repeating: "@" + pill.handle, count: range.length)
                } else {
                    out += (text.string as NSString).substring(with: range)
                }
            }
            return out
        }
        /// The text kept, each tag of a file in the shot as its pill.
        func rendered(_ text: String) -> NSAttributedString {
            let result = NSMutableAttributedString()
            var last = text.startIndex
            for tag in KinoPrompt.tags(in: text) {
                guard let file = known(tag.handle) else { continue }
                result.append(NSAttributedString(string: String(text[last..<tag.range.lowerBound]), attributes: Self.plain))
                result.append(pill(file))
                last = tag.range.upperBound
            }
            result.append(NSAttributedString(string: String(text[last...]), attributes: Self.plain))
            return result
        }
        func pill(_ file: KinoPromptTag) -> NSAttributedString {
            let made = NSMutableAttributedString(attachment: KinoTagAttachment(file))
            made.addAttributes(Self.plain, range: NSRange(location: 0, length: made.length))
            return made
        }

        func textDidBeginEditing(_ notification: Notification) { parent.began?() }
        func textDidEndEditing(_ notification: Notification) { picker.hide() }
        func textDidChange(_ notification: Notification) {
            guard !busy, let view = notification.object as? NSTextView else { return }
            pillTyped(view)
            parent.text = Self.written(view.textStorage ?? NSAttributedString())
            color(view)
            suggest(view)
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !busy, let view = notification.object as? NSTextView else { return }
            suggest(view)
        }
        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard picker.shown else { return false }
            switch selector {
            case #selector(NSResponder.moveDown(_:)): picker.move(1); return true
            case #selector(NSResponder.moveUp(_:)): picker.move(-1); return true
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                if let file = picker.chosen { pick(file, in: view) }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                dismissed = query(view)?.range.location
                picker.hide()
                return true
            default: return false
            }
        }

        /// The @ and what is typed after it, up to the cursor, when the cursor is in one.
        func query(_ view: NSTextView) -> (range: NSRange, text: String)? {
            let selection = view.selectedRange()
            guard selection.length == 0 else { return nil }
            let string = view.string as NSString
            var start = selection.location
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
            while start > 0, let scalar = UnicodeScalar(string.character(at: start - 1)), allowed.contains(scalar), selection.location - start < 40 { start -= 1 }
            guard start > 0, string.character(at: start - 1) == 64 else { return nil }  // "@"
            let at = start - 1
            // An @ inside a word (mail@x) is not a tag.
            if at > 0, let before = UnicodeScalar(string.character(at: at - 1)), CharacterSet.alphanumerics.contains(before) { return nil }
            return (NSRange(location: at, length: selection.location - at), string.substring(with: NSRange(location: start, length: selection.location - start)))
        }

        func suggest(_ view: NSTextView) {
            guard let query = query(view) else { dismissed = nil; picker.hide(); return }
            guard dismissed != query.range.location else { return }
            let words = query.text.lowercased()
            let found = parent.tags.filter { words.isEmpty || $0.handle.lowercased().hasPrefix(words) || $0.name.lowercased().contains(words) }
            guard !found.isEmpty else { picker.hide(); return }
            let caret = view.firstRect(forCharacterRange: NSRange(location: query.range.location, length: 0), actualRange: nil)
            picker.show(found, under: caret, in: view.window) { [weak self, weak view] file in
                guard let self, let view else { return }
                self.pick(file, in: view)
            }
        }

        /// The @ and what was typed after it become the file's pill, with a space after it.
        func pick(_ file: KinoPromptTag, in view: NSTextView) {
            guard let query = query(view), let storage = view.textStorage else { return }
            picker.hide()
            let string = view.string as NSString
            let end = NSMaxRange(query.range)
            let spaced = end < string.length && CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(string.character(at: end)) ?? " ")
            let made = NSMutableAttributedString(attributedString: pill(file))
            if !spaced { made.append(NSAttributedString(string: " ", attributes: Self.plain)) }
            guard view.shouldChangeText(in: query.range, replacementString: made.string) else { return }
            busy = true
            storage.replaceCharacters(in: query.range, with: made)
            view.didChangeText()
            busy = false
            view.setSelectedRange(NSRange(location: query.range.location + made.length + (spaced ? 1 : 0), length: 0))
            view.typingAttributes = Self.plain
            parent.text = Self.written(storage)
            color(view)
        }

        /// A tag of the shot's typed out whole (or pasted) becomes its pill once a space or a line follows it.
        func pillTyped(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let string = view.string
            for tag in KinoPrompt.tags(in: string).reversed() {
                guard let file = known(tag.handle), tag.range.upperBound < string.endIndex,
                      string[tag.range.upperBound].isWhitespace else { continue }
                let range = NSRange(tag.range, in: string)
                guard view.shouldChangeText(in: range, replacementString: "\u{FFFC}") else { continue }
                let at = view.selectedRange()
                busy = true
                storage.replaceCharacters(in: range, with: pill(file))
                view.didChangeText()
                busy = false
                let shift = range.length - 1
                view.setSelectedRange(NSRange(location: at.location >= NSMaxRange(range) ? at.location - shift : min(at.location, range.location + 1), length: 0))
            }
            view.typingAttributes = Self.plain
        }

        /// Plain text in the text's colour; a tag that names no file of the shot in red, dotted.
        func color(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let all = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.underlineStyle, range: all)
            storage.addAttributes(Self.plain, range: all)
            for tag in KinoPrompt.tags(in: view.string) where known(tag.handle) == nil {
                storage.addAttributes([.foregroundColor: NSColor.systemRed, .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                                       .underlineColor: NSColor.systemRed, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)],
                                      range: NSRange(tag.range, in: view.string))
            }
            storage.endEditing()
        }
    }
}

/// The prompt's text view: copies and cuts its pills as their @tags, and pastes plain text (tags in it become pills).
final class KinoPromptTextView: NSTextView {
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
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
}

/// A named file in the prompt: a rounded pill with its name, in its role's colour.
final class KinoTagAttachment: NSTextAttachment {
    let handle: String
    init(_ file: KinoPromptTag) {
        handle = file.handle
        super.init(data: nil, ofType: nil)
        let text = NSAttributedString(string: file.name, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: file.tint])
        let size = NSSize(width: ceil(text.size().width) + 16, height: 21)
        image = NSImage(size: size, flipped: false) { rect in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 0.5), xRadius: 5, yRadius: 5)
            file.tint.withAlphaComponent(0.16).setFill()
            shape.fill()
            file.tint.withAlphaComponent(0.5).setStroke()
            shape.lineWidth = 1
            shape.stroke()
            text.draw(at: NSPoint(x: 8, y: (rect.height - text.size().height) / 2))
            return true
        }
        bounds = NSRect(x: 0, y: -5, width: size.width, height: size.height)
    }
    required init?(coder: NSCoder) { nil }
}

/// The list typing @ opens under the cursor: the shot's files, with their picture, name and role.
@MainActor
final class KinoTagPicker {
    final class Choices: ObservableObject {
        @Published var files: [KinoPromptTag] = []
        @Published var index = 0
        var pick: (KinoPromptTag) -> Void = { _ in }
    }
    /// Takes the first click, though the list's window never becomes the key one.
    final class Host: NSHostingView<KinoTagList> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
    private let choices = Choices()
    private var panel: NSPanel?
    var shown: Bool { panel?.isVisible == true }
    var chosen: KinoPromptTag? { choices.files.indices.contains(choices.index) ? choices.files[choices.index] : nil }

    func show(_ files: [KinoPromptTag], under caret: NSRect, in window: NSWindow?, pick: @escaping (KinoPromptTag) -> Void) {
        guard let window else { return }
        if choices.files.map(\.handle) != files.map(\.handle) { choices.index = 0 }
        choices.files = files
        choices.pick = pick
        let size = NSSize(width: 250, height: CGFloat(files.count) * KinoTagList.row + 12)
        let panel = self.panel ?? {
            let made = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            made.isOpaque = false
            made.backgroundColor = .clear
            made.hasShadow = true
            made.contentView = Host(rootView: KinoTagList(choices: choices))
            self.panel = made
            return made
        }()
        // Under the @, or above it when there is no room below.
        var origin = NSPoint(x: caret.minX - 10, y: caret.minY - size.height - 4)
        if let screen = window.screen?.visibleFrame, origin.y < screen.minY { origin.y = caret.maxY + 4 }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }
    func move(_ step: Int) {
        guard !choices.files.isEmpty else { return }
        choices.index = (choices.index + step + choices.files.count) % choices.files.count
    }
    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}

struct KinoTagList: View {
    @ObservedObject var choices: KinoTagPicker.Choices
    static let row: CGFloat = 44
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(choices.files.enumerated()), id: \.element.handle) { index, file in
                HStack(spacing: 9) {
                    KinoThumb(url: file.url, width: 28, height: 34, corner: 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Text(file.role).font(.system(size: 10, weight: .medium)).foregroundStyle(Color(nsColor: file.tint))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).frame(height: Self.row)
                .background(index == choices.index ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onHover { if $0 { choices.index = index } }
                .onTapGesture { choices.pick(file) }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }
}

/// The research in docs/kino, which build.sh copies into the app's Resources/Kino: the map is a page (the same file
/// as its web version), the notes on each service are Markdown.
enum KinoResearch: String, CaseIterable, Identifiable {
    case map, kling, higgsfield, forge
    static let asOf = DateComponents(calendar: .current, year: 2026, month: 11, day: 4).date ?? .now
    var id: String { rawValue }
    var title: String {
        switch self {
        case .map: "Kling and Higgsfield side by side"
        case .kling: "Kling"
        case .higgsfield: "Higgsfield"
        case .forge: "KlingDom Forge"
        }
    }
    var summary: String {
        switch self {
        case .map: "What a file can be in a shot, how each names it in the prompt, what each can make, a job's life"
        case .kling: "Models, modes, limits, prompt structure and the API"
        case .higgsfield: "Its models and tools, the API, and every endpoint's fields"
        case .forge: "What the team's generator does well, what to fix, and the four jobs Kino adds"
        }
    }
    var icon: String {
        switch self {
        case .map: "map"
        case .kling, .higgsfield: "doc.text"
        case .forge: "hammer"
        }
    }
    var file: String { self == .map ? "map.html" : rawValue + ".md" }
    var url: URL? { Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "Kino") }
    /// A link between the notes ("kling.md", "higgsfield.md#…"); README.md, the map in words, opens the map.
    init?(link: URL) {
        guard link.scheme == nil || link.scheme == "file" else { return nil }
        let name = (link.path as NSString).lastPathComponent
        if name == "README.md" || name == "map.html" { self = .map; return }
        guard name.hasSuffix(".md"), let doc = KinoResearch(rawValue: String(name.dropLast(3))) else { return nil }
        self = doc
    }
}

/// One research note, read in the app. Links between the notes open here; web links open in the browser.
struct KinoResearchSheet: View {
    @State var doc: KinoResearch
    @State private var blocks: [MarkdownBlock] = []
    @State private var missing = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                PixelKino(pixel: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(doc.title)).font(.system(size: 15, weight: .semibold))
                    Text("docs/kino/\(doc.file) · " + L("As of %@", KinoResearch.asOf.formatted(date: .abbreviated, time: .omitted)))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            Divider()
            if doc == .map, let url = doc.url {
                KinoMapView(url: url)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if missing {
                            Text(md: L("This note is not in this copy of the app. Build it again with **./build.sh**."))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in MarkdownBlockView(block: block) }
                    }
                    .textSelection(.enabled)
                    .padding(.horizontal, 26).padding(.vertical, 20)
                    .frame(maxWidth: 980, alignment: .leading)
                }
                .id(doc)
            }
        }
        .frame(minWidth: 760, idealWidth: 1040, minHeight: 560, idealHeight: 800)
        .environment(\.openURL, OpenURLAction { url in
            if let other = KinoResearch(link: url) { doc = other; return .handled }
            return url.scheme == "https" || url.scheme == "http" ? .systemAction : .discarded
        })
        .task(id: doc) {
            let text = doc.url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            missing = text == nil
            blocks = doc == .map ? [] : MarkdownBlock.parse(text ?? "")
        }
    }
}

/// The map (docs/kino/map.html), the page its web version is published from, so both look the same. Its diagrams are
/// drawn by the page itself; web links open in the browser.
struct KinoMapView: NSViewRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        if let page = try? String(contentsOf: url, encoding: .utf8) {
            view.loadHTMLString(Self.document(page), baseURL: url.deletingLastPathComponent())
        }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    /// The page is written as an artifact's body (the host adds the document around it); here the app does, and the
    /// sheet's own background shows through.
    static func document(_ page: String) -> String {
        "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            + "<style>html,body{margin:0}body{background:transparent!important}</style></head><body>" + page + "</body></html>"
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let link = action.request.url, ["http", "https"].contains(link.scheme) else { return .allow }
            NSWorkspace.shared.open(link)
            return .cancel
        }
    }
}

/// A Markdown file as blocks, as much as the research notes use: headings, paragraphs, lists, tables, code, rules.
/// Bold, code and links inside a block are left to AttributedString.
enum MarkdownBlock {
    struct Item { var indent: Int; var marker: String; var text: String }
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([Item])
    case table(header: [String], rows: [[String]])
    case code(language: String, text: String)
    case rule

    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = [], paragraph: [String] = [], items: [Item] = [], table: [[String]] = []
        var code: (language: String, lines: [String])?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
            if !items.isEmpty { blocks.append(.list(items)); items = [] }
            if !table.isEmpty { blocks.append(.table(header: table[0], rows: Array(table.dropFirst()))); table = [] }
        }
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if var open = code {
                if trimmed.hasPrefix("```") { blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n"))); code = nil }
                else { open.lines.append(line); code = open }
                continue
            }
            let indent = line.prefix { $0 == " " }.count
            if trimmed.hasPrefix("```") { flush(); code = (String(trimmed.dropFirst(3)), []); continue }
            if trimmed.isEmpty { flush(); continue }
            if trimmed.hasPrefix("|") {
                if table.isEmpty { flush() }
                let row = cells(trimmed)
                if !row.allSatisfy({ !$0.isEmpty && $0.allSatisfy { "-: ".contains($0) } }) { table.append(row) }
                continue
            }
            if !table.isEmpty { flush() }
            let hashes = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flush(); blocks.append(.heading(level: hashes, text: String(trimmed.dropFirst(hashes + 1)))); continue
            }
            if trimmed == "---" || trimmed == "***" { flush(); blocks.append(.rule); continue }
            if let item = listItem(trimmed, indent: indent) {
                if !paragraph.isEmpty { flush() }
                items.append(item); continue
            }
            if !items.isEmpty, indent > 0 { items[items.count - 1].text += " " + trimmed; continue }
            if !items.isEmpty { flush() }
            paragraph.append(trimmed)
        }
        if let open = code { blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    /// "| a | b \| c |" → ["a", "b | c"].
    private static func cells(_ row: String) -> [String] {
        var inner = row.replacingOccurrences(of: "\\|", with: "\u{1}")
        if inner.hasPrefix("|") { inner.removeFirst() }
        if inner.hasSuffix("|") { inner.removeLast() }
        return inner.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{1}", with: "|")
        }
    }

    private static func listItem(_ trimmed: String, indent: Int) -> Item? {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return Item(indent: min(3, indent / 2), marker: "•", text: String(trimmed.dropFirst(2)))
        }
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, trimmed.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return Item(indent: min(3, indent / 2), marker: digits + ".", text: String(trimmed.dropFirst(digits.count + 2)))
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text)).font(.system(size: [1: 20, 2: 16, 3: 13.5][level] ?? 12.5, weight: .semibold))
                .padding(.top, level <= 2 ? 14 : 6).fixedSize(horizontal: false, vertical: true)
        case .paragraph(let text):
            Text(inline(text)).font(.system(size: 12)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.marker).font(.system(size: 12)).foregroundStyle(PixelKino.theme)
                        Text(inline(item.text)).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.indent) * 16)
                }
            }
        case .table(let header, let rows):
            MarkdownTableView(header: header, rows: rows)
        case .code(let language, let text):
            if language == "mermaid" {
                Label(L("A diagram: drawn in the web version of the map. The tables carry the same facts."), systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView(.horizontal) {
                    Text(text).font(.system(size: 11, design: .monospaced)).padding(10)
                }
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        case .rule:
            Divider().padding(.vertical, 4)
        }
    }
}

/// A table whose columns are as wide as their longest cell, up to 300 points, wrapping beyond; wide tables scroll sideways.
struct MarkdownTableView: View {
    let header: [String]
    let rows: [[String]]
    private let widths: [CGFloat]
    init(header: [String], rows: [[String]]) {
        self.header = header; self.rows = rows
        widths = header.indices.map { column in
            let longest = ([header] + rows).map { $0.indices.contains(column) ? $0[column].count : 0 }.max() ?? 0
            return min(300, max(50, CGFloat(longest) * 6))
        }
    }
    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    ForEach(header.indices, id: \.self) { column in
                        cell(header[column], column).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(header.indices, id: \.self) { column in
                            cell(row.indices.contains(column) ? row[column] : "", column).font(.system(size: 11))
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
    private func cell(_ text: String, _ column: Int) -> some View {
        Text(inline(text)).frame(width: widths[column], alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}

/// Bold, italics, code and links inside one block of Markdown; the text as it is when it does not parse.
private func inline(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}
