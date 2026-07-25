class_name PracticeSession
extends VBoxContainer

## Generic word-by-word typing engine, embedded inside MoreScreen's content
## panel (not a top-level screen — MoreScreen owns the backdrop/close
## button). One engine, six modes, all driven by a config dictionary so
## none of them needed their own copy-pasted typing loop:
##
##   "zen"         - untimed, no lives, infinite words, just relax and type
##   "drill"       - finite list built from GameState.missed_words_persistent
##   "custom"      - finite list built from GameState.custom_word_list
##   "typing_test" - fixed duration (60s/180s), standard WPM at the end
##   "daily"       - finite list from WordBank.get_daily_words() (date-seeded,
##                   same for everyone that day), one graded attempt/day
##   "boss"        - long words, 3 lives, a shrinking per-word timer
##   "survival"    - endless mixed-length words, 3 lives, timer shrinks
##                   gradually every 10 correct words (gentler ramp than
##                   Boss); tracks an all-time best streak
##
## Deliberately doesn't touch score/lives/high_scores/career state — it
## only ever reads GameState and, at the very end, calls
## GameState.register_practice_result() / register_miss() /
## _add_persistent_missed_word() through public methods. It can't corrupt
## normal-run stats or missions.

signal finished(result: Dictionary)
signal stopped()

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MINT := Color(0.4, 0.9, 0.75)
const COL_MUTE := Color(1, 1, 1, 0.55)
const COL_RED := Color(0.85, 0.35, 0.35)
const COL_SKY := Color(0.45, 0.7, 0.95)

var _game_state: GameState
var _audio: AudioManager
var _cfg: Dictionary

var _word_queue: Array = []
var _queue_index := 0
var _infinite_pool: Array = []
var _current_word := ""
var _rng := RandomNumberGenerator.new()

var _hits := 0
var _misses := 0
var _words_typed := 0
var _start_msec := 0
var _running := false

var _duration := 0.0        # 0 = untimed / ends when queue exhausted
var _time_left := 0.0
var _lives := 0             # 0 = can't fail
var _boss_stage := 0
var _boss_word_limit := 6.0

var _title_label: Label
var _subtitle_label: Label
var _word_label: Label
var _input_edit: LineEdit
var _stats_label: Label
var _timer_label: Label
var _lives_label: Label
var _result_label: Label
var _finish_btn: Button


func configure(cfg: Dictionary, game_state: GameState, audio: AudioManager) -> void:
	_cfg = cfg
	_game_state = game_state
	_audio = audio
	_rng.randomize()
	add_theme_constant_override("separation", 10)
	_build_ui()
	_start()


func _build_ui() -> void:
	_title_label = Label.new()
	_title_label.text = _cfg.get("title", "Practice")
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", COL_GOLD)
	add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.text = _cfg.get("subtitle", "")
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_subtitle_label.add_theme_font_size_override("font_size", 15)
	_subtitle_label.modulate = COL_MUTE
	add_child(_subtitle_label)

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 16)
	add_child(stats_row)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 14)
	_stats_label.modulate = COL_MINT
	stats_row.add_child(_stats_label)

	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 14)
	_timer_label.modulate = COL_SKY
	stats_row.add_child(_timer_label)

	_lives_label = Label.new()
	_lives_label.add_theme_font_size_override("font_size", 14)
	_lives_label.modulate = COL_RED
	stats_row.add_child(_lives_label)

	var word_panel := PanelContainer.new()
	var word_style := StyleBoxFlat.new()
	word_style.bg_color = Color(1, 1, 1, 0.05)
	word_style.set_corner_radius_all(16)
	word_style.content_margin_left = 20
	word_style.content_margin_right = 20
	word_style.content_margin_top = 18
	word_style.content_margin_bottom = 18
	word_panel.add_theme_stylebox_override("panel", word_style)
	add_child(word_panel)

	_word_label = Label.new()
	_word_label.add_theme_font_size_override("font_size", 30)
	_word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_word_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	word_panel.add_child(_word_label)

	_input_edit = LineEdit.new()
	_input_edit.placeholder_text = "Type it here…"
	_input_edit.add_theme_font_size_override("font_size", 20)
	add_child(_input_edit)
	_input_edit.text_changed.connect(_on_text_changed)
	_input_edit.text_submitted.connect(_on_text_submitted)

	_result_label = Label.new()
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_result_label.add_theme_font_size_override("font_size", 16)
	_result_label.modulate = COL_GOLD
	add_child(_result_label)

	_finish_btn = Button.new()
	_finish_btn.text = LocalizationManager.get_string("stop", _game_state.selected_language).to_upper()
	_finish_btn.custom_minimum_size = Vector2(0, 44)
	add_child(_finish_btn)
	_finish_btn.pressed.connect(_on_stop_pressed)


