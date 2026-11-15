extends RefCounted
## STATE-API v6 additions (economy E2b-2 T3.1 onward; later E2b-2 tasks add to v6): the held forts'
## contest (fort_retaken's cause "broken", big_undead_returned, the save's hold keys) and their
## readouts (garrison, garrison_rate, fall_s, margin, margin_cause, grace_s_left, war_supports and
## view_projection; api-requests #7, #13); counter_garrison_cleared (#10); the live loot yield.
## Headless, no autoloads.

var t: TestUtil
var _dir := "user://test_saves_api_v6_%d" % OS.get_process_id()


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
	_chip_slow_fall()
	_grace_view()
	_counter_garrison()
	_yield()
	_store_caps()
	_construction_time()
	_projected()
	_projected_frame()
	_projection_frame_pure()
	_projection_reset()
	_projection_lot_bound()
	_warden_card()
	_mill_starved()
	_catchup_api()
	_catchup_chunked_api()
	_run_checkpoint_api()
	_relish_returned_api()
	_away_api()
	_death_ends()
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
## pre_vei (none held), and pre_vei with Ashgate and Vespers held, contested, after a substep. The margins
## (E2b-2 T3.4b): by default (a drag) they are the one-wave probe's, as before, each row margin_verified
## false; with `settled` they are view_fort's (the wave train's), margin_verified true.
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
		var one := {}
		var wars := s._fort_wars()
		for i in s.realm.forts.size():
			var f: Dictionary = s.view_realm()["forts"][i]
			if f["held"]:
				want[f["id"]] = _ro(f).merged({"margin_verified": true})
				one[f["id"]] = _ro(s._fort_readout(s.realm.forts[i], float(wars[i]))).merged({"margin_verified": false})
				t.ok(_ro(s.view_fort(f["id"])) == _ro(f), "%s, %s: view_fort and view_realm agree" % [name, f["id"]])
		var ps := s.view_projection(s.view_hud()["valve"], true)
		t.ok(ps["margins"] == want, "%s: settled, every held fort's margin, cause, fall_s and garrison_rate are view_fort's exactly: %s" % [name, str(ps["margins"])])
		t.ok(p["margins"] == one, "%s: by default, the one-wave probe's, as before: %s" % [name, str(p["margins"])])
		ps.erase("margins")
		var pd := p.duplicate(true)
		pd.erase("margins")
		t.ok(ps == pd, "%s: settled changes only the margins" % name)
		t.ok(int(hud["war_supports"]["m"]) == want.size(), "%s: m is the held forts (%d)" % [name, want.size()])
	t.ok(cases[0][1].view_projection({})["valve"] == cases[0][1].view_hud()["valve"], "a valve with no keys is the current one")


## Purity: rev, every view and the save dump read the same after projections at other valves and at
## invalid ones; an invalid valve echoes the current one; each call is a fresh copy.
func _projection_pure() -> void:
	t.suite("api-v6-projection-pure")
	var s := _fixture("midgame_2flips")
	s._cfgs["economy"]["town"]["projection_rows_per_call"] = 1000  # view_town's build benefit refreshes in one call
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
		var ps := s.view_projection(v, true)
		t.ok(ps["valve"] == p["valve"] and ps["margins"].size() == p["margins"].size()
			and ps["margins"].values().all(func(r): return r["margin_verified"]), "%s with settled: the train's margins (margin_verified)" % str(v))
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
## 0 − min(r_drain · S / k_kill, k_destroy · (80 + τ · S) / q); fall_s = min(G, A / r_drain) / −rate +
## break_s (E2b-2 T3.4b: the line starts at the level its support holds, here 0 with no WAR, so it is
## break_s; with 0.1 mass/s of WAR, 0.1 / r_drain / −rate + break_s).
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
	t.near(float(vf["fall_s"]), float(cfg["hold"]["break_s"]), 1e-9, "no WAR: fall_s = min(30, 0 / r_drain) / −rate + break_s = break_s (%.3f)" % float(vf["fall_s"]))
	var ro_w := s.realm.readout_of(ash, 0.1, false, 4.0, false, 0.0, s.digest_q())
	t.near(float(ro_w["fall_s"]), (0.1 / float(cfg["r_drain"])) / (minf(hold_off, pile) - 0.1) + float(cfg["hold"]["break_s"]), 1e-9,
		"0.1 mass/s: fall_s = (0.1 / r_drain) / −rate + break_s (%.3f)" % float(ro_w["fall_s"]))
	t.ok(vf["margin"] == "will_fall" and vf["margin_cause"] == "fall" and vf["garrison"] == 30.0 and vf["grace_s_left"] == 0.0 and vf["held_s_left"] == 0.0,
		"will_fall (cause fall); garrison 30; no grace; held_s_left 0.0 (deprecated)")
	s.realm.hold("ashgate", 200.0)
	vf = s.view_fort("ashgate")
	t.near(float(vf["fall_s"]), 200.0 + float(cfg["hold"]["break_s"]), 1e-9, "in grace, fall_s adds the grace left")
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


## The one-wave chip predicts the sim (RealmSim at 10 s; RealmSim.readout_of with no train verdict at the
## WAR the dispatch gives Ashgate: the margin view_projection gives during a drag; view_fort's is the wave
## train's since E2b-2 T3.4b, tested in test_wave_train): will_fall is retaken within safe_horizon_s with no
## wave; safe holds the horizon with no wave and then a full wave; thin holds the horizon with no wave and
## is broken by the full wave. fall_s is a straight line (G / −rate ignores U's decay and her living's
## climb), so its gap to the sim's retake is printed, not gated.
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


## The margin's order (E2b-2 T3.2 §0, T3.4b; MECHANICS §3.5): will_fall, then thin "wave" when the waves
## break it, then thin "fall" when it falls beyond the horizon, then (the train) thin "wave" when unsettled,
## then safe. A contested Ashgate at q 2 (her living's pile binds first) with 60 undead and its WAR just
## under the edge falls past the 8 h horizon.
## - The one-wave probe (view_projection's drag): a falling fort's probe starts at the garrison its support
##   holds, which is 0, so a full wave always breaks it and the slow fall reads "wave" (printed). With
##   hold.probe_s under hold.break_s it can't see a break, and the slow fall reads cause "fall".
## - The wave train (view_fort, the shipped settings): it starts from today's state, but that doesn't make
##   this fort's slow fall reachable: its 60 undead decay to the level its WAR holds within about a minute,
##   and its first wave pins it past break_s, so the train breaks it and it reads thin (wave), as the one-wave
##   probe did. A slow fall no wave in the train breaks is a shielded one: Old Sluice with its WAR just under
##   the edge (a rate of −G / (1.5 × the horizon), so fall_s is about 1.5 × the horizon) beside Ashgate at 3.0
##   mass/s, whose larger garrison draws every wave. The train never hits Old Sluice, the set settles, and
##   its slow fall reads thin (fall): slow attrition, not a wave, is the threat (the reviewer's case).
func _chip_slow_fall() -> void:
	t.suite("api-v6-chip-slow-fall")
	var horizon := float(TestUtil.configs()["realm"]["hold"]["safe_horizon_s"])
	# the wave train, shipped settings: T3.2's slow faller (the train breaks it)
	var lone := _slow_sim(TestUtil.configs())
	lone.hold("ashgate", 0.0)
	var fa := lone.fort_by_id("ashgate")
	fa["undead"] = 60.0
	var sa := lone.reship_rate(fa)
	var ea := minf(lone._r_drain * sa / lone._k_kill, lone._k_destroy * (80.0 + lone._march * sa) / 2.0)
	var wa := ea / (1.0 + 1.0 / (2.0 * horizon * lone._r_drain))
	var tra := lone.train_probe({"ashgate": [wa, false, 4.0, false, 0.0]}, 2.0)
	var roa := lone.readout_of(fa, wa, false, 4.0, false, 0.0, 2.0, tra["forts"]["ashgate"])
	t.ok(roa["garrison_rate"] < 0.0 and float(roa["fall_s"]) > horizon and bool(tra["forts"]["ashgate"]["broken"]) and [roa["margin"], roa["margin_cause"]] == ["thin", "wave"],
		"the train: T3.2's slow faller (q 2, 60 undead, fall_s %.0f s) is broken by its first waves (%s): thin (wave)" % [roa["fall_s"], str(tra["targets"])])
	# the wave train, shipped settings: a shielded slow faller reads thin (fall)
	var two := _slow_sim(TestUtil.configs())
	for id in ["ashgate", "old-sluice"]:
		two.hold(id, 0.0)
		two.fort_by_id(id)["dead"] = 0.0
	var fo := two.fort_by_id("old-sluice")
	var so := two.reship_rate(fo)
	var off_o := two._r_drain * so / two._k_kill
	var wo := off_o / (1.0 + 1.0 / (1.5 * horizon * two._r_drain))  # its level G = wo / r falls at G / 1.5 h
	fo["undead"] = wo / two._r_drain
	two.fort_by_id("ashgate")["undead"] = 3.0 / two._r_drain
	var tr2 := two.train_probe({"ashgate": [3.0, false, 4.0, false, 0.0], "old-sluice": [wo, false, 4.0, false, 0.0]}, 1.2)
	var ro2 := two.readout_of(fo, wo, false, 4.0, false, 0.0, 1.2, tr2["forts"]["old-sluice"])
	t.ok(ro2["garrison_rate"] < 0.0 and float(ro2["fall_s"]) > horizon and not (tr2["targets"] as Array).has("old-sluice")
		and bool(tr2["settled"]) and not bool(tr2["forts"]["old-sluice"]["broken"]),
		"the premise: Old Sluice's rate %.5f < 0, fall_s %.0f s past the horizon; every wave to Ashgate (%s); the set settles" % [
		ro2["garrison_rate"], ro2["fall_s"], str(tr2["targets"])])
	t.ok([ro2["margin"], ro2["margin_cause"]] == ["thin", "fall"], "the train: the shielded slow fall reads %s (%s)" % [ro2["margin"], ro2["margin_cause"]])
	# the one-wave probe (a drag), as T3.2 pinned it
	for short_probe in [false, true]:
		var all := TestUtil.configs().duplicate(true)
		if short_probe:
			all["realm"]["hold"]["probe_s"] = 0.5 * float(all["realm"]["hold"]["break_s"])
		var sim := _slow_sim(all)
		for o in sim.forts:
			o["dead"] = 0.0
		sim.hold("ashgate", 0.0)
		var f := sim.fort_by_id("ashgate")
		f["undead"] = 60.0
		var q := 2.0
		var s := sim.reship_rate(f)
		var hold_off := sim._r_drain * s / sim._k_kill
		var pile := sim._k_destroy * (float(f["cap"]) + sim._march * s) / q
		var edge := minf(hold_off, pile)
		var w := edge / (1.0 + 1.0 / (2.0 * horizon * sim._r_drain))  # a rate of −(w / r_drain) / 2h: fall_s about 2 × the horizon
		var ro := sim.readout_of(f, w, false, 4.0, false, 0.0, q)
		var breaks := sim._wave_breaks(f, w, s, w, false, 4.0, false, 0.0, q, hold_off)
		var label := "probe_s %.0f" % float(all["realm"]["hold"]["probe_s"])
		t.ok(ro["garrison_rate"] < 0.0 and float(ro["fall_s"]) > horizon and breaks == (not short_probe),
			"%s: the premise: rate %.5f < 0, fall_s %.0f s past the %.0f s horizon, one full wave %s" % [
			label, ro["garrison_rate"], ro["fall_s"], horizon, "breaks it" if breaks else "doesn't break it"])
		var want := ["thin", "fall"] if short_probe else ["thin", "wave"]
		t.ok([ro["margin"], ro["margin_cause"]] == want, "%s: the slow fall reads %s (%s)" % [label, ro["margin"], ro["margin_cause"]])
		if not short_probe:
			print("  [api-v6-chip-slow-fall] shipped probe: a falling fort's probe starts at a 0 garrison and breaks, so a slow fall reads thin (wave)")


