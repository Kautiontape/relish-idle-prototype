extends Node2D
## One lot of the town view's static layer (VISUAL-LANGUAGE §2b): a locked dot grid, an empty
## lot's dashed blueprint, or its building's neon silhouette drawn by its look (TownModel.look_of),
## so its state reads by shape, not by blue alone:
##   staffed       its ink with glow, the slot ticks (filled = working, hollow = open) and pips;
##   unstaffed     a dim outline and the hollow slot ticks ("0/3": the wasted slots);
##   unpaid        a dim outline and a danger warning tick in the band (clear of the label above);
##   calm          its ink, steady (the view doesn't pulse it), no row;
##   heart         the crypt: its ink (violet home, undead away), lit, no row;
##   constructing  the reveal with its drawing head and the progress ticks.
## Slot ticks and pips are tallies: a gap after every view.pip_group, pips capped at pip_max, the
## count beside a row longer than a group. Redraws only when its display entry changes; the view
## pulses it via `self_modulate` (from Pulse.wave at `hops`) while `pulses`, and a construction
## reveal animates here, per frame on this lot only. Dead output pips and the counts draw in an
## unpulsed child (`_matte`): dead matter never brightens on the beat, text never pulses.
## Draws in the town view's coordinates. Colours from Palette, glows from LineGlow, numbers from
## configs/town.json `view`.

var model: TownModel
var vcfg: Dictionary = {}
## The model's lot dict (rect, unlocked, building entry, hops).
var lot: Dictionary = {}
## Street distance of this lot's door from the plaza (px), for Pulse.wave(hops, model.depth).
var hops := 0.0
## Relish's light on this lot (0 = none): the view multiplies its pulse by 1 + brighten.
var brighten := 0.0
## Whether the slab's wave pulses this lot: empty lots and the entries the model marks `pulse`.
var pulses := true

var _snap: Variant = null
var _shown := 0.0  # the construction reveal on screen; eases toward the entry's reveal
var _target := 0.0
var _matte: Node2D


func _ready() -> void:
	set_process(false)
	_matte = Node2D.new()
	_matte.name = "Matte"
	_matte.draw.connect(_draw_matte)
	add_child(_matte)


## Adopt `l` (the model's lot dict). Redraws only if it differs from the last one (or `force`).
## The status line isn't drawn here, so a status-only change doesn't redraw the lot.
func set_lot(l: Dictionary, force := false) -> void:
	lot = l
	hops = float(l.get("hops", 0.0))
	var b: Dictionary = l.get("building", {})
	pulses = b.is_empty() or bool(b.get("pulse", true))
	var drawn: Dictionary = b
	if b.has("status"):
		drawn = b.duplicate()
		drawn.erase("status")
		drawn.erase("status_parts")
	var snap := [l.get("rect", Rect2()), l.get("unlocked", false), drawn]
	if not force and _snap != null and snap == _snap:
		return
	var prev_bid := String(_snap[2].get("building_id", "")) if _snap != null else "<first>"
	_snap = snap
	_target = float(b.get("reveal", 1.0))
	# A building first seen (scene entry, or a different one) shows its progress as it stands; a
	# progress drop (an upgrade restarting) jumps; growth eases at view.reveal_rate.
	if prev_bid != String(b.get("building_id", "")) or _target < _shown or b.get("state", "") != "constructing" or b.get("upgrading", false):
		_shown = _target
	set_process(not is_equal_approx(_shown, _target))
	queue_redraw()
	_matte.queue_redraw()


func set_brighten(f: float) -> void:
	brighten = maxf(f, 0.0)


func _process(delta: float) -> void:
	if Pulse.reduced_motion:
		_shown = _target
	else:
		_shown = move_toward(_shown, _target, float(vcfg.get("reveal_rate", 0.0)) * delta)
	if is_equal_approx(_shown, _target):
		_shown = _target
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if lot.is_empty():
		return
	var r: Rect2 = lot["rect"]
	var b: Dictionary = lot.get("building", {})
	if not b.is_empty():
		_draw_building(b)
	elif lot.get("unlocked", false):
		_draw_blueprint(r)
	else:
		_draw_locked(r)


