class_name LoginScreen
extends ColorRect

## Email/password login screen. Built the same self-contained way as
## DictationScreen/SentenceModeScreen: its own overlay, no changes to
## existing screens or main.gd's core loop required beyond instantiating
## it and opening it from wherever you want a "Sign In" entry point
## (e.g. a new button in MoreScreen's Settings panel).
##
## Usage:
##   var login := preload("res://scenes/login_screen.tscn").instantiate()
##   login.setup(root, auth_manager)
##   login.open()
##   login.closed.connect(func(): ...)
##
## Two modes in one screen: Sign In (existing account) and Create
## Account. If the player already has anonymous cloud-save progress
## worth keeping, set has_anonymous_progress_to_keep = true before
## open() so "Create Account" links that identity instead of starting
## a brand-new blank one.

signal closed()

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MINT := Color(0.4, 0.9, 0.75)
const COL_MUTE := Color(1, 1, 1, 0.55)
const COL_RED := Color(0.85, 0.35, 0.35)

var _auth: AuthManager
var _card: PanelContainer
var _title_label: Label
var _status_label: Label
var _email_edit: LineEdit
var _password_edit: LineEdit
var _submit_btn: Button
var _toggle_mode_btn: Button
var _close_btn: Button
var _forgot_password_btn: Button

## true = "Create Account" mode, false = "Sign In" mode
var _sign_up_mode := false

## Set by the caller before open() if this device already has anonymous
## cloud-save progress worth preserving under the new account.
var has_anonymous_progress_to_keep := false


func setup(root: Control, auth_manager: AuthManager) -> void:
	_auth = auth_manager
	_auth.signed_in.connect(_on_signed_in)
	_auth.sign_up_completed.connect(_on_signed_in)
	_auth.sign_in_failed.connect(_on_auth_failed)
	_auth.sign_up_failed.connect(_on_auth_failed)
	_auth.password_reset_sent.connect(_on_password_reset_sent)
	_auth.password_reset_failed.connect(_on_auth_failed)

	color = Color(0.015, 0.016, 0.03, 0.97)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	root.add_child(self)
	_build_ui()


func open() -> void:
	visible = true
	_status_label.text = ""
	_email_edit.text = ""
	_password_edit.text = ""
	if _auth.is_signed_in_with_email():
		_show_signed_in_state()


func _close() -> void:
	visible = false
	closed.emit()


