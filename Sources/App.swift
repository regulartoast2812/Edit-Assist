import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Quit always quits. With a sheet open (the permission setup, at every first launch) SwiftUI cancelled a
/// quit ("User canceled") before any delegate was asked, so macOS's own "Quit & Reopen" after turning on
/// Screen recording did nothing and the installer had to force-quit. The quit request itself (from macOS,
/// the installer, or ⌘Q) now saves and exits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Saves projects and settings; set by the app once its store exists.
    static var save: (() -> Void)?
    static func quitNow() {
        save?()
        UserDefaults.standard.synchronize()
        exit(0)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleQuit(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEQuitApplication))
    }
    @objc func handleQuit(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) { AppDelegate.quitNow() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateNow }
}

@main
struct EditAssistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store()

    init() {
        // Only one Edit Assist: a second copy brings the running one forward and quits before it starts.
        let me = ProcessInfo.processInfo.processIdentifier
        if let id = Bundle.main.bundleIdentifier,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.processIdentifier != me && !$0.isTerminated }) {
            running.activate()
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup("Edit Assist") {
            ContentView().environmentObject(store)
                .frame(minWidth: 1120, minHeight: 760)
                .preferredColorScheme(.dark)
                .onAppear { ClickOutsideEndsEditing.install(); AppDelegate.save = { [weak store] in store?.save() } }
        }
        .defaultSize(width: 1360, height: 880)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button(L("Quit Edit Assist")) { AppDelegate.quitNow() }.keyboardShortcut("q")
            }
            // Not while something runs: a new project stops the run.
            CommandGroup(replacing: .newItem) { Button(L("New project")) { store.addProject() }.keyboardShortcut("n").disabled(store.busy) }
            // The assistant is hidden for now (Store.assistantHidden); this menu keeps Stop and Permissions.
            CommandMenu("Edit Assist") {
                Button(L("Stop")) { store.stop() }.keyboardShortcut(".", modifiers: .command)
                Button(L("Permissions…")) { store.openPermissions() }.keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}

