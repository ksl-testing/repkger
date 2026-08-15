#!/usr/bin/env bash
# =============================================================================
# PLACEHOLDER — NOT IMPLEMENTED (dummy, non-working file)
# =============================================================================
# This is a TODO marker for future release automation, NOT a working script.
# Do NOT wire it into anything and do NOT expect it to publish. Running it
# prints this notice and exits non-zero on purpose.
#
# When GitHub Actions is re-enabled (the account billing block is cleared —
# see HANDOFF.md), either (a) let .github/workflows/release.yml take over
# again, or (b) flesh this out into a gh-CLI-based release script so releases
# ship with ZERO Actions quota. The manual steps below are the ones actually
# used to publish v0.2.0 on 2026-08-15 — turn them into the script body.
#
# --- intended future flow (manual gh CLI, no Actions) ------------------------
#   set -euo pipefail
#   V="$(sed -n 's/^REPKGER_VERSION="\([^"]*\)"/\1/p' bin/repkger | head -1)"
#
#   1. Sanity gate:   bash test/roundtrip.sh            # expect 28 passed
#   2. Build the app: bash scripts/make-app.sh          # -> build/Repkger.app
#   3. Assemble dist/:
#        rm -rf dist/repkger-cli; mkdir -p dist/repkger-cli
#        cp bin/repkger dist/repkger-cli/repkger && cp bin/repkger dist/repkger
#        chmod +x dist/repkger dist/repkger-cli/repkger
#        (cd dist/repkger-cli && zip -r -q "../repkger-$V.zip" repkger)
#        ditto -c -k --keepParent build/Repkger.app "dist/Repkger-$V.app.zip"
#        (cd dist && shasum -a 256 repkger "repkger-$V.zip" "Repkger-$V.app.zip" > SHA256SUMS.txt)
#   4. Publish (refresh if the tag exists):
#        gh release view "v$V" --repo ksl-testing/repkger >/dev/null 2>&1 \\
#          && gh release delete "v$V" --repo ksl-testing/repkger --yes --cleanup-tag
#        gh release create "v$V" dist/repkger "dist/repkger-$V.zip" \\
#          "dist/Repkger-$V.app.zip" dist/SHA256SUMS.txt \\
#          --repo ksl-testing/repkger --title "repkger v$V"
#   5. Tap formula (still needs a repo-scope TAP_TOKEN PAT):
#        VERSION="$V" CLI_SHA256="$(shasum -a 256 dist/repkger-$V.zip | awk '{print $1}')" \\
#          TAP_TOKEN=ghp_xxx scripts/update-tap.sh
#
# TODO (automation, deferred):
#   - [ ] Convert the steps above into real script logic.
#   - [ ] Add `--dry-run` + `--skip-test` + `--skip-tap` flags.
#   - [ ] Decide whether to keep .github/workflows/release.yml or delete it
#         once this script is the canonical release path.
# =============================================================================

echo "scripts/release-gh.sh: PLACEHOLDER — not implemented (see header comments)" >&2
exit 1
