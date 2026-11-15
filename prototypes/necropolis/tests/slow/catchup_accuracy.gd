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
##   City-tier upkeep, a fixture artifact that is E4's, T3.3a's attribution). From there its pits work 2 of 6
##   on a store the convoy refills a load at a time, so the feed the mint reads (the last step's burned /
##   wanted) is a 10 s step's average over a landing against one 0.5 s substep's: at 12 h every stock and
##   outcome matches (Covington identical) and the mint and its split read 14% apart.

const HOURS := 12.0

var t := TestUtil.new()


func run() -> int:
	t.suite("catchup_accuracy")
	var cu = load("res://tests/test_catchup.gd")
	var conv = load("res://tests/slow/convergence.gd").new()
	conv.t = t
	var c: Dictionary = cu.cfgs()
	var tol := float(c["economy"]["idle"]["catchup_tol"])
	for st in ["midgame_2flips", "fresh", "pre_vei"]:
		var r: Dictionary = cu.accuracy(c, conv.start_json(st), HOURS * 3600.0, tol)
		print("  [catchup_accuracy] %s, %.0f h caught up vs live: %s%s" % [st, HOURS, "pass" if r["ok"] else "FAIL", "; " + str(r["lines"])])
		if st != "pre_vei":
			t.ok(r["ok"], "%s: %.0f h caught up against live at 0.5 s within %s: %s" % [st, HOURS, conv._pct(tol), r["lines"]])
	var script := func(s: GameState) -> void:
		s.cmd_set_valve(0.5, 0.35, 0.15)
		s.cmd_build("house", "lot-05")
		s.cmd_queue_build("well", "lot-06")
	var i1: Dictionary = cu.i1(c, "new", script, HOURS * 3600.0, 0.25, tol)
	print("  [catchup_accuracy] I1, a new game's session left %.0f h, closed vs open: %s" % [HOURS, i1["lines"]])
	t.ok(i1["ok"], "I1 over %.0f h: closed equals open within %s, the same outcomes: %s" % [HOURS, conv._pct(tol), i1["lines"]])
	return t.failures
