class_name BossLanes
extends Node2D
## The fronts on the field (MECHANICS 6 phase 1, VISUAL-LANGUAGE 2c): four lanes from the south of
## the arena to Vei's court, one per front. Each draws its horde as a stream of `undead` glyphs
## marching up into a guard line of `living` glyphs, with Vei's `vei` rings behind it. Everything
## here is procedural: glyph positions come from the front's progress and a march clock, there is
## no physics per glyph, and one `_draw` walks the lanes (BossLogic does the maths). Each lane's
## glyphs go out as a few batched draw_multiline calls (strokes, heads, guard bows, guard heads,
## flow dashes), not one call per glyph.
##   stream density   BossLogic.stream_count(have) (phase 2: thinned by the horde left)
##   guard thickness  BossLogic.guard_rows(need) rows of guards_across
##   contact point    BossLogic.contact_s(progress): the stream pushes the guard line back
##   cleared          the guard line breaks (break_s) and the lane runs green to Vei's court
## Phase-1 raised undead run from Relish into their lane's stream (`add_runners`) and vanish into it.
## The party's big undead lead their front's stream as nested diamonds until the break begins.
## Phase 2 adds the anchor sigils. The set pieces: `win_f` (every lane runs green toward Vei, then
## `frozen`) and `lose_f` (the streams drain into her and the lanes dim). Reduced motion: the march
## holds still and static chevrons show the direction. The labels (front, have / need, status) sit
## on a z 37 child above the trance dim so the player can read which lane a raise will feed.

var boss: Node2D = null
var lanes: Array = []          # BossLogic.lanes
var cfg: Dictionary = {}       # vei.json
var fronts: Array = []         # [{id, have, need, progress, cleared}] (VeiFronts phase-1 state)
var party_count: Array = [0, 0, 0, 0]
var party_shown := true        # phase 1: the big undead lead the streams; phase 2: they are units
var phase := 1
var anchors: Array = []
var horde_frac := 1.0          # phase 2: the horde left, 0..1
var win_f := -1.0              # >= 0: the victory run, 0..1 (green toward Vei)
var lose_f := -1.0             # >= 0: the loss drain, 0..1
var frozen := false            # victory: the lines stop

var _clock := 0.0              # march clock, scene seconds
var _break_t: Array = [-1.0, -1.0, -1.0, -1.0]
var _flash: Array = [0.0, 0.0, 0.0, 0.0]
var _runners: Array = []       # [{p: Vector2, lane: int}]
var _labels: Labels = null


func setup(p_boss: Node2D, p_lanes: Array, p_cfg: Dictionary) -> void:
	boss = p_boss
	lanes = p_lanes
	cfg = p_cfg
	z_index = 14   # under the walls (20) and units (30); dimmed by the trance like every line
	_labels = Labels.new()
	_labels.lanes_node = self
	_labels.z_as_relative = false
	_labels.z_index = 37
	add_child(_labels)


func lc() -> Dictionary:
	return cfg.get("lanes", {})


## A front's guard line broke this frame (phase 1, or every lane at victory).
func on_cleared(i: int) -> void:
	if i >= 0 and i < _break_t.size() and float(_break_t[i]) < 0.0:
		_break_t[i] = 0.0


func flash(i: int) -> void:
	if i >= 0 and i < _flash.size():
		_flash[i] = 1.0


## `n` raised undead leave `from` (round Relish) and run into lane `i`'s stream.
func add_runners(i: int, n: int, from: Vector2, rng: RandomNumberGenerator) -> void:
	for k in n:
		var ang := TAU * k / float(maxi(1, n)) + rng.randf() * 0.8
		_runners.append({"p": from + Vector2(48.0 + rng.randf_range(-8.0, 20.0), 0.0).rotated(ang), "lane": i})


func runners_left() -> int:
	return _runners.size()


func _process(delta: float) -> void:
	if not frozen:
		_clock += delta
	for i in _break_t.size():
		if float(_break_t[i]) >= 0.0:
			_break_t[i] = float(_break_t[i]) + delta
		_flash[i] = maxf(0.0, float(_flash[i]) - delta * 2.0)
	_step_runners(delta)
	queue_redraw()


