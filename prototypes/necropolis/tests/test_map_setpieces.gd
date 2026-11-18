extends RefCounted
## Tests for setpiece_logic.gd (the map's set pieces on the tempo): the valve swing's widths over
## its beat, the re-ink's segment order and completion, the tithe tide's band from Vei to the
## fort, victory's run-then-stop, the garrison timeline and its two sources (the real event with
## N, the stand-in without), first-flip detection, reduced motion going straight to each end
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
	_tide(t, c)
	_garrison(t, c)
	_sources_of_garrison(t, c)
	_victory(t, c)
	_reduced(t, c)
	_debug(t, c)
	_sources(t)
	return t.failures


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


func _first_flip(t: TestUtil) -> void:
	var forts := [{"id": "a", "flipped_count": 0}, {"id": "b", "flipped_count": 0}]
	t.ok(SetpieceLogic.first_flip("a", forts), "the views before the flip: no fort ever flipped")
	forts[0]["flipped_count"] = 1
	t.ok(SetpieceLogic.first_flip("a", forts), "the views after it: only this fort, once")
	t.ok(not SetpieceLogic.first_flip("b", forts), "another fort flipped before: not the first")
	forts[0]["flipped_count"] = 2
	t.ok(not SetpieceLogic.first_flip("a", forts), "a re-flip is not the first")
	t.ok(SetpieceLogic.first_flip("x", [{"id": "x"}]), "a missing count is 0")
	t.ok(SetpieceLogic.first_flip_text("Old Sluice") == "First flip: Old Sluice is yours", "the first flip's callout")
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
	var si := SetpieceLogic.garrison(pb + db * 0.5, -1, false)
	t.ok(str(si["chip"]["text"]) == str(c["garrison_cleared_word"]) and str(si["chip"]["key"]) == str(c["garrison_cleared_key"]), "the stand-in has no number: the cleared word, then the flip")
	t.ok(SetpieceLogic.drain_count(12, 0.0) == 12 and SetpieceLogic.drain_count(12, 1.0) == 0 and SetpieceLogic.drain_count(12, 0.99) == 1, "the drain hits 0 only at its end")


func _sources_of_garrison(t: TestUtil, c: Dictionary) -> void:
	var real := SetpieceLogic.garrison_from_event({"type": "counter_garrison_cleared", "fort_id": "ashgate", "killed_mass": 23.6})
	t.ok(real == {"fort_id": "ashgate", "n": 24}, "the real event gives its fort and N")
	t.ok(SetpieceLogic.garrison_text(int(real["n"])) == "Vei's living routed: −24", "the real event's callout shows N")
	t.ok(SetpieceLogic.garrison_from_event({"type": "loot_banked", "fort_id": "ashgate"}).is_empty(), "another event is not the source")
	var forts := {"ashgate": {"id": "ashgate", "held": true, "living": 0.0}, "vespers": {"id": "vespers", "held": false}}
	var seen := {"ashgate": {"loot_banked": true}}
	var si := SetpieceLogic.garrison_stand_in("ashgate", forts, seen)
	t.ok(si == {"fort_id": "ashgate", "n": -1}, "the stand-in: back from a held fort's raid that banked loot, no N")
	t.ok(SetpieceLogic.garrison_text(-1) == str(c["garrison_standin_text"]) and not SetpieceLogic.garrison_text(-1).contains("−"), "the stand-in's callout has no number")
	t.ok(SetpieceLogic.garrison_stand_in("ashgate", forts, {"ashgate": {"loot_banked": true, "fort_flipped": true}}).is_empty(), "a flip is the flip's set piece, not this")
	t.ok(SetpieceLogic.garrison_stand_in("ashgate", forts, {"ashgate": {"loot_banked": true, "counter_garrison_cleared": true}}).is_empty(), "the real event replaces the stand-in")
	t.ok(SetpieceLogic.garrison_stand_in("ashgate", forts, {}).is_empty(), "no raid banked: nothing")
	t.ok(SetpieceLogic.garrison_stand_in("vespers", forts, {"vespers": {"loot_banked": true}}).is_empty(), "a fort that is not held: nothing")
	var eps := float(c["garrison_clear_eps"])
	var alive := {"ashgate": {"id": "ashgate", "held": true, "living": 40.0}}
	t.ok(SetpieceLogic.garrison_stand_in("ashgate", alive, seen).is_empty(), "a retreat with garrison left alive: nothing")
	t.ok(SetpieceLogic.garrison_stand_in("ashgate", {"ashgate": {"held": true, "living": eps * 0.5}}, seen) == {"fort_id": "ashgate", "n": -1}, "living within the eps counts as cleared")
	t.ok(SetpieceLogic.garrison_stand_in("ashgate", {"ashgate": {"held": true, "living": eps * 2.0}}, seen).is_empty(), "living over the eps is not cleared")
	t.ok(SetpieceLogic.garrison_stand_in("ashgate", forts, {"ashgate": {"loot_banked": true}, SetpieceLogic.ANY_FORT: {"relish_died": true}}).is_empty(), "a death return: nothing, even with the garrison gone")
	t.ok(SetpieceLogic.garrison_stand_in("ashgate", {"ashgate": {"held": true}}, seen).is_empty(), "no living figure in the model: nothing")
	t.ok(SetpieceLogic.garrison_stand_in("", forts, seen).is_empty() and SetpieceLogic.garrison_stand_in("covington", forts, seen).is_empty(), "back from the town or nowhere: nothing")


func _victory(t: TestUtil, c: Dictionary) -> void:
	var d := float(c["victory_run_beats"])
	t.ok(SetpieceLogic.victory_phase(0.0, false) == SetpieceLogic.RUN, "victory runs first")
	t.ok(SetpieceLogic.victory_phase(d * 0.99, false) == SetpieceLogic.RUN, "for victory_run_beats (about 2)")
	t.ok(SetpieceLogic.victory_phase(d, false) == SetpieceLogic.STOP and SetpieceLogic.victory_phase(d * 10.0, false) == SetpieceLogic.STOP, "then stops, and stays stopped")
	t.ok(SetpieceLogic.victory_u(-1.0) == float(c["victory_u_floor"]) and SetpieceLogic.victory_u(0.9) == 0.9, "a dark lane lights at the floor; a bright one keeps its u")


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
