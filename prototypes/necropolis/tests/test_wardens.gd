extends RefCounted
## Pure-logic tests for WardenLogic and the wardens block of raid.json, plus the antechamber
## last-chance pile. No scene tree, no autoloads.


func run() -> int:
	var t := TestUtil.new()
	var cfg := TestUtil.load_json("res://configs/raid.json")
	var world := TestUtil.load_json("res://configs/world.json")
	var tempo_s := float(TestUtil.load_json("res://configs/pulse.json").get("tempo_ms", 1714)) / 1000.0

	t.suite("warden_config")
	var by_fort: Dictionary = cfg["wardens"]["by_fort"]
	var archs: Dictionary = cfg["wardens"]["archetypes"]
	var ids: Array = []
	for f in world["forts"]:
		ids.append(str(f["id"]))
	t.ok(ids.size() == 12, "world.json has 12 forts")
	var all_present := true
	for id in ids:
		all_present = all_present and by_fort.has(id)
	t.ok(all_present, "every world.json fort is in by_fort")
	var keys_ok := true
	var vals_ok := true
	var seen := {}
	for k in by_fort.keys():
		keys_ok = keys_ok and ids.has(k)
		vals_ok = vals_ok and archs.has(by_fort[k])
		seen[by_fort[k]] = true
	t.ok(keys_ok, "every by_fort key is a world.json fort id")
	t.ok(vals_ok, "every by_fort value is a known archetype")
	t.ok(by_fort.size() == 12, "by_fort has exactly 12 entries")
	t.ok(by_fort["old-sluice"] == "bellringer", "old-sluice is the bellringer")
	t.ok(seen.has("bellringer") and seen.has("huntsman") and seen.has("shieldwall") and seen.has("pyre_priest"), "all four archetypes appear")
	for a in ["bellringer", "huntsman", "shieldwall", "pyre_priest"]:
		var d: Dictionary = archs[a]
		var has_all := true
		for key in ["name", "tells", "weak_point", "hp_base", "hp_per_tier", "radius", "phases", "attack"]:
			has_all = has_all and d.has(key)
		for key in ["stat", "threshold", "effect", "label"]:
			has_all = has_all and (d["weak_point"] as Dictionary).has(key)
		t.ok(has_all and not (d["tells"] as Array).is_empty(), "%s has the full archetype shape" % a)

	t.suite("warden_spec")
	var fort := {"id": "vespers", "tier": 2}
	var s1 := WardenLogic.spec(fort, cfg)
	var s2 := WardenLogic.spec(fort, cfg)
	t.ok(s1 == s2, "spec is deterministic")
	t.ok(s1["archetype"] == "bellringer", "archetype comes from by_fort (vespers)")
	t.ok(WardenLogic.spec({"id": "ashgate", "tier": 1}, cfg)["archetype"] == "huntsman", "ashgate is a huntsman")
	t.ok(WardenLogic.spec({"id": "nowhere", "tier": 1}, cfg)["archetype"] == "bellringer", "unknown fort defaults to bellringer")
	t.ok(WardenLogic.spec({"id": "vespers", "tier": 2, "archetype": "huntsman"}, cfg)["archetype"] == "huntsman", "an explicit archetype wins")
	var ab: Dictionary = archs["bellringer"]
	t.near(float(s1["hp"]), float(ab["hp_base"]) + 2 * float(ab["hp_per_tier"]), 0.001, "bellringer hp at tier 2 = hp_base + 2 x hp_per_tier")
	s1["phases"][0]["period_beats"] = 99.0
	s1["attack"]["dmg_unit"] = 99.0
	s1["tells"].append("x")
	s1["weak_point"]["threshold"] = 99
	var s3 := WardenLogic.spec(fort, cfg)
	t.ok(s3 == s2 and s3["phases"][0]["period_beats"] == 4.0, "mutating a spec never touches the config or the next spec")
	t.ok(float(WardenLogic.spec({"id": "x", "tier": 3}, cfg)["hp"]) > float(WardenLogic.spec({"id": "x", "tier": 1}, cfg)["hp"]), "hp rises with tier")
	var fdm: Dictionary = cfg["wardens"]["first_dungeon"]
	var fd_hp := float(fdm["hp_mult"])
	var fd_per := float(fdm["period_mult"])
	var fd_dmg := float(fdm["dmg_mult"])
	t.ok(fd_per > 1.0 and fd_dmg < 1.0, "the first dungeon's warden is slower and softer (period x%s, damage x%s)" % [fd_per, fd_dmg])
	for a in ["bellringer", "huntsman", "shieldwall", "pyre_priest"]:
		var n := WardenLogic.spec({"id": "x", "tier": 1, "archetype": a}, cfg)
		var f := WardenLogic.spec({"id": "x", "tier": 1, "archetype": a, "first_dungeon": true}, cfg)
		t.ok(f["first_dungeon"] == true and n["first_dungeon"] == false, "%s: first_dungeon flag is carried" % a)
		# the behaviour, against the normal warden: every phase attacks less often, every hit lands softer
		var slower := true
		for i in n["phases"].size():
			slower = slower and WardenLogic.period_beats(f, i) > WardenLogic.period_beats(n, i)
		t.ok(slower, "%s: the first dungeon's warden attacks less often in every phase" % a)
		var softer := true
		for k in n["attack"].keys():
			if str(k).begins_with("dmg_") and float(n["attack"][k]) > 0.0:
				softer = softer and float(f["attack"][k]) < float(n["attack"][k])
		t.ok(softer, "%s: the first dungeon's warden hits softer (every dmg_ key)" % a)
		t.near(float(f["hp"]), float(n["hp"]) * fd_hp, 0.001, "%s: first dungeon hp x hp_mult" % a)
		var per_ok := true
		for i in n["phases"].size():
			per_ok = per_ok and absf(float(f["phases"][i]["period_beats"]) - float(n["phases"][i]["period_beats"]) * fd_per) < 0.0001
		t.ok(per_ok, "%s: first dungeon periods x period_mult" % a)
		var dmg_ok := true
		var any_dmg := false
		for k in n["attack"].keys():
			if str(k).begins_with("dmg_"):
				any_dmg = true
				dmg_ok = dmg_ok and absf(float(f["attack"][k]) - float(n["attack"][k]) * fd_dmg) < 0.0001
			else:
				dmg_ok = dmg_ok and f["attack"][k] == n["attack"][k]
		t.ok(any_dmg and dmg_ok, "%s: first dungeon damage x dmg_mult, other attack params untouched" % a)
	t.ok(RaidLogic.warden_spec(fort, cfg) == WardenLogic.spec(fort, cfg), "RaidLogic.warden_spec delegates to WardenLogic.spec")

	t.suite("warden_beats")
	t.near(WardenLogic.beat_of(tempo_s * 2.5, tempo_s), 2.5, 0.0001, "beat_of counts tempos")
	t.near(WardenLogic.beat_of(0.0, tempo_s), 0.0, 0.0001, "beat_of starts at 0")
	t.near(WardenLogic.wake_phase(tempo_s * 1000.0 * 3.25, tempo_s * 1000.0), 0.25, 0.0001, "wake_phase is the position in the Pulse beat")
	t.ok(not WardenLogic.is_tell(3.99, 5.0, 1.0), "no tell before the window")
	t.ok(WardenLogic.is_tell(4.0, 5.0, 1.0), "tell starts at attack_beat - tell_beats")
	t.ok(WardenLogic.is_tell(4.99, 5.0, 1.0), "tell holds up to the attack")
	t.ok(not WardenLogic.is_tell(5.0, 5.0, 1.0), "no tell on the attack beat")

	t.suite("warden_phases")
	var bell := WardenLogic.spec({"id": "x", "tier": 1, "archetype": "bellringer"}, cfg)
	var hunt := WardenLogic.spec({"id": "x", "tier": 1, "archetype": "huntsman"}, cfg)
	var exp_b := {1.0: 0, 0.67: 0, 0.66: 1, 0.34: 1, 0.33: 2, 0.0: 2}
	for hf in exp_b.keys():
		t.ok(WardenLogic.bellringer_phase(bell, hf) == exp_b[hf], "bellringer hp %.2f -> phase %d" % [hf, exp_b[hf]])
	var exp_h := {0: 0, 1: 0, 2: 1, 3: 1, 4: 2, 9: 2}
	for c in exp_h.keys():
		t.ok(WardenLogic.huntsman_phase(hunt, c) == exp_h[c], "huntsman catches %d -> phase %d" % [c, exp_h[c]])
	t.near(WardenLogic.period_beats(bell, 0), 4.0, 0.0001, "bellringer phase 0 period")
	t.near(WardenLogic.period_beats(bell, 2), 2.0, 0.0001, "bellringer phase 2 period")
	t.near(WardenLogic.period_beats(bell, 9), 2.0, 0.0001, "period_beats clamps the phase")
	t.near(WardenLogic.period_beats(hunt, 1), 3.0, 0.0001, "huntsman phase 1 period")
	var bf := WardenLogic.spec({"id": "x", "tier": 1, "archetype": "bellringer", "first_dungeon": true}, cfg)
	t.ok(WardenLogic.period_beats(bf, 0) > WardenLogic.period_beats(bell, 0),
		"first dungeon: slow slams (%.2f beats, the normal bellringer's 4.0)" % WardenLogic.period_beats(bf, 0))

	t.suite("warden_slam")
	var rpx := float(archs["bellringer"]["attack"]["radius_px"])
	var rbt := float(archs["bellringer"]["attack"]["ring_beats"])
	t.near(WardenLogic.slam_radius(bell, 0.0), 0.0, 0.0001, "ring starts at 0")
	t.near(WardenLogic.slam_radius(bell, rbt * 0.5), rpx * 0.5, 0.001, "ring is half grown at half ring_beats")
	t.near(WardenLogic.slam_radius(bell, rbt * 0.98), rpx * 0.98, 0.001, "ring grows linearly")
	t.near(WardenLogic.slam_radius(bell, rbt), -1.0, 0.0001, "ring is done at ring_beats")
	t.near(WardenLogic.slam_radius(bell, 5.0), -1.0, 0.0001, "ring stays done")
	var band := float(archs["bellringer"]["attack"]["band_px"])
	var targets := [50.0, rpx * 0.55, rpx - 1.0]
	var hits := [0, 0, 0]
	var prev := 0.0
	for fr in range(1, 400):
		var b := fr * 0.002
		var r := WardenLogic.slam_radius(bell, b)
		if r < 0.0:
			break
		for i in targets.size():
			if WardenLogic.slam_crosses(targets[i], prev, r, band):
				hits[i] += 1
		prev = r
	t.ok(hits == [1, 1, 1], "each target is hit exactly once per slam over many frames (%s)" % str(hits))
	t.ok(not WardenLogic.slam_crosses(100.0, 120.0, 120.0, band), "a stalled ring hits nothing")
	t.ok(WardenLogic.slam_crosses(10.0, 0.0, 5.0, band), "a target inside the first frame's band is hit")
	t.ok(not WardenLogic.slam_crosses(200.0, 100.0, 150.0, band), "a target beyond the band is not hit")
	var bat: Dictionary = ab["attack"]
	var du := float(bat["dmg_unit"])
	var dr := float(bat["dmg_relish"])
	var spb := float(bat["soak_per_beef"])
	var msk := float(bat["min_soak"])
	var mfl := float(ab["weak_point"]["dmg_mult"])
	var bth := float(ab["weak_point"]["threshold"])
	t.near(WardenLogic.slam_damage(bell, "unit", 0.0, false), du, 0.0001, "unit damage is dmg_unit")
	t.near(WardenLogic.slam_damage(bell, "relish", 0.0, false), dr, 0.0001, "relish damage is dmg_relish")
	t.near(WardenLogic.slam_damage(bell, "big", 0.0, false), du, 0.0001, "big with no beef takes full damage")
	t.near(WardenLogic.slam_damage(bell, "big", 5.0, false), du * (1.0 - 5.0 * spb), 0.0001, "5 beef soaks 5 x soak_per_beef")
	t.near(WardenLogic.slam_damage(bell, "big", 100.0, false), du * msk, 0.0001, "soak floors at min_soak")
	t.near(WardenLogic.slam_damage(bell, "unit", 99.0, false), du, 0.0001, "beef never soaks small units")
	t.near(WardenLogic.slam_damage(bell, "unit", 0.0, true), du * mfl, 0.0001, "muffled unit damage x the weak point's dmg_mult")
	t.ok(WardenLogic.slam_damage(bell, "relish", 0.0, true) == 0.0, "a MUFFLED slam does not reach Relish (Step 4b: the counter is the soak)")
	t.ok(WardenLogic.bash_strikes_relish(true, false, true) and WardenLogic.bash_strikes_relish(true, true, true) and not WardenLogic.bash_strikes_relish(false, false, true),
		"with the lever on, a bash strikes her in its lit arc, pinned or not (a pin spares her only the rush)")
	t.ok(WardenLogic.bash_strikes_relish(true, false, false) and not WardenLogic.bash_strikes_relish(true, true, false),
		"with it off (t1, the first dungeon), a pinned bash spares her, as before round 3")
	t.near(WardenLogic.slam_damage(bell, "big", 5.0, true), du * (1.0 - 5.0 * spb) * mfl, 0.0001, "muffle stacks with soak")
	t.near(WardenLogic.slam_damage(bf, "relish", 0.0, false), dr * fd_dmg, 0.0001, "first dungeon relish damage x dmg_mult")
	t.ok(mfl < 1.0 and du * mfl < du, "a muffled slam is softer")
	t.ok(WardenLogic.is_muffled(bell, [{"beef": bth}]), "beef at the threshold muffles")
	t.ok(not WardenLogic.is_muffled(bell, [{"beef": bth - 0.1}]), "beef under the threshold does not")
	t.ok(WardenLogic.is_muffled(bell, [{"beef": 1.0}, {"beef": 8.0}]), "any contact over the threshold muffles")
	t.ok(not WardenLogic.is_muffled(bell, []), "no contacts, no muffle")

	t.suite("warden_lunge")
	var from := Vector2(0, 0)
	var to := Vector2(300, 0)
	t.ok(WardenLogic.lunge_interceptor(hunt, from, to, [{"pos": Vector2(150, 30), "speed": 4.0}]) == 0, "fast candidate on the path intercepts")
	t.ok(WardenLogic.lunge_interceptor(hunt, from, to, [{"pos": Vector2(150, 41), "speed": 9.0}]) == -1, "candidate off the path does not")
	t.ok(WardenLogic.lunge_interceptor(hunt, from, to, [{"pos": Vector2(150, 0), "speed": 3.9}]) == -1, "slow candidate on the path does not")
	t.ok(WardenLogic.lunge_interceptor(hunt, from, to, [{"pos": Vector2(330, 0), "speed": 5.0}]) == 0, "candidate just past the end still reaches within intercept_px")
	t.ok(WardenLogic.lunge_interceptor(hunt, from, to, [{"pos": Vector2(-60, 0), "speed": 5.0}]) == -1, "candidate behind the hunter does not")
	var two := [{"pos": Vector2(250, 0), "speed": 5.0}, {"pos": Vector2(100, 10), "speed": 6.0}]
	t.ok(WardenLogic.lunge_interceptor(hunt, from, to, two) == 1, "nearest along the path wins (listed second)")
	t.ok(WardenLogic.lunge_interceptor(hunt, from, to, []) == -1, "no candidates, no interception")
	t.ok(WardenLogic.lunge_hits(from, to, Vector2(150, 20), 22.0), "lunge hits a target on the path")
	t.ok(not WardenLogic.lunge_hits(from, to, Vector2(150, 23), 22.0), "lunge misses a target beside the path")
	t.ok(WardenLogic.lunge_hits(from, to, Vector2(315, 0), 22.0), "lunge hits a target just past the end")
	t.ok(not WardenLogic.lunge_hits(from, to, Vector2(330, 0), 22.0), "lunge stops short of a distant target")
	t.ok(WardenLogic.lunge_hits(from, from, Vector2(10, 0), 22.0), "a zero-length lunge still hits what is inside the circle")

	t.suite("warden_huntsman_helpers")
	var hroom := Rect2(100, 100, 400, 300)
	t.ok(WardenLogic.leash_target(hroom, Vector2(200, 200)) == Vector2(200, 200), "Relish inside the hroom: hunt her")
	t.ok(WardenLogic.leash_target(hroom, Vector2(600, 200)) == hroom.get_center(), "Relish outside the hroom: back to the centre")
	t.ok(WardenLogic.leash_clamp(hroom, Vector2(300, 250), 30.0) == Vector2(300, 250), "a point well inside is not moved")
	t.ok(WardenLogic.leash_clamp(hroom, Vector2(0, 0), 30.0) == Vector2(130, 130), "clamped to the margin at a corner")
	t.ok(WardenLogic.leash_clamp(hroom, Vector2(900, 250), 30.0) == Vector2(470, 250), "clamped to the far edge")
	t.ok(WardenLogic.leash_clamp(Rect2(0, 0, 40, 40), Vector2(5, 5), 30.0) == Vector2(20, 20), "a hroom smaller than the margin collapses to its centre")
	t.ok(WardenLogic.lunge_target(Vector2.ZERO, Vector2(100, 0), 320.0) == Vector2(100, 0), "a near aim point is kept")
	t.ok(WardenLogic.lunge_target(Vector2.ZERO, Vector2(0, 640), 320.0).is_equal_approx(Vector2(0, 320)), "a far aim point is clipped to range_px")
	t.ok(WardenLogic.lunge_stop(Vector2.ZERO, Vector2(300, 0), Vector2(120, 30)).is_equal_approx(Vector2(120, 0)), "an intercepted lunge stops at the interceptor's projection")
	t.ok(WardenLogic.lunge_stop(Vector2.ZERO, Vector2(300, 0), Vector2(400, 0)).is_equal_approx(Vector2(300, 0)), "the stop never passes the lunge's end")
	var gp1 := WardenLogic.guard_point(Vector2(100, 100), Vector2(300, 100), 46.0, 0, 1, 18.0)
	t.ok(gp1.is_equal_approx(Vector2(146, 100)), "a lone guard stands guard_px from Relish toward the threat")
	var gpa := WardenLogic.guard_point(Vector2(100, 100), Vector2(300, 100), 46.0, 0, 2, 18.0)
	var gpb := WardenLogic.guard_point(Vector2(100, 100), Vector2(300, 100), 46.0, 1, 2, 18.0)
	t.ok(absf(gpa.x - 146.0) < 0.001 and absf(gpb.x - 146.0) < 0.001 and absf(gpa.y - gpb.y) > 30.0, "two guards spread sideways, both on the guard line")
	t.ok(absf((gpa.y + gpb.y) * 0.5 - 100.0) < 0.001, "the spread is centred on the line")
	t.ok(WardenLogic.guard_point(Vector2(5, 5), Vector2(5, 5), 46.0, 0, 1, 18.0).is_equal_approx(Vector2(51, 5)), "no threat direction falls back to a fixed side")
	t.near(WardenLogic.stun_damage(hunt, 10.0, false), 10.0, 0.0001, "an unstunned Huntsman takes full damage")
	var sdm := float(archs["huntsman"]["weak_point"]["stun_dmg_mult"])
	t.ok(sdm > 1.0, "a stunned Huntsman takes extra damage (x%s)" % sdm)
	t.near(WardenLogic.stun_damage(hunt, 10.0, true), 10.0 * sdm, 0.0001, "a stunned Huntsman takes x stun_dmg_mult")
	t.near(WardenLogic.stun_damage(bell, 10.0, true), 10.0, 0.0001, "a spec with no stun_dmg_mult is unchanged")
	t.ok(float(archs["bellringer"]["radius"]) >= 50.0 and float(archs["huntsman"]["radius"]) >= 28.0, "wardens read as large glyphs")
	t.ok(float(archs["huntsman"]["attack"]["tell_beats"]) < float(archs["huntsman"]["phases"][2]["period_beats"]), "the lunge tell fits inside the fastest period")
	var spd_ok := true
	for i in range(1, archs["huntsman"]["phases"].size()):
		spd_ok = spd_ok and float(archs["huntsman"]["phases"][i]["speed"]) > float(archs["huntsman"]["phases"][i - 1]["speed"])
	t.ok(spd_ok, "each huntsman phase is faster")

	t.suite("warden_run_config")
	var wc: Dictionary = cfg["wardens"]
	t.ok(float(wc.get("chest_open_px", 0.0)) > 0.0 and float(wc.get("victory_s", 0.0)) > 0.0, "chest_open_px and victory_s are set")
	t.ok(int(cfg["essence"].get("per_warden", 0)) > 0, "essence.per_warden is set")
	var ph: Array = archs["bellringer"]["phases"]
	t.ok(float(ph[0]["period_beats"]) > float(ph[1]["period_beats"]) and float(ph[1]["period_beats"]) > float(ph[2]["period_beats"]), "each bellringer phase rings faster")
	t.ok(float(archs["bellringer"]["attack"]["tell_beats"]) < float(ph[2]["period_beats"]), "the tell fits inside the fastest period")

	t.suite("merge_loot")
	var base := {"relics": 1, "blueprints": ["a"], "husks": [], "remnants": [], "essence": 0}
	var add := {"relics": 2, "blueprints": ["b"], "husks": [{"x": 1}], "remnants": [], "essence": 5}
	var m := RaidLogic.merge_loot(base, add)
	t.ok(int(m["relics"]) == 3, "relics add")
	t.ok(m["blueprints"] == ["a", "b"] and (m["husks"] as Array).size() == 1, "arrays append")
	t.ok(int(m.get("essence", 0)) == 0, "essence is skipped (it is the carried cluster)")
	t.ok(base["blueprints"] == ["a"] and int(base["relics"]) == 1, "inputs are unchanged")
	t.ok(RaidLogic.merge_loot({}, RaidLogic.empty_loot()).get("relics", -1) == 0, "merging the empty loot into nothing is safe")
	t.ok(RaidLogic.merge_loot(base, {}) == base, "merging nothing changes nothing")

	t.suite("warden_ante_pile")
	var checked := 0
	var ante_ok := true
	var rest_ok := true
	var plain_ok := true
	for f in world["forts"]:
		for tier in [1, 2, 3, 4]:
			var lay := LayoutLogic.gen_layout(str(f["id"]), tier, false, cfg)
			var piles := LayoutLogic.populate_piles(str(f["id"]), lay, 6)
			var ar := int(lay["ante_room"])
			if ar < 0:
				continue
			checked += 1
			var room: Rect2 = (lay["rooms"] as Array)[ar]
			var inner := room.grow(-60.0) if room.size.x > 180.0 and room.size.y > 180.0 else room.grow(-24.0)
			ante_ok = ante_ok and piles.size() == 6 and inner.grow(0.001).has_point(piles[0])
			var again := LayoutLogic.populate_piles(str(f["id"]), lay, 6)
			rest_ok = rest_ok and again == piles
	for tier in [1, 2, 3]:
		var held := LayoutLogic.gen_layout("held-fort", tier, false, cfg, {"held": true})
		var hp := LayoutLogic.populate_piles("held-fort", held, 4)
		plain_ok = plain_ok and hp.size() == 4 and int(held["ante_room"]) == -1
	t.ok(checked >= 40, "antechamber checked across forts and tiers (%d layouts)" % checked)
	t.ok(ante_ok, "the first pile is inside the antechamber's inner rect")
	t.ok(rest_ok, "pile placement stays deterministic")
	t.ok(plain_ok, "a held layout (no antechamber) still places every pile")
	t.ok(LayoutLogic.populate_piles("x", LayoutLogic.gen_layout("x", 2, false, cfg), 0).is_empty(), "zero piles stays empty")

	_hunt_tests(t)
	_window_tests(t, tempo_s)
	_meter_tests(t, cfg)
	_shield_tests(t, cfg)
	_pyre_tests(t, cfg)
	_pack_tests(t, cfg)
	return t.failures


