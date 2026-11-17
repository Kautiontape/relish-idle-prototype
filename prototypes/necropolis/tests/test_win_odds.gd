extends RefCounted
## E4 step 9, the odds lever (the manager's 2026-11-17 13:44 ruling, option B; MECHANICS §3.5, STATE-API §5.14): the
## win odds a player reads, the boss seed's and Vei-ready's are odds.time_weight · age / (age + odds.time_s) +
## (1 − time_weight) · min(odds.backlog_cap, strain), strain = backlog / (backlog + K). Her tithe period, reship and
## one-wave need read the strain alone, and every view shows the one odds. time_weight 0 with backlog_cap 1 is the
## strain bit for bit (the revert proof every re-pin of this change was checked against). Headless, no autoloads.

var t: TestUtil
const W := 0.7
const T_S := 345600.0  # 4 days
const CAP := 0.8


func run() -> int:
	t = TestUtil.new()
	t.suite("win-odds")
	_formula()
	_views_agree()
	_fight_reads_strain()
	_sim_blind()
	_valve_projection()
	_away_line()
	return t.failures


## A new game with the odds block at (W, T_S, CAP), or `w`/`cap` given.
func _game(w := W, cap := CAP) -> GameState:
	var cfg := TestUtil.configs()
	cfg["realm"]["odds"]["time_weight"] = w
	cfg["realm"]["odds"]["time_s"] = T_S
	cfg["realm"]["odds"]["backlog_cap"] = cap
	var s := GameState.new(cfg)
	s.cmd_new_game(7)
	return s


func _formula() -> void:
	var f := func(age: float, s: float) -> float: return GameState.win_odds_of(age, s, W, T_S, CAP)
	t.near(f.call(0.0, 0.5), 0.3 * 0.5, 1e-15, "at age 0 only the backlog term: (1 − w) · strain")
	t.near(f.call(T_S, 0.0), 0.5 * W, 1e-15, "at age time_s the age term is half its weight")
	t.near(f.call(T_S, 0.95), 0.5 * W + 0.3 * CAP, 1e-15, "the backlog term stops at backlog_cap")
	t.ok(f.call(1e12, 0.99) < W + 0.3 * CAP + 1e-9 and f.call(1e12, 0.99) > W + 0.3 * CAP - 1e-6,
		"the odds tend to w + (1 − w) · cap, never above")
	var exact := true
	for s in [0.0, 1e-9, 0.123456789, 0.5, 0.6000000001, 0.987654321]:
		for age in [0.0, 3600.0, 518406.5, 1e9]:
			exact = exact and GameState.win_odds_of(age, s, 0.0, T_S, 1.0) == s
	t.ok(exact, "time_weight 0 with backlog_cap 1 gives the strain bit for bit, at any age (the revert proof)")
	t.ok(GameState.win_odds_of(-5.0, 0.4, W, T_S, CAP) == GameState.win_odds_of(0.0, 0.4, W, T_S, CAP), "a negative age reads as 0")


## view_vei, view_hud and the boss seed carry the same odds, win_odds at the game's age on RealmSim's strain; view_vei's
## strain is RealmSim's.
func _views_agree() -> void:
	var s := _game()
	s.t = 2.5 * 86400.0
	s.realm.vei["undead_queue"] = 0.9 * float(s._cfg()["K"])
	var v := s.view_vei()
	var want := GameState.win_odds_of(s.t, s.realm.strain(), W, T_S, CAP)
	t.ok(float(v["odds"]) == want and float(v["strain"]) == s.realm.strain(),
		"view_vei: odds %.6f = win_odds(t, strain), strain %.6f = RealmSim's" % [float(v["odds"]), float(v["strain"])])
	t.ok(float(s.view_hud()["odds"]) == want, "view_hud.odds is the same win odds")
	var sd := StateRuns.boss_seed_v2(s, 1, s.rev)
	t.ok(float(sd["odds"]) == want, "the boss seed's odds are the same win odds")
	t.ok(absf(want - float(v["strain"])) > 0.05, "(setup) at day 2.5 the win odds and the strain differ: %.3f against %.3f" % [want, float(v["strain"])])
	var s0 := _game(0.0, 1.0)
	s0.t = s.t
	s0.realm.vei["undead_queue"] = s.realm.vei["undead_queue"]
	t.ok(float(s0.view_vei()["odds"]) == s0.realm.strain(), "time_weight 0, cap 1: view_vei's odds are the strain")


