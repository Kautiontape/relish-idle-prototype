extends RefCounted
## GameState macro wiring (MECHANICS §1.3, §2.2, §3.2–§3.5, §10): the valve slew and split, Relish's
## tide and redirect as RealmSim inputs, the substep order, the flip's hold and expiry, the tithe
## through GameState, q from circles, the sustained-differential readout and the live lanes.
## The influence field is shrunk in memory (a copy of the configs, never realm.json) so a new game
## and its substeps stay cheap; nothing here reads the field.

var t := TestUtil.new()
var _base := {}


## `substep` > 0 coarsens economy.json sim.substep_s in this copy (the 12 h q case).
func _mk(substep := 0.0) -> GameState:
	if _base.is_empty():
		_base = TestUtil.configs()
		var fld: Dictionary = _base["realm"]["field"]
		fld["tick_hz"] = 0.01
		fld["w"] = 8
		fld["h"] = 6
	var cfgs: Dictionary = _base.duplicate(true)
	if substep > 0.0:
		cfgs["economy"]["sim"]["substep_s"] = substep
	var s := GameState.new(cfgs)
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
	_tithe()
	_q()
	_readout()
	_lanes()
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
	var ok := true
	var pending_ok := true
	for i in 20:
		s.tick(s.substep_s())
		var sp: Dictionary = s._split
		if absf(sp["work"] + sp["war"] + sp["flood"] - sp["mint"] - sp["muster"]) > 1e-9 * maxf(1.0, sp["mint"]):
			ok = false
		for k in ["work", "war", "flood"]:
			if absf(sp[k] - sp["mint"] * s.valve[k] - (sp["muster"] if k == "war" else 0.0)) > 1e-12:
				ok = false
		pending_ok = pending_ok and s.work_pending == 0.0 and absf(float(s.town_sim.rates["workers"]["in"]) * s.worker_mass() - sp["work"]) <= 1e-12 * maxf(1.0, sp["work"])
	t.ok(s._split["mint"] > 0.0, "the mint runs: %.2f mass/s" % s._split["mint"])
	t.ok(ok, "work + war + flood = mint + muster, each its valve share (WAR plus muster), every substep")
	t.ok(pending_ok, "TownSim takes each substep's WORK in that substep (work_pending stays 0)")
	var inp: Dictionary = s._realm_inputs
	t.ok(inp["war"] == s._split["war"] and inp["flood"] == s._split["flood"], "WAR and FLOOD are RealmSim's inputs")
	t.near(s.realm.cov["r_out"], s._split["war"] + s._split["flood"], 1e-12, "RealmSim received them")
	t.ok(inp["digest_q"] == s.digest_q() and s.quality() == s.digest_q(), "digest_q is q (quality() forwards to it)")


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


# ------------------------------------------------------------- helpers (E2a) ----
## Relish raids `fort` (teleported there); `raised` are the result's buckets. Returns apply_result's.
## `dead` < 0 tops the fort's dead up to what the buckets raise (so the EMA is unclamped); >= 0 sets it.
func _raid(s: GameState, fort: String, raised: Array, beaten := false, dead := -1.0) -> Dictionary:
	s.legacy_teleport_relish(fort)
	var want := 0.0
	for e in raised:
		want += float(e["mass"])
	var fd: Dictionary = s.realm.fort_by_id(fort)
	fd["dead"] = maxf(float(fd["dead"]), want) if dead < 0.0 else dead
	var b := s.cmd_begin_dungeon(fort)
	var r := Results.from_v1("raid", {"fort_id": fort}, b["seed"])
	r["raised"] = raised
	r["warden_beaten"] = beaten
	r["retreated"] = not beaten
	return s.apply_result("raid", r)


func _ev_ok(ev: Dictionary) -> bool:
	var errs: Array = []
	ApiSchema.check(ev, {"t": TYPE_FLOAT, "type": TYPE_STRING}, "event", errs)
	ApiSchema.check(ev, ApiSchema.EVENTS.get(ev.get("type", ""), {}), "event", errs)
	return errs.is_empty()


## Ticks substeps until an event of `type` (at most `max_s`); returns it, or {}.
func _tick_until(s: GameState, type: String, max_s: float) -> Dictionary:
	var end := s.t + max_s
	while s.t < end:
		s.tick(s.substep_s())
		for ev in s.drain_events():
			if ev["type"] == type:
				return ev
	return {}


