class_name CloudSaveManager
extends Node

## Real cross-device cloud save, backed by Firebase (Anonymous Auth +
## Firestore REST API). No login screen REQUIRED: each install gets a
## stable anonymous identity on first use, persisted locally in
## user://cloud_identity.cfg (NOT the same file as the game save - this
## one only holds auth tokens, never player progress).
##
## Email/password login is OPTIONAL, layered on top of that anonymous
## identity rather than replacing the whole scheme:
## - link_email(): upgrades the CURRENT anonymous account to also have an
##   email+password, keeping the same uid/save - nothing is lost, this
##   just adds a way to get back into the same save from another device.
## - sign_in_with_email(): logs into an EXISTING email-linked account,
##   which REPLACES this device's local identity with that account's -
##   used when someone reinstalls or moves to a new device and wants
##   their previous progress back, as an alternative to the manual
##   backup code.
## Neither is required - Sync Now/Restore from Cloud keep working purely
## anonymously if a player never touches the account section at all.
##
## Project: typeblast-2aae9 (Firebase console: console.firebase.google.com)
##
## SECURITY NOTE: Firestore is currently in the default 30-day "test
## mode" (open read/write to anyone). Before that window closes, add
## rules restricting each document to only the UID that owns it:
##
##   rules_version = '2';
##   service cloud.firestore {
##     match /databases/{database}/documents {
##       match /saves/{uid} {
##         allow read, write: if request.auth != null && request.auth.uid == uid;
##       }
##     }
##   }
##
## Set that in Firebase console → Firestore Database → Rules.

signal sync_completed(success: bool)
signal sync_failed(reason: String)
signal account_linked(email: String)
signal account_link_failed(reason: String)
signal signed_in(email: String)
signal sign_in_failed(reason: String)

## Firebase Web API key - safe to ship client-side; it identifies the
## project, it doesn't grant access on its own (Firestore rules do that).
const API_KEY := "AIzaSyCS7UL0z_M-Es4blvGRCVEPRoFGLMqHIzs"
const PROJECT_ID := "typeblast-2aae9"
const REQUEST_TIMEOUT_SECONDS := 15.0
const IDENTITY_PATH := "user://cloud_identity.cfg"

## Built at call time rather than as consts - GDScript's compiler doesn't
## reliably treat "%s" % const_value as a valid constant expression, and
## a const-declaration compile failure here would silently break this
## whole class (and anything referencing its class_name elsewhere, like
## MoreScreen's setup() signature).
func _auth_signup_url() -> String:
	return "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s" % API_KEY

func _auth_refresh_url() -> String:
	return "https://securetoken.googleapis.com/v1/token?key=%s" % API_KEY

## Upgrades the currently-signed-in account (adds email+password to it) -
## used for link_email(). Same endpoint Firebase uses for any account
## profile update; providing email+password on an anonymous account is
## what "links" it while preserving the uid.
func _account_update_url() -> String:
	return "https://identitytoolkit.googleapis.com/v1/accounts:update?key=%s" % API_KEY

## Signs into an EXISTING email+password account - used for
## sign_in_with_email(). Distinct from _account_update_url(): this one
## can hand back a DIFFERENT uid than whatever this device currently has.
func _sign_in_url() -> String:
	return "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=%s" % API_KEY

func _firestore_doc_url(uid: String) -> String:
	return "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/saves/%s" % [PROJECT_ID, uid]

var _auth_request: HTTPRequest
var _data_request: HTTPRequest
var _account_request: HTTPRequest

var _uid := ""
var _id_token := ""
var _refresh_token := ""
var _token_expires_at := 0   # unix seconds
var _email := ""             # "" until link_email()/sign_in_with_email() succeeds

var _busy := false
var _last_auth_error := ""   # human-readable detail, shown directly in the UI on failure


