class_name GhostRacer
extends VBoxContainer

## Single-player race against a "ghost" — a past run replayed as a pace,
## not a recorded word-by-word replay (GameState.run_history only stores
## per-run averages, not per-word timing, so the ghost advances at a
## constant rate derived from the target run's WPM: ghost_words_done =
## elapsed_minutes * ghost_wpm). Simple, but genuinely useful: it turns an
## abstract "beat your best WPM" goal into something you watch happen
## live, word by word, next to your own progress.
##
## Embedded inside MoreScreen's content panel, same pattern as
## PracticeSession and VersusMode. Standalone rather than bolted onto
## either of those — this needs a target-selection screen first and a
## continuously-updating ghost meter during the run, which doesn't fit
## PracticeSession's config shape or VersusMode's two-turn flow.
##
## Doesn't touch score/lives/high_scores/career/mission state. Logs one
## run_history row via register_practice_result(), same as every other
## practice mode.

signal finished()
signal stopped()

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MINT := Color(0.4, 0.9, 0.75)
const COL_MUTE := Color(1, 1, 1, 0.55)
const COL_RED := Color(0.85, 0.35, 0.35)
const COL_SKY := Color(0.45, 0.7, 0.95)
const COL_GHOST := Color(0.7, 0.55, 0.95)

const WORD_COUNT := 20

var _game_state: GameState
var _audio: AudioManager
var _mission_manager: MissionManager

var _ghost_wpm := 0.0
var _ghost_label := ""
var _is_rival_race := false   # true when the current race is against the pinned Ghost Rival

var _word_list: Array = []
var _queue_index := 0
var _current_word := ""
var _hits := 0
var _misses := 0
var _words_typed := 0
var _start_msec := 0
var _running := false

var _title_label: Label
var _subtitle_label: Label
var _body_holder: VBoxContainer

var _word_label: Label
var _input_edit: LineEdit
var _stats_label: Label
var _lead_label: Label
var _you_bar: ProgressBar
var _ghost_bar: ProgressBar


func configure(game_state: GameState, audio: AudioManager, mission_manager: MissionManager = null) -> void:
	_game_state = game_state
	_audio = audio
	_mission_manager = mission_manager
	add_theme_constant_override("separation", 10)

	_title_label = Label.new()
	_title_label.text = LocalizationManager.get_string("ghost_race_title", _game_state.selected_language).to_upper()
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", COL_GHOST)
	add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_subtitle_label.add_theme_font_size_override("font_size", 15)
	_subtitle_label.modulate = COL_MUTE
	add_child(_subtitle_label)

	_body_holder = VBoxContainer.new()
	_body_holder.add_theme_constant_override("separation", 12)
	add_child(_body_holder)

	_show_target_picker()


func _clear_body() -> void:
	for c in _body_holder.get_children():
		c.queue_free()


# --- Ghost target selection ---

func _show_target_picker() -> void:
	_clear_body()
	_subtitle_label.text = LocalizationManager.get_string("ghost_race_subtitle", _game_state.selected_language)

	if is_instance_valid(_game_state) and _game_state.has_pinned_ghost_rival():
		_body_holder.add_child(_build_rival_rematch_card())
		_body_holder.add_child(HSeparator.new())

	var targets := _collect_targets()

	if targets.is_empty():
		var empty := Label.new()
		empty.text = LocalizationManager.get_string("ghost_race_empty", _game_state.selected_language)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty.modulate = COL_MUTE
		_body_holder.add_child(empty)

		var stop_btn := Button.new()
		stop_btn.text = LocalizationManager.get_string("back", _game_state.selected_language)
		_body_holder.add_child(stop_btn)
		stop_btn.pressed.connect(func(): stopped.emit())
		_add_import_code_row()
		return

	for t in targets:
		var card := _build_target_card(t.label, t.wpm)
		_body_holder.add_child(card)
		card.find_child("Button", true, false).pressed.connect(func():
			if _audio: _audio.play_whoosh()
			_ghost_wpm = t.wpm
			_ghost_label = t.label
			_is_rival_race = false
			_start_race()
		)

	var stop_btn2 := Button.new()
	stop_btn2.text = LocalizationManager.get_string("cancel", _game_state.selected_language)
	stop_btn2.flat = true
	stop_btn2.modulate = COL_MUTE
	_body_holder.add_child(stop_btn2)
	stop_btn2.pressed.connect(func(): stopped.emit())

	_add_import_code_row()


