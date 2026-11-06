# Basil, the recipe helper

Basil is personal, not Crossian's: he finds recipes on YouTube and keeps them in an Obsidian vault. He is staged in
Edit Assist (macOS) and meant to move to the Windows app, which has the same helpers and functions. Nothing of his
touches projects, Premiere, Grafana or any Crossian account.

## Files

| File | What it is | Port |
|---|---|---|
| `Sources/BasilKitchen.swift` | `Kitchen`: every rule and format. Foundation only. | Take as it is (Swift), or translate one function at a time; `Tests/Checks.swift` ("Basil, the recipe helper") lists what each must do. |
| `Sources/BasilDesk.swift` | `BasilDesk`: state, network calls, the key and the folder. | Rewrite: Keychain → Windows Credential Manager; `NSOpenPanel` → a folder picker; `UserDefaults` → the app's settings. |
| `Sources/Basil.swift` | His pixel icon and page (SwiftUI). | Rewrite in the Windows app's UI; the sprite rows and colours copy over as they are. |

## How he works

1. **Finding videos.** YouTube Data API v3 with your own API key (Google Cloud → enable YouTube Data API v3 →
   Credentials → API key). `search?part=snippet&type=video&maxResults=24&q=…` (100 units), then
   `videos?part=snippet,contentDetails,statistics&id=…` (1 unit) for length, views and the full description. The free
   quota is 10,000 units a day, so about 100 searches; it resets at midnight Pacific time. A key is kept only after
   YouTube takes it (one `videos` call). No scraping of youtube.com and no captions: those need YouTube's own apps.
2. **Reading the recipe.** The description's links, leaving out social and shop sites (`Kitchen.notRecipes`), up to
   four, in order. The first page that publishes a schema.org `Recipe` in JSON-LD (most recipe sites do, for search
   engines) is the exact source. The page is fetched plainly, without imitating a browser; a page that refuses is skipped.
3. **Writing it.** One call to the helper brain (the Claude CLI; Codex as the backup) with no tools and the strict
   schema `Kitchen.schema`: title, servings, prep, cook, total, cuisine, course, tags, ingredients, steps, notes. The
   prompt (`Kitchen.rules`) forbids inventing amounts, times or steps; anything missing is said in a note. Your own
   words (the Write tab) go through the same schema, keeping your amounts.
4. **The note.** `Kitchen.note`: a YAML header Obsidian shows as properties (`title`, `status`, `source`, `channel`,
   `page`, `servings`, `prep`, `cook`, `total`, `cuisine`, `course`, `tags` with `recipe` first, `added`), the video
   embedded (`![](youtube link)`), then Ingredients, Steps (numbered) and Notes. The file is named after the dish with
   characters Windows refuses taken out, and never written over an existing note (`Kitchen.fileName`: "Adobo 2.md").
5. **Tracking.** The recipes folder you choose (and the folders in it, `.obsidian` and hidden ones left out) is read
   into `Kitchen.Entry` rows. `status` is `to try`, `made` or `favourite`; changing it rewrites only that header line
   (`Kitchen.setting`). A video whose link is already a note's `source` shows "In your vault".
6. **Chat.** The first tab. Each message is answered in up to three brain calls with `Kitchen.chatSchema`
   (`reply`, `youtube`, `notes`, `show`): a call can ask for a YouTube search (12 videos) or notes to read by title
   (`Kitchen.named`, at most 5), which the desk does and hands back in the next call (`Kitchen.chatPrompt`); the last
   call must answer. Videos it lists in `show` appear with the answer as cards (Write recipe, watch). The prompt carries
   the notes list (title, status, cuisine, tags), the last 20 messages and the videos shown last. Saved in
   `basil/chat.json`. Search and chat need no folder; the folder is asked for when a recipe is first saved.
7. **Opening.** `obsidian://open?path=<absolute path>` opens a note in Obsidian; without Obsidian the file opens as it is.

## Rules carried from Edit Assist

- He reads only the folder you chose and writes only there.
- The API key never goes in settings files or git.
- Every on-screen string has its Vietnamese.
