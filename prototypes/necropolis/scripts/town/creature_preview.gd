extends Control
## The crypt slab's live morph preview (MECHANICS §4.6; VISUAL-LANGUAGE §2b, §2e). Every mark is a
## line through LineGlow (the only fills are the eye's tiny core): the husk's silhouette
## (town.json slab.silhouettes, unit box) in `undead`, a faint ghost when empty, fleshing in (alpha,
## width, glow) as its slots fill. One stat, one watchable verb:
##   beef      size: the silhouette's box grows (capped at preview.max_scale)
##   power     jagged spikes on the rim, count = round(power)
##   wits      a cold inner clarity: crisper halos, a pale core, and an eye mark
##   presence  a dashed pressure ring pushing outward each beat; its radius grows with presence
##   speed     trailing wisps (speed lines) behind it, count = round(speed)
## The slab's rings (the town's tempo source, hops 0) breathe on the beat around it, and one rides out
## each beat; while Relish holds the raise they brighten and the ride turns inward. The hold closes a
## violet ring and fleshes the creature to full. play_raise() is the set piece: the rings collapse
## into the creature's outline, landing on a beat, then a brief bright outline. Reduced motion: no
## breathing, ride, sway or push; the collapse is one static flash. The runes (one per slot, from
## CryptLogic.rune_points) ring it, each captioned with its group (and its remnant's aspect when
## filled, the magnitude inside); clicking a rune emits rune_clicked.

signal rune_clicked(index: int)
signal raise_finished

var pv: Dictionary = {}     # town.json view.crypt.preview
var slab: Dictionary = {}   # town.json slab
var texts: Dictionary = {}  # town.json view.crypt
var awake := true           # Relish is home
var kind := ""              # the husk kind on the slab ("" = none)
var ev: Dictionary = {}     # SlabLogic.evaluate of the board
var runes: Array = []       # per slot {group, aspect, mag}; aspect "" = empty
var hold := 0.0             # hold-to-raise progress, 0..1
var formed := false         # held to the end: whole, waiting for its name

var _raise_t := -1.0        # seconds into the set piece; -1 = none
var _collapse := 0.0
var _flash := 0.0
var _snap: Dictionary = {}  # {kind, ev}: the creature the set piece draws
var _hover := -1
var _pts: Array = []        # rune centres as last drawn


func setup(view_crypt: Dictionary, slab_cfg: Dictionary) -> void:
	texts = view_crypt
	pv = view_crypt.get("preview", {})
	slab = slab_cfg
	custom_minimum_size = Vector2(0, float(pv.get("h_px", 0.0)))
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_exited.connect(func(): _hover = -1)


func show_build(k: String, e: Dictionary, r: Array) -> void:
	kind = k
	ev = e
	runes = r


func raising() -> bool:
	return _raise_t >= 0.0


## The set piece for the creature now on the slab: collapse (to the next beat at least
## collapse_min_beats away) then the bright outline for flash_s. raise_finished when done.
func play_raise() -> void:
	_snap = {"kind": kind, "ev": ev.duplicate(true)}
	_collapse = 0.0 if Pulse.reduced_motion else CryptLogic.collapse_s(Pulse.phase(0.0), Pulse.tempo_ms / 1000.0,
		float(pv.get("collapse_min_beats", 0.0)))
	_flash = float(pv.get("flash_s", 0.0))
	_raise_t = 0.0


func _process(delta: float) -> void:
	if _raise_t >= 0.0:
		_raise_t += delta
		if _raise_t >= _collapse + _flash:
			_raise_t = -1.0
			_snap = {}
			raise_finished.emit()
	if is_visible_in_tree():
		queue_redraw()


func _f(key: String, i := -1) -> float:
	var v: Variant = pv.get(key, 0.0)
	if v is Array:
		return float((v as Array)[i]) if i >= 0 and i < (v as Array).size() else 0.0
	return float(v)


func _body_px(e: Dictionary) -> float:
	var beef := float(e.get("stats", {}).get("beef", 0.0))
	return _f("body_px") * minf(1.0 + _f("per_beef") * beef, _f("max_scale"))


func _draw() -> void:
	var c := size * 0.5
	var k := String(_snap.get("kind", kind)) if raising() else kind
	var e: Dictionary = _snap.get("ev", ev) if raising() else ev
	var body := _body_px(e) if k != "" else _f("body_px")
	_draw_rings(c, body * 0.5)
	_pts = []
	if not awake:
		return
	if k != "":
		_draw_creature(c, k, e, body)
	if not raising() and (hold > 0.0 or formed):
		LineGlow.arc(self, c, _f("hold_ring_px"), -PI * 0.5, -PI * 0.5 + TAU * (1.0 if formed else hold),
			Palette.c("relish"), _f("hold_w_px"), _f("hold_glow"))
	_draw_runes(c)
	if k == "":
		_text_centered(c, String(texts.get("empty_slab", "")), int(_f("label_px")), "text_dim")


