extends RefCounted
## Tests for the macro-readability pass (task 12): the fort state glyph rule (NodeLogic.fort_state
## and the tithe badge), lane focus and the per-kind glow cap (LaneStyle.selection_focus /
## relish_focus / focus / quiet_ids and the quiet stroke), the lane hue floor and the
## rate_log_max retune, Relish's minimum screen size and travel ETA, the label plates' contrast,
## the --lanes-report line and the debug speed row gate.

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
	_static_sig(t)
	_focus(t)
	_glow_cap(t)
	_quiet(t)
	_hue_floor(t)
	_retune(t)
	_relish(t)
	_plates(t)
	_report(t)
	_eta(t)
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
	t.ok(NodeLogic.fort_state(_fort(0.0, 30.0, 40.0), "") == NodeLogic.OVERRUN, "undead there and no living, not flipped: overrun")
	var present := float(n["state_present_frac"]) * 160.0
	t.ok(NodeLogic.fort_state(_fort(present * 0.9, 120.0, 0.0), "") == NodeLogic.OVERRUN, "living under state_present_frac of cap count as absent: overrun")
	t.ok(NodeLogic.fort_state(_fort(present * 1.1, 120.0, 0.0), "") == NodeLogic.CONTESTED, "living just present: contested (both sides), not overrun")
	t.ok(NodeLogic.fort_state(_fort(0.0, present * 0.9, 50.0), "") == NodeLogic.EMPTIED, "undead under the presence floor and no living: emptied, not overrun")
	t.ok(NodeLogic.fort_state(_fort(0.0, 120.0, 0.0, 160.0, {"held": true}), IdleLogic.SAFE) == IdleLogic.SAFE, "held beats overrun")
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
	for s in [NodeLogic.HERS, NodeLogic.OVERRUN, NodeLogic.CONTESTED, NodeLogic.EMPTIED, IdleLogic.SAFE, IdleLogic.THIN, IdleLogic.WILL_FALL]:
		all[s] = true
	t.ok(all.size() == 7, "seven distinct states")
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
	# the regenerated midgame garrisons Greywall with living, so build the overrun state on the real path
	s.cmd_debug_set_state({"forts": {"greywall": {"living": 0.0}}})
	m.refresh(true)
	var gw := m.fort("greywall")
	t.ok(NodeLogic.fort_state(gw, m.margin_of("greywall")) == NodeLogic.OVERRUN and float(gw["undead"]) > 0.0 and not bool(gw["held"]),
		"midgame Greywall with its living cleared (undead %.1f, no living, not held) is overrun" % float(gw["undead"]))
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
	t.ok(seen.size() == 7, "midgame with --nodes=demo shows all seven states (%s)" % ",".join(seen.keys()))
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
	var sq := float(n["state_square_ratio"])
	t.ok(sq >= 1.0, "the square and the hourglass are at least state_glyph_px on a side (axis-aligned extent)")
	# at the default zoom every shape stays inside the tier-1 pip ring
	var z0 := 0.61
	var pip_r := maxf(float(n["pip_radius_px"]), float(n["pip_min_screen_px"]) / z0 * 0.5)
	var pip_in := MapLogic.fort_radius(1) - float(n["pip_inset_px"]) - pip_r
	var reach := NodeLogic.state_glyph_half(z0) * maxf(1.0, sq)
	t.ok(reach < pip_in, "at zoom 0.61 every glyph's side (half extent) stays inside a tier-1 fort's pips (%.1f < %.1f world px)" % [reach, pip_in])


