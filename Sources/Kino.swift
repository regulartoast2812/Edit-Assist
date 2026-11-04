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

/// Kino's page (2026-11-04), laid out like KlingDom Forge, the team's generator, with what it lacked (docs/kino/forge.md):
/// the batch's media on the left, grouped by shot code; the shots in the middle, each with its files and their roles,
/// the prompt with @tags, the settings the chosen model takes and what Kino would send to it; the takes and the two
/// accounts on the right. Under 1180 points the media column goes (each shot shows its own files); under 820 the right
/// column goes under the shots. Before a folder: Kino, the research beside him, and choosing the batch.
struct KinoPage: View {
    @ObservedObject var desk: KinoDesk
    let project: Project
    @State private var reading: KinoResearch?
    @State private var hovered: KinoResearch?
    @State private var showingResearch = false
    private let accent = PixelKino.theme

    var body: some View {
        Group {
            if desk.folder == nil { start } else { workspace }
        }
        .onAppear { desk.open(project: project.id) }
        .onChange(of: project.id) { _, id in desk.open(project: id) }
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
                        .buttonStyle(.borderedProminent)
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
        VStack(alignment: .leading, spacing: 12) {
            header
            GeometryReader { size in
                let width = size.size.width
                HStack(alignment: .top, spacing: 12) {
                    if width >= 1180 { panel { media }.frame(width: 230) }
                    shots(sideBelow: width < 820).frame(maxWidth: .infinity, maxHeight: .infinity)
                    if width >= 820 { panel { ThinScrollView { side } }.frame(width: 270) }
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
                    Text(desk.folder?.lastPathComponent ?? "").font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(L("Change…")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.white.opacity(0.06), in: Capsule())
            }.buttonStyle(.plain).help(desk.folder?.path(percentEncoded: false) ?? "")
            Text(L("%@ shots · %@ pictures · %@ videos", codes.count, desk.files.filter { $0.kind == .image }.count, desk.files.filter { $0.kind == .video }.count))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Button { desk.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Read the folder again"))
            Spacer(minLength: 8)
            Button { showingResearch.toggle() } label: { Label(L("Research"), systemImage: "books.vertical") }
                .popover(isPresented: $showingResearch, arrowEdge: .bottom) { research.padding(6).frame(width: 340) }
            if !codes.isEmpty {
                Text(desk.blocker(codes)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Button {} label: { Label(L("Run all · %@ takes", takes), systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).disabled(true)
            }
        }
    }

    var media: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(L("MEDIA"))
            ThinScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(desk.shots, id: \.self) { code in
                        let chosen = desk.selected == code
                        Button { desk.selected = code } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(code).font(.system(size: 11, weight: .bold)).foregroundStyle(chosen ? accent : .primary)
                                    Spacer()
                                    Text("\(desk.files(in: code).count)").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 4)], alignment: .leading, spacing: 4) {
                                    ForEach(desk.files(in: code)) { file in
                                        KinoThumb(url: file.url, width: 46, height: 46)
                                            .opacity(desk.role(of: file, in: code) == .unused ? 0.35 : 1)
                                            .help("@" + file.handle)
                                    }
                                }
                            }
                            .padding(6).contentShape(Rectangle())
                            .background(chosen ? accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                    if !desk.loose.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L("Not in a shot")).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                            Text(md: L("Their names start with no shot code. Rename one **K4.2** to put it in shot K4."))
                                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 4)], alignment: .leading, spacing: 4) {
                                ForEach(desk.loose) { KinoThumb(url: $0.url, width: 46, height: 46).opacity(0.6).help($0.url.lastPathComponent) }
                            }
                        }.padding(6)
                    }
                }
            }
        }
    }

    func shots(sideBelow: Bool) -> some View {
        ScrollViewReader { proxy in
            ThinScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    everyShot
                    if desk.shots.isEmpty {
                        Text(md: L("No files named by shot in this folder yet. Name them **K1**, **K1.1**, **K2**… and they show here."))
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(12)
                    }
                    ForEach(desk.shots, id: \.self) { code in
                        KinoShotCard(desk: desk, code: code, open: desk.selected == code) {
                            desk.selected = desk.selected == code ? nil : code
                        }.id(code)
                    }
                    if sideBelow { side.padding(14).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 11)) }
                }
            }
            .onChange(of: desk.selected) { _, code in
                if let code { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(code, anchor: .top) } }
            }
        }
    }

    /// What every shot starts from: the settings, and the words said in each prompt (the product's facts, the look).
    var everyShot: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                heading(L("EVERY SHOT"))
                Spacer()
                Text(L("Change a shot and only that shot changes")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            KinoSettingsRow(settings: Binding(get: { desk.batch.settings }, set: { desk.setBatchSettings($0) }))
            TextField(L("Said in every shot's prompt: the product's facts, the look…"),
                      text: Binding(get: { desk.batch.shared }, set: { desk.setShared($0) }), axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 12)).lineLimit(1...6)
                .padding(8).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
        }
        .padding(12).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
    }

    // MARK: Right: takes and accounts

    var side: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                heading(L("TAKES"))
                if desk.outputs.isEmpty {
                    Text(md: L("Each take is saved in the batch's **Kino** folder as soon as it is made, named by its shot (K2 take 1). Higgsfield deletes its own copy after 7 days."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(desk.outputs, id: \.self) { url in
                        HStack(spacing: 8) {
                            KinoThumb(url: url, width: 52, height: 36)
                            Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 11)).lineLimit(2)
                            Spacer(minLength: 0)
                            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Show in Finder"))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                    }
                    Text(md: L("Drag a take into **Premiere** to use it.")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                heading(L("ACCOUNTS"))
                KinoAccounts(desk: desk)
            }
        }
    }

    func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(14).frame(maxHeight: .infinity, alignment: .top)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
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

/// One shot. Closed: one line (model · inputs · picture · length · takes) and whether it is ready, so twenty shots can
/// be read at a glance. Open: its files with their roles, the prompt, its settings, and what Kino would send.
struct KinoShotCard: View {
    @ObservedObject var desk: KinoDesk
    let code: String
    let open: Bool
    let toggle: () -> Void
    @State private var insert: String?
    @State private var showingSent = false
    private let accent = PixelKino.theme

    var body: some View {
        let plan = desk.plan(code)
        let settings = desk.settings(code)
        let files = desk.files(in: code)
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggle) { summary(plan, settings, files) }.buttonStyle(.plain)
            if open {
                FlowLayout(spacing: 10) {
                    ForEach(files) { file in
                        KinoFileTile(file: file, role: desk.role(of: file, in: code), seconds: desk.durations[file.id],
                                     choose: { desk.setRole($0, of: file, in: code) }, tag: { insert = "@" + file.handle })
                    }
                }
                prompt(plan)
                VStack(alignment: .leading, spacing: 4) {
                    KinoSettingsRow(settings: Binding(get: { desk.settings(code) }, set: { desk.setSettings($0, for: code) }),
                                    lengthFrom: plan.seconds == nil ? files.first { desk.role(of: $0, in: code) == .edit }?.handle : nil)
                    if desk.shot(code).settings != nil {
                        Button(L("Use every shot's settings")) { desk.setSettings(nil, for: code) }
                            .buttonStyle(.link).font(.system(size: 10))
                    }
                }
                sent(plan)
                HStack(spacing: 10) {
                    Text(desk.blocker([code])).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button {} label: {
                        Label(settings.takes > 1 ? L("Run %@ · %@ takes", code, settings.takes) : L("Run %@", code), systemImage: "play.fill")
                    }.buttonStyle(.borderedProminent).disabled(true)
                }
            }
        }
        .padding(12)
        .background(.white.opacity(open ? 0.06 : 0.035), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(open ? accent.opacity(0.45) : .clear))
    }

    func summary(_ plan: KinoPlan, _ settings: KinoSettings, _ files: [KinoFile]) -> some View {
        let model = KinoModel.named(settings.model)
        let used = files.filter { desk.role(of: $0, in: code) != .unused }
        let counts = [(KinoKind.image, "%@ pictures", "1 picture"), (.video, "%@ videos", "1 video"), (.audio, "%@ sounds", "1 sound")]
            .compactMap { kind, many, one -> String? in
                let count = used.filter { $0.kind == kind }.count
                return count == 0 ? nil : count == 1 ? L(one) : L(many, count)
            }
        let quality = model.qualities.first { $0.id == settings.fitted(to: model).quality }?.title
        let parts = [model.name, counts.isEmpty ? L("Text only") : counts.joined(separator: " + "), quality,
                     plan.seconds.map { "\($0) s" } ?? L("the video's length"), "×\(settings.takes)"].compactMap { $0 }
        return HStack(spacing: 10) {
            Text(code).font(.system(size: 13, weight: .bold)).foregroundStyle(accent)
            Text(parts.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 6)
            if plan.problems.isEmpty {
                Label(L("Ready"), systemImage: "checkmark.circle.fill").font(.system(size: 10.5)).foregroundStyle(accent)
            } else {
                Label(plan.problems.count == 1 ? L("1 to fix") : L("%@ to fix", plan.problems.count), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5)).foregroundStyle(.orange)
            }
            Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    func prompt(_ plan: KinoPlan) -> some View {
        let sent = Set(plan.inputs.map { $0.handle.lowercased() })
        let text = desk.shot(code).prompt
        return ZStack(alignment: .topLeading) {
            KinoPromptView(text: Binding(get: { desk.shot(code).prompt }, set: { desk.setPrompt($0, for: code) }),
                           sent: sent, tint: NSColor(accent), insert: $insert)
            if text.isEmpty {
                Text(md: L("What happens in the shot. Press a file's **@tag** to name it: \"@%@ is held up to the camera…\"", desk.files(in: code).first?.handle ?? code))
                    .font(.system(size: 13)).foregroundStyle(.tertiary).padding(.horizontal, 13).padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 120)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Where the shot goes, what stops it, what Kino changes, and the prompt as the service reads it.
    func sent(_ plan: KinoPlan) -> some View {
        let model = KinoModel.named(desk.settings(code).model)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "paperplane").font(.system(size: 10)).foregroundStyle(.secondary)
                Text(plan.endpoint).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
                if let limit = model.promptLimit {
                    Text(L("%@ / %@ characters", plan.prompt.count.formatted(), limit.formatted()))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(plan.prompt.count > limit ? Color.orange : .secondary)
                }
            }
            ForEach(plan.problems, id: \.self) { status(false, $0) }
            ForEach(plan.notes, id: \.self) { status(nil, $0) }
            DisclosureGroup(isExpanded: $showingSent) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.inputs, id: \.handle) { input in
                        HStack(spacing: 6) {
                            Text("@" + input.handle).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(accent)
                            Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                            Text(input.slot).font(.system(size: 10.5, design: .monospaced))
                            Text("· " + input.tag).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                    }
                    Text(plan.prompt.isEmpty ? " " : plan.prompt).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8).background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                }.padding(.top, 4)
            } label: {
                Text(L("What Kino sends")).font(.system(size: 11, weight: .medium))
            }
        }
        .padding(10).background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    func status(_ good: Bool?, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: good == nil ? "info.circle" : good == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 10)).foregroundStyle(good == nil ? Color.secondary : good == true ? accent : .orange)
            Text(md: text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A file in its shot: its picture, its tag (press it to put it in the prompt) and its role.
struct KinoFileTile: View {
    let file: KinoFile
    let role: KinoRole
    let seconds: Double?
    let choose: (KinoRole) -> Void
    let tag: () -> Void
    private let accent = PixelKino.theme
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            KinoThumb(url: file.url, width: 120, height: 84)
                .overlay(alignment: .topTrailing) {
                    if file.kind != .image {
                        Label(seconds.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " s" } ?? "",
                              systemImage: file.kind == .video ? "video.fill" : "waveform")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2).background(.black.opacity(0.6), in: Capsule()).padding(4)
                    }
                }
                .opacity(role == .unused ? 0.35 : 1)
                .onTapGesture(count: 2) { NSWorkspace.shared.open(file.url) }
                .help(file.url.lastPathComponent)
            Button(action: tag) {
                Text("@" + file.handle).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent).lineLimit(1)
            }.buttonStyle(.plain).help(L("Put @%@ in the prompt where the cursor is", file.handle))
            Menu {
                ForEach(KinoRole.choices(file.kind)) { option in
                    Button { choose(option) } label: {
                        if option == role { Label(L(option.title), systemImage: "checkmark") } else { Text(L(option.title)) }
                    }
                }
            } label: {
                Label(L(role.title), systemImage: role.icon).font(.system(size: 10.5))
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help(L(role.detail))
        }
        .frame(width: 120, alignment: .leading)
        .contextMenu {
            Button(L("Open")) { NSWorkspace.shared.open(file.url) }
            Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        }
    }
}

