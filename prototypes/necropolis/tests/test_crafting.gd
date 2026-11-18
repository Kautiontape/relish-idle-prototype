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
## E3-4's simulacra (MECHANICS §3.6, §3.4's retake; STATE-API §4.3 cmd_deploy_simulacrum, §5.5; IDLE I6, §4):
## - cmd_deploy_simulacrum's refusals, in order: unknown_fort, none_ready; it takes one from the stock and plants
##   {fort_id, charges, rate} from realm.json simulacrum (300, 1.0), returning its charges and ready_left; any fort;
##   several at one fort stack (view_fort sums their charges, and they raise side by side);
## - a planted simulacrum raises its fort's corpses at its rate until its charges run out, then crumbles; while it has
##   charges the garrison's kills there stay as corpses, and once it is gone they ship to Vei again; the ledger holds;
## - a retake loses it, live and caught up (IDLE I6: a simulacrum at a fort that falls while you're away is lost);
## - save -> load mid-charge keeps it, and the loaded game runs it out as the unsaved one does;
## - catch-up clips at its exhaustion: one running out 292.5 s in, inside a 15 s step, against live 0.5 s (its fort's
##   undead, dead and raised mass, and when it is gone); a starved one and a sliver are not clipped (the guards).
## Saves go under user://test_crafting_<pid>, removed at the end.

var t := TestUtil.new()
var _dir := "user://test_crafting_%d" % OS.get_process_id()
const CLOCK := 1_800_000_000  # a "now" for the saves (unix seconds)
const OSSUARY_LOT := "lot-13"  # size 2, the Ossuary Tower's
const FORT := "whitecross"  # the simulacra's fort (cap 520), held in grace in _grace
var _cat = load("res://tests/test_catchup.gd")  # its harness configs (the field shrunk, no pre-warm)


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
	_deploy_refusals()
	_deploy()
	_raise_until_out()
	_corpses_kept()
	_stacking()
	_retake_live()
	_retake_caught_up()
	_save_mid_charge()
	_exhaustion()
	_guards()
	_husk_refusals()
	_husk_craft()
	_husk_kinds_follow_config()
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


# ------------------------------------------------------------------------------------- the husk craft (E4, v9) ----
## Adds remnants with these magnitudes (aspect wits, common), oldest first; returns their uids.
static func _rems(s: GameState, mags: Array) -> Array:
	var out: Array = []
	for m in mags:
		var uid := s._mint_uid("r")
		s.remnants.append({"uid": uid, "aspect": "wits", "rarity": "common", "magnitude": int(m)})
		out.append(uid)
	return out


