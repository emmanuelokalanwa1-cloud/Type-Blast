class_name StatsScreen
extends Node

signal restart_pressed()
signal menu_pressed()
signal quit_pressed()

var _game_state: GameState
var _audio: AudioManager

var result_panel: ColorRect
var final_score_label: Label
var coin_label: Label
var _stats_label: Label
var _missed_label: Label

# --- new refs needed for animation / dynamic styling ---
var _card: PanelContainer
var _accent_bar: ColorRect
var _subtitle_label: Label
var _grade_label: Label
var _new_best_label: Label
var _acc_bar_bg: ColorRect
var _acc_bar_fill: ColorRect
var _acc_pct_label: Label
var _chips_row: HBoxContainer
var _music_pct_label: Label
var _sfx_pct_label: Label
var _hint_label: Label
var _corner_tl: Control
var _corner_br: Control
var _last_result_was_win := false  # so refresh_theme() can restore the right screen after a rebuild

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_RED := Color(0.95, 0.28, 0.28)
const COL_GREEN := Color(0.35, 0.85, 0.5)
const COL_MUTE := Color(1, 1, 1, 0.45)


func setup(result_panel_: ColorRect, final_score_label_: Label, coin_label_: Label, game_state: GameState, audio: AudioManager) -> void:
	result_panel = result_panel_
	final_score_label = final_score_label_
	coin_label = coin_label_
	_game_state = game_state
	_audio = audio

	result_panel.top_level = true
	result_panel.anchors_preset = Control.PRESET_FULL_RECT
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	# 1. Deep near-black base instead of flat gray-black
	result_panel.color = Color(0.015, 0.016, 0.03, 1.0)
	result_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	if final_score_label: final_score_label.visible = false
	if coin_label: coin_label.visible = false

	for child in result_panel.get_children():
		# final_score_label and coin_label are long-lived references held by
		# main.gd and re-passed into setup() on every refresh_theme() call
		# (e.g. when switching Casual/Jelly interface style). Freeing them
		# here would leave those references pointing at freed objects and
		# crash the next setup() call with an "previously freed" type error.
		if child == final_score_label or child == coin_label:
			child.visible = false
			continue
		result_panel.remove_child(child)
		child.queue_free()

	BackgroundThemes.advance()
	BackgroundThemes.build(result_panel, BackgroundThemes.current_index, 0.42)
	_build_vignette_background()
	_build_aaa_layout()


# 2. Radial vignette so the background isn't a dead flat color
func _build_vignette_background() -> void:
	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.color = Color(0, 0, 0, 0)

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
	result_panel.add_child(vignette)