/// The model and the settings it takes: only what the chosen model has, so the form follows the model.
struct KinoSettingsRow: View {
    @Binding var settings: KinoSettings
    /// The video a shot edits, whose length the take has: no length to pick then.
    var lengthFrom: String? = nil
    var body: some View {
        let model = KinoModel.named(settings.model)
        let current = settings.fitted(to: model)
        VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 6) {
                pill(model.name) {
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
                    Text(L("As long as @%@", lengthFrom)).font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 4)
                } else if let range = model.seconds {
                    pill(current.seconds.map { "\($0) s" } ?? L("Auto (%@ s)", model.defaultSeconds)) {
                        Button(L("Auto (%@ s)", model.defaultSeconds)) { settings = with(current) { $0.seconds = nil } }
                        ForEach(Array(range), id: \.self) { value in Button("\(value) s") { settings = with(current) { $0.seconds = value } } }
                    }
                }
                if !model.aspects.isEmpty {
                    pill(aspect(current.aspect)) {
                        ForEach(model.aspects, id: \.self) { value in Button(aspect(value)) { settings = with(current) { $0.aspect = value } } }
                    }
                }
                if !model.qualities.isEmpty {
                    pill(model.qualities.first { $0.id == current.quality }?.title ?? "") {
                        ForEach(model.qualities, id: \.id) { option in Button(option.title) { settings = with(current) { $0.quality = option.id } } }
                    }
                }
                if model.sound == true {
                    Button { settings = with(current) { $0.sound.toggle() } } label: {
                        Label(L(current.sound ? "Sound on" : "Sound off"), systemImage: current.sound ? "speaker.wave.2.fill" : "speaker.slash")
                            .font(.system(size: 11))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(.white.opacity(0.06), in: Capsule())
                    }.buttonStyle(.plain)
                } else if model.id == "kling-4.0" {
                    Text(L("Always makes sound")).font(.system(size: 10)).foregroundStyle(.secondary).padding(.vertical, 4)
                }
                Picker("", selection: Binding(get: { current.takes }, set: { value in settings = with(current) { $0.takes = value } })) {
                    ForEach(1...4, id: \.self) { Text("×\($0)").tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150).help(L("Takes a run makes"))
            }
            Text(L(model.note)).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    func with(_ settings: KinoSettings, _ change: (inout KinoSettings) -> Void) -> KinoSettings {
        var settings = settings
        change(&settings)
        return settings
    }

