extends VBoxContainer
## Crypt tab (MECHANICS §4.6): the slab, where Relish raises big undead, and the roster where they
## are placed. Built once; bind() (≈4×/s) updates it in place, so a held raise, hovers and focus
## survive. Rules come from SlabLogic and CryptLogic; this file only lays them out.
##   gate      Relish's state in words (view_relish); the slab works only while she's home
##   husks     view_inventory().husks as buttons ("Hulk · muscle 3 · nerve 1"); one goes on the slab
##   preview   creature_preview.gd: the live line morph, the runes, the hold ring, the set piece
##   verdict   the Adjective-Noun name, the role line, all five stats with what each one helps
##   remnants  click to slot (it lands where SlabLogic would put it), click again or click its rune
##             to take it off; one that fits no free slot is disabled with the reason
##   hold      hold the button, or Space on this tab, for slab.raise_hold_s; releasing early cancels
##   naming    inline "Name your new friend?", then cmd_raise_big_undead(husk, slot order, name)
##   roster    every big undead: name (rename inline), kind, role, all five stats, its place in words;
##             Crypt, Party, Foreman at…, Siege… (cmd_place_big_undead, cmd_set_party), refusals in words
## The raise is still a stub until E3 (ok, uid ""): the set piece plays, nothing is consumed, and the
## panel says the raise lands with E2/E3.

signal command_issued
## Sound and set-piece hooks for the shell (TownSynth, the town view's slab echo): the hold began, was let
## go early, the raise was kept (the collapse starts), the rings landed on the creature's outline.
signal hold_started
signal hold_stopped
signal raise_started
signal raise_landed

const PreviewScript := preload("res://scripts/town/creature_preview.gd")

var _t: Dictionary = {}     # town.json view.crypt
var _slab: Dictionary = {}  # town.json slab
var _bv: Dictionary = {}    # buildings_view (building labels)
var _views: Dictionary = {}
var _board := CryptLogic.board()
var _rems: Dictionary = {}
var _ev: Dictionary = {}
var _home := false
var _block := ""
var _held_s := 0.0
var _holding := false
var _hold_by_key := false
var _formed := false
var _formed_sig := ""
var _raising := false
var _auto_t := -1.0  # debug --town-raise: seconds until it starts; -1 = off
var _raised_name := ""
var _raised_ev: Dictionary = {}  # the verdict the set piece shows (the board may empty under it)
var _preset: Dictionary = {}  # debug --town-slab: {husk, remnants}, applied on the first bind that has them

var _gate: Label
var _slab_box: VBoxContainer
var _husk_row: HFlowContainer
var _husk_none: Label
var _husk_btns: Dictionary = {}  # uid -> Button
var _husk_sig := ""
var _preview: Control
var _name: Label
var _role: Label
var _stat_cells: Array = []  # per stat [mark, name, value, helps]
var _hold_btn: Button
var _hold_why: Label
var _prompt: VBoxContainer
var _name_edit: LineEdit
var _prompt_why: Label
var _status: Label
var _rem_head: Label
var _rem_grid: GridContainer
var _rem_cells: Dictionary = {}  # uid -> {btn, why}
var _rem_sig := ""
var _roster_head: Label
var _no_big: Label
var _roster: VBoxContainer
var _rows: Dictionary = {}  # uid -> row nodes


func _ready() -> void:
	_t = ConfigDb.v("town", "view", {}).get("crypt", {})
	_slab = ConfigDb.data.get("town", {}).get("slab", {})
	_bv = ConfigDb.data.get("buildings_view", {})
	add_theme_constant_override("separation", 6)
	_gate = _wrap("", _px("text_px"))
	add_child(_gate)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	scroll.add_child(col)
	_build_slab(col)
	_roster_head = TownUI.label("", _px("roster_name_px"))
	col.add_child(_roster_head)
	_no_big = TownUI.label(String(_t.get("no_big", "")), _px("text_px"), "text_dim")
	col.add_child(_no_big)
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 6)
	col.add_child(_roster)


func _px(key: String) -> int:
	return maxi(int(_t.get(key, TownUI.MIN_TEXT)), TownUI.MIN_TEXT)


func _tx(key: String) -> String:
	return String(_t.get(key, key))