## Turns Godot's HTTPRequest result code into something readable, since
## response_code alone is 0 (meaningless) for anything that fails before
## a server actually responds - DNS failure, TLS/cert problems, timeout,
## no connectivity, etc. all look identical without this.
func _describe_request_result(result_code: int) -> String:
	match result_code:
		HTTPRequest.RESULT_SUCCESS: return "success"
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH: return "chunked body size mismatch"
		HTTPRequest.RESULT_CANT_CONNECT: return "could not connect (network/firewall blocked the connection)"
		HTTPRequest.RESULT_CANT_RESOLVE: return "could not resolve host (DNS failure)"
		HTTPRequest.RESULT_CONNECTION_ERROR: return "connection error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: return "TLS/SSL handshake failed"
		HTTPRequest.RESULT_NO_RESPONSE: return "no response from server"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: return "response body too large"
		HTTPRequest.RESULT_REQUEST_FAILED: return "request failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN: return "could not open download file"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR: return "could not write download file"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: return "too many redirects"
		HTTPRequest.RESULT_TIMEOUT: return "timed out"
		_: return "unknown result code %d" % result_code


func _ready() -> void:
	_auth_request = HTTPRequest.new()
	_auth_request.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(_auth_request)

	_data_request = HTTPRequest.new()
	_data_request.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(_data_request)

	_account_request = HTTPRequest.new()
	_account_request.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(_account_request)

	_load_identity()


func is_signed_in() -> bool:
	return _uid != ""

func is_linked_to_email() -> bool:
	return _email != ""

func linked_email() -> String:
	return _email

## Short, human-showable form of this device/account's identity, for the
## "Your ID" row in Settings. Full uid is a long Firebase id — this is a
## truncated, uppercased slice in the same visual style as the reference
## settings screen, not the full token (nothing security-sensitive is
## lost by trimming it, and download_save/upload_save always use the
## full _uid internally, never this display copy).
func display_id() -> String:
	if _uid == "":
		return ""
	return _uid.sha256_text().substr(0, 16).to_upper()


# --- Identity persistence (auth tokens only - never game progress) -----

func _load_identity() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(IDENTITY_PATH) != OK:
		return
	_uid = cfg.get_value("auth", "uid", "")
	_id_token = cfg.get_value("auth", "id_token", "")
	_refresh_token = cfg.get_value("auth", "refresh_token", "")
	_token_expires_at = cfg.get_value("auth", "expires_at", 0)
	_email = cfg.get_value("auth", "email", "")


func _save_identity() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "uid", _uid)
	cfg.set_value("auth", "id_token", _id_token)
	cfg.set_value("auth", "refresh_token", _refresh_token)
	cfg.set_value("auth", "expires_at", _token_expires_at)
	cfg.set_value("auth", "email", _email)
	cfg.save(IDENTITY_PATH)


# --- Auth ---------------------------------------------------------------

## Returns true once _id_token is valid and usable. Reuses the existing
## token if it's not close to expiring, refreshes it if a refresh_token
## is on hand, and falls back to creating a brand-new anonymous identity
## only if neither of those work (e.g. very first launch ever).
func _ensure_authenticated() -> bool:
	var now := int(Time.get_unix_time_from_system())
	if _id_token != "" and now < _token_expires_at - 60:
		return true
	if _refresh_token != "":
		if await _refresh_id_token():
			return true
	return await _sign_up_anonymous()


