class_name SecretCodeEgg
extends CanvasLayer

## SURPRISE: a hidden Konami-style code (Up Up Down Down Left Right Left
## Right). Listens for raw key presses regardless of what has focus, so
## typing in the game's own input box doesn't swallow it. Holds all of its
## own state - main.gd just adds this once and never touches it again.

const SEQUENCE: Array[Key] = [
	KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT,
]

var _progress := 0
var _overlay: ColorRect
var _label: Label

func _ready() -> void:
	layer = 60

	_overlay = ColorRect.new()
	_overlay.color = Color(0.05, 0.02, 0.12, 0.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	_label = Label.new()
	_label.text = "👾  SECRET CODE FOUND  👾\nyou found the hidden code"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", 26)
	_label.modulate = Color(1, 1, 1, 0.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	if key_event.keycode == SEQUENCE[_progress]:
		_progress += 1
		if _progress >= SEQUENCE.size():
			_progress = 0
			_celebrate()
	else:
		_progress = 1 if key_event.keycode == SEQUENCE[0] else 0

func _celebrate() -> void:
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", 0.55, 0.3)
	tw.parallel().tween_property(_label, "modulate:a", 1.0, 0.3)
	tw.tween_interval(1.6)
	tw.tween_property(_overlay, "color:a", 0.0, 0.5)
	tw.parallel().tween_property(_label, "modulate:a", 0.0, 0.5)
