extends RefCounted
## RaidSound adapter: the pure helpers (throttle, known-kind gate, chime params, log line) and the
## no-op guarantee when no Synth is attached (tests, headless runs, branches without map's synth).


func run() -> int:
	var t := TestUtil.new()

	t.suite("raid_sound_logic")
	t.ok(not RaidSoundLogic.throttled(-1, 0), "never played is not throttled")
	t.ok(RaidSoundLogic.throttled(1000, 1049), "49 ms after the last play is throttled")
	t.ok(not RaidSoundLogic.throttled(1000, 1050), "50 ms after is allowed")
	t.ok(not RaidSoundLogic.throttled(1000, 1020, 0), "a zero gap never throttles")
	var known := ["absorb", "raise", "chime", "shatter"]
	t.ok(RaidSoundLogic.playable("absorb", known), "a known kind plays")
	t.ok(not RaidSoundLogic.playable("tell", known), "an unknown kind is a no-op")
	t.ok(not RaidSoundLogic.playable("absorb", []), "no kind list (no Synth) is a no-op")
	t.ok(not RaidSoundLogic.playable("", known), "an empty kind is a no-op")
	t.ok(RaidSoundLogic.synth_api_ok(true, 2) and RaidSoundLogic.synth_api_ok(true, 1), "play(kind, params) is accepted")
	t.ok(not RaidSoundLogic.synth_api_ok(false, 2), "no play method is rejected")
	t.ok(not RaidSoundLogic.synth_api_ok(true, 0) and not RaidSoundLogic.synth_api_ok(true, 3), "other arities are rejected")
	t.ok(RaidSoundLogic.can_warm(true, true), "a Synth in the tree can warm")
	t.ok(not RaidSoundLogic.can_warm(true, false), "a Synth outside the tree (no _ready, no config) does not warm")
	t.ok(not RaidSoundLogic.can_warm(false, true), "no Synth does not warm")
	t.ok(int(RaidSoundLogic.chime_params(87)["score"]) == 87, "chime carries the score")
	t.ok(int(RaidSoundLogic.chime_params(-5)["score"]) == 0, "chime score clamps low")
	t.ok(int(RaidSoundLogic.chime_params(250)["score"]) == 100, "chime score clamps high")
	t.ok(RaidSoundLogic.log_line("chime", {"score": 70}) == "RAID_SOUND chime {\"score\":70}", "log line format")

	t.suite("raid_sound")
	RaidSound.play("absorb")
	RaidSound.play("chime", RaidSoundLogic.chime_params(80))
	RaidSound.play("nonsense")
	RaidSound.warm(["absorb"])
	t.ok(true, "play and warm with no attached Synth do nothing and do not crash")
	var holder := Node.new()
	RaidSound.attach(holder)
	RaidSound.play("absorb")
	RaidSound.play("tell")
	t.ok(true, "attach then play is safe whether or not the Synth exists")
	holder.free()

	return t.failures
