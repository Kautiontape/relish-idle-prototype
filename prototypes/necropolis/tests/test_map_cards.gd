extends RefCounted
## Tests for the map's cards: card_logic.gd (the text builders), card_blocks_logic.gd (the card
## assembly) and a real-GameState pass over the pre_vei fixture (no autoloads).


func run() -> int:
	var t := TestUtil.new()
	t.suite("map_cards")
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	_warden(t)
	_loot(t)
	_threat(t)
	_death(t)
	_chips(t)
	_vei(t)
	_village(t)
	_blocks(t)
	_contrast(t)
	_real(t)
	return t.failures


func _warden(t: TestUtil) -> void:
	t.ok(CardLogic.warden_name("bellringer") == "The Bellringer", "bellringer is The Bellringer")
	t.ok(CardLogic.warden_name("pyre_priest") == "The Pyre Priest", "pyre_priest reads The Pyre Priest")
	t.ok(CardLogic.warden_name("storm_caller") == "The Storm Caller", "an unmapped archetype is title-cased")
	var one := CardLogic.warden_lines({"archetype": "bellringer", "tells": ["rings slam on the beat"]})
	t.ok(one == ["The Bellringer", "rings slam on the beat"], "one tell: name then the tell")
	t.ok(CardLogic.tell_label({"tells": ["a"]}) == "TELL", "one tell is labelled TELL")
	var many := CardLogic.warden_lines({"archetype": "huntsman", "tells": ["a", "b", "c"]})
	t.ok(many == ["The Huntsman", "a", "b", "c"], "every tell listed (Watchtower)")
	t.ok(CardLogic.tell_label({"tells": ["a", "b"]}) == "TELLS", "several tells are labelled TELLS")
	var none := CardLogic.warden_lines({"archetype": "huntsman", "tells": []})
	t.ok(none.size() == 2 and str(none[1]) != "", "no tells still gives a line")


func _loot(t: TestUtil) -> void:
	var cfg: Dictionary = MapLogic.cfg()["cards"]["loot"]
	t.ok(CardLogic.loot_line({"yield_mult": 1.0, "clears_since_retaken": 0}, cfg) == "Loot: full (fresh)", "full loot")
	t.ok(CardLogic.loot_line({"yield_mult": 0.64, "clears_since_retaken": 2}, cfg) == "Loot: 64% (recovering)", "decayed loot shows the percentage")
	t.ok(CardLogic.loot_line({"yield_mult": 1.0, "clears_since_retaken": 3}, cfg) == "Loot: full (fresh)", "full yield reads full whatever the clear count")
	t.ok(CardLogic.loot_line({}, cfg) == "Loot: full (fresh)", "a missing entry reads full")
	t.ok(CardLogic.loot_card_line({"yield_mult": 0.5, "clears_since_retaken": 1}) == "Loot: 50% (recovering)", "the card's one call site")
	t.ok(CardLogic.first_clear_line({"first_clear": true}) == "first clear: guaranteed blueprint", "first clear line")
	t.ok(CardLogic.first_clear_line({"first_clear": false}) == "", "no first clear, no line")


func _threat(t: TestUtil) -> void:
	var th := {"party_strength": 8.0, "garrison_strength": 6.1, "risk": "risky", "risk_pct": -1.0}
	t.ok(CardLogic.strength_text(th) == "PARTY 8.0 vs GARRISON 6.1", "strength text: " + CardLogic.strength_text(th))
	var fr := CardLogic.strength_fracs(th)
	t.near(fr[0], 1.0, 0.001, "the stronger side's bar is full")
	t.near(fr[1], 6.1 / 8.0, 0.001, "the other side's bar is proportional")
	var zero := {"party_strength": 0.0, "garrison_strength": 0.0, "risk": "low", "risk_pct": -1.0}
	t.ok(not CardLogic.strength_known(zero), "0 vs 0 is unknown")
	t.ok(CardLogic.strength_text(zero).contains("—") and not CardLogic.strength_text(zero).contains("0.0"), "0 vs 0 shows the dash: " + CardLogic.strength_text(zero))
	t.ok(CardLogic.strength_fracs(zero) == [0.0, 0.0], "0 vs 0 draws no bars")
	t.ok(CardLogic.strength_known({"party_strength": 0.0, "garrison_strength": 3.0}), "an empty party against a garrison is a known comparison")
	t.ok(CardLogic.risk_chip(th) == {"text": "RISKY", "key": "select"}, "risky chip without a percentage")
	t.ok(CardLogic.risk_chip({"risk": "risky", "risk_pct": 34.0})["text"] == "RISKY · 34%", "risky chip with the Watchtower percentage")
	t.ok(CardLogic.risk_chip({"risk": "low", "risk_pct": -1.0}) == {"text": "LOW", "key": "undead"}, "low chip")
	t.ok(CardLogic.risk_chip({"risk": "deadly", "risk_pct": 0.0}) == {"text": "DEADLY · 0%", "key": "danger"}, "deadly chip, 0% still shows")


