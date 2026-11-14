extends RefCounted
## STATE-API v6 additions (economy E2b-2 T3.1 onward; later E2b-2 tasks add to v6): the held forts'
## contest (fort_retaken's cause "broken", big_undead_returned, the save's hold keys) and their
## readouts (garrison, garrison_rate, fall_s, margin, margin_cause, grace_s_left, war_supports and
## view_projection; api-requests #7, #13). Headless, no autoloads.

var t: TestUtil


func _mk(seed_val := 1) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(seed_val)
	s.debug_enabled = true
	return s


func run() -> int:
	t = TestUtil.new()
	_version()
	_retake()
	_projection_now()
	_projection_pure()
	_by_hand()
	_supports_monotone()
	_chip_predicts()
	_grace_view()
	return t.failures


func _version() -> void:
	t.suite("api-v6")
	var s := _mk()
	t.ok(GameState.API_VERSION == 6 and s.to_dict()["api_version"] == 6, "API_VERSION is 6")
	for f in s.to_dict()["realm"]["forts"]:
		t.ok(f["held"] is bool and f["grace_s"] is float and f["zero_s"] is float and not f.has("held_s"),
			"%s: the save writes held, grace_s, zero_s (no held_s)" % f["id"])


## A contested Greywall with a siege big undead, no WAR (all FLOOD: no WORK, so no muster) and her
## living there: broken after break_s; fort_retaken {fort_id, cause: "broken"} then
## big_undead_returned {uid, fort_id}, both in the contract; the big undead is in the crypt.
func _retake() -> void:
	t.suite("api-v6-retake")
	var s := _mk()
	t.ok(s.cmd_debug_grant({"big_undead": 1})["ok"], "a big undead (setup)")
	var uid: String = s.view_big_undead()["big_undead"][0]["uid"]
	t.ok(s.cmd_place_big_undead(uid, "fort:greywall")["ok"], "placed at Greywall as siege")
	s.cmd_debug_set_state({"valve": {"work": 0.0, "war": 0.0, "flood": 1.0}, "forts": {"greywall": {"living": 60.0, "undead": 0.0}}})
	s.realm.hold("greywall", 0.0)
	s.drain_events()
	var got: Array = []
	for i in int(float(s._cfg()["hold"]["break_s"]) / s.substep_s()) + 2:
		s.tick(s.substep_s())
		got.append_array(s.drain_events().filter(func(e): return e["type"] in ["fort_retaken", "big_undead_returned"]))
	t.ok(got.size() == 2 and got[0]["type"] == "fort_retaken" and got[0]["cause"] == "broken" and got[0]["fort_id"] == "greywall"
		and got[1] == {"type": "big_undead_returned", "uid": uid, "fort_id": "greywall", "t": got[0]["t"]},
		"fort_retaken {greywall, broken}, then big_undead_returned {uid, fort_id} at its t: %s" % str(got))
	for e in got:
		var errs: Array = []
		ApiSchema.check(e, ApiSchema.EVENTS[e["type"]], e["type"], errs)
		t.ok(errs.is_empty(), "%s matches the contract%s" % [e["type"], "" if errs.is_empty() else ": " + str(errs)])
	t.ok(s.view_big_undead()["big_undead"][0]["place"] == "crypt" and s.view_fort("greywall")["siege"] == [] and not s.view_fort("greywall")["held"],
		"the big undead is back in the crypt; Greywall is no longer held")


# ------------------------------------------------------------- §2 readouts ----
func _fixture(name: String) -> GameState:
	var s := _mk()
	t.ok(s.cmd_debug_load_fixture(name)["ok"], "%s loads" % name)
	return s


## A fort's readout fields (view_fort's) next to a projection's margins entry.
static func _ro(vf: Dictionary) -> Dictionary:
	return {"margin": vf["margin"], "margin_cause": vf["margin_cause"], "fall_s": vf["fall_s"], "garrison_rate": vf["garrison_rate"]}


