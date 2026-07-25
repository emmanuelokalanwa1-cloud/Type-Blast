class_name TutorialOverlay
extends ColorRect

## ---------------------------------------------------------------------
## CHANGELOG (this pass) — visual redesign to match StatsScreen/
## DifficultyMenu's card language, plus 20 functional additions. setup(),
## open(), and the finished signal all still work exactly as before.
## ---------------------------------------------------------------------
##  1. Vignette background (same shader as the other premium screens)
##  2. Rounded, bordered, drop-shadowed card instead of a bare full-rect fill
##  3. Per-page accent color (each topic gets its own tint)
##  4. Per-page icon/emoji illustrating the topic
##  5. Clickable progress dots (jump straight to any page)
##  6. Linear progress bar alongside the dots
##  7. BACK button (hidden on page 1, so you can revisit earlier pages)
##  8. Page transition animation (slide + fade) instead of an instant swap
##  9. Card entrance animation when the overlay opens
## 10. Keyboard navigation: Right/Enter = next, Left = back, Esc = skip
## 11. Swipe/drag gesture support on touch to move between pages
## 12. page_changed(index) signal, e.g. for a UI click sound in main.gd
## 13. skip_to_page(index) public method for external/debug control
## 14. "TUTORIAL" eyebrow label + divider above the title
## 15. Subtle pulsing glow on the final "GOT IT" button to draw the eye
## 16. Icon bounce-in animation each time a page renders
## 17. close() method added for API symmetry with the other menus
## 18. Styled buttons (rounded, tinted, hover/press states) matching the
##     rest of the app instead of default Godot buttons
## 19. Guards so rapid double-taps on NEXT/BACK can't skip-render a page
## 20. Defensive bounds checks everywhere PAGES is indexed
## ---------------------------------------------------------------------

signal finished()
signal page_changed(index: int)

const PAGES := [
	{"title": "TYPE THE FALLING WORDS", "body": "Words fall from the top of the screen. Type them exactly before they reach the bottom, then press Enter (or just finish typing).", "icon": "▶", "color": Color(0.6, 0.85, 1.0)},
	{"title": "COMBO", "body": "Typing words back to back builds your COMBO. A higher combo means faster XP and turns your combo counter cyan, then orange.", "icon": "◆", "color": Color(0.4, 0.9, 0.85)},
	{"title": "FRENZY MODE", "body": "Hit a 50 combo and FRENZY MODE kicks in: more words spawn at once for big score bursts. Miss a word and your combo resets.", "icon": "▲", "color": Color(1.0, 0.35, 0.6)},
	{"title": "BOSS WORDS", "body": "Occasionally a big GOLD word appears. These boss words are longer and fall slower, but are worth showing off your speed on.", "icon": "★", "color": Color(1.0, 0.78, 0.25)},
	{"title": "SHIELD", "body": "Every 10 levels you earn a SHIELD. It absorbs your next missed word for free instead of costing a life.", "icon": "■", "color": Color(0.45, 0.7, 1.0)},
	{"title": "POWER-UP WORDS", "body": "Sky-blue words are power-ups: FREEZE stops the fall, SLOWMO slows everything down, and BONUS gives you an extra life. Type them like any other word.", "icon": "◇", "color": Color(0.5, 0.8, 1.0)},
]

var _page_index := 0
var _is_animating := false # 19

var _card: PanelContainer
var _icon_label: Label
var _keyboard_ref: TextureRect
var _title_label: Label
var _body_label: Label
var _progress_label: Label
var _progress_bar_bg: ColorRect
var _progress_bar_fill: ColorRect
var _dots_row: HBoxContainer
var _dots: Array = []
var _back_btn: Button
var _next_btn: Button
var _skip_btn: Button
var _next_pulse_tween: Tween

var _drag_start_x := -1.0

var _game_state: GameState