func _build_aaa_layout() -> void:
	var main_margin = MarginContainer.new()
	main_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_margin.grow_horizontal = Control.GROW_DIRECTION_BOTH
	main_margin.grow_vertical = Control.GROW_DIRECTION_BOTH
	main_margin.mouse_filter = Control.MOUSE_FILTER_STOP
	main_margin.add_theme_constant_override("margin_top", 60)
	main_margin.add_theme_constant_override("margin_bottom", 60)
	main_margin.add_theme_constant_override("margin_left", 100)
	main_margin.add_theme_constant_override("margin_right", 100)
	result_panel.add_child(main_margin)

	# 3. Outer "card" wrapper with rounded corners, border glow & drop shadow
	_card = PanelContainer.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card_style := JellyTheme.panel_style("card")
	card_style.content_margin_left = 48
	card_style.content_margin_right = 48
	card_style.content_margin_top = 40
	card_style.content_margin_bottom = 40
	_card.add_theme_stylebox_override("panel", card_style)
	main_margin.add_child(_card)

	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 20)
	_card.add_child(card_vbox)

	# 4. Top accent bar — colored strip that reflects win/loss state
	_accent_bar = ColorRect.new()
	_accent_bar.custom_minimum_size = Vector2(0, 5)
	_accent_bar.color = COL_RED
	card_vbox.add_child(_accent_bar)

	var h_split = HBoxContainer.new()
	h_split.add_theme_constant_override("separation", 70)
	h_split.alignment = BoxContainer.ALIGNMENT_CENTER
	h_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_vbox.add_child(h_split)

	# ---------------- LEFT COLUMN ----------------
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	left_vbox.add_theme_constant_override("separation", 20)
	h_split.add_child(left_vbox)

	final_score_label = Label.new()
	final_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_score_label.add_theme_font_size_override("font_size", 72)
	left_vbox.add_child(final_score_label)

	# 5. Subtitle tagline under the headline
	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 16)
	_subtitle_label.modulate = COL_MUTE
	left_vbox.add_child(_subtitle_label)

	# 6. Grade badge (S/A/B/C/D) as a small pill
	var grade_wrap := PanelContainer.new()
	var grade_style := JellyTheme.list_row_style()
	grade_wrap.add_theme_stylebox_override("panel", grade_style)
	_grade_label = Label.new()
	_grade_label.add_theme_font_size_override("font_size", 18)
	_grade_label.add_theme_color_override("font_color", Color(0.06, 0.18, 0.08, 1.0))
	_grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grade_wrap.add_child(_grade_label)
	left_vbox.add_child(grade_wrap)

	# 7. Inner glass stat panel (distinct depth layer from outer card)
	var panel_bg = PanelContainer.new()
	var stat_style := StyleBoxFlat.new()
	stat_style.bg_color = Color(1, 1, 1, 0.035)
	stat_style.set_corner_radius_all(18)
	stat_style.border_width_left = 1
	stat_style.border_width_right = 1
	stat_style.border_width_top = 1
	stat_style.border_width_bottom = 1
	stat_style.border_color = Color(1, 1, 1, 0.07)
	stat_style.content_margin_left = 28
	stat_style.content_margin_right = 28
	stat_style.content_margin_top = 22
	stat_style.content_margin_bottom = 22
	panel_bg.add_theme_stylebox_override("panel", stat_style)
	left_vbox.add_child(panel_bg)

	var stats_vbox = VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 10)
	panel_bg.add_child(stats_vbox)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 26)
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_vbox.add_child(_stats_label)

	# 8. Divider line between the numeric stats and the accuracy gauge
	var divider1 := ColorRect.new()
	divider1.custom_minimum_size = Vector2(0, 1)
	divider1.color = Color(1, 1, 1, 0.08)
	stats_vbox.add_child(divider1)

	# 9. Animated accuracy gauge (color-coded fill bar with % label)
	var acc_row := HBoxContainer.new()
	acc_row.add_theme_constant_override("separation", 10)
	stats_vbox.add_child(acc_row)

	var acc_track_wrap := Control.new()
	acc_track_wrap.custom_minimum_size = Vector2(0, 14)
	acc_track_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acc_row.add_child(acc_track_wrap)

	_acc_bar_bg = ColorRect.new()
	_acc_bar_bg.color = Color(1, 1, 1, 0.08)
	_acc_bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	acc_track_wrap.add_child(_acc_bar_bg)

	_acc_bar_fill = ColorRect.new()
	_acc_bar_fill.color = COL_GREEN
	_acc_bar_fill.anchor_top = 0
	_acc_bar_fill.anchor_bottom = 1
	_acc_bar_fill.anchor_left = 0
	_acc_bar_fill.anchor_right = 0.0
	_acc_bar_bg.add_child(_acc_bar_fill)

	_acc_pct_label = Label.new()
	_acc_pct_label.add_theme_font_size_override("font_size", 16)
	acc_row.add_child(_acc_pct_label)

	# 10. "PERFORMANCE REVIEW" eyebrow + divider, plus mistake "chips"
	var review_vbox = VBoxContainer.new()
	review_vbox.add_theme_constant_override("separation", 8)
	left_vbox.add_child(review_vbox)

	var review_title = Label.new()
	review_title.text = LocalizationManager.get_string("performance_review", _game_state.selected_language).to_upper()
	review_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	review_title.add_theme_font_size_override("font_size", 15)
	review_title.modulate = COL_MUTE
	review_vbox.add_child(review_title)

	var divider2 := ColorRect.new()
	divider2.custom_minimum_size = Vector2(60, 1)
	divider2.color = Color(1, 1, 1, 0.1)
	divider2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	review_vbox.add_child(divider2)

	_missed_label = Label.new()
	_missed_label.visible = false # replaced by chip row below; kept for API compatibility
	review_vbox.add_child(_missed_label)

	_chips_row = HBoxContainer.new()
	_chips_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips_row.add_theme_constant_override("separation", 8)
	review_vbox.add_child(_chips_row)

	# ---------------- RIGHT COLUMN ----------------
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	right_vbox.add_theme_constant_override("separation", 18)
	h_split.add_child(right_vbox)

	var settings_title = Label.new()
	settings_title.text = LocalizationManager.get_string("quick_config", _game_state.selected_language).to_upper()
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title.add_theme_font_size_override("font_size", 24)
	settings_title.modulate = COL_GOLD
	right_vbox.add_child(settings_title)

	var divider3 := ColorRect.new()
	divider3.custom_minimum_size = Vector2(60, 1)
	divider3.color = Color(1, 1, 1, 0.1)
	divider3.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right_vbox.add_child(divider3)

	# 11. Music slider + live % readout
	var music_row = _labeled_row(LocalizationManager.get_string("music_volume", _game_state.selected_language).to_upper())
	right_vbox.add_child(music_row)
	var music_slider = _styled_slider()
	music_slider.value = _game_state.music_volume
	_music_pct_label = _pct_label(music_slider.value)
	var music_line := HBoxContainer.new()
	music_line.add_theme_constant_override("separation", 10)
	music_line.add_child(music_slider)
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_line.add_child(_music_pct_label)
	right_vbox.add_child(music_line)
	music_slider.value_changed.connect(func(v):
		_audio.set_music_volume(v)
		_music_pct_label.text = "%d%%" % int(round(v * 100))
	)

	# 12. SFX slider + live % readout
	var sfx_row = _labeled_row(LocalizationManager.get_string("sfx_volume", _game_state.selected_language).to_upper())
	right_vbox.add_child(sfx_row)
	var sfx_slider = _styled_slider()
	sfx_slider.value = _game_state.sfx_volume
	_sfx_pct_label = _pct_label(sfx_slider.value)
	var sfx_line := HBoxContainer.new()
	sfx_line.add_theme_constant_override("separation", 10)
	sfx_line.add_child(sfx_slider)
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_line.add_child(_sfx_pct_label)
	right_vbox.add_child(sfx_line)
	sfx_slider.value_changed.connect(func(v):
		_audio.set_sfx_volume(v)
		_sfx_pct_label.text = "%d%%" % int(round(v * 100))
	)

	var mute_check = CheckButton.new()
	mute_check.text = LocalizationManager.get_string("mute_audio", _game_state.selected_language).to_upper()
	mute_check.button_pressed = _game_state.muted
	mute_check.add_theme_font_size_override("font_size", 18)
	mute_check.alignment = HORIZONTAL_ALIGNMENT_CENTER
	mute_check.toggled.connect(func(pressed): _audio.set_muted(pressed))
	right_vbox.add_child(mute_check)

	var action_vbox = VBoxContainer.new()
	action_vbox.add_theme_constant_override("separation", 14)
	right_vbox.add_child(action_vbox)

	# 13-15. Buttons: rounded stylebox, hover glow tween, press punch tween
	var restart_btn = _styled_button(LocalizationManager.get_string("play_again", _game_state.selected_language).to_upper(), Color(0.20, 0.55, 0.35))
	restart_btn.pressed.connect(func():
		result_panel.visible = false
		restart_pressed.emit()
	)
	action_vbox.add_child(restart_btn)

	var menu_btn = _styled_button(LocalizationManager.get_string("main_menu", _game_state.selected_language).to_upper(), Color(0.25, 0.3, 0.4))
	menu_btn.pressed.connect(func():
		result_panel.visible = false
		menu_pressed.emit()
	)
	action_vbox.add_child(menu_btn)

	var quit_btn = _styled_button(LocalizationManager.get_string("quit_game", _game_state.selected_language).to_upper(), Color(0.5, 0.2, 0.2))
	quit_btn.pressed.connect(func(): quit_pressed.emit())
	action_vbox.add_child(quit_btn)

	# 16. Footer keyboard-shortcut hint
	_hint_label = Label.new()
	_hint_label.text = LocalizationManager.get_string("hint_play_again_menu", _game_state.selected_language)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.modulate = Color(1, 1, 1, 0.3)
	card_vbox.add_child(_hint_label)

	# 19. Post-run "fortune cookie" — a small random motivational line pulled
	# from QuotesManager (already used for the menu's quote-of-the-day, never
	# shown here before). Pure surprise/delight, no gameplay effect.
	var fortune_label := Label.new()
	fortune_label.text = "\u2728 " + QuotesManager.random_quote() + " \u2728"
	fortune_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fortune_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	fortune_label.add_theme_font_size_override("font_size", 13)
	fortune_label.modulate = Color(1.0, 0.85, 0.4, 0.0)
	card_vbox.add_child(fortune_label)
	var fortune_tween := create_tween()
	fortune_tween.tween_interval(0.4)
	fortune_tween.tween_property(fortune_label, "modulate:a", 0.85, 0.6)

	# Arcade-announcer flourish #4: a very rare (~1 in 40) hidden mascot
	# cameo peeking from the corner with a wink and a one-liner - a nod to
	# the classic hidden "surprise cameo" gag, no violence involved.
	if randf() < 0.025:
		var mascot_label := Label.new()
		mascot_label.text = "👀 psst... nice typing!"
		mascot_label.add_theme_font_size_override("font_size", 12)
		mascot_label.modulate = Color(1, 1, 1, 0.0)
		mascot_label.z_index = 5
		_card.add_child(mascot_label)
		mascot_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		mascot_label.position -= Vector2(mascot_label.size.x + 14, 26)
		var mascot_tw := create_tween()
		mascot_tw.tween_interval(0.9)
		mascot_tw.tween_property(mascot_label, "modulate:a", 0.9, 0.3)
		mascot_tw.tween_interval(1.6)
		mascot_tw.tween_property(mascot_label, "modulate:a", 0.0, 0.4)

	# 17-18. Corner accent decorations (small L-shaped brackets, premium touch)
	_corner_tl = _make_corner_bracket(false)
	_card.add_child(_corner_tl)
	_corner_br = _make_corner_bracket(true)
	_card.add_child(_corner_br)


