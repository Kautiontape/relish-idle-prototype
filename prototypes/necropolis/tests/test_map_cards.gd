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
	_state(t)
	_no_cleared_words(t)
	_vei(t)
	_village(t)
	_blocks(t)
	_comes(t)
	_parity(t)
	_sidebar_src(t)
	_contrast(t)
	_real(t)
	return t.failures


func _warden(t: TestUtil) -> void:
	t.ok(CardLogic.warden_name("bellringer") == "The Bellringer", "bellringer is The Bellringer")
	# the configured name is used: raid.json's (whatever it calls pyre_priest), the title-cased fallback where it has none
	var named: Dictionary = TestUtil.load_json("res://configs/raid.json").get("wardens", {}).get("archetypes", {}).get("pyre_priest", {})
	var pyre := str(named.get("name", ""))
	t.ok(CardLogic.warden_name("pyre_priest", pyre) == (pyre if pyre != "" else "The Pyre Priest"), "pyre_priest reads its configured name")
	t.ok(CardLogic.warden_name("pyre_priest", "The Pyre-priest") == "The Pyre-priest", "a name on the view beats the id")
	t.ok(CardLogic.warden_lines({"archetype": "pyre_priest", "name": "The Pyre-priest", "tells": ["a"]})[0] == "The Pyre-priest", "warden_lines uses the view's name")
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
	var loot := TestUtil.load_json("res://configs/loot.json")
	for f in [{"yield_mult": 1.0, "clears_since_retaken": 0}, {"yield_mult": 0.64, "clears_since_retaken": 2}, {"tier": 2, "first_clear": true},
			{"held": true, "yield_mult": 0.5}, {}]:
		var want: String = RaidLoot.card_line(f, loot)
		t.ok(want != "" and CardLogic.loot_card_line(f, loot) == want, "the card's loot line is RaidLoot.card_line's: " + want)
	t.ok(CardLogic.loot_card_line({"yield_mult": 0.64}, loot).contains("64%"), "a decayed yield shows its percentage")
	t.ok(not MapLogic.cfg()["cards"]["loot"].has("full_text"), "the stand-in's text is gone from map_view.json")


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
	var quiet := CardLogic.status_chips({}, names)
	t.ok(quiet.size() == 1 and quiet[0]["text"] == "VEI'S", "a quiet fort has only the state chip")
	var held := CardLogic.status_chips({"held": true, "grace_s_left": 192.0}, names)
	t.ok(held.size() == 1 and held[0]["text"] == "HELD · Vei contests in 3:12", "held countdown m:ss")
	var eta := CardLogic.status_chips({"tithe": {"targeted": true, "eta_s": 88.0, "wave_active": false}}, names)
	t.ok(eta.size() == 2 and eta[1]["text"] == "TITHE WAVE IN 1:28", "tithe ETA")
	var now := CardLogic.status_chips({"tithe": {"targeted": true, "eta_s": 0.0, "wave_active": true}}, names)
	t.ok(now.size() == 2 and now[1]["text"] == "TITHE WAVE NOW", "wave now")
	t.ok(CardLogic.status_chips({"tithe": {"targeted": false, "eta_s": -1.0, "wave_active": false}}, names).size() == 1, "an untargeted tithe shows nothing")
	var here := CardLogic.status_chips({"relish_here": true, "tide": true, "redirect": true}, names)
	t.ok(here[1]["text"] == "RELISH HERE · tide · redirect", "relish here with tide and redirect")
	t.ok(CardLogic.status_chips({"relish_here": true}, names)[1]["text"] == "RELISH HERE", "relish here alone")
	var siege := CardLogic.status_chips({"siege": ["u1", "u2", "u9"]}, names)
	t.ok(siege[1]["text"] == "SIEGE · Old Gristle, Pale Ann, u9", "siege by name, unknown uid as itself")
	var sim := CardLogic.status_chips({"simulacrum_charges": 3.0}, names)
	t.ok(sim[1]["text"] == "SIMULACRUM · 3 charges", "simulacrum charges")
	t.ok(CardLogic.status_chips({"first_dungeon": true}, names)[1]["text"] == "YOUR FIRST DUNGEON", "first dungeon")
	var cfg: Dictionary = MapLogic.cfg()["cards"]
	var every := CardLogic.status_chips({"held": true, "grace_s_left": 5.0, "relish_here": true, "siege": ["u1"],
		"simulacrum_charges": 1.0, "first_dungeon": true, "tithe": {"targeted": true, "eta_s": 4.0, "wave_active": false}}, names)
	t.ok(every.size() == 6 and every.all(func(c): return str(c["text"]) != "" and cfg["chip_keys"].values().has(c["key"])), "all six chips, each with text and a configured key")
	t.ok(every[0]["text"].begins_with("HELD") and every[1]["text"].begins_with("TITHE"), "the state chip comes first, the rest keep their order")
	var unheld := CardLogic.status_chips({"first_dungeon": true, "flipped_count": 1}, names)
	t.ok(unheld[0]["text"] == "RETAKEN" and unheld[0]["key"] == "danger" and unheld[1]["text"] == "YOUR FIRST DUNGEON", "an unheld fort's first chip is its state chip")


