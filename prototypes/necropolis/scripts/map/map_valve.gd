class_name MapValve
extends Control
## The Covington valve panel (bottom-left): a big triangle whose corners are WORK, WAR and FLOOD.
## The handle's barycentric coordinates are the split. Drag it (or click inside the triangle)
## to set the target; click a corner label to snap to 100% of it. The solid handle is the target
## (view_hud.valve_target), the hollow ring the current, slewing split (view_hud.valve), set
## now_offset_px off the dot when the two coincide so a zero slew still shows. Beside it, a row per
## stream: share, projected rate (mint x share), what it feeds; under WORK the workforce the town
## settles at (capped: min(slots + idle_cap, steady)); on WAR's feed line the WAR that overflows to
## Vei once every target is capped. Under it all, while dragging and for payoff_hold_s after the
## release, the payoff line: Vei's differential now → at the dragged valve, and the drain or the
## odds after drain_window_s. Commands go out throttled (valve_send_hz) while dragging and once on
## release. Math and text: valve_logic.gd.

signal toast(msg: String)
## The player committed a new target (a drag's release or a corner snap, accepted): the valve
## swing set piece re-proportions Covington's stems to it.
signal committed(valve: Dictionary)

var model: MapModel

var _side := 0.0
var _origin := Vector2.ZERO  # the triangle's top-left in this panel
var _grab := Rect2()  # the triangle's bounding box grown by valve_pad_px: where a press starts a drag
var _dragging := false
var _last_sent := -1.0
var _override := {}  # the valve the player set, held until the model echoes it
var _rows := {}  # key -> {box, name, pct, rate, feed}
var _corner_btns := {}  # key -> the corner's Button
var _workers: Label
var _supports: Label
var _bone: Label  # the bone line: the pits-first stall's lever, or "below the bone edge" while dragging under it
var _over_rate: Label  # on WAR's feed line: "+3.1/s"
var _over_text: Label  # "overflows to Vei"
var _payoff: VBoxContainer  # the payoff, the panel's last block: two rows reserved (the cost may wrap)
var _explain: Label  # "WORK staffs your town · WAR garrisons your forts · FLOOD clogs Vei's queue", in the payoff's place
var _payoff_w := 0.0  # the payoff's inner width: the panel's, less its padding
var _payoff_key := ""  # the parts' kinds and texts and the row width the Labels were last built for
var _payoff_parts: Array = []  # the parts shown, [{kind, text}]: the differential and odds, then the costs
var _since_release := -1.0  # seconds since the last drag's release (-1: none yet); the payoff's hold
var _sig := ""
var _proj := {}  # the last projection (IdleLogic), reused while the valve hasn't moved
var _proj_key := ""
var _last_proj_s := -1.0
var _pointer := 0.0  # the opening's pulse on the triangle's edge, 0..1 (set_pointer)


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
	var rows_x := _origin.x + _side + float(btn[0]) * 0.5 + inner  # clear of the FLOOD button under the corner
	var rows_w := float(c["valve_rows_w_px"])
	var w := rows_x + rows_w + inner
	_corner_buttons(btn, cgap, tri_h)
	var col := _build_rows(c, rows_x, inner)
	# the payoff line spans the panel under the triangle's buttons and the rows, its height reserved
	# so the panel never jumps when it shows
	var top := maxf(_origin.y + tri_h + cgap + float(btn[1]), inner + col.get_combined_minimum_size().y) + inner
	_payoff = VBoxContainer.new()
	_payoff.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_payoff.add_theme_constant_override("separation", int(c["valve_payoff_row_gap_px"]))
	add_child(_payoff)
	_payoff.position = Vector2(inner, top)
	_payoff_w = w - inner * 2.0
	# the one-line explanation of the three streams takes the payoff's reserved rows while no fort has been
	# taken and no drag is paying off; always the panel's hover tooltip
	_explain = Label.new()
	_explain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_explain.text = str(cfg["clarity"]["valve_line"])
	MapType.style_label(_explain, "text")
	_explain.position = Vector2(inner, top)
	_explain.custom_minimum_size.x = _payoff_w
	_explain.size = Vector2(_payoff_w, 0.0)
	add_child(_explain)
	tooltip_text = HudLogic.tip("mint")
	var line_h := MapType.rate_font().get_height(MapType.size_of("size_rate"))
	_place(cfg, w, top + line_h * 2.0 + float(c["valve_payoff_row_gap_px"]) + inner)
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
		b.tooltip_text = HudLogic.tip(k)
		add_child(b)
		_corner_btns[k] = b