func _death(t: TestUtil) -> void:
	var u := CardLogic.death_lines({"outcome": "unmade", "respawn_s": 0.0, "loses": ["unbanked_loot", "morale"]})
	t.ok(u == ["If she dies now: she is unmade.", "loses: unbanked loot, morale"], "unmade, no respawn line: " + str(u))
	var c := CardLogic.death_lines({"outcome": "clone", "respawn_s": 125.0, "loses": ["party"]})
	t.ok(c == ["If she dies now: she wakes in a clone vat.", "Back on her feet in 2:05.", "loses: the party"], "clone with a respawn time: " + str(c))
	var p := CardLogic.death_lines({"outcome": "phylactery", "respawn_s": 0.0, "loses": []})
	t.ok(p == ["If she dies now: a phylactery charge revives her in place.", "loses nothing"], "phylactery loses nothing: " + str(p))
	var all := CardLogic.death_lines({"outcome": "unmade", "respawn_s": 600.0, "loses": ["party", "unbanked_loot", "flip", "morale"]})
	t.ok(all[2] == "loses: the party, unbanked loot, the flip, morale" and all[1] == "Back on her feet in 10:00.", "every loss word, 600 s is 10:00: " + str(all))
	t.ok(CardLogic.death_lines({}).size() >= 2 and str(CardLogic.death_lines({})[0]) != "", "an empty death still reads")


func _chips(t: TestUtil) -> void:
	var names := {"u1": "Old Gristle", "u2": "Pale Ann"}
	t.ok(CardLogic.status_chips({}, names).is_empty(), "no chips on a quiet fort")
	var held := CardLogic.status_chips({"held": true, "held_s_left": 192.0}, names)
	t.ok(held.size() == 1 and held[0]["text"] == "HELD · 3:12 left", "held countdown m:ss")
	var eta := CardLogic.status_chips({"tithe": {"targeted": true, "eta_s": 88.0, "wave_active": false}}, names)
	t.ok(eta.size() == 1 and eta[0]["text"] == "TITHE WAVE IN 1:28", "tithe ETA")
	var now := CardLogic.status_chips({"tithe": {"targeted": true, "eta_s": 0.0, "wave_active": true}}, names)
	t.ok(now.size() == 1 and now[0]["text"] == "TITHE WAVE NOW", "wave now")
	t.ok(CardLogic.status_chips({"tithe": {"targeted": false, "eta_s": -1.0, "wave_active": false}}, names).is_empty(), "an untargeted tithe shows nothing")
	var here := CardLogic.status_chips({"relish_here": true, "tide": true, "redirect": true}, names)
	t.ok(here[0]["text"] == "RELISH HERE · tide · redirect", "relish here with tide and redirect")
	t.ok(CardLogic.status_chips({"relish_here": true}, names)[0]["text"] == "RELISH HERE", "relish here alone")
	var siege := CardLogic.status_chips({"siege": ["u1", "u2", "u9"]}, names)
	t.ok(siege[0]["text"] == "SIEGE · Old Gristle, Pale Ann, u9", "siege by name, unknown uid as itself")
	var sim := CardLogic.status_chips({"simulacrum_charges": 3.0}, names)
	t.ok(sim[0]["text"] == "SIMULACRUM · 3 charges", "simulacrum charges")
	t.ok(CardLogic.status_chips({"first_dungeon": true}, names)[0]["text"] == "YOUR FIRST DUNGEON", "first dungeon")
	var cfg: Dictionary = MapLogic.cfg()["cards"]
	var every := CardLogic.status_chips({"held": true, "held_s_left": 5.0, "relish_here": true, "siege": ["u1"],
		"simulacrum_charges": 1.0, "first_dungeon": true, "tithe": {"targeted": true, "eta_s": 4.0, "wave_active": false}}, names)
	t.ok(every.size() == 6 and every.all(func(c): return str(c["text"]) != "" and cfg["chip_keys"].values().has(c["key"])), "all six chips, each with text and a configured key")