func _state(t: TestUtil) -> void:
	var veis := CardLogic.fort_state({"held": false, "cap": 80.0, "living": 60.0, "undead": 2.0, "flipped_count": 0})
	t.ok(veis["state"] == "veis" and veis["chip"] == {"text": "VEI'S", "key": "living"}, "a Vei's fort: " + str(veis["chip"]))
	t.ok(veis["line"] == "Not taken yet. Raid it and break its warden to take it.", "its line: " + str(veis["line"]))
	var over := CardLogic.fort_state({"held": false, "cap": 80.0, "living": 0.0, "undead": 30.0, "flipped_count": 0})
	t.ok(over["state"] == "veis" and over["chip"]["text"] == "VEI'S" and str(over["line"]).begins_with("Your undead fill it, but it's still Vei's."), "an overrun fort is still Vei's: " + str(over["line"]))
	var grace := CardLogic.fort_state({"held": true, "grace_s_left": 374.0, "margin": "thin"})
	t.ok(grace["state"] == "held" and grace["chip"]["text"] == "HELD · Vei contests in 6:14" and grace["chip"]["key"] == "undead", "held in grace: " + str(grace["chip"]))
	t.ok(str(grace["line"]).begins_with("Taken by you. Vei can't touch it until the clock runs out"), "grace line: " + str(grace["line"]))
	var cont := CardLogic.fort_state({"held": true, "grace_s_left": 0.0, "margin": "thin", "undead": 40.0})
	t.ok(cont["state"] == "held" and cont["chip"]["key"] == IdleLogic.color_key("thin") and str(cont["chip"]["text"]).begins_with("HELD · 40 undead · "), "held contested wears the margin: " + str(cont["chip"]))
	t.ok(str(cont["line"]).begins_with("Taken by you. Vei contests it now"), "contested line: " + str(cont["line"]))
	var ret := CardLogic.fort_state({"held": false, "flipped_count": 1, "cap": 80.0, "living": 60.0})
	t.ok(ret["state"] == "retaken" and ret["chip"] == {"text": "RETAKEN", "key": "danger"} and str(ret["line"]).begins_with("Vei won it back."), "retaken: " + str(ret["chip"]))
	# the held chip
	var both := CardLogic.held_chip({"held": true, "grace_s_left": 374.0, "margin": "safe", "undead": 64.0})
	t.ok(both["text"] == "HELD · Vei contests in 6:14" and both["key"] == "undead", "grace beats the margin: " + str(both))
	t.ok(CardLogic.held_chip({"held": true, "grace_s_left": 61.0})["text"] == "HELD · Vei contests in 1:01", "the countdown moves with grace_s_left")
	t.ok(CardLogic.held_chip({"held": true, "grace_s_left": 0.0, "margin": "safe", "undead": 64.0})["text"] == "HELD · 64 undead · SAFE", "no grace: the undead and margin (never 'garrison': that is the raid count)")
	var bare := CardLogic.held_chip({"held": true, "grace_s_left": 0.0})
	t.ok(bare["text"] == "HELD" and bare["key"] == "undead", "no grace and no margin: bare HELD")
	t.ok(not FileAccess.get_file_as_string("res://scripts/map/card_logic.gd").contains("held_s_left"), "card_logic no longer reads held_s_left")


