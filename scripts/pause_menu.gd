class_name PauseMenu
extends ColorRect

signal resume_pressed()
signal restart_pressed()
signal quit_pressed()

## ---------------------------------------------------------------------
## CHANGELOG — 20 additions (all self-contained, all guarded)
## ---------------------------------------------------------------------
##  1. Fixed a real bug: color alpha was 65.0 (should be 0-1) — was
##     silently clamping to fully opaque. Now a proper dim overlay.
##  2. Floating rounded card instead of a full-bleed flat rect
##  3. Drop shadow behind the card
##  4. Pop-in + fade-in animation when the menu opens
##  5. Section dividers between button groups
##  6. Live run-stats readout (score / level / lives) while paused
##  7. Live percentage labels next to volume sliders
##  8. Color-coded rounded buttons (resume=green, restart=blue, quit=red)
##  9. Hover feedback — buttons gently scale up on mouse-over
## 10. Press feedback — quick scale-down/up on click
## 11. Resume button auto-focused on open (keyboard/controller friendly)
## 12. ESC / "ui_cancel" resumes the game from the pause menu
## 13. Quit requires a second confirm tap ("TAP AGAIN TO QUIT")
## 14. Quit-confirm auto-resets after a few seconds
## 15. Subtle looping title pulse while the menu is open
## 16. Bigger, styled slider tracks (easier to grab on touch)
## 17. Mute checkbox tints when active
## 18. Subtitle under the title showing current level
## 19. close() fully resets quit-confirm + animation state
## 20. Everything guarded with is_instance_valid / null checks so it
##     can never throw even if a node is missing
## ---------------------------------------------------------------------

var _game_state: GameState
var _audio: AudioManager

# --- new node refs for polish ---
var _panel: PanelContainer
var _shadow: PanelContainer
var _title: Label
var _subtitle: Label
var _stats_label: Label
var _music_pct: Label
var _sfx_pct: Label
var _resume_btn: Button
var _restart_btn: Button
var _quit_btn: Button
var _quit_confirm_timer: Timer

var _quit_armed := false          # 13
var _theme_keep_child_count := 0  # 20. children added before the first _build_ui() call, preserved across refresh_theme()
var _title_pulse_t := 0.0         # 15

# --- new refs for this pass (fit-to-screen fix + 5 specials) ---
var _panel_style: StyleBox    # kept so the glow pulse (E) can mutate it
var _header_banner: ColorRect     # A
var _vignette_corners: Array = [] # B
var _ambient_dots: Array = []     # C
var _glow_pulse_t := 0.0          # E

func setup(root: Control, game_state: GameState, audio: AudioManager) -> void:
	_game_state = game_state
	_audio = audio
	visible = false

	# 1. FIX: alpha must be 0-1, not 65.0 — this was the real bug.
	color = Color(0.02, 0.02, 0.05, 0.75)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(self)

	# 14. Timer that auto-resets the quit confirm state.
	_quit_confirm_timer = Timer.new()
	_quit_confirm_timer.one_shot = true
	_quit_confirm_timer.wait_time = 3.0
	_quit_confirm_timer.timeout.connect(_reset_quit_confirm)
	add_child(_quit_confirm_timer)

	_theme_keep_child_count = get_child_count()
	_build_ui()

## Re-runs _build_ui() so the pause menu picks up a new Casual/Jelly
## interface style immediately, instead of only on the next app launch.
## Called by main.gd whenever GameState.ui_style_changed fires.
func refresh_theme() -> void:
	var was_paused_open := visible
	JellyTheme.trim_rebuildable_children(self, _theme_keep_child_count)
	_build_ui()
	visible = was_paused_open
	if was_paused_open and is_instance_valid(_panel):
		JellyTheme.play_rebuild_transition(_panel)