func _lane(s: GameState, id: String) -> Dictionary:
	for l in s.view_lanes()["lanes"]:
		if l["id"] == id:
			return l
	return {}


# ------------------------------------------------------------------- the tithe ----
## MECHANICS §3.4 through GameState: no wave before the first flip; the flip starts the clock; the
## events carry t and match the contract; view_vei, view_fort and the living lane follow.
func _tithe() -> void:
	var tc: Dictionary = TestUtil.configs()["realm"]["tithe"]
	var s := _mk()
	s.tick(900.0)
	var evs := s.drain_events().filter(func(e): return str(e["type"]).begins_with("tithe"))
	t.ok(evs.is_empty() and not s.realm.tithe["started"] and s.view_vei()["tithe"]["target"] == "", "no tithe in 15 min without a flip")
	t.ok(_raid(s, "old-sluice", [], true)["ok"], "flip Old Sluice")
	var t_flip := s.t
	t.ok(s.realm.tithe["started"], "the first flip starts the tithe cycle")
	t.near(s.realm.tithe["next_s"], float(tc["period_s"]) * (1.0 - float(tc["backlog_scale"]) * s.realm.odds()), 1e-9,
		"the first wave is one period (at the odds now) after the flip")
	s.realm.hold("old-sluice", 1e5)  # keep it held through the wave (the hold timer is 375 s)
	s.drain_events()
	var w := _tick_until(s, "tithe_warning", 600.0)
	t.ok(_ev_ok(w) and w["fort_id"] == "old-sluice" and w["t"] == s.t, "tithe_warning on the held fort, stamped and in the contract: %s" % str(w))
	t.ok(w["t"] - t_flip > float(tc["period_s"]) * 0.5 - float(tc["warning_s"]), "not before its time")
	var vv: Dictionary = s.view_vei()["tithe"]
	var ft: Dictionary = s.view_fort("old-sluice")["tithe"]
	t.ok(vv["target"] == "old-sluice" and vv["warning"] and not vv["wave_active"] and absf(vv["eta_s"] - w["eta_s"]) < 1e-9,
		"view_vei.tithe during the warning: %s" % str(vv))
	t.ok(ft == {"targeted": true, "eta_s": vv["eta_s"], "wave_active": false}, "view_fort.tithe on the target: %s" % str(ft))
	t.ok(s.view_fort("ashgate")["tithe"] == {"targeted": false, "eta_s": -1.0, "wave_active": false}, "and not elsewhere")
	var wv := _tick_until(s, "tithe_wave", 200.0)
	t.ok(_ev_ok(wv) and wv["fort_id"] == "old-sluice" and wv["wave_id"] == w["wave_id"], "tithe_wave follows on the warned fort: %s" % str(wv))
	t.near(wv["t"] - w["t"], w["eta_s"], s.substep_s(), "eta_s after its warning")
	t.ok(wv["relish_here"] and absf(wv["surge"] - float(tc["surge_mult"]) * 8.0 * 0.5) < 1e-9, "Relish stands there: the surge is halved")
	vv = s.view_vei()["tithe"]
	t.ok(vv["wave_active"] and vv["target"] == "old-sluice" and vv["eta_s"] == 0.0 and not vv["warning"]
		and absf(vv["wave_s_left"] - (float(tc["surge_s"]) - s.substep_s())) < 1e-9, "view_vei.tithe during the wave: %s" % str(vv))
	t.ok(s.view_fort("old-sluice")["tithe"] == {"targeted": true, "eta_s": 0.0, "wave_active": true}, "view_fort.tithe during the wave")
	var lane := _lane(s, "living:vei:old-sluice")
	t.ok(lane["why"] == "tithe wave" and absf(lane["bias"] - float(tc["surge_mult"]) * 0.5) < 1e-9 and lane["rate"] > 0.0,
		"the living lane: surge rate, bias surge_mult × counters, why 'tithe wave': %s" % str(lane))
	t.ok(absf(s.view_fort("old-sluice")["ship_in"] - lane["rate"]) < 1e-12, "ship_in carries the surge")
	var f := _fort(s, "old-sluice")
	var end := s.t + float(tc["surge_s"])
	var got: Array = []
	while s.t < end:
		s.tick(s.substep_s())
		got.append_array(s.drain_events().filter(func(e): return e["type"] == "fort_retaken"))
	var lost: bool = not RealmSim.is_held(f)
	t.ok(got.size() == (1 if lost else 0) and (not lost or (_ev_ok(got[0]) and got[0]["cause"] == "tithe_wave" and got[0]["t"] <= s.t)),
		"the wave's end: retaken (with the event) iff it overwhelmed the garrison (lost: %s, %s)" % [lost, str(got)])
	t.ok(s.realm.tithe["wave"].is_empty() and not s.view_vei()["tithe"]["wave_active"], "the wave is over")
	t.ok(lost and f["clears_since_retaken"] == 0, "this garrison (a fresh flip) is overwhelmed; the yield refreshes")


