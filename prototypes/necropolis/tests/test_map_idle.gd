extends RefCounted
## Tests for the idle surfaces: idle_logic.gd (margins, "WAR supports N of M", the dragged
## valve's projection), away_logic.gd (the away report's text and actions), the
## real-field-over-stand-in switch, and the chip colours' contrast. No autoloads.


## A GameState stand-in with the real view_projection and view_away shapes.
class FakeE2 extends RefCounted:
	func view_projection(valve: Dictionary) -> Dictionary:
		return {"rev": 1, "valve": valve, "split": {"work": 0.0, "war": 9.0, "flood": 0.0}, "workers_steady": 3.0, "backlog_diff": -2.0,
			"war_supports": {"n": 7, "m": 8},
			"margins": {"greywall": {"margin": "thin", "margin_cause": "", "fall_s": 500.0, "garrison_rate": -0.1, "margin_verified": false}}}

	func view_away() -> Dictionary:
		return {"rev": 5, "shown": true, "away_s": 100.0, "capped": false, "gains": [], "ready": [], "losses": []}


## An E2 away API: every view_away call carries a new rev, cmd_dismiss_away clears `shown`.
class FakeAwayApi extends RefCounted:
	var shown := true
	var rev := 100
	var dismissed := 0

	func view_away() -> Dictionary:
		rev += 1
		return {"rev": rev, "shown": shown, "away_s": 100.0}

	func cmd_dismiss_away() -> void:
		shown = false
		dismissed += 1


func run() -> int:
	var t := TestUtil.new()
	t.suite("map_idle")
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	_margin(t)
	_supports(t)
	_projection(t)
	_switch(t)
	_away(t)
	_away_api(t)
	_spans(t)
	_panel_fit(t)
	_demo(t)
	_contrast(t)
	_model(t)
	_sources(t)
	_chips(t)
	_layout_key(t)
	return t.failures


## IdleLogic.layout_key: the chip layout's cache key has no frame number, follows every input that
## moves a chip, and holds while Relish stays in one grid cell.
func _layout_key(t: TestUtil) -> void:
	t.suite("map_idle-layout-key")
	var grid := float(MapLogic.cfg()["callouts"]["token_key_px"])
	var base := {"rev": 4, "zoom": 1.0, "tier": "mid", "forts": 6, "has_token": true, "cell": IdleLogic.layout_token(Vector2(100, 50), true, grid)["key"], "margin_sig": "a",
		"shares": {"work": 0.2, "war": 0.8}, "backlog": 3.0, "vei_radius": 40.0, "cov_pos": Vector2(1, 2), "vei_pos": Vector2(3, 4), "widths": [120.0, 130.0], "panel": []}
	var k0 := IdleLogic.layout_key(base)
	t.ok(IdleLogic.layout_key(base.duplicate(true)) == k0, "the same inputs give the same key on two calls (no frame number)")
	var src := FileAccess.get_file_as_string("res://scripts/map/map_fort_idle.gd")
	t.ok(not src.contains("get_process_frames"), "map_fort_idle.gd keys its layout on no frame number")
	var changes := {"rev": 5, "zoom": 1.5, "tier": "near", "forts": 7, "has_token": false, "margin_sig": "b", "shares": {"work": 0.5, "war": 0.5},
		"backlog": 4.0, "vei_radius": 41.0, "cov_pos": Vector2(9, 2), "vei_pos": Vector2(3, 9), "widths": [120.0, 131.0], "panel": [1262, 800],
		"cell": IdleLogic.layout_token(Vector2(100 + grid * 2.0, 50), true, grid)["key"]}
	for k in changes:
		var v := base.duplicate(true)
		v[k] = changes[k]
		t.ok(IdleLogic.layout_key(v) != k0, "a changed %s changes the key" % k)
	# Relish moving inside one cell leaves the cell, and so the key, alone
	var mid := Vector2(8.0, 4.0) * grid  # a cell's centre
	var c1 := IdleLogic.token_cell(mid, grid)
	var c2 := IdleLogic.token_cell(mid + Vector2(grid * 0.4, -grid * 0.4), grid)
	t.ok(c1 == c2, "a token move of 0.4 cell from a cell's centre stays in its grid cell")
	t.ok(IdleLogic.token_cell(mid + Vector2(grid, 0.0), grid) != c1, "a move of a whole cell changes the cell")
	# the pad covers the distance from the cell's centre to any point in it
	var corner := IdleLogic.token_center(c1, grid) + Vector2(grid, grid) * 0.5  # a cell is centred on its centre
	t.ok(absf((corner - IdleLogic.token_center(c1, grid)).length() - IdleLogic.token_pad(grid)) < 0.001, "the token pad is half the cell's diagonal (%.2f)" % IdleLogic.token_pad(grid))
	t.ok(IdleLogic.token_cell(IdleLogic.token_center(c1, grid), grid) == c1, "a cell's centre is in the cell")
	_layout_token(t, grid)


