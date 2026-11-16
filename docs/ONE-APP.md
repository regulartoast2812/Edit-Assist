# One app: Creative Assist in Electron

Decided by the user on 2026-11-16. It replaces porting between Edit Assist (macOS, Swift) and Creative Assist
(Windows, WPF).

## The plan

- One cross-platform app in TypeScript: a web UI served by a local Node server, wrapped in Electron. It also runs
  in a browser.
- **Code:** `app/` in the Creative Assist repo, on the **`app` branch**. It is not on `main` yet.
  - Local worktree: `../Creative Assist-app` (`git worktree add "../Creative Assist-app" app`).
  - On another machine: `git fetch && git checkout app`.
- **Order:** Sage moves first, then the other helpers one at a time (Don, Kino, Penny, Remy, Tala, …).
- **Source of truth:** the C# Creative Assist on `main` is the newest version. Its page script and CSS are taken
  as they are, and each feature is read from its source.
- **Look:** one UI, held to the user's own standards and not styled per OS ("i only care about 1 UI being the
  true version").
- **Parity is the floor:** never strip a good feature to match. Progress is tracked row by row in
  [`app/PARITY.md`](https://github.com/regulartoast2812/Creative-Assist/blob/app/app/PARITY.md) on the `app` branch:
  ✅ seen working · 🔷 built, not yet seen working · 🟡 partial · ❌ missing.
- **Old apps:** fixes only. New features go only into the new app.

## Working on it

- `npm run check`: the checks, all of which must say "0 failed".
- `npm run build:mac`: builds and installs `~/Applications/Creative Assist.app` (ad-hoc signed).
  - Build and install after each finished task.
  - When launching Electron from a VS Code shell, unset `ELECTRON_RUN_AS_NODE` first.
- Test against a scratch vault and data folder (`CA_DATA=<scratch>`, `CA_PORT=<port>`), never the user's real vault.
- Commit only the files you changed, then push.
- Any download over 50 MB (Electron itself is about 110 MB) needs the user's OK first.

## Where it stands (2026-11-16)

- **Sage:** most of the file browser, the note page, the editor with its formatting toolbar and marks modes, the
  review comments with Sage's answers, and the in-app browser picker.
- **Next for Sage:**
  - the research stage;
  - chat brain actions;
  - the player and media;
  - review snapshots, and comments that follow a renamed file;
  - Ask Sage;
  - the remaining page rows.
- **The other helpers** have not started.
