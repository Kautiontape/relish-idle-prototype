extends Node2D
## Build-mode canvas additions of the town view, on their own node so the lot drawing (town_lot.gd)
## stays untouched: the hover outline and the hovered building's status tag under it (its one-line
## status from the model, rates oblique), the day-1 suggestion (a pulsing dashed outline, a tag, a
## dismiss x), the queue's numbered ghosts and the "construction started" flash.
## Everything is a line: `select` for UI (never matter), `town` ink for ghost silhouettes. Tempo
## from Pulse (the suggestion breathes on the slab's wave; the flash starts on the next beat);
## reduced motion holds both still. Tuning: configs/town.json `view` (hover, suggest, ghost, flash).

var model: TownModel
var vcfg: Dictionary = {}
## The lot under the pointer ("" for none) and the lots a hovered catalog row fits.
var hover_lot := ""
var row_lots: Array = []
## TownModel.ghost_layout() of the queue.
var ghosts: Array = []
## Lot id -> its building's status parts ([[text, oblique]], TownModel.status_of) for the hover tag.
var statuses: Dictionary = {}

var _sug_lot := ""
var _sug_label := ""
var _flashes: Array = []  # {lot, t}: t < 0 waits for the next beat
var _last_phase := 0.0


func set_hover(lot_id: String) -> void:
	if lot_id != hover_lot:
		hover_lot = lot_id
		queue_redraw()


func set_row_lots(lots: Array) -> void:
	if lots != row_lots:
		row_lots = lots.duplicate()
		queue_redraw()


## The built lots' status lines; redraws only when the hovered one changed.
func set_statuses(st: Dictionary) -> void:
	var changed: bool = hover_lot != "" and st.get(hover_lot, []) != statuses.get(hover_lot, [])
	statuses = st
	if changed:
		queue_redraw()


func set_ghosts(g: Array) -> void:
	if g != ghosts:
		ghosts = g
		queue_redraw()


## The suggested lot and the building's label ("" lot clears it).
func set_suggestion(lot_id: String, label: String) -> void:
	if lot_id != _sug_lot or label != _sug_label:
		_sug_lot = lot_id
		_sug_label = label
		_wake()
		queue_redraw()


func suggested_lot() -> String:
	return _sug_lot


## A short "construction started" flash on `lot_id`, from the next beat.
func flash(lot_id: String) -> void:
	_flashes.append({"lot": lot_id, "t": -1.0})
	_wake()


func _wake() -> void:
	set_process(_sug_lot != "" or not _flashes.is_empty())


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	var ph := Pulse.phase(0.0, 1.0)
	var wrapped := ph < _last_phase - 0.5
	_last_phase = ph
	var beat_s := Pulse.tempo_ms / 1000.0
	for f in _flashes:
		if f["t"] < 0.0:
			if wrapped or Pulse.reduced_motion:
				f["t"] = 0.0
		else:
			f["t"] += delta
	_flashes = _flashes.filter(func(f): return f["t"] < beat_s)
	_wake()
	queue_redraw()


## The suggestion's dismiss hit box (at least 44 px square, grown outward from the x so it never
## covers the tag's text); an empty rect when none is shown.
func dismiss_rect() -> Rect2:
	var lay := _sug_layout()
	if lay.is_empty():
		return Rect2()
	return BuildSort.dismiss_box(lay["x_cell"], lay["plate"], bool(lay["above"]))


func _draw() -> void:
	if model == null:
		return
	_draw_hover()
	_draw_suggestion()
	_draw_ghosts()
	_draw_flashes()
	_draw_tip()


func _outline(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position])


func _lot_rect(id: String, grow: float) -> Rect2:
	var l := model.lot(id)
	return (l["rect"] as Rect2).grow(grow) if not l.is_empty() else Rect2()


func _draw_hover() -> void:
	var h: Dictionary = vcfg.get("hover", {})
	var col := Palette.c("select", float(h.get("alpha", 1.0)))
	var seen := {}
	var ids: Array = row_lots.duplicate()
	if hover_lot != "":
		ids.append(hover_lot)
	for id in ids:
		var l := model.lot(String(id))
		if seen.has(id) or l.is_empty() or not bool(l["unlocked"]):
			continue
		seen[id] = true
		draw_polyline(_outline(_lot_rect(String(id), float(h.get("grow_px", 0.0)))), col, float(h.get("w_px", 1.0)))


