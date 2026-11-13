class_name RaidEndings
extends RefCounted
## Everything about ending a run and what is banked: checkpoint tracking and snapshots, retreat,
## phylactery revives, the result dict, the death beat and the single `finished` emit.
## RefCounted, not a Node: it has no tree presence or per-frame work (the raid calls
## `track_position()` from its physics step); it borrows the raid's tree for its timer.
## `_exit_result` / `_death_result` stay on the raid as overridable hooks (the boss scene
## replaces them) and delegate to `build_result` here.

var ended := false      # run is over; gameplay stops (raid._ended forwards here)
var finished := false   # `finished` already emitted

var banked := {}                 # the last checkpoint snapshot (full loot shape)
var banked_rooms := {}           # checkpoint room index -> true once it has banked
var revived := 0                 # phylactery revives spent this run
var exit_idx := -1               # index into layout.doors of the exit Relish stands at, else -1
var left_spawn_exit := false     # Relish has been outside the spawn exit's radius once

var _raid: Node2D
var _room := -2                  # Relish's current room
var _spawn_exit := -1            # the exit Relish spawns inside (spawn sits within its radius)


func _init(p_raid: Node2D) -> void:
	_raid = p_raid


## Called once the arena is built (dungeon only): the spawn room's checkpoint banks at once.
func start() -> void:
	var radius := float(_raid.rcfg().get("exits", {}).get("radius_px", 120.0))
	_spawn_exit = RaidLogic.near_exit(_raid.layout, _raid.layout["spawn"], radius)
	_room = RaidLogic.room_of(_raid.layout, _raid.relish.position)
	take_checkpoint(_room, false)


# ------------------------------------------------------------- checkpoints ---
## Update the exit Relish stands at and the checkpoint room she is in.
func track_position() -> void:
	var layout: Dictionary = _raid.layout
	var pos: Vector2 = _raid.relish.position
	exit_idx = RaidLogic.near_exit(layout, pos, float(_raid.rcfg().get("exits", {}).get("radius_px", 120.0)))
	if exit_idx != _spawn_exit:
		left_spawn_exit = true
	var room := RaidLogic.room_of(layout, pos)
	if room < 0:
		return   # a doorway's wall band belongs to no room: A -> doorway -> A is not a change
	if room != _room:
		var prev := _room
		_room = room
		if RaidLogic.checkpoint_entered(layout, prev, room):
			take_checkpoint(room, true)


## Bank loot: snapshot what was found plus what is carried now (MECHANICS 7).
func take_checkpoint(room: int, announce: bool) -> void:
	if not (_raid.layout.get("checkpoints", []) as Array).has(room):
		return
	var snap := RaidLogic.loot_snapshot(_raid.found_loot, _raid.carried_count())
	var changed := snap != banked
	banked = snap
	banked_rooms[room] = true
	_raid.arena.set_banked(banked_rooms)
	if changed and announce and _raid.hud != null:
		_raid.hud.show_checkpoint(banked)
	_send_checkpoint()


## Motes circled into undead are spent: a later death must not bank them (it would mint essence).
func clamp_banked() -> void:
	var clamped := RaidLogic.clamp_banked_essence(banked, _raid.carried_count())
	if clamped == banked:
		return
	banked = clamped
	_send_checkpoint()


## Tell the state what is banked. TODO(api-request #4): cmd_run_checkpoint(run_id, loot) is not
## in the state API yet, so this is a no-op until it lands.
func _send_checkpoint() -> void:
	if _raid._from_run and Game.state.has_method("cmd_run_checkpoint"):
		Game.state.cmd_run_checkpoint(int(_raid.seed_data.get("run_id", 0)), banked)


# ------------------------------------------------------------------ retreat ---
## The "AT EXIT" hint: Relish stands at an exit, and has either left the spawn exit's radius once
## or raised (spawn is inside that radius, so the hint would hide the circle hint from frame one).
func exit_hint_ready() -> bool:
	return exit_idx >= 0 and not ended and (left_spawn_exit or _raid.first_raise_done)


## Retreat is open only at an exit (the boss arena keeps its teleport).
func can_retreat() -> bool:
	return _raid.is_boss() or exit_idx >= 0


## The HUD's confirmed RETREAT: re-checks the exit, since Relish may have drifted off.
func try_retreat() -> void:
	if can_retreat():
		confirm_exit()


