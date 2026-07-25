class_name VersusMode
extends VBoxContainer

## Local pass-and-play 2-player race, embedded inside MoreScreen's content
## panel (same pattern PracticeSession uses). Both players type the exact
## same word list, one after the other ("pass the phone"), and the winner
## is whoever finishes with the higher WPM (ties broken by accuracy).

signal finished()
signal stopped()

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MINT := Color(0.4, 0.9, 0.75)
const COL_MUTE := Color(1, 1, 1, 0.55)
const COL_RED := Color(0.85, 0.35, 0.35)
const COL_SKY := Color(0.45, 0.7, 0.95)
const COL_P1 := Color(0.45, 0.7, 0.95)
const COL_P2 := Color(0.95, 0.6, 0.25)

const WORD_COUNT := 15

# Persistent scoreboard tracker (persists across match rematches during the session)
static var session_p1_wins := 0
static var session_p2_wins := 0

var _game_state: GameState
var _audio: AudioManager
var _mission_manager: MissionManager

var _word_list: Array = []
var _current_player := 1
var _stage := "ready"   # "setup" -> "ready" -> "playing" -> "results"

# Player Settings
var _p1_name := "Player 1"
var _p2_name := "Player 2"
var _selected_theme_name := "Mix"
var _sudden_death_enabled := false

# Run stats
var _queue_index := 0
var _current_word := ""
var _hits := 0
var _misses := 0
var _words_typed := 0
var _start_msec := 0
var _running := false

# Ghost pacing & word-by-word analysis
var _p1_word_timestamps: Array = []
var _current_word_start_msec := 0
var _word_timings: Array = [] # Stores float seconds spent on each word

var _p1_result := {}
var _p2_result := {}

var _title_label: Label
var _subtitle_label: Label
var _body_holder: VBoxContainer


func configure(game_state: GameState, audio: AudioManager, mission_manager: MissionManager = null) -> void:
	_game_state = game_state
	_audio = audio
	_mission_manager = mission_manager
	add_theme_constant_override("separation", 10)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", COL_GOLD)
	add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_subtitle_label.add_theme_font_size_override("font_size", 15)
	_subtitle_label.modulate = COL_MUTE
	add_child(_subtitle_label)

	_body_holder = VBoxContainer.new()
	_body_holder.add_theme_constant_override("separation", 12)
	add_child(_body_holder)

	_show_setup_screen()


func _clear_body() -> void:
	for c in _body_holder.get_children():
		c.queue_free()


# --- Setup Screen (Names, Theme, & Sudden Death) ---

