class_name QuotesManager
extends RefCounted

## Loads data/quotes/motivational_quotes.txt - short original lines about
## practice and typing, meant for an optional "quote of the day" or loading
## screen. Fully original text written for this project (no attribution
## needed, no licensing risk). Not wired into any screen yet.

const QUOTES_PATH := "res://data/quotes/motivational_quotes.txt"

static var _cache: Array = []
static var _loaded := false

static func _load() -> Array:
	if _loaded:
		return _cache
	_loaded = true
	if not FileAccess.file_exists(QUOTES_PATH):
		push_warning("QuotesManager: missing '%s'" % QUOTES_PATH)
		return []
	var f = FileAccess.open(QUOTES_PATH, FileAccess.READ)
	var out: Array = []
	while not f.eof_reached():
		var line = f.get_line().strip_edges()
		if line != "":
			out.append(line)
	f.close()
	_cache = out
	return _cache

static func random_quote(rng: RandomNumberGenerator = null) -> String:
	var pool = _load()
	if pool.is_empty():
		return "A little practice today beats a lot of practice someday."
	var idx = rng.randi_range(0, pool.size() - 1) if rng else (randi() % pool.size())
	return pool[idx]

## Deterministic "quote of the day" - same quote for everyone on a given
## date, same seeding trick WordBank.get_daily_words() already uses.
static func quote_of_the_day(date_seed: int) -> String:
	var rng = RandomNumberGenerator.new()
	rng.seed = date_seed
	return random_quote(rng)

static func count() -> int:
	return _load().size()
