class_name CareerScreen
extends ColorRect

## Full-screen "Career Path" ladder for Career Mode ("The Climb"). Reuses
## MissionData's 20 maps as ranks and matches the visual language already
## established by MissionsScreen / DifficultyMenu (vignette backdrop,
## rounded glass cards, gold/mint accents, pop-in tweens).
##
## Layout:
##   - Header: title, subtitle, big "current rank" status card (rank
##     number, title, tier badge, mission progress ring, word-length +
##     speed readout for that rank)
##   - Overall ladder progress bar (unlocked ranks / total)
##   - Scrollable ladder grouped into 4 tiers of 5 ranks each (Rookie /
##     Contender / Veteran / Elite), each tier with its own header,
##     accent color, and collapse arrow
##   - Rank-up certificate popup + a separate "climb complete" popup,
##     shown from main.gd right after a run clears enough of the
##     current (frontier) rank's missions

signal closed()
signal rank_selected(rank: int)

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MINT := Color(0.4, 0.9, 0.75)
const COL_MUTE := Color(1, 1, 1, 0.72)
const COL_LOCK := Color(1, 1, 1, 0.28)

var _game_state: GameState
var _mission_manager: MissionManager
var _career_manager: CareerManager

# --- static shell built once ---
var _card: PanelContainer
var _card_style: StyleBox
var _backdrop_nodes: Array = []
var _theme_keep_child_count := 0  # children added before the first _build_ui() call, preserved across refresh_theme()
var _list_vbox: VBoxContainer
var _scroll: ScrollContainer
var _close_btn: Button

var _status_rank_label: Label
var _status_badge_icon: TextureRect
var _cert_badge_icon: TextureRect
var _cert_star_fallback: Label
var _status_title_label: Label
var _status_tier_badge: Label
var _status_progress_label: Label
var _status_ring_fill: Control
var _status_speed_label: Label
var _status_lore_label: Label

var _overall_label: Label
var _overall_fill: Control

var _tier_expanded := {}
var _glow_pulse_t := 0.0

# --- popups ---
var _cert_overlay: ColorRect
var _cert_card: PanelContainer
var _cert_rank_label: Label

var _climb_overlay: ColorRect
var _climb_card: PanelContainer

func setup(root: Control, game_state: GameState, mission_manager: MissionManager, career_manager: CareerManager) -> void:
	_game_state = game_state
	_mission_manager = mission_manager
	_career_manager = career_manager
	color = Color(0.015, 0.016, 0.03, 0.97)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	root.add_child(self)

	BackgroundThemes.advance()
	_backdrop_nodes = BackgroundThemes.build(self, BackgroundThemes.current_index, 0.42)
	_build_vignette_background()
	_theme_keep_child_count = get_child_count()
	_build_ui()
	_build_certificate_popup(root)
	_build_climb_complete_popup(root)

## Re-runs _build_ui() so the career screen's rank track and buttons pick
## up a new Casual/Jelly interface style immediately.
func refresh_theme() -> void:
	var was_open := visible
	JellyTheme.trim_rebuildable_children(self, _theme_keep_child_count)
	_build_ui()
	visible = was_open
	if was_open:
		JellyTheme.play_rebuild_transition(self)

# Rotates to the next of the 4 space backdrops - called again each time
# this screen opens so it doesn't look identical to the last visit.
func _refresh_backdrop() -> void:
	BackgroundThemes.free_nodes(_backdrop_nodes)
	BackgroundThemes.advance()
	_backdrop_nodes = BackgroundThemes.build(self, BackgroundThemes.current_index, 0.42)