func _add_import_code_row() -> void:
	var import_panel := PanelContainer.new()
	var import_style := StyleBoxFlat.new()
	import_style.bg_color = Color(1, 1, 1, 0.04)
	import_style.set_corner_radius_all(14)
	import_style.content_margin_left = 14
	import_style.content_margin_right = 14
	import_style.content_margin_top = 10
	import_style.content_margin_bottom = 10
	import_panel.add_theme_stylebox_override("panel", import_style)
	_body_holder.add_child(import_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	import_panel.add_child(vb)

	var label := Label.new()
	label.text = LocalizationManager.get_string("ghost_code_prompt", _game_state.selected_language)
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = COL_MUTE
	vb.add_child(label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)

	var code_edit := LineEdit.new()
	code_edit.placeholder_text = "Paste code here…"
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(code_edit)

	var import_btn := Button.new()
	import_btn.text = LocalizationManager.get_string("import_label", _game_state.selected_language)
	row.add_child(import_btn)

	var feedback := Label.new()
	feedback.add_theme_font_size_override("font_size", 12)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(feedback)

	import_btn.pressed.connect(func():
		var parsed = _decode_ghost_code(code_edit.text)
		if parsed.is_empty():
			feedback.text = LocalizationManager.get_string("ghost_code_invalid", _game_state.selected_language)
			feedback.modulate = COL_RED
			return
		if is_instance_valid(_game_state):
			_game_state.add_imported_ghost_code(parsed.label, parsed.wpm)
		feedback.text = LocalizationManager.get_string("ghost_code_added", _game_state.selected_language) % [parsed.label, parsed.wpm]
		feedback.modulate = COL_MINT
		code_edit.text = ""
	)


func _collect_targets() -> Array:
	var out: Array = []
	if is_instance_valid(_game_state) and _game_state.best_wpm > 0.0:
		out.append({"label": "Personal Best", "wpm": _game_state.best_wpm})

	if is_instance_valid(_game_state):
		var history: Array = _game_state.run_history.duplicate()
		history.reverse()   # most recent first
		var seen_modes := {}
		for entry in history:
			var mode = String(entry.get("mode", "Run"))
			var wpm = float(entry.get("wpm", 0.0))
			if wpm <= 0.0:
				continue
			if seen_modes.has(mode):
				continue
			seen_modes[mode] = true
			out.append({"label": "%s (%s)" % [mode, entry.get("date", "")], "wpm": wpm})
			if out.size() >= 6:
				break

	if is_instance_valid(_game_state):
		for imported in _game_state.imported_ghost_codes:
			out.append({"label": "👤 %s" % String(imported.get("label", "Friend")), "wpm": float(imported.get("wpm", 0.0))})

	return out


## --- Ghost Codes: compact shareable strings so a friend's run can be
## raced without any server. Format (before base64): "KLGR1|label|wpm".
## Purely local string encode/decode - no network involved.

func _encode_ghost_code(label: String, wpm: float) -> String:
	var safe_label = label.replace("|", "-").strip_edges()
	if safe_label == "":
		safe_label = "Friend"
	var payload := "KLGR1|%s|%.1f" % [safe_label, wpm]
	return Marshalls.utf8_to_base64(payload)


func _decode_ghost_code(code: String) -> Dictionary:
	var trimmed = code.strip_edges()
	if trimmed == "":
		return {}
	var payload: String = ""
	payload = Marshalls.base64_to_utf8(trimmed)
	if payload == "":
		return {}
	var parts = payload.split("|")
	if parts.size() != 3 or parts[0] != "KLGR1":
		return {}
	var wpm = float(parts[2])
	if wpm <= 0.0:
		return {}
	return {"label": parts[1], "wpm": wpm}


## Dedicated card for the single pinned Ghost Rival — a fixed opponent kept
## across sessions (GameState.ghost_rival_label/_wpm), distinct from the
## ad-hoc "any past run" target list below it. Shows a rematch history log
## (win/loss + both WPMs) so the rivalry has some memory instead of being
## ephemeral like a normal ghost race.
func _build_rival_rematch_card() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.78, 0.25, 0.10)
	style.set_corner_radius_all(16)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.78, 0.25, 0.5)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "👑 YOUR GHOST RIVAL"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COL_GOLD)
	vb.add_child(title)

	var wins := 0
	var losses := 0
	for entry in _game_state.ghost_rival_history:
		if entry.get("won", false):
			wins += 1
		else:
			losses += 1

	var info := Label.new()
	info.text = "%s — %.0f WPM  (Record: %d-%d)" % [_game_state.ghost_rival_label, _game_state.ghost_rival_wpm, wins, losses]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_theme_font_size_override("font_size", 16)
	info.modulate = COL_MUTE
	vb.add_child(info)

	var rematch_btn := Button.new()
	rematch_btn.text = "⚔ REMATCH"
	rematch_btn.custom_minimum_size = Vector2(0, 48)
	vb.add_child(rematch_btn)
	rematch_btn.pressed.connect(func():
		if _audio: _audio.play_whoosh()
		_ghost_wpm = _game_state.ghost_rival_wpm
		_ghost_label = _game_state.ghost_rival_label
		_is_rival_race = true
		_start_race()
	)

	var clear_btn := Button.new()
	clear_btn.text = "Clear rival"
	clear_btn.flat = true
	clear_btn.modulate = COL_MUTE
	clear_btn.add_theme_font_size_override("font_size", 13)
	vb.add_child(clear_btn)
	clear_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		_game_state.pin_ghost_rival("", 0.0)
		_show_target_picker()
	)

	if not _game_state.ghost_rival_history.is_empty():
		var log_sep := HSeparator.new()
		vb.add_child(log_sep)
		var log_title := Label.new()
		log_title.text = "Rematch history"
		log_title.add_theme_font_size_override("font_size", 13)
		log_title.modulate = COL_MUTE
		vb.add_child(log_title)

		var history: Array = _game_state.ghost_rival_history.duplicate()
		history.reverse()
		for entry in history.slice(0, min(5, history.size())):
			var row := Label.new()
			var won: bool = entry.get("won", false)
			row.text = "%s  %s  %.0f vs %.0f WPM  (%s)" % [
				"✅" if won else "❌",
				String(entry.get("date", "")),
				float(entry.get("your_wpm", 0.0)),
				float(entry.get("rival_wpm", 0.0)),
				"WIN" if won else "LOSS",
			]
			row.add_theme_font_size_override("font_size", 13)
			row.modulate = COL_MINT if won else COL_RED
			vb.add_child(row)

	return panel


