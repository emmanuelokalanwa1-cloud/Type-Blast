class_name BigWordBanner
extends CanvasLayer

## Arcade-announcer flourish #1: catching a genuinely long/hard word (9+
## letters) slams a big bold banner across the screen for a beat, like a
## fighting-game "finish" callout - minus anything violent. Purely cosmetic,
## on a cooldown so it can't spam during a run full of long words.
## Self-connecting: main.gd only ever calls setup() once.

const MIN_LEN := 9
const COOLDOWN_SEC := 6.0
const PHRASES := [
	"CRUSHED IT!",
	"DESTROYED!",
	"WRECKED THAT WORD!",
	"ANNIHILATED!",
	"OBLITERATED!",
]

var _label: Label
var _cooldown_left := 0.0

func setup(typing_controller: TypingController) -> void:
	layer = 55
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", 40)
	_label.modulate = Color(1.0, 0.25, 0.2, 0.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.pivot_offset = Vector2.ZERO
	add_child(_label)
	typing_controller.word_matched.connect(_on_word_matched)

func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta

func _on_word_matched(label: Label) -> void:
	if _cooldown_left > 0.0 or not is_instance_valid(label):
		return
	if label.text.strip_edges().length() < MIN_LEN:
		return
	_cooldown_left = COOLDOWN_SEC
	_slam(PHRASES[randi() % PHRASES.size()])

func _slam(text: String) -> void:
	_label.text = text
	_label.scale = Vector2(1.6, 1.6)
	_label.pivot_offset = _label.size / 2.0
	_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_label, "scale", Vector2(1, 1), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.tween_property(_label, "modulate:a", 0.0, 0.35)
