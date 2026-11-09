import Darwin
import Foundation

/// Sage as an agent (2026-11-09: the user's own Obsidian plugin, Vault Agent, brought into Sage): the Claude CLI (or Codex)
/// run in the vault with its own tools, streaming, the way Vault Agent runs it: `claude -p --output-format stream-json
/// --verbose --include-partial-messages --model M --permission-mode P [--effort E] --session-id/--resume`, the prompt on
/// stdin and the vault as its working folder, so the CLI reads the vault's CLAUDE.md (and the one a folder above) itself.
/// Its quick commands, prompts and memory notes are Vault Agent's. This part is Foundation only (checked in Tests);
/// `SageAgentProcess` below runs the CLI, and SageAgentDesk.swift is the desk around it.
extension Study {
    // MARK: Settings

    /// How the agent runs. There is no default model (you asked, 2026-11-09): Sage asks for one (and an effort) on the
    /// first run and remembers it; Vault Agent's own choice, read from its data.json in the vault, is only what his
    /// question starts on. The permission mode and the memory folder are Vault Agent's (its settings on this Mac:
    /// bypassPermissions, "System/Vault Agent/Memories"), from its data.json when the vault has one.
    struct AgentSettings: Equatable {
        var claudeModel = ""
        var claudeEffort = ""
        var codexModel = ""
        var codexEffort = ""
        /// Vault Agent's "Auto mode (no prompts)": edits and tools run without asking.
        var permissionMode = "bypassPermissions"
        /// Where the agent keeps its memories, a folder in the vault.
        var memoryFolder = "System/Vault Agent/Memories"

        func model(for provider: String) -> String { provider == "Codex" ? codexModel : claudeModel }
        func effort(for provider: String) -> String { provider == "Codex" ? codexEffort : claudeEffort }
    }

