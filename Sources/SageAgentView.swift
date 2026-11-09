import AppKit
import SwiftUI

/// Sage's chat drawn as Markdown, as Vault Agent's panel draws replies (2026-11-09): the blocks from `Study.chatBlocks`,
/// bold, italic, inline code and links inside them; a [[wikilink]] opens its note in Notes, a web link your browser.
struct SageMarkdown: View {
    let text: String
    var size: CGFloat = 12
    var open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Study.chatBlocks(text).enumerated()), id: \.offset) { _, block in view(block) }
        }
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            if let name = Study.noteLinkTarget(url) { open(name); return .handled }
            return .systemAction
        })
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: Study.chatInline(text), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)))
            ?? AttributedString(text)
    }

    func line(_ text: String, size: CGFloat? = nil, weight: Font.Weight = .regular) -> some View {
        Text(Self.inline(text)).font(.system(size: size ?? self.size, weight: weight)).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder func view(_ block: Study.ChatBlock) -> some View {
        switch block {
        case let .heading(level, text):
            line(text, size: size + CGFloat(max(0, 4 - level)) * 1.5 + 1, weight: .semibold).padding(.top, level <= 2 ? 4 : 2)
        case let .paragraph(text):
            line(text)
        case let .bullet(level, text, checked):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let checked { Image(systemName: checked ? "checkmark.square" : "square").font(.system(size: size - 1)) } else { Text(level == 0 ? "•" : "◦").font(.system(size: size)) }
                line(text)
            }.padding(.leading, CGFloat(level) * 14)
        case let .numbered(level, number, text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(number + ".").font(.system(size: size).monospacedDigit()).foregroundStyle(.secondary)
                line(text)
            }.padding(.leading, CGFloat(level) * 14)
        case let .quote(text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(.secondary.opacity(0.5)).frame(width: 3)
                line(text).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        case let .code(_, text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text).font(.system(size: size - 1, design: .monospaced)).fixedSize().padding(8)
            }
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
        case let .table(rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in line(cell, size: size - 1, weight: index == 0 ? .semibold : .regular) }
                        }
                        if index == 0 { Divider() }
                    }
                }.padding(.vertical, 2)
            }
        case .rule:
            Divider()
        }
    }
}

/// An agent run (or Sage's media tools) in the chat: while it works, what it's doing (each step as it happens, the one
/// it's on lit, the model, the time, Stop); when it's done, a summary: how it ended, the files it changed, made or removed
/// as links, what was copied first (and what wasn't), and Undo.
struct SageRunCard: View {
    @ObservedObject var desk: SageDesk
    let message: Study.Message
    let run: Study.AgentRun
    let accent: Color
    @State private var allSteps = false

    var running: Bool { desk.agentMessage == message.id }
    var steps: [Study.AgentStep] { message.steps ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if running { liveSteps } else { doneSteps; summary }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(running ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(accent.opacity(running ? 0.5 : 0.2), lineWidth: 1))
    }

    var title: String {
        if running {
            switch run.kind {
            case "fetch": return L("Fetching the note's media…")
            case "transcribe": return L("Transcribing the note's media…")
            default: return L("Working in your vault…")
            }
        }
        if run.stopped { return L("Stopped") }
        if run.failure != nil {
            switch run.kind {
            case "fetch": return L("Couldn't fetch media")
            case "transcribe": return L("Couldn't transcribe")
            default: return L("The agent couldn't finish")
            }
        }
        return L("Done")
    }

