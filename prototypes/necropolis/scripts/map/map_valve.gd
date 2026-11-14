class_name MapValve
extends Control
## The Covington valve panel (bottom-left): a big triangle whose corners are WORK, WAR and FLOOD.
## The handle's barycentric coordinates are the split. Drag it (or click inside the triangle)
## to set the target; click a corner label to snap to 100% of it. The solid handle is the target
## (view_hud.valve_target), the hollow ring the current, slewing split (view_hud.valve). Beside it,
## a row per stream: share, projected rate (mint x share), what it feeds. Commands go out
## throttled (valve_send_hz) while dragging and once on release. Math and text: valve_logic.gd.

signal toast(msg: String)

var model: MapModel

var _side := 0.0
var _origin := Vector2.ZERO  # the triangle's top-left in this panel
var _grab := Rect2()  # the triangle's bounding box grown by valve_pad_px: where a press starts a drag
var _dragging := false
var _last_sent := -1.0
var _override := {}  # the valve the player set, held until the model echoes it
var _rows := {}  # key -> {name, pct, rate, feed}
var _workers: Label
var _supports: Label
var _sig := ""
var _proj := {}  # the last projection (IdleLogic), reused while the valve hasn't moved
var _proj_key := ""
var _last_proj_s := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var cfg := MapLogic.cfg()
	var c: Dictionary = cfg["controls"]
	_side = float(cfg["valve_tri_px"])
	var pad := float(c["valve_pad_px"])
	var inner := float(c["valve_inner_pad_px"])
	var btn: Array = c["valve_corner_btn_px"]
	var cgap := float(c["valve_corner_gap_px"])
	var tri_h := ValveLogic.height(_side)
	_origin = Vector2(pad, pad)
	_grab = Rect2(_origin - Vector2(pad, pad), Vector2(_side + pad * 2.0, tri_h + pad * 2.0))
	var rows_x := _origin.x + _side + inner
	var rows_w := float(c["valve_rows_w_px"])
	var w := rows_x + rows_w + inner
	var h := _origin.y + tri_h + cgap + float(btn[1]) + inner
	_place(cfg, w, h)
	_corner_buttons(btn, cgap, tri_h)
	_build_rows(c, rows_x, inner)
	refresh(true)


func _place(cfg: Dictionary, w: float, h: float) -> void:
	var m: Array = cfg["controls"]["valve_margin_px"]
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = float(m[0])
	offset_right = float(m[0]) + w
	offset_top = -float(m[1]) - h
	offset_bottom = -float(m[1])


## WAR beside the apex (to its right, in the empty space), WORK and FLOOD under their corners.
func _corner_buttons(btn: Array, cgap: float, tri_h: float) -> void:
	var size := Vector2(float(btn[0]), float(btn[1]))
	var pts := ValveLogic.corners(_side)
	var spots := {
		"war": _origin + (pts["war"] as Vector2) + Vector2(float(MapLogic.cfg()["controls"]["valve_pad_px"]), 0.0),
		"work": _origin + (pts["work"] as Vector2) + Vector2(-size.x * 0.5, cgap),
		"flood": _origin + (pts["flood"] as Vector2) + Vector2(-size.x * 0.5, cgap),
	}
	for k in ValveLogic.KEYS:
		var b := Button.new()
		b.text = ValveLogic.NAMES[k]
		b.position = spots[k]
		b.custom_minimum_size = size
		b.size = size
		MapUi.style_button(b, int(MapLogic.cfg()["font_label"]))
		b.pressed.connect(_snap.bind(k))
		add_child(b)


