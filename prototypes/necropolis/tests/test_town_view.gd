extends RefCounted
## TownModel, TownStandins, TownAgents and the town plan: silhouettes, lots, streets, tier walls,
## glow, pips, the demo city and the agents (counts, lockstep gait, trade arcs, carts, Relish).
## Views come from the fixtures the way the Covington shell fetches them.

const VIEW_RECT := Rect2(0, 96, 1040, 804)  # the town view at 1600x900: HUD 96 on top, dock 560 right
const NEEDS := ["gold", "bone", "bodies", "mint", "morale", "housing", "quality", "backups", "stances",
	"tithe", "front", "warden", "relics"]
const INKS := ["undead", "living", "town", "relish"]
const LIGHT_BY := ["staffing", "living", "always"]

var t: TestUtil
var cfg: Dictionary
var vcfg: Dictionary
var tempo_s := 0.0


func _model(town_cfg: Dictionary = {}) -> TownModel:
	return TownModel.new(cfg["town"] if town_cfg.is_empty() else town_cfg, cfg["buildings_view"],
		cfg["buildings"], cfg["economy"])


func _views(fixture: String) -> Dictionary:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	var r: Dictionary = s.cmd_debug_load_fixture(fixture)
	t.ok(r["ok"], "fixture %s loads" % fixture)
	return {
		"town": s.view_town(), "hud": s.view_hud(), "rates": s.view_rates(), "fort_names": {}, "catalog": s.view_catalog(),
		"stances": s.view_stances(), "backups": s.view_backups(),
		"inventory": s.view_inventory(), "big_undead": s.view_big_undead(),
		"relish": s.view_relish(), "vei": s.view_vei(),
	}


func _demo() -> Dictionary:
	return TownStandins.demo_views(_views("day1"), cfg["buildings"], cfg["town"])


func run() -> int:
	t = TestUtil.new()
	t.suite("town-view")
	cfg = TestUtil.configs()
	vcfg = cfg["town"]["view"]
	tempo_s = float(TestUtil.load_json("res://configs/pulse.json")["tempo_ms"]) / 1000.0
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))

	_silhouettes()
	_strokes()
	var day1 := _views("day1")
	var mid := _views("midgame_2flips")
	var pre := _views("pre_vei")
	var demo := TownStandins.demo_views(day1, cfg["buildings"], cfg["town"])
	for pair in [["day1", day1], ["midgame_2flips", mid], ["pre_vei", pre], ["demo", demo]]:
		_plan(pair[0], pair[1])
	_lot_pos_fallback()
	_footprint(day1)
	_walls(day1, mid, demo)
	_glow_monotone(day1)
	_standin(day1)
	_dim(day1)
	_demo_city(demo)
	_contrast()
	_hops(day1)
	_drift(day1)
	_truncate()
	_wall_ring(day1, mid)
	_crypt_ink(day1)
	_routes(day1)
	_agent_counts(day1, demo, pre)
	_agent_growth(day1)
	_agent_lockstep(day1)
	_agent_reduced(day1)
	_agent_missing(day1)
	_agent_held(day1)
	_agent_upgrading(day1)
	_upgrading(day1)
	_staff_cap(day1)
	_agent_seed(day1)
	_agent_loops(day1, demo)
	_trade_arcs(day1)
	_trade_standin(day1)
	_carts(day1)
	_relish(day1)
	_foremen(mid)
	_edge_rates(day1, demo)
	_build_needs(day1)
	_starved(day1)
	_kept(day1)
	_tier_need(day1)
	_save_for(day1)
	_variety()
	_variety_save()
	_idle_hands(day1, mid)
	_hud_idle(day1)
	_kept_reason(mid)
	_ladder_preview(day1)
	_relic_gate(mid)
	_td1_relics(mid)
	_td1_wall_line(day1, mid)
	_td1_names(mid)
	_td1_placeholders(day1, mid, pre)
	_td2(day1, mid)
	_queue_eta(day1)
	_stance_trade(mid)
	_stance_trade_grow(mid)
	_full_staffing_label()
	_build_sort(day1)
	_build_reasons(day1)
	_build_queue(day1)
	_build_inspect(day1, mid)
	_build_unique(day1)
	_build_eta(day1)
	_build_benefit()
	_build_suggest(day1)
	_autoplay(day1, mid)
	_deep_levels(day1)
	_upgrade_first(day1)
	_gate_lots(day1)
	_fix3a_serves(day1, mid)
	_fix3a_work()
	_fix3a_hud(day1)
	_fix3a_upgrades(day1)
	_fix3a_lots(day1)
	_fix3a_reserve(day1)
	_build_ghosts(day1)
	_build_chips()
	_build_caps(day1)
	_hud(day1, mid, pre, demo)
	_build_lot_refusal()
	_lot_hit(day1)
	_view_keys()
	_budget(day1)
	_looks(day1, mid, demo)
	_badges(day1, mid, demo)
	_pip_groups(day1, demo)
	_rate_units([day1, mid, pre, demo])
	_status_lines(day1, mid, demo)
	_agent_status(demo)
	_agent_pick(day1)
	_floats(day1, demo)
	_ring_order(day1)
	_ratio([day1, mid, pre, demo], ["day1", "midgame_2flips", "pre_vei", "demo"])
	_legend(pre)
	_arc_shape()
	_dismiss_box()
	_legible_contrast()
	_behaviour_pure()
	_stance_flash(day1, demo)
	_behaviour_config()
	_behaviour_commands()
	_backups(day1, pre)
	_sound_math()
	_sound_cfg()
	_morph_math()
	_walk_math()
	_walkout(mid)
	_foreman_float(mid)
	_fix3b_vats()
	_fix3b_stances(mid)
	_fix3b_cache()
	_fix3b_small(mid)
	_fix3b_lot_names()
	_fix3d_sigs(day1, mid)
	_fix3e_queue()
	_fix3e_sigs(mid)
	_fix3e_handlers()
	_fix3e_live()
	return t.failures


# ------------------------------------------------------------- silhouettes ----
func _silhouettes() -> void:
	var bv: Dictionary = cfg["buildings_view"]
	for bid in cfg["buildings"]:
		t.ok(bv.has(bid), "buildings_view has %s" % bid)
		if not bv.has(bid):
			continue
		var e: Dictionary = bv[bid]
		t.ok(String(e.get("label", "")) != "" and String(e.get("flavour", "")) != "" and String(e.get("benefit", "")) != "",
			"%s has a label, a flavour and a benefit" % bid)
		t.ok(String(e.get("ink", "")) in INKS and Palette.has(String(e.get("ink", ""))), "%s inks with a Palette key" % bid)
		t.ok(String(e.get("light_by", "")) in LIGHT_BY, "%s light_by is staffing, living or always" % bid)
		var jobs: Dictionary = cfg["buildings"][bid].get("jobs", {})
		if not jobs.is_empty():
			t.ok(e["light_by"] == "staffing" and e["ink"] == "undead", "%s has jobs: undead ink, lit by staffing" % bid)
		var serves: Array = e.get("serves", [])
		var known := not serves.is_empty()
		for n in serves:
			known = known and n in NEEDS
		t.ok(known, "%s serves known needs: %s" % [bid, str(serves)])
		var strokes: Array = e.get("strokes", [])
		var good := not strokes.is_empty()
		for pl in strokes:
			good = good and pl is Array and pl.size() >= 2
			for p in pl:
				good = good and p is Array and p.size() == 2 and float(p[0]) >= 0.0 and float(p[0]) <= 1.0 \
					and float(p[1]) >= 0.0 and float(p[1]) <= 1.0
		t.ok(good, "%s strokes: non-empty polylines, every point in the unit box" % bid)
	for bid in bv:
		t.ok(cfg["buildings"].has(bid), "buildings_view entry %s is a real building id" % bid)
	t.ok(bv["crypt"]["ink"] == "relish", "the crypt lights with Relish's violet")
	for bid in ["house", "inn", "well", "bakery", "plaza"]:
		t.ok(bv[bid]["ink"] == "living" and bv[bid]["light_by"] == "living", "%s is a living amenity" % bid)
	for bid in ["walls", "watchtower", "guildhall", "statue", "reliquary"]:
		t.ok(bv[bid]["ink"] == "town" and bv[bid]["light_by"] == "always", "%s is town structure" % bid)


func _len(pls: Array) -> float:
	var total := 0.0
	for pl in pls:
		for i in range(1, pl.size()):
			total += pl[i - 1].distance_to(pl[i])
	return total


func _strokes() -> void:
	var m := _model()
	for bid in cfg["buildings"]:
		var size := int(cfg["buildings"][bid]["lot_size"])
		var r := Rect2(100, 200, 80.0 * size, 88.0)
		var full := m.strokes(bid, r, 1.0)
		var half := m.strokes(bid, r, 0.5)
		var none := m.strokes(bid, r, 0.0)
		t.ok(full.size() == cfg["buildings_view"][bid]["strokes"].size(), "%s: reveal 1 draws every stroke" % bid)
		t.ok(none.is_empty(), "%s: reveal 0 draws nothing" % bid)
		t.near(_len(half), _len(full) * 0.5, 1.0, "%s: reveal 0.5 draws half the length" % bid)
		t.ok(half.size() < full.size(), "%s: reveal 0.5 draws fewer strokes" % bid)
		var inside := true
		for pl in full:
			for p in pl:
				inside = inside and r.grow(0.01).has_point(p)
		t.ok(inside, "%s: scaled strokes stay in the rect" % bid)
		t.ok(full[0][0].is_equal_approx(half[0][0]), "%s: the reveal starts where the first stroke starts" % bid)
	var q := m.strokes("crypt", Rect2(0, 0, 160, 88), 0.25)
	t.near(_len(q), _len(m.strokes("crypt", Rect2(0, 0, 160, 88), 1.0)) * 0.25, 1.0, "a quarter reveal draws a quarter")
	t.ok(m.strokes("no_such_building", Rect2(0, 0, 80, 88), 1.0).is_empty(), "an unknown building draws nothing")


# -------------------------------------------------------------------- plan ----
func _plan(name: String, views: Dictionary) -> void:
	var m := _model()
	m.update(views, VIEW_RECT)
	t.ok(m.lots.size() == cfg["town"]["lots"].size(), "%s: one entry per lot" % name)
	var gap := float(vcfg["lot_gap_px"])
	var all_in := true
	var apart := true
	var doors_ok := true
	for i in m.lots.size():
		var a: Dictionary = m.lots[i]
		all_in = all_in and VIEW_RECT.encloses(a["rect"])
		for j in range(i + 1, m.lots.size()):
			if a["rect"].grow(gap * 0.5 - 0.01).intersects(m.lots[j]["rect"].grow(gap * 0.5 - 0.01)):
				apart = false
				t.ok(false, "%s: %s and %s are closer than lot_gap_px" % [name, a["id"], m.lots[j]["id"]])
		doors_ok = doors_ok and m.nodes.has(a["door"]) and a["door_pos"] == m.nodes[a["door"]]
		var nearest := ""
		var best := INF
		for n in m.nodes:
			var d: float = m.nodes[n].distance_to(a["rect"].get_center())
			if d < best:
				best = d
				nearest = n
		doors_ok = doors_ok and a["door"] == nearest
	t.ok(all_in, "%s: every lot rect is inside the view rect" % name)
	t.ok(apart, "%s: no two lots overlap (at lot_gap_px clearance)" % name)
	t.ok(doors_ok, "%s: every lot's door is its nearest street node" % name)
	t.ok(m.nodes.has("gate") and m.nodes.has("plaza"), "%s: the street graph names gate and plaza" % name)

	# connected, and every door reaches the plaza and the gate along street edges
	var edge_set := {}
	var streets_px: bool = m.streets.size() == cfg["town"]["view"]["street_edges"].size()
	for s in m.streets:
		edge_set[_ek(s["from"], s["to"])] = true
		streets_px = streets_px and s["from"] == m.nodes[s["a"]] and s["to"] == m.nodes[s["b"]]
	t.ok(streets_px, "%s: one street per edge, ends in px at its nodes" % name)
	var reach := true
	for n in m.nodes:
		reach = reach and not m.path(n, "plaza").is_empty()
	t.ok(reach, "%s: the street graph is connected" % name)
	var walk := true
	for a in m.lots:
		for goal in ["plaza", "gate"]:
			var p := m.path(a["door"], goal)
			walk = walk and p.size() >= 1 and p[0] == a["door_pos"] and p[p.size() - 1] == m.nodes[goal]
			for k in range(1, p.size()):
				walk = walk and edge_set.has(_ek(p[k - 1], p[k]))
	t.ok(walk, "%s: every door walks along streets to the plaza and the gate" % name)
	var built := 0
	for a in m.lots:
		if not a["building"].is_empty():
			built += 1
			var b: Dictionary = a["building"]
			t.ok(b["pips"] is int and b["pips"] >= 0 and b["pips"] <= int(vcfg["pip_max"]), "%s: %s pips is a capped int" % [name, a["id"]])
			t.ok(b["glow"] is float and b["glow"] >= 0.0 and b["glow"] <= 1.0, "%s: %s glow in 0..1" % [name, a["id"]])
			t.ok(a["rect"].encloses(b["rect"]), "%s: %s silhouette rect sits in its lot" % [name, a["id"]])
	t.ok(built == views["town"]["buildings"].size(), "%s: one display entry per view building" % name)


func _ek(a: Vector2, b: Vector2) -> String:
	var lo := a if a < b else b
	var hi := b if a < b else a
	return "%.2f,%.2f|%.2f,%.2f" % [lo.x, lo.y, hi.x, hi.y]


func _lot_pos_fallback() -> void:
	var tc: Dictionary = cfg["town"].duplicate(true)
	tc["view"]["lot_pos"].erase("lot-05")
	var m := _model(tc)
	m.update({}, VIEW_RECT)
	var pos: Array = tc["lots"][4]["pos"]
	var want := VIEW_RECT.position + Vector2(float(pos[0]) * VIEW_RECT.size.x, float(pos[1]) * VIEW_RECT.size.y)
	t.ok(m.lot("lot-05")["rect"].get_center().is_equal_approx(want), "a lot missing from view.lot_pos falls back to lots[i].pos")
	t.ok(m.lots.size() == 24 and not m.lot("lot-01")["unlocked"] and m.lot("lot-01")["building"].is_empty(),
		"empty views: 24 locked, empty lots")


func _footprint(day1: Dictionary) -> void:
	var m := _model()
	m.update(day1, VIEW_RECT)
	var lot := m.lot("lot-02")
	var b: Dictionary = lot["building"]
	t.ok(b["building_id"] == "raising_pit", "day1: the raising pit sits on lot-02")
	t.near(b["rect"].size.x, float(vcfg["lot_unit_px"]), 0.01, "a size-1 building draws one unit wide on a size-2 lot")
	t.near(lot["rect"].size.x, 2.0 * float(vcfg["lot_unit_px"]), 0.01, "lot-02 is two units wide")
	t.near(b["rect"].get_center().x, lot["rect"].get_center().x, 0.01, "the footprint is centred in its lot")
	t.ok(m.lot("lot-01")["door"] == "plaza", "the crypt's door is the crypt plaza")
	# scaling: a half-size view halves the lots and keeps them proportionally placed
	var small := Rect2(0, 36, 520, 414)
	m.update(day1, small)
	t.near(m.lot("lot-02")["rect"].size.x, float(vcfg["lot_unit_px"]), 0.01, "lots scale with the view rect")
	t.ok(small.encloses(m.lot("lot-24")["rect"]), "scaled lots stay inside the scaled view")


# ------------------------------------------------------------------- walls ----
func _seg_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	return Geometry2D.segment_intersects_segment(a, b, c, d) != null


func _walls(day1: Dictionary, mid: Dictionary, demo: Dictionary) -> void:
	var m := _model()
	m.update(day1, VIEW_RECT)
	t.ok(m.tier == "hamlet", "day1 is a hamlet")
	var none := true
	for tier in m.tiers:
		none = none and m.walls(tier).is_empty()
	t.ok(none, "a hamlet has no walls")
	m.update(mid, VIEW_RECT)
	t.ok(m.tier == "village" and not m.walls("village").is_empty() and m.walls("town").is_empty() and m.walls("city").is_empty(),
		"a village has its palisade only")
	var village: Array = []
	for l in mid["town"]["lots"]:
		if l["unlocked"]:
			village.append(l["id"])
	var want: Array = []
	for i in range(1, 17):
		want.append("lot-%02d" % i)
	want.append("lot-23")
	t.ok(village == want, "a village's unlocked lots are lot-01..16 plus lot-23, not the first 17 (%s)" % str(village))
	t.ok(not m.lot("lot-17")["unlocked"] and m.lot("lot-23")["unlocked"], "the model follows lots[].unlocked: lot-17 locked, lot-23 unlocked")
	var wv := m.walls("village")
	var inside := true
	for id in village:
		var r: Rect2 = m.lot(id)["rect"]
		for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			inside = inside and Geometry2D.is_point_in_polygon(c, wv)
	t.ok(inside, "the village wall encloses every lot the view reports unlocked")
	m.update(demo, VIEW_RECT)
	t.ok(m.tier == "city", "the demo is a city")
	var tiers: Dictionary = cfg["economy"]["town"]["tiers"]
	for tier in cfg["town"]["view"]["tier_walls"]:
		var w := m.walls(tier)
		t.ok(w.size() >= 4, "%s wall is a polyline" % tier)
		# the lots unlocked at a tier are its lot_ids, not "the first N": Village has lot-01..16 + lot-23
		var ids: Array = tiers[tier]["lot_ids"]
		var n := ids.size()
		t.ok(n == int(tiers[tier]["lots"]), "%s: lots is the count of lot_ids" % tier)
		var enclosed := true
		for id in ids:
			var r: Rect2 = m.lot(id)["rect"]
			for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
				enclosed = enclosed and Geometry2D.is_point_in_polygon(c, w)
		t.ok(enclosed, "%s wall encloses the %d lots unlocked at %s" % [tier, n, tier])
		t.ok(Geometry2D.is_point_in_polygon(m.nodes["plaza"], w) and not Geometry2D.is_point_in_polygon(m.nodes["gate"], w),
			"%s wall: the plaza inside, the gate outside" % tier)
		var inside_view := true
		for p in w:
			inside_view = inside_view and VIEW_RECT.grow(0.01).has_point(p)
		t.ok(inside_view, "%s wall stays in the view rect" % tier)
		# streets never cross the wall; the gate road passes through the gap (last point -> first)
		var crossed := false
		for s in m.streets:
			for k in range(1, w.size()):
				crossed = crossed or _seg_cross(s["from"], s["to"], w[k - 1], w[k])
		t.ok(not crossed, "%s wall: no street crosses it" % tier)
		var road := m.path("gate", "plaza")
		var through_gap := false
		for k in range(1, road.size()):
			through_gap = through_gap or _seg_cross(road[k - 1], road[k], w[w.size() - 1], w[0])
		t.ok(through_gap, "%s wall: the gate road passes through its gap" % tier)


# -------------------------------------------------------------- glow, pips ----
## day1 views with lot `lot_id`'s building patched by `patch`.
func _patched(views: Dictionary, lot_id: String, patch: Dictionary) -> Dictionary:
	var v: Dictionary = views.duplicate(true)
	for b in v["town"]["buildings"]:
		if b["lot_id"] == lot_id:
			b.merge(patch, true)
	return v


func _glow_monotone(day1: Dictionary) -> void:
	var m := _model()
	var last := -1.0
	var mono := true
	var rates := [0.0, 0.05, 0.2, 0.6, 1.5, 4.0, 8.0, 30.0]
	var glows: Array = []
	for r in rates:
		m.update(_patched(day1, "lot-04", {"output": {"gold": r}}), VIEW_RECT)
		var g: float = m.lot("lot-04")["building"]["glow"]
		glows.append(g)
		mono = mono and g >= last
		last = g
	t.ok(mono, "glow is monotone in output rate: %s" % str(glows))
	t.ok(glows[0] == 0.0 and glows[3] > glows[1] and glows[6] > glows[4], "glow rises with rate, zero rate is dark")
	t.near(glows[6], 1.0, 0.0001, "the glow_ref rate glows fully")
	t.near(glows[7], 1.0, 0.0001, "glow caps at 1")


## A copy of the views with every building's output blanked: the E1 stub the stand-ins are for.
func _stub(views: Dictionary) -> Dictionary:
	var v: Dictionary = views.duplicate(true)
	for b in v["town"]["buildings"]:
		b["output"] = {}
	return v


func _standin(live: Dictionary) -> void:
	var m := _model()
	m.update(live, VIEW_RECT)
	t.ok(not m.staffing_standin, "live outputs (E2a): the staffing stand-in is off")
	var day1 := _stub(live)
	m.update(day1, VIEW_RECT)
	t.ok(m.staffing_standin, "every output blanked (the E1 stub): the staffing stand-in is on")
	var charnel: Dictionary = m.lot("lot-03")["building"]
	t.ok(charnel["building_id"] == "charnel_house" and charnel["slots"] > 0 and charnel["staffed"] > 0.0,
		"day1: the charnel house is staffed")
	t.near(charnel["glow"], charnel["staffed"] / float(charnel["slots"]), 0.0001, "stand-in glow is staffed / slots")
	t.ok(charnel["pips"] == roundi(charnel["staffed"]), "stand-in pips are round(staffed)")
	t.ok(charnel["pip_key"] == "dead", "stand-in pip key from the job's matter (haul -> bodies -> dead)")
	t.ok(m.lot("lot-04")["building"]["pip_key"] == "living", "stand-in: a market's pips are gold (living)")

	# one real output switches the stand-in off for every building
	m.update(_patched(day1, "lot-04", {"output": {"gold": 0.3}}), VIEW_RECT)
	t.ok(not m.staffing_standin, "one non-empty output switches the stand-in off")
	charnel = m.lot("lot-03")["building"]
	t.ok(charnel["staffed"] > 0.0 and charnel["glow"] == 0.0, "a staffed building with no output is dark once outputs are real")
	t.ok(charnel["pips"] == 0, "and has no pips")
	var market: Dictionary = m.lot("lot-04")["building"]
	t.ok(market["pips"] == 3 and market["pip_key"] == "living", "0.3 gold/s at 0.1 per pip: 3 living pips")
	m.update(_patched(day1, "lot-02", {"output": {"mint": 6.0, "burn": 0.6}}), VIEW_RECT)
	var pit: Dictionary = m.lot("lot-02")["building"]
	t.ok(pit["pips"] == 6 and pit["pip_key"] == "undead", "the pit's main output is mint: 6 undead pips")
	m.update(_patched(day1, "lot-02", {"output": {"mint": 500.0}}), VIEW_RECT)
	t.ok(m.lot("lot-02")["building"]["pips"] == int(vcfg["pip_max"]), "pips cap at pip_max")


## A building mid-upgrade (constructing at level >= 1) keeps its working look: it is not a new
## build (level 0), which still draws stroke by stroke.
func _upgrading(day1: Dictionary) -> void:
	var m := _model()
	var base := {"progress": 0.4, "slots": 2, "staffed": 2.0, "output": {"gold": 0.3}}
	m.update(_patched(day1, "lot-04", {}.merged(base).merged({"state": "active", "level": 1})), VIEW_RECT)
	var active: Dictionary = m.lot("lot-04")["building"]
	m.update(_patched(day1, "lot-04", {}.merged(base).merged({"state": "constructing", "level": 1})), VIEW_RECT)
	var b: Dictionary = m.lot("lot-04")["building"]
	t.ok(b["upgrading"] and b["look"] == "staffed" and b["reveal"] == 1.0, "upgrade: keeps its staffed look at full reveal")
	t.near(b["glow"], active["glow"], 0.0001, "upgrade: glows as it did before (no dim)")
	t.ok(b["pulse"] and b["badge"] == active["badge"] and b["pips"] == active["pips"], "upgrade: still pulses with its badge and pips")
	t.ok(b["status"] == "upgrading 40%: +0.30 gold/s", "upgrade: status reads '%s'" % b["status"])
	var raw := {"building_id": "market", "state": "constructing", "level": 1, "progress": 0.4, "slots": 2, "staffed": 2.0,
		"staff_cap": -1, "output": {"gold": 0.3}}
	t.ok(TownModel.status_of(raw, "staffed", day1["town"], cfg["buildings"], cfg["buildings_view"], vcfg)
		== [["upgrading 40%: ", false], ["+0.30 gold/s", true]], "upgrade: the rate stays the oblique part")
	m.update(_patched(day1, "lot-04", {}.merged(base).merged({"state": "constructing", "level": 1, "staffed": 0.0, "output": {}}, true)), VIEW_RECT)
	b = m.lot("lot-04")["building"]
	t.ok(b["look"] == "unstaffed" and b["upgrading"] and String(b["status"]).begins_with("upgrading 40%: "),
		"upgrade: an unstaffed one reads unstaffed, led by 'upgrading 40%%' (%s)" % b["status"])
	m.update(_patched(day1, "lot-04", {}.merged(base).merged({"state": "constructing", "level": 0})), VIEW_RECT)
	b = m.lot("lot-04")["building"]
	t.ok(not b["upgrading"] and b["look"] == "constructing" and b["reveal"] == 0.4 and b["status"] == "building: 40%",
		"a new build (level 0) is still constructing, revealing its progress")
	t.near(b["glow"], float(vcfg["glow_dim"]), 0.0001, "a new build still glows at glow_dim")


## A staff cap is not a shortage: the badge and status count min(slots, staff_cap) hands wanted.
func _staff_cap(day1: Dictionary) -> void:
	var m := _model()
	m.update(_patched(day1, "lot-04", {"slots": 3, "staffed": 1.0, "staff_cap": 1, "output": {"gold": 0.3}}), VIEW_RECT)
	var b: Dictionary = m.lot("lot-04")["building"]
	t.ok(b["badge"] == "1 working" and b["short"] == 0, "staff cap: 1 of a cap of 1 reads '1 working', not short (%s)" % b["badge"])
	t.ok(b["status"] == "working: +0.30 gold/s", "staff cap: status is working, not short (%s)" % b["status"])
	m.update(_patched(day1, "lot-04", {"slots": 3, "staffed": 1.0, "staff_cap": 2, "output": {"gold": 0.3}}), VIEW_RECT)
	b = m.lot("lot-04")["building"]
	t.ok(b["badge"] == "1 working · 1 short" and b["short"] == 1 and b["status"] == "short 1 hand", "staff cap: below the cap it is short by cap - working")
	m.update(_patched(day1, "lot-04", {"slots": 3, "staffed": 1.0, "staff_cap": -1, "output": {"gold": 0.3}}), VIEW_RECT)
	b = m.lot("lot-04")["building"]
	t.ok(b["badge"] == "1 working · 2 short" and b["status"] == "short 2 hands", "staff cap -1: all the slots count")


func _dim(day1: Dictionary) -> void:
	var m := _model()
	var dim := float(vcfg["glow_dim"])
	m.update(_patched(day1, "lot-04", {"state": "constructing", "progress": 0.4, "level": 0}), VIEW_RECT)
	var b: Dictionary = m.lot("lot-04")["building"]
	t.near(b["glow"], dim, 0.0001, "constructing glows at glow_dim")
	t.near(b["reveal"], 0.4, 0.0001, "constructing reveals its progress")
	m.update(_patched(day1, "lot-04", {"state": "unpaid"}), VIEW_RECT)
	b = m.lot("lot-04")["building"]
	t.ok(b["unpaid"] and b["state"] == "unpaid", "unpaid is flagged")
	t.near(b["glow"], dim, 0.0001, "unpaid glows at glow_dim")
	t.near(b["reveal"], 1.0, 0.0001, "an unpaid building is fully drawn")
	m.update(_patched(day1, "lot-04", {"state": "idle"}), VIEW_RECT)
	t.ok(m.lot("lot-04")["building"]["glow"] == 0.0, "idle is dark")
	m.update(day1, VIEW_RECT)
	t.near(m.lot("lot-01")["building"]["glow"], float(vcfg["glow_always"]), 0.0001, "Relish home: the crypt is lit at glow_always")
	var away: Dictionary = day1.duplicate(true)
	away["town"]["relish_home"] = false
	m.update(away, VIEW_RECT)
	t.near(m.lot("lot-01")["building"]["glow"], float(vcfg["glow_always"]), 0.0001,
		"Relish away: the crypt stays lit at glow_always, never drawn like an unbuilt or idle lot")


# -------------------------------------------------------------------- demo ----
func _demo_city(demo: Dictionary) -> void:
	var errs: Array = []
	ApiSchema.check(demo["town"], ApiSchema.VIEWS["view_town"], "demo.town", errs)
	t.ok(errs.is_empty(), "the demo town is a valid view_town: %s" % str(errs))
	var base := _views("day1")
	var same_keys := true
	for k in base:
		same_keys = same_keys and demo.has(k) and demo[k].keys() == base[k].keys()
	t.ok(same_keys, "the demo keeps every view and every key of the base")
	var town: Dictionary = demo["town"]
	t.ok(town["tier"] == "city" and town["relish_home"], "demo: a city with Relish home")
	var size_of := {}
	for l in cfg["town"]["lots"]:
		size_of[l["id"]] = int(l["size"])
	var unlocked := 0
	for l in town["lots"]:
		unlocked += 1 if l["unlocked"] and l["building_id"] != "" else 0
	t.ok(unlocked == 24, "demo: all 24 lots unlocked and built")
	var states := {}
	var ids := {}
	var fits := true
	var staffed := 0.0
	for b in town["buildings"]:
		states[b["state"]] = int(states.get(b["state"], 0)) + 1
		ids[b["building_id"]] = true
		fits = fits and int(cfg["buildings"][b["building_id"]]["lot_size"]) <= size_of[b["lot_id"]]
		staffed += b["staffed"]
	t.ok(town["buildings"].size() == 24 and fits, "demo: 24 buildings, each on a lot it fits")
	t.ok(int(states.get("constructing", 0)) >= 3 and int(states.get("unpaid", 0)) == 1 and int(states.get("idle", 0)) == 1,
		"demo: three constructing, one unpaid, one idle: %s" % str(states))
	var progress: Array = []
	for b in town["buildings"]:
		if b["state"] == "constructing":
			progress.append(b["progress"])
	progress.sort()
	t.ok(progress == [0.2, 0.5, 0.85], "demo: construction at 0.2, 0.5 and 0.85")
	# 14 size-1, 8 size-2 and 2 size-3 lots hold at most 18 distinct ids (13 ids need size >= 2)
	t.ok(ids.size() >= 18 and ids.has("crypt") and ids.has("walls") and ids.has("reliquary"),
		"demo: %d distinct buildings, as many as the lot sizes allow" % ids.size())
	t.near(town["workers"]["idle"], 8.0, 0.001, "demo: 8 idle")
	t.near(town["workers"]["total"], staffed + 8.0, 0.001, "demo: workers = staffed + 8 idle")
	var leveled := true
	for b in town["buildings"]:
		var jobs: Dictionary = cfg["buildings"][b["building_id"]]["jobs"]
		var n := 0
		for j in jobs:
			n += int(jobs[j])
		if b["state"] == "active" and n > 0:
			leveled = leveled and b["slots"] == n * b["level"] and b["staffed"] == float(b["slots"])
	t.ok(leveled and staffed > 30.0, "demo: active job buildings staffed to their job slots x level (%d staffed)" % int(staffed))
	var jobs_full := true
	for j in town["jobs"]:
		jobs_full = jobs_full and is_equal_approx(j["staffed"], float(j["slots"]))
	t.ok(jobs_full and not town["jobs"].is_empty(), "demo: every job staffed to its slots")
	t.ok(town["living"] == 64.0 and town["living_cap"] == 80.0 and town["trade_rate"] == 2.0, "demo: living 64/80, trade 2.0/s")
	t.ok(town["haul"]["convoys"].size() == 3, "demo: three haul convoys")
	var outputs := true
	for b in town["buildings"]:
		if b["state"] == "active" and not cfg["buildings"][b["building_id"]]["jobs"].is_empty():
			outputs = outputs and not b["output"].is_empty()
	t.ok(outputs, "demo: active job buildings report output")
	var m := _model()
	m.update(demo, VIEW_RECT)
	t.ok(not m.staffing_standin, "demo: real outputs, no stand-in")
	var lit := 0
	for l in m.lots:
		lit += 1 if l["building"].get("pips", 0) > 0 else 0
	t.ok(lit >= 6, "demo: job buildings show pips (%d)" % lit)


# ---------------------------------------------------------------- contrast ----
func _contrast() -> void:
	t.near(TownModel.contrast(Color.WHITE, Color.BLACK), 21.0, 0.01, "contrast: white on black is 21:1")
	t.near(TownModel.contrast(Color.BLACK, Color.WHITE), 21.0, 0.01, "contrast is symmetric")
	t.near(TownModel.contrast(Color(1, 1, 1, 0), Color.BLACK), 1.0, 0.0001, "a transparent line has no contrast")
	t.ok(TownModel.contrast(Color(1, 1, 1, 0.5), Color.BLACK) < TownModel.contrast(Color.WHITE, Color.BLACK),
		"alpha lowers contrast")
	var ground := Palette.c("ground")
	for k in ["blueprint_line", "idle_line"]:
		var spec: Dictionary = vcfg[k]
		var c := Palette.c(String(spec["key"]), float(spec["alpha"]))
		var ratio := TownModel.contrast(c, ground)
		t.ok(ratio >= 3.0, "%s (%s at %.2f) reaches 3:1 on ground: %.2f" % [k, spec["key"], spec["alpha"], ratio])


# ------------------------------------------------------------- hops, flows ----
func _hops(day1: Dictionary) -> void:
	var m := _model()
	m.update(day1, VIEW_RECT)
	t.ok(m.dist.size() == m.nodes.size() and is_zero_approx(m.dist["plaza"]), "every node has a street distance; the plaza is 0")
	var deepest := 0.0
	for n in m.dist:
		deepest = maxf(deepest, m.dist[n])
	t.near(m.depth, deepest, 0.001, "depth is the farthest node's distance")
	var lot_hops := true
	for l in m.lots:
		lot_hops = lot_hops and is_equal_approx(l["hops"], m.dist[l["door"]])
	t.ok(lot_hops, "a lot's hops is its door's street distance")
	t.ok(is_zero_approx(m.lot("lot-01")["hops"]), "the crypt sits at hops 0 (the tempo source)")
	var oriented := true
	for s in m.streets:
		var dn: float = m.dist[s["a"]] if s["near"] == s["from"] else m.dist[s["b"]]
		var df: float = m.dist[s["b"]] if s["near"] == s["from"] else m.dist[s["a"]]
		oriented = oriented and dn <= df and ((s["near"] == s["from"] and s["far"] == s["to"]) or (s["near"] == s["to"] and s["far"] == s["from"]))
	t.ok(oriented, "every street is oriented near -> far from the plaza, keeping from/to as configured")


func _drift(day1: Dictionary) -> void:
	var m := _model()
	m.update(day1, VIEW_RECT)
	var zero_in_lots := true
	for l in m.lots:
		var r: Rect2 = l["rect"]
		for p in [r.get_center(), r.position + Vector2(1, 1), r.end - Vector2(1, 1)]:
			zero_in_lots = zero_in_lots and m.drift_at(p) == Vector2.ZERO
	t.ok(zero_in_lots, "the floor's drift is zero inside every lot")
	var reach := float(vcfg["floor_reach_px"]) * m.scale
	var along := true
	var falls := true
	var checked := 0
	for s in m.streets:
		var mid: Vector2 = (s["near"] + s["far"]) * 0.5
		var toward: Vector2 = (s["near"] - s["far"]).normalized()
		var side := Vector2(-toward.y, toward.x)
		var on := m.drift_at(mid + side * 1.0)
		var off := m.drift_at(mid + side * reach * 0.5)
		if on == Vector2.ZERO:
			continue  # the midpoint sits in a lot's shadow or nearer another street
		checked += 1
		along = along and on.normalized().dot(toward) > 0.99 and on.length() > 0.9
		falls = falls and off.length() < on.length()
	t.ok(along and checked * 2 >= m.streets.size(),
		"on a street the drift runs along it toward the plaza at full strength (%d of %d streets)" % [checked, m.streets.size()])
	t.ok(falls, "the drift weakens away from the street")
	var far_point := Vector2(VIEW_RECT.end.x - 2.0, VIEW_RECT.end.y - 2.0)
	t.ok(m.drift_at(far_point) == Vector2.ZERO, "beyond floor_reach_px of every street there is no drift")


func _truncate() -> void:
	var pl: Array[PackedVector2Array] = [PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]),
		PackedVector2Array([Vector2(100, 0), Vector2(100, 100)])]
	t.ok(TownModel.truncate(pl, 0.0).is_empty(), "truncate 0 draws nothing")
	t.ok(TownModel.truncate(pl, 1.0) == pl, "truncate 1 draws everything")
	var q := TownModel.truncate(pl, 0.75)
	t.near(_len(q), 150.0, 0.001, "truncate 0.75 draws three quarters of the length")
	t.ok(q.size() == 2 and q[1][q[1].size() - 1].is_equal_approx(Vector2(100, 50)), "the head is where the drawing stops")
	var h := TownModel.truncate(pl, 0.25)
	t.ok(h.size() == 1 and h[0][1].is_equal_approx(Vector2(50, 0)), "a quarter stops inside the first stroke")


func _wall_ring(day1: Dictionary, mid: Dictionary) -> void:
	var m := _model()
	m.update(day1, VIEW_RECT)
	t.ok(m.walls("village").is_empty() and m.wall_ring("village").size() >= 4,
		"a hamlet has no village wall, but the set piece can still draw its ring")
	var ring := m.wall_ring("village")
	m.update(mid, VIEW_RECT)
	t.ok(m.walls("village") == ring, "once reached, walls() is the same ring")
	t.ok(m.wall_ring("hamlet").is_empty(), "a tier without walls has no ring")


func _crypt_ink(day1: Dictionary) -> void:
	var m := _model()
	m.update(day1, VIEW_RECT)
	t.ok(day1["town"]["relish_home"] and m.lot("lot-01")["building"]["ink"] == "relish", "Relish home: the crypt inks violet")
	var away: Dictionary = day1.duplicate(true)
	away["town"]["relish_home"] = false
	m.update(away, VIEW_RECT)
	t.ok(m.lot("lot-01")["building"]["ink"] == String(vcfg["relish_away_ink"]), "Relish away: the crypt takes relish_away_ink")
	t.ok(m.lot("lot-02")["building"]["ink"] == "undead", "other inks are untouched")


func _routes(day1: Dictionary) -> void:
	var m := _model()
	m.update(day1, VIEW_RECT)
	var r := m.route("gate", "plaza")
	var p := m.path("gate", "plaza")
	var same := r.size() == p.size() and r.size() >= 2
	for i in mini(r.size(), p.size()):
		same = same and m.nodes[r[i]] == p[i]
	t.ok(same and r[0] == "gate" and r[r.size() - 1] == "plaza", "route() names the nodes path() walks")
	var edges_ok := true
	for i in range(1, r.size()):
		var e := m.edge_index(r[i - 1], r[i])
		edges_ok = edges_ok and e >= 0 and e == m.edge_index(r[i], r[i - 1])
		if e >= 0:
			var s: Dictionary = m.streets[e]
			edges_ok = edges_ok and ((s["a"] == r[i - 1] and s["b"] == r[i]) or (s["a"] == r[i] and s["b"] == r[i - 1]))
	t.ok(edges_ok, "edge_index() finds each street a route walks, either way round")
	t.ok(m.edge_index("gate", "plaza") == -1 and m.route("gate", "nowhere").is_empty(), "no street, no route: -1 and []")
	t.ok(m.route("plaza", "plaza") == PackedStringArray(["plaza"]), "a route to itself is the node alone")
	var lens := true
	for s in m.streets:
		lens = lens and is_equal_approx(s["length"], s["from"].distance_to(s["to"]))
	t.ok(lens, "every street carries its length in px")


# ------------------------------------------------------------------ agents ----
## [model, agents] synced to `views` (a fixed seed, so every run walks the same way). `view_cfg`
## replaces town.json's view block (e.g. _one_to_one()).
func _agents(views: Dictionary, econ: Dictionary = {}, view_cfg: Dictionary = {}) -> Array:
	var m := _model()
	m.update(views, VIEW_RECT)
	var a := TownAgents.new(vcfg if view_cfg.is_empty() else view_cfg, cfg["buildings"], cfg["economy"] if econ.is_empty() else econ, tempo_s, 7)
	a.sync(m, views)
	return [m, a]


## The view block with the living ratio cap lifted, so day1's few agents sample 1:1: the tests of
## how counts follow the stream (growth, reduced motion, the entry seed) count people, not strokes.
func _one_to_one() -> Dictionary:
	var v: Dictionary = vcfg.duplicate(true)
	v["living_ratio_max"] = 1000.0
	return v


func _resync(m: TownModel, a: TownAgents, views: Dictionary) -> void:
	m.update(views, VIEW_RECT)
	a.sync(m, views)


## Steps `a` for `secs` at `fps`, Pulse's beat from a clock starting at `t0` s. Returns the clock.
func _run(a: TownAgents, secs: float, t0 := 0.0, reduced := false, fps := 30.0) -> float:
	var dt := 1.0 / fps
	var clock := t0
	for i in int(round(secs * fps)):
		clock += dt
		a.step(dt, fposmod(clock / tempo_s, 1.0), reduced)
	return clock


## Undead the stream asks for at 1 stroke = 1: every job's staffed plus the idle.
func _undead_want(town: Dictionary) -> int:
	var n := roundi(float(town["workers"]["idle"]))
	for j in town["jobs"]:
		n += roundi(float(j["staffed"]))
	return n


func _counts_match(a: TownAgents, town: Dictionary, k := 1) -> bool:
	var ok := true
	for j in town["jobs"]:
		ok = ok and a.count(String(j["id"])) == roundi(float(j["staffed"]) / float(k))
	return ok and a.count("idle") == roundi(float(town["workers"]["idle"]) / float(k))


func _agent_counts(day1: Dictionary, demo: Dictionary, pre: Dictionary) -> void:
	var pair := _agents(day1)
	var a: TownAgents = pair[1]
	var town: Dictionary = day1["town"]
	t.ok(_counts_match(a, town), "day1 on entry: undead per job = its staffed, idle = workers.idle")
	var lk := a.living_scale
	t.ok(a.living_count() == roundi(float(town["living"]) / float(lk)),
		"day1 on entry: the living sampled at 1 stroke = %d (%d strokes)" % [lk, a.living_count()])
	t.ok(a.undead_scale == 1, "day1's workers fit: 1 green stroke = 1 worker")
	var spots := {}
	for u in a.undead + a.living:
		spots["%d,%d" % [roundi(u.pos.x), roundi(u.pos.y)]] = true
	t.ok(spots.size() >= a.undead.size() + a.living.size() - 2, "on entry the agents stand spread along their loops, not stacked")
	_run(a, 30.0)
	t.ok(_counts_match(a, town) and a.living_count() == roundi(float(town["living"]) / float(lk)),
		"after 30 s of walking the counts still equal the stream")

	var big: Dictionary = day1.duplicate(true)
	big["town"]["workers"]["idle"] = 300.0
	var dtown: Dictionary = big["town"]
	var total := float(dtown["workers"]["idle"])
	for j in dtown["jobs"]:
		total += float(j["staffed"])
	var ucap := int(vcfg["max_agents"]) - mini(int(vcfg["min_living_agents"]), ceili(float(dtown["living"])))
	var k := ceili(total / float(ucap))
	a = _agents(big)[1]
	t.ok(k > 1 and a.undead_scale == k, "crowd: %d workers over the undead share %d of max_agents: 1 stroke = %d (got %d)"
		% [total, ucap, k, a.undead_scale])
	t.ok(_counts_match(a, dtown, k), "crowd: every job and the idle sampled by k")
	t.ok(a.undead.size() <= ucap + dtown["jobs"].size(), "crowd: the strokes stay at the cap (%d)" % a.undead.size())
	a = _agents(demo)[1]
	t.ok(a.undead_scale == 1 and _counts_match(a, demo["town"]) and a.count("idle") == 8,
		"demo: every job building staffed, 8 idle at the crypt, under the cap (1 stroke = 1)")
	a = _agents(pre)[1]
	t.ok(a.undead_scale == 1 and _counts_match(a, pre["town"]), "pre_vei: every worker is a stroke (%d)" % a.undead.size())


func _agent_growth(day1: Dictionary) -> void:
	var pair := _agents(day1, {}, _one_to_one())
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	var more: Dictionary = day1.duplicate(true)
	var idle0 := a.count("idle")
	var living0 := a.living_count()
	more["town"]["workers"]["idle"] = float(idle0) + 20.0
	more["town"]["living"] = float(living0) + 20.0
	_resync(m, a, more)
	var rate := float(vcfg["spawn_per_s"])
	var fps := 30.0
	var clock := 0.0
	var gradual := true
	var old := {}
	for u in a.undead + a.living:
		old[u] = true
	var first_u := Vector2.INF
	var first_l := Vector2.INF
	for i in int(round((24.0 / rate + 2.0) * fps)):
		clock += 1.0 / fps
		a.step(1.0 / fps, fposmod(clock / tempo_s, 1.0), false)
		gradual = gradual and a.count("idle") - idle0 <= rate * clock + 1.0 + 1e-6 and a.living_count() - living0 <= rate * clock + 1.0 + 1e-6
		for u in a.undead:
			if not old.has(u) and first_u == Vector2.INF:
				first_u = u.pos
		for u in a.living:
			if not old.has(u) and first_l == Vector2.INF:
				first_l = u.pos
	t.ok(gradual, "growth is gradual: at most spawn_per_s new agents a second per kind")
	t.ok(a.count("idle") == idle0 + 20 and a.living_count() == living0 + 20, "and it reaches the stream: +20 idle, +20 living")
	var crypt := (m.lot("lot-01")["building"]["rect"] as Rect2).get_center()
	var step := float(vcfg["step_px"]) * m.scale
	t.ok(first_u.distance_to(crypt) < 60.0 + 4.0 * step, "new undead rise at the crypt")
	t.ok(first_l.distance_to(m.nodes["gate"]) < 4.0 * float(vcfg["lane_px"]) + 12.0, "new living walk in at the gate")
	_resync(m, a, day1)
	var before := a.living_count()
	a.step(1.0 / fps, 0.0, false)
	t.ok(a.living_count() >= before - 1 and a.count("idle") >= idle0 + 19, "shrinking is gradual too")
	_run(a, 200.0, clock)
	var want_u := _undead_want(day1["town"])
	var want_l := roundi(float(day1["town"]["living"]))
	t.ok(a.count("idle") == idle0 and a.living_count() == want_l and a.undead.size() == want_u and a.living.size() == want_l,
		"the removed agents walk home (crypt, gate) and are gone: %d undead (want %d), %d living (want %d)"
		% [a.undead.size(), want_u, a.living.size(), want_l])


func _agent_lockstep(day1: Dictionary) -> void:
	var spb := int(vcfg["steps_per_beat"])
	var duty := float(vcfg["step_duty"])
	t.ok(TownAgents.gait_at(0.0, spb, duty) == 0.0 and is_equal_approx(TownAgents.gait_at(1.0, spb, duty), float(spb)),
		"the gait walks steps_per_beat steps a beat")
	var sub := 1.0 / float(spb)
	t.ok(is_equal_approx(TownAgents.gait_at(sub * duty, spb, duty), 1.0) and is_equal_approx(TownAgents.gait_at(sub * 0.99, spb, duty), 1.0),
		"a step is done by the end of its duty window and holds until the next sub-beat")
	t.ok(is_equal_approx(TownAgents.gait_at(sub * duty * 0.5, spb, duty), 0.5), "halfway through the duty window, half a step")

	var pair := _agents(_demo())
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	var clock := _run(a, 3.0)
	var fps := 240.0
	var dt := 1.0 / fps
	var duty_mask: Array = []
	var masks := {}
	var outside := true
	var too_far := true
	var step := float(vcfg["step_px"]) * m.scale
	for f in int(round(2.0 * tempo_s * fps)):
		var before := {}
		for u in a.undead:
			before[u] = u.pos
		var g0 := TownAgents.gait_at(clock / tempo_s, spb, duty)
		clock += dt
		a.step(dt, fposmod(clock / tempo_s, 1.0), false)
		var g1 := TownAgents.gait_at(clock / tempo_s, spb, duty)
		duty_mask.append(g1 > g0 + 1e-9)
		for u in a.undead:
			if not before.has(u):
				continue
			var moved: float = u.pos.distance_to(before[u])
			if not masks.has(u):
				masks[u] = []
			masks[u].append(moved > 1e-4)
			outside = outside and (moved <= 1e-4 or g1 > g0 + 1e-9)
			too_far = too_far and moved <= step * (g1 - g0) + 1e-3
	t.ok(outside, "undead move only inside the step duty window")
	t.ok(too_far, "and never more than step_px a step")
	var lock := 0
	for u in masks:
		if masks[u] == duty_mask:
			lock += 1
	var rises := 0
	for i in range(1, duty_mask.size()):
		rises += 1 if duty_mask[i] and not duty_mask[i - 1] else 0
	t.ok(rises >= 2 * spb - 1, "two beats hold %d duty windows (%d)" % [2 * spb, rises])
	t.ok(lock >= 10, "lockstep: %d undead step in exactly the same frames, every duty window" % lock)

	# a builder's hammer and a forge flash are beat actions too: only inside the window
	var b2: Dictionary = day1.duplicate(true)
	b2["town"]["jobs"].append({"id": "build", "slots": 1, "staffed": 1.0})
	b2["town"]["buildings"].append({"lot_id": "lot-05", "building_id": "house", "level": 0, "state": "constructing",
		"progress": 0.3, "slots": 0, "staffed": 0.0, "staff_cap": -1, "foreman": "", "output": {}, "upkeep": {"gold": 0.0, "bone": 0.0}})
	a = _agents(b2)[1]
	var builder: TownAgents.Agent = null
	for u in a.undead:
		if u.job == "build":
			builder = u
	clock = 0.0
	var tilted := false
	var still_out := true
	for f in int(round(tempo_s * fps)):
		var g0 := TownAgents.gait_at(clock / tempo_s, spb, duty)
		clock += dt
		a.step(dt, fposmod(clock / tempo_s, 1.0), false)
		var g1 := TownAgents.gait_at(clock / tempo_s, spb, duty)
		tilted = tilted or absf(builder.tilt) > 0.1
		still_out = still_out and (g1 > g0 + 1e-9 or builder.tilt == 0.0)
	t.ok(builder != null and builder.holding and tilted and still_out, "a builder hammers on the beat, still between")


func _agent_reduced(day1: Dictionary) -> void:
	var pair := _agents(day1, {}, _one_to_one())
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	var clock := _run(a, 2.0)
	var want_u := _undead_want(day1["town"])
	var want_l := roundi(float(day1["town"]["living"]))
	var before := {}
	for u in a.undead + a.living:
		before[u] = [u.pos, u.dir]
	clock = _run(a, 10.0, clock, true)
	var still := true
	for u in before:
		still = still and u.pos == before[u][0] and u.dir == before[u][1]
	t.ok(still, "reduced motion: no agent moves or turns, whatever the beat does")
	var more: Dictionary = day1.duplicate(true)
	var idle_more := roundi(float(day1["town"]["workers"]["idle"])) + 4
	var living_more := want_l + 2
	more["town"]["workers"]["idle"] = float(idle_more)
	more["town"]["living"] = float(living_more)
	_resync(m, a, more)
	_run(a, 10.0, clock, true)
	still = true
	for u in before:
		still = still and u.pos == before[u][0]
	t.ok(a.count("idle") == idle_more and a.living_count() == living_more and still, "reduced motion: counts still follow the stream; the others stay put")
	var calm := true
	for u in a.undead:
		calm = calm and u.tilt == 0.0 and u.flash == 0.0
	t.ok(calm, "reduced motion: no beat actions")
	_resync(m, a, day1)
	_run(a, 10.0, clock, true)
	t.ok(a.undead.size() == want_u and a.living.size() == want_l, "reduced motion: removed agents vanish in place")


func _agent_missing(day1: Dictionary) -> void:
	var v: Dictionary = day1.duplicate(true)
	var keep: Array = []
	for b in v["town"]["buildings"]:
		if b["building_id"] != "charnel_house":
			keep.append(b)
	v["town"]["buildings"] = keep
	var haulers := 0
	var idle0 := roundi(float(day1["town"]["workers"]["idle"]))
	for j in day1["town"]["jobs"]:
		if j["id"] == "haul":
			haulers = roundi(float(j["staffed"]))
	t.ok(haulers > 0, "day1 has haulers to idle (%d)" % haulers)
	var a: TownAgents = _agents(v)[1]
	t.ok(a.count("haul") == 0 and a.count("idle") == idle0 + haulers,
		"no charnel house: its %d haulers idle at the crypt (with the %d already idle)" % [haulers, idle0])
	var pit_hold := true
	for u in a.undead:
		if u.job == "pit":
			pit_hold = pit_hold and u.holding
	t.ok(pit_hold, "with no charnel house to fetch from, pit workers stand at the pit")
	var pair := _agents(day1)
	var m: TownModel = pair[0]
	a = pair[1]
	var clock := _run(a, 2.0)
	_resync(m, a, v)
	_run(a, 0.1, clock)
	t.ok(a.count("haul") == 0 and a.count("idle") == idle0 + haulers, "a job building gone mid-run re-tasks its agents to idle at once")

	var b2: Dictionary = day1.duplicate(true)
	b2["town"]["jobs"].append({"id": "build", "slots": 2, "staffed": 2.0})
	a = _agents(b2)[1]
	t.ok(a.count("build") == 0 and a.count("idle") == idle0 + 2, "build with nothing under construction: the builders idle")
	b2["town"]["buildings"].append({"lot_id": "lot-05", "building_id": "house", "level": 0, "state": "constructing",
		"progress": 0.3, "slots": 0, "staffed": 0.0, "staff_cap": -1, "foreman": "", "output": {}, "upkeep": {"gold": 0.0, "bone": 0.0}})
	a = _agents(b2)[1]
	var at_lot := true
	for u in a.undead:
		if u.job == "build":
			at_lot = at_lot and u.site == "lot-05" and u.holding
	t.ok(a.count("build") == 2 and at_lot, "build goes to the constructing lot")


func _holding(a: TownAgents, jobs: Array) -> int:
	var n := 0
	for u in a.undead:
		if u.job in jobs and u.holding:
			n += 1
	return n


func _agent_held(day1: Dictionary) -> void:
	var up := _patched(day1, "lot-03", {"state": "constructing", "progress": 0.4, "level": 0})
	var pair := _agents(day1)
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	var clock := _run(a, 1.0)
	# a pit worker on its way to the pit with a body when the charnel house goes up for upgrade
	var guard := 0
	while guard < 600 and not _any_carry(a):
		clock = _run(a, 0.1, clock)
		guard += 1
	t.ok(_any_carry(a), "a pit worker is carrying before the charnel house is (re)built")
	_resync(m, a, up)
	clock = _run(a, 90.0, clock)
	t.ok(_holding(a, ["pit"]) > 0, "a charnel house being built (level 0): pit workers stand at the pit")
	var carried := false
	for u in a.undead:
		carried = carried or (u.holding and u.carry)
	t.ok(not carried, "a held pit worker carries no pip")
	_resync(m, a, day1)
	clock = _run(a, 1.0, clock)
	t.ok(_holding(a, ["pit", "haul"]) == 0, "charnel house built: no pit or haul worker is still held")
	var loops := true
	for u in a.undead:
		if u.job == "pit":
			loops = loops and u.stops == ["lot:lot-03", "lot:lot-02"]
	t.ok(loops, "and the pit loop is charnel -> pit again")

	# a builder follows the work: its lot finishes, another is still constructing
	var b2: Dictionary = day1.duplicate(true)
	b2["town"]["jobs"].append({"id": "build", "slots": 2, "staffed": 2.0})
	for lot in ["lot-05", "lot-06"]:
		b2["town"]["buildings"].append({"lot_id": lot, "building_id": "house", "level": 0, "state": "constructing",
			"progress": 0.3, "slots": 0, "staffed": 0.0, "staff_cap": -1, "foreman": "", "output": {}, "upkeep": {"gold": 0.0, "bone": 0.0}})
	pair = _agents(b2)
	m = pair[0]
	a = pair[1]
	clock = _run(a, 20.0)
	var done := _patched(b2, "lot-05", {"state": "active", "progress": 1.0, "level": 1})
	_resync(m, a, done)
	clock = _run(a, 30.0, clock)
	var on_6 := true
	var builders := 0
	for u in a.undead:
		if u.job == "build":
			builders += 1
			on_6 = on_6 and u.site == "lot-06" and u.holding and (m.lot("lot-06")["rect"] as Rect2).grow(48.0).has_point(u.pos)
	t.ok(builders == 2 and on_6, "a builder at a finished lot re-routes to the remaining constructing lot and holds there")

	# a market being built (level 0) holds no stall worker and is not a seller
	var mk := _patched(day1, "lot-04", {"state": "constructing", "progress": 0.4, "level": 0})
	pair = _agents(day1)
	m = pair[0]
	a = pair[1]
	clock = _run(a, 1.0)
	_resync(m, a, mk)
	clock = _run(a, 10.0, clock)
	t.ok(_holding(a, ["stall"]) == 0, "a market being built holds no stall worker")


## An upgrade keeps working at its old level (STATE-API 4.3): the lot stays a job site (and a
## market) for its own jobs, and is a build site as well.
func _agent_upgrading(day1: Dictionary) -> void:
	var mk := _patched(day1, "lot-04", {"state": "constructing", "progress": 0.4, "level": 1, "output": {"gold": 0.3}})
	mk["town"]["trade_rate"] = 2.0
	var pair := _agents(day1)
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	var clock := _run(a, 1.0)
	_resync(m, a, mk)
	clock = _run(a, 10.0, clock)
	var stall_held := _holding(a, ["stall"])
	t.ok(stall_held > 0, "a market under upgrade keeps its stall workers (%d holding)" % stall_held)
	var seller: TownAgents.Agent = null
	for u in a.undead:
		if u.job == "stall":
			seller = u
	for p in a.living:
		p.pos = seller.pos + Vector2(20, 0)
	var dt := 0.125
	for i in 8:
		a.step(dt, 0.0, true)
	t.ok(a.trades_fired >= 1 and a.arcs.size() >= 1, "and its trade arcs keep firing while trade_rate > 0 (%d)" % a.trades_fired)
	var charnel := _patched(day1, "lot-03", {"state": "constructing", "progress": 0.4, "level": 1})
	pair = _agents(day1)
	m = pair[0]
	a = pair[1]
	clock = _run(a, 1.0)
	_resync(m, a, charnel)
	clock = _run(a, 20.0, clock)
	t.ok(_holding(a, ["pit"]) == 0, "a charnel house under upgrade holds no pit worker: it still works")
	var loops := true
	for u in a.undead:
		if u.job == "pit":
			loops = loops and u.stops == ["lot:lot-03", "lot:lot-02"]
	t.ok(loops, "and the pit loop is still charnel -> pit")


func _any_carry(a: TownAgents) -> bool:
	for u in a.undead:
		if u.carry:
			return true
	return false


func _agent_seed(day1: Dictionary) -> void:
	var m := _model()
	var a := TownAgents.new(_one_to_one(), cfg["buildings"], cfg["economy"], tempo_s, 7)
	m.update({}, VIEW_RECT)
	a.sync(m, {})
	t.ok(a.undead.is_empty() and a.living.is_empty(), "no town view yet: nobody is placed")
	m.update(day1, VIEW_RECT)
	a.sync(m, day1)
	t.ok(_counts_match(a, day1["town"]) and a.living_count() == roundi(day1["town"]["living"]),
		"the first sync with a town places the whole day1 population at once (not trickled)")


func _agent_loops(day1: Dictionary, demo: Dictionary) -> void:
	var pair := _agents(day1)
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	var ok := true
	for p in a.living:
		ok = ok and p.stops == ["gate", "lot:lot-04", "lot:lot-04"]
	t.ok(ok, "day1 (no houses, no inn): the living cycle gate -> market -> market")
	ok = true
	for u in a.undead:
		match u.job:
			"haul":
				ok = ok and u.stops == ["lot:lot-03", "away"]
			"pit":
				ok = ok and u.stops == ["lot:lot-03", "lot:lot-02"]
			"stall":
				ok = ok and u.stops == ["lot:lot-04"] and u.holding
	t.ok(ok, "day1 loops: haul charnel <-> gate, pit charnel -> pit, the stall holds at the market")
	var carry_ok := true
	var hidden_ok := true
	var hid := 0
	var carried := 0
	var gate: Vector2 = m.nodes["gate"]
	var clock := 0.0
	for i in 120 * 30:
		clock += 1.0 / 30.0
		a.step(1.0 / 30.0, fposmod(clock / tempo_s, 1.0), false)
		for u in a.undead:
			carry_ok = carry_ok and u.carry == (u.job == "pit" and u.stop == 1)
			carried += 1 if u.carry else 0
			if u.hidden:
				hid += 1
				hidden_ok = hidden_ok and u.job == "haul" and u.pos.distance_to(gate) < 1.0
	t.ok(carry_ok and carried > 0, "a pit worker carries a dead pip only on its way to the pit")
	t.ok(hidden_ok and hid > 0, "haulers leave town: hidden only while past the gate")

	var d: TownAgents = _agents(demo)[1]
	var homes: Array = []
	for b in demo["town"]["buildings"]:
		if b["building_id"] in ["house", "inn"] and b["state"] != "constructing":
			homes.append("lot:" + String(b["lot_id"]))
	ok = not d.living.is_empty()
	var used := {}
	for p in d.living:
		ok = ok and p.stops[0] in homes and p.stops[1] == "lot:lot-04" and p.stops[2] == "lot:lot-02"
		used[p.stops[0]] = true
	t.ok(ok and used.size() == homes.size(), "demo: home (every house and the inn) -> market -> inn")


func _trade_arcs(day1: Dictionary) -> void:
	var v := _patched(day1, "lot-04", {"output": {"gold": 0.3}})
	v["town"]["trade_rate"] = 2.0
	var pair := _agents(v)
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	t.ok(not a.trade_standin and a.trade_rate == 2.0, "real outputs: arcs follow view_town().trade_rate")
	var seller: TownAgents.Agent = null
	for u in a.undead:
		if u.job == "stall":
			seller = u
	t.ok(seller != null and seller.holding, "the stall worker holds at the market")
	for p in a.living:
		p.pos = seller.pos + Vector2(20, 0)
	var dt := 0.125
	for i in 8:
		a.step(dt, 0.0, true)
	t.ok(a.trades_fired == 2 and a.arcs.size() >= 1, "2.0 sales/s for 1 s fires 2 arcs (%d)" % a.trades_fired)
	var ends := true
	for arc in a.arcs:
		ends = ends and arc["seller"].job == "stall" and not arc["buyer"].undead
	t.ok(ends, "each arc runs from a living buyer to the stall worker")
	v["town"]["trade_rate"] = 100.0
	_resync(m, a, v)
	var cap := int(vcfg["max_trade_arcs"])
	var capped := true
	for i in 40:
		a.step(dt, 0.0, true)
		capped = capped and a.arcs.size() <= cap
	t.ok(capped and a.arcs.size() == cap, "arcs never exceed max_trade_arcs (%d)" % cap)
	v["town"]["trade_rate"] = 0.0
	_resync(m, a, v)
	for i in int(ceil(float(vcfg["trade_arc_s"]) / dt)) + 1:
		a.step(dt, 0.0, true)
	t.ok(a.arcs.is_empty(), "arcs end after trade_arc_s")
	for p in a.living:
		p.pos = seller.pos + Vector2(float(vcfg["trade_reach_px"]) * m.scale * 2.0, 0)
	v["town"]["trade_rate"] = 2.0
	_resync(m, a, v)
	var fired := a.trades_fired
	for i in 8:
		a.step(dt, 0.0, true)
	t.ok(a.trades_fired == fired, "no living agent within trade_reach_px: the sale draws no arc")


func _trade_standin(live: Dictionary) -> void:
	var a: TownAgents = _agents(live)[1]
	t.ok(not a.trade_standin and is_equal_approx(a.trade_rate, float(live["town"]["trade_rate"])),
		"live outputs (E2a): the stand-in is off and the rate is the view's trade_rate")
	var day1 := _stub(live)
	a = _agents(day1)[1]
	var stall := 0.0
	for j in day1["town"]["jobs"]:
		if j["id"] == "stall":
			stall += float(j["staffed"])
	var want := stall * float(vcfg["standin_sales_per_stall"])
	t.ok(a.trade_standin and stall > 0.0 and want > 0.0 and is_equal_approx(a.trade_rate, want),
		"outputs stubbed: the stand-in rate is staffed stalls x standin_sales_per_stall = %.3f (day1: > 0)" % want)
	var v: Dictionary = day1.duplicate(true)
	for j in v["town"]["jobs"]:
		if j["id"] == "stall":
			j["staffed"] = 2.0
	a = _agents(v)[1]
	t.ok(is_equal_approx(a.trade_rate, 2.0 * float(vcfg["standin_sales_per_stall"])), "two staffed stalls sell twice as fast")
	v["town"]["living"] = 1.0
	a = _agents(v)[1]
	t.ok(is_equal_approx(a.trade_rate, float(vcfg["standin_sales_per_living"])), "capped by living x standin_sales_per_living")
	v = _patched(day1, "lot-04", {"output": {"gold": 0.3}})
	v["town"]["trade_rate"] = 0.7
	a = _agents(v)[1]
	t.ok(not a.trade_standin and is_equal_approx(a.trade_rate, 0.7), "one real output switches the stand-in off: the view's trade_rate")
	v["town"]["trade_rate"] = 0.0
	a = _agents(v)[1]
	t.ok(a.trade_rate == 0.0, "and a real zero stays zero")


## Distance along `poly` of the point on it nearest `p`.
func _along(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var at := 0.0
	var run := 0.0
	for i in range(1, poly.size()):
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i - 1], poly[i])
		if q.distance_to(p) < best:
			best = q.distance_to(p)
			at = run + poly[i - 1].distance_to(q)
		run += poly[i - 1].distance_to(poly[i])
	return at


func _carts(day1: Dictionary) -> void:
	var f := float(vcfg["cart_town_frac"])
	var mass := float(vcfg["cart_pip_mass"])
	var v: Dictionary = day1.duplicate(true)
	v["town"]["haul"]["convoys"] = [
		{"from": "greywall", "to": "covington", "phase": "back", "t": 0.5, "load": 9.0},
		{"from": "greywall", "to": "covington", "phase": "back", "t": 1.0 - f * 0.5, "load": 9.0},
		{"from": "covington", "to": "greywall", "phase": "out", "t": f * 0.25, "load": 0.0},
		{"from": "covington", "to": "greywall", "phase": "out", "t": 0.6, "load": 0.0},
		{"from": "ashgate", "to": "covington", "phase": "back", "t": 1.0, "load": mass * 3.0 + 0.01},
	]
	var pair := _agents(v)
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	t.ok(a.carts.size() == 3, "carts only on the in-town legs (back t >= 1 - f, out t <= f): %d of 5" % a.carts.size())
	if a.carts.size() != 3:
		return
	t.ok(a.carts[0]["pips"] == ceili(9.0 / mass) and a.carts[1]["pips"] == 0 and a.carts[2]["pips"] == 4,
		"pips = ceil(load / cart_pip_mass): %s" % str([a.carts[0]["pips"], a.carts[1]["pips"], a.carts[2]["pips"]]))
	var charnel: Rect2 = m.lot("lot-03")["building"]["rect"]
	var end: Vector2 = a.carts[2]["pos"]
	t.ok(charnel.grow(float(vcfg["front_gap_px"]) * m.scale + 0.5).has_point(end), "back at t = 1: the cart is at the charnel house")
	var road := m.path("gate", m.lot("lot-03")["door"])
	road.append(end)
	var length := 0.0
	for i in range(1, road.size()):
		length += road[i - 1].distance_to(road[i])
	t.near(_along(road, a.carts[0]["pos"]), length * 0.5, 0.5, "back halfway through its town leg: halfway in from the gate")
	t.near(_along(road, a.carts[1]["pos"]), length * 0.75, 0.5, "out a quarter through its town leg: a quarter of the way out")
	var p0 := _along(road, a.carts[0]["pos"])
	var ahead := _along(road, a.carts[0]["pos"] + a.carts[0]["dir"] * 4.0)
	var p1 := _along(road, a.carts[1]["pos"])
	var ahead1 := _along(road, a.carts[1]["pos"] + a.carts[1]["dir"] * 4.0)
	t.ok(ahead > p0 and ahead1 < p1, "an inbound cart heads for the charnel house, an outbound one for the gate")
	a.step(0.1, 0.0, true)
	t.ok(a.carts[2]["lit"] == a.lit(end) and a.lit(end), "a cart load inside Relish's light is lit (dead_lit)")
	var none: Dictionary = v.duplicate(true)
	var keep: Array = []
	for b in none["town"]["buildings"]:
		if b["building_id"] != "charnel_house":
			keep.append(b)
	none["town"]["buildings"] = keep
	_resync(m, a, none)
	t.ok(a.carts.is_empty(), "no charnel house: no carts")


func _relish(day1: Dictionary) -> void:
	var pair := _agents(day1)
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	var crypt: Rect2 = m.lot("lot-01")["building"]["rect"]
	t.ok(a.relish_home and a.relish_pos == crypt.get_center(), "Relish home: her token sits at the slab (the crypt's centre)")
	var r := float(vcfg["relish_light_r"]) * m.scale
	t.ok(a.lit(a.relish_pos + Vector2(r - 1.0, 0)) and not a.lit(a.relish_pos + Vector2(r + 1.0, 0)),
		"dead pips are lit inside relish_light_r only")
	var demo := _demo()
	_resync(m, a, demo)
	var k := float(vcfg["relish_brighten"])
	var right := a.lot_brighten.size() == m.lots.size()
	var lit_n := 0
	var dark_n := 0
	for i in m.lots.size():
		var l: Dictionary = m.lots[i]
		var inside: bool = (l["rect"] as Rect2).get_center().distance_to(a.relish_pos) <= r and not l["building"].is_empty()
		right = right and is_equal_approx(a.lot_brighten[i], k if inside else 0.0)
		lit_n += 1 if inside else 0
		dark_n += 1 if not inside and not l["building"].is_empty() else 0
	t.ok(right and lit_n >= 2 and dark_n >= 2, "her light brightens the built lots within relish_light_r only (%d lit, %d not)" % [lit_n, dark_n])
	var away: Dictionary = demo.duplicate(true)
	away["town"]["relish_home"] = false
	_resync(m, a, away)
	var none := true
	for f in a.lot_brighten:
		none = none and f == 0.0
	t.ok(not a.relish_home and none and not a.lit(a.relish_pos), "Relish away: no token, no brighten, no lit pips")


func _foremen(mid: Dictionary) -> void:
	var pair := _agents(mid)
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	t.ok(a.foremen.size() == 1 and a.foremen[0]["lot_id"] == "lot-04", "midgame: the market's foreman stands at it")
	if a.foremen.size() == 1:
		var uid := String(m.lot("lot-04")["building"]["foreman"])
		var kind := ""
		for e in mid["big_undead"]["big_undead"]:
			if e["uid"] == uid:
				kind = String(e["kind"])
		var want: int = (mid["big_undead"]["big_undead"] as Array).reduce(func(w, e): return int(e.get("filled_slots", -1)) if e["uid"] == uid else w, -1)
		t.ok(want > 0 and a.foremen[0]["strokes"] == want, "filled_slots in view_big_undead: that count (api-request #6)")
		t.ok((m.lot("lot-04")["rect"] as Rect2).grow(48.0).has_point(a.foremen[0]["pos"]), "at its building")
	var slab: Dictionary = cfg["town"]["slab"]
	t.ok(TownStandins.foreman_strokes({"kind": "zombie", "filled_slots": 3}, vcfg, slab) == 3, "an entry with filled_slots: that count (api-request #6)")
	t.ok(TownStandins.foreman_strokes({"kind": "zombie"}, vcfg, slab) == 2, "no filled_slots: the kind's anatomy slots (zombie: 2)")
	t.ok(TownStandins.foreman_strokes({"kind": "ghost"}, vcfg, slab) == int(vcfg["foreman_strokes"]), "unknown kind: view.foreman_strokes")
	t.ok(TownStandins.foreman_strokes({}, vcfg, slab) == int(vcfg["foreman_strokes"]), "no entry: view.foreman_strokes")


func _edge_rates(day1: Dictionary, demo: Dictionary) -> void:
	for pair in [["day1", day1], ["demo", demo]]:
		var p := _agents(pair[1])
		var m: TownModel = p[0]
		var a: TownAgents = p[1]
		a.step(1.0 / 30.0, 0.0, true)
		var lit_entry := 0
		for r in a.edge_rates:
			lit_entry += 1 if r > 0.0 else 0
		t.ok(a.edge_rates.size() == m.streets.size() and lit_entry > 0, "%s: streets are lit from the first frame, reduced motion too (%d)" % [pair[0], lit_entry])
		var clock := _run(a, 3.0)
		_run(a, 40.0, clock, true)
		var v := float(vcfg["step_px"]) * m.scale * float(vcfg["steps_per_beat"]) / tempo_s
		var want := PackedFloat32Array()
		want.resize(m.streets.size())
		for u in a.undead:
			var e := TownAgents.edge_of(u)
			if e >= 0:
				want[e] += v / float(m.streets[e]["length"]) * float(a.undead_scale)
		var match_all := true
		var lit := 0
		for i in m.streets.size():
			match_all = match_all and absf(a.edge_rates[i] - want[i]) < 1e-3
			lit += 1 if a.edge_rates[i] > 0.0 else 0
		t.ok(match_all, "%s: each street's stream = its walking undead x their mean speed / its length (x 1 stroke = k)" % pair[0])
		t.ok(lit > 0 and lit < m.streets.size(), "%s: streets with walkers lit, the rest off (%d of %d)" % [pair[0], lit, m.streets.size()])
	var q := _agents(day1)
	var m2: TownModel = q[0]
	var b: TownAgents = q[1]
	var c2 := _run(b, 3.0)
	var empty: Dictionary = day1.duplicate(true)
	empty["town"]["jobs"] = []
	empty["town"]["workers"]["idle"] = 0.0
	empty["town"]["living"] = 0.0
	_resync(m2, b, empty)
	_run(b, 120.0, c2)
	var dark := b.undead.is_empty()
	for r in b.edge_rates:
		dark = dark and r < 1e-3
	t.ok(dark, "no workers left on the streets: every stream goes dark")


## Every number and key the town view reads lives in town.json's view block.
func _view_keys() -> void:
	var keys := ["relish_away_ink", "floor_tint", "floor_reach_px", "lot_pulse_gain", "bed", "bed_line", "junction_px",
		"flow_ref", "flow_glow", "chevron_px", "blueprint_dash_px", "blueprint_w_px", "locked_dot", "sil_w_px",
		"sil_glow", "sil_core_mix", "dim_w_px", "band_px", "pip_px", "pip_gap_px", "pip_glow", "slot_tick_px",
		"group_gap_px", "progress_ticks", "upgrade_mark", "progress_tick_w_px", "reveal_rate", "head", "warn", "slab_rings_px",
		"slab_ring_w_px", "slab_ring_alpha", "slab_ring_reach_px", "label_px", "wall_w_px", "wall_glow", "tierup_beats",
		"tierup_head", "tierup_flash", "demo_tierup", "walkout", "raise_echo", "demo_raise", "slot_open_w_px", "pip_w_px", "chevron_w_mul",
		"max_agents", "min_living_agents", "living_ratio_max", "legend", "trade_arc_min_h_px", "agent_hit_px", "pip_group", "pip_group_gap_px", "pip_count_px",
		"slab_ring_away_alpha", "badge", "rate_units", "status", "agent_status", "pick", "float", "ring_order",
		"spawn_per_s", "steps_per_beat", "step_duty", "step_px",
		"undead_dwell_steps", "haul_away_steps", "idle_dwell_steps", "idle_ring_px", "lane_px", "front_gap_px",
		"post_spread", "stall_shuffle_px", "hammer_deg", "living_speed_px", "living_dwell_s", "living_sway_px",
		"living_sway_stride_px", "trade_arc_s", "trade_reach_px", "max_trade_arcs", "cart_town_frac", "cart_pip_mass",
		"relish_light_r", "relish_brighten", "flow_smooth_s", "foreman_strokes", "standin_sales_per_stall", "standin_sales_per_living", "agent",
		"gate_reasons", "protected", "queue_max", "cap_buildings", "demolish_confirm_s", "placement_dim", "hit_min_px", "cap_bar",
		"grow_chunk_s", "grow_text", "zoom_text", "reasons", "states", "needs", "queue_text", "benefit", "card", "hover", "suggest", "ghost", "flash", "shortage_text"]
	var nested := {"head": ["core_px", "ring_mul", "ring_w_px", "glow"], "warn": ["size_px", "line_px", "glow", "bang_px", "dot_px"],
		"tierup_head": ["len_px", "gain", "w_mul", "ring_mul", "ring_w_px", "dot_mul", "glow"], "demo_tierup": ["tier", "delay_s"],
		"bed": ["key", "alpha", "width_px"], "bed_line": ["key", "alpha", "width_px"], "locked_dot": ["key", "alpha", "step_px", "size_px"],
		"agent": ["undead_len_px", "undead_w_px", "undead_glow", "core_px", "flash_mul", "carry_px", "living_len_px",
			"living_bend", "living_w_px", "living_ring_px", "living_glow", "big_px", "big_w_px", "big_gap", "big_glow",
			"cart_pip_px", "cart_pip_gap_px", "cart_cols", "cart_w_px", "tow_px", "arc_w_px", "arc_glow", "arc_bulge",
			"arc_grow", "arc_fade", "arc_chevron_px", "relish_r_px", "relish_core_px", "relish_bob_px", "relish_w_px",
			"relish_glow", "arc_mote_px"],
		"legend": ["undead", "living", "px", "ink", "pad_px"],
		"benefit": ["rate_effects", "plain_effects", "job_text", "now", "upgrade_now"],
		"card": ["w_px", "max_h_px", "gap_px", "edge_px", "row_gap_px"], "hover": ["w_px", "alpha", "grow_px"],
		"suggest": ["w_px", "dash_px", "alpha", "tag_prefix", "x_px", "tag_pad_px"],
		"ghost": ["alpha", "dash_px", "w_px", "ring_px", "ring_w_px", "number_px", "hold_px", "strike_px", "plus_px", "tag_pad_px"],
		"flash": ["w_px", "grow_px", "alpha", "text"], "upgrade_mark": ["text", "px", "key"],
		"badge": ["px", "gap_px", "pad_px", "working", "short", "sep", "idle"],
		"status": ["building", "upgrading", "upgrading_none", "upgrading_lead", "unpaid", "unpaid_none", "idle", "idle_ladder", "idle_capped", "idle_off", "short_one", "short",
			"working", "working_none", "calm", "calm_none", "heart_home", "heart_away", "sep", "px", "pad_px", "gap_px"],
		"agent_status": ["roles", "carry", "living_roles", "idle", "carrying", "going", "working", "heading_out", "out", "home",
			"at", "leaving", "leaving_living", "places"],
		"pick": ["ring_px", "w_px", "gap_px", "pad_px", "px"],
		"float": ["eps", "rise_px", "px", "pip_px", "outline_px"],
		"ring_order": ["px", "offset_px"],
		"shortage_text": ["eta", "stuck", "eta_s", "eta_min", "eta_h", "eta_min_max_s", "eta_s_max_s"]}
	var missing: Array = []
	for k in keys:
		if not vcfg.has(k):
			missing.append(k)
	for k in nested:
		for sub in nested[k]:
			if not vcfg.get(k, {}).has(sub):
				missing.append("%s.%s" % [k, sub])
	t.ok(missing.is_empty(), "town.json view has every key the town view reads: missing %s" % str(missing))
	for k in ["relish_away_ink", "floor_tint"]:
		t.ok(Palette.has(String(vcfg[k])), "view.%s is a Palette key" % k)
	t.ok(not String(vcfg["floor_tint"]) in ["dead", "dead_lit"], "the floor never tints dead")
	for k in ["bed", "bed_line", "locked_dot"]:
		t.ok(Palette.has(String(vcfg[k]["key"])), "view.%s.key is a Palette key" % k)
	t.ok(int(vcfg["label_px"]) >= 12, "labels are at least 12 px")
	t.ok(float(vcfg["lot_pulse_gain"]) >= 0.0, "the lot pulse only brightens (gain >= 0)")
	t.ok(vcfg["tier_walls"].has(String(vcfg["demo_tierup"]["tier"])), "the demo tier-up goes to a tier with walls")
	t.ok(float(vcfg["step_duty"]) > 0.0 and float(vcfg["step_duty"]) < 1.0 and int(vcfg["steps_per_beat"]) >= 1,
		"the gait walks part of each sub-beat (0 < step_duty < 1) and freezes the rest")
	t.ok(float(vcfg["cart_town_frac"]) > 0.0 and float(vcfg["cart_town_frac"]) <= 0.5, "a cart's town leg is a share of its trip")
	t.ok(float(vcfg["relish_brighten"]) >= 0.0 and float(vcfg["spawn_per_s"]) > 0.0, "Relish only brightens; agents do spawn")
	var und_v := float(vcfg["step_px"]) * float(vcfg["steps_per_beat"]) / tempo_s
	t.ok(float(vcfg["living_speed_px"][1]) < und_v, "the living walk slower than the undead's mean pace (%.1f px/s)" % und_v)


# ------------------------------------------------------------- build tab ----
const FORTS := {"ashgate": "Ashgate", "old-sluice": "Old Sluice"}


func _need_views(day1: Dictionary) -> Dictionary:
	# A quiet baseline: nothing is a live need.
	var v: Dictionary = day1.duplicate(true)
	v["vei"]["tithe"] = {"target": "", "eta_s": -1.0, "warning": false, "wave_active": false, "wave_s_left": 0.0}
	v["vei"]["fronts"] = []
	v["relish"]["state"] = "idle"
	v["relish"]["target"] = ""
	v["relish"]["at"] = "covington"
	v["town"]["next_tier"] = {}
	for r in v["hud"]["rates"]:
		if r["id"] == "gold" or r["id"] == "bone":
			r["rate"] = 0.1
	v["town"]["bodies"] = 100.0
	v["town"]["bodies_cap"] = 200.0
	v["town"]["living"] = 5.0
	v["town"]["living_cap"] = 16.0
	v["town"]["morale"] = {"value": 0.8, "target": 0.8, "factors": []}
	v["town"]["workers"]["idle"] = 0.0
	v["town"]["workers"]["muster"] = 0.0
	return v


func _need_ids(v: Dictionary) -> Array:
	var ids: Array = []
	for n in BuildSort.needs(v, FORTS, vcfg, cfg["buildings_view"]):
		ids.append(n["id"])
	return ids


func _build_needs(day1: Dictionary) -> void:
	var v := _need_views(day1)
	t.ok(_need_ids(v).is_empty(), "build needs: a quiet town has none")
	v = _need_views(day1)
	v["vei"]["tithe"]["warning"] = true
	v["vei"]["tithe"]["target"] = "ashgate"
	var n: Array = BuildSort.needs(v, FORTS, vcfg)
	t.ok(_need_ids(v) == ["tithe"] and n[0]["chip"] == "tithe wave on Ashgate", "build needs: a tithe warning names the fort (%s)" % n[0]["chip"])
	v["vei"]["tithe"]["warning"] = false
	v["vei"]["tithe"]["wave_active"] = true
	t.ok(_need_ids(v) == ["tithe"], "build needs: an active tithe wave counts")
	v["vei"]["tithe"]["target"] = ""
	t.ok(BuildSort.needs(v, FORTS, vcfg)[0]["chip"] == "tithe wave coming", "build needs: a wave with no target still has a chip")
	v = _need_views(day1)
	v["vei"]["fronts"] = [{"id": "raw", "need": 0.0, "have": 0.0}, {"id": "giants", "need": 24.0, "have": 26.5},
		{"id": "swarm", "need": 30.0, "have": 12.0}]
	# V-e: no front chip until Vei is in sight (a fort of front_sight_tier taken, or Relish at her gate)
	v["hud"]["highest_tier_flipped"] = int(vcfg["needs"]["front_sight_tier"]) - 1
	t.ok(_need_ids(v).is_empty(), "build needs: a short front is no chip while Vei is out of sight (highest tier taken %d)" % v["hud"]["highest_tier_flipped"])
	v["relish"]["state"] = "at_vei"
	t.ok(_need_ids(v).has("front"), "build needs: Relish at Vei's gate brings Vei in sight")
	v["relish"]["state"] = "idle"
	v["hud"]["highest_tier_flipped"] = int(vcfg["needs"]["front_sight_tier"])
	n = BuildSort.needs(v, FORTS, vcfg)
	t.ok(_need_ids(v) == ["front"] and n[0]["chip"].contains("swarm") and n[0]["chip"].contains("12 of 30"),
		"build needs: the first short front (need > 0, have < need) is named: %s" % n[0]["chip"])
	v["vei"]["fronts"] = [{"id": "giants", "need": 24.0, "have": 24.0}]
	t.ok(_need_ids(v).is_empty(), "build needs: a front that is met is no need")
	v = _need_views(day1)
	v["relish"]["state"] = "travelling"
	v["relish"]["target"] = "old-sluice"
	t.ok(_need_ids(v) == ["warden"] and BuildSort.needs(v, FORTS, vcfg)[0]["chip"].contains("Old Sluice"), "build needs: Relish travelling to a fort")
	v["relish"]["state"] = "idle"
	v["relish"]["target"] = ""
	v["relish"]["at"] = "ashgate"
	t.ok(_need_ids(v) == ["warden"], "build needs: Relish standing at a fort")
	v["relish"]["at"] = "vei"
	t.ok(_need_ids(v).is_empty(), "build needs: Relish at Vei or home is not a fort")
	v = _need_views(day1)
	for r in v["hud"]["rates"]:
		if r["id"] == "gold":
			r["rate"] = -0.05
	t.ok(_need_ids(v) == ["gold"], "build needs: gold net rate below 0")
	v = _need_views(day1)
	v["town"]["bodies"] = 59.0
	t.ok(_need_ids(v) == ["bodies"], "build needs: bodies under 30% of cap")
	v["town"]["bodies"] = 60.0
	t.ok(_need_ids(v).is_empty(), "build needs: bodies at exactly 30% is not low")
	v = _need_views(day1)
	v["town"]["living"] = 16.0
	t.ok(_need_ids(v) == ["housing"], "build needs: living at the living cap")
	v = _need_views(day1)
	v["town"]["morale"]["value"] = 0.49
	t.ok(_need_ids(v) == ["morale"], "build needs: morale under 0.5")
	v["town"]["morale"]["value"] = 0.5
	t.ok(_need_ids(v).is_empty(), "build needs: morale at 0.5 is not low")
	v = _need_views(day1)
	v["town"]["bodies_cap"] = 0.0
	v["town"]["living_cap"] = 0.0
	t.ok(_need_ids(v).is_empty(), "build needs: zero caps never read as a need")
	t.ok(BuildSort.needs({}, {}, vcfg).is_empty(), "build needs: empty views give none")
	var ns: Dictionary = vcfg["needs"]
	t.ok(ns["serves"].keys().size() == ns["order"].size(), "build needs: every ordered need has a serves list")
	for id in ns["order"]:
		for s in ns["serves"][id]:
			var any := false
			for bid in cfg["buildings_view"]:
				any = any or s in cfg["buildings_view"][bid]["serves"]
			t.ok(any, "build needs: some building serves '%s' (needed by %s)" % [s, id])


func _row(id: String, can: bool, reason := "", lots: Array = []) -> Dictionary:
	return {"building_id": id, "cost": {"gold": 10.0, "bone": 0.0, "relics": 0}, "count": 0, "lot_size": 1, "max_level": 2,
		"requires": {"tier": "village", "blueprint": "", "building": ""}, "can_build": can, "reason": reason, "lots": lots}


func _build_sort(day1: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	# well/bakery serve morale; market serves gold; house serves housing; inn is gated; forge unbuildable.
	var rows := [_row("market", false, "no_gold"), _row("house", true, "", ["lot-05"]), _row("inn", false, "needs_tier"),
		_row("well", true, "", ["lot-06"]), _row("bakery", false, "no_gold"), _row("forge", true, "", ["lot-07"])]
	var ids := func(items: Array) -> Array:
		return items.map(func(i): return i["row"]["building_id"])
	var base: Array = ids.call(BuildSort.sort_rows(rows, [], bv, vcfg))
	t.ok(base == ["house", "well", "forge", "market", "bakery", "inn"], "build sort: no need: buildable, then blocked, gated last, catalog order inside (%s)" % str(base))
	var needs: Array = [{"id": "morale", "chip": "morale is low", "serves": ["morale"]}]
	var items: Array = BuildSort.sort_rows(rows, needs, bv, vcfg)
	var got: Array = ids.call(items)
	t.ok(got == ["well", "house", "forge", "bakery", "market", "inn"],
		"build sort: buildable serving a need, buildable, serving but short, other blocked, gated (%s)" % str(got))
	var cls: Array = items.map(func(i): return i["cls"])
	t.ok(cls == [BuildSort.CLS_NEED_BUILDABLE, BuildSort.CLS_BUILDABLE, BuildSort.CLS_BUILDABLE, BuildSort.CLS_NEED_SHORT,
		BuildSort.CLS_SHORT, BuildSort.CLS_GATED], "build sort: the five classes (%s)" % str(cls))
	t.ok(items[0]["chip"] == "morale is low" and items[0]["need"] == "morale", "build sort: the serving row carries the need's chip")
	t.ok(items[1]["chip"] == "" and items[1]["need"] == "", "build sort: other rows carry no chip")
	t.ok(items[3]["chip"] == "morale is low", "build sort: a blocked row serving the need keeps its chip")
	var two: Array = [{"id": "gold", "chip": "gold is draining", "serves": ["gold"]}, {"id": "housing", "chip": "no room", "serves": ["housing"]}]
	items = BuildSort.sort_rows(rows, two, bv, vcfg)
	got = ids.call(items)
	t.ok(got == ["house", "well", "forge", "market", "bakery", "inn"], "build sort: several live needs (%s)" % str(got))
	t.ok(items[3]["chip"] == "gold is draining" and items[0]["chip"] == "no room", "build sort: each row's chip names the need it serves")
	# gated rows: those serving a need rank by need, the rest after them by catalog order, whatever the input order
	var gated := [_row("raising_pit", false, "needs_tier"), _row("house", false, "needs_tier"), _row("forge", false, "needs_tier"), _row("market", false, "needs_tier")]
	var consistent := true
	for rot in gated.size():
		var rows_in: Array = gated.slice(rot) + gated.slice(0, rot)
		var g: Array = ids.call(BuildSort.sort_rows(rows_in, two, bv, vcfg))
		var rest: Array = rows_in.map(func(r): return r["building_id"]).filter(func(i): return i != "market" and i != "house")
		consistent = consistent and g == ["market", "house"] + rest
		var tot := BuildSort.sort_rows(rows_in, two, bv, vcfg)
		for i in range(1, tot.size()):  # (cls, rank, idx) is a total order: the sorted list never steps backwards
			var a: Dictionary = tot[i - 1]
			var b: Dictionary = tot[i]
			var ra: int = a["rank"] if String(a["need"]) != "" else two.size()
			var rb: int = b["rank"] if String(b["need"]) != "" else two.size()
			consistent = consistent and (ra < rb or (ra == rb and a["idx"] < b["idx"]))
	t.ok(consistent, "build sort: a mixed gated set sorts by (class, need rank, catalog order), whichever way it arrives")
	t.ok(items[1]["chip"] == "no room", "build sort: a row serving two listed needs takes the first listed need that it serves")
	# Funds-blocked and serving beats funds-blocked and not serving, whatever the catalog order.
	var fb: Array = ids.call(BuildSort.sort_rows([_row("market", false, "no_gold"), _row("bakery", false, "no_gold")],
		[{"id": "housing", "chip": "x", "serves": ["housing"]}], bv, vcfg))
	t.ok(fb == ["bakery", "market"], "build sort: serving but short before other blocked (%s)" % str(fb))
	# A gated row that serves the need still sorts below a buildable one that serves it.
	var g: Array = ids.call(BuildSort.sort_rows([_row("inn", false, "needs_tier"), _row("house", true, "", ["lot-05"])],
		[{"id": "housing", "chip": "x", "serves": ["housing"]}], bv, vcfg))
	t.ok(g == ["house", "inn"], "build sort: gated serving row after buildable serving row")
	var gs: Array = ids.call(BuildSort.sort_rows([_row("inn", false, "needs_tier"), _row("market", false, "no_gold")],
		[{"id": "housing", "chip": "x", "serves": ["housing"]}], bv, vcfg))
	t.ok(gs == ["market", "inn"], "build sort: gated serving row after a plain blocked row")
	# Stable and total: same set, every row once.
	var all: Array = ids.call(BuildSort.sort_rows(rows, two, bv, vcfg))
	all.sort()
	t.ok(all == ["bakery", "forge", "house", "inn", "market", "well"], "build sort: every row appears exactly once")
	# The real catalog sorts and every row classifies.
	var cat: Array = day1["catalog"]["buildings"]
	var real: Array = BuildSort.sort_rows(cat, BuildSort.needs(day1, FORTS, vcfg), bv, vcfg)
	var built_unique := cat.filter(func(r): return BuildSort.is_hidden(r, bv)).size()
	t.ok(real.size() == cat.size() - built_unique, "build sort: the day1 catalog keeps all %d rows but the %d built unique" % [cat.size(), built_unique])
	t.ok(BuildSort.can_queue(_row("house", true, "", ["lot-05"]), vcfg), "build sort: a buildable row can be queued")
	t.ok(BuildSort.can_queue(_row("house", false, "no_gold", ["lot-05"]), vcfg), "build sort: an unaffordable row can be queued")
	t.ok(BuildSort.can_queue(_row("inn", false, "needs_tier", ["lot-05"]), vcfg), "build sort: a gated row can be queued (it waits for its tier)")
	t.ok(not BuildSort.can_queue(_row("inn", false, "needs_tier", []), vcfg), "build sort: a row with no free lot can't be queued")
	t.ok(not BuildSort.can_queue(_row("crypt", false, "unique", ["lot-05"]), vcfg), "build sort: a built unique building can't be queued")
	t.ok(not BuildSort.can_queue(_row("house", false, "no_lot", []), vcfg), "build sort: a row with no free lot cannot be queued")


const ALL_REASONS := ["unknown_building", "unknown_lot", "lot_locked", "lot_taken", "lot_too_small", "empty_lot",
	"under_construction", "needs_tier", "needs_blueprint", "needs_building", "no_lot", "no_gold", "no_bone", "no_relics",
	"max_level", "protected", "not_building", "queue_full", "cost_exceeds_cap", "unknown_index", "bad_order", "unpaid", "unique",
	"wait_slot"]


func _build_reasons(day1: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var row := {"building_id": "embalmer", "cost": {"gold": 100.0, "bone": 30.0, "relics": 2}, "lot_size": 2,
		"requires": {"tier": "village", "blueprint": "embalmer", "building": "house"}}
	var st := {"gold": 40.0, "bone": 30.0, "relics": 0.0}
	for r in ALL_REASONS:
		var txt := BuildSort.reason_text(r, row, st, bv, vcfg)
		t.ok(txt != "" and txt != r and not txt.contains("_") and not txt.contains("{"), "reason '%s' has human text: %s" % [r, txt])
	for r in vcfg["reasons"]:
		if r != "_unknown":
			t.ok(r in ALL_REASONS or r in ["no_cost", "just_queued", "catching_up"], "view.reasons.%s is a documented reason id (no_cost and just_queued are the town's own: past level_costs, and a lot a Queue click took since the last bind, BuildSort.send_queue; catching_up is every command's, STATE-API §4; wait_slot is economy P3's queue reason)" % r)
	t.ok(BuildSort.reason_text("needs_tier", row, st, bv, vcfg) == "needs Village tier", "reason: needs_tier uses requires.tier")
	t.ok(BuildSort.reason_text("needs_blueprint", row, st, bv, vcfg) == "needs the Embalmer blueprint: dungeon loot", "reason: needs_blueprint names the blueprint")
	t.ok(BuildSort.reason_text("needs_building", row, st, bv, vcfg) == "needs a House first", "reason: needs_building names the building")
	t.ok(BuildSort.reason_text("no_lot", row, st, bv, vcfg) == "no free lot fits (size 2)", "reason: no_lot carries the size")
	t.ok(BuildSort.reason_text("no_gold", row, st, bv, vcfg) == "needs 60 gold: build a Market", "reason: no_gold names the amount and the fix building")
	t.ok(BuildSort.reason_text("no_relics", row, st, bv, vcfg) == "needs 2 relics: raid a fort", "reason: no_relics sends you to raid a fort")
	t.ok(BuildSort.reason_text("no_bone", {"cost": {"bone": 60.0}}, {"bone": 30.0, "count": {"bone_mill": 1}}, bv, vcfg) == "needs 30 bone: staff the Bone Mill",
		"reason: a built fix building is staffed, not built")
	t.ok(BuildSort.reason_text("no_relics", {"cost": {"relics": 1}}, {"relics": 0.0}, bv, vcfg) == "needs 1 relic: raid a fort", "reason: one relic is singular")
	var tier_st := {"next_tier": {"tier": "village", "have": 4, "need": 6, "missing": ["house", "well"]}}
	t.ok(BuildSort.reason_text("needs_tier", row, tier_st, bv, vcfg) == "needs Village tier (4/6 buildings, missing: House, Well)", "reason: needs_tier shows the tier progress")
	t.ok(BuildSort.reason_text("needs_tier", row, {"next_tier": {"tier": "town"}}, bv, vcfg) == "needs Village tier", "reason: a tier further off has no progress")
	var fx := {"count": {"market": 0, "bone_mill": 1}, "placeable": {"market": true, "bone_mill": true, "house": true}}
	t.ok(BuildSort.fix_target("no_gold", row, fx, vcfg) == "market", "fix: a placeable, unbuilt fix building is clickable")
	t.ok(BuildSort.fix_target("no_bone", row, fx, vcfg) == "", "fix: a built fix building is not offered again")
	t.ok(BuildSort.fix_target("no_relics", row, fx, vcfg) == "", "fix: relics have no fix building")
	t.ok(BuildSort.fix_target("needs_building", row, fx, vcfg) == "house", "fix: a missing required building is clickable when placeable")
	t.ok(BuildSort.fix_target("no_gold", row, {"count": {}, "placeable": {"market": false}}, vcfg) == "", "fix: not clickable when it can't be placed")
	for k in vcfg["shortage_fix"]:
		t.ok(String(vcfg["shortage_fix"][k]) == "" or bv.has(vcfg["shortage_fix"][k]), "fix: shortage_fix.%s names a real building" % k)
	t.ok(BuildSort.reason_text("never_heard_of_it", row, st, bv, vcfg) == vcfg["reasons"]["_unknown"], "reason: an unknown id gets the fallback, not the raw id")
	t.ok(BuildSort.reason_text("no_gold", {}, st, bv, vcfg) == "needs 0 gold: build a Market", "reason: an empty row still formats")
	# Every reason the real catalog gives on any fixture reads as text.
	for r in day1["catalog"]["buildings"]:
		if String(r["reason"]) != "":
			var txt: String = BuildSort.reason_text(r["reason"], r, BuildSort.stocks(day1), bv, vcfg)
			t.ok(not txt.contains("_"), "reason: day1 %s: %s" % [r["building_id"], txt])
	var parts: Array = BuildSort.cost_parts({"gold": 40.0, "bone": 10.0, "relics": 0}, {"gold": 30.0, "bone": 10.0, "relics": 0.0})
	t.ok(parts[0]["short"] and parts[0]["text"] == "! 40 gold", "cost parts: an unaffordable part carries a text marker")
	t.ok(not parts[1]["short"] and parts[1]["text"] == "10 bone" and parts[2]["text"] == "0 relics", "cost parts: affordable parts are plain upright counts")
	t.ok(BuildSort.shortfall_reason({"gold": 5.0, "bone": 9.0}, {"gold": 5.0, "bone": 1.0}) == "no_bone", "shortfall: the first short part")


func _build_lot_refusal() -> void:
	var row := {"lot_size": 2}
	t.ok(BuildSort.lot_refusal({}, row) == "unknown_lot", "lot refusal: unknown lot")
	t.ok(BuildSort.lot_refusal({"unlocked": false, "size": 2, "building_id": ""}, row) == "lot_locked", "lot refusal: locked")
	t.ok(BuildSort.lot_refusal({"unlocked": true, "size": 2, "building_id": "house"}, row) == "lot_taken", "lot refusal: taken")
	t.ok(BuildSort.lot_refusal({"unlocked": true, "size": 1, "building_id": ""}, row) == "lot_too_small", "lot refusal: too small")


func _qctx(gold := 100.0, bone := 100.0, relics := 0.0, gold_cap := -1.0) -> Dictionary:
	return {"gold": gold, "bone": bone, "relics": relics, "gold_cap": gold_cap, "bone_cap": -1.0, "gates": vcfg["gate_reasons"],
		"catalog": {
			"house": _row("house", true, "", ["lot-05", "lot-06"]),
			"inn": _row("inn", false, "needs_tier", []),
			"well": _row("well", true, "", ["lot-07"]),
		},
		"built": {"lot-01": {"building_id": "crypt", "level": 1, "max_level": 3, "state": "active"},
			"lot-02": {"building_id": "house", "level": 3, "max_level": 3, "state": "active"}}}


func _entry(bid: String, lot: String, gold := 10.0, upgrade := false) -> Dictionary:
	return {"building_id": bid, "lot_id": lot, "upgrade": upgrade, "level": 1, "cost": {"gold": gold, "bone": 0.0, "relics": 0}}


func _statuses(q: TownStandins.BuildQueue) -> Array:
	return q.entries.map(func(e): return e["status"])


func _build_queue(day1: Dictionary) -> void:
	var no_q: Dictionary = (day1["town"] as Dictionary).duplicate(true)
	no_q.erase("queue")
	t.ok(TownStandins.queue_is_standin(no_q), "queue: a town view without `queue` uses the stand-in")
	t.ok(not TownStandins.queue_is_standin({"queue": []}), "queue: a real `queue` key switches the stand-in off")
	t.ok(not TownStandins.queue_is_standin(day1["town"]), "queue: the live view carries `queue` (E2b-2 T3.2), so the stand-in is off")
	var local: Array = [{"building_id": "house", "lot_id": "lot-05"}]
	t.ok(TownStandins.queue_entries(no_q, local) == local, "queue: without a `queue` key the local entries are shown")
	var real_q: Array = [{"building_id": "inn", "lot_id": "lot-06"}]
	t.ok(TownStandins.queue_entries({"queue": real_q}, local) == real_q and TownStandins.queue_entries({"queue": []}, local).is_empty(),
		"queue: with a real `queue` key (even empty) the view's entries are shown, never the local ones")
	var pb := FileAccess.get_file_as_string("res://scripts/town/panel_build.gd")  # panel_build needs the Game autoload: read its source
	var bs := FileAccess.get_file_as_string("res://scripts/town/build_sort.gd")  # the queue click sends through BuildSort.send_queue
	t.ok(pb.contains("BuildSort.send_queue(Game.state,") and bs.contains("gs.cmd_queue_build(") and pb.contains("Game.state.cmd_unqueue(")
		and pb.contains("Game.state.cmd_reorder_queue(") and not vcfg["queue_text"].has("no_commands"),
		"queue: with the view's queue the Build tab calls cmd_queue_build, cmd_unqueue and cmd_reorder_queue (no 'coming' text)")
	var q := TownStandins.BuildQueue.new(3, vcfg["cap_buildings"])
	var ctx := _qctx()
	var r := q.add(_entry("house", "lot-05"), ctx)
	t.ok(r["ok"] and r["index"] == 0 and r["cap_building"] == "", "queue: add returns ok, the index and no cap building")
	t.ok(_statuses(q) == ["next"], "queue: an affordable head is `next`")
	for k in ["building_id", "lot_id", "upgrade", "level", "cost", "status", "reason"]:
		t.ok(q.entries[0].has(k), "queue: entry has `%s` (api-request #3 shape)" % k)
	# Affordability holds the queue: the head waits for funds, everything behind it stays queued.
	ctx = _qctx(5.0)
	q.add(_entry("well", "lot-07"), ctx)
	t.ok(_statuses(q) == ["waiting_funds", "queued"], "queue: an unaffordable head holds the queue (%s)" % str(_statuses(q)))
	t.ok(q.entries[0]["reason"] == "no_gold", "queue: the held head says which store is short")
	# Gate-blocked heads are skipped and the next entry takes the head.
	var q2 := TownStandins.BuildQueue.new(8, vcfg["cap_buildings"])
	q2.add(_entry("house", "lot-05"), _qctx())
	q2.add(_entry("well", "lot-07"), _qctx())
	var gated := _qctx()
	gated["catalog"]["house"] = _row("house", false, "needs_tier", [])
	q2.evaluate(gated)
	t.ok(_statuses(q2) == ["skipped_gate", "next"] and q2.entries[0]["reason"] == "needs_tier", "queue: a gate-blocked head is skipped, the next one runs (%s)" % str(_statuses(q2)))
	q2.evaluate(_qctx(5.0))
	t.ok(_statuses(q2) == ["waiting_funds", "queued"], "queue: when the gate clears the head takes its place again")
	var norelic := _qctx()
	q2.entries[0]["cost"]["relics"] = 2
	q2.evaluate(norelic)
	t.ok(_statuses(q2) == ["skipped_gate", "next"] and q2.entries[0]["reason"] == "no_relics", "queue: a relics shortfall is a gate (time can't earn relics)")
	q2.entries[0]["cost"]["relics"] = 0
	var taken := _qctx()
	taken["catalog"]["house"]["lots"] = ["lot-06"]
	q2.evaluate(taken)
	t.ok(q2.entries[0]["status"] == "skipped_gate" and q2.entries[0]["reason"] == "lot_taken", "queue: a lot taken since queueing is skipped")
	# Upgrades.
	var q3 := TownStandins.BuildQueue.new(8, vcfg["cap_buildings"])
	t.ok(q3.add(_entry("crypt", "lot-01", 50.0, true), _qctx())["ok"] and q3.entries[0]["status"] == "next", "queue: an upgrade queues against the built lot")
	q3.add(_entry("house", "lot-02", 50.0, true), _qctx())
	t.ok(q3.entries[1]["status"] == "skipped_gate" and q3.entries[1]["reason"] == "max_level", "queue: an upgrade at max level is skipped")
	# Refusals.
	var full := TownStandins.BuildQueue.new(1, {})
	full.add(_entry("house", "lot-05"), _qctx())
	t.ok(full.add(_entry("well", "lot-07"), _qctx())["reason"] == "queue_full", "queue: queue_full at max_len")
	var q4 := TownStandins.BuildQueue.new(8, vcfg["cap_buildings"])
	var rr := q4.add(_entry("house", "lot-05", 600.0), _qctx(100.0, 100.0, 0.0, 500.0))
	t.ok(not rr["ok"] and rr["reason"] == "cost_exceeds_cap" and rr["cap_building"] == vcfg["cap_buildings"]["gold"] and rr["store"] == "gold",
		"queue: a cost over the gold cap is refused and offers the cap building (%s)" % rr["cap_building"])
	t.ok(cfg["buildings_view"].has(rr["cap_building"]), "queue: the offered cap building is a real building")
	t.ok(q4.entries.is_empty(), "queue: a refused add queues nothing")
	t.ok(q4.add(_entry("house", "lot-05", 400.0), _qctx(100.0, 100.0, 0.0, 500.0))["ok"], "queue: a cost under the cap queues")
	t.ok(q4.add(_entry("well", "lot-07", 9999.0), _qctx())["ok"], "queue: cap -1 means no cap")
	t.ok(TownStandins.BuildQueue.new(8, {}).add(_entry("house", "lot-05", 600.0), _qctx(0.0, 0.0, 0.0, 500.0))["cap_building"] == "",
		"queue: no cap building named gives \"\"")
	t.ok(q4.add(_entry("inn", "lot-09"), _qctx())["reason"] == "needs_tier", "queue: a gate reason refuses at add")
	t.ok(q4.add(_entry("house", "lot-09"), _qctx())["reason"] == "lot_taken", "queue: a lot the catalog doesn't offer is refused")
	t.ok(q4.add(_entry("nonesuch", "lot-09"), _qctx())["reason"] == "unknown_building", "queue: an unknown building is refused")
	# Reorder / unqueue keep the indices consistent.
	var q5 := TownStandins.BuildQueue.new(8, {})
	for e in [["house", "lot-05"], ["well", "lot-07"], ["house", "lot-06"]]:
		q5.add(_entry(e[0], e[1]), _qctx())
	var lots := func() -> Array:
		return q5.entries.map(func(e): return e["lot_id"])
	t.ok(q5.reorder([2, 0, 1])["ok"] and lots.call() == ["lot-06", "lot-05", "lot-07"], "queue: reorder applies a permutation (%s)" % str(lots.call()))
	t.ok(q5.reorder([0, 0, 1])["reason"] == "bad_order" and q5.reorder([0, 1])["reason"] == "bad_order" and q5.reorder([0, 1, 3])["reason"] == "bad_order",
		"queue: reorder refuses a non-permutation")
	t.ok(lots.call() == ["lot-06", "lot-05", "lot-07"], "queue: a refused reorder changes nothing")
	t.ok(q5.move(2, -1)["ok"] and lots.call() == ["lot-06", "lot-07", "lot-05"], "queue: move up one")
	t.ok(q5.move(0, -1)["ok"] and lots.call() == ["lot-06", "lot-07", "lot-05"], "queue: move up at the top stays put")
	t.ok(q5.move(1, 5)["ok"] and lots.call() == ["lot-06", "lot-05", "lot-07"], "queue: move down clamps at the end")
	t.ok(q5.move(7, 1)["reason"] == "unknown_index", "queue: move of an unknown index")
	t.ok(q5.unqueue(0)["ok"] and lots.call() == ["lot-05", "lot-07"], "queue: unqueue removes and shifts the rest")
	t.ok(_statuses(q5) == ["next", "queued"], "queue: statuses follow the new head after an unqueue")
	t.ok(q5.unqueue(5)["reason"] == "unknown_index" and q5.unqueue(-1)["reason"] == "unknown_index", "queue: unqueue of an unknown index")
	t.ok(q5.entries.size() == 2, "queue: refused unqueues keep the list")
	# queue_context from real views.
	var qc := BuildSort.queue_context(day1, cfg["buildings"], vcfg)
	t.ok(qc["catalog"].size() == day1["catalog"]["buildings"].size() and qc["gold_cap"] == -1.0 or qc["gold_cap"] >= 0.0, "queue: context reads the catalog and the gold cap")
	t.ok(qc["built"].size() == day1["town"]["buildings"].size(), "queue: context lists the built lots")
	t.ok(cfg["buildings_view"].has(vcfg["cap_buildings"]["gold"]) and cfg["buildings_view"].has(vcfg["cap_buildings"]["bone"]),
		"queue: view.cap_buildings name real buildings")


func _build_inspect(day1: Dictionary, mid: Dictionary) -> void:
	var st := {"gold": 1000.0, "bone": 1000.0, "relics": 5.0}
	var bcfg: Dictionary = cfg["buildings"]
	var bv: Dictionary = cfg["buildings_view"]
	var house := {"lot_id": "lot-05", "building_id": "house", "level": 1, "state": "active", "progress": 1.0, "slots": 0,
		"staffed": 0.0, "foreman": "", "upkeep": {"gold": 0.01, "bone": 0.0}}
	var i: Dictionary = BuildSort.inspect(house, st, bcfg, bv, vcfg)
	t.ok(i["label"] == "House" and i["level"] == 1 and i["max_level"] == int(bcfg["house"]["max_level"]) and i["state_text"] == "working", "inspect: label, level of max, state")
	t.ok(i["upgrade"]["enabled"] and i["upgrade"]["cost"] == bcfg["house"]["level_costs"][0] and i["upgrade"]["level"] == 2,
		"inspect: upgrade cost is level_costs[level - 1]")
	t.ok(not i["cancel"]["visible"] and i["demolish_visible"], "inspect: an active house can be demolished, not cancelled")
	house["level"] = int(bcfg["house"]["max_level"])
	i = BuildSort.inspect(house, st, bcfg, bv, vcfg)
	t.ok(not i["upgrade"]["enabled"] and i["upgrade"]["reason"] == "max_level", "inspect: no upgrade at max level")
	house["level"] = 2
	i = BuildSort.inspect(house, {"gold": 10.0, "bone": 1000.0, "relics": 0.0}, bcfg, bv, vcfg)
	t.ok(not i["upgrade"]["enabled"] and i["upgrade"]["reason"] == "no_gold", "inspect: an unaffordable upgrade says why")
	house["state"] = "constructing"
	house["progress"] = 0.4
	i = BuildSort.inspect(house, st, bcfg, bv, vcfg)
	t.ok(i["upgrade"]["reason"] == "under_construction" and i["cancel"]["visible"] and i["state_text"] == "under construction, 40% done",
		"inspect: constructing blocks upgrade and offers cancel")
	t.ok(i["cancel"]["refund"] == bcfg["house"]["level_costs"][1], "inspect: cancelling an upgrade refunds the upgrade's cost")
	house["state"] = "unpaid"  # cmd_upgrade refuses an idled building
	house["level"] = 1
	i = BuildSort.inspect(house, st, bcfg, bv, vcfg)
	t.ok(not i["upgrade"]["enabled"] and i["upgrade"]["reason"] == "unpaid" and not i["cancel"]["visible"],
		"inspect: an unpaid building cannot be upgraded (cmd_upgrade refuses it)")
	house["state"] = "constructing"
	house["level"] = 0
	i = BuildSort.inspect(house, st, bcfg, bv, vcfg)
	t.ok(i["cancel"]["refund"] == bcfg["house"]["cost"], "inspect: cancelling a first build refunds the build cost")
	var crypt := {"lot_id": "lot-01", "building_id": "crypt", "level": 1, "state": "active", "slots": 0, "staffed": 0.0, "foreman": "u4",
		"upkeep": {"gold": 0.0, "bone": 0.0}}
	i = BuildSort.inspect(crypt, st, bcfg, bv, vcfg)
	t.ok(not i["demolish_visible"], "inspect: the crypt is protected, no demolish")
	t.ok(i["foreman"] == "foreman u4", "inspect: the foreman shows")
	i = BuildSort.inspect(crypt, {"gold": 0.0, "bone": 0.0, "foreman_names": {"u4": "Old Gristle"}, "max_level": {"crypt": 5}}, bcfg, bv, vcfg)
	t.ok(i["foreman"] == "foreman Old Gristle" and i["max_level"] == 5, "inspect: the foreman by name and max_level from the catalog row")
	t.ok(BuildSort.stocks({"big_undead": {"big_undead": [{"uid": "u4", "name": "Old Gristle"}]},
		"catalog": {"buildings": [{"building_id": "crypt", "max_level": 7}]}})["foreman_names"] == {"u4": "Old Gristle"},
		"inspect: stocks() maps big-undead uids to names")
	for b in mid["town"]["buildings"]:
		var s: Dictionary = BuildSort.inspect(b, BuildSort.stocks(mid), bcfg, bv, vcfg)
		t.ok(s["label"] != "" and s["state_text"] != "" and s["staffing"] != "", "inspect: midgame %s reads fully" % b["building_id"])


func _build_unique(day1: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var uniques: Array = []
	for bid in bv:
		if bool(bv[bid].get("unique", false)):
			uniques.append(bid)
	t.ok(uniques == ["crypt"], "unique: only the crypt is marked unique (%s)" % str(uniques))
	var crypt := _row("crypt", false, "no_lot")
	crypt["count"] = 1
	var ids := func(items: Array) -> Array:
		return items.map(func(i): return i["row"]["building_id"])
	t.ok(ids.call(BuildSort.sort_rows([crypt, _row("house", true, "", ["lot-05"])], [], bv, vcfg)) == ["house"],
		"unique: a built crypt is never offered")
	crypt["count"] = 0
	t.ok(ids.call(BuildSort.sort_rows([crypt], [], bv, vcfg)) == ["crypt"], "unique: an unbuilt unique building is still offered")
	var house := _row("house", true, "", ["lot-05"])
	house["count"] = 3
	t.ok(ids.call(BuildSort.sort_rows([house], [], bv, vcfg)) == ["house"], "unique: a built non-unique building stays")
	for it in BuildSort.sort_rows(day1["catalog"]["buildings"], [], bv, vcfg):
		t.ok(it["row"]["building_id"] != "crypt" or int(it["row"]["count"]) == 0, "unique: day1 catalog never lists a built crypt")


func _build_eta(day1: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var row := {"building_id": "house", "cost": {"gold": 10.0, "bone": 40.0, "relics": 0}, "lot_size": 1,
		"requires": {"tier": "hamlet", "blueprint": "", "building": ""}}
	var st := {"gold": 100.0, "bone": 12.0, "relics": 0.0, "count": {}, "rates": {"gold": 0.5, "bone": 0.15}}
	t.ok(BuildSort.reason_text("no_bone", row, st, bv, vcfg) == "needs 28 more bone, about 3 min at +0.15/s",
		"eta: 28 short at +0.15/s is about 3 min (%s)" % BuildSort.reason_text("no_bone", row, st, bv, vcfg))
	st["rates"]["bone"] = 2.0
	t.ok(BuildSort.reason_text("no_bone", row, st, bv, vcfg) == "needs 28 more bone, about 14 s at +2.00/s", "eta: under 90 s reads in seconds")
	st["rates"]["bone"] = 0.002
	t.ok(BuildSort.reason_text("no_bone", row, st, bv, vcfg) == "needs 28 more bone, about 3.9 h at +0.00/s", "eta: long waits read in hours (%s)" % BuildSort.reason_text("no_bone", row, st, bv, vcfg))
	t.ok(BuildSort.fmt_eta(7200.0, vcfg) == "2 h" and BuildSort.fmt_eta(5399.0, vcfg) == "90 min" and BuildSort.fmt_eta(89.0, vcfg) == "89 s" and BuildSort.fmt_eta(90.0, vcfg) == "2 min",
		"eta: duration formats and their thresholds")
	for r in [0.0, -0.2]:
		st["rates"]["bone"] = r
		var txt := BuildSort.reason_text("no_bone", row, st, bv, vcfg)
		t.ok(txt == "bone isn't flowing: build a Bone Mill", "eta: net rate %.1f gives the fix, not an estimate (%s)" % [r, txt])
	st["count"] = {"bone_mill": 1}
	t.ok(BuildSort.reason_text("no_bone", row, st, bv, vcfg) == "bone isn't flowing: staff the Bone Mill", "eta: a built mill is staffed instead")
	var grow := {"building_id": "house", "cost": {"gold": 130.0, "bone": 0.0, "relics": 0}}
	t.ok(BuildSort.reason_text("no_gold", grow, st, bv, vcfg) == "needs 30 more gold, about 60 s at +0.50/s", "eta: gold uses its own rate")
	t.ok(BuildSort.reason_text("no_relics", {"cost": {"relics": 2}}, st, bv, vcfg) == "needs 2 relics: raid a fort", "eta: relics never get an estimate")
	# The live views: the Build tab's stocks carry the hud's net rates.
	var live := BuildSort.stocks(day1)
	t.ok(live.has("rates") and live["rates"].has("gold") and live["rates"].has("bone"), "eta: stocks() carries the hud net rates")
	for r in day1["catalog"]["buildings"]:
		if String(r["reason"]) in ["no_gold", "no_bone"]:
			var txt: String = BuildSort.reason_text(r["reason"], r, live, bv, vcfg)
			t.ok(txt.contains("more") or txt.contains("flowing"), "eta: day1 %s: %s" % [r["building_id"], txt])
	# The inspector's upgrade and the queue read the same text.
	var q := {"building_id": "house", "lot_id": "lot-05", "upgrade": false, "level": 1, "cost": {"gold": 10.0, "bone": 40.0, "relics": 0},
		"status": "waiting_funds", "reason": "no_bone"}
	st["rates"]["bone"] = 0.15
	st["count"] = {}
	t.ok(BuildSort.entry_reason(q, {"house": row}, st, bv, vcfg) == "needs 28 more bone, about 3 min at +0.15/s", "eta: a waiting queue head shows the estimate")
	q["reason"] = ""
	t.ok(BuildSort.entry_reason(q, {}, st, bv, vcfg) == "", "eta: no reason, no text")
	var ins := BuildSort.inspect({"lot_id": "lot-05", "building_id": "house", "level": 1, "state": "active", "slots": 0, "staffed": 0.0,
		"upkeep": {}}, {"gold": 10.0, "bone": 1000.0, "relics": 0.0, "rates": {"gold": 0.5, "bone": 0.0}}, cfg["buildings"], bv, vcfg)
	t.ok(BuildSort.reason_text(String(ins["upgrade"]["reason"]), {"cost": ins["upgrade"]["cost"]}, {"gold": 10.0, "rates": {"gold": 0.5}}, bv, vcfg)
		== "needs 70 more gold, about 2 min at +0.50/s", "eta: an upgrade's shortfall gets the estimate")


func _build_benefit() -> void:
	for bid in cfg["buildings_view"]:  # the static line is words only: numbers come live from BuildSort.benefit
		var line := String(cfg["buildings_view"][bid].get("benefit", ""))
		var digits := RegEx.create_from_string("[0-9]")
		t.ok(digits.search(line) == null, "benefit: %s's static line has no frozen sim number (%s)" % [bid, line])
	var bv: Dictionary = cfg["buildings_view"]
	var bc: Dictionary = cfg["buildings"]
	var pit := BuildSort.benefit("raising_pit", {}, bc, bv, vcfg)
	t.ok(pit["rates"].is_empty() and not pit["now"], "benefit: E2a's pit effects ({pits}) carry no rate, no 'now' label (%s)" % str(pit["rates"]))
	t.ok(pit["plain"] == ["+1 raising pit", "2 pit jobs"], "benefit: jobs are plain text (%s)" % str(pit["plain"]))
	var house := BuildSort.benefit("house", {}, bc, bv, vcfg)
	t.ok(house["rates"].is_empty() and house["plain"] == ["+8 housing"], "benefit: a cap is plain text, not a rate (%s)" % str(house["plain"]))
	var inn := BuildSort.benefit("inn", {}, bc, bv, vcfg)
	t.ok(inn["rates"] == ["+0.02/s migrants"] and inn["plain"] == ["+20 housing"], "benefit: the inn's migrants rate and housing cap")
	t.ok(BuildSort.benefit("guildhall", {}, bc, bv, vcfg)["plain"] == ["+1 stance slot"], "benefit: stance slots")
	t.ok(BuildSort.benefit("crypt", {}, bc, bv, vcfg)["plain"] == [bv["crypt"]["benefit"]], "benefit: the crypt has no effects keys now (E2a), so its view line says the big-undead cap")
	var synth := bc.duplicate(true)
	synth["crypt"]["effects"] = {"big_undead_cap": 1}
	t.ok(BuildSort.benefit("crypt", {}, synth, bv, vcfg)["plain"] == ["+1 big undead cap"], "benefit: a big_undead_cap effect is plain text")
	t.ok(BuildSort.benefit("plaza", {}, bc, bv, vcfg)["plain"] == [bv["plaza"]["benefit"]], "benefit: no recognised effects or jobs falls back to the view line")
	t.ok(BuildSort.benefit("market", {}, bc, bv, vcfg)["plain"] == ["2 stall jobs"], "benefit: a job building says its jobs")
	var proj := BuildSort.benefit("raising_pit", {"projected": {"mint": 3.0, "gold": -0.05}}, bc, bv, vcfg)
	t.ok(proj["now"] and proj["rates"] == ["+3.00/s mint now", "−0.05/s gold now"], "benefit: projected rates replace the stand-in and say 'now' (%s)" % str(proj["rates"]))
	t.ok(proj["plain"] == ["+1 raising pit", "2 pit jobs"], "benefit: with projected, jobs and caps stay as plain text")
	var hp := BuildSort.benefit("house", {"projected": {}}, bc, bv, vcfg)
	t.ok(hp["now"] and hp["rates"].is_empty() and hp["plain"] == ["+8 housing"], "benefit: an empty projected shows no rate but keeps the cap text")
	t.ok(BuildSort.rate_texts({"gold": 0.3, "bone": 0.0}, vcfg) == ["+0.30/s gold now"], "benefit: zero changes are left out of upgrade_projected")
	var ins := BuildSort.inspect({"lot_id": "lot-05", "building_id": "house", "level": 1, "state": "active", "slots": 0, "staffed": 0.0,
		"upkeep": {}, "upgrade_projected": {"gold": 0.1}}, {"gold": 1000.0, "bone": 1000.0}, bc, bv, vcfg)
	t.ok(ins["upgrade_projected"] == {"gold": 0.1}, "benefit: the inspector passes upgrade_projected through")


func _build_suggest(day1: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var rows := [_row("market", false, "no_gold"), _row("house", true, "", ["lot-09", "lot-05"]), _row("well", true, "", ["lot-06"])]
	var items: Array = BuildSort.sort_rows(rows, [], bv, vcfg)
	var s: Dictionary = BuildSort.suggest(items, bv)
	t.ok(s["building_id"] == "house" and s["label"] == "House" and s["lots"] == ["lot-09", "lot-05"], "suggest: the top buildable row of the sort")
	items = BuildSort.sort_rows(rows, [{"id": "morale", "chip": "x", "serves": ["morale"]}], bv, vcfg)
	t.ok(BuildSort.suggest(items, bv)["building_id"] == "well", "suggest: a buildable row serving a live need leads")
	t.ok(BuildSort.suggest(BuildSort.sort_rows([_row("market", false, "no_gold"), _row("inn", false, "needs_tier")], [], bv, vcfg), bv).is_empty(),
		"suggest: nothing buildable gives no suggestion")
	t.ok(BuildSort.suggest(BuildSort.sort_rows([_row("house", true, "", [])], [], bv, vcfg), bv).is_empty(), "suggest: a row with no free lot is no suggestion")
	t.ok(BuildSort.suggest([], bv).is_empty(), "suggest: empty catalog")
	t.ok(BuildSort.nearest_lot(["lot-09", "lot-05"], {"lot-09": 3.0, "lot-05": 1.0}) == "lot-05", "suggest: the lot nearest the crypt")
	t.ok(BuildSort.nearest_lot(["lot-09", "lot-05"], {"lot-09": 2.0, "lot-05": 2.0}) == "lot-09", "suggest: ties keep the first listed lot")
	t.ok(BuildSort.nearest_lot(["lot-09", "lot-05"], {}) == "lot-09" and BuildSort.nearest_lot([], {}) == "", "suggest: unknown distances keep the first; none gives \"\"")
	t.ok(BuildSort.nearest_lot(["lot-23", "lot-09"], {"lot-23": 1.0, "lot-09": 5.0}, {"lot-23": 3, "lot-09": 1}) == "lot-09",
		"suggest: the smallest free lot first, so a 1-lot building leaves the 3-lot for Walls")
	t.ok(BuildSort.nearest_lot(["lot-09", "lot-05"], {"lot-09": 3.0, "lot-05": 1.0}, {"lot-09": 1, "lot-05": 1}) == "lot-05",
		"suggest: equal sizes fall back to the nearest")
	var m := _model()
	m.update(day1, VIEW_RECT)
	var hops := {}
	for l in m.lots:
		hops[l["id"]] = l["hops"]
	var real: Dictionary = BuildSort.suggest(BuildSort.sort_rows(day1["catalog"]["buildings"], BuildSort.needs(day1, FORTS, vcfg), bv, vcfg), bv)
	var any := false
	for r in day1["catalog"]["buildings"]:
		any = any or bool(r["can_build"])
	t.ok(real.is_empty() != any, "suggest: day1 has a suggestion exactly when something is buildable (%s)" % str(real))
	if not real.is_empty():
		var lot := BuildSort.nearest_lot(real["lots"], hops)
		for l in real["lots"]:
			t.ok(float(hops[lot]) <= float(hops[l]), "suggest: day1 lot %s is nearest the crypt among %s" % [lot, str(real["lots"])])


func _build_ghosts(day1: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var catalog := {}
	for r in day1["catalog"]["buildings"]:
		catalog[String(r["building_id"])] = r
	var q := TownStandins.BuildQueue.new(8, vcfg["cap_buildings"])
	var ctx := BuildSort.queue_context(day1, cfg["buildings"], vcfg)
	# A funds-blocked head, a gated entry and a plain queued entry (the --town-queue seed).
	q.entries = [_entry("house", "lot-05", 9999.0), _entry("inn", "lot-06"), _entry("well", "lot-07")]
	q.entries[0]["cost"] = {"gold": 9999.0, "bone": 0.0, "relics": 0}
	q.evaluate(ctx)
	var st := BuildSort.stocks(day1)
	var g: Array = BuildSort.ghosts(q.entries, ctx["catalog"], st, bv, vcfg)
	t.ok(g.size() == 3, "ghosts: one per queue entry")
	t.ok(g.map(func(x): return x["number"]) == [1, 2, 3] and g.map(func(x): return x["lot_id"]) == ["lot-05", "lot-06", "lot-07"],
		"ghosts: numbers are the queue positions, on the entry's lot")
	t.ok(g.map(func(x): return x["shape"]) == ["hold", "plain", "plain"] and g.map(func(x): return x["status"]) == ["waiting_funds", "skipped_gate", "queued"],
		"ghosts: a waiting head holds; a gated entry waits in its place, plain; the rest are plain (%s)" % str(g.map(func(x): return x["shape"])))
	t.ok((g[0]["text"].begins_with("needs ") or g[0]["text"].contains("isn't flowing")) and g[1]["text"] == "queued: waits for Village",
		"ghosts: hover text is the shortage (%s) and the gate (%s)" % [g[0]["text"], g[1]["text"]])
	t.ok(g[2]["text"] == "", "ghosts: a plain queued entry has no hover text")
	q.entries = [_entry("well", "lot-07")]
	var rich := ctx.duplicate()
	rich["gold"] = 1000.0
	rich["bone"] = 1000.0
	q.evaluate(rich)
	t.ok(BuildSort.ghosts(q.entries, rich["catalog"], st, bv, vcfg)[0]["shape"] == "ring", "ghosts: a head that can be paid for is the solid ring")
	var up := _entry("house", "lot-05", 10.0, true)
	up["level"] = 2
	var gu: Array = BuildSort.ghosts([up], {}, st, bv, vcfg)
	t.ok(gu[0]["upgrade"] and gu[0]["level"] == 2, "ghosts: an upgrade is flagged (drawn as a small +1 over the building)")
	# Canvas positions come from the model: the footprint of the queued building, a ring inside the lot.
	var m := _model()
	m.update(day1, VIEW_RECT)
	var gl: Array = m.ghost_layout(g)
	t.ok(gl.size() == 3, "ghosts: layout keeps every ghost on a known lot")
	for e in gl:
		var lot: Dictionary = m.lot(e["lot_id"])
		t.ok((lot["rect"] as Rect2).grow(0.5).encloses(e["rect"]), "ghosts: %s's footprint sits inside its lot" % e["lot_id"])
		t.ok((lot["rect"] as Rect2).has_point(e["ring"]), "ghosts: %s's number ring sits on its lot" % e["lot_id"])
	t.ok(m.ghost_layout([{"lot_id": "lot-99", "building_id": "house"}]).is_empty(), "ghosts: an unknown lot is dropped")
	t.ok(BuildSort.ghosts([], {}, st, bv, vcfg).is_empty(), "ghosts: an empty queue draws nothing")


func _build_chips() -> void:
	var c: Dictionary = vcfg["needs"]["chips"]
	t.ok(String(c["warden_at"]).contains("for the warden at {fort}") and String(c["warden_at"]).contains("big undead and quality"), "chips: the warden chip says what it is for")
	t.ok(c["gold"] == "gold is falling" and c["housing"] == "no room for more living" and c["tithe"] == "tithe wave on {fort}", "chips: gold, housing and tithe read in plain words")
	for k in c:
		t.ok(not String(c[k]).contains("_") and String(c[k]) != "", "chips: %s has no raw ids" % k)


func _build_caps(day1: Dictionary) -> void:
	t.ok(BuildSort.fill(50.0, 200.0) == 0.25, "caps: stock over cap")
	t.ok(BuildSort.fill(50.0, -1.0) == -1.0, "caps: cap -1 means no cap (-1)")
	t.ok(BuildSort.fill(500.0, 200.0) == 1.0 and BuildSort.fill(-3.0, 200.0) == 0.0, "caps: fill clamps to 0..1")
	t.ok(BuildSort.fill(5.0, 0.0) == 1.0, "caps: a zero cap is full")
	t.ok(BuildSort.hud_rate(day1["hud"], "gold").has("cap") and BuildSort.hud_rate(day1["hud"], "nonesuch").is_empty(), "caps: hud rates carry gold's cap")
	var bar: Dictionary = vcfg["cap_bar"]
	t.ok(not bar.has("ink") and not (vcfg["hud"] as Dictionary).has("caps_bar"), "caps: the unused cap_bar.ink and hud.caps_bar keys are gone")
	for k in ["gold", "bone"]:  # the fills still read at 3:1 (the ink comes from view.hud.ink)
		var ink := String(vcfg["hud"]["ink"][k])
		t.ok(Palette.has(ink) and TownModel.contrast(Palette.c(ink), Palette.c("ground")) >= 3.0, "caps: the %s fill reads at 3:1 on ground" % k)
	t.ok(String(vcfg["hud"]["ink"]["gold"]) == "living" and String(vcfg["hud"]["ink"]["bone"]) == "dead", "caps: gold is living-orange, bone is dead matter")


func _lot_hit(day1: Dictionary) -> void:
	var m := _model()
	m.update(day1, VIEW_RECT)
	for l in m.lots:
		t.ok(m.lot_at((l["rect"] as Rect2).get_center(), 44.0) == l["id"], "hit: the centre of %s hits %s" % [l["id"], l["id"]])
	t.ok(m.lot_at(Vector2(-500, -500), 44.0) == "", "hit: far from every lot hits nothing")
	# At a small view the lots shrink under 44 px; their hit boxes still reach 44 px.
	var tiny := _model()
	tiny.update(day1, Rect2(Vector2.ZERO, Vector2(260, 207)))
	var r0: Rect2 = tiny.lots[0]["rect"]
	t.ok(r0.size.x < 44.0 and r0.size.y < 44.0, "hit: at a small view lot-01 is under 44 px (%.0f x %.0f)" % [r0.size.x, r0.size.y])
	var off := Vector2(21.0, 0.0)
	t.ok(not r0.has_point(r0.get_center() + off), "hit: a click 21 px off its centre is outside the drawn lot")
	t.ok(tiny.lot_at(r0.get_center() + off, 44.0) == "lot-01", "hit: ... but still lands on it with the 44 px box")
	t.ok(tiny.lot_at(r0.get_center() + off, 0.0) != "lot-01", "hit: ... and misses without the grown box")
	# Overlapping grown boxes go to the nearer centre; a point inside a real rect always wins.
	var a: Rect2 = tiny.lots[0]["rect"]
	for l in tiny.lots.slice(1):
		var b: Rect2 = l["rect"]
		var mid := (a.get_center() + b.get_center()) * 0.5
		if a.get_center().distance_to(b.get_center()) < 44.0 and not a.has_point(mid) and not b.has_point(mid):
			var got: String = tiny.lot_at(a.get_center().lerp(b.get_center(), 0.4), 44.0)
			t.ok(got == "lot-01", "hit: between two close lots the nearer centre wins")


# ------------------------------------------------------- legibility (2c) ----
## `views` with the idle workers and the living set.
func _crowd(views: Dictionary, idle: float, living: float) -> Dictionary:
	var v: Dictionary = views.duplicate(true)
	v["town"]["workers"]["idle"] = idle
	v["town"]["living"] = living
	return v


## Workers in `town`'s jobs, rounded as the sampler rounds them.
func _staffed(town: Dictionary) -> int:
	var n := 0
	for j in town["jobs"]:
		n += roundi(float(j["staffed"]))
	return n


func _budget(day1: Dictionary) -> void:
	var cap := int(vcfg["max_agents"])
	var fl := int(vcfg["min_living_agents"])
	var staffed := _staffed(day1["town"])
	t.ok(cap >= 100 and fl >= 1 and fl < cap, "budget: max_agents %d with a living floor of %d" % [cap, fl])
	# the undead keep one stroke per worker right up to their share (the budget less the living floor)
	var v := _crowd(day1, float(cap - fl - staffed), 100.0)
	var a: TownAgents = _agents(v)[1]
	t.ok(a.undead_scale == 1 and _counts_match(a, v["town"]) and a.undead.size() == cap - fl,
		"budget: %d workers, one stroke each (%d)" % [cap - fl, a.undead.size()])
	t.ok(a.living_scale == ceili(100.0 / fl) and a.living_count() == roundi(100.0 / a.living_scale) and a.living_count() <= fl,
		"budget: 100 living get what's left, their floor of %d (1 stroke = %d, %d strokes)" % [fl, a.living_scale, a.living_count()])
	t.ok(a.undead.size() + a.living_count() <= cap, "budget: all strokes stay within max_agents (%d)" % (a.undead.size() + a.living_count()))
	# the living are thinned first: 60 workers keep 60 strokes; 200 living get what is left, and no
	# more than living_ratio_max of the undead strokes
	v = _crowd(day1, float(60 - staffed), 200.0)
	a = _agents(v)[1]
	var allowed := mini(cap - 60, maxi(fl, floori(float(vcfg["living_ratio_max"]) * 60.0)))
	t.ok(a.undead_scale == 1 and _counts_match(a, v["town"]) and a.undead.size() == 60, "budget: 60 workers, 60 strokes")
	t.ok(a.living_scale == ceili(200.0 / allowed) and a.living_count() == roundi(200.0 / a.living_scale) and a.living_count() <= allowed,
		"budget: 200 living thinned into %d strokes (1 stroke = %d, %d strokes)" % [allowed, a.living_scale, a.living_count()])
	# with the ratio cap lifted, the shared budget alone leaves the living cap - 60 strokes
	a = _agents(v, {}, _one_to_one())[1]
	t.ok(a.living_scale == ceili(200.0 / (cap - 60)) and a.living_count() <= cap - 60,
		"budget: without the ratio cap 200 living share the %d strokes left (1 stroke = %d)" % [cap - 60, a.living_scale])
	# far past the budget the undead are sampled too, and the living keep their floor
	v = _crowd(day1, 1000.0, 300.0)
	a = _agents(v)[1]
	var und := a.undead.size()
	var total := 1000 + staffed
	t.ok(a.undead_scale == ceili(float(total) / float(cap - fl)) and und <= cap - fl + v["town"]["jobs"].size(),
		"budget: %d workers sampled into the undead share (%d strokes, 1 stroke = %d)" % [total, und, a.undead_scale])
	t.ok(a.living_scale == ceili(300.0 / maxf(cap - und, fl)) and a.living_count() >= fl and und + a.living_count() <= cap,
		"budget: the living take what is left, at least their floor (%d strokes, 1 stroke = %d)" % [a.living_count(), a.living_scale])
	# no living: the undead may use the whole budget; a few living reserve only what they need
	v = _crowd(day1, float(cap - staffed), 0.0)
	a = _agents(v)[1]
	t.ok(a.undead_scale == 1 and a.undead.size() == cap and a.living_count() == 0, "budget: no living, the undead use all %d strokes" % cap)
	v = _crowd(day1, float(cap - 3 - staffed), 3.0)
	a = _agents(v)[1]
	t.ok(a.undead_scale == 1 and a.undead.size() == cap - 3 and a.living_count() == 3,
		"budget: 3 living reserve 3 strokes, not the whole floor (%d undead, %d living)" % [a.undead.size(), a.living_count()])
	# day1's workers fit: one stroke each
	a = _agents(day1)[1]
	t.ok(a.undead_scale == 1, "budget: day1's workers fit the budget, 1 stroke = 1")


## Undead stay the visible majority: living strokes <= max(min_living_agents, floor(living_ratio_max x
## undead strokes)), sampled by k = ceil(living / allowed), on every real fixture and the demo.
func _ratio(views: Array, names: Array) -> void:
	var r := float(vcfg["living_ratio_max"])
	var fl := int(vcfg["min_living_agents"])
	t.ok(r > 0.0 and r < 1.0, "ratio: living_ratio_max %.2f keeps the living under the undead" % r)
	for i in views.size():
		var v: Dictionary = views[i]
		var a: TownAgents = _agents(v)[1]
		var u := a.undead.size()
		var l := a.living_count()
		var people := float(v["town"]["living"])
		var allowed := mini(maxi(fl, floori(r * float(u))), int(vcfg["max_agents"]) - u)
		var k := ceili(people / float(allowed) - 1e-9) if people > float(allowed) else 1
		t.ok(l <= maxi(fl, floori(r * float(u))) and a.living_scale == k and l == roundi(people / float(k)),
			"ratio: %s draws %d undead vs %d living strokes (%.0f living, 1 orange stroke = %d)" % [names[i], u, l, people, k])
		t.ok(l < u, "ratio: on %s the undead are the majority (%d > %d)" % [names[i], u, l])


func _legend(pre: Dictionary) -> void:
	t.ok(TownAgents.legend_lines(1, 1, vcfg).is_empty(), "legend: nothing when every stroke is one")
	t.ok(TownAgents.legend_lines(1, 5, vcfg) == ["1 orange stroke = 5 living"], "legend: '1 orange stroke = 5 living'")
	t.ok(TownAgents.legend_lines(3, 2, vcfg) == ["1 green stroke = 3 undead", "1 orange stroke = 2 living"],
		"legend: the undead's scale too when it is over 1")
	var a: TownAgents = _agents(pre)[1]
	t.ok(a.living_scale > 1 and a.legend() == ["1 orange stroke = %d living" % a.living_scale],
		"legend: pre_vei reads %s" % str(a.legend()))
	t.ok(int(vcfg["legend"]["px"]) >= 14, "legend: text at least 14 px (clarity round 3: the key was too small to read)")
	var ink := String(vcfg["legend"].get("ink", ""))
	t.ok(Palette.has(ink) and TownModel.contrast(Palette.c(ink), Palette.c("ground")) >= 7.0,
		"legend: its ink '%s' reads at 7:1 or better on its ground plate (%.1f:1)" % [ink, TownModel.contrast(Palette.c(ink), Palette.c("ground")) if Palette.has(ink) else 0.0])


func _looks(day1: Dictionary, mid: Dictionary, demo: Dictionary) -> void:
	var cases := [
		["crypt", "active", 0, 0.0, "heart"],
		["crypt", "constructing", 0, 0.0, "constructing"],
		["market", "active", 2, 2.0, "staffed"],
		["market", "active", 2, 1.0, "staffed"],
		["market", "active", 2, 0.5, "staffed"],  # any staff works (the ticks and badge count whole hands)
		["market", "active", 2, 0.0, "unstaffed"],
		["bone_mill", "idle", 2, 0.0, "unstaffed"],
		["house", "idle", 0, 0.0, "unstaffed"],
		["guildhall", "unpaid", 0, 0.0, "unpaid"],
		["market", "unpaid", 2, 1.0, "unpaid"],
		["house", "active", 0, 0.0, "calm"],
		["walls", "active", 0, 0.0, "calm"],
		["house", "constructing", 0, 0.0, "constructing"],
		["market", "constructing", 0, 0.0, "constructing"],
	]
	for c in cases:
		var has_jobs := not (cfg["buildings"][c[0]]["jobs"] as Dictionary).is_empty()
		var got := TownModel.look_of(String(c[0]), String(c[1]), int(c[2]), has_jobs, float(c[3]))
		t.ok(got == c[4] and got in TownModel.LOOKS, "look: %s %s, %d slots, %.1f staffed reads %s (got %s)" % [c[0], c[1], c[2], c[3], c[4], got])
	var m := _model()
	m.update(demo, VIEW_RECT)
	var seen := {}
	var pulse_ok := true
	var blue_ok := true
	for l in m.lots:
		var b: Dictionary = l["building"]
		if b.is_empty():
			continue
		seen[b["look"]] = true
		var want: bool = b["look"] in ["staffed", "constructing", "heart"]  # the demo has Relish home
		pulse_ok = pulse_ok and b["pulse"] == want
		if b["ink"] == "town":
			blue_ok = blue_ok and (cfg["buildings"][b["building_id"]]["jobs"] as Dictionary).is_empty()
	t.ok(seen.size() == TownModel.LOOKS.size(), "look: the demo shows all %d looks: %s" % [TownModel.LOOKS.size(), str(seen.keys())])
	t.ok(pulse_ok, "look: only staffed, constructing and the crypt with Relish home pulse")
	t.ok(blue_ok, "look: town blue is only on buildings that need no staff")
	t.ok(m.lot("lot-18")["building"]["look"] == "unstaffed" and m.lot("lot-14")["building"]["look"] == "unpaid"
		and m.lot("lot-09")["building"]["look"] == "calm" and m.lot("lot-04")["building"]["look"] == "staffed",
		"look: the demo's idle mill, unpaid guildhall, calm house and staffed market")
	t.ok(not mid["town"]["relish_home"], "midgame_2flips: Relish is away")
	m.update(mid, VIEW_RECT)
	var crypt: Dictionary = m.lot("lot-01")["building"]
	t.ok(crypt["look"] == "heart" and crypt["ink"] == "undead" and not crypt["pulse"] and crypt["away"] == String(vcfg["status"]["heart_away"])
		and crypt["reveal"] == 1.0 and crypt["glow"] > 0.0,
		"look: Relish away, the crypt stays whole and lit in undead ink, holds still and says so")
	m.update(day1, VIEW_RECT)
	crypt = m.lot("lot-01")["building"]
	t.ok(day1["town"]["relish_home"] and crypt["look"] == "heart" and crypt["ink"] == "relish" and crypt["pulse"] and crypt["away"] == "",
		"look: Relish home, the crypt is violet and pulses")


func _badges(day1: Dictionary, mid: Dictionary, demo: Dictionary) -> void:
	t.ok(TownModel.badge_text(12, 15, vcfg) == "12 working · 3 short", "badge: 12 of 15 reads '12 working · 3 short'")
	t.ok(TownModel.badge_text(3, 3, vcfg) == "3 working", "badge: full reads '3 working'")
	t.ok(TownModel.badge_text(0, 3, vcfg) == "0 working · 3 short", "badge: empty reads '0 working · 3 short'")
	t.ok(TownModel.badge_text(4, 3, vcfg) == "4 working", "badge: never a negative shortfall")
	t.ok(TownModel.working_of(2.7) == 2 and TownModel.working_of(3.0) == 3 and TownModel.working_of(2.9999999) == 3,
		"badge: working is the floor of staffed, like the slot ticks")
	var m := _model()
	m.update(day1, VIEW_RECT)
	var all_ok := true
	var n := 0
	for b in day1["town"]["buildings"]:
		var e: Dictionary = m.lot(String(b["lot_id"]))["building"]
		if int(b["slots"]) > 0:
			n += 1
			var w := TownModel.working_of(float(b["staffed"]))
			all_ok = all_ok and e["badge"] == TownModel.badge_text(w, int(b["slots"]), vcfg) and e["working"] == w \
				and e["short"] == int(b["slots"]) - w
	t.ok(all_ok and n >= 3, "badge: each of day1's %d job buildings counts its staffed and open slots" % n)
	var idle := TownModel.working_of(float(day1["town"]["workers"]["idle"]))
	t.ok(m.lot("lot-01")["building"]["badge"] == "%d idle" % idle, "badge: the crypt counts the idle (day1: %d)" % idle)
	m.update(_patched(day1, "lot-04", {"staffed": 1.0}), VIEW_RECT)
	t.ok(m.lot("lot-04")["building"]["badge"] == "1 working · 1 short" and m.lot("lot-04")["building"]["short"] == 1,
		"badge: a market missing a hand reads '1 working · 1 short'")
	m.update(demo, VIEW_RECT)
	t.ok(m.lot("lot-01")["building"]["badge"] == "8 idle", "badge: the demo's crypt reads '8 idle'")
	t.ok(m.lot("lot-18")["building"]["badge"] == "0 working", "badge: the idle bone mill (staff cap 0) wants no hands, so it is not short")
	var none := true
	for l in m.lots:
		var b: Dictionary = l["building"]
		if not b.is_empty() and b["look"] in ["calm", "constructing", "unpaid"]:
			none = none and b["badge"] == ""
	t.ok(none, "badge: no badge on buildings that need no staff, nor under construction, nor unpaid")
	m.update(mid, VIEW_RECT)
	var mid_idle := TownModel.working_of(float(mid["town"]["workers"]["idle"]))
	t.ok(m.lot("lot-01")["building"]["badge"] == "%d idle" % mid_idle, "badge: the idle count (%d) stays when Relish is away" % mid_idle)


func _pip_groups(day1: Dictionary, demo: Dictionary) -> void:
	t.ok(int(vcfg["pip_group"]) == 5, "pips: tally groups of 5")
	var o := TownModel.row_offsets(7, 5.0, 3.0, 4.0, 5)
	t.ok(o == PackedFloat32Array([0, 8, 16, 24, 32, 44, 52]), "pips: a gap after every 5th: %s" % str(o))
	t.near(TownModel.row_width(7, 5.0, 3.0, 4.0, 5), 57.0, 0.001, "pips: 7 pips span 57 px")
	t.ok(TownModel.row_offsets(5, 5.0, 3.0, 4.0, 5) == PackedFloat32Array([0, 8, 16, 24, 32]), "pips: no gap after the last")
	var ten := TownModel.row_offsets(10, 5.0, 3.0, 4.0, 5)
	t.ok(ten.size() == 10 and is_equal_approx(ten[5] - ten[4], 12.0) and is_equal_approx(ten[9] - ten[8], 8.0), "pips: 10 is two groups")
	t.ok(TownModel.row_offsets(0, 5.0, 3.0, 4.0, 5).is_empty() and TownModel.row_width(0, 5.0, 3.0, 4.0, 5) == 0.0, "pips: none is empty")
	t.ok(TownModel.count_label(6, 5) == "6" and TownModel.count_label(5, 5) == "" and TownModel.count_label(0, 5) == "",
		"pips: the integer shows beside a row of more than 5")
	var m := _model()
	m.update(_patched(demo, "lot-05", {"output": {"mint": 23.0, "burn": 0.6}}), VIEW_RECT)
	var pit: Dictionary = m.lot("lot-05")["building"]
	t.ok(pit["pips"] == int(vcfg["pip_max"]) and pit["pip_count"] == 23, "pips: capped at pip_max, the true count (23) kept beside")
	m.update(day1, VIEW_RECT)
	var mk: Dictionary = m.lot("lot-04")["building"]
	var want := floori(float(day1["town"]["buildings"][3]["output"]["gold"]) / float(vcfg["pip_unit"]["gold"]) + 1e-6)
	t.ok(day1["town"]["buildings"][3]["building_id"] == "market" and mk["pips"] == want and mk["pip_count"] == want,
		"pips: day1's market output is %d pips, the count the same" % want)
	var stub := _model()
	stub.update(_stub(day1), VIEW_RECT)
	var ch: Dictionary = stub.lot("lot-03")["building"]
	t.ok(stub.staffing_standin and ch["pips"] == roundi(ch["staffed"]) and ch["pip_count"] == ch["pips"], "pips: the stand-in keeps the count too")


func _rate_units(views: Array) -> void:
	var keys := {}
	for v in views:
		for b in v["town"]["buildings"]:
			for k in b["output"]:
				keys[k] = true
	for k in keys:
		var u: Dictionary = vcfg["rate_units"].get(k, {})
		t.ok(String(u.get("unit", "")) != "" and absf(float(u.get("sign", 0.0))) == 1.0 and Palette.has(String(u.get("ink", ""))),
			"rate units: output %s has a unit, a sign and a matter ink" % k)
	t.ok(keys.size() >= 6, "rate units: the fixtures and the demo report %d output keys: %s" % [keys.size(), str(keys.keys())])
	t.ok(vcfg["rate_units"]["gold"]["ink"] == "living" and vcfg["rate_units"]["mint"]["ink"] == "undead"
		and vcfg["rate_units"]["bodies"]["ink"] == "dead" and vcfg["rate_units"]["bone"]["ink"] == "dead",
		"rate units: gold is living, mint undead, bodies and bone dead")


func _status(b: Dictionary, look: String, town: Dictionary) -> String:
	return TownModel.status_text(TownModel.status_of(b, look, town, cfg["buildings"], cfg["buildings_view"], vcfg))


func _status_lines(day1: Dictionary, mid: Dictionary, demo: Dictionary) -> void:
	t.ok(TownModel.rate_text("gold", 0.3, vcfg) == "+0.30 gold/s", "status: a rate reads '+0.30 gold/s'")
	t.ok(TownModel.rate_text("gold", -0.03, vcfg) == "−0.03 gold/s", "status: a cost reads '−0.03 gold/s' (true minus)")
	t.ok(TownModel.rate_text("burn", 0.6, vcfg) == "−0.60 bodies/s", "status: burn reads as bodies spent")
	t.ok(TownModel.rate_text("q", 0.04, vcfg) == "+0.04 quality/s", "status: q reads as quality")
	var town := {"relish_home": true, "ladder_effective": ["build", "haul", "pit", "stall", "mill", "forge", "tend"],
		"jobs": [{"id": "haul", "slots": 3, "staffed": 3.0}, {"id": "pit", "slots": 2, "staffed": 0.0},
			{"id": "stall", "slots": 2, "staffed": 0.0}, {"id": "mill", "slots": 2, "staffed": 0.0}],
		"workers": {"idle": 0.0}}
	var mk := {"building_id": "market", "state": "active", "progress": 1.0, "slots": 2, "staffed": 0.0, "staff_cap": -1,
		"output": {}, "upkeep": {"gold": 0.03, "bone": 0.0}}
	t.ok(_status(mk, "unstaffed", town) == "idle: no staff (Haul is above it on the ladder)", "status: idle, Haul takes the hands first")
	var t2: Dictionary = town.duplicate(true)
	t2["jobs"][1]["staffed"] = 2.0
	t.ok(_status(mk, "unstaffed", t2) == "idle: no staff (Pit is above it on the ladder)", "status: the nearest staffed job above is named")
	t2["workers"]["idle"] = 4.0
	t.ok(_status(mk, "unstaffed", t2) == "idle: no staff", "status: with idle hands at the crypt it isn't the ladder")
	var t3: Dictionary = town.duplicate(true)
	t3["ladder_effective"] = ["build", "haul", "pit", "mill"]
	t.ok(_status(mk, "unstaffed", t3) == "idle: Stall is off the ladder", "status: a job off the ladder says so")
	var capped: Dictionary = mk.duplicate(true)
	capped["staff_cap"] = 0
	capped["state"] = "idle"
	t.ok(_status(capped, "unstaffed", town) == "idle: its staff cap is 0", "status: a staff cap of 0 says so")
	var up := {"building_id": "house", "state": "constructing", "progress": 0.45, "slots": 0, "staffed": 0.0, "upkeep": {"gold": 0.01}}
	t.ok(_status(up, "constructing", town) == "building: 45%", "status: 'building: 45%'")
	var unpaid: Dictionary = mk.duplicate(true)
	unpaid["state"] = "unpaid"
	t.ok(_status(unpaid, "unpaid", town) == "unpaid: −0.03 gold/s upkeep", "status: 'unpaid: −0.03 gold/s upkeep'")
	t.ok(TownModel.status_of(unpaid, "unpaid", town, cfg["buildings"], cfg["buildings_view"], vcfg)
		== [["unpaid: ", false], ["−0.03 gold/s", true], [" upkeep", false]], "status: the rate is the oblique part, the words upright")
	unpaid["upkeep"] = {"gold": 0.03, "bone": 0.01}
	t.ok(_status(unpaid, "unpaid", town) == "unpaid: −0.03 gold/s, −0.01 bone/s upkeep", "status: both upkeeps")
	unpaid["upkeep"] = {"gold": 0.0, "bone": 0.0}
	t.ok(_status(unpaid, "unpaid", town) == "unpaid", "status: unpaid with no upkeep listed")
	var short: Dictionary = mk.duplicate(true)
	short["slots"] = 3
	short["staffed"] = 1.0
	short["output"] = {"gold": 0.1}
	t.ok(_status(short, "staffed", town) == "short 2 hands", "status: 'short 2 hands'")
	short["slots"] = 2
	t.ok(_status(short, "staffed", town) == "short 1 hand", "status: 'short 1 hand'")
	short["slots"] = 3
	short["staffed"] = 2.7
	t.ok(_status(short, "staffed", town) == "short 1 hand", "status: 2.7 of 3 is short a hand (floor, as the ticks)")
	short["slots"] = 2
	short["staffed"] = 0.4
	t.ok(TownModel.look_of("market", "active", 2, true, 0.4) == "staffed" and _status(short, "staffed", town) == "short 2 hands"
		and TownModel.badge_text(TownModel.working_of(0.4), 2, vcfg) == "0 working · 2 short",
		"status: a fraction of a hand works, short 2 whole hands, as its badge says")
	var full: Dictionary = mk.duplicate(true)
	full["staffed"] = 2.0
	full["output"] = {"gold": 0.3}
	t.ok(_status(full, "staffed", town) == "working: +0.30 gold/s", "status: 'working: +0.30 gold/s'")
	t.ok(TownModel.status_of(full, "staffed", town, cfg["buildings"], cfg["buildings_view"], vcfg)
		== [["working: ", false], ["+0.30 gold/s", true]], "status: working's rates are oblique")
	full["output"] = {}
	t.ok(_status(full, "staffed", town) == "working", "status: working with no output")
	full["output"] = {"gold": 0.0}
	t.ok(_status(full, "staffed", town) == "working", "status: a zero rate is left out")
	var pit := {"building_id": "raising_pit", "state": "active", "progress": 1.0, "slots": 2, "staffed": 2.0, "upkeep": {},
		"output": {"burn": 0.6, "mint": 6.0}}
	t.ok(_status(pit, "staffed", town) == "working: +6.00 mint/s, −0.60 bodies/s", "status: the pit mints and burns (main output first)")
	var house := {"building_id": "house", "state": "active", "progress": 1.0, "slots": 0, "staffed": 0.0, "upkeep": {}, "output": {}}
	t.ok(_status(house, "calm", town) == "no staff needed: +8 housing", "status: 'no staff needed: +8 housing' (the card's benefit, with its number)")
	var plaza := {"building_id": "plaza", "state": "active", "progress": 1.0, "slots": 0, "staffed": 0.0, "upkeep": {}, "output": {}}
	t.ok(_status(plaza, "calm", town) == "no staff needed: " + String(cfg["buildings_view"]["plaza"]["benefit"]),
		"status: a building with no numeric effect keeps its benefit words")
	var crypt := {"building_id": "crypt", "state": "active", "progress": 1.0, "slots": 0, "staffed": 0.0, "upkeep": {}, "output": {}}
	t.ok(_status(crypt, "heart", town) == String(vcfg["status"]["heart_home"]), "status: the crypt with Relish home")
	var away: Dictionary = town.duplicate(true)
	away["relish_home"] = false
	t.ok(_status(crypt, "heart", away) == "Relish away: slab idle", "status: 'Relish away: slab idle'")
	# the model fills every entry from the live views
	var m := _model()
	for pair in [["day1", day1], ["midgame_2flips", mid]]:
		var v: Dictionary = pair[1]
		m.update(v, VIEW_RECT)
		var same := true
		for b in v["town"]["buildings"]:
			var e: Dictionary = m.lot(String(b["lot_id"]))["building"]
			same = same and e["status"] != "" and e["status"] == _status(b, String(e["look"]), v["town"]) \
				and e["status"] == TownModel.status_text(e["status_parts"])
		t.ok(same, "status: every %s building's line is status_of() its view entry" % pair[0])
	m.update(day1, VIEW_RECT)
	var b4: Dictionary = day1["town"]["buildings"][3]
	t.ok(b4["building_id"] == "market" and int(b4["slots"]) == TownModel.working_of(float(b4["staffed"]))
		and m.lot("lot-04")["building"]["status"] == "working: " + TownModel.rate_text("gold", float(b4["output"]["gold"]), vcfg),
		"status: day1's full market works at its live rate: '%s'" % m.lot("lot-04")["building"]["status"])
	m.update(demo, VIEW_RECT)
	var all := true
	for l in m.lots:
		if not l["building"].is_empty():
			all = all and String(l["building"]["status"]) != ""
	t.ok(all, "status: every demo building has a line")
	var gh_up := float(cfg["buildings"]["guildhall"]["upkeep"]["gold"])
	t.ok(m.lot("lot-14")["building"]["status"] == "unpaid: %s upkeep" % TownModel.rate_text("gold", -gh_up, vcfg),
		"status: the demo's unpaid guildhall: '%s'" % m.lot("lot-14")["building"]["status"])
	t.ok(m.lot("lot-04")["building"]["status"] == "working: +0.60 gold/s", "status: the demo's market")
	t.ok(m.lot("lot-18")["building"]["status"] == "idle: its staff cap is 0", "status: the demo's idle mill")
	t.ok(m.lot("lot-21")["building"]["status"] == "building: 20%", "status: the demo's statue going up")


func _agent_status(demo: Dictionary) -> void:
	var pair := _agents(demo)
	var a: TownAgents = pair[1]
	var by_job := {}
	for u in a.undead:
		if not by_job.has(u.job):
			by_job[u.job] = u
	t.ok(by_job.has("haul") and by_job.has("pit") and by_job.has("stall") and by_job.has("idle"), "agent text: the demo has haulers, pit workers, stalls and idle")
	var h: TownAgents.Agent = by_job["haul"]
	h.hidden = false
	h.holding = false
	h.stop = 0
	t.ok(String(h.stops[0]) == "lot:lot-03", "agent text: a hauler's first stop is the charnel house")
	t.ok(a.describe(h) == "hauler: carrying bodies to the Charnel House", "agent text: '%s'" % a.describe(h))
	h.stop = 1
	t.ok(a.describe(h) == "hauler: heading out to the forts", "agent text: '%s'" % a.describe(h))
	h.hidden = true
	t.ok(a.describe(h) == "hauler: out at the forts", "agent text: '%s'" % a.describe(h))
	h.hidden = false
	h.leaving = true
	t.ok(a.describe(h) == "hauler: going back to the crypt", "agent text: '%s'" % a.describe(h))
	h.leaving = false
	var p: TownAgents.Agent = by_job["pit"]
	p.holding = false
	p.hidden = false
	p.stop = 1
	t.ok(a.describe(p) == "pit worker: carrying a body to the Raising Pit", "agent text: '%s'" % a.describe(p))
	p.stop = 0
	t.ok(a.describe(p) == "pit worker: going to the Charnel House", "agent text: '%s'" % a.describe(p))
	var s: TownAgents.Agent = by_job["stall"]
	s.holding = true
	t.ok(a.describe(s) == "stall keeper: working at the Market", "agent text: '%s'" % a.describe(s))
	s.holding = false
	t.ok(a.describe(s) == "stall keeper: going to the Market", "agent text: '%s'" % a.describe(s))
	t.ok(a.describe(by_job["idle"]) == "idle at the crypt", "agent text: 'idle at the crypt'")
	var roles: Dictionary = vcfg["agent_status"]["roles"]
	var every := true
	for u in a.undead:
		var d := a.describe(u)
		every = every and (d == "idle at the crypt" if u.job == "idle" else d.begins_with(String(roles[u.job]) + ": "))
	t.ok(every, "agent text: every worker reads as its job's role")
	var l: TownAgents.Agent = a.living[0]
	l.leaving = false
	l.wait = -1.0
	var mk := -1
	for i in l.stops.size():
		if String(l.stops[i]) == "lot:lot-04":
			mk = i
	t.ok(mk == 1, "agent text: a townsperson's second stop is the market")
	l.stop = 1
	t.ok(a.describe(l) == "buyer: going to the Market", "agent text: '%s'" % a.describe(l))
	l.stop = 0
	t.ok(a.describe(l) == "resident: going home", "agent text: '%s'" % a.describe(l))
	l.stop = 2
	t.ok(a.describe(l) == "guest: going to the Inn", "agent text: '%s'" % a.describe(l))
	l.wait = 1e9
	t.ok(a.describe(l) == "buyer: at the Market", "agent text: dwelling, '%s'" % a.describe(l))
	l.leaving = true
	t.ok(a.describe(l) == "leaving town by the gate", "agent text: '%s'" % a.describe(l))


func _agent_pick(day1: Dictionary) -> void:
	var a: TownAgents = _agents(day1)[1]
	t.ok(float(vcfg["agent_hit_px"]) >= 22.0, "pick: the agent hit radius is at least 22 px (a 44 px target)")
	var u: TownAgents.Agent = a.undead[0]
	for x in a.undead + a.living:
		x.hidden = true
	u.hidden = false
	t.ok(a.agent_at(u.pos + Vector2(21, 0), 22.0) == u, "pick: a click 21 px off hits the agent")
	t.ok(a.agent_at(u.pos + Vector2(23, 0), 22.0) == null, "pick: 23 px off misses")
	t.ok(a.agent_at(u.pos + Vector2(21, 0), 4.0) == u, "pick: the radius never drops under 22 px")
	t.ok(a.agent_at(u.pos + Vector2(30, 0), 40.0) == u, "pick: a bigger configured radius reaches further")
	var w: TownAgents.Agent = a.undead[1]
	w.hidden = false
	w.pos = u.pos + Vector2(10, 0)
	t.ok(a.agent_at(u.pos + Vector2(8, 0), 22.0) == w, "pick: the nearest agent wins")
	w.hidden = true
	var liv: TownAgents.Agent = a.living[0]
	liv.hidden = false
	liv.pos = u.pos + Vector2(0, 200)
	t.ok(a.agent_at(liv.pos, 22.0) == liv, "pick: the living can be picked too")
	u.hidden = true
	t.ok(a.agent_at(u.pos, 22.0) == null, "pick: a hidden agent (out at the forts) can't be picked")
	u.hidden = false
	u.gone = true
	t.ok(a.agent_at(u.pos, 22.0) == null and not a.alive(u), "pick: a gone agent can't be picked and isn't alive")
	t.ok(a.alive(liv) and not a.alive(TownAgents.Agent.new()) and not a.alive(null), "pick: alive() is membership, not just the flag")


func _floats(day1: Dictionary, demo: Dictionary) -> void:
	var m := _model()
	m.update(demo, VIEW_RECT)
	t.ok(m.floats.is_empty(), "float: entering the scene floats nothing")
	m.update(demo, VIEW_RECT)
	t.ok(m.floats.is_empty(), "float: equal outputs float nothing")
	# a cause (a hand taken off the market) and its effect on the output: one float
	var gold := _out(demo, "lot-04", "gold")
	var st := _field(demo, "lot-04", "staffed")
	var less := _patched(demo, "lot-04", {"staffed": st - 1.0, "output": {"gold": gold - 0.1}})
	m.update(less, VIEW_RECT)
	t.ok(m.floats.size() == 1, "float: one staffing change with its output change, one float (%d)" % m.floats.size())
	if m.floats.size() == 1:
		var f: Dictionary = m.floats[0]
		t.ok(f["lot_id"] == "lot-04" and f["text"] == "−0.10 gold/s" and f["ink"] == "living" and f["text_key"] == "living",
			"float: the market floats '−0.10 gold/s' in gold's living orange: %s" % str(f))
	m.update(less, VIEW_RECT)
	t.ok(m.floats.is_empty(), "float: fires once, not again on the same values")
	m.update(demo, VIEW_RECT)
	t.ok(m.floats.size() == 1 and m.floats[0]["text"] == "+0.10 gold/s", "float: the hand back floats '+0.10 gold/s'")
	# no cause, no float: an output swing with the same staffing, level and state (haul trips)
	var bodies := _out(demo, "lot-03", "bodies")
	m.update(_patched(demo, "lot-03", {"output": {"bodies": bodies + 1.1}}), VIEW_RECT)
	t.ok(m.floats.is_empty(), "float: a haul output swing with unchanged staffing floats nothing")
	m.update(_patched(demo, "lot-03", {"output": {"bodies": bodies - 0.6}}), VIEW_RECT)
	t.ok(m.floats.is_empty(), "float: nor its swing back down")
	m.update(_patched(demo, "lot-04", {"staffed": st - 0.3, "output": {"gold": gold - 0.03}}), VIEW_RECT)
	t.ok(m.floats.is_empty(), "float: a staffing change that rounds to the same count is no cause")
	m.update(demo, VIEW_RECT)
	m.update(_patched(demo, "lot-04", {"staffed": st - 1.0, "output": {"gold": gold + float(vcfg["float"]["eps"]) * 0.5}}), VIEW_RECT)
	t.ok(m.floats.is_empty(), "float: a cause with an output change under float.eps floats nothing")
	m.update(demo, VIEW_RECT)
	# the level is a cause: an upgrade finishing
	var lvl := int(_field(demo, "lot-04", "level"))
	m.update(_patched(demo, "lot-04", {"level": lvl + 1, "output": {"gold": gold + 0.2}}), VIEW_RECT)
	t.ok(m.floats.size() == 1 and m.floats[0]["text"] == "+0.20 gold/s", "float: a level change with its output floats")
	m.update(demo, VIEW_RECT)
	# the pit: more burn floats bodies spent (dead text falls back to `text`); one float per building
	var mint := _out(demo, "lot-05", "mint")
	var burn := _out(demo, "lot-05", "burn")
	var pst := _field(demo, "lot-05", "staffed")
	m.update(_patched(demo, "lot-05", {"staffed": pst + 1.0, "output": {"mint": mint, "burn": burn + 0.6}}), VIEW_RECT)
	t.ok(m.floats.size() == 1 and m.floats[0]["text"] == "−0.60 bodies/s" and m.floats[0]["ink"] == "dead"
		and m.floats[0]["text_key"] == "text", "float: more burn floats bodies spent, its text in `text` (dead is too dark for text)")
	m.update(_patched(demo, "lot-05", {"staffed": pst + 2.0, "output": {"mint": mint + 2.0, "burn": burn + 1.0}}), VIEW_RECT)
	t.ok(m.floats.size() == 1 and m.floats[0]["text"] == "+2.00 mint/s", "float: one per building, its main output first")
	# live day1: a market hand lost, the upkeep unpaid, a new building, a swapped one
	var s := _model()
	s.update(day1, VIEW_RECT)
	t.ok(s.floats.is_empty(), "float: day1 entry floats nothing")
	var g1 := _out(day1, "lot-04", "gold")
	var half := _patched(day1, "lot-04", {"staffed": 1.0, "output": {"gold": g1 * 0.5}})
	s.update(half, VIEW_RECT)
	t.ok(s.floats.size() == 1 and s.floats[0]["lot_id"] == "lot-04" and s.floats[0]["text"] == TownModel.rate_text("gold", -g1 * 0.5, vcfg),
		"float: a market losing a hand floats its lost gold (%s)" % (s.floats[0]["text"] if s.floats.size() == 1 else "none"))
	s.update(_patched(half, "lot-04", {"state": "unpaid", "staffed": 1.0, "output": {}}), VIEW_RECT)
	t.ok(s.floats.size() == 1 and s.floats[0]["text"] == TownModel.rate_text("gold", -g1 * 0.5, vcfg), "float: going unpaid (a state change) floats the output lost")
	var added: Dictionary = half.duplicate(true)
	added["town"]["buildings"].append({"lot_id": "lot-05", "building_id": "market", "level": 1, "state": "active", "progress": 1.0,
		"slots": 2, "staffed": 2.0, "staff_cap": -1, "foreman": "", "output": {"gold": 0.3}, "upkeep": {"gold": 0.03, "bone": 0.0}})
	s.update(added, VIEW_RECT)
	var only_old := true
	for f in s.floats:
		only_old = only_old and f["lot_id"] != "lot-05"
	t.ok(only_old, "float: a building first seen floats nothing")
	s.update(_patched(added, "lot-05", {"building_id": "bone_mill", "output": {"bone": 0.2}}), VIEW_RECT)
	t.ok(s.floats.is_empty(), "float: a different building on a lot floats nothing")


## A building field on `lot_id` in `views` (0 if absent).
func _field(views: Dictionary, lot_id: String, key: String) -> float:
	for b in views["town"]["buildings"]:
		if b["lot_id"] == lot_id:
			return float(b.get(key, 0.0))
	return 0.0


## A building output on `lot_id` in `views` (0 if absent).
func _out(views: Dictionary, lot_id: String, key: String) -> float:
	for b in views["town"]["buildings"]:
		if b["lot_id"] == lot_id:
			return float(b["output"].get(key, 0.0))
	return 0.0


func _ring_order(day1: Dictionary) -> void:
	var m := _model()
	m.update(day1, VIEW_RECT)
	t.ok(m.street_order.size() == m.streets.size(), "ring order: one number per street")
	var plaza_ok := true
	var chain_ok := true
	var top := 0
	for i in m.streets.size():
		var s: Dictionary = m.streets[i]
		var n: int = m.street_order[i]
		top = maxi(top, n)
		if String(s["a"]).begins_with("plaza") or String(s["b"]).begins_with("plaza"):
			plaza_ok = plaza_ok and n == 1
		elif n <= 1:
			chain_ok = false
		else:
			var linked := false
			for j in m.streets.size():
				var o: Dictionary = m.streets[j]
				var shares: bool = o["a"] in [s["a"], s["b"]] or o["b"] in [s["a"], s["b"]]
				linked = linked or (j != i and shares and m.street_order[j] == n - 1)
			chain_ok = chain_ok and linked
	t.ok(plaza_ok, "ring order: every street touching the crypt's plaza (any plaza* node) is 1, the whole block round the crypt")
	t.ok(m.street_order[m.edge_index("plaza_nw", "plaza_ne")] == 1 and m.street_order[m.edge_index("w2", "plaza_nw")] == 1,
		"ring order: the north side of the crypt's block is 1 too")
	t.ok(chain_ok, "ring order: every other street touches one a ring nearer the crypt")
	var gate := m.edge_index("gate", "w1")
	t.ok(gate >= 0 and top >= 3 and m.street_order[gate] >= top - 1,
		"ring order: the gate road is out at the edge (ring %d of %d)" % [m.street_order[gate] if gate >= 0 else -1, top])


## Trade arcs read as an exchange: a hop at least view.trade_arc_min_h_px high even for close
## pairs, bowing up the screen, and a mote travelling buyer to seller over the arc's life.
func _arc_shape() -> void:
	var min_h := float(vcfg["trade_arc_min_h_px"])
	var bulge := float(vcfg["agent"]["arc_bulge"])
	t.ok(min_h >= 16.0, "arc: a hop of at least %.0f px" % min_h)
	for pair in [[Vector2(100, 200), Vector2(112, 200)], [Vector2(100, 200), Vector2(100, 206)], [Vector2(100, 200), Vector2(300, 200)]]:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		var c := TownAgents.arc_ctrl(a, b, bulge, min_h)
		var top := TownAgents.arc_point(a, c, b, 0.5)
		var chord := (a + b) * 0.5
		var h := top.distance_to(chord)
		var want := maxf(min_h, 0.5 * bulge * a.distance_to(b))
		t.near(h, want, 0.01, "arc: %.0f px apart, the hop is %.1f px (max of min_h and the bulge)" % [a.distance_to(b), h])
		if is_equal_approx(a.y, b.y):
			t.ok(top.y < chord.y, "arc: a level pair bows up the screen (%.1f px above the chord)" % (chord.y - top.y))
		t.ok(TownAgents.arc_point(a, c, b, 0.0).is_equal_approx(a) and TownAgents.arc_point(a, c, b, 1.0).is_equal_approx(b),
			"arc: from the buyer to the seller")
	t.ok(is_equal_approx(TownAgents.mote_u(0.0, 1.0, false), 0.0) and is_equal_approx(TownAgents.mote_u(0.5, 1.0, false), 0.5)
		and is_equal_approx(TownAgents.mote_u(2.0, 1.0, false), 1.0), "arc: the mote runs buyer to seller over the arc's life")
	t.ok(is_equal_approx(TownAgents.mote_u(0.1, 1.0, true), 0.5) and is_equal_approx(TownAgents.mote_u(0.9, 1.0, true), 0.5),
		"arc: under reduced motion the mote sits still at the midpoint")
	t.ok(float(vcfg["agent"]["arc_mote_px"]) > 0.0, "arc: the mote has a size")


func _dismiss_box() -> void:
	var plate := Rect2(100, 50, 160, 24)
	var xw := 20.0
	var cell := Rect2(plate.end.x - xw, plate.position.y, xw, plate.size.y)
	var text := Rect2(plate.position, Vector2(plate.size.x - xw, plate.size.y))
	for above in [true, false]:
		var box := BuildSort.dismiss_box(cell, plate, above)
		t.ok(box.size.x >= 44.0 and box.size.y >= 44.0, "dismiss: the hit box is at least 44 px (%s)" % str(box))
		t.ok(box.has_point(cell.get_center()), "dismiss: the hit box covers the x")
		t.ok(not box.intersects(text), "dismiss: the hit box never covers the tag text (above=%s)" % above)
		t.ok(box.end.y <= plate.end.y + 0.01 if above else box.position.y >= plate.position.y - 0.01,
			"dismiss: the hit box grows away from the lot (above=%s)" % above)
	t.near(BuildSort.dismiss_room(xw), 24.0, 0.001, "dismiss: the tag keeps 24 px free on its right for the box")


func _legible_contrast() -> void:
	var ground := Palette.c("ground")
	for k in ["text", "text_dim"]:
		t.ok(TownModel.contrast(Palette.c(k), ground) >= 4.5, "legible: %s text (badges, tags, ring numbers, away label) reads at 4.5:1" % k)
	for k in ["undead", "living"]:
		t.ok(TownModel.float_text_key(k) == k and TownModel.contrast(Palette.c(k), ground) >= 4.5, "legible: a %s float is in its matter colour" % k)
	t.ok(TownModel.float_text_key("dead") == "text" and TownModel.contrast(Palette.c("dead"), ground) < 4.5,
		"legible: a dead float's text falls back to `text` (dead is %.2f:1)" % TownModel.contrast(Palette.c("dead"), ground))
	var g: Dictionary = vcfg["agent"]
	t.ok(TownModel.contrast(Palette.c("living"), ground) >= 3.0, "legible: the living stroke reads at 3:1")
	t.ok(float(g["undead_glow"]) > float(g["living_glow"]) and float(g["core_px"]) >= 3.0,
		"legible: the undead glyph outshines the living (halo %.2f vs %.2f, core %.1f px)" % [g["undead_glow"], g["living_glow"], g["core_px"]])
	for k in [["badge", "px"], ["status", "px"], ["pick", "px"], ["float", "px"], ["ring_order", "px"]]:
		t.ok(int(vcfg[k[0]][k[1]]) >= 12, "legible: %s text is at least 12 px" % k[0])
	t.ok(int(vcfg["badge"]["px"]) <= 13 and int(vcfg["pip_count_px"]) >= 12, "legible: the badge is small (12-13 px); pip counts at least 12 px")
	t.ok(float(vcfg["warn"]["size_px"]) >= 16.0, "legible: the unpaid tick is at least 16 px")
	var away := float(vcfg["slab_ring_away_alpha"])
	t.ok(away < float(vcfg["slab_ring_alpha"]) and TownModel.contrast(Palette.c("undead", away), ground) >= 3.0,
		"legible: the slab rings breathe fainter while Relish is away, still a 3:1 line (%.2f:1)" % TownModel.contrast(Palette.c("undead", away), ground))


# -------------------------------------------------------- behaviour on auto ----
func _is_perm(order: Array) -> bool:
	var a := order.duplicate()
	a.sort()
	var b: Array = GameState.JOB_IDS.duplicate()
	b.sort()
	return a == b


func _behaviour_pure() -> void:
	var ids: Array = GameState.JOB_IDS
	var all_perm := true
	var lands := true
	for i in ids.size():
		for j in ids.size():
			var o := TownBehaviour.move(ids, i, j)
			all_perm = all_perm and _is_perm(o)
			lands = lands and o[j] == ids[i]
	t.ok(all_perm, "ladder: moving index i to j always yields a permutation of JOB_IDS")
	t.ok(lands, "ladder: the moved job ends at index j")
	t.ok(TownBehaviour.move(ids, 2, 2) == ids and TownBehaviour.move(ids, 99, 0) == ids, "ladder: a no-op move and a bad index change nothing")
	# a drop on row k's upper or lower half puts the job before or after row k
	var good := true
	for i in ids.size():
		for k in ids.size():
			if i == k:
				continue
			for lower in [false, true]:
				var o := TownBehaviour.move(ids, i, TownBehaviour.drop_index(i, k, lower))
				var at := o.find(ids[k])
				var me := o.find(ids[i])
				good = good and _is_perm(o) and (me == at + 1 if lower else me == at - 1)
	t.ok(good, "ladder: dropping on a row's upper half lands just above it, the lower half just below")

	var eff := TownBehaviour.move(ids, 5, 0)  # a stance (tend) jumped to the top
	var moves := TownBehaviour.ladder_moves(ids, eff)
	t.ok(moves.size() == 6 and moves[0]["job"] == ids[5] and moves[0]["from"] == 5 and moves[0]["to"] == 0,
		"ladder diff: the stance's job moved from 5 to 0, the six it passed each moved down one")
	t.ok(TownBehaviour.ladder_moves(ids, ids).is_empty() and TownBehaviour.ladder_moves(ids, []).is_empty(),
		"ladder diff: identical (or missing) effective order shows no moved rows")

	# the cap stepper: all(-1) -> 0 -> 1 ... slots -> all, and back
	for slots in [0, 1, 2, 3]:
		var seq: Array = []
		var c := -1
		for n in slots + 2:
			seq.append(c)
			c = TownBehaviour.cap_step(c, slots, 1)
		var want: Array = [-1]
		for k in range(0, slots + 1):
			want.append(k)
		t.ok(seq == want and c == -1, "cap: %d slots step up %s and wrap to -1" % [slots, str(want)])
		var down: Array = []
		c = -1
		for n in slots + 2:
			down.append(c)
			c = TownBehaviour.cap_step(c, slots, -1)
		var rev: Array = [-1]
		for k in range(slots, -1, -1):
			rev.append(k)
		t.ok(down == rev and c == -1, "cap: %d slots step down %s and wrap to -1" % [slots, str(rev)])
	t.ok(TownBehaviour.cap_step(9, 3, 1) == -1 and TownBehaviour.cap_step(9, 3, -1) == 2, "cap: a stored cap above the slots counts as the slots")
	t.ok(TownBehaviour.cap_text(-1, 3, "all") == "all" and TownBehaviour.cap_text(9, 3, "all") == "3", "cap: -1 reads \"all\", a big cap reads the slots")

	var prev := {"haul": 3.0, "pit": 2.0}
	var jobs := [{"id": "haul", "staffed": 3.0}, {"id": "pit", "staffed": 1.0}, {"id": "stall", "staffed": 2.0}]
	t.ok(TownBehaviour.staffing_changes(prev, jobs, 0.05) == ["pit"] and TownBehaviour.staffing_changes({}, jobs, 0.05).is_empty(),
		"staffing: only the job whose staffed moved is a change, and no baseline means none")
	var sb := TownBehaviour.slot_breakdown(4, 2, true)
	t.ok(sb == {"base": 2, "home": 1, "guild": 1} and TownBehaviour.slot_breakdown(2, 2, false) == {"base": 2, "home": 0, "guild": 0}
		and TownBehaviour.slot_breakdown(1, 2, true)["guild"] == 0, "stance slots: base + Guildhall + 1 while Relish is home, never negative")
	var units: Dictionary = vcfg["rate_units"]
	var parts := TownBehaviour.projected_parts({"gold": -0.05, "bodies": 0.4, "q": 0.0}, units)
	t.ok(parts == ["+0.40/s bodies", "−0.05/s gold"], "projected: signed rates, biggest first, zeros dropped, units from rate_units: %s" % str(parts))
	t.ok(TownBehaviour.projected_parts({}, units).is_empty(), "projected: {} shows nothing (the panel says the projection is coming)")
	var jb := {"market": ["stall"], "forge": ["forge"]}
	var bs := [{"lot_id": "lot-01", "building_id": "market", "state": "idle"}, {"lot_id": "lot-02", "building_id": "forge", "state": "idle"},
		{"lot_id": "lot-03", "building_id": "market", "state": "active"}]
	t.ok(TownBehaviour.idled_jobs({"lot-01": false, "lot-02": true, "lot-03": false}, bs, jb) == ["stall"],
		"thrift: only buildings that turned idle since the last view count (not ones already idle)")


## A bare undead agent for the flash queries.
func _bare(job: String) -> TownAgents.Agent:
	var a := TownAgents.Agent.new()
	a.job = job
	return a


func _stance_flash(day1: Dictionary, demo: Dictionary) -> void:
	var ag := TownAgents.new(vcfg, cfg["buildings"], cfg["economy"], tempo_s, 3)
	ag.flash(["haul", "idle"], 2.3)
	var h := _bare("haul")
	t.ok(not ag.is_flashing(h, 2.3) and not ag.is_flashing(h, 2.99), "flash: nothing before the NEXT beat (scheduled at 2.3 -> starts at 3)")
	t.ok(ag.is_flashing(h, 3.0) and ag.is_flashing(h, 3.99), "flash: lit for exactly one beat from the next beat")
	t.ok(not ag.is_flashing(h, 4.0), "flash: over after one beat")
	t.ok(ag.is_flashing(_bare("idle"), 3.5) and not ag.is_flashing(_bare("stall"), 3.5) and not ag.is_flashing(_bare("tend"), 3.5),
		"flash: only the mapped jobs flash")
	var l := _bare("haul")
	l.undead = false
	t.ok(not ag.is_flashing(l, 3.5), "flash: the living never do")
	ag.flash(["tend"], 0.0)
	t.ok(ag.is_flashing(_bare("tend"), 1.5) and ag.is_flashing(_bare("haul"), 3.5), "flash: two flashes coexist")

	# firing: the stance's jobs (config), once per beat id
	var jobs_of := {"vigil": ["tend"], "harvest": ["haul"], "muster": ["idle"], "hearth": ["stall"]}
	for id in jobs_of:
		var a2 := TownAgents.new(vcfg, cfg["buildings"], cfg["economy"], tempo_s, 3)
		var got := a2.fire_stance(id, 10)
		t.ok(got == jobs_of[id], "fire: %s flashes %s" % [id, str(jobs_of[id])])
		t.ok(a2.fire_stance(id, 10).is_empty(), "fire: %s at the same beat id again is the same firing (event + view dedupe)" % id)
		t.ok(a2.fire_stance(id, 11) == jobs_of[id], "fire: %s at a new beat id fires again" % id)
	for id in vcfg["stance_jobs"]:
		var spec = vcfg["stance_jobs"][id]
		t.ok(GameState.STANCE_IDS.has(id) and (spec is String or (spec is Array and not spec.is_empty())),
			"config: stance_jobs.%s is known and maps to jobs" % id)

	# through sync(): a changed fired_beat_id flashes at the next beat; the first sync is a baseline
	var pair := _agents(demo)
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	var clock := _run(a, 2.0)
	t.ok(a.count("haul") > 0, "flash: the demo city has haulers")
	var v := demo.duplicate(true)
	_resync(m, a, v)
	var start := a.beat()
	var first_lit := -1.0
	var wrong := false
	var lit_n := 0
	var dt := 1.0 / 60.0
	var armed := false
	for f in int(4.0 * tempo_s * 60.0):
		if f == 5 and not armed:
			armed = true
			for s in v["stances"]["stances"]:
				if s["id"] == "harvest":
					s["fired_beat_id"] = 42
			_resync(m, a, v)
		clock += dt
		a.step(dt, fposmod(clock / tempo_s, 1.0), false)
		var lit_haul := false
		for u in a.undead:
			if u.stance_flash:
				wrong = wrong or u.job != "haul"
				lit_haul = true
		if lit_haul and first_lit < 0.0:
			first_lit = a.beat()
		if lit_haul:
			lit_n += 1
	t.ok(first_lit >= 0.0 and not wrong, "flash: a changed fired_beat_id lights haulers only (and nobody else)")
	t.ok(first_lit == floorf(first_lit) or first_lit - floorf(first_lit) < 0.2, "flash: it starts on a beat boundary (%.3f)" % first_lit)
	t.ok(lit_n > 0 and float(lit_n) * dt <= tempo_s + 3.0 * dt, "flash: it lasts one beat (%.2f s of %.2f s)" % [float(lit_n) * dt, tempo_s])
	t.ok(first_lit >= floorf(start + 5.0 / 60.0 / tempo_s) + 1.0 - 0.001, "flash: not before the next beat after the change (%.3f vs %.3f)" % [first_lit, start])

	# the event path and the view path are one firing
	var b2 := _agents(demo)
	var a3: TownAgents = b2[1]
	_run(a3, 1.0)
	a3.fire_stance("harvest", 7)
	var v2 := demo.duplicate(true)
	for s in v2["stances"]["stances"]:
		if s["id"] == "harvest":
			s["fired_beat_id"] = 7
	var before := a3._flashes.size()
	_resync(b2[0], a3, v2)
	t.ok(a3._flashes.size() == before, "flash: the event then the view's fired_beat_id is one flash, not two")

	# thrift: the jobs of buildings that turned idle
	var b3 := _agents(day1)
	var a4: TownAgents = b3[1]
	var v3 := day1.duplicate(true)
	var idx := -1
	for i in v3["town"]["buildings"].size():
		if String(v3["town"]["buildings"][i]["building_id"]) == "market":
			idx = i
	if idx >= 0:
		v3["town"]["buildings"][idx]["state"] = "active"
		_resync(b3[0], a4, v3)
		a4.fire_stance("thrift", 3)
		t.ok(a4._flashes.is_empty(), "thrift: waits for the idled buildings (none yet)")
		v3["town"]["buildings"][idx]["state"] = "idle"
		_resync(b3[0], a4, v3)
		t.ok(a4._flashes.size() == 1 and (a4._flashes[0]["jobs"] as Dictionary).has("stall"),
			"thrift: the idled market's job (stall) flashes")

	# reduced motion: the flash still happens, as a static one-beat highlight
	var rp := _agents(demo)
	var ar: TownAgents = rp[1]
	_run(ar, 1.0, 0.0, true)
	ar.fire_stance("harvest", 5)
	var seen := false
	var secs := 0.0
	var moved := false
	var pos0 := {}
	for u in ar.undead:
		pos0[u] = u.pos
	for f in int(3.0 * tempo_s * 30.0):
		ar.step(1.0 / 30.0, 0.0, true)
		secs += 1.0 / 30.0
		for u in ar.undead:
			if u.stance_flash:
				seen = true
				if pos0.has(u):
					moved = moved or u.pos.distance_to(pos0[u]) > 0.01
	t.ok(seen, "reduced motion: the stance flash still shows")
	t.ok(not moved, "reduced motion: and nothing moves")
	var gone := true
	for u in ar.undead:
		gone = gone and not u.stance_flash
	t.ok(gone, "reduced motion: the highlight ends after its beat")
	_run(ar, 0.0)


func _behaviour_config() -> void:
	for k in ["job_labels", "job_site_text", "stance_labels", "stance_rules", "stance_jobs", "behaviour"]:
		t.ok(vcfg.has(k), "view.%s exists" % k)
	for id in GameState.JOB_IDS:
		t.ok(String(vcfg["job_labels"].get(id, "")) != "", "view.job_labels has %s" % id)
	for id in GameState.STANCE_IDS:
		t.ok(String(vcfg["stance_labels"].get(id, "")) != "" and String(vcfg["stance_rules"].get(id, "")) != "",
			"view.stance_labels/rules have %s" % id)
	for r in ["unknown_job", "duplicate_job", "missing_job", "bad_cap", "no_jobs", "no_slot", "unknown_stance", "_unknown"]:
		t.ok(vcfg["behaviour"]["refusals"].has(r), "view.behaviour.refusals has %s" % r)
	t.ok(String(vcfg["behaviour"]["refusals"]["no_slot"]).contains("turn one off"), "no_slot reads \"turn one off\"")


## The commands the tabs send, against a live GameState: the ladder, a cap and a stance echo in the views.
func _behaviour_commands() -> void:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	var order: Array = TownBehaviour.move(s.view_town()["ladder"], 3, 0)
	t.ok(s.cmd_set_job_priority(order)["ok"] and s.view_town()["ladder"] == order, "commands: a dropped ladder shows in view_town().ladder")
	var bad := order.duplicate()
	bad[1] = bad[0]
	t.ok(not s.cmd_set_job_priority(bad)["ok"], "commands: a ladder with a job twice is refused (the panel shows the reason)")
	var lot := ""
	var slots := 0
	for b in s.view_town()["buildings"]:
		if int(b["slots"]) > 0:
			lot = String(b["lot_id"])
			slots = int(b["slots"])
			break
	if lot != "":
		var cap := TownBehaviour.cap_step(-1, slots, 1)
		t.ok(s.cmd_set_staff_cap(lot, cap)["ok"], "commands: a cap step is accepted")
		var got := -2
		for b in s.view_town()["buildings"]:
			if String(b["lot_id"]) == lot:
				got = int(b["staff_cap"])
		t.ok(got == cap, "commands: the cap shows in view_town().buildings[].staff_cap")
	t.ok(s.cmd_set_stance("harvest", true)["ok"], "commands: a stance turns on")
	var on := false
	for st in s.view_stances()["stances"]:
		if st["id"] == "harvest":
			on = bool(st["on"])
	t.ok(on, "commands: it shows in view_stances().stances[].on")


# ------------------------------------------------------------------ the HUD ----
func _hud(day1: Dictionary, mid: Dictionary, pre: Dictionary, demo: Dictionary) -> void:
	var h: Dictionary = vcfg["hud"]
	var bview: Dictionary = cfg["buildings_view"]
	t.ok(HudModel.net_text(0.42, h) == "+0.42/s" and HudModel.net_text(-0.1, h) == "\u22120.10/s",
		"hud: a net rate is signed with `/s` and a true minus")
	t.ok(HudModel.net_text(0.0, h) == "\u00b10.00/s" and HudModel.net_text(0.004, h) == "\u00b10.00/s" and HudModel.net_text(-0.004, h) == "\u00b10.00/s",
		"hud: a flat rate (inside the dead band) reads \u00b10.00/s")
	t.ok(HudModel.split_text([["in", 0.3], ["out", -0.14]], h) == "in +0.30 \u00b7 out \u22120.14 /s" and HudModel.split_text([["in", 0.0]], h) == "in \u00b10.00 /s",
		"hud: the split is signed, one `/s` for both parts, flat parts read \u00b10.00")
	t.ok(HudModel.net_text(0.5, h, "min") == "+0.50/min", "hud: the unit replaces `s`")
	t.ok(HudModel.glyph(0.3, h) == "\u25b2" and HudModel.glyph(-0.3, h) == "\u25bc" and HudModel.glyph(0.0, h) == h["glyph"]["flat"],
		"hud: ▲ for a gain, ▼ for a loss, a flat shape at zero (the sign is a shape, not colour)")
	t.ok(HudModel.steady_dir(40.0, 100.0, h) == 1 and HudModel.steady_dir(140.0, 100.0, h) == -1 and HudModel.steady_dir(100.5, 100.0, h) == 0,
		"hud: the steady arrow rises below the steady count, falls above it, holds inside the tolerance")
	t.ok(HudModel.steady_arrow(40.0, 100.0, h) == h["glyph"]["up"] and HudModel.steady_arrow(140.0, 100.0, h) == h["glyph"]["down"]
		and HudModel.steady_arrow(100.0, 100.0, h) == h["glyph"]["flat"], "hud: the arrow glyph follows the direction")
	t.ok(HudModel.steady_text(61.4, h) == "\u2192 steady 61", "hud: the steady text is an upright integer")
	t.ok(HudModel.fmt_dur(45.0, h) == "45 s" and HudModel.fmt_dur(300.0, h) == "5 min" and HudModel.fmt_dur(21600.0, h) == "6 h"
		and HudModel.fmt_dur(259200.0, h) == "3 d", "hud: durations pick s, min, h or d")
	t.ok(HudModel.store_text(50.0, 200.0, 150.0 / 21600.0, h) == "full in 6 h", "hud: full in (cap - stock) / net")
	t.ok(HudModel.store_text(200.0, 200.0, 1.0, h) == h["text"]["full"] and HudModel.store_text(200.4, 200.0, 1.0, h) == h["text"]["full"],
		"hud: at the cap (as shown, rounded) reads overflowing")
	# clarity round 3: "20635 / 9750" said nothing. Over the cap TownSim keeps the excess and takes in nothing (store_overflow)
	t.ok(HudModel.store_text(20635.0, 9750.0, -0.14, h) == h["text"]["over"] and HudModel.store_text(5198.0, 300.0, 0.0, h) == "over cap: no income",
		"hud: over the cap reads 'over cap: no income', whatever the rate")
	t.ok(HudModel.stock_tip("gold", 656.0, 9750.0, "full in 11.8 h", h) == "656 gold in store; the store holds 9750. full in 11.8 h",
		"hud: the stock's tooltip says what its two numbers are: '%s'" % HudModel.stock_tip("gold", 656.0, 9750.0, "full in 11.8 h", h))
	var over_tip := HudModel.stock_tip("bone", 5198.0, 300.0, h["text"]["over"], h)
	t.ok(over_tip.begins_with("5198 bone in store; the store holds 300.") and over_tip.contains("nothing more comes in") and over_tip.contains("under 300"),
		"hud: over the cap, the tooltip says why nothing comes in: '%s'" % over_tip)
	t.ok(HudModel.stock_tip("living", 26.0, 26.0, "", h) == "26 living; your town has room for 26." and HudModel.stock_tip("bodies", 3.0, -1.0, "", h) == "3 bodies in store; no cap.",
		"hud: living reads as room; a store with no cap says so")
	t.ok(HudModel.store_text(50.0, -1.0, 1.0, h) == h["text"]["no_cap"], "hud: cap -1 reads no cap")
	t.ok(HudModel.store_text(50.0, 200.0, 0.0, h) == "" and HudModel.store_text(50.0, 200.0, -0.3, h) == "",
		"hud: a store that is not filling says nothing")
	var m: Dictionary = {"value": 0.6, "target": 0.7, "factors": [
		{"id": "amenity:well", "delta": 0.03}, {"id": "shock", "delta": -0.05}, {"id": "base", "delta": 0.6},
		{"id": "dread", "delta": -0.12}, {"id": "amenity:house", "delta": 0.0}]}
	t.ok(HudModel.factor_line(m, h, bview) == "base +0.60 \u00b7 dread \u22120.12 \u00b7 shock \u22120.05 \u00b7 well +0.03",
		"hud: the factor line orders base, dread, shock, amenities; signed; zero factors dropped (got `%s`)" % HudModel.factor_line(m, h, bview))
	t.ok(HudModel.factor_line({"factors": []}, h, bview) == "", "hud: no factors, no line")
	var nxt := {"tier": "village", "have": 4, "need": 6, "missing": ["house"]}
	t.ok(HudModel.next_tier_line("hamlet", nxt, h, bview) == "next: Village \u2014 4/6 buildings, missing: House",
		"hud: the next-tier line names the missing building (got `%s`)" % HudModel.next_tier_line("hamlet", nxt, h, bview))
	nxt["missing"] = []
	t.ok(HudModel.next_tier_line("hamlet", nxt, h, bview) == "next: Village \u2014 4/6 buildings", "hud: empty `missing` leaves the clause out")
	t.ok(HudModel.next_tier_line("city", {"tier": "", "have": 30, "need": 0, "missing": []}, h, bview) == "City", "hud: at City the line is just the tier")
	# the bottleneck rule, over hand-built views
	var rows := [{"building_id": "house", "can_build": false, "reason": "no_bone", "cost": {}, "count": 0, "lot_size": 1, "max_level": 1, "requires": {}}]
	var v := {"town": {"buildings": [], "jobs": [], "workers": {"idle": 3.0}},
		"hud": {"rates": [{"id": "gold", "rate": 0.4}, {"id": "bone", "rate": 0.0}]},
		"catalog": {"buildings": rows}, "fort_names": {}}
	t.ok(HudModel.bottleneck(v, vcfg, bview) == ["bone: \u00b10.00/s, no Bone Mill"], "hud: flat bone with the next building short of bone and no mill: `%s`" % [HudModel.bottleneck(v, vcfg, bview)])
	v["hud"]["rates"][1]["rate"] = 0.2
	t.ok(HudModel.bottleneck(v, vcfg, bview) == [], "hud: bone is flowing, nothing is stuck")
	v["hud"]["rates"][1]["rate"] = -0.05
	v["town"]["buildings"] = [{"building_id": "bone_mill", "level": 1, "state": "active"}]
	t.ok(HudModel.bottleneck(v, vcfg, bview) == ["bone: \u22120.05/s, upkeep beats milling"], "hud: a built mill that loses to upkeep says so")
	v["hud"]["rates"][1]["rate"] = 0.0
	t.ok(HudModel.bottleneck(v, vcfg, bview) == ["bone: \u00b10.00/s, Bone Mill has no staff"], "hud: a built mill at zero has no staff")
	v["town"]["buildings"] = [{"building_id": "bone_mill", "level": 1, "state": "active", "staffed": 2.0}]
	t.ok(HudModel.bottleneck(v, vcfg, bview) == ["bone: \u00b10.00/s, Bone Mill is starved: no bodies"],
		"hud: a staffed mill at zero is starved of bodies, not unstaffed (%s)" % [HudModel.bottleneck(v, vcfg, bview)])
	v["town"]["buildings"] = [{"building_id": "market", "level": 1, "state": "active", "staffed": 1.0}, {"building_id": "bone_mill", "level": 1, "state": "active", "staffed": 0.0}]
	t.ok(HudModel.bottleneck(v, vcfg, bview) == ["bone: \u00b10.00/s, Bone Mill has no staff"], "hud: staffing is summed for the fix building only")
	var gv := {"town": {"buildings": [{"building_id": "market", "level": 1, "state": "active", "staffed": 1.0}], "jobs": [], "workers": {"idle": 3.0}},
		"hud": {"rates": [{"id": "gold", "rate": 0.0}, {"id": "bone", "rate": 0.4}]},
		"catalog": {"buildings": [{"building_id": "house", "can_build": false, "reason": "no_gold", "cost": {}, "count": 0, "lot_size": 1, "max_level": 1, "requires": {}}]}, "fort_names": {}}
	t.ok(HudModel.bottleneck(gv, vcfg, bview) == ["gold: \u00b10.00/s, Market is starved: no buyers"], "hud: a staffed market at zero is starved of buyers (%s)" % [HudModel.bottleneck(gv, vcfg, bview)])
	v["town"]["buildings"] = [{"building_id": "bone_mill", "level": 0, "state": "constructing"}]
	t.ok(HudModel.bottleneck(v, vcfg, bview) == ["bone: \u00b10.00/s, Bone Mill still building"], "hud: a mill under construction is still building")
	v["town"]["buildings"] = []
	v["catalog"]["buildings"][0]["reason"] = "no_gold"
	v["hud"]["rates"][0]["rate"] = -0.05
	v["hud"]["rates"][1]["rate"] = 0.3
	t.ok(HudModel.bottleneck(v, vcfg, bview) == ["gold: \u22120.05/s, no Market"], "hud: gold short and falling names the market")
	v["catalog"]["buildings"][0]["can_build"] = true
	v["catalog"]["buildings"][0]["reason"] = ""
	t.ok(HudModel.bottleneck(v, vcfg, bview) == ["gold: \u22120.05/s, no Market"], "hud: a stream with no producer is named even when nothing is short")
	v["hud"]["rates"][0]["rate"] = 0.4
	v["town"]["jobs"] = [{"id": "x", "slots": 5, "staffed": 2.0}, {"id": "y", "slots": 2, "staffed": 2.0}]
	v["town"]["workers"]["idle"] = 0.0
	t.ok(HudModel.bottleneck(v, vcfg, bview) == ["workers: 3 short of slots"], "hud: unstaffed slots with no idle worker read `workers: N short of slots`")
	v["town"]["workers"]["idle"] = 4.0
	t.ok(HudModel.bottleneck(v, vcfg, bview) == [], "hud: idle workers mean slots are not the problem")
	# a first stuck-free short row does not hide a second stuck stream (the producer is built, so only the row names it)
	var two := [{"building_id": "house", "can_build": false, "reason": "no_gold", "cost": {}, "count": 0, "lot_size": 1, "max_level": 1, "requires": {}},
		{"building_id": "inn", "can_build": false, "reason": "no_bone", "cost": {}, "count": 0, "lot_size": 1, "max_level": 1, "requires": {}}]
	for order in [two, [two[1], two[0]]]:
		var v2 := {"town": {"buildings": [{"building_id": "bone_mill", "level": 1, "state": "active", "staffed": 0.0}], "jobs": [], "workers": {"idle": 3.0}},
			"hud": {"rates": [{"id": "gold", "rate": 0.4}, {"id": "bone", "rate": 0.0}]}, "catalog": {"buildings": order}, "fort_names": {}}
		t.ok(HudModel.bottleneck(v2, vcfg, bview) == ["bone: \u00b10.00/s, Bone Mill has no staff"],
			"hud: a flowing first stream does not hide the stuck second (%s first): %s" % [order[0]["reason"], HudModel.bottleneck(v2, vcfg, bview)])
	# a staff cap is not a shortage: min(slots, cap) hands are wanted
	var capv := {"town": {"buildings": [{"building_id": "market", "level": 1, "state": "active", "slots": 3, "staffed": 1.0, "staff_cap": 1}],
		"jobs": [{"id": "stall", "slots": 3, "staffed": 1.0}], "workers": {"idle": 0.0}}}
	t.ok(HudModel.short_slots(capv["town"]) == 0, "hud: a capped building at its cap is not short of slots")
	capv["town"]["buildings"][0]["staff_cap"] = 2
	t.ok(HudModel.short_slots(capv["town"]) == 1, "hud: below the cap it is short by cap - staffed")
	capv["town"]["buildings"][0]["staff_cap"] = -1
	t.ok(HudModel.short_slots(capv["town"]) == 2, "hud: no cap (-1) reads all the slots")
	for pair in [["day1", day1], ["midgame_2flips", mid], ["pre_vei", pre], ["demo", demo]]:
		var lines: Array = HudModel.bottleneck(pair[1], vcfg, bview)
		t.ok(lines is Array and lines.size() <= 3, "hud: %s bottleneck lines (%s)" % [pair[0], lines])
	for k in ["hud_h"]:
		t.ok(float(vcfg[k]) <= 96.0 and float(vcfg[k]) >= 72.0, "hud: the strip is %d px (72..96)" % int(vcfg[k]))
	for k in ["net_px", "split_px", "stock_px", "name_px"]:
		t.ok(int(h[k]) >= 12, "hud: %s text is at least 12 px" % k)
	var d: Dictionary = demo["town"]
	t.ok(float(demo["hud"]["rates"][3]["rate"]) > 0.0 and demo.has("rates") and float(d["workers"]["steady"]) > float(d["workers"]["total"]),
		"hud: the demo carries signed rates, a steady state above the count and morale factors")


func _autoplay(day1: Dictionary, mid: Dictionary) -> void:
	var pick: Dictionary = BuildSort.autoplay_pick(day1, cfg)
	var row_ok := false
	for r in day1["catalog"]["buildings"]:
		if String(r["building_id"]) == String(pick.get("building_id", "")):
			row_ok = bool(r["can_build"]) and (r["lots"] as Array).has(pick.get("lot_id", ""))
	t.ok(not pick.is_empty() and row_ok, "autoplay: day1 picks a buildable row on one of its lots (%s)" % str(pick))
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("day1")
	t.ok(bool(s.cmd_build(pick["building_id"], pick["lot_id"])["ok"]), "autoplay: the pick is accepted by cmd_build")
	var none := day1.duplicate(true)
	for r in none["catalog"]["buildings"]:
		r["can_build"] = false
		r["reason"] = "no_gold"
	t.ok(BuildSort.autoplay_pick(none, cfg).is_empty(), "autoplay: nothing buildable picks {}")
	var views := {"town": mid["town"], "hud": mid["hud"], "catalog": mid["catalog"], "vei": mid["vei"], "relish": mid["relish"],
		"big_undead": mid["big_undead"], "fort_names": {}}
	var rows: Array = views["catalog"]["buildings"].duplicate(true)
	for r in rows:
		if String(r["building_id"]) == "crypt":
			r["can_build"] = true
			r["count"] = 1
			r["lots"] = ["lot-01"]
		else:
			r["can_build"] = false
	views["catalog"] = {"buildings": rows}
	var up_pick: Dictionary = BuildSort.autoplay_pick(views, cfg)  # an upgrade of a built building may be picked, never a second crypt
	t.ok(up_pick.is_empty() or bool(up_pick.get("upgrade", false)), "autoplay: a built unique building is never picked as a new build (%s)" % str(up_pick))


func _set_rate(v: Dictionary, id: String, rate: float) -> void:
	for r in v["hud"]["rates"]:
		if r["id"] == id:
			r["rate"] = rate


func _drop_building(v: Dictionary, bid: String) -> void:
	v["town"]["buildings"] = (v["town"]["buildings"] as Array).filter(func(b): return b["building_id"] != bid)


## A starved stream is a live need: bone (no mill) and gold (market unstaffed) rank their producer first.
func _starved(day1: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var v: Dictionary = day1.duplicate(true)
	_set_rate(v, "bone", 0.0)
	_set_rate(v, "gold", 0.2)
	var ids: Array = []
	for n in BuildSort.needs(v, {}, vcfg, bv):
		ids.append(n["id"])
	t.ok("starved_bone" in ids and not ("starved_gold" in ids), "starved: flat bone with no Bone Mill is a need, positive gold is not (%s)" % str(ids))
	t.ok(BuildSort.needs(v, {}, vcfg, bv)[ids.find("starved_bone")]["chip"] == "bone isn't flowing: no Bone Mill", "starved: the chip names the missing producer")
	var items: Array = BuildSort.sort_rows(v["catalog"]["buildings"], BuildSort.needs(v, {}, vcfg, bv), bv, vcfg)
	t.ok(items[0]["row"]["building_id"] == "bone_mill", "starved: the Bone Mill ranks first (%s)" % items[0]["row"]["building_id"])
	t.ok(BuildSort.suggest(items, bv)["building_id"] == "bone_mill", "starved: day1 suggests the Bone Mill")
	t.ok(BuildSort.autoplay_pick(v, cfg)["building_id"] == "bone_mill", "starved: the autoplayer builds the Bone Mill first")
	# a mill under construction is no need (no second mill is queued)
	v["town"]["buildings"].append({"lot_id": "lot-09", "building_id": "bone_mill", "state": "constructing", "staffed": 0.0})
	ids = []
	for n in BuildSort.needs(v, {}, vcfg, bv):
		ids.append(n["id"])
	t.ok(not ("starved_bone" in ids), "starved: a mill under construction is not a need")
	# built but unstaffed, stock under the cheapest bone cost: it has no staff
	v["town"]["buildings"][-1]["state"] = "active"
	v["town"]["bone"] = 0.0
	var n: Array = _starved_needs(v)
	t.ok(n.size() > 0 and n[0]["chip"] == "bone isn't flowing: Bone Mill has no staff", "starved: an unstaffed mill with no bone to buy with")
	# the stock covers the cheapest bone cost: not starved yet
	v["town"]["bone"] = 1000.0
	t.ok(_starved_ids(v).is_empty(), "starved: stock above the cheapest cost is no need")
	# staffed: bone stops being a need
	v["town"]["bone"] = 0.0
	v["town"]["buildings"][-1]["staffed"] = 2.0
	t.ok(_starved_ids(v).is_empty(), "starved: a built, staffed mill ends the need")
	# gold behaves the same way
	_set_rate(v, "bone", 0.1)
	_set_rate(v, "gold", 0.0)
	var g: Dictionary = day1.duplicate(true)
	_set_rate(g, "bone", 0.1)
	_set_rate(g, "gold", 0.0)
	g["town"]["gold"] = 0.0
	for b in g["town"]["buildings"]:
		b["staffed"] = 0.0 if b["building_id"] == "market" else b["staffed"]
	var gn: Array = _starved_needs(g)
	t.ok(gn.size() == 1 and gn[0]["id"] == "starved_gold" and gn[0]["chip"] == "gold isn't flowing: Market has no staff", "starved: an unstaffed market with no gold")
	for b in g["town"]["buildings"]:
		if b["building_id"] == "market":
			b["staffed"] = 2.0
	t.ok(_starved_ids(g).is_empty(), "starved: a staffed market ends the gold need")
	_drop_building(g, "market")
	gn = _starved_needs(g)
	t.ok(gn.size() == 1 and gn[0]["chip"] == "gold isn't flowing: no Market", "starved: no market at all")


func _starved_needs(v: Dictionary) -> Array:
	return BuildSort.needs(v, {}, vcfg, cfg["buildings_view"]).filter(func(n): return String(n["id"]).begins_with("starved_"))


func _starved_ids(v: Dictionary) -> Array:
	return _starved_needs(v).map(func(n): return n["id"])


## Hamlet with House missing for Village: gold 35 (house costs 40) so only cheaper rows are buildable.
func _hamlet(day1: Dictionary, gold: float, gold_rate: float) -> Dictionary:
	var v: Dictionary = day1.duplicate(true)
	_set_rate(v, "bone", 0.1)
	_set_rate(v, "gold", gold_rate)
	v["town"]["gold"] = gold
	v["town"]["bone"] = 100.0
	v["town"]["next_tier"] = {"tier": "village", "have": 6, "need": 6, "missing": ["house"]}
	for r in v["catalog"]["buildings"]:
		var c: Dictionary = r["cost"]
		var ok: bool = float(c.get("gold", 0.0)) <= gold and float(c.get("bone", 0.0)) <= 100.0 and String(r["reason"]) in ["", "no_gold", "no_bone"]
		if String(r["reason"]) in ["", "no_gold", "no_bone"]:
			r["can_build"] = ok
			r["reason"] = "" if ok else "no_gold"
		if r["building_id"] in ["house", "well"]:
			r["lots"] = ["lot-05", "lot-06", "lot-07"]
	return v


func _tier_need(day1: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var v := _hamlet(day1, 100.0, 0.15)
	var n: Array = BuildSort.needs(v, {}, vcfg, bv).filter(func(x): return String(x["id"]).begins_with("tier"))
	t.ok(n.size() == 1 and n[0]["chip"] == "next tier: Village needs a House" and n[0]["serves"] == ["building:house"], "tier need: the missing House, named by tier and label (%s)" % str(n))
	var items: Array = BuildSort.sort_rows(v["catalog"]["buildings"], BuildSort.needs(v, {}, vcfg, bv), bv, vcfg)
	t.ok(items[0]["row"]["building_id"] == "house" and items[0]["chip"] == "next tier: Village needs a House", "tier need: the House ranks first")
	v["town"]["next_tier"]["missing"] = ["walls", "chapel_of_vats"]
	t.ok(BuildSort.needs(v, {}, vcfg, bv).filter(func(x): return String(x["id"]).begins_with("tier")).size() == 2, "tier need: one need per missing building")
	v["town"]["next_tier"]["missing"] = ["house", "walls"]
	v["town"]["buildings"].append({"lot_id": "lot-09", "building_id": "house", "level": 0, "state": "constructing", "progress": 0.3})
	n = BuildSort.needs(v, {}, vcfg, bv).filter(func(x): return String(x["id"]).begins_with("tier"))
	t.ok(n.size() == 1 and n[0]["serves"] == ["building:walls"], "tier need: a missing building already under construction is not asked for again (%s)" % str(n))
	v["town"]["next_tier"] = {}
	t.ok(BuildSort.needs(v, {}, vcfg, bv).filter(func(x): return String(x["id"]).begins_with("tier")).is_empty(), "tier need: none when nothing is missing")
	var ids: Array = (vcfg["needs"]["order"] as Array)
	t.ok(ids.find("tier") > ids.find("starved_gold") and ids.find("tier") < ids.find("gold"), "tier need: after the starved streams, before gold")


func _save_for(day1: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var v := _hamlet(day1, 35.0, 0.15)
	var items: Array = BuildSort.sort_rows(v["catalog"]["buildings"], BuildSort.needs(v, {}, vcfg, bv), bv, vcfg)
	var sug: Dictionary = BuildSort.suggest(items, bv, BuildSort.stocks(v), vcfg)
	t.ok(sug.get("building_id", "") == "house" and String(sug.get("label", "")).begins_with("save for House (~") and sug.get("save", false),
		"save: 35 gold at +0.15/s with House missing suggests saving for it (%s)" % str(sug))
	t.ok(BuildSort.autoplay_pick(v, cfg).is_empty(), "save: the autoplayer waits")
	var slow := _hamlet(day1, 35.0, 0.0)
	items = BuildSort.sort_rows(slow["catalog"]["buildings"], BuildSort.needs(slow, {}, vcfg, bv), bv, vcfg)
	sug = BuildSort.suggest(items, bv, BuildSort.stocks(slow), vcfg)
	t.ok(sug.get("building_id", "") != "house" and not sug.has("save"), "save: gold not flowing falls back to today's rule (%s)" % str(sug.get("building_id", "")))
	t.ok(not BuildSort.autoplay_pick(slow, cfg).is_empty(), "save: ... and the autoplayer builds something")
	var far := _hamlet(day1, 1.0, 0.15)  # 39 gold short at 0.15/s is over the wait
	t.ok(BuildSort.autoplay_pick(far, cfg).get("building_id", "") != "house" and not BuildSort.suggest(
		BuildSort.sort_rows(far["catalog"]["buildings"], BuildSort.needs(far, {}, vcfg, bv), bv, vcfg), bv, BuildSort.stocks(far), vcfg).has("save"),
		"save: an estimate over suggest_wait_s falls back")
	var rich := _hamlet(day1, 100.0, 0.15)
	var pick: Dictionary = BuildSort.autoplay_pick(rich, cfg)
	t.ok(pick.get("building_id", "") == "house", "save: once the House is affordable the autoplayer builds it (%s)" % str(pick))


## The workers cell shows what the town keeps: the real field, else (stand-in) the whole workforce
## while the sim musters, else steady.
func _kept(day1: Dictionary) -> void:
	var h: Dictionary = vcfg["hud"]
	var town: Dictionary = {"jobs": [{"id": "a", "slots": 30, "staffed": 20.0}, {"id": "b", "slots": 20, "staffed": 10.0}],
		"workers": {"total": 40.0, "steady": 87.8, "muster": 0.0}}
	var hud: Dictionary = {}
	t.ok(is_equal_approx(HudModel.kept(town, hud), 87.8), "kept: no muster running, the town keeps its steady")
	town["workers"]["muster"] = 0.069
	t.ok(is_equal_approx(HudModel.kept(town, hud), 40.0), "kept: while the sim musters, the workforce is the kept one (total)")
	t.ok(is_equal_approx(TownStandins.steady_kept(town, hud), HudModel.kept(town, hud)), "kept: the stand-in lives in TownStandins")
	town["workers"]["steady_kept"] = 55.0
	t.ok(is_equal_approx(HudModel.kept(town, hud), 55.0), "kept: the view's workers.steady_kept wins")
	town["workers"].erase("steady_kept")
	hud["workers_steady_kept"] = 52.0
	t.ok(is_equal_approx(HudModel.kept(town, hud), 52.0), "kept: view_hud's workers_steady_kept is used too")
	t.ok(HudModel.steady_arrow(40.0, 40.0, h) == h["glyph"]["flat"] and HudModel.steady_arrow(40.0, 87.8, h) == h["glyph"]["up"],
		"kept: the arrow compares against kept (flat at 40 of 40, where steady 87.8 would say up)")
	t.ok(is_equal_approx(HudModel.surplus_rate(town, 87.8, 40.0, h), 0.069), "surplus: shown when steady > kept, from the live muster")
	t.ok(is_equal_approx(HudModel.surplus_rate(town, 40.0, 40.0, h), 0.069), "surplus: a live muster shows even when steady sits within tolerance of kept")
	town["workers"]["muster"] = 0.0
	town["workers"]["muster_steady"] = 0.11
	t.ok(is_equal_approx(HudModel.surplus_rate(town, 87.8, 60.0, h), 0.11), "surplus: muster_steady when no live muster")
	t.ok(HudModel.surplus_rate(town, 60.0, 60.0, h) == 0.0, "surplus: hidden when steady does not exceed kept")
	town["workers"].erase("muster_steady")
	t.ok(HudModel.surplus_rate(town, 87.8, 60.0, h) == 0.0, "surplus: hidden when no muster rate is known")
	t.ok(HudModel.war_text(0.069, h) == "+0.07/s" and HudModel.muster_word({}, h) == "idle \u2192 FLOOD",
		"surplus: signed rate, then where the muster goes, upright (FLOOD without the Muster stance: '%s')" % HudModel.muster_word({}, h))


func _vrow(id: String, count: int, gold := 10.0) -> Dictionary:
	var r := _row(id, true, "", ["lot-05"])
	r["count"] = count
	r["cost"]["gold"] = gold
	return r


## With no live need served, the suggestion prefers types the town lacks, producers before amenities.
func _variety() -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var pick := func(rows: Array) -> String:
		return String(BuildSort.suggest(BuildSort.sort_rows(rows, [], bv, vcfg), bv).get("building_id", ""))
	t.ok(pick.call([_vrow("well", 2), _vrow("bakery", 0), _vrow("market", 0, 80.0)]) == "market",
		"variety: wells at 2, a bakery and a market at 0: the producer wins")
	t.ok(pick.call([_vrow("well", 2), _vrow("bakery", 1), _vrow("market", 1, 80.0), _vrow("bone_mill", 2)]) == "market",
		"variety: every type built: the producer with the lowest count wins")
	t.ok(pick.call([_vrow("well", 2), _vrow("market", 3), _vrow("bakery", 1)]) == "bakery",
		"variety: a lower-count amenity beats a higher-count producer")
	t.ok(pick.call([_vrow("well", 0, 30.0), _vrow("statue", 0, 20.0)]) == "statue", "variety: equal count and kind: the cheaper first")
	t.ok(pick.call([_vrow("well", 0), _vrow("bakery", 0)]) == "well", "variety: a full tie keeps catalog order")
	t.ok(pick.call([_vrow("well", 2), _vrow("house", 2), _vrow("bakery", 0)]) == "bakery", "variety: never a third well or house while a type is at 0")
	var needs: Array = [{"id": "morale", "chip": "x", "serves": ["morale"]}]
	t.ok(String(BuildSort.suggest(BuildSort.sort_rows([_vrow("well", 5), _vrow("market", 0)], needs, bv, vcfg), bv)["building_id"]) == "well",
		"variety: a row serving a live need still leads")


## The fallback never repeats a morale/housing-only building a third time while the town lacks a type
## it could save for; with nothing flowing it still falls back to the repeat.
func _variety_save() -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var rows: Array = [_vrow("well", 2, 30.0), _row("bakery", false, "no_gold", ["lot-05"]), _row("market", false, "no_gold", ["lot-05"])]
	rows[1]["cost"]["gold"] = 70.0
	rows[2]["cost"]["gold"] = 80.0
	var st := {"gold": 60.0, "bone": 100.0, "relics": 0.0, "rates": {"gold": 0.2, "bone": 0.1}}
	var items: Array = BuildSort.sort_rows(rows, [], bv, vcfg)
	var sug: Dictionary = BuildSort.suggest(items, bv, st, vcfg)
	t.ok(sug.get("building_id", "") == "market" and sug.get("save", false), "variety: a third well is not suggested: save for the unbuilt producer (%s)" % str(sug))
	st["rates"]["gold"] = 0.0
	sug = BuildSort.suggest(items, bv, st, vcfg)
	t.ok(sug.get("building_id", "") == "well" and not sug.has("save"), "variety: gold not flowing falls back to the well")
	rows[0]["count"] = 1
	st["rates"]["gold"] = 0.2
	sug = BuildSort.suggest(BuildSort.sort_rows(rows, [], bv, vcfg), bv, st, vcfg)
	t.ok(sug.get("building_id", "") == "well", "variety: a second well is still fine (%s)" % str(sug))


# ------------------------------------------------------------ decisions (4c) ----
func _need_ids_of(needs: Array) -> Array:
	return needs.map(func(n): return n["id"])


## Unspent workers are a need: idle at or over view.needs.idle_hands_min, or a muster running; served
## by every building with job slots; ranked after the tier and before gold.
func _idle_hands(day1: Dictionary, mid: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var bc: Dictionary = cfg["buildings"]
	var lo := float(vcfg["needs"]["idle_hands_min"])
	var v := _need_views(day1)
	t.ok(BuildSort.needs(v, FORTS, vcfg, bv, bc).is_empty(), "idle hands: no idle hands, no need")
	v["town"]["workers"]["idle"] = lo - 0.5
	t.ok(BuildSort.needs(v, FORTS, vcfg, bv, bc).is_empty(), "idle hands: fewer than idle_hands_min (%.1f) idle is no need" % (lo - 0.5))
	v["town"]["workers"]["idle"] = lo
	var n: Array = BuildSort.needs(v, FORTS, vcfg, bv, bc)
	t.ok(_need_ids_of(n) == ["idle_hands"] and n[0]["chip"] == "%d idle hands: build jobs for them" % roundi(lo),
		"idle hands: idle_hands_min idle is a need with its chip (%s)" % str(n[0]["chip"] if not n.is_empty() else ""))
	v["town"]["workers"]["idle"] = 1.0
	v["town"]["workers"]["muster"] = 0.05
	t.ok(_need_ids_of(BuildSort.needs(v, FORTS, vcfg, bv, bc)) == ["idle_hands"], "idle hands: a running muster is a need under the minimum too")
	var want: Array = []
	for bid in bc:
		if BuildSort.job_slots(String(bid), bc) > 0:
			want.append("building:" + String(bid))
	t.ok(n[0]["serves"] == want and "building:raising_pit" in want and "building:market" in want and not "building:house" in want
		and not "building:crypt" in want, "idle hands: served by exactly the buildings with job slots (%s)" % str(want))
	t.ok(BuildSort.job_slots("charnel_house", bc) == int(bc["charnel_house"]["jobs"]["haul"]) and BuildSort.job_slots("house", bc) == 0
		and BuildSort.job_slots("nonesuch", bc) == 0, "idle hands: job_slots sums buildings.json jobs")
	t.ok((BuildSort.needs(v, FORTS, vcfg, bv)[0]["serves"] as Array).is_empty(), "idle hands: without buildings.json nothing is served (callers pass it)")
	# the sort: job buildings carry the need, housing doesn't
	var rows := [_row("house", true, "", ["lot-05"]), _row("market", true, "", ["lot-06"]), _row("bone_mill", false, "no_gold", ["lot-07"])]
	var items: Array = BuildSort.sort_rows(rows, n, bv, vcfg)
	t.ok(items.map(func(i): return i["row"]["building_id"]) == ["market", "house", "bone_mill"] and items[0]["need"] == "idle_hands"
		and items[2]["need"] == "idle_hands" and items[1]["need"] == "", "idle hands: a buildable job building leads, a short one ranks as serving")
	# a job building beats the variety rule's unbuilt amenity
	var amen := [_vrow("well", 0), _vrow("market", 2, 80.0)]
	t.ok(String(BuildSort.suggest(BuildSort.sort_rows(amen, [], bv, vcfg), bv)["building_id"]) == "well"
		and String(BuildSort.suggest(BuildSort.sort_rows(amen, n, bv, vcfg), bv)["building_id"]) == "market",
		"idle hands: with idle hands the suggestion grows the workforce (a third Market over a first Well)")
	# order: after the tier, before gold
	var ord: Array = vcfg["needs"]["order"]
	t.ok(ord.find("idle_hands") == ord.find("tier") + 1 and ord.find("idle_hands") < ord.find("gold"), "idle hands: ordered after the tier, before gold")
	var tv := _need_views(day1)
	tv["town"]["workers"]["idle"] = lo + 2.0
	tv["town"]["next_tier"] = {"tier": "village", "have": 5, "need": 6, "missing": ["house"]}
	_set_rate(tv, "gold", -0.05)
	t.ok(_need_ids_of(BuildSort.needs(tv, FORTS, vcfg, bv, bc)) == ["tier", "idle_hands", "gold"], "idle hands: needs come tier, idle hands, gold")
	for pair in [["day1", day1], ["midgame_2flips", mid]]:
		var w: Dictionary = pair[1]["town"]["workers"]
		var live := float(w["idle"]) >= lo or float(w["muster"]) > 0.0
		t.ok(("idle_hands" in _need_ids_of(BuildSort.needs(pair[1], {}, vcfg, bv, bc))) == live,
			"idle hands: %s (idle %.1f, muster %.3f) %s" % [pair[0], float(w["idle"]), float(w["muster"]), "has the need" if live else "has none"])


## The HUD workers cell names the unspent hands and their best use.
func _hud_idle(day1: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var bc: Dictionary = cfg["buildings"]
	var mk := func(idle: float, muster: float, rows: Array) -> Dictionary:
		return {"town": {"workers": {"idle": idle, "muster": muster}, "buildings": [], "jobs": [], "next_tier": {}},
			"hud": {"rates": [{"id": "gold", "rate": 0.2}, {"id": "bone", "rate": 0.2}]}, "catalog": {"buildings": rows}, "fort_names": {}}
	var rows := [_row("house", true, "", ["lot-05"]), _row("charnel_house", true, "", ["lot-06"]), _row("market", false, "no_gold", ["lot-07"])]
	var v: Dictionary = mk.call(10.0, 0.1, rows)
	var p: Array = HudModel.idle_parts(v, vcfg, bv, bc)
	var want := "10 idle: build a %s (+%d jobs) or let them muster" % [BuildSort.label_of("charnel_house", bv), BuildSort.job_slots("charnel_house", bc)]
	t.ok(HudModel.parts_text(p) == want and p.size() == 1 and not p[0][1], "hud idle: the best use is the top buildable job building, its jobs counted upright (%s)" % HudModel.parts_text(p))
	var rp: Array = rows.duplicate(true)
	rp[1]["projected"] = {"bodies": 0.4}
	p = HudModel.idle_parts(mk.call(10.0, 0.1, rp), vcfg, bv, bc)
	t.ok(HudModel.parts_text(p) == "10 idle: build a Charnel House (+0.40/s bodies now) or let them muster" and p.size() == 3 and p[1][1]
		and not p[0][1] and not p[2][1], "hud idle: projected rates (api-request #9) replace the job count, oblique")
	var none: Array = rows.duplicate(true)
	none[1]["can_build"] = false
	none[1]["reason"] = "no_gold"
	t.ok(HudModel.parts_text(HudModel.idle_parts(mk.call(10.0, 0.1, none), vcfg, bv, bc)) == "10 idle: no job building affordable; mustering to FLOOD (Vei's queue)",
		"hud idle: nothing to build while mustering")
	t.ok(HudModel.parts_text(HudModel.idle_parts(mk.call(6.0, 0.0, none), vcfg, bv, bc)) == "6 idle: no job building affordable; waiting at the crypt",
		"hud idle: nothing to build and no muster: they wait")
	t.ok(HudModel.idle_parts(mk.call(1.0, 0.0, rows), vcfg, bv, bc).is_empty(), "hud idle: no idle-hands need, no line")
	# on day1 the line names a row that really can be built and has jobs
	var d := HudModel.parts_text(HudModel.idle_parts(day1, vcfg, bv, bc))
	var first := ""
	for it in BuildSort.sort_rows(day1["catalog"]["buildings"], BuildSort.needs(day1, {}, vcfg, bv, bc), bv, vcfg):
		if first == "" and bool(it["row"]["can_build"]) and BuildSort.job_slots(String(it["row"]["building_id"]), bc) > 0:
			first = String(it["row"]["building_id"])
	t.ok(first != "" and d.begins_with("%d idle: build a %s (" % [roundi(float(day1["town"]["workers"]["idle"])), BuildSort.label_of(first, bv)]),
		"hud idle: day1 reads '%s'" % d)
	t.ok(int(vcfg["hud"]["split_px"]) >= 12, "hud idle: the line is at least 12 px")


## The workers cell's "→ steady" says why the town keeps fewer than its raw steady state.
func _kept_reason(mid: Dictionary) -> void:
	var h: Dictionary = vcfg["hud"]
	var cap := float(cfg["economy"]["worker"]["idle_cap"])
	# the stand-in path: the view has no steady_kept (economy before E2b-1), so TownStandins gives the reason
	var town: Dictionary = (mid["town"] as Dictionary).duplicate(true)
	(town["workers"] as Dictionary).erase("steady_kept")
	(town["workers"] as Dictionary).erase("muster_steady")
	var hud: Dictionary = (mid["hud"] as Dictionary).duplicate(true)
	hud.erase("workers_steady_kept")
	var kept := HudModel.kept(town, hud)
	var in_slots := 0.0
	for j in town["jobs"]:
		in_slots += float(j["staffed"])
	var r := HudModel.kept_reason(town, hud, float(town["workers"]["steady"]), kept, cap, h)
	t.ok(kept < float(town["workers"]["steady"]) and r == "kept: %d slots + %d idle cap" % [roundi(in_slots), roundi(cap)],
		"kept reason (stand-in path): keeps %d of steady %.1f: '%s'" % [roundi(kept), float(town["workers"]["steady"]), r])
	t.ok(HudModel.kept_reason(town, hud, kept, kept, cap, h) == "", "kept reason: none when kept is the steady state")
	t.ok(TownStandins.kept_inputs(town, hud, cap) == {"slots": roundi(in_slots), "cap": roundi(cap)}, "kept reason (stand-in path): its inputs are the stand-in's (TownStandins)")
	# the real path: the view carries steady_kept (and muster_steady), so the stand-in switches itself off
	var real: Dictionary = town.duplicate(true)
	real["workers"]["steady_kept"] = kept
	real["workers"]["muster_steady"] = 1.2
	real["workers"]["muster"] = 0.0
	t.ok(TownStandins.kept_inputs(real, hud, cap).is_empty(), "kept reason (real path): the stand-in's inputs are off once the view has steady_kept")
	t.ok(HudModel.kept(real, hud) == kept, "kept reason (real path): the view's own kept value is what the HUD reads")
	t.ok(HudModel.kept_reason(real, hud, float(town["workers"]["steady"]), kept, cap, h) == "", "kept reason (real path): the view's own kept value (api-request #12) switches the stand-in reason off")
	t.ok(HudModel.surplus_rate(real, float(town["workers"]["steady"]), kept, h) >= 1.2 - 1e-6, "kept reason (real path): muster_steady is the surplus to WAR")


## The ladder preview: hands per job for a move, from the staffing projection (the stand-in until
## api-request #16), the total conserved; staff caps respected so today's order previews no change.
func _ladder_preview(day1: Dictionary) -> void:
	var bc: Dictionary = cfg["buildings"]
	var labels: Dictionary = vcfg["job_labels"]
	var tx: Dictionary = vcfg["behaviour"]
	var ladder: Array = ["build", "haul", "pit", "stall", "mill", "forge", "tend"]
	var town := {"jobs": [{"id": "haul", "slots": 3, "staffed": 3.0}, {"id": "pit", "slots": 2, "staffed": 2.0},
		{"id": "stall", "slots": 2, "staffed": 2.0}, {"id": "mill", "slots": 2, "staffed": 0.0}], "buildings": [], "workers": {"idle": 0.0}, "ladder": ladder}
	var v := {"town": town}
	var now: Dictionary = TownStandins.staffing_projection(v, ladder, bc)
	t.ok(TownBehaviour.staffing_diff(town["jobs"], now["jobs"]).is_empty(), "preview: today's order projects today's staffing")
	var after: Dictionary = TownStandins.staffing_projection(v, TownBehaviour.to_top(ladder, "mill"), bc)
	var diff := TownBehaviour.staffing_diff(now["jobs"], after["jobs"])
	var total := 0.0
	for d in diff:
		total += float(d["delta"])
	t.ok(TownBehaviour.diff_text(diff, labels, tx["hand"], tx["hands"]) == "Mill +2 hands, Stall −2" and absf(total) < 1e-6,
		"preview: Mill to the top takes 2 hands from Stall, total conserved (%s)" % TownBehaviour.diff_text(diff, labels, tx["hand"], tx["hands"]))
	var down := TownBehaviour.move(ladder, ladder.find("haul"), ladder.size() - 1)
	diff = TownBehaviour.staffing_diff(now["jobs"], TownStandins.staffing_projection(v, down, bc)["jobs"])
	t.ok(TownBehaviour.diff_text(diff, labels, tx["hand"], tx["hands"]) == "Mill +2 hands, Haul −2", "preview: Haul to the bottom gives Mill its 2 hands")
	t.ok(TownBehaviour.diff_text([{"id": "pit", "delta": -1.0}, {"id": "mill", "delta": 1.0}], labels, tx["hand"], tx["hands"]) == "Mill +1 hand, Pit −1",
		"preview: one hand is singular, gains before losses")
	t.ok(TownBehaviour.diff_text([{"id": "mill", "delta": 0.3}, {"id": "pit", "delta": -0.3}], labels, tx["hand"], tx["hands"]) == "",
		"preview: less than half a hand reads as no change")
	# the stand-in's behaviour, input to output: three jobs full (haul 3, pit 2, stall 2) and mill empty, 7 hands
	var by_id := func(jobs: Array, id: String) -> float:
		for j in jobs:
			if j["id"] == id:
				return float(j["staffed"])
		return -1.0
	t.ok(by_id.call(now["jobs"], "haul") == 3.0 and by_id.call(now["jobs"], "pit") == 2.0 and by_id.call(now["jobs"], "stall") == 2.0
		and by_id.call(now["jobs"], "mill") == 0.0, "preview: today's order keeps haul 3, pit 2, stall 2, mill 0")
	t.ok(by_id.call(after["jobs"], "mill") == 2.0 and by_id.call(after["jobs"], "stall") == 0.0 and by_id.call(after["jobs"], "haul") == 3.0
		and by_id.call(after["jobs"], "pit") == 2.0, "preview: mill on top gets 2 hands, the bottom (stall) pays them, 7 hands in all")
	t.ok(after["jobs"].map(func(j): return j["id"]) == TownBehaviour.to_top(ladder, "mill").filter(func(id): return id in ["haul", "pit", "stall", "mill"]),
		"preview: the answer lists the jobs in the order asked")
	# staff caps: a capped market keeps its one hand wherever Stall sits
	var capped := {"jobs": [{"id": "haul", "slots": 3, "staffed": 3.0}, {"id": "pit", "slots": 2, "staffed": 2.0},
		{"id": "stall", "slots": 2, "staffed": 1.0}, {"id": "mill", "slots": 2, "staffed": 1.0}],
		"buildings": [{"lot_id": "lot-04", "building_id": "market", "state": "active", "slots": 2, "staff_cap": 1}], "workers": {"idle": 0.0}}
	var cv := {"town": capped}
	var c0: Array = TownStandins.staffing_projection(cv, ladder, bc)["jobs"]
	t.ok(TownBehaviour.staffing_diff(capped["jobs"], c0).is_empty(), "preview: with a staff cap, today's order still projects today's staffing")
	t.ok(TownBehaviour.staffing_diff(c0, TownStandins.staffing_projection(cv, TownBehaviour.to_top(ladder, "stall"), bc)["jobs"]).is_empty(),
		"preview: the capped Stall to the top moves no hands")
	# day1 (every slot full, idle hands at the crypt): no move changes anything
	var lad: Array = day1["town"]["ladder"]
	var base: Array = TownStandins.staffing_projection(day1, lad, bc)["jobs"]
	var any := false
	for i in lad.size():
		any = any or not TownBehaviour.staffing_diff(base, TownStandins.staffing_projection(day1, TownBehaviour.move(lad, i, 0), bc)["jobs"]).is_empty()
	t.ok(not any, "preview: day1's ladder is all full, so no move moves a hand (the preview says so)")
	t.ok(TownBehaviour.to_top(lad, "nonesuch") == lad and TownBehaviour.to_top(lad, "tend")[0] == "tend", "preview: to_top moves a job up, ignores an unknown one")


## Relics: the card and catalog say "needs 2 relics: raid a fort"; the Build tab pins the gate.
func _relic_gate(mid: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var bc: Dictionary = cfg["buildings"]
	var needs: Array = BuildSort.needs(mid, {}, vcfg, bv, bc)
	var items: Array = BuildSort.sort_rows(mid["catalog"]["buildings"], needs, bv, vcfg)
	var st := BuildSort.stocks(mid)
	var miss: Array = mid["town"]["next_tier"]["missing"]
	var sum := 0
	for m in miss:
		sum += int(bc[m]["cost"]["relics"])
	var g := BuildSort.relic_gate(mid, items, st, bv, vcfg)
	var want := "Needs relics: %s. You have %d: raid a fort for more." % [
		" · ".join(miss.map(func(m): return "%s %d%s" % [BuildSort.label_of(String(m), bv), int(bc[m]["cost"]["relics"]), ""])), int(st["relics"])]
	want = want.replace("Walls and Gate 2", "Walls and Gate 2 ✓")  # 3 held: Walls is affordable, the Chapel then is not
	t.ok(sum > int(st["relics"]) and g.get("ids", []) == miss and g.get("text", "") == want,
		"relic gate: midgame's %s need %d relics, %d held: '%s'" % [str(miss), sum, int(st["relics"]), g.get("text", "")])
	var rich: Dictionary = mid.duplicate(true)
	rich["hud"]["relics"] = sum
	rich["inventory"]["relics"] = sum
	t.ok(BuildSort.relic_gate(rich, items, BuildSort.stocks(rich), bv, vcfg).is_empty(), "relic gate: enough relics for the whole tier set, no pin")
	var one: Dictionary = mid.duplicate(true)
	one["town"]["next_tier"]["missing"] = ["walls"]
	one["hud"]["relics"] = 0
	one["inventory"]["relics"] = 0
	var g1 := BuildSort.relic_gate(one, BuildSort.sort_rows(one["catalog"]["buildings"], BuildSort.needs(one, {}, vcfg, bv, bc), bv, vcfg), BuildSort.stocks(one), bv, vcfg)
	t.ok(String(g1.get("text", "")).begins_with("Needs relics: Walls and Gate 2. You have 0:"), "relic gate: one building, its own cost, no mark (%s)" % g1.get("text", ""))
	var placed: Dictionary = one.duplicate(true)
	placed["town"]["buildings"].append({"lot_id": "lot-23", "building_id": "walls", "level": 0, "state": "constructing", "progress": 0.1})
	t.ok(BuildSort.relic_gate(placed, [], BuildSort.stocks(placed), bv, vcfg).is_empty(), "relic gate: a missing building already placed is not asked for")
	var top := [{"row": {"building_id": "forge", "cost": {"gold": 0.0, "bone": 0.0, "relics": 1}}, "need": "idle_hands", "rank": 0}]
	var g2 := BuildSort.relic_gate({"town": {"next_tier": {}}}, top, {"relics": 0.0}, bv, vcfg)
	t.ok(g2.get("ids", []) == ["forge"] and String(g2.get("text", "")).begins_with("Needs relics: Forge 1. You have 0:"),
		"relic gate: the top need-serving row blocked by relics pins too (%s)" % g2.get("text", ""))
	t.ok(BuildSort.relic_gate({"town": {"next_tier": {}}}, top, {"relics": 1.0}, bv, vcfg).is_empty(), "relic gate: a top row it can pay for, no pin")
	t.ok(String(vcfg["relic_gate"]["button"]) == "To the realm", "relic gate: the pinned row's button says To the realm")
	# per row: an unmet relic cost is flagged (shape + danger in cost_parts) and said in words
	var walls := {"building_id": "walls", "cost": {"gold": 400.0, "bone": 0.0, "relics": 2}, "can_build": false, "reason": "no_gold",
		"requires": {"tier": "village"}, "lot_size": 3}
	var poor := {"gold": 100.0, "bone": 0.0, "relics": 0.0, "count": {"market": 1}, "rates": {"gold": 0.5}}
	t.ok(BuildSort.relic_text(walls, poor, bv, vcfg) == "needs 2 relics: raid a fort" and BuildSort.relic_text(walls, {"relics": 2.0}, bv, vcfg) == "",
		"relic row: 'needs 2 relics: raid a fort' only while short")
	t.ok(BuildSort.row_reason(walls, poor, bv, vcfg) == BuildSort.reason_text("no_gold", walls, poor, bv, vcfg) + "; needs 2 relics: raid a fort",
		"relic row: a funds-blocked row also says its relics (%s)" % BuildSort.row_reason(walls, poor, bv, vcfg))
	walls["reason"] = "no_relics"
	t.ok(BuildSort.row_reason(walls, poor, bv, vcfg) == "needs 2 relics: raid a fort", "relic row: a relic-blocked row says it once")
	walls["reason"] = "needs_tier"
	t.ok(not BuildSort.row_reason(walls, poor, bv, vcfg).contains("relic"), "relic row: a tier gate is said alone")
	walls["can_build"] = true
	t.ok(BuildSort.row_reason(walls, poor, bv, vcfg) == "", "relic row: a buildable row has no reason")
	var parts := BuildSort.cost_parts(walls["cost"], poor)
	t.ok(parts[2]["short"] and String(parts[2]["text"]).begins_with("! "), "relic row: the short relic cost carries the shortage mark (shape) and danger")


## Queue ETAs: the head saving for its cost, the cumulative estimate, a stream not flowing, the
## measured build throughput or the plain build work, and no ETA for a gate-skipped entry.
func _queue_eta(day1: Dictionary) -> void:
	var cat := {"raising_pit": {"build_work": 90.0}, "well": {"build_work": 60.0}, "forge": {"build_work": 120.0}, "house": {"build_work": 60.0}}
	var st := {"gold": 80.0, "bone": 30.0, "relics": 0.0, "rates": {"gold": 0.5, "bone": 0.1}}
	var mk := func(bid: String, lot: String, g: float, b: float, r: int, status: String) -> Dictionary:
		return {"building_id": bid, "lot_id": lot, "upgrade": false, "level": 1, "cost": {"gold": g, "bone": b, "relics": r}, "status": status, "reason": ""}
	var pit: Dictionary = mk.call("raising_pit", "lot-05", 90.0, 40.0, 0, "waiting_funds")
	var forge: Dictionary = mk.call("forge", "lot-13", 180.0, 50.0, 1, "skipped_gate")
	var well: Dictionary = mk.call("well", "lot-07", 30.0, 10.0, 0, "queued")
	var e: Array = BuildSort.queue_etas([pit, forge, well], st, cat, {}, -1.0, vcfg)
	var head_s := maxf(10.0 / 0.5, 10.0 / 0.1)
	var later_s := maxf(40.0 / 0.5, 20.0 / 0.1)  # the pit's and the well's costs; the skipped forge's are not counted
	t.ok(e[0] == "starts in ~%s · build time: 90 work" % BuildSort.fmt_eta(head_s, vcfg), "queue eta: the funds-blocked head (%s)" % e[0])
	t.ok(e[1] == "", "queue eta: a gate-skipped entry has no ETA")
	t.ok(e[2] == "starts in ≈ %s · build time: 60 work" % BuildSort.fmt_eta(later_s, vcfg), "queue eta: cumulative over the unskipped entries ahead (%s)" % e[2])
	var dry := st.duplicate(true)
	dry["rates"]["bone"] = 0.0
	e = BuildSort.queue_etas([pit, well], dry, cat, {}, -1.0, vcfg)
	t.ok(e[0] == "won't start: bone isn't flowing" and e[1] == "won't start: bone isn't flowing", "queue eta: a short store that isn't flowing says so")
	var rich := {"gold": 500.0, "bone": 500.0, "relics": 0.0, "rates": {"gold": 0.5, "bone": 0.1}}
	var nxt: Dictionary = mk.call("house", "lot-05", 40.0, 10.0, 0, "next")
	e = BuildSort.queue_etas([nxt, mk.call("well", "lot-07", 30.0, 10.0, 0, "queued")], rich, cat, {}, 1.2, vcfg)
	t.ok(e[0] == "starts now · then done in ~%s" % BuildSort.fmt_eta(60.0 / 1.2, vcfg) and e[1].begins_with("starts ≈ now · then done in ~"),
		"queue eta: the payable head starts now; with throughput the build time is measured (%s | %s)" % [e[0], e[1]])
	var site := {"buildings": [{"lot_id": "lot-07", "building_id": "well", "state": "constructing", "level": 0, "progress": 0.5}]}
	t.ok(is_equal_approx(BuildSort.entry_work(well, cat, site), 30.0) and is_equal_approx(BuildSort.entry_work(well, cat, {}), 60.0),
		"queue eta: an entry already being built has only its remaining work")
	var up := pit.duplicate(true)
	up["upgrade"] = true
	up["level"] = 2
	t.ok(is_equal_approx(BuildSort.entry_work(up, cat, {}), 180.0), "queue eta: an upgrade to level 2 is build_work × 2 (MECHANICS: build_work · target level)")
	# the throughput is measured from the views
	var at := func(tt: float, progress: float, level := 0, state := "constructing") -> Dictionary:
		return {"hud": {"t": tt}, "catalog": {"buildings": [{"building_id": "house", "build_work": 60.0}]},
			"town": {"buildings": [{"lot_id": "lot-05", "building_id": "house", "level": level, "state": state, "progress": progress}]}}
	var tp := BuildSort.Throughput.new(float(vcfg["queue_text"]["throughput_smooth_s"]))
	tp.observe(at.call(10.0, 0.2))
	t.ok(tp.rate < 0.0, "throughput: a site's first sighting measures nothing")
	tp.observe(at.call(20.0, 0.4))
	t.ok(is_equal_approx(tp.rate, 0.2 * 60.0 / 10.0), "throughput: Δprogress × build_work ÷ Δt (%.3f)" % tp.rate)
	tp.observe(at.call(20.0, 0.4))
	t.ok(is_equal_approx(tp.rate, 1.2), "throughput: a bind with no sim time passing changes nothing")
	tp.observe(at.call(30.0, 0.6))
	t.ok(is_equal_approx(tp.rate, 1.2), "throughput: a steady pace stays put under smoothing")
	tp.observe(at.call(40.0, 1.0, 0, "active"))
	t.ok(tp.rate < 0.0, "throughput: nothing constructing, unknown again")
	var tu := BuildSort.Throughput.new(10.0)
	tu.observe(at.call(0.0, 0.1, 1))
	tu.observe(at.call(10.0, 0.2, 1))
	t.ok(is_equal_approx(tu.rate, 0.1 * 60.0 * 2.0 / 10.0), "throughput: an upgrade site counts its target level's work (%.3f)" % tu.rate)
	# the real fixture: the queue context's stocks give real text (no raw keys)
	var q := TownStandins.BuildQueue.new(8, vcfg["cap_buildings"])
	var ctx := BuildSort.queue_context(day1, cfg["buildings"], vcfg)
	q.entries = [mk.call("raising_pit", "lot-05", 90.0, 40.0, 0, "queued"), mk.call("forge", "lot-13", 180.0, 50.0, 1, "queued"),
		mk.call("well", "lot-07", 30.0, 10.0, 0, "queued")]
	q.evaluate(ctx)
	var ds := BuildSort.stocks(day1)
	var etas: Array = BuildSort.queue_etas(q.entries, ds, ctx["catalog"], day1["town"], -1.0, vcfg)
	t.ok(etas.size() == 3 and q.entries[1]["status"] == "skipped_gate" and etas[1] == "" and String(etas[0]) != "" and not String(etas[0]).contains("{"),
		"queue eta: day1's seeded queue reads (%s)" % str(etas))
	t.ok(BuildSort.entry_reason(q.entries[1], ctx["catalog"], ds, cfg["buildings_view"], vcfg) == "needs 1 relic: raid a fort",
		"queue: a relic-gated entry is skipped and says 'raid a fort'")
	# a head saving for its cost names the store that holds it longest, as its ETA does
	var slow := {"gold": 80.0, "bone": 6.0, "relics": 0.0, "count": {"bone_mill": 1, "market": 1}, "rates": {"gold": 0.5, "bone": 0.05}}
	var head: Dictionary = mk.call("raising_pit", "lot-05", 90.0, 40.0, 0, "waiting_funds")
	head["reason"] = "no_gold"  # the stand-in records the first short store
	var why := BuildSort.entry_reason(head, cat, slow, cfg["buildings_view"], vcfg)
	var start := String(BuildSort.queue_etas([head], slow, cat, {}, -1.0, vcfg)[0])
	t.ok(why == "needs 34 more bone, about %s at +0.05/s" % BuildSort.fmt_eta(34.0 / 0.05, vcfg) and start.begins_with("starts in ~%s " % BuildSort.fmt_eta(34.0 / 0.05, vcfg)),
		"queue: the saving head names bone (34 at +0.05/s), not gold (10 at +0.50/s), matching its ETA (%s | %s)" % [why, start])
	slow["rates"]["gold"] = 0.0
	t.ok(BuildSort.entry_reason(head, cat, slow, cfg["buildings_view"], vcfg).begins_with("gold isn't flowing"), "queue: a short store that isn't flowing is named first")


## Stances name their trade in the town's numbers: the live condition and the hands it would move.
func _stance_trade(mid: Dictionary) -> void:
	var bc: Dictionary = cfg["buildings"]
	var town: Dictionary = mid["town"]
	var lad := TownBehaviour.effective(town)
	var before: Array = TownStandins.staffing_projection(mid, lad, bc)["jobs"]
	var proj := func(v: Dictionary, job: String) -> Array:
		return TownStandins.staffing_projection(v, TownBehaviour.to_top(TownBehaviour.effective(v["town"]), job), bc)["jobs"]
	var cap := float(town["bodies_cap"])
	var h := HudModel.parts_text(TownBehaviour.stance_trade("harvest", mid, before, proj.call(mid, "haul"), vcfg))
	t.ok(h == "Now: bodies %d / %d (fires under %d) → it would fire; Haul to the top: no hands move" % [int(float(town["bodies"])), roundi(cap), roundi(0.3 * cap)],
		"stance trade: midgame Harvest: '%s'" % h)
	var v: Dictionary = mid.duplicate(true)
	v["town"]["bodies"] = 150.0
	v["town"]["ladder_effective"] = ["build", "pit", "stall", "mill", "haul", "forge", "tend"]
	v["town"]["jobs"] = [{"id": "pit", "slots": 2, "staffed": 2.0}, {"id": "stall", "slots": 2, "staffed": 2.0},
		{"id": "mill", "slots": 2, "staffed": 2.0}, {"id": "haul", "slots": 3, "staffed": 1.0}]
	v["town"]["workers"]["idle"] = 0.0
	var vb: Array = TownStandins.staffing_projection(v, TownBehaviour.effective(v["town"]), bc)["jobs"]
	h = HudModel.parts_text(TownBehaviour.stance_trade("harvest", v, vb, proj.call(v, "haul"), vcfg))
	t.ok(h == "Now: bodies 150 / %d (fires under %d) → it wouldn't fire; if it did: Haul to the top: Haul +2 hands, Mill −2" % [roundi(cap), roundi(0.3 * cap)],
		"stance trade: Harvest at the top takes its hands from the jobs above it: '%s'" % h)
	var th: Array = TownBehaviour.stance_trade("thrift", mid, before, [], vcfg)
	var g: Dictionary = mid["rates"]["rates"]["gold"]
	var obl: Array = th.filter(func(p): return p[1]).map(func(p): return p[0])
	t.ok(obl == [TownUI.fmt_rate(float(g["in"])), TownUI.fmt_rate(-float(g["out"]))]
		and HudModel.parts_text(th).begins_with("Now: gold in %s vs upkeep %s → it %s" % [obl[0], obl[1], "would fire" if float(g["in"]) < float(g["out"]) else "wouldn't fire"]),
		"stance trade: Thrift compares gold income with upkeep, its rates oblique: '%s'" % HudModel.parts_text(th))
	var idle := roundi(float(town["workers"]["idle"]))
	t.ok(HudModel.parts_text(TownBehaviour.stance_trade("muster", mid, before, [], vcfg)) == "Now: %d idle at the crypt → it would fire; %d idle hands leave for WAR at once" % [idle, idle],
		"stance trade: Muster names the idle hands it sends")
	var vig := HudModel.parts_text(TownBehaviour.stance_trade("vigil", mid, before, proj.call(mid, "tend"), vcfg))
	var away := String(mid["relish"]["state"]) != "home"
	t.ok(vig.begins_with("Now: Relish is %s → it %s" % ["away" if away else "home", "would fire" if away else "wouldn't fire"]) and vig.ends_with("Tend to the top: no hands move"),
		"stance trade: Vigil reads Relish's state (%s)" % vig)
	var mv := float(town["morale"]["value"])
	var hearth := HudModel.parts_text(TownBehaviour.stance_trade("hearth", mid, before, proj.call(mid, "stall"), vcfg))
	t.ok(hearth.begins_with("Now: morale %.2f (fires under 0.50) → it %s" % [mv, "would fire" if mv < 0.5 else "wouldn't fire"]), "stance trade: Hearth reads morale (%s)" % hearth)
	for id in GameState.STANCE_IDS:
		var line := HudModel.parts_text(TownBehaviour.stance_trade(String(id), mid, before, proj.call(mid, TownBehaviour.stance_job(String(id), town, vcfg)), vcfg))
		t.ok(line.begins_with("Now: ") and not line.contains("{") and vcfg["stance_trade"].has(id), "stance trade: %s has a line: %s" % [id, line])
	t.ok(String(vcfg["behaviour"]["no_projection"]) == "projected rates: coming", "stance trade: rates still wait, and say so in player words")


## Phase I P3 (the run's manager's ruling 3 on handoff 4): Grow's trade line, from view_stances' `grow` (its pick, what
## holds it) and its row's `active` (the first finished build). midgame_2flips' own view first (a fixture load reads no
## beat yet, so `active` is false), then the same view as Grow armed, with its pick on a wait, held by the queue, held
## by the build under way, and with no pick. Names are buildings_view labels.
func _stance_trade_grow(mid: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var g: Dictionary = mid["stances"]["grow"]
	var name := BuildSort.label_of(String(g["building_id"]), bv)
	var line := HudModel.parts_text(TownBehaviour.stance_trade("grow", mid, [], [], vcfg, bv))
	t.ok(String(g["building_id"]) != "" and float(g["in_s"]) == 0.0 and String(g["held"]) == "" and not bool(g["busy"])
		and line == "Now: no build finished yet → it wouldn't fire; if it did: upgrades %s to level %d now" % [name, int(g["level"])],
		"stance trade: Grow in midgame_2flips' view names its pick (%s): '%s'" % [str(g), line])
	var v: Dictionary = mid.duplicate(true)
	for s in v["stances"]["stances"]:
		if String(s["id"]) == "grow":
			s["active"] = true
	v["stances"]["grow"] = {"building_id": "bone_mill", "lot_id": "lot-07", "level": 3, "in_s": 720.0, "held": "", "busy": false}
	var trade := func() -> String: return HudModel.parts_text(TownBehaviour.stance_trade("grow", v, [], [], vcfg, bv))
	t.ok(trade.call() == "Now: your first build is done → it would fire; upgrades Bone Mill to level 3 in 12 min",
		"stance trade: Grow armed, its pick on a wait: '%s'" % trade.call())
	v["stances"]["grow"]["held"] = "no_bone"
	t.ok(trade.call() == "Now: your first build is done → it would fire; Bone Mill level 3 waits: your queue is saving for its next build",
		"stance trade: Grow held by a queue head waiting on funds: '%s'" % trade.call())
	v["stances"]["grow"]["held"] = ""
	v["stances"]["grow"]["busy"] = true
	t.ok(trade.call() == "Now: your first build is done → it would fire; Bone Mill level 3 waits for the build under way",
		"stance trade: Grow held by the build under way (max_active): '%s'" % trade.call())
	v["stances"]["grow"] = {"building_id": "", "lot_id": "", "level": 0, "in_s": -1.0, "held": "", "busy": false}
	t.ok(trade.call() == "Now: your first build is done → it would fire; nothing it can upgrade now",
		"stance trade: Grow with no pick: '%s'" % trade.call())


## A stand-in rate of a building with job slots says "at full staffing"; projected rates say "now".
func _full_staffing_label() -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var bc: Dictionary = cfg["buildings"].duplicate(true)
	bc["raising_pit"]["effects"]["attract"] = 0.5
	var b := BuildSort.benefit("raising_pit", {}, bc, bv, vcfg)
	t.ok(b["rates"] == ["+0.50/s migrants at full staffing"] and not b["now"], "label: a job building's stand-in rate is 'at full staffing' (%s)" % str(b["rates"]))
	t.ok(BuildSort.benefit("inn", {}, cfg["buildings"], bv, vcfg)["rates"] == ["+0.02/s migrants"], "label: a building with no staff has no staffing label")
	t.ok(BuildSort.benefit("raising_pit", {"projected": {"mint": 3.0}}, bc, bv, vcfg)["rates"] == ["+3.00/s mint now"], "label: projected rates are 'now'")


# ------------------------------------------------------------ backups panel ----
func _backups(day1: Dictionary, pre: Dictionary) -> void:
	var tx: Dictionary = vcfg["backups"]
	# the death text: each outcome in words, the wait from respawn_s, no raw ids
	var o := func(outcome: String, s: float) -> String:
		return BackupsModel.outcome_text({"outcome": outcome, "respawn_s": s, "loses": []}, tx)
	t.ok(o.call("phylactery", 0.0) == "A phylactery charge: she gets back up where she fell", "backups: phylactery outcome (%s)" % o.call("phylactery", 0.0))
	t.ok(o.call("clone", 60.0) == "A ready clone: she wakes in Covington after 60 s", "backups: clone outcome with its wait (%s)" % o.call("clone", 60.0))
	t.ok(o.call("unmade", 600.0) == "Unmade: she reforms after 10 min", "backups: unmade outcome in minutes (%s)" % o.call("unmade", 600.0))
	t.ok(o.call("clone", 0.0) == "A ready clone: she wakes in Covington at once", "backups: a zero wait says at once (%s)" % o.call("clone", 0.0))
	for oc in ["phylactery", "clone", "unmade", "", "bogus"]:
		t.ok(not String(o.call(oc, 60.0)).contains("{") and not String(o.call(oc, 60.0)).contains("_"), "backups: '%s' leaks no raw id or placeholder" % oc)
	t.ok(BackupsModel.wait_text(60.0, tx) == "60 s" and BackupsModel.wait_text(600.0, tx) == "10 min" and BackupsModel.wait_text(0.0, tx) == "",
		"backups: wait text 60 s, 10 min, none")
	# the ladder: phylactery < clone < unmade, the current step marked
	for oc in ["phylactery", "clone", "unmade"]:
		var steps := BackupsModel.ladder(oc)
		t.ok(steps.map(func(x): return x["id"]) == ["phylactery", "clone", "unmade"]
			and steps.filter(func(x): return x["current"]).map(func(x): return x["id"]) == [oc], "backups: the ladder marks only %s" % oc)
	# every loses id in words
	for id in ["party", "unbanked_loot", "flip", "morale"]:
		var w := BackupsModel.loses_text(id, tx)
		t.ok(w != "" and w != id and not w.contains("_"), "backups: loses '%s' reads '%s'" % [id, w])
	t.ok(BackupsModel.loses_list(["unbanked_loot", "morale"], tx) == ["loot since the last checkpoint", "a morale shock"], "backups: loses list in order")
	t.ok(not BackupsModel.loses_text("some_new_id", tx).contains("_"), "backups: an unknown loses id still reads as words")
	var party := [{"name": "Old Gristle", "place": "town:lot-3"}, {"name": "Big u2", "place": "party"}]
	var pt := BackupsModel.party_text(party, {"lot-3": "Market"}, {}, vcfg["crypt"], tx)
	t.ok(pt == "the party: Old Gristle (foreman at the Market), Big u2", "backups: the party named with its places (%s)" % pt)
	t.ok(BackupsModel.party_text([], {}, {}, vcfg["crypt"], tx) == "the party", "backups: an empty party is just 'the party'")
	# vat state text
	t.ok(BackupsModel.vat_state_text({"staffed": true, "ready": false}, tx) == "staffed: growing", "backups: staffed vat")
	t.ok(BackupsModel.vat_state_text({"staffed": false, "ready": false}, tx) == "unstaffed: paused", "backups: unstaffed vat")
	t.ok(BackupsModel.vat_state_text({"staffed": false, "ready": true}, tx) == "ready: a clone waits", "backups: ready vat")
	# the silhouette reveal: length at grow 0, 0.5, 1
	var rect := Rect2(0, 0, 56, 96)
	var total := _strokes_len(BackupsModel.reveal_strokes(tx["figure"], rect, 1.0))
	t.ok(total > 100.0, "backups: the whole figure has length (%.1f)" % total)
	t.near(_strokes_len(BackupsModel.reveal_strokes(tx["figure"], rect, 0.0)), 0.0, 0.001, "backups: grow 0 draws nothing")
	t.near(_strokes_len(BackupsModel.reveal_strokes(tx["figure"], rect, 0.5)), total * 0.5, 0.5, "backups: grow 0.5 draws half the length")
	t.near(_strokes_len(BackupsModel.reveal_strokes(tx["figure"], rect, 1.0)), total, 0.001, "backups: grow 1 draws all of it")
	# crafts: cost and reason in words
	t.ok(BackupsModel.cost_text({"essence": 20, "relics": 1}, tx) == "20 essence, 1 relic", "backups: craft cost (%s)" % BackupsModel.cost_text({"essence": 20, "relics": 1}, tx))
	t.ok(BackupsModel.cost_text({"essence": 15, "relics": 0}, tx) == "15 essence", "backups: a zero relic cost is left out")
	t.ok(BackupsModel.craft_reason_text("needs_building", tx) == "needs the Ossuary Tower" and BackupsModel.craft_reason_text("no_essence", tx) == "not enough essence"
		and BackupsModel.craft_reason_text("no_relics", tx) == "not enough relics", "backups: craft reasons in words")
	t.ok(BackupsModel.pips_text(0, tx) == "none" and BackupsModel.pips_text(3, tx) == "◆◆◆" and BackupsModel.pips_text(11, tx) == "◆◆◆◆◆◆◆◆ +3", "backups: charges are countable pips")
	# staffing a vat takes one hand off the bottom of the order (the stand-in, until #16): a view with assigned hands
	var vtown := {"jobs": [{"id": "pit", "slots": 2, "staffed": 2.0}, {"id": "stall", "slots": 2, "staffed": 1.0}, {"id": "mill", "slots": 2, "staffed": 0.0}],
		"buildings": [], "workers": {"idle": 0.0}}
	var vorder: Array = ["pit", "stall", "mill"]
	var vviews := {"town": vtown, "backups": {"vats": [{"slot": 0, "staffed": false}]}}
	var before: Array = TownStandins.staffing_projection(vviews, vorder, cfg["buildings"])["jobs"]
	var after: Array = TownStandins.staffing_projection(vviews, vorder, cfg["buildings"], 1)["jobs"]
	var diff := TownBehaviour.staffing_diff(before, after)
	t.ok(diff.size() == 1 and absf(float(diff[0]["delta"]) + 1.0) < 0.001 and String(diff[0]["id"]) == "stall",
		"backups: one vat takes exactly one hand, from the bottom staffed job (%s)" % str(diff))
	var line := BackupsModel.staffing_cost_text(diff, vcfg["job_labels"], tx)
	t.ok(line == "staffing takes 1 hand from Stall", "backups: staffing cost line (%s)" % line)
	var views: Dictionary = pre
	var order: Array = TownBehaviour.effective(views["town"])
	var nohands := {"town": {"jobs": [{"id": "pit", "slots": 2, "staffed": 0.0}], "buildings": [], "workers": {"idle": 0.0}}}
	t.ok(TownBehaviour.staffing_diff(TownStandins.staffing_projection(nohands, ["pit"], cfg["buildings"])["jobs"],
		TownStandins.staffing_projection(nohands, ["pit"], cfg["buildings"], 1)["jobs"]).is_empty(), "backups: a vat with no hands to take from takes none")
	t.ok(BackupsModel.staffing_cost_text([], vcfg["job_labels"], tx) == "staffing takes no hand from a job", "backups: no hand moves, said so")
	# idle hands: every room is already full, so a vat slot is filled from idle and no job loses a hand
	var idle_town := {"jobs": [{"id": "pit", "slots": 2, "staffed": 2.0}, {"id": "stall", "slots": 2, "staffed": 2.0}, {"id": "mill", "slots": 2, "staffed": 2.0}],
		"buildings": [], "workers": {"idle": 10.0}}
	var idle_views := {"town": idle_town, "backups": {"vats": [{"slot": 0, "staffed": false}]}}
	var idle_order: Array = ["pit", "stall", "mill"]
	var idle_now: Dictionary = TownStandins.project(idle_views, idle_order, cfg["buildings"])
	var idle_on: Dictionary = TownStandins.project(idle_views, idle_order, cfg["buildings"], {0: true})
	var idle_diff := TownBehaviour.staffing_diff(idle_now["jobs"], idle_on["jobs"])
	t.ok(idle_diff.is_empty() and BackupsModel.staffing_cost_text(idle_diff, vcfg["job_labels"], tx, false, 10.0) == "10 idle hands: staffing costs nothing today",
		"backups: with 10 idle hands an unstaffed vat takes no hand from a job, and says so (%s)" % str(idle_diff))
	t.near(float(idle_now["idle"]), 10.0, 0.001, "backups: idle is the hands left over, not counted twice (now %s)" % str(idle_now["idle"]))
	t.near(float(idle_on["idle"]), 9.0, 0.001, "backups: staffing a vat from idle leaves 9 (%s)" % str(idle_on["idle"]))
	# the stand-in with nothing taken is unchanged
	t.ok(TownStandins.staffing_projection(views, order, cfg["buildings"], 0) == TownStandins.staffing_projection(views, order, cfg["buildings"]), "backups: taking 0 hands changes nothing")
	# the chapel's upkeep comes from the town view, not a constant
	var chapel := BackupsModel.chapel_upkeep(pre["town"]["buildings"], tx["chapel"])
	t.ok(not chapel.is_empty() and float(chapel["gold"]) > 0.0, "backups: the chapel's upkeep is read from view_town (%s)" % str(chapel))
	t.ok(BackupsModel.chapel_upkeep(day1["town"]["buildings"], tx["chapel"]).is_empty(), "backups: no chapel, no upkeep")
	# the real view on the fixtures: every outcome and loses id reads
	for v in [day1, pre]:
		var d: Dictionary = v["backups"]["death"]
		var txt := BackupsModel.outcome_text(d, tx)
		t.ok(txt != "" and BackupsModel.loses_list(d["loses"], tx).size() == (d["loses"] as Array).size(), "backups: the fixture's death reads: %s" % txt)


func _strokes_len(pls: Array) -> float:
	var n := 0.0
	for p in pls:
		for i in range(1, p.size()):
			n += p[i - 1].distance_to(p[i])
	return n


# ----------------------------------------------------------------- G3: deep levels ----
## A copy of buildings.json where `bid` has `top` levels (level_costs to L2..Ltop, each 1.6x the last).
func _deep_cfg(bid: String, top: int) -> Dictionary:
	var b: Dictionary = (cfg["buildings"] as Dictionary).duplicate(true)
	var lc: Array = b[bid]["level_costs"]
	while lc.size() < top - 1:
		var last: Dictionary = lc[lc.size() - 1]
		lc.append({"gold": float(last["gold"]) * 1.6, "bone": float(last["bone"]) * 1.6, "relics": 0})
	b[bid]["max_level"] = top
	return b


func _deep_levels(day1: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var deep := _deep_cfg("house", 8)
	var st := {"gold": 100000.0, "bone": 100000.0, "relics": 9.0, "max_level": {"house": 8}}
	var house := {"lot_id": "lot-05", "building_id": "house", "level": 5, "state": "active", "progress": 1.0, "slots": 0,
		"staffed": 0.0, "foreman": "", "upkeep": {"gold": 0.0, "bone": 0.0}}
	var i: Dictionary = BuildSort.inspect(house, st, deep, bv, vcfg)
	t.ok(i["max_level"] == 8 and i["level_text"] == "Level 5 of 8", "deep: the card/inspector reads 'Level 5 of 8' (%s)" % i["level_text"])
	t.ok(i["upgrade"]["enabled"] and i["upgrade"]["level"] == 6 and i["upgrade"]["cost"] == deep["house"]["level_costs"][4],
		"deep: 5 -> 6 costs level_costs[4]")
	for lv in range(1, 8):
		house["level"] = lv
		i = BuildSort.inspect(house, st, deep, bv, vcfg)
		t.ok(i["upgrade"]["enabled"] and i["upgrade"]["level"] == lv + 1 and i["upgrade"]["cost"] == deep["house"]["level_costs"][lv - 1],
			"deep: upgrade enabled from %d to %d with its own cost" % [lv, lv + 1])
	house["level"] = 8
	i = BuildSort.inspect(house, st, deep, bv, vcfg)
	t.ok(not i["upgrade"]["enabled"] and i["upgrade"]["reason"] == "max_level" and i["upgrade"]["cost"].is_empty() and i["level_text"] == "Level 8 of 8",
		"deep: at 8 the upgrade is refused with max_level")
	t.ok(vcfg["reasons"]["max_level"] == "already at its top level", "deep: max_level reads 'already at its top level'")
	t.ok(BuildSort.upgrade_cost(deep["house"], 8, 8).is_empty() and BuildSort.upgrade_cost(deep["house"], 7, 8) == deep["house"]["level_costs"][6],
		"deep: the per-level cost table at level 8 is empty, at 7 its last entry")
	t.ok(BuildSort.upgrade_cost(deep["house"], 9, 8).is_empty(), "deep: a level past the table never indexes out of range")
	# the catalog's max_level wins over buildings.json (which says 3)
	house["level"] = 5
	i = BuildSort.inspect(house, st, cfg["buildings"], bv, vcfg)
	t.ok(i["max_level"] == 8, "deep: max_level comes from view_catalog's stocks, not buildings.json")
	# a lot's output pips stay countable at 8 (the cap) with the integer beside them
	var po := TownModel.row_offsets(8, 5.0, 3.0, 4.0, 5)
	t.ok(po.size() == 8 and TownModel.count_label(8, 5) == "8", "deep: 8 pips are 8 marks in groups of 5 with the integer beside")
	t.ok(vcfg["pip_max"] >= 8, "deep: the pip cap holds 8")
	# the demo city and the stand-in queue take the top level from the config, whatever it is
	var dc := _deep_cfg("raising_pit", 8)
	var demo := TownStandins.demo_views(day1, dc, cfg["town"])
	var pit_ok := false
	for b in demo["town"]["buildings"]:
		if b["building_id"] == "raising_pit" and b["state"] == "active":
			pit_ok = pit_ok or (int(b["level"]) == 8 and int(b["slots"]) == int(dc["raising_pit"]["jobs"]["pit"]) * 8)
	t.ok(pit_ok, "deep: the demo city's job buildings stand at their top level (8)")
	var qc := {"gold": 1e6, "bone": 1e6, "relics": 9.0, "gold_cap": -1.0, "bone_cap": -1.0, "catalog": {"house": _row("house", true, "", [])},
		"built": {"lot-05": {"building_id": "house", "level": 7, "max_level": 8, "state": "active"}}, "gates": vcfg["gate_reasons"]}
	var q := TownStandins.BuildQueue.new(8, vcfg["cap_buildings"])
	var r: Dictionary = q.add({"building_id": "house", "lot_id": "lot-05", "upgrade": true, "level": 8, "cost": {"gold": 1.0, "bone": 1.0, "relics": 0}}, qc)
	t.ok(bool(r["ok"]), "deep: the queue takes an upgrade 7 -> 8")
	qc["built"]["lot-05"]["level"] = 8
	q.evaluate(qc)
	t.ok(q.entries[0]["status"] == "skipped_gate" and q.entries[0]["reason"] == "max_level", "deep: the queue skips an upgrade at 8 as max_level")



# ------------------------------------------------- G3: the suggestion prefers upgrading ----
## day1's views with a house built at `level` on a free lot (state `state`), the housing need live, plenty
## of funds, and a catalog where only well (first) and house are buildable, each on one free lot.
func _up_world(day1: Dictionary, level: int, state: String, gold := 1000.0, bone := 1000.0, house_max := 3) -> Dictionary:
	var v: Dictionary = day1.duplicate(true)
	var free: Array = []
	for l in v["town"]["lots"]:
		if bool(l["unlocked"]) and String(l["building_id"]) == "":
			free.append(String(l["id"]))
	# a quiet town: only the crypt stands, nobody idle, every stream flowing, so housing is the one live need
	v["town"]["buildings"] = (v["town"]["buildings"] as Array).filter(func(b): return b["building_id"] == "crypt")
	v["town"]["workers"]["idle"] = 0.0
	v["town"]["workers"]["muster"] = 0.0
	v["town"]["bodies"] = v["town"]["bodies_cap"]
	v["vei"]["fronts"] = []  # no front need (the fronts are live from E3-5), as _need_views
	for r in v["hud"]["rates"]:
		r["rate"] = 1.0
	var lot_h: String = free[0]
	var lot_new: String = free[1]
	for l in v["town"]["lots"]:
		if String(l["id"]) == lot_h:
			l["building_id"] = "house"
	v["town"]["buildings"].append({"lot_id": lot_h, "building_id": "house", "level": level, "state": state, "progress": 0.5 if state == "constructing" else 1.0,
		"slots": 0, "staffed": 0.0, "staff_cap": -1, "foreman": "", "output": {}, "upkeep": {"gold": 0.0, "bone": 0.0}})
	v["town"]["gold"] = gold
	v["town"]["bone"] = bone
	v["town"]["living_cap"] = 10.0
	v["town"]["living"] = 10.0  # the housing need is live
	v["hud"]["relics"] = 9
	v["inventory"]["relics"] = 9
	var rows: Array = []
	for bid in ["well", "house"]:
		var r := _row(bid, true, "", [lot_new])
		r["max_level"] = house_max
		r["cost"] = {"gold": 5.0, "bone": 1.0, "relics": 0}
		rows.append(r)
	for r in v["catalog"]["buildings"]:
		if not String(r["building_id"]) in ["well", "house"]:
			r["can_build"] = false
			r["reason"] = "needs_tier"
			rows.append(r)
	v["catalog"] = {"buildings": rows}
	v["_lot_h"] = lot_h
	v["_lot_new"] = lot_new
	return v


func _up_suggest(v: Dictionary, bc: Dictionary = {}, bv: Dictionary = {}) -> Dictionary:
	var bcfg: Dictionary = cfg["buildings"] if bc.is_empty() else bc
	var bview: Dictionary = cfg["buildings_view"] if bv.is_empty() else bv
	var nd := BuildSort.needs(v, {}, vcfg, bview, bcfg)
	var items := BuildSort.sort_rows(v["catalog"]["buildings"], nd, bview, vcfg)
	var ups := BuildSort.upgrade_items(v, nd, bview, bcfg, vcfg)
	return BuildSort.suggest(items, bview, BuildSort.stocks(v), vcfg, ups)


func _upgrade_first(day1: Dictionary) -> void:
	var v := _up_world(day1, 1, "active")
	var housing_live := false
	for n in BuildSort.needs(v, {}, vcfg, cfg["buildings_view"], cfg["buildings"]):
		housing_live = housing_live or String(n["id"]) == "housing"
	t.ok(housing_live, "upgrade first: the housing need is live in the test world")
	var lot_h: String = v["_lot_h"]
	var lot_new: String = v["_lot_new"]
	var s := _up_suggest(v)
	t.ok(bool(s.get("upgrade", false)) and s["building_id"] == "house" and s["lots"] == [lot_h] and s["level"] == 2,
		"upgrade first (a): the upgrade on the built house's lot beats a new house or well for the same need (%s)" % str(s))
	t.ok(s["label"].find("2") >= 0 and s["label"].find("House") >= 0, "upgrade first: the suggestion label says it is an upgrade to L2 (%s)" % s["label"])
	var nodes := BuildSort.upgrade_items(v, BuildSort.needs(v, {}, vcfg, cfg["buildings_view"], cfg["buildings"]), cfg["buildings_view"], cfg["buildings"], vcfg)
	t.ok(nodes.size() == 1 and nodes[0]["cls"] == BuildSort.CLS_NEED_BUILDABLE and nodes[0]["lot_id"] == lot_h, "upgrade first: one candidate, a buildable need row")
	# with the housing need dropped the upgrade is no candidate (it serves no live need)
	v["town"]["living"] = 0.0
	t.ok(BuildSort.upgrade_items(v, BuildSort.needs(v, {}, vcfg, cfg["buildings_view"], cfg["buildings"]), cfg["buildings_view"], cfg["buildings"], vcfg).is_empty(),
		"upgrade first: no live need served, no upgrade candidate")
	# (b) at max level -> the new build
	v = _up_world(day1, 3, "active")
	s = _up_suggest(v)
	t.ok(not s.has("upgrade") and s["building_id"] == "well" and s["lots"] == [v["_lot_new"]], "upgrade first (b): X at max_level -> the new build (%s)" % str(s))
	# deeper max_level from the catalog makes the same house a candidate again
	v = _up_world(day1, 3, "active", 1000.0, 1000.0, 8)
	t.ok(bool(_up_suggest(v, _deep_cfg("house", 8)).get("upgrade", false)), "upgrade first: max_level 8 from the catalog, with real level_costs, keeps a level-3 house a candidate")
	# (c) constructing or unpaid -> the new build
	for st_name in ["constructing", "unpaid"]:
		v = _up_world(day1, 1, st_name)
		s = _up_suggest(v)
		t.ok(not s.has("upgrade") and s["building_id"] == "well", "upgrade first (c): %s -> the new build (%s)" % [st_name, str(s)])
	# (d) the upgrade is short while a new build is buildable -> the new build (class order unchanged)
	v = _up_world(day1, 1, "active", 20.0, 1000.0)  # the new rows cost 5 gold, house L2 costs 80
	s = _up_suggest(v)
	t.ok(not s.has("upgrade") and s["building_id"] == "well", "upgrade first (d): short upgrade, buildable new row -> the new build (%s)" % str(s))
	# an upgrade ahead of a new build only inside the same class and need: a need-less new build stays behind
	v = _up_world(day1, 1, "active")
	t.ok(_up_suggest(v).get("upgrade", false), "upgrade first: the buildable need upgrade leads")
	# (e) autoplay returns upgrade + the building's lot; cmd_upgrade accepts it
	v = _up_world(day1, 1, "active")
	var pick: Dictionary = BuildSort.autoplay_pick(v, cfg)
	t.ok(bool(pick.get("upgrade", false)) and pick["lot_id"] == v["_lot_h"] and pick["building_id"] == "house",
		"upgrade first (e): autoplay_pick returns {building_id, lot_id, upgrade: true} (%s)" % str(pick))
	v = _up_world(day1, 3, "active")
	pick = BuildSort.autoplay_pick(v, cfg)
	t.ok(not pick.has("upgrade") and pick["building_id"] == "well", "upgrade first (e): a new build has no upgrade flag (%s)" % str(pick))
	t.ok(BuildSort.autoplay_why(_up_world(day1, 1, "active"), cfg).find("upgrade") >= 0, "upgrade first: the autoplay log line names the upgrade")


# ------------------------------------------------------------ gate-lot reservation ----
## A quiet town with lots of sizes 3 (lot-A), 1 (lot-B, lot-C), 2 (lot-D), a next tier needing `missing`
## (walls: lot_size 3, well: lot_size 1) and a catalog where house/well/walls are buildable on every free lot.
func _gate_world(day1: Dictionary, missing: Array, placed: Array = []) -> Dictionary:
	var v: Dictionary = day1.duplicate(true)
	var lots: Array = []
	for spec in [["lot-A", 3], ["lot-B", 1], ["lot-C", 1], ["lot-D", 2]]:
		lots.append({"id": spec[0], "size": spec[1], "unlocked": true, "building_id": ""})
	v["town"]["buildings"] = (v["town"]["buildings"] as Array).filter(func(b): return b["building_id"] == "crypt")
	for pb in placed:
		v["town"]["buildings"].append({"lot_id": "lot-D", "building_id": pb, "level": 1, "state": "constructing", "progress": 0.5,
			"slots": 0, "staffed": 0.0, "staff_cap": -1, "foreman": "", "output": {}, "upkeep": {"gold": 0.0, "bone": 0.0}})
	v["town"]["lots"] = lots
	v["town"]["next_tier"] = {"tier": "village", "have": 1, "need": 4, "missing": missing}
	v["town"]["gold"] = 1000.0
	v["town"]["bone"] = 1000.0
	v["town"]["workers"]["idle"] = 0.0
	v["town"]["workers"]["muster"] = 0.0
	var rows: Array = []
	for spec in [["walls", 3], ["well", 1], ["house", 1]]:
		var r := _row(spec[0], true, "", ["lot-A", "lot-B", "lot-C", "lot-D"].filter(func(l): return int(spec[1]) <= {"lot-A": 3, "lot-B": 1, "lot-C": 1, "lot-D": 2}[l]))
		r["lot_size"] = spec[1]
		rows.append(r)
	v["catalog"] = {"buildings": rows}
	return v


func _gate_lots(day1: Dictionary) -> void:
	var bc: Dictionary = cfg["buildings"]
	var v := _gate_world(day1, ["walls", "well"])
	var rs := BuildSort.reservation(v, bc)
	t.ok(rs["lots"] == {"lot-A": "walls", "lot-B": "well"} and rs["unfit"].is_empty(),
		"gate lots: a size-3 and a size-1 gate keep the size-3 lot and the smallest free lot (%s)" % str(rs))
	t.ok(BuildSort.reserved_lots(v, bc) == rs["lots"], "gate lots: reserved_lots is the reservation's lot map")
	# hops break a tie between equal-size lots: the nearer one is kept
	t.ok(BuildSort.reserved_lots(v, bc, {"lot-B": 5, "lot-C": 1}) == {"lot-A": "walls", "lot-C": "well"}, "gate lots: the nearer of two equal lots is kept")
	# a size not in the catalog falls back to buildings.json
	var v2 := _gate_world(day1, ["walls"])
	v2["catalog"]["buildings"] = []
	t.ok(BuildSort.reserved_lots(v2, {"walls": {"lot_size": 2}}) == {"lot-D": "walls"}, "gate lots: lot size from buildings.json when the catalog lacks the row")
	# a house suggestion never lands on a reserved lot; the gate building may
	var bview: Dictionary = cfg["buildings_view"]
	var nd := BuildSort.needs(v, {}, vcfg, bview, bc)
	var items := BuildSort.sort_rows(v["catalog"]["buildings"], nd, bview, vcfg)
	var sug := BuildSort.suggest(items, bview, {}, {}, [], rs["lots"])
	t.ok(not sug.is_empty() and sug["building_id"] in ["walls", "well"], "gate lots: the tier need leads (%s)" % str(sug))
	for l in sug["lots"]:
		t.ok(not rs["lots"].has(l) or rs["lots"][l] == sug["building_id"], "gate lots: the %s suggestion offers only lots free of other gates' (%s)" % [sug["building_id"], l])
	var house_only := items.filter(func(i): return i["row"]["building_id"] == "house")
	var hs := BuildSort.suggest(house_only, bview, {}, {}, [], rs["lots"])
	t.ok(hs["lots"] == ["lot-C", "lot-D"], "gate lots: a house is never offered the reserved lots (%s)" % str(hs))
	var well_only := items.filter(func(i): return i["row"]["building_id"] == "well")
	t.ok(BuildSort.suggest(well_only, bview, {}, {}, [], rs["lots"])["lots"] == ["lot-B", "lot-C", "lot-D"],
		"gate lots: the gate building keeps its own reserved lot and the free ones, loses the other gate's")
	var walls_only := items.filter(func(i): return i["row"]["building_id"] == "walls")
	t.ok(BuildSort.suggest(walls_only, bview, {}, {}, [], rs["lots"])["lots"] == ["lot-A"], "gate lots: walls may take its reserved lot")
	# the fallback (no live need) skips them: with the tier need gone only a house is buildable
	var v3 := _gate_world(day1, ["walls", "well"])
	v3["catalog"]["buildings"] = v3["catalog"]["buildings"].filter(func(r): return r["building_id"] == "house")
	var pick := BuildSort.autoplay_pick(v3, cfg)
	t.ok(not pick.is_empty() and pick["building_id"] == "house" and pick["lot_id"] in ["lot-C", "lot-D"],
		"gate lots: autoplay's house skips the reserved lots (%s)" % str(pick))
	t.ok(BuildSort.autoplay_why(v3, cfg).find("reserved=lot-A:walls,lot-B:well") >= 0, "gate lots: the autoplay log names the reserved lots (%s)" % BuildSort.autoplay_why(v3, cfg))
	# all non-gate lots reserved or taken: the house has no lot at all
	var v4 := _gate_world(day1, ["walls", "well"])
	v4["town"]["lots"] = v4["town"]["lots"].slice(0, 2)
	v4["catalog"]["buildings"] = v4["catalog"]["buildings"].filter(func(r): return r["building_id"] == "house")
	v4["catalog"]["buildings"][0]["lots"] = ["lot-A", "lot-B"]
	t.ok(BuildSort.autoplay_pick(v4, cfg).is_empty(), "gate lots: a house with only reserved lots left gets none")
	# a gate that fits no free lot reserves nothing and autoplay_why says so
	var v5 := _gate_world(day1, ["walls"])
	v5["town"]["lots"] = v5["town"]["lots"].filter(func(l): return l["id"] != "lot-A")
	rs = BuildSort.reservation(v5, bc)
	t.ok(rs["lots"].is_empty() and rs["unfit"] == ["walls"], "gate lots: a gate no free lot fits reserves nothing and is listed unfit (%s)" % str(rs))
	t.ok(BuildSort.autoplay_why(v5, cfg).find("no_lot_for_gate=walls") >= 0, "gate lots: autoplay_why says the gate has no lot")
	# nothing reserved: empty next_tier (top tier), no missing, built or constructing gates
	var v6 := _gate_world(day1, [])
	t.ok(BuildSort.reserved_lots(v6, bc).is_empty(), "gate lots: nothing missing reserves nothing")
	v6["town"]["next_tier"] = {}
	t.ok(BuildSort.reserved_lots(v6, bc).is_empty(), "gate lots: an empty next_tier (top tier) reserves nothing")
	v6 = _gate_world(day1, ["walls", "well"], ["walls"])
	t.ok(BuildSort.reserved_lots(v6, bc) == {"lot-B": "well"},
		"gate lots: a gate under construction reserves nothing; the size-1 well still keeps the smallest free lot, lot-B (%s)" % str(BuildSort.reserved_lots(v6, bc)))
	t.ok(not BuildSort.reserved_lots(v6, bc).values().has("walls"), "gate lots: the constructing walls keeps no lot")
	v6 = _gate_world(day1, ["walls", "well"], ["walls", "well"])
	t.ok(BuildSort.reserved_lots(v6, bc).is_empty(), "gate lots: every gate placed reserves nothing")
	# the lot card note
	t.ok(BuildSort.reserved_note("lot-A", rs, bview, vcfg) == "" and BuildSort.reserved_note("lot-A", {"lot-A": "walls"}, bview, vcfg) == "kept for %s (next tier)" % BuildSort.label_of("walls", bview),
		"gate lots: the empty lot card names the gate the lot is kept for")


# ------------------------------------------- Fix 3a: suggestion, build panel, HUD ----
func _row_of(v: Dictionary, bid: String) -> Dictionary:
	for r in v["catalog"]["buildings"]:
		if r["building_id"] == bid:
			return r
	return {}


## Item 1: an upgrade serves what one more level adds (buildings_view `upgrade_serves`), not what the
## building was built for.
func _fix3a_serves(day1: Dictionary, mid: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var bc: Dictionary = cfg["buildings"]
	# the audit, from the data: a level adds `jobs × level` and numeric `effects × level` (array effects are
	# per-level tables); only a building whose levels add neither needs its own `upgrade_serves`
	for bid in bc:
		var d: Dictionary = bc[bid]
		if int(d.get("max_level", 1)) <= 1:
			continue
		var levelled: bool = not (d.get("jobs", {}) as Dictionary).is_empty() or not (d.get("effects", {}) as Dictionary).is_empty()
		t.ok(bv[bid].has("upgrade_serves") == not levelled,
			"upgrade serves: %s %s (jobs/effects per level: %s)" % [bid, "inherits its serves" if levelled else "has its own upgrade_serves", str(levelled)])
	t.ok(bv["crypt"]["upgrade_serves"] == [] and bc["crypt"]["jobs"].is_empty() and bc["crypt"]["effects"].is_empty(),
		"upgrade serves: the Crypt's levels serve no need (+1 big-undead cap)")
	var plain: Dictionary = bv.duplicate(true)
	plain["crypt"].erase("upgrade_serves")
	t.ok(BuildSort.upgrade_serves("crypt", plain) == ["front", "warden", "building:crypt"], "upgrade serves: absent upgrade_serves inherits serves (%s)" % str(BuildSort.upgrade_serves("crypt", plain)))
	t.ok(BuildSort.upgrade_serves("house", bv) == ["housing", "building:house"], "upgrade serves: a building without upgrade_serves inherits (house)")
	t.ok(BuildSort.upgrade_serves("crypt", bv) == ["building:crypt"], "upgrade serves: [] serves nothing but its own building tag")
	var own: Dictionary = bv.duplicate(true)
	own["house"]["upgrade_serves"] = ["morale"]
	t.ok(BuildSort.upgrade_serves("house", own) == ["morale", "building:house"], "upgrade serves: upgrade_serves replaces serves for the upgrade")
	# midgame_2flips: the tithe need is live and the Crypt's L2 is affordable: it must not be a candidate
	var nd := BuildSort.needs(mid, mid["fort_names"], vcfg, bv, bc)
	t.ok("tithe" in _need_ids_of(nd), "upgrade serves: midgame_2flips has the tithe need live (%s)" % str(_need_ids_of(nd)))
	var ups := BuildSort.upgrade_items(mid, nd, bv, bc, vcfg)
	var crypt_ups := ups.filter(func(u): return u["row"]["building_id"] == "crypt")
	t.ok(crypt_ups.is_empty(), "upgrade serves: midgame_2flips offers no Crypt upgrade (%s)" % str(ups.map(func(u): return u["row"]["building_id"])))
	var old := BuildSort.upgrade_items(mid, BuildSort.needs(mid, mid["fort_names"], vcfg, plain, bc), plain, bc, vcfg).filter(func(u): return u["row"]["building_id"] == "crypt")
	t.ok(not old.is_empty() and old[0]["cls"] == BuildSort.CLS_NEED_BUILDABLE, "upgrade serves: (without upgrade_serves the Crypt L2 was the affordable need candidate)")
	var sug: Dictionary = BuildSort.tab_suggestion(mid, bv, bc, vcfg)["sug"]
	t.ok(not (bool(sug.get("upgrade", false)) and sug.get("building_id", "") == "crypt"), "upgrade serves: midgame_2flips' suggestion is not a Crypt upgrade (%s)" % str(sug))
	# a job building's upgrade still serves idle hands
	var v := _up_world(day1, 1, "active")
	for b in v["town"]["buildings"]:
		if b["lot_id"] == v["_lot_h"]:
			b["building_id"] = "market"
			b["slots"] = 2
	for l in v["town"]["lots"]:
		if l["id"] == v["_lot_h"]:
			l["building_id"] = "market"
	v["town"]["living"] = 0.0
	v["town"]["workers"]["idle"] = 6.0
	v["town"]["next_tier"] = {}  # no tier need ahead of idle_hands
	var jn := BuildSort.needs(v, {}, vcfg, bv, bc)
	var jups := BuildSort.upgrade_items(v, jn, bv, bc, vcfg)
	t.ok(_need_ids_of(jn) == ["idle_hands"] and jups.size() == 1 and jups[0]["row"]["building_id"] == "market" and jups[0]["need"] == "idle_hands",
		"upgrade serves: a built Market's upgrade serves idle_hands (%s)" % str(jups.map(func(u): return [u["row"]["building_id"], u["need"]])))
	var js := _up_suggest(v)
	t.ok(bool(js.get("upgrade", false)) and js["building_id"] == "market" and js["level"] == 2, "upgrade serves: ... and leads the suggestion (%s)" % str(js))


## Item 2: one marked helper for the build work of a site; the view's own numbers win.
func _fix3a_work() -> void:
	var row := {"building_id": "house", "build_work": 60.0}
	var w := BuildSort.site_work(row, 1)
	t.ok(is_equal_approx(w["total"], 60.0) and is_equal_approx(w["left"], 60.0), "site work: the stand-in is build_work × target level (L1: 60)")
	t.ok(is_equal_approx(BuildSort.site_work(row, 3)["total"], 180.0), "site work: ... L3: 180")
	var constructing := {"state": "constructing", "progress": 0.25}
	w = BuildSort.site_work(row, 2, constructing)
	t.ok(is_equal_approx(w["total"], 120.0) and is_equal_approx(w["left"], 90.0), "site work: stand-in left = total × (1 − progress)")
	var rw := row.duplicate()
	rw["work"] = 45.0
	t.ok(is_equal_approx(BuildSort.site_work(rw, 1)["total"], 45.0), "site work: a catalog row's `work` wins for a new build")
	t.ok(is_equal_approx(BuildSort.site_work(rw, 2)["total"], 120.0), "site work: ... but is no upgrade's work")
	t.ok(is_equal_approx(BuildSort.site_work(row, 2, {"state": "active", "upgrade_work": 77.0})["total"], 77.0), "site work: the built entry's `upgrade_work` wins for an upgrade")
	var lf := {"state": "constructing", "progress": 0.25, "work_left": 12.0}
	t.ok(is_equal_approx(BuildSort.site_work(row, 1, lf)["left"], 12.0), "site work: a constructing entry's `work_left` wins")
	var cat := {"house": rw}
	var e := {"building_id": "house", "lot_id": "lot-05", "upgrade": false, "level": 1}
	t.ok(is_equal_approx(BuildSort.entry_work(e, cat, {}), 45.0), "site work: entry_work takes the catalog `work`")
	t.ok(is_equal_approx(BuildSort.entry_work(e, cat, {"buildings": [{"lot_id": "lot-05", "building_id": "house", "state": "constructing", "level": 0, "progress": 0.5, "work_left": 7.0}]}), 7.0),
		"site work: entry_work takes `work_left` while the lot is constructing it")
	var up := {"building_id": "house", "lot_id": "lot-05", "upgrade": true, "level": 2}
	t.ok(is_equal_approx(BuildSort.entry_work(up, cat, {"buildings": [{"lot_id": "lot-05", "building_id": "house", "state": "active", "level": 1, "upgrade_work": 99.0}]}), 99.0),
		"site work: entry_work takes the built entry's `upgrade_work` for an upgrade")
	# the throughput reads the view's work counter when both samples have it
	var at := func(tt: float, progress: float, left: float) -> Dictionary:
		return {"hud": {"t": tt}, "catalog": {"buildings": [{"building_id": "house", "build_work": 60.0}]},
			"town": {"buildings": [{"lot_id": "lot-05", "building_id": "house", "level": 0, "state": "constructing", "progress": progress, "work_left": left}]}}
	var tp := BuildSort.Throughput.new(10.0)
	tp.observe(at.call(10.0, 0.2, 50.0))
	tp.observe(at.call(20.0, 0.3, 30.0))
	t.ok(is_equal_approx(tp.rate, 2.0), "site work: the throughput is Δwork_left ÷ Δt when the view has it (%.3f, not the stand-in's 0.6)" % tp.rate)


## Item 3 and 6: the HUD's idle line reads the Build tab's suggestion, handed over once.
func _fix3a_hud(day1: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var bc: Dictionary = cfg["buildings"]
	var mk := func(rows: Array, gold: float, missing: Array = []) -> Dictionary:
		return {"town": {"workers": {"idle": 10.0, "muster": 0.1}, "gold": gold, "bone": 1000.0, "jobs": [], "lots": [],
			"next_tier": {"tier": "village", "have": 1, "need": 2, "missing": missing} if not missing.is_empty() else {},
			"buildings": [{"lot_id": "lot-07", "building_id": "market", "level": 1, "state": "active", "progress": 1.0, "slots": 2, "staffed": 2.0}]},
			"hud": {"rates": [{"id": "gold", "rate": 0.2}, {"id": "bone", "rate": 0.2}], "relics": 0}, "catalog": {"buildings": rows}, "fort_names": {}}
	var rows := [_row("house", true, "", ["lot-05"]), _row("market", false, "no_gold", ["lot-08"])]
	var p: Array = HudModel.idle_parts(mk.call(rows, 1000.0), vcfg, bv, bc)
	t.ok(HudModel.parts_text(p) == "10 idle: upgrade the Market to L2 (+%d jobs) or let them muster" % BuildSort.job_slots("market", bc) and p.size() == 1,
		"hud idle: the best use is a job upgrade, the Build tab's suggestion (%s)" % HudModel.parts_text(p))
	t.ok(HudModel.parts_text(HudModel.idle_parts(mk.call(rows, 10.0), vcfg, bv, bc)) == "10 idle: no job building affordable; mustering to FLOOD (Vei's queue)",
		"hud idle: an upgrade that can't be paid for is no job building affordable")
	# a suggestion with no jobs (the tier's House) leaves the line on the first buildable job item
	var jrows := [_row("house", true, "", ["lot-05"]), _row("charnel_house", true, "", ["lot-06"]), _row("market", false, "no_gold", ["lot-08"])]
	var tier: Dictionary = mk.call(jrows, 10.0, ["house"])
	t.ok(BuildSort.tab_suggestion(tier, bv, bc, vcfg)["sug"]["building_id"] == "house", "hud idle: (the tier's House is the suggestion)")
	t.ok(HudModel.parts_text(HudModel.idle_parts(tier, vcfg, bv, bc)).begins_with("10 idle: build a Charnel House ("), "hud idle: a non-job suggestion falls to the first buildable job item")
	# the line reads the tab it is given, no second needs + sort
	var v: Dictionary = mk.call(rows, 1000.0)
	var tab := BuildSort.tab_suggestion(v, bv, bc, vcfg)
	tab["sug"] = {"building_id": "charnel_house", "label": "Charnel House", "lots": ["lot-06"]}
	t.ok(HudModel.parts_text(HudModel.idle_parts(v, vcfg, bv, bc, tab)).begins_with("10 idle: build a Charnel House ("), "hud idle: the line reads the given tab")
	var stuck_rows := [_row("house", false, "no_gold", ["lot-05"])]
	var sv: Dictionary = mk.call(stuck_rows, 1000.0)
	sv["hud"]["rates"] = [{"id": "gold", "rate": 0.0}, {"id": "bone", "rate": 0.2}]
	var real_stuck := HudModel.bottleneck(sv, vcfg, bv, bc)
	t.ok(not real_stuck.is_empty() and HudModel.bottleneck(sv, vcfg, bv, bc, BuildSort.tab_suggestion(sv, bv, bc, vcfg)) == real_stuck,
		"hud bottleneck: reads the given tab's sorted rows, the same result as computing its own (%s)" % str(real_stuck))


## Items 4 and 9, and the G3 test gaps.
func _fix3a_upgrades(day1: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var bc: Dictionary = cfg["buildings"]
	# 9: the chip names no lot
	var s := _up_suggest(_up_world(day1, 1, "active"))
	t.ok(s["chip"] == "suggested: upgrade to L2" and not String(s["chip"]).contains("lot-"), "chip: reads 'suggested: upgrade to L2', no raw lot id (%s)" % s["chip"])
	# 4: past the cost table is not upgradable (on a copy with the house's level_costs cut to two: the shipped
	# house has a cost for every level since economy's T7)
	var bc2: Dictionary = bc.duplicate(true)
	bc2["house"]["level_costs"] = (bc2["house"]["level_costs"] as Array).slice(0, 2)
	var st := {"gold": 1e6, "bone": 1e6, "relics": 9.0, "max_level": {"house": 8}}
	var house := {"lot_id": "lot-05", "building_id": "house", "level": 3, "state": "active", "progress": 1.0, "slots": 0,
		"staffed": 0.0, "foreman": "", "upkeep": {"gold": 0.0, "bone": 0.0}}
	var i := BuildSort.inspect(house, st, bc2, bv, vcfg)
	t.ok(i["upgrade"]["reason"] == "no_cost" and not i["upgrade"]["enabled"] and not i["upgrade"]["can_queue"] and i["upgrade"]["cost"].is_empty(),
		"no cost: past level_costs the upgrade is refused, not free (%s)" % str(i["upgrade"]))
	t.ok(BuildSort.reason_text("no_cost", {"level": i["upgrade"]["level"]}, st, bv, vcfg) == "no cost set for L4", "no cost: the reason reads 'no cost set for L4'")
	var v := _up_world(day1, 3, "active", 1000.0, 1000.0, 8)
	t.ok(BuildSort.upgrade_items(v, BuildSort.needs(v, {}, vcfg, bv, bc2), bv, bc2, vcfg).is_empty(), "no cost: past the table is no upgrade candidate")
	t.ok(not _up_suggest(v, bc2).has("upgrade"), "no cost: ... and no free upgrade suggestion")
	# 8a: an upgrade never outranks a higher-ranked need's new build
	v = _up_world(day1, 1, "active")
	_set_rate(v, "gold", -0.05)  # the gold need ranks above housing
	var mrow := _row_of(v, "market")
	mrow["can_build"] = true
	mrow["reason"] = ""
	mrow["lots"] = [v["_lot_new"]]
	mrow["cost"] = {"gold": 5.0, "bone": 1.0, "relics": 0}
	var nd := BuildSort.needs(v, {}, vcfg, bv, bc)
	s = _up_suggest(v)
	t.ok(_need_ids_of(nd).find("gold") >= 0 and _need_ids_of(nd).find("gold") < _need_ids_of(nd).find("housing"), "up gaps: the gold need ranks above housing (%s)" % str(_need_ids_of(nd)))
	t.ok(not s.has("upgrade") and s["building_id"] == "market", "up gaps: the buildable house upgrade (housing) does not outrank the Market (gold) (%s)" % str(s))
	# 8b: short of bone -> CLS_NEED_SHORT
	v = _up_world(day1, 1, "active", 1000.0, 5.0)
	var ups := BuildSort.upgrade_items(v, BuildSort.needs(v, {}, vcfg, bv, bc), bv, bc, vcfg)
	t.ok(ups.size() == 1 and ups[0]["cls"] == BuildSort.CLS_NEED_SHORT and ups[0]["row"]["reason"] == "no_bone" and not ups[0]["row"]["can_build"],
		"up gaps: an upgrade short of bone is CLS_NEED_SHORT with no_bone")
	# 8c: short of relics -> CLS_NEED_SHORT and never a save-for target
	var rc: Dictionary = bc.duplicate(true)
	rc["house"]["level_costs"][0]["relics"] = 1
	v = _up_world(day1, 1, "active")
	v["hud"]["relics"] = 0
	v["inventory"]["relics"] = 0
	ups = BuildSort.upgrade_items(v, BuildSort.needs(v, {}, vcfg, bv, rc), bv, rc, vcfg)
	t.ok(ups.size() == 1 and ups[0]["cls"] == BuildSort.CLS_NEED_SHORT and ups[0]["row"]["reason"] == "no_relics", "up gaps: an upgrade short of relics is CLS_NEED_SHORT with no_relics")
	s = _up_suggest(v, rc)
	t.ok(not s.has("save") and not s.has("upgrade"), "up gaps: ... and the suggestion is the buildable new row, not a save (%s)" % str(s))
	for r in v["catalog"]["buildings"]:
		r["can_build"] = false
		r["reason"] = "needs_tier"
	s = _up_suggest(v, rc)
	t.ok(s.is_empty(), "up gaps: with nothing else buildable a relic-short upgrade is never saved for (%s)" % str(s))
	# 8d: a gold-short upgrade is the save-for target, labelled as an upgrade
	v = _up_world(day1, 1, "active", 20.0, 1000.0)
	for r in v["catalog"]["buildings"]:
		r["can_build"] = false
		r["reason"] = "needs_tier"
	s = _up_suggest(v)
	t.ok(bool(s.get("save", false)) and bool(s.get("upgrade", false)) and s["building_id"] == "house" and s["lots"] == [v["_lot_h"]] and String(s["label"]).begins_with("save for upgrade House to L2 (~"),
		"up gaps: a short upgrade is saved for, 'save for upgrade House to L2 (~...)' (%s)" % str(s))
	t.ok(BuildSort.autoplay_pick(v, cfg).is_empty(), "up gaps: the autoplayer waits for it")


## Items 5 and 7 (the lot a Queue click takes, a lot of unknown size).
func _fix3a_lots(day1: Dictionary) -> void:
	t.ok(BuildSort.nearest_lot(["lot-x", "lot-09"], {}, {"lot-09": 1}) == "lot-09", "nearest lot: a lot with no known size sorts last, not first")
	t.ok(BuildSort.nearest_lot(["lot-x", "lot-y"], {"lot-x": 4.0, "lot-y": 2.0}, {"lot-09": 1}) == "lot-y", "nearest lot: two unknown sizes fall back to the hops")
	t.ok(BuildSort.nearest_lot(["lot-x", "lot-y"], {}, {}) == "lot-x", "nearest lot: no sizes at all keeps the first")
	var row := {"building_id": "house", "lots": ["lot-09", "lot-23", "lot-05"]}
	var sizes := {"lot-09": 1, "lot-23": 3, "lot-05": 1}
	var hops := {"lot-09": 3.0, "lot-23": 1.0, "lot-05": 2.0}
	t.ok(BuildSort.queue_lot(row, {}, {}, hops, sizes) == "lot-05", "queue lot: the smallest free lot, then the nearest (not lots[0], not the 3-lot)")
	t.ok(BuildSort.queue_lot(row, {"lot-05": true}, {}, hops, sizes) == "lot-09", "queue lot: a lot already queued is skipped")
	t.ok(BuildSort.queue_lot(row, {}, {"lot-05": "walls"}, hops, sizes) == "lot-09", "queue lot: another building's reserved lot is left alone")
	var wrow := {"building_id": "walls", "lots": ["lot-05", "lot-23"]}
	t.ok(BuildSort.queue_lot(wrow, {}, {"lot-23": "walls"}, hops, {"lot-05": 3, "lot-23": 3}) == "lot-23", "queue lot: the gate building takes its own reserved lot (nearest of equals)")
	t.ok(BuildSort.queue_lot(row, {}, {"lot-05": "walls", "lot-09": "well", "lot-23": "inn"}, hops, sizes) == "lot-05", "queue lot: with every lot reserved the button still works (the smallest, nearest)")
	t.ok(BuildSort.queue_lot(row, {"lot-05": true, "lot-09": true, "lot-23": true}, {}, hops, sizes) == "", "queue lot: no free lot gives none")
	t.ok(BuildSort.queue_lot({"building_id": "house", "lots": ["lot-zz", "lot-09"]}, {}, {}, {}, sizes) == "lot-09", "queue lot: a lot of unknown size goes last")
	t.ok(BuildSort.lot_sizes(day1).size() == day1["town"]["lots"].size() and BuildSort.lot_sizes(day1)["lot-02"] == int(day1["town"]["lots"][1]["size"]), "queue lot: lot_sizes reads view_town's lots")


## Items 10 and 11: the panel and the autoplayer keep the same lots; `_save_for` and `_variety_save` respect them.
func _fix3a_reserve(day1: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var bc: Dictionary = cfg["buildings"]
	# the shell's `lot_hops` break ties between equal lots, as the autoplayer's do
	var w := _gate_world(_need_views(day1), ["well"])
	t.ok(BuildSort.tab_suggestion(w, bv, bc, vcfg)["reserved"] == {"lot-B": "well"}, "same lots: without hops the first listed of equal lots is kept")
	w["lot_hops"] = {"lot-B": 5.0, "lot-C": 1.0}
	t.ok(BuildSort.tab_suggestion(w, bv, bc, vcfg)["reserved"] == {"lot-C": "well"}, "same lots: views.lot_hops breaks the tie, the nearer lot is kept")
	# the real town: the panel's reservation (hops from the shell) is the autoplayer's
	var v: Dictionary = day1.duplicate(true)
	v["town"]["next_tier"] = {"tier": "village", "have": 1, "need": 2, "missing": ["well"]}
	var maps := BuildSort.lot_maps(v, cfg)
	v["lot_hops"] = maps["hops"]
	var panel: Dictionary = BuildSort.tab_suggestion(v, bv, bc, vcfg)["reserved"]
	t.ok(panel.size() == 1 and panel.values() == ["well"], "same lots: the real town reserves a lot for the missing Well (%s)" % str(panel))
	var line: Array = []
	for l in panel:
		line.append("%s:%s" % [l, panel[l]])
	t.ok(BuildSort.autoplay_why(v, cfg).find("reserved=" + ",".join(line)) >= 0, "same lots: the autoplayer reserves exactly the panel's lots (%s | %s)" % [str(panel), BuildSort.autoplay_why(v, cfg)])
	t.ok(BuildSort.reserved_lots(v, bc, maps["hops"]) == panel, "same lots: reserved_lots with the shared hops is the panel's")
	t.ok(BuildSort.tab_suggestion(v, bv, bc, vcfg)["sug"] == BuildSort.tab_suggestion(v, bv, bc, vcfg, maps["hops"])["sug"], "same lots: ... and so is the suggestion")
	# _save_for: a need row whose only lot is kept for the gate is not saved for
	var base := _need_views(day1)
	var sv := _gate_world(base, ["walls"])
	_set_rate(sv, "gold", 0.5)
	_set_rate(sv, "bone", 0.5)
	sv["town"]["gold"] = 5.0
	sv["town"]["morale"] = {"value": 0.1, "target": 0.8, "factors": []}
	var inn := _row("inn", false, "no_gold", ["lot-A"])
	inn["lot_size"] = 1
	var house := _row("house", true, "", ["lot-B", "lot-C", "lot-D"])
	sv["catalog"] = {"buildings": [inn, house]}
	var nd := BuildSort.needs(sv, {}, vcfg, bv, bc)
	var items := BuildSort.sort_rows(sv["catalog"]["buildings"], nd, bv, vcfg)
	var st := BuildSort.stocks(sv)
	var free := BuildSort.suggest(items, bv, st, vcfg)
	t.ok("morale" in _need_ids_of(nd) and bool(free.get("save", false)) and free["building_id"] == "inn", "reserve: (without the reservation the Inn is saved for: %s)" % str(free))
	var tab := BuildSort.tab_suggestion(sv, bv, bc, vcfg)
	t.ok(tab["reserved"] == {"lot-A": "walls"}, "reserve: the Walls keep lot-A (%s)" % str(tab["reserved"]))
	t.ok(not tab["sug"].has("save") and tab["sug"]["building_id"] == "house" and tab["sug"]["lots"] == ["lot-B", "lot-C", "lot-D"],
		"reserve: _save_for skips a need row whose only lot is reserved; the suggestion falls to the House (%s)" % str(tab["sug"]))
	# _variety_save: an unbuilt type whose only lot is reserved is not saved for
	var vv := _gate_world(base, ["walls"])
	_set_rate(vv, "gold", 0.5)
	_set_rate(vv, "bone", 0.5)
	vv["town"]["gold"] = 5.0
	var market := _row("market", false, "no_gold", ["lot-A"])
	market["lot_size"] = 1
	var h2 := _row("house", true, "", ["lot-B", "lot-C", "lot-D"])
	h2["count"] = 2
	vv["catalog"] = {"buildings": [market, h2]}
	items = BuildSort.sort_rows(vv["catalog"]["buildings"], BuildSort.needs(vv, {}, vcfg, bv, bc), bv, vcfg)
	free = BuildSort.suggest(items, bv, BuildSort.stocks(vv), vcfg)
	t.ok(bool(free.get("save", false)) and free["building_id"] == "market", "reserve: (without the reservation the third House gives way to saving for the Market: %s)" % str(free))
	tab = BuildSort.tab_suggestion(vv, bv, bc, vcfg)
	t.ok(not tab["sug"].has("save") and tab["sug"]["building_id"] == "house", "reserve: _variety_save skips a type whose only lot is reserved (%s)" % str(tab["sug"]))


# ------------------------------------------------------- sound and set pieces ----
func _sound_math() -> void:
	t.suite("town-sound")
	# the rate limiter: sparse whatever the arc rate
	var last := -1.0
	var fired := 0
	for i in 600:  # 30 arcs a second for 20 s
		var now := float(i) / 30.0
		if TownSound.allow(now, last, 1.5):
			last = now
			fired += 1
	t.ok(fired == 14 or fired == 13, "limiter: 30 arcs/s for 20 s at a 1.5 s gap sounds %d blips, not 600" % fired)
	t.ok(TownSound.allow(0.0, -1.0, 1.5), "limiter: the first blip always sounds")
	t.ok(not TownSound.allow(1.49, 0.0, 1.5) and TownSound.allow(1.5, 0.0, 1.5), "limiter: exactly a gap apart passes, closer does not")
	t.ok(TownSound.allow(0.1, 0.0, 0.0), "limiter: a zero gap lets everything through")
	# the beat
	t.ok(TownSound.beat_index(0.0, 1714.0) == 0 and TownSound.beat_index(1713.0, 1714.0) == 0 and TownSound.beat_index(1714.0, 1714.0) == 1,
		"beat: the index steps once per tempo")
	t.ok(TownSound.beat_index(100.0, 0.0) == 0, "beat: a zero tempo never divides")
	# event -> kind
	var s: Dictionary = cfg["town"].get("sound", {})
	t.ok(TownSound.kind_for(s, "tier_up") == "horn" and TownSound.kind_for(s, "nope") == "", "kind_for: the configured kind, \"\" for an unmapped event")
	t.ok(TownSound.kind_for({}, "tier_up") == "", "kind_for: no sound block, no kind")


func _sound_cfg() -> void:
	var s: Dictionary = cfg["town"].get("sound", {})
	t.ok(not s.is_empty(), "town.json has a sound block")
	t.ok(not s.has("mute") and not s.has("volume_db"), "sound has no mute or volume of its own: the Synth owns them (AudioPrefs, M)")
	var kinds: Dictionary = s.get("kinds", {})
	var missing: Array = []
	for e in ["tier_up", "raise_hold", "raise_grow", "raise_done", "trade_blip", "beat"]:
		if not kinds.has(e):
			missing.append(e)
	t.ok(missing.is_empty(), "sound.kinds maps every town event: missing %s" % str(missing))
	var bad: Array = []
	var synth_cfg: Dictionary = TestUtil.load_json("res://configs/synth.json")
	for e in kinds:
		if not SynthLogic.KINDS.has(kinds[e]) or not (synth_cfg["kinds"] as Dictionary).has(kinds[e]):
			bad.append("%s -> %s" % [e, kinds[e]])
	t.ok(bad.is_empty(), "every mapped kind is one the shared Synth renders: %s" % str(bad))
	t.ok(float(s.get("trade_min_gap_s", 0.0)) >= 1.0, "trade blips are at least a second apart")
	t.ok(float(synth_cfg["kinds"][kinds.get("beat", "pulse")]["gain_db"]) <= -20.0, "the beat's kind is very quiet (gain_db <= -20)")
	for k in ["walkout", "raise_echo"]:
		t.ok(vcfg.has(k), "view.%s exists" % k)
	var w: Dictionary = vcfg.get("walkout", {})
	var miss: Array = []
	for k in ["speed_mul", "trail_px", "trail_segs", "trail_w_px", "trail_alpha", "badge_px", "badge_pad_px", "badge_gap_px", "badge_fade_s"]:
		if not w.has(k):
			miss.append(k)
	t.ok(miss.is_empty() and int(w.get("badge_px", 0)) >= 12, "view.walkout has its keys, badge text >= 12 px: %s" % str(miss))
	var pv: Dictionary = vcfg.get("crypt", {}).get("preview", {})
	t.ok(int(pv.get("morph_pts", 0)) >= 8, "preview.morph_pts: points per stroke in the ring-to-outline morph")


func _morph_math() -> void:
	t.suite("town-morph")
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	var r := TownSetPiece.resample(line, 5)
	t.ok(r.size() == 5 and r[0] == Vector2(0, 0) and r[4] == Vector2(10, 10), "resample: n points, both ends kept")
	t.near(r[2].distance_to(Vector2(10, 0)), 0.0, 1e-4, "resample: even spacing along the length (the corner is the middle of 20 px)")
	t.ok(TownSetPiece.resample(PackedVector2Array([Vector2(3, 3)]), 4).size() == 4, "resample: a lone point repeats")
	t.ok(TownSetPiece.resample(PackedVector2Array(), 4).size() == 0, "resample: nothing in, nothing out")
	var strokes: Array = [
		PackedVector2Array([Vector2(0, 0), Vector2(30, 0)]),
		PackedVector2Array([Vector2(30, 0), Vector2(30, 10), Vector2(0, 10)]),
	]
	var c := Vector2(100, 100)
	var rad := 50.0
	var arcs := TownSetPiece.morph(c, rad, strokes, 0.0, 12)
	t.ok(arcs.size() == 2, "morph: one arc per outline stroke")
	var all_on_ring := true
	for a in arcs:
		for p in a:
			all_on_ring = all_on_ring and absf(p.distance_to(c) - rad) < 1e-3
	t.ok(all_on_ring, "morph k=0: every point is on the ring")
	t.near(arcs[0][arcs[0].size() - 1].distance_to(arcs[1][0]), 0.0, 1e-3, "morph k=0: arc 0 ends where arc 1 starts (no gap in the ring)")
	t.near(arcs[1][arcs[1].size() - 1].distance_to(arcs[0][0]), 0.0, 1e-3, "morph k=0: and arc 1 closes back on arc 0 (a whole ring)")
	var len0 := TownSetPiece.poly_len(arcs[0])
	var len1 := TownSetPiece.poly_len(arcs[1])
	t.ok(len1 > len0 * 1.2, "morph: an arc's length follows its stroke's length (30 vs 40 px: %.0f vs %.0f)" % [len0, len1])
	var fin := TownSetPiece.morph(c, rad, strokes, 1.0, 12)
	var landed := true
	for j in 2:
		var want := TownSetPiece.resample(strokes[j], 12)
		for i in 12:
			landed = landed and fin[j][i].distance_to(want[i]) < 1e-3
	t.ok(landed, "morph k=1: ring point i is on outline point i of its stroke (the ring is the creature)")
	var mid := TownSetPiece.morph(c, rad, strokes, 0.5, 12)
	var want_mid: Vector2 = (arcs[0][3] + fin[0][3]) * 0.5
	t.near(mid[0][3].distance_to(want_mid), 0.0, 1e-3, "morph k=0.5: half-way between ring and outline")
	var empty := TownSetPiece.morph(c, rad, [], 0.5, 12)
	t.ok(empty.size() == 1 and empty[0].size() > 3, "morph: no outline, one plain ring")
	t.ok(TownSetPiece.ease_in(0.0) == 0.0 and TownSetPiece.ease_in(1.0) == 1.0 and TownSetPiece.ease_in(0.5) < 0.5, "ease: gathers speed, ends at 1")


func _walk_math() -> void:
	t.suite("town-walk")
	var p := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 50)])
	t.near(TownSetPiece.poly_len(p), 150.0, 1e-6, "walk: path length")
	t.ok(TownSetPiece.point_at(p, 0.0) == Vector2(0, 0) and TownSetPiece.point_at(p, 100.0) == Vector2(100, 0), "walk: point at distance")
	t.ok(TownSetPiece.point_at(p, 125.0) == Vector2(100, 25) and TownSetPiece.point_at(p, 999.0) == Vector2(100, 50), "walk: clamped to the end")
	var tr := TownSetPiece.trail(p, 125.0, 50.0)
	t.ok(tr.size() == 3 and tr[0] == Vector2(75, 0) and tr[1] == Vector2(100, 0) and tr[2] == Vector2(100, 25), "walk: the trail is the 50 px behind the head, corner kept")
	var tr0 := TownSetPiece.trail(p, 10.0, 50.0)
	t.ok(tr0[0] == Vector2(0, 0) and tr0[tr0.size() - 1] == Vector2(10, 0), "walk: near the start the trail is as long as the walk so far")
	t.near(TownSetPiece.advance(0.0, 0.0, 0.0, 8.0, 3.0, 150.0), 0.0, 1e-9, "walk: no gait, no progress")
	t.near(TownSetPiece.advance(10.0, 4.0, 6.0, 8.0, 3.0, 150.0), 10.0 + 2.0 * 8.0 * 3.0, 1e-6, "walk: gait steps x step_px x speed_mul (lockstep)")
	t.near(TownSetPiece.advance(140.0, 0.0, 9.0, 8.0, 3.0, 150.0), 150.0, 1e-9, "walk: stops at the end")
	t.near(TownSetPiece.advance(10.0, 6.0, 4.0, 8.0, 3.0, 150.0), 10.0, 1e-9, "walk: the gait never runs backwards")
	t.near(TownSetPiece.badge_alpha(true, 99.0, 0.5, false), 0.0, 1e-9, "badge: none while it walks")
	t.near(TownSetPiece.badge_alpha(false, 0.0, 0.5, false), 0.0, 1e-9, "badge: starts clear on arrival")
	t.near(TownSetPiece.badge_alpha(false, 0.25, 0.5, false), 0.5, 1e-9, "badge: fades in over badge_fade_s")
	t.near(TownSetPiece.badge_alpha(false, 5.0, 0.5, false), 1.0, 1e-9, "badge: then holds")
	t.near(TownSetPiece.badge_alpha(false, 0.0, 0.5, true), 1.0, 1e-9, "badge, reduced motion: whole at once")
	t.near(TownSetPiece.badge_alpha(true, 0.0, 0.5, true), 0.0, 1e-9, "badge, reduced motion: still not before it arrives")
	t.ok(TownSetPiece.badge_shown("town:lot-04", "lot-04", "market"), "badge: a foreman placed at its building wears it")
	t.ok(not TownSetPiece.badge_shown("crypt", "lot-01", "crypt") and not TownSetPiece.badge_shown("crypt", "lot-04", "market"), "badge: none for a big undead resting in the crypt")
	t.ok(not TownSetPiece.badge_shown("party", "lot-04", "market") and not TownSetPiece.badge_shown("fort:ashgate", "lot-04", "market"), "badge: none in the party or at a fort")
	t.ok(not TownSetPiece.badge_shown("town:lot-01", "lot-01", "crypt") and not TownSetPiece.badge_shown("town:lot-02", "lot-04", "market"), "badge: none on the crypt lot, none on a lot that is not his place")
	t.ok(TownSetPiece.badge_offset(Vector2(0, -1), 10.0, 14.0, 3.0).y == 15.0 and TownSetPiece.badge_offset(Vector2(0, 1), 10.0, 14.0, 3.0).y == -15.0
		and TownSetPiece.badge_offset(Vector2(1, 0), 10.0, 14.0, 3.0) == Vector2.ZERO, "badge: pushed off the street the foreman faces, level on a side front")
	# which big undead start a walk: a place that changes to town:<lot>, never the baseline
	var e := func(uid: String, place: String) -> Dictionary: return {"uid": uid, "name": "N" + uid, "place": place}
	var first := TownSetPiece.transitions({}, [e.call("a", "town:lot-1"), e.call("b", "crypt")], false)
	t.ok(first["starts"].is_empty() and first["prev"] == {"a": "town:lot-1", "b": "crypt"}, "transitions: the first look seeds silently (a loaded save does not walk)")
	var same := TownSetPiece.transitions(first["prev"], [e.call("a", "town:lot-1"), e.call("b", "crypt")], true)
	t.ok(same["starts"].is_empty(), "transitions: no change, no walk")
	var moved := TownSetPiece.transitions(first["prev"], [e.call("a", "town:lot-1"), e.call("b", "town:lot-2")], true)
	t.ok(moved["starts"].size() == 1 and moved["starts"][0] == {"uid": "b", "name": "Nb", "lot_id": "lot-2", "from_lot": ""}, "transitions: crypt -> town:lot-2 starts b's walk to lot-2")
	var hop := TownSetPiece.transitions(moved["prev"], [e.call("a", "town:lot-3"), e.call("b", "town:lot-2")], true)
	t.ok(hop["starts"].size() == 1 and hop["starts"][0]["uid"] == "a" and hop["starts"][0]["lot_id"] == "lot-3"
		and hop["starts"][0]["from_lot"] == "lot-1", "transitions: a foreman re-placed at another building walks to it, from the building he was at")
	var out := TownSetPiece.transitions(moved["prev"], [e.call("a", "crypt"), e.call("b", "fort:x")], true)
	t.ok(out["starts"].is_empty(), "transitions: back to the crypt or off to a fort is no walk to a building")
	var born := TownSetPiece.transitions(same["prev"], [e.call("a", "town:lot-1"), e.call("b", "crypt"), e.call("c", "town:lot-4")], true)
	t.ok(born["starts"].size() == 1 and born["starts"][0]["uid"] == "c", "transitions: a new big undead placed on a building walks (the raise's walk-out)")
	var born_crypt := TownSetPiece.transitions(same["prev"], [e.call("a", "town:lot-1"), e.call("b", "crypt"), e.call("c", "crypt")], true)
	t.ok(born_crypt["starts"].is_empty() and born_crypt["prev"].has("c"), "transitions: a new one that stays in the crypt waits there")


## The foreman of lot `lot` is `uid` in these views (the view's own entry and building change together).
func _foreman_views(mid: Dictionary, uid: String, lot: String, from_lot := "") -> Dictionary:
	var v: Dictionary = mid.duplicate(true)
	for b in v["town"]["buildings"]:
		if b["lot_id"] == lot:
			b["foreman"] = uid
		if from_lot != "" and b["lot_id"] == from_lot:
			b["foreman"] = ""
	for e in v["big_undead"]["big_undead"]:
		if e["uid"] == uid:
			e["place"] = "town:" + lot if lot != "" else "crypt"
	return v


func _walkout(mid: Dictionary) -> void:
	t.suite("town-walkout")
	var pair := _agents(mid)
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	t.ok(a.walkers.is_empty() and a.foremen.size() == 1, "walkout: entering the scene with a foreman in place does not walk him")
	t.ok(a.foremen[0]["name"] != "" and a.foremen[0]["uid"] == "u8", "walkout: a foreman at rest carries his uid and name for the badge")
	_run(a, 1.0)
	t.ok(a.walkers.is_empty(), "walkout: nothing walks by itself")
	# u7 (in the crypt) is placed at a building with no foreman
	var lot := ""
	for l in m.lots:
		var b: Dictionary = l["building"]
		if not b.is_empty() and String(b["foreman"]) == "" and String(b["building_id"]) != "crypt" and bool(l["unlocked"]):
			lot = String(l["id"])
			break
	t.ok(lot != "", "walkout: a building without a foreman exists in midgame (%s)" % lot)
	var placed := _foreman_views(mid, "u7", lot)
	_resync(m, a, placed)
	t.ok(a.walkers.size() == 1 and a.walkers[0]["uid"] == "u7" and a.walkers[0]["lot_id"] == lot, "walkout: the place change starts a walk to that building")
	t.ok(a.is_walking(lot) and not a.is_walking("lot-04"), "walkout: that lot is walking, the others are not")
	t.ok(a.walkers.size() == 1 and (a.walkers[0]["strokes"] as int) >= 1, "walkout: the walker is the foreman diamond (strokes %s)" % str(a.walkers[0]["strokes"]))
	var crypt_rect: Rect2 = Rect2()
	for l in m.lots:
		if String(l["building"].get("building_id", "")) == "crypt":
			crypt_rect = l["building"]["rect"]
	t.ok(crypt_rect.grow(40.0).has_point(a.walkers[0]["pos"]), "walkout: it starts at the crypt")
	var start_pos: Vector2 = a.walkers[0]["pos"]
	# the badge is not up while it walks
	t.ok(a.badge_alpha(lot) == 0.0, "walkout: no badge before it arrives")
	# lockstep: it moves only on the gait's steps, never between them
	var clock := 0.0
	var moves := 0
	var last: Vector2 = start_pos
	var frames := 0
	var still_between := true
	var dt := 1.0 / 60.0
	var guard := 0
	while a.is_walking(lot) and guard < 60 * 120:
		guard += 1
		clock += dt
		a.step(dt, fposmod(clock / tempo_s, 1.0), false)
		if a.walkers.is_empty():
			break
		var p: Vector2 = a.walkers[0]["pos"]
		if p != last:
			moves += 1
			last = p
		frames += 1
	t.ok(not a.is_walking(lot) and guard < 60 * 120, "walkout: it arrives (in %.1f s)" % clock)
	t.ok(moves > 0 and moves < frames, "walkout: it steps with the gait: moved on %d of %d frames" % [moves, frames])
	var spot := Vector2.ZERO
	for f in a.foremen:
		if f["lot_id"] == lot:
			spot = f["pos"]
	t.ok(spot != Vector2.ZERO and (m.lot(lot)["rect"] as Rect2).grow(48.0).has_point(spot), "walkout: once there the foreman stands at the building")
	t.ok(a.badge_alpha(lot) < 1.0, "walkout: the badge is still fading in the instant it arrives")
	_run(a, 2.0, clock)
	t.near(a.badge_alpha(lot), 1.0, 1e-6, "walkout: and is whole after badge_fade_s")
	# a second foreman moving to a taken-up lot
	var again := _foreman_views(placed, "u7", "lot-04", lot)
	for b in again["town"]["buildings"]:
		if b["lot_id"] == "lot-04":
			b["foreman"] = "u7"
	for e in again["big_undead"]["big_undead"]:
		if e["uid"] == "u8":
			e["place"] = "crypt"
	_resync(m, a, again)
	t.ok(a.is_walking("lot-04") and not a.is_walking(lot), "walkout: a foreman re-placed at another building walks to it")
	var moved_from: Vector2 = a.walkers[0]["pos"] if a.walkers.size() == 1 else Vector2(-1, -1)
	# reduced motion: it arrives at once, badge whole
	var pair2 := _agents(mid)
	var m2: TownModel = pair2[0]
	var a2: TownAgents = pair2[1]
	_resync(m2, a2, placed)
	t.ok(a2.is_walking(lot), "walkout (reduced): the walk is registered")
	a2.step(1.0 / 60.0, 0.5, true)
	t.ok(not a2.is_walking(lot), "walkout (reduced): it is there on the first frame")
	t.near(a2.badge_alpha(lot), 1.0, 1e-6, "walkout (reduced): with its badge whole")
	# the trail follows the head along the street path
	var pair3 := _agents(mid)
	var m3: TownModel = pair3[0]
	var a3: TownAgents = pair3[1]
	_resync(m3, a3, placed)
	_run(a3, 1.0)  # fixed steps, no wall clock: the walk (several seconds long) is still under way
	t.ok(a3.walkers.size() == 1, "walkout: still walking after 1 s of fixed steps (the trail assertions below always run)")
	if a3.walkers.size() == 1:
		var w: Dictionary = a3.walkers[0]
		var tr: PackedVector2Array = w["trail"]
		t.ok(tr.size() >= 2 and tr[tr.size() - 1].distance_to(w["pos"]) < 1e-3, "walkout: the trail ends at the walker")
		t.ok(TownSetPiece.poly_len(tr) <= float(vcfg["walkout"]["trail_px"]) * m3.scale + 1e-3, "walkout: and is no longer than view.walkout.trail_px")
	# a foreman moved between buildings walks from where he stood, not from the crypt
	t.ok(spot != Vector2.ZERO and spot.distance_to(moved_from) < 1e-3 and moved_from.distance_to(crypt_rect.get_center()) > 20.0,
		"walkout: a foreman moved to another building starts at his old building's foreman spot (%s vs %s), not the crypt" % [str(spot), str(moved_from)])


func _foreman_float(mid: Dictionary) -> void:
	t.suite("town-foreman-float")
	var m := _model()
	m.update(mid, VIEW_RECT)
	var lot := ""
	var key := ""
	for b in mid["town"]["buildings"]:
		if String(b.get("foreman", "")) == "" and not (b.get("output", {}) as Dictionary).is_empty():
			lot = String(b["lot_id"])
			key = String((b["output"] as Dictionary).keys()[0])
			break
	t.ok(lot != "", "foreman float: a producing building without a foreman exists (%s)" % lot)
	if lot == "":
		return
	# a foreman placed and the output moves with it: the cause is the foreman, so it floats
	var with_f := _patched(mid, lot, {"foreman": "u7", "output": {key: _out(mid, lot, key) + 0.25}})
	m.update(with_f, VIEW_RECT)
	t.ok(m.floats.size() == 1 and m.floats[0]["lot_id"] == lot and m.floats[0]["text"].begins_with("+0.25"),
		"foreman float: a foreman placed with +0.25 output floats it: %s" % str(m.floats))
	m.update(with_f, VIEW_RECT)
	t.ok(m.floats.is_empty(), "foreman float: once")
	# the output moves with the same staffing, level, state and foreman: haul-style swing, no float
	m.update(_patched(mid, lot, {"foreman": "u7", "output": {key: _out(mid, lot, key) + 0.9}}), VIEW_RECT)
	t.ok(m.floats.is_empty(), "foreman float: an output swing with no cause still floats nothing")
	# a foreman change with no output change floats nothing (E2 has no foreman effect yet)
	var m2 := _model()
	m2.update(mid, VIEW_RECT)
	m2.update(_patched(mid, lot, {"foreman": "u7"}), VIEW_RECT)
	t.ok(m2.floats.is_empty(), "foreman float: a foreman placed with no output change floats nothing")


# ------------------------------------------------------------ fix 3b ----
func _read_src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


## Item 1: a staffed vat names what unstaffing frees; an unstaffed one what staffing takes.
func _fix3b_vats() -> void:
	t.suite("town-fix3b-vats")
	var tx: Dictionary = vcfg["backups"]
	var labels: Dictionary = vcfg["job_labels"]
	var bc: Dictionary = cfg["buildings"]
	var town := {"jobs": [{"id": "pit", "slots": 2, "staffed": 2.0}, {"id": "stall", "slots": 2, "staffed": 1.0}, {"id": "mill", "slots": 2, "staffed": 0.0}],
		"buildings": [], "workers": {"idle": 0.0}}
	var order: Array = ["pit", "stall", "mill"]
	var off := {"town": town, "backups": {"vats": [{"slot": 0, "staffed": false}]}}
	var on := {"town": town, "backups": {"vats": [{"slot": 0, "staffed": true}]}}
	# unstaffed: the slot on takes a hand off the bottom of the order
	var d_on := TownBehaviour.staffing_diff(TownStandins.project(off, order, bc)["jobs"], TownStandins.project(off, order, bc, {0: true})["jobs"])
	var line := BackupsModel.staffing_cost_text(d_on, labels, tx, false)
	t.ok(line == "staffing takes 1 hand from Stall", "vat: an unstaffed vat says what staffing takes (%s)" % line)
	# staffed: it already holds its hand, so the slot off gives one back to the top of the order
	var d_off := TownBehaviour.staffing_diff(TownStandins.project(on, order, bc)["jobs"], TownStandins.project(on, order, bc, {0: false})["jobs"])
	line = BackupsModel.staffing_cost_text(d_off, labels, tx, true)
	t.ok(d_off.size() == 1 and d_off[0]["id"] == "stall" and absf(float(d_off[0]["delta"]) - 1.0) < 1e-6, "vat: unstaffing frees exactly one hand, for the first job with room (%s)" % str(d_off))
	t.ok(line == "unstaffing frees 1 hand for Stall", "vat: a staffed vat says what unstaffing frees (%s)" % line)
	t.ok(not line.begins_with("staffing takes"), "vat: a staffed vat never says staffing takes a hand")
	# the slot already in the asked state changes nothing, either way round
	t.ok(TownStandins.project(on, order, bc, {0: true}) == TownStandins.project(on, order, bc), "vat: asking a staffed vat to be staffed moves nothing")
	t.ok(TownStandins.project(off, order, bc, {0: false}) == TownStandins.project(off, order, bc), "vat: asking an unstaffed vat to be unstaffed moves nothing")
	# no job has room for the freed hand: said so
	var full := {"town": {"jobs": [{"id": "pit", "slots": 2, "staffed": 2.0}], "buildings": [], "workers": {"idle": 0.0}},
		"backups": {"vats": [{"slot": 0, "staffed": true}]}}
	var d_none := TownBehaviour.staffing_diff(TownStandins.project(full, ["pit"], bc)["jobs"], TownStandins.project(full, ["pit"], bc, {0: false})["jobs"])
	t.ok(BackupsModel.staffing_cost_text(d_none, labels, tx, true) == "unstaffing frees no hand for a job", "vat: a freed hand with no room says so")
	for k in ["unstaff_gain", "unstaff_gain_item", "unstaff_gain_none"]:
		t.ok(tx.has(k), "town.json view.backups.%s exists" % k)
	# the Chapel's upkeep: a signed rate, oblique, in parts
	var parts := BackupsModel.upkeep_parts({"gold": 0.5, "bone": 0.0}, "Chapel", tx)
	t.ok(HudModel.parts_text(parts) == "Chapel upkeep −0.50/s gold", "upkeep: the line reads as before (%s)" % HudModel.parts_text(parts))
	var obl: Array = parts.filter(func(p): return p[1]).map(func(p): return p[0])
	t.ok(obl == ["−0.50/s"], "upkeep: only the signed rate is oblique (%s)" % str(obl))
	t.ok(BackupsModel.upkeep_parts({"gold": 0.0, "bone": 0.0}, "Chapel", tx).is_empty(), "upkeep: nothing to pay, no parts")
	var both := BackupsModel.upkeep_parts({"gold": 0.5, "bone": 0.25}, "Chapel", tx)
	t.ok(both.filter(func(p): return p[1]).size() == 2, "upkeep: each store's rate is oblique (%s)" % HudModel.parts_text(both))


## Item 2: the stance row's fire/hold verdict comes from `active` once stances are live.
func _fix3b_stances(mid: Dictionary) -> void:
	t.suite("town-fix3b-stances")
	var bc: Dictionary = cfg["buildings"]
	var town: Dictionary = mid["town"]
	var lad := TownBehaviour.effective(town)
	var before: Array = TownStandins.staffing_projection(mid, lad, bc)["jobs"]
	var after: Array = TownStandins.staffing_projection(mid, TownBehaviour.to_top(lad, "haul"), bc)["jobs"]
	var st: Dictionary = vcfg["stance_trade"]
	t.ok(not (st["harvest"] as Dictionary).has("frac") and not (st["hearth"] as Dictionary).has("below"), "stance trade: no second threshold set in view.stance_trade")
	t.ok(not TownBehaviour.stances_live(mid), "stance trade: the fixtures' stances are stubs (projected is empty)")
	var cap := float(town["bodies_cap"])
	var need_frac := float(vcfg["needs"]["bodies_frac"])
	var h := HudModel.parts_text(TownBehaviour.stance_trade("harvest", mid, before, after, vcfg))
	t.ok(h.contains("fires under %d" % roundi(need_frac * cap)), "stance trade: stub stances use the needs' bodies threshold (%s)" % h)
	t.ok(h.contains("→ it would fire") == (float(town["bodies"]) < need_frac * cap), "stance trade: and its verdict (%s)" % h)
	var v2: Dictionary = mid.duplicate(true)
	var vc: Dictionary = vcfg.duplicate(true)
	vc["needs"]["bodies_frac"] = 0.0001
	h = HudModel.parts_text(TownBehaviour.stance_trade("harvest", v2, before, after, vc))
	t.ok(h.contains("→ it wouldn't fire"), "stance trade: changing the needs' threshold changes the stand-in verdict (%s)" % h)
	vc["needs"]["morale_below"] = 99.0
	t.ok(HudModel.parts_text(TownBehaviour.stance_trade("hearth", v2, before, [], vc)).contains("→ it would fire"), "stance trade: hearth follows needs.morale_below")
	# live: any stance has a projection; then `active` decides, whatever the thresholds say
	var live: Dictionary = mid.duplicate(true)
	for s in live["stances"]["stances"]:
		s["projected"] = {"bodies": 0.1}
		s["active"] = String(s["id"]) == "hearth"
	t.ok(TownBehaviour.stances_live(live), "stance trade: one non-empty projection makes the stances live")
	h = HudModel.parts_text(TownBehaviour.stance_trade("harvest", live, before, after, vcfg))
	t.ok(h.contains("→ it wouldn't fire"), "stance trade: live and inactive, Harvest holds even though bodies are under the threshold (%s)" % h)
	live["town"]["bodies"] = cap  # the threshold says hold; active says fire
	for s in live["stances"]["stances"]:
		s["active"] = String(s["id"]) == "harvest"
	h = HudModel.parts_text(TownBehaviour.stance_trade("harvest", live, before, after, vcfg))
	t.ok(h.contains("→ it would fire"), "stance trade: live and active, Harvest fires even with bodies full (%s)" % h)
	h = HudModel.parts_text(TownBehaviour.stance_trade("hearth", live, before, [], vcfg))
	t.ok(h.contains("→ it wouldn't fire"), "stance trade: live, a stance that is not active holds (%s)" % h)
	t.ok(not h.contains("fires under"), "stance trade: live rows drop the stand-in limit (%s)" % h)
	for sid in ["harvest", "hearth"]:
		t.ok(not HudModel.parts_text(TownBehaviour.stance_trade(sid, live, before, after, vcfg)).contains("fires under"),
			"stance trade: live %s row prints no threshold" % sid)
	t.ok(HudModel.parts_text(TownBehaviour.stance_trade("harvest", live, before, after, vcfg)).contains("bodies %d / %d" % [int(float(live["town"]["bodies"])), roundi(cap)]),
		"stance trade: live Harvest still says how many bodies there are")


## Items 3 and 15: one rev-keyed cache for staffing projections and the lot hops.
func _fix3b_cache() -> void:
	t.suite("town-fix3b-cache")
	var c := RevCache.new()
	var calls := [0]
	var make := func() -> Variant:
		calls[0] += 1
		return calls[0]
	t.ok(c.fetch(1, ["a", {"x": true}], make) == 1 and c.fetch(1, ["a", {"x": true}], make) == 1 and calls[0] == 1, "cache: the same rev and key makes it once")
	t.ok(c.fetch(1, ["b", {}], make) == 2 and calls[0] == 2, "cache: a different key (order or extra) makes it again")
	t.ok(c.fetch(1, ["a", {"x": false}], make) == 3, "cache: a different extra is a different key")
	t.ok(c.fetch(2, ["a", {"x": true}], make) == 4 and c.fetch(2, ["a", {"x": true}], make) == 4, "cache: a new rev starts over")
	t.ok(c.fetch(1, ["a", {"x": true}], make) == 5, "cache: and going back to an older rev is a miss, not a stale hit")
	# the three panels never ask GameState for a projection; the shell owns the one helper
	for p in ["panel_backups", "panel_stances", "panel_jobs"]:
		var src := _read_src("res://scripts/town/%s.gd" % p)
		t.ok(src != "" and not src.contains("view_staffing_projection") and not src.contains("TownStandins.staffing_projection"),
			"%s: no projection of its own (the shell's project_staffing, handed in as a Callable)" % p)
	var shell := _read_src("res://scripts/town/covington.gd")
	t.ok(shell.contains("func project_staffing(order: Array, extra := {})") and shell.contains("view_staffing_projection"),
		"covington: owns project_staffing, which calls the projection view when GameState has it")
	t.ok(shell.contains("_staff_cache.fetch(int(s.rev),") and not shell.contains("TownStandins.project(") and shell.contains("_hops_cache.fetch(0,"),
		"covington: the projection is the real view, keyed on GameState's rev (the #16 stand-in is retired); the lot hops are computed once")
	t.ok(shell.contains("RevCache"), "covington: caches the projections and the lot hops by rev")


## Items 5-14 that are pure.
func _fix3b_small(mid: Dictionary) -> void:
	t.suite("town-fix3b-small")
	# #11: slot ticks are capped like the pips, with the count beside
	var pm := int(vcfg["pip_max"])
	var k := TownModel.slot_ticks(3, 2, pm)
	t.ok(k["shown"] == 3 and k["working"] == 2 and k["count"] == "", "ticks: a short row draws every slot and no count (%s)" % str(k))
	k = TownModel.slot_ticks(16, 12, pm)
	t.ok(k["shown"] == pm and k["working"] == pm and k["count"] == "12/16", "ticks: 16 slots draw pip_max ticks with '12/16' beside (%s)" % str(k))
	k = TownModel.slot_ticks(16, 4, pm)
	t.ok(k["shown"] == pm and k["working"] == 4 and k["count"] == "4/16", "ticks: the filled ticks never exceed the hands working (%s)" % str(k))
	k = TownModel.slot_ticks(pm, 3, pm)
	t.ok(k["shown"] == pm and k["count"] == "", "ticks: exactly pip_max slots is not capped (%s)" % str(k))
	# #13 is in test_walkout; #14: styleboxes are built once
	t.ok(TownUI.button_box_cached("normal") == TownUI.button_box_cached("normal") and TownUI.button_box_cached("active") != TownUI.button_box_cached("normal"),
		"stylebox: a button state's box is built once and shared")
	# #16: a muted synth computes no beat; the unmute frame doesn't fire a stale one
	var tempo := 1714.0
	var r := TownSound.beat_step(true, 3, 9999.0, tempo)
	t.ok(r["i"] == -1 and not r["fire"], "beat: muted computes nothing and forgets the last beat")
	r = TownSound.beat_step(false, -1, 5000.0, tempo)
	t.ok(not r["fire"] and r["i"] == 2, "beat: the first unmuted frame only records the beat index")
	r = TownSound.beat_step(false, 2, 3500.0, tempo)
	t.ok(not r["fire"] and r["i"] == 2, "beat: inside the same beat nothing fires")
	r = TownSound.beat_step(false, 2, 1.0 * tempo * 3.0 + 1.0, tempo)
	t.ok(r["fire"] and r["i"] == 3, "beat: a new beat fires once")
	# #18: the name field takes focus when the raise forms, for a mouse hold at once, for Space once the key is up
	t.ok(CryptLogic.name_focus_now(false, "formed") and not CryptLogic.name_focus_now(true, "formed"), "name focus: a mouse hold focuses the field when the hold completes, a Space hold waits")
	t.ok(CryptLogic.name_focus_now(true, "key_up") and not CryptLogic.name_focus_now(false, "key_up"), "name focus: a Space hold focuses it on the key's release")
	# #12: literals live in town.json
	t.ok(vcfg["walkout"].has("badge_edge_px"), "view.walkout.badge_edge_px exists")
	t.ok(not _read_src("res://scripts/town/town_agents_layer.gd").contains("host.x - 2.0"), "badge: the edge margin is config, not a literal")
	t.ok(vcfg.has("lot_name"), "view.lot_name exists")


## Item 14: no raw lot id in player-facing text.
func _fix3b_lot_names() -> void:
	t.suite("town-fix3b-lots")
	t.ok(TownModel.lot_name("lot-05", vcfg) == "lot 5" and TownModel.lot_name("lot-12", vcfg) == "lot 12", "lot name: '%s', '%s'" % [TownModel.lot_name("lot-05", vcfg), TownModel.lot_name("lot-12", vcfg)])
	t.ok(TownModel.lot_name("", vcfg) == "" and TownModel.lot_name("lot-x", vcfg) == "lot x", "lot name: empty stays empty, an odd id is still words (%s)" % TownModel.lot_name("lot-x", vcfg))
	var leaks: Array = []
	var shape := RegEx.create_from_string("^lot [1-9][0-9]*$")
	for l in cfg["town"]["lots"]:
		var n := TownModel.lot_name(String(l["id"]), vcfg)
		if shape.search(n) == null:
			leaks.append(n)
	t.ok(leaks.is_empty() and TownModel.lot_name("lot-24", vcfg) == "lot 24", "lot name: no id leaks in any of the %d lots (%s)" % [cfg["town"]["lots"].size(), str(leaks)])
	t.ok(not String(vcfg.get("lot_name", "")).contains("lot-"), "lot name: the format string has no id")
	# the panels' player-facing formats use it
	for p in ["panel_build", "panel_crypt", "panel_jobs"]:
		var src := _read_src("res://scripts/town/%s.gd" % p)
		t.ok(src != "" and src.contains("lot_name("), "%s: names lots through TownModel.lot_name" % p)
	var pb := _read_src("res://scripts/town/panel_build.gd")
	for bad in ["on %s.\" % [_label(bid), lot_id]", "% [lot_id, _reason", "\"Lot %s\"", "\"Upgrading %s.\" % _selected_lot", "\"Demolished %s.\" % lot", "\"Queued %s on %s.\" % [_label(e[\"building_id\"]), e[\"lot_id\"]]"]:
		t.ok(not pb.contains(bad), "panel_build: no raw id in `%s`" % bad)
	t.ok(not _read_src("res://scripts/town/panel_jobs.gd").contains("trim_prefix(\"lot-\")"), "panel_jobs: no '(05)'")
	t.ok(String(vcfg["crypt"].get("lot_option", "")) != "" and not String(vcfg["crypt"].get("lot_option", "")).contains("{lot_id}"), "crypt: the foreman option takes a lot name")


# ---- fix 3d: the signatures that let a panel's bind skip unchanged work ----
func _fix3d_sigs(day1: Dictionary, mid: Dictionary) -> void:
	t.suite("town-fix3d-sigs")
	# a fresh copy of the same views is the same number; a stock that every refresh moves is not in it
	var again := day1.duplicate(true)
	again["town"]["gold"] = float(again["town"].get("gold", 0.0)) + 7.0
	again["town"]["rev"] = int(again["town"].get("rev", 0)) + 1
	again["hud"]["t"] = float(again["hud"].get("t", 0.0)) + 1.0
	t.ok(CryptLogic.bind_sig(day1) == CryptLogic.bind_sig(day1.duplicate(true)), "crypt sig: equal views, equal sig")
	t.ok(CryptLogic.bind_sig(day1) == CryptLogic.bind_sig(again), "crypt sig: gold, rev and clock moves don't change it")
	t.ok(BackupsModel.death_sig(day1) == BackupsModel.death_sig(again), "backups death sig: stocks don't change it")
	t.ok(BackupsModel.ossuary_sig(day1) == BackupsModel.ossuary_sig(again), "backups ossuary sig: stocks don't change it")
	t.ok(BackupsModel.vats_sig(day1) == BackupsModel.vats_sig(day1.duplicate(true)), "backups vats sig: equal views, equal sig")
	# each field a section reads moves its sig
	var base := CryptLogic.bind_sig(mid)
	var variants := {
		"a husk": func(v: Dictionary): v["inventory"]["husks"] = v["inventory"].get("husks", []) + [{"uid": "h-x", "kind": "warden"}],
		"a remnant": func(v: Dictionary): v["inventory"]["remnants"] = v["inventory"].get("remnants", []) + [{"uid": "r-x", "aspect": "bone", "magnitude": 2}],
		"a big undead": func(v: Dictionary): v["big_undead"]["big_undead"] = v["big_undead"].get("big_undead", []) + [{"uid": "b-x", "name": "X", "place": "crypt"}],
		"the cap": func(v: Dictionary): v["big_undead"]["cap"] = int(v["big_undead"].get("cap", 0)) + 1,
		"Relish's state": func(v: Dictionary): v["relish"]["state"] = String(v["relish"].get("state", "")) + "_x",
		"a fort's name": func(v: Dictionary): v["fort_names"] = {"old-sluice": "Old Sluice"},
		"a fort held": func(v: Dictionary): v["forts"] = [{"id": "old-sluice", "name": "Old Sluice", "held": true}],
		"a lot's building": func(v: Dictionary): v["town"]["buildings"] = v["town"]["buildings"] + [{"lot_id": "lot-99", "building_id": "inn", "level": 1, "slots": 1}],
	}
	for k in variants:
		var v := mid.duplicate(true)
		(variants[k] as Callable).call(v)
		t.ok(CryptLogic.bind_sig(v) != base, "crypt sig: %s changes it" % k)
	var dead := mid.duplicate(true)
	dead["relish"]["state"] = "dead"
	dead["relish"]["dead_s_left"] = 30.2
	var dead2 := dead.duplicate(true)
	dead2["relish"]["dead_s_left"] = 29.2
	t.ok(CryptLogic.bind_sig(dead) != CryptLogic.bind_sig(dead2), "crypt sig: a dead Relish's countdown moves it by the second")
	var bk := mid.duplicate(true)
	bk["backups"]["death"] = {"outcome": "__other"}
	t.ok(BackupsModel.death_sig(bk) != BackupsModel.death_sig(mid), "backups death sig: the death outcome changes it")
	var vt := mid.duplicate(true)
	vt["backups"]["vats"] = [{"slot": 0, "staffed": true, "ready": false, "grow": 0.5}]
	t.ok(BackupsModel.vats_sig(vt) != BackupsModel.vats_sig(mid), "backups vats sig: a vat changes it")
	var cr := mid.duplicate(true)
	cr["catalog"]["crafts"] = [{"item_id": "x", "can_craft": true, "cost": {}}]
	t.ok(BackupsModel.ossuary_sig(cr) != BackupsModel.ossuary_sig(mid), "backups ossuary sig: a craft row changes it")
	# the build row: the stocks aren't in it, the row, class, chip and the extras are
	var row := {"building_id": "house", "can_build": true, "cost": {"gold": 10}, "count": 1}
	var item := {"row": row, "cls": 1, "chip": ""}
	var rs := BuildSort.row_sig(item, [false, "", false, false, false, ""])
	t.ok(rs == BuildSort.row_sig(item.duplicate(true), [false, "", false, false, false, ""]), "row sig: equal inputs, equal sig")
	t.ok(rs != BuildSort.row_sig({"row": row, "cls": 2, "chip": ""}, [false, "", false, false, false, ""]), "row sig: the class changes it")
	t.ok(rs != BuildSort.row_sig({"row": row, "cls": 1, "chip": "need"}, [false, "", false, false, false, ""]), "row sig: the chip changes it")
	t.ok(rs != BuildSort.row_sig(item, [true, "", false, false, false, ""]), "row sig: the suggestion flag changes it")
	t.ok(rs != BuildSort.row_sig(item, [false, "", true, false, false, ""]), "row sig: placement changes it")
	t.ok(rs != BuildSort.row_sig(item, [false, "", false, true, false, ""]), "row sig: focus changes it")
	t.ok(rs != BuildSort.row_sig(item, [false, "", false, false, true, ""]), "row sig: a full queue changes it")
	t.ok(rs != BuildSort.row_sig(item, [false, "", false, false, false, "inn"]), "row sig: the fix target changes it")
	var r2 := row.duplicate()
	r2["can_build"] = false
	t.ok(rs != BuildSort.row_sig({"row": r2, "cls": 1, "chip": ""}, [false, "", false, false, false, ""]), "row sig: the row changes it")
	# the shell binds only what is on screen
	var src := FileAccess.get_file_as_string("res://scripts/town/covington.gd")
	t.ok(src.contains("func _binds_now(") and src.contains("_panels[i].bind(_last_views)"), "shell: hidden tabs bind on show, from the last views")


# ---- fix 3e: the refresh fix's review ----
## Item 1: the spread refresh's queue merges, so a fetch that lands before the queue drains drops nothing.
func _fix3e_queue() -> void:
	t.suite("town-fix3e-queue")
	var a := RefCounted.new()
	var b := RefCounted.new()
	var c := RefCounted.new()
	var d := RefCounted.new()
	var pend: Array = [a, b, c]
	var out := TownModel.merge_pending(pend, [a, b, c, d])
	t.ok(out == [a, b, c, d], "queue: a refresh over a part-drained queue keeps the order and adds only the new one")
	pend = [c]  # a, b were popped; the next fetch wants all four again
	out = TownModel.merge_pending(pend, [a, b, c, d])
	t.ok(out == [c, a, b, d], "queue: the node still waiting stays first, the rest follow once each (%d)" % out.size())
	t.ok(TownModel.merge_pending([], [a, b]) == [a, b], "queue: an empty queue takes the list as it is")
	t.ok(TownModel.merge_pending([a, b], []) == [a, b], "queue: nothing to add drops nothing")
	# a slow-frame cycle: every fetch lands after one pop; the last node must still be bound in the end
	var nodes: Array = [a, b, c, d]  # hud, view, build, open tab
	var queue: Array = []
	var bound := {}
	for fetch in 6:
		queue = TownModel.merge_pending(queue, nodes)
		bound[queue.pop_front()] = true
	t.ok(bound.size() == 4, "queue: popping one per fetch still reaches the open tab (%d of 4 bound)" % bound.size())
	var shell := _read_src("res://scripts/town/covington.gd")
	t.ok(shell.contains("TownModel.merge_pending(") and not shell.contains("_later = _bound.filter(_binds_now)"), "covington: the spread queue merges, it is not replaced")


## Items 5 and 6 (pure part): each field a section reads moves its signature, each it doesn't read leaves it.
func _fix3e_sigs(mid: Dictionary) -> void:
	t.suite("town-fix3e-sigs")
	var base := CryptLogic.bind_sig(mid)
	var edits := {
		"at": func(v: Dictionary): v["relish"]["at"] = "lot-77",
		"target": func(v: Dictionary): v["relish"]["target"] = "fort-x",
		"respawn_with_clone": func(v: Dictionary): v["relish"]["respawn_with_clone"] = not bool(v["relish"].get("respawn_with_clone", false)),
		"a changed creature": func(v: Dictionary): v["big_undead"]["big_undead"] = [{"uid": "b-1", "name": "A", "place": "crypt"}],
	}
	for k in edits:
		var v := mid.duplicate(true)
		(edits[k] as Callable).call(v)
		t.ok(CryptLogic.bind_sig(v) != base, "crypt sig: relish %s changes it" % k if k in ["at", "target", "respawn_with_clone"] else "crypt sig: %s changes it" % k)
	var cv := mid.duplicate(true)
	cv["big_undead"]["big_undead"] = [{"uid": "b-1", "name": "A", "place": "crypt"}]
	var cv2 := cv.duplicate(true)
	cv2["big_undead"]["big_undead"][0]["place"] = "party"
	t.ok(CryptLogic.bind_sig(cv) != CryptLogic.bind_sig(cv2), "crypt sig: a creature's place changes it")
	var lv := mid.duplicate(true)
	lv["town"]["buildings"][0]["level"] = int(lv["town"]["buildings"][0].get("level", 1)) + 1
	t.ok(CryptLogic.bind_sig(lv) != base, "crypt sig: a changed lot (its level) changes it")
	var fv := mid.duplicate(true)
	fv["town"]["buildings"][0]["foreman"] = "b-9"
	t.ok(CryptLogic.bind_sig(fv) != base, "crypt sig: a changed lot's foreman changes it")
	# the death section
	var d0 := BackupsModel.death_sig(mid)
	var dv := {
		"dead_s_left": func(v: Dictionary): v["backups"]["dead_s_left"] = float(v["backups"].get("dead_s_left", 0.0)) + 3.0,
		"party": func(v: Dictionary): v["party"] = {"party": [{"uid": "p-1", "name": "P", "place": "party"}]},
		"loses": func(v: Dictionary): v["backups"]["death"]["loses"] = ["party", "everything"],
		"respawn_s": func(v: Dictionary): v["backups"]["death"]["respawn_s"] = 12.0,
	}
	for k in dv:
		var v := mid.duplicate(true)
		if not v.has("party"):
			v["party"] = {"party": []}
		var before := BackupsModel.death_sig(v)
		(dv[k] as Callable).call(v)
		t.ok(BackupsModel.death_sig(v) != before, "death sig: %s changes it" % k)
	# the vats section: what its fill and the staffing projection read
	var base_v := mid.duplicate(true)
	base_v["town"]["buildings"] = [{"building_id": "chapel_of_vats", "lot_id": "lot-01", "state": "active", "slots": 2, "staff_cap": 2,
		"upkeep": {"gold": 0.5, "bone": 0.0}, "progress": 1.0, "staffed": 1.0, "output": {}, "rot": 0.0}]
	base_v["town"]["jobs"] = [{"id": "pit", "slots": 2, "staffed": 1.0}]
	base_v["town"]["workers"] = {"idle": 3.0, "total": 9.0}
	base_v["town"]["ladder"] = ["pit", "stall"]
	var v0 := BackupsModel.vats_sig(base_v)
	var vv := {
		"jobs.staffed": func(v: Dictionary): v["town"]["jobs"][0]["staffed"] = 2.0,
		"jobs.slots": func(v: Dictionary): v["town"]["jobs"][0]["slots"] = 3,
		"the ladder": func(v: Dictionary): v["town"]["ladder"] = ["stall", "pit"],
		"the effective ladder": func(v: Dictionary): v["town"]["ladder_effective"] = ["stall", "pit"],
		"clones_ready": func(v: Dictionary): v["backups"]["clones_ready"] = int(v["backups"].get("clones_ready", 0)) + 1,
		"a building's state": func(v: Dictionary): v["town"]["buildings"][0]["state"] = "constructing",
		"a building's slots": func(v: Dictionary): v["town"]["buildings"][0]["slots"] = 3,
		"a building's staff_cap": func(v: Dictionary): v["town"]["buildings"][0]["staff_cap"] = 1,
		"a building's upkeep": func(v: Dictionary): v["town"]["buildings"][0]["upkeep"] = {"gold": 0.75, "bone": 0.0},
		"a building's id": func(v: Dictionary): v["town"]["buildings"][0]["building_id"] = "bonemill",
	}
	for k in vv:
		var v := base_v.duplicate(true)
		(vv[k] as Callable).call(v)
		t.ok(BackupsModel.vats_sig(v) != v0, "vats sig: %s changes it" % k)
	# the idle hands reach the vats only as the staffing-cost line: with every room full, idle 0.5 says "takes 1 hand",
	# 0.6 says "no hand" (the same whole idle count), and the sig follows the line, not the count
	var full_town := {"jobs": [{"id": "pit", "slots": 2, "staffed": 2.0}, {"id": "stall", "slots": 2, "staffed": 2.0}],
		"buildings": [], "workers": {"idle": 0.5}, "ladder": ["pit", "stall"]}
	var full_views := {"town": full_town, "backups": {"vats": [{"slot": 0, "staffed": false}]}}
	var bcfg: Dictionary = cfg["buildings"]
	var proj := func(order: Array, extra := {}) -> Array: return TownStandins.project(full_views, order, bcfg, extra)["jobs"]
	var c_half := BackupsModel.staffing_costs(full_views, proj, vcfg["job_labels"], vcfg["backups"])
	var sig_half := BackupsModel.vats_sig(full_views, c_half)
	full_town["workers"]["idle"] = 0.6
	var c_six := BackupsModel.staffing_costs(full_views, proj, vcfg["job_labels"], vcfg["backups"])
	t.ok(c_half != c_six, "vats sig: idle 0.5 and 0.6 with rooms full read differently (%s / %s)" % [str(c_half), str(c_six)])
	t.ok(BackupsModel.vats_sig(full_views, c_six) != sig_half, "vats sig: idle 0.5 -> 0.6 with rooms full and an unstaffed vat changes it")
	full_town["workers"]["idle"] = 0.9
	t.ok(BackupsModel.vats_sig(full_views, BackupsModel.staffing_costs(full_views, proj, vcfg["job_labels"], vcfg["backups"])) == BackupsModel.vats_sig(full_views, c_six),
		"vats sig: idle creeping 0.6 -> 0.9 with the same line leaves it")
	# what the vats fill does not read leaves it
	var calm := base_v.duplicate(true)
	var cb: Dictionary = calm["town"]["buildings"][0]
	cb["progress"] = 0.4
	cb["staffed"] = 2.0
	cb["output"] = {"mint": 1.0}
	cb["rot"] = 0.3
	cb["muster"] = 1.0
	cb["lifetime"] = 99.0
	calm["town"]["workers"]["total"] = 10.0
	calm["town"]["workers"]["rot"] = 0.2
	calm["town"]["workers"]["muster"] = 1.0
	t.ok(BackupsModel.vats_sig(calm) == v0, "vats sig: progress, staffed, output, rot, muster, lifetime and the worker totals don't move it")
	# the ossuary section: each field it shows
	var o0 := BackupsModel.ossuary_sig(mid)
	var ov := {
		"phylactery_charges": func(v: Dictionary): v["backups"]["phylactery_charges"] = int(v["backups"].get("phylactery_charges", 0)) + 1,
		"phylactery_max_per_dungeon": func(v: Dictionary): v["backups"]["phylactery_max_per_dungeon"] = int(v["backups"].get("phylactery_max_per_dungeon", 0)) + 1,
		"simulacra_ready": func(v: Dictionary): v["inventory"]["simulacra_ready"] = int(v["inventory"].get("simulacra_ready", 0)) + 1,
		"essence": func(v: Dictionary): v["inventory"]["essence"] = float(v["inventory"].get("essence", 0)) + 1.0,
		"relics": func(v: Dictionary): v["inventory"]["relics"] = int(v["inventory"].get("relics", 0)) + 1,
		"crafts": func(v: Dictionary): v["catalog"]["crafts"] = [{"item_id": "z", "can_craft": false, "cost": {}}],
	}
	for k in ov:
		var v := mid.duplicate(true)
		(ov[k] as Callable).call(v)
		t.ok(BackupsModel.ossuary_sig(v) != o0, "ossuary sig: %s changes it" % k)


## Items 2 and 3: a local handler that writes row nodes directly makes the row (and the panel) redo them.
func _fix3e_handlers() -> void:
	t.suite("town-fix3e-handlers")
	var crypt := _read_src("res://scripts/town/panel_crypt.gd")
	var after := crypt.substr(crypt.find("func _after_place("))
	after = after.substr(0, after.find("\nfunc ", 10))
	t.ok(after.contains("_bind_sig = 0") and after.contains("row.erase(\"sig\")"), "crypt: _after_place invalidates the row and the panel's signature")
	var btn := crypt.substr(crypt.find("func _on_place_btn("))
	btn = btn.substr(0, btn.find("\nfunc ", 10))
	t.ok(btn.contains("_bind_sig = 0") and btn.contains("row.erase(\"sig\")"), "crypt: the Foreman/Siege chooser toggle invalidates them too")
	var build := _read_src("res://scripts/town/panel_build.gd")
	var cancel := build.substr(build.find("func cancel_placement("))
	cancel = cancel.substr(0, cancel.find("\nfunc ", 10))
	t.ok(cancel.contains("erase(\"sig\")"), "build: cancel_placement clears each row's signature after writing 'Place'")
	var jobs := _read_src("res://scripts/town/panel_jobs.gd")
	t.ok(jobs.contains("visibility_changed") and jobs.contains("_armed = 0"), "jobs: a hidden tab disarms the flash")
	var bs := _read_src("res://scripts/town/build_sort.gd")
	var i_doc := bs.find("## Cost as display parts")
	var i_sig := bs.find("static func row_sig(")
	var i_cp := bs.find("static func cost_parts(")
	t.ok(i_doc >= 0 and i_doc < i_cp and (i_sig < i_doc or i_sig > i_cp), "build_sort: cost_parts keeps its own doc comment, row_sig sits outside it")


## Item 6: a real GameState ticks with no command; none of the signatures moves.
func _fix3e_live() -> void:
	t.suite("town-fix3e-live")
	for fx in ["day1", "midgame_2flips"]:
		var s := GameState.new(TestUtil.configs())
		s.debug_enabled = true
		s.cmd_debug_load_fixture(fx)
		var v0 := _live(s)
		var sig0 := _live_sigs(v0)
		var r0 := s.rev
		for i in 6:
			s.tick(0.5)
		t.ok(s.rev > r0, "%s: the ticks moved the rev (%d to %d)" % [fx, r0, s.rev])
		var v1 := _live(s)
		# Allowed exceptions, each a field the panel really shows that moves with the sim: Relish travels in
		# midgame_2flips (the crypt gate and place words change when she arrives), so the crypt compares with
		# her view held; and a need chip carries a live count ("bodies are low (40 of 200)"), so a catalog row
		# may move by its chip alone.
		var held := v1.duplicate()
		held["relish"] = v0["relish"]
		var sig1 := _live_sigs(v1)
		sig1["crypt"] = CryptLogic.bind_sig(held)
		var items0 := {}
		for it in BuildSort.tab_suggestion(v0, cfg["buildings_view"], cfg["buildings"], vcfg)["items"]:
			items0[String(it["row"]["building_id"])] = it
		var items1 := {}
		for it in BuildSort.tab_suggestion(v1, cfg["buildings_view"], cfg["buildings"], vcfg)["items"]:
			items1[String(it["row"]["building_id"])] = it
		for k in sig0:
			if not k.begins_with("row:"):
				t.ok(sig0[k] == sig1[k], "%s: %s unchanged after 3 s of ticks with no command" % [fx, k])
		var moved: Array = []
		for k in sig0:
			if k.begins_with("row:") and sig0[k] != sig1[k]:
				var a: Dictionary = (items0[k.trim_prefix("row:")] as Dictionary).duplicate()
				var b: Dictionary = (items1[k.trim_prefix("row:")] as Dictionary).duplicate()
				a["chip"] = ""
				b["chip"] = ""
				if a != b:
					moved.append(k)
		t.ok(moved.is_empty(), "%s: no catalog row's signature moved but by its chip's live count (%s)" % [fx, str(moved)])
		t.ok(sig0.keys().filter(func(k): return k.begins_with("row:")).size() > 5, "%s: the rows were checked (%d)" % [fx, sig0.size()])


func _live(s: GameState) -> Dictionary:
	return {"town": s.view_town(), "hud": s.view_hud(), "rates": s.view_rates(), "fort_names": {}, "catalog": s.view_catalog(),
		"stances": s.view_stances(), "backups": s.view_backups(), "inventory": s.view_inventory(), "big_undead": s.view_big_undead(),
		"party": s.view_party(), "relish": s.view_relish(), "vei": s.view_vei()}


func _live_sigs(v: Dictionary) -> Dictionary:
	var out := {"crypt": CryptLogic.bind_sig(v), "death": BackupsModel.death_sig(v), "vats": BackupsModel.vats_sig(v),
		"ossuary": BackupsModel.ossuary_sig(v)}
	var bview: Dictionary = cfg["buildings_view"]
	var tab := BuildSort.tab_suggestion(v, bview, cfg["buildings"], vcfg)
	var st := BuildSort.stocks(v)
	var sug_bid := String(tab["sug"].get("building_id", ""))
	for it in tab["items"]:
		var row: Dictionary = it["row"]
		var bid := String(row.get("building_id", ""))
		var can := bool(row.get("can_build", false))
		var target := BuildSort.fix_target(String(row.get("reason", "")), row, st, vcfg) if not can else ""
		var sug := bid == sug_bid
		out["row:" + bid] = BuildSort.row_sig(it, [sug, String(tab["sug"].get("chip", "suggested")) if sug and bool(tab["sug"].get("upgrade", false)) else "",
			false, false, false, target])
	return out


# ------------------------------------------------------------------- T-d1 ----
## A world like midgame_2flips, but with `n` relics held in every view that carries them. With `consistent`
## the catalog is re-derived the way the sim would (a row whose relic cost is over `n` can't be built:
## no_relics); without it the catalog is left stale, so only the relic count says the row is blocked.
func _with_relics(mid: Dictionary, n: int, consistent: bool) -> Dictionary:
	var v: Dictionary = mid.duplicate(true)
	v["hud"]["relics"] = n
	v["inventory"]["relics"] = n
	if consistent:
		for r in v["catalog"]["buildings"]:
			if int(r["cost"]["relics"]) > n and bool(r["can_build"]):
				r["can_build"] = false
				r["reason"] = "no_relics"
	return v


## No gold or bone and no flow of either: nothing can be afforded, upgraded or saved for.
func _dry(v: Dictionary) -> void:
	v["town"]["gold"] = 0.0
	v["town"]["bone"] = 0.0
	for r in v["hud"]["rates"]:
		r["rate"] = 0.0
	for r in v["catalog"]["buildings"]:
		if int(r["cost"]["relics"]) == 0 and bool(r["can_build"]):
			r["can_build"] = false
			r["reason"] = "no_gold"


## The label of the first job building (new or an upgrade) the tab would offer that costs no relics.
func _first_free_job(tab: Dictionary, bc: Dictionary, bv: Dictionary) -> String:
	for it in BuildSort.candidates(tab["items"], tab["ups"], tab["reserved"]):
		var r: Dictionary = it["row"]
		if bool(r["can_build"]) and not (r["lots"] as Array).is_empty() and int(r["cost"]["relics"]) == 0 and BuildSort.job_slots(String(r["building_id"]), bc) > 0:
			return BuildSort.label_of(String(r["building_id"]), bv)
	return ""


func _sug_of(v: Dictionary) -> Dictionary:
	return BuildSort.tab_suggestion(v, cfg["buildings_view"], cfg["buildings"], vcfg)["sug"]


func _td1_relics(mid: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var bc: Dictionary = cfg["buildings"]
	# the budget: the next tier's missing buildings in order, each paid from what is left
	var m3 := _with_relics(mid, 3, true)
	var marks: Array = BuildSort.gate_marks(m3)
	t.ok(marks.size() == 2 and marks[0] == {"id": "walls", "cost": 2, "ok": true} and marks[1] == {"id": "chapel_of_vats", "cost": 2, "ok": false},
		"relic budget: with 3 relics Walls (2) is affordable and then the Chapel (2) is not (%s)" % str(marks))
	t.ok(BuildSort.gate_marks(_with_relics(mid, 4, true)).all(func(m): return m["ok"]), "relic budget: 4 relics pay both")
	t.ok(BuildSort.gate_marks(_with_relics(mid, 0, true)).all(func(m): return not m["ok"]), "relic budget: no relics pay neither")
	t.ok(BuildSort.held_relics(m3) == 3, "relics held come from view_inventory (3)")
	var inv_only: Dictionary = m3.duplicate(true)
	inv_only["hud"]["relics"] = 9
	t.ok(BuildSort.held_relics(inv_only) == 3 and BuildSort.stocks(inv_only)["relics"] == 3.0, "relics held: the inventory wins over the hud copy")

	# the suggestion on midgame (3 relics): Walls stays (it is affordable); the Chapel is not a pick, the idle line skips it
	var tab3 := BuildSort.tab_suggestion(m3, bv, bc, vcfg)
	t.ok(String(tab3["sug"].get("building_id", "")) == "walls", "relics 3: the tag stays on Walls, which the relics pay for (%s)" % str(tab3["sug"]))
	var idle3 := HudModel.parts_text(HudModel.idle_parts(m3, vcfg, bv, bc, tab3))
	t.ok(not idle3.contains("Chapel") and idle3.begins_with("10 idle: "), "relics 3: the idle line does not name the unaffordable Chapel (%s)" % idle3)
	var name3 := _first_free_job(tab3, bc, bv)
	t.ok(name3 != "" and idle3.contains(name3), "relics 3: the idle line names the best relic-free job item, %s (%s)" % [name3, idle3])

	# a relic-blocked top pick with a relic-free need row: the relic-free row wins (a stale catalog, and a consistent one)
	for consistent in [false, true]:
		var v0 := _with_relics(mid, 0, consistent)
		var sug0: Dictionary = _sug_of(v0)
		var cost0 := 99
		for r in v0["catalog"]["buildings"]:
			if String(r["building_id"]) == String(sug0.get("building_id", "")):
				cost0 = int(r["cost"]["relics"])
		t.ok(not sug0.is_empty() and cost0 == 0 and String(sug0["building_id"]) not in ["walls", "chapel_of_vats"],
			"relic-free: 0 relics (%s catalog) suggests a relic-free building, not the gate (%s)" % ["consistent" if consistent else "stale", str(sug0)])
		var idle0 := HudModel.parts_text(HudModel.idle_parts(v0, vcfg, bv, bc))
		var free0 := _first_free_job(BuildSort.tab_suggestion(v0, bv, bc, vcfg), bc, bv)
		t.ok(free0 != "" and idle0.contains(free0) and not idle0.contains("Chapel"), "relic-free: 0 relics, the idle line names a relic-free job item, %s (%s)" % [free0, idle0])
		var au: Dictionary = BuildSort.autoplay_pick(v0, cfg)
		t.ok(String(au.get("building_id", "")) == String(sug0.get("building_id", "")), "relic-free: the autoplayer follows the tag (%s)" % str(au))
	# the save-for rule never saves for a relic-blocked row either
	var v1 := _with_relics(mid, 0, false)
	for r in v1["catalog"]["buildings"]:
		if String(r["building_id"]) in ["walls", "chapel_of_vats"]:
			r["can_build"] = false
			r["reason"] = "no_gold"
	t.ok(not _sug_of(v1).has("save") or String(_sug_of(v1).get("building_id", "")) not in ["walls", "chapel_of_vats"], "relic-free: no save-for a gate the relics can't open")

	# nothing relic-free left: the suggestion is the wall (the gate row itself while it still reads buildable, none when it can't be)
	var wall := _with_relics(mid, 0, false)
	_dry(wall)
	for r in wall["catalog"]["buildings"]:
		if int(r["cost"]["relics"]) == 0 and bool(r["can_build"]):
			r["can_build"] = false
			r["reason"] = "no_gold"
	var sw: Dictionary = _sug_of(wall)
	t.ok(String(sw.get("building_id", "")) in ["walls", "chapel_of_vats", "forge", "embalmer"], "wall: with nothing relic-free left the suggestion is the relic wall (%s)" % str(sw))
	var wc := _with_relics(mid, 0, true)
	_dry(wc)
	for r in wc["catalog"]["buildings"]:
		if int(r["cost"]["relics"]) == 0 and bool(r["can_build"]):
			r["can_build"] = false
			r["reason"] = "no_gold"
	t.ok(_sug_of(wc).is_empty(), "wall: and none while the sim says the gate can't be built (%s)" % str(_sug_of(wc)))
	var idlew := HudModel.parts_text(HudModel.idle_parts(wall, vcfg, bv, bc))
	t.ok(idlew.begins_with("10 idle: "), "wall: the idle line still says something (%s)" % idlew)

	# the pin lists each gate building with its own relic cost and a mark when the relics held pay for it
	var pin := func(v: Dictionary) -> String:
		var st := BuildSort.stocks(v)
		var items := BuildSort.sort_rows(v["catalog"]["buildings"], BuildSort.needs(v, {}, vcfg, bv, bc), bv, vcfg)
		return String(BuildSort.relic_gate(v, items, st, bv, vcfg).get("text", ""))
	t.ok(pin.call(m3) == "Needs relics: Walls and Gate 2 ✓ · Chapel of Vats 2. You have 3: raid a fort for more.", "pin: per building, Walls marked as affordable (%s)" % pin.call(m3))
	var m0 := _with_relics(mid, 0, true)
	t.ok(pin.call(m0) == "Needs relics: Walls and Gate 2 · Chapel of Vats 2. You have 0: raid a fort for more.", "pin: with none, no building is marked (%s)" % pin.call(m0))
	t.ok(pin.call(_with_relics(mid, 4, true)) == "", "pin: enough for both, no pin")
	t.ok(String(vcfg["relic_gate"]["mark_ok"]) == "✓" and String(vcfg["relic_gate"]["button"]) == "To the realm", "pin: the mark and the To the realm button are town.json texts")


## Item 2: the HUD's next-tier line says the relic wall on every tab, in a lit colour, with a route out.
func _td1_wall_line(day1: Dictionary, mid: Dictionary) -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var h: Dictionary = vcfg["hud"]
	var m3 := _with_relics(mid, 3, true)
	var nl: Dictionary = HudModel.next_line(m3, h, bv)
	t.ok(nl["text"] == "next: Town — needs 4 relics (have 3): raid a fort → Return to the realm" and nl["relics"], "wall line: relics short -> '%s'" % nl["text"])
	t.ok(HudModel.next_line(_with_relics(mid, 0, true), h, bv)["text"] == "next: Town — needs 4 relics (have 0): raid a fort → Return to the realm", "wall line: with none, have 0")
	var plain := HudModel.next_line(_with_relics(mid, 4, true), h, bv)
	t.ok(not plain["relics"] and plain["text"] == HudModel.next_tier_line(String(mid["town"]["tier"]), mid["town"]["next_tier"], h, bv),
		"wall line: relics are not the block -> today's line (%s)" % plain["text"])
	t.ok(not HudModel.next_line(day1, h, bv)["relics"], "wall line: day1 (nothing missing needs relics) keeps today's line")
	var one: Dictionary = m3.duplicate(true)
	one["town"]["next_tier"]["missing"] = ["walls"]
	one["inventory"]["relics"] = 1
	t.ok(HudModel.next_line(one, h, bv)["text"] == "next: Town — needs 2 relics (have 1): raid a fort → Return to the realm", "wall line: N is the missing gate buildings' relic costs, summed")
	var placed: Dictionary = m3.duplicate(true)
	placed["town"]["buildings"].append({"building_id": "walls", "lot_id": "lot-23", "level": 0, "state": "constructing", "progress": 0.1})
	t.ok(not HudModel.next_line(placed, h, bv)["relics"], "wall line: Walls placed, the Chapel's 2 relics are held (3): not a wall")
	placed["inventory"]["relics"] = 1
	t.ok(HudModel.next_line(placed, h, bv)["text"] == "next: Town — needs 2 relics (have 1): raid a fort → Return to the realm", "wall line: a gate building already placed is not asked for again")
	# lit: its ink reaches 4.5:1 on the ground, and the button is a 44 px target routed through the shell
	var ink := Palette.c(String(h["relic_ink"]), 1.0)
	t.ok(TownModel.contrast(ink, Palette.c("ground")) >= 4.5, "wall line: ink '%s' reaches 4.5:1 on ground (%.2f)" % [h["relic_ink"], TownModel.contrast(ink, Palette.c("ground"))])
	t.ok(String(h["text"]["next_relics"]).ends_with("→ Return to the realm") and not h["text"].has("next_relics_btn") and int(h["relic_border_px"]) >= 2,
		"wall line: it points at the one Return button, which gets a thick lit border (no second button)")
	t.ok(float(h["return_w_px"]) > 0.0 and TownUI.MIN_TARGET >= 44, "wall line: the Return button stays a >= 44 px target")
	t.ok(int(h["next_px"]) >= 12, "wall line: at least 12 px")
	var hud_src := FileAccess.get_file_as_string("res://scripts/town/town_hud.gd")
	var shell := FileAccess.get_file_as_string("res://scripts/town/covington.gd")
	t.ok(not hud_src.contains("finished"), "wall line: the HUD never emits finished itself")
	t.ok(not hud_src.contains("realm_pressed") and not shell.contains("realm_pressed") and shell.contains("_hud.return_pressed.connect(_on_return)"),
		"wall line: one exit only: the HUD's Return through the shell's _on_return, no realm_pressed")


## Item 3: a placed big undead carries the slab's name everywhere a big undead is named.
func _td1_names(mid: Dictionary) -> void:
	var slab: Dictionary = cfg["town"]["slab"]
	var raw := {"uid": "u7", "name": "Big u7", "kind": "hulk", "role": "bulwark", "place": "party",
		"stats": {"power": 3.0, "beef": 9.0, "wits": 1.0, "presence": 0.0, "speed": 2.0}}
	var slab_name := SlabLogic.display_name(raw, slab)
	t.ok(slab_name != "Big u7" and slab_name.ends_with("Hulk"), "names: the default 'Big u7' becomes '%s'" % slab_name)
	# the crypt roster's names (and the Foreman chooser's)
	var chosen := {"uid": "u4", "name": "Old Gristle", "kind": "hulk", "stats": raw["stats"]}
	var names := CryptLogic.display_names([raw, chosen], slab)
	t.ok(names == {"u7": slab_name, "u4": "Old Gristle"}, "names: the roster shows the slab name for the default and keeps a real one (%s)" % str(names))
	# the backups loss line
	var tx: Dictionary = vcfg["backups"]
	var pt := BackupsModel.party_text([raw, chosen], {"lot-3": "Market"}, {}, vcfg["crypt"], tx, slab)
	t.ok(pt == "the party: %s, Old Gristle" % slab_name, "names: the loss line names the party by the slab's names (%s)" % pt)
	# the Build tab's foreman line (BuildSort.stocks) and the foreman badge / walk-out
	var v: Dictionary = mid.duplicate(true)
	v["big_undead"]["big_undead"] = [raw]
	t.ok(BuildSort.stocks(v, slab)["foreman_names"] == {"u7": slab_name}, "names: the lot inspector's foreman is named by the slab (%s)" % str(BuildSort.stocks(v, slab)["foreman_names"]))
	var mk := _model()
	mk.update(v, VIEW_RECT)
	var lot_id := String(mk.lot("lot-04")["id"])
	var vb: Dictionary = v.duplicate(true)
	for b in vb["town"]["buildings"]:
		if String(b["lot_id"]) == lot_id:
			b["foreman"] = "u7"
	var ag := TownAgents.new(vcfg, cfg["buildings"], cfg["economy"], tempo_s, 7, slab)
	var m2 := _model()
	m2.update(vb, VIEW_RECT)
	ag.sync(m2, vb)
	t.ok(ag.foremen.size() == 1 and ag.foremen[0]["name"] == slab_name, "names: the foreman badge shows '%s' (%s)" % [slab_name, str(ag.foremen.map(func(f): return f["name"]))])
	# the walk-out: a creature just placed at a building walks out under the slab's name
	var va: Dictionary = vb.duplicate(true)
	for b in va["town"]["buildings"]:
		if String(b["lot_id"]) == lot_id:
			b["foreman"] = ""
	va["big_undead"]["big_undead"][0]["place"] = "crypt"
	var ag2 := TownAgents.new(vcfg, cfg["buildings"], cfg["economy"], tempo_s, 7, slab)
	var m3 := _model()
	m3.update(va, VIEW_RECT)
	ag2.sync(m3, va)
	vb["big_undead"]["big_undead"][0]["place"] = "town:" + lot_id
	var m4 := _model()
	m4.update(vb, VIEW_RECT)
	ag2.sync(m4, vb)
	t.ok(ag2.walkers.size() == 1 and ag2.walkers[0]["name"] == slab_name, "names: the walk-out carries '%s' (%s)" % [slab_name, str(ag2.walkers.map(func(w): return w["name"]))])
	# the debug raise names its creature by the slab's name for what is on the slab, never the demo's "Gravel"
	t.ok(CryptLogic.raise_name("Hulking-Brutal Hulk", raw, slab) == "Hulking-Brutal Hulk", "names: the debug raise keeps the slab's evaluated name")
	t.ok(CryptLogic.raise_name("", raw, slab) == slab_name, "names: with no slab name it falls back to the minted creature's slab name")
	# every slab name is a legal name (the naming step defaults its field to it)
	var longest := 0
	for kind in slab["anatomy"]:
		for a in SlabLogic.STATS:
			for b in SlabLogic.STATS:
				var st := {"power": 0.0, "beef": 0.0, "wits": 0.0, "presence": 0.0, "speed": 0.0}
				st[a] = 6.0
				st[b] = st[b] + 6.0
				var nm := SlabLogic.name_for(String(kind), st, slab)
				longest = maxi(longest, nm.length())
				if not CryptLogic.check_name(nm)["ok"]:
					t.ok(false, "names: '%s' is a legal name" % nm)
	t.ok(longest <= CryptLogic.NAME_MAX, "names: every slab name fits the %d-character limit (longest %d)" % [CryptLogic.NAME_MAX, longest])
	var crypt_src := FileAccess.get_file_as_string("res://scripts/town/panel_crypt.gd")
	t.ok(crypt_src.contains("_name_edit.text = String(_ev.get(\"name\", \"\"))"), "names: the naming step's field defaults to the slab's name")


## Item 4: placeholders say so before the fact, in player words; no dev tags on screen.
func _td1_placeholders(day1: Dictionary, mid: Dictionary, pre: Dictionary) -> void:
	var slab: Dictionary = cfg["town"]["slab"]
	var ct: Dictionary = vcfg["crypt"]
	# raise: a preview note above the hold, the after-line without dev tags, cleared a few seconds later
	t.ok(ct["raise_note"] == "preview: nothing is spent and no big undead rises yet", "raise: the note before the hold (%s)" % ct["raise_note"])
	t.ok(ct["risen_stub"] == "coming: raised undead join the town in a later build", "raise: the after-line (%s)" % ct["risen_stub"])
	t.ok(float(ct["stub_line_s"]) > 0.0 and float(ct["stub_line_s"]) <= 10.0, "raise: the after-line clears a few seconds after the rings settle (%s s)" % ct["stub_line_s"])
	t.ok(slab.has("raise_wired") and slab["raise_wired"] == true and not CryptLogic.raise_is_preview(slab, false),
		"raise: E3 made the raise real, so slab.raise_wired is on and the preview note never shows (town-i M2)")
	var stub: Dictionary = slab.duplicate()
	stub["raise_wired"] = false
	t.ok(CryptLogic.raise_is_preview(stub, false), "raise: unwired, a raise that returned nothing yet is a preview")
	t.ok(not CryptLogic.raise_is_preview(stub, true), "raise: once a raise returned a creature, the note goes away")
	var wired: Dictionary = slab.duplicate()
	wired["raise_wired"] = true
	t.ok(not CryptLogic.raise_is_preview(wired, false), "raise: a wired raise needs no note")
	t.ok(CryptLogic.raise_returned_creature({"ok": true, "big_undead": {"uid": "u9"}}) and not CryptLogic.raise_returned_creature({"ok": true, "big_undead": {"uid": ""}})
		and not CryptLogic.raise_returned_creature({"ok": false, "big_undead": {}}), "raise: only a non-empty uid says the raise is real")
	t.near(CryptLogic.line_left(4.0, 1.5), 2.5, 0.0001, "raise: the line's clock runs down")
	t.near(CryptLogic.line_left(1.0, 3.0), 0.0, 0.0001, "raise: and stops at 0")
	# backups: the stub outcome/respawn line and the ladder step say 'coming'
	var tx: Dictionary = vcfg["backups"]
	var clone := {"outcome": "clone", "respawn_s": 0.0, "loses": []}
	t.ok(tx.has("numbers_wired") and tx["numbers_wired"] == true and not BackupsModel.numbers_pending(clone, tx),
		"backups: E3 made the death numbers real, so numbers_wired is on and nothing reads as pending (town-i M2)")
	tx = tx.duplicate()
	tx["numbers_wired"] = false
	t.ok(BackupsModel.numbers_pending(clone, tx), "backups: unwired, a clone with respawn 0 reads as pending")
	t.ok(BackupsModel.numbers_pending({"outcome": "unmade", "respawn_s": 600.0}, tx) == false, "backups: a real wait (respawn_s > 0) shows the view is live")
	t.ok(BackupsModel.numbers_pending({"outcome": "phylactery", "respawn_s": 0.0}, tx) == false, "backups: a phylactery outcome shows the view is live")
	var live: Dictionary = tx.duplicate()
	live["numbers_wired"] = true
	t.ok(not BackupsModel.numbers_pending(clone, live), "backups: wired, never pending")
	t.ok(BackupsModel.outcome_text(clone, tx, true) == "A ready clone: she wakes in Covington at once (numbers coming)", "backups: the outcome line is tagged (%s)" % BackupsModel.outcome_text(clone, tx, true))
	t.ok(BackupsModel.outcome_text(clone, tx) == "A ready clone: she wakes in Covington at once", "backups: untagged when live")
	t.ok(BackupsModel.ladder_now_text(tx, true) == "now · numbers coming" and BackupsModel.ladder_now_text(tx, false) == "now", "backups: the ladder's current step says numbers coming")
	t.ok(BackupsModel.death_sig({"backups": {"death": clone}}) != BackupsModel.death_sig({"backups": {"death": {"outcome": "clone", "respawn_s": 60.0, "loses": []}}}), "backups: a live respawn moves the death signature")
	# foreman: a 'coming' note by the button and on the placed line
	t.ok(not String(ct["foreman_coming"]).contains("coming") and String(ct["foreman_coming"]).contains("speed") and String(ct["foreman_coming"]).contains("morale"),
		"foreman: the note says what a foreman does (E3-3: speed on job output, presence on morale), not 'coming' (%s)" % ct["foreman_coming"])
	# clarity round 3: every place button says what it does (a tooltip each), and the roster's head says it once on screen
	var tips := CryptLogic.place_tips(ct, 0.6)
	t.ok(tips.size() == 4 and tips.values().all(func(s): return String(s) != "" and not String(s).contains("{")),
		"places: Crypt, Party, Foreman and Siege each carry a filled tooltip (%s)" % str(tips))
	t.ok(String(tips["party"]).contains("next raid") and String(tips["party"]).contains("lost"),
		"places: Party says it goes into your next raid, and is lost if Relish dies there ('%s')" % tips["party"])
	t.ok(String(tips["siege"]).contains("60%") and String(tips["foreman"]).contains("speed") and String(tips["foreman"]).contains("morale"),
		"places: Siege's share comes from the block given; Foreman says speed and morale")
	var pl := String(ct["places_line"])
	t.ok(pl.contains("Crypt") and pl.contains("Party") and pl.contains("next raid") and pl.contains("Foreman") and pl.contains("Siege")
		and not pl.to_lower().contains("the run"), "places: the line under the roster's head names all four ('%s')" % pl)
	# no dev tags in any text a player reads
	var bad := PackedStringArray()
	var re := RegEx.new()
	re.compile("\\bE[0-9][a-z]?\\b|(?i:\\bapi\\b|\\bapi-|stand-in|stand in)|TODO|STANDIN")  # an upper-case E3 (node ids like e1 are not tags)
	for f in ["res://configs/town.json", "res://configs/buildings_view.json"]:
		_scan_tags(TestUtil.load_json(f), f, "", re, bad)
	t.ok(bad.is_empty(), "no dev tags in town.json / buildings_view.json strings (%s)" % ", ".join(bad))
	# the scene scripts' on-screen strings (string literals, not comments) too
	var dir := DirAccess.open("res://scripts/town")
	var lit := RegEx.new()
	lit.compile("\"[^\"\\n]*\"")
	var lit_bad := PackedStringArray()
	for fn in dir.get_files():
		if not fn.ends_with(".gd"):
			continue
		for line in FileAccess.get_file_as_string("res://scripts/town/" + fn).split("\n"):
			var code := String(line)
			var hash := code.find("#")
			if hash >= 0 and not code.substr(0, hash).contains("\""):
				continue
			for m in lit.search_all(code):
				var str_lit := m.get_string()
				if re.search(str_lit) != null and not str_lit.begins_with("\"res://"):
					lit_bad.append("%s: %s" % [fn, str_lit])
	t.ok(lit_bad.is_empty(), "no dev tags in the town scripts' string literals (%s)" % "; ".join(lit_bad))


func _scan_tags(x: Variant, file: String, path: String, re: RegEx, out: PackedStringArray) -> void:
	if x is Dictionary:
		for k in x:
			_scan_tags(x[k], file, path + "/" + str(k), re, out)
	elif x is Array:
		for i in x.size():
			_scan_tags(x[i], file, path + "/" + str(i), re, out)
	elif x is String and re.search(x) != null:
		out.append("%s%s = '%s'" % [file.get_file(), path, x])


## T-d2: the backups headline, the honest vat line, one Off per stance, the slab's stats in town words, text size and contrast.
func _td2(day1: Dictionary, mid: Dictionary) -> void:
	t.suite("town-td2")
	var tx: Dictionary = vcfg["backups"]
	var slab: Dictionary = cfg["town"]["slab"]
	var labels: Dictionary = vcfg["job_labels"]
	# 1. backups: the loss is the large first line, the comfort line its subtitle
	t.ok(int(tx.get("loses_px", 0)) >= 20 and int(tx.get("outcome_px", 99)) < int(tx.get("loses_px", 0)) and int(tx.get("outcome_px", 0)) >= 12,
		"backups: the loss line is the large one (loses_px %s), the outcome its subtitle (outcome_px %s)" % [tx.get("loses_px"), tx.get("outcome_px")])
	var party := [{"uid": "u1", "name": "Old Gristle", "kind": "hulk", "place": "party", "stats": {}}]
	var line := BackupsModel.loses_line(["party", "unbanked_loot"], party, {}, {}, vcfg["crypt"], tx, slab)
	t.ok(line == "She would lose: the party: Old Gristle, loot since the last checkpoint.", "backups: the headline names the party and the loot (%s)" % line)
	t.ok(BackupsModel.loses_line([], [], {}, {}, vcfg["crypt"], tx, slab) == "She would lose: nothing else.", "backups: nothing to lose still reads as a line")
	# 2. vats: with idle hands, staffing costs nothing and says so
	var idle10 := BackupsModel.staffing_cost_text([], labels, tx, false, 10.7)
	t.ok(idle10 == "10 idle hands: staffing costs nothing today", "vat: idle hands round down, 10.7 -> 10 (%s)" % idle10)
	t.ok(BackupsModel.staffing_cost_text([], labels, tx, true, 10.7) == "10 idle hands: unstaffing frees nothing a job needs today", "vat: a staffed vat says unstaffing frees nothing (%s)" % BackupsModel.staffing_cost_text([], labels, tx, true, 10.7))
	t.ok(BackupsModel.staffing_cost_text([], labels, tx, true, 1.9) == "1 idle hand: unstaffing frees nothing a job needs today", "vat: staffed, one idle hand is singular")
	t.ok(BackupsModel.staffing_cost_text([], labels, tx, false, 1.9) == "1 idle hand: staffing costs nothing today", "vat: one idle hand is singular")
	t.ok(BackupsModel.staffing_cost_text([], labels, tx, false, 0.9) == "staffing takes no hand from a job", "vat: under one whole idle hand keeps the old line")
	t.ok(BackupsModel.staffing_cost_text([{"id": "stall", "delta": -1.0}], labels, tx, false, 10.0) == "staffing takes 1 hand from Stall", "vat: a hand that does move is still named")
	var idle_town := {"jobs": [{"id": "pit", "slots": 2, "staffed": 2.0}], "buildings": [], "workers": {"idle": 10.4}, "ladder": ["pit"]}
	var idle_views := {"town": idle_town, "backups": {"vats": [{"slot": 0, "staffed": false}, {"slot": 1, "staffed": true}]}}
	var proj := func(order: Array, extra := {}) -> Array: return TownStandins.project(idle_views, order, cfg["buildings"], extra)["jobs"]
	var costs := BackupsModel.staffing_costs(idle_views, proj, labels, tx)
	t.ok(costs.size() == 2 and costs[0] == idle10 and String(costs[1]).begins_with("10 idle hands"), "vat: the panel's lines carry the idle count (%s)" % str(costs))
	idle_town["workers"]["idle"] = 11.2
	t.ok(BackupsModel.vats_sig(idle_views, BackupsModel.staffing_costs(idle_views, proj, labels, tx)) != BackupsModel.vats_sig(idle_views, costs), "vat: the idle count is in the vats signature through the line")
	# 3. stances: the toggle says On/Off, the chips never repeat it
	var stx: Dictionary = vcfg["behaviour"]
	t.ok(TownBehaviour.stance_chips({"on": false}, stx).is_empty() and TownBehaviour.stance_chips({"on": true}, stx).is_empty(), "stance: no 'off' or 'on' chip beside the toggle")
	t.ok(TownBehaviour.stance_chips({"on": true, "suspended": true, "active": true}, stx) == ["suspended", "active"], "stance: suspended and active still show")
	# 4. slab stats in town words
	var jargon := ["foreman pace", "carters", "the carvers front", "the giants front", "the swarm front", "the raw front", "foreman throughput"]
	var sh: Dictionary = slab.get("stat_helps", {})
	for st in SlabLogic.STATS:
		var h := String(sh.get(st, ""))
		t.ok(h != "", "slab: %s has a town-words line (%s)" % [st, h])
		for j in jargon:
			t.ok(not h.contains(j), "slab: %s line has no '%s'" % [st, j])
		t.ok(CryptLogic.stat_helps(st, slab, vcfg["crypt"]) == h, "slab: the crypt panel reads slab.stat_helps for %s" % st)
	var bvw := TestUtil.load_json("res://configs/buildings_view.json")
	t.ok(String(sh["beef"]).contains(String(bvw["charnel_house"]["label"])) and String(sh["beef"]).contains(String(bvw["raising_pit"]["label"])), "slab: beef points at the Charnel House and the Raising Pit (%s)" % sh["beef"])
	for nm in ["well", "bakery", "inn"]:
		t.ok(String(sh["presence"]).contains(String(bvw[nm]["label"])), "slab: presence points at the %s (%s)" % [nm, sh["presence"]])
	t.ok(String(sh["speed"]).contains(String(bvw["stables"]["label"])) and not String(sh["speed"]).contains(String(bvw["market"]["label"])), "slab: speed points at the Stables, not the Market (%s)" % sh["speed"])
	for r in slab["roles"]:
		for j in jargon:
			t.ok(not String(slab["roles"][r]["good_for"]).contains(j), "slab: role %s line has no '%s'" % [r, j])
	# 5. text size and contrast: configured sizes at 12 px or more, the text colours at 4.5:1 on the ground (3:1 for lines)
	var sizes := {"legend": vcfg["legend"]["px"], "hud.split": vcfg["hud"]["split_px"], "hud.name": vcfg["hud"]["name_px"], "hud.stock": vcfg["hud"]["stock_px"],
		"hud.next": vcfg["hud"]["next_px"], "badge": vcfg["badge"]["px"], "status": vcfg["status"]["px"], "pick": vcfg["pick"]["px"], "ring_order": vcfg["ring_order"]["px"],
		"upgrade_mark": vcfg["upgrade_mark"]["px"], "walkout badge": vcfg["walkout"]["badge_px"], "crypt small": vcfg["crypt"]["small_px"],
		"crypt text": vcfg["crypt"]["text_px"], "preview caption": vcfg["crypt"]["preview"]["caption_px"], "pip count": vcfg["pip_count_px"],
		"backups subtitle": tx["outcome_px"], "backups ladder header": tx["ladder_header_px"], "backups title": tx["title_px"]}
	for k in sizes:
		t.ok(float(sizes[k]) >= 12.0, "text size: %s is %s px (>= 12)" % [k, sizes[k]])
	var ground := Palette.c("ground")
	for key in ["text", "text_dim", "danger", "select", "relish", "undead", "living"]:
		var cr := _wcag(Palette.c(key), ground)
		t.ok(cr >= 4.5, "contrast: %s on ground is %.2f:1 (>= 4.5)" % [key, cr])
	var on_btn := _wcag(Palette.c("text_dim"), Palette.c("ring_track"))
	t.ok(on_btn >= 4.5, "contrast: text_dim on a button face is %.2f:1 (>= 4.5)" % on_btn)
	var on_hover := _wcag(Palette.c("text_dim"), Palette.c("graticule"))
	t.ok(on_hover >= 4.5, "contrast: text_dim on a hovered button is %.2f:1 (>= 4.5)" % on_hover)
	var il: Dictionary = vcfg["idle_line"]
	var line_cr := _wcag(_over(Palette.c(String(il["key"])), float(il["alpha"]), ground), ground)
	t.ok(line_cr >= 3.0, "contrast: the unstaffed outline is %.2f:1 on ground (>= 3 for a line)" % line_cr)
	# a walk seeded from the entry itself names the slab's name, never "Big u9"
	var e9 := {"uid": "u9", "name": "Big u9", "kind": "hulk", "stats": {"beef": 3.0}, "place": "town:lot-1"}
	var tr := TownSetPiece.transitions({"u9": "crypt"}, [e9], true, slab)
	t.ok(tr["starts"].size() == 1 and String(tr["starts"][0]["name"]) == SlabLogic.display_name(e9, slab) and not String(tr["starts"][0]["name"]).begins_with("Big u"),
		"walk seed: the slab's name (%s)" % str(tr["starts"]))


static func _lum(c: Color) -> float:
	var f := func(x: float) -> float: return x / 12.92 if x <= 0.03928 else pow((x + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


static func _wcag(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _over(c: Color, alpha: float, bg: Color) -> Color:
	return Color(c.r * alpha + bg.r * (1.0 - alpha), c.g * alpha + bg.g * (1.0 - alpha), c.b * alpha + bg.b * (1.0 - alpha))
