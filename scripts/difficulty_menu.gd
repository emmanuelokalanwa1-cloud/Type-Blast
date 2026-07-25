class_name DifficultyMenu
extends ColorRect

signal start_pressed(theme: String, difficulty: String, weak_keys_mode: bool)
signal missions_pressed()
signal career_pressed()
signal achievements_pressed()
signal sentence_mode_pressed()
signal more_pressed()
signal more_shortcut_pressed(view_id: String)

const DIFFICULTIES := ["Short", "Medium", "Long", "Mixed"]
# Maps each canonical (English, save-file-stable) difficulty value to its
# locale key, so the dropdown can show a translated label while the value
# written to GameState / emitted to gameplay never changes with language.
const DIFFICULTY_LOC_KEYS := {"Short": "short", "Medium": "medium", "Long": "long", "Mixed": "mixed"}

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MINT := Color(0.4, 0.9, 0.75)
const COL_MUTE := Color(1, 1, 1, 0.68)
const COL_AMBER := Color(0.95, 0.6, 0.25)
const COL_SKY := Color(0.45, 0.7, 0.95)

var _game_state: GameState
var _theme_option: OptionButton
var _difficulty_option: OptionButton
var _weak_keys_check: CheckButton
var _start_btn: Button
var _backdrop_nodes: Array = []
var _streak_label: Label
var _unlock_label: Label
var _unlock_bar: ProgressBar

# --- FIFA-style nav list state ---------------------------------------
var _nav_list: VBoxContainer
var _flyout_panel: Control
var _flyout_card: PanelContainer
var _more_flyout_card: PanelContainer
var _nav_buttons: Dictionary = {}       # id -> Button
var _nav_widths: Dictionary = {}        # id -> float (base row width)
var _active_nav_id: String = "start"
var _theme_keep_child_count := 0  # children added before the first _build_ui() call (backdrop, scrim), preserved across refresh_theme()

# id -> {label_key, tint, has_flyout}
const NAV_ITEMS := [
	{"id": "start", "label_key": "start_run", "tint": Color(0.55, 0.95, 0.55), "has_flyout": true},
	{"id": "career", "label_key": "career_mode", "tint": COL_MINT, "has_flyout": false},
	{"id": "missions", "label_key": "missions", "tint": COL_GOLD, "has_flyout": false},
	{"id": "achievements", "label_key": "achievements", "tint": COL_AMBER, "has_flyout": false},
	{"id": "sentence", "label_key": "sentence_mode", "tint": COL_SKY, "has_flyout": false},
	{"id": "more", "label_key": "more", "tint": COL_MUTE, "has_flyout": true},
]

# Quick-access shortcuts shown in the MORE flyout - the FIFA equivalent of
# "Kick-Off - Team / Be a Pro / Be a Keeper". These jump straight into a
# panel inside MoreScreen instead of landing on its hub list first. The
# full hub (all ~15 entries) still lives behind "ALL FEATURES" at the
# bottom, since that's too much to cram into a cascading flyout.
## Flip this to true, export a build, hand it to playtesters. It hides every
## nav button except "Start Run" (career/missions/achievements/sentence/
## more all disappear) so the only thing reachable is: theme+difficulty
## picker -> the falling-word loop -> stats screen. Flip back to false for
## a normal build. Nothing else in the file changes behavior when this is
## false - existing saves, screens, and signals are untouched either way.
const TEST_CORE_LOOP_ONLY := false

static func _visible_nav_items() -> Array:
	if TEST_CORE_LOOP_ONLY:
		return NAV_ITEMS.filter(func(item): return item["id"] == "start")
	return NAV_ITEMS

const MORE_SHORTCUTS := [
	{"label": "\u270f  PRACTICE MODES", "view": "practice_menu", "tint": COL_MINT},
	{"label": "\u2696  BADGES", "view": "badges", "tint": COL_AMBER},
	{"label": "\ud83c\udfc6  LEADERBOARD", "view": "leaderboard", "tint": COL_GOLD},
	{"label": "\u2699  SETTINGS", "view": "settings", "tint": COL_MUTE},
	{"label": "\u2139  CREDITS", "view": "credits", "tint": COL_SKY},
]


