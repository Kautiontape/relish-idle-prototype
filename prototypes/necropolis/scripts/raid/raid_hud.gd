class_name RaidHud
extends CanvasLayer
## Raid HUD: fort name/tier, a compact glanceable stat block (the WARD chain and the carried
## essence as pips with their integers beside them), trance meter, hint line, the
## always-visible teleport-home button (top-right) + its confirmation dialog.

var raid: Node = null

var _title: Label
var _stats: StatBlock
var _hint: Label
var _meter: Control
var _exit_btn: Control
var _dialog: ConfirmationDialog
var _flash: ColorRect
var _flash_t := -1.0
var _banner: Label
var _banner_t := -1.0
var _warden_line: Label = null   # the awake warden's status ("CAUGHT 2")
# boss extras
var _vei_bar: Control = null
var _backlog: Label = null


func build(p_raid: Node, boss_mode: bool) -> void:
	raid = p_raid
	layer = 10

	var box := VBoxContainer.new()
	box.position = Vector2(18, 14)
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_title = _mk_label(box, 24, Palette.c("vei"))
	_stats = StatBlock.new()
	_stats.setup(boss_mode)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_stats)
	_warden_line = _mk_label(box, 20, Palette.c("danger"))
	_warden_line.visible = false

	_banner = _mk_label(self, 20, Palette.c("relish"))
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.offset_left = -300.0
	_banner.offset_right = 300.0
	_banner.offset_top = 70.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false

	_hint = _mk_label(self, 19, Palette.c("text"))
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
	if boss_mode:
		_dialog.title = "Teleport"
		_dialog.dialog_text = "Are you sure you wish to Teleport home?"
		_dialog.get_ok_button().text = "Teleport"
	else:
		_dialog.title = "Retreat"
		_dialog.dialog_text = "Retreat through this exit? Your loot is banked and the fort does not flip."
		_dialog.get_ok_button().text = "Retreat"
	_dialog.confirmed.connect(func() -> void: raid.try_retreat())
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
		_backlog = _mk_label(self, 16, Palette.c("undead"))
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
	l.add_theme_color_override("font_outline_color", Palette.c("ground", 0.85))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


func _process(_delta: float) -> void:
	if raid == null:
		return
	refresh()
	if _banner_t >= 0.0:
		_banner_t -= _delta
		if _banner_t < 0.0:
			_banner.visible = false
	if _flash_t >= 0.0:
		_flash_t += _delta / maxf(0.05, Engine.time_scale)
		var f := _flash_t / 0.9
		if f >= 1.0:
			_flash.visible = false
			_flash_t = -1.0
		else:
			var c: Color = _flash.color
			c.a = (1.0 - f) * 0.85
			_flash.color = c


func refresh() -> void:
	_title.text = "%s — TIER %d" % [raid.fort_name().to_upper(), raid.fort_tier()]
	var st := _stats
	st.living = raid.enemies.size()
	var motes: int = raid.get_tree().get_nodes_in_group("raid_essence").size()
	if raid.ledger_v2 != null:
		var cc: int = raid.carried_count()
		st.carried = cc
		st.carry_max = int(raid.rcfg().get("essence", {}).get("carry_max", 12))
		st.loose = maxi(0, motes - cc)
		var w: Dictionary = raid.ward_counts()
		st.ward[0] = int(w["chaff"])
		st.ward[1] = int(w["soldier"])
		st.ward[2] = int(w["elite"])
		st.ward[3] = int(w["big"])
		var rc: Dictionary = raid.ledger_v2.raised_counts()
		st.raised_text = "%d chaff · %d soldier · %d elite" % [rc["chaff"], rc["soldier"], rc["elite"]]
	else:
		st.loose = motes
		var lg = raid.ledger
		st.raised_text = "%.0f chaff · %d soldier · %d elite" % [lg.chaff_pool, lg.soldiers, lg.elites]
	_hint.visible = not raid.first_raise_done and not raid._ended
	if not raid.is_boss():
		st.phyl = raid.phylactery_left()
		# the checkpoint risk: BANKED is the last snapshot, UNBANKED is what a death loses now
		var bk: Dictionary = RaidLogic.loot_counts(raid.endings.banked)
		var ub: Dictionary = RaidLogic.unbanked(raid.found_loot, raid.carried_count(), raid.endings.banked)
		st.banked_text = _loot_line(bk)
		st.unbanked_text = _loot_line(ub)
		st.unbanked_n = int(ub["total"])
		st.floor_n = raid.pickups_left()
		if raid.exit_hint_ready():
			_hint.text = "AT EXIT · RETREAT banks your loot"
			_hint.visible = true
		else:
			_hint.text = "HOLD SPACE — TRACE A CIRCLE"
	if _backlog != null:
		_backlog.text = "BACKLOG  %.0f    LOST  s%d e%d" % [raid.backlog_left, raid.army_lost["soldier"], raid.army_lost["elite"]]
	st.queue_redraw()


