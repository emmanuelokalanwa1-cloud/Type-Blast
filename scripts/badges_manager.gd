class_name BadgesManager
extends RefCounted

## Lightweight collectibles layer that finally gives the achievements.json
## "collection" category (and the unused assets/items art) something to
## point at. Pure data + a pure evaluate() function, same shape as
## AchievementsManager - no external file needed since the list is short.

static func all() -> Array:
	return [
		{"id": "b_first_run",   "name": "First Steps",      "icon": "★", "desc": "Finish your very first run."},
		{"id": "b_speed_40",    "name": "Quick Fingers",     "icon": "⚡", "desc": "Reach 40 WPM."},
		{"id": "b_speed_70",    "name": "Lightning Hands",   "icon": "⚡", "desc": "Reach 70 WPM."},
		{"id": "b_combo_25",    "name": "On Fire",           "icon": "🔥", "desc": "Hit a 25x combo (any run)."},
		{"id": "b_combo_50",    "name": "Unstoppable",       "icon": "🔥", "desc": "Hit a 50x combo (any run)."},
		{"id": "b_accuracy",    "name": "Sharpshooter",      "icon": "🎯", "desc": "Finish a run at 100% accuracy."},
		{"id": "b_streak_3",    "name": "Getting Into It",   "icon": "📅", "desc": "Play 3 days in a row."},
		{"id": "b_streak_7",    "name": "Habit Formed",      "icon": "📅", "desc": "Play 7 days in a row."},
		{"id": "b_login_7",     "name": "Regular",           "icon": "🎁", "desc": "Claim 7 daily login rewards in a row."},
		{"id": "b_sentences",   "name": "Wordsmith",         "icon": "📖", "desc": "Complete 25 sentences in Sentence Practice."},
		{"id": "b_daily",       "name": "Challenger",        "icon": "🏆", "desc": "Finish a Daily Challenge."},
		{"id": "b_boss",        "name": "Boss Slayer",       "icon": "⚔", "desc": "Survive a full Boss Battle."},
		{"id": "b_career_10",   "name": "Climbing High",     "icon": "🧗", "desc": "Reach Career rank 10."},
		{"id": "b_missions",    "name": "Completionist",     "icon": "🗺", "desc": "Complete every mission on a map."},
		{"id": "b_versus_played", "name": "Local Legend",    "icon": "🆚", "desc": "Play a Versus Mode match with a friend."},
		{"id": "b_ghost_beat",  "name": "Ghost Buster",      "icon": "👻", "desc": "Beat your ghost in Ghost Race."},
		{"id": "b_rival_beat",  "name": "Rival Slayer",      "icon": "👑", "desc": "Beat your pinned Ghost Rival."},
		{"id": "b_playlist",    "name": "Sequencer",         "icon": "🎵", "desc": "Complete a Practice Playlist."},
		{"id": "b_ai_versus_win", "name": "Machine Slayer",  "icon": "🤖", "desc": "Beat the AI in AI Versus Mode."},
		{"id": "b_ai_versus_champion", "name": "Ghost In The Machine", "icon": "🤖", "desc": "Beat Champion AI in AI Versus Mode."},
		{"id": "b_survivor",     "name": "Survivor",          "icon": "🔥", "desc": "Reach a 50-word streak in Survival Mode."},
		{"id": "b_deep_signal",  "name": "Signal Received",   "icon": "📡", "desc": "Clear every chapter of Story Mode: Deep Signal."},
		{"id": "b_deep_signal_remix", "name": "Remix Master", "icon": "💎", "desc": "Clear every chapter of Deep Signal on Hard difficulty."},
	]