# ----------------------------------------------------------------- empty lots ----
func _draw_locked(r: Rect2) -> void:
	var spec: Dictionary = vcfg.get("locked_dot", {})
	var a := float(spec.get("alpha", 0.0))
	var step := float(spec.get("step_px", 0.0)) * model.scale
	if a <= 0.0 or step <= 0.0:
		return
	var col := Palette.c(String(spec.get("key", "contour")), a)
	var s := float(spec.get("size_px", 1.0))
	var nx := int(floor(r.size.x / step))
	var ny := int(floor(r.size.y / step))
	var origin := r.get_center() - Vector2(nx, ny) * step * 0.5
	for i in nx + 1:
		for j in ny + 1:
			draw_rect(Rect2(origin + Vector2(i, j) * step - Vector2(s, s) * 0.5, Vector2(s, s)), col)


func _draw_blueprint(r: Rect2) -> void:
	var spec: Dictionary = vcfg.get("blueprint_line", {})
	var col := Palette.c(String(spec.get("key", "town")), float(spec.get("alpha", 1.0)))
	var w := float(vcfg.get("blueprint_w_px", 1.0))
	var dash := float(vcfg.get("blueprint_dash_px", 4.0)) * model.scale
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		draw_dashed_line(c[i], c[(i + 1) % 4], col, w, dash)


# ------------------------------------------------------------------ buildings ----
## The silhouette box: the footprint above the pip band, keeping the footprint's aspect, centred.
func _sil_rect(fr: Rect2) -> Rect2:
	var band := float(vcfg.get("band_px", 0.0)) * model.scale
	var h := maxf(fr.size.y - band, 1.0)
	var w := fr.size.x * h / fr.size.y
	return Rect2(fr.position.x + (fr.size.x - w) * 0.5, fr.position.y, w, h)


func _band_y(fr: Rect2) -> float:
	return fr.end.y - float(vcfg.get("band_px", 0.0)) * model.scale * 0.5


## The pale core key for an ink, or "" if the ink has none.
static func _core_key(ink: String) -> String:
	return ink + "_core" if Palette.has(ink + "_core") else ""


func _draw_building(b: Dictionary) -> void:
	var fr: Rect2 = b["rect"]
	var sil := _sil_rect(fr)
	var bid := String(b["building_id"])
	var ink_key := String(b["ink"])
	var ink := Palette.c(ink_key)
	var dim_w := float(vcfg.get("dim_w_px", 1.0))
	var dim_glow := float(vcfg.get("glow_dim", 0.0))
	match String(b.get("look", "")):
		"constructing":
			var pls := model.strokes(bid, sil, _shown)
			for pl in pls:
				LineGlow.polyline(self, pl, ink, dim_w, dim_glow)
			if not pls.is_empty() and _shown < 1.0:
				var last: PackedVector2Array = pls[pls.size() - 1]
				_head(last[last.size() - 1], ink_key)
			_progress_ticks(fr, ink, float(b["progress"]))
		"unstaffed", "unpaid":
			var spec: Dictionary = vcfg.get("idle_line", {})
			var col := Palette.c(String(spec.get("key", "text_dim")), float(spec.get("alpha", 1.0)))
			for pl in model.strokes(bid, sil, 1.0):
				LineGlow.polyline(self, pl, col, dim_w, dim_glow)
			if String(b["look"]) == "unpaid":
				_warning(Vector2(fr.get_center().x, _band_y(fr)))
			else:
				_rows(fr, b)
		_:  # staffed, calm, heart
			var g := clampf(float(b["glow"]), 0.0, 1.0)
			var wr: Array = vcfg.get("sil_w_px", [1.0, 1.0])
			var gr: Array = vcfg.get("sil_glow", [0.0, 1.0])
			var w := lerpf(float(wr[0]), float(wr[1]), g)
			var halo := lerpf(float(gr[0]), float(gr[1]), g)
			var ck := _core_key(ink_key)
			var core := ink.lerp(Palette.c(ck), g * float(vcfg.get("sil_core_mix", 0.0))) if ck != "" else ink
			for pl in model.strokes(bid, sil, 1.0):
				LineGlow.polyline(self, pl, ink, w, halo, core)
			if String(b.get("look", "")) == "staffed":
				_rows(fr, b)
	if bool(b.get("upgrading", false)):  # it keeps working: the progress ticks ride the top edge
		_progress_ticks(fr, ink, float(b["progress"]), fr.position.y)