func _build_ui() -> void:
	var vp = get_viewport_rect().size
	var side_margin = int(clamp(vp.x * 0.12, 30, 220))
	var vert_margin = int(clamp(vp.y * 0.15, 60, 220))

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", vert_margin)
	margin.add_theme_constant_override("margin_bottom", vert_margin)
	margin.add_theme_constant_override("margin_left", side_margin)
	margin.add_theme_constant_override("margin_right", side_margin)
	add_child(margin)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", JellyTheme.panel_style("card"))
	margin.add_child(_card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_card.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "SIGN IN"
	_title_label.add_theme_font_size_override("font_size", 26)
	_title_label.add_theme_color_override("font_color", COL_GOLD)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_email_edit = LineEdit.new()
	_email_edit.placeholder_text = "Email"
	_email_edit.custom_minimum_size = Vector2(0, 48)
	vbox.add_child(_email_edit)

	_password_edit = LineEdit.new()
	_password_edit.placeholder_text = "Password"
	_password_edit.secret = true
	_password_edit.custom_minimum_size = Vector2(0, 48)
	_password_edit.text_submitted.connect(func(_t): _on_submit_pressed())
	vbox.add_child(_password_edit)

	_forgot_password_btn = Button.new()
	_forgot_password_btn.text = "Forgot password?"
	_forgot_password_btn.flat = true
	_forgot_password_btn.add_theme_color_override("font_color", COL_MUTE)
	_forgot_password_btn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_forgot_password_btn.pressed.connect(_on_forgot_password_pressed)
	vbox.add_child(_forgot_password_btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_color_override("font_color", COL_RED)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status_label)

	_submit_btn = Button.new()
	_submit_btn.text = "SIGN IN"
	_submit_btn.custom_minimum_size = Vector2(0, 52)
	_submit_btn.pressed.connect(_on_submit_pressed)
	vbox.add_child(_submit_btn)

	_toggle_mode_btn = Button.new()
	_toggle_mode_btn.text = "Need an account? Create one"
	_toggle_mode_btn.flat = true
	_toggle_mode_btn.add_theme_color_override("font_color", COL_MINT)
	_toggle_mode_btn.pressed.connect(_on_toggle_mode)
	vbox.add_child(_toggle_mode_btn)

	_close_btn = Button.new()
	_close_btn.text = "CLOSE"
	_close_btn.flat = true
	_close_btn.add_theme_color_override("font_color", COL_MUTE)
	_close_btn.pressed.connect(_close)
	vbox.add_child(_close_btn)


func _on_toggle_mode() -> void:
	_sign_up_mode = not _sign_up_mode
	_status_label.text = ""
	if _sign_up_mode:
		_title_label.text = "CREATE ACCOUNT"
		_submit_btn.text = "CREATE ACCOUNT"
		_toggle_mode_btn.text = "Already have an account? Sign in"
		_forgot_password_btn.visible = false
	else:
		_title_label.text = "SIGN IN"
		_submit_btn.text = "SIGN IN"
		_toggle_mode_btn.text = "Need an account? Create one"
		_forgot_password_btn.visible = true


func _on_submit_pressed() -> void:
	var email := _email_edit.text.strip_edges()
	var password := _password_edit.text

	if email == "" or not email.contains("@") or not email.contains("."):
		_status_label.text = "Enter a valid email address."
		return
	if password.length() < 6:
		_status_label.text = "Password must be at least 6 characters."
		return

	_status_label.remove_theme_color_override("font_color")
	_status_label.add_theme_color_override("font_color", COL_MUTE)
	_status_label.text = "Working..."
	_submit_btn.disabled = true

	if _sign_up_mode:
		if has_anonymous_progress_to_keep:
			_auth.link_current_anonymous(email, password)
		else:
			_auth.sign_up(email, password)
	else:
		_auth.sign_in(email, password)


func _on_signed_in(_email: String) -> void:
	_submit_btn.disabled = false
	_show_signed_in_state()


func _on_auth_failed(reason: String) -> void:
	_submit_btn.disabled = false
	_status_label.remove_theme_color_override("font_color")
	_status_label.add_theme_color_override("font_color", COL_RED)
	_status_label.text = reason


func _on_forgot_password_pressed() -> void:
	var email := _email_edit.text.strip_edges()
	if email == "" or not email.contains("@") or not email.contains("."):
		_status_label.remove_theme_color_override("font_color")
		_status_label.add_theme_color_override("font_color", COL_RED)
		_status_label.text = "Enter your email above first, then tap \"Forgot password?\""
		return
	_status_label.remove_theme_color_override("font_color")
	_status_label.add_theme_color_override("font_color", COL_MUTE)
	_status_label.text = "Sending reset email..."
	_auth.send_password_reset_email(email)


func _on_password_reset_sent(email: String) -> void:
	_status_label.remove_theme_color_override("font_color")
	_status_label.add_theme_color_override("font_color", COL_MINT)
	_status_label.text = "Check %s for a password reset link." % email


func _show_signed_in_state() -> void:
	_status_label.remove_theme_color_override("font_color")
	_status_label.add_theme_color_override("font_color", COL_MINT)
	_status_label.text = "Signed in as %s" % _auth.current_email()
	_email_edit.editable = false
	_password_edit.editable = false
	_forgot_password_btn.visible = false
	_submit_btn.text = "SIGN OUT"
	_submit_btn.disabled = false
	if not _submit_btn.pressed.is_connected(_on_sign_out_pressed):
		_submit_btn.pressed.disconnect(_on_submit_pressed)
		_submit_btn.pressed.connect(_on_sign_out_pressed)


func _on_sign_out_pressed() -> void:
	_auth.sign_out()
	_email_edit.editable = true
	_password_edit.editable = true
	_forgot_password_btn.visible = not _sign_up_mode
	_email_edit.text = ""
	_password_edit.text = ""
	_status_label.text = ""
	_submit_btn.text = "SIGN IN"
	_submit_btn.pressed.disconnect(_on_sign_out_pressed)
	_submit_btn.pressed.connect(_on_submit_pressed)
