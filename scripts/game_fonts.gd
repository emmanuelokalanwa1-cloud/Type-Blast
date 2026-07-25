class_name GameFonts
extends RefCounted

## Space Mono is the project-wide default font (set once, globally, via
## project.godot's gui/theme/custom -> assets/fonts/game_theme.tres), so
## nothing in the ~30 screen scripts needs to change to pick it up.
##
## This helper only exists for the handful of hero titles that want the
## *bold* weight specifically (ACHIEVEMENTS, RANK UP!, etc.) - call
## GameFonts.bold() and add_theme_font_override("font", ...) on that one
## label. Everything else keeps using the theme default automatically.

const BOLD_PATH := "res://assets/fonts/SpaceMono-Bold.ttf"

static var _bold_cache: Font = null

static func bold() -> Font:
	if _bold_cache == null and ResourceLoader.exists(BOLD_PATH):
		_bold_cache = load(BOLD_PATH)
	return _bold_cache
