class_name GameState
extends Node

## Holds all gameplay numbers and fires signals when they change so UI /
## other systems never need to reach into each other directly.

signal score_changed(new_score: int)
signal lives_changed(new_lives: int)
signal combo_changed(new_combo: int)
signal level_changed(new_level: int)
signal time_changed(new_time: float)
signal stats_changed()
signal level_up(new_level: int)
signal game_started()
signal game_ended(did_win: bool)
signal shield_changed(active: bool)
signal accessibility_changed()
signal ui_style_changed(new_style: String) # fired when the Casual/Jelly interface style changes so live screens can re-skin without an app restart

const SAVE_PATH = "user://keys_learning_save.cfg"

# --- core stats ---
var score := 0
var lives := 3
var combo := 0
var words_typed_total := 0
var high_scores := [0, 0, 0]
var best_wpm := 0.0
var time_left := 60.0
var running := false
var is_paused := false

# Explicit helper variable to prevent external lookup thread lockup crashes
var is_game_over: bool:
	get: return not running

# --- progression ---
var current_xp := 0
var level := 1
var xp_to_next_level := 100
var frenzy_mode := false
var shield_active := false

# --- accuracy / wpm ---
var accuracy_hits := 0
var accuracy_misses := 0
var missed_words: Array = []
var run_start_msec := 0

# --- settings persisted across sessions ---
var tutorial_seen := false
var sfx_volume := 1.0
var music_volume := 1.0
var muted := false
var music_enabled := true
var sfx_enabled := true
var hd_graphics_enabled := true # disable for better performance on low-end devices
var notifications_enabled := true
var distance_unit := "meters" # "meters" / "feet" — used by anything that reports in-game distance
var selected_theme := "General"
var selected_difficulty := "Mixed"
var weak_keys_mode := false
var weak_letter_counts := {}
var reduced_motion := false

# --- missions / maps ---
var completed_mission_ids: Array = []
var max_combo_this_run := 0

# --- career mode ("The Climb") ---
var career_unlocked_rank := 1
var career_current_rank := 1
var career_highest_rank_reached := 1
var career_mode_active := false

# --- new: all-time best combo (separate from max_combo_this_run, which
# resets every run) ---
var best_combo := 0
var best_survival_streak := 0
var story_chapter_unlocked := 1
var story_chapters_cleared: Array = []
var story_chapters_cleared_hard: Array = []
## "Decode Threshold" - clearing a chapter with clean enough typing (see
## StoryData.meets_decode_threshold) reveals extra deeper-lore outro lines
## on top of the normal ones. This tracks which chapters have had that
## bonus fully unlocked, separately from story_chapters_cleared, so a messy
## clear still counts as "cleared" but the player can see there's more of
## the real story still to uncover by replaying more cleanly.
var story_chapters_decoded: Array = []
var story_difficulty := "normal"

# --- new: rolling history of finished runs, newest last, capped at 50.
# Powers the Leaderboard panel and the "personal best" comparison. ---
var run_history: Array = []

# --- new: daily play streak ---
var current_streak := 0
var longest_streak := 0
var last_play_date := ""

# --- new: streak freeze (Daily Challenge feature). Earned automatically
# every STREAK_FREEZE_EVERY_DAYS-day streak milestone; update_streak()
# spends one to absorb a single missed day instead of resetting the
# streak to 0. streak_freeze_last_milestone just prevents re-granting a
# token for a milestone that's already been paid out. ---
const STREAK_FREEZE_EVERY_DAYS := 7
var streak_freeze_tokens := 0
var streak_freeze_last_milestone := 0

# --- new: cross-run pool of words you've missed, for "Drill My Mistakes".
# Capped at 100, oldest dropped first, no duplicates. ---
var missed_words_persistent: Array = []

# --- new: unlocked collectible badge ids (see BadgesManager) ---
var unlocked_badges: Array = []

# --- new: accessibility / presentation settings ---
var selected_language := "en"
var font_scale := 1.15
var high_contrast := false
var colorblind_mode := "off" # off / deuteranopia / protanopia / tritanopia
var dyslexia_spacing := false # widens letter/word spacing project-wide, an accessibility approximation
var adaptive_difficulty := false # nudges spawn pacing based on rolling recent accuracy, see AdaptiveDifficulty
var unlocked_cosmetics: Array = ["default"] # accent-color unlocks bought with XP, see CosmeticShop panel
var selected_cosmetic := "default"
var sound_pack := "Classic"
var ui_style := "arcade" # "casual" (flat, no texture assets) / "jelly" (SunGraphica jelly kit) / "arcade" (buttons_red/orange/grey + windows pack, default)
var keyboard_layout := "QWERTY"

# --- new: player-supplied custom word list for Custom Word Practice ---
var custom_word_list: Array = []