## A RealmSim for the slow-fall cases: her pool full, no living or undead anywhere, every fort full of
## corpses (so WAR reaches only the held forts), her clock started (the first wave one period away).
func _slow_sim(all: Dictionary) -> RealmSim:
	var sim := RealmSim.new()
	sim.setup(all["world"], all["realm"])
	sim.vei["living_pool"] = 600.0
	for o in sim.forts:
		o["living"] = 0.0
		o["undead"] = 0.0
		o["dead"] = float(o["cap"])
	sim.start_tithe()
	return sim


## A fort in grace shows grace_s_left > 0 and its post-grace readouts: midgame_2flips at load (374.5 s
## of grace on Ashgate and Old Sluice) reads the rate the same forts read with their grace ended, and
## fall_s adds the grace. The margin (E2b-2 T3.4b) is the wave train's run through the grace, which no
## wave reaches (test_wave_train's grace case): what the fort faces once contested, from the garrison the
## grace leaves it. It is no longer the same word the forts read with their grace zeroed now, which face
## a wave at once with today's garrison: a different train, not the same fort later.
func _grace_view() -> void:
	t.suite("api-v6-grace")
	var a := _fixture("midgame_2flips")
	var b := _fixture("midgame_2flips")
	for id in ["ashgate", "old-sluice"]:
		b.realm.fort_by_id(id)["grace_s"] = 0.0
	var tr := a._train_live()
	for i in [0, 1]:
		var id: String = a.realm.forts[i]["id"]
		var va := a.view_fort(id)
		var vb := b.view_fort(id)
		var want := a.realm.readout_of(a.realm.forts[i], float(a._fort_wars()[i]), false, a._raise_rate, false, 0.0, a.digest_q(), tr["forts"][id])
		t.ok(va["grace_s_left"] == 374.5 and vb["grace_s_left"] == 0.0 and va["margin"] == want["margin"] and va["margin_cause"] == want["margin_cause"]
			and va["garrison_rate"] == vb["garrison_rate"] and va["margin"] != "" and (va["fall_s"] < 0.0) == (vb["fall_s"] < 0.0)
			and (va["fall_s"] < 0.0 or absf(va["fall_s"] - vb["fall_s"] - 374.5) < 1e-9),
			"%s in grace (%.1f s left): the train's post-grace margin %s (%s), rate %.4f, fall_s %.1f (grace zeroed: %s)" % [id, va["grace_s_left"],
			va["margin"], va["margin_cause"], va["garrison_rate"], va["fall_s"], vb["margin"]])
	t.ok(bool(tr["samples"][0][1]), "midgame's first wave starts in grace and threatens neither (targets %s)" % str(tr["targets"]))


# --------------------------------------------- §3 counter_garrison_cleared (#10) ----
## A raid result for the open run's seed: a retreat that kills `killed` living; `over` replaces keys.
func _raid_res(sd: Dictionary, killed: float, over := {}) -> Dictionary:
	var r := {
		"v": 2, "run_id": sd["run_id"], "seed_rev": sd["seed_rev"], "fort_id": sd["fort"]["id"],
		"warden_beaten": false, "retreated": true, "relish_died": false, "revived_in_place": 0,
		"killed_living_mass": killed, "raised": [], "chaff_mass": 0.0, "garrison_mass": sd["garrison_in_mass"],
		"party_lost": [], "loot": {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0},
	}
	r.merge(over, true)
	return r


## A new game with Greywall held and contested, `living` of her counter-garrison there, Relish at it.
func _held_raid(living: float, held := true) -> GameState:
	var s := _mk()
	if held:
		s.realm.hold("greywall", 0.0)
	s.cmd_debug_set_state({"relish_at": "greywall", "forts": {"greywall": {"living": living, "undead": 20.0}}})
	return s


func _cleared(s: GameState) -> Array:
	return s.drain_events().filter(func(e): return e["type"] == "counter_garrison_cleared")


## apply_result("raid", …) raises counter_garrison_cleared {fort_id, killed_mass} when the run's fort
## was held when it began, the result is a retreat and its kills reach the seed's living less half of
## one of the dungeon's living units (raid_populate: enemy_count(living, cap) units of living / n);
## killed_mass is the writeback's clamped kill. An empty held fort's clear (living 0) raises it with
## 0. Not on a partial clear, a death, or a Vei fort's raid.
func _counter_garrison() -> void:
	t.suite("api-v6-counter-garrison")
	var s := _held_raid(52.0)
	var b := s.cmd_begin_dungeon("greywall")
	var sd: Dictionary = b["seed"]
	var rm: Dictionary = TestUtil.configs()["raid"]["mass"]  # how the dungeon turns living into units
	var n := clampi(int(round(52.0 / 90.0 * float(rm["enemies_per_cap"]))), int(rm["enemy_min"]), int(rm["enemy_max"]))
	var unit := 52.0 / float(n)
	t.ok(b["ok"] and sd["living"] == 52.0 and s.run["held"] == true and not sd.has("held"),
		"the run records the fort was held (the seed keeps its shape): %d units of %.3f" % [n, unit])
	t.near(s._clear_tolerance(sd), 0.5 * unit, 1e-12, "the tolerance is half a unit (%.4f)" % (0.5 * unit))
	s.drain_events()
	t.ok(s.apply_result("raid", _raid_res(sd, 52.0 - 0.49 * unit))["ok"], "a full clear reported to rounding applies")
	var evs := s.drain_events()
	var cg := evs.filter(func(e): return e["type"] == "counter_garrison_cleared")
	t.ok(cg.size() == 1 and cg[0] == {"type": "counter_garrison_cleared", "fort_id": "greywall", "killed_mass": 52.0 - 0.49 * unit, "t": s.t}
		and evs[0]["type"] == "loot_banked", "counter_garrison_cleared {fort_id, killed_mass} after loot_banked: %s" % str(cg))
	var errs: Array = ["none"]
	if not cg.is_empty():
		errs = []
		ApiSchema.check(cg[0], ApiSchema.EVENTS["counter_garrison_cleared"], "counter_garrison_cleared", errs)
	t.ok(errs.is_empty(), "in the contract%s" % ("" if errs.is_empty() else ": " + str(errs)))
	# partial: short by more than half a unit
	s = _held_raid(52.0)
	sd = s.cmd_begin_dungeon("greywall")["seed"]
	s.drain_events()
	s.apply_result("raid", _raid_res(sd, 52.0 - 0.51 * unit))
	t.ok(_cleared(s).is_empty(), "a partial clear (short by 0.51 of a unit) raises nothing")
	# a death
	s = _held_raid(52.0)
	sd = s.cmd_begin_dungeon("greywall")["seed"]
	s.drain_events()
	s.apply_result("raid", _raid_res(sd, 52.0, {"retreated": false, "relish_died": true}))
	t.ok(_cleared(s).is_empty(), "a death raises nothing, whatever it killed")
	# a Vei fort's raid
	s = _held_raid(52.0, false)
	sd = s.cmd_begin_dungeon("greywall")["seed"]
	s.drain_events()
	s.apply_result("raid", _raid_res(sd, 52.0))
	t.ok(_cleared(s).is_empty() and s.run.is_empty(), "a Vei fort's raid (not held) raises nothing")
	# an empty held fort (in grace after a flip: no living): its clear reports 0 and raises it with 0
	s = _held_raid(0.0)
	sd = s.cmd_begin_dungeon("greywall")["seed"]
	s.drain_events()
	s.apply_result("raid", _raid_res(sd, 0.0))
	cg = _cleared(s)
	t.ok(sd["living"] == 0.0 and cg.size() == 1 and cg[0]["killed_mass"] == 0.0, "an empty held fort's clear raises it with killed_mass 0: %s" % str(cg))
	# the clamp: her reship landed during the run; the kill is clamped to the living there now
	s = _held_raid(52.0)
	sd = s.cmd_begin_dungeon("greywall")["seed"]
	s.realm.fort_by_id("greywall")["living"] = 30.0  # the garrison killed some while the run went on
	s.drain_events()
	s.apply_result("raid", _raid_res(sd, 52.0))
	cg = _cleared(s)
	t.ok(cg.size() == 1 and cg[0]["killed_mass"] == 30.0 and s.realm.fort_by_id("greywall")["living"] == 0.0,
		"the writeback is the clamped delta: killed_mass is what the fort held now (30), its living 0: %s" % str(cg))
	s = _held_raid(52.0)
	sd = s.cmd_begin_dungeon("greywall")["seed"]
	s.realm.fort_by_id("greywall")["living"] = 60.0  # her reship landed during the run
	s.drain_events()
	s.apply_result("raid", _raid_res(sd, 52.0))
	cg = _cleared(s)
	t.ok(cg.size() == 1 and cg[0]["killed_mass"] == 52.0 and absf(float(s.realm.fort_by_id("greywall")["living"]) - 8.0) < 1e-9,
		"her reship during the run stays: 52 killed of 60, 8 left: %s" % str(cg))
	# the seed of a contested fort is what the dungeon expects: its living as the counter-garrison, its
	# undead as the garrison units, the warden as for any fort (the dungeon skips the warden room on a
	# held fort, reading view_fort.held)
	s = _held_raid(52.0)
	sd = s.cmd_begin_dungeon("greywall")["seed"]
	t.ok(Results.validate("raid_seed", sd) == [] and sd["living"] == 52.0 and sd["garrison_units"] == 2 and s.view_fort("greywall")["held"],
		"a contested fort's seed validates, with its living (52) and its garrison (2 units of 20 mass)")