## D-d/E Step 3: a warden's pack (WardenLogic.pack_*; the Huntsman's hounds).
func _pack_tests(t: TestUtil, cfg: Dictionary) -> void:
	t.suite("warden_pack")
	var h1 := WardenLogic.spec({"id": "ashgate", "tier": 1}, cfg)
	var h2 := WardenLogic.spec({"id": "chime-fort", "tier": 2}, cfg)
	var h3 := WardenLogic.spec({"id": "hollow-redoubt", "tier": 3}, cfg)
	var hf := WardenLogic.spec({"id": "x", "tier": 3, "archetype": "huntsman", "first_dungeon": true}, cfg)
	t.ok(not h1.has("pack") and not hf.has("pack"), "no pack key at tier 1 or in the first dungeon: those specs are as they were")
	var pk: Dictionary = h2["pack"]
	t.ok(int(pk["size"]) == int(cfg["wardens"]["archetypes"]["huntsman"]["pack"]["size_by_tier"]["2"]) and int(pk["size"]) > 0
		and int(h3["pack"]["size"]) >= int(pk["size"]), "the pack never shrinks with the tier (%d at t2, %d at t3)" % [int(pk["size"]), int(h3["pack"]["size"])])
	t.ok(not pk.has("_doc"), "the spec's pack carries no _doc")
	for a in ["bellringer", "shieldwall", "pyre_priest"]:
		var o := WardenLogic.spec({"id": "x", "tier": 3, "archetype": a}, cfg)
		t.ok(o.has("pack") == (cfg["wardens"]["archetypes"][a] as Dictionary).has("pack"), "%s: a pack only where its config has one" % a)
	var gates: Array = pk["at_hp_frac"]
	var gate_ok := true
	for gi in gates.size():
		gate_ok = gate_ok and not WardenLogic.pack_due(pk, float(gates[gi]) + 0.001, gi) and WardenLogic.pack_due(pk, float(gates[gi]), gi)
	t.ok(gate_ok, "each horn sounds at its own gate (%s), not above it" % str(gates))
	t.ok(not WardenLogic.pack_due(pk, 0.0, gates.size()), "no horn after the last gate")
	t.ok(not WardenLogic.pack_due({}, 0.1, 0), "no pack: never")
	t.near(WardenLogic.pack_ward(pk, 3), float(pk["ward_mult"]), 1e-9, "warded while any of the pack stands")
	t.ok(WardenLogic.pack_ward(pk, 0) == 1.0 and WardenLogic.pack_ward({}, 5) == 1.0, "exactly 1.0 with none standing or no pack")
	var room := Rect2(100, 100, 600, 400)
	var me := Vector2(150, 150)
	var pts := WardenLogic.pack_spots(room, me, 5, 50.0, 28.0)
	var inside := pts.size() == 5
	var far := true
	for q in pts:
		inside = inside and room.grow(-49.9).has_point(q)
		far = far and q.distance_to(me) > room.get_center().distance_to(me)
	t.ok(inside, "every hound comes in inside the room, clear of its walls: %s" % str(pts))
	t.ok(far, "on the far side from Relish")
	t.ok(pts[0] == Vector2(650, 450) and (pts[1] == Vector2(650, 150) or pts[1] == Vector2(150, 450)), "the first two at the two corners farthest from her")
	t.ok(str(WardenLogic.pack_spots(room, me, 5, 50.0, 28.0)) == str(pts), "the same each time (no rng)")
	var hb := WardenLogic.meter_bands(h2)
	t.ok(hb.size() == gates.size() + 2 and is_equal_approx(hb[1], float(gates[0])), "its meter is notched where the horn sounds: %s" % str(hb))
	t.ok(WardenLogic.pack_label(pk, 3, 5) == "HOUNDS 3 of 5 · it takes ×%s" % str(snappedf(float(pk["ward_mult"]), 0.01)), "the HUD row while they run: " + WardenLogic.pack_label(pk, 3, 5))
	t.ok(WardenLogic.pack_label(pk, 0, 5) == "", "and nothing once they are down")
	t.ok(WardenLogic.pack_teach(pk).begins_with("at 2/3 and 1/3 of its strength it calls %d hounds" % int(pk["size"])), "the teach row from the spec: " + WardenLogic.pack_teach(pk))
	t.ok(RaidLogic.death_cause("hound", "The Huntsman") == "The Huntsman's hounds", "the death card names the hounds")
	t.ok(RaidLogic.death_cause("pack", "The Bellringer") == "The Bellringer's pack", "and any other warden's pack")
	# 3c: the death card names the attack and the tell she missed
	t.ok(RaidLogic.death_line("slam", "The Bellringer") == "The Bellringer's slam · missed: the swing", "the card names the missed tell: " + RaidLogic.death_line("slam", "The Bellringer"))
	t.ok(RaidLogic.death_line("toll", "The Bellringer") == "The Bellringer's toll · missed: the ring at your feet" and RaidLogic.TELL_ATTACKS.has("toll")
		and not RaidLogic.chain_soaks("toll", true), "a toll death has its own line, and the toll stays a tell-attack: " + RaidLogic.death_line("toll", "The Bellringer"))
	t.ok(RaidLogic.death_line("lunge", "The Huntsman") == "The Huntsman's lunge · missed: the line"
		and RaidLogic.death_line("rush", "The Shieldwall") == "The Shieldwall's rush · missed: the lit arc"
		and RaidLogic.death_line("bash", "The Shieldwall") == "The Shieldwall's bash · missed: the lit arc"
		and RaidLogic.death_line("fire", "The Pyre-priest") == "The Pyre-priest's fire · missed: the marked ground", "every warden attack's tell")
	t.ok(RaidLogic.death_line("hound", "The Huntsman") == "The Huntsman's hounds" and RaidLogic.death_line("living", "") == "the living"
		and RaidLogic.death_line("", "x") == "a wound", "no tell, no missed: (a pack, the living, a wound)")
	# Step 4b (option A): a warden's tell-attacks strike her directly; the chain soaks everything else
	var bypass := true
	for src in ["slam", "lunge", "bash", "rush", "fire"]:
		bypass = bypass and not RaidLogic.chain_soaks(src, true)
	t.ok(bypass, "with the gate on the chain never soaks a warden's tell-attack (slam, lunge, bash, rush, fire)")
	t.ok(RaidLogic.chain_soaks("living", true) and RaidLogic.chain_soaks("pack", true) and RaidLogic.chain_soaks("hound", true) and RaidLogic.chain_soaks("", true),
		"it still soaks the living, packs, hounds and any unnamed blow (Vei's weaves)")
	var wcfg: Dictionary = cfg["wardens"]
	t.ok(not WardenLogic.lever_on(1, false, wcfg) and RaidLogic.chain_soaks("slam", WardenLogic.lever_on(1, false, wcfg)), "tier 1: the chain soaks a slam (the gate is off)")
	t.ok(not WardenLogic.lever_on(3, true, wcfg) and RaidLogic.chain_soaks("lunge", WardenLogic.lever_on(3, true, wcfg)), "the first dungeon: the chain soaks a lunge")
	t.ok(WardenLogic.lever_on(2, false, wcfg) and not RaidLogic.chain_soaks("slam", WardenLogic.lever_on(2, false, wcfg)), "tier 2: the slam strikes her")
	var rel_src := FileAccess.get_file_as_string("res://scripts/raid/relish.gd")
	t.ok(rel_src.contains("raid.has_allies() and RaidLogic.chain_soaks(src, raid.warden_run != null and raid.warden_run.tell_bypass)"), "Relish.take_hit asks RaidLogic.chain_soaks with the fort's gate")
	var wr_src := FileAccess.get_file_as_string("res://scripts/raid/raid_warden_run.gd")
	t.ok(wr_src.contains("tell_bypass = WardenLogic.lever_on("), "the gate is the lever's own (WardenLogic.lever_on)")
	# 3c: a pack never turns on Relish: with no undead standing it breaks (standing or still being called)
	t.ok(WardenLogic.pack_breaks(3, false, false) and WardenLogic.pack_breaks(0, true, false), "no undead stands: a standing pack, or one its horn calls, breaks")
	t.ok(not WardenLogic.pack_breaks(3, false, true) and not WardenLogic.pack_breaks(0, true, true), "undead stand: it stays")
	t.ok(not WardenLogic.pack_breaks(0, false, false), "no pack: nothing to break")
	# 3b: each pack answers to its warden's own counter stat, in one blow, with the weak point's verb
	for row in [["bellringer", "MUFFLED"], ["huntsman", "INTERCEPTED"], ["shieldwall", "FLANKED"], ["pyre_priest", "SNUFFED"]]:
		var sp := WardenLogic.spec({"id": "x", "tier": 3, "archetype": row[0]}, cfg)
		var th := float(sp["weak_point"]["threshold"])
		t.ok(WardenLogic.pack_breaker(sp, th) and not WardenLogic.pack_breaker(sp, th - 0.5), "%s: a big at its weak point's threshold breaks a pack unit, one under does not" % row[0])
		t.ok(WardenLogic.pack_verb(sp) == row[1], "%s: the one-blow kill reads %s" % [row[0], row[1]])
		t.ok(WardenLogic.pack_teach(sp["pack"]).contains("%s %s kills one in a blow" % [str(sp["weak_point"]["stat"]), str(snappedf(th, 0.1))]), "%s: the teach row names its counter" % row[0])
	t.ok(not WardenLogic.pack_breaker(WardenLogic.spec({"id": "x", "tier": 1, "archetype": "huntsman"}, cfg), 99.0), "no pack (tier 1): nothing to break")
	# 3b: the Shieldwall's rush is pinned by a wits flanker at its back
	var wpos := Vector2(500, 500)
	t.ok(WardenLogic.shield_pinned(0.0, wpos, 80.0, [Vector2(430, 500)], 90.0), "a flanker posted behind it pins it")
	t.ok(not WardenLogic.shield_pinned(0.0, wpos, 80.0, [Vector2(570, 500)], 90.0), "one on the shield's side does not")
	t.ok(not WardenLogic.shield_pinned(0.0, wpos, 80.0, [Vector2(300, 500)], 90.0), "nor one too far off")
	t.ok(not WardenLogic.shield_pinned(0.0, wpos, 80.0, [], 90.0), "no flanker: unpinned")
	var sat: Dictionary = cfg["wardens"]["archetypes"]["shieldwall"]["attack"]
	var stand := float(sat["reach_px"]) + 13.0 + float(cfg["autopilot"]["wall_margin_px"]) + float(cfg["autopilot"]["wall_stand_px"])
	t.ok(float(sat["reach_px"]) + float(sat["rush_px"]) + 13.0 >= stand and 80.0 + float(sat["rush_half_deg"]) >= float(cfg["autopilot"]["wall_side_deg"]),
		"a rush reaches a conduit waiting at its side stand (%d px, %d deg off its facing)" % [stand, float(cfg["autopilot"]["wall_side_deg"])])
	# Step 4.1: the rush never covers a small room (pale-bastion's is 543 px across)
	var rf := float(sat["rush_room_frac"])
	var full := float(sat["reach_px"]) + float(sat["rush_px"])
	t.near(WardenLogic.rush_reach(float(sat["reach_px"]), float(sat["rush_px"]), 339.0, rf), full, 1e-9, "in the-stair's room (678 px) the rush keeps its full reach")
	var small := WardenLogic.rush_reach(float(sat["reach_px"]), float(sat["rush_px"]), 271.5, rf)
	t.ok(small < full and small <= 271.5 * rf + 1e-6 and small + 13.0 < 271.5, "in pale-bastion's (543 px) it stops at %d px: with her 13 px radius it still reaches her side stand (%d px), but the ring out to the room's half-size (271 px) is clear" % [small, stand])
	t.ok(WardenLogic.rush_reach(140.0, 120.0, 100.0, rf) == 140.0 and WardenLogic.rush_reach(140.0, 120.0, 100.0, 0.0) == 260.0, "never below the bash's own reach; frac 0 is no cap")
	# Step 4, the lever candidates: from lever_min_tier up, never the first dungeon
	var cfg0: Dictionary = cfg.duplicate(true)
	cfg0["wardens"]["relish_dmg_mult_by_tier"] = {}   # (Step 4c: the per-tier values off, so these read the base levers)
	var lc: Dictionary = cfg.duplicate(true)
	lc["wardens"]["attack_dmg_mult"] = 2.0
	lc["wardens"]["relish_dmg_mult"] = 3.0
	lc["wardens"]["relish_dmg_mult_by_tier"] = {}   # (the per-tier values would override it; Step 4c)
	var base2: Dictionary = WardenLogic.spec({"id": "x", "tier": 2, "archetype": "bellringer"}, cfg0)["attack"]
	var lev2: Dictionary = WardenLogic.spec({"id": "x", "tier": 2, "archetype": "bellringer"}, lc)["attack"]
	t.ok(is_equal_approx(float(lev2["dmg_unit"]), 2.0 * float(base2["dmg_unit"])) and is_equal_approx(float(lev2["dmg_relish"]), 6.0 * float(base2["dmg_relish"])),
		"at tier 2 attack_dmg_mult scales all its damage, relish_dmg_mult only Relish's (%s)" % str(lev2))
	t.ok(str(WardenLogic.spec({"id": "x", "tier": 1, "archetype": "bellringer"}, lc)) == str(WardenLogic.spec({"id": "x", "tier": 1, "archetype": "bellringer"}, cfg))
		and str(WardenLogic.spec({"id": "x", "tier": 3, "archetype": "huntsman", "first_dungeon": true}, lc)) == str(WardenLogic.spec({"id": "x", "tier": 3, "archetype": "huntsman", "first_dungeon": true}, cfg)),
		"tier 1 and the first dungeon are untouched by the lever")
	t.ok(float(cfg["wardens"]["attack_dmg_mult"]) == 1.0 and float(cfg["wardens"]["relish_dmg_mult"]) == 1.0, "both levers rest at 1.0 until chosen")
	# Step 4c: the lever per tier, falling back to relish_dmg_mult
	var bt := {"relish_dmg_mult": 1.0, "relish_dmg_mult_by_tier": {"_doc": "x", "3": 0.75, "4": 1.35}}
	t.ok(is_equal_approx(WardenLogic.relish_mult(bt, 2), 1.0) and is_equal_approx(WardenLogic.relish_mult(bt, 3), 0.75) and is_equal_approx(WardenLogic.relish_mult(bt, 4), 1.35)
		and is_equal_approx(WardenLogic.relish_mult({"relish_dmg_mult": 1.2}, 3), 1.2), "relish_dmg_mult_by_tier per tier, else relish_dmg_mult")
	var lt: Dictionary = cfg.duplicate(true)
	lt["wardens"]["relish_dmg_mult_by_tier"] = {"3": 0.5}
	var b3: Dictionary = WardenLogic.spec({"id": "x", "tier": 3, "archetype": "huntsman"}, cfg0)["attack"]
	var l3: Dictionary = WardenLogic.spec({"id": "x", "tier": 3, "archetype": "huntsman"}, lt)["attack"]
	t.ok(is_equal_approx(float(l3["dmg_relish"]), 0.5 * float(b3["dmg_relish"])) and is_equal_approx(float(l3["dmg_unit"]), float(b3["dmg_unit"]))
		and str(WardenLogic.spec({"id": "x", "tier": 1, "archetype": "huntsman"}, lt)) == str(WardenLogic.spec({"id": "x", "tier": 1, "archetype": "huntsman"}, cfg))
		and str(WardenLogic.spec({"id": "x", "tier": 3, "archetype": "huntsman", "first_dungeon": true}, lt)) == str(WardenLogic.spec({"id": "x", "tier": 3, "archetype": "huntsman", "first_dungeon": true}, cfg)),
		"the tier's value reaches only its Relish damage; t1 and the first dungeon untouched")
	# Step 4c: the honest lunge tell: the drawn line is the dash's line, also at the leash edge
	var lroom := Rect2(1274.676, 30.0, 495.3244, 669.1307)
	var lfrom := Vector2(1379.848, 669.1307)
	var lock := WardenLogic.lunge_lock(lroom, lfrom, Vector2(1505.124, 696.832), 320.0, 30.0)
	var dash_to := WardenLogic.leash_clamp(lroom, lock, 30.0)
	t.ok(lock.distance_to(dash_to) < 0.001, "at the leash edge the drawn line ends where the dash ends (%s)" % str(lock))
	var reach := 22.0 + 13.0
	var dside := (lock - lfrom).normalized().orthogonal()
	var all_safe := true
	for k in 11:
		var on_line := lfrom.lerp(lock, float(k) / 10.0)
		for sgn in [-1.0, 1.0]:
			all_safe = all_safe and not WardenLogic.lunge_hits(lfrom, dash_to, on_line + dside * sgn * (reach + 1.0), reach)
	var old_lock := WardenLogic.lunge_target(lfrom, Vector2(1505.124, 696.832), 320.0)
	var old_side := (old_lock - lfrom).normalized().orthogonal()
	var old_to := WardenLogic.leash_clamp(lroom, old_lock, 30.0)
	var old_caught := WardenLogic.lunge_hits(lfrom, old_to, old_lock + old_side * (reach + 1.0), reach) \
		or WardenLogic.lunge_hits(lfrom, old_to, old_lock - old_side * (reach + 1.0), reach)
	t.ok(all_safe and old_caught, "a sidestep off the drawn line by the catch reach is safe all along it (unclamped, a step off the old drawn line's end was caught on one side)")
	# Step 4b, the reach at her stand: the toll and the aimed lane
	t.ok(WardenLogic.toll_strikes(Vector2(100, 0), Vector2(60, 0), 70.0, 13.0, false, false), "the toll strikes her while she is still in its ring")
	t.ok(not WardenLogic.toll_strikes(Vector2(200, 0), Vector2(60, 0), 70.0, 13.0, false, false), "stepped out: it misses")
	t.ok(not WardenLogic.toll_strikes(Vector2(60, 0), Vector2(60, 0), 70.0, 13.0, true, false), "a muffled bell tolls nothing on her")
	t.ok(not WardenLogic.toll_strikes(Vector2(60, 0), Vector2(60, 0), 70.0, 13.0, false, true), "no second blow where the slam's ring reaches her")
	# the toll's exit (round 3): a point in the room out of both rings, reached in the lead less a human's reaction
	var ex_open := WardenLogic.toll_exit(Rect2(0, 0, 1000, 800), Vector2(500, 100), Vector2(500, 400), 45.0, 13.0, 100.0, 16.0, 267.0)
	t.ok(ex_open != Vector2.INF and absf(ex_open.distance_to(Vector2(500, 100)) - 74.0) < 0.01, "open floor: the exit is just out of the toll (%s)" % str(ex_open))
	var ex_wall := WardenLogic.toll_exit(Rect2(0, 0, 640, 490), Vector2(620, 245), Vector2(320, 245), 45.0, 13.0, 291.0, 16.0, 267.0)
	t.ok(ex_wall != Vector2.INF and ex_wall.distance_to(Vector2(320, 245)) >= 307.0 and Rect2(0, 0, 640, 490).grow(-13.0).has_point(ex_wall)
		and absf(ex_wall.x - 620.0) < 1.0, "a wall at her back: the exit runs sideways along the slam's edge, in the room (%s)" % str(ex_wall))
	t.ok(WardenLogic.toll_exit(Rect2(0, 0, 560, 400), Vector2(13, 13), Vector2(280, 200), 45.0, 13.0, 291.0, 16.0, 267.0) == Vector2.INF,
		"a corner the slam nearly fills (lantern-keep s2's corner, in a tighter room): no exit, so no toll")
	t.ok(WardenLogic.toll_exit(Rect2(0, 0, 640, 490), Vector2(620, 245), Vector2(320, 245), 45.0, 13.0, 291.0, 16.0, 60.0) == Vector2.INF,
		"no exit a human reaches in time: no toll")
	t.near(WardenLogic.lane_reach(Rect2(0, 0, 600, 400), Vector2(300, 200)), Vector2(300, 200).length(), 1e-6, "the lane reaches the room's farthest corner")
	var pyre3 := WardenLogic.spec({"id": "x", "tier": 3, "archetype": "pyre_priest"}, cfg)
	var her := Vector2(400, 300)
	var plain := WardenLogic.burn_plan(pyre3, 1, 0, Vector2(200, 200), {"motes": [Vector2(250, 250)], "piles": [], "relish": her})
	var aimed := WardenLogic.burn_plan(pyre3, 1, 0, Vector2(200, 200), {"motes": [Vector2(250, 250)], "piles": [], "relish": her, "aim": true})
	t.ok(not plain.has(her) and aimed.size() == maxi(1, plain.size()) and aimed[aimed.size() - 1].distance_to(her) < 1.0,
		"with no acolyte left an aimed burn beat still puts one fire on her (%s -> %s)" % [str(plain), str(aimed)])
	# every tell is answerable by a human: lead >= the score-50 delay + the time to clear, worst case from inside
	var pulse := TestUtil.load_json("res://configs/pulse.json")
	var beat_s := float(pulse["tempo_ms"]) / 1000.0
	var spd := float(cfg["relish"]["speed"])
	var rr := float(cfg["relish"]["radius"])
	var d50 := float((cfg["autopilot"]["react_delay_s"] as Array)[0])   # the score-50 delay (react_score[0])
	var archs: Dictionary = cfg["wardens"]["archetypes"]
	var bell_at: Dictionary = archs["bellringer"]["attack"]
	var clears := {
		"slam": float(bell_at["radius_px"]) + float(bell_at["band_px"]) * 0.5 + rr - (float(archs["bellringer"]["radius"]) + rr),
		"toll": 0.0,   # its worst-case exit path, below
		"lunge": float(archs["huntsman"]["attack"]["hit_radius_px"]) + rr,
		"bash": float(archs["shieldwall"]["attack"]["reach_px"]) + rr - (float(archs["shieldwall"]["radius"]) + rr),
		"fire": 105.0 + rr,
	}
	# the toll's worst-case exit path: every spot a toll can land in the at-tier Bellringer forts' warden rooms
	var slam_r := float(bell_at["radius_px"]) + float(bell_at["band_px"]) * 0.5
	var budget := (float(bell_at["tell_beats"]) * beat_s - float(bell_at["toll_react_s"])) * spd
	var toll_worst := 0.0
	var toll_spots := [0, 0]
	for fid in ["vespers", "lantern-keep", "sable-hold"]:
		var blay := RaidLogic.gen_layout(fid, 4 if fid == "sable-hold" else 2, false, cfg)
		var broom: Rect2 = blay["rooms"][int(blay["warden_room"])]
		var bc := broom.get_center()
		for gx in range(int(broom.position.x + rr) + 5, int(broom.end.x - rr), 10):
			for gy in range(int(broom.position.y + rr) + 5, int(broom.end.y - rr), 10):
				var sp := Vector2(gx, gy)
				if sp.distance_to(bc) <= slam_r + rr:
					continue
				toll_spots[1] += 1
				var ex := WardenLogic.toll_exit(broom, sp, bc, float(bell_at["toll_radius_px"]), rr, slam_r + rr, float(bell_at["toll_exit_margin_px"]), budget)
				if ex != Vector2.INF:
					toll_spots[0] += 1
					toll_worst = maxf(toll_worst, sp.distance_to(ex))
	t.ok(toll_spots[0] > 0, "the toll can land at %d of %d spots beyond the slam in the at-tier Bellringer rooms" % toll_spots)
	clears["toll"] = toll_worst
	var lane_r := 0.0
	for fid in ["pale-bastion", "the-stair"]:
		var lay := RaidLogic.gen_layout(fid, 3 if fid == "pale-bastion" else 4, false, cfg)
		var wroom: Rect2 = lay["rooms"][int(lay["warden_room"])]
		lane_r = maxf(lane_r, WardenLogic.lane_reach(wroom, wroom.get_center()))
	clears["rush lane"] = lane_r * sin(deg_to_rad(float(archs["shieldwall"]["attack"]["rush_lane_half_deg"]))) + rr
	var worst := ""
	var ok_all := true
	for k in clears:
		var margin := float(archs["bellringer"]["attack"]["tell_beats"]) * beat_s - d50 - float(clears[k]) / spd
		ok_all = ok_all and margin >= 0.0
		worst += " %s %.2fs" % [k, margin]
	t.ok(ok_all, "every tell-attack is answerable by a human (lead - 0.6 s - clear/speed >= 0):%s" % worst)
	# the fire with its spread (phase 1, acolytes alive): one fire on her, the others relish_spread_px along her line
	# from the priest; the way out is sideways, and it clears them all
	var pya: Dictionary = archs["pyre_priest"]["attack"]
	var r1 := float((archs["pyre_priest"]["phases"] as Array)[0]["burn_radius_px"])
	var fspots := WardenLogic.relish_spots(Vector2.ZERO, Vector2(-200, 0), int(pya["relish_areas_max"]), float(pya["relish_spread_px"]))
	var fout := Vector2(0, r1 + rr)
	var fclear := true
	for fsp in fspots:
		fclear = fclear and fout.distance_to(fsp) > r1 + rr - 0.001
	var fmargin := float(pya["tell_beats"]) * beat_s - d50 - fout.length() / spd
	t.ok(fclear and fmargin >= 0.0, "the fire with its spread (%d fires, %d px apart, %d px wide): out sideways %.0f px, clear of all: %.2fs"
		% [fspots.size(), int(pya["relish_spread_px"]), int(r1), fout.length(), fmargin])
	var gd_src := FileAccess.get_file_as_string("res://scripts/raid/raid_warden_run.gd")
	t.ok(gd_src.contains("or u.kind != \"big\" or warden.pack_alive() > 0:"), "the Huntsman's bodyguards leave the post while its hounds run (Step 4.1)")
	for a2 in ["bellringer", "shieldwall"]:
		var w2 := WardenLogic.spec({"id": "x", "tier": 3, "archetype": a2}, cfg)
		var w1 := WardenLogic.spec({"id": "x", "tier": 1, "archetype": a2}, cfg)
		t.ok(w2.has("pack") and WardenLogic.meter_bands(w2) == WardenLogic.meter_bands(w1), "%s: an hp-phased warden's meter keeps its phase notches with a pack" % a2)



