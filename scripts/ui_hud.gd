class_name UiHud
extends Node

## Everything purely visual: HUD label text/color, floating "+10"/"MISS"
## popups, particles, background theme lerp, and screen shake. Other
## systems just call these functions or let signals drive them.
##
## LAYOUT: classic AAA cluster HUD (score/high-score top-left, level/combo
## top-center, timer top-right, lives bottom-left, WPM/accuracy bottom-right),
## each on its own panel, framed with corner brackets, plus a stack of
## advanced polish systems (drawn heart/shield icons, accuracy gauge, WPM
## sparkline, combo bar, toasts, vignettes, etc). See the numbered comments
## below for each addition.

var bg_themes = [Color(0.03, 0.03, 0.05), Color(0.06, 0.01, 0.03), Color(0.01, 0.05, 0.02), Color(0.05, 0.05, 0.01), Color(0.03, 0.0, 0.06)]
var accent_themes = [Color(0.25, 0.85, 1.0), Color(1.0, 0.35, 0.55), Color(0.4, 1.0, 0.5), Color(1.0, 0.85, 0.2), Color(0.7, 0.4, 1.0)]
var target_bg_color: Color = Color(0.03, 0.03, 0.05)
var shake_intensity := 0.0
var _shake_seed := 0.0

const DANGER_COLOR := Color(1.0, 0.25, 0.25)
const PANEL_COLOR := Color(0.0, 0.0, 0.0, 0.4)

var _root: Control
var _game_state: GameState
var _main_bg: ColorRect
var _color_overlay: ColorRect

var score_label: Label
var time_label: Label
var lives_label: Label
var highscore_label: Label
var combo_label: Label
var wpm_label: Label
var accuracy_label: Label

var _panel_topleft: Panel
var _panel_topcenter: Panel
var _panel_topright: Panel
var _panel_bottomleft: Panel
var _panel_bottomright: Panel
var _all_panels: Array[Panel] = []
var _corner_lines: Array[Line2D] = []
var _current_accent: Color = Color(0.25, 0.85, 1.0)

# --- animated score tally ---
var _displayed_score: float = 0.0

# --- danger / shield pulse state ---
var _time_pulse_t := 0.0
var _lives_pulse_t := 0.0
var _shield_pulse_t := 0.0

# --- heart / shield icon row (custom-drawn, avoids emoji/encoding issues) ---
var _heart_row: Control

# --- accuracy gauge + wpm sparkline (custom-drawn) ---
var _accuracy_gauge: Control
var _wpm_graph: Control
var _wpm_history: Array[float] = []

# --- combo progress bar ---
var _combo_bar: ProgressBar

# --- streak / fire badge ---
var _streak_badge: Label

# --- pause indicator ---
var _pause_dot: ColorRect
var _pause_t := 0.0

# --- timer warning icon ---
var _time_warning_icon: Label

# --- rank ticker ---
var _rank_ticker_t := 0.0
var _rank_ticker_index := 0

# --- ambient background particles ---
var _ambient_particles: CPUParticles2D

# --- decorative parallax planets (Kenney planet pack) ---
var _backdrop_nodes: Array = []

# --- achievement milestones already fired (so they don't repeat) ---
var _milestones_hit: Dictionary = {}

func setup(root: Control, game_state: GameState, score_label_: Label, time_label_: Label,
		lives_label_: Label, highscore_label_: Label, combo_label_: Label) -> void:
	_root = root
	_game_state = game_state
	score_label = score_label_
	time_label = time_label_
	lives_label = lives_label_
	highscore_label = highscore_label_
	combo_label = combo_label_

	_setup_background_layer()
	_setup_backdrop()                   # 21. rotating space backdrop (Kenney art)
	_setup_ambient_particles()          # 20. ambient background drift
	_setup_overlay()
	_setup_extra_labels()
	_setup_panels()
	_setup_corner_frame()
	_setup_heart_row()                  # 1. fixed heart/shield icons
	_setup_accuracy_gauge()             # 3. circular accuracy gauge
	_setup_wpm_graph()                  # 5. wpm sparkline
	_setup_combo_bar()                  # 4. combo progress bar
	_setup_streak_badge()               # 14. streak fire badge
	_setup_pause_indicator()            # 12. pause pulse dot
	_setup_time_warning_icon()          # 18. time critical icon
	_apply_shadows_to_all()
	_layout_labels()
	_play_intro_animation()             # 6. HUD intro animation

	_root.resized.connect(_layout_labels) # 19. adaptive re-layout on resize

	_game_state.score_changed.connect(func(_v): _on_score_changed())
	_game_state.lives_changed.connect(func(_v): update_ui())
	_game_state.combo_changed.connect(func(_v): update_ui())
	_game_state.time_changed.connect(func(_v): update_ui())
	_game_state.level_changed.connect(func(_v): update_ui())
	_game_state.stats_changed.connect(func(): update_ui())
	_game_state.shield_changed.connect(func(_v): update_ui())
	_game_state.level_up.connect(_on_level_up)

