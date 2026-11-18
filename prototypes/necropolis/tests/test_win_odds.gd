extends RefCounted
## E4 step 9, the odds lever (the manager's 2026-11-17 13:44 ruling, option B; MECHANICS §3.5, STATE-API §5.14): the
## win odds a player reads, the boss seed's and Vei-ready's are odds.time_weight · age / (age + odds.time_s) +
## (1 − time_weight) · min(odds.backlog_cap, strain), strain = backlog / (backlog + K). Her tithe period, reship and
## one-wave need read the strain alone, and every view shows the one odds. time_weight 0 with backlog_cap 1 is the
## strain bit for bit (the revert proof every re-pin of this change was checked against). Headless, no autoloads.
## Phase I P3's odds split (the manager's ruling): that formula is now `readiness` (the bots' Vei-ready and the boss
## seed's odds), and view_vei/view_hud's `odds` are the first-attempt estimate on it and the backups (first_odds_of;
## _first_attempt). backups_mid -1e9 is the readiness bit for bit (the split's revert proof).

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
	_strain_label()
	_first_attempt()
	_away_backups()
	_raid_credit()
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


## view_vei, view_hud and the boss seed carry the same readiness, win_odds at the game's age on RealmSim's strain (the
## seed as its `odds`); view_vei's strain is RealmSim's, and both views' odds are first_odds on it and vei_backups.
func _views_agree() -> void:
	var s := _game()
	s.t = 2.5 * 86400.0
	s.realm.vei["undead_queue"] = 0.9 * float(s._cfg()["K"])
	var v := s.view_vei()
	var want := GameState.win_odds_of(s.t, s.realm.strain(), W, T_S, CAP)
	t.ok(float(v["readiness"]) == want and float(v["strain"]) == s.realm.strain(),
		"view_vei: readiness %.6f = win_odds(t, strain), strain %.6f = RealmSim's" % [float(v["readiness"]), float(v["strain"])])
	t.ok(float(s.view_hud()["readiness"]) == want, "view_hud.readiness is the same win odds")
	var sd := StateRuns.boss_seed_v2(s, 1, s.rev)
	t.ok(float(sd["odds"]) == want, "the boss seed's odds are the same win odds (the readiness, not view_vei's odds)")
	var first := s.first_odds(want, s.vei_backups())
	t.ok(float(v["odds"]) == first and float(s.view_hud()["odds"]) == first and int(v["backups"]) == s.vei_backups()
		and int(s.view_hud()["backups"]) == s.vei_backups(),
		"view_vei and view_hud: odds %.6f = first_odds(readiness, %d backups)" % [first, s.vei_backups()])
	t.ok(float(sd["odds"]) != float(v["odds"]), "(setup) the seed's odds and view_vei's differ: %.4f against %.4f" % [float(sd["odds"]), float(v["odds"])])
	t.ok(absf(want - float(v["strain"])) > 0.05, "(setup) at day 2.5 the win odds and the strain differ: %.3f against %.3f" % [want, float(v["strain"])])
	var s0 := _game(0.0, 1.0)
	s0.t = s.t
	s0.realm.vei["undead_queue"] = s.realm.vei["undead_queue"]
	t.ok(float(s0.view_vei()["readiness"]) == s0.realm.strain(), "time_weight 0, cap 1: view_vei's readiness is the strain")


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
	s._phylactery_charges = 1
	s.clones_ready = 8  # 1+8, so first_odds' backup factor is not near 0 (Phase I P3's odds split)
	var k := float(s._cfg()["K"])
	var window := float(MapLogic.cfg()["controls"]["drain_window_s"])
	var ocfg: Dictionary = s._cfg()["odds"]
	var o := ValveLogic.odds_at(float(s.realm.vei["undead_queue"]), 0.0, window, k, ocfg, s.t)
	t.ok(o == GameState.win_odds_of(s.t + window, s.realm.strain(), W, T_S, CAP), "a zero differential: win_odds at age + window")
	t.near(o, float(s.view_vei()["readiness"]), 1e-3, "within a tenth of a point of view_vei's readiness now (%.5f against %.5f)" % [o, float(s.view_vei()["readiness"])])
	# Phase I P3's odds split: the projection is the readiness; first_odds_of on it and today's backups is the odds a
	# player reads (view_vei's), which is how the valve can project the shown odds
	var ocf: Dictionary = s._cfg()["odds"]
	var po := GameState.first_odds_of(o, s.vei_backups(), float(ocf["backups_mid"]), float(ocf["backups_scale"]),
		float(ocf["first_gain"]), float(ocf["first_cap"]))
	t.near(po, float(s.view_vei()["odds"]), 1e-3, "first_odds_of on it: within a tenth of a point of view_vei's odds (%.5f against %.5f)" % [po, float(s.view_vei()["odds"])])
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
		if str(l["text"]).contains(" · your odds "):
			line = str(l["text"])
	var tail := line.get_slice(" · your odds ", 1)
	# whole percents, as the top bar's YOUR ODDS (the V-I1 round)
	t.ok(tail.get_slice(" → ", 0) == "%d%%" % roundi(o0 * 100.0) and tail.get_slice(" → ", 1) == "%d%%" % roundi(float(s.view_vei()["odds"]) * 100.0),
		"the backlog line's odds are the win odds at the start and now: %s (%.3f → %.3f)" % [line, o0, float(s.view_vei()["odds"])])