func _start() -> void:
	_hits = 0
	_misses = 0
	_words_typed = 0
	_start_msec = Time.get_ticks_msec()
	_running = true
	_duration = _cfg.get("duration", 0.0)
	_time_left = _duration
	_lives = _cfg.get("lives", 0)
	_boss_stage = 0
	_boss_word_limit = 6.0

	var words = _cfg.get("words", [])
	if words is Array and not words.is_empty():
		_word_queue = words.duplicate()
	else:
		_word_queue = []
	_queue_index = 0
	_infinite_pool = _cfg.get("infinite_pool", [])

	if _lives > 0:
		_lives_label.text = "♥ %d" % _lives
	else:
		_lives_label.text = ""

	if _word_queue.is_empty() and _infinite_pool.is_empty():
		_word_label.text = ""
		_subtitle_label.text = _cfg.get("empty_message", "Nothing to practice yet.")
		_input_edit.editable = false
		_running = false
		return

	_advance_word()
	_update_stats_label()
	_update_timer_label()
	call_deferred("_focus_input")


func _focus_input() -> void:
	if is_instance_valid(_input_edit):
		_input_edit.grab_focus()


func _process(delta: float) -> void:
	if not _running:
		return
	if _duration > 0.0:
		_time_left -= delta
		_update_timer_label()
		if _time_left <= 0.0:
			_finish(false)
			return
	var mode_now: String = _cfg.get("mode", "")
	if (mode_now == "boss" or mode_now == "survival") and _boss_word_limit > 0.0:
		_boss_word_limit -= delta
		_update_timer_label()
		if _boss_word_limit <= 0.0:
			_boss_lose_life()


func _advance_word() -> void:
	if not _word_queue.is_empty():
		if _queue_index >= _word_queue.size():
			_finish(true)
			return
		_current_word = String(_word_queue[_queue_index]).to_upper()
		_queue_index += 1
	elif not _infinite_pool.is_empty():
		_current_word = String(WordBank.pick_word(_infinite_pool, _rng)).to_upper()
	else:
		_finish(true)
		return

	if _cfg.get("mode", "") == "boss":
		_boss_word_limit = max(2.0, 6.0 - (_boss_stage * 0.35))
	elif _cfg.get("mode", "") == "survival":
		_boss_word_limit = max(1.5, 6.0 - floor(_words_typed / 10.0) * 0.3)

	_word_label.text = _current_word
	_word_label.modulate = Color.WHITE
	_input_edit.text = ""


func _on_text_changed(new_text: String) -> void:
	if not _running:
		return
	var typed := new_text.to_upper()
	if _current_word.begins_with(typed):
		_word_label.modulate = Color.WHITE
	else:
		_word_label.modulate = COL_RED
	if typed == _current_word:
		_submit_current_word(true)


func _on_text_submitted(new_text: String) -> void:
	if not _running:
		return
	if new_text.to_upper() == _current_word:
		_submit_current_word(true)
	else:
		_submit_current_word(false)