func _vei(t: TestUtil) -> void:
	var names := {"u1": "Old Gristle"}
	var fronts := [
		{"id": "giants", "need": 24.0, "have": 26.5, "cleared": true, "assigned": ["u1"]},
		{"id": "swarm", "need": 10.0, "have": 2.0, "cleared": false, "assigned": []},
	]
	var rows := CardLogic.front_rows(fronts, names)
	t.ok(rows.size() == 2 and rows[0]["name"] == "Giants" and rows[0]["have"] == "27" and rows[0]["need"] == "24", "front row: name, have, need")
	t.ok(rows[0]["mark"] == "✓ met" and rows[1]["mark"] == "✗ open", "the met mark has a glyph and words")
	t.ok(rows[0]["assigned"] == "assigned: Old Gristle" and rows[1]["assigned"] == "no one assigned", "assigned names")
	t.ok(CardLogic.front_name("carvers") == "Carvers" and CardLogic.front_name("raw") == "Raw", "front display names")
	t.ok(CardLogic.fronts_met_text({"fronts_met": 3, "fronts_required": 3}) == "fronts met 3 of 3 required", "met count text")
	var win := CardLogic.confirm_text({"odds": 0.61, "sign": 1, "drain_s": 200.0})
	t.ok(win.contains("61%") and win.contains("▲") and win.contains("3m 20s"), "confirm repeats odds, sign and drain: " + win)
	var hold := CardLogic.confirm_text({"odds": 0.5, "sign": 0, "drain_s": -1.0})
	t.ok(hold.contains("50%") and hold.contains("holding") and hold.contains("∞"), "confirm for a holding war: " + hold)
	var lose := CardLogic.confirm_text({"odds": 0.2, "sign": -1, "drain_s": 70.0})
	t.ok(lose.contains("▼") and lose.contains("1m 10s"), "confirm for a losing war: " + lose)


func _readout(vei: Dictionary) -> Dictionary:
	return {"odds": vei.get("odds", 0.0), "sign": vei.get("sign", 0), "drain_s": vei.get("drain_s", -1.0), "backlog": vei.get("backlog", 0.0)}


func _village(t: TestUtil) -> void:
	t.ok(CardLogic.village_owner_text("player") == "held by the necrosis: its people drift to Covington", "player village")
	t.ok(CardLogic.village_owner_text("vei") == "held by Vei's living", "Vei's village")
	t.ok(CardLogic.village_owner_text("none") == "contested", "contested village")
	t.ok(CardLogic.village_owner_text("other") == "contested", "an unknown owner reads contested")


func _fort_entry() -> Dictionary:
	return {"id": "old-sluice", "name": "Old Sluice", "tier": 1, "cap": 80.0, "living": 61.2, "undead": 6.4, "dead": 3.1, "space": 9.3,
		"war_in": 0.48, "ship_in": 0.3, "held": false, "held_s_left": 0.0, "first_clear": true, "first_dungeon": true,
		"clears_since_retaken": 0, "yield_mult": 1.0, "warden": {"archetype": "bellringer", "tells": ["rings slam on the beat"]},
		"loot_hint": "a husk and a blueprint", "threat": {"party_strength": 8.0, "garrison_strength": 6.1, "risk": "low", "risk_pct": -1.0},
		"relish_here": false, "tide": false, "redirect": false, "simulacrum_charges": 0.0, "siege": [],
		"tithe": {"targeted": false, "eta_s": -1.0, "wave_active": false}}


