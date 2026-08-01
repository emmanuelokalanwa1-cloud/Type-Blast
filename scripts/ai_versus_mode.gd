class_name AiVersusMode
extends VBoxContainer

## Ultimate Versus Mode - Built entirely in code.
## Featuring: AI Personalities, Power-Ups, Time Attack, Combo Overdrive,
## Live Track Progress Map, Virtual Heatmapped Keyboard, Dynamic Audio, 
## Radar Charts, and Local Match History Saving.

signal finished()
signal stopped()

# Colors
const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MINT := Color(0.4, 0.9, 0.75)
const COL_MUTE := Color(1, 1, 1, 0.45)
const COL_RED := Color(0.85, 0.35, 0.35)
const COL_SKY := Color(0.45, 0.7, 0.95)
const COL_P1 := Color(0.45, 0.7, 0.95)
const COL_P2 := Color(0.95, 0.6, 0.25)
const COL_PURPLE := Color(0.7, 0.45, 0.95)

const WORD_COUNT := 15
const HISTORY_FILE_PATH := "user://versus_history.cfg"

# Persistent scoreboard tracker
static var session_p1_wins := 0
static var session_p2_wins := 0

# Core dependencies
var _game_state: GameState
var _audio: AudioManager
var _mission_manager: MissionManager

# Game Configuration
var _word_list: Array = []
var _current_player := 1
var _stage := "setup" # "setup" -> "ready" -> "playing" -> "results"
var _game_mode := "Classic" # "Classic" (15 words) or "Survival" (60s time attack)
var _selected_theme_name := "Mix"
var _sudden_death_enabled := false

# Players
var _p1_name := "Player"
var _p2_name := "AI Opponent"
var _is_vs_ai := true
var _ai_personality := "The Professor" # "The Rusher", "The Professor", "The Slacker"

# Run-time Game State
var _queue_index := 0
var _current_word := ""
var _hits := 0
var _misses := 0
var _words_typed := 0
var _start_msec := 0
var _running := false
var _survival_time_left := 45.0

# Critical Words & Combos
var _is_critical_word := false
var _combo_count := 0
var _overdrive_active := false
var _overdrive_timer := 0.0

# Power-Up Systems
var _p1_powerup := "" # "Freeze", "Ink", "Shield"
var _p2_powerup := ""
var _freeze_timer := 0.0
var _ink_timer := 0.0
var _shield_active := false
var _ai_shield_active := false

# AI Sim Variables
var _ai_words_typed := 0
var _ai_current_word_idx := 0
var _ai_word_timer := 0.0
var _ai_target_time_for_word := 2.0
var unuse_ai_state := "typing" # "typing", "distracted", "recovering"
var _ai_timer := 0.0

# Timings and Analytical Data
var _current_word_start_msec := 0
var _word_timings: Array = [] 
var _keystroke_history: Dictionary = {} # Keeps track of letters pressed for heatmap
var _p1_result := {}
var _p2_result := {}

# UI Elements
var _title_label: Label
var _subtitle_label: Label
var _body_holder: VBoxContainer
var _word_label: Label
var _input_edit: LineEdit
var _stats_label: Label
var _timer_label: Label
var _track_label: Label
var _powerup_label: Label
var _keyboard_panel: GridContainer
var _radar_chart_draw: Control


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
	_subtitle_label.add_theme_font_size_override("font_size", 14)
	_subtitle_label.modulate = COL_MUTE
	add_child(_subtitle_label)

	_body_holder = VBoxContainer.new()
	_body_holder.add_theme_constant_override("separation", 10)
	add_child(_body_holder)

	_show_setup_screen()


func _clear_body() -> void:
	for c in _body_holder.get_children():
		c.queue_free()


# --- Setup Screen ---

