# Edit Assist

A native macOS prototype for a conversational desktop editing assistant. It stores instructions and a chosen visual style per project, reads bold phrases from a script, and proposes/executes mouse and keyboard actions against a selected Adobe window. No Adobe plugin or scripting interface is used.

## Install

In Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/regulartoast2812/Edit-Assist/main/install.sh | bash
```

This downloads the latest release into `~/Applications/Edit Assist.app` and opens it. Run the same command again to update. Requires macOS 14.2 or later, on Apple silicon or Intel; no Xcode needed.

On first launch macOS asks for **Screen Recording** and **Accessibility** (System Settings → Privacy & Security). Edit Assist needs both: it reads your Premiere or After Effects window and clicks and types in it. Releases are signed ad hoc rather than with a developer certificate, so macOS asks again after each update.

To publish a new release (maintainers): bump `CFBundleShortVersionString` in `Resources/Info.plist`, then `./release.sh --publish`. It runs every test first and publishes nothing if one fails.

## Build from source


Edit Assist installs to **~/Applications/Edit Assist.app**, so it is reachable from Finder's Applications sidebar, Spotlight and Launchpad. Double-click **Launch Edit Assist.command** to open it.

`./build.sh` compiles, quits any running copy, reinstalls to `~/Applications`, and relaunches, so you are always looking at the newest build. Pass `--reveal` to also show it in Finder. Requires Xcode command-line tools and macOS 14.2 or newer; no third-party packages are needed. The `dist/` folder is only a build staging area — do not launch from there.

`build.sh` signs with a stable self-signed identity created by `setup-signing.sh`, which runs automatically on first build. This matters: an ad-hoc signature gives the bundle a designated requirement that pins its cdhash, and the cdhash changes on every build, so macOS silently discarded the Screen recording and Accessibility grants each time. The fixed certificate produces `identifier "com.crossian.editassist" and certificate leaf = H"…"`, which is identical across rebuilds, so a grant now sticks. The certificate lives in its own `edit-assist-signing.keychain`; the login keychain is untouched. Remove it with `security delete-keychain edit-assist-signing.keychain`.

Because the identity changed, approve the app once more, and delete any older **Edit Assist** rows in System Settings with the minus button — entries created under the previous ad-hoc signature can never match again. **Assistant → Permissions…** shows the running bundle path and its signing status so you can confirm you approved the right copy.

## First run

1. Name the project. Paste your script with ⌘V or **Script → Paste formatted text**. Both paths convert HTML/RTF bold or heavy font weights into `**phrase**` markers. If the source clipboard contains only plain text, formatting cannot be recovered: select phrases and press ⌘B (or **B · Mark selection**). Review the parsed highlights. **Use your example** loads a sample script.

   You can also **Add screenshots…**, **Paste image**, or paste an image with ⌘V into either editor. Up to four screenshots can accompany a message. Use them to describe a UI or style; **Read as script** requests transcription with visible bold phrases and opens a draft for review before replacing your script. Image interpretation can be ambiguous, so check its wording and emphasis. Screenshots attached to conversations are saved with that project, and up to four recent attachments are passed as references in later conversation turns. They are never treated as live desktop coordinates.
2. Codex CLI is selected by default. **Assistant CLI** lets you switch to Claude Code or Antigravity CLI (`agy`). Edit Assist uses the selected CLI’s existing login; there is no API-key form. Leave the model override empty to use the CLI default. If needed, sign in in Terminal with `codex login`, `claude auth login`, or `agy`. Detection checks installation, not authentication.
3. Grant **Screen recording** and **Mouse & keyboard** (Accessibility). An orange banner appears under the project name whenever either is off; click **Fix now**, or use **Assistant → Permissions…** (⇧⌘P), or the sidebar rows. The panel offers both **Ask macOS** and **Open System Settings**, because macOS shows its own popup only once per app — after that the system prompt never reappears and you must tick Edit Assist by hand. **Quit & reopen** in the same panel relaunches the app. Screen recording is read once at process start, so a running app never observes a grant you just made, no matter how long it waits. If the switch is on and the panel still reports Not allowed after a relaunch, the row in System Settings is an orphan from an earlier copy or signature of the app and can never match; **Reset & re-register** runs `tccutil reset` for this bundle id only, then reopens so macOS asks cleanly. Reopen the app if macOS requests it. There is no window picker: Edit Assist watches for **Premiere Pro** and **After Effects** only, and shows the one you last worked in as **You're editing in …**. Every other app is ignored, including other Adobe applications such as Media Encoder, so clicking your browser or editor never retargets it. Click your Premiere or After Effects window once, then return here. The target is re-checked about once a second while idle and frozen for the duration of a run.
4. Open Premiere's style browser, click **Capture**, and drag a rectangle around the desired style tile in the preview. The crop is a visual reference, not a fixed click position. Alternatively, describe the style in the conversation or import a cropped PNG/JPEG.
5. Tell the assistant the scope. For example: “Use this project's reference style. Only highlight the bold words in the currently selected caption.” Review **Routine → Current run** for the explicit run instruction, and **Pause below** for the confidence threshold. The model scores its own certainty and is poorly calibrated: sound, well-evidenced decisions commonly report about 0.7, so the threshold defaults to 0.6. Raise it to stop and review more often, lower it to let the routine keep moving. Pause playback and put Adobe at the intended starting point.
6. **Preview step** captures the current window and proposes one action without clicking. **Do one step** activates Adobe after a three-second countdown, observes again, plans and sends one action, then captures the result. **Run routine** repeats for up to 40 actions before pausing. Conversation alone never starts desktop control.
7. While a routine runs, Adobe is focused and the Edit Assist window is behind it, so a floating overlay appears above the target window showing the step number, what it is about to do, the model's confidence and any pause reason. It never takes focus and ignores mouse events, so clicks pass through to the editor; `Desktop.checkHit` is told to ignore it so it is not mistaken for a covering window. It is not part of the capture sent to the model.
8. If another window covers the target, the pass **waits** rather than giving up: the overlay names what is in the way and how long it has waited, and the run carries on by itself once you move it. Input monitoring is disarmed while waiting, since otherwise moving the mouse to close the dialog would be read as you taking control and stop the run. It gives up only after fifteen minutes.
9. Escape, manual mouse/keyboard input, or the Stop button cancels the run. The assistant also pauses on uncertainty, changing window geometry, focus loss, intervening windows, a changing screen while planning, or a repeated-action loop.

## What is implemented

- Native SwiftUI project sidebar, chat, script editor, rich-text import, highlight preview, editable learned routine and visual style selection.
- Codex CLI, Claude Code and Antigravity CLI adapters with screenshot inputs and validated JSON decisions. Codex receives image attachments and Claude receives base64 image blocks over streaming JSON input. Antigravity accepts text blocks only, so its screenshots are written beside the request and read with `view_file`, the single tool it is permitted.
- Automatic detection of the frontmost Premiere Pro or After Effects window, matched on bundle id and application name so yearly releases keep working, with ScreenCaptureKit captures of that window. Switching targets discards the previous capture, so a stale screenshot is never shown or sent to the model. The model sees the latest capture, previous capture, style reference and recent action history.
- Bounded clicks, double clicks, drags, scrolls and navigation/selection shortcuts through macOS events.
- Per-project style and instruction persistence, existing CLI authentication, activity logs, subprocess timeouts/cancellation and a preview mode.
- On-device OCR of each captured window through Vision, about 0.5s for a full-screen window. Recognised lines and their measured normalized boxes are supplied to the model as data, so it cites measured coordinates instead of estimating them from pixels.
- A `selectSpan` action: the model names the exact words to select and Edit Assist computes the drag from measured word boxes. If the phrase is not found, or its words resolve to different lines, or the span would be wider than the line containing it, the action is refused rather than approximated, because selecting a whole caption would restyle text that was never marked.
- A magenta coordinate grid drawn over the screenshot sent to the model, labelled every 0.1 on both axes, which reduces off-target clicks caused by estimating positions on a bare image. Only the model's copy is annotated; the preview and style crop use the raw capture.
- Exact Unicode text spans, multi-line bold formatting and separate occurrences of repeated phrases. The visual model is responsible for matching these to the live timeline; there is no deterministic caption/timecode alignment yet.

## Highlight text (no model)

The **Highlight** tab runs the whole pass without any CLI, model or network. One `VNRecognizeTextRequest` over the captured window, about 0.55s, gives every visible line and word with measured boxes.

Measured over the sample script against a real 3446x1910 screenshot: **7 of 7 phrases resolved in 0.559s total**, one OCR pass reused for all of them, each selection width proportional to its phrase.

### Stages

Each stage has a tickbox, and the checklist runs only the ticked ones:

1. **Escape** — leave any text edit, so the next keystroke is not typed into a caption.
2. **V** — the Selection tool, needed to click a clip.
3. **Click the caption in the Program Monitor** — the caption is on screen, so clicking it with the Selection tool selects its clip. The timeline is never scrolled, searched, or matched by label. Premiere ignores text edits until the clip is selected, and the result is verified from the Properties panel, which reads *Select a clip in the timeline to view properties* when nothing is selected.

   Two fallbacks remain for when that does not take: clicking the caption track under the playhead, whose position comes from the timeline **ruler** (its timecodes are centred on their ticks, so two of them give a seconds-to-x mapping) rather than from colour alone, because the playhead and the timeline's scrollbar are both thin blue lines and on a real capture the scrollbar was clicked instead; and then **D**, Select Clip at Playhead, which needs the Subtitle track targeted.

4. **Double-click the phrase's first word** — not the span midpoint, which can fall in the gap between words and only drop a caret.
5. **Drag across the phrase** — the exact measured range.
6. **Open the style panel** — the four-square button, skipped when the panel is already open.
7. **Click the style tile** — the tile matching this project's style reference image.
8. **Back out of the style panel** — returns to the outer panel, skipped when already there.
9. **Increase the font size** — reads the Font Size number, clicks it, types that number plus the step, presses Return. The step is set in the Highlight tab.

   Premiere draws that number small, isolated and in low contrast, and a whole-window pass can miss it entirely. When it does, the row is re-read at five magnifications and the majority value wins: a two-digit number has no unambiguous orientation — `60` upside down reads as `09` — and recognition genuinely picks differently at different scales, so one reading cannot be trusted.

The order is not fixed. After the selection, Premiere shows either the style browser or the outer properties panel, and the path follows from which one, detected by whether a **Back** button is present:

- **Style browser showing** — click the tile, press Back, then increase the size on the outer panel.
- **Outer panel showing** — increase the size first, then open the browser and click the tile.

The stage list shows the gestures in one order for tickability; the run picks the order from the panel. Which one was chosen is written to the log at the start of each phrase.

Nothing is recorded by demonstration, so a project works unchanged on another machine with a different panel layout:

- **Back** is ordinary text, found by its own label.
- The **four-square** button has no label, so it is found as the last control on the Track Style *value* row — the one showing the current style — by scanning that row band for ink against the panel background and taking the rightmost icon-shaped cluster. The band is sampled at the window's native resolution, since downscaling a whole window to a few hundred pixels smears a 20px icon into the background, and clusters are filtered to roughly square ones that sit inside the row. Width alone is not enough: a window edge or scrollbar can be the same width as the button, so a cluster is also required to paint less than the full band height and to have an aspect ratio near 1. If nothing matches, it reports rather than falling back to the rightmost cluster, which is how it ended up clicking the window edge. It is deliberately not the Track Style *header* row, whose right-hand control is the + that creates a new style.
- The **style tile** is found by matching this project's style reference image against the capture, so the tile is identified by how it looks rather than where it sits. The comparison is in colour, not luminance: style tiles differ mainly by hue, and a blue and a pink swatch are only 0.085 apart in brightness, so a grayscale match picks the wrong tile. A coarse colour sweep over several scales proposes candidates, and each is then rescored at the reference's own resolution with an edge term added, because tiles can share a hue, a typeface and a size and differ only in stroke weight, which a downscaled average colour cannot see. Measured over six tiles differing only in stroke, the nearest wrong tile scores 5 on colour alone but 13 with edges, against 0 for the right one. Nine scales are tried from half to one and a half times the reference, because a resized Properties panel renders tiles well outside a narrow range: on a real capture the reference was 1.4x the tile on screen. The search is limited to the style panel, found from its own labels, which is both faster and less distractable. The failure message reports the best score, so a near miss is distinguishable from looking at the wrong panel. Capture or import a style reference for this to work; the stage says so if one is missing.

Which of 6 and 7 you need first depends on which panel Premiere shows after the selection; untick whichever does not apply.

Typing is restricted to at most four digits, so a stray phrase can never be typed into a project.

### Running

- **Run checklist** performs the ticked stages instantly, with no countdown, on whichever script phrase is readable on screen, including ones already done, and records no progress. Use it while tuning.
- **Do next** does one phrase and records it. **Reset** clears progress.
- **Run all** walks the sequence on its own: style whatever is on screen, step the playhead to the next edit point with Down, look again. Before each step it presses Escape and clicks the timeline. Both are needed: styling leaves a caret blinking in the caption, and while text editing is active Down moves the caret rather than the playhead whatever has focus; and Down only reaches the playhead at all while the Timeline has keyboard focus, which after styling sits in the Properties panel. The click goes to the caption track at the playhead, which also selects the clip already under it without moving it, or to the track header when the playhead is scrolled out of view. Each step is logged as `next edit point 7.20s -> 8.40s`, so a playhead that is not moving is visible rather than inferred, and a stuck one writes `ocr-dump.png` so the screen that caused it can be examined. **Run all** starts a fresh pass at the current playhead, clears prior assistant progress, and leaves earlier captions untouched. Stop cancels the pass. The end is detected by the playhead's timecode refusing to change rather than by a step count, so a long sequence is not cut short and a finished one does not spin. It reports what it could not find:

  `Reached the end of the sequence. 2 phrases not found: "65% OFF", "GET YOURS NOW!".`

  Reading that timecode needs the ruler, and the Program Monitor shows its own pair of timecodes — current time and duration — which is indistinguishable from a ruler by count alone. The ruler is identified by position instead: it is the row of timecodes directly above the track rows.
- **Dump OCR** writes everything recognition sees, plus the capture itself, to `ocr-dump.txt` and `ocr-dump.png` next to `projects.json`.
- Every stage is logged as `OCR ok`, `OCR skip` or `OCR fail` with its elapsed time, so a failing stage is named rather than inferred.
- Progress is a set of completed phrases, so you can work out of order and resume.
- A caption that wraps onto a second line is treated as one block, so a phrase is selected across the wrap by dragging from its first word down to its last, as a person would. A gap of more than a couple of line heights is not a wrap and is refused.
- One recognised word can be several words of a phrase: `ultra-light` is `ultra` and `stretch`. Each keeps its word's box, so a phrase starting mid-hyphenation still resolves.
- Premiere splits long phrases across caption clips, so a phrase is styled **in parts**. Each pass selects as much of the remaining phrase as this clip shows, records how many words that covered, and carries the rest to the next clip. A phrase counts as done only when every word is styled, and the log names the range: `styled 1-2 of 5 words of "high-neck, ultra-light lining" — the rest is on the next caption clip`. Progress is kept per phrase rather than per index, so editing the script does not lose it. The **Highlight** tab lists every phrase with its word progress, and **Redo** clears one phrase without discarding the rest of a pass — useful when a mis-match has left a phrase recorded as part-styled.
- The caption text appears in three places: large in the Program Monitor, and at interface size in the Properties panel's caption field and in timeline clip labels. Only the Program Monitor copy can be edited, so blocks close to interface size are excluded, measured against the median height of all recognised lines. Where no size separation exists, the largest block is used.
- If the timeline is scrolled so the playhead is off-screen, the pass steps one frame back and forward, which returns to the same frame and makes Premiere scroll the playhead into view, then looks again.
- The same words can appear twice on screen: large in the Program Monitor caption and small in a timeline clip label. Both the span finder and the clip finder anchor on the **largest** match, because selecting inside a clip label would edit nothing and leaves no smaller label to match against.
- Each phrase logs its measured span before acting, so a run that targets the wrong text is visible in the log rather than inferred from behaviour.
- If a phrase is not on screen, or its clip is not found, it pauses and says which. The same refusals as `selectSpan` apply: words on different lines, or a span wider than its line, are never approximated.

The model-driven buttons stay behind the **OCR only** switch in the footer, which is on by default.

## Speed

Each step spawns the chosen CLI, sends the screenshot and waits for one decision, so step time is dominated by that call. Measured on this machine with the real system prompt and schema:

| Provider | Per step |
| --- | --- |
| Claude | **7.6s** |
| Codex | 8.5s |
| Antigravity, `gemini-3.8-flash-low` | 31s |
| Antigravity, CLI default model | 28-62s |

Claude and Codex attach images inline. Antigravity cannot, so it opens every screenshot with a `view_file` tool call before it can reason, and that agent loop costs roughly 30s a step no matter which model it runs. It is a capable CLI but a poor fit for one decision per click; prefer Claude or Codex for routine runs.

Defaults follow from this. Antigravity pins `gemini-3.8-flash-low` unless you set a model override, and a preference left over from the removed Gemini provider resolves to the fastest installed CLI rather than to Antigravity. An explicit choice in **Assistant CLI** is always respected. A step that exceeds 75 seconds is treated as wedged and reported, instead of stalling for two and a half minutes.

Execution steps send the latest screenshot and the style reference only. The previous screenshot is no longer sent, and the conversation and activity excerpts are short, because every extra token and image is latency on each step.

Every step writes to the project activity log: which CLI and model were asked, how long the reply took, the action kind and the confidence. Stops and failures are logged too, including runs you interrupt, so a slow or silent run can be diagnosed afterwards from **Activity** in the inspector.

## Current limits

This is an CLI-backed prototype, not a validated unattended editor. Text selection and style recognition depend on model accuracy. Confidence is model-reported, not a measured guarantee, and it is not calibrated; treat the threshold as a stop-frequency dial rather than an accuracy setting. The user must inspect the first caption and style result before longer runs. A reported completion is labeled as the assistant's claim for review.

The first routine targets Premiere's Properties/style browser. After Effects is detected and can be selected, but it needs its own taught procedure and has not been validated. Detection picks the app's largest ordinary window, so a project spread across several equally large windows may need you to click the intended one. Separate floating panels, menus or modal dialogs may be blocked as overlapping windows. Keep the relevant panels docked in the selected window. Video playback or animated content may cause stale-screen checks to pause. UI actions share your mouse and keyboard.

Teaching currently means natural-language instructions and reference images. Recording demonstrations, background always-on monitoring, document/spreadsheet file parsing, persistent per-caption completion state, and automatic resumption after app restart are not implemented. Paste formatted content from the source document instead. Conversation updates style, routine and task-scope preferences; the editable Current run field shows the run scope.

## Data and connectivity

Project scripts, conversations, attached screenshots, style crops and preferences are stored in `~/Library/Application Support/Edit Assist/projects.json`. Action descriptions are stored in project-specific `.log` files there. Screen observations are held in memory; the chosen style crop is persisted. Set `EDIT_ASSIST_DATA_DIR` to use another directory.

The selected CLI receives project context and captured images and uses its existing authentication. Its usage limits, billing and data policies apply. Only one provider is invoked per decision; there is no automatic cross-provider fallback. No API key is requested, read from the old Edit Assist Keychain entry, or stored by this version.

Requests run in private temporary folders, removed after completion or cancellation. Codex uses ephemeral mode and a read-only sandbox with user config ignored (authentication remains available); Claude runs with customizations and tools disabled, using its saved login. Antigravity is pointed at a request-local data directory through `ANTIGRAVITY_EXECUTABLE_DATA_DIR`, whose settings allow `view_file` and nothing else, with slash-command expansion disabled so script text cannot expand into commands; running commands, writing files and browsing are refused, and a refusal is reported as an error rather than acted on. No existing CLI settings files are modified. Temporary files can remain if the whole app is forcibly killed.

The helper process gives each request its own process group so cancellation terminates the CLI launcher and its children. Replies are decoded and action-validated before any desktop input. The app makes no direct model API requests. Installed CLIs were found in Homebrew and `~/.local/bin`; those locations are searched even when Finder launches the app with a minimal PATH.

## Verification

Run `./test.sh` for parser, persistence, rich-text conversion, provider envelope/image wiring, Antigravity's permission allow-list, subprocess timeout/cancellation and action-boundary checks. Tests never post mouse/keyboard events. `Tests/FindProbe.swift` and `Tests/TileProbe.swift` check the control finders against mock panels: the four-square against a decoy control on the same row, and the style tile against a grid of eight similar tiles. `Tests/OverlayProbe.swift` is a manual check that the run overlay appears, is click-through, floats above the editor, is centred on the target window, and is removed from the window server when hidden. Build and UI smoke checks do not establish that a model can reliably complete a Premiere sequence; live workflow validation requires a connected model, macOS permissions and a project to test against.

References: [Codex non-interactive mode](https://developers.openai.com/codex/noninteractive), [Claude Code headless mode](https://code.claude.com/docs/en/headless), [Antigravity CLI](https://antigravity.google/), [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager).

### Style selection consistency

The first style selection in an OCR pass compares distinct candidate locations using colour and edge distance (lower is better, not a confidence percentage). The best distance must be below 28 and at least 5 better than the next candidate; close competing styles stop the pass before the style click. The activity log records the best two scores.

**Your style is taught by clicking it, once per pass.** No reference image is needed. On the first phrase the pass selects the text, opens the style browser and waits, with the overlay reading *Click your style*. Click the preset you want; that click applies it to the first phrase. The pass works out which **row and column** you clicked and, because the browser always opens scrolled to the top, clicks that same slot for every remaining phrase. Input monitoring is off while it waits, so your click is not read as taking over.

The grid is read from the pixels, not from the `Ag` OCR boxes, which merge neighbouring tiles or miss some entirely. The gaps between tiles are flat panel background, so a column or row that is mostly background is a gap and everything between gaps is a tile; OCR only says where the grid is. A separator line crossing it, a scrollbar sliver, and a cut-off bottom row are ignored. Measured on real captures: two rows of six tiles, 172 pixels each with 26-pixel gaps, at the right positions.

Before every click the slot is checked against what the tile you chose looked like, comparing the glyph only. Hovering tints a tile's background, and your tile is captured while the pointer is on it, so the background is ignored: the same tile scores 0 hover or not, while the nearest different preset — the same blue `Ag` with a heavier stroke — scores 29, against a limit of 15. If the slot holds something else, it searches the browser page by page for the same glyph and clicks that instead; if it is nowhere, it stops without clicking. If you scroll before choosing, the slot is found by appearance on later phrases rather than by position.

**Two references for your style.** When the routine asks you to click your style, it records the tile's row and column and also captures an image of exactly that tile. The image is shown beside the progress overlay for the rest of the pass and saved as `style-reference-<project id>.png` in the app's data folder. For the remaining phrases it works the way a person would. The browser opens at the top, so it does not scroll up first. The second time, it scrolls down once, comparing every tile it passes with your image, and clicks as soon as your row is in view and the tile at your column matches (or, since the count can be off by one, the clear best within a row of it: under 45 and at least 8 ahead of the next). Reaching the end first, it goes back up only as far as the best tile it saw. It remembers how many scroll steps that took and where the tile sat, so every later phrase is one quick scroll straight there and a check of that spot; only if your style is not there does it count from the top again. If nothing matches clearly, nothing is clicked and the run stops, with the closest tiles and their scores in the log. While you choose, the list is followed through a live stream, frame by frame, so the row count keeps up with a quick scroll and the image is taken from the frame you clicked on.

**Rows keep their numbers while the browser scrolls.** Row 3 stays R3 as it moves, a row sliding off the top does not disturb the others, and a row appearing at the bottom gets the next number. Rather than matching whole rows — which fails as soon as only one row is fully visible — the tracker follows the scroll itself: between two looks it measures how far the tile grid moved, using every visible pixel of it, partly visible rows included, and takes the shift at which the overlapping parts agree, provided it agrees clearly better than any shift a row away. Rows of presets often look alike, so with live frames a near-perfect match within half a row of the previous frame's movement is taken first; no row-sized alias fits in that window. Frames where the grid itself cannot be made out (common mid-scroll) still advance the scroll from their pixels. The scroll position then gives each row its number from where it sits. The browser opens at the top, so counting starts at R1.

Scrolled further than one view between looks, the count is reported as lost — `R?`, drawn in gray — rather than guessed. A lost count recovers on its own: whether the list is at the top is also read from each look, since scrolled there is a cut-off row of tiles between the Open Projects box and the first full row. The scrollbar backs the count up: its thumb, the light bar right of the tiles, is read on every look and matched against the measured scroll. Once it has moved a few pixels, the thumb alone says how far the list is scrolled, so a count lost in a quick scroll comes back on the next look, and a slip of a row between look-alike tiles is corrected. Colour is a hard gate when comparing a tile with your image: the average of its strongly coloured pixels must be within 30 (the same tile measured 1–16 across captures, different colours 52 and more, pink against maroon about 90), and only then does the letter shape count. Only fully visible rows are counted, clicked or captured; a row cut off at the top or bottom of the view is left out. While the routine scrolls, the count may only move in the direction it is scrolling. A lost count is never reset by a single look that resembles the top: it stays R? until the routine scrolls to the top or the browser has been closed for 1.5 seconds. That single-look test is not trusted over a count being followed, because a view scrolled by exactly a whole number of rows looks just like the top; it only recovers a lost count. Scrolling to the top until the list stops moving resets it outright. Two looks in a row without the browser panel mean it was closed; it starts again at R1 when it reopens. Looks where the panel is there but its grid is unclear never count as closed.

Checked by scrolling a real capture in steps of 50 to 120 pixels, down through four rows and back: every step numbered correctly, including views where a single row is fully visible and views scrolled by exactly one row. `Tests/ScrollTrackProbe.swift` reproduces it.

On the first phrase the pass scrolls the browser to the top before waiting, and you may scroll before choosing: the row you click is recorded as its absolute row. On later phrases it scrolls down from the top until that row is fully visible, checks the glyph, and clicks the same column. If you scrolled too fast to follow, the tile is found by appearance instead.

The grid is found by its shape rather than by the most common colour: square tiles of one size at a regular pitch with narrow gaps. Scrolled, a cut-off row brings the darker Local Styles box into view and the empty panel below can become the most common level, so several background levels are tried and the one that yields a regular grid of square tiles wins; a wrong level carves glyphs into slivers that fail that test. Because tiles are square, the column width also says how tall a full row is, which drops rows cut off at the top or bottom of the view.

With the detection overlay on, whenever the style browser is open it is drawn as the pass counts it: one box per rounded tile, each row in its own colour — orange, pink, purple, mint, indigo, brown — labelled `R2 C4` with absolute row numbers, so a row keeps its colour as it scrolls; each row also carries its number in a badge to its left; and your style is in cyan. Gray means the count was lost. OCR's own `Ag` boxes are left out there, because recognition merges neighbouring tiles into one box and that is not how the tiles are counted.

Once taught, the slot is kept for the pass. Subsequent captions verify the same patch before clicking it; they do not rerank the style gallery. A changed reference, window geometry, or sufficiently changed tile stops the pass. A fresh run makes a fresh choice. These are visual heuristics, not Adobe style IDs, so visually indistinguishable presets cannot be reliably distinguished.

### OCR inspection overlay

Enable **Show OCR boxes while running** on the Highlight tab before starting a pass. A transparent, click-through overlay follows the captured editor window. Yellow boxes are caption candidates admitted by the current matcher; gray boxes are OCR text excluded by its size filter. Green shows the matched script range, and cyan shows style candidates and their image-distance scores or the locked style tile. These are the tool's actual heuristic classifications, not general object recognition.

Boxes refresh with each OCR capture, and the legend shows its timestamp. Captures without OCR keep the last OCR snapshot. The overlay is excluded from editor-window captures and ignored by click-obstruction checks. It disappears when the pass stops or the toggle is disabled.

### Continuous detection mode

The **Detection** bar is always visible above the bottom run controls, on every tab. **Always on** continually captures and recognizes the focused Premiere/After Effects window without activating it, sending input, or changing project progress. It watches the window through a live ScreenCaptureKit stream, which delivers a frame only when the editor's pixels change (up to 30 per second), so an idle editor costs nothing and a scroll in the style browser is tracked frame by frame; the grid and row tracker take under 10 ms per frame. Text is re-read (OCR, ~0.2–0.3 s, off the main thread) after the screen changes, at most every 0.6 s, and each frame reuses the latest reading. The stream keeps running while you are in another app and the overlay is only hidden, so switching back to Premiere shows it at once with the newest frame; app switches are noticed through macOS activation notifications rather than polling. Dragging the window moves the overlay with it; resizing restarts the stream (~250 ms) and takes a fresh reading. The legend's time is when the text was last read. While a run is active it uses the routine's own captures. Inside the style browser the routine likewise reads text once and scrolls or waits for your click on pixel-only looks, re-reading text every 1.5 s while it waits. Switch to another app to hide the overlay; return to Adobe to resume. No script or Accessibility permission is needed for observation; Screen Recording is required.

**Boxes**, **Text**, and **Details** independently control rectangles, recognized words, and classification/geometry labels plus the timestamp legend. **During runs** enables the same display only during automation when Always on is off. Preferences persist across app launches. Turning Always on off cancels its capture loop; there is no overlapping stream of passive captures.

### Detection master switch

Click **Detection: On/Off · F10** or press **F10** from any app while Edit Assist is running. This master switch stops passive captures and hides all inspection boxes and labels, including during routines. It retains Always on, During runs, Boxes, Text, and Details preferences. Turning it back on restores the configured mode; it does not start an editing routine. The shortcut is registered globally and consumed rather than forwarded to Premiere. Holding it toggles only once until released. If F10 is already reserved, the Detection bar reports that and the button still works. On keyboards using media keys by default, use Fn/Globe–F10.

### Workspace layout

Edit Assist is a set of **functions**, each a job it can do in your editor; **Highlight phrases** is the first. The sidebar lists your projects, then the functions with where each stands ("9 of 11 done", Running, Paused) and a ▶ quick start on the right (pause/continue while it runs). Clicking a project opens its **Project** page: its name, the editor and the script, which any function can use. A function's page holds only its own work, in two columns: **Task** on the left (the to-do list: phrase progress with per-phrase Redo) and **Setup** on the right (for Highlight phrases, the style picked last time and the font-size step, then the steps done for each phrase in order, then Diagnostics). Each function's sidebar row has its own progress bar along the bottom. The project name in the header opens the Project page, where it is edited. Assistant (the CLI conversation) and Settings sit at the bottom of the sidebar. The optional Context panel contains the screen capture and latest assistant decision.

Only one function runs at a time, so one **run bar**, just under the header, serves them all: the running function and its live status, a progress bar (counted in words, so a phrase split across clips moves it), the phrase count and, once something is done, the time left at this run's pace, then Pause/Continue, Stop and Run for the function on screen. Run is unavailable while any function is busy. To add a function: a case in `EditFunction` (Models.swift), a page in `ContentView.page(for:)`, a branch in `Store.start(_:)` and in `Store.progress(of:)`.

The header shows the connected editor and a compact Detection/F10 master control; its adjacent chevron opens observation and display settings. Pause keeps the same in-memory task and style lock, waiting at capture/input boundaries; a short in-flight gesture may complete first. Continue restores editor focus and continues that task without clearing progress. Keep the editor selection in place during a pause. Escape or Stop cancels the pass; manual input requests a pause. A validation error during a gesture can still stop the pass.