func _blocks(t: TestUtil) -> void:
	var back := {"death": {"outcome": "unmade", "respawn_s": 0.0, "loses": ["party", "unbanked_loot", "morale"]}}
	var card := CardBlocksLogic.fort_card(_fort_entry(), "a drowned water-works", back, {})
	t.ok(card["title"] == "Old Sluice" and card["sub"] == "FORTRESS · TIER 1 · CAPACITY 80", "fort title and subtitle: " + str(card["sub"]))
	var ids: Array = card["blocks"].map(func(b): return b["id"])
	for want in ["warden", "tell1", "hint", "loot", "first_clear", "versus", "risk", "death0", "death1", "living", "undead", "dead", "space", "war_in", "ship_in", "chips"]:
		t.ok(ids.has(want), "the fort card has a '%s' block" % want)
	t.ok(ids.find("warden") < ids.find("loot") and ids.find("loot") < ids.find("versus") and ids.find("versus") < ids.find("living"),
		"order: warden, loot, threat, matter")
	var by_id := {}
	for b in card["blocks"]:
		t.ok(CardBlocksLogic.sig_of(b) != "", "block %s has a signature" % b["id"])
		by_id[b["id"]] = b
	t.ok(by_id["tell1"]["text"] == "TELL: rings slam on the beat" and by_id["hint"]["text"] == "Hint: a husk and a blueprint", "the tell and the loot hint read as lines")
	t.ok(by_id["death0"]["text"].begins_with("If she dies now: ") and by_id["death1"]["text"].begins_with("loses: "), "the death cost is in words")
	var wide := _fort_entry()
	wide["warden"] = {"archetype": "huntsman", "tells": ["a", "b"]}
	var wb: Array = CardBlocksLogic.fort_card(wide, "", back, {})["blocks"].filter(func(b): return str(b["id"]).begins_with("tell"))
	t.ok(wb.size() == 2 and wb[0]["text"] == "TELLS: a" and wb[1]["text"] == "· b", "several tells, one line each")
	var stub := _fort_entry()
	stub["threat"] = {"party_strength": 0.0, "garrison_strength": 0.0, "risk": "low", "risk_pct": -1.0}
	stub["loot_hint"] = ""
	stub["first_dungeon"] = false
	stub["first_clear"] = false
	var sc := CardBlocksLogic.fort_card(stub, "", back, {})
	var vs: Dictionary = sc["blocks"].filter(func(b): return b["kind"] == "versus")[0]
	t.ok(not vs["known"] and str(vs["text"]).contains("—"), "the E1 stub renders as an unknown comparison")
	t.ok(not (sc["blocks"] as Array).any(func(b): return b["id"] == "hint" or b["id"] == "chips"), "no hint row and no chips when there are none")
	t.ok(CardBlocksLogic.card_sig(card) != CardBlocksLogic.card_sig(sc), "a different structure has a different signature")
	var c2 := _fort_entry()
	c2["living"] = 12.0
	t.ok(CardBlocksLogic.card_sig(CardBlocksLogic.fort_card(c2, "a drowned water-works", back, {})) == CardBlocksLogic.card_sig(card), "a changed number keeps the signature")

	var vei := {"backlog": 18450.0, "odds": 0.61, "sign": 1, "diff_ema": 6.1, "drain_s": -1.0, "fronts_met": 1, "fronts_required": 3,
		"fronts": [{"id": "giants", "need": 24.0, "have": 26.5, "cleared": true, "assigned": ["u1"]}]}
	var vc := CardBlocksLogic.vei_card(vei, "", [], {"u1": "Old Gristle"}, _readout(vei))
	var by := {}
	for b in vc["blocks"]:
		by[b["id"]] = b
	t.ok(vc["title"] == "Vei's Domain" and vc["sub"] == "THE GODDESS OF LIFE", "Vei title and subtitle")
	t.ok(by["backlog"]["mass"] == "18,450" and by["backlog"]["text"] == " massed at her gates", "backlog line")
	t.ok(by["odds"]["value"] == "61%" and by["sign"]["value"] == "▲" and by["diff"]["value"] == "+6.1/s" and by["drain"]["value"] == "∞", "odds, sign, differential, drain (holding is ∞)")
	t.ok(by["diff"]["vkind"] == "rate" and by["odds"]["vkind"] == "mass", "the differential is a rate, odds a mass")
	t.ok(by.has("front_giants") and by["fronts_met"]["text"] == "fronts met 1 of 3 required", "front row and the met count")
	t.ok(by.has("party_empty") and by["party_empty"]["text"].contains("crypt slab"), "an empty party says where to raise them")
	var party := [{"uid": "u1", "name": "Old Gristle", "kind": "hulk", "role": "brute", "front": "giants"}]
	var vp := CardBlocksLogic.vei_card({"fronts": [{"id": "giants"}, {"id": "swarm"}, {"id": "carvers"}, {"id": "raw"}]}, "", party, {}, {})
	var asg: Dictionary = vp["blocks"].filter(func(b): return b["kind"] == "assign")[0]
	t.ok(asg["options"] == ["", "giants", "swarm", "carvers", "raw"] and asg["labels"][0] == "—" and asg["labels"][1] == "Giants", "selector: a dash plus the four fronts")
	t.ok(asg["selected"] == "giants" and asg["sub"] == "hulk · brute", "selector shows the current front, the kind and the role")
	t.ok(not (vp["blocks"] as Array).any(func(b): return b["id"] == "party_empty"), "a party removes the empty line")

	var vl := CardBlocksLogic.village_card({"name": "Bellwether", "owner": "player", "migrants": 0.012}, "")
	t.ok(vl["title"] == "Bellwether" and vl["sub"] == "TOWN · NECROSIS", "village title and tag")
	t.ok(vl["blocks"][0]["text"].begins_with("held by the necrosis"), "village owner words")
	t.ok(vl["blocks"][1]["value"] == "+0.01/s" and vl["blocks"][1]["vkind"] == "rate", "migrants is a signed rate: " + str(vl["blocks"][1]["value"]))


