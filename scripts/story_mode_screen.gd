class_name StoryModeScreen
extends VBoxContainer

## "DEEP SIGNAL" — Story Mode, embedded inside MoreScreen's content panel
## (same pattern PracticeSession/VersusMode/GhostRacer already use).
##
## Structure is deliberately close to a fighting game's story mode: pick a
## chapter from a list, read a couple of cutscene panels, play a typing
## challenge, read the payoff panels, unlock the next chapter. Each
## chapter gets its own colored "scene banner" (built from
## BackgroundThemes' existing 4 palettes) so it visually reads as a new
## location every chapter, without touching MoreScreen's own rotating
## backdrop system.
##
## Chapter data lives in StoryData (data-only, no logic). This script is
## pure flow/UI. Doesn't touch score/lives/high_scores/career/mission
## state — on clearing a chapter it only ever writes
## GameState.story_chapter_unlocked / story_chapters_cleared and logs one
## run_history entry via register_practice_result(), same as every other
## practice mode.

signal finished()   # emitted whenever a chapter is cleared (badge-check hook)

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MINT := Color(0.4, 0.9, 0.75)
const COL_MUTE := Color(1, 1, 1, 0.6)
const COL_RED := Color(0.85, 0.35, 0.35)
const COL_SKY := Color(0.45, 0.7, 0.95)
const COL_AMBER := Color(0.95, 0.6, 0.25)

var _game_state: GameState
var _audio: AudioManager
var _mission_manager: MissionManager

var _stage := "select"   # select -> intro -> challenge -> results -> outro | fail
var _current_chapter: Dictionary = {}
var _panel_index := 0

var _line_queue: Array = []
var _queue_index := 0
var _current_line := ""
var _hits := 0
var _misses := 0
var _lines_typed := 0
var _word_units_done := 0.0
var _lives := 0
var _duration := 0.0
var _time_left := 0.0
var _fail_reason := "lives"
var _last_wpm := 0.0
var _last_acc := 0.0
var _start_msec := 0
var _rng := RandomNumberGenerator.new()

var _input_edit: LineEdit
var _line_label: Label
var _progress_label: Label
var _lives_label: Label
var _timer_label: Label


func configure(game_state: GameState, audio: AudioManager, mission_manager: MissionManager = null) -> void:
	_game_state = game_state
	_audio = audio
	_mission_manager = mission_manager
	_rng.randomize()
	add_theme_constant_override("separation", 12)
	_render_select()


func _clear_self() -> void:
	for child in get_children():
		child.queue_free()


func _title_label(txt: String, color: Color, size: int = 24) -> Label:
	var l = Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _body_label(txt: String, color: Color = Color(1, 1, 1, 0.9)) -> Label:
	var l = Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 19)
	l.modulate = color
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l


func _nav_button(txt: String, color: Color) -> Button:
	var b = Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", color)
	return b


## The per-chapter "changing background": a colored banner built from one
## of BackgroundThemes' 4 existing palettes (top/bottom gradient color +
## accent), so every chapter reads as a visually distinct location without
## a second parallel backdrop system.
func _build_scene_banner(chapter: Dictionary) -> PanelContainer:
	var th: Dictionary = BackgroundThemes.theme(chapter.get("bg_theme", 0))
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = th.get("top", Color(0.05, 0.05, 0.08))
	style.set_corner_radius_all(16)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = th.get("accent", COL_SKY)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)

	var vb = VBoxContainer.new()
	panel.add_child(vb)

	var loc = Label.new()
	loc.text = String(chapter.get("location", "")).to_upper()
	loc.add_theme_font_size_override("font_size", 15)
	loc.modulate = th.get("accent", COL_SKY)
	vb.add_child(loc)

	var title = Label.new()
	title.text = "CH. %d — %s" % [chapter.get("id", 0), chapter.get("title", "")]
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color.WHITE)
	vb.add_child(title)

	return panel


# --- Chapter select ---

