extends ScrollContainer
## Build tab: the catalog (cost, can_build and why, benefit, tier gate) sorted by the current
## need, placement on a lot, the lot inspector (upgrade, cancel, demolish) and the build queue
## (stand-in until E2). Everything it shows comes from the fetched views; enable/disable is driven by
## view_catalog (`can_build`, `reason`, `lots`) and view_town, never by a command's ok. Rows, the
## inspector and the queue's rows are built once and updated in place on every bind (the shell
## binds about 4x a second), so hover, focus and held buttons survive.
## Logic is pure in BuildSort / TownStandins.BuildQueue; text and tuning live in town.json `view`.
## The same data also drives the lot card in the town view (attach_card): an empty lot's card lists
## what fits it, a built lot's card reuses this tab's inspector widgets and commands. The panel also
## feeds the view its hover outline, the day-1 suggestion, the queue's ghosts and the build flash.
## When relics hold the tier back, a row pinned at the top says so, with a To the realm button (the
## shell's own exit). Under the catalog the Queue lists each entry with its status and an ETA.

signal command_issued
## Ask the town view to outline `lots` for `building_id` (and dim the rest); "" ends placement.
signal placement_changed(building_id: String, lots: Array)
## The inspected lot ("" = none), for the town view's dashed outline.
signal lot_selected(lot_id: String)
## The lot card opens beside `lot_id` / closes (the card's content is filled here).
signal card_opened(lot_id: String)
signal card_closed
## The lots a hovered catalog row (panel or card) fits; [] for none.
signal hover_lots(lots: Array)
## The day-1 suggestion for the canvas: {building_id, label, lots}, {} when hidden.
signal suggestion_changed(sug: Dictionary)
## The stand-in queue as BuildSort.ghosts(), for the canvas.
signal queue_changed(ghosts: Array)
## cmd_build / cmd_upgrade returned ok on this lot: the canvas flashes it on the next beat.
signal build_started(lot_id: String)
## The relic pin's To the realm: the shell leaves through its one exit (finished, once).
signal to_realm

var _views := {}
var _vcfg: Dictionary = {}
var _bview: Dictionary = {}
var _bcfg: Dictionary = {}
var _st := {}
var _ctx := {}

var _root: VBoxContainer
var _status: Label
var _banner: PanelContainer
var _banner_label: Label
var _rows_box: VBoxContainer
var _empty: Label
var _rows := {}  # building_id -> widgets
var _shape := ""
var _style_row: StyleBoxFlat
var _style_focus: StyleBoxFlat

var _placing := ""
var _placing_lots: Array = []
var _focus := ""
var _selected_lot := ""
var _armed_s := 0.0  # > 0 while Demolish waits for its confirming click

var _sorted: Array = []  # BuildSort.sort_rows() of the current catalog
var _card: Control  # the lot card (town_card.gd), a child of the town view
var _card_lot := ""
var _card_mode := ""  # "catalog" (an empty lot) | "inspect" (a built lot)
var _insp_card := {}  # the card's own inspector widgets
var _reserved := {}  # BuildSort.reserved_lots(): {lot id: gate building} kept free for the next tier
var _sug_data := {}  # BuildSort.suggest(): the top buildable row
var _sug_off := false  # the player dismissed the suggestion (kept for the scene's lifetime)
var _sug_bid := ""  # the suggested building while the suggestion is live
var _last_sug := {}
var _hover_bid := ""
var _card_hover := ""
var _last_hover: Array = []
var _last_ghosts: Array = []
var _seed := ""  # --town-queue=house:lot-05,... (debug): queue entries seeded on the first bind

var _insp := {}
var _q: TownStandins.BuildQueue  # TODO(api-request #3): swap for view_town().queue + the queue commands
var _q_title: Label
var _q_empty: Label
var _q_box: VBoxContainer
var _q_pool: Array = []
var _cap_box: HBoxContainer
var _cap_label: Label
var _cap_btn: Button
var _cap_building := ""
var _tp: BuildSort.Throughput  # the build throughput, measured from the views between binds
var _pin: PanelContainer
var _pin_label: Label
var _scroll_q_s := 0.0  # debug --town-queue: seconds the tab keeps the Queue (its last section) in view


