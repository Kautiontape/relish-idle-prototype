extends RefCounted
## IDLE §4's accuracy test at 12 h (E2b-2 T3.3b; the default suite runs 2 h, tests/test_catchup.gd): a
## catch-up of 12 h (a load with the clock 12 h on, the real runner) against a live 0.5 s run of 12 h with
## no input, from the same save, within idle.catchup_tol (2%) on Vei's and Covington's stocks and the key
## rates, held forts ±1, Covington identical, the same outcomes, both ledgers balanced
## (test_catchup.gd's accuracy() and compare()). Then I1 over 12 h: a new game's scripted opening, then
## closed against open through the frame path. The field is shrunk (8 × 6) as in the default suite.
## Run with tests/run.sh --slow --only=catchup_accuracy (a few minutes).
## - Starts: midgame_2flips, fresh (convergence.gd's: a new game run 10 min) and pre_vei, asserted again from E4
##   step 10 (it was run and printed only until the window means landed). Its gold reaches its floor about 2.14 h in with no input (one Market against
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
## The 12 h pre_vei Grow-on case's window (_grow_on): test_catchup.WINDOWED and bone_net, over GROW_WINDOW_S. bone_net
## is a pulse train (0 with pulses of 0.6 around 0.15, a 6.7 s cycle at 7c4a8f8 with the ramp): its swing is 401% of its
## mean, so 600 s bounds the means' phase error at about 4.5%, over tol; 1 800 s bounds it at about 1.5%.
const GROW_WINDOWED := ["mint", "war", "flood", "worker_in", "bone_net"]
const GROW_WINDOW_S := 1800.0

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
		# pre_vei asserted again from E4 step 10 (handoff E4 item 10): with R1's shed order and the 600 s window means it
		# passes (b475eb3: every stock within 0.035%, the mint's 12 h endpoint 7.48% on its 8.5 s saw)
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
	_grow_on(c, conv, cu, tol)
	_trickle_30h(c)
	return t.failures


## Phase I P3 (the run's manager's ruling 1 on handoff 4: Grow acts during catch-up, so this check runs a Grow-on case;
## the starts above load with Grow off, as every pre-v14 save does): pre_vei with Grow turned on, 12 h caught up against
## live with the window means, and a new game with Grow on by default (test_catchup.grow_script: the default I1's valve and
## House, the bone store full), 12 h closed against open. Each: the same Grow starts in the same order (test_catchup.grow_same
## untimed, as compare() checks the builds), the worst gap printed. The default suite times them (its 2 h and 30 min cases);
## here the 12 h schedule's early coarse steps move the first minutes' town income: at 37c0c44 the new game's House L2
## started 30 s after live's, 4.5 min in, at the same 10 s core step as the 30 min case (5.4 s there), while every stock
## ended within 0.02% (likely the field's 12 h steps, idle.field_steps; not chased). pre_vei's worst was 39.8 s of 12 h.
## The new game's Grow starts run out once its bone is spent (no mill is built); pre_vei's run on through the 12 h.
## pre_vei runs at market.price ×2 (test_catchup.grow_price): its own gold net is negative, so Grow's upkeep test (the
## run's manager's ruling 1 on handoff 5) would pass over every pick until the town sheds.
## pre_vei's bone_net is judged on the window means too (the run's manager's ruling 3 on handoff 6; GROW_WINDOWED): with
## the doubled price Grow levels the Bone Mill, whose convoy-fed bone net saws, so its endpoint compares two phases (at
## 7c4a8f8 47.5% apart, every stock within 0.37% and the same 24 starts). Every stock keeps its endpoint check, and the
## other starts keep test_catchup.WINDOWED. The window's premise is asserted on the mint and bone_net as on the mint
## above, over GROW_WINDOW_S, with the means' phase-error bound within tol too.
func _grow_on(c: Dictionary, conv: Variant, cu: Variant, tol: float) -> void:
	var r: Dictionary = cu.accuracy(cu.grow_price(c), cu.grow_on_json(conv.start_json("pre_vei")), HOURS * 3600.0, tol, GROW_WINDOW_S,
		GROW_WINDOWED)
	for k in ["mint", "bone_net"]:
		var sw: Dictionary = r["window"]["saw"][k]
		var cyc := float(sw["cycle_s"])
		var bound := float(sw["swing"]) * cyc / GROW_WINDOW_S if is_finite(cyc) else 0.0
		t.ok(((cyc <= 0.1 * GROW_WINDOW_S and float(sw["cycle_s_cu"]) <= 0.1 * GROW_WINDOW_S) and bound <= tol) or float(sw["swing"]) <= tol,
			"pre_vei with Grow on: %s saws %s on a %.1f s cycle live (%.1f s caught up), well inside the %.0f s window: the means' phase error is at most about %s (within %s)" % [
			k, conv._pct(float(sw["swing"])), cyc, float(sw["cycle_s_cu"]), GROW_WINDOW_S, conv._pct(bound), conv._pct(tol)])
	var g: Array = r["grow_started"]
	var gd: String = cu.grow_same(g[0], g[1], tol, float(r["t0"]), INF)
	print("  [catchup_accuracy] pre_vei with Grow on, %.0f h caught up vs live: %s; Grow started %d caught up, %d live (%s; the worst %.3f s apart)" % [
		HOURS, "pass" if r["ok"] else "FAIL", (g[0] as Array).size(), (g[1] as Array).size(), gd if gd != "" else "same",
		cu.grow_worst_dt(g[0], g[1])])
	t.ok(r["ok"] and (g[1] as Array).size() >= 10 and gd == "",
		"pre_vei with Grow on: %.0f h caught up against live within %s and the same %d Grow starts (%s): %s" % [HOURS, conv._pct(tol),
		(g[1] as Array).size(), gd if gd != "" else "same", r["lines"]])
	var cg: Dictionary = cu.cfgs({"economy.stance.grow.default_on": true})
	var i1: Dictionary = cu.i1(cg, "new", func(s: GameState) -> void: cu.grow_script(s), HOURS * 3600.0, 0.25, tol)
	var gi: Array = i1["grow_started"]
	var gid: String = cu.grow_same(gi[0], gi[1], tol, float(i1["t0"]), INF)
	print("  [catchup_accuracy] I1 with Grow on, %.0f h closed vs open: %s; Grow started %d closed, %d open (%s; the worst %.3f s apart)" % [
		HOURS, i1["lines"], (gi[0] as Array).size(), (gi[1] as Array).size(), gid if gid != "" else "same",
		cu.grow_worst_dt(gi[0], gi[1])])
	t.ok(i1["ok"] and (gi[1] as Array).size() >= 3 and gid == "",  # (its 3: the bone store's worth, no mill)
		"I1 with Grow on over %.0f h: closed equals open within %s and the same %d Grow starts (%s): %s" % [HOURS, conv._pct(tol),
		(gi[1] as Array).size(), gid if gid != "" else "same", i1["lines"]])


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
