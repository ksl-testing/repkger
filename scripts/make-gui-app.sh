#!/usr/bin/env bash
# Build a REAL windowed .app for repkger (Python/Tk front-end), not an
# AppleScript droplet. The droplet form mishandles launch/droplet argv
# ("erroring upon launch"); a bundled Python script gets clean argv so both
# double-click and Finder drag-drop / "Open With" work.
#
#   scripts/make-gui-app.sh                 # -> build/Repkger.app
#   APP_NAME="Noren Hodoki" scripts/make-gui-app.sh
#
# Env overrides: APP_NAME (default Repkger), DISPLAY_NAME, BUNDLE_ID,
# INSTALL_DIR (copy finished .app here).

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
gui_src="$root/gui/repkger_gui.py"
cli="$root/bin/repkger"
APP_NAME="${APP_NAME:-Repkger}"
DISPLAY_NAME="${DISPLAY_NAME:-$APP_NAME}"
bundle_id="${BUNDLE_ID:-com.ksl-testing.repkger}"
out="$root/build/${APP_NAME}.app"

[ -f "$gui_src" ] || { echo "missing $gui_src" >&2; exit 1; }
[ -x "$cli" ] || { echo "missing executable: $cli" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 1; }
python3 -m py_compile "$gui_src" || { echo "gui failed to compile" >&2; exit 1; }
version="$(sed -n 's/^REPKGER_VERSION="\([^"]*\)"/\1/p' "$cli" | head -1)"

rm -rf "$out"
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources"

cp "$gui_src" "$out/Contents/MacOS/repkger-gui"
chmod +x "$out/Contents/MacOS/repkger-gui"
cp "$cli" "$out/Contents/Resources/repkger"
chmod +x "$out/Contents/Resources/repkger"

cat > "$out/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key><string>$bundle_id</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>repkger-gui</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Installer Package</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSTypeIsPackage</key><true/>
            <key>CFBundleTypeExtensions</key>
            <array><string>pkg</string><string>mpkg</string><string>dmg</string><string>zip</string><string>bundle</string></array>
        </dict>
    </array>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$out" >/dev/null
xattr -dr com.apple.quarantine "$out" 2>/dev/null || true
xattr -dr com.apple.provenance "$out" 2>/dev/null || true
if [[ -x "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" ]]; then
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -f "$out" >/dev/null 2>&1 || true
fi

if [ -n "${INSTALL_DIR:-}" ]; then
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR/${APP_NAME}.app"
    cp -R "$out" "$INSTALL_DIR/${APP_NAME}.app"
    codesign --force --deep --sign - "$INSTALL_DIR/${APP_NAME}.app" >/dev/null
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -f "$INSTALL_DIR/${APP_NAME}.app" 2>/dev/null || true
    echo "Installed to $INSTALL_DIR/${APP_NAME}.app"
fi

echo "Built $out"
echo "  GUI:         $out/Contents/MacOS/repkger-gui (Python/Tk)"
echo "  CLI embedded: $out/Contents/Resources/repkger"
echo "  Bundle id:   $bundle_id"
echo "  Test:        open \"$out\" /path/to/some.pkg"
