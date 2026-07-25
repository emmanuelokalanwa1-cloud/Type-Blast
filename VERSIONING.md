# Versioning

Currently in `export_presets.cfg`: `version/code=1`, `version/name="1.0.0"`
— still pre-first-release. This file exists so version bumps don't become
a thing you have to remember the rules for each time.

## The two numbers, and why both matter

- **`version/name`** (`"1.0.0"`) — the human-facing version, shown to
  players. Semantic versioning: `MAJOR.MINOR.PATCH`.
  - PATCH: bug fixes, no new content (`1.0.0` → `1.0.1`)
  - MINOR: new content/features, backward-compatible saves (`1.0.1` → `1.1.0`)
  - MAJOR: breaking change — old saves need migration, or a fundamental
    redesign (`1.1.0` → `2.0.0`)

- **`version/code`** (`1`) — Android's internal build number. **Must
  increase by at least 1 on every single upload to Google Play**, even a
  same-day hotfix, even if `version/name` doesn't change. Google Play
  rejects an upload with a `version/code` it's already seen. iOS has an
  equivalent (`CFBundleVersion`) with the same rule — check the iOS
  export preset separately since it isn't tied to the Android field.

Easy failure mode: bump `version/name` and forget `version/code`, upload
gets rejected, you're debugging a rejection instead of shipping.

## Before every submission

1. Bump `version/code` (always) and `version/name` (per the rules above)
   in `export_presets.cfg`
2. Add an entry to `CHANGES.md` under a new version heading — see format
   below
3. Tag the commit you're shipping (`git tag v1.0.1`) so a specific build
   can always be traced back to exact source

## CHANGES.md format going forward

`CHANGES.md` currently documents an internal refactor, not a
player-facing changelog. Once you ship, add player-facing entries above
that section:

```markdown
## 1.0.1 — 2026-08-01
- Fixed: Daily Challenge share codes with accented characters failed to decode
- Fixed: Career rank-up certificate sometimes didn't appear on rank 20

## 1.0.0 — 2026-07-30
- Initial release
```

Keep these entries in plain language a player would understand — "Fixed:
X" and "Added: Y", not the internal refactor notes further down the file.
