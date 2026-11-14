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
	t.ok(seen.has("bellringer") and seen.has("huntsman"), "both archetypes appear")
	for a in ["bellringer", "huntsman"]:
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
	for a in ["bellringer", "huntsman"]:
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
	return t.failures


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
	var hunt := WardenLogic.spec({"id": "ashgate", "tier": 2}, cfg)
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