## IdleLogic.layout_token: standing, the exact token and no pad (the pre-T2 layout); travelling, her
## cell's centre padded so the kept layout clears her anywhere in the cell.
func _layout_token(t: TestUtil, grid: float) -> void:
	var z := 1.0
	var w := 120.0
	var items := _chip_items(["ashgate", "old-sluice", "greywall", "vespers"], w)
	var tok_r := float(NodeLogic.relish_radii(z)["halo"]) + float(NodeLogic.ncfg()["relish_halo_max_px"]) * 0.5
	var pad_chip := float(IdleLogic.cfg()["chip_token_pad_px"]) / z
	for f in items:
		if not bool(f["held"]):
			continue
		var place := IdleLogic.chip_rect(f["pos"], float(f["r"]), z, bool(f["second"]), w).get_center()
		var stand := IdleLogic.layout_token(place, false, grid)
		t.ok(stand["pos"] == place and float(stand["pad"]) == 0.0, "%s: standing, the helper gives the exact position and no pad" % f["id"])
		var want := IdleLogic.chip_layout(items, z, true, place, tok_r)
		var got := IdleLogic.chip_layout(items, z, true, stand["pos"], tok_r + float(stand["pad"]))
		t.ok(got == want, "%s: standing, the layout equals the direct (pre-T2) one" % f["id"])
		# travelling: real positions across the cell, corners included, with the chip laid out against the cell centre
		var cell_c := IdleLogic.token_center(IdleLogic.token_cell(place, grid), grid)
		var cl := IdleLogic.layout_token(place, true, grid)
		t.ok(cl["pos"] == cell_c and absf(float(cl["pad"]) - IdleLogic.token_pad(grid)) < 0.001, "%s: travelling, the cell centre and the padded radius" % f["id"])
		var lay := IdleLogic.chip_layout(items, z, true, cl["pos"], tok_r + float(cl["pad"]))
		var h := grid * 0.5
		for off in [Vector2(-h, -h), Vector2(h, -h), Vector2(-h, h), Vector2(h, h), Vector2(0, 0), Vector2(h, 0), Vector2(0, -h)]:
			var real: Vector2 = cell_c + off * 0.999
			t.ok(IdleLogic.token_cell(real, grid) == IdleLogic.token_cell(place, grid), "%s: real position %s is in the cell" % [f["id"], str(off)])
			var rrect := Rect2(real - Vector2.ONE * (tok_r + pad_chip), Vector2.ONE * (tok_r + pad_chip) * 2.0)
			for g in items:
				if bool(g["held"]):
					t.ok(not (lay[g["id"]] as Rect2).intersects(rrect), "%s: chip laid out for the cell clears the real token at %s of the cell (%s)" % [g["id"], str(off), f["id"]])


## The real world's forts as chip_layout items: every fort labelled (name_w 7 px a letter, a 40 px tag
## on Old Sluice), the ids in `held` with a chip `w` px wide.
func _chip_items(held: Array, w: float) -> Array:
	var out: Array = []
	for f in TestUtil.load_json("res://configs/world.json")["forts"]:
		var id := str(f["id"])
		out.append({"id": id, "pos": Vector2(float(f["pos"][0]), float(f["pos"][1])), "r": MapLogic.fort_radius(int(f["tier"])), "held": held.has(id),
			"second": id == "old-sluice", "w": w if held.has(id) else 0.0, "name_w": 7.0 * str(f["name"]).length(), "tag_w": 40.0 if id == "old-sluice" else -1.0})
	return out


## What `rect` (fort `f`'s chip) touches that it must not: another fort's ring, name or tag plate, a
## chip in `others` ({id: Rect2}) other than its own. Built here from the geometry, not from chip_layout.
func _chip_hits(rect: Rect2, f: Dictionary, items: Array, others: Dictionary, z: float) -> Array:
	var hits: Array = []
	var off := float(NodeLogic.ncfg()["label_off_px"])
	for g in items:
		if g["id"] == f["id"]:
			continue
		var gp: Vector2 = g["pos"]
		var gr := float(g["r"])
		var nearest := Vector2(clampf(gp.x, rect.position.x, rect.end.x), clampf(gp.y, rect.position.y, rect.end.y))
		if nearest.distance_to(gp) < gr:
			hits.append("ring of " + str(g["id"]))
		if float(g["name_w"]) >= 0.0:
			var at := gp + Vector2(0.0, gr + off)
			for pr in NodeLogic.fort_label_rects(float(g["name_w"]), float(g["tag_w"]), int(MapLogic.cfg()["font_label"])):
				if rect.intersects(Rect2(at + (pr as Rect2).position / z, (pr as Rect2).size / z)):
					hits.append("label of " + str(g["id"]))
	for id in others:
		if id != f["id"] and rect.intersects(others[id]):
			hits.append("chip of " + str(id))
	return hits


## Whether chip `rect` reads as fort `f`'s on sight, by the rule written out here (not chip_layout's code): its own gap,
## the nearer of the screen-px gaps to its own ring's edge and to its own name and tag plates, is at most chip_attach_px,
## and every other fort's ring edge is at least that gap + chip_attach_margin_px away.
func _reads_as_own(rect: Rect2, f: Dictionary, items: Array, z: float) -> bool:
	var gap := func(r: Rect2, g: Dictionary) -> float:
		var np := Vector2(clampf(g["pos"].x, r.position.x, r.end.x), clampf(g["pos"].y, r.position.y, r.end.y))
		return maxf(np.distance_to(g["pos"]) - float(g["r"]), 0.0) * z
	var cfg := IdleLogic.cfg()
	var own: float = gap.call(rect, f)
	var at: Vector2 = f["pos"] + Vector2(0.0, float(f["r"]) + float(NodeLogic.ncfg()["label_off_px"]))
	for pr in NodeLogic.fort_label_rects(float(f["name_w"]), float(f["tag_w"]), int(MapLogic.cfg()["font_label"])):
		var pl := Rect2(at + (pr as Rect2).position / z, (pr as Rect2).size / z)
		var d := Vector2(maxf(maxf(rect.position.x - pl.end.x, pl.position.x - rect.end.x), 0.0), maxf(maxf(rect.position.y - pl.end.y, pl.position.y - rect.end.y), 0.0))
		own = minf(own, d.length() * z)
	if own > float(cfg["chip_attach_px"]):
		return false
	for g in items:
		if g["id"] != f["id"] and float(gap.call(rect, g)) < own + float(cfg["chip_attach_margin_px"]):
			return false
	return true