# ---------------------------------------------------------------------------
# BASE LAYERS
# ---------------------------------------------------------------------------

func _setup_background_layer() -> void:
	_main_bg = ColorRect.new()
	_main_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_bg.color = bg_themes[0]
	_root.add_child(_main_bg)
	_root.move_child(_main_bg, 0)

## 21. The visible gameplay backdrop: one of 4 rotating space themes
## (gradient + two Kenney planet sprites) from BackgroundThemes. Advances
## once when a run starts and again automatically every ~22s on a timer,
## so a single long run doesn't just sit on the same scenery forever.
func _setup_backdrop() -> void:
	BackgroundThemes.advance()
	_backdrop_nodes = BackgroundThemes.build(_root, BackgroundThemes.current_index, 0.4)
	_root.move_child(_main_bg, 0) # keep the legacy flat layer furthest back

	var timer := Timer.new()
	timer.wait_time = 22.0
	timer.autostart = true
	timer.one_shot = false
	_root.add_child(timer)
	timer.timeout.connect(_cycle_backdrop)


func _cycle_backdrop() -> void:
	var old_nodes := _backdrop_nodes
	BackgroundThemes.advance()
	_backdrop_nodes = BackgroundThemes.build(_root, BackgroundThemes.current_index, 0.4)
	_root.move_child(_main_bg, 0)

	# Crossfade: new backdrop fades in over the old one, which is only
	# freed once the fade finishes, so the swap never pops or leaves a
	# blank frame.
	for n in _backdrop_nodes:
		n.modulate.a = 0.0
	var t := create_tween()
	t.set_parallel(true)
	for n in _backdrop_nodes:
		t.tween_property(n, "modulate:a", 1.0, 1.4)
	_root.get_tree().create_timer(1.5).timeout.connect(func(): BackgroundThemes.free_nodes(old_nodes))

## 20. Ambient background particles for atmosphere (slow, low-count drift).
func _setup_ambient_particles() -> void:
	_ambient_particles = CPUParticles2D.new()
	_ambient_particles.amount = 24
	_ambient_particles.lifetime = 8.0
	_ambient_particles.preprocess = 8.0
	_ambient_particles.emitting = true
	_ambient_particles.direction = Vector2(0, -1)
	_ambient_particles.spread = 15.0
	_ambient_particles.gravity = Vector2.ZERO
	_ambient_particles.initial_velocity_min = 4.0
	_ambient_particles.initial_velocity_max = 10.0
	_ambient_particles.scale_amount_min = 1.0
	_ambient_particles.scale_amount_max = 2.0
	_ambient_particles.color = Color(1, 1, 1, 0.08)
	_ambient_particles.texture = load("res://assets/items/particles/glow_soft.png")
	_root.add_child(_ambient_particles)
	_root.move_child(_ambient_particles, 1)
	_reposition_ambient_particles()

func _reposition_ambient_particles() -> void:
	if not is_instance_valid(_ambient_particles):
		return
	var screen = _root.get_viewport_rect().size
	_ambient_particles.position = Vector2(screen.x / 2.0, screen.y + 20)
	_ambient_particles.emission_rect_extents = Vector2(screen.x / 2.0, 4.0)

func _setup_overlay() -> void:
	_color_overlay = ColorRect.new()
	_color_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_color_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_overlay.color = Color(1, 1, 1, 0)
	_root.add_child(_color_overlay)
	_root.move_child(_color_overlay, 2)

func _setup_extra_labels() -> void:
	wpm_label = Label.new()
	wpm_label.text = "WPM: 0"
	wpm_label.add_theme_font_size_override("font_size", 30)
	wpm_label.modulate = Color(0.4, 1.0, 0.6)
	_root.add_child(wpm_label)

	accuracy_label = Label.new()
	accuracy_label.text = "ACC: 100%"
	accuracy_label.add_theme_font_size_override("font_size", 30)
	accuracy_label.modulate = Color(0.3, 0.8, 1.0)
	_root.add_child(accuracy_label)