func _show_setup_screen() -> void:
	_stage = "setup"
	_clear_body()

	_title_label.text = LocalizationManager.get_string("versus_mode_title", _game_state.selected_language).to_upper()
	_title_label.add_theme_color_override("font_color", COL_GOLD)
	_subtitle_label.text = "Configure your 2-player typing duel."

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.05)
	style.set_corner_radius_all(16)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	_body_holder.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	# Name Input P1
	var p1_row := HBoxContainer.new()
	p1_row.add_theme_constant_override("separation", 10)
	vb.add_child(p1_row)
	
	var p1_lbl := Label.new()
	p1_lbl.text = "P1 Name:"
	p1_lbl.custom_minimum_size = Vector2(100, 0)
	p1_lbl.add_theme_color_override("font_color", COL_P1)
	p1_row.add_child(p1_lbl)
	
	var p1_input := LineEdit.new()
	p1_input.text = _p1_name
	p1_input.placeholder_text = "Player 1"
	p1_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p1_row.add_child(p1_input)

	# Name Input P2
	var p2_row := HBoxContainer.new()
	p2_row.add_theme_constant_override("separation", 10)
	vb.add_child(p2_row)
	
	var p2_lbl := Label.new()
	p2_lbl.text = "P2 Name:"
	p2_lbl.custom_minimum_size = Vector2(100, 0)
	p2_lbl.add_theme_color_override("font_color", COL_P2)
	p2_row.add_child(p2_lbl)
	
	var p2_input := LineEdit.new()
	p2_input.text = _p2_name
	p2_input.placeholder_text = "Player 2"
	p2_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p2_row.add_child(p2_input)

	# Theme Selector
	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 10)
	vb.add_child(theme_row)

	var theme_lbl := Label.new()
	theme_lbl.text = "Category:"
	theme_lbl.custom_minimum_size = Vector2(100, 0)
	theme_lbl.modulate = COL_MUTE
	theme_row.add_child(theme_lbl)

	var theme_opt := OptionButton.new()
	theme_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_opt.add_item("Mix")
	for theme_name in WordBank.theme_names():
		theme_opt.add_item(theme_name)
	theme_row.add_child(theme_opt)

	# Sudden Death Mode Button Toggle
	var sd_row := HBoxContainer.new()
	sd_row.add_theme_constant_override("separation", 10)
	vb.add_child(sd_row)

	var sd_lbl := Label.new()
	sd_lbl.text = "Hardcore:"
	sd_lbl.custom_minimum_size = Vector2(100, 0)
	sd_lbl.modulate = COL_MUTE
	sd_row.add_child(sd_lbl)

	var sd_btn := Button.new()
	sd_btn.toggle_mode = true
	sd_btn.text = "SUDDEN DEATH: OFF"
	sd_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sd_row.add_child(sd_btn)
	sd_btn.toggled.connect(func(pressed):
		_sudden_death_enabled = pressed
		if pressed:
			sd_btn.text = "SUDDEN DEATH: ON (1 Typo = Eliminated)"
			sd_btn.add_theme_color_override("font_color", COL_RED)
		else:
			sd_btn.text = "SUDDEN DEATH: OFF"
			sd_btn.remove_theme_color_override("font_color")
	)

	# Continue Button
	var next_btn := Button.new()
	next_btn.text = "NEXT"
	next_btn.custom_minimum_size = Vector2(0, 48)
	next_btn.add_theme_font_size_override("font_size", 18)
	_body_holder.add_child(next_btn)
	next_btn.pressed.connect(func():
		_p1_name = p1_input.text if p1_input.text.strip_edges() != "" else "Player 1"
		_p2_name = p2_input.text if p2_input.text.strip_edges() != "" else "Player 2"
		_selected_theme_name = theme_opt.get_item_text(theme_opt.selected)
		
		# Generate word list
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var pool: Array = []
		if _selected_theme_name == "Mix":
			pool = WordBank.pool_for_theme_mix(WordBank.theme_names())
		else:
			pool = WordBank.pool_for_theme_mix([_selected_theme_name])
		_word_list = WordBank.get_batch(pool, WORD_COUNT, rng)
		
		if _audio: _audio.play_whoosh()
		_show_ready_screen(1)
	)

	var stop_btn := Button.new()
	stop_btn.text = LocalizationManager.get_string("cancel_versus", _game_state.selected_language)
	stop_btn.flat = true
	stop_btn.add_theme_font_size_override("font_size", 14)
	stop_btn.modulate = COL_MUTE
	_body_holder.add_child(stop_btn)
	stop_btn.pressed.connect(func():
		stopped.emit()
	)


# --- Pass-the-phone / ready screens ---