func setup(root: Control, game_state: GameState) -> void:
	_game_state = game_state
	color = Color(0.015, 0.016, 0.03, 1.0)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(self)
	_backdrop_nodes = BackgroundThemes.build(self, BackgroundThemes.current_index)
	_build_scrim()
	_theme_keep_child_count = get_child_count()
	_build_ui()

## Re-runs _build_ui() so the main menu (nav list, Start Run card, streak/
## unlock widgets, all its buttons) picks up a new Casual/Jelly interface
## style immediately. This is the screen players are looking at right when
## they change the setting in More > Settings, so it's the one that most
## needed to stop waiting for "next time this screen opens".
func refresh_theme() -> void:
	JellyTheme.trim_rebuildable_children(self, _theme_keep_child_count)
	_active_nav_id = "start"
	_build_ui()
	JellyTheme.play_rebuild_transition(self)


# Swaps in the next of the 4 rotating space backdrops. Called once at
# startup and again every time the menu is (re)opened, so returning here
# after a run visibly changes the scenery instead of it staying static.
func _refresh_backdrop() -> void:
	BackgroundThemes.free_nodes(_backdrop_nodes)
	_backdrop_nodes = BackgroundThemes.build(self, BackgroundThemes.current_index)
	move_child(_backdrop_nodes[0], 0)


func _refresh_progress_widgets() -> void:
	_apply_streak_warning()
	_apply_unlock_progress()


# Streak warning - gentle, not guilt-trippy, and only shows up if today
# genuinely isn't covered yet (update_streak() only fires when a run or
# practice session actually finishes, so this can't be fooled by just
# opening the app).
func _apply_streak_warning() -> void:
	if not is_instance_valid(_streak_label):
		return
	_streak_label.visible = false
	if not is_instance_valid(_game_state) or _game_state.current_streak <= 0:
		return
	var today := Time.get_date_string_from_system()
	if _game_state.last_play_date == today:
		return # already played today - streak is safe, nothing to warn about
	var hour = int(Time.get_time_dict_from_system().get("hour", 12))
	var plural_suffix = "one" if _game_state.current_streak == 1 else "other"
	if hour >= 18:
		var key = "streak_ends_tonight_%s" % plural_suffix
		_streak_label.text = LocalizationManager.get_string(key, _game_state.selected_language) % _game_state.current_streak
		_streak_label.modulate = COL_AMBER
	else:
		var key2 = "streak_active_%s" % plural_suffix
		_streak_label.text = LocalizationManager.get_string(key2, _game_state.selected_language) % _game_state.current_streak
		_streak_label.modulate = COL_MINT
	_streak_label.visible = true


# Next-unlock progress - always visible so there's always something one
# glance away, without needing to dig into the MORE hub for it.
func _apply_unlock_progress() -> void:
	if not is_instance_valid(_unlock_label) or not is_instance_valid(_unlock_bar):
		return
	var info = BadgesManager.nearest_locked_progress(_game_state)
	if info == null:
		_unlock_label.visible = false
		_unlock_bar.visible = false
		return
	_unlock_label.text = LocalizationManager.get_string("next_unlock", _game_state.selected_language) % [info.icon, info.name, int(info.progress * 100)]
	_unlock_label.visible = true
	_unlock_bar.value = info.progress * 100
	_unlock_bar.visible = true


