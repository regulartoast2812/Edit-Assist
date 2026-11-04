# Kling AI: how it works (research for Kino)

**As of: 2026-11-04.** Researched on 2026-11-04. Most facts below come from Kling's own developer docs at `kling.ai/document-api/*` (their LLM-optimised Markdown exports; the capability map is stamped "Updated At: 2026-10-20" and the API changelog runs to 2026-10-28) and from Kling's web-app guides at `kling.ai/quickstart/*` (the Kling 4.0 guide is dated 2026-10-26).

Every fact or table names its source. Tags used:
- **[official]**: Kling docs or Kling site.
- **[official-bundle]**: legacy API reference that ships inside the official docs site's JavaScript bundle but is not linked from the docs index (`kling.ai/document-api/llms.txt`).
- **[3rd-party]**: anyone else.
- **[inferred]**: my own reasoning from official facts.

Domain note: `klingai.com` and `app.klingai.com/global/dev/...` now redirect to **`kling.ai`**. The developer docs are at `https://kling.ai/document-api/...` and the console is at `https://kling.ai/dev`. Source: HTTP 301 from `app.klingai.com/global/dev/document-api/...` to `kling.ai/document-api/...`.

---

## 0. Executive summary (what matters most for Kino)

1. **Kling 4.0 is the current flagship** (API fully available 2026-10-28). It makes 3–30 s in one generation, takes up to 15 reference assets (10 images, 5 videos, 7 elements, 3 voices), up to 10 keyframes, always-on native stereo audio, and 720p/1080p output (4K and 10-bit HDR "coming soon"). Kling 4.0 Flash (≤20 s, 720p) and video extension (up to 2 min) are "coming soon". Sources: [API updates](https://kling.ai/document-api/updates/api.md), [4.0 user manual](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official].
2. **There are two API generations, and they coexist:**
   - The **"new" design** puts the model version in the path, e.g. `POST /omni-video/kling-4.0`. It uses an API-key Bearer token, a typed `contents[]` array whose items carry custom `id`s that the prompt references as `@id`, separate `settings` and `options` objects, one shared `GET/POST /tasks` query, and statuses `submitted|processing|succeeded|failed`.
   - The **legacy design** uses `/v1/videos/...` paths with a `model_name` field. It accepts an API key or an AK/SK JWT, references assets in the prompt as `<<<image_1>>>`, and uses statuses `...|succeed|failed`.
   - Elements, voices, lip sync, avatar, effects, audio and multi-element editing are **still `/v1/...` legacy-style endpoints**.
   - Source: [Authentication](https://kling.ai/document-api/api/get-started/authentication.md), [Callbacks](https://kling.ai/document-api/api/get-started/callbacks.md), [API updates 07/15/2026](https://kling.ai/document-api/updates/api.md) [official].
3. **How files are tagged differs by surface:**
   - **Web app:** assets are auto-numbered in upload order (`@Image1`, `@Image2`, `@Video1`), and elements are called with `@` plus the element name.
   - **New API:** you give each input an `id` and write `@<id>` (e.g. `@image_1`).
   - **Legacy API:** `<<<image_1>>>`, `<<<element_1>>>`, `<<<video_1>>>`, `<<<voice_1>>>`.
   - In every case the model infers an asset's role unless the prompt states it ("@Image1 is the scene; keep its layout…"). Source: [4.0 user manual §8.3](https://kling.ai/document-api/api/usage-guide/kling-4-0.md), [Kling 4.0 web guide](https://kling.ai/quickstart/kling-4-model-user-guide) [official].
4. **The input slot decides what an asset does.** `first_frame`, `middle_frame` and `last_frame` are pixel anchors on the timeline. `refer_image` is an appearance, scene or style reference. `feature_video` is a motion or camera reference. `base_video` is the video being edited. `element` is a saved reusable character, object or scene, optionally with a bound voice. `voice` assigns a speaker voice. Source: [4.0 Omni Video](https://kling.ai/document-api/api/video/4-0/video-omni.md) [official].
5. **Practical constraints for a desktop client:**
   - The API takes **URLs** for inputs. Base64 is allowed for images but **not for videos** ("input content can be provided through URLs") [official].
   - I found **no upload endpoint**, so Kino will need to host local clips at a reachable URL [inferred].
   - Result URLs are hotlink-protected and **deleted after 30 days**.
   - Video jobs take about 1–5 min, images 20–60 s, and elements 30 s–2 min.
   - Source: [4.0 Omni Video](https://kling.ai/document-api/api/video/4-0/video-omni.md), [Kling Skills](https://kling.ai/document-api/api/get-started/kling-skills.md) [official].
6. **Classic controls are legacy-only or web-only.** The new-design endpoints have **no** `negative_prompt`, `cfg_scale`, `camera_control`, motion brush or extend fields; exclusions go into the prompt itself. Those controls survive only in the legacy endpoints, and the docs reserve several of them for old v1.x models. Source: request-body tables of every new-design endpoint [official]; legacy reference [official-bundle].

---

## 1. Models and versions

### 1.1 Video model line-up

Source: [Video Capability Map](https://kling.ai/document-api/guides/capability-map/video.md) [official, updated 2026-10-20]

| Model | Official tagline | Input | Duration | Resolution |
|---|---|---|---|---|
| **Kling 4.0** | Native 30s generation, dynamic motions, omni reference, precise control over narrative beats | Text, Image, Video | 3–30 s | 720P, 1080P, 4K* |
| Kling 3.0 Turbo | Consistently excellent results, with even better value | Text, Image | 3–15 s | 720P, 1080P |
| Kling 3.0 | Enhanced native audio, improved element consistency, multi-shot storytelling | Text, Image, Video | 3–15 s | 720P, 1080P, 4K |
| Kling 3.0 Omni | All-in-one multimodal input, voice-driven characters, native audio output with storyboards | Text, Image, Video | 3–15 s | 720P, 1080P, 4K |
| Kling O1 | Unified video model with all-in-one multimodal instructions and exceptional consistency | Text, Image, Video | 3–10 s | 720P, 1080P |
| Kling 2.6 | See the sound, hear the visual | Text, Image, Video | 5 s, 10 s | 720P, 1080P |
| Kling 2.5 Turbo | Max creativity with exceptional value | Text, Image | 5 s, 10 s | 720P, 1080P |

\* The 4.0 API endpoints accept only `720p` and `1080p` today. 4K and 10-bit HDR (1080p and 4K) are "coming soon" (see §7). Sources: [4.0 T2V](https://kling.ai/document-api/api/video/4-0/text-to-video.md), [API updates 10/28/2026](https://kling.ai/document-api/updates/api.md) [official].

**Coming soon (official):**
- **Kling 4.0 Flash**: "designed for high-frequency creative experimentation", 3–20 s, 720p only, no first/last frame, no multi-keyframes, no voice cloning, no element-bound voice. The doc bundle already contains endpoint stubs `/text-to-video/kling-4.0-flash`, `/image-to-video/kling-4.0-flash` (first frame only) and `/omni-video/kling-4.0-flash` (720p, ≤20 s, aspect ratios incl. `adaptive`). Sources: [4.0 user manual §4.5, §5.1](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official]; Flash stubs [official-bundle: `api-doc/assets/api-CcVluKgU.js`, `api-ksnKhQAR.js`, `api-Cj0XRJt5.js` on `s15-kling.klingai.com/kos/s101/nlav112918/`].
- **Kling 4.0 video extension**: "Upload a video and extend it multiple times, up to 2 minutes." Source: [4.0 user manual §4.6](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official].

**Release timeline (official API changelog unless noted).** Source: [API Updates](https://kling.ai/document-api/updates/api.md)

| Date | Event |
|---|---|
| 2025-10-20 | 2.5 Turbo (API, PRO mode); 2.5 Turbo STD mode on 2025-11-11 |
| 2025-12-15 | Kling 2.6 (native sound) and Omni-Video (O1) launched; 2.6 voice control on 2025-12-16 |
| 2025-12-22 | Motion Control (2.6) launched |
| 2026-02-25 | 3.0 and 3.0 Omni launched in the API; Elements upgraded (video-based elements, voice binding, async `advanced-custom-elements`) |
| 2026-03-04 | 3.0 Motion Control |
| 2026-04-23 | Native 4K mode (`mode: 4k`) for `kling-v3`, `kling-v3-omni` |
| 2026-06-17 | 3.0 Turbo released (new API, API-key auth only); 3.0 Omni reference video up to 15 s and 4K |
| 2026-07-15 | 3.0, 3.0 Omni, 3.0 Motion Control, 2.6, 2.6 Motion Control and 2.5 Turbo moved onto the "new API" ("legacy API will continue to be available with no current plans for deprecation") |
| 2026-10-28 | **Kling 4.0 API fully available** |

Web-side dates:
- Kling 3.0 series: announced 2026-01-31, launched 2026-02-05, opened globally 2026-03-05 [3rd-party: Baidu Baike].
- Kling 4.0 Flash preview: 2026-09-28. Full 4.0 in the app: 2026-10-15 [3rd-party: several sites, e.g. unifically.com, imaginetovideo.com]. The official web guide for 4.0 is dated 2026-10-26.

### 1.2 What each model is good at (official positioning)

- **4.0**: one-sentence generation that the model expands, long single takes (up to 30 s), Omni Reference (character, action, camera, composition and storyboard references), instruction-based video editing, "creative recreation" of existing videos, multilingual dialogue with accents, on-screen text, emojis and logos, and many styles. Source: [4.0 user manual §4, §6](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official].
  - Two web entry points: **Omni Reference** (default, most capable; also covers text-to-video and keyframes) and **Keyframes** (pixel-level anchoring, images only). Their "capabilities cannot be combined within a single generation task". Source: [Kling 4.0 web guide §2.1](https://kling.ai/quickstart/kling-4-model-user-guide) [official].
- **3.0**: native audio with multi-character "coreference" (the right character speaks the right line), 5 languages plus dialects, multi-shot up to 6 shots, start frame plus up to 3 bound elements, 3–15 s. Source: [Kling VIDEO 3.0 guide](https://kling.ai/quickstart/klingai-video-3-model-user-guide) [official].
- **3.0 Omni**: everything uploaded "treated as prompts"; video character elements with captured voice; storyboards; editing (same as O1). Source: [3.0 Omni guide](https://kling.ai/quickstart/klingai-video-3-omni-model-user-guide) [official].
- **O1**: unified reference, editing ("inpainting", add/remove/swap, restyle, weather, green screen), and "generate next/previous shot" from a 3–10 s video. Source: [VIDEO O1 guide](https://kling.ai/quickstart/klingai-video-o1-user-guide) [official].
- **3.0 Turbo**: cheaper 3.0 (T2V and first-frame I2V only), native audio. Source: [3.0 Turbo T2V](https://kling.ai/document-api/api/video/3-0-turbo/text-to-video.md) [official].
- **2.6**: first model with native sound and voice control. **2.5 Turbo**: low cost, silent. Source: [Capability Map](https://kling.ai/document-api/guides/capability-map/video.md) [official].

### 1.3 Standard vs Professional vs 4K modes

- **Legacy API:** `mode` is `std`, `pro` or `4k`. `std` is "basic mode, cost-effective… 720P", `pro` is "higher quality… 1080P", `4k` is "4K". Source: legacy text2video reference [official-bundle: `api-DvT-6iDv.js`].
- **New API:** the mode is replaced by `settings.resolution` (`720p` / `1080p` / `4k`). Pricing is per resolution. Source: [Pricing - Video](https://kling.ai/document-api/pricing/base/video.md) [official]. That std ≈ 720p and pro ≈ 1080p is [inferred] from both docs.
- **Web app:** older guides describe Standard Mode as "faster… lower inference costs… excels in portraits, animals, and scenes with significant motion" and Professional Mode as "richer details and higher inference costs". The 3.0, 3.0 Omni and 4.0 guides now just say 720p / 1080p / 4K. Sources: [Standard vs Professional guide](https://kling.ai/quickstart/how-to-choose-video-mode), [4.0 web guide](https://kling.ai/quickstart/kling-4-model-user-guide) [official].
- **"Master":** `kling-v2-master` and `kling-v2-1-master` were legacy models; "kling-v2-master currently does not support mode parameter". No Master model appears in the current capability map. Source: [API updates 2025-05-13, 2025-06-19](https://kling.ai/document-api/updates/api.md) [official].

### 1.4 Output specs per model (new API)

Sources: each model's API page [official].

| Model | Endpoint(s) | Durations (s) | Resolution enum (default) | Aspect ratio enum (default) | Audio setting |
|---|---|---|---|---|---|
| 4.0 T2V | `/text-to-video/kling-4.0` | any int 3–30 (default 10, or the duration stated in the prompt) | `720p`,`1080p` (`1080p`) | `21:9`,`16:9`,`9:16`,`1:1` (`16:9`) | none; audio-visual sync always on |
| 4.0 I2V | `/image-to-video/kling-4.0` | 3–30 (10) | `720p`,`1080p` (`1080p`) | **no field**; follows the first keyframe ("do not pass one") | none |
| 4.0 Omni | `/omni-video/kling-4.0` | 3–30 (10, or prompt, or base_video length) | `720p`,`1080p` (`1080p`) | `21:9`,`16:9`,`9:16`,`1:1`,`adaptive` (`adaptive`) | none |
| 3.0 Turbo T2V | `/text-to-video/kling-3.0-turbo` | 3–15 (5) | `720p`,`1080p` (`720p`) | `16:9`,`9:16`,`1:1` (`16:9`) | no field (billed "With Native Audio") |
| 3.0 Turbo I2V | `/image-to-video/kling-3.0-turbo` | 3–15 (5) | `720p`,`1080p` (`720p`) | follows image [inferred] | no field |
| 3.0 T2V | `/text-to-video/kling-3.0` | 3–15 (5) | `720p`,`1080p`,`4k` (`720p`) | `16:9`,`9:16`,`1:1` (`16:9`) | `settings.audio`: `native`/`off` (`off`) |
| 3.0 I2V | `/image-to-video/kling-3.0` | 3–15 (5) | `720p`,`1080p`,`4k` (`720p`) | no field | `native`/`off` (`off`) |
| 3.0 Omni | `/omni-video/kling-3.0-omni` | 3–15 (5) | `720p`,`1080p`,`4k` (`720p`) | `16:9`,`9:16`,`1:1` (`16:9`; required when there is no first frame and no reference video) | `native`/`original`/`off` (`off`) |
| O1 | `/omni-video/kling-o1` | 3–10 (5); **only 5 or 10** when first frame alone | `720p`,`1080p` (`720p`) | `16:9`,`9:16`,`1:1` (`16:9`) | `original`/`off` (`off`) |
| 2.6 T2V | `/text-to-video/kling-2.6` | 5, 10 (5) | `720p`,`1080p` (`720p`); **native audio forces 1080p** | `16:9`,`9:16`,`1:1` | `native`/`off` (`off`) |
| 2.6 I2V | `/image-to-video/kling-2.6` | 5, 10 | as above; **first+last frame forces 1080p** | no field | `native`/`off` |
| 2.5 Turbo T2V | `/text-to-video/kling-2.5-turbo` | 5, 10 | `720p`,`1080p` (`720p`) | `16:9`,`9:16`,`1:1` | none |
| 2.5 Turbo I2V | `/image-to-video/kling-2.5-turbo` | 5, 10 | `720p`,`1080p`; **first+last frame forces 1080p** | no field | none |
| Motion Control 3.0 / 2.6 | `/motion-control/kling-3.0`, `/motion-control/kling-2.6` | follows the motion video (3–30 s) | `720p`,`1080p` (`720p`) | follows inputs | `original`/`off` (`original`) |

**Frame rate.** "Supported input frame rate: 24–60 fps. Generated videos use 24 fps." This is stated for 4.0 Omni, 3.0 Omni and O1 video inputs. Sources: [4.0 Omni](https://kling.ai/document-api/api/video/4-0/video-omni.md), [3.0 Omni](https://kling.ai/document-api/api/video/3-0-omni/video-omni.md), [O1](https://kling.ai/document-api/api/video/o1/video-omni.md) [official]. FPS for the other models is not documented. See §8.

**Native audio:**
- **4.0**: "high-quality audio and two-channel stereo"; "Audio-visual synchronization and intelligent storyboarding are enabled by default… no toggle". Languages: Chinese, English, Japanese, Korean, Spanish, Portuguese, German, French, Hindi, plus accents and dialects. "the model may add subtitles and background music by default. If you don't want them, explicitly write 'no subtitles' or 'no background music'." Audio input is **voice profiles only**: "uploading background music or sound effects is not supported." Source: [4.0 user manual §4.1, §4.4, §8.7, §9.1, §10.1](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official].
- **3.0 / 3.0 Omni**: 5 languages (zh/en/ja/ko/es) plus dialects and accents; per-character dialogue. Source: [3.0 guide](https://kling.ai/quickstart/klingai-video-3-model-user-guide) [official].

---

## 2. Generation modes

### 2.1 Mode × model matrix

Source: [Video Capability Map](https://kling.ai/document-api/guides/capability-map/video.md) [official], plus each endpoint page. "✓" means supported; notes quote the map.

| Mode | 4.0 | 3.0 Turbo | 3.0 | 3.0 Omni | O1 | 2.6 | 2.5 Turbo |
|---|---|---|---|---|---|---|---|
| Text-to-video | ✓ | ✓ | ✓ | ✓ via omni endpoint | ✓ via omni endpoint | ✓ single-shot | ✓ single-shot |
| Multi-shot (one generation) | ✓ (automatic) | ✓ | ✓ | ✓ | ✓ (map) | ✗ | ✗ |
| Image-to-video (first frame) | ✓ | ✓ first frame only | ✓ | ✓ | ✓ | ✓ | ✓ |
| First + last frame | ✓ | ✗ | ✓ | ✓ | ✓ (map: "only first frame, 5s/10s" in Omni table; endpoint allows first+last with no extra refs) | ✓ 1080p, silent per map | ✓ 1080p only |
| Multi-keyframe (middle frames) | ✓ up to 10 images | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Reference images (subject/scene/style) | ✓ up to 10 | ✗ | elements only (≤3) | ✓ | ✓ | ✗ | ✗ |
| Reference video (motion/camera "feature") | ✓ up to 5, total ≤30 s | ✗ | ✗ | ✓ 1 video, 3–15.5 s | ✓ 1 video, 3–10 s | ✗ | ✗ |
| Video editing (`base_video`) | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| Elements | ✓ ≤7 (≤3 video elements) | ✗ | ✓ ≤3 (I2V) | ✓ (limits vary) | ✓ multi-image elements only | ✗ | ✗ |
| Voice reference | ✓ (direct voice or element-bound) | ✗ | via element voice [inferred from docs] | element-bound only | ✗ | ✓ ≤2 voices (I2V, 1080p, audio on) | ✗ |
| Native audio | ✓ always | ✓ | ✓ | ✓ (not with reference/base video) | ✗ (keeps original sound only) | ✓ (1080p) | ✗ |
| Motion Control | ✗ (not listed) | ✗ | ✓ (3.0 MC) | – | – | ✓ (2.6 MC) | ✗ |

Capability-map oddity: the map says 2.6 T2V/I2V "Native Audio: Not Supported", yet the 2.6 endpoints have `settings.audio: native` and the price list bills "Kling 2.6 With Native Audio". See §8.

"Global" capabilities that work with videos from any model version: Avatar, Lip Sync, Multi-element Video Editing, Video to Audio, Text to Audio. Motion Control is "Only available for Kling 3.0 and Kling 2.6 models". Source: [Capability Map](https://kling.ai/document-api/guides/capability-map/video.md) [official].

### 2.2 Text-to-video
- **4.0**: `prompt` plus `settings` (`resolution`, `aspect_ratio`, `duration`). If `duration` is omitted, the model "detects and follows the duration intent in the Prompt, for example, 'Generate a 15-second video'", otherwise 10 s. Source: [4.0 T2V](https://kling.ai/document-api/api/video/4-0/text-to-video.md) [official].
- **One-sentence generation**: "Write the subject and the event… the model will expand the simple prompt by filling in the storyline, scene blocking, and camera movements. When the description is already sufficiently clear, the model follows it faithfully." Source: [4.0 user manual §6.1](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official].

### 2.3 Image-to-video, start/end frame and keyframes
- **4.0** `/image-to-video/kling-4.0`: `contents[].type` is one of `prompt`, `first_frame`, `middle_frame`, `last_frame`, with up to 10 images. A middle frame has **no timestamp field**. Timing is written in the prompt (e.g. `0–2.1s @Image1 …`), and the guide examples use timecoded segments. Source: [4.0 I2V](https://kling.ai/document-api/api/video/4-0/image-to-video.md), [4.0 prompt guide §1.9](https://kling.ai/document-api/api/usage-guide/kling-4-0-prompt-guide.md) [official].
- **4.0 keyframe tips**:
  - "For the first frame, write out what happens next; for the last frame, write out the process that leads up to it… For each intermediate keyframe, describe what happens at that node and how the camera arrives at that position."
  - The standalone Keyframes entry "supports only images". To combine keyframes with reference videos, elements or voices, use `/omni-video/kling-4.0` (which also accepts `first_frame`, `middle_frame`, `last_frame`).
  - Source: [4.0 user manual §2.2, §8.5](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official].
- **3.x / 2.x**: `first_frame` is required, `last_frame` optional, and last-frame-only is **not supported**. The legacy API allowed `image_tail`-only on old models. Source: [3.0 I2V](https://kling.ai/document-api/api/video/3-0-omni/image-to-video.md) [official]; legacy image2video ("At least one of `image` or `image_tail` must be provided") [official-bundle: `api-CAOCbR1O.js`].
- **Web tip**: "Choose two similar images with the same theme for smoother transitions… Large differences may trigger a shot switch." The web entry is "Add End Frame" at the top right of Image to Video. Source: [Start and End Frames guide](https://kling.ai/quickstart/ai-video-start-end-frames) [official, older guide].

### 2.4 Multi-image / Elements / reference-to-video ("Omni Reference")
- **4.0 Omni** `contents[].type` values: `prompt`, `first_frame`, `middle_frame`, `last_frame`, `refer_image`, `feature_video`, `base_video`, `element`, `voice`. Limits are in §3. Source: [4.0 Omni Video](https://kling.ai/document-api/api/video/4-0/video-omni.md) [official].
- **4.0 reference types the docs teach**: multi-character, action, camera movement, composition, storyboard (a storyboard sheet as the shot-order reference: "state that you want finished-frame output — otherwise grid lines, title bars, or Chinese annotations… may appear"), and voice profile. Source: [4.0 user manual §5.2, §8.8](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official].
- **Legacy multi-image-to-video**: `/v1/videos/multi-image2video` (`kling-v1-6` only, ≤4 images, std/pro, 5/10 s). Superseded. Source: [official-bundle: `api-DbldssU8.js`].

### 2.5 Video-to-video: edit, restyle, recreate, next/previous shot
- **4.0 editing**: one `base_video` ("video to be edited"), optionally with `refer_image` or `element`. The prompt states "which video to edit, what to change, and what to preserve". Source: [4.0 user manual §2.2](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official].
- **Key wording rule**: "When you need to modify the original video itself, explicitly write 'Edit'. Using only 'Reference' may route the request into reference-based generation instead of editing." Source: [4.0 user manual §8.4](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official]. Also: "Kling uses the API endpoint path and the asset type declared in contents to determine how each input is used" (§2.2), and Omni Reference "classifies the intent of the user's prompt and routes it to the appropriate pipeline" (§2.1).
- **Edit templates (4.0 web guide)**:
  - "Edit @Video1, change … to …"
  - "Remove the person in the foreground from @Video1. Keep everything else unchanged."
  - "Edit @Video1. Replace the corgi in the video with a 3D pixel-art corgi while preserving its actions."
  - Source: [4.0 web guide §3.x](https://kling.ai/quickstart/kling-4-model-user-guide) [official].
- **O1 / 3.0 Omni edit families** (web):
  - Add / remove / swap subject; change background; restyle ("Change [@Video] to [anime / wool felt / cyberpunk / pixel art / ink wash…] style" or "to the style of [@Image1]"); color; weather; green screen.
  - "Generate [another angle/composition]".
  - "Based on [@Video], generate the next shot / previous shot".
  - "Take [@Image] as the start frame. Generate a new video following the camera movement of the [@video]".
  - "Animate the character in [@Image 1] with the same motion as the character in the [@Video]".
  - Source: [VIDEO O1 guide](https://kling.ai/quickstart/klingai-video-o1-user-guide) [official].
- **3.0 Omni base_video restrictions**: no first/last frame, no multi-shot, no native audio. **feature_video restrictions**: `multi_shot` must be true if used, and no native audio. Source: [3.0 Omni Video](https://kling.ai/document-api/api/video/3-0-omni/video-omni.md) [official].
- **Multi-element Video Editing** (point-and-click masks, any model): see §5.6.

### 2.6 Extend
- **Legacy only**: `POST /v1/videos/video-extend` (`video_id`, `prompt`, `negative_prompt`, `cfg_scale`). It adds 4–5 s per extension, up to 3 min total, and "Only videos generated by V1.0, V1.5, and V1.6 models are supported". Source: [official-bundle: `api-Cgkc33Fe.js`]; [API updates 2025-03-31](https://kling.ai/document-api/updates/api.md) [official].
- **Web (legacy models)**: an "Extend" tab at the bottom left after generation, with "Auto-Extend" (no prompt) and "Customized Extend" (prompt; "must be consistent with the main subject… unrelated text may cause a camera cut"). Source: [Extend with Prompts guide](https://kling.ai/quickstart/ai-video-extension) [official, older guide].
- **4.0**: extension up to 2 min is "coming soon". O1 and 3.0 Omni can produce a **next/previous shot** from a reference video instead (§2.5).

### 2.7 Motion Brush (legacy only)
- **Web**: select an area ("automatic selection" or "manual brushing"), draw a trajectory; up to 6 elements, plus a "Static Brush" to pin areas. Trajectory end ≈ the element's final position. "Designating a motion trajectory for objects that cannot move… will be interpreted as a camera movement path." Source: [Motion Brush guide](https://kling.ai/quickstart/how-to-animate-image-parts) [official, older guide].
- **Legacy API fields** on `/v1/videos/image2video`:
  - `static_mask` (image).
  - `dynamic_masks[]` of `{mask, trajectories[{x,y}]}`, with 2–77 points for a 5 s video and the **origin at the bottom-left** of the image, in pixels.
  - The mask aspect ratio must match the image.
  - Mutually exclusive with `image_tail` and `camera_control`.
  - Source: [official-bundle: `api-CAOCbR1O.js`].
- **Model support**: historically V1.0 (std/pro 5 s) and V1.5 PRO. Source: [API updates 2024-11-29, 2025-03-12](https://kling.ai/document-api/updates/api.md) [official]. Whether any 2.x+ model honours it is **not confirmed**; the current legacy enum lists only `kling-v2-5-turbo`, `kling-v2-6`, `kling-v3`.

### 2.8 Camera control

| Item | Values | Source |
|---|---|---|
| Web basic moves | horizontal, vertical, zoom, pan, tilt, roll | [Camera Movement guide](https://kling.ai/quickstart/ai-camera-control-guide) [official, older] |
| Web "Master Shots" | move left and zoom in, move right and zoom in, move forward and zoom up, move down and zoom out | same |
| Legacy `camera_control.type` | `simple`, `down_back`, `forward_up`, `right_turn_forward`, `left_turn_forward` | [official-bundle: `api-CAOCbR1O.js`, `api-DvT-6iDv.js`] |
| Legacy `camera_control.config` (only with `simple`) | `horizontal`, `vertical`, `pan`, `tilt`, `roll`, `zoom`, each float **[-10, 10]**; **only one non-zero** | same |
| Sign conventions | horizontal −left/+right; vertical −down/+up; pan −left/+right (y-axis); tilt −down/+up (x-axis); roll −CCW/+CW; zoom −longer focal length (narrower)/+shorter (wider) | same |
| Model support | V1.5 PRO "camera control (simple only)", V1.0 | [API updates 2025-03-12](https://kling.ai/document-api/updates/api.md) [official] |

For **current models** camera control is done **in the prompt**. The 4.0 docs list push-in, pull-out, pan, lateral movement, tracking, orbit, whip pans, handheld, and shot-scale changes at nodes; a `feature_video` can supply a camera path ("Reference the camera path and pacing of @video_1… do not carry over its people or scene"). Source: [4.0 user manual §2.2, §8.8](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official]. 2.6 Motion Control with "Character Orientation Matches Image" also offers camera moves (Zoom In, Zoom Out, Camera Up, Camera Down, Fixed Position) in the web UI. Source: [Motion Control guide](https://kling.ai/quickstart/motion-control-user-guide) [official].

### 2.9 Motion Control (reference motion)
- **Endpoints**: `/motion-control/kling-3.0`, `/motion-control/kling-2.6` (new API).
- **`contents[].type`**: `prompt`, `image` (appearance), `video` (motion), and `element` (3.0 only, ≤1).
- **`settings.character_orientation`** (**required**):
  - `image`: the motion video must be ≤10 s.
  - `video`: ≤30 s.
  - With an element, orientation always follows the video.
- **`settings.audio`**: `original` (default) or `off`. **`settings.resolution`**: `720p` (default) or `1080p`.
- **No duration field.** The output length is the usable continuous motion (≥3 s), and the result "will be shorter than the uploaded video" if the motion is hard.
- **Input rules**:
  - Image: jpg/jpeg/png, ≤50 MB, ≥300 px, 1:2.5–2.5:1. Match half-body or full-body to the video, head visible, no extreme orientations.
  - Video: mp4/mov, ≤100 MB, 340–3850 px, one continuous take, no cuts or camera movement. With several people, the largest one is used.
- Source: [Motion Control 3.0](https://kling.ai/document-api/api/video/motion-control.md), [2.6](https://kling.ai/document-api/api/video/motion-control/2-6.md) [official].
- **3.0 MC elements** use "only facial information" (not clothing or hair), so upload face close-ups or a video. Source: [Motion Control guide](https://kling.ai/quickstart/motion-control-user-guide) [official].
- **Web extras**: a Motion Library for 2.6 MC on the web. The API says "Action libraries are not currently supported". Source: [Motion Control guide](https://kling.ai/quickstart/motion-control-user-guide); [API updates 2025-12-22](https://kling.ai/document-api/updates/api.md) [official].

### 2.10 Lip sync, Avatar (talking photo), TTS
See §5.6 for fields.
- **Lip Sync** puts new audio on a video's face: identify face, then `advanced-lip-sync`; 2–60 s audio; one face per task.
- **Avatar 2.0**: image plus audio (or a TTS `audio_id`) plus an optional prompt for "actions, emotions, and camera movements"; output up to 5 min. Web: an Avatar Library of presets; upload the image or pick it "from Assets". Source: [Avatar 2.0 guide](https://kling.ai/quickstart/kling-ai-avatar-2-user-guide) [official], [Avatar API](https://kling.ai/document-api/api/video/avatar.md) [official].
- **TTS**: 1000 chars, preset voices, zh/en, speed 0.8–2.0.

### 2.11 Sound effects / audio
- **Text-to-Audio**: prompt ≤200 chars, 3.0–10.0 s.
- **Video-to-Audio**: Kling video or upload 3–20 s; `sound_effect_prompt`, `bgm_prompt` (≤200 each), `asmr_mode`.
- Source: [Text to Audio](https://kling.ai/document-api/api/video/audio-generation/text-to-audio.md), [Video to Audio](https://kling.ai/document-api/api/video/audio-generation/video-to-audio.md) [official].

### 2.12 Virtual try-on, e-commerce solutions, effects
- **Virtual Try-On 3.0** (2026-09-15): one `product_image` and one `person_image`; `keep_face`, `keep_pose`, `keep_background` (all default true). Source: [Virtual Try-on](https://kling.ai/document-api/api/ecommerce-replication/virtual-try-on.md) [official].
- **Solution APIs**:
  - AI Apparel Replicator (`/solutions/e-commerce/clothing_dupe`): replaces the garment in a viral reference video.
  - Goods Studio (`/solutions/e-commerce/goods_studio`): product video from product images and selling points.
  - Video Commerce (`/solutions/talking_agent`): character image plus script, giving a talking-head or product promo.
  - All query via `GET/POST /solutions`. Source: [API updates 08/18, 08/21, 09/07/2026](https://kling.ai/document-api/updates/api.md) [official].
- **Video Effects (templates)**: `POST /v1/videos/effects`, `effect_scene` = one of **204 single-image** and **15 dual-image** templates (e.g. `pet_skateboard`, `hug_pro`, `kiss_pro`, `heart_gesture_pro`). Templates are added and retired often. Source: [Video Effects](https://kling.ai/document-api/api/effects/video-effects.md) [official].

### 2.13 Image generation relevant to video workflows
"Kolors" naming survives only in try-on model IDs such as `kolors-virtual-try-on-v1-5`. Source: [kling.ai/llms.txt](https://kling.ai/llms.txt) [official, May-2026 snapshot].

Uses in a video workflow: make start, end or keyframes, make element views, outpaint to change the aspect ratio.

| Model | Endpoint | Notes | Source |
|---|---|---|---|
| Image 3.0 Omni / Image O1 | `POST /v1/images/omni-image` (`model_name`: `kling-image-o1` default, `kling-v3-omni`) | prompt ≤2500, refs written `<<<image_1>>>`, `image_list` + `element_list` ≤10 total, `resolution` 1k/2k/4k (4k only on 3.0 Omni), `result_type` single/series, `n` 1–9, `series_amount` 2–9 or `auto`, aspect 16:9 9:16 1:1 4:3 3:4 3:2 2:3 21:9 auto | [Omni Image](https://kling.ai/document-api/api/image/3-0-omni/image-omni.md) [official] |
| Image 3.0 / 2.1 | `POST /v1/images/generations` (`kling-v3` default, `kling-v2-1`) | `negative_prompt`, `image`, `image_reference` subject/face, `image_fidelity` (0.5), `human_fidelity` (0.45), `element_list`, 1k/2k, `n` | [Image Generation](https://kling.ai/document-api/api/image/3-0-omni/image-generation.md) [official] |
| Image 2.1 multi-image | `POST /v1/images/multi-image2image` | subject, scene and style reference | [Multi-Image to Image](https://kling.ai/document-api/api/image/2-1/multi-image-to-image.md) [official] |
| Outpainting | `POST /v1/images/editing/expand` | 1K | [Outpainting](https://kling.ai/document-api/api/image/common/outpainting.md) [official] |
| AI Multi-Shot (element views) | `POST /v1/general/ai-multi-shot` | infers other angles from a front view, 3 sets per call | [AI Multi-Shot](https://kling.ai/document-api/api/image/common/subject-completion.md), [API updates 2026-01-23](https://kling.ai/document-api/updates/api.md) [official] |
| Image recognition | `POST /v1/videos/image-recognize` | recognises subjects, faces and clothing (4 result sets) for multi-image and multi-element workflows | [Image Recognition](https://kling.ai/document-api/api/video/image-recognition.md), [API updates 2025-10-20](https://kling.ai/document-api/updates/api.md) [official] |

Image aspect ratios and resolutions per model: [Image Capability Map](https://kling.ai/document-api/guides/capability-map/image.md) [official].

---

## 3. Input files: attaching, tagging, roles, limits

### 3.1 How references are named in the prompt

| Surface | How an asset gets its handle | Prompt syntax | Source |
|---|---|---|---|
| Web app, 4.0 Omni Reference | auto-numbered by upload order | `@Image1`, `@Image2`, `@Video1` (the guide also shows `@Video 1`, `@Image 1`) | [4.0 web guide](https://kling.ai/quickstart/kling-4-model-user-guide) [official] |
| Web app, elements | element name from the library; type `@` in the input box to pick | `@Banana Cat`, `[@Little Scholar]` | [Element Library guide](https://kling.ai/quickstart/klingai-element-library-3-user-guide) [official] |
| New API (4.0) | you set `"id"` on each `contents[]` item; unique per task; required for elements and voices and when there are several `middle_frame`/`refer_image` items | `@image_1`, `@video_1`, `@element_1`; a voice with id `"1"` is written `@1` | [4.0 Omni Video](https://kling.ai/document-api/api/video/4-0/video-omni.md) [official] |
| New API (3.0 / 3.0 Omni / O1) | `id` on items; the docs also say elements can be named | "@image_1, @Zhang, @video_1"; "Avoid Element names that are substrings of each other"; "Avoid… names that overlap with content in the prompt (e.g. @gmail)" | [3.0 Omni Video](https://kling.ai/document-api/api/video/3-0-omni/video-omni.md) [official] |
| New API (2.6 I2V voices) | `voice` item with `voice_id` and `id` | "Specify a voice in the format of @xxx, such as @sweet" | [2.6 I2V](https://kling.ai/document-api/api/video/2-6/image-to-video.md) [official] |
| Legacy API (omni-video, image omni) | position in `image_list` / `element_list` / `video_list` / `voice_list` | `<<<image_1>>>`, `<<<element_1>>>`, `<<<video_1>>>`, `<<<voice_1>>>` ("same sequence as voice_list") | [official-bundle: `api-CHj5NTCb.js`, `api-DUCNE9z7.js`]; [Omni Image](https://kling.ai/document-api/api/image/3-0-omni/image-omni.md) [official] |
| Multi-element editing | fixed | `<<<video_1>>>`, `<<<image_1>>>` | [Multi-elements](https://kling.ai/document-api/api/video/multi-elements.md) [official] |

The examples in the 4.0 prompt guide use ids like `Image1` and `start`/`end` ("@start is the first frame. @end is the last frame"), so ids are free-form strings. Source: [4.0 prompt guide](https://kling.ai/document-api/api/usage-guide/kling-4-0-prompt-guide.md), [4.0 user manual §2.2](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official].

### 3.2 What each role means to the model

| Slot / type | Meaning | Source |
|---|---|---|
| `first_frame` | the video starts on this exact image ("pixel-level consistency" in the Keyframes entry). The prompt describes what happens next. | [4.0 user manual §2.2, §8.5](https://kling.ai/document-api/api/usage-guide/kling-4-0.md); [4.0 web guide §2.1](https://kling.ai/quickstart/kling-4-model-user-guide) [official] |
| `last_frame` | the video ends on this image. Describe the process leading to it ("Ensure the final frame matches the last frame reference"). | same |
| `middle_frame` (4.0) | intermediate visual node; timing is set in the prompt | [4.0 I2V](https://kling.ai/document-api/api/video/4-0/image-to-video.md) [official] |
| `refer_image` | "reference images for scenes, styles, etc." (appearance, character, product, composition or storyboard), **not** a frame | [4.0 Omni Video](https://kling.ai/document-api/api/video/4-0/video-omni.md) [official] |
| `feature_video` | "feature reference video": motion, choreography, camera path, pacing, style. It is not edited. | same |
| `base_video` | "video to be edited" (max 1). Duration and aspect default to it. | same |
| `element` | saved library subject (multi-image or video character). Keeps identity across shots; may carry a bound voice. | [4.0 Elements](https://kling.ai/document-api/api/video/4-0/elements.md) [official] |
| `voice` | speaker voice profile (`voice_id` from the custom or preset voice API). Not for music or SFX. | [4.0 user manual §9.1](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official] |

**Start frame vs reference:** a frame anchors the timeline and composition, while a reference only lends traits. "If a material is referenced without an explicit purpose, the model will infer how to use it, which may produce results that differ from your intent." Source: [4.0 T2V field notes](https://kling.ai/document-api/api/video/4-0/text-to-video.md) [official]. In 3.0 (web), binding elements to a start frame "enhances start-frame consistency… It is recommended to bind elements that appear in the start frame". Source: [Element Library guide](https://kling.ai/quickstart/klingai-element-library-3-user-guide) [official].

**Aspect-ratio and duration inference (4.0 Omni, `adaptive`)**: prompt intent first, then the `base_video` ratio, then the keyframe images (first frame preferred), then other input videos, else 16:9. Duration: prompt intent, then `base_video` duration, else 10 s. Source: [4.0 user manual §7.2–7.3](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official].

### 3.3 Limits: Kling 4.0 (API and web share these)

Sources: [4.0 Omni Video](https://kling.ai/document-api/api/video/4-0/video-omni.md), [4.0 user manual §9.1](https://kling.ai/document-api/api/usage-guide/kling-4-0.md), [4.0 web guide](https://kling.ai/quickstart/kling-4-model-user-guide) [official]

| Input | Limit |
|---|---|
| Prompt | 8,000 tokens. API: English-only ≤26,000 chars, non-English-only ≤11,000 chars, mixed must satisfy E/26000 + N/11000 ≤ 1 |
| Images (any frame or `refer_image`) | ≤10; .jpg/.jpeg/.png; ≤30 MB each; min side ≥300 px; aspect 2:5–5:2; URL or Base64 |
| Videos (`feature_video` + `base_video` + video-element source) | ≤5 clips; each and total 3–30 s; ≤300 MB each; .mp4/.mov; 700–4553 px per side; ≤8,294,400 px area; aspect 2:5–5:2; 24–60 fps input; **URL only**; ≤1 `base_video` |
| Elements | ≤7, of which ≤3 video character elements; video elements count toward the 5-clip / 30 s video quota |
| Voices | ≤3 per task; voice source audio 5–30 s; ≤50 MB per file |
| Total | ≤15 across images, videos, elements, voices |
| Keyframes-only (`/image-to-video/kling-4.0`) | ≤10 images; no other reference types |

### 3.4 Limits: other models (new API)

| Model | Images | Videos | Elements | Prompt | Source |
|---|---|---|---|---|---|
| 3.0 / 3.0 Turbo I2V | first (+last for 3.0) frame; jpg/png; ≤50 MB; ≥300 px; 1:2.5–2.5:1 | – | 3.0 I2V: ≤3 | ≤3072 chars (≤2500 recommended); multi-shot ≤512 per shot | [3.0 I2V](https://kling.ai/document-api/api/video/3-0-omni/image-to-video.md), [3.0 Turbo I2V](https://kling.ai/document-api/api/video/3-0-turbo/image-to-video.md) [official] |
| 3.0 Omni | ≤50 MB; ≥300 px; 1:2.5–2.5:1. No ref video + only multi-image elements: images + elements ≤7. No ref video + video and multi-image elements: ≤3 video elements and images + multi-image elements ≤4. With ref video + multi-image elements: ≤4. With ref video: video elements and ref images cannot be combined | 1 (feature or base); mp4/mov; ≤200 MB; 3–15.5 s; 700–4553 px; ≤8,294,400 px; aspect 0.4–2; 24–60 fps | with first/last frame: ≤3; with ref video + only video elements: ≤1 | ≤3072 | [3.0 Omni Video](https://kling.ai/document-api/api/video/3-0-omni/video-omni.md) [official] |
| O1 | ≤50 MB; ≥300 px; 1:2.5–2.5:1; images + elements ≤7 (≤4 with ref video); first+last: no extra ref images | 1; mp4/mov; ≤200 MB; 3–10 s; 700–2160 px; feature video allows first frame only | multi-image elements only; none with first+last | not stated in the new doc (legacy: ≤2500) | [O1 Video](https://kling.ai/document-api/api/video/o1/video-omni.md) [official] |
| 2.6 I2V | first (+last) frame, ≤50 MB, same ratio rule | – | – (≤2 voices) | ≤2500 | [2.6 I2V](https://kling.ai/document-api/api/video/2-6/image-to-video.md) [official] |
| 2.5 Turbo | first (+last) frame, ≤50 MB | – | – | ≤2500 | [2.5 Turbo I2V](https://kling.ai/document-api/api/video/2-5-turbo/image-to-video.md) [official] |
| Legacy `/v1/...` images | Base64 **without** a `data:` prefix, or URL; ≤10 MB; ≥300 px; 1:2.5–2.5:1 | – | – | ≤2500 | [official-bundle: `api-CAOCbR1O.js`] |

**Web (3.0 Omni / O1) wording**: "When a video is provided, a total of up to 4 images/elements can be uploaded. If no video is provided, up to 7". 3.0 Omni web videos: "one video… 3s and 10s, ≤200MB, resolution ≤2k" (older than the API's 15.5 s). Source: [3.0 Omni guide FAQ](https://kling.ai/quickstart/klingai-video-3-omni-model-user-guide) [official].

### 3.5 Elements (reusable subjects)
- **Kinds**: "Multi-Image Elements" are 1 frontal image plus 1–3 more angles (2–4 images total). "Video Character Elements" come from a 3–8 s single-character video; appearance and voice are extracted, and only "realistic-style humanoid" subjects are allowed. Categories: Characters, Animals, Props/Items, Costumes and Accessories, Scenes, Special Effects, Others. Source: [Element Library guide](https://kling.ai/quickstart/klingai-element-library-3-user-guide), [4.0 Elements API](https://kling.ai/document-api/api/video/4-0/elements.md) [official].
- **API create**: `POST /v1/general/advanced-custom-elements` (asynchronous task).

| Field | Type | Rules |
|---|---|---|
| `element_name` | string, required | ≤20 chars (web: unique in the library) |
| `element_description` | string, required | ≤100 chars |
| `reference_type` | `video_refer` \| `image_refer` | required |
| `element_image_list` | `{ "frontal_image": url, "refer_images": [{ "image_url": url }] }` | 1–3 refer images; jpg/png ≤10 MB, ≥300 px, 1:2.5–2.5:1; URL or Base64; required for `image_refer` |
| `element_video_list` | `{ "refer_videos": [{ "video_url": url }] }` | mp4/mov, 3–8 s, 1080P, 16:9 or 9:16, 1 video, ≤200 MB. Speech in it triggers voice customisation and binding. "Video-customized elements are only supported for kling-video-o3 and later models" (sic) |
| `element_voice_id` | string | bind an existing voice; character or humanoid image elements only |
| `tag_list` | `[{ "tag_id": "o_101" }]` | o_101 Hottest, o_102 Character, o_103 Animal, o_104 Item, o_105 Costume, o_106 Scene, o_107 Effect, o_108 Others |

- **Related endpoints**:
  - `GET /v1/general/advanced-custom-elements/{id}`
  - `GET /v1/general/advanced-custom-elements` (`pageNum` 1–1000, `pageSize` 1–500, default 30)
  - `GET /v1/general/advanced-presets-elements` (official library)
  - `POST /v1/general/delete-advanced-elements`
  - The older elements API is a separate library: "cannot perform cross-API queries".
  - Source: [4.0 Elements](https://kling.ai/document-api/api/video/4-0/elements.md), [API updates 2026-02-25](https://kling.ai/document-api/updates/api.md) [official].
- **Web**:
  - Element creation is free. "AI multi-view completion": members get 3 free per day, then 5 credits.
  - "AI Auto-Description" is available.
  - Library caps: non-member 30, Standard 50, Pro/Premier 150, Ultra 500.
  - Elements cannot be shared, but videos made with them can be posted to Explore and "recreated with one click".
  - Source: [Element Library guide FAQ](https://kling.ai/quickstart/klingai-element-library-3-user-guide) [official].

### 3.6 Voices
- **`POST /v1/general/custom-voices`**:
  - `voice_name` ≤20 chars.
  - Exactly one of `voice_url` (.mp3/.wav/.mp4/.mov; clean, single speaker, 5–30 s) or `video_id`. A `video_id` must point to a Kling output from 2.6 with sound on, the Avatar API, or the Lip-Sync API.
- **Other endpoints**: `GET /v1/general/custom-voices/{id}`, `GET /v1/general/custom-voices` (pageSize 1–1000), `GET /v1/general/presets-voices`, `POST /v1/general/delete-voices`.
- Source: [4.0 Voice Management](https://kling.ai/document-api/api/video/4-0/voice-customization.md) [official].
- Voice IDs for TTS and lip sync are a **different** set (preset list on docs.qingque.cn). The legacy video doc warns its voice_id is "NOT the voice_id of Lip-Sync API". Source: [TTS](https://kling.ai/document-api/api/video/avatar/text-to-speech.md) [official]; [official-bundle: `api-CAOCbR1O.js`].

---

## 4. Prompting

### 4.1 Official structure (Kling 4.0)

Source: [4.0 user manual §8.2](https://kling.ai/document-api/api/usage-guide/kling-4-0.md), [4.0 web guide §3.1](https://kling.ai/quickstart/kling-4-model-user-guide) [official]

```
[Asset Roles]      @Image1 is ___, keep its ___ consistent. @Image2 is ___ … Reference the ___ of @Video1.
[Overall Settings] Scene and texture: ___. Visual style: ___. Camera tone: ___.
[Sequence of Events] 0–X s: ___ (visuals + action + emotion)  X–Y s: ___ (camera + details)  Y s–end: ___ (closing shot)
[Audio]            Who says what / narration; ambient sounds; music; sound effects.
```

**Rules from the official guides:**
- "Write in descriptive language. Avoid abstract terms." Write "Side backlighting outlines the object's edges…", not "Premium feel".
- Start with subject, scene, action and emotion in one sentence, then add camera, timing, audio and constraints.
- Longer is "not necessarily" better.
- **Negative control**: "Prefer positive descriptions… Only two types of negative instructions are truly necessary: no subtitles and no background music." "Negative prompts can increase the likelihood of errors." For stylisation, exclude the opposite (e.g. "exclude realistic texture" for animation).
- **Editing**: "Edit @Video1. Change ___ to ___. Keep everything else unchanged."
- **Timelines**: "X–Y s｜Keyframe 1: ___".
- **Dialogue**: write it in the target language inside quotes; add age, tone, speech rate and emotion.
- **Subtitles and on-screen text**: "Specify the exact text content, position, alignment, on-screen duration, and whether it should sync with spoken dialogue."
- **Storyboards**: ask for finished frames.
- The long examples in the 4.0 guides use numbered blocks: SCENE CONTEXT, ACTIVE REFERENCES, LOCATION MAP, FIRST FRAME AND SPATIAL BLOCKING, FORMAT MODE (shot list with timecodes), CAMERA, ACTION TIMING, PHYSICS, LIGHTING, AUDIO, CHARACTER ACTING, QUALITY, Negative Constraints.
- Source: [4.0 user manual §8](https://kling.ai/document-api/api/usage-guide/kling-4-0.md), [4.0 web guide](https://kling.ai/quickstart/kling-4-model-user-guide), [4.0 prompt guide](https://kling.ai/document-api/api/usage-guide/kling-4-0-prompt-guide.md) [official].

### 4.2 Older official formulas (still useful for 2.x/3.x)
- **Text-to-video**: "Prompt = Subject (Subject Description) + Subject Movement + Scene (Scene Description) + (Camera Language + Lighting + Atmosphere)". Source: [Text-to-Video prompt guide](https://kling.ai/quickstart/text-to-video-prompt-guide) [official].
- **Image-to-video**: "Prompt = Subject + Movement, Background + Movement…". The scene already exists, so describe only the motion. Source: [Image-to-Video guide](https://kling.ai/quickstart/image-to-video-guide) [official].

### 4.3 Negative prompt, cfg / "creativity vs relevance", prompt length

| Control | New API (all current video models) | Legacy API | Source |
|---|---|---|---|
| `negative_prompt` | **No field**. "The prompt can include positive and negative descriptions." | `negative_prompt` ≤2500 chars ("recommended to supplement… via negative sentences within positive prompts"). Also on multi-elements and image 3.0/2.1 | new-API endpoint pages [official]; [official-bundle: `api-DvT-6iDv.js`] |
| `cfg_scale` | **No field** | float [0,1], default 0.5; "higher value means lower model flexibility and stronger relevance to user prompt"; "**kling-v2.x models do not support this parameter**" | [official-bundle: `api-CAOCbR1O.js`] |
| Prompt length | 4.0: 26,000 EN / 11,000 non-EN chars (8k tokens); 3.x: 3072 (2500 recommended); 2.6/2.5 Turbo: 2500; per shot: 512 | 2500 | endpoint pages [official] |

The web 1.x/2.x UI exposed "Creativity vs Relevance" (cfg) in its older "Explanation of Parameter Selection" guide. Its current presence in the UI is **not confirmed**.

### 4.4 Multi-shot / storyboard
- **3.0 / 3.0 Turbo / 3.0 Omni (new API)**: `settings.multi_shot` (default `true`). The prompt format is `"shot n, m, words; shot n, m, words;"` with ASCII semicolons: n = 1–6, m = seconds (each ≥1, sum = `duration`), words ≤512 chars. With `multi_shot: false`, a multi-shot prompt gives one shot. Source: [3.0 T2V](https://kling.ai/document-api/api/video/3-0-omni/text-to-video.md) [official].
- **Legacy**: `multi_shot` (default false), `shot_type` `customize` or `intelligence` (AI storyboarding), `multi_prompt: [{index, prompt, duration}]` (1–6 shots, ≤512 chars each, durations sum to the total). With multi_shot true, `prompt` is ignored. Source: [official-bundle: `api-DvT-6iDv.js`]. Since 2026-05-07, multi-shot can be combined with first/last frames on `kling-v3` and `kling-v3-omni`. Source: [API updates](https://kling.ai/document-api/updates/api.md) [official].
- **Web 3.0**: a "Multi-Shot" switch (AI plans the cuts) plus a "Custom Multi-Shot" button that lets you set the number of shots and each one's duration and content. Source: [3.0 guide](https://kling.ai/quickstart/klingai-video-3-model-user-guide) [official].
- **4.0**: "intelligent storyboarding" is always on; shots are written as timecoded segments in the prompt (e.g. "SHOT 1 — 0.0–4.0s…"). Source: [4.0 user manual §10.1](https://kling.ai/document-api/api/usage-guide/kling-4-0.md), [4.0 web guide](https://kling.ai/quickstart/kling-4-model-user-guide) [official].

### 4.5 Camera language it understands (from official examples)
- **Moves**: push-in, pull-out, pan, tilt, lateral or tracking shot, orbit, whip pan, handheld (breathing sway, roll, delayed corrections), dolly/stabiliser, "one continuous long take", "no cuts", "hard cut", "fade to black".
- **Shot sizes**: wide, medium, close-up, macro, POV, overhead, low-angle.
- **Moves inside a shot**: "subtle 3% push-in".
- Source: [4.0 prompt guide](https://kling.ai/document-api/api/usage-guide/kling-4-0-prompt-guide.md), [4.0 user manual §8.8](https://kling.ai/document-api/api/usage-guide/kling-4-0.md), [3.0 guide](https://kling.ai/quickstart/klingai-video-3-model-user-guide) [official].

---

## 5. Developer API

### 5.1 Access, auth, base URLs
- **Console and keys**: `https://kling.ai/dev` → API Keys (`/dev/api-key`), the same account as the web app. Create a named key; it is "only shown once". Send `Authorization: Bearer <API_KEY>`. Source: [Quick Start](https://kling.ai/document-api/guides/get-started/quick-start.md) [official].
- **API key**: "API Key (for all models)". **AK/SK JWT** is "only applicable to legacy version design standards": HS256 with `iss` = AK and `exp` / `nbf` claims (example: exp = now + 1800 s, nbf = now − 5 s), sent as `Bearer <jwt>`. The new API (3.0 Turbo onwards) is API-key only. Source: [Authentication](https://kling.ai/document-api/api/get-started/authentication.md); [API updates 2026-06-17](https://kling.ai/document-api/updates/api.md) [official].
- **Base URL (global)**: `https://api-singapore.klingai.com` ("changed from https://api.klingai.com"; for servers outside China). China: `https://api-beijing.klingai.com`. Create and query a task in the same region. Source: [Authentication](https://kling.ai/document-api/api/get-started/authentication.md) [official]; China host from [kling.ai/llms.txt](https://kling.ai/llms.txt) [official].
- **Kling 4.0 API access** needs a **Flagship resource pack** or cash balance > 0. Source: [4.0 user manual §1](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official].
- **Official agent tooling**: a "Kling AI Skill" (Node 18+, `kling.mjs`) for Claude Code, Cursor, Codex and others; `KLING_API_BASE` env var; the Kling MCP and CLI support 4.0. Source: [Kling Skills](https://kling.ai/document-api/api/get-started/kling-skills.md) [official]; MCP/CLI [3rd-party: unifically.com, myclaw.ai].

### 5.2 Endpoint inventory (as documented 2026-11-04)

All paths are relative to the base URL. "New" means version-in-path design. Source: endpoint list compiled from every page in the [docs index](https://kling.ai/document-api/llms.txt) [official], plus legacy chunks [official-bundle].

| Area | Method + path | Design |
|---|---|---|
| 4.0 T2V / I2V / Omni | `POST /text-to-video/kling-4.0`, `POST /image-to-video/kling-4.0`, `POST /omni-video/kling-4.0` | New |
| 3.0 Turbo | `POST /text-to-video/kling-3.0-turbo`, `POST /image-to-video/kling-3.0-turbo` | New |
| 3.0 | `POST /text-to-video/kling-3.0`, `POST /image-to-video/kling-3.0` | New |
| 3.0 Omni | `POST /omni-video/kling-3.0-omni` | New |
| O1 | `POST /omni-video/kling-o1` | New |
| 2.6 | `POST /text-to-video/kling-2.6`, `POST /image-to-video/kling-2.6` | New |
| 2.5 Turbo | `POST /text-to-video/kling-2.5-turbo`, `POST /image-to-video/kling-2.5-turbo` | New |
| Motion Control | `POST /motion-control/kling-3.0`, `POST /motion-control/kling-2.6` | New |
| Task query (new) | `GET /tasks?task_ids=a,b` or `?external_task_ids=…` (not both); `POST /tasks` (cursor) | New |
| Legacy video | `POST /v1/videos/text2video`, `/v1/videos/image2video` (`model_name` ∈ `kling-v2-5-turbo`,`kling-v2-6`,`kling-v3`), `/v1/videos/omni-video` (`kling-video-o1`,`kling-v3-omni`), `/v1/videos/multi-image2video` (`kling-v1-6`), `/v1/videos/video-extend` (V1.x); `GET /v1/videos/<kind>/{id}` and list | Legacy |
| Elements | `POST/GET /v1/general/advanced-custom-elements[/{id}]`, `GET /v1/general/advanced-presets-elements`, `POST /v1/general/delete-advanced-elements` | /v1 |
| Voices | `POST/GET /v1/general/custom-voices[/{id}]`, `GET /v1/general/presets-voices`, `POST /v1/general/delete-voices` | /v1 |
| Multi-element edit | `POST /v1/videos/multi-elements/{init-selection, add-selection, delete-selection, clear-selection, preview-selection}`, `POST /v1/videos/multi-elements`, `GET /v1/videos/multi-elements[/{id}]` | /v1 |
| Avatar | `POST /v1/videos/avatar/image2video`, `GET …/{id}`, list | /v1 |
| TTS | `POST /v1/audio/tts` | /v1 |
| Lip sync | `POST /v1/videos/identify-face`; `POST /v1/videos/advanced-lip-sync`, `GET …/{id}`, list | /v1 |
| Audio | `POST /v1/audio/text-to-audio`, `POST /v1/audio/video-to-audio` (+ GET by id, list) | /v1 |
| Effects | `POST /v1/videos/effects`, `GET /v1/videos/effects/{id}`, list | /v1 |
| Image recognition | `POST /v1/videos/image-recognize` | /v1 |
| Images | `/v1/images/generations`, `/v1/images/omni-image`, `/v1/images/multi-image2image`, `/v1/images/editing/expand`, `/v1/general/ai-multi-shot` (+ GET by id, list) | /v1 |
| Solutions | `POST /solutions/virtual_try_on`, `/solutions/e-commerce/clothing_dupe`, `/solutions/e-commerce/goods_studio`, `/solutions/talking_agent`; `GET/POST /solutions` | New-style |
| Account | `GET /account/costs` (resource packs: tier `flagship`/`general`/`professional`/`basic`, remaining with a 12 h delay); `POST /account/billing/balance`; `POST /account/billing/package` | – |

### 5.3 New-design request shape (4.0 Omni as the superset)

Source: [4.0 Omni Video](https://kling.ai/document-api/api/video/4-0/video-omni.md) [official]

```json
{
  "contents": [
    { "type": "prompt", "text": "…@image_1 … @video_1 … @element_1 … @1 …" },
    { "type": "first_frame" | "middle_frame" | "last_frame" | "refer_image", "url": "<url or base64>", "id": "image_1" },
    { "type": "feature_video" | "base_video", "url": "<url>", "id": "video_1" },
    { "type": "element", "element_id": "164", "id": "element_1" },
    { "type": "voice", "voice_id": "829826751244537879", "id": "1" }
  ],
  "settings": { "resolution": "720p|1080p", "aspect_ratio": "21:9|16:9|9:16|1:1|adaptive", "duration": 3..30 },
  "options": {
    "callback_url": "https://…",
    "external_task_id": "unique-per-account",
    "watermark_info": { "enabled": false }
  }
}
```

- 4.0 T2V uses top-level `prompt` instead of a `contents` prompt item. Source: [4.0 T2V](https://kling.ai/document-api/api/video/4-0/text-to-video.md) [official].
- `external_task_id` "will not overwrite the system-generated task ID, but can be used for task queries; must be unique within a single user account".
- `watermark_info.enabled = true` also produces `watermark_url`. "Custom watermarks are not currently supported."
- Same source.

### 5.4 Task lifecycle

1. **Submit.**
   - The create call returns `{code, message, request_id, data:{id, status, create_time, update_time, external_id}}`. `code: 0` means accepted.
   - "Receiving a task ID only confirms that the task was created… query the original task — do not resubmit."
   - Source: [4.0 T2V](https://kling.ai/document-api/api/video/4-0/text-to-video.md), [4.0 user manual §2.3](https://kling.ai/document-api/api/usage-guide/kling-4-0.md) [official].
2. **Poll.**
   - `GET /tasks?task_ids=id1,id2` returns `data[]` items with `id`, `status` (`submitted|processing|succeeded|failed`), `message` (failure reason, e.g. content risk control), `outputs[]` and `billing[]`.
   - `POST /tasks` body: `start_time` and `end_time` (ms; default last 30 days), `cursor` (`next_cursor`), `limit` (default 100, max 500), `filters[{key: status|product_type, values}]`, where product_type ∈ `video`, `image`, `try_on`. Response: `result[]`, `count`, `next_cursor`, `has_more`.
   - Queries do not use concurrency.
   - Source: [4.0 T2V "Query Task"](https://kling.ai/document-api/api/video/4-0/text-to-video.md), [Concurrency Rules](https://kling.ai/document-api/api/get-started/concurrency-rules.md) [official].
3. **`outputs[]` types**:
   - `video` {`id`, `url`, `watermark_url`, `duration`}
   - `image` {`url`, `watermark_url`, `group_id`}
   - `audio` {`id`, `mp3_url`, `wav_url`, `mp3_duration`, `wav_duration`}
   - `voice` {`id`, `name`, `url`, `owned_by`, `status`}
   - `element` {`id`, `name`, `description`, `element_type` (`video_character_elements`/`multi_image_elements`), `references[]`, `owned_by`, `status`, `tags[]`}
   - `billing[]`: `charge_type` cash|unit, `cash_type`, `amount`, `currency`, `package_type` video|image|audio, `list_price`.
   - Same source.
4. **Callback (`options.callback_url`)**:
   - The server POSTs the same shape as a query item whenever the status changes. Legacy callback uses `task_id`, `task_status` (`succeed`), `task_status_msg`, `final_unit_deduction`, `task_info.parent_video`, `task_result`.
   - Webhook signatures are optional and follow Standard Webhooks headers: `webhook-id`, `webhook-timestamp`, `webhook-signature: v1,<base64>` (several are space-separated during the 7-day rotation grace period). Python: `standardwebhooks`.
   - The console has a "Send Test Callback" button (endpoint should return HTTP 200) and secret create/rotate/delete.
   - Retry policy: **not documented**.
   - Source: [Callback Protocol](https://kling.ai/document-api/api/get-started/callbacks.md) [official].
5. **Results**:
   - "Generated result URL with hotlink protection. (Generated results are retained for 30 days; save them promptly.)"
   - Inputs that point at Kling outputs by `video_id` (lip sync, video-to-audio, multi-elements, voice-from-video, legacy extend) also only work within 30 days.
   - Source: [4.0 T2V](https://kling.ai/document-api/api/video/4-0/text-to-video.md); [API updates 2025-09-29](https://kling.ai/document-api/updates/api.md) [official].
6. **Typical latency**: video 1–5 min, image 20–60 s, element 30 s–2 min. Source: [Kling Skills](https://kling.ai/document-api/api/get-started/kling-skills.md) [official].

### 5.5 Concurrency, rate limits, errors
- **Concurrency**:
  - "Maximum number of generation tasks an account can process simultaneously", counted separately per account, model version and package type (video/image), and shared by all API keys.
  - A task holds a slot from `submitted` until done (including failure).
  - The account's quota is the highest value among its active packs of the same type.
  - Video and try-on tasks take 1 slot; an image task takes `n` slots.
  - "The system does not impose any QPS limits."
  - Over the limit you get `code 1303` "parallel task over resource pack limit". Recommended handling: exponential backoff (≥1 s) and a client-side queue.
  - Source: [Concurrency Rules](https://kling.ai/document-api/api/get-started/concurrency-rules.md) [official].
  - **Actual slot numbers per pack are not published** in the docs (see §8).
- **Error codes**. Source: [Error Codes](https://kling.ai/document-api/api/get-started/error-codes.md) [official]

| HTTP | Code | Meaning |
|---|---|---|
| 200 | 0 | success |
| 401 | 1000–1004 | auth failed / empty / invalid / not yet valid / expired |
| 429 | 1100 / 1101 / 1102 | account abnormal / arrears (postpaid) / resource pack exhausted or expired |
| 403 | 1103 | no access to the API/model (e.g. 4.0 without a Flagship pack [inferred]) |
| 400 | 1200 / 1201 | invalid params / invalid key or value (see message) |
| 404 | 1202 / 1203 | wrong method / resource (e.g. model) not found |
| 400 | 1300 / 1301 | platform policy / **content security policy** |
| 429 | 1302 / 1303 / 1304 | rate limit / concurrency over pack limit / IP whitelist |
| 500/503/504 | 5000 / 5001 / 5002 | internal / maintenance / timeout (backlog) |

### 5.6 Field tables for the /v1 utility endpoints

**Multi-element video editing (mask by clicks).** Source: [Multi-elements](https://kling.ai/document-api/api/video/multi-elements.md) [official]

| Step | Fields |
|---|---|
| `init-selection` | `video_id` (Kling, ≤30 days) **or** `video_url` (mp4/mov); duration **2–5 s or 7–10 s**; 720–2160 px; 24/30/60 fps. Returns `session_id` |
| `add-selection` / `delete-selection` | `session_id`, `frame_index` (≤10 marked frames, 1 per call), `points[{x,y}]` normalised 0–1 (≤10 per frame). Returns an RLE mask (decoder sample provided) |
| `clear-selection`, `preview-selection` | `session_id` |
| create `POST /v1/videos/multi-elements` | `session_id`, `edit_mode` `addition`/`swap`/`removal`, `image_list[{image}]` (add: 1–2 cropped images; swap: 1; removal: none; ≤10 MB), `prompt` ≤2500 with `<<<video_1>>>`/`<<<image_1>>>`, `negative_prompt`, `mode` std/pro, `duration` `5` (input 2–5 s) or `10` (input 7–10 s) |

Official prompt templates: "Using the context of <<<video_1>>>, seamlessly add [x] from <<<image_1>>>" and "swap [x] from <<<image_1>>> for [x] from <<<video_1>>>". Same source.

**Avatar / TTS / Lip sync.** Sources: [Avatar](https://kling.ai/document-api/api/video/avatar.md), [TTS](https://kling.ai/document-api/api/video/avatar/text-to-speech.md), [Face Recognition](https://kling.ai/document-api/api/video/lip-sync/face-detection.md), [Lip Sync](https://kling.ai/document-api/api/video/lip-sync.md) [official]

| Endpoint | Fields and limits |
|---|---|
| Avatar `POST /v1/videos/avatar/image2video` | `image` (≤10 MB, ≥300 px, 1:2.5–2.5:1), `audio_id` (TTS, ≤30 days, 2–300 s) **xor** `sound_file` (mp3/wav/m4a/aac ≤5 MB, 2–300 s), `prompt` ≤2500 (actions, emotion, camera), `mode` std/pro. Multiple faces: cannot choose the face |
| TTS `POST /v1/audio/tts` | `text` ≤1000, `voice_id` (preset list), `voice_language` zh/en, `voice_speed` 0.8–2.0. Response gives the audio `url` and `duration` (appears synchronous [inferred]) |
| Identify face `POST /v1/videos/identify-face` | `video_id` (≤30 days, ≤60 s) **or** `video_url` (mp4/mov ≤100 MB, 2–60 s, 720p/1080p, 512–2160 px). Returns `session_id` and faces `[face_id, face_image, start_time, end_time (ms)]` |
| Lip sync `POST /v1/videos/advanced-lip-sync` | `session_id`, `face_choose[]` (one face supported): `face_id`, `audio_id` xor `sound_file` (2–60 s, ≤5 MB), `sound_start_time`, `sound_end_time` (crop, ms, ≥2 s kept), `sound_insert_time` (ms on the video timeline; must overlap the face interval by ≥2 s), `sound_volume` 0–2, `original_audio_volume` 0–2 |

**Audio and effects.** Sources: [Text to Audio](https://kling.ai/document-api/api/video/audio-generation/text-to-audio.md), [Video to Audio](https://kling.ai/document-api/api/video/audio-generation/video-to-audio.md), [Video Effects](https://kling.ai/document-api/api/effects/video-effects.md) [official]

| Endpoint | Fields |
|---|---|
| `POST /v1/audio/text-to-audio` | `prompt` ≤200, `duration` 3.0–10.0 (one decimal) |
| `POST /v1/audio/video-to-audio` | `video_id` (≤30 days) xor `video_url` (mp4/mov ≤100 MB); 3.0–20.0 s; `sound_effect_prompt` ≤200; `bgm_prompt` ≤200; `asmr_mode` bool |
| `POST /v1/videos/effects` | `effect_scene` (template enum), `input.image` (single) or `input.images` (exactly 2; left/right composite); ≤10 MB, ≥300 px, 1:2.5–2.5:1 |

### 5.7 Pricing (API)

Source: [Pricing - Video](https://kling.ai/document-api/pricing/base/video.md), [Image](https://kling.ai/document-api/pricing/base/image.md), [E-Commerce](https://kling.ai/document-api/pricing/solutions/ecommerce.md), [Effects](https://kling.ai/document-api/pricing/solutions/effects.md) [official]. USD per "unit" depends on the pack; the table shows the official example prices. Video is charged per second unless stated.

| Model / feature | Variant | 720p | 1080p | 4K |
|---|---|---|---|---|
| **Kling 4.0** | no input video (bills output s) | 1.0 u ($0.157)/s | 1.5 u ($0.235)/s | – |
| Kling 4.0 | with input video (bills output×2 if input ≤ output, else input + output) | 0.6 u ($0.094)/s | 0.9 u ($0.141)/s | – |
| 3.0 Turbo | native audio | 0.8 u ($0.112) | 1.0 u ($0.14) | – |
| 3.0 | no audio / with audio | 0.6 / 0.9 u | 0.8 / 1.2 u | 3.0 u ($0.42) |
| 3.0 | Motion Control | 0.9 u | 1.2 u | – |
| 3.0 Omni | no ref video, no audio / no ref video + audio / with ref video | 0.6 / 0.8 / 0.9 u | 0.8 / 1.0 / 1.2 u | 3.0 u |
| O1 | no ref video / with ref video | 0.6 / 0.9 u | 0.8 / 1.2 u | – |
| 2.6 | no audio / audio / audio + voice | 0.3 u / – / – | 0.5 / 1.0 / 1.2 u | – |
| 2.6 | Motion Control | 0.5 u | 0.8 u | – |
| 2.5 Turbo | silent | 0.3 u ($0.042) | 0.5 u ($0.07) | – |
| Multi-element editing | per 5 s | 3 u | 5 u | – |
| Avatar | per s | 0.4 u | 0.8 u | – |
| Lip sync | per 5 s | 0.5 u | – | – |
| TTS, face recognition, custom voice | per call | 0.05 u each | | |
| Text/Video-to-Audio | per call | 0.25 u | | |
| Image recognition | per call | 0.1 u | | |
| Images | Image 3.0 / 3.0 Omni / O1 1K–2K: 8 u ($0.028); 3.0 Omni 4K: 16 u; 2.1 T2I: 4 u, I2I: 8 u, multi-image: 16 u; AI Multi-Shot: 20 u/call; Outpainting: 8 u | | | |
| Virtual Try-On | per image, 1K | 32 u ($0.112) | | |
| Effects | per template ("Effects Pricing List" at `/document-api/video-effect-price`) | | | |

- Motion control rounds to the nearest whole second. Source: [API updates 2025-12-22](https://kling.ai/document-api/updates/api.md) [official].
- **Payment model**: prepaid resource packs (Basic, Pro, General, Flagship; models differ per pack; the 4.0 pack's sample row says "Available only for Kling 4.0 and Kling 4.0 Flash") or a cash balance. Source: [Quick Start](https://kling.ai/document-api/guides/get-started/quick-start.md), [Account Usage](https://kling.ai/document-api/api/assets/account-usage.md) [official].
- **Terms**: account balance is "non-withdrawable, non-refundable"; pack validity varies. Source: [Terms of API Paid Service](https://kling.ai/document-api/guides/protocols/paid-service.md) [official].

### 5.8 Web app can do / API cannot (as of today)

| Web-app feature | API status | Source |
|---|---|---|
| Video extension for current models (4.0: "coming soon"; old Auto/Customized Extend) | Legacy extend is V1.x only; none for 2.x+ | [4.0 user manual §6.10](https://kling.ai/document-api/api/usage-guide/kling-4-0.md), [official-bundle `api-Cgkc33Fe.js`] |
| 4K for Kling 4.0 (listed as a web "Generation Mode") | API enum is 720p/1080p; 4K "coming soon" | [4.0 web guide](https://kling.ai/quickstart/kling-4-model-user-guide), [4.0 Omni Video](https://kling.ai/document-api/api/video/4-0/video-omni.md) |
| Motion Library (preset motions) for Motion Control | "Action libraries are not currently supported" | [API updates 2025-12-22](https://kling.ai/document-api/updates/api.md) |
| Record a video element in-app (APP only), trim the element video | API takes an already-trimmed 3–8 s clip | [Element Library guide](https://kling.ai/quickstart/klingai-element-library-3-user-guide) |
| AI Auto-Description of an element | no field (you write `element_description`) | same |
| Explore feed, one-click "recreate", Avatar preset library | – | same; [Avatar 2.0 guide](https://kling.ai/quickstart/kling-ai-avatar-2-user-guide) |
| Upload local files directly | API needs URLs (Base64 for images only); no upload endpoint found | endpoint pages [official]; no upload endpoint in [index](https://kling.ai/document-api/llms.txt) |
| Motion brush, camera presets on current models | not on new-design endpoints; legacy fields documented for old models | §2.7–2.8 |
| Canvas with content nodes, in-app agent (4.0 relaunch) | – | [3rd-party: myclaw.ai, orcarouter.ai blog titles] |

The API can do some things the web app cannot: batch and cursor task queries, external task IDs, webhooks, watermark-free output by default, and the e-commerce Solution APIs (also available via Kling "Agent Market"). Source: [API updates](https://kling.ai/document-api/updates/api.md) [official].

---

## 6. Workflow UX in the web app

### 6.1 Assets to finished clip (official descriptions)
- **Pick an entry point.**
  - Kling 4.0 has **Omni Reference** (default): text, images, videos and voices with automatic intent routing.
  - It also has **Keyframes**: images only, first / last / first+last / intermediate frames. The aspect ratio follows the first keyframe once uploaded; without images you choose 21:9 / 16:9 / 1:1 / 9:16.
  - Settings: duration slider in 1 s steps from 3 to 30 (default 10); aspect 21:9 / 16:9 / 1:1 / 9:16 / Auto (default Auto); mode 720p / 1080p / 4K.
  - Source: [4.0 web guide §2.1, §3.1, §3.x Keyframes](https://kling.ai/quickstart/kling-4-model-user-guide) [official].
- **Attach assets.**
  - Upload from the device, or "Select from History" to reuse earlier generations.
  - Assets get handles (`@Image1`…) in upload order.
  - Elements: type "@" in the input box or "Add from Element Library".
  - In Video 3.0: "Bind elements to enhance consistency" under the start frame.
  - On the **Assets** page there is an "Elements" tab and a "Use Element" button that opens the Omni tool.
  - Source: [Element Library guide](https://kling.ai/quickstart/klingai-element-library-3-user-guide) [official].
- **Start & End Frames.** O1 / 3.0 Omni have a "Start & End Frames" icon that "open[s] the upload slots… making the workflow clearer". Older I2V has "Add End Frame" at the top right. Source: [O1 guide](https://kling.ai/quickstart/klingai-video-o1-user-guide), [Start and End Frames](https://kling.ai/quickstart/ai-video-start-end-frames) [official].
- **Multi-shot (3.x).** A "Multi-Shot" toggle, then "Custom Multi-Shot" for per-shot duration and content. Source: [3.0 guide](https://kling.ai/quickstart/klingai-video-3-model-user-guide) [official].
- **Lip sync (on a generated video).** Open the Lip Sync popup → "Text to Speech" (AI voices, speed 0.8–2×) or upload audio → "Lip Sync". Longer audio can be cropped. Source: [Lip Sync guide](https://kling.ai/quickstart/ai-lip-sync-guide) [official, older].
- **Extend (legacy models).** An Extend tab at the bottom left after generation (Auto-Extend / Customized Extend). Source: [Extend guide](https://kling.ai/quickstart/ai-video-extension) [official, older].
- **Reuse.** Earlier outputs can be picked via "Select from History" as new inputs. Elements can be built from history images, and AI multi-view completion fills in other angles. Source: [Element Library guide](https://kling.ai/quickstart/klingai-element-library-3-user-guide) [official].
- **Download and watermark.**
  - Free plan downloads carry a watermark; paid plans can download without one. The download icon offers "with or without watermark" [3rd-party: crepal.ai, pollo.ai, aireiter.com; defaults disputed].
  - API outputs are watermark-free unless `watermark_info.enabled` is set [official].
- **Credits (web).** Official guide prices:
  - 3.0: native audio 12 / 9 credits/s (1080p / 720p); no audio 8 / 6; voice control +2/s.
  - 3.0 Omni: no video input 12/9 (audio) or 8/6 (silent); with video input 16/12 (audio "not supported yet").
  - O1: 8 / 12 credits/s (without / with video input) in one mode and 6 / 9 in the other.
  - Motion Control 3.0: 12 (pro) / 9 (std). 2.6: 8 / 5.
  - Avatar 2.0: 8 / 4 credits/s.
  - Lip sync: 5 credits per 5 s.
  - Element multi-view: 3 free per day for members, then 5.
  - **Kling 4.0 web credit rates are not stated in the official guide** (see §8).
  - Source: respective [quickstart guides](https://kling.ai/quickstart) [official].
- **Plans (official llms.txt, a May-2026 snapshot):**
  - Free (Basic), Standard $6.99 first month then $8.80 (660 credits per month), Pro $25.99 → $32.56 (3,000), Premier $64.99 → $80.96 (8,000), Ultra $127.99 → $159.99 (26,000; early access).
  - Top-up packs do not expire for 2 years. "Failed generations do not consume credits." "Unused monthly credits do not roll over."
  - Source: [kling.ai/llms.txt](https://kling.ai/llms.txt) [official, but its "Latest major version: Kling 3.0" shows it is stale].

### 6.2 What users find confusing or praise
- **Official warnings that point at real confusion:**
  - "Edit" vs "Reference" wording changes the pipeline.
  - Unlabelled assets lead the model to "infer… less predictable" roles.
  - Storyboard sheets leak grids and labels unless you ask for finished frames.
  - Subtitles and BGM get added by default.
  - Two 4.0 entry points that cannot be combined.
  - Shared video quota (5 clips / 30 s) across reference videos, the edit video and video elements.
  - Source: [4.0 user manual §8, §10](https://kling.ai/document-api/api/usage-guide/kling-4-0.md), [4.0 web guide](https://kling.ai/quickstart/kling-4-model-user-guide) [official].
- **Complex, model-specific limits** (the 3.0 Omni image/element/video combination rules, 1080p-only cases in 2.x, last-frame-only unsupported) mean that one UI cannot apply the same rules to every model [inferred from official docs].
- **Complaints [3rd-party, mostly review/SEO sites]:**
  - Credits deducted for failed or prompt-ignoring clips. This contradicts the official "Failed generations do not consume credits"; the likely reading is that only hard failures are free [inferred].
  - Long queues, especially on the free tier.
  - Weak support.
  - Monthly credits expiring; billing on plan switches.
  - Per-clip cost hard to predict.
  - Sources: [cybernews.com](https://cybernews.com/ai-tools/kling-ai-review/), [websites2know.com](https://websites2know.com/kling-ai-review/), [screenweaver.ai](https://www.screenweaver.ai/blog/kling-ai-review-2026) [3rd-party].
- **Praise [official claims plus 3rd-party guides]:**
  - Character and product consistency with Elements.
  - Native audio with correct speaker attribution.
  - Multi-shot in one generation.
  - 4.0's 30 s long takes and stable large motion.
  - 3rd-party advice: build Elements first, then write shot-by-shot prompts with `@ElementName`; two or three strong references beat fifteen weak ones; put keyframes only where the scene must change. Sources: [vidmuse.ai](https://vidmuse.ai/blog/kling-3-0-omni), [seedance.tv](https://www.seedance.tv/blog/kling-4-0-keyframes-omni-reference), [poyo.ai](https://poyo.ai/hub/kling-4-0-omni-reference-guide) [3rd-party, not hands-on verified].
- **Kling on Higgsfield:** Kling 4.0 is also offered on Higgsfield, so Kino could reach Kling through either provider [3rd-party: aliteq.com "kling 4 on higgsfield"; higgsfield.ai blog]. The pricing there differs.

### 6.3 What this suggests for Kino [inferred]
- **Model the request as a list of typed slots, not loose attachments.** Each attachment gets a role (First frame / Middle frame @t / Last frame / Look reference / Motion-or-camera reference / Video to edit / Element / Voice) and a handle the user can drop into the prompt (`@image_1`). Generate the "[Asset Roles]" lines of the prompt automatically from those roles.
- **Validate per model before submitting.** Check counts, sizes, durations, aspect windows (2:5–5:2 for 4.0 vs 1:2.5–2.5:1 elsewhere), the 15-item and 5-video/30 s quotas, and the 1080p-only cases, so users never pay for a 1201 error.
- **Plan local-file hosting.** Videos need a URL.
- **Download outputs immediately.** URLs die after 30 days.
- **Queue against concurrency.** Handle 1303 with backoff.
- **Store `external_task_id`** to tie Kling tasks to Kino projects.
- **Use the 4.0 behaviours for one-field simplicity.** Leaving duration or aspect empty lets the prompt drive them (`adaptive`). Offer one-tap "no subtitles" and "no background music" toggles, because the model adds both by default.
- **Treat Elements and Voices as library objects** with their own async creation tasks.

---

## 7. Version and recency notes
- The capability map lists 4K for Kling 4.0, but 4.0 endpoints accept only `720p` and `1080p`, and both the API changelog (10/28/2026) and the manual say 4K and 10-bit HDR are "coming soon". Source: [Capability Map](https://kling.ai/document-api/guides/capability-map/video.md) vs [4.0 Omni Video](https://kling.ai/document-api/api/video/4-0/video-omni.md) [official].
- The old domains `klingai.com` / `app.klingai.com` redirect to `kling.ai`; the old API host `api.klingai.com` is replaced by `api-singapore.klingai.com`.

---

## 8. Unconfirmed / conflicting

1. **Kling 4.0 web-app credit cost**: not in the official 4.0 guide. Third-party reports conflict: 15 credits/s at 1080p [kie.ai] vs 2 credits/s (4 before discount) on 27 Oct [aliteq.com]. Unresolved.
2. **4K for 4.0**: the capability map and web guide list it; API enums lack it ("coming soon"). Whether the web app renders 4K today is unconfirmed.
3. **2.6 native audio**: the capability map says "Not Supported" for 2.6 T2V/I2V native audio, while the endpoints (`settings.audio: native`, 1080p only) and the price list support it. The endpoint docs are more likely right.
4. **3.0 Turbo audio**: no audio field, but billed "With Native Audio". Whether a silent output is possible is unconfirmed.
5. **Frame rate**: "Generated videos use 24 fps" is stated only for the omni / video-input models (4.0, 3.0 Omni, O1). Kling's own llms.txt claims "30–60fps" for 3.0 and 3.0 Omni and "30fps" for O1 and 2.5 Turbo. These conflict and I could not confirm per-model output fps.
6. **Element references in prompts (3.0 / 3.0 Omni / O1 new API)**: the docs show both `@<id>` and `@<ElementName>` (e.g. "@Zhang"). Which one the backend resolves, or whether both work, is unclear. The 4.0 docs use `@<id>` only.
7. **O1 first + last frame**: the capability map's Omni table says O1 "Only supports the first frame with a duration of 5s or 10s"; the O1 endpoint doc allows first + last frame (with no extra reference images or elements).
8. **Camera control, motion brush and `cfg_scale` on current models**: the legacy fields are still documented in the docs bundle. `cfg_scale` is explicitly unsupported on v2.x. Camera control and motion brush were documented for V1.0 / V1.5. Whether `kling-v3` honours any of them is unconfirmed, and the new endpoints do not expose them. Whether the current web app still shows these controls for 3.x/4.0 is unconfirmed (the guides are dated 2025-11-24 reposts of older material).
9. **Concurrency numbers per resource pack**: not published in the docs. Third-party figures (trial ≈5, standard ≈20; or 3/5 in an older guide) are unverified, as are pack prices and validity (e.g. $700 / 5,000 units / 180 days per costbench.com).
10. **USD per unit**: the official price table implies ~$0.14 per unit for most video models but ~$0.157 per unit on the 4.0 rows; image units are ~$0.0035. Exact per-pack unit prices were not verified on the console.
11. **"Failed generations do not consume credits"** (official llms.txt) vs widespread user complaints about losing credits on failed or unsatisfying clips (3rd-party). I could not determine what counts as "failed".
12. **Callback retry policy and timeout**: not documented.
13. **Upload endpoint**: none found. Inputs must be URLs (images may be Base64). If Kling offers a hosted upload (e.g. for the MCP/CLI), it is not in the public docs.
14. **Web features I could not confirm from official sources**: an upscaling feature; "variations" / number of outputs per generation in the video UI; project folders; exact History/Assets UI behaviour for 4.0; the reported 4.0 canvas and in-app agent (3rd-party only).
15. **3.0 Omni web vs API limits**: the web FAQ says reference video 3–10 s, ≤2k; the API says 3–15.5 s (expanded 2026-06-17). The web FAQ is probably stale.
16. **Kling 4.0 Flash and video extension**: officially "coming soon", but third-party sites say Flash previewed to top-tier subscribers from 2026-09-28. Current Flash availability (web/API) is unconfirmed; the API endpoints exist only as doc stubs.
17. **Kling 3.5**: one 2026 third-party guide claims a "Kling 3.5 (May 2026)". No official source mentions it, so treat it as wrong.
18. **Legacy endpoint doc provenance**: the `/v1/videos/text2video`, `/v1/videos/image2video`, `/v1/videos/omni-video`, `/v1/videos/multi-image2video` and `/v1/videos/video-extend` field lists come from the docs site's JS bundle (`https://s15-kling.klingai.com/kos/s101/nlav112918/api-doc/assets/api-DvT-6iDv.js`, `api-CAOCbR1O.js`, `api-CHj5NTCb.js`, `api-DbldssU8.js`, `api-Cgkc33Fe.js`). They are official content but not linked from the current docs index, so they may be partly outdated. One oddity: the legacy image2video `model_name` default reads `kling-v2-6-turbo`, a name that appears nowhere else.
19. **Element creation note "kling-video-o3 and later"**: this internal name does not match any public model name. It probably means 3.0 Omni [inferred].
