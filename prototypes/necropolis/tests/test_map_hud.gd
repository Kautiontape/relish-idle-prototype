extends RefCounted
## Tests for the type law (scripts/map/map_type.gd) and the HUD's pure logic
## (scripts/map/hud_logic.gd): the top-bar items, the status block, the lane callout text,
## their greedy non-overlapping placement and the count cap.


func run() -> int:
	var t := TestUtil.new()
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	_type(t)
	_contrast(t)
	_bar(t)
	_status(t)
	_tithe_line(t)
	_bone_line(t)
	_callout_text(t)
	_callout_rows(t)
	_placement(t)
	_drag_cap(t)
	_rects_key(t)
	_one_source(t)
	_layer_keys(t)
	_fit(t)
	_wrap(t)
	_clarity(t)
	_tip_rect(t)
	return t.failures


## The map's readouts as tip obstacles, the world-to-screen conversion, and TipPlacer's placement state.
func _tip_readouts(t: TestUtil, vp: Vector2, plates: Array, odds: Rect2, tip: Vector2) -> void:
	t.suite("map_hud-tip-readouts")
	var view := Rect2(Vector2.ZERO, vp)
	var bare := HudLogic.tip_rect(odds, tip, plates, vp)
	# a Vei readout where candidate 2 (right of the plates, under the bar) would land
	var ro := Rect2(bare.position + Vector2(40.0, 6.0), Vector2(150.0, 70.0))
	t.ok(bare.intersects(ro), "premise: the readout sits where the tip would land: %s" % str(bare))
	var r := HudLogic.tip_rect(odds, tip, plates, vp, Rect2(), [ro])
	var hit := false
	for p in plates:
		hit = hit or r.intersects(p)
	t.ok(not r.intersects(ro) and not hit and view.encloses(r) and r.size == tip, "the readout is an obstacle: the plate clears it and the plates, on screen: %s" % str(r))
	# a long (MINT-length) tip, and readouts stacked under the first
	var long_tip := Vector2(420.0, 130.0)
	var ro2 := Rect2(ro.position.x - 20.0, ro.end.y + 4.0, 200.0, 40.0)
	var r3 := HudLogic.tip_rect(odds, long_tip, plates, vp, Rect2(), [ro, ro2])
	t.ok(not r3.intersects(ro) and not r3.intersects(ro2) and view.encloses(r3) and r3.size == long_tip, "a long tip clears two stacked readouts: %s" % str(r3))
	# the readouts do not move where the plates end: candidate 1 still sits at the word's x when there is room
	var roomy := HudLogic.tip_rect(odds, tip, [Rect2(0, 0, 860, 60)], vp, Rect2(), [Rect2(1200, 400, 100, 50)])
	t.ok(roomy.position.x == odds.position.x, "a readout far away leaves the plate under its word: %s" % str(roomy))
	# world to screen: (world - camera) x zoom + viewport / 2, the inverse of screen_to_zoomed up to the zoom
	var w := Rect2(300, 200, 40, 20)
	var s := HudLogic.world_to_screen(w, Vector2(250, 180), 2.0, vp)
	t.ok(s == Rect2(Vector2(900.0, 490.0), Vector2(80.0, 40.0)), "world_to_screen centres the camera and scales: %s" % str(s))
	var back := HudLogic.screen_to_zoomed(s, Vector2(250, 180), 2.0, vp)
	t.ok(back.position.is_equal_approx(w.position * 2.0) and back.size.is_equal_approx(w.size * 2.0), "and screen_to_zoomed takes it to the zoomed frame: %s" % str(back))
	# Vei's readout block, in world px: right of her rings at zoom 1, half the size at zoom 2, none while hidden
	var vei := Vector2(1000.0, 500.0)
	var rr := NodeLogic.vei_readout_rect(vei, 40.0, [30.0, 60.0, 90.0], 1.0, {})
	t.ok(rr.size.x > 90.0 and rr.position.x > vei.x + 40.0 - 10.0 and rr.position.x < vei.x + 80.0, "Vei's readout block sits right of her rings: %s" % str(rr))
	var rr2 := NodeLogic.vei_readout_rect(vei, 40.0, [30.0, 60.0, 90.0], 2.0, {})
	t.ok(is_equal_approx(rr2.size.x * 2.0, rr.size.x) and is_equal_approx(rr2.size.y * 2.0, rr.size.y), "at zoom 2 its world size halves: %s" % str(rr2.size))
	var covered := NodeLogic.vei_readout_rect(vei, 40.0, [30.0, 60.0, 90.0], 1.0, NodeLogic.panel_of(1120.0, 0.0, 1.0, 0.0))
	t.ok(covered.size == Vector2.ZERO or covered.end.x <= 1120.0, "under an open card (left edge 1120) it shifts clear or is gone: %s" % str(covered))
	# TipPlacer: the placement state MapHud delegates to
	var pl := TipPlacer.new()
	var open: Array = [Rect2(0, 0, 860, 60)]  # room under the bar, so a card in the way can be dodged
	var first := pl.place(odds, tip, open, Rect2(), vp)
	t.ok(first["moved"] and (first["rect"] as Rect2) == HudLogic.tip_rect(odds, tip, open, vp), "the first call moves the plate to tip_rect's place")
	var again := pl.place(odds, tip, open.duplicate(), Rect2(), vp)
	t.ok(not again["moved"] and again["rect"] == first["rect"], "the same inputs twice: the second call does not move it")
	var over := (first["rect"] as Rect2).grow(10.0)
	var opened := pl.place(odds, tip, open, over, vp)
	t.ok(opened["moved"] and not (opened["rect"] as Rect2).intersects(over) and view.encloses(opened["rect"]), "a card opening over the current rect moves it, and the new rect clears the card: %s" % str(opened["rect"]))
	t.ok(not pl.place(odds, tip, open, over, vp)["moved"], "the card staying put leaves it")
	t.ok(pl.place(odds, tip, open, over, vp, [ro])["moved"], "a map readout appearing moves it")
	pl.reset()
	t.ok(pl.place(odds, tip, open, over, vp, [ro])["moved"], "after reset the next call moves it, though nothing changed")
	var landed := (HudLogic.tip_rect(odds, tip, plates, vp, Rect2(), [ro]))
	var with_ro := TipPlacer.new().place(odds, tip, plates, Rect2(), vp, [ro])
	t.ok(with_ro["rect"] == landed, "the placer passes the readouts to tip_rect")
	# MapHud and world_map name the Game autoload (no headless compile): their wiring is pinned as text
	var hs := FileAccess.get_file_as_string("res://scripts/map/map_hud.gd")
	var i := hs.find("func _tip_plates(")
	var tp := hs.substr(i, hs.find("\nfunc ", i + 1) - i)
	t.ok(i >= 0 and not tp.contains("_relayout()") and tp.contains("_plate_rects"), "_tip_plates reads the cached rects: no layout pass per tick")
	t.ok(hs.contains("_placer.place(word, _tip_size, _tip_plates(), card_r, vp, _tip_readouts(card_r, vp))") and hs.contains("_placer.reset()"), "MapHud places through the TipPlacer, reset on show and hide")
	var ti := hs.find("func _tip_readouts(")
	var tr := hs.substr(ti, hs.find("\nfunc ", ti + 1) - ti)
	t.ok(ti >= 0 and tr.contains("nodes.ctx.zoom, NodeLogic.panel_key(nodes.ctx.panel)]"), "readout cache key carries the nodes' ctx zoom and panel (the rects are built from them, a frame behind the camera)")
	t.ok(tr.contains("nodes.refresh_rev()") and not tr.contains("model.rev"), "the readout cache key carries the rev the nodes' ctx was refreshed at, not model.rev (which moves a frame before the ctx)")
	var ns := FileAccess.get_file_as_string("res://scripts/map/map_nodes.gd")
	var ri := ns.find("func refresh_rev()")
	t.ok(ri >= 0 and ns.substr(ri, ns.find("\nfunc ", ri + 1) - ri).contains("return _rev") and ns.contains("_rev = model.rev"), "MapNodes.refresh_rev() returns the rev its ctx was last refreshed at")
	var wm := FileAccess.get_file_as_string("res://scripts/map/world_map.gd")
	t.ok(wm.contains("hud.nodes = nodes_view") and wm.contains("hud.cam = cam"), "world_map gives the HUD the nodes and the camera")


