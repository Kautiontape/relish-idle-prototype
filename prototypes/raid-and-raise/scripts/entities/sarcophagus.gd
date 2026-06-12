class_name Sarcophagus
extends Node2D
## Interactable husk source (§9): 1–2 per chamber, 60% husk chance on open.
## Tapped via the command grammar's tap (raid director routes interactable
## taps here before treating them as move orders).

signal opened(s: Sarcophagus)

var is_open := false

func _ready() -> void:
	z_index = -5

func try_open(battlefield) -> void:
	if is_open:
		return
	is_open = true
	queue_redraw()
	if battlefield.rng.randf() < float(ConfigDb.v("rarity", "husk_drop_sarcophagus")):
		var husk_id: String = Loot.roll_husk(battlefield.rng)
		GameState.add_husk(husk_id)
		battlefield.spawn_ding(global_position, "HUSK: %s" % ConfigDb.husk(husk_id)["name"], Color(0.85, 0.75, 1.0))
	else:
		battlefield.spawn_ding(global_position, "empty...", Color(0.6, 0.6, 0.65))
	opened.emit(self)

func contains_point(p: Vector2) -> bool:
	return absf(p.x - global_position.x) < 36.0 and absf(p.y - global_position.y) < 28.0

func _draw() -> void:
	var c := Color(0.5, 0.4, 0.28) if not is_open else Color(0.32, 0.27, 0.2)
	draw_rect(Rect2(-26, -16, 52, 32), c)
	draw_rect(Rect2(-26, -16, 52, 32), Color(0.15, 0.12, 0.08), false, 2.0)
	if is_open:
		draw_rect(Rect2(-20, -10, 40, 20), Color(0.05, 0.05, 0.07))
	else:
		draw_line(Vector2(-18, 0), Vector2(18, 0), Color(0.3, 0.24, 0.16), 2.0)
		# faint shimmer so it reads as interactable
		draw_arc(Vector2.ZERO, 34.0, 0, TAU, 24, Color(1.0, 0.9, 0.5, 0.18), 1.5)