func _build_rows(c: Dictionary, x: float, inner: float) -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(x, inner)
	col.size = Vector2(float(c["valve_rows_w_px"]), 0.0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", int(c["valve_row_gap_px"]))
	add_child(col)
	var title := _label(col, "text_dim")
	title.text = str(c["valve_title"])
	for k in ValveLogic.KEYS:
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", int(c["valve_box_sep_px"]))
		col.add_child(box)
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_theme_constant_override("separation", int(c["valve_row_hsep_px"]))
		box.add_child(top)
		var parts := {"name": _label(top, "text_dim"), "pct": Label.new(), "rate": Label.new(), "feed": null}
		(parts["name"] as Label).custom_minimum_size.x = float(c["valve_name_w_px"])
		MapType.style_mass(parts["pct"])
		(parts["pct"] as Label).custom_minimum_size.x = float(c["valve_pct_w_px"])
		MapType.style_rate(parts["rate"])
		for key in ["pct", "rate"]:
			(parts[key] as Label).mouse_filter = Control.MOUSE_FILTER_IGNORE
			top.add_child(parts[key])
		parts["feed"] = _label(box, "text_dim")
		_rows[k] = parts
		if k == "work":
			_workers = _label(box, "text")
	_supports = _label(col, "text")
	var legend := _label(col, "text_dim")
	legend.text = str(c["valve_legend"])


func _label(parent: Node, color_key: String) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MapType.style_label(l, color_key)
	parent.add_child(l)
	return l


# --- state ------------------------------------------------------------------------

## The valve to show as the target: what the player is setting, else the view's target.
func shown_target() -> Dictionary:
	if not _override.is_empty():
		return _override
	return ValveLogic.normalise(model.hud.get("valve_target", model.hud.get("valve", {})))


## Re-reads the model (the held override clears once the view echoes it) and refreshes the rows.
func refresh(force := false) -> void:
	var target := ValveLogic.normalise(model.hud.get("valve_target", model.hud.get("valve", {})))
	if not _override.is_empty() and not _dragging and ValveLogic.same(_override, target, float(MapLogic.cfg()["controls"]["valve_sync_eps"])):
		_override = {}
	var shown := shown_target()
	var proj := _projection(shown)
	if _dragging:
		model.set_projection(proj)  # the fort chips and "N of M" follow the handle
	var sig := "%s|%s|%s|%s" % [str(ValveLogic.percents(shown)), str(proj["split"]), str(proj["workers_steady"]), str(proj["war_supports"])]
	var cur_sig := str(model.hud.get("valve", {}))
	if not force and sig + cur_sig == _sig:
		return
	_sig = sig + cur_sig
	var rows := ValveLogic.rows(proj, shown)
	for r in rows:
		var parts: Dictionary = _rows[r["key"]]
		(parts["name"] as Label).text = r["name"]
		(parts["pct"] as Label).text = r["pct_text"]
		(parts["rate"] as Label).text = r["rate_text"]
		(parts["feed"] as Label).text = r["feed_text"]
	_workers.text = ValveLogic.workers_text(proj)
	var sup := ValveLogic.supports_text(proj)
	_supports.text = sup
	_supports.visible = sup != ""
	queue_redraw()


## The projection of the valve shown: one per distinct valve and model rev, and while dragging at
## most valve_send_hz projections a second (the same throttle as the valve sends).
func _projection(shown: Dictionary) -> Dictionary:
	var key := "%s|%d|%s" % [str(ValveLogic.percents(shown)), model.rev, str(_dragging)]
	if key == _proj_key and not _proj.is_empty():
		return _proj
	var now := Time.get_ticks_msec() / 1000.0  # lint-ok: projection throttle, not animation
	if _dragging and not _proj.is_empty() and not ValveLogic.should_send(now, _last_proj_s, float(MapLogic.cfg()["valve_send_hz"]), false):
		return _proj
	_last_proj_s = now
	_proj_key = key
	_proj = IdleLogic.panel_projection(IdleLogic.projection(model.state, model.hud, shown, model.forts), model.supports_now(), _dragging)
	return _proj


# --- input ------------------------------------------------------------------------

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and _grab.has_point(e.position):
			_dragging = true
			_last_sent = -1.0
			_drag_to(e.position, false)
			accept_event()
		elif not e.pressed and _dragging:
			_dragging = false
			_drag_to(e.position, true)
			model.clear_projection()  # released: the committed values from the views take over
			accept_event()
	elif e is InputEventMouseMotion and _dragging:
		_drag_to(e.position, false)
		accept_event()


func _drag_to(pos: Vector2, released: bool) -> void:
	_override = ValveLogic.valve_at(pos - _origin, _side)
	refresh()
	queue_redraw()  # the handle follows the pointer even when no percentage changed
	var now := Time.get_ticks_msec() / 1000.0  # lint-ok: send throttle, not animation
	if ValveLogic.should_send(now, _last_sent, float(MapLogic.cfg()["valve_send_hz"]), released):
		_last_sent = now
		_send()


func _snap(key: String) -> void:
	_override = ValveLogic.snap(key)
	refresh()
	queue_redraw()
	_send()


func _send() -> void:
	var v := _override
	var r := model.state.cmd_set_valve(v["work"], v["war"], v["flood"])
	if not r["ok"]:
		_override = {}
		toast.emit(RelishLogic.reason_text(str(r["reason"])))
		refresh()


# --- drawing ----------------------------------------------------------------------

func _draw() -> void:
	var cfg := MapLogic.cfg()
	var c: Dictionary = cfg["controls"]
	draw_style_box(MapUi.plate_box(float(c["valve_plate_alpha"]), 0), Rect2(Vector2.ZERO, size))
	var pts := ValveLogic.corners(_side)
	var tri := PackedVector2Array([_origin + pts["work"], _origin + pts["war"], _origin + pts["flood"], _origin + pts["work"]])
	for l in NodeLogic.capped_layers(Palette.c("undead"), float(c["valve_edge_w_px"]), float(c["valve_edge_glow"]), float(c["valve_edge_halo_max_px"])):
		draw_polyline(tri, l[1], l[0])
	var cur := _origin + ValveLogic.point_of(model.hud.get("valve", shown_target()), _side)
	LineGlow.ring(self, cur, float(c["valve_ghost_r_px"]), Palette.c("undead"), float(c["valve_ghost_w_px"]), float(c["valve_edge_glow"]))
	var hp := _origin + ValveLogic.point_of(shown_target(), _side)
	LineGlow.ring(self, hp, float(c["valve_handle_r_px"]), Palette.c("undead"), float(c["valve_ghost_w_px"]), float(c["valve_edge_glow"]))
	draw_circle(hp, float(c["valve_handle_r_px"]), Palette.c("undead_core"))
