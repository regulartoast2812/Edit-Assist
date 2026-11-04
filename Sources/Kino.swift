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

/// Kino's page (redrawn 2026-11-04: the first one read as one long form). The batch's shots down the left, one line each
/// with their pictures, what the shot does and whether it is ready; the chosen shot in the middle, read top to bottom in
/// the order it is made (its files and their roles, the prompt, the settings, what Kino sends), with anything to fix
/// first; its takes on the right. A role has one colour everywhere: on the file, on its @tag in the prompt and in what is
/// sent; Kino's orange is only for what is chosen and for running. "Every shot", at the top of the list, holds what each
/// shot starts from. Accounts open from the top bar. Under 1100 points the takes go under the shot. Before a folder:
/// Kino, the research beside him, and choosing the batch.
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
        Group {
            if desk.folder == nil { start } else { workspace }
        }
        .onAppear { desk.open(project: project.id) }
        .onChange(of: project.id) { _, id in everyShot = false; desk.open(project: id) }
        // Files renamed or added in Finder show when you come back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in desk.refresh() }
        .sheet(item: $reading) { KinoResearchSheet(doc: $0) }
    }

    // MARK: Before a folder

    var start: some View {
        ThinScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Side by side when the page is wide enough, the research under him otherwise.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) { intro; Spacer(minLength: 0); research.frame(width: 320) }
                    VStack(alignment: .leading, spacing: 18) { intro; research.frame(maxWidth: 420) }
                }
                section(L("THE BATCH")) {
                    Bullets(["Pick the **folder** with this batch's pictures and videos",
                             "Name the files by **shot**: **K1**, **K1.1** and **K1.2** all go into shot K1's prompt",
                             "Words after the code are a label: **K9 ref** is a file of shot K9"], numbered: true, size: 11)
                    Button { desk.chooseFolder() } label: { Label(L("Choose the batch folder…"), systemImage: "folder") }
                        .buttonStyle(.borderedProminent).tint(accent)
                }
                section(L("ACCOUNTS")) { KinoAccounts(desk: desk) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 16) {
            PixelKino(pixel: 4, previewOnHover: true)
            VStack(alignment: .leading, spacing: 8) {
                Text(md: L("Your AI video helper")).font(.system(size: 13, weight: .semibold))
                Bullets(["Makes **AI videos** with **Kling** and **Higgsfield**",
                         "Connects your **media** (images, clips) to the **prompts**",
                         "Works to the look in **Don's** brief"], size: 11)
            }
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

    // MARK: The batch

    var workspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            GeometryReader { size in
                let wide = size.size.width >= 1100
                HStack(alignment: .top, spacing: 14) {
                    rail.frame(width: 236)
                    ThinScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            if let code = desk.selected, !everyShot, desk.shots.contains(code) {
                                KinoShotDesk(desk: desk, code: code, openAccounts: { showingAccounts = true }, openEveryShot: { everyShot = true })
                                if !wide { KinoTakes(desk: desk, code: code, columns: 4) }
                            } else if desk.shots.isEmpty && !everyShot {
                                empty
                            } else {
                                batchDesk
                            }
                        }
                        .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 24)
                        .frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if wide, let code = desk.selected, !everyShot, desk.shots.contains(code) {
                        ThinScrollView { KinoTakes(desk: desk, code: code, columns: 2).padding(14) }
                            .frame(width: 256).frame(maxHeight: .infinity)
                            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                    }
                }
            }
        }
    }

    var header: some View {
        let codes = desk.shots
        let takes = codes.map { desk.settings($0).takes }.reduce(0, +)
        return HStack(spacing: 10) {
            PixelKino(pixel: 1.6)
            Button { desk.chooseFolder() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(accent)
                    Text(desk.folder?.lastPathComponent ?? "").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.white.opacity(0.06), in: Capsule())
            }.buttonStyle(.plain).help(L("Choose another batch folder"))
            Text(L("%@ shots · %@ pictures · %@ videos", codes.count, desk.files.filter { $0.kind == .image }.count, desk.files.filter { $0.kind == .video }.count))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Button { desk.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Read the folder again"))
            Spacer(minLength: 8)
            Button { showingResearch.toggle() } label: { Label(L("Research"), systemImage: "books.vertical") }
                .popover(isPresented: $showingResearch, arrowEdge: .bottom) { research.padding(6).frame(width: 340) }
            Button { showingAccounts.toggle() } label: {
                Label(L("Accounts"), systemImage: "key")
                    .overlay(alignment: .topLeading) {
                        if desk.missingKey(codes) { Circle().fill(.red).frame(width: 6, height: 6).offset(x: -2, y: -1) }
                    }
            }
            .help(desk.missingKey(codes) ? L("A key these shots need is missing") : L("Higgsfield and Kling keys"))
            .popover(isPresented: $showingAccounts, arrowEdge: .bottom) { KinoAccounts(desk: desk).padding(16).frame(width: 300) }
            if !codes.isEmpty {
                Button {} label: { Label(L("Run all · %@ takes", takes), systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).tint(accent).disabled(true).help(desk.blocker(codes))
            }
        }
    }

    // MARK: Left: the shots

    var rail: some View {
        let broken = desk.shots.filter { !desk.plan($0).problems.isEmpty }.count
        return VStack(alignment: .leading, spacing: 0) {
            railRow(chosen: everyShot || desk.shots.isEmpty, action: { everyShot = true }) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 13)).foregroundStyle(accent)
                    .frame(width: 36, height: 36).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Every shot")).font(.system(size: 12.5, weight: .semibold))
                    Text(KinoSummary.settings(desk.batch.settings)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                heading(L("SHOTS"))
                Text("\(desk.shots.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                Spacer()
                if broken > 0 {
                    Text(broken == 1 ? L("1 to fix") : L("%@ to fix", broken)).font(.system(size: 10, weight: .medium)).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 6)
            ThinScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(desk.shots, id: \.self) { code in
                        let problems = desk.plan(code).problems.count
                        railRow(chosen: !everyShot && desk.selected == code, action: { everyShot = false; desk.selected = code }) {
                            KinoFan(files: desk.files(in: code).filter { desk.role(of: $0, in: code) != .unused })
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(code).font(.system(size: 12.5, weight: .bold))
                                    Spacer(minLength: 4)
                                    if problems > 0 {
                                        Text("\(problems)").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
                                            .frame(minWidth: 15).padding(.vertical, 1).background(.red, in: Capsule())
                                            .help(problems == 1 ? L("1 to fix") : L("%@ to fix", problems))
                                    } else {
                                        Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(.green).help(L("Ready"))
                                    }
                                }
                                Text(KinoSummary.what(desk, code)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    if !desk.loose.isEmpty { loose }
                }
            }
        }
        .padding(6)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
    }

    func railRow<Content: View>(chosen: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            HStack(spacing: 10) { content() }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(chosen ? accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(chosen ? accent.opacity(0.35) : .clear))
        }.buttonStyle(.plain)
    }

    var loose: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                heading(L("NOT IN A SHOT"))
                Text("\(desk.loose.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            Text(md: L("Their names start with no shot code. Rename one **K4.2** to put it in shot K4."))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 4)], alignment: .leading, spacing: 4) {
                ForEach(desk.loose) { file in
                    KinoThumb(url: file.url, width: 40, height: 50).opacity(0.55).help(file.url.lastPathComponent)
                        .contextMenu { Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } }
                }
            }
        }
        .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 8)
    }

    // MARK: Middle: every shot, or none yet

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

    var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("No shots yet")).font(.system(size: 24, weight: .bold, design: .rounded))
            Text(md: L("Name the files in **%@** by shot and they show here:", desk.folder?.lastPathComponent ?? ""))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Bullets(["**K1**, **K1.1** and **K1.2** all go into shot K1's prompt",
                     "Words after the code are a label: **K9 ref** is a file of shot K9"], size: 11)
            Button { NSWorkspace.shared.open(desk.folder!) } label: { Label(L("Open the folder"), systemImage: "folder") }
                .padding(.top, 4)
        }
    }

    func heading(_ title: String) -> some View {
        Text(md: title).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
    }

    func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(title)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(12).frame(maxWidth: 640, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        }
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
            if !plan.problems.isEmpty { problems(plan) }
            KinoSection(title: L("IN THIS SHOT"), note: L("Press a tag to put it in the prompt")) {
                FlowLayout(spacing: 14) {
                    ForEach(files) { file in
                        KinoFileTile(file: file, role: desk.role(of: file, in: code), seconds: desk.durations[file.id],
                                     sentAs: plan.inputs.first { $0.handle == file.handle }?.tag,
                                     choose: { desk.setRole($0, of: file, in: code) }, tag: { insert = "@" + file.handle })
                    }
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
                .buttonStyle(.borderedProminent).tint(accent).controlSize(.large).disabled(true)
                if desk.missingKey([code]) {
                    Button(desk.blocker([code]), action: openAccounts).buttonStyle(.link).font(.system(size: 10.5))
                } else {
                    Text(desk.blocker([code])).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// What stops the shot, boxed in red above everything else.
    func problems(_ plan: KinoPlan) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(plan.problems.count == 1 ? L("1 TO FIX") : L("%@ TO FIX", plan.problems.count))
                .font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.red)
            ForEach(plan.problems, id: \.self) { problem in
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
/// what the service will call it.
struct KinoFileTile: View {
    let file: KinoFile
    let role: KinoRole
    let seconds: Double?
    let sentAs: String?
    let choose: (KinoRole) -> Void
    let tag: () -> Void
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
                .overlay(alignment: .bottomTrailing) {
                    if file.kind != .image {
                        Label(seconds.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " s" } ?? "",
                              systemImage: file.kind == .video ? "video.fill" : "waveform")
                            .font(.system(size: 9.5, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(.black.opacity(0.65), in: Capsule()).padding(6)
                    }
                }
                .onTapGesture(count: 2) { NSWorkspace.shared.open(file.url) }
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
            .menuStyle(.borderlessButton).fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(role.color.opacity(off ? 0.08 : 0.16), in: Capsule())
            .help(L(role.detail))
            Text(sentAs.map { L("Sent as %@", $0) } ?? L("Not sent")).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(width: Self.width, alignment: .leading)
        .contextMenu {
            Button(L("Open")) { NSWorkspace.shared.open(file.url) }
            Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        }
    }
}

/// A shot's takes: a frame for each the run makes, in the shot's shape, filled by the takes already in the batch's Kino
/// folder; the batch's other takes below.
struct KinoTakes: View {
    @ObservedObject var desk: KinoDesk
    let code: String
    let columns: Int
    var body: some View {
        let settings = desk.settings(code)
        let made = desk.outputs.filter { $0.deletingPathExtension().lastPathComponent.hasPrefix(code + " ") }
        let others = desk.outputs.filter { !made.contains($0) }
        let ratio: CGFloat = switch settings.aspect { case "16:9": 16 / 9; case "1:1": 1; case "4:3": 4 / 3; case "3:4": 3 / 4; default: 9 / 16 }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("TAKES")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Text(code).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.tertiary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(maximum: 120), spacing: 10, alignment: .top), count: columns), alignment: .leading, spacing: 12) {
                ForEach(0..<max(settings.takes, made.count), id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Color.clear.aspectRatio(ratio, contentMode: .fit)
                            .overlay {
                                if index < made.count {
                                    GeometryReader { box in KinoThumb(url: made[index], width: box.size.width, height: box.size.height, corner: 8) }
                                } else {
                                    RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                                        .overlay(Image(systemName: "film").font(.system(size: 15)).foregroundStyle(.quaternary))
                                }
                            }
                            .onTapGesture(count: 2) { if index < made.count { NSWorkspace.shared.open(made[index]) } }
                            .onDrag { index < made.count ? NSItemProvider(contentsOf: made[index]) ?? NSItemProvider() : NSItemProvider() }
                        Text(L("Take %@", index + 1)).font(.system(size: 10.5, weight: .medium))
                        Text(index < made.count ? L("Drag into Premiere") : L("Not made yet")).font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    }
                }
            }
            Text(md: L("Each take is saved in **%@ › Kino** as soon as it is made. Higgsfield deletes its own copy after 7 days.", desk.folder?.lastPathComponent ?? ""))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !others.isEmpty {
                Divider()
                Text(L("OTHER TAKES IN THIS BATCH")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                ForEach(others, id: \.self) { url in
                    HStack(spacing: 8) {
                        KinoThumb(url: url, width: 30, height: 40, corner: 5)
                        Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 11)).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
                    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                    .contextMenu { Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                }
            }
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

/// A file's picture, from Quick Look (a video's shows a frame), kept while the app runs.
struct KinoThumb: View {
    let url: URL
    let width: CGFloat
    let height: CGFloat
    var corner: CGFloat = 6
    @State private var image: NSImage?
    private static let cache = NSCache<NSString, NSImage>()
    var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.06))
            if let image { Image(nsImage: image).resizable().scaledToFill() }
        }
        .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: corner))
        .task(id: url) { image = await load() }
    }
    private func load() async -> NSImage? {
        let key = "\(url.path)|\(Int(max(width, height)))" as NSString
        if let hit = Self.cache.object(forKey: key) { return hit }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: max(width, height), height: max(width, height)),
                                                   scale: 2, representationTypes: .thumbnail)
        guard let made = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        Self.cache.setObject(made.nsImage, forKey: key)
        return made.nsImage
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