func _pyre_tests(t: TestUtil, cfg: Dictionary) -> void:
	t.suite("pyre_config")
	var archs: Dictionary = cfg["wardens"]["archetypes"]
	var a: Dictionary = archs["pyre_priest"]
	var at: Dictionary = a["attack"]
	var by_fort: Dictionary = cfg["wardens"]["by_fort"]
	t.ok(by_fort["mourners-gate"] == "pyre_priest" and by_fort["whitecross"] == "pyre_priest", "mourners-gate (t3) and whitecross (t4) are the Pyre-priest")
	t.ok(str(a.get("_doc", "")) != "" and str(a["name"]) == "The Pyre-priest", "the Pyre-priest is documented and named")
	var wp: Dictionary = a["weak_point"]
	t.ok(wp["stat"] == "power" and wp["effect"] == "snuff", "its weak point is power, effect snuff")
	for tier in ["3", "4"]:
		var meets := false
		for e in cfg["autopilot"]["party_profiles"][tier]["party"]:
			meets = meets or float(e["stats"]["power"]) >= float(wp["threshold"])
		t.ok(meets, "a standard tier-%s party big meets the power threshold (%s)" % [tier, str(wp["threshold"])])
	var ph: Array = a["phases"]
	t.ok(ph.size() == 3 and (ph[0] as Dictionary).has("until_acolytes") and (ph[1] as Dictionary).has("until_hp_frac"), "phase 1 holds while acolytes live, phase 3 at an hp gate")
	var hotter := true
	for i in range(1, ph.size()):
		hotter = hotter and float(ph[i]["period_beats"]) < float(ph[i - 1]["period_beats"]) and float(ph[i]["burn_radius_px"]) > float(ph[i - 1]["burn_radius_px"])
	t.ok(hotter, "each phase burns sooner and wider")
	t.ok(float(at["tell_beats"]) < float(ph[ph.size() - 1]["period_beats"]), "the burn tell fits inside the fastest period")
	t.ok(float(at["ward_mult"]) > 0.0 and float(at["ward_mult"]) < 0.5, "the ward is a small multiplier (%s)" % str(at["ward_mult"]))
	var dmg_keys := []
	for k in at.keys():
		if str(k).begins_with("dmg_"):
			dmg_keys.append(str(k))
	dmg_keys.sort()
	t.ok(dmg_keys == ["dmg_relish", "dmg_unit"], "only damage is named dmg_ (the first dungeon scales those): %s" % str(dmg_keys))
	var warm: Array = cfg["sound"]["warm"]
	t.ok(warm.has("ignite") and warm.has("snuff") and warm.has("tell"), "ignite and snuff are warmed")
	var sp3 := WardenLogic.spec({"id": "mourners-gate", "tier": 3}, cfg)
	var sp4 := WardenLogic.spec({"id": "whitecross", "tier": 4}, cfg)
	t.ok(sp3["archetype"] == "pyre_priest" and sp4["archetype"] == "pyre_priest", "both forts field it")
	t.near(float(sp3["hp"]), float(a["hp_base"]) + 3.0 * float(a["hp_per_tier"]), 0.001, "pyre-priest hp at tier 3")
	var spf := WardenLogic.spec({"id": "x", "tier": 1, "archetype": "pyre_priest", "first_dungeon": true}, cfg)
	var sp1 := WardenLogic.spec({"id": "x", "tier": 1, "archetype": "pyre_priest"}, cfg)
	t.ok(WardenLogic.period_beats(spf, 0) > WardenLogic.period_beats(sp1, 0) and float(spf["attack"]["dmg_relish"]) < float(sp1["attack"]["dmg_relish"])
		and float(spf["attack"]["ward_mult"]) == float(sp1["attack"]["ward_mult"]), "a first-dungeon Pyre-priest burns slower and softer; its ward is the same")

	t.suite("pyre_acolytes")
	t.ok(WardenLogic.acolyte_count(sp3) == 3 and WardenLogic.acolyte_count(sp4) == 4 and WardenLogic.acolyte_count(sp1) == 1,
		"acolytes_base + acolytes_per_tier x tier: 1 / 3 / 4 at tiers 1 / 3 / 4")
	t.ok(WardenLogic.acolyte_count({"tier": 2, "attack": {"acolytes_base": -5, "acolytes_per_tier": 1}}) == 0, "never fewer than none")
	var c := Vector2(500, 400)
	var posts := WardenLogic.acolyte_posts(c, Vector2(500, 700), 3, 160.0, 110.0)
	var ring_ok := true
	for p in posts:
		ring_ok = ring_ok and absf(p.distance_to(c) - 160.0) < 0.001 and p.y < c.y
	t.ok(posts.size() == 3 and ring_ok, "three posts on the ring, all on the far side from the way in (it comes from below)")
	t.ok(posts[1].is_equal_approx(Vector2(500, 240)), "the middle post stands straight behind")
	t.near(absf(WardenLogic.angle_diff((posts[0] - c).angle(), (posts[2] - c).angle())), deg_to_rad(110.0), 0.0001, "the posts spread over acolyte_arc_deg")
	t.ok(WardenLogic.acolyte_posts(c, Vector2(100, 400), 1, 100.0, 90.0)[0].is_equal_approx(Vector2(600, 400)), "a lone acolyte stands straight behind")
	t.ok(WardenLogic.acolyte_posts(c, c, 0, 100.0, 90.0).is_empty(), "no acolytes, no posts")
	t.near(WardenLogic.ward_mult(sp3, 3), float(at["ward_mult"]), 0.000001, "warded while acolytes live")
	t.near(WardenLogic.ward_mult(sp3, 1), float(at["ward_mult"]), 0.000001, "one acolyte still wards it")
	t.near(WardenLogic.ward_mult(sp3, 0), 1.0, 0.000001, "exposed once they are gone")
	var th := float(wp["threshold"])
	t.ok(WardenLogic.is_snuffer(sp3, th) and not WardenLogic.is_snuffer(sp3, th - 0.1), "power at the threshold snuffs, under it does not")
	t.ok(not WardenLogic.is_snuffer(WardenLogic.spec({"id": "old-sluice", "tier": 2}, cfg), 99.0), "no other warden is snuffed")
	t.ok(WardenLogic.nearest_index(Vector2.ZERO, [Vector2(50, 0), Vector2(0, 20), Vector2(-20, 0)]) == 1, "the nearest acolyte")
	t.ok(WardenLogic.nearest_index(Vector2.ZERO, [Vector2(30, 0), Vector2(0, 30)]) == 0, "a tie goes to the lower index")
	t.ok(WardenLogic.nearest_index(Vector2.ZERO, []) == -1, "none: -1")

	t.suite("pyre_phase")
	t.ok(WardenLogic.pyre_phase(sp3, 3, 1.0) == 0 and WardenLogic.pyre_phase(sp3, 1, 0.1) == 0, "phase 1 while any acolyte lives, whatever its hp")
	t.ok(WardenLogic.pyre_phase(sp3, 0, 1.0) == 1 and WardenLogic.pyre_phase(sp3, 0, 0.41) == 1, "exposed: phase 2 above the gate")
	t.ok(WardenLogic.pyre_phase(sp3, 0, 0.4) == 2 and WardenLogic.pyre_phase(sp3, 0, 0.0) == 2, "phase 3 at the hp gate")
	t.ok(WardenLogic.pyre_phase(sp3, 0, 0.2) == 2, "hp past the gate while warded: straight to phase 3 when exposed")
	var k0 := WardenLogic.pyre_phase_knobs(sp3, 0)
	t.ok(float(k0["period_beats"]) == float(ph[0]["period_beats"]) and float(k0["burn_radius_px"]) == float(ph[0]["burn_radius_px"]) and int(k0["areas"]) == 1,
		"the phase's knobs")
	t.ok(WardenLogic.pyre_phase_knobs(sp3, 9) == WardenLogic.pyre_phase_knobs(sp3, 2), "pyre_phase_knobs clamps the phase")

	t.suite("pyre_burn_count")
	var per := int(at["areas_per_acolyte"])
	t.ok(WardenLogic.burn_count(sp3, 0, 3) == 1 + 2 * per, "three acolytes: its own fire and one more for each beyond the first")
	t.ok(WardenLogic.burn_count(sp3, 0, 2) == 1 + per and WardenLogic.burn_count(sp3, 0, 1) == 1, "each acolyte that falls takes a fire away")
	t.ok(WardenLogic.burn_count(sp3, 1, 0) == 1, "exposed: its own fire only")
	t.ok(WardenLogic.burn_aim_relish(sp3, 0, 3) == mini(2 * per, int(at["relish_areas_max"])) and WardenLogic.burn_aim_relish(sp3, 0, 1) == 0
		and WardenLogic.burn_aim_relish(sp3, 1, 0) == 0, "the acolytes' fires aim at Relish; the priest's own never does")
	var capped := sp4.duplicate(true)
	capped["attack"]["relish_areas_max"] = 1
	t.ok(WardenLogic.burn_aim_relish(capped, 0, 4) == 1 and WardenLogic.burn_count(capped, 0, 4) == 4, "relish_areas_max caps the fires on her (the rest go on essence)")
	t.ok(WardenLogic.pyre_label(sp3, 0, 3).contains("warded ×%s" % str(at["ward_mult"])) and WardenLogic.pyre_label(sp3, 0, 3).contains("3 fires every 4 beats")
		and WardenLogic.pyre_label(sp3, 0, 3).contains("2 at Relish"), "the HUD's pyre line while warded: " + WardenLogic.pyre_label(sp3, 0, 3))
	t.ok(WardenLogic.pyre_label(sp3, 1, 0) == "exposed · 1 fire every 3 beats", "and once exposed: " + WardenLogic.pyre_label(sp3, 1, 0))

	t.suite("pyre_burn_pick")
	var cands := [Vector2(0, 0), Vector2(10, 0), Vector2(20, 0), Vector2(300, 0), Vector2(305, 0)]
	var w1 := [1.0, 1.0, 1.0, 1.0, 1.0]
	var pk := WardenLogic.burn_pick(cands, w1, 15.0, Vector2(400, 0), 1)
	t.ok(pk.size() == 1 and pk[0] == Vector2(10, 0), "the densest cluster wins (three covered from its middle mote)")
	var pk2 := WardenLogic.burn_pick(cands, w1, 15.0, Vector2(400, 0), 3)
	t.ok(pk2.size() == 2 and pk2[1] == Vector2(305, 0), "the next pick covers what is left; nothing left, no third")
	var pkw := WardenLogic.burn_pick(cands, [1.0, 1.0, 1.0, 2.0, 2.0], 15.0, Vector2(400, 0), 1)
	t.ok(pkw[0] == Vector2(305, 0), "weight counts: two piles at 2 outweigh three motes (tie broken toward the priest)")
	var tie := WardenLogic.burn_pick([Vector2(0, 0), Vector2(200, 0)], [1.0, 1.0], 30.0, Vector2(190, 0), 1)
	t.ok(tie[0] == Vector2(200, 0), "a tie goes to the candidate nearest the priest")
	t.ok(WardenLogic.burn_pick([], [], 30.0, Vector2.ZERO, 2).is_empty(), "nothing to burn: no area")
	t.ok(WardenLogic.burn_pick(cands, w1, 30.0, Vector2(400, 0), 2) == WardenLogic.burn_pick(cands, w1, 30.0, Vector2(400, 0), 2), "burn_pick is deterministic")
	var rs := WardenLogic.relish_spots(Vector2(100, 0), Vector2.ZERO, 3, 60.0)
	t.ok(rs.size() == 3 and rs[0] == Vector2(100, 0) and rs[1].is_equal_approx(Vector2(160, 0)) and rs[2].is_equal_approx(Vector2(40, 0)),
		"on her, then spread round her from the bearing away from the priest: %s" % str(rs))
	t.ok(WardenLogic.relish_spots(Vector2(100, 0), Vector2.ZERO, 0, 60.0).is_empty(), "none asked, none placed")
	var field := {"motes": [Vector2(200, 0), Vector2(210, 0)], "piles": [], "relish": Vector2(0, 300)}
	var plan := WardenLogic.burn_plan(sp3, 0, 3, Vector2.ZERO, field)
	t.ok(plan.size() == 3 and plan[0] == Vector2(200, 0) and plan[1] == Vector2(0, 300), "warded, three acolytes: one on the essence, two on Relish: %s" % str(plan))
	field["relish"] = Vector2.INF
	var plan2 := WardenLogic.burn_plan(sp3, 0, 3, Vector2.ZERO, field)
	t.ok(plan2.size() == 1, "Relish out of reach: the fire goes on what burns (one cluster, so one area)")
	var plan3 := WardenLogic.burn_plan(sp3, 1, 0, Vector2.ZERO, {"motes": [], "piles": [Vector2(5, 5)], "relish": Vector2(0, 300)})
	t.ok(plan3.size() == 1 and plan3[0] == Vector2(5, 5), "exposed: its own fire on a corpse pile, none on her")
	t.ok(WardenLogic.burn_plan(sp3, 1, 0, Vector2.ZERO, {"motes": [], "piles": [], "relish": Vector2(0, 300)}).is_empty(), "nothing to burn and no acolytes: no fire")
	t.ok(WardenLogic.in_burn(Vector2(80, 0), [Vector2.ZERO], 72.0, 8.0) and not WardenLogic.in_burn(Vector2(81, 0), [Vector2.ZERO], 72.0, 8.0),
		"a target touching the circle is inside it (its radius counts)")
	t.ok(not WardenLogic.in_burn(Vector2.ZERO, [], 72.0, 8.0), "no areas, no fire")
	t.near(WardenLogic.pile_after_burn(6.0, 0.5, 0.5), 3.0, 0.000001, "a pile loses pile_burn_frac of its mass")
	t.near(WardenLogic.pile_after_burn(0.8, 0.5, 0.5), 0.0, 0.000001, "and burns away under pile_min_mass")

	t.suite("pyre_meter")
	var total := int(cfg["wardens"]["meter_pips"])
	var ppa := int(cfg["wardens"]["pyre_pips_per_acolyte"])
	var m3 := WardenLogic.pyre_meter(sp3, total, ppa)
	t.ok(int(m3["n"]) == total and int(m3["hp_pips"]) == total - 3 * ppa and m3["notches"] == [int(m3["hp_per"]), int(m3["hp_pips"])],
		"tier 3: %d pips, its hp's %d notched at the gate, then %d per acolyte: %s" % [total, int(m3["hp_pips"]), ppa, str(m3["notches"])])
	var m4 := WardenLogic.pyre_meter(sp4, total, ppa)
	t.ok(int(m4["n"]) == total and int(m4["hp_pips"]) == total - 4 * ppa, "tier 4: four acolytes' bands, the rest its hp")
	t.ok(WardenLogic.pyre_meter_lit(m3, 3, 1.0) == total and WardenLogic.pyre_meter_lit(m3, 0, 0.0) == 0, "full and empty")
	t.ok(WardenLogic.pyre_meter_lit(m3, 2, 1.0) == total - ppa, "an acolyte's fall drops its band")
	t.ok(WardenLogic.pyre_meter_lit(m3, 0, 1.0) == int(m3["hp_pips"]), "all fallen: its hp's pips left (the notch)")
	var mono := true
	var agree := true
	var prev := total + 1
	for kk in range(1000, -1, -1):
		var f := kk / 1000.0
		var lit := WardenLogic.pyre_meter_lit(m3, 0, f)
		mono = mono and lit <= prev
		prev = lit
		var by_meter := 1 if lit > int(m3["hp_per"]) else 2
		agree = agree and (by_meter == WardenLogic.pyre_phase(sp3, 0, f) or lit == 0)
	t.ok(mono, "exposed, the meter never relights as hp falls")
	t.ok(agree, "the hp notch is crossed on the hit that makes phase 3")

	# per-pip lit: hp pips are a prefix of [0, hp_pips), acolyte pips a prefix of [hp_pips, n)
	var hp_pips := int(m3["hp_pips"])
	var part_ok := true
	var part_hp := 0
	for i in hp_pips:
		part_ok = part_ok and (WardenLogic.pyre_pip_lit(m3, i, 3, 0.8) == (i < WardenLogic.meter_lit(m3["hp_bands"], int(m3["hp_per"]), 0.8)))
		part_hp += 1 if WardenLogic.pyre_pip_lit(m3, i, 3, 0.8) else 0
	for i in range(hp_pips, total):
		part_ok = part_ok and WardenLogic.pyre_pip_lit(m3, i, 3, 0.8)
	t.ok(part_ok and part_hp < hp_pips and part_hp > 0, "partial hp, three acolytes alive: every acolyte pip stays lit, only hp pips go dark (%d of %d hp pips)" % [part_hp, hp_pips])
	var after2 := true
	for i in range(hp_pips, total):
		after2 = after2 and (WardenLogic.pyre_pip_lit(m3, i, 2, 0.8) == (i - hp_pips < 2 * ppa))
	t.ok(after2, "two acolytes living: the right-hand band is dark, the others lit")
	var sn := WardenLogic.pyre_snuff_pips(m3, 3, 2)
	t.ok(sn == Vector2i(hp_pips + 2 * ppa, hp_pips + 3 * ppa), "a snuff of the last of three marks the right-most acolyte band: %s" % str(sn))
	var sn2 := WardenLogic.pyre_snuff_pips(m3, 2, 1)
	t.ok(sn2 == Vector2i(hp_pips + ppa, hp_pips + 2 * ppa) and sn2.y <= total and sn2.x >= hp_pips, "the next snuff marks the band before it, never an hp pip")
	var ph_ok := true
	for kk in range(1000, -1, -1):
		var f2 := kk / 1000.0
		var lit_hp := 0
		for i in hp_pips:
			lit_hp += 1 if WardenLogic.pyre_pip_lit(m3, i, 0, f2) else 0
		var by_hp := 1 if lit_hp > int(m3["hp_per"]) else 2
		ph_ok = ph_ok and (by_hp == WardenLogic.pyre_phase(sp3, 0, f2) or lit_hp == 0)
	t.ok(ph_ok, "past the phase-3 notch the hp pips left are within the last band, whatever the acolytes")
	var pre_ok := true
	for kk in range(1000, -1, -1):
		var f3 := kk / 1000.0
		for lv in 4:
			var seen_dark := false
			for i in total:
				var on := WardenLogic.pyre_pip_lit(m3, i, lv, f3)
				if i == hp_pips:
					seen_dark = false
				if on and seen_dark:
					pre_ok = false
				if not on:
					seen_dark = true
	t.ok(pre_ok, "each band is a prefix: no lit pip after a dark one within its own band")

	t.suite("pyre_step_off")
	var room := Rect2(0, 0, 600, 600)
	var ar := [Vector2(300, 300)]
	t.ok(WardenLogic.burn_exit(Vector2(100, 100), ar, 72.0, 29.0, room, 21.0) == Vector2(100, 100), "outside the fire: stay")
	var ex := WardenLogic.burn_exit(Vector2(320, 300), ar, 72.0, 29.0, room, 21.0)
	t.ok(not WardenLogic.in_burn(ex, ar, 72.0, 29.0) and ex.x > 300.0 and absf(ex.y - 300.0) < 1.0, "inside: straight out the near side (%s)" % str(ex))
	var three := WardenLogic.relish_spots(Vector2(300, 300), Vector2(300, 100), 3, 60.0)
	var ex3 := WardenLogic.burn_exit(Vector2(300, 300), three, 72.0, 29.0, room, 21.0)
	t.ok(not WardenLogic.in_burn(ex3, three, 72.0, 29.0) and room.grow(-21.0).has_point(ex3), "three fires round her: a point clear of all of them, in the room (%s)" % str(ex3))
	var wall := WardenLogic.burn_exit(Vector2(30, 300), [Vector2(30, 300)], 72.0, 29.0, room, 21.0)
	t.ok(wall.x >= 21.0 and not WardenLogic.in_burn(wall, [Vector2(30, 300)], 72.0, 29.0), "against a wall it steps off along the room, not through it")


