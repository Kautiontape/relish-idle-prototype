extends RefCounted
## The buildings for real (T2.4; STATE-API §4.3, §5.9, §5.10, §6; MECHANICS §4.4; BALANCE §5):
## cmd_build, cmd_upgrade, cmd_demolish and cmd_cancel_build with every reason in order, payment,
## construction through TownSim's build job, the tier rise and its lots, the caps the buildings
## give, and the catalog agreeing with cmd_build. The influence field is shrunk in memory, so
## substeps stay cheap.

var t := TestUtil.new()
var _base := {}


func _cfgs() -> Dictionary:
	if _base.is_empty():
		_base = TestUtil.configs()
		var fld: Dictionary = _base["realm"]["field"]
		fld["tick_hz"] = 0.01
		fld["w"] = 8
		fld["h"] = 6
	return _base.duplicate(true)


func _mk(cfgs: Dictionary = {}) -> GameState:
	var s := GameState.new(_cfgs() if cfgs.is_empty() else cfgs)
	s.debug_enabled = true
	s.cmd_new_game(1)
	return s


func _bld(s: GameState, lot_id: String) -> Dictionary:
	for b in s.view_town()["buildings"]:
		if b["lot_id"] == lot_id:
			return b
	return {}


func _lot(s: GameState, lot_id: String) -> Dictionary:
	for l in s.view_town()["lots"]:
		if l["id"] == lot_id:
			return l
	return {}


func _cat(s: GameState, building_id: String) -> Dictionary:
	for b in s.view_catalog()["buildings"]:
		if b["building_id"] == building_id:
			return b
	return {}


## Events of a type since the last drain (the queue is cleared by this).
func _evs(s: GameState, type: String) -> Array:
	return s.drain_events().filter(func(e): return e["type"] == type)


## Runs the sim for `secs`, keeping the town solvent: gold and bone are topped up every 10 s, so
## upkeep never idles the buildings under test. Returns the events.
func _run(s: GameState, secs: float) -> Array:
	var evs: Array = []
	var left := secs
	while left > 0.0:
		var dt := minf(left, 10.0)
		s.cmd_debug_grant({"gold": maxf(0.0, 3000.0 - s.town_sim.gold), "bone": maxf(0.0, 1500.0 - s.town_sim.bone)})
		s.cmd_debug_skip_time(dt)
		evs.append_array(s.drain_events())
		left -= dt
	return evs


func _of(evs: Array, type: String) -> Array:
	return evs.filter(func(e): return e["type"] == type)


func run() -> int:
	t.suite("game_state_build")
	_gates_config()
	_build_reasons()
	_build_pays_and_completes()
	_upgrade_reasons()
	_upgrade_works_meanwhile()
	_demolish()
	_cancel()
	_tiers()
	_unpaid_keeps_tier()
	_caps()
	_unpaid_keeps_stores()
	_playthrough()
	_catalog_agrees()
	return t.failures


# -------------------------------------------------- the gate fix and lots ----
func _gates_config() -> void:
	var cfg := _cfgs()
	var b: Dictionary = cfg["buildings"]
	t.ok(b["walls"]["requires"]["tier"] == "village" and b["chapel_of_vats"]["requires"]["tier"] == "village",
		"Walls and the Chapel of Vats are buildable at Village, one tier before the Town they make")
	t.ok(b["reliquary"]["requires"]["tier"] == "town" and b["reliquary"]["requires"]["blueprint"] == "reliquary",
		"the Reliquary is buildable at Town, with its blueprint")
	var tiers: Dictionary = cfg["economy"]["town"]["tiers"]
	t.ok(tiers["hamlet"]["lot_ids"] == ["lot-01", "lot-02", "lot-03", "lot-04", "lot-05", "lot-06", "lot-07", "lot-08"], "Hamlet opens lot-01..lot-08")
	var size := {}
	for l in cfg["town"]["lots"]:
		size[l["id"]] = int(l["size"])
	var prev: Array = []
	for tier in GameState.TIERS:
		var ids: Array = tiers[tier]["lot_ids"]
		t.ok(prev.all(func(id): return ids.has(id)), "%s keeps every lot the tier before it opened" % tier)
		t.ok(ids.all(func(id): return size.has(id)), "%s lists real lots only" % tier)
		prev = ids
	# every building has an unlocked lot of its size in the tier where it first becomes buildable
	for id in b:
		var tier: String = b[id]["requires"]["tier"]
		var need := int(b[id]["lot_size"])
		var fit: Array = (tiers[tier]["lot_ids"] as Array).filter(func(l): return size[l] >= need)
		t.ok(not fit.is_empty(), "%s (size %d) has a lot at %s" % [id, need, tier])
	t.ok((tiers["village"]["lot_ids"] as Array).has("lot-23") and not (tiers["village"]["lot_ids"] as Array).has("lot-24"),
		"lot-23 (Walls) opens at Village, lot-24 only later")
	t.ok((tiers["town"]["lot_ids"] as Array).has("lot-24"), "lot-24 (the Reliquary) opens at Town")


