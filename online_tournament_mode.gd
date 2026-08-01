class_name OnlineTournamentMode
extends VBoxContainer

## Multi-player online tournament bracket, using TournamentManager (a
## WebSocket connection to the relay server, same server as
## InternetMultiplayerManager but a separate connection and its own
## "tournament_*" message namespace - see TournamentManager.gd's header
## comment and relay-server/server.js).
##
## One player creates a tournament (picks a bracket size: 2/4/8/16) and
## gets a short room code back; others join with that code. The host
## starts it once enough people are in. From then on the SERVER runs the
## whole thing: it builds the bracket, generates the word list for every
## match, decides winners, and pushes live bracket updates to everyone -
## including players who are waiting on a later round or already
## eliminated, so they can keep watching.
##
## *** EXPERIMENTAL / NEW *** - same caveat as InternetVersusMode: this
## is real networking code but hasn't been run between real devices
## against a live deployed server in this environment. Test a real
## multi-device pass before relying on it for anything you'd call
## "shipped".
##
## Embedded inside MoreScreen's content panel, same pattern as
## InternetVersusMode. Doesn't touch score/lives/high_scores/career
## state beyond logging one run_history row per match played, same as
## the other online mode.
##
## NOTE ON TEXT: unlike the rest of the app, this screen's strings are
## plain English literals rather than LocalizationManager keys, to keep
## this drop-in file self-contained. If/when this ships for real, pull
## these into the locale files the same way everything else was done.

signal finished()
signal stopped()

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MINT := Color(0.4, 0.9, 0.75)
const COL_MUTE := Color(1, 1, 1, 0.55)
const COL_RED := Color(0.85, 0.35, 0.35)
const COL_ONLINE := Color(0.45, 0.65, 0.95)
const COL_OPP := Color(0.95, 0.55, 0.35)

## Internet round-trips get slower buffer than LAN, matching
## InternetVersusMode's reasoning.
const MATCH_START_BUFFER_SECONDS := 5.0

var _game_state: GameState
var _audio: AudioManager
var _tm: TournamentManager
var _mission_manager: MissionManager

var _title_label: Label
var _subtitle_label: Label
var _body_holder: VBoxContainer
var _connection_banner: Label

# --- session state ---
var _player_name := "Player"
var _selected_size := 8
var _status_label: Label

# --- lobby / bracket state (kept in sync from server pushes) ---
var _lobby_players: Array = []
var _host_id := ""
var _lobby_size := 0
var _lobby_started := false
var _rounds: Array = []

# --- active match / race state (mirrors InternetVersusMode) ---
var _match_id := ""
var _word_list: Array = []
var _opponent_name := ""
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

var _word_label: Label
var _input_edit: LineEdit
var _you_bar: ProgressBar
var _opp_bar: ProgressBar


func configure(game_state: GameState, audio: AudioManager, tournament_manager: TournamentManager, mission_manager: MissionManager = null) -> void:
	_game_state = game_state
	_audio = audio
	_tm = tournament_manager
	_mission_manager = mission_manager
	add_theme_constant_override("separation", 10)

	if not is_instance_valid(_tm):
		_title_label = Label.new()
		_title_label.text = "ONLINE TOURNAMENT"
		add_child(_title_label)
		var msg := Label.new()
		msg.text = "Online features aren't available right now."
		msg.modulate = COL_MUTE
		add_child(msg)
		return

	_title_label = Label.new()
	_title_label.text = "ONLINE TOURNAMENT"
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", COL_ONLINE)
	add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_subtitle_label.add_theme_font_size_override("font_size", 15)
	_subtitle_label.modulate = COL_MUTE
	add_child(_subtitle_label)

	_connection_banner = Label.new()
	_connection_banner.autowrap_mode = TextServer.AUTOWRAP_WORD
	_connection_banner.add_theme_font_size_override("font_size", 15)
	_connection_banner.modulate = COL_RED
	_connection_banner.visible = false
	add_child(_connection_banner)

	_body_holder = VBoxContainer.new()
	_body_holder.add_theme_constant_override("separation", 12)
	add_child(_body_holder)

	_tm.tournament_created.connect(_on_tournament_created)
	_tm.tournament_joined.connect(_on_tournament_joined)
	_tm.tournament_join_failed.connect(_on_tournament_join_failed)
	_tm.lobby_updated.connect(_on_lobby_updated)
	_tm.bracket_updated.connect(_on_bracket_updated)
	_tm.match_ready.connect(_on_match_ready)
	_tm.opponent_progress.connect(_on_opponent_progress)
	_tm.opponent_finished.connect(_on_opponent_finished)
	_tm.tournament_complete.connect(_on_tournament_complete)
	_tm.connection_failed.connect(_on_connection_failed)
	_tm.disconnected_unexpectedly.connect(_on_disconnected_unexpectedly)

	_show_checking_internet()


