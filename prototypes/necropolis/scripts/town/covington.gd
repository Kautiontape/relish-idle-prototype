extends Control
## COVINGTON shell: layout, view fetch on rev change, bind() to the HUD, the town view and the
## dock panels, event routing, and the one-click return to the realm.
## Contract (STATE-API 2.3): setup(args) with ids only; finished({"v": 2, "teleport_to": ""}) once.

signal finished(result: Dictionary)

const HudScript := preload("res://scripts/town/town_hud.gd")
const ViewScript := preload("res://scripts/town/town_view.gd")
const PANELS := [
	["Build", preload("res://scripts/town/panel_build.gd")],
	["Jobs", preload("res://scripts/town/panel_jobs.gd")],
	["Stances", preload("res://scripts/town/panel_stances.gd")],
	["Backups", preload("res://scripts/town/panel_backups.gd")],
	["Crypt", preload("res://scripts/town/panel_crypt.gd")],
]

var _setup_done := false
var _finished := false
var _hud: Control
var _view: Control
var _panels: Array = []
var _tabs: Array = []
var _bound: Array = []  # everything that gets bind() and on_game_event()
var _last_rev := -1
var _since_fetch := 0.0
var _dirty := false
var _refresh_s := 0.25
## Debug-only harness (`--town-demo=full|tierup`, ignored unless Game.state.debug_enabled):
## "full" binds the synthetic demo city instead of the fetched views; "tierup" fires a synthetic
## tier_up event shortly after setup. Both say so on screen.
var _demo := ""
var _tier := ""  # the last fetched town tier (the synthetic tier_up's `from`)
var _fort_names := {}  # fort id -> name, read once from view_realm (the Build tab's chips)
## Debug-only (`--town-grow=<sim_seconds>`, needs debug_enabled, no autosave and `--fixture=`/`--shot=`):
## before the first bind an autoplayer builds what the Build tab suggests, on the real TownSim, and
## skips sim time in view.grow_chunk_s steps until the target passes. `--town-grow-log` prints a line
## per chunk. `--town-zoom=<cx>,<cy>,<scale>` scales the town view's content about a point.
var _grow_label: Label
var _grow_log: Array = []  # [{t, building_id, lot_id}] of what the autoplayer built
var _grown_s := 0.0


func _ready() -> void:
	_build_ui()
	Game.game_event.connect(_on_game_event)
	if not _setup_done and get_tree().current_scene == self:
		setup({"mode": "town"})
	_standalone_check.call_deferred()


func _exit_tree() -> void:
	if Game.game_event.is_connected(_on_game_event):
		Game.game_event.disconnect(_on_game_event)


func _standalone_check() -> void:
	# change_scene_to_file can assign current_scene around _ready; re-check once settled.
	if not _setup_done and get_tree().current_scene == self:
		setup({"mode": "town"})


## args: {mode: "town"}; unknown keys (including legacy ones the router merges in) are ignored.
func setup(_args: Dictionary) -> void:
	_setup_done = true
	for f in Game.state.view_realm().get("forts", []):
		_fort_names[String(f.get("id", ""))] = String(f.get("name", ""))
	_grow()
	_zoom()
	_fetch()
	if _demo == "tierup":
		var spec: Dictionary = ConfigDb.v("town", "view", {}).get("demo_tierup", {})
		get_tree().create_timer(float(spec.get("delay_s", 0.0))).timeout.connect(
			_fire_demo_tierup.bind(String(spec.get("tier", ""))))


func _fire_demo_tierup(tier: String) -> void:
	if not is_inside_tree():
		return
	_on_game_event({"type": "tier_up", "t": 0.0, "tier": tier, "from": _tier})


## Reads `--town-demo=<mode>`; only a debug build honours it.
func _read_demo_flag() -> void:
	if not Game.state.debug_enabled:
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--town-demo="):
			var mode := arg.trim_prefix("--town-demo=")
			if mode in ["full", "tierup"]:
				_demo = mode
			else:
				printerr("Covington: unknown --town-demo=%s (expected full or tierup)" % mode)


## The value of a debug arg `--name=value` ("" absent); only a debug build reads it.
func _debug_arg(name: String) -> String:
	if not Game.state.debug_enabled:
		return ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.trim_prefix("--%s=" % name)
	return ""