func _wrap(text: String, size: int, key := "text") -> Label:
	var l := TownUI.label(text, size, key)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _build_slab(col: VBoxContainer) -> void:
	_slab_box = VBoxContainer.new()
	_slab_box.add_theme_constant_override("separation", 4)
	col.add_child(_slab_box)
	_husk_row = HFlowContainer.new()
	_husk_row.add_theme_constant_override("h_separation", 6)
	_husk_row.add_theme_constant_override("v_separation", 4)
	_slab_box.add_child(_husk_row)
	_husk_row.add_child(TownUI.label(_tx("husks"), _px("text_px"), "text_dim"))
	_husk_none = TownUI.label(_tx("no_husks"), _px("text_px"), "text_dim")
	_husk_row.add_child(_husk_none)

	_preview = PreviewScript.new()
	_preview.setup(_t, _slab)
	_preview.rune_clicked.connect(_on_rune)
	_preview.raise_finished.connect(_on_raise_finished)
	_preview.collapsed.connect(raise_landed.emit)
	_slab_box.add_child(_preview)

	_name = TownUI.label("", _px("name_px"))
	_name.add_theme_font_override("font", TownUI.bold_font())
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slab_box.add_child(_name)
	_role = _wrap("", _px("role_px"))
	_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slab_box.add_child(_role)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 0)
	_slab_box.add_child(grid)
	for s in SlabLogic.STATS:
		var cells: Array = []
		for j in 4:
			var l := TownUI.label("", _px("stat_px"), "text" if j < 3 else "text_dim")
			if j == 2:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if j == 3:
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			grid.add_child(l)
			cells.append(l)
		_stat_cells.append(cells)

	var hold_row := HBoxContainer.new()
	hold_row.add_theme_constant_override("separation", 8)
	_slab_box.add_child(hold_row)
	_hold_btn = TownUI.button(_tx("hold"))
	_hold_btn.focus_mode = Control.FOCUS_NONE  # Space is the panel's hold key, never ui_accept
	_hold_btn.custom_minimum_size = Vector2(240, TownUI.MIN_TARGET)
	_hold_btn.button_down.connect(_hold_press.bind(false))
	_hold_btn.button_up.connect(_hold_release.bind(false))
	_hold_btn.mouse_exited.connect(func():
		if _holding and not _hold_by_key:
			_hold_release(false))
	hold_row.add_child(_hold_btn)
	_hold_why = _wrap("", _px("small_px"), "text_dim")
	hold_row.add_child(_hold_why)

	_prompt = VBoxContainer.new()
	_prompt.add_theme_constant_override("separation", 4)
	_prompt.visible = false
	_slab_box.add_child(_prompt)
	_prompt.add_child(TownUI.label(_tx("prompt"), _px("roster_name_px"), "text"))
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 6)
	_prompt.add_child(prow)
	_name_edit = _line_edit()
	_name_edit.text_submitted.connect(func(_s): _on_keep())
	prow.add_child(_name_edit)
	var keep := TownUI.button(_tx("keep"))
	keep.pressed.connect(_on_keep)
	prow.add_child(keep)
	var sug := TownUI.button(_tx("suggest"))
	sug.pressed.connect(_on_suggest)
	prow.add_child(sug)
	_prompt_why = TownUI.label("", _px("small_px"), "select")
	_prompt.add_child(_prompt_why)

	_status = _wrap("", _px("text_px"), "select")
	_slab_box.add_child(_status)
	_rem_head = _wrap(_tx("remnants"), _px("small_px"), "text_dim")
	_slab_box.add_child(_rem_head)
	_rem_grid = GridContainer.new()
	_rem_grid.columns = 2
	_rem_grid.add_theme_constant_override("h_separation", 8)
	_rem_grid.add_theme_constant_override("v_separation", 4)
	_slab_box.add_child(_rem_grid)


func _line_edit() -> LineEdit:
	var e := LineEdit.new()
	e.max_length = CryptLogic.NAME_MAX + 8  # room to type past the limit; check_name says why
	e.custom_minimum_size = Vector2(0, TownUI.MIN_TARGET)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", _px("text_px"))
	e.add_theme_color_override("font_color", Palette.c("text"))
	e.add_theme_color_override("caret_color", Palette.c("select"))
	e.add_theme_stylebox_override("normal", TownUI.button_box("normal"))
	e.add_theme_stylebox_override("focus", TownUI.button_box("pressed"))
	return e


