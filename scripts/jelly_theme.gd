class_name JellyTheme
extends RefCounted

## Single source of truth for the game's UI skins (buttons, panels, icons).
##
## Before this file existed, 8 different screens each had their own copy of
## an `_asset_button_style()` function pointing at the old placeholder
## Kenney "sci-fi" button texture (assets/items/ui/button_rectangle.png),
## while only progress bars and list rows had been switched over to the
## jelly art. That's why the game looked like two different skins glued
## together. This file is the fix: one place that knows what the button/
## panel/icon textures are for every skin and how to slice them, so every
## screen renders the same button language.
##
## "arcade" pack (assets/ui/arcade/*) - buttons_red / buttons_orange /
## buttons_grey / buttons_blank / buttons_icon / windows. This is now the
## default skin. Buttons are colour-coded by action: grey = neutral/menu,
## orange = primary/confirm, red = danger/quit. Panels use the "windows"
## art in place of the flat near-black StyleBoxFlat cards every screen used
## to hand-roll on its own (that flat near-black box is the "default Godot
## panel" look this pack replaces).
##
## Screens should NOT load their own textures or build their own
## StyleBoxFlat "card" backgrounds any more - call button_style() /
## primary_button_style() / panel_style() / icon_rect() here instead, so
## a style switch (Settings > Interface) reskins the whole game at once.

## --- jelly pack (assets/ui/jelly/*) ------------------------------------
const BUTTON_NORMAL := "res://assets/ui/jelly/button_blank_wide_v2.png"
const BUTTON_PRIMARY := "res://assets/ui/jelly/button_ok_v2.png"
const BUTTON_PLAY := "res://assets/ui/jelly/button_play_v2.png"
const BUTTON_DANGER := "res://assets/ui/jelly/button_quit_red_v2.png"
const BUTTON_MENU := "res://assets/ui/jelly/button_menu_v2.png"

const PANEL_CARD := "res://assets/ui/jelly/panel_card_v2.png"
const PANEL_POPUP := "res://assets/ui/jelly/panel_popup_v2.png"
const PANEL_TALL := "res://assets/ui/jelly/panel_tall.png"
const PANEL_DARK_WIDE := "res://assets/ui/jelly/panel_dark_wide_v2.png"
const PANEL_DARK_WIDE_B := "res://assets/ui/jelly/panel_dark_wide_b.png"
const PANEL_LOGIN := "res://assets/ui/jelly/panel_login.png"
const PANEL_EXIT_BUBBLE := "res://assets/ui/jelly/panel_exit_bubble.png"

const PROGRESS_TRACK := "res://assets/ui/jelly/progress_track_v2.png"
const PROGRESS_FILL := "res://assets/ui/jelly/progress_fill_v2.png"
const LIST_ROW := "res://assets/ui/jelly/list_row_v2.png"
const LIST_ROW_LOCKED := "res://assets/ui/jelly/list_row_locked_v2.png"

const ICON_GEAR := "res://assets/ui/jelly/icon_gear.png"
const ICON_CLOSE := "res://assets/ui/jelly/icon_close_x.png"
const ICON_CLOSE_RED := "res://assets/ui/jelly/icon_close_red.png"
const ICON_CHECK := "res://assets/ui/jelly/icon_check.png"
const ICON_HEART_FULL := "res://assets/ui/jelly/icon_heart_red.png"
const ICON_HEART_EMPTY := "res://assets/ui/jelly/icon_heart_gray.png"
const ICON_PLAY := "res://assets/ui/jelly/icon_play.png"
const ICON_PAUSE := "res://assets/ui/jelly/icon_pause.png"
const ICON_STOP := "res://assets/ui/jelly/icon_stop.png"
const ICON_RESTART := "res://assets/ui/jelly/icon_restart.png"
const ICON_FASTFORWARD := "res://assets/ui/jelly/icon_fastforward.png"

