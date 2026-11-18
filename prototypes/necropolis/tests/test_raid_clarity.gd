extends RefCounted
## Phase I raid clarity (dungeon-i): the retreat panel (item 8: Space never confirms a retreat) and the
## retreat lines (item 6). Pure logic and the real RaidRetreatPanel class; no scene tree, no autoloads.


func run() -> int:
	var t := TestUtil.new()
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	_retreat_panel_tests(t)
	_retreat_line_tests(t)
	_warden_presence_tests(t)
	_legend_tests(t)
	return t.failures


## T1: the control legend. Open until a fort is taken, then a chip; only a left press on its header or
## chip toggles it; keys never do. The HUD names Game/ConfigDb, so it is checked by source text.
func _legend_tests(t: TestUtil) -> void:
	t.suite("raid_legend")
	t.ok(RaidLogic.legend_open_at_start(0) and not RaidLogic.legend_open_at_start(1) and not RaidLogic.legend_open_at_start(3),
		"open at 0 forts taken, collapsed after one or more")
	var cfg: Dictionary = TestUtil.load_json("res://configs/raid.json").get("hud", {}).get("legend", {})
	t.ok(cfg.has("_doc") and float(cfg.get("chip_h", 0)) >= 44.0 and float(cfg.get("key_px", 0)) >= 12.0 and float(cfg.get("row_px", 0)) >= 12.0,
		"hud.legend is documented, with a 44 px chip and text of at least 12 px")
	var l := RaidLegend.new()
	l.setup(cfg, true)
	t.ok(l.focus_mode == Control.FOCUS_NONE and l.mouse_filter == Control.MOUSE_FILTER_STOP, "no focus; it stops the mouse")
	t.ok(l.get_child_count() == 0, "no child controls")
	var open_h := l.size.y
	var open_w := l.size.x
	l.position = Vector2(18.0, 300.0)
	var bottom := l.position.y + l.size.y
	var on_row2 := Vector2(open_w * 0.5, open_h * 0.5)
	t.ok(not l.classify(_mouse(MOUSE_BUTTON_LEFT, on_row2)), "a left press on the rows does not toggle")
	t.ok(l.classify(_mouse(MOUSE_BUTTON_LEFT, Vector2(open_w - 20.0, 14.0))), "a left press on the header toggles")
	l.toggle()
	t.ok(not l.is_open and l.size.y >= 44.0 and l.size.y < open_h, "collapsed: a chip at least 44 px tall, shorter than the plate")
	t.ok(is_equal_approx(l.position.y + l.size.y, bottom), "the bottom edge stays put when it collapses")
	var on_chip := l.size * 0.5
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	var none := not l.classify(_mouse(MOUSE_BUTTON_RIGHT, on_chip)) and not l.classify(_mouse(MOUSE_BUTTON_LEFT, on_chip, false))
	for ev in [_key(KEY_SPACE), _key(KEY_ENTER), _key(KEY_ESCAPE), accept]:
		none = none and not l.classify(ev)
	t.ok(none, "a right press, a left release and Space, Enter, Esc, ui_accept never toggle")
	t.ok(l.classify(_mouse(MOUSE_BUTTON_LEFT, on_chip)), "a left press on the chip opens it")
	l.toggle()
	t.ok(l.is_open and is_equal_approx(l.size.y, open_h) and is_equal_approx(l.position.y + l.size.y, bottom), "reopened to the same plate, bottom edge fixed")
	l.free()
	var hud_src := FileAccess.get_file_as_string("res://scripts/raid/raid_hud.gd")
	t.ok(hud_src.contains("Game.state.view_hud().get(\"highest_tier_flipped\", 0)"), "the HUD reads highest_tier_flipped from view_hud()")
	var i := hud_src.find("RaidLegend.new()")
	t.ok(i > 0 and hud_src.substr(maxi(0, i - 400), 400).contains("if not boss_mode:"), "RaidLegend is built only when not boss_mode")
	t.ok(RegEx.create_from_string("_legend\\.visible = not raid\\._ended").search(hud_src) != null, "the legend hides once the run has ended")