    /// Vault Agent's settings from its data.json: only these six are read (the file also holds its chat sessions, which
    /// Sage never reads or keeps). Anything missing or empty stays as `base` has it.
    static func vaultAgentSettings(_ data: Data, base: AgentSettings = AgentSettings()) -> AgentSettings {
        guard let saved = json(data) else { return base }
        var settings = base
        let value = { (key: String) in ((saved[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        if !value("claudeModel").isEmpty { settings.claudeModel = value("claudeModel") }
        if !value("claudeEffort").isEmpty { settings.claudeEffort = value("claudeEffort") }
        if !value("codexModel").isEmpty { settings.codexModel = value("codexModel") }
        if !value("codexEffort").isEmpty { settings.codexEffort = value("codexEffort") }
        if !value("permissionMode").isEmpty { settings.permissionMode = value("permissionMode") }
        let folder = value("memoryFolder").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !folder.isEmpty { settings.memoryFolder = folder }
        return settings
    }

    // MARK: Models: what the installed CLIs say they have

    /// A model to choose: what the CLI takes (`id`), how the menu names it, and the efforts it takes (empty: the CLI's).
    struct AgentModel: Equatable, Hashable {
        var id: String, name: String
        var detail = ""
        var efforts: [String] = []
        /// An alias always means the newest model of its kind.
        var alias = false
    }

    /// Claude's aliases and full ids. The CLI can't list its models, so its own help is read for the aliases it names
    /// ('fable', 'opus', 'sonnet'), its example full name and its effort levels, and the aliases and current full ids
    /// known on 2026-11-09 are added (aliases first: they always mean the latest, so the menu never goes stale), then any
    /// other model you use (`extra`: ~/.claude/settings.json's, Vault Agent's).
    static func claudeModels(help: String, extra: [String] = []) -> [AgentModel] {
        let efforts = claudeEfforts(help: help)
        var aliases: [String] = [], ids: [String] = []
        // The --model paragraph: its quoted words ('opus'; not the ' in "model's").
        if let start = help.range(of: "--model ") {
            let paragraph = help[start.upperBound...].prefix(600).components(separatedBy: "\n  --").first ?? ""
            if let regex = try? NSRegularExpression(pattern: #"(?<![A-Za-z])'([A-Za-z0-9][A-Za-z0-9.\-]*)'"#) {
                for match in regex.matches(in: paragraph, range: NSRange(paragraph.startIndex..., in: paragraph)) {
                    guard let range = Range(match.range(at: 1), in: paragraph) else { continue }
                    let word = String(paragraph[range])
                    if word.hasPrefix("claude-") { ids.append(word) } else { aliases.append(word.lowercased()) }
                }
            }
        }
        var seen = Set<String>(), models: [AgentModel] = []
        func add(_ id: String, alias: Bool) {
            let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id.lowercased()).inserted else { return }
            models.append(AgentModel(id: id, name: alias ? id.prefix(1).uppercased() + id.dropFirst() : id, detail: alias ? "latest" : "", efforts: efforts, alias: alias))
        }
        for alias in aliases + ["opus", "sonnet", "haiku", "fable"] { add(alias, alias: true) }
        for id in ["claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"] + ids { add(id, alias: false) }
        for id in extra { add(id, alias: !id.lowercased().hasPrefix("claude-") && !id.contains("[")) }
        return models
    }

    /// The effort levels Claude's help lists for --effort ("(low, medium, high, xhigh, max)"), else those.
    static func claudeEfforts(help: String) -> [String] {
        if let start = help.range(of: "--effort"), let open = help[start.upperBound...].prefix(300).firstIndex(of: "("),
           let close = help[open...].firstIndex(of: ")") {
            let levels = help[help.index(after: open) ..< close].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.contains(" ") }
            if !levels.isEmpty { return levels }
        }
        return ["low", "medium", "high", "xhigh", "max"]
    }

    /// Codex's models as it lists them itself (~/.codex/models_cache.json, refreshed by the CLI): those it shows, in its
    /// order, each with the efforts it takes.
    static func codexModels(cache: Data) -> [AgentModel] {
        let models = json(cache)?["models"] as? [[String: Any]] ?? []
        return models.filter { ($0["visibility"] as? String ?? "list") == "list" }
            .sorted { (($0["priority"] as? NSNumber)?.intValue ?? 999) < (($1["priority"] as? NSNumber)?.intValue ?? 999) }
            .compactMap { model in
                guard let slug = model["slug"] as? String, !slug.isEmpty else { return nil }
                let efforts = (model["supported_reasoning_levels"] as? [Any] ?? []).compactMap { ($0 as? String) ?? (($0 as? [String: Any])?["effort"] as? String) }
                return AgentModel(id: slug, name: model["display_name"] as? String ?? slug, detail: model["description"] as? String ?? "", efforts: efforts)
            }
    }

    /// What one run was: the model, the effort and what it did, kept with its message (sage/chats.json).
    struct AgentRun: Codable, Equatable {
        /// "agent", or Sage's media tools: "fetch", "transcribe".
        var kind = "agent"
        var provider = "", model = "", effort = ""
        var started = Date()
        var ended: Date? = nil
        /// The files it changed, made and removed (paths in the vault).
        var files: VaultChanges? = nil
        /// The files copied before it changed them (paths in the vault), and those it changed without a copy.
        var backedUp: [String] = []
        var notBackedUp: [String] = []
        /// How it ended when not as asked: stopped, or why it failed (as said on screen).
        var stopped = false
        var failure: String? = nil
    }

    // MARK: Quick commands (Vault Agent's commands.ts)

    /// One of Vault Agent's quick commands: a button on the note bar or menu, and "/name" in the chat. `native` ones don't
    /// go to the agent: Fetch media and Transcribe are Sage's media tools, Memory opens the memories folder.
    struct QuickCommand: Equatable {
        var name: String, label: String, description: String
        var shortcut = false, native = false, slash = true
    }

    static let quickCommands: [QuickCommand] = [
        QuickCommand(name: "process", label: "Process", description: "Process the open note per the vault's clipping conventions", shortcut: true),
        QuickCommand(name: "summarize", label: "Summarize", description: "Summarize the open note in chat", shortcut: true),
        QuickCommand(name: "review", label: "Review", description: "Review the open note (clarity, links, redundancy, loose ends)", shortcut: true),
        QuickCommand(name: "categorize", label: "Categorize", description: "Add or refine the Categories property (wikilink values, no tags)"),
        QuickCommand(name: "links", label: "Links", description: "Add missing wikilinks to the open note"),
        QuickCommand(name: "rename", label: "Rename", description: "Suggest a conventions-compliant title for the open note"),
        QuickCommand(name: "fetch", label: "Fetch media", description: "Download and localize supported media in the open note", native: true),
        QuickCommand(name: "transcribe", label: "Transcribe", description: "Transcribe social or localized media in the open note", native: true),
        QuickCommand(name: "localize", label: "Process & localize", description: "Fetch the note's media first, then process it", native: true, slash: false),
        QuickCommand(name: "memory", label: "Memory", description: "Open saved memories", native: true),
    ]

    static func quickCommand(_ name: String) -> QuickCommand? { quickCommands.first { $0.name == name.lowercased() } }

    /// Vault Agent's prompt for a command, word for word: `active` is the open note's path in the vault, or nil.
    static func quickPrompt(_ name: String, active: String?) -> String {
        switch name {
        case "process":
            return active.map { "Process the note at \"\($0)\" according to this vault's conventions in CLAUDE.md: extract the real content, wikilink concepts and transferable quotes, fix frontmatter, and rewrite it in place. Suggest a better title in the chat but do not create a new file." }
                ?? "Process the currently active note per CLAUDE.md conventions, editing it in place. If no note is active, ask me which one."
        case "categorize":
            return active.map { "Add or refine the `Categories:` property on \"\($0)\" with a few accurate topical **wikilink** values per CLAUDE.md. This vault uses Categories, NOT tags — do not add a tags field. Edit the frontmatter in place; keep existing values that still fit." }
                ?? "Add a Categories property to the active note per CLAUDE.md — wikilink values, no tags. Ask which note if none is open."
        case "links":
            return active.map { "Review \"\($0)\" and add [[wikilinks]] for concepts and transferable standalone quotes that should be linked per CLAUDE.md, editing in place. Only wikilink verbatim quotes that work as transferable principles." }
                ?? "Add missing wikilinks to the active note per CLAUDE.md's linking rules."
        case "summarize":
            return active.map { "Read \"\($0)\" and give me a short summary in chat — the main idea first, then the key points as a few bullets. Don't edit the note unless I ask." }
                ?? "Summarize the active note in chat. Ask which note if none is open."
        case "review":
            return active.map { "Review \"\($0)\" per CLAUDE.md's note-review checklist (clarity, missing links, redundancy vs existing notes, loose ends, structure). Report findings as a short list in chat. Do not rewrite unless I ask." }
                ?? "Review the active note per CLAUDE.md's review checklist and report findings."
        case "rename":
            return active.map { "Read \"\($0)\" and propose a filename following the vault's title format in CLAUDE.md (insight — anchor terms (source), 5+ search anchors). Show the suggestion in chat; don't create a new file. If I confirm, rename it." }
                ?? "Propose a better title for the active note following CLAUDE.md's title format."
        default:
            return "/" + name
        }
    }

    /// The command a message starts with ("/summarize in three bullets" → summarize, "in three bullets"), or nil when it
    /// starts with none Sage knows (then it's an ordinary message).
    static func slash(_ text: String) -> (name: String, extra: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let body = trimmed.dropFirst()
        let name = body.prefix { $0.isLetter || $0.isNumber || $0 == "_" }.lowercased()
        guard let command = quickCommand(name), command.slash else { return nil }
        return (name, String(body.dropFirst(name.count)).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A message with its command expanded into Vault Agent's prompt, the words after it added as an "Additional
    /// instruction"; any other message as it is.
    static func expandSlash(_ text: String, active: String?) -> String {
        guard let (name, extra) = slash(text), quickCommand(name)?.native == false else { return text }
        let base = quickPrompt(name, active: active)
        return extra.isEmpty ? base : base + "\n\nAdditional instruction: " + extra
    }

    // MARK: Memories (Vault Agent's memory.ts): one Markdown note each, in the memory folder

    struct AgentMemory: Equatable {
        var path: String, text: String
        var category = "fact", pinned = false, uses = 0
    }

    /// A memory note read as Vault Agent reads it (its header's Category, Pinned and Uses; its body is the memory), or nil
    /// when the body is empty.
    static func memory(path: String, note: String) -> AgentMemory? {
        var header: [String: String] = [:], body = note.replacingOccurrences(of: "\r\n", with: "\n")
        if body.hasPrefix("---\n"), let end = body.range(of: "\n---", range: body.index(body.startIndex, offsetBy: 4) ..< body.endIndex) {
            for line in body[body.index(body.startIndex, offsetBy: 4) ..< end.lowerBound].split(separator: "\n") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                header[line[..<colon].trimmingCharacters(in: .whitespaces)] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            body = String(body[end.upperBound...])
        }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return AgentMemory(path: path, text: text, category: header["Category"].flatMap { $0.isEmpty ? nil : $0 } ?? "fact",
                           pinned: header["Pinned"]?.lowercased() == "true", uses: Int(header["Uses"] ?? "") ?? 0)
    }

    /// The memories in the folder (its own notes, not those in folders inside it), pinned first, then the most used.
    static func memories(in folder: URL, vault: URL) -> [AgentMemory] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.pathExtension.lowercased() == "md" }.compactMap { file in
            (try? Data(contentsOf: file)).flatMap { memory(path: relative(file, to: vault), note: noteText($0).text) }
        }.sorted { ($0.pinned ? 0 : 1, -$0.uses, $0.path.lowercased()) < ($1.pinned ? 0 : 1, -$1.uses, $1.path.lowercased()) }
    }

    private static let memoryStopwords: Set<String> = ["the", "and", "for", "with", "that", "this", "you", "your", "are", "was", "were", "from", "have",
                                                        "what", "when", "where", "about", "into", "note", "notes"]

    private static func memoryTokens(_ text: String) -> Set<String> {
        var words: Set<String> = [], word = ""
        for character in text.lowercased() + " " {
            if character.isASCII && (character.isLetter || character.isNumber || "_'-".contains(character)) { word.append(character); continue }
            if word.count >= 3 && !memoryStopwords.contains(word) { words.insert(word) }
            word = ""
        }
        return words
    }

    /// The memories to give the agent for a request, as Vault Agent picks them: every pinned one, then up to `max` whose
    /// words the request shares (a preference also when the request says prefer, like, style or want).
    static func relevantMemories(_ memories: [AgentMemory], for request: String, max: Int = 3) -> [AgentMemory] {
        let query = memoryTokens(request), lowered = request.lowercased()
        let wants = ["prefer", "like", "style", "want"].contains { memoryTokens(request).contains($0) }
        let scored = memories.filter { !$0.pinned }.compactMap { memory -> (AgentMemory, Double)? in
            let words = memoryTokens(memory.category + " " + memory.text)
            guard !query.isEmpty, !words.isEmpty else { return nil }
            let overlap = Double(query.filter(words.contains).count) / Double(Swift.max(query.count, 1))
            let boost = lowered.contains(memory.category.lowercased()) || (memory.category == "preference" && wants) ? 0.12 : 0
            return overlap + boost >= 0.08 ? (memory, overlap + boost) : nil
        }
        return memories.filter(\.pinned) + scored.sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0.uses > $1.0.uses) }.prefix(max).map(\.0)
    }