## The nodes' redraw economy: a fort's static rings redraw only when what they draw changed, and
## the glyphs' beat is their layer's modulate (no per-frame redraw).
func _static_sig(t: TestUtil) -> void:
	t.suite("map_macro-static-sig")
	var flip := {"hold_s": 300.0, "tier_mult": 0.5}
	var base := _fort(100.0, 40.0, 10.0, 160.0)
	var sig := NodeLogic.fort_static_sig(base, flip)
	var steps := float(NodeLogic.ncfg()["static_sig_steps"])
	t.ok(steps >= 256.0, "arcs and the held sweep are quantized finer than a screen pixel (1/%d of a turn)" % int(steps))
	t.ok(NodeLogic.fort_static_sig(_fort(100.0 + 160.0 / steps * 0.2, 40.0, 10.0, 160.0), flip) == sig, "a drift under one step (a fraction of a body) does not redraw")
	t.ok(NodeLogic.fort_static_sig(_fort(100.0 + 160.0 / steps * 3.0, 40.0, 10.0, 160.0), flip) != sig, "a few steps of matter redraw")
	t.ok(NodeLogic.fort_static_sig(_fort(100.0, 60.0, 10.0, 160.0), flip) != sig, "a new pip redraws")
	var held := _fort(10.0, 60.0, 0.0, 160.0, {"held": true, "held_s_left": 300.0})
	var hs := NodeLogic.fort_static_sig(held, flip)
	t.ok(hs != NodeLogic.fort_static_sig(_fort(10.0, 60.0, 0.0, 160.0), flip), "held redraws")
	var grace := NodeLogic.grace_total(flip, 2)
	t.ok(NodeLogic.fort_static_sig(_fort(10.0, 60.0, 0.0, 160.0, {"held": true, "held_s_left": 300.0 - grace / steps * 0.2}), flip) == hs, "the countdown under a step does not")
	t.ok(NodeLogic.fort_static_sig(_fort(10.0, 60.0, 0.0, 160.0, {"held": true, "held_s_left": 300.0 - grace / steps * 3.0}), flip) != hs, "a few steps of countdown do")
	t.ok(NodeLogic.fort_static_sig(_fort(100.0, 40.0, 10.0, 160.0, {"simulacrum_charges": 3.0}), flip) != sig, "a simulacrum redraws")
	t.near(NodeLogic.state_alpha(0.0), float(NodeLogic.ncfg()["state_alpha_base"]), 1e-6, "the glyph beat's trough is state_alpha_base")
	t.ok(NodeLogic.state_alpha(1.0) <= 1.0 and NodeLogic.state_alpha(1.0) > NodeLogic.state_alpha(0.0), "and its crest at most 1")
	var nodes := FileAccess.get_file_as_string("res://scripts/map/map_nodes.gd")
	t.ok(nodes.contains("var sig = l.static_sig()") and nodes.contains("_sigs[l] != sig"), "MapNodes redraws a static layer only when its static_sig changed")
	t.ok(nodes.contains("_glyph_beat.modulate.a = NodeLogic.state_alpha(Pulse.wave(model.hops_of("), "the glyphs beat through their layer's modulate, on Pulse at the forts' hop")
	var glyph := FileAccess.get_file_as_string("res://scripts/map/map_fort_glyph.gd")
	t.ok(glyph.contains("func static_sig()") and not glyph.contains("Pulse."), "the glyph layer reads no clock: it redraws on a state change only")


# --- 12b: lane focus and the glow cap ---------------------------------------------

