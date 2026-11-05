import AVFoundation
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

/// Kino's page (2026-11-05). The media on the left, empty until you drop or add files: Kino reads nothing by himself. The
/// shots in a strip across the top, in order, each one a place to drop files, with "Every shot" first and "New shot"
/// last; the chosen shot under it, read top to bottom in the order it is made (anything to fix, its files and their roles,
/// the prompt, the settings, what Kino sends); its takes on the right. A role has one colour everywhere: on the file, on
/// its @tag in the prompt and in what is sent; red is for what is wrong, green for ready, Kino's orange for what is chosen.
/// A shot not written yet is grey, not wrong. Accounts open from the top bar. Under 1100 points the takes go under the shot.
struct KinoPage: View {
    @ObservedObject var desk: KinoDesk
    let project: Project
    @State private var reading: KinoResearch?
    @State private var hovered: KinoResearch?
    @State private var showingResearch = false
    @State private var showingAccounts = false
    /// "Every shot" is open in the middle instead of a shot.
    @State private var everyShot = false
    private let accent = PixelKino.theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            GeometryReader { size in
                let wide = size.size.width >= 1100
                let code = desk.selected.flatMap { everyShot || !desk.shots.contains($0) ? nil : $0 }
                HStack(alignment: .top, spacing: 14) {
                    KinoMediaBin(desk: desk, target: code).frame(width: 248)
                    VStack(alignment: .leading, spacing: 16) {
                        KinoShotStrip(desk: desk, everyShot: $everyShot)
                        ThinScrollView {
                            VStack(alignment: .leading, spacing: 26) {
                                if let code {
                                    KinoShotDesk(desk: desk, code: code, openAccounts: { showingAccounts = true }, openEveryShot: { everyShot = true })
                                    if !wide { KinoTakes(desk: desk, code: code, columns: 4) }
                                } else if everyShot {
                                    batchDesk
                                } else {
                                    welcome
                                }
                            }
                            .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 24)
                            .frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    if wide, let code {
                        ThinScrollView { KinoTakes(desk: desk, code: code, columns: 2).padding(14) }
                            .frame(width: 256).frame(maxHeight: .infinity)
                            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                    }
                }
            }
        }
        .onAppear { desk.open(project: project.id) }
        .onChange(of: project.id) { _, id in everyShot = false; desk.open(project: id) }
        // Files moved or deleted in Finder show when you come back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in desk.refresh() }
        .sheet(item: $reading) { KinoResearchSheet(doc: $0) }
    }

    var header: some View {
        let codes = desk.shots
        let takes = codes.map { desk.settings($0).takes }.reduce(0, +)
        return HStack(spacing: 10) {
            PixelKino(pixel: 1.6)
            Text(L("Kino")).font(.system(size: 13, weight: .semibold))
            Text(L("%@ shots · %@ files", codes.count, desk.media.count)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
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

    // MARK: Middle: before any shot, or every shot

    /// What Kino does and how to start, with the research beside it.
    var welcome: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) { start; Spacer(minLength: 0); research.frame(width: 320) }
            VStack(alignment: .leading, spacing: 24) { start; research.frame(maxWidth: 420) }
        }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 14) {
            PixelKino(pixel: 4, previewOnHover: true)
            Text(L("Start with your media")).font(.system(size: 24, weight: .bold, design: .rounded))
            Text(L("Drop pictures, videos and sounds on the left, or onto New shot above."))
                .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Bullets(["Files named **K1**, **K1.1** and **K1.2** go straight into shot K1, each under its own **@tag**",
                     "Drag any file onto a shot to use it there; one picture can be in many shots",
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

    /// What every shot starts from, and the shots that have their own settings.
    var batchDesk: some View {
        let own = desk.shots.filter { desk.shot($0).settings != nil }
        return VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Every shot")).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(L("What each shot starts from. Change a shot and only that shot changes."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            KinoSection(title: L("SAID IN EVERY PROMPT"), note: L("Before each shot's own words")) {
                TextField(L("The product's facts and the look: Easyshape jeans, smooth waistband, metal buckle…"),
                          text: Binding(get: { desk.batch.shared }, set: { desk.setShared($0) }), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(3...8)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            }
            KinoSection(title: L("SETTINGS")) {
                KinoSettingsRow(settings: Binding(get: { desk.batch.settings }, set: { desk.setBatchSettings($0) }))
            }
            if !own.isEmpty {
                KinoSection(title: L("SHOTS WITH THEIR OWN SETTINGS")) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(own, id: \.self) { code in
                            HStack(spacing: 10) {
                                Button { everyShot = false; desk.selected = code } label: {
                                    Text(code).font(.system(size: 12, weight: .bold)).foregroundStyle(accent)
                                }.buttonStyle(.plain)
                                Text(KinoSummary.settings(desk.settings(code))).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Button(L("Use every shot's")) { desk.setSettings(nil, for: code) }.buttonStyle(.link).font(.system(size: 11))
                            }
                            .padding(.vertical, 7)
                            if code != own.last { Divider() }
                        }
                    }
                }
            }
        }
    }
}