func _submit_current_word(is_correct: bool) -> void:
	if is_correct:
		_hits += 1
		_words_typed += 1
		if _audio:
			_audio.play_success()
		if _cfg.get("mode", "") == "boss":
			_boss_stage += 1
	else:
		_misses += 1
		if _audio:
			_audio.play_error()
		if is_instance_valid(_game_state):
			_game_state._add_persistent_missed_word(_current_word)
		if _cfg.get("mode", "") == "boss":
			_boss_lose_life()
			return
		elif _cfg.get("mode", "") == "survival":
			_boss_lose_life()
			return
	_update_stats_label()
	_advance_word()


func _boss_lose_life() -> void:
	_misses += 1
	_lives -= 1
	_lives_label.text = "♥ %d" % max(_lives, 0)
	if _audio:
		_audio.play_error()
	if _lives <= 0:
		_finish(false)
	else:
		_advance_word()


func _update_stats_label() -> void:
	var total = _hits + _misses
	var acc = 100.0 if total <= 0 else (float(_hits) / total) * 100.0
	_stats_label.text = LocalizationManager.get_string("words_accuracy_stat", _game_state.selected_language) % [LocalizationManager.get_string("words_label", _game_state.selected_language), _words_typed, LocalizationManager.get_string("accuracy", _game_state.selected_language), acc]


func _update_timer_label() -> void:
	if _cfg.get("mode", "") == "boss":
		_timer_label.text = "%.1fs" % max(_boss_word_limit, 0.0)
	elif _duration > 0.0:
		_timer_label.text = "%d s" % max(int(ceil(_time_left)), 0)
	else:
		_timer_label.text = ""


func _get_wpm() -> float:
	var elapsed_min = max((Time.get_ticks_msec() - _start_msec) / 60000.0, 1.0 / 60.0)
	return _words_typed / elapsed_min if elapsed_min > 0 else 0.0


func _on_stop_pressed() -> void:
	if _running:
		_finish(false)
	else:
		stopped.emit()


func _finish(completed_all: bool) -> void:
	_running = false
	_input_edit.editable = false
	var total = _hits + _misses
	var acc = 100.0 if total <= 0 else (float(_hits) / total) * 100.0
	var wpm = _get_wpm()

	var mode = _cfg.get("mode", "")
	var result := {
		"mode": mode,
		"words_typed": _words_typed,
		"accuracy": acc,
		"wpm": wpm,
		"completed_all": completed_all,
	}

	if is_instance_valid(_game_state):
		_game_state.register_practice_result(_cfg.get("history_label", mode.capitalize()), wpm, acc, _words_typed)
		if mode == "daily" and _words_typed > 0:
			var today := Time.get_date_string_from_system()
			var is_new_day := _game_state.daily_challenge_date != today
			if is_new_day or _words_typed > _game_state.daily_challenge_best_score:
				_game_state.daily_challenge_best_score = _words_typed if is_new_day else max(_words_typed, _game_state.daily_challenge_best_score)
				_game_state.daily_challenge_date = today
				_game_state.save_data()
		if mode == "survival" and _words_typed > _game_state.best_survival_streak:
			_game_state.best_survival_streak = _words_typed
			_game_state.save_data()

	_result_label.text = LocalizationManager.get_string("result_summary_stat", _game_state.selected_language) % [_words_typed, LocalizationManager.get_string("words_label", _game_state.selected_language).to_lower(), wpm, acc, LocalizationManager.get_string("accuracy", _game_state.selected_language).to_lower()]
	if mode == "survival":
		if _words_typed >= _game_state.best_survival_streak and _words_typed > 0:
			_result_label.text += "\n🏆 New best streak!"
		else:
			_result_label.text += "\nBest streak: %d" % _game_state.best_survival_streak
	_finish_btn.text = LocalizationManager.get_string("done", _game_state.selected_language).to_upper()
	finished.emit(result)