# ---------------------------------------------------------------------------
# DYNAMIC CUSTOM-DRAWN WIDGETS (helper: builds a Control with inline _draw code)
# ---------------------------------------------------------------------------

func _make_dynamic(source: String) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	c.set_script(script)
	return c

## 1. Heart / shield icon row. Jelly mode draws the actual jelly heart icon
## (assets/ui/jelly/icon_heart_red.png); casual mode draws a small vector
## heart instead (same approach already used for the shield glyph below,
## and the same reason hearts were vector-drawn originally, before the
## jelly icon swap: sidesteps an emoji-mojibake bug rather than reviving it
## by falling back to a heart emoji glyph here).
func _setup_heart_row() -> void:
	var is_casual := JellyTheme.current_style == "casual"
	var heart_tex_var := "" if is_casual else "var _heart_tex: Texture2D = load(\"res://assets/ui/jelly/icon_heart_red.png\")"
	var draw_loop := """	for i in range(heart_count):
		var c = Vector2(18 + i * spacing, 20)
		_draw_heart(c, Color(0.9, 0.25, 0.3))""" if is_casual else """	for i in range(heart_count):
		var pos = Vector2(18 + i * spacing, 20) - size / 2.0
		draw_texture_rect(_heart_tex, Rect2(pos, size), false)"""
	var heart_func := """
func _draw_heart(center: Vector2, color: Color) -> void:
	var pts = PackedVector2Array([
		center + Vector2(0, 9),
		center + Vector2(-11, -2),
		center + Vector2(-11, -8),
		center + Vector2(-5, -12),
		center + Vector2(0, -7),
		center + Vector2(5, -12),
		center + Vector2(11, -8),
		center + Vector2(11, -2),
	])
	draw_colored_polygon(pts, color)
""" if is_casual else ""
	_heart_row = _make_dynamic("""
extends Control

var heart_count := 0
var shield_active := false
%s

func _draw() -> void:
	var spacing = 34.0
	var size = Vector2(26, 26)
%s
	if shield_active:
		_draw_shield(Vector2(18 + heart_count * spacing, 20), Color(0.35, 0.75, 1.0))

func _draw_shield(center: Vector2, color: Color) -> void:
	var pts = PackedVector2Array([
		center + Vector2(0, -14),
		center + Vector2(10, -8),
		center + Vector2(10, 5),
		center + Vector2(0, 15),
		center + Vector2(-10, 5),
		center + Vector2(-10, -8),
	])
	draw_colored_polygon(pts, color)
%s
func set_state(count: int, shield: bool) -> void:
	heart_count = count
	shield_active = shield
	queue_redraw()
""" % [heart_tex_var, draw_loop, heart_func])
	_heart_row.custom_minimum_size = Vector2(220, 40)
	_root.add_child(_heart_row)

## 3. Circular accuracy gauge (ring that fills clockwise with accuracy %).
func _setup_accuracy_gauge() -> void:
	_accuracy_gauge = _make_dynamic("""
extends Control

var pct := 1.0
var ring_color := Color(0.3, 0.8, 1.0)

func _draw() -> void:
	var r = 16.0
	var center = Vector2(r + 2, r + 2)
	draw_arc(center, r, 0, TAU, 32, Color(1, 1, 1, 0.15), 4.0, true)
	draw_arc(center, r, -PI / 2.0, -PI / 2.0 + TAU * pct, 32, ring_color, 4.0, true)

func set_pct(p: float, color: Color) -> void:
	pct = clamp(p, 0.0, 1.0)
	ring_color = color
	queue_redraw()
""")
	_accuracy_gauge.custom_minimum_size = Vector2(36, 36)
	_root.add_child(_accuracy_gauge)

## 5. WPM mini sparkline graph tracking recent samples.
func _setup_wpm_graph() -> void:
	_wpm_graph = _make_dynamic("""
extends Control

var samples: Array = []
var line_color := Color(0.4, 1.0, 0.6)

func _draw() -> void:
	if samples.size() < 2:
		return
	var w = size.x
	var h = size.y
	var max_v = 1.0
	for s in samples:
		max_v = max(max_v, s)
	var pts = PackedVector2Array()
	var step = w / float(samples.size() - 1)
	for i in range(samples.size()):
		var x = i * step
		var y = h - (samples[i] / max_v) * h
		pts.append(Vector2(x, y))
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], line_color, 2.0, true)

func push_sample(v: float, color: Color) -> void:
	samples.append(v)
	if samples.size() > 20:
		samples.pop_front()
	line_color = color
	queue_redraw()
""")
	_wpm_graph.custom_minimum_size = Vector2(90, 28)
	_root.add_child(_wpm_graph)

