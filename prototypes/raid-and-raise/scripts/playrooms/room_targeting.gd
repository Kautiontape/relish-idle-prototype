class_name RoomTargeting
extends PlayroomBase
## Wits vs the default brain. A frozen lineup of mixed Beef; spawn hunters and
## watch who they pick. Wits ≥ 3 locks the highest-Beef enemy and sticks;
## below that it's proximity × size. Target lines on by default.

var _next_wits := 5.0

func _setup() -> void:
	GameState.debug.pacifist = true
	GameState.debug.freeze = true
	GameState.debug.show_targets = true
	spawn_relish(room_point(0.5, 0.95))
	_lineup()
	add_button("Spawn hunter (Wits slider)", func(): _hunter(_next_wits))
	add_button("Spawn Wits-0 brawler", func(): _hunter(0.0))
	add_button("Clear minions", func():
		for u in battlefield.living(RRUnit.Faction.PLAYER):
			if u.kind != RRUnit.Kind.RELISH:
				u.queue_free())
	add_button("Reset lineup", func():
		battlefield.clear_faction(RRUnit.Faction.ENEMY)
		_lineup())
	add_button("Damage on/off", func(): GameState.debug.pacifist = not GameState.debug.pacifist)
	add_slider("Hunter wits", 0, 8, 1, 5, func(v): _next_wits = v)
	info.text = "TARGETING ROOM — red lines show who each unit wants.\nWits ≥ 3 locks the fattest target in the room and sticks until it's down (anti-Beef damage bonus). Wits 0 chases the closest-biggest thing.\nTurn damage on to watch the Wits bonus melt the giant."

func _lineup() -> void:
	spawn_bag(room_point(0.15, 0.2), 0.0, "Beef 0")
	spawn_bag(room_point(0.38, 0.2), 2.0, "Beef 2")
	spawn_bag(room_point(0.62, 0.2), 7.0, "Beef 7")
	spawn_bag(room_point(0.85, 0.22), 12.0, "Beef 12")

func _hunter(wits: float) -> void:
	var u := EntityFactory.make_custom({
		"kind": RRUnit.Kind.PERMANENT,
		"faction": RRUnit.Faction.PLAYER,
		"stats": {"power": 3.0, "speed": 3.0, "wits": wits},
		"name": "W%d" % int(wits),
		"color": Color(0.65, 0.88, 0.95) if wits >= 3 else Color(0.62, 0.78, 0.6),
	})
	battlefield.spawn_unit(u, room_point(randf_range(0.3, 0.7), 0.85))
