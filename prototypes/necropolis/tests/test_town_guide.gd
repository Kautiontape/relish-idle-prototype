extends RefCounted
## TownGuide (Phase I clarity, Shawn's checklist items 10-11): every building says why it's worth building and how
## it's used; the first goal in town keys off existing state and ends when its step is done; essence and the build
## costs are said plainly, and nothing says to carry essence to a building.

var t: TestUtil
var cfg: Dictionary
var vcfg: Dictionary
var gcfg: Dictionary


func run() -> int:
	t = TestUtil.new()
	t.suite("town-guide")
	cfg = TestUtil.configs()
	vcfg = cfg["town"]["view"]
	gcfg = vcfg["guide"]
	_lines()
	_how_kinds()
	_goal_new_game()
	_goal_fixtures()
	_words()
	_jargon()
	_inspect()
	_upgrade_relics()
	_scroll_cue()
	return t.failures


## Clarity round 3: a dock tab with more below its scroll edge says so (ScrollCue), so a row the edge cuts reads as
## more to scroll to; at the end of the scroll, or with nothing below, the cue is gone.
func _scroll_cue() -> void:
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	var sc: Dictionary = vcfg["scroll_cue"]
	var eps := float(sc["eps_px"])
	t.ok(ScrollCue.more_below(0.0, 500.0, 900.0, eps), "cue: 400 px below the page shows it")
	t.ok(not ScrollCue.more_below(400.0, 500.0, 900.0, eps) and not ScrollCue.more_below(399.0, 500.0, 900.0, eps),
		"cue: scrolled to the end (within eps_px), no cue")
	t.ok(not ScrollCue.more_below(0.0, 500.0, 500.0, eps), "cue: content that fits shows no cue")
	t.ok(String(sc["text"]).contains("more below") and int(sc["px"]) >= TownUI.MIN_TEXT and Palette.has(String(sc["ink"]))
		and TownModel.contrast(Palette.c(String(sc["ink"])), Palette.c("ground")) >= 4.5,
		"cue: '%s' at %d px in a 4.5:1 ink" % [sc["text"], int(sc["px"])])


## The clarity round (clarity-review-1): mint, husk and phylactery get the glossary's one line wherever they show,
## and the Pit, Market and Forge say why you'd want them.
func _jargon() -> void:
	var j: Dictionary = gcfg.get("jargon", {})
	t.ok(String(j.get("mint", "")).contains("Raising Pits") and String(j.get("mint", "")).contains("FLOOD"),
		"mint: the undead the pits make, split by the valve: '%s'" % j.get("mint", ""))
	t.ok(String(j.get("husk", "")).contains("big undead") and String(j.get("husk", "")).contains("slab"),
		"husk: the frame a big undead is raised in, on the slab: '%s'" % j.get("husk", ""))
	t.ok(String(j.get("phylactery", "")).contains("revives Relish") and String(j.get("phylactery", "")).contains("once per dungeon"),
		"phylactery: revives Relish in place, once per dungeon: '%s'" % j.get("phylactery", ""))
	t.ok(TownUI.jargon_tip("+9.60/s mint now", vcfg) == String(j["mint"]), "a Pit rate's tooltip is the mint line")
	t.ok(TownUI.jargon_tip("Phylactery charge", vcfg) == String(j["phylactery"]), "the word is found in any case")
	t.ok(TownUI.jargon_tip("Lay a husk, slot remnants", vcfg) == String(j["husk"]), "the husk line where a husk shows")
	t.ok(TownUI.jargon_tip("+0.30/s gold now", vcfg) == "", "a line with no jargon has no tooltip")
	t.ok(TownUI.jargon_tip("Crafts phylactery charges and husks", vcfg).split("\n").size() == 2, "two words, two lines")
	var why: Dictionary = gcfg["why"]
	t.ok(String(why["raising_pit"]).contains("mint") and String(why["raising_pit"]).contains("WAR") and String(why["raising_pit"]).contains("FLOOD"),
		"the Pit's why says its undead are the mint, and where they go: '%s'" % why["raising_pit"])
	t.ok(String(why["market"]).contains("gold for every build"), "the Market's why: gold for every build: '%s'" % why["market"])
	t.ok(String(why["forge"]).contains("relics") and String(why["forge"]).contains("fewer die"),
		"the Forge's why: what a step gives, and that it needs relics: '%s'" % why["forge"])
	var short := BuildSort.fmt(String(gcfg.get("essence_short", "")), {"n": 14})
	t.ok(short.contains("14") and short.contains("backups") and short.length() <= 28,
		"the HUD's essence count says what essence is for, short enough for its cell: '%s'" % short)
	var head := String(vcfg["crypt"]["husk_craft"]["head"])
	t.ok(head.begins_with("A husk is the frame a big undead is raised in."), "the craft opens with what a husk is: '%s'" % head)
	t.ok(String(vcfg["backups"]["charges_usable"]).contains("revives Relish in place"),
		"the Backups tab says what a charge does where the word first shows")