/// The media you put in: empty until you drop files or folders here (or press Add). Each shows where it is used; drag one
/// onto a shot, or press its + to put it in the shot that is open.
struct KinoMediaBin: View {
    @ObservedObject var desk: KinoDesk
    /// The shot open in the middle, which a file's + puts it in.
    let target: String?
    @State private var targeted = false
    private let accent = PixelKino.theme
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("MEDIA")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                if !desk.media.isEmpty { Text("\(desk.media.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary) }
                Spacer()
                Button { desk.choose() } label: { Label(L("Add"), systemImage: "plus") }.controlSize(.small)
            }
            if desk.media.isEmpty {
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
                    LazyVGrid(columns: [GridItem(.fixed(KinoMediaTile.width), spacing: 10), GridItem(.fixed(KinoMediaTile.width), spacing: 10)],
                              alignment: .leading, spacing: 12) {
                        ForEach(desk.media) { file in
                            KinoMediaTile(file: file, shots: desk.shots(using: file.id), missing: desk.missing.contains(file.id),
                                          seconds: desk.durations[file.id], target: target,
                                          put: { if let target { desk.add([file.url], into: target) } }, remove: { desk.remove(file.id) })
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
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(accent.opacity(targeted && !desk.media.isEmpty ? 0.9 : 0), lineWidth: 2))
        .dropDestination(for: URL.self) { urls, _ in desk.add(urls); return !urls.isEmpty } isTargeted: { targeted = $0 }
    }
}

/// A file in the media: its picture, its name, and the shots it is in.
struct KinoMediaTile: View {
    let file: KinoFile
    let shots: [String]
    let missing: Bool
    let seconds: Double?
    let target: String?
    let put: () -> Void
    let remove: () -> Void
    static let width: CGFloat = 106
    @State private var hovering = false
    private let accent = PixelKino.theme
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KinoThumb(url: file.url, width: Self.width, height: 128, corner: 8)
                .opacity(missing ? 0.35 : 1)
                .overlay(alignment: .bottomTrailing) { KinoLength(kind: file.kind, seconds: seconds) }
                .overlay(alignment: .topTrailing) {
                    if hovering, let target, !shots.contains(target), !missing {
                        Button(action: put) {
                            Label(target, systemImage: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                                .padding(.horizontal, 7).padding(.vertical, 3).background(accent, in: Capsule())
                        }
                        .buttonStyle(.plain).padding(5).help(L("Put it in %@", target))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if missing {
                        Text(L("Missing")).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(.red, in: Capsule()).padding(5)
                    }
                }
            Text(file.url.lastPathComponent).font(.system(size: 10.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Text(shots.isEmpty ? L("Not in a shot") : L("In %@", shots.joined(separator: ", ")))
                .font(.system(size: 9.5)).foregroundStyle(shots.isEmpty ? Color(nsColor: .tertiaryLabelColor) : accent).lineLimit(1)
        }
        .frame(width: Self.width, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(file.url) }
        .draggable(file.url) { KinoThumb(url: file.url, width: 60, height: 74, corner: 6) }
        .help(file.url.path(percentEncoded: false))
        .contextMenu {
            Button(L("Open")) { NSWorkspace.shared.open(file.url) }
            Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            if let target, !shots.contains(target) { Button(L("Put it in %@", target), action: put) }
            Divider()
            Button(L("Remove from Kino"), action: remove)
        }
    }
}

/// A video's or a sound's length, in the corner of its picture.
struct KinoLength: View {
    let kind: KinoKind
    let seconds: Double?
    var body: some View {
        if kind != .image {
            Label(seconds.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " s" } ?? "",
                  systemImage: kind == .video ? "video.fill" : "waveform")
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2).background(.black.opacity(0.65), in: Capsule()).padding(5)
        }
    }
}

/// The shots in order across the top: "Every shot" first, each shot with its pictures and whether it is ready, then "New
/// shot". Each takes files dropped on it; dropped on "New shot", they make one.
struct KinoShotStrip: View {
    @ObservedObject var desk: KinoDesk
    @Binding var everyShot: Bool
    private let accent = PixelKino.theme
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    KinoChip(chosen: everyShot, dashed: false, drop: nil, select: { everyShot = true }) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 12)).foregroundStyle(accent).frame(width: 28, height: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L("Every shot")).font(.system(size: 12, weight: .semibold))
                            Text(KinoSummary.settings(desk.batch.settings)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 34).padding(.horizontal, 2)
                    ForEach(desk.shots, id: \.self) { code in
                        let plan = desk.plan(code)
                        KinoChip(chosen: !everyShot && desk.selected == code, dashed: false,
                                 drop: { urls in desk.add(urls, into: code); everyShot = false; desk.selected = code },
                                 select: { everyShot = false; desk.selected = code }) {
                            KinoFan(files: desk.files(in: code).filter { desk.role(of: $0, in: code) != .unused })
                            VStack(alignment: .leading, spacing: 2) {
                                Text(code).font(.system(size: 12.5, weight: .bold))
                                KinoState(plan: plan, empty: desk.files(in: code).isEmpty && desk.shot(code).prompt.isEmpty)
                            }
                        }
                        .help(KinoSummary.what(desk, code))
                        .contextMenu {
                            Button(L("Remove %@", code)) { desk.removeShot(code) }
                        }
                        .id(code)
                    }
                    KinoChip(chosen: false, dashed: true, drop: { urls in everyShot = false; desk.newShot(with: urls) },
                             select: { everyShot = false; desk.newShot() }) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).frame(width: 20, height: 38)
                        Text(L("New shot")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .help(L("Press to add an empty shot, or drop files on it"))
                }
                .padding(.vertical, 2).padding(.horizontal, 1)
            }
            .onChange(of: desk.selected) { _, code in if let code { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(code) } } }
        }
    }
}

