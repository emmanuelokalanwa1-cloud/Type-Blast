class_name WordManager
extends Node

## Owns the falling word labels: spawning, movement, and picking which word
## pool to draw from (difficulty / theme / weak-key practice).

signal word_missed(label: Label)

const POWERUP_WORDS := {
	"FREEZE": "freeze",
	"SLOWMO": "slowmo",
	"BONUS": "bonus_life",
}
const POWERUP_CHANCE := 0.12
const POWERUP_COLOR := Color.SKY_BLUE

var word_colors = [Color.CYAN, Color.GREEN_YELLOW, Color.MAGENTA, Color.ORANGE, Color.DEEP_SKY_BLUE, Color.HOT_PINK, Color.GOLD]
var active_words: Array = []

var _label_template: Label
var _container: Node
var _game_state: GameState

# --- WORD REPEAT FIX --------------------------------------------------
# spawn_word() used to call current_pool().pick_random() every time -
# pure random, which can (and does) pick the same word again soon after,
# no matter how large the pool actually is. Two separate fixes:
#
# 1. Shuffle-bag: instead of an independent random roll each spawn, shuffle
#    a full copy of the current pool once and hand out words from it in
#    order, only reshuffling once every word in that batch has been used.
#    Guarantees no word repeats until everything else in the pool has come
#    up at least once - the same trick the music shuffle uses.
# 2. On-screen duplicate guard: separately, nothing stopped the exact same
#    word from being spawned while an identical one was still falling,
#    which reads as "it just repeated" even faster than the shuffle-bag
#    issue. spawn_word() now rerolls (bounded) if the picked word is
#    already active on screen.
var _word_shuffle_queue: Array = []
var _word_shuffle_pool_key: String = ""

func setup(label_template: Label, container: Node, game_state: GameState) -> void:
	_label_template = label_template
	_container = container
	_game_state = game_state

func clear_words() -> void:
	for l in active_words:
		if is_instance_valid(l):
			l.queue_free()
	active_words.clear()

func current_pool() -> Array:
	var theme_pool = WordBank.get_theme_pool(_game_state.selected_theme)
	var pool = WordBank.pool_for_difficulty(theme_pool, _game_state.selected_difficulty)
	if _game_state.weak_keys_mode:
		var weak_letters = _game_state.get_weak_letters()
		if weak_letters.size() > 0:
			var biased = pool.filter(func(w): return weak_letters.any(func(c): return String(w).contains(c)))
			if biased.size() >= 4:
				return biased
	return pool

# Identifies which pool config the current shuffle bag was built from, so
# switching theme/difficulty/weak-keys mid-session correctly starts a
# fresh bag instead of handing out leftover words from the old pool.
func _pool_key() -> String:
	return "%s|%s|%s" % [_game_state.selected_theme, _game_state.selected_difficulty, _game_state.weak_keys_mode]

func _pick_word_no_repeat(pool: Array) -> String:
	if pool.is_empty():
		return ""
	var key := _pool_key()
	if key != _word_shuffle_pool_key or _word_shuffle_queue.is_empty():
		_word_shuffle_queue = pool.duplicate()
		_word_shuffle_queue.shuffle()
		_word_shuffle_pool_key = key
	return _word_shuffle_queue.pop_back()

func _is_word_currently_active(word: String) -> bool:
	for label in active_words:
		if is_instance_valid(label) and String(label.get_meta("word")) == word:
			return true
	return false

# Pulls from the shuffle bag, and rerolls (bounded, so a very small or
# heavily-filtered pool can't loop forever) if that word is already
# falling on screen right now.
func _pick_regular_word() -> String:
	var pool := current_pool()
	if pool.is_empty():
		return "WORD"
	var word := _pick_word_no_repeat(pool)
	var attempts := 0
	while _is_word_currently_active(word) and attempts < 6:
		word = _pick_word_no_repeat(pool)
		attempts += 1
	return word

