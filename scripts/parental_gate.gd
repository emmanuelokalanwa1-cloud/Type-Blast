class_name ParentalGate
extends ColorRect

## A simple "are you an adult?" math-problem gate, shown before
## destructive/real-world actions (currently the account deletion flow
## in more_screen.gd). App Store Review Guideline 3.1.1 / Google Play's
## Families policy both expect an age gate of roughly this shape in
## front of anything that spends real money, opens an external link, or
## destroys data, if the app could plausibly be used by children —
## which applies here given the word-bank profanity filtering already
## done on this project (see CHANGES.md).
##
## Usage:
##   var gate := ParentalGate.new()
##   root.add_child(gate)
##   gate.open()
##   gate.gate_passed.connect(func(): ...)   # do the real thing
##   gate.gate_cancelled.connect(func(): ...) # optional, no-op is fine
## The gate frees itself after either outcome, so callers don't need to
## hold onto the reference or remove it manually.

signal gate_passed()
signal gate_cancelled()

const COL_GOLD := Color(1.0, 0.78, 0.25)
const COL_MUTE := Color(1, 1, 1, 0.68)

var _answer := 0
var _input: LineEdit
var _error_label: Label

func open() -> void:
	color = Color(0, 0, 0, 0.75)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	style.set_corner_radius_all(24)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = COL_GOLD
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 30
	style.content_margin_bottom = 30
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(320, 0)
	center.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	var title = Label.new()
	title.text = "Quick check"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = COL_GOLD
	vbox.add_child(title)

	var a := randi_range(3, 9)
	var b := randi_range(3, 9)
	_answer = a + b

	var question = Label.new()
	question.text = "This purchase is for grown-ups. To continue, solve:\n%d + %d = ?" % [a, b]
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.autowrap_mode = TextServer.AUTOWRAP_WORD
	question.add_theme_font_size_override("font_size", 18)
	vbox.add_child(question)

	_input = LineEdit.new()
	_input.placeholder_text = "Your answer"
	_input.custom_minimum_size = Vector2(0, 44)
	_input.text_submitted.connect(func(_t): _try_submit())
	vbox.add_child(_input)

	_error_label = Label.new()
	_error_label.text = "That's not it — try again."
	_error_label.modulate = Color.INDIAN_RED
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.visible = false
	vbox.add_child(_error_label)

	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)

	var cancel_btn = Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.modulate = COL_MUTE
	cancel_btn.pressed.connect(func():
		gate_cancelled.emit()
		queue_free()
	)
	row.add_child(cancel_btn)

	var submit_btn = Button.new()
	submit_btn.text = "CONTINUE"
	submit_btn.modulate = COL_GOLD
	submit_btn.pressed.connect(func(): _try_submit())
	row.add_child(submit_btn)

	_input.grab_focus()

func _try_submit() -> void:
	if int(_input.text.strip_edges()) == _answer:
		gate_passed.emit()
		queue_free()
	else:
		_error_label.visible = true
		_input.text = ""
		_input.grab_focus()
