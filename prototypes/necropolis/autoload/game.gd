extends Node
## Thin shell over GameState (scripts/sim/game_state.gd): feeds it real time,
## and turns its drained events into signals. Ticks regardless of which scene is
## active; this is an idle game, the realm never sleeps.

signal game_event(ev: Dictionary)
signal relish_respawned(with_vat: bool)
signal victory
signal defeat_boss

## Created once, never replaced.
var state := GameState.new()
var _autosave_acc := 0.0  # real seconds since the last autosave


func _ready() -> void:
	state.setup(ConfigDb.data)
	state.debug_enabled = OS.is_debug_build()
	randomize()
	state.cmd_new_game(randi())


func _process(delta: float) -> void:
	# Real time: trance's Engine.time_scale must never slow the realm.
	var real := delta / maxf(0.05, Engine.time_scale)
	state.tick(real * state.time_scale, state.max_substeps_per_frame())
	_autosave_acc += real  # real seconds only: neither the sim speed nor a pause stretches it
	if _autosave_acc >= state.autosave_s():
		autosave()
	for ev: Dictionary in state.drain_events():
		game_event.emit(ev)
		match ev["type"]:
			"relish_respawned":
				relish_respawned.emit(ev["with_clone"])
			"vei_result":
				if ev["won"]:
					victory.emit()
				else:
					defeat_boss.emit()


## Writes the "auto" slot now (the router calls it after every scene swap) and restarts the
## 30 s clock. Returns cmd_save's result; autosaved / save_failed reach scenes as game_event.
func autosave() -> Dictionary:
	_autosave_acc = 0.0
	return state.cmd_save("auto")


# Legacy, for scenes not yet on Game.state views; new code reads Game.state.
var realm: RealmSim:
	get: return state.realm
var field: InfluenceField:
	get: return state.field
var towns: Array:
	get: return state.towns
var green_towns: int:
	get: return state.green_towns
var army: Dictionary:
	get: return state.army
var res: Dictionary:
	get: return state.res
var town: Dictionary:
	get: return state.town
var assignments: Dictionary:
	get: return state.assignments
var idle_undead: int:
	get: return state.idle_undead
var gather: Dictionary:
	get: return state.gather
var won: bool:
	get: return state.won
var stats: Dictionary:
	get: return state.stats
var time_scale: float:
	get: return state.time_scale
	set(v): state.time_scale = v


func quality() -> float: return state.quality()
func raiding_fort_id() -> String: return state.raiding_fort_id()
func raid_seed(fort_id: String) -> Dictionary: return state.raid_seed(fort_id)
func begin_raid(fort_id: String) -> void: state.begin_raid(fort_id)
func end_raid() -> void: state.end_raid()
func apply_raid_result(r: Dictionary) -> void: state.apply_raid_result(r)
func auto_resolve_raid(fort_id: String) -> void: state.auto_resolve_raid(fort_id)
func town_snapshot() -> Dictionary: return state.town_snapshot()
func apply_town_result(r: Dictionary) -> void: state.apply_town_result(r)
func boss_seed() -> Dictionary: return state.boss_seed()
func apply_boss_result(r: Dictionary) -> void: state.apply_boss_result(r)
func auto_resolve_boss() -> void: state.auto_resolve_boss()