func _loot_line(c: Dictionary) -> String:
	return "relics %d · remnants %d · husks %d · blueprints %d · essence %d" % [int(c["relics"]), int(c["remnants"]),
		int(c["husks"]), int(c["blueprints"]), int(c["essence"])]


func flash(color: Color) -> void:
	var c := color
	c.a = 0.85
	_flash.color = c
	_flash.visible = true
	_flash_t = 0.0


## The warden's status line under the counters; empty text hides it.
func set_warden_line(text: String, color_key := "danger") -> void:
	if _warden_line == null:
		return
	_warden_line.visible = text != ""
	_warden_line.text = text
	_warden_line.add_theme_color_override("font_color", Palette.c(color_key))


## A plain banner line for `secs` seconds (warden wake, last chance, victory).
func show_banner(text: String, secs: float, color_key := "relish") -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", Palette.c(color_key))
	_banner.visible = true
	_banner_t = secs


## The banner when a checkpoint room banks new loot.
func show_checkpoint(loot: Dictionary) -> void:
	_banner.add_theme_color_override("font_color", Palette.c("relish"))
	_banner.text = "CHECKPOINT · loot banked\nrelics %d · blueprints %d · husks %d · remnants %d · essence %d" % [
		int(loot["relics"]), (loot["blueprints"] as Array).size(), (loot["husks"] as Array).size(),
		(loot["remnants"] as Array).size(), int(loot["essence"])]
	_banner.visible = true
	_banner_t = float(raid.rcfg().get("checkpoint", {}).get("banner_s", 2.5))


## Retreat is live only at an exit (always for the boss's teleport).
func exit_enabled() -> bool:
	return raid != null and raid.can_retreat()


func open_exit_dialog() -> void:
	if raid._ended or not exit_enabled():
		return
	_dialog.popup_centered()


## Standalone runs: show the emitted result so the scene is testable by itself.
func show_result(result: Dictionary, telemetry := "") -> void:
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
	lbl.text = "finished(result) emitted — standalone run\n" + telemetry + "\n\n" + JSON.stringify(result, "  ")
	panel.add_child(lbl)


