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
	_tithe_focus(t)
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
	t.ok(a1["text"] == "Drag the valve: toward WAR to garrison your forts, toward FLOOD to clog Vei's queue" and not str(a1["text"]).contains("drown") and a1["target"] == "", "ask 1 text, nothing to click")
	t.ok(a2["text"] == "Send Relish to Old Sluice: taken first time, it holds a blueprint" and a2["target"] == "old-sluice", "ask 2 text, a click selects the fort")
	t.ok(a3["text"] == "Descend into Old Sluice: break its warden to take it" and a3["target"] == "old-sluice", "ask 3 text, a click selects the fort")
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


func _tithe_focus(t: TestUtil) -> void:
	var warn := {"target": "greywall", "eta_s": 88.0, "warning": true, "wave_active": false, "wave_s_left": -1.0, "next_target": "ashgate", "next_s": 300.0}
	var f := OpeningLogic.tithe_focus(warn)
	t.ok(f["fort_id"] == "greywall" and is_equal_approx(float(f["eta_s"]), 88.0), "a warning: the warned fort and its ETA, not next_target")
	var wave := {"target": "greywall", "eta_s": 0.0, "warning": false, "wave_active": true, "wave_s_left": 40.0, "next_target": "ashgate", "next_s": 300.0}
	f = OpeningLogic.tithe_focus(wave)
	t.ok(f["fort_id"] == "greywall" and OpeningLogic.tithe_text("Greywall", float(f["eta_s"])).contains("at Greywall now:"), "a running wave: its fort, ETA 0 reads as now")
	t.ok(not OpeningLogic.tithe_text("Greywall", 0.0).contains("in now"), "never 'in now'")
	var idle := {"target": "", "eta_s": -1.0, "warning": false, "wave_active": false, "wave_s_left": -1.0, "next_target": "ashgate", "next_s": 212.0}
	f = OpeningLogic.tithe_focus(idle)
	t.ok(f["fort_id"] == "ashgate" and is_equal_approx(float(f["eta_s"]), 212.0), "no target: the fort the rule would pick, with next_s")
	f = OpeningLogic.tithe_focus({"target": "", "eta_s": -1.0, "next_target": "", "next_s": -1.0})
	t.ok(f["fort_id"] == "" and is_equal_approx(float(f["eta_s"]), -1.0), "neither: no fort")
	t.ok(OpeningLogic.tithe_focus({})["fort_id"] == "", "an empty view: no fort")


func _seen_reset(t: TestUtil) -> void:
	var path := "user://map_seen_reset_test.cfg"
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.remove_absolute(abs_path)
	MapSeen.forget_memory()
	# the same game keeps its flags, in memory and (after a restart) in the file
	var s := MapSeen.new(path, true)
	s.reconcile("aaaa0001")
	s.mark(MapSeen.VALVE)
	s.reconcile("aaaa0001")
	t.ok(s.has(MapSeen.VALVE), "the same game id again: kept")
	MapSeen.forget_memory()
	var same := MapSeen.new(path, true)
	same.reconcile("aaaa0001")
	t.ok(same.has(MapSeen.VALVE), "read back from the file under the same id: kept")
	# a different id forgets them, in memory and in the file
	MapSeen.forget_memory()
	var other := MapSeen.new(path, true)
	other.reconcile("bbbb0002")
	t.ok(not other.has(MapSeen.VALVE), "a different game id: forgotten")
	MapSeen.forget_memory()
	var after := MapSeen.new(path, true)
	t.ok(not after.has(MapSeen.VALVE), "and forgotten in the file")
	after.mark(MapSeen.TITHE)
	MapSeen.forget_memory()
	var kept := MapSeen.new(path, true)
	kept.reconcile("bbbb0002")
	t.ok(kept.has(MapSeen.TITHE), "the new id is stored: a flag marked under it is kept next time")
	MapSeen.forget_memory()
	var mem_swap := MapSeen.new(path, true)
	mem_swap.mark(MapSeen.VALVE)
	mem_swap.reconcile("cccc0003")
	t.ok(not mem_swap.has(MapSeen.VALVE) and not mem_swap.has(MapSeen.TITHE), "a new id forgets every flag at once, memory included")
	# in memory, no file (a harness session)
	MapSeen.forget_memory()
	DirAccess.remove_absolute(abs_path)
	var h := MapSeen.new(path, false)
	h.reconcile("aaaa0001")
	h.mark(MapSeen.TITHE)
	t.ok(h.has(MapSeen.TITHE), "harness: marked in memory")
	MapSeen.new(path, false).reconcile("aaaa0001")
	t.ok(MapSeen.new(path, false).has(MapSeen.TITHE), "harness: a remount of the same game keeps it")
	MapSeen.new(path, false).reconcile("bbbb0002")
	t.ok(not MapSeen.new(path, false).has(MapSeen.TITHE), "harness: forgotten in memory under a new id")
	t.ok(not FileAccess.file_exists(path), "harness: never writes the file")
	MapSeen.forget_memory()
	DirAccess.remove_absolute(abs_path)
	var legacy := ConfigFile.new()  # a file from before game ids: flags and a times section, no id
	legacy.set_value(MapSeen.SECTION, MapSeen.VALVE, true)
	legacy.set_value("seen_at", MapSeen.VALVE, 500.0)
	legacy.save(path)
	var old_seen := MapSeen.new(path, true)
	t.ok(old_seen.has(MapSeen.VALVE), "a legacy file's flag is read")
	old_seen.reconcile("aaaa0001")
	t.ok(not old_seen.has(MapSeen.VALVE), "and forgotten whole at the first reconcile (no stored id)")
	var raw := ConfigFile.new()
	raw.load(path)
	t.ok(not raw.has_section(MapSeen.SECTION) or raw.get_section_keys(MapSeen.SECTION).is_empty(), "the file's flags are gone")
	t.ok(not raw.has_section("seen_at"), "and so is its times section")
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
	t.ok(OpeningLogic.eta_text(3600.0) == "1h 00m" and OpeningLogic.eta_text(5430.0) == "1h 30m" and OpeningLogic.eta_text(3599.0) == "59:59", "an hour or more reads Nh Mm")
	var txt := OpeningLogic.tithe_text("Ashgate", 240.0)
	t.ok(txt == "Vei is sending a tithe wave at Ashgate in 4:00: a surge of the living to retake it. Stand Relish here, or place a big undead there as siege, to blunt it.", "the explanation names the fort and its ETA")
	t.ok(OpeningLogic.tithe_text("Ashgate", 100.0).contains("in 1:40:"), "and follows the live ETA")


