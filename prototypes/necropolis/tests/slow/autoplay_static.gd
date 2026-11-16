extends RefCounted
## E3-6b, the autoplayer's `static` profile (tests/autoplay/autoplayer.gd; IDLE §8), a regression baseline: the sessions
## schedule with the fixed build list and no reorder, and one raid a session at the day's tier (days 1-2 t1, 3-4 t2, 5-6
## t3, 7-8 t4). 8 days (AUTOPLAY_DAYS=n sets it). tests/run.sh --slow --only=autoplay_static

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("static", t)