## --- Per-style asset tables ---------------------------------------------
## Every screen looks assets up through here by semantic key (e.g.
## "danger", "card", "close_x") rather than a style-specific filename, so
## adding/repointing a skin is a one-place edit instead of a hunt through
## every screen script.
const STYLE_ASSETS := {
	"jelly": {
		"button_normal": BUTTON_NORMAL, "button_primary": BUTTON_PRIMARY,
		"button_play": BUTTON_PLAY, "button_danger": BUTTON_DANGER,
		"button_menu": BUTTON_MENU,
		"button_margin_h": 30, "button_margin_v": 16,
		"panel_card": PANEL_CARD, "panel_popup": PANEL_POPUP,
		"panel_tall": PANEL_TALL, "panel_dark_wide": PANEL_DARK_WIDE,
		"panel_dark_wide_b": PANEL_DARK_WIDE_B, "panel_login": PANEL_LOGIN,
		"panel_exit_bubble": PANEL_EXIT_BUBBLE,
		"panel_margin": 48,
		"progress_track": PROGRESS_TRACK, "progress_fill": PROGRESS_FILL,
		"list_row": LIST_ROW, "list_row_locked": LIST_ROW_LOCKED,
		"icon_gear": ICON_GEAR, "icon_close_x": ICON_CLOSE,
		"icon_close_red": ICON_CLOSE_RED, "icon_check": ICON_CHECK,
		"icon_heart_red": ICON_HEART_FULL, "icon_heart_gray": ICON_HEART_EMPTY,
		"icon_play": ICON_PLAY, "icon_pause": ICON_PAUSE,
		"icon_stop": ICON_STOP, "icon_restart": ICON_RESTART,
		"icon_fastforward": ICON_FASTFORWARD,
	},
	"arcade": {
		# Colour-coded by action: grey = neutral/menu, orange = primary/
		# confirm/play, red = danger/quit. Wide "_02" blanks are the plain
		# nine-sliceable buttons in the pack (the numbered button_NN_*.png
		# files are pre-baked with a printed number and aren't meant to be
		# stretched to fit arbitrary label text).
		"button_normal": "res://assets/ui/arcade/buttons_blank/button_blank_grey02.png",
		"button_primary": "res://assets/ui/arcade/buttons_blank/button_blank_orange02.png",
		"button_play": "res://assets/ui/arcade/buttons_blank/button_blank_orange02.png",
		"button_danger": "res://assets/ui/arcade/buttons_blank/button_blank_red02.png",
		"button_menu": "res://assets/ui/arcade/buttons_blank/button_blank_grey02.png",
		"button_margin_h": 16, "button_margin_v": 14,
		"panel_card": "res://assets/ui/arcade/windows/window_04.png",
		"panel_popup": "res://assets/ui/arcade/windows/window_01.png",
		"panel_tall": "res://assets/ui/arcade/windows/window_02.png",
		"panel_dark_wide": "res://assets/ui/arcade/windows/window_08.png",
		"panel_dark_wide_b": "res://assets/ui/arcade/windows/window_07.png",
		"panel_login": "res://assets/ui/arcade/windows/window_03.png",
		"panel_exit_bubble": "res://assets/ui/arcade/windows/window_13.png",
		"panel_margin": 42,
		# The pack has no dedicated progress-bar or list-row art, so those
		# keep borrowing the jelly textures rather than mis-using a button
		# or window graphic for a job it wasn't cut for.
		"progress_track": PROGRESS_TRACK, "progress_fill": PROGRESS_FILL,
		"list_row": LIST_ROW, "list_row_locked": LIST_ROW_LOCKED,
		"icon_gear": "res://assets/ui/arcade/buttons_icon/icon_02.png",
		"icon_close_x": "res://assets/ui/arcade/buttons_icon/icon_32.png",
		"icon_close_red": "res://assets/ui/arcade/buttons_icon/icon_32.png",
		"icon_check": "res://assets/ui/arcade/buttons_icon/icon_31.png",
		"icon_heart_red": "res://assets/ui/arcade/buttons_icon/icon_04.png",
		# No empty-heart art in the pack; keep the jelly grey heart for it.
		"icon_heart_gray": ICON_HEART_EMPTY,
		"icon_play": "res://assets/ui/arcade/buttons_icon/icon_39.png",
		"icon_pause": "res://assets/ui/arcade/buttons_icon/icon_40.png",
		"icon_stop": "res://assets/ui/arcade/buttons_icon/icon_41.png",
		"icon_restart": "res://assets/ui/arcade/buttons_icon/icon_26.png",
		"icon_fastforward": "res://assets/ui/arcade/buttons_icon/icon_43.png",
	},
}

