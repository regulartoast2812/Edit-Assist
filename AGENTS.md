# Working on Edit Assist

Edit Assist drives Premiere Pro by reading the screen (OCR + pixels) and sending mouse and keyboard
input. A wrong decision is not a crash: it is a click, double-click or drag in the user's project.
Treat every change to decision logic as a change to what happens in their timeline.

## Before you finish any change

1. `./build.sh` — it runs `./test.sh` first and installs nothing if a check fails or a recorded
   decision replays differently. Do not use `--skip-tests` without saying so to the user.
2. Report which files you changed and whether any of it is **automation** (Desktop.swift,
   LiveFeed.swift, Store.swift's run/doTile/doSize/doOpen/navigation code) or **UI only**
   (App.swift, Overlay.swift drawing, Models.swift labels). A UI request does not touch automation;
   if it must, say so before doing it.

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