## T3: a sleeping warden reads as a boss. Knobs in configs/raid.json; warden.gd needs Pulse/ConfigDb so
## it is checked by source text.
func _warden_presence_tests(t: TestUtil) -> void:
	t.suite("warden_presence")
	var w: Dictionary = TestUtil.load_json("res://configs/raid.json").get("wardens", {})
	var pc: Dictionary = w.get("presence", {})
	for k in ["ring_mult", "ring_alpha", "dash_gap_px", "tick_px", "plinth_y", "plinth_rx", "plinth_ry",
			"plinth_alpha", "name_px", "label_px", "plate_alpha", "plate_gap_px"]:
		t.ok(pc.has(k) and (pc[k] is float or pc[k] is int), "presence." + k + " is a number")
	t.ok(float(pc.get("ring_mult", 0.0)) > 1.5, "the boss ring stands well outside the body")
	for k in ["ring_alpha", "plinth_alpha", "plate_alpha"]:
		t.ok(float(pc.get(k, 0.0)) > 0.0 and float(pc.get(k, 0.0)) <= 1.0, k + " in (0, 1]")
	t.ok(float(pc.get("name_px", 0)) >= 12.0 and float(pc.get("label_px", 0)) >= 12.0, "plate text at least 12 px")
	t.ok(float(w.get("dormant_alpha", 0.0)) >= 0.6, "the sleeping glyph is not faint")
	var src := FileAccess.get_file_as_string("res://scripts/raid/warden.gd")
	t.ok(RegEx.create_from_string("if not awake:\\s*_draw_presence\\(\\)").search(src) != null, "_draw calls _draw_presence only while asleep")
	var i := src.find("func _draw_presence()")
	var body := src.substr(i, src.find("\nfunc ", i + 10) - i) if i >= 0 else ""
	t.ok(body.contains("wcfg().get(\"presence\""), "_draw_presence reads presence from wcfg()")
	t.ok(body.contains("\"WARDEN\"") and body.contains("break it to take this fort"), "the plates say WARDEN and what breaking it does")
	t.ok(body.contains("zoom()"), "sizes are held in screen px by the zoom")


func _key(code: Key, pressed := true) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = pressed
	return k


func _mouse(button: MouseButton, pos: Vector2, pressed := true) -> InputEventMouseButton:
	var m := InputEventMouseButton.new()
	m.button_index = button
	m.position = pos
	m.global_position = pos
	m.pressed = pressed
	return m