## The views the shell fetches for the goal: view_town, and view_realm's forts as covington._forts digests them.
func _views(s: GameState) -> Dictionary:
	var forts: Array = []
	for f in s.view_realm().get("forts", []):
		forts.append({"id": String(f["id"]), "name": String(f["name"]), "held": bool(f["held"]),
			"flipped_count": int(f.get("flipped_count", 0)), "first_dungeon": bool(f.get("first_dungeon", false))})
	return {"town": s.view_town(), "forts": forts, "catalog": s.view_catalog(), "hud": s.view_hud(),
		"inventory": s.view_inventory()}


func _new_game() -> GameState:
	var s := GameState.new(cfg)
	s.debug_enabled = true
	s.cmd_new_game(1)
	return s


func _lines() -> void:
	var missing: Array = []
	for bid in cfg["buildings"]:
		if not cfg["buildings"][bid] is Dictionary:
			continue
		if TownGuide.why(bid, gcfg) == "" or TownGuide.how(bid, cfg["buildings"], gcfg) == "":
			missing.append(bid)
	t.ok(missing.is_empty(), "every building in buildings.json has a why-line and a how-line (missing: %s)" % str(missing))
	var stray: Array = (gcfg["why"] as Dictionary).keys().filter(func(k): return not cfg["buildings"].has(k))
	t.ok(stray.is_empty(), "every why-line names a real building (stray: %s)" % str(stray))
	t.ok(TownGuide.why("no_such_building", gcfg) == "", "an unknown building has no why-line")


func _how_kinds() -> void:
	var bc: Dictionary = cfg["buildings"]
	for pair in [["crypt", "Crypt tab"], ["chapel_of_vats", "Backups tab"], ["ossuary_tower", "Backups tab"]]:
		var h := TownGuide.how(pair[0], bc, gcfg)
		t.ok(TownGuide.by_hand(pair[0], gcfg) and h.contains(pair[1]) and TownGuide.how_key(pair[0], gcfg) == "select",
			"%s is used by hand and says where: '%s'" % [pair[0], h])
	t.ok(TownGuide.how("ossuary_tower", bc, gcfg).contains("essence"), "the Ossuary's how-line says it's paid in essence")
	var wrong: Array = []
	for bid in bc:
		if not bc[bid] is Dictionary or TownGuide.by_hand(bid, gcfg):
			continue
		var h := TownGuide.how(bid, bc, gcfg)
		var want := String(gcfg["how"]["staffed" if not (bc[bid].get("jobs", {}) as Dictionary).is_empty() else "passive"])
		if not h.begins_with("Works on its own") or h != want or TownGuide.how_key(bid, gcfg) != "text_dim":
			wrong.append(bid)
	t.ok(wrong.is_empty(), "every other building works on its own: staffed by undead when it has jobs, else no staff (wrong: %s)" % str(wrong))
	t.ok(TownGuide.how("market", bc, gcfg).contains("undead") and TownGuide.how("house", bc, gcfg).contains("no staff"),
		"a job building is staffed by your undead; a House needs no staff")
	t.ok(TownGuide.how("guildhall", bc, gcfg).contains("Stances tab"), "the Guildhall points at the Stances tab for its slot")