## Held chips keep off other forts' rings, name and tag plates and chips, and stay clear of Relish's token.
func _chips(t: TestUtil) -> void:
	t.suite("map_idle-chip-layout")
	var w := 148.0
	var items := _chip_items(["ashgate", "old-sluice"], w)
	var ash: Dictionary = items[0]
	var slu: Dictionary = items[1]
	t.ok(ash["id"] == "ashgate" and slu["id"] == "old-sluice", "the real world lists Ashgate then Old Sluice")
	# the held-countdown screenshot: zoom ~0.57 (Ashgate and Old Sluice 80 px apart on screen), the chips ~148 px wide
	var z := 0.57
	var old_default := IdleLogic.chip_rect(ash["pos"], float(ash["r"]), z, false, w)
	t.ok(not _chip_hits(old_default, ash, items, {}, z).is_empty(), "the regression: Ashgate's chip under its name crowds Old Sluice: " + str(_chip_hits(old_default, ash, items, {}, z)))
	for zoom in [0.55, 0.57, 0.7, 1.0, 1.6]:
		var lay := IdleLogic.chip_layout(items, zoom, false, Vector2.ZERO, 0.0)
		t.ok(lay.size() == 2, "zoom %.2f: a chip for each held fort" % zoom)
		for f in [ash, slu]:
			var r: Rect2 = lay[f["id"]]
			var hits := _chip_hits(r, f, items, lay, zoom)
			t.ok(hits.is_empty(), "zoom %.2f: %s's chip touches nothing of another fort %s" % [zoom, f["id"], str(hits)])
			var own := r.get_center().distance_to(f["pos"])
			var nearer := true
			for g in items:
				if g["id"] != f["id"] and r.get_center().distance_to(g["pos"]) <= own:
					nearer = false
			t.ok(nearer and r.size == IdleLogic.chip_rect(f["pos"], float(f["r"]), zoom, bool(f["second"]), w).size, "zoom %.2f: %s's chip is nearer its own fort, same size" % [zoom, f["id"]])
		t.ok(IdleLogic.chip_layout(items, zoom, false, Vector2.ZERO, 0.0) == lay, "zoom %.2f: the same input gives the same places" % zoom)
	# the skip-time screenshot: Ashgate held, Old Sluice retaken and Greywall overrun (each with a tag line), zoom ~0.585
	var tagged := _chip_items(["ashgate"], w)
	tagged[2]["second"] = true
	tagged[2]["tag_w"] = 50.0
	for zoom in [0.55, 0.585, 0.7]:
		var lay := IdleLogic.chip_layout(tagged, zoom, false, Vector2.ZERO, 0.0)
		var hits := _chip_hits(lay["ashgate"], tagged[0], tagged, lay, zoom)
		t.ok(hits.is_empty(), "zoom %.3f: Ashgate's chip, its neighbours tagged, touches nothing %s" % [zoom, str(hits)])
	# the d99ea17 placement at zoom 0.57 (above Ashgate's ring slid left, beside Vespers) read as Vespers' chip
	var drifted := Rect2(1352.28, 1022.526, 259.6491, 56.84211)
	t.ok(not _reads_as_own(drifted, ash, items, 0.57), "the regression: a chip above the ring beside Vespers does not read as Ashgate's")
	for zoom in [0.55, 0.57, 0.585, 0.7, 1.0]:
		var lay := IdleLogic.chip_layout(items, zoom, false, Vector2.ZERO, 0.0)
		for f in [ash, slu]:
			t.ok(_reads_as_own(lay[f["id"]], f, items, zoom), "zoom %.3f: %s's chip reads as its own on sight" % [zoom, f["id"]])
	# Covington and Vei are obstacles too: their discs, Covington's name and the valve's stream labels, Vei's name
	var world := TestUtil.load_json("res://configs/world.json")
	var cov := Vector2(float(world["covington"]["pos"][0]), float(world["covington"]["pos"][1]))
	var vei := Vector2(float(world["vei"]["pos"][0]), float(world["vei"]["pos"][1]))
	var cen := NodeLogic.fort_centroid(items.map(func(g): return {"pos": [g["pos"].x, g["pos"].y]}))
	var tw := {}
	for k in {"war": "WAR", "flood": "FLOOD", "work": "WORK", "covington": "COVINGTON", "vei": "VEI'S DOMAIN"}:
		tw[k] = 7.0 * {"war": 3, "flood": 5, "work": 4, "covington": 9, "vei": 12}[k]
	for zoom in [0.55, 0.57, 0.585, 0.7]:
		var nodes := IdleLogic.node_obstacles(cov, vei, float(world["vei"]["radius"]), 0.0, {"work": 0.4, "war": 0.45, "flood": 0.15}, cen, zoom, true, tw)
		t.ok(nodes.size() == 2 and (nodes[0]["rects"] as Array).size() == 4, "zoom %.3f: Covington has a name and three stream labels as plates" % zoom)
		var lay := IdleLogic.chip_layout(items, zoom, false, Vector2.ZERO, 0.0, nodes)
		for f in [ash, slu]:
			var r: Rect2 = lay[f["id"]]
			var bad: Array = _chip_hits(r, f, items, lay, zoom)
			t.ok(bad.is_empty(), "zoom %.3f: %s's chip, with Covington and Vei in play, hits no fort ring, plate or chip %s" % [zoom, f["id"], str(bad)])
			t.ok(_reads_as_own(r, f, items, zoom), "zoom %.3f: %s's chip, with Covington and Vei in play, reads as its own on sight" % [zoom, f["id"]])
			# Covington and Vei are soft obstacles: where a chip touches one, it is the only thing it touches
			t.ok(not (nodes[1]["rects"] as Array).any(func(pr): return r.intersects(pr)), "zoom %.3f: %s's chip is off Vei's name" % [zoom, f["id"]])
	# a chip that is already clear does not move: Old Sluice alone, and Ashgate with nobody near
	var alone := IdleLogic.chip_layout(_chip_items(["sable-hold"], w), 1.0, false, Vector2.ZERO, 0.0)
	var sh: Dictionary = _chip_items(["sable-hold"], w)[11]
	t.ok(sh["id"] == "sable-hold" and alone["sable-hold"] == IdleLogic.chip_rect(sh["pos"], float(sh["r"]), 1.0, false, w), "a clear chip stays under its name")
	# the token still has the chip move clear, and the chip stays clear of the forts too
	var tok_r := 12.0
	for f in [ash, slu]:
		var base := IdleLogic.chip_rect(f["pos"], float(f["r"]), z, false, w)
		var tok := base.get_center()
		var lay := IdleLogic.chip_layout(items, z, true, tok, tok_r)
		var r: Rect2 = lay[f["id"]]
		var pad := float(IdleLogic.cfg()["chip_token_pad_px"]) / z
		var trect := Rect2(tok - Vector2.ONE * (tok_r + pad), Vector2.ONE * (tok_r + pad) * 2.0)
		t.ok(not r.intersects(trect), "%s: a token on the chip's place: the chip is clear of it" % f["id"])
		t.ok(_chip_hits(r, f, items, lay, z).is_empty(), "%s: and clear of the other forts %s" % [f["id"], str(_chip_hits(r, f, items, lay, z))])
	# nowhere clear: the chip keeps the least-overlapping place, not the default
	var crowd := _chip_items(["ashgate"], 4000.0)
	var jam := IdleLogic.chip_layout(crowd, z, false, Vector2.ZERO, 0.0)
	t.ok(jam.has("ashgate") and (jam["ashgate"] as Rect2).size.x > 0.0, "no clear place: it still gets one")
	# chips are placed in id order: a later chip avoids an earlier one
	var both := IdleLogic.chip_layout(_chip_items(["ashgate", "old-sluice", "greywall"], w), z, false, Vector2.ZERO, 0.0)
	t.ok(not (both["greywall"] as Rect2).intersects(both["ashgate"]) and not (both["old-sluice"] as Rect2).intersects(both["ashgate"]), "no two chips overlap")
	_chip_winners(t, w)


