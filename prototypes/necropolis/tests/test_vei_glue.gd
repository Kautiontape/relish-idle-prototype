extends RefCounted
## E3-5, the Vei glue (MECHANICS §6; STATE-API §5.14, §7.2, §8.3 boss steps 3-4). Headless, no autoloads:
## - view_vei().fronts: need and have against the vei.json formula for a known state (worked from the config here,
##   not by VeiFronts), cleared = have >= need, and fronts_met the cleared count;
## - `assigned` is cmd_assign_front's echo, as before (the uids whose front is that id); `counted` (v8) is the uids
##   VeiFronts counted: an unassigned party member is in `counted` on its best-stat front and in no `assigned`, an
##   assigned one is in both, and a big undead outside the party counts nowhere;
## - the boss seed's fronts keep §7.2's shape {id, need, have, assigned} (no cleared, no counted) and carry view_vei's
##   live need/have at issue; Results.validate("boss_seed") and the schema take it;
## - the gate (the run's manager's condition): on pre_vei and midgame_2flips (Relish moved to Vei), and pre_vei with a
##   party member unassigned, the seed's fronts' need and have are exactly VeiFronts.have_need(
##   VeiFronts.info_from_boss_seed(seed), ConfigDb's vei), the fight's own recompute, in FRONT_IDS order. The suites run
##   before autoloads exist, so ConfigDb's data is built by ConfigDb's own script and its own reload(), the call that
##   fills ConfigDb.data at boot; and GameState keeps the Dictionary setup() is given (no copy), as Game._ready gives it
##   ConfigDb.data;
## - the fight's backups (boss step 3): one relish_died{in_place: true, at: "vei", respawn_s: 0.0} per backup in
##   backups_spent, the phylactery charges first, then the clones, after vei_result;
## - a final death after every backup (step 4): the shared death rule at no clone left, unmade for
##   backups.unmade_respawn_s (600 s), after the in-place events.

var t := TestUtil.new()
## pre_vei's boss seed at E3-3 (test_api_v6's pin, 35ceaa1's JSON with filled_slots stripped): the fronts' need and
## have were 0.0 then.
const PRE_VEI_ZEROED_SHA := "92992a68afbea9f5cf9f1ec9a792f62e431b2a7d12fc629c8c622b7e7609d7c1"


func run() -> int:
	t.suite("vei_glue")
	_formula()
	_counted()
	_seed()
	_config_source()
	_gate()
	_seed_otherwise_unchanged()
	_backups_in_place()
	_final_death()
	_final_death_vat_filled()
	return t.failures


## ConfigDb's data: its own script, its own reload() (GameState.load_configs("res://configs")), as at boot.
static func _configdb_data() -> Dictionary:
	var db = load("res://autoload/config_db.gd").new()
	db.reload()
	var d: Dictionary = db.data
	db.free()
	return d


func _mk() -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(1)
	s.debug_enabled = true
	return s


func _fixture(name: String) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture(name)["ok"], "(setup) %s loads" % name)
	return s


## A known state on a new game: four big undead with set stats, three in the party (A on giants, B unassigned with
## presence its top stat, C on raw) and D in the crypt (stats that would clear everything), Vei's backlog 30 000 and
## pool 200. Returns [state, [A, B, C, D]].
func _known() -> Array:
	var s := _mk()
	var g := s.cmd_debug_grant({"big_undead": 4})
	var u: Array = g["applied"]["minted"]
	t.ok(g["ok"] and u.size() == 4, "(setup) four big undead minted: %s" % str(u))
	var stats := [
		{"power": 2.0, "beef": 3.0, "wits": 9.0, "presence": 1.0, "speed": 1.0},
		{"power": 1.0, "beef": 1.0, "wits": 1.0, "presence": 6.0, "speed": 1.0},
		{"power": 12.0, "beef": 2.0, "wits": 1.0, "presence": 1.0, "speed": 1.0},
		{"power": 50.0, "beef": 50.0, "wits": 50.0, "presence": 50.0, "speed": 50.0},
	]
	for i in 4:
		s._find_uid(s.big_undead, u[i])["stats"] = stats[i]
	t.ok(s.cmd_set_party([u[0], u[1], u[2]])["ok"] and s.cmd_assign_front(u[0], "giants")["ok"]
		and s.cmd_assign_front(u[2], "raw")["ok"], "(setup) A, B, C in the party; A on giants, C on raw, B unassigned")
	s.realm.vei["undead_queue"] = 30000.0
	s.realm.vei["living_pool"] = 200.0
	return [s, u]