# ----------------------------------------------------------- cmd_build ----
func _build_reasons() -> void:
	var s := _mk()
	var r := s.cmd_build("nope", "lot-99")
	t.ok(r == {"ok": false, "reason": "unknown_building", "cost": {}}, "unknown_building comes before unknown_lot: %s" % [r])
	t.ok(s.cmd_build("house", "lot-99")["reason"] == "unknown_lot", "unknown_lot")
	t.ok(s.cmd_build("statue", "lot-09")["reason"] == "lot_locked", "lot_locked comes before needs_tier (lot-09 is a Village lot)")
	t.ok(s.cmd_build("house", "lot-01")["reason"] == "lot_taken", "lot_taken")
	t.ok(s.cmd_build("inn", "lot-05")["reason"] == "lot_too_small", "lot_too_small comes before needs_tier (the Inn is size 2)")
	t.ok(s.cmd_build("statue", "lot-05")["reason"] == "needs_tier", "needs_tier at Hamlet")
	t.ok(s.cmd_build("embalmer", "lot-05")["reason"] == "needs_tier", "needs_tier comes before needs_blueprint")
	s.town_tier = "village"
	t.ok(s.cmd_build("embalmer", "lot-09")["reason"] == "needs_blueprint", "needs_blueprint")
	s.blueprints.append("embalmer")
	s.town_sim.gold = 0.0
	s.town_sim.bone = 0.0
	t.ok(s.cmd_build("embalmer", "lot-09")["reason"] == "no_gold", "no_gold before no_bone (both short)")
	s.town_sim.gold = 1000.0
	t.ok(s.cmd_build("embalmer", "lot-09")["reason"] == "no_bone", "no_bone")
	s.town_sim.bone = 1000.0
	t.ok(s.cmd_build("embalmer", "lot-09")["reason"] == "no_relics", "no_relics")
	t.ok(s.town_sim.gold == 1000.0 and s.town_sim.bone == 1000.0, "a refusal pays nothing")
	var rv := s.rev
	s.cmd_build("embalmer", "lot-09")
	t.ok(s.rev == rv, "a refusal leaves rev alone")
	# needs_building: the gate exists in the data model, though no building uses it yet
	var cfgs := _cfgs()
	cfgs["buildings"]["house"]["requires"]["building"] = "bakery"
	var b := _mk(cfgs)
	t.ok(b.cmd_build("house", "lot-05")["reason"] == "needs_building", "needs_building (a house needing a bakery)")
	t.ok(_cat(b, "house")["reason"] == "needs_building", "and the catalog says so")
	b.town_sim.place_building("lot-06", "bakery", 1)
	t.ok(b.cmd_build("house", "lot-05")["ok"], "with the bakery built, the house goes up")
	_unique()


## The Crypt is `unique` (buildings.json, the Crypt only): a second one is refused right after
## unknown_lot, and view_catalog says so, while one stands finished or under construction.
func _unique() -> void:
	var cfg: Dictionary = _cfgs()["buildings"]
	var flagged: Array = cfg.keys().filter(func(id): return bool(cfg[id].get("unique", false)))
	t.ok(flagged == ["crypt"], "buildings.json: only the Crypt is unique: %s" % [flagged])
	var s := _mk()
	t.ok(s.cmd_build("crypt", "lot-99")["reason"] == "unknown_lot", "unknown_lot still comes first")
	var r := s.cmd_build("crypt", "lot-13")
	t.ok(r == {"ok": false, "reason": "unique", "cost": {}}, "a second Crypt: unique, before lot_locked (lot-13 is a Village lot): %s" % [r])
	s.town_tier = "village"
	t.ok(s.cmd_build("crypt", "lot-13")["reason"] == "unique", "unique on a free, unlocked lot of its size")
	var c := _cat(s, "crypt")
	t.ok(not c["can_build"] and c["reason"] == "unique" and c["count"] == 1, "view_catalog: can_build false, reason unique")
	# with no Crypt standing it builds; under construction it already counts
	s.town_sim.buildings.erase("lot-01")
	t.ok(_cat(s, "crypt")["can_build"] and _cat(s, "crypt")["reason"] == "", "no Crypt: the catalog offers one")
	t.ok(s.cmd_build("crypt", "lot-13")["ok"], "and the first one builds")
	t.ok(s.cmd_build("crypt", "lot-14")["reason"] == "unique" and _cat(s, "crypt")["reason"] == "unique",
		"one under construction already blocks a second")
	_run(s, 2.0)
	t.ok(_bld(s, "lot-13")["level"] == 1 and s.cmd_build("crypt", "lot-14")["reason"] == "unique", "and so does the finished one")
	t.ok(s.view_big_undead()["cap"] == 4, "one Crypt, so the big-undead cap counts one Crypt's level")