# ------------------------------------------------------------------------------ q ----
## MECHANICS §2.2: the formula and its clamps; the circle EMA is mass-weighted, in apply order, moved
## only by results (12 h of ticking leave it alone) and raises q with good circles (vision M7).
func _q() -> void:
	var qc: Dictionary = TestUtil.configs()["realm"]["q"]
	var s := _mk()
	t.near(s.digest_q(), float(qc["q0"]), 1e-12, "a new game: q = q0, the EMA at 50")
	t.ok(s._readout["q_raise_ema"] == 50.0, "ema_score starts at 50")
	s.cmd_debug_set_state({"forge_level": 3})
	t.near(s.digest_q(), 1.2 + 0.1 * 3.0, 1e-12, "q_forge per forge level")
	s._readout["q_raise_ema"] = 100.0
	t.near(s.digest_q(), 1.5 + float(qc["q_raise_max"]), 1e-12, "q_raise_max at a perfect EMA")
	s._readout["q_raise_ema"] = 75.0
	t.near(s.digest_q(), 1.5 + float(qc["q_raise_max"]) * 0.5, 1e-12, "q_raise · (ema − 50) / 50")
	s._readout["q_raise_ema"] = 20.0
	t.near(s.digest_q(), 1.5, 1e-12, "no q_raise below 50")
	s.cmd_debug_set_state({"forge_level": 60})
	t.ok(s.digest_q() == float(qc["q_max"]), "clamped at q_max")
	var low := _mk()
	low._cfgs["realm"]["q"]["q0"] = 0.2
	t.ok(low.digest_q() == 1.0, "clamped at 1")
	s.cmd_debug_set_state({"forge_level": 2})
	s._readout["q_raise_ema"] = 90.0
	var q := s.digest_q()
	s.tick(s.substep_s())
	t.ok(s._realm_inputs["digest_q"] == q and s.realm.digest_q == q, "RealmSim steps at q")
	t.ok(s.view_vei()["digest_q"] == q and s.view_realm()["digest_q"] == q and s.quality() == q, "view_vei, view_realm and quality() show it")
	t.ok(s.raid_seed("ashgate")["quality"] == q and s.boss_seed()["quality"] == q and s.town_snapshot() == {},
		"the legacy seeds carry it (no elite term); the legacy town snapshot is {}")
	t.ok(s.town_sim.forge["level"] == 2, "forge_level is TownSim's")
	s.legacy_teleport_relish("ashgate")
	t.ok(s.cmd_begin_dungeon("ashgate")["seed"]["digest_q"] == q, "the dungeon seed carries it")
	s.cmd_abort_dungeon()
	s.legacy_teleport_relish("vei")
	t.ok(s.cmd_begin_boss()["seed"]["digest_q"] == q, "the boss seed carries it")
	s.cmd_abort_dungeon()

	# the EMA: mass-weighted, in apply order
	var big := _mk()
	var small := _mk()
	t.ok(_raid(big, "ashgate", [{"score": 90, "count": 10, "mass": 1000.0}])["ok"] and _raid(small, "ashgate", [{"score": 90, "count": 1, "mass": 10.0}])["ok"],
		"two raids of score-90 circles apply")
	var a_big := 1.0 - pow(0.5, 1000.0 / float(qc["raise_half_mass"]))
	t.near(big._readout["q_raise_ema"], 50.0 + a_big * 40.0, 1e-9, "α = 1 − 0.5^(mass / raise_half_mass): 1000 mass moves it to 88.75")
	t.near(small._readout["q_raise_ema"], 50.0 + (1.0 - pow(0.5, 10.0 / 200.0)) * 40.0, 1e-9, "10 mass moves it little")
	t.ok(big._readout["q_raise_ema"] - 50.0 > 20.0 * (small._readout["q_raise_ema"] - 50.0), "a 1000-mass raid moves it far more than a 10-mass one")
	var ab := _mk()
	var ba := _mk()
	_raid(ab, "ashgate", [{"score": 90, "count": 1, "mass": 200.0}, {"score": 10, "count": 1, "mass": 200.0}])
	_raid(ba, "ashgate", [{"score": 10, "count": 1, "mass": 200.0}, {"score": 90, "count": 1, "mass": 200.0}])
	t.near(ab._readout["q_raise_ema"], 40.0, 1e-9, "buckets apply in order (50 → 70 → 40)")
	t.near(ba._readout["q_raise_ema"], 60.0, 1e-9, "the other order ends elsewhere (50 → 30 → 60)")

	# the EMA is fed the clamped masses (STATE-API §8.3 step 3): each scaled by R'/R
	var cl := _mk()
	t.ok(_raid(cl, "ashgate", [{"score": 90, "count": 10, "mass": 1000.0}], false, 10.0)["ok"], "a result reporting 1000 mass at a fort with 10 dead applies")
	t.near(cl._readout["q_raise_ema"], 50.0 + (1.0 - pow(0.5, 10.0 / float(qc["raise_half_mass"]))) * 40.0, 1e-9, "the EMA moves as if 10 mass were raised, not 1000")
	var cl2 := _mk()
	_raid(cl2, "ashgate", [{"score": 90, "count": 1, "mass": 300.0}, {"score": 10, "count": 1, "mass": 100.0}], false, 200.0)
	var ema2 := 50.0  # R = 400, R' = 200: the masses become 150 and 50
	ema2 += (1.0 - pow(0.5, 150.0 / float(qc["raise_half_mass"]))) * (90.0 - ema2)
	ema2 += (1.0 - pow(0.5, 50.0 / float(qc["raise_half_mass"]))) * (10.0 - ema2)
	t.near(cl2._readout["q_raise_ema"], ema2, 1e-9, "every bucket's mass is scaled by R'/R (200/400), in apply order")
	var cl3 := _mk()
	_raid(cl3, "ashgate", [{"score": 90, "count": 1, "mass": 50.0}], false, 0.0)
	t.ok(cl3._readout["q_raise_ema"] == 50.0, "a fort with no dead raises nothing: the EMA does not move")

	# it never decays: 12 h of ticking with no raids (a coarse 10 s substep in this copy)
	var idle := _mk(10.0)
	_raid(idle, "ashgate", [{"score": 95, "count": 4, "mass": 300.0}], true)
	idle.legacy_teleport_relish("covington")
	var ema0: float = idle._readout["q_raise_ema"]
	var q0 := idle.digest_q()
	idle.tick(12.0 * 3600.0)
	t.ok(idle.t >= 12.0 * 3600.0 and idle._readout["q_raise_ema"] == ema0 and idle.digest_q() == q0,
		"12 h with no raids: ema_score %.3f and q %.3f unchanged (IDLE I2)" % [ema0, q0])
	t.ok(is_finite(idle._readout["diff_ema"]) and idle.view_vei()["drain_s"] >= -1.0, "and the readout stays finite")

	# q rises with good circles (vision M7)
	var g := _mk()
	var prev := g.digest_q()
	var rising := true
	for i in 5:
		_raid(g, "ashgate", [{"score": 95, "count": 3, "mass": 100.0}])
		rising = rising and g.digest_q() > prev
		prev = g.digest_q()
	t.ok(rising and prev > 1.6, "five raids of score-95 circles raise q every time (%.3f)" % prev)