/// A click anywhere outside the text field being edited ends the edit and keeps what was typed. macOS
/// leaves a field in edit mode when you click empty space, which left the font size step box stuck with
/// its cursor; Return ends it too. Only one-line fields: the script and message editors keep their focus.
@MainActor
enum ClickOutsideEndsEditing {
    private static var monitor: Any?
    static func install() {
        // Nothing starts in edit mode: the window otherwise focused the first field (the font size step) at launch,
        // so keys typed then went into it.
        for delay in [0.1, 0.5] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { NSApp.keyWindow?.makeFirstResponder(nil) } }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if let window = event.window, let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
               let field = editor.delegate as? NSView {
                let point = field.convert(event.locationInWindow, from: nil)
                if !field.bounds.contains(point) { window.makeFirstResponder(nil) }
            }
            return event
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
    @State private var logOpen = false
    @State private var renaming = false
    /// The script tab being renamed, its name as typed, and the one waiting for you to confirm removing it.
    @State private var renamingScript: UUID?
    @State private var scriptNameDraft = ""
    @State private var removingScript: ScriptTab?
    /// The script tab being dragged to another place.
    @State private var draggingScript: UUID?
    /// The sidebar row being dragged ("project:…", "function:…", "helper:…"), and your order of functions and helpers.
    @State private var draggingRow: String?
    @AppStorage("functionOrder") private var functionOrder = ""
    @AppStorage("helperOrder") private var helperOrder = ""
    @State private var renamingTitle = false
    @FocusState private var titleFocused: Bool
    /// Ends renaming in the header; an emptied name goes back to the default rather than leaving no title.
    func endTitleEdit() {
        if s.project.name.trimmingCharacters(in: .whitespaces).isEmpty { binding(\.name).wrappedValue = "Untitled project" }
        renamingTitle = false; titleFocused = false
    }
    @State private var settingsDestination: String?
    /// The sidebar folded to a rail of icons (you asked for it, 2026-11-11); remembered across launches.
    @AppStorage("sidebarCollapsed") private var sidebarCollapsed = false
    /// The rail item under the pointer, the one whose card shows, where it is, and whether the pointer is on the card.
    @State private var railPointer: String?
    @State private var railCard: String?
    @State private var railFrame: CGRect = .zero
    @State private var railCardHovered = false
    static let railWidth: CGFloat = 64
    var body: some View {
        HStack(spacing: 0) {
            Group { if sidebarCollapsed { rail } else { sidebar } }
                .frame(width: sidebarCollapsed ? Self.railWidth : 224)
                // The page remembered from last time (Store.tab), if it's still here; else the function's page.
                .onAppear { if !(["function", "project", "Assistant"] + Self.helpers.map(\.tab)).contains(s.tab) { s.tab = "function" } }
            Divider()
            VStack(spacing: 0) {
                // A helper's page has no project header: the project and detection are for functions (you asked, 2026-11-11).
                if !Self.helpers.contains(where: { $0.tab == s.tab }) {
                    header
                    Divider()
                }
                // The run bar belongs to functions: a helper's page shows it only while a function runs, to pause or stop it.
                if !Self.helpers.contains(where: { $0.tab == s.tab }) || s.busy {
                    footer
                    Divider()
                }
                if !s.permissionsReady { permissionBanner; Divider() }
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .firstTextBaseline) {
                            if s.tab == "Assistant" {
                                Text(md: L("Assistant")).font(.system(size: 22, weight: .semibold))
                            } else if s.tab == "project" {
                                // The name and editor are in the header above; renaming is here, on request.
                                if renaming {
                                    TextField(L("Project name"), text: binding(\.name))
                                        .textFieldStyle(.roundedBorder).font(.system(size: 18, weight: .semibold)).frame(maxWidth: 360)
                                        .onSubmit { renaming = false }
                                    Button(L("Done")) { renaming = false }
                                } else {
                                    Label(L("Project"), systemImage: "film.stack").font(.system(size: 22, weight: .semibold))
                                    Button { renaming = true } label: { Image(systemName: "pencil") }
                                        .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Rename project")).disabled(s.busy)
                                }
                            } else if ["amir", "tala", "bo", "pix", "don", "kino", "penny", "sage"].contains(s.tab) {
                                Text(md: L(["amir": "Amir", "tala": "Tala", "bo": "Bo", "pix": "Pix", "don": "Don", "kino": "Kino", "penny": "Penny", "sage": "Sage"][s.tab] ?? "")).font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(theme)
                            } else {
                                Label(L(s.function.title), systemImage: s.function.icon).font(.system(size: 22, weight: .semibold))
                            }
                            Spacer()
                            Button { contextOpen.toggle() } label: { Label(L("Context"), systemImage: "sidebar.right") }
                                .tint(contextOpen ? theme : .secondary)
                        }
                        if s.tab == "Assistant" { conversation }
                        else if s.tab == "project" { projectPage }
                        else if s.tab == "amir" { AmirPage(watcher: s.amir) }
                        else if s.tab == "tala" { TalaPage(voice: s.tala, project: s.project) }
                        else if s.tab == "bo" { BoPage(watcher: s.bo) }
                        else if s.tab == "pix" { PixPage(desk: s.studio.pix, don: s.studio.don, project: s.project) }
                        else if s.tab == "don" { DonPage(don: s.studio.don, project: s.project) }
                        else if s.tab == "kino" { KinoPage(desk: s.kino, project: s.project) }
                        else if s.tab == "penny" { PennyPage(desk: s.penny) }
                        else if s.tab == "sage" { SagePage(desk: s.sage) }
                        else { page(for: s.function) }
                    }.padding(24).frame(minWidth: 450, maxWidth: .infinity).tint(theme)
                    if contextOpen {
                        Divider()
                        inspector.padding(20).frame(width: 300)
                    }
                }
            }
        }
        .coordinateSpace(.named("window"))
        // The folded sidebar's card: the item in full beside its icon while the pointer is on either.
        .overlay(alignment: .topLeading) {
            if sidebarCollapsed, let key = railCard {
                GeometryReader { window in
                    railCardView(key)
                        .onHover { inside in railCardHovered = inside; if !inside { hideRailCardSoon() } }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 236)
                        .offset(x: Self.railWidth + 6, y: max(8, min(railFrame.minY - 6, window.size.height - 150)))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: railCard)
        .overlayPreferenceValue(GuideTargets.self) { anchors in GuideOverlay(anchors: anchors).environmentObject(s) }
        // Bo asking you to rebuild an account Finder has stopped showing properly.
        .modifier(BoReconnectDialog(watcher: s.bo, busy: s.busy))
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
        // Restarting: the whole window greys out at once, so the click visibly took.
        .overlay {
            if s.restarting {
                ZStack {
                    Color.black.opacity(0.55)
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.large)
                        Text(md: L("Restarting Edit Assist…")).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    }
                }.ignoresSafeArea()
            }
        }
        .sheet(isPresented: $s.showScriptDraft) {
            VStack(alignment: .leading, spacing: 15) {
                Text(md: L("Review the extracted script")).font(.title2)
                Text(md: L("Check the wording and **bold phrases** against your screenshot before applying.")).foregroundStyle(.secondary)
                TextEditor(text: Binding(get: { s.scriptDraft ?? "" }, set: { s.scriptDraft = $0 })).font(.system(size: 13, design: .monospaced)).frame(minHeight: 320)
                HStack { Button(L("Discard")) { s.scriptDraft = nil; s.showScriptDraft = false }; Spacer(); Button(L("Use this script")) { s.applyScriptDraft() }.buttonStyle(.borderedProminent) }
            }.padding(25).frame(width: 620)
        }
        .alert(L("Edit Assist"), isPresented: Binding(get: { s.error != nil }, set: { if !$0 { s.error = nil } })) {
            Button(L("OK")) { s.error = nil }
        } message: { Text(L(s.error ?? "")) }
        // A new version: offered once; Later leaves it in the sidebar.
        .alert(L("Update available"), isPresented: Binding(get: { s.updatePromptOpen }, set: { if !$0 { s.updatePromptOpen = false } })) {
            Button(L("Update now")) { s.updatePromptOpen = false; s.installUpdate() }
            Button(L("Later"), role: .cancel) { s.declineUpdate() }
        } message: {
            Text(L("Edit Assist %@ is available (you have %@).\n\nIt takes a few seconds and reopens the app. Your projects stay as they are.",
                   s.update?.label ?? "", Updater.current))
        }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.motionlines").font(.system(size: 26)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(md: L("EDIT ASSIST")).font(.system(size: 14, weight: .heavy, design: .rounded)).tracking(1.3)
                    Text(md: L("Your editing companion")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { withAnimation(.easeOut(duration: 0.18)) { sidebarCollapsed = true } } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).help(L("Fold the sidebar to icons"))
            }.padding(.top, 14)
            // Projects, functions and helpers scroll when the window is too short for them all; the rest stays put.
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { label(L("PROJECTS")); Spacer(); Button { s.addProject() } label: { Image(systemName: "plus") }.buttonStyle(.plain).disabled(s.busy) }
                        ForEach(s.projects) { project in
                            projectRow(project)
                                .guideTarget(project.id == s.selected ? "project" : "other-project")
                                .sidebarDraggable("project:" + project.id.uuidString, dragging: $draggingRow, disabled: s.busy) { id in
                                    guard let moved = UUID(uuidString: id), let place = s.projects.firstIndex(where: { $0.id == project.id }) else { return }
                                    s.moveProject(moved, to: place)
                                }
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        label(L("FUNCTIONS"))
                        ForEach(SidebarOrder.ordered(EditFunction.allCases.map(\.rawValue), saved: functionOrder).compactMap(EditFunction.init)) { job in
                            functionRow(job).sidebarDraggable("function:" + job.rawValue, dragging: $draggingRow) { id in
                                functionOrder = SidebarOrder.moved(id, to: job.rawValue, in: SidebarOrder.ordered(EditFunction.allCases.map(\.rawValue), saved: functionOrder))
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        label(L("HELPERS"))
                        ForEach(SidebarOrder.ordered(Self.helpers.map(\.tab), saved: helperOrder), id: \.self) { tab in
                            helper(tab).sidebarDraggable("helper:" + tab, dragging: $draggingRow) { id in
                                helperOrder = SidebarOrder.moved(id, to: tab, in: SidebarOrder.ordered(Self.helpers.map(\.tab), saved: helperOrder))
                            }
                        }
                    }
                }
            }.scrollIndicators(.never)
            if let update = s.update {
                // Until it is installed: a newer version, one click away.
                Button { s.installUpdate() } label: {
                    HStack(spacing: 9) {
                        Image(systemName: s.installingUpdate ? "hourglass" : "arrow.down.circle.fill").font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L(s.installingUpdate ? "Installing the update…" : "Update to latest version")).font(.system(size: 12, weight: .semibold))
                            Text(update.label).font(.system(size: 10)).opacity(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(accent).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(s.busy || s.installingUpdate)
                    .help(s.busy ? L("Finish or stop the run first") : L("Download and install, then reopen Edit Assist"))
            }
            Button { settingsOpen = true } label: {
                Label(L("Settings"), systemImage: "gearshape").font(.system(size: 12))
            }.buttonStyle(.plain)
            Button { techStackOpen = true } label: {
                Label(L("Tech stack"), systemImage: "square.stack.3d.up").font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            // A walk-through of a function, pointing at its controls.
            Menu {
                ForEach(EditFunction.allCases) { job in Button(L(job.title)) { s.startGuide(job) } }
            } label: {
                Label(L("Guide"), systemImage: "questionmark.circle").font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(s.busy).tint(.primary)
            // The error log: glows in the colour of the worst new problem until it is opened.
            LogSidebarItem(open: $logOpen).environmentObject(s)
                .popover(isPresented: $logOpen, arrowEdge: .trailing) { ErrorLogView().environmentObject(s) }
                .guideTarget("log")
            Text(md: L("Edit Assist · Preview")).font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(18).background(panel.opacity(0.55))
    }

    /// A project in the sidebar (and in the folded sidebar's card): opens its page.
    func projectRow(_ project: Project) -> some View {
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

    /// The sidebar folded: one icon per project, function and helper, in the same order; hovering one shows it in full
    /// beside the rail (its card works like the row: Run, Pause, open the page). The logo opens the sidebar again.
    var rail: some View {
        VStack(spacing: 12) {
            Button { withAnimation(.easeOut(duration: 0.18)) { railCard = nil; sidebarCollapsed = false } } label: {
                Image(systemName: "cursorarrow.motionlines").font(.system(size: 22)).foregroundStyle(accent)
                    .frame(width: 40, height: 36).contentShape(Rectangle())
            }.buttonStyle(.plain).help(L("Open the sidebar")).padding(.top, 14)
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(s.projects) { project in
                        let on = s.selected == project.id
                        Button { if !on { s.select(project.id) }; s.tab = "project" } label: {
                            railTile(selected: on && s.tab == "project", color: accent, lit: on) {
                                Text(Self.monogram(project.name)).font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                        }.buttonStyle(.plain).disabled(s.busy)
                            .railHover("project:" + project.id.uuidString, in: self)
                            .guideTarget(on ? "project" : "other-project")
                            .sidebarDraggable("project:" + project.id.uuidString, dragging: $draggingRow, disabled: s.busy) { id in
                                guard let moved = UUID(uuidString: id), let place = s.projects.firstIndex(where: { $0.id == project.id }) else { return }
                                s.moveProject(moved, to: place)
                            }
                    }
                    Button { s.addProject() } label: {
                        Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 40, height: 26).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(s.busy).help(L("New project"))
                    Divider().padding(.horizontal, 6).padding(.vertical, 5)
                    let functions = SidebarOrder.ordered(EditFunction.allCases.map(\.rawValue), saved: functionOrder)
                    ForEach(functions.compactMap(EditFunction.init)) { job in
                        railFunction(job)
                            .railHover("function:" + job.rawValue, in: self)
                            .guideTarget(job == s.function ? "function" : "other-function")
                            .sidebarDraggable("function:" + job.rawValue, dragging: $draggingRow) { id in
                                functionOrder = SidebarOrder.moved(id, to: job.rawValue, in: functions)
                            }
                    }
                    Divider().padding(.horizontal, 6).padding(.vertical, 5)
                    let helpers = SidebarOrder.ordered(Self.helpers.map(\.tab), saved: helperOrder)
                    ForEach(helpers, id: \.self) { tab in
                        let color = Self.helperThemes[tab] ?? accent
                        Button { s.tab = tab } label: {
                            railTile(selected: s.tab == tab, color: color, lit: s.tab == tab) { helperIcon(tab) }
                        }.buttonStyle(.plain)
                            .railHover("helper:" + tab, in: self)
                            .sidebarDraggable("helper:" + tab, dragging: $draggingRow) { id in
                                helperOrder = SidebarOrder.moved(id, to: tab, in: helpers)
                            }
                    }
                }.padding(.vertical, 2)
            }.scrollIndicators(.never)
            VStack(spacing: 6) {
                if s.update != nil {
                    Button { s.installUpdate() } label: {
                        Image(systemName: s.installingUpdate ? "hourglass" : "arrow.down.circle.fill").font(.system(size: 16)).foregroundStyle(accent)
                            .frame(width: 40, height: 32).background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).disabled(s.busy || s.installingUpdate).railHover("note:" + L("Update to latest version"), in: self)
                }
                Button { settingsOpen = true } label: { railIcon("gearshape") }.buttonStyle(.plain).railHover("note:" + L("Settings"), in: self)
                Button { techStackOpen = true } label: { railIcon("square.stack.3d.up") }.buttonStyle(.plain).railHover("note:" + L("Tech stack"), in: self)
                Menu {
                    ForEach(EditFunction.allCases) { job in Button(L(job.title)) { s.startGuide(job) } }
                } label: { railIcon("questionmark.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(s.busy).tint(.primary)
                    .railHover("note:" + L("Guide"), in: self)
                LogSidebarItem(open: $logOpen, compact: true).environmentObject(s)
                    .popover(isPresented: $logOpen, arrowEdge: .trailing) { ErrorLogView().environmentObject(s) }
                    .guideTarget("log").railHover("note:" + L("Log"), in: self)
            }
        }.padding(.horizontal, 10).padding(.bottom, 14).frame(maxWidth: .infinity).background(panel.opacity(0.55))
    }

    /// A project's initials for the rail ("Shelara" → "Sh", "Crafty Hold" → "CH").
    static func monogram(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" }).filter { $0.first?.isLetter == true || $0.first?.isNumber == true }
        if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        return words.first.map { $0.prefix(1).uppercased() + $0.dropFirst().prefix(1).lowercased() } ?? "?"
    }

    func railIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 40, height: 30).contentShape(Rectangle())
    }

    func railTile<Content: View>(selected: Bool, color: Color, lit: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 40, height: 40)
            .background(color.opacity(selected ? 0.16 : lit ? 0.07 : 0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(selected ? 0.4 : 0), lineWidth: 1))
            .foregroundStyle(selected || lit ? color : .secondary)
            .contentShape(Rectangle())
    }

    /// A function on the rail: its icon inside a ring of its progress; while it runs, the icon pauses and continues it.
    func railFunction(_ job: EditFunction) -> some View {
        let showing = s.tab == "function" && s.function == job
        let running = s.activeFunction == job
        let tint: Color = running && s.runPaused ? .orange : accent
        return Button { if running { s.toggleRunPause() } else { s.function = job; s.tab = "function" } } label: {
            railTile(selected: showing, color: accent, lit: running) {
                ZStack {
                    Circle().stroke(.white.opacity(0.08), lineWidth: 2.5)
                    Circle().trim(from: 0, to: s.progress(of: job).fraction).stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: running ? (s.runPaused ? "play.fill" : "pause.fill") : job.icon).font(.system(size: running ? 10 : 12))
                        .foregroundStyle(running ? tint : showing ? accent : .secondary)
                }.frame(width: 28, height: 28)
            }
        }.buttonStyle(.plain)
    }

    /// What the card beside the rail shows: the row itself for a project, function or helper, else the item's name.
    @ViewBuilder func railCardView(_ key: String) -> some View {
        let kind = String(key.prefix { $0 != ":" })
        let id = String(key.drop { $0 != ":" }.dropFirst())
        Group {
            if kind == "function", let job = EditFunction(rawValue: id) {
                functionRow(job)
            } else if kind == "helper" {
                helper(id)
            } else if kind == "project", let uuid = UUID(uuidString: id), let project = s.projects.first(where: { $0.id == uuid }) {
                projectRow(project)
            } else {
                Text(id).font(.system(size: 12, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(6)
        .background(panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.09), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 4)
    }

    /// The pointer on a rail item shows its card at once; leaving it (and the card) hides the card a moment later,
    /// so the pointer can cross the gap onto the card to press Run.
    func railEnter(_ key: String, frame: CGRect) { railPointer = key; railCard = key; railFrame = frame }
    func railLeave(_ key: String) { if railPointer == key { railPointer = nil }; hideRailCardSoon() }
    func hideRailCardSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if railPointer == nil && !railCardHovered { railCard = nil }
        }
    }

    private var techStackSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(md: L("Tech stack")).font(.title2.weight(.semibold))
            techStackRow("Swift · SwiftUI · AppKit", purpose: "Native macOS app")
            techStackRow("ScreenCaptureKit", purpose: "Live window capture")
            techStackRow("Apple Vision", purpose: "On-device text recognition")
            techStackRow("Core Graphics", purpose: "Image analysis · mouse & keyboard")
            techStackRow("Rules · local JSON", purpose: "Workflow logic · project memory")
            techStackRow("\(s.provider) CLI", purpose: "Optional AI assistant")
            HStack { Spacer(); Button(L("Done")) { techStackOpen = false }.buttonStyle(.borderedProminent) }
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
                // Click the name to rename it here. Plain text until clicked: an always-editable field took keyboard
                // focus at launch and looked stuck in editing. Return, Escape or clicking elsewhere ends the edit.
                if renamingTitle {
                    TextField(L("Project name"), text: binding(\.name))
                        .textFieldStyle(.plain).font(.system(size: 23, weight: .semibold)).frame(maxWidth: 420)
                        .focused($titleFocused)
                        .onSubmit { endTitleEdit() }
                        .onExitCommand { endTitleEdit() }
                        .onChange(of: titleFocused) { _, focused in if !focused { endTitleEdit() } }
                        .onAppear { titleFocused = true }
                } else {
                    HStack(spacing: 8) {
                        Text(s.project.name).font(.system(size: 23, weight: .semibold)).lineLimit(1)
                        Image(systemName: "pencil").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if !s.busy { renamingTitle = true } }
                    .help(L("Rename project"))
                }
                Text(s.target.map { L("Editing in %@ · %@", $0.app, ($0.title as NSString).lastPathComponent) } ?? L("Open Premiere or After Effects to connect"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).guideTarget("editor")
            }
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: s.detectionLevel == .off ? "eye.slash" : "eye").foregroundStyle(s.detectionLevel == .off ? Color.secondary : accent)
                        .guideTarget("detection")
                    // Off · During runs (only while a function runs) · Always (the live overlay too).
                    Picker(L("Detection"), selection: Binding(get: { s.detectionLevel }, set: { s.detectionLevel = $0 })) {
                        ForEach(Store.DetectionLevel.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                        .help(L("Off: no boxes. During runs: boxes only while a function runs. Always: the live overlay as well."))
                    Button { detectionSettingsOpen.toggle() } label: { Image(systemName: "chevron.down") }
                        .help(L("Detection settings")).popover(isPresented: $detectionSettingsOpen) { detectionControls }
                }.controlSize(.small)
                Text(L(!s.detectionEnabled ? "Detection off" : s.detectionMode ? s.detectionStatus : s.running ? "Showing this run's detection" : "Shows while a function runs"))
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
                    Text(md: L("Edit Assist cannot see your editor or act in it until macOS allows this.")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(md: L("Fix now")).font(.system(size: 11, weight: .semibold))
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
                    Text(md: L("What are we working on?")).font(.system(size: 25, weight: .semibold))
                    Text(md: L("Give me the project’s style and tell me what to handle. I’ll keep those choices with this project.")).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5)
                    VStack(alignment: .leading, spacing: 11) {
                        suggestion("Use the blue outline style for this project.")
                        suggestion("Only highlight bold phrases in the selected caption.")
                        suggestion("Explain the next step before you click.")
                    }.padding(.top, 7)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(panel, in: RoundedRectangle(cornerRadius: 16))
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ThinScrollView {
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
                Text(md: L("Tell your assistant what to do · ⌘V also pastes screenshots")).font(.system(size: 10)).foregroundStyle(.secondary)
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

    /// The script: one toolbar, the editor as the page's main thing, one line of help, then the phrases it gives.
    var script: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { s.pasteScript() } label: { Label(L("Paste formatted text"), systemImage: "doc.on.clipboard") }
                    .buttonStyle(.borderedProminent)
                Button(L("Import…")) { importScript() }
                Divider().frame(height: 18).padding(.horizontal, 4)
                Button { (NSApp.keyWindow?.firstResponder as? RichScriptTextView)?.toggleHighlight() } label: { Label(L("Highlight"), systemImage: "bold") }
                    .help(L("Select words, then click here or press ⌘B to highlight them or take the highlight off"))
                Button { RichScriptTextView.current?.flipHighlights() } label: { Label(L("Flip"), systemImage: "arrow.left.arrow.right") }
                    .help(L("Highlight everything that is not highlighted now, and the reverse. ⌘Z undoes it."))
                Spacer()
                if s.project.script.isEmpty { Button(L("Use your example")) { s.sample() }.buttonStyle(.plain).foregroundStyle(accent) }
            }.font(.system(size: 12)).controlSize(.regular).disabled(s.busy)
            RichScriptEditor(text: binding(\.script), editable: !s.busy)
                .padding(12).background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.06)))
                .frame(minHeight: 300).disabled(s.busy)
            if !s.project.script.isEmpty && s.targetCount == 0 {
                Text(md: L("No bold phrases found in the script.\n→ Select phrases and press ⌘B, or paste again with Paste formatted text.")).font(.system(size: 11)).foregroundStyle(.orange)
            } else {
                Text(md: L("Bold in what you paste becomes the phrases, in green. ⌘B highlights a selection · ⌘Z undoes."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let error = parseError { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
        }
    }

    /// The project's scripts, one tab each, where the card's title was: click to open one, double-click or right-click to
    /// rename, drag to put it somewhere else (the others slide aside as it passes), + for a new one. A run works on the open one.
    var scriptTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(s.project.scriptTabs) { tab in scriptTab(tab) }
                Button { s.addScript() } label: { Image(systemName: "plus").frame(width: 26, height: 26).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(L("New script"))
            }
        }
        .scrollIndicators(.never).disabled(s.busy)
        .confirmationDialog(L("Remove “%@”?", removingScript?.name ?? ""), isPresented: Binding(get: { removingScript != nil }, set: { if !$0 { removingScript = nil } })) {
            Button(L("Remove script"), role: .destructive) { if let tab = removingScript { s.removeScript(tab.id) }; removingScript = nil }
        } message: { Text(md: L("Its text and progress go. A copy is kept in Backups.")) }
    }

    func scriptTab(_ tab: ScriptTab) -> some View {
        let open = tab.id == s.project.openScript.id
        return Group {
            if renamingScript == tab.id {
                TextField(L("Script name"), text: $scriptNameDraft)
                    .textFieldStyle(.plain).font(.system(size: 14, weight: .semibold)).frame(width: 140)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit { s.renameScript(tab.id, to: scriptNameDraft); renamingScript = nil }
                    .onExitCommand { renamingScript = nil }
            } else {
                Button { s.openScript(tab.id) } label: {
                    Text(tab.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(open ? accent.opacity(0.16) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(open ? accent : .secondary).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture(count: 2).onEnded { scriptNameDraft = tab.name; renamingScript = tab.id })
                .onDrag { draggingScript = tab.id; return NSItemProvider(object: tab.id.uuidString as NSString) }
                .onDrop(of: [.text], delegate: ScriptTabDrop(target: tab.id, dragging: $draggingScript) { id in
                    guard let place = s.project.scriptTabs.firstIndex(where: { $0.id == tab.id }) else { return }
                    withAnimation(.easeOut(duration: 0.15)) { s.moveScript(id, to: place) }
                })
                .contextMenu {
                    Button(L("Rename")) { scriptNameDraft = tab.name; renamingScript = tab.id }
                    if s.project.scriptTabs.count > 1 {
                        Button(L("Remove…"), role: .destructive) {
                            if tab.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { s.removeScript(tab.id) } else { removingScript = tab }
                        }
                    }
                }
            }
        }
    }

    /// The phrases the script gives, numbered, as chips: what every function will highlight.
    var phraseChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(s.targets.enumerated()), id: \.offset) { index, phrase in
                HStack(spacing: 6) {
                    Text("\(index + 1)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.black.opacity(0.7))
                        .frame(minWidth: 16).padding(.vertical, 1).background(accent.opacity(0.85), in: Capsule())
                    Text(phrase.trimmingCharacters(in: .whitespaces)).font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                }
                .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 5)
                .background(accent.opacity(0.10), in: Capsule())
            }
        }
    }

    var phraseList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let next = s.nextTarget {
                HStack(spacing: 8) {
                    Text(md: L("NEXT")).font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
                    Text("“\(next)”").font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                    Spacer()
                    Text(md: L("whichever phrase is on screen goes first")).font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.bottom, 4)
            }
            ForEach(Array(s.targets.enumerated()), id: \.offset) { _, phrase in
                PhraseRow(phrase: phrase).environmentObject(s)
            }
            // Only when there is progress to clear.
            if !s.project.styledWords(graphics: s.progressGraphics).isEmpty {
                HStack {
                    Spacer()
                    Button(L("Reset progress")) { s.resetProgress() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).disabled(s.busy)
                }.padding(.top, 4)
            }
        }
    }

    var stages: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(md: L("In order, for every phrase. The boxes choose what Test selected stages does; a run follows Each phrase gets."))
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(L("All")) { s.steps = Set(OCRStep.allCases.map(\.rawValue)) }.font(.system(size: 10)).disabled(s.busy)
                Button(L("None")) { s.steps = [] }.font(.system(size: 10)).disabled(s.busy)
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
                        Text(L(step.label)).font(.system(size: 12, weight: .semibold))
                        Text(L(step.detail)).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
            Text(md: L("A routine you can teach")).font(.system(size: 23, weight: .semibold))
            Text(md: L("OCR mode below needs no instructions at all. The routine text and confidence threshold apply only to model-driven runs from the footer.")).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            TextEditor(text: binding(\.routine)).font(.system(size: 13)).scrollContentBackground(.hidden).padding(12).background(panel, in: RoundedRectangle(cornerRadius: 12)).disabled(s.busy)
            label(L("CURRENT RUN"))
            TextField(L("What should this run do?"), text: $s.runInstruction, axis: .vertical).lineLimit(3...5).textFieldStyle(.roundedBorder).disabled(s.busy)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    label(L("PAUSE BELOW"))
                    Spacer()
                    Text("\(Int(s.minConfidence * 100))% confidence").font(.system(size: 11, design: .monospaced)).foregroundStyle(accent)
                }
                Slider(value: $s.minConfidence, in: 0.3...0.95, step: 0.05).disabled(s.busy)
                Text(md: L("The model scores its own certainty and is not well calibrated: sound decisions often report around 0.7. Raise this to stop more often and review, lower it to let the routine keep moving."))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(2)
            }
            Text(md: L("Starts from the current Adobe state. Pause playback first. Run pauses after 40 actions so you can review progress.")).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    var inspector: some View {
        ThinScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { label(L("SCREEN OBSERVATION")); Spacer(); Button(L("Capture"), systemImage: "camera") { s.capture() }.font(.system(size: 11)).disabled(s.busy || s.window == nil) }
                if let observation = s.observation {
                    CaptureView(image: observation.image, action: s.proposal?.action) { rect in s.rememberStyle(rect) }
                        .disabled(s.busy).clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(md: L("Drag a rectangle around your chosen style tile to remember its appearance.")).font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "viewfinder").font(.system(size: 30)).foregroundStyle(accent.opacity(0.65))
                        Text(md: L("Your Adobe window will appear here")).font(.system(size: 12))
                        Text(md: L("Capture to inspect it or teach a style.")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).frame(height: 190).background(panel, in: RoundedRectangle(cornerRadius: 12))
                }
                Divider()
                if let proposal = s.proposal {
                    Divider()
                    label(L("NEXT STEP / LAST DECISION"))
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
            label(L("ASSISTANT RUNS ONLY"))
            TextField(L("Describe the style for the assistant"), text: binding(\.style), axis: .vertical).font(.system(size: 12)).lineLimit(2...4).textFieldStyle(.roundedBorder).disabled(s.busy)
            HStack {
                Button(L("Import style reference…")) { importStyle() }
                Button(L("Choose from editor")) { contextOpen = true; s.capture() }.disabled(s.window == nil)
                if s.project.styleImage != nil { Button(L("Clear reference")) { s.update(\.styleImage, nil) } }
            }.font(.system(size: 10)).disabled(s.busy)
        }
    }

    var diagnostics: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(L("Dump OCR")) { s.dumpOCR() }.disabled(s.busy)
                Button(L("Test selected stages")) { s.runChecklist() }.disabled(s.busy || s.targets.isEmpty)
                Button(L("Select next phrase")) { s.runOCR(all: false) }.disabled(s.busy || s.nextTarget == nil)
                if !s.ocrOnly { Button(L("Preview assistant step")) { s.run(limit: 1, preview: true) }.disabled(s.busy) }
            }.font(.system(size: 11))
            Text(md: L("Stage tests do not record phrase progress. Logs show recognition and action results.")).font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            // Safeguard: a run that worked becomes a test every build replays, so a later change that
            // would decide differently on those screens is caught before it reaches a run.
            HStack(spacing: 10) {
                Toggle(L("Record the next run"), isOn: $s.recordNextRun).toggleStyle(.switch).controlSize(.small).disabled(s.busy)
                Spacer()
                if s.lastRecording != nil {
                    Button(L("Keep last recording as a test")) { s.keepLastRecording() }.font(.system(size: 11)).disabled(s.busy)
                }
            }
            Text("\(s.keptRecordings) recorded run\(s.keptRecordings == 1 ? "" : "s") kept as tests. Every build replays them and refuses to install if a decision changes.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Divider()
            HStack(spacing: 10) {
                Text("Edit Assist \(Updater.current)").font(.system(size: 11))
                Spacer()
                if s.update != nil { Button(L("Update now")) { s.installUpdate() }.font(.system(size: 11)).disabled(s.busy) }
                Button(L("Check for updates")) { s.checkForUpdates(manual: true) }.font(.system(size: 11))
            }
            if !s.updateStatus.isEmpty { Text(L(s.updateStatus)).font(.system(size: 10)).foregroundStyle(.secondary) }
            ForEach(Array(s.activity.suffix(30).enumerated()), id: \.offset) { _, entry in
                Text(entry).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    var settingsSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(md: L("Settings")).font(.title2.weight(.semibold))
            // The interface language; the activity log stays in English.
            HStack {
                Text(md: L("Language")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker(L("Language"), selection: Binding(get: { s.language }, set: { s.language = $0 })) {
                    ForEach(AppLanguage.allCases) { Text($0.name).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            Divider()
            Button(L("macOS permissions")) { settingsDestination = "permissions"; settingsOpen = false }
            Text(L(s.permissionsReady ? "Screen recording and mouse control are allowed." : s.missingPermissions))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack { Spacer(); Button(L("Done")) { settingsOpen = false }.buttonStyle(.borderedProminent) }
        }.padding(26).frame(width: 440)
    }

    var detectionControls: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(md: L("Detection settings")).font(.system(size: 16, weight: .semibold))
            // When detection shows is the header switch (Off · During runs · Always): two separate toggles here
            // could disagree with it.
            Picker(L("Show"), selection: Binding(get: { s.detectionLevel }, set: { s.detectionLevel = $0 })) {
                ForEach(Store.DetectionLevel.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) }
            }.pickerStyle(.segmented)
            Divider()
            label(L("SHOW ON SCREEN"))
            Toggle(L("Boxes"), isOn: $s.detectionBoxes)
            Toggle(L("Recognized text"), isOn: $s.detectionText)
            Toggle(L("Details and coordinates"), isOn: $s.detectionDetails)
            Divider()
            label(L("RECOGNIZE"))
            Toggle(L("Faces and bodies"), isOn: $s.detectPeople)
        }.toggleStyle(.switch).controlSize(.small).padding(22).frame(width: 290)
    }

    /// The helpers in their first order; the sidebar shows them in yours (drag to change it).
    static let helpers: [(tab: String, name: String, role: String)] = [
        ("amir", "Amir", "File helper"), ("tala", "Tala", "Voice helper"), ("bo", "Bo", "Drive helper"), ("pix", "Pix", "CTA & image helper"),
        ("don", "Don", "Ads expert"), ("kino", "Kino", "AI video helper"), ("penny", "Penny", "Numbers helper"),
        ("sage", "Sage", "Research helper"),
    ]
    @ViewBuilder func helper(_ tab: String) -> some View {
        if let helper = Self.helpers.first(where: { $0.tab == tab }) {
            helperRow(helper.tab, helper.name, helper.role) { helperIcon(tab) }
        }
    }
    /// A helper's pixel icon, alive as in its row (the sidebar and the folded rail both show it).
    @ViewBuilder func helperIcon(_ tab: String) -> some View {
        switch tab {
        case "amir": AmirIcon(watcher: s.amir)
        case "tala": PixelTala(pixel: 1.1)
        case "bo": BoIcon(watcher: s.bo)
        case "pix": PixIcon(desk: s.studio.pix)
        case "don": DonIcon(don: s.studio.don)
        case "kino": PixelKino(pixel: 1.25)
        case "sage": SageIcon(desk: s.sage)
        default: PennyIcon(desk: s.penny)
        }
    }

    /// One function in the sidebar: its name, where it stands, and a quick start on the right.
    /// A helper in the sidebar: its pixel icon, name and what it helps with, in its colour; opens its page.
    func helperRow<Icon: View>(_ tab: String, _ name: String, _ role: String, @ViewBuilder icon: () -> Icon) -> some View {
        let color = Self.helperThemes[tab] ?? accent
        return Button { s.tab = tab } label: {
            HStack(spacing: 10) {
                icon().frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(md: L(name)).font(.system(size: 12, weight: .medium))
                    Text(md: L(role)).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(s.tab == tab ? 0.14 : 0.04), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(color.opacity(s.tab == tab ? 0.35 : 0), lineWidth: 1))
            .foregroundStyle(s.tab == tab ? color : .secondary).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    /// Each helper's colour, the colour of their body: their sidebar button and page take it.
    static let helperThemes: [String: Color] = ["amir": PixelAmir.theme, "tala": PixelTala.theme, "bo": PixelBo.theme,
                                                "pix": PixelPix.theme, "don": PixelDon.theme, "kino": PixelKino.theme, "penny": PixelPenny.theme,
                                                "sage": PixelSage.theme]
    /// The page's colour: the helper's on a helper page, the app's anywhere else.
    var theme: Color { Self.helperThemes[s.tab] ?? accent }

    func functionRow(_ job: EditFunction) -> some View {
        let showing = s.tab == "function" && s.function == job
        let progress = s.progress(of: job)
        return HStack(spacing: 4) {
            Button { s.function = job; s.tab = "function" } label: {
                HStack(spacing: 8) {
                    Image(systemName: job.icon).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L(job.title)).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        HStack(spacing: 4) {
                            Text(s.activeFunction == job ? L(s.runPaused ? "Paused" : "Running…") : progress.total == 0 ? L("No script yet") : L("%@ of %@ done", s.project.completed(graphics: job == .highlightGraphics).count, s.targets.count))
                                .font(.system(size: 9)).lineLimit(1).fixedSize().foregroundStyle(s.activeFunction == job ? (s.runPaused ? .orange : accent) : .secondary)
                            // The script it works on: the one open in the project.
                            if job.highlightsPhrases { scriptPill(s.project.openScript.name) }
                        }
                    }.layoutPriority(1)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if s.activeFunction == job {
                Button { s.toggleRunPause() } label: {
                    Image(systemName: s.runPaused ? "play.fill" : "pause.fill").font(.system(size: 10))
                        .frame(width: 26, height: 26).background((s.runPaused ? Color.orange : accent).opacity(0.2), in: Circle())
                        .foregroundStyle(s.runPaused ? .orange : accent)
                }.buttonStyle(.plain).help(L(s.runPaused ? "Continue" : "Pause"))
            } else {
                Button { s.start(job) } label: {
                    Image(systemName: "play.fill").font(.system(size: 10))
                        .frame(width: 26, height: 26).background(accent.opacity(s.busy ? 0.06 : 0.2), in: Circle())
                        .foregroundStyle(s.busy ? Color.secondary : accent)
                }.buttonStyle(.plain).disabled(s.busy || (job.highlightsPhrases && s.ocrOnly && s.targets.isEmpty))
                    .help(s.busy ? L("Another function is running") : "\(L(job.runLabel)) — \(L(job.title))")
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
            .guideTarget(job == s.function ? "function" : "other-function")
    }

    @ViewBuilder func page(for job: EditFunction) -> some View {
        switch job {
        case .highlight, .highlightGraphics: highlightPage
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
                        Text(L(job.title)).font(.system(size: 12, weight: .semibold))
                        Text(L(s.running ? (s.runPaused ? "Paused" : "Running") : s.busy ? "Working" : "Ready"))
                            .font(.system(size: 9, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background((!s.running ? Color.secondary : s.runPaused ? .orange : accent).opacity(0.18), in: Capsule())
                            .foregroundStyle(!s.running ? Color.secondary : s.runPaused ? .orange : accent)
                    }
                    Text(L(s.status)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 12)
                Button { s.toggleRunPause() } label: { Label(L(s.runPaused ? "Continue" : "Pause"), systemImage: s.runPaused ? "play" : "pause") }
                    .disabled(!s.running).help(L("Pause between gestures; Continue resumes the same pass"))
                Button { s.stop() } label: { Label(L("Stop"), systemImage: "stop.fill") }.disabled(!s.busy).tint(.orange)
                Button { s.start(s.function) } label: { Label(L(s.function.runLabel), systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).guideTarget("run")
                    .disabled(s.busy || (s.function.highlightsPhrases && s.ocrOnly && s.targets.isEmpty))
                    .help(s.busy ? "\((s.activeFunction ?? s.function).title) is running; one function runs at a time" : "Start \(s.function.title.lowercased()) at the current playhead")
            }
            HStack(spacing: 10) {
                ProgressView(value: progress.fraction).tint(s.runPaused ? .orange : accent)
                Text(L("%@ of %@ phrases", s.doneCount, s.targets.count))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).fixedSize()
                if let left = s.timeLeft(of: job) {
                    Text(L("· about %@ left", left < 60 ? "\(Int(left.rounded())) s" : "\(Int((left / 60).rounded())) min"))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).fixedSize()
                }
            }
        }.padding(.horizontal, 24).padding(.vertical, 14).background(panel.opacity(0.6))
    }

    /// Highlight phrases: what to highlight, how, and how far it has got, on one page.
    /// Highlight phrases in two columns: the task on the left, how it is done on the right.
    /// The function page: Task and Setup side by side when there is room, one above the other when not (the
    /// Context panel open on a narrow window left too little width, and the page slid over the sidebar).
    var highlightPage: some View {
        GeometryReader { space in
            if space.size.width >= 740 {
                HStack(alignment: .top, spacing: 18) {
                    ThinScrollView { taskColumn }.frame(minWidth: 380, maxWidth: .infinity)
                    ThinScrollView { setupColumn }.frame(minWidth: 340, maxWidth: 400)
                }
            } else {
                ThinScrollView {
                    VStack(alignment: .leading, spacing: 26) { taskColumn; setupColumn }
                }
            }
        }
    }

    /// A script's name as a small pill, on a function in the sidebar. The status beside it stays whole; a long name is cut.
    func scriptPill(_ name: String) -> some View {
        Text(name).font(.system(size: 9, weight: .semibold)).lineLimit(1).truncationMode(.tail)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(accent.opacity(0.15), in: Capsule()).foregroundStyle(accent)
            .help(name)
    }

    /// The project's scripts on a function's page, each with its phrase count: the open one is what a run works on;
    /// click another to switch.
    var scriptPicker: some View {
        HStack(spacing: 8) {
            Text(md: L("SCRIPT")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(s.project.scriptTabs) { tab in
                        let open = tab.id == s.project.openScript.id
                        let phrases = ((try? ScriptParser.parse(tab.script)) ?? []).reduce(0) { $0 + $1.highlights.count }
                        Button { s.openScript(tab.id) } label: {
                            HStack(spacing: 6) {
                                Text(tab.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text("\(phrases)").font(.system(size: 10, design: .monospaced)).opacity(0.7)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(open ? accent.opacity(0.16) : .white.opacity(0.04), in: Capsule())
                            .foregroundStyle(open ? accent : .secondary).contentShape(Capsule())
                        }.buttonStyle(.plain)
                            .help(open ? L("A run works on this script") : L("Switch to this script"))
                    }
                }
            }.scrollIndicators(.never)
        }
        .disabled(s.busy)
    }

    var taskColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            columnTitle(L("TASK"))
            Bullets(s.function.points)
            if s.function.highlightsPhrases { scriptPicker }
            if s.targets.isEmpty {
                card(L("To do")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(md: L("No phrases yet. The script belongs to the project, so every function can use it."))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Button(L("Add the script")) { s.tab = "project" }.buttonStyle(.borderedProminent)
                    }
                }
            } else {
                card(L("To do")) { phraseList }.guideTarget("todo")
            }
        }.padding(.bottom, 10)
    }

    var setupColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            columnTitle(L("SETUP"))
            card(L("Style and size")) {
                HStack(spacing: 10) {
                    label(L("APPLY"))
                    Spacer()
                    // What a run does to each phrase. The individual steps are under Diagnostics, for testing.
                    Picker(L("Each phrase gets"), selection: Binding(get: { s.project.effectiveRunParts }, set: { choice in
                        s.update(\.runParts, choice == "both" ? nil : choice)
                        // Sizing with a step of 0 would change nothing: give it a step to see and adjust.
                        if choice != "style", s.project.fontSizeStep == 0 { s.update(\.fontSizeStep, 5) }
                    })) {
                        Text(md: L("Style & size")).tag("both")
                        Text(md: L("Style only")).tag("style")
                        Text(md: L("Size only")).tag("size")
                    }.pickerStyle(.segmented).labelsHidden().fixedSize().disabled(s.busy)
                }
                HStack(alignment: .top, spacing: 12) {
                    Group {
                        if let picked = s.pickedStyleImage {
                            Image(nsImage: picked).resizable().scaledToFit()
                        } else {
                            Image(systemName: "square.grid.2x2").font(.system(size: 22)).foregroundStyle(accent)
                        }
                    }.frame(width: 56, height: 56).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L(s.pickedStyleImage == nil ? "Picked on the first phrase" : "Last picked style"))
                            .font(.system(size: 12, weight: .semibold))
                        Text(L(s.project.keepsStyle && s.hasRememberedStyle ? "Used on every run until you reset it." : "Picked on the first phrase of each run."))
                            .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Toggle(L("Keep style"), isOn: Binding(get: { s.project.keepsStyle }, set: { s.update(\.keepStyle, Optional($0)) }))
                        .toggleStyle(.switch).controlSize(.small)
                    Spacer()
                    Button(L("Reset style")) { s.resetStyle() }
                        .disabled(!s.hasRememberedStyle)
                }.disabled(s.busy).opacity(s.project.doesStyle ? 1 : 0.4)
                HStack(spacing: 10) {
                    label(L("FONT SIZE STEP"))
                    Spacer()
                    // Type a number or use the arrows: 0 leaves the size as it is, below 0 makes it smaller.
                    // A step of 0 changes no size: Apply follows it to Style only, and back to Style & size when the
                    // step leaves 0 from there (the arrows pass through 0 on the way from 1 to -1).
                    let step = Binding(get: { s.project.fontSizeStep }, set: { value in
                        let was = s.project.fontSizeStep, now = min(200, max(-100, value))
                        s.update(\.fontSizeStep, now)
                        if now == 0, s.project.runParts == nil { s.update(\.runParts, "style") }
                        else if was == 0, now != 0, s.project.runParts == "style" { s.update(\.runParts, nil) }
                    })
                    HStack(spacing: 4) {
                        TextField(L("0"), value: step, format: .number)
                            .onSubmit { NSApp.keyWindow?.makeFirstResponder(nil) }
                            .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                            .font(.system(size: 12, design: .monospaced)).frame(width: 56)
                            .help(L("Points added to the font size of each highlighted phrase. 0 leaves it unchanged; negative makes it smaller."))
                        Stepper(L("Font size step"), value: step, in: -100...200).labelsHidden()
                    }.disabled(s.busy)
                }.opacity(s.project.doesSize ? 1 : 0.4)
                if !s.ocrOnly { legacyStyle }
            }.guideTarget("apply")
            DisclosureGroup(L("Diagnostics")) {
                VStack(alignment: .leading, spacing: 16) {
                    // The individual steps: for testing one at a time (Test selected stages). A run follows
                    // "Each phrase gets" above, not these boxes.
                    label(L("STEPS FOR EACH PHRASE (TESTING)"))
                    stages
                    Divider()
                    diagnostics
                }.padding(.top, 12)
            }
            if !s.ocrOnly {
                DisclosureGroup(L("Assistant routine instructions")) { routine.frame(minHeight: 420).padding(.top, 12) }
            }
        }.padding(.bottom, 10)
    }

    func columnTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(accent.opacity(0.8))
    }

    /// The project's own information, shared by every function that works on it.
    var projectPage: some View {
        ThinScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    scriptTabs
                    script
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(panel, in: RoundedRectangle(cornerRadius: 12))
                card(L("Phrases to highlight"), trailing: L("%@ phrases", s.targetCount)) {
                    if s.targets.isEmpty {
                        Text(md: L("Paste your script above: its bold phrases show here.")).font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        phraseChips
                    }
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
            Button(L("Add screenshots…"), systemImage: "photo.badge.plus") { importScreenshots() }
                .help(L("Screenshots of your formatted script, read by the assistant"))
            Button(L("Paste image")) { s.pasteScreenshot() }
            if !s.attachments.isEmpty { Button(L("Read as script")) { s.readScriptScreenshot() } }
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
        Button(action: action) { HStack { Image(systemName: ready ? "checkmark.circle.fill" : "circle").foregroundStyle(ready ? accent : .secondary); Text(name).font(.system(size: 11)); Spacer(); if !ready { Text(md: L("Enable")).font(.system(size: 9)).foregroundStyle(accent) } } }.buttonStyle(.plain)
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
    @State private var troubleOpen = false
    /// Set once you have been sent to Screen Recording: macOS applies that grant only after a restart, so the
    /// step then offers the restart instead of waiting for a change it cannot see.
    @AppStorage("screenRecordingRequested") private var screenRequested = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: s.permissionsReady ? "checkmark.seal.fill" : "hand.raised.fill")
                    .font(.system(size: 26)).foregroundStyle(s.permissionsReady ? accent : .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L(s.permissionsReady ? "All set" : "Two quick permissions")).font(.system(size: 22, weight: .semibold))
                    Text(L(s.permissionsReady ? "Edit Assist can see and work in Premiere." : "Edit Assist needs to see Premiere and click in it for you. About a minute, once."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            step(1, "Mouse & keyboard", "Lets Edit Assist click and type in Premiere for you. macOS calls it Accessibility.",
                 done: s.controlAllowed, current: !s.controlAllowed) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        // Asking macOS first is what puts Edit Assist in the list; Settings opened at the same
                        // moment could show the list without it.
                        Button { s.desktop.requestControl() } label: { Label(L("Ask macOS"), systemImage: "hand.raised") }
                            .buttonStyle(.borderedProminent)
                        Button(L("Open System Settings")) { openAfterAsking(control: true) }
                    }
                    Bullets(["Click **Ask macOS**", "In its popup, click **Open System Settings**", "Turn on **Edit Assist**"], numbered: true)
                    Tip("No popup? Use **Open System Settings** here. Not in the list? Click **+** and add **Edit Assist**. This step ticks itself.")
                }
            }
            step(2, "Screen recording", "Lets Edit Assist see the Premiere window. It does not record or save your screen.",
                 done: s.screenAllowed, current: s.controlAllowed && !s.screenAllowed) {
                VStack(alignment: .leading, spacing: 8) {
                    if !screenRequested {
                        HStack(spacing: 8) {
                            Button { screenRequested = true; s.desktop.requestCapture() } label: { Label(L("Ask macOS"), systemImage: "hand.raised") }
                                .buttonStyle(.borderedProminent)
                            Button(L("Open System Settings")) { screenRequested = true; openAfterAsking(control: false) }
                        }
                        Bullets(["Click **Ask macOS**", "In its popup, click **Open System Settings**", "Turn on **Edit Assist**", "When macOS offers **Quit & Reopen**, choose it"], numbered: true)
                        Tip("Not in the list? Click **+** and add **Edit Assist**. Edit Assist reopens with this step done.")
                    } else {
                        Button { s.restart() } label: {
                            Label(L("Restart Edit Assist to finish"), systemImage: "arrow.clockwise")
                        }.buttonStyle(.borderedProminent)
                        HStack(spacing: 6) {
                            Text(md: L("Turned on **Edit Assist** in the list? macOS applies it after a restart."))
                            Button(L("Open the list again")) { openAfterAsking(control: false) }.buttonStyle(.link)
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            DisclosureGroup(L("Still not working?"), isExpanded: $troubleOpen) { trouble.padding(.top, 10) }
                .font(.system(size: 12))
            HStack {
                Spacer()
                Button(L(s.permissionsReady ? "Start using Edit Assist" : "Later")) { s.permissionsOpen = false }
                    .buttonStyle(.borderedProminent).tint(s.permissionsReady ? accent : .secondary)
            }
        }
        .padding(30).frame(width: 540).background(canvasBackground).tint(accent)
        // Accessibility changes show up at once; checking each second lets step 1 tick itself.
        .onReceive(tick) { _ in
            let wasReady = s.permissionsReady
            s.refreshPermissions()
            if s.screenAllowed { screenRequested = false }
            if !wasReady && s.permissionsReady {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if s.permissionsReady { s.permissionsOpen = false } }
            }
        }
        .confirmationDialog(L("Reset Edit Assist's permissions?"), isPresented: $resetting, titleVisibility: .visible) {
            Button(L("Reset and reopen"), role: .destructive) { screenRequested = false; s.restart(resetPermissions: true) }
            Button(L("Cancel"), role: .cancel) { }
        } message: {
            Text(md: L("Removes Edit Assist from Screen recording and Accessibility, then reopens it so macOS asks again.\n\nOnly this app is affected."))
        }
    }

    /// Opens the Settings list only after asking macOS, which adds Edit Assist to that list: opened at once,
    /// the list could load before the entry existed and show without Edit Assist.
    func openAfterAsking(control: Bool) {
        if control { s.desktop.requestControl() } else { s.desktop.requestCapture() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if control { s.desktop.openControlSettings() } else { s.desktop.openScreenSettings() }
        }
    }

    /// One numbered step: a tick when done, its button and instruction while it is the one to do.
    func step<Content: View>(_ number: Int, _ name: String, _ detail: String, done: Bool, current: Bool, @ViewBuilder action: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(done ? accent : (current ? Color.orange : Color.white).opacity(done ? 1 : 0.15)).frame(width: 28, height: 28)
                if done { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.black) }
                else { Text("\(number)").font(.system(size: 13, weight: .bold)).foregroundStyle(current ? .orange : .secondary) }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(L(name)).font(.system(size: 14, weight: .semibold))
                    if done { Text(md: L("Allowed")).font(.system(size: 10, weight: .bold)).foregroundStyle(accent) }
                }
                Text(L(detail)).font(.system(size: 11)).foregroundStyle(.secondary)
                if current { action().padding(.top, 4) }
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(panel, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(current ? Color.orange.opacity(0.5) : .clear))
        .opacity(done || current ? 1 : 0.55)
    }

    /// For when the steps did not take: old duplicate rows in System Settings, or a copy elsewhere.
    var trouble: some View {
        VStack(alignment: .leading, spacing: 10) {
            Bullets(["**Edit Assist not in the list?** Click **+** under the list, choose **Edit Assist** in Applications (the path below)", "Turned on but **not ticked**? The list may hold an **old entry** from an earlier copy", "**Reset & re-register** removes Edit Assist's entries and reopens it, so macOS asks again", "After an **update**, macOS may ask again: each version is a new app to it"])
            VStack(alignment: .leading, spacing: 4) {
                Text(md: L("THIS COPY")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Text(s.desktop.bundlePath).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            }
            HStack {
                Button(L("Reset & re-register")) { resetting = true }
                Button(L("Restart Edit Assist")) { s.restart() }
                Spacer()
            }.font(.system(size: 11))
        }
    }
}