# ---------------------------------------------------------------------
# BACKGROUND
# ---------------------------------------------------------------------

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
	var vp = get_viewport_rect().size
	var side_margin = int(clamp(vp.x * 0.05, 16, 120))
	var vert_margin = int(clamp(vp.y * 0.035, 24, 70))

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", vert_margin)
	margin.add_theme_constant_override("margin_bottom", vert_margin)
	margin.add_theme_constant_override("margin_left", side_margin)
	margin.add_theme_constant_override("margin_right", side_margin)
	add_child(margin)

	_card = PanelContainer.new()
	_card_style = JellyTheme.panel_style("card")
	_card.add_theme_stylebox_override("panel", _card_style)
	margin.add_child(_card)

	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 14)
	_card.add_child(outer_vbox)

	# --- Title row ---
	var title = Label.new()
	title.text = LocalizationManager.get_string("the_climb", _game_state.selected_language).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.modulate = COL_MINT
	outer_vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = LocalizationManager.get_string("climb_subtitle", _game_state.selected_language)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.modulate = COL_MUTE
	outer_vbox.add_child(subtitle)

	# --- Current-rank status card ---
	outer_vbox.add_child(_build_status_card())

	# --- Overall ladder progress ---
	var overall_row = HBoxContainer.new()
	overall_row.alignment = BoxContainer.ALIGNMENT_CENTER
	overall_row.add_theme_constant_override("separation", 10)
	_overall_label = Label.new()
	_overall_label.add_theme_font_size_override("font_size", 17)
	_overall_label.modulate = COL_GOLD
	overall_row.add_child(_overall_label)
	outer_vbox.add_child(overall_row)
	_overall_fill = _make_progress_bar(outer_vbox, 480.0, COL_GOLD)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1)
	divider.color = Color(1, 1, 1, 0.08)
	outer_vbox.add_child(divider)

	# --- Scrollable ladder ---
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(_scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 8)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list_vbox)

	_close_btn = _make_button("CLOSE", COL_MINT)
	_close_btn.pressed.connect(close)
	var button_row = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_child(_close_btn)
	outer_vbox.add_child(button_row)

func _build_status_card() -> Control:
	var status_wrap = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.045)
	style.set_corner_radius_all(20)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.09)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	status_wrap.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	status_wrap.add_child(hbox)

	# Progress ring (implemented as a circular Control drawn procedurally)
	var ring_wrap = Control.new()
	ring_wrap.custom_minimum_size = Vector2(88, 88)
	var ring_bg = _make_ring(Color(1, 1, 1, 0.1), 1.0)
	ring_wrap.add_child(ring_bg)
	_status_ring_fill = _make_ring(COL_GOLD, 0.0)
	ring_wrap.add_child(_status_ring_fill)
	_status_rank_label = Label.new()
	_status_rank_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_rank_label.add_theme_font_size_override("font_size", 30)
	ring_wrap.add_child(_status_rank_label)
	hbox.add_child(ring_wrap)

	_status_badge_icon = TextureRect.new()
	_status_badge_icon.custom_minimum_size = Vector2(44, 44)
	_status_badge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hbox.add_child(_status_badge_icon)

	var text_vbox = VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(text_vbox)

	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	_status_title_label = Label.new()
	_status_title_label.add_theme_font_size_override("font_size", 22)
	top_row.add_child(_status_title_label)
	_status_tier_badge = Label.new()
	_status_tier_badge.add_theme_font_size_override("font_size", 18)
	top_row.add_child(_status_tier_badge)
	text_vbox.add_child(top_row)

	_status_progress_label = Label.new()
	_status_progress_label.add_theme_font_size_override("font_size", 18)
	_status_progress_label.modulate = COL_MUTE
	text_vbox.add_child(_status_progress_label)

	_status_speed_label = Label.new()
	_status_speed_label.add_theme_font_size_override("font_size", 18)
	_status_speed_label.modulate = COL_MUTE
	text_vbox.add_child(_status_speed_label)

	# Short original narrative blurb for this rank (data/lore/rank_lore.json,
	# loaded via LoreManager). Purely cosmetic flavor text - if the lore
	# file is ever missing, LoreManager.get_lore_for_rank() just returns ""
	# and this label quietly stays empty instead of erroring.
	_status_lore_label = Label.new()
	_status_lore_label.add_theme_font_size_override("font_size", 18)
	_status_lore_label.modulate = Color(1, 1, 1, 0.4)
	_status_lore_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	text_vbox.add_child(_status_lore_label)

	var play_btn = _make_button("PLAY THIS RANK", COL_GOLD)
	play_btn.custom_minimum_size = Vector2(190, 48)
	play_btn.add_theme_font_size_override("font_size", 17)
	play_btn.pressed.connect(func(): _on_row_pressed(_career_manager.current_rank))
	hbox.add_child(play_btn)

	return status_wrap