func _build_pays_and_completes() -> void:
	var s := _mk()
	var gold := s.town_sim.gold
	var bone := s.town_sim.bone
	var r := s.cmd_build("house", "lot-05")
	t.ok(r == {"ok": true, "reason": "", "cost": {"gold": 40.0, "bone": 10.0, "relics": 0}}, "build house: ok with its cost: %s" % [r])
	t.ok(s.town_sim.gold == gold - 40.0 and s.town_sim.bone == bone - 10.0, "the cost is paid at once")
	var bl := _bld(s, "lot-05")
	t.ok(bl["state"] == "constructing" and bl["level"] == 0 and bl["progress"] == 0.0 and bl["slots"] == 3, "constructing at level 0 with the build slots")
	t.ok(_lot(s, "lot-05")["building_id"] == "house", "the lot shows it")
	t.ok(s.drain_events().is_empty(), "cmd_build emits nothing itself: building_started is TownSim's")
	t.ok(s.cmd_build("well", "lot-05")["reason"] == "lot_taken", "a lot under construction is taken")
	var evs := _run(s, 10.0)
	var started := _of(evs, "building_started")
	t.ok(started.size() == 1 and started[0]["lot_id"] == "lot-05" and started[0]["building_id"] == "house"
		and started[0]["level"] == 1 and started[0]["upgrade"] == false, "one building_started after the first substep: %s" % str(started))
	bl = _bld(s, "lot-05")
	t.ok(bl["state"] == "constructing" and bl["progress"] > 0.0 and bl["progress"] < 1.0, "the build job advances it (%.2f)" % bl["progress"])
	var jobs: Array = s.view_town()["jobs"].filter(func(j): return j["id"] == "build")
	t.ok(jobs.size() == 1 and jobs[0]["slots"] == 3 and jobs[0]["staffed"] == 3.0, "three builders on it")
	var done := _of(evs, "building_done")
	evs = _run(s, 60.0)
	done.append_array(_of(evs, "building_done"))
	t.ok(_of(evs, "building_started").is_empty(), "building_started is not emitted again")
	t.ok(done.size() == 1 and done[0] == {"t": done[0]["t"], "type": "building_done", "lot_id": "lot-05", "building_id": "house", "level": 1},
		"building_done once: %s" % str(done))
	bl = _bld(s, "lot-05")
	t.ok(bl["state"] != "constructing" and bl["level"] == 1 and bl["progress"] == 1.0, "level 1, finished")
	# 60 work / (0.5 per builder-second · 3 builders) = 40 s, and the done event lands in that window
	t.ok(done[0]["t"] > 35.0 and done[0]["t"] < 55.0, "in about 40 s (t = %.1f)" % done[0]["t"])
	t.near(s.town_sim.living_cap(), 16.0 + 8.0, 1e-9, "the house adds its living cap")
	# a crypt level (build_work 0) completes on the next substep
	s.cmd_debug_grant({"relics": 2})
	t.ok(s.cmd_upgrade("lot-01")["ok"], "crypt upgrade")
	_run(s, 1.0)
	t.ok(_bld(s, "lot-01")["level"] == 2 and _bld(s, "lot-01")["state"] != "constructing", "a build_work 0 upgrade completes at once")


# --------------------------------------------------------- cmd_upgrade ----
func _upgrade_reasons() -> void:
	var s := _mk()
	var fail := func(lot: String) -> String: return s.cmd_upgrade(lot)["reason"]
	t.ok(s.cmd_upgrade("lot-99") == {"ok": false, "reason": "unknown_lot", "level": 0, "cost": {}}, "unknown_lot")
	t.ok(fail.call("lot-05") == "empty_lot", "empty_lot")
	s.cmd_build("house", "lot-05")
	t.ok(fail.call("lot-05") == "under_construction", "under_construction (a first build)")
	s.town_sim.buildings["lot-04"]["state"] = "unpaid"
	t.ok(fail.call("lot-04") == "unpaid", "unpaid: TownSim refuses an unpaid building")
	s.town_sim.buildings["lot-04"]["state"] = "active"
	s.town_sim.place_building("lot-06", "house", int(_cfgs()["buildings"]["house"]["max_level"]))
	t.ok(fail.call("lot-06") == "max_level", "max_level")
	s.town_sim.place_building("lot-13", "inn", 1)
	t.ok(fail.call("lot-13") == "needs_tier", "needs_tier (an Inn placed at Hamlet)")
	s.town_sim.gold = 0.0
	s.town_sim.bone = 0.0
	t.ok(fail.call("lot-04") == "no_gold", "no_gold")
	s.town_sim.gold = 500.0
	t.ok(fail.call("lot-04") == "no_bone", "no_bone")
	s.town_sim.bone = 500.0
	t.ok(fail.call("lot-01") == "no_relics", "no_relics (the Crypt's second level costs a relic)")
	t.ok(s.town_sim.gold == 500.0 and s.town_sim.bone == 500.0, "refusals pay nothing")
	var r := s.cmd_upgrade("lot-04")
	var m2 := BuildRules.cost_of(s, _cfgs()["buildings"]["market"]["level_costs"][0])
	t.ok(r == {"ok": true, "reason": "", "level": 2, "cost": m2}, "upgrade the market: level 2 for level_costs[0]: %s" % [r])
	t.ok(s.town_sim.gold == 500.0 - float(m2["gold"]) and s.town_sim.bone == 500.0 - float(m2["bone"]), "paid at once")
	t.ok(s.cmd_upgrade("lot-04")["reason"] == "under_construction", "under_construction (an upgrade)")
	# a level-2 upgrade costs level_costs[1]
	s.town_sim.place_building("lot-07", "well", 2)
	s.town_sim.gold = 500.0
	t.ok(s.cmd_upgrade("lot-07")["cost"] == BuildRules.cost_of(s, _cfgs()["buildings"]["well"]["level_costs"][1]), "level 2 -> 3 costs level_costs[1]")