# ------------------------------------------------- §4 the loot yield recovers ----
## view_fort.yield_mult (and the seed's) is live (MECHANICS §5.3): loot.reclear_decay^clears relaxing
## linearly back to 1 over loot.recover_s. One paying clear halves it, two back to back quarter it; it
## recovers linearly to exactly 1 at recover_s from any depth; a save keeps it; a retake resets it; a
## save from before v6 reads 1.
func _yield() -> void:
	t.suite("api-v6-yield")
	var loot: Dictionary = TestUtil.configs()["loot"]
	var decay := float(loot["reclear_decay"])
	var rec := float(loot["recover_s"])
	var s := _mk()
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	var b := s.cmd_begin_dungeon("old-sluice")
	t.ok(b["seed"]["fort"]["yield_mult"] == 1.0 and s.view_fort("old-sluice")["yield_mult"] == 1.0, "a fresh fort's yield is 1")
	t.ok(s.apply_result("raid", _raid_res(b["seed"], 0.0, {"warden_beaten": true, "retreated": false}))["ok"], "the flip (a clear that pays loot)")
	var f := s.realm.fort_by_id("old-sluice")
	t.ok(s.view_fort("old-sluice")["yield_mult"] == decay and f["yield_c"] == decay and f["yield_t"] == s.t, "one clear: yield_mult × reclear_decay = %.2f" % decay)
	# a counter-garrison clear right after: quartered (the run starts at the same moment)
	var b2 := s.cmd_begin_dungeon("old-sluice")
	t.ok(b2["seed"]["fort"]["yield_mult"] == decay, "the next raid's seed carries the live yield")
	s.apply_result("raid", _raid_res(b2["seed"], float(b2["seed"]["living"])))
	t.near(float(s.view_fort("old-sluice")["yield_mult"]), decay * decay, 1e-12, "two back to back: reclear_decay² = %.2f" % (decay * decay))
	var t0 := s.t
	var c0: float = f["yield_c"]
	# linear recovery: checked at quarter points by moving the clock (the yield is a function of time)
	for k in [0.25, 0.5, 0.75]:
		s.t = t0 + k * rec
		t.near(float(s.view_fort("old-sluice")["yield_mult"]), 1.0 - (1.0 - c0) * (1.0 - k), 1e-12, "at %.0f%% of recover_s: %.4f" % [k * 100.0, 1.0 - (1.0 - c0) * (1.0 - k)])
	s.t = t0 + rec
	t.ok(s.view_fort("old-sluice")["yield_mult"] == 1.0, "exactly 1 at recover_s")
	s.t = t0 + 2.0 * rec
	t.ok(s.view_fort("old-sluice")["yield_mult"] == 1.0, "and after")
	s.t = t0 + 0.5 * rec
	var mid := float(s.view_fort("old-sluice")["yield_mult"])
	# a save round trip keeps it
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var n := _mk(2)
	t.ok(n.from_dict(d)["ok"] and absf(float(n.view_fort("old-sluice")["yield_mult"]) - mid) < 1e-12, "a save keeps it (%.4f)" % mid)
	# a save from before v6 (no yield keys) reads 1
	for e in d["realm"]["forts"]:
		e.erase("yield_c")
		e.erase("yield_t")
	var o := _mk(2)
	t.ok(o.from_dict(d)["ok"] and o.view_fort("old-sluice")["yield_mult"] == 1.0, "an older save reads 1")
	# a retake resets it
	var r := _mk()
	r.cmd_debug_set_state({"valve": {"work": 0.0, "war": 0.0, "flood": 1.0}, "forts": {"greywall": {"living": 60.0, "undead": 0.0}}})
	var g := r.realm.fort_by_id("greywall")
	r.realm.hold("greywall", 0.0)
	g["yield_c"] = 0.25
	g["yield_t"] = r.t
	t.ok(float(r.view_fort("greywall")["yield_mult"]) < 1.0, "a held fort with a spent yield (setup)")
	for i in int(float(r._cfg()["hold"]["break_s"]) / r.substep_s()) + 2:
		r.tick(r.substep_s())
	t.ok(not g["held"] and r.view_fort("greywall")["yield_mult"] == 1.0, "a retake resets it to 1")


## The gold and bone caps (E2b-2 T3.2, IDLE §6; STATE-API §5.1, §5.9, §4.7): view_hud's gold and bone `cap`
## is live (it was −1.0) and equals view_town's gold_cap and bone_cap: the base plus the Market's and the
## Bone Mill's per-level share. A demolished Market drops it. ledger().stores is the tally, 0 at a new game.
func _store_caps() -> void:
	t.suite("api-v6-store-caps")
	var cfg := TestUtil.configs()
	var s := _mk()
	var per_g := float(cfg["buildings"]["market"]["effects"]["gold_cap"])
	var per_b := float(cfg["buildings"]["bone_mill"]["effects"]["bone_cap"])
	var base_g := float(cfg["economy"]["gold"]["cap"])
	var base_b := float(cfg["economy"]["bone"]["cap"])
	var caps := {}
	for e in s.view_hud()["rates"]:
		caps[e["id"]] = e["cap"]
	var vt := s.view_town()
	t.ok(caps["gold"] == base_g + per_g and vt["gold_cap"] == caps["gold"] and caps["bone"] == base_b and vt["bone_cap"] == caps["bone"],
		"a new game: gold cap %.0f (base + a level-1 Market), bone cap %.0f (base), in view_hud and view_town" % [caps["gold"], caps["bone"]])
	t.ok(s.ledger()["stores"] == {"gold": {"overflow": 0.0}, "bone": {"overflow": 0.0}}, "ledger().stores is 0 at a new game")
	s.town_sim.place_building("lot-05", "bone_mill", 2)
	t.ok(s.view_town()["bone_cap"] == base_b + 2.0 * per_b, "a level-2 Bone Mill adds two shares: %.0f" % s.view_town()["bone_cap"])
	t.ok(s.cmd_demolish("lot-04")["ok"] and s.view_town()["gold_cap"] == base_g, "the Market demolished: the gold cap is the base again")
	# pre_vei's mill earns bone (+0.107/s uncapped) while its store sits over the cap: it keeps the excess
	# and every bone milled overflows, so the store never grows
	var m := _fixture("pre_vei")
	t.ok(m.view_town()["bone"] > m.view_town()["bone_cap"], "pre_vei: its bone (%.1f) is over the cap (%.0f); it keeps the excess" % [m.view_town()["bone"], m.view_town()["bone_cap"]])
	var b0 := m.town_sim.bone
	var milled := 0.0
	var grew := false
	for i in 2400:
		var before := m.town_sim.bone
		m.tick(m.substep_s())
		milled += float(m.town_sim.rates["bone"].get("mill", 0.0)) * m.substep_s()
		grew = grew or m.town_sim.bone > before
	t.ok(milled > 1.0 and not grew and m.town_sim.bone <= b0 and absf(float(m.ledger()["stores"]["bone"]["overflow"]) - milled) < 1e-9 * maxf(1.0, milled),
		"over 20 min it mills %.2f bone, all of it overflow (%.2f), and the store never grows: %.1f ≤ %.1f" % [
		milled, m.ledger()["stores"]["bone"]["overflow"], m.town_sim.bone, b0])


## Construction time (E2b-2 T3.2, api-request #17; STATE-API §5.9, §5.10): view_town's work_left (build work
## still to do) and eta_s (work_left over the lot's build rate now; −1.0 with no builders) while
## constructing, 0.0 and −1.0 otherwise; upgrade_work on every building (the next level's work, 0.0 at
## max_level); the catalog's work (a new build's). The numbers TownSim's step 6 uses.
func _construction_time() -> void:
	t.suite("api-v6-construction")
	var cfg := TestUtil.configs()
	var rate := float(cfg["economy"]["job"]["build"]["rate"])
	var s := _mk()
	s.cmd_debug_grant({"gold": 500.0, "bone": 100.0})
	t.ok(s.cmd_build("house", "lot-05")["ok"], "a house is started (setup)")
	s.tick(s.substep_s())
	var b := _bld(s, "lot-05")
	var work := float(cfg["buildings"]["house"]["build_work"])
	var crew := float(s.town_sim._by_lot["lot-05"]["build"])
	t.ok(b["state"] == "constructing" and crew > 0.0 and absf(float(b["work_left"]) - work * (1.0 - float(b["progress"]))) < 1e-9,
		"work_left = build_work × level × (1 − progress) = %.3f" % b["work_left"])
	t.ok(absf(float(b["eta_s"]) - float(b["work_left"]) / (rate * crew)) < 1e-9,
		"eta_s = work_left / (job.build.rate × %.1f builders) = %.2f s" % [crew, b["eta_s"]])
	var t0 := s.t
	var eta := float(b["eta_s"])
	var left := float(b["work_left"])
	s.tick(s.substep_s())
	t.ok(absf(left - float(_bld(s, "lot-05")["work_left"]) - rate * crew * s.substep_s()) < 1e-9,
		"work_left falls by the step's work (rate × builders × dt)")
	var done := -1.0
	s.drain_events()
	for i in 400:
		for e in s.drain_events():
			if e["type"] == "building_done" and e["lot_id"] == "lot-05" and done < 0.0:
				done = float(e["t"])
		if done >= 0.0:
			break
		s.tick(s.substep_s())
	t.ok(done > t0 and absf((done - t0) - eta) <= s.substep_s() + 1e-9,
		"it finishes %.2f s after the view; eta_s said %.2f s (within a step)" % [done - t0, eta])
	b = _bld(s, "lot-05")
	t.ok(b["state"] != "constructing" and b["work_left"] == 0.0 and b["eta_s"] == -1.0 and b["upgrade_work"] == work * 2.0,
		"finished: work_left 0.0, eta_s −1.0, upgrade_work = build_work × 2")
	# no builders: eta_s −1.0
	t.ok(s.cmd_upgrade("lot-05")["ok"], "an upgrade (setup)")
	s.town_sim.workers = 0.0
	s.town_sim.restaff()
	b = _bld(s, "lot-05")
	t.ok(b["state"] == "constructing" and b["eta_s"] == -1.0 and b["work_left"] == work * 2.0 and b["upgrade_work"] == work * 2.0,
		"no builders: eta_s −1.0; work_left the level's whole work; upgrade_work the construction's own (level + 1)")
	# max level: upgrade_work 0.0; the catalog's work is a new build's
	s.town_sim.place_building("lot-06", "house", 3)
	t.ok(_bld(s, "lot-06")["upgrade_work"] == 0.0, "at max_level upgrade_work is 0.0")
	var all_ok := true
	for r in s.view_catalog()["buildings"]:
		all_ok = all_ok and r["work"] == float(cfg["buildings"][r["building_id"]]["build_work"])
	t.ok(all_ok, "every catalog row's work is its build_work × 1")