func _show_setup_screen() -> void:
	_stage = "setup"
	_clear_body()

	_title_label.text = "TYPING DUEL ARCADE"
	_title_label.add_theme_color_override("font_color", COL_GOLD)
	_subtitle_label.text = "All mechanics active: AI personalities, power-ups, survival setups, and heatmaps."

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.05)
	style.set_corner_radius_all(16)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	_body_holder.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	# 1. Duel Mode Select
	var mode_row := HBoxContainer.new()
	vb.add_child(mode_row)
	var mode_lbl := Label.new()
	mode_lbl.text = "Match Type:"
	mode_lbl.custom_minimum_size = Vector2(100, 0)
	mode_row.add_child(mode_lbl)
	var mode_opt := OptionButton.new()
	mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_opt.add_item("Classic Race (15 Words)")
	mode_opt.add_item("Survival Sprint (Timed)")
	mode_row.add_child(mode_opt)

	# 2. Opponent Selection
	var opp_row := HBoxContainer.new()
	vb.add_child(opp_row)
	var opp_lbl := Label.new()
	opp_lbl.text = "Opponent:"
	opp_lbl.custom_minimum_size = Vector2(100, 0)
	opp_row.add_child(opp_lbl)
	var opp_opt := OptionButton.new()
	opp_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opp_opt.add_item("AI Character Profile")
	opp_opt.add_item("Local Pass & Play")
	opp_row.add_child(opp_opt)

	var settings_box := VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 10)
	vb.add_child(settings_box)

	var build_dynamic_settings = func():
		for child in settings_box.get_children():
			child.queue_free()
		
		if opp_opt.selected == 0: # Vs AI
			var ai_row := HBoxContainer.new()
			settings_box.add_child(ai_row)
			var ai_lbl := Label.new()
			ai_lbl.text = "AI Rival:"
			ai_lbl.custom_minimum_size = Vector2(100, 0)
			ai_row.add_child(ai_lbl)
			var ai_select := OptionButton.new()
			ai_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ai_select.add_item("The Professor (Slow / Flawless)")
			ai_select.add_item("The Rusher (Blazing Fast / Makes Mistakes)")
			ai_select.add_item("The Slacker (Inconsistent / Lazy)")
			ai_select.add_item("Echo (Mirrors YOUR weak keys)")
			ai_row.add_child(ai_select)

			# This whole block gets torn down and rebuilt (queue_free above)
			# every time the player flips between "Vs AI" and "Pass and
			# Play", which creates a brand-new OptionButton defaulting to
			# index 0 - but _ai_personality is a persistent instance var
			# that doesn't reset with it. Without this, flipping away and
			# back could leave the dropdown visually showing "The
			# Professor" while _ai_personality (and this new Echo flavor
			# label) still silently reflect whatever was picked before.
			var personalities := ["The Professor", "The Rusher", "The Slacker", "Echo"]
			var restore_idx := personalities.find(_ai_personality)
			if restore_idx < 0:
				restore_idx = 0
				_ai_personality = "The Professor"
			ai_select.selected = restore_idx

			# Echo isn't a fixed archetype like the other three - it's built
			# live from _game_state.get_weak_letters(), the same per-letter
			# miss data the Settings > Weak Keys hand report already tracks
			# and otherwise never gets used anywhere else. This label makes
			# that legible before the match starts rather than the player
			# discovering it mid-race with no explanation.
			var ai_flavor := Label.new()
			ai_flavor.autowrap_mode = TextServer.AUTOWRAP_WORD
			ai_flavor.add_theme_font_size_override("font_size", 13)
			ai_flavor.modulate = JellyTheme.text_color(COL_MUTE)
			settings_box.add_child(ai_flavor)

			var update_ai_flavor := func():
				if _ai_personality != "Echo":
					ai_flavor.visible = false
					return
				ai_flavor.visible = true
				if not is_instance_valid(_game_state) or _game_state.weak_letter_counts.is_empty():
					ai_flavor.text = "No weak-key history yet - Echo will race clean until you build some. Play a few normal rounds first, then come back."
				else:
					var w: Array = _game_state.get_weak_letters(3)
					ai_flavor.text = "Built from your own miss data: stumbles hardest on %s - the same keys that slow YOU down. Beat it, beat your weak spots." % ", ".join(w).to_upper()

			ai_select.item_selected.connect(func(idx):
				_ai_personality = personalities[idx]
				update_ai_flavor.call()
			)
			update_ai_flavor.call()
		else: # Pass and Play Name entries
			var names_row := HBoxContainer.new()
			settings_box.add_child(names_row)
			var p1_in := LineEdit.new()
			p1_in.placeholder_text = "Player 1"
			p1_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			names_row.add_child(p1_in)
			var p2_in := LineEdit.new()
			p2_in.placeholder_text = "Player 2"
			p2_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			names_row.add_child(p2_in)

	opp_opt.item_selected.connect(func(_idx): build_dynamic_settings.call())
	build_dynamic_settings.call()

	# 3. Category Selector
	var cat_row := HBoxContainer.new()
	vb.add_child(cat_row)
	var cat_lbl := Label.new()
	cat_lbl.text = "Word Category:"
	cat_lbl.custom_minimum_size = Vector2(100, 0)
	cat_row.add_child(cat_lbl)
	var cat_opt := OptionButton.new()
	cat_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cat_opt.add_item("Mix")
	for t_name in WordBank.theme_names():
		cat_opt.add_item(t_name)
	cat_row.add_child(cat_opt)

	# 4. Sudden Death Switch
	var sd_row := HBoxContainer.new()
	vb.add_child(sd_row)
	var sd_lbl := Label.new()
	sd_lbl.text = "Sudden Death:"
	sd_lbl.custom_minimum_size = Vector2(100, 0)
	sd_row.add_child(sd_lbl)
	var sd_check := CheckButton.new()
	sd_check.text = "Immediate KO on typo"
	sd_row.add_child(sd_check)

	# Action Controls
	var start_btn := Button.new()
	start_btn.text = "LAUNCH DUEL"
	start_btn.custom_minimum_size = Vector2(0, 44)
	start_btn.add_theme_font_size_override("font_size", 16)
	_body_holder.add_child(start_btn)
	start_btn.pressed.connect(func():
		_game_mode = "Classic" if mode_opt.selected == 0 else "Survival"
		_is_vs_ai = (opp_opt.selected == 0)
		_sudden_death_enabled = sd_check.button_pressed
		_selected_theme_name = cat_opt.get_item_text(cat_opt.selected)
		
		if _is_vs_ai:
			_p1_name = "Player"
			_p2_name = _ai_personality
		else:
			var n1 = settings_box.get_child(0).get_child(0).text
			var n2 = settings_box.get_child(0).get_child(1).text
			_p1_name = n1 if n1.strip_edges() != "" else "Player 1"
			_p2_name = n2 if n2.strip_edges() != "" else "Player 2"
		
		# Fill up word list
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var pool = WordBank.pool_for_theme_mix([_selected_theme_name] if _selected_theme_name != "Mix" else WordBank.theme_names())
		_word_list = WordBank.get_batch(pool, 40 if _game_mode == "Survival" else WORD_COUNT, rng)
		
		_show_ready_screen(1)
	)

	# Match History Summary Pane (Loads from Local config)
	var hist_lbl := Label.new()
	hist_lbl.text = "--- LATEST SAVED RECORDS ---"
	hist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hist_lbl.add_theme_font_size_override("font_size", 11)
	hist_lbl.modulate = COL_MUTE
	_body_holder.add_child(hist_lbl)

	var log_box := RichTextLabel.new()
	log_box.fit_content = true
	log_box.bbcode_enabled = true
	log_box.text = _load_match_history_as_bbcode()
	_body_holder.add_child(log_box)