## Returns ids newly unlocked this check (not yet in game_state.unlocked_badges).
## Read-only relative to badge definitions; the caller decides whether to
## persist unlocked_badges.
static func evaluate(game_state: GameState, mission_manager: MissionManager = null) -> Array:
	if not is_instance_valid(game_state):
		return []
	var newly: Array = []
	var already: Array = game_state.unlocked_badges

	var checks := {
		"b_first_run": game_state.run_history.size() >= 1,
		"b_speed_40": game_state.best_wpm >= 40.0,
		"b_speed_70": game_state.best_wpm >= 70.0,
		"b_combo_25": game_state.best_combo >= 25,
		"b_combo_50": game_state.best_combo >= 50,
		"b_accuracy": _has_perfect_run(game_state),
		"b_streak_3": game_state.longest_streak >= 3,
		"b_streak_7": game_state.longest_streak >= 7,
		"b_login_7": game_state.login_reward_best_streak >= 7,
		"b_sentences": game_state.sentence_practice_count >= 25,
		"b_daily": game_state.daily_challenge_date != "",
		"b_boss": _has_completed_boss(game_state),
		"b_career_10": game_state.career_highest_rank_reached >= 10,
		"b_missions": is_instance_valid(mission_manager) and mission_manager.get_completed_mission_count() > 0 and mission_manager.is_map_completed(0),
		"b_versus_played": game_state.versus_matches_played >= 1,
		"b_ghost_beat": game_state.ghost_race_wins_total >= 1,
		"b_rival_beat": game_state.ghost_rival_wins_total >= 1,
		"b_playlist": game_state.playlists_completed_total >= 1,
		"b_ai_versus_win": game_state.ai_versus_wins_total >= 1,
		"b_ai_versus_champion": game_state.ai_versus_champion_beaten,
		"b_survivor": game_state.best_survival_streak >= 50,
		"b_deep_signal": game_state.story_chapters_cleared.size() >= StoryData.chapter_count(),
		"b_deep_signal_remix": game_state.story_chapters_cleared_hard.size() >= StoryData.chapter_count(),
	}

	for id in checks.keys():
		if checks[id] and not already.has(id):
			newly.append(id)

	return newly

static func _has_perfect_run(game_state: GameState) -> bool:
	for entry in game_state.run_history:
		if entry.get("accuracy", 0.0) >= 100.0:
			return true
	return false

static func _has_completed_boss(game_state: GameState) -> bool:
	for entry in game_state.run_history:
		if String(entry.get("mode", "")) == "Boss Battle" and entry.get("score", 0) > 0:
			return true
	return false

## Returns {"id","name","icon","progress" (0..1)} for the locked badge
## you're closest to earning, or null if every measurable badge is
## already unlocked. Only badges with a clear numeric target are
## considered (a few, like Boss Slayer, are pass/fail with nothing
## meaningful to show a fraction of).
static func nearest_locked_progress(game_state: GameState):
	if not is_instance_valid(game_state):
		return null
	var targets := {
		"b_first_run": [min(game_state.run_history.size(), 1), 1],
		"b_speed_40": [game_state.best_wpm, 40.0],
		"b_speed_70": [game_state.best_wpm, 70.0],
		"b_combo_25": [game_state.best_combo, 25],
		"b_combo_50": [game_state.best_combo, 50],
		"b_streak_3": [game_state.longest_streak, 3],
		"b_streak_7": [game_state.longest_streak, 7],
		"b_sentences": [game_state.sentence_practice_count, 25],
		"b_career_10": [game_state.career_highest_rank_reached, 10],
		"b_versus_played": [min(game_state.versus_matches_played, 1), 1],
		"b_ghost_beat": [min(game_state.ghost_race_wins_total, 1), 1],
		"b_ai_versus_win": [min(game_state.ai_versus_wins_total, 1), 1],
	}
	var by_id := {}
	for b in all():
		by_id[b.id] = b

	var best = null
	var best_progress := -1.0
	for id in targets.keys():
		if game_state.unlocked_badges.has(id):
			continue
		var pair = targets[id]
		var progress = clamp(float(pair[0]) / float(pair[1]), 0.0, 0.999)
		if progress > best_progress:
			best_progress = progress
			best = by_id.get(id)

	if best == null:
		return null
	return {"id": best.id, "name": best.name, "icon": best.icon, "progress": max(best_progress, 0.0)}
