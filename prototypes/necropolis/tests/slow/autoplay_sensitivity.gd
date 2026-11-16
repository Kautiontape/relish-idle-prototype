extends RefCounted
## E3-6b, the one sensitivity pass (tests/autoplay/autoplayer.gd; BALANCE §8): the sessions profile with the frozen bot's
## death rates (StandinResolver opts.deaths "frozen") in place of the typical human's. It runs the sessions baseline
## alongside and prints the delta. 8 days (AUTOPLAY_DAYS=n sets it). tests/run.sh --slow --only=autoplay_sensitivity

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("sensitivity", t)
