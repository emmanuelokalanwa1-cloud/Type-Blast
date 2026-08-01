class_name MoreScreen
extends ColorRect

## Hub for every new feature added on top of the original game. Rather than
## bolting a dozen new top-level screens onto main.gd (each needing its own
## visibility check in the back-button handler), everything new lives as a
## swappable panel inside this one screen — same pattern DifficultyMenu /
## AchievementsScreen already use for their own layout, just with an extra
## level of internal navigation. main.gd only needs to know about this one
## screen.
##
## Panels: Practice Modes (Zen / Drill / Custom / Typing Test / Daily
## Challenge / Boss Battle), Leaderboard, Badges, full Career Lore,
## Practice Calendar, Settings (language / accessibility / sound pack /
## keyboard layout), and Share/Export.

signal closed()
signal view_full_achievements()
signal replay_tutorial_pressed()
signal dictation_pressed()
signal career_pressed()

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MINT := Color(0.4, 0.9, 0.75)
const COL_MUTE := Color(1, 1, 1, 0.68)
const COL_AMBER := Color(0.95, 0.6, 0.25)
const COL_SKY := Color(0.45, 0.7, 0.95)
const COL_RED := Color(0.85, 0.35, 0.35)

# Settings > Support > Contact Technical Support opens a mailto: link to
# this address. Placeholder — same "update before shipping" pattern as
# MonetizationManager.DONATION_URL — point it at a real support inbox.
const SUPPORT_EMAIL := "support@example.com"

# The COL_* palette above was tuned for Casual's near-black card
# (panel_style() -> flat dark StyleBoxFlat). Jelly and Arcade instead put
# text on a light parchment/paper window texture, where those same pastel
# tints all but disappear. These two helpers are the one place every label
# in this screen routes its color through, so text automatically flips to
# bold near-black on a light panel and stays as the original pastel/mute
# tint on Casual's dark one - instead of hand-tuning 70+ individual labels.
#
# _tc() used to have its own copy of the light/dark darkening math here
# (and tutorial_overlay.gd had a third copy) - now it just forwards to
# JellyTheme.text_color(), the same place every other screen in the game
# gets its adaptive color from, so there's one implementation to fix
# instead of three that can quietly drift apart.
func _tc(base_color: Color) -> Color:
	return JellyTheme.text_color(base_color)

## For plain modulate-tinted Labels/Buttons (the vast majority of text in
## this screen). Swaps in near-black + bold automatically outside Casual.
func _apply_text_style(ctrl: CanvasItem, base_color: Color) -> void:
	ctrl.modulate = _tc(base_color)
	if JellyTheme.current_style != "casual" and ctrl is Control:
		var bf := GameFonts.bold()
		if bf:
			ctrl.add_theme_font_override("font", bf)

## For the handful of section titles that set "font_color" directly rather
## than using modulate (so they don't get double-tinted by a parent's
## modulate elsewhere in the tree).
func _apply_title_style(ctrl: Control, base_color: Color) -> void:
	ctrl.add_theme_color_override("font_color", _tc(base_color))
	if JellyTheme.current_style != "casual":
		var bf := GameFonts.bold()
		if bf:
			ctrl.add_theme_font_override("font", bf)

var _game_state: GameState
var _audio: AudioManager
var _mission_manager: MissionManager
var _lan_manager: LanMultiplayerManager
var _internet_manager: InternetMultiplayerManager
var _tournament_manager: TournamentManager
var _monetization: MonetizationManager
var _auth: AuthManager
var _cloud_save: CloudSaveManager
var _cloud_status_label: Label
var _cloud_sync_buttons: Array = []

var _card: PanelContainer
var _content: VBoxContainer
var _header_label: Label
var _streak_label: Label
var _word_of_day_label: Label
var _new_badges_label: Label
var _tip_label: Label
var _streak_risk_label: Label
var _close_btn: Button
var _backdrop_nodes: Array = []
var _current_view := "hub"
var _custom_words_buffer := ""

var _fact_label: Label

# --- Practice Playlists (Session Builder) ---
const PLAYLIST_MODES := [
	["🧘  Zen Mode", "zen"],
	["🎯  Drill My Mistakes", "drill"],
	["⏱  Typing Test", "typing_test"],
	["📅  Daily Challenge", "daily"],
	["⚔️  Boss Battle", "boss"],
	["🔥  Survival", "survival"],
]
var _playlist_builder_selection: Array = []   # ordered mode_ids, builder-in-progress
var _playlist_queue: Array = []               # ordered mode_ids for the run currently playing
var _playlist_queue_index := 0
var _playlist_results: Array = []             # result dicts collected as the queue plays


func setup(root: Control, game_state: GameState, audio: AudioManager, mission_manager: MissionManager = null, lan_manager: LanMultiplayerManager = null, internet_manager: InternetMultiplayerManager = null, monetization: MonetizationManager = null, cloud_save: CloudSaveManager = null, tournament_manager: TournamentManager = null, auth: AuthManager = null) -> void:
	_game_state = game_state
	_audio = audio
	_mission_manager = mission_manager
	_lan_manager = lan_manager
	_internet_manager = internet_manager
	_tournament_manager = tournament_manager
	_monetization = monetization
	_auth = auth
	_cloud_save = cloud_save
	if _cloud_save:
		_cloud_save.sync_completed.connect(_on_cloud_sync_completed)
		_cloud_save.sync_failed.connect(_on_cloud_sync_failed)
	color = Color(0.015, 0.016, 0.03, 0.97)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	root.add_child(self)
	_build_ui()


func _set_cloud_status(text: String, tint: Color) -> void:
	if not is_instance_valid(_cloud_status_label):
		return
	_cloud_status_label.visible = true
	_cloud_status_label.text = text
	_apply_text_style(_cloud_status_label, tint)


func _set_cloud_buttons_disabled(disabled: bool) -> void:
	for btn in _cloud_sync_buttons:
		if is_instance_valid(btn):
			btn.disabled = disabled


## Connected once in setup() - reaches whichever copy of the Cloud Save
## UI is currently built (see _cloud_status_label/_cloud_sync_buttons),
## so it stays correct across settings-panel rebuilds without needing a
## fresh connection each time.
func _on_cloud_sync_completed(_success: bool) -> void:
	if _audio: _audio.play_success()
	_set_cloud_status("Synced!", COL_MINT)
	_set_cloud_buttons_disabled(false)
	if _current_view == "settings":
		_refresh_header() # progress may have just changed via a restore


func _on_cloud_sync_failed(reason: String) -> void:
	if _audio: _audio.play_error()
	_set_cloud_status(reason, Color.INDIAN_RED)
	_set_cloud_buttons_disabled(false)


func _refresh_backdrop() -> void:
	BackgroundThemes.free_nodes(_backdrop_nodes)
	BackgroundThemes.advance()
	_backdrop_nodes = BackgroundThemes.build(self, BackgroundThemes.current_index, 0.42)


func _build_ui() -> void:
	var vp = get_viewport_rect().size
	var side_margin = int(clamp(vp.x * 0.05, 16, 120))
	var vert_margin = int(clamp(vp.y * 0.035, 24, 70))

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

	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 16)
	_card.add_child(outer_vbox)

	var header_row = HBoxContainer.new()
	outer_vbox.add_child(header_row)

	_header_label = Label.new()
	_header_label.text = "MORE"
	_header_label.add_theme_font_size_override("font_size", 34)
	_apply_title_style(_header_label, COL_GOLD)
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_header_label)

	_close_btn = Button.new()
	_close_btn.text = ""
	_close_btn.custom_minimum_size = Vector2(44, 44)
	# NOTE: the jelly button textures (button_blank_wide etc.) are wide
	# rectangles meant for full-width buttons - stretching one into a 44px
	# square via 9-slice would distort badly, so a small icon-only button
	# uses a plain round badge instead, same pattern as the mode-button
	# icon badges in difficulty_menu.gd.
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(1, 1, 1, 0.12)
	badge_style.set_corner_radius_all(22)
	_close_btn.add_theme_stylebox_override("normal", badge_style)
	var hover_style := badge_style.duplicate()
	hover_style.bg_color = Color(1, 1, 1, 0.2)
	_close_btn.add_theme_stylebox_override("hover", hover_style)
	var pressed_style := badge_style.duplicate()
	pressed_style.bg_color = Color(1, 1, 1, 0.28)
	_close_btn.add_theme_stylebox_override("pressed", pressed_style)
	var close_icon := JellyTheme.icon_rect("close_x", Vector2(18, 18))
	close_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	close_icon.position -= close_icon.custom_minimum_size / 2.0
	_close_btn.add_child(close_icon)
	header_row.add_child(_close_btn)
	_close_btn.pressed.connect(_on_close_pressed)

	_streak_label = Label.new()
	_streak_label.add_theme_font_size_override("font_size", 18)
	_apply_text_style(_streak_label, COL_MINT)
	outer_vbox.add_child(_streak_label)

	_word_of_day_label = Label.new()
	_word_of_day_label.add_theme_font_size_override("font_size", 18)
	_apply_text_style(_word_of_day_label, COL_MUTE)
	_word_of_day_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer_vbox.add_child(_word_of_day_label)

	_new_badges_label = Label.new()
	_new_badges_label.add_theme_font_size_override("font_size", 18)
	_apply_text_style(_new_badges_label, COL_AMBER)
	_new_badges_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_new_badges_label.visible = false
	outer_vbox.add_child(_new_badges_label)

	_tip_label = Label.new()
	_tip_label.add_theme_font_size_override("font_size", 18)
	_apply_text_style(_tip_label, COL_SKY)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer_vbox.add_child(_tip_label)

	_streak_risk_label = Label.new()
	_streak_risk_label.add_theme_font_size_override("font_size", 18)
	_apply_text_style(_streak_risk_label, COL_GOLD)
	_streak_risk_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_streak_risk_label.visible = false
	outer_vbox.add_child(_streak_risk_label)

	var sep = HSeparator.new()
	outer_vbox.add_child(sep)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 14)
	scroll.add_child(_content)


# --- Navigation helpers ---

func _clear_content() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()


func _make_nav_button(txt: String, tint: Color) -> Button:
	var b = Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(0, 60)
	b.add_theme_font_size_override("font_size", 20)
	var text_col := _tc(tint)
	b.add_theme_color_override("font_color", text_col)
	b.add_theme_color_override("font_hover_color", text_col)
	b.add_theme_color_override("font_pressed_color", text_col)
	b.add_theme_color_override("font_focus_color", text_col)
	if JellyTheme.current_style != "casual":
		var bf := GameFonts.bold()
		if bf:
			b.add_theme_font_override("font", bf)
	# NOTE: without an explicit background here, this button falls back to
	# the project's global Theme (assets/fonts/game_theme.tres), which skins
	# every Button with the bright lime jelly texture meant to pair with
	# dark-green text. These nav buttons use light tint colors instead
	# (mint/sky/gold/etc.), so on that bright background the text became
	# nearly invisible. Giving it its own translucent panel - dark overlay
	# on Casual's dark card, but a DARK overlay on Jelly/Arcade's light
	# parchment card too (not more white-on-white) - is what actually fixes
	# it, so every style gets a row you can actually see as a button instead
	# of just a stray left-edge bracket with barely-visible text floating on
	# the panel art. A tinted left-edge accent (same trick DifficultyMenu's
	# FIFA-style nav rows use) makes each row read as its own category at a
	# glance instead of a flat, hard-to-scan stack of identical bars.
	var is_light_panel := JellyTheme.current_style != "casual"
	var base_alpha := 0.16 if is_light_panel else 0.06
	var overlay_col := Color(0, 0, 0, base_alpha) if is_light_panel else Color(1, 1, 1, base_alpha)
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = overlay_col
	normal_style.set_corner_radius_all(14)
	normal_style.border_width_left = 5
	normal_style.border_color = tint
	normal_style.content_margin_left = 18
	normal_style.content_margin_right = 18
	b.add_theme_stylebox_override("normal", normal_style)
	var hover_style2 := normal_style.duplicate()
	hover_style2.bg_color = Color(0, 0, 0, base_alpha + 0.08) if is_light_panel else Color(1, 1, 1, base_alpha + 0.06)
	b.add_theme_stylebox_override("hover", hover_style2)
	var pressed_style2 := normal_style.duplicate()
	pressed_style2.bg_color = Color(0, 0, 0, base_alpha + 0.14) if is_light_panel else Color(1, 1, 1, base_alpha + 0.12)
	b.add_theme_stylebox_override("pressed", pressed_style2)
	b.add_theme_stylebox_override("focus", normal_style)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