func _bld(s: GameState, lot_id: String) -> Dictionary:
	for b in s.view_town()["buildings"]:
		if b["lot_id"] == lot_id:
			return b
	return {}


## Build benefit (E2b-2 T3.2, api-request #9; STATE-API §5.10, §5.9): `projected` on every catalog row and
## `upgrade_projected` on every built lot ({} at max_level or while constructing), keyed by every RATE_IDS
## id. Correct: for a pit, a house, a market and a Bone Mill upgrade at midgame_2flips, the town ids, mint,
## work and flood equal the change in view_rates when it is really finished in a copy (place_building, the
## same allocation restaffing it) and one substep runs, within 1e-9; war, backlog and corpses read as §5.10
## defines them. Pure. A cached answer equals a fresh one, after time has moved too.
func _projected() -> void:
	t.suite("api-v6-projected")
	var js := JSON.stringify(_fixture("midgame_2flips").to_dict())
	var p := _load_js(js)
	var cat := p.view_catalog()
	var town := p.view_town()
	var ids_ok := true
	for r in cat["buildings"]:
		ids_ok = ids_ok and (r["projected"] as Dictionary).keys() == GameState.RATE_IDS
	for b in town["buildings"]:
		var up: Dictionary = b["upgrade_projected"]
		var top := int(TestUtil.configs()["buildings"][b["building_id"]]["max_level"])
		ids_ok = ids_ok and (up.keys() == GameState.RATE_IDS if (b["state"] != "constructing" and int(b["level"]) < top) else up.is_empty())
	t.ok(ids_ok, "every row's projected and every lot's upgrade_projected carries every RATE_IDS id ({} at max level or constructing)")
	var v: Dictionary = p.view_hud()["valve"]
	t.ok(v == p.view_hud()["valve_target"], "the valve is at its target (no slew pending)")
	for c in [["raising_pit", "lot-08", false], ["house", "lot-08", false], ["market", "lot-13", false], ["bone_mill", "lot-07", true]]:
		var proj: Dictionary = {}
		if c[2]:
			for b in town["buildings"]:
				if b["lot_id"] == c[1]:
					proj = b["upgrade_projected"]
		else:
			for r in cat["buildings"]:
				if r["building_id"] == c[0]:
					proj = r["projected"]
					t.ok(not (r["lots"] as Array).is_empty() and r["lots"][0] == c[1], "%s: projected on its first free lot %s" % [c[0], c[1]])
		var a := _load_js(js)
		var level := int(a.town_sim.buildings.get(c[1], {}).get("level", 0)) + 1
		t.ok(a.town_sim.place_building(c[1], c[0], level), "%s finished on %s at level %d in a copy (setup)" % [c[0], c[1], level])
		var b0 := _load_js(js)
		a.tick(a.substep_s())
		b0.tick(b0.substep_s())
		var ra: Dictionary = a.view_rates()["rates"]
		var rb: Dictionary = b0.view_rates()["rates"]
		var worst := 0.0
		for id in ["workers", "bodies", "gold", "bone", "living"]:
			worst = maxf(worst, absf(float(proj[id]) - (float(ra[id]["net"]) - float(rb[id]["net"]))))
		for id in ["mint", "work", "flood"]:
			worst = maxf(worst, absf(float(proj[id]) - (float(ra[id]["in"]) - float(rb[id]["in"]))))
		t.ok(worst < 1e-9, "%s: projected = the realized change in view_rates after one substep (worst %s): %s" % [c[0], _sci(worst), str(proj)])
		t.ok(absf(float(proj["war"]) - float(proj["mint"]) * float(v["war"])) < 1e-12 and proj["corpses"] == 0.0
			and float(proj["backlog"]) >= float(proj["flood"]) - 1e-12, "%s: war = Δmint × valve.war, corpses 0, backlog ≥ Δflood" % c[0])
	# pure: nothing changes, rev stays, no event; the live TownSim untouched
	var q := _load_js(js)
	q.tick(q.substep_s())
	q.drain_events()
	var before := _all(q)
	var ts_before := q.town_sim.to_dict()
	var staffing := q.town_sim.staffing.duplicate(true)
	var rv := q.rev
	q._proj_cache.clear()
	q.view_catalog()
	q.view_town()
	t.ok(_all(q) == before and q.town_sim.to_dict() == ts_before and q.town_sim.staffing == staffing and q.rev == rv
		and q.drain_events().is_empty(), "pure: every view, the save, TownSim and its staffing as before; rev stays; no event")
	# the cache (on the town's structure, refreshed every town.projection_refresh_s): a cached answer equals
	# a fresh one at the state it was computed; within the window it keeps that answer (the lag the doc
	# states); a structure change or the window's end recomputes it, and it equals a fresh one again
	var refresh := float(TestUtil.configs()["economy"]["town"]["projection_refresh_s"])
	var first := [_proj_of(q.view_catalog()), _proj_of(q.view_town())]
	q._proj_cache.clear()
	t.ok([_proj_of(q.view_catalog()), _proj_of(q.view_town())] == first, "the cached projections equal fresh ones at the same state")
	q.tick(q.substep_s())
	q.town_sim.workers += 8.0  # the workforce moves (no structure change): the projections a fresh compute gives move with it
	var lag := [_proj_of(q.view_catalog()), _proj_of(q.view_town())]
	q._proj_cache.clear()
	var fresh := [_proj_of(q.view_catalog()), _proj_of(q.view_town())]
	t.ok(lag == first and fresh != first, "a substep later, the workforce moved (inside the %.0f s window): the cache keeps its answer; a fresh one has moved" % refresh)
	var t1 := q.t
	var rv1 := q.rev
	q._core_step(refresh)  # a core step without a rev bump (as a catch-up runs it): the window ends
	var c1 := [_proj_of(q.view_catalog()), _proj_of(q.view_town())]
	q._proj_cache.clear()
	t.ok(q.t >= t1 + refresh and q.rev == rv1 and [_proj_of(q.view_catalog()), _proj_of(q.view_town())] == c1,
		"after %.0f s of sim (a core step that leaves rev alone) it is recomputed: it equals a fresh one" % refresh)
	q.view_catalog()
	q.view_town()
	t.ok(q.town_sim.place_building("lot-08", "house", 1), "a house appears (setup)")
	var c2 := [_proj_of(q.view_catalog()), _proj_of(q.view_town())]
	q._proj_cache.clear()
	t.ok([_proj_of(q.view_catalog()), _proj_of(q.view_town())] == c2 and c2 != c1, "a structure change recomputes it at once")
	var cc := q.view_catalog()
	cc["buildings"][0]["projected"]["gold"] = 1e9
	t.ok(q.view_catalog()["buildings"][0]["projected"]["gold"] != 1e9, "a fresh copy each call")


## The projections a catalog or town view carries, by row.
static func _proj_of(v: Dictionary) -> Array:
	return (v["buildings"] as Array).map(func(r): return r.get("projected", r.get("upgrade_projected", {})))


## A GameState loaded from `js`. `full` (the exactness and purity checks) overrides
## town.projection_rows_per_call in its configs so a view refreshes every stale row at once.
func _load_js(js: String, full := true) -> GameState:
	var c := TestUtil.configs()
	if full:
		c["economy"]["town"]["projection_rows_per_call"] = 1000
	var s := GameState.new(c)
	s.debug_enabled = true
	s.from_dict(JSON.parse_string(js))
	return s


## A full refresh at `s`'s state right now (town.projection_rows_per_call lifted for one call of each view),
## for comparing what the frame refresh shows against. Restores the configs and the cache after.
func _full_now(s: GameState) -> Array:
	var keep: Dictionary = s._proj_cache.duplicate(true)
	var per: Variant = s._cfgs["economy"]["town"]["projection_rows_per_call"]
	s._cfgs["economy"]["town"]["projection_rows_per_call"] = 1000
	s._proj_cache.clear()
	var out := [_proj_of(s.view_catalog()), _proj_of(s.view_town())]
	s._cfgs["economy"]["town"]["projection_rows_per_call"] = per
	s._proj_cache.clear()
	s._proj_cache.merge(keep)
	return out


## The units (rows and baselines) the frame refresh computed during `f`.
func _units(s: GameState, f: Callable) -> int:
	var n0 := int(s._proj_cache.get("rows_computed", 0))
	f.call()
	return int(s._proj_cache.get("rows_computed", 0)) - n0


## Whether every row of `got` is within town.projection_tol of `want` (rel × |got| + abs, the rule a held
## row was kept by), row by row and rate by rate. Empty rows must match exactly.
func _within_tol(got: Array, want: Array, tol: Dictionary) -> bool:
	if got.size() != want.size():
		return false
	for i in got.size():
		var g: Dictionary = got[i]
		var w: Dictionary = want[i]
		if g.keys() != w.keys():
			return false
		for id in w:
			if absf(float(g[id]) - float(w[id])) > float(tol["rel"]) * absf(float(g[id])) + float(tol["abs"]) + 1e-12:
				return false
	return true


## One frame-path tick (capped) that runs no substep and ends late in the substep interval, where the frame
## refresh works: the accumulator ends at least town.projection_phase of a substep full.
func _light(s: GameState, cap: int) -> void:
	var step := s.substep_s()
	var late := float(s._cfgs["economy"]["town"]["projection_phase"]) * step
	s.tick(maxf(step * 1e-5, late - s._acc + step * 1e-5), cap)


