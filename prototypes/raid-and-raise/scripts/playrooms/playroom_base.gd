class_name PlayroomBase
extends Node2D
## A playroom: one room, one mechanic, infinitely repeatable (prototype
## harness, not part of the design doc). Each room snapshots the debug toggles
## on entry and restores them on exit, so rooms can default to pacifist/freeze
## without polluting the raid.

const ROOM_W := 660.0
const ROOM_H := 1100.0

var battlefield: Battlefield
var trance: TranceController
var command: CommandController
var ui: CanvasLayer
var controls: HFlowContainer
var info: Label
var _debug_snapshot := {}

func _ready() -> void:
	_debug_snapshot = GameState.debug.duplicate()
	battlefield = Battlefield.new()
	add_child(battlefield)
	battlefield.build_arena(PackedVector2Array([
		Vector2(-ROOM_W / 2, 0), Vector2(ROOM_W / 2, 0),
		Vector2(ROOM_W / 2, -ROOM_H), Vector2(-ROOM_W / 2, -ROOM_H),
	]), _obstacles())
	battlefield.make_camera(Vector2(0, -ROOM_H / 2))
	trance = TranceController.new()
	trance.battlefield = battlefield
	add_child(trance)
	command = CommandController.new()
	command.battlefield = battlefield
	add_child(command)
	_build_ui()
	_setup()

func _exit_tree() -> void:
	GameState.debug = _debug_snapshot

func _setup() -> void:
	pass  # rooms override

func _obstacles() -> Array:
	return []  # rooms override: interior polygons carved from the navmesh

func room_point(nx: float, ny: float) -> Vector2:
	return Vector2(-ROOM_W / 2 + nx * ROOM_W, -ROOM_H + ny * ROOM_H)

func handle_input(ev: InputEvent) -> bool:
	if trance.handle_input(ev):
		return true
	return command.handle_input(ev)

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 15
	add_child(ui)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_to_group("rr_ui_block")
	panel.modulate = Color(1, 1, 1, 0.92)
	ui.add_child(panel)
	controls = HFlowContainer.new()
	controls.alignment = FlowContainer.ALIGNMENT_CENTER
	panel.add_child(controls)
	info = Label.new()
	info.position = Vector2(12, 50)
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	info.size = Vector2(420, 300)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.add_child(info)

func add_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.focus_mode = Control.FOCUS_NONE  # Space belongs to the Trance
	b.pressed.connect(cb)
	controls.add_child(b)
	return b

func add_slider(label: String, from: float, to: float, step: float, value: float, cb: Callable) -> HSlider:
	var box := VBoxContainer.new()
	var l := Label.new()
	l.text = "%s: %s" % [label, str(value)]
	l.add_theme_font_size_override("font_size", 13)
	box.add_child(l)
	var s := HSlider.new()
	s.focus_mode = Control.FOCUS_NONE
	s.min_value = from
	s.max_value = to
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(150, 24)
	s.value_changed.connect(func(v):
		l.text = "%s: %s" % [label, str(v)]
		cb.call(v))
	box.add_child(s)
	controls.add_child(box)
	return s

func spawn_relish(at: Vector2) -> RRUnit:
	return battlefield.spawn_unit(EntityFactory.make_relish(), at)

## A unit that stands still and (optionally) can't hurt anyone — pure observation target.
func spawn_bag(at: Vector2, beef: float, name_label: String = "") -> RRUnit:
	var u := EntityFactory.make_custom({
		"kind": RRUnit.Kind.ENEMY,
		"faction": RRUnit.Faction.ENEMY,
		"stats": {"beef": beef},
		"base_speed": 0.0,
		"base_hp": 60.0,
		"cadence": 0.0,
		"name": name_label,
		"color": Color(0.6, 0.35, 0.3),
	})
	return battlefield.spawn_unit(u, at)