## Item 8: the cac5a17 ConfirmationDialog focused its OK button, and Space (the trance key) is also
## ui_accept, so one Space press confirmed a retreat. The panel takes no focus and only a left click on
## RETREAT confirms.
func _retreat_panel_tests(t: TestUtil) -> void:
	t.suite("raid_retreat_panel")
	var p := RaidRetreatPanel.new()
	p.open(PackedStringArray(["a", "b", "c"]))
	var got := []
	p.chosen.connect(func(go: bool) -> void: got.append(go))
	t.ok(p.focus_mode == Control.FOCUS_NONE, "the panel never takes focus")
	t.ok(p.get_child_count() == 0, "no child controls (no Button to focus and press with ui_accept)")
	t.ok(p.is_open() and p.retreat_rect().size.y >= 44.0 and p.stay_rect().size.y >= 44.0, "open, with 44 px buttons")
	var on_retreat := p.retreat_rect().get_center()
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	var keys := [_key(KEY_SPACE), _key(KEY_ENTER), _key(KEY_KP_ENTER), _key(KEY_ESCAPE), accept]
	var none := true
	for ev in keys:
		none = none and p.classify(ev) == ""
	t.ok(none, "no key confirms: Space, Enter, keypad Enter, Esc and the ui_accept action all classify as nothing")
	for ev in keys:
		p.apply(p.classify(ev))
	t.ok(got.is_empty() and p.is_open(), "applied, the keys neither retreat nor close it")
	t.ok(p.classify(_mouse(MOUSE_BUTTON_RIGHT, on_retreat)) == "", "a right click on RETREAT does nothing (right mouse is the trance)")
	t.ok(p.classify(_mouse(MOUSE_BUTTON_LEFT, on_retreat, false)) == "", "a left release on RETREAT does nothing")
	t.ok(p.classify(_mouse(MOUSE_BUTTON_LEFT, Vector2(2, 2))) == "", "a left click on the plate, off the buttons, does nothing")
	t.ok(p.classify(_mouse(MOUSE_BUTTON_LEFT, p.stay_rect().get_center())) == "stay", "a left click on STAY stays")
	p.apply(p.classify(_mouse(MOUSE_BUTTON_LEFT, p.stay_rect().get_center())))
	t.ok(got == [false] and not p.is_open(), "STAY closes the panel and says stay")
	p.open(PackedStringArray(["a"]))
	p.apply(p.classify(_mouse(MOUSE_BUTTON_LEFT, p.retreat_rect().get_center())))
	t.ok(got == [false, true] and not p.is_open(), "a left click on RETREAT is the one way to retreat")
	p.apply("retreat")
	t.ok(got.size() == 2, "a closed panel ignores a late choice")
	t.ok(RaidRetreatPanel.is_stay_key(_key(KEY_SPACE)) and RaidRetreatPanel.is_stay_key(_key(KEY_ESCAPE))
		and RaidRetreatPanel.is_stay_key(_mouse(MOUSE_BUTTON_RIGHT, Vector2.ZERO)), "Space, Esc and right mouse are stay keys")
	t.ok(not RaidRetreatPanel.is_stay_key(_key(KEY_SPACE, false)) and not RaidRetreatPanel.is_stay_key(_mouse(MOUSE_BUTTON_LEFT, Vector2.ZERO)),
		"a release, or a left click, is not a stay key")
	p.free()
	# source guards: no dialog anywhere in the raid that a key could confirm; the raid closes the panel on a stay key
	var dialogs := []
	var made := RegEx.create_from_string("(ConfirmationDialog|AcceptDialog)\\.new\\(|:\\s*(ConfirmationDialog|AcceptDialog)\\b|extends\\s+(ConfirmationDialog|AcceptDialog)")
	var dir := DirAccess.open("res://scripts/raid")
	for f in dir.get_files():
		if f.ends_with(".gd") and made.search(FileAccess.get_file_as_string("res://scripts/raid/" + f)) != null:
			dialogs.append(f)
	t.ok(dialogs.is_empty(), "no ConfirmationDialog or AcceptDialog in scripts/raid (found: %s)" % str(dialogs))
	var raid_src := FileAccess.get_file_as_string("res://scripts/raid/raid.gd")
	t.ok(RegEx.create_from_string("retreat_open\\(\\) and RaidRetreatPanel\\.is_stay_key\\(ev\\):\\s*hud\\.close_retreat\\(\\)").search(raid_src) != null,
		"the raid closes the panel on a stay key before the trance reads it")
	var hud_src := FileAccess.get_file_as_string("res://scripts/raid/raid_hud.gd")
	t.ok(hud_src.contains("raid.endings.try_retreat(\"click\")"), "the panel's RETREAT is labelled a click for the capture")
	var cap_src := FileAccess.get_file_as_string("res://scripts/raid/raid_capture.gd")
	t.ok(cap_src.contains("\"retreat_by\": _raid.endings.retreat_by"), "the capture row carries the retreat trigger")


## Item 6: the panel says what a retreat keeps (as counts) and what stays, in the glossary's words.
func _retreat_line_tests(t: TestUtil) -> void:
	t.suite("raid_retreat_lines")
	var keep := RaidLogic.loot_counts(RaidLogic.loot_snapshot({"relics": 2, "husks": [{"kind": "skeleton"}]}, 5))
	var l := RaidLogic.retreat_lines(false, keep, "")
	t.ok(l[0] == "You keep everything you found and all carried essence.", "first: what you keep")
	t.ok(l[1].contains("relics 2") and l[1].contains("husks 1") and l[1].contains("essence 5"), "then the counts a retreat pays")
	t.ok(l[2].begins_with("The fort stays Vei's") and l.size() == 3, "then what stays: the fort stays Vei's")
	var e := RaidLogic.retreat_lines(true, RaidLogic.loot_counts(RaidLogic.empty_loot()), "\nBone Knight is on the plate · lost if you retreat.")
	t.ok(e[1].contains("nothing yet"), "nothing found: 'nothing yet'")
	t.ok(e[2] == "The fort stays yours.", "a held fort stays yours")
	t.ok(e.size() == 4 and e[3] == "Bone Knight is on the plate · lost if you retreat.", "the held door's line, without its newline")
	var paid := RaidLogic.loot_counts(RaidLogic.result_loot("retreated", false, {"relics": 2, "husks": [{"kind": "skeleton"}]}, 5, {}))
	t.ok(paid["relics"] == keep["relics"] and paid["husks"] == keep["husks"] and paid["essence"] == keep["essence"],
		"the counts shown are what result_loot pays a retreat")
