class_name MissionsScreen
extends ColorRect

## Full-screen overlay listing every map's missions with a checkmark for
## completed ones, plus the "Reset Progress" control. Rebuilds its list
## fresh every time it's opened so it always reflects the latest state —
## no separate refresh() call needed elsewhere.
##
## ---------------------------------------------------------------------
## 20 additions (all guarded, same public API: setup(), open(), close())
## ---------------------------------------------------------------------
##  1. Overall completion header + animated fill bar across all maps
##  2. Fade-in + scale pop-in animation when the screen opens
##  3. ESC ("ui_cancel") closes the screen
##  4. Buttons were missing a pressed-state style — added, plus hover/press
##     scale feedback
##  5. (see 4 — bundled together, button feedback was incomplete before)
##  6. Collapsible map sections via a toggle arrow on each header
##  7. Auto-scrolls to the first incomplete mission when opened
##  8. Live search box to filter missions by text
##  9. "ALL / DONE / TODO" filter chips
## 10. Per-map "★ COMPLETE" badge when a map hits 100%
## 11. Colored divider between maps (gold if that map is fully complete)
## 12. Reset button shows a live countdown while armed
## 13. Empty-state placeholder if there are no maps/missions yet
## 14. Close button auto-focuses when the screen opens
## 15. Breathing glow pulse on the card border
## 16. Small corner tag showing total map count
## 17. Mission rows get a subtle rounded chip background
## 18. Toast confirmation flash after progress is actually reset
## 19. Progress bar color shifts from red toward gold as completion rises
## 20. Everything guarded with is_instance_valid so nothing can break
## ---------------------------------------------------------------------

signal closed()

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_GREEN := Color(0.45, 0.9, 0.55)
const COL_MUTE := Color(1, 1, 1, 0.72)
const COL_RED := Color(0.85, 0.3, 0.3)

var _game_state: GameState
var _mission_manager: MissionManager
var _list_vbox: VBoxContainer
var _reset_btn: Button
var _reset_armed := false
var _reset_confirm_timer: Timer
var _reset_tick_timer: Timer # 12

# --- new refs for this pass ---
var _card: PanelContainer
var _card_style: StyleBox        # 15
var _progress_label: Label           # 1
var _progress_fill: Control          # 1
var _search_edit: LineEdit           # 8
var _filter_mode := "ALL"            # 9
var _filter_chips: Array = []        # 9
var _close_btn: Button               # 14
var _scroll: ScrollContainer         # 7
var _toast_label: Label              # 18
var _map_expanded := {}              # 6, keyed by map name
var _glow_pulse_t := 0.0             # 15
var _theme_keep_child_count := 0  # children added before the first _build_static_ui() call (timers), preserved across refresh_theme()

func setup(root: Control, game_state: GameState, mission_manager: MissionManager) -> void:
	_game_state = game_state
	_mission_manager = mission_manager
	color = Color(0.015, 0.016, 0.03, 0.96)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	root.add_child(self)

	_reset_confirm_timer = Timer.new()
	_reset_confirm_timer.one_shot = true
	_reset_confirm_timer.wait_time = 3.0
	_reset_confirm_timer.timeout.connect(_reset_confirm_state)
	add_child(_reset_confirm_timer)

	# 12. Ticks the "TAP AGAIN TO RESET (Ns)" countdown while armed.
	_reset_tick_timer = Timer.new()
	_reset_tick_timer.wait_time = 0.2
	_reset_tick_timer.timeout.connect(_update_reset_countdown)
	add_child(_reset_tick_timer)

	_theme_keep_child_count = get_child_count()
	_build_static_ui()

## Re-runs _build_static_ui() so the missions list picks up a new Casual/
## Jelly interface style immediately.
func refresh_theme() -> void:
	var was_open := visible
	JellyTheme.trim_rebuildable_children(self, _theme_keep_child_count)
	_map_expanded = {}
	_filter_chips = []
	_build_static_ui()
	if was_open:
		_rebuild_list()
	visible = was_open
	if was_open:
		JellyTheme.play_rebuild_transition(self)