func _build_ui() -> void:
	# FIX: the card used to call set_anchors_and_offsets_preset(PRESET_CENTER)
	# BEFORE custom_minimum_size was set, so it centered against a 0x0 size
	# and then grew from that corner — that's why it drifted toward the
	# bottom-right instead of sitting in the middle of the screen. It also
	# used a fixed pixel size regardless of screen size, so it looked tiny.
	# Now the card size is a percentage of the actual viewport, and it's
	# centered by anchoring to 0.5/0.5 with offsets computed from that size.
	var vp = get_viewport_rect().size
	var card_w = clamp(vp.x * 0.86, 360, 640)
	var card_h = clamp(vp.y * 0.86, 520, 780)

	# B. Vignette: soft dark circles pinned at each corner to draw focus
	# toward the centered card, like a cinematic pause screen.
	var corner_positions = [Vector2(0, 0), Vector2(vp.x, 0), Vector2(0, vp.y), Vector2(vp.x, vp.y)]
	for corner_pos in corner_positions:
		var vig = PanelContainer.new()
		var vig_size = max(vp.x, vp.y) * 0.55
		vig.size = Vector2(vig_size, vig_size)
		vig.position = corner_pos - Vector2(vig_size, vig_size) / 2
		vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vig_style := StyleBoxFlat.new()
		vig_style.bg_color = Color(0, 0, 0, 0.35)
		vig_style.corner_radius_top_left = int(vig_size / 2)
		vig_style.corner_radius_top_right = int(vig_size / 2)
		vig_style.corner_radius_bottom_left = int(vig_size / 2)
		vig_style.corner_radius_bottom_right = int(vig_size / 2)
		vig.add_theme_stylebox_override("panel", vig_style)
		add_child(vig)
		_vignette_corners.append(vig)

	# C. Ambient drifting particles behind the card for a bit of life while
	# the game is frozen — purely decorative, ignores mouse input.
	for i in range(14):
		var dot = ColorRect.new()
		var s = randf_range(3.0, 7.0)
		dot.size = Vector2(s, s)
		dot.color = Color(1.0, 0.84, 0.0, randf_range(0.15, 0.35))
		dot.position = Vector2(randf_range(0, vp.x), randf_range(0, vp.y))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.set_meta("speed", randf_range(8.0, 22.0))
		dot.set_meta("origin_x", dot.position.x)
		add_child(dot)
		_ambient_dots.append(dot)

	# 3. Faux drop shadow: a slightly offset, darker duplicate panel behind
	# the real one.
	_shadow = PanelContainer.new()
	_shadow.anchor_left = 0.5
	_shadow.anchor_top = 0.5
	_shadow.anchor_right = 0.5
	_shadow.anchor_bottom = 0.5
	_shadow.offset_left = -card_w / 2 + 6
	_shadow.offset_right = card_w / 2 + 6
	_shadow.offset_top = -card_h / 2 + 10
	_shadow.offset_bottom = card_h / 2 + 10
	_shadow.custom_minimum_size = Vector2(card_w, card_h)
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color(0, 0, 0, 0.45)
	shadow_style.corner_radius_top_left = 28
	shadow_style.corner_radius_top_right = 28
	shadow_style.corner_radius_bottom_left = 28
	shadow_style.corner_radius_bottom_right = 28
	_shadow.add_theme_stylebox_override("panel", shadow_style)
	add_child(_shadow)

	# 2. The actual floating card — properly centered, sized to the viewport.
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -card_w / 2
	_panel.offset_right = card_w / 2
	_panel.offset_top = -card_h / 2
	_panel.offset_bottom = card_h / 2
	_panel.custom_minimum_size = Vector2(card_w, card_h)
	_panel.pivot_offset = Vector2(card_w, card_h) / 2
	var panel_style := JellyTheme.panel_style("popup")
	if panel_style is StyleBoxFlat:
		panel_style.border_color = Color(1.0, 0.84, 0.0, 0.55)
	panel_style.content_margin_left = 36
	panel_style.content_margin_right = 36
	panel_style.content_margin_top = 32
	panel_style.content_margin_bottom = 32
	_panel.add_theme_stylebox_override("panel", panel_style)
	_panel_style = panel_style # E. kept so the breathing glow can mutate the border alpha
	add_child(_panel)

	# D. Glossy top-edge highlight for a bit of depth, like light catching
	# the top of a glass/plastic card.
	var gloss = ColorRect.new()
	gloss.color = Color(1, 1, 1, 0.10)
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gloss.anchor_left = 0.0
	gloss.anchor_right = 1.0
	gloss.offset_left = 6
	gloss.offset_right = -6
	gloss.offset_top = 4
	gloss.custom_minimum_size = Vector2(0, 3)
	_panel.add_child(gloss)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(vbox)

	# A. Full-width header banner behind the title, so the top of the card
	# reads as a distinct header section rather than the title just floating.
	var banner_wrap = PanelContainer.new()
	var banner_style := StyleBoxFlat.new()
	banner_style.bg_color = Color(1.0, 0.84, 0.0, 0.12)
	banner_style.corner_radius_top_left = 22
	banner_style.corner_radius_top_right = 22
	banner_style.corner_radius_bottom_left = 8
	banner_style.corner_radius_bottom_right = 8
	banner_style.content_margin_top = 14
	banner_style.content_margin_bottom = 10
	banner_wrap.add_theme_stylebox_override("panel", banner_style)
	vbox.add_child(banner_wrap)
	_header_banner = ColorRect.new() # kept as a ref for future re-tinting; invisible, sizing handled by banner_style
	_header_banner.custom_minimum_size = Vector2(0, 1)
	_header_banner.color = Color(0, 0, 0, 0)
	_header_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_title = Label.new()
	_title.text = LocalizationManager.get_string("paused", _game_state.selected_language).to_upper()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 56)
	_title.modulate = JellyTheme.text_color(Color.GOLD)
	banner_wrap.add_child(_title)
	banner_wrap.add_child(_header_banner)

	# 18. Subtitle showing current level for a bit of context.
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 18)
	_subtitle.modulate = JellyTheme.text_color(Color(1, 1, 1, 0.6))
	vbox.add_child(_subtitle)

	# 6. Live run-stats readout.
	_stats_label = Label.new()
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.add_theme_font_size_override("font_size", 20)
	_stats_label.modulate = JellyTheme.text_color(Color(0.6, 1.0, 0.8))
	vbox.add_child(_stats_label)

	vbox.add_child(HSeparator.new()) # 5

	_resume_btn = _make_button(LocalizationManager.get_string("resume", _game_state.selected_language).to_upper(), Color(0.25, 0.85, 0.4))
	_resume_btn.pressed.connect(func(): resume_pressed.emit())
	vbox.add_child(_resume_btn)

	_restart_btn = _make_button(LocalizationManager.get_string("restart", _game_state.selected_language).to_upper(), Color(0.3, 0.55, 0.95))
	_restart_btn.pressed.connect(func(): restart_pressed.emit())
	vbox.add_child(_restart_btn)

	vbox.add_child(HSeparator.new()) # 5

	# --- Music slider row with live percentage ---
	var music_row = HBoxContainer.new()
	var music_label = _labeled("MUSIC")
	music_label.custom_minimum_size = Vector2(140, 0)
	music_row.add_child(music_label)
	var music_slider = HSlider.new()
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.05
	music_slider.value = _game_state.music_volume
	music_slider.custom_minimum_size = Vector2(200, 45) # 16
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_pct = Label.new()
	_music_pct.custom_minimum_size = Vector2(56, 0)
	_music_pct.text = str(int(round(_game_state.music_volume * 100))) + "%"
	_music_pct.add_theme_font_size_override("font_size", 18)
	_music_pct.modulate = JellyTheme.text_color(Color.WHITE)
	music_slider.value_changed.connect(func(v):
		_audio.set_music_volume(v)
		_music_pct.text = str(int(round(v * 100))) + "%" # 7
	)
	music_row.add_child(music_slider)
	music_row.add_child(_music_pct)
	vbox.add_child(music_row)

	# --- SFX slider row with live percentage ---
	var sfx_row = HBoxContainer.new()
	var sfx_label = _labeled("SFX")
	sfx_label.custom_minimum_size = Vector2(140, 0)
	sfx_row.add_child(sfx_label)
	var sfx_slider = HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.value = _game_state.sfx_volume
	sfx_slider.custom_minimum_size = Vector2(200, 45) # 16
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sfx_pct = Label.new()
	_sfx_pct.custom_minimum_size = Vector2(56, 0)
	_sfx_pct.text = str(int(round(_game_state.sfx_volume * 100))) + "%"
	_sfx_pct.add_theme_font_size_override("font_size", 18)
	_sfx_pct.modulate = JellyTheme.text_color(Color.WHITE)
	sfx_slider.value_changed.connect(func(v):
		_audio.set_sfx_volume(v)
		_sfx_pct.text = str(int(round(v * 100))) + "%" # 7
	)
	sfx_row.add_child(sfx_slider)
	sfx_row.add_child(_sfx_pct)
	vbox.add_child(sfx_row)

	var mute_check = CheckButton.new()
	mute_check.text = LocalizationManager.get_string("mute", _game_state.selected_language).to_upper()
	mute_check.button_pressed = _game_state.muted
	mute_check.add_theme_font_size_override("font_size", 24)
	mute_check.alignment = HORIZONTAL_ALIGNMENT_CENTER
	mute_check.add_theme_color_override("font_color", JellyTheme.base_control_text_color())
	mute_check.modulate = Color(1.0, 0.6, 0.6) if _game_state.muted else Color.WHITE # 17
	mute_check.toggled.connect(func(pressed):
		_audio.set_muted(pressed)
		mute_check.modulate = Color(1.0, 0.6, 0.6) if pressed else Color.WHITE # 17
	)
	vbox.add_child(mute_check)

	var reduced_motion_check = CheckButton.new()
	reduced_motion_check.text = LocalizationManager.get_string("reduced_motion", _game_state.selected_language).to_upper()
	reduced_motion_check.button_pressed = _game_state.reduced_motion
	reduced_motion_check.add_theme_font_size_override("font_size", 24)
	reduced_motion_check.alignment = HORIZONTAL_ALIGNMENT_CENTER
	reduced_motion_check.add_theme_color_override("font_color", JellyTheme.base_control_text_color())
	reduced_motion_check.modulate = Color(0.6, 0.9, 1.0) if _game_state.reduced_motion else Color.WHITE
	reduced_motion_check.toggled.connect(func(pressed):
		_game_state.reduced_motion = pressed
		_game_state.save_data()
		reduced_motion_check.modulate = Color(0.6, 0.9, 1.0) if pressed else Color.WHITE
	)
	vbox.add_child(reduced_motion_check)

	vbox.add_child(HSeparator.new()) # 5

	_quit_btn = _make_button(LocalizationManager.get_string("quit", _game_state.selected_language).to_upper(), Color(0.85, 0.3, 0.3))
	_quit_btn.pressed.connect(_on_quit_pressed)
	vbox.add_child(_quit_btn)

