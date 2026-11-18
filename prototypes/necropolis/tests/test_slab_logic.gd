extends RefCounted
## SlabLogic: anatomy slots, assignment, stats, validity, role and name; the husk silhouettes;
## CryptLogic (the crypt tab): click-to-slot, gate and place text, names, the hold, the raise gate.

const KINDS := ["skeleton", "zombie", "hulk", "siren", "lich", "wraith", "revenant"]


func _r(aspect: String, mag: int, uid := 1) -> Dictionary:
	return {"uid": uid, "aspect": aspect, "rarity": "common", "magnitude": mag}


func run() -> int:
	var t := TestUtil.new()
	t.suite("slab-logic")
	var cfg: Dictionary = TestUtil.configs()["town"]["slab"]

	_display_name(t, cfg)

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
	t.ok(e["role_label"] == "Brawler" and e["role_line"] == "Brawler: good for breaking Vei's raw front and a warden's armour", "role label and line")
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

	_silhouettes(t, cfg)
	var texts: Dictionary = TestUtil.configs()["town"]["view"]["crypt"]
	_crypt_keys(t, texts)
	_board(t, cfg, texts)
	_gate(t, texts)
	_place(t, texts)
	_names(t)
	_hold(t, cfg)
	_block_and_rows(t, cfg, texts)
	_choices(t, cfg)
	return t.failures


# --- silhouettes (town.json slab.silhouettes, the live morph preview) ---------
func _silhouettes(t: TestUtil, cfg: Dictionary) -> void:
	var sil: Dictionary = cfg.get("silhouettes", {})
	for k in cfg["anatomy"]:
		t.ok(sil.has(k), "slab.silhouettes has %s" % k)
		if not sil.has(k):
			continue
		var strokes: Array = sil[k].get("strokes", [])
		var good := not strokes.is_empty()
		for pl in strokes:
			good = good and pl is Array and pl.size() >= 2
			for p in pl:
				good = good and p is Array and p.size() == 2 and float(p[0]) >= 0.0 and float(p[0]) <= 1.0 \
					and float(p[1]) >= 0.0 and float(p[1]) <= 1.0
		t.ok(good, "%s strokes: non-empty polylines, every point in the unit box" % k)
		var eye: Array = sil[k].get("eye", [])
		t.ok(eye.size() == 2 and float(eye[0]) >= 0.0 and float(eye[0]) <= 1.0 and float(eye[1]) >= 0.0 and float(eye[1]) <= 1.0,
			"%s has an eye mark in the unit box (wits)" % k)
	for k in sil:
		t.ok(cfg["anatomy"].has(k), "silhouette %s is a husk kind" % k)