func _ready() -> void:
	_vcfg = ConfigDb.v("town", "view", {})
	_bview = ConfigDb.data.get("buildings_view", {})
	_bcfg = ConfigDb.data.get("buildings", {})
	_q = TownStandins.BuildQueue.new(int(_vcfg.get("queue_max", 8)), _vcfg.get("cap_buildings", {}))
	_tp = BuildSort.Throughput.new(float(_vcfg.get("queue_text", {}).get("throughput_smooth_s", 10.0)))
	_style_row = TownUI.panel_box()
	_style_focus = TownUI.panel_box()
	_style_focus.border_color = Palette.c("select")
	_style_focus.set_border_width_all(2)
	if Game.state.debug_enabled:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--town-queue="):
				_seed = arg.trim_prefix("--town-queue=")
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 6)
	add_child(_root)
	_build_pin()
	_status = _wrap("", 14, "text")
	_root.add_child(_status)
	_build_banner()
	_build_inspector()
	var h := TownUI.label("Catalog", 16)
	_root.add_child(h)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 4)
	_root.add_child(_rows_box)
	_empty = _wrap("No buildings.", 14, "text_dim")
	_root.add_child(_empty)
	_build_queue_section()
	visibility_changed.connect(func(): if not is_visible_in_tree(): cancel_placement())


## The lot card the town view hosts: this tab fills it and handles its buttons.
func attach_card(card: Control) -> void:
	_card = card
	_insp_card = _make_inspector(_style_row)
	card.insp_host.add_child(_insp_card["node"])
	card.build_pressed.connect(_on_card_build)
	card.queue_pressed.connect(_on_card_queue)
	card.close_pressed.connect(dismiss)
	card.hover_building.connect(func(bid: String): _card_hover = bid; _emit_hover())


func _wrap(text: String, size := 14, key := "text") -> Label:
	var l := TownUI.label(text, size, key)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(40, 0)
	return l


func _btn(text: String, w := 76.0) -> Button:
	var b := TownUI.button(text)
	b.custom_minimum_size = Vector2(w, TownUI.MIN_TARGET)
	return b


## The relic pin: "Gated by relics: ... Relics come from dungeons." and To the realm (>= 44 px).
func _build_pin() -> void:
	_pin = PanelContainer.new()
	var sb := TownUI.panel_box()
	sb.border_color = Palette.c("select")
	sb.set_border_width_all(2)
	_pin.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_pin.add_child(row)
	_pin_label = _wrap("", 14, "text")
	row.add_child(_pin_label)
	var go := _btn(String(_vcfg.get("relic_gate", {}).get("button", "")), 130.0)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func(): to_realm.emit())
	row.add_child(go)
	_pin.visible = false
	_root.add_child(_pin)


func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", _style_focus)
	var row := HBoxContainer.new()
	_banner.add_child(row)
	_banner_label = _wrap("", 14, "select")
	row.add_child(_banner_label)
	var c := _btn("Cancel")
	c.pressed.connect(cancel_placement)
	row.add_child(c)
	_banner.visible = false
	_root.add_child(_banner)


# ------------------------------------------------------------------ bind ----
func bind(views: Dictionary) -> void:
	_views = views
	_st = BuildSort.stocks(views)
	_ctx = BuildSort.queue_context(views, _bcfg, _vcfg)
	if TownStandins.queue_is_standin(views.get("town", {})):
		_seed_queue()
		_q.evaluate(_ctx)
	var rows: Array = views.get("catalog", {}).get("buildings", [])
	var shape := ",".join(rows.map(func(r): return String(r.get("building_id", ""))))
	if shape != _shape:
		_shape = shape
		_rebuild_rows(rows)
	_empty.visible = rows.is_empty()
	var names: Dictionary = views.get("fort_names", {})
	var sorted := BuildSort.sort_rows(rows, BuildSort.needs(views, names, _vcfg, _bview, _bcfg), _bview, _vcfg)
	_sorted = sorted
	_tp.observe(views)
	var gate := BuildSort.relic_gate(views, sorted, _st, _bview, _vcfg)
	_pin.visible = not gate.is_empty()
	_pin_label.text = String(gate.get("text", ""))
	var ups := BuildSort.upgrade_items(views, BuildSort.needs(views, names, _vcfg, _bview, _bcfg), _bview, _bcfg, _vcfg)
	_reserved = BuildSort.reserved_lots(views, _bcfg)
	_sug_data = BuildSort.suggest(sorted, _bview, _st, _vcfg, ups, _reserved)
	_sug_bid = "" if _sug_off else String(_sug_data.get("building_id", ""))
	var listed := {}
	for i in sorted.size():
		var bid := String(sorted[i]["row"]["building_id"])
		var w: Dictionary = _rows[bid]
		listed[bid] = true
		w["node"].visible = true
		if w["node"].get_index() != i:
			_rows_box.move_child(w["node"], i)
		_update_row(sorted[i], w)
	for bid in _rows:
		if not listed.has(bid):  # a built unique building is never offered again
			_rows[bid]["node"].visible = false
	_check_placement()
	_update_inspector()
	_update_queue()
	_update_card()
	_push_suggestion()


