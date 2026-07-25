class_name RainbowSurprise
extends CanvasLayer

## SURPRISE: a very rare (~1 in 80 catches) full-screen rainbow flourish.
## Mostly cosmetic, with a small score nudge - a little "did that just
## happen?" moment. Entirely self-contained: main.gd only ever calls
## trigger(), nothing else needs to know this exists.

const COL_CYCLE: Array[Color] = [
	Color(1.0, 0.3, 0.3), Color(1.0, 0.65, 0.15), Color(1.0, 0.95, 0.2),
	Color(0.3, 0.9, 0.4), Color(0.25, 0.6, 1.0), Color(0.6, 0.3, 0.95),
]

var _overlay: ColorRect
var _label: Label
var _busy := false

func _ready() -> void:
	layer = 50

	_overlay = ColorRect.new()
	_overlay.color = Color(1, 1, 1, 0.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	_label = Label.new()
	_label.text = "\u2728 SURPRISE! \u2728"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", 34)
	_label.modulate = Color(1, 1, 1, 0.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

## Plays a quick rainbow flash cycle + pop-in/out message. Safe to call
## repeatedly - re-triggers are ignored while one is already playing.
func trigger() -> void:
	if _busy or not is_instance_valid(_overlay):
		return
	_busy = true

	var tw := create_tween()
	for c in COL_CYCLE:
		var flash := c
		flash.a = 0.16
		tw.tween_property(_overlay, "color", flash, 0.18)
	tw.tween_property(_overlay, "color:a", 0.0, 0.4)
	tw.parallel().tween_property(_label, "modulate:a", 1.0, 0.15)
	tw.tween_interval(0.6)
	tw.tween_property(_label, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): _busy = false)
