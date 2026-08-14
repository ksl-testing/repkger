# repkger — LLM handoff doc (read this first)

> Written 2026-08-10, updated 2026-08-11 (v0.2.0). Purpose: let a **cacheless
> LLM** (or a human) pick up this project in ≤5 minutes. Everything below is
> the current truth; re-read files before editing (they may have changed).

## What this project is

A macOS tool that installs Apple installer `.pkg` files **without admin / sudo /
`installer` / the pkg GUI**. It re-targets every install path to somewhere the
current user can write (`~/Applications`, `~/Library`, `~/.local`, ...), keeps
world-writable locations (`/Users/Shared`) in place, rewrites stale absolute
path references inside installed files, strips `com.apple.quarantine` from each
target **and its parent dir**, records exactly what landed, and can reverse it.
It also inspects `.pkg` files the way *Suspicious Package* does (components, BOM
file lists, scripts, versions) — including a `--files` view of where each BOM
entry will land after re-mapping. A `brew` wrapper intercepts
`brew install --cask <name>` for casks that ship a `.pkg` (e.g. `gamemaker`)
and installs them rootlessly. A GUI droplet app (`build/Repkger.app`) wraps the
inspect + install + uninstall flows.

Origin: generalization of the CSP_Mac project's `install_portable.sh`
(`~/Documents/GitHub/CSP_Mac`), which did the same thing for one specific pkg.

## Repo layout

```
bin/repkger             # the whole CLI — single bash script (macOS bash 3.2 compatible)
gui/Repkger.applescript # the GUI droplet source (osacompile target)
scripts/make-app.sh     # builds build/Repkger.app from the droplet + CLI + metadata
test/make-fixture.sh    # builds a tiny synthetic mini.pkg for the fast test loop
README.md               # overview + quick start
llms.md                 # THIS FILE — handoff
llms/STATUS.md          # detailed status + remaining work
llms/ROADMAP.md         # GUI .app, brew integration, tap integration
NOTES.md                # dev notes: architecture, validated behavior, gotchas
```

## Status (2026-08-11, v0.2.0)

### DONE + validated
- CLI: `inspect` (+ `--json`, `--show-scripts`, `--files [N]`), `install`,
  `uninstall`, `list`, `brew`, `gui`, `self-install`, `version`.
- **Rewrite/resign scope bug FIXED.** Rewrite + resign now operate only on the
  package's own landed files (BOM-driven `INSTALLED_FILES` list); dequarantine
  covers merged dirs + mapped install-location dirs. Validated with a decoy app
  pre-placed in a scratch `~/Applications`: it is never touched.
- **Rewrite nesting bug FIXED.** One perl pass with longest-prefix alternation
  that consumes the whole reference token: `/usr/local/bin` → `~/.local/bin`,
  `/usr/bin:/bin` PATH lists remap both, `/private/var` → `~/var`,
  `/Library/Application Support/...` spaces preserved, `--prefix=/usr/local/x`
  works, and re-running is a no-op (idempotent).
- **Quarantine parent handling.** `strip_quarantine` removes
  `com.apple.quarantine` (`xattr -dr`, recursive on targets; non-recursive on
  each target's parent dir so future copies don't re-inherit); if `-d` fails
  while the attr is present it falls back to clearing all xattrs (`-c`/`-cr`).
  Never walks `/` or `$HOME_ROOT` recursively.
- **GUI `Repkger.app` exists** (`build/Repkger.app`): droplet with
  `on open droppedItems`, mode chooser (Inspect / Install / Uninstall),
  Suspicious-Package-style inspect dialog with "Full Report" + "Install"
  buttons, headless `--install <pkg> [--home dir] [--data dir]` /
  `--inspect <pkg>` modes, embedded CLI in `Contents/Resources/repkger`,
  bundle id `com.ksl-testing.repkger`, `.pkg`/`.mpkg` doc types, ad-hoc
  signed. `repkger gui` finds it in `build/`, repo root, `~/Applications`,
  or `/Applications`.
- **GUI multi-select (2026-08-13)**: open dialog accepts multiple .pkg files
  (`choosePkgs`, `multiple selections allowed true`); mode chooser and
  drag-drop process each file independently in a loop with per-file
  `(i of n)` progress notifications; failures don't stop the batch.
  `make-app.sh` derives the version from `bin/repkger`'s `REPKGER_VERSION`
  instead of hardcoding.
- Fixed pre-existing bugs found along the way: single-component packages that
  expand with `PackageInfo` at the root (component_dirs now checks the root),
  `//` double-slash paths when install-location is `/` (which also broke
  keep-in-place for `/Users/Shared` + `/tmp`), SIGPIPE from `comp_scripts |
  grep -q` under `pipefail`, trailing exit-1 in `inspect`, `tcc_protected`
  walking the whole filesystem for install-location `/`, unrecorded
  `_CodeSignature` artifacts (now swept into the record after signing).