## Tiny custom-drawn ring used as a compact "missions cleared" indicator
## inside the status card, instead of a plain progress bar.
func _make_ring(ring_color: Color, fraction: float) -> Control:
	var c = Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.set_meta("ring_color", ring_color)
	c.set_meta("fraction", fraction)
	c.draw.connect(func():
		var col = c.get_meta("ring_color")
		var frac = c.get_meta("fraction")
		var radius = c.size.x / 2.0 - 6.0
		var center = c.size / 2.0
		if frac >= 0.999:
			c.draw_arc(center, radius, 0, TAU, 48, col, 8.0, true)
		elif frac > 0.0:
			c.draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * frac, 48, col, 8.0, true)
	)
	return c

func _set_ring_fraction(ring: Control, fraction: float) -> void:
	ring.set_meta("fraction", clamp(fraction, 0.0, 1.0))
	ring.queue_redraw()

func _make_progress_bar(parent: VBoxContainer, track_width: float, fill_color: Color) -> Control:
	var track = Control.new()
	track.custom_minimum_size = Vector2(track_width, 14)
	track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var track_bg = PanelContainer.new()
	track_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track_bg.add_theme_stylebox_override("panel", JellyTheme.progress_track_style())
	track.add_child(track_bg)

	var fill = PanelContainer.new()
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.offset_left = 0
	fill.offset_right = 0
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.set_corner_radius_all(7)
	fill.add_theme_stylebox_override("panel", fill_style)
	track.add_child(fill)

	parent.add_child(track)
	return fill