## The slab's rings: breathing on the beat, a ring riding out (or in, while held); collapsing into
## the creature's outline during the set piece.
func _draw_rings(c: Vector2, body_r: float) -> void:
	var rings: Array = pv.get("rings_px", [])
	var w := _f("ring_w_px")
	if raising():
		var k := 1.0 if _collapse <= 0.0 else clampf(_raise_t / _collapse, 0.0, 1.0)
		if k >= 1.0:
			return  # gone into the creature until the set piece ends
		var fall := k * k  # they gather speed as they fall in
		for r0 in rings:
			LineGlow.ring(self, c, lerpf(float(r0), body_r, fall), Palette.c("undead", lerpf(_f("ring_alpha"), 1.0, k)),
				w * lerpf(1.0, _f("flash_w_mul"), k), 1.0)
		return
	var alpha := _f("ring_asleep_alpha")
	if awake:
		alpha = lerpf(_f("ring_alpha"), _f("ring_hold_alpha"), 1.0 if formed else hold)
	var wave := Pulse.wave(0.0)
	for r in rings:
		LineGlow.ring(self, c, float(r), Palette.c("undead", alpha), w, wave)
	if not awake or Pulse.reduced_motion or rings.is_empty():
		return
	var b := Pulse.phase(0.0)
	var outer := float(rings[rings.size() - 1])
	var ride := lerpf(outer, body_r, b) if (hold > 0.0 or formed) else outer + b * _f("ring_reach_px")
	LineGlow.ring(self, c, ride, Palette.c("undead", alpha * wave), w, wave)


func _draw_creature(c: Vector2, k: String, e: Dictionary, body: float) -> void:
	var st: Dictionary = e.get("stats", {})
	var fill := float(e.get("filled", 0)) / float(maxi(int(e.get("slot_count", 0)), 1))
	var ghost := _f("ghost")
	var reveal := maxf(ghost + (1.0 - ghost) * fill, hold)
	if formed or raising():
		reveal = 1.0
	var rect := Rect2(c - Vector2(body, body) * 0.5, Vector2(body, body))
	var body_r := body * 0.5
	var col := Palette.c("undead", reveal)
	var width := lerpf(_f("w_px", 0), _f("w_px", 1), reveal)
	var glow := lerpf(_f("glow", 0), _f("glow", 1), reveal)
	var wits := float(st.get("wits", 0.0))
	var core := LineGlow.NO_CORE
	if wits > 0.0:
		glow *= maxf(1.0 - _f("wits_sharp") * wits, _f("wits_sharp_min"))
		core = Palette.c("undead_core")
	var reduced := Pulse.reduced_motion
	var b := Pulse.phase(0.0)

	var presence := float(st.get("presence", 0.0))
	if presence > 0.0:
		var rp := body_r + _f("presence_base_px") + presence * _f("presence_per_px")
		var push := 0.0 if reduced else b * _f("presence_push_px")
		_dashed_ring(c, rp + push, Palette.c("undead", reveal * (1.0 - _f("presence_fade") * (0.0 if reduced else b))),
			_f("presence_w_px"), _f("presence_glow"), int(_f("presence_dashes")))

	var wisps := mini(int(roundf(float(st.get("speed", 0.0)))), int(_f("wisp_max")))
	if wisps > 0:
		var segs := PackedVector2Array()
		var span := body * _f("wisp_span")
		for i in wisps:
			var y := c.y - span * 0.5 + span * (float(i) + 0.5) / float(wisps)
			var sway := 0.0 if reduced else _f("wisp_sway_px") * sin(TAU * (b + float(i) / float(wisps)))
			var x := rect.position.x - _f("wisp_gap_px") + sway
			segs.append(Vector2(x, y))
			segs.append(Vector2(x - _f("wisp_len_px", i % 2), y))
		_multiline(segs, Palette.c("undead", reveal * _f("wisp_alpha")), _f("wisp_w_px"), _f("wisp_glow"))

	var sil: Dictionary = slab.get("silhouettes", {}).get(k, {})
	var strokes: Array = []
	for pl in sil.get("strokes", []):
		var pts := PackedVector2Array()
		for p in pl:
			pts.append(rect.position + Vector2(float(p[0]), float(p[1])) * body)
		strokes.append(pts)
		LineGlow.polyline(self, pts, col, width, glow, core)

	var spikes := mini(int(roundf(float(st.get("power", 0.0)))), int(_f("spike_max")))
	if spikes > 0:
		var rr := body_r + _f("rim_gap_px")
		var half := deg_to_rad(_f("spike_deg"))
		var segs := PackedVector2Array()
		for i in spikes:
			var a := -PI * 0.5 + TAU * float(i) / float(spikes)
			var tip := c + Vector2.from_angle(a) * (rr + _f("spike_len_px", i % 2))
			segs.append(c + Vector2.from_angle(a - half) * rr)
			segs.append(tip)
			segs.append(tip)
			segs.append(c + Vector2.from_angle(a + half) * rr)
		_multiline(segs, col, _f("spike_w_px"), _f("spike_glow"))

	var eye: Array = sil.get("eye", [])
	if wits > 0.0 and eye.size() == 2:
		var p := rect.position + Vector2(float(eye[0]), float(eye[1])) * body
		var r := _f("eye_px")
		var almond := PackedVector2Array()
		for i in 9:
			var t := float(i) / 8.0
			almond.append(p + Vector2(lerpf(-r, r, t), -sin(PI * t) * r * 0.5))
		for i in range(1, 9):
			var t := float(i) / 8.0
			almond.append(p + Vector2(lerpf(r, -r, t), sin(PI * t) * r * 0.5))
		LineGlow.polyline(self, almond, Palette.c("undead_core", reveal), _f("eye_w_px"), _f("eye_glow"))
		draw_circle(p, _f("eye_core_px"), Palette.c("undead_core", reveal))

	# the set piece's bright outline, once the rings have collapsed into it
	if raising() and _raise_t >= _collapse:
		var f := 1.0 if reduced or _flash <= 0.0 else 1.0 - clampf((_raise_t - _collapse) / _flash, 0.0, 1.0)
		for pts in strokes:
			LineGlow.polyline(self, pts, Palette.c("undead", f), width * _f("flash_w_mul"), 1.0, Palette.c("undead_core", f))