## cmd_craft_husk's refusals in order (the sizing stop's ruling 2, lever (b)): unknown_kind before the remnants and the
## bone; then no_remnants (one short of craft.husk.remnants) before no_bone; then no_bone (a bone short); then at_cap
## (v10: the big undead and the husks waiting fill the crypt's big_undead cap; the bot's own room rule). None changes
## anything: rev, the husks, the remnants, the bone, the uid counter, the events; view_catalog's husk_craft agrees.
func _husk_refusals() -> void:
	var s := _mk()
	var n := int(s._req_f("economy.craft.husk.remnants"))
	var bone := s._req_f("economy.craft.husk.bone")
	s.remnants.clear()
	s.town_sim.bone = 0.0
	_rems(s, range(1, n))
	var snap := func() -> Array:
		return [s.rev, s.husks.duplicate(true), s.remnants.duplicate(true), s.town_sim.bone, s.next_uid, s._events.size()]
	var before: Array = snap.call()
	t.ok(s.cmd_craft_husk("lich") == {"ok": false, "reason": "unknown_kind", "husk": {}}, "a kind outside the t1 chest's: unknown_kind, before the remnants and the bone")
	t.ok(s.cmd_craft_husk("skeleton")["reason"] == "no_remnants" and s.view_catalog()["husk_craft"]["reason"] == "no_remnants",
		"%d remnants of %d: no_remnants, before the bone; the catalog agrees" % [n - 1, n])
	_rems(s, [9])
	s.town_sim.bone = bone - 1.0
	var cat: Dictionary = s.view_catalog()["husk_craft"]
	t.ok(s.cmd_craft_husk("zombie")["reason"] == "no_bone" and str(cat["reason"]) == "no_bone" and not bool(cat["can_craft"]),
		"enough remnants, a bone short of %.0f: no_bone; the catalog agrees (can_craft false)" % bone)
	before[2] = s.remnants.duplicate(true)
	before[3] = s.town_sim.bone
	before[4] = s.next_uid
	t.ok(snap.call() == before, "the refusals change nothing")
	s.town_sim.bone = bone
	cat = s.view_catalog()["husk_craft"]
	t.ok(bool(cat["can_craft"]) and str(cat["reason"]) == "" and float(cat["cost"]["bone"]) == bone and int(cat["cost"]["remnants"]) == n,
		"with the price in hand the catalog reads can_craft, and its cost is economy.json craft.husk's: %s" % str(cat))
	# at_cap (v10, the E4 review): the crypt's places are its big undead and the husks waiting, at the big_undead cap
	var cap := s._cap_of("big_undead")
	for i in cap - s.big_undead.size() - s.husks.size():
		s.husks.append({"uid": "hfill%d" % i, "kind": "skeleton", "rarity": "common"})
	before = snap.call()
	cat = s.view_catalog()["husk_craft"]
	t.ok(s.cmd_craft_husk("skeleton")["reason"] == "at_cap" and str(cat["reason"]) == "at_cap" and not bool(cat["can_craft"]),
		"big undead %d and husks waiting %d at the cap %d: at_cap; the catalog agrees" % [s.big_undead.size(), s.husks.size(), cap])
	t.ok(snap.call() == before, "at_cap changes nothing")
	s.town_sim.bone = bone - 1.0
	t.ok(s.cmd_craft_husk("skeleton")["reason"] == "no_bone", "at_cap is checked last: a bone short reads no_bone")
	s.town_sim.bone = bone
	s.husks.pop_back()
	s.big_undead.append({"uid": "bfill"})
	t.ok(s.cmd_craft_husk("skeleton")["reason"] == "at_cap", "a big undead takes a place as a waiting husk does")
	s.big_undead.pop_back()
	t.ok(bool(s.view_catalog()["husk_craft"]["can_craft"]) and bool(s.cmd_craft_husk("skeleton")["ok"]),
		"one place free: can_craft, and it crafts (the husk fills the last place)")
	_rems(s, range(1, n + 1))
	s.town_sim.bone = bone
	t.ok(s.cmd_craft_husk("skeleton")["reason"] == "at_cap" and s.view_catalog()["husk_craft"]["reason"] == "at_cap",
		"then, with the remnants and bone back, it reads at_cap again")


## A craft takes the weakest craft.husk.remnants (the smallest magnitude, then the oldest uid) and craft.husk.bone exactly,
## and adds {uid h<n>, kind, rarity common} to the husks (the extra is that record); rev + 1, no event; the mass ledger
## doesn't move (bone and remnants are not mass); the husk raises at the slab like a raid's.
func _husk_craft() -> void:
	var s := _mk()
	var n := int(s._req_f("economy.craft.husk.remnants"))
	var bone := s._req_f("economy.craft.husk.bone")
	s.remnants.clear()
	s.husks.clear()
	var mags: Array = []
	for i in n + 2:
		mags.append([3, 1, 2, 1, 5][i % 5])  # ties at 1 and the large ones kept
	var uids := _rems(s, mags)
	var want: Array = GameState.husk_craft_pick(s.remnants, n).map(func(r): return str(r["uid"]))
	var order: Array = range(mags.size())
	order.sort_custom(func(a, b): return int(mags[a]) < int(mags[b]) or (int(mags[a]) == int(mags[b]) and a < b))
	var expect: Array = order.slice(0, n).map(func(i): return str(uids[i]))
	t.ok(want == expect, "the pick is the %d weakest, smallest magnitude first, then the oldest: %s" % [n, str(want)])
	s.town_sim.bone = bone + 7.5
	var rev := s.rev
	var ev := s._events.size()
	var led := s.ledger()
	var r := s.cmd_craft_husk("skeleton")
	var left: Array = s.remnants.map(func(x): return str(x["uid"]))
	var gone := true
	for u in want:
		gone = gone and not left.has(u)
	t.ok(bool(r["ok"]) and gone and left.size() == mags.size() - n, "the craft takes exactly the picked remnants: %s left" % str(left))
	t.near(s.town_sim.bone, 7.5, 1e-9, "it takes craft.husk.bone (%.0f) exactly" % bone)
	var h: Dictionary = r["husk"]
	t.ok(s.husks.size() == 1 and s.husks[0] == h and str(h["kind"]) == "skeleton" and str(h["rarity"]) == "common"
		and str(h["uid"]).begins_with("h"), "it adds the husk it returns: %s" % str(h))
	t.ok(s.rev == rev + 1 and s._events.size() == ev, "rev + 1, no event")
	t.ok(s.ledger()["sinks"] == led["sinks"] and s.ledger()["sources"] == led["sources"] and GameState.Ledger.error(s.ledger()) < 1e-6,
		"the mass ledger doesn't move and stays balanced")
	var ri := s.cmd_raise_big_undead(str(h["uid"]), [left[0]], "Ground")
	t.ok(bool(ri["ok"]) and s.husks.is_empty(), "the crafted husk raises at the slab: %s" % str(ri["reason"]))


