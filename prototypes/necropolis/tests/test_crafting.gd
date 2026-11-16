extends RefCounted
## E3-4: crafting at the Ossuary (MECHANICS §3.6, §7; STATE-API §4.3 cmd_craft, §5.10 crafts, §5.12, §9.1).
## - cmd_craft's refusals, in order: unknown_item, needs_building, no_essence, no_relics; a refusal changes nothing;
## - a craft takes economy.json craft.<id>'s essence and relics exactly (and follows the config) and adds 1 to its
##   stock; `count` is the new stock, rev + 1, no event and no uid; neither stock has a cap of its own (two charges
##   pass phylactery.max_per_dungeon, which limits a run's revives);
## - needs_building is the built buildings' `craft_slots` under 1: the effect, not the Ossuary's id (an Ossuary given
##   craft_slots 0 can't craft, a House given 1 can), held while the Ossuary is unpaid or Thrift-idled (a capacity
##   effect), not yet on its first build;
## - view_catalog's crafts give what cmd_craft would answer, and view_inventory shows the stocks;
## - save -> load keeps simulacra_ready; a save without it reads 0, and one of another type is corrupt;
## - a crafted phylactery charge is the stock E3-2's death rule spends: a raid's revive in place, as test_backups has it.
## Saves go under user://test_crafting_<pid>, removed at the end.

var t := TestUtil.new()
var _dir := "user://test_crafting_%d" % OS.get_process_id()
const CLOCK := 1_800_000_000  # a "now" for the saves (unix seconds)
const OSSUARY_LOT := "lot-13"  # size 2, the Ossuary Tower's


func run() -> int:
	t.suite("crafting")
	DirAccess.make_dir_recursive_absolute(_dir)
	_refusals()
	_costs()
	_gate_by_effect()
	_unpaid_and_thrift()
	_views()
	_save_load()
	_old_save()
	_charge_revives()
	_cleanup()
	return t.failures


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(_dir)


func _mk(c := {}) -> GameState:
	var s := GameState.new(TestUtil.configs() if c.is_empty() else c)
	s.cmd_new_game(1)
	s.debug_enabled = true
	s.save_dir = _dir
	return s


## A new game with a level-1 Ossuary Tower on OSSUARY_LOT.
func _ossuary(c := {}) -> GameState:
	var s := _mk(c)
	s.town_sim.place_building(OSSUARY_LOT, "ossuary_tower", 1)
	return s


func _cfg_cost(id: String, k: String) -> int:
	return int(TestUtil.configs()["economy"]["craft"][id][k])


# -------------------------------------------------------------------------------------------------- the refusals ----
## Each refusal in order, the next one's condition holding too: an unknown item with no Ossuary, no essence and no
## relics is unknown_item; a known one there needs_building; with an Ossuary, no_essence before no_relics (one essence
## short of each cost); then no_relics. None changes anything (rev, the stocks, the uid counter, the stats).
func _refusals() -> void:
	var s := _mk()
	s.essence = 0
	s.relics = 0
	var snap := func() -> Array:
		return [s.rev, s.relics, s.simulacra_ready, s._phylactery_charges, s.next_uid, s.stats.duplicate(), s._events.size()]
	var before: Array = snap.call()
	t.ok(s.cmd_craft("relic") == {"ok": false, "reason": "unknown_item", "count": 0}, "an unknown item: unknown_item, before the building")
	t.ok(s.cmd_craft("simulacrum") == {"ok": false, "reason": "needs_building", "count": 0}
		and s.cmd_craft("phylactery_charge")["reason"] == "needs_building", "no Ossuary: needs_building, before the essence and the relics")
	s.town_sim.place_building(OSSUARY_LOT, "ossuary_tower", 1)
	t.ok(s.cmd_craft("nope")["reason"] == "unknown_item", "with an Ossuary an unknown item is still unknown_item")
	s.essence = _cfg_cost("simulacrum", "essence") - 1
	t.ok(s.cmd_craft("simulacrum") == {"ok": false, "reason": "no_essence", "count": 0},
		"an Ossuary, %d essence of the simulacrum's %d and no relic: no_essence, before no_relics" % [s.essence, s.essence + 1])
	s.essence = _cfg_cost("phylactery_charge", "essence") - 1
	t.ok(s.cmd_craft("phylactery_charge")["reason"] == "no_essence", "%d essence of the charge's %d: no_essence" % [s.essence, s.essence + 1])
	s.essence = _cfg_cost("simulacrum", "essence")
	t.ok(s.cmd_craft("simulacrum") == {"ok": false, "reason": "no_relics", "count": 0}, "its essence, no relic: no_relics")
	t.ok(snap.call() == before and s.essence == _cfg_cost("simulacrum", "essence"), "the refusals change nothing: %s" % str(snap.call()))


