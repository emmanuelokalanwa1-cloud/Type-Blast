class_name AchievementsScreen
extends ColorRect

## Full-screen list of achievements from data/achievements.json
## (AchievementsManager). Rebuilds itself fresh every time it opens so it
## always reflects current progress, same pattern as MissionsScreen /
## CareerScreen. Read-only relative to GameState - it only reads existing
## fields to check thresholds, never writes anything, so it can't corrupt
## a save file.

signal closed()

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MINT := Color(0.4, 0.9, 0.75)
const COL_MUTE := Color(1, 1, 1, 0.72)
const COL_LOCK := Color(1, 1, 1, 0.28)

var _game_state: GameState
var _list_vbox: VBoxContainer
var _scroll: ScrollContainer
var _card: PanelContainer
var _progress_label: Label
var _close_btn: Button
var _backdrop_nodes: Array = []
var _theme_keep_child_count := 0  # children added before the first _build_ui() call, preserved across refresh_theme()

func setup(root: Control, game_state: GameState) -> void:
	_game_state = game_state
	color = Color(0.015, 0.016, 0.03, 0.97)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	root.add_child(self)
	_refresh_backdrop()
	_theme_keep_child_count = get_child_count()
	_build_ui()

## Re-runs _build_ui() so the achievements list picks up a new Casual/Jelly
## interface style immediately.
func refresh_theme() -> void:
	var was_open := visible
	JellyTheme.trim_rebuildable_children(self, _theme_keep_child_count)
	_build_ui()
	visible = was_open
	if was_open:
		JellyTheme.play_rebuild_transition(self)

# One of the 4 rotating space backdrops (same set used everywhere else),
# refreshed each time this screen opens so it doesn't look identical to
# the last visit.
func _refresh_backdrop() -> void:
	BackgroundThemes.free_nodes(_backdrop_nodes)
	BackgroundThemes.advance()
	_backdrop_nodes = BackgroundThemes.build(self, BackgroundThemes.current_index, 0.42)

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
	_card.add_theme_stylebox_override("panel", JellyTheme.panel_style("card"))
	margin.add_child(_card)

	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 14)
	_card.add_child(outer_vbox)

	var title = Label.new()
	title.text = LocalizationManager.get_string("achievements", _game_state.selected_language).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	if GameFonts.bold(): title.add_theme_font_override("font", GameFonts.bold())
	title.modulate = JellyTheme.text_color(COL_GOLD)
	outer_vbox.add_child(title)

	_add_trophy_banner(outer_vbox)

	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 17)
	_progress_label.modulate = JellyTheme.text_color(COL_MUTE)
	outer_vbox.add_child(_progress_label)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1)
	divider.color = Color(1, 1, 1, 0.08)
	outer_vbox.add_child(divider)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(_scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 6)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list_vbox)

	_close_btn = _make_button("CLOSE", COL_MINT)
	_close_btn.pressed.connect(close)
	var button_row = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_child(_close_btn)
	outer_vbox.add_child(button_row)

func _add_trophy_banner(parent: VBoxContainer) -> void:
	# Decorative banner using the trophy/medal graphic from the items pack.
	# Wrapped so a missing/renamed file just skips the banner instead of
	# breaking the whole screen.
	var path := "res://assets/items/trophy_banner.jpg"
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if not tex:
		return

	var frame = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.0)
	style.set_corner_radius_all(18)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	frame.add_theme_stylebox_override("panel", style)
	frame.clip_contents = true

	var rect = TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.custom_minimum_size = Vector2(0, 110)
	rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(rect)
	parent.add_child(frame)

func _current_stats() -> Dictionary:
	if not is_instance_valid(_game_state):
		return {}
	return {
		"wpm": _game_state.best_wpm,
		"accuracy_percent": _game_state.get_accuracy(),
		"words_typed_total": _game_state.words_typed_total,
		"best_combo": _game_state.max_combo_this_run,
		"career_rank": _game_state.career_highest_rank_reached,
		"themes_played_count": 1,
	}

func _rebuild_list() -> void:
	for child in _list_vbox.get_children():
		child.queue_free()

	var stats = _current_stats()
	var unlocked_ids := AchievementsManager.evaluate(stats)
	var unlocked_set := {}
	for id in unlocked_ids:
		unlocked_set[id] = true

	var all_achievements = AchievementsManager.all()
	_progress_label.text = LocalizationManager.get_string("unlocked_count", _game_state.selected_language) % [unlocked_ids.size(), all_achievements.size()]

	_list_vbox.add_child(_build_badges_strip())

	var records_header = Label.new()
	records_header.text = LocalizationManager.get_string("full_record_log", _game_state.selected_language).to_upper()
	records_header.add_theme_font_size_override("font_size", 15)
	records_header.modulate = JellyTheme.text_color(Color(1, 1, 1, 0.35))
	_list_vbox.add_child(records_header)

	var categories := {}
	var category_order := []
	for a in all_achievements:
		var cat = String(a.get("category", "misc"))
		if not categories.has(cat):
			categories[cat] = []
			category_order.append(cat)
		categories[cat].append(a)

	if category_order.is_empty():
		var empty = Label.new()
		empty.text = LocalizationManager.get_string("no_achievements_data", _game_state.selected_language)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate = JellyTheme.text_color(COL_MUTE)
		_list_vbox.add_child(empty)
		return

	for cat in category_order:
		var header = Label.new()
		header.text = String(cat).to_upper()
		header.add_theme_font_size_override("font_size", 18)
		header.modulate = JellyTheme.text_color(COL_MINT)
		_list_vbox.add_child(header)

		for a in categories[cat]:
			_list_vbox.add_child(_build_row(a, unlocked_set.has(a.get("id", ""))))

