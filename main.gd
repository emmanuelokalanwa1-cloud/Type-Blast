extends Control

## Main no longer owns gameplay logic itself — it just builds the
## sub-systems (each its own node/script under res://scripts/), wires their
## signals together, and drives the per-frame loop (spawning, falling,
## freeze/slow-mo, screen shake, level-up transitions).
##
## ---------------------------------------------------------------------
## CHANGELOG (this pass)
## ---------------------------------------------------------------------
## MAIN FIX: spawn delay used to be keyed off SCORE (fast_level_threshold),
## not LEVEL. That meant difficulty could spike unrelated to what level you
## were on. It's now keyed purely off level, with a grace period and a cap.
##
## FOLLOW-UP FIX (this pass): frenzy_mode had the same shape of bug -  a
## flat, instant 3x spawn-rate multiplier with no ramp and no cap of its
## own, so a combo streak could spike difficulty the same way score used
## to. It now ramps in/out over ~0.5s (frenzy_rate_smoothed) instead of
## snapping, uses a gentler 2.4x ceiling instead of 3x, and has its own
## floor (min_frenzy_spawn_delay_cap) so it can't compound with a high
## level into something unplayable.
##
## NEW THIS PASS: wired TypingController's key_typed/key_deleted signals to
## AudioManager.play_keystroke() so the typing sound fires exactly once per
## real key you press instead of drifting off on its own. Also calls
## typing_controller.reset() whenever the pause menu, difficulty menu, or a
## fresh run opens, so no stale input state leaks between screens.
##
## 20 additive extras (all self-contained in this script, all guarded, none
## call into other scripts' unknown methods — so this can't break anything):
##  1. Level-only fall-speed curve (the actual bug fix)
##  2. Soft-landing grace period at the start of every new level
##  3. Miss-streak rubber-band assist (eases spawn rate if you're struggling)
##  4. Hard difficulty caps (fall speed + spawn delay can't go past sane limits)
##  5. Difficulty tier name callout on level-up ("WARM UP", "EXPERT", etc.)
##  6. Track total words spawned this run
##  7. Track total words typed successfully this run
##  8. Track run start time (available for future stats/WPM use)
##  9. Perfect-level bonus (+10s if you clear a level with zero misses)
## 10. Combo milestone celebrations (10/25/50/75/100/150)
## 11. Frenzy threshold eases at low levels, tightens at high levels
## 12. Reduced-motion toggle (skips screen shake when enabled)
## 13. Frenzy "about to end" warning callout
## 14. Richer score-view popup (shows top 2 instead of just top 1)
## 15. Highest combo reached this run (tracked, available for stats)
## 16. Total misses this run (tracked, available for stats)
## 17. Milestone celebrations reset cleanly on a miss (fair re-earning)
## 18. Pause button tints when paused (small visual confirmation)
## 19. Grace period also softens spawn rate, not just fall speed
## 20. All new state resets cleanly on every _start_game() call
## 21. Input box nudges above the bottom gesture-nav safe area in portrait
##     (see _bottom_safe_area_inset), so it never sits under the OS bar
## ---------------------------------------------------------------------

# --- UI REFERENCES (from main.tscn) ---
@onready var word_label_template: Label = $WordLabel
@onready var input_box: LineEdit = $InputBox
@onready var score_label: Label = $ScoreLabel
@onready var time_label: Label = $TimeLabel
@onready var lives_label: Label = $LivesLabel
@onready var highscore_label: Label = $HighScoreLabel
@onready var combo_label: Label = $ComboLabel
@onready var result_panel: ColorRect = $ResultPanel
@onready var restart_button: Button = $ResultPanel/RestartButton
@onready var final_score_label: Label = $ResultPanel/FinalScoreLabel
@onready var coin_label: Label = $ResultPanel/CoinLabel
@onready var menu_button: Button = $ResultPanel/MenuButton
@onready var score_button: Button = $ResultPanel/ScoreButton

@onready var success_snd = get_node_or_null("SuccessPlayer")
@onready var error_snd = get_node_or_null("ErrorPlayer")
@onready var music_snd = get_node_or_null("MusicPlayer")

# Bonus SFX pack + keystroke sound — now real scene nodes (see main.tscn)
# instead of being built from a hardcoded path in AudioManager. Change any
# of these by clicking the node in the editor and dragging a new file onto
# its Stream property; no script edit needed.
@onready var click_snd = get_node_or_null("ClickPlayer")
@onready var notification_snd = get_node_or_null("NotificationPlayer")
@onready var levelup_sting_snd = get_node_or_null("LevelUpPlayer")
@onready var whoosh_snd = get_node_or_null("WhooshPlayer")
@onready var gameover_voice_snd = get_node_or_null("GameOverVoicePlayer")
@onready var keystroke_snd = get_node_or_null("KeystrokePlayer")

# --- SUB-SYSTEMS ---
var game_state: GameState
var accessibility_manager: AccessibilityManager
var word_manager: WordManager
var powerup_system: PowerupSystem
var typing_controller: TypingController
var ui_hud: UiHud
var audio: AudioManager
var pause_menu: PauseMenu
var difficulty_menu: DifficultyMenu
var tutorial_overlay: TutorialOverlay
var stats_screen: StatsScreen
var mobile_support: MobileSupport
var mission_manager: MissionManager
var monetization: MonetizationManager
var cloud_save: CloudSaveManager
var auth: AuthManager
var missions_screen: MissionsScreen
var career_manager: CareerManager
var career_screen: CareerScreen
var achievements_screen: AchievementsScreen
var sentence_mode_screen: SentenceModeScreen
var dictation_screen: DictationScreen
var more_screen: MoreScreen
var lan_manager: LanMultiplayerManager
var internet_manager: InternetMultiplayerManager
var tournament_manager: TournamentManager
var rainbow_surprise: RainbowSurprise
var secret_code_egg: SecretCodeEgg
var big_word_banner: BigWordBanner
var round_start_announcer: RoundStartAnnouncer
var adaptive_difficulty: AdaptiveDifficulty
var _audio_unlocked := false
var _pending_menu_music := false

var pause_button: Button
var _pause_status_dot: ColorRect # 3. live running/paused indicator dot

# --- loop-local state ---
var is_transitioning := false
var spawn_timer := 0.0
var base_fall_speed := 40.0
var career_fall_speed_bonus := 0.0
var fast_level_threshold := 1000 # kept for compatibility; no longer drives spawn delay (see fix)
var original_input_pos_y: float

