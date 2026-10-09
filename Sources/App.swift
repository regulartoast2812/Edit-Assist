import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct EditAssistApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup("Edit Assist") {
            ContentView().environmentObject(store)
                .frame(minWidth: 1120, minHeight: 760)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1360, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) { Button("New project") { store.addProject() }.keyboardShortcut("n") }
            CommandMenu("Assistant") {
                Button("Stop") { store.stop() }.keyboardShortcut(".", modifiers: .command)
                Button("Connection settings") { store.openConnection() }.keyboardShortcut(",")
                Button("Permissions…") { store.openPermissions() }.keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}

private let accent = Color(red: 0.43, green: 0.88, blue: 0.73)
private let panel = Color(red: 0.085, green: 0.105, blue: 0.12)
private let canvasBackground = Color(red: 0.045, green: 0.06, blue: 0.075)

struct ContentView: View {
    @EnvironmentObject var s: Store
    @State private var contextOpen = false
    @State private var detectionSettingsOpen = false
    @State private var settingsOpen = false
    @State private var techStackOpen = false
    @State private var settingsDestination: String?
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 224)
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                footer
                Divider()
                if !s.permissionsReady { permissionBanner; Divider() }
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .firstTextBaseline) {
                            if s.tab == "Assistant" {
                                Text("Assistant").font(.system(size: 22, weight: .semibold))
                            } else if s.tab == "project" {
                                Label("Project", systemImage: "film.stack").font(.system(size: 22, weight: .semibold))
                            } else {
                                Label(s.function.title, systemImage: s.function.icon).font(.system(size: 22, weight: .semibold))
                            }
                            Spacer()
                            Button { contextOpen.toggle() } label: { Label("Context", systemImage: "sidebar.right") }
                                .tint(contextOpen ? accent : .secondary)
                        }
                        if s.tab == "Assistant" { conversation }
                        else if s.tab == "project" { projectPage }
                        else { page(for: s.function) }
                    }.padding(24).frame(minWidth: 450, maxWidth: .infinity)
                    if contextOpen {
                        Divider()
                        inspector.padding(20).frame(width: 300)
                    }
                }
            }
        }
        .background(canvasBackground)
        .tint(accent)
        .sheet(isPresented: $settingsOpen, onDismiss: {
            if settingsDestination == "provider" { s.openConnection() }
            if settingsDestination == "permissions" { s.openPermissions() }
            settingsDestination = nil
        }) { settingsSheet }
        .sheet(isPresented: $techStackOpen) { techStackSheet }
        .sheet(isPresented: $s.connectionOpen) { ConnectionView().environmentObject(s) }
        .sheet(isPresented: $s.permissionsOpen) { PermissionsView().environmentObject(s) }
        .sheet(isPresented: $s.showScriptDraft) {
            VStack(alignment: .leading, spacing: 15) {
                Text("Review the extracted script").font(.title2)
                Text("Check the wording and **bold phrases** against your screenshot before applying.").foregroundStyle(.secondary)
                TextEditor(text: Binding(get: { s.scriptDraft ?? "" }, set: { s.scriptDraft = $0 })).font(.system(size: 13, design: .monospaced)).frame(minHeight: 320)
                HStack { Button("Discard") { s.scriptDraft = nil; s.showScriptDraft = false }; Spacer(); Button("Use this script") { s.applyScriptDraft() }.buttonStyle(.borderedProminent) }
            }.padding(25).frame(width: 620)
        }
        .alert("Edit Assist", isPresented: Binding(get: { s.error != nil }, set: { if !$0 { s.error = nil } })) {
            Button("OK") { s.error = nil }
        } message: { Text(s.error ?? "") }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.motionlines").font(.system(size: 26)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("EDIT ASSIST").font(.system(size: 14, weight: .heavy, design: .rounded)).tracking(1.3)
                    Text("Your editing companion").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.top, 14)
            VStack(alignment: .leading, spacing: 12) {
                HStack { label("PROJECTS"); Spacer(); Button { s.addProject() } label: { Image(systemName: "plus") }.buttonStyle(.plain).disabled(s.busy) }
                ForEach(s.projects) { project in
                    Button { if s.selected != project.id { s.select(project.id) }; s.tab = "project" } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "film.stack").foregroundStyle(s.selected == project.id ? accent : .secondary)
                            Text(project.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            Spacer(minLength: 0)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(s.selected == project.id ? accent.opacity(s.tab == "project" ? 0.16 : 0.07) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(s.selected == project.id && s.tab == "project" ? accent : .primary)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(s.busy)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                label("FUNCTIONS")
                ForEach(EditFunction.allCases) { job in functionRow(job) }
            }
            Spacer()
            Button { s.tab = "Assistant" } label: {
                Label("Assistant", systemImage: "bubble.left.and.bubble.right").font(.system(size: 12))
                    .foregroundStyle(s.tab == "Assistant" ? accent : .primary)
            }.buttonStyle(.plain)
            Button { settingsOpen = true } label: {
                Label("Settings", systemImage: "gearshape").font(.system(size: 12))
            }.buttonStyle(.plain)
            Button { techStackOpen = true } label: {
                Label("Tech stack", systemImage: "square.stack.3d.up").font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Text("Edit Assist · Preview").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(18).background(panel.opacity(0.55))
    }

    private var techStackSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Tech stack").font(.title2.weight(.semibold))
            techStackRow("Swift · SwiftUI · AppKit", purpose: "Native macOS app")
            techStackRow("ScreenCaptureKit", purpose: "Live window capture")
            techStackRow("Apple Vision", purpose: "On-device text recognition")
            techStackRow("Core Graphics", purpose: "Image analysis · mouse & keyboard")
            techStackRow("Rules · local JSON", purpose: "Workflow logic · project memory")
            techStackRow("\(s.provider) CLI", purpose: "Optional AI assistant")
            HStack { Spacer(); Button("Done") { techStackOpen = false }.buttonStyle(.borderedProminent) }
        }.padding(26).frame(width: 400)
    }

    private func techStackRow(_ name: String, purpose: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary.opacity(0.8))
            Text(purpose).font(.system(size: 11)).foregroundStyle(.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }

    var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                // Plain text: an editable field here took keyboard focus at launch and looked stuck in editing.
                // The name is edited on the Project page.
                Button { s.tab = "project" } label: {
                    Text(s.project.name).font(.system(size: 23, weight: .semibold)).lineLimit(1)
                }.buttonStyle(.plain).help("Open the project")
                Text(s.target.map { "Editing in \($0.app) · \(($0.title as NSString).lastPathComponent)" } ?? "Open Premiere or After Effects to connect")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 0) {
                    Button { s.toggleDetection() } label: {
                        Label("Detection \(s.detectionEnabled ? "on" : "off") · F10", systemImage: s.detectionEnabled ? "eye" : "eye.slash")
                    }.tint(s.detectionEnabled ? accent : .secondary)
                    Button { detectionSettingsOpen.toggle() } label: { Image(systemName: "chevron.down") }
                        .help("Detection settings").popover(isPresented: $detectionSettingsOpen) { detectionControls }
                }.controlSize(.small)
                Text(!s.detectionEnabled ? "Detection off" : s.detectionMode ? s.detectionStatus : "During runs")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }.padding(.horizontal, 26).padding(.vertical, 22)
    }

    var permissionBanner: some View {
        Button { s.openPermissions() } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.badge.exclamationmark").font(.system(size: 17)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.missingPermissions).font(.system(size: 12, weight: .semibold))
                    Text("Edit Assist cannot see your editor or act in it until macOS allows this.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("Fix now").font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 13).padding(.vertical, 6).background(.orange.opacity(0.2), in: Capsule())
            }.padding(.horizontal, 26).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    var conversation: some View {
        VStack(alignment: .leading, spacing: 15) {
            if s.project.messages.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "sparkle").font(.system(size: 26)).foregroundStyle(accent)
                    Text("What are we working on?").font(.system(size: 25, weight: .semibold))
                    Text("Give me the project’s style and tell me what to handle. I’ll keep those choices with this project.").font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5)
                    VStack(alignment: .leading, spacing: 11) {
                        suggestion("Use the blue outline style for this project.")
                        suggestion("Only highlight bold phrases in the selected caption.")
                        suggestion("Explain the next step before you click.")
                    }.padding(.top, 7)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(panel, in: RoundedRectangle(cornerRadius: 16))
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(s.project.messages) { msg in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(msg.role == "user" ? "YOU" : "EDIT ASSIST").font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(msg.role == "user" ? .secondary : accent)
                                    if let images = msg.images { imageStrip(images, removable: false) }
                                    Text(msg.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(msg.role == "user" ? Color.white.opacity(0.035) : panel, in: RoundedRectangle(cornerRadius: 12)).id(msg.id)
                            }
                        }
                    }.onChange(of: s.project.messages.count) { _, _ in if let id = s.project.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                attachmentControls
                if !s.attachments.isEmpty { imageStrip(s.attachments, removable: true) }
                Text("Tell your assistant what to do · ⌘V also pastes screenshots").font(.system(size: 10)).foregroundStyle(.secondary)
                ScriptEditor(text: $s.command, editable: !s.busy, onPasteImage: { s.addScreenshot($0) }).frame(height: 70)
                HStack {
                    Text("\(s.provider) CLI · Conversation configures · Run performs").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button { s.send() } label: { Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).frame(width: 30, height: 28) }
                        .buttonStyle(.borderedProminent).disabled(s.busy || s.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(14).background(panel, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.1)))
        }
    }

    var script: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste formatted text from your script, or use **double asterisks** around phrases. Bold marks the range; your chosen style controls its appearance.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            HStack {
                Button("Paste formatted text", systemImage: "doc.on.clipboard") { s.pasteScript() }
                Button("Import…") { importScript() }
                Spacer()
                if s.project.script.isEmpty { Button("Use your example") { s.sample() }.buttonStyle(.plain).foregroundStyle(accent) }
            }.font(.system(size: 11)).disabled(s.busy)
            HStack {
                Button("B · Mark selection") { (NSApp.keyWindow?.firstResponder as? ScriptTextView)?.markSelection() }
                Text("Select words and press ⌘B").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
            }.disabled(s.busy)
            ScriptEditor(text: binding(\.script), editable: !s.busy, onPasteImage: { s.addScreenshot($0) })
                .padding(10).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10)).frame(minHeight: 160).disabled(s.busy)
            if !s.project.script.isEmpty && s.targetCount == 0 {
                Text("No bold phrases detected. The clipboard may contain only plain text. Mark phrases with ⌘B or read a screenshot of your formatted script.").font(.system(size: 11)).foregroundStyle(.orange)
            }
            attachmentControls
            if !s.attachments.isEmpty { imageStrip(s.attachments, removable: true) }
            if let error = parseError { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            label("PARSED HIGHLIGHTS")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(s.parsed.filter { !$0.highlights.isEmpty }) { line in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.text).font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(line.highlights.map(\.text).joined(separator: "  ·  ")).font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(maxHeight: 185)
        }
    }

    var phraseList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let next = s.nextTarget {
                HStack(spacing: 8) {
                    Text("NEXT").font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
                    Text("“\(next)”").font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                    Spacer()
                    Text("whichever phrase is on screen goes first").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.bottom, 4)
            }
            ForEach(Array(s.targets.enumerated()), id: \.offset) { _, phrase in
                let total = s.words(of: phrase).count
                let done = min(s.styled(phrase), total)
                HStack(spacing: 8) {
                    Image(systemName: done >= total ? "checkmark.circle.fill" : (done > 0 ? "circle.lefthalf.filled" : "circle"))
                        .font(.system(size: 11))
                        .foregroundStyle(done >= total ? accent : (done > 0 ? .orange : .secondary))
                    Text(phrase.trimmingCharacters(in: .whitespaces)).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text("\(done)/\(total)").font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(done > 0 && done < total ? .orange : .secondary)
                    Button("Redo") { s.clearProgress(of: phrase) }.font(.system(size: 9)).disabled(s.busy || done == 0)
                }
            }
            HStack {
                Text("Words count separately, so a phrase split across caption clips shows partial progress. Redo clears one phrase.")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Button("Reset progress") { s.resetProgress() }.font(.system(size: 10)).disabled(s.busy || s.project.styledWords.isEmpty)
            }.padding(.top, 4)
        }
    }

    var stages: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("In order, for every phrase. A run does them all; the boxes choose what Test selected stages does.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("All") { s.steps = Set(OCRStep.allCases.map(\.rawValue)) }.font(.system(size: 10)).disabled(s.busy)
                Button("None") { s.steps = [] }.font(.system(size: 10)).disabled(s.busy)
            }
            ForEach(OCRStep.allCases) { step in stageRow(step) }
        }
    }

    func stageRow(_ step: OCRStep) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { s.toggle(step) } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: s.enabled(step) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(s.enabled(step) ? accent : .secondary).font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.label).font(.system(size: 12, weight: .semibold))
                        Text(step.detail).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(s.busy)
            if let requirement = step.requirement {
                HStack(spacing: 7) {
                    Image(systemName: s.project.styleImage == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundStyle(s.project.styleImage == nil ? .orange : accent)
                    Text(s.project.styleImage == nil ? requirement : "Style reference image saved")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.leading, 24)
            }
        }.padding(.vertical, 3)
    }

    var routine: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A routine you can teach").font(.system(size: 23, weight: .semibold))
            Text("OCR mode below needs no instructions at all. The routine text and confidence threshold apply only to model-driven runs from the footer.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            TextEditor(text: binding(\.routine)).font(.system(size: 13)).scrollContentBackground(.hidden).padding(12).background(panel, in: RoundedRectangle(cornerRadius: 12)).disabled(s.busy)
            label("CURRENT RUN")
            TextField("What should this run do?", text: $s.runInstruction, axis: .vertical).lineLimit(3...5).textFieldStyle(.roundedBorder).disabled(s.busy)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    label("PAUSE BELOW")
                    Spacer()
                    Text("\(Int(s.minConfidence * 100))% confidence").font(.system(size: 11, design: .monospaced)).foregroundStyle(accent)
                }
                Slider(value: $s.minConfidence, in: 0.3...0.95, step: 0.05).disabled(s.busy)
                Text("The model scores its own certainty and is not well calibrated: sound decisions often report around 0.7. Raise this to stop more often and review, lower it to let the routine keep moving.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(2)
            }
            Text("Starts from the current Adobe state. Pause playback first. Run pauses after 40 actions so you can review progress.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { label("SCREEN OBSERVATION"); Spacer(); Button("Capture", systemImage: "camera") { s.capture() }.font(.system(size: 11)).disabled(s.busy || s.window == nil) }
                if let observation = s.observation {
                    CaptureView(image: observation.image, action: s.proposal?.action) { rect in s.rememberStyle(rect) }
                        .disabled(s.busy).clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("Drag a rectangle around your chosen style tile to remember its appearance.").font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "viewfinder").font(.system(size: 30)).foregroundStyle(accent.opacity(0.65))
                        Text("Your Adobe window will appear here").font(.system(size: 12))
                        Text("Capture to inspect it or teach a style.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).frame(height: 190).background(panel, in: RoundedRectangle(cornerRadius: 12))
                }
                Divider()
                if let proposal = s.proposal {
                    Divider()
                    label("NEXT STEP / LAST DECISION")
                    Text(proposal.message).font(.system(size: 12, weight: .medium))
                    Text(proposal.evidence).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(proposal.action.kind) · \(Int(proposal.confidence * 100))% model confidence").font(.system(size: 10, design: .monospaced)).foregroundStyle(accent)
                }
            }
        }
    }

    /// Style fields used only by assistant-driven (non-OCR) runs.
    var legacyStyle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            label("ASSISTANT RUNS ONLY")
            TextField("Describe the style for the assistant", text: binding(\.style), axis: .vertical).font(.system(size: 12)).lineLimit(2...4).textFieldStyle(.roundedBorder).disabled(s.busy)
            HStack {
                Button("Import style reference…") { importStyle() }
                Button("Choose from editor") { contextOpen = true; s.capture() }.disabled(s.window == nil)
                if s.project.styleImage != nil { Button("Clear reference") { s.update(\.styleImage, nil) } }
            }.font(.system(size: 10)).disabled(s.busy)
        }
    }

    var diagnostics: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Dump OCR") { s.dumpOCR() }.disabled(s.busy)
                Button("Test selected stages") { s.runChecklist() }.disabled(s.busy || s.targets.isEmpty)
                Button("Select next phrase") { s.runOCR(all: false) }.disabled(s.busy || s.nextTarget == nil)
                if !s.ocrOnly { Button("Preview assistant step") { s.run(limit: 1, preview: true) }.disabled(s.busy) }
            }.font(.system(size: 11))
            Text("Stage tests do not record phrase progress. Logs show recognition and action results.").font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            // Safeguard: a run that worked becomes a test every build replays, so a later change that
            // would decide differently on those screens is caught before it reaches a run.
            HStack(spacing: 10) {
                Toggle("Record the next run", isOn: $s.recordNextRun).toggleStyle(.switch).controlSize(.small).disabled(s.busy)
                Spacer()
                if s.lastRecording != nil {
                    Button("Keep last recording as a test") { s.keepLastRecording() }.font(.system(size: 11)).disabled(s.busy)
                }
            }
            Text("\(s.keptRecordings) recorded run\(s.keptRecordings == 1 ? "" : "s") kept as tests. Every build replays them and refuses to install if a decision changes.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            ForEach(Array(s.activity.suffix(30).enumerated()), id: \.offset) { _, entry in
                Text(entry).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    var settingsSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(.title2.weight(.semibold))
            Toggle("Use OCR for editing routines", isOn: $s.ocrOnly).disabled(s.busy)
            Text("OCR follows the caption styling workflow. Turn this off to use assistant-driven routines.").font(.system(size: 12)).foregroundStyle(.secondary)
            Divider()
            Button("Assistant provider · \(s.provider)") { settingsDestination = "provider"; settingsOpen = false }.disabled(s.busy)
            Button("macOS permissions") { settingsDestination = "permissions"; settingsOpen = false }
            Text(s.permissionsReady ? "Screen recording and mouse control are allowed." : s.missingPermissions)
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { settingsOpen = false }.buttonStyle(.borderedProminent) }
        }.padding(26).frame(width: 440)
    }

    var detectionControls: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Detection settings").font(.system(size: 16, weight: .semibold))
            Text("F10 switches all detection off or on.").font(.system(size: 11)).foregroundStyle(.secondary)
            Toggle("Continuous observation", isOn: $s.detectionMode)
            Toggle("Show during runs", isOn: $s.showOCRBoxes)
            Divider()
            label("SHOW ON SCREEN")
            Toggle("Boxes", isOn: $s.detectionBoxes)
            Toggle("Recognized text", isOn: $s.detectionText)
            Toggle("Details and coordinates", isOn: $s.detectionDetails)
            if !s.desktop.detectionHotkey.available { Text("F10 is unavailable. Use the header button.").font(.caption).foregroundStyle(.orange) }
        }.toggleStyle(.switch).controlSize(.small).padding(22).frame(width: 290)
    }

    /// One function in the sidebar: its name, where it stands, and a quick start on the right.
    func functionRow(_ job: EditFunction) -> some View {
        let showing = s.tab == "function" && s.function == job
        let progress = s.progress(of: job)
        return HStack(spacing: 6) {
            Button { s.function = job; s.tab = "function" } label: {
                HStack(spacing: 10) {
                    Image(systemName: job.icon).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.title).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        Text(s.activeFunction == job ? (s.runPaused ? "Paused" : "Running…") : progress.total == 0 ? "No script yet" : "\(s.project.completed.count) of \(s.targets.count) done")
                            .font(.system(size: 9)).foregroundStyle(s.activeFunction == job ? (s.runPaused ? .orange : accent) : .secondary)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if s.activeFunction == job {
                Button { s.toggleRunPause() } label: {
                    Image(systemName: s.runPaused ? "play.fill" : "pause.fill").font(.system(size: 10))
                        .frame(width: 26, height: 26).background((s.runPaused ? Color.orange : accent).opacity(0.2), in: Circle())
                        .foregroundStyle(s.runPaused ? .orange : accent)
                }.buttonStyle(.plain).help(s.runPaused ? "Continue" : "Pause")
            } else {
                Button { s.start(job) } label: {
                    Image(systemName: "play.fill").font(.system(size: 10))
                        .frame(width: 26, height: 26).background(accent.opacity(s.busy ? 0.06 : 0.2), in: Circle())
                        .foregroundStyle(s.busy ? Color.secondary : accent)
                }.buttonStyle(.plain).disabled(s.busy || (job == .highlight && s.ocrOnly && s.targets.isEmpty))
                    .help(s.busy ? "Another function is running" : "\(job.runLabel) — start \(job.title.lowercased()) now")
            }
        }.padding(.leading, 12).padding(.trailing, 8).padding(.top, 10).padding(.bottom, 14).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                // This function's own progress, along the bottom of its row.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08))
                        Capsule().fill(s.activeFunction == job && s.runPaused ? Color.orange : accent)
                            .frame(width: geometry.size.width * progress.fraction)
                    }
                }.frame(height: 3).padding(.horizontal, 12).padding(.bottom, 6)
            }
            .background(showing ? accent.opacity(0.12) : .white.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(showing ? accent : .secondary)
    }

    @ViewBuilder func page(for job: EditFunction) -> some View {
        switch job {
        case .highlight: highlightPage
        }
    }

    /// The one bar that shows and controls whatever is running. Only one function runs at a time, so
    /// Run starts the function on screen and is unavailable while any other is busy.
    var footer: some View {
        let job = s.activeFunction ?? s.function
        let progress = s.progress(of: job)
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: job.icon).font(.system(size: 15)).foregroundStyle(s.activeFunction == nil ? Color.secondary : (s.runPaused ? .orange : accent))
                    .frame(width: 30, height: 30).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(job.title).font(.system(size: 12, weight: .semibold))
                        Text(!s.running ? "Ready" : s.runPaused ? "Paused" : "Running")
                            .font(.system(size: 9, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background((!s.running ? Color.secondary : s.runPaused ? .orange : accent).opacity(0.18), in: Capsule())
                            .foregroundStyle(!s.running ? Color.secondary : s.runPaused ? .orange : accent)
                    }
                    Text(s.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 12)
                Button { s.toggleRunPause() } label: { Label(s.runPaused ? "Continue" : "Pause", systemImage: s.runPaused ? "play" : "pause") }
                    .disabled(!s.running).help("Pause between gestures; Continue resumes the same pass")
                Button { s.stop() } label: { Label("Stop", systemImage: "stop.fill") }.disabled(!s.busy).tint(.orange)
                Button { s.start(s.function) } label: { Label(s.function.runLabel, systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(s.busy || (s.function == .highlight && s.ocrOnly && s.targets.isEmpty))
                    .help(s.busy ? "\((s.activeFunction ?? s.function).title) is running; one function runs at a time" : "Start \(s.function.title.lowercased()) at the current playhead")
            }
            HStack(spacing: 10) {
                ProgressView(value: progress.fraction).tint(s.runPaused ? .orange : accent)
                Text("\(s.project.completed.count) of \(s.targets.count) phrases")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).fixedSize()
                if let left = s.timeLeft(of: job) {
                    Text("· about \(left < 60 ? "\(Int(left.rounded())) s" : "\(Int((left / 60).rounded())) min") left")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).fixedSize()
                }
            }
        }.padding(.horizontal, 24).padding(.vertical, 14).background(panel.opacity(0.6))
    }

    /// Highlight phrases: what to highlight, how, and how far it has got, on one page.
    /// Highlight phrases in two columns: the task on the left, how it is done on the right.
    var highlightPage: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    columnTitle("TASK")
                    Text(EditFunction.highlight.summary).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    if s.targets.isEmpty {
                        card("To do") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("No phrases yet. The script belongs to the project, so every function can use it.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                                Button("Add the script") { s.tab = "project" }.buttonStyle(.borderedProminent)
                            }
                        }
                    } else {
                        card("To do", trailing: "\(s.project.completed.count) of \(s.targets.count) done") { phraseList }
                    }
                }.padding(.bottom, 10)
            }.frame(minWidth: 380, maxWidth: .infinity)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    columnTitle("SETUP")
                    card("Style and size") {
                        HStack(alignment: .top, spacing: 12) {
                            Group {
                                if let picked = s.pickedStyleImage {
                                    Image(nsImage: picked).resizable().scaledToFit()
                                } else {
                                    Image(systemName: "square.grid.2x2").font(.system(size: 22)).foregroundStyle(accent)
                                }
                            }.frame(width: 56, height: 56).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.pickedStyleImage == nil ? "Picked on the first phrase" : "Last picked style")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(s.project.keepsStyle
                                     ? (s.hasRememberedStyle ? "Reuse this style across runs. Reset it when you want to choose a different tile." : "Choose a tile on the first phrase. Remember it for the rest of this run and future runs.")
                                     : "Choose a tile on the first phrase of each run; use it for the remaining phrases.")
                                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        HStack {
                            Toggle("Keep style", isOn: Binding(get: { s.project.keepsStyle }, set: { s.update(\.keepStyle, Optional($0)) }))
                                .toggleStyle(.switch).controlSize(.small)
                            Spacer()
                            Button("Reset style") { s.resetStyle() }
                                .disabled(!s.hasRememberedStyle)
                        }.disabled(s.busy)
                        HStack(spacing: 10) {
                            label("FONT SIZE STEP")
                            Spacer()
                            Stepper(value: Binding(get: { s.project.fontSizeStep }, set: { s.update(\.fontSizeStep, $0) }), in: 1...40) {
                                Text("+\(s.project.fontSizeStep)").font(.system(size: 12, design: .monospaced)).foregroundStyle(accent)
                            }.disabled(s.busy)
                        }
                        if !s.ocrOnly { legacyStyle }
                    }
                    card("Steps for each phrase") { stages }
                    DisclosureGroup("Diagnostics") { diagnostics.padding(.top, 12) }
                    if !s.ocrOnly {
                        DisclosureGroup("Assistant routine instructions") { routine.frame(minHeight: 420).padding(.top, 12) }
                    }
                }.padding(.bottom, 10)
            }.frame(width: 400)
        }
    }

    func columnTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(accent.opacity(0.8))
    }

    /// The project's own information, shared by every function that works on it.
    var projectPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("What this project is about. Functions read from here: Highlight phrases takes its bold phrases from the script.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                card("Details") {
                    HStack(spacing: 12) {
                        label("NAME")
                        TextField("Project name", text: binding(\.name)).textFieldStyle(.roundedBorder).disabled(s.busy)
                    }
                    HStack(spacing: 12) {
                        label("EDITOR")
                        Text(s.target.map { "\($0.app) · \(($0.title as NSString).lastPathComponent)" } ?? s.project.app).font(.system(size: 12))
                        Spacer()
                    }
                }
                card("Script", trailing: "\(s.targetCount) phrases") { script.frame(minHeight: 420) }
                HStack {
                    Spacer()
                    Button { s.function = .highlight; s.tab = "function" } label: { Label("Go to Highlight phrases", systemImage: "arrow.right") }
                        .disabled(s.targets.isEmpty)
                }
            }.padding(.bottom, 10)
        }
    }

    func card<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                if let trailing { Text(trailing).font(.system(size: 11, design: .monospaced)).foregroundStyle(accent) }
            }
            content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(panel, in: RoundedRectangle(cornerRadius: 12))
    }

    var attachmentControls: some View {
        HStack(spacing: 8) {
            Button("Add screenshots…", systemImage: "photo.badge.plus") { importScreenshots() }
            Button("Paste image") { s.pasteScreenshot() }
            if !s.attachments.isEmpty { Button("Read as script") { s.readScriptScreenshot() } }
        }.font(.system(size: 10)).disabled(s.busy)
    }
    func imageStrip(_ images: [Data], removable: Bool) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                    if let image = NSImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            Image(nsImage: image).resizable().scaledToFit().frame(width: 78, height: 60).background(panel, in: RoundedRectangle(cornerRadius: 6))
                            if removable { Button { s.attachments.remove(at: index) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).disabled(s.busy) }
                        }
                    }
                }
            }
        }.frame(height: 66)
    }
    func importScreenshots() {
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.png, .jpeg, .tiff]; picker.allowsMultipleSelection = true
        if picker.runModal() == .OK { for url in picker.urls { if let image = NSImage(contentsOf: url) { s.addScreenshot(image) } } }
    }
    var parseError: String? { do { _ = try ScriptParser.parse(s.project.script); return nil } catch { return error.localizedDescription } }
    func binding<T>(_ path: WritableKeyPath<Project, T>) -> Binding<T> { Binding(get: { s.project[keyPath: path] }, set: { s.update(path, $0) }) }
    func label(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary) }
    func suggestion(_ text: String) -> some View {
        Button { s.command = text } label: { HStack { Text(text).font(.system(size: 12)); Spacer(); Image(systemName: "arrow.up.left").font(.system(size: 10)).foregroundStyle(.secondary) }.padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
    }
    func permission(_ name: String, ready: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Image(systemName: ready ? "checkmark.circle.fill" : "circle").foregroundStyle(ready ? accent : .secondary); Text(name).font(.system(size: 11)); Spacer(); if !ready { Text("Enable").font(.system(size: 9)).foregroundStyle(accent) } } }.buttonStyle(.plain)
    }
    func importScript() {
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.plainText, .rtf, .html]; picker.allowsMultipleSelection = false
        if picker.runModal() == .OK, let url = picker.url {
            do {
                if ["rtf", "html", "htm"].contains(url.pathExtension.lowercased()) {
                    let value = try NSAttributedString(url: url, options: [:], documentAttributes: nil); s.update(\.script, RichScript.markdown(value))
                } else { s.update(\.script, try String(contentsOf: url, encoding: .utf8)) }
            } catch { s.error = error.localizedDescription }
        }
    }
    func importStyle() {
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.png, .jpeg]; picker.allowsMultipleSelection = false
        if picker.runModal() == .OK, let url = picker.url, let image = NSImage(contentsOf: url),
           let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            s.update(\.styleImage, png)
            if s.project.style.isEmpty { s.update(\.style, "Use the exact appearance of this project's style reference. Ask if ambiguous.") }
        }
    }
}

