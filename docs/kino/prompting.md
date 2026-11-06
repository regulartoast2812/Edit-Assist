# How to prompt in Kino

A reminder of how a shot's prompt works in Kino, and what Kling and Seedance want from it. The advice comes from the
services' own guides, gathered in [the Kling notes](kling.md) and [the Higgsfield notes](higgsfield.md) (as of 2026-11-06).

---

## 1. Name a file: type @

Type **@** in the prompt and the shot's files are listed. Pick one with **↑ ↓** and **Return** (or click it). It shows as
a pill with the file's name: `She walks toward camera in [K2.1]`.

- Only files in the shot can be named. Put a file in the shot first: drop it on the shot's files, or press **+ Add**.
- A tag typed out in full (`@K2.1` and a space) becomes a pill too.
- A tag in **red** names no file of this shot: a typo, or a file taken out.
- Backspace deletes a pill in one go. Copying the prompt gives the tags as text (`@K2.1`).
- **Escape** closes the list and keeps what you typed.

## 2. Give a file a role: type /

A file with no role goes to the model as a plain reference, and the model works out how to use it. To say exactly what
a file is for, type **/**, pick the role, then pick the file. `/start` **Return** **Return** is the quickest way.

| Command | Role | What the model does with the file | Files |
|---|---|---|---|
| `/start` | Start frame | The video opens on these exact pixels | picture |
| `/mid 2s` | Middle keyframe | The video passes through these exact pixels at that time (Kling 4.0 only) | picture |
| `/end` | End frame | The video lands on these exact pixels | picture |
| `/look` | Look | Takes its look (the product, a person, a place, a style), not its exact picture | picture |
| `/motion` | Camera and motion | Follows its camera path and pacing; its people, talking and place are not copied | video |
| `/edit` | Video to edit | Changes what the prompt says; keeps everything else | video |
| `/sound` | Sound | A sound or voice the video follows (Seedance only) | sound |
| `/out` | Left out | Not sent | any |

- The command stays in the prompt as one pill, `[Start · K2]`, and the file's picture shows the same role.
- **The prompt is the only place a role lives.** Delete the pill and the role goes. Picking a role on the picture (hover it,
  **Role ⌄**) writes its command at the start of the prompt; **No role** there takes it out.
- Commands are Kino's, not words for the model: they are never sent.
- A shot has one start frame and one end frame. Giving the role to another picture takes it from the first.
- The / list only shows roles the shot's files can take: with only pictures, there is no /motion or /edit.
- Other words work too: `/startframe`, `/first`, `/middle`, `/keyframe`, `/endframe`, `/last`, `/ref`, `/camera`, `/follow`, `/skip`.
- **Keyframes take their time first:** `/mid` **Return**, type `2s @`, pick the picture: `[Mid 2s · K3]`. Kling's API has no
  time field for a middle frame, so Kino writes the time into the prompt it sends. Only Kling 4.0 has keyframes: on
  another model /mid is listed as "Middle keyframe (Kling 4.0 only)", and its picture goes as a look (the card says
  so). Switch the shot to Kling 4.0 for a real keyframe.

**Start frame or look?** This is the choice people get wrong most often. A start or end frame is pixels on the timeline:
the video begins or ends on exactly that picture. A look only lends its traits. Use a start frame when the shot must open
on your photo; use a look when the product or person should appear but the framing is free.

## 3. What each model takes

| Input | Kling 4.0 | Kling O3 | Seedance 2.5 | In Kino |
|---|---|---|---|---|
| Start frame | ✓ | ✓ (no video in the shot) | ✓ | `/start` |
| End frame | ✓ | ✓ (no video in the shot) | ✓ | `/end` |
| Middle keyframes, at set times | ✓ (10 frames in all) | – | – | `/mid 2s` |
| Look pictures | ✓ up to 10 | ✓ up to 7 (4 with a video) | ✓ up to 30 | `/look` |
| Motion or camera video | ✓ up to 5 (30 s in all) | ✓ 1 | ✓ up to 10 | `/motion` |
| Video to edit | ✓ 1 | ✓ 1 | ✓ 1 | `/edit` |
| Sound files | ✗ voices only, no music or effects | ✗ | ✓ up to 10 | `/sound` |
| Saved subjects (Elements, Soul ID) | ✓ up to 7 | ✓ | – | not yet |
| Voices from Kling's library | ✓ up to 3 | – | – | not yet |

Motion Control is different: one picture of the person and one video of the performance, 3 to 30 s.

The shot's card says when something does not fit the model (too many pictures, a video too long), before anything is
sent.

## 4. Writing the prompt

### What to write

- **Describe, don't judge.** Write "side backlight outlines the jeans' seams", not "premium feel". (Kling)
- **Start with one sentence:** who, where, doing what, feeling what. Then add the camera, timing, sound and limits.
  Longer is not always better. (Kling)
- **With a start frame, write what happens, not what is there.** The picture already shows the scene: describe the
  movement, the camera and the timing. (Kling, Higgsfield)
- **Name the camera move in plain film words:** push in, pull back, pan, track, orbit, handheld follow, crane up, whip
  pan. Neither model has a camera setting any more; the prompt is the camera. (Kling, Seedance)
- **Seedance's order:** subject and action, then setting and lighting, then the camera move, then mood and style. (Higgsfield)
- **Say what you want, not what you don't.** Kling: only two negatives are really needed, **"no subtitles"** and
  **"no background music"**, because Kling 4.0 may add both on its own. More negatives can cause mistakes.
- **To keep a person or product the same:** "Keep the exact same woman, same face, same jeans; change only…". (Higgsfield)

### Editing a video

Use `/edit` on the video, then say what changes and what stays:

```
Edit [Edit · K4 O1]. Replace the pants with the ones in [K4 Size]. Same pattern, but bigger,
consistent through the whole video. Keep everything else unchanged.
```

Kling's own pattern is "Edit @Video1. Change ___ to ___. Keep everything else unchanged."

### Following a video's camera

Use `/motion`, and say what to take from it and what not:

```
Follow the camera path and pacing of [Motion · K3.1]. Don't carry over its people or place.
```

### Timing (Kling 4.0, up to 30 s)

Kling 4.0 plans its own cuts. To control them, write the shot as timed parts:

```
0–2 s: she holds the jeans up to the camera. 2–5 s: push in on the waistband as she
stretches it. 5 s–end: she smiles, pull back wide.
```

Dialogue goes in quotes, in the language it is spoken, with the speaker's age, tone and pace.

### Kling 4.0's full structure, for long shots

```
[Asset roles]       @K2 is the model; keep her face and the jeans the same. Follow the camera of @K3.1.
[Overall]           Scene and texture: ___. Visual style: ___. Camera tone: ___.
[Sequence]          0–X s: ___   X–Y s: ___   Y s–end: ___
[Audio]             Who says what; ambient sound; music; effects.
```

## 5. Habits that save takes

- **Change one thing per try,** so you know what made the difference. (Higgsfield)
- **Try short and cheap first:** a 5 s take at 720p to check the motion, then the same prompt at 1080p. (Higgsfield)
- **Don't contradict the picture:** if the start frame shows her standing, don't write "she sits". (Higgsfield)
- **Keep tags distinct:** names that contain each other (`@K1` and `@K1 Size` as words) or look like ordinary words can
  confuse the model. Kino's tags are the files' codes, which avoids most of this. (Kling)
- **Write it once for every shot:** what all shots share (the product's facts, the look) goes in **Every shot** at the
  top of the page, and is added to each prompt.
- **Chain shots:** a finished take can be dragged from Outputs onto a shot, to edit it or follow it there.