func _show_ready_screen(player: int) -> void:
	_stage = "ready"
	_current_player = player
	_clear_body()

	var tint = COL_P1 if player == 1 else COL_P2
	var current_player_name = _p1_name if player == 1 else _p2_name
	
	_title_label.text = LocalizationManager.get_string("versus_mode_title", _game_state.selected_language).to_upper()
	_title_label.add_theme_color_override("font_color", tint)

	# Session Leaderboard display if matches have been completed
	if session_p1_wins > 0 or session_p2_wins > 0:
		_subtitle_label.text = "Session Score: %s (%d) vs %s (%d)" % [_p1_name, session_p1_wins, _p2_name, session_p2_wins]
	else:
		_subtitle_label.text = LocalizationManager.get_string("versus_subtitle_intro", _game_state.selected_language) % WORD_COUNT

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.05)
	style.set_corner_radius_all(16)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	_body_holder.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var big := Label.new()
	big.text = current_player_name.to_upper()
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.add_theme_font_size_override("font_size", 30)
	big.add_theme_color_override("font_color", tint)
	vb.add_child(big)

	var hint := Label.new()
	hint.text = LocalizationManager.get_string("get_ready_hint", _game_state.selected_language)
	if _sudden_death_enabled:
		hint.text += " — SUDDEN DEATH MODE IS ON!"
		hint.add_theme_color_override("font_color", COL_RED)
	else:
		hint.modulate = COL_MUTE
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 15)
	vb.add_child(hint)

	if player == 2 and not _p1_result.is_empty():
		var recap := Label.new()
		recap.text = "%s's Run Result:\n%.1f WPM (%.1f%% Accuracy)" % [_p1_name, _p1_result.get("wpm", 0.0), _p1_result.get("accuracy", 0.0)]
		recap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		recap.add_theme_font_size_override("font_size", 14)
		recap.modulate = COL_P1
		vb.add_child(recap)

	var start_btn := Button.new()
	start_btn.text = LocalizationManager.get_string("im_ready_start", _game_state.selected_language).to_upper()
	start_btn.custom_minimum_size = Vector2(0, 48)
	start_btn.add_theme_font_size_override("font_size", 18)
	_body_holder.add_child(start_btn)
	start_btn.pressed.connect(func():
		if _audio: _audio.play_whoosh()
		_start_race(player)
	)

	var stop_btn := Button.new()
	stop_btn.text = "Back to Setup" if player == 1 else "Cancel Duel"
	stop_btn.flat = true
	stop_btn.add_theme_font_size_override("font_size", 14)
	stop_btn.modulate = COL_MUTE
	_body_holder.add_child(stop_btn)
	stop_btn.pressed.connect(func():
		if player == 1:
			_show_setup_screen()
		else:
			stopped.emit()
	)


# --- Racing ---

var _word_label: Label
var _input_edit: LineEdit
var _stats_label: Label
var _timer_label: Label
var _ghost_tracker_bar: ProgressBar

func _start_race(player: int) -> void:
	_stage = "playing"
	_current_player = player
	_clear_body()

	var tint = COL_P1 if player == 1 else COL_P2
	var current_player_name = _p1_name if player == 1 else _p2_name
	_subtitle_label.text = "Typing Focus: %s" % current_player_name

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 16)
	_body_holder.add_child(stats_row)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 14)
	_stats_label.modulate = COL_MINT
	stats_row.add_child(_stats_label)

	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 14)
	_timer_label.modulate = COL_SKY
	_timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_row.add_child(_timer_label)

	# Ghost Pace Tracker (Player 2 exclusive)
	if player == 2 and not _p1_word_timestamps.is_empty():
		var ghost_vbox := VBoxContainer.new()
		ghost_vbox.add_theme_constant_override("separation", 2)
		_body_holder.add_child(ghost_vbox)

		var ghost_lbl := Label.new()
		ghost_lbl.text = "VERSUS PACE (VS %s)" % _p1_name.to_upper()
		ghost_lbl.add_theme_font_size_override("font_size", 10)
		ghost_lbl.modulate = COL_MUTE
		ghost_vbox.add_child(ghost_lbl)

		_ghost_tracker_bar = ProgressBar.new()
		_ghost_tracker_bar.min_value = 0
		_ghost_tracker_bar.max_value = WORD_COUNT
		_ghost_tracker_bar.value = 0
		_ghost_tracker_bar.custom_minimum_size = Vector2(0, 14)
		_ghost_tracker_bar.show_percentage = false
		ghost_vbox.add_child(_ghost_tracker_bar)

	var word_panel := PanelContainer.new()
	var word_style := StyleBoxFlat.new()
	word_style.bg_color = Color(1, 1, 1, 0.05)
	word_style.set_corner_radius_all(16)
	word_style.content_margin_left = 20
	word_style.content_margin_right = 20
	word_style.content_margin_top = 18
	word_style.content_margin_bottom = 18
	word_panel.add_theme_stylebox_override("panel", word_style)
	_body_holder.add_child(word_panel)

	_word_label = Label.new()
	_word_label.add_theme_font_size_override("font_size", 30)
	_word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_word_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_word_label.add_theme_color_override("font_color", tint)
	word_panel.add_child(_word_label)

	_input_edit = LineEdit.new()
	_input_edit.placeholder_text = "Type it here…"
	_input_edit.add_theme_font_size_override("font_size", 20)
	_body_holder.add_child(_input_edit)
	_input_edit.text_changed.connect(_on_text_changed)
	_input_edit.text_submitted.connect(_on_text_submitted)

	_hits = 0
	_misses = 0
	_words_typed = 0
	_queue_index = 0
	_start_msec = Time.get_ticks_msec()
	_current_word_start_msec = _start_msec
	_running = true
	_word_timings.clear()

	if player == 1:
		_p1_word_timestamps.clear()

	_advance_word()
	_update_stats_label()
	call_deferred("_focus_input")


