extends RefCounted
## E3-7, the autoplayer's `away_risk_real` profile (tests/autoplay/autoplayer.gd; IDLE §8; the manager's ruling 5 at the
## E3-6b stop: a setup where the risk is real). The same start as away_risk (the sessions run to the end of day 3's last
## session, or the midgame_2flips fixture when nothing is held there), then three absences from that save: 24 h with WAR
## cut to 0, and 72 h as the sessions bot left it and after the prepared setup; then the WAR-cut midgame (the
## midgame_2flips fixture, 24 h as it loads, with WAR cut, and prepared). It measures the held forts lost.
## tests/run.sh --slow --only=autoplay_away_risk_real

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("away_risk_real", t)
