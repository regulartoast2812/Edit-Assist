#!/bin/zsh
# Creates a stable, self-signed code-signing identity for local builds.
#
# Why: an ad-hoc signature (codesign --sign -) gives the bundle a designated
# requirement that pins the cdhash, and the cdhash changes on every build. macOS
# ties Screen Recording and Accessibility grants to that requirement, so each
# rebuild silently invalidated the permission you had just granted. Signing with
# a fixed certificate produces `identifier "..." and certificate leaf = H"..."`,
# which stays identical across rebuilds, so the grant sticks.
#
# Everything lives in its own keychain, so the login keychain is untouched.
# To undo: security delete-keychain edit-assist-signing.keychain
set -euo pipefail

NAME="Edit Assist Local Signing"
KC="edit-assist-signing.keychain"
KC_PASS="edit-assist"
KC_PATH="$HOME/Library/Keychains/${KC}-db"

add_to_search_list() {
  local current
  current=$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')
  if ! print -r -- "$current" | grep -q "$KC"; then
    security list-keychains -d user -s ${(f)current} "$HOME/Library/Keychains/$KC"
  fi
}

if [[ -f "$KC_PATH" ]] && security find-certificate -c "$NAME" "$KC" >/dev/null 2>&1; then
  security unlock-keychain -p "$KC_PASS" "$KC" 2>/dev/null || true
  add_to_search_list
  exit 0
fi

echo "Creating a stable signing identity so macOS permissions survive rebuilds…"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/ext.cnf" <<'CNF'
[req]
distinguished_name=dn
[dn]
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/key.pem" -out "$work/cert.pem" \
  -days 3650 -subj "/CN=$NAME" -extensions v3 -config "$work/ext.cnf" 2>/dev/null
openssl pkcs12 -export -out "$work/id.p12" -inkey "$work/key.pem" -in "$work/cert.pem" \
  -name "$NAME" -passout "pass:$KC_PASS" 2>/dev/null

security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings "$KC"          # no auto-lock timeout
security unlock-keychain -p "$KC_PASS" "$KC"
security import "$work/id.p12" -k "$KC" -P "$KC_PASS" -T /usr/bin/codesign -A >/dev/null
# Let codesign use the key without an interactive keychain prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC" >/dev/null 2>&1
add_to_search_list
echo "Signing identity ready: $NAME"