func _shield_tests(t: TestUtil, cfg: Dictionary) -> void:
	t.suite("shieldwall_plant")
	var swept := true
	var turned_in_tell := false
	var started := false
	for k in range(0, 1001):
		var bb := 3.0 + float(k) * 0.01   # one beat before the tell, through the bash beat (5.0), and 5 more
		var turns := WardenLogic.shield_turns(bb, 5.0, 1.0)
		if bb >= 4.0 and bb <= 5.5:
			swept = swept and not turns
		turned_in_tell = turned_in_tell or (turns and WardenLogic.is_tell(bb, 5.0, 1.0))
		started = started or (turns and bb < 4.0)
	t.ok(swept and not turned_in_tell, "no turn from the first tell frame through the bash frame: the bash lands on the lit arc")
	t.ok(started, "it still turns before the tell")
	t.ok(not WardenLogic.shield_turns(5.0, 5.0, 1.0) and WardenLogic.shield_turns(3.99, 5.0, 1.0), "the frame at the attack beat is planted too")
	var sw_src := FileAccess.get_file_as_string("res://scripts/raid/warden_shieldwall.gd")
	var step_i := sw_src.find("func _step(")
	var step_body := sw_src.substr(step_i, sw_src.find("\nfunc ", step_i + 1) - step_i)
	t.ok(step_body.contains("if WardenLogic.shield_turns(") and step_body.find("turn_step(") < step_body.find("_bash(ph, at)"),
		"_step turns only under shield_turns, before the bash call")

	t.suite("shieldwall_config")
	var archs: Dictionary = cfg["wardens"]["archetypes"]
	var a: Dictionary = archs["shieldwall"]
	var by_fort: Dictionary = cfg["wardens"]["by_fort"]
	t.ok(by_fort["pale-bastion"] == "shieldwall" and by_fort["the-stair"] == "shieldwall", "pale-bastion (t3) and the-stair (t4) are the Shieldwall")
	t.ok(by_fort["hollow-redoubt"] == "huntsman" and by_fort["sable-hold"] == "bellringer", "the other tier 3-4 forts keep their wardens")
	t.ok(str(a.get("_doc", "")) != "" and str(a["name"]) == "The Shieldwall", "the Shieldwall is documented and named")
	var wp: Dictionary = a["weak_point"]
	t.ok(wp["stat"] == "wits" and wp["effect"] == "flank", "its weak point is wits, effect flank")
	var prof3: Array = cfg["autopilot"]["party_profiles"]["3"]["party"]
	var meets := false
	for e in prof3:
		meets = meets or float(e["stats"]["wits"]) >= float(wp["threshold"])
	t.ok(meets, "a standard tier-3 party big meets the wits threshold (%s)" % str(wp["threshold"]))
	var ph: Array = a["phases"]
	var faster := true
	for i in range(1, ph.size()):
		faster = faster and float(ph[i]["turn_deg_s"]) > float(ph[i - 1]["turn_deg_s"]) \
			and float(ph[i]["front_half_deg"]) >= float(ph[i - 1]["front_half_deg"]) \
			and float(ph[i]["period_beats"]) < float(ph[i - 1]["period_beats"])
	t.ok(ph.size() == 3 and faster, "each phase turns faster, keeps or widens the arc and bashes sooner")
	t.ok(float(a["attack"]["tell_beats"]) < float(ph[ph.size() - 1]["period_beats"]), "the bash tell fits inside the fastest period")
	t.ok(float(a["attack"]["front_mult"]) < 0.5 and float(a["attack"]["back_mult"]) >= 1.0, "the shield glances, the back lands in full")
	t.ok(float(a["attack"]["reach_px"]) > float(a["radius"]), "the bash reaches past the wall's body")
	t.ok(not str(a["attack"].keys()).contains("dmg_mult"), "no multiplier is named dmg_ (the first dungeon would scale it)")
	var sw := WardenLogic.spec({"id": "pale-bastion", "tier": 3}, cfg)
	t.ok(sw["archetype"] == "shieldwall" and WardenLogic.meter_bands(sw).size() == 4, "the Shieldwall's meter is notched at its hp thirds")
	t.near(float(sw["hp"]), float(a["hp_base"]) + 3.0 * float(a["hp_per_tier"]), 0.001, "shieldwall hp at tier 3")
	var swf := WardenLogic.spec({"id": "x", "tier": 1, "archetype": "shieldwall", "first_dungeon": true}, cfg)
	t.ok(WardenLogic.period_beats(swf, 0) > WardenLogic.period_beats(sw, 0) and float(swf["attack"]["dmg_unit"]) < float(sw["attack"]["dmg_unit"])
		and float(swf["attack"]["front_mult"]) == float(sw["attack"]["front_mult"]), "a first-dungeon Shieldwall bashes slower and softer; its shield is the same")
	var exp := {1.0: 0, 0.67: 0, 0.66: 1, 0.34: 1, 0.33: 2, 0.0: 2}
	var ph_ok := true
	for hf in exp.keys():
		ph_ok = ph_ok and WardenLogic.bellringer_phase(sw, hf) == exp[hf]
	t.ok(ph_ok, "its phases are hp thirds")
	t.near(float(WardenLogic.shield_phase(sw, 9)["turn_deg_s"]), float(ph[2]["turn_deg_s"]), 0.0001, "shield_phase clamps the phase")
	var lab := WardenLogic.shield_label(sw, 0)
	t.ok(lab.contains("±%d°" % int(ph[0]["front_half_deg"])) and lab.contains("%d°/s" % int(ph[0]["turn_deg_s"])) and lab.contains("glances ×0.1")
		and lab.contains("back ×%s" % str(a["attack"]["back_mult"])) and lab.contains("every 4 beats"), "the HUD's shield line comes from the spec: " + lab)
	t.ok(WardenLogic.shield_label(sw, 2).contains("every 2 beats"), "the shield line follows the phase")

	t.suite("shieldwall_arc")
	var o := Vector2(100, 100)
	t.ok(WardenLogic.in_front(0.0, o, Vector2(200, 100), 70.0), "straight ahead is front")
	t.ok(WardenLogic.in_front(0.0, o, o + Vector2(100, 0).rotated(deg_to_rad(70.0)), 70.0), "the arc's edge counts as front")
	t.ok(not WardenLogic.in_front(0.0, o, o + Vector2(100, 0).rotated(deg_to_rad(71.0)), 70.0), "just past the edge is not")
	t.ok(not WardenLogic.in_front(0.0, o, Vector2(0, 100), 70.0), "straight behind is not front")
	t.ok(WardenLogic.in_front(deg_to_rad(175.0), o, o + Vector2(100, 0).rotated(deg_to_rad(-175.0)), 20.0), "the arc wraps across ±180° (175° facing, -175° attacker)")
	t.ok(not WardenLogic.in_front(deg_to_rad(175.0), o, o + Vector2(100, 0).rotated(deg_to_rad(150.0)), 20.0), "25° off across the wrap is outside a ±20° arc")
	t.ok(WardenLogic.in_front(1.0, o, o, 10.0), "a point on the centre counts as front")
	t.ok(WardenLogic.in_front(0.0, o, Vector2(0, 100), 180.0), "a ±180° arc covers everything")
	t.near(WardenLogic.angle_diff(deg_to_rad(170.0), deg_to_rad(-170.0)), deg_to_rad(20.0), 0.000001, "angle_diff takes the short way across ±180°")
	t.near(WardenLogic.shield_mult(sw, "front"), float(a["attack"]["front_mult"]), 0.000001, "a hit on the shield glances at front_mult")
	t.near(WardenLogic.shield_mult(sw, "side"), 1.0, 0.000001, "a hit from the side lands in full")
	t.near(WardenLogic.shield_mult(sw, "back"), float(a["attack"]["back_mult"]), 0.000001, "a hit in the open back takes back_mult")
	t.ok(WardenLogic.shield_zone(0.0, o, o + Vector2(80, 10), 70.0, 50.0) == "front", "zone: ahead is the front")
	t.ok(WardenLogic.shield_zone(0.0, o, o + Vector2(0, 80), 70.0, 50.0) == "side", "zone: square to the facing is the side")
	t.ok(WardenLogic.shield_zone(0.0, o, o + Vector2(-80, 30), 70.0, 50.0) == "back", "zone: behind is the back")
	t.ok(WardenLogic.shield_zone(0.0, o, o + Vector2(100, 0).rotated(deg_to_rad(129.0)), 70.0, 50.0) == "side"
		and WardenLogic.shield_zone(0.0, o, o + Vector2(100, 0).rotated(deg_to_rad(131.0)), 70.0, 50.0) == "back", "zone: the back arc starts back_half_deg from the rear")
	t.ok(WardenLogic.shield_zone(0.0, o, o + Vector2(100, 0).rotated(deg_to_rad(100.0)), 120.0, 80.0) == "front", "zone: where the arcs overlap the shield wins")
	t.ok(float(a["attack"]["back_half_deg"]) + float(ph[ph.size() - 1]["front_half_deg"]) <= 180.0, "the back arc and the widest front arc never overlap")
	t.ok(WardenLogic.bash_hits(0.0, o, o + Vector2(140, 0), 70.0, 140.0, 0.0), "the bash reaches reach_px ahead")
	t.ok(WardenLogic.bash_hits(0.0, o, o + Vector2(150, 0), 70.0, 140.0, 10.0), "a target's radius counts")
	t.ok(not WardenLogic.bash_hits(0.0, o, o + Vector2(150, 0), 70.0, 140.0, 5.0), "beyond reach + radius is safe")
	t.ok(not WardenLogic.bash_hits(0.0, o, o + Vector2(-60, 0), 70.0, 140.0, 10.0), "behind it is safe however close")
	t.ok(WardenLogic.shove_point(0.0, o, o + Vector2(0, 60), 50.0).is_equal_approx(o + Vector2(0, 110)), "a shove pushes straight away from the wall")
	t.ok(WardenLogic.shove_point(PI, o, o, 50.0).is_equal_approx(o + Vector2(-50, 0)), "a target on the centre is shoved along the facing")

	t.suite("shieldwall_turn")
	t.near(WardenLogic.turn_step(0.0, 1.0, 45.0, 0.1), deg_to_rad(4.5), 0.000001, "a step turns at most rate x delta")
	t.near(WardenLogic.turn_step(0.0, 0.05, 45.0, 0.1), 0.05, 0.000001, "a step never overshoots the goal")
	t.near(WardenLogic.turn_step(deg_to_rad(170.0), deg_to_rad(-170.0), 90.0, 0.1), deg_to_rad(179.0), 0.000001, "it turns the short way across ±180°")
	var across := WardenLogic.turn_step(deg_to_rad(178.0), deg_to_rad(-170.0), 90.0, 0.1)
	t.near(WardenLogic.angle_diff(across, deg_to_rad(-173.0)), 0.0, 0.000001, "a step through 180° wraps to the other sign (178° + 9° is -173°)")
	var f := 0.0
	for k in 600:
		f = WardenLogic.turn_step(f, PI * 0.5, 40.0, 1.0 / 60.0)
	t.near(f, PI * 0.5, 0.000001, "it settles on the goal and holds")
	t.near(WardenLogic.turn_step(1.0, 2.0, 45.0, 0.0), 1.0, 0.000001, "no time, no turn")

	t.suite("shieldwall_goal")
	var c := Vector2(0, 0)
	var crowd := [Vector2(100, 0), Vector2(100, 10), Vector2(100, -10), Vector2(-100, 0)]
	var g := WardenLogic.shield_goal(c, crowd, 240.0, 70.0, PI)
	t.ok(bool(g["ok"]) and int(g["count"]) == 3 and absf(float(g["angle"])) < 0.01, "it turns to the crowd of three, not the one behind it (facing it)")
	t.ok(not bool(WardenLogic.shield_goal(c, [Vector2(400, 0)], 240.0, 70.0, 0.0)["ok"]), "undead beyond reach do not count")
	t.ok(not bool(WardenLogic.shield_goal(c, [], 240.0, 70.0, 0.0)["ok"]), "no undead: no goal (the caller holds or faces Relish)")
	var ring: Array = []
	for k in 8:
		ring.append(Vector2(100, 0).rotated(TAU * k / 8.0))
	var g1 := WardenLogic.shield_goal(c, ring, 240.0, 70.0, deg_to_rad(44.0))
	var g2 := WardenLogic.shield_goal(c, ring, 240.0, 70.0, deg_to_rad(-91.0))
	t.ok(absf(WardenLogic.angle_diff(float(g1["angle"]), deg_to_rad(45.0))) < 0.01 and absf(WardenLogic.angle_diff(float(g2["angle"]), deg_to_rad(-90.0))) < 0.01,
		"an even ring holds the facing (the tie goes to the bearing nearest it)")
	t.ok(WardenLogic.shield_goal(c, crowd, 240.0, 70.0, 0.3) == WardenLogic.shield_goal(c, crowd, 240.0, 70.0, 0.3), "shield_goal is deterministic")
	var wrap := WardenLogic.shield_goal(c, [Vector2(-100, 5), Vector2(-100, -5)], 240.0, 30.0, 0.0)
	t.ok(absf(absf(float(wrap["angle"])) - PI) < 0.01 and int(wrap["count"]) == 2, "a crowd astride ±180° is one crowd")

	t.suite("shieldwall_flank")
	t.ok(WardenLogic.is_flanker(sw, float(wp["threshold"])) and not WardenLogic.is_flanker(sw, float(wp["threshold"]) - 0.1), "wits at the threshold flanks, under it does not")
	var bellsp := WardenLogic.spec({"id": "old-sluice", "tier": 2}, cfg)
	t.ok(not WardenLogic.is_flanker(bellsp, 99.0), "no other warden has flankers")
	t.near(WardenLogic.flank_angle(0.0, 0, 1, 34.0), -PI, 0.000001, "a lone flanker's post is straight behind")
	var fa := WardenLogic.flank_angle(0.0, 0, 2, 34.0)
	var fb := WardenLogic.flank_angle(0.0, 1, 2, 34.0)
	t.near(absf(WardenLogic.angle_diff(fa, fb)), deg_to_rad(34.0), 0.000001, "two flankers spread flank_spread_deg apart")
	t.near(WardenLogic.angle_diff(fa + WardenLogic.angle_diff(fa, fb) * 0.5, PI), 0.0, 0.000001, "the spread is centred on the back")
	var post := WardenLogic.flank_angle(0.0, 0, 1, 34.0)
	var near := WardenLogic.flank_step(c, Vector2(-80, 10), post, 70.0, 40.0)
	t.ok(near.is_equal_approx(Vector2(-70, 0)), "near its post it goes straight to it")
	var far := WardenLogic.flank_step(c, Vector2(90, 0), post, 70.0, 40.0)
	t.near(far.length(), 70.0, 0.001, "far from its post it steps along the orbit")
	t.near(absf(far.angle()), deg_to_rad(40.0), 0.0001, "one flank_step_deg at a time (round the wall, not through it)")
	var side := WardenLogic.flank_step(c, Vector2(0, 90), post, 70.0, 40.0)
	t.ok(side.y > 0.0 and side.x < 0.0, "it goes round the shorter way")
	var p0 := Vector2(90, 1)
	var steps := 0
	while p0.distance_to(Vector2(-70, 0)) > 0.5 and steps < 20:
		p0 = WardenLogic.flank_step(c, p0, post, 70.0, 40.0)
		steps += 1
	t.ok(steps <= 6, "from the front it reaches its post in a few orbit steps (%d)" % steps)


