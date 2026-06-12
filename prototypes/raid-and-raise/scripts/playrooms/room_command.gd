class_name RoomCommand
extends PlayroomBase
## The command grammar (§8.1): lasso, tap-to-send, drag Relish, selection
## expiry — and the Wits hold-vs-drift rule when the order completes.

func _setup() -> void:
	spawn_relish(room_point(0.5, 0.8))
	for i in 2:
		_minion(5.0, room_point(0.35 + 0.3 * i, 0.65))
	for i in 3:
		_minion(0.0, room_point(0.3 + 0.2 * i, 0.72))
	spawn_bag(room_point(0.25, 0.15), 4.0, "Bag")
	spawn_bag(room_point(0.75, 0.15), 4.0, "Bag")
	add_button("Spawn 5 chaff", func():
		for i in 5:
			battlefield.spawn_unit(EntityFactory.make_chaff(1.0), room_point(randf_range(0.3, 0.7), 0.6)))
	add_button("Reset", func(): get_tree().get_first_node_in_group("rr_main").reset_room())
	info.text = "COMMAND ROOM — lasso a group (close the loop), tap to send them; tap empty ground to move Relish; drag starting on Relish to draw her path.\nSelection expires after 2s unused. After arriving: W5 units HOLD the spot, W0 units drift back to autopilot in ~2s."

func _minion(wits: float, at: Vector2) -> void:
	var u := EntityFactory.make_custom({
		"kind": RRUnit.Kind.PERMANENT, "faction": RRUnit.Faction.PLAYER,
		"stats": {"power": 2.0, "speed": 2.0, "wits": wits},
		"name": "W%d" % int(wits),
		"color": Color(0.65, 0.88, 0.95) if wits >= 3.0 else Color(0.62, 0.78, 0.6),
	})
	battlefield.spawn_unit(u, at)