func _build_target_card(label_txt: String, wpm: float) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.05)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	var hb := HBoxContainer.new()
	panel.add_child(hb)

	var btn := Button.new()
	btn.name = "Button"
	btn.text = label_txt
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 19)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(btn)

	var wpm_lbl := Label.new()
	wpm_lbl.text = LocalizationManager.get_string("wpm_value", _game_state.selected_language) % wpm
	wpm_lbl.add_theme_font_size_override("font_size", 19)
	wpm_lbl.modulate = COL_GHOST
	hb.add_child(wpm_lbl)

	var pin_btn := Button.new()
	pin_btn.text = "📌"
	pin_btn.tooltip_text = "Pin as Ghost Rival"
	pin_btn.flat = true
	pin_btn.add_theme_font_size_override("font_size", 19)
	hb.add_child(pin_btn)
	pin_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		if is_instance_valid(_game_state):
			_game_state.pin_ghost_rival(label_txt, wpm)
			_show_target_picker()
	)

	return panel


# --- Racing ---

func _start_race() -> void:
	_clear_body()
	_subtitle_label.text = LocalizationManager.get_string("racing_ghost", _game_state.selected_language) % [_ghost_label, _ghost_wpm]

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pool = WordBank.pool_for_theme_mix(WordBank.theme_names())
	_word_list = WordBank.get_batch(pool, WORD_COUNT, rng)

	var bars_panel := PanelContainer.new()
	var bars_style := StyleBoxFlat.new()
	bars_style.bg_color = Color(1, 1, 1, 0.05)
	bars_style.set_corner_radius_all(14)
	bars_style.content_margin_left = 16
	bars_style.content_margin_right = 16
	bars_style.content_margin_top = 12
	bars_style.content_margin_bottom = 12
	bars_panel.add_theme_stylebox_override("panel", bars_style)
	_body_holder.add_child(bars_panel)

	var bars_vb := VBoxContainer.new()
	bars_vb.add_theme_constant_override("separation", 6)
	bars_panel.add_child(bars_vb)

	var you_row := Label.new()
	you_row.text = LocalizationManager.get_string("you_label", _game_state.selected_language).to_upper()
	you_row.add_theme_font_size_override("font_size", 13)
	you_row.modulate = COL_MINT
	bars_vb.add_child(you_row)

	_you_bar = ProgressBar.new()
	_you_bar.max_value = _word_list.size()
	_you_bar.value = 0
	_you_bar.show_percentage = false
	_you_bar.custom_minimum_size = Vector2(0, 18)
	var you_track := JellyTheme.progress_track_style(0.4)
	_you_bar.add_theme_stylebox_override("background", you_track)
	var you_fill := StyleBoxFlat.new()
	you_fill.bg_color = COL_MINT
	you_fill.set_corner_radius_all(6)
	_you_bar.add_theme_stylebox_override("fill", you_fill)
	bars_vb.add_child(_you_bar)

	var ghost_row := Label.new()
	ghost_row.text = LocalizationManager.get_string("ghost_label", _game_state.selected_language).to_upper()
	ghost_row.add_theme_font_size_override("font_size", 13)
	ghost_row.modulate = COL_GHOST
	bars_vb.add_child(ghost_row)

	_ghost_bar = ProgressBar.new()
	_ghost_bar.max_value = _word_list.size()
	_ghost_bar.value = 0
	_ghost_bar.show_percentage = false
	_ghost_bar.custom_minimum_size = Vector2(0, 18)
	var ghost_track := JellyTheme.progress_track_style(0.4)
	_ghost_bar.add_theme_stylebox_override("background", ghost_track)
	var ghost_fill := StyleBoxFlat.new()
	ghost_fill.bg_color = COL_GHOST
	ghost_fill.set_corner_radius_all(6)
	_ghost_bar.add_theme_stylebox_override("fill", ghost_fill)
	bars_vb.add_child(_ghost_bar)

	_lead_label = Label.new()
	_lead_label.text = ""
	_lead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lead_label.add_theme_font_size_override("font_size", 14)
	bars_vb.add_child(_lead_label)

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 16)
	_body_holder.add_child(stats_row)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 14)
	_stats_label.modulate = COL_MINT
	stats_row.add_child(_stats_label)

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
	word_panel.add_child(_word_label)

	_input_edit = LineEdit.new()
	_input_edit.placeholder_text = "Type it here…"
	_input_edit.add_theme_font_size_override("font_size", 20)
	_body_holder.add_child(_input_edit)
	_input_edit.text_changed.connect(_on_text_changed)
	_input_edit.text_submitted.connect(_on_text_submitted)

	var stop_btn := Button.new()
	stop_btn.text = LocalizationManager.get_string("stop", _game_state.selected_language).to_upper()
	stop_btn.custom_minimum_size = Vector2(0, 44)
	_body_holder.add_child(stop_btn)
	stop_btn.pressed.connect(func():
		if _running:
			_finish(false)
		else:
			stopped.emit()
	)

	_hits = 0
	_misses = 0
	_words_typed = 0
	_queue_index = 0
	_running = false
	_input_edit.editable = false
	_word_label.text = LocalizationManager.get_string("get_ready", _game_state.selected_language).to_upper()
	call_deferred("_run_start_countdown")


