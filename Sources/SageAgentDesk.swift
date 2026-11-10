import AppKit
import Foundation

/// What one agent run has seen so far, while it streams.
@MainActor final class SageAgentLive {
    var session: String?
    var error: String?
    var finalText = ""
    var finished = false
    /// A step came after the text: the next text starts a new paragraph.
    var broke = false
}

/// The desk's side of Sage's agent (2026-11-09, Vault Agent brought into Sage): Vault Agent's quick commands on the open
/// note, the agent run in the vault with its steps streaming into the chat, Sage's media tools (SageMedia.swift), and the
/// safety around every run: the open note copied first and each file the moment the agent starts changing it, the vault's
/// files compared before and after, the files changed listed under the message with Undo. Never without a vault.
@MainActor
extension SageDesk {
    // MARK: The model (no default: asked on the first run, then remembered)

    nonisolated static func modelKey(_ provider: String) -> String { "sageAgentModel.\(provider)" }
    nonisolated static func effortKey(_ provider: String) -> String { "sageAgentEffort.\(provider)" }

    /// The model you chose for the agent on this CLI, or nil: then Sage asks before running.
    func chosenModel(_ provider: CLIProvider = HelperBrain.provider) -> String? {
        UserDefaults.standard.string(forKey: Self.modelKey(provider.rawValue)).flatMap { $0.isEmpty ? nil : $0 }
    }
    func chosenEffort(_ provider: CLIProvider = HelperBrain.provider) -> String {
        UserDefaults.standard.string(forKey: Self.effortKey(provider.rawValue)) ?? ""
    }

    func choose(model: String, effort: String, for provider: CLIProvider = HelperBrain.provider) {
        UserDefaults.standard.set(model, forKey: Self.modelKey(provider.rawValue))
        UserDefaults.standard.set(effort, forKey: Self.effortKey(provider.rawValue))
        agentChoice += 1
    }

    /// What the model question starts on: your choice, else Vault Agent's, else the first the CLI offers.
    func suggestedChoice(_ provider: CLIProvider = HelperBrain.provider) -> (model: String, effort: String) {
        let models = agentModels[provider.rawValue] ?? []
        let model = chosenModel(provider) ?? vaultAgentSettings.model(for: provider.rawValue).nonEmpty ?? models.first?.id ?? ""
        let efforts = models.first { $0.id == model }?.efforts ?? models.first?.efforts ?? []
        let effort = chosenEffort(provider).nonEmpty ?? vaultAgentSettings.effort(for: provider.rawValue).nonEmpty
            ?? (efforts.contains("medium") ? "medium" : efforts.first ?? "")
        return (model, effort)
    }

    /// Reads what the CLI offers (and Vault Agent's settings in the vault) off the main thread.
    func loadAgentModels() async {
        let provider = HelperBrain.provider, root = workVault
        let (models, saved) = await Task.detached { () -> ([Study.AgentModel], Study.AgentSettings) in
            let saved = root.map(SageDesk.vaultAgent(in:)) ?? Study.AgentSettings()
            return (SageDesk.readModels(provider, saved: saved), saved)
        }.value
        agentModels[provider.rawValue] = models
        vaultAgentSettings = saved
    }

    /// Vault Agent's settings from its data.json in the vault (six keys only; its chats there are never read).
    nonisolated static func vaultAgent(in vault: URL) -> Study.AgentSettings {
        guard let data = try? Data(contentsOf: vault.appendingPathComponent(".obsidian/plugins/vault-agent/data.json")) else { return Study.AgentSettings() }
        return Study.vaultAgentSettings(data)
    }