## Text on the card plate, and on the chip tints, must be >= 4.5:1; the bars >= 3:1.
func _contrast(t: TestUtil) -> void:
	var cfg := MapLogic.cfg()
	var plate := Palette.c("ground").lightened(float(cfg["panel_bg_lighten"]))
	var cards: Dictionary = cfg["cards"]
	var keys := {"text": true, "text_dim": true, "undead": true, "select": true, "danger": true, "relish": true, "essence": true}
	for k in cards["risk_keys"].values():
		keys[k] = true
	for k in cards["chip_keys"].values():
		keys[k] = true
	for k in keys:
		var r := MapLogic.contrast_ratio(Palette.c(k), plate)
		t.ok(r >= 4.5, "%s text on the card plate is %.1f:1 (>= 4.5)" % [k, r])
		var tint := plate.lerp(Palette.c(k), float(cards["chip_bg_alpha"]))
		var rc := MapLogic.contrast_ratio(Palette.c(k), tint)
		t.ok(rc >= 4.5, "%s chip text on its own tint is %.1f:1 (>= 4.5)" % [k, rc])
	for k in ["undead", "living"]:
		t.ok(MapLogic.contrast_ratio(Palette.c(k), plate) >= 3.0, "the %s comparison bar is >= 3:1" % k)
	t.ok(int(cfg["font_body"]) >= 12 and int(cfg["type"]["size_label"]) >= 12 and float(cfg["button_min_h_px"]) >= 44.0, "no text under 12 px, buttons at least 44 px")