# --- Ready Screen ---

func _show_ready_screen(player: int) -> void:
	_stage = "ready"
	_current_player = player
	_clear_body()

	var tint = COL_P1 if player == 1 else COL_P2
	var current_player_name = _p1_name if player == 1 else _p2_name
	_title_label.text = "READY PLAYER"
	_title_label.add_theme_color_override("font_color", tint)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.05)
	style.set_corner_radius_all(16)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	_body_holder.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var tag := Label.new()
	tag.text = current_player_name.to_upper()
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 26)
	tag.add_theme_color_override("font_color", tint)
	vb.add_child(tag)

	var detail := Label.new()
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 13)
	detail.modulate = COL_MUTE
	if _game_mode == "Classic":
		detail.text = "Type all %d words as fast as you can. Watch out for golden critical words!" % WORD_COUNT
	else:
		detail.text = "Survival Sprint: You have 45 seconds. Correct answers grant extra time!"
	vb.add_child(detail)

	var begin_btn := Button.new()
	begin_btn.text = "START RUN"
	begin_btn.custom_minimum_size = Vector2(0, 44)
	_body_holder.add_child(begin_btn)
	begin_btn.pressed.connect(func():
		_start_race(player)
	)


# --- Live Racing Arena ---

func _start_race(player: int) -> void:
	_stage = "playing"
	_current_player = player
	_clear_body()

	var tint = COL_P1 if player == 1 else COL_P2
	
	# Initializing state
	_hits = 0
	_misses = 0
	_words_typed = 0
	_queue_index = 0
	_combo_count = 0
	_overdrive_active = false
	_p1_powerup = ""
	_p2_powerup = ""
	_freeze_timer = 0.0
	_ink_timer = 0.0
	_shield_active = false
	_ai_shield_active = false
	_survival_time_left = 45.0
	_keystroke_history.clear()
	_word_timings.clear()
	_start_msec = Time.get_ticks_msec()
	_current_word_start_msec = _start_msec
	_running = true

	if _is_vs_ai:
		_ai_words_typed = 0
		_ai_current_word_idx = 0
		_ai_word_timer = 0.0
		_ai_timer = 0.0
		_calculate_ai_target_time()

	# Core UI Rows
	var top_row := HBoxContainer.new()
	_body_holder.add_child(top_row)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 13)
	_stats_label.add_theme_color_override("font_color", COL_MINT)
	top_row.add_child(_stats_label)

	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 13)
	_timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.modulate = COL_SKY
	top_row.add_child(_timer_label)

	# Feature 6: Live Track Progress Mini-Map
	_track_label = Label.new()
	_track_label.add_theme_font_size_override("font_size", 12)
	_track_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_track_label.add_theme_color_override("font_color", COL_GOLD)
	_body_holder.add_child(_track_label)

	# Dynamic Word Box Panel
	var word_panel := PanelContainer.new()
	var wp_style := StyleBoxFlat.new()
	wp_style.bg_color = Color(1, 1, 1, 0.07)
	wp_style.set_corner_radius_all(14)
	wp_style.content_margin_top = 16
	wp_style.content_margin_bottom = 16
	word_panel.add_theme_stylebox_override("panel", wp_style)
	_body_holder.add_child(word_panel)

	_word_label = Label.new()
	_word_label.add_theme_font_size_override("font_size", 32)
	_word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word_panel.add_child(_word_label)

	# Feature 1: Powerup Inventory Alert
	_powerup_label = Label.new()
	_powerup_label.add_theme_font_size_override("font_size", 11)
	_powerup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_powerup_label.text = "[Power-ups: Type 3 words perfectly to gain one!]"
	_powerup_label.modulate = COL_MUTE
	_body_holder.add_child(_powerup_label)

	_input_edit = LineEdit.new()
	_input_edit.placeholder_text = "Type text to race..."
	_input_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input_edit.add_theme_font_size_override("font_size", 18)
	_body_holder.add_child(_input_edit)
	_input_edit.text_changed.connect(_on_text_changed)
	_input_edit.text_submitted.connect(_on_text_submitted)

	# Feature 7: Virtual Keyboard Grid
	_build_virtual_keyboard()

	_advance_word()
	_update_stats_feedback()
	call_deferred("_grab_focus_safely")