func _make_back_button(target_view: String) -> Button:
	var b = _make_nav_button("\u2190  Back", COL_MUTE)
	b.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		_go_to(target_view)
	)
	return b


func _go_to(view: String) -> void:
	if _current_view == "lan_versus" and view != "lan_versus" and is_instance_valid(_lan_manager):
		_lan_manager.shutdown()
	if _current_view == "internet_versus" and view != "internet_versus" and is_instance_valid(_internet_manager):
		_internet_manager.shutdown()
	if _current_view == "online_tournament" and view != "online_tournament" and is_instance_valid(_tournament_manager):
		_tournament_manager.shutdown()
	match view:
		"hub": _build_hub_list()
		"cat_play": _build_category_list("cat_play")
		"cat_multiplayer": _build_category_list("cat_multiplayer")
		"cat_progress": _build_category_list("cat_progress")
		"cat_about": _build_category_list("cat_about")
		"practice_menu": _build_practice_menu()
		"story": _build_story_panel()
		"leaderboard": _build_leaderboard_panel()
		"badges": _build_badges_panel()
		"lore": _build_lore_panel()
		"calendar": _build_calendar_panel()
		"settings": _build_settings_panel()
		"share": _build_share_panel()
		"custom_editor": _build_custom_word_editor()
		"weak_keys": _build_weak_keys_panel()
		"facts": _build_facts_panel()
		"versus": _build_versus_panel()
		"ghost": _build_ghost_panel()
		"ai_versus": _build_ai_versus_panel()
		"lan_versus": _build_lan_versus_panel()
		"internet_versus": _build_internet_versus_panel()
		"credits": _build_credits_panel()
		"playlists": _build_playlists_panel()
		"cosmetics": _build_cosmetics_panel()
		"profiles": _build_profiles_panel()
		"online_tournament": _build_online_tournament_panel()


# Where the device back button / Back row should land when leaving a given
# view - one place to keep the "Back" button and the hardware back gesture
# in agreement, instead of every panel hardcoding "hub" regardless of which
# category it actually lives under.
const VIEW_PARENT := {
	"cat_play": "hub", "cat_multiplayer": "hub", "cat_progress": "hub", "cat_about": "hub",
	"practice_menu": "cat_play", "story": "cat_play",
	"playlists": "practice_menu", "custom_editor": "practice_menu",
	"versus": "cat_multiplayer", "ghost": "cat_multiplayer", "ai_versus": "cat_multiplayer",
	"lan_versus": "cat_multiplayer", "internet_versus": "cat_multiplayer",
	"leaderboard": "cat_progress", "badges": "cat_progress", "lore": "cat_progress",
	"calendar": "cat_progress", "weak_keys": "cat_progress", "cosmetics": "cat_progress",
	"credits": "cat_about", "facts": "cat_about",
	"settings": "hub", "share": "hub", "profiles": "hub",
	"online_tournament": "cat_multiplayer",
}


# --- Hub ---
# Six top-level categories instead of a single ~15-row wall of buttons -
# Multiplayer, Progress, etc. each open their own short list. Settings and
# Share stay one tap away since they're reached often on their own.
func _build_hub_list() -> void:
	_current_view = "hub"
	_clear_content()

	var entries := [
		["Play Modes", "cat_play", COL_MINT],
		["Multiplayer", "cat_multiplayer", COL_RED],
		["Progress & Stats", "cat_progress", COL_GOLD],
		["Settings", "settings", COL_MUTE],
		["Share / Export", "share", COL_SKY],
		["👪 Profiles (Family / Classroom)", "profiles", COL_MINT],
		["About", "cat_about", COL_MUTE],
	]
	for e in entries:
		var b = _make_nav_button(e[0], e[2])
		var target = e[1]
		b.pressed.connect(func():
			if _audio: _audio.play_ui_click()
			_go_to(target)
		)
		_content.add_child(b)


# Category id -> {title, entries[[label, view, tint]]}. Renamed a few modes
# here too while regrouping them: "AI Versus Mode" -> "VS Computer",
# "LAN Versus (Beta)" -> "Local Wi-Fi Match", "Online Versus (Beta)" ->
# "Online Match" - clearer at a glance than the old dev-shorthand names.
const CATEGORIES := {
	"cat_play": {
		"title": "PLAY MODES",
		"entries": [
			["Practice Modes", "practice_menu", COL_MINT],
			["Story Mode: Deep Signal", "story", COL_GOLD],
		],
	},
	"cat_multiplayer": {
		"title": "MULTIPLAYER",
		"entries": [
			["Versus Mode (2 Players, Same Device)", "versus", COL_RED],
			["Ghost Race", "ghost", COL_SKY],
			["VS Computer", "ai_versus", COL_AMBER],
			["Local Wi-Fi Match (Beta)", "lan_versus", COL_SKY],
			["Online Match (Beta)", "internet_versus", COL_SKY],
			["🌍 Online Tournament", "online_tournament", COL_SKY],
		],
	},
	"cat_progress": {
		"title": "PROGRESS & STATS",
		"entries": [
			["Leaderboard & Personal Best", "leaderboard", COL_GOLD],
			["Weak Keys Report", "weak_keys", COL_SKY],
			["Badges", "badges", COL_AMBER],
			["Career Lore (Full)", "lore", COL_SKY],
			["Practice Calendar", "calendar", COL_MINT],
			["🎨 Cosmetics Shop", "cosmetics", COL_GOLD],
		],
	},
	"cat_about": {
		"title": "ABOUT",
		"entries": [
			["Credits", "credits", COL_MUTE],
			["Fun Fact / Joke", "facts", COL_AMBER],
		],
	},
}


## Quick real-internet check, deliberately NOT the relay server itself -
## Render's free tier can be asleep for 30-60s on a cold start even when
## the device's connection is perfectly fine, and we don't want the
## Online Tournament button greyed out just because the server napped.
## Hits Google's captive-portal endpoint (fast, always up, tiny reply)
## and calls on_result.call(true/false) once it knows.
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


## Greys out the Online Tournament row until a connectivity probe comes
## back positive - re-checks every time this category is opened, since
## a phone can lose signal between visits.
func _gate_online_tournament_button(btn: Button) -> void:
	var base_text := btn.text
	btn.disabled = true
	btn.text = base_text + "  (checking…)"
	_probe_internet(func(ok: bool):
		if not is_instance_valid(btn):
			return
		btn.disabled = not ok
		btn.text = base_text if ok else base_text + "  (no internet)"
	)


func _build_category_list(cat_id: String) -> void:
	_current_view = cat_id
	_clear_content()
	_content.add_child(_make_back_button("hub"))

	var cat: Dictionary = CATEGORIES[cat_id]

	var title = Label.new()
	title.text = cat["title"]
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_MINT)
	_content.add_child(title)

	if cat_id == "cat_about":
		var note = Label.new()
		note.text = "The Fun Fact below has nothing to do with typing - just a break."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD
		note.add_theme_font_size_override("font_size", 14)
		_apply_text_style(note, COL_MUTE)
		_content.add_child(note)

	var online_tournament_btn: Button = null
	for e in cat["entries"]:
		var b = _make_nav_button(e[0], e[2])
		var target = e[1]
		b.pressed.connect(func():
			if _audio: _audio.play_ui_click()
			_go_to(target)
		)
		_content.add_child(b)
		if target == "online_tournament":
			online_tournament_btn = b

	if cat_id == "cat_multiplayer" and is_instance_valid(online_tournament_btn):
		_gate_online_tournament_button(online_tournament_btn)


# --- Practice Modes submenu ---

func _build_practice_menu() -> void:
	_current_view = "practice_menu"
	_clear_content()
	_content.add_child(_make_back_button("cat_play"))

	var title = Label.new()
	title.text = "PRACTICE MODES"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_MINT)
	_content.add_child(title)

	var modes := [
		["🧘  Zen Mode", "Relaxed, untimed, unlimited — no lives, no pressure.", "zen"],
		["🎯  Drill My Mistakes", "Practice the exact words you've missed in past runs.", "drill"],
		["📝  Custom Word Practice", "Type your own word list — great for lessons or vocab lists.", "custom"],
		["⏱  Typing Test", "Standard 60s or 180s WPM test.", "typing_test"],
		["📅  Daily Challenge", "Same 25 words for everyone today — one attempt to beat your best.", "daily"],
		["⚔️  Boss Battle", "Long words, 3 lives, a shrinking timer per word.", "boss"],
		["🔥  Survival", "Endless mixed words, 3 lives, timer creeps down as your streak grows. Beat your best streak.", "survival"],
	]
	for m in modes:
		var card = _build_mode_card(m[0], m[1])
		var mode_id = m[2]
		card.find_child("Button", true, false).pressed.connect(func():
			if _audio: _audio.play_whoosh()
			_launch_mode(mode_id)
		)
		_content.add_child(card)

	var playlist_sep = HSeparator.new()
	_content.add_child(playlist_sep)
	var playlist_btn = _make_nav_button("🎵  Practice Playlists (chain modes)", COL_GOLD)
	playlist_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		_go_to("playlists")
	)
	_content.add_child(playlist_btn)

	var dictation_btn = _make_nav_button("🎧  Dictation Mode (listen & type)", COL_SKY)
	dictation_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		dictation_pressed.emit()
	)
	_content.add_child(dictation_btn)


func _build_mode_card(title_txt: String, desc_txt: String) -> PanelContainer:
	var panel = PanelContainer.new()
	var is_light_panel := JellyTheme.current_style != "casual"
	var style := StyleBoxFlat.new()
	# A near-invisible white overlay used to be applied unconditionally, so on
	# Jelly/Arcade's bright parchment card (and with the button below having
	# no text color of its own) these rows had no visible boundary at all -
	# just words floating on the panel art. A darker overlay on light panels
	# (mirroring the nav button fix above) gives every mode row an actual
	# visible card.
	style.bg_color = Color(0, 0, 0, 0.14) if is_light_panel else Color(1, 1, 1, 0.05)
	style.set_corner_radius_all(14)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0, 0, 0, 0.12) if is_light_panel else Color(1, 1, 1, 0.08)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	var vb = VBoxContainer.new()
	panel.add_child(vb)

	var btn = Button.new()
	btn.name = "Button"
	btn.text = title_txt
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 22)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Previously had no color override at all, so it fell back to whatever
	# the global theme's default font color happened to be - unreadable on
	# some panel art. Route it through the same light/dark swap every other
	# label in this screen uses.
	_apply_text_style(btn, COL_MINT)
	vb.add_child(btn)

	var desc = Label.new()
	desc.text = desc_txt
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_font_size_override("font_size", 18)
	_apply_text_style(desc, COL_MUTE)
	vb.add_child(desc)

	return panel


func _launch_mode(mode_id: String) -> void:
	if mode_id == "custom":
		# Always show the editor first, whether or not a list is already
		# saved - lets the player reuse or edit it before starting.
		_go_to("custom_editor")
		return
	_start_practice_session(_build_mode_config(mode_id))