# ----------------------------------------------------------------------------------------------------- the costs ----
## The costs taken exactly, `count` the new stock, rev + 1, no event, no uid; stats.sims_built counts the simulacra
## crafted. No stock cap: a second charge is past max_per_dungeon (1). The costs follow economy.json (REQUIRED).
func _costs() -> void:
	var s := _ossuary()
	s.essence = 50
	s.relics = 3
	s.drain_events()
	var uid := s.next_uid
	var rv := s.rev
	var r := s.cmd_craft("simulacrum")
	t.ok(r == {"ok": true, "reason": "", "count": 1} and s.essence == 30 and s.relics == 2 and s.simulacra_ready == 1
		and s._phylactery_charges == 0 and s.rev == rv + 1,
		"a simulacrum takes 20 essence and 1 relic: count 1, rev + 1 (%s; essence %d, relics %d)" % [str(r), s.essence, s.relics])
	r = s.cmd_craft("phylactery_charge")
	t.ok(r == {"ok": true, "reason": "", "count": 1} and s.essence == 15 and s.relics == 2 and s._phylactery_charges == 1
		and s.simulacra_ready == 1 and s.rev == rv + 2, "a phylactery charge takes 15 essence and no relic: count 1 (%s)" % str(r))
	r = s.cmd_craft("phylactery_charge")
	t.ok(r["count"] == 2 and s.essence == 0 and s._phylactery_charges == 2 and s.view_backups()["phylactery_charges"] == 2
		and s._phylactery_charges > s._phylactery_max(),
		"a second charge: count 2, past phylactery.max_per_dungeon (%d), which limits a run's revives, not the stock" % s._phylactery_max())
	t.ok(s.next_uid == uid and s.drain_events().is_empty() and int(s.stats["sims_built"]) == 1,
		"no uid minted, no event; stats.sims_built counts the simulacrum (%d)" % int(s.stats["sims_built"]))
	s.essence = 60
	s.relics = 12
	for i in 3:
		r = s.cmd_craft("simulacrum")
	t.ok(r["count"] == 4 and s.simulacra_ready == 4 and s.essence == 0 and s.relics == 9 and int(s.stats["sims_built"]) == 4,
		"three more from a full essence store (60): 4 ready, no cap but the essence's")
	var c := TestUtil.configs()
	c["economy"]["craft"]["simulacrum"] = {"essence": 7, "relics": 2}
	var o := _ossuary(c)
	o.essence = 10
	o.relics = 2
	t.ok(o.cmd_craft("simulacrum")["ok"] and o.essence == 3 and o.relics == 0 and o.view_catalog()["crafts"][0]["cost"] == {"essence": 7, "relics": 2},
		"the cost is economy.json craft.simulacrum's (7 essence and 2 relics here), in cmd_craft and the catalog")


# ------------------------------------------------------------------------------------------------------ the gate ----
## needs_building reads the `craft_slots` effect over the built buildings, not a building id: an Ossuary Tower given
## craft_slots 0 refuses, a House given craft_slots 1 crafts with no Ossuary. An Ossuary on its first build (level 0)
## doesn't craft yet; one at level 2 does (its 2 slots add nothing more in E3).
func _gate_by_effect() -> void:
	var c := TestUtil.configs()
	c["buildings"]["ossuary_tower"]["effects"]["craft_slots"] = 0
	var s := _ossuary(c)
	s.essence = 60
	s.relics = 12
	t.ok(s.cmd_craft("simulacrum")["reason"] == "needs_building" and s.view_catalog()["crafts"][0]["reason"] == "needs_building",
		"an Ossuary Tower with craft_slots 0: needs_building, in cmd_craft and the catalog")
	var c2 := TestUtil.configs()
	c2["buildings"]["house"]["effects"]["craft_slots"] = 1
	var h := _mk(c2)
	h.town_sim.place_building("lot-05", "house", 1)
	h.essence = 60
	h.relics = 12
	t.ok(h.view_catalog()["crafts"][0]["can_craft"] and h.cmd_craft("simulacrum")["ok"] and h.simulacra_ready == 1,
		"a House given craft_slots 1 crafts with no Ossuary: the building is found by its effect, not its id")
	var b := _mk()
	b.essence = 60
	b.relics = 12
	t.ok(b.town_sim.start_construction(OSSUARY_LOT, "ossuary_tower", 1)["ok"] and b.cmd_craft("simulacrum")["reason"] == "needs_building",
		"an Ossuary on its first build (level 0) doesn't craft yet")
	var l2 := _mk()
	l2.town_sim.place_building(OSSUARY_LOT, "ossuary_tower", 2)
	l2.essence = 60
	l2.relics = 12
	t.ok(l2.town_sim.built_effect("craft_slots") == 2.0 and l2.cmd_craft("simulacrum")["count"] == 1,
		"a level-2 Ossuary (craft_slots 2) crafts as level 1 does: one item a craft")


