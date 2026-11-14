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

	t.suite("raid_sound warm plan")
	var scfg := {"kinds": {"chime": {"score_step": 5}, "streak": {"step_max": 20, "step_bucket": 1}}}
	var plan := RaidSoundLogic.warm_plan(["unravel", "chime", "streak", "unravel", "raise"], scfg)
	var names := {}
	for it in plan:
		var k := str(it["kind"])
		names[k] = int(names.get(k, 0)) + 1
	t.ok(int(names["unravel"]) == 1 and int(names["raise"]) == 1, "a plain kind renders once, and a repeat is deduped")
	t.ok(int(names["chime"]) == 21, "every chime bucket 0..100 step 5 (21)")
	t.ok(int(names["streak"]) == 21, "every streak step 0..20 (21)")
	t.ok(plan[0]["kind"] == "unravel" and plan[0]["params"] == {}, "the plan keeps the caller's order")
	var scores := []
	for it in plan:
		if it["kind"] == "chime":
			scores.append(int(it["params"]["score"]))
	t.ok(scores[0] == 0 and scores[20] == 100, "chime buckets run 0 to 100")
	t.ok(RaidSoundLogic.warm_plan(["chime"], {}).size() == 21, "no synth config falls back to step 5")
	t.ok(RaidSoundLogic.warm_plan(["streak"], {}).size() == 21, "no synth config falls back to 21 streak steps")
	t.ok(RaidSoundLogic.warm_plan(["streak"], {"kinds": {"streak": {"step_max": 20, "step_bucket": 4}}}).size() == 6, "a streak bucket of 4 gives steps 0,4..20")
	t.ok(RaidSoundLogic.warm_plan([], scfg).is_empty(), "no kinds, no plan")
	if ResourceLoader.exists(RaidSound.SYNTH_LOGIC_PATH):
		var sl := load(RaidSound.SYNTH_LOGIC_PATH) as Script
		var live: Dictionary = sl.call("cfg")
		var keys := {}
		for it in RaidSoundLogic.warm_plan(["chime", "streak"], live):
			keys[sl.call("cache_key", it["kind"], it["params"], live)] = true
		t.ok(keys.size() == RaidSoundLogic.warm_plan(["chime", "streak"], live).size(), "every planned render is a distinct Synth cache key")
		t.ok(keys.size() == 42, "the live config plans 21 chime + 21 streak renders")

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
	if ResourceLoader.exists(RaidSound.SYNTH_PATH):
		t.ok(RaidSound._synth != null, "attach creates the Synth when its script exists")
		t.ok(RaidSound._known.has("unravel"), "attach reads the Synth's kind list (unravel is one)")
		var sy := (load(RaidSound.SYNTH_PATH) as Script).new() as Node
		t.ok(sy.has_method("_stream") and sy.get_method_argument_count("_stream") == 2,
			"Synth._stream(kind, params) exists: the trickle warm calls it (rename it and RaidSound's warm stops)")
		sy.free()
	holder.free()

	return t.failures
