class_name RoomTranceGym
extends PlayroomBase
## §12 Step 1, kept alive as a playroom: the circle, alone. Dummy essence
## auto-scatters; trace, get graded, watch chaff pop. The GATE question lives
## here: does tracing circles feel good in isolation?

const TARGET_ESSENCE := 12
var _respawn_cd := 0.0
var _score_label: Label

func _setup() -> void:
	spawn_relish(room_point(0.5, 0.85))
	_scatter()
	add_button("Scatter essence", _scatter)
	add_button("Clear chaff", battlefield.clear_chaff)
	add_button("Spawn punching bag", func(): spawn_bag(room_point(0.5, 0.25), 6.0, "Bag"))
	info.text = "TRANCE GYM — hold the corner button (touch) or just RIGHT-CLICK-DRAG a circle around glowing essence; release to summon. (SPACE also holds the trance.)\nBig sloppy circle = many weak idiots. Small perfect circle = few strong ones."
	_score_label = Label.new()
	_score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_score_label.position = Vector2(-240, 90)
	_score_label.size = Vector2(230, 400)
	_score_label.add_theme_font_size_override("font_size", 15)
	ui.add_child(_score_label)

func _scatter() -> void:
	for i in TARGET_ESSENCE:
		battlefield.spawn_essence(room_point(randf_range(0.15, 0.85), randf_range(0.12, 0.62)), 1)

func _process(delta: float) -> void:
	_respawn_cd -= delta
	if battlefield.essence_list().size() < TARGET_ESSENCE and _respawn_cd <= 0.0:
		_respawn_cd = 0.8
		battlefield.spawn_essence(room_point(randf_range(0.15, 0.85), randf_range(0.12, 0.62)), 1)
	var lines := ["scores (last 10):"]
	var scores: Array = GameState.circle_scores
	for i in range(maxi(0, scores.size() - 10), scores.size()):
		lines.append("  %d" % scores[i])
	if scores.size() > 0:
		lines.append("avg: %.0f" % GameState.average_score())
	_score_label.text = "\n".join(lines)
