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
echo "roundtrip: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