## The projection at the current valve is the live views, exactly: midgame_2flips (two forts in grace),
## pre_vei (none held), and pre_vei with Ashgate and Vespers held, contested, after a substep.
func _projection_now() -> void:
	t.suite("api-v6-projection")
	var cases := []
	var m := _fixture("midgame_2flips")
	m.tick(m.substep_s())
	cases.append(["midgame_2flips", m])
	var v := _fixture("pre_vei")
	v.tick(v.substep_s())
	cases.append(["pre_vei", v])
	var c := _fixture("pre_vei")
	c.realm.hold("ashgate", 0.0)
	c.realm.hold("vespers", 0.0)
	c.tick(c.substep_s())
	cases.append(["pre_vei, two contested", c])
	for e in cases:
		var s: GameState = e[1]
		var name: String = e[0]
		var p := s.view_projection(s.view_hud()["valve"])
		var hud := s.view_hud()
		t.ok(p["rev"] == s.rev and p["valve"] == hud["valve"], "%s: at today's rev and valve" % name)
		var sp: Dictionary = p["split"]
		t.ok(sp["work"] == hud["split"]["work"] and sp["war"] == hud["split"]["war"] and sp["flood"] == hud["split"]["flood"]
			and sp["war_overflow"] == hud["war_overflow"], "%s: split and war_overflow are view_hud's exactly: %s vs %s, %f" % [
			name, str(sp), str(hud["split"]), hud["war_overflow"]])
		t.ok(p["workers_steady"] == s.view_town()["workers"]["steady"], "%s: workers_steady is view_town's (%f)" % [name, p["workers_steady"]])
		t.ok(p["war_supports"] == hud["war_supports"], "%s: war_supports is view_hud's: %s" % [name, str(hud["war_supports"])])
		t.ok(p["backlog_diff"] == s.view_vei()["diff_ema"], "%s: backlog_diff is the sustained differential (%f)" % [name, p["backlog_diff"]])
		var want := {}
		for f in s.view_realm()["forts"]:
			if f["held"]:
				want[f["id"]] = _ro(f)
				t.ok(_ro(s.view_fort(f["id"])) == _ro(f), "%s, %s: view_fort and view_realm agree" % [name, f["id"]])
		t.ok(p["margins"] == want, "%s: every held fort's margin, cause, fall_s and garrison_rate are view_fort's exactly: %s" % [name, str(p["margins"])])
		t.ok(int(hud["war_supports"]["m"]) == want.size(), "%s: m is the held forts (%d)" % [name, want.size()])
	t.ok(cases[0][1].view_projection({})["valve"] == cases[0][1].view_hud()["valve"], "a valve with no keys is the current one")


## Purity: rev, every view and the save dump read the same after projections at other valves and at
## invalid ones; an invalid valve echoes the current one; each call is a fresh copy.
func _projection_pure() -> void:
	t.suite("api-v6-projection-pure")
	var s := _fixture("midgame_2flips")
	s.tick(s.substep_s())
	var rv := s.rev
	var views := {}
	for nm in ["view_hud", "view_realm", "view_town", "view_vei", "view_lanes", "view_rates", "view_relish"]:
		views[nm] = s.call(nm)
	var forts := {}
	for f in s.realm.forts:
		forts[f["id"]] = s.view_fort(f["id"])
	var dump := JSON.stringify(s.to_dict())
	var evs := s.drain_events().size()
	var cur: Dictionary = s.view_hud()["valve"]
	for v in [{"work": 0.0, "war": 1.0, "flood": 0.0}, {"work": 0.9, "war": 0.0, "flood": 0.1}, {"work": 3, "war": 1, "flood": 0}]:
		var p := s.view_projection(v)
		t.ok(absf(float(p["valve"]["work"]) + float(p["valve"]["war"]) + float(p["valve"]["flood"]) - 1.0) < 1e-12 and p["valve"] != cur,
			"%s is normalised as cmd_set_valve would: %s" % [str(v), str(p["valve"])])
	for bad in [{"work": -1.0, "war": 1.0, "flood": 0.0}, {"work": 0.0, "war": 0.0, "flood": 0.0}, {"work": INF, "war": 1.0, "flood": 0.0},
			{"work": "x", "war": 1.0, "flood": 0.0}, {"war": 1.0}]:
		var p := s.view_projection(bad)
		t.ok(p["valve"] == cur and p["margins"] == s.view_projection(cur)["margins"], "an invalid valve %s echoes the current one" % str(bad))
	var p := s.view_projection(cur)
	p["margins"]["ashgate"]["margin"] = "x"
	p["split"]["war"] = -1.0
	t.ok(s.view_projection(cur)["margins"]["ashgate"]["margin"] != "x" and s.view_projection(cur)["split"]["war"] >= 0.0, "a fresh deep copy each call")
	t.ok(s.rev == rv, "rev is unchanged")
	for nm in views:
		t.ok(s.call(nm) == views[nm], "%s is unchanged" % nm)
	var same := true
	for f in s.realm.forts:
		same = same and s.view_fort(f["id"]) == forts[f["id"]]
	t.ok(same, "every view_fort is unchanged")
	t.ok(JSON.stringify(s.to_dict()) == dump and s.drain_events().size() == 0 and evs >= 0, "the save dump is unchanged, no events")


