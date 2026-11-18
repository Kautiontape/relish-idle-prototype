class_name MapRelishChip
extends PanelContainer
## Relish's chip, top-left under the objective strip: where she is ("Relish · travelling →
## Ashgate · 0:04"), GO HOME (hidden when she is home or walking home) and CANCEL (only while
## she travels). Clicking her name centres the camera on her. Every refusal's reason goes out as
## a toast, in plain words. Text and rules: relish_logic.gd.

signal toast(msg: String)

var model: MapModel
var hud: MapHud
var cam: MapCamera

var _name: Button
var _home: Button
var _cancel: Button
var _flow: HFlowContainer  # name + buttons; wraps the buttons below the name only when one row is too wide
var _rev := -2


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var c: Dictionary = MapLogic.cfg()["controls"]
	add_theme_stylebox_override("panel", MapUi.plate_box(float(c["chip_plate_alpha"]), int(c["chip_pad_px"])))
	custom_minimum_size.x = float(c["chip_w_px"])
	# One wrapping flow: the buttons sit on the name's row when `refresh` says the row fits
	# (it sets the flow's width), else they wrap to a row below.
	_flow = HFlowContainer.new()
	_flow.add_theme_constant_override("h_separation", int(c["chip_hsep_px"]))
	_flow.add_theme_constant_override("v_separation", int(c["chip_vsep_px"]))
	add_child(_flow)
	_name = Button.new()
	_name.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name.flat = true
	MapUi.style_button(_name, int(c["chip_font_px"]))
	_name.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_name.custom_minimum_size.y = float(c["chip_name_h_px"])  # the name is one line: no 44 px button pad
	_name.tooltip_text = "Centre the map on Relish"
	_name.pressed.connect(_centre)
	_flow.add_child(_name)
	_home = _button(_flow, "GO HOME", float(c["chip_button_w_px"]))
	_home.pressed.connect(_go_home)
	_cancel = _button(_flow, "CANCEL", float(c["chip_button_w_px"]))
	_cancel.pressed.connect(_do_cancel)
	if hud != null:
		hud.inset_changed.connect(_sit)
		_sit(hud.top_inset())
	refresh(true)


## Sits the chip just under the HUD plates; the HUD says when their edge moves.
func _sit(inset: float) -> void:
	var m: Array = MapLogic.cfg()["controls"]["chip_margin_px"]
	position = Vector2(float(m[0]), inset + float(m[1]))


func _button(parent: Node, text: String, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.x = w
	MapUi.style_button(b)
	parent.add_child(b)
	return b


## Sets the text and buttons from the model. Without `force` it is a no-op until the model has a
## new rev (so it is cheap to call every frame: a click shows at once).
func refresh(force := false) -> void:
	if not force and model.rev == _rev:
		return
	_rev = model.rev
	_name.text = RelishLogic.chip_text(model.relish, model.names)
	var b := RelishLogic.chip_buttons(model.relish)
	_home.visible = b["go_home"]
	_cancel.visible = b["cancel"]
	_lay_out()
	reset_size.call_deferred()  # shrink the plate when a button hides


## Buttons on the name's row if that row fits the left column, else the flow is chip_w_px wide and
## they wrap below. The name's click target is as tall as a button when they share its row.
func _lay_out() -> void:
	var c: Dictionary = MapLogic.cfg()["controls"]
	var ws := []
	for b in [_home, _cancel]:
		if b.visible:
			ws.append(b.get_combined_minimum_size().x)
	var name_w := _name.get_minimum_size().x
	var hsep := float(c["chip_hsep_px"])
	var inline := not ws.is_empty() and RelishLogic.chip_inline(name_w, ws, hsep, float(c["chip_pad_px"]), float(c["chip_max_w_px"]))
	var inner := float(c["chip_w_px"]) - 2.0 * float(c["chip_pad_px"])
	if inline:
		inner = maxf(RelishLogic.chip_row_w(name_w, ws, hsep, float(c["chip_pad_px"])) - 2.0 * float(c["chip_pad_px"]), inner)
	_flow.custom_minimum_size.x = inner
	_name.custom_minimum_size.y = float(MapLogic.cfg()["button_min_h_px"]) if inline else float(c["chip_name_h_px"])


func _centre() -> void:
	if cam != null and not model.relish.is_empty():
		cam.centre_on(MapModel.to_vec(model.relish.get("pos")))


func _go_home() -> void:
	var r := model.state.cmd_move_relish(MapModel.COVINGTON)
	if r["ok"]:
		toast.emit("Relish → %s · %s" % [HudLogic.node_name(MapModel.COVINGTON, model.names), RelishLogic.fmt_eta(float(r["eta_s"]))])
	else:
		toast.emit(RelishLogic.reason_text(str(r["reason"])))
	model.refresh(true)
	refresh(true)


func _do_cancel() -> void:
	var r := model.state.cmd_cancel_travel()
	if r["ok"]:
		toast.emit("Relish turns back · %s" % RelishLogic.fmt_eta(float(r["eta_s"])))
	else:
		toast.emit(RelishLogic.reason_text(str(r["reason"])))
	model.refresh(true)
	refresh(true)
