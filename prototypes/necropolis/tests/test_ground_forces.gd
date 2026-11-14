extends RefCounted
## What the game does to the flow ground's current (GroundForces, phase B): the routes' push
## weights, Vei's backlog clot, Relish's pull, and the tithe surges and flip inks, as the uniforms
## flow_ground.gd uploads. Plus the shader's array sizes and the lane cap's bound.


func _same(a: Vector2, b: Vector2) -> bool:
	return a.is_equal_approx(b)


func run() -> int:
	var t := TestUtil.new()
	t.suite("ground_forces")
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	LineGlow.configure(TestUtil.load_json("res://configs/line_glow.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	var ground := TestUtil.load_json("res://configs/ground.json")
	var fc: Dictionary = ground.get("forces", {})
	t.ok(not fc.is_empty(), "ground.json has a forces section")
	for k in ["route", "vortex", "relish", "surge", "ink"]:
		t.ok(fc.has(k), "forces.%s is tuned in ground.json" % k)
	var gf := GroundForces.new(fc)
	var kinds: Dictionary = fc["route"]["kinds"]

	# routes: the kind's weight times u; off rows and dead push nothing
	t.ok(gf.lane_weight("war", -1.0) == 0.0 and gf.lane_weight("war", 0.0) == 0.0, "an off lane pushes nothing")
	t.ok(is_equal_approx(gf.lane_weight("war", 0.5), float(kinds["war"]) * 0.5), "a WAR lane pushes by its kind's weight x u")
	t.ok(gf.lane_weight("flood", 0.8) > gf.lane_weight("flood", 0.2), "a busier lane pushes harder")
	t.ok(gf.lane_weight("dead", 0.9) == 0.0, "a dead gutter pushes nothing: dead stays matte")
	t.ok(gf.lane_weight("nonsense", 0.9) == 0.0, "an unlisted kind pushes nothing")

	# Vei's clot: the odds, the sign
	var vc: Dictionary = fc["vortex"]
	t.ok(gf.vortex({"odds": 0.0, "sign": 1}) == Vector4.ZERO, "no backlog, no clot")
	var mid := gf.vortex({"odds": 0.256, "sign": 1})     # midgame_2flips: backlog 4000
	var late := gf.vortex({"odds": 0.609, "sign": -1})   # pre_vei: backlog 18700
	t.ok(mid.x > 0.0 and late.x > mid.x * 2.0, "the clot grows with the odds (%.2f -> %.2f)" % [mid.x, late.x])
	t.ok(late.y > mid.y and mid.y >= float(vc["radius_px"][0]) and late.y <= float(vc["radius_px"][1]), "... and so does its reach")
	t.ok(is_equal_approx(gf.vortex({"odds": 0.99, "sign": 0}).x, 1.0), "it saturates at full_odds")
	t.ok(mid.z == 1.0 and late.z == -1.0 and gf.vortex({"odds": 0.5, "sign": 0}).z == 0.0,
		"it tightens while her queue grows, unwinds while it drains, only circulates when flat")
	t.ok(is_equal_approx(mid.w, float(vc["inner_px"])), "the clot starts at her gates (inner_px)")

	# Relish: her state, her tide
	var rc: Dictionary = fc["relish"]
	var base := {"pos": [1665.0, 975.0], "effects": {"tide_fort": "", "redirect_fort": "", "home": false}}
	var trav := base.duplicate(true)
	trav["state"] = "travelling"
	var tide := base.duplicate(true)
	tide["state"] = "at_fort"
	tide["effects"]["tide_fort"] = "greywall"
	var dead := base.duplicate(true)
	dead["state"] = "dead"
	var home := base.duplicate(true)
	home["state"] = "home"
	var rv := gf.relish(trav)
	t.ok(_same(Vector2(rv.x, rv.y), Vector2(1665, 975)) and is_equal_approx(rv.w, float(rc["radius_px"])), "the pull sits on her")
	t.ok(is_equal_approx(rv.z, float(rc["states"]["travelling"])), "travelling: her state's weight")
	t.ok(is_equal_approx(gf.relish(tide).z, float(rc["states"]["at_fort"]) * float(rc["tide_mult"])), "her tide strengthens it")
	t.ok(gf.relish(dead) == Vector4.ZERO, "dead: no pull")
	t.ok(gf.relish(home).z == float(rc["states"].get("home", 0.0)), "home: her home weight")

	# tithe surges, driven by the standing state
	var sc: Dictionary = fc["surge"]
	var pos := {"vei": Vector2(1024, 130), "covington": Vector2(1780, 1270), "ashgate": Vector2(1500, 900),
		"greywall": Vector2(1665, 975)}
	var warn := {"target": "ashgate", "eta_s": 131.0, "warning": true, "wave_active": false}
	var wave := {"target": "ashgate", "eta_s": 0.0, "warning": false, "wave_active": true}
	gf.update(0.0, warn, pos)
	var su := gf.surge_arrays(0.0, false)
	t.ok(su["count"] == 1, "a pending warning sends a surge")
	var curve := MapLogic.lane_curve(pos["vei"], pos["ashgate"], 1.0)
	var ac: Vector4 = su["ac"][0]
	var b: Vector4 = su["b"][0]
	t.ok(_same(Vector2(ac.x, ac.y), curve["a"]) and _same(Vector2(ac.z, ac.w), curve["c"]) and _same(Vector2(b.x, b.y), curve["b"]),
		"from Vei to its fort, along the living lane's curve")
	t.ok(is_equal_approx(b.w, float(sc["warning_strength"])) and b.z == 0.0, "a warning's surge is faint and starts at Vei")
	gf.update(1.0, warn, pos)
	t.ok(gf.surge_arrays(1.0, false)["count"] == 1, "no repeat before warning_every_s")
	var dur := float(sc["seconds"])
	var mid_b: Vector4 = gf.surge_arrays(dur * 0.5, false)["b"][0]
	t.ok(is_equal_approx(mid_b.z, 0.5 * (1.0 + float(sc["tail"]))), "the head runs along the curve")
	t.ok(gf.surge_arrays(dur * 0.999, false)["b"][0].w < b.w * 0.1, "and fades out at the end")
	gf.update(dur + 0.01, warn, pos)
	t.ok(gf.surge_arrays(dur + 0.01, false)["count"] == 0, "a finished surge is dropped")
	var every := float(sc["warning_every_s"])
	gf.update(every + 0.01, warn, pos)
	t.ok(gf.surge_arrays(every + 0.01, false)["count"] == 1, "the warning repeats every warning_every_s")
	gf.on_event({"t": 100.0, "type": "tithe_wave", "fort_id": "ashgate"}, every + 0.1, 100.0, pos)
	gf.update(every + 0.1, wave, pos)
	var ws := gf.surge_arrays(every + 0.1, false)
	t.ok(ws["count"] == 2 and is_equal_approx(ws["b"][1].w, 1.0), "a wave's event sends a full surge at once")
	for i in 6:
		gf.update(every + 0.2 + i * float(sc["wave_every_s"]), wave, pos)
	t.ok(gf.surge_arrays(every + 0.2, false)["count"] <= GroundForces.MAX_SURGES, "at most MAX_SURGES run at once")
	var sa := gf.surge_arrays(float(gf.sweeps[-1]["t0"]) + dur * 0.5, true)
	var red: Vector4 = sa["b"][sa["count"] - 1]   # the newest surge, mid-sweep
	var red0: Vector4 = gf.surge_arrays(float(gf.sweeps[-1]["t0"]), true)["b"][sa["count"] - 1]
	t.ok(red.z == 1.0 and red.w > 0.9 and red0.w < 0.1, "reduced motion: the whole line stands and fades in, instead of running")
	var quiet := GroundForces.new(fc)
	quiet.update(0.0, {"target": "", "eta_s": -1.0, "warning": false, "wave_active": false}, pos)
	quiet.update(0.0, {"target": "nowhere", "eta_s": 5.0, "warning": true, "wave_active": false}, pos)
	t.ok(quiet.sweeps.is_empty(), "no target, or a fort without a position: no surge")

	# flips ink the ground
	var ik := GroundForces.new(fc)
	ik.on_event({"t": 50.0, "type": "fort_flipped", "fort_id": "greywall"}, 0.0, 50.0, pos)
	ik.on_event({"t": 50.0, "type": "fort_retaken", "fort_id": "ashgate"}, 0.0, 50.0, pos)
	ik.on_event({"t": 10.0, "type": "fort_flipped", "fort_id": "greywall"}, 0.0, 50.0, pos)   # stale
	ik.on_event({"t": 50.0, "type": "fort_flipped", "fort_id": "ghost"}, 0.0, 50.0, pos)
	ik.on_event({"t": 50.0, "type": "autosaved"}, 0.0, 50.0, pos)
	var ia := ik.ink_array(0.5, false)
	t.ok(ia["count"] == 2, "a flip and a retake ink; a stale event, an unknown fort and other events don't (%d)" % ia["count"])
	var flip: Vector4 = ia["ink"][0]
	var back: Vector4 = ia["ink"][1]
	t.ok(_same(Vector2(flip.x, flip.y), pos["greywall"]) and flip.w > 0.0 and back.w < 0.0, "a flip inks green (+), a retake orange (-)")
	var ink_r := float(fc["ink"]["radius_px"])
	var ink_s := float(fc["ink"]["seconds"])
	t.ok(flip.z > 0.0 and flip.z < ink_r and ik.ink_array(ink_s * 0.6, false)["ink"][0].z > flip.z, "a flip's front eases outward")
	t.ok(back.z < ink_r and ik.ink_array(ink_s * 0.6, false)["ink"][1].z < back.z,
		"a retake's front closes in on the fort: they differ by motion, not only hue")
	t.ok(is_equal_approx(ik.ink_array(0.5, true)["ink"][0].z, ink_r), "reduced motion: the front stands at full radius")
	ik.update(ink_s + 0.1, {}, pos)
	t.ok(ik.ink_array(ink_s + 0.1, false)["count"] == 0, "a finished ink is dropped")

	# sizes shared with the shader, and the lane cap's bound
	var sh := FileAccess.get_file_as_string("res://shaders/flow_particles.gdshader")
	t.ok(sh.contains("const int MAX_SURGES = %d;" % GroundForces.MAX_SURGES), "the shader's MAX_SURGES matches")
	t.ok(sh.contains("const int MAX_INKS = %d;" % GroundForces.MAX_INKS), "the shader's MAX_INKS matches")
	var fg := FileAccess.get_file_as_string("res://scripts/map/flow_ground.gd")
	var m := RegEx.create_from_string("const MAX_LANES := (\\d+)").search(fg)
	var max_lanes := int(m.get_string(1)) if m != null else 0
	t.ok(max_lanes > 0 and sh.contains("const int MAX_LANES = %d;" % max_lanes), "the shader's MAX_LANES matches flow_ground's")
	# GroundMoat drops self-loops (work, redirect): per fort war, flood, dead, living and haul, plus
	# flood covington -> vei and war covington -> vei
	var forts: int = TestUtil.load_json("res://configs/world.json")["forts"].size()
	t.ok(2 + 5 * forts <= max_lanes, "every lane view_lanes can draw fits the moat (%d forts: at most %d of %d)" % [
		forts, 2 + 5 * forts, max_lanes])
	t.ok(not FileAccess.get_file_as_string("res://scripts/map/ground_forces.gd").contains("inject("),
		"render-only: GroundForces never writes the influence field")
	return t.failures
