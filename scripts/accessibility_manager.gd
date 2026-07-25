class_name AccessibilityManager
extends CanvasLayer

## Settings > Accessibility has two toggles that used to be saved to disk
## and do absolutely nothing visually: `high_contrast` and
## `colorblind_mode`. Rather than hand-edit the color constants in each of
## the ~12 screen scripts that define their own COL_RED / COL_MINT / etc.
## (risky to do blind, across a dozen files, with no editor to preview the
## result), both toggles are now applied globally from this one node:
##
## - High contrast: mutates the project's shared Theme resource at runtime
##   (assets/fonts/game_theme.tres, set in project.godot as the global
##   theme) so every Label/Button/etc. on every screen picks up a dark
##   text outline automatically — one edit, every screen, no per-file risk.
## - Colorblind palette: draws a full-screen shader filter above
##   everything else that nudges apart the specific hues each mode
##   confuses (red/green for deuteranopia + protanopia, blue/yellow for
##   tritanopia). This is a best-effort assist, not a clinically
##   validated correction — it won't fix every case, but it's a real,
##   live effect instead of a saved-but-ignored setting.
## - Font size: `font_scale` had the exact same problem — saved, shown on
##   a settings slider that nudged the live window scale while you dragged
##   it, but never re-applied on the NEXT launch, so it silently reverted
##   to 1.0 every time the app restarted. Setting Window.content_scale_factor
##   here on startup (and again through the same accessibility_changed
##   signal) makes it stick, project-wide, the same one-edit way as the
##   other two settings.
##
## Call `apply()` once at startup and again any time game_state's
## high_contrast / colorblind_mode / font_scale change (more_screen.gd's
## toggles call this through game_state.accessibility_changed).

const THEME_PATH := "res://assets/fonts/game_theme.tres"
const CB_MODES := ["off", "deuteranopia", "protanopia", "tritanopia"]

const SHADER_CODE := """
shader_type canvas_item;

uniform int cb_mode : hint_range(0, 3) = 0;
uniform float strength : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	vec4 c = texture(SCREEN_TEXTURE, SCREEN_UV);
	vec3 rgb = c.rgb;
	vec3 shifted = rgb;
	if (cb_mode == 1) {
		// Deuteranopia: red/green confusion. Separate green toward cyan.
		shifted.g = mix(rgb.g, rgb.b, 0.40);
		shifted.b = mix(rgb.b, rgb.g, 0.15);
	} else if (cb_mode == 2) {
		// Protanopia: red confusion. Push red toward orange/yellow.
		shifted.r = mix(rgb.r, rgb.g, 0.30);
	} else if (cb_mode == 3) {
		// Tritanopia: blue/yellow confusion. Separate blue from green.
		shifted.b = mix(rgb.b, rgb.r, 0.30);
		shifted.g = mix(rgb.g, rgb.r, 0.10);
	}
	float amount = strength * float(cb_mode != 0);
	c.rgb = clamp(mix(rgb, shifted, amount), 0.0, 1.0);
	COLOR = c;
}
"""

var _game_state: GameState
var _theme: Theme
var _filter_rect: ColorRect
var _shader_material: ShaderMaterial

# Control types that actually render text in this project's screens.
const TEXT_TYPES := ["Label", "Button", "RichTextLabel", "CheckButton", "OptionButton", "LineEdit"]

func setup(game_state: GameState) -> void:
	_game_state = game_state
	layer = 100 # above every other screen/CanvasLayer so the filter always covers everything
	_load_theme()
	_build_filter_rect()
	_game_state.accessibility_changed.connect(apply)
	apply()

func _load_theme() -> void:
	if not ResourceLoader.exists(THEME_PATH):
		return
	_theme = load(THEME_PATH)

func _build_filter_rect() -> void:
	_filter_rect = ColorRect.new()
	_filter_rect.color = Color(0, 0, 0, 0) # fully transparent; the shader reads the screen behind it
	_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader
	_filter_rect.material = _shader_material
	add_child(_filter_rect)

## Re-applies both settings from game_state. Safe to call as often as
## needed (e.g. every time a toggle changes) — it's idempotent.
func apply() -> void:
	if _game_state == null:
		return
	_apply_high_contrast(_game_state.high_contrast)
	_apply_colorblind_mode(_game_state.colorblind_mode)
	_apply_font_scale(_game_state.font_scale)
	_apply_dyslexia_spacing(_game_state.dyslexia_spacing)
	_apply_hd_graphics(_game_state.hd_graphics_enabled)

## Settings > HD Graphics — a real (not just saved-and-ignored) quality
## toggle: turns 2D anti-aliasing on/off. This is the one quality knob a
## flat 2D game like this actually has; on lower-end devices, disabling
## it (and the colorblind shader pass, which reads the full screen
## texture) is a genuine performance win, same spirit as reduced_motion.
func _apply_hd_graphics(on: bool) -> void:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return
	var root := (loop as SceneTree).root
	if root == null:
		return
	root.msaa_2d = Viewport.MSAA_4X if on else Viewport.MSAA_DISABLED

## Uniformly rescales the whole window's render resolution, which is the
## only way to affect font sizes set via per-label
## add_theme_font_size_override() calls (the shared Theme resource can't
## touch those — instance overrides always win over Theme values, which is
## exactly why high-contrast above targets font_outline_color instead).
## Clamped defensively in case a corrupt save ever stores something wild.
func _apply_font_scale(scale: float) -> void:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return
	var win := (loop as SceneTree).root
	if win == null:
		return
	win.content_scale_factor = clamp(scale, 0.7, 2.0)

func _apply_high_contrast(on: bool) -> void:
	if _theme == null:
		return
	for control_type in TEXT_TYPES:
		if on:
			_theme.set_color("font_outline_color", control_type, Color(0, 0, 0, 0.9))
			_theme.set_constant("outline_size", control_type, 3)
		else:
			_theme.clear_color("font_outline_color", control_type)
			_theme.clear_constant("outline_size", control_type)

func _apply_colorblind_mode(mode: String) -> void:
	if _shader_material == null:
		return
	var idx := CB_MODES.find(mode)
	if idx < 0:
		idx = 0
	_shader_material.set_shader_parameter("cb_mode", idx)
	_shader_material.set_shader_parameter("strength", 0.6)

## Dyslexia-friendly approximation: widens letter and word spacing project-wide
## via the same shared Theme resource high-contrast already uses, so every
## screen picks it up without per-file edits. Not a substitute for a real
## dyslexia-friendly typeface (none is bundled with this project), but wider
## glyph/word spacing is one of the two changes (along with larger size,
## already covered by the font-scale slider) most commonly recommended.
func _apply_dyslexia_spacing(on: bool) -> void:
	if _theme == null:
		return
	for control_type in TEXT_TYPES:
		if on:
			_theme.set_constant("font_spacing_glyph", control_type, 3)
			_theme.set_constant("font_spacing_space", control_type, 6)
		else:
			_theme.clear_constant("font_spacing_glyph", control_type)
			_theme.clear_constant("font_spacing_space", control_type)