## Which place wins, not just that nothing is hit: the default when it is clear, the under-the-name slide
## (by its exact share of the chip's width, right before left) when a neighbour crowds it, and never a
## place above the ring or beside it.
func _chip_winners(t: TestUtil, w: float) -> void:
	t.suite("map_idle-chip-winner")
	var items := _chip_items(["ashgate", "old-sluice"], w)
	var ash: Dictionary = items[0]
	var slu: Dictionary = items[1]
	var near := func(a: Rect2, b: Rect2) -> bool:
		return a.position.is_equal_approx(b.position) and a.size.is_equal_approx(b.size)
	# (i) clear space: exactly the default place, with and without Relish's token out of the way
	var alone: Dictionary = {}
	for it in _chip_items(["sable-hold"], w):
		if it["id"] == "sable-hold":
			alone = it
	t.ok(not alone.is_empty(), "sable-hold is among the fort items")
	var base_a := IdleLogic.chip_rect(alone["pos"], float(alone["r"]), 1.0, false, w)
	var lay_a := IdleLogic.chip_layout(_chip_items(["sable-hold"], w), 1.0, false, Vector2.ZERO, 0.0)
	t.ok(near.call(lay_a["sable-hold"], base_a), "a clear held fort gets exactly its default place")
	var far_tok: Vector2 = (alone["pos"] as Vector2) + Vector2(5000.0, 5000.0)
	var lay_t := IdleLogic.chip_layout(_chip_items(["sable-hold"], w), 1.0, true, far_tok, 10.0)
	t.ok(near.call(lay_t["sable-hold"], base_a), "and the same with Relish's token far away")
	# (ii) Ashgate crowded by Old Sluice: the 0.25 slide to the right at zoom 0.57, the 0.1 slide at 0.7
	var fr: Array = IdleLogic.cfg()["chip_slide_fracs"]
	for case in [[0.57, 0.25], [0.7, 0.1]]:
		var z: float = case[0]
		var lay := IdleLogic.chip_layout(items, z, false, Vector2.ZERO, 0.0)
		var base := IdleLogic.chip_rect(ash["pos"], float(ash["r"]), z, false, w)
		var want := Rect2(base.position + Vector2(base.size.x * float(case[1]), 0.0), base.size)
		t.ok(fr.has(case[1]) and near.call(lay["ashgate"], want), "zoom %.2f: Ashgate's chip is its default slid right by %.2f of its width, got dx/w %.4f dy %.4f" % [z, case[1], (lay["ashgate"].position.x - base.position.x) / base.size.x, lay["ashgate"].position.y - base.position.y])
		t.ok(not near.call(lay["ashgate"], base), "zoom %.2f: Ashgate's default place really was blocked (the slide is not the default)" % z)
		var base_s := IdleLogic.chip_rect(slu["pos"], float(slu["r"]), z, true, w)
		t.ok(near.call(lay["old-sluice"], base_s), "zoom %.2f: Old Sluice (nothing crowds it, but its tag line) keeps its default" % z)
	# (iii) never above the ring or beside it: every chip's top is under its own name (and tag) plate
	for zoom in [0.55, 0.57, 0.7, 1.0, 1.6]:
		var lay := IdleLogic.chip_layout(items, zoom, false, Vector2.ZERO, 0.0)
		for f in [ash, slu]:
			var plate_bottom := 0.0
			for pr in NodeLogic.fort_label_rects(float(f["name_w"]), float(f["tag_w"]), int(MapLogic.cfg()["font_label"])):
				plate_bottom = maxf(plate_bottom, (pr as Rect2).end.y)
			var under: float = f["pos"].y + float(f["r"]) + float(NodeLogic.ncfg()["label_off_px"]) + plate_bottom / zoom
			t.ok((lay[f["id"]] as Rect2).position.y >= under - 0.001, "zoom %.2f: %s's chip sits under its name plate, not above or beside the ring" % [zoom, f["id"]])
	# the second line's height is the tag plate's, drawn at tag_size(): the chip top sits chip_gap_px under it
	var gap := float(IdleLogic.cfg()["chip_gap_px"])
	var plates := NodeLogic.fort_label_rects(50.0, 40.0, int(MapLogic.cfg()["font_label"]))
	t.ok(is_equal_approx(IdleLogic.chip_top_px(true), (plates[1] as Rect2).end.y + gap), "a tagged fort's chip top is chip_gap_px under the tag plate: %.3f vs %.3f" % [IdleLogic.chip_top_px(true), (plates[1] as Rect2).end.y + gap])
	t.ok(is_equal_approx(IdleLogic.chip_top_px(false), (plates[0] as Rect2).end.y + gap), "and an untagged one's, under the name plate")


