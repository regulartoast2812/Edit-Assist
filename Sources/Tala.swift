import SwiftUI

/// Tala ("star" in Tagalog), the voice helper: a soft pink mochi with a red bow, smiling eyes and rosy cheeks (a star
/// with eyes read as Patrick Star, not as her, 2026-11-03). Working: she bounces, squashes and a note floats up.
struct PixelTala: View {
    /// The helper's colour, the body's: their page and sidebar button take it.
    static let theme = Color(red: 1, green: 178 / 255, blue: 192 / 255)
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["...................", "...................", "...................", "..RR.RR............",
                       "..RRQRRPPPP........", "..PPPPPPPPPPPP.....", ".PPPPPPPPPPPPPP....", ".PPPPPPPPPPPPPP....",
                       ".PPPPPPPPPPPPPP....", ".PPPKPPPPPPKPPP....", ".PPKPKPPPPKPKPP....", ".PBBPPPPPPPPBBP....",
                       ".PPPPPPPPPPPPPP....", "..PPPPPPPPPPPP.....", "...DDDDDDDDDD......"]
    static let working: [[String]] = [
        ["...................", "................NN.", "................N..", "..RR.RR........NN..",
         "..RRQRRPPPP....NN..", "..PPPPPPPPPPPP.....", ".PPPPPPPPPPPPPP....", ".PPPPPPPPPPPPPP....",
         ".PPPPPPPPPPPPPP....", ".PPPKPPPPPPKPPP....", ".PPKPKPPPPKPKPP....", ".PBBPPPPPPPPBBP....",
         ".PPPPPPPPPPPPPP....", "..PPPPPPPPPPPP.....", "...DDDDDDDDDD......"],
        [".................NN", ".................N.", "................NN.", "................NN.",
         "..RR.RR............", "..RRQRRPPPP........", "..PPPPPPPPPPPP.....", ".PPPPPPPPPPPPPP....",
         ".PPPPPPPPPPPPPP....", ".PPPKPPPPPPKPPP....", ".PPKPKPPPPKPKPP....", ".PBBPPPPPPPPBBP....",
         ".PPPPPPPPPPPPPP....", "..PPPPPPPPPPPP.....", "...DDDDDDDDDD......"],
        ["................NN.", "................N..", "..RR.RR........NN..", "..RRQRRPPPP....NN..",
         "..PPPPPPPPPPPP.....", ".PPPPPPPPPPPPPP....", ".PPPPPPPPPPPPPP....", ".PPPPPPPPPPPPPP....",
         ".PPPKPPPPPPKPPP....", ".PPKPKPPPPKPKPP....", ".PBBPPPPPPPPBBP....", ".PPPPPPPPPPPPPP....",
         "..PPPPPPPPPPPP.....", "...DDDDDDDDDD......", "..................."],
        ["...................", "...................", ".................NN", "..RR.RR..........N.",
         "..RRQRRPPPP.....NN.", "..PPPPPPPPPPPP..NN.", ".PPPPPPPPPPPPPP....", ".PPPPPPPPPPPPPP....",
         ".PPPPPPPPPPPPPP....", ".PPPKPPPPPPKPPP....", ".PPKPKPPPPKPKPP....", ".PBBPPPPPPPPBBP....",
         ".PPPPPPPPPPPPPP....", "..PPPPPPPPPPPP.....", "...DDDDDDDDDD......"],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, working: Self.working,
                       colors: ["P": Color(red: 1, green: 178 / 255, blue: 192 / 255), "D": Color(red: 235 / 255, green: 140 / 255, blue: 160 / 255),
                                "B": Color(red: 245 / 255, green: 110 / 255, blue: 140 / 255), "K": Color(red: 45 / 255, green: 20 / 255, blue: 30 / 255),
                                "R": Color(red: 232 / 255, green: 64 / 255, blue: 100 / 255), "Q": Color(red: 170 / 255, green: 30 / 255, blue: 65 / 255),
                                "N": Color(red: 1, green: 235 / 255, blue: 240 / 255)],
                       pixel: pixel, busyUntil: busyUntil, previewOnHover: previewOnHover)
            .accessibilityLabel("Tala")
    }
}