func _build_mode_config(mode_id: String) -> Dictionary:
	match mode_id:
		"zen":
			var pool = WordBank.get_theme_pool(_game_state.selected_theme if _game_state.selected_theme in WordBank.theme_names() else "General")
			return {
				"mode": "zen", "title": "ZEN MODE",
				"subtitle": "No timer, no lives — type at your own pace. Press STOP whenever you're done.",
				"infinite_pool": pool, "history_label": "Zen Mode",
			}
		"drill":
			return {
				"mode": "drill", "title": "DRILL MY MISTAKES",
				"subtitle": "Words you've missed in past runs, oldest first.",
				"words": _game_state.missed_words_persistent.duplicate(),
				"empty_message": "No missed words yet — play a normal run first, and anything you miss shows up here.",
				"history_label": "Drill",
			}
		"custom":
			var words = _game_state.custom_word_list.duplicate()
			words.shuffle()
			return {
				"mode": "custom", "title": "CUSTOM WORD PRACTICE",
				"subtitle": "Your own word list.",
				"words": words,
				"empty_message": "No custom words saved yet.",
				"history_label": "Custom Words",
			}
		"typing_test":
			return {
				"mode": "typing_test", "title": "TYPING TEST (60s)",
				"subtitle": "Standard WPM test. Keep typing until time runs out.",
				"infinite_pool": WordBank.get_theme_pool("General"),
				"duration": 60.0, "history_label": "Typing Test (60s)",
			}
		"daily":
			var date_seed = int(Time.get_date_string_from_system().replace("-", ""))
			return {
				"mode": "daily", "title": "DAILY CHALLENGE",
				"subtitle": "The same 25 words for every player today. Your best attempt is saved.",
				"words": WordBank.get_daily_words("General", 25, date_seed),
				"history_label": "Daily Challenge",
			}
		"boss":
			var long_pool = WordBank.words_by_length(WordBank.pool_for_theme_mix(WordBank.theme_names()), 8, 99)
			return {
				"mode": "boss", "title": "BOSS BATTLE",
				"subtitle": "Long words only. 3 lives. The timer per word shrinks the longer you survive.",
				"infinite_pool": long_pool, "lives": 3, "history_label": "Boss Battle",
			}
		"survival":
			var mixed_pool = WordBank.pool_for_theme_mix(WordBank.theme_names())
			return {
				"mode": "survival", "title": "SURVIVAL",
				"subtitle": "Endless words from every theme. 3 lives. The per-word timer creeps down every 10 words — how long can you last?",
				"infinite_pool": mixed_pool, "lives": 3, "history_label": "Survival",
			}
		_:
			return {"mode": mode_id, "title": mode_id.capitalize()}


func _start_practice_session(cfg: Dictionary) -> void:
	_current_view = "practice_session"
	_clear_content()
	_content.add_child(_make_back_button("practice_menu"))

	var session = preload("res://scenes/practice_session.tscn").instantiate() as PracticeSession
	_content.add_child(session)
	session.configure(cfg, _game_state, _audio)
	session.finished.connect(func(_result):
		_check_new_badges()
	)
	session.stopped.connect(func():
		_go_to("practice_menu")
	)


# --- Practice Playlists (Session Builder) ---

func _build_playlists_panel() -> void:
	_current_view = "playlists"
	_playlist_builder_selection.clear()
	_clear_content()
	_content.add_child(_make_back_button("practice_menu"))

	var title = Label.new()
	title.text = "PRACTICE PLAYLISTS"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_GOLD)
	_content.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Chain a few modes into one saved sequence — build it once, replay it any time."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	subtitle.add_theme_font_size_override("font_size", 15)
	_apply_text_style(subtitle, COL_MUTE)
	_content.add_child(subtitle)

	if not _game_state.saved_playlists.is_empty():
		var saved_title = Label.new()
		saved_title.text = "SAVED"
		saved_title.add_theme_font_size_override("font_size", 16)
		_apply_text_style(saved_title, COL_MINT)
		_content.add_child(saved_title)
		for pl in _game_state.saved_playlists:
			_content.add_child(_build_saved_playlist_row(pl))

	var sep = HSeparator.new()
	_content.add_child(sep)

	var build_title = Label.new()
	build_title.text = "BUILD A NEW ONE — tap modes in the order you want them"
	build_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	build_title.add_theme_font_size_override("font_size", 16)
	_apply_text_style(build_title, COL_MINT)
	_content.add_child(build_title)

	var queue_container = VBoxContainer.new()
	queue_container.add_theme_constant_override("separation", 4)
	_content.add_child(queue_container)

	var refresh_queue: Callable
	refresh_queue = func():
		for c in queue_container.get_children():
			c.queue_free()
		if _playlist_builder_selection.is_empty():
			var empty_lbl = Label.new()
			empty_lbl.text = "Sequence: (none yet)"
			empty_lbl.add_theme_font_size_override("font_size", 15)
			_apply_text_style(empty_lbl, COL_SKY)
			queue_container.add_child(empty_lbl)
			return
		for i in _playlist_builder_selection.size():
			var step_index := i
			var row = HBoxContainer.new()
			var step_lbl = Label.new()
			step_lbl.text = "%d. %s" % [step_index + 1, String(_playlist_builder_selection[step_index])]
			step_lbl.add_theme_font_size_override("font_size", 15)
			_apply_text_style(step_lbl, COL_SKY)
			step_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(step_lbl)
			var remove_btn = Button.new()
			remove_btn.text = "✕"
			remove_btn.flat = true
			_apply_text_style(remove_btn, COL_RED)
			row.add_child(remove_btn)
			remove_btn.pressed.connect(func():
				if _audio: _audio.play_ui_click()
				_playlist_builder_selection.remove_at(step_index)
				refresh_queue.call()
			)
			queue_container.add_child(row)

	for m in PLAYLIST_MODES:
		var mode_id: String = m[1]
		var btn = _make_nav_button(m[0], COL_MUTE)
		btn.pressed.connect(func():
			if _audio: _audio.play_ui_click()
			_playlist_builder_selection.append(mode_id)
			refresh_queue.call()
		)
		_content.add_child(btn)

	refresh_queue.call()

	var name_edit = LineEdit.new()
	name_edit.placeholder_text = "Name this playlist…"
	_content.add_child(name_edit)

	var save_row = HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 10)
	_content.add_child(save_row)

	var save_btn = Button.new()
	save_btn.text = "SAVE PLAYLIST"
	save_btn.custom_minimum_size = Vector2(0, 48)
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(save_btn)
	save_btn.pressed.connect(func():
		if _playlist_builder_selection.is_empty() or name_edit.text.strip_edges() == "":
			return
		_game_state.save_playlist(name_edit.text, _playlist_builder_selection)
		if _audio: _audio.play_notification()
		_go_to("playlists")
	)

	var play_now_btn = Button.new()
	play_now_btn.text = "PLAY NOW"
	play_now_btn.custom_minimum_size = Vector2(0, 48)
	play_now_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(play_now_btn)
	play_now_btn.pressed.connect(func():
		if _playlist_builder_selection.is_empty():
			return
		_start_playlist(_playlist_builder_selection.duplicate())
	)


func _build_saved_playlist_row(pl: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.05)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var vb = VBoxContainer.new()
	panel.add_child(vb)

	var name_lbl = Label.new()
	name_lbl.text = String(pl.get("name", "Playlist"))
	name_lbl.add_theme_font_size_override("font_size", 20)
	vb.add_child(name_lbl)

	var mode_ids: Array = pl.get("mode_ids", [])
	var steps_lbl = Label.new()
	steps_lbl.text = " → ".join(mode_ids)
	steps_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	steps_lbl.add_theme_font_size_override("font_size", 14)
	_apply_text_style(steps_lbl, COL_MUTE)
	vb.add_child(steps_lbl)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)

	var play_btn = Button.new()
	play_btn.text = "▶ PLAY"
	play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(play_btn)
	play_btn.pressed.connect(func():
		if _audio: _audio.play_whoosh()
		_start_playlist(mode_ids.duplicate())
	)

	var delete_btn = Button.new()
	delete_btn.text = "Delete"
	delete_btn.flat = true
	_apply_text_style(delete_btn, COL_MUTE)
	row.add_child(delete_btn)
	delete_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		_game_state.delete_playlist(String(pl.get("name", "")))
		_go_to("playlists")
	)

	return panel


func _start_playlist(mode_ids: Array) -> void:
	_playlist_queue = mode_ids
	_playlist_queue_index = 0
	_playlist_results.clear()
	_run_next_playlist_step()


func _run_next_playlist_step() -> void:
	if _playlist_queue_index >= _playlist_queue.size():
		_show_playlist_summary()
		return

	var mode_id: String = _playlist_queue[_playlist_queue_index]
	_current_view = "playlist_session"
	_clear_content()

	var progress_lbl = Label.new()
	progress_lbl.text = "Playlist step %d of %d — %s" % [_playlist_queue_index + 1, _playlist_queue.size(), mode_id]
	progress_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	progress_lbl.add_theme_font_size_override("font_size", 15)
	_apply_text_style(progress_lbl, COL_GOLD)
	_content.add_child(progress_lbl)

	var session = preload("res://scenes/practice_session.tscn").instantiate() as PracticeSession
	_content.add_child(session)
	var cfg := _build_mode_config(mode_id)
	cfg["history_label"] = String(cfg.get("history_label", mode_id.capitalize())) + " (Playlist)"
	session.configure(cfg, _game_state, _audio)
	session.finished.connect(func(result):
		_playlist_results.append(result)
		_check_new_badges()
		_playlist_queue_index += 1
		_run_next_playlist_step()
	)
	session.stopped.connect(func():
		_go_to("playlists")
	)


func _show_playlist_summary() -> void:
	_current_view = "playlist_summary"
	_clear_content()

	_game_state.register_playlist_completed()
	var newly_missions: Array = []
	if is_instance_valid(_mission_manager):
		newly_missions = _mission_manager.evaluate_playlist_complete()
	_check_new_badges()

	var title = Label.new()
	title.text = "🎉 PLAYLIST COMPLETE"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_GOLD)
	_content.add_child(title)

	var total_words := 0
	var wpm_sum := 0.0
	for r in _playlist_results:
		total_words += int(r.get("words_typed", 0))
		wpm_sum += float(r.get("wpm", 0.0))
	var avg_wpm := (wpm_sum / _playlist_results.size()) if not _playlist_results.is_empty() else 0.0

	var summary_lbl = Label.new()
	summary_lbl.text = "%d steps · %d words typed · %.0f avg WPM" % [_playlist_results.size(), total_words, avg_wpm]
	summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	summary_lbl.add_theme_font_size_override("font_size", 18)
	_apply_text_style(summary_lbl, COL_MINT)
	_content.add_child(summary_lbl)

	if not newly_missions.is_empty():
		var mission_texts: Array = []
		for m in newly_missions:
			mission_texts.append(String(m.get("text", "")))
		var mission_lbl = Label.new()
		mission_lbl.text = "🎯 Mission complete: " + ", ".join(mission_texts)
		mission_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		mission_lbl.add_theme_font_size_override("font_size", 15)
		_apply_text_style(mission_lbl, COL_GOLD)
		_content.add_child(mission_lbl)

	for i in _playlist_results.size():
		var r: Dictionary = _playlist_results[i]
		var row = Label.new()
		row.text = "%d. %s — %d words, %.0f WPM, %.0f%% acc" % [i + 1, String(r.get("mode", "")), r.get("words_typed", 0), r.get("wpm", 0.0), r.get("accuracy", 0.0)]
		row.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_theme_font_size_override("font_size", 14)
		_apply_text_style(row, COL_MUTE)
		_content.add_child(row)

	var done_btn = Button.new()
	done_btn.text = "DONE"
	done_btn.custom_minimum_size = Vector2(0, 48)
	_content.add_child(done_btn)
	done_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		_go_to("playlists")
	)


func _build_versus_panel() -> void:
	_current_view = "versus"
	_clear_content()
	_content.add_child(_make_back_button("cat_multiplayer"))

	var versus = preload("res://scenes/versus_mode.tscn").instantiate() as VersusMode
	_content.add_child(versus)
	versus.configure(_game_state, _audio, _mission_manager)
	versus.finished.connect(func():
		_check_new_badges()
		_go_to("cat_multiplayer")
	)
	versus.stopped.connect(func():
		_go_to("cat_multiplayer")
	)


func _build_ghost_panel() -> void:
	_current_view = "ghost"
	_clear_content()
	_content.add_child(_make_back_button("cat_multiplayer"))

	var ghost = preload("res://scenes/ghost_racer.tscn").instantiate() as GhostRacer
	_content.add_child(ghost)
	ghost.configure(_game_state, _audio, _mission_manager)
	ghost.finished.connect(func():
		_check_new_badges()
		_go_to("cat_multiplayer")
	)
	ghost.stopped.connect(func():
		_go_to("cat_multiplayer")
	)


func _build_story_panel() -> void:
	_current_view = "story"
	_clear_content()
	_content.add_child(_make_back_button("cat_play"))

	var story = preload("res://scenes/story_mode_screen.tscn").instantiate() as StoryModeScreen
	_content.add_child(story)
	story.configure(_game_state, _audio, _mission_manager)
	story.finished.connect(func():
		_check_new_badges()
	)


