#!/usr/bin/env bash
# Local / self-hosted-runner release builder for repkger.
#
# GH Actions is billing-blocked on this account, so the release pipeline
# (build assets -> gh release create -> update the ksl-testing/homebrew-tap
# formula) is driven from a LOCAL machine instead, WITHOUT consuming any
# Actions quota. This script is the body that a disabled GitHub workflow
# (.github/workflows/local-release.yml) would invoke on a self-hosted runner;
# from a shell you run it directly:
#
#   scripts/local-release.sh               # build assets + publish + update tap
#   scripts/local-release.sh --build-only  # just assemble dist/ + SHA256SUMS.txt
#   scripts/local-release.sh --dry-run     # assemble dist/ and print what would push
#
# "publish as a minor update": bump REPKGER_VERSION in bin/repkger first, then
# run this; the release is created under the tag v<version> so a republish of
# the same version refreshes the tag + assets (stable download URLs).
#
# Requires: gh (authenticated), zip, ditto (macOS), shasum.
#   TAP_TOKEN  optional repo-scoped PAT for pushing to ksl-testing/homebrew-tap
#              (falls back to the existing gh auth when unset).

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"

MODE="publish"
[ "${1:-}" = "--build-only" ] && MODE="buildonly"
[ "${1:-}" = "--dry-run" ] && MODE="dryrun"

version="$(sed -n 's/^REPKGER_VERSION="\([^"]*\)"/\1/p' "$root/bin/repkger" | head -1)"
case "$version" in
    [0-9]*\.[0-9]*\.[0-9]*) ;;
    *) echo "bad REPKGER_VERSION in bin/repkger: '$version'" >&2; exit 1 ;;
esac
REPO="${REPO:-ksl-testing/repkger}"
TAP_REPO="${TAP_REPO:-ksl-testing/homebrew-tap}"
TAG="v$version"

command -v gh >/dev/null 2>&1 || { echo "gh not found" >&2; exit 1; }
command -v ditto >/dev/null 2>&1 || { echo "ditto not found (macOS required)" >&2; exit 1; }

echo ">> building repkger v$version for $REPO (mode: $MODE)"

# 1. Build the .app (GUI) fresh — embeds bin/repkger v$version
"$root/scripts/make-app.sh"

# 2. Assemble dist assets, mirroring .github/workflows/release.yml
dist="$root/dist"
rm -rf "$dist"
mkdir -p "$dist/repkger-cli"
cp "$root/bin/repkger" "$dist/repkger-cli/repkger"
cp "$root/bin/repkger" "$dist/repkger"
chmod +x "$dist/repkger" "$dist/repkger-cli/repkger"
(cd "$dist/repkger-cli" && zip -r -q "../repkger-$version.zip" repkger)
ditto -c -k --keepParent "$root/build/Repkger.app" "$dist/Repkger-$version.app.zip"
(cd "$dist" && shasum -a 256 repkger "repkger-$version.zip" "Repkger-$version.app.zip" > SHA256SUMS.txt)

cli_sha256="$(shasum -a 256 "$dist/repkger-$version.zip" | awk '{print $1}')"

echo ">> dist/$version:"
ls -la "$dist"
echo "cli_sha256=$cli_sha256"

[ "$MODE" = "buildonly" ] && { echo ">> build-only: done (nothing pushed)"; exit 0; }

# 3. Publish the release (refresh the tag if it already exists)
if [ "$MODE" = "dryrun" ]; then
    echo ">> --dry-run: would publish $TAG to $REPO and update $TAP_REPO"
    exit 0
fi

GH_TOKEN="${GH_TOKEN:-$(gh auth token 2>/dev/null || true)}"
NOTES="$(mktemp)"
{
    echo "Local/self-hosted build of repkger v$version (no GitHub Actions quota)."
    echo
    echo "## Assets"
    echo "- \`repkger\` — the CLI (single bash file; also embedded in the app)"
    echo "- \`repkger-$version.zip\` — CLI zip (used by the Homebrew tap)"
    echo "- \`Repkger-$version.app.zip\` — drag to ~/Applications or /Applications (ad-hoc signed)"
    echo "- \`SHA256SUMS.txt\` — checksums"
    echo
    echo "## Homebrew"
    echo '    brew install ksl-testing/tap/repkgr'
} > "$NOTES"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo ">> refreshing existing release $TAG"
    gh release delete "$TAG" --repo "$REPO" --yes --cleanup-tag
fi
gh release create "$TAG" \
    "$dist/repkger" \
    "$dist/repkger-$version.zip" \
    "$dist/Repkger-$version.app.zip" \
    "$dist/SHA256SUMS.txt" \
    --repo "$REPO" \
    --title "repkger v$version" \
    --notes-file "$NOTES"
rm -f "$NOTES"
echo ">> published $TAG"

# 4. Update the homebrew tap for feature parity (same version everywhere)
echo ">> updating homebrew tap $TAP_REPO"
if [ -n "${TAP_TOKEN:-}" ]; then
    VERSION="$version" CLI_SHA256="$cli_sha256" TAP_TOKEN="$TAP_TOKEN" \
        "$root/scripts/update-tap.sh"
else
    # fall back to gh auth for the tap push when no PAT is supplied
    (cd "$root" && VERSION="$version" CLI_SHA256="$cli_sha256" \
        "$root/scripts/update-tap.sh")
fi

echo ">> local release v$version complete: $REPO + $TAP_REPO are in parity"