## Quick real-internet probe (same target/reasoning as MoreScreen's
## gate on the entry button - decoupled from the relay server's own
## uptime). Runs every time this screen opens, since the phone can lose
## signal between tapping the row in MoreScreen and this screen
## actually appearing.
func _probe_internet(on_result: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = 5.0
	add_child(req)
	req.request_completed.connect(func(result, _code, _headers, _body):
		if is_instance_valid(req):
			req.queue_free()
		on_result.call(result == HTTPRequest.RESULT_SUCCESS)
	)
	var err := req.request("https://www.gstatic.com/generate_204")
	if err != OK:
		req.queue_free()
		on_result.call(false)


func _show_checking_internet() -> void:
	_subtitle_label.text = "Checking your connection…"
	_clear_body()
	_probe_internet(func(ok: bool):
		if not is_instance_valid(self):
			return
		if ok:
			_show_announcement()
		else:
			_show_no_internet()
	)


func _show_no_internet() -> void:
	_subtitle_label.text = "The Championship needs an internet connection."
	_clear_body()

	var panel := _styled_panel(18)
	_body_holder.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var icon := Label.new()
	icon.text = "⚠"
	icon.add_theme_font_size_override("font_size", 28)
	icon.add_theme_color_override("font_color", COL_RED)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(icon)

	var msg := Label.new()
	msg.text = "No internet connection found. Online Tournament needs a live connection to match you with other racers - check Wi-Fi or mobile data and try again."
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.modulate = COL_MUTE
	box.add_child(msg)

	var retry_btn := Button.new()
	retry_btn.text = "Try Again"
	retry_btn.custom_minimum_size = Vector2(0, 48)
	_body_holder.add_child(retry_btn)
	retry_btn.pressed.connect(_show_checking_internet)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.flat = true
	cancel_btn.modulate = COL_MUTE
	_body_holder.add_child(cancel_btn)
	cancel_btn.pressed.connect(func(): _leave(true))


func _clear_body() -> void:
	for c in _body_holder.get_children():
		c.queue_free()


func _leave(emit_stopped: bool) -> void:
	_running = false
	_match_active = false
	if is_instance_valid(_tm):
		_tm.leave_tournament()
	if emit_stopped:
		stopped.emit()
	else:
		finished.emit()


func _styled_panel(margin: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.05)
	style.set_corner_radius_all(14)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	panel.add_theme_stylebox_override("panel", style)
	return panel


# --- Announcement / event hub ---

## Landing screen shown the moment a player opens Online Tournament, before
## they ever see a create/join form. Frames the feature the way a real
## typing-competition event page would: what it is, how a bracket run
## actually works here, and why the results are trustworthy - then hands
## off to the existing create/join flow untouched.
func _show_announcement() -> void:
	_subtitle_label.text = "The official TypeBlast bracket event - live, online, server-verified."
	_clear_body()

	var hero := _styled_panel(18)
	_body_holder.add_child(hero)
	var hero_box := VBoxContainer.new()
	hero_box.add_theme_constant_override("separation", 6)
	hero.add_child(hero_box)

	var badge := Label.new()
	badge.text = "★ COMMUNITY CHAMPIONSHIP ★"
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", COL_GOLD)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_box.add_child(badge)

	var headline := Label.new()
	headline.text = "Think you can type with the best?"
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD
	headline.add_theme_font_size_override("font_size", 19)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_box.add_child(headline)

	var blurb := Label.new()
	blurb.text = "Single-elimination brackets of 2, 4, 8, or 16 racers. Every match runs on the same word list for both players at once, decided by the server - not the honor system."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
	blurb.modulate = COL_MUTE
	blurb.add_theme_font_size_override("font_size", 14)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_box.add_child(blurb)

	# --- "How it works" steps ---
	var steps_panel := _styled_panel(16)
	_body_holder.add_child(steps_panel)
	var steps_box := VBoxContainer.new()
	steps_box.add_theme_constant_override("separation", 10)
	steps_panel.add_child(steps_box)

	var steps_title := Label.new()
	steps_title.text = "HOW IT WORKS"
	steps_title.add_theme_font_size_override("font_size", 13)
	steps_title.add_theme_color_override("font_color", COL_ONLINE)
	steps_box.add_child(steps_title)

	var steps := [
		"1. Host picks a bracket size and gets a room code.",
		"2. Racers join with that code from anywhere online.",
		"3. Host starts it - the server builds the bracket and sends everyone the same words for each match.",
		"4. Win your race, advance. Lose, and you can still spectate the rest of the bracket live.",
	]
	for s in steps:
		var l := Label.new()
		l.text = s
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.add_theme_font_size_override("font_size", 14)
		steps_box.add_child(l)

	# --- Fair-play note, framed like a real ranked leaderboard's rules ---
	var fair_panel := _styled_panel(14)
	_body_holder.add_child(fair_panel)
	var fair_box := HBoxContainer.new()
	fair_box.add_theme_constant_override("separation", 10)
	fair_panel.add_child(fair_box)
	var fair_icon := Label.new()
	fair_icon.text = "✓"
	fair_icon.add_theme_color_override("font_color", COL_MINT)
	fair_icon.add_theme_font_size_override("font_size", 18)
	fair_box.add_child(fair_icon)
	var fair_label := Label.new()
	fair_label.text = "Fair by design: word lists are generated once per match, server-side, and sent identically to both racers - so it's finger speed, not who got the easier list."
	fair_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	fair_label.modulate = COL_MUTE
	fair_label.add_theme_font_size_override("font_size", 13)
	fair_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fair_box.add_child(fair_label)

	# --- CTAs ---
	var host_btn := Button.new()
	host_btn.text = "★ Host a Championship"
	host_btn.custom_minimum_size = Vector2(0, 48)
	_body_holder.add_child(host_btn)
	host_btn.pressed.connect(_show_create_form)

	var join_btn := Button.new()
	join_btn.text = "Join with a Code"
	join_btn.custom_minimum_size = Vector2(0, 48)
	_body_holder.add_child(join_btn)
	join_btn.pressed.connect(_show_join_form)

	var cancel_btn := Button.new()
	cancel_btn.text = "Not now"
	cancel_btn.flat = true
	cancel_btn.modulate = COL_MUTE
	_body_holder.add_child(cancel_btn)
	cancel_btn.pressed.connect(func(): _leave(true))


# --- Menu ---

func _show_menu() -> void:
	_subtitle_label.text = "Play a bracket-style tournament with friends, over the internet."
	_clear_body()

	var create_btn := Button.new()
	create_btn.text = "Create Tournament"
	create_btn.custom_minimum_size = Vector2(0, 48)
	_body_holder.add_child(create_btn)
	create_btn.pressed.connect(_show_create_form)

	var join_btn := Button.new()
	join_btn.text = "Join Tournament"
	join_btn.custom_minimum_size = Vector2(0, 48)
	_body_holder.add_child(join_btn)
	join_btn.pressed.connect(_show_join_form)

	var back_btn := Button.new()
	back_btn.text = "◀ Back"
	back_btn.flat = true
	back_btn.modulate = COL_MUTE
	_body_holder.add_child(back_btn)
	back_btn.pressed.connect(_show_announcement)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.flat = true
	cancel_btn.modulate = COL_MUTE
	_body_holder.add_child(cancel_btn)
	cancel_btn.pressed.connect(func(): _leave(true))


func _name_field() -> LineEdit:
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Your name"
	name_edit.text = _player_name
	name_edit.max_length = 16
	name_edit.text_changed.connect(func(t): _player_name = t)
	return name_edit


func _show_create_form() -> void:
	_clear_body()

	var label := Label.new()
	label.text = "Bracket size"
	_body_holder.add_child(label)

	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 8)
	_body_holder.add_child(size_row)

	var size_buttons: Array = []
	for size in [2, 4, 8, 16]:
		var sb := Button.new()
		sb.text = str(size)
		sb.toggle_mode = true
		sb.button_pressed = size == _selected_size
		sb.custom_minimum_size = Vector2(0, 44)
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_row.add_child(sb)
		size_buttons.append(sb)
		sb.pressed.connect(func():
			_selected_size = size
			for other in size_buttons:
				other.button_pressed = (other == sb)
		)

	_body_holder.add_child(_name_field())

	var create_btn := Button.new()
	create_btn.text = "Create"
	create_btn.custom_minimum_size = Vector2(0, 48)
	_body_holder.add_child(create_btn)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.modulate = COL_MUTE
	_body_holder.add_child(_status_label)

	create_btn.pressed.connect(func():
		create_btn.disabled = true
		_status_label.text = "Connecting to server…"
		_status_label.modulate = COL_ONLINE
		_tm.host_tournament(_player_name.strip_edges() if _player_name.strip_edges() != "" else "Host", _selected_size)
	)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.flat = true
	cancel_btn.modulate = COL_MUTE
	_body_holder.add_child(cancel_btn)
	cancel_btn.pressed.connect(func():
		_tm.shutdown()
		_show_menu()
	)