    var header: some View {
        HStack(spacing: 7) {
            if running { ProgressView().controlSize(.small) } else {
                Image(systemName: run.stopped ? "stop.circle" : run.failure != nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(run.failure != nil || run.stopped ? Color.orange : accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11.5, weight: .semibold))
                TimelineView(.periodic(from: run.started, by: 1)) { context in
                    Text(detail(now: context.date)).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if running && desk.agentRun != nil {
                Button { desk.stopAgent() } label: { Label(L("Stop"), systemImage: "stop.fill") }.controlSize(.small)
                    .help(L("Stops the agent and the commands it started; what it changed so far stays, with Undo"))
            }
        }
    }

    /// The model and effort (for the agent), and how long it has run or took.
    func detail(now: Date) -> String {
        let seconds = Int(max(0, (run.ended ?? (running ? now : run.started)).timeIntervalSince(run.started)))
        let time = seconds < 60 ? L("%@ s", "\(seconds)") : L("%@ min %@ s", "\(seconds / 60)", "\(seconds % 60)")
        var parts: [String] = []
        if run.kind == "agent" { parts.append([run.provider, run.model, run.effort].filter { !$0.isEmpty }.joined(separator: " · ")) }
        if running || run.ended != nil { parts.append(time) }
        if !steps.isEmpty { parts.append(L("%@ steps", "\(steps.filter { $0.kind != "say" }.count)")) }
        return parts.filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }

    static func symbol(_ kind: String) -> String {
        ["read": "doc.text", "edit": "pencil", "write": "square.and.pencil", "run": "terminal", "search": "magnifyingglass", "find": "folder.badge.questionmark",
         "web": "globe", "websearch": "globe", "plan": "list.bullet", "task": "person.2", "say": "arrow.right.circle"][kind] ?? "gearshape"
    }

    func stepLine(_ step: Study.AgentStep, current: Bool = false) -> some View {
        Label {
            Text(step.kind == "say" ? step.target : L(step.format, step.target)).lineLimit(current ? 2 : 1).truncationMode(.middle)
        } icon: { Image(systemName: Self.symbol(step.kind)) }
        .font(.system(size: 10, weight: current ? .medium : .regular))
        .foregroundStyle(step.failed == true ? Color.orange : current ? Color.primary : Color.secondary)
    }

    /// The last few steps, the newest (the one it's on) lit.
    @ViewBuilder var liveSteps: some View {
        let shown = Array(steps.suffix(5))
        if steps.count > shown.count {
            Text(L("… %@ earlier steps", "\(steps.count - shown.count)")).font(.system(size: 9.5)).foregroundStyle(.secondary)
        }
        ForEach(Array(shown.enumerated()), id: \.offset) { index, step in stepLine(step, current: index == shown.count - 1) }
        if steps.isEmpty { Text(L("Starting…")).font(.system(size: 10)).foregroundStyle(.secondary) }
    }

    @ViewBuilder var doneSteps: some View {
        if steps.count > 4 {
            DisclosureGroup(isExpanded: $allSteps) {
                VStack(alignment: .leading, spacing: 3) { ForEach(Array(steps.enumerated()), id: \.offset) { _, step in stepLine(step) } }.padding(.top, 3)
            } label: { Text(L("%@ steps", "\(steps.count)")).font(.system(size: 10)).foregroundStyle(.secondary) }
        } else {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in stepLine(step) }
        }
    }

    @ViewBuilder var summary: some View {
        if let failure = run.failure {
            Text(failure).font(.system(size: 10.5)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        if let files = run.files {
            fileRow(L("Changed"), files.changed, link: true)
            fileRow(L("Created"), files.made, link: true)
            fileRow(L("Removed"), files.gone, link: false)
        } else if run.ended != nil {
            Text(L("No file in your vault changed.")).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        if !run.backedUp.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "externaldrive.badge.checkmark").font(.system(size: 9.5)).foregroundStyle(.secondary)
                Text(L("Copied first, into Sage's edited folder: %@", run.backedUp.map { SageViewer.title(URL(fileURLWithPath: $0)) }.joined(separator: ", ")))
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L("Show")) { NSWorkspace.shared.activateFileViewerSelecting([Study.editsKept(in: SageDesk.place)]) }.buttonStyle(.link).font(.system(size: 10))
            }
        }
        if !run.notBackedUp.isEmpty {
            Label(L("Not copied before it changed, so Undo can't put it back: %@", run.notBackedUp.map { SageViewer.title(URL(fileURLWithPath: $0)) }.joined(separator: ", ")),
                  systemImage: "exclamationmark.circle")
                .font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
        if desk.undos[message.id] != nil {
            Button { desk.undo(message.id) } label: { Label(L("Undo"), systemImage: "arrow.uturn.backward") }.controlSize(.small)
                .help(L("Puts back the files copied before the run, each only if it still reads as the agent left it"))
        }
    }

    @ViewBuilder func fileRow(_ title: String, _ paths: [String], link: Bool) -> some View {
        if !paths.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title + ":").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                SageFlow(spacing: 6) {
                    ForEach(paths, id: \.self) { path in
                        if link {
                            Button { desk.vault.show(path: path) } label: { Label(SageViewer.title(URL(fileURLWithPath: path)), systemImage: SageViewer.symbol(URL(fileURLWithPath: path))).lineLimit(1).truncationMode(.middle) }
                                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(accent).help(path)
                        } else {
                            Text(SageViewer.title(URL(fileURLWithPath: path))).font(.system(size: 10)).strikethrough().foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(path)
                        }
                    }
                }
            }
        }
    }
}