## The formula, worked from vei.json: have = per_stat · Σ stat of the counted + per_backlog · backlog + per_q · q;
## need = need_base + need_per_pool · living_pool; cleared = have >= need. Here giants counts A's wits, swarm B's
## presence (unassigned: its top stat), carvers nobody, raw C's power; D (crypt) nowhere.
func _formula() -> void:
	var k := _known()
	var s: GameState = k[0]
	var u: Array = k[1]
	var cfg: Dictionary = TestUtil.configs()["vei"]["fronts"]
	var q := s.digest_q()
	var who := {"giants": [u[0]], "swarm": [u[1]], "carvers": [], "raw": [u[2]]}
	var vv := s.view_vei()
	var fr: Array = vv["fronts"]
	t.ok(fr.map(func(f): return f["id"]) == GameState.FRONT_IDS, "view_vei's fronts in FRONT_IDS order")
	var met := 0
	for f in fr:
		var c: Dictionary = cfg[f["id"]]
		var sum := 0.0
		for uid in who[f["id"]]:
			sum += float(s._find_uid(s.big_undead, uid)["stats"][c["stat"]])
		var have := float(c["per_stat"]) * sum + float(c["per_backlog"]) * 30000.0 + float(c["per_q"]) * q
		var need := float(c["need_base"]) + float(c["need_per_pool"]) * 200.0
		t.near(float(f["have"]), have, 1e-9, "%s: have %.4f = %s·Σ%s + %s·30000 + %s·q (q %.4f)" % [f["id"], f["have"], c["per_stat"], c["stat"], c["per_backlog"], c["per_q"], q])
		t.near(float(f["need"]), need, 1e-9, "%s: need %.4f = %s + %s·200" % [f["id"], f["need"], c["need_base"], c["need_per_pool"]])
		t.ok(f["cleared"] == (float(f["have"]) >= float(f["need"])), "%s: cleared %s is have >= need" % [f["id"], f["cleared"]])
		if f["cleared"]:
			met += 1
	# at the shipped vei.json: giants 9 / 18 open, swarm 24 / 16 met, carvers 3q / 22 open, raw 48 / 46 met
	t.ok(fr.map(func(f): return f["cleared"]) == [false, true, false, true], "swarm and raw met, giants and carvers open: %s" % str(fr.map(func(f): return f["cleared"])))
	t.ok(vv["fronts_met"] == met and vv["fronts_met"] == 2 and vv["fronts_required"] == 3, "fronts_met 2 (the cleared count), fronts_required 3")
	# the backlog moves have where it counts (swarm and raw), and the pool moves need
	s.realm.vei["undead_queue"] = 0.0
	s.realm.vei["living_pool"] = 600.0
	var v2: Array = s.view_vei()["fronts"]
	t.near(float(v2[1]["have"]), 6.0, 1e-9, "swarm without a backlog: B's presence alone")
	t.near(float(v2[3]["need"]), float(cfg["raw"]["need_base"]) + float(cfg["raw"]["need_per_pool"]) * 600.0, 1e-9, "raw's need with the pool at 600")
	t.ok(s.view_vei()["fronts_met"] == 0, "and nothing is met")


