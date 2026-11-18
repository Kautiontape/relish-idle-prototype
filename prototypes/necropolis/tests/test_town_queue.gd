extends RefCounted
## The Build tab's real queue (town-i M2, Q-e): a gated entry reads "queued: waits for <tier>" and keeps its place,
## the start comes from the view's `affordable_in_s` (R2), a never-affordable head names its store and its
## `starved` cause, the reorder order cmd_reorder_queue takes, and the mill's starved cause in the HUD.

var t: TestUtil
var cfg: Dictionary
var vcfg: Dictionary


func run() -> int:
	t = TestUtil.new()
	t.suite("town-queue")
	cfg = TestUtil.configs()
	vcfg = cfg["town"]["view"]
	_swap()
	_gate_wait()
	_affordable()
	_never()
	_hud_starved()
	return t.failures


func _state(fixture: String) -> GameState:
	var s := GameState.new(cfg)
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture(fixture)["ok"], "(setup) %s loads" % fixture)
	return s


func _catalog(s: GameState) -> Dictionary:
	var out := {}
	for r in s.view_catalog()["buildings"]:
		out[String(r["building_id"])] = r
	return out


func _swap() -> void:
	t.ok(BuildSort.swap_order(3, 0, 1) == [1, 0, 2], "reorder: moving the head down swaps it with the second")
	t.ok(BuildSort.swap_order(3, 2, -1) == [0, 2, 1], "reorder: moving the last up swaps it with the one above")
	t.ok(BuildSort.swap_order(3, 2, 1) == [0, 1, 2] and BuildSort.swap_order(3, 0, -1) == [0, 1, 2], "reorder: out of range is the identity")
	var s := _state("day1")
	s.cmd_debug_grant({"gold": 500.0, "bone": 200.0})
	t.ok(s.cmd_queue_build("house", "lot-05")["ok"] and s.cmd_queue_build("well", "lot-06")["ok"], "(setup) two entries queued")
	var r: Dictionary = s.cmd_reorder_queue(BuildSort.swap_order(2, 0, 1))
	var q: Array = s.view_town()["queue"]
	t.ok(r["ok"] and q.size() == 2 and q[0]["building_id"] == "well" and q[1]["building_id"] == "house",
		"reorder: cmd_reorder_queue takes swap_order's permutation (%s)" % str(q.map(func(e): return e["building_id"])))


## Midgame is a Village: a Town-tier building that fits a free lot queues, the walk skips it as needs_tier, and the row
## says it waits for Town. (Day 1's free lots are all size 1; every Village building is size 2.)
func _gate_wait() -> void:
	var s := _state("midgame_2flips")
	var cat := _catalog(s)
	var bid := ""  # a Village building a free day-1 lot fits
	for id in cat:
		if cat[id]["reason"] == "needs_tier" and cat[id]["requires"]["tier"] == "town" and not (cat[id]["lots"] as Array).is_empty() \
				and cat[id]["requires"]["blueprint"] == "":
			bid = id
			break
	t.ok(bid != "" and BuildSort.can_queue(cat[bid], vcfg), "(setup) midgame has a tier-gated Town row with a free lot (%s), so its Queue shows" % bid)
	if bid == "":
		return
	var r: Dictionary = s.cmd_queue_build(bid, String(cat[bid]["lots"][0]))
	t.ok(r["ok"], "a tier-gated %s queues (the T3.2 ruling): %s" % [bid, r.get("reason", "")])
	var e: Dictionary = s.view_town()["queue"][0]
	var st := BuildSort.stocks({"town": s.view_town(), "hud": s.view_hud(), "catalog": s.view_catalog(), "inventory": s.view_inventory()})
	t.ok(e["status"] == "skipped_gate" and e["reason"] == "needs_tier" and BuildSort.is_gate_wait(e, vcfg),
		"its row is skipped_gate needs_tier: a gate it waits out")
	var line := BuildSort.skip_text(e, cat, st, cfg["buildings_view"], vcfg)
	t.ok(line == "queued: waits for Town", "the row reads 'queued: waits for Town': '%s'" % line)
	var g: Array = BuildSort.ghosts([e], cat, st, cfg["buildings_view"], vcfg)
	t.ok(g[0]["shape"] == "plain" and g[0]["text"] == line, "its canvas ghost is plain, not struck, with the same words")
	var taken := e.duplicate()
	taken["reason"] = "lot_taken"
	t.ok(not BuildSort.is_gate_wait(taken, vcfg) and BuildSort.skip_text(taken, cat, st, cfg["buildings_view"], vcfg).begins_with("skipped: "),
		"a lot taken by another build is a real skip: 'skipped: …'")
	var rel := e.duplicate()
	rel["reason"] = "no_relics"
	rel["cost"] = {"gold": 0.0, "bone": 0.0, "relics": 2}
	t.ok(BuildSort.skip_text(rel, cat, st, cfg["buildings_view"], vcfg) == "queued: waits for 2 relics: raid a fort",
		"a relic gate reads 'queued: waits for 2 relics: raid a fort'")
	t.ok(BuildSort.queue_etas([e], st, cat, s.view_town(), 1.0, vcfg) == [""], "a gated row has no start time (it says why instead)")


