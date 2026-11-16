extends RefCounted
## E3-6b, the autoplayer's `first30` profile (tests/autoplay/autoplayer.gd; IDLE §8): GAMEPLAY §6's opening from a new
## game, 30 min live (the first dungeon, its flip, the first big undead, one queue set), then the close and its load at
## the next session. Prints AUTOPLAY_ROW / AUTOPLAY_SUMMARY with each beat and when. tests/run.sh --slow --only=autoplay_first30

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("first30", t)