# --- new: Daily Challenge ---
var daily_challenge_date := ""
var daily_challenge_best_score := 0

# --- new: Sentence Practice mission tracking (total sentences ever typed) ---
var sentence_practice_count := 0

# --- new: Versus / Ghost Race / AI Versus mode tracking ---
var ai_versus_wins_total := 0
var ai_versus_matches_played := 0
var ai_versus_champion_beaten := false
var ai_versus_record := {}   # {"Rookie AI": {"wins": int, "losses": int}, ...}
var versus_matches_played := 0
var online_versus_matches_played := 0
var online_versus_wins := 0
var online_versus_losses := 0
var online_versus_ties := 0
var ghost_race_wins_total := 0
var ghost_race_matches_played := 0
var imported_ghost_codes := []   # Array of {"label": String, "wpm": float}, most recent first, capped at 5

# --- new: Daily Login Rewards. Separate from Daily Challenge (#daily
# challenge only counts if you actually play a round; this only cares
# whether you opened the app today) and separate from current_streak/
# longest_streak (the general play streak, which also advances from
# practice modes/versus/etc). Cycles every 7 days; day 7 always grants a
# badge on top of the XP. ---
var login_reward_streak := 0
var login_reward_best_streak := 0
var login_reward_last_date := ""
var login_reward_total_claims := 0

# --- new: pinned Ghost Rival for Ghost Rival Rematch (distinct from the
# ad-hoc target picker in GhostRacer, which lets you race ANY past run —
# this is a single pinned "rival" you keep coming back to) ---
var ghost_rival_label := ""
var ghost_rival_wpm := 0.0
var ghost_rival_history := []   # Array of {"date","your_wpm","rival_wpm","won"}, newest last, capped at 20

# --- new: saved Practice Playlists (Session Builder) — each is
# {"name": String, "mode_ids": Array[String]} where mode_ids are the same
# ids PracticeSession/MoreScreen already use ("zen","drill","custom",
# "typing_test","daily","boss","survival"). Capped at 10 saved playlists. ---
var saved_playlists := []

# --- new: lifetime counters feeding MissionManager/BadgesManager for the
# combo-streak-bonus, playlist, and ghost-rival features above. ---
var streak_bonus_triggers_total := 0
var playlists_completed_total := 0
var ghost_rival_wins_total := 0

func _ready() -> void:
	load_save_data()

func reset_run() -> void:
	score = 0
	lives = 3
	combo = 0
	words_typed_total = 0
	time_left = 60.0
	level = 1
	current_xp = 0
	xp_to_next_level = 100
	frenzy_mode = false
	shield_active = false
	accuracy_hits = 0
	accuracy_misses = 0
	missed_words.clear()
	max_combo_this_run = 0
	run_start_msec = Time.get_ticks_msec()

func start_run() -> void:
	reset_run()
	running = true
	is_paused = false
	score_changed.emit(score)
	lives_changed.emit(lives)
	combo_changed.emit(combo)
	level_changed.emit(level)
	time_changed.emit(time_left)
	shield_changed.emit(shield_active)
	stats_changed.emit()
	game_started.emit()

func tick(delta: float) -> void:
	if not running or is_paused:
		return
	time_left -= delta
	time_changed.emit(time_left)
	if time_left <= 0:
		end_run(false)

# FIX: "word" was never read in this function (only register_miss actually
# uses it, to append to missed_words) — prefixed with an underscore so
# Godot knows it's intentionally unused instead of warning about it.
func register_hit(_word: String) -> Dictionary:
	accuracy_hits += 1
	words_typed_total += 1
	score += 10
	combo += 1
	max_combo_this_run = max(max_combo_this_run, combo)
	current_xp += 10 + (combo * 2)
	var did_level_up := false
	if current_xp >= xp_to_next_level:
		did_level_up = true
		_apply_level_up()
	score_changed.emit(score)
	combo_changed.emit(combo)
	stats_changed.emit()
	return {"leveled_up": did_level_up, "bonus_time": words_typed_total % 10 == 0}

func register_miss(word: String) -> bool:
	accuracy_misses += 1
	missed_words.append(word)
	_add_persistent_missed_word(word)
	if shield_active:
		shield_active = false
		shield_changed.emit(false)
		stats_changed.emit()
		return false
	lives -= 1
	combo = 0
	lives_changed.emit(lives)
	combo_changed.emit(combo)
	stats_changed.emit()
	if lives <= 0:
		end_run(false)
	return true

func add_bonus_life() -> void:
	lives += 1
	lives_changed.emit(lives)

func add_bonus_time(seconds: float) -> void:
	time_left += seconds
	time_changed.emit(time_left)

