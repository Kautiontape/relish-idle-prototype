extends RefCounted
## Does the live model converge as dt → 0 (E2b T3.0s)? convergence.gd's measure() and table() at
## dt 0.125, 0.25 and 0.5 s against 0.125 s: 12 h with no input from its three starts, clipped as it
## clips, field frozen. Then each metric's ratio err(0.5) / err(0.25). Against a 0.125 s reference
## a first-order integrator gives (0.5 − 0.125) / (0.25 − 0.125) = 3, a second-order one
## (0.5² − 0.125²) / (0.25² − 0.125²) = 5; a ratio near 1 is an error that doesn't shrink with dt (a
## discontinuity). Only the ledger and the stocks' signs are asserted. Long: 0.125 s is 345 600 core
## steps per start. Also prints midgame_2flips' peak living per fort (the surge bound's regression:
## convergence.gd's check() asserts every fort stays within it). Run with
## tests/run.sh --slow --only=convergence_fine.

const DTS := [0.125, 0.25, 0.5]
const HOURS := 12.0
const TINY := 1e-6


func run() -> int:
	var c = load("res://tests/slow/convergence.gd").new()
	c.t.suite("convergence_fine")
	var res: Dictionary = c.measure(c.STARTS, HOURS, DTS, true)
	print(c.table(res, HOURS))
	print(ratios(c, res))
	print(c.peak_table(res, "midgame_2flips"))
	c.check(res)
	return c.t.failures


## Per start, each metric's err(dts[2]) / err(dts[1]): "≈0" when err(dts[1]) is below TINY (the
## ratio of two rounding errors means nothing).
static func ratios(c, res: Dictionary) -> String:
	var lines: Array = ["  [convergence_fine] err(%s s) / err(%s s), both vs %s s: 3 is first order, 5 second, near 1 an error that doesn't shrink; ≈0: err(%s s) below %s" % [
		str(DTS[2]), str(DTS[1]), str(DTS[0]), str(DTS[1]), String.num_scientific(TINY)],
		"  | start | " + " | ".join(PackedStringArray(c.METRICS.map(func(m): return c.SHORT[m]))) + " |",
		"  |" + "---|".repeat(c.METRICS.size() + 1)]
	for st in res:
		var cells: Array = []
		for m in c.METRICS:
			var a := float(res[st][DTS[1]]["err"][m])
			var b := float(res[st][DTS[2]]["err"][m])
			cells.append("≈0" if a < TINY else "%.2f" % (b / a))
		lines.append("  | %s | %s |" % [st, " | ".join(PackedStringArray(cells))])
	return "\n".join(PackedStringArray(lines))
