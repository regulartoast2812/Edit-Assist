#!/bin/zsh
# A folder of its own for a chat working in parallel with others (AGENTS.md, "Parallel chats"):
#   Tools/new-chat.sh kino   →   ../Edit Assist-kino, a git worktree on branch "kino", made from main.
# Client screens, kept probes and MakeFixtures are not in git, so a worktree would replay almost no fixtures and
# still pass: they are linked back to this folder instead. Run it again on an existing worktree to sync: a fixture
# made there is moved here (so it outlives the worktree and every chat replays it) and linked back.
set -euo pipefail
cd "${0:A:h}/.."
main=$PWD
name=${1:?"usage: Tools/new-chat.sh <name>   (e.g. kino)"}
[[ "$name" =~ ^[a-z0-9-]+$ ]] || { echo "Use lowercase letters, digits and dashes: $name" >&2; exit 1; }
dir="${main:h}/Edit Assist-$name"

if [[ ! -d "$dir" ]]; then
  if git show-ref --verify --quiet "refs/heads/$name"; then
    git worktree add "$dir" "$name"
  else
    git worktree add -b "$name" "$dir" main
  fi
fi

# Kept on this Mac only (.gitignore): everything ignored under Tests/, and the accuracy notes.
local_only=(Tests/Fixtures/*.png(N) Tests/Fixtures/*.json(N) Tests/*Probe.swift(N) Tests/AccuracyAudit.swift(N)
            Tests/MakeFixtures.swift(N) ACCURACY_FINDINGS.md(N))
cd "$dir"
moved=0
for f in Tests/Fixtures/*.png(N) Tests/Fixtures/*.json(N); do
  [[ -L "$f" ]] && continue
  git ls-files --error-unmatch "$f" >/dev/null 2>&1 && continue
  [[ -e "$main/$f" ]] && { echo "Not moving $f: $main/$f exists and differs. Sort it out by hand." >&2; continue; }
  mv "$f" "$main/$f"; moved=$((moved + 1))
done
linked=0
for f in $local_only; do
  git ls-files --error-unmatch "$f" >/dev/null 2>&1 && continue
  [[ -L "$f" ]] && continue
  [[ -e "$f" ]] && continue
  mkdir -p "${f:h}"; ln -s "$main/$f" "$f"; linked=$((linked + 1))
done
# The new fixtures moved above, linked back.
for f in $main/Tests/Fixtures/*.png(N) $main/Tests/Fixtures/*.json(N); do
  rel=${f#$main/}
  [[ -e "$rel" || -L "$rel" ]] || { ln -s "$f" "$rel"; linked=$((linked + 1)); }
done

echo "Worktree: $dir (branch $(git branch --show-current))"
echo "Linked $linked local-only files from $main$( (( moved )) && echo "; moved $moved new fixtures there" )."
echo "Open that folder in its own window for the chat. Check with ./test.sh; finish with Tools/ship.sh (AGENTS.md)."