# ------------------------------------------------------------------ bind ----
func bind(views: Dictionary) -> void:
	if _gate == null:
		return
	_views = views
	var relish: Dictionary = views.get("relish", {})
	_home = String(relish.get("state", "")) == "home"
	var gate := CryptLogic.gate_text(relish, views.get("fort_names", {}), _t)
	if not _home:
		gate += " " + String(_t.get("gate", {}).get("roster_note", ""))
	_gate.text = gate
	var inv: Dictionary = views.get("inventory", {})
	_rems = CryptLogic.by_uid(inv.get("remnants", []))
	_sync_husks(inv.get("husks", []))
	_sync_remnants(inv.get("remnants", []))
	_board = CryptLogic.reconcile(_board, inv)
	_apply_preset(inv)
	_refresh_slab()
	_sync_roster()


## Debug (`--town-slab=h1:r2,r3`, from the shell): this husk and these remnants on the slab, once
## the inventory has them.
func debug_preset(husk_uid: String, remnant_uids: Array) -> void:
	_preset = {"husk": husk_uid, "remnants": remnant_uids}


## Debug `--town-raise`: after `delay_s` it holds the raise on the slab and keeps the suggested name, the
## real path (_hold_press, _on_suggest), so the set piece can be screenshotted. Needs a creature on the slab
## (`--town-slab`); waits until there is one.
func debug_autoraise(delay_s: float) -> void:
	_auto_t = maxf(delay_s, 0.0)


func _auto_raise(delta: float) -> void:
	if _auto_t > 0.0:
		_auto_t = maxf(_auto_t - delta, 0.0)  # stays at 0 while it waits for a creature to hold
		return
	if not is_visible_in_tree():
		return
	if _formed and _prompt.visible:
		_auto_t = -1.0
		_on_suggest()
	elif not _holding and not _formed and not _raising and _block == "" and String(_board.get("husk", "")) != "":
		_hold_press(false)


func _apply_preset(inv: Dictionary) -> void:
	if _preset.is_empty():
		return
	for h in inv.get("husks", []):
		if String(h.get("uid", "")) == String(_preset["husk"]):
			_board = CryptLogic.board(String(h["uid"]), String(h.get("kind", "")))
			for u in _preset["remnants"]:
				var c := CryptLogic.click_remnant(_board, String(u), _rems, _slab)
				if not c["ok"]:
					printerr("Crypt: --town-slab remnant %s refused (%s)" % [u, c["reason"]])
				_board = c["board"]
			_preset = {}
			return


func _sync_husks(husks: Array) -> void:
	var sig := ",".join(husks.map(func(h): return "%s:%s" % [h.get("uid", ""), h.get("kind", "")]))
	if sig != _husk_sig:
		_husk_sig = sig
		for b in _husk_btns.values():
			_husk_row.remove_child(b)
			b.queue_free()
		_husk_btns = {}
		for h in husks:
			var uid := String(h.get("uid", ""))
			var b := TownUI.button(CryptLogic.husk_label(String(h.get("kind", "")), _slab, _tx("sep")))
			b.custom_minimum_size = Vector2(0, TownUI.MIN_TARGET)
			b.pressed.connect(_on_husk.bind(uid, String(h.get("kind", ""))))
			_husk_row.add_child(b)
			_husk_btns[uid] = b
	_husk_none.visible = husks.is_empty()


func _sync_remnants(remnants: Array) -> void:
	var sig := ",".join(remnants.map(func(r): return CryptLogic.remnant_label(r) + "#" + String(r.get("uid", ""))))
	if sig == _rem_sig:
		return
	_rem_sig = sig
	TownUI.clear(_rem_grid)
	_rem_cells = {}
	for r in remnants:
		var uid := String(r.get("uid", ""))
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := TownUI.button(CryptLogic.remnant_label(r, _tx("sep")))
		b.pressed.connect(_on_remnant.bind(uid))
		cell.add_child(b)
		var why := TownUI.label("", _px("small_px"), "text_dim")
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cell.add_child(why)
		_rem_grid.add_child(cell)
		_rem_cells[uid] = {"btn": b, "why": why}
	_rem_head.text = _tx("remnants") if not remnants.is_empty() else _tx("no_remnants")