func _build_ai_versus_panel() -> void:
	_current_view = "ai_versus"
	_clear_content()
	_content.add_child(_make_back_button("cat_multiplayer"))

	var ai_versus = preload("res://scenes/ai_versus_mode.tscn").instantiate() as AiVersusMode
	_content.add_child(ai_versus)
	ai_versus.configure(_game_state, _audio, _mission_manager)
	ai_versus.finished.connect(func():
		_check_new_badges()
		_go_to("cat_multiplayer")
	)
	ai_versus.stopped.connect(func():
		_go_to("cat_multiplayer")
	)


func _build_lan_versus_panel() -> void:
	_current_view = "lan_versus"
	_clear_content()
	_content.add_child(_make_back_button("cat_multiplayer"))

	var lan_versus = preload("res://scenes/lan_versus_mode.tscn").instantiate() as LanVersusMode
	_content.add_child(lan_versus)
	lan_versus.configure(_game_state, _audio, _lan_manager, _mission_manager)
	lan_versus.finished.connect(func():
		_check_new_badges()
		_go_to("cat_multiplayer")
	)
	lan_versus.stopped.connect(func():
		_go_to("cat_multiplayer")
	)


func _build_internet_versus_panel() -> void:
	_current_view = "internet_versus"
	_clear_content()
	_content.add_child(_make_back_button("cat_multiplayer"))

	var internet_versus = preload("res://scenes/internet_versus_mode.tscn").instantiate() as InternetVersusMode
	_content.add_child(internet_versus)
	internet_versus.configure(_game_state, _audio, _internet_manager, _mission_manager)
	internet_versus.finished.connect(func():
		_check_new_badges()
		_go_to("cat_multiplayer")
	)
	internet_versus.stopped.connect(func():
		_go_to("cat_multiplayer")
	)


func _build_online_tournament_panel() -> void:
	_current_view = "online_tournament"
	_clear_content()
	_content.add_child(_make_back_button("cat_multiplayer"))

	var online_tournament = preload("res://online_tournament_mode.tscn").instantiate() as OnlineTournamentMode
	_content.add_child(online_tournament)
	online_tournament.configure(_game_state, _audio, _tournament_manager, _mission_manager)
	online_tournament.finished.connect(func():
		_check_new_badges()
		_go_to("cat_multiplayer")
	)
	online_tournament.stopped.connect(func():
		_go_to("cat_multiplayer")
	)


func _build_custom_word_editor() -> void:
	_current_view = "custom_editor"
	_clear_content()
	_content.add_child(_make_back_button("practice_menu"))

	var title = Label.new()
	title.text = "CUSTOM WORD LIST"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_MINT)
	_content.add_child(title)

	var help = Label.new()
	help.text = "One word per line (or separated by commas/spaces). Great for spelling lists or vocab homework."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	help.add_theme_font_size_override("font_size", 18)
	_apply_text_style(help, COL_MUTE)
	_content.add_child(help)

	var editor = TextEdit.new()
	editor.custom_minimum_size = Vector2(0, 170)
	editor.add_theme_font_size_override("font_size", 18)
	editor.text = "\n".join(_game_state.custom_word_list)
	_content.add_child(editor)

	var save_btn = _make_nav_button("SAVE & PRACTICE", COL_GOLD)
	_content.add_child(save_btn)
	save_btn.pressed.connect(func():
		var raw = editor.text
		var parts = raw.replace(",", "\n").replace(" ", "\n").split("\n")
		var cleaned: Array = []
		for p in parts:
			var w = p.strip_edges().to_upper()
			if w.length() > 0:
				cleaned.append(w)
		_game_state.custom_word_list = cleaned
		_game_state.save_data()
		if _audio: _audio.play_ui_click()
		if cleaned.is_empty():
			return
		_start_practice_session(_build_mode_config("custom"))
	)


# --- Leaderboard ---

func _build_leaderboard_panel() -> void:
	_current_view = "leaderboard"
	_clear_content()
	_content.add_child(_make_back_button("cat_progress"))

	var title = Label.new()
	title.text = "LEADERBOARD"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_GOLD)
	_content.add_child(title)

	var summary = Label.new()
	var hs: Array = _game_state.high_scores
	var hs_text = ", ".join(hs.map(func(s): return str(s)))
	summary.text = "Top scores: %s\nBest WPM: %.0f   Best combo: %d   Best streak: %d\nDeep Signal: %d/%d chapters" % [hs_text, _game_state.best_wpm, _game_state.best_combo, _game_state.best_survival_streak, _game_state.story_chapters_cleared.size(), StoryData.chapter_count()]
	summary.add_theme_font_size_override("font_size", 18)
	_apply_text_style(summary, COL_MINT)
	_content.add_child(summary)

	# "Ghost" comparison: your most recent run vs your personal-best run.
	if _game_state.run_history.size() >= 1:
		var latest = _game_state.run_history[_game_state.run_history.size() - 1]
		var best = _game_state.run_history[0]
		for entry in _game_state.run_history:
			if entry.get("wpm", 0.0) > best.get("wpm", 0.0):
				best = entry
		var diff = float(latest.get("wpm", 0.0)) - float(best.get("wpm", 0.0))
		var ghost_label = Label.new()
		if diff >= 0:
			ghost_label.text = "Your last run was %.0f WPM — right at (or above) your personal best. Nice!" % latest.get("wpm", 0.0)
			_apply_text_style(ghost_label, COL_GOLD)
		else:
			ghost_label.text = "Your last run was %.0f WPM, %.0f WPM behind your personal best of %.0f." % [latest.get("wpm", 0.0), -diff, best.get("wpm", 0.0)]
			_apply_text_style(ghost_label, COL_MUTE)
		ghost_label.add_theme_font_size_override("font_size", 18)
		ghost_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		_content.add_child(ghost_label)

	var sep = HSeparator.new()
	_content.add_child(sep)

	var history_title = Label.new()
	history_title.text = "Recent runs"
	history_title.add_theme_font_size_override("font_size", 18)
	_apply_text_style(history_title, COL_SKY)
	_content.add_child(history_title)

	var recent = _game_state.run_history.slice(max(0, _game_state.run_history.size() - 12), _game_state.run_history.size())
	recent.reverse()
	if recent.is_empty():
		var none_label = Label.new()
		none_label.text = "No runs recorded yet."
		_apply_text_style(none_label, COL_MUTE)
		_content.add_child(none_label)
	for entry in recent:
		var row = Label.new()
		row.text = "%s · %s — %.0f WPM, %.0f%% acc, %d pts" % [entry.get("date", ""), entry.get("mode", ""), entry.get("wpm", 0.0), entry.get("accuracy", 0.0), entry.get("score", 0)]
		row.add_theme_font_size_override("font_size", 18)
		_apply_text_style(row, COL_MUTE)
		_content.add_child(row)


# --- Badges ---

func _build_badges_panel() -> void:
	_current_view = "badges"
	_clear_content()
	_content.add_child(_make_back_button("cat_progress"))

	var title = Label.new()
	title.text = "BADGES"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_AMBER)
	_content.add_child(title)

	var count_label = Label.new()
	count_label.text = "%d / %d unlocked" % [_game_state.unlocked_badges.size(), BadgesManager.all().size()]
	count_label.add_theme_font_size_override("font_size", 18)
	_apply_text_style(count_label, COL_MINT)
	_content.add_child(count_label)

	var log_link = Button.new()
	log_link.text = "VIEW FULL ACHIEVEMENT LOG →"
	log_link.flat = true
	log_link.add_theme_font_size_override("font_size", 18)
	_apply_title_style(log_link, COL_MINT)
	log_link.pressed.connect(func(): view_full_achievements.emit())
	_content.add_child(log_link)

	for badge in BadgesManager.all():
		var unlocked: bool = _game_state.unlocked_badges.has(badge.id)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var medal_tex := AchievementIcons.for_badge(badge.id)
		if medal_tex:
			var icon = TextureRect.new()
			icon.texture = medal_tex
			icon.custom_minimum_size = Vector2(32, 32)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.modulate = Color(1, 1, 1, 1) if unlocked else Color(1, 1, 1, 0.2)
			row.add_child(icon)
		else:
			var icon = Label.new()
			icon.text = badge.icon if unlocked else "🔒"
			icon.add_theme_font_size_override("font_size", 27)
			row.add_child(icon)

		var text_vb = VBoxContainer.new()
		text_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_vb)

		var name_label = Label.new()
		name_label.text = badge.name
		name_label.add_theme_font_size_override("font_size", 19)
		_apply_text_style(name_label, COL_GOLD if unlocked else COL_MUTE)
		text_vb.add_child(name_label)

		var desc_label = Label.new()
		desc_label.text = badge.desc
		desc_label.add_theme_font_size_override("font_size", 18)
		_apply_text_style(desc_label, COL_MUTE)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		text_vb.add_child(desc_label)

		_content.add_child(row)


func _check_new_badges() -> void:
	var newly = BadgesManager.evaluate(_game_state, _mission_manager)
	if newly.is_empty():
		return
	for id in newly:
		_game_state.unlocked_badges.append(id)
	_game_state.save_data()
	var names: Array = []
	var by_id := {}
	for b in BadgesManager.all():
		by_id[b.id] = b.name
	for id in newly:
		names.append(by_id.get(id, id))
	_new_badges_label.text = "🎉 New badge%s: %s" % ["s" if names.size() > 1 else "", ", ".join(names)]
	_new_badges_label.visible = true
	if _audio: _audio.play_notification()


# --- Career Lore ---

func _build_lore_panel() -> void:
	_current_view = "lore"
	_clear_content()
	_content.add_child(_make_back_button("cat_progress"))

	var title = Label.new()
	title.text = "CAREER LORE"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_SKY)
	_content.add_child(title)

	for rank in range(1, CareerData.rank_count() + 1):
		if not LoreManager.has_lore(rank):
			continue
		var rank_title = Label.new()
		rank_title.text = "Rank %d — %s" % [rank, CareerData.title_for_rank(rank)]
		rank_title.add_theme_font_size_override("font_size", 18)
		_apply_text_style(rank_title, COL_GOLD)
		_content.add_child(rank_title)

		var lore_text = Label.new()
		lore_text.text = LoreManager.get_lore_for_rank(rank)
		lore_text.autowrap_mode = TextServer.AUTOWRAP_WORD
		lore_text.add_theme_font_size_override("font_size", 18)
		_apply_text_style(lore_text, COL_MUTE)
		_content.add_child(lore_text)


# --- Practice Calendar (heatmap built from run_history) ---

func _build_calendar_panel() -> void:
	_current_view = "calendar"
	_clear_content()
	_content.add_child(_make_back_button("cat_progress"))

	var title = Label.new()
	title.text = "PRACTICE CALENDAR"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_MINT)
	_content.add_child(title)

	var streak_text = Label.new()
	streak_text.text = "Current streak: %d day%s   Longest streak: %d day%s" % [
		_game_state.current_streak, "" if _game_state.current_streak == 1 else "s",
		_game_state.longest_streak, "" if _game_state.longest_streak == 1 else "s",
	]
	streak_text.add_theme_font_size_override("font_size", 18)
	_apply_text_style(streak_text, COL_GOLD)
	streak_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_content.add_child(streak_text)

	# Aggregate run_history entries by date -> word count that day.
	var by_date := {}
	for entry in _game_state.run_history:
		var d = String(entry.get("date", ""))
		if d == "":
			continue
		by_date[d] = by_date.get(d, 0) + int(entry.get("score", 0))

	var grid = GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_content.add_child(grid)

	var today_unix = int(Time.get_unix_time_from_system())
	for i in range(27, -1, -1):
		var d = Time.get_date_string_from_unix_time(today_unix - i * 86400).substr(0, 10)
		var activity = int(by_date.get(d, 0))
		var cell = ColorRect.new()
		cell.custom_minimum_size = Vector2(30, 30)
		cell.color = _heat_color(activity)
		cell.tooltip_text = "%s: %d words" % [d, activity]
		grid.add_child(cell)

	var legend = Label.new()
	legend.text = "Lighter = more words typed that day. Hover a square for the date."
	legend.add_theme_font_size_override("font_size", 18)
	_apply_text_style(legend, COL_MUTE)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD
	_content.add_child(legend)