## Debug `--town-queue=house:lot-05,inn:lot-06`: puts these into the stand-in queue once, bypassing the
## gate check so a gated and a funds-blocked entry can show on the canvas.
func _seed_queue() -> void:
	if _seed == "":
		return
	for pair in _seed.split(","):
		var bl := pair.split(":")
		var row := _row_of(bl[0])
		if bl.size() == 2 and not row.is_empty():
			_q.entries.append({"building_id": bl[0], "lot_id": bl[1], "upgrade": false, "level": 1,
				"cost": (row.get("cost", {}) as Dictionary).duplicate(), "status": "queued", "reason": ""})
	_seed = ""
	_scroll_q_s = 4.0  # the shot shows the Queue section, whatever the status line does meanwhile


func on_game_event(_ev: Dictionary) -> void:
	pass


func _row_of(bid: String) -> Dictionary:
	for r in _views.get("catalog", {}).get("buildings", []):
		if String(r.get("building_id", "")) == bid:
			return r
	return {}


func _label(bid: String) -> String:
	return BuildSort.label_of(bid, _bview)


func _reason(reason: String, row: Dictionary) -> String:
	return BuildSort.reason_text(reason, row, _st, _bview, _vcfg)


func _say(text: String) -> void:
	_status.text = text


# ------------------------------------------------------------------ rows ----
func _rebuild_rows(rows: Array) -> void:
	TownUI.clear(_rows_box)
	_rows.clear()
	for r in rows:
		var bid := String(r.get("building_id", ""))
		_rows[bid] = _make_row(bid)
		_rows_box.add_child(_rows[bid]["node"])


func _make_row(bid: String) -> Dictionary:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style_row)
	var v := VBoxContainer.new()
	pc.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var nm := TownUI.label("", 16)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var count := TownUI.label("", 14, "text_dim")
	top.add_child(count)
	var queue := _btn("Queue")
	queue.pressed.connect(_on_queue.bind(bid))
	top.add_child(queue)
	var place := _btn("Place")
	place.pressed.connect(_toggle_place.bind(bid))
	top.add_child(place)
	var ben := HBoxContainer.new()  # the live benefit, as the card draws it: rates oblique, words upright
	ben.add_theme_constant_override("separation", 10)
	v.add_child(ben)
	var rates: Array = []
	for k in 3:
		var rl := TownUI.rate_label("", 14)
		ben.add_child(rl)
		rates.append(rl)
	var plain := _wrap("", 14, "text_dim")
	ben.add_child(plain)
	var cost_row := HBoxContainer.new()
	v.add_child(cost_row)
	var costs: Array = []
	for k in 3:
		var l := TownUI.label("", 14)
		cost_row.add_child(l)
		costs.append(l)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 10)
	v.add_child(tags)
	var sug := TownUI.label("suggested", 14, "select")
	tags.add_child(sug)
	var chip := _wrap("", 14, "select")
	tags.add_child(chip)
	var rbox := HBoxContainer.new()
	v.add_child(rbox)
	var reason := _wrap("", 14, "text_dim")
	rbox.add_child(reason)
	var link := _btn("", 110.0)
	link.pressed.connect(func(): _focus_building(String(link.get_meta("target", ""))))
	rbox.add_child(link)
	return {"node": pc, "name": nm, "count": count, "queue": queue, "place": place, "rates": rates, "plain": plain,
		"costs": costs, "chip": chip, "sug": sug, "reason": reason, "link": link}


func _update_row(it: Dictionary, w: Dictionary) -> void:
	var row: Dictionary = it["row"]
	var bid := String(row.get("building_id", ""))
	var can := bool(row.get("can_build", false))
	w["name"].text = _label(bid)
	w["name"].add_theme_color_override("font_color", Palette.c("text_dim" if it["cls"] == BuildSort.CLS_GATED else "text"))
	w["sug"].visible = bid == _sug_bid
	w["sug"].text = String(_sug_data.get("chip", "suggested")) if bool(_sug_data.get("upgrade", false)) else "suggested"
	w["count"].text = "built %d" % int(row.get("count", 0))
	var ben := BuildSort.benefit(bid, row, _bcfg, _bview, _vcfg)
	for k in 3:
		w["rates"][k].visible = k < ben["rates"].size()
		w["rates"][k].text = String(ben["rates"][k]) if k < ben["rates"].size() else ""
	w["plain"].text = "  ".join(ben["plain"])
	w["plain"].visible = not ben["plain"].is_empty()
	var parts := BuildSort.cost_parts(row.get("cost", {}), _st)
	for k in 3:
		w["costs"][k].text = String(parts[k]["text"]) + ("  ·  " if k < 2 else "")
		w["costs"][k].add_theme_color_override("font_color", Palette.c("danger" if parts[k]["short"] else "text"))
	w["chip"].visible = it["chip"] != ""
	w["chip"].text = "Needed now: " + String(it["chip"])
	w["place"].visible = can
	w["place"].text = "Stop" if _placing == bid else "Place"
	w["queue"].visible = BuildSort.can_queue(row, _vcfg)
	w["queue"].disabled = _queue_full() or _free_lot(row) == ""
	var why := String(row.get("reason", ""))
	w["reason"].get_parent().visible = not can
	w["reason"].text = BuildSort.row_reason(row, _st, _bview, _vcfg)  # with an unmet relic cost said too
	w["reason"].add_theme_color_override("font_color", Palette.c("text" if it["cls"] == BuildSort.CLS_GATED else "text_dim"))
	var target := BuildSort.fix_target(why, row, _st, _vcfg) if not can else ""
	w["link"].visible = target != ""
	w["link"].set_meta("target", target)
	w["link"].text = "Show " + _label(target) if target != "" else ""
	w["node"].add_theme_stylebox_override("panel", _style_focus if _focus == bid else _style_row)