## "Cleared" means one thing (taking a fort by breaking its warden): no config string says it otherwise.
func _no_cleared_words(t: TestUtil) -> void:
	var found: Array = []
	_walk_strings(MapLogic.cfg(), "", found)
	t.ok(found.is_empty(), "no map_view.json value says 'cleared': %s" % str(found))


func _walk_strings(v: Variant, path: String, found: Array) -> void:
	if v is Dictionary:
		for k in v:
			_walk_strings(v[k], path + "/" + str(k), found)
	elif v is Array:
		for i in v.size():
			_walk_strings(v[i], path + "/" + str(i), found)
	elif v is String and (v as String).to_lower().contains("cleared"):
		found.append(path)


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
	var card := _fc(_fort_entry(), "a drowned water-works", back, {}, _loot_cfg())
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
	var wb: Array = _fc(wide, "", back, {}, _loot_cfg())["blocks"].filter(func(b): return str(b["id"]).begins_with("tell"))
	t.ok(wb.size() == 2 and wb[0]["text"] == "TELLS: a" and wb[1]["text"] == "· b", "several tells, one line each")
	var stub := _fort_entry()
	stub["threat"] = {"party_strength": 0.0, "garrison_strength": 0.0, "risk": "low", "risk_pct": -1.0}
	stub["loot_hint"] = ""
	stub["first_dungeon"] = false
	stub["first_clear"] = false
	var sc := _fc(stub, "", back, {}, _loot_cfg())
	# was: the stub rendered as an unknown "PARTY — vs GARRISON —" versus block; now the threat blocks are omitted (map-i M1 task 3)
	var sids: Array = sc["blocks"].map(func(b): return b["id"])
	t.ok(not sids.has("threat_head") and not sids.has("versus") and not sids.has("risk"), "the E1 stub omits the threat head, versus and risk blocks")
	t.ok(sids.has("death0"), "and keeps the death lines")
	var known: Array = _fc(_fort_entry(), "", back, {}, _loot_cfg())["blocks"].map(func(b): return b["id"])
	t.ok(known.has("threat_head") and known.has("versus") and known.has("risk"), "a known threat shows all three")
	var pct := _fort_entry()
	pct["threat"] = {"party_strength": 0.0, "garrison_strength": 0.0, "risk": "risky", "risk_pct": 34.0}
	var pids: Array = _fc(pct, "", back, {}, _loot_cfg())["blocks"].map(func(b): return b["id"])
	t.ok(pids.has("versus") and pids.has("risk"), "a known risk % alone shows them too")
	t.ok(not (sc["blocks"] as Array).any(func(b): return b["id"] == "hint"), "no hint row when there is none")
	var order: Array = ids.filter(func(i): return ["chips", "state", "raid", "retreat", "warden"].has(i))
	t.ok(order == ["chips", "state", "raid", "retreat", "warden"], "order: chips, state, raid, retreat, warden: " + str(order))
	t.ok(by_id["state"]["text"] == "Not taken yet. Raid it and break its warden to take it." and by_id["state"]["key"] == "text", "the state line")
	t.ok(by_id["raid"]["text"] == "Raid: break the warden to take the fort. Loot: relics, husks, essence." and by_id["raid"]["key"] == "select", "the raid line, unheld")
	t.ok(by_id["retreat"]["text"].ends_with("the fort stays Vei's.") and by_id["retreat"]["key"] == "text_dim", "the retreat line, unheld")
	var hf := _fort_entry()
	hf["held"] = true
	var hb := {}
	for b in _fc(hf, "", back, {}, _loot_cfg())["blocks"]:
		hb[b["id"]] = b
	t.ok(hb["raid"]["text"] == "Raid it again for loot: less each time; it recovers over 8 h." and hb["retreat"]["text"].ends_with("the fort stays yours."), "held: raid again and retreat words")
	var lc := _loot_cfg()
	lc["recover_s"] = 7200.0
	var hb2 := {}
	for b in _fc(hf, "", back, {}, lc)["blocks"]:
		hb2[b["id"]] = b
	t.ok(str(hb2["raid"]["text"]).contains("over 2 h"), "the hours come from recover_s: " + str(hb2["raid"]["text"]))
	t.ok(CardBlocksLogic.card_sig(card) != CardBlocksLogic.card_sig(sc), "a different structure has a different signature")
	var c2 := _fort_entry()
	c2["living"] = 12.0
	t.ok(CardBlocksLogic.card_sig(_fc(c2, "a drowned water-works", back, {}, _loot_cfg())) == CardBlocksLogic.card_sig(card), "a changed number keeps the signature")

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
		var card := _fc(f, "", back, m.unit_names, _loot_cfg(), m.party)
		var empty := false
		for b in card["blocks"]:
			for k in ["text", "value", "label"]:
				if b.has(k) and b["kind"] in ["para", "row", "versus", "head"] and str(b[k]) == "" :
					empty = true
		t.ok(not empty and str(card["title"]) != "" and str(card["sub"]) != "", "fort %s card has no empty required line" % f["id"])
	var vc := CardBlocksLogic.vei_card(m.vei, "", m.party["party"], m.unit_names, m.readout())
	t.ok(str(vc["title"]) != "" and (vc["blocks"] as Array).size() > 8, "the Vei card builds from the real view")
	t.ok(CardLogic.confirm_text(m.readout(), m.vei).contains("%"), "the confirm text builds from the real view")
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


