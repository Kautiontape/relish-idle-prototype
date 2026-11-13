extends RefCounted
## SlabLogic: anatomy slots, assignment, stats, validity, role and name.

const KINDS := ["skeleton", "zombie", "hulk", "siren", "lich", "wraith", "revenant"]


func _r(aspect: String, mag: int, uid := 1) -> Dictionary:
	return {"uid": uid, "aspect": aspect, "rarity": "common", "magnitude": mag}


func run() -> int:
	var t := TestUtil.new()
	t.suite("slab-logic")
	var cfg: Dictionary = TestUtil.configs()["town"]["slab"]

	# --- slots ---------------------------------------------------------------
	var want := {
		"skeleton": ["muscle", "nerve", "nerve"],
		"zombie": ["muscle", "muscle"],
		"hulk": ["muscle", "muscle", "muscle", "nerve"],
		"siren": ["nerve", "presence", "presence", "presence"],
		"lich": ["nerve", "nerve", "nerve", "anima"],
		"wraith": ["nerve", "presence", "presence", "anima"],
		"revenant": ["muscle", "muscle", "presence", "anima", "anima"],
	}
	for k in KINDS:
		t.ok(SlabLogic.slots_for(k, cfg) == want[k], "slots_for %s in group order" % k)
	t.ok(SlabLogic.slots_for("dragon", cfg).is_empty(), "unknown kind has no slots")

	# --- fits ----------------------------------------------------------------
	t.ok(SlabLogic.fits("muscle", "power", cfg) and SlabLogic.fits("muscle", "beef", cfg), "muscle takes power, beef")
	t.ok(not SlabLogic.fits("muscle", "wits", cfg), "muscle rejects wits")
	t.ok(SlabLogic.fits("nerve", "wits", cfg) and SlabLogic.fits("nerve", "speed", cfg), "nerve takes wits, speed")
	t.ok(not SlabLogic.fits("nerve", "power", cfg), "nerve rejects power")
	t.ok(SlabLogic.fits("presence", "presence", cfg), "presence takes presence")
	t.ok(not SlabLogic.fits("presence", "speed", cfg), "presence rejects speed")
	for s in SlabLogic.STATS:
		t.ok(SlabLogic.fits("anima", s, cfg), "anima takes %s" % s)
	t.ok(not SlabLogic.fits("anima", "luck", cfg), "anima rejects a non-stat")
	t.ok(not SlabLogic.fits("bogus", "power", cfg), "unknown group fits nothing")

	# --- stats are sums, valid recipe ----------------------------------------
	var rem := [_r("power", 3, 1), _r("power", 4, 2), _r("wits", 2, 3)]
	var e := SlabLogic.evaluate("skeleton", rem, cfg)
	t.near(float(e["stats"]["power"]), 3.0, 0.001, "skeleton: one muscle slot holds first power only")
	t.near(float(e["stats"]["wits"]), 2.0, 0.001, "skeleton: wits lands in nerve")
	t.ok(e["unplaced"] == [1], "second power remnant is unplaced (no muscle, no anima)")
	t.ok(not e["ok"] and e["reason"] == "invalid_recipe", "unplaced remnant makes it invalid")
	e = SlabLogic.evaluate("hulk", [_r("power", 3), _r("beef", 4), _r("speed", 2)], cfg)
	t.ok(e["ok"] and e["reason"] == "", "hulk with power, beef, speed is ok")
	t.near(float(e["stats"]["power"]), 3.0, 0.001, "power stat")
	t.near(float(e["stats"]["beef"]), 4.0, 0.001, "beef stat")
	t.near(float(e["stats"]["speed"]), 2.0, 0.001, "speed stat")
	t.near(float(e["stats"]["wits"]), 0.0, 0.001, "unused stat is 0")
	t.ok(e["stats"]["power"] is float, "stats are floats")
	t.ok(e["filled"] == 3 and e["slot_count"] == 4 and e["slots"].size() == 4, "filled and slot counts")
	t.ok(e["slots"][0] == {"group": "muscle", "remnant_index": 0}, "first muscle slot holds remnant 0")
	t.ok(e["slots"][1] == {"group": "muscle", "remnant_index": 1}, "second muscle slot holds remnant 1")
	t.ok(e["slots"][2]["remnant_index"] == -1 and e["slots"][3]["remnant_index"] == 2, "empty slot is -1, nerve holds speed")
	t.ok(e["kind"] == "hulk" and e["noun"] == "Hulk", "kind and noun")

	# --- overflow into anima ---------------------------------------------------
	e = SlabLogic.evaluate("lich", [_r("power", 5, 1), _r("power", 5, 2)], cfg)
	t.ok(e["filled"] == 1 and e["unplaced"] == [1], "lich 2 power: 1 in anima, 2nd unplaced")
	t.ok(e["slots"][3]["remnant_index"] == 0, "the anima slot holds remnant 0")
	t.ok(not e["ok"] and e["reason"] == "invalid_recipe", "that is invalid")
	t.near(float(e["stats"]["power"]), 5.0, 0.001, "invalid still previews placed stats")
	t.ok(e["role"] == "brawler" and e["name"] == "Brutal Lich", "invalid still names and roles the placed part")
	e = SlabLogic.evaluate("revenant", [_r("wits", 2, 1), _r("speed", 2, 2), _r("presence", 1, 3)], cfg)
	t.ok(e["ok"] and e["filled"] == 3, "revenant: wits and speed ride in anima")
	e = SlabLogic.evaluate("revenant", [_r("power", 1), _r("power", 1), _r("power", 1), _r("wits", 1)], cfg)
	t.ok(e["ok"] and e["unplaced"].is_empty(), "revenant: third power spills to anima, wits to the other")
	# own group first even if the anima remnant comes earlier in the list
	e = SlabLogic.evaluate("wraith", [_r("wits", 1), _r("presence", 1), _r("presence", 1), _r("presence", 1)], cfg)
	t.ok(e["ok"] and e["slots"][3]["remnant_index"] == 3, "wraith: third presence spills to anima")
	e = SlabLogic.evaluate("lich", [_r("presence", 1), _r("wits", 1), _r("wits", 1), _r("wits", 1)], cfg)
	t.ok(e["ok"], "own group first: presence goes to anima, wits fill nerve")

	# --- invalid cases ---------------------------------------------------------
	e = SlabLogic.evaluate("dragon", [_r("power", 1)], cfg)
	t.ok(not e["ok"] and e["reason"] == "invalid_recipe", "unknown kind invalid")
	e = SlabLogic.evaluate("zombie", [_r("luck", 1), _r("power", 2)], cfg)
	t.ok(not e["ok"] and e["unplaced"] == [0] and e["filled"] == 1, "unknown aspect invalid and unplaced")
	e = SlabLogic.evaluate("zombie", [_r("power", 1), _r("power", 1), _r("power", 1)], cfg)
	t.ok(not e["ok"] and e["unplaced"] == [2], "too many remnants invalid")
	e = SlabLogic.evaluate("zombie", [_r("wits", 1)], cfg)
	t.ok(not e["ok"] and e["unplaced"] == [0] and e["filled"] == 0, "no fit invalid")
	e = SlabLogic.evaluate("zombie", [], cfg)
	t.ok(not e["ok"] and e["reason"] == "invalid_recipe", "zero remnants under min 1 invalid")
	t.ok(e["role"] == "hollow" and e["name"] == "Hollow Zombie", "empty is hollow")

	# --- role --------------------------------------------------------------------
	var role_for := {"power": "brawler", "beef": "bulwark", "wits": "stalker", "presence": "herald", "speed": "skirmisher"}
	for s in role_for:
		e = SlabLogic.evaluate("revenant", [_r(s, 3)], cfg)
		t.ok(e["role"] == role_for[s] and e["dominant"] == s, "dominant %s -> %s" % [s, role_for[s]])
	e = SlabLogic.evaluate("hulk", [_r("beef", 3, 1), _r("power", 3, 2)], cfg)
	t.ok(e["dominant"] == "power" and e["role"] == "brawler", "tie goes to STATS order (power before beef)")
	e = SlabLogic.evaluate("skeleton", [_r("speed", 2, 1), _r("wits", 2, 2)], cfg)
	t.ok(e["dominant"] == "wits", "tie wits vs speed goes to wits")
	e = SlabLogic.evaluate("zombie", [], cfg)
	t.ok(e["dominant"] == "" and e["role_label"] == "Hollow", "no stats: hollow, no dominant")
	e = SlabLogic.evaluate("zombie", [_r("power", 2)], cfg)
	t.ok(e["role_label"] == "Brawler" and e["role_line"] == "Brawler: good for breaking the raw front and a warden's armour", "role label and line")
	t.ok(SlabLogic.role_label("brute", cfg) == "Brute", "legacy role id capitalised")
	t.ok(SlabLogic.role_label("stalker", cfg) == "Stalker", "configured label")

	# --- names -------------------------------------------------------------------
	e = SlabLogic.evaluate("hulk", [_r("power", 10, 1), _r("wits", 5, 2)], cfg)
	t.ok(e["name"] == "Brutal Hulk" and e["adjective"] == "Brutal", "single adjective below 0.6")
	e = SlabLogic.evaluate("hulk", [_r("power", 10, 1), _r("speed", 6, 2)], cfg)
	t.ok(e["name"] == "Brutal-Fleet Hulk", "blend exactly at 0.6")
	e = SlabLogic.evaluate("hulk", [_r("power", 10, 1), _r("speed", 7, 2)], cfg)
	t.ok(e["name"] == "Brutal-Fleet Hulk", "blend above 0.6")
	e = SlabLogic.evaluate("zombie", [_r("power", 5, 1), _r("beef", 3, 2)], cfg)
	t.ok(e["name"] == "Brutal-Hulking Zombie" and e["noun"] == "Zombie", "blend names both stats")
	e = SlabLogic.evaluate("zombie", [_r("power", 5, 1), _r("power", 5, 2)], cfg)
	t.ok(e["name"] == "Brutal Zombie", "same stat does not blend")
	e = SlabLogic.evaluate("siren", [], cfg)
	t.ok(e["name"] == "Hollow Siren" and e["adjective"] == "Hollow", "hollow name")

	# --- purity ------------------------------------------------------------------
	var input := [_r("power", 3, 1), _r("wits", 2, 2), _r("luck", 1, 3)]
	var copy := input.duplicate(true)
	SlabLogic.evaluate("skeleton", input, cfg)
	t.ok(input == copy, "evaluate does not mutate its input")

	return t.failures
