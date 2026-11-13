extends RefCounted
## GameState macro wiring (MECHANICS §1.3, §3.2–§3.4, §10): the valve slew and split, Relish's
## tide and redirect as RealmSim inputs, the substep order, and the flip's hold and expiry.
## The influence field is shrunk in memory (a copy of the configs, never realm.json) so a new game
## and its substeps stay cheap; nothing here reads the field.

var t := TestUtil.new()
var _base := {}


func _mk() -> GameState:
	if _base.is_empty():
		_base = TestUtil.configs()
		var fld: Dictionary = _base["realm"]["field"]
		fld["tick_hz"] = 0.01
		fld["w"] = 8
		fld["h"] = 6
	var s := GameState.new(_base.duplicate(true))
	s.debug_enabled = true
	s.cmd_new_game(1)
	return s


func _sum(v: Dictionary) -> float:
	return float(v["work"]) + float(v["war"]) + float(v["flood"])


func _l1(a: Dictionary, b: Dictionary) -> float:
	return absf(a["work"] - b["work"]) + absf(a["war"] - b["war"]) + absf(a["flood"] - b["flood"])


func _fort(s: GameState, id: String) -> Dictionary:
	return s.realm.fort_by_id(id)


## old-sluice's WAR share over ashgate's, from the last substep.
func _ratio(s: GameState) -> float:
	return _fort(s, "old-sluice")["r_in"] / _fort(s, "ashgate")["r_in"]


func run() -> int:
	t.suite("game_state_macro")
	_valve()
	_split()
	_effects()
	_order()
	_flip()
	_legacy_realm_keys()
	return t.failures


# ------------------------------------------------------------------ the valve ----
func _valve() -> void:
	var s := _mk()
	var open: Dictionary = TestUtil.configs()["economy"]["opening"]["valve"]
	t.ok(s.valve == s.valve_target, "a new game starts with current = target")
	t.near(s.valve["war"], float(open["war"]), 1e-12, "the start valve is economy.json opening.valve")
	var start: Dictionary = s.valve.duplicate()
	var rv := s.rev
	var r := s.cmd_set_valve(0, 0, 1)
	t.ok(r["ok"] and s.valve_target == {"work": 0.0, "war": 0.0, "flood": 1.0} and s.valve == start,
		"cmd_set_valve sets the target only")
	t.ok(s.rev == rv + 1, "and bumps rev")
	var refused := s.cmd_set_valve(0, 0, 0)
	t.ok(refused == {"ok": false, "reason": "zero_valve", "target": {}} and s.rev == rv + 1
		and s.valve_target["flood"] == 1.0, "cmd_set_valve(0, 0, 0) is refused and changes nothing")
	var rate := float(TestUtil.configs()["realm"]["valve"]["slew_per_s"])
	var l1 := _l1(start, s.valve_target)
	var n := ceili(l1 / (rate * s.substep_s()) - 1e-9)
	var sum_ok := true
	var line_ok := true
	var step_ok := true
	var prev := l1
	for i in n:
		s.tick(s.substep_s())
		if absf(_sum(s.valve) - 1.0) > 1e-12 or s.valve.values().any(func(x): return x < 0.0):
			sum_ok = false
		var left := _l1(s.valve, s.valve_target)
		if i < n - 1:
			if absf(prev - left - rate * s.substep_s()) > 1e-9:
				step_ok = false
			# on the straight line from start to target
			var f := 1.0 - left / l1
			for k in ["work", "war", "flood"]:
				if absf(s.valve[k] - (start[k] + (s.valve_target[k] - start[k]) * f)) > 1e-9:
					line_ok = false
		if i == n - 2:
			t.ok(s.valve != s.valve_target, "one substep short of L1/slew it is not there yet")
		prev = left
	t.ok(sum_ok, "the slew keeps the sum at 1 (and no negative component) at every substep")
	t.ok(step_ok, "each substep moves slew_per_s · dt of L1 distance")
	t.ok(line_ok, "along the straight line from the start to the target")
	t.ok(s.valve == s.valve_target, "it reaches the target in L1/slew = %.1f s (%d substeps)" % [l1 / rate, n])
	s.tick(s.substep_s())
	t.ok(s.valve == s.valve_target, "and stays there")
	# debug set_state sets both at once
	s.cmd_debug_set_state({"valve": {"work": 1, "war": 1, "flood": 0}})
	t.ok(s.valve == s.valve_target, "cmd_debug_set_state sets current and target")