## The bar tooltip's own place (HudLogic.tip_rect): clear of every HUD text plate, inside the viewport.
func _tip_rect(t: TestUtil) -> void:
	t.suite("map_hud-tip-rect")
	var vp := Vector2(1600.0, 900.0)
	var plates: Array = [Rect2(0, 0, 860, 60), Rect2(0, 60, 560, 48), Rect2(0, 110, 550, 50), Rect2(0, 160, 560, 35),
		Rect2(10, 195, 300, 43), Rect2(10, 245, 490, 260), Rect2(10, 512, 500, 328)]
	var tip := Vector2(420.0, 64.0)
	var odds := Rect2(32, 34, 68, 22)
	var mint := Rect2(12, 6, 36, 20)
	var card := Rect2(1110, 12, 490, 888)
	var view := Rect2(Vector2.ZERO, vp)
	for case in [["row 2 (ODDS)", odds, Rect2()], ["row 1 (MINT)", mint, Rect2()], ["row 2, the card open", odds, card], ["row 1, the card open", mint, card]]:
		var r := HudLogic.tip_rect(case[1], tip, plates, vp, case[2])
		var hit := false
		for p in plates:
			hit = hit or r.intersects(p)
		t.ok(not hit and view.encloses(r) and r.size == tip, "%s: the plate clears every HUD plate and stays on screen: %s" % [case[0], str(r)])
		t.ok(not (case[2] as Rect2).intersects(r), "%s: and the open card" % case[0])
	# a card that really is in the way: the card-less answer lands on it, the card-aware one avoids it and the plates
	var wide := Rect2(600, 12, 1000, 888)
	var sparse: Array = [Rect2(0, 0, 860, 60), Rect2(0, 60, 300, 100)]
	var far := Rect2(500, 34, 68, 22)
	var right_card := Rect2(800, 12, 800, 888)
	var bare := HudLogic.tip_rect(far, tip, sparse, vp)
	t.ok(bare.intersects(right_card), "without the card the plate would sit on it: %s" % str(bare))
	var dodged := HudLogic.tip_rect(far, tip, sparse, vp, right_card)
	t.ok(not dodged.intersects(right_card) and not dodged.intersects(sparse[0]) and not dodged.intersects(sparse[1]) and view.encloses(dodged), "with the card passed it clears the card and the plates, on screen: %s" % str(dodged))
	# the full column and a card across the map: nothing is clear, so the fallback applies (least overlap, clamped on screen)
	var cramped := HudLogic.tip_rect(odds, tip, plates, vp, wide)
	t.ok(HudLogic.tip_rect(odds, tip, plates, vp).intersects(wide) and view.encloses(cramped) and cramped.size == tip, "no clear place: the least-overlapping candidate, still on screen: %s" % str(cramped))
	t.ok(not cramped.intersects(plates[0]) and not cramped.intersects(plates[6]), "and that fallback keeps off the HUD's text plates: %s" % str(cramped))
	var k0 := HudLogic.tip_key(odds, tip, plates, Rect2(), vp)
	t.ok(k0 == HudLogic.tip_key(odds, tip, plates.duplicate(), Rect2(), vp), "tip_key: equal inputs, equal key")
	t.ok(k0 != HudLogic.tip_key(odds, tip, plates, wide, vp), "tip_key: a card opening changes it")
	t.ok(k0 != HudLogic.tip_key(odds, tip, plates.slice(1), Rect2(), vp), "tip_key: a plate going changes it")
	t.ok(k0 != HudLogic.tip_key(mint, tip, plates, Rect2(), vp) and k0 != HudLogic.tip_key(odds, tip, plates, Rect2(), vp + Vector2(1, 0)), "tip_key: the word or the viewport moving changes it")
	_tip_readouts(t, vp, plates, odds, tip)
	var r2 := HudLogic.tip_rect(odds, tip, plates, vp)
	t.ok(r2.position.x >= 560.0 and r2.position.y >= 60.0, "with the column below the goal full, it goes right of the plates under the bar, over the map: %s" % str(r2))
	var roomy := HudLogic.tip_rect(odds, tip, [Rect2(0, 0, 860, 60)], vp)
	t.ok(roomy.position.x == odds.position.x and roomy.position.y >= 60.0 and roomy.position.y < 80.0, "nothing under the bar: just below the word's plate, at its x: %s" % str(roomy))
	# nothing fits cleanly: still inside the viewport (the fallback is documented on tip_rect)
	var tiny := Vector2(300.0, 120.0)
	var small := HudLogic.tip_rect(odds, tip, plates, tiny, Rect2(100, 0, 200, 120))
	t.ok(Rect2(Vector2.ZERO, tiny).encloses(small), "a tiny viewport: the plate is still inside it: %s" % str(small))
	var huge := HudLogic.tip_rect(odds, Vector2(900.0, 400.0), plates, tiny)
	t.ok(Rect2(Vector2.ZERO, tiny).encloses(huge), "a plate larger than the viewport is shrunk into it: %s" % str(huge))
	var tc: Dictionary = MapLogic.cfg()["clarity"]["tooltip"]
	t.ok(float(tc["gap_px"]) > 0.0 and float(tc["margin_px"]) > 0.0 and float(tc["delay_s"]) > 0.0 and float(tc["max_w_px"]) > 100.0, "the placement's numbers are in clarity.tooltip")
	var th := MapUi.tooltip_theme()
	var pbox := th.get_stylebox("panel", "TooltipPanel") as StyleBoxFlat
	t.ok(pbox != null and pbox.bg_color.a >= 0.95, "the shared tooltip theme (the valve's tooltips) still has its TooltipPanel plate")