func _crypt_keys(t: TestUtil, texts: Dictionary) -> void:
	var keys := ["gate", "vei_name", "sep", "husks", "no_husks", "remnants", "no_remnants", "empty_slab", "dominant_mark",
		"arrow", "refuse", "block", "hold", "holding", "prompt", "keep", "suggest", "bad_name", "risen",
		"risen_stub", "refused", "roster", "no_big", "rename", "save", "to_crypt", "to_party", "to_foreman", "to_siege", "places_line", "tips",
		"held", "lot_option", "taken", "no_lots", "no_forts", "reasons", "place", "name_px", "role_px", "stat_px", "text_px",
		"small_px", "roster_name_px", "preview"]
	var nested := {
		"gate": ["home", "travelling", "travelling_home", "at_fort", "at_vei", "in_dungeon", "in_boss", "dead_clone", "dead_unmade", "away", "roster_note"],
		"refuse": ["no_husk", "on_slab", "no_slot", "full"], "block": ["away", "no_husk", "cap", "min", "unplaced", "kind", "raising"],
		"place": ["crypt", "party", "town", "fort", "other"],
		"reasons": ["_unknown", "not_home", "unknown_husk", "unknown_remnant", "duplicate_remnant", "invalid_recipe", "at_cap",
			"bad_name", "unknown_uid", "busy", "bad_place", "unknown_lot", "empty_lot", "foreman_taken", "unknown_fort", "duplicate_uid"],
		"preview": ["h_px", "body_px", "per_beef", "max_scale", "ghost", "w_px", "glow", "rings_px", "ring_w_px", "ring_alpha",
			"ring_hold_alpha", "ring_asleep_alpha", "ring_reach_px", "hold_ring_px", "hold_w_px", "hold_glow", "rim_gap_px",
			"spike_len_px", "spike_deg", "spike_max", "spike_w_px", "spike_glow", "presence_base_px", "presence_per_px",
			"presence_push_px", "presence_dashes", "presence_w_px", "presence_glow", "presence_fade", "wisp_len_px", "wisp_gap_px",
			"wisp_max", "wisp_sway_px", "wisp_w_px", "wisp_glow", "wisp_span", "wisp_alpha", "eye_px", "eye_w_px", "eye_glow",
			"eye_core_px", "wits_sharp", "wits_sharp_min",
			"rune_r_px", "rune_hit_px", "rune_rx_px", "rune_ry_px", "rune_step_deg", "rune_group_deg", "rune_w_px", "rune_glow",
			"rune_dashes", "hover_w_px", "hover_pad_px", "caption_px", "caption_gap_px", "number_px", "label_px", "collapse_min_beats", "flash_s", "flash_w_mul"]}
	var missing: Array = []
	for k in keys:
		if not texts.has(k):
			missing.append(k)
	for k in nested:
		for sub in nested[k]:
			if not texts.get(k, {}).has(sub):
				missing.append("%s.%s" % [k, sub])
	t.ok(missing.is_empty(), "town.json view.crypt has every key the crypt tab reads: missing %s" % str(missing))
	var pv: Dictionary = texts["preview"]
	for k in ["caption_px", "number_px", "label_px"]:
		t.ok(int(pv[k]) >= 12, "preview %s is at least 12 px" % k)
	for k in ["name_px", "role_px", "stat_px", "text_px", "small_px", "roster_name_px"]:
		t.ok(int(texts[k]) >= 12, "crypt %s is at least 12 px" % k)
	t.ok(float(pv["rune_hit_px"]) * 2.0 >= 44.0, "a rune's click target is at least 44 px across")
	for g in SlabLogic.GROUPS:
		t.ok(pv["rune_group_deg"].has(g), "runes of group %s have an angle" % g)
	var rings: Array = pv["rings_px"]
	var body_r := float(pv["body_px"]) * float(pv["max_scale"]) * 0.5
	t.ok(body_r + float(pv["rim_gap_px"]) + float(pv["spike_len_px"][0]) < float(rings[0]),
		"the biggest creature's spikes stay inside the slab's innermost ring")
	t.ok(float(rings[rings.size() - 1]) < float(pv["hold_ring_px"]), "the hold ring closes outside the slab's rings")


func _r2(uid: String, aspect: String, mag: int, rarity := "common") -> Dictionary:
	return {"uid": uid, "aspect": aspect, "rarity": rarity, "magnitude": mag}