# ------------------------------------------------------------- sub-controls --
## The compact stat block. One neutral label tone (`text_dim`) and one value tone (`text`); the
## pips carry the colour (WARD undead, essence, phylactery relish), so meaning is by shape and
## position, not hue. Everything is drawn from cached ints; nothing is allocated per frame.
class StatBlock:
	extends Control
	const RANKS := ["chaff", "soldier", "elite", "big"]
	var boss := false
	var living := 0
	var carried := 0
	var carry_max := 12
	var loose := 0
	var ward := [0, 0, 0, 0]
	var raised_text := ""
	var phyl := 0
	var banked_text := ""
	var unbanked_text := ""
	var unbanked_n := 0      # items + essence a death would lose now
	var floor_n := 0         # pickups still on the floor
	var _row := 20.0
	var _lab := 13
	var _val := 15
	var _pip := 7.0
	var _row_max := 24
	var _col := 92.0

	func setup(p_boss: bool) -> void:
		boss = p_boss
		var c: Dictionary = ConfigDb.data.get("raid", {}).get("hud", {})
		_pip = float(c.get("pip_px", 7.0))
		_lab = int(c.get("label_px", 13))
		_val = int(c.get("value_px", 15))
		_row_max = int(c.get("pip_row_max", 24))
		var rows := 3.0 if boss else 12.0   # living, essence, raised | + 4 ward rows, phylactery, banked, unbanked, stakes
		custom_minimum_size = Vector2(420.0, rows * _row + 8.0)

	func _label(y: float, text: String) -> void:
		draw_string(ThemeDB.fallback_font, Vector2(6, y), text, HORIZONTAL_ALIGNMENT_LEFT, _col, _lab, Palette.c("text_dim"))

	func _value(x: float, y: float, text: String, col: Variant = null) -> float:
		var f := ThemeDB.fallback_font
		var tone: Color = Palette.c("text") if col == null else col
		draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _val, tone)
		return x + f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _val).x

	## `n` pips left to right from x, `filled` of them solid; returns the x after the row.
	func _pips(x: float, y: float, n: int, filled: int, col: Color, r: float, diamond := false) -> float:
		var step := r * 2.0 + 3.0
		var dim := col
		dim.a = 0.6
		for i in n:
			var p := Vector2(x + r + step * i, y)
			if diamond:
				var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)])
				if i < filled:
					draw_colored_polygon(pts, col)
				else:
					draw_polyline(pts, dim, 1.3)
			elif i < filled:
				draw_circle(p, r, col)
			else:
				draw_arc(p, r - 0.6, 0.0, TAU, 12, dim, 1.3)
		return x + step * n

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Palette.c("ground", 0.62))
		var y := _row - 5.0
		var und := Palette.c("undead")
		_label(y, "LIVING")
		var lx := _pips(_col, y - 5.0, 1, 0, Palette.c("living"), _pip * 0.6)   # hollow ring = the living
		_value(lx + 4.0, y, str(living))
		y += _row
		if boss:
			_label(y, "ESSENCE")
			_value(_col, y, str(loose))
			y += _row
		else:
			_label(y, "WARD")
			y += _row
			for i in 4:
				var n := int(ward[i])
				_label(y, RANKS[i])
				var r := _pip * (0.5 + 0.12 * i)
				var shown := mini(n, _row_max)
				var x := _pips(_col, y - 5.0, shown, shown, und, r, i == 3)
				_value(x + 4.0, y, ("+" if n > _row_max else "") + str(n))
				y += _row
			_label(y, "ESSENCE")
			var ex := _pips(_col, y - 5.0, carry_max, carried, Palette.c("essence"), _pip * 0.5)
			_value(ex + 6.0, y, "%d/%d" % [carried, carry_max])
			if loose > 0:
				_value(ex + 6.0 + 60.0, y, "+%d loose" % loose)
			y += _row
		_label(y, "RAISED")
		_value(_col, y, raised_text)
		y += _row
		if not boss:
			_label(y, "PHYLACT.")
			var px := _pips(_col, y - 5.0, phyl, phyl, Palette.c("relish"), _pip * 0.6, true)
			_value(px + 4.0, y, str(phyl))
			y += _row
			_label(y, "BANKED")
			_value(_col, y, banked_text)
			y += _row
			var risk := unbanked_n > 0
			var tone := Palette.c("danger") if risk else Palette.c("text_dim")
			_label(y, "UNBANKED")
			_value(_col, y, unbanked_text, tone)
			y += _row
			# the stakes: one pip per unbanked thing (capped), then what it means
			var px2 := _pips(_col, y - 5.0, mini(unbanked_n, _row_max), mini(unbanked_n, _row_max), tone, _pip * 0.6, true)
			var note := "lost if you die" + ("" if floor_n <= 0 else " · %d on the floor" % floor_n)
			_value(px2 + 6.0, y, note, tone)