func _step_runners(delta: float) -> void:
	if _runners.is_empty():
		return
	var spd := float(lc().get("runner_px_s", 170.0))
	var keep: Array = []
	for r in _runners:
		var i: int = r["lane"]
		var a: Vector2 = lanes[i]["a"]
		var head := BossLogic.point_at(lanes[i], _contact(i))
		var p: Vector2 = r["p"]
		var goal := a.lerp(head, BossLogic.seg_t(p, a, head))
		if p.distance_to(goal) <= 10.0:
			if boss != null and boss.fx_root != null:
				RaidFx.ring(boss.fx_root, goal, Palette.c("undead", 0.7), 18.0, 0.3, 2.0)
			_flash[i] = 1.0
			continue
		r["p"] = p.move_toward(goal, spd * delta)
		keep.append(r)
	_runners = keep


func _front(i: int) -> Dictionary:
	return fronts[i] if i < fronts.size() else {"have": 0.0, "need": 1.0, "progress": 0.0, "cleared": false}


func _cleared(i: int) -> bool:
	return bool(_front(i).get("cleared", false)) or win_f >= 0.0


## The lane fraction where the stream meets the guard line (1 once the lane runs to Vei).
func _contact(i: int) -> float:
	if _cleared(i) and float(_break_t[i]) >= float(lc().get("break_s", 0.8)) * 0.5:
		return 1.0
	return BossLogic.contact_s(float(_front(i).get("progress", 0.0)), cfg)


# ------------------------------------------------------------------- draw ---
func _draw() -> void:
	var t0 := BossDev.pt()
	var reduced: bool = Pulse.reduced_motion
	var dim := 1.0 - 0.8 * maxf(lose_f, 0.0)
	for i in lanes.size():
		_draw_lane(i, reduced, dim)
	for p in anchors:
		_draw_anchor(p, reduced)
	var r := float(lc().get("glyph_r_px", 8.0))
	for rn in _runners:
		var i: int = rn["lane"]
		var head := BossLogic.point_at(lanes[i], _contact(i))
		var p: Vector2 = rn["p"]
		_undead(p, (head - p).normalized() if head.distance_to(p) > 1.0 else BossLogic.lane_dir(lanes[i]), r, 1.0)
	BossDev.pa("lanes", t0)


func _draw_lane(i: int, reduced: bool, dim: float) -> void:
	var lane: Dictionary = lanes[i]
	var a: Vector2 = lane["a"]
	var b: Vector2 = lane["b"]
	var dir := BossLogic.lane_dir(lane)
	var perp := dir.orthogonal()
	var len_px := BossLogic.lane_len(lane)
	var f := _front(i)
	var cleared := _cleared(i)
	var s_c := _contact(i)
	var glyph_r := float(lc().get("glyph_r_px", 8.0))
	var band := float(lc().get("band_px", 34.0))
	var fl := float(_flash[i])
	# the track: a faint matte groove the whole way to her court
	draw_line(a, b, Palette.c("contour", 0.9 * dim), 6.0)
	if cleared:
		_flow(a, b, len_px, dir, dim, reduced)
	elif reduced:
		_chevrons(a, b, len_px, dir, dim)
	# the stream: undead marching from the south start up to the contact point
	var count := BossLogic.stream_count(float(f.get("have", 0.0)), cfg)
	if phase >= 2 and cleared:
		count = 0 if horde_frac <= 0.0 else maxi(2, roundi(count * clampf(horde_frac, 0.0, 1.0)))
	var s0 := 0.0
	var s_end := s_c
	if lose_f >= 0.0:
		s0 = s_end * lose_f   # the streams drain into Vei from the back
		count = roundi(count * (1.0 - lose_f))
	var march := 0.0 if reduced else _clock * float(lc().get("march_px_s", 38.0)) * (1.0 + 3.0 * maxf(lose_f, 0.0))
	var ss := BossLogic.stream_s(count, s_end - s0, len_px, march)
	var step_px := (s_end - s0) * len_px / float(maxi(1, count))
	var base := floori(march / maxf(step_px, 0.001))
	var strokes := PackedVector2Array()
	var heads := PackedVector2Array()
	for k in ss.size():
		var g := k - base
		var lat := sin(float(g) * 2.39 + float(i) * 1.7) * band * 0.5
		var p := BossLogic.point_at(lane, s0 + ss[k]) + perp * lat
		strokes.append(p - dir * glyph_r)
		strokes.append(p + dir * glyph_r)
		heads.append(p + dir * (glyph_r * 0.7 + 1.0))
		heads.append(p + dir * (glyph_r * 1.3 + 1.0))
	_undead_batch(strokes, heads, glyph_r, dim * (0.75 + 0.25 * fl))
	# the party's big undead lead the stream
	if party_shown and phase == 1:
		var n := int(party_count[i]) if i < party_count.size() else 0
		for k in n:
			var lat2 := (float(k) - (n - 1) * 0.5) * 34.0
			_big(BossLogic.point_at(lane, s_c) - dir * 26.0 + perp * lat2, glyph_r * 2.1, dim)
	# the guard line (and its break)
	var bt := float(_break_t[i])
	var break_s := float(lc().get("break_s", 0.8))
	if not cleared or (bt >= 0.0 and bt < break_s):
		var kf := clampf(bt / break_s, 0.0, 1.0) if bt >= 0.0 else 0.0
		_guard_line(lane, s_c, dir, perp, int(BossLogic.guard_rows(float(f.get("need", 1.0)), cfg)), kf, dim, reduced)
	# Vei's rings behind the line, at her court end
	var vcol := Palette.c("vei", (0.35 if cleared else 0.85) * dim)
	LineGlow.ring(self, b, 15.0, vcol, 2.0, 0.4)
	LineGlow.ring(self, b, 24.0, Palette.c("vei", (0.2 if cleared else 0.5) * dim), 1.5, 0.0)