func _fort(id: String, margin: String, held := true) -> Dictionary:
	return {"id": id, "held": held, "margin": margin, "ship_in": 0.0, "undead": 10.0, "garrison": 10.0, "garrison_rate": 0.0, "fall_s": -1.0}


func _margin(t: TestUtil) -> void:
	t.ok(IdleLogic.word("safe") == "SAFE" and IdleLogic.word("thin") == "THIN" and IdleLogic.word("will_fall") == "WILL FALL", "the chip words")
	var keys := {}
	for m in ["safe", "thin", "will_fall"]:
		keys[IdleLogic.color_key(m)] = true
		t.ok(Palette.has(IdleLogic.color_key(m)), "%s colour is a palette key" % m)
	t.ok(keys.size() == 3, "the three margins have three colours")
	t.ok(IdleLogic.garrison({"undead": 12.0, "garrison": 40.0}) == 40.0, "garrison is the view's garrison")
	t.ok(IdleLogic.garrison({"undead": 12.0}) == 0.0, "the fort's undead is not a garrison: no stand-in")


func _supports(t: TestUtil) -> void:
	var forts := [_fort("a", "safe"), _fort("b", "thin"), _fort("c", "will_fall"), _fort("d", "", false)]
	t.ok(IdleLogic.held_forts(forts).size() == 3, "held_forts skips the unheld")
	t.ok(IdleLogic.committed_margins(forts) == {"a": "safe", "b": "thin", "c": "will_fall"}, "committed margins are view_fort.margin of the held forts")
	# "WAR supports N of M" is view_hud.war_supports, whatever the forts' ship_in
	var hud := {"war_supports": {"n": 2, "m": 5}}
	t.ok(IdleLogic.committed_supports(hud) == {"n": 2, "m": 5}, "committed N of M is view_hud.war_supports")
	t.ok(ValveLogic.supports_text({"war_supports": IdleLogic.committed_supports(hud)}) == "WAR supports 2 of 5 held forts", "the valve text reads it")
	# a held fort with no margin: no word, and never SAFE
	var blank := IdleLogic.committed_margins([_fort("a", "")])
	t.ok(blank == {"a": ""}, "a held fort with an empty margin keeps it empty")
	t.ok(IdleLogic.word(blank["a"]) == "", "and shows no margin word")
	t.ok(NodeLogic.fort_state(_fort("a", ""), "") != IdleLogic.SAFE, "and is not SAFE")
	t.ok(IdleLogic.committed_margins([_fort("t", "thin")])["t"] != IdleLogic.SAFE and NodeLogic.fort_state(_fort("t", "thin"), "thin") == IdleLogic.THIN, "a thin held fort never reads SAFE")
	t.ok(IdleLogic.chip_parts(_fort("t", "thin"), "thin", {"rate": 0.0, "fall_s": -1.0})["word"] == "THIN", "its chip says THIN")
	# the same view, from a real GameState, is the model's
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	var hv := s.view_hud()
	var m := MapModel.new(s)
	m.refresh(true)
	t.ok(m.supports == hv["war_supports"] and m.supports_now() == hv["war_supports"], "the model's WAR supports N of M is view_hud's")
	var rv := s.view_realm()
	var ok := true
	for f in IdleLogic.held_forts(rv["forts"]):
		var id := str(f["id"])
		ok = ok and m.margins[id] == str(f["margin"]) and m.margin_of(id) == str(f["margin"]) and m.margins[id] != ""
		ok = ok and is_equal_approx(float(m.clock_of(id)["rate"]), float(f["garrison_rate"])) and is_equal_approx(float(m.clock_of(id)["fall_s"]), float(f["fall_s"]))
		ok = ok and is_equal_approx(IdleLogic.garrison(f), float(f["garrison"]))
	t.ok(ok and not m.margins.is_empty(), "every held fort's margin, rate and fall_s on the map are the view_fort ones")


func _projection(t: TestUtil) -> void:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	var m := MapModel.new(s)
	m.refresh(true)
	var seen := {}
	for i in 11:
		var war := float(i) / 10.0
		var valve := {"work": 1.0 - war, "war": war, "flood": 0.0}
		var p := IdleLogic.projection(s, valve, m.forts)
		var v := s.view_projection(ValveLogic.normalise(valve))
		t.ok(p["war_supports"] == v["war_supports"], "drag projection N of M is view_projection's at war %.1f" % war)
		t.ok(int(p["war_supports"]["m"]) == IdleLogic.held_forts(m.forts).size() and int(p["war_supports"]["n"]) <= int(p["war_supports"]["m"]), "and bounded by the held count")
		for id in v["margins"]:
			t.ok(p["margins"][id] == str(v["margins"][id]["margin"]), "the projected margin word is view_projection's (%s)" % id)
			seen[p["margins"][id]] = true
	t.ok(not seen.is_empty(), "the drag shows margin words")
	t.ok(IdleLogic.split_at(s, m.hud["valve"]) == s.view_projection(ValveLogic.normalise(m.hud["valve"]))["split"], "the base split is view_projection's")