# --- click-to-slot -----------------------------------------------------------
func _board(t: TestUtil, cfg: Dictionary, texts: Dictionary) -> void:
	var rems := CryptLogic.by_uid([_r2("p1", "power", 2), _r2("p2", "power", 3), _r2("p3", "power", 1), _r2("p4", "power", 4),
		_r2("b1", "beef", 3), _r2("w1", "wits", 4), _r2("w2", "wits", 1), _r2("w3", "wits", 2), _r2("s1", "speed", 1),
		_r2("pr1", "presence", 2)])
	var empty := CryptLogic.board()
	var c := CryptLogic.click_remnant(empty, "p1", rems, cfg)
	t.ok(not c["ok"] and c["reason"] == "no_husk", "no husk on the slab: a remnant click is refused")

	# hulk: muscle 3, nerve 1
	var b := CryptLogic.board("h1", "hulk")
	c = CryptLogic.click_remnant(b, "p1", rems, cfg)
	t.ok(c["ok"] and c["action"] == "slot" and c["slot"] == 0, "power lands in the first muscle slot")
	b = c["board"]
	c = CryptLogic.click_remnant(b, "s1", rems, cfg)
	t.ok(c["ok"] and c["slot"] == 3, "speed skips the free muscle slots for the nerve slot")
	b = c["board"]
	c = CryptLogic.click_remnant(b, "w1", rems, cfg)
	t.ok(not c["ok"] and c["reason"] == "full" and c["board"] == b, "wits with the nerve slot taken is refused, the board unchanged")
	t.ok(CryptLogic.refusal_text(b, "w1", rems, cfg, texts) == String(texts["refuse"]["full"]).format({"groups": "nerve"}),
		"the reason says which slots are full: %s" % CryptLogic.refusal_text(b, "w1", rems, cfg, texts))
	t.ok(CryptLogic.refusal_text(b, "p1", rems, cfg, texts) == String(texts["refuse"]["on_slab"]).format({"group": "muscle"}),
		"a slotted remnant says where it sits")
	t.ok(CryptLogic.slot_uids(b, rems, cfg) == ["p1", "", "", "s1"], "slot_uids: p1 in muscle, s1 in nerve")
	t.ok(CryptLogic.slot_order(b, rems, cfg) == ["p1", "s1"], "the raise gets the uids in slot order")
	var ev := CryptLogic.evaluate(b, rems, cfg)
	t.ok(ev["ok"] and int(ev["filled"]) == 2, "evaluate runs on the board (2 filled, ok)")

	# zombie: muscle 2 only
	var z := CryptLogic.board("h4", "zombie")
	c = CryptLogic.click_remnant(z, "w1", rems, cfg)
	t.ok(not c["ok"] and c["reason"] == "no_slot", "a zombie has no slot for wits: refused")
	t.ok(CryptLogic.refusal_text(z, "w1", rems, cfg, texts) == String(texts["refuse"]["no_slot"]).format({"noun": "Zombie", "aspect": "wits"}),
		"the no-slot reason names the husk and the aspect")
	z = CryptLogic.click_remnant(z, "p1", rems, cfg)["board"]
	z = CryptLogic.click_remnant(z, "b1", rems, cfg)["board"]
	c = CryptLogic.click_remnant(z, "p2", rems, cfg)
	t.ok(not c["ok"] and c["reason"] == "full", "a third muscle remnant on a zombie is refused")
	t.ok(CryptLogic.landing(z, "p2", rems, cfg) == -1 and CryptLogic.refusal(z, "p2", rems, cfg) == "full",
		"landing -1 and refusal full agree for the disabled button")

	# lich: nerve 3, anima 1 -- anima last
	var l := CryptLogic.board("h9", "lich")
	c = CryptLogic.click_remnant(l, "w1", rems, cfg)
	t.ok(c["slot"] == 0, "lich: wits takes a nerve slot even with the anima slot free")
	l = c["board"]
	c = CryptLogic.click_remnant(l, "p1", rems, cfg)
	t.ok(c["ok"] and c["slot"] == 3, "lich: power has no muscle, so it falls into anima")
	l = c["board"]
	c = CryptLogic.click_remnant(l, "p2", rems, cfg)
	t.ok(not c["ok"] and c["reason"] == "full", "lich: a second power finds anima full")
	t.ok(CryptLogic.refusal_text(l, "p2", rems, cfg, texts) == String(texts["refuse"]["full"]).format({"groups": "anima"}),
		"the reason names the anima slot")

	# revenant: muscle 2, presence 1, anima 2 -- overflow then unslot
	var r := CryptLogic.board("h7", "revenant")
	for u in ["p1", "p2", "p3"]:
		r = CryptLogic.click_remnant(r, u, rems, cfg)["board"]
	t.ok(CryptLogic.slot_uids(r, rems, cfg) == ["p1", "p2", "", "p3", ""], "revenant: two powers in muscle, the third spills into anima")
	var before := int(CryptLogic.evaluate(r, rems, cfg)["filled"])
	var cs := CryptLogic.click_slot(r, 0, rems, cfg)
	t.ok(cs["uid"] == "p1" and not ("p1" in CryptLogic.slot_uids(cs["board"], rems, cfg)), "clicking a filled rune takes its remnant off")
	t.ok(int(CryptLogic.evaluate(cs["board"], rems, cfg)["filled"]) == before - 1, "unslotting frees a slot (filled - 1)")
	t.ok(CryptLogic.slot_uids(cs["board"], rems, cfg) == ["p2", "p3", "", "", ""],
		"the spilled power settles into the freed muscle slot, as the raise would place it")
	t.ok(CryptLogic.click_slot(cs["board"], 4, rems, cfg)["uid"] == "", "clicking an empty rune does nothing")
	c = CryptLogic.click_remnant(cs["board"], "p2", rems, cfg)
	t.ok(c["ok"] and c["action"] == "unslot" and not ("p2" in c["board"]["order"]), "clicking a slotted remnant takes it off too")
	t.ok(CryptLogic.refusal(cs["board"], "p1", rems, cfg) == "", "the freed remnant can go back on")

	# the order the panel sends evaluates the same as the click order (E3 re-evaluates what it gets)
	var mixed := CryptLogic.board("h7", "revenant")
	for u in ["w1", "p1", "pr1", "p2", "p4"]:
		mixed = CryptLogic.click_remnant(mixed, u, rems, cfg)["board"]
	var by_click := CryptLogic.evaluate(mixed, rems, cfg)
	var sent: Array = []
	for u in CryptLogic.slot_order(mixed, rems, cfg):
		sent.append(rems[u])
	var by_slot := SlabLogic.evaluate("revenant", sent, cfg)
	t.ok(by_click["stats"] == by_slot["stats"] and by_click["filled"] == by_slot["filled"] and by_click["ok"] == by_slot["ok"],
		"evaluate(slot order) gives the same stats and validity as evaluate(click order)")
	var same := true
	var su := CryptLogic.slot_uids(mixed, rems, cfg)
	for j in by_slot["slots"].size():
		var i := int(by_slot["slots"][j]["remnant_index"])
		same = same and (sent[i]["uid"] if i >= 0 else "") == su[j]
	t.ok(same, "and the same rune for every remnant")

	# reconcile with the inventory
	var inv := {"husks": [{"uid": "h7", "kind": "revenant"}], "remnants": [_r2("p1", "power", 2), _r2("p3", "power", 1)]}
	var rb := CryptLogic.reconcile(r, inv)
	t.ok(rb["husk"] == "h7" and rb["order"] == ["p1", "p3"], "reconcile drops remnants the inventory no longer has")
	t.ok(CryptLogic.reconcile(r, {"husks": [], "remnants": []}) == CryptLogic.board(), "a husk that is gone empties the slab")
	t.ok(CryptLogic.reconcile(CryptLogic.board(), inv) == CryptLogic.board(), "an empty slab stays empty")