# Directional scrim: darker on the left where the nav list sits (for text
# legibility over the starfield), fading out toward the right so the
# backdrop art stays visible behind the flyout - same job the FIFA menu's
# gradient does behind its list.
func _build_scrim() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	float left_fade = 1.0 - smoothstep(0.0, 0.78, UV.x);
	float bottom_fade = smoothstep(0.62, 1.0, UV.y);
	float top_fade = 1.0 - smoothstep(0.0, 0.16, UV.y);
	float a = clamp(max(left_fade * 0.72, max(bottom_fade * 0.55, top_fade * 0.5)), 0.0, 0.85);
	COLOR = vec4(0.015, 0.016, 0.03, a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	scrim.material = mat
	add_child(scrim)


func _build_ui() -> void:
	# This project's real viewport is 720x1280 (portrait — see project.godot).
	var vp = get_viewport_rect().size
	var side_margin = int(clamp(vp.x * 0.045, 14, 50))
	var top_margin = int(clamp(vp.y * 0.03, 16, 46))

	var root_margin := MarginContainer.new()
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", side_margin)
	root_margin.add_theme_constant_override("margin_right", side_margin)
	root_margin.add_theme_constant_override("margin_top", top_margin)
	root_margin.add_theme_constant_override("margin_bottom", int(top_margin * 0.7))
	add_child(root_margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(clamp(vp.y * 0.014, 8, 18)))
	root_margin.add_child(outer)

	_build_header(outer, vp)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1)
	divider.color = Color(1, 1, 1, 0.1)
	outer.add_child(divider)

	# --- Body: nav list (left) + flyout (right), FIFA-style ------------
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	_nav_list = VBoxContainer.new()
	_nav_list.add_theme_constant_override("separation", int(clamp(vp.y * 0.014, 8, 16)))
	_nav_list.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_nav_list.anchor_bottom = 1.0
	_nav_list.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(_nav_list)

	_flyout_panel = Control.new()
	_flyout_panel.anchor_left = 0.5
	_flyout_panel.anchor_right = 1.0
	_flyout_panel.anchor_top = 0.0
	_flyout_panel.anchor_bottom = 1.0
	_flyout_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(_flyout_panel)

	var nav_base_width = vp.x * 0.5
	for item in _visible_nav_items():
		var row := _build_nav_row(item, nav_base_width)
		_nav_list.add_child(row)

	_build_flyout(vp)
	if not TEST_CORE_LOOP_ONLY:
		_build_more_flyout(vp)
	_set_active_nav("start", false)


func _build_header(outer: VBoxContainer, vp: Vector2) -> void:
	var title_size = int(clamp(vp.x * 0.058, 22, 40))
	var title = Label.new()
	title.text = LocalizationManager.get_string("choose_your_run", _game_state.selected_language).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_size_override("font_size", title_size)
	title.modulate = COL_MINT
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	outer.add_child(title)

	var quote_label = Label.new()
	var date_seed = int(Time.get_date_string_from_system().replace("-", ""))
	quote_label.text = "\u201c" + QuotesManager.quote_of_the_day(date_seed) + "\u201d"
	quote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	quote_label.add_theme_font_size_override("font_size", 13)
	quote_label.modulate = COL_GOLD
	outer.add_child(quote_label)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 18)
	outer.add_child(status_row)

	var streak_label = Label.new()
	streak_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	streak_label.custom_minimum_size = Vector2(130, 0)
	streak_label.add_theme_font_size_override("font_size", 13)
	streak_label.visible = false
	status_row.add_child(streak_label)
	_streak_label = streak_label

	var unlock_col := VBoxContainer.new()
	unlock_col.add_theme_constant_override("separation", 3)
	unlock_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(unlock_col)

	var unlock_label = Label.new()
	unlock_label.add_theme_font_size_override("font_size", 12)
	unlock_label.modulate = COL_AMBER
	unlock_label.visible = false
	unlock_col.add_child(unlock_label)
	_unlock_label = unlock_label

	var unlock_bar = ProgressBar.new()
	unlock_bar.min_value = 0
	unlock_bar.max_value = 100
	unlock_bar.show_percentage = false
	unlock_bar.custom_minimum_size = Vector2(0, 6)
	unlock_bar.visible = false
	unlock_col.add_child(unlock_bar)
	_unlock_bar = unlock_bar

	_refresh_progress_widgets()


