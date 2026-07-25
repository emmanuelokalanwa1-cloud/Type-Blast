class_name BackgroundThemes
extends RefCounted

## Shared set of 10 clearly-different Type Blast backdrops (static art from
## the "Typing Game Background Asset Pack" — falling neon letters over a
## colored burst), used by every screen (main menu, gameplay, results,
## Career, Achievements) so the game doesn't look like the same static dark
## rectangle everywhere.
##
## `current_index` is a static var, so it's shared across every screen in
## the running game without needing a project-wide autoload. Screens call
## `advance()` each time they (re)open so the backdrop visibly moves every
## time you return to the menu, finish a run, or open Career/Achievements.
## Gameplay additionally calls `advance()` on a timer so it keeps moving
## during a single long run too.
##
## Each theme still carries `top`/`bottom`/`accent` colors (sampled from its
## background image) so screens that only need a color — banners, borders,
## text tint — don't have to load the image (see story_mode_screen.gd).

static var current_index: int = 0

const THEMES := [
	{
		"name": "Nebula Blue",
		"image": "res://assets/backgrounds/bg_01.png",
		"top": Color(0.035, 0.05, 0.13),
		"bottom": Color(0.01, 0.012, 0.03),
		"accent": Color(0.35, 0.65, 1.0),
		"planets": [0, 4],
	},
	{
		"name": "Violet Surge",
		"image": "res://assets/backgrounds/bg_02.png",
		"top": Color(0.10, 0.03, 0.13),
		"bottom": Color(0.02, 0.008, 0.03),
		"accent": Color(0.75, 0.4, 1.0),
		"planets": [1, 8],
	},
	{
		"name": "Emerald Void",
		"image": "res://assets/backgrounds/bg_03.png",
		"top": Color(0.02, 0.12, 0.09),
		"bottom": Color(0.008, 0.03, 0.03),
		"accent": Color(0.35, 1.0, 0.75),
		"planets": [5, 8],
	},
	{
		"name": "Solar Amber",
		"image": "res://assets/backgrounds/bg_04.png",
		"top": Color(0.13, 0.08, 0.02),
		"bottom": Color(0.03, 0.02, 0.01),
		"accent": Color(1.0, 0.7, 0.25),
		"planets": [2, 7],
	},
	{
		"name": "Crimson Drift",
		"image": "res://assets/backgrounds/bg_05.png",
		"top": Color(0.13, 0.03, 0.06),
		"bottom": Color(0.03, 0.01, 0.02),
		"accent": Color(1.0, 0.4, 0.5),
		"planets": [1, 9],
	},
	{
		"name": "Arctic Teal",
		"image": "res://assets/backgrounds/bg_06.png",
		"top": Color(0.04, 0.10, 0.12),
		"bottom": Color(0.01, 0.03, 0.04),
		"accent": Color(0.35, 0.85, 0.9),
		"planets": [0, 6],
	},
	{
		"name": "Dawn Blush",
		"image": "res://assets/backgrounds/bg_07.png",
		"top": Color(0.14, 0.06, 0.09),
		"bottom": Color(0.04, 0.02, 0.03),
		"accent": Color(1.0, 0.55, 0.65),
		"planets": [2, 4],
	},
	{
		"name": "Deep Galaxy",
		"image": "res://assets/backgrounds/bg_08.png",
		"top": Color(0.02, 0.04, 0.12),
		"bottom": Color(0.005, 0.01, 0.03),
		"accent": Color(0.45, 0.6, 1.0),
		"planets": [3, 7],
	},
	{
		"name": "Neon Skyline",
		"image": "res://assets/backgrounds/bg_09.png",
		"top": Color(0.10, 0.03, 0.12),
		"bottom": Color(0.02, 0.01, 0.03),
		"accent": Color(0.9, 0.4, 0.85),
		"planets": [5, 9],
	},
	{
		"name": "Golden Glow",
		"image": "res://assets/backgrounds/bg_10.png",
		"top": Color(0.14, 0.10, 0.03),
		"bottom": Color(0.04, 0.03, 0.01),
		"accent": Color(1.0, 0.8, 0.35),
		"planets": [0, 2],
	},
]

static func theme(i: int) -> Dictionary:
	return THEMES[((i % THEMES.size()) + THEMES.size()) % THEMES.size()]


static func current() -> Dictionary:
	return theme(current_index)


static func advance() -> Dictionary:
	current_index = (current_index + 1) % THEMES.size()
	return current()


## Builds a full backdrop (gradient + two planet sprites) as children of
## `parent`, using theme `i`. Returns every node it created so the caller
## can queue_free() them later when it's time to rotate to a new theme.
## `parent` must be a Control (or ColorRect/etc) already in the tree so
## get_viewport_rect() resolves correctly.
static func build(parent: Control, i: int, planet_alpha: float = 0.4) -> Array:
	var th := theme(i)
	var nodes: Array = []

	# Solid fallback color underneath (covers any edge/letterboxing while the
	# texture loads, and matches the art's own background tone).
	var backstop := ColorRect.new()
	backstop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backstop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backstop.color = th["bottom"]
	parent.add_child(backstop)
	parent.move_child(backstop, 0)
	nodes.append(backstop)

	# Static Type Blast background art, cover-fit (fills the rect, cropping
	# overflow) so it always fills the screen without distorting the art.
	var bg := TextureRect.new()
	bg.texture = load(th["image"])
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	parent.move_child(bg, 1)
	nodes.append(bg)

	# Faint accent-tinted planet sprites layered on top for a bit of extra
	# depth/parallax, kept subtle since the background art already carries
	# most of the visual interest.
	var vp: Vector2 = parent.get_viewport_rect().size
	var planet_ids: Array = th["planets"]
	var rel_positions := [Vector2(0.80, 0.16), Vector2(0.14, 0.80)]
	var rel_sizes := [0.40, 0.26]
	for idx in planet_ids.size():
		var pid = planet_ids[idx]
		var planet := TextureRect.new()
		planet.texture = load("res://assets/items/planets/planet0%d.png" % pid)
		planet.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		planet.modulate = Color(1, 1, 1, planet_alpha * 0.5)
		parent.add_child(planet)
		parent.move_child(planet, idx + 2)
		var size: float = minf(vp.x, vp.y) * rel_sizes[idx]
		planet.size = Vector2(size, size)
		var pos: Vector2 = rel_positions[idx]
		planet.position = Vector2(pos.x * vp.x - size / 2.0, pos.y * vp.y - size / 2.0)
		nodes.append(planet)

	return nodes


static func free_nodes(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
