extends RefCounted
## The V-I1 fix round's town items (briefs/v-i1-round.md, town-i): the queue row's stray "..", the suggestion's tag
## clear of other buildings' labels, the workers' muster lump read as hands not a rate, and a lot click that never
## opens a card repeating the dock. (The goal plate at every tier is test_town_guide's _goal_fixtures.)

const VIEW := Rect2(0, 0, 1040, 780)  # the town view at 1600x900 (the HUD on top, the dock on the right)

var t: TestUtil
var cfg: Dictionary
var vcfg: Dictionary


func run() -> int:
	t = TestUtil.new()
	t.suite("town-vi1")
	cfg = TestUtil.configs()
	vcfg = cfg["town"]["view"]
	_queue_detail()
	_chip()
	_burst()
	_lot_click()
	_plate_fits()
	return t.failures


## The goal plate's step at its worst (every gate building of the next tier missing, two-digit counts): one line that
## fits inside the town view from the plate's x, so the plate (and the cover rect the suggestion's tag keeps clear of)
## never runs past the view. And with no forts digest, a neutral realm step, never "face Vei".
func _plate_fits() -> void:
	var g: Dictionary = vcfg["guide"]["goal"]
	var font := ThemeDB.fallback_font
	var room := VIEW.size.x - float(g["x_px"]) - 2.0 * 8.0 - 8.0  # the panel's content margins, and a little air
	var tiers: Dictionary = cfg["economy"]["town"]["tiers"]
	var order := ["hamlet", "village", "town", "city"]
	var forts: Array = []
	for i in 12:
		forts.append({"held": i == 0, "flipped_count": 1 if i == 0 else 0, "first_dungeon": i == 0, "name": "Mourner's Gate"})
	var lines: Array = []
	for i in 3:
		var to: Dictionary = tiers[order[i + 1]]
		var need := int(to["buildings"])
		var v := {"town": {"tier": order[i], "buildings": [{"building_id": "bone_mill"}],
			"next_tier": {"tier": order[i + 1], "have": need - 1, "need": need, "missing": to["requires"]}}, "forts": forts}
		var s := TownGuide.step(v, vcfg["guide"], vcfg["hud"], cfg["buildings_view"])
		t.ok(s["id"] == "tier", "(setup) %s → %s: the tier step: '%s'" % [order[i], order[i + 1], s["text"]])
		lines.append(s["text"])
	var lead := String(g["lead"])
	lines.append(lead + BuildSort.fmt(String(g["relics"]), {"tier": "Village", "n": 99, "unit": "relics", "have": 98}))
	for id in ["forts", "vei", "forts_any"]:
		lines.append(lead + BuildSort.fmt(String(g[id]), {"n": 99}))
	lines.append(String(g["won"]))   # P7: the won step (no lead) and the won head over it
	lines.append(String(g["won_head"]))
	for st in g["steps"]:
		lines.append(String(st.get("lead", lead)) + BuildSort.fmt(String(st["text"]), {"fort": "Mourner's Gate"}))
	for ln in lines:
		var w := font.get_string_size(String(ln), HORIZONTAL_ALIGNMENT_LEFT, -1, int(g["px"])).x
		t.ok(w <= room and String(ln).length() <= 100, "the plate's step fits the view (%d of %d px, %d chars): '%s'" % [w, room, String(ln).length(), ln])
	var bare := {"town": {"tier": "city", "buildings": [{"building_id": "bone_mill"}], "next_tier": {"tier": "", "have": 20, "need": 0, "missing": []}}, "forts": []}
	var s0 := TownGuide.step(bare, vcfg["guide"], vcfg["hud"], cfg["buildings_view"])
	t.ok(s0["id"] == "forts_any" and not String(s0["text"]).contains("still hers") and String(s0["short"]).begins_with("next: take Vei's forts"),
		"no forts digest at the top tier: the goal's own step, not 'face Vei': '%s' / '%s'" % [s0["text"], s0["short"]])


func _fixture(fx: String) -> GameState:
	var s := GameState.new(cfg)
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture(fx)["ok"], "(setup) %s loads" % fx)
	return s