func _labeled_row(txt: String) -> Label:
	return _sub_labeled(txt)


func _pct_label(v: float) -> Label:
	var l := Label.new()
	l.text = "%d%%" % int(round(v * 100))
	l.add_theme_font_size_override("font_size", 15)
	l.custom_minimum_size = Vector2(42, 0)
	l.modulate = COL_MUTE
	return l


func _styled_slider() -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(0, 36)
	return s


# 19. Buttons now use the same Kenney sci-fi button art as the difficulty
# menu and pause menu (was a flat StyleBoxFlat here, so the game-over screen
# — the moment most likely to make a first impression — looked the least
# finished of the three). Depth texture gives a real pressed-in look.
func _styled_button(txt: String, tint: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(0, 62)
	b.add_theme_font_size_override("font_size", 24)

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
	b.button_down.connect(func():
		var t := create_tween()
		t.tween_property(b, "scale", Vector2(0.97, 0.97), 0.05)
	)
	b.button_up.connect(func():
		var t := create_tween()
		t.tween_property(b, "scale", Vector2(1.02, 1.02), 0.05)
	)
	return b


func _asset_button_style(texture_path: String, tint: Color, brightness: float) -> StyleBox:
	return JellyTheme.button_style(tint, brightness, texture_path.contains("depth"))


func _make_corner_bracket(flip: bool) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(26, 26)
	c.size = Vector2(26, 26)
	if flip:
		c.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		c.position -= Vector2(26, 26)
	else:
		c.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		c.position += Vector2(14, 14)

	var h := ColorRect.new()
	h.color = Color(1, 1, 1, 0.25)
	h.size = Vector2(16, 2)
	if flip: h.position = Vector2(10, 24)
	c.add_child(h)

	var v := ColorRect.new()
	v.color = Color(1, 1, 1, 0.25)
	v.size = Vector2(2, 16)
	if flip: v.position = Vector2(24, 10)
	c.add_child(v)
	return c


func show_game_over() -> void:
	_last_result_was_win = false
	var gs = _game_state
	final_score_label.text = LocalizationManager.get_string("run_failed", _game_state.selected_language).to_upper()
	final_score_label.modulate = COL_RED
	_subtitle_label.text = "%s: %d" % [LocalizationManager.get_string("score", _game_state.selected_language).to_upper(), gs.score]
	_accent_bar.color = COL_RED
	_render_stats(gs.get_wpm(), gs.get_accuracy())
	result_panel.visible = true
	_play_entrance()


func show_win() -> void:
	_last_result_was_win = true
	var gs = _game_state
	final_score_label.text = LocalizationManager.get_string("run_complete", _game_state.selected_language).to_upper()
	final_score_label.modulate = COL_GOLD
	_subtitle_label.text = "%s: %d" % [LocalizationManager.get_string("score", _game_state.selected_language).to_upper(), gs.score]
	_accent_bar.color = COL_GOLD
	_render_stats(gs.get_wpm(), gs.get_accuracy())
	result_panel.visible = true
	_play_entrance()


## Re-runs setup() (which already fully rebuilds result_panel's children)
## so the game-over/win screen picks up a new Casual/Jelly interface style
## immediately. If it's on screen right now, restores the same win/loss
## content it was already showing instead of leaving it blank.
func refresh_theme() -> void:
	var was_open := result_panel.visible
	setup(result_panel, final_score_label, coin_label, _game_state, _audio)
	if was_open:
		if _last_result_was_win:
			show_win()
		else:
			show_game_over()
		if is_instance_valid(_card):
			JellyTheme.play_rebuild_transition(_card)


# 20. Entrance animation: card scales up + fades in instead of popping instantly
func _play_entrance() -> void:
	_card.scale = Vector2(0.92, 0.92)
	_card.modulate.a = 0.0
	_card.pivot_offset = _card.size / 2.0
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_card, "scale", Vector2(1, 1), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_card, "modulate:a", 1.0, 0.22)