func _sign_up_anonymous() -> bool:
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify({"returnSecureToken": true})
	var err := _auth_request.request(_auth_signup_url(), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_last_auth_error = "Could not start request (error %d)" % err
		ErrorLogger.log_warning("CloudSaveManager: signUp request failed to send", "HTTPRequest.request() error %d" % err)
		return false

	var result: Array = await _auth_request.request_completed
	var result_code: int = result[0]
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]

	if response_code == 0:
		_last_auth_error = "Connection failed: " + _describe_request_result(result_code)
		ErrorLogger.log_warning("CloudSaveManager: anonymous sign-up could not connect", _last_auth_error)
		return false

	if response_code != 200:
		_last_auth_error = "Server rejected sign-in (HTTP %d): %s" % [response_code, response_body.get_string_from_utf8()]
		ErrorLogger.log_warning("CloudSaveManager: anonymous sign-up failed", _last_auth_error)
		return false

	var json = JSON.parse_string(response_body.get_string_from_utf8())
	if json == null or typeof(json) != TYPE_DICTIONARY or not json.has("idToken"):
		_last_auth_error = "Unexpected response: " + response_body.get_string_from_utf8()
		ErrorLogger.log_warning("CloudSaveManager: anonymous sign-up returned unexpected body", response_body.get_string_from_utf8())
		return false

	_uid = json.get("localId", "")
	_id_token = json.get("idToken", "")
	_refresh_token = json.get("refreshToken", "")
	var expires_in := int(json.get("expiresIn", "3600"))
	_token_expires_at = int(Time.get_unix_time_from_system()) + expires_in
	_save_identity()
	return true


func _refresh_id_token() -> bool:
	var headers := ["Content-Type: application/x-www-form-urlencoded"]
	var body := "grant_type=refresh_token&refresh_token=%s" % _refresh_token
	var err := _auth_request.request(_auth_refresh_url(), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		return false

	var result: Array = await _auth_request.request_completed
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]

	if response_code != 200:
		# Refresh token itself may be invalid/expired - clear it so the
		# next call falls through to a fresh anonymous sign-up instead
		# of retrying a dead token forever.
		_refresh_token = ""
		return false

	var json = JSON.parse_string(response_body.get_string_from_utf8())
	if json == null or typeof(json) != TYPE_DICTIONARY:
		return false

	_id_token = json.get("id_token", "")
	_refresh_token = json.get("refresh_token", _refresh_token)
	_uid = json.get("user_id", _uid)
	var expires_in := int(json.get("expires_in", "3600"))
	_token_expires_at = int(Time.get_unix_time_from_system()) + expires_in
	_save_identity()
	return _id_token != ""


# --- Optional email/password account (layered on top of anonymous auth) -

## Turns Firebase's machine-readable error codes (e.g. "EMAIL_EXISTS")
## into something worth showing a player. Returns "" if the body doesn't
## look like a recognizable Firebase error, so callers can fall back to
## showing the raw HTTP code/body instead of silently swallowing it.
func _extract_error_message(body_text: String) -> String:
	var json = JSON.parse_string(body_text)
	if json == null or typeof(json) != TYPE_DICTIONARY or not json.has("error"):
		return ""
	var code: String = json["error"].get("message", "")
	var friendly := {
		"EMAIL_EXISTS": "That email is already linked to an account - try Log In instead.",
		"INVALID_PASSWORD": "Incorrect password.",
		"INVALID_LOGIN_CREDENTIALS": "Incorrect email or password.",
		"EMAIL_NOT_FOUND": "No account found for that email.",
		"WEAK_PASSWORD": "Password must be at least 6 characters.",
		"INVALID_EMAIL": "That doesn't look like a valid email address.",
		"MISSING_PASSWORD": "Enter a password.",
		"MISSING_EMAIL": "Enter an email address.",
		"CREDENTIAL_TOO_OLD_LOGIN_AGAIN": "Please try that again.",
	}
	for key in friendly.keys():
		if code.begins_with(key):
			return friendly[key]
	return code


