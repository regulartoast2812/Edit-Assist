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
   review (`Study.Saved`, `sage/saved.json`): nothing is written and no vault is needed. **Pick for me** searches,
   asks the brain once which results are real recipe videos worth saving (`Study.pickPrompt`, `Study.pickSchema`;
   at most five, only ids it was shown, `Study.picks`) and saves those, each with its reason. A saved video's recipe
   is written (steps 2–4) only when you press Write recipe or Write all; the vault folder is asked for then.
8. **Notes stage.** Beside the chat, the page has two stages: Research (Find, Saved, Write your own) and Notes (the
   recipes list and the open note). The note is drawn by `Study.page` (`Sources/SageNotes.swift`, Foundation only) as
   Obsidian's reading view: the same classes (`theme-dark`/`theme-light`, `markdown-preview-view markdown-rendered`,
   `metadata-container` for the properties, `callout`, `task-list-item`, `internal-link`, `tag`) and CSS variables, then
   the vault's look from `Study.look(vault:)`: `.obsidian/appearance.json` (`theme` obsidian/moonstone/system,
   `accentColor`, `baseFontSize`, `textFontFamily`, `monospaceFontFamily`), the community theme
   (`.obsidian/themes/<cssTheme>/theme.css`) and enabled snippets (`.obsidian/snippets/<name>.css`). The vault is the
   nearest folder up from the recipes folder holding `.obsidian` (`Study.vault`). `Study.markdown` covers what recipe
   notes use: headings, paragraphs, nested lists, tasks, quotes and callouts, code, tables, bold/italic/strike/highlight,
   links, pictures, YouTube embeds (drawn as the video's picture, opening YouTube), [[wikilinks]] (`sage-note:` links)
   and #tags. On Windows, show the page in WebView2. The chat's answer can also carry `save` (video ids to keep in Saved).
9. **Opening.** `obsidian://open?path=<absolute path>` opens a note in Obsidian; without Obsidian the file opens as it is.

## Rules carried from Edit Assist

- He reads only the folder you chose and writes only there.
- The API key never goes in settings files or git.
- Every on-screen string has its Vietnamese.