## The kinds follow loot.json chest_by_tier 1's husk_kinds: with ["siren"] there, a siren crafts and a skeleton is
## unknown_kind; view_catalog lists them.
func _husk_kinds_follow_config() -> void:
	var c := TestUtil.configs()
	c["loot"]["chest_by_tier"]["1"]["husk_kinds"] = ["siren"]
	var s := _mk(c)
	_rems(s, range(int(s._req_f("economy.craft.husk.remnants"))))
	s.town_sim.bone = s._req_f("economy.craft.husk.bone")
	t.ok(s.view_catalog()["husk_craft"]["kinds"] == ["siren"] and s.cmd_craft_husk("skeleton")["reason"] == "unknown_kind"
		and bool(s.cmd_craft_husk("siren")["ok"]), "the kinds are the t1 chest's (siren here): skeleton unknown_kind, siren crafts")
	t.ok(TestUtil.configs()["loot"]["chest_by_tier"]["1"]["husk_kinds"] == GameState.new(TestUtil.configs()).husk_craft_kinds(),
		"shipped: the kinds are loot.json chest_by_tier 1's: %s" % str(TestUtil.configs()["loot"]["chest_by_tier"]["1"]["husk_kinds"]))


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
	# E4 step 10: the Ossuary has one level (max_level 1); its L2 and L3 bought nothing (a level-2 Ossuary crafted as
	# level 1 did, one item a craft), so neither is offered, nor can one be placed
	var l2 := _mk()
	t.ok(int(l2._cfgs["buildings"]["ossuary_tower"]["max_level"]) == 1 and not l2.town_sim.place_building(OSSUARY_LOT, "ossuary_tower", 2)
		and l2.town_sim.place_building(OSSUARY_LOT, "ossuary_tower", 1) and l2.town_sim.built_effect("craft_slots") == 1.0,
		"the Ossuary has one level: a level 2 can't be placed, level 1 gives craft_slots 1")


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


# ============================================================================================== the simulacra ====
func _sims_at(s: GameState, fort_id: String) -> Array:
	return s.realm.simulacra.filter(func(sm): return str(sm["fort_id"]) == fort_id)


## [undead, dead, raised_by_sims] at FORT.
func _masses(s: GameState) -> Array:
	var f := s.realm.fort_by_id(FORT)
	return [float(f["undead"]), float(f["dead"]), s.realm.raised_by_sims]