func _panel(t: TestUtil) -> void:
	var vp := Vector2(1600, 900)
	var size := Vector2(300, 150)
	var p := OpeningLogic.panel_pos(Vector2(800, 500), size, vp, 100.0, 30.0, 8.0)
	t.ok(p == Vector2(650, 320), "the panel sits centred above its fort")
	var low := OpeningLogic.panel_pos(Vector2(800, 150), size, vp, 100.0, 30.0, 8.0)
	t.ok(low.y == 180.0, "with no room above (under the HUD) it goes below")
	var edge := OpeningLogic.panel_pos(Vector2(1590, 500), size, vp, 100.0, 30.0, 8.0)
	t.ok(edge.x == 1600.0 - 300.0 - 8.0, "and it is kept inside the viewport")
	t.ok(OpeningLogic.panel_pos(Vector2(800, 500), size, vp, 100.0, 30.0, 8.0, Rect2()) == p, "no card: placement is unchanged")
	var card := Rect2(1200, 60, 392, 780)
	var near := OpeningLogic.panel_pos(Vector2(1300, 500), size, vp, 100.0, 30.0, 8.0, card)
	t.ok(not Rect2(near, size).intersects(card), "a panel over the card moves clear of it")
	t.ok(near.x == 1200.0 - 8.0 - 300.0 and near.y == 320.0, "to the card's left, a margin off, same height")
	t.ok(OpeningLogic.panel_pos(Vector2(400, 500), size, vp, 100.0, 30.0, 8.0, card) == Vector2(250, 320), "a panel already clear stays put")
	var low2 := OpeningLogic.panel_pos(Vector2(1300, 150), size, vp, 100.0, 30.0, 8.0, card)
	t.ok(not Rect2(low2, size).intersects(card) and low2.y == 180.0, "also below the fort, and still under the HUD")
	var narrow := Vector2(700, 900)
	var short_card := Rect2(300, 60, 400, 300)
	var under := OpeningLogic.panel_pos(Vector2(500, 500), size, narrow, 100.0, 30.0, 8.0, short_card)
	t.ok(not Rect2(under, size).intersects(short_card) and under.y == 368.0, "no room on the left: below the card, a margin off")
	var tall_low := Rect2(300, 500, 400, 350)
	var over := OpeningLogic.panel_pos(Vector2(500, 600), size, narrow, 100.0, 30.0, 8.0, tall_low)
	t.ok(not Rect2(over, size).intersects(tall_low) and over.y == 342.0, "none below either: above the card, a margin off")
	var wall := Rect2(300, 60, 400, 780)
	var last := OpeningLogic.panel_pos(Vector2(500, 500), size, narrow, 100.0, 30.0, 8.0, wall)
	t.ok(last == Vector2(8, 320), "nowhere clear: the left-clamped position (it overlaps; the last resort)")


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