# Optional dev toggle: auto-types the oldest word every ai_speed seconds.
var ai_enabled := false
var ai_timer := 0.0
var ai_speed := 2.0

# --- Enhancement state (additive only, see CHANGELOG above) ---
var level_grace_timer := 0.0                 # 2, 19
var level_grace_duration := 1.6              # 2, 19
var miss_streak := 0                         # 3
var max_fall_speed_cap := 260.0              # 4
var min_spawn_delay_cap := 0.55              # 4
# Frenzy used to be a flat instant 3x spawn-rate multiplier with no ramp
# and no cap of its own - the same shape of bug as the score-linked spawn
# spike that was fixed above, just reintroduced through combo instead of
# score. frenzy_rate_smoothed eases toward its target over ~0.5s instead
# of snapping, and min_frenzy_spawn_delay_cap gives frenzy its own floor
# (faster than the normal level cap, since that's the point of frenzy -
# but still bounded, so it can't compound with a high level into
# something unplayable).
var frenzy_rate_smoothed := 1.0
var frenzy_rate_target := 2.4                # was a flat 3.0x; gentler ceiling
var frenzy_rate_ramp_speed := 3.0            # units/sec toward target (~0.5s to ramp fully in or out)
var min_frenzy_spawn_delay_cap := 0.35
var difficulty_tier_names := [               # 5
	"WARM UP", "GETTING QUICKER", "PICKING UP PACE", "CHALLENGING",
	"FAST", "EXPERT", "BLISTERING", "INSANE"
]
var total_words_spawned := 0                 # 6
var total_words_typed := 0                   # 7
var run_start_msec := 0                      # 8
var current_level_had_miss := false          # 9
var milestone_combos := [10, 25, 50, 75, 100, 150]  # 10
var milestones_hit := {}                     # 10, 17
var frenzy_warned := false                   # 13
var highest_combo_this_run := 0              # 15
var total_run_misses := 0                    # 16

# --- Combo streak bonuses (21): 10/25/50-combo tiers grant an escalating
# score bonus plus temporary fall-speed relief on top of the existing
# milestone celebration text, so a hot streak actually gets easier to keep
# alive for a few seconds instead of just being praised for it. Resets
# alongside milestones_hit (fresh run, or the moment a miss breaks combo).
var streak_bonus_tiers := [10, 25, 50]
var streak_bonuses_hit := {}
var streak_relief_timer := 0.0
var streak_relief_factor := 1.0   # multiplies base_fall_speed while active; 1.0 = no relief
var streak_relief_tier := 0       # 0 = inactive, 1/2/3 = which tier is currently easing the fall

