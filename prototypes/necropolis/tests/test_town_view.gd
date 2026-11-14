extends RefCounted
## TownModel, TownStandins, TownAgents and the town plan: silhouettes, lots, streets, tier walls,
## glow, pips, the demo city and the agents (counts, lockstep gait, trade arcs, carts, Relish).
## Views come from the fixtures the way the Covington shell fetches them.

const VIEW_RECT := Rect2(0, 72, 1040, 828)  # the town view at 1600x900: HUD 72 on top, dock 560 right
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
	_agent_seed(day1)
	_agent_loops(day1, demo)
	_trade_arcs(day1)
	_trade_standin(day1)
	_carts(day1)
	_relish(day1)
	_foremen(mid)
	_edge_rates(day1, demo)
	_build_needs(day1)
	_build_sort(day1)
	_build_reasons(day1)
	_build_queue(day1)
	_build_inspect(day1, mid)
	_build_unique(day1)
	_build_eta(day1)
	_build_benefit()
	_build_suggest(day1)
	_build_ghosts(day1)
	_build_chips()
	_build_caps(day1)
	_build_lot_refusal()
	_lot_hit(day1)
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
## [model, agents] synced to `views` (a fixed seed, so every run walks the same way).
func _agents(views: Dictionary, econ: Dictionary = {}) -> Array:
	var m := _model()
	m.update(views, VIEW_RECT)
	var a := TownAgents.new(vcfg, cfg["buildings"], cfg["economy"] if econ.is_empty() else econ, tempo_s, 7)
	a.sync(m, views)
	return [m, a]


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
	t.ok(a.living_count() == roundi(town["living"]), "day1 on entry: one living agent per living person (%d)" % a.living_count())
	t.ok(a.undead_scale == 1 and a.living_scale == 1, "day1 is under the caps: 1 stroke = 1")
	var spots := {}
	for u in a.undead + a.living:
		spots["%d,%d" % [roundi(u.pos.x), roundi(u.pos.y)]] = true
	t.ok(spots.size() >= a.undead.size() + a.living.size() - 2, "on entry the agents stand spread along their loops, not stacked")
	_run(a, 30.0)
	t.ok(_counts_match(a, town) and a.living_count() == roundi(town["living"]), "after 30 s of walking the counts still equal the stream")

	var big: Dictionary = day1.duplicate(true)
	big["town"]["workers"]["idle"] = 300.0
	var dtown: Dictionary = big["town"]
	var total := float(dtown["workers"]["idle"])
	for j in dtown["jobs"]:
		total += float(j["staffed"])
	var k := ceili(total / float(vcfg["max_undead_agents"]))
	a = _agents(big)[1]
	t.ok(k > 1 and a.undead_scale == k, "crowd: %d workers over max_undead_agents %d: 1 stroke = %d (got %d)"
		% [total, vcfg["max_undead_agents"], k, a.undead_scale])
	t.ok(_counts_match(a, dtown, k), "crowd: every job and the idle sampled by k")
	t.ok(a.undead.size() <= int(vcfg["max_undead_agents"]) + dtown["jobs"].size(), "crowd: the strokes stay at the cap (%d)" % a.undead.size())
	a = _agents(demo)[1]
	t.ok(a.undead_scale == 1 and _counts_match(a, demo["town"]) and a.count("idle") == 8,
		"demo: every job building staffed, 8 idle at the crypt, under the cap (1 stroke = 1)")
	var lk := ceili(float(pre["town"]["living"]) / float(vcfg["max_living_agents"]))
	a = _agents(pre)[1]
	t.ok(lk > 1 and a.living_scale == lk and a.living_count() == roundi(float(pre["town"]["living"]) / float(lk)),
		"pre_vei: %.0f living over max_living_agents: 1 stroke = %d, %d strokes" % [pre["town"]["living"], lk, a.living_count()])