## The ▲/▼ is the backlog's sign (the differential's EMA), while the odds are mostly time and climb on a ▼, so wherever the
## map shows it with the odds it is labelled as the strain and never follows the percent (E4 step 10, the step 9 review's
## item 4; the run's manager's 2026-11-17 16:40 ruling): the top bar's STRAIN label before the glyph, Vei's node "61%"
## over "strain ▲ · drain …", the card's row, the pinned odds and the BEGIN dialog. Before this they read "61% ▲ gaining".
func _strain_label() -> void:
	t.suite("win-odds-strain-label")
	var words := {1: "strain ▲ rising", 0: "strain holding", -1: "strain ▼ falling"}
	for sg in [1, 0, -1]:
		var ro := {"odds": 0.61, "sign": sg, "drain_s": 520.0, "backlog": 18000.0}
		var pin := CardLogic.pinned_odds(ro)
		var conf := CardLogic.confirm_text(ro)
		t.ok(pin == "Your odds 61%% · %s · drains in 8m 40s" % words[sg], "sign %d: the pinned odds (%s)" % [sg, pin])
		t.ok(conf.contains("Odds 61%% · %s · drains in 8m 40s" % words[sg]), "sign %d: the BEGIN dialog (%s)" % [sg, conf.replace("\n", " / ")])
		for txt in [pin, conf]:
			t.ok(not txt.contains("% ▲") and not txt.contains("% ▼") and not txt.contains("%▲") and not txt.contains("%▼"),
				"sign %d: no glyph right after the percent (%s)" % [sg, str(txt).replace("\n", " / ")])
	t.ok(NodeLogic.strain_line(1, 18000.0, 520.0) == "strain ▲ · drain 8m 40s" and NodeLogic.strain_line(-1, 18000.0, -1.0) == "strain ▼ · drain ∞"
		and NodeLogic.strain_line(0, 0.0, -1.0) == "strain holding · queue empty",
		"Vei's node: the line under the odds (%s)" % NodeLogic.strain_line(1, 18000.0, 520.0))
	var vei_src := FileAccess.get_file_as_string("res://scripts/map/map_vei.gd")
	t.ok(vei_src.contains("NodeLogic.strain_line(") and not vei_src.contains("MapLogic.sign_glyph("), "Vei's node draws the odds alone and the glyph on the strain line")
	# A source-order check, accepted as is (the E4 final review's item 4; the run's manager's 2026-11-17 20:20 ruling 9): it
	# fails if the order is edited, and would pass a label built but never added, or hidden. Building the real bar
	# headless was tried (MapHud.new() then _build_bar([]), which needs no tree): map_hud.gd doesn't compile under the
	# --script runner ("Identifier not found: Game", the autoload its _ready connects to), so the suite can't load it.
	# The bar's screenshots (reports/economy/e4-strain-label-*.png) are the visual check
	var hud_src := FileAccess.get_file_as_string("res://scripts/map/map_hud.gd")
	var at_odds := hud_src.find("_odds = _bar_label(")
	var at_label := hud_src.find("cfg[\"strain_label\"]")
	var at_sign := hud_src.find("_sign = _bar_label(")
	t.ok(at_odds >= 0 and at_odds < at_label and at_label < at_sign, "the top bar puts the STRAIN label between the odds and the glyph")
	t.ok(str(MapLogic.cfg()["strain_label"]) == "STRAIN", "the top bar's label reads STRAIN")
	var sl := str(MapLogic.cfg()["cards"]["vei_sign_label"])
	t.ok(sl.begins_with("STRAIN") and not sl.contains("winning"), "the Vei card's row is the strain's, not 'winning' (%s)" % sl)


