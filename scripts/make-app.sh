#!/usr/bin/env bash
# Build Repkger.app — the AppleScript droplet GUI for the repkger CLI.
#
#   scripts/make-app.sh            # -> build/Repkger.app
#
# Steps: osacompile the droplet, embed bin/repkger into Contents/Resources/,
# set bundle metadata (id com.ksl-testing.repkger), register .pkg/.mpkg as
# document types (Finder "Open With"), and ad-hoc sign the bundle so
# Gatekeeper lets it run locally.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
src_applescript="$root/gui/Repkger.applescript"
cli="$root/bin/repkger"
out="$root/build/Repkger.app"
bundle_id="com.ksl-testing.repkger"
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
set_plist CFBundleName string "Repkger"
set_plist CFBundleDisplayName string "Repkger"
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

# icon (optional — build one with iconutil if you add gui/Repkger.iconset)
if [ -f "$root/gui/Repkger.icns" ]; then
    cp "$root/gui/Repkger.icns" "$out/Contents/Resources/"
    set_plist CFBundleIconFile string "Repkger"
fi

# ad-hoc sign so it runs locally (no notarization until there's a dev account)
codesign --force --deep --sign - "$out" >/dev/null

echo "Built $out"
echo "  CLI embedded:  $out/Contents/Resources/repkger"
echo "  Bundle id:     $bundle_id"
echo "  Test:          open -a \"$out\" /path/to/some.pkg"