func _agent_growth(day1: Dictionary) -> void:
	var pair := _agents(day1)
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	var more: Dictionary = day1.duplicate(true)
	more["town"]["workers"]["idle"] = 20.0
	more["town"]["living"] = 30.0
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
		gradual = gradual and a.count("idle") <= rate * clock + 1.0 + 1e-6 and a.living_count() - 10 <= rate * clock + 1.0 + 1e-6
		for u in a.undead:
			if not old.has(u) and first_u == Vector2.INF:
				first_u = u.pos
		for u in a.living:
			if not old.has(u) and first_l == Vector2.INF:
				first_l = u.pos
	t.ok(gradual, "growth is gradual: at most spawn_per_s new agents a second per kind")
	t.ok(a.count("idle") == 20 and a.living_count() == 30, "and it reaches the stream: 20 idle, 30 living")
	var crypt := (m.lot("lot-01")["building"]["rect"] as Rect2).get_center()
	var step := float(vcfg["step_px"]) * m.scale
	t.ok(first_u.distance_to(crypt) < 60.0 + 4.0 * step, "new undead rise at the crypt")
	t.ok(first_l.distance_to(m.nodes["gate"]) < 4.0 * float(vcfg["lane_px"]) + 12.0, "new living walk in at the gate")
	_resync(m, a, day1)
	var before := a.living_count()
	a.step(1.0 / fps, 0.0, false)
	t.ok(a.living_count() >= before - 1 and a.count("idle") >= 19, "shrinking is gradual too")
	_run(a, 200.0, clock)
	t.ok(a.count("idle") == 0 and a.living_count() == 10 and a.undead.size() == 6 and a.living.size() == 10,
		"the removed agents walk home (crypt, gate) and are gone: %d undead, %d living" % [a.undead.size(), a.living.size()])


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
	var pair := _agents(day1)
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	var clock := _run(a, 2.0)
	var before := {}
	for u in a.undead + a.living:
		before[u] = [u.pos, u.dir]
	clock = _run(a, 10.0, clock, true)
	var still := true
	for u in before:
		still = still and u.pos == before[u][0] and u.dir == before[u][1]
	t.ok(still, "reduced motion: no agent moves or turns, whatever the beat does")
	var more: Dictionary = day1.duplicate(true)
	more["town"]["workers"]["idle"] = 4.0
	more["town"]["living"] = 12.0
	_resync(m, a, more)
	_run(a, 10.0, clock, true)
	still = true
	for u in before:
		still = still and u.pos == before[u][0]
	t.ok(a.count("idle") == 4 and a.living_count() == 12 and still, "reduced motion: counts still follow the stream; the others stay put")
	var calm := true
	for u in a.undead:
		calm = calm and u.tilt == 0.0 and u.flash == 0.0
	t.ok(calm, "reduced motion: no beat actions")
	_resync(m, a, day1)
	_run(a, 10.0, clock, true)
	t.ok(a.undead.size() == 6 and a.living.size() == 10, "reduced motion: removed agents vanish in place")


func _agent_missing(day1: Dictionary) -> void:
	var v: Dictionary = day1.duplicate(true)
	var keep: Array = []
	for b in v["town"]["buildings"]:
		if b["building_id"] != "charnel_house":
			keep.append(b)
	v["town"]["buildings"] = keep
	var a: TownAgents = _agents(v)[1]
	t.ok(a.count("haul") == 0 and a.count("idle") == 3, "no charnel house: its 3 haulers idle at the crypt")
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
	t.ok(a.count("haul") == 0 and a.count("idle") == 3, "a job building gone mid-run re-tasks its agents to idle at once")

	var b2: Dictionary = day1.duplicate(true)
	b2["town"]["jobs"].append({"id": "build", "slots": 2, "staffed": 2.0})
	a = _agents(b2)[1]
	t.ok(a.count("build") == 0 and a.count("idle") == 2, "build with nothing under construction: the builders idle")
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
	var up := _patched(day1, "lot-03", {"state": "constructing", "progress": 0.4})
	var pair := _agents(day1)
	var m: TownModel = pair[0]
	var a: TownAgents = pair[1]
	var clock := _run(a, 1.0)
	# a pit worker on its way to the pit with a body when the charnel house goes up for upgrade
	var guard := 0
	while guard < 600 and not _any_carry(a):
		clock = _run(a, 0.1, clock)
		guard += 1
	t.ok(_any_carry(a), "a pit worker is carrying before the upgrade")
	_resync(m, a, up)
	clock = _run(a, 90.0, clock)
	t.ok(_holding(a, ["pit"]) > 0, "charnel house under construction: pit workers stand at the pit")
	var carried := false
	for u in a.undead:
		carried = carried or (u.holding and u.carry)
	t.ok(not carried, "a held pit worker carries no pip")
	_resync(m, a, day1)
	clock = _run(a, 1.0, clock)
	t.ok(_holding(a, ["pit", "haul"]) == 0, "charnel house active again: no pit or haul worker is still held")
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

	# a stall worker leaves a market that is upgrading (and stops being a seller)
	var mk := _patched(day1, "lot-04", {"state": "constructing", "progress": 0.4})
	pair = _agents(day1)
	m = pair[0]
	a = pair[1]
	clock = _run(a, 1.0)
	_resync(m, a, mk)
	clock = _run(a, 10.0, clock)
	t.ok(_holding(a, ["stall"]) == 0, "a market under construction holds no stall worker")