## 4. Combo progress bar - fills toward the next glow tier (10 / 25).
func _setup_combo_bar() -> void:
	_combo_bar = ProgressBar.new()
	_combo_bar.show_percentage = false
	_combo_bar.max_value = 25
	_combo_bar.value = 0
	_combo_bar.custom_minimum_size = Vector2(280, 8)
	_combo_bar.add_theme_stylebox_override("background", JellyTheme.progress_track_style(0.5))
	_combo_bar.add_theme_stylebox_override("fill", JellyTheme.progress_fill_style(_current_accent))
	_root.add_child(_combo_bar)

## Re-skins the two HUD elements that actually change look between Casual
## and Jelly (the combo progress bar, and the heart row which swaps
## between a drawn vector heart and the jelly heart icon) so a style
## change takes effect immediately even if a run is in progress, instead
## of only on the next time the HUD happens to rebuild (it never does -
## the HUD is built once at boot and reused for the whole app session).
func refresh_theme() -> void:
	if is_instance_valid(_combo_bar):
		_combo_bar.add_theme_stylebox_override("background", JellyTheme.progress_track_style(0.5))
		var new_fill := JellyTheme.progress_fill_style(_current_accent)
		_combo_bar.add_theme_stylebox_override("fill", new_fill)

	if is_instance_valid(_heart_row):
		var prev_lives := _game_state.lives if is_instance_valid(_game_state) else 0
		var prev_shield := _game_state.shield_active if is_instance_valid(_game_state) else false
		var old_heart_row := _heart_row
		_root.remove_child(old_heart_row)
		old_heart_row.queue_free()
		_setup_heart_row()
		_heart_row.set_state(max(0, prev_lives), prev_shield)

	_layout_labels()
	if is_instance_valid(_combo_bar): JellyTheme.play_rebuild_transition(_combo_bar)
	if is_instance_valid(_heart_row): JellyTheme.play_rebuild_transition(_heart_row)

## 14. Streak / fire badge that appears and grows with high combos.
func _setup_streak_badge() -> void:
	_streak_badge = Label.new()
	_streak_badge.text = "▲ STREAK"
	_streak_badge.add_theme_font_size_override("font_size", 20)
	_streak_badge.modulate = Color(1, 1, 1, 0)
	_root.add_child(_streak_badge)

## 12. Small pulsing pause indicator dot next to the system pause label.
func _setup_pause_indicator() -> void:
	_pause_dot = ColorRect.new()
	_pause_dot.color = Color(1.0, 0.85, 0.2)
	_pause_dot.size = Vector2(10, 10)
	_pause_dot.visible = false
	_root.add_child(_pause_dot)

## 18. Small pulsing warning icon shown beside the timer under 10 seconds.
func _setup_time_warning_icon() -> void:
	_time_warning_icon = Label.new()
	_time_warning_icon.text = "!"
	_time_warning_icon.add_theme_font_size_override("font_size", 34)
	_time_warning_icon.modulate = Color(1, 1, 1, 0)
	_time_warning_icon.add_theme_color_override("font_color", DANGER_COLOR)
	_root.add_child(_time_warning_icon)

# ---------------------------------------------------------------------------
# PANELS / FRAME
# ---------------------------------------------------------------------------

func _make_panel() -> Panel:
	var p = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_corner_radius_all(8)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(_current_accent.r, _current_accent.g, _current_accent.b, 0.35)
	p.add_theme_stylebox_override("panel", style)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(p)
	_root.move_child(p, 3)
	return p

func _setup_panels() -> void:
	_panel_topleft = _make_panel()
	_panel_topcenter = _make_panel()
	_panel_topright = _make_panel()
	_panel_bottomleft = _make_panel()
	_panel_bottomright = _make_panel()
	_all_panels = [_panel_topleft, _panel_topcenter, _panel_topright, _panel_bottomleft, _panel_bottomright]

func _setup_corner_frame() -> void:
	var configs = [
		{"corner": Vector2(0, 0), "dx": 1, "dy": 1},
		{"corner": Vector2(1, 0), "dx": -1, "dy": 1},
		{"corner": Vector2(0, 1), "dx": 1, "dy": -1},
		{"corner": Vector2(1, 1), "dx": -1, "dy": -1},
	]
	for cfg in configs:
		var line = Line2D.new()
		line.width = 3.0
		line.default_color = Color(_current_accent.r, _current_accent.g, _current_accent.b, 0.55)
		line.set_meta("corner", cfg["corner"])
		line.set_meta("dx", cfg["dx"])
		line.set_meta("dy", cfg["dy"])
		_root.add_child(line)
		_root.move_child(line, 3)
		_corner_lines.append(line)
	_update_corner_frame()

