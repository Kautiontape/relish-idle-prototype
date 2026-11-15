extends RefCounted
## view_rates live for every RATE_IDS id (STATE-API §5.2, T2.5): each id's in, out and net against
## the stream it describes, from the last substep's flows, and view_hud.rates read from the same
## numbers. The influence field is shrunk in memory (a copy of the configs); nothing here reads it.
## Headless, no autoloads.

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


func _sum(s: GameState, key: String) -> float:
	var x := 0.0
	for f in s.realm.forts:
		x += float(f[key])
	return x


## A game where every stream runs: Relish standing at old-sluice (tide and the redirect) on a pile of
## corpses, corpses at ashgate for the haul and k_clear, a mill, and the valve sending some FLOOD.
func _busy() -> GameState:
	var s := GameState.new(_cfgs())
	s.debug_enabled = true
	s.cmd_new_game(3)
	s.cmd_debug_grant({"gold": 500.0, "bone": 200.0})
	s.cmd_build("bone_mill", "lot-05")
	s.cmd_debug_set_state({"forts": {"old-sluice": {"undead": 30.0, "dead": 40.0}, "ashgate": {"dead": 60.0}}})
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	s.cmd_debug_skip_time(120.0)
	return s


func run() -> int:
	t.suite("game_state_rates")
	_each_id()
	_mass_balance()
	_hud()
	_session_only()
	return t.failures


func _each_id() -> void:
	var s := _busy()
	var dt := s.substep_s()
	var eco: Dictionary = _base["economy"]
	var mass := float(eco["worker"]["mass"])
	var feed_before := float(s.town_sim.rates["feed"])  # the mint reads the feed of the step before
	var pits := s.town_sim.pits()
	var c0: float = s.realm.cleared_total
	# give Vei room to digest undead this substep (her pool fills fast, and she takes the dead first)
	s.realm.vei["living_pool"] = 0.0
	s.realm.vei["dead_queue"] = 0.0
	s.tick(dt)
	var r: Dictionary = s.view_rates()["rates"]
	var tr: Dictionary = s.town_sim.rates
	var keys := r.keys()
	keys.sort()
	var want := GameState.RATE_IDS.duplicate()
	want.sort()
	t.ok(keys == want, "one entry per RATE_IDS id")
	var nets := true
	for id in r:
		nets = nets and r[id]["net"] == r[id]["in"] - r[id]["out"] and r[id]["unit"] == GameState._RATE_UNITS[id]
	t.ok(nets, "net is in − out everywhere, with §5.2's units")
	# mint and the valve's streams
	var rcfg: Dictionary = _base["realm"]
	var mint := (float(rcfg["P_base"]) + float(rcfg["P_per_pit"]) * pits) * (1.0 + float(eco["pit"]["bonus"]) * feed_before)
	t.near(r["mint"]["in"], mint, 1e-12, "mint.in: (P_base + P_per_pit · pits) · (1 + pit.bonus · last step's feed)")
	t.ok(r["mint"]["out"] == r["mint"]["in"] and r["mint"]["net"] == 0.0, "mint.out: all of it goes through the valve (net 0)")
	var muster := float(tr["workers"]["muster"]) * mass
	t.near(r["work"]["in"], mint * s.valve["work"], 1e-12, "work.in: mint · valve.work")
	t.near(r["war"]["in"], mint * s.valve["war"] + muster, 1e-9, "war.in: mint · valve.war + muster × worker.mass")
	t.near(r["flood"]["in"], mint * s.valve["flood"], 1e-12, "flood.in: mint · valve.flood")
	t.near(r["war"]["in"], _sum(s, "r_in") + s.realm.r_war_to_vei, 1e-9, "war: what the forts (and Vei, on a fall-through) received")
	t.ok(r["flood"]["in"] == s.realm.r_flood and s.work_pending == 0.0, "flood is what reached Vei; work went to TownSim in the same substep")
	for id in ["work", "war", "flood"]:
		t.ok(r[id]["out"] == r[id]["in"] and r[id]["net"] == 0.0, "%s: delivered = in, net 0" % id)
	# the town
	t.near(r["workers"]["in"], r["work"]["in"] / mass, 1e-12, "workers.in: this substep's work / worker.mass (WORK arrives in the same substep)")
	t.near(r["workers"]["out"], float(tr["workers"]["rot"]) + float(tr["workers"]["muster"]), 1e-12, "workers.out: rot + muster")
	t.ok(r["bodies"]["in"] == float(tr["bodies"]["rot"]) + s._haul_rate() and r["bodies"]["out"] == float(tr["bodies"]["pit"]) + float(tr["bodies"]["mill"]),
		"bodies: haul (trip-averaged) + rot return in, pit burn + mill out")
	t.near(float(tr["bodies"]["rot"]), float(tr["workers"]["rot"]) * mass * float(eco["worker"]["body_return"]), 1e-12, "rot return: rot × worker.mass × body_return")
	t.ok(r["gold"]["in"] == float(tr["gold"]["in"]) and r["gold"]["in"] == float(tr["trade_rate"]) * float(eco["market"]["price"]) and r["gold"]["out"] == float(tr["gold"]["out"]),
		"gold: trade in, upkeep out")
	t.ok(r["bone"]["in"] == float(tr["bone"]["in"]) and r["bone"]["out"] == float(tr["bone"]["out"]) and r["bone"]["in"] > 0.0, "bone: the mill in, upkeep out")
	t.ok(r["living"]["in"] == float(tr["living"]["in"]) and r["living"]["out"] == float(tr["living"]["out"]), "living: migrants in, departures out")
	# the realm
	var cleared: float = s.realm.cleared_total - c0
	t.near(r["corpses"]["in"], _sum(s, "r_kills") + _sum(s, "r_redirected"), 1e-12, "corpses.in: Σ forts' kills + redirected garrison kills")
	var os: Dictionary = s.realm.fort_by_id("old-sluice")
	t.ok(os["r_dead_out"] == 0.0 and os["r_raised"] > 0.0, "Relish's redirect and raise both run at old-sluice (its garrison kills stay; it ships none)")
	t.near(r["corpses"]["out"], _sum(s, "r_raised") + cleared / dt + s._haul_rate(), 1e-12,
		"corpses.out: raises (Relish, simulacra) + k_clear + the haul (trip-averaged)")
	t.ok(cleared > 0.0, "k_clear runs")
	t.ok(r["backlog"]["in"] == s.realm.vei["r_in_undead"], "backlog.in: what entered Vei's undead queue")
	t.near(r["backlog"]["in"], s.realm.r_flood + _sum(s, "r_drain") + s.realm.r_war_to_vei, 1e-12, "= FLOOD + the forts' drain + WAR fallen through")
	t.ok(r["backlog"]["out"] == s.realm.r_digested_undead and r["backlog"]["out"] > 0.0, "backlog.out: Vei's digestion")
	t.ok(r["backlog"]["net"] == s.view_vei()["diff"], "backlog.net == view_vei.diff (the raw differential)")


