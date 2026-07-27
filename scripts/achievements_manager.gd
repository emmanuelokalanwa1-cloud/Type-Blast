class_name AchievementsManager
extends RefCounted

## Loads data/achievements.json and checks a stats snapshot against each
## achievement's threshold. Deliberately stateless/pure: it does not touch
## GameState's save file or add new persisted fields on its own, so
## dropping this file into the project cannot break existing saves.
##
## To wire it up later: call AchievementsManager.evaluate(stats) with a
## Dictionary built from GameState (see `stats_keys_expected()` below for
## the shape it looks for), then persist whichever ids came back unlocked
## however you already persist other settings in GameState.save_data().

const ACHIEVEMENTS_PATH := "res://data/achievements.json"

static var _cache: Array = []
static var _loaded := false

static func _load() -> Array:
	if _loaded:
		return _cache
	_loaded = true
	if not FileAccess.file_exists(ACHIEVEMENTS_PATH):
		push_warning("AchievementsManager: missing '%s'" % ACHIEVEMENTS_PATH)
		return []
	var f = FileAccess.open(ACHIEVEMENTS_PATH, FileAccess.READ)
	var text = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("achievements"):
		push_warning("AchievementsManager: malformed achievements.json")
		return []
	_cache = parsed["achievements"]
	return _cache

static func all() -> Array:
	return _load()

static func by_category(category: String) -> Array:
	return _load().filter(func(a): return a.get("category", "") == category)

static func get_by_id(id: String) -> Dictionary:
	for a in _load():
		if a.get("id", "") == id:
			return a
	return {}

## Documents the keys this manager reads from a stats snapshot, so wiring
## it up later is a one-line call, not archaeology.
static func stats_keys_expected() -> Array:
	return ["wpm", "accuracy_percent", "words_typed_total", "best_combo",
		"career_rank", "themes_played_count"]

const CATEGORY_STAT_KEY := {
	"speed": "wpm",
	"accuracy": "accuracy_percent",
	"endurance": "words_typed_total",
	"combo": "best_combo",
	"career": "career_rank",
	"collection": "themes_played_count",
}

## Returns the ids of every achievement whose threshold is met by `stats`.
## Pure function - call it, get a list back, decide what to do with it.
static func evaluate(stats: Dictionary) -> Array:
	var unlocked: Array = []
	for a in _load():
		var key = CATEGORY_STAT_KEY.get(a.get("category", ""), "")
		if key == "" or not stats.has(key):
			continue
		if float(stats[key]) >= float(a.get("threshold", INF)):
			unlocked.append(a["id"])
	return unlocked

static func count_total() -> int:
	return _load().size()