func _switch(t: TestUtil) -> void:
	var forts := [_fort("greywall", "safe"), _fort("b", "safe")]
	var valve := {"work": 0.0, "war": 1.0, "flood": 0.0}
	var e2 := IdleLogic.projection(FakeE2.new(), valve, forts)
	t.ok(e2["margins"] == {"greywall": "thin"}, "view_projection's margins are used")
	t.ok(e2["war_supports"] == {"n": 7, "m": 8}, "view_projection's N of M is used")
	t.near(float(e2["split"]["war"]), 9.0, 1e-6, "view_projection's split is used")
	t.near(float(e2["workers_steady"]), 3.0, 1e-6, "view_projection's workers_steady is used")
	t.near(float(e2["backlog_diff"]), -2.0, 1e-6, "view_projection's backlog_diff is used")
	t.ok(float(e2["clocks"]["greywall"]["fall_s"]) == 500.0 and is_equal_approx(float(e2["clocks"]["greywall"]["rate"]), -0.1), "its fall_s and garrison_rate are the chip's clock")
	t.ok(e2["clocks"].has("b"), "a held fort it leaves out keeps its committed clock")
	# the away report
	var demo := {"shown": true, "rev": 1}
	t.ok(AwayLogic.report(null, {}) == {"shown": false}, "no state: nothing to show")
	t.ok(AwayLogic.report(null, demo) == demo, "the demo report is used")
	t.ok(int(AwayLogic.report(FakeE2.new(), {})["rev"]) == 5, "view_away is used")
	t.ok(AwayLogic.report(FakeE2.new(), demo) == demo, "the debug flag's report wins over the real one")


func _away_api(t: TestUtil) -> void:
	var api := FakeAwayApi.new()
	var closed := -1
	# the real API: shown alone decides, whatever the rev did
	var rep := AwayLogic.report(api, {})
	t.ok(AwayLogic.should_open(api, false, rep, closed), "a shown real report opens")
	closed = int(rep["rev"])  # what _close records
	t.ok(AwayLogic.should_open(api, false, AwayLogic.report(api, {}), closed), "the real report's rev moves every call: the closed rev never matches")
	# acting on a ready line dismisses through the API, so the panel stays closed on every mount
	AwayLogic.dismiss(api)
	t.ok(api.dismissed == 1 and not api.shown, "acting on a line sends cmd_dismiss_away")
	t.ok(not AwayLogic.should_open(api, false, AwayLogic.report(api, {}), closed), "after a dismissed real report the panel does not reopen")
	# the debug demo compares rev
	var demo := {"shown": true, "rev": 1}
	t.ok(AwayLogic.should_open(api, true, demo, -1), "the demo opens")
	t.ok(not AwayLogic.should_open(api, true, demo, 1), "the demo's closed rev keeps it closed")
	t.ok(not AwayLogic.should_open(api, false, {"shown": false}, -1), "not shown: never open")
	AwayLogic.dismiss(null)
	t.ok(true, "dismiss tolerates no state")
	# a real GameState: the panel's report is view_away()
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	var real := AwayLogic.report(s, {})
	var va := s.view_away()
	t.ok(real["shown"] == va["shown"] and real["away_s"] == va["away_s"] and real["capped"] == va["capped"] and real["gains"] == va["gains"]
		and real["ready"] == va["ready"] and real["losses"] == va["losses"], "the away report is view_away's {shown, away_s, capped, gains, ready, losses}")


func _away(t: TestUtil) -> void:
	t.ok(AwayLogic.duration_text(33120.0) == "9 h 12 m", "9 h 12 m")
	t.ok(AwayLogic.duration_text(720.0) == "12 m", "under an hour is minutes")
	t.ok(AwayLogic.duration_text(7200.0) == "2 h 0 m", "whole hours keep the minutes")
	t.ok(AwayLogic.duration_text(10.0) == "under a minute", "under a minute")
	t.ok(AwayLogic.duration_text(-5.0) == "under a minute", "negative time is under a minute")
	var ids := ["ashgate", "greywall"]
	var rep: Dictionary = MapLogic.cfg()["demo_away"]
	var b := AwayLogic.build(rep, ids)
	t.ok(b["away"] == "Away 9 h 12 m", "away line")
	t.ok(b["capped"] == "", "not capped")
	var keys := []
	for s in b["sections"]:
		keys.append(s["key"])
	t.ok(keys == ["gains", "ready", "losses"], "order is gains, ready, losses")
	var ready: Dictionary = b["sections"][1]
	t.ok(ready["lines"].size() == 3, "three ready lines")
	t.ok(ready["lines"][0]["action"] == {"kind": "fort", "id": "ashgate"}, "a fort id selects the fort")
	t.ok(ready["lines"][1]["action"] == {"kind": "dive", "to": "covington"}, "the slab dives into Covington")
	t.ok(ready["lines"][2]["action"] == {"kind": "dive", "to": "covington"}, "the queue dives into Covington")
	t.ok(AwayLogic.action("nowhere", ids)["kind"] == "none" and AwayLogic.action("", ids)["kind"] == "none", "an unknown or empty target does nothing")
	t.ok(b["sections"][0]["lines"][0]["action"]["kind"] == "none", "gains lines are not actions")
	t.ok(b["tithe"]["text"] == "" and b["tithe"]["action"]["kind"] == "none", "no vei view: no tithe line")
	var live := AwayLogic.build(rep, ids, {"target": "", "next_target": "ashgate", "next_s": 750.0}, {"ashgate": "Ashgate"})
	t.ok(live["tithe"]["text"] == "Next tithe: Ashgate in 12:30" and live["tithe"]["action"] == {"kind": "fort", "id": "ashgate"}, "the tithe line is read from the vei view; clicking selects the fort")
	t.ok(live["sections"].size() == b["sections"].size(), "and it is its own line, not a section")
	var live2 := AwayLogic.build(rep, ids, {"target": "ashgate", "eta_s": 100.0, "warning": true, "next_target": "ashgate", "next_s": 100.0}, {"ashgate": "Ashgate"})
	t.ok(live2["tithe"]["text"] == "Tithe wave at Ashgate in 1:40", "it ticks with the view")
	t.ok(AwayLogic.build(rep, ids, {"next_target": "nowhere", "next_s": 5.0})["tithe"]["action"]["kind"] == "none", "a target that is no fort does nothing")
	var capped := AwayLogic.build({"away_s": 604800.0, "capped": true, "gains": [], "ready": [], "losses": []}, ids)
	t.ok(capped["capped"] == "capped at 7 days", "capped text")
	var empty_keys := []
	for s in capped["sections"]:
		empty_keys.append(s["key"])
	t.ok(empty_keys == ["losses"], "empty gains and ready are left out; losses always show")
	t.ok(capped["sections"][0]["lines"][0]["text"] == "Nothing lost.", "no losses reads Nothing lost.")
	var lost: Array = b["sections"][2]["lines"]
	t.ok(lost.size() == (rep["losses"] as Array).size() + 1 and lost[0]["text"] == AwayLogic.losses_count(rep["losses"]) and lost[1]["text"] != "Nothing lost.", "losses are listed, led by their count")