## `--town-grow=<sim_seconds>`: plays the town the way the suggestion tells a new player to (the top
## buildable row on its nearest lot), skipping view.grow_chunk_s of sim between moves.
func _grow() -> void:
	var raw := _debug_arg("town-grow")
	if raw == "" or not raw.is_valid_float():
		return
	var args := OS.get_cmdline_user_args()
	var harness := false
	for a in args:
		if a.begins_with("--fixture=") or a.begins_with("--shot="):
			harness = true
	if Game.autosave_enabled or not harness:
		printerr("Covington: --town-grow refused (needs --fixture= or --shot= alongside, and no autosave)")
		return
	var cfg: Dictionary = ConfigDb.v("town", "view", {})
	var chunk := maxf(float(cfg.get("grow_chunk_s", 60.0)), 1.0)
	var target := float(raw)
	var cfgs := {"town": ConfigDb.data.get("town", {}), "buildings_view": ConfigDb.data.get("buildings_view", {}),
		"buildings": ConfigDb.data.get("buildings", {}), "economy": ConfigDb.data.get("economy", {})}
	var log_chunks := "--town-grow-log" in args
	while _grown_s < target:
		var pick := BuildSort.autoplay_pick(_fetch_views(), cfgs)
		if not pick.is_empty():
			var r: Dictionary = Game.state.cmd_build(pick["building_id"], pick["lot_id"])
			if bool(r.get("ok", false)):
				_grow_log.append({"t": _grown_s, "building_id": pick["building_id"], "lot_id": pick["lot_id"]})
		Game.state.cmd_debug_skip_time(chunk)
		_grown_s += chunk
		if log_chunks:
			var town: Dictionary = Game.state.view_town()
			print("GROW t=%d tier=%s buildings=%d built=%d workers=%.1f/%.1f idle=%.1f muster=%.3f living=%.1f/%.0f" % [_grown_s, town["tier"],
				(town["buildings"] as Array).size(), _grow_log.size(), town["workers"]["total"], town["workers"]["steady"],
				town["workers"]["idle"], town["workers"]["muster"], town["living"], town["living_cap"]])
	if log_chunks:
		var tw: Dictionary = Game.state.view_town()
		var rates := []
		for r in Game.state.view_hud().get("rates", []):
			if r["id"] in ["gold", "bone", "bodies"]:
				rates.append("%s %+.3f/s" % [r["id"], float(r["rate"])])
		print("GROWSTATE t=%d tier=%s buildings=%s workers=%.1f steady=%.1f living=%.1f/%.0f %s gold=%.1f bone=%.1f bodies=%.1f next=%s" % [_grown_s,
			tw["tier"], ",".join((tw["buildings"] as Array).map(func(b): return "%s@%s(%s)" % [b["building_id"], b["lot_id"], b["state"]])),
			tw["workers"]["total"], tw["workers"]["steady"], tw["living"], tw["living_cap"], ", ".join(rates), tw["gold"], tw["bone"], tw["bodies"], str(tw["next_tier"])])
	var h := int(_grown_s) / 3600
	var m := (int(_grown_s) % 3600) / 60
	_grow_label = TownUI.label(BuildSort.fmt(String(cfg.get("grow_text", "")),
		{"h": h, "mm": "%02d" % m, "n": _grow_log.size()}), 14, "select")
	_grow_label.position = Vector2(12, 8)
	_grow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grow_label.add_theme_stylebox_override("normal", TownUI.panel_box())
	_view.add_child(_grow_label)


## `--town-zoom=<cx>,<cy>,<scale>` (debug): the town view's content scaled about a point.
func _zoom() -> void:
	var p := _debug_arg("town-zoom").split(",")
	if p.size() != 3 or not p[2].is_valid_float() or float(p[2]) <= 0.0:
		return
	_view.set_zoom(Vector2(float(p[0]), float(p[1])), float(p[2]))
	var cfg: Dictionary = ConfigDb.v("town", "view", {})
	var tag := TownUI.label(BuildSort.fmt(String(cfg.get("zoom_text", "")), {"scale": p[2]}), 14, "select")
	tag.position = Vector2(12, 8 if _grow_label == null and _demo == "" else 40)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_stylebox_override("normal", TownUI.panel_box())
	_view.add_child(tag)


