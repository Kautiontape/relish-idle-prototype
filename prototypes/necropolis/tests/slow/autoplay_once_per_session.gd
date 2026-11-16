extends RefCounted
## E3-6b, the autoplayer's `once_per_session` profile (tests/autoplay/autoplayer.gd; IDLE §8): sessions, but exactly one
## raid a session. 8 days (AUTOPLAY_DAYS=n sets it). tests/run.sh --slow --only=autoplay_once_per_session

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("once_per_session", t)
