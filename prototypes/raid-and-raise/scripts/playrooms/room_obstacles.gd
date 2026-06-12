class_name RoomObstacles
extends PlayroomBase
## Obstacle course (user-requested): pillars and a chicane to stress pathing —
## NavigationAgent2D avoidance through gaps, and the lasso-path grammar
## (close the loop around the squad, keep dragging, they follow your line
## through the course). Nav paths drawn by default.

func _obstacles() -> Array:
	return [
		_rect(0.25, 0.22, 90, 90),    # pillar pair, top
		_rect(0.75, 0.22, 90, 90),
		_bar(0.0, 0.6, 0.45),         # chicane: left bar...
		_bar(0.55, 1.0, 0.62),        # ...right bar below it
		_diamond(0.5, 0.82, 62),      # diamond near the squad spawn
	]

func _rect(nx: float, ny: float, w: float, h: float) -> PackedVector2Array:
	var c := room_point(nx, ny)
	return PackedVector2Array([
		c + Vector2(-w / 2, -h / 2), c + Vector2(w / 2, -h / 2),
		c + Vector2(w / 2, h / 2), c + Vector2(-w / 2, h / 2),
	])

func _bar(nx0: float, nx1: float, ny: float) -> PackedVector2Array:
	var a := room_point(nx0, ny)
	var b := room_point(nx1, ny)
	return PackedVector2Array([
		Vector2(a.x, a.y - 18), Vector2(b.x, b.y - 18),
		Vector2(b.x, b.y + 18), Vector2(a.x, a.y + 18),
	])

func _diamond(nx: float, ny: float, r: float) -> PackedVector2Array:
	var c := room_point(nx, ny)
	return PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0),
	])

func _setup() -> void:
	GameState.debug.pacifist = true
	GameState.debug.show_paths = true
	spawn_relish(room_point(0.5, 0.95))
	for i in 2:
		_minion(5.0, room_point(0.3 + 0.4 * i, 0.9))
	for i in 3:
		_minion(0.0, room_point(0.3 + 0.2 * i, 0.93))
	add_button("Wave: 6 rats (top)", func(): _wave("tomb_rat", 6))
	add_button("Wave: 2 guards (top)", func(): _wave("guard", 2))
	add_button("Clear enemies", func(): battlefield.clear_faction(RRUnit.Faction.ENEMY))
	add_button("Spawn 5 chaff", func():
		for i in 5:
			battlefield.spawn_unit(EntityFactory.make_chaff(1.0), room_point(randf_range(0.35, 0.65), 0.88)))
	add_button("Reset", func(): get_tree().get_first_node_in_group("rr_main").reset_room())
	info.text = "OBSTACLE COURSE — pathing playground.\nLasso your squad and KEEP DRAGGING: the closed loop selects, the rest of the stroke is the path they follow live (watch it thread the chicane).\nTap sends nav-pathing instead; spawn waves up top and watch them route down. Esc deselects."

func _minion(wits: float, at: Vector2) -> void:
	var u := EntityFactory.make_custom({
		"kind": RRUnit.Kind.PERMANENT, "faction": RRUnit.Faction.PLAYER,
		"stats": {"power": 2.0, "speed": 3.0, "wits": wits},
		"name": "W%d" % int(wits),
		"color": Color(0.65, 0.88, 0.95) if wits >= 3.0 else Color(0.62, 0.78, 0.6),
	})
	battlefield.spawn_unit(u, at)

func _wave(type: String, count: int) -> void:
	for i in count:
		var u := EntityFactory.make_enemy(type)
		battlefield.spawn_unit(u, room_point(randf_range(0.2, 0.8), randf_range(0.03, 0.08)))