# --- gate text -----------------------------------------------------------------
func _gate(t: TestUtil, texts: Dictionary) -> void:
	var g: Dictionary = texts["gate"]
	var names := {"greywall": "Greywall", "ashgate": "Ashgate"}
	var rl := func(state: String, extra := {}) -> Dictionary:
		return ({"state": state, "at": "covington", "target": "", "dead_s_left": 0.0, "respawn_with_clone": false} as Dictionary).merged(extra, true)
	t.ok(CryptLogic.gate_text(rl.call("home"), names, texts) == g["home"], "home: the slab is awake")
	var tr := CryptLogic.gate_text(rl.call("travelling", {"target": "greywall"}), names, texts)
	t.ok(tr == String(g["travelling"]).format({"to": "Greywall"}) and "Greywall" in tr, "travelling to a fort names it: %s" % tr)
	t.ok(CryptLogic.gate_text(rl.call("travelling", {"target": "covington", "at": "ashgate"}), names, texts) == g["travelling_home"],
		"travelling home says so")
	t.ok("Vei" in CryptLogic.gate_text(rl.call("travelling", {"target": "vei"}), names, texts), "travelling to Vei names Vei")
	t.ok(CryptLogic.gate_text(rl.call("at_fort", {"at": "ashgate"}), names, texts) == String(g["at_fort"]).format({"at": "Ashgate"}),
		"at a fort names it")
	t.ok(CryptLogic.gate_text(rl.call("at_vei", {"at": "vei"}), names, texts) == g["at_vei"], "at Vei")
	t.ok(CryptLogic.gate_text(rl.call("in_dungeon", {"at": "ashgate"}), names, texts) == String(g["in_dungeon"]).format({"at": "Ashgate"}),
		"in a dungeon names the fort")
	t.ok(CryptLogic.gate_text(rl.call("in_boss", {"at": "vei"}), names, texts) == g["in_boss"], "facing Vei")
	var dc := CryptLogic.gate_text(rl.call("dead", {"dead_s_left": 41.2, "respawn_with_clone": true}), names, texts)
	t.ok(dc == String(g["dead_clone"]).format({"s": 42}) and "42" in dc, "dead with a clone: whole seconds left, rounded up: %s" % dc)
	var du := CryptLogic.gate_text(rl.call("dead", {"dead_s_left": 7.0}), names, texts)
	t.ok(du == String(g["dead_unmade"]).format({"s": 7}), "dead and unmade: she reforms in 7 s")
	t.ok(CryptLogic.gate_text(rl.call("travelling", {"target": "nowhere"}), {}, texts) == String(g["travelling"]).format({"to": "Nowhere"}),
		"an unknown node falls back to its capitalised id")
	var all := {}
	for st in ["home", "travelling", "at_fort", "at_vei", "in_dungeon", "in_boss", "dead"]:
		var txt := CryptLogic.gate_text(rl.call(st, {"at": "ashgate", "target": "greywall"}), names, texts)
		t.ok(txt != "", "%s has a gate line" % st)
		all[txt] = true
	t.ok(all.size() == 7, "every Relish state reads differently")


