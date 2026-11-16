extends RefCounted
## E3-6b, the autoplayer's `sessions` profile (tests/autoplay/autoplayer.gd; IDLE §8): three 20 min sessions a sim day,
## closed between (cmd_save, a fresh GameState, cmd_load with the clock moved: the real catch-up), each acting on the queue,
## the slab, the party, the vats and the phylactery and raiding as many times as fit. 8 days (AUTOPLAY_DAYS=n sets it).
## tests/run.sh --slow --only=autoplay_sessions

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("sessions", t)
