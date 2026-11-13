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
	_fetch()


func _build_ui() -> void:
	var cfg: Dictionary = ConfigDb.v("town", "view", {})
	_refresh_s = float(cfg.get("refresh_s", 0.25))
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
	_select_tab(0)


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
	var s = Game.state
	_last_rev = s.rev
	_since_fetch = 0.0
	_dirty = false
	var views := {
		"town": s.view_town(), "hud": s.view_hud(), "catalog": s.view_catalog(),
		"stances": s.view_stances(), "backups": s.view_backups(),
		"inventory": s.view_inventory(), "big_undead": s.view_big_undead(),
		"relish": s.view_relish(), "vei": s.view_vei(),
	}
	for n in _bound:
		n.bind(views)


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