    func aspect(_ value: String) -> String { value == "adaptive" ? L("Follows the files") : value }

    func pill<Items: View>(_ title: String, @ViewBuilder items: () -> Items) -> some View {
        Menu { items() } label: { Text(title).font(.system(size: 11, weight: .medium)) }
            .menuStyle(.borderlessButton).fixedSize()
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(.white.opacity(0.06), in: Capsule())
    }
}

/// The two accounts. Higgsfield runs Seedance, Kling O3 and Motion Control under one key; Kling's own API has Kling 4.0.
/// Keys go in the Keychain; nothing checks them until Kino sends his first job.
struct KinoAccounts: View {
    @ObservedObject var desk: KinoDesk
    @State private var klingKey = ""
    @State private var keyID = ""
    @State private var secret = ""
    private let accent = PixelKino.theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            account("Higgsfield", L("Seedance 2.5, Kling O3 and Motion Control"), saved: desk.hasHiggsfield,
                    remove: desk.removeHiggsfield, site: "https://console.higgsfield.ai") {
                TextField(L("Key ID"), text: $keyID).textFieldStyle(.roundedBorder)
                SecureField(L("Key secret"), text: $secret).textFieldStyle(.roundedBorder)
                Button(L("Save")) { desk.saveHiggsfield(id: keyID, secret: secret); keyID = ""; secret = "" }
                    .disabled(keyID.trimmingCharacters(in: .whitespaces).isEmpty || secret.trimmingCharacters(in: .whitespaces).isEmpty)
            }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: saved ? "checkmark.circle.fill" : "key").font(.system(size: 11)).foregroundStyle(saved ? accent : .secondary)
                Text(name).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { NSWorkspace.shared.open(URL(string: site)!) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Get a key from %@", name))
            }
            Text(what).font(.system(size: 10)).foregroundStyle(.secondary)
            if saved {
                HStack(spacing: 8) {
                    Text(L("Key saved · checked on the first run")).font(.system(size: 10.5)).foregroundStyle(.secondary)
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
    @State private var image: NSImage?
    private static let cache = NSCache<NSString, NSImage>()
    var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.06))
            if let image { Image(nsImage: image).resizable().scaledToFill() }
        }
        .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 6))
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

/// A shot's prompt as you write it: tags of files the shot sends in Kino's colour, any other @tag in orange (it names no
/// file this shot sends). A file's tag button puts its tag where the cursor is.
struct KinoPromptView: NSViewRepresentable {
    @Binding var text: String
    let sent: Set<String>
    let tint: NSColor
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
        editor.textContainerInset = NSSize(width: 8, height: 10)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let changed = context.coordinator.parent.sent != sent
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
            let lines = NSMutableParagraphStyle()
            lines.lineSpacing = 4
            storage.addAttributes([.paragraphStyle: lines, .foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 13)], range: all)
            for tag in KinoPrompt.tags(in: view.string) {
                let color = parent.sent.contains(tag.handle.lowercased()) ? parent.tint : NSColor.systemOrange
                storage.addAttributes([.foregroundColor: color, .backgroundColor: color.withAlphaComponent(0.14),
                                       .font: NSFont.systemFont(ofSize: 13, weight: .semibold)], range: NSRange(tag.range, in: view.string))
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