func _focus_input() -> void:
	if is_instance_valid(_input_edit):
		_input_edit.grab_focus()


func _process(_delta: float) -> void:
	if not _running or _stage != "playing":
		return
	var elapsed = (Time.get_ticks_msec() - _start_msec) / 1000.0
	_timer_label.text = "Time: %.1fs" % elapsed

	# Update Ghost pace tracker
	if _current_player == 2 and is_instance_valid(_ghost_tracker_bar):
		_ghost_tracker_bar.value = _words_typed


func _advance_word() -> void:
	if _queue_index >= _word_list.size():
		_finish_turn()
		return
	_current_word = String(_word_list[_queue_index]).to_upper()
	_queue_index += 1
	_word_label.text = _current_word
	_word_label.modulate = Color.WHITE
	_input_edit.text = ""
	_current_word_start_msec = Time.get_ticks_msec()


func _on_text_changed(new_text: String) -> void:
	if not _running:
		return
	var typed := new_text.to_upper()
	_word_label.modulate = Color.WHITE if _current_word.begins_with(typed) else COL_RED
	
	if typed == _current_word:
		_submit_word(true)
	elif _sudden_death_enabled and not _current_word.begins_with(typed) and typed.length() > 0:
		# Immediate elimination check
		_submit_word(false)


func _on_text_submitted(new_text: String) -> void:
	if not _running:
		return
	_submit_word(new_text.to_upper() == _current_word)


func _submit_word(is_correct: bool) -> void:
	var now = Time.get_ticks_msec()
	var duration = (now - _current_word_start_msec) / 1000.0
	
	if is_correct:
		_hits += 1
		_words_typed += 1
		_word_timings.append({"word": _current_word, "time": duration})
		if _audio: _audio.play_success()
		
		if _current_player == 1:
			_p1_word_timestamps.append(now - _start_msec)
		_update_stats_label()
		_advance_word()
	else:
		_misses += 1
		if _audio: _audio.play_error()
		if is_instance_valid(_game_state):
			_game_state._add_persistent_missed_word(_current_word)
			
		if _sudden_death_enabled:
			# Abort run immediately in Sudden Death
			_running = false
			_finish_turn()
		else:
			_update_stats_label()
			_advance_word()


func _update_stats_label() -> void:
	var total = _hits + _misses
	var acc = 100.0 if total <= 0 else (float(_hits) / total) * 100.0
	var label = "SUDDEN DEATH!" if _sudden_death_enabled else LocalizationManager.get_string("words_label", _game_state.selected_language)
	_stats_label.text = LocalizationManager.get_string("words_progress_accuracy_stat", _game_state.selected_language) % [label, _words_typed, _word_list.size(), LocalizationManager.get_string("accuracy", _game_state.selected_language), acc]