## A new game (test_catchup's harness configs unless `c`) 2 s in with FORT held in grace (Vei ships nothing there and
## no wave targets it) holding only `dead` corpses: no living, no undead, the valve's WAR at 0 (the muster's WAR still
## stages there and kills nothing), the haul sent to Ashgate. Only a simulacrum moves its corpses: nothing kills,
## clears or hauls there.
func _grace(c := {}, dead := 400.0) -> GameState:
	var s := _mk(_cat.cfgs() if c.is_empty() else c)
	s.tick(2.0)
	s.cmd_set_haul_target("ashgate")
	s.cmd_debug_set_state({"valve": {"work": 0.4, "war": 0.0, "flood": 0.6}, "forts": {FORT: {"living": 0.0, "undead": 0.0, "dead": dead}}})
	s.realm.hold(FORT, 5000.0)
	s.drain_events()
	return s


## Each refusal in order: an unknown fort with none ready is unknown_fort, and with one ready too; a known fort with
## none ready is none_ready. A refusal changes nothing (rev, the stock, the realm's simulacra).
func _deploy_refusals() -> void:
	var s := _mk()
	var rv := s.rev
	t.ok(s.cmd_deploy_simulacrum("vei") == {"ok": false, "reason": "unknown_fort", "charges": 0.0, "ready_left": 0},
		"deploy at an unknown fort with none ready: unknown_fort, before none_ready")
	t.ok(s.cmd_deploy_simulacrum("vespers") == {"ok": false, "reason": "none_ready", "charges": 0.0, "ready_left": 0},
		"deploy with none ready: none_ready")
	s.simulacra_ready = 1
	t.ok(s.cmd_deploy_simulacrum("nowhere")["reason"] == "unknown_fort" and s.simulacra_ready == 1 and s.realm.simulacra.is_empty()
		and s.rev == rv, "one ready, an unknown fort: unknown_fort; the refusals change nothing")


## A deploy takes one from the stock and plants realm.json simulacrum's charges and rate at the fort: its extras are
## those charges and ready_left; view_fort shows them; rev + 1; no event. Any fort takes one (a held one too). The
## numbers follow the config.
func _deploy() -> void:
	var s := _mk()
	s.simulacra_ready = 3
	s.drain_events()
	var rv := s.rev
	var r := s.cmd_deploy_simulacrum("vespers")
	t.ok(r == {"ok": true, "reason": "", "charges": 300.0, "ready_left": 2} and s.simulacra_ready == 2 and s.rev == rv + 1,
		"deploy at Vespers: its charges (realm.json simulacrum.charges, 300) and ready_left 2: %s" % str(r))
	t.ok(s.realm.simulacra == [{"fort_id": "vespers", "charges": 300.0, "rate": 1.0}] and s.view_fort("vespers")["simulacrum_charges"] == 300.0
		and s.view_inventory()["simulacra_ready"] == 2 and s.drain_events().is_empty(),
		"RealmSim gets {vespers, 300, rate 1.0} (simulacrum.rate), view_fort shows its charges, no event: %s" % str(s.realm.simulacra))
	s.realm.hold("ashgate", 0.0)
	t.ok(s.cmd_deploy_simulacrum("ashgate")["ok"] and _sims_at(s, "ashgate").size() == 1, "a held fort takes one too")
	var c := TestUtil.configs()
	c["realm"]["simulacrum"] = {"rate": 2.5, "charges": 40.0}
	var o := _mk(c)
	o.simulacra_ready = 1
	t.ok(o.cmd_deploy_simulacrum("greywall") == {"ok": true, "reason": "", "charges": 40.0, "ready_left": 0}
		and o.realm.simulacra == [{"fort_id": "greywall", "charges": 40.0, "rate": 2.5}], "the charges and rate are realm.json simulacrum's (40, 2.5 here)")