/// Tala's page (2026-11-04). Before a key: the ElevenLabs setup. With one, columns laid out like ElevenLabs' own Text to
/// Speech page (you asked for it): the output folder and its files on the left, Tala's copy of the script in the middle,
/// where your [audio tags] direct the delivery (no voice sliders, you asked for none), and the voice, the model and the
/// account on the right. On a narrow window the files go in a tab beside the settings.
struct TalaPage: View {
    @ObservedObject var voice: TalaVoice
    let project: Project
    @State private var draft = ""
    @State private var changingKey = false
    @State private var confirmRecopy = false
    @State private var insert: String?
    @State private var pickingVoice = false
    @State private var sideTab = "settings"
    /// The tags your ElevenLabs scripts use (2026-11-04), then two more ElevenLabs documents for v3 and v4.
    static let commonTags = ["[warm]", "[enthusiastic]", "[cheerful]", "[happy]", "[playful]", "[excited]", "[whispers]", "[laughs]"]
    private let accent = PixelTala.theme

    var body: some View {
        Group {
            if voice.connection == .connected && !changingKey {
                workspace
            } else {
                ThinScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        intro
                        section(L("ELEVENLABS")) { account }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.scrollIndicators(.automatic)
            }
        }
        .onAppear { voice.open(); voice.load(script: project.openScript.id, text: project.script) }
        .onChange(of: project.openScript.id) { _, id in voice.load(script: id, text: project.script) }
        .onDisappear { voice.stopPreview() }
        .confirmationDialog(L("Copy the script again?"), isPresented: $confirmRecopy) {
            Button(L("Copy the script again"), role: .destructive) { voice.recopy(project.script) }
        } message: {
            Text(md: L("Tala's copy starts again from the script as it is now. The tags you added are lost."))
        }
    }

    var intro: some View {
        HStack(alignment: .top, spacing: 16) {
            PixelTala(pixel: 4, previewOnHover: true)
            VStack(alignment: .leading, spacing: 8) {
                Text(md: L("Your voice helper")).font(.system(size: 13, weight: .semibold))
                Bullets(["Turns your script into a **voice-over** with **ElevenLabs**",
                         "Finds **music** that suits the voice",
                         "The first helper that works with **AI**"], size: 11)
            }
        }
    }

    // MARK: Columns