# ------------------------------------------------------------------ the split ----
func _split() -> void:
	var s := _mk()
	var w0 := s.work_pending
	var work_sum := 0.0
	var ok := true
	for i in 20:
		s.tick(s.substep_s())
		var sp: Dictionary = s._split
		if absf(sp["work"] + sp["war"] + sp["flood"] - sp["mint"]) > 1e-9 * maxf(1.0, sp["mint"]):
			ok = false
		for k in ["work", "war", "flood"]:
			if absf(sp[k] - sp["mint"] * s.valve[k]) > 1e-12:
				ok = false
		work_sum += sp["work"] * s.substep_s()
	t.ok(s._split["mint"] > 0.0, "the interim (legacy) mint runs: %.2f mass/s" % s._split["mint"])
	t.ok(ok, "work + war + flood = mint, each its valve share, every substep")
	t.near(s.work_pending - w0, work_sum, 1e-9, "WORK accumulates in work_pending (no consumer until TownSim)")
	var inp: Dictionary = s._realm_inputs
	t.ok(inp["war"] == s._split["war"] and inp["flood"] == s._split["flood"], "WAR and FLOOD are RealmSim's inputs")
	t.near(s.realm.cov["r_out"], s._split["war"] + s._split["flood"], 1e-12, "RealmSim received them")
	t.ok(inp["digest_q"] == s.quality(), "digest_q is the legacy quality() for now")


# ----------------------------------------------------- Relish's tide and redirect ----
func _inputs_none(s: GameState, tag: String) -> void:
	s.tick(s.substep_s())
	var i: Dictionary = s._realm_inputs
	var fx: Dictionary = s.view_relish()["effects"]
	t.ok(i["tide_fort"] == "" and i["redirect_fort"] == "" and fx["tide_fort"] == "" and fx["redirect_fort"] == "",
		"%s: no tide, no redirect (%s)" % [tag, str(i)])


func _effects() -> void:
	var cfg: Dictionary = TestUtil.configs()["realm"]["relish"]
	var home := _mk()
	_inputs_none(home, "home")
	t.ok(home.view_relish()["effects"]["home"] == true, "home: effects.home")
	var plain := _ratio(home)

	var s := _mk()
	s.legacy_teleport_relish("old-sluice")
	var fx: Dictionary = s.view_relish()["effects"]
	t.ok(fx == {"tide_fort": "old-sluice", "redirect_fort": "old-sluice", "home": false}, "at a fort: tide and redirect there (%s)" % str(fx))
	s.tick(s.substep_s())
	var i: Dictionary = s._realm_inputs
	t.ok(i["tide_fort"] == "old-sluice" and i["redirect_fort"] == "old-sluice", "RealmSim gets her fort as tide and redirect")
	t.ok(i["tide_bias"] == float(cfg["tide_bias"]) and i["redirect_rate"] == float(cfg["raise_rate"]),
		"at relish.tide_bias (%s) and relish.raise_rate (%s)" % [i["tide_bias"], i["redirect_rate"]])
	t.near(_ratio(s), plain * float(cfg["tide_bias"]), 1e-9, "the tide triples her fort's WAR weight")
	var vf := s.view_fort("old-sluice")
	t.ok(vf["tide"] and vf["redirect"] and vf["relish_here"], "view_fort: tide and redirect at her fort")
	t.ok(not s.view_fort("ashgate")["tide"] and not s.view_fort("ashgate")["redirect"], "and nowhere else")
	var f := _fort(s, "old-sluice")
	s.tick(s.substep_s())
	t.ok(f["r_dead_out"] == 0.0 and f["r_redirected"] > 0.0, "her fort keeps its garrison kills")

	# in its dungeon: tide only
	var b := s.cmd_begin_dungeon("old-sluice")
	t.ok(b["ok"], "begin the dungeon")
	t.ok(s.view_relish()["effects"] == {"tide_fort": "old-sluice", "redirect_fort": "", "home": false}, "in its dungeon: tide only")
	s.tick(s.substep_s())
	i = s._realm_inputs
	t.ok(i["tide_fort"] == "old-sluice" and i["redirect_fort"] == "", "RealmSim gets the tide, not the redirect")
	vf = s.view_fort("old-sluice")
	t.ok(vf["tide"] and not vf["redirect"], "view_fort: tide, no redirect")
	t.ok(f["r_dead_out"] > 0.0 and f["r_redirected"] == 0.0, "garrison kills ship again")
	s.cmd_abort_dungeon()

	# travelling, dead, at Vei, home again
	s.cmd_move_relish("ashgate")
	_inputs_none(s, "travelling")
	t.ok(s.view_relish()["state"] == "travelling", "(still travelling)")
	s.legacy_teleport_relish("old-sluice")
	s.relish["state"] = "dead"
	_inputs_none(s, "dead")
	s.relish["state"] = "at_fort"
	s.legacy_teleport_relish("vei")
	_inputs_none(s, "at Vei")
	s.legacy_teleport_relish("covington")
	_inputs_none(s, "home")

	# home's one live effect: relish.home_stance_bonus extra stance slots
	s._cfgs["realm"]["relish"]["home_stance_bonus"] = 2
	var base := int(s._cfgs["economy"]["stance"]["base_slots"])
	t.ok(s._stance_slots() == base + 2, "home: base + relish.home_stance_bonus stance slots")
	s.legacy_teleport_relish("old-sluice")
	t.ok(s._stance_slots() == base, "away: base slots")