func _render_stats(wpm: float, acc: float) -> void:
	var gs = _game_state
	var is_new_best = wpm >= gs.best_wpm - 0.01 and wpm > 0

	# Arcade-announcer flourish #3: a bold "FLAWLESS!" slam-in when a run
	# ends with perfect accuracy (distinct from the speed-based "new best"
	# label below - this one's about not missing a single word).
	if acc >= 99.99 and wpm > 0:
		var flawless_label := Label.new()
		flawless_label.text = "🔥 FLAWLESS! 🔥"
		flawless_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		flawless_label.add_theme_font_size_override("font_size", 22)
		flawless_label.modulate = Color(1.0, 0.35, 0.15, 0.0)
		flawless_label.scale = Vector2(1.4, 1.4)
		flawless_label.pivot_offset = Vector2(flawless_label.size.x / 2.0, flawless_label.size.y / 2.0)
		_card.add_child(flawless_label)
		var flawless_tw := create_tween()
		flawless_tw.tween_interval(0.15)
		flawless_tw.tween_property(flawless_label, "modulate:a", 1.0, 0.2)
		flawless_tw.parallel().tween_property(flawless_label, "scale", Vector2(1, 1), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_stats_label.text = (LocalizationManager.get_string("speed_wpm_stat", _game_state.selected_language) + "\n\n" + LocalizationManager.get_string("best_speed_wpm_stat", _game_state.selected_language)) % [
		int(round(wpm)),
		int(round(gs.best_wpm))
	]

	# 21. Grade badge computed from accuracy + wpm
	var grade := "D"
	var grade_color := COL_RED
	if acc >= 97 and wpm >= 40:
		grade = "S"; grade_color = COL_GOLD
	elif acc >= 90 and wpm >= 25:
		grade = "A"; grade_color = COL_GREEN
	elif acc >= 75:
		grade = "B"; grade_color = Color(0.4, 0.7, 0.9)
	elif acc >= 50:
		grade = "C"; grade_color = Color(0.85, 0.7, 0.3)
	_grade_label.text = "%s  %s" % [LocalizationManager.get_string("rank_label", _game_state.selected_language).to_upper(), grade]
	_grade_label.modulate = grade_color

	if is_new_best and wpm > 0:
		if not _new_best_label:
			_new_best_label = Label.new()
			_new_best_label.add_theme_font_size_override("font_size", 16)
			_new_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_stats_label.get_parent().add_child(_new_best_label)
		_new_best_label.text = LocalizationManager.get_string("new_best", _game_state.selected_language).to_upper()
		_new_best_label.modulate = COL_GOLD
		_new_best_label.visible = true
		# 22. Pulsing glow loop on the new-best tag
		var pulse := create_tween()
		pulse.set_loops()
		pulse.tween_property(_new_best_label, "modulate:a", 0.4, 0.5)
		pulse.tween_property(_new_best_label, "modulate:a", 1.0, 0.5)
	elif _new_best_label:
		_new_best_label.visible = false

	# 23. Accuracy gauge fill, color-coded, animated to target width
	var acc_color := COL_RED
	if acc >= 90: acc_color = COL_GREEN
	elif acc >= 70: acc_color = Color(0.9, 0.8, 0.3)
	_acc_bar_fill.color = acc_color
	_acc_pct_label.text = "%s %d%%" % [LocalizationManager.get_string("hud_acc", _game_state.selected_language).to_upper(), int(round(acc))]
	var fill_tween := create_tween()
	fill_tween.tween_property(_acc_bar_fill, "anchor_right", clamp(acc / 100.0, 0.0, 1.0), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# 24. Missed words rendered as individual "chip" pills instead of a comma string
	for c in _chips_row.get_children():
		c.queue_free()

	if gs.missed_words.is_empty():
		var perfect := Label.new()
		perfect.text = LocalizationManager.get_string("perfect_run", _game_state.selected_language)
		perfect.add_theme_font_size_override("font_size", 16)
		perfect.modulate = COL_GOLD
		_chips_row.add_child(perfect)
	else:
		var shown = gs.missed_words.slice(0, min(6, gs.missed_words.size()))
		for w in shown:
			_chips_row.add_child(_make_chip(w.to_upper()))


func _make_chip(txt: String) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.9, 0.4, 0.4, 0.15)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.9, 0.4, 0.4, 0.4)
	style.set_corner_radius_all(999)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", style)
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 15)
	l.modulate = Color(0.95, 0.6, 0.6)
	chip.add_child(l)
	return chip


func _sub_labeled(txt: String) -> Label:
	var l = Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.modulate = Color(1, 1, 1, 0.65)
	return l
