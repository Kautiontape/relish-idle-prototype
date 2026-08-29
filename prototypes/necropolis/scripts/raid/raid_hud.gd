class_name RaidHud
extends CanvasLayer
## Minimal raid HUD: fort name/tier, counters, trance meter, hint line, the
## always-visible teleport-home button (top-right) + its confirmation dialog.

const ORANGE := Color("#ff6a2b")
const GREEN := Color("#39ff9e")
const GREY := Color("#9a96aa")
const VIOLET := Color("#c04cff")
const GOLD := Color("#fff3d0")
const TRACE := Color("#50ffd9")
const AMBER := Color(1.0, 0.72, 0.25)
const DANGER := Color("#ff2d55")

var raid: Node = null

var _title: Label
var _living: Label
var _essence: Label
var _raised: Label
var _hint: Label
var _dim: ColorRect
var _meter: Control
var _exit_btn: Control
var _dialog: ConfirmationDialog
var _flash: ColorRect
var _flash_t := -1.0
# boss extras
var _vei_bar: Control = null
var _backlog: Label = null


func build(p_raid: Node, boss_mode: bool) -> void:
	raid = p_raid
	layer = 10

	_dim = ColorRect.new()
	_dim.color = Color(0.10, 0.03, 0.14, float(ConfigDb.data.get("raid", {}).get("trance", {}).get("dim_alpha", 0.2)))
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	add_child(_dim)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.position = Vector2(18, 14)
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_title = _mk_label(box, 24, GOLD)
	_living = _mk_label(box, 17, ORANGE)
	_essence = _mk_label(box, 17, GREEN)
	_raised = _mk_label(box, 17, Color("#bdf5d8"))

	_hint = _mk_label(self, 19, TRACE)
	_hint.text = "HOLD SPACE — TRACE A CIRCLE"
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.anchor_top = 1.0
	_hint.offset_top = -52.0
	_hint.offset_bottom = -24.0
	_hint.offset_left = -260.0
	_hint.offset_right = 260.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_meter = TranceMeter.new()
	_meter.raid = p_raid
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_meter)
	_meter.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_meter.anchor_top = 1.0
	_meter.offset_left = 18.0
	_meter.offset_top = -46.0
	_meter.offset_right = 208.0
	_meter.offset_bottom = -16.0

	_exit_btn = ExitButton.new()
	_exit_btn.hud = self
	add_child(_exit_btn)
	_exit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_exit_btn.anchor_left = 1.0
	_exit_btn.offset_left = -168.0
	_exit_btn.offset_top = 14.0
	_exit_btn.offset_right = -18.0
	_exit_btn.offset_bottom = 60.0

	_dialog = ConfirmationDialog.new()
	_dialog.title = "Teleport"
	_dialog.dialog_text = "Are you sure you wish to Teleport home?"
	_dialog.get_ok_button().text = "Teleport"
	_dialog.confirmed.connect(func() -> void: raid.confirm_exit())
	add_child(_dialog)

	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.visible = false
	add_child(_flash)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)

	if boss_mode:
		_vei_bar = VeiBar.new()
		_vei_bar.raid = p_raid
		_vei_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_vei_bar)
		_vei_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_vei_bar.anchor_left = 0.5
		_vei_bar.anchor_right = 0.5
		_vei_bar.offset_left = -240.0
		_vei_bar.offset_right = 240.0
		_vei_bar.offset_top = 12.0
		_vei_bar.offset_bottom = 54.0
		_backlog = _mk_label(self, 16, GREEN)
		_backlog.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_backlog.anchor_left = 0.5
		_backlog.anchor_right = 0.5
		_backlog.offset_left = -240.0
		_backlog.offset_right = 240.0
		_backlog.offset_top = 56.0
		_backlog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _mk_label(parent: Node, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


func _process(_delta: float) -> void:
	if raid == null:
		return
	refresh()
	if _flash_t >= 0.0:
		_flash_t += _delta / maxf(0.05, Engine.time_scale)
		var f := _flash_t / 0.9
		if f >= 1.0:
			_flash.visible = false
			_flash_t = -1.0
		else:
			var c: Color = _flash.color
			_flash.color = Color(c.r, c.g, c.b, (1.0 - f) * 0.85)


func refresh() -> void:
	_title.text = "%s — TIER %d" % [str(raid.seed_data.get("name", "?")).to_upper(), int(raid.seed_data.get("tier", 1))]
	_living.text = "LIVING  %d" % raid.enemies.size()
	_essence.text = "ESSENCE  %d" % raid.get_tree().get_nodes_in_group("raid_essence").size()
	var lg = raid.ledger
	_raised.text = "RAISED  chaff %.0f  ·  sold %d  ·  elite %d" % [lg.chaff_pool, lg.soldiers, lg.elites]
	_hint.visible = not raid.first_raise_done and not raid._ended
	_dim.visible = raid.trance_active
	if _backlog != null:
		_backlog.text = "BACKLOG  %.0f    LOST  s%d e%d" % [raid.backlog_left, raid.army_lost["soldier"], raid.army_lost["elite"]]


func flash(color: Color) -> void:
	_flash.color = Color(color.r, color.g, color.b, 0.85)
	_flash.visible = true
	_flash_t = 0.0


func open_exit_dialog() -> void:
	if raid._ended:
		return
	_dialog.popup_centered()


## Standalone runs: show the emitted result so the scene is testable by itself.
func show_result(result: Dictionary) -> void:
	var panel := PanelContainer.new()
	add_child(panel)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300.0
	panel.offset_top = -190.0
	panel.offset_right = 300.0
	panel.offset_bottom = 190.0
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.text = "finished(result) emitted — standalone run\n\n" + JSON.stringify(result, "  ")
	panel.add_child(lbl)


# ------------------------------------------------------------- sub-controls --
class TranceMeter:
	extends Control
	var raid: Node = null

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if raid == null or raid.trance == null or raid._ended:
			return
		var tr = raid.trance
		var r := Rect2(0, 12, 150, 12)
		draw_rect(r.grow(2.0), Color(0, 0, 0, 0.55))
		var word := ""
		var col := TRACE
		if tr.state == RaidTrance.State.READY:
			word = "TRANCE READY"
			draw_rect(r, Color(TRACE.r, TRACE.g, TRACE.b, 0.85))
		elif tr.state == RaidTrance.State.ACTIVE:
			word = "FOCUS"
			draw_rect(Rect2(r.position, Vector2(r.size.x * tr.focus_frac(), r.size.y)), TRACE)
		elif tr.state == RaidTrance.State.COOLDOWN:
			word = "COOLDOWN"
			col = AMBER
			draw_rect(Rect2(r.position, Vector2(r.size.x * (1.0 - tr.cooldown_frac()), r.size.y)),
				Color(AMBER.r, AMBER.g, AMBER.b, 0.9))
		elif tr.state == RaidTrance.State.LOCKOUT:
			word = "…"
			col = DANGER
			draw_rect(Rect2(r.position, Vector2(r.size.x * (1.0 - tr.cooldown_frac()), r.size.y)),
				Color(DANGER.r, DANGER.g, DANGER.b, 0.5))
		draw_string(ThemeDB.fallback_font, Vector2(0, 8), word,
			HORIZONTAL_ALIGNMENT_LEFT, 190, 13, col)


class ExitButton:
	extends Control
	var hud: RaidHud = null
	var _hover := false

	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hover = false; queue_redraw())

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			accept_event()
			hud.open_exit_dialog()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var border := VIOLET if _hover else Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.55)
		draw_rect(r, Color(0.09, 0.07, 0.13, 0.92))
		draw_rect(r, border, false, 2.0)
		# door glyph: frame, leaf ajar, knob + escape arrow
		var d0 := Vector2(14, 9)
		draw_rect(Rect2(d0, Vector2(18, 28)), Color(GREY.r, GREY.g, GREY.b, 0.9), false, 2.0)
		var leaf := PackedVector2Array([d0 + Vector2(2, 2), d0 + Vector2(13, 5),
			d0 + Vector2(13, 24), d0 + Vector2(2, 26)])
		draw_colored_polygon(leaf, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.75))
		draw_circle(d0 + Vector2(10.5, 14.5), 1.6, Color(1, 1, 1, 0.9))
		draw_line(d0 + Vector2(22, 14), d0 + Vector2(32, 14), GOLD, 2.0)
		draw_line(d0 + Vector2(28, 10), d0 + Vector2(32, 14), GOLD, 2.0)
		draw_line(d0 + Vector2(28, 18), d0 + Vector2(32, 14), GOLD, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(56, size.y * 0.5 + 6), "TELEPORT",
			HORIZONTAL_ALIGNMENT_LEFT, 100, 15, GOLD if _hover else Color(GOLD.r, GOLD.g, GOLD.b, 0.8))

	const GREY := Color("#9a96aa")
	const VIOLET := Color("#c04cff")
	const GOLD := Color("#fff3d0")


class VeiBar:
	extends Control
	var raid: Node = null

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if raid == null or raid.vei == null or not is_instance_valid(raid.vei):
			return
		var frac: float = clampf(raid.vei.hp / maxf(1.0, raid.vei.max_hp), 0.0, 1.0)
		var r := Rect2(0, 18, size.x, 14)
		draw_rect(r.grow(2.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), GOLD)
		draw_string(ThemeDB.fallback_font, Vector2(0, 12), "VEI",
			HORIZONTAL_ALIGNMENT_LEFT, 200, 15, GOLD)
		draw_string(ThemeDB.fallback_font, Vector2(size.x - 90, 12), "%.0f" % raid.vei.hp,
			HORIZONTAL_ALIGNMENT_RIGHT, 90, 15, GOLD)

	const GOLD := Color("#fff3d0")
