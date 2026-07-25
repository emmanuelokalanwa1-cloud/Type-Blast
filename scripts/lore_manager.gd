class_name LoreManager
extends RefCounted

## Loads data/lore/rank_lore.json - a short narrative blurb per Career
## rank. Purely additive: CareerScreen doesn't call this today, but the
## data and API are ready for a "read more" panel or a rank-up popup.
## Original writing, generated for this project - not sourced from
## anywhere else.

const LORE_PATH := "res://data/lore/rank_lore.json"

static var _cache: Dictionary = {}
static var _loaded := false

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(LORE_PATH):
		push_warning("LoreManager: missing '%s'" % LORE_PATH)
		return
	var f = FileAccess.open(LORE_PATH, FileAccess.READ)
	var text = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("lore"):
		push_warning("LoreManager: malformed rank_lore.json")
		return
	for entry in parsed["lore"]:
		_cache[int(entry.get("rank", 0))] = entry

static func get_lore_for_rank(rank: int) -> String:
	_load()
	var entry = _cache.get(rank, {})
	return String(entry.get("text", ""))

static func get_tier_for_rank(rank: int) -> String:
	_load()
	var entry = _cache.get(rank, {})
	return String(entry.get("tier", ""))

static func has_lore(rank: int) -> bool:
	_load()
	return _cache.has(rank)