## `assigned` is the echo (the uids whose front is that id, in view_big_undead's order), unchanged; `counted` is the uids
## VeiFronts counted. B (unassigned, top stat presence) is counted on swarm and assigned nowhere; A and C are in both
## on their fronts; D (crypt) in neither. Assigning B moves it; unassigning puts it back on swarm's count.
func _counted() -> void:
	var k := _known()
	var s: GameState = k[0]
	var u: Array = k[1]
	var fr: Array = s.view_vei()["fronts"]
	var echo := func(id: String) -> Array:
		return s.view_big_undead()["big_undead"].filter(func(b): return b["front"] == id).map(func(b): return b["uid"])
	for f in fr:
		t.ok(f["assigned"] == echo.call(f["id"]), "%s: assigned %s is cmd_assign_front's echo" % [f["id"], str(f["assigned"])])
	t.ok(fr.map(func(f): return f["assigned"]) == [[u[0]], [], [], [u[2]]], "assigned: A on giants, C on raw, nothing else")
	t.ok(fr.map(func(f): return f["counted"]) == [[u[0]], [u[1]], [], [u[2]]],
		"counted: A on giants, B (unassigned) on swarm by its presence, C on raw: %s" % str(fr.map(func(f): return f["counted"])))
	t.ok(not fr.any(func(f): return f["assigned"].has(u[1])) and fr[1]["counted"].has(u[1]), "B is in swarm's counted and in no assigned")
	t.ok(not fr.any(func(f): return f["counted"].has(u[3]) or f["assigned"].has(u[3])), "D, in the crypt, counts nowhere")
	var have0 := float(fr[2]["have"])
	t.ok(s.cmd_assign_front(u[1], "carvers")["ok"], "(setup) B to carvers")
	var f2: Array = s.view_vei()["fronts"]
	t.ok(f2[2]["assigned"] == [u[1]] and f2[2]["counted"] == [u[1]] and f2[1]["counted"] == [],
		"assigned, B is in carvers' assigned and counted, and off swarm's count")
	t.near(float(f2[2]["have"]), have0 + 1.0, 1e-9, "carvers' have gains B's beef (1)")
	t.ok(s.cmd_assign_front(u[1], "")["ok"] and s.view_vei()["fronts"][1]["counted"] == [u[1]]
		and s.view_vei()["fronts"].all(func(f): return not f["assigned"].has(u[1])), "unassigned again, B is back on swarm's count only")
	var errs: Array = []
	ApiSchema.check(s.view_vei(), ApiSchema.VIEWS["view_vei"], "view_vei", errs)
	t.ok(errs.is_empty(), "view_vei with counted is in the contract: %s" % str(errs))


## The boss seed's fronts: §7.2's shape exactly (no cleared, no counted), view_vei's need and have at issue (one unit per
## front here, so the sums are the same), assigned the echo; Results.validate and the schema take the seed.
func _seed() -> void:
	var k := _known()
	var s: GameState = k[0]
	s.cmd_debug_set_state({"relish_at": "vei"})
	var vf: Array = s.view_vei()["fronts"]
	var bb := s.cmd_begin_boss()
	t.ok(bb["ok"], "(setup) the boss run opens")
	var fr: Array = bb["seed"]["fronts"]
	t.ok(fr.all(func(f): return f.keys() == ["id", "need", "have", "assigned"]), "the seed's fronts keep §7.2's keys, {id, need, have, assigned}: %s" % str(fr[0].keys()))
	for i in fr.size():
		t.ok(fr[i]["id"] == vf[i]["id"] and fr[i]["need"] == vf[i]["need"] and fr[i]["have"] == vf[i]["have"] and fr[i]["assigned"] == vf[i]["assigned"],
			"%s: the seed carries view_vei's live need %.4f and have %.4f, assigned the echo %s" % [fr[i]["id"], fr[i]["need"], fr[i]["have"], str(fr[i]["assigned"])])
	t.ok(fr.any(func(f): return float(f["need"]) > 0.0), "the seed's fronts are not all zero, so the fight takes them as they are")
	var errs: Array = []
	ApiSchema.check(bb["seed"], ApiSchema.BOSS_SEED, "boss_seed", errs)
	t.ok(Results.validate("boss_seed", bb["seed"]) == [] and errs.is_empty(), "Results.validate and the schema take the seed: %s %s" % [str(Results.validate("boss_seed", bb["seed"])), str(errs)])
	t.ok(s.view_boss_seed() == bb["seed"], "view_boss_seed is the seed as issued")


