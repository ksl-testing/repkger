# AGENTS.md — session learnings for repkger

Terse, hard-won facts that aren't recoverable from the code or README/NOTES.
Read these before touching the matching areas.

## Testing (test/roundtrip.sh)

- `check "desc" <cmd>` redirects `<cmd>`'s stdout to /dev/null — a pipe placed
  *outside* the call (`check … lsbom | grep`) feeds grep empty input and dies
  under `set -euo pipefail` with a misleading "ok printed then exit 1". Capture
  output into a variable first (e.g. `BOM5="$(lsbom …)"; check … grep -q <<<"$BOM5"`).
- "No raw ref" assertions must not use `grep -F '/Applications/…'`: the mapped
  path `$H5/Applications/…` contains that substring. Match path-root positions
  only: `grep -E '(^|[[:space:]])/Applications/MiniApp.app'`.
- Fixture `postinstall` carries stale `/Applications`, `/Library`, `/usr/local`
  refs deliberately — phase 5 verifies the redone pkg's embedded script is
  home-mapped. Don't "simplify" them away.

## pkg internals / tools

- `xar -xf <pkgbuild-made.pkg> Scripts` extracts the Scripts member as a
  **gzip-compressed cpio file**, not a dir: inspect with
  `gunzip -dc Scripts | cpio -id`. (Same for any pkgbuild output.)
- A redone pkg's install-location is only in `PackageInfo`
  (`install-location="…"`); `lsbom` shows BOM paths **relative** to that root
  (`./Applications/…`), so destination assertions must grep PackageInfo.
- `pkgbuild --scripts` refuses unknown script names and arch-suffixed variants
  (`postinstall-e`) — the fallback in `cmd_bom_redo` retries without `--scripts`.

## Architecture decisions (deliberate, not bugs)

- Payload rewrite and embedded-script rewrite use **different pairs sets**:
  `script_rewrite_pairs` drops `/usr`, `/bin`, `/sbin` (and keeps all user
  `--map`s) so `#!/bin/sh` and `/usr/bin/env` in redone-pkg scripts still
  resolve to real system tools. Don't "unify" them.
- `--only` pruning: unmatched dirs that merely *contain* a requested prefix
  must still be descended into — recursion condition is
  `has_boundary || only_below(vc)`, and only the emit/merge branch requires
  `only_match(vc)`. A naive top-level prune drops the whole subtree.
- `bom_redo_leaves` emits `src<TAB>mapped<TAB>virtual-path` — the third field
  is what callers should display (basename alone shows `Shared` for
  `/Users/Shared`).

## brew wrapper — default rootless for `--cask`

- `repkger brew install --cask <name>` **always** intercepts pkg/dmg/zip
  casks rootlessly (no `--rpkg` needed). Non-pkg casks pass through to
  real brew. `--rootless` (alias for `--rpkg`, or `-r`) additionally dies on
  non-pkg casks instead of passing through.
- The `brew()` shim (added by `repkger self-install`) intercepts
  `brew install --cask <name>` by default and routes to `repkger brew`.
  It also installs `brewpkg()`, `rbrew()` (force rootless), and `rpkg()`
  (alias for `repkger`) shell functions and puts `~/bin` on PATH so the
  shim can find `repkger`. `-r` is accepted by both `repkger brew` and the
  `brew()` shim; `--rootless`/`--rpkg` are the other force flags.
- `cmd_brew` arg parsing: `--rpkg|--rootless|-r` all set `rpkg=1`.
  The variable is still named `rpkg` internally.
- Homebrew visibility: `repkger brew install --cask <name>` auto-links the
  install into Homebrew's Caskroom (`<prefix>/Caskroom/<cask>/<ver>/<app>.app`
  symlink + `.metadata/INSTALL_RECEIPT.json`) so `brew list --cask <name>`
  reports it. `repkger brew link/unlink <cask>` manage it by hand. The
  app path is taken from the record's `file … <app>.app` dir entry (NOT a
  scan of ~/Applications — that can grab the wrong app, e.g. when
  `Visual Studio Code.app` sorts before `GameMaker.app`).
- CRITICAL TEST GOTCHA: `cask_link_receipt`/`cask_unlink_receipt` derive the
  prefix via the `brew_prefix` helper (resolves `command -v brew` and walks
  up — does NOT execute `brew`). Do NOT call `brew --prefix` there:
  `test/roundtrip.sh` phase 4 stubs `brew`, and any non-`info` call to it
  fails the "fake brew only saw 'info'" assertions.
- Test: `test/roundtrip.sh` phase 4 has `brew install --cask (no --rpkg)`,
  `brew --rootless`, `brew --rpkg`, `zip`, `dmg` cases (112 total checks
  as of 0.5.1+, all passing).

## GUI (Python/Tk, not the old droplet)

- The GUI is `gui/repkger_gui.py` (Python/Tk), built into `build/Repkger.app`
  by `scripts/make-gui-app.sh`. The old `gui/Repkger.applescript` droplet is
  kept ONLY for the Noren Suite build. The droplet mishandled launch argv
  (`{"current application"}`) and errored on open — that's why the GUI is
  Python/Tk now: double-click, Finder drag-drop, and "Open With" all work.
- The Tk GUI's `--smoketest <file>` mode prints the repkger command it
  *would* run (no window, no execution) — use it to validate wiring
  headlessly. The embedded CLI is `Contents/Resources/repkger`; the GUI
  finds it via a path relative to its own `Contents/MacOS`.
- macOS has no `tk` in the system Python? No — `/usr/bin/python3` ships
  tkinter. (If you rebuild on a box without it, `brew install python-tk`.)

## bash heredoc gotcha (macOS bash 3.2)

- `bash -n` on macOS DOES parse the body of a quoted heredoc
  (`func_block=$(cat <<'FUNC' … FUNC)`). A `case` pattern with `|`
  alternation inside that heredoc triggers a parser quirk
  (`syntax error near unexpected token ';;'`) even though the same pattern
  is valid outside a heredoc. When generating shell code into a heredoc
  (e.g. the `self-install` func_block), use `if/elif` chains instead of
  `case … | … )` patterns.

## Brew cask packaging (repkger cask)

- To expose the embedded CLI on PATH from the GUI cask, do NOT use a
  `postflight` with `Symlink.new(...)` — the cask loader doesn't define
  `Symlink` and it dies with `uninitialized constant ... Symlink`
  (`tap/Casks/repkger.rb`). Use the `binary` stanza instead:
  `binary "#{appdir}/Repkger.app/Contents/Resources/repkger", target: "repkger"`
  (brew symlinks it into `HOMEBREW_PREFIX/bin` and auto-removes it on uninstall).
- `repkger` repo is PUBLIC (changed from private on 2026-08-29) so the
  formula/cask download release assets anonymously — `gh release download` works
  either way, but plain `brew install` cannot auth, so private assets 404 for brew.

## Version

- Current: 0.5.2 (bin/repkger `REPKGER_VERSION`). Bump for releases.
