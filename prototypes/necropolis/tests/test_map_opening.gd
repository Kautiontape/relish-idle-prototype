extends RefCounted
## Tests for the opening (task 10): scripts/map/opening_logic.gd, map_seen.gd, the same-cause
## callout fold in hud_logic.gd, and the "lanes respond within 5 s" measurement against a real
## GameState (no autoloads).

const SEEN_PATH := "user://map_seen_test.cfg"


func run() -> int:
	var t := TestUtil.new()
	t.suite("map_opening")
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	_detection(t)
	_stages(t)
	_levels(t)
	_pointer(t)
	_flash(t)
	_seen(t)
	_tithe(t)
	_pending_tithe(t)
	_seen_reset(t)
	_panel(t)
	_collapse(t)
	_response(t)
	return t.failures


func _forts(flipped := 0, first := true) -> Array:
	return [{"id": "ashgate", "name": "Ashgate", "flipped_count": 0, "first_dungeon": false},
		{"id": "old-sluice", "name": "Old Sluice", "flipped_count": flipped, "first_dungeon": first}]


func _detection(t: TestUtil) -> void:
	var secs := float(OpeningLogic.cfg()["opening_s"])
	t.ok(OpeningLogic.active(0.0, _forts()), "the opening is active at t = 0")
	t.ok(OpeningLogic.active(secs - 1.0, _forts()), "and just under opening_s")
	t.ok(not OpeningLogic.active(secs, _forts()), "not at opening_s")
	t.ok(not OpeningLogic.active(10.0, _forts(1)), "not once a fort has flipped")
	t.ok(OpeningLogic.first_dungeon(_forts())["id"] == "old-sluice", "the first dungeon is the fort carrying the flag")
	t.ok(OpeningLogic.first_dungeon(_forts(0, false)).is_empty(), "none once the flag has cleared")


func _stages(t: TestUtil) -> void:
	var home := {"state": "home", "at": "covington", "target": ""}
	var go := {"state": "travelling", "at": "covington", "target": "old-sluice"}
	var other := {"state": "travelling", "at": "covington", "target": "ashgate"}
	var there := {"state": "at_fort", "at": "old-sluice", "target": ""}
	var secs := float(OpeningLogic.cfg()["opening_s"])
	t.ok(OpeningLogic.stage(1.0, _forts(), home, false) == OpeningLogic.VALVE, "ask 1: the valve, until it is first committed")
	t.ok(OpeningLogic.stage(1.0, _forts(), go, false) == OpeningLogic.VALVE, "the valve ask holds even if Relish already walks")
	t.ok(OpeningLogic.stage(1.0, _forts(), home, true) == OpeningLogic.SEND, "ask 2: send Relish once the valve is committed")
	t.ok(OpeningLogic.stage(1.0, _forts(), other, true) == OpeningLogic.SEND, "travelling elsewhere is still ask 2")
	t.ok(OpeningLogic.stage(1.0, _forts(), go, true) == OpeningLogic.DESCEND, "ask 3 as soon as she travels to the first dungeon")
	t.ok(OpeningLogic.stage(1.0, _forts(), there, true) == OpeningLogic.DESCEND, "and while she stands at it")
	t.ok(OpeningLogic.stage(1.0, _forts(0, false), there, true) == OpeningLogic.NONE, "the strip is handed back once the first dungeon is cleared")
	t.ok(OpeningLogic.stage(secs, _forts(), home, false) == OpeningLogic.NONE, "every ask ends with the opening (time)")
	t.ok(OpeningLogic.stage(1.0, _forts(1), home, false) == OpeningLogic.NONE, "and at the first flip")
	var a1 := OpeningLogic.ask(OpeningLogic.VALVE, _forts())
	var a2 := OpeningLogic.ask(OpeningLogic.SEND, _forts())
	var a3 := OpeningLogic.ask(OpeningLogic.DESCEND, _forts())
	t.ok(a1["text"] == "Drag toward WAR to hold forts, toward FLOOD to drown Vei" and a1["target"] == "", "ask 1 text, nothing to click")
	t.ok(a2["text"] == "Send Relish to Old Sluice: its first clear holds a blueprint" and a2["target"] == "old-sluice", "ask 2 text, a click selects the fort")
	t.ok(a3["text"] == "Descend into Old Sluice" and a3["target"] == "old-sluice", "ask 3 text, a click selects the fort")
	t.ok(OpeningLogic.ask(OpeningLogic.NONE, _forts())["text"] == "", "no stage: an empty ask clears the strip")
	t.ok(OpeningLogic.pointer_shown(OpeningLogic.VALVE, false), "the pointer shows during ask 1")
	t.ok(not OpeningLogic.pointer_shown(OpeningLogic.VALVE, true), "not while the handle is held")
	t.ok(not OpeningLogic.pointer_shown(OpeningLogic.SEND, false), "and gone from ask 2 on")