func _make_button(txt: String, accent: Color) -> Button:
	var btn = Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(200, 56)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pivot_offset = btn.custom_minimum_size / 2

	var normal := _asset_button_style("res://assets/items/ui/button_rectangle.png", accent, 0.85)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := _asset_button_style("res://assets/items/ui/button_rectangle.png", accent, 1.05)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed_style := _asset_button_style("res://assets/items/ui/button_rectangle_depth.png", accent, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.mouse_entered.connect(func(): create_tween().tween_property(btn, "scale", Vector2(1.03, 1.03), 0.12))
	btn.mouse_exited.connect(func(): create_tween().tween_property(btn, "scale", Vector2(1.0, 1.0), 0.12))
	btn.button_down.connect(func(): create_tween().tween_property(btn, "scale", Vector2(0.96, 0.96), 0.08))
	btn.button_up.connect(func(): create_tween().tween_property(btn, "scale", Vector2(1.03, 1.03), 0.08))
	return btn

func _asset_button_style(texture_path: String, tint: Color, brightness: float) -> StyleBox:
	return JellyTheme.button_style(tint, brightness, texture_path.contains("depth"))

# ---------------------------------------------------------------------
# LADDER LIST (grouped into 4 tiers of 5 ranks each)
# ---------------------------------------------------------------------

func _rebuild_list() -> void:
	for child in _list_vbox.get_children():
		child.queue_free()

	var total_ranks := CareerData.rank_count()
	var current_row: Control = null

	# Group consecutive ranks by tier label so ranks stay in numeric order.
	var tier_order: Array = []
	var tier_ranks := {}
	for rank in range(1, total_ranks + 1):
		var tier = CareerData.tier_label_for_rank(rank)
		if not tier_ranks.has(tier):
			tier_ranks[tier] = []
			tier_order.append(tier)
		tier_ranks[tier].append(rank)

	for tier in tier_order:
		var ranks_in_tier: Array = tier_ranks[tier]
		var tier_color = CareerData.color_for_rank(ranks_in_tier[0])
		var tier_done = 0
		for r in ranks_in_tier:
			if _career_manager.is_rank_unlocked(r) and _career_manager.is_rank_complete(r):
				tier_done += 1

		if not _tier_expanded.has(tier):
			_tier_expanded[tier] = true

		var header_row = HBoxContainer.new()
		header_row.add_theme_constant_override("separation", 8)

		var toggle_btn = Button.new()
		toggle_btn.text = "▼" if _tier_expanded[tier] else "▶"
		toggle_btn.custom_minimum_size = Vector2(30, 30)
		toggle_btn.flat = true
		header_row.add_child(toggle_btn)

		var header = Label.new()
		header.text = "%s TIER   (%d/%d ranks cleared)" % [tier, tier_done, ranks_in_tier.size()]
		header.add_theme_font_size_override("font_size", 20)
		header.modulate = tier_color if tier_done == ranks_in_tier.size() else Color.WHITE
		header_row.add_child(header)

		if tier_done == ranks_in_tier.size():
			var badge = Label.new()
			badge.text = "★ " + LocalizationManager.get_string("tier_cleared", _game_state.selected_language).to_upper()
			badge.add_theme_font_size_override("font_size", 17)
			badge.modulate = COL_GOLD
			header_row.add_child(badge)

		_list_vbox.add_child(header_row)

		var rows_container = VBoxContainer.new()
		rows_container.add_theme_constant_override("separation", 8)
		rows_container.visible = _tier_expanded[tier]
		toggle_btn.pressed.connect(func():
			_tier_expanded[tier] = not _tier_expanded[tier]
			rows_container.visible = _tier_expanded[tier]
			toggle_btn.text = "▼" if _tier_expanded[tier] else "▶"
		)
		_list_vbox.add_child(rows_container)

		for rank in ranks_in_tier:
			var row = _build_rank_row(rank, tier_color)
			rows_container.add_child(row)
			if rank == _career_manager.current_rank:
				current_row = row

		var divider := ColorRect.new()
		divider.custom_minimum_size = Vector2(0, 2)
		divider.color = Color(tier_color.r, tier_color.g, tier_color.b, 0.25) if tier_done == ranks_in_tier.size() else Color(1, 1, 1, 0.07)
		_list_vbox.add_child(divider)

	_update_status_card()
	_update_overall_progress()

	if is_instance_valid(current_row) and is_instance_valid(_scroll):
		call_deferred("_scroll_to_row", current_row)

func _build_rank_row(rank: int, tier_color: Color) -> Control:
	var unlocked := _career_manager.is_rank_unlocked(rank)
	var is_current := rank == _career_manager.current_rank
	var complete := unlocked and _career_manager.is_rank_complete(rank)
	var progress := CareerData.missions_for_rank(rank).size()
	var done := _mission_manager.get_completed_ids_for_map(rank - 1).size() if unlocked else 0
	var need := CareerData.clear_requirement_for_rank(rank)

	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 60)
	row.add_theme_font_size_override("font_size", 19)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.disabled = not unlocked
	row.clip_text = true

	var status_text: String
	var tint: Color
	if not unlocked:
		status_text = "LOCKED"
		tint = COL_LOCK
	elif complete:
		status_text = "★ COMPLETE  (%d/%d missions)" % [done, progress]
		tint = COL_GOLD
	else:
		status_text = "%d/%d missions to rank up" % [done, need]
		tint = tier_color if is_current else Color.WHITE

	var badge_tex := CareerData.icon_for_rank(rank)
	if badge_tex:
		row.icon = badge_tex
		row.expand_icon = false
		row.add_theme_constant_override("h_separation", 12)
		row.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.35))
		row.text = "  RANK %d — %s        %s" % [rank, CareerData.flavor_for_rank(rank).to_upper(), status_text]
	else:
		var icon = "○" if not unlocked else ("★" if complete else "▶")
		row.text = "   %s   RANK %d — %s        %s" % [icon, rank, CareerData.flavor_for_rank(rank).to_upper(), status_text]

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(tier_color.r, tier_color.g, tier_color.b, 0.07) if unlocked else Color(1, 1, 1, 0.02)
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 16
	if is_current and unlocked:
		normal.border_width_left = 3
		normal.border_width_right = 3
		normal.border_width_top = 3
		normal.border_width_bottom = 3
		normal.border_color = tier_color
	row.add_theme_stylebox_override("normal", normal)
	if unlocked:
		var hover := normal.duplicate()
		hover.bg_color = Color(tier_color.r, tier_color.g, tier_color.b, 0.16)
		row.add_theme_stylebox_override("hover", hover)
		var pressed_style := normal.duplicate()
		pressed_style.bg_color = Color(tier_color.r, tier_color.g, tier_color.b, 0.24)
		row.add_theme_stylebox_override("pressed", pressed_style)
	row.add_theme_stylebox_override("disabled", normal)
	row.add_theme_color_override("font_color", tint)
	row.add_theme_color_override("font_disabled_color", COL_LOCK)

	if unlocked:
		row.pressed.connect(func(): _on_row_pressed(rank))
		row.mouse_entered.connect(func(): create_tween().tween_property(row, "scale", Vector2(1.01, 1.01), 0.1))
		row.mouse_exited.connect(func(): create_tween().tween_property(row, "scale", Vector2(1.0, 1.0), 0.1))
		row.pivot_offset = row.custom_minimum_size / 2

	return row

