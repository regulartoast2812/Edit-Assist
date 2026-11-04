# Higgsfield AI — research map for Kino

**As of: 2026-11-04.** Everything below was checked on the live web that day. Each fact or table is followed by its source.

**What the source labels mean**
- **[official-docs]**: the API docs at docs.higgsfield.ai (Mintlify; each page is also served as Markdown).
- **[official-help]**: the Creator Hub help center (higgsfield.ai/creator-hub/help-center/…, also served as `.md`) or the Enterprise help center (higgsfield.ai/enterprise-help-center/…, also served as `.md`; its articles are dated 2026-11-01).
- **[official-changelog]**: https://higgsfield.ai/creator-hub/changelog (RSS: https://higgsfield.ai/creator-hub/changelog/rss.xml).
- **[official-site]**: higgsfield.ai marketing pages, higgsfield.ai/llms.txt, and open.higgsfield.ai (the API console).
- **[official-github]**: github.com/higgsfield-ai/skills, the official agent skills for the Higgsfield CLI, v0.14.0, last pushed 2026-10-27.
- **[3rd-party]**: anything else. Treat it as unconfirmed.

**Higgsfield has two separate products.** The rest of this map depends on that split.
1. **The web app / "plan" product** (higgsfield.ai). It runs on a subscription plus credits and has the full model lineup: Veo, Sora 2, Nano Banana, Kling 4.0, DoP presets and so on. The MCP server, CLI, plugins, Canvas and Supercomputer all spend these plan credits.
2. **The Higgsfield API** (api.higgsfield.ai, with its console at open.higgsfield.ai / console.higgsfield.ai). It needs a separate account and a prepaid USD balance, uses key ID + secret auth, and has **its own curated catalog that differs from the web app**. The docs list 84 entries: 17 image and 67 video.
   - Source: https://higgsfield.ai/creator-hub/help-center/integrations/what-is-the-higgsfield-api [official-help]
   - Source: https://docs.higgsfield.ai/docs/models.md [official-docs]

---

## 0. Key takeaways for Kino

1. **For a native macOS app, the API is the only sanctioned programmatic route.**
   - The MCP server and CLI log in to a *user's* web account through OAuth or a browser login. They fall under the "Developer Terms", and every generation spends credits. "Unlimited" plans never apply to them.
   - The API is pay-per-generation in USD and is completely separate from plans.
   - Sources: https://higgsfield.ai/creator-hub/help-center/integrations/what-is-higgsfield-mcp, https://higgsfield.ai/creator-hub/help-center/integrations/how-do-i-access-higgsfield-via-cli [official-help]
2. **The API has no Veo, Sora, Nano Banana, GPT Image or Seedream, and no DoP camera-preset endpoint is documented.**
   - The API docs catalog has: Genjutsu, Seedance 2.0/2.5, Kling 2.5 Turbo/2.6/3.0/O3/Omni plus Motion Control, HappyHorse, Wan 2.6/2.7/3.0/3.0 Prime, Cinema Studio 4.0, LTX-2.5, MiniMax H3, Hailuo 2.3, PixVerse V6 and Grok Video 1.5. On the image side: SOUL/SOUL V2/SOUL Cinema plus Soul ID training, Marketing Studio Image, Ads Studio, Grok Image 2, Recraft, Qwen Image 3, Ideogram 4 and Z-Image.
   - The API console additionally lists **Kling 4.0**, which has no workflow page in the docs yet.
   - Sources: https://docs.higgsfield.ai/docs/models/video-generation.md, https://docs.higgsfield.ai/docs/models/image-generation.md [official-docs]; https://open.higgsfield.ai/pricing [official-site]
3. **The API does not take raw file bytes on generation calls; every input is a public HTTPS URL.**
   - Upload flow: call `POST /files/generate-upload-url`, `PUT` the bytes to the presigned URL, then pass the returned `public_url` in `image_url`, `video_url`, `audio_url`, `image_urls` and so on.
   - Supported upload types are JPEG, PNG, WebP and GIF images; WAV audio; and MP4 video.
   - Source: https://docs.higgsfield.ai/docs/concepts/file-uploads.md [official-docs]
4. **References are tagged differently depending on where you work:**
   - **Web app Elements:** `@tag`, for example `@char_hero_v1`.
   - **Cinema Studio 4.0 API:** positional tokens `<<<image_1>>>`, `<<<video_1>>>` and `<<<audio_1>>>`.
   - **Seedance-style reference roles:** described in prose at the start of the prompt.
   - **Popcorn:** "image one", "image three" and so on.
   - **Kling:** a directly connected image is a *start frame*, not a character reference.
   - Kino needs one tagging model that maps to each of these. See §3.
5. **The lifecycle is uniform across every API model:** submit → `queued` → `in_progress` → `completed | failed | nsfw | canceled`.
   - Use polling with backoff from 2 s up to 10 s, or Standard-Webhooks-signed webhooks.
   - Outputs expire **7 days** after the request finishes.
   - Failed and NSFW requests are refunded.
   - Source: https://docs.higgsfield.ai/docs/concepts/requests.md [official-docs]

---

## 1. What Higgsfield is

Higgsfield describes itself as an "AI-native creative suite". It combines its own models and tools (Soul, Soul ID, Cinema Studio, Marketing Studio, Canvas, Supercomputer, DoP, Popcorn, Genjutsu) with a library of third-party models under one subscription. Its marketing copy claims "30+ models" and "25 million users".
- Source: https://higgsfield.ai/creator-hub/help-center/getting-started/what-is-higgsfield [official-help]
- Source: https://higgsfield.ai [official-site]

The company is Higgsfield, Inc., 535 Mission St, 14th floor, San Francisco. There are no native mobile or desktop apps; it runs in the browser only.
- Source: https://higgsfield.ai/creator-hub/help-center/getting-started/official-higgsfield-platforms [official-help]

### 1.1 Higgsfield's own models

| Model | Type | What it is for | Key specs (confirmed) | Source |
|---|---|---|---|---|
| **Soul** (v1, "Soul Standard") | Image | Quick generation driven by presets. Preset categories: General, TikTok Core, Instagram Aesthetics, Beauty, Mood, Camera Photo, Graphic Art | API: aspect ratios 9:16 / 16:9 / 4:3 / 3:4 / 1:1 / 2:3 / 3:2; 720p or 1080p; batch 1 or 4; `style_id` + `style_strength` | help: …/ai-models/how-do-i-use-soul-to-generate-images; docs: …/models/soul-standard/generate.md |
| **Soul 2.0** | Image | Photoreal fashion, editorial and people images. Supports presets, Moodboards, Soul HEX color, Soul ID and a reference image | Web: quality 1.5k / 2k, batch 1–4, 7 aspect ratios. Attaching a reference image disables the prompt field. API `higgsfield-ai/soul/v2/standard`: `style_strength` is accepted but has no effect | same + docs …/soul-2/generate.md |
| **Soul Cinema** | Image | Cinematic stills and keyframes for video. Style is built in, with no presets or Moodboards | Soul HEX and Soul ID supported. CLI note: adds 21:9 | help …/how-do-i-use-soul-cinema; docs …/soul-cinema/generate.md |
| **Soul ID** | Character training | Trains one person's identity once and reuses it across the Soul family; it carries over to video as an Element | Web: train on 20+ photos (up to 80), takes "a few minutes". API: 1–100 images, `model_version` v1 / v2 / cinema | help …/how-do-i-create-and-use-a-soul-id-character; docs …/soul-id/create-character.md |
| Soul Cast / AI Cast | Image (AI actors) | Builds an actor by genre, era, archetype and appearance | CLI note: text only, 16:9 only | changelog 2026-03-10; github model-catalog.md |
| Soul Location | Image | Locations without people | Prompt only, fixed dimensions per aspect ratio (CLI) | github model-catalog.md |
| **Higgsfield DoP** ("Director of Photography"; shows as **Higgsfield Standard** in the model picker) | Image→video | Turns one keyframe into a cinematic shot driven by a **motion preset** | Durations 3 or 5 s; Advanced settings: seed, steps; **Mix** combines presets; Enhance toggle | help …/ai-models/how-do-i-use-dop |
| **Cinema Studio** 2.0 / 2.5 / 3.0 / 3.5 / **4.0** | Video (tool + model) | Film-studio workflow. **4.0 runs on Seedance 2.5** | 4.0: up to 50 references, clips up to 30 s, Director's Panel. 3.0: up to 9 references. Uploaded video length: 2.5 none, 3.0/3.5 ≤15 s, 4.0 ≤30 s | help …/tools/how-do-i-use-cinema-studio |
| **Popcorn** | Image (storyboard) | Coherent sequences of up to 8 frames; Manual, Auto and Instadump modes | Up to 4 image references, referred to by number; aspect ratios 3:4, 2:3, 3:2, 4:3, 16:9, 1:1, 9:16 or Auto | help …/ai-models/how-do-i-use-popcorn |
| **Genjutsu** / Genjutsu Lite | Video→video | Motion Transfer, Objects Swap, Restyle (keeps motion, timing and camera) | Web: source clip 4–30 s, up to 30 reference images, 480p / 720p / 1080p. Lite: 4–15 s, ≤10 images, 720p / 1080p | help …/tools/how-do-i-use-genjutsu; changelog 2026-10-19 |
| Higgsfield Speak 2.0 | Talking avatar | Image + audio → talking clip (Lipsync Studio) | "Priority-queue speed" | help …/how-do-i-use-lipsync-voiceover-and-aspect-ratios |
| **Higgsfield Intone** | Talking character | Character + location + speech → lip-synced video with the same voice across scenes | Speech ≤30 s per generation; 720p / 1080p; 5 aspect ratios; `[smirks]`-style cues in square brackets | changelog 2026-10-30 |
| Marketing Studio (Image / Video) | Ads | Template-first ads; avatars, products, hooks | Video modes: `ugc`, `ugc_how_to`, `ugc_unboxing`, `product_showcase`, `product_review`, `tv_spot`, `wild_card`, `ugc_virtual_try_on`, `virtual_try_on` (CLI); 480p / 720p / 1080p | help …/how-do-i-use-marketing-studio…; github SKILL.md |
| 3D Jutsu | 3D scene → video | Editable 3D scene (objects, lights, cameras) → video | — | changelog 2026-09-04 |
| Virality Predictor (`brain_activity`) | Video analysis | Scores the hook, attention and retention of a finished video | Video in, text report out | github SKILL.md |

Full help URLs use the prefix `https://higgsfield.ai/creator-hub/help-center/`. Docs URLs use the prefix `https://docs.higgsfield.ai/docs/models/`.

### 1.2 Third-party video models on the web app

The help center's guidance on choosing a model:
- DoP for VFX and camera work.
- Seedance for realistic human motion.
- Kling for stylized, long or multi-shot video.
- Wan for first- and last-frame control.
- Grok Imagine for synced audio.
- Sora (OpenAI) and Veo (Google).
- MiniMax Hailuo for fast, high-dynamic motion.

Source: https://higgsfield.ai/creator-hub/help-center/ai-models/which-ai-model-should-i-use [official-help]

| Model (web) | Duration | Resolution | Aspect ratios | Audio | Inputs / notes | Source |
|---|---|---|---|---|---|---|
| **Seedance 2.5** | 4–30 s | Up to 1080p on Pro/Plus plans and above (see §8 for a conflict) | "any aspect ratio from 9:16 to 21:9" | Native, generated in the same pass | Up to 50 refs (30 images, 10 videos, 10 audio). Region-level edits in **Seedance 2.5 Edit**. **Draft Mode**: 480p previews, then re-render the chosen take at 1080p (not available in the US) | help …/how-do-i-use-seedance; changelog 2026-08-06, 2026-09-22 |
| Seedance 2.5 Edit | Matches source | 480p–720p | — | Edits audio too | Edits an existing clip; you can mark the region to change on the frame | help …/how-do-i-use-seedance |
| **Seedance 2.0** | 4–15 s | 480p–4K | auto, 21:9, 16:9, 4:3, 1:1, 3:4, 9:16 | Native | Up to 9 images + 3 videos + 3 audio files; bitrate Standard/High (High costs the same credits but makes larger files) | help …/how-do-i-use-seedance; changelog 2026-06-19/21; github model-catalog |
| Seedance 2.0 Fast / Mini | 4–15 s | 480p–720p | — | — | For iteration | help …/how-do-i-use-seedance |
| Seedance 1.5 Pro, Pro, Pro Fast | — | — | — | — | Older models, under "All models" | same |
| **Kling 4.0** (new 2026-10-21) | 3–30 s | 720p / 1080p | 21:9 → 9:16 | Stereo, voiceover in 9 languages | **Up to 10 keyframes**; up to 15 references (images, up to 5 videos, a voice reference, Elements); "Creative Recreation" mode; video editing (swap character, product, background, camera angle or style). Tabs: References / Frames / Edit video | changelog 2026-10-21 |
| Kling 3.0 | 3–15 s | Up to 4K | 16:9, 9:16, 1:1 | Native | Multi-shot scenes; start and end frames; Elements; genres (General, Action, Horror, Comedy, Noir, Drama, Epic); speed ramps (Linear, Auto, Flash In/Out, Slow-mo, Bullet Time, Impact, Ramp Up) | help …/how-do-i-use-kling |
| Kling 3.0 Turbo | 3–15 s | Up to 1080p | 16:9, 9:16, 1:1 | — | For drafts | help …/how-do-i-use-kling; github |
| Kling 3.0 Omni / Omni Edit | 3–15 s / 3–10 s | 4K / 1080p | — | Omni: native | Generation and editing in one model | help …/how-do-i-use-kling |
| Kling 3.0 Motion Control, Kling Motion Control | 3–30 s | 1080p | — | — | Character image + motion reference video | same |
| Kling 2.6, O1 Video / O1 Edit, 2.5 Turbo, 2.1, 2.1 Master | 5–10 s (O1 Edit 3–10 s) | 1080p | — | 2.6: native | Older models | same |
| **Veo 3.1** (Google) | 4, 6 or 8 s | Landing page says 720p / 1080p at 24 fps; the changelog says 4K was added 2026-01-24 | 16:9, 9:16 | Dialogue and lip sync (Standard) | Modes: text-to-video; start + end frame (2 images, Fast); multi-image reference (1–3 images, Standard). CLI: quality basic / high / ultra; `start_image` max 1 | https://higgsfield.ai/veo3.1; changelog 2026-01-24; github |
| Veo 3.1 Lite / Veo 3 | — | — | — | — | Lite: "fast, cost-effective" | changelog 2026-04-06; github |
| **Sora 2** (OpenAI) | **not stated** | 480p, 720p, 1080p | — | Synchronized sound | Reference image + scenario prompt | https://higgsfield.ai/sora-2 |
| Wan 3.0 / 3.0 Prime | Up to 30 s | 480p / 720p / 1080p | — | Synced | Multi-subject consistency; Prime is faster and costs more | changelog 2026-08-24 |
| Wan 2.7, 2.6, 2.5 | — | 2.7: 1080p | — | 2.5 / 2.7: audio | 2.7 adds frame control | changelog 2026-04-06; help |
| Grok Imagine Video 1.5 (xAI) | 1–15 s | 480p / 720p / 1080p, 24 fps | — | Native | Image→video, text→video, reference→video (≤7 images), **video extension** | changelog 2026-10-01 |
| Gemini Omni Flash / Omni 1.1 Flash (Google) | ≤10 s | 360p draft / 720p / 1080p / 4K | — | Native | First + last frame; edit mode | changelog 2026-06-29, 2026-08-28 |
| MiniMax H3 / H3 Max, Hailuo 2.3 | H3 up to 15 s (API) | H3: 2K; H3 Max: up to 768p | — | H3: dialogue and SFX; Hailuo: none | H3 combines character images, motion references and audio | changelog 2026-08-31; ehc ai-models |
| HappyHorse (Alibaba) | — | — | — | Native | Multi-shot | changelog 2026-04-27 |
| FLUX 3 Video / Video Edit | — | — | — | Native (help) | — | help lipsync article; github |

### 1.3 Third-party image models on the web app

Nano Banana Pro, Nano Banana 2 / 2.1 / 2 Lite, Nano Banana (edit), GPT Image 1.5 / 2 / 2.5 (Flare, Sunburst), Seedream 4.5 / 5.0 Lite / 5.0 Pro / 5.0 Flash, FLUX 2 / FLUX 3 Image / Flux Kontext Max, Recraft V4 Styles / V4.1 / V4.1 Utility, Ideogram 4.0 / 4.5 / 4.5 Precise Edit / Vector 1.0 (SVG), Grok Imagine Image, Kling O1 Image, Z-Image, Qwen Image, and "Auto" (routes to the best model).
- Sources: https://higgsfield.ai/llms.txt, changelog, and https://github.com/higgsfield-ai/skills/blob/main/higgsfield-generate/references/model-catalog.md

| Nano Banana family (web) | Best for | Max references | Notes | Source |
|---|---|---|---|---|
| Nano Banana Pro | Complex scenes; reasons about the prompt before rendering | 14 | Native 4K; input modes Text-to-Image / Multi-reference / Image-to-Image | help …/how-do-i-use-nano-banana |
| Nano Banana 2 (2.1 since 2026-10-06) | Fast bulk generation | 14 | Up to 5 consistent characters + 14 objects; up to 4K | same; changelog 2026-10-06 |
| Nano Banana 2 Lite | Volume drafts | 14 | About 4 s per image, 1K; a Thinking level (High/Minimal) replaces the resolution setting | same |
| Nano Banana | Edits by instruction, text on images | 8 | JPG / PNG / WebP refs | same |

### 1.4 Audio on the web app

- **Audio tab** modes: Text to Speech, Voice Change, Translate (18 languages).
- **Voices:** voice presets, or custom voice cloning from an MP3 or WAV sample.
- **Audio models:** Seed Audio 1.0 (speech + SFX + music in one track), Eleven v4 (90+ languages, 10,000 characters per generation), MiniMax Speech, Seed Speech, VibeVoice, Qwen, plus Sonilo Music and Mirelo SFX.

Sources: https://higgsfield.ai/creator-hub/help-center/ai-models/how-do-i-use-lipsync-voiceover-and-aspect-ratios and https://higgsfield.ai/creator-hub/help-center/ai-models/which-ai-model-should-i-use [official-help]; changelog 2026-09-28 [official-changelog]; github model-catalog [official-github]

### 1.5 Models with native audio (generated in the same pass)

Seedance 2.5, Seedance 2.0, Kling 3.0, Kling 2.6, Kling 4.0, Flux 3, MiniMax Hailuo 3.0, Wan 2.5, Grok Imagine, Veo 3.1, Sora 2, and Cinema Studio (all versions).
- Source: help …/how-do-i-use-lipsync-voiceover-and-aspect-ratios; model landing pages and changelog.

---

## 2. Products, generation modes and tools (web app)

**Top navigation** (as of 2026-11-04): Explore, Image, Video, Audio, MCP, API, Genjutsu, Shorts, Content Factory, Playable, Mangaka, AI Influencer, Academy, Katana, ChatGPT Plugin, Ads Studio, Effects, Cinema Studio, Contests, Marketing Studio, Supercomputer, Edit, Community, Plugins, Canvas, Originals, Enterprise, Pricing.
- Source: https://higgsfield.ai/pricing (navigation HTML) [official-site]

### 2.1 Basic Create Image / Create Video

The basic flow:
1. Choose **Image** or **Video**.
2. Pick a model or feature.
3. Write a prompt.
4. Optionally upload a reference.
5. Set duration, aspect ratio and resolution.
6. Click **Generate**. The **credit cost is always shown on the Generate button** before you confirm.

The result appears in that section and in **Assets**. Typical time is "usually a few minutes". Enterprise help says most jobs finish in 30 s–10 min, and heavy video models take about 15–20 min.
- Sources: https://higgsfield.ai/creator-hub/help-center/getting-started/how-do-i-create-my-first-generation; https://higgsfield.ai/enterprise-help-center/support/issues [official-help]

Aspect ratio is set per generation. Some models offer **Auto**, which infers the ratio from the input image. To change the ratio of a finished video, use **Reframe**; to change an image's ratio, use **Expand** (outpaint).
- Source: help …/how-do-i-use-lipsync-voiceover-and-aspect-ratios

### 2.2 Camera motion presets (DoP), Motion Library, Effects, Viral Presets

