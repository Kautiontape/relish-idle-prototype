extends RefCounted
## E3-6b, the autoplayer's `away_risk` profile (tests/autoplay/autoplayer.gd; IDLE §8): the sessions run to the end of
## day 3's last session (the midgame_2flips fixture when nothing is held there, said so in its output), then 24 h away
## twice from that save: as the sessions bot left it, and after the prepared setup (the weak held forts raided, WAR
## raised to support every held fort, a siege and a simulacrum at the thinnest). It measures the held forts lost.
## tests/run.sh --slow --only=autoplay_away_risk

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("away_risk", t)