func spawn_word(level: int) -> Label:
	var new_label: Label = _label_template.duplicate()
	_container.add_child(new_label)
	new_label.visible = true

	var is_boss = (level % 5 == 0 and randf() < 0.2)
	var is_powerup = (not is_boss) and randf() < POWERUP_CHANCE

	var word_text: String
	var random_color: Color
	if is_powerup:
		var keys = POWERUP_WORDS.keys()
		word_text = keys[randi() % keys.size()]
		random_color = POWERUP_COLOR
	elif is_boss:
		word_text = WordBank.BOSS_WORDS.pick_random()
		random_color = Color.GOLD
	else:
		word_text = _pick_regular_word()
		random_color = word_colors.pick_random()

	new_label.text = word_text
	new_label.set_meta("word", word_text)
	new_label.set_meta("is_boss", is_boss)
	new_label.set_meta("is_powerup", is_powerup)
	if is_powerup:
		new_label.set_meta("powerup_type", POWERUP_WORDS[word_text])
	new_label.modulate = random_color
	new_label.set_meta("base_color", random_color)
	new_label.set_meta("speed_mult", 0.5 if is_boss else 1.0)
	
	# Base sizes were tuned for a wide (~860px+) reference screen. On a
	# narrower phone that made words look oversized relative to how much
	# horizontal room they actually have to fall through, so scale down
	# proportionally (never scale up past the original size).
	var vp_width: float = _container.get_viewport_rect().size.x
	var font_scale: float = clamp(vp_width / 860.0, 0.6, 1.0)
	var base_font_size: int = 48 if (is_boss or is_powerup) else 32
	new_label.add_theme_font_size_override("font_size", roundi(base_font_size * font_scale))

	# --- Sleek Text Drop Shadow Configuration ---
	new_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	new_label.add_theme_constant_override("shadow_offset_x", 2)
	new_label.add_theme_constant_override("shadow_offset_y", 2)
	new_label.add_theme_constant_override("shadow_outline_size", 1)

	# Old fixed 300px side margins left only a ~120px spawn corridor on a
	# 720px-wide phone, so words landed almost on top of each other and
	# looked like one giant overlapping block. Scale the margin to the
	# screen instead, so there's always a wide, proportional spawn band.
	var side_margin: float = clamp(vp_width * 0.12, 40.0, 300.0)
	var spawn_min: float = side_margin
	var spawn_max: float = max(vp_width - side_margin, spawn_min + 1.0)
	new_label.position = Vector2(randf_range(spawn_min, spawn_max), -50)
	active_words.append(new_label)
	return new_label

func update_positions(delta: float, base_fall_speed: float, score: int, slow_mo_factor: float, screen_height: float) -> void:
	# ORIENTATION FIX: fall speed used to be flat pixels/second, tuned
	# against a ~1280px-tall portrait screen. Rotate to landscape (often
	# only ~700-800px tall) and words covered half the distance in the
	# same time - reaction time got cut roughly in half, which is what
	# made landscape feel broken rather than just differently laid out.
	# Scaling speed to the actual available height keeps fall TIME (not
	# raw speed) roughly consistent across orientations. Clamped so a
	# very tall screen can't make things slower than originally tuned,
	# and a very short one can't make them unfairly fast.
	const REFERENCE_FALL_HEIGHT := 1280.0
	var fall_scale: float = clamp(screen_height / REFERENCE_FALL_HEIGHT, 0.45, 1.0)

	for i in range(active_words.size() - 1, -1, -1):
		var label = active_words[i]
		if is_instance_valid(label):
			var speed_mult = label.get_meta("speed_mult") if label.has_meta("speed_mult") else 1.0
			var current_fall_speed = (base_fall_speed + (score * 0.05)) * slow_mo_factor * speed_mult * fall_scale
			label.position.y += current_fall_speed * delta
			label.position.x += sin(label.position.y * 0.05) * 0.5
			if label.position.y > screen_height - 180:
				active_words.remove_at(i)
				_game_state.note_weak_letters(String(label.get_meta("word")))
				word_missed.emit(label)

func find_prefix_match(upper_text: String) -> bool:
	for label in active_words:
		if is_instance_valid(label) and String(label.get_meta("word")).begins_with(upper_text):
			return true
	return false

func find_exact_match(upper_text: String) -> Label:
	for i in range(active_words.size() - 1, -1, -1):
		var label = active_words[i]
		if is_instance_valid(label) and label.get_meta("word") == upper_text:
			return label
	return null

func remove_word(label: Label) -> void:
	active_words.erase(label)
