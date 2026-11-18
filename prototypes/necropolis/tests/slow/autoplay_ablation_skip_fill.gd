extends RefCounted
## Phase I P3 (the run's manager's ruling 2 of 2026-11-18 03:10): the skip-fill ablation under the autoplayer's sessions
## profile (tests/autoplay/autoplayer.gd; IDLE §8). The bot's default fill parks gated builds in the list's spare room
## (Autoplayer._park), as players do; this row runs P2's skip fill (park_gated off: an item that would be gated is passed
## over, but for one parked no_relics entry) beside the sessions baseline, and prints the delta. 8 days
## (AUTOPLAY_DAYS=n sets it). tests/run.sh --slow --only=autoplay_ablation_skip_fill

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("ablation_skip_fill", t)
