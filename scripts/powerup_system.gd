class_name PowerupSystem
extends Node


signal powerup_activated(kind: String)
signal powerup_expired(kind: String)          # 6
signal powerup_ending_soon(kind: String)       # 7
signal powerup_progress(kind: String, ratio: float) # 8
signal all_cleared()                           # 9

var is_frozen := false
var freeze_time := 0.0
var slow_mo_factor := 1.0
var _slow_mo_timer := 0.0

# 1. Double-score effect
var double_score_active := false
var _double_score_timer := 0.0

const FREEZE_DURATION := 2.5
const SLOWMO_DURATION := 5.0
const SLOWMO_STRENGTH := 0.45
const DOUBLE_SCORE_DURATION := 6.0     # 1
const DOUBLE_SCORE_MULTIPLIER := 2.0   # 1, 3
const EXTRA_TIME_SECONDS := 15.0       # 2
const ENDING_SOON_THRESHOLD := 1.0     # 7

# 14/15. Run stats
var total_powerups_collected := 0
var powerup_history: Array = []

# 16. Optional per-kind cooldowns (seconds). Empty by default = no cooldowns.
var kind_cooldowns := {}
var _last_activation_msec := {}

# 17. Explicit pause flag, independent of whether main.gd calls process()
var _paused := false

# 7. Track which timed effects have already fired their "ending soon" warning
var _freeze_warned := false
var _slowmo_warned := false
var _double_score_warned := false

var _game_state: GameState

func setup(game_state: GameState) -> void:
	_game_state = game_state

func activate(kind: String, duration_override: float = -1.0) -> void:
	# 16. Respect an optional cooldown for this kind, if one is configured.
	if kind_cooldowns.has(kind):
		var now = Time.get_ticks_msec()
		var last = _last_activation_msec.get(kind, -999999)
		if now - last < int(kind_cooldowns[kind] * 1000.0):
			return
		_last_activation_msec[kind] = now

	match kind:
		"freeze":
			is_frozen = true
			freeze_time = duration_override if duration_override > 0.0 else FREEZE_DURATION # 4, 5
			_freeze_warned = false
		"slowmo":
			slow_mo_factor = SLOWMO_STRENGTH
			_slow_mo_timer = duration_override if duration_override > 0.0 else SLOWMO_DURATION # 4, 5
			_slowmo_warned = false
		"bonus_life":
			if _game_state:
				_game_state.add_bonus_life()
		"extra_time": # 2
			if _game_state:
				_game_state.add_bonus_time(duration_override if duration_override > 0.0 else EXTRA_TIME_SECONDS)
		"double_score": # 1
			double_score_active = true
			_double_score_timer = duration_override if duration_override > 0.0 else DOUBLE_SCORE_DURATION
			_double_score_warned = false
		_:
			# 18. Unknown kind — surfaced as a warning instead of silently no-op'ing.
			push_warning("PowerupSystem.activate() called with unrecognized kind: '%s'" % kind)
			return

	total_powerups_collected += 1 # 14
	powerup_history.append(kind)  # 15
	powerup_activated.emit(kind)

func process(delta: float) -> void:
	if _paused: # 17
		return

	if is_frozen:
		freeze_time -= delta
		if not _freeze_warned and freeze_time <= ENDING_SOON_THRESHOLD and freeze_time > 0.0: # 7
			_freeze_warned = true
			powerup_ending_soon.emit("freeze")
		if freeze_time > 0.0:
			powerup_progress.emit("freeze", clamp(freeze_time / FREEZE_DURATION, 0.0, 1.0)) # 8
		if freeze_time <= 0:
			is_frozen = false
			powerup_expired.emit("freeze") # 6

	if _slow_mo_timer > 0:
		_slow_mo_timer -= delta
		if not _slowmo_warned and _slow_mo_timer <= ENDING_SOON_THRESHOLD and _slow_mo_timer > 0.0: # 7
			_slowmo_warned = true
			powerup_ending_soon.emit("slowmo")
		if _slow_mo_timer > 0.0:
			powerup_progress.emit("slowmo", clamp(_slow_mo_timer / SLOWMO_DURATION, 0.0, 1.0)) # 8
		if _slow_mo_timer <= 0:
			slow_mo_factor = 1.0
			powerup_expired.emit("slowmo") # 6

	if _double_score_timer > 0: # 1
		_double_score_timer -= delta
		if not _double_score_warned and _double_score_timer <= ENDING_SOON_THRESHOLD and _double_score_timer > 0.0:
			_double_score_warned = true
			powerup_ending_soon.emit("double_score")
		if _double_score_timer > 0.0:
			powerup_progress.emit("double_score", clamp(_double_score_timer / DOUBLE_SCORE_DURATION, 0.0, 1.0))
		if _double_score_timer <= 0:
			double_score_active = false
			powerup_expired.emit("double_score")

# 3. Lets score-awarding code multiply cleanly without knowing internals.
func get_score_multiplier() -> float:
	return DOUBLE_SCORE_MULTIPLIER if double_score_active else 1.0

# 10. Snapshot of everything currently running.
func get_active_powerups() -> Array:
	var active: Array = []
	if is_frozen: active.append("freeze")
	if _slow_mo_timer > 0: active.append("slowmo")
	if double_score_active: active.append("double_score")
	return active

# 11. Convenience check for a single kind.
func is_active(kind: String) -> bool:
	match kind:
		"freeze": return is_frozen
		"slowmo": return _slow_mo_timer > 0
		"double_score": return double_score_active
		_: return false

# 12. Remaining-time ratios (1.0 = just activated, 0.0 = about to expire).
func get_freeze_ratio() -> float:
	return clamp(freeze_time / FREEZE_DURATION, 0.0, 1.0) if is_frozen else 0.0

func get_slowmo_ratio() -> float:
	return clamp(_slow_mo_timer / SLOWMO_DURATION, 0.0, 1.0) if _slow_mo_timer > 0 else 0.0

func get_double_score_ratio() -> float:
	return clamp(_double_score_timer / DOUBLE_SCORE_DURATION, 0.0, 1.0) if double_score_active else 0.0

# 13. End a specific effect early (e.g. a "cleanse" powerup, or a debug tool).
func cancel(kind: String) -> void:
	match kind:
		"freeze":
			if is_frozen:
				is_frozen = false
				freeze_time = 0.0
				powerup_expired.emit("freeze")
		"slowmo":
			if _slow_mo_timer > 0:
				_slow_mo_timer = 0.0
				slow_mo_factor = 1.0
				powerup_expired.emit("slowmo")
		"double_score":
			if double_score_active:
				double_score_active = false
				_double_score_timer = 0.0
				powerup_expired.emit("double_score")

# 17. Explicit pause control independent of whether main.gd calls process().
func set_paused(paused: bool) -> void:
	_paused = paused

func reset() -> void:
	is_frozen = false
	freeze_time = 0.0
	slow_mo_factor = 1.0
	_slow_mo_timer = 0.0

	double_score_active = false   # 19
	_double_score_timer = 0.0     # 19

	total_powerups_collected = 0  # 19
	powerup_history.clear()       # 19
	_last_activation_msec.clear() # 19

	_freeze_warned = false
	_slowmo_warned = false
	_double_score_warned = false
	_paused = false

	all_cleared.emit() # 9