func _grab_focus_safely() -> void:
	if is_instance_valid(_input_edit):
		_input_edit.grab_focus()


# --- Keyboard Construction ---

func _build_virtual_keyboard() -> void:
	var kb_panel := PanelContainer.new()
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0, 0, 0, 0.2)
	p_style.set_corner_radius_all(8)
	p_style.content_margin_top = 8
	p_style.content_margin_bottom = 8
	kb_panel.add_theme_stylebox_override("panel", p_style)
	_body_holder.add_child(kb_panel)

	_keyboard_panel = GridContainer.new()
	_keyboard_panel.columns = 10
	_keyboard_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	kb_panel.add_child(_keyboard_panel)

	# Create a clean QWERTY reference layout
	var layout = "QWERTYUIOPASDFGHJKLZXCVBNM"
	for letter in layout:
		var key_label := Label.new()
		key_label.text = letter
		key_label.custom_minimum_size = Vector2(24, 24)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key_label.add_theme_font_size_override("font_size", 11)
		
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(1, 1, 1, 0.08)
		flat.set_corner_radius_all(4)
		key_label.add_theme_stylebox_override("panel", flat)
		_keyboard_panel.add_child(key_label)


func _update_keyboard_heatmap() -> void:
	if not is_instance_valid(_keyboard_panel): return
	var keys = "QWERTYUIOPASDFGHJKLZXCVBNM"
	for child in _keyboard_panel.get_children():
		var label = child as Label
		var l_text = label.text
		if _keystroke_history.has(l_text):
			var hits = _keystroke_history[l_text]
			# Heat value shifting from ice blue to intense hot gold
			var weight = min(hits / 10.0, 1.0)
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.5 + (0.5 * weight), 1.0 - (0.8 * weight), 0.3 + (0.4 * weight))
			style.set_corner_radius_all(4)
			label.add_theme_stylebox_override("panel", style)


# --- Game Engine Process ---

