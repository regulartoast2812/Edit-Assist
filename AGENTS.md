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

**Where the Properties panel is**: `propertiesArea(in:image:)` bounds it by Premiere's black divider
lines around its tab (left, right, below), so it holds wherever the tab sits in its group and however the
panels are sized. Without the image it falls back to "from the tab to the window's edges", which once left
the whole panel out when Properties was the sixth tab (fixture 40).

**Know the panel, not a position.** `Desktop.propertiesState` says what the Properties panel shows
(nothing selected, caption, graphic text, style browser, unknown) from its text and the four-square
icon's shape right under its Track Style header. After a click that should change the panel, read
its state, and click again (at most three times) only if it still shows the old panel — a busy machine
can be slow or miss a click. Never re-click a remembered spot, and never click a shape found by
searching the whole panel: once the browser is open a style tile can look like the four-square, and
clicking it applies the wrong style to the selected text (this happened).

**Graphics** (Essential Graphics text, or a caption upgraded to one) have no Track Style. Selected as a
whole, Properties shows the layer list and Transform (`graphicLayers`); with its text being edited, the
text layer (`graphic`): Text, Appearance, Align and Transform, then **Linked style** far below, whose row
holds the four-square. The routine scrolls the panel down to Linked style to open the browser, and back up
to Font Size on the next phrase; it does not click a layer row (that could drop the word selection).
All of this belongs to **Highlight graphics** (`runOCR(graphics: true)`); every graphics rule in the
routine is behind that flag, so **Highlight phrases (captions) decides exactly as before**: a graphic is
not a selected caption (its fallback then selects the caption clip under the playhead), and it only clicks
the four-square under Track Style. Fixtures 33-37 (graphics), 38-39 (captions must ignore graphics).

## Invariants — each one was learned from a real failure

- **Never act outside caption text.** Timeline clip labels repeat caption words. Caption candidates
  must be well above interface text size, at least 65% of a caption height already seen, and, once
  a caption has been styled, inside the area captions appear in (the Program Monitor). There is no
  fallback to "the largest text" — that once dragged a clip over its neighbour and deleted it.
- **Never drag without the drag check.** Re-read the screen and drag only if the start point is in
  caption-sized text. A drag over a timeline clip moves it.
- **A phrase split across clips: step to the next edit point before matching the rest.** The rest
  cannot be on the screen just styled.
- **Selected = the Properties panel shows text controls** (C1: Subtitle, Track Style, Font Size, a
  Text section, or the style browser), not just the caption layout.
- **Style tiles: the position decides, the image confirms.** Presets come in near twins; the image is
  taken under the pointer's hover tint and can score a twin closer than the picked tile. At the
  remembered row and column, accept same colour and shape under 30. Colour is a hard gate.
- **The row counter is shared** by the routine, the teach step and the live overlay. A change for one
  must be checked in the others. It resets only on: the routine scrolling to the top, a fresh
  browser (two looks where text and pixels agree the list is gone, then it reappears), or the top
  measured on the frame itself — the scrollbar thumb level with the first full row and no partly
  hidden row above it. Panels are resizable: nothing may depend on geometry remembered from an
  earlier layout; a mid-session layout change marks the count lost.
- **One kind of image per tracker sequence.** Screenshots and stream frames of the same screen differ
  (about 8 levels); the tracker treats a change of kind as a new reference.
- **Waits are tuned to Premiere's redraw.** Shortening one can make a capture land mid-redraw and
  expose another bug. Change waits deliberately, one at a time, and say which.
- Script wording, timings and unmarked text are never changed. Only the phrase range is styled.
