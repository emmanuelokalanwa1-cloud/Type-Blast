extends Node

## Lightweight regression harness — no external test addon required.
## Run it: open tests/TestRunner.tscn and hit F6 (Run Current Scene).
## Results print to the Output panel. Green summary line = all good.
##
## This is NOT a substitute for a real test framework (GUT). It exists to
## catch the specific regression risk in this codebase: GameState is one
## big shared blob that CareerManager, MissionManager, and AchievementsManager
## all read/write, so a change to one save key silently breaking another
## system is the most likely failure mode. These tests target exactly that.

var _pass_count := 0
var _fail_count := 0

func _ready() -> void:
	print("\n=== Type Blast test run — %s ===\n" % Time.get_datetime_string_from_system())

	_test_game_state_save_load_roundtrip()
	_test_achievements_evaluate()
	_test_career_rank_progression()
	_test_word_bank_blocklist()
	_test_mission_manager_evaluate_run_end()
	_test_powerup_system()
	_test_ghost_code_roundtrip()
	_test_save_migration_from_old_save()
	_test_stats_screen_survives_repeated_theme_refresh()
	_test_pause_menu_survives_repeated_theme_refresh()
	_test_difficulty_menu_survives_repeated_theme_refresh()
	_test_online_versus_result_tracking()

	print("\n=== Results: %d passed, %d failed ===\n" % [_pass_count, _fail_count])
	if _fail_count > 0:
		push_error("Test run had %d failure(s) — see log above." % _fail_count)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass_count += 1
		print("  PASS  " + label)
	else:
		_fail_count += 1
		print("  FAIL  " + label + (("  (" + detail + ")") if detail != "" else ""))


# ---------------------------------------------------------------------
# GameState save/load roundtrip
# ---------------------------------------------------------------------
func _test_game_state_save_load_roundtrip() -> void:
	print("-- GameState save/load roundtrip --")

	var gs := GameState.new()
	add_child(gs)

	gs.high_scores = [111, 222, 333]
	gs.best_wpm = 42.5
	gs.current_streak = 7
	gs.longest_streak = 9
	gs.career_unlocked_rank = 5
	gs.career_current_rank = 3
	gs.unlocked_badges = ["first_win", "combo_10"]
	gs.selected_language = "es"

	# game_state.gd hardcodes SAVE_PATH as a const, so we can't redirect
	# it from outside. Instead we snapshot values, save+reload against
	# the real path, then restore whatever was there before the test
	# (see cleanup at the end of this function).
	var had_existing_save := FileAccess.file_exists(gs.SAVE_PATH)
	var backup_path := gs.SAVE_PATH + ".bak"
	if had_existing_save:
		DirAccess.copy_absolute(gs.SAVE_PATH, backup_path)

	gs.save_data()

	var gs2 := GameState.new()
	add_child(gs2)
	gs2.load_save_data()

	_check("high_scores round-trips", gs2.high_scores == [111, 222, 333], str(gs2.high_scores))
	_check("best_wpm round-trips", is_equal_approx(gs2.best_wpm, 42.5), str(gs2.best_wpm))
	_check("current_streak round-trips", gs2.current_streak == 7, str(gs2.current_streak))
	_check("career_unlocked_rank round-trips", gs2.career_unlocked_rank == 5, str(gs2.career_unlocked_rank))
	_check("unlocked_badges round-trips", gs2.unlocked_badges == ["first_win", "combo_10"], str(gs2.unlocked_badges))
	_check("selected_language round-trips", gs2.selected_language == "es", str(gs2.selected_language))

	# Restore whatever save existed before this test ran.
	if had_existing_save:
		DirAccess.copy_absolute(backup_path, gs.SAVE_PATH)
		DirAccess.remove_absolute(backup_path)
	else:
		DirAccess.remove_absolute(gs.SAVE_PATH)

	gs.queue_free()
	gs2.queue_free()


