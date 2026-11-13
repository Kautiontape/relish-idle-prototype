class_name RaidWardenRun
extends RefCounted
## The dungeon's warden thread: builds the warden at the centre of its room, tracks Relish's room
## for the wake and the antechamber's last chance, opens the chest, and ends the run
## `warden_beaten`. A held fort, or the boss arena, has none of it (every method is a no-op).

var warden: RaidWarden = null
var chest: RaidChest = null
var last_chance_done := false

var _raid: Node2D
var _room := -2


func _init(p_raid: Node2D) -> void:
	_raid = p_raid


func active() -> bool:
	return not _raid.is_boss() and not _raid.held and int(_raid.layout.get("warden_room", -1)) >= 0


## Build the warden (dungeon, not held). Dormant until Relish enters its room.
func build() -> void:
	if not active():
		return
	var rooms: Array = _raid.layout["rooms"]
	var fort: Dictionary = _raid.seed_data.get("fort", {})
	var w := RaidLogic.warden_spec({"id": str(fort.get("id", "")), "tier": _raid.fort_tier(),
		"archetype": str(_raid.seed_data.get("warden", {}).get("archetype", "")),
		"first_dungeon": bool(fort.get("first_dungeon", false))}, _raid.rcfg())
	# TODO(task 6c): the Huntsman node; until then any other archetype is the inert base glyph
	var node: RaidWarden = RaidBellringer.new() if str(w["archetype"]) == "bellringer" else RaidWarden.new()
	node.position = (rooms[int(_raid.layout["warden_room"])] as Rect2).get_center()
	_raid.units_root.add_child(node)
	node.configure(_raid, w)
	warden = node


## Per physics frame: room tracking (wake, last chance).
func tick() -> void:
	if not active() or _raid.relish == null or not _raid.relish.alive:
		return
	var room := RaidLogic.room_of(_raid.layout, _raid.relish.position)
	if room < 0 or room == _room:
		return   # a doorway band belongs to no room
	_room = room
	if room == int(_raid.layout.get("ante_room", -1)) and not last_chance_done:
		last_chance()
	if room == int(_raid.layout["warden_room"]) and warden != null and is_instance_valid(warden):
		warden.wake()


## The nearest awake warden within `reach` of pos (an enemy for the undead), else null.
func target_in(pos: Vector2, reach: float):
	if warden == null or not is_instance_valid(warden) or not warden.alive or not warden.awake:
		return null
	return warden if pos.distance_to(warden.global_position) < reach else null


## The antechamber's last chance (MECHANICS 5.3): trance ready now, the next completed raise
## starts no cooldown, and every loose mote in the room is lit again.
func last_chance() -> void:
	last_chance_done = true
	_raid.trance.grant_free()
	var wc: Dictionary = _raid.rcfg().get("wardens", {})
	var rect: Rect2 = (_raid.layout["rooms"] as Array)[int(_raid.layout["ante_room"])]
	var lit := 0
	for o in _raid.get_tree().get_nodes_in_group("raid_essence"):
		if is_instance_valid(o) and not o.absorbing and not o.carried and rect.has_point(o.global_position):
			o.ignite(float(wc.get("ignite_s", 0.8)))
			lit += 1
	_raid.hud.show_banner("LAST CHANCE · a free trance", float(wc.get("last_chance_banner_s", 3.5)), "essence")
	if _raid._standalone:
		print("RAID_WARDEN last_chance lit=%d" % lit)


func on_warden_died(w: RaidWarden) -> void:
	var c := RaidChest.new()
	c.raid = _raid
	c.position = _raid.resolve_walls(w.position, 14.0)
	_raid.units_root.add_child(c)
	chest = c
	warden = null


## Relish opened the chest: merge its loot into what was found, then the victory beat, then the
## run ends warden_beaten (loot is everything found plus the carried essence, as for a retreat).
func on_chest_opened(c: RaidChest) -> void:
	var e: RaidEndings = _raid.endings
	if e.ended:
		return
	_raid.found_loot = RaidLogic.merge_loot(_raid.found_loot, _raid.chest_loot())
	e.ended = true
	_raid.trance.force_end()
	var wc: Dictionary = _raid.rcfg().get("wardens", {})
	RaidFx.ring(_raid.fx_root, c.global_position, Palette.c("vei"), 120.0, 0.9, 5.0)
	RaidFx.ring(_raid.fx_root, _raid.relish.global_position, Palette.c("relish"), 80.0, 0.8, 4.0)
	_raid.hud.show_banner("THE WARDEN IS BEATEN · loot banked", float(wc.get("victory_s", 1.5)) + 1.0, "vei")
	if _raid._standalone:
		print("RAID_WARDEN chest opened")
	_raid.get_tree().create_timer(float(wc.get("victory_s", 1.5))).timeout.connect(func() -> void:
		if not is_instance_valid(_raid):
			return
		e.finish(e.build_result("warden_beaten")))
