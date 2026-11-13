extends Node
## Thin shell over GameState (scripts/sim/game_state.gd): feeds it real time,
## and turns its drained events into signals. Ticks regardless of which scene is
## active; this is an idle game, the realm never sleeps.

signal game_event(ev: Dictionary)
signal relish_respawned(with_vat: bool)
signal victory
signal defeat_boss

## Any of these CLI user args makes the session a harness/test session (STATE-API 2.1).
## --reduced-motion is a player accessibility flag and is deliberately not listed.
const DEV_ARGS: Array[String] = ["--shot", "--new-game", "--fixture", "--teleport", "--scene",
		"--select", "--speed", "--cheat", "--finish-raid", "--trace", "--clicks"]

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
	var harness := false
	var fixture := ""
	for arg in OS.get_cmdline_user_args():
		for pre in DEV_ARGS:
			if arg == pre or arg.begins_with(pre + "="):
				harness = true
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
		var r := state.cmd_load("auto")
		if not r["ok"]:
			if r["reason"] == "bad_version":
				# A newer build wrote it (worktrees share user://): never overwrite it.
				autosave_enabled = false
				push_warning("Game: auto.json is from a newer save version; autosave is off this session")
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
## In a harness session returns {ok: false, reason: "disabled"} and writes nothing.
func autosave() -> Dictionary:
	_autosave_acc = 0.0
	if not autosave_enabled:
		return {"ok": false, "reason": "disabled"}
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
# legacy: delete when map drops the reads (world_map.gd, map_routes.gd). Fresh dicts built from the
# new state on every read (GameState.legacy_stores); writes to them change nothing.
var army: Dictionary:
	get: return state.legacy_stores()["army"]
var res: Dictionary:
	get: return state.legacy_stores()["res"]
var town: Dictionary:
	get: return state.legacy_stores()["town"]
var assignments: Dictionary:
	get: return state.legacy_stores()["assignments"]
var idle_undead: int:
	get: return state.legacy_stores()["idle_undead"]
var gather: Dictionary:
	get: return state.legacy_stores()["gather"]
var won: bool:
	get: return state.won
var stats: Dictionary:
	get: return state.stats
var time_scale: float:
	get: return state.time_scale
	set(v): state.time_scale = v


func quality() -> float: return state.quality()  # legacy: delete when map drops the call (world_map.gd)
func raiding_fort_id() -> String: return state.raiding_fort_id()
# legacy: delete each when map drops the call (scripts/main.gd calls the GameState members these
# forward to, for unported scenes; STATE-API §2.2)
func raid_seed(fort_id: String) -> Dictionary: return state.raid_seed(fort_id)
func town_snapshot() -> Dictionary: return state.town_snapshot()
func apply_town_result(r: Dictionary) -> void: state.apply_town_result(r)
func boss_seed() -> Dictionary: return state.boss_seed()