## fort_card with the real raid and economy configs and the realm's tide bias; `party` is view_party() (none by default).
func _fc(f: Dictionary, desc: String, back: Dictionary, names: Dictionary, lc: Dictionary, party := {"party": []}) -> Dictionary:
	return CardBlocksLogic.fort_card(f, desc, back, names, lc, party, TestUtil.load_json("res://configs/raid.json"),
		TestUtil.load_json("res://configs/economy.json"), float(TestUtil.load_json("res://configs/realm.json")["relish"]["tide_bias"]))


func _comes(t: TestUtil) -> void:
	var raid := TestUtil.load_json("res://configs/raid.json")
	var econ := TestUtil.load_json("res://configs/economy.json")
	var none := {"party": []}
	var two := {"party": [{"uid": "a"}, {"uid": "b"}]}
	var first := CardLogic.comes_in(_fort_entry(), none, raid, econ)
	t.ok(first == {"garrison": 0, "starter": 8, "bigs": 0, "total": 8}, "the first dungeon: starter 8, garrison 0 of undead 6.4: " + str(first))
	var f27 := _fort_entry()
	f27["undead"] = 27.5
	f27["first_dungeon"] = false
	t.ok(CardLogic.comes_in(f27, none, raid, econ) == {"garrison": 2, "starter": 0, "bigs": 0, "total": 2}, "undead 27.5: garrison 2, no starter")
	f27["undead"] = 500.0
	var cap := int(raid["mass"]["garrison_max"])
	t.ok(cap == 12 and CardLogic.comes_in(f27, none, raid, econ)["garrison"] == cap, "undead 500: the garrison caps at garrison_max")
	f27["held"] = false
	f27["garrison"] = 0.0
	t.ok(CardLogic.comes_in(f27, two, raid, econ) == {"garrison": 12, "starter": 0, "bigs": 2, "total": 14}, "bigs count the party; `garrison` (0 unheld) is not read")
	# profiles and the warning
	t.ok(CardLogic.profile(1, raid) == {"undead": 6, "bigs": 0} and CardLogic.profile(2, raid) == {"undead": 6, "bigs": 1}
		and CardLogic.profile(3, raid) == {"undead": 8, "bigs": 2} and CardLogic.profile(4, raid) == {"undead": 12, "bigs": 3}, "profiles t1..t4")
	t.ok(CardLogic.profile(9, raid) == CardLogic.profile(4, raid) and CardLogic.profile(0, raid) == CardLogic.profile(1, raid), "the tier clamps to 1..4")
	var zero := {"garrison": 0, "starter": 0, "bigs": 0, "total": 0}
	var w0 := CardLogic.comes_in_warning(zero, CardLogic.profile(2, raid), 2, 0.0)
	t.ok(w0 == {"text": "No undead and no corpses here. Relish never attacks, so this raid can't be won yet.", "key": "danger"}, "nobody, no corpses: danger")
	var wp := CardLogic.comes_in_warning(zero, CardLogic.profile(2, raid), 2, 3.1)
	t.ok(wp == {"text": "No undead come in: you'd raise every one inside, from corpse piles. Bring some first.", "key": "select"}, "nobody, corpses: select, and it is not 'can't be won'")
	# the threshold mirrors raid.gd's `dead > 0.05`: exactly at it is no piles, just over it is piles
	var pmin := float(MapLogic.cfg()["cards"]["comes_pile_min_dead"])
	t.ok(pmin == 0.05, "the pile threshold mirrors raid.gd:207 (0.05)")
	t.ok(CardLogic.comes_in_warning(zero, CardLogic.profile(2, raid), 2, pmin)["key"] == "danger", "dead exactly at the threshold: no piles, danger")
	t.ok(CardLogic.comes_in_warning(zero, CardLogic.profile(2, raid), 2, pmin + 0.001)["key"] == "select", "dead just over the threshold: piles, select")
	t.ok(CardLogic.comes_in_warning({"garrison": 6, "starter": 0, "bigs": 1, "total": 7}, CardLogic.profile(2, raid), 2, 3.1).is_empty(), "corpses do not change a warning-free party")
	var low := {"garrison": 6, "starter": 0, "bigs": 0, "total": 6}
	var w2 := CardLogic.comes_in_warning(low, CardLogic.profile(2, raid), 2, 0.0)
	t.ok(w2 == {"text": "Below a standard tier-2 party (6 undead, 1 big undead): expect losses.", "key": "select"}, "below t2 names 1 big: " + str(w2))
	t.ok(CardLogic.comes_in_warning({"garrison": 5, "starter": 0, "bigs": 1, "total": 6}, CardLogic.profile(2, raid), 2, 0.0)["key"] == "select", "too few undead warns too")
	t.ok(CardLogic.comes_in_warning({"garrison": 6, "starter": 0, "bigs": 1, "total": 7}, CardLogic.profile(2, raid), 2, 0.0).is_empty(), "at the profile: no warning")
	t.ok(CardLogic.comes_in_warning({"garrison": 12, "starter": 0, "bigs": 4, "total": 16}, CardLogic.profile(4, raid), 4, 0.0).is_empty(), "above the profile: no warning")
	var w1 := CardLogic.comes_in_warning({"garrison": 2, "starter": 0, "bigs": 0, "total": 2}, CardLogic.profile(1, raid), 1, 0.0)
	t.ok(w1["text"] == "Below a standard tier-1 party (6 undead): expect losses.", "a t1 profile drops the big-undead part: " + str(w1))
	# the card
	var back := {"death": {"outcome": "unmade", "respawn_s": 0.0, "loses": ["party"]}}
	var ids: Array = _fc(_fort_entry(), "", back, {}, _loot_cfg())["blocks"].map(func(b): return b["id"])
	var want := ["chips", "state", "raid", "retreat", "comes_in_head", "comes_in", "bring_more", "warden"]
	t.ok(ids.filter(func(i): return want.has(i)) == want, "block order: chips, state, raid, retreat, comes_in_head, comes_in, bring_more, warden (no warning for a first dungeon): " + str(ids))
	var warn_f := _fort_entry()
	warn_f["first_dungeon"] = false
	warn_f["tier"] = 2
	var wb := {}
	var wids: Array = []
	for b in _fc(warn_f, "", back, {}, _loot_cfg())["blocks"]:
		wb[b["id"]] = b
		wids.append(b["id"])
	want = ["chips", "state", "raid", "retreat", "comes_in_head", "comes_in", "bring_more", "comes_warn", "warden"]
	t.ok(wids.filter(func(i): return want.has(i)) == want, "with a warning: comes_warn sits before the warden: " + str(wids))
	t.ok(wb["comes_warn"]["key"] == "select" and wb["comes_warn"]["text"].begins_with("No undead come in:"), "nobody coming in, corpses there (dead 3.1): the select line on the card")
	warn_f["dead"] = 0.0
	var wb0 := {}
	for b in _fc(warn_f, "", back, {}, _loot_cfg())["blocks"]:
		wb0[b["id"]] = b
	t.ok(wb0["comes_warn"]["key"] == "danger" and wb0["comes_warn"]["text"].begins_with("No undead and no corpses"), "nobody and no corpses: the danger line on the card")
	t.ok(CardBlocksLogic.sig_of(wb["comes_warn"]) == CardBlocksLogic.sig_of(wb0["comes_warn"]), "the two warnings share a signature, so the view must restyle on the key")
	t.ok(wb["comes_in_head"]["text"] == "WHO COMES IN" and wb["comes_in"]["face"] == "mass" and wb["comes_in"]["text"] == "Garrison 0 (from WAR) · starter 0 · big undead 0 · total 0", "the head and the count: " + str(wb["comes_in"]["text"]))
	t.ok(wb["bring_more"]["key"] == "text_dim" and wb["bring_more"]["text"].contains("draws 3× its share") and wb["bring_more"]["text"].begins_with("Bring more: raise WAR on the valve;"), "the tide bias reads from config: " + str(wb["bring_more"]["text"]))
	t.ok(CardLogic.bring_more_text(2.5).contains("2.5×") and CardLogic.bring_more_text(3.0).contains("3×") and not CardLogic.bring_more_text(3.0).contains("3.0"), "no trailing .0")
	# the pinned line and the descend dialog text
	t.ok(CardLogic.comes_count_text({"garrison": 2, "starter": 8, "bigs": 1, "total": 11}) == "10 undead and 1 big undead come in", "the pinned count")
	t.ok(CardLogic.descend_confirm_text(w0) == w0["text"] + "\n\nDescend anyway?", "the descend dialog's text")
	t.ok(CardLogic.descend_confirm_text(wp) == wp["text"] + "\n\nDescend anyway?", "the dialog opens for the corpse-pile case too")
	# vei: fronts short versus met
	var short := {"fronts_met": 1, "fronts_required": 3}
	var sentence := "Fronts met 1 of 3 required: Vei will likely win. Assign big undead to the open fronts."
	var ro := {"odds": 0.61, "sign": 1, "drain_s": 200.0}
	t.ok(CardLogic.confirm_text(ro, short).ends_with("\n" + sentence), "confirm_text appends the shortfall on its own line")
	t.ok(CardLogic.confirm_text(ro, {"fronts_met": 3, "fronts_required": 3}) == CardLogic.confirm_text(ro) and not CardLogic.confirm_text(ro, {"fronts_met": 3, "fronts_required": 3}).contains("Fronts met"), "fronts met: no shortfall line")
	var home := {"state": "at_vei", "at": "vei"}
	var va := RelishLogic.vei_actions({"can_begin": true, "reason": "", "fronts_met": 1, "fronts_required": 3}, home)
	var wi := va.find_custom(func(i): return i["text"] == sentence)
	var bi := va.find_custom(func(i): return i["act"] == "begin")
	t.ok(wi >= 0 and wi < bi and va[wi]["key"] == "danger" and va[bi]["enabled"], "vei_actions: a danger line above an enabled BEGIN")
	t.ok(not RelishLogic.vei_actions({"can_begin": true, "reason": "", "fronts_met": 3, "fronts_required": 3}, home).any(func(i): return str(i["text"]).begins_with("Fronts met")), "no line with the fronts met")