## The frame refresh (T3.2, STATE-API §5.10) at the shipped config: the views only read; GameState._advance
## refreshes at most town.projection_rows_per_frame units (the baseline counting as one) on a capped tick
## that ran no substep and ends late in the substep interval (town.projection_phase), only while
## view_catalog() was read within projection_refresh_s; substep frames
## refresh nothing until town.projection_starve_frames of them in a row let one row through; a refreshed
## row keeps its old value unless a rate moved past town.projection_tol; and after a structure change
## enough light frames converge on a fresh full compute.
func _projected_frame() -> void:
	t.suite("api-v6-projected-frame")
	var tc: Dictionary = TestUtil.configs()["economy"]["town"]
	var per := int(tc["projection_rows_per_frame"])
	var starve := int(tc["projection_starve_frames"])
	var tol: Dictionary = tc["projection_tol"]
	var js := JSON.stringify(_fixture("pre_vei").to_dict())
	var s := _load_js(js, false)
	var cap := s.max_substeps_per_frame()
	var step := s.substep_s()
	var light := step / 1000.0  # a frame's dt that runs no substep
	# the views only read
	var did := _units(s, func():
		s.view_catalog()
		s.view_town())
	t.ok(did == 0 and _proj_of(s.view_catalog()).all(func(p): return (p as Dictionary).is_empty()),
		"after a load the views compute nothing and every row reads {} (did %d)" % did)
	# tick(dt) with no cap (tests, harnesses) never refreshes
	did = _units(s, func():
		s.tick(light)
		s.tick(step))
	t.ok(did == 0, "an uncapped tick, with or without a substep, refreshes nothing (did %d)" % did)
	var phase := float(tc["projection_phase"])
	did = _units(s, func(): _light(s, 0))
	t.ok(did == 0 and s._acc >= phase * step and s._acc < step,
		"and one ending late in the interval (at %.2f of a substep), the catalog wanted and every row stale: did %d" % [s._acc / step, did])
	# wanted: view_town doesn't count; with no view_catalog read in the last projection_refresh_s, nothing
	var w := _load_js(js, false)
	did = _units(w, func():
		for i in 5:
			w.view_town()
			_light(w, cap))
	t.ok(did == 0, "with no view_catalog() read, light frames refresh nothing (view_town doesn't count; did %d)" % did)
	w.view_catalog()
	w.tick(float(tc["projection_refresh_s"]) + step)  # uncapped: the window passes with no read
	did = _units(w, func(): _light(w, cap))
	t.ok(did == 0, "a view_catalog() read older than projection_refresh_s of sim wants nothing (did %d)" % did)
	w.view_catalog()
	did = _units(w, func(): _light(w, cap))
	t.ok(did > 0, "a fresh read wants the rows again (did %d)" % did)
	# bounded: each light frame refreshes at most rows_per_frame units until nothing is stale
	s.view_catalog()
	var n_cat: int = s.view_catalog()["buildings"].size()
	var n_lot: int = s.town_sim.buildings.size()
	var worst := 0
	var frames := 0
	for i in n_cat + n_lot + 4:
		var d := _units(s, func(): _light(s, cap))
		worst = maxi(worst, d)
		frames += 1
	t.ok(worst > 0 and worst <= per, "a light frame refreshes at most %d units (the most: %d, over %d frames)" % [per, worst, frames])
	var full := _full_now(s)
	t.ok(_proj_of(s.view_catalog()) == full[0] and _proj_of(s.view_town()) == full[1],
		"after %d light frames at one state both views equal a full refresh (first values, so exact)" % frames)
	# a structure change makes every row stale; a substep frame still refreshes none of them (before the
	# starve rule's count), and enough light frames converge on a fresh full compute
	s.cmd_debug_grant({"gold": 5000.0, "bone": 400.0, "relics": 6})
	var up := ""
	for lot_id in s.town_sim.buildings:
		if s.cmd_upgrade(lot_id)["ok"]:
			up = lot_id
			break
	t.ok(up != "", "an upgrade starts on %s: the structure moved (setup)" % up)
	s.view_catalog()
	s._acc = 0.0
	did = _units(s, func(): s.tick(step, cap))
	t.ok(did == 0, "with every row stale, a frame that ran a substep refreshes nothing (did %d)" % did)
	# the phase: a frame without a substep early in the interval refreshes nothing, one late in it a unit
	did = _units(s, func(): s.tick(step * phase * 0.5, cap))
	t.ok(did == 0 and s._acc < phase * step, "early in the interval (the accumulator at %.2f of a substep, under %.2f) a light frame refreshes nothing (did %d)" % [
		s._acc / step, phase, did])
	did = _units(s, func(): _light(s, cap))
	t.ok(did == 1 and s._acc >= phase * step and s._acc < step, "late in it (at %.2f) one refreshes a unit (did %d)" % [s._acc / step, did])
	did = _units(s, func():
		for i in n_cat + n_lot + 2:
			_light(s, cap))
	full = _full_now(s)
	t.ok(did <= (n_cat + n_lot + 2) * per and _within_tol(_proj_of(s.view_catalog()), full[0], tol)
		and _within_tol(_proj_of(s.view_town()), full[1], tol),
		"after the structure change %d light frames give a full refresh's values within projection_tol (%d units)" % [n_cat + n_lot + 2, did])
	# churn: once the refresh window passes, a refreshed row keeps its value unless a rate moved past tol
	var held_before := [_proj_of(s.view_catalog()), _proj_of(s.view_town())]
	s.tick(float(tc["projection_refresh_s"]) + step)  # uncapped: the window passes, every row ages out
	s.view_catalog()
	var r0 := int(s._proj_cache.get("rows_replaced", 0))
	did = _units(s, func():
		for i in n_cat + n_lot + 2:
			_light(s, cap))
	var after := [_proj_of(s.view_catalog()), _proj_of(s.view_town())]
	full = _full_now(s)
	var rule := true
	var kept := 0
	var replaced := 0
	for part in 2:
		for i in (after[part] as Array).size():
			var a: Dictionary = after[part][i]
			var b: Dictionary = held_before[part][i]
			if a == b:
				kept += 0 if a.is_empty() else 1  # a {} row (constructing, at max_level) isn't refreshed at all
			else:
				replaced += 1
				if _within_tol([b], [full[part][i]], tol) or a != full[part][i]:
					rule = false  # replaced although within tol, or replaced by something other than the fresh value
	var counted := int(s._proj_cache.get("rows_replaced", 0)) - r0
	t.ok(rule and _within_tol(after[0], full[0], tol) and _within_tol(after[1], full[1], tol),
		"after a window each row is its old value (within tol of the fresh one) or the fresh value (%d kept, %d replaced, %d units)" % [
			kept, replaced, did])
	t.ok(kept > 0 and replaced > 0 and counted == replaced,
		"both happen: %d rows drifted less than the tolerance and were kept, %d moved past it (the count says %d)" % [kept, replaced, counted])
	# the starve rule: substep frames in a row refresh nothing until the starve_frames-th lets one row through
	s.cmd_set_valve(0.3, 0.55, 0.15)  # the valve target is in the signature: every row is stale
	var counts: Array = []
	for i in starve + 1:
		s.view_catalog()  # the town fetches on every rev move, so the catalog stays wanted
		s._acc = 0.0
		counts.append(_units(s, func(): s.tick(step, cap)))
	var first := counts.slice(0, starve - 1)
	t.ok(first.all(func(x): return x == 0) and int(counts[starve - 1]) == 2 and int(counts[starve]) == 0,
		"%d substep frames refresh nothing, the %d-th the baseline and one row, then the count restarts: %s" % [
			starve - 1, starve, str(counts)])


## Frame work changes nothing but the projections' own cache: two states from one save run the same light
## frames (past the phase), a structure change, more light frames and substep frames past the starve count,
## one reading view_catalog() before each frame (so the frame refresh runs) and one never (so it doesn't).
## Their rev, save, TownSim and events match after.
func _projection_frame_pure() -> void:
	t.suite("api-v6-projection-frame-pure")
	var js := JSON.stringify(_fixture("pre_vei").to_dict())
	var starve := int(TestUtil.configs()["economy"]["town"]["projection_starve_frames"])
	var seq := func(s: GameState, wanted: bool) -> void:
		var cap := s.max_substeps_per_frame()
		for i in 50:
			if wanted:
				s.view_catalog()
			_light(s, cap)
		s.cmd_debug_grant({"gold": 5000.0, "bone": 400.0, "relics": 6})
		for lot_id in s.town_sim.buildings:
			if s.cmd_upgrade(lot_id)["ok"]:
				break
		for i in 50:
			if wanted:
				s.view_catalog()
			_light(s, cap)
		for i in starve + 2:
			if wanted:
				s.view_catalog()
			s._acc = 0.0
			s.tick(s.substep_s(), cap)
	var a := _load_js(js, false)
	var b := _load_js(js, false)
	a.drain_events()
	b.drain_events()
	var da := _units(a, func(): seq.call(a, true))
	var db := _units(b, func(): seq.call(b, false))
	t.ok(da > 2 and db == 0, "(setup) the frame refresh ran on one (%d units) and not the other (%d)" % [da, db])
	t.ok(a.rev == b.rev, "rev is the same (%d, %d)" % [a.rev, b.rev])
	t.ok(a.to_dict() == b.to_dict(), "the save is the same")
	t.ok(a.town_sim.to_dict() == b.town_sim.to_dict(), "TownSim's own state is the same")
	var ea := a.drain_events()
	t.ok(ea == b.drain_events() and ea.size() > 0, "and so are the events (%d)" % ea.size())


## A full refresh of both views at `s` (the budget lifted for the calls), leaving the rows and the baseline
## in the cache and the shipped budget back in place.
func _fill(s: GameState) -> void:
	var per: Variant = s._cfgs["economy"]["town"]["projection_rows_per_call"]
	s._cfgs["economy"]["town"]["projection_rows_per_call"] = 1000
	s.view_catalog()
	s.view_town()
	s._cfgs["economy"]["town"]["projection_rows_per_call"] = per


func _all_empty(s: GameState) -> bool:
	return (_proj_of(s.view_catalog()) + _proj_of(s.view_town())).all(func(p): return (p as Dictionary).is_empty())


