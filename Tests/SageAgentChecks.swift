import Foundation

/// Sage as an agent (2026-11-09, Vault Agent brought into Sage): its commands, prompts, the CLI's stream read, what a run
/// changed and what Undo puts back, models, memories and the chat's Markdown. Temp folders only, never your vault.
extension Checks {
    @MainActor static func sageAgent(_ check: Check) throws {
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("sage-agent-\(UUID().uuidString)", isDirectory: true).standardizedFileURL
        defer { try? fm.removeItem(at: vault) }
        try fm.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)

        // Vault Agent's commands, word for word.
        check(Study.slash("/summarize in three bullets")! == ("summarize", "in three bullets") && Study.slash("  /process ")! == ("process", "")
              && Study.slash("/unknown thing") == nil && Study.slash("summarize this") == nil && Study.slash("/localize") == nil && Study.slash("/MEMORY")?.name == "memory",
              "A message starting with one of Vault Agent's commands is read as it; anything else is an ordinary message")
        let process = Study.expandSlash("/process", active: "Clippings/Reel.md")
        check(process == "Process the note at \"Clippings/Reel.md\" according to this vault's conventions in CLAUDE.md: extract the real content, wikilink concepts and transferable quotes, fix frontmatter, and rewrite it in place. Suggest a better title in the chat but do not create a new file."
              && Study.expandSlash("/summarize in three bullets", active: "A.md").hasSuffix("Don't edit the note unless I ask.\n\nAdditional instruction: in three bullets")
              && Study.expandSlash("/summarize", active: nil) == "Summarize the active note in chat. Ask which note if none is open."
              && Study.expandSlash("/fetch", active: "A.md") == "/fetch" && Study.expandSlash("tidy this note", active: "A.md") == "tidy this note",
              "A command becomes Vault Agent's prompt for the open note, the words after it an Additional instruction; media commands and plain words stay")
        check(Study.quickCommands.filter(\.shortcut).map(\.name) == ["process", "summarize", "review"]
              && ["categorize", "links", "rename", "memory", "fetch", "transcribe", "localize"].allSatisfy { Study.quickCommand($0) != nil },
              "Process, Summarize and Review are the note bar's buttons; the rest are in its menu")

        // The prompt, built as Vault Agent builds it.
        let memories = [Study.AgentMemory(path: "M/a.md", text: "Prefer short notes", category: "preference", pinned: true),
                        Study.AgentMemory(path: "M/b.md", text: "Banners come from the channel avatar")]
        let prompt = Study.agentPrompt("Do it", active: "Clippings/Reel.md", memories: memories, memoryFolder: "System/Vault Agent/Memories", instructions: "Use Categories.")
        let order = ["[Project instructions", "Use Categories.", "[Context] The note currently open in Sage is \"Clippings/Reel.md\"", "[Saved memories]", "- [pinned] Prefer short notes",
                     "Do it", "[Memories] Keep persistent memories as Markdown notes in the vault folder \"System/Vault Agent/Memories\"", "[Sage runtime capabilities"]
        let places = order.compactMap { prompt.range(of: $0)?.lowerBound }
        check(places.count == order.count && places == places.sorted(),
              "The agent's prompt: the vault's instructions (Codex), the open note, memories, the request, where memories go, what it can do")
        let plain = Study.agentPrompt("Do it", active: nil, memories: [], memoryFolder: "Mem")
        check(!plain.contains("[Project instructions") && !plain.contains("[Context]") && !plain.contains("[Saved memories]") && plain.hasPrefix("Do it"),
              "Claude's prompt carries no copy of CLAUDE.md (it reads it itself), and nothing about a note when none is open")