# -------------------------------------------------------------- the order contract ----
## §3: valve (3) before Relish (4) before RealmSim (5). In the substep where she arrives, RealmSim
## already sees her tide, and the WAR it gets is the mint split by this substep's slewed valve.
## (Steps 3 and 4 do not read each other, so their relative order shows only in the code.)
func _order() -> void:
	var home := _mk()
	home.tick(home.substep_s())
	var plain := _ratio(home)
	var s := _mk()
	var eta: float = s.cmd_move_relish("old-sluice")["eta_s"]
	var before := ceili(eta / s.substep_s()) - 1
	for i in before:
		s.tick(s.substep_s())
	t.ok(s.view_relish()["state"] == "travelling" and s._realm_inputs["tide_fort"] == "", "still on the road before her arrival substep")
	s.cmd_set_valve(0, 1, 0)
	var v_before: Dictionary = s.valve.duplicate()
	s.tick(s.substep_s())
	t.ok(s.view_relish()["state"] == "at_fort", "she arrives in this substep")
	t.ok(s._realm_inputs["tide_fort"] == "old-sluice", "RealmSim saw her arrival in the same substep (Relish before RealmSim)")
	t.near(_ratio(s), plain * 3.0, 1e-9, "the tide shaped this substep's dispatch")
	t.ok(s.valve != v_before, "the valve slewed in this substep")
	t.near(s._realm_inputs["war"], s._split["mint"] * s.valve["war"], 1e-12, "RealmSim got the mint split by the slewed valve (valve before RealmSim)")
	t.ok(absf(s._realm_inputs["war"] - s._split["mint"] * v_before["war"]) > 1e-6, "not by the pre-slew valve")


# ------------------------------------------------------------------- the flip ----
func _flip() -> void:
	var s := _mk()
	s.legacy_teleport_relish("old-sluice")
	var b := s.cmd_begin_dungeon("old-sluice")
	var r := Results.from_v1("raid", {"fort_id": "old-sluice"}, b["seed"])
	r["warden_beaten"] = true
	r["retreated"] = false
	var ar := s.apply_result("raid", r)
	t.ok(ar["ok"], "a won dungeon applies: %s" % str(ar))
	var f := _fort(s, "old-sluice")
	var vf := s.view_fort("old-sluice")
	t.ok(f["held_s"] == 375.0 and f["held"] == true, "the flip sets the RealmSim fort's held_s (375)")
	t.ok(vf["held"] and vf["held_s_left"] == 375.0 and s.view_realm()["held_count"] == 1, "view_fort held, held_s_left; held_count 1")
	s.drain_events()
	s.tick(s.substep_s())
	t.ok(f["r_shipped"] == 0.0 and s.view_fort("old-sluice")["ship_in"] == 0.0, "Vei ships nothing into a held fort")
	t.near(f["held_s"], 375.0 - s.substep_s(), 1e-9, "the hold counts down")
	s.tick(375.0 - 2.0 * s.substep_s())
	t.ok(s.drain_events().filter(func(e): return e["type"] == "fort_retaken").is_empty() and f["held_s"] > 0.0,
		"no retake while time is left (%.2f s)" % f["held_s"])
	s.tick(s.substep_s())
	var evs := s.drain_events().filter(func(e): return e["type"] == "fort_retaken")
	t.ok(evs == [{"type": "fort_retaken", "fort_id": "old-sluice", "cause": "expired", "t": s.t}],
		"expiry re-emits fort_retaken with this substep's t: %s" % str(evs))
	t.ok(not s.view_fort("old-sluice")["held"] and s.view_realm()["held_count"] == 0, "the fort is no longer held")


# ------------------------------------------------- saves with legacy realm keys ----
func _legacy_realm_keys() -> void:
	var s := _mk()
	var d := TestUtil.load_json("res://tests/fixtures/midgame_2flips.json")
	d["realm"]["relish"] = {"at": "covington", "target": "", "state": "raising", "progress": 0.0, "travel_total": 0.0}
	d["realm"]["directShare"] = 0.22
	t.ok(s.from_dict(d)["ok"], "a save whose realm carries relish/directShare-era keys loads")
	var out: Dictionary = s.to_dict()["realm"]
	t.ok(not out.has("relish") and not out.has("directShare"), "and they are dropped")
	t.ok(s.view_realm()["held_count"] == 2 and _fort(s, "ashgate")["held"], "the fixture's holds are live after a load")