func _catalog(s: GameState) -> Dictionary:
	var out := {}
	for r in s.view_catalog()["buildings"]:
		out[String(r["building_id"])] = r
	return out


## t-queue-gated: "1. Inn on lot 13" read ".. queued: waits for its lot to open at a higher tier". The gate wait's
## line now leads with its words; every other status keeps its glyph and ink.
func _queue_detail() -> void:
	var s := _fixture("day1")
	var r: Dictionary = s.cmd_queue_build("inn", "lot-13")
	t.ok(r["ok"], "(setup) day1 queues an Inn on locked lot 13: %s" % r.get("reason", ""))
	var e: Dictionary = s.view_town()["queue"][0]
	var cat := _catalog(s)
	var st := BuildSort.stocks({"town": s.view_town(), "hud": s.view_hud(), "catalog": s.view_catalog(), "inventory": s.view_inventory()})
	var bv: Dictionary = cfg["buildings_view"]
	t.ok(BuildSort.is_gate_wait(e, vcfg), "(setup) its row is a gate it waits out (%s / %s)" % [e["status"], e["reason"]])
	var d := BuildSort.queue_detail(e, cat, st, bv, vcfg)
	t.ok(String(d["text"]) == "queued: waits for its lot to open at a higher tier" and d["key"] == "text_dim",
		"the gated row's note leads with its words, no '..': '%s'" % d["text"])
	t.ok(not String(d["text"]).begins_with("."), "no stray dots lead it")
	var taken := e.duplicate()
	taken["reason"] = "lot_taken"
	var dt := BuildSort.queue_detail(taken, cat, st, bv, vcfg)
	t.ok(String(dt["text"]).begins_with("x skipped: ") and dt["key"] == "danger", "a real skip keeps its x and its danger ink: '%s'" % dt["text"])
	for pair in [["next", "> next: building now", "text"], ["queued", "- queued", "text_dim"]]:
		var q := e.duplicate()
		q["status"] = pair[0]
		q["reason"] = ""
		var dq := BuildSort.queue_detail(q, cat, st, bv, vcfg)
		t.ok(dq["text"] == pair[1] and dq["key"] == pair[2], "a %s row reads '%s' (got '%s')" % [pair[0], pair[1], dq["text"]])
	var panel := FileAccess.get_file_as_string("res://scripts/town/panel_build.gd")
	t.ok(panel.contains("BuildSort.queue_detail(") and not panel.contains("\"..\""), "the Build tab's queue rows take BuildSort.queue_detail, and no '..' glyph is left")