        // Memories, as Vault Agent keeps and picks them.
        let note = "---\nType: Memory\nCategory: preference\nPinned: false\nCreated: 2026-11-01\nUses: 4\nSource: Vault Agent\n---\n\nAlways write titles in sentence case\n"
        let read = Study.memory(path: "Mem/Titles.md", note: note)
        check(read == Study.AgentMemory(path: "Mem/Titles.md", text: "Always write titles in sentence case", category: "preference", pinned: false, uses: 4)
              && Study.memory(path: "x.md", note: "---\nType: Memory\n---\n\n") == nil,
              "A memory note reads as Vault Agent reads it: its header's category, pin and uses, its body the memory")
        let pool = [Study.AgentMemory(path: "a", text: "Pinned rule", pinned: true), Study.AgentMemory(path: "b", text: "Banner images come from channel avatars"),
                    Study.AgentMemory(path: "c", text: "Recipes use metric units", category: "preference"), Study.AgentMemory(path: "d", text: "Unrelated thing about taxes")]
        let picked = Study.relevantMemories(pool, for: "set the banner from the channel")
        check(picked.map(\.path) == ["a", "b"] && Study.relevantMemories(pool, for: "what style do I prefer").map(\.path).contains("c"),
              "The memories given: every pinned one, then those sharing the request's words (a preference when it asks what you prefer)")
        try fm.createDirectory(at: vault.appendingPathComponent("Mem"), withIntermediateDirectories: true)
        try Data(note.utf8).write(to: vault.appendingPathComponent("Mem/Titles.md"))
        check(Study.memories(in: vault.appendingPathComponent("Mem"), vault: vault).map(\.path) == ["Mem/Titles.md"], "The memories folder's notes are read as memories")

