extends RefCounted
## Tests for setpiece_logic.gd (the map's set pieces on the tempo): the valve swing's widths over
## its beat, the re-ink's segment order and completion, the tithe tide's band from Vei to the
## fort, victory's run-then-stop, the garrison timeline and its source (the real event, with
## N), first-flip detection, reduced motion going straight to each end
## state, the clock and the debug flags; plus a source check on the set-piece scripts. No autoloads.

const MAP_DIR := "res://scripts/map"
const LINT := preload("res://tests/test_lint.gd")
const FILES := ["map_setpieces.gd", "map_setpiece_layer.gd", "setpiece_logic.gd"]


func run() -> int:
	var t := TestUtil.new()
	t.suite("map_setpieces")
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	var c := SetpieceLogic.cfg()
	_clock(t)
	_valve(t, c)
	_reink(t, c)
	_first_flip(t)
	_return(t, c)
	_place(t, c)
	_words(t)
	_tide(t, c)
	_garrison(t, c)
	_sources_of_garrison(t, c)
	_builds(t, c)
	_build_place(t, c)
	_victory(t, c)
	_reduced(t, c)
	_debug(t, c)
	_after_away(t)
	_callout_cache(t)
	_sources(t)
	return t.failures


## A catch-up swallowed the events: what the set pieces kept from them is re-read from the views.
func _after_away(t: TestUtil) -> void:
	var forts := [{"id": "a", "held": true}, {"id": "b", "held": false}, {"id": "c", "held": true}]
	var r := SetpieceLogic.after_away(["a", "b"], forts, false, false)
	t.ok(r["taken_ids"] == ["a"] and not bool(r["victory"]), "a fort Vei retook inside the catch-up is no longer a taken one; no victory")
	t.ok(bool(SetpieceLogic.after_away([], forts, false, true)["victory"]), "a won realm that never played its victory plays it now")
	t.ok(not bool(SetpieceLogic.after_away([], forts, true, true)["victory"]), "but only once")
	t.ok(SetpieceLogic.after_away(["gone"], forts, false, false)["taken_ids"] == [], "an unknown fort is dropped")
	# victory seen: primed at mount from the view, then set when it plays
	var seen := SetpieceLogic.victory_seen(false, true)
	t.ok(seen and not bool(SetpieceLogic.after_away([], forts, seen, true)["victory"]), "mounted on a won game: the next away_report plays no victory")
	seen = SetpieceLogic.victory_seen(false, false)
	t.ok(not seen and bool(SetpieceLogic.after_away([], forts, seen, true)["victory"]), "mounted not won, the away time holds the win: it plays once")
	seen = SetpieceLogic.victory_seen(true, false)
	t.ok(not bool(SetpieceLogic.after_away([], forts, seen, true)["victory"]), "a second away_report plays nothing")
	var cs := FileAccess.get_file_as_string("%s/map_setpieces.gd" % MAP_DIR)
	var nm := cs.substr(cs.find("func note_mount("), cs.find("\n\n\n", cs.find("func note_mount(")) - cs.find("func note_mount("))
	t.ok(nm.contains("_won_at_mount") and nm.contains("hud.get(\"won\""), "the mount primes the seen state from the view")
	t.ok(cs.contains("SetpieceLogic.victory_seen(_won, _won_at_mount)"), "the away resync reads it")
	var src := FileAccess.get_file_as_string("%s/map_setpieces.gd" % MAP_DIR)
	var ev := src.substr(src.find("func on_event("), src.find("func _after_away(") - src.find("func on_event("))
	t.ok(ev.contains("\"away_report\":") and ev.contains("_after_away()"), "the away_report branch calls the resync")
	var a0 := src.find("func _after_away(")
	var aa := src.substr(a0, src.find("\n\n\n", a0) - a0)
	t.ok(aa.contains("SetpieceLogic.after_away(") and aa.contains("model.refresh(true)") and not aa.contains("_add(SetpieceLogic.FLIP") and not aa.contains("for "), "the resync re-reads the views and replays no flip set pieces")


## The callout cache key carries the chips; the cache keeps only what was drawn this frame.
func _callout_cache(t: TestUtil) -> void:
	var chips_a := HudLogic.rects_key([Rect2(10, 20, 40.2, 12)])
	var chips_b := HudLogic.rects_key([Rect2(10, 20, 52, 12)])
	var chips_a2 := HudLogic.rects_key([Rect2(10.2, 19.8, 40.4, 12.1)])
	var k := func(chips: Array): return SetpieceLogic.callout_key("x", 1.0, Vector2.ZERO, Vector2(800, 600), "near", 3, Vector2.ZERO, [], chips, [])
	t.ok(k.call(chips_a) != k.call(chips_b), "a different chip width is a different key")
	t.ok(k.call(chips_a) == k.call(chips_a2), "chips equal to the whole px are one key")
	t.ok(k.call(chips_a) == k.call(chips_a), "equal inputs, equal key")
	var kept := SetpieceLogic.prune_placed({"a|x": 1, "b|y": 2, "c|z": 3}, {"b|y": true})
	t.ok(kept == {"b|y": 2}, "the cache drops callouts not drawn this frame")
	t.ok(SetpieceLogic.prune_placed({"a|x": 1}, {}) == {}, "nothing drawn, nothing kept")
	var src := FileAccess.get_file_as_string("%s/map_setpieces.gd" % MAP_DIR)
	t.ok(src.contains("_chips_key(") and src.contains("prune_placed("), "the placement and _process use them")


func _clock(t: TestUtil) -> void:
	t.near(SetpieceLogic.beats(1000.0, 1000.0 + 1714.0, 1714.0), 1.0, 1e-9, "one tempo of wall clock is one beat")
	t.near(SetpieceLogic.beats(1000.0, 1000.0 + 1714.0, 1714.0, 4.0), 0.25, 1e-9, "the slow factor stretches the beat")
	t.ok(SetpieceLogic.beats(5000.0, 4000.0, 1714.0) == 0.0, "a set piece never runs backwards")
	t.ok(SetpieceLogic.beat_index(1713.0, 1714.0) == 0 and SetpieceLogic.beat_index(1714.0, 1714.0) == 1, "the beat number steps on each tempo")
	t.ok(SetpieceLogic.beat_index(1714.0 * 7.5, 1714.0) == 7, "the beat number counts beats")


func _valve(t: TestUtil, c: Dictionary) -> void:
	var from := {"work": 0.4, "war": 0.45, "flood": 0.15}
	var to := {"work": 0.1, "war": 0.7, "flood": 0.2}
	var d := float(c["valve_beats"])
	var w0 := NodeLogic.valve_widths(SetpieceLogic.valve_shares(from, to, 0.0, false))
	var wh := NodeLogic.valve_widths(SetpieceLogic.valve_shares(from, to, d * 0.5, false))
	var w1 := NodeLogic.valve_widths(SetpieceLogic.valve_shares(from, to, d, false))
	for k in ["work", "war", "flood"]:
		t.near(w0[k], NodeLogic.valve_widths(from)[k], 1e-6, "the %s stem starts at the old share's width" % k)
		t.near(wh[k], (NodeLogic.valve_widths(from)[k] + NodeLogic.valve_widths(to)[k]) * 0.5, 1e-6, "the %s stem is halfway at half a beat" % k)
		t.near(w1[k], NodeLogic.valve_widths(to)[k], 1e-6, "the %s stem lands on the new share at one beat" % k)
	var q := SetpieceLogic.valve_shares(from, to, d * 0.25, false)
	t.ok(absf(q["war"] - 0.45) < absf(0.7 - 0.45) * 0.25, "the swing eases in (a quarter beat is under a quarter of the way)")
	t.ok(SetpieceLogic.valve_shares(from, to, d * 3.0, false) == SetpieceLogic.valve_shares(from, to, d, false), "the swing holds its end")
	t.ok(SetpieceLogic.valve_bright(0.0, false) == 1.0 and SetpieceLogic.valve_bright(d, false) == 0.0, "the stems brighten for the beat")
	t.near(SetpieceLogic.valve_bright(d * 0.5, false), 0.5, 1e-9, "the brightening fades across the beat")
	t.ok(not SetpieceLogic.valve_done(d * 0.99) and SetpieceLogic.valve_done(d), "the swing is one beat long")
	t.ok(SetpieceLogic.valve_moved(from, to) and not SetpieceLogic.valve_moved(from, from.duplicate()), "valve_moved compares shares")
	t.ok(not SetpieceLogic.valve_moved(from, {"work": 0.401, "war": 0.449, "flood": 0.15}), "a change under valve_eps is not a move")