## The lane runs green toward Vei: undead dashes at a mid rate (VISUAL-LANGUAGE law 3). Their
## offset is the lane's own clock, so the victory freeze stops them.
func _flow(a: Vector2, b: Vector2, len_px: float, dir: Vector2, dim: float, reduced: bool) -> void:
	var u := 0.85 if win_f >= 0.0 else 0.6
	var ch := Pulse.channels(u, Palette.hue("undead"))
	var period := float(ch["period"])
	var dash := float(ch["dash"])
	var off := 0.0 if reduced else fposmod(_clock * float(ch["speed"]), period)
	var col: Color = ch["color"]
	col.a *= dim
	var segs := PackedVector2Array()
	var d := -period + off
	while d < len_px:
		var d0 := maxf(0.0, d)
		var d1 := minf(len_px, d + dash)
		if d1 > d0:
			segs.append(a + dir * d0)
			segs.append(a + dir * d1)
		d += period
	if not segs.is_empty():
		for l in LineGlow.layers(col, float(ch["width"]), 0.6, Palette.c("undead_core", col.a)):
			draw_multiline(segs, l[1], l[0])
	if reduced:
		_chevrons(a, b, len_px, dir, dim)


## Static chevrons along the lane pointing at Vei (reduced motion keeps the direction).
func _chevrons(a: Vector2, _b: Vector2, len_px: float, dir: Vector2, dim: float) -> void:
	var perp := dir.orthogonal()
	var d := 60.0
	while d < len_px - 20.0:
		var p := a + dir * d
		var col := Palette.c("undead", 0.45 * dim)
		draw_line(p - dir * 6.0 + perp * 6.0, p, col, 2.0)
		draw_line(p - dir * 6.0 - perp * 6.0, p, col, 2.0)
		d += 110.0


func _guard_line(lane: Dictionary, s_c: float, dir: Vector2, perp: Vector2, rows: int,
		kf: float, dim: float, reduced: bool) -> void:
	var across := maxi(1, int(lc().get("guards_across", 5)))
	var row_px := float(lc().get("row_px", 16.0))
	var band := float(lc().get("band_px", 34.0)) * 1.3
	var r := float(lc().get("glyph_r_px", 8.0))
	var head := BossLogic.point_at(lane, s_c)
	var alpha := (1.0 - kf) * dim
	if alpha <= 0.0:
		return
	# one living glyph's shape (a bow arc and a hollow ring head, facing back down the lane),
	# translated per guard into two batched multilines
	var face := -dir
	var bow_c := -face * (r * 0.55)
	var a0 := face.angle() - 1.2
	var bow := _arc_pts(bow_c, r * 1.1, a0, a0 + 2.4, 8)
	var ring := _arc_pts(bow_c + face * r * 1.1, r * 0.45, 0.0, TAU, 10)
	var mb := PackedVector2Array()
	var mr := PackedVector2Array()
	for row in rows:
		for c in across:
			var lat := (float(c) - (across - 1) * 0.5) * band / maxf(1.0, across - 1)
			var p := head + dir * (14.0 + row * row_px) + perp * lat
			if kf > 0.0:
				# the line breaks: guards scatter sideways and back toward her court, fading
				var sgn := -1.0 if c < (across - 1) * 0.5 else 1.0
				var push := 0.0 if reduced else kf * (30.0 + 12.0 * row)
				p += perp * sgn * push + dir * push * 0.5
			for j in bow.size() - 1:
				mb.append(p + bow[j])
				mb.append(p + bow[j + 1])
			for j in ring.size() - 1:
				mr.append(p + ring[j])
				mr.append(p + ring[j + 1])
	draw_multiline(mb, Palette.c("living", alpha), maxf(2.4, r * 0.26))
	draw_multiline(mr, Palette.c("living_core", alpha), 1.6)


