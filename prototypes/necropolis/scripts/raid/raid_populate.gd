class_name RaidPopulate
extends RefCounted
## Who is on the field when a dungeon scene builds: the fortress's living, plus the seed's
## garrison, starters and party around Relish. The boss scene builds its own cast.

var _raid: Node2D


func _init(p_raid: Node2D) -> void:
	_raid = p_raid


## Standard fortress population from the v2 seed. The boss scene replaces this.
func populate(cfg: Dictionary, fort_id: String, tier: int) -> void:
	var sd: Dictionary = _raid.seed_data
	var layout: Dictionary = _raid.layout
	var relish: RaidRelish = _raid.relish
	var living := float(sd.get("living", 0.0))
	var cap := float(sd.get("fort", {}).get("cap", 100.0))
	if living > 0.05:
		var n := RaidLogic.enemy_count(living, cap, cfg)
		var mpe := living / n
		var spots := RaidLogic.populate_enemies(fort_id, layout, n, tier, cfg)
		for s in spots:
			var u: RaidUnit = _raid.spawn_unit("enemy", s["kind"], s["pos"])
			u.mass = mpe
			u.home_room = layout["rooms"][s["room"]]
	# garrison: exactly the seed's units, each carrying garrison_mass_div of ledger mass
	var gn := int(sd.get("garrison_units", 0))
	var gdiv := float(sd.get("garrison_mass_div", 10.0))
	var gmult := float(cfg.get("garrison", {}).get("stat_mult", 1.0))
	var gstats := RaidLogic.undead_stats(gmult, "chaff", cfg)
	for i in gn:
		var ang := TAU * i / maxf(1.0, gn) + 0.4
		var pos: Vector2 = relish.position + Vector2(54.0 + (i % 3) * 22.0, 0).rotated(ang)
		_raid.spawn_ally_v2("garrison", "chaff", gmult, gdiv, "", gstats, _raid.resolve_walls(pos, 8.0))
	# starters: massless chaff
	var sn := int(sd.get("starter_units", 0))
	var smult := float(cfg.get("starter", {}).get("stat_mult", 1.0))
	var sstats := RaidLogic.undead_stats(smult, "chaff", cfg)
	for i in sn:
		var ang := TAU * i / maxf(1.0, sn) + 0.9
		var pos: Vector2 = relish.position + Vector2(96.0 + (i % 2) * 22.0, 0).rotated(ang)
		_raid.spawn_ally_v2("starter", "chaff", smult, 0.0, "", sstats, _raid.resolve_walls(pos, 8.0))
	# party: one big undead per entry
	var party: Array = sd.get("party", [])
	for i in party.size():
		var e: Dictionary = party[i]
		var ang := TAU * i / maxf(1.0, party.size()) - 0.7
		var pos: Vector2 = relish.position + Vector2(150.0, 0).rotated(ang)
		var u: RaidUnit = _raid.spawn_ally_v2("party", "big", 1.0, 0.0, str(e.get("uid", "")),
			RaidLogic.big_undead_stats(e.get("stats", {}), cfg), _raid.resolve_walls(pos, 20.0), false, "big")
		# TODO(api-request #6): party entries carry no filled_slots yet; 1 nested diamond until they do
		u.beef = float((e.get("stats", {}) as Dictionary).get("beef", 0.0))
		u.speed_stat = float((e.get("stats", {}) as Dictionary).get("speed", 0.0))
		u.wits = float((e.get("stats", {}) as Dictionary).get("wits", 0.0))
		u.slots = maxi(1, int(e.get("filled_slots", 1)))