func _apply_level_up() -> void:
	level += 1
	current_xp = 0
	xp_to_next_level += 50
	time_left += 15.0
	if level == 5:
		add_bonus_life()
	if level % 10 == 0:
		shield_active = true
		shield_changed.emit(true)
	level_changed.emit(level)
	time_changed.emit(time_left)
	level_up.emit(level)

func get_wpm() -> float:
	if run_start_msec == 0:
		return 0.0
	var elapsed_minutes = max((Time.get_ticks_msec() - run_start_msec) / 60000.0, 1.0 / 60.0)
	return words_typed_total / elapsed_minutes

func get_accuracy() -> float:
	var total = accuracy_hits + accuracy_misses
	if total <= 0:
		return 100.0
	return (float(accuracy_hits) / total) * 100.0

func note_weak_letters(word: String) -> void:
	for c in word:
		weak_letter_counts[c] = weak_letter_counts.get(c, 0) + 1

func get_weak_letters(count: int = 5) -> Array:
	var letters = weak_letter_counts.keys()
	letters.sort_custom(func(a, b): return weak_letter_counts[a] > weak_letter_counts[b])
	return letters.slice(0, count)

func end_run(did_win: bool) -> void:
	if not running:
		return
	running = false
	var wpm = get_wpm()
	if wpm > best_wpm:
		best_wpm = wpm
	high_scores.append(score)
	high_scores.sort_custom(func(a, b): return a > b)
	high_scores = high_scores.slice(0, 3)
	if max_combo_this_run > best_combo:
		best_combo = max_combo_this_run
	record_run_history("Career" if career_mode_active else "Classic")
	save_data()
	game_ended.emit(did_win)

## --- Backup code: export/import ---
## Real cloud save needs a backend account (Firebase, a custom API, etc.)
## that isn't available in this environment — see CloudSaveManager for
## where that would plug in. This is a genuinely working stand-in that
## needs no network at all: it packages the actual save file (same one
## save_data()/load_save_data() read and write) into a copy-pasteable
## text code the player can save somewhere themselves and paste back in
## on a new device or after a reinstall. Not automatic, but it actually
## solves "I lost my progress" today, which nothing else here does yet.
func export_save_code() -> String:
	save_data() # make sure the on-disk file reflects current state first
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		ErrorLogger.log_error("export_save_code failed", "Could not open save file at %s" % SAVE_PATH)
		return ""
	var raw := f.get_as_text()
	f.close()
	return Marshalls.utf8_to_base64(raw)

## Returns true on success. Overwrites the current save file and reloads
## every field from it, so call this only after the player has explicitly
## confirmed they want to replace their current progress.
func import_save_code(code: String) -> bool:
	var raw := Marshalls.base64_to_utf8(code.strip_edges())
	if raw == "" or raw == null:
		return false
	var cfg := ConfigFile.new()
	var err := cfg.parse(raw)
	if err != OK:
		ErrorLogger.log_warning("import_save_code: invalid code", "ConfigFile.parse() returned error code %d" % err)
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		ErrorLogger.log_error("import_save_code failed", "Could not write save file at %s" % SAVE_PATH)
		return false
	f.store_string(raw)
	f.close()
	load_save_data()
	return true