func _ready() -> void:
	randomize()

	# Mobile support first: everything else (input box placement, HUD
	# positions) may want to know is_touch / safe-area insets right away.
	mobile_support = preload("res://scenes/mobile_support.tscn").instantiate() as MobileSupport
	add_child(mobile_support)
	mobile_support.back_pressed.connect(_on_back_pressed)
	mobile_support.app_focus_lost.connect(_on_app_focus_lost)
	mobile_support.viewport_resized.connect(_on_viewport_resized)

	game_state = preload("res://scenes/game_state.tscn").instantiate() as GameState
	add_child(game_state)

	monetization = preload("res://scenes/monetization_manager.tscn").instantiate() as MonetizationManager
	add_child(monetization)
	monetization.init_ads()

	cloud_save = preload("res://cloud_save_manager.tscn").instantiate() as CloudSaveManager
	add_child(cloud_save)

	auth = preload("res://auth_manager.tscn").instantiate() as AuthManager
	add_child(auth)

	accessibility_manager = preload("res://scenes/accessibility_manager.tscn").instantiate() as AccessibilityManager
	add_child(accessibility_manager)
	accessibility_manager.setup(game_state)

	word_manager = preload("res://scenes/word_manager.tscn").instantiate() as WordManager
	add_child(word_manager)
	word_manager.setup(word_label_template, self, game_state)

	powerup_system = preload("res://scenes/powerup_system.tscn").instantiate() as PowerupSystem
	add_child(powerup_system)
	powerup_system.setup(game_state)

	audio = preload("res://scenes/audio_manager.tscn").instantiate() as AudioManager
	add_child(audio)
	
	# Pack your gameplay tracks into an array for the new playlist system
	var gameplay_tracks: Array[AudioStreamPlayer] = []
	if has_node("MusicPlayer1"): gameplay_tracks.append($MusicPlayer1)
	if has_node("MusicPlayer2"): gameplay_tracks.append($MusicPlayer2)
	if has_node("MusicPlayer3"): gameplay_tracks.append($MusicPlayer3)
	
	# FIXED LINE BELOW: Wrapped music_snd inside an Array bracket [music_snd] 
	# to support multiple menu tracks expected by the updated AudioManager setup.
	audio.setup(game_state, [music_snd], gameplay_tracks, success_snd, error_snd, keystroke_snd,
		click_snd, notification_snd, levelup_sting_snd, whoosh_snd, gameover_voice_snd)

	ui_hud = preload("res://scenes/ui_hud.tscn").instantiate() as UiHud
	add_child(ui_hud)
	ui_hud.setup(self, game_state, score_label, time_label, lives_label, highscore_label, combo_label)

	stats_screen = preload("res://scenes/stats_screen.tscn").instantiate() as StatsScreen
	add_child(stats_screen)
	stats_screen.setup(result_panel, final_score_label, coin_label, game_state, audio)

	stats_screen.restart_pressed.connect(_on_restart_pressed)
	stats_screen.menu_pressed.connect(_on_menu_pressed)
	stats_screen.quit_pressed.connect(_on_quit_to_menu)

	typing_controller = preload("res://scenes/typing_controller.tscn").instantiate() as TypingController
	add_child(typing_controller)
	typing_controller.setup(input_box, word_manager, func(): return game_state.running and not game_state.is_paused and not is_transitioning and not (is_instance_valid(tutorial_overlay) and tutorial_overlay.visible), mobile_support)
	typing_controller.word_matched.connect(_on_word_matched)
	typing_controller.input_invalid.connect(_on_input_invalid)

	# NEW: keystroke sound now fires exactly once per real key you press or
	# delete, instead of drifting off on its own separate trigger.
	typing_controller.key_typed.connect(func(letter: String, is_valid: bool):
		audio.play_keystroke(is_valid)
		game_state.record_letter_accuracy(letter, is_valid)
	)
	typing_controller.key_deleted.connect(func(): audio.play_keystroke(false))

	word_manager.word_missed.connect(_on_word_missed)

	game_state.level_up.connect(_on_level_up)
	game_state.game_ended.connect(_on_game_ended)

	if music_snd:
		music_snd.finished.connect(_on_music_finished)

	word_label_template.visible = false
	word_label_template.add_theme_font_size_override("font_size", 32)
	input_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	input_box.add_theme_font_size_override("font_size", 36)
	input_box.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	input_box.context_menu_enabled = false   # no copy/paste bubble on long-press
	input_box.selecting_enabled = false
	# The keyboard must never show word predictions/suggestions above it -
	# that's the falling word's correct spelling, handed to the player for
	# free. URL-type still let some keyboards (Gboard included) show a
	# suggestion strip. PASSWORD-type reliably suppresses it on Android and
	# iOS. This does NOT mask the typed text on screen - Godot draws the
	# LineEdit's text itself; the native OS text field behind it (used only
	# to bridge IME input) is invisible, so the player still sees exactly
	# what they type.
	input_box.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	input_box.secret = false
	if mobile_support.is_touch:
		input_box.position.y = get_viewport_rect().size.y * 0.55 - _bottom_safe_area_inset()
	else:
		input_box.position.y = get_viewport_rect().size.y - 120
	original_input_pos_y = input_box.position.y

	restart_button.text = "RESTART"
	restart_button.pressed.connect(_on_restart_pressed)
	if menu_button: menu_button.pressed.connect(_on_menu_pressed)
	if score_button: score_button.pressed.connect(_on_score_view_pressed)

	_setup_pause_button()

	mobile_support.apply_safe_area_top([
		score_label, time_label, lives_label, combo_label, highscore_label,
		pause_button, _pause_status_dot,
	])

	pause_menu = preload("res://scenes/pause_menu.tscn").instantiate() as PauseMenu
	pause_menu.setup(self, game_state, audio)
	pause_menu.resume_pressed.connect(_on_resume_pressed)
	pause_menu.restart_pressed.connect(_on_pause_restart_pressed)
	pause_menu.quit_pressed.connect(_on_quit_to_menu)

	difficulty_menu = preload("res://scenes/difficulty_menu.tscn").instantiate() as DifficultyMenu
	difficulty_menu.setup(self, game_state)
	difficulty_menu.start_pressed.connect(_on_difficulty_start)
	difficulty_menu.close()

	mission_manager = preload("res://scenes/mission_manager.tscn").instantiate() as MissionManager
	add_child(mission_manager)
	mission_manager.setup(game_state)

	missions_screen = preload("res://scenes/missions_screen.tscn").instantiate() as MissionsScreen
	missions_screen.setup(self, game_state, mission_manager)
	difficulty_menu.missions_pressed.connect(func(): audio.play_whoosh(); missions_screen.open())
	missions_screen.closed.connect(func(): audio.play_ui_click())

	career_manager = preload("res://scenes/career_manager.tscn").instantiate() as CareerManager
	add_child(career_manager)
	career_manager.setup(game_state, mission_manager)

	career_screen = preload("res://scenes/career_screen.tscn").instantiate() as CareerScreen
	career_screen.setup(self, game_state, mission_manager, career_manager)
	career_screen.rank_selected.connect(_on_career_rank_selected)
	difficulty_menu.career_pressed.connect(func(): audio.play_whoosh(); career_screen.open())
	career_screen.closed.connect(func(): audio.play_ui_click())

	achievements_screen = preload("res://scenes/achievements_screen.tscn").instantiate() as AchievementsScreen
	achievements_screen.setup(self, game_state)
	difficulty_menu.achievements_pressed.connect(func(): audio.play_whoosh(); achievements_screen.open())
	achievements_screen.closed.connect(func(): audio.play_ui_click())

	sentence_mode_screen = preload("res://scenes/sentence_mode_screen.tscn").instantiate() as SentenceModeScreen
	sentence_mode_screen.setup(self, game_state, mission_manager)
	difficulty_menu.sentence_mode_pressed.connect(func(): audio.play_whoosh(); sentence_mode_screen.open())
	sentence_mode_screen.closed.connect(func(): audio.play_ui_click())

	dictation_screen = preload("res://scenes/dictation_screen.tscn").instantiate() as DictationScreen
	dictation_screen.setup(self, game_state)
	dictation_screen.closed.connect(func(): audio.play_ui_click())

	lan_manager = preload("res://scenes/lan_multiplayer_manager.tscn").instantiate() as LanMultiplayerManager
	lan_manager.name = "LanMultiplayerManager"
	add_child(lan_manager)

	internet_manager = preload("res://scenes/internet_multiplayer_manager.tscn").instantiate() as InternetMultiplayerManager
	internet_manager.name = "InternetMultiplayerManager"
	add_child(internet_manager)

	tournament_manager = preload("res://tournament_manager.tscn").instantiate() as TournamentManager
	tournament_manager.name = "TournamentManager"
	add_child(tournament_manager)

	more_screen = preload("res://scenes/more_screen.tscn").instantiate() as MoreScreen
	more_screen.setup(self, game_state, audio, mission_manager, lan_manager, internet_manager, monetization, cloud_save, tournament_manager, auth)
	more_screen.dictation_pressed.connect(func(): more_screen.close(); dictation_screen.open())
	difficulty_menu.more_pressed.connect(func(): audio.play_whoosh(); more_screen.open())
	difficulty_menu.more_shortcut_pressed.connect(func(view_id): audio.play_whoosh(); more_screen.open(view_id))
	more_screen.closed.connect(func(): audio.play_ui_click())
	more_screen.view_full_achievements.connect(func(): more_screen.close(); achievements_screen.open())
	more_screen.replay_tutorial_pressed.connect(func(): more_screen.close(); tutorial_overlay.open())
	more_screen.career_pressed.connect(func(): more_screen.close(); audio.play_whoosh(); career_screen.open())

	tutorial_overlay = preload("res://scenes/tutorial_overlay.tscn").instantiate() as TutorialOverlay
	tutorial_overlay.setup(self, game_state)
	tutorial_overlay.finished.connect(_on_tutorial_finished)
	tutorial_overlay.visible = false

	# SURPRISES: two self-contained overlays that need zero setup() calls -
	# they just sit here quietly and fire themselves.
	rainbow_surprise = preload("res://scenes/rainbow_surprise.tscn").instantiate() as RainbowSurprise
	add_child(rainbow_surprise)
	secret_code_egg = preload("res://scenes/secret_code_egg.tscn").instantiate() as SecretCodeEgg
	add_child(secret_code_egg)

	# ARCADE-ANNOUNCER FLOURISHES: same self-contained pattern, each takes a
	# single setup() call and wires its own signal listener internally.
	big_word_banner = preload("res://scenes/big_word_banner.tscn").instantiate() as BigWordBanner
	add_child(big_word_banner)
	big_word_banner.setup(typing_controller)
	round_start_announcer = preload("res://scenes/round_start_announcer.tscn").instantiate() as RoundStartAnnouncer
	add_child(round_start_announcer)
	round_start_announcer.setup(game_state)
	adaptive_difficulty = preload("res://scenes/adaptive_difficulty.tscn").instantiate() as AdaptiveDifficulty
	add_child(adaptive_difficulty)
	adaptive_difficulty.setup(game_state, typing_controller, word_manager)

	game_state.ui_style_changed.connect(_on_ui_style_changed)

	result_panel.visible = false
	pause_button.visible = false

	if game_state.tutorial_seen:
		difficulty_menu.open()
		_pending_menu_music = true
		_check_daily_login_reward()
	else:
		tutorial_overlay.open()