final class CropState: ObservableObject { @Published var selection: CGRect? }

struct CaptureView: View {
    let image: CGImage
    let action: AgentAction?
    let onCrop: (CGRect) -> Void
    @StateObject private var crop = CropState()
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1).resizable().frame(width: geo.size.width, height: geo.size.height)
                if let selection = crop.selection { Rectangle().fill(accent.opacity(0.18)).overlay(Rectangle().stroke(accent, lineWidth: 2)).frame(width: selection.width, height: selection.height).offset(x: selection.minX, y: selection.minY) }
                if let action, ["click", "doubleClick", "drag", "scroll"].contains(action.kind) {
                    Circle().stroke(.orange, lineWidth: 2).background(Circle().fill(.orange.opacity(0.2))).frame(width: 20, height: 20).offset(x: action.x * geo.size.width - 10, y: action.y * geo.size.height - 10).allowsHitTesting(false)
                }
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 3).onChanged { v in
                crop.selection = rect(v.startLocation, v.location).intersection(CGRect(origin: .zero, size: geo.size))
            }.onEnded { _ in
                if let selection = crop.selection { onCrop(CGRect(x: selection.minX / geo.size.width, y: selection.minY / geo.size.height, width: selection.width / geo.size.width, height: selection.height / geo.size.height)) }
                crop.selection = nil
            })
        }.aspectRatio(CGFloat(image.width) / CGFloat(image.height), contentMode: .fit)
    }
    func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect { CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)) }
}

