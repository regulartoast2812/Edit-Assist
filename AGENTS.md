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
  browser, the scrollbar thumb back at its top position, or a reopened browser showing the top.
- **One kind of image per tracker sequence.** Screenshots and stream frames of the same screen differ
  (about 8 levels); the tracker treats a change of kind as a new reference.
- **Waits are tuned to Premiere's redraw.** Shortening one can make a capture land mid-redraw and
  expose another bug. Change waits deliberately, one at a time, and say which.
- Script wording, timings and unmarked text are never changed. Only the phrase range is styled.
