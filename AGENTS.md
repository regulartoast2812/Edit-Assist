# Working on Edit Assist

Edit Assist drives Premiere Pro by reading the screen (OCR + pixels) and sending mouse and keyboard
input. A wrong decision is not a crash: it is a click, double-click or drag in the user's project.
Treat every change to decision logic as a change to what happens in their timeline.

## Before you finish any change

1. `./build.sh` — it runs `./test.sh` first and installs nothing if a check fails or a recorded
   decision replays differently. Do not use `--skip-tests` without saying so to the user. In a chat's worktree,
   `Tools/ship.sh` instead (it runs `./build.sh`; see Parallel chats).
2. Report which files you changed and whether any of it is **automation** (Desktop.swift,
   LiveFeed.swift, Store.swift's run/doTile/doSize/doOpen/navigation code) or **UI only**
   (App.swift, Overlay.swift drawing, Models.swift labels). A UI request does not touch automation;
   if it must, say so before doing it.

## Parallel chats

Several chats can work on this project at once, usually one per helper. Each works in a folder of its own.
- **Start**: from the main folder, `Tools/new-chat.sh <helper>` makes `../Edit Assist-<helper>`, a git worktree on its
  own branch, with the fixtures, probes and MakeFixtures (not in git) linked back. Without them a worktree replays
  almost nothing and still passes. Work, test and commit only in that folder, and only the files you changed (never
  `git add -A` / `commit -a` in the main folder while other chats are running).
- **Finish with `Tools/ship.sh`, not `./build.sh`**: commit your files, then ship from the worktree. It merges main in
  (so the app keeps what the other chats shipped; on a conflict it stops for you to resolve and run it again), runs
  `./build.sh` there (every check and replay, nothing installed if one fails), relaunches the app, and moves main up to
  your branch. Ships and builds take turns (`Tools/build-lock.zsh`). A plain `./build.sh` on a branch installs an app
  without the others' work (it says so). While working, `./test.sh` checks without installing.
- **One chat drives the screen.** The app uses the real mouse, keyboard and Premiere; never run or test it live while
  another chat might, and never build while a highlight run or a Bo restart is in progress.
- **Shared files** (App.swift sidebar and pages, Localization.swift, Models.swift, Store.swift, test.sh's `SOURCES`,
  this file's Helpers paragraph): keep edits there small, expect merge conflicts, and keep both sides when resolving.
  A helper's own files (Kino.swift, BoWatcher.swift, …) belong to its chat.
- **New fixtures made in a worktree** are not in git: run `Tools/new-chat.sh <helper>` again (from the main folder)
  to move them into the main folder and link them back, before the worktree is removed.
- **Releases** (`release.sh`) only from main, by one chat, when the user asks.

## Safeguards and how to extend them

- `Tests/Checks.swift`: unit checks on synthetic images and measured values.
- `Tests/Replay.swift`: replays recorded decisions through today's code — `Tests/Fixtures`
  (real screens, each expectation checked by eye; built by `Tests/MakeFixtures.swift`) and every
  recording the user kept (Diagnostics → Record the next run → Keep last recording as a test,
  stored in `~/Library/Application Support/Edit Assist/recordings/kept`).
- A run that fails on a real screen: add that screen as a fixture or keep its recording, so the same
  failure cannot come back unnoticed.
- New decision points must be recorded (`recordDecision(Snapshot(...))`) and replayed (a case in
  `Replay.check`).

## Reading the UI

`Sources/PanelReader.swift` reads panels as named controls (`Desktop.textSection`: font, weight, the
seven type buttons, Font Size and its slider, the nine paragraph buttons with their on/off state,
tracking, leading). Reading only; a function that acts on a control looks it up by name there. Add new
panels the same way, with a `textSection`-style replay case and a fixture checked by eye.

**Faces and bodies**: `Desktop.people` (`Sources/PeopleReader.swift`) finds faces (box, tilt, turn,
outlines) and people (outline from the person mask, body joints when the pose is visible) with Apple's
Vision, about 20-30 ms a frame, read on every stream frame. It reads inside `Desktop.programPicture`
(the Program Monitor's picture, found from its tab, the timecode under it and the pixels) when found,
which gives Vision about three times the detail of the whole window. `PeopleFollower` numbers faces across frames,
re-reads a head the pose shows but the face model missed, and holds a lost face for 15 frames (Vision's
object tracker, started only once a face is lost), marked "followed". Where Vision's skeleton has fewer than 15 joints (a
close-up), `WholeBodyPose` (DWPose RTMPose-m, Apache-2.0, `Resources/Models`, see its NOTICE.md) adds
the joints it is confident about (0.5, body joints away from the picture's edge) and both hands, on
the GPU: on the Neural Engine its float16 scores are wrong for some keypoints. Overlay only
(Detection settings → Faces and bodies); no run decides anything from it yet. A function that starts
acting on it adds a replay case and fixtures like any other decision.

**Which panels are on screen**: `Desktop.panelTabs` finds Premiere's panels by their tab names (the
Window menu's list in `premierePanels`, plus "Program: …", "Source: …", "Project: …" forms). A name
counts as a tab only on a row of tabs or with the ≡ menu icon, so "Text" inside a panel is not one.

**Panels as rectangles**: `Desktop.panels(in:image:)` cuts the window along Premiere's divider lines (thin,
black, grey on both sides; black video and list boxes are content, not lines) into the panel rectangles,
then reads each one's tab row and the tab in front (underlined). Drawn on the overlay in light blue.
**Where the Properties panel is**: `propertiesArea(in:image:)` is the panel rectangle holding its tab, below
the tab row (falling back to the divider lines around the tab), so it holds wherever the tab sits in its
group and however the panels are sized. Without the image it falls back to "from the tab to the window's edges", which once left
the whole panel out when Properties was the sixth tab (fixture 40).

**Know the panel, not a position.** `Desktop.propertiesState` says what the Properties panel shows
(nothing selected, caption, graphic text, style browser, unknown) from its text and the four-square
icon's shape right under its Track Style header. After a click that should change the panel, read
its state, and click again (at most three times) only if it still shows the old panel — a busy machine
can be slow or miss a click. Never re-click a remembered spot, and never click a shape found by
searching the whole panel: once the browser is open a style tile can look like the four-square, and
clicking it applies the wrong style to the selected text (this happened).

**Reading the panel alone**: the quick checks after clicking the caption, the four-square and Back read only
the Properties panel (`Store.readProperties`, `Desktop.propertiesReadRegion`): ~95 ms against ~320 ms for the
whole window. Only positive answers are taken from it ("selected", "the browser is open", "back on the outer
panel"); "not selected" and an unclear panel are read again from the whole window. Replay decides every
Properties fixture a second time from the panel read alone, so a region that loses text fails the build.

**Without font**, learnt from your pick: a left-click on your tile is the normal style; a right-click followed by
"Apply Style without Font" (the item under your click, read from the screen) is saved with the style
(`RememberedStyle.withoutFont`), and every phrase then gets it that way: the bot right-clicks the tile and clicks
the item by its name (`Desktop.readScreen`, `withoutFontLine`: a word near "font" and within a third of the
item's letters, since "l Appty Style wlthoth font" was read once, 2026-11-02), right-clicking up to three times
(0.6, 1.0, 1.5 s for the menu) before stopping. Any other item, a click
outside or Escape is not learnt and the pick starts again. No raw input is replayed: a build that replayed it
repeated a misread item ("wlthout") and a misclick on every phrase (2026-10-26). No switch for it in the window
(you asked for none). Premiere's style menu is not a window the window list finds; `clickMenu` clicks only where
something covers Premiere.

**Reading only the caption areas**: caption steps (the scan after each step, the drag check, a re-read of a
partial match) read afresh only the Program Monitor's picture with its time display and the timeline's time and
ruler (`Desktop.captionRegions`, `captureCaptions`), about half the time of the whole window; everything else
comes from the last whole-window reading (`Store.readCaptions`), redone every ten steps and whenever the window
changed size or the picture or time is not found where expected. Replay decides every caption screen a second
time that way and compares the playhead time. Input is sent without a screenshot first (the window list gives
its place). The pause before pressing a style tile starts at 0.15 s and goes to 0.3 s for the run once a press
is ignored.

**Graphics** (Essential Graphics text, or a caption upgraded to one) have no Track Style. Selected as a
whole, Properties shows the layer list and Transform (`graphicLayers`); with its text being edited, the
text layer (`graphic`): Text, Appearance, Align and Transform, then **Linked style** far below, whose row
holds the four-square. The routine scrolls the panel down to Linked style to open the browser, and back up
to Font Size on the next phrase; it does not click a layer row (that could drop the word selection).
All of this belongs to **Highlight graphics** (`runOCR(graphics: true)`); every graphics rule in the
routine is behind that flag, so **Highlight phrases (captions) decides exactly as before**: a graphic is
not a selected caption (its fallback then selects the caption clip under the playhead), and it only clicks
the four-square under Track Style. Fixtures 33-37 (graphics), 38-39 (captions must ignore graphics).

**Reading the script in order**: each caption read is placed in the script (`ScriptMap.locate`: most of its words
lined up, nearest going forward from the last caption), and only the bold words of that part, not yet styled,
are selected, by their place in the caption (`Store.placedVisible`). A phrase that runs past the caption's end is
styled there and finished on the next clip. Matching phrases anywhere on screen styled a repeated word in the
wrong place ("Fabric" inside "Soft fabric", "wire" twice on one word, 2026-10-28); it remains only as the
fallback for a caption that cannot be placed, and then only for phrases near the last place.

**Script tabs**: a project can hold several scripts, one tab each on the project page. The open tab is the project's
`script` and progress fields themselves, so runs, progress and everything that reads the script are unchanged; the other
tabs wait in `otherScripts` with their own progress (`Project.scriptTabs`, `openScript`, `addScript`, `removeScript`).
Tabs cannot change during a run (a paused run still counts). Removing a script with text backs up projects.json first.

**Helpers** (sidebar, under Functions; never part of a highlight run; their pages show the run bar only while a function runs): **Amir** lists the files of a folder you choose
(`AmirWatcher`) and moves for a few seconds when one arrives; nothing is renamed or moved yet, and when it is, only after
you agree to each one. **Tala** (voice-overs with ElevenLabs, music that suits them) connects
to ElevenLabs with your API key (`TalaVoice`, `ElevenLabs` in `Sources/ElevenLabs.swift`; the key lives in the Keychain,
never in UserDefaults or projects.json) and, when her page opens, reads the plan's credits, My Voices (samples play from
ElevenLabs, free) and the text-to-speech models. A voice-over is one MP3 per script, made from **Tala's own copy** of
the script (`TalaCopy`, one file per script in Application Support/Edit Assist/tala): your ElevenLabs audio tags
(`[excited]`, `[whispers]`) go there, never in the script, so highlight runs never see a tag. No voice sliders: the tags
direct the delivery (you asked for none). Eleven v4 by default, since only v3 and v4 follow tags. A script longer than
the model takes is sent in parts cut between lines or sentences, each with the text around it, and joined. Saved in a
folder picked once, never over an earlier file. Credits are spent only when you press Make. Music waits for Don.
Her page is laid out like ElevenLabs' Text to Speech page, in columns (you asked for it): the output folder and its
sound files (play, drag into Premiere) on the left, the copy in the middle, voice (searchable), model and account on
the right; under 980 points wide the files share the right column as a tab. **Bo**
(`BoWatcher`) checks Google Drive for Desktop every minute and restarts it by himself on these signs: Google Drive not
running; a drive that does not answer a listing within 15 s for three minutes (at most once every half hour); Finder
not taking Drive's changes for 30 minutes ("Slow working set change acknowledgment" with no "acknowledged after";
he restarts macOS's fileproviderd too); and Drive stuck half-quit for 5 minutes ("StopAllAccounts … initiated" only: "Quit initiated" is also written for a quit
you cancel). Bo reads Drive's log incrementally, new lines only, in one pass (`BoWatcher.DriveLog`): reading a long
running 46 MB log whole each minute took 7–23 s. Bo also shows this Mac's disk (free space each minute; the biggest folders every three hours
by du in a separate process: Offline Projects projects, Documents, Downloads, Premiere's media cache, drag copies in
~/Library/Caches/com.apple.SwiftUI.Drag-*; never inside Google Drive) and each account's Drive space as Drive's settings
last showed it ("quota_details" in its log). He recommends archiving projects idle for 30 days; he deletes nothing. A restart that cannot quit Drive ends
it with SIGKILL. A drive that answers can still be stale: on 2026-11-03 Drive had been half-quit for hours. Every 15 minutes Bo also
compares the top of each drive in Drive's database (read only; immutable when Drive keeps it locked) with what Finder
lists; a gap of 3+ items and a tenth of the drive that lasts 15 minutes opens a dialog asking you to disconnect and
reconnect that account (Google's rebuild). For three hours after an account is connected, or after you choose to
reconnect, Bo leaves Drive alone, except for a Drive stuck half-quit, which he ends whatever the hold (Drive
restarts itself after a sign-out, an update or a settings change, and can freeze doing it). He also restarts nothing within 20 minutes of Drive's settings being on screen (he once
force-quit Drive during "Preparing to disconnect account"), and tries the File Provider restart once in three hours;
stalling again after it, he asks for the reconnect instead. A disconnect showing "Preparing to disconnect account" with no change
in Drive's windows for 10 minutes brings a dialog whose button restarts Drive so you can retry. Bo does not rebuild an
account by moving Drive's folder aside: Finder's copy lives in ~/Library/Application Support/FileProvider, which only
Drive's own disconnect removes. Errors in
Drive's log are shown, never acted on: it holds hundreds of harmless ones. Bo also measures what Drive keeps in Application
Support (each account's cache, old logs, lost_and_found, free space; never the drives themselves) every 15 minutes, and
sorts the last day of log errors into kinds (`BoWatcher.kind(of:)`; Drive's own telemetry and settings fetches are
noise). He only recommends: a cache is cleared Google's way (Disconnect account, sign in again), never by deleting
Drive's folders, where files not yet uploaded live. Folders and drives are read off the main
thread: macOS asks before an app reads Downloads, and the app must not freeze while it asks. **Don**, the ads expert, reads the open script when you ask
(`DonReader`, `Sources/Studio.swift`) into a brief: product, vibe, voice, music, graphic style, the CTA words and look,
and the lines the script gives no media for, which need AI video. The script can come from the project's **script sheet** (`DonSheet`, `SheetsConnector`; you asked for it 2026-11-05): a Google Sheets link pasted on Don's page, read with the Claude CLI's Google Sheets connector (the one on your Claude account; `get_spreadsheet` and `get_values` only, writes disallowed; Codex has no Google connector, so a sheet is always read with Claude). The cells are taken from the connector's own result in the CLI's output, never retyped by the model. The link's tab (gid) is read; headers are matched in English or Vietnamese (Cảnh, Text/Voiceover, Khoảng cut từ source, Source); a filled Version cell starts a version, and versions with no words (finished videos) are left out. Each script reads from the version named like its tab, or one you pick, or the pasted script; a line's Source tells Don it has media, so only lines with none need AI video. Kept in `don/sheet-<project>.json`. **Pix** takes his jobs from that brief (`PixDesk`):
**only the CTA is queued by itself**; a product schematic (for lines needing AI video) and anything you ask for in his
chat are proposals you queue with a press, since GPT Image costs credit. The CTA is three 1080×1920 variants in one
3560×1920 SVG with real text, as your earlier CTA files are, designed by the helper brain and opened in Illustrator;
product pictures go in as `PICTUREn` placeholders Pix swaps for the picture. Schematics and pictures come from GPT Image
(`OpenAIImages`; the OpenAI key lives in the Keychain; the newest full gpt-image model the key lists). Made files go to
Downloads, named after the project and script, never over an earlier one. Briefs and Pix's jobs and chat are kept per
script (each script's chat with a history: New chat keeps the one before in `PixBoard.past`, reopened or deleted from the list; his chat is a column on the side of his page, as Basil's is) in `don/` and `pix/` beside projects.json, never in it. Don and Pix think with `HelperBrain`: the Claude CLI by
default, Codex as the backup you pick in Pix's chat, one call with no tools and a strict JSON schema each; the highlight
runs keep their own Assistant CLI. A job cut off by quitting is marked failed, never made again by itself. **Kino** (AI videos with Kling and Higgsfield, from your media and prompts; `KinoDesk`, `Sources/KinoDesk.swift`)
works on a batch per project that starts empty: he reads only the files you drop or add, never a folder by himself. Files
named by shot code go into their shot as they come in (K1, K1.1 and K1.2 into shot K1's one prompt, each under its own tag,
@K1.1); any file can be dragged into any shot, and one picture can be in many shots under a tag of each (K2.3). Each file
has a role (look, start or end frame, camera and motion, video to edit, sound, left out), and the roles decide the model's
endpoint, so an edit is never sent as a reference by chance; a video follows by default, its people and talking left out;
a file has no role until you give one (no start frame is made for you, 2026-11-06): with none it goes as a
reference, and only a given role shows on its picture. The shots are cards in one list,
as the Forge shows its jobs, with the shot's files and one + box (the boxes for other roles show while files are dragged
over it). Files dropped on a shot's files go into it; dropped anywhere else in the list they make a new shot, and while
files are dragged each shot's files are outlined to show it. The prompt names a file by typing @ (a list of the shot's files);
it shows each as a pill with the file's name in its role's colour and keeps it as its @tag. Typing / gives a role: /start then a file
makes it the start frame (/end, /look, /edit, /motion, /sound, /out the same), shown as one pill ("Start · K2") and kept
as "/start @K2"; deleting it takes the role away, a role picked on the file rewrites it, and commands are never sent. The media sorts by name, shot or newest. The outputs sit beside the shots, the newest take first, each played in
place on a press (it counts as watched) and dragged into Premiere or onto a shot; until Kino sends, videos dropped there
are the takes, with the shot their name has (K3.1 O1 with K3).
The form follows the model (Kling O3, Seedance 2.5, Motion Control through Higgsfield; Kling 4.0 direct), and each shot
shows what Kino would send and what stops it, before anything is spent. Batches are kept in `kino/<project>.json` beside
projects.json; the Kling and Higgsfield keys live in the Keychain. Nothing is sent yet: sending comes with the keys.
How both services work is mapped in `docs/kino/README.md`, sourced, as of 2026-11-04; the team's KlingDom Forge in `forge.md`.
**Penny** (the numbers of the products you run, from the company's Grafana) signs in to grafana.selless.com (Grafana
11.2; Google sign-in only, its login form is off) in a private web view and keeps only the `grafana_session` cookie, in
the Keychain (`Grafana`, `PennyDesk` in `Sources/Grafana.swift`). Grafana rotates that session every few minutes: a 401
asks `api/user/auth-tokens/rotate` for the new one (one renewal shared by every request refused at once) before
counting you signed out. He reads the dashboards you can see and saves the ones you use (Retail Operations V3.5 first, the one you read: it
gathers every team's sales and ads; then Facebook Ads Manager Campaign V1.0, PMKT's and the Facebook breakdown; and your starred ones) as
Grafana sent them in penny/ beside projects.json, never in git. His page draws the one you pick as Grafana draws it
(`PennyBoard`, the `Grafana` dashboard model in `Sources/GrafanaBoard.swift`; views in `Sources/PennyPanels.swift`): its
filters, its rows and panels on the 24-column grid, each panel's own queries run through `/api/ds/query` with the
filters written in as Grafana writes them for SQL (quoted, All as every value or the all-value; `$__timeFilter` and the
other macros left to Grafana), then the panel's transformations (calculateField, organize, concatenate) and its units,
decimals, thresholds and cell colours. A closed row reads its panels when opened. Your filters and time are kept per
dashboard; what each panel last answered (columns, rows, a stat's values or the error) is written to penny/answers/.
His page has two tabs: **Products**, his own dashboard, and **Grafana**, the dashboard drawn as above. Products reads his own copy of the Facebook ads' numbers (`PennyLedger`, `Ledger` in `Sources/PennyLedger.swift`; views in `Sources/PennyProducts.swift`). While you are signed in, from launch and every half hour, he copies each ad's numbers hour by hour from ad_stats_ad on cms-replica2, the table Facebook Ads Manager Campaign V1.0 sums up. These are his only queries of his own: two read-only SELECTs a day, and a third, sent apart so a failure leaves the ads' copy alone, for each product's day as the company's CBH counts it (`Ledger.Margin`: Retail Operations V3.5's product table with no filters, and `cbh_tax` asked again with no ad spend, so what a product keeps of each revenue dollar before ads and what an ad dollar costs it are measured, not assumed), kept in summary.json. The copy is kept by product (pbase_code) in penny/history/<product>/<day>.json.gz (gzipped: a tenth of the size), with each day's totals in summary.json. Days are Alaska time, the company's. He covers the last 30 days, newest first, and copies a day again until it has been over for 12 hours. An empty answer for a day he already has never replaces it, because Grafana keeps little history. The Data section at the top of Products says whether the copy is up to date (when he last copied and copies next, the last hour Grafana has today) and marks each day in the range with a green check when it is final or was copied in the last hour, else behind or not copied. From that CBH each product gets its own breakeven ROAS (`Ledger.Profit`; you said CBH is the real profit, 2026-11-06), the usual 1.8× until he has it, and profitable from CBH 5% (2.0× when breakeven is 1.8×). The hours are read as a media buyer does (`Ledger.HourRead`, the rules of the Campaign Breakdown dashboard in ~/Documents/Campaign Breakdown): each hour's spend a day, ROAS, its bad and good days (10th and 90th percentile of its days' ROAS, counting a day's hour from $20, or $3 on a day under $300), CBH and a verdict (reliable win, high ceiling, thin profit, below breakeven, costly waste over $50 a day, dead under 1×, too few days under 3), and where the budget went (hours below breakeven, thin, profitable: share of spend, of revenue, CBH). From the copy he shows each product's totals, his written read (against the days before, the creatives that sell and the ones that only spend, the best and weakest hours), the product by day and by hour, each creative's orders hour by hour, and its creatives and campaigns. A creative is the ad's name, so the same creative in several campaigns is one line. He only reads, never changes anything in Grafana. **Basil** (recipes; personal, not Crossian's: staged here for the user's Windows app, which will take him; `Kitchen` in `Sources/BasilKitchen.swift` is Foundation only and holds every rule, `BasilDesk` and `Basil.swift` are the Mac around it; port notes in `docs/basil/README.md`) finds recipe videos with YouTube's Data API on your key (Keychain; about 100 searches a day free; no scraping of youtube.com), reads the schema.org Recipe of the page a video links to, has the helper brain write the recipe without inventing amounts, and saves it as a Markdown note with a YAML header in the recipes folder you chose in your Obsidian vault, never over a note already there. He tracks each note's `status` (to try, made, favourite), changing only that line. He reads and writes only that folder. His page is one dashboard, no tabs (you asked for it, 2026-11-06): a one-line header with your counts (each filters your recipes), the vault and the YouTube key; then the chat on the left and, beside it, two stages: **Research** (Find: YouTube, yours or what he searched from the chat; Saved; Write your own) and **Notes** (your recipes as a list, the open one drawn as Obsidian's reading view in a web view: `Kitchen.page`/`Kitchen.markdown` in `Sources/BasilNotes.swift`, Foundation only, with your vault's look read from .obsidian: appearance.json's light or dark, accent, font size and fonts, your community theme's CSS and enabled snippets, over Obsidian's own CSS variables and classes; [[wikilinks]] open the recipe there, web links in the browser). A recipe just written, and any note named in Saved or the chat, opens in Notes. The chat can also save videos to Saved when you ask (`save` in its answer). Narrower windows stack the columns. The chat answers with the helper brain in up to three rounds: a round can ask for a YouTube search or notes to read by title (`Kitchen.chatPrompt`, `Kitchen.Reply`), and the last answers with what was found, showing the videos it picks as cards. The chat has a history, as Claude Code lists its sessions: each conversation titled by your first message, with how long ago, searchable, New chat keeping the old one (`Kitchen.Conversation`, all kept in basil/chats.json beside projects.json; the single basil/chat.json from before becomes the first conversation). Search and chat work before a folder is chosen; it is asked for when a recipe is saved. Searches add "recipe" to your words unless they already ask for cooking (`Kitchen.recipeSearch`). Videos saved (Save, or dragged onto the save area on the right) are kept in the app to review (`Kitchen.Saved`, basil/saved.json), not written; **Pick for me** searches and has the brain pick at most five real recipe videos from the results (`Kitchen.pickPrompt`; only ids it was shown) into that list, each with why. A saved video's recipe is written into the vault only when you press Write recipe or Write all, and only then is the vault folder asked for (you asked for it, 2026-11-06). Each helper has a colour, their body's, for their sidebar button and page.
Characters are pixel art
(`PixelSprite`, `AnimatedSprite`), never photos of real people, and not built on stereotypes of any nationality.

## Invariants — each one was learned from a real failure

- **Never act outside caption text.** Timeline clip labels repeat caption words. Caption candidates
  must be well above interface text size (1.8 times; 1.4 inside the Program Monitor's picture, where there is no
  interface text and a caption without tall or hanging letters fell under 1.8), at least 65% of a caption height already seen, and, once
  a caption has been styled, inside the area captions appear in (the Program Monitor). There is no
  fallback to "the largest text" — that once dragged a clip over its neighbour and deleted it.
- **Never drag without the drag check.** Re-read the screen and drag only if the start point is in
  caption-sized text. A drag over a timeline clip moves it.
- **Step with Shift+Down (any track), not Down.** Down stops only at edit points of the targeted tracks (the video
  cuts); where they do not line up with the captions it skipped captions (2026-10-28). Down only if Shift+Down
  does not move.
- **Edit points are never caption clips, so check every step against the script.** Shift+Down stops only at video
  and audio cuts; a caption with no cut inside it is stepped over (2026-10-28, checked against the project file:
  "heavy lifting from below" 7.90–9.37 s and "push-up effect" 10.70–11.57 s never shown). When the caption landed
  on is later in the script than the last one by bold words not yet styled, step back five frames at a time
  (Shift+Left) and style each caption met, until none of them is left before it or the last caption's time is
  reached; each passed-over word is looked for once (`walkedPast`).
- **A phrase split across clips: step to the next edit point before matching the rest.** The rest
  cannot be on the screen just styled.
- **Selected = the Properties panel shows text controls** (C1: Subtitle, Track Style, Font Size, a
  Text section, or the style browser), not just the caption layout.
- **Style tiles: the position decides, the image confirms.** Presets come in near twins; the image is
  taken under the pointer's hover tint and can score a twin closer than the picked tile. At the
  remembered row and column, accept same colour and shape under 30. Colour is a hard gate.
- **The row counter is shared** by the routine, the teach step and the live overlay. A change for one
  must be checked in the others. A count being followed restarts only when the routine scrolls to the top
  or the browser reopens (two looks where text and pixels agree the list is gone, then it reappears). The
  top measured on a frame (scrollbar thumb level with the first full row, nothing above) only recovers a
  count that is lost: on a short list the thumb barely moves and stays level with row 1, and that measure
  replaced correct counts four times on 2026-10-13 and sent clicks to the wrong row. Panels are
  resizable: nothing may depend on geometry remembered from an earlier layout; a mid-session layout
  change marks the count lost.
- **One kind of image per tracker sequence.** Screenshots and stream frames of the same screen differ
  (about 8 levels); the tracker treats a change of kind as a new reference.
- **Waits are tuned to Premiere's redraw.** Shortening one can make a capture land mid-redraw and
  expose another bug. Change waits deliberately, one at a time, and say which.
- Script wording, timings and unmarked text are never changed. Only the phrase range is styled.