func _upgrade_works_meanwhile() -> void:
	var s := _mk()
	s.cmd_debug_grant({"gold": 1000.0, "bone": 500.0})
	s.tick(2.0)
	var before := _bld(s, "lot-04")
	t.ok(before["output"].has("gold") and before["output"]["gold"] > 0.0 and before["slots"] == 2, "the market sells before the upgrade")
	s.drain_events()
	t.ok(s.cmd_upgrade("lot-04")["ok"], "upgrade the market")
	var evs := _run(s, 10.0)
	var mid := _bld(s, "lot-04")
	t.ok(mid["state"] == "constructing" and mid["level"] == 1 and mid["progress"] > 0.0, "constructing, still level 1")
	t.ok(mid["output"].has("gold") and mid["output"]["gold"] > 0.0, "and it keeps its output meanwhile: %s" % str(mid["output"]))
	t.ok(mid["slots"] == 2 + 3, "its old stalls plus the build slots")
	t.ok(mid["upkeep"] == before["upkeep"], "and its upkeep")
	var started := _of(evs, "building_started")
	t.ok(started.size() == 1 and started[0]["level"] == 2 and started[0]["upgrade"] == true, "building_started {level 2, upgrade true}")
	# build_work 90 · target level 2 = 180 work at 1.5/s = 120 s
	evs = _run(s, 130.0)
	var done := _of(evs, "building_done")
	t.ok(done.size() == 1 and done[0]["level"] == 2 and done[0]["building_id"] == "market", "building_done {level 2}: %s" % str(done))
	var after := _bld(s, "lot-04")
	t.ok(after["level"] == 2 and after["state"] != "constructing" and after["slots"] == 4, "level 2, 4 stalls")


# -------------------------------------------------------- cmd_demolish ----
func _demolish() -> void:
	var s := _mk()
	t.ok(s.cmd_demolish("lot-99") == {"ok": false, "reason": "unknown_lot"}, "unknown_lot")
	t.ok(s.cmd_demolish("lot-05")["reason"] == "empty_lot", "empty_lot")
	s.cmd_build("house", "lot-05")
	t.ok(s.cmd_demolish("lot-05")["reason"] == "under_construction", "under_construction (use cmd_cancel_build)")
	t.ok(s.cmd_demolish("lot-01")["reason"] == "protected", "protected: the Crypt")
	s.cmd_debug_grant({"relics": 1, "gold": 500.0, "bone": 200.0})
	s.cmd_upgrade("lot-01")
	t.ok(s.cmd_demolish("lot-01")["reason"] == "under_construction", "under_construction comes before protected")
	# success: no refund, the lot is free, the cap goes, a foreman returns to the crypt
	s.cmd_debug_grant({"big_undead": 1})
	var u: String = s.big_undead[0]["uid"]
	t.ok(s.cmd_place_big_undead(u, "town:lot-03")["ok"], "a foreman at the Charnel House")
	s.cmd_set_staff_cap("lot-03", 1)
	var gold := s.town_sim.gold
	var bone := s.town_sim.bone
	var rl := s.relics
	var rv := s.rev
	t.ok(s.cmd_demolish("lot-03") == {"ok": true, "reason": ""} and s.rev == rv + 1, "demolish the Charnel House: ok")
	t.ok(s.town_sim.gold == gold and s.town_sim.bone == bone and s.relics == rl, "no refund")
	t.ok(_lot(s, "lot-03")["building_id"] == "" and _bld(s, "lot-03").is_empty(), "the lot is free")
	t.ok(s.big_undead[0]["place"] == "crypt" and s.view_town()["buildings"].all(func(b): return b["foreman"] != u), "the foreman is back in the crypt")
	t.ok(s.cmd_demolish("lot-03")["reason"] == "empty_lot", "twice: empty_lot")
	t.ok(s.cmd_build("charnel_house", "lot-03")["ok"], "the lot takes a new building")
	t.ok(s.town_sim.buildings["lot-03"]["staff_cap"] == -1, "with no staff cap carried over")
	# a pending building_started dies with its lot
	var d := _mk()
	d.town_sim.place_building("lot-05", "house", 1)
	d.cmd_upgrade("lot-05")
	d.cmd_cancel_build("lot-05")
	d.cmd_demolish("lot-05")
	t.ok(_evs(d, "building_started").is_empty() and (d.tick(1.0) >= 0) and _evs(d, "building_started").is_empty(), "no building_started for a cancelled upgrade")


