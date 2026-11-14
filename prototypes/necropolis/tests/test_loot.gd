extends RefCounted
## Pure-logic tests for RaidLoot and configs/loot.json. No scene tree, no autoloads.

const OWNED_NONE: Array = []


func _rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r


func _info(tier := 2, arche := "bellringer", first := false, husk := false, y := 1.0) -> Dictionary:
	return {"tier": tier, "archetype": arche, "first_clear": first, "chest_husk": husk, "yield_mult": y}


func _item_ok(loot: Dictionary) -> bool:
	for r in loot["remnants"]:
		if not (GameState.STATS.has(r["aspect"]) and GameState.RARITIES.has(r["rarity"]) and int(r["magnitude"]) >= 1):
			return false
	for h in loot["husks"]:
		if not GameState.HUSK_KINDS.has(h["kind"]):
			return false
	return true


func run() -> int:
	var t := TestUtil.new()
	var cfg := TestUtil.load_json("res://configs/loot.json")
	var rcfg := TestUtil.load_json("res://configs/raid.json")
	var bcfg := TestUtil.load_json("res://configs/buildings.json")

	t.suite("loot_config")
	# reclear_decay / recover_s feed the economy's yield_mult (STATE-API view_fort); the dungeon reads only yield_mult (loot_yield)
	t.ok(TestUtil.configs().has("loot"), "ConfigDb-style load picks up loot.json by filename")
	t.ok(RaidLoot.ASPECTS == GameState.STATS and RaidLoot.RARITIES == GameState.RARITIES, "aspect and rarity lists match GameState")
	var bp_ok := true
	var bp_text := JSON.stringify(bcfg)
	for k in cfg["first_clear_blueprint_by_tier"]:
		for id in cfg["first_clear_blueprint_by_tier"][k]:
			bp_ok = bp_ok and bp_text.contains("\"%s\"" % id)
	t.ok(bp_ok, "every configured blueprint id is a building requirement")
	var kinds_ok := GameState.HUSK_KINDS.has(str(cfg["first_dungeon_husk"]))
	for k in cfg["chest_by_tier"]:
		for kind in cfg["chest_by_tier"][k]["husk_kinds"]:
			kinds_ok = kinds_ok and GameState.HUSK_KINDS.has(kind)
	t.ok(kinds_ok, "every configured husk kind is valid")

	t.suite("loot_determinism")
	var a := _rng(77)
	var b := _rng(77)
	var ra: Array = []
	var rb: Array = []
	for i in 300:
		ra.append(RaidLoot.ding(a, 1 + i % 4, "huntsman", 1.0, cfg))
		rb.append(RaidLoot.ding(b, 1 + i % 4, "huntsman", 1.0, cfg))
	ra.append(RaidLoot.chest(a, _info(3, "huntsman", true, true), ["embalmer"], cfg))
	rb.append(RaidLoot.chest(b, _info(3, "huntsman", true, true), ["embalmer"], cfg))
	t.ok(ra == rb, "same seed and call order give identical dings and chest")
	t.ok(ra != Array(range(0)), "the run is not empty")
	var diff := false
	var c := _rng(78)
	for i in 300:
		if RaidLoot.ding(c, 1 + i % 4, "huntsman", 1.0, cfg) != ra[i]:
			diff = true
			break
	t.ok(diff, "a different seed differs")

	t.suite("loot_valid")
	var all_ok := true
	var rv := _rng(5)
	var seen_rar := {}
	for i in 600:
		var d := RaidLoot.ding(rv, 1 + i % 4, ["bellringer", "huntsman", ""][i % 3], 1.0, cfg)
		if not d.is_empty():
			seen_rar[d["rarity"]] = true
			all_ok = all_ok and _item_ok({"remnants": [d], "husks": []})
	t.ok(all_ok, "every ding passes aspect, rarity and magnitude checks")
	t.ok(seen_rar.has("common") and seen_rar.has("uncommon"), "dings include commons and uncommons")
	var chests_ok := true
	var res_ok := true
	var lg := RaidLogic.LedgerV2.new(RaidLogic.demo_seed(rcfg), rcfg)
	for i in 80:
		var loot := RaidLoot.chest(rv, _info(1 + i % 4, ["bellringer", "huntsman"][i % 2], i % 2 == 0, i % 3 == 0, 1.0), ["embalmer"], cfg)
		chests_ok = chests_ok and _item_ok(loot) and loot.keys().size() == 5
		var r := lg.build_result(RaidLogic.demo_seed(rcfg), "warden_beaten", [], [], 0, loot, rcfg)
		res_ok = res_ok and Results.validate("raid", r) == []
	t.ok(chests_ok, "every chest item is valid and has the full loot shape")
	t.ok(res_ok, "chest loot inside a raid result passes Results.validate")
	var hc := RaidLoot.held_clear(_rng(3), 2, 1.0, cfg)
	t.ok(_item_ok(hc), "held_clear items are valid")

	t.suite("loot_yield")
	var hi := 0
	var lo := 0
	var r1 := _rng(11)
	var r2 := _rng(11)
	for i in 4000:
		hi += 0 if RaidLoot.ding(r1, 3, "bellringer", 1.0, cfg).is_empty() else 1
		lo += 0 if RaidLoot.ding(r2, 3, "bellringer", 0.25, cfg).is_empty() else 1
	t.ok(hi > lo * 2.5, "ding hits fall with yield (%d at 1.0 vs %d at 0.25)" % [hi, lo])
	t.near(float(hi) / 4000.0, 0.10, 0.02, "tier 3 ding rate is near its configured 0.10")
	var rel_hi := 0
	var rel_lo := 0
	var rem_hi := 0
	var rem_lo := 0
	var hk_hi := 0
	var hk_lo := 0
	var q1 := _rng(21)
	var q2 := _rng(21)
	for i in 1000:
		var h1 := RaidLoot.chest(q1, _info(2), OWNED_NONE, cfg)
		var l1 := RaidLoot.chest(q2, _info(2, "bellringer", false, false, 0.25), OWNED_NONE, cfg)
		rel_hi += int(h1["relics"])
		rel_lo += int(l1["relics"])
		rem_hi += (h1["remnants"] as Array).size()
		rem_lo += (l1["remnants"] as Array).size()
		hk_hi += (h1["husks"] as Array).size()
		hk_lo += (l1["husks"] as Array).size()
	t.ok(rel_hi > rel_lo * 2.5, "chest relics fall with yield (%d vs %d)" % [rel_hi, rel_lo])
	t.ok(rem_hi > rem_lo * 2.5, "chest remnants fall with yield (%d vs %d)" % [rem_hi, rem_lo])
	t.ok(hk_hi > hk_lo * 2.0, "chest husk chance falls with yield (%d vs %d)" % [hk_hi, hk_lo])
	var sc := 0
	var sr := _rng(9)
	for i in 4000:
		sc += RaidLoot.scaled_count(sr, 3.0, 0.5)
	t.near(float(sc) / 4000.0, 1.5, 0.05, "scaled_count keeps the expected value")
	t.ok(RaidLoot.scaled_count(_rng(1), 4.0, 1.0) == 4, "scaled_count of a whole number is exact")
	t.ok(RaidLoot.scaled_count(_rng(1), 4.0, 0.0) == 0, "yield 0 gives nothing")
	t.ok(RaidLoot.ding(_rng(1), 4, "bellringer", 0.0, cfg).is_empty(), "yield 0 gives no dings")

	t.suite("loot_first_clear")
	var fc_ok := true
	var owned_mix: Array = ["embalmer"]
	for i in 40:
		var loot := RaidLoot.chest(_rng(i), _info(3, "bellringer", true), owned_mix, cfg)
		fc_ok = fc_ok and (loot["blueprints"] as Array).size() == 1 and not owned_mix.has(loot["blueprints"][0])
	t.ok(fc_ok, "a first clear gives exactly one blueprint the player does not own")
	t.ok(RaidLoot.chest(_rng(1), _info(1, "bellringer", true), OWNED_NONE, cfg)["blueprints"] == ["embalmer"], "tier 1 first clear gives embalmer")
	t.ok(RaidLoot.chest(_rng(1), _info(3, "bellringer", true), ["embalmer"], cfg)["blueprints"] == ["ossuary_tower"], "next unowned in order")
	t.ok(RaidLoot.chest(_rng(1), _info(1, "bellringer", true), ["embalmer"], cfg)["blueprints"] == [], "no blueprint above the fort's tier")
	var all_owned := ["embalmer", "ossuary_tower", "reliquary"]
	var plain := RaidLoot.chest(_rng(4), _info(3, "bellringer", false), all_owned, cfg)
	var capped := RaidLoot.chest(_rng(4), _info(3, "bellringer", true), all_owned, cfg)
	t.ok((capped["blueprints"] as Array).is_empty() and int(capped["relics"]) == int(plain["relics"]) + 1, "all owned gives +1 relic instead")
	t.ok((RaidLoot.chest(_rng(4), _info(3, "bellringer", false), OWNED_NONE, cfg)["blueprints"] as Array).is_empty(), "no blueprint when it is not a first clear")
	var lowy := RaidLoot.chest(_rng(4), _info(2, "bellringer", true, false, 0.0), OWNED_NONE, cfg)
	t.ok((lowy["blueprints"] as Array).size() == 1, "the blueprint is not scaled by yield")

	t.suite("loot_husk")
	var hk := RaidLoot.chest(_rng(2), _info(1, "bellringer", true, true, 0.0), OWNED_NONE, cfg)
	t.ok(hk["husks"] == [{"kind": "skeleton"}], "chest_husk gives the starter skeleton even at yield 0")
	var no_hk := RaidLoot.chest(_rng(2), _info(1, "bellringer", true, false, 0.0), OWNED_NONE, cfg)
	t.ok((no_hk["husks"] as Array).is_empty(), "no chest_husk and yield 0 gives no husk")

	t.suite("loot_held")
	var held_ok := true
	for i in 20:
		var h := RaidLoot.held_clear(_rng(i), 2, 1.0, cfg)
		var n := int(h["relics"]) + (h["remnants"] as Array).size() + int(h["essence"])
		held_ok = held_ok and n > 0 and int(h["essence"]) >= 2 and (h["blueprints"] as Array).is_empty()
	t.ok(held_ok, "held_clear is non-empty at yield 1 and carries essence motes")
	var h0 := RaidLoot.held_clear(_rng(1), 2, 0.0, cfg)
	t.ok(int(h0["relics"]) == 0 and int(h0["essence"]) == 0 and (h0["remnants"] as Array).is_empty(), "held_clear shrinks to nothing at yield 0")

	t.suite("loot_card_line")
	var fort := {"tier": 2, "warden": {"archetype": "bellringer"}, "first_clear": true, "first_dungeon": false,
		"yield_mult": 1.0, "held": false}
	t.ok(RaidLoot.card_line(fort, cfg) == "loot: blueprint · relics 2–3 · remnants (beef) · yield 100%", "first clear line: " + RaidLoot.card_line(fort, cfg))
	var hunt := fort.duplicate(true)
	hunt["warden"]["archetype"] = "huntsman"
	hunt["first_clear"] = false
	t.ok(RaidLoot.card_line(hunt, cfg) == "loot: relics 2–3 · remnants (speed) · yield 100%", "cleared line: " + RaidLoot.card_line(hunt, cfg))
	var fd := fort.duplicate(true)
	fd["tier"] = 1
	fd["first_dungeon"] = true
	t.ok(RaidLoot.card_line(fd, cfg).begins_with("loot: blueprint · husk · relics 1–2"), "first dungeon line shows the husk: " + RaidLoot.card_line(fd, cfg))
	var refill := hunt.duplicate(true)
	refill["yield_mult"] = 0.55
	t.ok(RaidLoot.card_line(refill, cfg) == "refilling · yield 55%", "refilling line: " + RaidLoot.card_line(refill, cfg))
	var heldf := hunt.duplicate(true)
	heldf["held"] = true
	var hl := RaidLoot.card_line(heldf, cfg)
	t.ok(hl.begins_with("held") and "essence 2–4" in hl and hl.ends_with("yield 100%"), "held line: " + hl)
	var held_part := heldf.duplicate(true)
	held_part["yield_mult"] = 0.4
	var hp_line := RaidLoot.card_line(held_part, cfg)
	t.ok(hp_line.begins_with("held · counter-garrison:") and "relics 0–1" in hp_line and "remnants 1" in hp_line and hp_line.ends_with("yield 40%"),
		"held card shows the counter-garrison reward even while refilling: " + hp_line)
	t.ok(not ("loot:" in hl) and not ("blueprint" in hl), "held card carries no warden chest lines: " + hl)
	var plainf := fort.duplicate(true)
	plainf["warden"]["archetype"] = ""
	t.ok("remnants · yield" in RaidLoot.card_line(plainf, cfg), "no single lean shows plain remnants")

	t.suite("loot_hint")
	t.ok(RaidLoot.hint("t2.bellringer", false, cfg) == cfg["hints"]["t2.bellringer"] and cfg["hints"]["t2.bellringer"] != "", "known table has its phrase")
	t.ok(RaidLoot.hint("t2.bellringer", true, cfg) == "a husk and a blueprint", "first dungeon hint wins")
	t.ok(RaidLoot.hint("t9.nothing", false, cfg) == "", "unknown table is empty")
	var all_tables := true
	for tier in [1, 2, 3, 4]:
		for ar in ["bellringer", "huntsman"]:
			all_tables = all_tables and RaidLoot.hint("t%d.%s" % [tier, ar], false, cfg) != ""
	t.ok(all_tables, "every tier and archetype has a hint")
	return t.failures