## Her tithe period, reship and one-wave need read the strain, so the odds block moves none of them.
func _fight_reads_strain() -> void:
	var a := _game()
	var b := _game(0.0, 1.0)
	for s in [a, b]:
		s.t = 3.0 * 86400.0
		s.realm.vei["undead_queue"] = 1.4 * float(s._cfg()["K"])
	var f: Dictionary = a.realm.fort_by_id("ashgate")
	var g: Dictionary = b.realm.fort_by_id("ashgate")
	t.ok(a.realm.tithe_period() == b.realm.tithe_period() and a.realm.reship_rate(f) == b.realm.reship_rate(g)
		and a.realm.need_of(f, false, 0.0, false, 0.0, 1.2) == b.realm.need_of(g, false, 0.0, false, 0.0, 1.2),
		"the tithe period (%.2f s), reship and need are the same bits at time_weight 0.7 and 0" % a.realm.tithe_period())
	t.ok(float(a.view_vei()["odds"]) != float(b.view_vei()["odds"]), "(setup) while the odds differ: %.3f against %.3f" % [
		float(a.view_vei()["odds"]), float(b.view_vei()["odds"])])


## The step 9 review's item 3, end to end: nothing the sim steps reads the win odds. Two games, the odds block as shipped
## and at time_weight 0, cap 1 (the strain: 69542f2's revert proof, kept in the suite), from day 3 with a backlog, stepped
## an hour of live substeps: their saves (to_dict: the realm, the town, every stock, Vei's queues and clocks) are the same
## bits, while view_vei's odds differ.
func _sim_blind() -> void:
	var a := _game()
	var b := _game(0.0, 1.0)
	for s in [a, b]:
		s.t = 3.0 * 86400.0
		s.realm.vei["undead_queue"] = 1.4 * float(s._cfg()["K"])
		for i in 60:
			s.tick(60.0)  # (uncapped: 120 live substeps a call, no gap)
	t.ok(float(a.view_vei()["odds"]) != float(b.view_vei()["odds"]), "(setup) the odds differ after the hour: %.4f against %.4f" % [
		float(a.view_vei()["odds"]), float(b.view_vei()["odds"])])
	var ja := JSON.stringify(a.to_dict(), "", true)
	var jb := JSON.stringify(b.to_dict(), "", true)
	t.ok(ja == jb and a.t == b.t, "an hour of live play at time_weight 0.7 and at 0 saves the same state (%d chars, t %.1f)" % [ja.length(), a.t])
## "now" side is win_odds at age + the window on the same strain; without the odds block it is the strain, as before.
func _valve_projection() -> void:
	var s := _game()
	s.t = 1.5 * 86400.0
	s.realm.vei["undead_queue"] = 0.5 * float(s._cfg()["K"])
	var k := float(s._cfg()["K"])
	var window := float(MapLogic.cfg()["controls"]["drain_window_s"])
	var ocfg: Dictionary = s._cfg()["odds"]
	var o := ValveLogic.odds_at(float(s.realm.vei["undead_queue"]), 0.0, window, k, ocfg, s.t)
	t.ok(o == GameState.win_odds_of(s.t + window, s.realm.strain(), W, T_S, CAP), "a zero differential: win_odds at age + window")
	t.near(o, float(s.view_vei()["odds"]), 1e-3, "within a tenth of a point of view_vei's odds now (%.5f against %.5f)" % [o, float(s.view_vei()["odds"])])
	t.ok(ValveLogic.odds_at(float(s.realm.vei["undead_queue"]), 0.0, window, k) == s.realm.strain(), "without the odds block: the strain")
	var up := ValveLogic.odds_at(float(s.realm.vei["undead_queue"]), 1000.0, window, k, ocfg, s.t)
	t.ok(up > o, "a rising differential projects higher odds (%.5f against %.5f)" % [up, o])


## The away report's backlog line, "odds A → B": A the win odds at the away's start (its age and backlog), B view_vei's.
func _away_line() -> void:
	var s := _game()
	s.t = 86400.0
	s.realm.vei["undead_queue"] = 0.3 * float(s._cfg()["K"])
	var before := StateViews.away_before(s)
	var o0 := float(s.view_vei()["odds"])
	s.t += 8.0 * 3600.0
	s.realm.vei["undead_queue"] = 0.4 * float(s._cfg()["K"])
	var rep := StateViews.away_report(s, before, [], 8.0 * 3600.0, false)
	var line := ""
	for l in rep["gains"]:
		if str(l["text"]).contains(" · odds "):
			line = str(l["text"])
	var tail := line.get_slice(" · odds ", 1)
	t.ok(tail.get_slice(" → ", 0) == "%.2f" % o0 and tail.get_slice(" → ", 1) == "%.2f" % float(s.view_vei()["odds"]),
		"the backlog line's odds are the win odds at the start and now: %s (%.3f → %.3f)" % [line, o0, float(s.view_vei()["odds"])])
