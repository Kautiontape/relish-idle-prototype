extends RefCounted
## Tests for transition_logic.gd (the router's dive: timeline, easing, camera targets, the slow
## factor) and a source check that main.gd still applies and autosaves synchronously. No autoloads.


func run() -> int:
	var t := TestUtil.new()
	t.suite("map_transition")
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	var c := TransitionLogic.cfg()
	_timeline(t, c)
	_ease(t, c)
	_targets(t, c)
	_slow(t)
	_router_source(t)
	return t.failures


func _timeline(t: TestUtil, c: Dictionary) -> void:
	var dive := TransitionLogic.timeline(c, TransitionLogic.IN, false)
	t.ok(dive["total_s"] < 0.6, "the dive in is under 600 ms")
	t.ok(absf(dive["total_s"] - (dive["zoom_s"] + dive["fade_s"])) < 1e-9, "the dive in is the zoom, then the fade")
	t.ok(dive["zoom_s"] > 0.0 and dive["fade_s"] > 0.0, "both dive phases have a length")
	var back := TransitionLogic.timeline(c, TransitionLogic.OUT, false)
	t.ok(back["total_s"] < 0.6, "the return is under 600 ms")
	t.ok(back["total_s"] == maxf(back["zoom_s"], back["fade_s"]), "the return's zoom and fade run together")
	for kind in [TransitionLogic.IN, TransitionLogic.OUT]:
		var r := TransitionLogic.timeline(c, kind, true)
		t.ok(absf(r["total_s"] - 0.15) < 1e-9 and r["zoom_s"] == 0.0, "reduced motion is a 150 ms fade with no zoom (%s)" % kind)
	var slow := TransitionLogic.timeline(c, TransitionLogic.IN, false, 8.0)
	t.ok(absf(slow["total_s"] - dive["total_s"] * 8.0) < 1e-9, "the slow factor multiplies every duration")
	t.ok(absf(TransitionLogic.timeline(c, TransitionLogic.IN, true, 8.0)["total_s"] - 1.2) < 1e-9, "the slow factor scales the reduced fade too")
	t.ok(dive["total_s"] * 1000.0 <= float(c["max_total_ms"]), "the config's max_total_ms holds")


func _ease(t: TestUtil, c: Dictionary) -> void:
	var p := float(c["ease_power"])
	t.ok(TransitionLogic.ease_t(0.0, p) == 0.0 and TransitionLogic.ease_t(1.0, p) == 1.0, "the ease runs 0 to 1")
	t.ok(absf(TransitionLogic.ease_t(0.5, p) - 0.5) < 1e-9, "the in-out ease is 0.5 at the middle")
	t.ok(TransitionLogic.ease_t(0.25, p) < 0.25 and TransitionLogic.ease_t(0.75, p) > 0.75, "the ease is slow at both ends")
	t.ok(TransitionLogic.ease_t(-1.0, p) == 0.0 and TransitionLogic.ease_t(2.0, p) == 1.0, "the ease clamps")
	t.ok(absf(TransitionLogic.ease_t(0.25, 3.0) - 0.0625) < 1e-9, "cubic in-out at 0.25 is 0.0625")
	t.ok(TransitionLogic.progress(0.1, 0.0) == 1.0 and TransitionLogic.progress(0.05, 0.1) == 0.5, "progress of a phase")
	t.ok(absf(TransitionLogic.mix_zoom(0.5, 2.0, 0.5) - 1.0) < 1e-9, "the zoom mix is geometric")
	t.ok(TransitionLogic.mix_zoom(0.6, 1.8, 0.0) == 0.6 and absf(TransitionLogic.mix_zoom(0.6, 1.8, 1.0) - 1.8) < 1e-9, "the zoom mix hits both ends")


func _targets(t: TestUtil, c: Dictionary) -> void:
	var zmin := 0.3
	var zmax := 3.0
	var node := Vector2(120.0, -40.0)
	var d := TransitionLogic.dive_target(0.6, node, c, zmin, zmax)
	t.ok(absf(d["zoom"] - 0.6 * float(c["dive_zoom_mult"])) < 1e-9 and d["centre"] == node, "the dive zooms by the multiplier, centred on the node")
	t.ok(TransitionLogic.dive_target(2.5, node, c, zmin, zmax)["zoom"] == zmax, "the dive zoom clamps to zoom_max")
	t.ok(TransitionLogic.dive_target(0.05, node, c, zmin, zmax)["zoom"] >= zmin, "the dive zoom never falls under zoom_min")
	t.ok(TransitionLogic.arrive_start(0.61, node, c, zmin, zmax) == TransitionLogic.dive_target(0.61, node, c, zmin, zmax), "the arrival starts at the dive's end state")


func _slow(t: TestUtil) -> void:
	t.ok(TransitionLogic.slow_factor(["--transition-slow=8"], true) == 8.0, "--transition-slow=8 multiplies by 8")
	t.ok(TransitionLogic.slow_factor(["--transition-slow=8"], false) == 1.0, "the slow flag is debug-only")
	t.ok(TransitionLogic.slow_factor(["--fixture=day1"], true) == 1.0, "no flag is 1")
	t.ok(TransitionLogic.slow_factor(["--transition-slow=0"], true) == 1.0, "a zero factor is ignored")
	t.ok(TransitionLogic.slow_factor(["--transition-slow=abc"], true) == 1.0, "a bad factor is ignored")
	t.ok(TransitionLogic.slow_factor(["--transition-slow=2.5"], true) == 2.5, "a fractional factor works")


## Source checks on the router: the result apply and the autosave stay synchronous in _swap/_apply
## (a window close mid-raid routes its retreat result here), and time_scale resets on every swap.
func _router_source(t: TestUtil) -> void:
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	var swap := _body(src, "func _swap(")
	t.ok(swap.contains("Engine.time_scale = 1.0"), "main.gd resets Engine.time_scale in _swap")
	t.ok(swap.contains("Game.autosave()"), "main.gd autosaves in _swap")
	t.ok(swap.find("Game.autosave()") < swap.find("_run_transition"), "the autosave runs before any animation starts")
	t.ok(not swap.contains("await"), "_swap itself never awaits")
	var apply := _body(src, "func _apply(")
	t.ok(apply.contains("apply_result(") and not apply.contains("await"), "main.gd applies the result synchronously")
	t.ok(apply.find("apply_result(") < apply.find("_open_map("), "the result applies before the map opens")
	t.ok(src.contains("router_done"), "main.gd keeps the one-emit-per-scene guard")
	t.ok(swap.contains("_held_events = []") and swap.find("_held_events = []") < swap.find("_run_transition"), "_swap resets _held_events before a new swap starts holding")
	var run := _body(src, "func _run_transition(")
	var ab := run.substr(run.find("if gen != _gen:"), 260)
	t.ok(ab.contains("node.queue_free()") and ab.contains("node != current") and ab.find("node.queue_free()") < ab.find("return"), "an abandoned transition frees its unmounted node")


func _body(src: String, head: String) -> String:
	var i := src.find(head)
	if i < 0:
		return ""
	var j := src.find("\n\n\n", i)  # two blank lines end a function
	return src.substr(i, j - i if j >= 0 else src.length() - i)