func confirm_exit() -> void:
	if ended:
		return
	ended = true
	_raid.trance.force_end()
	RaidFx.ring(_raid.fx_root, _raid.relish.global_position, Palette.c("relish"), 60.0, 0.5, 4.0)
	finish(_raid._exit_result())


# ------------------------------------------------------------------- revive ---
## A lethal hit with allies gone: spend a phylactery if one is left. True = Relish lives.
func try_phylactery() -> bool:
	if _raid.is_boss() or not RaidLogic.can_revive(revived, _raid.seed_data):
		return false
	revived += 1
	var hp_frac := float(ConfigDb.data.get("backups", {}).get("phylactery", {}).get("revive_hp", 0.5))
	var rc: Dictionary = _raid.rcfg().get("revive", {})
	var relish: RaidRelish = _raid.relish
	relish.revive(relish.max_hp * hp_frac, float(_raid.rcfg().get("relish", {}).get("revive_iframes_s", 1.5)))
	RaidFx.crack(_raid.fx_root, relish.global_position, Palette.c("relish"),
		float(rc.get("crack_radius_px", 90.0)), float(rc.get("crack_s", 1.1)))
	_raid.hud.flash(Palette.c("relish"))
	if _raid._standalone:
		print("RAID_REVIVE n=%d left=%d hp=%.1f" % [revived, phylactery_left(), relish.hp])
	return true


## Phylactery charges still spendable this run.
func phylactery_left() -> int:
	return RaidLogic.revives_left(revived, _raid.seed_data)


func on_relish_died() -> void:
	if ended:
		return
	ended = true
	_raid.trance.force_end()
	RaidFx.ring(_raid.fx_root, _raid.relish.global_position, Palette.c("danger"), 90.0, 0.8, 4.0)
	RaidFx.ring(_raid.fx_root, _raid.relish.global_position, Palette.c("relish"), 50.0, 0.8, 3.0)
	_raid.get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if not is_instance_valid(_raid):
			return   # the scene was freed during the death beat
		finish(_raid._death_result()))


# ------------------------------------------------------------------- result ---
## Raid result v2 from the ledger and every living ally.
func build_result(exit: String) -> Dictionary:
	var survivors: Array = []
	for a in _raid.allies:
		if is_instance_valid(a) and a.alive:
			survivors.append({"role": a.role, "tier": a.tier, "mass": a.mass})
	# retreat banks everything found plus the carried motes; a death keeps the last checkpoint only
	var loot := RaidLogic.loot_snapshot(_raid.found_loot, _raid.carried_count()) if exit == "retreated" else banked.duplicate(true)
	if loot.is_empty():
		loot = RaidLogic.empty_loot()
	var r: Dictionary = _raid.ledger_v2.build_result(_raid.seed_data, exit, survivors, _raid.party_died, revived, loot, _raid.rcfg())
	for e in Results.validate("raid", r):
		push_error("necropolis: raid result invalid: " + e)
	return r


func finish(result: Dictionary) -> void:
	if finished:
		return
	finished = true
	ended = true
	Engine.time_scale = 1.0
	_raid.finished.emit(result)
	var tele := ""
	if not _raid.is_boss():
		tele = telemetry_line()
		print(tele)
	if _raid._standalone:
		if not _raid.is_boss():
			print("RAID_RESULT_DICT ", JSON.stringify(result))
			_print_standalone_result(result)
		_raid.hud.show_result(result, tele)


## RAID_TELEMETRY line (not part of the result dict).
func telemetry_line() -> String:
	return "RAID_TELEMETRY moves=%d raises=%d ratio=%.1f drifting=%s" % [_raid.moves, _raid.raises,
		RaidLogic.drift_ratio(_raid.moves, _raid.raises),
		str(RaidLogic.is_drifting(_raid.moves, _raid.raises, _raid.rcfg()))]


## Standalone only (no router): say what the scene produced. The scene never writes to the state
## (STATE-API 1.2); the headless writeback test in tests/test_raid_logic.gd covers that path.
func _print_standalone_result(result: Dictionary) -> void:
	if not _raid._from_run or not result.has("v"):
		return
	var errs := Results.validate("raid", result)
	var ex := "relish_died" if result["relish_died"] else ("warden_beaten" if result["warden_beaten"] else "retreated")
	print("RAID_RESULT exit=%s raised=%s garrison_mass=%.2f chaff_mass=%.2f valid=%s errors=%s" % [
		ex, str(result["raised"]), float(result["garrison_mass"]), float(result["chaff_mass"]),
		errs.is_empty(), str(errs)])
