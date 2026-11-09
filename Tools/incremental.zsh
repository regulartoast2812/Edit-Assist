# Incremental Swift builds (2026-11-09): the compiler keeps each file's object and what it depends on in
# .build/inc/<name>/, so a build recompiles only the files you changed and the ones that use something whose
# shape changed, on every core at once. A change inside one helper no longer recompiles the whole app.
# Changing the flags or the list of files rebuilds that product from scratch once (the compiler notices).
#
#   source Tools/incremental.zsh
#   incremental <name> <output> <swiftc flags...> -- <source files...>

incremental() {
  local name=$1 out=$2; shift 2
  local -a flags sources
  while (( $# )) && [[ $1 != "--" ]]; do flags+=("$1"); shift; done
  shift
  sources=("$@")
  local dir="$PWD/.build/inc/$name"
  mkdir -p "$dir"
  # The output file map: where each file's object and dependency record go (one per file, named by its path).
  local map="$dir/map.json" entries=() source key
  entries+=("  \"\": {\"swift-dependencies\": \"$dir/master.swiftdeps\"}")
  for source in "${sources[@]}"; do
    key=${source//\//_}; key=${key%.swift}
    entries+=("  \"$source\": {\"object\": \"$dir/$key.o\", \"swift-dependencies\": \"$dir/$key.swiftdeps\"}")
  done
  local joined=${(pj:,\n:)entries}
  local fresh="{
$joined
}"
  # Rewritten only when the list changed, so the compiler sees the same map from build to build.
  if [[ ! -f "$map" || "$(<"$map")" != "$fresh" ]]; then print -r -- "$fresh" > "$map"; fi
  xcrun swiftc -incremental -output-file-map "$map" -j "$(sysctl -n hw.ncpu)" "${flags[@]}" "${sources[@]}" -o "$out"
}
