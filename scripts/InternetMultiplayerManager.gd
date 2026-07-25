class_name InternetMultiplayerManager
extends Node

## WebSocket client for a single 1v1 ONLINE match, routed through the
## relay server in relay-server/server.js. Unlike LanMultiplayerManager
## (same-WiFi only, no server), this works over the real internet: both
## players connect out to a small always-on relay server, which pairs
## them by a short room code and forwards messages between them.
##
## *** EXPERIMENTAL / UNVERIFIED ***
## This is real networking code, but it has not been run against a live
## deployed relay server or tested between two real devices in this
## environment (no engine, no second device, no network access here).
## The WebSocketPeer usage and message protocol are correct to the best
## of my knowledge of Godot 4's API and the relay server's protocol, but
## "correct on paper" and "works on your phones over real internet" are
## different things for anything networked. Test a real host/join pass
## between two devices (or two app instances) before shipping this.
##
## Lives at a fixed, stable path, added once in main.gd's _ready() and
## never removed - same reasoning as LanMultiplayerManager: this manager
## owns its own persistent connection and shouldn't be torn down by
## screen navigation while a match might be in progress.
##
## Public API intentionally mirrors LanMultiplayerManager's signal names
## and send_* methods (send_match_start, send_progress, send_finished)
## so calling code that already knows how to drive a LAN match needs
## only minor changes to drive an online match instead.

signal room_code_ready(code: String)          # host only: share this with your opponent
signal join_failed(reason: String)            # guest only: code was wrong/full/expired
signal rejoin_failed(reason: String)          # rejoin_match() couldn't reattach to the old room
signal opponent_connected(peer_id: int)       # fires for both sides once paired
signal opponent_disconnected()
signal connected_to_host()                    # guest only, fires alongside opponent_connected
signal connection_failed()                    # could not reach the relay server at all
signal match_start_received(word_list: Array, start_unix_time: float)
signal opponent_progress(words_done: int)
signal opponent_finished(elapsed_seconds: float)

## Fill this in after deploying relay-server/ (see its comments for how).
## Must start with "wss://" (secure) for a real deploy - "ws://" (no TLS)
## only works for local testing against your own machine.
const SERVER_URL := "wss://type-blast-wpkh.onrender.com"

## How long to wait for the initial connection to the relay server
## before giving up and emitting connection_failed. Deliberately generous
## (not just "fast network" territory) because Render's free tier spins
## the server down after ~15 minutes of inactivity, and waking it back up
## can take 30-60 seconds on the first connection after that. A short
## timeout here would misreport "server unreachable" when it's actually
## just still waking up.
const CONNECT_TIMEOUT_SECONDS := 60.0

var _socket: WebSocketPeer
var _role := ""                  # "host" or "guest"
var _is_paired := false
var _connect_timer := 0.0
var _awaiting_open := false
var _pending_action := ""        # "host", "join", or "rejoin" - sent once the socket opens
var _pending_join_code := ""

## Unlike _role/_pending_*, these deliberately survive _teardown() - they
## remember the last room this device was part of, specifically so
## rejoin_match() can reconnect into it after an unplanned disconnect
## (dropped WiFi/data, app backgrounded, etc) without needing a brand new
## code from the host. Only cleared by an explicit new host_match() call,
## since starting a fresh room makes any old code meaningless.
var _last_room_code := ""
var _last_role := ""
var _join_code_in_flight := ""    # remembers the code used in the current join_match() call, since _pending_join_code is cleared immediately after sending


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
			_send_pending_action()
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
		var was_paired := _is_paired
		_is_paired = false
		if was_paired:
			opponent_disconnected.emit()
		else:
			connection_failed.emit()


func is_connected_to_opponent() -> bool:
	return _is_paired


## Opens a fresh connection to the relay server and asks it to create a
## new room. room_code_ready fires once the server assigns a code -
## show that to the player so they can share it with their opponent
## (text it, say it out loud, whatever).
func host_match() -> void:
	_teardown()
	_role = "host"
	_pending_action = "host"
	# A brand new room makes any previous code meaningless, so clear the
	# rejoin memory too - rejoin_match() should never reattach into a
	# room that's already been abandoned in favor of a new one.
	_last_room_code = ""
	_last_role = ""
	_open_socket()


## Opens a fresh connection to the relay server and asks it to pair
## this device into an existing room. Either opponent_connected +
## connected_to_host fires (success) or join_failed fires (bad/expired
## code, or the room already has a guest).
func join_match(code: String) -> void:
	_teardown()
	_role = "guest"
	_pending_action = "join"
	_pending_join_code = code.to_upper().strip_edges()
	_join_code_in_flight = _pending_join_code
	_open_socket()