# --- place text ----------------------------------------------------------------
func _place(t: TestUtil, texts: Dictionary) -> void:
	var p: Dictionary = texts["place"]
	var lots := {"lot-04": "Market"}
	var forts := {"ashgate": "Ashgate"}
	t.ok(CryptLogic.place_text("crypt", lots, forts, texts) == p["crypt"], "crypt")
	t.ok(CryptLogic.place_text("party", lots, forts, texts) == p["party"], "party")
	t.ok(CryptLogic.place_text("town:lot-04", lots, forts, texts) == String(p["town"]).format({"label": "Market"}),
		"foreman at the Market: %s" % CryptLogic.place_text("town:lot-04", lots, forts, texts))
	t.ok(CryptLogic.place_text("town:lot-09", lots, forts, texts) == String(p["town"]).format({"label": "lot-09"}), "an unknown lot shows its id")
	t.ok(CryptLogic.place_text("fort:ashgate", lots, forts, texts) == String(p["fort"]).format({"name": "Ashgate"}), "sieging Ashgate")
	t.ok(CryptLogic.place_text("fort:greywall", lots, forts, texts) == String(p["fort"]).format({"name": "Greywall"}),
		"an unnamed fort falls back to its capitalised id")
	t.ok(CryptLogic.place_text("void", lots, forts, texts) == "void", "anything else shows as it is")
	var block := float(TestUtil.configs()["realm"]["tithe"]["siege_block"])
	var sl := CryptLogic.siege_line(texts, block)
	t.ok(sl == "Siege: blocks %d%% of a tithe wave here, no kills; a second adds nothing" % roundi(block * 100.0),
		"the Siege menu's line reads its share from realm.json tithe.siege_block (as the map's chip does): '%s'" % sl)
	t.ok(CryptLogic.siege_line(texts, 0.25).contains("blocks 25%"), "the share follows the config, never a fixed 60")


