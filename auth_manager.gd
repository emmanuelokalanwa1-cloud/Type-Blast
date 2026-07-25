class_name AuthManager
extends Node

## Real email/password login, backed by the same Firebase project as
## CloudSaveManager (typeblast-2aae9), using the Identity Toolkit REST
## API directly — no Firebase SDK/plugin needed, just HTTPRequest.
##
## Shares CloudSaveManager's identity file (user://cloud_identity.cfg)
## and field names on purpose: once a player signs in or signs up with
## email, this overwrites that file with their real account's uid/
## tokens, and CloudSaveManager picks them up automatically on its next
## call — cloud save then follows the player's account instead of the
## anonymous per-device identity, with no changes needed in
## CloudSaveManager itself.
##
## Two entry points:
##   sign_up(email, password)   - brand-new account
##   sign_in(email, password)   - existing account, e.g. on a new device
##   link_current_anonymous(email, password) - upgrades whatever
##       anonymous identity is already signed in (from CloudSaveManager)
##       to a real email/password account WITHOUT losing progress, since
##       the uid stays the same and Firestore data keyed to it stays
##       reachable. Use this for "create an account" when the player has
##       already been playing anonymously; use sign_up() for a
##       from-scratch account with no prior anonymous session.
##
## SECURITY NOTE: same Firestore test-mode caveat as CloudSaveManager —
## lock down rules before the 30-day test-mode window closes.

signal signed_in(email: String)
signal sign_up_completed(email: String)
signal sign_in_failed(reason: String)
signal sign_up_failed(reason: String)
signal signed_out()
signal password_reset_sent(email: String)
signal password_reset_failed(reason: String)
signal verification_email_sent()
signal verification_email_failed(reason: String)

const API_KEY := "AIzaSyCS7UL0z_M-Es4blvGRCVEPRoFGLMqHIzs"
const IDENTITY_PATH := "user://cloud_identity.cfg"
const REQUEST_TIMEOUT_SECONDS := 15.0

func _signup_url() -> String:
	return "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s" % API_KEY

func _signin_url() -> String:
	return "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=%s" % API_KEY

func _set_account_info_url() -> String:
	return "https://identitytoolkit.googleapis.com/v1/accounts:update?key=%s" % API_KEY

func _refresh_url() -> String:
	return "https://securetoken.googleapis.com/v1/token?key=%s" % API_KEY

func _oob_code_url() -> String:
	return "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=%s" % API_KEY

var _request: HTTPRequest
var _busy := false

var _uid := ""
var _id_token := ""
var _refresh_token := ""
var _token_expires_at := 0
var _email := ""


func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(_request)
	_load_identity()


func is_signed_in_with_email() -> bool:
	return _uid != "" and _email != ""


func current_email() -> String:
	return _email


# --- Identity persistence (same file/keys CloudSaveManager reads) ------

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


func _describe_request_result(result_code: int) -> String:
	match result_code:
		HTTPRequest.RESULT_SUCCESS: return "success"
		HTTPRequest.RESULT_CANT_CONNECT: return "could not connect (network/firewall blocked the connection)"
		HTTPRequest.RESULT_CANT_RESOLVE: return "could not resolve host (DNS failure)"
		HTTPRequest.RESULT_CONNECTION_ERROR: return "connection error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: return "TLS/SSL handshake failed"
		HTTPRequest.RESULT_NO_RESPONSE: return "no response from server"
		HTTPRequest.RESULT_TIMEOUT: return "timed out"
		_: return "unknown result code %d" % result_code


## Maps Firebase's short error codes to messages safe to show a player.
func _friendly_error(code: String) -> String:
	match code:
		"EMAIL_EXISTS": return "An account with this email already exists. Try signing in instead."
		"EMAIL_NOT_FOUND": return "No account found for this email."
		"INVALID_PASSWORD", "INVALID_LOGIN_CREDENTIALS": return "Incorrect email or password."
		"INVALID_EMAIL": return "That email address doesn't look valid."
		"WEAK_PASSWORD : Password should be at least 6 characters": return "Password must be at least 6 characters."
		"USER_DISABLED": return "This account has been disabled."
		"TOO_MANY_ATTEMPTS_TRY_LATER": return "Too many attempts. Please wait a bit and try again."
		_: return "Something went wrong (%s)" % code


