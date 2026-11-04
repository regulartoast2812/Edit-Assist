# KlingDom Forge: what Kino can learn from it

Notes on the team's current generator (Kling and Seedance through Higgsfield), from a screenshot of its Studio view on
2026-11-04 (batch "Batch 1 (W1-September-2026)", product Easyshape Jeans). Read against the research in
[README.md](README.md), [kling.md](kling.md) and [higgsfield.md](higgsfield.md). Marked **[unsure]** where the screenshot
alone does not show what a control does.

## What is on screen

| Area | What it shows |
|---|---|
| Top bar | Account picker ("The Duc Nguyen", green dot), views **Thư viện** (library), **Flow**, **Studio**; icons for links, notifications, keys |
| Left: Input | The batch's files in tabs **Ảnh 33 / Element 0 / Video 56**, thumbnails named by shot code (K1, K1.1, K2 … K9, "K3 improve", "K9 ref") |
| Path | Account / product / batch, search "Tìm job, ảnh…", **▶ Chọn** (run selected) and **▶ Tất cả** (run all) |
| A job, open | Mode tabs **Omni / Video / Motion / Avatar**; results per run **×1–×4**; **Reference 3/4** with numbered images; an Elements drop zone ("kéo bộ vào đây", **Gắn**); one video attached by its file name (`hf_20260911_103632_…`, an earlier Higgsfield output); model picker (Kling 3.0 Omni, Seedance 2.5, Seedance 2); duration **Auto (~6 s)**; a second **Auto** setting **[unsure: aspect ratio?]**; prompt with an inline chip **K12**; **Audio** (off), **Giữ tiếng gốc** (keep original sound), **✦ AI** (prompt help), **Generate**; **Multi-shot + Shot**; a list Output 1–5 with edit and download |
| Jobs, closed | One line each: name, mode, inputs, quality, length, output count ("K2 · OMNI · 2 ẢNH + VIDEO · 1080P · AUTO · 5 OUTPUT"); green border **[unsure: done?]**; × to remove |
| Right: Preview (133) | **Output / Tất cả / Theo ô** (all, or grouped by job), **Download**; cards "Custom Output 1 · KLING 3.0 OMNI · ĐÃ XEM (seen)" with approve, bookmark, download; players at 0:00 with no picture |

## What works and should stay

1. **The structure matches how ads are made**: account → product → weekly batch → one job per shot (K1, K2…) →
   its outputs. Kino should keep this shape, and can tie it to Edit Assist's projects and script tabs.
2. **Shot codes as names.** Files are named K1, K2.1…, and the prompt uses them as chips (K12). One short name per
   file is exactly the single tagging syntax the map recommends (README §3).
3. **A one-line job summary** (mode · inputs · quality · length · outputs) makes 20 jobs scannable.
4. **Limits shown before you hit them**: "Reference 3/4" is Kling O3 on Higgsfield taking at most 4 images with a video.
5. **Batch runs** (run selected, run all) and **variations per run** (×1–×4).
6. **Outputs reused as inputs**: the attached video is an earlier generation.
7. **A review pass**: seen markers, approve, bookmark, grouped by job, download.
8. **Mode tabs that match the services' modes**: Omni (references or edit), Video (frames), Motion (Motion Control),
   Avatar (talking photo).

## What to fix (each tied to what the research found)