func _update_status_card() -> void:
	var rank = _career_manager.current_rank
	var progress = _career_manager.get_current_rank_progress()
	var tier_color = CareerData.color_for_rank(rank)

	_status_rank_label.text = str(rank)
	_status_rank_label.modulate = tier_color
	if is_instance_valid(_status_badge_icon):
		_status_badge_icon.texture = CareerData.icon_for_rank(rank)
	_status_title_label.text = CareerData.flavor_for_rank(rank).to_upper()
	_status_title_label.modulate = tier_color
	_status_tier_badge.text = "  " + CareerData.tier_label_for_rank(rank) + " TIER"
	_status_tier_badge.modulate = COL_MUTE
	_status_progress_label.text = "%d / %d missions cleared this rank (%d needed to rank up)" % [
		progress.done, CareerData.missions_for_rank(rank).size(), progress.need
	]
	_status_speed_label.text = "Word length: %s   •   Fall-speed bonus: +%d" % [
		CareerData.difficulty_for_rank(rank), int(CareerData.fall_speed_bonus_for_rank(rank))
	]
	if is_instance_valid(_status_lore_label):
		_status_lore_label.text = LoreManager.get_lore_for_rank(rank)

	if is_instance_valid(_status_ring_fill):
		var frac = float(progress.done) / float(max(progress.need, 1))
		_status_ring_fill.set_meta("ring_color", tier_color)
		_set_ring_fraction(_status_ring_fill, frac)

func _update_overall_progress() -> void:
	var total = CareerData.rank_count()
	var unlocked = _career_manager.unlocked_rank
	_overall_label.text = LocalizationManager.get_string("ladder_progress", _game_state.selected_language).to_upper() + " — " + (LocalizationManager.get_string("rank_of_unlocked", _game_state.selected_language) % [unlocked, total]).to_upper()
	if is_instance_valid(_overall_fill):
		var pct = float(unlocked - 1) / float(max(total - 1, 1))
		_overall_fill.anchor_right = clamp(pct, 0.0, 1.0)

func _scroll_to_row(row: Control) -> void:
	if is_instance_valid(row) and is_instance_valid(_scroll):
		_scroll.ensure_control_visible(row)

func _on_row_pressed(rank: int) -> void:
	close()
	rank_selected.emit(rank)

func _process(delta: float) -> void:
	if not visible:
		return
	_glow_pulse_t += delta
	if is_instance_valid(_card_style) and _card_style is StyleBoxFlat:
		_card_style.border_color.a = 0.06 + sin(_glow_pulse_t * 1.6) * 0.04

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func open() -> void:
	_refresh_backdrop()
	_rebuild_list()
	move_to_front()
	visible = true

	modulate.a = 0.0
	if is_instance_valid(_card):
		_card.scale = Vector2(0.94, 0.94)
		_card.pivot_offset = _card.size / 2
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	if is_instance_valid(_card):
		tw.parallel().tween_property(_card, "scale", Vector2(1.0, 1.0), 0.3)

	if is_instance_valid(_close_btn):
		_close_btn.call_deferred("grab_focus")

func close() -> void:
	visible = false
	closed.emit()

# ---------------------------------------------------------------------
# "Rank up" certificate popup — shown from main.gd right after a run
# clears enough missions to open the next rank.
# ---------------------------------------------------------------------