# ---------------------------------------------------------------------
# AchievementsManager.evaluate() unlock logic
# ---------------------------------------------------------------------
func _test_achievements_evaluate() -> void:
	print("-- AchievementsManager.evaluate() --")

	var all_defs: Array = AchievementsManager.all()
	_check("achievement definitions loaded", all_defs.size() > 0, "count=%d" % all_defs.size())

	if all_defs.is_empty():
		return

	# Build a stats dict that should satisfy every "count"-style
	# threshold in the achievements file, then check nothing crashes
	# and every returned entry actually exists in the definitions.
	var expected_keys: Array = AchievementsManager.stats_keys_expected()
	var huge_stats := {}
	for k in expected_keys:
		huge_stats[k] = 999999

	var unlocked: Array = AchievementsManager.evaluate(huge_stats)
	_check("evaluate() returns an array", unlocked is Array)
	_check("evaluate() with maxed stats unlocks at least one achievement", unlocked.size() > 0, "count=%d" % unlocked.size())

	var all_ids := {}
	for a in all_defs:
		all_ids[a.get("id", "")] = true
	var all_valid := true
	for id in unlocked:
		if not all_ids.has(id):
			all_valid = false
			break
	_check("every unlocked id matches a real achievement definition", all_valid)

	# Zeroed stats should unlock nothing (assuming no achievement has a
	# threshold of 0 — if this fails, check for a bad threshold value).
	var zero_stats := {}
	for k in expected_keys:
		zero_stats[k] = 0
	var unlocked_zero: Array = AchievementsManager.evaluate(zero_stats)
	_check("evaluate() with zeroed stats unlocks nothing", unlocked_zero.is_empty(), "count=%d" % unlocked_zero.size())


# ---------------------------------------------------------------------
# CareerManager rank progression
# ---------------------------------------------------------------------
func _test_career_rank_progression() -> void:
	print("-- CareerManager rank progression --")

	var gs := GameState.new()
	add_child(gs)
	gs.career_unlocked_rank = 1
	gs.career_current_rank = 1

	var mm := MissionManager.new()
	add_child(mm)
	mm.setup(gs)

	var cm := CareerManager.new()
	add_child(cm)
	cm.setup(gs, mm)

	_check("rank 1 starts unlocked", cm.is_rank_unlocked(1))
	_check("rank 2 starts locked", not cm.is_rank_unlocked(2))
	_check("select_rank fails for a locked rank", not cm.select_rank(2))
	_check("select_rank succeeds for the unlocked rank", cm.select_rank(1))
	_check("is_climb_complete false at rank 1", not cm.is_climb_complete())

	gs.queue_free()
	mm.queue_free()
	cm.queue_free()


# ---------------------------------------------------------------------
# WordBank blocklist regression check
# ---------------------------------------------------------------------
## Guards against the word pools ever silently regaining profanity/slurs —
## e.g. if general.txt or general_extended.txt get regenerated from a raw
## dictionary source again without running back through the blocklist.
func _test_word_bank_blocklist() -> void:
	print("-- WordBank blocklist --")

	var blockset := {}
	for w in WordBank.BLOCKLIST:
		blockset[w] = true

	var any_leaked := false
	var leaked_examples: Array = []
	for theme_name in WordBank.theme_names():
		var pool: Array = WordBank.get_theme_pool(theme_name)
		for w in pool:
			if blockset.has(w):
				any_leaked = true
				leaked_examples.append("%s: %s" % [theme_name, w])

	_check("no blocklisted word appears in any theme pool", not any_leaked, str(leaked_examples.slice(0, 10)))

	var extended_pool: Array = WordBank.get_extended_general_pool()
	var extended_leaked: Array = []
	for w in extended_pool:
		if blockset.has(w):
			extended_leaked.append(w)
	_check("no blocklisted word in the opt-in extended pool", extended_leaked.is_empty(), str(extended_leaked.slice(0, 10)))

	_check("BLOCKLIST is actually populated", WordBank.BLOCKLIST.size() > 0, "size=%d" % WordBank.BLOCKLIST.size())


