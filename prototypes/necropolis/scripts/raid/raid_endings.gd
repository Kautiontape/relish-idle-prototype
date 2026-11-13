class_name RaidEndings
extends RefCounted
## End-of-run flow for a raid scene: exit request/confirm, Relish's death
## (0.9 s beat), and the single `finished` emit. RefCounted, not a Node: it has
## no tree presence or per-frame work; it borrows the raid's tree for its timer.
## The result dicts stay on the raid (`_exit_result` / `_death_result`) so the
## boss scene can override them.

var ended := false      # run is over; gameplay stops (raid._ended forwards here)
var finished := false   # `finished` already emitted

var _raid: Node2D


func _init(p_raid: Node2D) -> void:
	_raid = p_raid


func request_exit() -> void:
	_raid.hud.open_exit_dialog()


func confirm_exit() -> void:
	if ended:
		return
	ended = true
	_raid.trance.force_end()
	RaidFx.ring(_raid.fx_root, _raid.relish.global_position, Palette.c("relish"), 60.0, 0.5, 4.0)
	finish(_raid._exit_result())


func on_relish_died() -> void:
	if ended:
		return
	ended = true
	_raid.trance.force_end()
	RaidFx.ring(_raid.fx_root, _raid.relish.global_position, Palette.c("danger"), 90.0, 0.8, 4.0)
	RaidFx.ring(_raid.fx_root, _raid.relish.global_position, Palette.c("relish"), 50.0, 0.8, 3.0)
	_raid.get_tree().create_timer(0.9).timeout.connect(func() -> void: finish(_raid._death_result()))


func finish(result: Dictionary) -> void:
	if finished:
		return
	finished = true
	ended = true
	Engine.time_scale = 1.0
	_raid.finished.emit(result)
	if _raid._standalone:
		_raid.standalone_apply(result)
		_raid.hud.show_result(result)