func _hunt_tests(t: TestUtil) -> void:
	t.suite("huntsman_hunt_target")
	var room := Rect2(100, 100, 400, 300)
	var units: Array = [Vector2(300, 200), Vector2(450, 350), Vector2(900, 900)]
	var h := WardenLogic.hunt_target(room, Vector2(300, 300), true, units, Vector2(200, 200), 40.0)
	t.ok(h["kind"] == "relish" and (h["pos"] as Vector2) == Vector2(300, 300), "Relish in the room: it hunts her")
	h = WardenLogic.hunt_target(room, Vector2(900, 100), true, units, Vector2(200, 200), 40.0)
	t.ok(h["kind"] == "undead" and int(h["index"]) == 0 and (h["pos"] as Vector2) == Vector2(300, 200), "Relish out: the nearest undead in the room")
	h = WardenLogic.hunt_target(room, Vector2(900, 100), true, units, Vector2(440, 340), 40.0)
	t.ok(h["kind"] == "undead" and int(h["index"]) == 1, "nearest to the Huntsman, not to Relish")
	h = WardenLogic.hunt_target(room, Vector2(900, 100), true, [Vector2(520, 250)], Vector2(300, 250), 40.0)
	t.ok(h["kind"] == "undead", "an undead entering through the doorway band is a target")
	h = WardenLogic.hunt_target(room, Vector2(900, 100), true, [Vector2(560, 250)], Vector2(300, 250), 40.0)
	t.ok(h["kind"] == "none", "an undead beyond the margin is not")
	h = WardenLogic.hunt_target(room, Vector2(900, 100), true, [], Vector2(300, 250), 40.0)
	t.ok(h["kind"] == "none" and int(h["index"]) == -1, "nobody to hunt: none")
	h = WardenLogic.hunt_target(room, Vector2(300, 300), false, [Vector2(300, 200)], Vector2(200, 200), 40.0)
	t.ok(h["kind"] == "undead", "a dead Relish is not hunted")
	h = WardenLogic.hunt_target(room, Vector2(520, 250), true, units, Vector2(200, 200), 40.0)
	t.ok(h["kind"] == "undead", "Relish in the doorway band (outside the room proper) is not hunted")