/// Views laid out in rows, wrapping to the next row when the width runs out; one wider than a whole row is offered the
/// row's width, so a long name shortens (…) instead of running past the edge (2026-11-09).
struct SageFlow: Layout {
    var spacing: CGFloat = 6
    static func size(_ view: LayoutSubview, _ width: CGFloat) -> CGSize {
        let ideal = view.sizeThatFits(.unspecified)
        guard width.isFinite, ideal.width > width else { return ideal }
        return view.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = Self.size(view, width)
            if x > 0 && x + size.width > width { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing; row = max(row, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = Self.size(view, bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}

/// Sage's first agent run asks which model (and effort) to use; the answer is remembered (you asked for no default,
/// 2026-11-09). It starts on your last choice, else Vault Agent's, else the CLI's first.
struct SageModelQuestion: View {
    @ObservedObject var desk: SageDesk
    let message: Study.Message
    let accent: Color
    @State private var model = ""
    @State private var effort = ""

    var models: [Study.AgentModel] { desk.agentModels[HelperBrain.provider.rawValue] ?? [] }
    var efforts: [String] { models.first { $0.id == model }?.efforts ?? models.first?.efforts ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L("Model"), selection: $model) {
                let aliases = models.filter(\.alias), exact = models.filter { !$0.alias }
                if !aliases.isEmpty {
                    Section(L("Always the newest")) { ForEach(aliases, id: \.id) { Text(SageModelMenu.name($0)).tag($0.id) } }
                }
                if !exact.isEmpty {
                    Section(L("Exact models")) { ForEach(exact, id: \.id) { Text(SageModelMenu.name($0)).tag($0.id) } }
                }
                if !model.isEmpty && !models.contains(where: { $0.id == model }) { Text(model).tag(model) }
            }
            if !efforts.isEmpty {
                Picker(L("Effort"), selection: $effort) {
                    ForEach(efforts, id: \.self) { Text(L(SageModelMenu.effortName($0))).tag($0) }
                    if !effort.isEmpty && !efforts.contains(effort) { Text(effort).tag(effort) }
                }
            }
            HStack(spacing: 8) {
                Button { desk.answer(message.id, model: model, effort: efforts.isEmpty ? "" : effort) } label: { Label(L("Use it and run"), systemImage: "play.fill") }
                    .controlSize(.small).disabled(model.isEmpty || desk.thinking)
                if desk.vaultAgentSettings.model(for: HelperBrain.provider.rawValue) == model, !model.isEmpty {
                    Text(L("Vault Agent's choice")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 11))
        .padding(9)
        .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .onAppear(perform: suggest)
        .onChange(of: models) { _, _ in suggest() }
        .task { if models.isEmpty { await desk.loadAgentModels() } }
    }

    private func suggest() {
        guard model.isEmpty || !models.contains(where: { $0.id == model }) else { return }
        let suggested = desk.suggestedChoice()
        model = suggested.model; effort = suggested.effort
    }
}

/// The agent's model and effort, to change any time: aliases first (they always mean the newest), then the exact models
/// the CLI names, then the efforts it takes.
struct SageModelMenu: View {
    @ObservedObject var desk: SageDesk

    static func name(_ model: Study.AgentModel) -> String {
        model.alias ? L("%@ (newest)", model.name) : model.name == model.id ? model.id : "\(model.name) · \(model.id)"
    }
    static func effortName(_ effort: String) -> String {
        ["low": "Low", "medium": "Medium", "high": "High", "xhigh": "Extra high", "max": "Max", "ultra": "Ultra"][effort] ?? effort
    }

    var body: some View {
        let provider = HelperBrain.provider
        let models = desk.agentModels[provider.rawValue] ?? []
        let _ = desk.agentChoice
        let chosen = desk.chosenModel(provider), effort = desk.chosenEffort(provider)
        let efforts = models.first { $0.id == chosen }?.efforts ?? models.first?.efforts ?? []
        Menu {
            Text(L("The agent's model (%@ CLI)", provider.rawValue))
            let aliases = models.filter(\.alias), exact = models.filter { !$0.alias }
            if !aliases.isEmpty {
                Section(L("Always the newest")) { ForEach(aliases, id: \.id) { item(model: $0, chosen: chosen, effort: effort, efforts: efforts) } }
            }
            if !exact.isEmpty {
                Section(L("Exact models")) { ForEach(exact, id: \.id) { item(model: $0, chosen: chosen, effort: effort, efforts: efforts) } }
            }
            if chosen != nil, !efforts.isEmpty {
                Section(L("Effort")) {
                    ForEach(efforts, id: \.self) { level in
                        Button { desk.choose(model: chosen ?? "", effort: level) } label: {
                            if level == effort { Label(L(Self.effortName(level)), systemImage: "checkmark") } else { Text(L(Self.effortName(level))) }
                        }
                    }
                }
            }
            if models.isEmpty { Text(L("Reading the models…")) }
        } label: {
            Label(chosen.map { effort.isEmpty ? $0 : "\($0) · \(L(Self.effortName(effort)))" } ?? L("Choose a model"), systemImage: "cpu")
        }
        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 10))
        .help(L("The model Sage works with as an agent in your vault (Vault Agent's commands, and work he hands over)"))
        .task(id: provider.rawValue) { if models.isEmpty { await desk.loadAgentModels() } }
    }

    @ViewBuilder func item(model: Study.AgentModel, chosen: String?, effort: String, efforts: [String]) -> some View {
        Button {
            let levels = model.efforts.isEmpty ? efforts : model.efforts
            desk.choose(model: model.id, effort: levels.contains(effort) ? effort : (levels.contains("medium") ? "medium" : levels.first ?? ""))
        } label: {
            if model.id == chosen { Label(Self.name(model), systemImage: "checkmark") } else { Text(Self.name(model)) }
        }
    }
}

/// Vault Agent's quick actions on the open note (2026-11-09): Process, Summarize and Review on the note bar, the rest in
/// its menu; each runs in Sage's chat, the stage staying on the note.
struct SageQuickBar: View {
    @ObservedObject var desk: SageDesk

    static func symbol(_ name: String) -> String {
        ["process": "sparkles", "summarize": "text.alignleft", "review": "checklist", "categorize": "folder", "links": "link", "rename": "pencil",
         "fetch": "icloud.and.arrow.down", "transcribe": "mic", "localize": "wand.and.stars", "memory": "brain"][name] ?? "sparkles"
    }

    func run(_ command: Study.QuickCommand) {
        if command.slash { desk.send("/" + command.name) } else { desk.send(L(command.label), quick: command.name) }
    }

    func button(_ name: String) -> some View {
        let command = Study.quickCommand(name)!
        return Button { run(command) } label: { Label(L(command.label), systemImage: Self.symbol(name)) }.help(L(command.description))
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Study.quickCommands.filter(\.shortcut), id: \.name) { command in
                Button { run(command) } label: { Label(L(command.label), systemImage: Self.symbol(command.name)) }
                    .controlSize(.small).help(L(command.description))
            }
            Menu {
                button("fetch"); button("transcribe"); button("localize")
                Divider()
                button("categorize"); button("links"); button("rename")
                Divider()
                button("memory")
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize().help(L("More of Vault Agent's actions on this note"))
        }
        .disabled(desk.thinking)
    }
}