func _focus(t: TestUtil) -> void:
	t.suite("map_macro-focus")
	var forts := {"ashgate": {}, "greywall": {}}
	t.ok(LaneStyle.selection_focus("ashgate", forts) == ["ashgate"], "a selected fort is the selection focus")
	t.ok(LaneStyle.selection_focus("", forts).is_empty() and LaneStyle.selection_focus("vei", forts).is_empty() and LaneStyle.selection_focus("lorn", forts).is_empty(),
		"nothing, Vei or a village selected: no selection focus")
	t.ok(LaneStyle.relish_focus({"state": "home", "at": "covington", "target": ""}, forts).is_empty() and LaneStyle.relish_focus({}, forts).is_empty(), "Relish home, or no entry: no fort")
	t.ok(LaneStyle.relish_focus({"state": "at_fort", "at": "greywall", "target": ""}, forts) == ["greywall"], "standing at a fort: that fort")
	t.ok(LaneStyle.relish_focus({"state": "in_dungeon", "at": "greywall", "target": ""}, forts) == ["greywall"], "in its dungeon: that fort")
	t.ok(LaneStyle.relish_focus({"state": "travelling", "at": "covington", "target": "greywall"}, forts) == ["greywall"], "travelling: her target fort, not where she left")
	t.ok(LaneStyle.relish_focus({"state": "travelling", "at": "greywall", "target": "covington"}, forts).is_empty()
		and LaneStyle.relish_focus({"state": "travelling", "at": "greywall", "target": "vei"}, forts).is_empty(), "travelling home or to Vei: no fort")
	t.ok(LaneStyle.relish_focus({"state": "at_vei", "at": "vei", "target": ""}, forts).is_empty() and LaneStyle.relish_focus({"state": "dead", "at": "greywall", "target": ""}, forts).is_empty(),
		"at Vei, or dead: no fort")
	var ids := ["ashgate"]
	t.ok(LaneStyle.focus(_row("war", "covington", "ashgate"), ids), "a lane ending at the fort touches it")
	t.ok(LaneStyle.focus(_row("flood", "ashgate", "vei"), ids) and LaneStyle.focus(_row("haul", "ashgate", "covington"), ids), "lanes starting there do")
	t.ok(LaneStyle.focus(_row("living", "vei", "ashgate"), ids) and LaneStyle.focus(_row("redirect", "ashgate", "ashgate"), ids), "living in, and its REDIRECT ring")
	t.ok(not LaneStyle.focus(_row("war", "covington", "greywall"), ids), "another fort's lane does not")
	t.ok(not LaneStyle.focus(_row("work", "covington", "covington"), ids) and not LaneStyle.focus(_row("flood", "covington", "vei"), ids), "nor WORK, nor the direct FLOOD")
	t.ok(not LaneStyle.focus(_row("war", "covington", "ashgate"), []), "no ids, no lane")
	# a selection quiets every other lane; Relish's fort stays loud with it
	var lit := [_row("war", "covington", "ashgate", 0.2), _row("war", "covington", "greywall", 5.0), _row("living", "vei", "ashgate", 0.1),
		_row("flood", "covington", "vei", 9.0), _row("work", "covington", "covington", 1.0), _row("living", "vei", "greywall", 0.3)]
	var q := LaneStyle.quiet_ids(lit, ["ashgate"], [], 4)
	t.ok(q.size() == 4 and q.has("war:covington:greywall") and q.has("flood:covington:vei") and q.has("work:covington:covington") and q.has("living:vei:greywall"),
		"a selected fort quiets every lane off it, whatever its rate (%s)" % ",".join(q.keys()))
	t.ok(not q.has("war:covington:ashgate") and not q.has("living:vei:ashgate"), "its own lanes stay loud, slow or not")
	var qr := LaneStyle.quiet_ids(lit, ["ashgate"], ["greywall"], 4)
	t.ok(qr.size() == 2 and qr.has("flood:covington:vei") and qr.has("work:covington:covington"), "with a selection, Relish's fort's lanes are loud as well")
	t.ok(LaneStyle.quiet_ids(lit, [], ["greywall"], 4).is_empty(), "Relish alone quiets nothing: under the cap every lane is loud")
	t.ok(LaneStyle.quiet_ids(lit, [], [], 0).is_empty(), "no selection and no cap: nothing is quiet")


func _glow_cap(t: TestUtil) -> void:
	t.suite("map_macro-glow-cap")
	var lit := [_row("war", "covington", "a", 0.5), _row("war", "covington", "b", 3.0), _row("war", "covington", "c", 1.0),
		_row("living", "vei", "a", 0.05), _row("living", "vei", "b", 0.2), _row("living", "vei", "c", 0.1), _row("haul", "a", "covington", 0.07)]
	var q := LaneStyle.quiet_ids(lit, [], [], 2)
	t.ok(q.size() == 2 and q.has("war:covington:a") and q.has("living:vei:a"), "past the cap, each kind's slowest go quiet (%s)" % ",".join(q.keys()))
	t.ok(not q.has("living:vei:b") and not q.has("living:vei:c") and not q.has("haul:a:covington"),
		"the cap is per kind: living's top two stay loud beside far faster WAR, and a lone haul too")
	var qr := LaneStyle.quiet_ids(lit, [], ["a"], 2)
	t.ok(qr.is_empty(), "Relish's fort's lanes stay loud on top of the cap")
	var tie := [_row("war", "covington", "b", 1.0), _row("war", "covington", "a", 1.0), _row("war", "covington", "c", 1.0)]
	var qt := LaneStyle.quiet_ids(tie, [], [], 2)
	t.ok(qt.size() == 1 and qt.has("war:covington:c"), "ties break by id, so the choice is stable between refreshes")
	t.ok(LaneStyle.quiet_ids(lit, [], [], 3).is_empty(), "at the cap nothing is quiet")
	# hysteresis: two near-equal lanes at the boundary don't flip-flop
	var memo := {}
	var h := float(MapLogic.cfg()["glow_cap_hysteresis"])
	t.ok(h > 0.0, "glow_cap_hysteresis is configured")
	var near := [_row("war", "covington", "a", 2.0), _row("war", "covington", "b", 1.0), _row("war", "covington", "c", 0.98)]
	var q1 := LaneStyle.quiet_ids(near, [], [], 2, memo, h)
	t.ok(q1.size() == 1 and q1.has("war:covington:c"), "first call: the two fastest are loud")
	near[2]["rate"] = 1.04  # c passes b, but not by 10%
	var q2 := LaneStyle.quiet_ids(near, [], [], 2, memo, h)
	t.ok(q2.size() == 1 and q2.has("war:covington:c"), "c just ahead of b does not displace it")
	near[2]["rate"] = 1.2  # clearly ahead
	var q3 := LaneStyle.quiet_ids(near, [], [], 2, memo, h)
	t.ok(q3.size() == 1 and q3.has("war:covington:b"), "c clearly ahead of b displaces it")
	near[1]["rate"] = 1.25  # b is back ahead of c, but not by 10%
	var q4 := LaneStyle.quiet_ids(near, [], [], 2, memo, h)
	t.ok(q4.size() == 1 and q4.has("war:covington:b"), "and b slightly ahead again does not flip it back")
	var flips := 0
	var last := q4
	for i in 8:  # rates wobbling around equality never flip the set
		near[1]["rate"] = 1.2 + (0.02 if i % 2 == 0 else -0.02)
		near[2]["rate"] = 1.2 - (0.02 if i % 2 == 0 else -0.02)
		var qi := LaneStyle.quiet_ids(near, [], [], 2, memo, h)
		if qi != last:
			flips += 1
		last = qi
	t.ok(flips == 0, "near-equal lanes wobbling at the boundary never flip (%d flips)" % flips)
	t.ok(LaneStyle.quiet_ids(near, [], [], 2).size() == 1, "without a memo the plain ranking still answers")
	t.ok(int(MapLogic.cfg()["glow_cap_per_kind"]) >= 1 and not MapLogic.cfg().has("glow_cap"), "glow_cap_per_kind replaces the global glow_cap")