## A new game: the goal is the Bone Mill until one is placed, then the first fort (by the first dungeon's name)
## until a fort is taken, then nothing.
func _goal_new_game() -> void:
	var s := _new_game()
	var v := _views(s)
	var first := ""
	for f in v["forts"]:
		if f["first_dungeon"]:
			first = f["name"]
	t.ok(first != "", "(setup) a new game marks a first dungeon")
	t.ok(not TownGuide.placed(v, "bone_mill") and not TownGuide.fort_taken(v), "(setup) a new game: no Bone Mill, no fort taken")
	var g := TownGuide.goal(v, gcfg)
	t.ok(g.get("id", "") == "mill" and String(g.get("text", "")).begins_with("First step: build a Bone Mill"),
		"a new game's first step is the Bone Mill: '%s'" % g.get("text", ""))
	# clarity round 3: the game's goal heads the plate, in the glossary's words ("your goal", never "the run")
	t.ok(String(g.get("head", "")) == "Your goal: take Vei's forts, then beat Vei. Beating Vei wins the game.",
		"the plate's head is the game's goal: '%s'" % g.get("head", ""))
	t.ok(not String(g.get("head", "")).to_lower().contains("the run") and not String(g.get("text", "")).to_lower().contains("the run"),
		"the goal plate never says 'the run'")
	s.cmd_debug_grant({"gold": 500.0, "bone": 200.0})
	var lot := ""
	for row in s.view_catalog()["buildings"]:
		if row["building_id"] == "bone_mill" and not (row.get("lots", []) as Array).is_empty():
			lot = String(row["lots"][0])
	var r: Dictionary = s.cmd_build("bone_mill", lot)
	t.ok(r.get("ok", false), "(setup) a Bone Mill is placed on %s: %s" % [lot, r.get("reason", "")])
	v = _views(s)
	g = TownGuide.goal(v, gcfg)
	t.ok(TownGuide.placed(v, "bone_mill"), "a Bone Mill under construction counts as placed")
	t.ok(g.get("id", "") == "fort" and String(g.get("text", "")).contains(first) and String(g.get("text", "")).contains("Return to the realm"),
		"once the mill is placed the goal is the first fort, by name: '%s'" % g.get("text", ""))
	t.ok(String(g.get("text", "")).begins_with("Next step: ") and String(g.get("head", "")).begins_with("Your goal: "),
		"the next step takes the plate's shared lead, under the same head: '%s'" % g.get("text", ""))
	v["forts"][0]["flipped_count"] = 1  # a fort taken (held now or retaken since): the state flip_fort leaves
	t.ok(TownGuide.goal(v, gcfg).is_empty(), "once a fort is taken (and the mill placed) there is no goal")
	var no_mill: Dictionary = v.duplicate(true)
	no_mill["town"]["buildings"] = (no_mill["town"]["buildings"] as Array).filter(func(b): return b["building_id"] != "bone_mill")
	t.ok(TownGuide.goal(no_mill, gcfg).get("id", "") == "mill", "a fort taken but no mill: the goal is still the mill")
	var unnamed: Dictionary = _views(s)
	for f in unnamed["forts"]:
		f["first_dungeon"] = false
	t.ok(String(TownGuide.goal(unnamed, gcfg).get("text", "")).contains(String(gcfg["goal"]["fort_any"])),
		"with no first dungeon marked the goal says '%s'" % gcfg["goal"]["fort_any"])


func _goal_fixtures() -> void:
	for fx in ["day1", "midgame_2flips", "pre_vei"]:
		var s := GameState.new(cfg)
		s.debug_enabled = true
		t.ok(s.cmd_debug_load_fixture(fx)["ok"], "(setup) %s loads" % fx)
		var g := TownGuide.goal(_views(s), gcfg)
		if fx == "day1":
			t.ok(g.get("id", "") == "mill", "day1 (no mill, no fort taken) shows the mill goal")
		elif fx == "midgame_2flips":
			t.ok(g.is_empty(), "midgame_2flips (mill built, two forts held) shows no goal: '%s'" % g.get("text", ""))
		else:  # pre_vei loads its forts unheld (no held_s in the fixture), but it is a City: past the early tiers
			t.ok(g.is_empty() and not String(_views(s)["town"]["tier"]) in gcfg["goal"]["tiers"],
				"pre_vei (City tier) shows no goal: '%s'" % g.get("text", ""))
	var late := {"town": {"buildings": [], "tier": "town"}, "forts": []}
	t.ok(TownGuide.goal(late, gcfg).is_empty(), "a Town-tier town with no mill and no fort shows no first goal")
	var held := {"town": {"buildings": [{"building_id": "bone_mill"}], "tier": "village"}, "forts": [{"held": true, "flipped_count": 0}]}
	t.ok(TownGuide.goal(held, gcfg).is_empty(), "a fort held (an old save's flipped_count 0) counts as taken")


