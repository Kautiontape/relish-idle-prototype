class_name MapCallouts
extends Node2D
## Lane "why" callouts (VISUAL-LANGUAGE 2d): at mid and near zoom, a small dim plate near the
## midpoint of each lane that carries a `why`, joined to the lane by a 1 px leader. Drawn in
## screen pixels: the node is scaled by 1/zoom, so text is the same size at every zoom. The
## layout (text, plate rects, greedy placement) is rebuilt only when the model's rev, the zoom
## tier, the zoom, a drag starting or ending, or a held fort's chip rect changes, never per frame; while the card is open, also when it moves or the
## camera pans (the card is fixed on screen, so a pan moves it over the world). Lanes that share a
## kind, a cause and a source fold into one callout at that source ("WAR ×9 · valve · +2.6/s
## total", HudLogic.callout_items). While the valve is dragged only callouts.drag_max_count show, the
## loudest. A callout never
## takes a place under the open card or over a held fort's chip. Text and placement:
## scripts/map/hud_logic.gd.

var model: MapModel
var cam: MapCamera
var nodes: MapNodes  # the drawn chips' places (a chip can step clear of Relish's token)
var card: Control  # the sidebar: its rect is occupied while it is visible

var _rev := -2
var _tier := ""
var _zoom := -1.0
var _card_key: Array = []
var _chip_sig: Array = []  # what the chip rects depend on: recomputed only when it changes
var _chip_rects_cache: Array = []
var _chip_key: Array = []  # the held forts' chip rects as drawn (HudLogic.rects_key): a moved chip re-places
var _capped := false  # a valve drag is on: only callouts.drag_max_count show
var _shown: Array = []  # [{plate, leader_from, leader_to, head, rate, tail, base}] in screen px


func _process(_delta: float) -> void:
	if model == null or cam == null:
		return
	var z := cam.zoom.x
	var eps: float = MapLogic.cfg()["callouts"]["zoom_eps"]
	var ck := _card_rect_key()
	var sig := _chip_signature(z)
	if sig != _chip_sig:  # the chip rects cost a measure and a placement per held fort: not per frame
		_chip_sig = sig
		_chip_rects_cache = _chip_rects(z, cam.tier)
	var chips := HudLogic.rects_key(_chip_rects_cache)
	var capped := not model.projection.is_empty()  # set only while the valve is being dragged
	if model.rev == _rev and cam.tier == _tier and absf(z - _zoom) <= eps and ck == _card_key and chips == _chip_key and capped == _capped:
		return
	_card_key = ck
	_chip_key = chips
	_capped = capped
	_rev = model.rev
	_tier = cam.tier
	_zoom = z
	scale = Vector2.ONE / z
	_layout(z)
	queue_redraw()


## What the card's occupancy depends on: [] while it is closed, else its screen rect and the
## camera's position.
func _card_rect_key() -> Array:
	if card == null or not card.is_visible_in_tree():
		return []
	return [card.get_global_rect(), cam.position]


## What a callout must not cover, in this layer's frame (world x zoom): the open card, and every
## held fort's chip while chips show (its clock must stay readable).
func _occupied(z: float) -> Array:
	var out: Array = []
	if not _card_key.is_empty():
		out.append(HudLogic.screen_to_zoomed(_card_key[0], cam.position, z, get_viewport_rect().size))
	out.append_array(_chip_rects_cache)
	return out


## What the chips' drawn rects follow: the model rev (held set, clocks, projection), the zoom and
## tier, the drag, the dragged margins (margin_sig: a drag moves them without a rev change), and
## where Relish's token is drawn (a chip steps clear of it), on a coarse grid (callouts.token_key_px)
## so her travelling does not refresh it every frame.
func _chip_signature(z: float) -> Array:
	var rp: Vector2 = nodes.relish_drawn_pos() if nodes != null else Vector2.ZERO
	var grid: float = MapLogic.cfg()["callouts"]["token_key_px"]
	return [model.rev, roundi(z * 1000.0), cam.tier, not model.projection.is_empty(), model.margin_sig, roundi(rp.x / grid), roundi(rp.y / grid)]


