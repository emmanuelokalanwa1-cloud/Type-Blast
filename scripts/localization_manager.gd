class_name LocalizationManager
extends RefCounted

## Loads data/locales/*.json - preliminary translations of the game's core
## UI strings (menus, labels, stat names). These are a solid first pass
## meant to unblock localization work, not final human-reviewed copy -
## worth a native-speaker pass before shipping any one language for real.
##
## Wired into difficulty_menu.gd and stats_screen.gd, which call
## LocalizationManager.get_string(key, GameState.selected_language) instead
## of hardcoding English text. Other screens (career, missions,
## achievements, sentence mode, more) still use hardcoded English strings
## and are candidates for a future wiring pass.

const LOCALE_DIR := "res://data/locales/"
const AVAILABLE_LOCALES := ["en", "es", "fr", "de", "pt", "it"]
const DEFAULT_LOCALE := "en"

static var _cache: Dictionary = {}

static func _load_locale(locale: String) -> Dictionary:
	if _cache.has(locale):
		return _cache[locale]
	var path = LOCALE_DIR + locale + ".json"
	if not FileAccess.file_exists(path):
		_cache[locale] = {}
		return {}
	var f = FileAccess.open(path, FileAccess.READ)
	var text = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	var out = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	_cache[locale] = out
	return out

## Looks up `key` in `locale`, falling back to English, then to the key
## itself so a missing translation never shows a blank label.
static func get_string(key: String, locale: String = DEFAULT_LOCALE) -> String:
	var table = _load_locale(locale)
	if table.has(key):
		return String(table[key])
	var en_table = _load_locale(DEFAULT_LOCALE)
	if en_table.has(key):
		return String(en_table[key])
	return key

static func available_locales() -> Array:
	return AVAILABLE_LOCALES.duplicate()

static func is_supported(locale: String) -> bool:
	return AVAILABLE_LOCALES.has(locale)
