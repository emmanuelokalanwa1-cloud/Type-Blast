class_name SentenceBank
extends RefCounted

## Data source for an optional "Sentence Practice" mode: instead of single
## falling words, the player types whole sentences. Mirrors WordBank's
## architecture on purpose (lazy load from res://data/sentences/, cache,
## safety-net fallback) so it's a drop-in for anyone wiring up a new game
## mode later - nothing here is wired into gameplay yet, this is data +
## a clean API waiting to be called from a screen/controller.
##
## Sentences are template-generated from the game's own real-word theme
## pools (data/words/*.txt), not copied from any book, article, or song -
## safe to ship without licensing concerns.

const SENTENCE_DIR := "res://data/sentences/"

const THEME_FILES: Dictionary = {
	"General": "general_sentences.txt",
	"Nature": "nature_sentences.txt",
	"Tech": "tech_sentences.txt",
	"Food": "food_sentences.txt",
	"Adventure": "adventure_sentences.txt",
	"Space": "space_sentences.txt",
	"Classic": "classic_sentences.txt",
}

const FALLBACK_SENTENCES: Array = [
	"The quick brown fox jumps over the lazy dog.",
	"Practice a little every day and speed follows on its own.",
	"Typing well is mostly about not looking down at your hands.",
]

static var _cache: Dictionary = {}

static func _load_file(filename: String) -> Array:
	var path = SENTENCE_DIR + filename
	if not FileAccess.file_exists(path):
		push_warning("SentenceBank: missing sentence file '%s' - using fallback" % path)
		return FALLBACK_SENTENCES.duplicate()
	var f = FileAccess.open(path, FileAccess.READ)
	var out: Array = []
	while not f.eof_reached():
		var line = f.get_line().strip_edges()
		if line != "":
			out.append(line)
	f.close()
	return out if out.size() > 0 else FALLBACK_SENTENCES.duplicate()

## Primary accessor, same shape as WordBank.get_theme_pool().
static func get_theme_sentences(theme_name: String) -> Array:
	if _cache.has(theme_name):
		return _cache[theme_name]
	var filename = THEME_FILES.get(theme_name, THEME_FILES["General"])
	var sentences = _load_file(filename)
	_cache[theme_name] = sentences
	return sentences

static func theme_names() -> Array:
	return THEME_FILES.keys()

static func preload_all() -> void:
	for theme_name in THEME_FILES.keys():
		get_theme_sentences(theme_name)

## Random sentence for a theme, with a length cap for early/short runs
## (Career rookie ranks, first-time onboarding) so nobody's opening
## sentence is a monster.
static func random_sentence(theme_name: String, max_length: int = -1, rng: RandomNumberGenerator = null) -> String:
	var pool = get_theme_sentences(theme_name)
	var candidates = pool
	if max_length > 0:
		candidates = pool.filter(func(s): return String(s).length() <= max_length)
		if candidates.is_empty():
			candidates = pool
	var idx = rng.randi_range(0, candidates.size() - 1) if rng else (randi() % candidates.size())
	return candidates[idx]

## A batch of unique sentences, e.g. for a "5 sentences, best average WPM" mode.
static func get_batch(theme_name: String, count: int, rng: RandomNumberGenerator = null) -> Array:
	var shuffled = get_theme_sentences(theme_name).duplicate()
	if rng:
		for i in range(shuffled.size() - 1, 0, -1):
			var j = rng.randi_range(0, i)
			var tmp = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = tmp
	else:
		shuffled.shuffle()
	return shuffled.slice(0, min(count, shuffled.size()))

## Simple WPM-relevant word count for a sentence (standard "5 chars = 1
## word" typing convention, matching how most typing tests score WPM).
static func standard_word_count(sentence: String) -> float:
	return float(sentence.length()) / 5.0