        // The CLI's arguments and PATH.
        var settings = Study.AgentSettings()
        check(settings.claudeModel.isEmpty && settings.codexModel.isEmpty && settings.permissionMode == "bypassPermissions" && settings.memoryFolder == "System/Vault Agent/Memories",
              "No default model (Sage asks); Vault Agent's permission mode and memory folder")
        settings.claudeModel = "opus"; settings.claudeEffort = "medium"
        check(Study.claudeArguments(settings, session: "S1", resume: false) == ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--model", "opus",
                                                                              "--permission-mode", "bypassPermissions", "--effort", "medium", "--session-id", "S1"]
              && Study.claudeArguments(settings, session: "S1", resume: true).suffix(2) == ["--resume", "S1"],
              "Claude runs as Vault Agent runs it: streaming, the model, permission mode and effort, a session fixed then resumed")
        settings.codexModel = "gpt-6-luna"
        check(Study.codexArguments(settings, session: nil) == ["exec", "--json", "--skip-git-repo-check", "--model", "gpt-6-luna", "--dangerously-bypass-approvals-and-sandbox", "-"]
              && Study.codexArguments(settings, session: "T9").prefix(3) == ["exec", "resume", "T9"],
              "Codex runs as `codex exec --json`, resuming its thread, the prompt on stdin")
        let path = Study.agentPath(vault: vault, home: URL(fileURLWithPath: "/Users/me"), current: "/usr/bin:/opt/homebrew/bin", pythonVersions: ["3.12"])
        check(path.hasPrefix("/usr/bin:/opt/homebrew/bin:") && path.contains(vault.path + "/.obsidian/plugins/vault-agent/bin") && path.contains("/Users/me/Library/Python/3.12/bin")
              && path.components(separatedBy: ":").filter { $0 == "/usr/bin" }.count == 1,
              "The agent's PATH has Vault Agent's tools (its yt-dlp), Homebrew, npm and pip's folders, each once")

        // Vault Agent's settings: only six keys read from its data.json.
        let saved = Data(#"{"claudeModel":"claude-sonnet-5","claudeEffort":"medium","permissionMode":"plan","memoryFolder":"/System/Mem/","chatSessions":[{"x":1}],"customInstructions":"secret"}"#.utf8)
        let fromVaultAgent = Study.vaultAgentSettings(saved)
        check(fromVaultAgent.claudeModel == "claude-sonnet-5" && fromVaultAgent.claudeEffort == "medium" && fromVaultAgent.permissionMode == "plan"
              && fromVaultAgent.memoryFolder == "System/Mem" && fromVaultAgent.codexModel.isEmpty && Study.vaultAgentSettings(Data("x".utf8)) == Study.AgentSettings(),
              "Vault Agent's choice of model and effort, permission mode and memory folder are read from its data.json; nothing else")

        // Models the CLIs offer.
        let help = """
          --effort <level>                      Effort level for the current session
                                                (low, medium, high, xhigh, max)
          --model <model>                       Model for the current session. Provide
                                                an alias for the latest model (e.g.
                                                'fable', 'opus', or 'sonnet') or a
                                                model's full name (e.g.
                                                'claude-fable-5').
          --permission-mode <mode>              Permission mode
        """
        let claude = Study.claudeModels(help: help, extra: ["claude-sonnet-5", "opus"])
        check(claude.prefix(4).map(\.id) == ["fable", "opus", "sonnet", "haiku"] && claude.prefix(4).allSatisfy(\.alias)
              && ["claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5", "claude-sonnet-5"].allSatisfy { id in claude.contains { $0.id == id && !$0.alias } }
              && claude.filter { $0.id == "opus" }.count == 1 && claude[0].efforts == ["low", "medium", "high", "xhigh", "max"]
              && Study.claudeModels(help: "").prefix(4).map(\.id) == ["opus", "sonnet", "haiku", "fable"],
              "Claude's models: its aliases first (always the newest, read from its help), then full ids, yours and Vault Agent's, with its efforts")
        let cache = Data(#"{"models":[{"slug":"b","display_name":"B","priority":2,"visibility":"list","supported_reasoning_levels":[{"effort":"low"},{"effort":"high"}]},{"slug":"hidden","priority":0,"visibility":"hide"},{"slug":"a","display_name":"A","priority":1,"supported_reasoning_levels":["low","medium"]}]}"#.utf8)
        check(Study.codexModels(cache: cache).map(\.id) == ["a", "b"] && Study.codexModels(cache: cache)[1].efforts == ["low", "high"],
              "Codex's models are those it lists itself, in its order, with their efforts")

        // Reading Claude's stream (lines as `claude -p --output-format stream-json --include-partial-messages` prints them).
        let file = vault.appendingPathComponent("Clippings/Reel.md").path
        let lines = [
            #"{"type":"system","subtype":"init","cwd":"/v","session_id":"S-1","tools":["Read"]}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"All"}},"session_id":"S-1","parent_tool_use_id":null}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"inside"}},"parent_tool_use_id":"toolu_9"}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hm"}}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"\#(file)","old_string":"a","new_string":"b"}}]},"session_id":"S-1"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"yt-dlp -o x 'https://example.com/v'\nls"}}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"All done."}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"t2","type":"tool_result","content":"boom","is_error":true}]}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":"All done.","session_id":"S-1"}"#,
            #"{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["No conversation found with session ID: S-0"],"result":""}"#,
            "not json",
        ]
        let events = lines.map { Study.claudeEvents($0, vault: vault) }
        check(events[0] == [.session("S-1")] && events[1] == [.text("All")] && events[2].isEmpty && events[3].isEmpty && events[6].isEmpty && events[10].isEmpty,
              "Claude's stream: the session, the reply's text pieces (a subagent's own text, thinking and the whole message left out)")
        check(events[4] == [.step(Study.AgentStep(id: "t1", kind: "edit", target: "Clippings/Reel.md"), file: file)]
              && events[5] == [.step(Study.AgentStep(id: "t2", kind: "run", target: "yt-dlp -o x 'https://example.com/v' …"), file: nil)]
              && events[7] == [.result(id: "t2", failed: true)],
              "A tool call is a step with the file's path in the vault (an edit names the file to copy first); a failed result marks it")
        check(events[8] == [.finished(error: nil, text: "All done.")] && events[9] == [.finished(error: "No conversation found with session ID: S-0", text: "")],
              "The run's end: its last reply, or why it failed")
        check(Study.AgentStep(kind: "read", target: "A.md").english == "Reading A.md" && Study.AgentStep(kind: "plan").english == "Planning"
              && Study.AgentStep.formats.values.allSatisfy { Vietnamese.text[$0] != nil },
              "Steps say what the agent is doing, in your language")
        let outside = Study.claudeEvents(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t3","name":"Read","input":{"file_path":"\#(fm.homeDirectoryForCurrentUser.path)/x.txt"}}]}}"#, vault: vault)
        check(Study.vaultPath("/private/tmp/v/Notes/New.md", in: URL(fileURLWithPath: "/tmp/v")) == "Notes/New.md"
              && Study.vaultPath("/tmp/vault2/x.md", in: URL(fileURLWithPath: "/tmp/vault")) == nil && Study.vaultPath("/tmp/v", in: URL(fileURLWithPath: "/tmp/v")) == nil,
              "A file the agent is about to make is placed in the vault however its path is written")
        check(outside == [.step(Study.AgentStep(id: "t3", kind: "read", target: "~/x.txt"), file: nil)], "A file outside the vault is shown from the home folder")

        // Reading Codex's stream.
        let codex = [
            #"{"type":"thread.started","thread_id":"01a1-thread"}"#,
            #"{"type":"item.started","item":{"id":"i1","type":"command_execution","command":"bash -lc ls","status":"in_progress"}}"#,
            #"{"type":"item.completed","item":{"id":"i1","type":"command_execution","command":"bash -lc ls","exit_code":1,"status":"failed"}}"#,
            #"{"type":"item.completed","item":{"id":"i2","type":"file_change","changes":[{"path":"\#(file)","kind":"update"},{"path":"\#(vault.path)/B.md","kind":"add"}],"status":"completed"}}"#,
            #"{"type":"item.completed","item":{"id":"i3","type":"agent_message","text":"Done it."}}"#,
            #"{"type":"error","message":"{\"type\":\"error\",\"status\":400,\"error\":{\"type\":\"invalid_request_error\",\"message\":\"The 'gpt-6.1-sol' model is not supported when using Codex with a ChatGPT account.\",\"code\":\"model_not_found\"}}"}"#,
            #"{"type":"turn.failed","error":{"message":"plain failure"}}"#,
            #"{"type":"turn.completed","usage":{}}"#,
        ].map { Study.codexEvents($0, vault: vault) }
        check(codex[0] == [.session("01a1-thread")] && codex[1] == [.step(Study.AgentStep(id: "i1", kind: "run", target: "bash -lc ls"), file: nil)]
              && codex[2].last == .result(id: "i1", failed: true) && codex[3] == [.step(Study.AgentStep(id: "i2", kind: "edit", target: "Clippings/Reel.md (+1)"), file: nil)]
              && codex[4] == [.text("Done it.")]
              && codex[5] == [.failure("The 'gpt-6.1-sol' model is not supported when using Codex with a ChatGPT account.")]
              && codex[6] == [.finished(error: "plain failure", text: "")] && codex[7] == [.finished(error: nil, text: "")],
              "Codex's stream: its thread, commands and their failures, file changes, messages, and its errors in plain words")

        // What a run changed, and what Undo can put back.
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let before = [Study.VaultItem(path: "A.md", folder: false, modified: day), Study.VaultItem(path: "B.md", folder: false, modified: day),
                      Study.VaultItem(path: "C.md", folder: false, modified: day), Study.VaultItem(path: "F", folder: true, modified: day)]
        let after = [Study.VaultItem(path: "A.md", folder: false, modified: day.addingTimeInterval(5)), Study.VaultItem(path: "B.md", folder: false, modified: day),
                     Study.VaultItem(path: "F/New 2.md", folder: false, modified: day), Study.VaultItem(path: "F/New 10.md", folder: false, modified: day),
                     Study.VaultItem(path: "F", folder: true, modified: day.addingTimeInterval(9))]
        check(Study.vaultChanges(before: before, after: after) == Study.VaultChanges(changed: ["A.md"], made: ["F/New 2.md", "F/New 10.md"], gone: ["C.md"]),
              "A run's files: changed (a new modified date), made and removed, folders aside")
        let edited = vault.appendingPathComponent("edited.md"), made = vault.appendingPathComponent("made.md"), removed = vault.appendingPathComponent("removed.md")
        let same = vault.appendingPathComponent("same.md")
        try Data("new".utf8).write(to: edited); try Data("made".utf8).write(to: made); try Data("same".utf8).write(to: same)
        var copied: [String: Data?] = [:]
        copied[edited.path] = .some(Data("old".utf8)); copied[made.path] = .some(nil)
        copied[removed.path] = .some(Data("gone".utf8)); copied[same.path] = .some(Data("same".utf8))
        let changes = Study.agentUndo(backups: copied, read: { try? Data(contentsOf: URL(fileURLWithPath: $0)) })
        let expected: [Study.Change] = [.edited(edited, before: Data("old".utf8), after: Data("new".utf8)), .created(made, Data("made".utf8)), .removed(removed, Data("gone".utf8))]
        check(changes == expected,
              "Undo has each file copied before the run that reads differently now: edited, made or removed")
        check(changes.allSatisfy(Study.undo) && (try? Data(contentsOf: edited)) == Data("old".utf8) && !fm.fileExists(atPath: made.path)
              && (try? Data(contentsOf: removed)) == Data("gone".utf8),
              "Undo puts each back: the old text, the new file gone, the removed file returned")
        try Data("changed by you".utf8).write(to: edited)
        check(!Study.undo(.edited(edited, before: Data("x".utf8), after: Data("old".utf8))) && (try? Data(contentsOf: edited)) == Data("changed by you".utf8)
              && !Study.undo(.removed(removed, Data("other".utf8))),
              "A file changed since the run (or back already) is left as it is")
        let keep = vault.appendingPathComponent("sage", isDirectory: true)
        let backups = SageAgentBackups(vault: vault, keep: keep)
        backups.keep(edited); try Data("later".utf8).write(to: edited); backups.keep(edited)
        backups.keep(vault.appendingPathComponent("not yet.md")); backups.keep(URL(fileURLWithPath: "/tmp/outside.md"))
        check(backups.copies[edited.path] == .some(Data("changed by you".utf8)) && backups.copies[vault.appendingPathComponent("not yet.md").path] == .some(nil)
              && backups.copies.count == 2 && ((try? fm.contentsOfDirectory(atPath: keep.appendingPathComponent("edited").path)) ?? []).count == 1,
              "A file is copied once a run, as it was first (into Sage's edited folder); one not there yet is noted as new; nothing outside the vault")

        // Older chats still open: the new fields are optional.
        let old = Data(#"[{"id":"7B0F8A4E-6F15-4E8B-9C2D-1A2B3C4D5E6F","messages":[{"id":"8B0F8A4E-6F15-4E8B-9C2D-1A2B3C4D5E6F","fromSage":true,"text":"Hi","videos":[],"notes":[],"date":0}],"created":0,"updated":0}]"#.utf8)
        let decoded = try? JSONDecoder().decode([Study.Conversation].self, from: old)
        var message = Study.Message(fromSage: true, text: "x")
        message.steps = [Study.AgentStep(id: "t", kind: "edit", target: "A.md")]
        message.run = Study.AgentRun(provider: "Claude", model: "opus", effort: "high", files: Study.VaultChanges(changed: ["A.md"]), backedUp: ["A.md"])
        var conversation = Study.Conversation(messages: [message])
        conversation.agent = Study.AgentSession(id: "S-1", provider: "Claude", vault: "/v")
        let again = (try? JSONEncoder().encode([conversation])).flatMap { try? JSONDecoder().decode([Study.Conversation].self, from: $0) }
        check(decoded?.first?.agent == nil && decoded?.first?.messages.first?.run == nil && again?.first == conversation,
              "chats.json from before the agent still opens; a run's steps, files and session are kept with it")

        // The chat's Markdown.
        let blocks = Study.chatBlocks("""
        # Title
        Some **bold** text
        and more.

        - one
          - two
        - [x] done
        1. first
        2) second
        > quoted
        ```swift
        let x = 1
        ```
        | A | B |
        |---|:-:|
        | 1 | 2 |
        ---
        """)
        check(blocks == [.heading(level: 1, text: "Title"), .paragraph("Some **bold** text\nand more."), .bullet(level: 0, text: "one", checked: nil),
                         .bullet(level: 1, text: "two", checked: nil), .bullet(level: 0, text: "done", checked: true), .numbered(level: 0, number: "1", text: "first"),
                         .numbered(level: 0, number: "2", text: "second"), .quote("quoted"), .code(language: "swift", text: "let x = 1"),
                         .table(rows: [["A", "B"], ["1", "2"]]), .rule],
              "Sage's replies are read as Markdown: headings, paragraphs, nested and task bullets, numbered lists, quotes, code, tables and rules")
        check(Study.chatBlocks("#hashtag and 2024. was a year") == [.paragraph("#hashtag and 2024. was a year")] && Study.chatBlocks("") == [],
              "A #tag or a number in text is not a heading or a list")
        let inline = Study.chatInline("See [[Pho bò#Broth|the broth]] and [[Plan]], https://example.com/a.")
        check(inline == "See [the broth](sage-note:Pho%20b%C3%B2%23Broth) and [Plan](sage-note:Plan), <https://example.com/a>."
              && Study.noteLinkTarget(URL(string: "sage-note:Pho%20b%C3%B2%23Broth")!) == "Pho bò" && Study.noteLinkTarget(URL(string: "https://x.com")!) == nil,
              "A [[wikilink]] becomes a link that opens its note (alias shown, heading aside); a bare web address a link")
        let attributed = try? AttributedString(markdown: inline, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        check(attributed?.runs.compactMap(\.link).map(\.absoluteString) == ["sage-note:Pho%20b%C3%B2%23Broth", "sage-note:Plan", "https://example.com/a"],
              "The links survive Markdown's reading")
    }
}
