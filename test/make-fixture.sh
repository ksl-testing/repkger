#!/usr/bin/env bash
# Build a tiny synthetic installer package (mini.pkg) that exercises every
# repkger mapping/merge/rewrite/resign/quarantine path, so the fast test loop
# doesn't need the 800 MB GameMaker fixture.
#
#   test/make-fixture.sh [out.pkg]     # default: /tmp/repkger-fixture/mini.pkg
#
# Contents (single component, install-location /):
#   /Applications/MiniApp.app        — real bundle (Info.plist + executable),
#                                      Contents/Resources/refs.txt with stale
#                                      /Applications /Library /usr/local refs,
#                                      plus a relative symlink
#   /usr/local/bin/mini-tool         — script with stale refs
#   /Library/MiniSupport/README.txt  — home-mapped /Library
#   /Users/Shared/mini-shared.txt    — kept in place (world-writable)
#   /tmp/mini-tmp.txt                — kept in place (world-writable)
#   preinstall / postinstall         — recorded, never run by default

set -euo pipefail

out="${1:-/tmp/repkger-fixture/mini.pkg}"
work="$(mktemp -d "${TMPDIR:-/tmp}/repkger-fixture.XXXXXX")"
trap 'rm -rf "$work"' EXIT

payload="$work/payload"
scripts="$work/scripts"
mkdir -p \
    "$payload/Applications/MiniApp.app/Contents/MacOS" \
    "$payload/Applications/MiniApp.app/Contents/Resources" \
    "$payload/usr/local/bin" \
    "$payload/Library/MiniSupport" \
    "$payload/Users/Shared" \
    "$payload/tmp" \
    "$scripts"

# --- the app bundle ---------------------------------------------------------
cat > "$payload/Applications/MiniApp.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>miniapp</string>
    <key>CFBundleIdentifier</key><string>com.test.miniapp</string>
    <key>CFBundleName</key><string>MiniApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
</dict>
</plist>
PLIST

cat > "$payload/Applications/MiniApp.app/Contents/MacOS/miniapp" <<'SH'
#!/bin/sh
echo "mini app running"
SH
chmod +x "$payload/Applications/MiniApp.app/Contents/MacOS/miniapp"

cat > "$payload/Applications/MiniApp.app/Contents/Resources/refs.txt" <<'TXT'
stale refs to rewrite:
/Applications/MiniApp.app/Contents/Resources
/Library/MiniSupport
/Library/Application Support/Mini
/usr/local/bin
/usr/bin:/bin
/private/var/log/mini.log
/private/etc/mini.conf
--prefix=/usr/local/x
TXT

ln -s refs.txt "$payload/Applications/MiniApp.app/Contents/Resources/rel-link"
# top-level symlink (regression: ditto dereferences a top-level symlink source
# and copies its target as a real dir, which breaks record/uninstall symmetry)
ln -s MiniApp.app "$payload/Applications/MiniApp-link.app"

# --- other roots ------------------------------------------------------------
cat > "$payload/usr/local/bin/mini-tool" <<'SH'
#!/bin/sh
# looks up resources under /usr/local/lib/mini-tool
echo "/usr/local/lib/mini-tool"
SH
chmod +x "$payload/usr/local/bin/mini-tool"

cat > "$payload/Library/MiniSupport/README.txt" <<'TXT'
installed via /Library/MiniSupport
TXT

echo "shared file (kept at /Users/Shared)" > "$payload/Users/Shared/mini-shared.txt"
echo "tmp file (kept at /tmp)" > "$payload/tmp/mini-tmp.txt"

# --- scripts ----------------------------------------------------------------
cat > "$scripts/preinstall" <<'SH'
#!/bin/sh
echo "preinstall would run (recorded, not executed)"
SH
cat > "$scripts/postinstall" <<'SH'
#!/bin/sh
# postinstall refs that bom-redo must home-map to match the redone BOM
mkdir -p /Applications/MiniApp.app/Contents/Resources
chmod 755 /Applications/MiniApp.app/Contents/MacOS/miniapp
echo "support at /Library/MiniSupport" > /Library/MiniSupport/README.txt
echo "tool at /usr/local/bin/mini-tool"
SH
chmod +x "$scripts"/*

mkdir -p "$(dirname "$out")"
pkgbuild \
    --root "$payload" \
    --scripts "$scripts" \
    --identifier com.test.miniapp \
    --version 1.0.0 \
    --install-location / \
    "$out" >/dev/null

echo "built $out ($(stat -f%z "$out") bytes)"