# ------------------------------------------------------------------ slab ----
## Re-evaluates the board (SlabLogic, via CryptLogic) and updates every slab node in place.
func _refresh_slab() -> void:
	_slab_box.visible = _home
	var kind := String(_board.get("kind", ""))
	var has_husk := String(_board.get("husk", "")) != ""
	_ev = CryptLogic.evaluate(_board, _rems, _slab) if has_husk else {}
	var runes: Array = []
	if has_husk:
		var groups := SlabLogic.slots_for(kind, _slab)
		var su := CryptLogic.slot_uids(_board, _rems, _slab)
		for j in groups.size():
			var r: Dictionary = _rems.get(su[j], {}) if j < su.size() else {}
			runes.append({"group": groups[j], "aspect": String(r.get("aspect", "")), "mag": int(r.get("magnitude", 0))})
	_preview.awake = _home
	_preview.show_build(kind, _ev, runes)

	var shown: Dictionary = _raised_ev if _raising else _ev
	if _raising:
		_name.text = _raised_name
	else:
		_name.text = String(_ev.get("name", "")) if has_husk else ""
	_name.visible = _name.text != ""
	_role.text = String(shown.get("role_line", "")) if has_husk or _raising else ""
	_role.visible = _role.text != ""
	var rows := CryptLogic.stat_rows(shown.get("stats", {}), String(shown.get("dominant", "")), _slab, _t)
	for i in rows.size():
		var cells: Array = _stat_cells[i]
		var dom: bool = rows[i]["dominant"]
		(cells[0] as Label).text = _tx("dominant_mark") if dom else ""
		(cells[1] as Label).text = String(rows[i]["stat"])
		(cells[2] as Label).text = "%s %s" % [String(rows[i]["text"]), _tx("arrow")]
		(cells[3] as Label).text = String(rows[i]["helps"])
		for j in 3:
			if dom:
				(cells[j] as Label).add_theme_font_override("font", TownUI.bold_font())
			else:
				(cells[j] as Label).remove_theme_font_override("font")
		(cells[3] as Label).add_theme_color_override("font_color", Palette.c("text" if dom else "text_dim"))

	for uid in _husk_btns:
		var on: bool = uid == String(_board.get("husk", ""))
		(_husk_btns[uid] as Button).add_theme_stylebox_override("normal", TownUI.button_box("active" if on else "normal"))
	for uid in _rem_cells:
		var cell: Dictionary = _rem_cells[uid]
		var on_slab: bool = uid in _board.get("order", [])
		var why := CryptLogic.refusal(_board, uid, _rems, _slab)
		var b: Button = cell["btn"]
		b.disabled = (why != "" and not on_slab) or _raising
		b.add_theme_stylebox_override("normal", TownUI.button_box("active" if on_slab else "normal"))
		(cell["why"] as Label).text = CryptLogic.refusal_text(_board, uid, _rems, _slab, _t) if has_husk else ""

	var count := int(_views.get("big_undead", {}).get("count", 0))
	var cap := int(_views.get("big_undead", {}).get("cap", 0))
	_block = String(_t.get("block", {}).get("raising", "")) if _raising else \
		CryptLogic.raise_block(_board, _ev, _home, count, cap, _slab, _t)
	if _holding and _block != "":
		_cancel_hold()
	if _formed and (_block != "" or _sig() != _formed_sig):
		_close_prompt()
	_hold_btn.disabled = _block != "" or _formed
	_hold_btn.text = _tx("holding") if _holding else _tx("hold")
	_say(_hold_why, _block)
	_say(_status, _status.text)
	_preview.formed = _formed


## Sets a label's text and hides it while empty (an empty label still takes a line).
func _say(l: Label, text: String) -> void:
	l.text = text
	l.visible = text != ""


func _sig() -> String:
	return "%s|%s" % [_board.get("husk", ""), ",".join(CryptLogic.slot_order(_board, _rems, _slab))]


func _on_husk(uid: String, kind: String) -> void:
	if _raising:
		return
	if uid == String(_board.get("husk", "")):
		_board = CryptLogic.board()  # clicking the husk on the slab takes it off
	else:
		_board = CryptLogic.board(uid, kind)
	_board_changed()


func _on_remnant(uid: String) -> void:
	if _raising:
		return
	_board = CryptLogic.click_remnant(_board, uid, _rems, _slab)["board"]
	_board_changed()