func _heat_color(activity: int) -> Color:
	if activity <= 0:
		return Color(1, 1, 1, 0.06)
	elif activity < 20:
		return Color(0.4, 0.9, 0.75, 0.35)
	elif activity < 60:
		return Color(0.4, 0.9, 0.75, 0.65)
	else:
		return Color(0.4, 0.9, 0.75, 1.0)


# --- Cosmetics Shop ---
# Spends XP (the game's one existing currency - no new economy introduced)
# on a handful of accent-color unlocks. The selected color is read by
# main.gd for the ordinary "+10" catch-text color, so a purchase has a
# small but real, visible payoff instead of just sitting on a settings page.
const COSMETIC_OPTIONS := {
	"default": {"label": "Default Yellow", "color": Color(1.0, 0.92, 0.3), "cost": 0},
	"mint": {"label": "Mint", "color": Color(0.4, 0.9, 0.75), "cost": 150},
	"sky": {"label": "Sky Blue", "color": Color(0.4, 0.7, 1.0), "cost": 300},
	"sunset": {"label": "Sunset Orange", "color": Color(1.0, 0.55, 0.25), "cost": 500},
	"royal": {"label": "Royal Purple", "color": Color(0.65, 0.4, 0.95), "cost": 800},
	"rose": {"label": "Rose Gold", "color": Color(0.95, 0.65, 0.65), "cost": 1200},
}

func _build_cosmetics_panel() -> void:
	_current_view = "cosmetics"
	_clear_content()
	_content.add_child(_make_back_button("cat_progress"))

	var title = Label.new()
	title.text = "COSMETICS SHOP"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_GOLD)
	_content.add_child(title)

	var xp_label = Label.new()
	xp_label.text = "Your XP: %d  (spend it here on catch-text colors)" % int(_game_state.current_xp)
	xp_label.add_theme_font_size_override("font_size", 16)
	_apply_text_style(xp_label, COL_MUTE)
	_content.add_child(xp_label)

	for cosmetic_id in COSMETIC_OPTIONS.keys():
		var opt = COSMETIC_OPTIONS[cosmetic_id]
		var owned: bool = _game_state.unlocked_cosmetics.has(cosmetic_id)
		var selected: bool = _game_state.selected_cosmetic == cosmetic_id

		var row = PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(opt["color"].r, opt["color"].g, opt["color"].b, 0.14)
		style.set_corner_radius_all(12)
		style.border_width_left = 4
		style.border_color = opt["color"]
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		row.add_theme_stylebox_override("panel", style)
		_content.add_child(row)

		var hb = HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		row.add_child(hb)

		var label = Label.new()
		var suffix := "  (selected)" if selected else ("  (owned)" if owned else "  — %d XP" % int(opt["cost"]))
		label.text = opt["label"] + suffix
		label.add_theme_font_size_override("font_size", 17)
		label.modulate = opt["color"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(label)

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(110, 40)
		btn.add_theme_font_size_override("font_size", 14)
		if selected:
			btn.text = "IN USE"
			btn.disabled = true
		elif owned:
			btn.text = "SELECT"
			btn.pressed.connect(func():
				if _audio: _audio.play_ui_click()
				_game_state.selected_cosmetic = cosmetic_id
				_game_state.save_data()
				_go_to("cosmetics")
			)
		else:
			btn.text = "UNLOCK"
			btn.disabled = _game_state.current_xp < opt["cost"]
			btn.pressed.connect(func():
				if _game_state.current_xp < opt["cost"]:
					return
				if _audio: _audio.play_powerup()
				_game_state.current_xp -= int(opt["cost"])
				_game_state.unlocked_cosmetics.append(cosmetic_id)
				_game_state.selected_cosmetic = cosmetic_id
				_game_state.save_data()
				_go_to("cosmetics")
			)
		hb.add_child(btn)


# --- Profiles (Family / Classroom mode) ---
# Lets one device support multiple players (siblings, a classroom) without
# a full account system: each profile is just the same save file, copied
# under a different name. Switching swaps the active save file on disk and
# asks GameState to reload from it - no changes to GameState's own
# save/load format needed.
func _build_profiles_panel() -> void:
	_current_view = "profiles"
	_clear_content()
	_content.add_child(_make_back_button("hub"))

	var title = Label.new()
	title.text = "PROFILES"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_MINT)
	_content.add_child(title)

	var note = Label.new()
	note.text = "Great for siblings sharing a device, or a classroom set. Switching saves your current progress first, then loads the other profile's progress."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.add_theme_font_size_override("font_size", 14)
	_apply_text_style(note, COL_MUTE)
	_content.add_child(note)

	var current_label = Label.new()
	current_label.text = "Active profile: " + ProfileManager.get_active_profile()
	current_label.add_theme_font_size_override("font_size", 17)
	_apply_text_style(current_label, COL_GOLD)
	_content.add_child(current_label)

	for profile_name in ProfileManager.list_profiles():
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_content.add_child(row)

		var label = Label.new()
		label.text = profile_name
		label.add_theme_font_size_override("font_size", 16)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_text_style(label, COL_MINT)
		row.add_child(label)

		if profile_name != ProfileManager.get_active_profile():
			var switch_btn = Button.new()
			switch_btn.text = "SWITCH"
			switch_btn.custom_minimum_size = Vector2(100, 40)
			switch_btn.pressed.connect(func():
				if _audio: _audio.play_whoosh()
				ProfileManager.switch_to(profile_name, _game_state)
				_go_to("profiles")
			)
			row.add_child(switch_btn)

	var new_row = HBoxContainer.new()
	new_row.add_theme_constant_override("separation", 12)
	_content.add_child(new_row)

	var new_edit := LineEdit.new()
	new_edit.placeholder_text = "New profile name"
	new_edit.custom_minimum_size = Vector2(160, 44)
	new_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_row.add_child(new_edit)

	var create_btn = Button.new()
	create_btn.text = "CREATE"
	create_btn.custom_minimum_size = Vector2(100, 44)
	create_btn.pressed.connect(func():
		var new_name := new_edit.text.strip_edges()
		if new_name == "":
			return
		if _audio: _audio.play_ui_click()
		ProfileManager.create_profile(new_name, _game_state)
		_go_to("profiles")
	)
	new_row.add_child(create_btn)


# --- Settings ---

