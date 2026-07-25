# What changed

`main.gd` used to hold the entire game in one 465-line file. It's now a thin
orchestrator; each concern lives in its own script under `res://scripts/`,
built and wired together at runtime (same "create it in code" style the
original already used for the pause button).

| File | Owns |
|---|---|
| `main.gd` | Wires everything together, drives the per-frame loop (spawn timer, falling, freeze/slow-mo, screen shake) |
| `scripts/word_bank.gd` | Word data: master list, themes (General/Nature/Tech/Adventure), boss words |
| `scripts/word_manager.gd` | Spawning + falling words, difficulty/theme/weak-key pool selection, power-up words |
| `scripts/game_state.gd` | Score, lives, combo, level, XP, timer, accuracy, WPM, missed words, save file |
| `scripts/powerup_system.gd` | Turns FREEZE / SLOWMO / BONUS words into real effects (was dead code before) |
| `scripts/typing_controller.gd` | Reads the input box, matches it against falling words |
| `scripts/ui_hud.gd` | HUD labels (incl. new WPM + live accuracy), floating text, particles, background theme, screen shake |
| `scripts/audio_manager.gd` | Music/SFX playback, volume, mute |
| `scripts/pause_menu.gd` | Resume / Restart / Quit / music+SFX sliders / mute |
| `scripts/difficulty_menu.gd` | Pre-game word-set + word-length + "practice weak keys" picker |
| `scripts/tutorial_overlay.gd` | First-run onboarding (combo, frenzy, boss words, shield, power-ups) |
| `scripts/stats_screen.gd` | Post-game screen: WPM, accuracy, best WPM, words you missed |

## New features

- **WPM** — live in the HUD, plus best-ever WPM saved and shown at game over.
- **Live accuracy %** — shown in the HUD during play, not just at the end.
- **Difficulty / word-set picker** — shown before each run: word theme
  (General/Nature/Tech/Adventure), word length (Short/Medium/Long/Mixed),
  and a "practice my weak keys" toggle that learns from words you miss.
- **Power-ups now do something** — sky-blue words spawn occasionally:
  FREEZE stops the fall, SLOWMO slows everything down, BONUS gives a life.
- **Real pause menu** — Resume, Restart, Quit, music/SFX volume sliders, mute.
- **Post-game stats screen** — WPM, accuracy, best WPM, and a list of the
  words you missed that run.
- **Onboarding** — a short first-time-only tutorial explaining combo,
  frenzy, boss words, shield and power-ups, before the difficulty picker.

## Content & systems expansion (this pass)

Everything below is **purely additive** - no existing script, scene, or save
key was modified. Nothing here is wired into gameplay yet, so the game
behaves exactly as before unless you choose to call these new APIs from a
screen or controller.

| New file | What it is |
|---|---|
| `scripts/sentence_bank.gd` | Data source for an optional "type whole sentences" mode. Same lazy-load/cache/fallback pattern as `word_bank.gd`. |
| `data/sentences/*.txt` | ~9,000 generated practice sentences (6 themes), built from the game's own real-word pools via templates - not copied from any book/article/song, so there's no licensing risk. |
| `scripts/achievements_manager.gd` | Loads `data/achievements.json` (108 achievements across speed/accuracy/endurance/combo/career/collection) and exposes a pure `evaluate(stats: Dictionary)` function. |
| `scripts/lore_manager.gd` | Loads `data/lore/rank_lore.json` - one original short narrative per Career rank (20 total), for a future "read more" panel. |
| `scripts/localization_manager.gd` | Loads `data/locales/*.json` - preliminary translations of ~50 core UI strings into Spanish, French, German, Portuguese, and Italian. Treat as a first draft, not final copy - worth a native-speaker pass before shipping. |
| `scripts/quotes_manager.gd` | Loads `data/quotes/motivational_quotes.txt` (130 original one-liners) for an optional quote-of-the-day. |
| `data/words/adventure.txt`, `data/words/space.txt` | Topped up with ~110 and ~74 additional real words respectively (the two thinnest theme pools). |

### Why the project didn't balloon to 40+ MB

Going from ~20MB to 40MB+ with content that's actually worth having would
mean either (a) real new audio/art assets - which I can't generate here -
or (b) padding the build with junk data to hit a number, which bloats
download size and load times for no player-facing benefit and can even get
a submission flagged on some app stores. I didn't do (b). What's here is
real: a new gameplay mode's worth of data, an achievements system, career
lore, localization scaffolding, and a bigger vocabulary - all reviewed for
correctness and none of it touching code that already works.