func save_data() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("scores", "high_scores", high_scores)
	cfg.set_value("scores", "best_wpm", best_wpm)
	cfg.set_value("settings", "tutorial_seen", tutorial_seen)
	cfg.set_value("settings", "sfx_volume", sfx_volume)
	cfg.set_value("settings", "music_volume", music_volume)
	cfg.set_value("settings", "muted", muted)
	cfg.set_value("settings", "music_enabled", music_enabled)
	cfg.set_value("settings", "sfx_enabled", sfx_enabled)
	cfg.set_value("settings", "hd_graphics_enabled", hd_graphics_enabled)
	cfg.set_value("settings", "notifications_enabled", notifications_enabled)
	cfg.set_value("settings", "distance_unit", distance_unit)
	cfg.set_value("settings", "selected_theme", selected_theme)
	cfg.set_value("settings", "selected_difficulty", selected_difficulty)
	cfg.set_value("settings", "weak_keys_mode", weak_keys_mode)
	cfg.set_value("settings", "reduced_motion", reduced_motion)
	cfg.set_value("missions", "completed_ids", completed_mission_ids)
	cfg.set_value("career", "unlocked_rank", career_unlocked_rank)
	cfg.set_value("career", "current_rank", career_current_rank)
	cfg.set_value("career", "highest_rank_reached", career_highest_rank_reached)
	cfg.set_value("extra", "best_combo", best_combo)
	cfg.set_value("extra", "best_survival_streak", best_survival_streak)
	cfg.set_value("extra", "story_chapter_unlocked", story_chapter_unlocked)
	cfg.set_value("extra", "story_chapters_cleared", story_chapters_cleared)
	cfg.set_value("extra", "story_chapters_cleared_hard", story_chapters_cleared_hard)
	cfg.set_value("extra", "story_chapters_decoded", story_chapters_decoded)
	cfg.set_value("extra", "story_difficulty", story_difficulty)
	cfg.set_value("extra", "run_history", run_history)
	cfg.set_value("extra", "current_streak", current_streak)
	cfg.set_value("extra", "longest_streak", longest_streak)
	cfg.set_value("extra", "last_play_date", last_play_date)
	cfg.set_value("extra", "streak_freeze_tokens", streak_freeze_tokens)
	cfg.set_value("extra", "streak_freeze_last_milestone", streak_freeze_last_milestone)
	cfg.set_value("extra", "missed_words_persistent", missed_words_persistent)
	cfg.set_value("extra", "unlocked_badges", unlocked_badges)
	cfg.set_value("extra", "selected_language", selected_language)
	cfg.set_value("extra", "font_scale", font_scale)
	cfg.set_value("extra", "high_contrast", high_contrast)
	cfg.set_value("extra", "colorblind_mode", colorblind_mode)
	cfg.set_value("extra", "dyslexia_spacing", dyslexia_spacing)
	cfg.set_value("extra", "adaptive_difficulty", adaptive_difficulty)
	cfg.set_value("extra", "unlocked_cosmetics", unlocked_cosmetics)
	cfg.set_value("extra", "selected_cosmetic", selected_cosmetic)
	cfg.set_value("extra", "sound_pack", sound_pack)
	cfg.set_value("extra", "ui_style", ui_style)
	cfg.set_value("extra", "keyboard_layout", keyboard_layout)
	cfg.set_value("extra", "custom_word_list", custom_word_list)
	cfg.set_value("extra", "daily_challenge_date", daily_challenge_date)
	cfg.set_value("extra", "daily_challenge_best_score", daily_challenge_best_score)
	cfg.set_value("extra", "sentence_practice_count", sentence_practice_count)
	cfg.set_value("extra", "ai_versus_wins_total", ai_versus_wins_total)
	cfg.set_value("extra", "ai_versus_matches_played", ai_versus_matches_played)
	cfg.set_value("extra", "ai_versus_champion_beaten", ai_versus_champion_beaten)
	cfg.set_value("extra", "ai_versus_record", ai_versus_record)
	cfg.set_value("extra", "versus_matches_played", versus_matches_played)
	cfg.set_value("extra", "online_versus_matches_played", online_versus_matches_played)
	cfg.set_value("extra", "online_versus_wins", online_versus_wins)
	cfg.set_value("extra", "online_versus_losses", online_versus_losses)
	cfg.set_value("extra", "online_versus_ties", online_versus_ties)
	cfg.set_value("extra", "ghost_race_wins_total", ghost_race_wins_total)
	cfg.set_value("extra", "ghost_race_matches_played", ghost_race_matches_played)
	cfg.set_value("extra", "imported_ghost_codes", imported_ghost_codes)
	cfg.set_value("extra", "login_reward_streak", login_reward_streak)
	cfg.set_value("extra", "login_reward_best_streak", login_reward_best_streak)
	cfg.set_value("extra", "login_reward_last_date", login_reward_last_date)
	cfg.set_value("extra", "login_reward_total_claims", login_reward_total_claims)
	cfg.set_value("extra", "ghost_rival_label", ghost_rival_label)
	cfg.set_value("extra", "ghost_rival_wpm", ghost_rival_wpm)
	cfg.set_value("extra", "ghost_rival_history", ghost_rival_history)
	cfg.set_value("extra", "saved_playlists", saved_playlists)
	cfg.set_value("extra", "streak_bonus_triggers_total", streak_bonus_triggers_total)
	cfg.set_value("extra", "playlists_completed_total", playlists_completed_total)
	cfg.set_value("extra", "ghost_rival_wins_total", ghost_rival_wins_total)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		ErrorLogger.log_error("Save failed", "ConfigFile.save() returned error code %d for path %s" % [err, SAVE_PATH])

