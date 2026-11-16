extends RefCounted
## E3-6b, the autoplayer's `sessions_open` profile and the I1 gate (tests/autoplay/autoplayer.gd; IDLE §2 I1, §8): the
## sessions run's commands, replayed at the same sim t on a game left open and untouched between sessions, against the
## sessions run closed. At each day's end both agree: the same t, the bodies within one convoy load, every other stock
## within idle.catchup_tol, the same buildings and levels and held forts; and every replayed command answers as it did.
## 2 days (AUTOPLAY_DAYS=n sets it).
## tests/run.sh --slow --only=autoplay_sessions_open

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("sessions_open", t)