func _build_certificate_popup(root: Control) -> void:
	_cert_overlay = ColorRect.new()
	_cert_overlay.color = Color(0, 0, 0, 0.72)
	_cert_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cert_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_cert_overlay.visible = false
	root.add_child(_cert_overlay)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cert_overlay.add_child(center)

	_cert_card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	style.set_corner_radius_all(24)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = COL_GOLD
	style.shadow_size = 34
	style.shadow_color = Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.35)
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 34
	style.content_margin_bottom = 34
	_cert_card.add_theme_stylebox_override("panel", style)
	center.add_child(_cert_card)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_cert_card.add_child(vbox)

	_cert_badge_icon = TextureRect.new()
	_cert_badge_icon.custom_minimum_size = Vector2(96, 96)
	_cert_badge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_center = CenterContainer.new()
	icon_center.add_child(_cert_badge_icon)
	vbox.add_child(icon_center)

	_cert_star_fallback = Label.new()
	_cert_star_fallback.text = "★"
	_cert_star_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cert_star_fallback.add_theme_font_size_override("font_size", 48)
	_cert_star_fallback.modulate = COL_GOLD
	_cert_star_fallback.visible = false
	vbox.add_child(_cert_star_fallback)

	var cert_title = Label.new()
	cert_title.text = LocalizationManager.get_string("rank_up", _game_state.selected_language).to_upper()
	cert_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cert_title.add_theme_font_size_override("font_size", 34)
	if GameFonts.bold(): cert_title.add_theme_font_override("font", GameFonts.bold())
	cert_title.modulate = COL_GOLD
	vbox.add_child(cert_title)

	_cert_rank_label = Label.new()
	_cert_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cert_rank_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_cert_rank_label)

	var continue_btn = _make_button("CONTINUE", COL_GOLD)
	continue_btn.pressed.connect(func(): _cert_overlay.visible = false)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(continue_btn)
	vbox.add_child(row)

## Call right after CareerManager.check_rank_progress() reports a rank-up.
func show_rank_up(rank: int, _title: String) -> void:
	var flavor = CareerData.flavor_for_rank(rank).to_upper()
	_cert_rank_label.text = "You've reached RANK %d\n%s" % [rank, flavor]
	var badge_tex := CareerData.large_icon_for_rank(rank)
	if is_instance_valid(_cert_badge_icon):
		_cert_badge_icon.texture = badge_tex
		_cert_badge_icon.visible = badge_tex != null
	if is_instance_valid(_cert_star_fallback):
		_cert_star_fallback.visible = badge_tex == null
	_cert_overlay.visible = true
	_cert_overlay.move_to_front()
	_cert_card.scale = Vector2(0.85, 0.85)
	_cert_card.modulate.a = 0.0
	_cert_card.pivot_offset = _cert_card.size / 2
	var tw = create_tween().set_parallel(true)
	tw.tween_property(_cert_card, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_cert_card, "modulate:a", 1.0, 0.25)

# ---------------------------------------------------------------------
# "Climb complete" popup — shown once the top rank's requirement is met.
# ---------------------------------------------------------------------

func _build_climb_complete_popup(root: Control) -> void:
	_climb_overlay = ColorRect.new()
	_climb_overlay.color = Color(0, 0, 0, 0.78)
	_climb_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_climb_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_climb_overlay.visible = false
	root.add_child(_climb_overlay)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_climb_overlay.add_child(center)

	_climb_card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.98)
	style.set_corner_radius_all(26)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = COL_GOLD
	style.shadow_size = 44
	style.shadow_color = Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.45)
	style.content_margin_left = 56
	style.content_margin_right = 56
	style.content_margin_top = 40
	style.content_margin_bottom = 40
	_climb_card.add_theme_stylebox_override("panel", style)
	center.add_child(_climb_card)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	_climb_card.add_child(vbox)

	var crown = Label.new()
	crown.text = "★"
	crown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crown.add_theme_font_size_override("font_size", 56)
	vbox.add_child(crown)

	var big_title = Label.new()
	big_title.text = LocalizationManager.get_string("climb_complete", _game_state.selected_language).to_upper()
	big_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_title.add_theme_font_size_override("font_size", 30)
	big_title.modulate = COL_GOLD
	vbox.add_child(big_title)

	var sub = Label.new()
	sub.text = LocalizationManager.get_string("legend_status", _game_state.selected_language)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.modulate = COL_MUTE
	vbox.add_child(sub)

	var continue_btn = _make_button("CONTINUE", COL_GOLD)
	continue_btn.pressed.connect(func(): _climb_overlay.visible = false)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(continue_btn)
	vbox.add_child(row)

func show_climb_complete() -> void:
	_climb_overlay.visible = true
	_climb_overlay.move_to_front()
	_climb_card.scale = Vector2(0.8, 0.8)
	_climb_card.modulate.a = 0.0
	_climb_card.pivot_offset = _climb_card.size / 2
	var tw = create_tween().set_parallel(true)
	tw.tween_property(_climb_card, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_climb_card, "modulate:a", 1.0, 0.3)