func _show_join_form() -> void:
	_clear_body()

	_body_holder.add_child(_name_field())

	var label := Label.new()
	label.text = "Tournament code"
	_body_holder.add_child(label)

	var code_edit := LineEdit.new()
	code_edit.placeholder_text = "ABCD"
	code_edit.max_length = 4
	code_edit.text_changed.connect(func(new_text: String):
		var upper := new_text.to_upper()
		if upper != new_text:
			var caret := code_edit.caret_column
			code_edit.text = upper
			code_edit.caret_column = caret
	)
	_body_holder.add_child(code_edit)

	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.custom_minimum_size = Vector2(0, 44)
	_body_holder.add_child(join_btn)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.modulate = COL_MUTE
	_body_holder.add_child(_status_label)

	join_btn.pressed.connect(func():
		var code = code_edit.text.strip_edges()
		if code == "":
			_status_label.text = "Enter a code first."
			_status_label.modulate = COL_RED
			return
		join_btn.disabled = true
		_status_label.text = "Connecting to server…"
		_status_label.modulate = COL_ONLINE
		_tm.join_tournament(code, _player_name.strip_edges() if _player_name.strip_edges() != "" else "Player")
	)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.flat = true
	cancel_btn.modulate = COL_MUTE
	_body_holder.add_child(cancel_btn)
	cancel_btn.pressed.connect(func():
		_tm.shutdown()
		_show_menu()
	)


