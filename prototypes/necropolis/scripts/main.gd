extends Node
## Scene flow: one active scene at a time, uniform contract
## (setup(seed) / signal finished(result)). Every exit routes through here.

const MAP := "res://scenes/map/WorldMap.tscn"
const RAID := "res://scenes/raid/Raid.tscn"
const TOWN := "res://scenes/town/Covington.tscn"
const BOSS := "res://scenes/boss/VeiBoss.tscn"

var current: Node = null


func _ready() -> void:
	_to_map()


func _to_map() -> void:
	_swap(MAP, {})


func _swap(path: String, seed_data: Dictionary) -> bool:
	if current != null:
		current.queue_free()
		current = null
	if not ResourceLoader.exists(path):
		push_warning("necropolis: scene missing " + path)
		return false
	var node: Node = (load(path) as PackedScene).instantiate()
	add_child(node)
	current = node
	if node.has_method("setup"):
		node.setup(seed_data)
	if node.has_signal("finished"):
		node.finished.connect(_on_finished.bind(path))
	return true


func _on_finished(result: Dictionary, path: String) -> void:
	match path:
		MAP:
			_handle_teleport(str(result.get("teleport_to", "")))
		RAID:
			Game.apply_raid_result(result)
			Game.end_raid()
			_to_map()
		TOWN:
			Game.apply_town_result(result)
			var tp := str(result.get("teleport_to", ""))
			if tp != "":
				_handle_teleport(tp)
			else:
				_to_map()
		BOSS:
			Game.apply_boss_result(result)
			_to_map()


func _handle_teleport(id: String) -> void:
	if id == "" :
		_to_map()
		return
	if id == "covington":
		if not _swap(TOWN, Game.town_snapshot()):
			_to_map()
		return
	if id == "vei":
		if not _swap(BOSS, Game.boss_seed()):
			Game.auto_resolve_boss()
			_to_map()
		return
	Game.begin_raid(id)
	if not _swap(RAID, Game.raid_seed(id)):
		Game.auto_resolve_raid(id)
		Game.end_raid()
		_to_map()