# ------------------------------------------------------------- placement ----
func _toggle_place(bid: String) -> void:
	if _placing == bid:
		cancel_placement()
		return
	_close_card()
	_placing = bid
	_placing_lots = []
	_check_placement()
	_update_banner()  # the banner says how to leave placement; no second hint in the status line


## Ends placement (Escape, right-click, Stop, leaving the tab).
func cancel_placement() -> void:
	if _placing == "":
		return
	_placing = ""
	_placing_lots = []
	placement_changed.emit("", [])
	_update_banner()
	for bid in _rows:
		_rows[bid]["place"].text = "Place"
	_push_suggestion()


func _update_banner() -> void:
	_banner.visible = _placing != ""
	_banner_label.text = "Placing %s: click a lit lot in town. Esc, right-click or Cancel stops." % _label(_placing) if _placing != "" else ""


## Keeps the town view's lit lots in step with the catalog; a building that can't be placed any
## more (funds spent, lots gone) ends placement, with the reason.
func _check_placement() -> void:
	if _placing == "":
		return
	var row := _row_of(_placing)
	if row.is_empty() or not bool(row.get("can_build", false)):
		var why := _reason(String(row.get("reason", "")), row) if not row.is_empty() else ""
		var nm := _label(_placing)
		cancel_placement()
		_say("Can't place %s now: %s." % [nm, why])
		return
	if row.get("lots", []) != _placing_lots:
		_placing_lots = (row["lots"] as Array).duplicate()
		placement_changed.emit(_placing, _placing_lots)
	_update_banner()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.keycode != KEY_ESCAPE:
		return
	if (_placing != "" and is_visible_in_tree()) or _card_lot != "":
		dismiss()
		get_viewport().set_input_as_handled()


## Escape or a right-click: ends placement, else closes the lot card (and its selection).
func dismiss() -> void:
	if _placing != "":
		cancel_placement()
	elif _card_lot != "" or _selected_lot != "":
		_select_lot("")
		_close_card()


## The town view reports a click: a lit lot places the building, a built lot is inspected.
func on_lot_clicked(lot_id: String) -> void:
	if _placing != "":
		var row := _row_of(_placing)
		if lot_id == "":
			_say("Click one of the lit lots, or press Esc.")
		elif lot_id in row.get("lots", []):
			var bid := _placing
			var r: Dictionary = Game.state.cmd_build(bid, lot_id)
			_report(r, "Building %s on %s." % [_label(bid), lot_id], row)
			if bool(r.get("ok", false)):
				build_started.emit(lot_id)
			cancel_placement()
		else:
			_say("%s: %s." % [lot_id, _reason(BuildSort.lot_refusal(_town_lot(lot_id), row), row)])
		return
	if lot_id != "" and _entry_at(lot_id) != {}:  # a built or constructing lot: the inspector, in the card too
		_open_card(lot_id, "inspect")
		_select_lot(lot_id)
	elif lot_id != "" and bool(_town_lot(lot_id).get("unlocked", false)):  # an empty open lot: what fits it
		_select_lot("")
		_open_card(lot_id, "catalog")
	else:
		_select_lot("")
		_close_card()


func _town_lot(lot_id: String) -> Dictionary:
	for l in _views.get("town", {}).get("lots", []):
		if String(l.get("id", "")) == lot_id:
			return l
	return {}


func _entry_at(lot_id: String) -> Dictionary:
	for b in _views.get("town", {}).get("buildings", []):
		if String(b.get("lot_id", "")) == lot_id:
			return b
	return {}


func _report(r: Dictionary, ok_text: String, row := {}) -> void:
	if bool(r.get("ok", false)):
		_say(ok_text)
	else:
		_say("Refused: %s." % _reason(String(r.get("reason", "")), row))
	command_issued.emit()


## Another tab (backups' No vats yet) asks for this building: its row is focused and, when it can be built, placement starts.
func select_building(bid: String) -> void:
	_focus_building(bid)