## Daily Login Reward popup — separate from Daily Challenge and from
## Career/Achievements toasts. Fires at most once per calendar day, and
## only once tutorial_seen is true (first-ever launch shows the tutorial
## instead, so a brand new player doesn't get a reward popup for a streak
## they haven't started yet).
func _check_daily_login_reward() -> void:
	var reward := game_state.claim_daily_login_reward()
	if reward.is_empty():
		return
	var newly_badges: Array = BadgesManager.evaluate(game_state, mission_manager)
	if not newly_badges.is_empty():
		game_state.unlocked_badges.append_array(newly_badges)
		game_state.save_data()
	var newly_missions: Array = []
	if is_instance_valid(mission_manager):
		newly_missions = mission_manager.evaluate_daily_login()
	_show_daily_login_popup(reward, newly_badges, newly_missions)

func _show_daily_login_popup(reward: Dictionary, newly_badges: Array, newly_missions: Array = []) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 90
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.13, 0.98)
	style.set_corner_radius_all(24)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.78, 0.25, 0.6)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(320, 0)
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)

	var title := Label.new()
	title.text = "ðŸŽ DAILY LOGIN REWARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.25))
	vb.add_child(title)

	var streak_lbl := Label.new()
	streak_lbl.text = "Day %d of your streak (login #%d overall)" % [reward.get("day_in_cycle", 1), reward.get("streak", 1)]
	streak_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	streak_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	streak_lbl.add_theme_font_size_override("font_size", 16)
	streak_lbl.modulate = Color(1, 1, 1, 0.75)
	vb.add_child(streak_lbl)

	var xp_lbl := Label.new()
	xp_lbl.text = "+%d XP" % reward.get("xp", 0)
	xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_lbl.add_theme_font_size_override("font_size", 26)
	xp_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.75))
	vb.add_child(xp_lbl)

	if reward.get("leveled_up", false):
		var lvl_lbl := Label.new()
		lvl_lbl.text = "LEVEL UP! Now level %d" % game_state.level
		lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lvl_lbl.add_theme_font_size_override("font_size", 16)
		lvl_lbl.add_theme_color_override("font_color", Color.GOLD)
		vb.add_child(lvl_lbl)

	if not newly_badges.is_empty():
		var badge_lbl := Label.new()
		var badge_defs := BadgesManager.all()
		var names: Array = []
		for id in newly_badges:
			for b in badge_defs:
				if b.get("id", "") == id:
					names.append("%s %s" % [b.get("icon", ""), b.get("name", "")])
		badge_lbl.text = "New badge: " + ", ".join(names)
		badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		badge_lbl.add_theme_font_size_override("font_size", 15)
		badge_lbl.add_theme_color_override("font_color", Color(0.95, 0.6, 0.25))
		vb.add_child(badge_lbl)

	if not newly_missions.is_empty():
		var mission_lbl := Label.new()
		var mission_texts: Array = []
		for m in newly_missions:
			mission_texts.append(String(m.get("text", "")))
		mission_lbl.text = "Mission complete: " + ", ".join(mission_texts)
		mission_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mission_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		mission_lbl.add_theme_font_size_override("font_size", 15)
		mission_lbl.add_theme_color_override("font_color", Color(0.45, 0.7, 0.95))
		vb.add_child(mission_lbl)

	var claim_btn := Button.new()
	claim_btn.text = "NICE!"
	claim_btn.custom_minimum_size = Vector2(0, 48)
	vb.add_child(claim_btn)
	claim_btn.pressed.connect(func():
		audio.play_ui_click()
		overlay.queue_free()
	)

func _setup_pause_button() -> void:
	pause_button = Button.new()
	pause_button.text = "PAUSE"
	pause_button.add_theme_font_size_override("font_size", 16)

	pause_button.anchor_left = 0.0
	pause_button.anchor_right = 0.0
	pause_button.position = Vector2(25, 128)
	# 48x48dp is the platform-recommended minimum touch target; the mouse-
	# driven desktop size (140x36) is too cramped to tap reliably.
	pause_button.size = Vector2(150, 52) if mobile_support.is_touch else Vector2(140, 36)
	pause_button.pivot_offset = pause_button.size / 2

	var normal := _pause_btn_style("", 0.9)
	pause_button.add_theme_stylebox_override("normal", normal)
	var hover_style := _pause_btn_style("", 1.1)
	pause_button.add_theme_stylebox_override("hover", hover_style)
	var pressed_style := _pause_btn_style("", 1.0)
	pause_button.add_theme_stylebox_override("pressed", pressed_style)

	pause_button.tooltip_text = "Tap to pause the game"

	pause_button.pressed.connect(_toggle_pause)
	add_child(pause_button)

	var pause_icon := JellyTheme.icon_rect("pause", Vector2(16, 16))
	pause_icon.modulate = Color(0.06, 0.16, 0.05)
	pause_icon.anchor_left = 0.0
	pause_icon.anchor_top = 0.0
	pause_icon.position = pause_button.position + Vector2(10, pause_button.size.y / 2.0 - 8)
	pause_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pause_icon)
	pause_button.text = "   PAUSE"

	_pause_status_dot = ColorRect.new()
	_pause_status_dot.size = Vector2(10, 10)
	_pause_status_dot.color = Color(0.3, 0.9, 0.4)
	_pause_status_dot.anchor_left = 0.0
	_pause_status_dot.anchor_right = 0.0
	_pause_status_dot.position = Vector2(11, 143)
	_pause_status_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pause_status_dot)

