class_name WordBank
extends RefCounted

## Central word data for the game.
##
## IMPORTANT ARCHITECTURE CHANGE: with pools this large (100,000+ words),
## embedding them as literal GDScript arrays would bloat this script to
## several megabytes and slow down parsing/compiling. Instead, word lists
## now live as plain-text data files (one word per line) under
## res://data/words/, and WordBank loads + caches them lazily the first
## time each theme is actually used.
##
## Real-word sourcing note: pools were built from an offline English
## dictionary plus WordNet's category data (animals/plants/weather for
## Nature, machines/devices/vehicles for Tech, mythical creatures/weapons/
## armor/treasure for Adventure, etc). Niche themes like Adventure simply
## don't have 100,000 distinct real English words behind them - English
## itself doesn't have that many - so those pools are the largest genuinely
## on-theme sets obtainable (hundreds to a few thousand words), while
## General is 100,000+ since it draws from the whole dictionary.

const WORD_DIR := "res://data/words/"
const EXTENDED_GENERAL_FILE := "general_extended.txt" # ~415k word "insane" pool, opt-in only

const THEME_FILES: Dictionary = {
	"General": "general.txt",       # ~130,000 real dictionary words
	"Nature": "nature.txt",         # ~11,500 animals/plants/weather/landscape words
	"Tech": "tech.txt",             # ~1,300 machines/devices/vehicles words
	"Adventure": "adventure.txt",   # ~350 mythical creatures/weapons/armor/treasure words
	"Food": "food.txt",             # ~1,700 food & drink words (new theme)
	"Space": "space.txt",           # ~90 celestial body / astronomy words (new theme)
	"Numbers & Symbols": "numbers_symbols.txt", # keyboard number-row/symbol-row drill tokens
	"Holiday": "holiday.txt",       # generic seasonal/festive words, not tied to one specific holiday
	"Classic": "classic.txt",       # classic-literature-style vocabulary
}

const BOSS_WORDS: Array = ["EXTRAORDINARY", "SYNCHRONIZATION", "ARCHITECTURE", "PHENOMENAL", "REFRIGERATION"]

## Tiny built-in safety net so the game never hard-crashes if a data file is
## missing or fails to load.
const FALLBACK_WORDS: Array = ["APPLE", "BEACH", "BRAIN", "BREAD", "CHAIR", "CLOCK", "CLOUD",
	"DANCE", "EARTH", "FIELD", "FRUIT", "GLASS", "HEART", "HOUSE", "LIGHT", "MUSIC",
	"NIGHT", "OCEAN", "RIVER", "WATER"]

## Exclusion list applied while loading any word file, and re-applied
## automatically to anything added to the data files later. EXACT MATCH
## ONLY — no substring/prefix matching. That's deliberate: substring
## matching against a full dictionary is the classic "Scunthorpe problem"
## (blocking "COCK" as a prefix would also strip COCKTAIL, COCKPIT,
## COCKATOO, PEACOCK; blocking "RAPE" as a substring would strip GRAPE).
## Exact match means legitimate compound words and homographs
## (CUMIN, TITAN, BOOBY the bird, COCKTAIL, SPICE) are untouched, while
## the standalone word — which reads as offensive with zero context when
## it's just one word falling down the screen — is removed.
##
## A few genuinely ambiguous words were deliberately left OFF this list
## rather than auto-removed, because they have common non-offensive
## dictionary meanings and the call is a judgment one: CHINK (as in "a
## chink in the armor"), DYKE (embankment), GYPO, TARBABY. Revisit if
## you want them out too.
const BLOCKLIST: Array = [
	"FUCK", "FUCKS", "FUCKED", "FUCKING", "FUCKER", "FUCKERS", "MOTHERFUCKER", "MOTHERFUCKERS",
	"SHIT", "SHITS", "SHITTY", "SHITTED", "SHITTING", "SHITHEAD", "BULLSHIT",
	"BITCH", "BITCHES", "BITCHY", "BITCHING", "BITCHED", "BITCHERY", "BITCHERIES",
	"CUNT", "CUNTS",
	"NIGGER", "NIGGERS", "NIGGA", "NIGGAS", "NIGGAZ", "NIGGERING", "NIGGARDLY",
	"WHORE", "WHORES",
	"SLUT", "SLUTS", "SLUTTY",
	"COCK", "COCKS", "COCKING",
	"DICK", "DICKS", "DICKHEAD", "DICKHEADS",
	"PUSSY", "PUSSIES",
	"ASSHOLE", "ASSHOLES",
	"BASTARD", "BASTARDS",
	"TWAT", "TWATS",
	"WANK", "WANKS", "WANKER", "WANKERS", "WANKING",
	"JIZZ",
	"RAPE", "RAPES", "RAPED", "RAPING", "RAPIST", "RAPISTS",
	"FAGGOT", "FAGGOTS", "FAG", "FAGS",
	"RETARD", "RETARDS", "RETARDED",
	"MOLEST", "MOLESTS", "MOLESTED", "MOLESTER", "MOLESTERS", "MOLESTING",
	"PEDOPHILE", "PEDOPHILES", "PEDOPHILIA",
	"BESTIALITY",
	"SPIC", "SPICS",
	"KIKE", "KIKES",
	"GOOK", "GOOKS",
	"WETBACK", "WETBACKS",
	"TRANNY", "TRANNIES",
	"PAKI", "PAKIS",
	"COON", "COONS",
	"DAGO", "DAGOS",
	"HONKY", "HONKIES",
	"JIGABOO", "JIGABOOS",
	"SAMBO", "SAMBOS",
	"REDSKIN", "REDSKINS",
	"SQUAW",
	"TIT", "TITS",
	"BOOB", "BOOBS",
	"CUM",
]

