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
	t.near(float(s1["hp"]), 300.0 + 2 * 200.0, 0.001, "bellringer hp at tier 2")
	s1["phases"][0]["period_beats"] = 99.0
	s1["attack"]["dmg_unit"] = 99.0
	s1["tells"].append("x")
	s1["weak_point"]["threshold"] = 99
	var s3 := WardenLogic.spec(fort, cfg)
	t.ok(s3 == s2 and s3["phases"][0]["period_beats"] == 4.0, "mutating a spec never touches the config or the next spec")
	t.ok(float(WardenLogic.spec({"id": "x", "tier": 3}, cfg)["hp"]) > float(WardenLogic.spec({"id": "x", "tier": 1}, cfg)["hp"]), "hp rises with tier")
	for a in ["bellringer", "huntsman"]:
		var n := WardenLogic.spec({"id": "x", "tier": 1, "archetype": a}, cfg)
		var f := WardenLogic.spec({"id": "x", "tier": 1, "archetype": a, "first_dungeon": true}, cfg)
		t.ok(f["first_dungeon"] == true and n["first_dungeon"] == false, "%s: first_dungeon flag is carried" % a)
		t.near(float(f["hp"]), float(n["hp"]) * 0.8, 0.001, "%s: first dungeon hp x0.8" % a)
		var per_ok := true
		for i in n["phases"].size():
			per_ok = per_ok and absf(float(f["phases"][i]["period_beats"]) - float(n["phases"][i]["period_beats"]) * 1.5) < 0.0001
		t.ok(per_ok, "%s: first dungeon periods x1.5" % a)
		var dmg_ok := true
		var any_dmg := false
		for k in n["attack"].keys():
			if str(k).begins_with("dmg_"):
				any_dmg = true
				dmg_ok = dmg_ok and absf(float(f["attack"][k]) - float(n["attack"][k]) * 0.6) < 0.0001
			else:
				dmg_ok = dmg_ok and f["attack"][k] == n["attack"][k]
		t.ok(any_dmg and dmg_ok, "%s: first dungeon damage x0.6, other attack params untouched" % a)
	t.ok(RaidLogic.warden_spec(fort, cfg) == WardenLogic.spec(fort, cfg), "RaidLogic.warden_spec delegates to WardenLogic.spec")

	t.suite("warden_beats")
	t.near(WardenLogic.beat_of(tempo_s * 2.5, tempo_s), 2.5, 0.0001, "beat_of counts tempos")
	t.near(WardenLogic.beat_of(0.0, tempo_s), 0.0, 0.0001, "beat_of starts at 0")
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
	t.near(WardenLogic.period_beats(bf, 0), 6.0, 0.0001, "first dungeon: slow slams (4 -> 6 beats)")

	t.suite("warden_slam")
	t.near(WardenLogic.slam_radius(bell, 0.0), 0.0, 0.0001, "ring starts at 0")
	t.near(WardenLogic.slam_radius(bell, 0.3), 180.0, 0.001, "ring is half grown at half ring_beats")
	t.near(WardenLogic.slam_radius(bell, 0.59), 360.0 * 0.59 / 0.6, 0.001, "ring grows linearly")
	t.near(WardenLogic.slam_radius(bell, 0.6), -1.0, 0.0001, "ring is done at ring_beats")
	t.near(WardenLogic.slam_radius(bell, 5.0), -1.0, 0.0001, "ring stays done")
	var band := 36.0
	var targets := [50.0, 200.0, 359.0]
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
	t.near(WardenLogic.slam_damage(bell, "unit", 0.0, false), 6.0, 0.0001, "unit damage")
	t.near(WardenLogic.slam_damage(bell, "relish", 0.0, false), 9.0, 0.0001, "relish damage")
	t.near(WardenLogic.slam_damage(bell, "big", 0.0, false), 6.0, 0.0001, "big with no beef takes full damage")
	t.near(WardenLogic.slam_damage(bell, "big", 5.0, false), 6.0 * 0.7, 0.0001, "5 beef soaks 30%")
	t.near(WardenLogic.slam_damage(bell, "big", 100.0, false), 6.0 * 0.3, 0.0001, "soak floors at min_soak")
	t.near(WardenLogic.slam_damage(bell, "unit", 99.0, false), 6.0, 0.0001, "beef never soaks small units")
	t.near(WardenLogic.slam_damage(bell, "unit", 0.0, true), 6.0 * 0.35, 0.0001, "muffled unit damage x0.35")
	t.near(WardenLogic.slam_damage(bell, "big", 5.0, true), 6.0 * 0.7 * 0.35, 0.0001, "muffle stacks with soak")
	t.near(WardenLogic.slam_damage(bf, "relish", 0.0, false), 9.0 * 0.6, 0.0001, "first dungeon relish damage x0.6")
	t.ok(WardenLogic.is_muffled(bell, [{"beef": 6.0}]), "beef at the threshold muffles")
	t.ok(not WardenLogic.is_muffled(bell, [{"beef": 5.9}]), "beef under the threshold does not")
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
	t.near(WardenLogic.stun_damage(hunt, 10.0, false), 10.0, 0.0001, "an unstunned Huntsman takes full damage")
	t.near(WardenLogic.stun_damage(hunt, 10.0, true), 15.0, 0.0001, "a stunned Huntsman takes x1.5")
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
	return t.failures