# ---------------------------------------------------------------------
# MissionManager.evaluate_run_end() — priority #1 from README's "not
# covered" list. Tests the actual mission-completion logic, not just the
# CareerManager layer sitting on top of it.
# ---------------------------------------------------------------------
func _test_mission_manager_evaluate_run_end() -> void:
	print("-- MissionManager.evaluate_run_end() --")

	var gs := GameState.new()
	add_child(gs)
	var mm := MissionManager.new()
	add_child(mm)
	mm.setup(gs)

	var total_missions := mm.get_total_mission_count()
	_check("mission data actually loaded", total_missions > 0, "count=%d" % total_missions)
	if total_missions == 0:
		gs.queue_free()
		mm.queue_free()
		return

	# Maxed-out run stats should satisfy every numeric mission type in one
	# pass (mirrors the achievements test's "huge stats" approach).
	gs.words_typed_total = 999999
	gs.max_combo_this_run = 999999
	gs.score = 999999
	gs.level = 999999
	gs.accuracy_hits = 999999
	gs.accuracy_misses = 0
	gs.run_start_msec = Time.get_ticks_msec() - 60000
	gs.weak_keys_mode = true

	var completed: Array = mm.evaluate_run_end(true)
	_check("evaluate_run_end() returns newly-completed missions for a maxed run", completed.size() > 0, "count=%d" % completed.size())

	var all_valid := true
	for entry in completed:
		var id = entry.get("id", "")
		if id == "" or not mm.is_completed(id):
			all_valid = false
			break
	_check("every returned entry is recorded as completed", all_valid)

	# Calling it again immediately must not re-return the same missions —
	# is_completed() should have filtered them out this time.
	var completed_again: Array = mm.evaluate_run_end(true)
	var no_dupes := true
	for entry in completed_again:
		if entry.get("id", "") in completed.map(func(e): return e.get("id", "")):
			no_dupes = false
			break
	_check("already-completed missions aren't returned a second time", no_dupes, "count=%d" % completed_again.size())

	# A fresh manager with zeroed stats and a loss should complete nothing
	# (assuming no mission has a target of 0 — if this fails, check for a
	# bad threshold in mission_data.gd).
	var gs2 := GameState.new()
	add_child(gs2)
	var mm2 := MissionManager.new()
	add_child(mm2)
	mm2.setup(gs2)
	var completed_zero: Array = mm2.evaluate_run_end(false)
	_check("zeroed stats + a loss completes nothing", completed_zero.is_empty(), "count=%d" % completed_zero.size())

	gs.queue_free()
	mm.queue_free()
	gs2.queue_free()
	mm2.queue_free()


# ---------------------------------------------------------------------
# PowerupSystem — priority #2 from README's "not covered" list. 20+
# powerup types with stacking/timing; this covers activation, expiry,
# cooldowns, the score multiplier, and reset().
# ---------------------------------------------------------------------
func _test_powerup_system() -> void:
	print("-- PowerupSystem --")

	var gs := GameState.new()
	add_child(gs)
	var ps := PowerupSystem.new()
	add_child(ps)
	ps.setup(gs)

	# Basic activation
	ps.activate("freeze")
	_check("freeze activates", ps.is_frozen)
	_check("is_active('freeze') reflects state", ps.is_active("freeze"))
	_check("freeze ratio starts near 1.0", ps.get_freeze_ratio() > 0.9, str(ps.get_freeze_ratio()))
	_check("freeze counted in active powerups", "freeze" in ps.get_active_powerups())

	# Expiry via process()
	var expired_signals: Array = []
	ps.powerup_expired.connect(func(kind): expired_signals.append(kind))
	ps.process(ps.FREEZE_DURATION + 0.1)
	_check("freeze expires after its duration elapses", not ps.is_frozen)
	_check("powerup_expired fired for freeze", "freeze" in expired_signals, str(expired_signals))

	# Score multiplier
	_check("no multiplier before double_score", is_equal_approx(ps.get_score_multiplier(), 1.0))
	ps.activate("double_score")
	_check("double_score doubles the multiplier", is_equal_approx(ps.get_score_multiplier(), 2.0), str(ps.get_score_multiplier()))
	ps.cancel("double_score")
	_check("cancel() ends double_score early", not ps.double_score_active)

	# Unknown kind: warned, not counted
	var before_count = ps.total_powerups_collected
	ps.activate("not_a_real_powerup_kind")
	_check("unrecognized kind doesn't increment collected count", ps.total_powerups_collected == before_count, "before=%d after=%d" % [before_count, ps.total_powerups_collected])

	# Cooldown gating
	ps.kind_cooldowns["bonus_life"] = 60.0
	var lives_before = gs.lives
	ps.activate("bonus_life")
	var count_after_first = ps.total_powerups_collected
	ps.activate("bonus_life") # immediate repeat - should be blocked by cooldown
	_check("cooldown blocks an immediate repeat activation", ps.total_powerups_collected == count_after_first, "count stayed at %d" % ps.total_powerups_collected)

	# Reset
	ps.reset()
	_check("reset() clears frozen state", not ps.is_frozen)
	_check("reset() clears double_score", not ps.double_score_active)
	_check("reset() clears collected count", ps.total_powerups_collected == 0)
	_check("reset() clears history", ps.powerup_history.is_empty())

	gs.queue_free()
	ps.queue_free()


