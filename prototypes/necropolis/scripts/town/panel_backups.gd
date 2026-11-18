extends VBoxContainer
## Backups tab: what a death would cost right now (first, largest), the clone vats with growing
## silhouettes and staffing toggles that say what the town pays, and the Ossuary's phylactery
## charges, simulacra and crafting. Nodes are built once and updated in place on every bind.
## Pure text lives in BackupsModel; commands are cmd_staff_vat and cmd_craft.

signal command_issued
## "No vats yet": the shell switches to the Build tab and selects this building there.
signal show_building(building_id: String)

const FigureScript := preload("res://scripts/town/backups_figure.gd")

## The shell's cached staffing projection: project.call(order, extra := {}) -> the jobs array.
var project: Callable
var _tx: Dictionary = {}
var _vcfg: Dictionary = {}
var _views: Dictionary = {}
var _body: VBoxContainer
var _status: Label
# death
var _outcome: Label
var _wait: Label
var _steps: Array = []  # [{id, box, label}]
var _loses: Label
# vats
var _clones: Label
var _upkeep: RichTextLabel
var _vat_box: VBoxContainer
var _vats: Dictionary = {}  # slot -> {node, fig, title, state, cost, toggle}
var _vat_sig := ""
var _no_vats: VBoxContainer
# ossuary
var _charges: Label
var _usable: Label
var _simulacra: Label
var _stock: Label
var _craft_box: GridContainer  # the craft cards side by side, so both show without scrolling
var _crafts: Dictionary = {}  # item id -> {node, name, cost, btn, why}
var _craft_sig := ""
var _sigs := {}  # section -> BackupsModel signature of the inputs it was last filled from
var _ladder_now := "?"


func _ready() -> void:
	_vcfg = ConfigDb.v("town", "view", {})
	_tx = _vcfg.get("backups", {})
	add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)
	_build_death()
	_build_vats()
	_build_ossuary()
	_status = _wrap("", 14, "select")
	add_child(_status)


func _wrap(text: String, size := 14, key := "text") -> Label:
	var l := TownUI.label(text, size, key)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(40, 0)
	return l


func _t(key: String) -> String:
	return String(_tx.get(key, key))


## The glossary's one line for a word (view.guide.jargon): its tooltip.
func _jargon(word: String) -> String:
	return String(_vcfg.get("guide", {}).get("jargon", {}).get(word, ""))


func _say(text: String) -> void:
	_status.text = text


