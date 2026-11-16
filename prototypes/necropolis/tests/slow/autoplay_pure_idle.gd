extends RefCounted
## E3-6b, the autoplayer's `pure_idle` profile (tests/autoplay/autoplayer.gd; IDLE §8): one 20 min setup from a new game
## (the queue filled, the stances set, the valve at its default, no raids), then closed for 7 days (AUTOPLAY_DAYS=n, at
## most 7). The timeline is the catch-up's own events. tests/run.sh --slow --only=autoplay_pure_idle

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("pure_idle", t)