## A planted simulacrum raises its fort's corpses at its rate, every substep, until its charges run out, then
## crumbles: at FORT (held in grace, 400 corpses, nothing else moving them) the shipped 300 charges at 1.0 mass/s last
## exactly 300 s; it raised 300 into the fort's undead, the corpses are 100, it raises nothing after. The ledger holds.
func _raise_until_out() -> void:
	var s := _grace()
	s.simulacra_ready = 1
	s.cmd_deploy_simulacrum(FORT)
	var f := s.realm.fort_by_id(FORT)
	var dt := s.substep_s()
	var t0 := s.t
	var at_rate := true
	var gone := -1.0
	for i in 700:
		var c0 := float(_sims_at(s, FORT)[0]["charges"]) if not _sims_at(s, FORT).is_empty() else 0.0
		s.tick(dt)
		if gone < 0.0:
			at_rate = at_rate and absf(float(f["r_raised"]) - 1.0) < 1e-9 and absf(c0 - 1.0 * dt - (float(_sims_at(s, FORT)[0]["charges"]) if not _sims_at(s, FORT).is_empty() else 0.0)) < 1e-9
			if _sims_at(s, FORT).is_empty():
				gone = s.t - t0
		if s.t - t0 >= 310.0:
			break
	t.ok(at_rate and absf(gone - 300.0) < 1e-6, "it raises at its rate (1.0 mass/s, its charges down 0.5 a substep) until they run out, %.1f s in, and crumbles" % gone)
	t.ok(absf(s.realm.raised_by_sims - 300.0) < 1e-6 and absf(float(f["dead"]) - 100.0) < 1e-6 and float(f["r_raised"]) == 0.0
		and s.view_fort(FORT)["simulacrum_charges"] == 0.0,
		"it raised its 300 charges (raised_by_sims %.4f), 100 corpses are left, and nothing is raised after it" % s.realm.raised_by_sims)
	t.ok(GameState.Ledger.error(s.ledger()) < 1e-9, "the ledger holds: %s" % String.num_scientific(GameState.Ledger.error(s.ledger())))


## MECHANICS §3.6: while it has charges the garrison's kills at its fort stay there as corpses (r_redirected, no
## r_dead_out), as at Relish's redirect; once it has crumbled they ship to Vei again. Vespers, unheld, with living and
## undead fighting and corpses to raise.
func _corpses_kept() -> void:
	var s := _mk(_cat.cfgs())
	s.tick(2.0)
	s.cmd_set_haul_target("ashgate")
	s.cmd_debug_set_state({"forts": {"vespers": {"living": 60.0, "undead": 20.0, "dead": 40.0}}})
	var f := s.realm.fort_by_id("vespers")
	s.tick(0.5)
	var before := [float(f["r_dead_out"]), float(f["r_redirected"])]
	s.simulacra_ready = 1
	s.cmd_deploy_simulacrum("vespers")
	s.tick(0.5)
	t.ok(before[0] > 0.0 and before[1] == 0.0 and float(f["r_dead_out"]) == 0.0 and float(f["r_redirected"]) > 0.0 and float(f["r_raised"]) > 0.0,
		"with charges its garrison's kills stay as corpses: %.3f mass/s kept, none shipped (before it, %.3f shipped)" % [float(f["r_redirected"]), before[0]])
	s.realm.simulacra[0]["charges"] = 0.25  # its last quarter: it runs out in the next substep
	s.tick(0.5)
	s.tick(0.5)
	t.ok(s.realm.simulacra.is_empty() and float(f["r_dead_out"]) > 0.0 and float(f["r_redirected"]) == 0.0 and float(f["r_raised"]) == 0.0,
		"once it has crumbled they ship to Vei again: %.3f mass/s" % float(f["r_dead_out"]))


## Several at one fort stack: view_fort's simulacrum_charges is their sum, and they raise side by side, each at its rate
## from its own charges.
func _stacking() -> void:
	var s := _grace()
	s.simulacra_ready = 2
	s.cmd_deploy_simulacrum(FORT)
	var r := s.cmd_deploy_simulacrum(FORT)
	t.ok(r["ready_left"] == 0 and _sims_at(s, FORT).size() == 2 and s.view_fort(FORT)["simulacrum_charges"] == 600.0,
		"two at one fort: view_fort sums their charges (%.1f)" % s.view_fort(FORT)["simulacrum_charges"])
	for i in 20:
		s.tick(0.5)
	var f := s.realm.fort_by_id(FORT)
	var ch: Array = _sims_at(s, FORT).map(func(sm): return float(sm["charges"]))
	t.ok(absf(float(f["r_raised"]) - 2.0) < 1e-9 and ch.size() == 2 and absf(float(ch[0]) - 290.0) < 1e-9 and absf(float(ch[1]) - 290.0) < 1e-9
		and absf(s.view_fort(FORT)["simulacrum_charges"] - 580.0) < 1e-9,
		"10 s on they raise 2.0 mass/s together, each down to 290 (%s), 580 shown" % str(ch))


