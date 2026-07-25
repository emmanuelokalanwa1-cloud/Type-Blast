class_name CareerManager
extends Node

## Tracks Career Mode ("The Climb") progress on top of MissionManager: which
## rank is unlocked, which one the player has selected to play, and whether
## a run just cleared enough of the current rank's missions to open the
## next one. Doesn't duplicate mission-completion tracking — it reads that
## straight from MissionManager, so a "Reset Progress" there naturally
## resets Career too.

signal rank_unlocked(rank: int, title: String)

var _game_state: GameState
var _mission_manager: MissionManager

var current_rank := 1   # rank the player has selected to play
var unlocked_rank := 1  # highest rank actually unlocked (playable)

func setup(game_state: GameState, mission_manager: MissionManager) -> void:
	_game_state = game_state
	_mission_manager = mission_manager
	unlocked_rank = clamp(_game_state.career_unlocked_rank, 1, CareerData.rank_count())
	current_rank = clamp(_game_state.career_current_rank, 1, unlocked_rank)

func is_rank_unlocked(rank: int) -> bool:
	return rank >= 1 and rank <= unlocked_rank

func is_climb_complete() -> bool:
	return unlocked_rank >= CareerData.rank_count() and is_rank_complete(CareerData.rank_count())

func is_rank_complete(rank: int) -> bool:
	if not is_instance_valid(_mission_manager) or not is_rank_unlocked(rank):
		return false
	return _mission_manager.get_completed_ids_for_map(rank - 1).size() >= CareerData.clear_requirement_for_rank(rank)

## Player tapped a rank on the Career Path screen. Only takes effect if
## that rank is actually unlocked — locked rows shouldn't even be clickable
## in the UI, but this guards the data layer too.
func select_rank(rank: int) -> bool:
	if not is_rank_unlocked(rank):
		return false
	current_rank = rank
	_game_state.career_current_rank = rank
	_game_state.career_mode_active = true
	_game_state.selected_difficulty = CareerData.difficulty_for_rank(rank)
	_game_state.save_data()
	return true

## Called when the player starts an ordinary (non-Career) run from the
## normal difficulty menu, so Career's fall-speed bonus doesn't leak into
## a quick-play session.
func exit_career_mode() -> void:
	if is_instance_valid(_game_state):
		_game_state.career_mode_active = false

func get_fall_speed_bonus() -> float:
	if not is_instance_valid(_game_state) or not _game_state.career_mode_active:
		return 0.0
	return CareerData.fall_speed_bonus_for_rank(current_rank)

## Progress readout for the currently-selected rank: {"done": int, "need": int}.
func get_current_rank_progress() -> Dictionary:
	if not is_instance_valid(_mission_manager):
		return {"done": 0, "need": 0}
	return {
		"done": _mission_manager.get_completed_ids_for_map(current_rank - 1).size(),
		"need": CareerData.clear_requirement_for_rank(current_rank),
	}

## Call once per run-end, after MissionManager.evaluate_run_end() has
## already recorded this run's mission completions. Returns
## {"rank_up": bool, "new_rank": int, "title": String, "climb_complete": bool}
## so the caller can show a rank-up (or full-climb) celebration exactly
## when it happens.
func check_rank_progress() -> Dictionary:
	var result := {"rank_up": false, "new_rank": 0, "title": "", "climb_complete": false}
	if not is_instance_valid(_game_state) or not is_instance_valid(_mission_manager):
		return result
	if not _game_state.career_mode_active:
		return result
	# Only the frontier rank (the one still being climbed) can trigger an
	# unlock — replaying an already-cleared earlier rank for fun shouldn't
	# skip you further ahead.
	if unlocked_rank != current_rank:
		return result

	var total_ranks := CareerData.rank_count()
	var done := _mission_manager.get_completed_ids_for_map(unlocked_rank - 1).size()
	var need := CareerData.clear_requirement_for_rank(unlocked_rank)
	if done < need:
		return result

	if unlocked_rank >= total_ranks:
		# Already at the top rank and just cleared its requirement — the
		# climb itself is complete, there's no further rank to unlock.
		if _game_state.career_highest_rank_reached < total_ranks:
			_game_state.career_highest_rank_reached = total_ranks
			_game_state.save_data()
		result.climb_complete = true
		return result

	unlocked_rank += 1
	_game_state.career_unlocked_rank = unlocked_rank
	if unlocked_rank > _game_state.career_highest_rank_reached:
		_game_state.career_highest_rank_reached = unlocked_rank
	_game_state.save_data()

	result.rank_up = true
	result.new_rank = unlocked_rank
	result.title = CareerData.title_for_rank(unlocked_rank)
	rank_unlocked.emit(unlocked_rank, result.title)
	return result