# --- Connection signal handlers ---

func _on_tournament_created(_code: String, _player_id: String) -> void:
	_hide_connection_banner()
	_show_lobby()


func _on_tournament_joined(_code: String, _player_id: String, _you_are_host: bool) -> void:
	_hide_connection_banner()
	_show_lobby()


func _on_tournament_join_failed(reason: String) -> void:
	if _connection_banner.visible:
		_connection_banner.text = "Reconnect failed: %s" % ("that tournament is no longer available." if reason in ["not_found", "already_started"] else "please rejoin manually.")
	if not is_instance_valid(_status_label):
		return
	var text := "Couldn't join that tournament."
	if reason == "not_found":
		text = "No tournament found with that code."
	elif reason == "already_started":
		text = "That tournament has already started."
	elif reason == "full":
		text = "That tournament is full."
	_status_label.text = text
	_status_label.modulate = COL_RED


func _on_connection_failed() -> void:
	if is_instance_valid(_status_label):
		_status_label.text = "Couldn't reach the server. It may be waking up (can take up to a minute) - try again."
		_status_label.modulate = COL_RED
	if _connection_banner.visible:
		# This connection_failed is the rejoin attempt itself failing to
		# even reach the server - nothing more we can automatically do.
		_connection_banner.text = "Connection lost and couldn't reconnect. Please rejoin manually."