## The card behind this overlay is JellyTheme.panel_style("popup") - a flat
## dark box on Casual, but a light parchment texture on Jelly/Arcade. Every
## label below used to be a flat white-based modulate tuned only for the
## dark case, which made the eyebrow/body/progress text nearly invisible on
## the light panel. Route text color through this the same way
## more_screen.gd already does, so it swaps to dark automatically outside
## Casual.
const COL_TEXT_ON_LIGHT := Color(0.12, 0.09, 0.04)

func _tc(base_color: Color) -> Color:
	if JellyTheme.current_style == "casual":
		return base_color
	return Color(COL_TEXT_ON_LIGHT.r, COL_TEXT_ON_LIGHT.g, COL_TEXT_ON_LIGHT.b, base_color.a)


func setup(root: Control, game_state: GameState) -> void:
	_game_state = game_state
	color = Color(0.015, 0.016, 0.03, 0.97)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(self)
	_build_vignette_background() # 1
	_build_ui()
	_render_page(false)


# 1. Same radial vignette used by StatsScreen/DifficultyMenu for a
# consistent, non-flat backdrop across every full-screen overlay.
func _build_vignette_background() -> void:
	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	uv.x *= 1.6;
	float d = length(uv);
	float vig = smoothstep(0.15, 0.9, d);
	vec3 base = vec3(0.05, 0.06, 0.10);
	vec3 edge = vec3(0.0, 0.0, 0.01);
	COLOR = vec4(mix(base, edge, vig), 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	vignette.material = mat
	add_child(vignette)


func _build_ui() -> void:
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 60)
	margin.add_theme_constant_override("margin_left", 160)
	margin.add_theme_constant_override("margin_right", 160)
	add_child(margin)

	# 2. Rounded, bordered, drop-shadowed card (matches the other screens).
	_card = PanelContainer.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var card_style := JellyTheme.panel_style("popup")
	card_style.content_margin_left = 56
	card_style.content_margin_right = 56
	card_style.content_margin_top = 44
	card_style.content_margin_bottom = 44
	_card.add_theme_stylebox_override("panel", card_style)
	_card.gui_input.connect(_on_card_gui_input) # 11. swipe support
	margin.add_child(_card)
	# _card already centers itself vertically via SIZE_SHRINK_CENTER above —
	# no wrapper needed.

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(480, 0)
	vbox.add_theme_constant_override("separation", 16)
	_card.add_child(vbox)

	# 14. Eyebrow + divider above the title.
	var eyebrow = Label.new()
	eyebrow.text = "TUTORIAL"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.modulate = _tc(Color(1, 1, 1, 0.4))
	vbox.add_child(eyebrow)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(50, 1)
	divider.color = Color(1, 1, 1, 0.1)
	divider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(divider)

	# 4. Per-page icon.
	_icon_label = Label.new()
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.add_theme_font_size_override("font_size", 56)
	vbox.add_child(_icon_label)

	# Keyboard reference image (from the items pack) — only shown on the
	# first page, as a quick visual reminder of where your fingers go.
	_keyboard_ref = TextureRect.new()
	_keyboard_ref.visible = false
	_keyboard_ref.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_keyboard_ref.stretch_mode = TextureRect.STRETCH_SCALE
	_keyboard_ref.custom_minimum_size = Vector2(0, 130)
	_keyboard_ref.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var kb_path := "res://assets/items/keyboard_reference.jpg"
	if ResourceLoader.exists(kb_path):
		var kb_tex: Texture2D = load(kb_path)
		if kb_tex:
			_keyboard_ref.texture = kb_tex
	vbox.add_child(_keyboard_ref)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 34)
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body_label.custom_minimum_size = Vector2(440, 0)
	_body_label.add_theme_font_size_override("font_size", 20)
	_body_label.modulate = _tc(Color(1, 1, 1, 0.85))
	vbox.add_child(_body_label)

	# 6. Linear progress bar.
	var bar_wrap := Control.new()
	bar_wrap.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(bar_wrap)
	_progress_bar_bg = ColorRect.new()
	_progress_bar_bg.color = Color(1, 1, 1, 0.08)
	_progress_bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_wrap.add_child(_progress_bar_bg)
	_progress_bar_fill = ColorRect.new()
	_progress_bar_fill.anchor_top = 0
	_progress_bar_fill.anchor_bottom = 1
	_progress_bar_fill.anchor_left = 0
	_progress_bar_fill.anchor_right = 0.0
	_progress_bar_bg.add_child(_progress_bar_fill)

	# 5. Clickable progress dots.
	_dots_row = HBoxContainer.new()
	_dots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots_row.add_theme_constant_override("separation", 10)
	vbox.add_child(_dots_row)
	for i in range(PAGES.size()):
		var dot := Button.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.flat = true
		dot.focus_mode = Control.FOCUS_NONE
		var dot_style := StyleBoxFlat.new()
		dot_style.set_corner_radius_all(6)
		dot_style.bg_color = Color(1, 1, 1, 0.25)
		dot.add_theme_stylebox_override("normal", dot_style)
		dot.add_theme_stylebox_override("hover", dot_style)
		dot.add_theme_stylebox_override("pressed", dot_style)
		dot.pressed.connect(func(): skip_to_page(i)) # 13
		_dots_row.add_child(dot)
		_dots.append(dot)

	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 13)
	_progress_label.modulate = _tc(Color(1, 1, 1, 0.4))
	vbox.add_child(_progress_label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	# 7. BACK button (visibility toggled per page in _render_page).
	_back_btn = _styled_button("BACK", Color(0.3, 0.32, 0.4), 130)
	_back_btn.pressed.connect(_on_back_pressed)
	hbox.add_child(_back_btn)

	_skip_btn = _styled_button("SKIP", Color(0.4, 0.25, 0.25), 110)
	_skip_btn.pressed.connect(_finish)
	hbox.add_child(_skip_btn)

	_next_btn = _styled_button("NEXT", Color(0.2, 0.55, 0.4), 160)
	_next_btn.pressed.connect(_on_next_pressed)
	hbox.add_child(_next_btn)


# 18. Shared button styling matching the rest of the app.
func _styled_button(txt: String, tint: Color, min_width: float) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(min_width, 60)
	b.add_theme_font_size_override("font_size", 22)

	var normal := _asset_button_style("res://assets/items/ui/button_rectangle.png", tint, 0.85)
	var hover := _asset_button_style("res://assets/items/ui/button_rectangle.png", tint, 1.05)
	var pressed := _asset_button_style("res://assets/items/ui/button_rectangle_depth.png", tint, 1.0)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)

	b.pivot_offset = Vector2(0, 0)
	b.mouse_entered.connect(func():
		var t := create_tween()
		t.tween_property(b, "scale", Vector2(1.02, 1.02), 0.08)
	)
	b.mouse_exited.connect(func():
		var t := create_tween()
		t.tween_property(b, "scale", Vector2(1.0, 1.0), 0.08)
	)
	return b