const PANEL_MARGIN := 48 # fallback used by panel_style_from_path()

## --- Interface style switch -----------------------------------------
## "jelly"  = the SunGraphica texture kit (chunky, colorful, 3D-ish)
## "arcade" = buttons_red/orange/grey + windows pack - default skin
## "casual" = flat StyleBoxFlat/StyleBoxTexture-free look, no image assets
##            required at all - safe fallback if a style's assets ever go
##            missing.
## A simple static var rather than threading a style string through every
## caller (~50+ call sites across 9 screens) - same pattern this codebase
## already uses for BackgroundThemes.current_index. Set once at boot from
## GameState.ui_style (see GameState.load_save_data()) and again whenever
## the Settings panel changes it.
const STYLES := ["casual", "jelly", "arcade"]
const STYLE_LABELS := {"casual": "Casual", "jelly": "Jelly", "arcade": "Arcade"}
static var current_style := "arcade"

static func set_style(style: String) -> void:
	current_style = style if style in STYLES else "arcade"

## Flat-style palette - deliberately plain/neutral so any per-screen tint
## still reads clearly on top of it (buttons multiply this by the caller's
## tint the same way the textured styles do via modulate_color).
const CASUAL_BASE := Color(0.16, 0.17, 0.2, 1.0)
const CASUAL_BORDER := Color(1, 1, 1, 0.18)
const CASUAL_RADIUS := 14

## Unicode glyphs standing in for the icon PNGs in casual mode, so
## switching styles doesn't require a second imported icon set.
const CASUAL_GLYPHS := {
	"gear": "\u2699", "close_x": "\u2715", "close_red": "\u2715",
	"check": "\u2713", "heart_red": "\u2665", "heart_gray": "\u2661",
	"play": "\u25B6", "pause": "\u23F8", "stop": "\u23F9",
	"restart": "\u21BB", "fastforward": "\u23E9",
}


## Returns a StyleBoxTexture skinned with the current style's button art.
## - tint: the per-screen accent color the caller already uses for
##   color-coding (e.g. red for quit, gold for primary). Buttons are
##   pre-colored, so the tint is blended at partial strength instead of
##   multiplied at full strength - that keeps the art's look intact while
##   still letting color-coding read at a glance.
## - brightness: same 0.85 / 1.05 / 1.25-ish multiplier callers already use
##   for normal / hover / pressed states.
## - is_pressed: picks a brighter "punched in" texture instead of just
##   dimming/brightening the same flat art.
static func button_style(tint: Color = Color(1, 1, 1), brightness: float = 1.0, is_pressed: bool = false) -> StyleBox:
	if current_style == "casual":
		return _casual_button_style(tint, brightness)
	var assets: Dictionary = STYLE_ASSETS[current_style]
	var sb := StyleBoxTexture.new()
	# Hue-based, not "r > g" - gold/amber accents (used for achievements,
	# career, etc.) are also red-shifted but read as warm, not "danger".
	# Only genuine reds (hue ~0, i.e. g and b roughly equal and both well
	# below r) should map to the quit/danger texture.
	var is_danger := (tint.h < 0.04 or tint.h > 0.96) and tint.s > 0.3
	if is_danger:
		sb.texture = load(assets["button_danger"])
	elif is_pressed:
		sb.texture = load(assets["button_primary"])
	else:
		sb.texture = load(assets["button_normal"])
	sb.texture_margin_left = assets["button_margin_h"]
	sb.texture_margin_right = assets["button_margin_h"]
	sb.texture_margin_top = assets["button_margin_v"]
	sb.texture_margin_bottom = assets["button_margin_v"]
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	var blended := tint.lerp(Color(1, 1, 1), 0.55) * brightness
	sb.modulate_color = Color(blended.r, blended.g, blended.b, 1.0)
	return sb


