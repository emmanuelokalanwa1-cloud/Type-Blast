class_name TournamentManager
extends Node

## WebSocket client for ONLINE TOURNAMENTS, routed through the same relay
## server as InternetMultiplayerManager (relay-server/server.js) but using
## its own separate connection and its own message namespace (all
## "tournament_*" types), so it can run independently of - or alongside -
## a regular 1v1 Online Versus match.
##
## One player creates a tournament and gets a short room code back
## (host_tournament), shares it however they like, and up to `size - 1`
## other players join with that code (join_tournament). The host taps
## Start once enough people are in; the SERVER builds the bracket, picks
## the word list for every match itself (so both racers in a match always
## get an identical list with zero client-side coordination), decides
## winners, and pushes live bracket updates to everyone in the
## tournament - including players who are waiting on a later round or
## already eliminated, so they can spectate.
##
## Public API intentionally mirrors InternetMultiplayerManager's shape
## (signals for state changes, send_* methods for in-match traffic) so
## screens that already know that pattern pick this up quickly.
##
## Lives at a fixed, stable path, added once in main.gd's _ready() and
## never removed - same reasoning as the other online managers: it owns
## its own persistent connection and shouldn't be torn down by screen
## navigation while a tournament might be in progress.

signal tournament_created(code: String, player_id: String)
signal tournament_joined(code: String, player_id: String, you_are_host: bool)
signal tournament_join_failed(reason: String)
signal lobby_updated(players: Array, host_id: String, size: int, started: bool)
signal bracket_updated(rounds: Array)
signal match_ready(match_id: String, opponent_name: String, word_list: Array, start_unix_time: float)
signal opponent_progress(match_id: String, words_done: int)
signal opponent_finished(match_id: String, words_done: int, elapsed_seconds: float)
signal tournament_complete(champion_id: String, champion_name: String)
signal connection_failed()
## Fires when a previously OPEN connection drops on its own (network
## hiccup, app backgrounded, server restart) - as opposed to
## connection_failed, which is about never reaching OPEN in the first
## place, or an intentional leave_tournament()/shutdown() call (which
## never reaches this signal at all, since those null the socket
## directly). _last_code / _last_player_id are still valid when this
## fires, so rejoin_tournament() is worth trying.
signal disconnected_unexpectedly()

## Same relay server as InternetMultiplayerManager - one small Node
## process handles both the 1v1 relay and the tournament protocol over
## the same WebSocket endpoint, distinguished by message "type".
const SERVER_URL := "wss://type-blast-wpkh.onrender.com"

## Generous like InternetMultiplayerManager's - Render's free tier can
## take 30-60s to wake from a cold start.
const CONNECT_TIMEOUT_SECONDS := 60.0

var _socket: WebSocketPeer
var _connect_timer := 0.0
var _awaiting_open := false
var _pending_send: Dictionary = {}   # queued message to send once the socket opens
var _was_open := false               # true once this socket reached STATE_OPEN at least once