func _levels(t: TestUtil) -> void:
	t.near(OpeningLogic.level(0.3, true), 1.0, 0.0001, "reduced motion: a fixed full level")
	t.near(OpeningLogic.level(0.3, false), 0.3, 0.0001, "otherwise the beat's wave")


func _pointer(t: TestUtil) -> void:
	var oc := OpeningLogic.cfg()
	t.ok(not oc.has("hint_text") and not oc.has("hint_font_px") and not oc.has("hint_pad_px") and not oc.has("hint_gap_px") and not oc.has("hint_plate_alpha"), "the label over the triangle is gone from the config")
	var mx := float(oc["line_max_px"])
	var st := float(oc["line_start_px"])
	t.near(mx, 240.0, 0.0001, "the pointer's line is at most 240 px")
	var far := OpeningLogic.pointer_segment(Vector2(100, 100), Vector2(1100, 100), st, mx)
	t.ok(far[0].distance_to(far[1]) <= mx + 0.001, "a far Covington: the line is capped (%.1f px)" % far[0].distance_to(far[1]))
	t.ok(far[1] == Vector2(1100, 100) and is_equal_approx(far[0].y, 100.0) and far[0].x > 100.0 + st, "it ends at the valve corner and starts well past Covington's glyph")
	var diag := OpeningLogic.pointer_segment(Vector2(0, 0), Vector2(3000, 4000), st, mx)
	t.ok(diag[0].distance_to(diag[1]) <= mx + 0.001 and is_equal_approx((diag[1] - diag[0]).normalized().dot(Vector2(0.6, 0.8)), 1.0), "capped on a diagonal too, still aimed from Covington")
	var near := OpeningLogic.pointer_segment(Vector2(0, 0), Vector2(200, 0), st, mx)
	t.ok(near[0] == Vector2(st, 0) and near[1] == Vector2(200, 0), "Covington nearer than line_max_px: the whole line from line_start_px")
	var d := OpeningLogic.chevrons(Vector2.ZERO, Vector2(100, 0), 20.0, 4.0, 0.0)
	t.ok(d.size() > 0 and d.size() % 4 == 0, "chevrons are two arms each (%d points)" % d.size())
	var tip := d[1]
	t.ok(tip.x <= 100.0 and d[0].x < tip.x and d[3].x < tip.x and is_equal_approx(d[0].y, -d[3].y), "each chevron points toward the end")
	var moved := OpeningLogic.chevrons(Vector2.ZERO, Vector2(100, 0), 20.0, 4.0, 5.0)
	t.ok(moved[1].x > tip.x, "an offset marches them toward the valve")
	t.ok(OpeningLogic.chevrons(Vector2.ONE, Vector2.ONE, 20.0, 4.0, 0.0).is_empty(), "no chevrons on a zero-length line")


func _flash(t: TestUtil) -> void:
	var beat := 1714.0
	t.near(OpeningLogic.flash_level(-1.0, beat, 0.2, false), 0.2, 0.0001, "no flash: the beat's wave")
	t.near(OpeningLogic.flash_level(0.0, beat, 0.2, false), 1.0, 0.0001, "a click: full level at once")
	t.near(OpeningLogic.flash_level(beat - 1.0, beat, 0.2, false), 1.0, 0.0001, "held for one beat")
	t.near(OpeningLogic.flash_level(beat, beat, 0.2, false), 0.2, 0.0001, "then back to the wave")
	t.near(OpeningLogic.flash_level(beat * 0.5, beat, 0.2, true), 1.0, 0.0001, "reduced motion: a static full level during the flash")
	t.near(OpeningLogic.flash_level(beat * 2.0, beat, 0.2, true), 1.0, 0.0001, "and the reduced-motion level after it")
	t.ok(OpeningLogic.flash_active(0.0, beat) and not OpeningLogic.flash_active(beat, beat) and not OpeningLogic.flash_active(-1.0, beat), "active for [0, one beat)")