# ----------------------------------------------------- cmd_cancel_build ----
func _cancel() -> void:
	var s := _mk()
	t.ok(s.cmd_cancel_build("lot-99") == {"ok": false, "reason": "unknown_lot", "refund": {}}, "unknown_lot")
	t.ok(s.cmd_cancel_build("lot-05")["reason"] == "not_building", "not_building (an empty lot)")
	t.ok(s.cmd_cancel_build("lot-04")["reason"] == "not_building", "not_building (a finished building)")
	# a new build: full refund, the lot is free, no event ever comes of it (the forge is bought with bone
	# since T7: the grant covers its bone, a stock a grant may put over the cap)
	var fc := BuildRules.construction_cost(s, "forge", 1)
	s.cmd_debug_grant({"relics": 4, "gold": 500.0, "bone": float(fc["bone"]) + 100.0})
	s.drain_events()
	s.town_sim.place_building("lot-01", "crypt", 1)
	s.town_tier = "village"
	var gold := s.town_sim.gold
	var bone := s.town_sim.bone
	t.ok(s.cmd_build("forge", "lot-13")["ok"], "build a forge (%d relic)" % int(fc["relics"]))
	t.ok(s.relics == 4 - int(fc["relics"]) and s.town_sim.gold == gold - float(fc["gold"]) and s.town_sim.bone == bone - float(fc["bone"]), "paid")
	var r := s.cmd_cancel_build("lot-13")
	t.ok(r == {"ok": true, "reason": "", "refund": fc}, "cancel: full refund: %s" % [r])
	t.ok(s.town_sim.gold == gold and s.town_sim.bone == bone and s.relics == 4, "the stocks are back")
	t.ok(_lot(s, "lot-13")["building_id"] == "" and _bld(s, "lot-13").is_empty(), "the lot is free")
	var evs := _run(s, 5.0)
	t.ok(_of(evs, "building_started").is_empty() and _of(evs, "building_done").is_empty(), "cancelled before a substep: no building_started, no building_done")
	# cancelled after it started: the started event stays, no done follows
	s.cmd_build("forge", "lot-13")
	evs = _run(s, 5.0)
	t.ok(_of(evs, "building_started").size() == 1, "started")
	t.ok(s.cmd_cancel_build("lot-13")["ok"], "cancel mid-build")
	evs = _run(s, 80.0)
	t.ok(_of(evs, "building_done").is_empty() and _bld(s, "lot-13").is_empty(), "no building_done after a cancel")
	t.ok(s.cmd_cancel_build("lot-13")["reason"] == "not_building", "twice: not_building")
	# a foreman on a cancelled new build goes home
	s.cmd_debug_grant({"big_undead": 1})
	var u: String = s.big_undead[0]["uid"]
	s.cmd_build("house", "lot-05")
	s.cmd_place_big_undead(u, "town:lot-05")
	s.cmd_cancel_build("lot-05")
	t.ok(s.big_undead[0]["place"] == "crypt", "the foreman of a cancelled build returns to the crypt")
	# a cancelled upgrade keeps the old level, still working
	s.cmd_debug_grant({"gold": 500.0})
	var g1 := s.town_sim.gold
	var b1 := s.town_sim.bone
	s.cmd_upgrade("lot-04")
	s.tick(5.0)
	r = s.cmd_cancel_build("lot-04")
	t.ok(r == {"ok": true, "reason": "", "refund": BuildRules.construction_cost(s, "market", 2)}, "cancel an upgrade: its cost back: %s" % [r])
	var b := _bld(s, "lot-04")
	t.ok(b["level"] == 1 and b["state"] != "constructing" and b["progress"] == 1.0 and b["output"].has("gold") and b["slots"] == 2,
		"level 1, working, no build slots: %s" % str(b))
	t.ok(s.town_sim.bone <= b1 + 1.0 and s.town_sim.gold >= g1 - 1.0, "(the stocks are back, give or take 5 s of trade)")
	t.ok(s.cmd_cancel_build("lot-04")["reason"] == "not_building", "and it can't be cancelled again")
	# relics are clamped to the cap
	var c := _mk()
	c.cmd_debug_grant({"relics": 12, "gold": 500.0, "bone": 2.0 * float(fc["bone"])})  # two forges' bone
	c.town_tier = "village"
	c.cmd_build("forge", "lot-13")
	c.cmd_debug_grant({"relics": 1})
	t.ok(c.relics == 12, "the relic cap is 12")
	r = c.cmd_cancel_build("lot-13")
	t.ok(r["ok"] and r["refund"]["relics"] == 0 and c.relics == 12, "the relic refund is clamped to the cap: %s" % [r])
	c.cmd_build("forge", "lot-13")
	c.relics = 10
	r = c.cmd_cancel_build("lot-13")
	t.ok(r["refund"]["relics"] == 1 and c.relics == 11, "and not clamped below it")