# ------------------------------------------------------------------ death ----
func _build_death() -> void:
	_body.add_child(_wrap(_t("title"), int(_tx.get("title_px", 16)), "text_dim"))
	_loses = _wrap("", int(_tx.get("loses_px", 22)))  # the stake is the headline
	_body.add_child(_loses)
	_outcome = _wrap("", int(_tx.get("outcome_px", 14)), "text_dim")  # the comfort line is its subtitle
	_body.add_child(_outcome)
	_wait = _wrap("", 14, "text_dim")
	_body.add_child(_wait)
	_body.add_child(_wrap(_t("ladder_header"), int(_tx.get("ladder_header_px", 12)), "text_dim"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_body.add_child(row)
	for id in BackupsModel.LADDER:
		var box := PanelContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l := _wrap("", 14)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
		if id == "phylactery":
			box.tooltip_text = _jargon("phylactery")
		row.add_child(box)
		_steps.append({"id": id, "box": box, "label": l})


func _fill_death(bk: Dictionary) -> void:
	var death: Dictionary = bk.get("death", {})
	var pending := BackupsModel.numbers_pending(death, _tx)  # the stub's outcome and wait are tagged "coming"
	_outcome.text = BackupsModel.outcome_text(death, _tx, pending)
	var left := float(bk.get("dead_s_left", 0.0))
	_wait.text = String(_tx.get("dead_now", "")).format({"wait": BackupsModel.wait_text(left, _tx)}) if left > 0.0 else ""
	_wait.visible = _wait.text != ""
	var cur := String(death.get("outcome", ""))
	var key := "%s|%s" % [cur, pending]
	if key != _ladder_now:  # the theme overrides are the cost: only when the outcome moved
		_ladder_now = key
		for s in _steps:
			var now: bool = s["id"] == cur
			var l: Label = s["label"]
			l.text = "%s %s%s" % [_t("ladder_mark") if now else _t("ladder_off"), String(_tx.get("ladder", {}).get(s["id"], s["id"])),
				"\n(%s)" % BackupsModel.ladder_now_text(_tx, pending) if now else ""]
			l.add_theme_color_override("font_color", Palette.c("text" if now else "text_dim"))
			s["box"].add_theme_stylebox_override("panel", TownUI.button_box_cached("active" if now else "normal"))
	var town: Dictionary = _views.get("town", {})
	var lots := CryptLogic.lot_labels(town.get("buildings", []), _labels())
	_loses.text = BackupsModel.loses_line(death.get("loses", []), _views.get("party", {}).get("party", []), lots, _views.get("fort_names", {}), _vcfg.get("crypt", {}), _tx, ConfigDb.data.get("town", {}).get("slab", {}))


func _labels() -> Dictionary:
	var out := {}
	var bv: Dictionary = ConfigDb.data.get("buildings_view", {})
	for bid in bv:
		out[bid] = String(bv[bid].get("label", bid))
	return out


# ------------------------------------------------------------------- vats ----
func _build_vats() -> void:
	_body.add_child(_wrap(_t("vats_header"), 16, "text_dim"))
	_clones = _wrap("", 18)
	_body.add_child(_clones)
	_upkeep = TownUI.parts_label(14, "text_dim", true)  # the signed rate is oblique like every other rate
	_body.add_child(_upkeep)
	_vat_box = VBoxContainer.new()
	_vat_box.add_theme_constant_override("separation", 6)
	_body.add_child(_vat_box)
	_no_vats = VBoxContainer.new()
	_no_vats.add_child(_wrap(_t("no_vats"), 14))
	var b := TownUI.button(_t("no_vats_btn"))
	b.pressed.connect(func() -> void: show_building.emit(_t("chapel")))
	_no_vats.add_child(b)
	_body.add_child(_no_vats)


func _make_vat(slot: int) -> Dictionary:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", TownUI.panel_box())
	card.custom_minimum_size = Vector2(0, float(_tx.get("card_h_px", 112)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	var fig := Control.new()
	fig.set_script(FigureScript)
	fig.setup(_tx)
	h.add_child(fig)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	var title := TownUI.label("", 16)
	var state := _wrap("", 14)
	var cost := _wrap("", 14, "text_dim")
	var toggle := TownUI.button("")
	toggle.pressed.connect(_on_toggle.bind(slot))
	col.add_child(title)
	col.add_child(state)
	col.add_child(cost)
	col.add_child(toggle)
	_vat_box.add_child(card)
	return {"node": card, "fig": fig, "title": title, "state": state, "cost": cost, "toggle": toggle, "staffed": false}


func _fill_vats(bk: Dictionary, costs: Array) -> void:
	var vats: Array = bk.get("vats", [])
	_clones.text = String(_tx.get("clones_ready", "")).format({"n": int(bk.get("clones_ready", 0))})
	_no_vats.visible = vats.is_empty()
	var up := BackupsModel.chapel_upkeep(_views.get("town", {}).get("buildings", []), _t("chapel"))
	var up_parts := BackupsModel.upkeep_parts(up, String(_labels().get(_t("chapel"), "Chapel")), _tx)
	TownUI.set_parts(_upkeep, up_parts)
	_upkeep.visible = not up_parts.is_empty() and not vats.is_empty()
	var sig := ",".join(vats.map(func(v): return str(int(v.get("slot", 0)))))
	if sig != _vat_sig:
		_vat_sig = sig
		TownUI.clear(_vat_box)
		_vats.clear()
		for v in vats:
			_vats[int(v.get("slot", 0))] = _make_vat(int(v.get("slot", 0)))
	for i in vats.size():
		var v: Dictionary = vats[i]
		var slot := int(v.get("slot", 0))
		var w: Dictionary = _vats[slot]
		var staffed := bool(v.get("staffed", false))
		w["staffed"] = staffed
		var ready := bool(v.get("ready", false))
		var grow := float(v.get("grow", 0.0))
		(w["title"] as Label).text = String(_tx.get("vat_title", "")).format({"n": slot + 1}) \
			+ ("" if ready else "  " + String(_tx.get("vat_grow", "")).format({"pct": roundi(grow * 100.0)}))
		(w["state"] as Label).text = BackupsModel.vat_state_text(v, _tx)
		(w["cost"] as Label).text = String(costs[i]) if i < costs.size() else ""
		(w["toggle"] as Button).text = _t("staff_off" if staffed else "staff_on")
		(w["fig"] as Control).set_state(1.0 if ready else grow, ready)


func _on_toggle(slot: int) -> void:
	if not _vats.has(slot):
		return
	var r: Dictionary = Game.state.cmd_staff_vat(slot, not bool(_vats[slot]["staffed"]))
	if not bool(r.get("ok", false)):
		var why := String(_tx.get("staff_reasons", {}).get(String(r.get("reason", "")), String(r.get("reason", ""))))
		_say(TownUI.refusal(String(r.get("reason", "")), why, String(_tx.get("staff_refused", "")).format({"reason": why})))
	else:
		_say("")
	command_issued.emit()


# --------------------------------------------------------------- ossuary ----
func _build_ossuary() -> void:
	_body.add_child(_wrap(_t("ossuary_header"), 16, "text_dim"))
	_charges = _wrap("", 18)
	_charges.mouse_filter = Control.MOUSE_FILTER_STOP
	_charges.tooltip_text = _jargon("phylactery")
	_body.add_child(_charges)
	_usable = _wrap("", 14, "text_dim")  # the glossary's meaning of a charge, inline where the word first shows
	_body.add_child(_usable)
	_simulacra = _wrap("", 18)
	_body.add_child(_simulacra)
	_stock = _wrap("", 14)
	_body.add_child(_stock)
	# where essence comes from and what it pays for (view.guide; Shawn's checklist item 11): beside the count
	_body.add_child(_wrap(String(ConfigDb.v("town", "view", {}).get("guide", {}).get("essence_line", "")), 14, "text_dim"))
	_craft_box = GridContainer.new()
	_craft_box.columns = int(_tx.get("craft_columns", 2))
	_craft_box.add_theme_constant_override("h_separation", 6)
	_craft_box.add_theme_constant_override("v_separation", 6)
	_body.add_child(_craft_box)


func _make_craft(item_id: String) -> Dictionary:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", TownUI.panel_box())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if item_id == String(_tx.get("phylactery_item", "")):
		card.tooltip_text = _jargon("phylactery")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	card.add_child(h)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	var nm := TownUI.label("", 16)
	var cost := _wrap("", 14)
	var why := _wrap("", TownUI.MIN_TEXT, "text_dim")  # half a dock wide: the reason fits one line at the smallest size
	col.add_child(nm)
	col.add_child(cost)
	col.add_child(why)
	var btn := TownUI.button(_t("craft_btn"))
	btn.custom_minimum_size = Vector2(float(_tx.get("craft_btn_w_px", 72.0)), TownUI.MIN_TARGET)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(_on_craft.bind(item_id))
	h.add_child(btn)
	_craft_box.add_child(card)
	return {"node": card, "name": nm, "cost": cost, "why": why, "btn": btn}


func _fill_ossuary(bk: Dictionary) -> void:
	var inv: Dictionary = _views.get("inventory", {})
	var charges := int(bk.get("phylactery_charges", 0))
	_charges.text = "%s: %s" % [_t("charges"), BackupsModel.pips_text(charges, _tx)]
	_usable.text = String(_tx.get("charges_usable", "")).format({"n": int(bk.get("phylactery_max_per_dungeon", 0))})
	_simulacra.text = "%s (%s)" % [String(_tx.get("simulacra", "")).format({"n": int(inv.get("simulacra_ready", 0))}), _t("simulacra_where")]
	_stock.text = String(_tx.get("stock", "")).format({"essence": int(inv.get("essence", 0)), "relics": int(inv.get("relics", 0))})
	var crafts: Array = _views.get("catalog", {}).get("crafts", [])
	var sig := ",".join(crafts.map(func(c): return String(c.get("item_id", ""))))
	if sig != _craft_sig:
		_craft_sig = sig
		TownUI.clear(_craft_box)
		_crafts.clear()
		for c in crafts:
			_crafts[String(c.get("item_id", ""))] = _make_craft(String(c.get("item_id", "")))
	for c in crafts:
		var w: Dictionary = _crafts[String(c.get("item_id", ""))]
		var can := bool(c.get("can_craft", false))
		(w["name"] as Label).text = BackupsModel.craft_label(String(c.get("item_id", "")), _tx)
		(w["cost"] as Label).text = BackupsModel.cost_text(c.get("cost", {}), _tx)
		(w["why"] as Label).text = "" if can else BackupsModel.craft_reason_text(String(c.get("reason", "")), _tx)
		(w["why"] as Label).visible = not can
		(w["btn"] as Button).disabled = not can


func _on_craft(item_id: String) -> void:
	var r: Dictionary = Game.state.cmd_craft(item_id)
	if bool(r.get("ok", false)):
		_say(String(_tx.get("craft_ok", "")).format({"label": BackupsModel.craft_label(item_id, _tx)}))
	else:
		var why := BackupsModel.craft_reason_text(String(r.get("reason", "")), _tx)
		_say(TownUI.refusal(String(r.get("reason", "")), why, String(_tx.get("craft_refused", "")).format({"reason": why})))
	command_issued.emit()


# ------------------------------------------------------------------- bind ----
func bind(views: Dictionary) -> void:
	_views = views
	var bk: Dictionary = views.get("backups", {})
	# a section is filled only when the fields it reads moved (the refresh is twice a second; the sections change rarely)
	var costs := BackupsModel.staffing_costs(views, project, _vcfg.get("job_labels", {}), _tx)
	var sigs := {"death": BackupsModel.death_sig(views), "vats": BackupsModel.vats_sig(views, costs), "ossuary": BackupsModel.ossuary_sig(views)}
	if sigs["death"] != _sigs.get("death"):
		_fill_death(bk)
	if sigs["vats"] != _sigs.get("vats"):
		_fill_vats(bk, costs)
	if sigs["ossuary"] != _sigs.get("ossuary"):
		_fill_ossuary(bk)
	_sigs = sigs


func on_game_event(_ev: Dictionary) -> void:
	pass