func _render_select() -> void:
	_stage = "select"
	_clear_self()

	var eyebrow = _title_label("STORY MODE", COL_MINT, 18)
	add_child(eyebrow)
	var title = _title_label("DEEP SIGNAL", COL_GOLD, 30)
	add_child(title)
	var subtitle = _body_label("A comms operator's night, told in six transmissions. Clear each one to unlock the next.", COL_MUTE)
	add_child(subtitle)

	add_child(_body_label("Difficulty", COL_MUTE))
	var diff_row = HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	add_child(diff_row)
	var current_diff: String = _game_state.story_difficulty if is_instance_valid(_game_state) else "normal"
	for d in ["easy", "normal", "hard"]:
		var diff_btn = Button.new()
		diff_btn.text = d.to_upper()
		diff_btn.toggle_mode = true
		diff_btn.button_pressed = (d == current_diff)
		diff_btn.custom_minimum_size = Vector2(0, 44)
		diff_btn.add_theme_font_size_override("font_size", 16)
		if d == current_diff:
			diff_btn.add_theme_color_override("font_color", COL_GOLD)
		diff_row.add_child(diff_btn)
		diff_btn.pressed.connect(func():
			if is_instance_valid(_game_state):
				_game_state.story_difficulty = d
				_game_state.save_data()
			if _audio: _audio.play_ui_click()
			_render_select()
		)

	add_child(HSeparator.new())

	var legend = _body_label("🔒 locked · ✓ cleared · ✓💎 cleared on Hard", COL_MUTE)
	legend.add_theme_font_size_override("font_size", 14)
	add_child(legend)

	var unlocked: int = _game_state.story_chapter_unlocked if is_instance_valid(_game_state) else 1
	var cleared: Array = _game_state.story_chapters_cleared if is_instance_valid(_game_state) else []
	var cleared_hard: Array = _game_state.story_chapters_cleared_hard if is_instance_valid(_game_state) else []

	for chapter: Dictionary in StoryData.CHAPTERS:
		var id: int = chapter.get("id", 0)
		var is_unlocked := id <= unlocked
		var is_cleared: bool = cleared.has(id)
		var is_cleared_hard: bool = cleared_hard.has(id)
		var scaled: Dictionary = StoryData.apply_difficulty(chapter, current_diff)

		var row = PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1, 1, 1, 0.05) if is_unlocked else Color(1, 1, 1, 0.02)
		style.set_corner_radius_all(14)
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		row.add_theme_stylebox_override("panel", style)

		var vb = VBoxContainer.new()
		row.add_child(vb)

		var btn = Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 21)
		btn.disabled = not is_unlocked
		var status := ""
		if is_cleared_hard:
			status = "  ✓💎"
		elif is_cleared:
			status = "  ✓"
		elif not is_unlocked:
			status = "  🔒"
		btn.text = "Ch. %d — %s%s" % [id, chapter.get("title", ""), status]
		if is_unlocked:
			btn.add_theme_color_override("font_color", Color.WHITE)
			btn.add_theme_color_override("font_hover_color", COL_GOLD)
		else:
			btn.add_theme_color_override("font_disabled_color", COL_MUTE)
		vb.add_child(btn)

		if is_unlocked:
			var info_bits: Array = ["%s" % chapter.get("location", ""), "%d lines" % scaled.get("line_count", 0)]
			if scaled.get("lives", 0) > 0:
				info_bits.append("♥ %d" % scaled.get("lives", 0))
			if scaled.get("duration", 0.0) > 0.0:
				info_bits.append("⏱ %ds" % int(scaled.get("duration", 0.0)))
			var desc = _body_label(" · ".join(info_bits), COL_MUTE)
			desc.add_theme_font_size_override("font_size", 16)
			vb.add_child(desc)
		else:
			var locked_desc = _body_label("Clear the previous transmission to unlock.", COL_MUTE)
			locked_desc.add_theme_font_size_override("font_size", 16)
			vb.add_child(locked_desc)

		if is_unlocked:
			btn.pressed.connect(func():
				if _audio: _audio.play_whoosh()
				_start_chapter(id)
			)
		add_child(row)

	if unlocked > StoryData.chapter_count():
		add_child(HSeparator.new())
		var teaser = PanelContainer.new()
		var teaser_style := StyleBoxFlat.new()
		teaser_style.bg_color = Color(1, 1, 1, 0.03)
		teaser_style.set_corner_radius_all(14)
		teaser_style.content_margin_left = 16
		teaser_style.content_margin_right = 16
		teaser_style.content_margin_top = 10
		teaser_style.content_margin_bottom = 10
		teaser.add_theme_stylebox_override("panel", teaser_style)
		var teaser_vb = VBoxContainer.new()
		teaser.add_child(teaser_vb)
		teaser_vb.add_child(_title_label("🔒  DEEP SIGNAL — PART TWO", COL_MUTE, 18))
		teaser_vb.add_child(_body_label("Coming soon.", COL_MUTE))
		add_child(teaser)
		add_child(_body_label("You've heard every transmission. Thanks for playing DEEP SIGNAL, Part One.", COL_GOLD))


func _start_chapter(id: int) -> void:
	var base_chapter := StoryData.get_chapter(id)
	if base_chapter.is_empty():
		return
	var difficulty: String = _game_state.story_difficulty if is_instance_valid(_game_state) else "normal"
	_current_chapter = StoryData.apply_difficulty(base_chapter, difficulty)
	_panel_index = 0
	_render_intro()