# --------------------------------------------------------------- tiers ----
func _tiers() -> void:
	var s := _mk()
	var tiers: Dictionary = _cfgs()["economy"]["town"]["tiers"]
	var v := s.view_town()
	t.ok(v["tier"] == "hamlet" and v["next_tier"] == {"tier": "village", "have": 4, "need": 6, "missing": ["house"]}, "Hamlet: 4 of 6, no house: %s" % str(v["next_tier"]))
	t.ok(v["lots"].all(func(l): return l["unlocked"] == tiers["hamlet"]["lot_ids"].has(l["id"])), "Hamlet's lots are unlocked, the rest locked")
	# six buildings but no house: no Village
	s.town_sim.place_building("lot-05", "well", 1)
	s.town_sim.place_building("lot-06", "bakery", 1)
	s.tick(1.0)
	v = s.view_town()
	t.ok(v["tier"] == "hamlet" and v["next_tier"] == {"tier": "village", "have": 6, "need": 6, "missing": ["house"]}, "6 buildings without a house stay Hamlet: %s" % str(v["next_tier"]))
	t.ok(_evs(s, "tier_up").is_empty(), "no tier_up")
	# the house, built for real, is the one that makes it
	s.cmd_debug_grant({"gold": 500.0, "bone": 200.0})
	t.ok(s.cmd_build("house", "lot-07")["ok"], "build the house")
	var evs := _run(s, 20.0)
	t.ok(s.town_tier == "hamlet" and _of(evs, "tier_up").is_empty(), "still Hamlet while it is under construction")
	evs = _run(s, 60.0)
	var done_t: float = _of(evs, "building_done")[0]["t"]
	var up := _of(evs, "tier_up")
	t.ok(up.size() == 1 and up[0]["tier"] == "village" and up[0]["from"] == "hamlet" and up[0]["t"] == done_t, "tier_up once, in the substep the house is done: %s" % str(up))
	evs = _run(s, 30.0)
	t.ok(_of(evs, "tier_up").is_empty() and s.town_tier == "village", "and never again")
	v = s.view_town()
	t.ok(v["tier"] == "village" and v["next_tier"] == {"tier": "town", "have": 7, "need": 12, "missing": ["walls", "chapel_of_vats"]}, "Village: next is Town: %s" % str(v["next_tier"]))
	t.ok(v["lots"].all(func(l): return l["unlocked"] == tiers["village"]["lot_ids"].has(l["id"])), "Village's lots are unlocked")
	t.ok(_lot(s, "lot-23")["unlocked"] and not _lot(s, "lot-24")["unlocked"] and not _lot(s, "lot-17")["unlocked"], "lot-23 yes; lot-24 and lot-17 not yet")
	# a tier never falls
	s.cmd_demolish("lot-07")
	s.cmd_demolish("lot-05")
	s.tick(1.0)
	t.ok(s.town_tier == "village" and s.view_town()["next_tier"]["tier"] == "town", "demolishing the house does not take the Village away")
	# a debug placement that skips tiers rises one tier per rise, in order
	var p := _mk()
	for i in 8:
		p.town_sim.place_building("lot-%02d" % (5 + i), "house", 1)
	p.town_sim.place_building("lot-13", "chapel_of_vats", 1)
	p.town_sim.place_building("lot-23", "walls", 1)
	p.town_sim.place_building("lot-24", "reliquary", 1)
	p.town_sim.place_building("lot-14", "inn", 1)
	p.town_sim.place_building("lot-15", "forge", 1)
	p.town_sim.place_building("lot-16", "graveyard", 1)
	p.town_sim.place_building("lot-17", "well", 1)
	p.town_sim.place_building("lot-18", "well", 1)
	p.town_sim.place_building("lot-19", "well", 1)
	p.town_sim.place_building("lot-20", "well", 1)
	p.tick(0.5)
	var rises := _of(p.drain_events(), "tier_up")
	t.ok(rises.map(func(e): return [e["from"], e["tier"]]) == [["hamlet", "village"], ["village", "town"], ["town", "city"]],
		"all three tiers hold at once: three tier_up events in order: %s" % str(rises))
	t.ok(p.view_town()["tier"] == "city" and p.view_town()["next_tier"] == {"tier": "", "have": p._count_built(""), "need": 0, "missing": []}, "City: no next tier")
	t.ok(p.view_town()["lots"].all(func(l): return l["unlocked"]), "City opens every lot")


## R1 (the run's manager): an unpaid building keeps its tier and unlock contribution; a floor never drops a
## tier gate. BuildRules.count_built counts every building past its first build whatever its state, so
## next_tier, rise_tiers and req_reason's needs_building count an unpaid one, and the lots follow the tier
## (which never falls). Hamlet's four start buildings, a well and the town's only house make the Village's six
## with its market and house; nobody sells and the gold is 0, so the upkeep sheds the house in the substep the
## tier is checked, and the Village rises with it unpaid.
func _unpaid_keeps_tier() -> void:
	var s := _mk()
	s.town_sim.place_building("lot-05", "house", 1)
	s.town_sim.place_building("lot-06", "well", 1)
	s.town_sim.set_ladder([])
	s.town_sim.gold = 0.0
	s.drain_events()
	s.tick(0.5)
	var evs := s.drain_events()
	var shed := _of(evs, "building_unpaid").filter(func(e): return bool(e["unpaid"])).map(func(e): return e["lot_id"])
	var up := _of(evs, "tier_up")
	t.ok(s.town_sim.buildings["lot-05"]["state"] == "unpaid" and shed.has("lot-05") and up.size() == 1 and s.town_tier == "village",
		"the only house goes unpaid in the substep the tier is checked, and the Village rises: shed %s, %s" % [str(shed), str(up)])
	t.ok(s.view_town()["next_tier"]["have"] == 6 and BuildRules.count_built(s, "house") == 1,
		"the unpaid house counts: next_tier has 6 (%s)" % str(s.view_town()["next_tier"]))
	t.ok(BuildRules.req_reason(s, {"tier": "hamlet", "blueprint": "", "building": "house"}) == "",
		"a building that needs a house isn't refused needs_building while the house is unpaid")
	var lots: Array = _cfgs()["economy"]["town"]["tiers"]["village"]["lot_ids"]
	t.ok(lots.all(func(l): return BuildRules.lot_unlocked(s, l)), "and the Village's lots open")