func _run_start_countdown() -> void:
	for i in [3, 2, 1]:
		if not is_instance_valid(_word_label):
			return
		_word_label.text = str(i)
		if _audio: _audio.play_ui_click()
		await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(_word_label):
		return
	_word_label.text = LocalizationManager.get_string("go_label", _game_state.selected_language).to_upper()
	if _audio: _audio.play_whoosh()
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(_input_edit):
		return

	_input_edit.editable = true
	_start_msec = Time.get_ticks_msec()
	_running = true
	_advance_word()
	_update_stats_label()
	call_deferred("_focus_input")


func _focus_input() -> void:
	if is_instance_valid(_input_edit):
		_input_edit.grab_focus()


func _process(_delta: float) -> void:
	if not _running:
		return
	var elapsed_min = max((Time.get_ticks_msec() - _start_msec) / 60000.0, 0.0)
	var ghost_words = min(elapsed_min * _ghost_wpm, _word_list.size())
	_ghost_bar.value = ghost_words

	var diff = _words_typed - ghost_words
	if diff > 0.4:
		_lead_label.text = LocalizationManager.get_string("lead_ahead", _game_state.selected_language) % diff
		_lead_label.modulate = COL_MINT
	elif diff < -0.4:
		_lead_label.text = LocalizationManager.get_string("lead_behind", _game_state.selected_language) % -diff
		_lead_label.modulate = COL_RED
	else:
		_lead_label.text = LocalizationManager.get_string("neck_and_neck", _game_state.selected_language)
		_lead_label.modulate = COL_GOLD

	if ghost_words >= _word_list.size():
		_finish(false)


func _advance_word() -> void:
	if _queue_index >= _word_list.size():
		_finish(true)
		return
	_current_word = String(_word_list[_queue_index]).to_upper()
	_queue_index += 1
	_word_label.text = _current_word
	_word_label.modulate = Color.WHITE
	_input_edit.text = ""


func _on_text_changed(new_text: String) -> void:
	if not _running:
		return
	var typed := new_text.to_upper()
	_word_label.modulate = Color.WHITE if _current_word.begins_with(typed) else COL_RED
	if typed == _current_word:
		_submit_word(true)