func _on_disconnected_unexpectedly() -> void:
	# The socket was live (lobby, bracket wait, or an active match) and
	# dropped on its own - not us tapping Leave. Freeze any in-progress
	# typing so a stale race doesn't keep accepting input, show a banner
	# that's visible no matter which screen is up (unlike _status_label,
	# which only exists on the create/join forms), and try once to
	# rejoin using the server's reconnect grace window.
	_running = false
	_connection_banner.text = "Connection lost. Reconnecting…"
	_connection_banner.visible = true
	if not _tm.rejoin_tournament():
		_connection_banner.text = "Connection lost. Please rejoin manually."


func _hide_connection_banner() -> void:
	if is_instance_valid(_connection_banner):
		_connection_banner.visible = false


# --- Lobby ---

func _on_lobby_updated(players: Array, host_id: String, size: int, started: bool) -> void:
	_lobby_players = players
	_host_id = host_id
	_lobby_size = size
	_lobby_started = started
	if not _match_active:
		if started:
			_show_bracket_wait()
		else:
			_show_lobby()


func _show_lobby() -> void:
	_subtitle_label.text = "Waiting in lobby…"
	_clear_body()

	if is_instance_valid(_tm) and _tm.you_are_host and _tm.my_tournament_code != "":
		var code_title := Label.new()
		code_title.text = "TOURNAMENT CODE"
		code_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		code_title.add_theme_font_size_override("font_size", 13)
		code_title.modulate = COL_MUTE
		_body_holder.add_child(code_title)

		var code_panel := _styled_panel(16)
		_body_holder.add_child(code_panel)
		var code_label := Label.new()
		code_label.text = _tm.my_tournament_code
		code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		code_label.add_theme_font_size_override("font_size", 40)
		code_label.add_theme_color_override("font_color", COL_ONLINE)
		code_panel.add_child(code_label)

		var copy_btn := Button.new()
		copy_btn.text = "Copy Code"
		_body_holder.add_child(copy_btn)
		copy_btn.pressed.connect(func(): DisplayServer.clipboard_set(_tm.my_tournament_code))

	var players_panel := _styled_panel(14)
	_body_holder.add_child(players_panel)
	var players_vb := VBoxContainer.new()
	players_vb.add_theme_constant_override("separation", 4)
	players_panel.add_child(players_vb)

	var header := Label.new()
	header.text = "PLAYERS (%d/%d)" % [_lobby_players.size(), _lobby_size]
	header.add_theme_font_size_override("font_size", 13)
	header.modulate = COL_MUTE
	players_vb.add_child(header)

	for p in _lobby_players:
		var row := Label.new()
		var pname := String(p.get("name", "?"))
		var is_host := String(p.get("id", "")) == _host_id
		row.text = ("★ " if is_host else "• ") + pname + ("" if bool(p.get("connected", true)) else " (reconnecting…)")
		row.modulate = COL_GOLD if is_host else Color.WHITE
		players_vb.add_child(row)

	if is_instance_valid(_tm) and _tm.you_are_host:
		var start_btn := Button.new()
		start_btn.text = "Start Tournament"
		start_btn.custom_minimum_size = Vector2(0, 48)
		start_btn.disabled = _lobby_players.size() < 2
		_body_holder.add_child(start_btn)
		start_btn.pressed.connect(func(): _tm.start_tournament())
		if _lobby_players.size() < 2:
			var hint := Label.new()
			hint.text = "Need at least 2 players to start."
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.add_theme_font_size_override("font_size", 12)
			hint.modulate = COL_MUTE
			_body_holder.add_child(hint)
	else:
		var waiting := Label.new()
		waiting.text = "Waiting for the host to start…"
		waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		waiting.modulate = COL_MUTE
		_body_holder.add_child(waiting)

	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.flat = true
	leave_btn.modulate = COL_MUTE
	_body_holder.add_child(leave_btn)
	leave_btn.pressed.connect(func(): _leave(true))


# --- Bracket ---

func _on_bracket_updated(rounds: Array) -> void:
	_rounds = rounds
	if not _match_active:
		_show_bracket_wait()


func _my_id() -> String:
	return _tm.my_player_id if is_instance_valid(_tm) else ""