/// Bottom-right button: how many problems are new, and a list of every one with Copy, the log file and Clear.
struct ErrorLogButton: View {
    @EnvironmentObject var s: Store
    @State private var open = false
    var body: some View {
        Button { open.toggle(); s.unseenProblems = 0 } label: {
            HStack(spacing: 6) {
                Image(systemName: s.unseenProblems > 0 ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                Text(L(s.unseenProblems > 0 ? "\(s.unseenProblems) new" : "Errors")).font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background((s.unseenProblems > 0 ? Color.orange : Color.white).opacity(s.unseenProblems > 0 ? 0.22 : 0.07), in: Capsule())
            .foregroundStyle(s.unseenProblems > 0 ? Color.orange : .secondary)
        }
        .buttonStyle(.plain).help(L("Error log"))
        .popover(isPresented: $open, arrowEdge: .top) { ErrorLogView().environmentObject(s) }
    }
}

/// The error log: every problem this session with its time, and Email log, Copy all, Show full log, Clear.
struct ErrorLogView: View {
    @EnvironmentObject var s: Store
    var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(md: L("Error log")).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(L("%@ this session", s.problems.count)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if s.problems.isEmpty {
                    Text(md: L("Nothing has gone wrong this session.")).font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    ThinScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(s.problems.reversed()) { problem in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(problem.time.formatted(date: .omitted, time: .standard))
                                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                        if let done = problem.done {
                                            Text(L("%@% done", Int((done * 100).rounded()))).font(.system(size: 10, weight: .semibold))
                                                .padding(.horizontal, 6).padding(.vertical, 1)
                                                .background(severityColor(done).opacity(0.2), in: Capsule()).foregroundStyle(severityColor(done))
                                        }
                                    }
                                    Text(L(problem.message)).font(.system(size: 12)).textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10).padding(.leading, 4).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .leading) {
                                    // How bad it was: red for nothing done, through orange, to green.
                                    RoundedRectangle(cornerRadius: 2).fill(severityColor(problem.done)).frame(width: 4).padding(.vertical, 6)
                                }
                            }
                        }
                    }.frame(maxHeight: 360)
                }
                HStack {
                    Button { s.revealLogPackage() } label: { Label(L("Show log file"), systemImage: "folder") }
                        .buttonStyle(.borderedProminent)
                        .help(L("Packs the errors, the full log and the screens saved on problems into one zip and shows it in Finder, to drag into a chat"))
                    Button(L("Copy all")) {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s.problemsText, forType: .string)
                    }.disabled(s.problems.isEmpty)
                    Spacer()
                    Button(L("Clear")) { s.problems = []; s.unseenProblems = 0 }.disabled(s.problems.isEmpty)
                }.font(.system(size: 11))
            }.padding(16).frame(width: 440).tint(accent)
    }
}

