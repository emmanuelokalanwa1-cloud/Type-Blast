class_name SentenceModeScreen
extends ColorRect

## Standalone "type the whole sentence" practice mode, built on top of
## SentenceBank. Deliberately NOT integrated into the falling-word game
## loop (main.gd / typing_controller.gd) - it's its own simple self-typing
## screen with a Label + LineEdit, so it can't destabilize the existing
## gameplay code path. Opened from DifficultyMenu's "SENTENCE PRACTICE"
## button, closed back to it.

signal closed()

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MINT := Color(0.4, 0.9, 0.75)
const COL_MUTE := Color(1, 1, 1, 0.55)
const COL_RED := Color(0.85, 0.35, 0.35)

var _game_state: GameState
var _mission_manager: MissionManager
var _card: PanelContainer
var _sentence_label: Label
var _input_edit: LineEdit
var _result_label: Label
var _next_btn: Button
var _close_btn: Button

var _current_sentence := ""
var _start_msec := 0
var _typing_started := false
var _rng := RandomNumberGenerator.new()
var _theme_keep_child_count := 0  # children added before the first _build_ui() call, preserved across refresh_theme()

## mission_manager is optional (defaults to null) so this stays backward
## compatible with any existing caller that only passes root+game_state.
func setup(root: Control, game_state: GameState, mission_manager: MissionManager = null) -> void:
	_game_state = game_state
	_mission_manager = mission_manager
	_rng.randomize()
	color = Color(0.015, 0.016, 0.03, 0.97)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	root.add_child(self)
	_theme_keep_child_count = get_child_count()
	_build_ui()

## Re-runs _build_ui() so sentence practice picks up a new Casual/Jelly
## interface style immediately.
func refresh_theme() -> void:
	var was_open := visible
	JellyTheme.trim_rebuildable_children(self, _theme_keep_child_count)
	_build_ui()
	visible = was_open
	if was_open:
		JellyTheme.play_rebuild_transition(self)

func _build_ui() -> void:
	var vp = get_viewport_rect().size
	var side_margin = int(clamp(vp.x * 0.06, 20, 140))
	var vert_margin = int(clamp(vp.y * 0.06, 40, 120))

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

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 22)
	_card.add_child(vbox)

	var title = Label.new()
	title.text = LocalizationManager.get_string("sentence_mode", _game_state.selected_language).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.modulate = JellyTheme.text_color(COL_MINT)
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = LocalizationManager.get_string("sentence_mode_subtitle", _game_state.selected_language)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.modulate = JellyTheme.text_color(COL_MUTE)
	vbox.add_child(subtitle)

	_sentence_label = Label.new()
	_sentence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sentence_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_sentence_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_sentence_label)

	_input_edit = LineEdit.new()
	_input_edit.custom_minimum_size = Vector2(0, 56)
	_input_edit.add_theme_font_size_override("font_size", 22)
	_input_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input_edit.context_menu_enabled = false
	_input_edit.text_changed.connect(_on_text_changed)
	_input_edit.text_submitted.connect(_on_text_submitted)
	vbox.add_child(_input_edit)

	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 18)
	_result_label.modulate = JellyTheme.text_color(COL_GOLD)
	vbox.add_child(_result_label)

	var button_row = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 16)
	vbox.add_child(button_row)

	_next_btn = _make_button("NEXT SENTENCE", COL_MINT)
	_next_btn.pressed.connect(_load_new_sentence)
	button_row.add_child(_next_btn)

	_close_btn = _make_button("CLOSE", COL_GOLD)
	_close_btn.pressed.connect(close)
	button_row.add_child(_close_btn)

func _make_button(txt: String, tint: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_size_override("font_size", 18)
	var normal := _asset_button_style("res://assets/items/ui/button_rectangle.png", tint, 0.85)
	b.add_theme_stylebox_override("normal", normal)
	var hover := _asset_button_style("res://assets/items/ui/button_rectangle.png", tint, 1.05)
	b.add_theme_stylebox_override("hover", hover)
	var pressed_style := _asset_button_style("res://assets/items/ui/button_rectangle_depth.png", tint, 1.0)
	b.add_theme_stylebox_override("pressed", pressed_style)
	return b

func _asset_button_style(texture_path: String, tint: Color, brightness: float) -> StyleBox:
	return JellyTheme.button_style(tint, brightness, texture_path.contains("depth"))

func _current_theme() -> String:
	if is_instance_valid(_game_state) and String(_game_state.selected_theme) != "":
		return _game_state.selected_theme
	return "General"

func _load_new_sentence() -> void:
	_current_sentence = SentenceBank.random_sentence(_current_theme(), 90, _rng)
	_sentence_label.text = _current_sentence
	_input_edit.text = ""
	_result_label.text = ""
	_typing_started = false
	_input_edit.modulate = Color.WHITE
	if is_instance_valid(_input_edit):
		_input_edit.call_deferred("grab_focus")

func _on_text_changed(new_text: String) -> void:
	if not _typing_started and new_text.length() > 0:
		_typing_started = true
		_start_msec = Time.get_ticks_msec()

	if new_text == _current_sentence:
		_finish_sentence()
	elif _current_sentence.begins_with(new_text):
		_input_edit.modulate = Color.WHITE
	else:
		_input_edit.modulate = COL_RED

func _on_text_submitted(new_text: String) -> void:
	if new_text == _current_sentence:
		_finish_sentence()

func _finish_sentence() -> void:
	var elapsed_min = max((Time.get_ticks_msec() - _start_msec) / 60000.0, 1.0 / 60.0)
	var word_count = SentenceBank.standard_word_count(_current_sentence)
	var wpm = word_count / elapsed_min
	_result_label.text = LocalizationManager.get_string("sentence_result", _game_state.selected_language) % wpm
	_result_label.modulate = JellyTheme.text_color(COL_GOLD)
	if is_instance_valid(_game_state):
		# Tracks lifetime sentence count (for the new sentence-practice
		# missions) and only ever raises best_wpm, never lowers it -
		# consistent with how GameState already tracks best_wpm from
		# normal runs.
		_game_state.register_sentence_practice(wpm)
	if is_instance_valid(_mission_manager):
		_mission_manager.evaluate_sentence_practice(wpm)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func open() -> void:
	move_to_front()
	visible = true
	_load_new_sentence()
	modulate.a = 0.0
	if is_instance_valid(_card):
		_card.scale = Vector2(0.94, 0.94)
		_card.pivot_offset = _card.size / 2
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	if is_instance_valid(_card):
		tw.parallel().tween_property(_card, "scale", Vector2(1.0, 1.0), 0.3)

func close() -> void:
	visible = false
	closed.emit()
