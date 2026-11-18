class_name RaidRaise
extends RefCounted
## Circle -> undead: a released, scored circle consumes the enclosed essence and raises one
## undead per mote (MECHANICS 5.3); the boss raises through VeiBoss.perform_raise. RefCounted: the
## raid calls `perform` / `show_feedback` from the trance and owns the scene state it touches.

var _raid: Node2D
var _last_feedback: RaidTraceFeedback = null


func _init(p_raid: Node2D) -> void:
	_raid = p_raid


func show_feedback(g: Dictionary, trace: PackedVector2Array) -> void:
	var fb := RaidTraceFeedback.new()
	fb.trace = trace
	fb.fitted_center = g["center"]
	fb.fitted_radius = g["radius"]
	fb.score = int(g["score"])
	fb.valid = g["valid"]
	_raid.fx_root.add_child(fb)
	_last_feedback = fb


## The essence motes a ring at `center` / `radius` takes in: every raid_essence mote not already absorbing whose
## centre is within the radius. `perform` raises one undead per mote in this list; the live readout counts it.
func motes_inside(center: Vector2, radius: float) -> Array:
	var picked: Array = []
	for e in _raid.get_tree().get_nodes_in_group("raid_essence"):
		if is_instance_valid(e) and not e.absorbing and e.global_position.distance_to(center) <= radius:
			picked.append(e)
	return picked


func perform(g: Dictionary) -> void:
	var score := int(g["score"])
	var center: Vector2 = g["center"]
	var radius: float = g["radius"]
	var picked: Array = motes_inside(center, radius)
	if picked.is_empty():
		return
	var motes: Array = []
	for e in picked:
		motes.append({"mass": e.mass, "recycled": e.recycled})
		e.absorb()
	_raid.endings.clamp_banked()
	var cfg: Dictionary = _raid.rcfg()
	var spec := RaidLogic.raise_spec_v2(score, motes, cfg, ConfigDb.data.get("circle", {}))
	var count := int(spec["count"])
	if count <= 0:
		return
	_raid.ledger_v2.on_raise(score, float(spec["fresh_mass"]), count)
	_raid.first_raise_done = true
	RaidSound.play("raise")
	_raid.raises += 1
	var tier := str(spec["tier"])
	if _last_feedback != null and is_instance_valid(_last_feedback):
		_last_feedback.raised_n = count
		_last_feedback.raised_tier = tier
		_last_feedback.raised_mult = float(spec["stat_mult"])
	var mult := float(spec["stat_mult"])
	var stats := RaidLogic.undead_stats(mult, tier, cfg)
	var masses: Array = spec["unit_masses"]
	_spawn_ring(count, func(i: int, pos: Vector2) -> void:
		_raid.spawn_ally_v2("raised", tier, mult, float(masses[i]), "", stats, pos, true))


## Place `count` raised units on a jittered ring around Relish (`spawn` gets the index and the
## wall-resolved position), then the raise ring fx.
func _spawn_ring(count: int, spawn: Callable) -> void:
	var ring_px: float = float(_raid.rcfg().get("raise", {}).get("spawn_ring_px", 52.0))
	var rng: RandomNumberGenerator = _raid.rng_combat
	var rp: Vector2 = _raid.relish.global_position
	for i in count:
		var ang := TAU * i / float(count) + rng.randf() * 0.8
		var pos: Vector2 = rp + Vector2(ring_px + rng.randf_range(-10, 26), 0).rotated(ang)
		spawn.call(i, _raid.resolve_walls(pos, 10.0))
	RaidFx.ring(_raid.fx_root, rp, Palette.c("undead"), ring_px + 26.0, 0.5, 3.0)
