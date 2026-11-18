extends RefCounted
## E3-6b, ablation (b) under the autoplayer's sessions profile (tests/autoplay/autoplayer.gd; BALANCE §2 and §7): the
## spine's "bone-priced buildings removed" (Phase I P3, R-d), a config variant (Autoplayer.cfgs("no_bone_buildings"):
## of the raising pit, charnel house, bone mill, stables, graveyard, embalmer and forge, none levels and none with a
## bone price can be built) on fresh GameStates. It runs the sessions baseline alongside and prints the delta. 8 days
## (AUTOPLAY_DAYS=n sets it).
## tests/run.sh --slow --only=autoplay_ablation_bone

var t := TestUtil.new()


func run() -> int:
	return Autoplayer.run_profile("ablation_bone", t)
