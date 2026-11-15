extends Node

## Thin shell over GameState (scripts/sim/game_state.gd): feeds it real time,
## and turns its drained events into signals. Ticks regardless of which scene is
## active; this is an idle game, the realm never sleeps.

const BootRule := preload("res://scripts/sim/boot_rule.gd")

signal game_event(ev: Dictionary)
signal relish_respawned(with_vat: bool)
signal victory
signal defeat_boss

## Created once, never replaced.
var state := GameState.new()
var _autosave_acc := 0.0  # real seconds since the last autosave
## False for a harness/test session (--shot, --new-game, --fixture): autosave() writes nothing.
## Set once in _ready; read-only by rule.
var autosave_enabled := true


func _ready() -> void:
	state.setup(ConfigDb.data)
	state.debug_enabled = OS.is_debug_build()
	randomize()
	_boot()


## Boot rule (STATE-API 2.1): a harness arg disables autosave for the session and starts a
## fresh or fixture game; a normal launch resumes the autosave, else starts a new game.
func _boot() -> void:
	var harness := BootRule.is_harness(OS.get_cmdline_user_args(), OS.get_cmdline_args(), DisplayServer.get_name() == "headless")
	var fixture := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="):
			fixture = arg.trim_prefix("--fixture=")
	autosave_enabled = not harness
	if harness:
		if fixture != "":
			var r := state.cmd_debug_load_fixture(fixture)
			if r["ok"]:
				return
			printerr("Game: --fixture=%s refused (%s); starting a new game" % [fixture, r["reason"]])
		state.cmd_new_game(randi())
	else:
		# Continue: the time since the save is caught up in chunks over the first frames (IDLE §4;
		# view_catchup drives a progress screen), so a week away doesn't freeze the window
		var r := state.cmd_load("auto", true)
		if not r["ok"]:
			if r["reason"] == "bad_version":
				# A newer build wrote it (worktrees share user://): never overwrite it.
				autosave_enabled = false
				push_warning("Game: auto.json is from a newer save version; autosave is off this session")
			state.cmd_new_game(randi())


func _process(delta: float) -> void:
	# Real time: trance's Engine.time_scale must never slow the realm. tick() itself sends a frame whose
	# real time (its dt / time_scale) is above idle.gap_s through catch-up, and runs a catch-up's chunks.
	var real := delta / maxf(0.05, Engine.time_scale)
	state.tick(real * state.time_scale, state.max_substeps_per_frame())
	_autosave_acc += real  # real seconds only: neither the sim speed nor a pause stretches it
	if _autosave_acc >= state.autosave_s() and not state.catching_up():
		autosave()  # (waits out a catch-up: a save then would lose the time still to run)
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
## In a harness session returns {ok: false, reason: "disabled"} and writes nothing. While a catch-up runs
## it writes nothing and returns {ok: false, reason: "catching_up"} with no save_failed event, and the
## 30 s clock stays due, so the save follows the catch-up.
func autosave() -> Dictionary:
	if not autosave_enabled:
		_autosave_acc = 0.0
		return {"ok": false, "reason": "disabled"}
	if state.catching_up():
		return {"ok": false, "reason": "catching_up"}
	_autosave_acc = 0.0
	return state.cmd_save("auto")


# Legacy, for scenes not yet on Game.state views; new code reads Game.state (STATE-API §2.2).
var realm: RealmSim:
	get: return state.realm
var field: InfluenceField:
	get: return state.field
var towns: Array:
	get: return state.towns
var green_towns: int:
	get: return state.green_towns
var won: bool:
	get: return state.won
var stats: Dictionary:
	get: return state.stats
var time_scale: float:
	get: return state.time_scale
	set(v): state.time_scale = v


func raiding_fort_id() -> String: return state.raiding_fort_id()
