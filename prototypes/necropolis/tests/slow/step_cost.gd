extends RefCounted
## The core step's cost alone (tests/run.sh --slow --only=step_cost, a couple of minutes): the
## convergence harness's best-of-3 timing at every dt from the three start states, with the load
## average beside each, and the 12 h and 7 d projections (field ticks included). No accuracy runs.


func run() -> int:
	var c = load("res://tests/slow/convergence.gd").new()
	c.t.suite("step_cost")
	print("  [step_cost] load average: %s" % c._loadavg())
	var cost: Dictionary = c.timing(c.STARTS, c.DTS)
	print(c.cost_table(cost))
	c.t.ok(c.cost_us(cost, 0.5) > 0.0, "a core step costs something measurable (%.0f µs at 0.5 s)" % c.cost_us(cost, 0.5))
	return c.t.failures