## Phase I P3's odds split (the manager's ruling; realm.json odds.backups_mid, backups_scale) with P3b's honest ceiling
## (V-I2 (b); odds.first_gain, first_cap): the odds a player reads are first_odds_of(readiness, backups) =
## min(first_cap, first_gain × readiness) / (1 + exp(-(backups - mid) / scale)), fit to P3's faithful grade at sessions'
## Vei-ready (180121f's sessions seed 1 at day 5.1667, score 65, readiness 0.6053): its own 1+10 won 16/20, 1+6 9/20, 1+4
## 5/20, 1+2 1/20, 0+0 0/20. Within five points of each, and the 1+10 point reads its 80% (P3's form, the readiness as the
## ceiling, read 0.60 there); rising in the backups, never falling with the readiness, never above the ceiling or
## first_cap. Revert proofs: first_gain 1 with first_cap 1 is P3's form bit for bit (readiness / (1 + exp(...)), at P3's
## 5.57 and 1.24), so 1+10 reads 0.60 again; backups_mid -1e9 is the ceiling bit for bit. Backups count the revives a run
## may use (min(charges, max_per_dungeon)) and the clones ready.
func _first_attempt() -> void:
	t.suite("win-odds-first")
	var ocf: Dictionary = TestUtil.configs()["realm"]["odds"]
	var mid := float(ocf["backups_mid"])
	var sc := float(ocf["backups_scale"])
	var gain := float(ocf["first_gain"])
	var cap := float(ocf["first_cap"])
	var r := 0.6053
	var grade := {11: 0.80, 7: 0.45, 5: 0.25, 3: 0.05, 0: 0.0}
	var fit := []
	var within := true
	for n in grade:
		var o := GameState.first_odds_of(r, int(n), mid, sc, gain, cap)
		fit.append("%d: %.3f (%.2f)" % [n, o, float(grade[n])])
		within = within and absf(o - float(grade[n])) <= 0.05
	t.ok(within, "at readiness 0.6053 the odds are within five points of P3's grade, 1+10 included: %s" % ", ".join(fit))
	var old := GameState.first_odds_of(r, 11, 5.57, 1.24, 1.0, 1.0)
	t.ok(absf(old - 0.598) < 0.005 and old == r / (1.0 + exp(-(11.0 - 5.57) / 1.24)) and old == GameState.first_odds_of(r, 11, 5.57, 1.24),
		"first_gain 1 and first_cap 1 (the defaults): P3's form bit for bit, 1+10 at %.3f (the revert proof)" % old)
	var rising := true
	var capped := true
	for n in range(0, 21):
		for rr in [0.1, 0.4, 0.6118, 0.9]:
			var o := GameState.first_odds_of(rr, n, mid, sc, gain, cap)
			rising = rising and o > GameState.first_odds_of(rr, n - 1, mid, sc, gain, cap) and o >= GameState.first_odds_of(rr - 0.05, n, mid, sc, gain, cap)
			capped = capped and o >= 0.0 and o <= minf(cap, gain * rr) and o < 0.95 + 1e-12
	t.ok(rising and capped, "the odds rise with each backup, never fall with the readiness, and never pass min(first_cap, first_gain × readiness) (0..20 backups)")
	var exact := true
	for rr in [0.0, 0.123456789, 0.6118, 0.94]:
		for n in [0, 3, 9]:
			exact = exact and GameState.first_odds_of(rr, n, -1e9, sc, gain, cap) == minf(cap, gain * rr)
	t.ok(exact, "backups_mid -1e9: the odds are the ceiling bit for bit")
	t.ok(GameState.first_odds_of(0.5, 7, 7.0, 0.0) == 0.5 and GameState.first_odds_of(0.5, 6, 7.0, 0.0) == 0.0, "scale 0: a step at mid")
	var s := _game()
	s._phylactery_charges = 3
	s.clones_ready = 8
	var pmax := int(s._phylactery_max())
	t.ok(s.vei_backups() == mini(3, pmax) + 8 and pmax == int(TestUtil.configs()["backups"]["phylactery"]["max_per_dungeon"]),
		"backups: min(3 charges, max_per_dungeon %d) + 8 clones = %d" % [pmax, s.vei_backups()])
	s.t = 6.0 * 86400.0
	s.realm.vei["undead_queue"] = 1.7 * float(s._cfg()["K"])
	var v := s.view_vei()
	t.ok(float(v["odds"]) == GameState.first_odds_of(float(v["readiness"]), s.vei_backups(), mid, sc, gain, cap) and int(v["backups"]) == s.vei_backups(),
		"view_vei at day 6 with %d backups: odds %.4f on readiness %.4f" % [s.vei_backups(), float(v["odds"]), float(v["readiness"])])
	s.clones_ready = 0
	s._phylactery_charges = 0
	t.ok(float(s.view_vei()["odds"]) < 0.05 * float(s.view_vei()["readiness"]), "and with none, under a twentieth of it (%.4f)" % float(s.view_vei()["odds"]))
	# the bots' Vei-ready reads the readiness, never the first-attempt odds (the ruling: the old formula drives it)
	var src := FileAccess.get_file_as_string("res://tests/autoplay/autoplayer.gd")
	t.ok(src.contains("float(v[\"readiness\"]) < VEI_READY_ODDS") and src.contains("float(v2[\"readiness\"]) >= VEI_READY_ODDS")
		and not src.contains("[\"odds\"]) < VEI_READY_ODDS") and not src.contains("[\"odds\"]) >= VEI_READY_ODDS"),
		"the autoplayer's Vei-ready (both checks) reads view_vei's readiness")