class TranceMeter:
	extends Control
	var raid: Node = null

	func _process(_d: float) -> void:
		queue_redraw()

	## Cooldown reads by shape: one segment per second of cooldown, draining away.
	func _segmented(r: Rect2, remaining_frac: float, total_s: float, col: Color) -> void:
		var n := maxi(1, roundi(total_s))
		var w := r.size.x / n
		var left := remaining_frac * n
		for i in n:
			var fill := clampf(left - i, 0.0, 1.0)
			if fill > 0.0:
				draw_rect(Rect2(r.position.x + w * i, r.position.y, (w - 2.0) * fill, r.size.y), col)

	func _draw() -> void:
		if raid == null or raid.trance == null or raid._ended:
			return
		var tr = raid.trance
		var r := Rect2(0, 12, 150, 12)
		var violet := Palette.c("relish")
		draw_rect(r.grow(2.0), Palette.c("ground", 0.8))
		var word := ""
		var col := violet
		if tr.state == RaidTrance.State.READY:
			word = "TRANCE READY"
			draw_rect(r, Palette.c("relish", 0.85))
		elif tr.state == RaidTrance.State.ACTIVE:
			word = "FOCUS"
			draw_rect(Rect2(r.position, Vector2(r.size.x * tr.focus_frac(), r.size.y)), violet)
		elif tr.state == RaidTrance.State.COOLDOWN:
			word = "COOLDOWN"
			col = Palette.c("cooldown")
			_segmented(r, tr.cooldown_frac(), tr.cooldown_total, Palette.c("cooldown", 0.9))
		elif tr.state == RaidTrance.State.LOCKOUT:
			word = "…"
			col = Palette.c("danger")
			_segmented(r, tr.cooldown_frac(), tr.cooldown_total, Palette.c("danger", 0.5))
		draw_string(ThemeDB.fallback_font, Vector2(0, 8), word,
			HORIZONTAL_ALIGNMENT_LEFT, 190, 14, col)


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

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var on := hud.exit_enabled()
		var boss: bool = hud.raid != null and hud.raid.is_boss()
		var border := Palette.c("relish", (1.0 if _hover else 0.55) if on else 0.2)
		var vei := Palette.c("vei")
		draw_rect(r, Palette.c("ground", 0.92))
		draw_rect(r, border, false, 2.0)
		# door glyph: frame, leaf ajar, knob + escape arrow
		var d0 := Vector2(14, 9)
		draw_rect(Rect2(d0, Vector2(18, 28)), Palette.c("text_dim"), false, 2.0)
		var leaf := PackedVector2Array([d0 + Vector2(2, 2), d0 + Vector2(13, 5),
			d0 + Vector2(13, 24), d0 + Vector2(2, 26)])
		draw_colored_polygon(leaf, Palette.c("relish", 0.75))
		draw_circle(d0 + Vector2(10.5, 14.5), 1.6, Palette.c("text", 0.9))
		draw_line(d0 + Vector2(22, 14), d0 + Vector2(32, 14), vei, 2.0)
		draw_line(d0 + Vector2(28, 10), d0 + Vector2(32, 14), vei, 2.0)
		draw_line(d0 + Vector2(28, 18), d0 + Vector2(32, 14), vei, 2.0)
		if not on:
			draw_rect(r, Palette.c("ground", 0.55))   # visibly disabled
			draw_string(ThemeDB.fallback_font, Vector2(52, size.y * 0.5 + 5), "reach an exit",
				HORIZONTAL_ALIGNMENT_LEFT, 96, 13, Palette.c("text_dim", 0.8))
			return
		draw_string(ThemeDB.fallback_font, Vector2(56, size.y * 0.5 + 6), "TELEPORT" if boss else "RETREAT",
			HORIZONTAL_ALIGNMENT_LEFT, 100, 15, Palette.c("vei", 1.0 if _hover else 0.8))


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
		var vei := Palette.c("vei")
		draw_rect(r.grow(2.0), Palette.c("ground", 0.8))
		draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), vei)
		draw_string(ThemeDB.fallback_font, Vector2(0, 12), "VEI",
			HORIZONTAL_ALIGNMENT_LEFT, 200, 15, vei)
		draw_string(ThemeDB.fallback_font, Vector2(size.x - 90, 12), "%.0f" % raid.vei.hp,
			HORIZONTAL_ALIGNMENT_RIGHT, 90, 15, vei)