    /// The models the CLI offers: Codex lists its own (its models cache); Claude can't, so its help is read for its
    /// aliases and efforts (Study.claudeModels), with the model in your Claude settings and Vault Agent's added.
    nonisolated static func readModels(_ provider: CLIProvider, saved: Study.AgentSettings) -> [Study.AgentModel] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if provider == .codex {
            var models = (try? Data(contentsOf: home.appendingPathComponent(".codex/models_cache.json"))).map(Study.codexModels(cache:)) ?? []
            let configured = ((try? String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8)) ?? "")
                .split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("model ") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("model=") }
                .map { $0.split(separator: "=", maxSplits: 1).last.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) } ?? "" } ?? ""
            for id in [configured, saved.codexModel] where !id.isEmpty && !models.contains(where: { $0.id == id }) {
                models.append(Study.AgentModel(id: id, name: id, efforts: models.first?.efforts ?? ["low", "medium", "high"]))
            }
            return models
        }
        var help = ""
        if let executable = provider.executable {
            let process = Process(), out = Pipe()
            process.executableURL = executable
            process.arguments = ["--help"]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = CLIProvider.searchPath
            environment.removeValue(forKey: "CLAUDECODE")
            process.environment = environment
            process.standardOutput = out; process.standardError = FileHandle.nullDevice
            if (try? process.run()) != nil {
                let deadline = Date().addingTimeInterval(10)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                while process.isRunning && Date() < deadline { usleep(20_000) }
                if process.isRunning { process.terminate() }
                help = String(decoding: data, as: UTF8.self)
            }
        }
        let settings = (try? Data(contentsOf: home.appendingPathComponent(".claude/settings.json"))).flatMap { Study.json($0)?["model"] as? String } ?? ""
        return Study.claudeModels(help: help, extra: [settings, saved.claudeModel].filter { !$0.isEmpty })
    }

    /// The model chosen on a question message: remembered, the question put away, and the request it held run.
    func answer(_ messageID: UUID, model: String, effort: String) {
        guard !thinking, let id = conversations.first(where: { $0.messages.contains { $0.id == messageID } })?.id else { return }
        var request: String?
        edit(messageID, in: id) { message in
            request = message.ask
            message.ask = nil
            message.text = effort.isEmpty ? L("I'll use %@ from now on. Change it any time from the model menu under the message box.", model)
                                          : L("I'll use %@ (%@ effort) from now on. Change it any time from the model menu under the message box.", model, effort)
        }
        choose(model: model, effort: effort)
        saveChats()
        guard let request else { return }
        thinkingIn = id; failure = nil
        Task {
            defer { thinkingIn = nil }
            await runAgent(request, in: id)
        }
    }

    // MARK: Quick commands

    /// The open note as the agent sees it: the file and its path in the vault; nil when none is open in the vault.
    func openNote(in root: URL) -> (file: URL, path: String)? {
        guard let file = note, FileManager.default.fileExists(atPath: file.path) else { return nil }
        let path = Study.relative(file, to: root)
        return path.hasPrefix("/") ? nil : (file, path)
    }

    /// One of Vault Agent's commands, from the chat ("/review in three bullets") or the note bar. `note`: a note the
    /// message tags ("/summarize @Note"), worked on instead of the open one; `context`: the message's tags and files.
    func quick(_ name: String, extra: String, in id: UUID, note: String? = nil, context: String = "") async {
        switch name {
        case "memory":
            await openMemories(in: id)
        case "fetch", "transcribe":
            _ = await runMedia(name, in: id)
        case "localize":
            // Process & localize, as Vault Agent: the media fetched first, then processed only when that worked.
            if await runMedia("fetch", in: id) { await runQuick("process", extra: extra, in: id, note: note, context: context) }
        default:
            await runQuick(name, extra: extra, in: id, note: note, context: context)
        }
    }

    private func runQuick(_ name: String, extra: String, in id: UUID, note: String? = nil, context: String = "") async {
        let active = note ?? workVault.flatMap { openNote(in: $0) }?.path
        await runAgent(Study.expandSlash("/\(name) \(extra)", active: active) + context, in: id)
    }

    /// Sage saying something went wrong, as a failure line under his message.
    func refuse(_ line: String, in id: UUID) {
        var message = Study.Message(fromSage: true, text: "")
        message.done = [line]
        append(message, to: id)
    }

    /// /memory: the memories folder (Vault Agent's) shown in the vault's tree.
    func openMemories(in id: UUID) async {
        guard let root = workVault else { refuse(L("Couldn't open your memories: no vault is connected"), in: id); return }
        let folder = await Task.detached { SageDesk.vaultAgent(in: root).memoryFolder }.value
        let exists = FileManager.default.fileExists(atPath: root.appendingPathComponent(folder).path)
        if exists, vault.vault?.standardizedFileURL.path == root.standardizedFileURL.path {
            vault.revealFolder(folder)
            vault.showInTree(folder)
            stage = "notes"
            append(Study.Message(fromSage: true, text: L("Your memories are in %@: it's open in the tree.", folder)), to: id)
        } else if exists {
            append(Study.Message(fromSage: true, text: L("Your memories are in %@ in your vault.", folder)), to: id)
        } else {
            append(Study.Message(fromSage: true, text: L("No memories yet: I keep them as notes in %@, made when I save the first one.", folder)), to: id)
        }
    }

    // MARK: The agent

    func stopAgent() { agentRun?.stop() }

    /// Changes one of a conversation's messages without saving the chats (a run saves them once it's done).
    func edit(_ message: UUID, in id: UUID, _ change: (inout Study.Message) -> Void) {
        guard let c = conversations.firstIndex(where: { $0.id == id }), let m = conversations[c].messages.firstIndex(where: { $0.id == message }) else { return }
        change(&conversations[c].messages[m])
    }

    /// The agent asked `request` in the vault, its reply and steps streaming into a message of his; the run's files
    /// listed under it when done, with Undo.
    func runAgent(_ request: String, in id: UUID, retried: Bool = false) async {
        guard let root = workVault else {
            refuse(L("I can't work in your vault yet: none is connected. Choose your vault in Notes, or ask me to connect it."), in: id); return
        }
        let provider = HelperBrain.provider
        guard let executable = provider.executable else { refuse(L("I can't work in your vault: %@ CLI is not installed on this Mac.", provider.rawValue), in: id); return }
        vaultAgentSettings = await Task.detached { SageDesk.vaultAgent(in: root) }.value
        guard let model = chosenModel(provider) else {
            await loadAgentModels()
            // The first run: which model, and how hard it thinks (you asked for no default, 2026-11-09).
            var message = Study.Message(fromSage: true, text: L("Before I work in your vault: which model should I use, and with how much effort? I'll remember it; change it any time from the model menu under the message box."))
            message.ask = request
            append(message, to: id)
            return
        }
        var settings = vaultAgentSettings
        let effort = chosenEffort(provider)
        if provider == .codex { settings.codexModel = model; settings.codexEffort = effort } else { settings.claudeModel = model; settings.claudeEffort = effort }
        let active = openNote(in: root)
        let previous = conversations.first { $0.id == id }?.agent.flatMap { $0.provider == provider.rawValue && $0.vault == root.path && !$0.id.isEmpty ? $0.id : nil }
        let folder = settings.memoryFolder, codex = provider == .codex
        let (memories, instructions, before) = await Task.detached { () -> ([Study.AgentMemory], String?, [Study.VaultItem]) in
            let instructions = codex && previous == nil ? Study.instructionFile(above: root).flatMap { try? String(contentsOf: $0, encoding: .utf8) } : nil
            return (Study.memories(in: root.appendingPathComponent(folder), vault: root), instructions, Study.vaultItems(root))
        }.value
        let prompt = Study.agentPrompt(request, active: active?.path, memories: Study.relevantMemories(memories, for: request), memoryFolder: folder, instructions: instructions)

        let run = Study.AgentRun(kind: "agent", provider: provider.rawValue, model: model, effort: effort)
        var message = Study.Message(fromSage: true, text: "")
        message.steps = []; message.run = run
        append(message, to: id)
        let messageID = message.id
        agentMessage = messageID
        let backups = SageAgentBackups(vault: root, keep: Self.place)
        if let file = active?.file { await Task.detached { backups.keep(file) }.value }

        let session = previous ?? (codex ? nil : UUID().uuidString.lowercased())
        // Files attached from outside the vault are in Sage's attachments folder: Claude may read there too.
        let attachments = Self.attachmentsPlace.path
        let arguments = codex ? Study.codexArguments(settings, session: previous)
            : Study.claudeArguments(settings, session: session ?? "", resume: previous != nil, folders: request.contains(attachments) ? [attachments] : [])
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pythons = (try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Library/Python").path)) ?? []
        environment["PATH"] = Study.agentPath(vault: root, home: home, current: CLIProvider.searchPath, pythonVersions: pythons.sorted())
        // Keep the CLI's own sign-in; don't inherit a parent agent's nesting marker.
        environment.removeValue(forKey: "CLAUDECODE")
        let process = SageAgentProcess()
        agentRun = process
        let live = SageAgentLive()
        var startFailure: String?
        let (status, errors): (Int32, String) = await withCheckedContinuation { continuation in
            do {
                try process.start(executable: executable, arguments: arguments, input: Data(prompt.utf8), directory: root, environment: environment, line: { line in
                    let events = codex ? Study.codexEvents(line, vault: root) : Study.claudeEvents(line, vault: root)
                    // A file about to change is copied here, on the reading thread, before anything else: best effort (see SageAgentBackups).
                    for case let .step(_, file?) in events { backups.keep(URL(fileURLWithPath: file)) }
                    let login = CLIProcess.loginRequired(line)
                    guard !events.isEmpty || login else { return }
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.apply(events, login: login, codex: codex, live: live, message: messageID, in: id) } }
                }, exit: { status, errors in continuation.resume(returning: (status, errors)) })
            } catch {
                startFailure = error.localizedDescription
                continuation.resume(returning: (-1, ""))
            }
        }
        agentRun = nil
        agentMessage = nil

        // A session the CLI no longer has (cleared, or made on another Mac): forgotten, and asked again in a new one.
        if !retried, previous != nil, let error = live.error,
           error.localizedCaseInsensitiveContains("no conversation found") || (codex && error.localizedCaseInsensitiveContains("session")) {
            if let c = conversations.firstIndex(where: { $0.id == id }) {
                conversations[c].agent = nil
                conversations[c].messages.removeAll { $0.id == messageID }
            }
            await runAgent(request, in: id, retried: true)
            return
        }
        if let c = conversations.firstIndex(where: { $0.id == id }), let kept = live.session ?? session, !kept.isEmpty {
            conversations[c].agent = Study.AgentSession(id: kept, provider: provider.rawValue, vault: root.path)
        }
        var ended = run
        if process.stopped { ended.stopped = true }
        else if let startFailure { ended.failure = startFailure }
        else if CLIProcess.loginRequired(errors) || live.error == "login" {
            ended.failure = CLIProcess.loginError(executable).errorDescription ?? L("%@ CLI needs sign-in.", provider.rawValue)
        } else if let error = live.error { ended.failure = error }
        else if status != 0 && !live.finished {
            ended.failure = L("%@ CLI stopped (exit code %@). Open it in Terminal to check its sign-in, model or usage limits.", provider.rawValue, "\(status)")
        }
        let fallback = live.finalText
        edit(messageID, in: id) { message in
            if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { message.text = fallback }
        }
        await finish(messageID, in: id, root: root, before: before, backups: backups, run: ended)
    }

    /// One line's events applied to the message: text added, steps listed (each once, by its id), failures marked.
    func apply(_ events: [Study.AgentEvent], login: Bool, codex: Bool, live: SageAgentLive, message: UUID, in id: UUID) {
        if login { live.error = "login" }
        edit(message, in: id) { message in
            for event in events {
                switch event {
                case let .session(session): live.session = session
                case let .text(text):
                    if live.broke, !message.text.isEmpty, !message.text.hasSuffix("\n\n") { message.text += message.text.hasSuffix("\n") ? "\n" : "\n\n" }
                    message.text += text
                    live.broke = codex
                case let .step(step, _):
                    var steps = message.steps ?? []
                    if !step.id.isEmpty, let index = steps.firstIndex(where: { $0.id == step.id }) {
                        let failed = steps[index].failed
                        steps[index] = step
                        if step.failed == nil { steps[index].failed = failed }
                    } else { steps.append(step) }
                    message.steps = steps
                    live.broke = true
                case let .result(toolID, failed):
                    if failed, let index = message.steps?.firstIndex(where: { $0.id == toolID }) { message.steps?[index].failed = true }
                case let .finished(error, text):
                    live.finished = true
                    if let error { live.error = error }
                    if !text.isEmpty { live.finalText = text }
                case let .failure(reason): live.error = reason
                }
            }
        }
    }

    /// After a run: the vault compared with before it, the files it changed listed, what can be put back kept for Undo,
    /// and what was copied (or wasn't) said.
    func finish(_ messageID: UUID, in id: UUID, root: URL, before: [Study.VaultItem], backups: SageAgentBackups, run: Study.AgentRun, reported: [String] = []) async {
        let copies = backups.copies
        let (after, undo) = await Task.detached { () -> ([Study.VaultItem], [Study.Change]) in
            (Study.vaultItems(root), Study.agentUndo(backups: copies, read: { try? Data(contentsOf: URL(fileURLWithPath: $0)) }))
        }.value
        func inVault(_ path: String) -> String { Study.vaultPath(path, in: root) ?? Study.relative(URL(fileURLWithPath: path), to: root) }
        var files = Study.vaultChanges(before: before, after: after)
        // Files the vault's list leaves out (types Obsidian doesn't show) but a copy shows changed, and what media said it changed.
        for change in undo {
            let path = inVault(change.file.path)
            guard !files.all.contains(path) else { continue }
            switch change {
            case .created: files.made.append(path)
            case .removed: files.gone.append(path)
            default: files.changed.append(path)
            }
        }
        for path in reported where !path.isEmpty && !files.all.contains(path) { files.changed.append(path) }
        let copied = Set(copies.keys.map { inVault($0) })
        var ended = run
        ended.ended = Date()
        ended.files = files.isEmpty ? nil : files
        ended.backedUp = copies.filter { $0.value != nil }.keys.map { inVault($0) }.sorted()
        ended.notBackedUp = (files.changed + files.gone).filter { !copied.contains($0) }
        edit(messageID, in: id) { $0.run = ended }
        if !undo.isEmpty { undos[messageID] = undo.map(SageUndo.file) }
        saveChats()
        reload()
        vault.reload()
    }

    // MARK: Media (SageMedia.swift, built by the media port)

    /// Fetch media or Transcribe on the open note: its progress said as it goes, its report as the message. False when it
    /// failed (Process & localize then stops, as Vault Agent's does).
    func runMedia(_ name: String, in id: UUID) async -> Bool {
        let fetching = name == "fetch"
        guard let root = workVault else {
            refuse(fetching ? L("Couldn't fetch media: no vault is connected") : L("Couldn't transcribe: no vault is connected"), in: id); return false
        }
        guard let active = openNote(in: root), active.file.pathExtension.lowercased() == "md" else {
            refuse(fetching ? L("Couldn't fetch media: open the note in Notes first") : L("Couldn't transcribe: open the note in Notes first"), in: id); return false
        }
        var run = Study.AgentRun(kind: name)
        var message = Study.Message(fromSage: true, text: "")
        message.steps = []; message.run = run
        append(message, to: id)
        let messageID = message.id
        agentMessage = messageID
        defer { agentMessage = nil }
        let backups = SageAgentBackups(vault: root, keep: Self.place)
        let before = await Task.detached { backups.keep(active.file); return Study.vaultItems(root) }.value
        let progress: @Sendable (String) -> Void = { line in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.edit(messageID, in: id) { $0.steps = ($0.steps ?? []) + [Study.AgentStep(kind: "say", target: line)] } }
            }
        }
        do {
            let report = fetching ? try await SageMedia.fetch(note: active.file, vault: root, progress: progress)
                                  : try await SageMedia.transcribe(note: active.file, vault: root, progress: progress)
            edit(messageID, in: id) { $0.text = report.lines.joined(separator: "\n") }
            await finish(messageID, in: id, root: root, before: before, backups: backups, run: run, reported: report.changed)
            return true
        } catch {
            run.failure = describe(error)
            await finish(messageID, in: id, root: root, before: before, backups: backups, run: run)
            return false
        }
    }

    /// A [[link]] in the chat clicked: the note opened in Notes (nil when the vault has none by that name).
    @discardableResult func openLink(_ name: String) -> Bool {
        if let found = Study.resolve(name, in: vault.items), !found.folder { vault.show(path: found.path); return true }
        if let root = workVault, let found = Study.resolve(name, in: Study.contents(ofVault: root, limit: 40000).notes) {
            show(root.appendingPathComponent(found.path)); return true
        }
        return false
    }
}

extension String {
    /// Nil for an empty string, so `??` can go on to the next choice.
    var nonEmpty: String? { isEmpty ? nil : self }
}
