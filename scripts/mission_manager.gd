class_name MissionManager
extends Node

signal mission_completed(map_index: int, mission_id: String, text: String)
signal map_completed(map_index: int, map_name: String)   # 10. fires once a map's last mission completes
signal all_missions_completed()                            # 11. fires once literally everything is done

## ---------------------------------------------------------------------
## 20 additions (all guarded, same public API: setup(), get_maps(),
## is_completed(), evaluate_run_end() — _check_mission's behavior is
## unchanged, just hardened against bad data)
## ---------------------------------------------------------------------
##  1. evaluate_run_end() guards against a missing GameState instead of
##     crashing
##  2. is_completed() guards against a missing/malformed completed-ids list
##  3. O(1) mission-id lookup cache (was: nothing, callers scanned manually)
##  4. get_map_completion(map_index) -> {done, total}
##  5. is_map_completed(map_index) -> bool
##  6. get_completion_percent() -> overall % across every map
##  7. get_total_mission_count()
##  8. get_completed_mission_count()
##  9. get_highest_completed_map_index() -> current "tier" for UI
## 10. map_completed signal — fires exactly when a map's last mission
##     completes (no separate "already emitted" flag needed: it's derived
##     fresh from completed_mission_ids each call, so a progress reset
##     naturally lets it fire again on the next full clear)
## 11. all_missions_completed signal — same self-correcting approach
## 12. get_next_incomplete_mission() -> Dictionary, for UI hints/auto-scroll
## 13. get_completed_ids_for_map(map_index) -> Array
## 14. _check_mission hardened with .get() defaults instead of direct
##     dictionary indexing, so one malformed mission entry can't crash
##     the whole evaluation pass
## 15. Numeric mission types now guard against a non-numeric target
##     instead of throwing a comparison error
## 16. Ephemeral (non-persisted) "just completed" timestamps, exposed via
##     get_last_completion_time(id), for "NEW!" highlight UI
## 17. force_complete_mission(id) — clearly-marked debug/dev helper
## 18. get_map_index_for_mission(id) -> int, via the lookup cache
## 19. Duplicate mission-id detection while building the cache (push_warning
##     instead of silently letting one shadow the other)
## 20. Everything guarded so a bad entry never throws instead of failing safely
## ---------------------------------------------------------------------

var _game_state: GameState
var _maps: Array = MissionData.get_maps()

# --- new internal state ---
var _mission_lookup := {}          # 3/18/19: id -> {"map_index": int, "mission": Dictionary}
var _completion_times := {}        # 16: id -> Unix time (ephemeral, not saved)

func setup(game_state: GameState) -> void:
	_game_state = game_state
	_build_lookup_cache()

func _build_lookup_cache() -> void:
	# 3/19. Build an O(1) id -> mission lookup once, instead of every caller
	# scanning _maps by hand. Flags any duplicate ids since that would
	# silently make one mission unreachable.
	_mission_lookup.clear()
	for map_index in _maps.size():
		var map: Dictionary = _maps[map_index]
		for mission: Dictionary in map.get("missions", []):
			var id = mission.get("id", "")
			if id == "":
				continue
			if _mission_lookup.has(id):
				push_warning("MissionManager: duplicate mission id '%s' — the earlier one will be shadowed." % id)
			_mission_lookup[id] = {"map_index": map_index, "mission": mission}

func get_maps() -> Array:
	return _maps

func is_completed(mission_id: String) -> bool:
	# 2. Defensive: never crash just because save data hasn't loaded yet.
	if not is_instance_valid(_game_state):
		return false
	var ids = _game_state.get("completed_mission_ids")
	if typeof(ids) != TYPE_ARRAY:
		return false
	return mission_id in ids