static var _blockset: Dictionary = {} # built lazily from BLOCKLIST for O(1) lookups

static var _cache: Dictionary = {}         # theme name -> Array[String]   (lazy load + cache)
static var _lookup_cache: Dictionary = {}  # theme name -> Dictionary(word -> true), for O(1) validation
static var _custom_words: Dictionary = {}  # theme name -> Array[String]   (player-imported words)
static var _recent_history: Array = []     # recently-served words, avoid immediate repeats
const _HISTORY_LIMIT := 40

# ---------------------------------------------------------------------------
# LOADING
# ---------------------------------------------------------------------------

static func _load_file(filename: String) -> Array:
	if _blockset.is_empty() and not BLOCKLIST.is_empty():
		for w in BLOCKLIST:
			_blockset[w] = true
	var path = WORD_DIR + filename
	if not FileAccess.file_exists(path):
		push_warning("WordBank: missing word file '%s' - using built-in fallback list" % path)
		return FALLBACK_WORDS.duplicate()
	var f = FileAccess.open(path, FileAccess.READ)
	var out: Array = []
	while not f.eof_reached():
		var line = f.get_line().strip_edges()
		if line != "" and not _blockset.has(line):
			out.append(line)
	f.close()
	return out

## Primary accessor - replaces the old `WordBank.THEMES[name]` lookup.
static func get_theme_pool(theme_name: String) -> Array:
	if _cache.has(theme_name):
		return _cache[theme_name]
	var filename = THEME_FILES.get(theme_name, THEME_FILES["General"])
	var words = _load_file(filename)
	if _custom_words.has(theme_name):
		words = words + _custom_words[theme_name]
	_cache[theme_name] = words
	var lookup := {}
	for w in words:
		lookup[w] = true
	_lookup_cache[theme_name] = lookup
	return words

static func theme_names() -> Array:
	return THEME_FILES.keys()

## Warm every theme's cache up front, e.g. during a loading screen, so the
## first spawn of a run doesn't pay the file-read cost.
static func preload_all() -> void:
	for theme_name in THEME_FILES.keys():
		get_theme_pool(theme_name)

## Force a theme to reload from disk (useful while iterating on word list
## files during development).
static func reload_theme(theme_name: String) -> void:
	_cache.erase(theme_name)
	_lookup_cache.erase(theme_name)
	get_theme_pool(theme_name)

## The full ~415k-word "insane" dictionary dump, loaded only if a
## player/mode explicitly opts into maximum variety (kept out of the
## default pool to avoid surfacing extremely obscure words by default).
static func get_extended_general_pool() -> Array:
	if _cache.has("__extended__"):
		return _cache["__extended__"]
	var words = _load_file(EXTENDED_GENERAL_FILE)
	_cache["__extended__"] = words
	return words

## Merge a player-supplied word list into a theme (e.g. a custom vocabulary
## practice set). Words are cleaned to uppercase-alpha only.
static func import_custom_words(theme_name: String, words: Array) -> void:
	if _blockset.is_empty() and not BLOCKLIST.is_empty():
		for w in BLOCKLIST:
			_blockset[w] = true
	var cleaned: Array = []
	for w in words:
		var wl = String(w).strip_edges().to_upper()
		if _is_clean_word(wl) and not _blockset.has(wl):
			cleaned.append(wl)
	_custom_words[theme_name] = cleaned
	_cache.erase(theme_name)
	_lookup_cache.erase(theme_name)

static func _is_clean_word(s: String) -> bool:
	if s.length() == 0:
		return false
	for c in s:
		if c < "A" or c > "Z":
			return false
	return true

# ---------------------------------------------------------------------------
# FILTERS / DIFFICULTY
# ---------------------------------------------------------------------------

static func words_by_length(pool: Array, min_len: int, max_len: int) -> Array:
	var out: Array = []
	for w in pool:
		var l = String(w).length()
		if l >= min_len and l <= max_len:
			out.append(w)
	return out