struct ConnectionView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(md: L("Choose your assistant")).font(.system(size: 24, weight: .semibold))
            Text(md: L("Uses your existing CLI login. No API key setup in Edit Assist.")).font(.system(size: 12)).foregroundStyle(.secondary)
            Picker(L("Assistant"), selection: $s.provider) {
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
            TextField(L("Model override (optional — CLI default)"), text: $s.model).textFieldStyle(.roundedBorder)
            if let fastest = CLIProvider(rawValue: s.provider)?.fastestModel {
                HStack(spacing: 8) {
                    Button(L("Use fastest model")) { s.model = fastest }.font(.system(size: 10))
                    Text("Sets \(fastest), roughly a third of the default's time per step.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if let provider = CLIProvider(rawValue: s.provider) {
                Text("If sign-in is needed, run “\(provider.loginHint)” in Terminal. Installed status does not confirm login.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(md: L("The selected CLI receives the script and any captured images. Its account limits and data policies apply. Only one assistant is called per step.")).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            HStack {
                Button(L("Cancel")) { s.connectionOpen = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use \(s.provider)") { s.saveConnection() }.buttonStyle(.borderedProminent)
            }
        }.padding(30).frame(width: 490).background(canvasBackground).tint(accent)
    }
}


/// Lays out views left to right, wrapping onto new lines, like words in a paragraph.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing; row = max(row, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}


/// Points or numbered steps, one idea each, **bold** for the key words. Every list of instructions uses this.
struct Bullets: View {
    let items: [String]
    var numbered = false
    var size: CGFloat = 12
    private let accent = Color(red: 0.43, green: 0.88, blue: 0.73)
    init(_ items: [String], numbered: Bool = false, size: CGFloat = 12) { self.items = items; self.numbered = numbered; self.size = size }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if numbered {
                        Text("\(index + 1)").font(.system(size: size - 2, weight: .bold, design: .rounded)).foregroundStyle(.black.opacity(0.75))
                            .frame(width: 16, height: 16).background(accent.opacity(0.85), in: Circle())
                    } else {
                        Circle().fill(accent).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    }
                    Text(md: L(item)).font(.system(size: size)).foregroundStyle(.primary.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A tip in a tinted box, after the steps it belongs to.
struct Tip: View {
    let text: String
    private let accent = Color(red: 0.43, green: 0.88, blue: 0.73)
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "lightbulb").font(.system(size: 10)).foregroundStyle(accent)
            Text(md: L(text)).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
    }
}


/// Red when a run got nothing done, through orange, to green when it got nearly all done; orange outside a run.
func severityColor(_ done: Double?) -> Color {
    guard let done else { return .orange }
    return Color(hue: 0.33 * min(1, max(0, done)), saturation: 0.75, brightness: 0.95)
}

/// The sidebar's Log: an orange count of new problems, and a soft pulse in the colour of the worst of them.
struct LogSidebarItem: View {
    @EnvironmentObject var s: Store
    @Binding var open: Bool
    /// On the folded sidebar: the icon alone, with the count of new problems as a badge.
    var compact = false
    @State private var pulse = false
    var worst: Color {
        let fresh = s.problems.suffix(s.unseenProblems)
        let shares = fresh.compactMap(\.done)
        return severityColor(shares.min() ?? (fresh.isEmpty ? nil : nil))
    }
    var body: some View {
        let alerting = s.unseenProblems > 0
        Button { open.toggle(); s.unseenProblems = 0 } label: {
            if compact {
                Image(systemName: alerting ? "exclamationmark.triangle.fill" : "doc.text.magnifyingglass").font(.system(size: 14))
                    .foregroundStyle(alerting ? worst : .secondary)
                    .frame(width: 40, height: 30)
                    .background(alerting ? worst.opacity(pulse ? 0.22 : 0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if alerting {
                            Text("\(s.unseenProblems)").font(.system(size: 8, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
                                .background(worst, in: Capsule()).foregroundStyle(.black).offset(x: 2, y: -2)
                        }
                    }
                    .contentShape(Rectangle())
            } else {
            HStack(spacing: 6) {
                Label(L("Log"), systemImage: alerting ? "exclamationmark.triangle.fill" : "doc.text.magnifyingglass").font(.system(size: 12))
                    .foregroundStyle(alerting ? worst : .primary)
                if alerting {
                    Text("\(s.unseenProblems)").font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(worst.opacity(0.25), in: Capsule()).foregroundStyle(worst)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, alerting ? 6 : 0).padding(.horizontal, alerting ? 8 : 0)
            .background {
                if alerting {
                    RoundedRectangle(cornerRadius: 8).fill(worst.opacity(pulse ? 0.22 : 0.08))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(worst.opacity(pulse ? 0.8 : 0.3), lineWidth: 1))
                        .shadow(color: worst.opacity(pulse ? 0.6 : 0), radius: pulse ? 10 : 2)
                }
            }
            .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .onAppear { pulse = false; withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true } }
    }
}


/// One phrase in To do: its state, its words done (the tooltip explains the count), and Redo on hover once it has
/// progress to clear.
struct PhraseRow: View {
    @EnvironmentObject var s: Store
    let phrase: String
    @State private var hovering = false
    private let accent = Color(red: 0.43, green: 0.88, blue: 0.73)
    var body: some View {
        let total = s.words(of: phrase).count
        let done = min(s.styled(phrase), total)
        HStack(spacing: 8) {
            Image(systemName: done >= total ? "checkmark.circle.fill" : (done > 0 ? "circle.lefthalf.filled" : "circle"))
                .font(.system(size: 12))
                .foregroundStyle(done >= total ? accent : (done > 0 ? .orange : .secondary))
            Text(phrase.trimmingCharacters(in: .whitespaces)).font(.system(size: 12))
                .foregroundStyle(done >= total ? .secondary : .primary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            if hovering && done > 0 && !s.busy {
                Button(L("Redo")) { s.clearProgress(of: phrase) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
            }
            Text("\(done)/\(total)").font(.system(size: 10, design: .monospaced))
                .foregroundStyle(done > 0 && done < total ? .orange : .secondary)
                .help(L("Words done. A phrase split across clips shows part done."))
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(hovering ? Color.white.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// A script tab as a place to drop another: the dragged tab moves there as soon as it is over it, so the tabs slide aside
/// while you drag rather than jumping when you let go.
struct ScriptTabDrop: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let move: (UUID) -> Void
    func dropEntered(info: DropInfo) { if let dragging, dragging != target { move(dragging) } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

/// Your order for a sidebar list, kept as ids joined by commas: the ones you placed first, then any new ones in their
/// first order.
enum SidebarOrder {
    static func ordered(_ ids: [String], saved: String) -> [String] {
        let placed = saved.split(separator: ",").map(String.init).filter(ids.contains)
        return placed + ids.filter { !placed.contains($0) }
    }
    /// `id` moved to where `target` is.
    static func moved(_ id: String, to target: String, in order: [String]) -> String {
        var order = order
        guard let from = order.firstIndex(of: id), let to = order.firstIndex(of: target) else { return order.joined(separator: ",") }
        order.insert(order.remove(at: from), at: to)
        return order.joined(separator: ",")
    }
}

/// A folded-sidebar item: tells the page when the pointer comes onto it (with where it is) and leaves it.
struct RailHover: ViewModifier {
    let key: String
    let enter: (String, CGRect) -> Void
    let leave: (String) -> Void
    @State private var frame: CGRect = .zero
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("window")) } action: { frame = $0 }
            .onHover { inside in if inside { enter(key, frame) } else { leave(key) } }
    }
}

extension View {
    func railHover(_ key: String, in page: ContentView) -> some View {
        modifier(RailHover(key: key, enter: page.railEnter, leave: page.railLeave))
    }
    /// A sidebar row you can drag to another place in its own list ("kind:id"); the others slide aside as it passes.
    func sidebarDraggable(_ id: String, dragging: Binding<String?>, disabled: Bool = false, move: @escaping (String) -> Void) -> some View {
        let kind = id.prefix { $0 != ":" }
        return self
            .onDrag { if !disabled { dragging.wrappedValue = id }; return NSItemProvider(object: id as NSString) }
            .onDrop(of: [.text], delegate: SidebarDrop(target: id, dragging: dragging) { dragged in
                guard !disabled, dragged.prefix(while: { $0 != ":" }) == kind else { return }
                withAnimation(.easeOut(duration: 0.15)) { move(String(dragged.drop { $0 != ":" }.dropFirst())) }
            })
    }
}

/// A sidebar row as a place to drop another: the dragged row moves there as soon as it is over it.
struct SidebarDrop: DropDelegate {
    let target: String
    @Binding var dragging: String?
    let move: (String) -> Void
    func dropEntered(info: DropInfo) { if let dragging, dragging != target { move(dragging) } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}