## Upgrades the CURRENT anonymous account to also have this email +
## password, keeping the same uid - so whatever's already been synced to
## Firestore under this device's anonymous identity stays exactly where
## it is, just now reachable from another device via sign_in_with_email().
## No account exists yet? This creates the anonymous one first
## (_ensure_authenticated() does that automatically on a first-ever call).
func link_email(email: String, password: String) -> void:
	if _busy:
		account_link_failed.emit("A sync is already in progress")
		return
	_busy = true

	if not await _ensure_authenticated():
		_busy = false
		account_link_failed.emit("Could not sign in: " + _last_auth_error)
		return

	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify({"idToken": _id_token, "email": email, "password": password, "returnSecureToken": true})
	var err := _account_request.request(_account_update_url(), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		account_link_failed.emit("Could not start request (error %d)" % err)
		return

	var result: Array = await _account_request.request_completed
	_busy = false
	var result_code: int = result[0]
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]

	if response_code == 0:
		account_link_failed.emit("Connection failed: " + _describe_request_result(result_code))
		return
	if response_code != 200:
		var detail := response_body.get_string_from_utf8()
		var friendly := _extract_error_message(detail)
		account_link_failed.emit(friendly if friendly != "" else "Server rejected request (HTTP %d): %s" % [response_code, detail])
		return

	var json = JSON.parse_string(response_body.get_string_from_utf8())
	if json == null or typeof(json) != TYPE_DICTIONARY:
		account_link_failed.emit("Unexpected response from server")
		return

	# Linking issues a fresh idToken/refreshToken for the now-upgraded
	# account - same uid as before, so nothing about the Firestore save
	# needs to change.
	_id_token = json.get("idToken", _id_token)
	_refresh_token = json.get("refreshToken", _refresh_token)
	_email = email
	_save_identity()
	account_linked.emit(_email)


## Logs into an EXISTING email+password account. This REPLACES this
## device's local identity with that account's uid/tokens - used when
## someone's on a new/reinstalled device and wants their previous
## progress back, as an alternative to the manual backup code. Does NOT
## touch local save data by itself; call download_save() afterward if you
## want to actually pull that account's cloud save onto this device.
func sign_in_with_email(email: String, password: String) -> void:
	if _busy:
		sign_in_failed.emit("A sync is already in progress")
		return
	_busy = true

	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify({"email": email, "password": password, "returnSecureToken": true})
	var err := _account_request.request(_sign_in_url(), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		sign_in_failed.emit("Could not start request (error %d)" % err)
		return

	var result: Array = await _account_request.request_completed
	_busy = false
	var result_code: int = result[0]
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]

	if response_code == 0:
		sign_in_failed.emit("Connection failed: " + _describe_request_result(result_code))
		return
	if response_code != 200:
		var detail := response_body.get_string_from_utf8()
		var friendly := _extract_error_message(detail)
		sign_in_failed.emit(friendly if friendly != "" else "Server rejected request (HTTP %d): %s" % [response_code, detail])
		return

	var json = JSON.parse_string(response_body.get_string_from_utf8())
	if json == null or typeof(json) != TYPE_DICTIONARY or not json.has("idToken"):
		sign_in_failed.emit("Unexpected response from server")
		return

	_uid = json.get("localId", "")
	_id_token = json.get("idToken", "")
	_refresh_token = json.get("refreshToken", "")
	var expires_in := int(json.get("expiresIn", "3600"))
	_token_expires_at = int(Time.get_unix_time_from_system()) + expires_in
	_email = email
	_save_identity()
	signed_in.emit(_email)


# --- Save upload / download ---------------------------------------------

## Upload the current save to Firestore, keyed by this device's anonymous
## UID. Reuses GameState.export_save_code() so the exact same
## ConfigFile-as-base64 format backs both the manual backup code and the
## cloud copy - one format, one source of truth.
func upload_save(game_state: GameState) -> void:
	if _busy:
		sync_failed.emit("A sync is already in progress")
		return
	_busy = true

	if not await _ensure_authenticated():
		_busy = false
		sync_failed.emit("Could not sign in: " + _last_auth_error)
		return

	var save_code := game_state.export_save_code()
	if save_code == "":
		_busy = false
		sync_failed.emit("Local save could not be read")
		return

	var url := _firestore_doc_url(_uid)
	var doc := {
		"fields": {
			"data": {"stringValue": save_code},
			"updated_at": {"integerValue": str(int(Time.get_unix_time_from_system()))},
		}
	}
	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % _id_token,
	]
	# PATCH creates-or-overwrites the document - exactly the last-write-
	# wins semantics we want (see class TODO history: no merge/conflict
	# UI, matches what the manual backup code already does).
	var err := _data_request.request(url, headers, HTTPClient.METHOD_PATCH, JSON.stringify(doc))
	if err != OK:
		_busy = false
		sync_failed.emit("Could not reach the cloud backend")
		return

	var result: Array = await _data_request.request_completed
	_busy = false
	var response_code: int = result[1]

	if response_code == 200:
		sync_completed.emit(true)
	else:
		var response_body: PackedByteArray = result[3]
		ErrorLogger.log_warning("CloudSaveManager: upload failed", "HTTP %d: %s" % [response_code, response_body.get_string_from_utf8()])
		sync_failed.emit("Cloud save upload failed (HTTP %d)" % response_code)