func _update_corner_frame() -> void:
	var screen = _root.get_viewport_rect().size
	var margin := 18.0
	var arm := 46.0
	for line in _corner_lines:
		var corner: Vector2 = line.get_meta("corner")
		var dx: float = line.get_meta("dx")
		var dy: float = line.get_meta("dy")
		var base = Vector2(corner.x * screen.x, corner.y * screen.y)
		base += Vector2(dx, dy) * margin
		line.clear_points()
		line.add_point(base + Vector2(dx * arm, 0))
		line.add_point(base)
		line.add_point(base + Vector2(0, dy * arm))

## 13. Re-tint corner frame + panel borders to match the current level's accent.
func _apply_accent_color(color: Color) -> void:
	_current_accent = color
	for line in _corner_lines:
		line.default_color = Color(color.r, color.g, color.b, 0.55)
	for p in _all_panels:
		var style: StyleBoxFlat = p.get_theme_stylebox("panel")
		if style:
			style.border_color = Color(color.r, color.g, color.b, 0.35)
	if is_instance_valid(_combo_bar):
		var fill: StyleBox = _combo_bar.get_theme_stylebox("fill")
		if fill:
			JellyTheme.set_fill_color(fill, color)

func _apply_shadows_to_all() -> void:
	var hud_labels = [score_label, time_label, lives_label, highscore_label, combo_label, wpm_label, accuracy_label, _streak_badge]
	for label in hud_labels:
		if is_instance_valid(label) and label:
			label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
			label.add_theme_constant_override("shadow_offset_x", 3)
			label.add_theme_constant_override("shadow_offset_y", 3)
			label.add_theme_constant_override("shadow_outline_size", 5)

# ---------------------------------------------------------------------------
# LAYOUT
# ---------------------------------------------------------------------------

func _layout_labels() -> void:
	var screen = _root.get_viewport_rect().size

	# --- TOP LEFT: SCORE CLUSTER ---
	highscore_label.add_theme_font_size_override("font_size", 20)
	highscore_label.modulate = Color(0.75, 0.75, 0.75)
	highscore_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	highscore_label.position = Vector2(46, 24)
	highscore_label.size = Vector2(240, 26)
	highscore_label.clip_text = false

	score_label.add_theme_font_size_override("font_size", 40)
	score_label.modulate = Color.WHITE
	score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	score_label.position = Vector2(46, 54)

	_panel_topleft.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_panel_topleft.position = Vector2(24, 12)
	_panel_topleft.size = Vector2(280, 108) # roomy padding so text never clips

	# --- TOP CENTER: STATUS CLUSTER ---
	combo_label.add_theme_font_size_override("font_size", 28)
	combo_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	combo_label.position = Vector2((screen.x / 2) - 150, 30)

	_combo_bar.position = Vector2((screen.x / 2) - 140, 66)

	_panel_topcenter.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel_topcenter.position = Vector2((screen.x / 2) - 170, 12)
	_panel_topcenter.size = Vector2(340, 78)

	# --- TOP RIGHT: TIMER CLUSTER ---
	time_label.add_theme_font_size_override("font_size", 40)
	time_label.modulate = Color(1.0, 0.4, 0.4)
	time_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	time_label.position = Vector2(screen.x - 220, 30)

	_time_warning_icon.position = Vector2(screen.x - 250, 26)

	_panel_topright.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel_topright.position = Vector2(screen.x - 260, 12)
	_panel_topright.size = Vector2(236, 78)

	# --- BOTTOM LEFT: LIVES CLUSTER ---
	lives_label.visible = false # replaced by drawn heart row (addition 1)
	_heart_row.position = Vector2(20, screen.y - 70)

	_panel_bottomleft.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_panel_bottomleft.position = Vector2(24, screen.y - 96)
	_panel_bottomleft.size = Vector2(260, 78)

	# --- BOTTOM RIGHT: PERFORMANCE CLUSTER ---
	wpm_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	wpm_label.position = Vector2(screen.x - 300, screen.y - 100)

	_wpm_graph.position = Vector2(screen.x - 300, screen.y - 68)

	accuracy_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	accuracy_label.position = Vector2(screen.x - 300, screen.y - 34)

	_accuracy_gauge.position = Vector2(screen.x - 68, screen.y - 40)

	_panel_bottomright.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel_bottomright.position = Vector2(screen.x - 320, screen.y - 112)
	_panel_bottomright.size = Vector2(296, 96)

	# --- misc floating elements ---
	_streak_badge.position = Vector2((screen.x / 2) - 60, 96)
	_pause_dot.position = Vector2(90, 8)

	_update_corner_frame()
	_reposition_ambient_particles()