/// One place in the shot strip: chosen in Kino's colour, ringed while files are dragged over it.
struct KinoChip<Content: View>: View {
    let chosen: Bool
    let dashed: Bool
    let drop: (([URL]) -> Void)?
    let select: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var targeted = false
    private let accent = PixelKino.theme
    var body: some View {
        let chip = HStack(spacing: 8) { content() }
            .padding(.leading, 8).padding(.trailing, 12).padding(.vertical, 6)
            .background(chosen ? accent.opacity(0.16) : dashed ? .clear : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if dashed {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(targeted ? accent : .white.opacity(0.18), style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: [5, 3]))
                } else {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(targeted ? accent : chosen ? accent.opacity(0.4) : .clear, lineWidth: targeted ? 2 : 1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: select)
        if let drop {
            chip.dropDestination(for: URL.self) { urls, _ in drop(urls); return !urls.isEmpty } isTargeted: { targeted = $0 }
        } else {
            chip
        }
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
        .font(.system(size: 10, weight: .medium)).labelStyle(KinoTightLabel())
    }
}

struct KinoTightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon.font(.system(size: 9)); configuration.title }
    }
}

/// A part of the middle column: its heading, a note or control on the right, then what it holds. No box: the parts are
/// set apart by space, so the few things that are boxed (the prompt, a problem) stand out.
struct KinoSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.trailing = trailing; self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