# ---------------------------------------------------------------------
# Ghost Race code encode/decode round-trip — the closest thing this
# codebase has to the README's "Daily Challenge score encoding/decoding"
# item: a purely local, no-server clipboard share/compare code
# (GhostRacer._encode_ghost_code / _decode_ghost_code). A silent bug here
# would corrupt shared codes without ever throwing an error.
# ---------------------------------------------------------------------
func _test_ghost_code_roundtrip() -> void:
	print("-- Ghost code encode/decode round-trip --")

	var gr := GhostRacer.new()
	add_child(gr)

	var code = gr._encode_ghost_code("Ada", 87.3)
	var decoded = gr._decode_ghost_code(code)
	_check("decoded label matches", decoded.get("label", "") == "Ada", str(decoded))
	_check("decoded wpm matches", is_equal_approx(decoded.get("wpm", 0.0), 87.3), str(decoded))

	# A "|" in the label would break the pipe-delimited payload if not
	# sanitized - it should be silently replaced, not corrupt the field.
	var code2 = gr._encode_ghost_code("A|B|C", 50.0)
	var decoded2 = gr._decode_ghost_code(code2)
	_check("pipe characters in the label are sanitized before encoding", not "|" in decoded2.get("label", "|"), str(decoded2))

	# Blank label falls back to "Friend" rather than encoding an empty field.
	var code3 = gr._encode_ghost_code("   ", 40.0)
	var decoded3 = gr._decode_ghost_code(code3)
	_check("blank label falls back to 'Friend'", decoded3.get("label", "") == "Friend", str(decoded3))

	# Garbage / non-base64 input must fail closed (empty dict), not crash
	# or silently return a fabricated result.
	_check("garbage input decodes to an empty dict", gr._decode_ghost_code("not a real code!!").is_empty())
	_check("empty string decodes to an empty dict", gr._decode_ghost_code("").is_empty())

	# A code from a different/older format tag should be rejected rather
	# than silently accepted with the wrong shape.
	var wrong_tag = Marshalls.utf8_to_base64("OLDFMT|Someone|99.0")
	_check("mismatched format tag is rejected", gr._decode_ghost_code(wrong_tag).is_empty())

	# Zero/negative WPM should never round-trip as a "valid" decoded code.
	var zero_wpm_code = Marshalls.utf8_to_base64("KLGR1|Nobody|0.0")
	_check("zero WPM is rejected as invalid", gr._decode_ghost_code(zero_wpm_code).is_empty())

	gr.queue_free()