## 6. HUD intro animation: panels + corner frame fade/slide in on start.
func _play_intro_animation() -> void:
	for p in _all_panels:
		var target_pos = p.position
		p.position = target_pos + Vector2(0, -30)
		p.modulate.a = 0.0
		var tw = _root.create_tween()
		tw.tween_property(p, "position", target_pos, 0.35).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(p, "modulate:a", 1.0, 0.35)
	for line in _corner_lines:
		line.modulate.a = 0.0
		_root.create_tween().tween_property(line, "modulate:a", 1.0, 0.5)

# ---------------------------------------------------------------------------
# STATE -> UI
# ---------------------------------------------------------------------------

func _format_number(n: int) -> String: # 17. thousands separator formatting
	var s = str(abs(n))
	var out = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i != 0:
			out = "," + out
	if n < 0:
		out = "-" + out
	return out

func update_ui() -> void:
	var gs = _game_state
	var loc = gs.selected_language
	time_label.text = LocalizationManager.get_string("hud_time", loc).to_upper() + ": " + str(int(gs.time_left))
	highscore_label.text = LocalizationManager.get_string("hud_top", loc).to_upper() + ": " + _format_number(gs.high_scores[0])
	combo_label.text = LocalizationManager.get_string("level", loc).to_upper() + " " + str(gs.level) + " | [x" + str(gs.combo) + "]"
	wpm_label.text = LocalizationManager.get_string("hud_wpm", loc).to_upper() + ": " + str(int(round(gs.get_wpm())))
	accuracy_label.text = LocalizationManager.get_string("hud_acc", loc).to_upper() + ": " + str(int(round(gs.get_accuracy()))) + "%"

	# score_label.text is driven by the animated tally in per_frame_tween()

	# --- 1. heart/shield icon row (fixes broken emoji rendering) ---
	_heart_row.set_state(max(0, gs.lives), gs.shield_active)

	# --- 3. accuracy gauge ---
	var acc = gs.get_accuracy()
	var acc_color = Color(0.3, 0.8, 1.0)
	if acc < 60:
		acc_color = DANGER_COLOR
	elif acc < 85:
		acc_color = Color(1.0, 0.8, 0.2)
	_accuracy_gauge.set_pct(acc / 100.0, acc_color)

	# --- 5. wpm sparkline ---
	_wpm_graph.push_sample(gs.get_wpm(), Color(0.4, 1.0, 0.6))

	# --- 4. combo progress bar ---
	var tier_max = 25.0 if gs.combo >= 10 else 10.0
	_combo_bar.max_value = tier_max
	_combo_bar.value = min(float(gs.combo), tier_max)

	# --- 14. streak badge ---
	if gs.combo > 15:
		var scale_boost = 1.0 + min(0.5, (gs.combo - 15) * 0.02)
		_streak_badge.modulate.a = 1.0
		_streak_badge.scale = Vector2(scale_boost, scale_boost)
	else:
		_streak_badge.modulate.a = 0.0

	# --- 8. achievement toast for combo milestones ---
	for milestone in [10, 25, 50, 100]:
		if gs.combo >= milestone and not _milestones_hit.get(milestone, false):
			_milestones_hit[milestone] = true
			_show_achievement_toast(str(milestone) + "x COMBO!")
	if gs.combo == 0:
		_milestones_hit.clear()

	# Text Glow Multiplier States
	if gs.combo > 25:
		combo_label.modulate = Color(1.0, 0.85, 0.2)
	elif gs.combo > 10:
		combo_label.modulate = Color(0.2, 0.7, 1.0)
	else:
		combo_label.modulate = Color.WHITE

func _on_score_changed() -> void:
	score_label.modulate = Color(1.0, 0.85, 0.2)
	var tw = _root.create_tween()
	tw.tween_property(score_label, "scale", Vector2(1.15, 1.15), 0.05)
	tw.tween_property(score_label, "scale", Vector2.ONE, 0.1)
	update_ui()

## Public entry point for toasts triggered from outside ui_hud (e.g. mission
## completions). `offset_index` staggers vertical position so several toasts
## fired back-to-back don't fully overlap.
func show_toast(text: String, offset_index: int = 0) -> void:
	_show_achievement_toast(text, offset_index)

