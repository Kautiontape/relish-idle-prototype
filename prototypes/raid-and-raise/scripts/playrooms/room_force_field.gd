class_name RoomForceField
extends PlayroomBase
## The magnetism room (user-requested): watch enemies magnet onto the Beef
## wall, bend toward Charm, and give ground to Dread. Pacifist by default so
## you watch pure movement; sliders are the live §6 coefficients.

var wall: RRUnit
var lure: RRUnit
var pusher: RRUnit

func _setup() -> void:
	GameState.debug.pacifist = true
	GameState.debug.show_fields = true
	spawn_relish(room_point(0.5, 0.95))
	wall = _post(room_point(0.5, 0.55), {"beef": 8.0, "wits": 5.0}, "Wall", Color(0.76, 0.7, 0.56))
	lure = _post(room_point(0.18, 0.5), {"charm": 5.0, "wits": 5.0}, "Lure", Color(0.88, 0.62, 0.78))
	pusher = _post(room_point(0.82, 0.5), {"dread": 5.0, "wits": 5.0}, "Pusher", Color(0.62, 0.66, 0.88))
	add_button("Wave: 6 rats", func(): _wave("tomb_rat", 6))
	add_button("Wave: 4 guards", func(): _wave("guard", 4))
	add_button("Wave: 1 brute", func(): _wave("brute", 1))
	add_button("Clear enemies", func(): battlefield.clear_faction(RRUnit.Faction.ENEMY))
	add_button("Damage on/off", func(): GameState.debug.pacifist = not GameState.debug.pacifist)
	add_slider("Charm", 0, 10, 1, 5, func(v): lure.stats.charm = v)
	add_slider("Dread", 0, 10, 1, 5, func(v): pusher.stats.dread = v)
	add_slider("Field strength", 0, 60, 1, float(ConfigDb.v("stats", "field_strength")),
		func(v): ConfigDb.set_v("stats", "field_strength", v))
	add_slider("Field radius", 50, 600, 10, float(ConfigDb.v("stats", "field_radius_px")),
		func(v): ConfigDb.set_v("stats", "field_radius_px", v))
	add_slider("Bias clamp", 0.0, 1.0, 0.05, float(ConfigDb.v("stats", "field_bias_clamp")),
		func(v): ConfigDb.set_v("stats", "field_bias_clamp", v))
	info.text = "FORCE FIELD ROOM — spawn waves from the top, watch their paths bend.\nWall (center): proximity×size magnet. Lure (left): Charm pull. Pusher (right): Dread push.\nDamage is OFF by default — pure steering."

func _post(at: Vector2, stats: Dictionary, label: String, color: Color) -> RRUnit:
	var u := EntityFactory.make_custom({
		"kind": RRUnit.Kind.PERMANENT,
		"faction": RRUnit.Faction.PLAYER,
		"stats": stats,
		"base_hp": 200.0,
		"name": label,
		"color": color,
	})
	battlefield.spawn_unit(u, at)
	u.cmd = RRUnit.Cmd.HOLD  # high Wits → holds the post
	return u

func _wave(type: String, count: int) -> void:
	for i in count:
		var u := EntityFactory.make_enemy(type)
		battlefield.spawn_unit(u, room_point(randf_range(0.25, 0.75), randf_range(0.04, 0.1)))
