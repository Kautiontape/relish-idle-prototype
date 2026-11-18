extends RefCounted
## The crypt's husk craft (town-i M2 Q-f, the bone lever): CryptLogic.husk_craft's price line, kind buttons and the
## reason in words (no_bone split by the bone store's cap), the crypt bind signature that wakes the panel when the
## craft's state moves, and the same lines on a real GameState's views.

var t: TestUtil
var cfg: Dictionary
var ct: Dictionary
var slab: Dictionary


func run() -> int:
	t = TestUtil.new()
	t.suite("town-craft")
	cfg = TestUtil.configs()
	ct = cfg["town"]["view"]["crypt"]
	slab = cfg["town"]["slab"]
	_lines()
	_reasons()
	_sig()
	_real()
	return t.failures


func _hc(reason := "", can := false) -> Dictionary:
	return {"kinds": ["skeleton", "zombie"], "cost": {"bone": 500.0, "remnants": 3}, "can_craft": can, "reason": reason}


func _rates(bone_cap: float) -> Array:
	return [{"id": "gold", "stock": 10.0, "cap": 7200.0}, {"id": "bone", "stock": 120.0, "cap": bone_cap}]


func _lines() -> void:
	var none := CryptLogic.husk_craft({}, [], 0, 0, 4, slab, ct)
	t.ok(not bool(none["shown"]) and (none["buttons"] as Array).is_empty(), "no husk_craft in the catalog: nothing shown")
	var ok := CryptLogic.husk_craft(_hc("", true), _rates(1000.0), 5, 1, 4, slab, ct)
	t.ok(bool(ok["shown"]) and bool(ok["can"]) and String(ok["why"]) == "", "can_craft: shown, enabled, no why")
	t.ok(String(ok["head"]).contains("500 bone") and String(ok["head"]).contains("3 weakest remnants"),
		"the head names the price and that it takes the weakest remnants: '%s'" % ok["head"])
	var b: Array = ok["buttons"]
	t.ok(b.size() == 2 and String(b[0]["kind"]) == "skeleton" and String(b[0]["text"]).begins_with("Craft Skeleton")
		and String(b[1]["text"]).begins_with("Craft Zombie"), "a button per kind, by the slab's noun: %s" % str(b))
	var away := CryptLogic.husk_craft_done("zombie", false, slab, ct)
	var home := CryptLogic.husk_craft_done("zombie", true, slab, ct)
	t.ok(away.contains("Zombie") and away.contains("until Relish is home") and home.contains("husks above"),
		"the done line says where the husk waits, home or away ('%s' / '%s')" % [home, away])
	t.ok(not String(ct["no_husks"]).contains("Dungeons") and String(ct["no_husks"]).contains("craft"),
		"no husks: raids drop them, or craft one ('%s')" % ct["no_husks"])


func _reasons() -> void:
	var r := CryptLogic.husk_craft(_hc("no_remnants"), _rates(1000.0), 1, 0, 4, slab, ct)
	t.ok(not bool(r["can"]) and String(r["why"]) == "needs 3 remnants and you have 1: raid a fort for more", "no_remnants: '%s'" % r["why"])
	r = CryptLogic.husk_craft(_hc("no_bone"), _rates(200.0), 3, 0, 4, slab, ct)
	t.ok(String(r["reason"]) == "no_bone_cap" and String(r["why"]).contains("holds 200") and String(r["why"]).contains("Bone Mill"),
		"no_bone under a 200 cap: the store can't hold the price, Bone Mill levels raise it ('%s')" % r["why"])
	r = CryptLogic.husk_craft(_hc("no_bone"), _rates(1000.0), 3, 0, 4, slab, ct)
	t.ok(String(r["reason"]) == "no_bone" and String(r["why"]) == "needs 500 bone: the Bone Mill grinds it from bodies", "no_bone with room: '%s'" % r["why"])
	r = CryptLogic.husk_craft(_hc("no_bone"), [], 3, 0, 4, slab, ct)
	t.ok(String(r["reason"]) == "no_bone", "no bone cap in the rates: plain no_bone")
	r = CryptLogic.husk_craft(_hc("at_cap"), _rates(1000.0), 3, 4, 4, slab, ct)
	t.ok(String(r["why"]).contains("4 / 4") and String(r["why"]).contains("Crypt upgrade"), "at_cap counts big undead and husks: '%s'" % r["why"])
	r = CryptLogic.husk_craft(_hc("catching_up"), _rates(1000.0), 3, 0, 4, slab, ct)
	t.ok(TownUI.refusal("catching_up", String(r["why"]), "x") == "Catching up on your time away: try again in a moment.",
		"catching_up reads as a wait (%s)" % TownUI.refusal("catching_up", String(r["why"]), "x"))
	r = CryptLogic.husk_craft(_hc("mystery"), _rates(1000.0), 3, 0, 4, slab, ct)
	t.ok(String(r["why"]) == String(ct["husk_craft"]["reasons"]["_unknown"]), "an unknown reason: the fallback line")
	r = CryptLogic.husk_craft(_hc("", false), _rates(1000.0), 3, 0, 4, slab, ct)
	t.ok(not bool(r["can"]), "can_craft false with no reason: still disabled")
	var left := PackedStringArray()
	for id in (ct["husk_craft"]["reasons"] as Dictionary):
		var w := String(CryptLogic.husk_craft(_hc("no_bone" if id == "no_bone_cap" else id), _rates(200.0 if id == "no_bone_cap" else 1000.0),
			2, 3, 4, slab, ct)["why"])
		if w.contains("{"):
			left.append("%s: %s" % [id, w])
	t.ok(left.is_empty(), "every reason line fills its numbers (%s)" % ", ".join(left))