## Greywall held and contested (no grace) with 60 living and no undead or corpses, no WAR (test_away's _greywall): its
## garrison sits at 0, so it is broken hold.break_s less 0.3 s in. A simulacrum planted there has nothing to raise.
func _contested(c: Dictionary) -> GameState:
	var s := _mk(c)
	s.tick(2.0)
	s.cmd_debug_set_state({"valve": {"work": 0.0, "war": 0.0, "flood": 1.0}, "forts": {"greywall": {"living": 60.0, "undead": 0.0, "dead": 0.0}}})
	s.realm.hold("greywall", 0.0)
	s.realm.fort_by_id("greywall")["zero_s"] = 0.3
	s.drain_events()
	return s


## Live: a retake loses the simulacrum planted at the fort, at the retake's substep, with its charges; one at another
## fort is kept.
func _retake_live() -> void:
	var s := _contested(_cat.cfgs())
	s.simulacra_ready = 2
	s.cmd_deploy_simulacrum("greywall")
	s.cmd_deploy_simulacrum("vespers")
	var held_until := -1.0
	var evs: Array = []
	for i in 400:
		s.tick(0.5)
		evs = s.drain_events().filter(func(e): return e["type"] == "fort_retaken")
		if not evs.is_empty():
			break
		if not _sims_at(s, "greywall").is_empty() and float(_sims_at(s, "greywall")[0]["charges"]) == 300.0:
			held_until = s.t
	t.ok(evs.size() == 1 and evs[0]["fort_id"] == "greywall" and held_until >= s.t - 0.5 - 1e-9,
		"(setup) Greywall is retaken at %.2f s, its simulacrum there unspent (300 charges) up to the substep before" % (float(evs[0]["t"]) if not evs.is_empty() else -1.0))
	t.ok(_sims_at(s, "greywall").is_empty() and s.view_fort("greywall")["simulacrum_charges"] == 0.0 and _sims_at(s, "vespers").size() == 1,
		"the retake loses the simulacrum at Greywall; Vespers' is kept")


## Caught up (IDLE I6): saved with a simulacrum at Greywall before it falls and loaded 10 min later (10 s steps): the
## catch-up's events hold the retake, and the simulacrum is gone, lost, not spent: nothing was raised there.
func _retake_caught_up() -> void:
	var c: Dictionary = _cat.cfgs({"economy.idle.catchup_max_steps": 60})
	var s := _contested(c)
	s.simulacra_ready = 1
	s.cmd_deploy_simulacrum("greywall")
	var raised0 := s.realm.raised_by_sims
	s.clock_override = CLOCK
	t.ok(s.cmd_save("retake")["ok"], "(setup) saved with a simulacrum at Greywall")
	var n := _mk(c)
	n.clock_override = CLOCK + 600
	t.ok(n.cmd_load("retake")["ok"] and n._catchup.dt == 10.0, "(setup) loaded 10 min later, caught up at 10 s steps")
	var rt: Array = n.catchup_events().filter(func(e): return e["type"] == "fort_retaken" and e["fort_id"] == "greywall")
	t.ok(rt.size() == 1 and n.realm.simulacra.is_empty() and n.view_fort("greywall")["simulacrum_charges"] == 0.0 and n.realm.raised_by_sims == raised0,
		"away, Greywall fell (%.1f s in) and its simulacrum was lost with it, unspent: %s" % [float(rt[0]["t"]) - s.t if not rt.is_empty() else -1.0, str(n.realm.simulacra)])