func _quiet(t: TestUtil) -> void:
	t.suite("map_macro-quiet")
	var ground := Palette.c("ground")
	var mult := float(MapLogic.cfg()["quiet_width_mult"])
	t.ok(mult > 0.0 and mult <= 1.0, "quiet_width_mult narrows a lane, never widens it")
	var rows := {"war": _row("war", "covington", "ashgate"), "flood": _row("flood", "ashgate", "vei"), "direct flood": _row("flood", "covington", "vei"),
		"work": _row("work", "covington", "covington"), "haul": _row("haul", "ashgate", "covington"), "living": _row("living", "vei", "ashgate"),
		"redirect": _row("redirect", "ashgate", "ashgate")}
	for key in rows:
		var style := LaneStyle.style_for(rows[key])
		for u in [0.0, 0.5, 1.0]:
			var hue := Palette.hue(style["hue_key"])
			var ch := LaneStyle.with_hue(p.channels(u, hue), p.channels(LaneStyle.hue_u(u), hue))
			var loud := LaneStyle.lit_layers(ch, style)
			var quiet := LaneStyle.lit_layers(ch, style, true)
			t.ok(quiet.size() == 1 and loud.size() > 1, "%s u=%.1f: quiet is one stroke, no halos" % [key, u])
			t.ok(bool(quiet[0]["hairline"]) and bool(quiet[0]["dashed"]), "%s u=%.1f: a dashed hairline" % [key, u])
			t.near(float(quiet[0]["width"]), LaneStyle.lane_width(ch, style) * mult, 1e-6, "%s u=%.1f: width x quiet_width_mult" % [key, u])
			var qc: Color = quiet[0]["color"]
			var want := Color(ch["color"], maxf(LaneStyle.lane_alpha(ch, style), float(MapLogic.cfg()["quiet_alpha_floor"])))
			t.ok(qc.is_equal_approx(want), "%s u=%.1f: the lane's own floored-hue colour, at max(floored alpha, quiet_alpha_floor)" % [key, u])
			var hd := absf(wrapf(qc.h * 360.0 - hue, -180.0, 180.0))
			t.ok(hd <= 20.0 and qc.s >= 0.6, "%s u=%.1f: hue within 20 deg of the flow (%.0f vs %.0f), saturation >= 0.6 (%.2f)" % [key, u, qc.h * 360.0, hue, qc.s])
			t.ok(LaneStyle.core_color(ch, style, true).is_equal_approx(qc), "%s u=%.1f: its chevrons take the same colour" % [key, u])
			var cr := MapLogic.contrast_ratio(qc, ground)
			t.ok(cr >= 3.0, "%s u=%.1f: a quiet hairline reads 3:1 over ground (%.2f)" % [key, u, cr])
		# identity: the quiet core keeps its flow's hue family
		var hue0 := Palette.hue(style["hue_key"])
		var c0: Color = LaneStyle.lit_layers(LaneStyle.with_hue(p.channels(0.0, hue0), p.channels(LaneStyle.hue_u(0.0), hue0)), style, true)[0]["color"]
		var hd0 := absf(wrapf(c0.h * 360.0 - hue0, -180.0, 180.0))
		t.ok(hd0 <= 20.0, "%s: a quiet lane at u=0 keeps its flow's hue (%.0f deg vs %.0f)" % [key, c0.h * 360.0, hue0])


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