    var workspace: some View {
        GeometryReader { size in
            let wide = size.size.width >= 980
            HStack(alignment: .top, spacing: 12) {
                if wide { panel { files }.frame(width: 240) }
                editor.frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                panel {
                    if !wide {
                        Picker("", selection: $sideTab) {
                            Text(L("Settings")).tag("settings")
                            Text(L("Files")).tag("files")
                        }.pickerStyle(.segmented).labelsHidden()
                    }
                    if wide || sideTab == "settings" { settings } else { files }
                }.frame(width: 290)
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

    // MARK: Middle: the script

    var editor: some View {
        let text = voice.copy?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chosen = voice.model
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                PixelTala(pixel: 1.6, busyUntil: voice.making == nil ? nil : .distantFuture)
                Button { pickingVoice = true } label: {
                    HStack(spacing: 6) {
                        Circle().fill(accent.gradient).frame(width: 14, height: 14)
                        Text(voice.voices.first { $0.id == voice.voiceID }?.name ?? L("Choose a voice")).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.06), in: Capsule())
                }.buttonStyle(.plain)
                .popover(isPresented: $pickingVoice, arrowEdge: .bottom) { TalaVoicePicker(voice: voice, shown: $pickingVoice) }
                Spacer()
                Text(project.openScript.name).font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            if let copy = voice.copy, copy.outdated(by: project.script), !ElevenLabs.spoken(project.script).isEmpty {
                HStack(spacing: 10) {
                    status(false, L("The script changed since Tala copied it"))
                    Button(L("Copy again")) { confirmRecopy = true }.controlSize(.small)
                }.padding(.horizontal, 16).padding(.bottom, 6)
            }
            ZStack(alignment: .topLeading) {
                TaggedTextView(text: Binding(get: { voice.copy?.text ?? "" }, set: { voice.edit($0) }), tagColor: NSColor(accent), insert: $insert)
                    .disabled(voice.making != nil || voice.copy == nil)
                if text.isEmpty {
                    Text(md: L("Write or paste the voice-over here. Put a **[tag]** like [warm] before the words it directs."))
                        .font(.system(size: 13)).foregroundStyle(.tertiary).padding(.horizontal, 13).padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxHeight: .infinity).padding(.horizontal, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.commonTags, id: \.self) { tag in
                        Button(tag) { insert = tag }.buttonStyle(.plain)
                            .font(.system(size: 11)).foregroundStyle(accent)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                            .help(L("Put %@ where the cursor is", tag))
                    }
                }.padding(.horizontal, 16)
            }.padding(.vertical, 8)
            if voice.failure != nil || voice.made != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let failure = voice.failure { status(false, L("ElevenLabs could not make it: %@", failure)) }
                    if let made = voice.made { fileRow(made, date: nil, bytes: nil, highlighted: true) }
                }.padding(.horizontal, 16).padding(.bottom, 8)
            }
            Divider()
            HStack(spacing: 12) {
                if let plan = voice.account {
                    Text(L("%@ credits remaining", plan.left.formatted())).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if let chosen {
                    let parts = ElevenLabs.parts(text, max: chosen.maxCharacters).count
                    Text(L("%@ / %@ characters", text.count.formatted(), chosen.maxCharacters.formatted()))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(parts > 1 ? Color.orange : .secondary)
                        .help(parts > 1 ? L("Longer than %@ takes at once: Tala will send it in %@ parts", chosen.name, parts)
                                        : L("About %@ credits", Int((Double(text.count) * chosen.creditsPerCharacter).rounded(.up)).formatted()))
                }
                if let making = voice.making {
                    ProgressView().controlSize(.small)
                    Text(making.of > 1 ? L("Tala is reading part %@ of %@…", making.part, making.of) : L("Tala is reading…")).font(.system(size: 11))
                } else {
                    Button { voice.make(project: project.name, script: project.openScript.name) } label: {
                        Label(L("Make voice-over"), systemImage: "waveform")
                    }.buttonStyle(.borderedProminent).disabled(text.isEmpty || voice.voiceID.isEmpty || chosen == nil)
                }
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
    }

    // MARK: Right: voice, model, account

    @ViewBuilder var settings: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading(L("VOICE"))
            Button { pickingVoice = true } label: {
                HStack(spacing: 10) {
                    Circle().fill(accent.gradient).frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        let chosen = voice.voices.first { $0.id == voice.voiceID }
                        Text(chosen?.name ?? L("Choose a voice")).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        if let labels = chosen?.labels, !labels.isEmpty {
                            Text(labels.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(10).contentShape(Rectangle())
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
            Text(L("%@ in My Voices", voice.voices.count)).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 6) {
            heading(L("MODEL"))
            Menu {
                ForEach(voice.models) { model in
                    Button { voice.modelID = model.id } label: {
                        if model.id == voice.modelID { Label(model.name, systemImage: "checkmark") } else { Text(model.name) }
                    }
                }
            } label: {
                Text(voice.model?.name ?? L("Choose a model")).font(.system(size: 12, weight: .medium))
            }.menuStyle(.borderlessButton).fixedSize()
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            if let chosen = voice.model {
                if !chosen.description.isEmpty { Text(chosen.description).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                Text(chosen.creditsPerCharacter == 1 ? L("Up to %@ characters a request · 1 credit a character", chosen.maxCharacters.formatted())
                     : L("Up to %@ characters a request · %@ credits a character", chosen.maxCharacters.formatted(), chosen.creditsPerCharacter.formatted()))
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !ElevenLabs.understandsTags(chosen.id), let text = voice.copy?.text, !ElevenLabs.tags(in: text).isEmpty {
                    status(false, L("%@ may read your [tags] out loud: Eleven v4 and v3 follow them", chosen.name))
                }
            }
        }
        Spacer()
        VStack(alignment: .leading, spacing: 6) {
            heading(L("ELEVENLABS"))
            status(true, L("Connected to ElevenLabs"))
            if let plan = voice.account {
                Text(L("%@ plan: %@ of %@ credits left", plan.tier.capitalized, plan.left.formatted(), plan.limit.formatted())).font(.system(size: 11)).foregroundStyle(.secondary)
                if let resets = plan.resets {
                    Text(L("Credits renew on %@", resets.formatted(date: .abbreviated, time: .omitted))).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else {
                Text(md: L("This key cannot read your plan: allow **User** (read) on it to see your credits")).font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Button(L("Refresh")) { voice.refresh() }
                Button(L("Change key")) { draft = ""; changingKey = true }
                Button(L("Remove key"), role: .destructive) { voice.disconnect() }
            }.controlSize(.small)
        }
    }

    // MARK: Left: the output folder

    @ViewBuilder var files: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                heading(L("SAVE TO"))
                Spacer()
                Button { voice.refreshFiles() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Refresh"))
            }
            Button { voice.chooseFolder() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(accent)
                    Text(voice.folder?.lastPathComponent ?? L("Choose a folder")).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer()
                    Text(L("Change…")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(10).contentShape(Rectangle())
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(voice.making != nil)
            .help(voice.folder?.path(percentEncoded: false) ?? L("Tala asks for it the first time you make a voice-over"))
        }
        VStack(alignment: .leading, spacing: 6) {
            heading(L("FILES"))
            if voice.folder == nil {
                Text(md: L("Pick where voice-overs are saved; they are listed here.")).font(.system(size: 11)).foregroundStyle(.secondary)
            } else if voice.files.isEmpty {
                Text(md: L("No voice-overs in this folder yet.")).font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(voice.files) { fileRow($0.url, date: $0.date, bytes: $0.bytes, highlighted: $0.url == voice.made) }
                    }
                }
                Text(md: L("Drag a file into **Premiere** to use it.")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.frame(maxHeight: .infinity, alignment: .top)
    }

    func fileRow(_ url: URL, date: Date?, bytes: Int64?, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            Button { voice.play(url) } label: {
                Image(systemName: voice.playing == url.path ? "stop.circle.fill" : "play.circle.fill").font(.system(size: 20))
            }.buttonStyle(.plain).foregroundStyle(accent).help(L(voice.playing == url.path ? "Stop" : "Play"))
            VStack(alignment: .leading, spacing: 1) {
                Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 11, weight: highlighted ? .semibold : .regular)).lineLimit(2)
                if let date {
                    Text([date.formatted(.relative(presentation: .named)), bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }]
                        .compactMap { $0 }.joined(separator: " · ")).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Show in Finder"))
        }
        .padding(6).contentShape(Rectangle())
        .background(highlighted ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button(L("Copy path")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string) }
        }
    }

    // MARK: Key setup

    @ViewBuilder var account: some View {
        switch voice.connection {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(md: L("Checking with ElevenLabs…")).font(.system(size: 12))
            }
        case .missing(let permission) where !changingKey:
            let name = ElevenLabs.permissionName(permission)
            status(false, L("Your key works, but it is missing one permission: **%@**", name))
            Bullets([L("In **ElevenLabs**, open **Developers** in the sidebar, then **API Keys**"),
                     L("Edit this key and turn on **%@**", name),
                     L("Press **Check again** here. Tala kept the key, so there is no need to paste it again")], numbered: true, size: 11)
            HStack(spacing: 8) {
                Button(L("Check again")) { voice.refresh() }
                Button(L("Use another key")) { draft = ""; changingKey = true }
                Button(L("Remove key"), role: .destructive) { voice.disconnect() }
                Button(L("Open ElevenLabs")) { NSWorkspace.shared.open(URL(string: "https://elevenlabs.io/app")!) }
            }.controlSize(.small)
        case .offline(let reason):
            status(false, L("Could not reach ElevenLabs: %@", reason))
            Button(L("Try again")) { voice.refresh() }.controlSize(.small)
        default:
            if case .rejected(let reason) = voice.connection { status(false, L("ElevenLabs did not accept this key: %@", reason)) }
            Bullets(["In **ElevenLabs**, open **Developers** in the sidebar, then **API Keys**",
                     "**Create Key**. New keys are restricted: allow **Text to Speech**, and reading **Voices**, **Models** and **User**",
                     "Copy it at once (ElevenLabs shows it only once) and paste it here"], numbered: true, size: 11)
            HStack(spacing: 8) {
                SecureField(L("ElevenLabs API key"), text: $draft)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    .onSubmit(connect)
                Button(L("Connect"), action: connect).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                if changingKey { Button(L("Cancel")) { changingKey = false; draft = "" } }
                Button(L("Open ElevenLabs")) { NSWorkspace.shared.open(URL(string: "https://elevenlabs.io/app")!) }
            }
            Text(md: L("The key is kept in your Mac's **Keychain**, never in your projects."))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func connect() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        voice.connect(key: draft)
        draft = ""; changingKey = false
    }

    func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(title)
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

/// The voices in My Voices, searched by name, accent, gender, age, use or kind; a sample plays from each.
struct TalaVoicePicker: View {
    @ObservedObject var voice: TalaVoice
    @Binding var shown: Bool
    @State private var search = ""
    private let accent = PixelTala.theme

    var found: [TalaVoice.Voice] {
        let words = search.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return voice.voices }
        return voice.voices.filter { item in
            let text = ([item.name, item.category] + item.labels).joined(separator: " ").lowercased()
            return words.allSatisfy(text.contains)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("Search %@ voices", voice.voices.count), text: $search).textFieldStyle(.roundedBorder)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(found) { row($0).id($0.id) }
                    }
                }
                .onAppear { proxy.scrollTo(voice.voiceID, anchor: .center) }
            }
            if found.isEmpty { Text(L("No voice matches")).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .padding(12).frame(width: 400, height: 460)
    }

    func row(_ item: TalaVoice.Voice) -> some View {
        let chosen = item.id == voice.voiceID
        return HStack(spacing: 10) {
            Image(systemName: chosen ? "checkmark.circle.fill" : "circle").foregroundStyle(chosen ? accent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 12, weight: chosen ? .semibold : .regular)).lineLimit(1)
                if !item.labels.isEmpty {
                    Text(item.labels.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if !item.category.isEmpty {
                Text(L(item.category.capitalized)).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(.white.opacity(0.06), in: Capsule())
            }
            if item.preview != nil {
                Button { voice.preview(item) } label: {
                    Image(systemName: voice.playing == item.id ? "stop.circle.fill" : "play.circle.fill").font(.system(size: 18))
                }.buttonStyle(.plain).foregroundStyle(accent).help(L(voice.playing == item.id ? "Stop" : "Hear a sample"))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(chosen ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { voice.voiceID = item.id; shown = false }
    }
}

/// Tala's copy as you edit it, with [tags] in her colour. A tag button puts its tag where the cursor is.
struct TaggedTextView: NSViewRepresentable {
    @Binding var text: String
    let tagColor: NSColor
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
        editor.font = .systemFont(ofSize: 14)
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
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        view.isEditable = context.environment.isEnabled
        if view.string != text { view.string = text; context.coordinator.color(view) }
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
        var parent: TaggedTextView
        init(_ parent: TaggedTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            color(view)
        }
        func color(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let all = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.foregroundColor, range: all)
            storage.removeAttribute(.backgroundColor, range: all)
            let lines = NSMutableParagraphStyle()
            lines.lineSpacing = 5
            storage.addAttribute(.paragraphStyle, value: lines, range: all)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: all)
            for range in ElevenLabs.tags(in: view.string) {
                storage.addAttributes([.foregroundColor: parent.tagColor, .backgroundColor: parent.tagColor.withAlphaComponent(0.14)],
                                      range: NSRange(range, in: view.string))
            }
            storage.endEditing()
        }
    }
}