func load_save_data() -> void:
	var cfg = ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			# FILE_NOT_FOUND is expected on first launch ever; anything
			# else (corrupt file, permission issue) means real progress
			# may be unreadable, which is worth knowing about.
			ErrorLogger.log_error("Save file failed to load", "ConfigFile.load() returned error code %d for path %s" % [err, SAVE_PATH])
		return
	high_scores = cfg.get_value("scores", "high_scores", [0, 0, 0])
	best_wpm = cfg.get_value("scores", "best_wpm", 0.0)
	tutorial_seen = cfg.get_value("settings", "tutorial_seen", false)
	sfx_volume = cfg.get_value("settings", "sfx_volume", 1.0)
	music_volume = cfg.get_value("settings", "music_volume", 1.0)
	muted = cfg.get_value("settings", "muted", false)
	music_enabled = cfg.get_value("settings", "music_enabled", true)
	sfx_enabled = cfg.get_value("settings", "sfx_enabled", true)
	hd_graphics_enabled = cfg.get_value("settings", "hd_graphics_enabled", true)
	notifications_enabled = cfg.get_value("settings", "notifications_enabled", true)
	distance_unit = cfg.get_value("settings", "distance_unit", "meters")
	selected_theme = cfg.get_value("settings", "selected_theme", "General")
	selected_difficulty = cfg.get_value("settings", "selected_difficulty", "Mixed")
	weak_keys_mode = cfg.get_value("settings", "weak_keys_mode", false)
	reduced_motion = cfg.get_value("settings", "reduced_motion", false)
	completed_mission_ids = cfg.get_value("missions", "completed_ids", [])
	career_unlocked_rank = cfg.get_value("career", "unlocked_rank", 1)
	career_current_rank = cfg.get_value("career", "current_rank", 1)
	career_highest_rank_reached = cfg.get_value("career", "highest_rank_reached", 1)
	best_combo = cfg.get_value("extra", "best_combo", 0)
	best_survival_streak = cfg.get_value("extra", "best_survival_streak", 0)
	story_chapter_unlocked = cfg.get_value("extra", "story_chapter_unlocked", 1)
	story_chapters_cleared = cfg.get_value("extra", "story_chapters_cleared", [])
	story_chapters_cleared_hard = cfg.get_value("extra", "story_chapters_cleared_hard", [])
	story_chapters_decoded = cfg.get_value("extra", "story_chapters_decoded", [])
	story_difficulty = cfg.get_value("extra", "story_difficulty", "normal")
	run_history = cfg.get_value("extra", "run_history", [])
	current_streak = cfg.get_value("extra", "current_streak", 0)
	longest_streak = cfg.get_value("extra", "longest_streak", 0)
	last_play_date = cfg.get_value("extra", "last_play_date", "")
	streak_freeze_tokens = cfg.get_value("extra", "streak_freeze_tokens", 0)
	streak_freeze_last_milestone = cfg.get_value("extra", "streak_freeze_last_milestone", 0)
	missed_words_persistent = cfg.get_value("extra", "missed_words_persistent", [])
	unlocked_badges = cfg.get_value("extra", "unlocked_badges", [])
	selected_language = cfg.get_value("extra", "selected_language", "en")
	font_scale = cfg.get_value("extra", "font_scale", 1.15)
	high_contrast = cfg.get_value("extra", "high_contrast", false)
	colorblind_mode = cfg.get_value("extra", "colorblind_mode", "off")
	dyslexia_spacing = cfg.get_value("extra", "dyslexia_spacing", false)
	adaptive_difficulty = cfg.get_value("extra", "adaptive_difficulty", false)
	unlocked_cosmetics = cfg.get_value("extra", "unlocked_cosmetics", ["default"])
	selected_cosmetic = cfg.get_value("extra", "selected_cosmetic", "default")
	sound_pack = cfg.get_value("extra", "sound_pack", "Classic")
	ui_style = cfg.get_value("extra", "ui_style", "arcade")
	JellyTheme.set_style(ui_style)
	keyboard_layout = cfg.get_value("extra", "keyboard_layout", "QWERTY")
	custom_word_list = cfg.get_value("extra", "custom_word_list", [])
	daily_challenge_date = cfg.get_value("extra", "daily_challenge_date", "")
	daily_challenge_best_score = cfg.get_value("extra", "daily_challenge_best_score", 0)
	sentence_practice_count = cfg.get_value("extra", "sentence_practice_count", 0)
	ai_versus_wins_total = cfg.get_value("extra", "ai_versus_wins_total", 0)
	ai_versus_matches_played = cfg.get_value("extra", "ai_versus_matches_played", 0)
	ai_versus_champion_beaten = cfg.get_value("extra", "ai_versus_champion_beaten", false)
	ai_versus_record = cfg.get_value("extra", "ai_versus_record", {})
	versus_matches_played = cfg.get_value("extra", "versus_matches_played", 0)
	online_versus_matches_played = cfg.get_value("extra", "online_versus_matches_played", 0)
	online_versus_wins = cfg.get_value("extra", "online_versus_wins", 0)
	online_versus_losses = cfg.get_value("extra", "online_versus_losses", 0)
	online_versus_ties = cfg.get_value("extra", "online_versus_ties", 0)
	ghost_race_wins_total = cfg.get_value("extra", "ghost_race_wins_total", 0)
	ghost_race_matches_played = cfg.get_value("extra", "ghost_race_matches_played", 0)
	imported_ghost_codes = cfg.get_value("extra", "imported_ghost_codes", [])
	login_reward_streak = cfg.get_value("extra", "login_reward_streak", 0)
	login_reward_best_streak = cfg.get_value("extra", "login_reward_best_streak", 0)
	login_reward_last_date = cfg.get_value("extra", "login_reward_last_date", "")
	login_reward_total_claims = cfg.get_value("extra", "login_reward_total_claims", 0)
	ghost_rival_label = cfg.get_value("extra", "ghost_rival_label", "")
	ghost_rival_wpm = cfg.get_value("extra", "ghost_rival_wpm", 0.0)
	ghost_rival_history = cfg.get_value("extra", "ghost_rival_history", [])
	saved_playlists = cfg.get_value("extra", "saved_playlists", [])
	streak_bonus_triggers_total = cfg.get_value("extra", "streak_bonus_triggers_total", 0)
	playlists_completed_total = cfg.get_value("extra", "playlists_completed_total", 0)
	ghost_rival_wins_total = cfg.get_value("extra", "ghost_rival_wins_total", 0)

