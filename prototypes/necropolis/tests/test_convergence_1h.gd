extends RefCounted
## The convergence harness's short version (E2b T3.0; the full table is tests/slow/convergence.gd):
## 1 h with no input from the three start states, the core step at 0.5 s (reference) and at 15 s,
## field frozen. The ledger balances and nothing goes negative at either dt, and Vei's stocks and
## Covington's smooth ones (convergence.gd KEY) stay within IDLE's 2% at 15 s. The fort pools and
## bodies are printed, not asserted: they didn't converge in T3.0's measurement, and the cause is
## not yet measured (the candidates: the dispatch rules' edges, the convoy's choice of fort, the
## tithe surge's overfill, unbounded then and bounded since T3.0s; see the slow suite's
## attribution run). Then the surge bound's regression: 12 h from midgame_2flips at 15 s, every
## fort's living within cap · (1 + tithe.overfill).

const DTS := [0.5, 15.0]
const KEY_TOL := 0.02


func run() -> int:
	var c = load("res://tests/slow/convergence.gd").new()
	c.t.suite("convergence_1h")
	var res: Dictionary = c.measure(c.STARTS, 1.0, DTS, true)
	print(c.table(res, 1.0))
	c.check(res)
	for st in res:
		var r: Dictionary = res[st][15.0]
		var w: float = c.worst(r, c.KEY)
		c.t.ok(w <= KEY_TOL, "%s at 15 s: Vei's and Covington's stocks within %.0f%% of 0.5 s over 1 h (worst %.3f%%)" % [
			st, KEY_TOL * 100.0, w * 100.0])
	# the surge bound's regression (E2b T3.0s): 12 h with no input from midgame_2flips once took Greywall
	# to about 850 × its cap. At 15 s (cheap; the bound holds at any dt, and the slow suites check it
	# at 0.125 to 30 s) no fort's living passes cap · (1 + tithe.overfill)
	var long: Dictionary = c.run_one(c.load_state(c.start_json("midgame_2flips")), 15.0, 43200.0, true)
	var over: Array = c.peaks_over(long["peak"])
	var parts: Array = []
	for id in long["peak"]:
		parts.append("%s %.2f" % [id, float(long["peak"][id][0]) / float(long["peak"][id][1])])
	print("  [convergence_1h] midgame_2flips, 12 h at 15 s: peak living / cap: " + ", ".join(PackedStringArray(parts)))
	c.t.ok(over.is_empty(), "midgame_2flips, 12 h at 15 s: every fort's living stays within cap · (1 + tithe.overfill)%s" % [
		"" if over.is_empty() else ": " + ", ".join(PackedStringArray(over))])
	return c.t.failures