## t-card-ossuary / t-relic-row: at City the "suggested: upgrade Raising Pit to L3" tag sat on the "4 working" of the
## Raising Pit above its lot ("rking"). On pre_vei's real layout, for every building's lot as the suggestion: the tag
## lands clear of every other lot, badge and name when any of its spots is clear, and always flush over or under its own lot.
func _chip() -> void:
	var s := _fixture("pre_vei")
	var views := {"town": s.view_town(), "hud": s.view_hud(), "rates": s.view_rates(), "catalog": s.view_catalog(),
		"stances": s.view_stances(), "backups": s.view_backups(), "inventory": s.view_inventory(),
		"big_undead": s.view_big_undead(), "relish": s.view_relish(), "vei": s.view_vei(), "fort_names": {}}
	var m := TownModel.new(cfg["town"], cfg["buildings_view"], cfg["buildings"], cfg["economy"])
	m.update(views, VIEW)
	var font := ThemeDB.fallback_font
	var fs := maxi(int(vcfg.get("label_px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
	var text := String(vcfg["suggest"]["tag_prefix"]) + "upgrade Raising Pit to L3"
	var x_w := float(vcfg["suggest"]["x_px"]) * 2.0 + float(vcfg["suggest"]["tag_pad_px"]) * 2.0
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var size := Vector2(sz.x + float(vcfg["suggest"]["tag_pad_px"]) * 2.0 + x_w, sz.y + float(vcfg["suggest"]["tag_pad_px"]))
	var room := BuildSort.dismiss_room(x_w)
	var grow := float(vcfg["hover"]["grow_px"]) + 2.0
	var old_badge_hits: Array = []
	var bad: Array = []
	var stuck: Array = []
	var n := 0
	for l in m.lots:
		if (l["building"] as Dictionary).is_empty():
			continue
		n += 1
		var id := String(l["id"])
		var r := (l["rect"] as Rect2).grow(grow)
		var keep := m.sug_keep(id, font, VIEW.size.x)
		var below := r.end.y
		for p in TownModel.badge_plates(l["building"], vcfg["badge"], font, VIEW.size.x):
			below = maxf(below, (p["rect"] as Rect2).end.y)
		var at := BuildSort.sug_place(r, size, room, keep, VIEW.size, below, 6.0)
		var plate := Rect2(at["pos"], size)  # what shows (the dismiss box's reach is invisible)
		t.ok(plate.end.x + room <= VIEW.size.x and plate.position.x >= 0.0, "%s: the tag and its dismiss reach stay in the view" % id)
		# before: centred above, with no look at its neighbours
		var old := Rect2(Vector2(clampf(r.get_center().x - size.x * 0.5, 4.0, maxf(VIEW.size.x - size.x - room - 4.0, 4.0)),
			r.position.y - size.y - 6.0), size)
		var badges: Array = []
		for o in m.lots:
			if String(o["id"]) != id and not (o["building"] as Dictionary).is_empty():
				for p in TownModel.badge_plates(o["building"], vcfg["badge"], font, VIEW.size.x):
					badges.append(p["rect"])
		if badges.any(func(k): return (k as Rect2).intersects(old)):
			old_badge_hits.append(id)
		if keep.any(func(k): return (k as Rect2).intersects(plate)):
			stuck.append(id)  # no spot was clear: the old place (a layout can be that tight)
		if String((l["building"] as Dictionary).get("building_id", "")) == TownModel.HEART:  # the crypt suggested: its own name shows
			var nm: Rect2 = TownModel.name_plate(l["rect"], String(l["building"].get("label", "")), font, fs)["rect"]
			t.ok(not nm.intersects(plate) and keep.has(nm), "the crypt suggested (%s): its tag keeps clear of its own name" % id)
		# its own: over its lot's span, and over its top edge (above it, or tucked half over it) or under its foot
		var own := plate.position.x < r.end.x and plate.end.x > r.position.x and (plate.position.y < r.position.y or plate.position.y >= r.end.y)
		if not own:
			bad.append(id)
	t.ok(n > 10, "(setup) pre_vei's City has its buildings laid out (%d)" % n)
	t.ok(not old_badge_hits.is_empty(), "(the bug) centred above, a tag sat on a neighbour's badge on lots %s" % str(old_badge_hits))
	var fixed := old_badge_hits.filter(func(id): return not stuck.has(id))
	t.ok(fixed.size() == old_badge_hits.size(), "every one of those now lands clear of every lot, badge and name (still covered: %s)" % str(stuck))
	t.ok(bad.is_empty(), "the tag stays over or under its own lot, overlapping its span, so it reads as that lot's (not: %s)" % str(bad))
	# the pure rule: a clear spot is taken in order (above centred, above right-flush, above left-flush, below …)
	var lot := Rect2(300, 300, 160, 100)
	var tag := Vector2(200, 24)
	t.ok(BuildSort.sug_place(lot, tag, 0.0, [], VIEW.size, 410.0, 6.0) == {"pos": Vector2(280, 270), "above": true}, "nothing in the way: centred above")
	var right_badge := [Rect2(470, 260, 50, 20)]  # a neighbour's badge over the lot's right end: right-flush clears it
	t.ok(BuildSort.sug_place(lot, tag, 0.0, right_badge, VIEW.size, 410.0, 6.0) == {"pos": Vector2(260, 270), "above": true},
		"a badge at the right: flush with the lot's right edge")
	var both := [Rect2(470, 260, 50, 20), Rect2(250, 260, 20, 20)]  # and one at the left: no flush spot above clears both
	t.ok(BuildSort.sug_place(lot, tag, 0.0, both, VIEW.size, 410.0, 6.0) == {"pos": Vector2(280, 288), "above": true},
		"badges at both ends above: tucked half over the lot's top edge, centred: %s" % str(BuildSort.sug_place(lot, tag, 0.0, both, VIEW.size, 410.0, 6.0)))
	var tight := [Rect2(0, 260, 1040, 22)]  # a row of badges ending 18 px over the lot: tucked half over its top edge
	t.ok(BuildSort.sug_place(lot, tag, 0.0, tight, VIEW.size, 410.0, 6.0) == {"pos": Vector2(280, 288), "above": true},
		"a row of badges just above: tucked half over the lot's top edge")
	var above_full := [Rect2(0, 260, 1040, 30)]
	t.ok(BuildSort.sug_place(lot, tag, 0.0, above_full, VIEW.size, 410.0, 6.0) == {"pos": Vector2(280, 416), "above": false},
		"a row of labels down to the lot: under the lot, past its own badge")
	t.ok(BuildSort.sug_place(lot, tag, 0.0, [Rect2(0, 0, 1040, 780)], VIEW.size, 410.0, 6.0) == {"pos": Vector2(280, 270), "above": true},
		"nothing clear: centred above, as before")
	var layer := FileAccess.get_file_as_string("res://scripts/town/town_build_layer.gd")
	var view := FileAccess.get_file_as_string("res://scripts/town/town_view.gd")
	t.ok(layer.contains("BuildSort.sug_place(") and layer.contains("model.sug_keep(") and layer.contains("keep.append(cover)"),
		"the build layer places its tag by sug_place, clear of sug_keep and the goal plate")
	t.ok(view.contains("TownModel.badge_plates(") and view.contains("TownModel.name_plate("),
		"the labels layer draws the badges and names from the same plates the tag keeps clear of")


## t-card-ossuary: "workers −4.00/s" at City. pre_vei loads 35 workers, 12 idle against an idle cap of 10; the first
## 0.5 s substep musters the 2 over the cap at once, which view_hud reads as −4.00/s for that substep, then ±0.00/s.
## A staffed building demolished in play frees its hands and does the same. The cell shows the settled rate and the
## lump in hands.
func _burst() -> void:
	var h: Dictionary = vcfg["hud"]
	var dt := float(cfg["economy"]["sim"]["substep_s"])
	var s := _fixture("pre_vei")
	s.tick(dt)
	var w: Dictionary = s.view_town()["workers"]
	var net := float(BuildSort.hud_rate(s.view_hud(), "workers").get("rate", 0.0))
	var b := HudModel.muster_burst(w, dt, h)
	t.ok(net < -3.0, "(the shot's state) pre_vei's first substep reads workers %.2f/s" % net)
	t.ok(not b.is_empty() and absf(float(b["hands"]) - 2.0) < 0.05, "it is a lump of 2 hands over the idle cap: %s" % str(b))
	t.ok(not b.is_empty() and absf(net + float(b["extra"])) < 0.05, "less the lump the cell shows the settled rate: %.3f/s" % (net + float(b.get("extra", 0.0))))
	t.ok(not b.is_empty() and String(h["text"]["burst"]).format({"n": roundi(float(b["hands"]))}) == "2 over the idle cap mustered at once",
		"its words: '%s'" % String(h["text"]["burst"]).format({"n": roundi(float(b.get("hands", 0.0)))}))
	var town: Dictionary = s.view_town()
	var steady := float(w["steady"])
	var kept := HudModel.kept(town, s.view_hud())
	var raw := HudModel.surplus_rate(town, steady, kept, h)
	var shown := HudModel.surplus_rate(town, steady, kept, h, b)
	t.ok(raw > 3.0 and absf(shown - float(w["muster_steady"])) < 0.01,
		"the 'idle → FLOOD' row under it reads the settled rate too (%.2f/s, not %.2f/s), so the cell agrees with itself" % [shown, raw])
	for i in 4:
		s.tick(dt)
	var w2: Dictionary = s.view_town()["workers"]
	t.ok(HudModel.muster_burst(w2, dt, h).is_empty() and absf(float(BuildSort.hud_rate(s.view_hud(), "workers").get("rate", 0.0))) < 0.01,
		"two seconds on: no lump, and the net is ±0.00/s (the −4.00 was one substep)")
	# real play: a staffed building demolished
	var m := _fixture("midgame_2flips")
	for i in 20:
		m.tick(dt)
	var lot := ""
	for bb in m.view_town()["buildings"]:
		if float(bb.get("staffed", 0.0)) >= 2.0 and String(bb["building_id"]) != "crypt":
			lot = String(bb["lot_id"])
			break
	t.ok(lot != "" and m.cmd_demolish(lot)["ok"], "(setup) midgame demolishes a staffed building on %s" % lot)
	m.tick(dt)
	var bm := HudModel.muster_burst(m.view_town()["workers"], dt, h)
	var mnet := float(BuildSort.hud_rate(m.view_hud(), "workers").get("rate", 0.0))
	t.ok(not bm.is_empty() and float(bm["hands"]) >= 1.5 and absf(mnet + float(bm["extra"])) < 0.05,
		"a demolish in play: a lump of %.1f hands (%.2f/s raw), shown as %.3f/s" % [float(bm.get("hands", 0.0)), mnet, mnet + float(bm.get("extra", 0.0))])
	t.ok(HudModel.muster_burst({"muster": 0.36, "muster_steady": 0.35}, dt, h).is_empty(), "a settled muster is no lump")
	t.ok(HudModel.muster_burst({"muster": 0.2, "muster_steady": 0.5}, dt, h).is_empty(), "a muster under its settled rate is no lump")
	var hud := FileAccess.get_file_as_string("res://scripts/town/town_hud.gd")
	t.ok(hud.contains("HudModel.muster_burst(") and hud.contains("net += float(burst[\"extra\"])")
		and hud.contains("HudModel.surplus_rate(town, steady, kept, _hcfg, burst)"), "the workers cell reads HudModel.muster_burst, in its net, split and idle row")


## t-card-crypt / t-card-house: a click on a built lot opened the Lot card repeating the dock's inspector over the town.
func _lot_click() -> void:
	t.ok(BuildSort.lot_click("lot-01", true, true, true) == "dock", "a built lot, the Build tab showing: the dock's inspector, no card")
	t.ok(BuildSort.lot_click("lot-01", true, true, false) == "inspect", "a built lot, another tab showing: the card (the only place it shows)")
	t.ok(BuildSort.lot_click("lot-09", false, true, true) == "catalog", "an empty open lot: the card's what-fits list (the dock has none)")
	t.ok(BuildSort.lot_click("lot-20", false, false, true) == "" and BuildSort.lot_click("", false, false, true) == "",
		"a locked lot or no lot: nothing")
	var panel := FileAccess.get_file_as_string("res://scripts/town/panel_build.gd")
	var click := panel.substr(panel.find("func on_lot_clicked("), panel.find("func _make_inspector") - panel.find("func on_lot_clicked("))
	t.ok(click.contains("BuildSort.lot_click(") and click.contains("is_visible_in_tree()") and click.contains("_scroll_to_inspector()"),
		"on_lot_clicked follows lot_click with the tab's visibility, and scrolls the dock to the inspector")
	var scroll := panel.substr(panel.find("func _scroll_to_inspector("), 400)
	t.ok(scroll.contains("await get_tree().process_frame") and scroll.contains("is_visible_in_tree()")
		and scroll.find("await") < scroll.find("ensure_control_visible(n)") and scroll.contains("var n: Control = _insp[\"node\"]"),
		"the scroll waits a frame for the inspector's layout (a deferred call read its stale rect and showed mid-catalog)")
	t.ok(panel.contains("func _on_visibility()") and panel.contains("elif _card_mode == \"inspect\":"),
		"coming back to the Build tab closes an inspect card (the dock shows that lot)")