## The drawing head of a construction: a tiny hot core with a full-glow ring.
func _head(p: Vector2, ink_key: String) -> void:
	var spec: Dictionary = vcfg.get("head", {})
	var r := float(spec.get("core_px", 2.0)) * model.scale
	var ck := _core_key(ink_key)
	var ink := Palette.c(ink_key)
	LineGlow.ring(self, p, r * float(spec.get("ring_mul", 1.0)), ink, float(spec.get("ring_w_px", 1.0)),
		float(spec.get("glow", 1.0)))
	draw_circle(p, r, Palette.c(ck) if ck != "" else ink)


## Construction progress: view.progress_ticks ticks across the band; done ticks are full-height
## ink strokes, the rest short thin ones (shape, not only colour).
func _progress_ticks(fr: Rect2, ink: Color, progress: float, at_y := INF) -> void:
	var n := int(vcfg.get("progress_ticks", 0))
	if n <= 0:
		return
	var th := float((vcfg.get("slot_tick_px", [2.0, 8.0]) as Array)[1]) * model.scale
	var y := _band_y(fr) if at_y == INF else at_y
	var tw: Array = vcfg.get("progress_tick_w_px", [1.0, 1.0])
	var step := fr.size.x / float(n + 1)
	var done := floori(progress * n + 1e-6)
	for i in n:
		var x := fr.position.x + step * (i + 1)
		if i < done:
			draw_line(Vector2(x, y - th * 0.5), Vector2(x, y + th * 0.5), ink, float(tw[0]))
		else:
			draw_line(Vector2(x, y - th * 0.2), Vector2(x, y + th * 0.2), ink, float(tw[1]))


## Unpaid: a danger triangle with a bang, drawn as lines, centred on `c` (the band under the
## silhouette, where the pip row would be: clear of the label above the lot). At least
## view.warn.size_px tall whatever the view's scale.
func _warning(c: Vector2) -> void:
	var spec: Dictionary = vcfg.get("warn", {})
	var base := float(spec.get("size_px", 16.0))
	var s := maxf(base * model.scale, base)
	var col := Palette.c("danger")
	var top := c + Vector2(0.0, -s * 0.5)
	var tri := PackedVector2Array([top, top + Vector2(s * 0.55, s * 0.95), top + Vector2(-s * 0.55, s * 0.95), top])
	LineGlow.polyline(self, tri, col, float(spec.get("line_px", 1.0)), float(spec.get("glow", 0.0)))
	draw_line(top + Vector2(0, s * 0.3), top + Vector2(0, s * 0.6), col, float(spec.get("bang_px", 1.0)))
	draw_circle(top + Vector2(0, s * 0.75), float(spec.get("dot_px", 1.0)), col)


## The band under an active building: slot ticks (filled = staffed, hollow = open) for job
## buildings, then the output pips in their matter colour. Both are counts, never brightness.
func _rows(fr: Rect2, b: Dictionary) -> void:
	var worker := Palette.c("undead")
	for m in _row_marks(fr, b):
		match m[0]:
			"staffed":
				draw_line(m[1] - Vector2(0, m[2].y * 0.5), m[1] + Vector2(0, m[2].y * 0.5), worker, m[2].x)
			"open":
				draw_rect(Rect2(m[1] - m[2] * 0.5, m[2]), worker, false, float(vcfg.get("slot_open_w_px", 1.0)))
			"pip":
				_pip(m[1], m[2].x, String(m[3]))