func _finish_turn() -> void:
	_running = false
	if is_instance_valid(_input_edit):
		_input_edit.editable = false
	var elapsed = max((Time.get_ticks_msec() - _start_msec) / 1000.0, 0.05)
	var total = _hits + _misses
	var acc = 100.0 if total <= 0 else (float(_hits) / total) * 100.0
	var wpm = (_words_typed / (elapsed / 60.0)) if elapsed > 0 else 0.0

	var fastest = {"word": "None", "time": 999.0}
	var slowest = {"word": "None", "time": 0.0}
	for timing in _word_timings:
		if timing.time < fastest.time:
			fastest = timing
		if timing.time > slowest.time:
			slowest = timing

	var result := {
		"words_typed": _words_typed,
		"accuracy": acc,
		"wpm": wpm,
		"time": elapsed,
		"fastest_word": fastest.word if _words_typed > 0 else "None",
		"fastest_time": fastest.time if _words_typed > 0 else 0.0,
		"slowest_word": slowest.word if _words_typed > 0 else "None",
		"slowest_time": slowest.time if _words_typed > 0 else 0.0,
	}

	if _current_player == 1:
		_p1_result = result
		_show_ready_screen(2)
	else:
		_p2_result = result
		_show_results()


# --- Results & Leaderboards ---

func _show_results() -> void:
	_stage = "results"
	_clear_body()

	var p1_wins: bool = _p1_result.get("wpm", 0.0) > _p2_result.get("wpm", 0.0)
	var tie := is_equal_approx(_p1_result.get("wpm", 0.0), _p2_result.get("wpm", 0.0))
	if tie:
		p1_wins = _p1_result.get("accuracy", 0.0) >= _p2_result.get("accuracy", 0.0)

	var exact_tie := tie and is_equal_approx(_p1_result.get("accuracy", 0.0), _p2_result.get("accuracy", 0.0))
	
	# Update session-level Win Streak Counter
	if not exact_tie:
		if p1_wins:
			session_p1_wins += 1
		else:
			session_p2_wins += 1

	_title_label.text = LocalizationManager.get_string("versus_results_title", _game_state.selected_language).to_upper()
	_title_label.add_theme_color_override("font_color", COL_GOLD)
	
	if exact_tie:
		_subtitle_label.text = LocalizationManager.get_string("exact_tie_msg", _game_state.selected_language)
	else:
		_subtitle_label.text = "%s wins the duel! 🏆" % (_p1_name if p1_wins else _p2_name)

	# Session Leaderboard Row
	var board_panel := PanelContainer.new()
	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color(1, 1, 1, 0.02)
	b_style.set_corner_radius_all(10)
	b_style.content_margin_top = 6
	b_style.content_margin_bottom = 6
	board_panel.add_theme_stylebox_override("panel", b_style)
	_body_holder.add_child(board_panel)

	var board_lbl := Label.new()
	board_lbl.text = "🏆 SESSION SCOREBOARD:  %s (%d)   -   %s (%d)" % [_p1_name.to_upper(), session_p1_wins, _p2_name.to_upper(), session_p2_wins]
	board_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board_lbl.add_theme_font_size_override("font_size", 13)
	board_lbl.add_theme_color_override("font_color", COL_GOLD)
	board_panel.add_child(board_lbl)

	if _audio:
		if exact_tie:
			_audio.play_notification()
		else:
			_audio.play_level_up_sting()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_body_holder.add_child(row)

	row.add_child(_build_result_card(_p1_name.to_upper(), COL_P1, _p1_result, p1_wins))
	row.add_child(_build_result_card(_p2_name.to_upper(), COL_P2, _p2_result, not p1_wins))

	if is_instance_valid(_game_state):
		var better = _p1_result if p1_wins else _p2_result
		_game_state.register_practice_result("Versus Mode", better.get("wpm", 0.0), better.get("accuracy", 0.0), better.get("words_typed", 0))
		_game_state.register_versus_match()

	if is_instance_valid(_mission_manager):
		var newly_completed: Array = _mission_manager.evaluate_versus_played()
		if not newly_completed.is_empty():
			var texts: Array = []
			for m in newly_completed:
				texts.append(String(m.get("text", "")))
			var mission_note := Label.new()
			mission_note.text = LocalizationManager.get_string("career_mission_complete", _game_state.selected_language) % ", ".join(texts)
			mission_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mission_note.autowrap_mode = TextServer.AUTOWRAP_WORD
			mission_note.add_theme_font_size_override("font_size", 14)
			mission_note.modulate = COL_GOLD
			_body_holder.add_child(mission_note)

	var share_feedback := Label.new()
	share_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	share_feedback.add_theme_font_size_override("font_size", 13)
	share_feedback.modulate = COL_MINT

	var share_btn := Button.new()
	share_btn.text = LocalizationManager.get_string("share_result", _game_state.selected_language)
	_body_holder.add_child(share_btn)
	share_btn.pressed.connect(func():
		var winner_txt = "Tie" if exact_tie else ("%s" % _p1_name if p1_wins else "%s" % _p2_name)
		var text = "Versus Match (%s) on Keys: %s (%.0f WPM) vs %s (%.0f WPM) — %s wins! 🆚" % \
			[_selected_theme_name, _p1_name, _p1_result.get("wpm", 0.0), _p2_name, _p2_result.get("wpm", 0.0), winner_txt]
		DisplayServer.clipboard_set(text)
		share_feedback.text = LocalizationManager.get_string("share_copied", _game_state.selected_language)
		if not share_feedback.is_inside_tree():
			_body_holder.add_child(share_feedback)
	)

	var done_btn := Button.new()
	done_btn.text = LocalizationManager.get_string("done", _game_state.selected_language).to_upper()
	done_btn.custom_minimum_size = Vector2(0, 48)
	_body_holder.add_child(done_btn)
	done_btn.pressed.connect(func():
		finished.emit()
	)

	var rematch_btn := Button.new()
	rematch_btn.text = "REMATCH (SAME WORDS)"
	rematch_btn.flat = true
	rematch_btn.modulate = COL_MUTE
	_body_holder.add_child(rematch_btn)
	rematch_btn.pressed.connect(func():
		_p1_result = {}
		_p2_result = {}
		_show_ready_screen(1)
	)