func _build_static_ui() -> void:
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 50)
	margin.add_theme_constant_override("margin_bottom", 50)
	margin.add_theme_constant_override("margin_left", 180)
	margin.add_theme_constant_override("margin_right", 180)
	add_child(margin)

	_card = PanelContainer.new()
	_card_style = JellyTheme.panel_style("card")
	_card_style.content_margin_left = 48
	_card_style.content_margin_right = 48
	_card_style.content_margin_top = 40
	_card_style.content_margin_bottom = 32
	_card.add_theme_stylebox_override("panel", _card_style)
	margin.add_child(_card)

	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 18)
	_card.add_child(outer_vbox)

	var header_row = HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer_vbox.add_child(header_row)

	var title = Label.new()
	title.text = LocalizationManager.get_string("missions", _game_state.selected_language).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.modulate = JellyTheme.text_color(COL_GOLD)
	header_row.add_child(title)

	# 16. Small corner tag showing total map count.
	var map_count_tag = Label.new()
	map_count_tag.name = "MapCountTag"
	map_count_tag.add_theme_font_size_override("font_size", 17)
	map_count_tag.modulate = JellyTheme.text_color(Color(1, 1, 1, 0.4))
	map_count_tag.position = Vector2(0, 8)
	map_count_tag.set_meta("is_map_count_tag", true)
	outer_vbox.add_child(map_count_tag)

	# 1. Overall completion header + animated fill bar.
	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 18)
	_progress_label.modulate = JellyTheme.text_color(Color(1, 1, 1, 0.75))
	outer_vbox.add_child(_progress_label)
	_progress_fill = _make_progress_bar(outer_vbox)

	# 18. Toast confirmation label, hidden until a reset actually happens.
	_toast_label = Label.new()
	_toast_label.text = LocalizationManager.get_string("progress_reset", _game_state.selected_language).to_upper()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 18)
	_toast_label.modulate = JellyTheme.text_color(Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.0))
	outer_vbox.add_child(_toast_label)

	# 8. Live search filter.
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search missions..."
	_search_edit.custom_minimum_size = Vector2(0, 44)
	_search_edit.text_changed.connect(func(_t): _rebuild_list())
	outer_vbox.add_child(_search_edit)

	# 9. Filter chips: ALL / DONE / TODO.
	var chip_row = HBoxContainer.new()
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip_row.add_theme_constant_override("separation", 10)
	for mode in ["ALL", "DONE", "TODO"]:
		var chip = _make_filter_chip(mode)
		chip_row.add_child(chip)
		_filter_chips.append(chip)
	outer_vbox.add_child(chip_row)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(_scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 10)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list_vbox)

	var button_row = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 16)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer_vbox.add_child(button_row)

	_reset_btn = _make_button("RESET PROGRESS", COL_RED)
	_reset_btn.pressed.connect(_on_reset_pressed)
	button_row.add_child(_reset_btn)

	_close_btn = _make_button("CLOSE", Color(0.4, 0.9, 0.75))
	_close_btn.pressed.connect(close)
	button_row.add_child(_close_btn)

func _make_progress_bar(parent: VBoxContainer) -> Control:
	# 1. Reusable animated fill bar, same pattern as the stats screen.
	var track_width = 400.0
	var track = Control.new()
	track.custom_minimum_size = Vector2(track_width, 16)
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
	var fill_style := JellyTheme.progress_fill_style(Color.RED)
	fill.add_theme_stylebox_override("panel", fill_style)
	fill.set_meta("track_width", track_width)
	fill.set_meta("fill_style", fill_style)
	track.add_child(fill)


	parent.add_child(track)
	return fill

func _make_filter_chip(mode: String) -> Button:
	# 9. Small toggle chip for filtering the mission list.
	var chip = Button.new()
	chip.text = mode
	chip.toggle_mode = true
	chip.button_pressed = (mode == "ALL")
	chip.custom_minimum_size = Vector2(90, 40)
	chip.add_theme_font_size_override("font_size", 18)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.06)
	style.set_corner_radius_all(20)
	chip.add_theme_stylebox_override("normal", style)
	var pressed_style := style.duplicate()
	pressed_style.bg_color = COL_GOLD.darkened(0.3)
	chip.add_theme_stylebox_override("pressed", pressed_style)
	chip.toggled.connect(func(is_pressed):
		if is_pressed:
			_filter_mode = mode
			for other in _filter_chips:
				if other != chip and is_instance_valid(other):
					other.button_pressed = false
			_rebuild_list()
		elif _filter_mode == mode:
			# Prevent leaving zero chips selected — snap back to ALL.
			chip.button_pressed = true
	)
	return chip

