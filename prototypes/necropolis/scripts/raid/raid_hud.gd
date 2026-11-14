class_name RaidHud
extends CanvasLayer
## Raid HUD: fort name/tier, a compact glanceable stat block (the WARD chain and the carried
## essence as pips with their integers beside them), trance meter, hint line, the
## always-visible retreat button (top-right) + its confirmation dialog. The boss (Vei's final test)
## has no retreat: no button and no dialog; its BossBlock (top centre) shows the fronts, the horde,
## the break's beat pips and the backups left. A dungeon's awake warden gets the WardenBlock (top
## centre): its break meter and whether the counterplay is working.

var raid: Node = null

var _title: Label
var _stats: StatBlock
var _hint: Label
var _meter: Control
var _exit_btn: Control = null       # dungeon only
var _dialog: ConfirmationDialog = null
var _flash: ColorRect
var _flash_t := -1.0
var _banner: Label
var _banner_t := -1.0
var _banner_plate: ColorRect = null   # a dark plate fitted to the banner's lines (walls run under it)
var _banner_live := Callable()        # recomputes the banner's text while it shows (the last chance)
var _banner_live_t := 0.0
var _warden_block: Control = null   # dungeon only: the awake warden's break meter
var _pointers: Node2D = null        # dungeon only: the pointer to the nearest floor loot
var _push: PushLine = null          # dungeon only: the push-or-retreat line under the RETREAT button
var _push_t := 1.0
var _risk := {}                     # the UNBANKED counts, for the push line
var exit_pos := Vector2.INF         # the nearest exit's inner point (the Pointers' EXIT chevron)
var _banner_top := 70.0
var _loot_key := []              # [banked, found_loot, carried, on the floor] the BANKED/UNBANKED lines show
# boss extras
var _boss_block: Control = null
var boss_info: Dictionary = {}   # the boss's hud_info(), built once a frame in refresh() (BossBlock reads it)


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

	_banner_plate = ColorRect.new()
	_banner_plate.color = Palette.c("ground", 0.72)
	_banner_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_plate.visible = false
	add_child(_banner_plate)
	_banner_plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_plate.anchor_left = 0.5
	_banner_plate.anchor_right = 0.5
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

	if not boss_mode:
		_warden_block = WardenBlock.new()
		_warden_block.raid = p_raid
		_warden_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_warden_block.visible = false
		add_child(_warden_block)
		_warden_block.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_warden_block.anchor_left = 0.5
		_warden_block.anchor_right = 0.5
		_warden_block.offset_left = -340.0
		_warden_block.offset_right = 340.0
		_warden_block.offset_top = 10.0
		_warden_block.offset_bottom = 72.0

	if not boss_mode:   # there is no retreat from the Vei fight
		_exit_btn = ExitButton.new()
		_exit_btn.hud = self
		add_child(_exit_btn)
		_exit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_exit_btn.anchor_left = 1.0
		_exit_btn.offset_left = -196.0
		_exit_btn.offset_top = 14.0
		_exit_btn.offset_right = -18.0
		_exit_btn.offset_bottom = 60.0

		_push = PushLine.new()
		_push.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_push)
		_push.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_push.anchor_left = 1.0
		_push.offset_left = -760.0
		_push.offset_right = -18.0
		_push.offset_top = 64.0
		_push.offset_bottom = 88.0

		_dialog = ConfirmationDialog.new()
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

	if not boss_mode:
		_pointers = Pointers.new()
		_pointers.hud = self
		add_child(_pointers)
		move_child(_pointers, 0)   # under the stat block and its plate: the loot pointer never crosses HUD text

	if boss_mode:
		_boss_block = BossBlock.new()
		_boss_block.raid = p_raid
		_boss_block.hud = self
		_boss_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_boss_block)
		_boss_block.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_boss_block.anchor_left = 0.5
		_boss_block.anchor_right = 0.5
		_boss_block.offset_left = -320.0
		_boss_block.offset_right = 320.0
		_boss_block.offset_top = 10.0
		_boss_block.offset_bottom = 10.0 + BossBlock.H_BREAK
		_banner.offset_top = 10.0 + BossBlock.H_BREAK + 8.0
	if not boss_mode:
		_banner.offset_top = 116.0   # its own row under the push line (up to two lines), so neither can run into the other
	_banner_top = _banner.offset_top


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
	if _warden_block != null:
		# the banner steps down under the warden's block while it shows
		var top := _banner_top + ((14.0 + (_warden_block as WardenBlock).extra_h) if _warden_block.visible else 0.0)
		if _banner.offset_top != top:
			_banner.offset_top = top
			_fit_banner_plate()
		if _push != null:
			_push.max_w = _push_room()
	if _banner_t >= 0.0:
		_banner_t -= _delta
		if _banner_live.is_valid():
			_banner_live_t += _delta_real()
			if _banner_live_t >= 0.25:
				_banner_live_t = 0.0
				var lt: String = _banner_live.call()
				if lt != _banner.text:
					_banner.text = lt
					_fit_banner_plate()
		if _banner_t < 0.0:
			_banner.visible = false
			_banner_plate.visible = false
			_banner_live = Callable()
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
	_title.text = raid.fort_name().to_upper() if raid.is_boss() else "%s — TIER %d" % [raid.fort_name().to_upper(), raid.fort_tier()]
	var st := _stats
	st.living = raid.enemies.size()
	var motes: int = raid.get_tree().get_node_count_in_group("raid_essence")   # a count, no array
	if raid.is_boss():
		# the boss keeps no ledger: the WARD (her sacrifice chain) and the raised that stand
		st.loose = motes
		var raised := 0
		var party := 0
		for a in raid.allies:
			if is_instance_valid(a) and a.alive:
				if a.role == "party":
					party += 1
				else:
					raised += 1
		st.raised_text = "%d raised · %d big undead" % [raised, party]
		boss_info = raid.hud_info()   # once a frame; the boss block reads this copy
		var info: Dictionary = boss_info
		_hint.text = str(info["hint"])
		_hint.visible = _hint.text != ""
		st.queue_redraw()
		return
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
	_hint.visible = not raid.first_raise_done and not raid._ended
	if not raid.is_boss():
		st.phyl = raid.phylactery_left()
		st.phyl_word = RaidLogic.phylactery_word(st.phyl)
		if st.phyl_word != "":
			# no revive is a state, not a mood: `danger` whatever her hp (the halo's dashes say it in the world)
			st.phyl_tone = Palette.c("danger")
		# the checkpoint risk: BANKED is the last snapshot, UNBANKED is what a death loses now. Rebuilt only
		# when what they show changes (banked and found_loot are replaced, never edited, when they change)
		var carried: int = raid.carried_count()
		var floor_n: int = raid.pickups_left()
		if _loot_key.is_empty() or not is_same(_loot_key[0], raid.endings.banked) or not is_same(_loot_key[1], raid.found_loot) \
				or int(_loot_key[2]) != carried or int(_loot_key[3]) != floor_n:
			_loot_key = [raid.endings.banked, raid.found_loot, carried, floor_n]
			var bk: Dictionary = RaidLogic.loot_counts(raid.endings.banked)
			var ub: Dictionary = RaidLogic.unbanked(raid.found_loot, carried, raid.endings.banked)
			st.banked_text = RaidLogic.loot_line(bk)
			st.unbanked_text = RaidLogic.loot_line(ub)
			_risk = ub
			st.unbanked_n = int(ub["total"])
			st.floor_n = floor_n
			st.set_key(floor_n > 0)
			_push_t = 1.0   # the push line's "at risk" follows UNBANKED on the same frame
		_push_t += _delta_real()
		if _push != null and _push_t >= 0.25:
			_push_t = 0.0
			_update_push()
		if raid.exit_hint_ready():
			_hint.text = "AT EXIT · RETREAT banks your loot"
			_hint.visible = true
		else:
			_hint.text = "HOLD SPACE — TRACE A CIRCLE"
	st.queue_redraw()