## Call once, right after GameState.end_run() has updated score/level/etc
## for that run. Returns the list of newly-completed missions (each a
## {map_index, id, text} Dictionary) so the caller can show a toast per one.
func evaluate_run_end(did_win: bool) -> Array:
	var newly_completed: Array = []

	# 1. Defensive: bail out cleanly rather than crashing mid-run-end.
	if not is_instance_valid(_game_state):
		return newly_completed

	var accuracy := _game_state.get_accuracy()
	var wpm := _game_state.get_wpm()

	for map_index in _maps.size():
		var map: Dictionary = _maps[map_index]
		for mission: Dictionary in map.get("missions", []):
			var id: String = mission.get("id", "")
			if id == "" or is_completed(id):
				continue
			if _check_mission(mission, did_win, accuracy, wpm):
				_game_state.completed_mission_ids.append(id)
				_completion_times[id] = Time.get_unix_time_from_system() # 16
				newly_completed.append({"map_index": map_index, "id": id, "text": mission.get("text", "")})
				mission_completed.emit(map_index, id, mission.get("text", ""))

	if not newly_completed.is_empty():
		_game_state.save_data()

		# 10. Fire map_completed for any map that just became fully done.
		var touched_maps := {}
		for entry in newly_completed:
			touched_maps[entry.map_index] = true
		for map_index in touched_maps.keys():
			if is_map_completed(map_index):
				var map_name: String = _maps[map_index].get("name", "")
				map_completed.emit(map_index, map_name)

		# 11. Fire all_missions_completed if this run finished the very last one.
		if get_completed_mission_count() >= get_total_mission_count() and get_total_mission_count() > 0:
			all_missions_completed.emit()

	return newly_completed

## Call after each completed sentence in Sentence Practice. Only checks
## sentence_count / sentence_wpm missions - never touches run_* missions,
## so it can't accidentally complete a falling-word mission using
## sentence-mode numbers.
func evaluate_sentence_practice(sentence_wpm: float) -> Array:
	var newly_completed: Array = []
	if not is_instance_valid(_game_state):
		return newly_completed

	for map_index in _maps.size():
		var map: Dictionary = _maps[map_index]
		for mission: Dictionary in map.get("missions", []):
			var id: String = mission.get("id", "")
			var mission_type: String = mission.get("type", "")
			if id == "" or is_completed(id):
				continue
			if mission_type != "sentence_count" and mission_type != "sentence_wpm":
				continue
			var target = mission.get("target")
			if typeof(target) != TYPE_INT and typeof(target) != TYPE_FLOAT:
				continue
			var done := false
			if mission_type == "sentence_count":
				done = _game_state.sentence_practice_count >= target
			else:
				done = sentence_wpm >= target
			if done:
				_game_state.completed_mission_ids.append(id)
				_completion_times[id] = Time.get_unix_time_from_system()
				newly_completed.append({"map_index": map_index, "id": id, "text": mission.get("text", "")})
				mission_completed.emit(map_index, id, mission.get("text", ""))

	if not newly_completed.is_empty():
		_game_state.save_data()
		var touched_maps := {}
		for entry in newly_completed:
			touched_maps[entry.map_index] = true
		for map_index in touched_maps.keys():
			if is_map_completed(map_index):
				map_completed.emit(map_index, _maps[map_index].get("name", ""))
		if get_completed_mission_count() >= get_total_mission_count() and get_total_mission_count() > 0:
			all_missions_completed.emit()

	return newly_completed

## Call once per finished AI Versus match. Only checks ai_versus_win
## missions - never touches run_*/sentence_* missions, so it can't
## accidentally complete an unrelated mission using AI Versus numbers.
func evaluate_ai_versus(_player_won: bool) -> Array:
	return _evaluate_lifetime_counter_mission("ai_versus_win")


## Call once per finished Ghost Race. Only checks ghost_race_win missions.
func evaluate_ghost_race(_beat_ghost: bool) -> Array:
	return _evaluate_lifetime_counter_mission("ghost_race_win")


## Call once per finished Versus Mode or LAN Versus match. Only checks
## versus_played missions - these two modes share one lifetime counter
## (GameState.versus_matches_played), same as they share the "Local
## Legend" badge, since both are "raced a friend" in spirit.
func evaluate_versus_played() -> Array:
	return _evaluate_lifetime_counter_mission("versus_played")