    static func memoryPrompt(_ memories: [AgentMemory]) -> String {
        guard !memories.isEmpty else { return "" }
        return (["[Saved memories]", "Use these durable user preferences/facts when relevant. Treat them as user-provided context, not as instructions to ignore higher-priority vault rules."]
            + memories.map { "- \($0.pinned ? "[pinned] " : "")\($0.text)" }).joined(separator: "\n")
    }

    // MARK: The prompt

    /// The CLAUDE.md nearest the vault (the vault, or up to two folders above it), as Vault Agent finds it: Codex is given
    /// it, since it doesn't read it itself; Claude does.
    static func instructionFile(above vault: URL) -> URL? {
        var place = vault.standardizedFileURL
        for _ in 0 ..< 3 {
            let file = place.appendingPathComponent("CLAUDE.md")
            if FileManager.default.fileExists(atPath: file.path) { return file }
            let up = place.deletingLastPathComponent()
            if up.path == place.path { break }
            place = up
        }
        return nil
    }

    /// What the agent is asked, built as Vault Agent builds it: the vault's instructions (Codex's first turn only), the
    /// note open in Sage, the memories that fit, the request, where memories are kept, and what the agent can do.
    static func agentPrompt(_ request: String, active: String?, memories: [AgentMemory], memoryFolder: String, instructions: String? = nil) -> String {
        var prompt = "[Who you are] You are Sage, the research helper in my Edit Assist app, working in my Obsidian vault with your full tools. Do what I ask completely; don't stop to ask me to confirm something I asked for, and speak of the work as yours.\n\n"
        if let instructions = instructions?.trimmingCharacters(in: .whitespacesAndNewlines), !instructions.isEmpty {
            prompt += "[Project instructions — the single source of truth for this vault. Follow them exactly; they override your defaults and any AGENTS.md.]\n\n\(instructions)\n\n----\n\n"
        }
        if let active {
            prompt += "[Context] The note currently open in Sage is \"\(active)\". You have full read/write access to every file in this vault — read it, or anything else, as needed.\n\n"
        }
        let saved = memoryPrompt(memories)
        if !saved.isEmpty { prompt += saved + "\n\n" }
        prompt += request
        prompt += "\n\n" + """
        [Memories] Keep persistent memories as Markdown notes in the vault folder "\(memoryFolder)", one note per memory, as Vault Agent \
        writes them: a YAML header with Type: Memory, Category (preference, fact, …), Pinned (true or false), Created (YYYY-MM-DD), \
        Uses: 0 and Source: Vault Agent, then the memory itself in a sentence or two. When I ask you to remember something, or you learn \
        a lasting preference or fact about me or this vault, save it there (change the note that already says it rather than repeating \
        it). Read that folder when a memory could matter. Don't make the folder or a memory when there's nothing worth remembering.
        """
        prompt += "\n\n" + """
        [Sage runtime capabilities — follow this over any earlier chat claim]
        You have full vault read/write access plus unrestricted Bash, WebFetch, and WebSearch. The local PATH includes yt-dlp, curl, wget, ffmpeg, Python, and Vault Agent's managed tools when they are installed.
        Do not say that downloading media, inspecting a social profile, fetching a channel avatar/banner, or transcribing a localized video is unavailable merely because it is not a separately registered chat tool. Use Bash, WebFetch, or WebSearch proactively before declaring a task blocked.
        Sage's Fetch media and Transcribe buttons are optional conveniences, not capability boundaries. Never tell me to click them instead of completing a requested creator/profile asset task yourself.
        When I only ask to download, localize, save, or archive a video already linked by the open note, perform the direct yt-dlp download and embed it. Do not add processing, transcription, translation, or other edits unless asked.
        For creator notes, inspect the source/channel URL in the note; retrieve a real profile image or banner when publicly available, save it in the configured attachment folder with a readable name, and update the note's banner property. If a service blocks a method, try another available method and report the concrete error only after attempts fail.
        Change notes with your Edit and Write tools rather than shell commands where you can (Sage keeps a copy of each file the moment you start editing it, so I can undo), and don't delete files unless I ask.
        """
        return prompt
    }