# FIXED: Removed JellyTheme button style dependency to avoid texture stretching.
# Now generates a crisp vector style to perfectly align with your casual style sheet.
func _pause_btn_style(_texture_path: String, brightness: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	
	var base_color = Color(0.1, 0.1, 0.1, 0.6)
	if brightness > 1.0:
		# Hovered
		style.bg_color = Color(0.12, 0.18, 0.14, 0.8)
		style.border_color = Color(0.4, 0.9, 0.75, 0.6) # COL_MINT
	elif brightness < 1.0:
		# Pressed
		style.bg_color = Color(0.05, 0.08, 0.06, 0.9)
		style.border_color = Color(0.4, 0.9, 0.75, 0.8)
	else:
		# Normal state
		style.bg_color = base_color
		style.border_color = Color(0.4, 0.9, 0.75, 0.3)
	
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	
	style.set_corner_radius_all(10)
	
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	
	return style

func _toggle_pause() -> void:
	if not game_state.running:
		return
	game_state.is_paused = !game_state.is_paused
	if game_state.is_paused:
		pause_menu.open()
		mobile_support.hide_keyboard()
		if typing_controller: typing_controller.reset()
		if is_instance_valid(pause_button):
			pause_button.modulate = Color(1.0, 0.85, 0.4)
		if is_instance_valid(_pause_status_dot):
			_pause_status_dot.color = Color(1.0, 0.84, 0.0)
	else:
		pause_menu.close()
		if is_instance_valid(pause_button):
			pause_button.modulate = Color.WHITE
		if is_instance_valid(_pause_status_dot):
			_pause_status_dot.color = Color(0.3, 0.9, 0.4)
	if music_snd:
		music_snd.stream_paused = game_state.is_paused

func _on_resume_pressed() -> void:
	game_state.is_paused = false
	pause_menu.close()
	if is_instance_valid(pause_button):
		pause_button.modulate = Color.WHITE
	if is_instance_valid(_pause_status_dot):
		_pause_status_dot.color = Color(0.3, 0.9, 0.4)
	if music_snd:
		music_snd.stream_paused = false

func _on_pause_restart_pressed() -> void:
	pause_menu.close()
	game_state.is_paused = false
	_start_game()

## Both the pause menu's "Quit" and the game-over screen's "Quit" now return
## the player to the main/difficulty menu instead of calling get_tree().quit().
## get_tree().quit() terminates the whole application/process, which on web
## export just halts the SceneTree (no way to "close a tab" from inside the
## page) and in the Godot editor stops the running instance and kicks focus
## back to the editor -- neither of which is "return to the main menu".
## Fires whenever GameState.ui_style_changed does (i.e. the player just
## picked Casual or Jelly in More > Settings). Every major screen in this
## game is built ONCE at boot and reused for the rest of the session
## (open()/close() only toggle visibility - they never rebuild), so
## without this the Interface Style setting would only ever take effect
## on the next full app relaunch. Each screen's own refresh_theme()
## rebuilds just that screen's buttons/panels in place; this just fans
## the change out to everything so the whole app re-skins together and
## instantly, not screen-by-screen as the player happens to revisit them.
func _on_ui_style_changed(_new_style: String) -> void:
	if is_instance_valid(pause_menu): pause_menu.refresh_theme()
	if is_instance_valid(stats_screen): stats_screen.refresh_theme()
	if is_instance_valid(difficulty_menu): difficulty_menu.refresh_theme()
	if is_instance_valid(missions_screen): missions_screen.refresh_theme()
	if is_instance_valid(career_screen): career_screen.refresh_theme()
	if is_instance_valid(achievements_screen): achievements_screen.refresh_theme()
	if is_instance_valid(sentence_mode_screen): sentence_mode_screen.refresh_theme()
	if is_instance_valid(ui_hud): ui_hud.refresh_theme()
	# more_screen rebuilds its own currently-open Settings panel itself,
	# at the point of selection - see more_screen.gd.

func _on_quit_to_menu() -> void:
	game_state.running = false
	game_state.is_paused = false
	is_transitioning = false

	pause_menu.close()
	result_panel.visible = false
	pause_button.visible = false

	if is_instance_valid(pause_button):
		pause_button.modulate = Color.WHITE
	if is_instance_valid(_pause_status_dot):
		_pause_status_dot.color = Color(0.3, 0.9, 0.4)
	if music_snd:
		music_snd.stream_paused = false

	mobile_support.hide_keyboard()
	if typing_controller: typing_controller.reset()
	word_manager.clear_words()

	if audio.has_method("stop_all_music"):
		audio.stop_all_music()

	difficulty_menu.open()
	audio.play_menu_music()

func _on_tutorial_finished() -> void:
	difficulty_menu.open()
	# By this point the player has tapped NEXT/SKIP/GOT IT at least once,
	# so _input() should already have set _audio_unlocked — but fall back
	# to the pending-music flag just in case, same as the tutorial_seen path.
	if _audio_unlocked:
		audio.play_menu_music()
	else:
		_pending_menu_music = true

func _on_difficulty_start(_theme: String, _difficulty: String, _weak: bool) -> void:
	audio.play_ui_click()
	career_manager.exit_career_mode()
	_start_game()

func _on_career_rank_selected(rank: int) -> void:
	if career_manager.select_rank(rank):
		difficulty_menu.close()
		_start_game()

func _start_game() -> void:
	word_manager.clear_words()
	powerup_system.reset()
	spawn_timer = 0.0
	base_fall_speed = 40.0
	career_fall_speed_bonus = career_manager.get_fall_speed_bonus() if is_instance_valid(career_manager) else 0.0
	is_transitioning = false
	result_panel.visible = false
	pause_button.visible = true
	pause_menu.close()
	# A round could previously start underneath the Replay Tutorial overlay
	# or the Missions screen if either was left open when Play was tapped -
	# the game would be running but hidden behind them until the player
	# manually closed the overlay. Force-close anything that could still be
	# stacked on top before a run actually begins.
	if is_instance_valid(tutorial_overlay) and tutorial_overlay.visible:
		tutorial_overlay.close()
	if is_instance_valid(missions_screen) and missions_screen.visible:
		missions_screen.close()
	if is_instance_valid(more_screen) and more_screen.visible:
		more_screen.close()
	if is_instance_valid(career_screen) and career_screen.visible:
		career_screen.close()
	if is_instance_valid(achievements_screen) and achievements_screen.visible:
		achievements_screen.close()
	if is_instance_valid(sentence_mode_screen) and sentence_mode_screen.visible:
		sentence_mode_screen.close()
	if is_instance_valid(dictation_screen) and dictation_screen.visible:
		dictation_screen.close()
	ui_hud.set_target_bg(ui_hud.bg_themes[0])
	input_box.clear()
	input_box.grab_focus()
	if typing_controller: typing_controller.reset()
	audio.start_gameplay_music()

	level_grace_timer = level_grace_duration
	miss_streak = 0
	total_words_spawned = 0
	total_words_typed = 0
	run_start_msec = Time.get_ticks_msec()
	current_level_had_miss = false
	milestones_hit.clear()
	frenzy_warned = false
	highest_combo_this_run = 0
	total_run_misses = 0
	streak_bonuses_hit.clear()
	streak_relief_timer = 0.0
	streak_relief_factor = 1.0
	streak_relief_tier = 0

	game_state.start_run()
	AnalyticsManager.log_event("run_started", {
		"difficulty": game_state.selected_difficulty,
		"theme": game_state.selected_theme,
		"career_mode": game_state.career_mode_active,
	})

func _process(delta: float) -> void:
	var pulse_val = 1.0 + (sin(Time.get_ticks_msec() * 0.005) * 0.05)
	
	if is_instance_valid(restart_button) and restart_button:
		restart_button.scale = Vector2(pulse_val, pulse_val)
		
	if is_instance_valid(pause_button) and pause_button:
		pause_button.scale = Vector2(pulse_val, pulse_val)
		
	if ui_hud:
		ui_hud.per_frame_tween(delta)
		
	if not game_state.running or game_state.is_paused or (pause_menu and pause_menu.visible) or (is_instance_valid(tutorial_overlay) and tutorial_overlay.visible):
		return

	if ai_enabled and word_manager.active_words.size() > 0:
		ai_timer += delta
		if ai_timer >= ai_speed:
			ai_timer = 0
			var target = word_manager.active_words[0]
			if is_instance_valid(target):
				ui_hud.spawn_floating_text("AI TYPED", Vector2(576, 250), Color.CYAN)
				_on_word_matched(target)

	if is_transitioning:
		return

	if game_state.combo > highest_combo_this_run:
		highest_combo_this_run = game_state.combo

	for milestone in milestone_combos:
		if game_state.combo == milestone and not milestones_hit.get(milestone, false):
			milestones_hit[milestone] = true
			ui_hud.spawn_floating_text(str(milestone) + " COMBO!", Vector2(get_viewport_rect().size.x / 2, 150), Color.GOLD)

	for i in streak_bonus_tiers.size():                                    # 21
		var tier_combo: int = streak_bonus_tiers[i]
		if game_state.combo == tier_combo and not streak_bonuses_hit.get(tier_combo, false):
			streak_bonuses_hit[tier_combo] = true
			_apply_streak_bonus(i + 1, tier_combo)

	if streak_relief_timer > 0.0:                                          # 21
		streak_relief_timer -= delta
		if streak_relief_timer <= 0.0:
			streak_relief_timer = 0.0
			streak_relief_factor = 1.0
			streak_relief_tier = 0

	var frenzy_threshold = clamp(60 - (game_state.level - 1) * 2, 30, 60)

	if game_state.combo >= frenzy_threshold and not game_state.frenzy_mode:
		game_state.frenzy_mode = true
		frenzy_warned = false
		ui_hud.set_target_bg(Color.MAGENTA)
		ui_hud.spawn_floating_text("FRENZY!", Vector2(get_viewport_rect().size.x / 2, 200), Color.HOT_PINK, 1.6)
		audio.play_powerup()
	elif game_state.combo < frenzy_threshold and game_state.frenzy_mode:
		game_state.frenzy_mode = false
		frenzy_warned = false
		ui_hud.set_target_bg(ui_hud.theme_for_level(game_state.level))
	elif game_state.frenzy_mode and game_state.combo <= frenzy_threshold + 5 and not frenzy_warned:
		frenzy_warned = true
		ui_hud.spawn_floating_text("Frenzy fading...", Vector2(get_viewport_rect().size.x / 2, 230), Color.LIGHT_PINK)

	powerup_system.process(delta)
	if powerup_system.is_frozen:
		ui_hud.apply_freeze_overlay(delta)
		return
	else:
		ui_hud.clear_freeze_overlay(delta)

	game_state.tick(delta)
	if not game_state.running:
		return

	base_fall_speed = clamp(40.0 + (game_state.level - 1) * 18.0 + career_fall_speed_bonus, 40.0, max_fall_speed_cap)
	if streak_relief_timer > 0.0:                                          # 21
		base_fall_speed *= streak_relief_factor

	var grace_active = level_grace_timer > 0.0
	if grace_active:
		level_grace_timer -= delta
		base_fall_speed *= 0.6

	frenzy_rate_target = 2.4 if game_state.frenzy_mode else 1.0
	frenzy_rate_smoothed = move_toward(frenzy_rate_smoothed, frenzy_rate_target, delta * frenzy_rate_ramp_speed)

	spawn_timer -= delta * powerup_system.slow_mo_factor
	if spawn_timer <= 0:
		var spawned_label := word_manager.spawn_word(game_state.level)
		total_words_spawned += 1

		# SURPRISE: "Lucky Word" - roughly 1 in 10 ordinary words spawns
		# gold-tinted instead. Catching it pays a bonus (see _on_word_matched).
		# Kept out of word_manager.gd entirely - just a meta tag + a color
		# swap on the label it already handed back, so it can't interfere
		# with the existing powerup selection logic.
		if is_instance_valid(spawned_label) \
				and not (spawned_label.has_meta("is_powerup") and spawned_label.get_meta("is_powerup")) \
				and randf() < 0.10:
			spawned_label.set_meta("is_lucky", true)
			spawned_label.modulate = Color(1.0, 0.85, 0.15)

		var base_delay = 3.2 - ((game_state.level - 1) * 0.32)
		var target_delay = max(min_spawn_delay_cap, base_delay)

		if miss_streak >= 3:
			target_delay += 0.4

		if grace_active:
			target_delay += 0.5

		target_delay *= adaptive_difficulty.get_delay_multiplier()

		# Frenzy speeds things up by dividing the delay, same as before, but
		# now ramped (frenzy_rate_smoothed) instead of an instant flip, and
		# floored so it can't stack with a high level into something that
		# outpaces what's actually catchable.
		target_delay /= frenzy_rate_smoothed
		if game_state.frenzy_mode:
			target_delay = max(target_delay, min_frenzy_spawn_delay_cap)

		spawn_timer = target_delay

	word_manager.update_positions(delta, base_fall_speed, game_state.score, powerup_system.slow_mo_factor, get_viewport_rect().size.y)

## 21. Combo streak bonus: tier 1 (10-combo), tier 2 (25-combo), tier 3
## (50-combo). Each tier escalates score reward, fall-speed relief duration/
## strength, and the visual payoff (color, particles, screen flash, shake).
func _apply_streak_bonus(tier: int, combo_count: int) -> void:
	var bonus_score := 25 * tier * tier                 # 25, 100, 225
	var relief_seconds := 3.0 + (tier - 1) * 2.5         # 3s, 5.5s, 8s
	var relief_factor := 1.0 - (tier * 0.12)             # 0.88, 0.76, 0.64 (slower fall)
	var tier_colors := [Color.GOLD, Color.CYAN, Color.MAGENTA]
	var col: Color = tier_colors[clamp(tier - 1, 0, tier_colors.size() - 1)]

	game_state.score += bonus_score
	game_state.score_changed.emit(game_state.score)
	game_state.register_streak_bonus()
	if is_instance_valid(mission_manager):
		var newly: Array = mission_manager.evaluate_streak_bonus()
		if not newly.is_empty():
			var texts: Array = []
			for m in newly:
				texts.append(String(m.get("text", "")))
			ui_hud.spawn_floating_text("MISSION: " + ", ".join(texts), Vector2(get_viewport_rect().size.x / 2, 100), Color.GOLD)

	streak_relief_timer = relief_seconds
	streak_relief_factor = relief_factor
	streak_relief_tier = tier

	var vp_center := Vector2(get_viewport_rect().size.x / 2, 150 - tier * 25)
	ui_hud.spawn_floating_text("%dx STREAK! +%d SCORE" % [combo_count, bonus_score], vp_center, col)
	ui_hud.spawn_particles(vp_center, col)
	if tier >= 2:
		ui_hud.flash_background_gold()
	if tier >= 3 and not game_state.reduced_motion:
		ui_hud.shake(10.0)
	audio.play_level_up_sting()

## Cosmetics Shop payoff: looks up the player's selected accent color for
## the ordinary "+10" catch text. Falls back to the original yellow if
## nothing is selected or the shop's option table doesn't have an entry
## for it (e.g. an older save file), so this can never break the catch
## feedback even if the cosmetic id is unrecognized.
func _cosmetic_catch_color() -> Color:
	var chosen: String = game_state.selected_cosmetic
	if MoreScreen.COSMETIC_OPTIONS.has(chosen):
		return MoreScreen.COSMETIC_OPTIONS[chosen]["color"]
	return Color.YELLOW

func _on_word_matched(label: Label) -> void:
	if not is_instance_valid(label):
		return
	word_manager.remove_word(label)
	var word_text = String(label.get_meta("word"))
	var is_powerup = label.has_meta("is_powerup") and label.get_meta("is_powerup")
	var is_lucky = label.has_meta("is_lucky") and label.get_meta("is_lucky")

	var result = game_state.register_hit(word_text)

	miss_streak = 0
	total_words_typed += 1

	if is_powerup:
		var kind = label.get_meta("powerup_type")
		powerup_system.activate(kind)
		audio.play_powerup()
		ui_hud.spawn_floating_text(word_text + "!", label.position, Color.SKY_BLUE)
	elif is_lucky:
		# SURPRISE payoff: flat score bonus + extra sparkle/flash/sting so it
		# reads as a little jackpot moment rather than a normal catch.
		game_state.score += 50
		game_state.score_changed.emit(game_state.score)
		ui_hud.spawn_floating_text("\u2728 LUCKY! +50", label.position, Color(1.0, 0.85, 0.15))
		ui_hud.flash_background_gold()
		audio.play_level_up_sting()
	else:
		audio.play_success(game_state.combo)
		ui_hud.spawn_floating_text("+10", label.position, _cosmetic_catch_color(), 1.0 + clamp(game_state.combo * 0.02, 0.0, 0.5))
		# SURPRISE: about 1 in 80 ordinary catches also sets off the rainbow
		# flourish, purely for delight, plus a tiny bonus to make it count.
		if is_instance_valid(rainbow_surprise) and randf() < 0.0125:
			rainbow_surprise.trigger()
			game_state.score += 15
			game_state.score_changed.emit(game_state.score)

	ui_hud.spawn_particles(label.position, label.modulate)
	ui_hud.spawn_ghost(label)

	if result.get("bonus_time", false):
		game_state.add_bonus_time(30.0)
		ui_hud.flash_background_gold()

	label.queue_free()

	if result.get("leveled_up", false):
		_run_level_up_transition()

func _run_level_up_transition() -> void:
	is_transitioning = true
	audio.play_level_up_sting()
	word_manager.clear_words()
	await ui_hud.show_level_up_intermission(game_state.level)
	is_transitioning = false

func _on_word_missed(label: Label) -> void:
	if not is_instance_valid(label):
		return
	var word_text = String(label.get_meta("word"))
	var lost_life = game_state.register_miss(word_text)
	if lost_life:
		miss_streak += 1
		total_run_misses += 1
		current_level_had_miss = true
		milestones_hit.clear()
		streak_bonuses_hit.clear()
		streak_relief_timer = 0.0
		streak_relief_factor = 1.0
		streak_relief_tier = 0
		if not game_state.reduced_motion:
			ui_hud.shake(20.0)
		audio.play_error()
		mobile_support.vibrate(200)
		ui_hud.spawn_floating_text("MISS", label.position, Color.RED)
	else:
		ui_hud.spawn_floating_text("SHIELD BROKEN", label.position, Color.WHITE)
	label.queue_free()

func _on_input_invalid() -> void:
	input_box.modulate = Color.RED
	create_tween().tween_property(input_box, "modulate", Color.WHITE, 0.2)

func _on_level_up(new_level: int) -> void:
	if new_level > 1 and not current_level_had_miss:
		game_state.add_bonus_time(10.0)
		ui_hud.spawn_floating_text("PERFECT LEVEL! +10s", Vector2(get_viewport_rect().size.x / 2, 260), Color.GOLD)
	current_level_had_miss = false

	level_grace_timer = level_grace_duration

	var tier_index = clamp(new_level - 1, 0, difficulty_tier_names.size() - 1)
	ui_hud.spawn_floating_text(difficulty_tier_names[tier_index], Vector2(get_viewport_rect().size.x / 2, 320), Color.ORANGE)

func _on_music_finished() -> void:
	if game_state.running and game_state.lives > 0:
		game_state.end_run(true)

func _on_game_ended(did_win: bool) -> void:
	pause_button.visible = false
	mobile_support.hide_keyboard()
	if audio.has_method("stop_all_music"):
		audio.stop_all_music()
	if did_win:
		stats_screen.show_win()
	else:
		stats_screen.show_game_over()
		audio.play_game_over_voice()

	AnalyticsManager.log_event("run_ended", {
		"did_win": did_win,
		"score": game_state.score,
		"wpm": game_state.get_wpm(),
		"accuracy": game_state.get_accuracy(),
	})

	if monetization.should_show_ads(game_state):
		monetization.show_interstitial()
		AnalyticsManager.log_event("interstitial_shown", {})

	var newly_completed := mission_manager.evaluate_run_end(did_win)
	if newly_completed.size() > 0:
		audio.play_notification()
	for i in newly_completed.size():
		ui_hud.show_toast("MISSION COMPLETE: " + newly_completed[i].text, i)

	if game_state.career_mode_active:
		var career_result := career_manager.check_rank_progress()
		if career_result.rank_up:
			audio.play_notification()
			career_screen.show_rank_up(career_result.new_rank, career_result.title)
		elif career_result.climb_complete:
			audio.play_notification()
			career_screen.show_climb_complete()

func _on_restart_pressed() -> void:
	result_panel.visible = false
	ai_timer = 0.0
	is_transitioning = false
	await get_tree().process_frame
	_start_game()
	game_state.is_paused = false
	game_state.running = true

func _on_menu_pressed() -> void:
	result_panel.visible = false
	if typing_controller: typing_controller.reset()
	difficulty_menu.open()
	audio.play_menu_music()

func _on_score_view_pressed() -> void:
	if game_state.high_scores.size() == 0:
		return
	var best_text = "BEST: " + str(game_state.high_scores[0])
	if game_state.high_scores.size() > 1:
		best_text += "   2ND: " + str(game_state.high_scores[1])
	ui_hud.spawn_floating_text(best_text, Vector2(get_viewport_rect().size.x / 2, 400), Color.CYAN)

func _input(event: InputEvent) -> void:
	if not _audio_unlocked and (event is InputEventScreenTouch or event is InputEventMouseButton or event is InputEventKey):
		_audio_unlocked = true
		if _pending_menu_music:
			_pending_menu_music = false
			audio.play_menu_music()

	if event is InputEventScreenTouch and event.pressed:
		if not result_panel.visible and not pause_menu.visible and not difficulty_menu.visible and not tutorial_overlay.visible and not (is_instance_valid(career_screen) and career_screen.visible) and not (is_instance_valid(achievements_screen) and achievements_screen.visible) and not (is_instance_valid(sentence_mode_screen) and sentence_mode_screen.visible) and not (is_instance_valid(dictation_screen) and dictation_screen.visible) and not (is_instance_valid(more_screen) and more_screen.visible) and not (is_instance_valid(missions_screen) and missions_screen.visible):
			if not input_box.has_focus():
				input_box.grab_focus()
				mobile_support.show_keyboard()
		else:
			# Deferred so this runs AFTER the same tap has already been
			# through Control's own click/focus handling - otherwise a tap
			# that's focusing a LineEdit inside an overlay (e.g. the login
			# screen's email/password fields, the backup-code box, the
			# playlist-name box) gets its keyboard hidden by this call
			# before it ever has a chance to show, since this hide fires
			# first in Godot's input order. Skipping the hide whenever
			# focus is (or is about to remain) on a text field lets those
			# overlay text fields manage their own keyboard visibility.
			call_deferred("_maybe_hide_keyboard")

func _on_back_pressed() -> void:
	if is_instance_valid(missions_screen) and missions_screen.visible:
		missions_screen.close()
		return
	if is_instance_valid(career_screen) and career_screen.visible:
		career_screen.close()
		return
	if is_instance_valid(achievements_screen) and achievements_screen.visible:
		achievements_screen.close()
		return
	if is_instance_valid(sentence_mode_screen) and sentence_mode_screen.visible:
		sentence_mode_screen.close()
		return
	if is_instance_valid(dictation_screen) and dictation_screen.visible:
		dictation_screen.close()
		return
	if is_instance_valid(more_screen) and more_screen.visible:
		more_screen.close()
		return
	if pause_menu.visible or difficulty_menu.visible or tutorial_overlay.visible or result_panel.visible or (is_instance_valid(career_screen) and career_screen.visible):
		return
	if game_state.running:
		_toggle_pause()

func _on_app_focus_lost() -> void:
	mobile_support.hide_keyboard()
	if game_state.running and not game_state.is_paused:
		_toggle_pause()

func _on_viewport_resized() -> void:
	if not is_instance_valid(input_box):
		return
	if mobile_support.is_touch:
		input_box.position.y = get_viewport_rect().size.y * 0.55 - _bottom_safe_area_inset()
	else:
		input_box.position.y = get_viewport_rect().size.y - 120
	original_input_pos_y = input_box.position.y

# --- PORTRAIT COMFORT EXTRA -------------------------------------------------
# Modern phones in portrait reserve a strip at the bottom of the physical
# screen for the gesture-nav bar / home indicator, which isn't part of
# DisplayServer's "safe area". On phones with 3-button nav disabled (the
# common default), that strip can sit right where the 0.55-height input box
# lands, so the OS gesture bar visually crowds the typing field. This nudges
# the input box up by however much of the real screen is outside the safe
# area at the bottom, converted into the game's own viewport units. It's a
# no-op (returns 0.0) on desktop, in the editor, and on any phone that
# doesn't report a safe-area inset, so it can only ever move the box up,
# never break existing layouts.
func _bottom_safe_area_inset() -> float:
	if not mobile_support.is_touch:
		return 0.0
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	if screen_size.y <= 0:
		return 0.0
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	var bottom_gap_px: float = float(screen_size.y - (safe_area.position.y + safe_area.size.y))
	if bottom_gap_px <= 0.0:
		return 0.0
	var viewport_h: float = get_viewport_rect().size.y
	var scale: float = viewport_h / float(screen_size.y)
	# Cap the nudge so a misreported inset can't shove the box somewhere silly.
	return clamp(bottom_gap_px * scale, 0.0, viewport_h * 0.08)

func _maybe_hide_keyboard() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	mobile_support.hide_keyboard()