# ------------------------------------------------------------------- the readout ----
## MECHANICS §3.5: the sign moves only on a sustained differential; drain_s = backlog / −EMA, never
## INF; odds. One substep moves the EMA by α·diff (α = 1 − e^(−0.5/120) ≈ 0.00416), so one substep
## flips the sign only past |diff| > sign_eps / α ≈ 12 mass/s; the cases stay at 5.
func _readout() -> void:
	var rc: Dictionary = TestUtil.configs()["realm"]["readout"]
	var s := _mk()
	var dt := s.substep_s()
	var a := 1.0 - exp(-dt / float(rc["ema_s"]))
	t.ok(s.view_vei()["sign"] == 0 and s.view_vei()["drain_s"] == -1.0 and s.view_vei()["diff_ema"] == 0.0, "a new game holds")
	s._update_readout(dt, 5.0, 0.0)
	t.near(s.view_vei()["diff_ema"], 5.0 * a, 1e-12, "the EMA moves α = 1 − e^(−dt/ema_s) of the way")
	t.ok(s.view_vei()["diff"] == 5.0 and s.view_vei()["sign"] == 0 and s.view_hud()["sign"] == 0, "one substep of +5 mass/s does not flip the sign")
	for i in 119:
		s._update_readout(dt, 5.0, 0.0)
	t.ok(s.view_vei()["sign"] == 1 and s.view_hud()["sign"] == 1, "sustained for 60 s it does (EMA %.3f)" % s.view_vei()["diff_ema"])
	t.ok(s.view_vei()["drain_s"] == -1.0, "no drain time while the backlog grows")
	s._update_readout(dt, 0.0, 5.0)
	t.ok(s.view_vei()["sign"] == 1 and s.view_vei()["diff"] == -5.0, "one substep the other way does not flip it back")
	for i in 600:
		s._update_readout(dt, 0.0, 5.0)
	var ema: float = s.view_vei()["diff_ema"]
	t.ok(s.view_vei()["sign"] == -1, "sustained draining flips it to ▼ (EMA %.3f)" % ema)
	s.realm.vei["undead_queue"] = 1000.0
	t.near(s.view_vei()["drain_s"], 1000.0 / -ema, 1e-9, "drain_s = backlog / −EMA")
	t.ok(s.view_hud()["drain_s"] == s.view_vei()["drain_s"], "view_hud agrees")
	var k := float(s._cfg()["K"])
	t.near(s.view_vei()["odds"], 1000.0 / (1000.0 + k), 1e-12, "odds = backlog / (backlog + K)")
	s._readout["diff_ema"] = -5e-324
	t.ok(s.view_vei()["drain_s"] == -1.0 and is_finite(s.view_vei()["drain_s"]), "a vanishing EMA gives -1.0, never INF")
	s.realm.vei["undead_queue"] = 0.0
	s._readout["diff_ema"] = -2.0
	t.ok(s.view_vei()["drain_s"] == 0.0, "an empty backlog drains in 0 s")
	s._readout["diff_ema"] = float(rc["sign_eps"]) * 0.5
	t.ok(s.view_vei()["sign"] == 0, "inside ±sign_eps it holds")
	# live: diff = what entered the undead queue less what she took, each substep
	var g := _mk()
	g.tick(30.0)
	var e0: float = g._readout["diff_ema"]
	g.tick(dt)
	var diff: float = g.realm.vei["r_in_undead"] - g.realm.r_digested_undead
	t.near(g.view_vei()["diff"], diff, 1e-12, "diff = inflow − undead digested, last substep")
	t.near(g.view_vei()["diff_ema"], e0 + a * (diff - e0), 1e-12, "the EMA steps once per substep")
	var d := g.to_dict()
	t.ok(d["readout"]["diff_ema"] == SaveIO.canon(g._readout["diff_ema"]) and d["readout"]["q_raise_ema"] == 50.0, "the readout block saves diff_ema and ema_score")