## A real GameState on the pre_vei fixture: every card builds from real views with no empty
## required line, and cmd_assign_front shows in view_vei().fronts[].assigned.
func _real(t: TestUtil) -> void:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	var r := s.cmd_debug_load_fixture("pre_vei")
	t.ok(r["ok"], "pre_vei loads (%s)" % r["reason"])
	var m := MapModel.new(s)
	m.refresh(true)
	t.ok(not m.backups.is_empty() and m.backups.has("death") and m.party.has("party"), "the model caches backups and the party")
	var back := m.backups
	for f in m.forts:
		var card := CardBlocksLogic.fort_card(f, "", back, m.unit_names)
		var empty := false
		for b in card["blocks"]:
			for k in ["text", "value", "label"]:
				if b.has(k) and b["kind"] in ["para", "row", "versus", "head"] and str(b[k]) == "" :
					empty = true
		t.ok(not empty and str(card["title"]) != "" and str(card["sub"]) != "", "fort %s card has no empty required line" % f["id"])
	var vc := CardBlocksLogic.vei_card(m.vei, "", m.party["party"], m.unit_names, m.readout())
	t.ok(str(vc["title"]) != "" and (vc["blocks"] as Array).size() > 8, "the Vei card builds from the real view")
	t.ok(CardLogic.confirm_text(m.readout()).contains("%"), "the confirm text builds from the real view")
	# the card and the dialog read the one readout the bar and Vei's node draw, with and without the demo
	for demo in [false, true]:
		var md := MapModel.new(s)
		md.nodes_demo = demo
		md.refresh(true)
		var ro := md.readout()
		var st := HudLogic.status(ro)
		var card: Dictionary = CardBlocksLogic.vei_card(md.vei, "", md.party["party"], md.unit_names, ro)
		var cb := {}
		for b in card["blocks"]:
			cb[b["id"]] = b
		t.ok(cb["odds"]["value"] == st["odds_text"] and cb["sign"]["value"] == st["sign_text"] and cb["drain"]["value"] == st["drain_text"],
			"demo=%s: the Vei card's odds, sign and drain are the bar's" % demo)
		t.ok(CardLogic.confirm_text(ro).contains(st["odds_text"]) and CardLogic.confirm_text(ro).contains(st["drain_text"]), "demo=%s: the dialog repeats the same" % demo)
	var empty := {"odds": 0.5, "sign": 1, "drain_s": 0.0, "backlog": 0.0}
	var ec := CardBlocksLogic.vei_card({"backlog": 0.0}, "", [], {}, empty)
	t.ok(ec["blocks"].filter(func(b): return b["id"] == "drain")[0]["value"] == "queue empty", "an empty backlog reads queue empty on the card")
	t.ok(CardLogic.confirm_text(empty).contains("queue empty"), "and in the dialog")
	for v in m.villages:
		var vcard := CardBlocksLogic.village_card(v, "")
		t.ok(str(vcard["sub"]) != "" and str(vcard["blocks"][0]["text"]) != "", "village %s card builds" % v["id"])
	# a party member takes a front
	if s.view_big_undead()["big_undead"].is_empty():
		s.cmd_debug_grant({"big_undead": 1})
	var uid := str(s.view_big_undead()["big_undead"][0]["uid"])
	if (s.view_party()["party"] as Array).is_empty():
		var sp := s.cmd_set_party([uid])
		t.ok(sp["ok"], "the big undead joins the party (%s)" % sp["reason"])
	# pick a front she is not on now, so the command's effect is the only way the view can change
	var cur := ""
	for pm in s.view_party()["party"]:
		if pm["uid"] == uid:
			cur = str(pm["front"])
	var target := "giants" if cur != "giants" else "swarm"
	t.ok(not _assigned_to(s, target).has(uid), "before: %s is not on %s" % [uid, target])
	var ar := s.cmd_assign_front(uid, target)
	t.ok(ar["ok"], "assign_front succeeds (%s)" % ar["reason"])
	m.refresh(true)
	t.ok(_assigned_to(s, target).has(uid) and m.vei["fronts"].filter(func(f): return f["id"] == target)[0]["assigned"].has(uid), "after: view_vei shows the assignment on %s" % target)
	if cur != "":
		t.ok(not _assigned_to(s, cur).has(uid), "and she left %s" % cur)
	var vc2 := CardBlocksLogic.vei_card(m.vei, "", m.party["party"], m.unit_names, m.readout())
	var fr: Dictionary = vc2["blocks"].filter(func(b): return b["id"] == "front_" + target)[0]
	t.ok(str(fr["assigned"]).contains(str(m.unit_names[uid])), "the front row names her: " + str(fr["assigned"]))
	var asg: Dictionary = vc2["blocks"].filter(func(b): return b["kind"] == "assign" and b["uid"] == uid)[0]
	t.ok(asg["selected"] == target, "the selector shows %s" % target)
	t.ok(s.cmd_assign_front(uid, "")["ok"], "an empty front unassigns")
	m.refresh(true)
	var vc3 := CardBlocksLogic.vei_card(m.vei, "", m.party["party"], m.unit_names, m.readout())
	var asg3: Dictionary = vc3["blocks"].filter(func(b): return b["kind"] == "assign" and b["uid"] == uid)[0]
	t.ok(asg3["selected"] == "" and asg3["labels"][0] == "—" and not _assigned_to(s, target).has(uid), "unassigned: the selector falls back to the dash")
	t.ok(not s.cmd_assign_front("nobody", "giants")["ok"], "an unknown uid is refused")
	t.ok(RelishLogic.reason_text("unknown_uid") != "" and not RelishLogic.reason_text("unknown_uid").contains("("), "a refusal reads in words")


func _assigned_to(s: GameState, front_id: String) -> Array:
	for f in s.view_vei()["fronts"]:
		if f["id"] == front_id:
			return f["assigned"]
	return []