func _focus_building(bid: String) -> void:
	if bid == "" or not _rows.has(bid):
		return
	_focus = bid
	if bool(_row_of(bid).get("can_build", false)) and _placing != bid:
		_toggle_place(bid)
	ensure_control_visible.call_deferred(_rows[bid]["node"])


# ------------------------------------------------------------- inspector ----
func _build_inspector() -> void:
	_insp = _make_inspector(_style_focus)
	_root.add_child(_insp["node"])


## The inspector's widgets (one set in this tab, one in the lot card), wired to the same handlers.
func _make_inspector(style: StyleBox) -> Dictionary:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", style)
	var v := VBoxContainer.new()
	pc.add_child(v)
	var w := {"node": pc}
	w["title"] = TownUI.label("", 18)
	w["flavour"] = _wrap("", 14, "text_dim")
	for k in ["level", "state", "staffing", "foreman"]:
		w[k] = _wrap("", 14)
	for k in ["title", "flavour", "level", "state", "staffing", "foreman"]:
		v.add_child(w[k])
	var up := HBoxContainer.new()
	var ul := TownUI.label("upkeep", 14, "text_dim")
	up.add_child(ul)
	w["up_gold"] = TownUI.rate_label("", 14)
	w["up_bone"] = TownUI.rate_label("", 14)
	up.add_child(w["up_gold"])
	up.add_child(w["up_bone"])
	up.add_theme_constant_override("separation", 12)
	v.add_child(up)
	w["sug_up"] = TownUI.label("suggested", 14, "select")  # the upgrade is the suggested action
	w["sug_up"].visible = false
	v.add_child(w["sug_up"])
	var r1 := HBoxContainer.new()
	w["upgrade"] = _btn("Upgrade", 100.0)
	w["upgrade"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w["upgrade"].pressed.connect(_on_upgrade)
	w["queue_up"] = _btn("Queue", 76.0)
	w["queue_up"].pressed.connect(_on_queue_upgrade)
	r1.add_child(w["upgrade"])
	r1.add_child(w["queue_up"])
	v.add_child(r1)
	w["proj"] = TownUI.rate_label("", 14, "text")  # TODO(api-request #9): upgrade_projected, labelled "now"
	w["proj"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	w["proj"].custom_minimum_size = Vector2(40, 0)
	v.add_child(w["proj"])
	w["why"] = _wrap("", 14, "text_dim")
	v.add_child(w["why"])
	var r2 := HBoxContainer.new()
	w["cancel"] = _btn("Cancel build", 100.0)
	w["cancel"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w["cancel"].pressed.connect(_on_cancel_build)
	w["demolish"] = _btn("Demolish", 100.0)
	w["demolish"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w["demolish"].pressed.connect(_on_demolish)
	w["close"] = _btn("Close", 76.0)
	w["close"].pressed.connect(func(): _select_lot(""))
	r2.add_child(w["cancel"])
	r2.add_child(w["demolish"])
	r2.add_child(w["close"])
	v.add_child(r2)
	pc.visible = false
	return w


func _select_lot(lot_id: String) -> void:
	if lot_id != _selected_lot:
		_armed_s = 0.0
	_selected_lot = lot_id
	lot_selected.emit(lot_id)
	if lot_id == "" and _card_mode == "inspect":
		_close_card()
	_update_inspector()
	_push_suggestion()


func _update_inspector() -> void:
	var entry := _entry_at(_selected_lot) if _selected_lot != "" else {}
	if entry.is_empty():
		if _selected_lot != "":
			_selected_lot = ""
			lot_selected.emit("")
			if _card_mode == "inspect":
				_close_card()
		_insp["node"].visible = false
		return
	var i := BuildSort.inspect(entry, _st, _bcfg, _bview, _vcfg)
	_fill_inspector(_insp, i)
	if _card_mode == "inspect" and _card_lot == _selected_lot and not _insp_card.is_empty():
		_fill_inspector(_insp_card, i)
		_card.show_inspector("Lot %s" % _selected_lot)


func _fill_inspector(w: Dictionary, i: Dictionary) -> void:
	w["node"].visible = true
	w["title"].text = "%s  (%s)" % [i["label"], _selected_lot]
	w["flavour"].text = i["flavour"]
	w["level"].text = String(i["level_text"])
	w["state"].text = "State: " + String(i["state_text"])
	w["staffing"].text = "Staffing: " + String(i["staffing"])
	var fm := String(i["foreman"])
	w["foreman"].text = "Foreman: none" if fm == "no foreman" else "Foreman: " + fm.trim_prefix("foreman ")
	w["up_gold"].text = "%s gold" % TownUI.fmt_rate(-float(i["upkeep"]["gold"]))
	w["up_bone"].text = "%s bone" % TownUI.fmt_rate(-float(i["upkeep"]["bone"]))
	var u: Dictionary = i["upgrade"]
	w["upgrade"].visible = u["visible"]
	w["sug_up"].visible = u["visible"] and not _sug_off and bool(_sug_data.get("upgrade", false)) and String(_sug_data.get("lot_id", "")) == _selected_lot
	w["upgrade"].disabled = not u["enabled"]
	w["upgrade"].text = "Upgrade to Lv %d: %s" % [u["level"], _cost_text(u["cost"])] if not (u["cost"] as Dictionary).is_empty() else "Upgrade"
	w["queue_up"].visible = u["visible"]
	w["queue_up"].disabled = not u["can_queue"] or _queue_full() or _queued_lot(_selected_lot)
	var proj: Array = BuildSort.rate_texts(i["upgrade_projected"], _vcfg) if i["upgrade_projected"] is Dictionary else []
	w["proj"].visible = u["visible"] and u["enabled"] and not proj.is_empty()
	w["proj"].text = "%s %s" % [String(_vcfg.get("benefit", {}).get("upgrade_now", "")), ", ".join(proj)]
	var why := ""
	if u["visible"] and not u["enabled"]:
		why = _reason(String(u["reason"]), {"cost": u["cost"]})
	w["why"].visible = why != ""
	w["why"].text = why
	var c: Dictionary = i["cancel"]
	w["cancel"].visible = c["visible"]
	w["cancel"].text = "Cancel build (refund %s)" % _cost_text(c["refund"], false) if c["visible"] else "Cancel build"
	w["demolish"].visible = i["demolish_visible"] and not c["visible"]
	w["demolish"].text = "Click again to demolish (%d s)" % int(ceil(_armed_s)) if _armed_s > 0.0 else "Demolish"


func _cost_text(cost: Dictionary, marks := true) -> String:
	var parts := BuildSort.cost_parts(cost, _st)
	var out: Array = []
	for p in parts:
		if p["key"] != "relics" or int(cost.get("relics", 0)) > 0:
			out.append(String(p["text"]) if marks else String(p["text"]).trim_prefix("! "))
	return " · ".join(out)


func _on_upgrade() -> void:
	var r: Dictionary = Game.state.cmd_upgrade(_selected_lot)
	_report(r, "Upgrading %s." % _selected_lot, {})
	if bool(r.get("ok", false)):
		build_started.emit(_selected_lot)


func _on_cancel_build() -> void:
	var r: Dictionary = Game.state.cmd_cancel_build(_selected_lot)
	_report(r, "Cancelled the build on %s." % _selected_lot, {})


func _on_demolish() -> void:
	if _armed_s <= 0.0:
		_armed_s = float(_vcfg.get("demolish_confirm_s", 3.0))
		_update_inspector()
		return
	_armed_s = 0.0
	var lot := _selected_lot
	var r: Dictionary = Game.state.cmd_demolish(lot)
	_report(r, "Demolished %s." % lot, {})
	_update_inspector()


func _process(delta: float) -> void:
	if _scroll_q_s > 0.0:
		_scroll_q_s -= delta
		if is_visible_in_tree():
			scroll_vertical = int(get_v_scroll_bar().max_value)
	if _armed_s > 0.0:
		_armed_s = maxf(_armed_s - delta, 0.0)
		_update_inspector()
	_poll_hover()


## The catalog row under the pointer (a Control's mouse_entered/exited misfire over its buttons, so
## this reads the pointer against the row rects while the tab is showing).
func _poll_hover() -> void:
	var bid := ""
	if is_visible_in_tree():
		var mp := get_global_mouse_position()
		if get_global_rect().has_point(mp):
			for id in _rows:
				var n: Control = _rows[id]["node"]
				if n.visible and n.get_global_rect().has_point(mp):
					bid = id
					break
	if bid != _hover_bid:
		_hover_bid = bid
		_emit_hover()


func _emit_hover() -> void:
	var bid := _card_hover if _card_hover != "" else _hover_bid
	var lots: Array = (_row_of(bid).get("lots", []) as Array).duplicate() if bid != "" else []
	if lots != _last_hover:
		_last_hover = lots
		hover_lots.emit(lots)


# ------------------------------------------------------------------ card ----
func _open_card(lot_id: String, mode: String) -> void:
	if _card == null:
		return
	_card_lot = lot_id
	_card_mode = mode
	_card.open()
	card_opened.emit(lot_id)
	_update_card()
	_update_inspector()
	_push_suggestion()


func _close_card() -> void:
	if _card_lot == "" and _card_mode == "":
		return
	_card_lot = ""
	_card_mode = ""
	_card_hover = ""
	if _card != null:
		_card.close()
	card_closed.emit()
	_emit_hover()
	_push_suggestion()


## Keeps an open empty-lot card in step with the catalog (rows, costs, reasons with their estimates).
func _update_card() -> void:
	if _card == null or _card_lot == "" or _card_mode != "catalog":
		return
	var lot := _town_lot(_card_lot)
	if lot.is_empty() or not bool(lot.get("unlocked", false)):
		_close_card()
		return
	if _entry_at(_card_lot) != {}:  # something is being built here now: the lot's inspector takes over
		_select_lot(_card_lot)
		_open_card(_card_lot, "inspect")
		return
	var items := BuildSort.fitting(_sorted, int(lot.get("size", 1)))
	_card.show_catalog(_card_lot, int(lot.get("size", 1)), items, _st, _sug_new_bid(),
		not _queue_full() and not _queued_lot(_card_lot), BuildSort.reserved_note(_card_lot, _reserved, _bview, _vcfg))


func _on_card_build(bid: String, lot_id: String) -> void:
	var row := _row_of(bid)
	var r: Dictionary = Game.state.cmd_build(bid, lot_id)
	_report(r, "Building %s on %s." % [_label(bid), lot_id], row)
	if bool(r.get("ok", false)):
		build_started.emit(lot_id)
		dismiss()


func _on_card_queue(bid: String, lot_id: String) -> void:
	var row := _row_of(bid)
	if _add_queue({"building_id": bid, "lot_id": lot_id, "upgrade": false, "level": 1, "cost": row.get("cost", {})}, row):
		dismiss()


## The suggested building when the suggestion is a new build ("" for an upgrade: an empty lot's card has no upgrade).
func _sug_new_bid() -> String:
	return "" if bool(_sug_data.get("upgrade", false)) else _sug_bid


## The suggestion shows on the canvas only while nothing else is going on: no placement, no
## selection, no open card, and not dismissed.
func _push_suggestion() -> void:
	var live: bool = not _sug_off and _placing == "" and _selected_lot == "" and _card_lot == "" and not _sug_data.is_empty()
	var sug: Dictionary = _sug_data if live else {}
	if sug != _last_sug:
		_last_sug = sug.duplicate(true)
		suggestion_changed.emit(sug)


## The view's x on the suggestion tag.
func on_suggestion_dismissed() -> void:
	_sug_off = true
	_sug_bid = ""
	_push_suggestion()
	bind(_views)


# ----------------------------------------------------------------- queue ----
## The Queue, under the catalog: each entry with its number, label, lot, status shape, an ETA from
## today's rates and the measured build throughput, Up / Down / Unqueue (>= 44 px).
func _build_queue_section() -> void:
	_q_title = TownUI.label(String(_vcfg.get("queue_text", {}).get("title", "")), 16)
	_q_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_q_title.custom_minimum_size = Vector2(40, 0)
	_root.add_child(_q_title)
	_cap_box = HBoxContainer.new()
	_cap_label = _wrap("", 14, "danger")
	_cap_box.add_child(_cap_label)
	_cap_btn = _btn("", 130.0)
	_cap_btn.pressed.connect(func(): _focus_building(_cap_building))
	_cap_box.add_child(_cap_btn)
	_cap_box.visible = false
	_root.add_child(_cap_box)
	_q_empty = _wrap("Nothing queued. Queue a building to spend income while you are away.", 14, "text_dim")
	_root.add_child(_q_empty)
	_q_box = VBoxContainer.new()
	_q_box.add_theme_constant_override("separation", 4)
	_root.add_child(_q_box)


func _free_lot(row: Dictionary) -> String:
	for l in row.get("lots", []):
		if not _queued_lot(String(l)):
			return String(l)
	return ""


func _queued_lot(lot_id: String) -> bool:
	for e in _queue_entries():
		if e["lot_id"] == lot_id:
			return true
	return false


func _on_queue(bid: String) -> void:
	var row := _row_of(bid)
	_add_queue({"building_id": bid, "lot_id": _free_lot(row), "upgrade": false, "level": 1, "cost": row.get("cost", {})}, row)


func _on_queue_upgrade() -> void:
	var entry := _entry_at(_selected_lot)
	var i := BuildSort.inspect(entry, _st, _bcfg, _bview, _vcfg)
	_add_queue({"building_id": i["building_id"], "lot_id": _selected_lot, "upgrade": true, "level": i["upgrade"]["level"],
		"cost": i["upgrade"]["cost"]}, {"cost": i["upgrade"]["cost"]})


func _add_queue(e: Dictionary, row: Dictionary) -> bool:
	if not TownStandins.queue_is_standin(_views.get("town", {})):
		# TODO(api-request #3): call cmd_queue_build here once E2b ships it; the local queue is off meanwhile
		_say(String(_vcfg.get("queue_text", {}).get("no_commands", "")))
		return false
	var r := _q.add(e, _ctx)
	if r["ok"]:
		_cap_box.visible = false
		_say("Queued %s on %s." % [_label(e["building_id"]), e["lot_id"]])
	elif r["reason"] == "cost_exceeds_cap":
		_show_cap_refusal(e, r)
	else:
		_say("Not queued: %s." % _reason(String(r["reason"]), row))
	_update_queue()
	return bool(r["ok"])


## "<cost> is over the <gold> cap: build <label> first", with a button that selects that building.
func _show_cap_refusal(e: Dictionary, r: Dictionary) -> void:
	var store := String(r["store"])
	var tt: Dictionary = _vcfg.get("queue_text", {})
	_cap_building = String(r["cap_building"])
	var vars := {"cost": "%d %s" % [int(ceil(float(e["cost"].get(store, 0.0)))), store], "store": store,
		"cap": int(_ctx.get(store + "_cap", -1.0)), "label": _label(_cap_building)}
	_cap_label.text = BuildSort.fmt(String(tt.get("cap_refusal" if _cap_building != "" else "cap_refusal_none", "")), vars)
	_cap_btn.visible = _cap_building != ""
	_cap_btn.text = "Show " + _label(_cap_building)
	_cap_box.visible = true
	_say("Not queued: %s." % _reason("cost_exceeds_cap", {}))


func _queue_entries() -> Array:
	return TownStandins.queue_entries(_views.get("town", {}), _q.entries)


func _queue_full() -> bool:
	return _queue_entries().size() >= _q.max_len


func _update_queue() -> void:
	var entries := _queue_entries()
	_q_empty.visible = entries.is_empty()
	while _q_pool.size() < entries.size():
		_q_pool.append(_make_q_row(_q_pool.size()))
	var tt: Dictionary = _vcfg.get("queue_text", {})
	var etas := BuildSort.queue_etas(entries, _st, _ctx.get("catalog", {}), _views.get("town", {}), _tp.rate, _vcfg)
	for i in _q_pool.size():
		var w: Dictionary = _q_pool[i]
		w["node"].visible = i < entries.size()
		if i >= entries.size():
			continue
		var e: Dictionary = entries[i]
		var what := ("Upgrade %s to Lv %d" % [_label(e["building_id"]), e["level"]]) if e["upgrade"] else _label(e["building_id"])
		var status := String(e["status"])
		var why := BuildSort.entry_reason(e, _ctx.get("catalog", {}), _st, _bview, _vcfg)
		var glyph: String = {"next": ">", "waiting_funds": "||", "skipped_gate": "x", "queued": "-"}.get(status, "-")
		var title := "%d. %s on %s" % [i + 1, what, e["lot_id"]]
		w["title"].text = "[s]%s[/s]" % title if status == "skipped_gate" else title
		w["detail"].text = "%s %s" % [glyph, BuildSort.fmt(String(tt.get(status, "")), {"why": why})]
		w["detail"].add_theme_color_override("font_color", Palette.c(
			{"next": "text", "waiting_funds": "select", "skipped_gate": "danger", "queued": "text_dim"}.get(status, "text_dim")))
		w["eta"].text = String(etas[i])
		w["eta"].visible = String(etas[i]) != ""  # a gate-skipped entry says why instead
		w["up"].disabled = i == 0
		w["down"].disabled = i == entries.size() - 1
	var ghosts := BuildSort.ghosts(entries, _ctx.get("catalog", {}), _st, _bview, _vcfg)
	if ghosts != _last_ghosts:  # the canvas draws these same entries, same numbers
		_last_ghosts = ghosts
		queue_changed.emit(ghosts)


## Reorder (delta ±1) or remove (0) a stand-in entry. TODO(api-request #3): cmd_reorder_queue /
## cmd_unqueue once the view has a queue; until then those arrive with E2b.
func _move_queue(index: int, delta: int) -> void:
	if not TownStandins.queue_is_standin(_views.get("town", {})):
		_say(String(_vcfg.get("queue_text", {}).get("no_commands", "")))
		return
	if delta == 0:
		_q.unqueue(index)
	else:
		_q.move(index, delta)
	_update_queue()


func _make_q_row(index: int) -> Dictionary:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style_row)
	var h := HBoxContainer.new()
	pc.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size = Vector2(40, 0)
	title.add_theme_font_size_override("normal_font_size", 14)
	title.add_theme_color_override("default_color", Palette.c("text"))
	v.add_child(title)
	var detail := _wrap("", 14, "text_dim")
	v.add_child(detail)
	var eta := _wrap("", 14, "text")
	v.add_child(eta)
	var up := _btn("Up", 56.0)
	up.pressed.connect(func(): _move_queue(index, -1))
	var down := _btn("Down", 56.0)
	down.pressed.connect(func(): _move_queue(index, 1))
	var rm := _btn("Unqueue", 80.0)
	rm.pressed.connect(func(): _move_queue(index, 0))
	for b in [up, down, rm]:
		h.add_child(b)
	_q_box.add_child(pc)
	return {"node": pc, "title": title, "detail": detail, "eta": eta, "up": up, "down": down}
