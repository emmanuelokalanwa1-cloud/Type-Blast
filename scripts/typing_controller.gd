class_name TypingController
extends Node


signal word_matched(label: Label)
signal input_invalid()
@warning_ignore("unused_signal")
signal input_progress(is_valid_prefix: bool, matched_color: Color)
signal key_typed(letter: String, is_valid: bool)     # fires once per character actually typed
signal key_deleted()                  # fires once per character actually removed
signal word_progress(ratio: float)    # 0.0-1.0 how far into the closest word you are
signal repeated_mistake()             # same wrong char typed 3+ times in a row

var _input_box: LineEdit
var _word_manager: WordManager
var _is_active_check: Callable # returns bool: should we accept input right now?
var _last_text := "" # tracks previous text so we can tell keystrokes from programmatic clears
var _was_active := true
var _last_invalid_char := ""
var _repeated_invalid_count := 0

func setup(input_box: LineEdit, word_manager: WordManager, is_active_check: Callable) -> void:
	_input_box = input_box
	_word_manager = word_manager
	_is_active_check = is_active_check
	_input_box.text_changed.connect(_on_text_changed)
	_input_box.text_submitted.connect(_on_text_submitted)

func _on_text_submitted(_t: String) -> void:
	_on_text_changed(_input_box.text)

func _on_text_changed(new_text: String) -> void:
	var active = _is_active_check.call()

	# 4. If typing just became inactive mid-word (pause opened, game ended),
	# clear the box instead of leaving stale text sitting there.
	if _was_active and not active and new_text != "":
		_last_text = ""
		_input_box.call_deferred("set_text", "")
		_was_active = active
		return
	_was_active = active

	if not active:
		_last_text = new_text
		return

	# 1. Strip anything that isn't a letter so stray punctuation/number taps
	# don't corrupt prefix matching (and re-sync the box if we changed it).
	var letters_only := ""
	for c in new_text:
		if c.to_upper() != c.to_lower(): # is alphabetic
			letters_only += c
	if letters_only != new_text:
		new_text = letters_only
		_input_box.call_deferred("set_text", new_text)
		_input_box.call_deferred("caret_column", new_text.length())

	if new_text == "":
		if _last_text != "":
			key_deleted.emit()
		_last_text = new_text
		return

	var upper_text = new_text.to_upper()

	var found_match := false
	var match_color := Color.WHITE
	var closest_word := ""
	for label in _word_manager.active_words:
		if is_instance_valid(label):
			var word_target = String(label.get_meta("word"))
			if word_target.begins_with(upper_text):
				match_color = label.modulate
				found_match = true
				closest_word = word_target
				break
	if found_match:
		_input_box.add_theme_color_override("font_color", match_color)
	else:
		_input_box.add_theme_color_override("font_color", Color.RED)

	# 2. Report progress through the closest matching word.
	if found_match and closest_word.length() > 0:
		word_progress.emit(float(upper_text.length()) / float(closest_word.length()))

	# Emit one key_typed()/key_deleted() per actual character difference vs
	# the last known text, so a fast typist (or a paste) still gets one
	# sound per character rather than one sound for the whole event.
	var char_delta = new_text.length() - _last_text.length()
	if char_delta > 0:
		# Slice out just the newly-added letters (usually 1, but a paste
		# or very fast burst can add more than one at once) so each gets
		# its own key_typed emission with the letter that was actually typed.
		var added_chars := upper_text.substr(upper_text.length() - char_delta, char_delta)
		for i in range(char_delta):
			var ch := added_chars.substr(i, 1) if i < added_chars.length() else ""
			key_typed.emit(ch, found_match)
	elif char_delta < 0:
		for i in range(-char_delta):
			key_deleted.emit()

	# 5. Track repeated wrong characters (same last letter, still invalid).
	var last_char = upper_text.substr(upper_text.length() - 1, 1) if upper_text.length() > 0 else ""
	if not found_match and last_char == _last_invalid_char:
		_repeated_invalid_count += 1
		if _repeated_invalid_count >= 3:
			repeated_mistake.emit()
			_repeated_invalid_count = 0
	elif not found_match:
		_last_invalid_char = last_char
		_repeated_invalid_count = 1
	else:
		_last_invalid_char = ""
		_repeated_invalid_count = 0

	if not _word_manager.find_prefix_match(upper_text):
		input_invalid.emit()
		_last_text = "" # we're about to clear it ourselves - not a real backspace
		_input_box.call_deferred("set_text", "")
		return

	var matched_label = _word_manager.find_exact_match(upper_text)
	if matched_label:
		_last_text = "" # same as above: this clear is programmatic, not a keystroke
		_input_box.call_deferred("set_text", "")
		word_matched.emit(matched_label)
		return

	_last_text = new_text

# 3. Public reset for callers (main.gd) to invoke when pausing/opening a
# menu, so no leftover state carries into the next run.
func reset() -> void:
	_last_text = ""
	_last_invalid_char = ""
	_repeated_invalid_count = 0
	if _input_box:
		_input_box.call_deferred("set_text", "")