## 8. Small toast banner used for combo milestones / achievements.
func _show_achievement_toast(text: String, offset_index: int = 0) -> void:
	var msg = Label.new()
	_root.add_child(msg)
	msg.text = text
	msg.add_theme_font_size_override("font_size", 30)
	msg.modulate = Color(1.0, 0.85, 0.2, 0)
	msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	var base_y := 130 + (offset_index * 46)
	msg.position = Vector2((_root.get_viewport_rect().size.x / 2) - 100, base_y)
	var tw = _root.create_tween()
	tw.tween_property(msg, "modulate:a", 1.0, 0.15)
	tw.tween_property(msg, "position:y", base_y + 20, 0.8)
	tw.tween_interval(0.6)
	tw.tween_property(msg, "modulate:a", 0.0, 0.3)
	tw.tween_callback(msg.queue_free)

func per_frame_tween(delta: float) -> void:
	score_label.modulate = score_label.modulate.lerp(Color.WHITE, delta * 2.0)
	_main_bg.color = _main_bg.color.lerp(target_bg_color, delta * 1.5)

	# 16. smoother multi-axis screen shake using layered sine noise instead
	# of pure randf, so it decays as a gentle wobble rather than jitter.
	if shake_intensity > 0:
		_shake_seed += delta * 40.0
		var ox = sin(_shake_seed * 1.3) * shake_intensity
		var oy = cos(_shake_seed * 1.7) * shake_intensity
		_root.position = Vector2(ox, oy)
		shake_intensity = lerp(shake_intensity, 0.0, 5.0 * delta)
	else:
		_root.position = Vector2.ZERO

	if not _game_state:
		return

	var gs = _game_state

	# 7. animated score tally with per-tier flash color
	_displayed_score = lerp(_displayed_score, float(gs.score), min(1.0, delta * 6.0))
	if abs(_displayed_score - gs.score) < 0.5:
		_displayed_score = gs.score
	score_label.text = LocalizationManager.get_string("score", gs.selected_language).to_upper() + ": " + _format_number(int(round(_displayed_score)))

	# 9. low-time danger pulse + 18. warning icon
	if gs.time_left <= 10.0 and gs.time_left > 0.0:
		_time_pulse_t += delta * 8.0
		var t = (sin(_time_pulse_t) + 1.0) * 0.5
		time_label.modulate = DANGER_COLOR.lerp(Color(1, 1, 1), t * 0.5)
		_time_warning_icon.modulate.a = t
	else:
		_time_pulse_t = 0.0
		time_label.modulate = Color(1.0, 0.4, 0.4)
		_time_warning_icon.modulate.a = 0.0

	# 2. low-lives danger pulse (now applied to the drawn heart row)
	if gs.lives <= 1:
		_lives_pulse_t += delta * 8.0
		var scale_amt = 1.0 + (sin(_lives_pulse_t) + 1.0) * 0.5 * 0.15
		_heart_row.scale = Vector2(scale_amt, scale_amt)
	else:
		_lives_pulse_t = 0.0
		_heart_row.scale = Vector2.ONE

	# 10. shield pulse vignette
	if gs.shield_active:
		_shield_pulse_t += delta * 3.0
		var a = 0.05 + (sin(_shield_pulse_t) + 1.0) * 0.5 * 0.05
		_color_overlay.color = Color(0.2, 0.5, 1.0, a)
	elif gs.time_left > 10.0:
		_color_overlay.color = _color_overlay.color.lerp(Color(1, 1, 1, 0), 4 * delta)

	# 12. pause indicator (defensive: only if GameState exposes is_paused)
	var paused = gs.get("is_paused")
	if paused == true:
		_pause_t += delta * 6.0
		_pause_dot.visible = true
		_pause_dot.modulate.a = 0.4 + (sin(_pause_t) + 1.0) * 0.3
	else:
		_pause_dot.visible = false

	# 15. rank ticker - cycles the top few high scores in the score panel
	if gs.high_scores.size() > 1:
		_rank_ticker_t += delta
		if _rank_ticker_t > 2.5:
			_rank_ticker_t = 0.0
			_rank_ticker_index = (_rank_ticker_index + 1) % min(3, gs.high_scores.size())
			var rank_label = "TOP" if _rank_ticker_index == 0 else ("#" + str(_rank_ticker_index + 1))
			highscore_label.text = rank_label + ": " + _format_number(gs.high_scores[_rank_ticker_index])

func apply_freeze_overlay(delta: float) -> void:
	_color_overlay.color = _color_overlay.color.lerp(Color(0, 0.4, 0.9, 0.12), 4 * delta)