## The start comes from the view's affordable_in_s: 0 now, > 0 a wait.
func _affordable() -> void:
	var st := {"gold": 0.0, "bone": 0.0, "rates": {"gold": 1.0, "bone": 1.0}}
	var head := {"building_id": "house", "lot_id": "lot-05", "status": "waiting_funds", "cost": {"gold": 999.0, "bone": 0.0},
		"affordable_in_s": 120.0, "level": 1}
	var later := head.duplicate()
	later["status"] = "queued"
	later["affordable_in_s"] = 0.0
	var etas := BuildSort.queue_etas([head, later], st, {}, {}, -1.0, vcfg)
	t.ok(String(etas[0]).begins_with("starts in ~2 min"), "a head affordable in 120 s starts in ~2 min, not the local estimate: '%s'" % etas[0])
	t.ok(String(etas[1]).begins_with(String(vcfg["queue_text"]["eta_later_now"])), "affordable now behind it: '%s'" % etas[1])


func _never() -> void:
	var e := {"status": "waiting_funds", "affordable_in_s": -1.0, "short": {"gold": 0.0, "bone": 25.0}, "starved": "pits_first",
		"cost": {"gold": 0.0, "bone": 25.0}, "building_id": "house", "level": 1}
	var line := BuildSort.never_text(e, vcfg)
	t.ok(line.begins_with("can't be afforded at today's bone income") and line.contains("raise WAR"),
		"a never-affordable head names its store and the pits-first cause with its lever: '%s'" % line)
	var behind := {"status": "queued", "affordable_in_s": -1.0, "short": {"gold": 0.0, "bone": 0.0}}
	t.ok(BuildSort.never_text(behind, vcfg) == String(vcfg["queue_text"]["eta_behind"]), "an entry stuck behind it says it waits for the one ahead")
	t.ok(BuildSort.queue_etas([e], {"gold": 0.0, "bone": 0.0, "rates": {}}, {}, {}, -1.0, vcfg)[0] == line, "the queue's ETA line is that text")


func _hud_starved() -> void:
	var views := {"hud": {"rates": [{"id": "bone", "rate": 0.0, "stock": 10.0, "cap": 300.0}]},
		"town": {"buildings": [{"building_id": "bone_mill", "level": 1, "staffed": 2.0, "starved": "pits_first"}]}}
	var hcfg: Dictionary = vcfg["hud"]
	var line := HudModel.stuck_line("bone", "bone_mill", views, hcfg, cfg["buildings_view"])
	t.ok(line.contains("the pits take every body before the Bone Mill") and line.contains("raise WAR"),
		"the HUD names the mill's own cause and its lever: '%s'" % line)
	views["town"]["buildings"][0]["starved"] = "no_bodies"
	line = HudModel.stuck_line("bone", "bone_mill", views, hcfg, cfg["buildings_view"])
	t.ok(line.contains("no bodies coming in"), "no bodies at all reads so: '%s'" % line)
	views["town"]["buildings"][0]["starved"] = ""
	line = HudModel.stuck_line("bone", "bone_mill", views, hcfg, cfg["buildings_view"])
	t.ok(line.contains("is starved: no bodies"), "with no cause given the old line stands: '%s'" % line)