## The realm's ids against the mass they describe: with no haul out, the corpses' net is what the
## forts' dead did over the substep, and the backlog's net what Vei's undead queue did.
func _mass_balance() -> void:
	var s := _busy()
	var dt := s.substep_s()
	s.cmd_set_staff_cap("lot-03", 0)  # the Charnel House's haulers stand down
	s.cmd_debug_skip_time(30.0)
	t.ok((s.town_sim.haul["convoys"] as Array).is_empty() and s._haul_rate() == 0.0, "no convoy out")
	var dead0 := _sum(s, "dead")
	var q0: float = s.realm.vei["undead_queue"]
	s.tick(dt)
	var r: Dictionary = s.view_rates()["rates"]
	t.near(r["corpses"]["net"], (_sum(s, "dead") - dead0) / dt, 1e-9, "corpses.net = Δ Σ forts' dead / dt (%.3f mass/s)" % r["corpses"]["net"])
	t.near(r["backlog"]["net"], (float(s.realm.vei["undead_queue"]) - q0) / dt, 1e-9, "backlog.net = Δ backlog / dt (%.3f mass/s)" % r["backlog"]["net"])


func _hud() -> void:
	var s := _busy()
	s.tick(s.substep_s())
	var r: Dictionary = s.view_rates()["rates"]
	var hud := s.view_hud()
	var ok := true
	for i in GameState.HUD_RATE_IDS.size():
		var id: String = GameState.HUD_RATE_IDS[i]
		var e: Dictionary = hud["rates"][i]
		ok = ok and e["id"] == id and e["unit"] == r[id]["unit"]
		ok = ok and e["rate"] == (r[id]["in"] if id == "mint" else r[id]["net"])
	t.ok(ok, "view_hud.rates: mint's rate is view_rates' mint.in, the rest are view_rates' nets")
	t.ok(hud["split"] == {"work": r["work"]["in"], "war": r["war"]["in"], "flood": r["flood"]["in"]}, "view_hud.split is view_rates' work, war and flood")


## The realm's streams are session-only: 0 after a load until the first substep. The valve's (the mint and
## its split) are too, but a load rebuilds them from what the save holds (E2b-2 T3.3b, the load flash:
## GameState._restore_dispatch), so they read the last substep's.
func _session_only() -> void:
	var s := _busy()
	s.tick(s.substep_s())
	var n := GameState.new(_cfgs())
	n.debug_enabled = true
	n.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	var r: Dictionary = n.view_rates()["rates"]
	var r0: Dictionary = s.view_rates()["rates"]
	var same := float(r0["mint"]["in"]) > 0.0
	for id in ["mint", "work", "war", "flood"]:
		for k in ["in", "out"]:
			same = same and absf(float(r[id][k]) - float(r0[id][k])) <= 1e-12 * maxf(1.0, absf(float(r0[id][k])))
	t.ok(same, "after a load: the mint and the valve's split read the last substep's, rebuilt from the save (mint %.4f)" % float(r["mint"]["in"]))
	var zero: bool = r["backlog"]["in"] == 0.0 and r["backlog"]["out"] == 0.0
	t.ok(zero and r["corpses"]["in"] == 0.0 and r["corpses"]["out"] == n._haul_rate(), "after a load: corpses and backlog read 0 (the haul's part is TownSim's, saved)")
	var w0: Dictionary = s.view_rates()["rates"]["workers"]
	t.ok(absf(r["workers"]["in"] - w0["in"]) <= 1e-12 * w0["in"] and absf(r["workers"]["out"] - w0["out"]) <= 1e-12 * maxf(1.0, w0["out"]),
		"the town's rates are saved with TownSim (to the 15 digits a save keeps)")
	n.tick(n.substep_s())
	t.ok(n.view_rates()["rates"]["backlog"]["in"] > 0.0 and n.view_rates()["rates"]["corpses"]["in"] > 0.0, "the first substep fills them")