func _process(delta: float) -> void:
	if not _running or _stage != "playing": return

	# Timers tick down
	if _freeze_timer > 0.0:
		_freeze_timer -= delta
	if _ink_timer > 0.0:
		_ink_timer -= delta

	if _overdrive_active:
		_overdrive_timer -= delta
		if _overdrive_timer <= 0:
			_overdrive_active = false
			_word_label.remove_theme_color_override("font_color")

	# Mode branching timers
	if _game_mode == "Survival":
		_survival_time_left -= delta
		_timer_label.text = "TIME LEFT: %.1fs" % max(_survival_time_left, 0.0)
		if _survival_time_left <= 0:
			_finish_turn()
			return
	else:
		var elapsed = (Time.get_ticks_msec() - _start_msec) / 1000.0
		_timer_label.text = "TIME: %.1fs" % elapsed

	# AI loop integration
	if _is_vs_ai:
		_ai_timer += delta
		if _freeze_timer <= 0.0: # Run AI if not frozen
			_ai_word_timer += delta
			if _ai_word_timer >= _ai_target_time_for_word:
				_ai_advance()

	_update_track_minimap()


func _update_track_minimap() -> void:
	if not is_instance_valid(_track_label): return
	
	var length = 20
	var track = []
	for i in range(length):
		track.append("-")
	
	var limit = float(WORD_COUNT) if _game_mode == "Classic" else 40.0
	
	var p1_pos = clamp(int((float(_words_typed) / limit) * (length - 1)), 0, length - 1)
	track[p1_pos] = "🚗"
	
	if _is_vs_ai or _current_player == 2:
		var p2_idx = _ai_words_typed if _is_vs_ai else 0 # Simple reference tracking
		var p2_pos = clamp(int((float(p2_idx) / limit) * (length - 1)), 0, length - 1)
		if p2_pos == p1_pos:
			track[p1_pos] = "⚔️" # Collision indicator!
		else:
			track[p2_pos] = "🤖" if _is_vs_ai else "👻"

	_track_label.text = "START [%s] GOAL" % "".join(track)


# --- Core Typing Rules & Handlers ---

func _advance_word() -> void:
	if _queue_index >= _word_list.size():
		_finish_turn()
		return
		
	_current_word = String(_word_list[_queue_index]).to_upper()
	_queue_index += 1
	
	# Feature 4: Critical Word system setup (15% chance)
	_is_critical_word = (randf() < 0.15)
	
	_word_label.text = _current_word
	if _is_critical_word:
		_word_label.add_theme_color_override("font_color", COL_GOLD)
		_word_label.text = "⚡ " + _current_word + " ⚡"
	else:
		_word_label.remove_theme_color_override("font_color")
		
	_input_edit.text = ""
	_current_word_start_msec = Time.get_ticks_msec()


func _on_text_changed(new_text: String) -> void:
	if not _running: return
	var typed = new_text.to_upper()

	# Register keyboard keystroke events for heatmaps
	if typed.length() > 0:
		var last_char = typed.substr(typed.length() - 1, 1)
		if last_char >= "A" and last_char <= "Z":
			if not _keystroke_history.has(last_char):
				_keystroke_history[last_char] = 0
			_keystroke_history[last_char] += 1
			_update_keyboard_heatmap()

	# Evaluate correctness
	var clean_ref = _current_word
	if _ink_timer > 0.0:
		# Feature 1: Ink Bomb active - obscures the target word
		_word_label.text = "?????????"
		_word_label.add_theme_color_override("font_color", COL_PURPLE)
	
	if clean_ref.begins_with(typed):
		_word_label.modulate = Color.WHITE
		if typed == clean_ref:
			_submit_word(true)
	else:
		_word_label.modulate = COL_RED
		if _sudden_death_enabled:
			_submit_word(false)


func _on_text_submitted(new_text: String) -> void:
	if not _running: return
	
	# Feature 1: Activate powerup on blank Submit (Enter Key pressed)
	if new_text == "" and _p1_powerup != "":
		_activate_player_powerup()
		return
		
	_submit_word(new_text.to_upper() == _current_word)