## Compact strip of the curated BadgesManager milestones (previously only
## visible buried in the More screen). Shown above the full granular
## record log so both halves of the achievement system live in one place.
func _build_badges_strip() -> Control:
	var section_wrap = VBoxContainer.new()
	section_wrap.add_theme_constant_override("separation", 8)

	var header = Label.new()
	header.text = LocalizationManager.get_string("milestone_badges", _game_state.selected_language).to_upper()
	header.add_theme_font_size_override("font_size", 15)
	header.modulate = JellyTheme.text_color(Color(1, 1, 1, 0.35))
	section_wrap.add_child(header)

	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)

	var unlocked_badges: Array = _game_state.unlocked_badges if is_instance_valid(_game_state) else []
	for badge in BadgesManager.all():
		var is_unlocked: bool = unlocked_badges.has(badge.id)
		var tex := AchievementIcons.for_badge(badge.id)
		var cell = TextureRect.new()
		if tex:
			cell.texture = tex
			cell.custom_minimum_size = Vector2(40, 40)
			cell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			cell.modulate = Color(1, 1, 1, 1) if is_unlocked else Color(1, 1, 1, 0.18)
			cell.tooltip_text = "%s — %s" % [badge.name, badge.desc]
		grid.add_child(cell)
	section_wrap.add_child(grid)
	return section_wrap

func _build_row(a: Dictionary, is_unlocked: bool) -> Control:
	var category := String(a.get("category", ""))
	var row = PanelContainer.new()
	var style := JellyTheme.list_row_style(not is_unlocked)
	row.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	var medal_tex := AchievementIcons.for_category(category)
	if medal_tex:
		var icon = TextureRect.new()
		icon.texture = medal_tex
		icon.custom_minimum_size = Vector2(28, 28)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color(1, 1, 1, 1) if is_unlocked else Color(1, 1, 1, 0.22)
		hbox.add_child(icon)
	else:
		var icon = Label.new()
		icon.text = "★" if is_unlocked else "○"
		icon.modulate = JellyTheme.text_color(COL_GOLD) if is_unlocked else JellyTheme.text_color(COL_LOCK)
		icon.add_theme_font_size_override("font_size", 20)
		hbox.add_child(icon)

	var text_vbox = VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(text_vbox)

	var title_label = Label.new()
	title_label.text = String(a.get("title", ""))
	title_label.add_theme_font_size_override("font_size", 19)
	title_label.modulate = JellyTheme.text_color(Color.WHITE) if is_unlocked else JellyTheme.text_color(COL_LOCK)
	text_vbox.add_child(title_label)

	var desc_label = Label.new()
	desc_label.text = String(a.get("description", ""))
	desc_label.add_theme_font_size_override("font_size", 16)
	desc_label.modulate = JellyTheme.text_color(COL_MUTE) if is_unlocked else JellyTheme.text_color(COL_LOCK)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	text_vbox.add_child(desc_label)

	return row

func _make_button(txt: String, tint: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(160, 52)
	b.add_theme_font_size_override("font_size", 18)
	# NOTE: this button overrides its background with a jelly-tinted style
	# below but was never given its own font color, so it fell back to the
	# project's global Theme default (a dark green meant to pair with a
	# specific bright-green background) — on this tint the text read as
	# green-on-green and was effectively invisible. Setting it explicitly
	# here, same pattern difficulty_menu.gd already uses for its jelly
	# buttons, is what actually fixes it.
	b.add_theme_color_override("font_color", Color(0.06, 0.16, 0.05))
	b.add_theme_color_override("font_hover_color", Color(0.06, 0.16, 0.05))
	b.add_theme_color_override("font_pressed_color", Color(0.04, 0.1, 0.03))
	var normal := JellyTheme.button_style(tint, 0.85, false)
	b.add_theme_stylebox_override("normal", normal)
	var hover := JellyTheme.button_style(tint, 1.05, false)
	b.add_theme_stylebox_override("hover", hover)
	var pressed_style := JellyTheme.button_style(tint, 1.0, true)
	b.add_theme_stylebox_override("pressed", pressed_style)
	return b


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
