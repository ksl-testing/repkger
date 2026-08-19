#!/usr/bin/env bash
# Full install -> uninstall round-trip for bin/repkger against the synthetic
# fixture (test/make-fixture.sh). This is what CI (.github/workflows/release.yml)
# runs; a release is only published if it passes.
#
#   test/roundtrip.sh
#
# Covers:
#   - default mapping (keep-if-writable) AND --home-rooted exact mapping
#   - decoy protection: a pre-existing app in ~/Applications is never touched
#     (regression test for the v0.1.0 rewrite/resign scope bug)
#   - quarantine stripped from mapped targets AND their parent dirs
#   - /Users/Shared + /tmp kept in place and cleaned up on uninstall
#   - record creation + deterministic uninstall reversal
#
# Requires macOS (pkgbuild, pkgutil, xattr, codesign).

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
R="$root/bin/repkger"

for c in pkgbuild pkgutil xattr codesign; do
    command -v "$c" >/dev/null 2>&1 || { echo "roundtrip: required tool '$c' not found (macOS?)" >&2; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PKG="$TMP/mini.pkg"
H="$TMP/home"          # phase 1 scratch home (default mapping)
B="$TMP/home-rooted"   # phase 2 scratch home (--home-rooted)
D1="$TMP/data"         # phase 1 records
D2="$TMP/data2"        # phase 2 records

# the always-keep locations are shared with the real machine — clear fixture files
rm -f /Users/Shared/mini-shared.txt /tmp/mini-tmp.txt

bash "$here/make-fixture.sh" "$PKG" >/dev/null

pass=0
fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }
check() {  # $1 = description; rest = command...
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

echo "== phase 1: default mapping (keep-if-writable) =="
mkdir -p "$H/Applications/Decoy.app/Contents"
echo "decoy payload" > "$H/Applications/Decoy.app/Contents/decoy.txt"
# quarantine the scratch home itself (parent of every mapped loc) and the
# mapped install-location dir — both must come out stripped
xattr -w com.apple.quarantine "0083;5f2e2a2e;MiniApp;1;test" "$H"
xattr -w com.apple.quarantine "0083;5f2e2a2e;MiniApp;1;test" "$H/Applications"

# Pin the fixture's system dirs to the scratch home. Default mapping keeps a
# location in place when the top-level dir is writable, so on admin machines
# (CI runners, admin dev accounts) /Applications and /Library are kept and the
# app would land in the REAL system dirs. Pinning makes phase 1 deterministic
# on every machine while still exercising default mapping for /Users and the
# always-keep dirs (/Users/Shared, /tmp) below.
REPKGER_DATA="$D1" "$R" install "$PKG" --home "$H" \
    --map "/Applications=$H/Applications" \
    --map "/Library=$H/Library" \
    --map "/usr/local=$H/.local" \
    --yes >/dev/null

check "decoy untouched"            grep -q "decoy payload" "$H/Applications/Decoy.app/Contents/decoy.txt"
check "quarantine stripped from parent dir (\$H)" \
    test -z "$(xattr -p com.apple.quarantine "$H" 2>/dev/null)"
check "quarantine stripped from mapped loc" \
    test -z "$(xattr -p com.apple.quarantine "$H/Applications" 2>/dev/null)"
check "app landed in \$H/Applications" \
    test -x "$H/Applications/MiniApp.app/Contents/MacOS/miniapp"
check "top-level symlink preserved" \
    test -L "$H/Applications/MiniApp-link.app"
check "/Applications ref rewritten" \
    grep -Fq "$H/Applications/MiniApp.app/Contents/Resources" \
        "$H/Applications/MiniApp.app/Contents/Resources/refs.txt"
check "/Library ref rewritten" \
    grep -Fq "$H/Library/MiniSupport" "$H/Applications/MiniApp.app/Contents/Resources/refs.txt"
check "keep-in-place /Users/Shared" test -f /Users/Shared/mini-shared.txt
check "keep-in-place /tmp"          test -f /tmp/mini-tmp.txt
rec="$(ls -d "$D1"/records/com.test.miniapp-* | head -1)"
check "record written"              test -f "$rec/record.tsv"
check "record has file entries" \
    test "$(awk -F'\t' '$1=="file"{n++} END{print n+0}' "$rec/record.tsv")" -ge 15

REPKGER_DATA="$D1" "$R" uninstall "$rec" --yes >/dev/null
check "uninstall removed app"       test ! -e "$H/Applications/MiniApp.app"
check "uninstall removed top symlink" test ! -e "$H/Applications/MiniApp-link.app"
check "uninstall left decoy"        grep -q "decoy payload" "$H/Applications/Decoy.app/Contents/decoy.txt"
check "uninstall cleaned /Users/Shared" test ! -e /Users/Shared/mini-shared.txt
check "uninstall cleaned /tmp"      test ! -e /tmp/mini-tmp.txt

echo
echo "== phase 2: --home-rooted (deterministic exact paths) =="
mkdir -p "$B"
REPKGER_DATA="$D2" "$R" install "$PKG" --home "$B" --home-rooted --yes >/dev/null

refs="$B/Applications/MiniApp.app/Contents/Resources/refs.txt"
check "exact: app"                  test -x "$B/Applications/MiniApp.app/Contents/MacOS/miniapp"
check "exact: /usr/local -> .local" test -x "$B/.local/bin/mini-tool"
check "exact: /Library -> \$B/Library" test -f "$B/Library/MiniSupport/README.txt"
check "refs: .local/bin"            grep -Fq "$B/.local/bin" "$refs"
check "refs: no stale /usr/local/bin" \
    test -z "$(grep -F '/usr/local/bin' "$refs" || true)"
check "refs: PATH list /usr/bin:/bin" grep -Fq "$B/.usr/bin:$B/bin" "$refs"
check "refs: /private/var -> var"   grep -Fq "$B/var/log/mini.log" "$refs"
check "refs: /private/etc -> etc"   grep -Fq "$B/etc/mini.conf" "$refs"
check "refs: --prefix="             grep -Fq -- "--prefix=$B/.local/x" "$refs"
check "tool content rewritten"      grep -Fq "$B/.local/lib/mini-tool" "$B/.local/bin/mini-tool"
check "keep-in-place still works"   test -f /Users/Shared/mini-shared.txt

rec2="$(ls -d "$D2"/records/com.test.miniapp-* | head -1)"
REPKGER_DATA="$D2" "$R" uninstall "$rec2" --yes >/dev/null
check "phase2 uninstall removed app" test ! -e "$B/Applications/MiniApp.app"
check "phase2 uninstall cleaned .local" test ! -e "$B/.local"
check "phase2 uninstall cleaned Library" test ! -e "$B/Library"

echo
echo "== phase 3: bom-redo — BOM repacked to no-sudo locations, installed WITHOUT --map =="
H3="$TMP/home3"
D3="$TMP/data3"
OUT="$TMP/rootless"
mkdir -p "$H3"
# redo the BOM so every destination is the mapped (accessible) location
REPKGER_DATA="$D3" "$R" bom-redo "$PKG" --home "$H3" --out "$OUT" \
    --map "/Applications=$H3/Applications" \
    --map "/Library=$H3/Library" \
    --map "/usr/local=$H3/.local" \
    --quiet >/dev/null
check "bom-redo produced .mpkg"        test -d "$OUT/mini-rootless.mpkg"
check "mpkg has Distribution"          test -f "$OUT/mini-rootless.mpkg/Contents/Distribution"
check "mpkg has 5 leaf components"     test "$(ls "$OUT/mini-rootless.mpkg/Contents/Packages"/*.pkg 2>/dev/null | wc -l | tr -d ' ')" -eq 5
# the redone pkg needs NO --map: every BOM entry is already a writable location
REPKGER_DATA="$D3" "$R" install "$OUT/mini-rootless.mpkg" --home "$H3" --yes >/dev/null
check "rootless: app in H3/Applications" test -x "$H3/Applications/MiniApp.app/Contents/MacOS/miniapp"
check "rootless: top symlink preserved" test -L "$H3/Applications/MiniApp-link.app"
check "rootless: tool in H3/.local/bin"   test -x "$H3/.local/bin/mini-tool"
check "rootless: Library in H3/Library"   test -f "$H3/Library/MiniSupport/README.txt"
check "rootless: keep /Users/Shared"      test -f /Users/Shared/mini-shared.txt
check "rootless: keep /tmp"               test -f /tmp/mini-tmp.txt
check "rootless: refs rewritten to H3/.local/bin" \
    grep -Fq "$H3/.local/bin" "$H3/Applications/MiniApp.app/Contents/Resources/refs.txt"

local_r=""
for r in "$D3"/records/*; do
    [ -f "$r/record.tsv" ] || continue
    REPKGER_DATA="$D3" "$R" uninstall "$r" --yes >/dev/null
    local_r="$r"
done
check "rootless: 5 records uninstalled"  test -n "$local_r"
check "rootless: uninstalled top symlink"  test ! -e "$H3/Applications/MiniApp-link.app"
check "rootless uninstall cleared H3"     test -z "$(find "$H3" -mindepth 1 | head -1)"
check "rootless uninstall cleaned /Users/Shared" test ! -e /Users/Shared/mini-shared.txt
check "rootless uninstall cleaned /tmp"   test ! -e /tmp/mini-tmp.txt

echo
echo "== phase 4: brew wrapper --rpkg (force rootless, never installer/sudo) =="
H4="$TMP/home4"
D4="$TMP/data4"
BIN4="$TMP/fakebrew"
FAKE_LOG="$TMP/brew-calls.log"
mkdir -p "$H4" "$BIN4"
# a fake brew that ONLY answers `info --cask <name> --json=v2` (from an env
# JSON file) and records every invocation — if the wrapper ever execs real
# brew's install path (installer/sudo), the log shows a non-info call and the
# test fails. Real brew is never on PATH here.
cat > "$BIN4/brew" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG"
case "$1" in
    info) cat "$BREW_FAKE_JSON" ;;
    *) echo "fake brew: unexpected call: $*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$BIN4/brew"
FAKE_PKG="$BIN4/mini.pkg"
cp "$PKG" "$FAKE_PKG"
FSHA=$(shasum -a 256 "$FAKE_PKG" | awk '{print $1}')
cat > "$BIN4/brew-pkg.json" <<JSON
{"casks":[{"url":"file://$FAKE_PKG","sha256":"$FSHA"}]}
JSON
cat > "$BIN4/brew-other.json" <<JSON
{"casks":[{"url":"https://example.com/Foo.tar.bz2","sha256":"$FSHA"}]}
JSON
: > "$FAKE_LOG"
check "brew --rpkg: pkg cask installs rootlessly" \
    env PATH="$BIN4:$PATH" HOME="$H4" REPKGER_DATA="$D4" BREW_FAKE_JSON="$BIN4/brew-pkg.json" FAKE_LOG="$FAKE_LOG" \
        "$R" brew install --cask --rpkg rpkgtest
check "brew --rpkg: app landed in HOME/Applications" \
    test -x "$H4/Applications/MiniApp.app/Contents/MacOS/miniapp"
check "brew --rpkg: fake brew only saw 'info' (no installer call)" \
    test "$(grep -vc '^info ' "$FAKE_LOG" || true)" -eq 0
check "brew --rpkg: record written" \
    test -n "$(ls -d "$D4"/records/* 2>/dev/null | head -1)"
REPKGER_DATA="$D4" "$R" uninstall "$(ls -d "$D4"/records/* | head -1)" --yes >/dev/null 2>&1 || true
rm -f /Users/Shared/mini-shared.txt /tmp/mini-tmp.txt

# --map passthrough: the map must reach the rootless install (e.g. Unity Hub layout)
mkdir -p "$H4/MappedApps"
check "brew --rpkg: --map passes through to install" \
    env PATH="$BIN4:$PATH" HOME="$H4" REPKGER_DATA="$D4" BREW_FAKE_JSON="$BIN4/brew-pkg.json" FAKE_LOG="$FAKE_LOG" \
        "$R" brew install --cask --rpkg --map "/Applications=$H4/MappedApps" rpkgmap
check "map case: app landed in mapped dir" \
    test -x "$H4/MappedApps/MiniApp.app/Contents/MacOS/miniapp"
REPKGER_DATA="$D4" "$R" uninstall "$(ls -d "$D4"/records/* | head -1)" --yes >/dev/null 2>&1 || true
rm -f /Users/Shared/mini-shared.txt /tmp/mini-tmp.txt

# unsupported artifact + --rpkg must FAIL LOUD, never fall through to brew
if env PATH="$BIN4:$PATH" HOME="$H4" REPKGER_DATA="$D4" BREW_FAKE_JSON="$BIN4/brew-other.json" FAKE_LOG="$FAKE_LOG" \
        "$R" brew install --cask --rpkg notapkg >/dev/null 2>&1; then
    bad "brew --rpkg: unsupported artifact must die (not fall through to installer)"
else
    ok "brew --rpkg: unsupported artifact dies with an error (no silent installer)"
fi
check "brew --rpkg: still no installer call" \
    test "$(grep -vc '^info ' "$FAKE_LOG" || true)" -eq 0

# zip cask that CONTAINS a .pkg
FAKE_ZIP="$BIN4/FakeCask.zip"
rm -rf "$BIN4/zippkg" && mkdir -p "$BIN4/zippkg"
cp "$PKG" "$BIN4/zippkg/mini.pkg"
( cd "$BIN4/zippkg" && ditto -c -k mini.pkg "$FAKE_ZIP" )
ZSHA=$(shasum -a 256 "$FAKE_ZIP" | awk '{print $1}')
cat > "$BIN4/brew-zip.json" <<JSON
{"casks":[{"url":"file://$FAKE_ZIP","sha256":"$ZSHA"}]}
JSON
: > "$FAKE_LOG"
check "brew --rpkg: zip cask with inner .pkg installs rootlessly" \
    env PATH="$BIN4:$PATH" HOME="$H4" REPKGER_DATA="$D4" BREW_FAKE_JSON="$BIN4/brew-zip.json" FAKE_LOG="$FAKE_LOG" \
        "$R" brew install --cask --rpkg rpkgzip
check "zip case: app landed"        test -x "$H4/Applications/MiniApp.app/Contents/MacOS/miniapp"
check "zip case: no installer call" test "$(grep -vc '^info ' "$FAKE_LOG" || true)" -eq 0
REPKGER_DATA="$D4" "$R" uninstall "$(ls -d "$D4"/records/* | head -1)" --yes >/dev/null 2>&1 || true
rm -f /Users/Shared/mini-shared.txt /tmp/mini-tmp.txt

# dmg cask that CONTAINS a .pkg (mounted read-only, inner pkg installed, detached)
FAKE_DMG="$BIN4/FakeCask.dmg"
hdiutil create -volname FakeCask -srcfolder "$BIN4/zippkg" -ov -format UDZO "$FAKE_DMG" >/dev/null 2>&1
DSHA=$(shasum -a 256 "$FAKE_DMG" | awk '{print $1}')
cat > "$BIN4/brew-dmg-pkg.json" <<JSON
{"casks":[{"url":"file://$FAKE_DMG","sha256":"$DSHA"}]}
JSON
: > "$FAKE_LOG"
check "brew --rpkg: dmg cask with inner .pkg installs rootlessly" \
    env PATH="$BIN4:$PATH" HOME="$H4" REPKGER_DATA="$D4" BREW_FAKE_JSON="$BIN4/brew-dmg-pkg.json" FAKE_LOG="$FAKE_LOG" \
        "$R" brew install --cask --rpkg rpkgdmg
check "dmg case: app landed"        test -x "$H4/Applications/MiniApp.app/Contents/MacOS/miniapp"
check "dmg case: no installer call" test "$(grep -vc '^info ' "$FAKE_LOG" || true)" -eq 0
check "dmg case: volume detached"   test -z "$(ls -d /Volumes/FakeCask 2>/dev/null || true)"
REPKGER_DATA="$D4" "$R" uninstall "$(ls -d "$D4"/records/* | head -1)" --yes >/dev/null 2>&1 || true
rm -f /Users/Shared/mini-shared.txt /tmp/mini-tmp.txt

echo
echo "roundtrip: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