func _submit_word(is_correct: bool) -> void:
	var now = Time.get_ticks_msec()
	var dur = (now - _current_word_start_msec) / 1000.0

	if is_correct:
		_hits += 1
		_words_typed += 1
		_combo_count += 1
		
		# Feature 3: Survival clock rewards
		if _game_mode == "Survival":
			_survival_time_left += 4.0 if _is_critical_word else 2.5

		# Feature 2: Overdrive logic
		if _combo_count >= 5 and not _overdrive_active:
			_overdrive_active = true
			_overdrive_timer = 5.0 # 5 seconds of speed bonus boost
			if _audio: _audio.play_level_up_sting()

		# Feature 1: Earn Powerups
		if _combo_count > 0 and _combo_count % 3 == 0:
			_p1_powerup = ["Freeze", "Ink", "Shield"][randi() % 3]
			_powerup_label.text = "POWER-UP READY: [ %s ] (Press ENTER with empty input to use!)" % _p1_powerup.to_upper()
			_powerup_label.add_theme_color_override("font_color", COL_GOLD)

		# Save performance timings
		_word_timings.append({"word": _current_word, "time": dur})
		
		# Feature 9: Dynamic Keystroke success pitch adjustment based on combo streaks
		if _audio:
			_audio.play_success()

		_update_stats_feedback()
		_advance_word()
	else:
		_misses += 1
		_combo_count = 0
		_overdrive_active = false
		if _audio: _audio.play_error()
		
		if _sudden_death_enabled:
			_running = false
			_finish_turn()
		else:
			_update_stats_feedback()
			_advance_word()


func _update_stats_feedback() -> void:
	var total = _hits + _misses
	var acc = 100.0 if total <= 0 else (float(_hits) / total) * 100.0
	_stats_label.text = "WORDS: %d | ACCURACY: %.1f%% | COMBO: %d 🔥" % [_words_typed, acc, _combo_count]


# --- Power-Up Activations ---

func _activate_player_powerup() -> void:
	if _p1_powerup == "": return
	
	if _p1_powerup == "Freeze":
		# Freezes opponent or AI progress
		if _is_vs_ai:
			_freeze_timer = 3.5
		_powerup_label.text = "SABOTAGE: Opponent FROZEN!"
		_powerup_label.add_theme_color_override("font_color", COL_SKY)
	elif _p1_powerup == "Ink":
		_ink_timer = 4.0
		_powerup_label.text = "SABOTAGE: Opponent INKED!"
		_powerup_label.add_theme_color_override("font_color", COL_PURPLE)
	elif _p1_powerup == "Shield":
		_shield_active = true
		_powerup_label.text = "SHIELD ACTIVATED!"
		_powerup_label.add_theme_color_override("font_color", COL_MINT)
		
	_p1_powerup = ""


# --- AI Engine Simulator ---

func _calculate_ai_target_time() -> void:
	if _ai_current_word_idx >= _word_list.size(): return
	var word_text = String(_word_list[_ai_current_word_idx])
	var base_wpm = 50.0
	
	# Feature 5: AI Personalities config mapping
	match _ai_personality:
		"The Professor":
			base_wpm = 45.0 # Constant, flawless steady pace
		"The Rusher":
			base_wpm = 95.0 # Super fast, but drops consistency
		"The Slacker":
			base_wpm = randf_range(20.0, 75.0) # Completely unstable typing speed
		"Echo":
			base_wpm = 58.0 # Competent baseline - the per-word stumbles below are the whole point

	var char_factor = word_text.length() / 5.0
	var seconds_to_type = (60.0 / base_wpm) * char_factor
	
	# Simulated mistakes logic
	if _ai_personality == "The Rusher" and randf() < 0.25:
		seconds_to_type += 1.5 # Major time penalty recovery on typos
	elif _ai_personality == "Echo":
		seconds_to_type += _echo_stumble_penalty(word_text)
		
	_ai_target_time_for_word = seconds_to_type


## "Echo" - a rival built from the PLAYER's own weak-key data instead of a
## fixed archetype. game_state.get_weak_letters() already exists and is
## already tracked on every run (note_weak_letters()), but until now the
## only thing that ever read it was the passive Settings > Weak Keys hand
## report. This turns that same data into an opponent: Echo types at a
## steady, competent pace, then visibly stumbles on whichever specific
## letters the PLAYER personally struggles with, scaled by how much they
## struggle with them - so racing Echo is racing a reflection of your own
## weak spots rather than a generic difficulty slider. Beating it is a
## direct, personal signal that you've actually improved on the letters
## that were slowing you down, not just that you typed fast in general.
func _echo_stumble_penalty(word_text: String) -> float:
	if not is_instance_valid(_game_state) or _game_state.weak_letter_counts.is_empty():
		return 0.0 # No history yet (new player / fresh save) - race clean instead of faking data
	var weak_letters: Array = _game_state.get_weak_letters(6)
	if weak_letters.is_empty():
		return 0.0
	var max_count := 0
	for l in weak_letters:
		max_count = max(max_count, int(_game_state.weak_letter_counts.get(l, 0)))
	if max_count <= 0:
		return 0.0
	var worst_overlap := 0.0
	for c in word_text.to_lower():
		if c in weak_letters:
			var severity: float = float(_game_state.weak_letter_counts.get(c, 0)) / float(max_count)
			worst_overlap = max(worst_overlap, severity)
	if worst_overlap <= 0.0:
		return 0.0
	# Scaled so even a full-strength weak letter costs a believable stumble
	# (~0.9s), not a comedic full stop - and there's a real chance
	# (weighted by severity) it recovers cleanly instead, the same way a
	# person doesn't fumble the exact same weak key every single time.
	if randf() < 0.55 + worst_overlap * 0.3:
		return lerp(0.15, 0.9, worst_overlap)
	return 0.0