## comes_in matches the sim's own garrison and starter counts (view_party) at the fort Relish stands at.
func _parity(t: TestUtil) -> void:
	var raid := TestUtil.load_json("res://configs/raid.json")
	var econ := TestUtil.load_json("res://configs/economy.json")
	for cs in [["day1", "old-sluice"], ["midgame_2flips", "greywall"]]:
		var s := GameState.new(TestUtil.configs())
		s.debug_enabled = true
		t.ok(s.cmd_debug_load_fixture(cs[0])["ok"], "%s loads" % cs[0])
		t.ok(s.cmd_debug_set_state({"relish_at": cs[1]})["ok"], "Relish stands at %s" % cs[1])
		var party := s.view_party()
		var fort: Dictionary = s.view_realm()["forts"].filter(func(f): return f["id"] == cs[1])[0]
		var ci := CardLogic.comes_in(fort, party, raid, econ)
		t.ok(party["fort_id"] == cs[1], "view_party is for %s" % cs[1])
		t.ok(ci["garrison"] == party["garrison_units"] and ci["starter"] == party["starter_units"], "%s: comes_in garrison %d / starter %d equal view_party's %d / %d (undead %.1f)" % [cs[1], ci["garrison"], ci["starter"], party["garrison_units"], party["starter_units"], fort["undead"]])
		# bigs: put two big undead in the party, then compare with the party the raid's own seed carries
		s.cmd_debug_grant({"big_undead": 2})
		var uids: Array = s.big_undead.map(func(b): return b["uid"])
		t.ok(uids.size() >= 2 and s.cmd_set_party(uids.slice(0, 2))["ok"], "%s: two big undead are in the party" % cs[1])
		party = s.view_party()
		ci = CardLogic.comes_in(fort, party, raid, econ)
		var begun := s.cmd_begin_dungeon(cs[1])
		var seeded: Array = s.view_dungeon_seed(cs[1]).get("party", [])
		t.ok(begun["ok"] and seeded.size() == 2, "%s: the raid starts with a party of 2 in its seed (%s)" % [cs[1], str(begun.get("reason", ""))])
		t.ok(ci["bigs"] == seeded.size(), "%s: comes_in's bigs (%d) are the raid seed's party (%d)" % [cs[1], ci["bigs"], seeded.size()])