func _pending_tithe(t: TestUtil) -> void:
	var forts := [{"id": "ashgate", "tithe": {"targeted": false, "eta_s": -1.0}}, {"id": "greywall", "tithe": {"targeted": true, "eta_s": 88.0}}]
	var p := OpeningLogic.pending_tithe(forts, false)
	t.ok(p["fort_id"] == "greywall" and is_equal_approx(float(p["eta_s"]), 88.0), "a warning already pending names its fort and the view's ETA")
	t.ok(OpeningLogic.pending_tithe(forts, true).is_empty(), "nothing once the explanation has been seen")
	t.ok(OpeningLogic.pending_tithe([forts[0]], false).is_empty(), "nothing when no fort is targeted")


func _seen_reset(t: TestUtil) -> void:
	var path := "user://map_seen_reset_test.cfg"
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.remove_absolute(abs_path)
	MapSeen.forget_memory()
	var ng := 2.0
	var s := MapSeen.new(path, true)
	s.mark(MapSeen.VALVE, 500.0)
	s.reconcile(600.0, ng)
	t.ok(s.has(MapSeen.VALVE), "read at t = 600 (marked at 500): kept")
	MapSeen.forget_memory()
	var late := MapSeen.new(path, true)
	late.reconcile(490.0, ng)
	t.ok(late.has(MapSeen.VALVE), "a lagging autosave (marked 500, read at 490): kept, it is not a new game")
	MapSeen.forget_memory()
	var f := MapSeen.new(path, true)
	f.reconcile(0.5, ng)
	t.ok(not f.has(MapSeen.VALVE), "read at t = 0.5 (marked at 500): a new game, forgotten")
	MapSeen.forget_memory()
	t.ok(not MapSeen.new(path, true).has(MapSeen.VALVE), "and forgotten in the file")
	MapSeen.forget_memory()
	DirAccess.remove_absolute(abs_path)
	var early := MapSeen.new(path, true)
	early.mark(MapSeen.VALVE, 3.0)
	MapSeen.forget_memory()
	var early2 := MapSeen.new(path, true)
	early2.reconcile(0.5, ng)
	t.ok(not early2.has(MapSeen.VALVE), "marked at t = 3, read at a new game: forgotten")
	MapSeen.forget_memory()
	DirAccess.remove_absolute(abs_path)
	var cont := MapSeen.new(path, true)
	cont.mark(MapSeen.VALVE, 1000.0)
	MapSeen.forget_memory()
	var cont2 := MapSeen.new(path, true)
	cont2.reconcile(990.0, ng)
	t.ok(cont2.has(MapSeen.VALVE), "marked at 1000, read at 990: kept")
	# in memory, no file (a harness session)
	MapSeen.forget_memory()
	DirAccess.remove_absolute(abs_path)
	var h := MapSeen.new(path, false)
	h.mark(MapSeen.TITHE, 500.0)
	t.ok(h.has(MapSeen.TITHE), "harness: marked in memory")
	MapSeen.new(path, false).reconcile(0.5, ng)
	t.ok(not MapSeen.new(path, false).has(MapSeen.TITHE), "harness: forgotten in memory for that path")
	t.ok(not FileAccess.file_exists(path), "harness: still no file")
	MapSeen.forget_memory()
	DirAccess.remove_absolute(abs_path)
	var legacy := MapSeen.new(path, true)
	legacy.mark(MapSeen.VALVE)
	legacy.reconcile(600.0, ng)
	t.ok(legacy.has(MapSeen.VALVE), "a flag with no recorded time is kept at t = 600")
	legacy.reconcile(0.5, ng)
	t.ok(not legacy.has(MapSeen.VALVE), "and forgotten at t = 0.5")
	MapSeen.forget_memory()
	DirAccess.remove_absolute(abs_path)
	var old := ConfigFile.new()  # a file from before seen_at: [seen] only, no times section
	old.set_value(MapSeen.SECTION, MapSeen.VALVE, true)
	old.save(path)
	var old_seen := MapSeen.new(path, true)
	t.ok(old_seen.has(MapSeen.VALVE), "an old-format file's flag is read")
	old_seen.reconcile(0.5, ng)
	t.ok(not old_seen.has(MapSeen.VALVE), "and forgotten at a new game without a times section")
	MapSeen.forget_memory()
	t.ok(not MapSeen.new(path, true).has(MapSeen.VALVE), "in the file too")
	MapSeen.forget_memory()
	DirAccess.remove_absolute(abs_path)