# --- names ---------------------------------------------------------------------
func _names(t: TestUtil) -> void:
	t.ok(not CryptLogic.check_name("")["ok"] and CryptLogic.check_name("")["reason"] == "bad_name", "empty name refused")
	t.ok(not CryptLogic.check_name("   \t ")["ok"], "whitespace-only name refused")
	var n24 := "abcdefghijklmnopqrstuvwx"
	t.ok(n24.length() == 24 and CryptLogic.check_name(n24)["ok"], "24 characters is fine")
	t.ok(not CryptLogic.check_name(n24 + "y")["ok"], "25 characters refused")
	var padded := CryptLogic.check_name("   " + n24 + "  ")
	t.ok(padded["ok"] and padded["name"] == n24, "padding is stripped before the length check")
	t.ok(CryptLogic.check_name(" Old Gristle ")["name"] == "Old Gristle" and CryptLogic.check_name("Old Gristle")["reason"] == "",
		"a good name comes back stripped")


# --- hold to raise ---------------------------------------------------------------
func _hold(t: TestUtil, cfg: Dictionary) -> void:
	var hold_s := float(cfg["raise_hold_s"])
	var h := CryptLogic.hold_step(0.0, true, hold_s - 0.05, hold_s)
	t.ok(CryptLogic.hold_progress(h, hold_s) < 1.0, "just short of raise_hold_s the hold is not done")
	h = CryptLogic.hold_step(h, true, 0.05, hold_s)
	t.near(CryptLogic.hold_progress(h, hold_s), 1.0, 0.0001, "at raise_hold_s the hold reaches 1")
	h = CryptLogic.hold_step(h, true, 1.0, hold_s)
	t.ok(h == hold_s and CryptLogic.hold_progress(h, hold_s) == 1.0, "held past it, it stays at 1")
	var frames := 0.0
	var steps := 0
	while CryptLogic.hold_progress(frames, hold_s) < 1.0 and steps < 10000:
		frames = CryptLogic.hold_step(frames, true, 1.0 / 60.0, hold_s)
		steps += 1
	t.ok(float(steps) / 60.0 >= hold_s - 0.0001, "at 60 fps it takes at least raise_hold_s (%d frames)" % steps)
	h = CryptLogic.hold_step(hold_s * 0.7, false, 0.016, hold_s)
	t.ok(h == 0.0 and CryptLogic.hold_progress(h, hold_s) == 0.0, "releasing resets it to 0")
	t.ok(CryptLogic.hold_step(0.2, true, -1.0, hold_s) == 0.2, "a negative dt never runs it backwards")
	t.near(CryptLogic.collapse_s(0.0, 1.714, 0.5), 1.714, 0.0001, "the collapse started on a beat lasts one beat")
	t.near(CryptLogic.collapse_s(0.25, 1.714, 0.5), 1.714 * 0.75, 0.0001, "started a quarter in, it ends on the next beat")
	t.near(CryptLogic.collapse_s(0.9, 1.714, 0.5), 1.714 * 1.1, 0.0001, "too close to a beat, it ends on the one after")