func _build_settings_panel() -> void:
	_current_view = "settings"
	_clear_content()
	_content.add_child(_make_back_button("hub"))

	var title = Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_MUTE)
	_content.add_child(title)

	# Sound — Music/Effects toggles in the reference-style card: icon +
	# title/subtitle + pill toggle switch. Backed by GameState.music_enabled
	# / sfx_enabled (new persisted flags), applied via AudioManager so
	# turning a channel off silences it immediately, same fade behavior as
	# the existing volume system.
	var sound_card := _build_settings_card()
	sound_card.add_child(_build_toggle_row(
		"res://assets/settings_ui/icon_speaker.png", "Music", "Turn on/off background music",
		_game_state.music_enabled,
		func(on):
			if _audio: _audio.set_music_enabled(on)
	))
	sound_card.add_child(_build_toggle_row(
		"res://assets/settings_ui/icon_speaker.png", "Effects", "Turn on/off sound effects",
		_game_state.sfx_enabled,
		func(on):
			if _audio: _audio.set_sfx_enabled(on)
	))
	sound_card.add_child(_build_toggle_row(
		"res://assets/settings_ui/icon_hd.png", "HD Graphics", "Disable for better performance",
		_game_state.hd_graphics_enabled,
		func(on):
			_game_state.hd_graphics_enabled = on
			_game_state.save_data()
			_game_state.accessibility_changed.emit()
	))
	sound_card.add_child(_build_toggle_row(
		"res://assets/settings_ui/icon_bell.png", "Notifications", "Enable/disable notifications",
		_game_state.notifications_enabled,
		func(on):
			_game_state.notifications_enabled = on
			_game_state.save_data()
	))
	_content.add_child(sound_card.get_meta("card_root"))

	# Unit of length — the reference settings screen shows this as a left/
	# right arrow stepper next to "Meters"; an OptionButton gives the same
	# pick-one behavior with the project's existing pattern (see Language
	# below) instead of building a one-off stepper control just for this.
	_content.add_child(_section_label("Unit of length in game"))
	var unit_option = OptionButton.new()
	unit_option.custom_minimum_size = Vector2(0, 48)
	unit_option.add_theme_font_size_override("font_size", 18)
	var units = ["meters", "feet"]
	var unit_labels = {"meters": "Meters", "feet": "Feet"}
	for i in units.size():
		unit_option.add_item(unit_labels[units[i]])
		if units[i] == _game_state.distance_unit:
			unit_option.select(i)
	_content.add_child(unit_option)
	unit_option.item_selected.connect(func(idx):
		_game_state.distance_unit = units[idx]
		_game_state.save_data()
		if _audio: _audio.play_ui_click()
	)

	# Language
	_content.add_child(_section_label("Language"))
	var lang_option = OptionButton.new()
	lang_option.custom_minimum_size = Vector2(0, 48)
	lang_option.add_theme_font_size_override("font_size", 18)
	var langs = ["en", "es", "fr", "de", "it", "pt"]
	var lang_labels = {"en": "English", "es": "Español", "fr": "Français", "de": "Deutsch", "it": "Italiano", "pt": "Português"}
	for i in langs.size():
		lang_option.add_item(lang_labels[langs[i]])
		if langs[i] == _game_state.selected_language:
			lang_option.select(i)
	_content.add_child(lang_option)
	lang_option.item_selected.connect(func(idx):
		_game_state.selected_language = langs[idx]
		_game_state.save_data()
		if _audio: _audio.play_ui_click()
	)
	var lang_note = Label.new()
	lang_note.text = "Applies to translated UI strings via LocalizationManager (translation is a first draft, not final copy)."
	lang_note.add_theme_font_size_override("font_size", 18)
	_apply_text_style(lang_note, COL_MUTE)
	lang_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_content.add_child(lang_note)

	# Interface style — Casual (flat, no image assets) vs Jelly (SunGraphica
	# texture kit). Picking a style here now applies instantly across the
	# whole app (main menu, pause menu, game-over screen, etc.) instead of
	# only taking effect the next time each screen happens to reopen -
	# GameState.ui_style_changed fires and main.gd rebuilds every live
	# screen in place. Each option shows a real live-rendered mini button
	# in that style, so the choice is a preview rather than a guess from
	# a text label.
	_content.add_child(_section_label("Interface Style"))
	var style_row = HBoxContainer.new()
	style_row.add_theme_constant_override("separation", 14)
	_content.add_child(style_row)
	for i in JellyTheme.STYLES.size():
		var style_id: String = JellyTheme.STYLES[i]
		var swatch := _build_style_swatch_card(style_id, style_id == _game_state.ui_style)
		swatch.pressed.connect(func():
			if _game_state.ui_style == style_id:
				return
			_game_state.ui_style = style_id
			JellyTheme.set_style(style_id)
			_game_state.save_data()
			if _audio: _audio.play_ui_click()
			_game_state.ui_style_changed.emit(style_id)
			# Rebuild this settings panel itself too, so its own swatches/
			# buttons re-skin along with everything else instead of being
			# the one screen that's out of sync with the choice just made.
			_build_settings_panel()
		)
		style_row.add_child(swatch)
	var style_note = Label.new()
	style_note.text = "Arcade is the default look (color-coded red/orange/grey buttons + panel art). Jelly is the chunky SunGraphica look. Casual is flat and icon-free — no image assets. Applies instantly everywhere."
	style_note.add_theme_font_size_override("font_size", 18)
	_apply_text_style(style_note, COL_MUTE)
	style_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_content.add_child(style_note)

	# Sound pack
	_content.add_child(_section_label("Sound Pack"))
	var pack_option = OptionButton.new()
	pack_option.custom_minimum_size = Vector2(0, 48)
	pack_option.add_theme_font_size_override("font_size", 18)
	var packs = ["Classic", "Arcade", "Chill"]
	for i in packs.size():
		pack_option.add_item(packs[i])
		if packs[i] == _game_state.sound_pack:
			pack_option.select(i)
	_content.add_child(pack_option)
	pack_option.item_selected.connect(func(idx):
		if _audio: _audio.set_sound_pack(packs[idx])
		if _audio: _audio.play_success()
	)

	# Keyboard layout
	_content.add_child(_section_label("Keyboard Layout (for the Weak Keys report)"))
	var layout_option = OptionButton.new()
	layout_option.custom_minimum_size = Vector2(0, 48)
	layout_option.add_theme_font_size_override("font_size", 18)
	var layouts = KeyboardLayoutManager.layout_names()
	for i in layouts.size():
		layout_option.add_item(layouts[i])
		if layouts[i] == _game_state.keyboard_layout:
			layout_option.select(i)
	_content.add_child(layout_option)
	layout_option.item_selected.connect(func(idx):
		_game_state.keyboard_layout = layouts[idx]
		_game_state.save_data()
	)

	var hand_report_label = Label.new()
	hand_report_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	hand_report_label.add_theme_font_size_override("font_size", 18)
	_apply_text_style(hand_report_label, COL_SKY)
	var report = KeyboardLayoutManager.hand_report(_game_state.weak_letter_counts, _game_state.keyboard_layout)
	if report.is_empty():
		hand_report_label.text = "No weak-key data yet — play a few runs first."
	else:
		var top = report[0]
		hand_report_label.text = "Your weakest area: %s (%d misses tracked)" % [top.hand, top.count]
	_content.add_child(hand_report_label)

	# Accessibility
	_content.add_child(_section_label("Accessibility"))
	var access_card := _build_settings_card()
	access_card.add_child(_build_toggle_row(
		"res://assets/settings_ui/icon_gear.png", "High Contrast", "Adds a dark text outline everywhere",
		_game_state.high_contrast,
		func(on):
			_game_state.high_contrast = on
			_game_state.save_data()
			_game_state.accessibility_changed.emit()
	))
	access_card.add_child(_build_toggle_row(
		"res://assets/settings_ui/icon_info.png", "Dyslexia-Friendly", "Wider letter and word spacing",
		_game_state.dyslexia_spacing,
		func(on):
			_game_state.dyslexia_spacing = on
			_game_state.save_data()
			_game_state.accessibility_changed.emit()
	))
	access_card.add_child(_build_toggle_row(
		"res://assets/settings_ui/icon_chart.png", "Adaptive Difficulty", "Gently follows your recent accuracy",
		_game_state.adaptive_difficulty,
		func(on):
			_game_state.adaptive_difficulty = on
			_game_state.save_data()
	))
	_content.add_child(access_card.get_meta("card_root"))

	_content.add_child(_mini_label("Font size"))
	var font_slider = HSlider.new()
	font_slider.min_value = 0.85
	font_slider.max_value = 1.4
	font_slider.step = 0.05
	font_slider.value = _game_state.font_scale
	font_slider.custom_minimum_size = Vector2(0, 28)
	_content.add_child(font_slider)
	font_slider.value_changed.connect(func(v):
		_game_state.font_scale = v
		_game_state.save_data()
		_game_state.accessibility_changed.emit()
	)

	var colorblind_option = OptionButton.new()
	colorblind_option.custom_minimum_size = Vector2(0, 48)
	colorblind_option.add_theme_font_size_override("font_size", 18)
	var cb_modes = ["off", "deuteranopia", "protanopia", "tritanopia"]
	var cb_labels = {"off": "Off", "deuteranopia": "Deuteranopia-friendly palette", "protanopia": "Protanopia-friendly palette", "tritanopia": "Tritanopia-friendly palette"}
	_content.add_child(_mini_label("Colorblind-friendly palette"))
	for i in cb_modes.size():
		colorblind_option.add_item(cb_labels[cb_modes[i]])
		if cb_modes[i] == _game_state.colorblind_mode:
			colorblind_option.select(i)
	_content.add_child(colorblind_option)
	colorblind_option.item_selected.connect(func(idx):
		_game_state.colorblind_mode = cb_modes[idx]
		_game_state.save_data()
		_game_state.accessibility_changed.emit()
	)

	var access_note = Label.new()
	access_note.text = "Font size scales the whole game immediately. High contrast adds a dark text outline everywhere. Colorblind palette applies a screen-wide filter tuned for the selected type — it's a best-effort assist, not a medical-grade correction. All three apply live and are saved to your profile."
	access_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	access_note.add_theme_font_size_override("font_size", 18)
	_apply_text_style(access_note, COL_MUTE)
	_content.add_child(access_note)

	# Select Career — a shortcut into Career Mode straight from Settings,
	# same as the reference screen. more_screen doesn't own career_screen
	# itself (main.gd does — see career_screen preload/setup there), so
	# this just emits a signal for main.gd to act on, same pattern as
	# replay_tutorial_pressed above it.
	_content.add_child(_section_label("Career"))
	var career_btn = _make_nav_button("SELECT CAREER", COL_AMBER)
	_content.add_child(career_btn)
	career_btn.pressed.connect(func():
		if _audio: _audio.play_whoosh()
		career_pressed.emit()
	)

	# Account (email/password login via AuthManager) — lets a player sign
	# in on this device so cloud save follows their account instead of
	# the anonymous per-device identity. Optional; the game works fully
	# without ever touching this section.
	if _auth:
		_content.add_child(_section_label("Account"))
		var account_status = Label.new()
		account_status.autowrap_mode = TextServer.AUTOWRAP_WORD
		account_status.add_theme_font_size_override("font_size", 18)
		if _auth.is_signed_in_with_email():
			account_status.text = "Signed in as %s" % _auth.current_email()
			_apply_text_style(account_status, COL_MINT)
		else:
			account_status.text = "Sign in to keep your progress backed up to your account."
			_apply_text_style(account_status, COL_MUTE)
		_content.add_child(account_status)

		var account_btn = _make_nav_button(
			"SIGN OUT" if _auth.is_signed_in_with_email() else "SIGN IN / CREATE ACCOUNT",
			COL_GOLD
		)
		_content.add_child(account_btn)
		account_btn.pressed.connect(func():
			if _audio: _audio.play_ui_click()
			if _auth.is_signed_in_with_email():
				_auth.sign_out()
				if _current_view == "settings": _build_settings_panel()
			else:
				var login := preload("res://login_screen.tscn").instantiate() as LoginScreen
				login.has_anonymous_progress_to_keep = _cloud_save != null
				login.setup(self, _auth)
				login.open()
				login.closed.connect(func():
					login.queue_free()
					if _current_view == "settings": _build_settings_panel()
				)
		)

	# Support the Game (donations) — opens the dev's donation page in the
	# device browser. No SDK, no purchase flow, just a link, so it's
	# available even before a real billing SDK is wired in.
	if _monetization:
		_content.add_child(_section_label("Support the Game"))
		var donate_status = Label.new()
		donate_status.autowrap_mode = TextServer.AUTOWRAP_WORD
		donate_status.add_theme_font_size_override("font_size", 18)
		donate_status.text = "Enjoying Type Blast? A small donation helps keep it going \u2014 no purchase required, totally optional."
		_apply_text_style(donate_status, COL_MUTE)
		_content.add_child(donate_status)

		var donate_btn = _make_nav_button("SUPPORT THE GAME", COL_MINT)
		_content.add_child(donate_btn)
		donate_btn.pressed.connect(func():
			if _audio: _audio.play_ui_click()
			_monetization.open_donation_page()
		)

	# Cloud Save — automatic, no-login backup keyed to this device's
	# anonymous Firebase identity (see CloudSaveManager). Protects against
	# losing progress on THIS device (reinstall, storage cleared, etc.)
	# without asking the player to create an account. Does NOT move a
	# save to a different device on its own — the anonymous identity is
	# per-install, so the Backup Code below is still the way to do that.
	if _cloud_save:
		_content.add_child(_section_label("Cloud Save"))
		var cloud_note = Label.new()
		cloud_note.text = "Automatically backs up your progress with no account needed. Sync now, or restore if this device's save was lost."
		cloud_note.autowrap_mode = TextServer.AUTOWRAP_WORD
		cloud_note.add_theme_font_size_override("font_size", 18)
		_apply_text_style(cloud_note, COL_MUTE)
		_content.add_child(cloud_note)

		var cloud_status = Label.new()
		cloud_status.autowrap_mode = TextServer.AUTOWRAP_WORD
		cloud_status.add_theme_font_size_override("font_size", 16)
		cloud_status.visible = false
		_content.add_child(cloud_status)

		var sync_btn = _make_nav_button("SYNC NOW", COL_MINT)
		_content.add_child(sync_btn)

		var cloud_restore_btn = _make_nav_button("RESTORE FROM CLOUD", COL_MUTE)
		_content.add_child(cloud_restore_btn)

		# Stashed on the instance (not captured in a per-rebuild closure)
		# so the single, permanent signal connection made in setup() can
		# always reach whichever copy of this UI is currently on screen,
		# instead of accumulating one stale connection per panel rebuild.
		_cloud_status_label = cloud_status
		_cloud_sync_buttons = [sync_btn, cloud_restore_btn]

		sync_btn.pressed.connect(func():
			if _audio: _audio.play_ui_click()
			_set_cloud_status("Syncing…", COL_MUTE)
			_set_cloud_buttons_disabled(true)
			_cloud_save.upload_save(_game_state)
		)

		cloud_restore_btn.pressed.connect(func():
			if _audio: _audio.play_ui_click()
			_set_cloud_status("Restoring…", COL_MUTE)
			_set_cloud_buttons_disabled(true)
			_cloud_save.download_save(_game_state)
		)

	# Backup Code — a manual, no-account stand-in/companion for cloud save.
	# Packages the actual save file into a copy-pasteable code so progress
	# can be carried to a genuinely NEW device (cloud save above only
	# covers this device, since its identity is per-install).
	_content.add_child(_section_label("Backup Code"))
	var backup_note = Label.new()
	backup_note.text = "No account needed. Copy a backup code and save it somewhere safe, then paste it back in on a new device or after a reinstall."
	backup_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	backup_note.add_theme_font_size_override("font_size", 18)
	_apply_text_style(backup_note, COL_MUTE)
	_content.add_child(backup_note)

	var backup_status = Label.new()
	backup_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	backup_status.add_theme_font_size_override("font_size", 16)
	backup_status.visible = false
	_content.add_child(backup_status)

	var copy_btn = _make_nav_button("COPY BACKUP CODE", COL_SKY)
	_content.add_child(copy_btn)
	copy_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		var code := _game_state.export_save_code()
		backup_status.visible = true
		if code != "":
			DisplayServer.clipboard_set(code)
			backup_status.text = "Copied! Paste it somewhere safe."
			_apply_text_style(backup_status, COL_MINT)
		else:
			backup_status.text = "Couldn't read the save file — try again."
			backup_status.modulate = Color.INDIAN_RED
	)

	var restore_input = LineEdit.new()
	restore_input.placeholder_text = "Paste backup code here"
	restore_input.custom_minimum_size = Vector2(0, 44)
	_content.add_child(restore_input)

	var restore_note = Label.new()
	restore_note.text = "Restoring replaces all current progress on this device with the pasted code."
	restore_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	restore_note.add_theme_font_size_override("font_size", 14)
	_apply_text_style(restore_note, COL_MUTE)
	_content.add_child(restore_note)

	var restore_code_btn = _make_nav_button("RESTORE FROM CODE", COL_MUTE)
	_content.add_child(restore_code_btn)
	restore_code_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		if restore_input.text.strip_edges() == "":
			return
		if _game_state.import_save_code(restore_input.text):
			if _audio: _audio.play_success()
			_refresh_header()
			_build_settings_panel() # progress just got replaced — rebuild to reflect it
		else:
			if _audio: _audio.play_error()
			restore_note.text = "That code didn't look right — double check and try again."
			restore_note.modulate = Color.INDIAN_RED
	)

	# Replay tutorial — the onboarding overlay only ever shows once
	# (gated by GameState.tutorial_seen), with no way back in if you
	# skipped it, forgot it, or just want a refresher. This button is
	# the way back in.
	_content.add_child(_section_label("Help"))
	var replay_tutorial_btn = _make_nav_button("REPLAY TUTORIAL", COL_SKY)
	_content.add_child(replay_tutorial_btn)
	replay_tutorial_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		replay_tutorial_pressed.emit()
	)

	# Contact technical support — a plain mailto: link opened in whatever
	# mail app the device has, same OS.shell_open() approach already used
	# by Support the Game's donation link above. Update SUPPORT_EMAIL to
	# a real inbox before shipping.
	_content.add_child(_section_label("Support"))
	var support_btn = _make_nav_button("CONTACT TECHNICAL SUPPORT", COL_SKY)
	_content.add_child(support_btn)
	support_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		OS.shell_open("mailto:%s?subject=Type%%20Blast%%20support" % SUPPORT_EMAIL)
	)

	# Privacy Policy — legal/PRIVACY_POLICY_DRAFT.md is explicitly a draft
	# (see the file's own header), not a hosted page, so there's no real
	# URL to open yet. Showing it in an in-app scroll dialog is the
	# honest option: it surfaces the actual current text instead of a
	# link to a page that doesn't exist.
	var privacy_btn = _make_nav_button("PRIVACY POLICY", COL_MUTE)
	_content.add_child(privacy_btn)
	privacy_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		_show_privacy_policy_dialog()
	)

	# Delete your account — wipes local progress (GameState.reset_all_progress,
	# already used by the existing "Reset Progress" flow elsewhere), the
	# remote save document if cloud save is set up, and signs out of any
	# linked email account. Gated behind ParentalGate since this is
	# destructive and shouldn't trigger from a stray tap.
	_content.add_child(_section_label("Account Deletion"))
	var delete_status = Label.new()
	delete_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	delete_status.add_theme_font_size_override("font_size", 14)
	delete_status.visible = false
	_content.add_child(delete_status)

	var delete_btn = _make_nav_button("DELETE YOUR ACCOUNT", COL_RED)
	_content.add_child(delete_btn)
	delete_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		var gate := preload("res://scenes/parental_gate.tscn").instantiate() as ParentalGate
		add_child(gate)
		gate.open()
		gate.gate_passed.connect(func():
			_game_state.reset_all_progress()
			if _auth and _auth.is_signed_in_with_email():
				_auth.sign_out()
			delete_status.visible = true
			if _cloud_save and _cloud_save.is_signed_in():
				delete_status.text = "Local progress deleted. Deleting cloud data…"
				_apply_text_style(delete_status, COL_MUTE)
				_cloud_save.delete_cloud_save()
				# One-shot: awaits the very next sync_completed/sync_failed
				# emission and updates this row, then disconnects itself.
				# Deliberately NOT a permanent connection like
				# _on_cloud_sync_completed/_on_cloud_sync_failed above -
				# those already own the Cloud Save section's status label,
				# and this only needs to react to the one delete call it
				# just made, not every future sync/restore too.
				var on_done: Callable
				var on_fail: Callable
				on_done = func(_success: bool):
					delete_status.text = "Account deleted."
					_apply_text_style(delete_status, COL_MINT)
					if _cloud_save.sync_completed.is_connected(on_done):
						_cloud_save.sync_completed.disconnect(on_done)
					if _cloud_save.sync_failed.is_connected(on_fail):
						_cloud_save.sync_failed.disconnect(on_fail)
				on_fail = func(_reason: String):
					delete_status.text = "Local progress deleted. Cloud data may still remain — try again from Settings later."
					_apply_text_style(delete_status, COL_MUTE)
					if _cloud_save.sync_completed.is_connected(on_done):
						_cloud_save.sync_completed.disconnect(on_done)
					if _cloud_save.sync_failed.is_connected(on_fail):
						_cloud_save.sync_failed.disconnect(on_fail)
				_cloud_save.sync_completed.connect(on_done)
				_cloud_save.sync_failed.connect(on_fail)
			else:
				delete_status.text = "Local progress deleted."
				_apply_text_style(delete_status, COL_MINT)
		)
	)

	# Your ID — a short, stable, copy-free identifier shown at the very
	# bottom of Settings, matching the reference screen's "Your ID" row.
	# Falls back to the OS's device id if cloud save was never set up
	# (no _uid to derive a display id from yet).
	var id_text := ""
	if _cloud_save and _cloud_save.is_signed_in():
		id_text = _cloud_save.display_id()
	if id_text == "":
		id_text = OS.get_unique_id().sha256_text().substr(0, 16).to_upper()
	var id_label = Label.new()
	id_label.text = "Your ID: %s" % id_text
	id_label.add_theme_font_size_override("font_size", 13)
	_apply_text_style(id_label, COL_MUTE)
	_content.add_child(id_label)