## map_sidebar.gd names autoloads, so it is read as text: DESCEND checks who comes in before it dives, and a
## "Descend anyway" dialog (its own, so a confirmed BEGIN still dives to Vei) dives to the fort.
func _sidebar_src(t: TestUtil) -> void:
	var src := FileAccess.get_file_as_string("res://scripts/map/map_sidebar.gd")
	var a := src.find('"descend":')
	var b := src.find('"begin":')
	t.ok(a >= 0 and b > a, "the sidebar has descend and begin branches")
	var branch := src.substr(a, b - a)
	t.ok(branch.contains('["total"]') and branch.find('["total"]') < branch.find("dive.emit"), "the descend branch checks comes_in's total before dive.emit")
	t.ok(branch.contains("_descend_confirm.popup_centered()"), "and opens the dialog when nobody comes in")
	t.ok(src.contains("_descend_confirm.confirmed.connect(func(): dive.emit(_descend_id))") and src.contains("_confirm.confirmed.connect(func(): dive.emit(MapModel.VEI))"), "each dialog dives to its own id")
	t.ok(src.contains("descend_confirm_ok") and src.contains("descend_confirm_title"), "the dialog's words come from config")
	var cards: Dictionary = TestUtil.load_json("res://configs/map_view.json")["cards"]
	t.ok(cards["descend_confirm_ok"] == "Descend anyway" and cards["descend_confirm_title"] == "No undead come in", "the dialog's title and OK")
	t.ok(src.contains('items[i].get("key", "text_dim")'), "a line is coloured by its key, text_dim by default")
	t.ok(src.contains('float(f.get("dead", 0.0))'), "the sidebar passes the fort's dead to the warning")
	# the card view names autoloads, so its para restyle is read as text: the style is stored at build and re-applied when the key or face changes
	var view := FileAccess.get_file_as_string("res://scripts/map/map_card_view.gd")
	var pa := view.find('"para":', view.find("func _update"))
	var pb := view.find('"chips":', pa)
	var pbranch := view.substr(pa, pb - pa)
	t.ok(view.contains('refs["para_style"] = _para_style(blk)'), "a para's style (face and key) is stored in its refs at build")
	t.ok(pa >= 0 and pb > pa and pbranch.contains('refs.get("para_style", "") != style') and pbranch.contains('_face(refs["label"], str(blk["face"]), str(blk["key"]))'), "_update re-applies a para's face when its style changed")
	var ps := CardBlocksLogic.sig_of({"kind": "para", "id": "x", "text": "a", "key": "danger", "face": "text"})
	t.ok(ps == CardBlocksLogic.sig_of({"kind": "para", "id": "x", "text": "b", "key": "select", "face": "mass"}), "a para's signature ignores key and face (hence the restyle)")


func _loot_cfg() -> Dictionary:
	return TestUtil.load_json("res://configs/loot.json")
