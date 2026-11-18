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
var _row: HBoxContainer  # the buttons' row; hidden when neither shows, so it leaves no gap
var _rev := -2


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var c: Dictionary = MapLogic.cfg()["controls"]
	add_theme_stylebox_override("panel", MapUi.plate_box(float(c["chip_plate_alpha"]), int(c["chip_pad_px"])))
	custom_minimum_size.x = float(c["chip_w_px"])
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(c["chip_vsep_px"]))
	add_child(vb)
	_name = Button.new()
	_name.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name.flat = true
	MapUi.style_button(_name, int(c["chip_font_px"]))
	_name.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_name.custom_minimum_size.y = float(c["chip_name_h_px"])  # the name is one line: no 44 px button pad
	_name.tooltip_text = "Centre the map on Relish"
	_name.pressed.connect(_centre)
	vb.add_child(_name)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", int(c["chip_hsep_px"]))
	vb.add_child(_row)
	_home = _button(_row, "GO HOME", float(c["chip_button_w_px"]))
	_home.pressed.connect(_go_home)
	_cancel = _button(_row, "CANCEL", float(c["chip_button_w_px"]))
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
	_row.visible = _home.visible or _cancel.visible
	reset_size.call_deferred()  # shrink the plate when a button hides


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