## Returns the word pool for a given difficulty ("Short", "Medium", "Long", "Mixed")
## drawn from the given theme pool.
static func pool_for_difficulty(theme_pool: Array, difficulty: String) -> Array:
	match difficulty:
		"Short":
			var s = words_by_length(theme_pool, 3, 5)
			return s if s.size() > 0 else theme_pool
		"Medium":
			var m = words_by_length(theme_pool, 6, 6)
			return m if m.size() > 0 else theme_pool
		"Long":
			var l = words_by_length(theme_pool, 7, 99)
			return l if l.size() > 0 else theme_pool
		_:
			return theme_pool

## Combine multiple themes into one pool (e.g. Nature + Space).
static func pool_for_theme_mix(theme_list: Array) -> Array:
	var out: Array = []
	var seen := {}
	for theme_name in theme_list:
		for w in get_theme_pool(theme_name):
			if not seen.has(w):
				seen[w] = true
				out.append(w)
	return out

## Rough syllable estimate via vowel-group counting, used for a better
## difficulty signal than raw character length alone.
static func estimate_syllables(word: String) -> int:
	var w = word.to_lower()
	var vowels = "aeiouy"
	var count = 0
	var prev_was_vowel = false
	for c in w:
		var is_vowel = vowels.find(c) != -1
		if is_vowel and not prev_was_vowel:
			count += 1
		prev_was_vowel = is_vowel
	return max(1, count)

## Coarse difficulty tier combining length + syllable count, so e.g.
## "RHYTHM" (short but chunky) doesn't get judged purely on length.
static func difficulty_tier(word: String) -> String:
	var score = word.length() + estimate_syllables(word) * 2
	if score <= 7:
		return "Easy"
	elif score <= 13:
		return "Medium"
	return "Hard"

# ---------------------------------------------------------------------------
# PICKING WORDS
# ---------------------------------------------------------------------------

## Pick a random word, skipping anything served recently (within
## _HISTORY_LIMIT picks) so the same word doesn't reappear too soon.
static func pick_word(pool: Array, rng: RandomNumberGenerator = null) -> String:
	if pool.is_empty():
		return FALLBACK_WORDS[0]
	var choice = ""
	var attempts = 0
	while attempts < 10:
		var idx = rng.randi_range(0, pool.size() - 1) if rng else (randi() % pool.size())
		choice = pool[idx]
		if not _recent_history.has(choice):
			break
		attempts += 1
	_recent_history.append(choice)
	if _recent_history.size() > _HISTORY_LIMIT:
		_recent_history.pop_front()
	return choice

## Grab a batch of unique words from a pool (no repeats within the batch
## itself) - handy for spawning a wave of words at once.
static func get_batch(pool: Array, count: int, rng: RandomNumberGenerator = null) -> Array:
	var shuffled = pool.duplicate()
	if rng:
		for i in range(shuffled.size() - 1, 0, -1):
			var j = rng.randi_range(0, i)
			var tmp = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = tmp
	else:
		shuffled.shuffle()
	return shuffled.slice(0, min(count, shuffled.size()))

## Deterministic "daily challenge" word list - same for every player on a
## given date, by seeding the RNG from a date-derived int (e.g.
## int(Time.get_date_string_from_system().replace("-", ""))).
static func get_daily_words(theme_name: String, count: int, date_seed: int) -> Array:
	var rng = RandomNumberGenerator.new()
	rng.seed = date_seed
	return get_batch(get_theme_pool(theme_name), count, rng)

# ---------------------------------------------------------------------------
# HINTS / VALIDATION / STATS
# ---------------------------------------------------------------------------

## Hint helpers for a "reveal a letter" or "show pattern" UI.
static func hint_first_letter(word: String) -> String:
	return word.substr(0, 1) + "_".repeat(max(0, word.length() - 1))

static func hint_pattern(word: String, revealed_count: int) -> String:
	var out = ""
	for i in range(word.length()):
		out += word[i] if i < revealed_count else "_"
	return out

## O(1) check for whether a typed word exists in any known pool (uses the
## lookup dictionaries built alongside each theme's cache).
static func is_valid_word(word: String) -> bool:
	var wl = word.to_upper()
	if BOSS_WORDS.has(wl):
		return true
	for theme_name in THEME_FILES.keys():
		if not _lookup_cache.has(theme_name):
			get_theme_pool(theme_name)
		if _lookup_cache[theme_name].has(wl):
			return true
	return false

## Quick pool-size stats, handy for a debug overlay or a "word bank size"
## display in settings.
static func get_stats() -> Dictionary:
	var stats := {}
	for theme_name in THEME_FILES.keys():
		stats[theme_name] = get_theme_pool(theme_name).size()
	stats["Extended (opt-in)"] = -1 # not loaded unless requested; call get_extended_general_pool() to measure
	return stats
