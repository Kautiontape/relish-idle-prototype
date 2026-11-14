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
		# the guarded detour's guard comes out of the fort's own count: the same bodies, mass and motes, placed
		var guard := RaidLogic.detour_guard(fort_id, layout, tier, cfg)
		var spots := RaidLogic.populate_enemies(fort_id, layout, maxi(0, n - guard.size()), tier, cfg)
		for s in spots + guard:
			var u: RaidUnit = _raid.spawn_unit("enemy", s["kind"], s["pos"])
			u.mass = mpe
			u.home_room = layout["rooms"][s["room"]]
		for i in guard.size():
			var g: RaidUnit = _raid.enemies[_raid.enemies.size() - guard.size() + i]
			g.sentry = true   # it holds its post (raid.json detour)
			_raid.detour_guard.append(g)
	_place_cache(tier)
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
		u.power = float((e.get("stats", {}) as Dictionary).get("power", 0.0))
		u.slots = maxi(1, int(e.get("filled_slots", 1)))


## The guarded detour's cache (raid.json detour, loot.json cache): relic pickups at the site, labelled CACHE.
func _place_cache(tier: int) -> void:
	var site := RaidLogic.detour_site(_raid.layout, tier, _raid.rcfg())
	if site.is_empty():
		return
	var lc: Dictionary = ConfigDb.data.get("loot", {}).get("cache", {})
	var n := int((lc.get("relics_by_tier", {}) as Dictionary).get(str(clampi(tier, 1, 4)), 0))
	var sp := float(lc.get("spread_px", 18.0))
	for i in n:
		var pk := RaidPickup.new()
		pk.raid = _raid
		pk.kind = "relic"
		pk.cache = true
		pk.position = _raid.resolve_walls((site["pos"] as Vector2) + Vector2(sp * (float(i) - float(n - 1) * 0.5), 0.0), 6.0)
		_raid.units_root.add_child(pk)
		_raid.detour_cache.append(pk)