func _reink(t: TestUtil, c: Dictionary) -> void:
	var n := int(c["reink_segments"])
	var d := float(c["reink_beats"])
	t.near(d, 1.5, 1e-9, "the re-ink takes about 1.5 beats")
	t.near(SetpieceLogic.segment_arc(0, n).x, -PI * 0.5, 1e-6, "the first segment starts at 12 o'clock")
	var ok := true
	for i in n - 1:
		ok = ok and is_equal_approx(SetpieceLogic.segment_arc(i, n).y, SetpieceLogic.segment_arc(i + 1, n).x)
		ok = ok and SetpieceLogic.segment_arc(i + 1, n).x > SetpieceLogic.segment_arc(i, n).x
	t.ok(ok, "segments follow each other clockwise (angles grow with y down)")
	t.near(SetpieceLogic.segment_arc(n - 1, n).y, -PI * 0.5 + TAU, 1e-6, "the last segment closes the ring at 12 o'clock")
	t.ok(SetpieceLogic.reink_count(0.0, false) == 0, "nothing re-inked at the flip")
	var prev := 0
	var mono := true
	for k in 31:
		var cnt := SetpieceLogic.reink_count(d * k / 30.0, false)
		mono = mono and cnt >= prev
		prev = cnt
	t.ok(mono, "segments switch in sequence, never back")
	t.ok(SetpieceLogic.reink_count(d * 0.5, false) == n / 2, "half the ring at half the time")
	t.ok(SetpieceLogic.reink_count(d * 0.99, false) < n, "not done before 1.5 beats")
	t.ok(SetpieceLogic.reink_count(d, false) == n and SetpieceLogic.reink_done(d, false), "the ring is re-inked at 1.5 beats")
	t.ok(not SetpieceLogic.reink_done(d * 0.9, false), "the glyph waits for the ring")


## The map's line when it mounts after a dungeon: taken (the fort_flipped event, or a fort that is now
## held within its grace) or retreat (still Vei's, Relish alive), in the glossary's words.
func _return(t: TestUtil, c: Dictionary) -> void:
	t.suite("map_setpieces-return")
	var vei_fort := {"id": "ashgate", "name": "Ashgate", "held": false, "grace_s_left": 0.0}
	var held_fort := {"id": "ashgate", "name": "Ashgate", "held": true, "grace_s_left": 400.0}
	var alive := {"dead_s_left": 0.0, "state": "at_fort"}
	t.ok(SetpieceLogic.return_kind("ashgate", held_fort, true, alive) == SetpieceLogic.TAKEN, "the fort_flipped event: taken")
	t.ok(SetpieceLogic.return_kind("ashgate", held_fort, false, alive) == SetpieceLogic.TAKEN, "no event, but the fort is held in its grace and we came from it: taken")
	t.ok(SetpieceLogic.return_kind("ashgate", vei_fort, true, alive) == SetpieceLogic.TAKEN, "the event wins over a view that has not caught up")
	t.ok(SetpieceLogic.return_kind("ashgate", vei_fort, false, alive) == SetpieceLogic.RETREAT, "still Vei's after the raid: a retreat")
	t.ok(SetpieceLogic.return_kind("ashgate", vei_fort, false, {"dead_s_left": 30.0, "state": "dead"}) == "", "she died: not a retreat, you did not keep everything")
	t.ok(SetpieceLogic.return_kind("ashgate", {"id": "ashgate", "held": true, "grace_s_left": 0.0}, false, alive) == "", "an old held fort raided again with no flip: nothing taken, nothing to say")
	# the dive record: a held fort raided again is not taken, whatever its grace
	var was_held := {"fort": "ashgate", "held": true}
	var was_vei := {"fort": "ashgate", "held": false}
	t.ok(SetpieceLogic.return_kind("ashgate", held_fort, false, alive, was_held) == "", "held at the dive, held in grace now, no event: nothing taken, no line (not a retreat either: the fort is not Vei's)")
	t.ok(SetpieceLogic.return_kind("ashgate", held_fort, false, alive, was_vei) == SetpieceLogic.TAKEN, "Vei's at the dive, held in grace now, no event yet: taken (the late-event path)")
	t.ok(SetpieceLogic.return_kind("ashgate", held_fort, false, alive, {}) == SetpieceLogic.TAKEN, "no dive record: the grace fallback stands")
	t.ok(SetpieceLogic.return_kind("ashgate", held_fort, true, alive, was_held) == SetpieceLogic.TAKEN, "a real event is taken whatever the dive record says")
	t.ok(SetpieceLogic.return_kind("ashgate", held_fort, false, alive, {"fort": "bellmoor", "held": true}) == SetpieceLogic.TAKEN, "a dive record for another fort is ignored")
	var saved: Dictionary = SetpieceLogic._last_dive
	SetpieceLogic.note_dive("ashgate", true)
	t.ok(SetpieceLogic.return_kind("ashgate", held_fort, false, alive) == "", "the default record is the last dive")
	SetpieceLogic.note_dive("bellmoor", false)
	t.ok(SetpieceLogic._last_dive == {"fort": "bellmoor", "held": false} and SetpieceLogic.return_kind("ashgate", held_fort, false, alive) == SetpieceLogic.TAKEN, "only the last dive is kept")
	SetpieceLogic._last_dive = saved
	t.ok(SetpieceLogic.return_kind("covington", {}, false, alive) == "" and SetpieceLogic.return_kind("", {}, false, alive) == "", "back from town: no line")
	t.ok(SetpieceLogic.return_kind("vei", {}, true, alive) == "", "back from Vei: no line")
	t.ok(SetpieceLogic.return_text(SetpieceLogic.TAKEN, "Ashgate") == "Ashgate taken by you", "taken line")
	t.ok(SetpieceLogic.return_text(SetpieceLogic.RETREAT, "Ashgate") == "Ashgate stays Vei's: you kept all you found", "retreat line: both halves of the glossary's meaning (the fort stays Vei's, you keep what you found)")
	t.ok(int(c["callout_font_two"]) >= 14 and int(c["callout_font_two"]) <= int(c["callout_font"]), "the two-line form is set no smaller than 14 px, and no bigger than the one line")
	t.ok(SetpieceLogic.return_text("", "Ashgate") == "", "no kind, no line")
	t.ok(SetpieceLogic.KINDS.has(SetpieceLogic.RETREAT), "the retreat line is a set piece (debug trigger)")
	t.ok(float(c["callout_beats"]) > 0.0, "the line's time is configured")
	var src := FileAccess.get_file_as_string("%s/map_setpieces.gd" % MAP_DIR)
	t.ok(src.contains("SetpieceLogic.return_kind(") and src.contains("func note_return("), "MapSetpieces decides the return line through the pure function")
	var wm := FileAccess.get_file_as_string("res://scripts/map/world_map.gd")
	t.ok(wm.contains("setpieces.note_return("), "world_map hands the arrival's fort to the set pieces")
	t.ok(wm.contains("SetpieceLogic.note_dive(node_id,") and wm.find("SetpieceLogic.note_dive(") < wm.find("finished.emit({\"v\": 2, \"teleport_to\""), "world_map records the dive (held or not) before it leaves")


