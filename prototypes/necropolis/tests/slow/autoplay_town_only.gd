extends RefCounted
## E3-6b, the autoplayer's `town_only` profile (tests/autoplay/autoplayer.gd; IDLE §8): the never-raider, three sessions a
## day playing the town (the queue, the stances, the valve at its default, the vats), never raiding. 8 days
## (AUTOPLAY_DAYS=n sets it). tests/run.sh --slow --only=autoplay_town_only

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("town_only", t)