## The held forts' chips as drawn (shift included), in this layer's frame; none while chips are hidden.
func _chip_rects(z: float, tier: String) -> Array:
	var out: Array = []
	if nodes != null and IdleLogic.chip_shown(tier, z):
		for f in model.forts:
			if bool(f.get("held", false)):
				var r := nodes.chip_world_rect(f)
				out.append(Rect2(r.position * z, r.size * z))
	return out


func _names() -> Dictionary:
	var names := {MapModel.COVINGTON: "Covington", MapModel.VEI: "Vei"}
	for f in model.forts:
		names[str(f["id"])] = str(f["name"])
	return names


## The lane's curve point at t = 0.5, in world px (the quadratic's (a + 2c + b) / 4).
func _mid(row: Dictionary) -> Vector2:
	var from_id := str(row["from"])
	var to_id := str(row["to"])
	var c := MapLogic.lane_curve_for(row, model.node_pos(from_id), model.node_pos(to_id), 0.0)
	return ((c["a"] as Vector2) + 2.0 * (c["c"] as Vector2) + (c["b"] as Vector2)) * 0.25


func _layout(z: float) -> void:
	_shown.clear()
	if _tier == "far":
		return
	var cfg: Dictionary = MapLogic.cfg()["callouts"]
	var size_px := int(cfg["size_px"])
	var pad := float(cfg["pad_px"])
	var off: Array = cfg["offset_px"]
	var names := _names()
	var rows: Array = []
	for r in HudLogic.callout_items(model.lanes, int(cfg["collapse_min"])):
		if model.has_node(str(r["from"])) and (bool(r.get("group", false)) or model.has_node(str(r["to"]))):
			rows.append(r)
	var items: Array = []
	var options: Array = []
	var lf := MapType.label_font()
	var rf := MapType.rate_font()
	for r in rows:
		var p := HudLogic.callout_parts(r, names)
		var hw := lf.get_string_size(p["head"], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var rw := rf.get_string_size(p["rate"], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var tw := lf.get_string_size(p["tail"], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var text_h := maxf(lf.get_height(size_px), rf.get_height(size_px))
		var size := Vector2(hw + rw + tw + pad * 2.0, text_h + pad * 2.0)
		var anchor := (model.node_pos(str(r["from"])) if bool(r.get("group", false)) else _mid(r)) * z
		items.append({"parts": p, "anchor": anchor, "hw": hw, "rw": rw, "text_h": text_h})
		options.append(HudLogic.candidate_rects(anchor, size, Vector2(float(off[0]), float(off[1]))))
	var picks := HudLogic.place(options, HudLogic.callout_cap(_capped), float(cfg["gap_px"]), _occupied(z))
	for i in items.size():
		if picks[i] < 0:
			continue
		var plate: Rect2 = options[i][picks[i]]
		var it: Dictionary = items[i]
		_shown.append({"plate": plate, "from": it["anchor"], "to": HudLogic.leader_end(plate, it["anchor"]),
			"head": it["parts"]["head"], "rate": it["parts"]["rate"], "tail": it["parts"]["tail"],
			"hw": it["hw"], "rw": it["rw"], "text_h": it["text_h"]})


func _draw() -> void:
	if _shown.is_empty():
		return
	var cfg: Dictionary = MapLogic.cfg()["callouts"]
	var size_px := int(cfg["size_px"])
	var pad := float(cfg["pad_px"])
	var bg := Palette.c("ground").lightened(float(MapLogic.cfg()["panel_bg_lighten"]))
	bg.a = float(cfg["plate_alpha"])
	var lf := MapType.label_font()
	var rf := MapType.rate_font()
	for s in _shown:
		var plate: Rect2 = s["plate"]
		draw_line(s["from"], s["to"], Palette.c("text_dim"), float(cfg["leader_width_px"]))
		draw_rect(plate, bg)
		draw_rect(plate, Palette.c("contour", float(MapLogic.cfg()["panel_border_alpha"])), false, 1.0)
		var base := plate.position + Vector2(pad, pad + maxf(lf.get_ascent(size_px), rf.get_ascent(size_px)))
		draw_string(lf, base, s["head"], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Palette.c("text_dim"))
		draw_string(rf, base + Vector2(float(s["hw"]), 0.0), s["rate"], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Palette.c("text"))
		draw_string(lf, base + Vector2(float(s["hw"]) + float(s["rw"]), 0.0), s["tail"], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Palette.c("text_dim"))