## Where a set-piece callout sits (SetpieceLogic.callout_place), in the zoomed frame: a fort at
## (500, 500) with an outer ring of 30, a 410 px line (two lines of 165 and 250 when split at ": ").
func _place(t: TestUtil, c: Dictionary) -> void:
	t.suite("map_setpieces-place")
	var fort := Vector2(500.0, 500.0)
	var base_y := 500.0 - 30.0 - float(c["callout_gap_px"])
	var w := {"one": 410.0, "a": 165.0, "b": 250.0}
	var none := {"rings": [], "circles": [], "rects": [], "soft": []}
	var at := SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], none)
	t.ok(str(at["form"]) == "one" and str(at["place"]) == "above" and float(at["slide"]) == 0.0 and at["pos"] == Vector2(500.0, base_y), "a clear neighbourhood: today's centred place, exactly")
	# a neighbour's ring under the centred place: the row slides to the first share that clears it
	var ring := {"rings": [Vector3(650.0, 440.0, 30.0)], "circles": [], "rects": [], "soft": []}
	at = SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], ring)
	t.ok(str(at["form"]) == "one" and str(at["place"]) == "above" and is_equal_approx(float(at["slide"]), -0.35), "a ring on the right: the one-line row slides left by 0.35 of its width, the first share that clears it")
	t.ok(float(at["hard"]) == 0.0 and is_equal_approx((at["pos"] as Vector2).x, 500.0 - 0.35 * 410.0) and (at["pos"] as Vector2).y == base_y, "the slid place is clear, on the same row")
	# rings both sides: no slide of the long line clears, the two lines centred above do
	var both := {"rings": [Vector3(330.0, 440.0, 30.0), Vector3(670.0, 440.0, 30.0)], "circles": [], "rects": [], "soft": []}
	at = SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], both)
	t.ok(str(at["form"]) == "two" and str(at["place"]) == "above" and float(at["slide"]) == 0.0 and float(at["hard"]) == 0.0, "rings both sides: the two-line form centred above")
	t.ok((at["pos"] as Vector2).y == base_y - float(c["callout_line_px"]) and (at["rects"] as Array).size() == 2, "the two lines stack up from today's baseline (the last line stays where the one line sat)")
	t.ok(SetpieceLogic.split_text("Old Sluice stays Vei's: you kept all you found") == ["Old Sluice stays Vei's:", "you kept all you found"], "the split keeps the colon on line one")
	t.ok(SetpieceLogic.split_text("Ashgate taken by you").is_empty(), "no ': ', no split")
	# a soft overlap is avoided when a hard-clear place without it exists
	var soft := {"rings": [], "circles": [], "rects": [], "soft": [Rect2(300.0, 440.0, 100.0, 30.0)]}
	at = SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], soft)
	t.ok(float(at["soft"]) == 0.0 and is_equal_approx(float(at["slide"]), 0.35), "a soft obstacle under the centred place: it slides to the first share clear of it")
	# the drift cap: the centred place is clear but sits far above the fort (a high base), too far to read as its own
	var high := SetpieceLogic.callout_place(fort, 30.0, base_y - 100.0, 16, w, [], none)
	t.ok(str(high["place"]) == "below" and float(high["hard"]) == 0.0, "a clear place beyond the drift cap is never chosen: the line goes under the fort")
	var saved: float = float(c["callout_drift_px"])
	c["callout_drift_px"] = 400.0
	high = SetpieceLogic.callout_place(fort, 30.0, base_y - 100.0, 16, w, [], none)
	c["callout_drift_px"] = saved
	t.ok(str(high["place"]) == "above" and float(high["slide"]) == 0.0, "with the cap lifted that same place is taken, so the cap is what refused it")
	# the span must cover the fort's x: a share of 0.9 would clear a ring on the left and the right but never reads as the fort's
	var cover := SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], both)
	var span_l := INF
	var span_r := -INF
	for r in cover["rects"]:
		span_l = minf(span_l, (r as Rect2).position.x)
		span_r = maxf(span_r, (r as Rect2).end.x)
	t.ok(span_l - float(c["callout_x_margin_px"]) <= fort.x and span_r + float(c["callout_x_margin_px"]) >= fort.x, "the chosen span still covers the fort's x")
	# a neighbour's ring nearer than the fort's own: never chosen, whatever else
	var near := {"rings": [Vector3(500.0, 440.0, 30.0)], "circles": [], "rects": [], "soft": []}
	at = SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], near)
	var worst := INF
	for r in at["rects"]:
		worst = minf(worst, SetpieceLogic.circle_gap(r, Vector3(500.0, 440.0, 30.0)))
	t.ok(str(at["place"]) == "below" or worst >= 0.0, "a ring nearer than the fort's own is never the choice")
	# nothing clear: the least hard overlap. A wall over every row above, and one just clipping the
	# row under the fort: the under row (one line, centred) overlaps least.
	var wall := {"rings": [], "circles": [], "rects": [Rect2(0.0, 300.0, 1000.0, 200.0), Rect2(0.0, 555.0, 1000.0, 70.0)], "soft": []}
	at = SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], wall)
	t.ok(float(at["hard"]) > 0.0 and str(at["place"]) == "below" and str(at["form"]) == "one" and float(at["slide"]) == 0.0, "nothing clear: the least hard overlap is taken")
	var wall_up := {"rings": [], "circles": [], "rects": [Rect2(0.0, 300.0, 1000.0, 200.0)], "soft": []}
	t.ok(float(SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], wall_up)["hard"]) == 0.0, "(and with only the upper wall, the under row is clear)")
	# the screen's bounds are hard: the free screen is y 100..800 here
	var bounds := Rect2(0.0, 100.0, 1000.0, 700.0)
	var low := SetpieceLogic.callout_place(Vector2(500.0, 780.0), 30.0, 740.0, 16, w, [], {"rings": [], "circles": [], "rects": [], "soft": [], "bounds": bounds})
	t.ok(str(low["place"]) == "above" and _inside(low, bounds), "a fort 20 px above the bottom inset never gets a place under it")
	var top := SetpieceLogic.callout_place(Vector2(500.0, 120.0), 30.0, 80.0, 16, w, [], {"rings": [], "circles": [], "rects": [], "soft": [], "bounds": bounds})
	t.ok(str(top["place"]) == "below" and _inside(top, bounds), "a fort near the top never gets a place crossing the top inset")
	var lost := SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], {"rings": [], "circles": [], "rects": [], "soft": [], "bounds": Rect2(0.0, 100.0, 50.0, 50.0)})
	t.ok(lost.has("rects") and str(lost["place"]) == "above", "no place on screen: the one with the least off-screen area (the above row, nearest the bounds)")
	var e := float(c["callout_edge_px"])
	t.ok(SetpieceLogic.screen_bounds(Vector2(1600.0, 900.0), Vector2(100.0, 50.0), 2.0, 62.0, 852.0) == Rect2(e - 800.0 + 200.0, 62.0 + e - 450.0 + 100.0, 1600.0 - e * 2.0, 852.0 - 62.0 - e * 2.0),"the bounds are the viewport less the edge, the top bar and the bottom bars, in the zoomed frame")
	# nothing reads as the fort's (drift cap of 1 px): the least hard overlap wins, not the first candidate
	var wall_above := {"rings": [], "circles": [], "rects": [Rect2(0.0, 400.0, 1000.0, 75.0)], "soft": []}
	var saved_cap: float = float(c["callout_drift_px"])
	c["callout_drift_px"] = 1.0
	at = SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], wall_above)
	c["callout_drift_px"] = saved_cap
	t.ok(float(at["hard"]) == 0.0 and str(at["place"]) == "below", "every place fails the ownership rule: the least hard overlap wins, not the centred first")
	# a line that is up does not hop: the previous choice stays while it is clear, and is re-chosen when blocked
	var prev := {"form": "one", "place": "above", "slide": 0.2}
	at = SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], none, prev)
	t.ok(is_equal_approx(float(at["slide"]), 0.2), "the last place is kept while it is still clear (not snapped back to centred)")
	at = SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], ring, prev)
	t.ok(is_equal_approx(float(at["slide"]), -0.35) and float(at["hard"]) == 0.0, "blocked (a ring now under it): it moves, to the first clear place")
	# beside the ring: only when the rows above and under are walled off; right first, left when the right is blocked too
	var rows_walled := [Rect2(0.0, 380.0, 1000.0, 100.0), Rect2(0.0, 525.0, 1000.0, 100.0)]
	at = SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], {"rings": [], "circles": [], "rects": rows_walled, "soft": []})
	t.ok(str(at["place"]) == "right" and str(at["form"]) == "one" and float(at["hard"]) == 0.0, "rows above and under walled off: beside the ring, on the right")
	at = SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], {"rings": [], "circles": [], "rects": rows_walled + [Rect2(545.0, 485.0, 400.0, 30.0)], "soft": []})
	t.ok(str(at["place"]) == "left" and float(at["hard"]) == 0.0 and (at["rects"][0] as Rect2).end.x < fort.x - 30.0, "the right blocked too: beside the ring, on the left")
	# the two-line form can be set smaller: its rects and line step follow the font
	var w14 := {"one": 410.0, "a": 150.0, "b": 200.0, "size_two": 14}
	at = SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w14, [], both)
	t.ok(str(at["form"]) == "two" and int(at["size"]) == 14 and is_equal_approx(float(at["line"]), float(c["callout_line_px"]) * 14.0 / 16.0), "the two-line form at 14 px steps its lines 14/16 of the line step")
	t.ok(int(SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], none)["size"]) == 16, "the one line keeps callout_font")
	# Covington's and Vei's discs and plates, world px to the zoomed frame
	var nh := SetpieceLogic.node_hard([{"pos": Vector2(100.0, 200.0), "r": 12.0, "rects": [Rect2(90.0, 210.0, 20.0, 10.0)]}], 0.5)
	t.ok(nh["circles"] == [Vector3(50.0, 100.0, 6.0)] and nh["rects"] == [Rect2(45.0, 105.0, 10.0, 5.0)], "node_hard scales the discs and plates by the zoom")
	# a line that is up stays on a soft overlap only while no fully clear place exists
	var soft_prev := {"rings": [], "circles": [], "rects": [], "soft": [Rect2(300.0, 440.0, 100.0, 30.0)]}
	at = SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], soft_prev, {"form": "one", "place": "above", "slide": 0.0})
	t.ok(float(at["soft"]) == 0.0 and is_equal_approx(float(at["slide"]), 0.35), "the held place is dropped for a fully clear one when a lane callout lands on it")
	var soft_all := {"rings": [], "circles": [], "rects": [], "soft": [Rect2(0.0, 0.0, 1000.0, 1000.0)]}
	at = SetpieceLogic.callout_place(fort, 30.0, base_y, 16, w, [], soft_all, {"form": "one", "place": "above", "slide": 0.2})
	t.ok(is_equal_approx(float(at["slide"]), 0.2), "with no fully clear place anywhere the held one stays (a line never hops for nothing)")
	_shot_geometry(t, c)


func _inside(place: Dictionary, bounds: Rect2) -> bool:
	for r in place["rects"]:
		if not bounds.encloses(r):
			return false
	return true


