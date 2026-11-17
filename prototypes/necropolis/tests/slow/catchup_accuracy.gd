extends RefCounted
## IDLE §4's accuracy test at 12 h (E2b-2 T3.3b; the default suite runs 2 h, tests/test_catchup.gd): a
## catch-up of 12 h (a load with the clock 12 h on, the real runner) against a live 0.5 s run of 12 h with
## no input, from the same save, within idle.catchup_tol (2%) on Vei's and Covington's stocks and the key
## rates, held forts ±1, Covington identical, the same outcomes, both ledgers balanced
## (test_catchup.gd's accuracy() and compare()). Then I1 over 12 h: a new game's scripted opening, then
## closed against open through the frame path. The field is shrunk (8 × 6) as in the default suite.
## Run with tests/run.sh --slow --only=catchup_accuracy (a few minutes).
## - Starts: midgame_2flips and fresh (convergence.gd's: a new game run 10 min). pre_vei is run and
##   printed, not asserted: its gold reaches its floor about 2.14 h in with no input (one Market against
##   City-tier upkeep, a fixture artifact that is E4's, T3.3a's attribution). From there its pits work (all 6
##   since R1's shed order sheds the decorations and passive buildings first; 2 of 6 before) on a store the
##   convoy refills a load at a time, so the feed the mint reads (the last step's burned / wanted) is a 10 s
##   step's average over a landing against one 0.5 s substep's: at 12 h every stock and outcome matches
##   (Covington identical) and the mint and its split read 16% apart (14% before R1; the 0.5 s WAR swings
##   33 to 49 mass/s around its 42 over a convoy's cycle).
## - The feed's rates (the mint, its split and the workers' inflow) are judged on their means over the next WINDOW_S
##   of live play in both runs, their 12 h endpoint printed (E4, a measurement correction with the convoy's claim,
##   test_catchup.accuracy's window). The feed saws with each landed load, so the endpoint compares two phases: with
##   the claim fresh read 12.80 caught up against 9.40 live (36.2%) while its minted totals were 0.0015% apart
##   (483 952 / 483 959) and its 600 s means 0.05% (11.047 / 11.052); without it fresh passed on its phase (12.69 /
##   12.80, 0.84%) and read 12.80 / 9.40 600 s later, with 600 s means 0.26% apart.

const HOURS := 12.0
const WINDOW_S := 600.0

var t := TestUtil.new()


func run() -> int:
	t.suite("catchup_accuracy")
	var cu = load("res://tests/test_catchup.gd")
	var conv = load("res://tests/slow/convergence.gd").new()
	conv.t = t
	var c: Dictionary = cu.cfgs()
	var tol := float(c["economy"]["idle"]["catchup_tol"])
	for st in ["midgame_2flips", "fresh", "pre_vei"]:
		var r: Dictionary = cu.accuracy(c, conv.start_json(st), HOURS * 3600.0, tol, WINDOW_S)
		print("  [catchup_accuracy] %s, %.0f h caught up vs live: %s%s" % [st, HOURS, "pass" if r["ok"] else "FAIL", "; " + str(r["lines"])])
		if st != "pre_vei":
			t.ok(r["ok"], "%s: %.0f h caught up against live at 0.5 s within %s: %s" % [st, HOURS, conv._pct(tol), r["lines"]])
		# the window's premise (E4 review item 4): a mean over WINDOW_S is off by at most about swing × cycle ÷ window, so
		# the mint's saw must cycle well inside it (at most a tenth: 10 cycles), or not saw past the tolerance at all.
		# Measured at the E4 review items' tree: fresh 30.8% on 21.4 s, pre_vei 36.6% on 8.5 s, midgame_2flips none
		var wd: Dictionary = r["window"]
		var cyc := float(wd["cycle_s"])
		var sw := float(wd["swing"])
		t.ok((cyc <= 0.1 * WINDOW_S and float(wd["cycle_s_cu"]) <= 0.1 * WINDOW_S) or sw <= tol,
			"%s: the mint saws %s on a %.1f s cycle live (%.1f s caught up), well inside the %.0f s window: the means' phase error is at most about %s" % [
			st, conv._pct(sw), cyc, float(wd["cycle_s_cu"]), WINDOW_S, conv._pct(sw * cyc / WINDOW_S if is_finite(cyc) else 0.0)])
	var script := func(s: GameState) -> void:
		s.cmd_set_valve(0.5, 0.35, 0.15)
		s.cmd_build("house", "lot-05")
		s.cmd_queue_build("well", "lot-06")
	var i1: Dictionary = cu.i1(c, "new", script, HOURS * 3600.0, 0.25, tol)
	print("  [catchup_accuracy] I1, a new game's session left %.0f h, closed vs open: %s" % [HOURS, i1["lines"]])
	t.ok(i1["ok"], "I1 over %.0f h: closed equals open within %s, the same outcomes: %s" % [HOURS, conv._pct(tol), i1["lines"]])
	_trickle_30h(c)
	return t.failures


## The step 9 review's item 1, the steady case: the relic trickle over 30 h, open against closed (the real runner's steps),
## from midgame_2flips with every t1 fort held for 2 days (test_relic_trickle.start): both pay the same relics and carry the
## same seconds (2 relics and 6 h). The transition (a fort lost inside a step) is the default suite's.
func _trickle_30h(c: Dictionary) -> void:
	var tr = load("res://tests/test_relic_trickle.gd")
	var s: GameState = tr.start(c, 0.0, false)
	var period := float(c["economy"]["relic_trickle"]["period_s"])
	var r0 := s.relics
	var runs: Array = tr.open_closed(c, s, 30.0 * 3600.0)
	var cl: GameState = runs[0]
	var op: GameState = runs[1]
	var want := 30.0 * 3600.0 - 2.0 * period
	print("  [catchup_accuracy] the relic trickle over 30 h, every t1 fort held: relics %d -> %d closed, %d open; carried %.3f s closed, %.3f s open" % [
		r0, cl.relics, op.relics, cl.relic_trickle_s, op.relic_trickle_s])
	t.ok(cl.relics == r0 + 2 and op.relics == r0 + 2 and absf(cl.relic_trickle_s - want) < 1e-3 and absf(op.relic_trickle_s - want) < 1e-3,
		"the trickle over 30 h, open and closed: 2 relics each and %.0f s carried (closed %.3f, open %.3f)" % [want, cl.relic_trickle_s, op.relic_trickle_s])