# ------------------------------------------------------------- suggestion ----
func _sug_layout() -> Dictionary:
	if _sug_lot == "" or model == null or model.lot(_sug_lot).is_empty():
		return {}
	var s: Dictionary = vcfg.get("suggest", {})
	var font := ThemeDB.fallback_font
	var fs := maxi(int(vcfg.get("label_px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
	var text := String(s.get("tag_prefix", "")) + _sug_label
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pad := float(s.get("tag_pad_px", 4.0))
	var x_w := float(s.get("x_px", 5.0)) * 2.0 + pad * 2.0
	var r := _lot_rect(_sug_lot, float(vcfg.get("hover", {}).get("grow_px", 0.0)) + 2.0)
	var h := sz.y + pad
	var w := sz.x + pad * 2.0 + x_w
	var host: Vector2 = (get_parent() as Control).size if get_parent() is Control else Vector2(1e6, 1e6)
	var room := BuildSort.dismiss_room(x_w)  # the dismiss box reaches past the plate's right end
	var p := Vector2(clampf(r.get_center().x - w * 0.5, 4.0, maxf(host.x - w - room - 4.0, 4.0)), r.position.y - h - 6.0)
	var above := p.y >= 4.0
	if not above:
		p.y = r.end.y + 6.0
	var plate := Rect2(p, Vector2(w, h))
	return {"plate": plate, "text": text, "fs": fs, "x_cell": Rect2(plate.end.x - x_w, plate.position.y, x_w, h), "pad": pad,
		"above": above}


func _draw_suggestion() -> void:
	var lay := _sug_layout()
	if lay.is_empty():
		return
	var s: Dictionary = vcfg.get("suggest", {})
	var a: Array = s.get("alpha", [1.0, 1.0])
	var k := Pulse.wave(0.0, 1.0)
	var col := Palette.c("select", lerpf(float(a[0]), float(a[1]), k))
	var r := _lot_rect(_sug_lot, float(vcfg.get("hover", {}).get("grow_px", 0.0)) + 2.0)
	var c := _outline(r)
	for i in 4:
		draw_dashed_line(c[i], c[i + 1], col, float(s.get("w_px", 1.0)), float(s.get("dash_px", 6.0)))
	var plate: Rect2 = lay["plate"]
	draw_rect(plate, Palette.c("ground"))
	draw_polyline(_outline(plate), Palette.c("select", 0.8), 1.0)
	var font := ThemeDB.fallback_font
	var fs: int = lay["fs"]
	var base := Vector2(plate.position.x + float(lay["pad"]), plate.position.y + (plate.size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	draw_string(font, base, String(lay["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c("text"))
	var xc: Vector2 = (lay["x_cell"] as Rect2).get_center()
	var xr := float(s.get("x_px", 5.0))
	draw_line(xc + Vector2(-xr, -xr), xc + Vector2(xr, xr), Palette.c("text"), 1.5)
	draw_line(xc + Vector2(-xr, xr), xc + Vector2(xr, -xr), Palette.c("text"), 1.5)


# ----------------------------------------------------------------- ghosts ----
func _draw_ghosts() -> void:
	var g: Dictionary = vcfg.get("ghost", {})
	var ink := String((vcfg.get("blueprint_line", {}) as Dictionary).get("key", "town"))
	var col := Palette.c(ink, float(g.get("alpha", 0.4)))
	for e in ghosts:
		var rect: Rect2 = e["rect"]
		if bool(e["upgrade"]):
			_text_at("+1", rect.get_center(), int(g.get("plus_px", 14)), "text")
		else:
			for pl in model.strokes(String(e["building_id"]), rect, 1.0):
				for i in pl.size() - 1:
					draw_dashed_line(pl[i], pl[i + 1], col, float(g.get("w_px", 1.0)), float(g.get("dash_px", 5.0)))
		_draw_ring(e, g)


func _draw_ring(e: Dictionary, g: Dictionary) -> void:
	var c: Vector2 = e["ring"]
	var r := float(g.get("ring_px", 10.0))
	var w := float(g.get("ring_w_px", 1.5))
	draw_circle(c, r, Palette.c("ground"))
	match String(e["shape"]):
		"ring":  # next: a solid, heavier ring
			LineGlow.ring(self, c, r, Palette.c("select"), w * 1.6, 0.6)
		"plain":  # queued: a thin plain ring
			draw_arc(c, r, 0.0, TAU, 32, Palette.c("text_dim"), w)
		"hold":  # waiting on funds: a ring with a hold glyph "||" beside it
			draw_arc(c, r, 0.0, TAU, 32, Palette.c("select"), w)
			var hp := float(g.get("hold_px", 4.0))
			for dx in [r + hp, r + hp * 2.0]:
				draw_line(c + Vector2(dx, -r * 0.6), c + Vector2(dx, r * 0.6), Palette.c("select"), w * 1.4)
		"struck":  # skipped on a gate: a ring struck through
			draw_arc(c, r, 0.0, TAU, 32, Palette.c("danger"), w)
			var sp := r * 1.3
			draw_line(c + Vector2(-sp, sp), c + Vector2(sp, -sp), Palette.c("danger"), float(g.get("strike_px", 1.8)))
	_text_at(str(e["number"]), c, int(g.get("number_px", 14)), "text" if String(e["shape"]) != "plain" else "text_dim")


func _text_at(text: String, center: Vector2, size: int, key: String) -> void:
	var font := ThemeDB.fallback_font
	var fs := maxi(size, TownUI.MIN_TEXT)
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var base := Vector2(center.x - sz.x * 0.5, center.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c(key))


## Under the hovered lot: its building's status tag, then the shortage or gate text of a ghost
## queued there (stacked).
func _draw_tip() -> void:
	var y := -1.0
	var parts: Array = statuses.get(hover_lot, [])
	if not parts.is_empty():
		y = _status_tag(parts)
	for e in ghosts:
		if String(e["lot_id"]) == hover_lot and String(e["text"]) != "":
			var font := ThemeDB.fallback_font
			var fs := maxi(int(vcfg.get("label_px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
			var text := "%d. %s" % [int(e["number"]), String(e["text"])]
			var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var pad := float(vcfg.get("ghost", {}).get("tag_pad_px", 4.0))
			var lot: Rect2 = e["lot_rect"]
			var host: Vector2 = (get_parent() as Control).size if get_parent() is Control else Vector2(1e6, 1e6)
			var p := Vector2(clampf(lot.get_center().x - sz.x * 0.5 - pad, 4.0, maxf(host.x - sz.x - pad * 2.0 - 4.0, 4.0)),
				y if y >= 0.0 else lot.end.y + 6.0)
			var plate := Rect2(p, Vector2(sz.x + pad * 2.0, sz.y + pad))
			draw_rect(plate, Palette.c("ground"))
			draw_polyline(_outline(plate), Palette.c("contour"), 1.0)
			draw_string(font, p + Vector2(pad, (plate.size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c("text"))
			return


## The hovered building's status tag under its lot: words upright, rates oblique (view.status
## px, pad_px, gap_px). Returns the y just below it (where a ghost tip would stack).
func _status_tag(parts: Array) -> float:
	var sc: Dictionary = vcfg.get("status", {})
	var fs := maxi(int(sc.get("px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
	var pad := float(sc.get("pad_px", 4.0))
	var up := ThemeDB.fallback_font
	var ob := TownUI.oblique_font()
	var w := 0.0
	for pt in parts:
		w += (ob if pt[1] else up).get_string_size(String(pt[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var h := up.get_height(fs) + pad
	var lot := _lot_rect(hover_lot, 0.0)
	var host: Vector2 = (get_parent() as Control).size if get_parent() is Control else Vector2(1e6, 1e6)
	var p := Vector2(clampf(lot.get_center().x - w * 0.5 - pad, 4.0, maxf(host.x - w - pad * 2.0 - 4.0, 4.0)),
		lot.end.y + float(sc.get("gap_px", 6.0)))
	var plate := Rect2(p, Vector2(w + pad * 2.0, h))
	draw_rect(plate, Palette.c("ground"))
	draw_polyline(_outline(plate), Palette.c("contour"), 1.0)
	var x := p.x + pad
	var by := p.y + (h + up.get_ascent(fs) - up.get_descent(fs)) * 0.5
	for pt in parts:
		var f: Font = ob if pt[1] else up
		draw_string(f, Vector2(x, by), String(pt[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c("text"))
		x += f.get_string_size(String(pt[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return plate.end.y + 4.0


# ----------------------------------------------------------------- flash ----
func _draw_flashes() -> void:
	var f: Dictionary = vcfg.get("flash", {})
	var beat_s := maxf(Pulse.tempo_ms / 1000.0, 0.001)
	for fl in _flashes:
		if fl["t"] < 0.0 or model.lot(String(fl["lot"])).is_empty():
			continue
		var p := 0.5 if Pulse.reduced_motion else clampf(float(fl["t"]) / beat_s, 0.0, 1.0)
		var a := float(f.get("alpha", 1.0)) * (1.0 if Pulse.reduced_motion else 1.0 - p)
		var r := _lot_rect(String(fl["lot"]), float(f.get("grow_px", 0.0)) * p)
		LineGlow.polyline(self, _outline(r), Palette.c("select", a), float(f.get("w_px", 2.0)), 0.6)
		var font := ThemeDB.fallback_font
		var fs := maxi(int(vcfg.get("label_px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
		var text := String(f.get("text", ""))
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var base := Vector2(r.get_center().x - sz.x * 0.5, r.position.y - 6.0)
		draw_rect(Rect2(base - Vector2(3, font.get_ascent(fs)), Vector2(sz.x + 6, sz.y)), Palette.c("ground", a))
		draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c("select", a))
