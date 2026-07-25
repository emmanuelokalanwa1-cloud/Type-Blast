class_name AchievementIcons
extends RefCounted

## Single shared icon mapping for BOTH the granular Achievements screen
## (achievements.json / AchievementsManager) and the curated Badges panel
## (BadgesManager). Previously these two systems had no visual relationship
## to each other - achievements used plain "★"/"○" glyphs and badges used
## unicode emoji. Giving them the same underlying medal art (Kenney Medals,
## CC0) is part of unifying them into one coherent "achievement system"
## instead of two disconnected ones.
##
## Medal files live at res://assets/badges/medals/medal_<n>.png (n one of
## 1,2,3,4,6,8,9 - a curated subset of the 9-medal Kenney pack).

const MEDAL_DIR := "res://assets/badges/medals/"

## achievements.json "category" -> medal number.
const CATEGORY_MEDAL := {
	"speed": 4,
	"accuracy": 9,
	"endurance": 1,
	"combo": 2,
	"career": 6,
	"collection": 3,
}

## BadgesManager badge id -> medal number.
const BADGE_MEDAL := {
	"b_first_run": 8,
	"b_speed_40": 4,
	"b_speed_70": 4,
	"b_combo_25": 2,
	"b_combo_50": 2,
	"b_accuracy": 9,
	"b_streak_3": 3,
	"b_streak_7": 3,
	"b_sentences": 1,
	"b_daily": 6,
	"b_boss": 8,
	"b_career_10": 6,
	"b_missions": 3,
	"b_survivor": 8,
	"b_deep_signal": 6,
	"b_deep_signal_remix": 1,
}

static var _cache := {}

static func _load_medal(n: int) -> Texture2D:
	if _cache.has(n):
		return _cache[n]
	var path := "%smedal_%d.png" % [MEDAL_DIR, n]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[n] = tex
	return tex

static func for_category(category: String) -> Texture2D:
	return _load_medal(CATEGORY_MEDAL.get(category, 6))

static func for_badge(badge_id: String) -> Texture2D:
	return _load_medal(BADGE_MEDAL.get(badge_id, 6))
