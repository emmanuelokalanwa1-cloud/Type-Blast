class_name AdaptiveDifficulty
extends Node

## Optional (off by default) feature: watches the last ~15 word outcomes
## (caught vs missed) and returns a small, tightly bounded multiplier that
## main.gd applies to its own spawn-delay calculation. Struggling players
## get a little more breathing room; players who are cruising get pulled in
## slightly tighter. Deliberately bounded (0.8x-1.3x) so it can only ever
## nudge the existing level-based pacing, never override it or make a run
## feel broken. Fully self-contained: reads game_state.adaptive_difficulty
## itself, so main.gd's spawn code can call get_delay_multiplier()
## unconditionally without an extra if-check at the call site.

const WINDOW_SIZE := 15
const HIGH_ACCURACY := 0.92
const LOW_ACCURACY := 0.65
const TIGHTEN_MULT := 0.85
const EASE_MULT := 1.25

var _game_state: GameState
var _recent: Array[int] = [] # 1 = caught, 0 = missed

func setup(game_state: GameState, typing_controller: TypingController, word_manager: WordManager) -> void:
	_game_state = game_state
	typing_controller.word_matched.connect(func(_label): _record(1))
	word_manager.word_missed.connect(func(_label): _record(0))

func _record(outcome: int) -> void:
	_recent.append(outcome)
	if _recent.size() > WINDOW_SIZE:
		_recent.pop_front()

## Called from main.gd's existing spawn-delay calculation. Returns 1.0
## (no change) whenever the feature is off, there isn't enough data yet, or
## performance is in the ordinary middle range.
func get_delay_multiplier() -> float:
	if _game_state == null or not _game_state.adaptive_difficulty:
		return 1.0
	if _recent.size() < 8:
		return 1.0
	var hits := 0
	for o in _recent:
		hits += o
	var acc := float(hits) / float(_recent.size())
	if acc >= HIGH_ACCURACY:
		return TIGHTEN_MULT
	elif acc <= LOW_ACCURACY:
		return EASE_MULT
	return 1.0