func _build_ui() -> void:
	var cfg: Dictionary = ConfigDb.v("town", "view", {})
	_refresh_s = float(cfg.get("refresh_s", 0.25))
	_read_demo_flag()
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_hud = HudScript.new()
	_hud.custom_minimum_size = Vector2(0, float(cfg.get("hud_h", 72)))
	root.add_child(_hud)
	_hud.return_pressed.connect(_on_return)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	_view = ViewScript.new()
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_view)

	var dock := PanelContainer.new()
	dock.custom_minimum_size = Vector2(float(cfg.get("dock_w", 560)), 0)
	dock.add_theme_stylebox_override("panel", TownUI.panel_box())
	body.add_child(dock)
	var col := VBoxContainer.new()
	dock.add_child(col)
	var tab_row := HBoxContainer.new()
	col.add_child(tab_row)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(stack)

	for i in PANELS.size():
		var p: Control = PANELS[i][1].new()
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(p)
		_panels.append(p)
		var b := TownUI.button(PANELS[i][0])
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, maxf(TownUI.MIN_TARGET, float(cfg.get("tab_h", 44))))
		b.pressed.connect(_select_tab.bind(i))
		tab_row.add_child(b)
		_tabs.append(b)
	_bound = [_hud, _view] + _panels
	for n in _bound:
		n.command_issued.connect(_on_command_issued)
	var build: Control = _panels[0]
	build.placement_changed.connect(_view.set_placement)
	build.lot_selected.connect(_view.set_selected_lot)
	_view.lot_clicked.connect(build.on_lot_clicked)
	_view.right_clicked.connect(build.dismiss)
	# In-scene building: the lot card, the hover outline, the day-1 suggestion, queue ghosts, the build flash.
	build.attach_card(_view.card)
	build.card_opened.connect(_view.open_card)
	build.card_closed.connect(_view.close_card)
	build.hover_lots.connect(_view.set_hover_lots)
	build.suggestion_changed.connect(_view.set_suggestion)
	build.queue_changed.connect(_view.set_queue)
	build.build_started.connect(_view.flash_lot)
	_view.suggestion_dismissed.connect(build.on_suggestion_dismissed)
	_select_tab(_debug_tab())
	if _demo != "":
		var tag := TownUI.label("SYNTHETIC DEMO TOWN (debug)" if _demo == "full" else "SYNTHETIC TIER-UP EVENT (debug)",
			14, "select")
		tag.position = Vector2(12, 8)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_theme_stylebox_override("normal", TownUI.panel_box())
		_view.add_child(tag)


## Reads `--town-tab=<build|jobs|stances|backups|crypt>`; only a debug build honours it. Tab 0 otherwise.
func _debug_tab() -> int:
	if not Game.state.debug_enabled:
		return 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--town-tab="):
			var i := ["build", "jobs", "stances", "backups", "crypt"].find(arg.trim_prefix("--town-tab="))
			if i >= 0:
				return i
			printerr("Covington: unknown --town-tab=%s (expected build, jobs, stances, backups or crypt)" % arg.trim_prefix("--town-tab="))
	return 0


func _select_tab(i: int) -> void:
	for k in _panels.size():
		_panels[k].visible = (k == i)
		_tabs[k].set_pressed_no_signal(k == i)
		_tabs[k].add_theme_stylebox_override("normal", TownUI.button_box("active" if k == i else "normal"))


func _on_command_issued() -> void:
	_dirty = true


func _process(delta: float) -> void:
	if not _setup_done:
		return
	_since_fetch += delta
	if _dirty or (Game.state.rev != _last_rev and _since_fetch >= _refresh_s):
		_fetch()


func _fetch() -> void:
	_last_rev = Game.state.rev
	_since_fetch = 0.0
	_dirty = false
	var views := _fetch_views()
	_tier = String(views["town"].get("tier", ""))
	for n in _bound:
		n.bind(views)


func _fetch_views() -> Dictionary:
	var s = Game.state
	var views := {
		"town": s.view_town(), "hud": s.view_hud(), "rates": s.view_rates(), "catalog": s.view_catalog(),
		"stances": s.view_stances(), "backups": s.view_backups(),
		"inventory": s.view_inventory(), "big_undead": s.view_big_undead(),
		"relish": s.view_relish(), "vei": s.view_vei(), "fort_names": _fort_names,
	}
	if _demo == "full":
		views = TownStandins.demo_views(views, ConfigDb.data.get("buildings", {}), ConfigDb.data.get("town", {}))
	return views


func _on_game_event(ev: Dictionary) -> void:
	for n in _bound:
		if n.has_method("on_game_event"):
			n.on_game_event(ev)


func _on_return() -> void:
	if _finished:
		return
	_finished = true
	_hud.set_return_enabled(false)
	finished.emit({"v": 2, "teleport_to": ""})
