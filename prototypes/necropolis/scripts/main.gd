extends Node
## Scene router (STATE-API 2.3): one active scene at a time. Every scene gets setup(args)
## with ids only and emits finished(result); every exit routes through here.
## E1 compatibility: scenes not yet ported also get their legacy seed keys merged into args.

const MAP := "res://scenes/map/WorldMap.tscn"
const RAID := "res://scenes/raid/Raid.tscn"
const TOWN := "res://scenes/town/Covington.tscn"
const BOSS := "res://scenes/boss/VeiBoss.tscn"

var current: Node = null


func _ready() -> void:
	_open_map()


func _open_map() -> void:
	_swap(MAP, {"mode": "map"})


## Map or town must never be open with a run open: forfeit one if it is.
func _forfeit_open_run() -> void:
	if Game.state.view_relish().get("run_id", -1) != -1:
		push_warning("necropolis: router forfeited an open run before opening the map or town")
		Game.state.cmd_abort_dungeon()


## Frees the old scene and opens `path`. On a missing or unloadable scene: forfeits any open
## run and falls back to the map (unless the map itself is what failed).
func _swap(path: String, args: Dictionary) -> void:
	Engine.time_scale = 1.0
	if current != null:
		current.queue_free()
		current = null
	var packed := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if packed == null:
		push_warning("necropolis: scene unavailable " + path)
		Game.state.cmd_abort_dungeon()
		if path != MAP:
			_open_map()
		return
	if path == MAP or path == TOWN:
		_forfeit_open_run()
	var node: Node = packed.instantiate()
	current = node
	if node.has_signal("finished"):
		node.finished.connect(_on_finished.bind(node, path))
	add_child(node)
	if node.has_method("setup"):
		node.setup(args)
	Game.autosave()


func _on_finished(result: Dictionary, emitter: Node, path: String) -> void:
	if emitter != current or emitter.has_meta("router_done"):
		return  # a late or duplicate emit from a scene that is no longer current
	emitter.set_meta("router_done", true)  # one handled emit per scene
	var legacy := not result.has("v")
	match path:
		MAP:
			var id := str(result.get("teleport_to", ""))
			if legacy and (id == "vei" or id == "covington" or not Game.state.realm.fort_by_id(id).is_empty()):
				Game.state.legacy_teleport_relish(id)
			_teleport(id)
		TOWN:
			if legacy:
				Game.state.apply_town_result(result)
			_teleport(str(result.get("teleport_to", "")))
		RAID:
			_apply("raid", result, Game.state.view_dungeon_seed(Game.state.raiding_fort_id()))
		BOSS:
			_apply("boss", result, Game.state.view_boss_seed())


func _teleport(id: String) -> void:
	var s := Game.state
	if id == "covington":
		var args := {"mode": "town"}
		args.merge(s.town_snapshot())
		_swap(TOWN, args)
	elif id == "vei":
		var r := s.cmd_begin_boss()
		if not r["ok"]:
			_open_map()
			return
		var args := {"mode": "boss", "run_id": r["run_id"], "seed_rev": r["seed_rev"]}
		args.merge(s.boss_seed())
		_swap(BOSS, args)
	elif id != "" and not s.realm.fort_by_id(id).is_empty():
		var r := s.cmd_begin_dungeon(id)
		if not r["ok"]:
			_open_map()
			return
		var args := {"mode": "dungeon", "fort_id": id, "run_id": r["run_id"], "seed_rev": r["seed_rev"]}
		args.merge(s.raid_seed(id))
		_swap(RAID, args)
	else:
		_open_map()


## Writes a dungeon or boss result back (converting a v1 one with the open run's seed), then
## goes to the map. A refusal is logged and the run forfeited, so none stays open.
func _apply(kind: String, result: Dictionary, seed: Dictionary) -> void:
	var s := Game.state
	var v2 := result if result.has("v") else Results.from_v1(kind, result, seed)
	var out := s.apply_result(kind, v2)
	if not out["ok"]:
		push_warning("necropolis: %s result refused: %s" % [kind, out["reason"]])
		s.cmd_abort_dungeon()
	_open_map()