func mark_tutorial_seen() -> void:
	tutorial_seen = true
	save_data()

## "Reset Progress" — wipes high scores, best WPM, weak-letter tracking and
## mission completion back to a fresh start. Deliberately leaves player
## preferences (volume, theme, difficulty, reduced motion, tutorial-seen)
## untouched, and doesn't touch `running`/`is_paused` — if this is called
## mid-run the current round keeps going, it just won't count toward any
## already-completed mission the reset just cleared.
func reset_all_progress() -> void:
	high_scores = [0, 0, 0]
	best_wpm = 0.0
	weak_letter_counts = {}
	completed_mission_ids = []
	career_unlocked_rank = 1
	career_current_rank = 1
	career_highest_rank_reached = 1
	career_mode_active = false
	best_combo = 0
	run_history = []
	current_streak = 0
	longest_streak = 0
	last_play_date = ""
	streak_freeze_tokens = 0
	streak_freeze_last_milestone = 0
	missed_words_persistent = []
	unlocked_badges = []
	daily_challenge_date = ""
	daily_challenge_best_score = 0
	sentence_practice_count = 0
	login_reward_streak = 0
	login_reward_best_streak = 0
	login_reward_last_date = ""
	login_reward_total_claims = 0
	ghost_rival_label = ""
	ghost_rival_wpm = 0.0
	ghost_rival_history = []
	save_data()

## --- New feature support methods (see MoreScreen / CHANGES.md) ---

func _add_persistent_missed_word(word: String) -> void:
	if word == "":
		return
	missed_words_persistent.erase(word)
	missed_words_persistent.append(word)
	if missed_words_persistent.size() > 100:
		missed_words_persistent = missed_words_persistent.slice(missed_words_persistent.size() - 100, missed_words_persistent.size())

## Appends a summary of the just-finished run to run_history (capped at 50).
## Called from end_run(). Practice modes (Zen/Drill/Custom/Typing
## Test/Daily Challenge/Boss Battle) call this too with their own mode name,
## since they don't go through the falling-word end_run() path.
func record_run_history(mode: String) -> void:
	update_streak()
	run_history.append({
		"date": Time.get_date_string_from_system(),
		"mode": mode,
		"score": score,
		"wpm": get_wpm(),
		"accuracy": get_accuracy(),
	})
	if run_history.size() > 50:
		run_history = run_history.slice(run_history.size() - 50, run_history.size())

## True when the player has an active streak but hasn't played yet today
## — i.e. it'll lapse if they don't start a run before the day rolls over.
## Only meaningful if checked BEFORE update_streak() runs this session
## (update_streak() immediately marks today as played), so call this at
## app open / menu display, not after a run has already started.
## A real push notification reminding players of this (see
## NotificationManager) needs an OS-level plugin this environment can't
## install; this is what's checkable without one — an in-app nudge shown
## while they're already looking at the screen.
func is_streak_at_risk() -> bool:
	return current_streak > 0 and last_play_date != Time.get_date_string_from_system()

## Call once per session (menu open or practice session start). Only the
## first call in a given calendar day has any effect.
func update_streak() -> void:
	var today := Time.get_date_string_from_system()
	if last_play_date == today:
		return
	var yesterday := Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 86400).substr(0, 10)
	if last_play_date == yesterday:
		current_streak += 1
	elif last_play_date != "" and streak_freeze_tokens > 0:
		# Streak freeze: absorbs exactly ONE missed day (spends one
		# token) instead of resetting to 0. Only covers a single-day
		# gap - a 2+ day lapse still breaks the streak even with a
		# token available, so it can't be stretched to skip a whole
		# week indefinitely.
		streak_freeze_tokens -= 1
		current_streak += 1
	else:
		current_streak = 1
	last_play_date = today
	if current_streak > longest_streak:
		longest_streak = current_streak
	_maybe_award_streak_freeze()
	save_data()