**DoP preset browser.** Categories are **Effects**, **Basic Camera Control**, **Epic Camera Control** and **Catch the Pulse**, plus the **New** and **Trending** feeds. **Top Choice** marks curated presets.
- **Mix** combines presets in one generation.
- Prompt plus **Enhance** toggle (expands the prompt).
- Advanced settings: duration 3 or 5 s, seed, steps.
- Source: https://higgsfield.ai/creator-hub/help-center/ai-models/how-do-i-use-dop [official-help]

The original launch post says Mix combines **two** motion templates, and a later post says "2+".
- Source: https://higgsfield.ai/blog/Introducing-Higgsfield-Mix-Motion-Reimagined [official-site, older]

**Motion strength slider:** the web UI could not be confirmed. The legacy v1 API docs (now 404) used `motions: [{id, strength}]` with an example of 0.5, and a third party lists strength 0–1. See §8.

**Motion Library** (https://higgsfield.ai/motion, sitemap https://higgsfield.ai/motion/sitemap.xml) has **419 public preset pages**. Each page title names the engine that renders it:

| Engine | Presets |
|---|---|
| Higgsfield | 229 |
| MiniMax Hailuo | 77 |
| Kling | 56 |
| Seedance | 25 |
| WAN 2.2 | 17 |
| WAN 2.5 | 15 |

The same preset name often exists for several engines. Combined presets appear as "A + B" names, for example "Crash Zoom In + Face Punch", "Lazy Susan + Super Dolly Out", "FPV Drone + Timelapse Landscape", "Thunder God + Levitation".
- Source: page titles fetched from the motion sitemap [official-site]

**Camera-move preset names** in the library:
- **Movement:** 360 Orbit, 3D Rotation, Aerial Pull Out / Pullback, Arc Left / Right, Bullet Time, Car Grip, Car Mount, Crane Down / Up, Crane Over The Head, Crash Zoom In / Out, Dolly In / Out / Left / Right, Dolly Zoom In / Out, Double Dolly, Downhill POV, Dutch Angle, Eyes In, Fisheye, Flying Cam Transition, Focus Change, FPV Drone, Free Cam, Handheld, Head Tracking, Hero Cam, Hyperlapse, Incline, Jib Up / Down, Lazy Susan, Low Shutter, Mouth In, Object POV, Overhead, Pan Left / Right, Push To Glass, Rapid Zoom In / Out, Robo Arm, Snorricam, Static, Super Dolly In / Out, Through Object In / Out, Tilt Up / Down, Timelapse (Glam / Human / Landscape), Whip Pan, Wiggle, YoYo Zoom, Zoom In / Out.
- **Effect presets** (examples): Disintegration, Set on Fire, Turning Metal, Melting, Levitation, Thunder God, Datamosh, Portal, Clone Explosion, Raven Transition, Northern Lights.
- Source: motion sitemap pages [official-site]

**Effects / "Viral Presets"** (https://higgsfield.ai/effects; 87 example pages at https://higgsfield.ai/effects/sitemap.xml) are trend formats such as Floating fall, Eyes in, Wild ride, Agamemnon, Earth zoom, Fallen angel, Bullet time, Infinite clones and Vanish.
- **Input:** a photo or a video. **Aspect ratios:** 16:9, 1:1 or 9:16. Cost depends on the preset and is shown before you generate.
- **Effects 2.0** is also available as `/effects` inside ChatGPT.
- Sources: changelog 2026-05-15 and 2026-09-10 [official-changelog]

**Model-native camera controls**, distinct from presets:
- **LTX-2.5 API:** `camera_movement` enum `dolly_in`, `dolly_out`, `dolly_left`, `dolly_right`, `jib_up`, `jib_down`, `static`, `focus_shift` (see Appendix A).
- **Cinema Studio 4.0:** 33 camera movements (Appendix A).
- **Seedance** reads camera terms from the prompt: dolly in, truck left, arc shot, push in, pull back wide, handheld follow, crane up, orbital move.
- Source: help …/how-do-i-use-seedance

### 2.3 Cinema Studio (tool; 4.0 is the default)

Cinema Studio has its own workspace (since 2026-06-07) organized into **projects**. Each project holds the brief, references, Elements, generations and team. The version selector at the top switches between 2.0 and 4.0. Version 4.0 runs on Seedance 2.5.
- Sources: https://higgsfield.ai/creator-hub/help-center/tools/how-do-i-use-cinema-studio; https://higgsfield.ai/enterprise-help-center/platform/tools-creative-workflow; changelog 2026-06-07

**Cinema Studio 4.0 Director's Panel:**

| Control | Values on the web | API enum (`higgsfield/cinema-studio/4.0`) |
|---|---|---|
| Film Setup: genre | General, Action, Epic, Drama, Comedy, Horror, Noir | `genre`: epic / drama / noir / comedy / horror / action (no "general"; leave it out to get auto) |
| Film Setup: era | "from the 60s to the 2020s" | `era`: 1960s / 1980s / 1990s / 2000s / 2020s |
| Film Setup: tempo | From Single Shot to Chaotic (cut speed) | `pacing`: chaotic / dynamic / calm / single-shot |
| Camera body | Includes 35mm Film, 8mm Film, DV Camcorder ("4 camera types") | `camera_model`: modern / 35mm-film / 8mm-film / dv-camcorder |
| Lens | Clean sharp → anamorphic / vintage ("5-lens system") | `camera_lens`: clean-sharp / anamorphic / vintage-anamorphic / warm-vintage / halation-vintage |
| Aperture | — | `camera_aperture`: f14-wide-open / f4-moderate / f11-deep-focus |
| Camera move | 30+ presets including POV, Robot Arm, Helicopter Shot | `camera_movement`: 33 values (Appendix A) |
| Color Palette | 50+ grading templates | `color_palette`: 50 named slugs (Appendix A) |
| Lighting | 6 presets, or custom (color, brightness, diffusion, angle; "two light sources" per EHC) | `light`: silhouette / practicals / window / overhead-fall / contre-jour / soft-cross |
| Emotion | Emotion Wheel or slider (8+ emotions; EHC says "six emotions, three intensities") | not exposed in the API |
| Modes | References (new clip), Forward / Backward Extend (upload ≤30 s), Edit Video (regional) | API covers generation only; editing and extension go to the Seedance 2.5 endpoints |

Sources: help …/how-do-i-use-cinema-studio; changelog 2026-08-12; https://docs.higgsfield.ai/docs/models/cinema-studio-4/generate.md

**Earlier versions:**
- **2.5:** up to 3 Soul Cast characters; Colorgrade post-step with temperature, contrast, saturation, sharpness, grain, highlights and exposure.
- **3.0:** up to 9 references, a reasoning engine, genres and speed ramps.
- **3.5:** "Claude Chat AI Director" (adjusts Genre, Style and Camera and breaks a script into shots, but **never triggers generation itself**), the Elements system, and shared projects. Per-shot camera settings sit alongside global settings: 8 palettes, 10 "Camera MoveSet" styles and 6 lighting presets.
- Source: help …/how-do-i-use-cinema-studio

**Project tools:**
- **Tools → Canvas / Chat / AI Director.** The AI Director uses `/` for skills and `@` for Elements; agent calls cost credits.
- **Asset review statuses:** In progress / Needs review / Approved / Rejected.
- Deleted items go to the project Trash for 30 days.
- Source: https://higgsfield.ai/enterprise-help-center/manage-account/projects [official-help]

### 2.4 Speak / lip sync / talking avatars

**Lipsync Studio** (Video → Lipsync Studio, "Create Talking Clips"):
1. Upload an image or a video.
2. Type the **Audio text**, or generate or upload audio.
3. Pick a model.
4. Optionally pick a scene template (General, Selfie, Podcast, Car Talking…).

| Lipsync model | Input | Notes |
|---|---|---|
| Google Veo 3.1 | Image→video | Cinematic |
| Kling 2.6 Lipsync | Image→video | Up to 1080p, audio |
| Wan 2.5 Speak | Image→video | 480p–1080p |
| Kling Avatars 2.0 | Image→video | Longer clips |
| Higgsfield Speak 2.0 | Image→video | Priority-queue speed |
| Infinite Talk | Image→video | Long-form |
| Kling Lipsync | Video→video | Existing footage |
| Sync Lipsync 3 | Video→video | Up to 4K |

Sources: https://higgsfield.ai/creator-hub/help-center/ai-models/how-do-i-use-lipsync-voiceover-and-aspect-ratios; https://higgsfield.ai/lipsync-studio

**Higgsfield Intone** (added 2026-10-30): character (an upload or an AI Influencer) + location + speech (an upload or generated, ≤30 s). Delivery cues go in square brackets; output is 720p or 1080p with 5 aspect ratios and an optional motion/camera prompt.
- Source: changelog

**Shorts** (added 2026-11-03): 9:16 reels with an AI host.
- Script written from a topic, hook or key points.
- Motion from a reference video of 10–120 s.
- Duration 10 s–2 min; quality Basic or High.
- Source: changelog

### 2.5 Popcorn (storyboards)

- **Up to 8 consistent frames.**
- **Manual** mode lets you direct every frame. **Auto** mode turns one prompt into N frames (≤8). **Instadump** works from a style pack of up to 15 photos (PNG or JPG) plus your photo.
- **Up to 4 image references, addressed by number** ("Man from image one in the setting of image three…").
- To animate, use the frames as start frames or references for Kling or Veo, and chain the last frame of one clip into the next.
- Source: https://higgsfield.ai/creator-hub/help-center/ai-models/how-do-i-use-popcorn

There is also a "Storyboard Generator" landing page (https://higgsfield.ai/storyboard-generator) and a Canvas template, "StoryBoard With Elements" (changelog 2026-04-30).

### 2.6 Character consistency: Soul ID, Elements, AI Influencer

**Soul ID**
- Train it at Soul → Train new character with 20+ photos (≤80): varied angles, good light, no sunglasses or group shots, at least one full-height shot, recent photos. Then select it in the **Character** tab.
- It holds **one person**; for 2+ characters use Elements. It cannot be exported.
- A Soul 1 character must be "updated" to work in Soul Cinema or Soul 2.0.
- Source: help …/how-do-i-create-and-use-a-soul-id-character; changelog 2026-02-19

**Elements** (added 2026-02-25)
- A personal asset library of **Characters, Locations, Props** (and outfits). You save reference images, or a video, under one tag and call it in any prompt with **`@`**.
- A video element can keep, remove or replace its audio.
- Supported models: Kling 3.0 / 4.0, Seedream 4.5 and 5.0 Lite, Cinema Studio image and video, Nano Banana Pro, Seedance (Soul characters appear automatically), "and more".
- Sources: changelog 2026-02-25; help …/how-do-i-use-seedance

How to create an Element:
- From Assets: open the asset, then **⋯ → Create Element**.
- In a Cinema Studio project: **Elements → + Add new**, choose a type (Auto / Character / Location / Prop), then set the **Name, Version and Element ID** (for example **`@char_hero_v1`**).
- **Import** extracts elements from a script or spreadsheet (.pdf, .xlsx, .csv, .docx, .txt, .md). **Export CSV** is also available.
- Elements are project-scoped but can be pulled in from other projects.
- In Assets → Elements, each card shows its **@Element ID**.
- Sources: https://higgsfield.ai/enterprise-help-center/manage-account/projects; https://higgsfield.ai/enterprise-help-center/manage-account/assets; help …/whats-in-my-higgsfield-account

**AI Influencer Studio** is a game-style character builder.
- **Builder** panel: type, gender, origin, skin, eyes, skin conditions, age.
- Advanced settings: Face, Body, Style.
- Generates up to 4K. Text edits are made with **Edit**.
- Characters are saved to a library and can be animated, for example with Motion Control using your own recorded performance.
- Source: https://higgsfield.ai/creator-hub/help-center/tools/how-do-i-use-ai-influencer

### 2.7 Canvas (node workspace)

Canvas is an infinite board (Canvas → New canvas, or start from a template).
- **Nodes:** image and video generation (every model is a node), LLM, prompt, upload, text, shapes.
- **Templates:** Long Video, Simple Seedance 2.0, Extend Video, Image Edit, StoryBoard With Elements.
- On-board edits: crop, upscale, expand, remove background, inpaint.
- Real-time collaboration through **Share**; workflows can be saved as templates.
- **Building is free; credits are spent only when a node generates.** Canvas always spends credits, even on Unlimited models.
- Autosaves periodically.
- Sources: https://higgsfield.ai/creator-hub/help-center/tools/how-do-i-use-canvas; changelog 2026-04-30

### 2.8 Supercomputer (agent) and other "assist" features

**Supercomputer** is a chat agent. You give it a plain-language brief, and it:
- plans the work and routes each step to a model,
- uses connectors (Slack, Drive, Notion, Gmail, TikTok, Telegram, social publishing, custom MCP servers),
- runs Skills (official, community and your own),
- keeps Memory and Projects,
- can schedule recurring tasks,
- and builds and deploys apps and games.

You can choose the LLM yourself (Anthropic, OpenAI, Google, xAI, DeepSeek…) or let it route automatically. Credits are deducted per step, with the running cost shown as it works. Storage is 20 GB by default, expandable to 1 TB at 2.5 credits per GB per month.
- Sources: https://higgsfield.ai/creator-hub/help-center/tools/how-do-i-use-supercomputer; changelog 2026-07-06/08

**Agent mode setting:** "Ask before generating" or "Generate without asking". Writing permission in a chat message does not change it.
- Source: https://higgsfield.ai/enterprise-help-center/manage-account/projects

**No product called "Higgsfield Assist" was found.** The assistant-type features are Supercomputer, the Cinema Studio AI Director, and prompt enhancers (Enhance toggle, `enhance_prompt`, `prompt_optimizer`, `prompt_extend`).

### 2.9 Editing, upscaling and other tools

| Tool | What it does | Source |
|---|---|---|
| Inpaint / Draw to Edit | Sketch-guided image editing and inpainting (`/edit?generationType=image&model=veo-instruct`) | https://higgsfield.ai/llms.txt |
| Draw to Video | Sketch on a frame at a timestamp to change the video. CLI workflow `draw_to_video` with `--video --sketch --timestamp --prompt` | llms.txt; github workflows.md |
| Edit Video / Video Edit | Prompt-based edits to clips (Kling Omni Edit, Seedance 2.5 Edit, Kling 4.0 Edit, Cinema Studio Edit) | help; changelog |
| Reframe | Changes a video to 9:16 / 16:9 / 4:3 / 3:4 / 21:9 / 1:1 by regenerating the background; up to 4 style refs. CLI `reframe` with `--mode std\|pro` | changelog 2026-05-30; github |
| Expand | Image outpaint | help |
| Upscale | Image + video. Video engines: FLUX 3 Video Upscaler (1080p / 2K / 4K, Precise or Creative), ByteDance Upscale (2K / 4K, interpolation up to 60 fps, presets), Topaz (faces / slow-mo) | changelog 2026-06-15, 2026-08-27, 2026-10-15 |
| Asset-view edits | Color Grading, Upscale, Enhancer, Relight, Inpaint, Angles; **Turn to video**, **Recreate**, **Reference** | help …/whats-in-my-higgsfield-account |
| Angles 2.0 | Rotate the camera around a subject by dragging; quick Top / Front / Left / Right | changelog 2026-01-26 |
| Relight, Color Palette | Standalone video tools (6 lighting presets, 50+ grades) | changelog 2026-08-21 |
| Layers | Splits a flat image into editable elements | changelog 2026-08-11 |
| Background remover (image / video), Color grading, Skin Enhancer, Face Swap, Video Face Swap, Character Swap 2.0, Recast | One-click apps | https://higgsfield.ai/llms.txt |

### 2.10 Product placement and ads

- **Marketing Studio** (template-first):
  - Template categories: Product Shot, Motion, UGC, TikTok, Ads, Posters, Marketplace.
  - Add a **Product** and optionally an **Avatar**, then **Recreate**.
  - **Product Link** builds a video ad from a URL.
  - **Ad Reference** recreates an existing ad's structure with your product.
  - **Brand Kit** pulls brand details from your website.
  - **DTC Ads** makes static ad images.
  - There is also a free-prompt path.
  - The full template library is web-only; MCP offers a smaller preset set.
  - Sources: https://higgsfield.ai/creator-hub/help-center/tools/how-do-i-use-marketing-studio-to-create-video-ads; https://higgsfield.ai/enterprise-help-center/platform/tools-creative-workflow
- **Ads Studio:** paste a website; it imports the brand and products and generates batches of static ads (up to 20 per product per batch).
  - Source: changelog 2026-09-30
- **Ad Multiplier:** takes a 4–30 s ad and swaps the person, outfit, location, objects or product. It runs on Seedance 2.5, keeps the cut, timing and audio, and can remove burned-in captions.
  - Source: EHC tools-creative-workflow
- **Click to Ad** app (URL → UGC or pro video ad), plus product apps (Packshot, Bullet Time Scene / White / Splash, Giant Product, Billboard, Truck Ad, Fridge Ad, Volcano Ad, Macro Scene, ASMR Add-On / Promo…).
  - Source: https://higgsfield.ai/llms.txt

### 2.11 Other surfaces

- **Apps:** 94 one-click apps in 22 collections.
- **Content Factory / Faceless Studio:** faceless narrated videos.
- **Explainer.**
- **Playable / Games.**
- **Mangaka:** manga and comics.
- **Katana:** a Claude skill that recreates a reference edit with up to 5 of your photos.
- **Higgsfield Apps:** Supercomputer-built web apps whose users generate on their own credits.
- **Plugins:** Figma / FigJam, Photoshop, Premiere Pro / After Effects, DaVinci Resolve, Blender, Minecraft.

Sources: https://higgsfield.ai/llms.txt; https://higgsfield.ai/creator-hub/help-center/integrations/external-integrations-higgsfield; …/how-do-i-use-katana; …/tools/what-are-higgsfield-apps

---

## 3. Input files: attaching, tagging, reuse, limits

### 3.1 How references are named or referred to

| Context | How a reference is addressed | Source |
|---|---|---|
| Elements (web; Seedance, Kling, Cinema Studio, Nano Banana Pro…) | Type **`@`** in the prompt or click **@ Elements** under the prompt field. The Element ID is set by you (for example `@char_hero_v1`). The panel also lists your uploads and past generations | help …/how-do-i-use-seedance; EHC projects/assets |
| Seedance reference "roles" (web help) | `@character` (face, skin, style within the clip), `@style` (lighting, palette, mood from an image or still), `@motion` (camera and motion pattern from a video), `@audio` (sync, lip sync, ambience) | help …/how-do-i-use-seedance |
| Seedance in Canvas | Describe each reference's role **at the start of the prompt** ("the reference function must be described in the prompt, not just connected visually") | help …/how-do-i-use-canvas |
| Kling in Canvas | A directly connected image = **start frame**. For a character, create an Element and use `@element-name` | same |
| Cinema Studio 4.0 API | One-based tokens **`<<<image_1>>>`, `<<<video_1>>>`, `<<<audio_1>>>`**, which refer to the order in `image_urls` / `video_urls` / `audio_urls` | https://docs.higgsfield.ai/docs/models/cinema-studio-4/generate.md |
| Popcorn | By number in prose: "image one", "image three" | help …/how-do-i-use-popcorn |
| Nano Banana / multi-reference image models | "Describe the role of each reference in the prompt" | help …/how-do-i-use-nano-banana |
| Marketing Studio Image API with `enhance_prompt=true` | Order matters: **product first, optional person/model second** (1–2 images) | docs …/marketing-studio-image/flare.md |
| Katana shared preset | "a prompt that mentions them with @" (up to 40 images) | help …/how-do-i-use-katana |
| MCP / agents | Name the role in plain language ("Use the uploaded image as the character reference"; "The image is the character, the video is the motion reference") | help …/how-do-i-connect-higgsfield-to-ai-agent |
| Kling API `elements` | Kling element IDs as decimal strings, which must belong to the calling account. **No documented API call creates them** | docs …/kling-3/pro-image-to-video.md |
| Soul API | `custom_reference_id` (a trained Soul ID) with `custom_reference_strength` 0–1 | docs …/soul-2/generate.md |

### 3.2 Input roles and how each model reads them (API field names; full tables in Appendix A)

| Role | API field(s) | Models / behavior |
|---|---|---|
| Start frame | `image_url` (Kling 3.0, Seedance, Wan 3, LTX, PixVerse, MiniMax H3, HappyHorse, Hailuo, Kling 2.x); `first_frame_url` (Kling O3 / Omni) | Output framing follows the start image (Seedance, MiniMax H3, PixVerse have no `aspect_ratio` in i2v, or ignore it) |
| End frame | `last_image_url` (Kling 3.0 std / pro / 4k i2v), `end_image_url` (Seedance 2.0 / 2.5, Wan 2.7 / 3.0, LTX, PixVerse, MiniMax H3), `last_frame_url` (Kling O3 / Omni) | Not supported: HappyHorse, Wan 2.6, Kling 3.0 Turbo |
| Multi-image references | `image_urls` | Seedance 2.5 ≤30; Seedance 2.0 ≤9; Cinema Studio 4.0 ≤30; Wan 3.0 ≤10; MiniMax H3 1–9; HappyHorse 1–9; Grok Video 1.5 ≤7; Wan 2.7 images + videos ≤5 combined; Kling O3 / Omni video modes ≤4; Genjutsu 1–8 (Restyle ≤5) |
| Video references | `video_urls`, or `video_url` for a source to edit | Seedance 2.5 ≤10 (the source counts toward it); Seedance 2.0 ≤3 (each trimmed to 15 s); Wan 3.0 ≤5 (1–30 s each, ≤30 s total); MiniMax H3 ≤3; Wan 2.6 1–3; Kling O3 / Omni exactly 1 |
| Audio references | `audio_urls` / `audio_url` | Seedance 2.5 ≤10; Seedance 2.0 ≤3 (2–15 s each, ≤15 s total; audio alone is not enough); Wan 3.0 ≤5 (WAV or MP3, ≤30 s total); MiniMax H3 ≤3 (needs an image or video too); Wan 2.6 / 2.7 single `audio_url` ("driving audio"); Grok Video 1.5 `audio_url` (needs `image_urls`) |
| Motion source (motion control) | `video_url` + `image_url` | Kling 2.6 / 3.0 Motion Control: video 3–30 s (>100 MB gets compressed); character image ≤10 MB, 300–65,536 px per side, aspect 0.4–2.5; `character_orientation` image / video; `keep_original_sound` yes / no |
| Document / web page | `file_url` / `link_url` | Wan 3.0 / 3.0 Prime reference-to-video (automatically turns on thinking) |
| Trained identity | `custom_reference_id` | SOUL / SOUL V2 / SOUL Cinema |
| Style preset | `style_id` (Soul), `preset_id` (Genjutsu Restyle, Marketing Studio Image) | Preset catalogs: `GET /models/higgsfield/genjutsu/restyle/v1.0/presets` (returns `items[].id`, `items[].preview_url`); `GET /marketing-studio/image/presets` |

Source: the per-model pages listed in Appendix A [official-docs]

### 3.3 Limits

| Item | Limit | Source |
|---|---|---|
| API upload content types | image/jpeg, image/jpg, image/png, image/webp, image/gif; audio/wav, audio/x-wav; video/mp4 | https://docs.higgsfield.ai/docs/concepts/file-uploads.md |
| Presigned upload URL lifetime | 1 hour | same |
| Uploaded files retention (API) | Deleted within 7 days | https://docs.higgsfield.ai/docs/enterprise/data-retention.md |
| URL length for media fields (Genjutsu, Soul ID) | ≤2083 chars | Appendix A |
| Genjutsu source video (API) | ≥4 s; trimmed to 30 s; object swap needs ≥409,600 px per frame; Restyle ≤200 MiB | docs …/genjutsu/* |
| Kling O3 video edit source | 3–15.5 s, ≤200 MB; Omni edit 3–10 s, ≤200 MB | docs …/kling-o3/video-edit.md, …/kling-omni/video-edit.md |
| Wan 2.6 i2v input image | Resized to ≤1,440 px on the longest side | docs …/wan-2-6/image-to-video.md |
| Grok Video 1.5 image formats | JPEG / PNG / WebP / GIF; no SVG or XML | docs …/grok-video-1-5/reference-to-video.md |
| Marketing Studio Image refs | JPEG / PNG / WebP; ≤16 for editing | docs …/marketing-studio-image/* |
| Soul ID training | Web: 20–80 photos; API: 1–100 images | help; docs |
| Web uploads (CLI auto-detect) | Image png / jpg / webp / gif; video mp4 / mov / webm; audio mp3 / wav / m4a / ogg | github media-inputs.md |
| Web: per-file size limits | **Not published** | — |
| Cinema Studio upload video length | 2.5: none; 3.0 / 3.5: ≤15 s; 4.0: ≤30 s | help …/how-do-i-use-cinema-studio |
| Seedance 2.5 / Cinema Studio 4.0 refs | 30 images / 10 videos / 10 audio, **≤50 total**; video and audio each normalized to ≤30 s total | docs |
| Kling 4.0 refs (web) | ≤15 (images, ≤5 videos, 1 voice, Elements); ≤10 keyframes | changelog 2026-10-21 |
| Voice clones | 5 per workspace by default (Enterprise) | EHC integrations |

### 3.4 Reusing results as inputs

- **Web:** the asset view has **Reference**, **Turn to video**, **Recreate** and **Create Element**. The `+` picker in Cinema Studio offers device uploads, saved Elements, past generations and liked assets. The Genjutsu picker pulls from Generations, Liked and AI Influencer.
  - Sources: help …/whats-in-my-higgsfield-account; …/how-do-i-use-cinema-studio; …/how-do-i-use-genjutsu
- **CLI/MCP:** media flags accept a local path, an upload ID, **or a previous job ID**. Example: `--start-image <previous_job_id>`.
  - Source: https://github.com/higgsfield-ai/skills/blob/main/higgsfield-generate/references/media-inputs.md
- **API:** pass the output URL from a completed request (valid until `expires_at`) as an input URL. The docs do not state this explicitly; it is implied, because inputs only need to be public HTTPS URLs.

---

## 4. Prompting

**Official prompt guide:** https://higgsfield.ai/creator-hub/help-center/getting-started/how-do-i-write-a-good-prompt [official-help]
- **Be specific, in layers:** subject → details → environment → style. For video, add camera and mood.
- **Image→video prompts change role.** They describe *what happens*, not what things look like: action, camera movement, timing, mood.
- **Cinematic video prompts are written as a shot list in blocks:** Style & mood / Cinematography & camera / Lighting & color / Action (beat by beat) / Audio (score, ambience, dialogue with timestamps) / Shot list with durations. The worked example is 6 shots in 15 s, with dialogue lines timed, for example "COWBOY, around 2.4 to 4.0 seconds: …".
- **To keep identity:** "Keep the exact same man, same face, same pose…, change only…".
- **Habits:** say what you want rather than what you don't (a few targeted "NO …" phrases are fine); match prompt complexity to the task; avoid contradicting the input image; write in English (Seedance and Kling sometimes respond better to Chinese for nuanced motion); change one thing per iteration; chain the last frame into the next clip.

**Per-model structure:**
- **Seedance:** subject + action → setting + lighting → camera move → mood/style. Use explicit camera terms. "SFX:" lines are allowed. Start with image-to-video at 720p, check the 5–8 s mark, then scale to 1080p or 4K with an identical prompt.
  - Source: help …/how-do-i-use-seedance
- **Popcorn:** Subject / Setting / Style / Action / Atmosphere. Lead with style keywords.
  - Source: help …/how-do-i-use-popcorn
- **DoP:** a sharp keyframe matters most. The preset defines the camera logic, and the prompt adds scene details. Use Enhance when the scene "barely changes".
  - Source: help …/how-do-i-use-dop
- **Official CLI guidance** (github prompt-engineering.md): stay under about 200 tokens. For image→image, describe the change only. For image→video, describe motion and don't redescribe the frame. Most models expose no negative prompt, so phrase things positively.

**Enhancers and optimizers:**
- **Web:** DoP has an **Enhance** toggle.
- **API:**
  - `enhance_prompt` on Soul and on Marketing Studio Image (needs `preset_id` + 1–2 images).
  - `prompt_optimizer` on Hailuo 2.3 (default true).
  - `prompt_extend` on Wan 2.6 / 2.7 and Z-Image (enhanced pricing tier) and on Qwen.
  - `enable_thinking` on Qwen and Wan 3.0.
  - Short Soul prompts with the general style can be enhanced automatically even with `enhance_prompt=false`.
- Source: Appendix A [official-docs]

**Presets versus free text:**
- **DoP and Effects:** the preset sets the motion and the prompt is supplementary.
- **Genjutsu Restyle:** `preset_id` is required; the prompt "supplements" it and "does not create a custom style".
- **Marketing Studio templates:** no prompt is required.
- **Cinema Studio 4.0:** leave a control out and the "director chooses automatically". The literal value `"auto"` is rejected.
- Sources: help; docs …/genjutsu/restyle.md; docs …/cinema-studio-4/generate.md

Kling 3.0 / O3 prompt limits: top-level prompt ≤2,500 characters (longer is truncated); multi-shot `multi_prompt` has 1–6 items, each ≤512 characters with duration 1–15 s, and the durations are summed for billing. Other limits: Kling 3.0 Turbo T2V ≤3,072; LTX ≤5,000; Ideogram 2–2,048; Ads Studio ≤8,000; Genjutsu ≤10,000; Recraft ≤10,000; Z-Image ≤800; MiniMax H3 uses only the first 7,000.
- Source: Appendix A

---

## 5. Developer API, cloud platform and integrations

### 5.1 Basics

| Item | Value | Source |
|---|---|---|
| Base URL | `https://api.higgsfield.ai` | https://docs.higgsfield.ai/docs/how-to/introduction.md |
| Console | https://console.higgsfield.ai (docs) / https://open.higgsfield.ai (help center, pricing; cloud.higgsfield.ai redirects there) | docs; help; site |
| Auth | `Authorization: Key {key_id}:{key_secret}`. Legacy `hf-api-key` + `hf-secret` headers still accepted. **Not Bearer.** Server-side only | https://docs.higgsfield.ai/docs/authentication.md |
| Auth errors | `401 {"detail":"Invalid credentials"}`. Expired key: `403 {"code":"api_key_expired",…}`. Disabled key: `403 api_key_disabled` | authentication.md; enterprise/access-control.md |
| Key management | Name, expiration, last used, tags, disable / delete; in orgs only admins manage keys | enterprise/access-control.md |
| Python SDK | `pip install higgsfield-client` (Python 3.8+). Env `HF_KEY="id:secret"`. `subscribe` / `subscribe_async`, `submit` / `submit_async`, `status`, `result`, `cancel`, `upload`, `upload_file`, `upload_image`. Repo: https://github.com/higgsfield-ai/higgsfield-client | https://docs.higgsfield.ai/docs/how-to/sdk.md |
| TS SDK | `npm install @higgsfield/client`; `import { config, higgsfield } from "@higgsfield/client/v2"`; env `HF_CREDENTIALS`; `higgsfield.subscribe(id, {input, withPolling:true})`. **Blocks browser use.** Repo: https://github.com/higgsfield-ai/higgsfield-js | same |
| Swift / macOS SDK | **None.** Use REST | — |
| OpenAPI | https://docs.higgsfield.ai/docs/openapi.json (v2.0.0). Only partial; per the docs it is "not the authoritative model catalog" | https://docs.higgsfield.ai/docs/llms.txt |
| LLM-friendly docs | https://docs.higgsfield.ai/docs/llms.txt; every page is also served as `.md` | same |

### 5.2 Endpoints (shared)

| Method / path | Purpose | Notes |
|---|---|---|
| `POST /{endpoint_id}` (for example `/kling-video/v3.0/pro/image-to-video`) | Submit a generation | JSON body per model. Optional headers `Idempotency-Key`, `Hf-Expires-After`; optional query `?hf_webhook=<urlencoded https>` |
| `GET /requests/{request_id}/status` | Status + outputs | Use the returned `status_url` rather than building it yourself |
| `POST /requests/{request_id}/cancel` | Cancel | Only while every job is `queued`. Returns `202` with an empty body, or `400` once started |
| `DELETE /requests/{request_id}` | Delete files, prompt and params | `200 {"request_id","status":"deleted"}` (idempotent); `409` while running; `404`; `503` |
| `POST /estimate/{endpoint_id}` | Cost estimate in USD | Response `{"usd":"0.094"}` |
| `POST /files/generate-upload-url` | Presigned upload | Body `{"content_type":"image/jpeg"}`. Response `public_url`, `upload_url`, `content_type`, `upload_headers` (for example `x-amz-tagging: retention=temporary`). `PUT` with exactly those headers and **no** API credentials |
| `POST /v1/custom-references` | Train Soul ID | Body `name` (≤100), `model_version` v1 / v2 / cinema (default v1), `input_images[]` 1–100 of `{"type":"image_url","image_url":…}`. Response `id, name, model_version, status, thumbnail_url, created_at, in_progress_at, fail_reason` |
| `GET /v1/custom-references/{id}` | Training status | `not_ready`, `queued`, `in_progress`, `completed`, `failed`. Concurrent trainings are limited (example message: "(2)"); over the limit returns `429` + `Retry-After` |
| `GET /models/higgsfield/genjutsu/restyle/v1.0/presets` | Restyle style catalog | `items[].id` (UUID → `preset_id`), `items[].preview_url` |
| `GET /marketing-studio/image/presets` | Marketing Studio Image presets | For `enhance_prompt=true` |
| `GET /models/usage` | Usage analytics (not a billing record) | Query `start`, `end` (≤31 days), `timeframe` hour / day / week / month, `bound_to_timeframe`, `model` (repeatable), `expand` time_series / auth_method, `page`, `limit` ≤100 |

Sources: https://docs.higgsfield.ai/docs/concepts/requests.md, …/concepts/file-uploads.md, …/concepts/billing-and-retention.md, …/enterprise/usage-and-billing.md, …/models/soul-id/create-character.md, …/models/genjutsu/restyle.md, …/models/marketing-studio-image/generate-and-edit.md [official-docs]

### 5.3 Request lifecycle

| Status | Terminal | Meaning |
|---|---|---|
| `queued` | no | Waiting; can still be canceled |
| `in_progress` | no | Started; can no longer be canceled |
| `completed` | yes | Output URLs present |
| `failed` | yes | May include `error` |
| `nsfw` | yes | Input or output was moderated |
| `canceled` | yes | Canceled before processing started |

Source: https://docs.higgsfield.ai/docs/concepts/requests.md

**Responses:**
- **Submit:** `{"status":"queued","request_id":<uuid>,"status_url":…,"cancel_url":…,"expires_after":604800}`.
- **Completed image:** `images: [{url}]`. **Video:** `video: {url}`. **Audio:** `audio: {url}`, `audios: [{url}]`.
- Some video and 3D operations also return artifacts: `zip`, `mov`, `jsx`, `fbx`, `ply`.
- Once finished, `expires_at` (ISO date) is present.
- The OpenAPI `MediaOutput` is `{url}` only. Webhooks add `content_type`.
- Source: same + https://docs.higgsfield.ai/docs/api-reference/requests/get-request-status.md

**Polling:** start at 2 s, multiply by about 1.5 up to 10 s, and add jitter. Stop on a terminal status. Retry `5xx` errors; stop on `401` or `404`. Set an app-level timeout per model. Models have server-side timeouts: a timed-out request is marked failed and not charged.
- Sources: https://docs.higgsfield.ai/docs/concepts/polling.md; https://docs.higgsfield.ai/docs/help/faq.md

**Webhooks:**
- Add `?hf_webhook=` with an HTTPS endpoint. It must respond within 10 s.
- **Envelope:** `{request_id, status, error, expires_at, payload:{images|video|audio…}}`.
- **Signing:** Standard Webhooks with headers `webhook-id`, `webhook-timestamp`, `webhook-signature` (`v1,<base64>`). The secret is `whsec_…`, revealed in Console → Settings (deliveries are unsigned until it is first revealed). Rotation keeps the old secret valid for 24 h. ±5 min tolerance.
- **Retries:** `5xx` and network failures are retried for up to 2 h; `4xx` responses are treated as permanent.
- Deduplicate by `webhook-id`. Sent on `completed`, `failed` and `nsfw`.
- Legacy `X-Webhook-Secret-Key` is being retired.
- Source: https://docs.higgsfield.ai/docs/how-to/webhooks.md

A desktop app has no public HTTPS endpoint, so **Kino should poll**, unless it adds a relay.

**Idempotency:**
- `Idempotency-Key`: 1–255 visible ASCII characters (a UUID is recommended).
- Replaying the same key returns the original `request_id`, with no new charge.
- Same key with different parameters returns `422`.
- The key's fingerprint includes the endpoint, body, webhook and `Hf-Expires-After`. A rejected request (auth or validation) does not consume the key.
- Source: https://docs.higgsfield.ai/docs/concepts/idempotency.md

**Retention:**
- Default is 7 days after finish.
- `Hf-Expires-After` (3600 s up to the account retention) can only shorten it; an account retention of 1 h–7 d can be set by Higgsfield on request.
- After expiry, URLs die but the status record remains.
- Third-party providers' own data policies also apply.
- Source: https://docs.higgsfield.ai/docs/enterprise/data-retention.md

There is a **model training opt-out** setting in Console → Settings; it is off by default.
- Source: https://docs.higgsfield.ai/docs/enterprise/model-training.md

### 5.4 Errors

| HTTP | Meaning | Retry? |
|---|---|---|
| 400 | Invalid params / rejected input (also cancel after start) | After fixing the request |
| 401 | Missing or invalid credentials | No |
| 403 | **Insufficient balance**; expired or disabled key | After adding funds |
| 404 | Request or model not found for this account (also model unavailable to the account) | No |
| 409 | Request still running (delete) | After it finishes |
| 422 | Validation failed; idempotency key reused with different params; `Hf-Expires-After` out of range | No |
| 423 | Model temporarily blocked | Later |
| 429 | `account_queue_full` (body `detail.code / message / retryable / limit / retry_after_seconds`) or an endpoint limit | After `Retry-After` |
| 500 | Server error | Yes, with backoff |
| 503 | Model disabled or not ready; `admission_control_unavailable` | Later, with backoff |

The error envelope is FastAPI-style `{"detail": …}` (a list for validation errors). Every response carries `X-Correlation-ID`. `failed` and `nsfw` outcomes are not charged.
- Source: https://docs.higgsfield.ai/docs/concepts/errors.md

### 5.5 Rate limits / concurrency

**The primary limit is concurrency.** Requests above it are accepted and queued. The queue cap is a multiple of the concurrency limit, and every batch output counts separately. When the queue is full you get `429` and nothing is charged. Some models have their own concurrency limits. Successful responses carry no rate-limit headers; the Console shows your limits.
- Sources: https://docs.higgsfield.ai/docs/concepts/rate-limits.md; …/enterprise/capacity.md

**Concurrency tiers** on the API pricing page, based on funds added in the last 28 days:

| Funds added | Concurrent generations |
|---|---|
| New account | 2 |
| ≥$25 | 10 |
| ≥$100 | 20 |
| ≥$1,000 | 40 |

- Source: https://open.higgsfield.ai/pricing [official-site]
- Conflict: the help center says "Creating a key unlocks 20 concurrent requests". See §8.

### 5.6 Pricing and credits

**API billing:**
- Pay-as-you-go from a USD balance; minimum top-up $5; funds expire 1 year after they are added.
- **Video is priced per second of output, images per image, DoP per generation.**
- Rates depend on settings such as resolution and audio, and are public.
- The balance can't go negative (requests wait when it is empty), and auto top-up is available.
- Sources: https://higgsfield.ai/creator-hub/help-center/integrations/what-is-the-higgsfield-api; https://docs.higgsfield.ai/docs/concepts/billing-and-retention.md
- Note that the docs' error table says insufficient balance returns `403`, which conflicts with "requests wait". See §8.

**Starting per-second rates** shown on https://open.higgsfield.ai/pricing on 2026-11-04. These are labeled "List price from" and "Max-discount price from"; the discount is a time-limited launch offer. The page shows the first 10 of 33 models.

| Model | Modes | Duration / resolution | List from | Discounted from |
|---|---|---|---|---|
| Genjutsu | 2 | up to 1080p | $0.318/s | $0.159/s (−50%) |
| Genjutsu Light | 2 | up to 1080p | $0.050/s | $0.025/s |
| Seedance 2.5 | 5 | 4–30 s, ≤1080p | $0.206/s | $0.144/s (−30%) |
| Seedance 2.0 | 3 | 4–15 s, ≤4K | $0.141/s | $0.099/s |
| Wan 3.0 Prime | 3 | 2–30 s, ≤1080p | $0.068/s | $0.041/s (−40%) |
| Wan 3.0 | 3 | 2–30 s, ≤1080p | $0.050/s | $0.025/s |
| Kling 4.0 | 4 | 3–30 s, ≤1080p | $0.094/s | $0.066/s |
| Kling 3.0 | 10 | 3–15 s, ≤1080p | $0.084/s | $0.042/s |
| Kling 2.6 | 4 | 5 / 10 s | $0.070/s | $0.035/s |
| Kling 2.5 | 3 | 5 / 10 s, ≤1080p | $0.042/s | $0.021/s |

The API explore page (https://open.higgsfield.ai/explore) also shows "from" prices for: MiniMax H3, LTX 2.5 Fast and Pro, Grok Video 1.5, Wan 2.7, Soul 2, Soul Standard, Ideogram 4.0, Recraft 4.1, Z-Image Turbo, Ads Studio, Marketing Studio Image, Grok Imagine 2.0, and AI Influencer ($0.05 per sheet). The text extraction scrambled which number belongs to which model, so **use `POST /estimate/{endpoint_id}` for exact figures.**

Changelog promotions: API cashback ($15 after the first $100; up to 20% in 30-day cycles; earlier "$1 back per $1 spent, up to $200,000 per verified business") and 60% off Wan 3.0 until 2026-10-31.
- Source: changelog 2026-09-24, 2026-10-02, 2026-10-13

**Web plan credits:**
- Credits are the currency; the cost is shown on the Generate button.
- Subscription credits reset each cycle and do not roll over (annual plans reset every 30 days).
- Credit Packs, Auto-Refill and Boost credits expire after 90 days; promo credits on a stated date.
- Spend order: subscription credits first, then whatever expires soonest.
- Batch outputs are each charged.
- Failed or flagged generations are refunded automatically, **except Grok**, which is charged when it starts.
- Sources: https://higgsfield.ai/creator-hub/help-center/credits/how-credits-work; …/troubleshooting/generation-is-stuck-or-failed

**Unlimited models:**
- A model-specific window: 365 days on most models included in mid and top plans; the newest flagships may be ~7 days; some plans give a free-generation pool instead.
- Requires an active subscription. Turned on with an Unlimited toggle in the generation panel.
- Unlimited runs in the **standard (slower) queue**; credit mode runs in the **priority queue**.
- **Web only**: never through MCP, CLI, Canvas or Supercomputer.
- The Unlimited Models Marketplace sells 1-, 7- or 14-day bundles. Bundle concurrency: video 1 at a time (≤15 s), image 2, All Models bundle 2 images + 1 video.
- Sources: https://higgsfield.ai/creator-hub/help-center/credits/what-are-unlimited-models-and-which-plans-include-them; changelog 2026-06-26

**Concurrency Boost:** +4, +8, +12 or +16 concurrent generations, with a separate Boost Credit balance.
- Source: …/credits/how-does-concurrency-boost-work

**Watermark:** free accounts get a visible watermark; paid plans don't. Invisible AI markers may be embedded either way.
- Source: …/credits/watermark-and-how-to-remove

**Plan names and prices:** the official pricing page is rendered client-side and could not be read.
- The help center names individual plans (Starter, Basic, Pro, Plus, with "Ultra" per third parties) and business plans (Team, Scale, Enterprise).
- Third-party figures for Oct 2026: Starter $19/mo, 270 credits; Plus $59/mo or $47/mo annual, 1,200 credits; Ultra $129/mo or $99/mo annual, 3,000 credits. Other third-party sources disagree. **Unconfirmed.**
- Sources: help …/plans/how-do-higgsfield-plans-work [official-help]; https://www.heygen.com/blog/higgsfield-pricing, https://www.krea.ai/blog/higgsfield-pricing-explained-2026-unlimited-credits-and-real-monthly-costs [3rd-party]

### 5.7 MCP, CLI, Bridge and other integrations

| Integration | Details | Source |
|---|---|---|
| **Higgsfield MCP** | URL **`https://mcp.higgsfield.ai/mcp`** (launched 2026-04-28/30). OAuth through Clerk (`authorization_servers: https://clerk.higgsfield.ai`; scopes `openid email offline_access`); unauthenticated calls get `401`. No API key; uses **plan credits** with no Unlimited; needs an active paid subscription. Clients: Claude (custom connector), ChatGPT (official plugin), Cursor (marketplace), Manus, Grok Bot, any MCP client | help …/what-is-higgsfield-mcp, …/how-do-i-connect-higgsfield-to-ai-agent; live probe of `/.well-known/oauth-protected-resource` |
| MCP capabilities (official list) | Image and video generation on "all models"; image and video upscaling; background removal; expand and reframe; Kling 3.0 Motion Control; Soul characters and Elements; audio (voiceover, cloning, voice change, dubbing); Personal Clipper; credit balance; list generations and uploads; Marketing Studio (smaller preset set); Ad Multiplier; Genjutsu; app builder; skills; send outputs to folders. Results land in Assets tagged with source MCP. File refs go through **an upload window the agent opens**, because files attached to the chat are not passed through | same; EHC integrations |
| MCP tool names / schemas | **Not published.** Third-party guides disagree ("30+ models" vs "7 models through 5 tools"). This environment has "claude.ai Higgsfield" and "Higgsfield Bridge" connectors that are **not authorized**, so the live tool list could not be read | 3rd-party: https://creatify.ai/blog/what-is-higgsfield-mcp…, https://mcp.directory/blog/higgsfield-mcp-guide |
| **Higgsfield Bridge** | **`https://bridge.higgsfield.ai/mcp`**: connects an agent to the installed **Blender** add-on so it works in the open scene | help …/external-integrations-higgsfield |
| **Higgsfield CLI** | `npm i -g @higgsfield/cli` (or `curl -fsSL https://raw.githubusercontent.com/higgsfield-ai/cli/main/install.sh \| sh`). `higgsfield auth login` (browser). Skills: `npx skills add higgsfield-ai/skills` | help …/how-do-i-access-higgsfield-via-cli; github SKILL.md |
| CLI command surface | `higgsfield model list/get`, `generate create <job_set_type> --prompt … --image/--start-image/--end-image/--video/--audio/--image-references… --wait [--json]`, `generate list/get/wait/cost`, `generate workflow draw_to_video\|reframe`, `upload create`, `soul-id create/list/get/wait`, `preset list soul-v2`, `marketing-studio avatars/products/hooks/settings/ad-references/brand-kits/ad-formats …`, `account status`. Media flags accept a path, an upload ID or a job ID; the server returns `adjustments` for coerced values | github higgsfield-generate/SKILL.md, media-inputs.md, workflows.md |
| Web-side model IDs (CLI, plan credits) | Examples: `seedance_2_5` (modes `t2v` / `omni_reference` / `video_edit` / `video_extension`), `seedance_2_0`, `kling3_0`, `kling3_0_turbo`, `kling2_6`, `veo3_1`, `cinematic_studio_video_4_0`, `grok_video_v15`, `gemini_omni_flash_1_1`, `minimax_h3`, `wan3_0`, `text2image_soul_v2`, `soul_cinematic`, `gpt_image_2_5`, `nano_banana_flash` (Nano Banana 2), `nano_banana_pro` (alias `nano_banana_2`!), `seedream_v5_pro`, `recraft_v4_1`, `z_image`, `seed_audio`, `multi_image_to_3d`, `marketing_studio_video` / `_image`, `brain_activity` | github model-catalog.md |
| Org API (Enterprise, read-only) | `GET https://fnf-api-gw.higgsfield.ai/fnf/v1/organization/generation_usage_report`, `/generations`, `/generations/{id}`. Header `x-api-key`. 60 requests/min, 2 concurrent per organization; downloads 600/min, 4 concurrent | https://higgsfield.ai/enterprise-help-center/manage-account/usage-analytics |
| Plugins | Figma/FigJam, Photoshop (UXP, 2024+), Premiere/After Effects (2024+), DaVinci Resolve, Blender 5.1+, Minecraft (NeoForge 1.21.1). Default models: Nano Banana 2 (image), Seedance 2.0 (video) | help …/external-integrations-higgsfield |

### 5.8 What the web app can do that the API cannot (as documented)

**Missing models on the API:**
- **Veo 3.1 / Veo 3 / Veo 3.1 Lite, Sora 2, Gemini Omni Flash**.
- **Nano Banana (all), GPT Image (direct), Seedream, FLUX**.
- **DoP camera presets / Mix / Motion Library / Effects / Viral Presets**: no documented endpoint. The help center claims DoP is in the API (see §8).
- **Popcorn**.
- **Lipsync Studio models**, Speak, Intone, Kling Avatars.
- Audio: TTS, voice cloning, Seed Audio. The docs mention `audio` outputs exist, but no audio model page.

**Missing features on the API:**
- **Elements creation** (Kling `elements` IDs are accepted, but there is no create endpoint) and the `@` tagging UI.
- Upscalers, Reframe, Expand, Inpaint, Draw to Edit / Video, Angles, Relight, Layers, background removal.
- Kling 4.0 is listed in the API console but has no docs workflow page yet.
- Cinema Studio 4.0 extend and edit modes (the docs point to Seedance 2.5 edit and extend instead), the Emotion control, 1080p (API is 480p / 720p), and start/end-frame slots (the CLI has them).
- Marketing Studio **Video**, avatars, products, hooks, brand kits (CLI/MCP only); Click to Ad; templates.
- Canvas, Supercomputer, Projects, Assets library, history, comments, Community.

**Partly covered:**
- Seedance 2.5 Draft Mode and region-level edit masks are not exposed. Video edit exists, but there is no mask field.

Sources: https://docs.higgsfield.ai/docs/models/video-generation.md, …/image-generation.md, compared with the web help pages above.

---

## 6. Web app workflow UX

**From assets to a finished clip** (typical official path):
1. Make a keyframe (Soul / Soul Cinema / Nano Banana / GPT Image), or upload one.
2. Optionally train a Soul ID, or save Elements for characters, locations and props.
3. Animate: in Video, pick a model and add the start frame and optional end frame, references or `@Elements`. Or use Cinema Studio with the Director's Panel, or DoP with a preset.
4. Check the cost on Generate, then generate. Iterate one change at a time; draft on Turbo, Lite or Draft Mode.
5. Extend or chain: last frame → next start frame, or Extend (Cinema Studio 4.0, Grok 1.5, Seedance 2.5 extend).
6. Edit (Seedance 2.5 Edit, Kling Edit), reframe, upscale.
7. Download from Assets, or join clips in an editor.

Sources: help …/how-do-i-write-a-good-prompt, …/how-do-i-use-kling, …/how-do-i-use-seedance, …/how-do-i-use-cinema-studio

**Assets library** (https://higgsfield.ai/asset/all):
- Every generation is saved automatically, filterable by Image / Video / Audio (Enterprise adds Enhanced, Projects, Members, Sub-workspaces, Favourites, Elements, Trash).
- Folders ("Move to"), Favorites (heart), search by keyword, date or prompt.
- Filters: type, model, date range. View: Square / Masonry, Split by date, card size.
- Asset view: copy the prompt; see model, resolution and date; edit tools; **Turn to video / Recreate / Reference**; download; share link; comments; **Create Element**; **Publish**.
- Bulk bar: Download, Publish all, Add to folder, Like, Delete.
- Trash keeps items 30 days.
- Sources: help …/whats-in-my-higgsfield-account; https://higgsfield.ai/enterprise-help-center/manage-account/assets

**Queue and cancel:**
- Generation tiles show **Queued → Processing → Generating**.
- Cancel (hover the tile) works only while Queued and refunds the credits. "Failed to cancel" means the job had already started.
- Error messages: "You've hit your limit of generations at the same time", "Rejected due to copyright restrictions" / "IP detected", "May contain protected content", and NSFW flags. Some IP blocks offer an **"I own the rights for this image"** button.
- Sources: help …/troubleshooting/generation-is-stuck-or-failed, …/my-generation-blocked-for-copyright-or-ip; changelog 2026-01-31

**Variations:**
- Batch size (Soul 1–4; Marketing Studio "variations"; Ads Studio 1–8 via API, up to 20 per product on web).
- **Recreate** re-runs the same prompt. Draft Mode compares several previews before the final render.
- Canvas runs models side by side.

**What users praise** [3rd-party: Trustpilot 4.0/5 from 5,290 reviews (62% 5★, 19% 1★); Reddit r/HiggsfieldAI snapshots]:
- The breadth of models in one place and the model quality (Seedance 2.0 / 2.5, Soul Cinema).
- A clean all-in-one UI, character consistency, viral templates, tutorials and Academy, fast feature releases, and some fast support resolutions.
- Sources: https://www.trustpilot.com/review/higgsfield.ai, https://reddit.sentinel-team.org/subreddits/HiggsfieldAI/snapshots/2026-04-25T00%3A11%3A40.375255Z

**What users find confusing or complain about** [3rd-party]:
- Credit expiry with no rollover, and hard-to-understand plan and credit rules.
- "Unlimited" plans with very long standard-queue waits (reports of hours), and a perceived quality gap between unlimited and credit mode.
- Billing and renewal after cancellation, and refused refunds.
- Navigation ("very difficult to navigate").
- Start frames ignored, matching end frames, lip-sync length mismatches, removing music but keeping SFX.
- Moderation and IP blocks (Seedance blocks celebrity and IP characters; Element "eligibility").
- Failed generations perceived as charged.
- Sources: same

---

## 7. Design implications for Kino (our inference, not Higgsfield documentation)

1. **Model a "role" for every attached file:** start frame, end frame, character, style, motion, audio, product, edit source. Then map each role to each backend's field names: `image_url` / `first_frame_url`, `last_image_url` / `end_image_url` / `last_frame_url`, `image_urls`, `video_urls`, `audio_urls`, `<<<image_n>>>` tokens. Use the table in §3.2 and Appendix A.
2. **Keep a local "Elements"-style library** (named characters, products, locations with reference images) and expand a mention like `@hero` into the right mechanism per model: ordered `image_urls` + `<<<image_n>>>` for Cinema Studio; a role sentence at the start of the prompt for Seedance; `custom_reference_id` for Soul.
3. **Upload once with `/files/generate-upload-url` and cache the `public_url`.** Uploaded files are deleted within 7 days, so track their age and re-upload when needed.
4. **Always call `/estimate/...` before submitting** to show the cost, matching the web app's "cost on the Generate button". Always send an `Idempotency-Key`. Poll with 2 → 10 s backoff. Download outputs right away, because of the 7-day `expires_at`.
5. **Expose model-native controls as simple pickers:** Cinema Studio 4.0 enums, LTX `camera_movement`, Kling `multi_prompt` shots (1–6, ≤512 characters, summed duration). Offer DoP-style named camera moves only for models whose schema has them, or as prompt phrases for Seedance or Kling. There is no preset endpoint on the API.

---

## 8. Unconfirmed / conflicting

| Topic | Conflict / gap | Sources |
|---|---|---|
| DoP on the API | The help center says the API includes "DoP… priced per generation"; the docs catalog (84 entries) has no DoP. Legacy v1 docs (`image2video/dop`, `motions:[{id,strength}]`, `model:"dop-turbo"`, `hf-api-key` / `hf-secret` headers) now return **404**. Treat DoP as **not available** on the current API | help …/what-is-the-higgsfield-api vs https://docs.higgsfield.ai/docs/models.md; search snippet of https://docs.higgsfield.ai/api-reference/image-to-video/generate-[dop] (404 on 2026-11-04) |
| DoP strength / Mix | Strength slider not confirmed on the web UI; third party says strength 0–1. Mix combines "two" (launch post) or "2+" presets | help …/how-do-i-use-dop; https://higgsfield.ai/blog/Introducing-Higgsfield-Mix-Motion-Reimagined; https://clipia.ai/en/video-models/higgsfield-dop [3rd-party] |
| API concurrency | Help center: a new key unlocks 20 concurrent. Pricing page: 2 by default, 10 at ≥$25, 20 at ≥$100, 40 at ≥$1,000 (funds from the last 28 days) | help …/what-is-the-higgsfield-api vs https://open.higgsfield.ai/pricing |
| Empty balance | Help center: "new requests simply wait". Docs: `403` = insufficient balance | help vs https://docs.higgsfield.ai/docs/concepts/errors.md |
| Console URL | console.higgsfield.ai (docs) vs open.higgsfield.ai (help center, live; cloud.higgsfield.ai redirects there) | docs; help |
| Seedance 2.5 resolution | Changelog 2026-08-06: "480p and 720p, with upscaling up to 4K". Help center: "up to 1080p on Pro and Plus plans". API: 480p / 720p / 1080p. Seedance 2.5 Edit 480–720p | changelog; help; docs |
| Cinema Studio 4.0 resolution | API: 480p / 720p only. CLI catalog says "up to 1080p" | docs vs github model-catalog |
| Cinema Studio emotion control | "Emotion Wheel, 8+ emotions" (changelog) vs "six emotions, three intensities" (EHC) vs "emotion slider" (help) | changelog 2026-08-12; EHC tools-creative-workflow; help |
| Veo 3.1 resolution | Landing page: 720p / 1080p. Changelog: 4K added 2026-01-24. CLI: quality basic / high / ultra | https://higgsfield.ai/veo3.1; changelog; github |
| Sora 2 durations / aspect ratios | Not stated on the Higgsfield page | https://higgsfield.ai/sora-2 |
| Kling naming | API "Kling O3" / "Kling Omni" vs web "Kling 3.0 Omni" / "O1". Assumed O3 = Omni 3.0, unconfirmed | docs vs help …/how-do-i-use-kling |
| Kling 4.0 on the API | Listed on open.higgsfield.ai (4 modes, 3–30 s, ≤1080p) but no docs workflow page or field schema | https://open.higgsfield.ai/pricing |
| Kling "latest" | EHC (2026-11-01) lists Kling 4.0 as current; Creator Hub Kling article still centres on 3.0 | EHC ai-models vs help …/how-do-i-use-kling |
| Soul ID photo count | Web help: 20–80. Official CLI skill: 5–20. API: 1–100 | help; github soul_skill; docs |
| Seedance reference "@character/@style/@motion/@audio" | These appear in the help center as reference *types*. Whether they are literal typed tokens in the Seedance prompt UI (versus Elements `@tags`) could not be verified without logging in | help …/how-do-i-use-seedance |
| Plan names and prices | The official pricing page could not be read (client-rendered). Third-party figures conflict (Starter $15 vs $19; Plus $39 / $49 / $59) | https://higgsfield.ai/pricing; third parties in §5.6 |
| Web upload limits | No published per-file size, length or resolution limits for web uploads (only per-model API limits) | — |
| MCP tool names | Not published; the live list needs OAuth. Third parties disagree on scope | §5.7 |
| Web DoP duration | Help says 3 or 5 s; other durations for preset-based engines (Kling, MiniMax, Seedance, WAN presets in the Motion Library) are not documented | help …/how-do-i-use-dop; motion sitemap |
| API explore-page prices | Text extraction scrambled the model ↔ price pairing beyond the first 10 rows; use `/estimate` | https://open.higgsfield.ai/explore |
| Ads Studio batch | API 1–8 concepts; web "up to 20 ads per product per batch" | docs vs changelog 2026-09-30 |
| Genjutsu reference count | Web: up to 30 images. API: 1–8 (motion transfer / object swap), ≤5 (restyle) | help vs docs |

---

## Appendix A — API endpoint parameter tables (generated from the official JSON schemas, 2026-11-04)

Each table was generated mechanically from the "Complete JSON schema" block on that model's docs page. "Req" marks fields listed as `required` in the schema; some limits are enforced only at submission, as the Notes say. Every endpoint is `POST https://api.higgsfield.ai/{Endpoint ID}` and returns the shared request handle (§5.3). Outputs: video models → `video.url`; image models → `images[].url`.

#### Soul ID — Create character (training, not generation)
`POST https://api.higgsfield.ai/v1/custom-references` — source: https://docs.higgsfield.ai/docs/models/soul-id/create-character.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `name` | string | yes |  | ≤100 chars |
| `model_version` | string (enum) |  | "v1" | `v1` / `v2` / `cinema` |
| `input_images` | array of {type:"image_url", image_url:string(uri, 1–2083 chars)} | yes |  | items 1–100 |

Notes: Poll `GET /v1/custom-references/{id}`. Statuses are not_ready / queued / in_progress / completed / failed. Use the returned `id` as `custom_reference_id` on the matching Soul endpoint. References are scoped to the account. Over the training-concurrency limit you get `429` + `Retry-After`.

#### Ads Studio — Generate ads
`POST https://api.higgsfield.ai/higgsfield/ads-studio/v1.0` — source: https://docs.higgsfield.ai/docs/models/ads-studio/generate.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `niche` | string |  | "" | ≤1000 chars |
| `prompt` | string | yes |  | ≤8000 chars |
| `language` | string |  | "" | ≤80 chars |
| `batch_size` | integer |  | 1 | 1–8 |
| `image_urls` | array<string> |  | [] | items 0–10 |
| `aspect_ratio` | string |  | "1:1" | `1:1` / `4:5` / `5:4` / `16:9` / `9:16` / `4:3` / `3:4` / `21:9` / `3:2` / `2:3` / `2:1` / `1:2` / `3:1` / `1:3` |
| `target_audience` | string |  | "" | ≤2000 chars |

Notes: Submit one request with your brief. Ad concepts are prepared automatically, then rendered as images; no separate preparation or generate call is required. · batch_size selects 1–8 ad concepts. Each concept produces one image, so a fully successful batch returns batch_size images. · Rendering uses GPT Image 2.5 Flare with fixed 2k resolution and high quality. Exact dimensions depend on aspect_ratio. quality, resolution, renderer and fallback model are not public inputs. · All outputs in a batch use the requested aspect_ratio. Omitting it selects 1:1. The value auto is not supported.

#### Cinema Studio 4.0 — Generate
`POST https://api.higgsfield.ai/higgsfield/cinema-studio/4.0` — source: https://docs.higgsfield.ai/docs/models/cinema-studio-4/generate.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `era` | string |  |  | `1960s` / `1980s` / `1990s` / `2000s` / `2020s` |
| `genre` | string |  |  | `epic` / `drama` / `noir` / `comedy` / `horror` / `action` |
| `light` | string |  |  | `silhouette` / `practicals` / `window` / `overhead-fall` / `contre-jour` / `soft-cross` |
| `pacing` | string |  |  | `chaotic` / `dynamic` / `calm` / `single-shot` |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 4–30 |
| `audio_urls` | array<string(uri)> |  |  | items 0–10 |
| `image_urls` | array<string(uri)> |  |  | items 0–30 |
| `resolution` | string |  | "720p" | `480p` / `720p` |
| `video_urls` | array<string(uri)> |  |  | items 0–10 |
| `camera_lens` | string |  |  | `clean-sharp` / `anamorphic` / `vintage-anamorphic` / `warm-vintage` / `halation-vintage` |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `4:3` / `1:1` / `3:4` / `9:16` / `21:9` |
| `camera_model` | string |  |  | `modern` / `35mm-film` / `8mm-film` / `dv-camcorder` |
| `color_palette` | string |  |  | `static-noon` / `twilight-fable` / `back-row-kissing-seats` / `on-the-other-side-of-the-porthole` / `the-emerald-ambush` / `highway-standoff` / `the-faded-fresco` / `oil-ochre` / `the-mountain-convent` / `ghost-in-the-code` / `pink-velvet` / `two-days-to-the-horizon` / `industrial-fog` / `stairs-go-up` / `field-post` / `home-is-the-next-gas-station` / `glossy-flesh` / `the-crimson-ballet` / `neon-rain-at-midnight` / `the-morning-after-rain` / `the-iron-borough` / `the-ground` / `the-investigation` / `turquoise-mirage` / `a-dream-in-color` / `breakfast-on-schedule` / `favela-gold` / `a-hotel-for-one` / `after-dark` / `crimson-vigi` / `the-neighbors-saw-everything` / `the-grey-channel` / `mirage-at-noon` / `bubblegum-boulevard` / `yellow-room` / `the-earth-keeps-things-reluctantly` / `tropic-fever-dream` / `bioluminescent-night` / `dont-turn-it-off-im-watching` / `the-silk-curtain-falls` / `the-butterfly` / `playtime` / `wallpaper-romance` / `overtime` / `the-way-home-is-longer` / `everyone-speaks-in-whispers` / `runaway-summer` / `amber-wasteland` / `the-circus` / `gasoline-sunset` |
| `generate_audio` | boolean |  | true |  |
| `camera_aperture` | string |  |  | `f14-wide-open` / `f4-moderate` / `f11-deep-focus` |
| `camera_movement` | string |  |  | `snorricam` / `robot-arm` / `tilt-up` / `rack-focus` / `tilt-down` / `pov` / `pan-left` / `crane-up` / `pan-right` / `crane-down` / `side-tracking` / `pedestal-up` / `pedestal-down` / `handheld` / `tracking` / `drone-orbit` / `dolly-zoom` / `aerial-pullback` / `static-shot` / `bullet-time` / `whip-pan` / `slow-zoom-in` / `arc-left` / `slow-zoom-out` / `arc-right` / `truck-right` / `dolly-in` / `truck-left` / `dolly-out` / `slider-right` / `crush-zoom` / `slider-left` / `helicopter-shot` |

Notes: This is the public Cinema Studio 4.0 workflow. It uses text-to-video when references are absent and reference-to-video when any media array is nonempty. · Omit creative-control fields to let the director choose them automatically; the literal value "auto" is not accepted for these enum fields. · Optional prompt references use one-based tokens such as <<<image_1>>>, <<<video_1>>> and <<<audio_1>>>. Each token must refer to an attached item of the same media type. · This endpoint produces a new video. Editing and extension use the separate Seedance 2.5 endpoints. · Reference media are limited to 30 images, 10 videos and 10 audio files, with at most 50 items total. Video and audio may be normalized to separate 30-second total budgets.

#### Genjutsu — Motion transfer
`POST https://api.higgsfield.ai/higgsfield/genjutsu/motion-transfer/v1.0` — source: https://docs.higgsfield.ai/docs/models/genjutsu/motion-transfer.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string |  | "" | ≤10000 chars |
| `video_url` | string(uri) | yes |  | ≤2083 chars |
| `image_urls` | array<string(uri)> | yes |  | items 1–8 |
| `resolution` | string |  | "720p" | `720p` / `480p` / `1080p` |

Notes: Use higgsfield/genjutsu/motion-transfer/v1.0 for new integrations. The legacy endpoint higgsfiled/genjutsu/motion-transfer/v1.0 remains callable for existing clients but is hidden from model discovery. · The source video must be at least 4 seconds. Videos longer than 30 seconds are trimmed to 30 seconds; output duration follows the prepared source video. · Provide 1–8 image references. The prompt is optional and defaults to an empty string.

#### Genjutsu — Object swap
`POST https://api.higgsfield.ai/higgsfield/genjutsu/object-swap/v1.0` — source: https://docs.higgsfield.ai/docs/models/genjutsu/object-swap.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string |  | "" | ≤10000 chars |
| `video_url` | string(uri) | yes |  | ≤2083 chars |
| `image_urls` | array<string(uri)> | yes |  | items 1–8 |
| `resolution` | string |  | "720p" | `720p` / `480p` / `1080p` |

Notes: Use higgsfield/genjutsu/object-swap/v1.0 for new integrations. The legacy endpoint higgsfiled/genjutsu/object-swap/v1.0 remains callable for existing clients but is hidden from model discovery. · The source video must be at least 4 seconds. Videos longer than 30 seconds are trimmed to 30 seconds; output duration follows the prepared source video. · Provide 1–8 image references. The prompt is optional and defaults to an empty string. · The source video must contain at least 409,600 pixels per frame (width × height).

#### Genjutsu — Restyle
`POST https://api.higgsfield.ai/higgsfield/genjutsu/restyle/v1.0` — source: https://docs.higgsfield.ai/docs/models/genjutsu/restyle.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string |  | "" | ≤10000 chars |
| `preset_id` | string(uuid) | yes |  |  |
| `video_url` | string(uri) | yes |  |  |
| `image_urls` | array<string(uri)> |  | [] | items 0–5 |
| `resolution` | string |  | "720p" | `480p` / `720p` / `1080p` |

Notes: Restyle changes the visual style of a source video while retaining its motion, shot composition, and source audio. Each request produces one video. · Select a current style from GET /models/higgsfield/genjutsu/restyle/v1.0/presets and send its UUID as preset_id. The example UUID below is illustrative of a published preset; fetch the current catalog before submitting. · The source must be at least 4 seconds and no larger than 200 MiB. Videos longer than 30 seconds are trimmed to their first 30 seconds, including audio. · Character references are optional: omit image_urls or send [] to restyle the existing source subjects. Supply up to 5 character images to guide their appearance. · Defaults apply to omitted optional fields. Use [] or an empty string where appropriate; null is not accepted. · Output framing is derived from the source and animation cadence can depend on the selected style. Exact output duration and FPS may differ from the source.

#### Grok Image 2.0 — Generate and edit
`POST https://api.higgsfield.ai/xai/grok-imagine-image-2.0` — source: https://docs.higgsfield.ai/docs/models/grok-image-2/generate-and-edit.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `quality` | string |  | "medium" | `low` / `medium` |
| `image_urls` | array<string(uri)> |  |  | items 0–10 |
| `resolution` | string |  | "1k" | `1k` / `2k` |
| `aspect_ratio` | string |  | "auto" | `auto` / `1:1` / `1:2` / `2:1` / `3:2` / `2:3` / `4:3` / `3:4` / `16:9` / `9:16` |

Notes: Supports both text-to-image and editing: omit image_urls for generation, or supply up to 10 references for editing. · quality accepts low or medium only; resolution accepts 1k or 2k. aspect_ratio defaults to auto. · Reference images may be resized during preprocessing before submission. The request produces one image; no batch count is declared.

#### Grok Imagine Video 1.5 — Reference to video
`POST https://api.higgsfield.ai/xai/grok-imagine-video/v1.5/reference-to-video` — source: https://docs.higgsfield.ai/docs/models/grok-video-1-5/reference-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 1–15 |
| `audio_url` | string(uri) |  |  |  |
| `image_url` | string(uri) |  |  |  |
| `image_urls` | array<string(uri)> |  |  | items 0–7 |
| `resolution` | string |  | "480p" | `480p` / `720p` / `1080p` |
| `aspect_ratio` | string |  | "auto" | `auto` / `1:1` / `16:9` / `9:16` / `4:3` / `3:4` / `3:2` / `2:3` |

Notes: This endpoint also accepts text-only requests or one first-frame image. Choose either image_url or reference media (image_urls/audio_url); do not combine these modes. · When image_urls or audio_url is provided, resolution must be 480p or 720p. The shared schema also lists 1080p, which is rejected in reference mode. · Input images must decode as JPEG, PNG, WebP or GIF; SVG and XML are unsupported.

#### Hailuo 2.3 — Standard image to video
`POST https://api.higgsfield.ai/minimax/hailuo-2.3/standard/image-to-video` — source: https://docs.higgsfield.ai/docs/models/hailuo-2-3/standard-image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 6 | `6` / `10` |
| `image_url` | string(uri) | yes |  |  |
| `prompt_optimizer` | boolean |  | true |  |

Notes: This Standard endpoint uses a fixed 768P output resolution; resolution is not a configurable field in the production schema.

#### Hailuo 2.3 — Standard text to video
`POST https://api.higgsfield.ai/minimax/hailuo-2.3/standard/text-to-video` — source: https://docs.higgsfield.ai/docs/models/hailuo-2-3/standard-text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 6 | `6` / `10` |
| `prompt_optimizer` | boolean |  | true |  |

Notes: This Standard endpoint uses a fixed 768P output resolution; resolution is not a configurable field in the production schema.

#### HappyHorse 1.1 — Image to video
`POST https://api.higgsfield.ai/alibaba/happy-horse/v1.1/image-to-video` — source: https://docs.higgsfield.ai/docs/models/happy-horse-1-1/image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 1–2147483646 |
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 2–15 |
| `image_url` | string(uri) | yes |  |  |
| `resolution` | string |  | "1080p" | `720p` / `1080p` |

Notes: The prompt is optional. This endpoint accepts one first-frame image; it does not support a last-frame image.

#### HappyHorse 1.1 — Reference to video
`POST https://api.higgsfield.ai/alibaba/happy-horse/v1.1/reference-to-video` — source: https://docs.higgsfield.ai/docs/models/happy-horse-1-1/reference-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 1–2147483646 |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 2–15 |
| `image_urls` | array<string(uri)> | yes |  |  |
| `resolution` | string |  | "1080p" | `720p` / `1080p` |

Notes: Provide 1–9 reference images. This limit is enforced at submission even though the stored JSON Schema does not set minItems or maxItems. Reference videos are unsupported.

#### HappyHorse 1.1 — Text to video
`POST https://api.higgsfield.ai/alibaba/happy-horse/v1.1/text-to-video` — source: https://docs.higgsfield.ai/docs/models/happy-horse-1-1/text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 1–2147483646 |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 3–15 |
| `resolution` | string |  | "1080p" | `720p` / `1080p` |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` / `1:1` / `4:3` / `3:4` |

Notes: The prompt must contain text; an empty string is rejected during submission.

#### Happy Horse 1.0 — Image to video
`POST https://api.higgsfield.ai/alibaba/happy-horse/image-to-video` — source: https://docs.higgsfield.ai/docs/models/happy-horse-1/image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 1–2147483646 |
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 2–15 |
| `image_url` | string(uri) | yes |  |  |
| `resolution` | string |  | "720p" | `720p` / `1080p` |

Notes: The prompt is optional. This endpoint accepts one first-frame image; it does not support a last-frame image.

#### Happy Horse 1.0 — Reference to video
`POST https://api.higgsfield.ai/alibaba/happy-horse/reference-to-video` — source: https://docs.higgsfield.ai/docs/models/happy-horse-1/reference-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 1–2147483646 |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 2–15 |
| `image_urls` | array<string(uri)> | yes |  |  |
| `resolution` | string |  | "720p" | `720p` / `1080p` |

Notes: Provide 1–9 reference images. This limit is enforced at submission even though the stored JSON Schema does not set minItems or maxItems. Reference videos are unsupported.

#### Happy Horse 1.0 — Text to video
`POST https://api.higgsfield.ai/alibaba/happy-horse/text-to-video` — source: https://docs.higgsfield.ai/docs/models/happy-horse-1/text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 1–2147483646 |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 3–15 |
| `resolution` | string |  | "720p" | `720p` / `1080p` |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` / `1:1` / `4:3` / `3:4` |

Notes: The prompt must contain text; an empty string is rejected during submission.

#### Ideogram 4.0 — Generate
`POST https://api.higgsfield.ai/ideogram/v4.0` — source: https://docs.higgsfield.ai/docs/models/ideogram-4/generate.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  | ≤2048 chars; ≥2 chars |
| `image_url` | string(uri) |  |  |  |
| `aspect_ratio` | string |  | "1:1" | `1:1` / `1:2` / `2:1` / `2:3` / `3:2` / `4:5` / `5:4` / `9:16` / `16:9` / `5:8` / `8:5` / `3:4` / `4:3` / `9:22` / `22:9` / `9:23` / `23:9` / `3:8` / `8:3` / `5:12` / `12:5` / `1:3` / `3:1` |
| `image_weight` | integer |  |  | 1–100 |
| `rendering_speed` | string |  | "DEFAULT" | `TURBO` / `DEFAULT` / `QUALITY` |

Notes: Omit image_url for text-to-image; provide image_url for remix/editing. · image_weight controls preservation of the input image and applies to editing requests only; values are integers from 1 to 100. · The square 1:1 aspect ratio is applied by default, including when an input image is supplied. · rendering_speed values are case-sensitive: TURBO, DEFAULT, QUALITY. prompt must contain 2–2048 characters.

#### Kling 2.5 Turbo — Pro image to video
`POST https://api.higgsfield.ai/kling-video/v2.5-turbo/pro/image-to-video` — source: https://docs.higgsfield.ai/docs/models/kling-2-5-turbo/pro-image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | `5` / `10` |
| `cfg_scale` | number |  | 0.5 | 0–1; step 0.01 |
| `image_url` | string(uri) | yes |  |  |
| `negative_prompt` | string |  | "" |  |

Notes: duration accepts 5 or 10 seconds; 5 is the default. · This endpoint does not expose a sound or aspect_ratio field.

#### Kling 2.5 Turbo — Pro text to video
`POST https://api.higgsfield.ai/kling-video/v2.5-turbo/pro/text-to-video` — source: https://docs.higgsfield.ai/docs/models/kling-2-5-turbo/pro-text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | `5` / `10` |
| `cfg_scale` | number |  | 0.5 | 0–1; step 0.01 |
| `negative_prompt` | string |  | "" |  |

Notes: duration accepts 5 or 10 seconds; 5 is the default. · This endpoint does not expose a sound or aspect_ratio field.

#### Kling 2.5 Turbo — Standard image to video
`POST https://api.higgsfield.ai/kling-video/v2.5-turbo/standard/image-to-video` — source: https://docs.higgsfield.ai/docs/models/kling-2-5-turbo/standard-image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | `5` / `10` |
| `cfg_scale` | number |  | 0.5 | 0–1; step 0.01 |
| `image_url` | string(uri) | yes |  |  |
| `negative_prompt` | string |  | "" |  |

Notes: duration accepts 5 or 10 seconds; 5 is the default. · This endpoint does not expose a sound or aspect_ratio field.

#### Kling 2.6 Motion Control — Pro
`POST https://api.higgsfield.ai/kling-video/motion-control/pro` — source: https://docs.higgsfield.ai/docs/models/kling-2-6-motion-control/pro.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string |  | "" |  |
| `image_url` | string(uri) | yes |  |  |
| `video_url` | string(uri) | yes |  |  |
| `keep_original_sound` | string |  | "yes" | `yes` / `no` |
| `character_orientation` | string |  | "video" | `image` / `video` |

Notes: Use a motion-reference video from 3 to 30 seconds long. The output duration follows the source video; do not send a separate duration field. · Use a character image up to 10 MB with each dimension between 300 and 65,536 pixels. Images outside the 0.4–2.5 width-to-height range are adjusted before generation. · Videos larger than 100 MB are compressed before generation. · Set character_orientation to image or video. keep_original_sound uses the strings yes and no, with yes as the default.

#### Kling 2.6 Motion Control — Standard
`POST https://api.higgsfield.ai/kling-video/motion-control/std` — source: https://docs.higgsfield.ai/docs/models/kling-2-6-motion-control/std.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string |  | "" |  |
| `image_url` | string(uri) | yes |  |  |
| `video_url` | string(uri) | yes |  |  |
| `keep_original_sound` | string |  | "yes" | `yes` / `no` |
| `character_orientation` | string |  | "video" | `image` / `video` |

Notes: Use a motion-reference video from 3 to 30 seconds long. The output duration follows the source video; do not send a separate duration field. · Use a character image up to 10 MB with each dimension between 300 and 65,536 pixels. Images outside the 0.4–2.5 width-to-height range are adjusted before generation. · Videos larger than 100 MB are compressed before generation. · Set character_orientation to image or video. keep_original_sound uses the strings yes and no, with yes as the default.

#### Kling 2.6 — Pro image to video
`POST https://api.higgsfield.ai/kling-video/v2.6/pro/image-to-video` — source: https://docs.higgsfield.ai/docs/models/kling-2-6/pro-image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `sound` | string |  | "on" | `on` / `off` |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | `5` / `10` |
| `cfg_scale` | number |  | 0.5 | 0–1; step 0.01 |
| `image_url` | string(uri) | yes |  |  |
| `aspect_ratio` | string |  |  | `16:9` / `9:16` / `1:1` |

Notes: duration accepts 5 or 10 seconds; 5 is the default. · Native audio uses sound: on or off and defaults to on.

#### Kling 2.6 — Pro text to video
`POST https://api.higgsfield.ai/kling-video/v2.6/pro/text-to-video` — source: https://docs.higgsfield.ai/docs/models/kling-2-6/pro-text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `sound` | string |  | "on" | `on` / `off` |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | `5` / `10` |
| `cfg_scale` | number |  | 0.5 | 0–1; step 0.01 |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` / `1:1` |

Notes: duration accepts 5 or 10 seconds; 5 is the default. · Native audio uses sound: on or off and defaults to on.

#### Kling 3.0 Motion Control — Pro
`POST https://api.higgsfield.ai/kling-video/v3/motion-control/pro` — source: https://docs.higgsfield.ai/docs/models/kling-3-motion-control/pro.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string |  | "" |  |
| `image_url` | string(uri) | yes |  |  |
| `video_url` | string(uri) | yes |  |  |
| `keep_original_sound` | string |  | "yes" | `yes` / `no` |
| `character_orientation` | string |  | "video" | `image` / `video` |

Notes: Use a motion-reference video from 3 to 30 seconds long. The output duration follows the source video; do not send a separate duration field. · Use a character image up to 10 MB with each dimension between 300 and 65,536 pixels. Images outside the 0.4–2.5 width-to-height range are adjusted before generation. · Videos larger than 100 MB are compressed before generation. · Set character_orientation to image or video. keep_original_sound uses the strings yes and no, with yes as the default.

#### Kling 3.0 Motion Control — Standard
`POST https://api.higgsfield.ai/kling-video/v3/motion-control/std` — source: https://docs.higgsfield.ai/docs/models/kling-3-motion-control/std.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string |  | "" |  |
| `image_url` | string(uri) | yes |  |  |
| `video_url` | string(uri) | yes |  |  |
| `keep_original_sound` | string |  | "yes" | `yes` / `no` |
| `character_orientation` | string |  | "video" | `image` / `video` |

Notes: Use a motion-reference video from 3 to 30 seconds long. The output duration follows the source video; do not send a separate duration field. · Use a character image up to 10 MB with each dimension between 300 and 65,536 pixels. Images outside the 0.4–2.5 width-to-height range are adjusted before generation. · Videos larger than 100 MB are compressed before generation. · Set character_orientation to image or video. keep_original_sound uses the strings yes and no, with yes as the default.

#### Kling 3.0 — 4K · Image to video
`POST https://api.higgsfield.ai/kling-video/v3.0/4k/image-to-video` — source: https://docs.higgsfield.ai/docs/models/kling-3/4k-image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `sound` | string |  | "on" | `on` / `off` |
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 3–15 |
| `elements` | array<string> |  |  |  |
| `cfg_scale` | number |  | 0.5 | 0–1; step 0.01 |
| `image_url` | string(uri) | yes |  |  |
| `multi_shots` | boolean |  | false |  |
| `multi_prompt` | array of {prompt:string, duration:integer} |  |  | items 0–6 |
| `last_image_url` | string(uri) |  |  |  |

Notes: image_url is the first frame; last_image_url optionally sets the final frame. · Always include a non-empty top-level prompt, including when using multi_prompt. Keep it within 2,500 characters; longer prompts are truncated. · For custom shots, set multi_shots to true and provide 1–6 multi_prompt objects. Each object needs prompt (at most 512 characters) and duration (a positive integer from 1 to 15 seconds). · Custom-shot durations are summed for generation and billing; the top-level duration does not override that sum. With multi_shots enabled and no custom shots, the top-level duration is retained. · Native audio uses sound: on or off and defaults to on. · elements contains Kling element IDs as decimal strings. Each ID must belong to the account making the request; arbitrary provider IDs are rejected.

#### Kling 3.0 — 4K · Text to video
`POST https://api.higgsfield.ai/kling-video/v3.0/4k/text-to-video` — source: https://docs.higgsfield.ai/docs/models/kling-3/4k-text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `sound` | string |  | "on" | `on` / `off` |
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 3–15 |
| `elements` | array<string> |  |  |  |
| `cfg_scale` | number |  | 0.5 | 0–1; step 0.01 |
| `multi_shots` | boolean |  | false |  |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` / `1:1` |
| `multi_prompt` | array of {prompt:string, duration:integer} |  |  | items 0–6 |

Notes: Always include a non-empty top-level prompt, including when using multi_prompt. Keep it within 2,500 characters; longer prompts are truncated. · For custom shots, set multi_shots to true and provide 1–6 multi_prompt objects. Each object needs prompt (at most 512 characters) and duration (a positive integer from 1 to 15 seconds). · Custom-shot durations are summed for generation and billing; the top-level duration does not override that sum. With multi_shots enabled and no custom shots, the top-level duration is retained. · Native audio uses sound: on or off and defaults to on. · elements contains Kling element IDs as decimal strings. Each ID must belong to the account making the request; arbitrary provider IDs are rejected.

#### Kling 3.0 — Pro · Image to video
`POST https://api.higgsfield.ai/kling-video/v3.0/pro/image-to-video` — source: https://docs.higgsfield.ai/docs/models/kling-3/pro-image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `sound` | string |  | "on" | `on` / `off` |
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 3–15 |
| `elements` | array<string> |  |  |  |
| `cfg_scale` | number |  | 0.5 | 0–1; step 0.01 |
| `image_url` | string(uri) | yes |  |  |
| `multi_shots` | boolean |  | false |  |
| `multi_prompt` | array of {prompt:string, duration:integer} |  |  | items 0–6 |
| `last_image_url` | string(uri) |  |  |  |

Notes: image_url is the first frame; last_image_url optionally sets the final frame. · Always include a non-empty top-level prompt, including when using multi_prompt. Keep it within 2,500 characters; longer prompts are truncated. · For custom shots, set multi_shots to true and provide 1–6 multi_prompt objects. Each object needs prompt (at most 512 characters) and duration (a positive integer from 1 to 15 seconds). · Custom-shot durations are summed for generation and billing; the top-level duration does not override that sum. With multi_shots enabled and no custom shots, the top-level duration is retained. · Native audio uses sound: on or off and defaults to on. · elements contains Kling element IDs as decimal strings. Each ID must belong to the account making the request; arbitrary provider IDs are rejected.

#### Kling 3.0 — Pro · Text to video
`POST https://api.higgsfield.ai/kling-video/v3.0/pro/text-to-video` — source: https://docs.higgsfield.ai/docs/models/kling-3/pro-text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `sound` | string |  | "on" | `on` / `off` |
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 3–15 |
| `elements` | array<string> |  |  |  |
| `cfg_scale` | number |  | 0.5 | 0–1; step 0.01 |
| `multi_shots` | boolean |  | false |  |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` / `1:1` |
| `multi_prompt` | array of {prompt:string, duration:integer} |  |  | items 0–6 |

Notes: Always include a non-empty top-level prompt, including when using multi_prompt. Keep it within 2,500 characters; longer prompts are truncated. · For custom shots, set multi_shots to true and provide 1–6 multi_prompt objects. Each object needs prompt (at most 512 characters) and duration (a positive integer from 1 to 15 seconds). · Custom-shot durations are summed for generation and billing; the top-level duration does not override that sum. With multi_shots enabled and no custom shots, the top-level duration is retained. · Native audio uses sound: on or off and defaults to on. · elements contains Kling element IDs as decimal strings. Each ID must belong to the account making the request; arbitrary provider IDs are rejected.

#### Kling 3.0 — Standard · Image to video
`POST https://api.higgsfield.ai/kling-video/v3.0/std/image-to-video` — source: https://docs.higgsfield.ai/docs/models/kling-3/standard-image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `sound` | string |  | "on" | `on` / `off` |
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 3–15 |
| `elements` | array<string> |  |  |  |
| `cfg_scale` | number |  | 0.5 | 0–1; step 0.01 |
| `image_url` | string(uri) | yes |  |  |
| `multi_shots` | boolean |  | false |  |
| `multi_prompt` | array of {prompt:string, duration:integer} |  |  | items 1–6 |
| `last_image_url` | string(uri) |  |  |  |

Notes: image_url is the first frame; last_image_url optionally sets the final frame. · Always include a non-empty top-level prompt, including when using multi_prompt. Keep it within 2,500 characters; longer prompts are truncated. · For custom shots, set multi_shots to true and provide 1–6 multi_prompt objects. Each object needs prompt (at most 512 characters) and duration (a positive integer from 1 to 15 seconds). · Custom-shot durations are summed for generation and billing; the top-level duration does not override that sum. With multi_shots enabled and no custom shots, the top-level duration is retained. · Native audio uses sound: on or off and defaults to on. · elements contains Kling element IDs as decimal strings. Each ID must belong to the account making the request; arbitrary provider IDs are rejected.

#### Kling 3.0 — Standard · Text to video
`POST https://api.higgsfield.ai/kling-video/v3.0/std/text-to-video` — source: https://docs.higgsfield.ai/docs/models/kling-3/standard-text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `sound` | string |  | "on" | `on` / `off` |
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 3–15 |
| `elements` | array<string> |  |  |  |
| `cfg_scale` | number |  | 0.5 | 0–1; step 0.01 |
| `multi_shots` | boolean |  | false |  |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` / `1:1` |
| `multi_prompt` | array of {prompt:string, duration:integer} |  |  | items 1–6 |

Notes: Always include a non-empty top-level prompt, including when using multi_prompt. Keep it within 2,500 characters; longer prompts are truncated. · For custom shots, set multi_shots to true and provide 1–6 multi_prompt objects. Each object needs prompt (at most 512 characters) and duration (a positive integer from 1 to 15 seconds). · Custom-shot durations are summed for generation and billing; the top-level duration does not override that sum. With multi_shots enabled and no custom shots, the top-level duration is retained. · Native audio uses sound: on or off and defaults to on. · elements contains Kling element IDs as decimal strings. Each ID must belong to the account making the request; arbitrary provider IDs are rejected.

#### Kling 3.0 — Turbo · Image to video
`POST https://api.higgsfield.ai/kling-video/v3.0-turbo/image-to-video` — source: https://docs.higgsfield.ai/docs/models/kling-3/turbo-image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 3–15 |
| `image_url` | string(uri) | yes |  |  |
| `resolution` | string |  | "720p" | `720p` / `1080p` |

Notes: duration accepts integers from 3 to 15 seconds. resolution accepts 720p or 1080p and defaults to 720p. · This endpoint has no sound, multi_shots, elements, or last-frame field. · Keep prompt within 2,500 characters; longer prompts are truncated.

#### Kling 3.0 — Turbo · Text to video
`POST https://api.higgsfield.ai/kling-video/v3.0-turbo/text-to-video` — source: https://docs.higgsfield.ai/docs/models/kling-3/turbo-text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 3–15 |
| `resolution` | string |  | "720p" | `720p` / `1080p` |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` / `1:1` |

Notes: duration accepts integers from 3 to 15 seconds. resolution accepts 720p or 1080p and defaults to 720p. · This endpoint has no sound, multi_shots, elements, or last-frame field. · aspect_ratio accepts 16:9, 9:16, or 1:1 and defaults to 16:9. · Keep prompt within 3,072 characters; longer prompts are truncated.

#### Kling O3 — First last frame
`POST https://api.higgsfield.ai/kling-video/o3/first-last-frame` — source: https://docs.higgsfield.ai/docs/models/kling-o3/first-last-frame.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `mode` | string |  | "pro" | `std` / `pro` / `4k` |
| `sound` | string |  | "off" | `on` / `off` |
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 3–15 |
| `multi_shots` | boolean |  | false |  |
| `aspect_ratio` | string |  |  | `16:9` / `9:16` / `1:1` |
| `multi_prompt` | array of {prompt:string, duration:integer} |  |  | items 1–6 |
| `last_frame_url` | string(uri) |  |  |  |
| `first_frame_url` | string(uri) |  |  |  |

Notes: first_frame_url supplies the starting frame; last_frame_url is optional. These names differ from the image_url and last_image_url fields on Kling 3.0 image-to-video. · For a single shot, set multi_shots to false and provide prompt. For multiple shots, set multi_shots to true and provide 1–6 multi_prompt objects, each containing prompt and a positive integer duration. · Always include a non-empty top-level prompt, including when using multi_prompt. · Each shot prompt is limited to 512 characters. Custom-shot durations are summed for generation and billing; the top-level duration does not override that sum. · Native audio uses sound: on or off and defaults to off. · Keep the top-level prompt within 2,500 characters; longer prompts are truncated.

#### Kling O3 — Image reference
`POST https://api.higgsfield.ai/kling-video/o3/image-reference` — source: https://docs.higgsfield.ai/docs/models/kling-o3/image-reference.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `mode` | string |  | "std" | `std` / `pro` / `4k` |
| `sound` | string |  | "off" | `on` / `off` |
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 3–15 |
| `elements` | array<string> |  |  |  |
| `shot_type` | string |  | "customize" | `customize` / `intelligent` |
| `image_urls` | array<string(uri)> |  |  |  |
| `multi_shots` | boolean |  | false |  |
| `aspect_ratio` | string |  |  | `16:9` / `9:16` / `1:1` |
| `multi_prompt` | array of {prompt:string, duration:integer} |  |  | items 1–6 |
| `last_frame_url` | string(uri) |  |  |  |
| `first_frame_url` | string(uri) |  |  |  |

Notes: Supply image_urls for visual references. Reference images are optional in the schema. · For a single shot, set multi_shots to false and provide prompt. For multiple shots, set multi_shots to true and provide 1–6 multi_prompt objects, each containing prompt and a positive integer duration. · Always include a non-empty top-level prompt, including when using multi_prompt. · Each shot prompt is limited to 512 characters. Custom-shot durations are summed for generation and billing; the top-level duration does not override that sum. · Native audio uses sound: on or off and defaults to off. · A multi_prompt shot must last at least 1 second; zero-second shots are rejected even though the schema permits zero. · When multi_shots is true, multi_prompt is required even with shot_type set to intelligent. · Keep the top-level prompt within 2,500 characters; longer prompts are truncated. · elements contains Kling element IDs as decimal strings. Each ID must belong to the account making the request; arbitrary provider IDs are rejected.

#### Kling O3 — Video edit
`POST https://api.higgsfield.ai/kling-video/o3/video-edit` — source: https://docs.higgsfield.ai/docs/models/kling-o3/video-edit.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `mode` | string |  | "pro" | `std` / `pro` / `4k` |
| `prompt` | string | yes |  |  |
| `elements` | array<string> |  |  | items 0–4 |
| `image_urls` | array<string(uri)> |  |  | items 0–4 |
| `video_urls` | array<string(uri)> | yes |  | items 1–1 |

Notes: Supply exactly one source video from 3 to 15.5 seconds long and no larger than 200 MB. Duration is derived from the video; do not send a separate duration field. · You may also supply up to four image_urls and up to four elements. · Keep the top-level prompt within 2,500 characters; longer prompts are truncated. · elements contains Kling element IDs as decimal strings. Each ID must belong to the account making the request; arbitrary provider IDs are rejected.

#### Kling O3 — Video reference
`POST https://api.higgsfield.ai/kling-video/o3/video-reference` — source: https://docs.higgsfield.ai/docs/models/kling-o3/video-reference.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `mode` | string |  | "pro" | `std` / `pro` |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 3–10 |
| `elements` | array<string> |  |  | items 0–4 |
| `image_urls` | array<string(uri)> |  |  | items 0–4 |
| `video_urls` | array<string(uri)> | yes |  | items 1–1 |
| `aspect_ratio` | string |  |  | `16:9` / `9:16` / `1:1` |

Notes: Supply exactly one video reference. duration controls the generated clip and accepts integer values from 3 to 10 seconds. · You may also supply up to four image_urls and up to four elements. · Keep the top-level prompt within 2,500 characters; longer prompts are truncated. · elements contains Kling element IDs as decimal strings. Each ID must belong to the account making the request; arbitrary provider IDs are rejected.

#### Kling Omni — First last frame
`POST https://api.higgsfield.ai/kling-video/omni/first-last-frame` — source: https://docs.higgsfield.ai/docs/models/kling-omni/first-last-frame.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `mode` | string |  | "pro" | `std` / `pro` |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | `5` / `10` |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` / `1:1` |
| `last_frame_url` | string(uri) |  |  |  |
| `first_frame_url` | string(uri) | yes |  |  |

Notes: first_frame_url supplies the starting frame; last_frame_url is optional. These names differ from the image_url and last_image_url fields on Kling 3.0 image-to-video. · Keep the top-level prompt within 2,500 characters; longer prompts are truncated.

#### Kling Omni — Image reference
`POST https://api.higgsfield.ai/kling-video/omni/image-reference` — source: https://docs.higgsfield.ai/docs/models/kling-omni/image-reference.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `mode` | string |  | "pro" | `std` / `pro` |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 3–10 |
| `elements` | array<string> |  |  |  |
| `image_urls` | array<string(uri)> |  |  |  |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` / `1:1` |

Notes: Supply image_urls for visual references. Reference images are optional in the schema. · Keep the top-level prompt within 2,500 characters; longer prompts are truncated. · elements contains Kling element IDs as decimal strings. Each ID must belong to the account making the request; arbitrary provider IDs are rejected.

#### Kling Omni — Video edit
`POST https://api.higgsfield.ai/kling-video/omni/video-edit` — source: https://docs.higgsfield.ai/docs/models/kling-omni/video-edit.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `mode` | string |  | "pro" | `std` / `pro` |
| `prompt` | string | yes |  |  |
| `elements` | array<string> |  |  | items 0–4 |
| `image_urls` | array<string(uri)> |  |  | items 0–4 |
| `video_urls` | array<string(uri)> | yes |  | items 1–1 |

Notes: Supply exactly one source video from 3 to 10 seconds long and no larger than 200 MB. Duration is derived from the video; do not send a separate duration field. · You may also supply up to four image_urls and up to four elements. · Keep the top-level prompt within 2,500 characters; longer prompts are truncated. · elements contains Kling element IDs as decimal strings. Each ID must belong to the account making the request; arbitrary provider IDs are rejected.

#### Kling Omni — Video reference
`POST https://api.higgsfield.ai/kling-video/omni/video-reference` — source: https://docs.higgsfield.ai/docs/models/kling-omni/video-reference.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `mode` | string |  | "pro" | `std` / `pro` |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 3–10 |
| `elements` | array<string> |  |  | items 0–4 |
| `image_urls` | array<string(uri)> |  |  | items 0–4 |
| `video_urls` | array<string(uri)> | yes |  | items 1–1 |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` / `1:1` |

Notes: Supply exactly one video reference. duration controls the generated clip and accepts integer values from 3 to 10 seconds. · You may also supply up to four image_urls and up to four elements. · Keep the top-level prompt within 2,500 characters; longer prompts are truncated. · elements contains Kling element IDs as decimal strings. Each ID must belong to the account making the request; arbitrary provider IDs are rejected.

#### LTX-2.5 — Image to video fast
`POST https://api.higgsfield.ai/lightricks/ltx-2.5/image-to-video/fast` — source: https://docs.higgsfield.ai/docs/models/ltx-2-5/image-to-video-fast.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `fps` | integer |  | 25 | `24` / `25` / `48` / `50` |
| `prompt` | string | yes |  | ≤5000 chars; ≥2 chars |
| `duration` | integer | yes | 6 | `6` / `8` / `10` |
| `image_url` | string(uri) | yes |  |  |
| `resolution` | string |  | "720p" | `720p` / `1080p` / `2k` / `4k` |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` |
| `end_image_url` | string(uri) |  |  |  |
| `generate_audio` | boolean |  | true |  |
| `camera_movement` | string |  |  | `dolly_in` / `dolly_out` / `dolly_left` / `dolly_right` / `jib_up` / `jib_down` / `static` / `focus_shift` |

Notes: duration is marked required in the schema and has default 6; the API applies this top-level default before validation. The example includes it explicitly. · Fast supports 720p, 1080p, 2k or 4k and 24, 25, 48 or 50 fps. · image_url is the required first frame; end_image_url is an optional last frame. aspect_ratio explicitly controls output dimensions.

#### LTX-2.5 — Image to video pro
`POST https://api.higgsfield.ai/lightricks/ltx-2.5/image-to-video/pro` — source: https://docs.higgsfield.ai/docs/models/ltx-2-5/image-to-video-pro.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `fps` | integer |  | 25 | `24` / `25` / `50` |
| `prompt` | string | yes |  | ≤5000 chars; ≥2 chars |
| `duration` | integer | yes | 6 | `6` / `8` / `10` |
| `image_url` | string(uri) | yes |  |  |
| `resolution` | string |  | "720p" | `720p` / `1080p` |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` |
| `end_image_url` | string(uri) |  |  |  |
| `generate_audio` | boolean |  | true |  |
| `camera_movement` | string |  |  | `dolly_in` / `dolly_out` / `dolly_left` / `dolly_right` / `jib_up` / `jib_down` / `static` / `focus_shift` |

Notes: duration is marked required in the schema and has default 6; the API applies this top-level default before validation. The example includes it explicitly. · Pro supports 720p or 1080p and 24, 25 or 50 fps. Use the Fast endpoint for 2k, 4k or 48 fps. · image_url is the required first frame; end_image_url is an optional last frame. aspect_ratio explicitly controls output dimensions.

#### LTX-2.5 — Text to video fast
`POST https://api.higgsfield.ai/lightricks/ltx-2.5/text-to-video/fast` — source: https://docs.higgsfield.ai/docs/models/ltx-2-5/text-to-video-fast.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `fps` | integer |  | 25 | `24` / `25` / `48` / `50` |
| `prompt` | string | yes |  | ≤5000 chars; ≥2 chars |
| `duration` | integer | yes | 6 | `6` / `8` / `10` |
| `resolution` | string |  | "720p" | `720p` / `1080p` / `2k` / `4k` |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` |
| `generate_audio` | boolean |  | true |  |
| `camera_movement` | string |  |  | `dolly_in` / `dolly_out` / `dolly_left` / `dolly_right` / `jib_up` / `jib_down` / `static` / `focus_shift` |

Notes: duration is marked required in the schema and has default 6; the API applies this top-level default before validation. The example includes it explicitly. · Fast supports 720p, 1080p, 2k or 4k and 24, 25, 48 or 50 fps.

#### LTX-2.5 — Text to video pro
`POST https://api.higgsfield.ai/lightricks/ltx-2.5/text-to-video/pro` — source: https://docs.higgsfield.ai/docs/models/ltx-2-5/text-to-video-pro.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `fps` | integer |  | 25 | `24` / `25` / `50` |
| `prompt` | string | yes |  | ≤5000 chars; ≥2 chars |
| `duration` | integer | yes | 6 | `6` / `8` / `10` |
| `resolution` | string |  | "720p" | `720p` / `1080p` |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` |
| `generate_audio` | boolean |  | true |  |
| `camera_movement` | string |  |  | `dolly_in` / `dolly_out` / `dolly_left` / `dolly_right` / `jib_up` / `jib_down` / `static` / `focus_shift` |

Notes: duration is marked required in the schema and has default 6; the API applies this top-level default before validation. The example includes it explicitly. · Pro supports 720p or 1080p and 24, 25 or 50 fps. Use the Fast endpoint for 2k, 4k or 48 fps.

#### Marketing Studio Image — 2.5 Flare
`POST https://api.higgsfield.ai/marketing-studio/image/flare` — source: https://docs.higgsfield.ai/docs/models/marketing-studio-image/flare.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  | ≤5000 chars |
| `quality` | string |  | "high" | `low` / `medium` / `high` / `xhigh` / `max` |
| `preset_id` | string(uuid) |  |  |  |
| `image_urls` | array<string(uri)> |  |  | items 0–16 |
| `moderation` | string |  | "auto" | `auto` / `low` |
| `resolution` | string |  | "2k" | `1k` / `2k` / `4k` |
| `aspect_ratio` | string |  | "auto" | `auto` / `1:1` / `3:2` / `2:3` / `4:3` / `3:4` / `16:9` / `9:16` / `21:9` |
| `enhance_prompt` | boolean |  | false |  |

Notes: Omit image_urls for text-to-image; provide up to 16 URLs for editing when enhance_prompt=false. · enhance_prompt=true requires an existing preset_id and 1–2 image URLs: product first, optional person/model reference second. Discover presets with GET /marketing-studio/image/presets. · Reference images must be valid JPEG, PNG, or WebP. Oversized supported images are normalized before rendering. · With enhancement enabled, aspect_ratio=auto uses the preset ratio. With enhancement disabled, current production mappings use square output for auto. · The 1k/2k/4k values are resolution tiers; exact pixel dimensions depend on the aspect ratio. · quality accepts low, medium, high, xhigh, max and remains selectable with enhancement enabled.

#### Marketing Studio Image — 2.0 Alpha
`POST https://api.higgsfield.ai/marketing-studio/image` — source: https://docs.higgsfield.ai/docs/models/marketing-studio-image/generate-and-edit.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  | ≤5000 chars |
| `quality` | string |  | "high" | `low` / `medium` / `high` |
| `preset_id` | string(uuid) |  |  |  |
| `image_urls` | array<string(uri)> |  |  | items 0–16 |
| `moderation` | string |  | "auto" | `auto` / `low` |
| `resolution` | string |  | "2k" | `1k` / `2k` / `4k` |
| `aspect_ratio` | string |  | "auto" | `auto` / `1:1` / `3:2` / `2:3` / `4:3` / `3:4` / `16:9` / `9:16` / `21:9` |
| `enhance_prompt` | boolean |  | false |  |

Notes: Omit image_urls for text-to-image; provide up to 16 URLs for editing when enhance_prompt=false. · enhance_prompt=true requires an existing preset_id and 1–2 image URLs: product first, optional person/model reference second. Discover presets with GET /marketing-studio/image/presets. · Reference images must be valid JPEG, PNG, or WebP. Oversized supported images are normalized before rendering. · With enhancement enabled, aspect_ratio=auto uses the preset ratio. With enhancement disabled, current production mappings use square output for auto. · The 1k/2k/4k values are resolution tiers; exact pixel dimensions depend on the aspect ratio. · With enhance_prompt=true, quality must be high. This endpoint accepts low, medium, or high for unenhanced requests.

#### Marketing Studio Image — 2.5 Sunburst
`POST https://api.higgsfield.ai/marketing-studio/image/sunburst` — source: https://docs.higgsfield.ai/docs/models/marketing-studio-image/sunburst.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  | ≤5000 chars |
| `quality` | string |  | "high" | `low` / `medium` / `high` / `xhigh` / `max` |
| `preset_id` | string(uuid) |  |  |  |
| `image_urls` | array<string(uri)> |  |  | items 0–16 |
| `moderation` | string |  | "auto" | `auto` / `low` |
| `resolution` | string |  | "2k" | `1k` / `2k` / `4k` |
| `aspect_ratio` | string |  | "auto" | `auto` / `1:1` / `3:2` / `2:3` / `4:3` / `3:4` / `16:9` / `9:16` / `21:9` |
| `enhance_prompt` | boolean |  | false |  |

Notes: Omit image_urls for text-to-image; provide up to 16 URLs for editing when enhance_prompt=false. · enhance_prompt=true requires an existing preset_id and 1–2 image URLs: product first, optional person/model reference second. Discover presets with GET /marketing-studio/image/presets. · Reference images must be valid JPEG, PNG, or WebP. Oversized supported images are normalized before rendering. · With enhancement enabled, aspect_ratio=auto uses the preset ratio. With enhancement disabled, current production mappings use square output for auto. · The 1k/2k/4k values are resolution tiers; exact pixel dimensions depend on the aspect ratio. · quality accepts low, medium, high, xhigh, max and remains selectable with enhancement enabled.

#### MiniMax H3 — Image to video
`POST https://api.higgsfield.ai/minimax/h3/image-to-video` — source: https://docs.higgsfield.ai/docs/models/minimax-h3/image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 5–15 |
| `image_url` | string(uri) | yes |  |  |
| `resolution` | string |  | "2K" | `2K` |
| `aspect_ratio` | string |  | "auto" | `auto` / `adaptive` / `21:9` / `16:9` / `4:3` / `1:1` / `3:4` / `9:16` |
| `end_image_url` | string(uri) |  |  |  |
| `aigc_watermark` | boolean |  | false |  |

Notes: Resolution is fixed to the case-sensitive schema value "2K". The prompt must contain non-whitespace text; the current provider serializer uses only its first 7,000 characters. · The output aspect ratio follows the input keyframe even when aspect_ratio is supplied. end_image_url is an optional last frame.

#### MiniMax H3 — Reference to video
`POST https://api.higgsfield.ai/minimax/h3/reference-to-video` — source: https://docs.higgsfield.ai/docs/models/minimax-h3/reference-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 5–15 |
| `audio_urls` | array<string(uri)> |  |  | items 0–3 |
| `image_urls` | array<string(uri)> |  |  | items 1–9 |
| `resolution` | string |  | "2K" | `2K` |
| `video_urls` | array<string(uri)> |  |  | items 1–3 |
| `aspect_ratio` | string |  | "auto" | `auto` / `adaptive` / `21:9` / `16:9` / `4:3` / `1:1` / `3:4` / `9:16` |
| `aigc_watermark` | boolean |  | false |  |

Notes: Resolution is fixed to the case-sensitive schema value "2K". The prompt must contain non-whitespace text; the current provider serializer uses only its first 7,000 characters. · Provide at least one image or video reference. Audio references require an image or video reference and cannot be used alone. · Reference media may be cropped, resized, transcoded and trimmed. Video duration and audio duration are each normalized to fit within the provider's 15-second total budget.

#### MiniMax H3 — Text to video
`POST https://api.higgsfield.ai/minimax/h3/text-to-video` — source: https://docs.higgsfield.ai/docs/models/minimax-h3/text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 5–15 |
| `resolution` | string |  | "2K" | `2K` |
| `aspect_ratio` | string |  | "auto" | `auto` / `adaptive` / `21:9` / `16:9` / `4:3` / `1:1` / `3:4` / `9:16` |
| `aigc_watermark` | boolean |  | false |  |

Notes: Resolution is fixed to the case-sensitive schema value "2K". The prompt must contain non-whitespace text; the current provider serializer uses only its first 7,000 characters. · For text-only requests, aspect_ratio="auto" or "adaptive" resolves to 16:9.

#### PixVerse V6 — Image to video
`POST https://api.higgsfield.ai/pixverse/v6/image-to-video` — source: https://docs.higgsfield.ai/docs/models/pixverse-v6/image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 0–2147483647 |
| `prompt` | string | yes |  | ≤5000 chars |
| `duration` | number |  | 5 | 1–15 |
| `image_url` | string(uri) | yes |  |  |
| `resolution` | string |  | "720p" | `360p` / `540p` / `720p` / `1080p` |
| `end_image_url` | string(uri) |  |  |  |
| `generate_audio` | boolean |  | true |  |
| `negative_prompt` | string |  |  | ≤2048 chars |

Notes: duration is a number from 1 to 15, so the schema allows fractional values. If negative_prompt is supplied, it must contain 1–2,048 characters. · Use image_url for the first frame and optional end_image_url for the last frame. This endpoint has no aspect_ratio parameter; framing comes from the input image.

#### PixVerse V6 — Text to video
`POST https://api.higgsfield.ai/pixverse/v6/text-to-video` — source: https://docs.higgsfield.ai/docs/models/pixverse-v6/text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 0–2147483647 |
| `prompt` | string | yes |  | ≤5000 chars |
| `duration` | number |  | 5 | 1–15 |
| `resolution` | string |  | "720p" | `360p` / `540p` / `720p` / `1080p` |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `4:3` / `1:1` / `3:4` / `9:16` |
| `generate_audio` | boolean |  | true |  |
| `negative_prompt` | string |  |  | ≤2048 chars |

Notes: duration is a number from 1 to 15, so the schema allows fractional values. If negative_prompt is supplied, it must contain 1–2,048 characters.

#### Qwen Image 3 — Edit images
`POST https://api.higgsfield.ai/alibaba/qwen-image-3/edit` — source: https://docs.higgsfield.ai/docs/models/qwen-image-3/edit.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 0–2147483647 |
| `prompt` | string | yes |  |  |
| `image_urls` | array<string(uri)> | yes |  | items 1–3 |
| `resolution` | string |  | "1k" | `1k` / `2k` |
| `aspect_ratio` | string |  | "1:1" | `1:1` / `2:3` / `3:2` / `3:4` / `4:3` / `7:9` / `9:7` / `9:16` / `16:9` / `21:9` |
| `prompt_extend` | boolean |  | true |  |
| `enable_thinking` | boolean |  | true |  |
| `negative_prompt` | string |  |  |  |
| `prompt_extend_mode` | string |  | "direct" | `direct` |

Notes: Provide 1–3 ordered reference image URLs. The list is required and cannot be empty. · enable_thinking defaults to true and requires prompt_extend=true. Set both to false to disable enhancement. · prompt_extend_mode accepts only direct; agent enhancement is unavailable on editing requests. · prompt must contain non-whitespace text. The 2k square output tier maps to 1536 by 1536 pixels.

#### Qwen Image 3 — Text to image
`POST https://api.higgsfield.ai/alibaba/qwen-image-3/text-to-image` — source: https://docs.higgsfield.ai/docs/models/qwen-image-3/text-to-image.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 0–2147483647 |
| `prompt` | string | yes |  |  |
| `resolution` | string |  | "1k" | `1k` / `2k` |
| `aspect_ratio` | string |  | "1:1" | `1:1` / `2:3` / `3:2` / `3:4` / `4:3` / `7:9` / `9:7` / `9:16` / `16:9` / `21:9` |
| `prompt_extend` | boolean |  | true |  |
| `enable_thinking` | boolean |  | true |  |
| `negative_prompt` | string |  |  |  |
| `prompt_extend_mode` | string |  | "direct" | `direct` / `agent` |

Notes: prompt must contain non-whitespace text. The schema imposes no character maximum; its 4,500-token guidance is advisory. · enable_thinking defaults to true and requires prompt_extend=true. Set both to false to disable enhancement. · prompt_extend_mode supports direct or agent. No reference images are accepted by this endpoint. · resolution is a tier; 2k square maps to 1536 by 1536 pixels, not 2048 by 2048.

#### Recraft V4.1 Pro — Text to image
`POST https://api.higgsfield.ai/recraft/v4.1/pro/text-to-image` — source: https://docs.higgsfield.ai/docs/models/recraft-v4-1-pro/generate.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `colors` | array of {rgb:array} |  |  |  |
| `prompt` | string | yes |  | ≤10000 chars |
| `resolution` | string |  | "2k" | `2k` |
| `aspect_ratio` | string |  | "1:1" | `1:1` / `2:1` / `1:2` / `3:2` / `2:3` / `4:3` / `3:4` / `5:4` / `4:5` / `6:10` / `14:10` / `10:14` / `16:9` / `9:16` |
| `output_format` | string |  | "jpg" | `jpg` / `png` / `webp` |
| `background_color` | object {rgb:array} |  |  |  |

Notes: This variant accepts only resolution=2k; use the separate standard/Pro endpoint for the other resolution tier. · colors is an array of objects shaped as {"rgb": [R, G, B]}; background_color is one such object. Every RGB value is an integer 0–255, with exactly three entries. · output_format is jpg, png, or webp; default is jpg. No reference-image input is declared. · prompt must contain 1–10000 characters. Fourteen aspect-ratio values are listed in the schema, including 6:10, 14:10, and 10:14.

#### Recraft V4.1 Utility Pro — Text to image
`POST https://api.higgsfield.ai/recraft/v4.1/utility/pro/text-to-image` — source: https://docs.higgsfield.ai/docs/models/recraft-v4-1-utility-pro/text-to-image.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `colors` | array of {rgb:array} |  |  |  |
| `prompt` | string | yes |  | ≤10000 chars |
| `resolution` | string |  | "2k" | `2k` |
| `aspect_ratio` | string |  | "1:1" | `1:1` / `2:1` / `1:2` / `3:2` / `2:3` / `4:3` / `3:4` / `5:4` / `4:5` / `6:10` / `14:10` / `10:14` / `16:9` / `9:16` |
| `output_format` | string |  | "jpg" | `jpg` / `png` / `webp` |
| `background_color` | object {rgb:array} |  |  |  |

Notes: This variant accepts only resolution=2k; use the separate standard/Pro endpoint for the other resolution tier. · colors is an array of objects shaped as {"rgb": [R, G, B]}; background_color is one such object. Every RGB value is an integer 0–255, with exactly three entries. · output_format is jpg, png, or webp; default is jpg. No reference-image input is declared. · prompt must contain 1–10000 characters. Fourteen aspect-ratio values are listed in the schema, including 6:10, 14:10, and 10:14.

#### Recraft V4.1 Utility — Text to image
`POST https://api.higgsfield.ai/recraft/v4.1/utility/text-to-image` — source: https://docs.higgsfield.ai/docs/models/recraft-v4-1-utility/text-to-image.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `colors` | array of {rgb:array} |  |  |  |
| `prompt` | string | yes |  | ≤10000 chars |
| `resolution` | string |  | "1k" | `1k` |
| `aspect_ratio` | string |  | "1:1" | `1:1` / `2:1` / `1:2` / `3:2` / `2:3` / `4:3` / `3:4` / `5:4` / `4:5` / `6:10` / `14:10` / `10:14` / `16:9` / `9:16` |
| `output_format` | string |  | "jpg" | `jpg` / `png` / `webp` |
| `background_color` | object {rgb:array} |  |  |  |

Notes: This variant accepts only resolution=1k; use the separate standard/Pro endpoint for the other resolution tier. · colors is an array of objects shaped as {"rgb": [R, G, B]}; background_color is one such object. Every RGB value is an integer 0–255, with exactly three entries. · output_format is jpg, png, or webp; default is jpg. No reference-image input is declared. · prompt must contain 1–10000 characters. Fourteen aspect-ratio values are listed in the schema, including 6:10, 14:10, and 10:14.

#### Recraft V4.1 — Text to image
`POST https://api.higgsfield.ai/recraft/v4.1/text-to-image` — source: https://docs.higgsfield.ai/docs/models/recraft-v4-1/text-to-image.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `colors` | array of {rgb:array} |  |  |  |
| `prompt` | string | yes |  | ≤10000 chars |
| `resolution` | string |  | "1k" | `1k` |
| `aspect_ratio` | string |  | "1:1" | `1:1` / `2:1` / `1:2` / `3:2` / `2:3` / `4:3` / `3:4` / `5:4` / `4:5` / `6:10` / `14:10` / `10:14` / `16:9` / `9:16` |
| `output_format` | string |  | "jpg" | `jpg` / `png` / `webp` |
| `background_color` | object {rgb:array} |  |  |  |

Notes: This variant accepts only resolution=1k; use the separate standard/Pro endpoint for the other resolution tier. · colors is an array of objects shaped as {"rgb": [R, G, B]}; background_color is one such object. Every RGB value is an integer 0–255, with exactly three entries. · output_format is jpg, png, or webp; default is jpg. No reference-image input is declared. · prompt must contain 1–10000 characters. Fourteen aspect-ratio values are listed in the schema, including 6:10, 14:10, and 10:14.

#### Seedance 2.5 — Image to video
`POST https://api.higgsfield.ai/bytedance/seedance-2.5/image-to-video` — source: https://docs.higgsfield.ai/docs/models/seedance-2-5/image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 4–30 |
| `image_url` | string(uri) | yes |  |  |
| `resolution` | string |  | "720p" | `480p` / `720p` / `1080p` |
| `bitrate_mode` | string |  | "high" | `standard` / `high` |
| `end_image_url` | string(uri) |  |  |  |
| `generate_audio` | boolean |  | true |  |

Notes: Use publicly accessible media URLs; asset:// references are rejected for these endpoints. · The prompt is optional. Output framing follows image_url; end_image_url is the optional last frame.

#### Seedance 2.5 — Reference to video
`POST https://api.higgsfield.ai/bytedance/seedance-2.5/reference-to-video` — source: https://docs.higgsfield.ai/docs/models/seedance-2-5/reference-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 4–30 |
| `audio_urls` | array<string(uri)> |  |  | items 1–10 |
| `image_urls` | array<string(uri)> |  |  | items 1–30 |
| `resolution` | string |  | "720p" | `480p` / `720p` / `1080p` |
| `video_urls` | array<string(uri)> |  |  | items 1–10 |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `4:3` / `1:1` / `3:4` / `9:16` / `21:9` |
| `bitrate_mode` | string |  | "high" | `standard` / `high` |
| `generate_audio` | boolean |  | true |  |

Notes: Use publicly accessible media URLs; asset:// references are rejected for these endpoints. · Provide at least one nonempty reference array: image_urls, video_urls or audio_urls. Audio-only references are supported by this schema and preprocessing path. · Reference media are limited to 30 images, 10 videos and 10 audio files, with at most 50 items total. Video duration and audio duration are normalized separately to at most 30 seconds total per media type.

#### Seedance 2.5 — Text to video
`POST https://api.higgsfield.ai/bytedance/seedance-2.5/text-to-video` — source: https://docs.higgsfield.ai/docs/models/seedance-2-5/text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 4–30 |
| `resolution` | string |  | "720p" | `480p` / `720p` / `1080p` |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `4:3` / `1:1` / `3:4` / `9:16` / `21:9` |
| `bitrate_mode` | string |  | "high" | `standard` / `high` |
| `output_format` | string |  | "mp4" | `mp4` / `mov` |
| `generate_audio` | boolean |  | true |  |

Notes: Use publicly accessible media URLs; asset:// references are rejected for these endpoints. · Provide a nonblank prompt. This endpoint does not use media inputs; use the image-to-video or reference-to-video endpoint instead.

#### Seedance 2.5 — Video edit
`POST https://api.higgsfield.ai/bytedance/seedance-2.5/video-edit` — source: https://docs.higgsfield.ai/docs/models/seedance-2-5/video-edit.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `video_url` | string(uri) | yes |  |  |
| `audio_urls` | array<string(uri)> |  |  | items 1–10 |
| `image_urls` | array<string(uri)> |  |  | items 1–30 |
| `resolution` | string |  | "720p" | `480p` / `720p` / `1080p` |
| `video_urls` | array<string(uri)> |  |  | items 1–10 |
| `bitrate_mode` | string |  | "high" | `standard` / `high` |
| `generate_audio` | boolean |  | true |  |

Notes: Use publicly accessible media URLs; asset:// references are rejected for these endpoints. · The source video_url counts toward the 10-video limit, so include at most 9 additional video_urls. At most 50 media items are accepted across the source video and all reference arrays. · Videos and audio may be trimmed or padded during preprocessing to fit their respective 30-second total budgets. Output framing follows the source video. · Do not send duration: this endpoint derives output duration from the processed source video. The main video is normalized to at least 4 seconds.

#### Seedance 2.5 — Video extend
`POST https://api.higgsfield.ai/bytedance/seedance-2.5/video-extend` — source: https://docs.higgsfield.ai/docs/models/seedance-2-5/video-extend.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 4–30 |
| `video_url` | string(uri) | yes |  |  |
| `audio_urls` | array<string(uri)> |  |  | items 1–10 |
| `image_urls` | array<string(uri)> |  |  | items 1–30 |
| `resolution` | string |  | "720p" | `480p` / `720p` / `1080p` |
| `video_urls` | array<string(uri)> |  |  | items 1–10 |
| `bitrate_mode` | string |  | "high" | `standard` / `high` |
| `generate_audio` | boolean |  | true |  |

Notes: Use publicly accessible media URLs; asset:// references are rejected for these endpoints. · The source video_url counts toward the 10-video limit, so include at most 9 additional video_urls. At most 50 media items are accepted across the source video and all reference arrays. · Videos and audio may be trimmed or padded during preprocessing to fit their respective 30-second total budgets. Output framing follows the source video. · duration is an integer from 4 to 30 seconds, with default 5.

#### Seedance 2.0 — Image to video
`POST https://api.higgsfield.ai/bytedance/seedance-2.0/image-to-video` — source: https://docs.higgsfield.ai/docs/models/seedance-2/image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 4–15 |
| `image_url` | string(uri) | yes |  |  |
| `resolution` | string |  | "720p" | `480p` / `720p` / `1080p` / `4k` |
| `end_image_url` | string(uri) |  |  |  |
| `generate_audio` | boolean |  | true |  |

Notes: Use publicly accessible media URLs; asset:// references are rejected for these endpoints. · The prompt is optional. Output framing follows image_url; end_image_url is the optional last frame.

#### Seedance 2.0 — Reference to video
`POST https://api.higgsfield.ai/bytedance/seedance-2.0/reference-to-video` — source: https://docs.higgsfield.ai/docs/models/seedance-2/reference-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 4–15 |
| `audio_urls` | array<string(uri)> |  |  | items 1–3 |
| `image_urls` | array<string(uri)> |  |  | items 1–9 |
| `resolution` | string |  | "720p" | `480p` / `720p` / `1080p` / `4k` |
| `video_urls` | array<string(uri)> |  |  | items 1–3 |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `4:3` / `1:1` / `3:4` / `9:16` / `21:9` |
| `generate_audio` | boolean |  | true |  |

Notes: Use publicly accessible media URLs; asset:// references are rejected for these endpoints. · Provide a nonempty image_urls or video_urls array. Audio alone does not satisfy the reference requirement. Do not mix reference arrays with image_url, end_image_url or video_url. · Reference videos may be resized, transcoded and trimmed to 15 seconds each. Reference audio is normalized to 2–15 seconds per file and at most 15 seconds total.

#### Seedance 2.0 — Text to video
`POST https://api.higgsfield.ai/bytedance/seedance-2.0/text-to-video` — source: https://docs.higgsfield.ai/docs/models/seedance-2/text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 4–15 |
| `resolution` | string |  | "720p" | `480p` / `720p` / `1080p` / `4k` |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `4:3` / `1:1` / `3:4` / `9:16` / `21:9` |
| `generate_audio` | boolean |  | true |  |

Notes: Use publicly accessible media URLs; asset:// references are rejected for these endpoints. · Provide a nonblank prompt. This endpoint does not use media inputs; use the image-to-video or reference-to-video endpoint instead.

#### SOUL V2 — Text to image
`POST https://api.higgsfield.ai/higgsfield-ai/soul/v2/standard` — source: https://docs.higgsfield.ai/docs/models/soul-2/generate.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `aspect_ratio` | string |  | "1:1" | `9:16` / `16:9` / `4:3` / `3:4` / `1:1` / `2:3` / `3:2` |
| `resolution` | string |  | "720p" | `720p` / `1080p` |
| `enhance_prompt` | boolean |  | false |  |
| `custom_reference_id` | string|null |  | null |  |
| `custom_reference_strength` | number |  | 1.0 | 0–1 |
| `style_id` | string(uuid) |  | "3db34ab5-3439-4317-9e03-08dc30852e69" |  |
| `style_strength` | number |  | 1.0 | 0–1 |
| `seed` | integer |  |  | 1–1000000 |
| `batch_size` | integer |  | 1 | `1` / `4` |

Notes: batch_size is 1 or 4 only. A custom_reference_id must belong to the calling account and have completed training. · aspect_ratio defaults to 1:1 and enhance_prompt defaults to false. seed defaults to a random integer from 1 to 1000000; explicit null is invalid. · style_id defaults to 3db34ab5-3439-4317-9e03-08dc30852e69. style_strength is accepted by the request schema but currently has no effect on generation. · Short prompts using the general style can be enhanced automatically even when enhance_prompt=false. · When using custom_reference_id, set custom_reference_strength to a value greater than 0 and no greater than 1. The schema accepts 0, but the current runtime fails to process it for a character reference.

#### SOUL Cinema — Text to image
`POST https://api.higgsfield.ai/higgsfield-ai/soul/cinema` — source: https://docs.higgsfield.ai/docs/models/soul-cinema/generate.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `aspect_ratio` | string |  | "1:1" | `9:16` / `16:9` / `4:3` / `3:4` / `1:1` / `2:3` / `3:2` |
| `enhance_prompt` | boolean |  | false |  |
| `resolution` | string |  | "720p" | `720p` / `1080p` |
| `custom_reference_id` | string|null |  | null |  |
| `custom_reference_strength` | number |  | 1.0 | 0–1 |
| `seed` | integer |  |  | 1–1000000 |
| `batch_size` | integer |  | 1 | `1` / `4` |

Notes: batch_size is 1 or 4 only. A custom_reference_id must belong to the calling account and have completed training. · aspect_ratio defaults to 1:1 and enhance_prompt defaults to false. seed defaults to a random integer from 1 to 1000000; explicit null is invalid. · Providing a custom_reference_id enables prompt enhancement for the character reference, even if enhance_prompt is false. · Cinema uses a fixed style; client-supplied style_id is ignored. · This model may be absent from model discovery; authorized requests can use the endpoint ID directly.

#### SOUL — Text to image
`POST https://api.higgsfield.ai/higgsfield-ai/soul/standard` — source: https://docs.higgsfield.ai/docs/models/soul-standard/generate.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `aspect_ratio` | string |  | "4:3" | `9:16` / `16:9` / `4:3` / `3:4` / `1:1` / `2:3` / `3:2` |
| `enhance_prompt` | boolean |  | false |  |
| `style_id` | string(uuid) |  | "464ea177-8d40-4940-8d9d-b438bab269c7" |  |
| `style_strength` | number |  | 1.0 | 0–1 |
| `resolution` | string |  | "720p" | `720p` / `1080p` |
| `seed` | integer|null |  | null |  |
| `custom_reference_id` | string|null |  | null |  |
| `custom_reference_strength` | number |  | 1.0 | 0–1 |
| `image_reference_url` | string|null |  | null |  |
| `batch_size` | integer |  | 1 | `1` / `4` |

Notes: batch_size is 1 or 4 only. A custom_reference_id must belong to the calling account and have completed training. · aspect_ratio defaults to 4:3; enhance_prompt defaults to false; style_id defaults to 464ea177-8d40-4940-8d9d-b438bab269c7. · Optional image_reference_url guides prompt enhancement; it is distinct from custom_reference_id for a trained character. · seed may be omitted or null; generation selects a random seed when it is absent. · Short prompts using the general style can be enhanced automatically even when enhance_prompt=false. · custom_reference_strength=0 uses the selected style's default character strength; it does not disable the character reference.

#### Wan 2.6 — Image to video
`POST https://api.higgsfield.ai/wan/v2.6/image-to-video` — source: https://docs.higgsfield.ai/docs/models/wan-2-6/image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | -1–10000000 |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | `5` / `10` / `15` |
| `audio_url` | string(uri) |  |  |  |
| `image_url` | string(uri) | yes |  |  |
| `resolution` | string |  | "720p" | `480p` / `720p` / `1080p` |
| `multi_shots` | boolean |  | false |  |
| `prompt_extend` | boolean |  | false |  |
| `negative_prompt` | string |  | "" |  |

Notes: Setting multi_shots=true also enables prompt_extend, even if prompt_extend was false. · Input images may be resized to fit a 1,440-pixel maximum dimension before generation. A last-frame input is unsupported.

#### Wan 2.6 — Reference to video
`POST https://api.higgsfield.ai/wan/v2.6/reference-to-video` — source: https://docs.higgsfield.ai/docs/models/wan-2-6/reference-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | `5` / `10` |
| `resolution` | string |  | "720p" | `720p` / `1080p` |
| `video_urls` | array<string(uri)> | yes |  | items 1–3 |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` / `1:1` / `4:3` / `3:4` |

Notes: Supply 1–3 reference videos. This endpoint supports only 5 or 10 seconds, unlike the text and image endpoints that also support 15 seconds.

#### Wan 2.6 — Text to video
`POST https://api.higgsfield.ai/wan/v2.6/text-to-video` — source: https://docs.higgsfield.ai/docs/models/wan-2-6/text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | -1–10000000 |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | `5` / `10` / `15` |
| `audio_url` | string(uri) |  |  |  |
| `resolution` | string |  | "720p" | `720p` / `1080p` |
| `multi_shots` | boolean |  | false |  |
| `prompt_extend` | boolean |  | false |  |

Notes: Setting multi_shots=true also enables prompt_extend, even if prompt_extend was false.

#### Wan 2.7 — Image to video
`POST https://api.higgsfield.ai/wan/v2.7/image-to-video` — source: https://docs.higgsfield.ai/docs/models/wan-2-7/image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 1–2147483646 |
| `prompt` | string |  |  |  |
| `duration` | integer |  | 5 | 2–15 |
| `audio_url` | string(uri) |  |  |  |
| `image_url` | string(uri) | yes |  |  |
| `resolution` | string |  | "720p" | `720p` / `1080p` |
| `end_image_url` | string(uri) |  |  |  |
| `prompt_extend` | boolean |  | false |  |
| `negative_prompt` | string |  | "" |  |

Notes: The prompt is optional. end_image_url supplies a last frame, and audio_url can supply driving audio.

#### Wan 2.7 — Reference to video
`POST https://api.higgsfield.ai/wan/v2.7/reference-to-video` — source: https://docs.higgsfield.ai/docs/models/wan-2-7/reference-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 1–2147483646 |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 2–10 |
| `image_urls` | array<string(uri)> |  |  |  |
| `resolution` | string |  | "720p" | `720p` / `1080p` |
| `video_urls` | array<string(uri)> |  |  |  |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` |
| `prompt_extend` | boolean |  | false |  |
| `negative_prompt` | string |  | "" |  |

Notes: Provide a nonempty image_urls or video_urls array. The combined number of image and video references must not exceed 5; this submission limit is not expressed in the stored JSON Schema. · Reference generation is limited to 2–10 seconds and aspect ratios 16:9 or 9:16.

#### Wan 2.7 — Text to video
`POST https://api.higgsfield.ai/wan/v2.7/text-to-video` — source: https://docs.higgsfield.ai/docs/models/wan-2-7/text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 1–2147483646 |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 2–15 |
| `audio_url` | string(uri) |  |  |  |
| `resolution` | string |  | "720p" | `720p` / `1080p` |
| `aspect_ratio` | string |  | "16:9" | `16:9` / `9:16` / `1:1` / `4:3` / `3:4` |
| `prompt_extend` | boolean |  | false |  |
| `negative_prompt` | string |  | "" |  |

Notes: The prompt must contain text. audio_url can supply driving audio.

#### Wan 3.0 Prime — Image to video
`POST https://api.higgsfield.ai/alibaba/wan-3.0-prime/image-to-video` — source: https://docs.higgsfield.ai/docs/models/wan-3-prime/image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 0–2147483647 |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 2–30 |
| `image_url` | string(uri) | yes |  |  |
| `resolution` | string |  | "1080p" | `480p` / `720p` / `1080p` |
| `aspect_ratio` | string |  | "adaptive" | `16:9` / `4:3` / `1:1` / `3:4` / `9:16` / `adaptive` |
| `end_image_url` | string(uri) |  |  |  |
| `generate_audio` | boolean |  | true |  |
| `enable_thinking` | boolean |  | false |  |

Notes: Use image_url for the first frame and optional end_image_url for the last frame. Reference arrays belong to the reference-to-video endpoint. · The schema accepts seed=0, but the current implementation only forwards a nonzero seed.

#### Wan 3.0 Prime — Reference to video
`POST https://api.higgsfield.ai/alibaba/wan-3.0-prime/reference-to-video` — source: https://docs.higgsfield.ai/docs/models/wan-3-prime/reference-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 0–2147483647 |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 2–30 |
| `file_url` | string(uri) |  |  |  |
| `link_url` | string(uri) |  |  |  |
| `audio_urls` | array<string(uri)> |  |  | items 0–5 |
| `image_urls` | array<string(uri)> |  |  | items 0–10 |
| `resolution` | string |  | "1080p" | `480p` / `720p` / `1080p` |
| `video_urls` | array<string(uri)> |  |  | items 0–5 |
| `aspect_ratio` | string |  | "adaptive" | `16:9` / `4:3` / `1:1` / `3:4` / `9:16` / `adaptive` |
| `generate_audio` | boolean |  | true |  |
| `enable_thinking` | boolean |  | false |  |

Notes: Reference media are optional in the stored schema: only prompt is required. The example includes an image to demonstrate reference mode. · Send either file_url or link_url. A document or web-page reference automatically enables thinking; when both are sent, file_url takes precedence. · Reference video clips must be 1–30 seconds each and total at most 30 seconds. Reference audio must be WAV or MP3 and total at most 30 seconds, as specified in the production schema. · The schema accepts seed=0, but the current implementation only forwards a nonzero seed.

#### Wan 3.0 Prime — Text to video
`POST https://api.higgsfield.ai/alibaba/wan-3.0-prime/text-to-video` — source: https://docs.higgsfield.ai/docs/models/wan-3-prime/text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 0–2147483647 |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 2–30 |
| `resolution` | string |  | "1080p" | `480p` / `720p` / `1080p` |
| `aspect_ratio` | string |  | "adaptive" | `16:9` / `4:3` / `1:1` / `3:4` / `9:16` / `adaptive` |
| `generate_audio` | boolean |  | true |  |
| `enable_thinking` | boolean |  | false |  |

Notes: This endpoint generates from text; use the separate image or reference endpoint for media inputs. · The schema accepts seed=0, but the current implementation only forwards a nonzero seed.

#### Wan 3.0 — Image to video
`POST https://api.higgsfield.ai/alibaba/wan-3.0/image-to-video` — source: https://docs.higgsfield.ai/docs/models/wan-3/image-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 0–2147483647 |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 2–30 |
| `image_url` | string(uri) | yes |  |  |
| `resolution` | string |  | "1080p" | `480p` / `720p` / `1080p` |
| `aspect_ratio` | string |  | "adaptive" | `16:9` / `4:3` / `1:1` / `3:4` / `9:16` / `adaptive` |
| `end_image_url` | string(uri) |  |  |  |
| `generate_audio` | boolean |  | true |  |
| `enable_thinking` | boolean |  | false |  |

Notes: Use image_url for the first frame and optional end_image_url for the last frame. Reference arrays belong to the reference-to-video endpoint. · The schema accepts seed=0, but the current implementation only forwards a nonzero seed.

#### Wan 3.0 — Reference to video
`POST https://api.higgsfield.ai/alibaba/wan-3.0/reference-to-video` — source: https://docs.higgsfield.ai/docs/models/wan-3/reference-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 0–2147483647 |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 2–30 |
| `file_url` | string(uri) |  |  |  |
| `link_url` | string(uri) |  |  |  |
| `audio_urls` | array<string(uri)> |  |  | items 0–5 |
| `image_urls` | array<string(uri)> |  |  | items 0–10 |
| `resolution` | string |  | "1080p" | `480p` / `720p` / `1080p` |
| `video_urls` | array<string(uri)> |  |  | items 0–5 |
| `aspect_ratio` | string |  | "adaptive" | `16:9` / `4:3` / `1:1` / `3:4` / `9:16` / `adaptive` |
| `generate_audio` | boolean |  | true |  |
| `enable_thinking` | boolean |  | false |  |

Notes: Reference media are optional in the stored schema: only prompt is required. The example includes an image to demonstrate reference mode. · Send either file_url or link_url. A document or web-page reference automatically enables thinking; when both are sent, file_url takes precedence. · Reference video clips must be 1–30 seconds each and total at most 30 seconds. Reference audio must be WAV or MP3 and total at most 30 seconds, as specified in the production schema. · The schema accepts seed=0, but the current implementation only forwards a nonzero seed.

#### Wan 3.0 — Text to video
`POST https://api.higgsfield.ai/alibaba/wan-3.0/text-to-video` — source: https://docs.higgsfield.ai/docs/models/wan-3/text-to-video.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 0–2147483647 |
| `prompt` | string | yes |  |  |
| `duration` | integer |  | 5 | 2–30 |
| `resolution` | string |  | "1080p" | `480p` / `720p` / `1080p` |
| `aspect_ratio` | string |  | "adaptive" | `16:9` / `4:3` / `1:1` / `3:4` / `9:16` / `adaptive` |
| `generate_audio` | boolean |  | true |  |
| `enable_thinking` | boolean |  | false |  |

Notes: This endpoint generates from text; use the separate image or reference endpoint for media inputs. · The schema accepts seed=0, but the current implementation only forwards a nonzero seed.

#### Z-Image Turbo — Generate
`POST https://api.higgsfield.ai/z-image/turbo` — source: https://docs.higgsfield.ai/docs/models/z-image-turbo/generate.md

| Field | Type | Req | Default | Allowed / range |
|---|---|---|---|---|
| `seed` | integer |  |  | 0–2147483647 |
| `prompt` | string | yes |  | ≤800 chars |
| `resolution` | string |  | "1k" | `1k` / `2k` |
| `aspect_ratio` | string |  | "1:1" | `1:1` / `2:3` / `3:2` / `3:4` / `4:3` / `7:9` / `9:7` / `9:16` / `16:9` / `21:9` |
| `prompt_extend` | boolean |  | false |  |

Notes: Text-to-image only. prompt must contain non-whitespace text and at most 800 characters. · prompt_extend defaults to false; enabling it uses the enhanced pricing tier. · The schema accepts 1k and 2k tiers, ten aspect ratios, and an optional integer seed from 0 to 2147483647.