func _seen(t: TestUtil) -> void:
	var abs_path := ProjectSettings.globalize_path(SEEN_PATH)
	DirAccess.remove_absolute(abs_path)
	MapSeen.forget_memory()
	var s := MapSeen.new(SEEN_PATH, true)
	t.ok(not s.has(MapSeen.VALVE) and not s.has(MapSeen.TITHE), "a fresh file: nothing seen")
	s.mark(MapSeen.VALVE)
	t.ok(s.has(MapSeen.VALVE) and not s.has(MapSeen.TITHE), "marked: only that flag")
	MapSeen.forget_memory()
	var again := MapSeen.new(SEEN_PATH, true)
	t.ok(again.has(MapSeen.VALVE) and not again.has(MapSeen.TITHE), "it persists across sessions (read back from the file)")
	again.mark(MapSeen.TITHE)
	MapSeen.forget_memory()
	var both := MapSeen.new(SEEN_PATH, true)
	t.ok(both.has(MapSeen.VALVE) and both.has(MapSeen.TITHE), "both flags are kept")
	# a harness session reads the file as empty and never writes it
	MapSeen.forget_memory()
	var h := MapSeen.new(SEEN_PATH, false)
	t.ok(not h.has(MapSeen.VALVE) and not h.has(MapSeen.TITHE), "harness: the file reads as empty, so shots always show the opening")
	DirAccess.remove_absolute(abs_path)
	h.mark(MapSeen.VALVE)
	t.ok(h.has(MapSeen.VALVE), "harness: a mark holds in memory for the process")
	t.ok(not FileAccess.file_exists(SEEN_PATH), "harness: nothing is ever written")
	MapSeen.forget_memory()
	t.ok(not MapSeen.new(SEEN_PATH, false).has(MapSeen.VALVE), "harness: and it is gone with the process")
	DirAccess.remove_absolute(abs_path)


func _tithe(t: TestUtil) -> void:
	t.ok(OpeningLogic.eta_text(240.0) == "4:00", "240 s reads 4:00")
	t.ok(OpeningLogic.eta_text(232.2) == "3:53", "a live ETA rounds up to the second")
	t.ok(OpeningLogic.eta_text(9.0) == "0:09", "seconds are padded")
	t.ok(OpeningLogic.eta_text(0.0) == "now" and OpeningLogic.eta_text(-1.0) == "now", "a running wave (0.0) or an unknown ETA (-1) reads as now, never a number")
	var txt := OpeningLogic.tithe_text("Ashgate", 240.0)
	t.ok(txt == "Vei is sending a tithe wave at Ashgate in 4:00: a surge of the living to retake it. Stand Relish here, or place a big undead there as siege, to blunt it.", "the explanation names the fort and its ETA")
	t.ok(OpeningLogic.tithe_text("Ashgate", 100.0).contains("in 1:40:"), "and follows the live ETA")
	var forts := [{"id": "ashgate", "tithe": {"targeted": true, "eta_s": 88.0, "wave_active": false}}, {"id": "greywall", "tithe": {"targeted": false, "eta_s": -1.0, "wave_active": false}}]
	t.near(OpeningLogic.tithe_eta(forts, "ashgate", 240.0), 88.0, 0.0001, "the live ETA is the fort's tithe.eta_s while targeted")
	t.near(OpeningLogic.tithe_eta(forts, "greywall", 240.0), 240.0, 0.0001, "an untargeted fort falls back to the event's ETA")
	t.ok(OpeningLogic.debug_tithe_fort(forts, "old-sluice") == "ashgate", "the debug trigger picks the fort a warning targets")
	t.ok(OpeningLogic.debug_tithe_fort([forts[1]], "old-sluice") == "old-sluice", "else the demo fort")


func _panel(t: TestUtil) -> void:
	var vp := Vector2(1600, 900)
	var size := Vector2(300, 150)
	var p := OpeningLogic.panel_pos(Vector2(800, 500), size, vp, 100.0, 30.0, 8.0)
	t.ok(p == Vector2(650, 320), "the panel sits centred above its fort")
	var low := OpeningLogic.panel_pos(Vector2(800, 150), size, vp, 100.0, 30.0, 8.0)
	t.ok(low.y == 180.0, "with no room above (under the HUD) it goes below")
	var edge := OpeningLogic.panel_pos(Vector2(1590, 500), size, vp, 100.0, 30.0, 8.0)
	t.ok(edge.x == 1600.0 - 300.0 - 8.0, "and it is kept inside the viewport")


func _lane(kind: String, from: String, to: String, rate: float, why: String) -> Dictionary:
	return {"id": "%s:%s:%s" % [kind, from, to], "kind": kind, "from": from, "to": to, "rate": rate, "bias": 1.0, "why": why}


