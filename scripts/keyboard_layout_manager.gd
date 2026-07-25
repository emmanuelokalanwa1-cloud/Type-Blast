class_name KeyboardLayoutManager
extends RefCounted

## Groups GameState's weak-letter tracking by physical hand/finger for a
## given keyboard layout, so the "weak keys" report means something for
## players on AZERTY or Dvorak, not just QWERTY. Purely a read-only report
## generator — doesn't change how weak_keys_mode picks practice words
## (that logic in WordManager already works off raw letters and stays
## layout-agnostic on purpose).

const LAYOUTS := ["QWERTY", "AZERTY", "Dvorak"]

## finger group id -> list of letters on that finger, per layout. Small,
## illustrative mapping (home-row + reachable keys), not a full geometry
## model — enough to give a useful "which hand/finger struggles most" read.
const _HAND_MAP := {
	"QWERTY": {
		"Left Pinky": ["Q", "A", "Z"],
		"Left Ring": ["W", "S", "X"],
		"Left Middle": ["E", "D", "C"],
		"Left Index": ["R", "F", "V", "T", "G", "B"],
		"Right Index": ["Y", "H", "N", "U", "J", "M"],
		"Right Middle": ["I", "K"],
		"Right Ring": ["O", "L"],
		"Right Pinky": ["P"],
	},
	"AZERTY": {
		"Left Pinky": ["A", "Q", "W"],
		"Left Ring": ["Z", "S", "X"],
		"Left Middle": ["E", "D", "C"],
		"Left Index": ["R", "F", "V", "T", "G", "B"],
		"Right Index": ["Y", "H", "N", "U", "J"],
		"Right Middle": ["I", "K"],
		"Right Ring": ["O", "L"],
		"Right Pinky": ["P", "M"],
	},
	"Dvorak": {
		"Left Pinky": ["A", "Q"],
		"Left Ring": ["O", "J"],
		"Left Middle": ["E", "K"],
		"Left Index": ["P", "U", "Y", "I", "X"],
		"Right Index": ["G", "C", "R", "H", "T", "D"],
		"Right Middle": ["N"],
		"Right Ring": ["S"],
		"Right Pinky": ["L"],
	},
}

static func layout_names() -> Array:
	return LAYOUTS

## Returns [{hand: String, count: int}], sorted worst-first, for the
## player's current weak_letter_counts under the given layout.
static func hand_report(weak_letter_counts: Dictionary, layout: String) -> Array:
	var map: Dictionary = _HAND_MAP.get(layout, _HAND_MAP["QWERTY"])
	var totals := {}
	for hand in map.keys():
		totals[hand] = 0
	for letter in weak_letter_counts.keys():
		var upper = String(letter).to_upper()
		for hand in map.keys():
			if map[hand].has(upper):
				totals[hand] += weak_letter_counts[letter]
				break
	var out: Array = []
	for hand in totals.keys():
		if totals[hand] > 0:
			out.append({"hand": hand, "count": totals[hand]})
	out.sort_custom(func(a, b): return a.count > b.count)
	return out