func _delta_real() -> float:
	return get_process_delta_time() / maxf(0.05, Engine.time_scale)


## The push-or-retreat line, 4 times a second and on the frame UNBANKED changes: the living left,
## the nearest exit by walking distance (the compass word of the first step of the route to it,
## LayoutLogic.waypoint: the doorway to take, so it never points through a wall; and how many rooms
## away), and what a death would lose now. No exit found drops the exit clause. Its text is set only
## when it changes.
func _update_push() -> void:
	var lay: Dictionary = raid.layout
	var rel: RaidRelish = raid.relish
	if rel == null or lay.is_empty():
		return
	var doors: Array = lay.get("doors", [])
	var best := -1
	var bd := INF
	for i in doors.size():
		if not bool(doors[i].get("exit", false)):
			continue
		var d := LayoutLogic.route_dist(lay, rel.global_position, doors[i]["inner"], rel.radius)
		if d < bd:
			bd = d
			best = i
	exit_pos = Vector2.INF if best < 0 else (doors[best]["inner"] as Vector2)
	var word := ""
	var hops := -1
	var at_exit: bool = raid.endings.exit_idx >= 0
	if best >= 0 and not at_exit:
		var step := LayoutLogic.waypoint(lay, rel.global_position, exit_pos, rel.radius)
		word = RaidLogic.compass(step - rel.global_position)
		var rf := RaidLogic.room_of(lay, rel.global_position)
		var rt := int(doors[best].get("room", -1))
		if rf >= 0 and rt >= 0 and lay.has("room_hops"):
			hops = int(((lay["room_hops"] as Array)[rf] as Array)[rt])
	_push.set_text(RaidLogic.push_line(raid.enemies.size(), word, hops, _risk, at_exit,
		raid.endings.rooms_seen(), (lay.get("rooms", []) as Array).size()))


## Width the push line may use without running under the warden's block (narrow windows wrap it).
func _push_room() -> float:
	var room := _push.size.x
	if _warden_block != null and _warden_block.visible:
		var block_right := _warden_block.global_position.x + _warden_block.size.x
		room = minf(room, _push.global_position.x + _push.size.x - block_right - 12.0)
	return maxf(160.0, room)


## The banner's plate: the widest line plus a margin, as tall as its lines, centred under it.
func _fit_banner_plate() -> void:
	if _banner_plate == null:
		return
	var f := ThemeDB.fallback_font
	var w := 0.0
	var lines := _banner.text.split("\n")
	for l in lines:
		w = maxf(w, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x)
	var h := float(lines.size()) * _banner.get_line_height() + 8.0
	_banner_plate.offset_left = -w * 0.5 - 14.0
	_banner_plate.offset_right = w * 0.5 + 14.0
	_banner_plate.offset_top = _banner.offset_top - 3.0
	_banner_plate.offset_bottom = _banner.offset_top - 3.0 + h
	_banner_plate.visible = _banner.visible


## Screen point at the end of the "N on the floor" note (the loot pointer starts there), or INF
## when nothing lies on the floor.
func floor_anchor() -> Vector2:
	if _stats == null or _stats.floor_n <= 0 or _stats.floor_end == Vector2.INF:
		return Vector2.INF
	return _stats.global_position + _stats.floor_end


func flash(color: Color) -> void:
	var c := color
	c.a = 0.85
	_flash.color = c
	_flash.visible = true
	_flash_t = 0.0


## A plain banner line for `secs` seconds (warden wake, last chance, victory).
func show_banner(text: String, secs: float, color_key := "relish") -> void:
	_banner_live = Callable()
	_banner.text = text
	_banner.add_theme_color_override("font_color", Palette.c(color_key))
	_banner.visible = true
	_banner_t = secs
	_fit_banner_plate()