## fall_s and garrison_rate by hand, from fort_step's terms: Ashgate contested with no WAR, every other
## fort full of corpses, odds 0, q 1.2. Her reship S = reship_share · S_vei · 80 / Σcap; the rate is
## 0 − min(r_drain · S / k_kill, k_destroy · (80 + τ · S) / q); fall_s = G / −rate + break_s.
func _by_hand() -> void:
	t.suite("api-v6-by-hand")
	var s := _mk()
	s.cmd_debug_set_state({"valve": {"work": 0.0, "war": 0.0, "flood": 1.0}})
	for f in s.realm.forts:
		f["living"] = 0.0
		f["undead"] = 0.0
		f["dead"] = 0.0 if f["id"] == "ashgate" else float(f["cap"])
	var ash := s.realm.fort_by_id("ashgate")
	ash["undead"] = 30.0
	s.realm.hold("ashgate", 0.0)
	var cfg: Dictionary = s._cfg()
	var sum_cap := 0.0
	for f in s.realm.forts:
		sum_cap += float(f["cap"])
	var sh := float(cfg["hold"]["reship_share"]) * float(cfg["S_vei"]) * 80.0 / sum_cap
	var hold_off := float(cfg["r_drain"]) * sh / float(cfg["k_kill"])
	var pile := float(cfg["k_destroy"]) * (80.0 + float(cfg["tithe"]["march_back_s"]) * sh) / s.digest_q()
	var rate := -minf(hold_off, pile)
	var vf := s.view_fort("ashgate")
	t.ok(s.realm.odds() == 0.0 and s.digest_q() == 1.2, "odds 0, q 1.2 (setup)")
	t.near(float(vf["garrison_rate"]), rate, 1e-12, "garrison_rate = −min(r_drain · S / k_kill = %.6f, k_destroy · (cap + τ · S) / q = %.6f)" % [hold_off, pile])
	t.near(float(vf["fall_s"]), 30.0 / -rate + float(cfg["hold"]["break_s"]), 1e-9, "fall_s = garrison / −rate + break_s (%.3f)" % float(vf["fall_s"]))
	t.ok(vf["margin"] == "will_fall" and vf["margin_cause"] == "fall" and vf["garrison"] == 30.0 and vf["grace_s_left"] == 0.0 and vf["held_s_left"] == 0.0,
		"will_fall (cause fall); garrison 30; no grace; held_s_left 0.0 (deprecated)")
	s.realm.hold("ashgate", 200.0)
	vf = s.view_fort("ashgate")
	t.near(float(vf["fall_s"]), 200.0 + 30.0 / -rate + float(cfg["hold"]["break_s"]), 1e-9, "in grace, fall_s adds the grace left")
	t.ok(vf["grace_s_left"] == 200.0 and vf["margin"] == "will_fall" and float(vf["garrison_rate"]) == rate,
		"and grace_s_left > 0 marks the post-grace margin and rate")
	var gr := s.view_fort("greywall")
	t.ok(gr["garrison"] == 0.0 and gr["garrison_rate"] == 0.0 and gr["fall_s"] == -1.0 and gr["margin"] == "" and gr["margin_cause"] == ""
		and gr["grace_s_left"] == 0.0, "a fort not held: garrison 0, rate 0, fall_s −1, margin and cause empty")
	t.ok(s.view_hud()["war_supports"] == {"n": 0, "m": 1}, "WAR supports 0 of 1")