func _am_i_eliminated() -> bool:
	var my_id := _my_id()
	for round in _rounds:
		for m in round:
			if (String(m.get("a_id", "")) == my_id or String(m.get("b_id", "")) == my_id):
				var winner_id := String(m.get("winner_id", ""))
				if winner_id != "" and winner_id != my_id:
					return true
	return false


func _build_bracket_panel() -> Control:
	var panel := _styled_panel(14)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var my_id := _my_id()
	for round_idx in _rounds.size():
		var round: Array = _rounds[round_idx]
		var round_label := Label.new()
		round_label.text = "ROUND %d" % (round_idx + 1)
		round_label.add_theme_font_size_override("font_size", 12)
		round_label.modulate = COL_MUTE
		vb.add_child(round_label)

		for m in round:
			var row := Label.new()
			var a_name := String(m.get("a_name", "")) if String(m.get("a_name", "")) != "" else "TBD"
			var b_name := String(m.get("b_name", "")) if String(m.get("b_name", "")) != "" else (("(bye)") if bool(m.get("bye", false)) else "TBD")
			var winner_id := String(m.get("winner_id", ""))
			row.text = "%s  vs  %s" % [a_name, b_name]
			row.autowrap_mode = TextServer.AUTOWRAP_WORD
			if winner_id != "":
				var winner_name := String(m.get("winner_name", ""))
				row.text += "  →  %s" % winner_name
				row.modulate = COL_GOLD if winner_id == my_id else COL_MUTE
			elif String(m.get("a_id", "")) == my_id or String(m.get("b_id", "")) == my_id:
				row.modulate = COL_ONLINE
			vb.add_child(row)

	return panel


func _show_bracket_wait() -> void:
	_clear_body()

	var eliminated := _am_i_eliminated()
	var champion_found := false
	var champion_name := ""
	if not _rounds.is_empty():
		var final_round: Array = _rounds[_rounds.size() - 1]
		if final_round.size() == 1 and String(final_round[0].get("winner_id", "")) != "":
			champion_found = true
			champion_name = String(final_round[0].get("winner_name", ""))

	if champion_found:
		_subtitle_label.text = "Tournament complete!"
	elif eliminated:
		_subtitle_label.text = "You've been eliminated - spectating the rest of the bracket."
	else:
		_subtitle_label.text = "Waiting for your next match…"

	if not _rounds.is_empty():
		_body_holder.add_child(_build_bracket_panel())

	if champion_found:
		var champ_label := Label.new()
		champ_label.text = "🏆 %s WINS THE TOURNAMENT 🏆" % champion_name.to_upper()
		champ_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		champ_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		champ_label.add_theme_font_size_override("font_size", 18)
		champ_label.add_theme_color_override("font_color", COL_GOLD)
		_body_holder.add_child(champ_label)

		var done_btn := Button.new()
		done_btn.text = "Done"
		done_btn.custom_minimum_size = Vector2(0, 48)
		_body_holder.add_child(done_btn)
		done_btn.pressed.connect(func(): _leave(false))
	else:
		var leave_btn := Button.new()
		leave_btn.text = "Leave Tournament"
		leave_btn.flat = true
		leave_btn.modulate = COL_MUTE
		_body_holder.add_child(leave_btn)
		leave_btn.pressed.connect(func(): _leave(true))


func _on_tournament_complete(_champion_id: String, _champion_name: String) -> void:
	if not _match_active:
		_show_bracket_wait()


# --- Match / race (mirrors InternetVersusMode's race logic) ---