## The hover lines on the real nodes. MapValve compiles headless, so it is built as the scene builds it
## (model set, then _ready) and its buttons and name labels are read. map_hud.gd names the Game autoload
## and does not compile here: its bar words go through HudLogic.apply_tip, tested on real Labels and
## Buttons, and the scene's calls to it are pinned as text (one per word).
func _tips_on_nodes(t: TestUtil) -> void:
	t.suite("map_hud-tips-on-nodes")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture("midgame_2flips")["ok"], "fixture loads")
	var m := MapModel.new(s)
	m.refresh(true)
	var v := MapValve.new()
	v.model = m
	v._ready()  # not in a tree: the scene's own build, run by hand
	t.ok(v.tooltip_text == HudLogic.tip("mint") and v.mouse_filter == Control.MOUSE_FILTER_STOP, "the valve panel carries the mint line and takes the hover")
	var buttons := {}
	for c in v.get_children():
		if c is Button:
			buttons[(c as Button).text] = c
	for k in ValveLogic.KEYS:
		var b: Button = buttons.get(ValveLogic.NAMES[k])
		t.ok(b != null, "the valve has a %s button" % k)
		if b == null:
			continue
		t.ok(b.tooltip_text == HudLogic.tip(k) and b.tooltip_text != "", "the %s button carries the %s tip" % [k, k])
		t.ok(b.mouse_filter != Control.MOUSE_FILTER_IGNORE, "the %s button takes the hover" % k)
		var nm: Label = v._rows[k]["name"]
		t.ok(nm.tooltip_text == HudLogic.tip(k), "the %s name label carries the %s tip" % [k, k])
		t.ok(nm.mouse_filter == Control.MOUSE_FILTER_PASS, "the %s name label passes the hover (not IGNORE)" % k)
	v.free()
	# the helper the bar's words use, on real nodes
	for node in [Label.new(), Button.new()]:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for id in ["mint", "odds", "odds_backups", "strain", "drain"]:
			HudLogic.apply_tip(node, id)
			t.ok(node.tooltip_text == HudLogic.tip(id) and node.tooltip_text != "" and node.mouse_filter == Control.MOUSE_FILTER_PASS, "apply_tip(%s, %s): the glossary line, hover passed on" % [node.get_class(), id])
		var plain: Control = node.duplicate()
		plain.tooltip_text = ""
		plain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		HudLogic.apply_tip(plain, "nothing")
		t.ok(plain.tooltip_text == "" and plain.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s: an unknown word leaves the node as it was" % node.get_class())
		plain.free()
		node.free()
	# map_hud.gd's calls, pinned as text (MapHud names the Game autoload, so it can't compile headless and can't be built here): the stream words by their item id (MINT among them), then the three status words
	var hud_src := FileAccess.get_file_as_string("res://scripts/map/map_hud.gd")
	t.ok(HudLogic.LABELS.has("mint"), "MINT is a bar item, so the item call carries its tip")
	t.ok(hud_src.contains("HudLogic.apply_tip(parts[\"name\"], str(it[\"id\"]))"), "map_hud.gd tips each stream word by its item id (MINT, BONE, ...)")
	for id in ["odds", "strain", "drain"]:
		t.ok(hud_src.contains("HudLogic.apply_tip(%s_name, \"%s\")" % [id, id]), "map_hud.gd tips the %s word with HudLogic.apply_tip" % id)
	var valve_src := FileAccess.get_file_as_string("res://scripts/map/map_valve.gd")
	t.ok(not valve_src.contains("valve_tip") and not MapLogic.cfg()["clarity"].has("valve_tip"), "no valve_tip: the valve's line is the mint tip")


## C2: the run's goal shows until a fort is taken; the jargon words have config tooltips; nothing
## on the map says "drown Vei".
func _clarity(t: TestUtil) -> void:
	t.suite("map_hud-clarity")
	t.ok(HudLogic.goal_shown({"highest_tier_flipped": 0}), "no fort taken: the goal shows")
	t.ok(HudLogic.goal_shown({}), "a view without the field reads as a new game")
	t.ok(not HudLogic.goal_shown({"highest_tier_flipped": 1}), "a fort taken: the goal is gone")
	t.ok(not HudLogic.goal_shown({"highest_tier_flipped": 0, "won": true}), "won: no goal line")
	var goal := HudLogic.goal_text()
	t.ok(goal == "Your goal: take Vei's forts, then beat Vei. Beating Vei wins the game.\nFLOOD clogs her queue and raises your odds; face her when they're good.", "the goal line is the glossary's, verbatim: " + goal)
	var hits: Array = []
	_the_run_hits(MapLogic.cfg(), "", hits)
	t.ok(hits.is_empty(), "no map_view.json string calls the whole game 'the run': %s" % str(hits))
	t.ok(JSON.stringify(MapLogic.cfg()).contains("\"busy\":\"A raid is already open\""), "a busy refusal says raid")
	t.ok(not goal.to_lower().contains("drown"), "no 'drown Vei' on the goal line")
	for id in ["mint", "odds", "odds_backups", "strain", "drain", "work", "war", "flood"]:
		t.ok(HudLogic.tip(id) != "", "%s has a tooltip line" % id)
	t.ok(HudLogic.tip("nothing") == "", "an unknown word has none")
	t.ok(HudLogic.tip("mint").contains("Raising Pit"), "MINT says where undead come from")
	var mint_line := "Mint: the undead your Raising Pits make each second. The map's valve splits it into WORK (your town's jobs), WAR (your forts) and FLOOD (Vei's queue)."
	var war_line := "WAR sends undead to your forts, spread by distance, with Relish's fort drawing 3× its share. FLOOD sends them into Vei's queue, which raises your odds against her."
	t.ok(HudLogic.tip("mint") == mint_line, "the mint tip is the glossary's line verbatim")
	t.ok(not MapLogic.cfg()["clarity"].has("valve_tip"), "the mint line lives under clarity.tips.mint only")
	_tips_on_nodes(t)
	t.ok(HudLogic.tip("war") == war_line and HudLogic.tip("flood") == war_line, "the WAR and FLOOD tips are the glossary's full line verbatim")
	t.ok(HudLogic.tip("strain") == "How backed up Vei's queue is. ▲ means it's growing (FLOOD is clogging it); ▼ means she's working it down.", "the STRAIN tip is the glossary's line verbatim")
	t.ok(HudLogic.tip("drain") == "How long until Vei's queue empties at this rate. ∞ means it isn't emptying.", "the DRAIN tip is the glossary's line verbatim")
	t.ok(HudLogic.tip("odds") == "Your chance to beat Vei if you faced her now. It grows with time and with her clogged queue.", "the ODDS tip is the pre-P3 line verbatim")
	t.ok(HudLogic.tip("odds_backups") == "Your chance to beat Vei if you faced her now. It grows with time, with her clogged queue and with your backups.", "the ODDS-with-backups tip is the glossary's line verbatim")
	t.ok(not HudLogic.tip("odds").contains("backups"), "the plain ODDS tip never names backups")
	t.ok(HudLogic.odds_tip_id(-1) == "odds" and HudLogic.odds_tip_id(0) == "odds_backups" and HudLogic.odds_tip_id(4) == "odds_backups", "odds_tip_id: backups unknown (-1) is the plain tip, any reported count the backups one")
	var odds_src := FileAccess.get_file_as_string("res://scripts/map/map_hud.gd")
	t.ok(odds_src.contains("HudLogic.odds_tip_id(int(ro[\"backups\"]))") and odds_src.contains("HudLogic.apply_tip(_odds_name, odds_tip)"), "map_hud.gd re-applies the ODDS tip from odds_tip_id on a refresh")
	t.ok(HudLogic.tip("work") == "WORK: your town's jobs", "the WORK tip stands")
	# the legend: clear of the chip and the valve, collapses with no room, unchanged with plenty
	var chip := Rect2(12, 200, 330, 35)
	var valve := Rect2(12, 512, 400, 300)
	var roomy := HudLogic.legend_place(chip, valve, 12.0, 490.0, 240.0, 200.0, 40.0, true, 10.0)
	t.ok(roomy["mode"] == "full" and is_equal_approx((roomy["rect"] as Rect2).end.y, 502.0) and (roomy["rect"] as Rect2).position.y >= chip.end.y + 10.0, "plenty of room: full, just above the valve, under the chip")
	var tight := HudLogic.legend_place(chip, valve, 12.0, 490.0, 330.0, 250.0, 40.0, true, 10.0)
	t.ok(tight["mode"] == "compact" and not (tight["rect"] as Rect2).intersects(chip) and not (tight["rect"] as Rect2).intersects(valve), "no room for full: compact, clear of both")
	t.ok((tight["rect"] as Rect2).position.y >= chip.end.y + 10.0 and (tight["rect"] as Rect2).end.y <= valve.position.y - 10.0, "compact sits between the chip and the valve with the gap kept")
	var nohope := HudLogic.legend_place(chip, valve, 12.0, 490.0, 330.0, 280.0, 40.0, true, 10.0)
	t.ok(nohope["mode"] == "closed", "not even compact fits: collapsed")
	var tall_chip := HudLogic.legend_place(Rect2(12, 200, 330, 120), valve, 12.0, 490.0, 300.0, 250.0, 40.0, true, 10.0)
	t.ok(tall_chip["mode"] == "closed", "a taller chip takes the room: collapsed")
	var far_chip := HudLogic.legend_place(Rect2(900, 200, 330, 120), valve, 12.0, 490.0, 300.0, 250.0, 40.0, true, 10.0)
	t.ok(far_chip["mode"] == "full", "a chip beside the legend's columns does not bound it")
	t.ok(HudLogic.legend_place(chip, valve, 12.0, 490.0, 300.0, 250.0, 40.0, false, 10.0)["mode"] == "closed", "not wanted open: the button")
	t.ok(HudLogic.legend_rows_state("closed", 0.0)["visible"] and HudLogic.legend_rows_state("closed", 0.0)["alpha"] == 0.0, "closed and not yet measured: laid out to measure, but drawn at alpha 0")
	t.ok(not HudLogic.legend_rows_state("closed", 120.0)["visible"] and HudLogic.legend_rows_state("closed", 120.0)["alpha"] == 0.0, "closed once measured: hidden")
	t.ok(HudLogic.legend_rows_state("full", 0.0)["visible"] and HudLogic.legend_rows_state("compact", 120.0)["alpha"] == 1.0, "open: shown and opaque")
	t.ok(HudLogic.legend_settled_first(0.0, 90.0) and not HudLogic.legend_settled_first(90.0, 92.0) and not HudLogic.legend_settled_first(0.0, 0.0), "the key is cleared only when the settled height is first set")
	t.ok(not JSON.stringify(MapLogic.cfg().get("opening", {})).to_lower().contains("drown"), "the opening's lines do not say drown")
	# the card rises to the screen's top only where the HUD's plates leave it room
	t.ok(HudLogic.sidebar_top(1600.0, 338.0, 1000.0, 12.0, 150.0, 12.0) == 12.0, "1600 wide, plates end at 1000: the card starts at the top")
	t.ok(HudLogic.sidebar_top(1280.0, 338.0, 1000.0, 12.0, 150.0, 12.0) == 150.0, "1280 wide: the plates reach the card's column, so it starts under them")
	t.ok(HudLogic.sidebar_top(1600.0, 338.0, 1255.0, 12.0, 150.0, 12.0) == 150.0, "the gap is kept clear of the plates")
	# the fort legend: open by default until the player closes it; then as they left it
	t.ok(HudLogic.legend_open(-1), "legend open by default")
	t.ok(HudLogic.legend_open(HudLogic.legend_user(false)), "no earlier close: open")
	t.ok(not HudLogic.legend_open(0), "a close sticks")
	t.ok(not HudLogic.legend_open(HudLogic.legend_user(true)), "a close remembered from an earlier game: closed")
	t.ok(HudLogic.legend_open(1), "a reopen sticks")
	var lroom := HudLogic.legend_place(chip, valve, 12.0, 490.0, 330.0, 250.0, 40.0, HudLogic.legend_open(-1), 10.0)
	t.ok(lroom["mode"] == "compact", "default open, no room for full: compact")
	t.ok(HudLogic.legend_place(chip, valve, 12.0, 490.0, 330.0, 280.0, 40.0, HudLogic.legend_open(-1), 10.0)["mode"] == "closed", "default open, no room even for compact: collapses")
	t.ok(HudLogic.legend_place(chip, valve, 12.0, 490.0, 240.0, 200.0, 40.0, HudLogic.legend_open(0), 10.0)["mode"] == "closed", "closed by the player: the button even with room")
	# the held row's tag line names each word the chip can show
	var tag := HudLogic.held_tag_line()
	for m in [IdleLogic.SAFE, IdleLogic.THIN, IdleLogic.WILL_FALL]:
		t.ok(IdleLogic.word(m) != "" and tag.contains(IdleLogic.word(m)), "the legend's tag line names %s" % IdleLogic.word(m))
	t.ok(not tag.to_lower().contains("lost"), "the tag line does not say a will-fall fort is lost (it is still held until Vei wins it)")
	t.ok(tag.contains("Vei is set to retake it"), "WILL FALL means Vei is set to retake it")
	t.ok(tag.length() <= 110 and tag.contains("Relish"), "the tag line is short (%d chars) and says Relish helps" % tag.length())
	# the player's close is MapSeen's global key: across a new game, in memory when it cannot write
	MapSeen.forget_memory()
	var spath := "user://test_map_hud_legend_seen.cfg"
	var sw := MapSeen.new(spath, true)
	sw.reconcile("g1")
	t.ok(not sw.get_global(MapSeen.LEGEND_CLOSED), "no close yet")
	sw.set_global(MapSeen.LEGEND_CLOSED, true)
	sw.mark(MapSeen.VALVE)
	MapSeen.forget_memory()
	var sr := MapSeen.new(spath, true)
	t.ok(sr.get_global(MapSeen.LEGEND_CLOSED), "the close is read back from the file")
	sr.reconcile("g2")  # a new game forgets the per-game flags, not the player's choice
	MapSeen.forget_memory()
	var sn := MapSeen.new(spath, true)
	t.ok(sn.get_global(MapSeen.LEGEND_CLOSED) and not sn.has(MapSeen.VALVE), "a new game keeps the close and forgets the game's flags")
	sn.set_global(MapSeen.LEGEND_CLOSED, false)
	t.ok(not MapSeen.new(spath, true).get_global(MapSeen.LEGEND_CLOSED), "a reopen is kept")
	var sm := MapSeen.new(spath, false)  # a session that cannot write: memory only
	sm.set_global(MapSeen.LEGEND_CLOSED, true)
	t.ok(sm.get_global(MapSeen.LEGEND_CLOSED), "a read-only session keeps the close in memory")
	MapSeen.forget_memory()
	t.ok(not MapSeen.new(spath, true).get_global(MapSeen.LEGEND_CLOSED), "and never wrote it to the file")
	MapSeen.forget_memory()
	DirAccess.remove_absolute(spath)
	t.ok(HudLogic.legend_glyph_state("held") == IdleLogic.SAFE and HudLogic.legend_glyph_state("overrun") == NodeLogic.OVERRUN and HudLogic.legend_glyph_state("hers") == NodeLogic.HERS and HudLogic.legend_glyph_state("retaken") == NodeLogic.HERS, "each legend row draws the map's own state glyph")
	var lc: Dictionary = MapLogic.cfg()["clarity"]["legend"]
	t.ok((lc["rows"] as Array).size() == 4, "four states in the legend")
	var lplate := Palette.c("ground").lightened(float(MapLogic.cfg()["panel_bg_lighten"]))
	lplate.a = float(lc["plate_alpha"])
	var lbright := ""
	for k in Palette.keys():
		if lbright == "" or MapLogic.luminance(Palette.c(k)) > MapLogic.luminance(Palette.c(lbright)):
			lbright = k
	var lthrough := Palette.c(lbright).lerp(lplate, lplate.a)  # the brightest key showing through the plate's alpha
	for row in lc["rows"]:
		for key in [str(row["key"]), "text_dim"]:
			var lr := MapLogic.contrast_ratio(Palette.c(key), lthrough)
			t.ok(lr >= 4.5, "legend %s (%s) reads %.1f:1 on its plate (>= 4.5)" % [row["word"], key, lr])
	t.ok(int(MapLogic.cfg()["font_label"]) >= 12, "legend text is at least 12 px")
	# the goal's plate is the bar's: its text reads 4.5:1 over the brightest key showing through
	var a := float(MapLogic.cfg()["topbar_plate_alpha"])
	var bright := ""
	for k in Palette.keys():
		if bright == "" or MapLogic.luminance(Palette.c(k)) > MapLogic.luminance(Palette.c(bright)):
			bright = k
	var through := Palette.c("ground").lerp(Palette.c(bright), 1.0 - a)
	t.ok(MapLogic.contrast_ratio(Palette.c("text"), through) >= 4.5, "the goal's text reads 4.5:1 on the strip's plate")
	var hs := FileAccess.get_file_as_string("res://scripts/map/map_hud.gd")
	t.ok(hs.contains("_goal = _label(int(cfg[\"clarity\"][\"goal_size_px\"]), \"text\")") and hs.contains("MapType.style_label(_goal, \"text\", int(cfg[\"clarity\"][\"goal_size_px\"]))"), "the goal is drawn in the text colour at clarity.goal_size_px")
	t.ok(int(MapLogic.cfg()["clarity"]["goal_size_px"]) >= int(MapLogic.cfg()["objective_size_px"]) + 2 and int(MapLogic.cfg()["clarity"]["goal_size_px"]) >= 15, "the goal is at least 2 px over its old 13 px")
	# the bar's hover cue sits on the same plate
	var cue_key := str(MapLogic.cfg()["clarity"]["hover_cue_key"])
	var cue_ratio := MapLogic.contrast_ratio(Palette.c(cue_key), through)
	t.ok(cue_ratio >= 4.5, "the hover cue (%s) reads %.1f:1 on the bar's plate (>= 4.5)" % [cue_key, cue_ratio])
	t.ok(HudLogic.hover_cue() == "hover a word for what it means", "the cue's words")
	# the tooltip's own plate: opaque, and its text reads on it
	var ts := HudLogic.tooltip_style()
	var plate: Color = ts["plate"]
	t.ok(plate.a >= 0.95, "the tooltip plate is at least 0.95 opaque (%.2f)" % plate.a)
	var tt_ratio := MapLogic.contrast_ratio(Palette.c("text"), Palette.c(lbright).lerp(plate, plate.a))
	t.ok(tt_ratio >= 4.5 and ts["text"] == Palette.c("text"), "tooltip text reads %.1f:1 on its plate over the brightest key (>= 4.5)" % tt_ratio)
	t.ok(int(ts["size"]) >= 12 and int(ts["pad"]) >= 3, "tooltip text is at least 12 px with padding")
	var th := MapUi.tooltip_theme()
	var pbox := th.get_stylebox("panel", "TooltipPanel") as StyleBoxFlat
	t.ok(pbox != null and pbox.bg_color.a >= 0.95 and pbox.border_width_left == 1 and pbox.bg_color.is_equal_approx(plate), "the theme's TooltipPanel is the opaque plate with a 1 px border")
	t.ok(th.get_color("font_color", "TooltipLabel") == Palette.c("text") and th.get_font_size("font_size", "TooltipLabel") == int(ts["size"]), "the theme's TooltipLabel is the text colour at the HUD size")


## Every string value of the config that says "the run" / "A run" for the game (code keys are not values).
func _the_run_hits(v: Variant, path: String, found: Array) -> void:
	if v is Dictionary:
		for k in v:
			_the_run_hits(v[k], path + "/" + str(k), found)
	elif v is Array:
		for i in v.size():
			_the_run_hits(v[i], path + "/" + str(i), found)
	elif v is String:
		var re := RegEx.create_from_string("(?i)(\\bthe run\\b|^run\\b|\\ba run\\b)")
		if re.search(v as String) != null:
			found.append(path)


func _type(t: TestUtil) -> void:
	t.suite("map_hud-type")
	var want := tan(deg_to_rad(9.0))
	var rf := MapType.rate_font()
	var mf := MapType.mass_font()
	var lf := MapType.label_font()
	var tf := MapType.title_font()
	t.near(rf.variation_transform.y.x, want, 1e-4, "rate font is skewed 9 degrees")
	t.near(rf.variation_transform.x.y, 0.0, 1e-6, "the skew only shears")
	t.ok(rf.variation_embolden < 0.0, "rate font is lighter")
	t.near(mf.variation_transform.y.x, 0.0, 1e-6, "mass font is upright")
	t.ok(mf.variation_embolden > 0.0, "mass font is heavier")
	t.ok(mf.variation_embolden > lf.variation_embolden and lf.variation_embolden > rf.variation_embolden, "weights run rate < label < mass")
	t.near(lf.variation_transform.y.x, 0.0, 1e-6, "label font is upright")
	t.near(tf.variation_transform.y.x, 0.0, 1e-6, "title font is upright")
	t.ok(MapType.rate_font() == rf and MapType.mass_font() == mf, "fonts are cached")
	for key in ["size_rate", "size_mass", "size_label", "size_title", "size_stock"]:
		t.ok(MapType.size_of(key) >= 12, "%s is at least 12 px" % key)
	t.ok(int(MapLogic.cfg()["callouts"]["size_px"]) >= 12, "callout text is at least 12 px")
	t.ok(int(MapLogic.cfg()["objective_size_px"]) >= 12, "objective strip is at least 12 px")
	var l := Label.new()
	MapType.style_rate(l)
	t.ok(l.get_theme_font("font") == rf and l.get_theme_font_size("font_size") == MapType.size_of("size_rate"), "style_rate sets the rate font and size")
	MapType.style_mass(l, "text_dim", 13)
	t.ok(l.get_theme_font("font") == mf and l.get_theme_font_size("font_size") == 13, "style_mass takes a size override")
	t.ok(l.get_theme_color("font_color").is_equal_approx(Palette.c("text_dim")), "style_mass takes a palette key")
	MapType.style_label(l)
	t.ok(l.get_theme_font("font") == lf, "style_label sets the label font")
	l.free()


func _contrast(t: TestUtil) -> void:
	t.suite("map_hud-contrast")
	var cfg := MapLogic.cfg()
	var panel := Palette.c("ground").lightened(float(cfg["panel_bg_lighten"]))
	var grounds := {"ground": Palette.c("ground"), "panel": panel}
	# the HUD plate: ground at topbar_plate_alpha, with the brightest map content (vei) showing
	# through at 1 - alpha
	var a := float(cfg["topbar_plate_alpha"])
	var bright_key := ""
	for k in Palette.keys():
		if bright_key == "" or MapLogic.luminance(Palette.c(k)) > MapLogic.luminance(Palette.c(bright_key)):
			bright_key = k
	var through := Palette.c("ground").lerp(Palette.c(bright_key), 1.0 - a)
	for key in ["text", "text_dim", "undead", "danger", "select"]:
		var r := MapLogic.contrast_ratio(Palette.c(key), through)
		t.ok(r >= 4.5, "%s on the top-bar plate over the brightest palette key (%s) is %.1f:1 (>= 4.5)" % [key, bright_key, r])
	t.ok(a > 0.0 and a <= 1.0, "plate alpha in range")
	for key in ["text", "text_dim", "undead", "danger", "select"]:
		for g in grounds:
			var r := MapLogic.contrast_ratio(Palette.c(key), grounds[g])
			t.ok(r >= 4.5, "%s on %s is %.1f:1 (>= 4.5)" % [key, g, r])


## The BONE item's pits-first warning: the mill's stall, or the queue head that can never be afforded.
func _bone_line(t: TestUtil) -> void:
	t.suite("map_hud-bone-line")
	var pits := {"starved": "pits_first", "lever": "raise_war"}
	var none := {"starved": "", "lever": ""}
	var bodies := {"starved": "no_bodies", "lever": ""}
	var names := {"inn": "Inn"}
	var stalled := {"building_id": "inn", "level": 1, "status": "waiting_funds", "reason": "no_bone", "affordable_in_s": -1.0,
		"short": {"gold": 0.0, "bone": 6.2}, "starved": "pits_first", "lever": "raise_war"}
	t.ok(HudLogic.bone_line(none, {}, names) == "", "no stall: nothing to say")
	t.ok(HudLogic.bone_line({}, {}, names) == "", "no mill row: nothing to say")
	t.ok(HudLogic.bone_line(pits, {}, names) == "no bone: the pits eat every body. Raise WAR", "mill pits_first: the stall and the lever, as config words: " + HudLogic.bone_line(pits, {}, names))
	var head := HudLogic.bone_line(pits, stalled, names)
	t.ok(head == "Inn: never, 7 bone short. The pits eat every body: raise WAR", "a stalled head is named with a never ETA and what it lacks: " + head)
	t.ok(not head.contains(":0") and not head.contains(" in ") and not head.contains("m "), "a never ETA carries no number of time")
	t.ok(HudLogic.bone_line(none, stalled, names) == head, "the head alone (the mill row between steps) reads the same")
	var timed := stalled.duplicate()
	timed["affordable_in_s"] = 90.0
	timed["starved"] = ""
	timed["lever"] = ""
	t.ok(HudLogic.bone_line(pits, timed, names) == "no bone: the pits eat every body. Raise WAR", "a timed wait is not a stall: the mill's line stands")
	t.ok(HudLogic.bone_line(bodies, {}, names) == "", "no_bodies is not pits first: no raise WAR line")
	var bod_head := stalled.duplicate()
	bod_head["starved"] = "no_bodies"
	bod_head["lever"] = ""
	t.ok(HudLogic.bone_line(bodies, bod_head, names) == "", "a no_bodies head says nothing either")
	t.ok(HudLogic.bone_line(pits, stalled, {}).begins_with("Inn: never"), "no name table: the id, capitalised")
	var bl: Dictionary = MapLogic.cfg()["bone_line"]
	t.ok(HudLogic.lever_text("raise_war") == "Raise WAR" and bl["levers"]["raise_war"] == "Raise WAR", "the lever's words come from config, keyed by the view's lever")
	var cfg := MapLogic.cfg()
	var a := float(cfg["topbar_plate_alpha"])
	var bright := ""
	for k in Palette.keys():
		if bright == "" or MapLogic.luminance(Palette.c(k)) > MapLogic.luminance(Palette.c(bright)):
			bright = k
	var through := Palette.c("ground").lerp(Palette.c(bright), 1.0 - a)
	var r := MapLogic.contrast_ratio(Palette.c(str(bl["key"])), through)
	t.ok(r >= 4.5, "the bone warning (%s) reads 4.5:1 on the bar plate (%.1f)" % [bl["key"], r])


func _hud(rates: Array, extra := {}) -> Dictionary:
	var d := {"rates": rates, "odds": 0.0, "sign": 0, "drain_s": -1.0, "time_scale": 1.0, "won": false}
	d.merge(extra, true)
	return d


func _rate(id: String, rate: float, stock: float, cap := -1.0) -> Dictionary:
	return {"id": id, "rate": rate, "stock": stock, "cap": cap, "unit": "x/s"}


func _bar(t: TestUtil) -> void:
	t.suite("map_hud-bar")
	var rates: Array = []
	for id in GameState.HUD_RATE_IDS:
		rates.append(_rate(id, 0.0, -1.0 if id == "mint" else 10.0))
	var items := HudLogic.rate_items(_hud(rates))
	t.ok(items.size() == GameState.HUD_RATE_IDS.size(), "one item per stream")
	var ids: Array = items.map(func(i): return i["id"])
	t.ok(ids == Array(GameState.HUD_RATE_IDS), "items follow HUD_RATE_IDS order")
	t.ok(items.all(func(i): return str(i["rate_text"]).ends_with("/s")), "every rate ends in /s")
	t.ok(items.all(func(i): return str(i["rate_text"]) == "+0.0/s"), "E1: every rate reads +0.0/s")
	t.ok(items[0]["stock_text"] == "", "mint has no stock")
	t.ok(items[1]["stock_text"] == "10", "a stock reads as a mass")
	t.ok(items.all(func(i): return not i["capped"] and i["cap_mark"] == ""), "no cap marker below cap")
	var sw := HudLogic.rate_items(_hud([_rate("workers", -2.34, 1234.0), _rate("bodies", 0.05, 40.0, 200.0)]))
	t.ok(sw[0]["rate_text"] == "−2.3/s", "a negative net uses the minus sign (%s)" % sw[0]["rate_text"])
	t.ok(sw[0]["stock_text"] == "1,234", "stock has thousands separators")
	t.ok(sw[1]["rate_text"] == "+0.05/s", "a faint rate gets two decimals")
	t.ok(sw[1]["stock_text"] == "40/200" and not sw[1]["capped"], "a capped stream shows /cap, no marker under it")
	var full := HudLogic.rate_items(_hud([_rate("living", 0.0, 16.0, 16.0), _rate("bodies", 0.0, 250.0, 200.0), _rate("gold", 0.0, 99999.0, -1.0)]))
	t.ok(full[0]["capped"] and full[0]["cap_mark"] != "", "at cap: marker")
	t.ok(full[1]["capped"], "over cap counts as at cap")
	t.ok(not full[2]["capped"] and full[2]["stock_text"] == "99,999", "uncapped never marks")
	t.ok(HudLogic.rate_items({}).is_empty(), "no rates, no items")


func _tithe_line(t: TestUtil) -> void:
	t.suite("map_hud-tithe-line")
	var names := {"ashgate": "Ashgate"}
	var wave := HudLogic.tithe_line({"target": "ashgate", "eta_s": 0.0, "warning": false, "wave_active": true, "next_target": "greywall", "next_s": 900.0}, names)
	t.ok(wave["text"] == "Tithe wave at Ashgate now" and wave["fort_id"] == "ashgate", "wave running")
	var warn := HudLogic.tithe_line({"target": "ashgate", "eta_s": 105.0, "warning": true, "wave_active": false, "next_target": "ashgate", "next_s": 105.0}, names)
	t.ok(warn["text"] == "Tithe wave at Ashgate in 1:45" and warn["fort_id"] == "ashgate", "warning with its ETA")
	var nxt := HudLogic.tithe_line({"target": "", "eta_s": -1.0, "warning": false, "wave_active": false, "next_target": "ashgate", "next_s": 750.0}, names)
	t.ok(nxt["text"] == "Next tithe: Ashgate in 12:30" and nxt["fort_id"] == "ashgate", "next pick with next_s")
	var far := HudLogic.tithe_line({"next_target": "ashgate", "next_s": 5430.0}, names)
	t.ok(far["text"] == "Next tithe: Ashgate in 1h 30m", "an hour out reads Nh Mm")
	t.ok(HudLogic.tithe_line({"next_target": "greywall", "next_s": 60.0}, names)["text"] == "Next tithe: Greywall in 1:00", "an unnamed fort falls back to its id")
	var none := {"text": "", "fort_id": ""}
	t.ok(HudLogic.tithe_line({"target": "", "eta_s": -1.0, "next_target": "", "next_s": -1.0}, names) == none, "before Vei's clock: nothing")
	t.ok(HudLogic.tithe_line({"next_target": "ashgate", "next_s": -1.0}, names) == none and HudLogic.tithe_line({}, names) == none, "no next_s or an empty view: nothing")


func _status(t: TestUtil) -> void:
	var gap := float(MapLogic.cfg()["toast_gap_px"])
	t.ok(HudLogic.toast_top(200.0, 90.0, gap) == 200.0 + gap, "the toast sits a gap under a two-row bar's chip, below its bottom edge")
	t.ok(HudLogic.toast_top(130.0, 90.0, gap) >= 130.0 + gap and HudLogic.toast_top(0.0, 90.0, gap) == 90.0 + gap, "one row: under the chip; no chip yet: under the inset")
	t.ok(not MapLogic.cfg().has("toast_top_px"), "the fixed toast_top_px is gone")
	t.suite("map_hud-status")
	var hold := HudLogic.status(_hud([], {"odds": 0.614, "sign": 0, "drain_s": -1.0}))
	t.ok(hold["odds_text"] == "61%", "odds are an integer percent (%s)" % hold["odds_text"])
	t.ok(hold["sign_text"] == "holding" and hold["sign"] == 0, "sign 0 reads holding")
	t.ok(hold["drain_text"] == "∞", "drain_s = -1 reads ∞")
	var up := HudLogic.status(_hud([], {"sign": 1, "drain_s": 520.0, "odds": 1.0}))
	t.ok(up["sign_text"] == "▲" and up["drain_text"] == "8m 40s" and up["odds_text"] == "100%", "up: ▲, a time, 100%")
	var down := HudLogic.status(_hud([], {"sign": -1}))
	t.ok(down["sign_text"] == "▼", "down: ▼")
	var empty := HudLogic.status({})
	t.ok(empty["odds_text"] == "0%" and empty["sign_text"] == "holding" and empty["drain_text"] == "∞", "an empty hud is safe")
	t.ok(HudLogic.speed_text(_hud([], {"time_scale": 1.0})) == "" and HudLogic.speed_text(_hud([], {"time_scale": 10.0})) == "×10", "the speed tag shows only off 1x")
	var cfg := MapLogic.cfg()
	t.ok(HudLogic.objective_text(_hud([])) == cfg["objective_text"], "the objective line")
	t.ok(HudLogic.objective_text(_hud([], {"won": true})) == cfg["objective_won_text"], "the victory line when won")
	t.ok(cfg["objective_text"] != cfg["objective_won_text"], "the two differ")


func _callout_text(t: TestUtil) -> void:
	t.suite("map_hud-callout-text")
	var names := {"covington": "Covington", "ashgate": "Ashgate", "vei": "Vei"}
	var war := {"id": "war:covington:ashgate", "from": "covington", "to": "ashgate", "kind": "war", "rate": 1.2, "bias": 1.0, "why": "Relish left"}
	t.ok(HudLogic.callout_text(war, names) == "WAR → Ashgate +1.2/s · Relish left", "callout reads like the law's example (%s)" % HudLogic.callout_text(war, names))
	var neg := war.duplicate()
	neg["rate"] = -1.2
	t.ok(HudLogic.callout_text(neg, names) == "WAR → Ashgate −1.2/s · Relish left", "negative rates use the minus sign")
	var parts := HudLogic.callout_parts(war, names)
	t.ok(parts["rate"] == "+1.2/s" and parts["head"] == "WAR → Ashgate " and parts["tail"] == " · Relish left", "parts split head, rate, tail")
	var flood := {"kind": "flood", "from": "ashgate", "to": "vei", "rate": 3.0, "why": "valve"}
	t.ok(HudLogic.callout_text(flood, names) == "FLOOD → Vei +3.0/s · valve", "kind upper-case, destination from names")
	var unknown := {"kind": "haul", "from": "x", "to": "old-sluice", "rate": 0.0, "why": "held"}
	t.ok(HudLogic.callout_text(unknown, names) == "HAUL → Old Sluice +0.0/s · held", "an unnamed id falls back to a capitalised id (%s)" % HudLogic.callout_text(unknown, names))
	var silent := war.duplicate()
	silent["why"] = ""
	t.ok(HudLogic.callout_text(silent, names) == "" and HudLogic.callout_parts(silent, names).is_empty(), "empty why: no callout")
	for kind in ["war", "flood", "dead", "living", "haul", "redirect", "work"]:
		var row := {"kind": kind, "to": "vei", "rate": 1.0, "why": "valve"}
		t.ok(HudLogic.callout_text(row, names).begins_with(kind.to_upper() + " → "), "%s is upper-case" % kind)


func _callout_rows(t: TestUtil) -> void:
	t.suite("map_hud-callout-rows")
	var rows := [
		{"id": "a", "rate": 1.0, "why": "valve"},
		{"id": "b", "rate": 9.0, "why": ""},
		{"id": "c", "rate": -5.0, "why": "held"},
		{"id": "d", "rate": 5.0, "why": "retaken"},
		{"id": "e", "rate": 0.0, "why": "staging"},
	]
	var out := HudLogic.callout_rows(rows)
	var ids: Array = out.map(func(r): return r["id"])
	t.ok(ids == ["c", "d", "a", "e"], "only rows with a why, loudest first, ties in input order (%s)" % str(ids))
	t.ok(HudLogic.callout_rows([]).is_empty(), "no rows, none")


func _drag_cap(t: TestUtil) -> void:
	t.suite("map_hud-drag-cap")
	var cfg: Dictionary = MapLogic.cfg()["callouts"]
	t.ok(HudLogic.callout_cap(false) == int(cfg["max_count"]) and int(cfg["max_count"]) == 8, "off a drag, max_count")
	t.ok(HudLogic.callout_cap(true) == 4 and int(cfg["drag_max_count"]) == 4, "during a drag, drag_max_count (4)")
	var lanes: Array = []
	for i in 7:
		lanes.append({"id": "l%d" % i, "from": "a%d" % i, "to": "b%d" % i, "kind": "war", "rate": float(i) - 3.0, "why": "valve%d" % i})
	var items := HudLogic.callout_items(lanes, 3)
	var size := Vector2(60, 20)
	var opts: Array = []
	for i in items.size():
		opts.append(HudLogic.candidate_rects(Vector2(300.0 * i, 100.0), size, Vector2(16, 26)))
	var picks := HudLogic.place(opts, HudLogic.callout_cap(true), 4.0)
	var placed := []
	for i in picks.size():
		if picks[i] >= 0:
			placed.append(str(items[i]["id"]))
	t.ok(placed.size() == 4, "seven callouts fit but a drag shows four (%d)" % placed.size())
	t.ok(placed == ["l0", "l6", "l1", "l5"], "the four with the largest |rate|: %s" % str(placed))
	var open_picks := HudLogic.place(opts, HudLogic.callout_cap(false), 4.0)
	t.ok(open_picks.filter(func(k): return k >= 0).size() == 7, "off a drag all seven place")
	var folded := HudLogic.callout_items([
		{"id": "x1", "from": "covington", "to": "a", "kind": "war", "rate": 1.0, "why": "valve"},
		{"id": "x2", "from": "covington", "to": "b", "kind": "war", "rate": 1.0, "why": "valve"},
		{"id": "x3", "from": "covington", "to": "c", "kind": "war", "rate": 1.0, "why": "valve"},
		{"id": "y", "from": "a", "to": "b", "kind": "flood", "rate": 0.5, "why": "tithe"}], 3)
	t.ok(folded.size() == 2 and bool(folded[0].get("group", false)), "collapsing still folds inside the cap")


func _rects_key(t: TestUtil) -> void:
	t.suite("map_hud-rects-key")
	var a := [Rect2(10, 20, 40, 12), Rect2(100, 100, 40, 12)]
	var b := [Rect2(10, 20, 40, 12), Rect2(100, 100, 40, 12)]
	t.ok(HudLogic.rects_key(a) == HudLogic.rects_key(b), "the same chip rects give the same key")
	var moved := [Rect2(10, 20, 40, 12), Rect2(100, 118, 40, 12)]
	t.ok(HudLogic.rects_key(a) != HudLogic.rects_key(moved), "a chip that moved gives a new key (a re-place)")
	var sub := [Rect2(10.2, 20.1, 40, 12), Rect2(100.3, 100.0, 40, 12)]
	t.ok(HudLogic.rects_key(a) == HudLogic.rects_key(sub), "a sub-pixel drift does not re-place")
	t.ok(HudLogic.rects_key([]) == [], "no chips, an empty key")


## The callouts' label rects and the legend's refresh run only when their keys change.
func _layer_keys(t: TestUtil) -> void:
	t.suite("map_hud-layer-keys")
	t.ok(HudLogic.label_key(3, 1.0, "mid", 5) == HudLogic.label_key(3, 1.0, "mid", 5), "the same label inputs give the same key")
	t.ok(HudLogic.label_key(3, 1.0, "mid", 5) == HudLogic.label_key(3, 1.0004, "mid", 5), "a sub-thousandth zoom drift does not change it")
	for alt in [HudLogic.label_key(4, 1.0, "mid", 5), HudLogic.label_key(3, 1.2, "mid", 5), HudLogic.label_key(3, 1.0, "near", 5), HudLogic.label_key(3, 1.0, "mid", 6)]:
		t.ok(alt != HudLogic.label_key(3, 1.0, "mid", 5), "a changed rev, zoom, tier or fort count changes the label key")
	var chip := Rect2(12, 60, 330, 100)
	var valve := Rect2(12, 600, 300, 120)
	var area := Vector2(1280, 720)
	var k0 := HudLogic.legend_key(area, true, -1, chip, valve, 4, 300.0)
	t.ok(HudLogic.legend_key(area, true, -1, chip, valve, 4, 300.0) == k0, "the same legend inputs give the same key")
	t.ok(HudLogic.legend_key(area, true, -1, chip, valve, 4, 312.0) != k0, "only the measured min heights changing (wrapped rows settling) changes the key")
	for alt in [HudLogic.legend_key(Vector2(1000, 720), true, -1, chip, valve, 4, 300.0), HudLogic.legend_key(area, false, -1, chip, valve, 4, 300.0),
			HudLogic.legend_key(area, true, 1, chip, valve, 4, 300.0), HudLogic.legend_key(area, true, -1, Rect2(12, 60, 330, 140), valve, 4, 300.0),
			HudLogic.legend_key(area, true, -1, chip, Rect2(12, 560, 300, 160), 4, 300.0), HudLogic.legend_key(area, true, -1, chip, valve, 5, 300.0)]:
		t.ok(alt != k0, "a changed size, open flag, click, chip rect, valve rect or row count changes the legend key")
	# the real legend (it names no autoload), outside a tree: _ready by hand, then _process. A refresh rewrites
	# offset_top, so a sentinel there that survives _process proves the key gated it.
	var lg := MapLegend.new()
	lg.model = MapModel.new(GameState.new(TestUtil.configs()))
	lg._ready()
	for _i in 4:  # the first frames settle the wrapped rows' heights (each resets the key)
		lg._process(0.0)
	lg.offset_top = 12345.0
	lg._process(0.0)
	t.ok(lg.offset_top == 12345.0, "MapLegend._process: the same inputs, no refresh")
	var chip_ctl := Control.new()
	chip_ctl.size = Vector2(330, 100)
	lg.chip = chip_ctl
	lg._process(0.0)
	t.ok(lg.offset_top != 12345.0, "MapLegend._process: the Relish chip's rect changing refreshes it")
	chip_ctl.free()
	lg.free()


func _placement(t: TestUtil) -> void:
	t.suite("map_hud-placement")
	var size := Vector2(120, 20)
	var c := HudLogic.candidate_rects(Vector2(100, 100), size, Vector2(16, 26))
	t.ok(c.size() == 4, "four candidate rects around an anchor")
	t.ok(c.all(func(r): return r.size == size), "candidates keep the plate size")
	t.ok(c.all(func(r): return not r.has_point(Vector2(100, 100))), "no candidate covers its own anchor")
	t.ok(c[0].position.x > 100.0 and c[0].end.y < 100.0, "first candidate is up and to the right")
	var le := HudLogic.leader_end(c[0], Vector2(100, 100))
	t.ok(c[0].grow(0.01).has_point(le), "the leader ends on its plate")
	# three plates anchored at the same spot: the candidates cannot all fit
	var opts: Array = []
	for i in 6:
		opts.append(HudLogic.candidate_rects(Vector2(100, 100), size, Vector2(16, 26)))
	var picks := HudLogic.place(opts, 99, 4.0)
	t.ok(picks.size() == opts.size(), "one pick per option")
	var placed: Array[Rect2] = []
	for i in picks.size():
		if picks[i] >= 0:
			placed.append(opts[i][picks[i]])
	t.ok(placed.size() == 4, "four stacked anchors place four plates and skip two (%d)" % placed.size())
	var clash := false
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			if placed[i].grow(4.0).intersects(placed[j]):
				clash = true
	t.ok(not clash, "no two placed plates intersect (gap included)")
	var capped := HudLogic.place(opts, 2, 4.0)
	t.ok(capped.count(-1) == opts.size() - 2, "the cap leaves at most 2 placed")
	t.ok(capped[0] >= 0 and capped[1] >= 0, "the cap keeps the first (loudest) ones")
	var far: Array = [[Rect2(0, 0, 10, 10)], [Rect2(500, 500, 10, 10)]]
	t.ok(HudLogic.place(far, 5, 4.0) == [0, 0], "well-separated plates all place")
	t.ok(HudLogic.place([], 5, 4.0).is_empty(), "nothing in, nothing out")
	# a callout candidate over a fort's name label is rejected for the next candidate (C2 item 3)
	var anchor := Vector2(300, 300)
	var lab_rects := NodeLogic.fort_label_rects(60.0, -1.0, 12)
	t.ok(lab_rects.size() == 1, "a fort with no tag has one label rect")
	var lab: Rect2 = lab_rects[0]
	lab.position += anchor
	var over := Rect2(lab.position + Vector2(5, 2), Vector2(80, 20))
	var clear := Rect2(lab.position + Vector2(0, 80), Vector2(80, 20))
	t.ok(over.intersects(lab), "the first candidate sits on the label")
	t.ok(HudLogic.place([[over, clear]], 5, 4.0, [lab]) == [1], "the candidate over a label is rejected for the next")
	t.ok(HudLogic.place([[over]], 5, 4.0, [lab]) == [-1], "no clear candidate: the callout is skipped")
	# the tag's plate is occupied too: a rect under the name but over the tag line is rejected
	var two := NodeLogic.fort_label_rects(60.0, 140.0, 12)
	t.ok(two.size() == 2, "a tagged fort has a name rect and a tag rect")
	t.ok(two[1].position.y > two[0].position.y and two[1].size.x > two[0].size.x, "the tag plate sits under the name and is wider here")
	t.ok(HudLogic.place([[two[1].grow(-2.0)]], 5, 0.0, two) == [-1], "a candidate over the tag plate is rejected")
	# the rects are the plates draw_label draws: pad, ascent and height from the nodes config
	var n := NodeLogic.ncfg()
	var want := Rect2(-30.0 - float(n["plate_pad_px"]), 12.0 - 12.0 * float(n["plate_ascent"]), 60.0 + 2.0 * float(n["plate_pad_px"]), 12.0 * float(n["plate_height"]))
	t.ok(lab_rects[0].is_equal_approx(want), "the name's rect is draw_label's plate for dy = font size")
	t.ok(NodeLogic.label_plate(-30.0, 60.0, 12, 12.0).is_equal_approx(want), "label_plate is what draw_label draws")


## The top bar and Vei's node read one MapModel.readout(): identical odds, sign and drain, with
## and without the --nodes=demo overlay.
func _one_source(t: TestUtil) -> void:
	t.suite("map_hud-one-source")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	for demo in [false, true]:
		var m := MapModel.new(s)
		m.nodes_demo = demo
		m.flip_cfg = TestUtil.configs().get("realm", {}).get("flip", {})
		m.refresh(true)
		var ro := m.readout()
		var bar := HudLogic.status(m.readout())
		var vei_odds := NodeLogic.fmt_odds(float(ro["odds"]))
		var vei_sign := MapLogic.sign_glyph(int(ro["sign"]))
		var vei_drain := NodeLogic.drain_line(float(ro["backlog"]), float(ro["drain_s"]))
		var tag := "demo" if demo else "real"
		t.ok(bar["odds_text"] == vei_odds, "%s: bar odds == Vei odds (%s)" % [tag, vei_odds])
		t.ok(bar["sign_text"] == vei_sign, "%s: bar sign == Vei sign (%s)" % [tag, vei_sign])
		t.ok(ro["odds"] == m.hud["odds"] and ro["sign"] == m.hud["sign"] and ro["drain_s"] == m.hud["drain_s"], "%s: the readout is view_hud's" % tag)
		t.ok(ro["backlog"] == m.vei["backlog"], "%s: the backlog is view_vei's" % tag)
		if float(ro["backlog"]) > 0.0:
			t.ok(vei_drain == "drain " + bar["drain_text"], "%s: bar drain == Vei drain (%s)" % [tag, vei_drain])
		else:
			t.ok(bar["drain_text"] == "queue empty" and vei_drain == "queue empty", "%s: both say queue empty" % tag)
		if demo:
			var vd: Dictionary = MapLogic.cfg()["demo_nodes"]["vei"]
			t.ok(is_equal_approx(float(ro["odds"]), float(vd["odds"])) and int(ro["sign"]) == int(vd["sign"]) \
				and is_equal_approx(float(ro["drain_s"]), float(vd["drain_s"])) and is_equal_approx(float(ro["backlog"]), float(vd["backlog"])), "demo: the overlay's values come through the readout")


func _fit(t: TestUtil) -> void:
	t.suite("map_hud-fit")
	var cfg := MapLogic.cfg()
	var vp := Vector2(1600, 900)
	var inset := 70.0
	var content := Rect2(300, -40, 1500, 1400)
	var v := MapLogic.fit_view(content, vp, inset)
	var z: float = v["zoom"]
	var centre: Vector2 = v["centre"]
	# screen position of a world point: (p - centre) * z + viewport / 2
	var tl := (content.position - centre) * z + vp * 0.5
	var br := (content.end - centre) * z + vp * 0.5
	t.ok(tl.x >= 0.0 and br.x <= vp.x, "the content fits the viewport width")
	t.ok(tl.y >= inset - 1e-3 and br.y <= vp.y + 1e-3, "the content fits below the inset (top %.1f >= %.0f)" % [tl.y, inset])
	t.ok(MapLogic.fit_view(Rect2(), vp, inset).is_empty() and MapLogic.fit_view(content, vp, vp.y).is_empty(), "degenerate input fits nothing")
	var wide := MapLogic.fit_view(Rect2(0, 0, 4000, 100), vp, inset)
	t.near(float(wide["zoom"]), vp.x / 4000.0 * float(cfg["fit_margin"]), 1e-6, "a wide content is width-limited")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("pre_vei")
	var m := MapModel.new(s)
	m.refresh(true)
	var rect := m.content_rect()
	t.ok(rect.size.x > 0.0 and rect.size.y > 0.0, "the model has a content rect")
	for f in m.forts:
		t.ok(rect.has_point(MapModel.to_vec(f["pos"])), "%s is inside the content" % f["id"])
	t.ok(rect.has_point(m.node_pos("covington")) and rect.has_point(m.node_pos("vei")), "Covington and Vei are inside the content")
	var reach := NodeLogic.vei_reach(float(m.realm["vei"]["radius"]), float(m.vei["backlog"]))
	t.ok(rect.position.y <= m.node_pos("vei").y - reach, "the whole Vei stack is inside the content")
	var fit := MapLogic.fit_view(rect, vp, inset)
	var tier := MapLogic.zoom_tier(float(fit["zoom"]), "mid")
	t.ok(tier == "mid", "the default fit is the mid tier (zoom %.3f)" % float(fit["zoom"]))
	t.ok(float(fit["zoom"]) >= float(cfg["zoom_far_below"]) + float(cfg["zoom_hysteresis"]), "with at least the hysteresis margin above far (%.3f >= %.2f + %.2f)" % [float(fit["zoom"]), float(cfg["zoom_far_below"]), float(cfg["zoom_hysteresis"])])
	var vtop := ((m.node_pos("vei").y - reach) - float(fit["centre"].y)) * float(fit["zoom"]) + vp.y * 0.5
	t.ok(vtop >= inset, "Vei's stack starts below the HUD (%.1f >= %.0f)" % [vtop, inset])


func _wrap(t: TestUtil) -> void:
	t.suite("map_hud-wrap")
	var cfg := MapLogic.cfg()
	var gap := float(cfg["topbar_gap_px"])
	var max_w := float(cfg["topbar_max_w_px"])
	var widths := [150, 190, 140, 170, 130, 180, 260, 220, 90]
	var rows := HudLogic.wrap_rows(widths, gap, max_w)
	var flat: Array = []
	for r in rows:
		flat.append_array(r)
	t.ok(flat == range(widths.size()), "every item appears once, in order")
	t.ok(rows.size() > 1, "these widths wrap (%d rows)" % rows.size())
	for r in rows:
		var w: float = gap * (r.size() - 1)
		for i in r:
			w += float(widths[i])
		t.ok(w <= max_w, "a row of %d items is %.0f px (<= %.0f)" % [r.size(), w, max_w])
	t.ok(HudLogic.wrap_rows([100, 100], gap, max_w) == [[0, 1]], "items that fit share a row")
	t.ok(HudLogic.wrap_rows([max_w], gap, max_w) == [[0]] and HudLogic.wrap_rows([max_w, 1], gap, max_w) == [[0], [1]], "a row may be exactly max_w; one more px wraps")
	t.ok(HudLogic.wrap_rows([2000, 50], gap, max_w) == [[0], [1]], "an over-wide item stands alone")
	t.ok(HudLogic.wrap_rows([], gap, max_w).is_empty(), "no items, no rows")
	var pos: Array = cfg["topbar_pos_px"]
	var right_edge := float(pos[0]) + max_w + float(cfg["topbar_plate_pad_px"])
	t.ok(right_edge <= 1600.0 - float(cfg["meter_reserve_px"]), "the bar's plate (%.0f) stops left of the ground meter's reserve (%.0f)" % [right_edge, 1600.0 - float(cfg["meter_reserve_px"])])
	var hud_src := FileAccess.get_file_as_string("res://scripts/map/map_hud.gd")
	t.ok(hud_src.contains("HudLogic.wrap_rows("), "the bar lays its rows out with wrap_rows")
	t.ok(hud_src.contains('odds_name.text = str(cfg["cards"]["vei_odds_label"])') and not hud_src.contains('"ODDS"'), "the bar's odds label is the config's, not a literal")
	t.ok(str(cfg["cards"]["vei_odds_label"]) == "YOUR ODDS", "and it says whose odds")
	var bar_odds_w: float = ThemeDB.fallback_font.get_string_size(str(cfg["cards"]["vei_odds_label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(cfg["font_label"])).x
	t.ok(bar_odds_w < max_w * 0.25, "the longer label (%.0f px) is a small part of the bar's max width (%.0f)" % [bar_odds_w, max_w])