## More WAR never supports fewer forts, nor lowers a garrison_rate: projections across the WAR share,
## from a new game with Ashgate and Vespers contested (a substep in, no muster yet), so N of M runs
## from 0 to 2.
func _supports_monotone() -> void:
	t.suite("api-v6-supports")
	var s := _mk()
	s.realm.hold("ashgate", 0.0)
	s.realm.hold("vespers", 0.0)
	s.tick(s.substep_s())
	var last := -1
	var rates := {}
	var mono := true
	var seen := {}
	for i in 21:
		var w := float(i) / 20.0
		var p := s.view_projection({"work": (1.0 - w) * 0.7, "war": w, "flood": (1.0 - w) * 0.3})
		var n := int(p["war_supports"]["n"])
		mono = mono and n >= last and int(p["war_supports"]["m"]) == 2
		last = n
		seen[n] = true
		for id in p["margins"]:
			var r := float(p["margins"][id]["garrison_rate"])
			mono = mono and r >= float(rates.get(id, -INF))
			rates[id] = r
	t.ok(mono and seen.has(0) and seen.has(1) and seen.has(2), "n and every garrison_rate never drop as the valve's WAR rises (0, 1 and 2 of 2 seen: %s)" % str(seen.keys()))


## A contested Ashgate with `war` mass/s of WAR and nothing else WAR can reach (every other fort full of
## corpses), its garrison at the level that WAR holds, Vei's pool full, odds 0; `grace` s of grace.
func _ash(war: float, grace := 0.0) -> RealmSim:
	var all := TestUtil.configs()
	var sim := RealmSim.new()
	sim.setup(all["world"], all["realm"])
	sim.vei["living_pool"] = 600.0
	sim.vei["dead_queue"] = 1e5
	for o in sim.forts:
		o["living"] = 0.0
		o["undead"] = 0.0
		o["dead"] = 0.0 if o["id"] == "ashgate" else float(o["cap"])
	sim.hold("ashgate", grace)
	sim.fort_by_id("ashgate")["undead"] = war / float(all["realm"]["r_drain"])
	sim.start_tithe()
	sim.tithe["next_s"] = 1e9  # no wave unless the case starts one
	return sim


func _inputs(war: float, relish: bool) -> Dictionary:
	var inp := {"war": war, "digest_q": 1.2}
	if relish:
		inp.merge({"tide_fort": "ashgate", "tide_bias": 3.0, "redirect_fort": "ashgate", "redirect_rate": 4.0})
	return inp


## [seconds to the retake, or -1] over `seconds` of 10 s steps.
func _run_ash(sim: RealmSim, seconds: float, inp: Dictionary) -> float:
	var el := 0.0
	while el < seconds - 1e-9:
		sim.step(10.0, inp)
		for e in sim.drain_timed():
			if e[1]["type"] == "fort_retaken":
				return el + float(e[0])
		el += 10.0
	return -1.0