# One FIFA-style bar: text-only, left-anchored, rounded only on the right
# edge (so it visually bleeds off the left of the screen like the KICK-OFF
# / CAREER MODE / GAME MODES stack). The active row brightens, grows wider,
# and gets a trailing chevron; everything else stays a dim flat bar.
func _build_nav_row(item: Dictionary, base_width: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(base_width, 0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.clip_text = false
	b.add_theme_font_size_override("font_size", 20)
	# Row padding is baked into the stylebox content margins rather than a
	# wrapper container - see _nav_bar_style below.

	_nav_buttons[item["id"]] = b
	_nav_widths[item["id"]] = base_width
	_apply_nav_row_visuals(b, item, false)

	b.pressed.connect(func(): _on_nav_pressed(item["id"]))
	# FIFA-style preview: sliding a cursor/finger onto a row (without
	# committing to a press) already reveals its flyout there, same as
	# resting on KICK-OFF shows its sub-buttons before you confirm. Touch
	# presses trigger _on_nav_pressed anyway, so this mainly matters for
	# mouse/controller input, but it's harmless either way.
	b.mouse_entered.connect(func(): _set_active_nav(item["id"]))
	return b


func _apply_nav_row_visuals(b: Button, item: Dictionary, active: bool) -> void:
	var tint: Color = item["tint"]
	var label = LocalizationManager.get_string(item["label_key"], _game_state.selected_language).to_upper()
	if active and item["has_flyout"]:
		label += "   \u25B6"
	b.text = label

	var normal := _nav_bar_style(tint, active)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", _nav_bar_style(tint, active, true))
	b.add_theme_stylebox_override("pressed", _nav_bar_style(tint, active, true))
	b.add_theme_stylebox_override("focus", normal)

	if active:
		b.add_theme_color_override("font_color", Color(0.06, 0.07, 0.06))
		b.add_theme_color_override("font_hover_color", Color(0.06, 0.07, 0.06))
		b.add_theme_color_override("font_pressed_color", Color(0.06, 0.07, 0.06))
	else:
		b.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))


