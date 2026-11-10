# Working on Edit Assist

Edit Assist drives Premiere Pro by reading the screen (OCR + pixels) and sending mouse and keyboard
input. A wrong decision is not a crash: it is a click, double-click or drag in the user's project.
Treat every change to decision logic as a change to what happens in their timeline.

## Before you finish any change

1. `./build.sh` — it runs `./test.sh` first and installs nothing if a check fails or a recorded
   decision replays differently. Do not use `--skip-tests` without saying so to the user. In a chat's worktree,
   `Tools/ship.sh` instead (it runs `./build.sh`; see Parallel chats).
   Builds are incremental (`Tools/incremental.zsh`, 2026-11-09): each product keeps its objects and dependency records in
   `.build/inc/<name>/`, so only changed files (and files using something whose shape changed) recompile, on every core;
   the checks compile and run while the app compiles, and are compiled with -O (the image checks took a minute unoptimized).
   A one-file change builds, checks and installs in about 15 s; a first build or a flag change, about 2 min. Never edit
   Sources/ while a build runs (the compiler stops: "modified during the build").
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
over it). Files dropped on a shot's files (only the files and their boxes, outlined while files are dragged) go into it;
between two shots, a + opens and they make a variant of the shot above (K2.1 after K2, with its settings); anywhere
else in the list, the prompt included, they make a new shot. The prompt names a file by typing @ (a list of the shot's files);
it shows each as a pill with the file's name in its role's colour and keeps it as its @tag. Typing / gives a role: /start then a file
makes it the start frame (/end, /look, /edit, /motion, /sound, /out the same; /mid 2s @K3, a Kling 4.0 keyframe at
2 s, its time written into the prompt sent), shown as one pill ("Start · K2") and kept
as "/start @K2"; a role lives only there (2026-11-06): one picked on the file or by dropping on a role's box is written as its command,
No role or deleting the pill takes it away, roles kept beside the prompt before are not read, and commands are never sent. The media sorts by name, shot or newest. A file's × removes it from Kino, saying first which shots use it (Remove or Cancel); files are picked as in Finder (click, Cmd+click, Shift+click, Cmd+A; `KinoPick`) to drag, put in a shot or remove together (Delete removes, Esc unpicks), dragged as Finder drags (`KinoFileDrag`, AppKit: SwiftUI's drag carries one file); the rest slide into a removed file's place, at once with Reduce Motion (built first in Creative Assist, 2026-11-08). The outputs sit beside the shots, the newest take first, each played in
place on a press (it counts as watched) and dragged into Premiere or onto a shot; until Kino sends, videos dropped there
are the takes, with the shot their name has (K3.1 O1 with K3).
The form follows the model (Kling O3, Seedance 2.5, Motion Control through Higgsfield; Kling 4.0 direct), and each shot
shows what Kino would send and what stops it, before anything is spent. Batches are kept in `kino/<project>.json` beside
projects.json; the Kling and Higgsfield keys live in the Keychain. Nothing is sent yet: sending comes with the keys.
How both services work is mapped in `docs/kino/README.md`, sourced, as of 2026-11-04; the team's KlingDom Forge in `forge.md`. How to prompt in Kino (@, /, what each model takes, the services' prompt
advice), for the team, is `prompting.md`, opened from How to prompt on his page; keep it in step with the commands.
**Penny** (the numbers of the products you run, from the company's Grafana) signs in to grafana.selless.com (Grafana
11.2; Google sign-in only, its login form is off) and keeps only the `grafana_session` cookie, in the Keychain (`Grafana`,
`PennyDesk` in `Sources/Grafana.swift`). Grafana rotates that session every few minutes: a 401 asks
`api/user/auth-tokens/rotate` for the new one (one renewal shared by every request refused at once). The sign-in window
uses a web data store of its own (`GrafanaWeb`, WKWebsiteDataStore(forIdentifier:), macOS 14; 2026-11-08, from the Windows
app: you were asked to sign in too often) that keeps only Google's sign-in: Grafana's cookies are deleted from it as soon
as the session is taken, so it never holds or renews Penny's session. When Grafana won't renew the session, or refuses the renewed one at once (2026-11-10, after the Mac slept), Penny signs in
again out of sight with it (`GrafanaWeb.silently`: a see-through window off every screen, 25 s, never focused; one at a
time), and once when his page opens signed out; only when Google wants you is he signed out. He never sees or keeps the
password and never reads your browsers. **Sign out** removes the store; a session ending does not. penny/sign-ins.log says
when and why sessions ended (`Grafana.note`), never the session. He reads the dashboards you can see and saves the ones you use (Retail Operations V3.5 first, the one you read: it
gathers every team's sales and ads; then Facebook Ads Manager Campaign V1.0, PMKT's and the Facebook breakdown; and your starred ones) as
Grafana sent them in penny/ beside projects.json, never in git. His page draws the one you pick as Grafana draws it
(`PennyBoard`, the `Grafana` dashboard model in `Sources/GrafanaBoard.swift`; views in `Sources/PennyPanels.swift`): its
filters, its rows and panels on the 24-column grid, each panel's own queries run through `/api/ds/query` with the
filters written in as Grafana writes them for SQL (quoted, All as every value or the all-value; `$__timeFilter` and the
other macros left to Grafana), then the panel's transformations (calculateField, organize, concatenate) and its units,
decimals, thresholds and cell colours. A closed row reads its panels when opened. Your filters and time are kept per
dashboard; what each panel last answered (columns, rows, a stat's values or the error) is written to penny/answers/.
His page has two tabs: **Products**, his own dashboard, and **Grafana**, the dashboard drawn as above. Products reads his own copy of the Facebook ads' numbers (`PennyLedger`, `Ledger` in `Sources/PennyLedger.swift`; views in `Sources/PennyProducts.swift`). While you are signed in, from launch and every half hour, he copies each ad's numbers hour by hour from ad_stats_ad on cms-replica2, the table Facebook Ads Manager Campaign V1.0 sums up. These are his only queries of his own: two read-only SELECTs a day, and a third, sent apart so a failure leaves the ads' copy alone, for each product's day as the company's CBH counts it (`Ledger.Margin`: Retail Operations V3.5's product table with no filters, and `cbh_tax` asked again with no ad spend, so what a product keeps of each revenue dollar before ads and what an ad dollar costs it are measured, not assumed), kept in summary.json. The copy is kept by product (pbase_code) in penny/history/<product>/<day>.json.gz (gzipped: a tenth of the size), with each day's totals in summary.json. Days are Alaska time, the company's. He covers the last 30 days, newest first, and copies a day again until it has been over for 12 hours. An empty answer for a day he already has never replaces it, because Grafana keeps little history. When Grafana's database is busy (it is a replica, and cancels a query that conflicts with catching up: "conflict with recovery"), or a gateway or the network hiccups (`Ledger.passing`), he asks again after 10 and 30 seconds; a day that still fails doesn't stop the other days or the CBH, the Data section says so plainly, and he tries again in 5 minutes instead of 30 (2026-11-09). The Data section at the top of Products shows what the copy takes on disk (`PennyLedger.stored`, measured off the main thread at launch and after each copy) and a Show in Finder button that selects penny/history, to zip, copy or share it (2026-11-10, you asked); it says whether the copy is up to date (when he last copied and copies next, the last hour Grafana has today) and marks each day in the range with a green check when it is final or was copied in the last hour, else behind or not copied. From that CBH each product gets its own breakeven ROAS (`Ledger.Profit`; you said CBH is the real profit, 2026-11-06), the usual 1.8× until he has it, and profitable from CBH 5% (2.0× when breakeven is 1.8×). The hours are read as a media buyer does (`Ledger.HourRead`, the rules of the Campaign Breakdown dashboard in ~/Documents/Campaign Breakdown): each hour's spend a day, ROAS, its bad and good stretch (2026-11-09, instead of the dashboard's single days, which made every bad day 0: its days cut into runs long enough for about 3 orders at the hour's rate, at most 7 days, the 10th and 90th percentile of their ROAS at the nearest place, with 3 runs or more; a profitable hour with fewer is too few to judge), CBH and a verdict (reliable win, high ceiling, thin profit, below breakeven, costly waste over $50 a day, dead under 1×, too few days under 3), and where the budget went (hours below breakeven, thin, profitable: share of spend, of revenue, CBH). The hours (Hours of the day, Hour by hour, a day opened hour by hour's column shading, and the read's put-more-in and cut-back) are judged over every day copied for the product on which its ads ran (`Ledger.ran`: in 12 hours or $300 spent; days the ads trickled or were off read as 0× hours), against those days' own breakeven, not the range (`PennyAnalysis.history`, `hourProfit`; 2026-11-09: on Today each hour had one day and every verdict was too few days); the figures, the days, the read's totals and where the range's budget went stay on the range. Hour by hour also shows each hour over the last 7 of those days (`recentHours`, ▲▼ a tenth off its whole ROAS), its orders, CPM, CTR and CR (2026-11-09, you asked; to review), and takes the page's whole width, scrolling sideways when narrower than its columns (`PennyGrid.minWidth`). The product page draws these (`Sources/PennyCharts.swift`, numbers from `Ledger.dayReads`, `weekReads`, `bands`), redrawn 2026-11-06 after the first try looked cluttered: one measure per chart and never two axes on one chart. The days and the hours each get ROAS, spend and CBH stacked so a column lines up down the page (`PennyColumns`). ROAS is a bar for a day, and for an hour of the day a dot for its average on a band from its bad day to its good day. Spend is split by how each hour did, and CBH is drawn above or below zero. Green, yellow and red mean profitable, above breakeven and below it everywhere, Penny's read included: the read's values carry `Ledger.Tone` marks and are drawn bold in that colour. Below the charts come a calendar, any day pressed hour by hour, where the budget went (one bar split by verdict, then by the ROAS each hour of each day brought back), the weeks from Monday (spend and revenue, night against peak, dead spend, CPM) and each creative's orders hour by hour on one canvas. Breakeven sits beside the product's name, and the data strip lists the days newest first, in one row (every day the copy keeps; those outside the range picked grey at half opacity, 2026-11-09, and the range's newest scrolled to the left edge) (arrows when it overflows; it keeps its place on the minute's refresh). Ported back from the Windows app (2026-11-09): the day range selector beside the breakeven pill (`DayRangeSelector`: Today, Yesterday, 7D, 14D, 30D, Custom; ‹ › step the same number of days, never past today, `Ledger.shift`), on its own line when the row is narrow; Custom opens `RangePicker` (two months, two clicks, quick picks for whole months). The charts are drawn on canvases as the Windows app draws them: each hour's column (and Hour by hour row) shaded by its average against breakeven (`Ledger.shade`; a day opened hour by hour by each hour over all the days), washes down all three charts, bars rounded at their end, values on them when they fit, breakeven and profitable numbers on the axis, values past the top marked, bars growing in on new days (a fresh copy keeps the open day); the calendar sits under the plot and lights with the columns; weeks show spend and revenue a day with tips. The days are compared with the same number just before, named and dated (`Ledger.Against`, `Ledger.before`: today matched hour for hour against the day it meets, totals a day when fewer earlier days were copied), in the read, the header and each figure's tip. The figures are two rows (2026-11-10, you asked: in → out, then stats; a first try, ads over product, read badly): **Money**, from the days' CBH, every source, Marketing → Product cost → Tax → Other costs (what the database's `cbh_tax` takes off besides those, about 9% of revenue before tax, fees and the like, so the row adds up; revenue is after tax already, so tax is not taken off it again, and Tax's pill says so) → Revenue → CBH, arrows between (`FigureFlow`, `FigureArrow`; none at a row's start when it wraps), the ads' own spend and revenue as pills and %CBH a pill on CBH (just the ads' spend → revenue until the range's CBH is in); **Stats**, the ads as copied hour by hour: ROAS, orders (all sources' in a pill), cost per order, order value, and CPM, CTR and CR in one card; 6, 3 or 2 equal columns; a pill's change is in its tip. Product cost has a pill with its share of revenue. The product list shows each product's CBH over the range instead of its spend (green made money, red lost; – until the range's CBH is in; spend in the row's tip) and its ROAS coloured against the product's own breakeven, as its page colours it (2026-11-10, you asked, to see which products do well and study them); most spent first unless you sort it: a press on the header's products count, CBH or ROAS sorts by it (names A to Z, CBH and ROAS highest first; products without CBH last), again the other way, a third time back to most spent, remembered; a hairline between rows; fixed columns, the header as wide as the rows inside the scroll view (`PennyProductList.rowsWidth`; 2026-11-10: with the scroll bar always shown the header ran under it and sat off its columns). The panels sit two to a row in a wide window (`PanelFlow`), the opened day under its row. To keep the page quick (it was slow): `PennyAnalysis` works the product out once, off the main thread, `ProductDetail` redraws only when that changes, and hovering redraws only a thin layer over the charts (`PennyHover`), never the charts; the hour table and the creatives' and campaigns' tables are drawn as one canvas each (`PennyGrid`: header buttons sort, the row under the pointer is lit with its tip), not a view per cell: with selectable text and a tooltip in every cell they were 392 and 562 views and scrolling to them crawled (2026-11-09). From the copy he shows each product's totals, his written read (against the days before, the creatives that sell and the ones that only spend, the best and weakest hours), the product by day and by hour, each creative's orders hour by hour, and its creatives and campaigns. A creative is the ad's name, so the same creative in several campaigns is one line. He only reads, never changes anything in Grafana. **Sage** (research; personal, not Crossian's: staged here for the user's Windows app, which will take him; Basil, the recipe helper, grown into him on 2026-11-06, his basil/ folder moved to sage/ and his recipes folder made the Recipes topic) keeps your research by **topic**, each with its own folder in your Obsidian vault and kind of note: Recipes (ingredients and steps; to try, made, favourite) or research notes (summary, key points, details, quotes, open questions, sources; to read, read, key). His logic is Foundation only for the port: `Study` in `Sources/SageStudy.swift` (YouTube, recipes, notes, chat), `SageResearch.swift` (topics, web pages, research notes) and `SageNotes.swift` (a note drawn as Obsidian's reading view); `SageDesk` and `Sage.swift` are the Mac around it; port notes in `docs/sage/README.md`. He finds videos with YouTube's Data API on your key (Keychain; about 100 searches a day free; no scraping of youtube.com, no captions: the API gives none, so long talks are pasted as transcripts into Write your own) and reads web pages you paste or drag in, plainly, as any program asks (a page that refuses is reported, not worked around). What you save (Save, a drop on Saved, his picks, or the chat's `save`) is kept in the app per topic (sage/saved.json); a note is written only when you press Write or Write all, by the helper brain without inventing anything, into the topic's folder (asked for then), never over a note already there. He reads and writes only the topics' folders. His page is one dashboard (no tabs, you asked): a header with the topic menu, its counts (each filters its notes), the vault folder and the YouTube key; the chat on the left (rounds that can search YouTube or read notes by title, with a history kept in sage/chats.json); beside it the Research stage (Find, Saved, Write your own) and the Notes stage: your whole vault as Obsidian's explorer shows it (`SageVaultDesk`, `SageExplorer`; tree settings and tabs in sage/notes.json; **folder focus**, 2026-11-10, hoisting as in Workflowy and Notebook Navigator: a double-click on a folder, its right-click, ⌘→ or the path bar's folder menus' Focus here make it the tree's root, the bar's title a breadcrumb (each level a click, the vault's to leave) with ‹ up (⌘↑) and × out (Esc); search, Pinned and Recent keep to it, the bar's new note and folder go in it, following never leaves it and showing anything outside leaves it first; `Settings.focus`, optional, follows `repath` and is dropped when the folder is gone; helpers `Study.inside`, `scoped`, `keptFocus`, `focusLevels` in SageFiles.swift; the rows cache keys on it), the open files in tabs drawn by `SageNoteView` (a WKWebView per tab, served by a WKURLSchemeHandler under sage://sage/, pages never handed over as strings) with Obsidian's own app.css, fonts and icons read from the installed Obsidian's obsidian.asar (copied once per version into the app's cache, read only), then your plugins' styles, theme and snippets; Bases, canvases and Vault Agent's embeds (`SageBases.swift`). Brought back from the Windows app (2026-11-09): **Pick for me** works as a curator (`Sources/SagePick.swift`, the desk's side in `SageDeskPick.swift`): up to three searches (your words and two angles from the brain), merged and screened in code (Shorts, already saved or written, reuploads, music, reactions, compilations; mukbangs for recipes), every video left scored by the brain on a four-part rubric, then code keeps only those at 70/100 or more, one per channel, no two alike, nothing covering what you have, at most five. From the chat (`Sources/SageActions.swift`, 2026-11-09) Sage also acts when you ask: he connects a vault from Obsidian's own list (obsidian.json, read only when asked; it becomes the Notes stage's vault), sets a topic's folder, makes, renames and opens topics, finds and reads any note in the whole vault, and writes, adds to, marks, moves and renames notes (links follow a rename). He does what you ask with his full tools (2026-11-09: he used to call them "the Vault Agent", say he couldn't edit properties or bases, and ask "just say yes"): the `agent` action is Sage himself, never named as another helper; he asks only when he can't tell what you mean, and deletes only when you clearly ask, into the vault's .trash. A [[link]] to a note that doesn't exist is drawn dimmed (`is-unresolved`) and, clicked, makes the note where the vault puts new notes (or the folder the link names) and opens it, as Obsidian does (2026-11-09). Switching a tab's note (2026-11-10: a link pressed once showed the new note's tab and path over the old note's page): `SageNotePage` loads a page unless it is already in the web view or on its way (`pageFile`, `loading`), a show cut off by a newer one leaves the newer one to load, what the old page still says while the new one loads is dropped (its typing saved into its own note, `editQuietly`; links and keys still work), and text flushed while switching goes into the note it was typed in; each switch is logged (`log show --predicate 'subsystem == "EditAssist"' --debug`). Back and forward in a tab (2026-11-10, you asked; `SageHistoryInput`, one app monitor on while the notes stage is shown): ⌘[ ⌘] and ⌘⌥← ⌘⌥→ (not while typing in the chat), a mouse's side buttons 3 and 4, and swipes, which is how Logi Options+ sends the MX Master's Back and Forward (`OSX_GESTURE_BACK`; deltaX 1 is back), as do three-finger trackpad swipes; taken before the note's page sees them. Use /usr/bin/log in zsh: `log` alone is a zsh builtin. Media in notes (2026-11-09): a YouTube card plays in place (`SageInlinePlayer`: YouTube's own player, waiting for a click, laid over each card in or near sight, at most three a note, and moved with it as it scrolls, so one click plays; a player made on the click needed a second click, since YouTube starts only for a click on its own player; YouTube refuses `sage://` pages with Error 153, and an https page can't load the vault's styles and scripts), a YouTube link elsewhere plays in Sage's mini player (a web page still opens in your browser), video and sound files in the vault play in the note (the scheme handler answers byte ranges), and a picture opens full size on click, a video on double-click, in `pageScript`'s media viewer (‹ › and the arrow keys step through the note's pictures and videos, Home/End, Space plays, Esc closes); a video's or sound's controls keep their clicks while editing (they're in `embeds`); the chat and the notes stage fill the window's height (`SagePage.columnsHeight`); a theme's "newer Obsidian installer" notice, shown because WebKit lacks `interpolate-size`, is hidden (`Study.afterTheme`). Every change is listed under his message with Undo (this run only; a step is undone only while nothing has changed it since), a note is copied to sage/edited/ before he first changes it, and edits go through a hidden file beside the note so it keeps its dates, line endings and byte-order mark. Find shows its steps while it works, then "Saved N of M looked at", why each was picked and a folded Passed over list (Save anyway). Its reasons are `Study.Says` templates, so they show in Vietnamese; `EDIT_ASSIST_SAGE_PICK_FIXTURE=Tests/Fixtures/Sage` runs it on fixtures with no key or brain call. Any YouTube video (Find, Pick, Saved, the chat, a note's source) plays in Sage from its picture (`Sources/SagePlayer.swift`): YouTube's nocookie embed in a small page loaded with https://sage-player.example/ as its address (without an origin and referrer the embed fails with Error 153), docked bottom-right (400 pt) or expanded over the stage (remembered), with Save, Write and open on YouTube; links open in your browser and leaving the page stops it. The lines between chat, Find and Saved drag to size the columns (remembered), Find and Saved sit side by side once the stage is 820 pt wide, and cards fade in once and lift under the mouse (`Sources/SagePickView.swift`; Reduce Motion stops the movement). Built first in Creative Assist and brought back 2026-11-09; the Foundation parts (`SageVault`, `SageFiles`, `SageObsidian`, `SageBases`, `SageNotes`) are checked in Tests/Sage*Checks.swift on temp vaults. **Sage as an agent** (2026-11-09, the user's Obsidian plugin Vault Agent brought in; `Sources/SageAgent.swift` Foundation + the CLI process, `SageAgentDesk.swift`, `SageAgentView.swift`, `SageChatMarkdown.swift`; checked in Tests/SageAgentChecks.swift): the helper brain's CLI (Claude, else Codex) run with its own tools in the vault as Vault Agent runs it (`claude -p --output-format stream-json --verbose --include-partial-messages --model --permission-mode bypassPermissions --effort --session-id/--resume`, prompt on stdin, cwd the vault root so it reads the vault's CLAUDE.md and the one above; Codex `exec --json`, given CLAUDE.md on a new thread), the session kept per conversation (`Study.Conversation.agent`). Vault Agent's quick commands, prompts word for word: Process, Summarize, Review on the note bar, Categorize, Links, Rename, Memory, Fetch media, Transcribe, Process & localize in its menu, and the same as /commands in the chat (words after one become "Additional instruction"); the chat's brain hands tool work over with an `agent` action. Memories are Markdown notes in Vault Agent's memory folder (the agent is told to keep them; the pinned and relevant ones are put in its prompt as Vault Agent does). No default model (you asked): the first run asks for a model and effort, remembered per CLI (UserDefaults `sageAgentModel.<CLI>`), changed from the chat's model menu; Claude's list is its aliases (read from `claude --help`, always the newest) then full ids, Codex's from ~/.codex/models_cache.json; Vault Agent's data.json in the vault is read for six keys only (its choice pre-selected, permission mode, memory folder; never its chats). Fetch media and Transcribe call `SageMedia` (SageMedia.swift, the media port's). Steps stream into a run card (what it's doing, Stop), then a summary: the files changed, made and removed (the vault read before and after), what was copied first and Undo. Safety: never without a vault; the open note is copied into sage/edited/ before a run and each file the moment its Edit/Write call shows in the stream (best effort: it races the CLI; Bash, Codex and files outside the vault aren't copied, and are listed as such); Undo puts back each copied file only if it still reads as the agent left it. **Sage's media tools**: **Fetch media** and **Transcribe** (`SageMedia.fetch`, `transcribe`; `Sources/SageMedia.swift`, logic in `SageMediaText.swift`, checked in Tests/SageMediaChecks.swift; ported from the user's Vault Agent plugin, 2026-11-09): social videos with yt-dlp and picture links into the vault's attachments folder (app.json `attachmentFolderPath`), each link made `![[file]]` only when a new file is really there, the first thumbnail as `banner:` only when the note has none; a login gate retries with an installed browser's cookies (Chrome's can ask for the Keychain); transcripts by WhisperX as "## Transcript" under the source, audio in a temp folder deleted after. yt-dlp is the first that runs from your shell, Homebrew, ~/.local/bin, Vault Agent's in the vault, else downloaded once into Application Support/Edit Assist/bin; WhisperX is Vault Agent's runtime, a python3 that already has it, or a private one made in Edit Assist/whisperx on first use (many minutes, every step said). Sage's replies are drawn as Markdown (headings, lists, code, tables, links, [[wikilinks]] opening the note). **His message box** (2026-11-10, you asked for one like Claude's; `Sources/SageComposer.swift`, Foundation in `SageComposerText.swift`, checked in Tests/SageComposerChecks.swift): a rounded box lit in his colour while you write, growing a few lines then scrolling; under it + (attach), / (his commands), his model menu (moved there from the chat's header) and ↑ send (Stop while he works); Return sends, Shift+Return starts a line. Typing @ opens Kino's list (`KinoTagPicker`, its pill `KinoTagAttachment`) with the vault's notes and files (`Study.tagChoices`: the quick switcher's fuzzy match, notes first, recent first); the pick is a pill kept as its [[link]] (typing a [[link]] whole makes one too); / at the start lists his commands. On send each tagged note is read for the chat's brain (as his `read`) and its path told (`taggedPrompt`); a command with a tagged note works on that note, not the open one. Files come in by +, a drop on the box or the chat, or a paste (copied files, or a picture saved as "Pasted image … .png"); a note of the vault dropped in is tagged instead. Shown above the text with ×; on send, files outside the vault are copied into sage/attachments/<day>/ ("name 2" when taken; `keepAttachments`), files in the vault referenced in place, the paths kept on the message (`Study.Message.files`, optional), and the message goes to his CLI (the brain can't see files), told each full path and how to look at it (`composerContext`; Claude gets `--add-dir` for that folder). Sent messages show pictures and videos as thumbnails (Quick Look on a click, `SageQuickLook`), other files as chips (Finder), tags as links opening the note.
Built first in Creative Assist and brought back 2026-11-09; the Foundation parts (`SageVault`, `SageFiles`, `SageObsidian`, `SageBases`, `SageNotes`) are checked in Tests/Sage*Checks.swift on temp vaults.
Processes run off the main thread, their lines streamed to progress, killed when the task is cancelled; note edits go through `Study.writeNote`, applied to the note as it reads when written.
**You edit the vault from Sage** (the user's request in Creative Assist, 2026-11-07/08); the model does only through the chat's actions, when you ask (`SageActions.swift`, 2026-11-09), under the same rules. In a note, only the lines of the block you changed are written, and only if they still read as when the page was drawn (`Study.editLines`); the note as it was is copied into sage/edited/ before its first edit in a run (kept 30 days); the new text goes to a hidden file beside the note that replaces it in one step, keeping its line endings, BOM and created date (`Study.writeNote`). A canvas is saved only over the version the page was drawn from (`Study.saveCanvas`, written as Obsidian writes it); a note's text edited on its canvas card only if it still reads as it did (`Study.saveNoteBody`). **Properties** (2026-11-10, you asked: a click turned them into raw YAML) are edited as in Obsidian's Properties table, in reading and editing view (`Sources/SageProperties.swift`, checked in Tests/SagePropertyChecks.swift; the `props` part of `pageScript`, message "property"): a value where it is (text, number, date, date & time, a tick, a list's pills with ×, Enter or a comma adding one and Backspace taking the last; a [[link]] value by its pencil), the name by clicking it, the row's icon for its type (Text, List, Number, Checkbox, Date, Date & time; written to .obsidian/types.json only when you change one, `Study.typesJSON`) and Remove, Add property (and Cmd+;, which gives a note without frontmatter one); Enter or leaving saves, Esc puts back. `Study.changeProperty` changes only that property's lines (quotes kept, lists as `key:` + `  - item`, the last property removed takes the frontmatter), only if the frontmatter still reads as drawn (`front`, sent with every redraw), through `Study.writeNote`; one change at a time, the note redrawn around the field you're in (`propKeep`). A value over several lines is left to its YAML: the properties block's corner button (editing view) opens it as before. From the tree: move, rename, new note or folder, duplicate, delete, copy files in; links follow a move or rename as Obsidian's "update internal links" does (`Study.relink`, unless app.json `alwaysUpdateLinks` is off), notes rewritten through `Study.writeNote`; delete follows app.json `trashOption` (the vault's .trash, else the Trash) after a copy into sage/edited/deleted/; every change can be undone (`SageVaultDesk.undo`), each step only if nothing changed it since; nothing is moved over something already there. Never test with the real vault. Each helper has a colour, their body's, for their sidebar button and page.
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
