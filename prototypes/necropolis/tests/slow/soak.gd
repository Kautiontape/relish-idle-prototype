extends RefCounted
## The full ledger soak (MECHANICS §2.1, §10; tests/run.sh --slow --only=soak): 1 sim-hour of random
## valves, Relish's moves, raids and flips, a lost Vei fight, musters, builds and debug grants, through
## test_ledger.gd's soak(). The default suite runs the same soak for 10 sim-min.


func run() -> int:
	var suite = load("res://tests/test_ledger.gd").new()
	suite.t.suite("soak")
	suite.soak(3600.0, 23)
	return suite.t.failures
