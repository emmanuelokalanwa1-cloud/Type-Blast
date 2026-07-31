class_name DictationScreen
extends ColorRect

## Standalone "listen and type" practice mode, built the same safe way as
## SentenceModeScreen: its own simple Label + LineEdit screen, NOT wired
## into the falling-word game loop, so it can't destabilize existing
## gameplay code. Uses Godot's built-in DisplayServer TTS - no external
## dependency, no bundled audio files needed. The sentence stays hidden
## until the player finishes (or gives up), since seeing it would defeat
## the point of typing from what they heard.

signal closed()

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MINT := Color(0.4, 0.9, 0.75)
const COL_MUTE := Color(1, 1, 1, 0.55)
const COL_RED := Color(0.85, 0.35, 0.35)
const COL_SKY := Color(0.4, 0.7, 1.0)

var _game_state: GameState
var _card: PanelContainer
var _status_label: Label
var _input_edit: LineEdit
var _result_label: Label
var _replay_btn: Button
var _reveal_btn: Button
var _next_btn: Button
var _close_btn: Button

var _current_sentence := ""
var _revealed := false
var _rng := RandomNumberGenerator.new()
var _theme_keep_child_count := 0  # children added before the first _build_ui() call, preserved across refresh_theme()

func setup(root: Control, game_state: GameState) -> void:
	_game_state = game_state
	_rng.randomize()
	color = Color(0.015, 0.016, 0.03, 0.97)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	root.add_child(self)
	_theme_keep_child_count = get_child_count()
	_build_ui()

## Re-runs _build_ui() so this screen picks up a new Casual/Jelly/Arcade
## interface style immediately instead of staying on whatever skin was
## active when the app booted. This screen (like Tutorial) used to be
## built once at startup and never wired into GameState.ui_style_changed,
## so changing the style in More > Settings and then opening Dictation
## Mode in the same session showed the OLD skin - the style only "finished"
## applying here once the app was fully closed and relaunched, which is
## what looked like a stuck/incomplete theme switch.
func refresh_theme() -> void:
	var was_open := visible
	if DisplayServer.tts_is_speaking():
		DisplayServer.tts_stop()
	JellyTheme.trim_rebuildable_children(self, _theme_keep_child_count)
	_build_ui()
	# Restore whatever was on screen instead of blanking mid-session -
	# _load_new_passage() would otherwise wipe an in-progress attempt.
	_status_label.text = _current_sentence if _revealed else "🔊 Listen carefully..."
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
	title.text = "DICTATION MODE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.modulate = JellyTheme.text_color(COL_MINT)
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Listen, then type exactly what you heard. No peeking!"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.modulate = JellyTheme.text_color(COL_MUTE)
	vbox.add_child(subtitle)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.modulate = JellyTheme.text_color(COL_SKY)
	vbox.add_child(_status_label)

	_input_edit = LineEdit.new()
	_input_edit.custom_minimum_size = Vector2(0, 56)
	_input_edit.add_theme_font_size_override("font_size", 22)
	_input_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input_edit.context_menu_enabled = false
	_input_edit.text_submitted.connect(_on_text_submitted)
	vbox.add_child(_input_edit)

	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_result_label.add_theme_font_size_override("font_size", 18)
	_result_label.modulate = JellyTheme.text_color(COL_GOLD)
	vbox.add_child(_result_label)

	var button_row = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 14)
	vbox.add_child(button_row)

	_replay_btn = _make_button("🔊 REPLAY", COL_SKY)
	_replay_btn.pressed.connect(_speak_current)
	button_row.add_child(_replay_btn)

	_reveal_btn = _make_button("👁 REVEAL", COL_GOLD)
	_reveal_btn.pressed.connect(_reveal)
	button_row.add_child(_reveal_btn)

	_next_btn = _make_button("NEXT", COL_MINT)
	_next_btn.pressed.connect(_load_new_passage)
	button_row.add_child(_next_btn)

	_close_btn = _make_button("CLOSE", COL_RED)
	_close_btn.pressed.connect(close)
	button_row.add_child(_close_btn)

func _make_button(txt: String, tint: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 15)
	var normal := JellyTheme.button_style(tint, 0.85, false)
	b.add_theme_stylebox_override("normal", normal)
	var hover := JellyTheme.button_style(tint, 1.05, false)
	b.add_theme_stylebox_override("hover", hover)
	var pressed_style := JellyTheme.button_style(tint, 1.0, true)
	b.add_theme_stylebox_override("pressed", pressed_style)
	return b

func _current_theme() -> String:
	if is_instance_valid(_game_state) and String(_game_state.selected_theme) != "":
		return _game_state.selected_theme
	return "General"

func _load_new_passage() -> void:
	_current_sentence = SentenceBank.random_sentence(_current_theme(), 70, _rng)
	_revealed = false
	_input_edit.text = ""
	_input_edit.modulate = Color.WHITE
	_result_label.text = ""
	_status_label.text = "🔊 Listen carefully..."
	if is_instance_valid(_input_edit):
		_input_edit.call_deferred("grab_focus")
	_speak_current()

func _speak_current() -> void:
	if _current_sentence == "":
		return
	if DisplayServer.tts_is_speaking():
		DisplayServer.tts_stop()
	DisplayServer.tts_speak(_current_sentence, "", 0, 1.0, 0.95)

func _reveal() -> void:
	_revealed = true
	_status_label.text = _current_sentence

func _on_text_submitted(new_text: String) -> void:
	var correct := new_text.strip_edges() == _current_sentence.strip_edges()
	if correct:
		_result_label.text = "✅ Correct! Nice listening."
		_result_label.modulate = JellyTheme.text_color(COL_MINT)
		_input_edit.modulate = COL_MINT
	else:
		_result_label.text = "Not quite. Try REPLAY, or REVEAL to check."
		_result_label.modulate = JellyTheme.text_color(COL_RED)
		_input_edit.modulate = COL_RED

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func open() -> void:
	move_to_front()
	visible = true
	_load_new_passage()
	modulate.a = 0.0
	if is_instance_valid(_card):
		_card.scale = Vector2(0.94, 0.94)
		_card.pivot_offset = _card.size / 2
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	if is_instance_valid(_card):
		tw.parallel().tween_property(_card, "scale", Vector2(1.0, 1.0), 0.3)

func close() -> void:
	if DisplayServer.tts_is_speaking():
		DisplayServer.tts_stop()
	visible = false
	closed.emit()