## A new game, a load and a fixture load each empty the projection cache, so another state's rows never
## show: every row reads {} until the frame refresh reaches it.
func _projection_reset() -> void:
	t.suite("api-v6-projection-reset")
	var js := JSON.stringify(_fixture("pre_vei").to_dict())
	for how in ["cmd_new_game", "cmd_load", "cmd_debug_load_fixture"]:
		var s := _load_js(js, false)
		s.save_dir = _dir
		s.clock_override = 1_800_000_000  # (E2b-2 T3.3b) a 0 s load: nothing to catch up
		var saved: bool = s.cmd_save("proj")["ok"] if how == "cmd_load" else true
		_fill(s)
		var c := s._proj_cache
		t.ok(saved and (c.get("catalog", {}) as Dictionary).size() > 0 and (c.get("upgrades", {}) as Dictionary).size() > 0
			and c.has("base") and not _all_empty(s), "%s: (setup) the cache holds rows and a baseline" % how)
		var ok := false
		match how:
			"cmd_new_game":
				ok = s.cmd_new_game(7)["ok"]
			"cmd_load":
				ok = s.cmd_load("proj")["ok"]
			"cmd_debug_load_fixture":
				ok = s.cmd_debug_load_fixture("midgame_2flips")["ok"]
		t.ok(ok and s._proj_cache.is_empty(), "%s: the cache is empty after (%s)" % [how, str(s._proj_cache.keys())])
		t.ok(_all_empty(s), "%s: every row reads {}" % how)
	var d := DirAccess.open(_dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(_dir)
	t.ok(not DirAccess.dir_exists_absolute(_dir), "the test save directory is gone")


## A cached upgrades row belongs to the lot's building and level it was computed for: after a finished
## upgrade (a new level) or a demolish and rebuild (another building) on a lot, that lot's row reads {}
## until it is refreshed, while the other lots keep their values.
func _projection_lot_bound() -> void:
	t.suite("api-v6-projection-lot-bound")
	var s := _load_js(JSON.stringify(_fixture("pre_vei").to_dict()), false)
	_fill(s)
	var before := {}
	for r in s.view_town()["buildings"]:
		if not (r["upgrade_projected"] as Dictionary).is_empty():
			before[r["lot_id"]] = r
	var up := ""
	var swap := ""
	var other := ""
	for lot_id in before:
		var r: Dictionary = before[lot_id]
		# an upgradable lot: level 1 and a building that reaches level 3 (so level 2 still has a projection to drop)
		if up == "" and int(r["level"]) == 1 and int(s.town_sim._defs[str(r["building_id"])]["max_level"]) >= 3:
			up = lot_id
		elif swap == "" and r["building_id"] != "house":
			swap = lot_id
		elif other == "":
			other = lot_id
	t.ok(up != "" and swap != "" and other != "", "(setup) lots: %s (max_level 3 or more) levels up, %s is rebuilt as a house, %s is untouched" % [up, swap, other])
	s.town_sim.place_building(up, str(before[up]["building_id"]), 2)  # the upgrade finished
	s.town_sim.place_building(swap, "house", 1)  # demolished and rebuilt
	var after := {}
	for r in s.view_town()["buildings"]:
		after[r["lot_id"]] = r["upgrade_projected"]
	t.ok((after[up] as Dictionary).is_empty(), "%s, now level 2, doesn't show the projection made for its level 1: {}" % up)
	t.ok((after[swap] as Dictionary).is_empty(), "%s, a house now, doesn't show the %s's projection: {}" % [swap, before[swap]["building_id"]])
	t.ok(after[other] == before[other]["upgrade_projected"], "%s keeps its last value until its turn" % other)
	s._cfgs["economy"]["town"]["projection_rows_per_call"] = 1000
	var fresh := s.view_town()
	s._cfgs["economy"]["town"]["projection_rows_per_call"] = 0
	var got := {}
	for r in fresh["buildings"]:
		got[r["lot_id"]] = r["upgrade_projected"]
	t.ok(not (got[up] as Dictionary).is_empty() and not (got[swap] as Dictionary).is_empty(),
		"once refreshed both lots show their own projections again")


## T3.4a (#5): the fort card's warden (name, tells) and loot hint come from raid.json's
## wardens.archetypes and loot.json's hints. Compared against the config, never a literal.
func _warden_card() -> void:
	t.suite("api-v6-warden-card")
	var cfgs := TestUtil.configs()
	var raid_w: Dictionary = cfgs["raid"]["wardens"]
	var hints: Dictionary = cfgs["loot"]["hints"]
	var s := GameState.new(cfgs)
	s.cmd_new_game(1)
	var by_fort: Dictionary = raid_w["by_fort"]
	t.ok(by_fort.size() == 12, "(setup) every fort has a warden in by_fort")
	for id in by_fort:
		var a: String = by_fort[id]
		var spec: Dictionary = raid_w["archetypes"].get(a, {})
		var w: Dictionary = s.view_fort(id)["warden"]
		t.ok(w["archetype"] == a and str(w["name"]) != "" and w["name"] == spec.get("name"), "%s: the card names %s as the config does" % [id, a])
		t.ok(not (w["tells"] as Array).is_empty() and w["tells"] == spec.get("tells"), "%s: the card's tells are the config's" % id)
	# the loot hint: the first dungeon's, else the tier's and archetype's, over every archetype and tier
	var first := ""
	for id in by_fort:
		if s.view_fort(id)["first_dungeon"]:
			first = id
	t.ok(first != "" and s.view_fort(first)["loot_hint"] == hints["first_dungeon_hint"] and s.view_fort(first)["loot_hint"] != "", "the first dungeon reads first_dungeon_hint")
	t.ok(StateRuns.dungeon_seed(s, first, 1, s.rev)["loot_hint"] == hints["first_dungeon_hint"], "(seed) the same hint")
	var seen := {}
	for a in raid_w["archetypes"]:
		var c2 := TestUtil.configs()
		for id in c2["raid"]["wardens"]["by_fort"]:
			c2["raid"]["wardens"]["by_fort"][id] = a
		var s2 := GameState.new(c2)
		s2.cmd_new_game(1)
		for f in s2.realm.forts:
			var fv := s2.view_fort(f["id"])
			if fv["first_dungeon"]:
				continue
			var key := "t%d.%s" % [int(f["tier"]), a]
			seen[key] = true
			t.ok(fv["loot_hint"] == str(hints.get(key, "")), "%s as %s reads hints[%s]" % [f["id"], a, key])
			t.ok(StateRuns.dungeon_seed(s2, f["id"], 1, s2.rev)["loot_hint"] == fv["loot_hint"], "%s: the raid seed reads the same hint" % f["id"])
	t.ok(seen.size() >= 4, "(setup) more than one tier was checked")
	# a hint key the config lacks reads ""
	var c3 := TestUtil.configs()
	c3["loot"]["hints"] = {}
	var s3 := GameState.new(c3)
	s3.cmd_new_game(1)
	var nonfirst := ""
	for id in by_fort:
		if not s3.view_fort(id)["first_dungeon"]:
			nonfirst = id
	t.ok(s3.view_fort(nonfirst)["loot_hint"] == "" and s3.view_fort(first)["loot_hint"] == "", "no hints in the config: every fort's hint is empty")
	# an archetype the config doesn't list: name "" and no tells
	var c4 := TestUtil.configs()
	(c4["raid"]["wardens"]["archetypes"] as Dictionary).erase(by_fort[nonfirst])
	var s4 := GameState.new(c4)
	s4.cmd_new_game(1)
	var w4: Dictionary = s4.view_fort(nonfirst)["warden"]
	t.ok(w4["archetype"] == by_fort[nonfirst] and w4["name"] == "" and w4["tells"] == [], "an unlisted archetype: name \"\" and tells []")

	# malformed sections (not a Dictionary / Array) read as missing and never crash
	var nf := ""
	for id in by_fort:
		if not s.view_fort(id)["first_dungeon"]:
			nf = id
	for bad in ["x", 7, [1], null]:
		var c5 := TestUtil.configs()
		c5["raid"]["wardens"]["archetypes"] = bad
		c5["raid"]["wardens"]["by_fort"] = bad
		c5["loot"]["hints"] = bad
		var s5 := GameState.new(c5)
		s5.cmd_new_game(1)
		var v5: Dictionary = s5.view_fort(nf)
		t.ok(v5["warden"]["archetype"] == "bellringer" and v5["warden"]["name"] == "" and v5["warden"]["tells"] == [] and v5["loot_hint"] == "",
			"non-dict archetypes, by_fort and hints (%s): the card reads the stub, \"\" and []" % str(bad))
	var c6 := TestUtil.configs()
	for k in c6["raid"]["wardens"]["archetypes"]:
		c6["raid"]["wardens"]["archetypes"][k]["tells"] = "not an array"
	var s6 := GameState.new(c6)
	s6.cmd_new_game(1)
	t.ok(s6.view_fort(nf)["warden"]["tells"] == [] and str(s6.view_fort(nf)["warden"]["name"]) != "", "non-array tells read []; the name stays")


## T3.4a: view_town().buildings[].starved, on the Bone Mill (lot-05 here): "pits_first" when the pits took bodies and the
## supply fell short of both, "no_bodies" when the pits took none either, "" with a surplus or no
## staffed mill; every other job's is "". Read from TownSim's last step; "" before one.
func _mill_starved() -> void:
	t.suite("api-v6-mill-starved")
	var s := _mk()
	var ts := s.town_sim
	t.ok(ts.place_building("lot-05", "bone_mill", 1), "(setup) a bone mill on lot-05")
	ts.ladder = ["pit", "mill"]
	ts.workers = 4.0
	t.ok(_mill_row(s)["starved"] == "", "before any step: \"\"")
	ts.bodies = 100.0
	ts.step(0.5, {"work_mass": 0.0})
	t.ok(float(s.town_sim.staffing["jobs"]["mill"]["staffed"]) > 0.0 and _mill_row(s)["starved"] == "", "a surplus: the mill got all it wants: \"\"")
	ts.bodies = 0.1  # wants this step: pits 0.3, mill 0.2 (test_town_sim's short-bodies case)
	var o := ts.step(0.5, {"work_mass": 0.0})
	t.ok(float(o["burned"]) > 0.0 and float(o["milled"]) < 0.2 and _mill_row(s)["starved"] == "pits_first", "supply below the pits' want and the mill's: \"pits_first\"")
	var blds := s.view_town()["buildings"] as Array
	t.ok(blds.all(func(r): return r["lot_id"] == "lot-05" or r["starved"] == ""), "no building without mill slots reads a reason")
	t.ok(not (s.view_town()["jobs"][0] as Dictionary).has("starved"), "the job rows are unchanged")
	ts.bodies = 100.0
	ts.step(0.5, {"work_mass": 0.0})
	t.ok(_mill_row(s)["starved"] == "", "a surplus again clears it")
	# nothing to mill: the store is empty, only the mill is staffed, and the rot return is under its want
	ts.ladder = ["mill", "pit"]
	ts.workers = 0.2
	ts.bodies = 0.0
	o = ts.step(0.5, {"work_mass": 0.0})
	t.ok(float(o["burned"]) == 0.0 and float(o["milled"]) < 0.2 * float(s.town_sim.staffing["jobs"]["mill"]["staffed"]) and _mill_row(s)["starved"] == "no_bodies",
		"no bodies and no pit burning: \"no_bodies\"")
	# a load reads "" until the first step (this state held "no_bodies" a moment ago)
	ts.ladder = ["pit", "mill", "haul", "build", "stall", "forge", "tend"]
	var ld := s.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	t.ok(ld["ok"] and s.town_sim.mill_starved == "" and _mill_row(s)["starved"] == "", "after a load: \"\" until the first step (%s)" % str(ld))
	t.ok(_mk().view_town()["buildings"].all(func(r): return r["starved"] == ""), "a fresh town: every building \"\"")


func _mill_row(s: GameState) -> Dictionary:
	for r in s.view_town()["buildings"]:
		if r["lot_id"] == "lot-05":
			return r
	return {}


## Every view's output and the save, for purity checks.
func _all(s: GameState) -> Array:
	return [s.to_dict(), s.view_hud(), s.view_rates(), s.view_town(), s.view_catalog(), s.view_realm(), s.view_vei(), s.ledger()]


static func _sci(x: float) -> String:
	return String.num_scientific(x) if x != 0.0 else "0"


## E2b-2 T3.3b (IDLE §4): cmd_load's away_s and capped extras, on success (the time caught up, capped
## above idle.catchup_max_s) and on every refusal (0.0 and false).
func _catchup_api() -> void:
	t.suite("api-v6-catchup")
	var dir := _dir + "_cu"
	DirAccess.make_dir_recursive_absolute(dir)
	var s := _fixture("midgame_2flips")
	s.save_dir = dir
	s.clock_override = 1_800_000_000
	t.ok(s.cmd_save("cu")["ok"], "(setup) saved")
	for away in [120, 0, -60]:
		var n := GameState.new(TestUtil.configs())
		n.debug_enabled = true
		n.save_dir = dir
		n.clock_override = 1_800_000_000 + away
		var r := n.cmd_load("cu")
		var errs: Array = []
		ApiSchema.check_command("cmd_load", r, errs)
		t.ok(errs.is_empty() and r["ok"] and r["away_s"] == float(maxi(away, 0)) and r["capped"] == false and n.t == s.t + maxi(away, 0),
			"cmd_load %d s on: ok, away_s %.1f, capped false %s" % [away, float(r["away_s"]), str(errs)])
	var c := TestUtil.configs()
	c["economy"]["idle"]["catchup_max_s"] = 60.0
	var m := GameState.new(c)
	m.save_dir = dir
	m.clock_override = 1_800_000_000 + 600
	var rc := m.cmd_load("cu")
	t.ok(rc["ok"] and rc["away_s"] == 60.0 and rc["capped"] == true, "600 s on with idle.catchup_max_s 60: away_s 60.0, capped: %s" % str(rc))
	var fail := m.cmd_load("missing")
	var errs: Array = []
	ApiSchema.check_command("cmd_load", fail, errs)
	t.ok(errs.is_empty() and fail == {"ok": false, "reason": "no_save", "away_s": 0.0, "capped": false}, "a refused cmd_load carries away_s 0.0 and capped false")
	var dd := DirAccess.open(dir)
	if dd != null:
		for f in dd.get_files():
			dd.remove(f)
		DirAccess.remove_absolute(dir)


## E2b-2 T3.3b (IDLE §4): cmd_load(slot, true) returns with the catch-up pending; while it runs every cmd_*
## refuses with catching_up (its own extras zero-valued, nothing changed,
## rev alone; not_debug still first for the debug and time commands; cmd_save's refusal emits save_failed),
## and view_catchup shows its progress.
func _catchup_chunked_api() -> void:
	t.suite("api-v6-catchup-chunked")
	var dir := _dir + "_cuc"
	DirAccess.make_dir_recursive_absolute(dir)
	var s := _fixture("midgame_2flips")
	s.save_dir = dir
	s.clock_override = 1_800_000_000
	t.ok(s.cmd_save("cu")["ok"], "(setup) saved")
	var n := GameState.new(TestUtil.configs())
	n.debug_enabled = true
	n.save_dir = dir
	n.clock_override = 1_800_000_000 + 7200
	var r := n.cmd_load("cu", true)
	var errs: Array = []
	ApiSchema.check_command("cmd_load", r, errs)
	t.ok(errs.is_empty() and r["ok"] and r["away_s"] == 7200.0 and r["capped"] == false and n.catching_up(),
		"cmd_load(slot, true): ok with away_s 7200.0 and capped false, the catch-up pending %s" % str(errs))
	var cu := n.view_catchup()
	errs = []
	ApiSchema.check(cu, ApiSchema.VIEWS["view_catchup"], "view_catchup", errs)
	t.ok(errs.is_empty() and cu["rev"] == n.rev and cu["active"] and cu["done_s"] == 0.0 and cu["total_s"] == 7200.0,
		"view_catchup before its first chunk: %s %s" % [str(cu), str(errs)])
	n.tick(1.0 / 60.0, n.max_substeps_per_frame())
	var mid := n.view_catchup()
	t.ok(mid["active"] and mid["done_s"] > 0.0 and mid["done_s"] < 7200.0 and mid["total_s"] == 7200.0,
		"a frame runs one chunk: %.1f of 7200 s done" % float(mid["done_s"]))
	var args := {
		"cmd_new_game": [1], "cmd_save": ["x"], "cmd_load": ["cu"], "cmd_set_time_scale": [2.0], "cmd_pause": [true],
		"cmd_set_valve": [1.0, 1.0, 1.0], "cmd_move_relish": ["covington"], "cmd_cancel_travel": [],
		"cmd_set_haul_target": ["auto"], "cmd_build": ["house", "lot-08"], "cmd_upgrade": ["lot-02"],
		"cmd_demolish": ["lot-05"], "cmd_cancel_build": ["lot-05"], "cmd_queue_build": ["house", "lot-08"],
		"cmd_unqueue": [0], "cmd_reorder_queue": [[]], "cmd_set_job_priority": [GameState.JOB_IDS.duplicate()],
		"cmd_set_staff_cap": ["lot-02", 1], "cmd_set_stance": ["vigil", true], "cmd_raise_big_undead": ["h1", [], "x"],
		"cmd_rename_big_undead": ["u1", "x"], "cmd_place_big_undead": ["u1", "crypt"], "cmd_craft": ["simulacrum"],
		"cmd_deploy_simulacrum": ["ashgate"], "cmd_staff_vat": [0, true], "cmd_set_party": [[]],
		"cmd_assign_front": ["u1", "giants"], "cmd_begin_dungeon": ["ashgate"], "cmd_begin_boss": [],
		"cmd_abort_dungeon": [], "cmd_run_checkpoint": [1, {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0}],
		"cmd_dismiss_away": [],
		"cmd_debug_grant": [{"gold": 1.0}], "cmd_debug_set_state": [{"paused": false}],
		"cmd_debug_load_fixture": ["day1"], "cmd_debug_skip_time": [1.0],
	}
	var names: Array = []
	for m in n.get_method_list():
		if str(m["name"]).begins_with("cmd_") and not names.has(str(m["name"])):
			names.append(str(m["name"]))
	t.ok(names.all(func(x): return args.has(x)) and names.size() == args.size(), "every cmd_* is tried (%d)" % names.size())
	var d0 := n.to_dict()
	var bad: Array = []
	for name in args:
		var rv := n.rev
		n.drain_events()
		var res: Variant = n.callv(name, args[name])
		errs = []
		ApiSchema.check_command(name, res, errs)
		# T3.3c: the run commands give a dead run's refusal before catching_up (no run is open during a
		# catch-up: every open run ends before one starts), so a dungeon scene on an ended run learns it is over
		var want := "no_run" if name in ["cmd_abort_dungeon", "cmd_run_checkpoint"] else "catching_up"
		if not (errs.is_empty() and res["ok"] == false and res["reason"] == want and n.rev == rv):
			bad.append("%s: %s %s" % [name, str(res), str(errs)])
		var evs := n.drain_events()
		if name == "cmd_save" and not (evs.size() == 1 and evs[0]["type"] == "save_failed" and evs[0]["reason"] == "catching_up"):
			bad.append("cmd_save's save_failed: %s" % str(evs))
	t.ok(bad.is_empty() and n.to_dict() == d0 and n.catching_up(), "during the catch-up every command refuses with catching_up (the run commands no_run), changing nothing%s" % (
		"" if bad.is_empty() else ": " + "; ".join(PackedStringArray(bad))))
	n.debug_enabled = false
	var nd := []
	for name in ["cmd_set_time_scale", "cmd_pause", "cmd_debug_grant", "cmd_debug_set_state", "cmd_debug_load_fixture", "cmd_debug_skip_time"]:
		nd.append(n.callv(name, args[name])["reason"])
	t.ok(nd.all(func(x): return x == "not_debug"), "in a release build not_debug still comes first: %s" % str(nd))
	n.debug_enabled = true
	var last := float(mid["done_s"])
	var rising := true
	var frames := 0
	while n.catching_up() and frames < 500:
		n.tick(1.0 / 60.0, n.max_substeps_per_frame())
		var v := n.view_catchup()
		rising = rising and (float(v["done_s"]) > last or not v["active"])
		last = float(v["done_s"])
		frames += 1
	var end := n.view_catchup()
	t.ok(rising and not end["active"] and end["done_s"] == 7200.0 and end["total_s"] == 7200.0,
		"view_catchup's done_s rises each frame to 7200 of 7200 s, then it is done (%d frames)" % frames)
	t.ok(n.cmd_set_valve(1.0, 1.0, 1.0)["ok"], "commands work again once it is done")
	var fail := n.cmd_load("missing")
	errs = []
	ApiSchema.check_command("cmd_load", fail, errs)
	t.ok(errs.is_empty() and fail == {"ok": false, "reason": "no_save", "away_s": 0.0, "capped": false}, "a refused cmd_load carries away_s 0.0 and capped false")
	var dd := DirAccess.open(dir)
	if dd != null:
		for f in dd.get_files():
			dd.remove(f)
		DirAccess.remove_absolute(dir)


## E2b-2 T3.3c (api-request #4; IDLE I5): cmd_run_checkpoint(run_id, loot, outcome := "retreated") -> {ok,
## reason}, its reasons in order (no_run, wrong_run, wrong_kind for a boss run, invalid, bad_outcome; a refusal
## changes nothing and leaves rev, a success adds 1), the save's pending_retreat (written only while a run is
## open) and the run_ended event a gap raises, all in the contract.
func _run_checkpoint_api() -> void:
	t.suite("api-v6-checkpoint")
	var loot := {"relics": 1, "blueprints": ["embalmer"], "husks": [{"kind": "hulk"}], "remnants": [{"aspect": "wits", "rarity": "common", "magnitude": 1}], "essence": 2}
	var s := _mk()
	t.ok(not s.to_dict().has("pending_retreat"), "no run open: the save has no pending_retreat")
	var got: Array = [s.cmd_run_checkpoint(1, loot)]
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	var b := s.cmd_begin_dungeon("old-sluice")
	var id := int(b["run_id"])
	got.append(s.cmd_run_checkpoint(id + 1, loot))
	var bad_loot := loot.duplicate(true)
	bad_loot["relics"] = -1
	got.append(s.cmd_run_checkpoint(id, bad_loot))
	got.append(s.cmd_run_checkpoint(id, loot, "won"))
	var bad_both := bad_loot.duplicate(true)
	got.append(s.cmd_run_checkpoint(id, bad_both, "won"))
	var d0 := s.to_dict()
	var rv := s.rev
	var reasons: Array = got.map(func(r): return r["reason"])
	var shape_ok := true
	for i in got.size():
		var errs: Array = []
		ApiSchema.check_command("cmd_run_checkpoint", got[i], errs)
		shape_ok = shape_ok and errs.is_empty() and got[i].keys().size() == 2
	t.ok(shape_ok and reasons == ["no_run", "wrong_run", "invalid", "bad_outcome", "invalid"] and s.rev == rv and s.to_dict() == d0,
		"no_run, wrong_run, invalid (before bad_outcome), bad_outcome: {ok, reason} only, nothing changed: %s" % str(reasons))
	var ok := s.cmd_run_checkpoint(id, loot, "warden_beaten")
	t.ok(ok == {"ok": true, "reason": ""} and s.rev == rv + 1, "a checkpoint: ok, +1 rev")
	var pr: Dictionary = s.to_dict().get("pending_retreat", {})
	var errs: Array = []
	ApiSchema.check(pr, ApiSchema.PENDING_RETREAT, "pending_retreat", errs)
	t.ok(errs.is_empty() and pr["loot"] == loot and pr["outcome"] == "warden_beaten" and pr["run_id"] == id and pr["fort_id"] == "old-sluice"
		and pr["kind"] == "raid", "to_dict's pending_retreat holds the last checkpoint, in the contract %s" % str(errs))
	# a gap ends it: run_ended in the contract
	s.drain_events()
	s.tick(60.0, s.max_substeps_per_frame())
	var ev: Dictionary = s.drain_events()[0]
	errs = []
	ApiSchema.check(ev, ApiSchema.EVENTS["run_ended"], "run_ended", errs)
	t.ok(errs.is_empty() and ev["type"] == "run_ended" and ev["cause"] == "gap" and ev["outcome"] == "warden_beaten" and ev["kind"] == "raid",
		"a 60 s gap: run_ended {run_id, kind, outcome, cause: gap} in the contract: %s %s" % [str(ev), str(errs)])
	var m := _fixture("pre_vei")
	var bb := m.cmd_begin_boss()
	t.ok(m.cmd_run_checkpoint(int(bb["run_id"]), loot)["reason"] == "wrong_kind", "a boss run: wrong_kind")
	var mp: Dictionary = m.to_dict()["pending_retreat"]
	t.ok(mp["kind"] == "boss" and mp["fort_id"] == "vei" and mp["loot"] == StateRuns.empty_loot() and mp["outcome"] == "retreated",
		"an open boss run saves as pending_retreat {boss, vei, empty loot, retreated}: %s" % str(mp))


## E2b-2 T3.3c (IDLE I5): Relish walks home from the retaken fort she stands at: the event relish_returned
## {fort_id, cause: "retaken"} and view_relish().returned {fort_id, cause, t} ({} before any), both in the
## contract; the save's relish.returned (written once there is one) the same shape.
func _relish_returned_api() -> void:
	t.suite("api-v6-returned")
	var s := _mk()
	t.ok(s.view_relish()["returned"] == {}, "a new game: returned is {}")
	s.cmd_debug_set_state({"relish_at": "greywall", "valve": {"work": 0.0, "war": 0.0, "flood": 1.0},
		"forts": {"greywall": {"living": 60.0, "undead": 0.0}}})
	s.realm.hold("greywall", 0.0)
	s.drain_events()
	var ev := {}
	for i in int(float(s._cfg()["hold"]["break_s"]) / s.substep_s()) + 2:
		s.tick(s.substep_s())
		for e in s.drain_events():
			if e["type"] == "relish_returned":
				ev = e
	var errs: Array = []
	ApiSchema.check(ev, ApiSchema.EVENTS["relish_returned"], "relish_returned", errs)
	var ret: Dictionary = s.view_relish()["returned"]
	ApiSchema.check(ret, ApiSchema.RELISH_RETURNED, "view_relish.returned", errs)
	ApiSchema.check(s.to_dict()["relish"]["returned"], ApiSchema.RELISH_RETURNED, "to_dict.relish.returned", errs)
	t.ok(errs.is_empty() and ev["fort_id"] == "greywall" and ev["cause"] == "retaken" and ret["t"] == ev["t"] and ret["fort_id"] == "greywall",
		"relish_returned {greywall, retaken}; view_relish().returned and the save's relish.returned {fort_id, cause, t}, in the contract %s" % str(errs))


## E2b-2 T3.3c (api-request #7 d; IDLE §7): view_away() -> {rev, shown, away_s, capped, gains, ready, losses},
## each line {text, kind, target} with `kind` in the request's list and `target` a fort id, "slab", "queue" or
## ""; empty and not shown before any; cmd_dismiss_away() -> {ok, reason}; the away_report {away_s, capped}
## event. All in the contract.
func _away_api() -> void:
	t.suite("api-v6-away")
	var dir := _dir + "_away"
	DirAccess.make_dir_recursive_absolute(dir)
	var s := _mk()
	t.ok(s.view_away() == {"rev": s.rev, "shown": false, "away_s": 0.0, "capped": false, "gains": [], "ready": [], "losses": []},
		"a new game: no report (shown false, the lists empty)")
	s.cmd_debug_load_fixture("midgame_2flips")
	s.save_dir = dir
	s.clock_override = 1_800_000_000
	s.cmd_save("away")
	var n := GameState.new(TestUtil.configs())
	n.debug_enabled = true
	n.save_dir = dir
	n.clock_override = 1_800_000_000 + 7200
	n.cmd_load("away")
	var v := n.view_away()
	var spec: Dictionary = (ApiSchema.VIEWS["view_away"] as Dictionary).duplicate()
	spec["rev"] = TYPE_INT
	var errs: Array = []
	ApiSchema.check(v, spec, "view_away", errs)
	var forts := n.realm.forts.map(func(f): return str(f["id"]))
	var bad: Array = []
	for k in ["gains", "ready", "losses"]:
		for l in v[k]:
			if not ApiSchema.AWAY_KINDS.has(l["kind"]) or not (forts.has(l["target"]) or l["target"] in ["slab", "queue", ""]):
				bad.append(str(l))
	t.ok(errs.is_empty() and bad.is_empty() and v["shown"] and v["away_s"] == 7200.0 and not v["gains"].is_empty(),
		"a 2 h load's view_away matches the contract, every kind and target in its list %s %s" % [str(errs), str(bad)])
	var ev: Array = n.drain_events().filter(func(e): return e["type"] == "away_report")
	errs = []
	if ev.size() == 1:
		ApiSchema.check(ev[0], ApiSchema.EVENTS["away_report"], "away_report", errs)
	t.ok(ev.size() == 1 and errs.is_empty() and ev[0]["away_s"] == 7200.0 and ev[0]["capped"] == false, "one away_report {away_s, capped} in the contract %s" % str(errs))
	var r := n.cmd_dismiss_away()
	errs = []
	ApiSchema.check_command("cmd_dismiss_away", r, errs)
	t.ok(errs.is_empty() and r == {"ok": true, "reason": ""} and not n.view_away()["shown"], "cmd_dismiss_away: {ok, reason}, shown false %s" % str(errs))
	var dd := DirAccess.open(dir)
	if dd != null:
		for f in dd.get_files():
			dd.remove(f)
		DirAccess.remove_absolute(dir)


## E2b-2 T3.3c (the dungeon's D-e, via the run's manager): the raid seed's death_ends {outcome, respawn_s} is
## view_backups().death's outcome and respawn_s, with no clone ready (unmade) and with one (clone); the boss
## seed's is unmade (a fight ends in a death only once every backup is spent), with a clone ready or not. Both
## validate (Results: an optional key, checked when present; a bad outcome is range:death_ends.outcome).
func _death_ends() -> void:
	t.suite("api-v6-death-ends")
	for clones in [0, 1, 2]:
		var s := _mk()
		s.clones_ready = clones
		s.cmd_debug_set_state({"relish_at": "old-sluice"})
		var b := s.cmd_begin_dungeon("old-sluice")
		var de: Dictionary = b["seed"]["death_ends"]
		var bd: Dictionary = s.view_backups()["death"]
		t.ok(de == {"outcome": bd["outcome"], "respawn_s": bd["respawn_s"]} and de["outcome"] == ("unmade" if clones == 0 else "clone")
			and Results.validate("raid_seed", b["seed"]).is_empty() and s.view_dungeon_seed("old-sluice")["death_ends"] == de,
			"%d clones ready: the raid seed's death_ends %s is view_backups().death's" % [clones, str(de)])
		var m := _mk()
		m.clones_ready = clones
		m.cmd_debug_set_state({"relish_at": "vei"})
		var bb := m.cmd_begin_boss()
		t.ok(bb["seed"]["death_ends"] == {"outcome": "unmade", "respawn_s": 0.0} and Results.validate("boss_seed", bb["seed"]).is_empty(),
			"%d clones ready: the boss seed's death_ends is unmade (backups go first): %s" % [clones, str(bb["seed"]["death_ends"])])
	var s2 := _mk()
	s2.cmd_debug_set_state({"relish_at": "old-sluice"})
	var sd: Dictionary = s2.cmd_begin_dungeon("old-sluice")["seed"]
	var bad := sd.duplicate(true)
	bad["death_ends"]["outcome"] = "phylactery"
	var no := sd.duplicate(true)
	no.erase("death_ends")
	t.ok(Results.validate("raid_seed", bad) == ["range:death_ends.outcome"] and Results.validate("raid_seed", no).is_empty(),
		"Results: a death_ends outcome outside clone/unmade is range:death_ends.outcome; a seed without it is valid (optional)")