If you want to genuinely reach 40+ MB, the honest way is to add real
assets: more music tracks, a larger SFX set, higher-res art/particles, or
voice-over. I'm glad to help wire any of those in once you have the files.

### Now wired into the game (this pass)

You said "nothing changed" — that's because the first pass only added data
+ loader scripts, nothing calling them. This pass actually hooks them up:

- **Achievements screen** — new "ACHIEVEMENTS" button on the difficulty
  menu opens a full list (`achievements_screen.gd`), locked/unlocked based
  on your best WPM, accuracy, words typed, this-run combo, and career rank.
- **Sentence Practice mode** — new "SENTENCE PRACTICE" button opens a
  self-contained typing screen (`sentence_mode_screen.gd`): type the shown
  sentence, press Enter, see your WPM. Built as its own screen rather than
  changed into the falling-word loop, so the core game code is untouched.
- **Career lore** — the Career Path status card now shows a short original
  blurb for whichever rank is selected, pulled from `rank_lore.json`.
- **Quote of the day** — shown under the subtitle on the difficulty menu.

Achievements/localization/quotes still have a couple of loose ends you may
want to finish later: `best_combo` uses this-run combo (not an all-time
best, since GameState doesn't persist one yet), and the 5 language files
aren't attached to any language switcher UI yet — they're just data ready
to be read from `LocalizationManager.get_string()` whenever you add one.

## Notes

- Save data (high scores, best WPM, settings, tutorial-seen flag) is now in
  `user://keys_learning_save.cfg` (was `user://leaderboard_final.cfg`), so
  scores reset once on first run of this version.
- No new audio assets were added — the power-up sound reuses the existing
  "correct" SFX at a higher pitch so nothing needs re-importing.
- Everything is Godot 4.6 GDScript, matching the project's existing setup.

---

# 25-feature expansion pass

Two lists, both fully wired in: the 10 gaps identified from reading the
codebase, plus 15 brand-new modes/systems. Same rule as always — additive
only. `main.gd`, `word_manager.gd`, `typing_controller.gd`, `ui_hud.gd`,
`career_screen.gd`, `stats_screen.gd`, `achievements_screen.gd`, and
`powerup_system.gd` (the highest-risk, most central files) were **not**
touched at all. Everything new lives behind one new button.

## The one new entry point

`difficulty_menu.gd` gained a single **"MORE"** button (matching the
existing icon-badge button style). It opens `more_screen.gd`, a hub screen
built exactly like `achievements_screen.gd`/`missions_screen.gd` — except
instead of one purpose, it's a small internal router that swaps a content
panel between: **Practice Modes, Leaderboard, Badges, Career Lore,
Practice Calendar, Settings, Share/Export**. `main.gd` only needed 3 lines
(instantiate it, connect the one signal, add it to the existing
visibility-gating checks) since every sub-feature lives inside this one
screen rather than as its own top-level overlay.

## The original 10 gaps — now filled

1. **Language switcher** — Settings panel in MORE. Picks from the 6
   existing locale files and saves the choice (`selected_language`).
2. **All-time best combo** — `GameState.best_combo`, updated in `end_run()`
   alongside the existing this-run combo tracking. Shown on the
   Leaderboard panel.
3. **Collectibles** — `badges_manager.gd`: 13 badges (speed, combo,
   accuracy, streaks, sentences, daily challenge, boss battle, career
   rank, missions). Evaluated every time MORE opens; new unlocks show as
   a banner at the top of the hub.
4. **Sentence Practice → Missions** — two new missions in `mission_data.gd`
   ("Complete 5 sentences", "Reach 40 WPM in Sentence Practice"), checked
   by a new `MissionManager.evaluate_sentence_practice()` that only
   touches those two mission types — it can't accidentally complete a
   normal run mission.
5. **Daily streak** — `GameState.current_streak` / `longest_streak`,
   updated once per calendar day from `update_streak()` (called from both
   the difficulty menu and MORE). Shown in the hub header and the
   Practice Calendar panel.
6. **Drill My Mistakes** — `GameState.missed_words_persistent`, a capped
   (100), deduped, cross-run pool fed every time you miss a word
   (`register_miss()`) or fail a word in a practice session. One of the
   six Practice Modes.
7. **Custom word list** — small in-app text editor (one word per line, or
   comma/space separated) under Practice Modes → Custom Word Practice.
   Saved to `GameState.custom_word_list`.
8. **Accessibility settings** — high contrast toggle, font-size slider,
   colorblind-palette picker, all in the Settings panel and persisted.
   Honest caveat: these save correctly today; wiring every existing
   screen's actual colors/fonts to read them is the natural next pass.
9. **Leaderboard panel** — top scores, best WPM/combo, last 12 runs
   (`GameState.run_history`, capped at 50), plus a "personal best"
   comparison against your most recent run.
10. **Full career lore viewer** — reads every rank via
	`CareerData.rank_count()` + `LoreManager`, shown as one scrollable list
	instead of only the current rank's blurb.

## 15 new features

11. **Daily Challenge** — same 25 words for everyone each day
    (`WordBank.get_daily_words()`, date-seeded), one graded attempt,
    best score saved per day.
12. **Personal-best "ghost" comparison** — see #9; your last run vs. your
    best-ever run, shown on the Leaderboard panel.
13. **Typing Test** — standard 60-second WPM test, same formula
    (`chars / 5 / minutes`) as Sentence Practice already used.
14. **Boss Battle** — long words (8+ letters) only, 3 lives, a per-word
    timer that shrinks the longer you survive.
15. **Sound Packs** — Classic / Arcade / Chill, a pitch multiplier applied
    to every existing SFX (`audio_manager.gd`) — no new audio files.
16. *(folded into #15 — one settings entry, not a separate system)*
17. **Practice Calendar** — a 28-day heatmap built from `run_history`
    dates, plus the streak counters from #5.
18. **Share/export stats** — a plain-text "share card" (best WPM, combo,
    streak, badges, career rank), copy-to-clipboard or save to
    `user://share_card.txt`.
19. **Zen Mode** — untimed, no lives, just type. Uses your selected theme.
20. **Adaptive difficulty (practice modes)** — Boss Battle's per-word timer
	is the concrete version of this: it shrinks based on how many words
	you've survived in the current session.
21. **Recently unlocked badges** — MORE shows a banner the moment a new
    badge unlocks, instead of only being visible if you go looking for it.
22. **Keyboard-layout-aware weak-key report** — `keyboard_layout_manager.gd`
    groups your existing `weak_letter_counts` by hand/finger for QWERTY,
    AZERTY, or Dvorak, shown in Settings.
23. **Rotating tips** — `tips_manager.gd`, 10 short tips.
24. **Word of the Day** — `vocabulary_manager.gd`, a 30-word curated list
    with original one-line definitions, date-seeded, shown in the MORE
    header.
25. **Custom Word Practice** — see #7; the editor + practice mode together.

## New files

`scripts/more_screen.gd`, `scripts/practice_session.gd` (the shared
word-by-word engine behind Zen/Drill/Custom/Typing Test/Daily
Challenge/Boss Battle), `scripts/badges_manager.gd`,
`scripts/vocabulary_manager.gd`, `scripts/tips_manager.gd`,
`scripts/keyboard_layout_manager.gd`.

## Edited files (all additive)

- `scripts/game_state.gd` — new persisted fields (best combo, run history,
  streaks, persistent missed words, badges, settings, custom words, daily
  challenge, sentence count) + helper methods. No existing field or method
  signature changed.
- `scripts/mission_data.gd` / `scripts/mission_manager.gd` — two new
  mission entries + one new evaluator method, additive only.
- `scripts/sentence_mode_screen.gd` — routes through the new
  `register_sentence_practice()` instead of mutating `best_wpm` directly;
  optional `mission_manager` param (defaults to `null`, so nothing else
  calling `setup()` breaks).
- `scripts/audio_manager.gd` — sound-pack pitch multiplier (defaults to
  1.0 — identical sound if never touched).
- `scripts/difficulty_menu.gd` — one new button, one new signal, one line
  calling `update_streak()`.
- `main.gd` — instantiate `MoreScreen`, wire its signal, add it to the
  existing visibility-gating checks (touch input + Android back button).

## What wasn't done (being upfront about scope)

- Accessibility settings persist but aren't yet read by the existing
  screens' rendering — see #8.
- "Adaptive difficulty" for the main falling-word game (not just practice
  modes) would mean editing `word_manager.gd`'s spawn logic, which was
  deliberately left alone to avoid touching the riskiest file in the
  project.
- None of this has been run inside the Godot editor (no engine available
  here) — it's been checked for matching APIs/signatures and balanced
  syntax against the real codebase, but give it a run before you ship it.

## Asset integration pass (fonts, badges, career ranks, app icon)

Sourced from three asset dumps (fonts, app icons; Kenney Medals, Vector
Ranks, Aethermint reward widgets; misc packs). Everything below is real,
licensed-for-games art wired into existing systems — nothing was dumped in
unused. See "What was left out" for the packs that didn't make the cut and why.

- **Font, project-wide** — Space Mono (SIL OFL, `assets/fonts/`) is now the
  default font for the *entire game*, set once via
  `project.godot [gui] theme/custom -> assets/fonts/game_theme.tres`. Every
  screen picks it up automatically with zero per-screen changes, since none
  of them override `font` (only `font_size`). `scripts/game_fonts.gd` adds
  the Bold weight as an opt-in for hero titles (ACHIEVEMENTS, RANK UP!).
- **Achievements + Badges, consolidated** — these were two disconnected
  systems (108 granular `achievements.json` records on one screen, 13
  curated `BadgesManager` milestones buried in the More screen, no shared
  visuals, no link between them). Now:
  - `scripts/achievement_icons.gd` (new) gives both systems the same
    Kenney Medals (CC0) icon set, mapped by category/badge id, replacing
    the old plain "★/○" glyphs and emoji.
  - The Achievements screen now opens with a "MILESTONE BADGES" strip
    (pulling live from `BadgesManager`) above the full "FULL RECORD LOG",
    so it reads as one screen with two sections instead of two competing
    achievement systems.
  - The Badges panel in the More screen gained a "VIEW FULL ACHIEVEMENT
    LOG →" link (`more_screen.view_full_achievements` signal, wired in
    `main.gd`) that jumps straight to the Achievements screen.
  - This addresses audit issue #1 (duplicate achievement/badge systems)
    by unifying the *presentation* and *icon language*; the underlying
    data model (persisted badges vs. live-evaluated achievements) was left
    as two sources since merging that safely needs an editor to test save
    compatibility — flagged below.
- **Career ranks get real badge art** — Vector Ranks (CC0): Wood → Bronze
  → Silver → Gold across the 4 existing tiers (Rookie/Contender/
  Veteran/Elite), 5 numbered variants per material so all 20 ranks have a
  distinct badge (`CareerData.icon_for_rank()` / `large_icon_for_rank()`).
  Shows up on: each ladder row (as the Button's native `icon`), the status
  card next to the progress ring, and the RANK UP! certificate (large
  version, with the old star kept as an automatic fallback if art is ever
  missing).
- **App icon wired up** — `export_presets.cfg`'s Android adaptive launcher
  icon slots and the web PWA icon slots were empty (would have shipped
  with Godot's default robot icon); now point at the uploaded
  `app_icon_1024.png` / `adaptive_foreground_1024.png` /
  `adaptive_background_1024.png` (`assets/icons/app/`). Desktop/editor
  icon (`icon.svg`) was left alone since it's already a custom design, not
  a placeholder.

### What was left out, on purpose

- **"Sci-Fi Rank Battle & Cosmic Electronic BGM" pack** — its license is a
  YouTube/Instagram/TikTok *creator* license only and explicitly excludes
  apps/games. Using it in a shipped game would violate the license, so it
  was not copied in. If you want music in this style, it'd need to be
  repurchased under a game-usable license.
- **`TrophyCups.unitypackage`** — Unity-only format, can't be used in
  Godot.
- **`Furrey_AchievementSystem.js` / `GameJolt.js`** — JavaScript, not
  GDScript; also would have added a *third* parallel achievement system on
  top of the two just consolidated.
- **`Elapsed Time Counter Node`** — a BlitzMax `.bbnode`, not a Godot
  format.
- **`BlueStyle_gui.rar`** — couldn't extract it (no unrar tool / no
  network in this environment). Re-zip and re-upload if you want it
  evaluated.
- **Freebuttons / buttons-text-pack / parallax_demon_woods_pack / kenney
  board-game & game-icon packs** — not applied. The project already has a
  cohesive Kenney Sci-Fi UI button skin and a 4-theme space backdrop
  system from an earlier pass; layering a second, visually different
  button style or a fantasy-forest parallax background on top would fight
  that existing polish rather than add to it. Files are still sitting in
  the source zips if you want a specific one applied deliberately.
- **Aethermint idle-reward widgets** — license permits shipped commercial
  games, but the pack itself is themed around gacha/idle-game monetization
  (energy refill cards, gem/gold chips, "limited offer" panels) that
  doesn't fit a typing-practice game. Not applied; flag if you want select
  pieces (e.g. the toast/panel shapes) repurposed.
- As with everything above: **not run in the Godot editor** (none
  available here). Open the project and let it reimport the new
  fonts/PNGs, then check the Achievements, Career, and More screens.