## Shows the current draft privacy policy text (legal/PRIVACY_POLICY_DRAFT.md)
## in a scrollable in-app dialog, since the file is explicitly marked as a
## draft with no hosted URL yet (see the file's own header). Reading it
## from disk rather than hardcoding a copy means this always reflects
## whatever's actually in the repo.
func _show_privacy_policy_dialog() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560, 640)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	style.set_corner_radius_all(20)
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "PRIVACY POLICY"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COL_GOLD)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 500)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var body := RichTextLabel.new()
	body.fit_content = true
	body.bbcode_enabled = false
	body.custom_minimum_size = Vector2(520, 0)
	body.add_theme_font_size_override("normal_font_size", 14)
	body.add_theme_color_override("default_color", Color(1, 1, 1, 0.85))
	var path := "res://legal/PRIVACY_POLICY_DRAFT.md"
	if ResourceLoader.exists(path) or FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		body.text = f.get_as_text() if f else "Privacy policy text could not be loaded."
	else:
		body.text = "No privacy policy document was found in this build."
	scroll.add_child(body)

	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.custom_minimum_size = Vector2(0, 48)
	vbox.add_child(close_btn)
	close_btn.pressed.connect(func():
		if _audio: _audio.play_ui_click()
		overlay.queue_free()
	)


func _section_label(txt: String) -> Label:
	var l = Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 18)
	_apply_text_style(l, COL_GOLD)
	return l


## Card panel using the settings_card_bg 9-slice asset, matching the
## reference settings screen's rounded cream card look. Wrap a VBoxContainer
## of rows inside this for grouped toggle sections.
##
## BUGFIX: this used to hard-load "res://assets/settings_ui/settings_card_bg.png",
## a file that was never actually added to assets/settings_ui/ (that folder
## doesn't exist in this project at all — see also _build_toggle_row below,
## which referenced the same missing folder for icons and, worse, didn't
## exist as a function at all). load() on a missing path returns null
## silently, so the card rendered with no visible background. Falls back
## to a plain rounded StyleBoxFlat card so Settings still looks like
## grouped sections if/when real art never gets added to that folder.
func _build_settings_card() -> VBoxContainer:
	var root: Control
	var bg_path := "res://assets/settings_ui/settings_card_bg.png"
	if ResourceLoader.exists(bg_path):
		var nine := NinePatchRect.new()
		nine.texture = load(bg_path)
		nine.patch_margin_left = 24
		nine.patch_margin_right = 24
		nine.patch_margin_top = 24
		nine.patch_margin_bottom = 24
		nine.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 20)
		margin.add_theme_constant_override("margin_right", 20)
		margin.add_theme_constant_override("margin_top", 16)
		margin.add_theme_constant_override("margin_bottom", 16)
		nine.add_child(margin)

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		margin.add_child(vbox)
		vbox.set_meta("card_root", nine)
		return vbox

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	var is_light_panel := JellyTheme.current_style != "casual"
	style.bg_color = Color(0.1, 0.09, 0.08, 0.35) if not is_light_panel else Color(1.0, 0.98, 0.9, 0.9)
	style.set_corner_radius_all(18)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var fallback_vbox = VBoxContainer.new()
	fallback_vbox.add_theme_constant_override("separation", 4)
	panel.add_child(fallback_vbox)

	# Store the panel root so callers can add() to it directly while this
	# function returns the inner vbox rows actually get added to.
	fallback_vbox.set_meta("card_root", panel)
	return fallback_vbox


## One icon + title/subtitle + toggle switch row, styled after the
## reference: icon on the left, title (bold) + muted subtitle stacked in
## the middle, toggle switch pinned to the right.
##
## BUGFIX: this function was documented (see comment above) but never
## actually implemented — every call site (Music, Effects, High Contrast,
## Dyslexia-Friendly, Adaptive Difficulty) called a method that didn't
## exist, so opening Settings threw a "Nonexistent function
## '_build_toggle_row'" error and the panel never finished building.
## Icon is optional: if the given path has no real asset behind it yet
## (see _build_settings_card above — assets/settings_ui/ isn't populated
## in this project), the row just skips it instead of showing a broken
## texture.
func _build_toggle_row(icon_path: String, title_text: String, subtitle_text: String, value: bool, on_changed: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size = Vector2(0, 52)

	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(26, 26)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)

	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", 1)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text_col)

	var title_lbl := Label.new()
	title_lbl.text = title_text
	title_lbl.add_theme_font_size_override("font_size", 17)
	_apply_text_style(title_lbl, COL_MINT)
	text_col.add_child(title_lbl)

	if subtitle_text != "":
		var subtitle_lbl := Label.new()
		subtitle_lbl.text = subtitle_text
		subtitle_lbl.add_theme_font_size_override("font_size", 13)
		subtitle_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		_apply_text_style(subtitle_lbl, COL_MUTE)
		text_col.add_child(subtitle_lbl)

	var switch := CheckButton.new()
	switch.button_pressed = value
	switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(switch)
	switch.toggled.connect(func(on: bool):
		if _audio: _audio.play_ui_click()
		on_changed.call(on)
	)

	return row


## One selectable card for the Interface Style picker: a real, disabled
## sample button rendered with JellyTheme.preview_button_style(style) so
## the player sees exactly what that style looks like (not just its name),
## plus a label and a selected-state border/glow.
func _build_style_swatch_card(style: String, is_selected: bool) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(140, 92)
	card.toggle_mode = false
	card.flat = false
	card.focus_mode = Control.FOCUS_ALL

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(1, 1, 1, 0.10 if is_selected else 0.04)
	card_style.border_width_left = 2
	card_style.border_width_right = 2
	card_style.border_width_top = 2
	card_style.border_width_bottom = 2
	card_style.border_color = COL_GOLD if is_selected else Color(1, 1, 1, 0.14)
	card_style.set_corner_radius_all(16)
	card_style.content_margin_top = 12
	card_style.content_margin_bottom = 10
	card.add_theme_stylebox_override("normal", card_style)
	var hover_style3 := card_style.duplicate()
	hover_style3.bg_color = Color(1, 1, 1, 0.14 if is_selected else 0.08)
	card.add_theme_stylebox_override("hover", hover_style3)
	card.add_theme_stylebox_override("pressed", hover_style3)
	card.add_theme_stylebox_override("focus", card_style)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 8)
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)

	# The live preview sample - a real (non-interactive) button skinned
	# with the *other* style's look via preview_button_style(), regardless
	# of which style is currently active app-wide.
	var sample := Button.new()
	sample.text = "AB"
	sample.custom_minimum_size = Vector2(72, 34)
	sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sample.focus_mode = Control.FOCUS_NONE
	sample.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var accent := Color(0.55, 0.85, 0.55)
	sample.add_theme_stylebox_override("normal", JellyTheme.preview_button_style(style, accent, 1.0))
	sample.add_theme_stylebox_override("hover", JellyTheme.preview_button_style(style, accent, 1.0))
	sample.add_theme_stylebox_override("pressed", JellyTheme.preview_button_style(style, accent, 1.0))
	sample.add_theme_stylebox_override("disabled", JellyTheme.preview_button_style(style, accent, 1.0))
	sample.disabled = true
	var sample_wrap := CenterContainer.new()
	sample_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sample_wrap.add_child(sample)
	vb.add_child(sample_wrap)

	var label := Label.new()
	label.text = JellyTheme.STYLE_LABELS.get(style, style.capitalize())
	label.add_theme_font_size_override("font_size", 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_text_style(label, Color.WHITE if is_selected else COL_MUTE)
	vb.add_child(label)

	if is_selected:
		var check := Label.new()
		check.text = "✓ Active"
		check.add_theme_font_size_override("font_size", 13)
		check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_apply_text_style(check, COL_GOLD)
		vb.add_child(check)

	return card


func _mini_label(txt: String) -> Label:
	var l = Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 18)
	_apply_text_style(l, COL_MUTE)
	return l


# --- Share / Export ---

