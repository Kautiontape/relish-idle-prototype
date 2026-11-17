extends RefCounted
## E4 step 2, the keep_fronts ablation under the autoplayer's sessions profile (tests/autoplay/autoplayer.gd; IDLE §8):
## the E3 policy, raid_all. Every big rides every raid (the oldest three; reach by the whole party) and the slab fills by
## magnitude alone, so no big is kept home on giants or carvers. It is the proof that those fronts aren't decorative: it
## must reach Vei later than the sessions baseline it runs alongside, or never. It prints the delta, in days to Vei-ready
## or in fronts and backlog at the end. 8 days (AUTOPLAY_DAYS=n sets it). tests/run.sh --slow --only=autoplay_ablation_keep

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("ablation_keep", t)