func _any_carry(a: TownAgents) -> bool:
	for u in a.undead:
		if u.carry:
			return true
	return false


func _agent_seed(day1: Dictionary) -> void:
	var m := _model()
	var a := TownAgents.new(vcfg, cfg["buildings"], cfg["economy"], tempo_s, 7)
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
		ends = ends and arc["seller"] == seller and not arc["buyer"].undead
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


func _trade_standin(day1: Dictionary) -> void:
	var a: TownAgents = _agents(day1)[1]
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
		var want := SlabLogic.slots_for(kind, cfg["town"]["slab"]).size()
		t.ok(want > 0 and a.foremen[0]["strokes"] == want, "no filled_slots in view_big_undead yet: the %s's anatomy slots (%d)" % [kind, want])
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
		"group_gap_px", "progress_ticks", "progress_tick_w_px", "reveal_rate", "head", "warn", "slab_rings_px",
		"slab_ring_w_px", "slab_ring_alpha", "slab_ring_reach_px", "label_px", "wall_w_px", "wall_glow", "tierup_beats",
		"tierup_head", "tierup_flash", "demo_tierup", "slot_open_w_px", "pip_w_px", "chevron_w_mul",
		"max_undead_agents", "max_living_agents", "spawn_per_s", "steps_per_beat", "step_duty", "step_px",
		"undead_dwell_steps", "haul_away_steps", "idle_dwell_steps", "idle_ring_px", "lane_px", "front_gap_px",
		"post_spread", "stall_shuffle_px", "hammer_deg", "living_speed_px", "living_dwell_s", "living_sway_px",
		"living_sway_stride_px", "trade_arc_s", "trade_reach_px", "max_trade_arcs", "cart_town_frac", "cart_pip_mass",
		"relish_light_r", "relish_brighten", "flow_smooth_s", "foreman_strokes", "standin_sales_per_stall", "standin_sales_per_living", "agent",
		"gate_reasons", "protected", "queue_max", "cap_buildings", "demolish_confirm_s", "placement_dim", "hit_min_px", "cap_bar",
		"reasons", "states", "needs", "queue_text", "benefit", "card", "hover", "suggest", "ghost", "flash", "shortage_text"]
	var nested := {"head": ["core_px", "ring_mul", "ring_w_px", "glow"], "warn": ["size_px", "line_px", "glow", "bang_px", "dot_px"],
		"tierup_head": ["len_px", "gain", "w_mul", "ring_mul", "ring_w_px", "dot_mul", "glow"], "demo_tierup": ["tier", "delay_s"],
		"bed": ["key", "alpha", "width_px"], "bed_line": ["key", "alpha", "width_px"], "locked_dot": ["key", "alpha", "step_px", "size_px"],
		"agent": ["undead_len_px", "undead_w_px", "undead_glow", "core_px", "flash_mul", "carry_px", "living_len_px",
			"living_bend", "living_w_px", "living_ring_px", "living_glow", "big_px", "big_w_px", "big_gap", "big_glow",
			"cart_pip_px", "cart_pip_gap_px", "cart_cols", "cart_w_px", "tow_px", "arc_w_px", "arc_glow", "arc_bulge",
			"arc_grow", "arc_fade", "arc_chevron_px", "relish_r_px", "relish_core_px", "relish_bob_px", "relish_w_px",
			"relish_glow"],
		"benefit": ["rate_effects", "plain_effects", "job_text", "now", "upgrade_now"],
		"card": ["w_px", "max_h_px", "gap_px", "edge_px", "row_gap_px"], "hover": ["w_px", "alpha", "grow_px"],
		"suggest": ["w_px", "dash_px", "alpha", "tag_prefix", "x_px", "tag_pad_px"],
		"ghost": ["alpha", "dash_px", "w_px", "ring_px", "ring_w_px", "number_px", "hold_px", "strike_px", "plus_px", "tag_pad_px"],
		"flash": ["w_px", "grow_px", "alpha", "text"],
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
	for r in v["hud"]["rates"]:
		if r["id"] == "gold":
			r["rate"] = 0.1
	v["town"]["bodies"] = 100.0
	v["town"]["bodies_cap"] = 200.0
	v["town"]["living"] = 5.0
	v["town"]["living_cap"] = 16.0
	v["town"]["morale"] = {"value": 0.8, "target": 0.8, "factors": []}
	return v


func _need_ids(v: Dictionary) -> Array:
	var ids: Array = []
	for n in BuildSort.needs(v, FORTS, vcfg):
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
	t.ok(not BuildSort.can_queue(_row("inn", false, "needs_tier", ["lot-05"]), vcfg), "build sort: a gated row cannot be queued")
	t.ok(not BuildSort.can_queue(_row("house", false, "no_lot", []), vcfg), "build sort: a row with no free lot cannot be queued")


const ALL_REASONS := ["unknown_building", "unknown_lot", "lot_locked", "lot_taken", "lot_too_small", "empty_lot",
	"under_construction", "needs_tier", "needs_blueprint", "needs_building", "no_lot", "no_gold", "no_bone", "no_relics",
	"max_level", "protected", "not_building", "queue_full", "cost_exceeds_cap", "unknown_index", "bad_order"]


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
			t.ok(r in ALL_REASONS, "view.reasons.%s is a documented reason id" % r)
	t.ok(BuildSort.reason_text("needs_tier", row, st, bv, vcfg) == "needs Village tier", "reason: needs_tier uses requires.tier")
	t.ok(BuildSort.reason_text("needs_blueprint", row, st, bv, vcfg) == "needs the Embalmer blueprint: dungeon loot", "reason: needs_blueprint names the blueprint")
	t.ok(BuildSort.reason_text("needs_building", row, st, bv, vcfg) == "needs a House first", "reason: needs_building names the building")
	t.ok(BuildSort.reason_text("no_lot", row, st, bv, vcfg) == "no free lot fits (size 2)", "reason: no_lot carries the size")
	t.ok(BuildSort.reason_text("no_gold", row, st, bv, vcfg) == "needs 60 gold: build a Market", "reason: no_gold names the amount and the fix building")
	t.ok(BuildSort.reason_text("no_relics", row, st, bv, vcfg) == "needs 2 relics: dungeon loot", "reason: no_relics points at dungeon loot")
	t.ok(BuildSort.reason_text("no_bone", {"cost": {"bone": 60.0}}, {"bone": 30.0, "count": {"bone_mill": 1}}, bv, vcfg) == "needs 30 bone: staff the Bone Mill",
		"reason: a built fix building is staffed, not built")
	t.ok(BuildSort.reason_text("no_relics", {"cost": {"relics": 1}}, {"relics": 0.0}, bv, vcfg) == "needs 1 relic: dungeon loot", "reason: one relic is singular")
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
	t.ok(TownStandins.queue_is_standin(day1["town"]), "queue: a town view without `queue` uses the stand-in")
	t.ok(not TownStandins.queue_is_standin({"queue": []}), "queue: a real `queue` key switches the stand-in off")
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
	t.ok(i["label"] == "House" and i["level"] == 1 and i["max_level"] == 3 and i["state_text"] == "working", "inspect: label, level of max, state")
	t.ok(i["upgrade"]["enabled"] and i["upgrade"]["cost"] == bcfg["house"]["level_costs"][0] and i["upgrade"]["level"] == 2,
		"inspect: upgrade cost is level_costs[level - 1]")
	t.ok(not i["cancel"]["visible"] and i["demolish_visible"], "inspect: an active house can be demolished, not cancelled")
	house["level"] = 3
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
	t.ok(BuildSort.reason_text("no_relics", {"cost": {"relics": 2}}, st, bv, vcfg) == "needs 2 relics: dungeon loot", "eta: relics never get an estimate")
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
	var bv: Dictionary = cfg["buildings_view"]
	var bc: Dictionary = cfg["buildings"]
	var pit := BuildSort.benefit("raising_pit", {}, bc, bv, vcfg)
	t.ok(pit["rates"] == ["+6.00/s mint", "−0.60/s bodies"] and not pit["now"], "benefit: the pit's effects as signed rates, no 'now' label (%s)" % str(pit["rates"]))
	t.ok(pit["plain"] == ["2 pit jobs"], "benefit: jobs are plain text (%s)" % str(pit["plain"]))
	var house := BuildSort.benefit("house", {}, bc, bv, vcfg)
	t.ok(house["rates"].is_empty() and house["plain"] == ["+8 housing"], "benefit: a cap is plain text, not a rate (%s)" % str(house["plain"]))
	var inn := BuildSort.benefit("inn", {}, bc, bv, vcfg)
	t.ok(inn["rates"] == ["+0.02/s migrants"] and inn["plain"] == ["+20 housing"], "benefit: the inn's migrants rate and housing cap")
	t.ok(BuildSort.benefit("guildhall", {}, bc, bv, vcfg)["plain"] == ["+1 stance slot"], "benefit: stance slots")
	t.ok(BuildSort.benefit("crypt", {}, bc, bv, vcfg)["plain"] == ["+1 big undead cap"], "benefit: the crypt's big-undead cap")
	t.ok(BuildSort.benefit("well", {}, bc, bv, vcfg)["plain"] == [bv["well"]["benefit"]], "benefit: no effects or jobs falls back to the view line")
	t.ok(BuildSort.benefit("market", {}, bc, bv, vcfg)["plain"] == ["2 stall jobs"], "benefit: a job building says its jobs")
	var proj := BuildSort.benefit("raising_pit", {"projected": {"mint": 3.0, "gold": -0.05}}, bc, bv, vcfg)
	t.ok(proj["now"] and proj["rates"] == ["+3.00/s mint now", "−0.05/s gold now"], "benefit: projected rates replace the stand-in and say 'now' (%s)" % str(proj["rates"]))
	t.ok(proj["plain"] == ["2 pit jobs"], "benefit: with projected, jobs and caps stay as plain text")
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
	t.ok(g.map(func(x): return x["shape"]) == ["hold", "struck", "plain"] and g.map(func(x): return x["status"]) == ["waiting_funds", "skipped_gate", "queued"],
		"ghosts: a waiting head holds, a gated entry is struck, the rest are plain (%s)" % str(g.map(func(x): return x["shape"])))
	t.ok((g[0]["text"].begins_with("needs ") or g[0]["text"].contains("isn't flowing")) and g[1]["text"].begins_with("needs Village tier"),
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
	for k in ["gold", "bone"]:
		t.ok(Palette.has(String(bar["ink"][k])), "caps: %s bar ink is a Palette key" % k)
		t.ok(TownModel.contrast(Palette.c(String(bar["ink"][k])), Palette.c("ground")) >= 3.0, "caps: the %s fill reads at 3:1 on ground" % k)
	t.ok(String(bar["ink"]["gold"]) == "living" and String(bar["ink"]["bone"]) == "dead", "caps: gold is living-orange, bone is dead matter")


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
