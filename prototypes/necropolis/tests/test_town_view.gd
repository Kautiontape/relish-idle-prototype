extends RefCounted
## TownModel, TownStandins and the town plan: silhouettes, lots, streets, tier walls, glow, pips
## and the demo city. Views come from the fixtures the way the Covington shell fetches them.

const VIEW_RECT := Rect2(0, 72, 1040, 828)  # the town view at 1600x900: HUD 72 on top, dock 560 right
const NEEDS := ["gold", "bone", "bodies", "mint", "morale", "housing", "quality", "backups", "stances",
	"tithe", "front", "warden", "relics"]
const INKS := ["undead", "living", "town", "relish"]
const LIGHT_BY := ["staffing", "living", "always"]

var t: TestUtil
var cfg: Dictionary
var vcfg: Dictionary


func _model(town_cfg: Dictionary = {}) -> TownModel:
	return TownModel.new(cfg["town"] if town_cfg.is_empty() else town_cfg, cfg["buildings_view"],
		cfg["buildings"], cfg["economy"])


func _views(fixture: String) -> Dictionary:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	var r: Dictionary = s.cmd_debug_load_fixture(fixture)
	t.ok(r["ok"], "fixture %s loads" % fixture)
	return {
		"town": s.view_town(), "hud": s.view_hud(), "catalog": s.view_catalog(),
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
	_edge_rates(day1, demo)
	_drift(day1)
	_truncate()
	_wall_ring(day1, mid)
	_crypt_ink(day1)
	_view_keys()
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
	m.update(demo, VIEW_RECT)
	t.ok(m.tier == "city", "the demo is a city")
	var tiers: Dictionary = cfg["economy"]["town"]["tiers"]
	for tier in cfg["town"]["view"]["tier_walls"]:
		var w := m.walls(tier)
		t.ok(w.size() >= 4, "%s wall is a polyline" % tier)
		var n := int(tiers[tier]["lots"])
		var enclosed := true
		for i in n:
			var r: Rect2 = m.lots[i]["rect"]
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


func _standin(day1: Dictionary) -> void:
	var m := _model()
	m.update(day1, VIEW_RECT)
	t.ok(m.staffing_standin, "every output is the E1 stub: the staffing stand-in is on")
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
	t.near(m.lot("lot-01")["building"]["glow"], float(vcfg["glow_always"]), 0.0001, "the crypt is always lit at glow_always")


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
	t.near(town["workers"]["total"], 180.0, 0.001, "demo: 180 workers")
	t.near(town["workers"]["idle"] + staffed, 180.0, 0.001, "demo: staffed plus idle is the workforce")
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


## Expected rate per street: the staffed workers of every job building whose route from the plaza
## to its door walks that street.
func _expected_rates(m: TownModel) -> Dictionary:
	var want := {}
	for l in m.lots:
		var b: Dictionary = l["building"]
		if b.is_empty() or b["slots"] <= 0 or b["staffed"] <= 0.0:
			continue
		var p := m.path("plaza", l["door"])
		for k in range(1, p.size()):
			var key := _ek(p[k - 1], p[k])
			want[key] = float(want.get(key, 0.0)) + b["staffed"]
	return want


func _edge_rates(day1: Dictionary, demo: Dictionary) -> void:
	for pair in [["day1", day1], ["demo", demo]]:
		var m := _model()
		m.update(pair[1], VIEW_RECT)
		var want := _expected_rates(m)
		var match_all := true
		var lit := 0
		for s in m.streets:
			var w := float(want.get(_ek(s["from"], s["to"]), 0.0))
			match_all = match_all and is_equal_approx(s["rate"], w)
			lit += 1 if s["rate"] > 0.0 else 0
		t.ok(match_all, "%s: each street carries the staffed workers routed through it" % pair[0])
		t.ok(lit > 0 and lit < m.streets.size(), "%s: some streets lit, the rest off (%d of %d)" % [pair[0], lit, m.streets.size()])
		var out_of_plaza := 0.0
		for s in m.streets:
			if s["near"] == m.nodes["plaza"]:
				out_of_plaza += s["rate"]
		var routed := 0.0
		for l in m.lots:
			var b: Dictionary = l["building"]
			if not b.is_empty() and b["slots"] > 0 and l["door"] != "plaza":
				routed += b["staffed"]
		t.near(out_of_plaza, routed, 0.0001, "%s: what leaves the plaza is every staffed worker not at a plaza door" % pair[0])
	var m := _model()
	m.update(_patched(day1, "lot-03", {"staffed": 0.0}), VIEW_RECT)
	var charnel_door: String = m.lot("lot-03")["door"]
	var p := m.path("plaza", charnel_door)
	var dark := true
	for s in m.streets:
		for k in range(1, p.size()):
			if _ek(p[k - 1], p[k]) == _ek(s["from"], s["to"]):
				dark = dark and is_zero_approx(s["rate"])
	t.ok(dark, "an unstaffed building's route goes dark (zero rate is off)")
	m.update(day1, VIEW_RECT)
	m.update({}, VIEW_RECT)
	var none := true
	for s in m.streets:
		none = none and s["rate"] == 0.0
	t.ok(none, "rates reset on every update (no building, no stream)")


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


## Every number and key the town view reads lives in town.json's view block.
func _view_keys() -> void:
	var keys := ["relish_away_ink", "floor_tint", "floor_reach_px", "lot_pulse_gain", "bed", "bed_line", "junction_px",
		"flow_ref", "flow_glow", "chevron_px", "blueprint_dash_px", "blueprint_w_px", "locked_dot", "sil_w_px",
		"sil_glow", "sil_core_mix", "dim_w_px", "band_px", "pip_px", "pip_gap_px", "pip_glow", "slot_tick_px",
		"group_gap_px", "progress_ticks", "progress_tick_w_px", "reveal_rate", "head", "warn", "slab_rings_px",
		"slab_ring_w_px", "slab_ring_alpha", "slab_ring_reach_px", "label_px", "wall_w_px", "wall_glow", "tierup_beats",
		"tierup_head", "tierup_flash", "demo_tierup", "slot_open_w_px", "pip_w_px", "chevron_w_mul"]
	var nested := {"head": ["core_px", "ring_mul", "ring_w_px", "glow"], "warn": ["size_px", "line_px", "glow", "bang_px", "dot_px"],
		"tierup_head": ["len_px", "gain", "w_mul", "ring_mul", "ring_w_px", "dot_mul", "glow"], "demo_tierup": ["tier", "delay_s"],
		"bed": ["key", "alpha", "width_px"], "bed_line": ["key", "alpha", "width_px"], "locked_dot": ["key", "alpha", "step_px", "size_px"]}
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