func _build_rows(c: Dictionary, x: float, inner: float) -> VBoxContainer:
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
		var parts := {"box": box, "name": _label(top, "text_dim"), "pct": Label.new(), "rate": Label.new(), "feed": null}
		(parts["name"] as Label).custom_minimum_size.x = float(c["valve_name_w_px"])
		HudLogic.apply_tip(parts["name"], k)  # the stream's word, in the glossary's meaning (and the hover passes through)
		MapType.style_mass(parts["pct"])
		(parts["pct"] as Label).custom_minimum_size.x = float(c["valve_pct_w_px"])
		MapType.style_rate(parts["rate"])
		for key in ["pct", "rate"]:
			(parts[key] as Label).mouse_filter = Control.MOUSE_FILTER_IGNORE
			top.add_child(parts[key])
		var feed_row := _hbox(box, int(c["valve_row_hsep_px"]))
		parts["feed"] = _label(feed_row, "text_dim")
		_rows[k] = parts
		if k == "work":
			_workers = _label(box, "text")
		elif k == "war":
			_over_rate = Label.new()
			_over_rate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			MapType.style_rate(_over_rate, "text", MapType.size_of("size_label"))
			feed_row.add_child(_over_rate)
			_over_text = _label(feed_row, "text_dim")
	_supports = _label(col, "text")
	# the bone line (the stall's lever, or "below the bone edge" while dragging): two lines of room are
	# always kept, so the panel never jumps when it shows
	_bone = _label(col, str(MapLogic.cfg()["bone_line"]["key"]))
	_bone.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bone.custom_minimum_size = Vector2(float(c["valve_rows_w_px"]), MapType.label_font().get_height(MapType.size_of("size_label")) * 2.0)
	var legend := _label(col, "text_dim")
	legend.text = str(c["valve_legend"])
	return col


