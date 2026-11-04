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

/// Tala's page (2026-11-04): your ElevenLabs API key, then the plan's credits, the voice and the model, as ElevenLabs'
/// own text-to-speech page asks for them, and Tala's copy of the open script, where your [audio tags] direct the delivery
/// (no voice sliders, you asked for none). Make saves one MP3 of it in the folder you picked.
struct TalaPage: View {
    @ObservedObject var voice: TalaVoice
    let project: Project
    @State private var draft = ""
    @State private var changingKey = false
    @State private var confirmRecopy = false
    /// Voice tags ElevenLabs documents for v3 and v4, the ones an ad's read uses most.
    static let commonTags = ["[excited]", "[curious]", "[whispers]", "[laughs]", "[sighs]", "[sarcastic]", "[exhales]"]
    private let accent = PixelTala.theme

    var body: some View {
        ThinScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PixelTala(pixel: 4, busyUntil: voice.making == nil ? nil : .distantFuture, previewOnHover: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(md: L("Your voice helper")).font(.system(size: 13, weight: .semibold))
                    Bullets(["Turns your script into a **voice-over** with **ElevenLabs**",
                             "Finds **music** that suits the voice",
                             "The first helper that works with **AI**"], size: 11)
                }
            }
            section(L("ELEVENLABS")) { account }
            if voice.connection == .connected {
                section(L("VOICE"), trailing: voice.voices.isEmpty ? nil : L("%@ in My Voices", voice.voices.count)) { voices }
                section(L("MODEL")) { model }
                section(L("VOICE-OVER SCRIPT"), trailing: project.openScript.name) { copy }
                section(L("MAKE")) { make }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.automatic)
        .onAppear { voice.open(); voice.load(script: project.openScript.id, text: project.script) }
        .onChange(of: project.openScript.id) { _, id in voice.load(script: id, text: project.script) }
        .onDisappear { voice.stopPreview() }
        .confirmationDialog(L("Copy the script again?"), isPresented: $confirmRecopy) {
            Button(L("Copy the script again"), role: .destructive) { voice.recopy(project.script) }
        } message: {
            Text(md: L("Tala's copy starts again from the script as it is now. The tags you added are lost."))
        }
    }

    @ViewBuilder var account: some View {
        switch voice.connection {
        case .connected where !changingKey:
            status(true, L("Connected to ElevenLabs"))
            if let plan = voice.account {
                status(nil, L("%@ plan: %@ of %@ credits left", plan.tier.capitalized, plan.left.formatted(), plan.limit.formatted()))
                if let resets = plan.resets {
                    Text(L("Credits renew on %@", resets.formatted(date: .abbreviated, time: .omitted))).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else {
                status(nil, L("This key cannot read your plan: allow **User** (read) on it to see your credits"))
            }
            HStack(spacing: 8) {
                Button(L("Refresh")) { voice.refresh() }
                Button(L("Change key")) { draft = ""; changingKey = true }
                Button(L("Remove key"), role: .destructive) { voice.disconnect() }
            }.controlSize(.small)
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

    @ViewBuilder var voices: some View {
        if voice.voices.isEmpty {
            Text(md: L("No voices in My Voices: add one in ElevenLabs' **Voice Library**, then Refresh.")).font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(voice.voices) { row($0) }
                }
            }.frame(maxHeight: 260)
        }
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
        .onTapGesture { voice.voiceID = item.id }
    }

    @ViewBuilder var model: some View {
        Picker(L("Model"), selection: $voice.modelID) {
            ForEach(voice.models) { Text($0.name).tag($0.id) }
        }.labelsHidden().frame(maxWidth: 300)
        if let chosen = voice.model {
            if !chosen.description.isEmpty { Text(chosen.description).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3) }
            Text(L("Up to %@ characters a request · %@ credits a character", chosen.maxCharacters.formatted(), chosen.creditsPerCharacter.formatted())).font(.system(size: 10)).foregroundStyle(.secondary)
            if !ElevenLabs.understandsTags(chosen.id), let text = voice.copy?.text, !ElevenLabs.tags(in: text).isEmpty {
                status(false, L("%@ may read your [tags] out loud: Eleven v4 and v3 follow them", chosen.name))
            }
        }
    }

    @ViewBuilder var copy: some View {
        if ElevenLabs.spoken(project.script).isEmpty {
            Text(md: L("No script yet: paste one in the project first.")).font(.system(size: 12)).foregroundStyle(.secondary)
        } else if let copy = voice.copy {
            Text(md: L("Tala's own copy of the script. Add **[tags]** where the delivery should change; your script and highlight runs never see them."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if copy.outdated(by: project.script) {
                HStack(spacing: 10) {
                    status(false, L("The script changed since Tala copied it"))
                    Button(L("Copy again")) { confirmRecopy = true }.controlSize(.small)
                }
            }
            TaggedTextView(text: Binding(get: { copy.text }, set: { voice.edit($0) }), tagColor: NSColor(accent), insert: $insert)
                .frame(minHeight: 180, maxHeight: 320)
                .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 7))
                .disabled(voice.making != nil)
            HStack(spacing: 6) {
                ForEach(Self.commonTags, id: \.self) { tag in
                    Button(tag) { insert = tag }.buttonStyle(.plain)
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(accent)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(accent.opacity(0.12), in: Capsule())
                        .help(L("Put %@ where the cursor is", tag))
                }
            }
        }
    }

    @State private var insert: String?

    @ViewBuilder var make: some View {
        let text = voice.copy?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let chosen = voice.model, !text.isEmpty {
            let credits = Int((Double(text.count) * chosen.creditsPerCharacter).rounded(.up))
            let parts = ElevenLabs.parts(text, max: chosen.maxCharacters).count
            status(nil, L("%@ characters, about %@ credits", text.count.formatted(), credits.formatted()))
            if parts > 1 { status(nil, L("Longer than %@ takes at once: Tala will send it in %@ parts", chosen.name, parts)) }
            if let plan = voice.account, credits > plan.left {
                status(false, L("More than the %@ credits left on your plan", plan.left.formatted()))
            }
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(voice.folder?.path(percentEncoded: false) ?? L("No folder yet: Tala asks the first time")).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                Button(L(voice.folder == nil ? "Choose…" : "Change…")) { voice.chooseFolder() }.controlSize(.small).disabled(voice.making != nil)
            }
            HStack(spacing: 10) {
                Button { voice.make(project: project.name, script: project.openScript.name) } label: {
                    Label(L("Make voice-over"), systemImage: "waveform")
                }.buttonStyle(.borderedProminent).disabled(voice.making != nil || voice.voiceID.isEmpty)
                if let making = voice.making {
                    ProgressView().controlSize(.small)
                    Text(making.of > 1 ? L("Tala is reading part %@ of %@…", making.part, making.of) : L("Tala is reading…")).font(.system(size: 11))
                }
            }
            if let failure = voice.failure { status(false, L("ElevenLabs could not make it: %@", failure)) }
            if let made = voice.made {
                HStack(spacing: 10) {
                    Button { voice.playMade() } label: {
                        Image(systemName: voice.playing == made.path ? "stop.circle.fill" : "play.circle.fill").font(.system(size: 18))
                    }.buttonStyle(.plain).foregroundStyle(accent)
                    Text(made.lastPathComponent).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([made]) }.controlSize(.small)
                }
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
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: all)
            for range in ElevenLabs.tags(in: view.string) {
                storage.addAttribute(.foregroundColor, value: parent.tagColor, range: NSRange(range, in: view.string))
            }
            storage.endEditing()
        }
    }
}
