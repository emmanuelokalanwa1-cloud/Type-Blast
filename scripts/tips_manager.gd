class_name TipsManager
extends RefCounted

## Short rotating gameplay tips. Used by MoreScreen's hub header and by
## PauseMenu (see the one extra line added there) so a paused moment
## teaches the player something instead of just sitting idle.

const TIPS := [
	"Keep your eyes on the word, not your fingers — it builds real muscle memory.",
	"A steady rhythm beats short bursts of speed. Consistency wins races.",
	"Missed a word? It goes into Drill My Mistakes so you can practice it directly.",
	"Weak Keys mode learns which letters trip you up and serves more of them.",
	"Try Zen Mode when you want to practice without the pressure of a timer.",
	"The Daily Challenge uses the same word list for everyone — great for comparing runs with friends.",
	"Combos build XP faster than raw speed. Don't break the chain!",
	"Boss Battle words get shorter time limits the longer you survive — pace yourself.",
	"A Typing Test score is most accurate over the full 60 or 180 seconds — don't stop early.",
	"Check the Leaderboard panel to see how your last run compares to your personal best.",
]

static func get_tip(index: int = -1) -> String:
	if TIPS.is_empty():
		return ""
	if index < 0:
		return TIPS[randi() % TIPS.size()]
	return TIPS[index % TIPS.size()]

static func count() -> int:
	return TIPS.size()
