# Tests

No GUT or other test addon installed — this is a plain scene + script so it
runs with zero setup.

## Running

1. Open `tests/TestRunner.tscn` in the editor.
2. Press F6 (Run Current Scene) while it's the active tab.
3. Read the Output panel. Each check prints `PASS` or `FAIL`; a summary
   line totals both at the end.

The GameState save/load test writes to your **real** save file
(`user://keys_learning_save.cfg`) briefly, then restores whatever was there
before the test ran (backed up to `keys_learning_save.cfg.bak` during the
run, deleted after). If a test run is ever killed mid-way and your save
looks wrong, check for that `.bak` file next to the save and restore it
manually.

## What's covered

- `GameState` save → load round-trip for a representative field from each
  save section (scores, streaks, career, badges, language)
- `AchievementsManager.evaluate()` — maxed stats unlock something and only
  ever return real achievement ids; zeroed stats unlock nothing
- `CareerManager` rank-gating — rank 1 starts unlocked, rank 2 doesn't,
  `select_rank()` respects that gate
- `WordBank` blocklist — no theme pool (including the opt-in extended
  dictionary pool) ever contains a blocklisted word, so a future word-list
  regeneration can't silently reintroduce profanity/slurs
- `MissionManager.evaluate_run_end()` — a maxed-out run completes at least
  one mission, completed missions are never re-returned on a second call,
  and a zeroed/lost run completes nothing
- `PowerupSystem` — activation, expiry via `process()`, the score
  multiplier, per-kind cooldown gating, unrecognized-kind handling, and
  `reset()` clearing every piece of state
- Ghost Race code encode/decode round-trip (`GhostRacer._encode_ghost_code`
  / `_decode_ghost_code`) — the local, no-server clipboard share/compare
  feature: label + WPM survive the round trip, pipe characters in a label
  get sanitized, blank labels fall back to "Friend", and garbage/wrong-tag/
  zero-WPM input all fail closed instead of decoding into something wrong
- Save-file migration — a save written with only the two oldest fields
  (`high_scores`, `best_wpm`) and nothing else loads cleanly into the
  current `GameState`, with every newer field landing on its documented
  default instead of crashing or coming back null/wrong-typed

## What's NOT covered (worth adding next, in priority order)

1. `AiVersusMode` opponent difficulty scaling and match-result recording
   (`ai_versus_wins_total` / `ai_versus_record`) — currently only exercised
   indirectly through the save round-trip test, not through actual match
   logic
2. `LanMultiplayerManager` — host/join handshake and disconnect handling;
   hard to unit-test without two real peers, would likely need a mocked
   `ENetMultiplayerPeer` pair
3. `LocalizationManager.get_string()` parity across all 6 locale files for
   every key actually referenced in code (not just that the files parse) —
   would catch a screen calling a key that was added to `en.json` but
   never back-filled into the other five
4. `AccessibilityManager`'s colorblind GLSL shader modes — shader
   correctness isn't really unit-testable outside the renderer, but the
   mode-switching logic (which shader gets attached for which
   `colorblind_mode` value) could be

## Why not GUT

GUT (Godot Unit Test) is the standard addon and worth adopting once test
coverage grows past what fits comfortably in one file — it gives you
setup/teardown hooks, mocking, and CI integration. Installing it is a
5-minute AssetLib download; ask if you want it wired in along with a
proper CI run on every push.