## The config the fight reads (ConfigDb.data["vei"]) is the one GameState reads: GameState keeps the Dictionary it is
## set up with (no copy; Game._ready calls state.setup(ConfigDb.data)), and ConfigDb's reload reads the same files as
## TestUtil.configs() (both GameState.load_configs("res://configs")).
func _config_source() -> void:
	var cd := _configdb_data()
	var s := GameState.new(cd)
	t.ok(is_same(s._cfgs, cd) and is_same(s._cfgs["vei"], cd["vei"]), "setup keeps ConfigDb's Dictionary itself, so _cfgs[\"vei\"] is ConfigDb.data[\"vei\"]")
	t.ok(cd.has("vei") and cd["vei"] == TestUtil.configs()["vei"], "ConfigDb's reload and TestUtil.configs() read the same vei.json")


## The gate: the seed's need and have are exactly the fight's recompute from the seed with ConfigDb's vei.
func _gate() -> void:
	var vc: Dictionary = _configdb_data().get("vei", {})
	for fx in ["pre_vei", "midgame_2flips", "pre_vei/u1 unassigned"]:
		var s := _fixture(fx.get_slice("/", 0))
		if fx.ends_with("unassigned"):
			t.ok(s.cmd_assign_front("u1", "")["ok"], "(setup) u1 leaves its front")
			var vf: Array = s.view_vei()["fronts"]
			t.ok(vf[1]["assigned"] == ["u2"] and vf[1]["counted"] == ["u1", "u2"] and vf[0]["counted"] == [],
				"pre_vei, u1 unassigned: swarm's counted %s (u1 by its presence) against its assigned %s" % [str(vf[1]["counted"]), str(vf[1]["assigned"])])
		if s.view_relish()["state"] != "at_vei":
			s.cmd_debug_set_state({"relish_at": "vei"})
		var bb := s.cmd_begin_boss()
		t.ok(bb["ok"], "(setup) %s: the boss run opens (%s)" % [fx, bb["reason"]])
		var sd: Dictionary = bb["seed"]
		var hn := VeiFronts.have_need(VeiFronts.info_from_boss_seed(sd), vc)
		t.ok(sd["fronts"].map(func(f): return f["id"]) == GameState.FRONT_IDS and hn.map(func(f): return f["id"]) == VeiFronts.FRONT_IDS,
			"%s: the seed's fronts in FRONT_IDS order" % fx)
		var exact := true
		var shown: Array = []
		for i in hn.size():
			exact = exact and sd["fronts"][i]["need"] == hn[i]["need"] and sd["fronts"][i]["have"] == hn[i]["have"]
			shown.append("%s %.4f/%.4f" % [sd["fronts"][i]["id"], sd["fronts"][i]["have"], sd["fronts"][i]["need"]])
		t.ok(exact, "%s: the seed's need and have are exactly VeiFronts.have_need(info_from_boss_seed(seed), ConfigDb's vei): %s" % [fx, ", ".join(shown)])
		t.ok(sd["fronts"].any(func(f): return float(f["need"]) > 0.0 or float(f["have"]) > 0.0), "%s: live (not all zero)" % fx)