struct PermissionsView: View {
    @EnvironmentObject var s: Store
    @State private var resetting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Two macOS permissions").font(.system(size: 24, weight: .semibold))
            Text("macOS shows its own popup only once. If it never appeared, or you dismissed it, open System Settings and tick Edit Assist by hand.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            row("Screen recording", "Lets Edit Assist see the window you are editing in.", ready: s.screenAllowed,
                ask: { s.desktop.requestCapture(); s.refreshPermissions() }, settings: { s.desktop.openScreenSettings() })
            row("Mouse & keyboard", "Listed as Accessibility. Lets Edit Assist click and press keys for you.", ready: s.controlAllowed,
                ask: { s.desktop.requestControl(); s.refreshPermissions() }, settings: { s.desktop.openControlSettings() })
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Ticked the box but it still says Not allowed?").font(.system(size: 12, weight: .semibold))
                Text("Screen recording is read once at launch, so a running app never sees a grant you just made — use Quit & reopen. If it is still wrong afterwards, the row in System Settings is an orphan left by an older copy of the app, and no amount of ticking it will match. Reset & re-register deletes those rows so macOS asks you cleanly.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                Text("THIS COPY").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Text(s.desktop.bundlePath).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                let signing = s.desktop.signingSummary
                if signing.stable {
                    Text("Signed as “\(signing.name)”. Permissions stay granted across rebuilds.")
                        .font(.system(size: 10)).foregroundStyle(accent)
                } else {
                    Text("Ad-hoc signed, so macOS drops permissions on every rebuild. Run ./setup-signing.sh, then ./build.sh.")
                        .font(.system(size: 10)).foregroundStyle(.orange).lineSpacing(2)
                }
                Text("In System Settings, approve the entry at this exact path. Remove older “Edit Assist” rows with the minus button.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(2)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            HStack {
                Button("Quit & reopen") { s.desktop.relaunch() }.buttonStyle(.borderedProminent)
                Button("Reset & re-register") { resetting = true }
                Button("Recheck") { s.refreshPermissions() }
                Spacer()
                Button("Done") { s.permissionsOpen = false }
            }
            .confirmationDialog("Reset Edit Assist's permissions?", isPresented: $resetting, titleVisibility: .visible) {
                Button("Reset and reopen", role: .destructive) { s.desktop.resetPermissions() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Removes Edit Assist from Screen recording and Accessibility, then reopens the app so macOS can ask again. Only this app is affected.")
            }
        }.padding(30).frame(width: 530).background(canvasBackground).tint(accent)
    }

