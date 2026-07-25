class_name CareerData
extends RefCounted

## Static data for Career Mode ("The Climb"). Ranks reuse MissionData's 20
## maps directly — Map 1's name becomes Rank 1's title, Map 1's missions
## become Rank 1's clear requirements, and so on. Add a Map 21 to
## MissionData and it becomes Rank 21 here automatically — nothing in this
## file needs to change to support more ranks.

## Fraction of a rank's missions that must be cleared to unlock the next
## rank. Deliberately not 100% — one brutal outlier mission (a perfect-
## accuracy run, say) can't wall someone out of progressing.
const CLEAR_FRACTION := 0.8

## Rank "tier" labels shown as a small badge above each row of 5 ranks on
## the ladder, purely cosmetic grouping so a 20-row list doesn't feel like
## one undifferentiated wall.
const TIER_LABELS := ["ROOKIE", "CONTENDER", "VETERAN", "ELITE"]

static func rank_count() -> int:
	return MissionData.get_maps().size()

static func title_for_rank(rank: int) -> String:
	var maps = MissionData.get_maps()
	if rank < 1 or rank > maps.size():
		return "Rank %d" % rank
	return String(maps[rank - 1].get("name", "Rank %d" % rank))

## Just the flavor part of the name, without the "Map N — " prefix, so UI
## can show "RANK 3 — MASTERY" instead of "RANK 3 — Map 3 — Mastery".
static func flavor_for_rank(rank: int) -> String:
	var full = title_for_rank(rank)
	var dash = full.find(" — ")
	if dash == -1:
		return full
	return full.substr(dash + 3)

static func missions_for_rank(rank: int) -> Array:
	var maps = MissionData.get_maps()
	if rank < 1 or rank > maps.size():
		return []
	return maps[rank - 1].get("missions", [])

## How many of a rank's missions must be cleared to unlock the next rank.
static func clear_requirement_for_rank(rank: int) -> int:
	var total = missions_for_rank(rank).size()
	if total <= 0:
		return 0
	return max(1, ceili(total * CLEAR_FRACTION))

## Which cosmetic tier a rank belongs to (4 tiers of 5 ranks each, scaling
## to any rank count so this never breaks if maps are added/removed).
static func tier_label_for_rank(rank: int) -> String:
	var total = rank_count()
	if total <= 0:
		return TIER_LABELS[0]
	var per_tier = max(1, ceili(float(total) / TIER_LABELS.size()))
	var idx = clamp((rank - 1) / per_tier, 0, TIER_LABELS.size() - 1)
	return TIER_LABELS[idx]

## Word-length pool to draw from at a given rank — reuses WordBank's
## existing Short/Medium/Long/Mixed categories rather than a separate word
## list, so Rank 1 stays easy and Rank 20 is full chaos.
static func difficulty_for_rank(rank: int) -> String:
	if rank <= 4:
		return "Short"
	elif rank <= 9:
		return "Medium"
	elif rank <= 14:
		return "Long"
	return "Mixed"

## Extra flat fall-speed bump layered on top of the normal in-run level
## curve, so higher ranks feel harder from word one — before any in-run
## leveling even kicks in. Rank 1: +0, Rank 20: +76.
static func fall_speed_bonus_for_rank(rank: int) -> float:
	return float(rank - 1) * 4.0

## Accent color per tier, used to tint rows/badges on the ladder so the
## climb visually escalates (cool green -> gold) as ranks get harder.
static func color_for_rank(rank: int) -> Color:
	var tier = tier_label_for_rank(rank)
	match tier:
		"ROOKIE":
			return Color(0.4, 0.9, 0.75)   # mint
		"CONTENDER":
			return Color(0.45, 0.75, 0.95) # sky blue
		"VETERAN":
			return Color(0.85, 0.55, 0.95) # violet
		_:
			return Color(1.0, 0.78, 0.25)  # gold

## Rank badge icons (Vector Ranks pack, CC0). Ascending material per tier -
## Wood (Rookie) -> Bronze (Contender) -> Silver (Veteran) -> Gold (Elite) -
## with 5 numbered variants per material giving each of the 20 ranks its
## own distinct badge, res://assets/ranks/<material>/rank_<1-5>.png.
const TIER_MATERIALS := ["wood", "bronze", "silver", "gold"]
const RANK_ICON_DIR := "res://assets/ranks/"

static var _icon_cache := {}

static func _material_for_tier(tier: String) -> String:
	var idx = TIER_LABELS.find(tier)
	if idx == -1 or idx >= TIER_MATERIALS.size():
		idx = TIER_MATERIALS.size() - 1
	return TIER_MATERIALS[idx]

## Small (64x64) badge for a specific rank, used on ladder rows.
static func icon_for_rank(rank: int) -> Texture2D:
	var total = rank_count()
	var per_tier = max(1, ceili(float(total) / TIER_LABELS.size()))
	var pos_in_tier = clamp(((rank - 1) % per_tier) + 1, 1, 5)
	var material = _material_for_tier(tier_label_for_rank(rank))
	var key = "%s_%d" % [material, pos_in_tier]
	if not _icon_cache.has(key):
		var path = "%s%s/rank_%d.png" % [RANK_ICON_DIR, material, pos_in_tier]
		_icon_cache[key] = load(path) if ResourceLoader.exists(path) else null
	return _icon_cache[key]

## Large (256x256) hero badge for a tier, used on the rank-up certificate.
static func large_icon_for_rank(rank: int) -> Texture2D:
	var material = _material_for_tier(tier_label_for_rank(rank))
	var key = "large_%s" % material
	if not _icon_cache.has(key):
		var path = "%slarge/rank_%s_large.png" % [RANK_ICON_DIR, material]
		_icon_cache[key] = load(path) if ResourceLoader.exists(path) else null
	return _icon_cache[key]