## save -> load mid-charge: 60 s into its 300, the save holds it as RealmSim does ({fort_id, charges 240, rate}), a
## fresh state loading it shows the same, and from there both run it out at the same substep with the same masses.
func _save_mid_charge() -> void:
	var s := _grace()
	s.simulacra_ready = 1
	s.cmd_deploy_simulacrum(FORT)
	for i in 120:
		s.tick(0.5)
	s.clock_override = CLOCK
	t.ok(s.cmd_save("mid")["ok"], "(setup) saved 60 s into its charges")
	var n := _mk(_cat.cfgs())
	n.clock_override = CLOCK
	t.ok(n.cmd_load("mid")["ok"], "(setup) loaded at once (nothing to catch up)")
	t.ok(n.to_dict()["realm"]["simulacra"] == [{"fort_id": FORT, "charges": 240.0, "rate": 1.0}] and n.realm.simulacra == s.realm.simulacra
		and n.view_fort(FORT)["simulacrum_charges"] == 240.0, "the load keeps it: %s" % str(n.realm.simulacra))
	var gone := [-1.0, -1.0]
	for i in 500:
		for k in 2:
			var g: GameState = [s, n][k]
			g.tick(0.5)
			if gone[k] < 0.0 and g.realm.simulacra.is_empty():
				gone[k] = g.t
	var ms := _masses(s)
	var mn := _masses(n)
	var same := true
	for i in 3:
		same = same and absf(float(ms[i]) - float(mn[i])) <= 1e-9 * maxf(1.0, absf(float(ms[i])))
	t.ok(gone[0] > 0.0 and gone[0] == gone[1] and same, "the loaded game runs it out when the unsaved one does (%.1f s), the fort's masses the same: %s vs %s" % [
		float(gone[1]), str(ms), str(mn)])


## The exhaustion against live (the run's manager's required test; IDLE §4): FORT held in grace with only its corpses,
## the shipped simulacrum planted and 7.5 s run live, so it runs out 292.5 s after the save: inside a 15 s step of a
## catch-up stepping at idle.catchup_dt_long_s from its start (catchup_dt_long_after_s 0, catchup_max_steps 1).
## Without the clip (E3-4 measured it, and the clip's revert reads it) that step raised its last 7.5 charges over all
## 15 s: at its end, 300 s in, the fort's undead read 13.99 against live's 12.89 (+1.09 mass, +8.5%), still +1.2%
## 60 s on, with the dead and raised mass exact; it was gone 7.5 s late. Clipped (Catchup.simulacrum_out_s), a step
## ends at the exhaustion: it is gone at live's moment, and the undead, dead and raised mass match live within
## idle.catchup_tol there, at the next step's end and at the catch-up's end (10 min).
func _exhaustion() -> void:
	var c: Dictionary = _cat.cfgs()
	var cu_c: Dictionary = _cat.cfgs({"economy.idle.catchup_max_steps": 1, "economy.idle.catchup_dt_long_after_s": 0.0})
	var long_s := float(c["economy"]["idle"]["catchup_dt_long_s"])
	var tol := float(c["economy"]["idle"]["catchup_tol"])
	var span := 600.0
	var s := _grace(c)
	s.simulacra_ready = 1
	s.cmd_deploy_simulacrum(FORT)
	for i in 15:
		s.tick(0.5)
	var js := JSON.stringify(s.to_dict())
	var live := GameState.new(c)
	live.from_dict(JSON.parse_string(js))
	var t0 := live.t
	var rows := {}
	var gone_live := -1.0
	while live.t < t0 + span - 1e-9:
		live.tick(live.substep_s())
		rows[snappedf(live.t - t0, 0.5)] = _masses(live)
		if gone_live < 0.0 and live.realm.simulacra.is_empty():
			gone_live = live.t - t0
	var cu := GameState.new(cu_c)
	cu.from_dict(JSON.parse_string(js))
	cu._catchup.begin(cu, span, false)
	cu._catchup.trace = []
	var gone_cu := -1.0
	var at := {}  # seconds after t0 -> the caught-up masses: the exhaustion, the next step's end, the catch-up's end
	while cu._catchup.active:
		cu._catchup.run(cu, 1)
		var k := snappedf(cu.t - t0, 0.5)
		if gone_cu < 0.0 and cu.realm.simulacra.is_empty():
			gone_cu = cu.t - t0
			at[k] = _masses(cu)
		elif gone_cu >= 0.0 and at.size() == 1:
			at[k] = _masses(cu)
	at[snappedf(cu.t - t0, 0.5)] = _masses(cu)
	var steps: Array = cu._catchup.trace
	var ends_there := steps.any(func(e): return absf(float(e[0]) + float(e[1]) - (t0 + gone_live)) < 1e-9)
	t.ok(absf(gone_live - 292.5) < 1e-9 and fmod(gone_live, long_s) > 1e-6 and float(steps[0][1]) == long_s,
		"live: it runs out %.1f s after the save, inside a %.0f s catch-up step (the catch-up's first step %.1f s)" % [gone_live, long_s, float(steps[0][1])])
	t.ok(ends_there and absf(gone_cu - gone_live) < 1e-9, "caught up, a step ends at the exhaustion: gone %.2f s in, live %.2f s (unclipped: 300 s, 7.5 s late)" % [gone_cu, gone_live])
	var worst := 0.0
	var parts: Array = []
	var keys := at.keys()
	keys.sort()
	for k in keys:
		var a: Array = at[k]
		var b: Array = rows.get(k, [])
		if b.is_empty():
			worst = INF
			continue
		var es: Array = []
		for i in 3:
			var e := absf(float(a[i]) - float(b[i])) / maxf(absf(float(b[i])), 1.0)
			es.append(e)
			worst = maxf(worst, e)
		parts.append("%.1f s: undead %.4f vs %.4f (%.4f%%), dead %.4f vs %.4f, raised %.4f vs %.4f" % [k, a[0], b[0], 100.0 * float(es[0]), a[1], b[1], a[2], b[2]])
	t.ok(keys.size() == 3 and worst <= tol and GameState.Ledger.error(cu.ledger()) < 1e-9 and GameState.Ledger.error(live.ledger()) < 1e-9,
		"clipped, the fort's undead, dead and raised mass match live within idle.catchup_tol (%.0f%%; worst %.4f%%), both ledgers balanced: %s" % [
		100.0 * tol, 100.0 * worst, "; ".join(PackedStringArray(parts))])