# ---------------------------------------------------------------------
# Save-file migration — priority #4 from README's "not covered" list.
# Simulates an old save written before many of GameState's current keys
# existed, and checks that loading it into a newer build degrades
# gracefully (every field falls back to its documented default) instead
# of crashing or leaving fields in a broken state.
# ---------------------------------------------------------------------
func _test_save_migration_from_old_save() -> void:
	print("-- Save-file migration (old save -> current build) --")

	var save_path := GameState.SAVE_PATH
	var backup_path := save_path + ".bak"
	var had_existing_save := FileAccess.file_exists(save_path)
	if had_existing_save:
		DirAccess.copy_absolute(save_path, backup_path)

	# Write a deliberately minimal ConfigFile - only the two fields that
	# would have existed in the game's very first save format - leaving
	# every "settings"/"career"/"extra" key entirely absent, same as a
	# real old save would look like next to today's GameState.
	var old_cfg := ConfigFile.new()
	old_cfg.set_value("scores", "high_scores", [50, 30, 10])
	old_cfg.set_value("scores", "best_wpm", 22.5)
	var write_err := old_cfg.save(save_path)
	_check("old-format save file writes without error", write_err == OK, "err=%d" % write_err)

	var gs := GameState.new()
	add_child(gs)
	gs.load_save_data()

	_check("fields present in the old save still load correctly", gs.high_scores == [50, 30, 10] and is_equal_approx(gs.best_wpm, 22.5), "high_scores=%s best_wpm=%s" % [gs.high_scores, gs.best_wpm])

	# Every key added since should fall back to its documented default
	# rather than being null, wrong-typed, or crashing the load.
	_check("selected_theme defaults gracefully", gs.selected_theme == "General", gs.selected_theme)
	_check("selected_language defaults gracefully", gs.selected_language == "en", gs.selected_language)
	_check("colorblind_mode defaults gracefully", gs.colorblind_mode == "off", gs.colorblind_mode)
	_check("career_unlocked_rank defaults gracefully", gs.career_unlocked_rank == 1, str(gs.career_unlocked_rank))
	_check("unlocked_badges defaults to an empty array", gs.unlocked_badges is Array and gs.unlocked_badges.is_empty())
	_check("daily_challenge_date defaults gracefully", gs.daily_challenge_date == "", gs.daily_challenge_date)
	_check("custom_word_list defaults to an empty array", gs.custom_word_list is Array and gs.custom_word_list.is_empty())
	_check("ai_versus_record defaults to an empty dict", gs.ai_versus_record is Dictionary and gs.ai_versus_record.is_empty())
	_check("font_scale defaults gracefully", is_equal_approx(gs.font_scale, 1.15), str(gs.font_scale))

	gs.queue_free()

	# Restore whatever save existed before this test ran.
	if had_existing_save:
		DirAccess.copy_absolute(backup_path, save_path)
		DirAccess.remove_absolute(backup_path)
	else:
		DirAccess.remove_absolute(save_path)


# ---------------------------------------------------------------------
# Regression coverage for the "setup() frees a node another script still
# holds a reference to" bug class (found 2026-07-15: switching Casual/Jelly
# interface style called refresh_theme() -> setup() on stats_screen, which
# looped over every child of result_panel and queue_free()'d it — including
# final_score_label and coin_label, which main.gd holds as long-lived refs
# and passes back into setup() every time a theme refresh fires. The second
# call then received a freed object and crashed with a type error.
#
# These three tests don't render anything - they just call setup() twice in
# a row (simulating one real game-over screen showing, then a style change
# firing refresh_theme()) and confirm nothing throws and the key node refs
# passed in are still valid afterwards. Any screen that rebuilds its content
# in response to GameState.ui_style_changed is a candidate for this same bug,
# so add a test here for any new screen that gets a refresh_theme() method.
# ---------------------------------------------------------------------

func _test_stats_screen_survives_repeated_theme_refresh() -> void:
	print("-- StatsScreen survives repeated setup()/refresh_theme() --")

	var gs := GameState.new()
	add_child(gs)

	var result_panel := ColorRect.new()
	add_child(result_panel)

	# Mirrors main.gd: final_score_label/coin_label are children living
	# INSIDE result_panel, not siblings, which is what makes them vulnerable
	# to a get_children()+queue_free() loop over result_panel's contents.
	var final_score_label := Label.new()
	result_panel.add_child(final_score_label)
	var coin_label := Label.new()
	result_panel.add_child(coin_label)

	var stats_screen := StatsScreen.new()
	add_child(stats_screen)

	# _audio is only touched inside signal-callback closures during setup(),
	# never called directly, so null is safe for this smoke test.
	stats_screen.setup(result_panel, final_score_label, coin_label, gs, null)
	_check("first setup() call does not crash", true)
	_check("final_score_label still valid after first setup()", is_instance_valid(final_score_label))
	_check("coin_label still valid after first setup()", is_instance_valid(coin_label))

	# This is the exact call sequence a Casual/Jelly style switch triggers.
	stats_screen.refresh_theme()
	_check("refresh_theme() does not crash", true)
	_check("final_score_label still valid after refresh_theme()", is_instance_valid(final_score_label))
	_check("coin_label still valid after refresh_theme()", is_instance_valid(coin_label))

	# A second style switch in the same session - the scenario that would
	# have crashed before the fix, since the freed refs would already be
	# invalid going into this call.
	stats_screen.refresh_theme()
	_check("second refresh_theme() does not crash", true)

	stats_screen.queue_free()
	result_panel.queue_free()
	gs.queue_free()