/// The words the shot list and the shot's title use: what a shot does, said by its roles, and its settings in one line.
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
}

/// Up to three of a shot's pictures, fanned like prints on a desk, in the shot list.
struct KinoFan: View {
    let files: [KinoFile]
    var body: some View {
        let shown = Array(files.prefix(3))
        ZStack(alignment: .leading) {
            if shown.isEmpty {
                RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 28, height: 38)
            }
            ForEach(Array(shown.enumerated().reversed()), id: \.element.id) { index, file in
                KinoThumb(url: file.url, width: 28, height: 38, corner: 5)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.5), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 1.5, x: 1)
                    .offset(x: CGFloat(index) * 9)
            }
        }
        .frame(width: 46, alignment: .leading)
    }
}

/// The chosen shot, top to bottom as it is made: what it is and whether it can run, anything to fix, its files and their
/// roles, the prompt, the settings, and what Kino would send.
struct KinoShotDesk: View {
    @ObservedObject var desk: KinoDesk
    let code: String
    let openAccounts: () -> Void
    let openEveryShot: () -> Void
    @State private var insert: String?
    @State private var showingSent = false
    private let accent = PixelKino.theme

    var body: some View {
        let plan = desk.plan(code)
        let files = desk.files(in: code)
        let model = KinoModel.named(desk.settings(code).model)
        VStack(alignment: .leading, spacing: 26) {
            title(plan, files, model)
            if !KinoSummary.issues(plan).isEmpty { problems(KinoSummary.issues(plan)) }
            KinoSection(title: L("IN THIS SHOT"), note: files.isEmpty ? "" : L("Press a tag to put it in the prompt")) {
                FlowLayout(spacing: 14) {
                    ForEach(files) { file in
                        KinoFileTile(file: file, role: desk.role(of: file, in: code), seconds: desk.durations[file.id],
                                     sentAs: plan.inputs.first { $0.handle == file.handle }?.tag,
                                     choose: { desk.setRole($0, of: file, in: code) }, tag: { insert = "@" + file.handle },
                                     takeOut: { desk.takeOut(file, of: code) })
                    }
                    KinoDropTile(code: code, empty: files.isEmpty, drop: { desk.add($0, into: code) }, choose: { desk.choose(into: code) })
                }
            }
            KinoSection(title: L("PROMPT"), trailing: { count(plan, model) }) { prompt(plan, files) }
            KinoSection(title: L("SETTINGS"), trailing: {
                if desk.shot(code).settings != nil {
                    Button(L("Use every shot's settings")) { desk.setSettings(nil, for: code) }.buttonStyle(.link).font(.system(size: 10.5))
                } else {
                    Text(L("As every shot")).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }) {
                KinoSettingsRow(settings: Binding(get: { desk.settings(code) }, set: { desk.setSettings($0, for: code) }),
                                base: desk.shot(code).settings == nil ? nil : desk.batch.settings,
                                lengthFrom: plan.seconds == nil ? files.first { desk.role(of: $0, in: code) == .edit }?.handle : nil)
            }
            sent(plan)
        }
    }

    func title(_ plan: KinoPlan, _ files: [KinoFile], _ model: KinoModel) -> some View {
        let settings = desk.settings(code)
        let used = files.filter { desk.role(of: $0, in: code) != .unused }
        let counts = [(KinoKind.image, "%@ pictures", "1 picture"), (.video, "%@ videos", "1 video"), (.audio, "%@ sounds", "1 sound")]
            .compactMap { kind, many, one -> String? in
                let count = used.filter { $0.kind == kind }.count
                return count == 0 ? nil : count == 1 ? L(one) : L(many, count)
            }
        let length = plan.seconds.map { "\($0) s" } ?? files.first { desk.role(of: $0, in: code) == .edit }.map { L("as long as @%@", $0.handle) }
        let line = [L("%@ through %@", model.name, model.service.rawValue), counts.isEmpty ? L("Text only") : counts.joined(separator: " + "),
                    length, settings.takes == 1 ? L("1 take") : L("%@ takes", settings.takes)].compactMap { $0 }
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(code).font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(KinoSummary.what(desk, code)).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(line.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Button {} label: {
                    Label(settings.takes > 1 ? L("Run %@ · %@ takes", code, settings.takes) : L("Run %@", code), systemImage: "play.fill")
                        .padding(.horizontal, 4)
                }
                .controlSize(.large).disabled(true)
                if desk.missingKey([code]) {
                    Button(desk.blocker([code]), action: openAccounts).buttonStyle(.link).font(.system(size: 10.5))
                } else {
                    Text(KinoSummary.issues(plan).isEmpty && KinoSummary.unwritten(plan) ? L("Write what happens in the shot first") : desk.blocker([code]))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// What stops the shot, boxed in red above everything else.
    func problems(_ problems: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(problems.count == 1 ? L("1 TO FIX") : L("%@ TO FIX", problems.count))
                .font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.red)
            ForEach(problems, id: \.self) { problem in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(.red)
                    Text(md: problem).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.red.opacity(0.3)))
    }

    func count(_ plan: KinoPlan, _ model: KinoModel) -> some View {
        Group {
            if let limit = model.promptLimit {
                Text(L("%@ of %@ characters sent", plan.prompt.count.formatted(), limit.formatted()))
                    .foregroundStyle(plan.prompt.count > limit ? Color.red : Color(nsColor: .tertiaryLabelColor))
            }
        }
        .font(.system(size: 10.5).monospacedDigit())
    }

    func prompt(_ plan: KinoPlan, _ files: [KinoFile]) -> some View {
        let text = desk.shot(code).prompt
        var tints: [String: NSColor] = [:]
        for file in files where plan.inputs.contains(where: { $0.handle == file.handle }) { tints[file.handle.lowercased()] = desk.role(of: file, in: code).tint }
        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                KinoPromptView(text: Binding(get: { desk.shot(code).prompt }, set: { desk.setPrompt($0, for: code) }), tints: tints, insert: $insert)
                if text.isEmpty {
                    Text(md: L("What happens in the shot. Press a file's **@tag** to name it: \"@%@ is held up to the camera…\"", files.first?.handle ?? code))
                        .font(.system(size: 13)).foregroundStyle(.tertiary).padding(.horizontal, 13).padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 112)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.06)))
            Button(action: openEveryShot) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "text.badge.plus").font(.system(size: 10))
                    Text(L("Every shot adds")).font(.system(size: 10.5, weight: .semibold))
                    Text(desk.batch.shared.isEmpty ? L("nothing yet") : desk.batch.shared).font(.system(size: 10.5)).lineLimit(1)
                }
                .foregroundStyle(.secondary).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(L("Change what every shot's prompt says"))
        }
    }

    /// Where the shot goes and what Kino changes on the way; the request itself, as the service reads it, on demand.
    func sent(_ plan: KinoPlan) -> some View {
        KinoSection(title: L("WHAT KINO SENDS"), trailing: {
            Text(plan.endpoint).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).textSelection(.enabled).lineLimit(1)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.notes, id: \.self) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: "info.circle").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(md: note).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                DisclosureGroup(isExpanded: $showingSent) {
                    VStack(alignment: .leading, spacing: 10) {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                            ForEach(plan.inputs, id: \.handle) { input in
                                let role = desk.files(in: code).first { $0.handle == input.handle }.map { desk.role(of: $0, in: code) } ?? .unused
                                GridRow {
                                    Text("@" + input.handle).font(.system(size: 11, weight: .semibold)).foregroundStyle(role.color)
                                    Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                                    Text(input.tag).font(.system(size: 11))
                                    Text(input.slot).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Text(plan.prompt.isEmpty ? " " : plan.prompt).font(.system(size: 11, design: .monospaced)).lineSpacing(2).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.top, 8)
                } label: {
                    Text(L("The request, as the service reads it")).font(.system(size: 11.5, weight: .medium))
                }
            }
        }
    }
}