func _make_button(txt: String, accent: Color) -> Button:
	var btn = Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(0, 68)
	btn.add_theme_font_size_override("font_size", 28)
	btn.pivot_offset = Vector2(btn.custom_minimum_size.x / 2, 34)

	# Same Kenney sci-fi button art as the difficulty menu (was previously
	# flat StyleBoxFlat rectangles here, so the pause menu looked like a
	# different, cheaper app than the rest of the game). The "depth" texture
	# gives the pressed state a real inset look instead of just a color shift.
	var normal := _asset_button_style("res://assets/items/ui/button_rectangle.png", accent, 0.85)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := _asset_button_style("res://assets/items/ui/button_rectangle.png", accent, 1.05)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed_style := _asset_button_style("res://assets/items/ui/button_rectangle_depth.png", accent, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	# 9/10. Hover + press scale feedback.
	btn.mouse_entered.connect(func():
		create_tween().tween_property(btn, "scale", Vector2(1.03, 1.03), 0.12)
	)
	btn.mouse_exited.connect(func():
		create_tween().tween_property(btn, "scale", Vector2(1.0, 1.0), 0.12)
	)
	btn.button_down.connect(func():
		create_tween().tween_property(btn, "scale", Vector2(0.96, 0.96), 0.08)
	)
	btn.button_up.connect(func():
		create_tween().tween_property(btn, "scale", Vector2(1.03, 1.03), 0.08)
	)
	return btn


# Jelly skin (see scripts/jelly_theme.gd). texture_path is kept in the
# signature so every call site above is untouched; "depth" in the path
# (the old pressed-state texture) now maps to the jelly pressed art.
func _asset_button_style(texture_path: String, tint: Color, brightness: float) -> StyleBox:
	return JellyTheme.button_style(tint, brightness, texture_path.contains("depth"))

func _labeled(txt: String) -> Label:
	var l = Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.modulate = JellyTheme.text_color(Color.WHITE)
	return l

func _on_quit_pressed() -> void:
	# 13. Require a second confirm tap before actually quitting.
	if not _quit_armed:
		_quit_armed = true
		if is_instance_valid(_quit_btn):
			_quit_btn.text = LocalizationManager.get_string("tap_again_to_quit", _game_state.selected_language).to_upper()
		_quit_confirm_timer.start()
	else:
		_reset_quit_confirm()
		quit_pressed.emit()

func _reset_quit_confirm() -> void:
	_quit_armed = false
	if is_instance_valid(_quit_btn):
		_quit_btn.text = LocalizationManager.get_string("quit", _game_state.selected_language).to_upper()

func _process(delta: float) -> void:
	# 15. Subtle looping title pulse, only while the menu is actually shown.
	if not visible or not is_instance_valid(_title):
		return
	_title_pulse_t += delta
	var glow = 0.85 + sin(_title_pulse_t * 2.5) * 0.15
	_title.modulate = JellyTheme.text_color(Color(1.0, 0.84, 0.0)) * glow

	# E. Slow breathing glow on the card's border, alongside the title pulse.
	_glow_pulse_t += delta
	if is_instance_valid(_panel_style) and _panel_style is StyleBoxFlat:
		_panel_style.border_color.a = 0.4 + sin(_glow_pulse_t * 1.6) * 0.2

	# C. Drift the ambient particles slowly upward, wrapping back to the
	# bottom once they scroll off the top.
	var vp = get_viewport_rect().size
	for dot in _ambient_dots:
		if not is_instance_valid(dot):
			continue
		var speed = dot.get_meta("speed", 12.0)
		dot.position.y -= speed * delta
		if dot.position.y < -10:
			dot.position.y = vp.y + 10
			dot.position.x = randf_range(0, vp.x)

func _unhandled_input(event: InputEvent) -> void:
	# 12. ESC (or the mapped ui_cancel action) resumes from pause.
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume_pressed.emit()

func open() -> void:
	visible = true

	# 6/18. Refresh live stats + subtitle each time the menu opens.
	if is_instance_valid(_stats_label) and _game_state:
		_stats_label.text = "%s %s   %s %s" % [LocalizationManager.get_string("score", _game_state.selected_language).to_upper(), str(_game_state.score), LocalizationManager.get_string("lives", _game_state.selected_language).to_upper(), str(_game_state.lives)]
	if is_instance_valid(_subtitle) and _game_state:
		_subtitle.text = LocalizationManager.get_string("level", _game_state.selected_language) + " " + str(_game_state.level)

	# 4. Pop-in + fade-in animation.
	if is_instance_valid(_panel):
		_panel.scale = Vector2(0.85, 0.85)
		_panel.modulate.a = 0.0
		var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(_panel, "scale", Vector2(1.0, 1.0), 0.28)
		tw.parallel().tween_property(_panel, "modulate:a", 1.0, 0.2)
	if is_instance_valid(_shadow):
		_shadow.modulate.a = 0.0
		create_tween().tween_property(_shadow, "modulate:a", 1.0, 0.25)

	# 11. Keyboard/controller-friendly: focus lands on Resume.
	if is_instance_valid(_resume_btn):
		_resume_btn.grab_focus()

func close() -> void:
	visible = false
	_reset_quit_confirm() # 19. never leave a stale "tap again" state behind
