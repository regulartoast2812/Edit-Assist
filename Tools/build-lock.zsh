# Sourced by build.sh and Tools/ship.sh: one build or ship at a time on this Mac, since chats working in parallel share
# the installed app and main. Held until the sourcing script exits; a build run by a ship that holds it skips it.
if [[ -z "${EDIT_ASSIST_LOCKED-}" ]]; then
  LOCK="${TMPDIR:-/tmp}/edit-assist-build.lock"
  until mkdir "$LOCK" 2>/dev/null; do
    holder=$(cat "$LOCK/pid" 2>/dev/null || echo "")
    if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then rm -rf "$LOCK"; continue; fi
    [[ -n "${told-}" ]] || { echo "Another build is running (pid ${holder:-?}); waiting for it…" >&2; told=1; }
    sleep 2
  done
  echo $$ > "$LOCK/pid"
  trap 'rm -rf "$LOCK"' EXIT
  export EDIT_ASSIST_LOCKED=1
fi