## Grants one streak-freeze token per fresh STREAK_FREEZE_EVERY_DAYS-day
## milestone reached (7, 14, 21, ...). streak_freeze_last_milestone stops
## a milestone that's already been paid out from granting a second token
## if update_streak() somehow runs again at the same streak length.
func _maybe_award_streak_freeze() -> void:
	var milestone := current_streak / STREAK_FREEZE_EVERY_DAYS
	if milestone > streak_freeze_last_milestone:
		streak_freeze_tokens += (milestone - streak_freeze_last_milestone)
		streak_freeze_last_milestone = milestone

## Called by SentenceModeScreen each time a sentence is completed. Tracks
## the lifetime count (for missions) and lets sentence practice contribute
## to best_wpm the same way normal runs do.
func register_sentence_practice(wpm: float) -> void:
	sentence_practice_count += 1
	if wpm > best_wpm:
		best_wpm = wpm
	update_streak()
	save_data()

## Called once per finished AI Versus match. Tracks lifetime matches/wins
## for career missions and badges - doesn't touch score/lives/best_wpm,
## same no-corruption guarantee as register_practice_result(). difficulty_label
## is optional and only used to flag the "beat Champion AI" badge.
func register_ai_versus_result(player_won: bool, difficulty_label: String = "") -> void:
	ai_versus_matches_played += 1
	if player_won:
		ai_versus_wins_total += 1
		if difficulty_label == "Champion AI":
			ai_versus_champion_beaten = true
	if difficulty_label != "":
		var record: Dictionary = ai_versus_record.get(difficulty_label, {"wins": 0, "losses": 0})
		if player_won:
			record["wins"] = record.get("wins", 0) + 1
		else:
			record["losses"] = record.get("losses", 0) + 1
		ai_versus_record[difficulty_label] = record
	update_streak()
	save_data()

## next time Ghost Race opens. Capped at 5, most recent first - doesn't
## touch any other GameState field.
func add_imported_ghost_code(label: String, wpm: float) -> void:
	imported_ghost_codes.push_front({"label": label, "wpm": wpm})
	if imported_ghost_codes.size() > 5:
		imported_ghost_codes = imported_ghost_codes.slice(0, 5)
	save_data()

## Just tracks that a match happened, for the "played versus" badge -
## there's no single "you" to attach a win/loss to in pass-and-play.
func register_versus_match() -> void:
	versus_matches_played += 1
	update_streak()
	save_data()

## Called once per finished Online Versus match. Unlike register_versus_match()
## (pass-and-play, no single "you"), an online match has two separate
## devices each with their own player, so wins/losses/ties are meaningful
## and worth tracking here - same no-corruption guarantee as
## register_practice_result(): doesn't touch score/lives/best_wpm.
func register_online_versus_result(player_won: bool, tie: bool = false) -> void:
	online_versus_matches_played += 1
	if tie:
		online_versus_ties += 1
	elif player_won:
		online_versus_wins += 1
	else:
		online_versus_losses += 1
	update_streak()
	save_data()

## Called once per finished Ghost Race. Tracks lifetime races/wins for
## badges, same no-corruption guarantee as the other register_* helpers.
func register_ghost_race_result(beat_ghost: bool) -> void:
	ghost_race_matches_played += 1
	if beat_ghost:
		ghost_race_wins_total += 1
	update_streak()
	save_data()

## Generic entry point for the new self-contained practice modes (Zen,
## Drill My Mistakes, Custom Words, Typing Test, Daily Challenge, Boss
## Battle). These never touch lives/score/high_scores/career state - they
## just log a run_history row and, where relevant, raise best_wpm - so they
## can't corrupt normal-run stats or mission tracking.
func register_practice_result(mode: String, wpm: float, accuracy: float, words_typed: int) -> void:
	if wpm > best_wpm:
		best_wpm = wpm
	if words_typed > 0:
		update_streak()
	run_history.append({
		"date": Time.get_date_string_from_system(),
		"mode": mode,
		"score": words_typed,
		"wpm": wpm,
		"accuracy": accuracy,
	})
	if run_history.size() > 50:
		run_history = run_history.slice(run_history.size() - 50, run_history.size())
	save_data()

