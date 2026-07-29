class_name TypingController
extends Node

## Watches the on-screen text input and matches what's typed against the
## currently falling words owned by WordManager. Centralizes:
##  - per-keystroke validity (does the input still prefix-match a falling
##    word?) so main.gd can play the right keystroke sound and track
##    per-letter accuracy without duplicating logic here.
##  - detecting a completed word (exact match) and clearing input for the
##    next word.
##  - flagging input that no longer matches anything falling.
##
## Doesn't touch scoring, lives, or word removal directly - it reports what
## happened via signals and lets main.gd/game_state own the consequences.

signal word_matched(label: Label)
signal input_invalid
signal key_typed(letter: String, is_valid: bool)
signal key_deleted

var _input_box: LineEdit
var _word_manager: WordManager
var _is_active: Callable
var _mobile_support: MobileSupport

var _last_text := ""

func setup(input_box: LineEdit, word_manager: WordManager, is_active: Callable, mobile_support: MobileSupport) -> void:
	_input_box = input_box
	_word_manager = word_manager
	_is_active = is_active
	_mobile_support = mobile_support
	_input_box.text_changed.connect(_on_text_changed)
	_last_text = _input_box.text

## Clears whatever's typed so far without treating it as a deletion (called
## by main.gd after a catch, a miss, or whenever the pause/difficulty menu
## or tutorial overlay closes).
func reset() -> void:
	_last_text = ""
	if is_instance_valid(_input_box):
		_input_box.text = ""

func _on_text_changed(new_text: String) -> void:
	if _is_active.is_valid() and not _is_active.call():
		_last_text = new_text
		return

	# Backspace / cut - just report it, nothing else to validate.
	if new_text.length() < _last_text.length():
		_last_text = new_text
		key_deleted.emit()
		return

	# No net growth (e.g. a no-op signal fire) - nothing to do.
	if new_text.length() <= _last_text.length():
		_last_text = new_text
		return

	var upper_text := new_text.to_upper()
	var letter := upper_text.substr(upper_text.length() - 1, 1)
	var is_valid := _word_manager.find_prefix_match(upper_text)

	key_typed.emit(letter, is_valid)

	if not is_valid:
		# Only wrong keys buzz - vibrating on every valid keystroke gets
		# tiring fast on a long typing run, so save the haptic for the
		# moment that actually needs a player's attention.
		if is_instance_valid(_mobile_support):
			_mobile_support.vibrate(25)
		input_invalid.emit()
		_last_text = ""
		_input_box.text = ""
		return

	var match_label := _word_manager.find_exact_match(upper_text)
	if match_label:
		_last_text = ""
		_input_box.text = ""
		word_matched.emit(match_label)
		return

	_last_text = new_text
