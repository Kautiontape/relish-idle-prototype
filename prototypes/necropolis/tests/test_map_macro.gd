extends RefCounted
## Tests for the macro-readability pass (task 12): the fort state glyph rule (NodeLogic.fort_state
## and the tithe badge), lane focus and the glow cap (LaneStyle.focus_ids / focus / quiet_ids and
## the quiet stroke stack), the lane hue floor and the rate_log_max retune, Relish's minimum
## screen size, the label plates' contrast, the --lanes-report line and the debug speed row gate.

const PULSE := preload("res://autoload/pulse.gd")
const HUD_FILE := "res://scripts/map/map_hud.gd"

var p: Node


## A GameState stand-in with only the flag the HUD reads.
class StubState:
	var debug_enabled := false


func run() -> int:
	var t := TestUtil.new()
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	LineGlow.configure(TestUtil.load_json("res://configs/line_glow.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	p = PULSE.new()
	p.configure(TestUtil.load_json("res://configs/pulse.json"))
	_states(t)
	_states_fixtures(t)
	_glyph_size(t)
	_focus(t)
	_glow_cap(t)
	_quiet(t)
	_hue_floor(t)
	_retune(t)
	_relish(t)
	_plates(t)
	_report(t)
	_speed_row(t)
	p.free()
	return t.failures


func _fort(living: float, undead: float, dead: float, cap := 160.0, extra := {}) -> Dictionary:
	var f := {"id": "f", "tier": 2, "cap": cap, "living": living, "undead": undead, "dead": dead, "held": false,
		"tithe": {"targeted": false, "eta_s": -1.0, "wave_active": false}}
	f.merge(extra, true)
	return f


func _row(kind: String, from: String, to: String, rate := 1.0) -> Dictionary:
	return {"id": "%s:%s:%s" % [kind, from, to], "from": from, "to": to, "kind": kind,
		"rate": rate, "bias": 1.0, "why": ""}


# --- 12a: one state per fort ------------------------------------------------------

func _states(t: TestUtil) -> void:
	t.suite("map_macro-states")
	var n := NodeLogic.ncfg()
	t.ok(NodeLogic.fort_state(_fort(140.0, 0.0, 0.0), "") == NodeLogic.HERS, "living only: hers")
	t.ok(NodeLogic.fort_state(_fort(140.0, 3.0, 10.0), "") == NodeLogic.HERS, "a few undead under the floor and the ratio: still hers")
	var ratio := float(n["contested_frac"])
	t.ok(NodeLogic.fort_state(_fort(40.0, 40.0 * ratio + 1.0, 0.0), "") == NodeLogic.CONTESTED, "undead >= contested_frac of the living: contested")
	var floor_m := float(n["contested_floor_frac"]) * 160.0
	t.ok(NodeLogic.fort_state(_fort(150.0, floor_m + 0.5, 0.0), "") == NodeLogic.CONTESTED, "both sides above the floor: contested")
	t.ok(NodeLogic.fort_state(_fort(0.0, 30.0, 40.0), "") == NodeLogic.CONTESTED, "undead there and no living, not yet held: contested")
	t.ok(NodeLogic.fort_state(_fort(1.9, 0.9, 74.2, 80.0), "") == NodeLogic.EMPTIED, "neither side present (under state_present_frac of cap), dead remain: emptied")
	t.ok(NodeLogic.fort_state(_fort(0.0, 0.0, 0.0), "") == NodeLogic.EMPTIED, "nothing at all: emptied")
	t.ok(NodeLogic.fort_state(_fort(0.0, 0.0, 0.0, 0.0), "") == NodeLogic.EMPTIED, "no capacity: emptied, no division by zero")
	# held beats everything, by margin
	var held := {"held": true}
	for m in [IdleLogic.SAFE, IdleLogic.THIN, IdleLogic.WILL_FALL]:
		t.ok(NodeLogic.fort_state(_fort(10.0, 60.0, 0.0, 160.0, held), m) == m, "held at margin %s: %s" % [m, m])
	t.ok(NodeLogic.fort_state(_fort(60.0, 60.0, 0.0, 160.0, held), IdleLogic.THIN) == IdleLogic.THIN, "held beats contested")
	t.ok(NodeLogic.fort_state(_fort(0.0, 0.0, 80.0, 160.0, held), IdleLogic.WILL_FALL) == IdleLogic.WILL_FALL, "held beats emptied")
	t.ok(NodeLogic.fort_state(_fort(10.0, 60.0, 0.0, 160.0, held), "") == IdleLogic.SAFE, "held with no margin yet: safe (IdleLogic's committed fallback)")
	t.ok(NodeLogic.fort_state(_fort(10.0, 60.0, 0.0, 160.0, held), "bogus") == IdleLogic.SAFE, "held with an unknown margin: safe")
	t.ok(NodeLogic.fort_state(_fort(140.0, 0.0, 0.0), IdleLogic.WILL_FALL) == NodeLogic.HERS, "a margin on a fort that is not held is ignored")
	var all := {}
	for s in [NodeLogic.HERS, NodeLogic.CONTESTED, NodeLogic.EMPTIED, IdleLogic.SAFE, IdleLogic.THIN, IdleLogic.WILL_FALL]:
		all[s] = true
	t.ok(all.size() == 6, "six distinct states")
	# the tithe badge: any base state
	var warn := {"tithe": {"targeted": true, "eta_s": 80.0, "wave_active": false}}
	var wave := {"tithe": {"targeted": true, "eta_s": 0.0, "wave_active": true}}
	t.ok(NodeLogic.tithe_badge(_fort(140.0, 0.0, 0.0, 160.0, warn)), "a targeted fort carries the badge")
	t.ok(NodeLogic.tithe_badge(_fort(140.0, 0.0, 0.0, 160.0, wave)), "a fort under the wave carries the badge")
	t.ok(not NodeLogic.tithe_badge(_fort(140.0, 0.0, 0.0)), "no tithe, no badge")
	t.ok(NodeLogic.tithe_badge(_fort(0.0, 0.0, 80.0, 160.0, warn)), "badge on an emptied fort")
	var held_warn := warn.duplicate(true)
	held_warn["held"] = true
	t.ok(NodeLogic.tithe_badge(_fort(10.0, 60.0, 0.0, 160.0, held_warn)) and NodeLogic.fort_state(_fort(10.0, 60.0, 0.0, 160.0, held_warn), IdleLogic.SAFE) == IdleLogic.SAFE,
		"badge on a held fort, and the base state is unchanged")
	t.ok(NodeLogic.tithe_badge({"tithe": {}}) == false and NodeLogic.tithe_badge({}) == false, "a missing tithe block is no badge")


func _states_fixtures(t: TestUtil) -> void:
	t.suite("map_macro-states-fixtures")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	var m := MapModel.new(s)
	m.refresh(true)
	var ash := m.fort("ashgate")
	t.ok(bool(ash["held"]) and NodeLogic.fort_state(ash, m.margin_of("ashgate")) == m.margin_of("ashgate"), "midgame Ashgate is held: its glyph is its margin (%s)" % m.margin_of("ashgate"))
	t.ok(NodeLogic.tithe_badge(ash), "and the real tithe on it carries the badge")
	t.ok(NodeLogic.fort_state(m.fort("greywall"), m.margin_of("greywall")) == NodeLogic.CONTESTED, "midgame Greywall (22 undead, no living, not held) is contested")
	t.ok(NodeLogic.fort_state(m.fort("vespers"), m.margin_of("vespers")) == NodeLogic.HERS, "midgame Vespers (living only) is hers")
	var d := MapModel.new(s)
	d.nodes_demo = true
	d.flip_cfg = TestUtil.configs()["realm"]["flip"]
	d.refresh(true)
	var seen := {}
	var agree := true
	for f in d.forts:
		var id := str(f["id"])
		var st := NodeLogic.fort_state(f, d.margin_of(id))
		seen[st] = true
		if bool(f["held"]) and st != d.margin_of(id):
			agree = false
	t.ok(agree and not d.margins.is_empty(), "every held fort's glyph state is its chip's margin (model.margin_of)")
	t.ok(seen.size() == 6, "midgame with --nodes=demo shows all six states (%s)" % ",".join(seen.keys()))
	var dn: Dictionary = MapLogic.cfg()["demo_nodes"]
	t.ok(NodeLogic.tithe_badge(d.fort(dn["tithe"]["fort"])) and NodeLogic.tithe_badge(d.fort(dn["wave"]["fort"])), "the demo's tithe and wave forts carry the badge")


func _glyph_size(t: TestUtil) -> void:
	t.suite("map_macro-glyph-size")
	var n := NodeLogic.ncfg()
	t.ok(float(n["state_glyph_px"]) >= 14.0, "the state glyph is at least 14 screen px")
	var ok := true
	for z in [0.3, 0.45, 0.61, 1.0, 1.6, 3.0]:
		var half := NodeLogic.state_glyph_half(z)
		ok = ok and absf(half * 2.0 * z - float(n["state_glyph_px"])) < 1e-4
	t.ok(ok, "its full extent is state_glyph_px on screen at every zoom")
	# at the default zoom it stays inside the tier-1 pip ring
	var z0 := 0.61
	var pip_r := maxf(float(n["pip_radius_px"]), float(n["pip_min_screen_px"]) / z0 * 0.5)
	var pip_in := MapLogic.fort_radius(1) - float(n["pip_inset_px"]) - pip_r
	t.ok(NodeLogic.state_glyph_half(z0) < pip_in, "at zoom 0.61 the glyph clears a tier-1 fort's pips (%.1f < %.1f world px)" % [NodeLogic.state_glyph_half(z0), pip_in])


# --- 12b: lane focus and the glow cap ---------------------------------------------

func _focus(t: TestUtil) -> void:
	t.suite("map_macro-focus")
	var forts := {"ashgate": {}, "greywall": {}}
	var home := {"state": "home", "at": "covington", "target": ""}
	t.ok(LaneStyle.focus_ids("", home, forts).is_empty(), "nothing selected, Relish home: no focus")
	t.ok(LaneStyle.focus_ids("", {}, forts).is_empty(), "no Relish entry: no focus")
	t.ok(LaneStyle.focus_ids("ashgate", home, forts) == ["ashgate"], "a selected fort is in focus")
	t.ok(LaneStyle.focus_ids("vei", home, forts).is_empty() and LaneStyle.focus_ids("lorn", home, forts).is_empty(), "selecting Vei or a village gives no focus")
	var at := {"state": "at_fort", "at": "greywall", "target": ""}
	t.ok(LaneStyle.focus_ids("", at, forts) == ["greywall"], "Relish standing at a fort puts it in focus")
	t.ok(LaneStyle.focus_ids("", {"state": "in_dungeon", "at": "greywall", "target": ""}, forts) == ["greywall"], "and while she is in its dungeon")
	t.ok(LaneStyle.focus_ids("", {"state": "travelling", "at": "covington", "target": "greywall"}, forts) == ["greywall"], "travelling: her target fort, not where she left")
	t.ok(LaneStyle.focus_ids("", {"state": "travelling", "at": "greywall", "target": "covington"}, forts).is_empty(), "travelling home: no focus")
	t.ok(LaneStyle.focus_ids("", {"state": "travelling", "at": "greywall", "target": "vei"}, forts).is_empty(), "travelling to Vei: no focus")
	t.ok(LaneStyle.focus_ids("", {"state": "at_vei", "at": "vei", "target": ""}, forts).is_empty(), "at Vei: no focus")
	t.ok(LaneStyle.focus_ids("", {"state": "dead", "at": "greywall", "target": ""}, forts).is_empty(), "dead: no focus")
	var both := LaneStyle.focus_ids("ashgate", at, forts)
	t.ok(both.size() == 2 and both.has("ashgate") and both.has("greywall"), "the selected fort and Relish's fort together")
	t.ok(LaneStyle.focus_ids("greywall", at, forts) == ["greywall"], "the same fort once")
	var ids := ["ashgate"]
	t.ok(LaneStyle.focus(_row("war", "covington", "ashgate"), ids), "a lane ending at the fort is in focus")
	t.ok(LaneStyle.focus(_row("flood", "ashgate", "vei"), ids) and LaneStyle.focus(_row("haul", "ashgate", "covington"), ids), "lanes starting there are in focus")
	t.ok(LaneStyle.focus(_row("living", "vei", "ashgate"), ids) and LaneStyle.focus(_row("redirect", "ashgate", "ashgate"), ids), "living in, and its REDIRECT ring")
	t.ok(not LaneStyle.focus(_row("war", "covington", "greywall"), ids), "another fort's lane is not")
	t.ok(not LaneStyle.focus(_row("work", "covington", "covington"), ids) and not LaneStyle.focus(_row("flood", "covington", "vei"), ids), "nor WORK, nor the direct FLOOD")
	t.ok(not LaneStyle.focus(_row("war", "covington", "ashgate"), []), "with no focus ids no lane is in focus")
	var lit := [_row("war", "covington", "ashgate", 0.2), _row("war", "covington", "greywall", 5.0), _row("living", "vei", "ashgate", 0.1),
		_row("flood", "covington", "vei", 9.0), _row("work", "covington", "covington", 1.0)]
	var q := LaneStyle.quiet_ids(lit, ["ashgate"], 1)
	t.ok(q.size() == 3 and q.has("war:covington:greywall") and q.has("flood:covington:vei") and q.has("work:covington:covington"),
		"with a focus every lane off it goes quiet, whatever its rate (%s)" % ",".join(q.keys()))
	t.ok(not q.has("war:covington:ashgate") and not q.has("living:vei:ashgate"), "the focus fort's lanes keep their glow, slow or not")
	t.ok(LaneStyle.quiet_ids(lit, [], 12).is_empty(), "no focus and no more than glow_cap lit: nothing is quiet")


func _glow_cap(t: TestUtil) -> void:
	t.suite("map_macro-glow-cap")
	var lit := [_row("war", "covington", "a", 0.5), _row("war", "covington", "b", 3.0), _row("war", "covington", "c", 1.0),
		_row("living", "vei", "a", 3.0), _row("flood", "covington", "vei", 0.1), _row("work", "covington", "covington", 2.0)]
	var q := LaneStyle.quiet_ids(lit, [], 3)
	t.ok(q.size() == 3, "past the cap only glow_cap lanes keep their halos (%d quiet of %d)" % [q.size(), lit.size()])
	t.ok(not q.has("war:covington:b") and not q.has("living:vei:a") and not q.has("work:covington:covington"), "the highest-rate lanes keep them")
	t.ok(q.has("war:covington:a") and q.has("war:covington:c") and q.has("flood:covington:vei"), "the slowest go quiet")
	var tie := [_row("war", "covington", "b", 1.0), _row("war", "covington", "a", 1.0), _row("war", "covington", "c", 1.0)]
	var qt := LaneStyle.quiet_ids(tie, [], 2)
	t.ok(qt.size() == 1 and qt.has("war:covington:c"), "ties break by id, so the choice is stable between refreshes")
	t.ok(LaneStyle.quiet_ids(lit, [], 6).is_empty() and LaneStyle.quiet_ids(lit, [], 0).is_empty(), "at the cap, or with no cap, nothing is quiet")
	t.ok(LaneStyle.quiet_ids(lit, ["a"], 100).size() == 4, "a focus wins over the cap: the four lanes off fort a go quiet")
	t.ok(int(MapLogic.cfg()["glow_cap"]) >= 1, "glow_cap is set")


func _quiet(t: TestUtil) -> void:
	t.suite("map_macro-quiet")
	var ground := Palette.c("ground")
	var mult := float(MapLogic.cfg()["quiet_width_mult"])
	t.ok(mult > 0.0 and mult <= 1.0, "quiet_width_mult narrows a lane, never widens it")
	for key in ["war", "living", "redirect"]:
		var row := _row(key, "covington", "ashgate") if key != "living" else _row("living", "vei", "ashgate")
		if key == "redirect":
			row = _row("redirect", "ashgate", "ashgate")
		var style := LaneStyle.style_for(row)
		for u in [0.0, 0.5, 1.0]:
			var ch: Dictionary = p.channels(u, Palette.hue(style["hue_key"]))
			var loud := LaneStyle.lit_layers(ch, style)
			var quiet := LaneStyle.lit_layers(ch, style, true)
			t.ok(quiet.size() == 1 and loud.size() > 1, "%s u=%.1f: quiet is the core alone, no halos" % [key, u])
			t.ok(bool(quiet[0]["hairline"]) and bool(quiet[0]["dashed"]), "%s u=%.1f: the quiet core is a dashed hairline" % [key, u])
			t.near(float(quiet[0]["width"]), LaneStyle.lane_width(ch, style) * mult, 1e-6, "%s u=%.1f: width x quiet_width_mult" % [key, u])
			t.ok((quiet[0]["color"] as Color).is_equal_approx(loud[loud.size() - 1]["color"]), "%s u=%.1f: the same core colour at the same floored alpha" % [key, u])
			var cr := MapLogic.contrast_ratio(quiet[0]["color"], ground)
			t.ok(cr >= 3.0, "%s u=%.1f: a quiet core still reads 3:1 over ground (%.2f)" % [key, u, cr])


# --- 12c: the hue floor and the retune --------------------------------------------

func _hue(u: float, key: String) -> float:
	var hue := Palette.hue(key)
	return LaneStyle.with_hue(p.channels(u, hue), p.channels(LaneStyle.hue_u(u), hue))["hue"]


func _hue_floor(t: TestUtil) -> void:
	t.suite("map_macro-hue-floor")
	var floor_u := float(MapLogic.cfg()["hue_u_floor"])
	# the smallest u at which Pulse's eased hue reads green (<= 170) and orange-red (0..25)
	var need_undead := 2.0
	var need_living := 2.0
	for i in 1001:
		var u := i / 1000.0
		var hu: float = p.channels(u, Palette.hue("undead"))["hue"]
		var hl: float = p.channels(u, Palette.hue("living"))["hue"]
		if need_undead > 1.0 and hu <= 170.0:
			need_undead = u
		if need_living > 1.0 and hl <= 25.0:
			need_living = u
	var need := maxf(need_undead, need_living)
	t.ok(need <= 1.0, "Pulse reaches both target hues (undead at u=%.3f, living at u=%.3f)" % [need_undead, need_living])
	t.ok(floor_u >= need and floor_u <= 1.0, "hue_u_floor %.2f is at or above the smallest u that holds both (%.3f)" % [floor_u, need])
	var worst_undead := 0.0
	var worst_living := 0.0
	var other_ok := true
	for i in 101:
		var u := i / 100.0
		for key in ["undead", "living"]:
			var hue := Palette.hue(key)
			var ch: Dictionary = p.channels(u, hue)
			var out := LaneStyle.with_hue(ch, p.channels(LaneStyle.hue_u(u), hue))
			for k in ["u", "width", "speed", "period", "dash", "alpha", "hz"]:
				other_ok = other_ok and is_equal_approx(float(out[k]), float(ch[k]))
			other_ok = other_ok and is_equal_approx((out["color"] as Color).a, float(ch["alpha"]))
			if key == "undead":
				worst_undead = maxf(worst_undead, float(out["hue"]))
			else:
				worst_living = maxf(worst_living, float(out["hue"]))
	t.ok(worst_undead <= 170.0, "undead lanes read green at every u: hue <= 170 (worst %.1f)" % worst_undead)
	t.ok(worst_living <= 25.0, "living lanes read orange-red at every u: hue 0..25, never toward danger's 345 (worst %.1f)" % worst_living)
	t.ok(other_ok, "width, speed, period, dash, frequency and alpha all keep the real u; only the hue moves")
	t.ok(_hue(0.0, "undead") == _hue(floor_u * 0.5, "undead"), "below the floor every u shares the floor's hue")
	t.ok(_hue(1.0, "undead") < _hue(floor_u, "undead"), "above it the hue still eases toward the flow's own")
	t.ok(LaneStyle.hue_u(-1.0) < 0.0, "an off lane stays off")
	var war := LaneStyle.style_for(_row("war", "covington", "ashgate"))
	var hue := Palette.hue("undead")
	var lo := LaneStyle.with_hue(p.channels(0.1, hue), p.channels(LaneStyle.hue_u(0.1), hue))
	var hi := LaneStyle.with_hue(p.channels(0.4, hue), p.channels(LaneStyle.hue_u(0.4), hue))
	t.ok(LaneStyle.lane_width(hi, war) > LaneStyle.lane_width(lo, war) and float(hi["period"]) < float(lo["period"]),
		"rate ranking survives in width and dash period")
	var c := LaneStyle.with_hue(p.channels(0.1, hue), p.channels(LaneStyle.hue_u(0.1), hue))["color"] as Color
	var want := p.channels(floor_u, hue)["color"] as Color
	t.ok(Color(c, 1.0).is_equal_approx(Color(want, 1.0)), "the halo colour is the floored channel's (hue and its lightness)")


## The median lit lane of the three fixtures (view_lanes plus the model's ship_in stand-ins) sits
## near u = 0.5 at rate_log_max.
func _retune(t: TestUtil) -> void:
	t.suite("map_macro-retune")
	var log_max := float(MapLogic.cfg()["rate_log_max"])
	var rates: Array = []
	for fx in ["day1", "midgame_2flips", "pre_vei"]:
		var s := GameState.new(TestUtil.configs())
		s.debug_enabled = true
		s.cmd_debug_load_fixture(fx)
		var m := MapModel.new(s)
		m.refresh(true)
		for r in m.lanes:
			if p.rate_to_u(float(r["rate"]), log_max) >= 0.0:
				rates.append(float(r["rate"]))
	rates.sort()
	t.ok(rates.size() >= 10, "the fixtures light %d lanes" % rates.size())
	if rates.is_empty():
		return
	var mid: float = rates[rates.size() / 2] if rates.size() % 2 == 1 else (rates[rates.size() / 2 - 1] + rates[rates.size() / 2]) * 0.5
	var u: float = p.rate_to_u(mid, log_max)
	t.ok(u >= 0.4 and u <= 0.6, "the median lit lane (%.2f/s) sits near u = 0.5 at rate_log_max %.2f (u = %.2f)" % [mid, log_max, u])
	t.ok(p.rate_to_u(rates[0], log_max) < p.rate_to_u(rates[rates.size() - 1], log_max), "the slowest and the fastest still differ in u")


# --- 12d: Relish and the labels -----------------------------------------------------

func _relish(t: TestUtil) -> void:
	t.suite("map_macro-relish")
	var n := NodeLogic.ncfg()
	var ok := true
	for z in [0.3, 0.45, 0.61, 1.0, 1.6, 3.0]:
		var r := NodeLogic.relish_radii(z)
		ok = ok and r["core"] * z >= float(n["relish_min_core_px"]) - 1e-4 and r["halo"] * z >= float(n["relish_min_halo_px"]) - 1e-4 \
			and r["wide"] > r["halo"] and r["halo"] > r["core"]
	t.ok(ok, "her core and halo hold their minimum screen radii at every zoom, the wide ring outside both")
	var r0 := NodeLogic.relish_radii(0.61)
	t.ok(r0["halo"] * 0.61 > float(n["state_glyph_px"]) and r0["core"] * 0.61 * 2.0 > float(n["state_glyph_px"]) * 0.5,
		"at the default zoom her mark is bigger than any fort's state glyph")


func _plates(t: TestUtil) -> void:
	t.suite("map_macro-plates")
	var cfg := MapLogic.cfg()
	var n := NodeLogic.ncfg()
	var bright_key := ""
	for k in Palette.keys():
		if bright_key == "" or MapLogic.luminance(Palette.c(k)) > MapLogic.luminance(Palette.c(bright_key)):
			bright_key = k
	var plate := NodeLogic.label_plate_color()
	t.ok(Color(plate, 1.0).is_equal_approx(Palette.c("ground")) and plate.a > 0.0 and plate.a <= 1.0, "the plate is the ground at label_plate_alpha")
	t.ok(float(n["label_plate_radius_px"]) > 0.0, "with a small radius")
	# the plate lets (1 - alpha) of whatever is behind it through: the brightest palette key at worst
	var under := Palette.c("ground").lerp(Palette.c(bright_key), 1.0 - plate.a)
	var dim := float(cfg["node_label_dim_alpha"])
	var labels := {
		"fort names, village names, ODDS": Palette.c("text_dim", dim),
		"Covington's WORK / WAR / FLOOD / COVINGTON": Palette.c("undead", dim),
		"VEI'S DOMAIN": Palette.c("vei", dim),
		"Vei's odds": Palette.c("vei"),
		"Vei's drain line": Palette.c("text"),
		"Vei's +N": Palette.c("undead"),
		"the tithe ETA": Palette.c("living"),
		"WAVE": Palette.c("danger"),
		"your first dungeon / INSIDE": Palette.c("relish"),
		"garrison N": Palette.c("text"),
	}
	for k in labels:
		var r := MapLogic.contrast_ratio(labels[k], under)
		t.ok(r >= 4.5, "%s on the plate over %s: %.2f:1 (>= 4.5)" % [k, bright_key, r])
	var chip_under := Palette.c("ground").lerp(Palette.c(bright_key), 1.0 - float(cfg["idle"]["plate_alpha"]))
	for m in [IdleLogic.SAFE, IdleLogic.THIN, IdleLogic.WILL_FALL]:
		var r := MapLogic.contrast_ratio(Palette.c(IdleLogic.color_key(m)), chip_under)
		t.ok(r >= 4.5, "the %s chip on its plate over %s: %.2f:1 (>= 4.5)" % [m, bright_key, r])
	var sizes := [int(cfg["font_label"]), int(n["font_tithe"]), int(n["font_odds"]), int(n["font_odds_sub"]),
		int(cfg["idle"]["chip_font"]), int(cfg["idle"]["garrison_font"])]
	t.ok(sizes.all(func(s): return s >= 12), "every node label is at least 12 px on screen (%s)" % str(sizes))


# --- the --lanes-report line and the speed row --------------------------------------

func _report(t: TestUtil) -> void:
	t.suite("map_macro-report")
	var row := _row("war", "covington", "vespers", 1.418)
	var line := LaneStyle.report_line(row, "undead", 0.272, 0.5, 163.8)
	for part in ["war:covington:vespers", "war", "undead", "1.418", "0.272", "0.500", "163.8"]:
		t.ok(line.contains(part), "the report line carries %s: %s" % [part, line])
	t.ok(LaneStyle.report_header(25.0, 0.0).contains("25.00"), "the header names rate_log_max")


func _speed_row(t: TestUtil) -> void:
	t.suite("map_macro-speed-row")
	var s := StubState.new()
	t.ok(not HudLogic.speed_row_shown(s), "a state whose debug_enabled is false gets no speed row")
	s.debug_enabled = true
	t.ok(HudLogic.speed_row_shown(s), "a debug state gets one")
	t.ok(not HudLogic.speed_row_shown(null), "no state, no row")
	var src := FileAccess.get_file_as_string(HUD_FILE)
	var body := src.substr(src.find("func _build_speed_row"))
	body = body.substr(0, body.find("\nfunc ", 1))
	var gate := body.find("if not HudLogic.speed_row_shown(model.state):")
	var build := body.find("HBoxContainer.new()")
	t.ok(gate > 0 and build > gate and body.substr(gate, build - gate).contains("return"), "MapHud returns before building the row unless the state is a debug one")
