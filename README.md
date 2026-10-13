# ✨ Edit Assist

Your editing companion for Premiere Pro. 🎬 It reads the screen and does repetitive edits for you — one **function** at a time.

🧪 Early days: two functions so far, with more on the way.

## 🚀 Install

```sh
curl -fsSL https://raw.githubusercontent.com/regulartoast2812/Edit-Assist/main/install.sh | bash
```

Needs macOS 14.2+.

🧪 **Beta testers**, get the newest beta instead:

```sh
curl -fsSL https://raw.githubusercontent.com/regulartoast2812/Edit-Assist/main/install.sh | bash -s -- --beta
```

## 🔄 Updates

The app checks for you. When a newer build is out, an **Update** button appears at the top: one click installs it and reopens the app. (Diagnostics → **Check for updates** to look right away.) Betas get newer betas and stable releases; stable gets stable.

## 🔐 Setup (once)

When macOS asks, allow **Screen Recording** and **Accessibility** (System Settings → Privacy & Security).

## 🧰 Functions

| | Function | What it does |
|---|---|---|
| 🖍️ | **Highlight - Subtitle Layers** | Finds your script's **bold** phrases in the captions, applies your style and bumps the font size, clip by clip. |
| 🔤 | **Highlight - Graphic Layers** | The same for graphic text on the video tracks, using Linked style. Hide the caption track first if it shows the same words. |
| ➕ | *More coming* | Each new function gets its own page and shares the same run bar. |

## ▶️ Using a function

1. 📄 Click your project and add what it needs (for highlighting: your script, **bold** = highlight; both highlight functions share it and the style settings, and each keeps its own progress).
2. 🧰 Pick a function in the sidebar.
3. ⏯️ Put the Premiere playhead where it should start.
4. ▶️ Press **Run** — the bar at the top shows progress.

⏸️ Move the mouse to pause · ▶️ or ✕ on the overlay to continue or stop · ⎋ Escape to stop.

---

🛠️ Building from source, adding a function, or curious how it works? See [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).
