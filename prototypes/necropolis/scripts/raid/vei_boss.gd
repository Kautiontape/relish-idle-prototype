extends "res://scripts/raid/raid.gd"
## The BOSS scene: assault on Vei herself. Reuses the raid machinery; the
## backlog is the horde — chaff stream in from the south doors while it lasts.

var backlog_spent := 0.0
var _stream_acc := 0.0
var _remnants: Array = []


func demo_seed() -> Dictionary:
	return {"fort_id": "vei", "name": "Vei's Domain", "tier": 5,
		"cap": 800.0, "living": 500.0, "undead": 0.0, "dead": 60.0,
		"boss": true, "quality": 2.1, "backlog": 9421.0,
		"army": {"soldier": 41, "elite": 9}, "vei_capacity": 50.0, "odds": 0.61}


func _build_extra() -> void:
	var b: Dictionary = rcfg().get("boss", {})
	ally_engage_px = 5000.0  # the horde marches the full arena to reach her
	backlog_left = float(seed_data.get("backlog", 0.0))
	var arena: Vector2 = layout["size"]

	# Vei at the far north end
	vei = RaidVei.new()
	vei.position = Vector2(arena.x * 0.5, float(layout["wall_t"]) + 210.0)
	units_root.add_child(vei)
	vei.configure(self, float(seed_data.get("odds", 0.5)))

	# her honor guard (living, orange-gold)
	var guard_mass: float = float(b.get("guard", {}).get("mass", 10.0))
	for i in int(b.get("initial_guards", 8)):
		var ang := PI * 0.5 + (float(i) / maxf(1.0, float(b.get("initial_guards", 8)) - 1.0) - 0.5) * 1.8
		var pos: Vector2 = vei.position + Vector2(vei.radius + 70.0 + (i % 2) * 40.0, 0).rotated(ang)
		var g := spawn_unit("enemy", "guard", resolve_walls(pos, 10.0))
		g.mass = guard_mass

	# the brought army spawns around Relish
	var army: Dictionary = seed_data.get("army", {})
	_spawn_army("soldier", int(army.get("soldier", 0)))
	_spawn_army("elite", int(army.get("elite", 0)))


func _spawn_army(kind: String, count: int) -> void:
	for i in count:
		var ang := randf() * TAU
		var dist := 46.0 + randf() * 130.0
		var pos: Vector2 = relish.position + Vector2(dist, 0).rotated(ang)
		spawn_unit("ally", kind, resolve_walls(pos, 10.0))


func _post_physics(delta: float) -> void:
	# THE BACKLOG IS THE HORDE: chaff stream in from the south doors while it lasts
	if backlog_left <= 0.0 or _ended:
		return
	var b: Dictionary = rcfg().get("boss", {})
	var alive_chaff := 0
	for a in allies:
		if is_instance_valid(a) and a.alive and a.kind == "chaff":
			alive_chaff += 1
	if alive_chaff >= int(b.get("max_chaff_alive", 130)):
		return  # arena is saturated; the backlog waits at the doors
	var rate: float = float(b.get("stream_rate_base", 2.0)) \
		+ backlog_left / float(b.get("stream_backlog_div", 1500.0))
	_stream_acc += rate * delta
	while _stream_acc >= 1.0 and backlog_left > 0.0:
		_stream_acc -= 1.0
		_spawn_stream_chaff(b)


func _spawn_stream_chaff(b: Dictionary) -> void:
	var south_doors: Array = []
	for d in layout["doors"]:
		if d["side"] == "s":
			south_doors.append(d)
	if south_doors.is_empty():
		south_doors = layout["doors"]
	var door: Dictionary = south_doors[randi_range(0, south_doors.size() - 1)]
	var pos: Vector2 = door["inner"] + Vector2(randf_range(-55, 55), randf_range(-16, 4))
	spawn_unit("ally", "chaff", resolve_walls(pos, 8.0), true)
	var drain := minf(float(b.get("stream_mass_per_spawn", 8.0)), backlog_left)
	backlog_left -= drain
	backlog_spent += drain


## Allies see Vei as a target too.
func nearest_enemy_of(pos: Vector2):
	var best = super.nearest_enemy_of(pos)
	if vei != null and is_instance_valid(vei) and vei.alive:
		var dv: float = pos.distance_to(vei.global_position)
		if best == null or dv < pos.distance_to(best.global_position):
			if dv < ally_engage_px:
				return vei
	return best


## Dead undead leave grey remnants — the matter Vei's REVIVE recycles.
func _on_ally_died(u: RaidUnit) -> void:
	var b: Dictionary = rcfg().get("boss", {})
	_remnants = _remnants.filter(func(r) -> bool: return is_instance_valid(r))
	if _remnants.size() >= int(b.get("remnant_cap", 40)):
		return
	var pile := RaidPile.new()
	pile.raid = self
	pile.small = true
	pile.mass = float(b.get("remnant_mass", 3.0))
	pile.position = u.global_position
	units_root.add_child(pile)
	_remnants.append(pile)


func on_vei_died() -> void:
	if _ended:
		return
	_ended = true
	trance.force_end()
	hud.flash(Color("#fff3d0"))
	RaidFx.ring(fx_root, vei.global_position, Color("#fff3d0"), 700.0, 1.1, 8.0)
	RaidFx.ring(fx_root, vei.global_position, Color(1, 1, 1, 0.9), 400.0, 0.8, 5.0)
	get_tree().create_timer(1.2).timeout.connect(func() -> void: _finish(_boss_result(true, false)))


func _exit_result() -> Dictionary:
	return _boss_result(false, false)


func _death_result() -> Dictionary:
	return _boss_result(false, true)


func _boss_result(won: bool, died: bool) -> Dictionary:
	return {"fort_id": str(seed_data.get("fort_id", "vei")), "won": won,
		"relish_died": died, "backlog_spent": backlog_spent,
		"army_lost": army_lost.duplicate()}