## The chip predicts the sim (RealmSim at 10 s; the readout is view_fort's own, RealmSim.readout_of at
## the WAR the dispatch gives Ashgate): will_fall is retaken within safe_horizon_s with no wave; safe
## holds the horizon with no wave and then a full wave; thin holds the horizon with no wave and is broken
## by the full wave. fall_s is a straight line (G / −rate ignores U's decay and her living's climb), so
## its gap to the sim's retake is printed, not gated.
func _chip_predicts() -> void:
	t.suite("api-v6-chip")
	var horizon := float(TestUtil.configs()["realm"]["hold"]["safe_horizon_s"])
	for c in [["will_fall", 0.2, false], ["thin", 0.8, false], ["safe", 1.5, false], ["safe", 0.8, true]]:
		var sim := _ash(c[1])
		var inp := _inputs(c[1], c[2])
		sim.step(10.0, inp)  # the dispatch the readout reads
		var f := sim.fort_by_id("ashgate")
		var w: float = sim.war_at(c[1])[0][0]
		var ro := sim.readout_of(f, w, c[2], 4.0, c[2], 0.0, 1.2)
		var label := "Ashgate, WAR %.1f%s" % [c[1], ", Relish there" if c[2] else ""]
		t.ok(absf(w - c[1]) < 1e-12 and ro["margin"] == c[0] and ro["margin_cause"] == {"will_fall": "fall", "thin": "wave", "safe": ""}[c[0]],
			"%s: the chip reads %s (%s), garrison_rate %.4f, fall_s %.1f" % [label, ro["margin"], ro["margin_cause"], ro["garrison_rate"], ro["fall_s"]])
		var at := _run_ash(sim, horizon, inp)
		if c[0] == "will_fall":
			t.ok(at >= 0.0 and at <= horizon, "%s: retaken within the horizon with no wave (%.0f s; fall_s said %.0f s, %+.0f s)" % [
				label, at, ro["fall_s"], at - float(ro["fall_s"])])
			print("  [api-v6-chip] %s: fall_s %.1f s, the sim's retake %.1f s from the readout's step (gap %.1f s)" % [label, ro["fall_s"], at, at - float(ro["fall_s"])])
			continue
		t.ok(at < 0.0 and f["held"], "%s: no wave, it holds the %.0f s horizon" % [label, horizon])
		var surge_s := float(sim.t["tithe"]["surge_s"])
		sim.tithe["wave"] = {"wave_id": 1, "fort_id": "ashgate", "s_left": surge_s, "duration_s": surge_s,
			"mult": float(sim.t["tithe"]["surge_mult"]), "delivered": 0.0}
		var wat := _run_ash(sim, 1200.0, inp)
		t.ok((wat >= 0.0) == (c[0] == "thin"), "%s: then a full wave %s" % [label, "breaks it (%.0f s in)" % wat if wat >= 0.0 else "doesn't break it"])
	# another will_fall with a longer fall, for the gap: no WAR at all, a full garrison
	var sim := _ash(0.0)
	sim.fort_by_id("ashgate")["undead"] = 80.0
	sim.step(10.0, _inputs(0.0, false))
	var ro := sim.readout_of(sim.fort_by_id("ashgate"), 0.0, false, 4.0, false, 0.0, 1.2)
	var u_read := float(sim.fort_by_id("ashgate")["undead"])
	var at := _run_ash(sim, horizon, _inputs(0.0, false))
	t.ok(ro["margin"] == "will_fall" and at >= 0.0, "Ashgate, no WAR, %.1f undead: will_fall, retaken at %.0f s (fall_s %.0f s)" % [
		u_read, at, ro["fall_s"]])
	print("  [api-v6-chip] Ashgate, no WAR: fall_s %.1f s, the sim's retake %.1f s (gap %.1f s)" % [ro["fall_s"], at, at - float(ro["fall_s"])])


## A fort in grace shows grace_s_left > 0 and its post-grace readouts: midgame_2flips at load (374.5 s
## of grace on Ashgate and Old Sluice) reads the margin, cause and rate the same forts read with their
## grace ended, and fall_s adds the grace.
func _grace_view() -> void:
	t.suite("api-v6-grace")
	var a := _fixture("midgame_2flips")
	var b := _fixture("midgame_2flips")
	for id in ["ashgate", "old-sluice"]:
		b.realm.fort_by_id(id)["grace_s"] = 0.0
	for id in ["ashgate", "old-sluice"]:
		var va := a.view_fort(id)
		var vb := b.view_fort(id)
		t.ok(va["grace_s_left"] == 374.5 and vb["grace_s_left"] == 0.0 and va["margin"] == vb["margin"] and va["margin_cause"] == vb["margin_cause"]
			and va["garrison_rate"] == vb["garrison_rate"] and va["margin"] != "" and (va["fall_s"] < 0.0) == (vb["fall_s"] < 0.0)
			and (va["fall_s"] < 0.0 or absf(va["fall_s"] - vb["fall_s"] - 374.5) < 1e-9),
			"%s in grace (%.1f s left): the post-grace margin %s (%s), rate %.4f, fall_s %.1f" % [id, va["grace_s_left"], va["margin"],
			va["margin_cause"], va["garrison_rate"], va["fall_s"]])