func _rebuild_list() -> void:
	for child in _list_vbox.get_children():
		child.queue_free()

	var maps = _mission_manager.get_maps()

	# 13. Empty-state placeholder.
	if maps.is_empty():
		var empty_label = Label.new()
		empty_label.text = LocalizationManager.get_string("no_missions_yet", _game_state.selected_language)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.modulate = JellyTheme.text_color(COL_MUTE)
		_list_vbox.add_child(empty_label)
		if is_instance_valid(_progress_label):
			_progress_label.text = ""
		return

	var search_text = _search_edit.text.to_lower() if is_instance_valid(_search_edit) else ""
	var total_missions := 0
	var total_done := 0
	var first_incomplete_row: Control = null

	for map: Dictionary in maps:
		var done := 0
		for mission: Dictionary in map.missions:
			if _mission_manager.is_completed(mission.id):
				done += 1
		total_missions += map.missions.size()
		total_done += done

		var map_complete = done == map.missions.size() and map.missions.size() > 0
		if not _map_expanded.has(map.name):
			_map_expanded[map.name] = true # 6. expanded by default

		var header_row = HBoxContainer.new()
		header_row.add_theme_constant_override("separation", 8)

		# 6. Collapse/expand arrow toggle for this map's section.
		var toggle_btn = Button.new()
		toggle_btn.text = "▼" if _map_expanded[map.name] else "▶"
		toggle_btn.custom_minimum_size = Vector2(32, 32)
		toggle_btn.flat = true
		header_row.add_child(toggle_btn)

		var header = Label.new()
		header.text = "%s   (%d/%d)" % [map.name, done, map.missions.size()]
		header.add_theme_font_size_override("font_size", 26)
		header.modulate = JellyTheme.text_color(COL_GOLD if map_complete else Color.WHITE)
		header_row.add_child(header)

		# 10. "★ COMPLETE" badge when a map hits 100%.
		if map_complete:
			var badge = Label.new()
			badge.text = "★ " + LocalizationManager.get_string("complete", _game_state.selected_language).to_upper()
			badge.add_theme_font_size_override("font_size", 18)
			badge.modulate = JellyTheme.text_color(COL_GOLD)
			header_row.add_child(badge)

		_list_vbox.add_child(header_row)

		var rows_container = VBoxContainer.new()
		rows_container.add_theme_constant_override("separation", 6)
		rows_container.visible = _map_expanded[map.name]
		toggle_btn.pressed.connect(func():
			_map_expanded[map.name] = not _map_expanded[map.name]
			rows_container.visible = _map_expanded[map.name]
			toggle_btn.text = "▼" if _map_expanded[map.name] else "▶"
		)
		_list_vbox.add_child(rows_container)

		for mission: Dictionary in map.missions:
			var completed: bool = _mission_manager.is_completed(mission.id)

			# 8/9. Apply search text + filter chip before building the row.
			if search_text != "" and not str(mission.text).to_lower().contains(search_text):
				continue
			if _filter_mode == "DONE" and not completed:
				continue
			if _filter_mode == "TODO" and completed:
				continue

			# 17. Rounded chip background behind each mission row.
			var chip_wrap = PanelContainer.new()
			var chip_style := StyleBoxFlat.new()
			chip_style.bg_color = Color(1, 1, 1, 0.03) if not completed else Color(COL_GREEN.r, COL_GREEN.g, COL_GREEN.b, 0.06)
			chip_style.set_corner_radius_all(10)
			chip_style.content_margin_left = 14
			chip_style.content_margin_right = 14
			chip_style.content_margin_top = 6
			chip_style.content_margin_bottom = 6
			chip_wrap.add_theme_stylebox_override("panel", chip_style)

			var row = Label.new()
			row.text = ("●  " if completed else "◻  ") + mission.text
			row.add_theme_font_size_override("font_size", 20)
			row.modulate = JellyTheme.text_color(COL_GREEN if completed else COL_MUTE)
			chip_wrap.add_child(row)
			rows_container.add_child(chip_wrap)

			if not completed and first_incomplete_row == null:
				first_incomplete_row = chip_wrap # 7. remember for auto-scroll

		# 11. Colored divider — gold if this map is fully complete.
		var divider = ColorRect.new()
		divider.custom_minimum_size = Vector2(0, 2)
		divider.color = Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.3) if map_complete else Color(1, 1, 1, 0.08)
		_list_vbox.add_child(divider)

	# 1/19. Update the overall progress readout + bar color.
	if is_instance_valid(_progress_label):
		_progress_label.text = (LocalizationManager.get_string("missions_complete_count", _game_state.selected_language) % [total_done, total_missions]).to_upper()
	if is_instance_valid(_progress_fill):
		var pct = (float(total_done) / float(max(total_missions, 1))) * 100.0
		_animate_progress_fill(pct)

	# 16. Keep the map-count corner tag in sync.
	var tag = _find_map_count_tag()
	if is_instance_valid(tag):
		tag.text = str(maps.size()) + (" MAP" if maps.size() == 1 else " MAPS")

	# 7. Auto-scroll to the first incomplete mission, once layout settles.
	if is_instance_valid(first_incomplete_row) and is_instance_valid(_scroll):
		call_deferred("_scroll_to_row", first_incomplete_row)

