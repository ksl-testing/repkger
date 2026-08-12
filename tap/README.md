# ksl-testing/homebrew-tap

Personal Homebrew tap for [repkger](https://github.com/ksl-testing/repkger) — a
rootless .pkg installer for macOS: unpacks any installer package into `~/`
equivalents, no admin, no sudo.

```bash
brew install ksl-testing/tap/repkgr
```

`repkgr` and `repkger` are aliases for the same formula (both install the
`repkger` CLI). Current version: **repkgr v__VERSION__**.

This tap is updated automatically by the
[repkger release pipeline](https://github.com/ksl-testing/repkger/actions)
every time the source changes — do not edit the generated formulas by hand
(they come from the `tap/` templates in the repkger repo).