## rate_log_max against the real lanes (E2a): every live lane of the three fixtures (gutters too)
## after 2 sim seconds, as --lanes-report prints them. At most a tenth of pre_vei's lanes clamp at
## u = 1, so the ranking survives late; the map warms as the game goes on.
func _retune(t: TestUtil) -> void:
	t.suite("map_macro-retune")
	var log_max := float(MapLogic.cfg()["rate_log_max"])
	var stats := {}
	for fx in ["day1", "midgame_2flips", "pre_vei"]:
		var s := GameState.new(TestUtil.configs())
		s.debug_enabled = true
		s.cmd_debug_load_fixture(fx)
		for i in 4:
			s.tick(0.5)
		var m := MapModel.new(s)
		m.refresh(true)
		var sum := 0.0
		var n := 0
		var clamped := 0
		for r in m.lanes:
			var u: float = p.rate_to_u(float(r["rate"]), log_max)
			if u >= 0.0:
				sum += u
				n += 1
				if u >= 1.0:
					clamped += 1
		stats[fx] = {"mean": sum / maxf(n, 1.0), "n": n, "clamped": clamped}
	var pv: Dictionary = stats["pre_vei"]
	t.ok(int(pv["n"]) >= 20, "pre_vei lights %d lanes" % int(pv["n"]))
	t.ok(int(pv["clamped"]) * 10 <= int(pv["n"]), "at most a tenth of pre_vei's lanes clamp at u = 1 (%d of %d) at rate_log_max %.1f" % [int(pv["clamped"]), int(pv["n"]), log_max])
	var d: Dictionary = stats["day1"]
	var mg: Dictionary = stats["midgame_2flips"]
	t.ok(float(d["mean"]) < float(mg["mean"]) and float(mg["mean"]) < float(pv["mean"]),
		"the map warms as the game goes on: mean u day1 %.2f < midgame %.2f < pre_vei %.2f" % [float(d["mean"]), float(mg["mean"]), float(pv["mean"])])


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
		int(cfg["idle"]["chip_font"]), int(GlyphLogic.gcfg()["garrison_font"])]
	t.ok(sizes.all(func(s): return s >= 12), "every node label is at least 12 px on screen (%s)" % str(sizes))


# --- the --lanes-report line and the speed row --------------------------------------

func _report(t: TestUtil) -> void:
	t.suite("map_macro-report")
	var row := _row("war", "covington", "vespers", 1.418)
	var line := LaneStyle.report_line(row, "undead", 0.272, 0.5, 163.8)
	for part in ["war:covington:vespers", "war", "undead", "1.418", "0.272", "0.500", "163.8"]:
		t.ok(line.contains(part), "the report line carries %s: %s" % [part, line])
	t.ok(LaneStyle.report_header(25.0, 0.0).contains("25.00"), "the header names rate_log_max")


func _eta(t: TestUtil) -> void:
	t.suite("map_macro-eta")
	t.ok(RelishLogic.fmt_eta(0.439) == "0:01" and RelishLogic.fmt_eta(0.939) == "0:01", "a trip with under a second left reads 0:01, never 0:00")
	t.ok(RelishLogic.fmt_eta(1.2) == "0:02" and RelishLogic.fmt_eta(59.5) == "1:00", "it rounds up")
	t.ok(RelishLogic.fmt_eta(60.0) == "1:00" and RelishLogic.fmt_eta(60.0000001) == "1:00" and RelishLogic.fmt_eta(4.0) == "0:04", "whole seconds stay whole (float noise absorbed)")
	t.ok(RelishLogic.fmt_eta(0.0) == "0:00" and RelishLogic.fmt_eta(-1.0) == "0:00", "arrived, or the API's none: 0:00")
	var travelling := {"state": "travelling", "at": "covington", "target": "greywall", "eta_s": 0.439}
	t.ok(RelishLogic.chip_text(travelling, {"greywall": "Greywall"}).ends_with("0:01"), "the chip reads 0:01 in her last half-second, not 0:00")


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