## A banner whose text `provider` recomputes 4 times a second while it shows (the last chance's
## "N essence to bank" falls as Relish gathers).
func show_banner_live(provider: Callable, secs: float, color_key := "relish") -> void:
	show_banner(str(provider.call()), secs, color_key)
	_banner_live = provider
	_banner_live_t = 0.0


## The banner when a checkpoint room banks new loot.
func show_checkpoint(loot: Dictionary) -> void:
	_banner.add_theme_color_override("font_color", Palette.c("relish"))
	_banner.text = "CHECKPOINT · loot banked\nrelics %d · blueprints %d · husks %d · remnants %d · essence %d" % [
		int(loot["relics"]), (loot["blueprints"] as Array).size(), (loot["husks"] as Array).size(),
		(loot["remnants"] as Array).size(), int(loot["essence"])]
	_banner_live = Callable()
	_banner.visible = true
	_banner_t = float(raid.rcfg().get("checkpoint", {}).get("banner_s", 2.5))
	_fit_banner_plate()


## Retreat is live only at an exit (never in the boss: there is no retreat from Vei).
func exit_enabled() -> bool:
	return raid != null and raid.can_retreat()


func open_exit_dialog() -> void:
	if _dialog == null or raid._ended or not exit_enabled():
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
	var phyl_word := ""      # "NO REVIVE · death ends the run" at 0 charges (RaidLogic.phylactery_word)
	var phyl_tone: Color = Palette.c("danger")   # the NO REVIVE words: `danger` whenever no charge is left
	var banked_text := ""
	var unbanked_text := ""
	var unbanked_n := 0      # items + essence a death would lose now
	var floor_n := 0         # pickups still on the floor
	var floor_end := Vector2.INF   # local end of the "N on the floor" note (the loot pointer's start)
	var _row := 20.0
	var _lab := 13
	var _val := 15
	var _pip := 7.0
	var _row_max := 24
	var _col := 92.0
	var plate_alpha := 0.86
	var show_key := false

	func setup(p_boss: bool) -> void:
		boss = p_boss
		var c: Dictionary = ConfigDb.data.get("raid", {}).get("hud", {})
		_pip = float(c.get("pip_px", 7.0))
		_lab = int(c.get("label_px", 13))
		_val = int(c.get("value_px", 15))
		_row_max = int(c.get("pip_row_max", 24))
		plate_alpha = float(c.get("plate_alpha", 0.86))
		var rows := 3.0 if boss else 12.0   # living, essence, raised | + 4 ward rows, phylactery, banked, unbanked, stakes
		custom_minimum_size = Vector2(420.0, rows * _row + 8.0)

	## The floor-loot key (two rows under the stakes) shows while something lies on the floor.
	func set_key(on: bool) -> void:
		if on == show_key:
			return
		show_key = on
		custom_minimum_size = Vector2(420.0, (12.0 + (2.0 if on else 0.0)) * _row + 8.0)

	## A floor glyph as the pickups draw it (RaidLoot.floor_glyph shapes), small, at `p`.
	func _key_glyph(p: Vector2, shape: String, col: Color) -> void:
		var s := 5.0
		match shape:
			"gem":
				draw_polyline(PackedVector2Array([p + Vector2(0, -s * 1.2), p + Vector2(s, -s * 0.25), p + Vector2(0, s * 1.2), p + Vector2(-s, -s * 0.25), p + Vector2(0, -s * 1.2)]), col, 1.5)
			"scroll":
				draw_polyline(PackedVector2Array([p + Vector2(-s, -s * 0.8), p + Vector2(s * 0.55, -s * 0.8), p + Vector2(s, -s * 0.35), p + Vector2(s, s * 0.8), p + Vector2(-s, s * 0.8), p + Vector2(-s, -s * 0.8)]), col, 1.3)
			"husk":
				draw_polyline(PackedVector2Array([p + Vector2(0, -s * 1.2), p + Vector2(s * 0.75, -s * 0.6), p + Vector2(s * 0.75, s * 0.6), p + Vector2(0, s * 1.2), p + Vector2(-s * 0.75, s * 0.6), p + Vector2(-s * 0.75, -s * 0.6), p + Vector2(0, -s * 1.2)]), col, 1.5)
			_:
				draw_polyline(PackedVector2Array([p + Vector2(-s * 0.55, s), p + Vector2(-s * 0.1, -s * 1.25), p + Vector2(s * 0.55, s * 0.2), p + Vector2(-s * 0.55, s)]), col, 1.5)

	func _draw_key(y: float) -> void:
		var f := ThemeDB.fallback_font
		var x := 6.0
		for k in [["relic", "relic"], ["remnant", "remnant"], ["husk", "husk"], ["blueprint", "blueprint"]]:
			var g := RaidLoot.floor_glyph(str(k[0]), false)
			_key_glyph(Vector2(x + 6.0, y - 4.0), str(g["shape"]), Palette.c(str(g["key"])))
			draw_string(f, Vector2(x + 16.0, y), str(k[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.c("text_dim"))
			x += 22.0 + f.get_string_size(str(k[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, Vector2(6.0, y + _row), "grey ×9 = a corpse pile (the bodies in it): walk close, it gives essence", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.c("text_dim"))

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
		# the plate sits near-opaque so a world glyph under the block never crosses its text
		draw_rect(Rect2(Vector2.ZERO, size), Palette.c("ground", plate_alpha))
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
				if n > 0:   # a zero rank is an empty row (the label stays: it teaches the chain's order)
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
			var vx := _value(px + 4.0, y, str(phyl), phyl_tone if phyl_word != "" else null)
			if phyl_word != "":
				# no revive left: the state in words (the halo says it in the world)
				var cut := phyl_word.find(" · ")
				var head := phyl_word if cut < 0 else phyl_word.substr(0, cut)
				var hx := _value(vx + 10.0, y, head, phyl_tone)
				if cut >= 0:
					draw_string(ThemeDB.fallback_font, Vector2(hx, y), phyl_word.substr(cut), HORIZONTAL_ALIGNMENT_LEFT, -1, _lab, Palette.c("text_dim"))
			y += _row
			# zero kinds are hidden; nothing at all is one dim word
			_label(y, "BANKED")
			_value(_col, y, banked_text if banked_text != "" else "none", null if banked_text != "" else Palette.c("text_dim"))
			y += _row
			var risk := unbanked_n > 0
			var tone := Palette.c("danger") if risk else Palette.c("text_dim")
			_label(y, "UNBANKED")
			_value(_col, y, unbanked_text if unbanked_text != "" else "none", tone)
			y += _row
			# the stakes: one pip per unbanked thing (capped), then what it means
			floor_end = Vector2.INF
			if risk or floor_n > 0:
				var px2 := _pips(_col, y - 5.0, mini(unbanked_n, _row_max), mini(unbanked_n, _row_max), tone, _pip * 0.6, true)
				var note := ("lost if you die" if risk else "") + ("" if floor_n <= 0 else (" · " if risk else "") + "%d on the floor" % floor_n)
				var nx := _value(px2 + 6.0, y, note, tone if risk else Palette.c("vei"))
				if floor_n > 0:
					floor_end = Vector2(nx + 4.0, y - 5.0)
			if show_key:
				_draw_key(y + _row)


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


## The awake warden's break meter (top centre; hidden while it sleeps and once it falls). Row 1:
## its name, the strength left as pips (`vei`, VISUAL-LANGUAGE law 9) with the phase notches where
## its phases are hp gates, "n/N", and the counterplay's running count: the Bellringer's
## "MUFFLED x n of m" (lit `undead` once it has worked, "braced" while a brace is up), the Huntsman's
## "INTERCEPTED x n · took k" (k pips taken inside stun windows). Pips a stun window took stay as
## `undead` rings with a slash; the open window's pips flash (steady under reduced motion).
## The Shieldwall's "FLANKED x n of m · took k" (hits from off its shield, of all the hits it took; k
## pips taken by them), the weak point's words until the first flank. The Pyre-priest's "SNUFFED x n ·
## took k" (acolytes a power big killed in one blow; k their pips), the weak point's words until the
## first snuff; its meter's right-hand pips are its acolytes.
## Row 2: the Bellringer's phase and its weak point; the Huntsman's CAUGHT track (danger diamonds,
## notched where catches change its phase) and whether it is hunting your dead; the Shieldwall's
## phase and its shield (WardenLogic.shield_label: arc, multipliers, turn rate, bash period); the
## Pyre-priest's phase, its acolytes left, its fire (WardenLogic.pyre_label: the ward, fires per beat
## and how many at Relish) and the essence it has burned (hidden at 0). Redrawn
## only when what it shows changes (or every frame while a stun window flashes).
class WardenBlock:
	extends Control
	var raid: Node = null
	var _key := -1
	var _key2 := -1
	var _t := 0.0
	var extra_h := 0.0   # the Huntsman's third row (what a catch costs) and a pack's row make the block taller
	var _key3 := -1

	func _warden() -> RaidWarden:
		if raid == null or raid.warden_run == null:
			return null
		var w = raid.warden_run.warden
		if w == null or not is_instance_valid(w) or not w.alive or not w.awake:
			return null
		return w

	func _process(d: float) -> void:
		var w := _warden()
		var show: bool = w != null and not raid._ended
		if show != visible:
			visible = show
			_key = -1
		if not show:
			return
		_t += d / maxf(0.05, Engine.time_scale)
		var eh := (20.0 if w is RaidHuntsman else 0.0) + (20.0 if w.spec.has("pack") else 0.0)
		if eh != extra_h:
			extra_h = eh
			offset_bottom = offset_top + 62.0 + eh
			_key = -1
		var k := w.meter_lit() | (w.phase << 6) | (w.weak_taken << 9)
		var k2 := 0
		var flashing := false
		if w is RaidBellringer:
			var bw := w as RaidBellringer
			k2 = mini(bw.slams_muffled, 1023) | (mini(bw.slams, 1023) << 10) | (int(bw.muffled) << 20)
		elif w is RaidHuntsman:
			var hw := w as RaidHuntsman
			flashing = hw.is_stunned()
			k2 = mini(hw.intercepts, 1023) | (mini(hw.catches, 1023) << 10) | (int(flashing) << 20) | (int(hw.hunting_undead) << 21)
		elif w is RaidShieldwall:
			var sw := w as RaidShieldwall
			k2 = (sw.flanks & 0xFFFFF) | ((sw.hits & 0xFFFFF) << 20)
		elif w is RaidPyrePriest:
			var pp := w as RaidPyrePriest
			k2 = mini(pp.snuffs, 63) | (mini(pp.living(), 63) << 6) | (mini(pp.essence_burned, 0xFFFF) << 12)
		var k3 := mini(w.pack_alive(), 255) | (int(w.horn_beat >= 0.0) << 8) | (mini(w.horns, 63) << 9)
		if k != _key or k2 != _key2 or k3 != _key3 or (flashing and not Pulse.reduced_motion):
			_key = k
			_key2 = k2
			_key3 = k3
			queue_redraw()

	func _text(x: float, y: float, text: String, px: int, key := "text") -> float:
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Palette.c(key))
		return x + f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x

	func _notch(x: float, y: float) -> void:
		draw_line(Vector2(x, y - 11.0), Vector2(x, y + 1.0), Palette.c("vei", 0.9), 2.0)

	## A warden with a pack: HORN while it sounds, "HOUNDS n of m · it takes ×0.25" while they run, else
	## what the pack is (WardenLogic.pack_teach).
	func _pack_row(w: RaidWarden, x0: float, y: float) -> void:
		var pk: Dictionary = w.spec.get("pack", {})
		if pk.is_empty():
			return
		if w.horn_beat >= 0.0:
			_text(x0, y, "HORN · %d %s coming" % [w.horn_pts.size(), str(pk.get("name", "pack"))], 13, "danger")
		elif w.pack_alive() > 0:
			_text(x0, y, WardenLogic.pack_label(pk, w.pack_alive(), int(pk.get("size", 0))), 13, "vei")
		else:
			_text(x0, y, WardenLogic.pack_teach(pk), 13, "text_dim")

	func _draw() -> void:
		var w := _warden()
		if w == null:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Palette.c("ground", 0.62))
		var x0 := 12.0
		var px0 := 150.0
		var y := 26.0
		_text(x0, y, str(w.spec.get("name", "")).to_upper(), 13, "text_dim")
		# row 1: the strength left, notched at the phase boundaries
		var lit := w.meter_lit()
		var hw: RaidHuntsman = w as RaidHuntsman
		var win_lo := lit
		var win_hi := -1
		if hw != null and hw.is_stunned() and hw.stun_lit0 > lit:
			win_hi = hw.stun_lit0
		var blink := 1.0 if Pulse.reduced_motion else 0.55 + 0.45 * sin(_t * 14.0)
		var x := px0 + 6.0
		var r := 6.0
		for i in w.meter_n:
			if w.meter_notch.has(i):
				_notch(x - 3.5, y + 1.0)
				x += 9.0
			var p := Vector2(x, y - 5.0)
			if w.pip_lit(i):
				draw_circle(p, r, Palette.c("vei"))
			elif i >= win_lo and i < win_hi:
				# the open stun window took this pip: it flashes, slashed (shape as well as colour)
				draw_circle(p, r, Palette.c("undead", blink))
				draw_line(p + Vector2(-r * 0.7, r * 0.7), p + Vector2(r * 0.7, -r * 0.7), Palette.c("ground", 0.9), 1.8)
			elif w.weak_marks[i] != 0:
				draw_arc(p, r - 0.6, 0.0, TAU, 14, Palette.c("undead"), 1.6)
				draw_line(p + Vector2(-r * 0.7, r * 0.7), p + Vector2(r * 0.7, -r * 0.7), Palette.c("undead"), 1.6)
			else:
				draw_arc(p, r - 0.6, 0.0, TAU, 14, Palette.c("text_dim", 0.6), 1.3)
			x += 16.0
		x = _text(x + 2.0, y, "%d/%d" % [lit, w.meter_n], 15)
		y += 26.0
		if w is RaidBellringer:
			var bw := w as RaidBellringer
			var n := bw.slams_muffled
			var x2 := x + 14.0
			if bw.slams > 0:   # no slam yet: no "×0 of 0" (the PHASE row below already says what muffles it)
				x2 = _text(x2, y - 26.0, "MUFFLED ×%d of %d" % [n, bw.slams], 15, "undead" if n > 0 else "text_dim")
			if bw.muffled:
				_text(x2 + 8.0, y - 26.0, "braced", 13, "undead")
			_text(x0, y, "PHASE", 13, "text_dim")
			var x3 := _text(px0 + 6.0, y, "%d/%d" % [w.phase + 1, (w.spec.get("phases", []) as Array).size()], 15)
			_text(x3 + 12.0, y, str((w.spec.get("weak_point", {}) as Dictionary).get("label", "")), 13, "text_dim")
		elif hw != null:
			var n2 := hw.intercepts
			var tag := "INTERCEPTED ×%d" % n2 + ("" if w.weak_taken <= 0 else " · took %d" % w.weak_taken)
			var x4 := x + 14.0
			if n2 > 0:
				x4 = _text(x4, y - 26.0, tag, 15, "undead")
			else:   # no intercept yet: teach the counter in words instead of a zero
				x4 = _text(x4, y - 26.0, str((w.spec.get("weak_point", {}) as Dictionary).get("label", "")), 13, "text_dim")
			if win_hi > 0:
				_text(x4 + 8.0, y - 26.0, "STUNNED", 13, "undead")
			# row 2: the hunt, notched where catches change its phase
			_text(x0, y, "CAUGHT", 13, "text_dim")
			var notches := WardenLogic.catch_notches(w.spec)
			var slots := maxi(WardenLogic.catch_slots(w.spec), hw.catches)
			var cx := px0 + 6.0
			for i in slots:
				if notches.has(i):
					_notch(cx - 3.5, y + 1.0)
					cx += 9.0
				var q := Vector2(cx, y - 5.0)
				var pts := PackedVector2Array([q + Vector2(0, -6), q + Vector2(6, 0), q + Vector2(0, 6), q + Vector2(-6, 0), q + Vector2(0, -6)])
				if i < hw.catches:
					draw_colored_polygon(pts, Palette.c("danger"))
				else:
					draw_polyline(pts, Palette.c("text_dim", 0.6), 1.3)
				cx += 16.0
			var x5 := cx + 2.0
			if hw.catches > 0:
				x5 = _text(x5, y, str(hw.catches), 15, "danger")
			x5 = _text(x5 + 12.0, y, "phase %d/%d" % [w.phase + 1, (w.spec.get("phases", []) as Array).size()], 13, "text_dim")
			if hw.hunting_undead:
				_text(x5 + 12.0, y, "hunting your dead", 13, "danger")
			# row 3: what a catch costs and where the phases turn (from the spec, so it follows the config)
			_text(x0, y + 22.0, WardenLogic.catch_label(w.spec), 13, "text_dim")
		elif w is RaidShieldwall:
			var sw := w as RaidShieldwall
			var x6 := x + 14.0
			if sw.flanks > 0:
				_text(x6, y - 26.0, "FLANKED ×%d of %d" % [sw.flanks, sw.hits] + ("" if w.weak_taken <= 0 else " · took %d" % w.weak_taken), 15, "undead")
			else:   # no flank yet: teach the counter in words instead of a zero
				_text(x6, y - 26.0, str((w.spec.get("weak_point", {}) as Dictionary).get("label", "")), 13, "text_dim")
			_text(x0, y, "PHASE", 13, "text_dim")
			var x7 := _text(px0 + 6.0, y, "%d/%d" % [w.phase + 1, (w.spec.get("phases", []) as Array).size()], 15)
			_text(x7 + 12.0, y, WardenLogic.shield_label(w.spec, w.phase), 13, "text_dim")
		elif w is RaidPyrePriest:
			var pp := w as RaidPyrePriest
			var x8 := x + 14.0
			if pp.snuffs > 0:
				_text(x8, y - 26.0, "SNUFFED ×%d" % pp.snuffs + ("" if w.weak_taken <= 0 else " · took %d" % w.weak_taken), 15, "undead")
			else:   # no snuff yet: teach the counter in words instead of a zero
				_text(x8, y - 26.0, str((w.spec.get("weak_point", {}) as Dictionary).get("label", "")), 13, "text_dim")
			_text(x0, y, "PHASE", 13, "text_dim")
			var x9 := _text(px0 + 6.0, y, "%d/%d" % [w.phase + 1, (w.spec.get("phases", []) as Array).size()], 15)
			var lv := pp.living()
			if lv > 0:
				x9 = _text(x9 + 12.0, y, "ACOLYTES %d/%d" % [lv, pp.acolytes.size()], 13, "vei")
			x9 = _text(x9 + 12.0, y, WardenLogic.pyre_label(w.spec, w.phase, lv), 13, "danger" if lv <= 0 else "text_dim")
			if pp.essence_burned > 0:
				_text(x9 + 12.0, y, "burned %d essence" % pp.essence_burned, 13, "danger")
		_pack_row(w, x0, y + (44.0 if hw != null else 22.0))


## Screen-space pointers over the world (a Node2D: it takes no input). The loot pointer: a faint
## dashed `vei` line from the HUD's "N on the floor" to the nearest pickup, ringed, while it is on
## screen; an edge chevron marked LOOT pointing at it while it is off screen. The exit pointer: an
## edge chevron marked EXIT (`relish`, the exits' lip colour) toward the nearest exit while it is off
## screen. The nearest pickup and exit are re-picked 4 times a second; each frame only projects them,
## and it redraws only when what it would draw moves (nothing to point at: no redraw at all).
class Pointers:
	extends Node2D
	var hud: RaidHud = null
	var _t := 1.0
	var _loot: Node2D = null
	var _chev := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var _ep := Vector2.INF      # the off-screen exit's screen point (INF: no EXIT chevron)
	var _sp := Vector2.INF      # the nearest pickup's screen point (INF: none)
	var _from := Vector2.INF    # the HUD's "N on the floor" anchor

	func _process(d: float) -> void:
		var raid = hud.raid if hud != null else null
		var on: bool = raid != null and not raid._ended and raid.relish != null
		if on != visible:
			visible = on
		if not on:
			return
		_t += d / maxf(0.05, Engine.time_scale)
		if _t >= 0.25:
			_t = 0.0
			_loot = _nearest(raid, "raid_pickups")
		var view := get_viewport_rect().size
		var inner := Rect2(Vector2.ZERO, view).grow(-30.0)
		var xf: Transform2D = raid.get_viewport().get_canvas_transform()
		var ep := Vector2.INF
		if hud.exit_pos != Vector2.INF:
			ep = xf * hud.exit_pos
			if inner.has_point(ep):
				ep = Vector2.INF   # on screen: its lips and sigil already say where it is
		var sp := Vector2.INF
		if _loot != null and is_instance_valid(_loot) and _loot.is_in_group("raid_pickups"):
			sp = xf * _loot.global_position
		var from := hud.floor_anchor() if sp != Vector2.INF else Vector2.INF
		if ep != _ep or sp != _sp or from != _from:
			_ep = ep
			_sp = sp
			_from = from
			queue_redraw()

	func _nearest(raid: Node, group: String) -> Node2D:
		var best: Node2D = null
		var bd := INF
		var rp: Vector2 = raid.relish.global_position
		for o in raid.get_tree().get_nodes_in_group(group):
			var d: float = (o as Node2D).global_position.distance_to(rp)
			if d < bd:
				bd = d
				best = o
		return best

	## A chevron on the screen's inset edge where the line from its centre to `sp` leaves it.
	func _edge(sp: Vector2, view: Vector2, col: Color, word: String) -> void:
		var c := view * 0.5
		var dir := (sp - c).normalized()
		var m := 34.0
		var tx := INF if absf(dir.x) < 0.0001 else ((view.x - m) - c.x) / absf(dir.x)
		var ty := INF if absf(dir.y) < 0.0001 else ((view.y - m) - c.y) / absf(dir.y)
		var p := c + dir * minf(tx, ty)
		_chev[0] = p + dir * 12.0
		_chev[1] = p - dir * 6.0 + dir.orthogonal() * 10.0
		_chev[2] = p - dir * 6.0 - dir.orthogonal() * 10.0
		draw_colored_polygon(_chev, Palette.c("ground", 0.8))
		draw_polyline(_chev, col, 2.0)
		draw_line(_chev[2], _chev[0], col, 2.0)
		var f := ThemeDB.fallback_font
		var tw := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var lp := p - dir * 26.0 - Vector2(tw * 0.5, -5.0)
		draw_string(f, lp, word, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

	func _draw() -> void:
		var view := get_viewport_rect().size
		if _ep != Vector2.INF:
			_edge(_ep, view, Palette.c("relish"), "EXIT")
		if _sp == Vector2.INF:
			return
		if Rect2(Vector2.ZERO, view).grow(-30.0).has_point(_sp):
			if _from != Vector2.INF:
				draw_dashed_line(_from, _sp, Palette.c("vei", 0.45), 1.5, 7.0)
			draw_arc(_sp, 26.0, 0.0, TAU, 28, Palette.c("vei", 0.7), 1.5)
		else:
			_edge(_sp, view, Palette.c("vei"), "LOOT")


## The push-or-retreat line, right-aligned on a dark backing (walls run under the HUD). When it is
## wider than `max_w` (a narrow window, where it would run under the warden's block) it wraps at its
## " · " clauses onto more lines, still right-aligned. Redrawn only when its text or room changes.
class PushLine:
	extends Control
	var text := ""
	var max_w := 4096.0:
		set(v):
			if absf(v - max_w) >= 1.0:
				max_w = v
				queue_redraw()

	func set_text(t: String) -> void:
		if t != text:
			text = t
			queue_redraw()

	func _line(f: Font, y: float, s: String) -> void:
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var x := size.x - w
		draw_rect(Rect2(Vector2(x - 10.0, y - 3.0), Vector2(w + 12.0, 28.0)), Palette.c("ground", float(ConfigDb.data.get("raid", {}).get("hud", {}).get("plate_alpha", 0.86))))
		draw_string(f, Vector2(x - 2.0, y + 17.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Palette.c("text"))

	func _draw() -> void:
		if text == "":
			return
		var f := ThemeDB.fallback_font
		if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 8.0 <= max_w:
			_line(f, 0.0, text)
			return
		var y := 0.0
		var cur := ""
		for part in text.split(" · "):
			var next := part if cur == "" else cur + " · " + part
			if cur != "" and f.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 8.0 > max_w:
				_line(f, y, cur)
				y += 22.0
				cur = part
			else:
				cur = next
		if cur != "":
			_line(f, y, cur)


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
		draw_string(ThemeDB.fallback_font, Vector2(56, 21), "RETREAT",
			HORIZONTAL_ALIGNMENT_LEFT, 120, 15, Palette.c("vei", 1.0 if _hover else 0.8))
		# what it does, always beside the button at an exit (the hint line may be teaching the circle)
		draw_string(ThemeDB.fallback_font, Vector2(56, 38), "banks your loot",
			HORIZONTAL_ALIGNMENT_LEFT, 130, 13, Palette.c("text", 0.85))


## Vei's final test (top centre). Fronts phase: FRONTS n/4 · need k, a front pip per front (filled
## once it breaks through), and the phase-1 clock. The break: BACKLOG (the seed's horde) as an upright
## integer with the ferry's rate in plain words (the real clock is deaths, so no minus, no slant) and
## which side is winning, then the BREAK meter drawn as the wardens' meter (WardenBlock): break_beats
## pips lit from the left by the streak, a notch every `notch` pips, a lapse's pips slashed in `danger`
## while it shows (flashing, steady under reduced motion), the beat count and, while the pace gains,
## "~30 s at this pace". Under it one line: the phase-2 rule for the break's first hint_s seconds, and
## once a lapse has happened "LAPSES ×n · −k beats" (no row before the first). Always: BACKUPS left as
## pips (a phylactery diamond, a clone dot) and one cracked violet ring per backup spent. Reads the HUD's once-a-frame boss_info and
## redraws only when what it shows changes (or while a lapse flashes).
class BossBlock:
	extends Control
	var raid: Node = null
	var hud: Node = null
	const H_FRONTS := 94.0   # the plate's height before the break (three rows)
	const H_BREAK := 122.0  # and from the break on (four: the rule / lapse line sits under the meter)
	var _key := PackedInt32Array()
	var _next := PackedInt32Array()
	var _eta_key := ""
	var _t := 0.0
	static var _oblique: FontVariation = null

	static func oblique() -> FontVariation:
		if _oblique == null:
			_oblique = FontVariation.new()
			_oblique.base_font = ThemeDB.fallback_font
			_oblique.variation_transform = Transform2D(Vector2(1, 0), Vector2(tan(deg_to_rad(9.0)), 1), Vector2.ZERO)
		return _oblique

	static func thousands(n: int) -> String:
		var t := str(absi(n))
		var out := ""
		while t.length() > 3:
			out = "," + t.substr(t.length() - 3) + out
			t = t.substr(0, t.length() - 3)
		return ("-" if n < 0 else "") + t + out

	func _info() -> Dictionary:
		return hud.boss_info if hud != null else {}

	## Redraw when a shown number changes, or every frame while a lapse flashes (not under reduced motion).
	func _process(d: float) -> void:
		_t += d / maxf(0.05, Engine.time_scale)
		var info := _info()
		if info.is_empty():
			return
		_next.resize(17)
		_next[0] = int(info["break_began"]) | (int(info["over"]) << 1) | (int(info["won"]) << 2) | (int(info["winning"]) << 3) | (int(info["lapse_on"]) << 4)
		_next[1] = int(info["met"])
		_next[2] = floori(float(info["t"]))
		_next[3] = roundi(float(info["horde"]))
		_next[4] = int(info["streak"])
		_next[5] = int(info["break_beats"])
		_next[6] = int(info["lapses"])
		_next[7] = int(info["lapse_lost"])
		_next[8] = int(info["lapse_lo"])
		_next[9] = int(info["lapse_hi"])
		_next[10] = int(info["phyl_left"])
		_next[11] = int(info["clones_left"])
		_next[12] = int(info["spent_phyl"]) + int(info["spent_clones"])
		_next[13] = roundi(float(info["ferry"]) * 100.0)
		_next[14] = int(info["required"])
		_next[15] = int(info["notch"])
		_next[16] = int(info["rule_on"])
		var eta_key := str(info["eta"])
		if _next != _key or eta_key != _eta_key or (bool(info["lapse_on"]) and not Pulse.reduced_motion):
			_key = _next.duplicate()
			_eta_key = eta_key
			queue_redraw()

	func _label(x: float, y: float, text: String) -> float:
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.c("text_dim"))
		return x + f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x

	func _text(x: float, y: float, text: String, px: int, key := "text", font: Font = null) -> float:
		var f: Font = font if font != null else ThemeDB.fallback_font
		draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Palette.c(key))
		return x + f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x

	func _pip(p: Vector2, r: float, col: Color, filled: bool, diamond: bool) -> void:
		if diamond:
			var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)])
			if filled:
				draw_colored_polygon(pts, col)
			else:
				draw_polyline(pts, Palette.c("text_dim", 0.6), 1.3)
		elif filled:
			draw_circle(p, r, col)
		else:
			draw_arc(p, r - 0.6, 0.0, TAU, 12, Palette.c("text_dim", 0.6), 1.3)

	func _cracked(p: Vector2, r: float, i: int) -> void:
		for j in 3:
			var a0: float = TAU * j / 3.0 + 0.7 * i + 0.2
			draw_arc(p, r, a0, a0 + TAU / 3.0 - 0.55, 8, Palette.c("relish", 0.9), 1.6)

	func _notch(x: float, y: float) -> void:
		draw_line(Vector2(x, y - 11.0), Vector2(x, y + 1.0), Palette.c("vei", 0.9), 2.0)

	func _draw() -> void:
		var info := _info()
		if info.is_empty():
			return
		draw_rect(Rect2(Vector2(0.0, 0.0), Vector2(size.x, H_BREAK if bool(info["break_began"]) else H_FRONTS)), Palette.c("ground", 0.62))
		var x0 := 12.0
		var col2 := 108.0
		var y := 26.0
		if not bool(info["break_began"]):
			var x := _label(x0, y, "FRONTS")
			x = _text(col2, y, "%d/4" % int(info["met"]), 20)
			x = _text(x + 8.0, y, "· need %d" % int(info["required"]), 15)
			var tx := size.x - 150.0
			_label(tx, y, "TIME")
			_text(tx + 44.0, y, "%d / %d s" % [floori(float(info["t"])), roundi(float(info["max_t"]))], 15)
			y += 28.0
			_label(x0, y, "BROKEN")
			for i in 4:
				_pip(Vector2(col2 + 8.0 + 20.0 * i, y - 5.0), 6.0, Palette.c("undead"), i < int(info["met"]), true)
			_text(col2 + 96.0, y, "a front breaks when its stream reaches her court", 13, "text_dim")
		else:
			# the backlog (the seed's horde), the ferry's rate in words, and which side the beat is going to.
			# The backlog drains by deaths, not by this clock (it would take ~90 min): no minus, no slant.
			_label(x0, y, "BACKLOG")
			var x2 := _text(col2, y, thousands(roundi(float(info["horde"]))), 20)
			x2 = _text(x2 + 10.0, y, "ferried %.2f/s" % float(info["ferry"]), 13, "text_dim")
			if bool(info["won"]):
				_text(x2 + 18.0, y, "SHE BREAKS", 15, "vei")
			elif bool(info["over"]):
				_text(x2 + 18.0, y, "the fight is lost", 13, "danger")
			elif bool(info["winning"]):
				_text(x2 + 18.0, y, "raise > ferry", 13, "undead")
			else:
				_text(x2 + 18.0, y, "raise < ferry", 13, "living")
			y += 28.0
			# the break meter, as the wardens': lit from the left, notched, a lapse's pips slashed
			_label(x0, y, "BREAK")
			var n := int(info["break_beats"])
			var st := int(info["streak"])
			var notch := maxi(1, int(info["notch"]))
			var lo := int(info["lapse_lo"])
			var hi := int(info["lapse_hi"]) if bool(info["lapse_on"]) else -1
			var blink := 1.0 if Pulse.reduced_motion else 0.55 + 0.45 * sin(_t * 14.0)
			var r := 5.0
			var x := col2 + 8.0
			for i in n:
				if i > 0 and i % notch == 0:
					_notch(x - 3.5, y + 1.0)
					x += 7.0
				var p := Vector2(x, y - 5.0)
				if i < st:
					draw_circle(p, r, Palette.c("vei"))
				elif i >= lo and i < hi:
					# the lapse took this pip: it flashes, slashed (shape as well as colour)
					draw_circle(p, r, Palette.c("danger", blink))
					draw_line(p + Vector2(-r * 0.7, r * 0.7), p + Vector2(r * 0.7, -r * 0.7), Palette.c("ground", 0.9), 1.8)
				else:
					draw_arc(p, r - 0.6, 0.0, TAU, 12, Palette.c("text_dim", 0.6), 1.3)
				x += 13.0
			x = _text(x + 2.0, y, "%d/%d" % [st, n], 15)
			var eta := str(info["eta"])
			if eta != "" and not bool(info["over"]):
				_text(x + 10.0, y, eta, 13, "text_dim")
			# under the meter: the rule for the break's first seconds, and the lapse count once there is one
			y += 22.0
			var nl := int(info["lapses"])
			var tx := x0
			if bool(info["rule_on"]):
				tx = _text(x0, y, str(info["rule"]), 13, "text") + 18.0
			if nl > 0:
				_text(tx, y, BossLogic.lapse_text(nl, int(info["lapse_lost"])), 13, "danger" if hi > 0 else "text_dim")
		y += 28.0
		_label(x0, y, "BACKUPS")
		var px := col2 + 8.0
		for i in int(info["phyl_left"]):
			_pip(Vector2(px, y - 5.0), 6.5, Palette.c("relish"), true, true)
			px += 18.0
		for i in int(info["clones_left"]):
			_pip(Vector2(px, y - 5.0), 6.0, Palette.c("relish"), true, false)
			px += 18.0
		var spent := int(info["spent_phyl"]) + int(info["spent_clones"])
		for i in spent:
			_cracked(Vector2(px, y - 5.0), 6.5, i)
			px += 18.0
		var left := int(info["phyl_left"]) + int(info["clones_left"])
		_text(px + 4.0, y, "%d left%s" % [left, "" if spent == 0 else " · %d cracked" % spent], 15,
			"text" if left > 0 else "danger")