## --- Daily Login Rewards ---
## Call once per app launch (after tutorial). Returns a Dictionary describing
## the reward if today's hasn't been claimed yet, or {} if it already has
## (so callers can skip showing a popup twice in one session). Purely a
## "you opened the app today" reward — doesn't require playing a round,
## which is what makes it distinct from Daily Challenge and from the
## general current_streak/longest_streak play-streak counters.
func claim_daily_login_reward() -> Dictionary:
	var today := Time.get_date_string_from_system()
	if login_reward_last_date == today:
		return {}
	var yesterday := Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 86400).substr(0, 10)
	if login_reward_last_date == yesterday:
		login_reward_streak += 1
	else:
		login_reward_streak = 1
	login_reward_last_date = today
	login_reward_total_claims += 1
	if login_reward_streak > login_reward_best_streak:
		login_reward_best_streak = login_reward_streak

	var day_in_cycle := ((login_reward_streak - 1) % 7) + 1
	var xp_reward := 20 * day_in_cycle
	var badge_day := day_in_cycle == 7

	current_xp += xp_reward
	var did_level_up := false
	if current_xp >= xp_to_next_level:
		did_level_up = true
		_apply_level_up()
	stats_changed.emit()
	save_data()

	return {
		"streak": login_reward_streak,
		"day_in_cycle": day_in_cycle,
		"xp": xp_reward,
		"leveled_up": did_level_up,
		"badge_day": badge_day,
	}

## --- Ghost Rival (pinned) ---
## Pins a single ghost target so Ghost Rival Rematch always has a fixed
## opponent to jump straight back into, instead of re-picking from the
## target list every time. Overwrites any previously pinned rival.
func pin_ghost_rival(label: String, wpm: float) -> void:
	ghost_rival_label = label
	ghost_rival_wpm = wpm
	save_data()

func has_pinned_ghost_rival() -> bool:
	return ghost_rival_label != "" and ghost_rival_wpm > 0.0

## Logs one rematch against the pinned rival. Capped at 20, oldest dropped
## first. Doesn't touch run_history/best_wpm/etc — the caller is expected
## to also call register_practice_result()/register_ghost_race_result()
## the same way the ad-hoc Ghost Race target picker already does.
func record_ghost_rival_rematch(your_wpm: float, won: bool) -> void:
	ghost_rival_history.append({
		"date": Time.get_date_string_from_system(),
		"your_wpm": your_wpm,
		"rival_wpm": ghost_rival_wpm,
		"won": won,
	})
	if ghost_rival_history.size() > 20:
		ghost_rival_history = ghost_rival_history.slice(ghost_rival_history.size() - 20, ghost_rival_history.size())
	if won:
		ghost_rival_wins_total += 1
	save_data()

## --- Practice Playlists (Session Builder) ---
## Saves a named sequence of practice-mode ids (see MoreScreen's
## _build_mode_config() for valid ids) so it can be replayed as one chained
## session later. Overwrites an existing playlist with the same name;
## otherwise appends, capped at 10 (oldest dropped first).
func save_playlist(playlist_name: String, mode_ids: Array) -> void:
	var clean_name := playlist_name.strip_edges()
	if clean_name == "" or mode_ids.is_empty():
		return
	for i in saved_playlists.size():
		if String(saved_playlists[i].get("name", "")) == clean_name:
			saved_playlists[i] = {"name": clean_name, "mode_ids": mode_ids.duplicate()}
			save_data()
			return
	saved_playlists.append({"name": clean_name, "mode_ids": mode_ids.duplicate()})
	if saved_playlists.size() > 10:
		saved_playlists = saved_playlists.slice(saved_playlists.size() - 10, saved_playlists.size())
	save_data()

func delete_playlist(playlist_name: String) -> void:
	for i in saved_playlists.size():
		if String(saved_playlists[i].get("name", "")) == playlist_name:
			saved_playlists.remove_at(i)
			save_data()
			return

## Called from main.gd each time a 10/25/50-combo streak bonus fires.
## Doesn't save immediately (this can happen several times per run) — it
## rides along with whatever save already happens at end_run()/pause/etc,
## same as max_combo_this_run.
func register_streak_bonus() -> void:
	streak_bonus_triggers_total += 1

## Called once per keystroke from TypingController.key_typed, on top of the
## existing note_weak_letters(word) (whole-word misses). That only catches
## words the player never finished; this catches wrong keystrokes typed
## along the way inside words they eventually got right, feeding the same
## weak_letter_counts dict already used by get_weak_letters(),
## KeyboardLayoutManager.hand_report(), and WordManager's weak-key word
## filtering — so a mid-word typo counts toward "weak" the same way a
## fully-missed word does, instead of being invisible until the whole word
## is missed. letter is a single uppercase character; anything else (e.g.
## the "" edge case for a non-letter) is ignored. Doesn't save immediately
## — rides along with whatever save already happens at end_run()/pause/etc,
## same as note_weak_letters().
func record_letter_accuracy(letter: String, is_valid: bool) -> void:
	if is_valid or letter.length() != 1:
		return
	weak_letter_counts[letter] = weak_letter_counts.get(letter, 0) + 1

## Called from MoreScreen once a chained Practice Playlist finishes every
## step in its queue.
func register_playlist_completed() -> void:
	playlists_completed_total += 1
	save_data()