# --- Cutscene panels (intro / outro share the same pager) ---

func _render_intro() -> void:
	_stage = "intro"
	var id: int = _current_chapter.get("id", 0)
	var already_cleared: bool = is_instance_valid(_game_state) and _game_state.story_chapters_cleared.has(id)
	_render_panel_page(_current_chapter.get("intro", []), func(): _render_challenge(), already_cleared)


func _render_outro() -> void:
	_stage = "outro"
	_render_panel_page(_current_chapter.get("outro", []), func(): _complete_chapter(), false)


func _render_panel_page(pages: Array, on_last_next: Callable, allow_skip: bool = false) -> void:
	_clear_self()
	add_child(_build_scene_banner(_current_chapter))

	var page_text: String = pages[_panel_index] if _panel_index < pages.size() else ""
	var body = _body_label(page_text)
	body.add_theme_font_size_override("font_size", 20)
	add_child(body)

	var progress = _body_label("Page %d / %d" % [_panel_index + 1, max(pages.size(), 1)], COL_MUTE)
	progress.add_theme_font_size_override("font_size", 14)
	add_child(progress)

	var is_last := _panel_index >= pages.size() - 1
	var next_btn = _nav_button("BEGIN" if (is_last and _stage == "intro") else ("CONTINUE" if is_last else "NEXT ▶"), COL_SKY if not is_last else COL_GOLD)
	next_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		if is_last:
			_panel_index = 0
			on_last_next.call()
		else:
			_panel_index += 1
			_render_panel_page(pages, on_last_next, allow_skip)
	)
	add_child(next_btn)

	if allow_skip and not is_last:
		var skip_btn = _nav_button("SKIP TO CHALLENGE ▶▶", COL_MUTE)
		skip_btn.pressed.connect(func():
			if _audio: _audio.play_ui_click()
			_panel_index = 0
			on_last_next.call()
		)
		add_child(skip_btn)


# --- Challenge ---

func _render_challenge() -> void:
	_stage = "challenge"
	_hits = 0
	_misses = 0
	_lines_typed = 0
	_queue_index = 0
	_word_units_done = 0.0
	_lives = _current_chapter.get("lives", 0)
	_duration = _current_chapter.get("duration", 0.0)
	_time_left = _duration
	_fail_reason = "lives"
	_start_msec = Time.get_ticks_msec()

	_line_queue = StoryData.sentence_queue_for(_current_chapter, _rng)

	_clear_self()
	add_child(_build_scene_banner(_current_chapter))

	var stats_row = HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 16)
	add_child(stats_row)

	var progress_label = Label.new()
	progress_label.add_theme_font_size_override("font_size", 16)
	progress_label.modulate = COL_MINT
	stats_row.add_child(progress_label)
	_progress_label = progress_label

	var lives_label = Label.new()
	lives_label.add_theme_font_size_override("font_size", 16)
	lives_label.modulate = COL_RED
	stats_row.add_child(lives_label)
	_lives_label = lives_label

	var timer_label = Label.new()
	timer_label.add_theme_font_size_override("font_size", 16)
	timer_label.modulate = COL_AMBER
	stats_row.add_child(timer_label)
	_timer_label = timer_label

	var word_label = Label.new()
	word_label.add_theme_font_size_override("font_size", 22)
	word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(word_label)
	_line_label = word_label

	_input_edit = LineEdit.new()
	_input_edit.custom_minimum_size = Vector2(0, 56)
	_input_edit.add_theme_font_size_override("font_size", 24)
	_input_edit.text_changed.connect(_on_text_changed)
	_input_edit.text_submitted.connect(_on_text_submitted)
	add_child(_input_edit)

	if _line_queue.is_empty():
		add_child(_body_label("Nothing to transcribe here yet — try again shortly.", COL_MUTE))
		var back_btn = _nav_button("BACK TO TRANSMISSIONS", COL_MUTE)
		back_btn.pressed.connect(func():
			if _audio: _audio.play_ui_click()
			_render_select()
		)
		add_child(back_btn)
		return

	var give_up_btn = _nav_button("GIVE UP (BACK TO TRANSMISSIONS)", COL_MUTE)
	give_up_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		_render_select()
	)
	add_child(give_up_btn)

	_update_challenge_labels()
	_advance_line()
	call_deferred("_focus_input")


func _process(delta: float) -> void:
	if _stage != "challenge" or _duration <= 0.0:
		return
	_time_left -= delta
	if _timer_label:
		_timer_label.text = "%d s" % max(int(ceil(_time_left)), 0)
	if _time_left <= 0.0:
		_fail_reason = "time"
		_render_fail()