func _asset_button_style(texture_path: String, tint: Color, brightness: float) -> StyleBox:
	return JellyTheme.button_style(tint, brightness, texture_path.contains("depth"))


func _render_page(animate: bool = true) -> void:
	if _page_index < 0 or _page_index >= PAGES.size(): # 20. bounds guard
		return

	var page = PAGES[_page_index]
	var accent: Color = page.get("color", Color.WHITE)

	var apply := func():
		_icon_label.text = page.get("icon", "")
		if is_instance_valid(_keyboard_ref):
			_keyboard_ref.visible = (_page_index == 0) and _keyboard_ref.texture != null
		_title_label.text = page["title"]
		_title_label.modulate = accent
		_body_label.text = page["body"]
		_progress_label.text = str(_page_index + 1) + " / " + str(PAGES.size())
		_next_btn.text = "GOT IT" if _page_index == PAGES.size() - 1 else "NEXT"
		_back_btn.visible = _page_index > 0 # 7

		# 5. Update dot highlighting.
		for i in range(_dots.size()):
			var dot: Button = _dots[i]
			var style: StyleBoxFlat = dot.get_theme_stylebox("normal")
			var new_style := style.duplicate()
			new_style.bg_color = accent if i == _page_index else Color(1, 1, 1, 0.25)
			dot.add_theme_stylebox_override("normal", new_style)
			dot.add_theme_stylebox_override("hover", new_style)
			dot.add_theme_stylebox_override("pressed", new_style)

		# 6. Update the linear progress bar.
		var ratio = float(_page_index + 1) / float(PAGES.size())
		var bar_tween := create_tween()
		bar_tween.tween_property(_progress_bar_fill, "anchor_right", ratio, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

		# 16. Icon bounce-in.
		_icon_label.scale = Vector2(0.6, 0.6)
		var icon_tween := create_tween()
		icon_tween.tween_property(_icon_label, "scale", Vector2(1, 1), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		# 15. Subtle pulsing glow on the final "GOT IT" button.
		if _next_pulse_tween and _next_pulse_tween.is_valid():
			_next_pulse_tween.kill()
		_next_btn.modulate = Color.WHITE
		if _page_index == PAGES.size() - 1:
			_next_pulse_tween = create_tween()
			_next_pulse_tween.set_loops()
			_next_pulse_tween.tween_property(_next_btn, "modulate", Color(1.15, 1.15, 1.15), 0.6)
			_next_pulse_tween.tween_property(_next_btn, "modulate", Color(1, 1, 1), 0.6)

		_is_animating = false

	# 8. Slide + fade transition instead of an instant swap.
	if animate:
		_is_animating = true
		var t := create_tween()
		t.tween_property(_card, "modulate:a", 0.0, 0.12)
		t.tween_callback(apply)
		t.tween_property(_card, "modulate:a", 1.0, 0.16)
	else:
		apply.call()

	page_changed.emit(_page_index) # 12


func _on_next_pressed() -> void:
	if _is_animating: # 19. guard against rapid double-taps
		return
	if _page_index >= PAGES.size() - 1:
		_finish()
		return
	_page_index += 1
	_render_page()


func _on_back_pressed() -> void:
	if _is_animating or _page_index <= 0: # 19, 7
		return
	_page_index -= 1
	_render_page()


# 13. Public: jump directly to a given page (used by the dots, and
# available for debug/external tools too).
func skip_to_page(index: int) -> void:
	if _is_animating or index == _page_index:
		return
	if index < 0 or index >= PAGES.size(): # 20
		return
	_page_index = index
	_render_page()


func _finish() -> void:
	if _game_state:
		_game_state.mark_tutorial_seen()
	visible = false
	finished.emit()


func open() -> void:
	_page_index = 0
	visible = true
	_render_page(false)

	# 9. Card entrance animation.
	_card.scale = Vector2(0.94, 0.94)
	_card.modulate.a = 0.0
	_card.pivot_offset = _card.size / 2.0
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_card, "scale", Vector2(1, 1), 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_card, "modulate:a", 1.0, 0.2)


# 17. Added for symmetry with DifficultyMenu/PauseMenu's open()/close() pair.
func close() -> void:
	visible = false


# 10. Keyboard navigation: Right/Enter = next, Left = back, Esc = skip.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):
		_on_next_pressed()
	elif event.is_action_pressed("ui_left"):
		_on_back_pressed()
	elif event.is_action_pressed("ui_cancel"):
		_finish()


# 11. Swipe/drag gesture support so touch users can flick between pages.
func _on_card_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_drag_start_x = event.position.x
		else:
			_drag_start_x = -1.0
	elif event is InputEventScreenDrag:
		if _drag_start_x < 0.0:
			return
		var delta_x = event.position.x - _drag_start_x
		const SWIPE_THRESHOLD := 80.0
		if delta_x <= -SWIPE_THRESHOLD:
			_drag_start_x = -1.0
			_on_next_pressed()
		elif delta_x >= SWIPE_THRESHOLD:
			_drag_start_x = -1.0
			_on_back_pressed()