## Creates a brand-new email/password account with no prior anonymous
## session. If the player already has anonymous progress they want to
## keep, use link_current_anonymous() instead.
func sign_up(email: String, password: String) -> void:
	if _busy:
		return
	_busy = true
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify({
		"email": email,
		"password": password,
		"returnSecureToken": true,
	})
	var err := _request.request(_signup_url(), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		sign_up_failed.emit("Could not start request (error %d)" % err)
		return

	var result: Array = await _request.request_completed
	_busy = false
	_handle_auth_response(result, true)


## Signs into an existing email/password account — e.g. the player is
## on a new device and wants their progress back via cloud save.
## This REPLACES the local identity, so any unsynced local-only
## anonymous progress on this device should be uploaded first if it
## needs to be kept (CloudSaveManager.upload_save()).
func sign_in(email: String, password: String) -> void:
	if _busy:
		return
	_busy = true
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify({
		"email": email,
		"password": password,
		"returnSecureToken": true,
	})
	var err := _request.request(_signin_url(), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		sign_in_failed.emit("Could not start request (error %d)" % err)
		return

	var result: Array = await _request.request_completed
	_busy = false
	_handle_auth_response(result, false)


## AuthManager only loads _id_token once, at _ready(), from whatever was
## last written to the shared identity file - it never checks whether
## that token has since expired (Firebase ID tokens last ~1 hour), unlike
## CloudSaveManager's own _ensure_authenticated(), which already handles
## this. Without this check, link_current_anonymous() could silently be
## using a dead token and fail with INVALID_ID_TOKEN. Refreshes in place
## using _refresh_token if the current _id_token is missing or close to
## expiring; on success this also updates the shared identity file, so
## CloudSaveManager picks up the refreshed token too.
func _ensure_fresh_session() -> bool:
	var now := int(Time.get_unix_time_from_system())
	if _id_token != "" and now < _token_expires_at - 60:
		return true
	if _refresh_token == "":
		return false
	return await _refresh_id_token()


func _refresh_id_token() -> bool:
	var headers := ["Content-Type: application/x-www-form-urlencoded"]
	var body := "grant_type=refresh_token&refresh_token=%s" % _refresh_token
	var err := _request.request(_refresh_url(), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		return false

	var result: Array = await _request.request_completed
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]

	if response_code != 200:
		# Refresh token itself may be invalid/expired - clear it so the
		# caller's own error handling takes over instead of retrying a
		# dead token forever.
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


## Upgrades the CURRENT signed-in identity (anonymous, from
## CloudSaveManager) to a real email/password account, keeping the same
## uid — so existing progress in Firestore stays attached. Call this
## only while an anonymous _id_token is already loaded (i.e. after
## CloudSaveManager has signed in at least once this session).
func link_current_anonymous(email: String, password: String) -> void:
	if _busy:
		return
	_busy = true
	if not await _ensure_fresh_session():
		_busy = false
		sign_up_failed.emit("No active session to link — try Sign Up instead")
		return
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify({
		"idToken": _id_token,
		"email": email,
		"password": password,
		"returnSecureToken": true,
	})
	var err := _request.request(_signup_url(), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		sign_up_failed.emit("Could not start request (error %d)" % err)
		return

	var result: Array = await _request.request_completed
	_busy = false
	_handle_auth_response(result, true)


func _handle_auth_response(result: Array, is_sign_up: bool) -> void:
	var result_code: int = result[0]
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]

	if response_code == 0:
		var reason := "Connection failed: " + _describe_request_result(result_code)
		if is_sign_up: sign_up_failed.emit(reason)
		else: sign_in_failed.emit(reason)
		return

	var json = JSON.parse_string(response_body.get_string_from_utf8())

	if response_code != 200:
		var error_code := "UNKNOWN_ERROR"
		if json != null and typeof(json) == TYPE_DICTIONARY and json.has("error"):
			var errors: Array = json["error"].get("errors", [])
			error_code = json["error"].get("message", error_code)
		var reason := _friendly_error(error_code)
		ErrorLogger.log_warning("AuthManager: auth request failed", "HTTP %d: %s" % [response_code, response_body.get_string_from_utf8()])
		if is_sign_up: sign_up_failed.emit(reason)
		else: sign_in_failed.emit(reason)
		return

	if json == null or typeof(json) != TYPE_DICTIONARY or not json.has("idToken"):
		var reason := "Unexpected response from server"
		if is_sign_up: sign_up_failed.emit(reason)
		else: sign_in_failed.emit(reason)
		return

	_uid = json.get("localId", _uid)
	_id_token = json.get("idToken", "")
	_refresh_token = json.get("refreshToken", "")
	_email = json.get("email", "")
	var expires_in := int(json.get("expiresIn", "3600"))
	_token_expires_at = int(Time.get_unix_time_from_system()) + expires_in
	_save_identity()

	if is_sign_up:
		sign_up_completed.emit(_email)
	signed_in.emit(_email)


## Sends a "reset your password" email via Firebase - the standard,
## secure way to handle a forgotten password: Firebase generates the
## reset link and hosts the reset page itself, so no reset token or
## new-password handling needs to happen in this app at all.
func send_password_reset_email(email: String) -> void:
	if _busy:
		return
	_busy = true
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify({
		"requestType": "PASSWORD_RESET",
		"email": email,
	})
	var err := _request.request(_oob_code_url(), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		password_reset_failed.emit("Could not start request (error %d)" % err)
		return

	var result: Array = await _request.request_completed
	_busy = false
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]

	if response_code != 200:
		var json = JSON.parse_string(response_body.get_string_from_utf8())
		var error_code := "UNKNOWN_ERROR"
		if json != null and typeof(json) == TYPE_DICTIONARY and json.has("error"):
			error_code = json["error"].get("message", error_code)
		# EMAIL_NOT_FOUND is deliberately shown as a generic success message
		# by many apps to avoid confirming which emails have accounts
		# (enumeration protection). Keeping the real message here instead
		# since this is a small non-adversarial kids' app, not a bank -
		# clearer UX matters more than that protection here.
		password_reset_failed.emit(_friendly_error(error_code))
		return

	password_reset_sent.emit(email)


## Sends Firebase's own "verify this email" link to whatever email is on
## the CURRENT signed-in account. Requires an active session (call after
## sign_up/sign_in/link_current_anonymous has succeeded) - there's no
## separate verify-by-email-address path the way password reset has one,
## since verification is tied to a specific account's token.
func send_verification_email() -> void:
	if _busy:
		return
	if _id_token == "":
		verification_email_failed.emit("Sign in first")
		return
	_busy = true
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify({
		"requestType": "VERIFY_EMAIL",
		"idToken": _id_token,
	})
	var err := _request.request(_oob_code_url(), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		verification_email_failed.emit("Could not start request (error %d)" % err)
		return

	var result: Array = await _request.request_completed
	_busy = false
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]

	if response_code != 200:
		var json = JSON.parse_string(response_body.get_string_from_utf8())
		var error_code := "UNKNOWN_ERROR"
		if json != null and typeof(json) == TYPE_DICTIONARY and json.has("error"):
			error_code = json["error"].get("message", error_code)
		verification_email_failed.emit(_friendly_error(error_code))
		return

	verification_email_sent.emit()


## Signs out, clearing the shared identity file. Note this also signs
## CloudSaveManager out of whatever account was active — its next call
## will fall back to creating a fresh anonymous identity, since
## _load_identity() there will find nothing.
func sign_out() -> void:
	_uid = ""
	_id_token = ""
	_refresh_token = ""
	_token_expires_at = 0
	_email = ""
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(IDENTITY_PATH):
		DirAccess.remove_absolute(IDENTITY_PATH)
	signed_out.emit()