## Points along an arc (count segments), for batching one glyph shape many times.
static func _arc_pts(c: Vector2, r: float, a0: float, a1: float, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in count + 1:
		out.append(c + Vector2(r, 0.0).rotated(lerpf(a0, a1, float(k) / float(count))))
	return out


## A lane's stream in three calls: a faint halo under every stroke, the strokes, and the heads
## (raid_unit.gd's undead glyph: one stroke along the heading with a core at its head).
func _undead_batch(strokes: PackedVector2Array, heads: PackedVector2Array, r: float, alpha: float) -> void:
	if strokes.is_empty():
		return
	var w := maxf(2.0, r * 0.22)
	draw_multiline(strokes, Palette.c("undead", 0.18 * alpha), w + 4.0)
	draw_multiline(strokes, Palette.c("undead", clampf(alpha, 0.0, 1.0)), w)
	draw_multiline(heads, Palette.c("undead_core", clampf(alpha, 0.0, 1.0)), r * 0.6)


## An undead glyph (raid_unit.gd's language): one stroke along the heading with a core dot at the head.
func _undead(p: Vector2, dir: Vector2, r: float, alpha: float) -> void:
	var col := Palette.c("undead", clampf(alpha, 0.0, 1.0))
	draw_line(p - dir * r, p + dir * r, Palette.c("undead", 0.18 * alpha), maxf(2.0, r * 0.22) + 4.0)
	draw_line(p - dir * r, p + dir * r, col, maxf(2.0, r * 0.22))
	draw_circle(p + dir * (r + 1.0), r * 0.3, Palette.c("undead_core", clampf(alpha, 0.0, 1.0)))


## A big undead: nested diamonds (two) with a core dot, breathing on the Pulse.
func _big(p: Vector2, r: float, dim: float) -> void:
	var col := Palette.c("undead", dim)
	var k := 1.0 + 0.06 * Pulse.wave()
	for j in 2:
		var rr := r * k * (1.0 - 0.3 * j)
		var pts := PackedVector2Array([p + Vector2(0, -rr), p + Vector2(rr, 0), p + Vector2(0, rr), p + Vector2(-rr, 0), p + Vector2(0, -rr)])
		if j == 0:
			LineGlow.polyline(self, pts, col, 2.0, 0.5)
		else:
			draw_polyline(pts, col, 1.6)
	draw_circle(p, 3.4, Palette.c("undead_core", dim))


## An anchor: where the ferried fall. A violet double ring (Relish raises here) round a matte dead
## core, with three ticks that turn on the tempo (steady under reduced motion).
func _draw_anchor(p: Vector2, reduced: bool) -> void:
	var ac: Dictionary = cfg.get("anchors", {})
	var r := float(ac.get("radius_px", 58.0))
	var w := Pulse.wave()
	var dim := 1.0 - 0.8 * maxf(lose_f, 0.0)
	LineGlow.ring(self, p, r, Palette.c("relish", (0.45 + 0.3 * w) * dim), 2.0, 0.5)
	LineGlow.matte_ring(self, p, r * 0.55, Palette.c("dead", 0.9 * dim), 2.0)
	var spin := 0.0 if reduced else Pulse.phase() * TAU / 3.0
	var ticks := PackedVector2Array()
	for k in 3:
		var ang := TAU * k / 3.0 + spin - PI * 0.5
		var d := Vector2.RIGHT.rotated(ang)
		ticks.append(p + d * (r + 4.0))
		ticks.append(p + d * (r + 14.0))
	draw_multiline(ticks, Palette.c("relish", 0.8 * dim), 2.0)


## The lane labels: front, have / need as integers, and a status word. On screen at label_px
## whatever the camera zoom, above the trance dim.
class Labels:
	extends Node2D
	var lanes_node: BossLanes = null
	var _sig := ""

	## Redraw only when what the labels say changes: the signature is the exact strings and status
	## colours drawn, plus the zoom and the loss dim.
	func _process(_d: float) -> void:
		var ln := lanes_node
		if ln == null or ln.boss == null or ln.boss.cam == null:
			return
		var sig := "%.3f|%.2f" % [ln.boss.cam.zoom.x, maxf(ln.lose_f, 0.0)]
		for i in ln.lanes.size():
			sig += "|" + "/".join(lane_text(i))
		if sig != _sig:
			_sig = sig
			queue_redraw()

	## Lane i's label: [front name, "have X / need Y", status, status palette key].
	func lane_text(i: int) -> PackedStringArray:
		var ln := lanes_node
		var f := ln._front(i)
		var have := float(f.get("have", 0.0))
		var need := float(f.get("need", 0.0))
		var status := "SHORT %d" % ceili(need - have - 0.0001)
		var skey := "living"
		if bool(f.get("cleared", false)):
			status = "CLEARED"
			skey = "undead"
		elif ln.phase >= 2:
			status = "SENDS GUARDS"
		elif have >= need:
			status = "MET · breaking"
			skey = "undead"
		return PackedStringArray([String(ln.lanes[i]["id"]).to_upper(),
			"have %d / need %d" % [floori(have + 0.0001), ceili(need - 0.0001)], status, skey])

	func _draw() -> void:
		var t0 := BossDev.pt()
		_draw_labels()
		BossDev.pa("labels", t0)

	func _draw_labels() -> void:
		var ln := lanes_node
		if ln == null or ln.boss == null or ln.boss.cam == null:
			return
		var zoom: float = maxf(0.1, ln.boss.cam.zoom.x)
		var px := float(ln.lc().get("label_px", 15))
		var fs := int(round(px / zoom))
		var font := ThemeDB.fallback_font
		var dim := 1.0 - 0.7 * maxf(ln.lose_f, 0.0)
		for i in ln.lanes.size():
			var at: Vector2 = (ln.lanes[i]["a"] as Vector2) + Vector2(0.0, 26.0 / zoom)
			var txt := lane_text(i)
			var lines := [[txt[0], "text"], [txt[1], "text"], [txt[2], txt[3]]]
			var y := at.y
			var wmax := 0.0
			for ln2 in lines:
				wmax = maxf(wmax, font.get_string_size(ln2[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
			draw_rect(Rect2(at.x - wmax * 0.5 - 6.0 / zoom, y - fs * 0.95, wmax + 12.0 / zoom, fs * 3.35),
				Palette.c("ground", 0.72 * dim))
			for ln2 in lines:
				var tw := font.get_string_size(ln2[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(font, Vector2(at.x - tw * 0.5, y), ln2[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Palette.c(ln2[1], dim))
				y += fs * 1.1


## One cracked violet ring per backup Relish has spent in this fight; it never comes back
## (VISUAL-LANGUAGE 2c). A child of Relish, drawn just above her.
class BackupMarks:
	extends Node2D
	var boss: Node2D = null
	var _n := -1

	## Redraw only when a backup is spent (the marks ride on Relish's transform).
	func _process(_d: float) -> void:
		if boss != null and boss.backups_spent_total() != _n:
			_n = boss.backups_spent_total()
			queue_redraw()

	func _draw() -> void:
		if boss == null:
			return
		var n: int = boss.backups_spent_total()
		var bc: Dictionary = boss.vcfg().get("backups", {})
		for i in n:
			var rr: float = float(bc.get("mark_radius_px", 40.0)) + float(bc.get("mark_step_px", 6.0)) * i
			for j in 3:   # three shards with two gaps and a break: reads as cracked
				var a0: float = TAU * j / 3.0 + 0.7 * i + 0.2
				LineGlow.arc(self, Vector2.ZERO, rr, a0, a0 + TAU / 3.0 - 0.55, Palette.c("relish", 0.95), 2.2, 0.4)