func _on_match_ready(match_id: String, opponent_name: String, word_list: Array, start_unix_time: float) -> void:
	_match_id = match_id
	_opponent_name = opponent_name
	_word_list = word_list
	_match_active = true
	_own_finish_elapsed = -1.0
	_opponent_words_done = 0
	_opponent_finish_elapsed = -1.0
	_clear_body()

	_subtitle_label.text = "Your match vs %s starts soon…" % opponent_name

	var bars_panel := _styled_panel(14)
	_body_holder.add_child(bars_panel)
	var bars_vb := VBoxContainer.new()
	bars_vb.add_theme_constant_override("separation", 6)
	bars_panel.add_child(bars_vb)

	var you_row := Label.new()
	you_row.text = "YOU"
	you_row.add_theme_font_size_override("font_size", 13)
	you_row.modulate = COL_ONLINE
	bars_vb.add_child(you_row)

	_you_bar = ProgressBar.new()
	_you_bar.max_value = _word_list.size()
	_you_bar.show_percentage = false
	_you_bar.custom_minimum_size = Vector2(0, 18)
	var you_fill := StyleBoxFlat.new()
	you_fill.bg_color = COL_ONLINE
	you_fill.set_corner_radius_all(6)
	_you_bar.add_theme_stylebox_override("fill", you_fill)
	bars_vb.add_child(_you_bar)

	var opp_row := Label.new()
	opp_row.text = opponent_name.to_upper()
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

	var word_panel := _styled_panel(20)
	_body_holder.add_child(word_panel)
	_word_label = Label.new()
	_word_label.text = "GET READY"
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
	stop_btn.text = "STOP"
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
	_word_label.text = "GO!"
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
		if is_instance_valid(_tm):
			_tm.send_progress(_match_id, _words_typed)
	else:
		_misses += 1
		if _audio: _audio.play_error()
		if is_instance_valid(_game_state):
			_game_state._add_persistent_missed_word(_current_word)
	_advance_word()


func _on_opponent_progress(match_id: String, words_done: int) -> void:
	if match_id != _match_id:
		return
	_opponent_words_done = words_done
	if is_instance_valid(_opp_bar):
		_opp_bar.value = words_done


func _on_opponent_finished(match_id: String, words_done: int, elapsed_seconds: float) -> void:
	if match_id != _match_id:
		return
	_opponent_words_done = max(_opponent_words_done, words_done)
	_opponent_finish_elapsed = elapsed_seconds
	if _own_finish_elapsed >= 0.0:
		_show_match_result()


func _finish() -> void:
	if not _running and _own_finish_elapsed >= 0.0:
		return
	_running = false
	if is_instance_valid(_input_edit):
		_input_edit.editable = false

	_own_finish_elapsed = max((Time.get_ticks_msec() - _start_msec) / 1000.0, 0.05)
	if is_instance_valid(_tm):
		_tm.send_finished(_match_id, _words_typed, _own_finish_elapsed)

	if _opponent_finish_elapsed >= 0.0 or _opponent_words_done < _word_list.size():
		_show_match_result()
	# else: wait for the opponent's finished signal so both screens agree.


func _show_match_result() -> void:
	_match_active = false
	_clear_body()

	var total = _hits + _misses
	var acc = 100.0 if total <= 0 else (float(_hits) / total) * 100.0
	var wpm = (_words_typed / (_own_finish_elapsed / 60.0)) if _own_finish_elapsed > 0 else 0.0

	if is_instance_valid(_game_state) and _words_typed > 0:
		_game_state.register_practice_result("Online Tournament", wpm, acc, _words_typed)
		_game_state.register_versus_match()

	if is_instance_valid(_mission_manager):
		var newly_completed: Array = _mission_manager.evaluate_versus_played()
		if not newly_completed.is_empty():
			var texts: Array = []
			for m in newly_completed:
				texts.append(String(m.get("text", "")))
			var mission_note := Label.new()
			mission_note.text = "Mission complete: %s" % ", ".join(texts)
			mission_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mission_note.autowrap_mode = TextServer.AUTOWRAP_WORD
			mission_note.add_theme_font_size_override("font_size", 14)
			mission_note.modulate = COL_GOLD
			_body_holder.add_child(mission_note)

	var detail := Label.new()
	detail.text = "%d/%d words · %.0f WPM · %.0f%% accuracy" % [_words_typed, _word_list.size(), wpm, acc]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 14)
	detail.modulate = COL_MUTE
	_body_holder.add_child(detail)

	var note := Label.new()
	note.text = "Match reported — waiting for the bracket to update…"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.modulate = COL_ONLINE
	_body_holder.add_child(note)

	# The server resolves the match once both sides have reported (or a
	# forfeit timer fires), then pushes a bracket_update and, if there's
	# a next round for us, a fresh match_ready. _on_bracket_updated will
	# swap this screen for the live bracket automatically once that
	# arrives - nothing else to do here but wait.