func _collapse(t: TestUtil) -> void:
	var lanes: Array = []
	for i in 9:
		lanes.append(_lane("war", "covington", "fort%d" % i, 0.3, "valve"))
	lanes.append(_lane("war", "covington", "ashgate", 5.0, "staging"))
	lanes.append(_lane("war", "covington", "greywall", 0.1, "staging"))
	lanes.append(_lane("living", "vei", "ashgate", 2.0, "tithe wave"))
	lanes.append(_lane("flood", "covington", "vei", 1.0, ""))
	var min_n := int(MapLogic.cfg()["callouts"]["collapse_min"])
	t.ok(min_n == 3, "collapse_min is 3")
	var items := HudLogic.callout_items(lanes, min_n)
	var groups := items.filter(func(r): return bool(r.get("group", false)))
	t.ok(groups.size() == 1, "nine WAR lanes sharing a cause fold into ONE row (got %d groups)" % groups.size())
	var g: Dictionary = groups[0]
	t.ok(int(g["count"]) == 9 and g["kind"] == "war" and g["why"] == "valve", "the group counts its lanes and keeps kind and cause")
	t.near(float(g["rate"]), 2.7, 0.0001, "its rate is the lanes' sum")
	t.ok(g["from"] == "covington", "anchored at the common source node (Covington)")
	t.ok(items.size() == 1 + 2 + 1, "the two staging lanes stay individual (under collapse_min), plus the tithe lane; the whyless lane is no callout (%d rows)" % items.size())
	t.ok(items.filter(func(r): return r["why"] == "valve" and not bool(r.get("group", false))).is_empty(), "no valve lane is left on its own")
	t.ok(is_equal_approx(float(items[0]["rate"]), 5.0) and is_equal_approx(float(items[1]["rate"]), 2.7), "still loudest first, by the folded rate")
	var parts := HudLogic.callout_parts(g, {})
	t.ok(parts["head"] == "WAR ×9 · valve · " and parts["rate"] == "+2.7/s" and parts["tail"] == " total", "the text reads WAR ×9 · valve · +2.7/s total (%s)" % (parts["head"] + parts["rate"] + parts["tail"]))
	# a tithe from Vei folds at Vei
	var wave: Array = []
	for i in 3:
		wave.append(_lane("living", "vei", "f%d" % i, 1.0, "tithe wave"))
	var w := HudLogic.callout_items(wave, 3)
	t.ok(w.size() == 1 and w[0]["from"] == "vei" and int(w[0]["count"]) == 3, "a tithe wave on three forts folds at Vei")
	# the same cause from different sources never merges
	var mixed := [_lane("war", "covington", "a", 1.0, "valve"), _lane("war", "covington", "b", 1.0, "valve"), _lane("war", "vei", "c", 1.0, "valve")]
	t.ok(HudLogic.callout_items(mixed, 3).size() == 3, "lanes of different sources do not fold")
	t.ok(HudLogic.callout_items(lanes, 0).size() == HudLogic.callout_rows(lanes).size(), "collapse_min 0 folds nothing")


## The 5 s promise: the war lanes' summed rate has covered response_frac of its final change.
func _response(t: TestUtil) -> void:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	t.ok(bool(s.cmd_debug_load_fixture("day1")["ok"]), "day1 loads")
	s.tick(2.0)  # the first substeps fill the split at the default valve
	var base := _war_rate(s)
	t.ok(base > 0.0, "the war lanes carry the default valve's WAR (%.2f/s)" % base)
	t.ok(bool(s.cmd_set_valve(0.1, 0.8, 0.1)["ok"]), "a WAR-heavy split is accepted")
	s.tick(5.0)
	var at5 := _war_rate(s)
	s.tick(20.0)
	var final := _war_rate(s)
	var frac := OpeningLogic.response_fraction(base, at5, final)
	print("  MEASURED 5 s response: base %.2f/s, at 5 s %.2f/s, final %.2f/s, fraction %.3f" % [base, at5, final, frac])
	t.ok(final > base, "the war lanes grow to the new split (%.2f -> %.2f/s)" % [base, final])
	t.ok(frac >= float(OpeningLogic.cfg()["response_frac"]), "5 s after the change the war lanes have moved %.0f%% of the way (needs %.0f%%)" % [frac * 100.0, float(OpeningLogic.cfg()["response_frac"]) * 100.0])
	t.near(OpeningLogic.response_fraction(1.0, 1.0, 1.0), 1.0, 0.0001, "a rate that never changes counts as landed")


func _war_rate(s: GameState) -> float:
	var sum := 0.0
	for l in s.view_lanes()["lanes"]:
		if str(l["kind"]) == "war":
			sum += float(l["rate"])
	return sum
