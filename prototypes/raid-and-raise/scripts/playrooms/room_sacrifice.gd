class_name RoomSacrifice
extends PlayroomBase
## The sacrifice chain (§8.3), one button at a time: chaff dies for Relish →
## then permanents (with the loud warning) → then Relish, and everything is
## lost. Persistence may catch a sacrificed permanent — watch for the rise.

func _setup() -> void:
	GameState.debug.pacifist = true
	_populate()
	add_button("STRIKE RELISH", func(): battlefield.relish_hit(null))
	add_button("Add 3 chaff", func(): _chaff(3))
	add_button("Kill all chaff", battlefield.clear_chaff)
	add_button("Reset room", _reset)
	battlefield.relish_died.connect(_on_relish_died)
	info.text = "SACRIFICE ROOM — press STRIKE RELISH and watch who dies in her place.\nChain: nearest chaff → nearest permanent (warning!) → Relish herself.\nMorrow has Persistence 8 — sacrificed permanents can still rise, once per chamber."

func _populate() -> void:
	spawn_relish(room_point(0.5, 0.5))
	_chaff(3)
	var tank := EntityFactory.make_custom({
		"kind": RRUnit.Kind.PERMANENT, "faction": RRUnit.Faction.PLAYER,
		"stats": {"beef": 5.0}, "name": "Expendable", "color": Color(0.76, 0.7, 0.56),
	})
	battlefield.spawn_unit(tank, room_point(0.3, 0.65))
	var rev := EntityFactory.make_custom({
		"kind": RRUnit.Kind.PERMANENT, "faction": RRUnit.Faction.PLAYER,
		"stats": {"power": 2.0, "persistence": 8.0}, "name": "Morrow (P8)", "color": Color(0.91, 0.78, 0.49),
	})
	battlefield.spawn_unit(rev, room_point(0.7, 0.65))

func _chaff(n: int) -> void:
	for i in n:
		battlefield.spawn_unit(EntityFactory.make_chaff(1.0),
			room_point(randf_range(0.35, 0.65), randf_range(0.3, 0.45)))

func _reset() -> void:
	for u in battlefield.all_units():
		u.queue_free()
	battlefield.relish = null
	_populate()

func _on_relish_died() -> void:
	battlefield.spawn_ding(room_point(0.5, 0.4), "RELISH DIED — in a raid, EVERYTHING is lost", Color(1, 0.3, 0.25))
	await get_tree().create_timer(2.0).timeout
	if is_inside_tree():
		_reset()
