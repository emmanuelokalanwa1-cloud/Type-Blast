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
		word_text = current_pool().pick_random()
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
	
	new_label.add_theme_font_size_override("font_size", 48 if (is_boss or is_powerup) else 32)
	
	# --- Sleek Text Drop Shadow Configuration ---
	new_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	new_label.add_theme_constant_override("shadow_offset_x", 2)
	new_label.add_theme_constant_override("shadow_offset_y", 2)
	new_label.add_theme_constant_override("shadow_outline_size", 1)
	
	new_label.position = Vector2(randf_range(300, _container.get_viewport_rect().size.x - 300), -50)
	active_words.append(new_label)
	return new_label

func update_positions(delta: float, base_fall_speed: float, score: int, slow_mo_factor: float, screen_height: float) -> void:
	for i in range(active_words.size() - 1, -1, -1):
		var label = active_words[i]
		if is_instance_valid(label):
			var speed_mult = label.get_meta("speed_mult") if label.has_meta("speed_mult") else 1.0
			var current_fall_speed = (base_fall_speed + (score * 0.05)) * slow_mo_factor * speed_mult
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