func _test_pause_menu_survives_repeated_theme_refresh() -> void:
	print("-- PauseMenu survives repeated setup()/refresh_theme() --")

	var gs := GameState.new()
	add_child(gs)

	var root := Control.new()
	add_child(root)

	var pause_menu := PauseMenu.new()
	add_child(pause_menu)

	pause_menu.setup(root, gs, null)
	_check("PauseMenu first setup() does not crash", true)

	pause_menu.refresh_theme()
	_check("PauseMenu refresh_theme() does not crash", true)

	pause_menu.refresh_theme()
	_check("PauseMenu second refresh_theme() does not crash", true)

	pause_menu.queue_free()
	root.queue_free()
	gs.queue_free()


func _test_difficulty_menu_survives_repeated_theme_refresh() -> void:
	print("-- DifficultyMenu survives repeated setup()/refresh_theme() --")

	var gs := GameState.new()
	add_child(gs)

	var root := Control.new()
	add_child(root)

	var difficulty_menu := DifficultyMenu.new()
	add_child(difficulty_menu)

	difficulty_menu.setup(root, gs)
	_check("DifficultyMenu first setup() does not crash", true)

	difficulty_menu.refresh_theme()
	_check("DifficultyMenu refresh_theme() does not crash", true)

	difficulty_menu.refresh_theme()
	_check("DifficultyMenu second refresh_theme() does not crash", true)

	difficulty_menu.queue_free()
	root.queue_free()
	gs.queue_free()


# ---------------------------------------------------------------------
# Coverage for register_online_versus_result() (added alongside the
# online relay/WebSocket feature) - checks the win/loss/tie counters
# increment correctly for each outcome, and that they persist through a
# save/load cycle the same as every other stat this game tracks. This
# doesn't touch networking at all - it's pure GameState logic, so it's
# fast, deterministic, and doesn't need a live relay server to run.
# ---------------------------------------------------------------------

func _test_online_versus_result_tracking() -> void:
	print("-- GameState.register_online_versus_result() tracking --")

	var gs := GameState.new()
	add_child(gs)

	var had_existing_save := FileAccess.file_exists(gs.SAVE_PATH)
	var backup_path := gs.SAVE_PATH + ".bak"
	if had_existing_save:
		DirAccess.copy_absolute(gs.SAVE_PATH, backup_path)

	_check("starts at zero matches played", gs.online_versus_matches_played == 0, str(gs.online_versus_matches_played))

	gs.register_online_versus_result(true, false)   # a win
	gs.register_online_versus_result(false, false)  # a loss
	gs.register_online_versus_result(false, true)   # a tie (won flag ignored when tie is true)

	_check("matches_played counts all three results", gs.online_versus_matches_played == 3, str(gs.online_versus_matches_played))
	_check("wins counts only the win", gs.online_versus_wins == 1, str(gs.online_versus_wins))
	_check("losses counts only the loss", gs.online_versus_losses == 1, str(gs.online_versus_losses))
	_check("ties counts only the tie", gs.online_versus_ties == 1, str(gs.online_versus_ties))
	# A tie must not also be double-counted as a win or loss.
	_check("win+loss+tie sums to matches_played", (gs.online_versus_wins + gs.online_versus_losses + gs.online_versus_ties) == gs.online_versus_matches_played, "")

	var gs2 := GameState.new()
	add_child(gs2)
	gs2.load_save_data()

	_check("online_versus_wins round-trips through save/load", gs2.online_versus_wins == 1, str(gs2.online_versus_wins))
	_check("online_versus_losses round-trips through save/load", gs2.online_versus_losses == 1, str(gs2.online_versus_losses))
	_check("online_versus_ties round-trips through save/load", gs2.online_versus_ties == 1, str(gs2.online_versus_ties))
	_check("online_versus_matches_played round-trips through save/load", gs2.online_versus_matches_played == 3, str(gs2.online_versus_matches_played))

	if had_existing_save:
		DirAccess.copy_absolute(backup_path, gs.SAVE_PATH)
		DirAccess.remove_absolute(backup_path)
	else:
		DirAccess.remove_absolute(gs.SAVE_PATH)

	gs.queue_free()
	gs2.queue_free() 