# -------------------------------------------------------------------------- lanes ----
## STATE-API §5.3: each kind in its situation; `why` set by its cause and gone 10 s later; zero-rate
## lanes only while a callout is live.
func _lanes() -> void:
	var s := _mk()
	s.tick(30.0)
	var lanes: Array = s.view_lanes()["lanes"]
	var kinds := {}
	var shape_ok := true
	for l in lanes:
		kinds[l["kind"]] = true
		shape_ok = shape_ok and l["id"] == "%s:%s:%s" % [l["kind"], l["from"], l["to"]] and GameState.LANE_KINDS.has(l["kind"])
		shape_ok = shape_ok and (l["rate"] > 0.0 or l["why"] != "") and l["why"] == ""
	t.ok(shape_ok, "ids are kind:from:to; every lane carries mass; no callouts yet")
	t.ok(kinds.has("war") and kinds.has("flood") and kinds.has("dead") and kinds.has("living") and kinds.has("work"),
		"after 30 s: war, flood, work, dead and living lanes: %s" % str(kinds.keys()))
	t.ok(_lane(s, "work:covington:covington")["rate"] == s._split["work"], "the work lane carries the valve's WORK")
	var ash := _fort(s, "ashgate")
	t.ok(_lane(s, "flood:ashgate:vei")["rate"] == ash["r_drain"] and _lane(s, "dead:ashgate:vei")["rate"] == ash["r_dead_out"]
		and _lane(s, "living:vei:ashgate").get("rate", 0.0) == ash["r_shipped"], "flood (drain), dead and living lanes carry the fort's rates")
	t.ok(_lane(s, "flood:covington:vei")["rate"] == s.realm.r_flood, "FLOOD from Covington")
	# the valve
	s.cmd_set_valve(1, 1, 1)  # a command: the callout starts at its t
	t.ok(_lane(s, "war:covington:ashgate")["why"] == "valve" and _lane(s, "flood:covington:vei")["why"] == "valve", "a valve change: 'valve' on war and flood")
	s.tick(_WHY_S() - s.substep_s())
	t.ok(_lane(s, "war:covington:ashgate")["why"] == "valve", "still there just before 10 s")
	s.tick(s.substep_s())
	t.ok(_lane(s, "war:covington:ashgate")["why"] == "" and not s._why.has("war:covington:ashgate"), "gone after 10 s (and pruned)")
	var rv := s.rev
	s.cmd_set_valve(1, 1, 1)
	t.ok(_lane(s, "war:covington:ashgate")["why"] == "" and s.rev == rv + 1, "the same target again is no cause")
	# Relish here, Relish left
	s.cmd_debug_set_state({"forts": {"greywall": {"dead": 30.0}}})
	s.legacy_teleport_relish("greywall")
	s.tick(s.substep_s())
	var war := _lane(s, "war:covington:greywall")
	t.ok(war["why"] == "Relish here" and war["bias"] == 3.0, "her arrival: 'Relish here' on the war lane, bias tide_bias")
	var red := _lane(s, "redirect:greywall:greywall")
	t.ok(red["why"] == "Relish here" and red["rate"] > 0.0 and red["rate"] == _fort(s, "greywall")["r_raised"], "the redirect lane: her raise, 'Relish here'")
	var dl := _lane(s, "dead:greywall:vei")
	t.ok(dl["why"] == "Relish here" and dl["rate"] == 0.0, "the dead lane drops to 0 but stays while its callout lives")
	s.tick(_WHY_S())
	t.ok(_lane(s, "dead:greywall:vei").is_empty() and _lane(s, "war:covington:greywall")["why"] == "", "10 s on: the empty dead lane is omitted, callouts gone")
	s.legacy_teleport_relish("covington")
	s.tick(s.substep_s())
	t.ok(_lane(s, "war:covington:greywall")["why"] == "Relish left" and _lane(s, "war:covington:greywall")["bias"] == 1.0
		and _lane(s, "redirect:greywall:greywall")["why"] == "Relish left", "she leaves: 'Relish left', bias back to 1")
	# held and staging, then retaken
	_raid(s, "ashgate", [], true)
	s.tick(s.substep_s())
	t.ok(_lane(s, "living:vei:ashgate")["why"] == "held" and _lane(s, "living:vei:ashgate")["rate"] == 0.0, "a flip: 'held' on the living lane (no shipping)")
	t.ok(_lane(s, "war:covington:ashgate")["why"] == "staging" and _lane(s, "war:covington:ashgate")["rate"] > 0.0
		and _lane(s, "war:covington:ashgate")["rate"] == _fort(s, "ashgate")["r_staged"], "and 'staging' on its war lane")
	_fort(s, "ashgate")["held_s"] = 0.25
	s.tick(s.substep_s())
	t.ok(_lane(s, "living:vei:ashgate")["why"] == "retaken" and _lane(s, "war:covington:ashgate")["why"] == "retaken", "expiry: 'retaken'")
	# a simulacrum
	s.cmd_debug_set_state({"forts": {"vespers": {"dead": 40.0}}})
	s.realm.simulacra.append({"fort_id": "vespers", "charges": 30.0, "rate": 2.0})
	s.tick(s.substep_s())
	red = _lane(s, "redirect:vespers:vespers")
	t.ok(red["why"] == "simulacrum" and red["rate"] > 0.0 and _lane(s, "dead:vespers:vei")["why"] == "simulacrum", "a simulacrum: 'simulacrum' on its redirect and dead lanes")
	# WAR with no target falls through to Vei: its own war lane
	var e := _mk()
	var none := {}
	for f in e.realm.forts:
		none[f["id"]] = {"living": 0.0, "dead": 1e6}  # no living and no room: Vei can ship nowhere
	e.cmd_debug_set_state({"forts": none})
	e.tick(e.substep_s())
	var fall := _lane(e, "war:covington:vei")
	t.ok(e.realm.war_route == "vei" and fall["rate"] == e.realm.r_war_to_vei and fall["rate"] > 0.0, "no target: a war lane covington → vei")


func _WHY_S() -> float:
	return GameState._WHY_S