## Flat, texture-free button: solid tinted panel, thin border, rounded
## corners. Same tint/brightness contract as the textured styles above, so
## every caller can switch styles without touching their own code.
static func _casual_button_style(tint: Color = Color(1, 1, 1), brightness: float = 1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var is_danger := (tint.h < 0.04 or tint.h > 0.96) and tint.s > 0.3
	var base_color = Color(0.75, 0.2, 0.2) if is_danger else tint
	var blended := base_color.lerp(CASUAL_BASE, 0.35) * Color(brightness, brightness, brightness, 1.0)
	sb.bg_color = Color(blended.r, blended.g, blended.b, 0.9)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = CASUAL_BORDER
	sb.set_corner_radius_all(CASUAL_RADIUS)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


## The single, unmistakable "go" action (Start Run, Play). Uses the bright
## primary texture at full saturation rather than the blended tint, so it
## reads as more important than every other button on screen.
static func primary_button_style(brightness: float = 1.0) -> StyleBox:
	if current_style == "casual":
		var sb := StyleBoxFlat.new()
		var g: float = clampf(0.7 * brightness, 0.0, 1.0)
		sb.bg_color = Color(g * 0.6, g, g * 0.55, 0.95)
		sb.border_width_left = 2
		sb.border_width_right = 2
		sb.border_width_top = 2
		sb.border_width_bottom = 2
		sb.border_color = Color(1, 1, 1, 0.25)
		sb.set_corner_radius_all(CASUAL_RADIUS)
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		return sb
	var assets: Dictionary = STYLE_ASSETS[current_style]
	var sb := StyleBoxTexture.new()
	sb.texture = load(assets["button_primary"])
	sb.texture_margin_left = assets["button_margin_h"]
	sb.texture_margin_right = assets["button_margin_h"]
	sb.texture_margin_top = assets["button_margin_v"]
	sb.texture_margin_bottom = assets["button_margin_v"]
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.modulate_color = Color(brightness, brightness, brightness, 1.0)
	return sb


## Panel/card background for a screen's main body. `kind` picks which
## panel art to use ("card", "popup", "tall", "dark_wide", "dark_wide_b",
## "login", "exit_bubble" - see STYLE_ASSETS keys above). In casual mode
## this returns the same flat near-black StyleBoxFlat every screen used to
## build by hand; in jelly/arcade mode it returns the matching texture,
## nine-sliced with that style's panel margin. This is the one function
## every screen's main card/popup background should go through instead of
## rolling its own StyleBoxFlat, so a style switch reskins every panel at
## once instead of leaving the old flat black box behind.
static func panel_style(kind: String = "card", margin: int = -1) -> StyleBox:
	if current_style == "casual":
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.065, 0.09, 0.96)
		sb.set_corner_radius_all(28)
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(1, 1, 1, 0.08)
		sb.shadow_size = 40
		sb.shadow_color = Color(0, 0, 0, 0.55)
		sb.content_margin_left = 28
		sb.content_margin_right = 28
		sb.content_margin_top = 22
		sb.content_margin_bottom = 22
		return sb
	var assets: Dictionary = STYLE_ASSETS[current_style]
	var key := "panel_" + kind
	var texture_path: String = assets.get(key, assets["panel_card"])
	var sb := StyleBoxTexture.new()
	sb.texture = load(texture_path)
	var m: int = margin if margin >= 0 else int(assets["panel_margin"])
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	return sb


## Legacy helper kept for any caller still passing a full texture path
## directly rather than a semantic panel kind.
static func panel_style_from_path(texture_path: String, margin: int = PANEL_MARGIN) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(texture_path)
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	return sb


