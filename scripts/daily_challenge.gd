class_name DailyChallenge

## Stateless helper for the Daily Challenge mode. All persistence already
## lives on GameState (daily_challenge_date, daily_challenge_best_score,
## current_streak/longest_streak via register_practice_result) - this just
## generates the deterministic daily word list and reports/records a
## finished run through the existing GameState API, so it can't create a
## second, conflicting save system.
##
## Wherever the actual Daily Challenge screen lives (PracticeSession /
## MoreScreen, going by GameState's comments - not files I have), it needs
## roughly:
##   if DailyChallenge.is_available(game_state):
##       var words := DailyChallenge.generate_todays_words()
##       # ... run the falling/typing loop with these words ...
##       var result := DailyChallenge.submit_result(game_state, score, wpm, accuracy, words_typed)
##       # show result.share_text, result.is_new_best, etc.
##   else:
##       # show "come back tomorrow" + game_state.daily_challenge_best_score

const WORDS_PER_CHALLENGE := 20
# Deliberately theme/difficulty-neutral (not tied to whatever the player
# has selected for endless mode) so every player's Daily Challenge is the
# literal same list of words, which is what makes it comparable at all.
const CHALLENGE_THEME := "General"
const CHALLENGE_DIFFICULTY := "Mixed"


static func today_string() -> String:
	return Time.get_date_string_from_system()


## True if the player hasn't completed today's Daily Challenge yet.
static func is_available(game_state: GameState) -> bool:
	return game_state.daily_challenge_date != today_string()


## Deterministic per calendar date: every player who opens the Daily
## Challenge on the same day gets the exact same 20 words in the exact
## same order, so scores/leaderboards for the day are actually comparable.
static func generate_todays_words() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(today_string())
	var pool: Array = WordBank.pool_for_difficulty(
		WordBank.get_theme_pool(CHALLENGE_THEME), CHALLENGE_DIFFICULTY
	)
	if pool.is_empty():
		return []
	var words: Array = []
	for i in WORDS_PER_CHALLENGE:
		words.append(pool[rng.randi() % pool.size()])
	return words


## Call once when a Daily Challenge run finishes. Updates
## daily_challenge_date/daily_challenge_best_score directly, then routes
## through register_practice_result() (mode "Daily Challenge") for
## run_history + the existing streak system - so this never creates a
## second streak counter, it just feeds the one that's already there.
## register_practice_result() also calls save_data(), which persists the
## two fields set here in the same write - no extra save needed.
static func submit_result(
	game_state: GameState, score: int, wpm: float, accuracy: float, words_typed: int
) -> Dictionary:
	var is_new_best := score > game_state.daily_challenge_best_score
	if is_new_best:
		game_state.daily_challenge_best_score = score
	game_state.daily_challenge_date = today_string()

	game_state.register_practice_result("Daily Challenge", wpm, accuracy, words_typed)

	return {
		"score": score,
		"best_score": game_state.daily_challenge_best_score,
		"is_new_best": is_new_best,
		"streak": game_state.current_streak,
		"longest_streak": game_state.longest_streak,
		"streak_freeze_tokens": game_state.streak_freeze_tokens,
		"wpm": wpm,
		"accuracy": accuracy,
		"share_text": _build_share_text(game_state, wpm, accuracy),
	}


## Wordle-style one-line summary, ready to display or drop into a copy
## button - no OS share-sheet integration needed, just the string.
static func _build_share_text(game_state: GameState, wpm: float, accuracy: float) -> String:
	var streak_part := ""
	if game_state.current_streak > 0:
		streak_part = "Day streak %d \U0001F525\n" % game_state.current_streak
	return "%sKeys Learning Daily - %d WPM \u00b7 %d%% accuracy\nCan you beat it?" % [
		streak_part, roundi(wpm), roundi(accuracy)
	]