## A capacity effect (TownSim.CAPACITY_EFFECTS): an unpaid Ossuary still crafts, and so does one the Thrift stance
## idles. Thrift: the day1 town plus the Ossuary (0.15 gold/s) and a Watchtower (0.08) is 0.32 of upkeep on 0.30 of
## trade, so Thrift idles the dearer passive building, the Ossuary, and stops.
func _unpaid_and_thrift() -> void:
	var s := _ossuary()
	s.essence = 60
	s.relics = 12
	s.town_sim.set_ladder([])  # nobody sells
	s.town_sim.gold = 0.0
	s.tick(0.5)
	var st := str(s.town_sim.buildings[OSSUARY_LOT]["state"])
	var r := s.cmd_craft("simulacrum")
	t.ok(st == "unpaid" and r["ok"] and r["count"] == 1 and s.view_catalog()["crafts"][1]["can_craft"],
		"an unpaid Ossuary (state %s) still crafts: %s" % [st, str(r)])
	var th := _ossuary()
	th.town_sim.place_building("lot-05", "watchtower", 1)
	th.town_sim.gold = 500.0
	th.essence = 60
	th.relics = 12
	th.cmd_set_stance("thrift", true)
	th._stance_beat = -1  # the stance step reads the conditions at the next step
	th.tick(0.5)
	var ts := str(th.town_sim.buildings[OSSUARY_LOT]["state"])
	r = th.cmd_craft("phylactery_charge")
	t.ok(ts == "thrift" and str(th.town_sim.buildings["lot-05"]["state"]) != "thrift" and r["ok"] and r["count"] == 1,
		"an Ossuary the Thrift stance idles (state %s) still crafts: %s" % [ts, str(r)])


# ----------------------------------------------------------------------------------------------------- the views ----
## view_catalog's crafts against what cmd_craft answers on a copy of the state, at each gate: no Ossuary, no essence,
## the simulacrum short of a relic (the charge craftable), both craftable. view_inventory and view_backups show the
## stocks.
func _views() -> void:
	var s := _mk()
	s.essence = 0
	s.relics = 0
	var agree := func(label: String) -> void:
		var rows: Array = s.view_catalog()["crafts"]
		var ok := rows.size() == GameState.CRAFT_IDS.size()
		var got: Array = []
		for i in rows.size():
			var cp := GameState.new(s._cfgs)
			cp.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))  # the town's buildings and the stocks
			var want := cp.cmd_craft(str(rows[i]["item_id"]))
			got.append([rows[i]["item_id"], rows[i]["reason"], want["reason"]])
			ok = ok and rows[i]["item_id"] == GameState.CRAFT_IDS[i] and rows[i]["reason"] == want["reason"] and rows[i]["can_craft"] == want["ok"]
		t.ok(ok, "%s: view_catalog's crafts say what cmd_craft answers: %s" % [label, str(got)])
	agree.call("no Ossuary")
	s.town_sim.place_building(OSSUARY_LOT, "ossuary_tower", 1)
	agree.call("an Ossuary, no essence")
	s.essence = 20
	agree.call("20 essence, no relic")
	s.relics = 1
	agree.call("20 essence and a relic")
	s.cmd_craft("simulacrum")
	s.essence = 15
	s.cmd_craft("phylactery_charge")
	var inv := s.view_inventory()
	t.ok(inv["simulacra_ready"] == 1 and inv["phylactery_charges"] == 1 and s.view_backups()["phylactery_charges"] == 1,
		"view_inventory shows the simulacra ready and the charges, view_backups the charges: %d, %d" % [inv["simulacra_ready"], inv["phylactery_charges"]])