## The clip's guards (Catchup.simulacrum_out_s): neither changes a catch-up's steps.
## - corpses: a starved simulacrum (10 charges left, under one 15 s step's raise, at FORT with no corpses) raises
##   nothing and runs out never; a 10 min catch-up at 15 s steps takes as many steps as with none planted (without the
##   guard each step would end 10 s in);
## - the floor: a sliver (0.25 charges, under one substep's raise, with corpses) is not clipped either: as many steps
##   as with none, and it is gone at the first step's end.
func _guards() -> void:
	var cu_c: Dictionary = _cat.cfgs({"economy.idle.catchup_max_steps": 1, "economy.idle.catchup_dt_long_after_s": 0.0})
	var steps_of := func(js: String) -> Array:
		var g := GameState.new(cu_c)
		g.from_dict(JSON.parse_string(js))
		g._catchup.begin(g, 600.0, false)
		g._catchup.run(g)
		return [g._catchup.steps, g.realm.simulacra.duplicate(true)]
	for pair in [[0.0, 10.0, "starved: 10 charges, no corpses"], [400.0, 0.25, "a sliver: 0.25 charges, 400 corpses"]]:
		var s := _grace(cu_c, float(pair[0]))
		var none: Array = steps_of.call(JSON.stringify(s.to_dict()))
		s.simulacra_ready = 1
		s.cmd_deploy_simulacrum(FORT)
		s.realm.simulacra[0]["charges"] = float(pair[1])
		var got: Array = steps_of.call(JSON.stringify(s.to_dict()))
		var left: Array = got[1]
		var kept := left.is_empty()
		if float(pair[0]) == 0.0:
			kept = left.size() == 1 and absf(float(left[0]["charges"]) - 10.0) < 1e-9
		t.ok(int(none[0]) == 40 and int(got[0]) == int(none[0]) and kept,
			"%s: a 10 min catch-up takes %d steps, as with none planted (%d); it is %s: %s" % [pair[2], int(got[0]), int(none[0]),
			"still there, unspent" if float(pair[0]) == 0.0 else "gone", str(left)])
