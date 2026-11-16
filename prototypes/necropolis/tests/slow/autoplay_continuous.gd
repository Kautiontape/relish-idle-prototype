extends RefCounted
## E3-6b, the autoplayer's `continuous` profile (tests/autoplay/autoplayer.gd; IDLE §8): open and acting all the time,
## raids back to back, the queue always fed, until Vei-ready or 8 days (AUTOPLAY_DAYS=n sets it). All of it is live
## ticking, so it is the longest profile. tests/run.sh --slow --only=autoplay_continuous

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("continuous", t)