    // MARK: Running the CLI

    /// The CLI's PATH, as Vault Agent's: what the app has, then the places CLIs install to (Homebrew, npm, pip's user
    /// folders) and Vault Agent's own tools folder in the vault (its yt-dlp), so the agent finds them.
    static func agentPath(vault: URL, home: URL, current: String, pythonVersions: [String]) -> String {
        let extra = [vault.appendingPathComponent(".obsidian/plugins/vault-agent/bin").path, home.appendingPathComponent(".local/bin").path,
                     "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin",
                     home.appendingPathComponent(".npm-global/bin").path, home.appendingPathComponent(".npm/bin").path, "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            + pythonVersions.map { home.appendingPathComponent("Library/Python/\($0)/bin").path }
        var seen = Set<String>()
        return (current.split(separator: ":").map(String.init) + extra).filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }

    /// Claude's arguments, Vault Agent's: a first turn fixes the session's id, later turns resume it.
    static func claudeArguments(_ settings: AgentSettings, session: String, resume: Bool) -> [String] {
        var arguments = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
        if !settings.claudeModel.isEmpty { arguments += ["--model", settings.claudeModel] }
        arguments += ["--permission-mode", settings.permissionMode.isEmpty ? "bypassPermissions" : settings.permissionMode]
        if !settings.claudeEffort.isEmpty { arguments += ["--effort", settings.claudeEffort] }
        return arguments + (resume ? ["--resume", session] : ["--session-id", session])
    }

    /// Codex's arguments (`codex exec --json`, resuming a thread when there is one), its sandbox from the permission mode
    /// as Vault Agent sets it; the prompt comes on stdin ("-").
    static func codexArguments(_ settings: AgentSettings, session: String?) -> [String] {
        var arguments = ["exec"] + (session.map { ["resume", $0] } ?? []) + ["--json", "--skip-git-repo-check"]
        if !settings.codexModel.isEmpty { arguments += ["--model", settings.codexModel] }
        if !settings.codexEffort.isEmpty { arguments += ["-c", "model_reasoning_effort=\"\(settings.codexEffort)\""] }
        switch settings.permissionMode {
        case "bypassPermissions": arguments += ["--dangerously-bypass-approvals-and-sandbox"]
        case "plan": arguments += ["-c", "sandbox_mode=\"read-only\"", "-c", "approval_policy=\"never\""]
        default: arguments += ["-c", "sandbox_mode=\"workspace-write\"", "-c", "approval_policy=\"never\""]
        }
        return arguments + ["-"]
    }

    // MARK: Reading the stream

    /// A step the agent took, shown under its reply: what (`kind`: read, edit, write, run, search, find, web, websearch,
    /// plan, task, other; say for a line from Sage's media tools), on what (a path in the vault, a command, a pattern),
    /// and whether it failed. `id` is the tool call's, to mark its result.
    struct AgentStep: Codable, Equatable {
        var id = ""
        var kind: String
        var target = ""
        var failed: Bool? = nil

        static let formats = ["read": "Reading %@", "edit": "Editing %@", "write": "Writing %@", "run": "Running %@", "search": "Searching for “%@”",
                              "find": "Finding files “%@”", "web": "Fetching %@", "websearch": "Searching the web for “%@”", "plan": "Planning",
                              "task": "Handing part to a helper: %@"]
        /// How it's said, with %@ for its target (put through L() on screen).
        var format: String { Self.formats[kind] ?? "%@" }
        var english: String { format.replacingOccurrences(of: "%@", with: target) }
    }

    /// What one line of the CLI's output means.
    enum AgentEvent: Equatable {
        /// The session's id, to resume it next turn.
        case session(String)
        /// Reply text, streamed in pieces.
        case text(String)
        /// A tool call; `file` is the file it is about to change (Edit, Write), so Sage can keep a copy first.
        case step(AgentStep, file: String?)
        /// A tool call's result came back.
        case result(id: String, failed: Bool)
        /// The run ended: why it failed (nil: it didn't), and its last reply as a whole.
        case finished(error: String?, text: String)
        /// Something went wrong mid-run (Codex says so in its own event).
        case failure(String)
    }

    /// A path as the steps show it: from the vault when it's inside, else from the home folder (~/…).
    static func shownPath(_ path: String, vault: URL) -> String {
        guard path.hasPrefix("/") else { return path }
        if let inside = vaultPath(path, in: vault) { return inside }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// A full path's place in the vault, or nil when it's outside. Works for a file not made yet too, and whether the
    /// path came as /private/tmp/… or /tmp/… (the CLI and Foundation don't always agree).
    static func vaultPath(_ path: String, in vault: URL) -> String? {
        func plain(_ path: String) -> String {
            let standard = URL(fileURLWithPath: path).standardizedFileURL.path
            return standard.hasPrefix("/private/") ? String(standard.dropFirst("/private".count)) : standard
        }
        let root = plain(vault.path), full = plain(path)
        guard full.count > root.count + 1, full.lowercased().hasPrefix(root.lowercased() + "/") else { return nil }
        return String(full.dropFirst(root.count + 1))
    }

    static func shortened(_ text: String, _ count: Int = 70) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let more = line.count < text.trimmingCharacters(in: .whitespacesAndNewlines).count
        return line.count > count ? String(line.prefix(count - 1)) + "…" : line + (more ? " …" : "")
    }

    /// One line of `claude -p --output-format stream-json --verbose --include-partial-messages`. Text comes from the
    /// partial messages' text deltas (a subagent's own text is left out); tool calls from the assistant messages (their
    /// input is whole there); results from the tool results; the session from init and the result.
    static func claudeEvents(_ line: String, vault: URL) -> [AgentEvent] {
        guard let event = json(Data(line.utf8)) else { return [] }
        let inSubagent = !((event["parent_tool_use_id"] as? String) ?? "").isEmpty
        switch event["type"] as? String ?? "" {
        case "system":
            guard event["subtype"] as? String == "init", let id = event["session_id"] as? String else { return [] }
            return [.session(id)]
        case "stream_event":
            guard !inSubagent, let inner = event["event"] as? [String: Any], inner["type"] as? String == "content_block_delta",
                  let delta = inner["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String, !text.isEmpty else { return [] }
            return [.text(text)]
        case "assistant":
            let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.filter { $0["type"] as? String == "tool_use" }.map { claudeTool($0, vault: vault) }
        case "user":
            let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.filter { $0["type"] as? String == "tool_result" }.map { .result(id: $0["tool_use_id"] as? String ?? "", failed: $0["is_error"] as? Bool == true) }
        case "result":
            let failed = event["is_error"] as? Bool == true
            let first = (event["errors"] as? [Any])?.first
            let reason = (first as? String) ?? ((first as? [String: Any])?["message"] as? String) ?? (event["result"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "The run failed."
            return [.finished(error: failed ? reason : nil, text: event["result"] as? String ?? "")]
        default:
            return []
        }
    }

    /// A Claude tool call as a step, as Vault Agent's buildToolCall names it.
    static func claudeTool(_ block: [String: Any], vault: URL) -> AgentEvent {
        let id = block["id"] as? String ?? UUID().uuidString
        let name = block["name"] as? String ?? "tool"
        let input = block["input"] as? [String: Any] ?? [:]
        let value = { (key: String) in (input[key] as? String) ?? "" }
        let file = value("file_path").isEmpty ? value("notebook_path") : value("file_path")
        let full = file.isEmpty ? nil : (file.hasPrefix("/") ? file : vault.appendingPathComponent(file).path)
        let shown = file.isEmpty ? "" : shownPath(full ?? file, vault: vault)
        switch name {
        case "Read": return .step(AgentStep(id: id, kind: "read", target: shown), file: nil)
        case "Edit", "MultiEdit", "NotebookEdit": return .step(AgentStep(id: id, kind: "edit", target: shown), file: full)
        case "Write": return .step(AgentStep(id: id, kind: "write", target: shown), file: full)
        case "Bash": return .step(AgentStep(id: id, kind: "run", target: shortened(value("command"))), file: nil)
        case "Grep": return .step(AgentStep(id: id, kind: "search", target: value("pattern")), file: nil)
        case "Glob": return .step(AgentStep(id: id, kind: "find", target: value("pattern")), file: nil)
        case "WebFetch": return .step(AgentStep(id: id, kind: "web", target: value("url")), file: nil)
        case "WebSearch": return .step(AgentStep(id: id, kind: "websearch", target: value("query")), file: nil)
        case "TodoWrite": return .step(AgentStep(id: id, kind: "plan"), file: nil)
        case "Task", "Agent": return .step(AgentStep(id: id, kind: "task", target: value("description")), file: nil)
        default:
            let argument = ["file_path", "path", "pattern", "command", "query", "url"].map(value).first { !$0.isEmpty } ?? ""
            return .step(AgentStep(id: id, kind: "other", target: argument.isEmpty ? name : name + " " + shortened(argument)), file: nil)
        }
    }

    /// One line of `codex exec --json`: its thread (to resume), messages (whole, not in pieces), commands, file changes and
    /// errors, in its current shape and the older msg-wrapped one, as Vault Agent reads them. Codex reports a file change
    /// once it's made, so its files can't be copied before they change.
    static func codexEvents(_ line: String, vault: URL) -> [AgentEvent] {
        guard let event = json(Data(line.utf8)) else { return [] }
        let type = event["type"] as? String ?? ""
        switch type {
        case "thread.started", "session.created":
            return ((event["thread_id"] ?? event["session_id"]) as? String).map { [.session($0)] } ?? []
        case "item.delta", "response.output_text.delta":
            return ((event["delta"] ?? event["text"]) as? String).map { [.text($0)] } ?? []
        case "item.started", "item.completed":
            let item = event["item"] as? [String: Any] ?? [:]
            let id = item["id"] as? String ?? ""
            let started = type == "item.started"
            switch item["type"] as? String ?? "" {
            case "agent_message", "assistant_message":
                guard !started, let text = item["text"] as? String, !text.isEmpty else { return [] }
                return [.text(text)]
            case "command_execution":
                if started { return [.step(AgentStep(id: id, kind: "run", target: shortened(item["command"] as? String ?? "")), file: nil)] }
                let code = (item["exit_code"] as? NSNumber)?.intValue ?? 0
                return [.step(AgentStep(id: id, kind: "run", target: shortened(item["command"] as? String ?? "")), file: nil), .result(id: id, failed: code != 0)]
            case "file_change":
                let paths = (item["changes"] as? [[String: Any]])?.compactMap { $0["path"] as? String } ?? (item["path"] as? String).map { [$0] } ?? []
                let shown = paths.map { shownPath($0, vault: vault) }
                let target = shown.first.map { shown.count > 1 ? "\($0) (+\(shown.count - 1))" : $0 } ?? ""
                return [.step(AgentStep(id: id, kind: "edit", target: target, failed: item["status"] as? String == "failed" ? true : nil), file: nil)]
            case "mcp_tool_call":
                guard started else { return [] }
                let name = [item["server"] as? String, item["tool"] as? String].compactMap { $0 }.joined(separator: ".")
                return [.step(AgentStep(id: id, kind: "other", target: name.isEmpty ? "tool" : name), file: nil)]
            case "web_search":
                guard started else { return [] }
                return [.step(AgentStep(id: id, kind: "websearch", target: item["query"] as? String ?? ""), file: nil)]
            case "todo_list":
                guard started else { return [] }
                return [.step(AgentStep(id: id, kind: "plan"), file: nil)]
            case "tool_call":
                guard started else { return [] }
                return [.step(AgentStep(id: id, kind: "other", target: (item["name"] as? String ?? "Tool") + " " + shortened(item["arguments"] as? String ?? "")), file: nil)]
            default:
                return []
            }
        case "error":
            return [.failure(codexReason(event["message"]))]
        case "turn.failed":
            return [.finished(error: codexReason((event["error"] as? [String: Any])?["message"] ?? event["error"]), text: "")]
        case "turn.completed":
            return [.finished(error: nil, text: "")]
        default:
            guard let message = event["msg"] as? [String: Any] else { return [] }
            switch message["type"] as? String ?? "" {
            case "agent_message": return (message["message"] as? String).map { [.text($0)] } ?? []
            case "agent_message_delta": return (message["delta"] as? String).map { [.text($0)] } ?? []
            case "exec_command_begin":
                let command = (message["command"] as? [String])?.joined(separator: " ") ?? "command"
                return [.step(AgentStep(id: message["call_id"] as? String ?? command, kind: "run", target: shortened(command)), file: nil)]
            default: return []
            }
        }
    }

    /// Codex's error message, which is often the service's JSON answer as a string: its own message when it is.
    static func codexReason(_ value: Any?) -> String {
        let text = (value as? String) ?? "Codex couldn't finish."
        guard let answer = json(Data(text.utf8)) else { return text }
        return ((answer["error"] as? [String: Any])?["message"] as? String) ?? (answer["message"] as? String) ?? text
    }

    // MARK: What a run changed

    /// The vault's files a run changed, made and removed, by their paths in the vault (folders aside), from the vault read
    /// before and after it (each file's modified date).
    struct VaultChanges: Codable, Equatable {
        var changed: [String] = [], made: [String] = [], gone: [String] = []
        var isEmpty: Bool { changed.isEmpty && made.isEmpty && gone.isEmpty }
        var all: [String] { changed + made + gone }
    }

    static func vaultChanges(before: [VaultItem], after: [VaultItem]) -> VaultChanges {
        let was = Dictionary(before.filter { !$0.folder }.map { ($0.path, $0.modified) }, uniquingKeysWith: { a, _ in a })
        let now = Dictionary(after.filter { !$0.folder }.map { ($0.path, $0.modified) }, uniquingKeysWith: { a, _ in a })
        let order = { (a: String, b: String) in a.localizedStandardCompare(b) == .orderedAscending }
        return VaultChanges(changed: now.filter { path, date in was[path].map { $0 != date } ?? false }.map(\.key).sorted(by: order),
                            made: now.keys.filter { was[$0] == nil }.sorted(by: order),
                            gone: was.keys.filter { now[$0] == nil }.sorted(by: order))
    }

    /// The changes Undo can take back: each file copied before the run touched it (`backups`, by full path; nil: it
    /// wasn't there) against what it holds now (`read`). Files that read as they did are left out.
    static func agentUndo(backups: [String: Data?], read: (String) -> Data?) -> [Change] {
        backups.keys.sorted().compactMap { path in
            let file = URL(fileURLWithPath: path), before = backups[path] ?? nil, after = read(path)
            switch (before, after) {
            case (nil, let after?): return .created(file, after)
            case (let before?, let after?) where before != after: return .edited(file, before: before, after: after)
            case (let before?, nil): return .removed(file, before)
            default: return nil
            }
        }
    }
}

/// The files Sage copies before a run changes them: the open note first, then each file the moment its Edit or Write call
/// shows in the stream (on the thread reading it, before anything else is done with the line). Best effort: the CLI runs
/// the tool right after printing the call, so a copy can lose that race and hold the new text (then Undo finds nothing to
/// take back); files changed by a shell command (Bash), by Codex (it reports changes once made) or outside the vault are
/// never copied, and are only listed.
final class SageAgentBackups: @unchecked Sendable {
    private let lock = NSLock()
    private var before: [String: Data?] = [:]
    let vault: URL, keep: URL

    init(vault: URL, keep: URL) { self.vault = vault; self.keep = keep }

    /// Copies the file as it is now (into sage/edited/ too), once a run; a file not there yet is noted as new.
    func keep(_ file: URL) {
        let path = file.standardizedFileURL.path
        guard Study.vaultPath(path, in: vault) != nil else { return }
        lock.lock()
        let seen = before.keys.contains(path)
        lock.unlock()
        guard !seen else { return }
        let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        if let data { Study.keep(data, of: file, in: keep) }
        lock.lock()
        if !before.keys.contains(path) { before[path] = .some(data) }
        lock.unlock()
    }

    var copies: [String: Data?] { lock.lock(); defer { lock.unlock() }; return before }
}

/// The CLI run as an agent: started through the CLI worker so it owns a process group (Stop ends the commands it started
/// too), its stdout read line by line on a thread of its own, in order.
final class SageAgentProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var stoppedFlag = false
    var stopped: Bool { lock.lock(); defer { lock.unlock() }; return stoppedFlag }

    /// Starts the CLI in `directory` with `input` on stdin. `line` is told each line of stdout on the reading thread;
    /// `exit` on the main queue after the last line, with the exit status and the end of stderr (never shown as it is:
    /// a CLI's stderr can hold private configuration).
    func start(executable: URL, arguments: [String], input: Data, directory: URL, environment: [String: String],
               line: @escaping @Sendable (String) -> Void, exit: @escaping @Sendable (Int32, String) -> Void) throws {
        let worker = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("CLIWorker")
        if FileManager.default.isExecutableFile(atPath: worker.path) {
            process.executableURL = worker
            process.arguments = [executable.path] + arguments
        } else {
            process.executableURL = executable
            process.arguments = arguments
        }
        process.currentDirectoryURL = directory
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        try process.run()
        // The prompt written then closed, so the CLI starts (written off the main thread: a long one fills the pipe).
        DispatchQueue.global(qos: .userInitiated).async {
            try? stdin.fileHandleForWriting.write(contentsOf: input)
            try? stdin.fileHandleForWriting.close()
        }
        let errors = SageAgentTail()
        Thread.detachNewThread {
            while true {
                let chunk = stderr.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                errors.add(chunk)
            }
        }
        let process = process
        Thread.detachNewThread {
            var buffer = Data()
            func emit(_ bytes: Data) {
                var text = String(decoding: bytes, as: UTF8.self)
                if text.hasSuffix("\r") { text.removeLast() }
                if !text.isEmpty { line(text) }
            }
            while true {
                let chunk = stdout.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 10) {
                    emit(buffer[buffer.startIndex ..< newline])
                    buffer.removeSubrange(buffer.startIndex ... newline)
                }
            }
            if !buffer.isEmpty { emit(buffer) }
            ended.wait()
            let status = process.terminationStatus, tail = errors.text
            DispatchQueue.main.async { exit(status, tail) }
        }
    }

    /// Ends the run and what it started: asked first, then made to.
    func stop() {
        lock.lock(); stoppedFlag = true; lock.unlock()
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        let group = getpgid(pid) == pid
        _ = group ? kill(-pid, SIGTERM) : kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
            if process.isRunning { _ = group ? kill(-pid, SIGKILL) : kill(pid, SIGKILL) }
        }
    }
}

/// The last few kilobytes of a stream.
private final class SageAgentTail: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func add(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        if data.count > 16_000 { data = data.suffix(8_000) }
    }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}