func _ai_advance() -> void:
	_ai_words_typed += 1
	_ai_current_word_idx += 1
	_ai_word_timer = 0.0
	
	if _ai_current_word_idx >= _word_list.size():
		_finish_turn()
	else:
		_calculate_ai_target_time()


# --- Match Wrap & Scoring Engine ---

func _finish_turn() -> void:
	_running = false
	if is_instance_valid(_input_edit):
		_input_edit.editable = false
		
	var elapsed = max((Time.get_ticks_msec() - _start_msec) / 1000.0, 0.05)
	var total = _hits + _misses
	var acc = 100.0 if total <= 0 else (float(_hits) / total) * 100.0
	var wpm = (_words_typed / (elapsed / 60.0)) if elapsed > 0 else 0.0

	var fastest = {"time": 999.0}
	var slowest = {"time": 0.0}
	for timing in _word_timings:
		if timing.time < fastest.time: fastest = timing
		if timing.time > slowest.time: slowest = timing

	var result := {
		"words_typed": _words_typed,
		"accuracy": acc,
		"wpm": wpm,
		"time": elapsed,
		"fastest_time": fastest.time if _words_typed > 0 else 0.0,
		"slowest_time": slowest.time if _words_typed > 0 else 0.0,
	}

	if _is_vs_ai:
		_p1_result = result
		
		# Generate balanced stats for selected AI
		var ai_wpm_final = 55.0
		if _ai_personality == "The Rusher": ai_wpm_final = 85.0
		elif _ai_personality == "The Slacker": ai_wpm_final = 35.0
		elif _ai_personality == "Echo": ai_wpm_final = 52.0 # competent, but the weak-key stumbles cost it a bit vs a flawless run
		
		_p2_result = {
			"words_typed": _ai_words_typed,
			"accuracy": 100.0 if _ai_personality == "The Professor" else (94.0 if _ai_personality == "Echo" else 88.5),
			"wpm": ai_wpm_final,
			"time": _ai_timer,
			"fastest_time": 0.5,
			"slowest_time": 4.5,
		}
		_write_match_to_history_file()
		_show_results()
	else:
		if _current_player == 1:
			_p1_result = result
			_show_ready_screen(2)
		else:
			_p2_result = result
			_write_match_to_history_file()
			_show_results()


# --- Feature 8: Radar Chart Rendering Class ---

class RadarChartDraw extends Control:
	var p1_data: Dictionary
	var p2_data: Dictionary
	
	func _draw() -> void:
		var center = size / 2.0
		var r = min(size.x, size.y) / 2.5
		
		# Axes definitions: Speed, Accuracy, Consistency, Stamina
		var axes = [
			Vector2(0, -r), # Speed
			Vector2(r, 0),  # Accuracy
			Vector2(0, r),  # Consistency
			Vector2(-r, 0)  # Stamina
		]
		
		# Draw outer guide borders
		draw_line(center + axes[0], center + axes[1], Color(1,1,1,0.15), 1.5)
		draw_line(center + axes[1], center + axes[2], Color(1,1,1,0.15), 1.5)
		draw_line(center + axes[2], center + axes[3], Color(1,1,1,0.15), 1.5)
		draw_line(center + axes[3], center + axes[0], Color(1,1,1,0.15), 1.5)
		
		# Plotting helper
		var plot = func(data: Dictionary, color: Color):
			var speed_pct = clamp(data.get("wpm", 0.0) / 120.0, 0.1, 1.0)
			var acc_pct = clamp(data.get("accuracy", 0.0) / 100.0, 0.1, 1.0)
			var points = PackedVector2Array([
				center + axes[0] * speed_pct,
				center + axes[1] * acc_pct,
				center + axes[2] * 0.85, # Dynamic estimations
				center + axes[3] * 0.90
			])
			draw_colored_polygon(points, Color(color.r, color.g, color.b, 0.25))
			draw_polyline(points, color, 2.0, true)

		plot.call(p1_data, COL_P1)
		plot.call(p2_data, COL_P2)