## Small square icon on a transparent/tinted circular badge, matching the
## icon_badge pattern already used for mode buttons. `icon_key` is a
## semantic name ("gear", "close_x", "close_red", "check", "heart_red",
## "heart_gray", "play", "pause", "stop", "restart", "fastforward") looked
## up per-style, so the icon set follows the current skin automatically.
## In casual mode there's no icon image set to switch to, so this renders
## a centered Unicode glyph instead - same call signature, same layout
## footprint (custom_minimum_size), so every caller works unchanged.
static func icon_rect(icon_key: String, size: Vector2 = Vector2(26, 26)) -> Control:
	if current_style == "casual":
		var l := Label.new()
		l.text = CASUAL_GLYPHS.get(icon_key, "\u2022")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", int(size.y * 0.85))
		l.custom_minimum_size = size
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return l
	var assets: Dictionary = STYLE_ASSETS[current_style]
	var path: String = assets.get("icon_" + icon_key, "")
	var t := TextureRect.new()
	if path != "":
		t.texture = load(path)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Shared hover/press scale feedback so every button behaves the same way
## instead of each screen hand-rolling slightly different tween timings.
##
## Each interface style gets its own tactile identity rather than sharing
## one generic tween: the textured styles overshoot into a springy "squish"
## (bigger scale swing, BACK easing, a firmer haptic pulse) to match their
## chunky rounded art, while Casual stays crisp and minimal (smaller swing,
## plain easing, a light tap) to match its flat look. Callers don't need to
## know about this - same call signature either way, the style branch
## lives here.
static func wire_press_feedback(btn: Button, hover_scale: float = 1.03, press_scale: float = 0.96, duration: float = 0.1) -> void:
	var is_textured := current_style != "casual"
	# Widen the swing a bit around the caller's requested values instead of
	# ignoring them outright, so per-screen tuning still matters.
	var h_scale := hover_scale + 0.02 if is_textured else hover_scale
	var p_scale := press_scale - 0.03 if is_textured else press_scale
	var ease_type := Tween.EASE_OUT
	var trans_type := Tween.TRANS_BACK if is_textured else Tween.TRANS_SINE

	btn.pivot_offset = btn.size / 2.0
	btn.mouse_entered.connect(func():
		btn.pivot_offset = btn.size / 2.0
		btn.create_tween().set_ease(ease_type).set_trans(trans_type).tween_property(btn, "scale", Vector2(h_scale, h_scale), duration)
	)
	btn.mouse_exited.connect(func():
		btn.create_tween().set_ease(ease_type).set_trans(trans_type).tween_property(btn, "scale", Vector2(1.0, 1.0), duration)
	)
	btn.button_down.connect(func():
		btn.create_tween().set_ease(ease_type).set_trans(trans_type).tween_property(btn, "scale", Vector2(p_scale, p_scale), duration * 0.6)
		_haptic(18 if is_textured else 8)
	)
	btn.button_up.connect(func():
		btn.create_tween().set_ease(ease_type).set_trans(trans_type).tween_property(btn, "scale", Vector2(h_scale, h_scale), duration * 0.6)
	)

## Guarded haptic pulse - no-ops when there's no touchscreen (desktop/web),
## same guard MobileSupport.vibrate() uses. Kept local to JellyTheme so the
## button-feedback helper above doesn't need a MobileSupport reference
## threaded through every one of its ~50 call sites.
static func _haptic(duration_ms: int) -> void:
	if DisplayServer.is_touchscreen_available():
		Input.vibrate_handheld(duration_ms)


## --- Live theme switching support -------------------------------------

## Removes every child a screen's build function appended after
## `keep_count` (i.e. everything a prior call to that build function
## created), so it can safely be re-run when the interface style changes
## mid-session. `keep_count` should be captured right before the *first*
## build call, after any one-time housekeeping children (timers, shader
## scrims, etc.) added earlier in setup() - those are left alone.
static func trim_rebuildable_children(node: Node, keep_count: int) -> void:
	while node.get_child_count() > keep_count:
		var c := node.get_child(node.get_child_count() - 1)
		node.remove_child(c)
		c.queue_free()

