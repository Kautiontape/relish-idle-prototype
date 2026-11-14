class_name MapTitheExplain
extends Control
## The first tithe warning, explained once. On the first `tithe_warning` ever seen (the "tithe_explain"
## flag in MapSeen, outside the save) a small plate opens over the targeted fort: Vei is sending a
## wave there, with the live ETA from the fort's view, what it is and how to blunt it. GOT IT closes
## it and sets the flag; "Send Relish" (cmd_move_relish) and "Centre" (the camera) are shortcuts that
## leave it open. It reappears only while the flag is unset. A LineGlow frame in the living colour
## (Vei's tide) on a plate, 14 px text, buttons at least 44 px. Debug: --setpiece=tithe_explain
## opens it on the targeted fort (or the demo fort) after debug_delay_s, through the same path as
## the event; pair it with --fixture=. A warning already pending at mount opens it too (open_pending). Text and placement: opening_logic.gd.

signal toast(msg: String)

var model: MapModel
var cam: MapCamera
var hud: MapHud
var seen: MapSeen

var _panel: PanelContainer
var _text: Label
var _fort_id := ""
var _fallback_eta := -1.0
var _shown_text := ""
var _top := 0.0  # the HUD plates' bottom edge: the panel stays under it


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var oc := OpeningLogic.cfg()
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", MapUi.plate_box(float(oc["tithe_plate_alpha"]), int(oc["tithe_pad_px"])))
	_panel.draw.connect(_draw_frame)
	_panel.visible = false
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(oc["tithe_btn_gap_px"]))
	_panel.add_child(col)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = float(oc["tithe_w_px"])
	MapType.style_label(_text, "text", int(oc["tithe_font_px"]))
	col.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(oc["tithe_btn_gap_px"]))
	col.add_child(row)
	for spec in [["tithe_got_it", _got_it], ["tithe_send", _send], ["tithe_centre", _centre]]:
		var b := Button.new()
		b.text = str(oc[spec[0]])
		MapUi.style_button(b, int(oc["tithe_font_px"]))
		b.pressed.connect(spec[1])
		row.add_child(b)
	_top = hud.top_inset()
	hud.inset_changed.connect(func(inset: float) -> void: _top = inset)
	if Game.state.debug_enabled and OS.get_cmdline_user_args().has("--setpiece=tithe_explain"):
		get_tree().create_timer(float(SetpieceLogic.cfg()["debug_delay_s"])).timeout.connect(_fire_debug)


func _fire_debug() -> void:
	if not is_inside_tree() or model.forts.is_empty():
		return
	var id := OpeningLogic.debug_tithe_fort(model.forts, SetpieceLogic.demo_target(model.forts, str(SetpieceLogic.cfg()["debug_target"])))
	on_event({"type": "tithe_warning", "fort_id": id, "eta_s": OpeningLogic.tithe_eta(model.forts, id, float(OpeningLogic.cfg()["tithe_debug_eta_s"]))})


## Opens on the first tithe warning ever seen (the router's held events arrive here too).
func on_event(ev: Dictionary) -> void:
	if str(ev.get("type", "")) != "tithe_warning" or seen.has(MapSeen.TITHE):
		return
	var id := str(ev.get("fort_id", ""))
	if not model.has_node(id):
		return
	_fort_id = id
	_fallback_eta = float(ev.get("eta_s", -1.0))
	_shown_text = ""
	_panel.visible = true
	refresh()


## A warning already pending when the map mounts (the event fired before it): after the model's
## first refresh, the explanation opens for the targeted fort as the event path does.
func open_pending() -> void:
	var p := OpeningLogic.pending_tithe(model.forts, seen.has(MapSeen.TITHE))
	if not p.is_empty():
		on_event({"type": "tithe_warning", "fort_id": p["fort_id"], "eta_s": p["eta_s"]})


func is_open() -> bool:
	return _panel.visible


## The text with the fort's live ETA (a new string only when the second changed).
func refresh() -> void:
	if not _panel.visible:
		return
	var f := model.fort(_fort_id)
	var eta := OpeningLogic.tithe_eta(model.forts, _fort_id, _fallback_eta)
	var s := OpeningLogic.tithe_text(str(f.get("name", _fort_id)), eta)
	if s != _shown_text:
		_shown_text = s
		_text.text = s
		_panel.reset_size()


func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	var anchor: Vector2 = get_viewport().get_canvas_transform() * model.node_pos(_fort_id)
	var oc := OpeningLogic.cfg()
	_panel.position = OpeningLogic.panel_pos(anchor, _panel.size, get_viewport_rect().size, _top,
		float(oc["tithe_gap_px"]), float(oc["tithe_margin_px"]))


func _draw_frame() -> void:
	var oc := OpeningLogic.cfg()
	var r := Rect2(Vector2.ZERO, _panel.size)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position])
	for l in NodeLogic.capped_layers(Palette.c("living"), float(oc["tithe_frame_w_px"]), float(oc["tithe_frame_glow"]), float(oc["tithe_frame_halo_max_px"])):
		_panel.draw_polyline(pts, l[1], l[0])


func _got_it() -> void:
	seen.mark(MapSeen.TITHE, float(model.hud.get("t", 0.0)))  # TODO(api-request #18)
	_panel.visible = false


func _send() -> void:
	var r := model.state.cmd_move_relish(_fort_id)
	if not bool(r["ok"]):
		toast.emit(RelishLogic.reason_text(str(r["reason"])))


func _centre() -> void:
	cam.centre_on(model.node_pos(_fort_id))