## The words Shawn's item 11 asks for: essence comes home from raids and pays for backups at the Ossuary; buildings
## are paid in gold and bone the town makes, relics from raids; nothing says to carry essence to a building.
func _words() -> void:
	var ess := String(gcfg["essence_line"])
	t.ok(ess.contains("raids") and ess.contains("Ossuary Tower") and ess.contains("backups") and ess.contains("never for buildings"),
		"the essence line: from raids, for backups at the Ossuary, never buildings: '%s'" % ess)
	var paid := String(gcfg["paid_line"])
	t.ok(paid.contains("gold and bone") and paid.contains("your town makes") and paid.contains("relics: raid a fort"),
		"the paid line: gold and bone your town makes; relics from a raid: '%s'" % paid)
	var bad: Array = []
	for s in _strings(cfg["town"]):
		var low := String(s).to_lower()
		if low.contains("essence") and (low.contains("carry") or low.contains("deliver") or low.contains("bring") or low.contains("take it to")):
			bad.append(s)
	t.ok(bad.is_empty(), "no town text tells the player to carry essence anywhere (%s)" % str(bad))
	for built in [[], [{"building_id": "bone_mill"}]]:  # the mill step, then the fort step
		var g := TownGuide.goal({"town": {"buildings": built, "tier": "hamlet"}, "forts": [{"first_dungeon": true, "name": "Old Sluice"}]}, gcfg)
		t.ok(g.get("text", "") != "" and String(g["text"]).length() <= 100,
			"the goal is one short line (%d chars): '%s'" % [String(g.get("text", "")).length(), g.get("text", "")])
	var long: Array = []
	for bid in gcfg["why"]:
		if String(gcfg["why"][bid]).length() > 90:
			long.append(bid)
	t.ok(long.is_empty(), "every why-line is one short line, at most 90 characters (long: %s)" % str(long))


func _strings(d: Variant) -> Array:
	var out: Array = []
	if d is Dictionary:
		for k in d:
			out.append_array(_strings(d[k]))
	elif d is Array:
		for x in d:
			out.append_array(_strings(x))
	elif d is String:
		out.append(d)
	return out


## The inspector's purpose and use lines come with BuildSort.inspect (the dock's inspector and the lot card's).
func _inspect() -> void:
	var s := _new_game()
	var st := BuildSort.stocks(_views(s))
	for b in s.view_town()["buildings"]:
		var i := BuildSort.inspect(b, st, cfg["buildings"], cfg["buildings_view"], vcfg)
		var bid := String(b["building_id"])
		t.ok(i["purpose"] == TownGuide.why(bid, gcfg) and i["use"] == TownGuide.how(bid, cfg["buildings"], gcfg)
			and i["use_key"] == TownGuide.how_key(bid, gcfg) and i["purpose"] != "",
			"inspect(%s) carries its why and how: '%s' / '%s'" % [bid, i["purpose"], i["use"]])


## A new game's Crypt upgrade is short of gold and of a relic: the line says the gold first, then the relic.
func _upgrade_relics() -> void:
	var s := _new_game()
	var st := BuildSort.stocks(_views(s))
	var crypt: Dictionary = {}
	for b in s.view_town()["buildings"]:
		if b["building_id"] == "crypt":
			crypt = b
	var i := BuildSort.inspect(crypt, st, cfg["buildings"], cfg["buildings_view"], vcfg)
	var u: Dictionary = i["upgrade"]
	var why := BuildSort.upgrade_reason(u, st, cfg["buildings_view"], vcfg)
	t.ok(int(u["cost"]["relics"]) > int(st["relics"]) and u["reason"] in ["no_gold", "no_bone"],
		"(setup) a new game's Crypt upgrade is short of %s and of relics (%s)" % [u["reason"], JSON.stringify(u["cost"])])
	t.ok(why.contains("needs %d relic" % int(u["cost"]["relics"])) and why.ends_with("raid a fort"),
		"the upgrade line says the relic too: '%s'" % why)
	u = u.duplicate(true)
	u["reason"] = "max_level"
	t.ok(not BuildSort.upgrade_reason(u, st, cfg["buildings_view"], vcfg).contains("relic"), "a top-level building says nothing of relics")