# --- raise gate, stats → verbs, labels ------------------------------------------
func _block_and_rows(t: TestUtil, cfg: Dictionary, texts: Dictionary) -> void:
	var bt: Dictionary = texts["block"]
	var rems := CryptLogic.by_uid([_r2("p1", "power", 6), _r2("s1", "speed", 2)])
	var b := CryptLogic.board("h1", "hulk")
	var ev := CryptLogic.evaluate(b, rems, cfg)
	t.ok(CryptLogic.raise_block(b, ev, false, 0, 4, cfg, texts) == bt["away"], "away first")
	t.ok(CryptLogic.raise_block(CryptLogic.board(), {}, true, 0, 4, cfg, texts) == bt["no_husk"], "no husk")
	t.ok(CryptLogic.raise_block(b, ev, true, 4, 4, cfg, texts) == String(bt["cap"]).format({"count": 4, "cap": 4}), "at the cap")
	t.ok(CryptLogic.raise_block(b, ev, true, 1, 4, cfg, texts) == String(bt["min"]).format({"n": int(cfg["min_remnants"])}),
		"an empty husk says which rule fails (min remnants)")
	b = CryptLogic.click_remnant(b, "p1", rems, cfg)["board"]
	b = CryptLogic.click_remnant(b, "s1", rems, cfg)["board"]
	ev = CryptLogic.evaluate(b, rems, cfg)
	t.ok(CryptLogic.raise_block(b, ev, true, 1, 4, cfg, texts) == "", "a valid recipe, home, under the cap: the hold is open")
	var bad := SlabLogic.evaluate("zombie", [_r2("a", "power", 1), _r2("b", "power", 1), _r2("c", "power", 1)], cfg)
	t.ok(CryptLogic.raise_block(CryptLogic.board("h4", "zombie"), bad, true, 0, 4, cfg, texts) == String(bt["unplaced"]).format({"n": 1}),
		"an unplaced remnant is named as the failing rule")
	t.ok(CryptLogic.raise_block(CryptLogic.board("hx", "dragon"), SlabLogic.evaluate("dragon", [], cfg), true, 0, 4, cfg, texts) == bt["kind"],
		"an unknown husk kind")

	var rows := CryptLogic.stat_rows(ev["stats"], ev["dominant"], cfg, texts)
	t.ok(rows.size() == 5, "all five stats, never only the top one")
	var ids: Array = rows.map(func(r): return r["stat"])
	t.ok(ids == SlabLogic.STATS, "in STATS order")
	t.ok(rows[0]["dominant"] and rows.filter(func(r): return r["dominant"]).size() == 1, "power is the one dominant stat")
	t.ok(rows[0]["text"] == "6" and rows[4]["text"] == "2" and rows[2]["text"] == "0", "upright whole numbers")
	t.ok(rows[0]["helps"] == cfg["stat_helps"]["power"], "power helps what slab.stat_helps says: %s" % rows[0]["helps"])
	t.ok(rows.all(func(r): return String(r["helps"]) != ""), "every stat says what it helps")
	t.ok(CryptLogic.stat_rows({}, "", cfg, texts).all(func(r): return not r["dominant"]), "a hollow husk has no dominant stat")
	t.ok(CryptLogic.fmt_stat(3.4893) == "3.5" and CryptLogic.fmt_stat(6.0) == "6" and CryptLogic.fmt_stat(5.97) == "6",
		"stats print whole or with one decimal")
	t.ok(CryptLogic.husk_label("hulk", cfg) == "Hulk · muscle 3 · nerve 1", "husk label: noun and anatomy")
	t.ok(CryptLogic.husk_label("revenant", cfg) == "Revenant · muscle 2 · presence 1 · anima 2", "revenant label skips empty groups")
	t.ok(CryptLogic.remnant_label(_r2("r5", "wits", 4, "rare")) == "wits 4 · rare", "remnant label: aspect, magnitude, rarity")