func _sig() -> void:
	var v := {"catalog": {"husk_craft": _hc("no_bone")}, "hud": {"rates": _rates(200.0)}}
	var base := CryptLogic.bind_sig(v)
	var v2: Dictionary = v.duplicate(true)
	v2["hud"]["rates"][1]["stock"] = 180.0
	t.ok(CryptLogic.bind_sig(v2) == base, "the bone stock moving alone leaves the crypt's bind signature alone")
	v2["hud"]["rates"][1]["cap"] = 700.0
	t.ok(CryptLogic.bind_sig(v2) != base, "the bone cap moving changes it (no_bone_cap's line)")
	var v3: Dictionary = v.duplicate(true)
	v3["catalog"]["husk_craft"] = _hc("", true)
	t.ok(CryptLogic.bind_sig(v3) != base, "the craft turning possible changes it")


func _real() -> void:
	var s := GameState.new(cfg)
	s.cmd_new_game(1)
	s.debug_enabled = true
	var n := int(s._req_f("economy.craft.husk.remnants"))
	var price := s._req_f("economy.craft.husk.bone")
	s.remnants.clear()
	var view := func() -> Dictionary:
		var inv: Dictionary = s.view_inventory()
		var bu: Dictionary = s.view_big_undead()
		return CryptLogic.husk_craft(s.view_catalog()["husk_craft"], s.view_hud()["rates"], (inv["remnants"] as Array).size(),
			int(bu["count"]) + (inv["husks"] as Array).size(), int(bu["cap"]), slab, ct)
	var r: Dictionary = view.call()
	t.ok(String(r["reason"]) == "no_remnants" and String(r["why"]).contains("you have 0"), "a new game with no remnants: '%s'" % r["why"])
	for i in n:
		s.remnants.append({"uid": s._mint_uid("r"), "aspect": "wits", "rarity": "common", "magnitude": 1})
	s.town_sim.bone = 0.0
	r = view.call()
	var cap := CryptLogic.store_cap(s.view_hud()["rates"], "bone")
	t.ok(cap >= 0.0 and cap < price and String(r["reason"]) == "no_bone_cap",
		"a new game's bone store (cap %.0f) is under the %.0f price: the line says so ('%s')" % [cap, price, r["why"]])
	s.town_sim._bone_cap = price * 2.0
	s.town_sim.bone = price
	r = view.call()
	t.ok(bool(r["can"]), "room and the price in hand: the buttons are live ('%s')" % r["why"])
	var husks_before := s.husks.size()
	t.ok(bool(s.cmd_craft_husk(String(r["buttons"][0]["kind"]))["ok"]) and s.husks.size() == husks_before + 1,
		"the first button's kind crafts")
	r = view.call()
	t.ok(String(r["reason"]) == "no_remnants", "the remnants went into it: no_remnants again ('%s')" % r["why"])