## The away report's "odds A → B" reads the backups at the away's start for A (away_before's backups), not today's: a
## catch-up that spends clones shows the odds it started on.
func _away_backups() -> void:
	var s := _game()
	s.t = 4.0 * 86400.0
	s.realm.vei["undead_queue"] = 1.0 * float(s._cfg()["K"])
	s._phylactery_charges = 1
	s.clones_ready = 8
	var before := StateViews.away_before(s)
	var o0 := float(s.view_vei()["odds"])
	t.ok(int(before["backups"]) == 9, "away_before keeps the backups (%d)" % int(before["backups"]))
	s.t += 8.0 * 3600.0
	s.clones_ready = 0
	var rep := StateViews.away_report(s, before, [], 8.0 * 3600.0, false)
	var line := ""
	for l in rep["gains"]:
		if str(l["text"]).contains(" · your odds "):
			line = str(l["text"])
	var tail := line.get_slice(" · your odds ", 1)
	var o1 := float(s.view_vei()["odds"])
	t.ok(roundi(o0 * 100.0) != roundi(o1 * 100.0), "(setup) the odds at the start and now differ as printed: %.3f against %.3f" % [o0, o1])
	t.ok(tail.get_slice(" → ", 0) == "%d%%" % roundi(o0 * 100.0) and tail.get_slice(" → ", 1) == "%d%%" % roundi(o1 * 100.0),
		"A is the odds on the start's 9 backups, B on today's 1: %s (%.3f → %.3f)" % [line, o0, o1])


