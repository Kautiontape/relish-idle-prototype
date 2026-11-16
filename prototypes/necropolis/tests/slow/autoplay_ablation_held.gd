extends RefCounted
## E3-6b, ablation (a) under the autoplayer's sessions profile (tests/autoplay/autoplayer.gd; IDLE §8, BALANCE §2): never
## raid a held or refilled fort. It runs the sessions baseline alongside and prints the delta, in days to Vei-ready or in
## fronts and backlog at the end. 8 days (AUTOPLAY_DAYS=n sets it). tests/run.sh --slow --only=autoplay_ablation_held

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("ablation_held", t)