func _on_rune(i: int) -> void:
	if _raising or not _home:
		return
	var c := CryptLogic.click_slot(_board, i, _rems, _slab)
	if String(c["uid"]) == "":
		return
	_board = c["board"]
	_board_changed()


## A different creature on the slab: a hold in progress starts over (the prompt closes on its own).
func _board_changed() -> void:
	if _holding:
		_cancel_hold()
	_say(_status, "")
	_refresh_slab()


# ------------------------------------------------------------------ hold ----
func _hold_press(by_key: bool) -> void:
	if _holding or _formed or _block != "":
		return
	_holding = true
	_hold_by_key = by_key
	_held_s = 0.0
	_say(_status, "")
	_refresh_slab()
	hold_started.emit()


func _hold_release(by_key: bool) -> void:
	if _holding and by_key == _hold_by_key:
		_cancel_hold()
	elif _formed and not _holding:
		_name_edit.grab_focus.call_deferred()  # the hold's own key and click are done; now type a name
		_name_edit.select_all.call_deferred()


func _cancel_hold() -> void:
	if _holding:
		hold_stopped.emit()
	_holding = false
	_held_s = 0.0
	_preview.hold = 0.0
	_hold_btn.text = _tx("hold")


func _process(delta: float) -> void:
	if _auto_t >= 0.0:
		_auto_raise(delta)
	if not _holding:
		return
	if not is_visible_in_tree():  # the tab was switched mid-hold: its release can't reach us
		_cancel_hold()
		return
	var hold_s := float(_slab.get("raise_hold_s", 1.0))
	_held_s = CryptLogic.hold_step(_held_s, true, delta, hold_s)
	_preview.hold = CryptLogic.hold_progress(_held_s, hold_s)
	if _held_s >= hold_s:
		_holding = false
		_formed = true
		_formed_sig = _sig()
		_preview.hold = 1.0
		_name_edit.text = String(_ev.get("name", ""))
		_say(_prompt_why, "")
		_prompt.visible = true
		_refresh_slab()


## Space on this tab holds the raise (not while a name field has focus). Space is always the
## tab's: it never also presses whatever button was clicked last.
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or (k.keycode != KEY_SPACE and k.physical_keycode != KEY_SPACE) or not is_visible_in_tree():
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	get_viewport().set_input_as_handled()
	if k.echo:
		return
	if k.pressed:
		_hold_press(true)
	else:
		_hold_release(true)


func _close_prompt() -> void:
	_formed = false
	_formed_sig = ""
	_prompt.visible = false
	_preview.formed = false
	_preview.hold = 0.0
	if _name_edit.has_focus():
		_name_edit.release_focus()


func _on_suggest() -> void:
	_name_edit.text = String(_ev.get("name", ""))
	_on_keep()


func _on_keep() -> void:
	if not _formed:
		return
	var chk := CryptLogic.check_name(_name_edit.text)
	if not chk["ok"]:
		_say(_prompt_why, _tx("bad_name"))
		return
	var r: Dictionary = Game.state.cmd_raise_big_undead(String(_board["husk"]), CryptLogic.slot_order(_board, _rems, _slab), chk["name"])
	command_issued.emit()
	var why := _reason(String(r.get("reason", "")))
	if not bool(r.get("ok", false)):
		if String(r.get("reason", "")) == "bad_name":
			_say(_prompt_why, why)
			return
		_close_prompt()
		_say(_status, _tx("refused").format({"why": why}))
		_refresh_slab()
		return
	_close_prompt()
	var uid := String(r.get("big_undead", {}).get("uid", ""))
	_say(_status, _tx("risen" if uid != "" else "risen_stub").format({"name": chk["name"]}))
	_raising = true
	_raised_name = chk["name"]
	_raised_ev = _ev.duplicate(true)
	_preview.play_raise()
	_refresh_slab()
	raise_started.emit()


func _on_raise_finished() -> void:
	_raising = false
	_raised_name = ""
	_raised_ev = {}
	_board = CryptLogic.board()  # the husk and its remnants went into the creature
	_refresh_slab()


func _reason(id: String) -> String:
	var rs: Dictionary = _t.get("reasons", {})
	return String(rs.get(id, rs.get("_unknown", id)))