    func row(_ name: String, _ detail: String, ready: Bool, ask: @escaping () -> Void, settings: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 18)).foregroundStyle(ready ? accent : .orange).frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(name).font(.system(size: 13, weight: .semibold))
                    Text(ready ? "Allowed" : "Not allowed").font(.system(size: 9, weight: .bold)).tracking(0.8)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background((ready ? accent : Color.orange).opacity(0.18), in: Capsule())
                        .foregroundStyle(ready ? accent : .orange)
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                if !ready {
                    HStack(spacing: 8) {
                        Button("Ask macOS", action: ask)
                        Button("Open System Settings", action: settings).buttonStyle(.borderedProminent)
                    }.font(.system(size: 11)).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(panel, in: RoundedRectangle(cornerRadius: 11))
    }
}

struct ConnectionView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose your assistant").font(.system(size: 24, weight: .semibold))
            Text("Uses your existing CLI login. No API key setup in Edit Assist.").font(.system(size: 12)).foregroundStyle(.secondary)
            Picker("Assistant", selection: $s.provider) {
                ForEach(CLIProvider.allCases) { provider in Text(provider.rawValue).tag(provider.rawValue) }
            }.pickerStyle(.segmented).onChange(of: s.provider) { _, _ in s.model = "" }
            ForEach(CLIProvider.allCases) { provider in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: provider.executable == nil ? "circle" : "checkmark.circle.fill").foregroundStyle(provider.executable == nil ? .secondary : accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(provider.rawValue + " CLI").font(.system(size: 12, weight: .semibold))
                        Text(provider.executable?.path ?? "Not installed").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        Text(provider.speedNote).font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            TextField("Model override (optional — CLI default)", text: $s.model).textFieldStyle(.roundedBorder)
            if let fastest = CLIProvider(rawValue: s.provider)?.fastestModel {
                HStack(spacing: 8) {
                    Button("Use fastest model") { s.model = fastest }.font(.system(size: 10))
                    Text("Sets \(fastest), roughly a third of the default's time per step.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if let provider = CLIProvider(rawValue: s.provider) {
                Text("If sign-in is needed, run “\(provider.loginHint)” in Terminal. Installed status does not confirm login.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("The selected CLI receives the script and any captured images. Its account limits and data policies apply. Only one assistant is called per step.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            HStack { Spacer(); Button("Use \(s.provider)") { s.saveConnection() }.buttonStyle(.borderedProminent) }
        }.padding(30).frame(width: 490).background(canvasBackground).tint(accent)
    }
}