## A ring of `n` dashes (half on, half off), drawn as one glowing multiline.
func _dashed_ring(c: Vector2, r: float, col: Color, w: float, glow: float, n: int) -> void:
	if n <= 0 or r <= 0.0:
		return
	var segs := PackedVector2Array()
	var step := TAU / float(n)
	for i in n:
		var a0 := step * float(i)
		for j in 3:
			segs.append(c + Vector2.from_angle(a0 + step * 0.5 * float(j) / 3.0) * r)
			segs.append(c + Vector2.from_angle(a0 + step * 0.5 * float(j + 1) / 3.0) * r)
	_multiline(segs, col, w, glow)


func _multiline(segs: PackedVector2Array, col: Color, w: float, glow: float) -> void:
	if segs.is_empty():
		return
	for l in LineGlow.layers(col, w, glow):
		draw_multiline(segs, l[1], l[0])


## One rune per slot: a glowing ring with the remnant's magnitude when filled, a dashed dim ring
## when empty; captioned outward with the slot's group and, when filled, the remnant's aspect.
func _draw_runes(c: Vector2) -> void:
	var groups := SlabLogic.slots_for(kind, slab)
	if groups.is_empty():
		return
	_pts = CryptLogic.rune_points(groups, c, _f("rune_rx_px"), _f("rune_ry_px"), pv.get("rune_group_deg", {}), _f("rune_step_deg"))
	var r := _f("rune_r_px")
	var font := ThemeDB.fallback_font
	var cap_px := maxi(int(_f("caption_px")), TownUI.MIN_TEXT)
	var num_px := maxi(int(_f("number_px")), TownUI.MIN_TEXT)
	for i in _pts.size():
		var p: Vector2 = _pts[i]
		var info: Dictionary = runes[i] if i < runes.size() else {}
		var aspect := String(info.get("aspect", ""))
		if aspect != "":
			LineGlow.ring(self, p, r, Palette.c("undead"), _f("rune_w_px"), _f("rune_glow"))
			_text_centered(p, str(int(info.get("mag", 0))), num_px, "text")
			if i == _hover:
				LineGlow.ring(self, p, r + _f("hover_pad_px"), Palette.c("select"), _f("hover_w_px"), 0.0)
		else:
			_dashed_ring(p, r, Palette.c("text_dim"), _f("rune_w_px"), 0.0, int(_f("rune_dashes")))
		var lines: Array = [[String(groups[i]), "text_dim"]]
		if aspect != "":
			lines.append([aspect, "text"])
		var right := p.x >= c.x
		var lh := font.get_height(cap_px)
		var y := p.y - lh * float(lines.size()) * 0.5
		for ln in lines:
			var w := font.get_string_size(String(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, cap_px).x
			var x := p.x + r + _f("caption_gap_px") if right else p.x - r - _f("caption_gap_px") - w
			draw_string(font, Vector2(x, y + font.get_ascent(cap_px)), String(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, cap_px,
				Palette.c(String(ln[1])))
			y += lh


func _text_centered(p: Vector2, text: String, px: int, key: String) -> void:
	if text == "":
		return
	var font := ThemeDB.fallback_font
	var fs := maxi(px, TownUI.MIN_TEXT)
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, Vector2(p.x - sz.x * 0.5, p.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c(key))


func _rune_at(p: Vector2) -> int:
	for i in _pts.size():
		if p.distance_to(_pts[i]) <= _f("rune_hit_px"):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	var m := event as InputEventMouseMotion
	if m != null:
		_hover = _rune_at(m.position)
		var filled := _hover >= 0 and _hover < runes.size() and String(runes[_hover].get("aspect", "")) != ""
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if filled else Control.CURSOR_ARROW
	var b := event as InputEventMouseButton
	if b != null and b.pressed and b.button_index == MOUSE_BUTTON_LEFT:
		var i := _rune_at(b.position)
		if i >= 0:
			rune_clicked.emit(i)
			accept_event()