var _last_code := ""
var _last_player_id := ""
var you_are_host := false
var my_player_id := ""
var my_tournament_code := ""


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if not _socket:
		set_process(false)
		return

	_socket.poll()
	var state := _socket.get_ready_state()

	if _awaiting_open:
		if state == WebSocketPeer.STATE_OPEN:
			_awaiting_open = false
			_was_open = true
			if not _pending_send.is_empty():
				_socket.send_text(JSON.stringify(_pending_send))
				_pending_send = {}
		elif state == WebSocketPeer.STATE_CLOSED:
			_awaiting_open = false
			set_process(false)
			connection_failed.emit()
			return
		else:
			_connect_timer += delta
			if _connect_timer > CONNECT_TIMEOUT_SECONDS:
				_awaiting_open = false
				set_process(false)
				_socket = null
				connection_failed.emit()
				return

	if state == WebSocketPeer.STATE_OPEN:
		while _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet()
			_handle_message(packet.get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED and not _awaiting_open:
		set_process(false)
		if _was_open:
			# The connection was live and dropped on its own - a real
			# disconnect, not a failed initial connect and not us
			# intentionally leaving (that path nulls _socket before this
			# ever runs). _last_code/_last_player_id are still set, so
			# the caller can try rejoin_tournament().
			_was_open = false
			_socket = null
			disconnected_unexpectedly.emit()


func _open_socket_and_send(payload: Dictionary) -> void:
	_teardown_socket_only()
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(SERVER_URL)
	if err != OK:
		_socket = null
		connection_failed.emit()
		return
	_pending_send = payload
	_awaiting_open = true
	_connect_timer = 0.0
	set_process(true)


func _send_now(payload: Dictionary) -> void:
	if not _socket or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(JSON.stringify(payload))


# --- Public API ---

## Creates a new tournament lobby. size should be 2, 4, 8, or 16.
## tournament_created fires with the room code once the server confirms.
func host_tournament(display_name: String, size: int) -> void:
	you_are_host = true
	_open_socket_and_send({"type": "tournament_create", "name": display_name, "size": size})


## Joins an existing tournament lobby by code.
## tournament_joined fires on success, tournament_join_failed on error
## (reasons: "not_found", "already_started", "full").
func join_tournament(code: String, display_name: String) -> void:
	you_are_host = false
	_open_socket_and_send({"type": "tournament_join", "code": code.to_upper().strip_edges(), "name": display_name})


## Reattaches to the last tournament this device was part of (same code,
## same player id) - works within the server's 45s reconnect grace
## window after a drop. Returns false immediately if there's nothing to
## rejoin.
func rejoin_tournament() -> bool:
	if _last_code == "" or _last_player_id == "":
		return false
	_open_socket_and_send({"type": "tournament_rejoin", "code": _last_code, "player_id": _last_player_id})
	return true


## Host-only: locks the lobby and starts the bracket. The server replies
## with a bracket_update, then a match_ready for every first-round pair
## whose seats are both filled.
func start_tournament() -> void:
	_send_now({"type": "tournament_start"})


## Call whenever the local player completes a word during an active
## tournament match, to keep the opponent's progress bar live.
func send_progress(match_id: String, words_done: int) -> void:
	_send_now({"type": "tournament_relay", "match_id": match_id, "payload": {"kind": "progress", "words_done": words_done}})


## Call the moment the local player finishes (or stops) their word list
## for the current match. The server uses this - from both racers - to
## decide the winner and advance the bracket.
func send_finished(match_id: String, words_done: int, elapsed_seconds: float) -> void:
	_send_now({"type": "tournament_relay", "match_id": match_id, "payload": {"kind": "finished", "words_done": words_done, "elapsed_seconds": elapsed_seconds}})


## Leaves the tournament outright (no reconnect grace) and closes the
## connection. Use for an explicit "leave" tap, not for an accidental
## disconnect.
func leave_tournament() -> void:
	_send_now({"type": "tournament_leave"})
	shutdown()


func shutdown() -> void:
	_teardown_socket_only()
	you_are_host = false
	my_player_id = ""
	my_tournament_code = ""


func _teardown_socket_only() -> void:
	if _socket:
		_socket.close()
	_socket = null
	_awaiting_open = false
	_was_open = false
	_pending_send = {}
	set_process(false)


# --- Incoming message handling ---

func _handle_message(text: String) -> void:
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	var msg = json.data
	if typeof(msg) != TYPE_DICTIONARY or not msg.has("type"):
		return

	match msg["type"]:
		"tournament_created":
			my_tournament_code = String(msg.get("code", ""))
			my_player_id = String(msg.get("player_id", ""))
			_last_code = my_tournament_code
			_last_player_id = my_player_id
			you_are_host = true
			tournament_created.emit(my_tournament_code, my_player_id)

		"tournament_joined":
			my_tournament_code = String(msg.get("code", ""))
			my_player_id = String(msg.get("player_id", ""))
			_last_code = my_tournament_code
			_last_player_id = my_player_id
			you_are_host = bool(msg.get("you_are_host", false))
			tournament_joined.emit(my_tournament_code, my_player_id, you_are_host)

		"tournament_join_failed":
			tournament_join_failed.emit(String(msg.get("reason", "unknown")))

		"tournament_lobby_update":
			lobby_updated.emit(
				msg.get("players", []),
				String(msg.get("host_id", "")),
				int(msg.get("size", 0)),
				bool(msg.get("started", false))
			)

		"tournament_bracket_update":
			bracket_updated.emit(msg.get("rounds", []))

		"tournament_match_ready":
			match_ready.emit(
				String(msg.get("match_id", "")),
				String(msg.get("opponent_name", "")),
				msg.get("word_list", []),
				float(msg.get("start_unix_time", 0.0))
			)

		"tournament_relay":
			var payload = msg.get("payload", {})
			if typeof(payload) != TYPE_DICTIONARY:
				return
			var match_id := String(msg.get("match_id", ""))
			match payload.get("kind", ""):
				"progress":
					opponent_progress.emit(match_id, int(payload.get("words_done", 0)))
				"finished":
					opponent_finished.emit(match_id, int(payload.get("words_done", 0)), float(payload.get("elapsed_seconds", 0.0)))

		"tournament_complete":
			tournament_complete.emit(String(msg.get("champion_id", "")), String(msg.get("champion_name", "")))

		"error":
			connection_failed.emit()
