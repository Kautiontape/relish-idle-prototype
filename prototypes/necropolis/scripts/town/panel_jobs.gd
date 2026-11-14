extends VBoxContainer
## Jobs tab (MECHANICS §4.5): the job ladder as a readable queue (drag a row, or use its arrows,
## to reorder; `cmd_set_job_priority`) and one staffing-cap stepper per building with job slots
## (`cmd_set_staff_cap`). Rows are built once and updated in place on every bind, so drags, hover
## and held buttons survive the shell's ~4 Hz refetch. After a reorder or cap change the rows whose
## staffing changed flash for one Pulse beat on the bind that shows it. Before a move, hovering a
## drop position (or an arrow) previews the hands it would move ("Mill +2 hands, Pit −2") from
## TownSim's own allocation (through the shell's one projection helper) or, until that exists, the marked stand-in.

signal command_issued

const RowScript := preload("res://scripts/town/job_row.gd")

## The shell's cached staffing projection: project.call(order, extra := {}) -> the jobs array.
var project: Callable
var _vcfg: Dictionary = {}
var _bcfg: Dictionary = {}
var _bview: Dictionary = {}
var _summary: Label
var _status: Label
var _ladder_box: VBoxContainer
var _caps_box: VBoxContainer
var _rows: Dictionary = {}  # job id -> job_row
var _order: Array = []  # the ladder as last bound
var _caps: Dictionary = {}  # lot id -> {box, name, count, minus, value, plus, cap, slots}
var _caps_sig := ""
var _prev_staffed: Dictionary = {}
var _armed := 0
var _flashing: Dictionary = {}
var _town: Dictionary = {}
var _stances: Dictionary = {}
var _views: Dictionary = {}
var _preview: Label
var _hover := {}  # the hovered move: {src, job, dir} (an arrow) or {src, job, target, lower} (a drop); {} = none


func _ready() -> void:
	var db: Dictionary = ConfigDb.data
	_vcfg = ConfigDb.v("town", "view", {})
	_bcfg = db.get("buildings", {})
	_bview = db.get("buildings_view", {})
	add_theme_constant_override("separation", 6)
	_summary = _wrap("", 14)
	add_child(_summary)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	scroll.add_child(body)
	body.add_child(_wrap(_t("ladder_header"), 12, "text_dim"))
	_preview = TownUI.label(_t("preview_hint"), 14, "text_dim")  # one reserved line: the rows never shift mid-drag
	_preview.clip_text = true
	_preview.custom_minimum_size = Vector2(40, 22)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_preview)
	_ladder_box = VBoxContainer.new()
	_ladder_box.add_theme_constant_override("separation", 3)
	body.add_child(_ladder_box)
	var h := TownUI.label(_t("cap_header"), 16)
	h.add_theme_constant_override("line_spacing", 0)
	body.add_child(h)
	_caps_box = VBoxContainer.new()
	_caps_box.add_theme_constant_override("separation", 3)
	body.add_child(_caps_box)
	_status = _wrap("", 14, "select")
	add_child(_status)


func _t(key: String) -> String:
	return String(_vcfg.get("behaviour", {}).get(key, key))


func _wrap(text: String, size: int, key := "text") -> Label:
	var l := TownUI.label(text, size, key)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _job_label(job: String) -> String:
	return String(_vcfg.get("job_labels", {}).get(job, job.capitalize()))


## "Charnel House" for haul, "construction sites" for build, from buildings.json `jobs`.
func _site_text(job: String) -> String:
	var names: Array = []
	for bid in _bcfg:
		if (_bcfg[bid].get("jobs", {}) as Dictionary).has(job):
			names.append(BuildSort.label_of(bid, _bview))
	if not names.is_empty():
		return ", ".join(names)
	return String(_vcfg.get("job_site_text", {}).get(job, _vcfg.get("job_site_text", {}).get("none", "")))


func bind(views: Dictionary) -> void:
	if _ladder_box == null:
		return
	_views = views
	_town = views.get("town", {})
	_stances = views.get("stances", {})
	var ladder: Array = _town.get("ladder", [])
	var jobs := {}
	for j in _town.get("jobs", []):
		jobs[String(j.get("id", ""))] = j
	var w: Dictionary = _town.get("workers", {})
	var idle := float(w.get("idle", 0.0))
	var s := String(_t("summary")).format({"total": roundi(float(w.get("total", 0.0))), "idle": roundi(idle)})
	if idle >= 0.5:
		s += ". " + _t("summary_muster")
	_summary.text = s
	_bind_ladder(ladder, jobs)
	_bind_caps(_town.get("buildings", []))
	_flash_changed(_town.get("jobs", []))
	if not _hover.is_empty():
		_refresh_preview()  # against the ladder as it stands now (an arrow press moved it)