func _build_result_card(label_txt: String, tint: Color, result: Dictionary, is_winner: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.bg_color.a = 0.18 if is_winner else 0.05
	style.set_corner_radius_all(14)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	if is_winner:
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = tint
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	var header := Label.new()
	header.text = ("★ " if is_winner else "") + label_txt
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", tint)
	vb.add_child(header)

	var wpm_lbl := Label.new()
	wpm_lbl.text = LocalizationManager.get_string("wpm_value", _game_state.selected_language) % result.get("wpm", 0.0)
	wpm_lbl.add_theme_font_size_override("font_size", 22)
	vb.add_child(wpm_lbl)

	var acc_lbl := Label.new()
	acc_lbl.text = LocalizationManager.get_string("accuracy_value", _game_state.selected_language) % result.get("accuracy", 0.0)
	acc_lbl.add_theme_font_size_override("font_size", 14)
	acc_lbl.modulate = COL_MUTE
	vb.add_child(acc_lbl)

	var time_lbl := Label.new()
	time_lbl.text = "Time: %.1fs" % result.get("time", 0.0)
	time_lbl.add_theme_font_size_override("font_size", 13)
	time_lbl.modulate = COL_MUTE
	vb.add_child(time_lbl)

	# Divider line
	var div := ColorRect.new()
	div.color = Color(1, 1, 1, 0.1)
	div.custom_minimum_size = Vector2(0, 1)
	vb.add_child(div)

	# Performance Breakdowns
	var fastest_lbl := Label.new()
	fastest_lbl.text = "⚡ %s (%.2fs)" % [result.get("fastest_word", "None"), result.get("fastest_time", 0.0)]
	fastest_lbl.add_theme_font_size_override("font_size", 11)
	fastest_lbl.modulate = COL_MINT
	vb.add_child(fastest_lbl)

	var slowest_lbl := Label.new()
	slowest_lbl.text = "🐢 %s (%.2fs)" % [result.get("slowest_word", "None"), result.get("slowest_time", 0.0)]
	slowest_lbl.add_theme_font_size_override("font_size", 11)
	slowest_lbl.modulate = COL_RED
	vb.add_child(slowest_lbl)

	return panel