## pre_vei's boss seed differs from E3-3's only by the fronts' live need and have: zeroing them gives E3-3's seed.
## Built as test_api_v6 builds it (a new game, seed 1, then the fixture: its seed_rev is that state's rev).
func _seed_otherwise_unchanged() -> void:
	var s := _mk()
	t.ok(s.cmd_debug_load_fixture("pre_vei")["ok"], "(setup) pre_vei loads over a new game")
	var bs: Dictionary = s.cmd_begin_boss()["seed"].duplicate(true)
	for e in bs["party"]:
		e.erase("filled_slots")
	var live := JSON.stringify(bs).sha256_text()
	for f in bs["fronts"]:
		f["need"] = 0.0
		f["have"] = 0.0
	t.ok(JSON.stringify(bs).sha256_text() == PRE_VEI_ZEROED_SHA,
		"pre_vei's boss seed with its fronts zeroed is E3-3's (%s); live, it hashes %s" % [PRE_VEI_ZEROED_SHA.left(16), live])


## Boss step 3: one relish_died in place per spent backup, phylactery charges first, then clones, after vei_result.
## pre_vei with two charges and two clones ready (vats 0 and 1 full); a win that spent 2 charges and 1 clone.
func _backups_in_place() -> void:
	var s := _fixture("pre_vei")
	s._phylactery_charges = 2
	s.vats_grow = [1.0, 1.0]
	var bb := s.cmd_begin_boss()
	var sd: Dictionary = bb["seed"]
	t.ok(bb["ok"] and sd["phylactery_charges"] == 2 and sd["clones_ready"] == 2, "(setup) the seed carries 2 charges and 2 clones")
	s.drain_events()
	var rid: int = sd["run_id"]
	var res := {"v": 2, "run_id": rid, "seed_rev": sd["seed_rev"], "won": true, "fronts_cleared": ["giants", "swarm", "raw"],
		"relish_deaths": 3, "backups_spent": {"phylactery": 2, "clones": 1}, "party_lost": [], "backlog_spent": 0.0}
	t.ok(s.apply_result("boss", res)["ok"], "(setup) the won fight applies")
	var evs := s.drain_events()
	var died := func(outcome: String) -> Dictionary:
		return {"type": "relish_died", "t": s.t, "outcome": outcome, "in_place": true, "at": "vei", "run_id": rid, "respawn_s": 0.0}
	t.ok(evs.map(func(e): return e["type"]) == ["vei_result", "relish_died", "relish_died", "relish_died"],
		"vei_result, then one relish_died per spent backup: %s" % str(evs.map(func(e): return e["type"])))
	t.ok(evs.slice(1) == [died.call("phylactery"), died.call("phylactery"), died.call("clone")],
		"in place at Vei, respawn 0: the two charges first, then the clone: %s" % str(evs.slice(1)))
	t.ok(s.view_relish()["state"] == "at_vei" and s._phylactery_charges == 0 and s.clones_ready == 1 and s.vats_grow == [0.0, 1.0],
		"she stays at Vei; the charges spent, the lowest ready vat emptied")
	# a fight that spent nothing raises none
	var n := _fixture("pre_vei")
	var nb := n.cmd_begin_boss()
	n.drain_events()
	n.apply_result("boss", {"v": 2, "run_id": nb["run_id"], "seed_rev": nb["seed_rev"], "won": true, "fronts_cleared": [],
		"relish_deaths": 0, "backups_spent": {"phylactery": 0, "clones": 0}, "party_lost": [], "backlog_spent": 0.0})
	t.ok(n.drain_events().map(func(e): return e["type"]) == ["vei_result"], "no backup spent: vei_result alone")