func _nav_bar_style(tint: Color, active: bool, hovered: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if active:
		sb.bg_color = tint if not hovered else tint.lightened(0.1)
	else:
		sb.bg_color = Color(1, 1, 1, 0.14) if hovered else Color(1, 1, 1, 0.07)
	sb.border_width_left = 6
	sb.border_color = tint if active else Color(tint.r, tint.g, tint.b, 0.5)
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_right = 16
	sb.content_margin_left = 22
	sb.content_margin_right = 18
	sb.content_margin_top = 15
	sb.content_margin_bottom = 15
	sb.shadow_size = 8 if active else 0
	sb.shadow_color = Color(0, 0, 0, 0.35)
	return sb


func _on_nav_pressed(id: String) -> void:
	_set_active_nav(id)
	match id:
		"career":
			career_pressed.emit()
		"missions":
			missions_pressed.emit()
		"achievements":
			achievements_pressed.emit()
		"sentence":
			sentence_mode_pressed.emit()
		# "start" and "more" open a flyout instead of navigating immediately -
		# the actual run / MORE panel only opens once something inside the
		# flyout is pressed (see _build_flyout / _build_more_flyout).


func _set_active_nav(id: String, animate: bool = true) -> void:
	_active_nav_id = id
	for item in _visible_nav_items():
		var is_active = item["id"] == id
		var b: Button = _nav_buttons[item["id"]]
		_apply_nav_row_visuals(b, item, is_active)
		var target_width = _nav_widths[item["id"]] * (1.14 if is_active else 1.0)
		if animate:
			var t := create_tween()
			t.tween_property(b, "custom_minimum_size:x", target_width, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			b.custom_minimum_size.x = target_width

	_show_flyout_card(_flyout_card, id == "start")
	_show_flyout_card(_more_flyout_card, id == "more")


# Shared reveal animation for any cascading flyout card (START's run
# config, MORE's quick-access shortcuts, ...). Only one is ever visible
# at a time since _set_active_nav calls this once per card per row change.
func _show_flyout_card(card: Control, should_show: bool) -> void:
	if not is_instance_valid(card):
		return
	card.visible = should_show
	if should_show:
		card.modulate.a = 0.0
		card.scale = Vector2(0.96, 0.96)
		card.pivot_offset = card.size / 2.0
		var ft := create_tween()
		ft.set_parallel(true)
		ft.tween_property(card, "modulate:a", 1.0, 0.2)
		ft.tween_property(card, "scale", Vector2(1, 1), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Cascading flyout that opens beside the active "START RUN" row - the
# equivalent of FIFA's "Kick-Off Team / Be a Pro / Be a Keeper" stack,
# each step nudged further right than the last.
func _build_flyout(vp: Vector2) -> void:
	_flyout_card = PanelContainer.new()
	_flyout_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_flyout_card.add_theme_stylebox_override("panel", JellyTheme.panel_style("popup"))
	_flyout_panel.add_child(_flyout_card)

	var fly_vbox := VBoxContainer.new()
	fly_vbox.add_theme_constant_override("separation", 14)
	_flyout_card.add_child(fly_vbox)

	fly_vbox.add_child(_cascade_step(0, _labeled(LocalizationManager.get_string("word_set", _game_state.selected_language).to_upper())))
	_theme_option = _styled_option_button()
	for theme_name in WordBank.theme_names():
		_theme_option.add_item(theme_name)
	_select_option(_theme_option, _game_state.selected_theme)
	fly_vbox.add_child(_cascade_step(0, _theme_option))

	fly_vbox.add_child(_cascade_step(1, _labeled(LocalizationManager.get_string("word_length", _game_state.selected_language).to_upper())))
	_difficulty_option = _styled_option_button()
	for d in DIFFICULTIES:
		var label = LocalizationManager.get_string(DIFFICULTY_LOC_KEYS[d], _game_state.selected_language)
		_difficulty_option.add_item(label)
		_difficulty_option.set_item_metadata(_difficulty_option.item_count - 1, d)
	_select_option_by_metadata(_difficulty_option, _game_state.selected_difficulty)
	fly_vbox.add_child(_cascade_step(1, _difficulty_option))

	var toggle_panel := PanelContainer.new()
	var toggle_style := StyleBoxFlat.new()
	toggle_style.bg_color = Color(1, 1, 1, 0.05)
	toggle_style.set_corner_radius_all(14)
	toggle_style.border_width_left = 1
	toggle_style.border_width_right = 1
	toggle_style.border_width_top = 1
	toggle_style.border_width_bottom = 1
	toggle_style.border_color = Color(1, 1, 1, 0.08)
	toggle_style.content_margin_left = 18
	toggle_style.content_margin_right = 18
	toggle_style.content_margin_top = 12
	toggle_style.content_margin_bottom = 12
	toggle_panel.add_theme_stylebox_override("panel", toggle_style)

	var toggle_vbox = VBoxContainer.new()
	toggle_vbox.add_theme_constant_override("separation", 5)
	toggle_panel.add_child(toggle_vbox)

	_weak_keys_check = CheckButton.new()
	_weak_keys_check.text = LocalizationManager.get_string("weak_keys", _game_state.selected_language).to_upper()
	_weak_keys_check.button_pressed = _game_state.weak_keys_mode
	_weak_keys_check.add_theme_font_size_override("font_size", 18)
	toggle_vbox.add_child(_weak_keys_check)

	var hint = Label.new()
	hint.text = LocalizationManager.get_string("weak_keys_hint", _game_state.selected_language)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = COL_MUTE
	toggle_vbox.add_child(hint)

	fly_vbox.add_child(_cascade_step(2, toggle_panel))

	_start_btn = _styled_start_button()
	_start_btn.pressed.connect(_on_start_pressed)
	fly_vbox.add_child(_cascade_step(3, _start_btn))


# MORE's cascading flyout - same staircase pattern as START's, but each
# step is a shortcut straight into a MoreScreen panel instead of a config
# control. "ALL FEATURES" at the end is the escape hatch to the full hub
# for anything not shortcut here.
func _build_more_flyout(vp: Vector2) -> void:
	_more_flyout_card = PanelContainer.new()
	_more_flyout_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_more_flyout_card.add_theme_stylebox_override("panel", JellyTheme.panel_style("popup"))
	_more_flyout_card.visible = false
	_flyout_panel.add_child(_more_flyout_card)

	var fly_vbox := VBoxContainer.new()
	fly_vbox.add_theme_constant_override("separation", 12)
	_more_flyout_card.add_child(fly_vbox)

	fly_vbox.add_child(_cascade_step(0, _labeled("QUICK ACCESS")))

	for i in range(MORE_SHORTCUTS.size()):
		var entry: Dictionary = MORE_SHORTCUTS[i]
		var btn := _flyout_shortcut_button(entry["label"], entry["tint"])
		var view_id: String = entry["view"]
		btn.pressed.connect(func(): more_shortcut_pressed.emit(view_id))
		fly_vbox.add_child(_cascade_step(i, btn))

	var all_btn := _flyout_shortcut_button("\u2261  ALL FEATURES  \u25B6", COL_GOLD)
	all_btn.pressed.connect(func(): more_pressed.emit())
	fly_vbox.add_child(_cascade_step(MORE_SHORTCUTS.size(), all_btn))


# Small left-aligned tinted row button used inside the MORE flyout - same
# family as the nav bars, just sized for a cascade step rather than the
# full-width main list.
func _flyout_shortcut_button(label_text: String, tint: Color) -> Button:
	var b := Button.new()
	b.text = label_text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_stylebox_override("normal", create_casual_stylebox(Color(tint.r, tint.g, tint.b, 0.55)))
	b.add_theme_stylebox_override("hover", create_casual_stylebox(tint))
	b.add_theme_stylebox_override("pressed", create_casual_stylebox(tint))
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	return b


# Wraps a control in an HBox with a growing left spacer, so each successive
# flyout item steps further to the right - the same staircase FIFA uses for
# its Kick-Off sub-buttons.
func _cascade_step(index: int, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(index * 16, 0)
	row.add_child(spacer)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _styled_option_button() -> OptionButton:
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(0, 54)
	opt.add_theme_font_size_override("font_size", 20)
	opt.alignment = HORIZONTAL_ALIGNMENT_CENTER

	var normal := create_casual_stylebox(Color(1, 1, 1, 0.15))
	var hover := create_casual_stylebox(Color(1, 1, 1, 0.3))
	var pressed := create_casual_stylebox(Color(1, 1, 1, 0.45))

	opt.add_theme_stylebox_override("normal", normal)
	opt.add_theme_stylebox_override("hover", hover)
	opt.add_theme_stylebox_override("pressed", pressed)
	opt.get_popup().add_theme_font_size_override("font_size", 20)
	return opt


func _styled_start_button() -> Button:
	var b := Button.new()
	b.text = LocalizationManager.get_string("start_run", _game_state.selected_language).to_upper()
	b.custom_minimum_size = Vector2(0, 66)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color(0.06, 0.16, 0.05))
	b.add_theme_color_override("font_hover_color", Color(0.06, 0.16, 0.05))
	b.add_theme_color_override("font_pressed_color", Color(0.06, 0.16, 0.05))

	b.add_theme_stylebox_override("normal", JellyTheme.primary_button_style(0.92))
	b.add_theme_stylebox_override("hover", JellyTheme.primary_button_style(1.05))
	b.add_theme_stylebox_override("pressed", JellyTheme.primary_button_style(1.15))

	b.item_rect_changed.connect(func():
		b.pivot_offset = b.size / 2.0
	)
	b.mouse_entered.connect(func():
		var t := create_tween()
		t.tween_property(b, "scale", Vector2(1.015, 1.015), 0.08)
	)
	b.mouse_exited.connect(func():
		var t := create_tween()
		t.tween_property(b, "scale", Vector2(1.0, 1.0), 0.08)
	)
	return b


func _select_option(option_button: OptionButton, value: String) -> void:
	for i in range(option_button.item_count):
		if option_button.get_item_text(i) == value:
			option_button.select(i)
			return
	option_button.select(0)


func _select_option_by_metadata(option_button: OptionButton, value: String) -> void:
	for i in range(option_button.item_count):
		if option_button.get_item_metadata(i) == value:
			option_button.select(i)
			return
	option_button.select(0)


func _on_start_pressed() -> void:
	var theme_name = _theme_option.get_item_text(_theme_option.selected)
	var difficulty = _difficulty_option.get_item_metadata(_difficulty_option.selected)
	var weak_keys = _weak_keys_check.button_pressed
	_game_state.selected_theme = theme_name
	_game_state.selected_difficulty = difficulty
	_game_state.weak_keys_mode = weak_keys
	_game_state.save_data()
	visible = false
	start_pressed.emit(theme_name, difficulty, weak_keys)


func _labeled(txt: String) -> Label:
	var l = Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 14)
	l.modulate = COL_MUTE
	return l


func open() -> void:
	move_to_front()
	visible = true
	_refresh_progress_widgets()
	_set_active_nav("start", false)

	BackgroundThemes.advance()
	_refresh_backdrop()


func close() -> void:
	visible = false


## Generates a clean, flat, modern button style that never stretches or distorts
func create_casual_stylebox(border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	# Transparent dark gray background
	style.bg_color = Color(0.1, 0.1, 0.1, 0.6)

	# Subtle clean border
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = border_color

	# Clean rounded corners (perfect for grids and options!)
	style.set_corner_radius_all(14)

	# Internal spacing so text has breathing room
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8

	return style