func clear_freeze_overlay(delta: float) -> void:
	_color_overlay.color = _color_overlay.color.lerp(Color(1, 1, 1, 0), 4 * delta)

func shake(amount: float) -> void:
	shake_intensity = amount

func theme_for_level(level: int) -> Color:
	return bg_themes[(level - 1) % bg_themes.size()]

func accent_for_level(level: int) -> Color:
	return accent_themes[(level - 1) % accent_themes.size()]

func set_target_bg(color: Color) -> void:
	target_bg_color = color

func _on_level_up(new_level: int) -> void:
	set_target_bg(theme_for_level(new_level))
	_apply_accent_color(accent_for_level(new_level)) # 13. accent re-theme
	_spawn_level_up_ring()                            # 11. radial burst ring

## 11. Expanding ring burst on level-up, layered on top of the gold flash.
func _spawn_level_up_ring() -> void:
	var ring = _make_dynamic("""
extends Control

var progress := 0.0
var ring_color := Color(1.0, 0.85, 0.2)

func _draw() -> void:
	var r = 20 + progress * 160
	var a = 1.0 - progress
	draw_arc(size / 2.0, r, 0, TAU, 48, Color(ring_color.r, ring_color.g, ring_color.b, a), 4.0, true)
""")
	ring.size = _root.get_viewport_rect().size
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(ring)
	var tw = _root.create_tween()
	tw.tween_method(func(v): ring.progress = v; ring.queue_redraw(), 0.0, 1.0, 0.6)
	tw.finished.connect(ring.queue_free)

## punch: 1.0 = old behavior (no pop). Values above 1.0 (e.g. 1.3 at a high
## combo) make the label snap in oversized and settle to normal size, so a
## hot streak visibly reads as "bigger" catches, not just a pitch change.
func spawn_floating_text(txt: String, pos: Vector2, color: Color, punch: float = 1.0) -> void:
	var l = Label.new()
	_root.add_child(l)
	l.text = txt
	l.position = pos
	l.modulate = color
	l.add_theme_font_size_override("font_size", 32)
	l.pivot_offset = Vector2(20, 16)

	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)

	if punch > 1.0:
		l.scale = Vector2(punch, punch)
		var punch_tw = _root.create_tween()
		punch_tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var tw = _root.create_tween()
	tw.tween_property(l, "position:y", pos.y - 100, 0.4)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(l.queue_free)

func spawn_particles(pos: Vector2, color: Color) -> void:
	var particles = CPUParticles2D.new()
	_root.add_child(particles)
	particles.position = pos
	particles.amount = 16
	particles.explosiveness = 1.0
	particles.color = color
	particles.texture = load("res://assets/items/particles/star.png")
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.1
	particles.spread = 180.0
	particles.initial_velocity_min = 40.0
	particles.initial_velocity_max = 110.0
	particles.gravity = Vector2(0, 60)
	particles.emitting = true
	_root.get_tree().create_timer(0.8).timeout.connect(particles.queue_free)

func spawn_ghost(label: Label) -> void:
	var ghost = label.duplicate()
	_root.add_child(ghost)
	var t = _root.create_tween().set_parallel(true)
	t.tween_property(ghost, "scale", Vector2(1.4, 1.4), 0.2)
	t.tween_property(ghost, "modulate:a", 0.0, 0.2)
	t.chain().tween_callback(ghost.queue_free)

func flash_background_gold() -> void:
	var flash = ColorRect.new()
	flash.size = _root.get_viewport_rect().size
	flash.color = Color.GOLD
	flash.modulate.a = 0.15
	_root.add_child(flash)
	_root.move_child(flash, 1)
	_root.create_tween().tween_property(flash, "modulate:a", 0.0, 0.8).finished.connect(flash.queue_free)

func show_level_up_intermission(level: int) -> void:
	var msg = Label.new()
	_root.add_child(msg)
	msg.text = LocalizationManager.get_string("level_up", _game_state.selected_language).to_upper() + ": " + str(level)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 54)
	msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	msg.modulate = Color(1.0, 0.85, 0.2)
	msg.scale = Vector2.ZERO

	msg.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	msg.add_theme_constant_override("shadow_offset_x", 3)
	msg.add_theme_constant_override("shadow_offset_y", 3)

	var tw = _root.create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(msg, "scale", Vector2.ONE, 0.4)
	await _root.get_tree().create_timer(1.6).timeout
	_root.create_tween().tween_property(msg, "modulate:a", 0.0, 0.2).finished.connect(msg.queue_free)