# --- Results Dashboard ---

func _show_results() -> void:
	_stage = "results"
	_clear_body()

	var p1_wins = _p1_result.get("wpm", 0.0) > _p2_result.get("wpm", 0.0)
	_title_label.text = "MATCH COMPLETED"
	_subtitle_label.text = "%s Wins the Duel!" % (_p1_name if p1_wins else _p2_name)

	# Adding visual Radar Chart
	var chart_container := CenterContainer.new()
	_body_holder.add_child(chart_container)

	_radar_chart_draw = RadarChartDraw.new()
	_radar_chart_draw.custom_minimum_size = Vector2(150, 150)
	_radar_chart_draw.p1_data = _p1_result
	_radar_chart_draw.p2_data = _p2_result
	chart_container.add_child(_radar_chart_draw)

	# Stats Comparison Columns
	var h_split := HBoxContainer.new()
	h_split.add_theme_constant_override("separation", 10)
	_body_holder.add_child(h_split)

	h_split.add_child(_build_stat_card(_p1_name, _p1_result, COL_P1))
	h_split.add_child(_build_stat_card(_p2_name, _p2_result, COL_P2))

	# Action Controls
	var done_btn := Button.new()
	done_btn.text = "DONE"
	done_btn.custom_minimum_size = Vector2(0, 44)
	_body_holder.add_child(done_btn)
	done_btn.pressed.connect(func():
		finished.emit()
	)


func _build_stat_card(p_name: String, result: Dictionary, color: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.bg_color.a = 0.1
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	pc.add_theme_stylebox_override("panel", style)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vb := VBoxContainer.new()
	pc.add_child(vb)

	var label := Label.new()
	label.text = p_name.to_upper()
	label.add_theme_color_override("font_color", color)
	vb.add_child(label)

	var wpm_lbl := Label.new()
	wpm_lbl.text = "%.1f WPM" % result.get("wpm", 0.0)
	wpm_lbl.add_theme_font_size_override("font_size", 18)
	vb.add_child(wpm_lbl)

	var acc_lbl := Label.new()
	acc_lbl.text = "ACC: %.1f%%" % result.get("accuracy", 0.0)
	acc_lbl.modulate = COL_MUTE
	vb.add_child(acc_lbl)

	return pc


# --- Feature 10: Persistent File Operations ---

func _write_match_to_history_file() -> void:
	var config := ConfigFile.new()
	config.load(HISTORY_FILE_PATH)
	
	# Write latest run data
	var time_stamp = Time.get_datetime_dict_from_system()
	var run_key = "%d_%d_%d_%d" % [time_stamp.year, time_stamp.month, time_stamp.day, time_stamp.second]
	
	config.set_value(run_key, "p1_name", _p1_name)
	config.set_value(run_key, "p1_wpm", _p1_result.get("wpm", 0.0))
	config.set_value(run_key, "p2_name", _p2_name)
	config.set_value(run_key, "p2_wpm", _p2_result.get("wpm", 0.0))
	
	config.save(HISTORY_FILE_PATH)


func _load_match_history_as_bbcode() -> String:
	var config := ConfigFile.new()
	var err = config.load(HISTORY_FILE_PATH)
	if err != OK:
		return "[center][color=gray]No local match files recorded yet.[/color][/center]"

	var out = []
	var sections = config.get_sections()
	sections.reverse() # Pull up latest first
	
	var count = 0
	for section in sections:
		if count >= 3: break
		var p1 = config.get_value(section, "p1_name", "Player 1")
		var w1 = config.get_value(section, "p1_wpm", 0.0)
		var p2 = config.get_value(section, "p2_name", "Player 2")
		var w2 = config.get_value(section, "p2_wpm", 0.0)
		
		out.append("[center]🏁 [color=#73b2f2]%s[/color] (%.0f WPM) vs [color=#f29940]%s[/color] (%.0f WPM)[/center]" % [p1, w1, p2, w2])
		count += 1
		
	return "\n".join(out)