func _build_share_panel() -> void:
	_current_view = "share"
	_clear_content()
	_content.add_child(_make_back_button("hub"))

	var title = Label.new()
	title.text = "SHARE YOUR STATS"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_GOLD)
	_content.add_child(title)

	var card_text = _build_share_card_text()
	var preview = Label.new()
	preview.text = card_text
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD
	preview.add_theme_font_size_override("font_size", 18)
	_apply_text_style(preview, COL_MINT)
	_content.add_child(preview)

	var copy_btn = _make_nav_button("COPY TO CLIPBOARD", COL_GOLD)
	_content.add_child(copy_btn)
	var status_label = Label.new()
	_apply_text_style(status_label, COL_MUTE)
	status_label.add_theme_font_size_override("font_size", 18)
	_content.add_child(status_label)
	copy_btn.pressed.connect(func():
		DisplayServer.clipboard_set(card_text)
		status_label.text = "Copied!"
		if _audio: _audio.play_ui_click()
	)

	var save_btn = _make_nav_button("SAVE TO FILE", COL_MINT)
	_content.add_child(save_btn)
	save_btn.pressed.connect(func():
		var f = FileAccess.open("user://share_card.txt", FileAccess.WRITE)
		if f:
			f.store_string(card_text)
			f.close()
			status_label.text = "Saved to user://share_card.txt"
		else:
			status_label.text = "Couldn't save the file."
	)


func _build_share_card_text() -> String:
	return "TYPE BLAST — my stats\nBest WPM: %.0f\nBest combo: %d\nHigh score: %d\nStreak: %d days (best %d)\nSurvival best: %d words\nDeep Signal: %d/%d chapters\nBadges: %d/%d\nCareer rank: %d" % [
		_game_state.best_wpm, _game_state.best_combo,
		_game_state.high_scores[0] if _game_state.high_scores.size() > 0 else 0,
		_game_state.current_streak, _game_state.longest_streak,
		_game_state.best_survival_streak,
		_game_state.story_chapters_cleared.size(), StoryData.chapter_count(),
		_game_state.unlocked_badges.size(), BadgesManager.all().size(),
		_game_state.career_highest_rank_reached,
	]


# --- Weak Keys Report (replaces the old Bubble Pop fidget panel — this one
# actually uses data the game already tracks: GameState.weak_letter_counts,
# fed every time you miss a word during a run) ---

func _build_weak_keys_panel() -> void:
	_current_view = "weak_keys"
	_clear_content()
	_content.add_child(_make_back_button("cat_progress"))

	var title = Label.new()
	title.text = "WEAK KEYS REPORT"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_SKY)
	_content.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "The letters that show up most often in words you've missed. Turn on \"Practice My Weak Keys\" on the difficulty screen to drill these directly."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	subtitle.add_theme_font_size_override("font_size", 18)
	_apply_text_style(subtitle, COL_MUTE)
	_content.add_child(subtitle)

	var sep = HSeparator.new()
	_content.add_child(sep)

	var weak_letters: Array = _game_state.get_weak_letters(8)
	if weak_letters.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No missed-word data yet — play a few runs and check back here."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty_label.add_theme_font_size_override("font_size", 18)
		_apply_text_style(empty_label, COL_MUTE)
		_content.add_child(empty_label)
	else:
		var list_wrap = VBoxContainer.new()
		list_wrap.add_theme_constant_override("separation", 8)
		_content.add_child(list_wrap)

		var max_count: int = _game_state.weak_letter_counts[weak_letters[0]]
		for i in weak_letters.size():
			var letter = weak_letters[i]
			var count: int = _game_state.weak_letter_counts[letter]
			list_wrap.add_child(_weak_key_row(letter, count, max_count, i))

		var hand_report = KeyboardLayoutManager.hand_report(_game_state.weak_letter_counts, _game_state.keyboard_layout)
		if not hand_report.is_empty():
			var hand_label = Label.new()
			var top = hand_report[0]
			hand_label.text = "Overall, your %s hand is doing the most of the missing (%d tracked)." % [top.hand, top.count]
			hand_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			hand_label.add_theme_font_size_override("font_size", 18)
			_apply_text_style(hand_label, COL_AMBER)
			_content.add_child(hand_label)


# Single ranked row: letter badge + a bar sized relative to the worst
# offender + the raw miss count. Rank 0 gets the gold tint so the single
# biggest problem letter is obvious at a glance.
func _weak_key_row(letter: String, count: int, max_count: int, rank: int) -> Control:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var tint = COL_GOLD if rank == 0 else COL_SKY

	var badge = PanelContainer.new()
	badge.custom_minimum_size = Vector2(36, 36)
	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = Color(tint.r, tint.g, tint.b, 0.85)
	badge_style.set_corner_radius_all(10)
	badge.add_theme_stylebox_override("panel", badge_style)
	var letter_label = Label.new()
	letter_label.text = letter.to_upper()
	letter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter_label.add_theme_font_size_override("font_size", 18)
	letter_label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
	badge.add_child(letter_label)
	row.add_child(badge)

	var bar_wrap = Control.new()
	bar_wrap.custom_minimum_size = Vector2(0, 20)
	bar_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar_wrap)

	var bar_bg = ColorRect.new()
	bar_bg.color = Color(1, 1, 1, 0.08)
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_wrap.add_child(bar_bg)

	var bar_fill = ColorRect.new()
	bar_fill.color = tint
	bar_fill.anchor_top = 0
	bar_fill.anchor_bottom = 1
	bar_fill.anchor_left = 0
	bar_fill.anchor_right = clamp(float(count) / max(max_count, 1), 0.04, 1.0)
	bar_bg.add_child(bar_fill)

	var count_label = Label.new()
	count_label.text = str(count)
	count_label.custom_minimum_size = Vector2(30, 0)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.add_theme_font_size_override("font_size", 18)
	_apply_text_style(count_label, COL_MUTE)
	row.add_child(count_label)

	return row


# --- Fun Fact / Joke (general trivia + one-liners - also no connection to
# typing; distinct from Word of the Day, which is at least vocab-adjacent) ---

func _build_credits_panel() -> void:
	_current_view = "credits"
	_clear_content()
	_content.add_child(_make_back_button("cat_about"))

	var title = Label.new()
	title.text = "CREDITS"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_MUTE)
	_content.add_child(title)

	var made_by = Label.new()
	made_by.text = "Type Blast — made by Emmanuel."
	made_by.add_theme_font_size_override("font_size", 19)
	_content.add_child(made_by)

	_content.add_child(_section_label("Art assets"))
	var kenney_panel = _credits_card(
		"Medal / badge icons",
		"By Kenney (kenney.nl) — Creative Commons Zero (CC0). Free for any use; credit isn't required but is appreciated."
	)
	_content.add_child(kenney_panel)

	var sungraphica_panel = _credits_card(
		"UI buttons & panels (\"jelly\" skin)",
		"Casual Game Interface Kit by SunGraphica (sungraphica.itch.io) — personal & commercial use, modification allowed."
	)
	_content.add_child(sungraphica_panel)

	_content.add_child(_section_label("Music"))
	var music_note = Label.new()
	music_note.text = "Four background tracks are bundled in audio/. Licensing for these hasn't been confirmed/recorded yet — check where each was sourced from before shipping a public release, and add the license terms here once confirmed."
	music_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	music_note.add_theme_font_size_override("font_size", 17)
	_apply_text_style(music_note, COL_AMBER)
	_content.add_child(music_note)

	var track_names := [
		"\"Where the Answers At\"",
		"\"Me and the Answer\"",
		"\"Thinking for my self\"",
		"\"Typing to my self\"",
		"\"dragon-studio-correct\" (SFX)",
		"\"dragon-studio-keyboard-typing-sound-effect\" (SFX)",
	]
	for t in track_names:
		var tl = Label.new()
		tl.text = "• " + t
		tl.add_theme_font_size_override("font_size", 16)
		_apply_text_style(tl, COL_MUTE)
		_content.add_child(tl)


func _credits_card(heading: String, body: String) -> PanelContainer:
	var panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.05)
	style.set_corner_radius_all(16)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	var head = Label.new()
	head.text = heading
	head.add_theme_font_size_override("font_size", 18)
	_apply_text_style(head, COL_MINT)
	vbox.add_child(head)

	var body_label = Label.new()
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	body_label.add_theme_font_size_override("font_size", 16)
	_apply_text_style(body_label, COL_MUTE)
	vbox.add_child(body_label)

	return panel


func _build_facts_panel() -> void:
	_current_view = "facts"
	_clear_content()
	_content.add_child(_make_back_button("cat_about"))

	var title = Label.new()
	title.text = "FUN FACT / JOKE"
	title.add_theme_font_size_override("font_size", 24)
	_apply_title_style(title, COL_AMBER)
	_content.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Nothing to do with typing — just something fun to read."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	subtitle.add_theme_font_size_override("font_size", 18)
	_apply_text_style(subtitle, COL_MUTE)
	_content.add_child(subtitle)

	var fact_panel = PanelContainer.new()
	var fact_style := StyleBoxFlat.new()
	fact_style.bg_color = Color(1, 1, 1, 0.05)
	fact_style.set_corner_radius_all(16)
	fact_style.content_margin_left = 18
	fact_style.content_margin_right = 18
	fact_style.content_margin_top = 16
	fact_style.content_margin_bottom = 16
	fact_panel.add_theme_stylebox_override("panel", fact_style)
	_content.add_child(fact_panel)

	_fact_label = Label.new()
	var date_seed = int(Time.get_date_string_from_system().replace("-", ""))
	_fact_label.text = FactsManager.get_fact(date_seed)
	_fact_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_fact_label.add_theme_font_size_override("font_size", 19)
	_apply_text_style(_fact_label, COL_MINT)
	fact_panel.add_child(_fact_label)

	var another_btn = _make_nav_button("ANOTHER ONE →", COL_AMBER)
	_content.add_child(another_btn)
	another_btn.pressed.connect(_on_another_fact_pressed)


func _on_another_fact_pressed() -> void:
	if not is_instance_valid(_fact_label):
		return
	_fact_label.text = FactsManager.get_fact(randi())
	if _audio: _audio.play_ui_click()
	_fact_label.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(_fact_label, "modulate:a", 1.0, 0.25)


# --- Open / close ---

## initial_view lets callers (e.g. the MORE flyout's quick-access shortcuts
## in difficulty_menu.gd) land directly on a specific panel instead of
## always starting at the hub list.
func open(initial_view: String = "hub") -> void:
	_refresh_backdrop()
	_refresh_header()
	_check_new_badges()
	_go_to(initial_view)
	move_to_front()
	visible = true
	modulate.a = 0.0
	if is_instance_valid(_card):
		_card.scale = Vector2(0.94, 0.94)
		_card.pivot_offset = _card.size / 2
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	if is_instance_valid(_card):
		tw.parallel().tween_property(_card, "scale", Vector2(1.0, 1.0), 0.3)


func _refresh_header() -> void:
	_streak_label.text = "🔥 %d day streak (best %d)" % [_game_state.current_streak, _game_state.longest_streak]
	var date_seed = int(Time.get_date_string_from_system().replace("-", ""))
	var wod = VocabularyManager.word_of_the_day(date_seed)
	_word_of_day_label.text = "Word of the day: %s — %s" % [wod.word, wod.definition]
	_tip_label.text = "Tip: " + TipsManager.get_tip()
	if _game_state.is_streak_at_risk():
		_streak_risk_label.text = "🔥 Play today to keep your %d-day streak!" % _game_state.current_streak
		_streak_risk_label.visible = true
	else:
		_streak_risk_label.visible = false


func close() -> void:
	if _current_view == "lan_versus" and is_instance_valid(_lan_manager):
		_lan_manager.shutdown()
	if _current_view == "internet_versus" and is_instance_valid(_internet_manager):
		_internet_manager.shutdown()
	if _current_view == "online_tournament" and is_instance_valid(_tournament_manager):
		_tournament_manager.shutdown()
	visible = false
	closed.emit()


func _on_close_pressed() -> void:
	if _audio: _audio.play_ui_click()
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _current_view == "hub":
			close()
		elif _current_view == "practice_session":
			_go_to("practice_menu")
		else:
			_go_to(VIEW_PARENT.get(_current_view, "hub"))