## Call each time a 10/25/50-combo streak bonus fires in the main falling-
## word game (see main.gd's _apply_streak_bonus()). Only checks
## streak_bonus_total missions.
func evaluate_streak_bonus() -> Array:
	return _evaluate_lifetime_counter_mission("streak_bonus_total")


## Call once a chained Practice Playlist finishes every queued step. Only
## checks playlist_complete missions.
func evaluate_playlist_complete() -> Array:
	return _evaluate_lifetime_counter_mission("playlist_complete")


## Call once per finished Ghost Rival rematch (the pinned rival, not the
## ad-hoc target picker — see evaluate_ghost_race() for that). Only checks
## ghost_rival_win missions.
func evaluate_ghost_rival() -> Array:
	return _evaluate_lifetime_counter_mission("ghost_rival_win")


## Call once per Daily Login Reward claim. Only checks login_streak
## missions, against the all-time best login streak.
func evaluate_daily_login() -> Array:
	return _evaluate_lifetime_counter_mission("login_streak")


## Shared implementation for the three lifetime-counter mission types
## above. Each only reads its own GameState field, matched by mission_type,
## so none of them can cross-complete another type's missions.
func _evaluate_lifetime_counter_mission(mission_type: String) -> Array:
	var newly_completed: Array = []
	if not is_instance_valid(_game_state):
		return newly_completed

	var current_value = 0
	match mission_type:
		"ai_versus_win":
			current_value = _game_state.ai_versus_wins_total
		"ghost_race_win":
			current_value = _game_state.ghost_race_wins_total
		"versus_played":
			current_value = _game_state.versus_matches_played
		"streak_bonus_total":
			current_value = _game_state.streak_bonus_triggers_total
		"playlist_complete":
			current_value = _game_state.playlists_completed_total
		"ghost_rival_win":
			current_value = _game_state.ghost_rival_wins_total
		"login_streak":
			current_value = _game_state.login_reward_best_streak
		_:
			return newly_completed

	for map_index in _maps.size():
		var map: Dictionary = _maps[map_index]
		for mission: Dictionary in map.get("missions", []):
			var id: String = mission.get("id", "")
			var type: String = mission.get("type", "")
			if id == "" or is_completed(id):
				continue
			if type != mission_type:
				continue
			var target = mission.get("target")
			if typeof(target) != TYPE_INT and typeof(target) != TYPE_FLOAT:
				continue
			if current_value >= target:
				_game_state.completed_mission_ids.append(id)
				_completion_times[id] = Time.get_unix_time_from_system()
				newly_completed.append({"map_index": map_index, "id": id, "text": mission.get("text", "")})
				mission_completed.emit(map_index, id, mission.get("text", ""))

	if not newly_completed.is_empty():
		_game_state.save_data()
		var touched_maps := {}
		for entry in newly_completed:
			touched_maps[entry.map_index] = true
		for map_index in touched_maps.keys():
			if is_map_completed(map_index):
				map_completed.emit(map_index, _maps[map_index].get("name", ""))
		if get_completed_mission_count() >= get_total_mission_count() and get_total_mission_count() > 0:
			all_missions_completed.emit()

	return newly_completed

func _check_mission(mission: Dictionary, did_win: bool, accuracy: float, wpm: float) -> bool:
	# 14. Use .get() with defaults everywhere instead of direct indexing, so
	# one malformed mission entry (missing "type"/"target") can't crash the
	# whole evaluation pass — it just safely fails that one check.
	var target = mission.get("target")
	var mission_type = mission.get("type", "")

	# 15. Guard numeric comparisons against a non-numeric target.
	var numeric_types = ["run_words", "run_combo", "run_accuracy", "run_score", "run_wpm", "reach_level", "sentence_count", "sentence_wpm"]
	if mission_type in numeric_types and typeof(target) != TYPE_INT and typeof(target) != TYPE_FLOAT:
		return false

	match mission_type:
		"run_words":
			return _game_state.words_typed_total >= target
		"run_combo":
			return _game_state.max_combo_this_run >= target
		"run_accuracy":
			return accuracy >= target
		"run_score":
			return _game_state.score >= target
		"run_wpm":
			return wpm >= target
		"reach_level":
			return _game_state.level >= target
		"survive_full_run":
			return did_win
		"use_theme":
			return _game_state.selected_theme == target
		"use_weak_keys":
			return _game_state.weak_keys_mode
		"sentence_count":
			return _game_state.sentence_practice_count >= target
		"sentence_wpm":
			# Checked separately via evaluate_sentence_practice(), since it
			# needs the sentence's own WPM, not the falling-word run's.
			return false
		_:
			return false

