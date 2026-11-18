extends PanelContainer
## The "While you were away" strip of the welcome-back replay (TownReplay): a plate under the first-goal line in the
## town view with the report's build and ready lines. A line with somewhere to go has a button (TownReplay.act_of);
## Close hides it, and so does cfg.hold_s after the replay's last flash (0 keeps it until closed).

signal acted(act: String)  # "crypt", "build" or "realm"

var _cfg: Dictionary = {}
var _col: VBoxContainer
var _title: Label
var _left := -1.0  # seconds until it hides (-1 = not timed)


func setup(cfg: Dictionary) -> void:
	_cfg = cfg
	var sb := TownUI.panel_box()
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 4)
	add_child(_col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_col.add_child(head)
	_title = TownUI.label("", _px(), "text")
	_title.add_theme_font_override("font", TownUI.bold_font())
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := TownUI.button(String(cfg.get("close", "Close")))
	close.custom_minimum_size = Vector2(0, TownUI.MIN_TARGET)
	close.pressed.connect(hide_strip)
	head.add_child(close)
	visible = false
	set_process(false)


func _px() -> int:
	return maxi(int(_cfg.get("px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)


## Shows `title` over `lines` ([{text, act}], TownReplay.lines), replacing any lines shown before.
func show_report(title: String, lines: Array) -> void:
	_title.text = title
	for i in range(_col.get_child_count() - 1, 0, -1):  # every row but the title's
		var n := _col.get_child(i)
		_col.remove_child(n)
		n.queue_free()
	var acts: Dictionary = _cfg.get("acts", {})
	for l in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_col.add_child(row)
		var lab := TownUI.label(String(l["text"]), _px(), "text")
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.custom_minimum_size = Vector2(float(_cfg.get("line_w_px", 360.0)), 0)
		row.add_child(lab)
		var act := String(l["act"])
		if act != "" and acts.has(act):
			var b := TownUI.button(String(acts[act]))
			b.custom_minimum_size = Vector2(0, TownUI.MIN_TARGET)
			b.pressed.connect(func(): acted.emit(act))
			row.add_child(b)
	_left = -1.0
	visible = true
	reset_size()


## The replay's flashes are done: the strip hides cfg.hold_s from now (0 or less keeps it until closed).
func flashes_done() -> void:
	var hold := float(_cfg.get("hold_s", 0.0))
	if hold > 0.0 and visible:
		_left = hold
		set_process(true)


func hide_strip() -> void:
	visible = false
	_left = -1.0
	set_process(false)


func _process(delta: float) -> void:
	if _left < 0.0:
		set_process(false)
		return
	_left -= delta
	if _left <= 0.0:
		hide_strip()