## Dead pips (matte squares) and the pip count, in the unpulsed child.
func _draw_matte() -> void:
	var b: Dictionary = lot.get("building", {})
	if b.is_empty():
		return
	if bool(b.get("upgrading", false)):  # the level mark: "+1", upright
		var spec: Dictionary = vcfg.get("upgrade_mark", {})
		var font := ThemeDB.fallback_font
		var fs := maxi(int(spec.get("px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
		var txt := String(spec.get("text", ""))
		var fr: Rect2 = b["rect"]
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_matte.draw_string(font, Vector2(fr.end.x - w, fr.position.y + font.get_ascent(fs)), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c(String(spec.get("key", "text"))))
	if not String(b.get("look", "")) in ["staffed", "unstaffed"]:
		return
	for m in _row_marks(b["rect"], b):
		match m[0]:
			"dead":
				_matte.draw_rect(Rect2(m[1] - m[2] * 0.5, m[2]), Palette.c(String(m[3])))
			"count":
				var font := ThemeDB.fallback_font
				var fs := maxi(int(vcfg.get("pip_count_px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
				var base := Vector2(m[1].x, m[1].y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
				_matte.draw_string(font, base, String(m[3]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c("text_dim"))


## The band's marks, left to right, centred: [kind, centre, size, pip key]. kind is "staffed",
## "open" (slot ticks), "pip" (a glowing pip), "dead" (a matte pip) or "count" (the integer beside
## a long pip row: [kind, left-middle point, size, text]). Ticks and pips are tallies with a gap
## after every view.pip_group.
func _row_marks(fr: Rect2, b: Dictionary) -> Array:
	var out: Array = []
	var slots_all := int(b.get("slots", 0))
	var tk := TownModel.slot_ticks(slots_all, TownModel.working_of(float(b.get("staffed", 0.0))), int(vcfg.get("pip_max", 8)))
	var slots := int(tk["shown"])  # capped at pip_max like the pips, the whole count beside
	var staffed := int(tk["working"])
	var pip_key := String(b.get("pip_key", ""))
	var pips := int(b.get("pips", 0)) if pip_key != "" else 0
	if slots <= 0 and pips <= 0:
		return out
	var k := model.scale
	var tick: Array = vcfg.get("slot_tick_px", [2.0, 8.0])
	var ts := Vector2(float(tick[0]), float(tick[1])) * k
	var pw := float(vcfg.get("pip_px", 4.0)) * k
	var gap := float(vcfg.get("pip_gap_px", 3.0)) * k
	var tally := int(vcfg.get("pip_group", 0))
	var tg := float(vcfg.get("pip_group_gap_px", 0.0)) * k
	var group := float(vcfg.get("group_gap_px", 6.0)) * k if slots > 0 and pips > 0 else 0.0
	var count := TownModel.count_label(int(b.get("pip_count", pips)), tally) if pips > 0 else ""
	var tcount := String(tk["count"])  # beside a capped tick row
	var fs := maxi(int(vcfg.get("pip_count_px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
	var cw := 0.0
	if count != "":
		cw = gap * 2.0 + ThemeDB.fallback_font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tw := 0.0
	if tcount != "":
		tw = gap * 2.0 + ThemeDB.fallback_font.get_string_size(tcount, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var sw := TownModel.row_width(slots, ts.x, gap, tg, tally)
	var pwid := TownModel.row_width(pips, pw, gap, tg, tally)
	var x := fr.get_center().x - (sw + tw + group + pwid + cw) * 0.5
	var y := _band_y(fr)
	var so := TownModel.row_offsets(slots, ts.x, gap, tg, tally)
	for i in slots:
		out.append(["staffed" if i < staffed else "open", Vector2(x + so[i] + ts.x * 0.5, y), ts, ""])
	if tcount != "":
		out.append(["count", Vector2(x + sw + gap * 2.0, y), Vector2.ZERO, tcount])
	x += sw + tw + group
	var dead := pip_key == "dead" or pip_key == "dead_lit"
	var po := TownModel.row_offsets(pips, pw, gap, tg, tally)
	for i in pips:
		out.append(["dead" if dead else "pip", Vector2(x + po[i] + pw * 0.5, y), Vector2(pw, pw), pip_key])
	if count != "":
		out.append(["count", Vector2(x + pwid + gap * 2.0, y), Vector2.ZERO, count])
	return out


## One glowing output pip: undead a ring, living a diamond (dead is a matte square, _draw_matte),
## so the three read apart without colour (and apart from the slot bars).
func _pip(c: Vector2, s: float, key: String) -> void:
	var h := s * 0.5
	var col := Palette.c(key)
	var ck := _core_key(key)
	var core := Palette.c(ck) if ck != "" else col
	var glow := float(vcfg.get("pip_glow", 0.5))
	var w := float(vcfg.get("pip_w_px", 1.0))
	if key == "living":
		var d := PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0), c + Vector2(0, -h)])
		LineGlow.polyline(self, d, col, w, glow, core)
	else:
		LineGlow.ring(self, c, h * 0.8, col, w, glow, core)