func _panel_fit(t: TestUtil) -> void:
	# V-I1 item 7: the away panel opens under the top bar's plate, never across its rows
	var f := AwayLogic.panel_fit(900.0, 92.0, 600.0, 22.0, 8.0)
	t.ok(is_equal_approx(float(f["top"]), 100.0) and is_equal_approx(float(f["bottom"]), 8.0) and is_equal_approx(float(f["body_h"]), 600.0) and not bool(f["scroll"]), "room enough: under the bar, the body at its own height (%s)" % str(f))
	var tall := AwayLogic.panel_fit(900.0, 92.0, 810.0, 22.0, 8.0)
	t.ok(is_equal_approx(float(tall["body_h"]), 900.0 - 8.0 - 100.0 - 44.0) and bool(tall["scroll"]), "too tall for the room: it scrolls, its plate ending margin px above the bottom (%s)" % str(tall))
	t.ok(float(tall["top"]) + float(tall["body_h"]) + 44.0 <= 900.0 - 8.0 + 0.001, "the plate fits between the bar and the bottom")
	t.ok(float(AwayLogic.panel_fit(400.0, 500.0, 300.0, 22.0, 8.0)["body_h"]) == 0.0, "no room at all: zero, never negative")
	t.ok(int(AwayLogic.cfg()["top_gap_px"]) > 0, "a gap under the bar")
	var src := FileAccess.get_file_as_string("res://scripts/map/map_away.gd")
	t.ok(src.contains("AwayLogic.panel_fit(vp.y, bar, body_h") and src.contains("_centre.offset_top = float(f[\"top\"])") and src.contains("_scroll.custom_minimum_size.y = float(f[\"body_h\"])"), "the panel sizes itself from panel_fit")
	t.ok(FileAccess.get_file_as_string("res://scripts/map/world_map.gd").contains("away.hud = hud"), "the map hands the panel its HUD")


func _spans(t: TestUtil) -> void:
	var s := AwayLogic.spans("backlog ▲ +2.1/s · +69,500")
	var kinds := []
	for x in s:
		kinds.append(x["kind"])
	t.ok(kinds == ["label", "rate", "label", "mass"], "stream line: label, rate, label, mass (%s)" % str(kinds))
	t.ok(s[1]["text"] == "+2.1/s" and s[3]["text"] == "+69,500", "rate and total are their own runs")
	# V-I1 item 8: the stand-in's queue line in the glossary's words (economy's real label is theirs to change)
	var demo_gain := str(MapLogic.cfg()["demo_away"]["gains"][0]["text"])
	t.ok(demo_gain.begins_with("Vei's queue ▲") and not demo_gain.contains("backlog") and demo_gain.ends_with("your odds 5% → 8%"), "the demo's queue line says Vei's queue, odds in percent: " + demo_gain)
	var dk := []
	for x in AwayLogic.spans(demo_gain):
		dk.append(x["kind"])
	t.ok(dk == ["label", "rate", "label", "mass", "label"], "its rate and total still stand out (%s)" % str(dk))
	var b := AwayLogic.spans("2 builds finished")
	t.ok(b[0]["kind"] == "mass" and b[1]["kind"] == "label" and b[1]["text"] == "builds finished", "a count is a mass, the words merge")
	t.ok(AwayLogic.spans("Nothing lost.").size() == 1, "plain words are one run")
	t.ok(AwayLogic.spans("rot −0.3/s")[1]["kind"] == "rate", "a minus-sign rate is a rate")


func _demo(t: TestUtil) -> void:
	var d: Dictionary = MapLogic.cfg()["demo_nodes"]
	var all: Array = [d["held"]]
	all.append_array(d["also_held"])
	var seen := {}
	for h in all:
		seen[str(h["margin"])] = true
	t.ok(seen.has("safe") and seen.has("thin") and seen.has("will_fall"), "the demo held forts show all three margins")
	var gs := GameState.new(TestUtil.configs())
	gs.debug_enabled = true
	gs.cmd_debug_load_fixture("midgame_2flips")
	var dm := MapModel.new(gs)
	dm.nodes_demo = true
	dm.refresh(true)
	var ok := true
	for h in all:
		var ck := dm.clock_of(str(h["fort"]))
		ok = ok and dm.margins[h["fort"]] == h["margin"] and is_equal_approx(float(ck["rate"]), float(h["garrison_rate"])) and is_equal_approx(float(ck["fall_s"]), float(h["fall_s"]))
	t.ok(ok, "the demo overlay writes the view's own margin, garrison_rate and fall_s")
	var held_n := IdleLogic.held_forts(dm.forts).size()
	t.ok(int(dm.supports["m"]) == held_n and int(dm.supports["n"]) < held_n, "and its N of M (the will-fall fort does not count)")
	var c: Dictionary = IdleLogic.cfg()
	t.ok(int(c["chip_font"]) >= 12, "the chip's text (garrison, rate, word, clock) is at least 12 px")
	t.ok(float(AwayLogic.cfg()["line_min_h_px"]) >= 44.0 and float(AwayLogic.cfg()["dismiss_w_px"]) >= 44.0, "away targets are at least 44 px")