# ---------------------------------------------------------------- caps ----
## R1 (the run's manager's condition): unpaid storage never destroys stock. The capacity effects GameState reads
## (the Reliquary's relic_cap and essence_cap, the Chapel of Vats' vat_slots, the Guildhall's stance_slots;
## TownSim.CAPACITY_EFFECTS) count while the building is unpaid, so with each store full the cap and the stock
## stay as they were when a gold floor sheds the building and again when it is paid. (TownSim's own stores,
## bodies, gold, bone and living: test_town_sim's _unpaid_keeps_caps.)
func _unpaid_keeps_stores() -> void:
	var hold := float(_cfgs()["economy"]["upkeep"]["unpaid_hold_s"])
	for c in [["reliquary", "lot-24", 1], ["chapel_of_vats", "lot-13", 2], ["guildhall", "lot-14", 1]]:
		var s := _mk()
		s.town_sim.place_building(c[1], c[0], c[2])
		s.relics = s._cap_of("relics")
		s.essence = s._cap_of("essence")
		for i in s._vat_slots():
			s.cmd_staff_vat(i, true)
		for id in GameState.STANCE_IDS:
			s.cmd_set_stance(id, true)  # up to the slots; the rest are refused no_slot
		var snap := func() -> Array:
			return [s._cap_of("relics"), s.relics, s._cap_of("essence"), s.essence, s._vat_slots(), s.vats_staffed.duplicate(),
				s._stance_slots(), s.stances_on.duplicate()]
		var full: Array = snap.call()
		s.town_sim.set_ladder([])  # nobody sells
		s.town_sim.gold = 0.0
		s.tick(0.5)
		var unpaid: bool = s.town_sim.buildings[c[1]]["state"] == "unpaid"
		t.ok(unpaid and snap.call() == full, "%s unpaid: the caps and the full stores as they were: %s" % [c[0], str(snap.call())])
		s.town_sim.gold = 1000.0
		for i in int(2.0 * hold) + 4:
			s.tick(0.5)
		var paid: bool = s.town_sim.buildings[c[1]]["state"] != "unpaid"
		t.ok(paid and snap.call() == full, "%s paid again: the same (%s)" % [c[0], str(snap.call())])


func _caps() -> void:
	var s := _mk()
	var hud := s.view_hud()
	t.ok(hud["relics_cap"] == 12 and hud["essence_cap"] == 60 and s.view_big_undead()["cap"] == 4, "base caps 12, 60, 4")
	s.town_sim.place_building("lot-24", "reliquary", 1)
	hud = s.view_hud()
	t.ok(hud["relics_cap"] == 18 and hud["essence_cap"] == 90, "the Reliquary adds 6 relics and 30 essence")
	s.cmd_debug_grant({"relics": 99, "essence": 99})
	t.ok(s.relics == 18 and s.essence == 90, "grants are capped by them")
	s.cmd_debug_grant({"relics": 5})
	s.relics = 3
	s.cmd_debug_grant({"gold": 500.0, "bone": 200.0})
	t.ok(s.cmd_upgrade("lot-01")["ok"], "upgrade the crypt")
	t.ok(s.view_big_undead()["cap"] == 4, "mid-upgrade it is still level 1: cap 4")
	_run(s, 2.0)
	t.ok(s.view_big_undead()["cap"] == 5, "crypt level 2: cap 5")
	s.cmd_debug_grant({"relics": 5})
	s.cmd_upgrade("lot-01")
	_run(s, 2.0)
	t.ok(s.view_big_undead()["cap"] == 6 and _bld(s, "lot-01")["level"] == 3, "crypt level 3: cap 6")
	s.cmd_debug_grant({"big_undead": 99})
	t.ok(s.big_undead.size() == 6, "the grant fills the cap")
	t.ok(_cfgs()["economy"]["big_undead"]["per_crypt_level"] == 1, "per_crypt_level is in economy.json")
	# vats: the Chapel's slots
	var c := _mk()
	t.ok(c.view_backups()["vats"].is_empty(), "no Chapel, no vats")
	c.town_sim.place_building("lot-13", "chapel_of_vats", 1)
	t.ok(c.view_backups()["vats"].size() == 2, "a Chapel: 2 vat slots")
	c.town_sim.place_building("lot-13", "chapel_of_vats", 2)
	t.ok(c.view_backups()["vats"].size() == 4, "2 per level")
	t.ok(c.cmd_staff_vat(3, true)["ok"] and not c.cmd_staff_vat(4, true)["ok"], "slots 0..3")
	# stance slots: base 2 + 1 home, + the Guildhall
	var g := _mk()
	var slots: int = g.view_stances()["slots"]
	g.town_sim.place_building("lot-14", "guildhall", 1)
	t.ok(g.view_stances()["slots"] == slots + 1, "the Guildhall adds a stance slot")


