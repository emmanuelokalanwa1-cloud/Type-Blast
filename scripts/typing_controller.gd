class_name MobileSupport
extends Node

## Centralizes everything the game needs to behave well on a phone/tablet
## instead of "the desktop build happens to also run on Android":
##
##  1. Detects touch/mobile at runtime (is_touch) so callers can branch.
##  2. Detects current orientation (is_portrait) and reports changes, instead
##     of forcing the device into one orientation — some players will hold
##     it sideways and the game shouldn't fight them.
##  3. Routes the Android hardware Back button to pause instead of doing
##     nothing (default) or fighting with ui_cancel.
##  4. Auto-pauses when the app loses focus (phone call, app switch, screen
##     lock) and reports when it regains focus, so the timer/spawns don't
##     silently burn through while the player isn't looking.
##  5. Centralizes on-screen keyboard show/hide so it's called from exactly
##     one place instead of scattered DisplayServer calls.
##  6. Provides safe-area insets (notches / punch-holes / gesture bars) and a
##     helper to nudge top-anchored HUD elements clear of them — computed
##     fresh each time, so it's correct in either orientation.
##  7. A guarded haptic-feedback wrapper (no-ops on desktop).
##
## Nothing here assumes a specific scene layout — it's handed nodes/values
## by main.gd rather than reaching into $Paths itself, so it can't break if
## the scene tree changes shape.

signal back_pressed        # Android/back gesture, only when nothing else claimed it
signal app_focus_lost      # OS took focus away (call, switch, lock)
signal app_focus_regained
signal viewport_resized     # canvas size changed (e.g. mobile browser keyboard opening)
signal orientation_changed(is_portrait: bool)  # device was rotated

var is_touch := false
var is_web := false
var is_portrait := true
var _keyboard_visible := false

func _ready() -> void:
	is_touch = DisplayServer.is_touchscreen_available()
	is_web = OS.has_feature("web")
	is_portrait = _compute_is_portrait()

	# Locked to portrait: the game's UI is laid out for a portrait canvas
	# (720x1280). Free rotation used to be allowed here, but that let the
	# same portrait layout get stretched into a landscape frame whenever a
	# player tilted their phone or had landscape as their default, breaking
	# the HUD and falling-word layout. Keep-awake is unrelated to
	# orientation and still applies.
	if not is_web:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
		DisplayServer.screen_set_keep_on(true)

	get_viewport().size_changed.connect(_on_resized)

func _on_resized() -> void:
	viewport_resized.emit()
	var now_portrait := _compute_is_portrait()
	if now_portrait != is_portrait:
		is_portrait = now_portrait
		orientation_changed.emit(is_portrait)

func _compute_is_portrait() -> bool:
	var size := get_viewport().get_visible_rect().size
	return size.y >= size.x

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			back_pressed.emit()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			app_focus_lost.emit()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			app_focus_regained.emit()

## --- On-screen keyboard -----------------------------------------------
## Always route through here (instead of calling DisplayServer directly)
## so keyboard state can't drift out of sync with what's on screen.
func show_keyboard(existing_text: String = "") -> void:
	if not is_touch or _keyboard_visible:
		return
	DisplayServer.virtual_keyboard_show(existing_text)
	_keyboard_visible = true

func hide_keyboard() -> void:
	if not is_touch:
		return
	if _keyboard_visible:
		DisplayServer.virtual_keyboard_hide()
		_keyboard_visible = false

## --- Safe area -----------------------------------------------------------
## Returns how many project-space pixels are unsafe on each edge (notches,
## camera cutouts, gesture bars), scaled from screen space into the game's
## stretched canvas space so callers can just add these to their offsets.
func get_safe_area_insets() -> Dictionary:
	var empty := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if not is_touch:
		return empty

	var screen_size := DisplayServer.screen_get_size()
	var safe_area := DisplayServer.get_display_safe_area()
	if screen_size.x <= 0 or screen_size.y <= 0:
		return empty

	var canvas_size := get_viewport().get_visible_rect().size
	var scale_x := canvas_size.x / float(screen_size.x)
	var scale_y := canvas_size.y / float(screen_size.y)

	return {
		"left": safe_area.position.x * scale_x,
		"top": safe_area.position.y * scale_y,
		"right": (screen_size.x - (safe_area.position.x + safe_area.size.x)) * scale_x,
		"bottom": (screen_size.y - (safe_area.position.y + safe_area.size.y)) * scale_y,
	}

## Nudges a list of top-anchored Controls down by the top safe-area inset
## (e.g. a camera cutout eating into the status bar) so nothing gets
## clipped behind it. Safe to call on desktop — it's a no-op there.
func apply_safe_area_top(nodes: Array) -> void:
	var insets := get_safe_area_insets()
	if insets.top <= 0.0:
		return
	for n in nodes:
		if is_instance_valid(n):
			n.position.y += insets.top

## --- Haptics ---------------------------------------------------------
func vibrate(duration_ms: int = 20) -> void:
	if is_touch:
		Input.vibrate_handheld(duration_ms)
