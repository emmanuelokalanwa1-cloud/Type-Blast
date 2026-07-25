class_name RoundStartAnnouncer
extends CanvasLayer

## Arcade-announcer flourish #2: a quick "GET READY... TYPE!" banner every
## time a run begins, fighting-game round-intro style but with zero violence.
## Self-connecting: main.gd only ever calls setup() once.

var _label: Label

func setup(game_state: GameState) -> void:
	layer = 54
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", 34)
	_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	game_state.game_started.connect(_on_game_started)

func _on_game_started() -> void:
	if not is_instance_valid(_label):
		return
	_label.text = "GET READY...\nTYPE!"
	_label.scale = Vector2(0.85, 0.85)
	_label.pivot_offset = _label.size / 2.0
	var tw := create_tween()
	tw.tween_property(_label, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(_label, "scale", Vector2(1, 1), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(_label, "modulate:a", 0.0, 0.3)