# ---------------------------------------------------------------- roster ----
func _sync_roster() -> void:
	var bu: Dictionary = _views.get("big_undead", {})
	var list: Array = bu.get("big_undead", [])
	_roster_head.text = _tx("roster").format({"count": int(bu.get("count", 0)), "cap": int(bu.get("cap", 0))})
	_no_big.visible = list.is_empty()
	var seen := {}
	for i in list.size():
		var e: Dictionary = list[i]
		var uid := String(e.get("uid", ""))
		seen[uid] = true
		if not _rows.has(uid):
			_rows[uid] = _make_row(uid)
		var row: Dictionary = _rows[uid]
		if (row["box"] as Control).get_index() != i:
			_roster.move_child(row["box"], i)
		_update_row(row, e)
	for uid in _rows.keys():
		if not seen.has(uid):
			(_rows[uid]["box"] as Node).queue_free()
			_rows.erase(uid)


func _make_row(uid: String) -> Dictionary:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", TownUI.panel_box())
	_roster.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	box.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var nm := TownUI.label("", _px("roster_name_px"))
	nm.add_theme_font_override("font", TownUI.bold_font())
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var ren := TownUI.button(_tx("rename"))
	head.add_child(ren)
	var edit_row := HBoxContainer.new()
	edit_row.add_theme_constant_override("separation", 6)
	edit_row.visible = false
	col.add_child(edit_row)
	var edit := _line_edit()
	edit_row.add_child(edit)
	var save := TownUI.button(_tx("save"))
	edit_row.add_child(save)
	var info := _wrap("", _px("text_px"))
	col.add_child(info)
	var stats := _wrap("", _px("text_px"))
	col.add_child(stats)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	col.add_child(btns)
	var row := {"box": box, "name": nm, "edit_row": edit_row, "edit": edit, "info": info, "stats": stats,
		"mode": "", "opts_sig": "", "uid": uid}
	for pair in [["crypt", "to_crypt"], ["party", "to_party"], ["foreman", "to_foreman"], ["siege", "to_siege"]]:
		var b := TownUI.button(_tx(pair[1]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_place_btn.bind(uid, pair[0]))
		btns.add_child(b)
		row[pair[0]] = b
	var opts := HFlowContainer.new()
	opts.add_theme_constant_override("h_separation", 6)
	opts.add_theme_constant_override("v_separation", 4)
	opts.visible = false
	col.add_child(opts)
	row["opts"] = opts
	var status := _wrap("", _px("small_px"), "select")
	status.visible = false
	col.add_child(status)
	row["status"] = status
	ren.pressed.connect(func():
		edit_row.visible = not edit_row.visible
		if edit_row.visible:
			edit.text = String(row.get("name_now", ""))
			edit.grab_focus()
			edit.select_all())
	save.pressed.connect(_on_rename.bind(uid))
	edit.text_submitted.connect(func(_s): _on_rename(uid))
	return row


func _update_row(row: Dictionary, e: Dictionary) -> void:
	var nm := String(e.get("name", ""))
	row["name_now"] = nm
	(row["name"] as Label).text = nm
	var kind := String(e.get("kind", ""))
	var place := String(e.get("place", ""))
	row["place"] = place
	var town: Dictionary = _views.get("town", {})
	var labels := _labels()
	var parts: Array = [String(_slab.get("nouns", {}).get(kind, kind.capitalize())), SlabLogic.role_label(String(e.get("role", "")), _slab),
		CryptLogic.place_text(place, CryptLogic.lot_labels(town.get("buildings", []), labels), _views.get("fort_names", {}), _t)]
	(row["info"] as Label).text = _tx("sep").join(parts)
	var st: Array = []
	for s in SlabLogic.STATS:
		st.append("%s %s" % [s, CryptLogic.fmt_stat(float(e.get("stats", {}).get(s, 0.0)))])
	(row["stats"] as Label).text = _tx("sep").join(st)
	var active := {"crypt": place == "crypt", "party": place == "party", "foreman": place.begins_with("town:"),
		"siege": place.begins_with("fort:")}
	for k in active:
		var b: Button = row[k]
		b.add_theme_stylebox_override("normal", TownUI.button_box("active" if active[k] or row["mode"] == k else "normal"))
	if row["mode"] != "":
		_fill_options(row)


func _labels() -> Dictionary:
	var out := {}
	for bid in _bv:
		out[bid] = String(_bv[bid].get("label", bid))
	return out


func _on_place_btn(uid: String, what: String) -> void:
	if not _rows.has(uid):
		return
	var row: Dictionary = _rows[uid]
	_say(row["status"], "")
	match what:
		"crypt":
			_place(uid, "crypt")
		"party":
			if String(row.get("place", "")) == "party":
				return
			var uids: Array = []
			for p in _views.get("party", {}).get("party", []):
				uids.append(String(p.get("uid", "")))
			uids.append(uid)
			var r: Dictionary = Game.state.cmd_set_party(uids)
			_after_place(uid, r)
		"foreman", "siege":
			row["mode"] = "" if row["mode"] == what else what
			row["opts_sig"] = ""
			(row["opts"] as Control).visible = row["mode"] != ""
			if row["mode"] != "":
				_fill_options(row)
			for k in ["foreman", "siege"]:
				(row[k] as Button).add_theme_stylebox_override("normal", TownUI.button_box(
					"active" if row["mode"] == k or (k == "foreman" and String(row["place"]).begins_with("town:"))
					or (k == "siege" and String(row["place"]).begins_with("fort:")) else "normal"))


## The open chooser's buttons: built lots with jobs (Foreman at…) or forts, held first (Siege…).
## Rebuilt only when the choices change.
func _fill_options(row: Dictionary) -> void:
	var uid := String(row["uid"])
	var opts: Array = []  # [text, place, disabled, active]
	if row["mode"] == "foreman":
		var names := {}
		for e in _views.get("big_undead", {}).get("big_undead", []):
			names[String(e.get("uid", ""))] = String(e.get("name", ""))
		for l in CryptLogic.foreman_lots(_views.get("town", {}).get("buildings", []), _labels()):
			var fm := String(l["foreman"])
			var taken := fm != "" and fm != uid
			var text := _tx("taken").format({"label": l["label"], "name": names.get(fm, fm)}) if taken else \
				_tx("lot_option").format({"label": l["label"], "lot": l["lot_id"]})
			opts.append([text, "town:" + String(l["lot_id"]), taken, fm == uid and fm != ""])
	else:
		for f in CryptLogic.siege_forts(_views.get("forts", [])):
			var text := String(f.get("name", ""))
			if bool(f.get("held", false)):
				text += _tx("sep") + _tx("held")
			opts.append([text, "fort:" + String(f.get("id", "")), false, String(row["place"]) == "fort:" + String(f.get("id", ""))])
	var sig := str(opts)
	if sig == row["opts_sig"]:
		return
	row["opts_sig"] = sig
	var box: HFlowContainer = row["opts"]
	TownUI.clear(box)
	if opts.is_empty():
		box.add_child(TownUI.label(_tx("no_lots" if row["mode"] == "foreman" else "no_forts"), _px("small_px"), "text_dim"))
	for o in opts:
		var b := TownUI.button(String(o[0]))
		b.disabled = o[2]
		if o[3]:
			b.add_theme_stylebox_override("normal", TownUI.button_box("active"))
		b.pressed.connect(_place.bind(uid, String(o[1])))
		box.add_child(b)


func _place(uid: String, place: String) -> void:
	_after_place(uid, Game.state.cmd_place_big_undead(uid, place))


func _after_place(uid: String, r: Dictionary) -> void:
	command_issued.emit()
	if not _rows.has(uid):
		return
	var row: Dictionary = _rows[uid]
	if bool(r.get("ok", false)):
		_say(row["status"], "")
		row["mode"] = ""
		(row["opts"] as Control).visible = false
	else:
		_say(row["status"], _tx("refused").format({"why": _reason(String(r.get("reason", "")))}))


func _on_rename(uid: String) -> void:
	if not _rows.has(uid):
		return
	var row: Dictionary = _rows[uid]
	var r: Dictionary = Game.state.cmd_rename_big_undead(uid, (row["edit"] as LineEdit).text)
	command_issued.emit()
	if bool(r.get("ok", false)):
		_say(row["status"], "")
		(row["edit_row"] as Control).visible = false
		(row["edit"] as LineEdit).release_focus()
	else:
		_say(row["status"], _tx("refused").format({"why": _reason(String(r.get("reason", "")))}))


func on_game_event(_ev_in: Dictionary) -> void:
	pass