## Deletes this device/account's save document from Firestore. Used by
## Settings > Delete your account, alongside GameState.reset_all_progress()
## (local wipe) and AuthManager.sign_out() (session wipe) — this is the
## remote-data piece of that same flow. Best-effort: if the document
## never existed, or the network call fails, we still emit sync_completed
## (deletion effectively already achieved) rather than surface a scary
## error for what the player experiences as "my data is gone".
func delete_cloud_save() -> void:
	if _busy:
		sync_failed.emit("A sync is already in progress")
		return
	_busy = true

	if not await _ensure_authenticated():
		_busy = false
		# Nothing was ever uploaded under an identity we can't even
		# reach - from the player's point of view there's nothing left
		# to delete, so treat this as success rather than failure.
		sync_completed.emit(true)
		return

	var url := _firestore_doc_url(_uid)
	var headers := ["Authorization: Bearer %s" % _id_token]
	var err := _data_request.request(url, headers, HTTPClient.METHOD_DELETE)
	if err != OK:
		_busy = false
		sync_failed.emit("Could not reach the cloud backend")
		return

	var result: Array = await _data_request.request_completed
	_busy = false
	var response_code: int = result[1]

	# Firestore returns 200 on successful delete and (per their REST API)
	# also 200 for deleting a doc that doesn't exist - 404 shouldn't
	# happen here, but treat it the same way just in case.
	if response_code == 200 or response_code == 404:
		sync_completed.emit(true)
	else:
		var response_body: PackedByteArray = result[3]
		ErrorLogger.log_warning("CloudSaveManager: delete failed", "HTTP %d: %s" % [response_code, response_body.get_string_from_utf8()])
		sync_failed.emit("Cloud data deletion failed (HTTP %d)" % response_code)


## Download this device's cloud save from Firestore and apply it via
## GameState.import_save_code(), overwriting current local progress -
## same "call only after explicit player confirmation" contract as
## import_save_code() itself.
func download_save(game_state: GameState) -> void:
	if _busy:
		sync_failed.emit("A sync is already in progress")
		return
	_busy = true

	if not await _ensure_authenticated():
		_busy = false
		sync_failed.emit("Could not sign in: " + _last_auth_error)
		return

	var url := _firestore_doc_url(_uid)
	var headers := ["Authorization: Bearer %s" % _id_token]
	var err := _data_request.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_busy = false
		sync_failed.emit("Could not reach the cloud backend")
		return

	var result: Array = await _data_request.request_completed
	_busy = false
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]

	if response_code == 404:
		sync_failed.emit("No cloud save found for this device yet")
		return
	if response_code != 200:
		ErrorLogger.log_warning("CloudSaveManager: download failed", "HTTP %d: %s" % [response_code, response_body.get_string_from_utf8()])
		sync_failed.emit("Cloud save download failed (HTTP %d)" % response_code)
		return

	var json = JSON.parse_string(response_body.get_string_from_utf8())
	if json == null or typeof(json) != TYPE_DICTIONARY or not json.has("fields"):
		sync_failed.emit("Cloud save data was unreadable")
		return

	var fields: Dictionary = json["fields"]
	var save_code: String = fields.get("data", {}).get("stringValue", "")
	if save_code == "":
		sync_failed.emit("Cloud save data was empty")
		return

	if game_state.import_save_code(save_code):
		sync_completed.emit(true)
	else:
		sync_failed.emit("Cloud save data could not be applied")