func _contrast(t: TestUtil) -> void:
	var cfg := MapLogic.cfg()
	var panel := Palette.c("ground").lightened(float(cfg["panel_bg_lighten"]))
	for m in ["safe", "thin", "will_fall"]:
		var col := Palette.c(IdleLogic.color_key(m))
		t.ok(MapLogic.contrast_ratio(col, Palette.c("ground")) >= 4.5, "%s chip text on the ground is >= 4.5:1" % m)
		# the plate lets (1 - alpha) of whatever is behind it through: the brightest palette key at worst
		var through := Palette.c("ground").lerp(Palette.c("undead"), 1.0 - float(cfg["idle"]["plate_alpha"]))
		t.ok(MapLogic.contrast_ratio(col, through) >= 4.5, "%s chip text on its plate over green WAR lanes is %.1f:1 (>= 4.5)" % [m, MapLogic.contrast_ratio(col, through)])
	for key in ["text", "text_dim", "select"]:
		t.ok(MapLogic.contrast_ratio(Palette.c(key), panel) >= 4.5, "%s on the away panel is >= 4.5:1" % key)


## No stand-in for a view field is left in scripts/map: no api-request #7, #12 or #13 TODO, and
## nothing reads the dead hold-timer field.
func _sources(t: TestUtil) -> void:
	var dir := DirAccess.open("res://scripts/map")
	var names := Array(dir.get_files()).filter(func(n): return str(n).ends_with(".gd"))
	t.ok(names.size() > 20, "the map's scripts are found (%d)" % names.size())
	var bad: Array = []
	for n in names:
		var src := FileAccess.get_file_as_string("res://scripts/map/%s" % n)
		for needle in ["TODO(api-request #7", "TODO(api-request #12", "TODO(api-request #13", "held_s_left"]:
			if src.contains(needle):
				bad.append("%s: %s" % [n, needle])
	t.ok(bad.is_empty(), "no #7/#12/#13 stand-in TODO and no held_s_left in scripts/map (%s)" % str(bad))
	var open: Array = []
	var paths: Array = names.map(func(n): return "res://scripts/map/%s" % n)
	paths.append("res://scripts/main.gd")
	for p in paths:
		var src2 := FileAccess.get_file_as_string(str(p))
		# #21 merged with economy's P3b: no request is open, so no marker is left
		if src2.contains("TODO(api-request"):
			open.append(str(p))
	t.ok(FileAccess.get_file_as_string("res://scripts/main.gd") != "", "scripts/main.gd is read")
	t.ok(open.is_empty(), "no TODO(api-request left in scripts/map or scripts/main.gd (%s)" % str(open))
	var cfg := IdleLogic.cfg()
	t.ok(not cfg.has("hold_word") and not cfg.has("hold_fmt") and not cfg["colors"].has("hold"), "the hold-timer chip's config keys are gone")


func _model(t: TestUtil) -> void:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	var m := MapModel.new(s)
	m.refresh(true)
	var real_held := IdleLogic.held_forts(m.forts).size()
	t.ok(real_held > 0 and m.margins.size() == real_held and int(m.supports["m"]) == real_held,
		"every fort the view holds has a margin, and N of M counts them (%d held)" % real_held)
	var m2 := MapModel.new(s)
	m2.nodes_demo = true
	m2.refresh(true)
	var demo_held := IdleLogic.held_forts(m2.forts).size()
	t.ok(demo_held > real_held and m2.margins.size() == demo_held, "the demo holds more forts and the model has every margin (%d)" % demo_held)
	var before := m2.margin_sig
	var id: String = m.margins.keys()[0]  # a fort the real view_projection carries
	var held := m2.margin_of(id)
	var proj := IdleLogic.projection(s, {"work": 0.0, "war": 1.0, "flood": 0.0}, m2.forts)
	t.ok(proj["margins"].has(id), "the projection carries the held fort")
	proj["margins"][id] = "will_fall" if held != "will_fall" else "safe"  # a margin the drag changes, whatever the fixture's
	m2.set_projection(proj)
	t.ok(m2.margin_of(id) == proj["margins"][id], "while a projection is set the chips read it")
	t.ok(m2.supports_now() == proj["war_supports"], "and so does N of M")
	t.ok(m2.margin_sig != before, "the signature changes when the projected margins differ")
	m2.clear_projection()
	t.ok(m2.margin_of(id) == held and m2.margin_sig == before, "cleared: the committed margins are back")
	t.ok(m2.supports_now() == m2.supports, "cleared: the committed N of M is back")
	# the valve panel: not dragging, N of M is the committed one even when the target differs
	var tgt := IdleLogic.projection(s, {"work": 1.0, "war": 0.0, "flood": 0.0}, m2.forts)
	tgt["war_supports"] = {"n": int(m2.supports["n"]) + 1, "m": int(m2.supports["m"])}  # a target the split hasn't reached
	t.ok(tgt["war_supports"] != m2.supports_now(), "the target's N of M differs from the committed (setup)")
	t.ok(IdleLogic.panel_projection(tgt, m2.supports_now(), false)["war_supports"] == m2.supports_now(), "not dragging: the panel's N of M is supports_now()")
	t.ok(IdleLogic.panel_projection(tgt, m2.supports_now(), true)["war_supports"] == tgt["war_supports"], "dragging: the panel shows the dragged valve's")
