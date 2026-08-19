#!/usr/bin/env bash
# Build a branded .app — the AppleScript droplet GUI for the repkger CLI.
#
#   scripts/make-app.sh                        # -> build/Repkger.app  (default)
#   APP_NAME="Noren Hodoki" scripts/make-app.sh   # -> build/Noren Hodoki.app
#
# Environment overrides:
#   APP_NAME      — .app folder name + CFBundleName (default: Repkger)
#   DISPLAY_NAME  — CFBundleDisplayName (default: $APP_NAME)
#   BUNDLE_ID     — CFBundleIdentifier  (default: com.ksl-testing.repkger)
#   INSTALL_DIR   — if set, copy finished .app here after build
#
# Steps: osacompile the droplet, embed bin/repkger into Contents/Resources/,
# set bundle metadata, register .pkg/.mpkg as document types (Finder
# "Open With"), and ad-hoc sign the bundle so Gatekeeper lets it run locally.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
src_applescript="$root/gui/Repkger.applescript"
cli="$root/bin/repkger"
APP_NAME="${APP_NAME:-Repkger}"
DISPLAY_NAME="${DISPLAY_NAME:-$APP_NAME}"
bundle_id="${BUNDLE_ID:-com.ksl-testing.repkger}"
out="$root/build/${APP_NAME}.app"
# single source of truth for the version is bin/repkger
version="$(sed -n 's/^REPKGER_VERSION="\([^"]*\)"/\1/p' "$cli" | head -1)"
case "$version" in
    [0-9]*\.[0-9]*\.[0-9]*) ;;
    *) echo "bad REPKGER_VERSION in bin/repkger: '$version'" >&2; exit 1 ;;
esac

command -v osacompile >/dev/null 2>&1 || { echo "osacompile not found (macOS required)" >&2; exit 1; }
[ -f "$src_applescript" ] || { echo "missing $src_applescript" >&2; exit 1; }
[ -x "$cli" ] || { echo "missing executable: $cli" >&2; exit 1; }

PB="$(command -v PlistBuddy || echo /usr/libexec/PlistBuddy)"
[ -x "$PB" ] || { echo "PlistBuddy not found" >&2; exit 1; }

rm -rf "$out"
mkdir -p "$(dirname "$out")"
osacompile -o "$out" "$src_applescript"

# embed the CLI
mkdir -p "$out/Contents/Resources"
cp "$cli" "$out/Contents/Resources/repkger"
chmod +x "$out/Contents/Resources/repkger"

info="$out/Contents/Info.plist"

set_plist() {  # $1 key $2 type $3 value
    "$PB" -c "Set :$1 $3" "$info" 2>/dev/null \
        || "$PB" -c "Add :$1 $2 $3" "$info"
}

set_plist CFBundleIdentifier string "$bundle_id"
set_plist CFBundleName string "$APP_NAME"
set_plist CFBundleDisplayName string "$DISPLAY_NAME"
set_plist CFBundleShortVersionString string "$version"
set_plist CFBundleVersion string "$version"
set_plist LSApplicationCategoryType string "public.app-category.utilities"
set_plist NSHighResolutionCapable bool true

# Finder: accept .pkg / .mpkg drops ("Open With Repkger")
"$PB" -c "Delete :CFBundleDocumentTypes" "$info" 2>/dev/null || true
"$PB" -c "Add :CFBundleDocumentTypes array" "$info"
"$PB" -c "Add :CFBundleDocumentTypes:0 dict" "$info"
"$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string 'Installer Package'" "$info"
"$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer" "$info"
"$PB" -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Alternate" "$info"
"$PB" -c "Add :CFBundleDocumentTypes:0:LSTypeIsPackage bool true" "$info"
"$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array" "$info"
"$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:0 string pkg" "$info"
"$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:1 string mpkg" "$info"

# icon — look for gui/<APP_NAME>.icns, then fall back to gui/Repkger.icns
icon_src=""
for cand in "$root/gui/${APP_NAME}.icns" "$root/gui/Repkger.icns"; do
    [ -f "$cand" ] && icon_src="$cand" && break
done
if [ -n "$icon_src" ]; then
    cp "$icon_src" "$out/Contents/Resources/"
    set_plist CFBundleIconFile string "$(basename "${icon_src%.icns}")"
fi

# ad-hoc sign so it runs locally — must come after ALL plist edits
codesign --force --deep --sign - "$out" >/dev/null

# Strip Gatekeeper quarantine from the newly built app — endpoint security
# (Microsoft Defender, etc.) often quarantines fresh builds, causing the
# "downloaded from the internet" prompt or deletion. Do this AFTER codesign
# so the signature remains valid but the quarantine flag is removed.
xattr -dr com.apple.quarantine "$out" 2>/dev/null || true
xattr -dr com.apple.provenance "$out" 2>/dev/null || true
# Also clean any nested helpers inside the bundle
find "$out" -name "*.app" -type d -exec xattr -dr com.apple.quarantine {} + 2>/dev/null || true
find "$out" -name "*.app" -type d -exec xattr -dr com.apple.provenance {} + 2>/dev/null || true
# Re-register with Launch Services so Finder/Dock sees the clean state
if [[ -x "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" ]]; then
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -u "$out" >/dev/null 2>&1 || true
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -f "$out" >/dev/null 2>&1 || true
fi
echo "quarantine stripped from built app"

# optional: install to a target directory
if [ -n "${INSTALL_DIR:-}" ]; then
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR/${APP_NAME}.app"
    cp -R "$out" "$INSTALL_DIR/${APP_NAME}.app"
    # re-sign the installed copy (cp preserves sig but target path differs)
    codesign --force --deep --sign - "$INSTALL_DIR/${APP_NAME}.app" >/dev/null
    # force LaunchServices to re-evaluate the app (clears cached Gatekeeper rejections)
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_DIR/${APP_NAME}.app" 2>/dev/null || true
    echo "Installed to $INSTALL_DIR/${APP_NAME}.app"
fi

echo "Built $out"
echo "  CLI embedded:  $out/Contents/Resources/repkger"
echo "  Bundle id:     $bundle_id"
echo "  Test:          open -a \"$out\" /path/to/some.pkg"
