#!/usr/bin/env bash
# Publish (or refresh) the ksl-testing/homebrew-tap formulas for repkger.
#
# Called by .github/workflows/release.yml after every release. Creates the tap
# repo on first run; otherwise updates Formula/repkgr.rb + Formula/repkger.rb
# (and the tap README) from the tap/*.rb templates with the new release URL
# and sha256, then pushes — so `brew install ksl-testing/tap/repkgr` always
# gets the latest build.
#
# Required env:
#   VERSION       repkger version, e.g. 0.2.0
#   CLI_SHA256    sha256 of the repkger-<VERSION>.zip release asset
#   TAP_TOKEN     GitHub PAT with repo scope. When unset the script prints a
#                 notice and exits 0 (the release itself still succeeds — the
#                 tap just isn't updated until a PAT is configured).
#
# Optional env:
#   REPO       owner/repo hosting the release assets (default ksl-testing/repkger)
#   TAP_REPO   tap repo to update                (default ksl-testing/homebrew-tap)
#
# Usage:
#   scripts/update-tap.sh [--dry-run]                    # print formulas, touch nothing
#   VERSION=0.2.0 CLI_SHA256=abc... TAP_TOKEN=ghp_xxx \
#     scripts/update-tap.sh

set -euo pipefail

DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
tmpl_dir="$root/tap"

REPO="${REPO:-ksl-testing/repkger}"
TAP_REPO="${TAP_REPO:-ksl-testing/homebrew-tap}"

VERSION="${VERSION:-}"
CLI_SHA256="${CLI_SHA256:-}"
TAP_TOKEN="${TAP_TOKEN:-}"

if [ -z "$VERSION" ] || [ -z "$CLI_SHA256" ]; then
    echo "update-tap: VERSION and CLI_SHA256 are required" >&2
    exit 1
fi
printf '%s' "$CLI_SHA256" | grep -Eq '^[0-9a-f]{64}$' \
    || { echo "update-tap: CLI_SHA256 must be 64 hex chars (got: $CLI_SHA256)" >&2; exit 1; }

URL="https://github.com/$REPO/releases/download/v$VERSION/repkger-$VERSION.zip"

render() {  # $1 = template file -> stdout with placeholders substituted
    sed -e "s|__URL__|$URL|g" \
        -e "s|__SHA256__|$CLI_SHA256|g" \
        -e "s|__VERSION__|$VERSION|g" "$1"
}

render_formulas() {  # $1 = tap repo dir (must exist)
    mkdir -p "$1/Formula"
    render "$tmpl_dir/repkgr.rb"  > "$1/Formula/repkgr.rb"
    render "$tmpl_dir/repkger.rb" > "$1/Formula/repkger.rb"
    render "$tmpl_dir/README.md"  > "$1/README.md"
}

if [ "$DRY" -eq 1 ]; then
    echo "== would publish $TAP_REPO (version $VERSION, sha256 $CLI_SHA256) =="
    echo "== url: $URL =="
    for f in repkgr.rb repkger.rb; do
        echo
        echo "--- Formula/$f ---"
        render "$tmpl_dir/$f"
    done
    exit 0
fi

if [ -z "$TAP_TOKEN" ]; then
    echo "update-tap: TAP_TOKEN not set — skipping tap update (release is still published)."
    echo "            Add a PAT (repo scope) as the TAP_TOKEN secret on ksl-testing/repkger to enable it."
    exit 0
fi

command -v git >/dev/null 2>&1 || { echo "update-tap: git not found" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

clone_url="https://x-access-token:${TAP_TOKEN}@github.com/${TAP_REPO}.git"

if ! git clone --quiet "$clone_url" "$tmp/tap" 2>/dev/null; then
    # first run: the tap repo doesn't exist yet — create it with gh
    command -v gh >/dev/null 2>&1 || { echo "update-tap: gh not found; cannot create $TAP_REPO" >&2; exit 1; }
    echo "update-tap: creating $TAP_REPO ..."
    mkdir -p "$tmp/tap"
    git -C "$tmp/tap" init -q -b main
    git -C "$tmp/tap" config user.name "repkger release bot"
    git -C "$tmp/tap" config user.email "noreply@github.com"
    render_formulas "$tmp/tap"
    git -C "$tmp/tap" add -A
    git -C "$tmp/tap" commit -q -m "repkgr v$VERSION"
    GH_TOKEN="$TAP_TOKEN" gh repo create "$TAP_REPO" --public \
        --source "$tmp/tap" --push --remote origin >/dev/null \
        || { echo "update-tap: gh repo create failed (does the PAT have repo + repo create scopes?)" >&2; exit 1; }
    echo "update-tap: created $TAP_REPO and pushed repkgr v$VERSION"
    exit 0
fi

cd "$tmp/tap"
git config user.name "repkger release bot"
git config user.email "noreply@github.com"

render_formulas "$tmp/tap"
git add Formula/repkgr.rb Formula/repkger.rb README.md
if git diff --cached --quiet; then
    echo "update-tap: no formula changes (tap already at v$VERSION)"
else
    git commit -q -m "repkgr v$VERSION (sha256 ${CLI_SHA256:0:12}...)"
fi

# push to the remote's default branch (fall back: main, then master)
BR="$(git ls-remote --symref "$clone_url" HEAD 2>/dev/null | awk '/^ref:/{print $2; exit}' | sed 's#refs/heads/##')"
[ -n "$BR" ] || BR="main"
if ! git push -q origin "HEAD:$BR"; then
    echo "update-tap: push to $BR failed, retrying master" >&2
    git push -q origin HEAD:master
fi
echo "update-tap: pushed Formula/repkgr.rb + Formula/repkger.rb to $TAP_REPO ($BR)"
echo "            next: brew install ksl-testing/tap/repkgr"