## 4. Completion count for a single map: {"done": int, "total": int}.
func get_map_completion(map_index: int) -> Dictionary:
	if map_index < 0 or map_index >= _maps.size():
		return {"done": 0, "total": 0}
	var map: Dictionary = _maps[map_index]
	var total := 0
	var done := 0
	for mission: Dictionary in map.get("missions", []):
		total += 1
		if is_completed(mission.get("id", "")):
			done += 1
	return {"done": done, "total": total}

## 5. Whether every mission in a given map is complete.
func is_map_completed(map_index: int) -> bool:
	var c = get_map_completion(map_index)
	return c.total > 0 and c.done == c.total

## 6. Overall completion percentage across every map (0-100).
func get_completion_percent() -> float:
	var total = get_total_mission_count()
	if total <= 0:
		return 0.0
	return (float(get_completed_mission_count()) / float(total)) * 100.0

## 7. Total number of missions across every map.
func get_total_mission_count() -> int:
	var total := 0
	for map: Dictionary in _maps:
		total += map.get("missions", []).size()
	return total

## 8. Total number of missions completed across every map.
func get_completed_mission_count() -> int:
	var count := 0
	for map: Dictionary in _maps:
		for mission: Dictionary in map.get("missions", []):
			if is_completed(mission.get("id", "")):
				count += 1
	return count

## 9. Index of the highest map that's 100% complete, or -1 if none are.
func get_highest_completed_map_index() -> int:
	var highest := -1
	for map_index in _maps.size():
		if is_map_completed(map_index):
			highest = map_index
	return highest

## 12. The first incomplete mission encountered, in map/mission order —
## handy for "here's what to do next" UI hints or auto-scroll targets.
func get_next_incomplete_mission() -> Dictionary:
	for map_index in _maps.size():
		var map: Dictionary = _maps[map_index]
		for mission: Dictionary in map.get("missions", []):
			var id = mission.get("id", "")
			if id != "" and not is_completed(id):
				return {"map_index": map_index, "mission": mission}
	return {}

## 13. All completed mission ids belonging to a specific map.
func get_completed_ids_for_map(map_index: int) -> Array:
	var out: Array = []
	if map_index < 0 or map_index >= _maps.size():
		return out
	var map: Dictionary = _maps[map_index]
	for mission: Dictionary in map.get("missions", []):
		var id = mission.get("id", "")
		if id != "" and is_completed(id):
			out.append(id)
	return out

## 16. Unix timestamp of when a mission was completed THIS SESSION (not
## persisted — only useful for "NEW!" highlight animations right after a
## run ends, not for anything that needs to survive a restart).
func get_last_completion_time(mission_id: String) -> int:
	return _completion_times.get(mission_id, 0)

## 18. Which map a given mission id belongs to, or -1 if unknown.
func get_map_index_for_mission(mission_id: String) -> int:
	if _mission_lookup.has(mission_id):
		return _mission_lookup[mission_id].map_index
	return -1

## 17. DEBUG/DEV HELPER ONLY — force-completes a mission by id without
## checking its actual condition. Useful for testing UI states quickly;
## not wired to any in-game button, so it can't be triggered by players
## unless you explicitly call it from a debug menu.
func force_complete_mission(mission_id: String) -> void:
	if not is_instance_valid(_game_state):
		return
	if is_completed(mission_id) or not _mission_lookup.has(mission_id):
		return
	_game_state.completed_mission_ids.append(mission_id)
	_completion_times[mission_id] = Time.get_unix_time_from_system()
	var entry = _mission_lookup[mission_id]
	mission_completed.emit(entry.map_index, mission_id, entry.mission.get("text", ""))
	_game_state.save_data()