- Synthetic fixture validates everything without the 800 MB GameMaker pkg:
  `test/make-fixture.sh` → `/tmp/repkger-fixture/mini.pkg` (single component,
  install-location `/`, 22 BOM entries, preinstall/postinstall).
  Round-trip verified: install (25 files recorded incl. `_CodeSignature`) →
  uninstall → scratch home back to only the pre-placed decoy.

### OUTSTANDING — historical ~/Applications damage (this machine only)
The first real install (v0.1.0) ran the rewrite pass over the whole
`~/Applications` and ad-hoc re-signed other apps' bundles. The tool can no
longer cause this, but the damage is not yet reversed. Reversal procedure
(survey, reverse-rewrite, re-sign/reinstall) is in the old llms.md section
below, still valid.

## How to test (fast loop — no downloads needed)

```bash
R=$PWD/bin/repkger
test/make-fixture.sh                       # builds /tmp/repkger-fixture/mini.pkg
$R inspect /tmp/repkger-fixture/mini.pkg --files 12
rm -rf /tmp/rk-home /tmp/rk-data
REPKGER_DATA=/tmp/rk-data $R install /tmp/repkger-fixture/mini.pkg --home /tmp/rk-home --yes
REPKGER_DATA=/tmp/rk-data $R list
REPKGER_DATA=/tmp/rk-data $R uninstall com.test.miniapp --yes
find /tmp/rk-home | wc -l                  # expect 1 (only the root)

# GUI headless flow (no dialogs) — osascript ONLY:
PATH="$PWD/bin:$PATH" osascript gui/Repkger.applescript --install /tmp/repkger-fixture/mini.pkg --home /tmp/rk-home --data /tmp/rk-data
osascript build/Repkger.app --install /tmp/repkger-fixture/mini.pkg --home /tmp/rk-home --data /tmp/rk-data   # uses embedded CLI
scripts/make-app.sh                        # rebuild build/Repkger.app
# NOTE: droplets ignore argv when run directly (MacOS/droplet --install …) or
# via `open --args` — always drive headless tests through `osascript`, and
# pkill -f MacOS/droplet first (a stale instance swallows Apple events).
```

## Key implementation facts (gotchas learned)

