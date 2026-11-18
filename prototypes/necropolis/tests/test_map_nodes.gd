extends RefCounted
## Tests for scripts/map/node_logic.gd (pips, arcs, notches, the held and tithe countdowns, the
## backlog stack, the valve glyph, Relish's interpolation, wake and light, the demo overlay), the
## lit gutter in LaneStyle, node contrast, and source lints over the node scripts.

const PULSE := preload("res://autoload/pulse.gd")
const LINT := preload("res://tests/test_lint.gd")
const MAP_DIR := "res://scripts/map"
const NODE_FILES := ["map_nodes.gd", "map_node_layer.gd", "map_node_ctx.gd", "map_fort_ring.gd",
	"map_covington.gd", "map_vei.gd", "map_relish.gd", "node_logic.gd"]

var p: Node


func run() -> int:
	var t := TestUtil.new()
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	LineGlow.configure(TestUtil.load_json("res://configs/line_glow.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	p = PULSE.new()
	p.configure(TestUtil.load_json("res://configs/pulse.json"))
	_pips(t)
	_arcs(t)
	_countdowns(t)
	_vei(t)
	_valve(t)
	_relish(t)
	_wake(t)
	_labels(t)
	_relish_clock(t)
	_light(t)
	_misc(t)
	_demo(t)
	_hops(t)
	_contrast(t)
	_lit_gutter(t)
	_trim(t)
	_sources(t)
	p.free()
	return t.failures


func _fort(cap: float, living: float, undead: float, dead: float, tier := 2) -> Dictionary:
	return {"id": "f", "name": "F", "tier": tier, "cap": cap, "living": living, "undead": undead,
		"dead": dead, "pos": [100.0, 100.0]}


func _pips(t: TestUtil) -> void:
	t.suite("map_nodes-pips")
	t.ok(NodeLogic.pip_slots() == 10, "one pip per 10% of capacity: 10 slots")
	var c := NodeLogic.pip_counts(_fort(100.0, 47.0, 0.0, 0.0))
	t.ok(c["living"] == 5 and c["undead"] == 0 and c["dead"] == 0, "47% living shows 5 living pips")
	c = NodeLogic.pip_counts(_fort(200.0, 0.0, 41.0, 59.0))
	t.ok(c["undead"] == 2 and c["dead"] == 3, "20.5% undead -> 2, 29.5% dead -> 3 (rounded per matter)")
	c = NodeLogic.pip_counts(_fort(80.0, 0.0, 0.0, 0.0))
	t.ok(c["living"] == 0 and c["undead"] == 0 and c["dead"] == 0, "no mass, no pips")
	c = NodeLogic.pip_counts(_fort(80.0, 80.0, 0.0, 0.0))
	t.ok(c["living"] == 10, "a full fort shows 10 pips")
	c = NodeLogic.pip_counts(_fort(100.0, 45.0, 45.0, 10.0))
	t.ok(c["living"] + c["undead"] + c["dead"] <= 10, "rounding up never overfills the ring (%s)" % str(c))
	t.ok(c["living"] == 5 and c["undead"] == 5 and c["dead"] == 0, "the overfill comes off the last matter in arc order")
	c = NodeLogic.pip_counts(_fort(0.0, 5.0, 5.0, 5.0))
	t.ok(c["living"] == 0, "a zero cap draws no pips")
	var lay := NodeLogic.pip_layout(_fort(100.0, 20.0, 30.0, 10.0))
	t.ok(lay.size() == 10 and lay.slice(0, 2) == ["living", "living"] and lay.slice(2, 5) == ["undead", "undead", "undead"] \
		and lay[5] == "dead" and lay[6] == "", "pips group by matter in arc order, then empty slots")
	t.near(NodeLogic.pip_angle(0), -PI * 0.5 + PI / 10.0, 1e-6, "slot 0 sits just clockwise of 12 o'clock")
	t.ok(NodeLogic.pips_shown("mid") and NodeLogic.pips_shown("near") and not NodeLogic.pips_shown("far"), "pips at mid and near zoom only")


func _arcs(t: TestUtil) -> void:
	t.suite("map_nodes-arcs")
	var fr := NodeLogic.arc_fracs(_fort(100.0, 30.0, 20.0, 10.0))
	t.near(fr["living"], 0.3, 1e-6, "living is mass / cap")
	t.near(fr["living"] + fr["undead"] + fr["dead"], 0.6, 1e-6, "the arcs sum to the filled share")
	fr = NodeLogic.arc_fracs(_fort(100.0, 80.0, 60.0, 40.0))
	t.ok(fr["living"] + fr["undead"] + fr["dead"] <= 1.0 + 1e-6, "an over-cap fort scales its arcs to fit the circle")
	t.near(fr["living"] / fr["undead"], 80.0 / 60.0, 1e-5, "and keeps their proportions")
	fr = NodeLogic.arc_fracs(_fort(0.0, 5.0, 0.0, 0.0))
	t.ok(fr["living"] == 0.0, "zero cap: no arc")
	for tier in [1, 2, 3, 4]:
		t.ok(NodeLogic.notch_angles(tier).size() == tier, "tier %d draws %d notches" % [tier, tier])
	var a := NodeLogic.notch_angles(3)
	t.near(a[1], PI * 0.5, 1e-6, "notches centre on 6 o'clock")
	t.near(a[1] - a[0], a[2] - a[1], 1e-6, "and are evenly spaced")
	t.ok(NodeLogic.controller(_fort(100, 10, 20, 0)) == "undead", "more undead than living: undead")
	t.ok(NodeLogic.controller(_fort(100, 20, 10, 0)) == "living", "otherwise any living: living")
	t.ok(NodeLogic.controller(_fort(100, 0, 0, 30)) == "dead", "only dead: dead")
	t.ok(NodeLogic.controller(_fort(100, 0, 0, 0)) == "dead", "empty: dead")


func _countdowns(t: TestUtil) -> void:
	t.suite("map_nodes-countdowns")
	var flip := {"hold_s": 300.0, "tier_mult": 0.25}
	t.near(NodeLogic.grace_total(flip, 1), 375.0, 1e-6, "grace total = hold_s x (1 + tier_mult x tier): tier 1")
	t.near(NodeLogic.grace_total(flip, 4), 600.0, 1e-6, "tier 4")
	var f := _fort(100, 0, 50, 0, 2)
	t.near(NodeLogic.held_fraction(f, flip), 0.0, 1e-9, "not held: no countdown")
	f["held"] = true
	f["held_s_left"] = 9999.0  # the dead stub: ignored
	t.near(NodeLogic.held_fraction(f, flip), 0.0, 1e-9, "held_s_left is not read")
	f["grace_s_left"] = 225.0
	t.near(NodeLogic.held_fraction(f, flip), 225.0 / 450.0, 1e-6, "held countdown = grace_s_left / grace_total (tier 2: 450 s)")
	f["grace_s_left"] = 9999.0
	t.near(NodeLogic.held_fraction(f, flip), 1.0, 1e-9, "clamped to 1")
	t.near(NodeLogic.held_fraction(f, {}), 0.0, 1e-9, "no flip config, no divide by zero")
	var w := float(NodeLogic.ncfg()["tithe_warning_s"])
	t.near(NodeLogic.tithe_fraction(w * 0.5), 0.5, 1e-6, "tithe sweep = eta_s / tithe_warning_s")
	t.near(NodeLogic.tithe_fraction(-1.0), 0.0, 1e-9, "eta -1 (not targeted): no sweep")
	t.near(NodeLogic.tithe_fraction(w * 3.0), 1.0, 1e-9, "past the warning window: full")
	t.ok(NodeLogic.fmt_eta(88.0) == "1:28" and NodeLogic.fmt_eta(5.0) == "0:05" and NodeLogic.fmt_eta(600.0) == "10:00", "ETA as m:ss")
	t.ok(NodeLogic.fmt_eta(-3.0) == "0:00", "a negative ETA reads 0:00")
	t.ok(NodeLogic.tithe_mode({}) == "" and NodeLogic.tithe_mode({"tithe": {"targeted": true, "wave_active": false}}) == "warning" \
		and NodeLogic.tithe_mode({"tithe": {"targeted": true, "wave_active": true}}) == "wave", "tithe mode: none, warning, wave")
	var nx := {"tithe": {"targeted": false, "wave_active": false, "next": true, "next_s": 600.0}}
	t.ok(NodeLogic.tithe_mode(nx) == "next" and NodeLogic.tithe_next(nx) and not NodeLogic.tithe_badge(nx), "the next pick is mode next: the quiet telegraph, not the warning badge")
	t.ok(NodeLogic.tithe_mode({"tithe": {"targeted": true, "wave_active": false, "next": true}}) == "warning", "a warning wins over next")
	t.ok(not NodeLogic.tithe_next({"tithe": {"next": false}}) and not NodeLogic.tithe_next({}), "not next: no telegraph")
	t.ok(NodeLogic.first_dungeon_pulse({"first_dungeon": true, "first_clear": true}) and not NodeLogic.first_dungeon_pulse({"first_dungeon": true, "first_clear": false}) \
		and not NodeLogic.first_dungeon_pulse({"first_clear": true}), "the first-dungeon pulse needs both flags")
	# the one tag line under a name
	var n := NodeLogic.ncfg()
	var over := _fort(100.0, 0.0, 60.0, 0.0)
	var tag := NodeLogic.name_tag(over)
	t.ok(NodeLogic.fort_state(over, "") == NodeLogic.OVERRUN and tag.get("text", "") == n["label_overrun"] and tag.get("key", "") == "text_dim", "overrun, never taken: Vei's tag in text_dim")
	var first := _fort(100.0, 0.0, 60.0, 0.0)
	first["first_dungeon"] = true
	first["first_clear"] = true
	tag = NodeLogic.name_tag(first)
	t.ok(tag.get("text", "") == n["label_first_dungeon"] and tag.get("key", "") == "relish", "the first dungeon keeps its relish line, ahead of the overrun tag")
	var back := _fort(100.0, 40.0, 0.0, 0.0)
	back["flipped_count"] = 1
	tag = NodeLogic.name_tag(back)
	t.ok(tag.get("text", "") == n["label_retaken"] and tag.get("key", "") == "danger", "retaken (flipped before, not held): danger tag")
	t.ok(NodeLogic.name_tag(_fort(100.0, 40.0, 0.0, 0.0)).is_empty(), "a plain hers fort has no tag")
	var held := _fort(100.0, 0.0, 60.0, 0.0)
	held["held"] = true
	held["flipped_count"] = 1
	t.ok(NodeLogic.name_tag(held).is_empty(), "a held fort has no tag")
	# two unheld forts with identical matter, differing only in flipped_count: the retaken tag is the only difference
	var plain := _fort(100.0, 40.0, 0.0, 0.0)
	var retaken := _fort(100.0, 40.0, 0.0, 0.0)
	retaken["flipped_count"] = 1
	t.ok(NodeLogic.name_tag(plain).is_empty() and not NodeLogic.name_tag(retaken).is_empty(), "the pair differs by the tag alone")
	var sp := NodeLogic.fort_static_sig(plain, {})
	var sr := NodeLogic.fort_static_sig(retaken, {})
	var diff := []
	for i in sp.size():
		if sp[i] != sr[i]:
			diff.append(i)
	t.ok(sp != sr and diff == [7], "a tag's text is in the static signature: only the tag slot differs (%s)" % str(diff))


func _vei(t: TestUtil) -> void:
	t.suite("map_nodes-vei")
	var mass := float(NodeLogic.ncfg()["backlog_ring_mass"])
	var mx := int(NodeLogic.ncfg()["backlog_ring_max"])
	var b := NodeLogic.backlog_rings(0.0)
	t.ok(b["rings"] == 0 and b["overflow"] == 0, "no backlog, no rings")
	b = NodeLogic.backlog_rings(mass * 3.4)
	t.ok(b["rings"] == 3 and b["overflow"] == 0, "one ring per backlog_ring_mass (a partial ring is not drawn)")
	b = NodeLogic.backlog_rings(mass * (mx + 5.2))
	t.ok(b["rings"] == mx and b["overflow"] == 5, "past the cap: %d rings and +5" % mx)
	t.ok(NodeLogic.backlog_rings(-4.0)["rings"] == 0, "a negative backlog is none")
	t.ok(NodeLogic.fmt_odds(0.08) == "8%" and NodeLogic.fmt_odds(0.614) == "61%" and NodeLogic.fmt_odds(1.4) == "100%", "odds as an integer percent")
	t.ok(MapLogic.fmt_drain(-1.0) == "∞", "holding reads ∞, never a number")
	t.near(NodeLogic.vei_spin(100.0), 2.0 * NodeLogic.vei_spin(50.0), 1e-9, "the digestion rings turn in proportion to R_vei")
	t.ok(NodeLogic.vei_spin(0.0) == 0.0, "no capacity, no turning")
	t.ok(NodeLogic.vei_struct_radius(150.0) > 0.0 and NodeLogic.vei_struct_radius(150.0) < 150.0, "the structure sits inside the domain")


func _trim(t: TestUtil) -> void:
	t.suite("map_nodes-trim")
	var n := NodeLogic.ncfg()
	var pad := float(n["lane_trim_pad_px"])
	var fort := NodeLogic.outer_radius("fort", 2, 0.0)
	t.near(fort, MapLogic.fort_radius(2) + float(n["tithe_off_px"]) + float(n["tithe_halo_max_px"]) * 0.5 + pad, 1e-6, "a fort's outer radius reaches past its tithe ring")
	t.ok(fort < MapLogic.fort_radius(2) + float(MapLogic.cfg()["redirect_ring_pad_px"]), "and stays inside the REDIRECT ring")
	t.ok(NodeLogic.outer_radius("fort", 4, 0.0) > NodeLogic.outer_radius("fort", 1, 0.0), "bigger tiers trim more")
	t.near(NodeLogic.outer_radius("covington", 0, 0.0), float(n["cov_half_px"]) + pad, 1e-6, "Covington: its glyph plus the pad")
	var ro := NodeLogic.vei_struct_radius(150.0)
	var beat := ro + float(n["vei_beat_reach_px"]) + float(n["source_halo_max_px"]) * 0.5
	t.near(NodeLogic.outer_radius("vei", 0, 150.0), beat + pad, 1e-6, "Vei with no backlog: her beat ring at full reach plus the pad")
	var last := 0.0
	var growing := true
	for rings in range(1, int(n["backlog_ring_max"]) + 1):
		var r := NodeLogic.outer_radius("vei", 0, 150.0, float(rings) * float(n["backlog_ring_mass"]))
		var stack_edge := ro + float(n["backlog_first_gap_px"]) + (rings - 1) * float(n["backlog_step_px"])
		growing = growing and r >= last and r > stack_edge + pad
		last = r
	t.ok(growing, "Vei's trim clears the outer edge of every ring shown, never shrinking as rings are added")
	t.ok(NodeLogic.outer_radius("vei", 0, 150.0, 99999.0) == NodeLogic.outer_radius("vei", 0, 150.0, float(n["backlog_ring_max"]) * float(n["backlog_ring_mass"])), "past the cap the radius stops growing (the +N is text, not a ring)")
	t.ok(NodeLogic.outer_radius("vei", 0, 150.0, float(n["backlog_ring_max"]) * float(n["backlog_ring_mass"])) >= ro + 59.0, "with the full stack it clears ~59 px past the structure")
	t.ok(NodeLogic.outer_radius("village", 0, 0.0) == 0.0, "other nodes: no trim")
	var tr := NodeLogic.trim_lengths(40.0, 60.0, 500.0)
	t.ok(tr["start"] == 40.0 and tr["end"] == 60.0, "trim lengths are the end radii on a long lane")
	tr = NodeLogic.trim_lengths(40.0, 60.0, 100.0)
	t.near(tr["start"] + tr["end"], 50.0, 1e-6, "a short lane keeps at least half its length")
	t.near(tr["start"] / tr["end"], 40.0 / 60.0, 1e-6, "scaled together")
	tr = NodeLogic.trim_lengths(-5.0, 0.0, 10.0)
	t.ok(tr["start"] == 0.0 and tr["end"] == 0.0, "no negative trim")
	var sh := FileAccess.get_file_as_string("res://shaders/map_lane.gdshader")
	t.ok(sh.contains("uniform float trim_start") and sh.contains("uniform float trim_end") and not sh.contains("discard;"), "the lane shader trims by coverage, never by discard")
	t.ok(sh.contains("trim_start + (lane_len - trim_start - trim_end)"), "chevrons sit inside the trimmed range")
	var carts := FileAccess.get_file_as_string("res://scripts/map/map_carts.gd")
	t.ok(carts.contains("tr[\"lo\"]") and carts.contains("tr[\"hi\"]"), "carts stay inside the trimmed range")
	t.ok(NodeLogic.drain_line(0.0, 0.0) == str(n["queue_empty_text"]) and NodeLogic.drain_line(-3.0, -1.0) == str(n["queue_empty_text"]), "no backlog: queue empty, not a drain time")
	t.ok(NodeLogic.drain_line(500.0, -1.0) == "drain ∞" and NodeLogic.drain_line(500.0, 520.0) == "drain 8m 40s", "with a backlog: holding is ∞, else the time")


func _relish_clock(t: TestUtil) -> void:
	t.suite("map_nodes-relish-clock")
	var rel := {"pos": [100.0, 200.0], "state": "travelling", "target": "ashgate", "heading": 0.3}
	var same := {"pos": [100.0, 200.0], "state": "travelling", "target": "ashgate", "heading": 0.3, "rev_noise": 7}
	t.ok(NodeLogic.relish_sig(rel) == NodeLogic.relish_sig(same), "a refresh that leaves pos, state and target alone keeps the same key")
	t.ok(NodeLogic.relish_sig(rel) != NodeLogic.relish_sig({"pos": [101.0, 200.0], "state": "travelling", "target": "ashgate"}), "a new position restarts the clock")
	t.ok(NodeLogic.relish_sig(rel) != NodeLogic.relish_sig({"pos": [100.0, 200.0], "state": "at_fort", "target": "ashgate"}), "a new state restarts it")
	t.ok(NodeLogic.relish_sig(rel) != NodeLogic.relish_sig({"pos": [100.0, 200.0], "state": "travelling", "target": "greywall"}), "a new target restarts it")
	t.ok(NodeLogic.relish_sig({}) == [], "no Relish entry: an empty key")
	var j := float(NodeLogic.ncfg()["wake_jump_px"])
	t.ok(not NodeLogic.wake_jumped(Vector2.ZERO, Vector2(j * 0.5, 0)), "a normal step does not clear the wake")
	t.ok(not NodeLogic.wake_jumped(Vector2.ZERO, Vector2(j, 0)), "exactly wake_jump_px is not a jump")
	t.ok(NodeLogic.wake_jumped(Vector2.ZERO, Vector2(j + 1.0, 0)), "past wake_jump_px is")
	t.ok(NodeLogic.wake_jumped(Vector2(1780, 1270), Vector2(1024, 130)), "a teleport across the map is")
	var rel_src := FileAccess.get_file_as_string("%s/map_relish.gd" % MAP_DIR)
	t.ok(rel_src.contains("join"), "the wake only joins her token while she travels")
	t.ok(j > float(NodeLogic.ncfg()["relish_gap_px"]) + MapLogic.fort_radius(4), "the jump distance clears a standing offset above the biggest fort")


## Real positions: Covington, the forts' centroid, Vei (configs/world.json).
func _labels(t: TestUtil) -> void:
	t.suite("map_nodes-labels")
	var world := TestUtil.load_json("res://configs/world.json")
	var cov := Vector2(float(world["covington"]["pos"][0]), float(world["covington"]["pos"][1]))
	var vei := Vector2(float(world["vei"]["pos"][0]), float(world["vei"]["pos"][1]))
	var cen := NodeLogic.fort_centroid(world["forts"])
	var size := float(MapLogic.cfg()["font_label"])
	var text_w := {"war": 30.0, "flood": 44.0, "work": 38.0, "covington": 88.0}
	var cases := [NodeLogic.valve_dirs(cov, cen, vei)]
	for a in [0.0, 25.0, 60.0, 100.0, 170.0, 250.0, 330.0]:
		var w := Vector2.from_angle(deg_to_rad(a))
		cases.append(NodeLogic.valve_dirs(Vector2.ZERO, w * 500.0, Vector2.from_angle(deg_to_rad(a + 15.0)) * 500.0))
		cases.append(NodeLogic.valve_dirs(Vector2.ZERO, w * 500.0, Vector2.from_angle(deg_to_rad(a + 120.0)) * 500.0))
	var shares := [{"work": 0.4, "war": 0.45, "flood": 0.15}, {"work": 1.0, "war": 0.0, "flood": 0.0}, {"work": 0.0, "war": 0.5, "flood": 0.5},
		{"work": 0.2, "war": 0.2, "flood": 0.6}, {"work": 0.0, "war": 0.0, "flood": 0.0}, {"work": 0.34, "war": 0.33, "flood": 0.33}]
	var checked := 0
	var bad := 0
	for dirs in cases:
		for sh in shares:
			var widths := NodeLogic.valve_widths(sh)
			for z in [0.3, 0.55, 0.61, 0.8, 1.0, 1.6, 2.0, 3.0]:
				for on in [true, false]:
					var lay := NodeLogic.valve_label_layout(dirs, widths, on, z, text_w, size)
					var keys := lay.keys()
					checked += 1
					if not lay.has("covington") or (on and (widths["war"] > 0.0) != lay.has("war")):
						bad += 1
					for i in keys.size():
						for j in range(i + 1, keys.size()):
							if (lay[keys[i]]["rect"] as Rect2).intersects(lay[keys[j]]["rect"]):
								bad += 1
								printerr("    overlap %s/%s dirs=%s share=%s zoom=%s" % [keys[i], keys[j], str(dirs), str(sh), z])
	t.ok(checked > 500 and bad == 0, "no two valve labels overlap across %d layouts (shares x directions x zoom x label modes), %d bad" % [checked, bad])
	# the real fixture, at the fit zoom and the tier edges: no label meets the glyph, a drawn stem or the hook
	var dirs0: Dictionary = cases[0]
	var widths0 := NodeLogic.valve_widths({"work": 0.4, "war": 0.45, "flood": 0.15})
	var glue := 0
	for z: float in [0.55, 0.61, 1.0, 1.6, 3.0]:
		var lay := NodeLogic.valve_label_layout(dirs0, widths0, true, z, text_w, size)
		var n := NodeLogic.ncfg()
		var h := float(n["cov_half_px"]) * z
		var glyph := Rect2(-h, -h, h * 2.0, h * 2.0)
		var inner := float(n["valve_in_px"]) * z
		var tip := inner + float(n["valve_len_px"]) * z
		var hr := float(n["valve_hook_r_px"]) * z
		var hook := Rect2(dirs0["work"] * (inner + hr) - Vector2(hr, hr), Vector2(hr, hr) * 2.0)
		for k in lay:
			var rect: Rect2 = lay[k]["rect"]
			if rect.intersects(glyph) or rect.intersects(hook):
				glue += 1
				printerr("    glue %s zoom=%s rect=%s glyph=%s hook=%s" % [k, z, rect, glyph, hook])
			for st in ["war", "flood"]:
				var stem := Rect2(dirs0[st] * inner, Vector2.ZERO).expand(dirs0[st] * tip)
				if rect.intersects(stem):
					glue += 1
	t.ok(glue == 0, "on the real layout no label touches the glyph, a stem or the WORK hook (%d)" % glue)
	var lay1 := NodeLogic.valve_label_layout(dirs0, widths0, true, 0.61, text_w, size)
	t.ok(lay1["covington"]["off"].y > 0.0 and lay1["covington"]["align"] == 0, "COVINGTON sits centred below the glyph")
	var stem_dir: Vector2 = dirs0["war"]
	t.ok((lay1["war"]["off"] as Vector2).normalized().dot(stem_dir) > 0.999, "WAR's label is beyond its stem's end along the stem")
	t.ok((lay1["war"]["off"] as Vector2).length() >= (float(NodeLogic.ncfg()["valve_in_px"]) + float(NodeLogic.ncfg()["valve_len_px"])) * 0.61, "and at least at the stem's tip")


func _valve(t: TestUtil) -> void:
	t.suite("map_nodes-valve")
	var mw := float(NodeLogic.ncfg()["valve_glyph_max_w"])
	var w := NodeLogic.valve_widths({"work": 0.4, "war": 0.45, "flood": 0.15})
	t.near(w["work"], mw * 0.4, 1e-6, "WORK width = max x share")
	t.near(w["war"], mw * 0.45, 1e-6, "WAR width")
	t.near(w["flood"], mw * 0.15, 1e-6, "FLOOD width")
	w = NodeLogic.valve_widths({"work": 0.0, "war": 1.0, "flood": 0.0})
	t.ok(w["work"] == 0.0 and w["flood"] == 0.0 and absf(w["war"] - mw) < 1e-6, "a share of 0 draws nothing; a share of 1 is the full width")
	t.ok(NodeLogic.valve_widths({})["war"] == 0.0, "no valve, no stems")
	var cov := Vector2(1780, 1270)
	var cen := Vector2(1150, 940)
	var vei := Vector2(1024, 130)
	var d := NodeLogic.valve_dirs(cov, cen, vei)
	t.ok(d["war"].is_normalized() and d["flood"].is_normalized() and d["work"].is_normalized(), "directions are unit vectors")
	t.ok(absf(rad_to_deg(d["war"].angle_to(d["flood"]))) >= float(NodeLogic.ncfg()["valve_min_sep_deg"]) - 0.01, "WAR and FLOOD are at least valve_min_sep_deg apart")
	t.ok(d["work"].dot(d["war"]) < 0.0 and d["work"].dot(d["flood"]) < 0.0, "WORK points away from both")
	var far := NodeLogic.valve_dirs(cov, Vector2(1780, 100), Vector2(300, 1270))
	t.ok(far["war"].dot((Vector2(1780, 100) - cov).normalized()) > 0.99, "well-separated targets are aimed at exactly")
	t.ok(NodeLogic.fort_centroid([{"pos": [0.0, 0.0]}, {"pos": [10.0, 20.0]}]) == Vector2(5, 10), "centroid of the forts")
	t.ok(NodeLogic.fort_centroid([]) == Vector2.ZERO, "no forts: the origin")


func _relish(t: TestUtil) -> void:
	t.suite("map_nodes-relish")
	var pos := Vector2(100, 100)
	var tgt := Vector2(400, 100)
	var q := NodeLogic.relish_drawn_pos("travelling", pos, 0.0, 220.0, 0.25, tgt, true)
	t.ok(q.distance_to(Vector2(155, 100)) < 1e-3, "advances speed x dt along heading (55 px in 0.25 s)")
	q = NodeLogic.relish_drawn_pos("travelling", pos, 0.0, 220.0, 5.0, tgt, true)
	t.ok(q.x <= 400.0 + 1e-3 and q.x > 100.0, "never passes the target (x = %.1f)" % q.x)
	q = NodeLogic.relish_drawn_pos("travelling", pos, 0.0, 220.0, 0.55, Vector2(120, 100), true)
	t.ok(q.distance_to(Vector2(120, 100)) < 1e-3, "stops at a near target")
	t.ok(NodeLogic.relish_drawn_pos("at_fort", pos, 0.0, 220.0, 0.25, tgt, true) == pos, "snaps to the model's position when not travelling")
	t.ok(NodeLogic.relish_drawn_pos("travelling", pos, 0.0, 0.0, 0.25, tgt, true) == pos, "speed 0: no advance")
	t.ok(NodeLogic.relish_drawn_pos("travelling", pos, 0.0, 220.0, 0.0, tgt, true) == pos, "no time since the refresh: no advance")
	q = NodeLogic.relish_drawn_pos("travelling", pos, PI * 0.5, 100.0, 0.5, tgt, false)
	t.ok(q.distance_to(Vector2(100, 150)) < 1e-3, "heading is radians (pi/2 is +y); no target: unclamped")
	var cap := float(NodeLogic.ncfg()["relish_extrap_max_s"])
	t.near(NodeLogic.extrap_dt(60.0, 1.0), cap, 1e-9, "a stale refresh extrapolates at most relish_extrap_max_s of real time")
	t.near(NodeLogic.extrap_dt(0.1, 10.0), 1.0, 1e-9, "x10: 0.1 s real is 1 s of sim, not clipped to the cap")
	t.near(NodeLogic.extrap_dt(0.1, 0.0), 0.0, 1e-9, "paused: no advance")
	t.near(NodeLogic.extrap_dt(-1.0, 1.0), 0.0, 1e-9, "a clock step back is no advance")


func _wake(t: TestUtil) -> void:
	t.suite("map_nodes-wake")
	var wake_s := float(NodeLogic.ncfg()["wake_s"])
	var step := float(NodeLogic.ncfg()["wake_min_step_px"])
	var buf: Array = []
	NodeLogic.wake_add(buf, Vector2.ZERO, 0.0)
	NodeLogic.wake_add(buf, Vector2(step * 0.3, 0), 0.1)
	t.ok(buf.size() == 1, "a point closer than wake_min_step_px is not added")
	NodeLogic.wake_add(buf, Vector2(step * 2.0, 0), 0.2)
	t.ok(buf.size() == 2 and absf(buf[1].z - 0.2) < 1e-6 and absf(buf[1].x - step * 2.0) < 1e-6, "a point farther is added with its time")
	NodeLogic.wake_prune(buf, wake_s + 0.1)
	t.ok(buf.size() == 1 and absf(buf[0].z - 0.2) < 1e-6, "points older than wake_s drop")
	NodeLogic.wake_prune(buf, wake_s + 1.0)
	t.ok(buf.is_empty(), "the wake decays away once she stops")
	var mx := int(NodeLogic.ncfg()["wake_max_points"])
	for i in mx + 25:
		NodeLogic.wake_add(buf, Vector2(i * step * 2.0, 0), float(i) * 0.001)
	t.ok(buf.size() == mx, "the buffer is capped at wake_max_points (%d)" % buf.size())
	t.near(buf[0].x, 25.0 * step * 2.0, 1e-3, "the oldest points are the ones dropped")
	var al := NodeLogic.wake_alphas(buf, buf.back().z, false)
	t.ok(al.size() == buf.size() and al[al.size() - 1] > 0.99 and al[0] < al[al.size() - 1], "live: alpha is 1 at her, less toward the tail")
	var old := [Vector3(0, 0, 0.0), Vector3(1, 0, wake_s), Vector3(2, 0, wake_s * 0.5)]
	var oa := NodeLogic.wake_alphas(old, wake_s, false)
	t.near(oa[0], 0.0, 1e-6, "a point wake_s old has faded to 0")
	t.near(oa[2], 0.5, 1e-6, "and half-aged is half")
	var fz := NodeLogic.wake_alphas(old, 12345.0, true)
	t.ok(fz[0] == 0.0 and fz[2] == 1.0 and fz[1] == 0.5, "frozen (reduced motion): fades along its length, independent of the clock")
	var demo := NodeLogic.demo_wake(Vector2(500, 500), 0.0, 10, 100.0)
	t.ok(demo.size() == 10 and Vector2(demo[9].x, demo[9].y) == Vector2(500, 500) and demo[0].x < demo[9].x, "demo wake trails behind her, newest at her")
	t.ok(demo[0].z < demo[9].z and demo[9].z == 100.0, "and ages toward the tail")


func _light(t: TestUtil) -> void:
	t.suite("map_nodes-light")
	var r := float(NodeLogic.ncfg()["relish_light_radius_px"])
	var forts := [{"id": "a", "pos": [0.0, 0.0]}, {"id": "b", "pos": [r * 0.9, 0.0]}, {"id": "c", "pos": [r * 1.1, 0.0]}]
	var ids := NodeLogic.lit_fort_ids(forts, Vector2.ZERO, r)
	t.ok(ids == ["a", "b"], "the forts within relish_light_radius_px of her are lit")
	t.ok(NodeLogic.lit_fort_ids(forts, Vector2(5000, 5000), r).is_empty(), "far from every fort: none")


func _misc(t: TestUtil) -> void:
	t.suite("map_nodes-misc")
	t.ok(NodeLogic.fort_label_shown("mid", 1) and NodeLogic.fort_label_shown("near", 1), "fort names show at mid and near zoom")
	t.ok(NodeLogic.fort_label_shown("far", 4) and not NodeLogic.fort_label_shown("far", 1), "at far zoom only the big tiers keep a name")
	t.ok(NodeLogic.village_edge_key("player") == "undead" and NodeLogic.village_edge_key("vei") == "living" and NodeLogic.village_edge_key("none") == "town", "village edge by owner")


func _demo(t: TestUtil) -> void:
	t.suite("map_nodes-demo")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	var m := MapModel.new(s)
	m.nodes_demo = true
	m.flip_cfg = TestUtil.configs()["realm"]["flip"]
	m.refresh(true)
	var d: Dictionary = MapLogic.cfg()["demo_nodes"]
	var held: Dictionary = m.fort(d["held"]["fort"])
	t.ok(held["held"] and absf(NodeLogic.held_fraction(held, m.flip_cfg) - float(d["held"]["frac"])) < 1e-6, "a held fort with the countdown at the demo fraction")
	var th: Dictionary = m.fort(d["tithe"]["fort"])
	t.ok(NodeLogic.tithe_mode(th) == "warning" and NodeLogic.fmt_eta(th["tithe"]["eta_s"]) == "1:28", "a fort under a tithe warning at 1:28")
	t.ok(m.vei["tithe"]["target"] == d["tithe"]["fort"] and m.vei["tithe"]["warning"], "model.vei.tithe agrees")
	t.ok(NodeLogic.tithe_mode(m.fort(d["wave"]["fort"])) == "wave", "a fort with the wave active")
	t.ok(NodeLogic.first_dungeon_pulse(m.fort(d["first_dungeon"])), "the first-dungeon pulse on Old Sluice")
	t.ok(float(m.fort(d["simulacrum"]["fort"])["simulacrum_charges"]) > 0.0, "a simulacrum")
	t.ok(m.relish["state"] == "travelling" and m.relish["target"] == d["relish"]["target"] and float(m.relish["speed"]) == 0.0, "Relish travelling toward the demo target")
	t.ok(d["relish"].has("eta_s") and is_equal_approx(float(m.relish["eta_s"]), float(d["relish"]["eta_s"])) and float(m.relish["eta_s"]) > 1.0, "the demo's Relish carries a real ETA (%s s)" % m.relish["eta_s"])
	var b := NodeLogic.backlog_rings(float(m.vei["backlog"]))
	t.ok(b["rings"] == int(NodeLogic.ncfg()["backlog_ring_max"]) and b["overflow"] > 0, "the backlog fills the ring stack and overflows")
	t.ok(m.readout()["sign"] == 1 and m.readout()["drain_s"] > 0.0, "an up arrow and a finite drain time")
	var plain := MapModel.new(s)
	plain.refresh(true)
	t.ok(not plain.fort(d["held"]["fort"])["held"] and plain.vei["backlog"] != m.vei["backlog"], "without the flag the views are untouched")


func _hops(t: TestUtil) -> void:
	t.suite("map_nodes-hops")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("day1")
	var m := MapModel.new(s)
	m.refresh(true)
	t.ok(m.hops_of("covington") == 0.0 and m.hops_of("vei") == 2.0, "Covington is hop 0, Vei hop 2")
	t.ok(m.forts.all(func(f): return m.hops_of(f["id"]) == 1.0), "every fort is hop 1")
	var w0: float = p.wave(m.hops_of("covington"))
	t.ok(p.phase(0.0) != p.phase(1.0) and p.phase(1.0) != p.phase(2.0), "the tempo is offset by hop distance")
	t.ok(w0 >= 0.0, "wave reads")
	p.reduced_motion = true
	t.ok(p.wave(1.0) == p.reduced_wave and p.phase(2.0) == p.reduced_phase, "reduced motion freezes the wave and the phase")
	p.reduced_motion = false


func _contrast(t: TestUtil) -> void:
	t.suite("map_nodes-contrast")
	var n := NodeLogic.ncfg()
	var ground := Palette.c("ground")
	var hair := Palette.c(str(n["hairline_key"]), float(n["hairline_alpha"]))
	t.ok(MapLogic.contrast_ratio(hair, ground) >= 3.0, "the capacity hairline reads 3:1 over ground (%.2f)" % MapLogic.contrast_ratio(hair, ground))
	t.ok(float(n["hairline_screen_px"]) >= 1.0, "and is at least 1 px on screen")
	for k in ["dead", "dead_lit"]:
		var cr := MapLogic.contrast_ratio(Palette.c(k), ground)
		t.ok(cr >= 3.0, "%s pips and arcs read 3:1 over ground (%.2f)" % [k, cr])
	for k in ["undead", "living", "relish", "vei"]:
		t.ok(MapLogic.contrast_ratio(Palette.c(k), ground) >= 3.0, "%s pips read 3:1" % k)
	var lab := Palette.c("text_dim", float(MapLogic.cfg()["node_label_dim_alpha"]))
	t.ok(MapLogic.contrast_ratio(lab, ground) >= 4.5, "fort labels read 4.5:1 (%.2f)" % MapLogic.contrast_ratio(lab, ground))
	t.ok(NodeLogic.fort_label_key("far") == "text" and NodeLogic.fort_label_key("mid") == "text" and NodeLogic.fort_label_key("near") == "text_dim", "fort names are full text in the overview tiers (far, mid), dim at near")
	for tier in ["far", "mid", "near"]:
		var tl := Palette.c(NodeLogic.fort_label_key(tier), float(MapLogic.cfg()["node_label_dim_alpha"]))
		t.ok(MapLogic.contrast_ratio(tl, ground) >= 4.5, "fort names read 4.5:1 at the %s tier (%.2f)" % [tier, MapLogic.contrast_ratio(tl, ground)])
	t.ok(float(MapLogic.cfg()["node_label_dim_alpha"]) == 1.0 and MapLogic.contrast_ratio(Palette.c("text"), ground) >= MapLogic.contrast_ratio(Palette.c("text_dim"), ground), "the far name is at least as bright as the dim one")
	for k in ["undead", "living", "relish", "danger", "text"]:
		t.ok(MapLogic.contrast_ratio(Palette.c(k), ground) >= 4.5, "%s text reads 4.5:1" % k)
	t.ok(int(MapLogic.cfg()["font_label"]) >= 12 and int(n["font_tithe"]) >= 12 and int(n["font_odds_sub"]) >= 12 and int(n["font_odds"]) >= 12, "no text under 12 px")
	t.ok(MapLogic.cfg()["redirect_ring_pad_px"] > float(n["tithe_off_px"]) + float(n["tithe_halo_max_px"]) * 0.5, "the tithe ring sits inside the REDIRECT ring")


func _lit_gutter(t: TestUtil) -> void:
	t.suite("map_nodes-lit-gutter")
	var ch: Dictionary = p.channels(0.4, Palette.hue("dead"))
	var host_half := MapLogic.lane_half_width(0.3)
	var plain := LaneStyle.gutter_layers(ch, host_half)
	var lit := LaneStyle.gutter_layers(ch, host_half, 1.0, true)
	t.ok(plain == LaneStyle.gutter_layers(ch, host_half, 1.0, false), "lit defaults to false")
	t.ok(lit.size() == plain.size(), "same strokes lit or not")
	var g: Dictionary = MapLogic.cfg()["gutter"]
	var want_lip := Palette.c("dead_lit").lightened(float(g["lip_lighten"]))
	var want_rim := Palette.c("dead_lit").darkened(float(g["rim_darken"]))
	t.ok(Color(lit[2]["color"], 1.0).is_equal_approx(want_lip), "lit: the lip is dead_lit lightened")
	t.ok(Color(lit[3]["color"], 1.0).is_equal_approx(want_rim), "lit: the rim is dead_lit darkened")
	t.ok(Color(plain[2]["color"], 1.0).is_equal_approx(Palette.c("dead").lightened(float(g["lip_lighten"]))), "unlit: the lip is still dead-derived")
	t.near(lit[2]["color"].a, plain[2]["color"].a, 1e-6, "alpha rules are unchanged")
	t.ok(Color(lit[0]["color"], 1.0) == Palette.c("void") and Color(lit[1]["color"], 1.0) == Palette.c("void"), "the spill and the cut stay black")
	t.ok(lit[2]["width"] == plain[2]["width"] and lit[3]["width"] == plain[3]["width"] and lit[1]["width"] == plain[1]["width"], "widths are unchanged")
	var lum_cap := Palette.c("dead_lit").lightened(float(g["lip_lighten"])).get_luminance()
	var ok := true
	for l in lit:
		ok = ok and Color(l["color"], 1.0).get_luminance() <= lum_cap + 1e-4
	t.ok(ok, "no lit gutter stroke is brighter than the matte lip: still never glows")
	t.ok(LaneStyle.gutter_chevron_color(ch, true).is_equal_approx(Color(want_lip, float(ch["alpha"]) * float(g["chevron_alpha_mult"]))), "lit chevrons take the lit lip colour")
	t.ok(LaneStyle.gutter_chevron_color(ch) == LaneStyle.gutter_chevron_color(ch, false), "chevrons default unlit")


func _sources(t: TestUtil) -> void:
	t.suite("map_nodes-sources")
	var banned := RegEx.new()
	banned.compile("\\bsin\\(|Time\\.get_ticks|1\\.714|\\b1714\\b|draw_circle\\([^)]*Color\\(")
	var lines := 0
	for f in NODE_FILES:
		var n := 0
		for line in FileAccess.get_file_as_string("%s/%s" % [MAP_DIR, f]).split("\n"):
			n += 1
			lines += 1
			var code: String = LINT.strip_comment(line)
			if banned.search(code) != null and not line.contains("# lint-ok: bench"):
				t.ok(false, "%s:%d animates off the wrong clock or carries a literal tempo: %s" % [f, n, line.strip_edges()])
	t.ok(lines > 400, "scanned %d lines of node scripts" % lines)
	if t.failures == 0:
		t.ok(true, "no sin(), Time.get_ticks (outside bench timing) or literal tempo in the node scripts")
	t.ok(banned.search("x = sin(t * 3.0)") != null and banned.search("Time.get_ticks_msec()") != null and banned.search("var T = 1.714") != null, "detector flags them")
	var layers := ""
	for f in ["map_fort_ring.gd", "map_covington.gd", "map_vei.gd", "map_relish.gd"]:
		layers += FileAccess.get_file_as_string("%s/%s" % [MAP_DIR, f])
	t.ok(layers.contains("Pulse.wave(") and layers.contains("Pulse.phase(") and layers.contains("hops_of("), "the layers take their tempo from Pulse.wave and Pulse.phase at model.hops_of")
	t.ok(not layers.contains("Pulse.wave(1") and not layers.contains("Pulse.wave(0") and not layers.contains("Pulse.wave(2"), "no literal hop counts")
	t.ok(layers.contains("LineGlow.") or layers.contains("glow_arc("), "glows go through LineGlow")
	var vei_src := FileAccess.get_file_as_string("%s/map_vei.gd" % MAP_DIR)
	var static_body := vei_src.substr(vei_src.find("func _draw_static"), vei_src.find("func sync_rings") - vei_src.find("func _draw_static"))
	t.ok(not static_body.contains("sync_rings") and vei_src.contains("func reset_rings"), "Vei's digestion rings never sync from _draw, and F6 resets them")
	var nodes := FileAccess.get_file_as_string("%s/map_nodes.gd" % MAP_DIR)
	t.ok(nodes.contains("_vei_s.sync_rings()") and nodes.contains("_vei_s.reset_rings()"), "MapNodes syncs the rings on refresh and camera change, and resets them on a config reload")
	t.ok(nodes.contains("Pulse.reduced_motion") and nodes.contains("Pulse.now_ms()"), "Vei's turning reads Pulse's clock and the reduced-motion flag")
	t.ok(nodes.contains("set_lit_forts"), "the nodes layer lights the gutters")
	t.ok(FileAccess.get_file_as_string("%s/map_routes.gd" % MAP_DIR).contains("func set_lit_forts("), "MapRoutes has set_lit_forts")