func _bind_ladder(ladder: Array, jobs: Dictionary) -> void:
	for id in ladder:
		if not _rows.has(id):
			var r: PanelContainer = RowScript.new()
			_ladder_box.add_child(r)
			r.setup(String(id), _vcfg.get("slot_tick_px", [3.0, 9.0]))
			r.dropped.connect(_on_dropped)
			r.nudged.connect(_on_nudged)
			r.hover_drop.connect(_on_hover_drop)
			r.hover_nudge.connect(_on_hover_nudge)
			r.hover_end.connect(_on_hover_end)
			_rows[id] = r
	var moves := {}
	for m in TownBehaviour.ladder_moves(ladder, _town.get("ladder_effective", [])):
		moves[m["job"]] = m
	var dragging := is_inside_tree() and get_viewport().gui_is_dragging()
	for i in ladder.size():
		var id := String(ladder[i])
		var row: PanelContainer = _rows[id]
		if not dragging and row.get_index() != i:
			_ladder_box.move_child(row, i)
		var j: Dictionary = jobs.get(id, {})
		var site := _site_text(id) if int(j.get("slots", 0)) > 0 else _t("no_building").format({"site": _site_text(id)})
		row.update(i + 1, i == ladder.size() - 1, _job_label(id), site,
			float(j.get("staffed", 0.0)), int(j.get("slots", 0)), _move_note(id, moves.get(id, {})))
	_order = ladder.duplicate()


## "↑ Harvest moved Haul to the top (acts as #1)" when a stance moved `job` up; "↓ ..." when down.
func _move_note(job: String, m: Dictionary) -> String:
	if m.is_empty():
		return ""
	var tail := " (acts as #%d)" % (int(m["to"]) + 1)
	if int(m["to"]) < int(m["from"]):
		var who := _t("moved_by_generic").format({"job": _job_label(job)})
		for st in _stances.get("stances", []):
			var spec = _vcfg.get("stance_jobs", {}).get(String(st.get("id", "")), [])
			if bool(st.get("on", false)) and bool(st.get("active", false)) and spec is Array and spec.has(job):
				var nm := String(_vcfg.get("stance_labels", {}).get(String(st["id"]), String(st["id"]).capitalize()))
				who = _t("moved_by").format({"stance": nm, "job": _job_label(job)})
				break
		return "↑ " + who + tail
	return "↓ " + _t("moved_down") + tail


# ---- the move preview ----
## The allocation for `order`, from the shell's one cached helper (set at setup, Covington.project_staffing).
func _project(order: Array) -> Array:
	return project.call(order) if project.is_valid() else []


func _on_hover_drop(job: String, target: String, lower: bool) -> void:
	_hover = {"src": target, "job": job, "target": target, "lower": lower}
	_refresh_preview()


func _on_hover_nudge(job: String, dir: int) -> void:
	_hover = {"src": job, "job": job, "dir": dir}
	_refresh_preview()


func _on_hover_end(source: String) -> void:
	if not _hover.is_empty() and source == String(_hover["src"]):
		_hover = {}
		_preview.text = _t("preview_hint")
		_preview.tooltip_text = ""
		_preview.add_theme_color_override("font_color", Palette.c("text_dim"))


## "If you move it: Mill +2 hands, Pit −2": the hovered move against today's ladder, as counts from
## the projections of today's order and the moved one.
func _refresh_preview() -> void:
	var i := _order.find(String(_hover["job"]))
	if i < 0:
		return
	var order := TownBehaviour.move(_order, i, i + int(_hover["dir"])) if _hover.has("dir") \
		else TownBehaviour.move(_order, i, TownBehaviour.drop_index(i, _order.find(String(_hover["target"])), bool(_hover["lower"])))
	var hands := ""
	if order != _order:
		hands = TownBehaviour.diff_text(TownBehaviour.staffing_diff(_project(_order), _project(order)),
			_vcfg.get("job_labels", {}), _t("hand"), _t("hands"))
	_preview.text = _t("preview").format({"hands": hands}) if hands != "" else _t("preview_none")
	_preview.tooltip_text = _preview.text
	_preview.add_theme_color_override("font_color", Palette.c("select" if hands != "" else "text"))


# ---- reorder ----
func _on_dropped(job: String, target: String, lower: bool) -> void:
	var i := _order.find(job)
	var k := _order.find(target)
	if i < 0 or k < 0:
		return
	_issue(TownBehaviour.move(_order, i, TownBehaviour.drop_index(i, k, lower)))