- `pkgutil --expand-full` **refuses a pre-existing destination dir** ("File
  exists") — the script must `rm -rf` the target first. A single-component pkg
  expands with `PackageInfo` at the ROOT, not under `Contents/Packages/`.
- macOS BSD `sed` has **no `\b`** — attribute regexes must not use it.
- `lsbom` output is **tab-separated with spaces allowed inside the path** —
  parse with `awk -F'\t'`, never default whitespace splitting.
- BOM entries include `._*` AppleDouble files that `pkgutil --expand-full`
  folds into xattrs — they never exist on disk; the record skips non-existent
  entries (and uninstall works off the record).
- bash 3.2 (macOS system bash): `set -u` + empty array expansion errors —
  use `${arr[@]+"${arr[@]}"}` everywhere.
- EXIT traps must reference **global** vars, not function-locals (locals are
  out of scope when the trap fires).
- Don't pipe to `grep -q` under `set -o pipefail` without draining the
  producer (SIGPIPE abort noise) — capture to a variable first.
- `tcc_protected` must never run on `/` or `$HOME_ROOT` (`xattr -r` walks the
  whole disk).
- `installer manual:` in brew cask DSL does NOT run anything (just prints);
  `installer script:` runs as the current user with `reset_uid` — that's the
  rootless cask hook. `depends_on formula:` is valid in casks.
- GameMaker pkg facts: single component `com.yoyogames.gms2` v2024.14.4.222,
  install-location `/Applications`, preinstall entirely commented out,
  postinstall only chmods `/Users/Shared/GameMakerStudio2` dirs + relaunches.
  Upstream cask sha256 `8cbd33a9a92ed60ebd53734413b33afdeb8c677326ada0c80971e9f91555cc7f`.
- Rewrite must use the longest-prefix-first single-pass perl (`rewrite_one`);
  the old protect-convert-restore multi-pass double-rewrote tails
  (`/usr/local/bin` → `~/.local<...>/bin`).
- macOS names the About/Hide/Quit menu items from the executable FILE name,
  not argv[0]: `exec -a` fixes only the menu-bar title, and the dotnet muxer
  refuses to run when renamed — the reliable fix for a .NET app's menu name is
  a real apphost (generate via `dotnet publish` of a minimal project named
  after the app, then `exec` it next to the app's dll + runtimeconfig).
- **osacompile droplets ignore argv** when launched directly
  (`Contents/MacOS/droplet --install …` receives `{"current application"}` or
  nothing → falls into the mode-chooser dialog and hangs) and via
  `open --args`; headless automation must use `osascript <app-or-source>`.
  A stale running droplet intercepts Apple events and hangs new osascript
  calls — `pkill -f MacOS/droplet` first.
- **AppleScript handlers have NO optional parameters** — adding a param to
  `doInstall` broke every 3-arg call site with `-1721`; grep for all callers
  after changing arity.
- **CI round-trip (2026-08-13)**: `test/roundtrip.sh` phase 1 pins `--map`
  `/Applications`, `/Library`, `/usr/local` to the scratch home because the
  default keep-if-writable mapping keeps fixture files in the REAL system
  dirs on admin machines (GitHub runners) — the original test only passed on
  standard-user machines. 28/28 everywhere now.

## Next milestones (details in llms/ROADMAP.md)

1. **Unity Editor rootless install test** (user request; pkg downloaded at
   `~/Downloads/Unity-6000.3.22f1.pkg`, 5,133,313,381 bytes — sha256
   verify before use). Source URL:
   `https://download.unity3d.com/download_unity/1c726e1fb402/MacEditorInstaller/Unity.pkg`
   (6000.3.22f1 LTS; hash via
   `services.api.unity.com/unity/editor/release/v1/releases`). Plan:
   inspect → `install --home $HOME --yes` → launch Unity.app once →
   `uninstall` to verify reversal. See HANDOFF pending step 1.
2. **Release re-run**: this session's push auto-triggers the fixed pipeline
   (test fix in `test/roundtrip.sh`); verify `gh release view v0.2.0` and add
   the `TAP_TOKEN` secret.
3. Reverse the historical ~/Applications damage (procedure below).
4. ~~Brew formula pipeline~~ — DONE (see below; TAP_TOKEN still needed).
5. First publish — in progress via the pipeline (see item 2).

## Old v0.1.0 damage reversal (still pending)

#### Survey (interrupted earlier — re-run before reversing)
grep all of `~/Applications` (excluding GameMaker.app) for the new-form
prefixes: `/Users/tpldih/Applications`, `/Users/tpldih/Library`,
`/Users/tpldih/bin`, `/Users/tpldih/.local`, `/Users/tpldih/.usr`,
`/Users/tpldih/etc`, `/Users/tpldih/var`, `/Users/tpldih/opt`,
`/Users/tpldih/sbin`.

#### Reverse (only files that actually contain new-form strings; longest /
least-common prefixes first; binary plists via `plutil -convert xml1` first):
```bash
perl -pi -e '
  s{/Users/tpldih/bin/}{/bin/}g;
  s{/Users/tpldih/sbin/}{/sbin/}g;
  s{/Users/tpldih/\.local/}{/usr/local/}g;
  s{/Users/tpldih/\.usr/}{/usr/}g;
  s{/Users/tpldih/etc/}{/etc/}g;
  s{/Users/tpldih/var/}{/var/}g;
  s{/Users/tpldih/opt/}{/opt/}g;
  s{/Users/tpldih/Applications/}{/Applications/}g;
  s{/Users/tpldih/Library/}{/Library/}g' FILE
```
CAUTION: only reverse files that were actually rewritten; verify shebangs back
to `#!/bin/...`.

#### Re-sign affected bundles
`codesign --force --deep --sign - "PATH.app"` for each affected .app (NOT
GameMaker.app — it is intentionally rewritten). Prefer
`brew reinstall --cask suspicious-package platypus` (and famistudio from
ksl-testing/tap) to restore genuine vendor signatures.

## GitHub access & releases (ops)

Verified 2026-08-14 — re-check if push/release actions misbehave (last known
failure: 2026-08-13).

- Identity: `Kai SL <114260909+ksl-testing@users.noreply.github.com>`; HTTPS
  remotes; credential helper `gh auth git-credential` (token in macOS keychain).
- `gh auth status`: **ksl-testing** active; scopes `gist`, `read:org`, `repo`,
  `workflow` → push/pull to private repos + workflow file updates work.
- Verified: `git ls-remote` succeeded against every ksl-testing repo (clones in
  `~/Documents/GitHub` + `~/homebrew/library/taps/ksl-testing`). Push was not
  exercised end-to-end from the CLI on that date.
- 2026-08-13 incident: CLI push + `gh release create` failed; pushed manually
  via GitHub Desktop; no releases could be created. If a release is needed,
  run `gh auth status` first, then `gh release create`. Release uploads
  consume free-plan quota — fine for real releases, avoid churn.
- Housekeeping: READMEs/assets may be stale across projects; verify before
  trusting them.