## The return shot (--fixture=day1 --teleport=old-sluice --finish-raid): a 1600 x 900 window, every fort at
## its world.json position, none held (day1 holds no fort, so no chip), Old Sluice's "your first dungeon"
## tag, Relish's token standing above it with her real halo. The camera is the one the return eases out to,
## read from a run of that command (a print in MapSetpieces._place_callout: zoom 0.57552540302277 centred on
## (986.6473, 657.0635), the top bar 62 px tall and the bottom bars from y 848). The retreat line must sit inside the inset screen, clear
## of every other fort's ring and every plate and the token, and read as Old Sluice's. The sweep re-frames
## Old Sluice at the same screen point at other zooms.
func _shot_geometry(t: TestUtil, c: Dictionary) -> void:
	var vp := Vector2(1600.0, 900.0)
	var shot_z := 0.57552540302277
	var shot_cam := Vector2(986.6473, 657.0635)
	var sluice := Vector2(1420.0, 1305.0)
	var screen_pt := (sluice - shot_cam) * shot_z + vp * 0.5
	var texts := {"retreat": SetpieceLogic.return_text(SetpieceLogic.RETREAT, "Old Sluice"),
		"taken": SetpieceLogic.return_text(SetpieceLogic.TAKEN, "Old Sluice"), "garrison": SetpieceLogic.garrison_text(36)}
	# the winner at each zoom: [form, place, slide, font, clean]. 0.4 is too crowded for any clean place (the lane
	# callouts and Covington close in): the least hard overlap is taken there, and the pin says so.
	var want := {
		shot_z: {"retreat": ["two", "right", 0.0, 14, true], "taken": ["one", "right", 0.0, 16, true], "garrison": ["one", "right", 0.0, 16, true]},
		0.4: {"retreat": ["one", "right", 0.0, 16, false], "taken": ["one", "right", 0.0, 16, false], "garrison": ["two", "right", 0.0, 14, false]},
		0.8: {"retreat": ["two", "above", -0.2, 14, true], "taken": ["one", "above", -0.2, 16, true], "garrison": ["one", "above", -0.2, 16, true]},
		1.2: {"retreat": ["two", "above", 0.0, 14, true], "taken": ["one", "above", 0.0, 16, true], "garrison": ["one", "above", 0.0, 16, true]}}
	var clean_zooms := 0
	for zoom in [shot_z, 0.4, 0.8, 1.2]:
		var z: float = zoom
		var cam_pos := shot_cam if z == shot_z else sluice - (screen_pt - vp * 0.5) / z
		var sc := _shot_scene(c, z, cam_pos, shot_z, shot_cam, vp)
		for kind in texts:
			var r := _shot_place(c, str(texts[kind]), sc)
			var at: Dictionary = r["at"]
			var w: Array = (want[zoom] as Dictionary)[kind]
			var tag := "%s at zoom %.3f" % [kind, z]
			t.ok(str(at["form"]) == w[0] and str(at["place"]) == w[1] and is_equal_approx(float(at["slide"]), float(w[2])) and int(at["size"]) == int(w[3]),
				"%s: the winner is the %s form %s the fort, slid %s, at %d px (got %s %s %s at %s)" % [tag, w[0], w[1], w[2], w[3], at["form"], at["place"], at["slide"], at["size"]])
			t.ok(bool(r["clean"]) == bool(w[4]), "%s: %s" % [tag, "no hard or soft overlap, inside the inset screen, reads as Old Sluice's" if w[4] else "no clean place at this zoom: the least hard overlap"])
			if kind == "retreat" and bool(r["clean"]):
				clean_zooms += 1
			if z == shot_z:  # the return screen itself: every part of it, spelled out
				t.ok(bool(r["inside"]), "%s: inside the inset screen" % tag)
				t.ok(int(r["hard_hits"]) == 0 and not bool(r["soft_hit"]), "%s: touches no fort's ring or plate, Relish's halo, Covington's glyph or labels, Vei's, nor a lane callout" % tag)
				t.ok(bool((r["reads"] as Dictionary)["ok"]), "%s: reads as Old Sluice's (%.0f px from its ring or plates, no other ring nearer)" % [tag, float((r["reads"] as Dictionary)["gap"])])
	t.ok(clean_zooms == 3, "the retreat line has a clean place at 3 of the 4 zooms, the shot's among them (got %d)" % clean_zooms)


