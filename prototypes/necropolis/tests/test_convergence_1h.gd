extends RefCounted
## The convergence harness's short version (E2b T3.0; the full table is tests/slow/convergence.gd):
## 1 h with no input from the three start states, the core step at 0.5 s (reference) and at 15 s,
## field frozen. The ledger balances and nothing goes negative at either dt, and Vei's stocks and
## Covington's smooth ones (convergence.gd KEY) stay within IDLE's 2% at 15 s. The fort pools and
## bodies are printed, not asserted: they didn't converge in T3.0's measurement, and the cause is
## not yet measured (the candidates: the dispatch rules' edges, the convoy's choice of fort, the
## tithe surge's unbounded overfill; see the slow suite's attribution run).

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
	return c.t.failures