# ---------------------------------------------------------- playthrough ----
## From cmd_new_game to City through the commands only: grants and a blueprint are the only debug
## help. It proves the gates (and the lot lists) are not circular.
func _playthrough() -> void:
	var s := _mk()
	var order := [
		["house", "lot-05"], ["well", "lot-06"],  # 6 buildings with a house: Village
		["walls", "lot-23"], ["chapel_of_vats", "lot-13"],  # one tier early
		["bakery", "lot-07"], ["bone_mill", "lot-08"], ["inn", "lot-14"], ["forge", "lot-15"],  # 12: Town
		["reliquary", "lot-24"],  # one tier early, with its blueprint
		["graveyard", "lot-16"], ["watchtower", "lot-09"], ["statue", "lot-10"], ["raising_pit", "lot-11"],
		["house", "lot-12"], ["bakery", "lot-17"], ["well", "lot-18"],  # 20: City
	]
	var failed := ""
	s.blueprints.append("reliquary")
	for i in order.size():
		var bid: String = order[i][0]
		var lot: String = order[i][1]
		s.cmd_debug_grant({"gold": 3000.0 - s.town_sim.gold, "bone": 1500.0 - s.town_sim.bone, "relics": 12 - s.relics})
		var r := s.cmd_build(bid, lot)
		if not r["ok"]:
			failed = "%s on %s: %s (tier %s)" % [bid, lot, r["reason"], s.town_tier]
			break
		# wait for it to finish
		var guard := 0
		while _bld(s, lot).get("state", "") == "constructing" and guard < 40:
			_run(s, 20.0)
			guard += 1
		if _bld(s, lot).get("state", "") == "constructing":
			failed = "%s on %s never finished" % [bid, lot]
			break
	t.ok(failed == "", "the playthrough builds in order: %s" % failed)
	t.ok(s.town_tier == "city", "and reaches City (tier %s, %d buildings)" % [s.town_tier, s._count_built("")])
	t.ok(s._count_built("") == 20 and s._count_built("reliquary") == 1 and s._count_built("walls") == 1, "20 buildings including the Reliquary and the Walls")
	# the order of the tiers: village at 6, town at 12, city with the Reliquary
	var a := _mk()
	a.blueprints.append("reliquary")
	var seq: Array = []
	for i in order.size():
		a.cmd_debug_grant({"gold": 3000.0 - a.town_sim.gold, "bone": 1500.0 - a.town_sim.bone, "relics": 12 - a.relics})
		a.cmd_build(order[i][0], order[i][1])
		while _bld(a, order[i][1]).get("state", "") == "constructing":
			for e in _of(_run(a, 20.0), "tier_up"):
				seq.append([i + 1, e["from"], e["tier"]])
	t.ok(seq == [[2, "hamlet", "village"], [8, "village", "town"], [16, "town", "city"]],
		"Village after the 2nd build, Town after the 8th (12 buildings), City after the 16th (20): %s" % str(seq))


# ------------------------------------------------- catalog and cmd_build ----
func _catalog_agrees() -> void:
	var states := ["new_game"] + GameState.FIXTURES
	for name in states:
		var probe := _load(name)
		var cat: Array = probe.view_catalog()["buildings"]
		var bad := []
		var built := 0
		for e in cat:
			var bid: String = e["building_id"]
			var s := _load(name)
			var lots: Array = e["lots"]
			if e["can_build"]:
				var r := s.cmd_build(bid, lots[0])
				if not (r["ok"] and e["reason"] == "" and not lots.is_empty()):
					bad.append("%s can_build but %s" % [bid, str(r)])
				else:
					built += 1
			elif not lots.is_empty():
				var r := s.cmd_build(bid, lots[0])
				if r["ok"] or r["reason"] != e["reason"]:
					bad.append("%s catalog %s, cmd_build %s" % [bid, e["reason"], str(r)])
			else:
				for l in s.view_town()["lots"]:
					var r := s.cmd_build(bid, l["id"])
					if r["ok"]:
						bad.append("%s has no lot but built on %s" % [bid, l["id"]])
				if e["reason"] == "no_lot":
					var all_lot := true
					for l in s.view_town()["lots"]:
						all_lot = all_lot and ["lot_locked", "lot_taken", "lot_too_small"].has(s.cmd_build(bid, l["id"])["reason"])
					if not all_lot:
						bad.append("%s no_lot but a lot passes the lot checks" % bid)
		t.ok(bad.is_empty(), "%s: view_catalog's can_build and reason agree with cmd_build for all %d buildings (%d buildable): %s" % [name, cat.size(), built, str(bad)])
		# the catalog's other keys follow the config
		var cfg: Dictionary = _cfgs()["buildings"]
		var c: Dictionary = _cat(probe, "walls")
		t.ok(c["requires"]["tier"] == "village" and c["lot_size"] == 3 and c["cost"]["relics"] == 2 and c["max_level"] == 1 and c["build_work"] == 240.0
			and c["upkeep"]["gold"] == 0.12 and cfg.has("walls"), "%s: walls entry from the config" % name)
	var f := _mk()
	t.ok(f.view_catalog()["buildings"].size() == 21, "21 buildings in the catalog")
	var h := _cat(f, "house")
	t.ok(h["can_build"] and h["reason"] == "" and h["lots"] == ["lot-05", "lot-06", "lot-07", "lot-08"] and h["count"] == 0, "a fresh game can build a house on lots 5-8")
	t.ok(_cat(f, "market")["reason"] == "no_lot" and _cat(f, "inn")["reason"] == "needs_tier", "the market has no free size-2 lot; the inn needs Village")
	t.ok(_cat(f, "crypt")["count"] == 1 and _cat(f, "walls")["reason"] == "needs_tier", "count and needs_tier")
	f.cmd_build("house", "lot-05")
	t.ok(not (_cat(f, "house")["lots"] as Array).has("lot-05"), "a lot under construction is not free in the catalog")
	t.ok(_cat(f, "house")["count"] == 0, "and the house does not count until it is built")


func _load(name: String) -> GameState:
	if name == "new_game":
		return _mk()
	var s := GameState.new(_cfgs())
	s.debug_enabled = true
	var r := s.cmd_debug_load_fixture(name)
	if not r["ok"]:
		printerr("fixture %s failed to load: %s" % [name, str(r)])
	return s
