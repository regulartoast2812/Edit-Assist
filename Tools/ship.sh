#!/bin/zsh
# A chat's finished change into main, and the app relaunched with it (AGENTS.md, "Parallel chats"). Run in the chat's
# worktree after committing: it merges main in, so the app keeps what the other chats shipped; builds and installs from
# here (build.sh: every check and replay first, nothing installed if one fails); then moves main up to this branch.
# Ships take turns (Tools/build-lock.zsh), so main cannot move between the merge and the build.
set -euo pipefail
cd "${0:A:h}/.."
branch=$(git branch --show-current)
[[ -n "$branch" && "$branch" != main ]] || { echo "Run this in a chat's worktree (Tools/new-chat.sh), not on main." >&2; exit 1; }
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit your changes first (only the files you changed):" >&2; git status --short >&2; exit 1
fi
main_dir=$(git worktree list --porcelain | awk '/^worktree /{d=substr($0,10)} /^branch refs\/heads\/main$/{print d}')
[[ -n "$main_dir" ]] || { echo "No folder has main checked out; it should be the main Edit Assist folder." >&2; exit 1; }
if [[ -n "$(git -C "$main_dir" status --porcelain --untracked-files=no)" ]]; then
  echo "The main folder has uncommitted changes, so main cannot move under them. Commit or move them first:" >&2
  git -C "$main_dir" status --short --untracked-files=no >&2; exit 1
fi

source Tools/build-lock.zsh
if ! git merge --no-edit main; then
  echo "Merging main into $branch conflicts: resolve here (keep both sides), commit, and run this again." >&2; exit 1
fi
./build.sh "$@"
git -C "$main_dir" merge --ff-only --quiet "$branch"
echo "Shipped: main is now $(git log --oneline -1 | cut -c1-100)"
