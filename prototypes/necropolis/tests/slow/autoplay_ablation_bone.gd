extends RefCounted
## E3-6b, ablation (b) under the autoplayer's sessions profile (tests/autoplay/autoplayer.gd; BALANCE §2 and §7): the
## dead's buildings without bone prices, a config variant (Autoplayer.cfgs("no_bone_prices"): the raising pit, charnel
## house, bone mill, stables, graveyard, embalmer and forge at 0 bone at every level, their gold unchanged) on fresh
## GameStates. It runs the sessions baseline alongside and prints the delta. 8 days (AUTOPLAY_DAYS=n sets it).
## tests/run.sh --slow --only=autoplay_ablation_bone

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("ablation_bone", t)