## P3b (V-I2 (a), the active nudge; realm.json odds.raid_credit, raid_credit_cap): the readiness's strain term takes
## min(raid_credit_cap, raid_credit × raids finished), GameState.raid_credit. A game at day 3 with Vei's strain at 0.5:
## no raids, no credit; 50 raids lift the readiness by exactly (1 − w) × 50 × raid_credit and nothing else (the strain,
## the tithe period, reship and the one-wave need are the same bits); 10 000 raids are held at the cap; the credit
## rides stats.raids through a save; view_vei carries it and the valve's projection reads it (within a tenth of a
## point of view_vei's readiness). Revert proof: raid_credit 0, the readiness is win_odds_of without it bit for bit.
func _raid_credit() -> void:
	t.suite("win-odds-credit")
	var ocf: Dictionary = TestUtil.configs()["realm"]["odds"]
	var per := float(ocf["raid_credit"])
	var top := float(ocf["raid_credit_cap"])
	var s := _game()
	s.t = 3.0 * 86400.0
	s.realm.vei["undead_queue"] = float(s._cfg()["K"])  # strain 0.5
	var r0 := float(s.view_vei()["readiness"])
	var st0 := s.realm.strain()
	var per0 := s.realm.tithe_period()
	t.ok(s.raid_credit() == 0.0 and r0 == GameState.win_odds_of(s.t, st0, W, T_S, CAP), "no raids: no credit, the readiness as before (%.5f)" % r0)
	s.stats["raids"] = 50
	var v := s.view_vei()
	var r1 := float(v["readiness"])
	t.ok(per > 0.0 and absf(r1 - r0 - (1.0 - W) * 50.0 * per) < 1e-12 and float(v["raid_credit"]) == 50.0 * per,
		"50 raids: the readiness up by (1 - w) x 50 x %.5f = %.5f (%.5f -> %.5f)" % [per, (1.0 - W) * 50.0 * per, r0, r1])
	t.ok(s.realm.strain() == st0 and s.realm.tithe_period() == per0 and float(v["strain"]) == st0,
		"and only the readiness: the strain and the tithe period are the same bits")
	s.stats["raids"] = 10000
	t.ok(s.raid_credit() == top and absf(float(s.view_vei()["readiness"]) - GameState.win_odds_of(s.t, st0 + top, W, T_S, CAP)) < 1e-12,
		"10 000 raids: held at raid_credit_cap %.3f" % top)
	s.stats["raids"] = 50
	var n := GameState.new(s._cfgs)
	t.ok(n.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))["ok"] and n.raid_credit() == s.raid_credit()
		and float(n.view_vei()["readiness"]) == r1, "a save keeps it (stats.raids): readiness %.5f" % float(n.view_vei()["readiness"]))
	var k := float(s._cfg()["K"])
	var window := float(MapLogic.cfg()["controls"]["drain_window_s"])
	var o := ValveLogic.odds_at(float(s.realm.vei["undead_queue"]), 0.0, window, k, s._cfg()["odds"], s.t, float(v["raid_credit"]))
	t.near(o, r1, 1e-3, "the valve's projection with view_vei's raid_credit: within a tenth of a point of its readiness (%.5f against %.5f)" % [o, r1])
	var cfg := TestUtil.configs()
	cfg["realm"]["odds"]["raid_credit"] = 0.0
	var z := GameState.new(cfg)
	z.cmd_new_game(7)
	z.t = 3.0 * 86400.0
	z.realm.vei["undead_queue"] = float(z._cfg()["K"])
	z.stats["raids"] = 50
	var ocz: Dictionary = cfg["realm"]["odds"]
	t.ok(float(z.view_vei()["readiness"]) == GameState.win_odds_of(z.t, z.realm.strain(), float(ocz["time_weight"]), float(ocz["time_s"]), float(ocz["backlog_cap"])),
		"raid_credit 0: the readiness is win_odds_of without the credit bit for bit (the revert proof)")