## Attempts to reconnect into the SAME room this device was last part of
## (same code, same host/guest role), instead of a host generating a
## brand new code or a guest having to re-type one. Only works within
## the relay server's reconnect grace window (45s after a disconnect -
## see RECONNECT_GRACE_MS in server.js) and only if there IS a
## last-known room to reconnect to (host_match()/join_match() must have
## succeeded at least once since the app opened).
##
## On success, behaves exactly like a fresh pairing: opponent_connected
## fires, and if this device is the host, the calling screen is expected
## to kick off a brand-new match (fresh word list, fresh countdown) -
## same "no attempt to resume mid-race state" design as everything else
## here, just without needing a new code.
func rejoin_match() -> bool:
	if _last_room_code == "" or _last_role == "":
		return false
	_teardown()
	_role = _last_role
	_pending_action = "rejoin"
	_pending_join_code = _last_room_code
	_join_code_in_flight = _last_room_code
	_open_socket()
	return true


func _open_socket() -> void:
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(SERVER_URL)
	if err != OK:
		_socket = null
		connection_failed.emit()
		return
	_awaiting_open = true
	_connect_timer = 0.0
	set_process(true)


## Sends the queued "host"/"join"/"rejoin" request once the socket
## actually reaches STATE_OPEN - connect_to_url() returns immediately
## but the handshake itself is asynchronous, so we can't send anything
## until the connection is confirmed open.
func _send_pending_action() -> void:
	if _pending_action == "host":
		_socket.send_text(JSON.stringify({"type": "host"}))
	elif _pending_action == "join":
		_socket.send_text(JSON.stringify({"type": "join", "code": _pending_join_code}))
	elif _pending_action == "rejoin":
		_socket.send_text(JSON.stringify({"type": "rejoin", "code": _pending_join_code, "role": _role}))
	_pending_action = ""
	_pending_join_code = ""


func _handle_message(text: String) -> void:
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	var msg = json.data
	if typeof(msg) != TYPE_DICTIONARY or not msg.has("type"):
		return

	match msg["type"]:
		"hosting":
			var code: String = msg.get("code", "")
			_last_room_code = code
			_last_role = "host"
			room_code_ready.emit(code)


		"matched":
			_is_paired = true
			if _role == "guest":
				# join_match() only sent the code, never confirmed here -
				# record it now so rejoin_match() has something to use
				# later if this connection drops mid-match.
				_last_room_code = _join_code_in_flight
				_last_role = "guest"
				connected_to_host.emit()
			opponent_connected.emit(1)

		"join_failed":
			join_failed.emit(msg.get("reason", "unknown"))

		"rejoin_failed":
			rejoin_failed.emit(msg.get("reason", "unknown"))

		"opponent_left":
			var was_paired := _is_paired
			_is_paired = false
			if was_paired:
				opponent_disconnected.emit()

		"relay":
			_handle_relay_payload(msg.get("payload", {}))

		"error":
			# Server-side protocol complaint (malformed message, unknown
			# type, etc.) - surfaced as a failed connection since there's
			# no finer-grained signal for it and it means something in
			# this client/server pair is out of sync.
			connection_failed.emit()


func _handle_relay_payload(payload) -> void:
	if typeof(payload) != TYPE_DICTIONARY or not payload.has("kind"):
		return
	match payload["kind"]:
		"match_start":
			match_start_received.emit(payload.get("word_list", []), payload.get("start_unix_time", 0.0))
		"progress":
			opponent_progress.emit(payload.get("words_done", 0))
		"finished":
			opponent_finished.emit(payload.get("elapsed_seconds", 0.0))


func _send_relay(kind: String, extra: Dictionary) -> void:
	if not _is_paired or not _socket or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var payload := {"kind": kind}
	payload.merge(extra)
	var envelope := {"type": "relay", "payload": payload}
	_socket.send_text(JSON.stringify(envelope))


## Host-only: kicks off the match for both sides at once. word_list is
## generated by the host so both players race the identical words;
## start_unix_time is a few seconds in the future so both devices' local
## countdowns land on the same moment despite normal internet latency
## (which is higher and less predictable than LAN - leave more buffer
## here than you would for the LAN version, e.g. 5 seconds instead of 2).
func send_match_start(word_list: Array, start_unix_time: float) -> void:
	if _role != "host":
		return
	_send_relay("match_start", {"word_list": word_list, "start_unix_time": start_unix_time})


## Call from either side whenever the local player completes a word, to
## keep the opponent's progress bar live.
func send_progress(words_done: int) -> void:
	_send_relay("progress", {"words_done": words_done})


## Call from either side the moment the local player finishes all words.
func send_finished(elapsed_seconds: float) -> void:
	_send_relay("finished", {"elapsed_seconds": elapsed_seconds})


## Closes the connection and resets state so the app behaves like a
## normal offline game again and a future match can start clean.
func shutdown() -> void:
	_teardown()


func _teardown() -> void:
	if _socket:
		_socket.close()
	_socket = null
	_role = ""
	_is_paired = false
	_awaiting_open = false
	_pending_action = ""
	_pending_join_code = ""
	set_process(false)