func _hbox(parent: Node, sep: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", sep)
	if parent != null:
		parent.add_child(h)
	return h


func _label(parent: Node, color_key: String) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MapType.style_label(l, color_key)
	parent.add_child(l)
	return l


# --- state ------------------------------------------------------------------------

## The valve to show as the target: what the player is setting, else the view's target. Once won, FLOOD's
## share is WAR's (ValveLogic.won_valve): the rows add to 100 without a FLOOD row.
func shown_target() -> Dictionary:
	if not _override.is_empty():
		return ValveLogic.won_valve(_override, model.hud)
	return ValveLogic.won_valve(ValveLogic.normalise(model.hud.get("valve_target", model.hud.get("valve", {}))), model.hud)


## Re-reads the model (the held override clears once the view echoes it) and refreshes the rows.
func refresh(force := false) -> void:
	var target := ValveLogic.won_valve(ValveLogic.normalise(model.hud.get("valve_target", model.hud.get("valve", {}))), model.hud)  # folded as the override is
	if not _override.is_empty() and not _dragging and ValveLogic.same(_override, target, float(MapLogic.cfg()["controls"]["valve_sync_eps"])):
		_override = {}
	var shown := shown_target()
	var proj := _projection(shown)
	if _dragging:
		model.set_projection(proj)  # the fort chips and "N of M" follow the handle
	var pay_parts := _payoff_parts_for(proj)
	var payoff := " | ".join(PackedStringArray(pay_parts.map(func(q): return q["text"])))
	var over := ValveLogic.overflow_parts(ValveLogic.war_overflow(model.hud, proj, _dragging), model.hud)  # its won words once won
	var bone := _bone_text(shown)
	var explain_on := HudLogic.valve_explain_shown(model.hud) and pay_parts.is_empty()
	var flood_on := HudLogic.flood_shown(model.hud)
	var sig := "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [str(ValveLogic.percents(shown)), str(proj["split"]), str(proj["workers_steady"]), str(proj["war_supports"]), str(payoff), str(over), bone, str(explain_on), str(flood_on)]
	var cur_sig := str(model.hud.get("valve", {})) + (str(model.rev) if payoff != "" else "")
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
	_workers.text = ValveLogic.workers_text(ValveLogic.workers_kept(float(proj["workers_steady"]), model.hud, model.job_slots, model.idle_cap, _dragging))
	_over_rate.text = str(over.get("rate", ""))
	_over_text.text = str(over.get("text", ""))
	var sup := ValveLogic.supports_text(proj)
	_supports.text = sup
	_supports.visible = sup != ""
	_bone.text = bone
	_explain.visible = explain_on
	(_rows["flood"]["box"] as Control).visible = flood_on  # won: the FLOOD row and its corner go
	(_corner_btns["flood"] as Control).visible = flood_on
	tooltip_text = HudLogic.tip("mint", model.hud)  # won (flood_on is in the sig): the mint's won line, no FLOOD
	for k in ValveLogic.KEYS:  # and WAR's and FLOOD's won line (no FLOOD sentence), on the names and the corners
		HudLogic.apply_tip(_rows[k]["name"], k, model.hud)
		(_corner_btns[k] as Control).tooltip_text = HudLogic.tip(k, model.hud)
	_payoff_rows(pay_parts)
	queue_redraw()


## The bone line for the valve `shown`: the live stall's lever, else "below the bone edge" in a drag under it.
func _bone_text(shown: Dictionary) -> String:
	var stalled := HudLogic.pits_stalled(model.mill, model.queue_stall)
	var lever := HudLogic.lever_text(HudLogic.stall_lever(model.mill, model.queue_stall))
	return ValveLogic.bone_readout(stalled, lever, _dragging, float(shown["war"]), ValveLogic.bone_edge(model.hud))


## The payoff's parts while it shows (ValveLogic.payoff_shown), else []: Vei's differential now and
## at the valve shown (the "now" side at the current valve through the same projection) with the
## drain or odds, then what the drag costs (ValveLogic.payoff_costs against the same base split).
func _payoff_parts_for(proj: Dictionary) -> Array:
	if not ValveLogic.payoff_shown(_dragging, _since_release) or not HudLogic.vei_readout_shown(model.hud):
		return []  # won: no Vei odds or queue line after a drag, as nowhere else on the map
	var base := IdleLogic.split_at(model.state, model.hud.get("valve", {}))
	var p := ValveLogic.payoff(model.vei, proj, float(model.realm_cfg.get("K", 0.0)), model.realm_cfg.get("odds", {}),
		float(model.hud.get("t", 0.0)))  # (E4 step 9: the win odds view_vei shows)
	var eps := float(model.realm_cfg.get("readout", {}).get("sign_eps", 0.0))
	var parts: Array = [{"kind": "main", "text": ValveLogic.payoff_line(p, eps, model.realm_cfg.get("odds", {}))}]
	parts.append_array(ValveLogic.payoff_cost_parts(proj, base, eps))
	return parts


## Lays the parts out in the payoff's two rows: one row when it fits the panel's inner width, else
## the costs wrap whole under the first part, and the ones that still do not fit are dropped
## (ValveLogic.payoff_rows).
func _payoff_rows(parts: Array) -> void:
	var key := "%s|%s" % [_payoff_w, "|".join(PackedStringArray(parts.map(func(q): return "%s:%s" % [q["kind"], q["text"]])))]
	if key == _payoff_key:  # the same text on the same rows: keep the Labels
		_payoff_parts = parts
		return
	_payoff_key = key
	_payoff_parts = parts
	for ch in _payoff.get_children():
		_payoff.remove_child(ch)
		ch.queue_free()
	if parts.is_empty():
		return
	var sep_text := str(MapLogic.cfg()["controls"]["payoff_sep"])
	var boxes: Array = []
	var widths: Array = []
	var kinds: Array = []
	for part in parts:
		var box := _hbox(null, int(MapLogic.cfg()["controls"]["valve_payoff_sep_px"]))
		_spans_into(box, str(part["text"]))
		boxes.append(box)
		kinds.append(str(part["kind"]))
		widths.append(_row_w(box))
	var sep_probe := _sep_label(sep_text)
	var sep_w := sep_probe.get_minimum_size().x
	sep_probe.free()
	var plan := ValveLogic.payoff_rows(widths, kinds, sep_w, _payoff_w)
	var rows: Array = [_hbox(_payoff, 0), _hbox(_payoff, 0)]
	var used := [0, 0]
	for i in parts.size():
		var r: int = plan[i]
		if r < 0:
			boxes[i].free()
			continue
		if used[r] > 0:
			rows[r].add_child(_sep_label(sep_text))
		rows[r].add_child(boxes[i])
		used[r] += 1


## A row of labels' width: their minimum widths plus the gaps between them (a container off the tree
## can hand back a stale combined size).
func _row_w(box: HBoxContainer) -> float:
	var w := 0.0
	for ch in box.get_children():
		w += (ch as Control).get_minimum_size().x
	return w + float(maxi(box.get_child_count() - 1, 0) * box.get_theme_constant("separation"))


func _sep_label(text: String) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	MapType.style_label(l, "text_dim")
	return l


## The payoff line as runs: its rates in the rate face (AwayLogic.spans), the rest as labels.
func _spans_into(row: HBoxContainer, text: String) -> void:
	for ch in row.get_children():
		row.remove_child(ch)
		ch.queue_free()
	for sp in ValveLogic.payoff_spans(text):
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.text = str(sp["text"])
		if str(sp["kind"]) == "rate":
			MapType.style_rate(l)
		else:
			MapType.style_label(l, "text")
		row.add_child(l)


## The payoff's hold after a release runs on the frame clock; it hides once payoff_hold_s is up.
func _process(delta: float) -> void:
	if _since_release < 0.0 or _dragging:
		return
	var was := ValveLogic.payoff_shown(false, _since_release)
	_since_release += delta
	if was and not ValveLogic.payoff_shown(false, _since_release):
		refresh(true)


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
	_proj = IdleLogic.panel_projection(IdleLogic.projection(model.state, shown, model.forts), model.supports_now(), _dragging)
	return _proj


# --- input ------------------------------------------------------------------------

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and _grab.has_point(e.position):
			_dragging = true
			_since_release = -1.0
			_last_sent = -1.0
			_drag_to(e.position, false)
			accept_event()
		elif not e.pressed and _dragging:
			_dragging = false
			_since_release = 0.0  # the payoff holds for payoff_hold_s
			# Released: the committed values from the views take over. Clear the drag's projection
			# and the cache before the final refresh, so the panel's N of M is read from the
			# committed source and not cached from the drag.
			model.clear_projection()
			_proj_key = ""
			_drag_to(e.position, true)
			accept_event()
	elif e is InputEventMouseMotion and _dragging:
		_drag_to(e.position, false)
		accept_event()


func _drag_to(pos: Vector2, released: bool) -> void:
	_override = ValveLogic.won_valve(ValveLogic.valve_at(pos - _origin, _side), model.hud)  # won: on the WORK–WAR edge, FLOOD 0 sent
	refresh()
	queue_redraw()  # the handle follows the pointer even when no percentage changed
	var now := Time.get_ticks_msec() / 1000.0  # lint-ok: send throttle, not animation
	if ValveLogic.should_send(now, _last_sent, float(MapLogic.cfg()["valve_send_hz"]), released):
		_last_sent = now
		if _send() and released:
			committed.emit(_override.duplicate())


func _snap(key: String) -> void:
	_override = ValveLogic.won_valve(ValveLogic.snap(key), model.hud)
	refresh()
	queue_redraw()
	if _send():
		committed.emit(_override.duplicate())


## Where the opening's pointer ends, in screen px (this panel sits in a CanvasLayer): the FLOOD
## corner, the triangle's point nearest the map. The line reaches it over the empty strip of the
## plate under the rows, so it crosses no text.
func pointer_end() -> Vector2:
	return get_global_rect().position + _origin + (ValveLogic.corners(_side)["flood"] as Vector2)


## The opening's pulse on the triangle's edge (0: none). Redraws only when the level moved.
func set_pointer(level: float) -> void:
	if is_equal_approx(level, _pointer):
		return
	_pointer = level
	queue_redraw()


## While the handle is held: the set pieces keep Covington's stems on the last committed valve.
func is_dragging() -> bool:
	return _dragging


## Sends the shown valve; false (and a toast) when GameState refuses it.
func _send() -> bool:
	var v := _override
	var r := model.state.cmd_set_valve(v["work"], v["war"], v["flood"])
	if not r["ok"]:
		_override = {}
		toast.emit(RelishLogic.reason_text(str(r["reason"])))
		refresh()
	return bool(r["ok"])


# --- drawing ----------------------------------------------------------------------

func _draw() -> void:
	var cfg := MapLogic.cfg()
	var c: Dictionary = cfg["controls"]
	draw_style_box(MapUi.plate_box(float(c["valve_plate_alpha"]), 0), Rect2(Vector2.ZERO, size))
	var pts := ValveLogic.corners(_side)
	var tri := PackedVector2Array([_origin + pts["work"], _origin + pts["war"], _origin + pts["flood"], _origin + pts["work"]])
	var oc: Dictionary = cfg["opening"]
	var edge := Palette.c("undead").lightened(float(oc["edge_lighten"]) * _pointer)
	var edge_w := float(c["valve_edge_w_px"]) + float(oc["edge_width_boost_px"]) * _pointer
	var edge_glow := float(c["valve_edge_glow"]) + float(oc["edge_glow_boost"]) * _pointer
	for l in NodeLogic.capped_layers(edge, edge_w, edge_glow, float(c["valve_edge_halo_max_px"])):
		draw_polyline(tri, l[1], l[0])
	# where bone starts: a level tick across the triangle at view_hud.bone_war_share, a tiny word past its right end
	var tick := ValveLogic.bone_tick(ValveLogic.bone_edge(model.hud), _side)
	if not tick.is_empty():
		var tick_col := Palette.c(str(c["valve_bone_tick_key"]))
		draw_line(_origin + (tick[0] as Vector2), _origin + (tick[1] as Vector2), tick_col, float(c["valve_bone_tick_w_px"]))
		var lf := MapType.label_font()
		var ls := MapType.size_of("size_label")
		var at := _origin + (tick[1] as Vector2) + Vector2(float(c["valve_bone_label_gap_px"]), lf.get_ascent(ls) * 0.5)
		draw_string(lf, at, str(c["valve_bone_label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, ls, Palette.c(str(c["valve_bone_label_key"])))
	var hp := _origin + ValveLogic.point_of(shown_target(), _side)
	var cur := ValveLogic.now_ring_pos(_origin + ValveLogic.point_of(ValveLogic.won_valve(model.hud.get("valve", shown_target()), model.hud), _side), hp)
	LineGlow.ring(self, cur, float(c["valve_ghost_r_px"]), Palette.c("undead"), float(c["valve_ghost_w_px"]), float(c["valve_edge_glow"]))
	LineGlow.ring(self, hp, float(c["valve_handle_r_px"]), Palette.c("undead"), float(c["valve_ghost_w_px"]), float(c["valve_edge_glow"]))
	draw_circle(hp, float(c["valve_handle_r_px"]), Palette.c("undead_core"))