/// A file in its shot: its picture framed in its role's colour, its tag (press it to put it in the prompt), its role, and
/// what the service will call it. Drag it onto another shot to use it there too, or into Premiere.
struct KinoFileTile: View {
    let file: KinoFile
    let role: KinoRole
    let seconds: Double?
    let sentAs: String?
    let choose: (KinoRole) -> Void
    let tag: () -> Void
    let takeOut: () -> Void
    static let width: CGFloat = 116
    var body: some View {
        let off = role == .unused
        VStack(alignment: .leading, spacing: 6) {
            KinoThumb(url: file.url, width: Self.width, height: 146, corner: 9)
                .opacity(off ? 0.3 : 1)
                .overlay {
                    if off {
                        RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    } else {
                        RoundedRectangle(cornerRadius: 9).strokeBorder(role.color, lineWidth: 2)
                    }
                }
                .overlay(alignment: .bottomTrailing) { KinoLength(kind: file.kind, seconds: seconds) }
                .onTapGesture(count: 2) { NSWorkspace.shared.open(file.url) }
                .draggable(file.url) { KinoThumb(url: file.url, width: 60, height: 74, corner: 6) }
                .help(file.url.lastPathComponent)
            Button(action: tag) {
                HStack(spacing: 3) {
                    Text("@" + file.handle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Image(systemName: "plus").font(.system(size: 8, weight: .bold)).opacity(0.6)
                }
                .foregroundStyle(off ? Color.secondary : role.color)
            }.buttonStyle(.plain).help(L("Put @%@ in the prompt where the cursor is", file.handle))
            Menu {
                ForEach(KinoRole.choices(file.kind)) { option in
                    Button { choose(option) } label: {
                        if option == role { Label(L(option.title), systemImage: "checkmark") } else { Text(L(option.title)) }
                    }
                }
            } label: {
                Label(L(role.title), systemImage: role.icon).font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 8).frame(width: Self.width, height: 24, alignment: .leading)
            .background(role.color.opacity(off ? 0.08 : 0.16), in: Capsule())
            .help(L(role.detail))
            Text(sentAs.map { L("Sent as %@", $0) } ?? L("Not sent")).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(width: Self.width, alignment: .leading)
        .contextMenu {
            Button(L("Open")) { NSWorkspace.shared.open(file.url) }
            Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            Divider()
            Button(L("Take out of %@", file.shot ?? ""), action: takeOut)
        }
    }
}

/// The last place in a shot's files: drop files here (from the media or Finder), or press it to choose some.
struct KinoDropTile: View {
    let code: String
    let empty: Bool
    let drop: ([URL]) -> Void
    let choose: () -> Void
    @State private var targeted = false
    private let accent = PixelKino.theme
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 18, weight: .light))
            Text(empty ? L("Drag files here from the media") : L("Drop more here")).font(.system(size: 10.5, weight: .medium))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(targeted ? accent : .secondary)
        .padding(10)
        .frame(width: KinoFileTile.width, height: 146)
        .background(RoundedRectangle(cornerRadius: 9).fill(targeted ? accent.opacity(0.1) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(targeted ? accent : .white.opacity(0.16), style: StrokeStyle(lineWidth: targeted ? 2 : 1.2, dash: [5, 4])))
        .contentShape(Rectangle())
        .onTapGesture(perform: choose)
        .dropDestination(for: URL.self) { urls, _ in drop(urls); return !urls.isEmpty } isTargeted: { targeted = $0 }
        .help(L("Drop pictures, videos or sounds into %@, or press to choose them", code))
    }
}