# -------------------------------------------------------------------------------------------------- the save ----
## save -> load keeps the stocks: the file holds inventory.simulacra_ready and backups.phylactery_charges, and a fresh
## state loading it shows them; to_dict's inventory comes back as it was.
func _save_load() -> void:
	var s := _ossuary()
	s.essence = 60
	s.relics = 12
	s.cmd_craft("simulacrum")
	s.cmd_craft("simulacrum")
	s.cmd_craft("phylactery_charge")
	var d := s.to_dict()
	t.ok(d["inventory"]["simulacra_ready"] == 2 and d["backups"]["phylactery_charges"] == 1, "the save writes 2 simulacra ready and 1 charge")
	s.clock_override = CLOCK
	t.ok(s.cmd_save("craft")["ok"], "(setup) saved")
	var n := _mk()
	n.clock_override = CLOCK
	var r := n.cmd_load("craft")
	t.ok(r["ok"] and n.simulacra_ready == 2 and n.view_inventory()["simulacra_ready"] == 2 and n._phylactery_charges == 1
		and n.to_dict()["inventory"] == d["inventory"] and n.to_dict()["stats"] == d["stats"],
		"save -> load keeps them: %d ready, %d charge, the inventory and stats as saved" % [n.simulacra_ready, n._phylactery_charges])


## A save without inventory.simulacra_ready (the key is optional from E3-4) loads, reading 0 whatever the state held
## before; one of another type is corrupt. The fixtures write 0 and come back as they are (test_game_state_persist).
func _old_save() -> void:
	var s := _ossuary()
	s.essence = 20
	s.relics = 1
	s.cmd_craft("simulacrum")
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	(d["inventory"] as Dictionary).erase("simulacra_ready")
	var n := _mk()
	n.simulacra_ready = 5  # what the state held before the load, which the load replaces
	var r := n.from_dict(d.duplicate(true))
	t.ok(r["ok"] and n.simulacra_ready == 0 and n.view_inventory()["simulacra_ready"] == 0 and n.to_dict()["inventory"]["simulacra_ready"] == 0,
		"a save without inventory.simulacra_ready loads, reading 0: %s" % str(r))
	for bad in ["two", 1.5, [1]]:
		var e := d.duplicate(true)
		e["inventory"]["simulacra_ready"] = bad
		t.ok(_mk().from_dict(e) == {"ok": false, "reason": "corrupt"}, "inventory.simulacra_ready %s is corrupt" % str(bad))


# ------------------------------------------------------------------------------------------------ the revive ----
## A crafted phylactery charge is what E3-2's death rule spends (test_backups._each_outcome's path): view_backups'
## death reads the phylactery, the raid's seed carries the charge, and a result with a revive in place raises
## relish_died {phylactery, in_place} and spends it; the run went on (a retreat after it, Relish at the fort).
func _charge_revives() -> void:
	var s := _ossuary()
	s.essence = 15
	s.relics = 0
	t.ok(s.cmd_craft("phylactery_charge") == {"ok": true, "reason": "", "count": 1} and s.view_backups()["death"]["outcome"] == "phylactery",
		"a crafted charge: view_backups' death is the phylactery (%s)" % str(s.view_backups()["death"]))
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	var b := s.cmd_begin_dungeon("old-sluice")
	var sd: Dictionary = b.get("seed", {})
	t.ok(b["ok"] and int(sd["phylactery_charges"]) == 1, "(setup) a raid at Old Sluice; its seed carries the crafted charge")
	s.drain_events()
	var res := {"v": 2, "run_id": sd["run_id"], "seed_rev": sd["seed_rev"], "fort_id": sd["fort"]["id"],
		"warden_beaten": false, "retreated": true, "relish_died": false, "revived_in_place": 1,
		"killed_living_mass": 0.0, "raised": [], "chaff_mass": 0.0, "garrison_mass": sd["garrison_in_mass"],
		"party_lost": [], "loot": {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0}}
	var r := s.apply_result("raid", res)
	var died: Array = s.drain_events().filter(func(e): return e["type"] == "relish_died")
	t.ok(r["ok"] and died.size() == 1 and died[0]["outcome"] == "phylactery" and died[0]["in_place"] and float(died[0]["respawn_s"]) == 0.0,
		"the dungeon's revive in place spends it: relish_died %s" % str(died))
	t.ok(s._phylactery_charges == 0 and s.view_inventory()["phylactery_charges"] == 0 and s.view_relish()["state"] == "at_fort"
		and s.view_relish()["at"] == "old-sluice", "the charge is spent and the run went on: Relish at Old Sluice")
