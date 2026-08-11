# repkger — rootless macOS .pkg unpacker / installer (no admin, no sudo)

Unpacks the contents of **any** Apple installer `.pkg` into locations the current
user can actually write to. Default behavior: keep system locations the user can
already write to (e.g. `/Users/Shared`), re-target everything else to `~/`
equivalents (`/Applications` → `~/Applications`, `/Library` → `~/Library`,
`/usr/local` → `~/.local`, ...). No `installer`, no GUI installer, no
escalation — works even on privilege-locked accounts.

## Quick start

```bash
bin/repkger inspect  ~/Downloads/GameMaker-2024.14.4.222.pkg   # read it like Suspicious Package
bin/repkger install  ~/Downloads/GameMaker-2024.14.4.222.pkg   # home-rooted install
bin/repkger list                                                # installed records
bin/repkger uninstall com.yoyogames.gms2 --yes                  # reverse an install
bin/repkger brew --cask gamemaker                               # rootless install of a pkg-style cask
bin/repkger self-install                                        # symlink into ~/bin + brewpkg() in ~/.zshrc
```

## Validated

- **GameMaker 2024.14.4.222** (single component `com.yoyogames.gms2`,
  `/Applications`, 17,480 BOM entries, ~800 MB payload): `inspect` + `install`
  + `uninstall` all verified end-to-end on this machine (2026-08-10).
  - install → `~/Applications/GameMaker.app`, 9,327 files recorded, stale
    `/Applications` refs rewritten in 33 files, ad-hoc re-signed.
  - uninstall → 8,235 files + 1,093 dirs removed; tree fully reversed.
- Dry-run (`--list-only`) shows the exact mapping without touching anything.

## Design

- Expand: `pkgutil --expand-full` (extracts payloads to dirs; handles modern
  compression). Fallback: `xar` + manual `gunzip|cpio` / `pbzx`.
- Map: user `--map SRC=DEST` > keep-if-writable > world-writable-keep
  (`/Users/Shared`, `/tmp`) > home-rooted defaults.
- Merge: tree-walk that remaps only at mapping boundaries, `ditto` whole
  subtrees (preserves symlinks/AppleDouble/perms).
- Rewrite: perl pass converting stale absolute installer paths in installed
  text/plist files; idempotent (protect-convert-restore).
- Record: `~/.repkger/records/<id>-<ver>-<sha8>/record.tsv` — the BOM of what
  actually landed (skips `._*` AppleDouble that pkgutil folds into xattrs) →
  deterministic `uninstall`.
- Scripts: never run by default; recorded (name + md5) for auditing;
  `--run-scripts` opts in.

## ⚠️ Known bug (2026-08-10) — see `llms.md`

The rewrite/codesign passes originally scanned the whole mapped top-level dir
(`~/Applications`), which **rewrote `/Applications`, `/bin`, `/Library` refs
inside OTHER apps' bundles** in `~/Applications` and ad-hoc re-signed 10
bundles. Files in the user's `~/Applications` (Freebuff, FamiStudio, MacNdCheese
Launcher, Suspicious Package, TPLDIH BootKit, Remove Autodesk Fusion, Platypus,
...) still need the reverse-rewrite described in `llms.md`. The code currently
on disk still has the broad-scan behavior — fix before any further real installs.

## Roadmap

See `llms/ROADMAP.md`: GUI `.app` (AppleScript droplet), brew integration
(formula + cask + `repkger brew` wrapper), `ksl-testing/homebrew-tap`
integration, GitHub repo push.