func _on_text_submitted(new_text: String) -> void:
	if not _running:
		return
	_submit_word(new_text.to_upper() == _current_word)


func _submit_word(is_correct: bool) -> void:
	if is_correct:
		_hits += 1
		_words_typed += 1
		if _audio: _audio.play_success()
		_you_bar.value = _words_typed
	else:
		_misses += 1
		if _audio: _audio.play_error()
		if is_instance_valid(_game_state):
			_game_state._add_persistent_missed_word(_current_word)
	_update_stats_label()
	_advance_word()


func _update_stats_label() -> void:
	var total = _hits + _misses
	var acc = 100.0 if total <= 0 else (float(_hits) / total) * 100.0
	_stats_label.text = LocalizationManager.get_string("words_progress_accuracy_stat", _game_state.selected_language) % [LocalizationManager.get_string("words_label", _game_state.selected_language), _words_typed, _word_list.size(), LocalizationManager.get_string("accuracy", _game_state.selected_language), acc]


func _finish(you_finished_all: bool) -> void:
	_running = false
	if is_instance_valid(_input_edit):
		_input_edit.editable = false

	var elapsed = max((Time.get_ticks_msec() - _start_msec) / 60000.0, 1.0 / 60000.0)
	var total = _hits + _misses
	var acc = 100.0 if total <= 0 else (float(_hits) / total) * 100.0
	var wpm = _words_typed / elapsed

	var beat_ghost = you_finished_all and _words_typed >= _word_list.size()

	if _audio:
		if beat_ghost:
			_audio.play_level_up_sting()
		else:
			_audio.play_game_over_voice()

	_clear_body()

	var result_label := Label.new()
	result_label.text = LocalizationManager.get_string("you_beat_ghost", _game_state.selected_language).to_upper() if beat_ghost else LocalizationManager.get_string("ghost_wins", _game_state.selected_language)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 22)
	result_label.add_theme_color_override("font_color", COL_MINT if beat_ghost else COL_GHOST)
	_body_holder.add_child(result_label)

	var detail := Label.new()
	detail.text = LocalizationManager.get_string("race_detail", _game_state.selected_language) % [wpm, acc, _ghost_wpm]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	detail.add_theme_font_size_override("font_size", 15)
	detail.modulate = COL_MUTE
	_body_holder.add_child(detail)

	if is_instance_valid(_game_state) and _words_typed > 0:
		_game_state.register_practice_result("Ghost Race (Rival)" if _is_rival_race else "Ghost Race", wpm, acc, _words_typed)
		_game_state.register_ghost_race_result(beat_ghost)
		if _is_rival_race:
			_game_state.record_ghost_rival_rematch(wpm, beat_ghost)

	if is_instance_valid(_mission_manager):
		var newly_completed: Array = _mission_manager.evaluate_ghost_race(beat_ghost)
		if _is_rival_race and beat_ghost:
			newly_completed.append_array(_mission_manager.evaluate_ghost_rival())
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

	if _words_typed > 0:
		var share_btn := Button.new()
		share_btn.text = LocalizationManager.get_string("share_result", _game_state.selected_language)
		_body_holder.add_child(share_btn)
		share_btn.pressed.connect(func():
			var text = "I just raced a %s (%.0f WPM) ghost in Type Blast — %.0f WPM, %.0f%% accuracy. %s" % \
				[_ghost_label, _ghost_wpm, wpm, acc, ("Beat it! 👻⚡" if beat_ghost else "So close!")]
			DisplayServer.clipboard_set(text)
			share_feedback.text = LocalizationManager.get_string("share_copied", _game_state.selected_language)
			if not share_feedback.is_inside_tree():
				_body_holder.add_child(share_feedback)
		)

		var code_btn := Button.new()
		code_btn.text = LocalizationManager.get_string("copy_ghost_code", _game_state.selected_language)
		code_btn.flat = true
		_body_holder.add_child(code_btn)
		code_btn.pressed.connect(func():
			var my_label = "%.0f WPM run" % wpm
			DisplayServer.clipboard_set(_encode_ghost_code(my_label, wpm))
			share_feedback.text = LocalizationManager.get_string("ghost_code_copied", _game_state.selected_language)
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

	var again_btn := Button.new()
	again_btn.text = LocalizationManager.get_string("race_again", _game_state.selected_language).to_upper()
	again_btn.flat = true
	again_btn.modulate = COL_MUTE
	_body_holder.add_child(again_btn)
	again_btn.pressed.connect(func():
		_show_target_picker()
	)