/// A shot's takes: a frame for each the run makes, in the shot's shape. Filled once sending is built.
struct KinoTakes: View {
    @ObservedObject var desk: KinoDesk
    let code: String
    let columns: Int
    var body: some View {
        let settings = desk.settings(code)
        let ratio: CGFloat = switch settings.aspect { case "16:9": 16 / 9; case "1:1": 1; case "4:3": 4 / 3; case "3:4": 3 / 4; default: 9 / 16 }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("TAKES")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Text(code).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.tertiary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(maximum: 120), spacing: 10, alignment: .top), count: columns), alignment: .leading, spacing: 12) {
                ForEach(0..<settings.takes, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Color.clear.aspectRatio(ratio, contentMode: .fit)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                                    .overlay(Image(systemName: "film").font(.system(size: 15)).foregroundStyle(.quaternary))
                            }
                        Text(L("Take %@", index + 1)).font(.system(size: 10.5, weight: .medium))
                        Text(L("Not made yet")).font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    }
                }
            }
            Text(L("Each take shows here as soon as it is made, to watch and drag into Premiere. Higgsfield deletes its own copy after 7 days; Kino keeps one."))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The model and the settings it takes: only what the chosen model has, so the form follows the model. With `base`, the
/// settings every shot has, what this shot changes is ringed in Kino's colour.
struct KinoSettingsRow: View {
    @Binding var settings: KinoSettings
    var base: KinoSettings? = nil
    /// The video a shot edits, whose length the take has: no length to pick then.
    var lengthFrom: String? = nil
    private let accent = PixelKino.theme
    var body: some View {
        let model = KinoModel.named(settings.model)
        let current = settings.fitted(to: model)
        let usual = base?.fitted(to: model)
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                pill(model.name, icon: "sparkles", changed: base.map { $0.model != settings.model } ?? false) {
                    ForEach([KinoModel.Service.higgsfield, .kling], id: \.self) { service in
                        Section(L("Through %@", service.rawValue)) {
                            ForEach(KinoModel.all.filter { $0.service == service }) { option in
                                Button { settings = current.fitted(to: option) } label: {
                                    if option.id == model.id { Label(option.name, systemImage: "checkmark") } else { Text(option.name) }
                                }
                            }
                        }
                    }
                }
                if let lengthFrom {
                    plain(L("As long as @%@", lengthFrom), icon: "timer")
                } else if let range = model.seconds {
                    pill(current.seconds.map { "\($0) s" } ?? L("Auto (%@ s)", model.defaultSeconds), icon: "timer", changed: usual.map { $0.seconds != current.seconds } ?? false) {
                        Button(L("Auto (%@ s)", model.defaultSeconds)) { settings = with(current) { $0.seconds = nil } }
                        ForEach(Array(range), id: \.self) { value in Button("\(value) s") { settings = with(current) { $0.seconds = value } } }
                    }
                }
                if !model.aspects.isEmpty {
                    pill(aspect(current.aspect), icon: "aspectratio", changed: usual.map { $0.aspect != current.aspect } ?? false) {
                        ForEach(model.aspects, id: \.self) { value in Button(aspect(value)) { settings = with(current) { $0.aspect = value } } }
                    }
                }
                if !model.qualities.isEmpty {
                    pill(model.qualities.first { $0.id == current.quality }?.title ?? "", icon: "dial.medium", changed: usual.map { $0.quality != current.quality } ?? false) {
                        ForEach(model.qualities, id: \.id) { option in Button(option.title) { settings = with(current) { $0.quality = option.id } } }
                    }
                }
                if model.sound == true {
                    Button { settings = with(current) { $0.sound.toggle() } } label: {
                        Label(L(current.sound ? "Sound on" : "Sound off"), systemImage: current.sound ? "speaker.wave.2.fill" : "speaker.slash")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(.white.opacity(0.07), in: Capsule())
                            .overlay(Capsule().strokeBorder(accent.opacity(usual.map { $0.sound != current.sound } ?? false ? 0.8 : 0)))
                    }.buttonStyle(.plain)
                } else if model.id == "kling-4.0" {
                    plain(L("Always makes sound"), icon: "speaker.wave.2")
                }
                Picker("", selection: Binding(get: { current.takes }, set: { value in settings = with(current) { $0.takes = value } })) {
                    ForEach(1...4, id: \.self) { Text("×\($0)").tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140).help(L("Takes a run makes"))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(accent.opacity(usual.map { $0.takes != current.takes } ?? false ? 0.8 : 0)))
            }
            Text(L(model.note)).font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
    }

    func with(_ settings: KinoSettings, _ change: (inout KinoSettings) -> Void) -> KinoSettings {
        var settings = settings
        change(&settings)
        return settings
    }

    func aspect(_ value: String) -> String { value == "adaptive" ? L("Follows the files") : value }

    func pill<Items: View>(_ title: String, icon: String, changed: Bool, @ViewBuilder items: () -> Items) -> some View {
        Menu { items() } label: { Label(title, systemImage: icon).font(.system(size: 11, weight: .medium)) }
            .menuStyle(.borderlessButton).fixedSize()
            .padding(.horizontal, 10).frame(height: 26)
            .background(changed ? accent.opacity(0.14) : .white.opacity(0.07), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(changed ? 0.8 : 0)))
            .help(changed ? L("Changed for this shot") : "")
    }

    func plain(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).frame(height: 26)
            .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
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
struct KinoPromptView: NSViewRepresentable {
    @Binding var text: String
    /// The role's colour of each file sent, by its tag in lower case.
    let tints: [String: NSColor]
    @Binding var insert: String?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = OverlayScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = NSTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 13)
        editor.textColor = .labelColor
        editor.insertionPointColor = NSColor(PixelKino.theme)
        editor.textContainerInset = NSSize(width: 8, height: 12)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let changed = context.coordinator.parent.tints != tints
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text; context.coordinator.color(view) } else if changed { context.coordinator.color(view) }
        if let tag = insert {
            DispatchQueue.main.async { insert = nil }
            let at = view.selectedRange()
            // A space either side unless there is one already, so the tag never joins a word.
            let before = at.location > 0 && !(view.string as NSString).substring(with: NSRange(location: at.location - 1, length: 1)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            view.window?.makeFirstResponder(view)
            view.insertText((before ? " " : "") + tag + " ", replacementRange: at)
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: KinoPromptView
        init(_ parent: KinoPromptView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            color(view)
        }
        func color(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let all = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: all)
            storage.removeAttribute(.underlineStyle, range: all)
            let lines = NSMutableParagraphStyle()
            lines.lineSpacing = 5
            storage.addAttributes([.paragraphStyle: lines, .foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 13)], range: all)
            for tag in KinoPrompt.tags(in: view.string) {
                let range = NSRange(tag.range, in: view.string)
                if let tint = parent.tints[tag.handle.lowercased()] {
                    storage.addAttributes([.foregroundColor: tint, .backgroundColor: tint.withAlphaComponent(0.16),
                                           .font: NSFont.systemFont(ofSize: 13, weight: .semibold)], range: range)
                } else {
                    storage.addAttributes([.foregroundColor: NSColor.systemRed, .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                                           .underlineColor: NSColor.systemRed, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)], range: range)
                }
            }
            storage.endEditing()
        }
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