func _focus_input() -> void:
	if is_instance_valid(_input_edit):
		_input_edit.grab_focus()


func _update_challenge_labels() -> void:
	if _progress_label:
		_progress_label.text = "%d / %d" % [_lines_typed, _line_queue.size()]
	if _lives_label:
		_lives_label.text = ("♥ %d" % _lives) if _lives > 0 else ""
	if _timer_label:
		_timer_label.text = ("%d s" % max(int(ceil(_time_left)), 0)) if _duration > 0.0 else ""


func _advance_line() -> void:
	if _queue_index >= _line_queue.size():
		_finish_challenge()
		return
	_current_line = String(_line_queue[_queue_index])
	_queue_index += 1
	if _line_label:
		_line_label.text = _current_line
		_line_label.modulate = Color.WHITE
	if _input_edit:
		_input_edit.text = ""


func _on_text_changed(new_text: String) -> void:
	if not _line_label:
		return
	if new_text == _current_line:
		_submit_line(true)
	elif _current_line.begins_with(new_text):
		_line_label.modulate = Color.WHITE
	else:
		_line_label.modulate = COL_RED


func _on_text_submitted(new_text: String) -> void:
	_submit_line(new_text == _current_line)


func _submit_line(is_correct: bool) -> void:
	if is_correct:
		_hits += 1
		_lines_typed += 1
		_word_units_done += SentenceBank.standard_word_count(_current_line)
		if _audio: _audio.play_success()
		_update_challenge_labels()
		_advance_line()
		return

	_misses += 1
	if _audio: _audio.play_error()

	if _lives > 0:
		_lives -= 1
		_update_challenge_labels()
		if _lives <= 0:
			_render_fail()
			return
	_advance_line()


func _finish_challenge() -> void:
	_last_wpm = 0.0
	_last_acc = 100.0
	if is_instance_valid(_game_state):
		var elapsed_min = max((Time.get_ticks_msec() - _start_msec) / 60000.0, 1.0 / 60.0)
		_last_wpm = _word_units_done / elapsed_min if elapsed_min > 0 else 0.0
		var total = _hits + _misses
		_last_acc = 100.0 if total <= 0 else (float(_hits) / total) * 100.0
		_game_state.register_practice_result("Story: %s" % _current_chapter.get("title", ""), _last_wpm, _last_acc, _lines_typed)
	_render_results()


func _render_results() -> void:
	_stage = "results"
	_clear_self()
	add_child(_build_scene_banner(_current_chapter))
	add_child(_title_label("TRANSMISSION RECEIVED", COL_GOLD, 22))

	var stats = _body_label("%d lines · %.0f WPM · %.0f%% accuracy" % [_lines_typed, _last_wpm, _last_acc], COL_MINT)
	stats.add_theme_font_size_override("font_size", 20)
	add_child(stats)

	var diff_label = _body_label("Difficulty: %s" % String(_current_chapter.get("difficulty", "normal")).capitalize(), COL_MUTE)
	diff_label.add_theme_font_size_override("font_size", 15)
	add_child(diff_label)

	var continue_btn = _nav_button("CONTINUE", COL_SKY)
	continue_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		_render_outro()
	)
	add_child(continue_btn)


func _render_fail() -> void:
	_stage = "fail"
	_clear_self()
	add_child(_build_scene_banner(_current_chapter))
	add_child(_title_label("TRANSMISSION LOST", COL_RED, 24))
	var msg := "The connection dropped before you finished. No progress lost — try the transmission again whenever you're ready."
	if _fail_reason == "time":
		msg = "Time ran out before you finished. No progress lost — try the transmission again whenever you're ready."
	add_child(_body_label(msg))

	var retry_btn = _nav_button("RETRY TRANSMISSION", COL_SKY)
	retry_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		_panel_index = 0
		_render_intro()
	)
	add_child(retry_btn)

	var back_btn = _nav_button("BACK TO TRANSMISSIONS", COL_MUTE)
	back_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		_render_select()
	)
	add_child(back_btn)


func _complete_chapter() -> void:
	if is_instance_valid(_game_state):
		var id: int = _current_chapter.get("id", 0)
		if id == _game_state.story_chapter_unlocked:
			_game_state.story_chapter_unlocked = id + 1
		if not _game_state.story_chapters_cleared.has(id):
			_game_state.story_chapters_cleared.append(id)
		if _current_chapter.get("difficulty", "normal") == "hard" and not _game_state.story_chapters_cleared_hard.has(id):
			_game_state.story_chapters_cleared_hard.append(id)
		_game_state.save_data()
	finished.emit()
	_render_select()