### Inputs and the prompt
1. **Files have no role.** References 1–3 are only numbered, and the prompt says "this one". Is image 1 the product,
   image 2 a detail, image 3 a fit? The services guess when the role is not said (README §2: "the model will infer how
   to use it"). Give every attached file a role (start frame, look, motion, video to edit…) and write the role lines into
   the prompt automatically.
2. **Edit or reference is left to chance.** With a video attached, Kling O3 has two different endpoints on Higgsfield,
   `kling-video/o3/video-edit` and `kling-video/o3/video-reference`, and on Kling the word "Edit" picks the pipeline.
   "Replace the pants in the video" is an edit; the tool should say so in the request and the prompt ("Edit @K12…
   keep everything else unchanged").
3. **Two naming systems**: images by number (1, 2, 3), the video by file name, the prompt by code (K12). Use the code
   everywhere: the reference thumbnails, the video chip, the prompt. The raw `hf_2026…` name tells nobody which clip it
   is; show its thumbnail, length and the job it came from.
4. **Product facts typed into every prompt** ("Smooth waistband, Metal buckle, Clear Fibre texture"). Keep them once
   on the product (with its reference images) and insert them; Don's brief can fill the look the same way.
5. **Elements are empty (0).** For a product ad the product is the thing to keep identical across shots. Kling can
   save it as an element (2–4 images or a 3–8 s clip), Higgsfield passes Kling element ids but cannot create them, and
   Seedance takes up to 30 reference images instead. Make "the product" a saved subject.

### Models and settings
6. **Switching model should change the form.** Kling 3.0 Omni and Seedance 2.5 accept different inputs (4 vs 30
   images, 1 vs 10 videos, audio references only on Seedance) and settings. The counter, the fields and the warnings
   should follow the chosen model, and show what would be dropped when switching.
7. **Combinations the model refuses**: on Kling 3.0 Omni an edit video rules out multi-shot and native sound (kling.md
   §2.5). Multi-shot and Audio should turn off, with the reason, when a video to edit is attached.
8. **The model list is short.** Kling 4.0 (10 keyframes, 15 references, 30 s) is out on Kling's API and listed on
   Higgsfield's; offer it as soon as Higgsfield documents its fields, or call Kling directly.

### Running and cost
9. **No cost before "Run all"** **[unsure: a hidden field near the model picker may be a price]**. With 133 outputs in
   one batch, show the cost per job and the batch total before running (Higgsfield's `POST /estimate`), and what was
   spent after.
10. **Job state needs words.** A green border is not enough: show queued, running, failed (with the reason),
    blocked by moderation (refunded on Higgsfield), and retry. Send an `Idempotency-Key` so a double click never pays
    twice.

### Results and review
11. **Results expire.** Higgsfield deletes outputs 7 days after they finish, and this batch is from September. The
    players showing nothing may be expired links **[unsure]**. Download every output when it finishes, to the batch's
    folder, named by job and variant.
12. **Previews need pictures.** Show a still from each output, scrub on hover, and compare an output beside its
    source video at the same moment, which is how an edit like "replace the pants" is judged.
13. **Outputs need a history.** "Custom Output 1" says nothing. Each output should carry its job, variant, model,
    settings and the exact prompt that made it, so a good one can be re-run or varied, and a bad one traced.
14. **Approved outputs should go to the edit.** Approve → the clip lands in the Premiere project's folder under its
    shot code. That is where Kino and Edit Assist meet (Amir already watches folders).

### Batches
15. **Twenty similar jobs.** K1–K9 share most of their prompt and settings. A batch-level shared prompt and settings,
    with per-job changes only, saves retyping and keeps the batch consistent.

## Open questions about Forge

- What the green job border, the second **Auto** setting and the hidden field next to the model mean.
- How **Avatar** runs: Higgsfield's API has no talking-photo or lip-sync model (higgsfield.md §5.8), so that tab
  presumably uses Kling directly or the web.
- What **Flow** and **Thư viện** do, and whether Forge stores outputs anywhere after Higgsfield's 7 days.
- Whether **✦ AI** rewrites the prompt, and with what.

## What Kino adds: four jobs Forge leaves to you

Asked for on 2026-11-04. Each job lists how it works and the service limits it has to respect.

### 1. Files join a prompt by their shot code
- K1.1, K1.2 and K1.3 belong to shot K1: Kino groups files by the number before the dot and puts all of them into
  K1's one prompt, each under its own tag (`@K1.1`). Words after the code ("K3 improve", "K9 ref") are labels, not new
  shots.
- The tags stay the same on screen. When sending, Kino translates them to each service's syntax (Kling 4.0 custom
  `@id`s, Higgsfield's field order or `<<<image_n>>>`; README §3).
- A group bigger than the chosen model takes is flagged before running. For example, Kling O3 on Higgsfield takes 4
  images and exactly 1 video; Seedance 2.5 takes 30 images and 10 videos.

### 2. The script drives the prompt and the tags
- From the AI video script, Kino reads each shot's line and matches it to that shot's files.
- He gives each file a role: start frame, end frame, product, look, motion or camera, video to edit.
- He writes the prompt in the shape each service teaches (Kling 4.0: overall settings, then events by time;
  Higgsfield: style, camera, lighting, action beat by beat). Each prompt names every file's role and inserts the
  product's facts.
- An edit is written as an edit ("Edit @K12: replace the pants… keep everything else unchanged") and sent to the edit
  endpoint.
- You review and change it before anything runs.

### 3. Reading reference videos and cutting the useful part
- **Find the takes.** A long reference is split at its cuts, since Kling's motion source must be one continuous take.
- **Describe each take:** camera move, action, who is in it, whether someone talks. This uses stills for the
  configured AI plus on-device checks: Vision's lip landmarks (already used by PeopleReader) for a moving mouth, and the
  audio for speech.
- **Match and cut.** Takes are matched to the shots that need them. The best part is cut to the service's limits:
  - Kling 4.0: 3–30 s each, 5 videos at most, 30 s in total.
  - Kling O3 on Higgsfield: 3–15.5 s, 1 video.
  - MP4 only for Higgsfield uploads.
- **File the cut.** Each cut is saved as the next code (K4.2), with the source and timecodes it came from, so it can
  be recut.

### 4. Prompting from a reference without copying what you don't want
Reference videos are often a person talking to camera. Kino keeps the part you want, such as the camera move, pacing,
body movement or product handling, and leaves the talking out. He does this in four ways:
- **Cut around it:** prefer takes with no speech and a still mouth (job 3).
- **Remove the sound from the cut before upload.** On Kling, speech in a video element binds a voice, and Kling 3.0
  allows no native audio with a reference video anyway. Motion Control's `keep_original_sound` stays off.
- **Use the right slot:**
  - a motion or camera reference (`feature_video`), not a video to edit;
  - a still frame, when only the look matters;
  - words alone, when only the action matters.

  Motion Control copies the whole performance, the mouth included, so it gets only takes without talking.
- **Say what to take.** Each prompt says what to take from the reference and states the wanted action positively,
  with one targeted exclusion. Kling's guide does this ("Reference the camera path and pacing of @video_1… do not carry
  over its people or scene"), and Higgsfield's advice is to say what you want, with a few targeted "no" phrases. For
  example: "Follow only the camera path and pacing of @K4.2. She holds the jeans up to camera, lips closed, smiling; no
  talking."