## Small popped-in fade so a freshly-rebuilt screen doesn't just snap to
## the new skin - a quick, cheap "refresh" flourish shared by every screen
## that supports live style switching.
static func play_rebuild_transition(control: Control) -> void:
	control.modulate.a = 0.0
	control.scale = Vector2(0.97, 0.97)
	control.pivot_offset = control.size / 2.0
	var tw := control.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(control, "modulate:a", 1.0, 0.22)
	tw.tween_property(control, "scale", Vector2(1.0, 1.0), 0.22)

## Renders a small live sample of a given style's button, independent of
## whatever current_style currently is - used for the Settings screen's
## preview swatches so players can see every style before picking one.
static func preview_button_style(style: String, tint: Color = Color(1, 1, 1), brightness: float = 1.0) -> StyleBox:
	var saved := current_style
	current_style = style if style in STYLES else "arcade"
	var sb := button_style(tint, brightness)
	current_style = saved
	return sb


## Progress bar track (the dim background groove). dim ~= how much to
## darken the track texture; ignored in casual mode, which uses a flat
## translucent groove instead.
static func progress_track_style(dim: float = 0.45) -> StyleBox:
	if current_style == "casual":
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.08)
		sb.set_corner_radius_all(8)
		return sb
	var assets: Dictionary = STYLE_ASSETS[current_style]
	var sb := StyleBoxTexture.new()
	sb.texture = load(assets["progress_track"])
	sb.texture_margin_left = 14
	sb.texture_margin_right = 14
	sb.texture_margin_top = 6
	sb.texture_margin_bottom = 6
	sb.modulate_color = Color(dim, dim, dim, 1.0)
	return sb


## Progress bar fill, pre-tinted to `color`. Use set_fill_color() below to
## re-tint it later (e.g. a fill that shifts red -> gold as it progresses,
## or matches the level's current accent) - that's the piece that broke
## last time because StyleBoxFlat.bg_color and StyleBoxTexture.modulate_color
## aren't interchangeable, which this pair of functions is here to prevent
## happening again.
static func progress_fill_style(color: Color) -> StyleBox:
	if current_style == "casual":
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(8)
		return sb
	var assets: Dictionary = STYLE_ASSETS[current_style]
	var sb := StyleBoxTexture.new()
	sb.texture = load(assets["progress_fill"])
	sb.texture_margin_left = 14
	sb.texture_margin_right = 14
	sb.texture_margin_top = 6
	sb.texture_margin_bottom = 6
	sb.modulate_color = color
	return sb


## Re-tints a stylebox returned by progress_fill_style() (or any stylebox,
## really) regardless of whether it turned out to be a StyleBoxFlat or a
## StyleBoxTexture - the one place that needs to know the difference, so
## nowhere else has to.
static func set_fill_color(stylebox: StyleBox, color: Color) -> void:
	if stylebox is StyleBoxFlat:
		stylebox.bg_color = color
	elif stylebox is StyleBoxTexture:
		stylebox.modulate_color = color


## List row / pill background (achievement rows, the stats-screen grade
## badge). `locked` swaps in the dimmer art in textured modes, or just
## lowers alpha in casual mode since there's only one flat panel look.
static func list_row_style(locked: bool = false) -> StyleBox:
	if current_style == "casual":
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.05) if locked else Color(1, 1, 1, 0.09)
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_color = CASUAL_BORDER
		sb.set_corner_radius_all(CASUAL_RADIUS)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		return sb
	var assets: Dictionary = STYLE_ASSETS[current_style]
	var sb := StyleBoxTexture.new()
	sb.texture = load(assets["list_row_locked"] if locked else assets["list_row"])
	sb.texture_margin_left = 18
	sb.texture_margin_right = 18
	sb.texture_margin_top = 10
	sb.texture_margin_bottom = 10
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb
