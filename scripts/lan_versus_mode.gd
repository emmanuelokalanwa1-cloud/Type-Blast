class_name LanVersusMode
extends VBoxContainer

## Real-time 1v1 race over local WiFi, using LanMultiplayerManager (Godot's
## built-in ENet networking - no internet service, no account, just two
## phones on the same network). One player hosts, the other joins by
## typing the host's local IP. Both race the same word list live, each
## seeing their own progress bar and the opponent's, updated over the
## network as each word is completed.
##
## *** EXPERIMENTAL / UNVERIFIED *** - see the header comment in
## lan_multiplayer_manager.gd. This has not been tested between two real
## devices. Treat "AI Versus Mode" and "Ghost Race" as the solid,
## proven modes, and this one as a beta you should try on your own two
## phones before relying on it.
##
## Embedded inside MoreScreen's content panel, same pattern as the other
## three race modes. Doesn't touch score/lives/high_scores/career state.
## Logs one run_history row via register_practice_result() on finish,
## same as everything else.

signal finished()
signal stopped()

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MINT := Color(0.4, 0.9, 0.75)
const COL_MUTE := Color(1, 1, 1, 0.55)
const COL_RED := Color(0.85, 0.35, 0.35)
const COL_LAN := Color(0.5, 0.75, 0.55)
const COL_OPP := Color(0.95, 0.55, 0.35)

const WORD_COUNT := 15

var _game_state: GameState
var _audio: AudioManager
var _lan: LanMultiplayerManager
var _mission_manager: MissionManager

var _word_list: Array = []
var _queue_index := 0
var _current_word := ""
var _hits := 0
var _misses := 0
var _words_typed := 0
var _start_msec := 0
var _running := false
var _match_active := false
var _own_finish_elapsed := -1.0
var _opponent_words_done := 0
var _opponent_finish_elapsed := -1.0
var _last_join_address := ""
var _i_am_host := false

var _title_label: Label
var _subtitle_label: Label
var _body_holder: VBoxContainer

var _word_label: Label
var _input_edit: LineEdit
var _you_bar: ProgressBar
var _opp_bar: ProgressBar
var _status_label: Label


func configure(game_state: GameState, audio: AudioManager, lan_manager: LanMultiplayerManager, mission_manager: MissionManager = null) -> void:
	_game_state = game_state
	_audio = audio
	_lan = lan_manager
	_mission_manager = mission_manager
	add_theme_constant_override("separation", 10)

	if not is_instance_valid(_lan):
		_title_label = Label.new()
		_title_label.text = LocalizationManager.get_string("lan_unavailable_title", _game_state.selected_language).to_upper()
		add_child(_title_label)
		var msg := Label.new()
		msg.text = LocalizationManager.get_string("networking_unavailable", _game_state.selected_language)
		msg.modulate = COL_MUTE
		add_child(msg)
		return

	_title_label = Label.new()
	_title_label.text = LocalizationManager.get_string("lan_versus_title", _game_state.selected_language).to_upper()
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", COL_LAN)
	add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_subtitle_label.add_theme_font_size_override("font_size", 15)
	_subtitle_label.modulate = COL_MUTE
	add_child(_subtitle_label)

	_body_holder = VBoxContainer.new()
	_body_holder.add_theme_constant_override("separation", 12)
	add_child(_body_holder)

	_lan.opponent_connected.connect(_on_opponent_connected)
	_lan.opponent_disconnected.connect(_on_opponent_disconnected)
	_lan.connected_to_host.connect(_on_connected_to_host)
	_lan.connection_failed.connect(_on_connection_failed)
	_lan.match_start_received.connect(_on_match_start_received)
	_lan.opponent_progress.connect(_on_opponent_progress)
	_lan.opponent_finished.connect(_on_opponent_finished)

	_show_menu()


func _clear_body() -> void:
	for c in _body_holder.get_children():
		c.queue_free()


func _leave(emit_stopped: bool) -> void:
	_running = false
	_match_active = false
	if is_instance_valid(_lan):
		_lan.shutdown()
	if emit_stopped:
		stopped.emit()
	else:
		finished.emit()


# --- Host / Join menu ---

func _show_menu() -> void:
	_subtitle_label.text = LocalizationManager.get_string("lan_subtitle_intro", _game_state.selected_language)
	_clear_body()

	var host_btn := Button.new()
	host_btn.text = LocalizationManager.get_string("host_match", _game_state.selected_language)
	host_btn.custom_minimum_size = Vector2(0, 48)
	_body_holder.add_child(host_btn)
	host_btn.pressed.connect(_show_host_screen)

	var join_btn := Button.new()
	join_btn.text = LocalizationManager.get_string("join_match", _game_state.selected_language)
	join_btn.custom_minimum_size = Vector2(0, 48)
	_body_holder.add_child(join_btn)
	join_btn.pressed.connect(_show_join_screen)

	var cancel_btn := Button.new()
	cancel_btn.text = LocalizationManager.get_string("cancel", _game_state.selected_language)
	cancel_btn.flat = true
	cancel_btn.modulate = COL_MUTE
	_body_holder.add_child(cancel_btn)
	cancel_btn.pressed.connect(func(): _leave(true))


func _show_host_screen() -> void:
	_clear_body()
	var err = _lan.host_match()
	if err != OK:
		_subtitle_label.text = LocalizationManager.get_string("host_error", _game_state.selected_language) % err
		_show_menu()
		return
	_i_am_host = true

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.text = LocalizationManager.get_string("waiting_opponent", _game_state.selected_language)
	_status_label.modulate = COL_LAN
	_body_holder.add_child(_status_label)

	var ips = _lan.get_local_ip_candidates()
	var ip_label := Label.new()
	ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	ip_label.text = LocalizationManager.get_string("tell_them_join", _game_state.selected_language) % (", ".join(ips) if not ips.is_empty() else LocalizationManager.get_string("ip_detect_fail", _game_state.selected_language))
	ip_label.add_theme_font_size_override("font_size", 15)
	_body_holder.add_child(ip_label)

	var cancel_btn := Button.new()
	cancel_btn.text = LocalizationManager.get_string("cancel_hosting", _game_state.selected_language)
	cancel_btn.flat = true
	cancel_btn.modulate = COL_MUTE
	_body_holder.add_child(cancel_btn)
	cancel_btn.pressed.connect(func():
		_lan.shutdown()
		_show_menu()
	)


func _show_join_screen() -> void:
	_clear_body()

	var label := Label.new()
	label.text = LocalizationManager.get_string("enter_host_ip", _game_state.selected_language)
	_body_holder.add_child(label)

	var ip_edit := LineEdit.new()
	ip_edit.placeholder_text = "e.g. 192.168.1.42"
	_body_holder.add_child(ip_edit)

	var connect_btn := Button.new()
	connect_btn.text = LocalizationManager.get_string("connect_label", _game_state.selected_language)
	connect_btn.custom_minimum_size = Vector2(0, 44)
	_body_holder.add_child(connect_btn)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.modulate = COL_MUTE
	_body_holder.add_child(_status_label)

	connect_btn.pressed.connect(func():
		var addr = ip_edit.text.strip_edges()
		if addr == "":
			_status_label.text = LocalizationManager.get_string("enter_ip_first", _game_state.selected_language)
			_status_label.modulate = COL_RED
			return
		var err = _lan.join_match(addr)
		if err != OK:
			_status_label.text = LocalizationManager.get_string("connect_error", _game_state.selected_language) % err
			_status_label.modulate = COL_RED
			return
		_last_join_address = addr
		_i_am_host = false
		_status_label.text = LocalizationManager.get_string("connecting", _game_state.selected_language)
		_status_label.modulate = COL_LAN
		connect_btn.disabled = true
	)

	var cancel_btn := Button.new()
	cancel_btn.text = LocalizationManager.get_string("cancel", _game_state.selected_language)
	cancel_btn.flat = true
	cancel_btn.modulate = COL_MUTE
	_body_holder.add_child(cancel_btn)
	cancel_btn.pressed.connect(func():
		_lan.shutdown()
		_show_menu()
	)


# --- Connection signal handlers ---

func _on_opponent_connected(_id: int) -> void:
	# Host side: opponent joined. Generate the shared word list and kick
	# off the match a few seconds from now so both sides' countdowns land
	# on the same moment despite normal LAN latency.
	if not is_instance_valid(_status_label):
		return
	_status_label.text = LocalizationManager.get_string("opponent_connected", _game_state.selected_language)

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pool = WordBank.pool_for_theme_mix(WordBank.theme_names())
	var word_list = WordBank.get_batch(pool, WORD_COUNT, rng)
	var start_time = Time.get_unix_time_from_system() + 3.0
	_lan.send_match_start(word_list, start_time)


func _on_opponent_disconnected() -> void:
	if _match_active:
		_running = false
		_match_active = false
		_clear_body()
		_title_label.add_theme_color_override("font_color", COL_RED)
		_subtitle_label.text = LocalizationManager.get_string("opponent_disconnected_mid", _game_state.selected_language)

		var reconnect_btn := Button.new()
		reconnect_btn.text = LocalizationManager.get_string("try_reconnecting", _game_state.selected_language)
		reconnect_btn.custom_minimum_size = Vector2(0, 44)
		_body_holder.add_child(reconnect_btn)
		reconnect_btn.pressed.connect(_attempt_reconnect)

		var back_btn := Button.new()
		back_btn.text = LocalizationManager.get_string("back_to_hub", _game_state.selected_language)
		back_btn.flat = true
		back_btn.modulate = COL_MUTE
		_body_holder.add_child(back_btn)
		back_btn.pressed.connect(func(): _leave(false))
	else:
		_subtitle_label.text = LocalizationManager.get_string("opponent_disconnected", _game_state.selected_language)
		_show_menu()


## Reconnect always restarts as a fresh match (new word list, new
## countdown) rather than trying to resume mid-race state over the
## network - far simpler and safer than reconciling two devices' idea of
## "how far into the old race were we" after a drop.
func _attempt_reconnect() -> void:
	if _i_am_host:
		_show_host_screen()
	elif _last_join_address != "":
		_show_join_screen()
		# _show_join_screen rebuilds a blank IP field; prefill it so the
		# player doesn't have to retype the address they already used.
		var ip_edit: LineEdit = _body_holder.find_child("LineEdit", true, false)
		if is_instance_valid(ip_edit):
			ip_edit.text = _last_join_address
	else:
		_show_menu()


func _on_connected_to_host() -> void:
	if is_instance_valid(_status_label):
		_status_label.text = LocalizationManager.get_string("connected_waiting_host", _game_state.selected_language)
		_status_label.modulate = COL_LAN


func _on_connection_failed() -> void:
	if is_instance_valid(_status_label):
		_status_label.text = LocalizationManager.get_string("unreachable_address", _game_state.selected_language)
		_status_label.modulate = COL_RED


# --- Match start / countdown ---

func _on_match_start_received(word_list: Array, start_unix_time: float) -> void:
	_word_list = word_list
	_match_active = true
	_own_finish_elapsed = -1.0
	_opponent_words_done = 0
	_opponent_finish_elapsed = -1.0
	_clear_body()

	_subtitle_label.text = LocalizationManager.get_string("race_starts_soon", _game_state.selected_language)

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
	you_row.modulate = COL_LAN
	bars_vb.add_child(you_row)

	_you_bar = ProgressBar.new()
	_you_bar.max_value = _word_list.size()
	_you_bar.show_percentage = false
	_you_bar.custom_minimum_size = Vector2(0, 18)
	var you_fill := StyleBoxFlat.new()
	you_fill.bg_color = COL_LAN
	you_fill.set_corner_radius_all(6)
	_you_bar.add_theme_stylebox_override("fill", you_fill)
	bars_vb.add_child(_you_bar)

	var opp_row := Label.new()
	opp_row.text = LocalizationManager.get_string("opponent_label", _game_state.selected_language).to_upper()
	opp_row.add_theme_font_size_override("font_size", 13)
	opp_row.modulate = COL_OPP
	bars_vb.add_child(opp_row)

	_opp_bar = ProgressBar.new()
	_opp_bar.max_value = _word_list.size()
	_opp_bar.show_percentage = false
	_opp_bar.custom_minimum_size = Vector2(0, 18)
	var opp_fill := StyleBoxFlat.new()
	opp_fill.bg_color = COL_OPP
	opp_fill.set_corner_radius_all(6)
	_opp_bar.add_theme_stylebox_override("fill", opp_fill)
	bars_vb.add_child(_opp_bar)

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
	_word_label.text = LocalizationManager.get_string("get_ready", _game_state.selected_language).to_upper()
	_word_label.add_theme_font_size_override("font_size", 26)
	_word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_word_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	word_panel.add_child(_word_label)

	_input_edit = LineEdit.new()
	_input_edit.placeholder_text = "Type it here…"
	_input_edit.editable = false
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
			_finish()
		else:
			_leave(true)
	)

	call_deferred("_run_start_countdown", start_unix_time)


func _run_start_countdown(start_unix_time: float) -> void:
	while Time.get_unix_time_from_system() < start_unix_time - 1.0:
		if not is_instance_valid(_word_label) or not _match_active:
			return
		var remaining = int(ceil(start_unix_time - Time.get_unix_time_from_system()))
		_word_label.text = str(remaining)
		await get_tree().create_timer(0.3).timeout

	if not is_instance_valid(_word_label) or not _match_active:
		return
	_word_label.text = LocalizationManager.get_string("go_label", _game_state.selected_language).to_upper()
	if _audio: _audio.play_whoosh()
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(_input_edit) or not _match_active:
		return

	_hits = 0
	_misses = 0
	_words_typed = 0
	_queue_index = 0
	_start_msec = Time.get_ticks_msec()
	_running = true
	_input_edit.editable = true
	_advance_word()
	call_deferred("_focus_input")


func _focus_input() -> void:
	if is_instance_valid(_input_edit):
		_input_edit.grab_focus()


# --- Racing ---

func _advance_word() -> void:
	if _queue_index >= _word_list.size():
		_finish()
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
		if is_instance_valid(_lan):
			_lan.send_progress(_words_typed)
	else:
		_misses += 1
		if _audio: _audio.play_error()
		if is_instance_valid(_game_state):
			_game_state._add_persistent_missed_word(_current_word)
	_advance_word()


func _on_opponent_progress(words_done: int) -> void:
	_opponent_words_done = words_done
	if is_instance_valid(_opp_bar):
		_opp_bar.value = words_done


func _on_opponent_finished(elapsed_seconds: float) -> void:
	_opponent_finish_elapsed = elapsed_seconds
	if _own_finish_elapsed >= 0.0:
		_show_results()


func _finish() -> void:
	if not _running and _own_finish_elapsed >= 0.0:
		return
	_running = false
	if is_instance_valid(_input_edit):
		_input_edit.editable = false

	_own_finish_elapsed = max((Time.get_ticks_msec() - _start_msec) / 1000.0, 0.05)
	if is_instance_valid(_lan):
		_lan.send_finished(_own_finish_elapsed)

	if _opponent_finish_elapsed >= 0.0 or _opponent_words_done < _word_list.size():
		_show_results()
	# else: wait for the opponent's finished RPC before showing results,
	# so both screens agree on who actually won.


func _show_results() -> void:
	_match_active = false
	_clear_body()

	var total = _hits + _misses
	var acc = 100.0 if total <= 0 else (float(_hits) / total) * 100.0
	var wpm = (_words_typed / (_own_finish_elapsed / 60.0)) if _own_finish_elapsed > 0 else 0.0

	var you_finished_all = _words_typed >= _word_list.size()
	var opp_finished_all = _opponent_words_done >= _word_list.size() or _opponent_finish_elapsed >= 0.0
	var you_won: bool
	var tie := false
	if you_finished_all and opp_finished_all and _opponent_finish_elapsed >= 0.0:
		if is_equal_approx(_own_finish_elapsed, _opponent_finish_elapsed):
			tie = true
			you_won = false
		else:
			you_won = _own_finish_elapsed < _opponent_finish_elapsed
	else:
		you_won = you_finished_all and not opp_finished_all

	if _audio:
		if tie:
			_audio.play_notification()
		elif you_won:
			_audio.play_level_up_sting()
		else:
			_audio.play_game_over_voice()

	var result_label := Label.new()
	if tie:
		result_label.text = LocalizationManager.get_string("match_tied", _game_state.selected_language).to_upper()
		result_label.add_theme_color_override("font_color", COL_GOLD)
	elif you_won:
		result_label.text = LocalizationManager.get_string("you_win", _game_state.selected_language).to_upper()
		result_label.add_theme_color_override("font_color", COL_LAN)
	else:
		result_label.text = LocalizationManager.get_string("opponent_wins", _game_state.selected_language).to_upper()
		result_label.add_theme_color_override("font_color", COL_OPP)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 22)
	_body_holder.add_child(result_label)

	var detail := Label.new()
	detail.text = LocalizationManager.get_string("lan_race_detail", _game_state.selected_language) % [_words_typed, _word_list.size(), wpm, acc]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 14)
	detail.modulate = COL_MUTE
	_body_holder.add_child(detail)

	if is_instance_valid(_game_state) and _words_typed > 0:
		_game_state.register_practice_result("LAN Versus", wpm, acc, _words_typed)
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

	var share_btn := Button.new()
	share_btn.text = LocalizationManager.get_string("share_result", _game_state.selected_language)
	_body_holder.add_child(share_btn)
	var share_feedback := Label.new()
	share_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	share_feedback.add_theme_font_size_override("font_size", 13)
	share_feedback.modulate = COL_MINT
	share_btn.pressed.connect(func():
		var outcome = "Tied" if tie else ("Won" if you_won else "Lost")
		DisplayServer.clipboard_set("%s a LAN Versus match in Type Blast — %.0f WPM! 🆚📶" % [outcome, wpm])
		share_feedback.text = LocalizationManager.get_string("share_copied", _game_state.selected_language)
		if not share_feedback.is_inside_tree():
			_body_holder.add_child(share_feedback)
	)

	var done_btn := Button.new()
	done_btn.text = LocalizationManager.get_string("done", _game_state.selected_language).to_upper()
	done_btn.custom_minimum_size = Vector2(0, 48)
	_body_holder.add_child(done_btn)
	done_btn.pressed.connect(func():
		_leave(false)
	)