## A clone that grows while the fight runs (the sim ticks on; a tended vat fills) isn't the fight's backup: the seed
## said death_ends unmade, so a final death is unmade (600 s, the morale shock) and the new clone stays in its vat.
func _final_death_vat_filled() -> void:
	var s := _fixture("pre_vei")
	var bb := s.cmd_begin_boss()
	var sd: Dictionary = bb["seed"]
	t.ok(sd["death_ends"]["outcome"] == "unmade" and sd["clones_ready"] == 1, "(setup) the seed promises unmade with 1 clone")
	s.cmd_staff_vat(1, true)
	s.vats_grow = [1.0, 0.9999]
	for i in 8:
		s.tick(0.5)
	t.ok(s.vats_grow[1] >= 1.0 and s.clones_ready == 2, "(setup) a vat filled mid-fight: clones_ready %d, vats %s" % [s.clones_ready, str(s.vats_grow)])
	s.drain_events()
	var shock0: float = s.town_sim.shock
	var res := {"v": 2, "run_id": sd["run_id"], "seed_rev": sd["seed_rev"], "won": false, "fronts_cleared": [],
		"relish_deaths": 3, "backups_spent": {"phylactery": 1, "clones": 1}, "party_lost": [], "backlog_spent": 0.0}
	t.ok(s.apply_result("boss", res)["ok"], "(setup) the lost fight applies")
	var died: Array = s.drain_events().filter(func(e): return e["type"] == "relish_died" and not e["in_place"])
	t.ok(died.size() == 1 and died[0]["outcome"] == "unmade" and died[0]["respawn_s"] == 600.0,
		"the final death is the seed's unmade, 600 s, not a wake from the clone grown mid-fight: %s" % str(died))
	t.ok(s.town_sim.shock > shock0 and s.view_relish()["dead_s_left"] == 600.0 and not s.relish["respawn_with_clone"],
		"the town takes the morale shock (%.3f to %.3f) and she is dead for 600 s" % [shock0, s.town_sim.shock])
	t.ok(s.clones_ready == 1, "the clone grown in the fight is still ready: clones_ready %d" % s.clones_ready)


## Boss step 4: a final death after every backup (pre_vei: 1 charge, 1 clone, both spent, deaths = s + 1) follows the
## shared death rule with no clone left: unmade, backups.unmade_respawn_s (600 s), dead at Vei, after the in-place events.
func _final_death() -> void:
	var s := _fixture("pre_vei")
	var bb := s.cmd_begin_boss()
	var sd: Dictionary = bb["seed"]
	t.ok(sd["phylactery_charges"] == 1 and sd["clones_ready"] == 1 and sd["death_ends"] == {"outcome": "unmade", "respawn_s": 600.0},
		"(setup) pre_vei's seed: 1 charge, 1 clone, death_ends unmade 600 s")
	s.drain_events()
	var rid: int = sd["run_id"]
	var res := {"v": 2, "run_id": rid, "seed_rev": sd["seed_rev"], "won": false, "fronts_cleared": [],
		"relish_deaths": 3, "backups_spent": {"phylactery": 1, "clones": 1}, "party_lost": [], "backlog_spent": 0.0}
	t.ok(s.apply_result("boss", res)["ok"], "(setup) the lost fight applies")
	var evs := s.drain_events()
	var unmade_s := float(TestUtil.configs()["backups"]["backups"]["unmade_respawn_s"])
	t.ok(evs.map(func(e): return [e["type"], e.get("outcome", ""), e.get("in_place", null)]) == [["vei_result", "", null],
		["relish_died", "phylactery", true], ["relish_died", "clone", true], ["relish_died", "unmade", false]],
		"vei_result, the charge and the clone in place, then the final death: %s" % str(evs.map(func(e): return [e["type"], e.get("outcome", "")])))
	t.ok(evs[3] == {"type": "relish_died", "t": s.t, "outcome": "unmade", "in_place": false, "at": "vei", "run_id": rid, "respawn_s": unmade_s}
		and unmade_s == 600.0, "the final death: unmade at Vei, respawn %.0f s (backups.unmade_respawn_s)" % unmade_s)
	t.ok(s.view_relish()["state"] == "dead" and s.view_relish()["dead_s_left"] == 600.0 and s.clones_ready == 0 and s._phylactery_charges == 0,
		"she is dead for 600 s with no backup left")