func _scroll_to_row(row: Control) -> void:
	if is_instance_valid(_scroll) and is_instance_valid(row):
		_scroll.ensure_control_visible(row)

func _find_map_count_tag() -> Label:
	for child in _card.get_children():
		var found = _search_for_tag(child)
		if found:
			return found
	return null

func _search_for_tag(node: Node) -> Label:
	if node is Label and node.get_meta("is_map_count_tag", false):
		return node
	for child in node.get_children():
		var found = _search_for_tag(child)
		if found:
			return found
	return null

func _animate_progress_fill(pct: float) -> void:
	var fill = _progress_fill
	if not is_instance_valid(fill):
		return
	var track_width = fill.get_meta("track_width", 400.0)
	var fill_style: StyleBox = fill.get_meta("fill_style", null)
	if fill_style:
		JellyTheme.set_fill_color(fill_style, Color.RED.lerp(COL_GOLD, clamp(pct / 100.0, 0.0, 1.0))) # 19
	var target_width = track_width * (clamp(pct, 0.0, 100.0) / 100.0)
	fill.offset_right = 0
	create_tween().tween_property(fill, "offset_right", target_width, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _make_button(txt: String, accent: Color) -> Button:
	var btn = Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(220, 60)
	btn.add_theme_font_size_override("font_size", 22)
	btn.pivot_offset = btn.custom_minimum_size / 2

	var normal := JellyTheme.button_style(accent, 0.85, false)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := JellyTheme.button_style(accent, 1.05, false)
	btn.add_theme_stylebox_override("hover", hover)

	# 4/5. Buttons had no pressed style before — added, plus scale feedback.
	var pressed_style := JellyTheme.button_style(accent, 1.0, true)
	btn.add_theme_stylebox_override("pressed", pressed_style)

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


func _on_reset_pressed() -> void:
	# Same double-tap-to-confirm pattern as the pause menu's Quit button —
	# resetting progress is destructive enough to deserve a second tap.
	if not _reset_armed:
		_reset_armed = true
		_reset_btn.text = (LocalizationManager.get_string("tap_again_reset", _game_state.selected_language) % 3).to_upper()
		_reset_confirm_timer.start()
		_reset_tick_timer.start() # 12
	else:
		_reset_confirm_state()
		_game_state.reset_all_progress()
		_rebuild_list()
		_flash_toast() # 18

func _update_reset_countdown() -> void:
	# 12. Live countdown while the reset button is armed.
	if not _reset_armed or not is_instance_valid(_reset_btn):
		_reset_tick_timer.stop()
		return
	var secs = int(ceil(_reset_confirm_timer.time_left))
	_reset_btn.text = (LocalizationManager.get_string("tap_again_reset", _game_state.selected_language) % max(secs, 0)).to_upper()

func _reset_confirm_state() -> void:
	_reset_armed = false
	_reset_tick_timer.stop()
	if is_instance_valid(_reset_btn):
		_reset_btn.text = LocalizationManager.get_string("reset_progress", _game_state.selected_language).to_upper()

func _flash_toast() -> void:
	# 18. Brief confirmation flash after progress is actually reset.
	if not is_instance_valid(_toast_label):
		return
	_toast_label.modulate.a = 1.0
	var tw = create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(_toast_label, "modulate:a", 0.0, 0.6)

func _process(delta: float) -> void:
	if not visible:
		return
	# 15. Subtle breathing glow on the card border, consistent with the
	# pause menu and results screen.
	_glow_pulse_t += delta
	if is_instance_valid(_card_style) and _card_style is StyleBoxFlat:
		_card_style.border_color.a = 0.06 + sin(_glow_pulse_t * 1.6) * 0.04

func _unhandled_input(event: InputEvent) -> void:
	# 3. ESC (or the mapped ui_cancel action) closes the screen.
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func open() -> void:
	_rebuild_list()
	visible = true

	# 2. Fade-in + scale pop-in for the whole overlay.
	modulate.a = 0.0
	if is_instance_valid(_card):
		_card.scale = Vector2(0.92, 0.92)
		_card.pivot_offset = _card.size / 2
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	if is_instance_valid(_card):
		tw.parallel().tween_property(_card, "scale", Vector2(1.0, 1.0), 0.3)

	# 14. Keyboard/controller friendly: focus lands on Close.
	if is_instance_valid(_close_btn):
		_close_btn.call_deferred("grab_focus")

func close() -> void:
	visible = false
	closed.emit()