func _on_nudged(job: String, dir: int) -> void:
	var i := _order.find(job)
	if i < 0:
		return
	_issue(TownBehaviour.move(_order, i, i + dir))


func _issue(order: Array) -> void:
	if order == _order:
		return
	var r: Dictionary = Game.state.cmd_set_job_priority(order)
	_report(r)
	_armed = int(_vcfg.get("behaviour", {}).get("arm_binds", 12))
	command_issued.emit()


func _report(r: Dictionary) -> void:
	if bool(r.get("ok", false)):
		_status.text = ""
		return
	var why := String(r.get("reason", ""))
	var refusals: Dictionary = _vcfg.get("behaviour", {}).get("refusals", {})
	_status.text = String(refusals.get(why, refusals.get("_unknown", why)))


# ---- staffing caps ----
func _bind_caps(buildings: Array) -> void:
	var rows: Array = []
	for b in buildings:
		if int(b.get("slots", 0)) > 0:
			rows.append(b)
	var sig := ",".join(rows.map(func(b: Dictionary) -> String: return str(b.get("lot_id", ""))))
	if sig != _caps_sig:
		_caps_sig = sig
		TownUI.clear(_caps_box)
		_caps = {}
		for b in rows:
			_make_cap_row(String(b["lot_id"]), String(b.get("building_id", "")))
	for b in rows:
		var c: Dictionary = _caps[String(b["lot_id"])]
		var slots := int(b["slots"])
		var cap := int(b.get("staff_cap", -1))
		c["slots"] = slots
		c["cap"] = cap
		(c["count"] as Label).text = "%d/%d" % [roundi(float(b.get("staffed", 0.0))), slots]
		(c["value"] as Label).text = TownBehaviour.cap_text(cap, slots, _t("cap_all"))


func _make_cap_row(lot: String, bid: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_caps_box.add_child(row)
	var nm := TownUI.label("%s  (%s)" % [BuildSort.label_of(bid, _bview), TownModel.lot_name(lot, _vcfg)], 14)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(0, TownUI.MIN_TARGET)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(nm)
	var count := TownUI.label("", 14)
	count.custom_minimum_size = Vector2(44, TownUI.MIN_TARGET)
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(count)
	var minus := TownUI.button("−")
	minus.custom_minimum_size = Vector2(TownUI.MIN_TARGET, TownUI.MIN_TARGET)
	row.add_child(minus)
	var value := TownUI.label("", 16)
	value.custom_minimum_size = Vector2(40, TownUI.MIN_TARGET)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	var plus := TownUI.button("+")
	plus.custom_minimum_size = Vector2(TownUI.MIN_TARGET, TownUI.MIN_TARGET)
	row.add_child(plus)
	var c := {"box": row, "name": nm, "count": count, "minus": minus, "value": value, "plus": plus, "cap": -1, "slots": 0}
	_caps[lot] = c
	minus.pressed.connect(_on_cap.bind(lot, -1))
	plus.pressed.connect(_on_cap.bind(lot, 1))


func _on_cap(lot: String, dir: int) -> void:
	var c: Dictionary = _caps.get(lot, {})
	if c.is_empty():
		return
	var next := TownBehaviour.cap_step(int(c["cap"]), int(c["slots"]), dir)
	var r: Dictionary = Game.state.cmd_set_staff_cap(lot, next)
	_report(r)
	_armed = int(_vcfg.get("behaviour", {}).get("arm_binds", 12))
	command_issued.emit()


# ---- the one-beat flash on rows whose staffing changed ----
func _flash_changed(jobs: Array) -> void:
	var eps := float(_vcfg.get("behaviour", {}).get("changed_eps", 0.05))
	var changed := TownBehaviour.staffing_changes(_prev_staffed, jobs, eps)
	if _armed > 0:
		_armed -= 1
		if not changed.is_empty():
			_armed = 0
			for id in changed:
				_start_flash(String(id))
	_prev_staffed = {}
	for j in jobs:
		_prev_staffed[String(j.get("id", ""))] = float(j.get("staffed", 0.0))


func _start_flash(job: String) -> void:
	var row = _rows.get(job)
	if row == null or not is_inside_tree():
		return
	_flashing[job] = true
	row.set_flash(true)
	# one Pulse beat, then back (the highlight is static, so reduced motion shows the same thing)
	var beat_s := maxf(Pulse.tempo_ms / 1000.0, 0.2)
	get_tree().create_timer(beat_s).timeout.connect(func() -> void:
		_flashing.erase(job)
		if is_instance_valid(row):
			row.set_flash(false))


func on_game_event(_ev: Dictionary) -> void:
	pass