func _window_tests(t: TestUtil, tempo_s: float) -> void:
	t.suite("slam_window")
	t.ok(WardenLogic.slam_window_open(5.0, 0.0, 240.0, tempo_s, 1.5), "a far-off slam with no walk to leave: open")
	t.ok(not WardenLogic.slam_window_open(1.0, 0.0, 240.0, tempo_s, 1.5), "inside the safe margin: closed")
	t.ok(not WardenLogic.slam_window_open(-1.0, 0.0, 240.0, tempo_s, 1.5), "a slam in flight (negative beats): closed")
	var near_open := WardenLogic.slam_window_open(3.0, 0.0, 240.0, tempo_s, 1.5)
	var far_closed := WardenLogic.slam_window_open(3.0, 800.0, 240.0, tempo_s, 1.5)
	t.ok(near_open and not far_closed, "the walk out is subtracted from the time left")
	t.ok(WardenLogic.slam_window_open(2.0, 100.0, 240.0, tempo_s, 0.0), "zero margin reduces to the walk out alone")


func _meter_tests(t: TestUtil, cfg: Dictionary) -> void:
	t.suite("break_meter")
	var total := int(cfg["wardens"].get("meter_pips", 12))
	var bell := WardenLogic.spec({"id": "old-sluice", "tier": 2}, cfg)
	var hunt := WardenLogic.spec({"id": "ashgate", "tier": 1}, cfg)   # tier 1: no pack, so no horn notches
	var bb := WardenLogic.meter_bands(bell)
	t.ok(bb.size() == 4 and is_equal_approx(bb[0], 1.0) and is_equal_approx(bb[1], 0.66) and is_equal_approx(bb[2], 0.33) and bb[3] == 0.0,
		"the Bellringer's bands are its phase hp gates: %s" % str(bb))
	var bp := WardenLogic.meter_per_band(bb, total)
	t.ok(bp * 3 == total, "%d pips share evenly over three phases (%d each)" % [total, bp])
	t.ok(WardenLogic.meter_notches(bb, bp) == [bp, bp * 2], "notches sit between the phase segments")
	t.ok(WardenLogic.meter_lit(bb, bp, 1.0) == total, "full hp lights every pip")
	t.ok(WardenLogic.meter_lit(bb, bp, 0.0) == 0, "no hp lights none")
	t.ok(WardenLogic.meter_lit(bb, bp, 0.001) == 1, "a sliver of hp keeps one pip")
	t.ok(WardenLogic.meter_lit(bb, bp, 0.999) == total, "a scratch takes no pip")
	# the notch is crossed on exactly the hit that changes the phase
	var agree := true
	var mono := true
	var prev := total + 1
	for k in range(1000, -1, -1):
		var f := k / 1000.0
		var lit := WardenLogic.meter_lit(bb, bp, f)
		var ph := WardenLogic.bellringer_phase(bell, f)
		var by_meter := 0 if lit > bp * 2 else (1 if lit > bp else 2)
		agree = agree and (by_meter == ph or lit == 0)
		mono = mono and lit <= prev
		prev = lit
	t.ok(agree, "every hp from 1 to 0: the meter's segment is bellringer_phase")
	t.ok(mono, "the meter never relights as hp falls")
	t.ok(WardenLogic.meter_lit(bb, bp, 0.6601) == bp * 2 + 1 and WardenLogic.meter_lit(bb, bp, 0.66) == bp * 2,
		"0.66 is the notch: one pip above it at 0.6601, on it at 0.66")
	var hb := WardenLogic.meter_bands(hunt)
	t.ok(hb.size() == 2, "the Huntsman (phased by catches) gets one flat band")
	var hp := WardenLogic.meter_per_band(hb, total)
	t.ok(hp == total and WardenLogic.meter_notches(hb, hp).is_empty(), "no notches on its strength")
	t.ok(WardenLogic.meter_lit(hb, hp, 0.5) == total / 2 and WardenLogic.meter_lit(hb, hp, 0.51) == total / 2 + 1, "flat meter is the ceiling of hp x pips")
	t.ok(WardenLogic.catch_notches(hunt) == [2, 4], "the Huntsman's notches are on its catches (2, 4)")
	var cl := WardenLogic.catch_label(hunt)
	t.ok(cl.contains("costs Relish 12 hp") and cl.contains("at 2 and 4 catches"), "the CAUGHT label states the cost and the thresholds from the spec: " + cl)
	var hunt_first := WardenLogic.spec({"id": "x", "tier": 1, "archetype": "huntsman", "first_dungeon": true}, cfg)
	t.ok(WardenLogic.catch_label(hunt_first).contains("costs Relish 7 hp"), "the first dungeon's softer catch is the label's number (7)")
	t.ok(WardenLogic.catch_label(bell) == "", "the Bellringer has no catch label")
	t.ok(WardenLogic.catch_slots(hunt) == 6, "the CAUGHT track shows the open last phase (6 slots)")
	t.ok(WardenLogic.catch_notches(bell).is_empty() and WardenLogic.catch_slots(bell) == 0, "the Bellringer has no CAUGHT track")
	var agree2 := true
	for c in 9:
		var nb := 0
		for n in WardenLogic.catch_notches(hunt):
			if c >= n:
				nb += 1
		agree2 = agree2 and nb == WardenLogic.huntsman_phase(hunt, c)
	t.ok(agree2, "catches past n notches = huntsman_phase, for 0..8 catches")
	var first := WardenLogic.spec({"id": "old-sluice", "tier": 1, "first_dungeon": true}, cfg)
	t.ok(WardenLogic.meter_bands(first) == bb, "the first dungeon's Bellringer has the same bands")
