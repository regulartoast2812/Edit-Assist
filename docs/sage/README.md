# Sage, the research helper

Sage is personal, not Crossian's: he researches your topics on YouTube and the web and keeps notes in an Obsidian
vault. He was Basil, a recipe helper, until 2026-11-06; recipes are now one kind of topic. He is staged in
Edit Assist (macOS) and meant to move to the Windows app, which has the same helpers and functions. Nothing of his
touches projects, Premiere, Grafana or any Crossian account.

## Files

| File | What it is | Port |
|---|---|---|
| `Sources/SageStudy.swift` | `Study`: YouTube, recipes, notes in the vault, the chat. Foundation only. | Take as it is (Swift), or translate one function at a time; `Tests/Checks.swift` (the Sage checks) lists what each must do. |
| `Sources/SageResearch.swift` | `Study` too: topics, web pages, the research note. Foundation only. | Same. |
| `Sources/SageDesk.swift` | `SageDesk`: state, network calls, the key and the folder. | Rewrite: Keychain → Windows Credential Manager; `NSOpenPanel` → a folder picker; `UserDefaults` → the app's settings. |
| `Sources/Sage.swift` | His pixel icon and page (SwiftUI). | Rewrite in the Windows app's UI; the sprite rows and colours copy over as they are. |
| `Sources/SagePick.swift` | `Study` too: Pick for me as a curator (angles, filters, the rubric, the choice). Foundation only. | Came from the Windows app (`SagePick.cs`); keep the two alike. |
| `Sources/SagePlayer.swift` | The mini player's page and address (`Study`), and its web view. | Windows: WebView2 with a virtual host. |
| `Sources/SageDeskPick.swift`, `SagePickView.swift` | The desk's Pick and player, and their page parts (steps, outcome, playable pictures, the column lines, motion). | Windows: `SageDesk.cs`, `Sage.cs`. |
| `Sources/SageVault.swift`, `SageFiles.swift`, `SageObsidian.swift`, `SageBases.swift`, `SageNotes.swift` | The vault as Obsidian shows it, link updating, Obsidian's own look, Bases and canvases, the note page and its editing script. Foundation only. | Built first in Creative Assist (`SageVault.cs`, `SageFiles.cs`, `SageObsidian.cs`, `SageBases.cs`, `SageNotes.cs`) and brought back 2026-11-09, function for function; checked in `Tests/SageVaultChecks.swift`, `SageNotesChecks.swift`, `SageBasesChecks.swift`. |
| `Sources/SageVaultDesk.swift`, `SageDeskFiles.swift` | The notes stage's state (vault, tabs, tree settings in `sage/notes.json`, FSEvents) and the tree's changes to the vault with Undo. | Creative Assist's `SageDesk.cs` (vault and tabs parts) and `SageDeskFiles.cs`. |
| `Sources/SageMediaText.swift`, `SageMedia.swift` | Fetch media and Transcribe, ported from the Vault Agent plugin (`view.ts`): the note logic and what the tools print (Foundation only, checked in `Tests/SageMediaChecks.swift`), and the runner for yt-dlp, ffmpeg and WhisperX (Foundation `Process`). | Windows: the same tools as `.exe` (yt-dlp.exe, WhisperX's `Scripts\python.exe`), `Process` → `System.Diagnostics.Process`. |
| `Sources/SageExplorer.swift`, `SageColors.swift`, `SageNoteView.swift` | The tree, quick switcher, path bar and preview; the WKWebView note view (one per tab, served by a `WKURLSchemeHandler` under `sage://sage/`), the tab row and the bar. | Creative Assist's `SageExplorer.cs`, `SageColors.cs` and `Sage.cs` (`NoteView`, tabs). |

## How he works

0. **Topics.** `Study.Topic`: a name, a kind (`general` research notes or `recipes`) and its vault folder (chosen when
   its first note is written). Statuses: `to read`, `read`, `key` for research; `to try`, `made`, `favourite` for
   recipes. Searches add "recipe" only in recipe topics (`Study.search`). Kept in `sage/topics.json`; what you save
   carries its topic. Research notes (`Study.Brief`, `Study.briefSchema`, `Study.note(_:topic:)`): summary, key points,
   details, quotes, open questions, sources, with `topic` and `image` in the header. **Web pages** (`Study.Page`,
   `Study.page(fromHTML:url:)`): title, site, description and picture as the page declares them (og: and meta tags),
   and its readable text (an article or main element when there is one; scripts, menus, headers and footers left
   out). A link pasted in Find or dragged onto Saved is saved as a page (or as the video, for a YouTube link).

1. **Finding videos.** YouTube Data API v3 with your own API key (Google Cloud → enable YouTube Data API v3 →
   Credentials → API key). `search?part=snippet&type=video&maxResults=24&q=…` (100 units), then
   `videos?part=snippet,contentDetails,statistics&id=…` (1 unit) for length, views and the full description. The free
   quota is 10,000 units a day, so about 100 searches; it resets at midnight Pacific time. A key is kept only after
   YouTube takes it (one `videos` call). No scraping of youtube.com and no captions: those need YouTube's own apps.
2. **Reading the recipe.** The description's links, leaving out social and shop sites (`Study.notRecipes`), up to
   four, in order. The first page that publishes a schema.org `Recipe` in JSON-LD (most recipe sites do, for search
   engines) is the exact source. The page is fetched plainly, without imitating a browser; a page that refuses is skipped.
3. **Writing it.** One call to the helper brain (the Claude CLI; Codex as the backup) with no tools and the strict
   schema `Study.schema`: title, servings, prep, cook, total, cuisine, course, tags, ingredients, steps, notes. The
   prompt (`Study.rules`) forbids inventing amounts, times or steps; anything missing is said in a note. Your own
   words (Write your own) go through the same schema, keeping your amounts.
4. **The note.** `Study.note`: a YAML header Obsidian shows as properties (`title`, `status`, `source`, `channel`,
   `page`, `servings`, `prep`, `cook`, `total`, `cuisine`, `course`, `tags` with `recipe` first, `added`), the video
   embedded (`![](youtube link)`), then Ingredients, Steps (numbered) and Notes. The file is named after the dish with
   characters Windows refuses taken out, and never written over an existing note (`Study.fileName`: "Adobo 2.md").
5. **Tracking.** The recipes folder you choose (and the folders in it, `.obsidian` and hidden ones left out) is read
   into `Study.Entry` rows. `status` is `to try`, `made` or `favourite`; changing it rewrites only that header line
   (`Study.setting`). A video whose link is already a note's `source` shows "In your vault".
6. **Chat.** The left column of his one-page dashboard (Find and Your recipes in the middle, Saved and Write your own on the right). What he searches from the chat also fills Find. Each message is answered in up to three brain calls with `Study.chatSchema`
   (`reply`, `youtube`, `notes`, `show`): a call can ask for a YouTube search (12 videos) or notes to read by title
   (`Study.named`, at most 5), which the desk does and hands back in the next call (`Study.chatPrompt`); the last
   call must answer. Videos it lists in `show` appear with the answer as cards (Write recipe, watch). The prompt carries
   the notes list (title, status, cuisine, tags), the last 20 messages and the videos shown last. Saved in
   `sage/chats.json` as a history of conversations (`Study.Conversation`: titled by the first message, listed
   newest first with `Study.ago`, searched with `Study.find`; New chat keeps the old one). Search, chat and saving videos need no folder; it is asked for when a recipe is first written.
7. **Saving and picks.** Searches add "recipe" unless the words already ask for cooking (`Study.recipeSearch`).
   Saving a video (its Save button, or dragging it onto the save area right of the results) keeps it in the app to
   review (`Study.Saved`, `sage/saved.json`): nothing is written and no vault is needed. **Pick for me** works as a
   curator (`Sources/SagePick.swift`, from the Windows app, 2026-11-09): the brain gives up to two more search angles
   (`Study.anglesPrompt`, `angles(from:)`; three searches at most, 100 units each), merged in turn (`Study.merged`); code drops
   Shorts and videos under 2 minutes, what is saved or written, reuploads, music, reactions and compilations (mukbangs and eating
   shows for recipes; `Study.screen`); the brain marks every video left 0-5 on relevance, substance, credibility and density
   (`Study.scorePrompt`, `scoreSchema`, `marks(from:)`, junk-proof); code weighs them (40/25/20/15) with small like, view and
   recency signals and keeps only those at 70/100 or more, one per channel, no two covering the same thing, nothing covering what
   you have, at most five (`Study.choose`). Saving none is a fine answer: `PickOutcome.why` says what fell short, and Find lists
   everything passed over with why (`Study.Says`, translated on screen). `EDIT_ASSIST_SAGE_PICK_FIXTURE` points Pick at a folder
   of answers (`Tests/Fixtures/Sage`: angles.json, videos.json, scores.json) instead of YouTube and the brain.
   **The mini player** plays any video in Sage: `Study.playerPage` (YouTube's nocookie embed in an iframe) loaded with
   `Study.playerURL` (https://sage-player.example/player.html?v=…) as its address, so the embed has an origin and a referrer
   (without them it shows Error 153); only real-looking ids reach it (`Study.isVideoID`). A saved video's recipe
   is written (steps 2–4) only when you press Write recipe or Write all; the vault folder is asked for then.
8. **Notes stage** (2026-11-07 in Creative Assist, on the Mac 2026-11-09). Beside the chat, the page has two stages:
   Research (Find, Saved, Write your own) and Notes: your **whole vault** as Obsidian's file explorer shows it
   (`Study.vaultItems`, `explorerOrder` from workspace.json, `children`, `natural`), chosen once (Sage offers the one he
   finds), the tree on the left (resizable) and the open file beside it in tabs. A file is drawn by `Study.notePage`
   (`Sources/SageNotes.swift`) as Obsidian's reading view builds it, dressed by **Obsidian's own app.css, fonts and
   icons**, copied once per version from `/Applications/Obsidian.app/Contents/Resources/obsidian.asar` (or the newer
   one Obsidian downloads into `~/Library/Application Support/obsidian`, read only; `Study.obsidianStyle`) into the
   app's cache, then your enabled plugins' styles.css, theme and snippets; body `mod-macos`, no styled-scrollbars (as
   Obsidian on the Mac). Without Obsidian, `Study.baseCSS` stands in. Reading settings follow app.json (properties
   shown/hidden/source, inline title, readable line width, default view mode, spellcheck, tabs) and types.json.
   [[Links]] resolve as Obsidian resolves them (`Study.resolve`: by name, nearest first, by path); pictures keep their
   |size (`Study.withPictures`). Bases (`.base`: views, filters, formulas, sort, groups, chips), canvases and Vault
   Agent's file embeds are drawn by `Sources/SageBases.swift`. **Editing**: a block you click becomes Obsidian-style live
   preview; only its lines are written, and only if they still read as when the page was drawn (`Study.editLines`), the
   note kept first in `sage/edited/` and replaced in one step keeping its line endings, BOM and created date
   (`Study.writeNote`). A canvas opened on its own is edited as in Obsidian and saved only over the version shown
   (`Study.saveCanvas`). **The tree** changes the vault too: move, rename, new note or folder, duplicate, delete (app.json
   `trashOption`: the vault's .trash, else the Mac's Trash, a copy kept first), copy files in; links follow as Obsidian's
   "update internal links" does (`Study.relink`, `movedPath`); every change can be undone, each step only if nothing
   changed it since. Keys: Cmd+O quick switcher, Cmd+W, Cmd+Shift+T, Ctrl+Tab, Cmd+[ and ], Cmd+E edit or read; Cmd+click
   or the middle button opens in a new tab. The topic's folder is still where Sage writes: right-click a folder, "Write …
   notes here". The chat's answer can also carry `save` (video ids to keep in Saved).
9. **Opening.** `obsidian://open?path=<absolute path>` opens a note in Obsidian; without Obsidian the file opens as it is.
10. **As an agent** (2026-11-09: the user's Obsidian plugin Vault Agent, its source in the vault's
    `.obsidian/plugins/vault-agent/`, brought into Sage). `Sources/SageAgent.swift` (Foundation: commands, prompts, the
    stream read, models, memories, a run's files and Undo; plus `SageAgentProcess`, the CLI run through the CLI worker in
    its own process group), `SageAgentDesk.swift` (the desk: runs, media, safety), `SageAgentView.swift` (run card, model
    question and menu, note-bar actions, the chat's Markdown), `SageChatMarkdown.swift` (Foundation: Markdown blocks and
    [[links]]). Checked in `Tests/SageAgentChecks.swift`.
    - **Running.** As Vault Agent: `claude -p --output-format stream-json --verbose --include-partial-messages --model M
      --permission-mode bypassPermissions --effort E` with `--session-id` on a conversation's first run and `--resume`
      after (`Study.Conversation.agent`: id, CLI, vault; another vault or CLI starts afresh; a session the CLI lost is
      dropped and asked again once). Prompt on stdin, cwd the vault root (the CLI reads the vault's CLAUDE.md and the one a
      folder above). Codex: `codex exec [resume id] --json --skip-git-repo-check … -`, given CLAUDE.md on a new thread;
      its messages come whole (no text deltas) and its file changes once made. PATH as Vault Agent's (its yt-dlp folder,
      Homebrew, npm, pip). Text deltas stream into his message; tool calls become steps (Reading, Editing, Running…).
    - **Commands.** `Study.quickCommands`, `quickPrompt` (Vault Agent's commands.ts word for word), `slash`, `expandSlash`:
      /process /summarize /review /categorize /links /rename /fetch /transcribe /memory; words after one are added as
      "Additional instruction". Process, Summarize, Review on the note bar, the rest (and Process & localize: fetch, then
      process) in its ⋯ menu. The brain hands tool work over with the `agent` action (`abilitiesPrompt`).
    - **Model.** No default: the first run asks (`Study.Message.ask`), remembered per CLI; the chat's model menu changes
      it. Claude's list: its help's aliases (always the newest) and the known full ids, plus yours (~/.claude/settings.json)
      and Vault Agent's; Codex's: ~/.codex/models_cache.json. Vault Agent's data.json: six keys only, never its chats.
    - **Memories.** Notes in Vault Agent's memory folder ("System/Vault Agent/Memories"), its header format; the agent is
      told to keep them, and the pinned and relevant ones go into its prompt (`relevantMemories`, Vault Agent's scoring).
      /memory shows the folder in the tree. Vault Agent's "remember: …" shortcut and use counts aren't ported.
    - **Media.** Fetch media and Transcribe call `SageMedia.fetch` / `transcribe` (SageMedia.swift, the media port's);
      their progress lines are the run's steps, their report the message, a failure an ordinary failure line.
    - **Safety.** Never without a vault. Before a run the open note is copied into sage/edited/, and each file the moment
      its Edit or Write call shows in the stream (`SageAgentBackups`, on the reading thread; best effort: it races the CLI's
      tool, and Bash, Codex and files outside the vault are never copied). The vault is read before and after
      (`vaultChanges`): files changed, made and removed are listed as links; `agentUndo` puts back each copied file only if
      it still reads as the agent left it; what had no copy is said.
    - **Markdown.** His replies (agent's and his own) are drawn as Markdown: `chatBlocks` (headings, lists, tasks,
      quotes, code, tables, rules), `chatInline` ([[wikilinks]] as `sage-note:` links that open the note).
11. **Media tools** (2026-11-09, ported from Vault Agent, the user's Obsidian plugin). `SageMedia.fetch`: the note's
   social-video links (YouTube, Facebook, Instagram, TikTok, X/Twitter, Reddit, Vimeo, Twitch, Dailymotion, Streamable;
   frontmatter included) are downloaded with yt-dlp into the attachments folder (app.json `attachmentFolderPath`, read
   as Obsidian reads it, `./` included) as "<note> <n>.mp4"; a link is replaced by `![[file]]` only when a new video
   file is really there (the folder is listed before and after), a failed download's leftovers go and the link stays.
   A login or bot gate retries with a browser's cookies (your default browser first, then Chrome, Brave, Opera, Firefox,
   Safari, only those installed; Chrome's may ask for the Keychain). The first thumbnail becomes `banner:` only when the note has none. Then
   picture links are downloaded under a free name (an error or a web page is refused). `SageMedia.transcribe`: the
   note's embedded video/sound and its links (audio only, into a temp folder deleted after) through WhisperX (small
   model, CPU, int8, Silero VAD), each transcript as "## Transcript" under its source. Tools: yt-dlp from your shell's
   PATH, /opt/homebrew/bin, /usr/local/bin, ~/.local/bin, Vault Agent's `<vault>/.obsidian/plugins/vault-agent/bin`,
   else downloaded once into `~/Library/Application Support/Edit Assist/bin`; ffmpeg the same way; WhisperX from
   Vault Agent's runtime or a python3 that already imports it, else a private one in `Edit Assist/whisperx` (python3 -m venv with a Python 3.10-3.12, else uv,
   downloaded as a release archive, brings Python 3.11). Every step and the tools' useful lines go to `progress` (progress at most every 2 s, "Still working: …" after 20 s of quiet);
   cancelling the task stops the process. Notes change only through `Study.writeNote`, applied to the note as it reads
   when written.

## Rules carried from Edit Assist

- He (the model, through his own actions) writes only new notes, only into a topic's folder, never over a note. As an
  agent (section 10) he edits notes with the CLI's tools, under its safety: copies first, the changes listed, Undo. You edit notes and change the
  vault yourself, in the note view and the tree; those writes follow the vault-editing rule in AGENTS.md.
- Checks use temp folders, never your vault.
- The API key never goes in settings files or git.
- Every on-screen string has its Vietnamese.