## The shot's scene at zoom `z`, camera `cam_pos` (all in the zoomed frame, world x zoom): Old Sluice (`fp`,
## `ring_r`, its `own` plates and Relish's token), every other fort's ring and plates, Covington's and Vei's
## discs and plates at the day-1 valve (IdleLogic.node_obstacles: the chip layout's own), the two lane callouts
## the shot draws over the line's neighbourhood (REDIRECT and WAR, plates 28 px tall, as MapCallouts.drawn_rects
## gave them at the shot zoom; at other zooms kept at their world anchor, screen size), and the bounds.
func _shot_scene(c: Dictionary, z: float, cam_pos: Vector2, shot_z: float, shot_cam: Vector2, vp: Vector2) -> Dictionary:
	var world := TestUtil.load_json("res://configs/world.json")
	var forts: Array = world["forts"]
	var font := ThemeDB.fallback_font
	var n := NodeLogic.ncfg()
	var label := int(MapLogic.cfg()["font_label"])
	var own: Array = []
	var rects: Array = []
	var rings: Array = []
	var fp := Vector2.ZERO
	var ring_r := 0.0
	var pos_list: Array = []
	for f in forts:
		pos_list.append({"pos": f["pos"]})
	for f in forts:
		var p := MapModel.to_vec(f["pos"])
		var tier := int(f["tier"])
		var r := NodeLogic.outer_radius("fort", tier, 0.0) * z
		var tag_w := -1.0
		if str(f["id"]) == "old-sluice":
			tag_w = font.get_string_size("your first dungeon", HORIZONTAL_ALIGNMENT_LEFT, -1, NodeLogic.tag_size()).x
		var name_w := font.get_string_size(str(f["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, label).x
		var plates := SetpieceLogic.fort_plates(p, tier, name_w, tag_w, z)
		if str(f["id"]) == "old-sluice":
			fp = p * z
			ring_r = r
			own.append_array(plates)
		else:
			rings.append(Vector3(p.x * z, p.y * z, r))
			rects.append_array(plates)
	var halo_w := float(NodeLogic.relish_radii(z)["halo"])  # world px: max(halo r, min screen px / zoom)
	var halo := halo_w * z
	var tok := fp - Vector2(0.0, (ring_r / z + float(n["relish_gap_px"]) + halo_w) * z)  # MapNodes: above the fort's reach
	own.append(Rect2(tok - Vector2(halo, halo), Vector2(halo, halo) * 2.0))
	var text_w := {}
	for k in NodeLogic.node_names():
		text_w[k] = font.get_string_size(str(NodeLogic.node_names()[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, label).x
	var cov := MapModel.to_vec(world["covington"]["pos"])
	var vei := MapModel.to_vec(world["vei"]["pos"])
	var nodes := IdleLogic.node_obstacles(cov, vei, float(world["vei"]["radius"]), 0.0, {"work": 0.4, "war": 0.45, "flood": 0.15},
		NodeLogic.fort_centroid(pos_list), z, true, text_w)
	var hard := SetpieceLogic.node_hard(nodes, z)
	var soft: Array = []
	for s in [Rect2(524.6368, 696.5007, 274.0, 28.0), Rect2(939.8651, 704.0345, 243.0, 28.0)]:  # as MapCallouts drew them (zoomed frame at the shot zoom)
		soft.append(Rect2((s as Rect2).position / shot_z * z, (s as Rect2).size))
	return {"fp": fp, "ring_r": ring_r, "own": own, "rings": rings, "rects": rects + (hard["rects"] as Array), "tok": tok, "halo": halo,
		"circles": [Vector3(tok.x, tok.y, halo)] + (hard["circles"] as Array), "soft": soft,
		"bounds": SetpieceLogic.screen_bounds(vp, cam_pos, z, 62.0, 848.0), "z": z}


## `text`'s place in `sc` (callout_place with the widths measured as MapSetpieces does) and whether it is clean:
## {at, clean (inside the bounds, no hard or soft overlap, reads as Old Sluice's), inside, hard_hits, soft_hit, reads}.
func _shot_place(c: Dictionary, text: String, sc: Dictionary) -> Dictionary:
	var font := ThemeDB.fallback_font
	var size := int(c["callout_font"])
	var size_two := int(c.get("callout_font_two", size))
	var split := SetpieceLogic.split_text(text)
	var widths := {"one": font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x}
	if not split.is_empty():
		widths["a"] = font.get_string_size(str(split[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, size_two).x
		widths["b"] = font.get_string_size(str(split[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, size_two).x
		widths["size_two"] = size_two
	var fp: Vector2 = sc["fp"]
	var ring_r: float = sc["ring_r"]
	var tok: Vector2 = sc["tok"]
	var halo: float = sc["halo"]
	var gap := float(c["callout_gap_px"])
	var base_y := minf(fp.y - ring_r - gap, tok.y - halo - gap)
	var obs := {"rings": sc["rings"], "circles": sc["circles"], "rects": sc["rects"], "soft": sc["soft"], "bounds": sc["bounds"]}
	var at := SetpieceLogic.callout_place(fp, ring_r, base_y, size, widths, sc["own"], obs)
	var inside := true
	var hits := 0
	var soft_hit := false
	for r in at["rects"]:
		inside = inside and (sc["bounds"] as Rect2).encloses(r)
		for ring in sc["rings"]:
			if SetpieceLogic.circle_gap(r, ring) < 0.0:
				hits += 1
		for ci in sc["circles"]:
			if SetpieceLogic.circle_gap(r, ci) < 0.0:
				hits += 1
		for o in sc["rects"]:
			if (r as Rect2).intersects(o):
				hits += 1
		for o in sc["own"]:
			if (r as Rect2).intersects(o):
				hits += 1
		for o in sc["soft"]:
			soft_hit = soft_hit or (r as Rect2).intersects(o)
	var reads := SetpieceLogic._own_gap(at["rects"], fp, Vector3(fp.x, fp.y, ring_r), sc["own"], sc["rings"], str(at["place"]) in ["left", "right"])
	return {"at": at, "inside": inside, "hard_hits": hits, "soft_hit": soft_hit, "reads": reads,
		"clean": inside and hits == 0 and not soft_hit and bool(reads["ok"])}


## No displayed config string says flip or cleared: the player's word for winning a fort is taken
## (briefs/glossary.md). Config KEYS and event names keep their names; only values are scanned.
## EXEMPT lists value paths that are not player-facing (none today).
const EXEMPT: Array[String] = []


func _words(t: TestUtil) -> void:
	t.suite("map_setpieces-words")
	var re := RegEx.new()
	re.compile("(?i)\\b(flip|flips|flipped|flipping|clear|clears|cleared)\\b")
	var bad: Array = []
	_scan(TestUtil.load_json("res://configs/map_view.json"), "", re, bad)
	for b in bad:
		t.ok(false, "player-facing string uses flip/cleared: %s" % b)
	t.ok(bad.is_empty(), "no displayed map_view string says flip or cleared (%d)" % bad.size())
	t.ok(str(SetpieceLogic.cfg()["taken_fmt"]).contains("taken") and str(SetpieceLogic.cfg()["retreat_fmt"]).contains("Vei's"), "the new lines are config text")


func _scan(v: Variant, path: String, re: RegEx, bad: Array) -> void:
	if v is Dictionary:
		for k in v:
			_scan(v[k], "%s.%s" % [path, k], re, bad)
	elif v is Array:
		for i in v.size():
			_scan(v[i], "%s[%d]" % [path, i], re, bad)
	elif v is String and re.search(v) != null and not EXEMPT.has(path):
		bad.append("%s = \"%s\"" % [path, v])


func _first_flip(t: TestUtil) -> void:
	var forts := [{"id": "a", "flipped_count": 0}, {"id": "b", "flipped_count": 0}]
	t.ok(SetpieceLogic.first_flip("a", forts), "the views before the flip: no fort ever flipped")
	forts[0]["flipped_count"] = 1
	t.ok(SetpieceLogic.first_flip("a", forts), "the views after it: only this fort, once")
	t.ok(not SetpieceLogic.first_flip("b", forts), "another fort flipped before: not the first")
	forts[0]["flipped_count"] = 2
	t.ok(not SetpieceLogic.first_flip("a", forts), "a re-flip is not the first")
	t.ok(SetpieceLogic.first_flip("x", [{"id": "x"}]), "a missing count is 0")
	t.ok(SetpieceLogic.first_flip_text("Old Sluice") == "Old Sluice taken by you: your first fort", "the first fort's callout says taken")
	var c := SetpieceLogic.cfg()
	t.ok(not SetpieceLogic.ripple(0.3, 0.5, false).is_empty() and SetpieceLogic.ripple(0.3, float(c["ripple_beats"]), false).is_empty(), "the ripple runs for ripple_beats")
	t.ok(SetpieceLogic.ripple(0.0, 0.5, false)["alpha"] > SetpieceLogic.ripple(0.8, 0.5, false)["alpha"], "the ripple fades as it spreads on the beat")


func _tide(t: TestUtil, c: Dictionary) -> void:
	var vei := Vector2(1024.0, 130.0)
	var fort := Vector2(1420.0, 1305.0)
	var row := {"id": "living:vei:old-sluice", "kind": "living", "from": "vei", "to": "old-sluice"}
	var tr := SetpieceLogic.track(row, vei, fort, 120.0, 40.0, 40)
	var lo := float(tr["lo"])
	var hi := float(tr["hi"])
	t.ok(lo > 0.0 and hi > lo and hi < (tr["cum"] as PackedFloat32Array)[-1], "the band is trimmed off both nodes' rings")
	var d := float(c["tide_beats"])
	var b0 := SetpieceLogic.tide(0.0, false, lo, hi)
	t.ok(b0.y == lo, "the tide starts at Vei")
	var dist_prev := INF
	var toward := true
	for k in range(1, 10):
		var b := SetpieceLogic.tide(d * k / 10.0, false, lo, hi)
		var head := LaneStyle.point_at(tr["pts"], tr["cum"], b.y)
		toward = toward and head.distance_to(fort) < dist_prev
		dist_prev = head.distance_to(fort)
	t.ok(toward, "the head sweeps from Vei toward the fort over the beats")
	var bh := SetpieceLogic.tide(d * 0.5, false, lo, hi)
	t.near(bh.y, (lo + hi) * 0.5, 1e-3, "the head is halfway at half the sweep")
	t.near(bh.y - bh.x, float(c["tide_band_px"]), 1e-3, "the band is tide_band_px long")
	t.ok(SetpieceLogic.tide(d, false, lo, hi) == SetpieceLogic.NONE, "the tide is over after tide_beats (about 2)")
	var seg := SetpieceLogic.sub_polyline(tr["pts"], tr["cum"], bh.x, bh.y)
	t.ok(seg.size() >= 2 and seg[0].distance_to(LaneStyle.point_at(tr["pts"], tr["cum"], bh.x)) < 1e-3, "the band's points follow the lane's curve")
	t.near(MapLogic.curve_length(seg), bh.y - bh.x, 1.0, "the band's drawn length matches its arc range")
	var curve := MapLogic.lane_curve_for(row, vei, fort, 0.0)
	var mid := LaneStyle.point_at(tr["pts"], tr["cum"], (tr["cum"] as PackedFloat32Array)[-1] * 0.5)
	t.ok(mid.distance_to(vei.lerp(fort, 0.5)) > 10.0 and curve["c"] != vei.lerp(fort, 0.5), "the band rides the lane's bowed curve, not the chord")
	t.ok(SetpieceLogic.sub_polyline(tr["pts"], tr["cum"], 50.0, 50.0).is_empty(), "an empty range draws nothing")


func _garrison(t: TestUtil, c: Dictionary) -> void:
	var pb := float(c["garrison_pulse_beats"])
	var db := float(c["garrison_drain_beats"])
	var fb := float(c["garrison_flip_beats"])
	var g0 := SetpieceLogic.garrison(0.0, 12, false)
	t.ok(g0["pulse"] == 0.0 and g0["burst"] < 0.0 and (g0["chip"] as Dictionary).is_empty(), "the pulse leaves Covington first; the chip is untouched")
	t.near(SetpieceLogic.garrison(pb * 0.5, 12, false)["pulse"], 0.5, 1e-9, "the pulse is halfway along the WAR lane at half its time")
	var land := SetpieceLogic.garrison(pb, 12, false)
	t.ok(land["pulse"] < 0.0 and land["burst"] == 0.0, "the burst starts as the pulse lands at the fort")
	t.ok(str(land["chip"]["text"]) == "living 12" and str(land["chip"]["key"]) == "living", "the chip shows her counter-garrison when the pulse lands")
	var mid := SetpieceLogic.garrison(pb + db * 0.5, 12, false)
	t.ok(str(mid["chip"]["text"]) == "living 6", "it drains (%s)" % mid["chip"]["text"])
	var counts: Array = []
	for k in 11:
		var ch: Dictionary = SetpieceLogic.garrison(pb + db * k / 10.0 - 1e-6 * k / 10.0, 12, false)["chip"]
		if ch.has("text"):
			counts.append(int(str(ch["text"]).trim_prefix("living ")))
	t.ok(counts[0] == 12 and counts.all(func(x): return x >= 0), "the counter starts at N and never goes under 0")
	var sorted := counts.duplicate()
	sorted.sort()
	sorted.reverse()
	t.ok(counts == sorted, "the counter only goes down")
	var zero := SetpieceLogic.garrison(pb + db, 12, false)
	t.ok(str(zero["chip"]["text"]) == "living 0" and is_equal_approx(float(zero["chip"]["squash"]), 1.0), "it reaches 0, then the flip starts")
	var half := SetpieceLogic.garrison(pb + db + fb * 0.5 - 1e-6, 12, false)
	t.ok(float(half["chip"]["squash"]) < 0.01, "the flip squashes line two to nothing at its middle")
	var after := SetpieceLogic.garrison(pb + db + fb * 0.75, 12, false)
	t.ok(bool(after["chip"].get("live", false)) and absf(float(after["chip"]["squash"]) - 0.5) < 1e-6, "it opens again on the live margin word")
	t.ok((SetpieceLogic.garrison(pb + db + fb, 12, false)["chip"] as Dictionary).is_empty(), "then the chip is the live chip")
	t.ok(SetpieceLogic.garrison(pb + 0.1, 12, false)["callout"] == 1.0 and SetpieceLogic.garrison(0.5 * pb, 12, false)["callout"] == 0.0, "the callout shows from the landing")
	var end := maxf(pb + float(c["garrison_burst_beats"]), maxf(pb + db + fb, pb + float(c["garrison_callout_beats"])))
	t.ok(not SetpieceLogic.garrison(end - 0.01, 12, false)["done"] and SetpieceLogic.garrison(end, 12, false)["done"], "it ends when the callout, burst and flip are all over")
	t.ok(SetpieceLogic.drain_count(12, 0.0) == 12 and SetpieceLogic.drain_count(12, 1.0) == 0 and SetpieceLogic.drain_count(12, 0.99) == 1, "the drain hits 0 only at its end")


func _sources_of_garrison(t: TestUtil, c: Dictionary) -> void:
	var real := SetpieceLogic.garrison_from_event({"type": "counter_garrison_cleared", "fort_id": "ashgate", "killed_mass": 23.6})
	t.ok(real == {"fort_id": "ashgate", "n": 24}, "the real event gives its fort and N")
	t.ok(SetpieceLogic.garrison_text(int(real["n"])) == str(c["garrison_fmt"]) % MapLogic.fmt_mass(24), "the real event's callout shows N")
	t.ok(SetpieceLogic.garrison_from_event({"type": "loot_banked", "fort_id": "ashgate"}).is_empty(), "another event is not the source")
	# the real event drives the set piece: the event's N is the chip's starting count
	var pb := float(c["garrison_pulse_beats"])
	var first := SetpieceLogic.garrison(pb + 0.01, int(real["n"]), false)
	t.ok(str(first["chip"]["text"]) == str(c["garrison_counter_fmt"]) % MapLogic.fmt_mass(24), "the chip counts down from the event's N")
	var src := FileAccess.get_file_as_string("%s/map_setpieces.gd" % MAP_DIR)
	t.ok(src.contains("\"counter_garrison_cleared\":") and src.contains("SetpieceLogic.garrison_from_event(ev)") and src.contains("_add(SetpieceLogic.GARRISON"), "MapSetpieces starts the garrison piece from the real event")
	t.ok(not src.contains("stand_in") and not src.contains("_standin"), "and no stand-in path is left")


## Where the build line sits at Covington (SetpieceLogic.build_place), in the zoomed frame: Covington at
## (500, 500), outer ring 30, a 220 px line on a 34 px plate; its default place is the plate's bottom
## build_gap_px over the ring.
func _build_place(t: TestUtil, c: Dictionary) -> void:
	t.suite("map_setpieces-build-place")
	var cov := Vector2(500.0, 500.0)
	var bottom := 500.0 - 30.0 - float(c["build_gap_px"])
	var none := {"rings": [], "circles": [], "rects": [], "soft": []}
	var home := SetpieceLogic.build_place(cov, 30.0, bottom, 220.0, 34.0, [], none)
	var plate: Rect2 = home["plate"]
	t.ok(is_equal_approx(plate.size.x, 220.0 + float(c["build_pad_px"]) * 2.0) and is_equal_approx(plate.size.y, 34.0), "the plate is the text plus build_pad_px each side, at the height given")
	t.ok(is_equal_approx(plate.get_center().x, 500.0) and is_equal_approx(plate.end.y, bottom) and (home["pos"] as Vector2).is_equal_approx(Vector2(500.0, bottom)), "nothing near: centred above the rings, bottom build_gap_px clear, as it always sat")
	# (1) a fort's name plate under the default place: the line moves off it
	var name_plate := Rect2(430.0, 430.0, 140.0, 22.0)
	var moved := SetpieceLogic.build_place(cov, 30.0, bottom, 220.0, 34.0, [], {"rings": [], "circles": [], "rects": [name_plate], "soft": []})
	t.ok(plate.intersects(name_plate), "(the default place does cover that plate)")
	t.ok(not (moved["plate"] as Rect2).intersects(name_plate) and float((moved["at"] as Dictionary)["hard"]) == 0.0, "(1) it is moved so it clears the fort's name plate: %s" % str(moved["plate"]))
	t.ok(not (moved["plate"] as Rect2).is_equal_approx(plate), "(1) and is not the default place")
	# (2) Covington's own discs and plates are its own, not hard: Vei's stay hard
	var nodes := [{"pos": Vector2(500.0, 500.0), "r": 40.0, "rects": [Rect2(450.0, 535.0, 100.0, 20.0)]},
		{"pos": Vector2(900.0, 100.0), "r": 60.0, "rects": [Rect2(880.0, 20.0, 80.0, 18.0)]}]
	var sp := SetpieceLogic.build_obstacles(nodes, 2.0)
	t.ok(sp["own"] == [Rect2(900.0, 1070.0, 200.0, 40.0)] and (sp["circles"] as Array) == [Vector3(1800.0, 200.0, 120.0)] and (sp["rects"] as Array) == [Rect2(1760.0, 40.0, 160.0, 36.0)],
		"Covington's plates are its own (zoomed), Vei's disc and plates stay hard: %s" % str(sp))
	var own_only := SetpieceLogic.build_place(cov, 30.0, bottom, 220.0, 34.0, [Rect2(450.0, 535.0, 100.0, 20.0)], none)
	t.ok((own_only["plate"] as Rect2).is_equal_approx(plate), "(2) Covington's own plates do not push it off its default place")
	# (3) a fort callout placed first is hard to it
	var callout := Rect2(440.0, 415.0, 120.0, 40.0)
	var past := SetpieceLogic.build_place(cov, 30.0, bottom, 220.0, 34.0, [], {"rings": [], "circles": [], "rects": [callout], "soft": []})
	t.ok(plate.intersects(callout) and not (past["plate"] as Rect2).intersects(callout) and float((past["at"] as Dictionary)["hard"]) == 0.0, "(3) a fort callout fed as hard is avoided: %s" % str(past["plate"]))
	# the sum of the runs' widths, in the faces the layer draws them in
	var runs := SetpieceLogic.build_spans("Bone Mill built · BODIES −0.4/s")
	var m := SetpieceLogic.build_metrics(runs, 16)
	var sum := 0.0
	for w in m["widths"]:
		sum += float(w)
	t.ok(runs.size() >= 2 and is_equal_approx(float(m["total"]), sum + float(m["space"]) * (runs.size() - 1)) and float(m["h"]) > 0.0 and float(m["asc"]) > 0.0, "the line's width is its runs' widths and the spaces between: %s" % str(m["total"]))


## A finished build's callout at Covington: the projection store (by lot and level, only ever
## overwritten by a real value), the level-rise diff, the away-report skip, the text, its time.
func _builds(t: TestUtil, c: Dictionary) -> void:
	t.suite("map_setpieces-builds")
	var names := {"inn": "Inn", "bakery": "Bakery", "bone_mill": "Bone Mill"}
	var eps := float(c["build_eps"])
	t.ok(SetpieceLogic.proj_key("lot-13", 2) == "lot-13:2", "a projection is keyed by lot and level")
	# the store: queued new builds from the catalog, built lots' upgrades from view_town, never overwritten by {}
	var store := {}
	var town := {"queue": [{"building_id": "inn", "lot_id": "lot-13", "upgrade": false, "level": 1},
			{"building_id": "house", "lot_id": "lot-05", "upgrade": true, "level": 2}],
		"buildings": [{"lot_id": "lot-05", "building_id": "house", "level": 1, "state": "active", "upgrade_projected": {"gold": 0.4, "bodies": -0.1}},
			{"lot_id": "lot-06", "building_id": "well", "level": 1, "state": "active", "upgrade_projected": {}},
			{"lot_id": "lot-14", "building_id": "bakery", "level": 0, "state": "constructing", "upgrade_projected": {}}]}
	var pend := SetpieceLogic.pending_new(town)
	t.ok(pend.size() == 2 and pend[0] == {"lot_id": "lot-13", "building_id": "inn", "level": 1} and pend[1] == {"lot_id": "lot-14", "building_id": "bakery", "level": 1},
		"pending new builds: the queued ones and a first build under construction, at level 1 (an upgrade reads view_town)")
	t.ok(SetpieceLogic.has_pending(town) and not SetpieceLogic.has_pending({"queue": [], "buildings": [{"lot_id": "lot-05", "building_id": "house", "level": 1, "state": "active"}]}),
		"a catalog read is wanted only while a build is queued or under construction")
	SetpieceLogic.note_upgrades(store, town["buildings"])
	t.ok(SetpieceLogic.projection_for(store, "lot-05", "house", 2) == {"gold": 0.4, "bodies": -0.1}, "an upgrade's projection is stored at the lot's next level")
	t.ok(SetpieceLogic.projection_for(store, "lot-06", "well", 2).is_empty(), "an empty upgrade_projected stores nothing")
	var rows := [{"building_id": "inn", "projected": {"mint": 0.8}}, {"building_id": "bakery", "projected": {}}, {"building_id": "house", "projected": {"gold": 9.0}}]
	SetpieceLogic.note_catalog(store, pend, rows)
	t.ok(SetpieceLogic.projection_for(store, "lot-13", "inn", 1) == {"mint": 0.8}, "a new build's projection comes from its catalog row, at lot:1")
	t.ok(SetpieceLogic.projection_for(store, "lot-14", "bakery", 1).is_empty(), "a still-cold (empty) catalog row stores nothing")
	t.ok(SetpieceLogic.projection_for(store, "lot-13", "bakery", 1).is_empty(), "a projection of another building on that lot is not used")
	# the last good value survives: the build starts (the lot reads {} while constructing) and the catalog goes cold
	var constructing := [{"lot_id": "lot-05", "building_id": "house", "level": 1, "state": "constructing", "upgrade_projected": {}}]
	SetpieceLogic.note_upgrades(store, constructing)
	SetpieceLogic.note_catalog(store, pend, [{"building_id": "inn", "projected": {}}])
	t.ok(SetpieceLogic.projection_for(store, "lot-05", "house", 2) == {"gold": 0.4, "bodies": -0.1}, "an upgrade's last projection stays while it constructs")
	t.ok(SetpieceLogic.projection_for(store, "lot-13", "inn", 1) == {"mint": 0.8}, "and a new build's when its row goes cold")
	SetpieceLogic.note_catalog(store, pend, [{"building_id": "inn", "projected": {"mint": 1.1}}])
	t.ok(SetpieceLogic.projection_for(store, "lot-13", "inn", 1) == {"mint": 1.1}, "a newer real value replaces the old one")
	t.ok(SetpieceLogic.projection_for(store, "lot-05", "house", 3).is_empty(), "the projection moves on to the next level: level 3 has none")

	# the level-rise diff
	var snap := SetpieceLogic.lot_levels([{"lot_id": "lot-05", "building_id": "house", "level": 1}, {"lot_id": "lot-06", "building_id": "well", "level": 1}])
	t.ok(snap == {"lot-05": {"building_id": "house", "level": 1}, "lot-06": {"building_id": "well", "level": 1}}, "built levels by lot")
	var now := SetpieceLogic.lot_levels([{"lot_id": "lot-05", "building_id": "house", "level": 2}, {"lot_id": "lot-06", "building_id": "well", "level": 1},
		{"lot_id": "lot-13", "building_id": "inn", "level": 1}, {"lot_id": "lot-14", "building_id": "bakery", "level": 0}])
	var rise := SetpieceLogic.rises(snap, now)
	t.ok(rise == [{"lot_id": "lot-05", "building_id": "house", "level": 2}, {"lot_id": "lot-13", "building_id": "inn", "level": 1}], "an upgrade and a new building rose; a level-0 first build and an unchanged lot did not")
	t.ok(SetpieceLogic.rises(now, now).is_empty(), "nothing rose, nothing announced")
	var swapped := SetpieceLogic.rises(snap, SetpieceLogic.lot_levels([{"lot_id": "lot-06", "building_id": "bakery", "level": 1}]))
	t.ok(swapped == [{"lot_id": "lot-06", "building_id": "bakery", "level": 1}], "another building on the lot at the same level is a rise")
	t.ok(SetpieceLogic.mount_builds(rise, false).size() == 2, "on mount the diff is announced")
	t.ok(SetpieceLogic.mount_builds(rise, true).is_empty(), "but not when the away panel opens for this return: its report already lists the builds")
	t.ok(AwayLogic.should_open(null, false, {"shown": true, "rev": 1}, -1) and not AwayLogic.should_open(null, false, {"shown": false}, -1), "the skip's test is AwayLogic.should_open: the report is shown")
	t.ok(SetpieceLogic.add_build([], {"lot_id": "lot-13", "building_id": "inn", "level": 1}).size() == 1
		and SetpieceLogic.add_build([{"lot_id": "lot-13", "building_id": "inn", "level": 1}], {"lot_id": "lot-13", "building_id": "inn", "level": 1}).size() == 1,
		"the same lot and level (an event the router re-emitted after the mount's diff) joins the callout once")

	# the text
	var inn := {"lot_id": "lot-13", "building_id": "inn", "level": 1}
	var bakery := {"lot_id": "lot-14", "building_id": "bakery", "level": 1}
	var s2 := {}
	SetpieceLogic.note_catalog(s2, [{"lot_id": "lot-13", "building_id": "inn", "level": 1}, {"lot_id": "lot-14", "building_id": "bakery", "level": 1}],
		[{"building_id": "inn", "projected": {"mint": 0.8, "gold": -0.05, "corpses": 5.0}}, {"building_id": "bakery", "projected": {"mint": 0.3, "gold": 0.1}}])
	t.ok(SetpieceLogic.build_text([inn], s2, names) == "Inn built · MINT +0.8/s", "one build: its name and its biggest rate, signed: %s" % SetpieceLogic.build_text([inn], s2, names))
	t.ok(SetpieceLogic.build_text([inn, bakery], s2, names) == "2 builds: Inn · Bakery · MINT +1.1/s", "several: the names, the rates summed: %s" % SetpieceLogic.build_text([inn, bakery], s2, names))
	var s3 := {}
	SetpieceLogic.note_catalog(s3, [{"lot_id": "lot-13", "building_id": "inn", "level": 1}], [{"building_id": "inn", "projected": {"mint": 0.1, "gold": -0.6, "backlog": -50.0}}])
	t.ok(SetpieceLogic.build_text([inn], s3, names) == "Inn built · GOLD −0.6/s", "a fall is signed with the minus, and a stream with no label (backlog) never leads")
	t.ok(SetpieceLogic.build_text([inn], {}, names) == "Inn built", "no recorded projection: just the build")
	t.ok(SetpieceLogic.build_text([inn, bakery], {}, names) == "2 builds: Inn · Bakery", "several with none recorded: just the list")
	var s4 := {}
	SetpieceLogic.note_catalog(s4, [{"lot_id": "lot-13", "building_id": "inn", "level": 1}], [{"building_id": "inn", "projected": {"mint": eps * 0.5, "gold": -eps * 0.9}}])
	t.ok(SetpieceLogic.build_text([inn], s4, names) == "Inn built", "every |delta| under the eps: just the build")
	t.ok(SetpieceLogic.build_text([{"lot_id": "lot-20", "building_id": "bone_mill", "level": 1}], {}, names) == "Bone Mill built", "a name with a space")
	t.ok(SetpieceLogic.build_text([{"lot_id": "lot-20", "building_id": "stables", "level": 1}], {}, names) == "Stables built", "an id with no label is capitalised")
	var bid := SetpieceLogic.biggest({"gold": -0.3, "mint": 0.3})
	t.ok(str(bid["id"]) == "mint", "a tie goes to the first stream in the HUD's order")
	t.ok((c["build_rate_ids"] as Array).all(func(id): return HudLogic.LABELS.has(id)), "the streams a callout can name are the HUD's own (HudLogic.LABELS)")
	# the runs: rates oblique, the rest labels
	var spans := SetpieceLogic.build_spans("Inn built · MINT +0.8/s")
	t.ok(spans.size() == 2 and spans[0]["kind"] == "label" and spans[1] == {"text": "+0.8/s", "kind": "rate"}, "the signed rate is its own run (the rate face): %s" % str(spans))

	# the time
	var d := float(c["build_beats"])
	t.ok(SetpieceLogic.build_alpha(0.0, false) == 1.0 and SetpieceLogic.build_alpha(d * 0.5, false) == 1.0, "the plate holds full for most of its time")
	t.ok(SetpieceLogic.build_alpha(d - float(c["callout_fade_beats"]) * 0.5, false) < 1.0 and SetpieceLogic.build_alpha(d, false) == 0.0, "then fades out by build_beats")
	t.ok(SetpieceLogic.build_alpha(d - 0.01, true) == 1.0 and SetpieceLogic.build_alpha(d, true) == 0.0, "reduced motion: it appears and disappears, no fade")
	t.ok(SetpieceLogic.build_done(d) and not SetpieceLogic.build_done(d * 0.99), "it lasts build_beats")

	# 4.5:1 over its plate, the way the node labels are tested: the brightest palette key behind it at worst
	var bright_key := ""
	for k in Palette.keys():
		if bright_key == "" or MapLogic.luminance(Palette.c(k)) > MapLogic.luminance(Palette.c(bright_key)):
			bright_key = k
	var plate := NodeLogic.label_plate_color()
	for under_key in [bright_key, "undead", "living", "vei"]:
		var under := Palette.c("ground").lerp(Palette.c(under_key), 1.0 - plate.a)
		for key in ["build_label_key", "build_rate_key"]:
			var r := MapLogic.contrast_ratio(Palette.c(str(c[key])), under)
			t.ok(r >= 4.5, "%s (%s) on its plate over %s: %.2f:1 (>= 4.5)" % [key, c[key], under_key, r])
	t.ok(int(c["build_font"]) >= 12, "the callout's type is at least 12 px")
	var src := FileAccess.get_file_as_string("%s/map_setpieces.gd" % MAP_DIR)
	t.ok(src.contains("\"building_done\":") and src.contains("SetpieceLogic.add_build(") and src.contains("model.mount_rises"), "MapSetpieces takes the live event and the mount's diff through one path")
	var lay := FileAccess.get_file_as_string("%s/map_setpiece_layer.gd" % MAP_DIR)
	t.ok(lay.contains("\"runs\"") and lay.contains("MapType.rate_font()"), "the layer draws a runs plate with the rate face")


func _victory(t: TestUtil, c: Dictionary) -> void:
	var d := float(c["victory_run_beats"])
	t.ok(SetpieceLogic.victory_phase(0.0, false) == SetpieceLogic.RUN, "victory runs first")
	t.ok(SetpieceLogic.victory_phase(d * 0.99, false) == SetpieceLogic.RUN, "for victory_run_beats (about 2)")
	t.ok(SetpieceLogic.victory_phase(d, false) == SetpieceLogic.STOP and SetpieceLogic.victory_phase(d * 10.0, false) == SetpieceLogic.STOP, "then stops, and stays stopped")
	t.ok(SetpieceLogic.victory_u(-1.0) == float(c["victory_u_floor"]) and SetpieceLogic.victory_u(0.9) == 0.9, "a dark lane lights at the floor; a bright one keeps its u")
	# once per game: the decision, the settle path's end state, and the wiring (source text: the scene scripts name autoloads)
	t.ok(SetpieceLogic.victory_start(true, false) == "" and SetpieceLogic.victory_start(true, true) == "", "victory: a map that already played or settled it ignores a second start")
	t.ok(SetpieceLogic.victory_start(false, false) == SetpieceLogic.VICTORY_PLAY, "victory: the first time in a game it plays")
	t.ok(SetpieceLogic.victory_start(false, true) == SetpieceLogic.VICTORY_SETTLE, "victory: seen in this game, a later mount settles")
	t.ok(SetpieceLogic.victory_phase(0.0, true) == SetpieceLogic.STOP, "victory: the settle path's end state is STOP at once")
	var sp := FileAccess.get_file_as_string("%s/map_setpieces.gd" % MAP_DIR)
	var s0 := sp.find("func _start(")
	var st := sp.substr(s0, sp.find("\n\n\n", s0) - s0)
	t.ok(st.contains("SetpieceLogic.victory_start(_won, seen.has(MapSeen.VICTORY))") and st.contains("seen.mark(MapSeen.VICTORY)") and st.contains("p[\"settle\"]"), "_start decides from the seen flag, marks it when the victory plays, and records the settle")
	var p0 := sp.find("func _process(")
	var pr := sp.substr(p0, sp.find("\n\n\n", p0) - p0)
	t.ok(pr.contains("_victory_tick(t, rm or bool(p.get(\"settle\", false)))"), "_process settles a settled victory like reduced motion")
	t.ok(sp.contains("var seen: MapSeen"), "the set pieces hold the game's seen flags")
	var wm := FileAccess.get_file_as_string("%s/world_map.gd" % MAP_DIR)
	var w0 := wm.find("setpieces.seen = seen")
	t.ok(w0 >= 0 and w0 < wm.find("add_child(setpieces)"), "the world map hands the seen flags over before the set pieces enter the tree")


func _reduced(t: TestUtil, c: Dictionary) -> void:
	var from := {"work": 0.4, "war": 0.45, "flood": 0.15}
	var to := {"work": 0.1, "war": 0.7, "flood": 0.2}
	t.ok(SetpieceLogic.valve_shares(from, to, 0.0, true) == SetpieceLogic.valve_shares(from, to, 9.0, false), "reduced: the stems snap to the new shares")
	t.ok(SetpieceLogic.valve_bright(0.0, true) == 1.0 and SetpieceLogic.valve_bright(0.5, true) == 1.0 and SetpieceLogic.valve_bright(float(c["valve_beats"]), true) == 0.0, "reduced: the brightening is a step, no fade")
	t.ok(SetpieceLogic.reink_count(0.0, true) == int(c["reink_segments"]) and SetpieceLogic.reink_done(0.0, true), "reduced: the ring re-inks at once")
	t.ok(SetpieceLogic.ripple(0.2, 0.1, true).is_empty(), "reduced: no ripple")
	t.ok(SetpieceLogic.callout_alpha(0.0, 3.0, true) == 1.0 and SetpieceLogic.callout_alpha(2.99, 3.0, true) == 1.0, "reduced: the callout still shows, without a fade")
	t.ok(SetpieceLogic.tide(0.0, true, 10.0, 500.0) == Vector2(10.0, 500.0) and SetpieceLogic.tide(float(c["tide_beats"]) * 0.9, true, 10.0, 500.0) == Vector2(10.0, 500.0), "reduced: a still band along the whole lane")
	t.ok(SetpieceLogic.tide(float(c["tide_beats"]), true, 10.0, 500.0) == SetpieceLogic.NONE, "reduced: the band lasts tide_beats")
	var g := SetpieceLogic.garrison(0.0, 12, true)
	t.ok(g["pulse"] < 0.0 and g["burst"] < 0.0 and g["ring"] and (g["chip"] as Dictionary).is_empty() and g["callout"] == 1.0, "reduced: the garrison's end state (live word, callout, still ring)")
	t.ok(SetpieceLogic.garrison(float(c["garrison_callout_beats"]), 12, true)["done"], "reduced: the garrison callout still times out")
	t.ok(SetpieceLogic.victory_phase(0.0, true) == SetpieceLogic.STOP, "reduced: victory is frozen green at once")


func _debug(t: TestUtil, c: Dictionary) -> void:
	t.ok(SetpieceLogic.debug_args(["--setpiece=first_flip"], true) == {"kind": "first_flip", "slow": 1.0}, "--setpiece names a set piece")
	t.ok(SetpieceLogic.debug_args(["--setpiece=flip", "--setpiece-slow=4"], true) == {"kind": "flip", "slow": 4.0}, "--setpiece-slow stretches it")
	t.ok(SetpieceLogic.debug_args(["--setpiece=flip"], false)["kind"] == "", "the trigger is debug-only")
	t.ok(SetpieceLogic.debug_args(["--setpiece=nope", "--setpiece-slow=0"], true) == {"kind": "", "slow": 1.0}, "an unknown kind or a zero factor is ignored")
	for k in SetpieceLogic.KINDS:
		t.ok(SetpieceLogic.debug_args(["--setpiece=" + k], true)["kind"] == k, "--setpiece=%s parses" % k)
	var forts := [{"id": "a", "held": false}, {"id": "b", "held": true}, {"id": "old-sluice", "held": true}]
	t.ok(SetpieceLogic.demo_target(forts, "old-sluice") == "old-sluice", "the preferred demo fort")
	t.ok(SetpieceLogic.demo_target(forts, "gone") == "b", "else the first held fort")
	t.ok(SetpieceLogic.demo_target([{"id": "a"}], "gone") == "a" and SetpieceLogic.demo_target([], "x") == "", "else the first fort, or none")
	var v: Array = c["debug_valve"]
	var dv := SetpieceLogic.demo_valve({"work": 0.4, "war": 0.45, "flood": 0.15})
	t.ok(is_equal_approx(dv["war"], float(v[1])), "the debug swing goes to debug_valve")
	var again := SetpieceLogic.demo_valve(dv)
	t.ok(SetpieceLogic.valve_moved(again, dv), "and somewhere else when the valve already is debug_valve")


## The set-piece scripts animate on Pulse (no sin(), no Time.get_ticks, no literal tempo or hops,
## no colour literals); the controller hears events only through Game.game_event.
func _sources(t: TestUtil) -> void:
	var sp := FileAccess.get_file_as_string("%s/map_setpieces.gd" % MAP_DIR)
	var vt := sp.substr(sp.find("func _valve_tick("), sp.find("# --- the flip") - sp.find("func _valve_tick("))
	t.ok(vt.contains("model.rev == _valve_rev") and vt.find("model.rev == _valve_rev") < vt.find("_target()"), "idle valve ticks do nothing until the model rev changes")
	var banned := RegEx.new()
	banned.compile("\\bsin\\(|Time\\.get_ticks|1\\.714|\\b1714\\b|Pulse\\.wave\\([0-9]|Pulse\\.phase\\([0-9]|Color\\s*\\(\\s*[\"\\d]")
	var lines := 0
	for f in FILES:
		var path := "%s/%s" % [MAP_DIR, f]
		t.ok(FileAccess.file_exists(path), "%s exists" % f)
		var n := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			lines += 1
			if banned.search(LINT.strip_comment(line)) != null and not line.contains("# lint-ok: bench"):
				t.ok(false, "%s:%d: %s" % [f, n, line.strip_edges()])
	t.ok(lines > 200, "scanned %d lines of set-piece scripts" % lines)
	var ctl := FileAccess.get_file_as_string("%s/map_setpieces.gd" % MAP_DIR)
	t.ok(ctl.contains("Game.game_event.connect(") and not ctl.contains("Game.victory") and not ctl.contains("drain_events"), "the set pieces hear events through Game.game_event only")
	t.ok(ctl.contains("Pulse.tempo_ms") and ctl.contains("Pulse.reduced_motion"), "they time on Pulse's tempo and honour reduced motion")
	for kind in ["\"pulse\"", "\"whoosh\"", "\"horn\"", "\"flip\""]:
		t.ok(ctl.contains("play(%s" % kind), "the map plays %s" % kind)