# --- placement choices, rune layout ----------------------------------------------
func _choices(t: TestUtil, cfg: Dictionary) -> void:
	var forts := [{"id": "ashgate", "name": "Ashgate", "held": false}, {"id": "greywall", "name": "Greywall", "held": true},
		{"id": "old-sluice", "name": "Old Sluice", "held": false}, {"id": "vespers", "name": "Vespers", "held": true}]
	var ids: Array = CryptLogic.siege_forts(forts).map(func(f): return f["id"])
	t.ok(ids == ["greywall", "vespers", "ashgate", "old-sluice"], "siege choices: held forts first, world order within")
	var blds := [{"lot_id": "lot-01", "building_id": "crypt", "level": 1, "slots": 0, "foreman": ""},
		{"lot_id": "lot-04", "building_id": "market", "level": 1, "slots": 2, "foreman": "u8"},
		{"lot_id": "lot-05", "building_id": "bone_mill", "level": 0, "slots": 0, "foreman": ""},
		{"lot_id": "lot-06", "building_id": "bone_pit", "level": 2, "slots": 4, "foreman": ""}]
	var lots := CryptLogic.foreman_lots(blds, {"market": "Market", "bone_pit": "Bone Pit"})
	t.ok(lots.size() == 2 and lots[0]["lot_id"] == "lot-04" and lots[1]["lot_id"] == "lot-06",
		"foreman choices: built lots with jobs only (no crypt, nothing under first construction)")
	t.ok(lots[0]["label"] == "Market" and lots[0]["foreman"] == "u8", "with their label and current foreman")
	t.ok(CryptLogic.lot_labels(blds, {"market": "Market"})["lot-04"] == "Market", "lot labels for the place text")

	var pv: Dictionary = TestUtil.configs()["town"]["view"]["crypt"]["preview"]
	var c := Vector2(264, 132)
	for kind in cfg["anatomy"]:
		var groups := SlabLogic.slots_for(kind, cfg)
		var pts := CryptLogic.rune_points(groups, c, float(pv["rune_rx_px"]), float(pv["rune_ry_px"]), pv["rune_group_deg"], float(pv["rune_step_deg"]))
		t.ok(pts.size() == groups.size(), "%s: one rune per slot" % kind)
		var apart := true
		var clear := true
		for i in pts.size():
			clear = clear and (pts[i] as Vector2).distance_to(c) - float(pv["rune_r_px"]) > float(pv["hold_ring_px"]) + float(pv["hold_w_px"])
			for j in range(i + 1, pts.size()):
				apart = apart and (pts[i] as Vector2).distance_to(pts[j]) >= 2.0 * float(pv["rune_hit_px"])
		t.ok(apart, "%s: rune click targets never overlap" % kind)
		t.ok(clear, "%s: runes sit outside the hold ring" % kind)


## T-d1: a placed big undead carries the slab's name; the helper and `evaluate` share one naming rule.
func _display_name(t: TestUtil, cfg: Dictionary) -> void:
	var rems := [_r("beef", 6, 1), _r("beef", 5, 2), _r("power", 4, 3), _r("wits", 2, 4)]
	for k in KINDS:
		var ev := SlabLogic.evaluate(k, rems, cfg)
		t.ok(SlabLogic.name_for(k, ev["stats"], cfg) == ev["name"], "display name: name_for agrees with evaluate for a %s (%s)" % [k, ev["name"]])
		var entry := {"uid": "u7", "name": "Big u7", "kind": k, "stats": ev["stats"]}
		t.ok(SlabLogic.display_name(entry, cfg) == ev["name"], "display name: the mint default 'Big u7' shows the slab name for a %s" % k)
	var hulk := SlabLogic.evaluate("hulk", [_r("beef", 6, 1), _r("beef", 5, 2), _r("power", 4, 3)], cfg)
	t.ok(String(hulk["name"]).contains(" ") and String(hulk["name"]).ends_with("Hulk"), "display name: a two-word name (%s)" % hulk["name"])
	var kept := {"uid": "u7", "name": "Old Gristle", "kind": "hulk", "stats": hulk["stats"]}
	t.ok(SlabLogic.display_name(kept, cfg) == "Old Gristle", "display name: a real name is kept")
	t.ok(SlabLogic.display_name({"uid": "u8", "name": "Big u7", "kind": "hulk", "stats": hulk["stats"]}, cfg) == "Big u7",
		"display name: another creature's 'Big u7' is a chosen name, not this one's default")
	t.ok(SlabLogic.display_name({"uid": "u7", "name": "", "kind": "hulk", "stats": hulk["stats"]}, cfg) == hulk["name"], "display name: an empty name shows the slab name")
	t.ok(SlabLogic.display_name({"uid": "u7", "name": "Big u7", "kind": "", "stats": {}}, cfg) == "Big u7", "display name: no kind to name, so the name stays")
	var hollow := SlabLogic.display_name({"uid": "u9", "name": "Big u9", "kind": "zombie", "stats": {"power": 0.0}}, cfg)
	t.ok(hollow == "%s Zombie" % cfg["hollow_adjective"], "display name: no stats at all names it Hollow (%s)" % hollow)
	t.ok(String(cfg.get("default_name_prefix", "")) == "Big ", "display name: the mint prefix is in town.json slab.default_name_prefix")
