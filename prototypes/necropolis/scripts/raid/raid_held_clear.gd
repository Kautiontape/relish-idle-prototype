class_name RaidHeldClear
extends RefCounted
## A held fort's raid payoff (IDLE I3, section 3): when its last living enemy falls the counter-garrison is
## cleared. A banner and a short set piece say so, the held_clear loot joins found_loot, its essence bonus
## arrives as fresh mass-0 motes around Relish, and after `held.clear_victory_s` (long enough for them to
## gather) the run ends as a retreat. `killed_living_mass` is all the living killed, so the writeback clears
## the fort's living. Relish dying inside the window still ends `relish_died`; `endings.ended` guards a
## double end (a manual retreat inside the window wins, with the loot already in found_loot). A held
## fort with no living at the build clears `held.empty_clear_s` later (`on_built`).

var started := false      # the clear has fired (no run may fire it twice)
var loot := {}            # the held_clear roll (items merged into found_loot; essence spawned as motes)

var _raid: Node2D


func _init(p_raid: Node2D) -> void:
	_raid = p_raid


func _c(key: String, def: float) -> float:
	return float(_raid.rcfg().get("held", {}).get(key, def))


## Called once the scene is built: a held fort with no living at all clears after
## `held.empty_clear_s` (there is no last kill to trigger it).
func on_built() -> void:
	var left := 0
	for e in _raid.enemies:
		if is_instance_valid(e) and e.alive:
			left += 1
	var wait := RaidLogic.held_empty_clear_s(_raid.held, _raid.is_boss(), left, _raid.rcfg())
	if wait < 0.0:
		return
	_raid.get_tree().create_timer(wait, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(_raid) and not _raid.endings.ended and not started:
			_start())


## Called by the raid after each enemy dies (dungeon only).
func on_enemy_died() -> void:
	if _raid.endings.ended:
		return
	var left := 0
	for e in _raid.enemies:
		if is_instance_valid(e) and e.alive:
			left += 1
	if RaidLogic.held_clear_due(_raid.held, _raid.is_boss(), left, started):
		_start()


func _start() -> void:
	started = true
	var fort: Dictionary = _raid.seed_data.get("fort", {})
	loot = RaidLoot.held_clear(_raid.rng_loot, _raid.fort_tier(), float(fort.get("yield_mult", 1.0)), _raid.lcfg())
	_raid.found_loot = RaidLogic.merge_loot(_raid.found_loot, loot)
	# the clear's payoff, then its effect on the map: the counter-garrison mass this run killed
	var killed: float = _raid.ledger_v2.killed if _raid.ledger_v2 != null else 0.0
	_raid.hud.show_banner(RaidLogic.held_banner(_raid.fort_name()) + "\n" + RaidLogic.held_payoff(loot)
		+ "\n" + RaidLogic.held_map_effect(killed), _c("banner_s", 3.5), "undead_core")
	var pos: Vector2 = _raid.relish.global_position
	# the set piece: a ring sweeps out from Relish and the walls flash toward the town's colour
	var ring_px := _c("ring_px", 720.0)
	var ring_s := _c("ring_s", 1.1)
	RaidFx.ring(_raid.fx_root, pos, Palette.c("town"), ring_px, ring_s, 5.0)
	RaidFx.ring(_raid.fx_root, pos, Palette.c("undead_core", 0.8), ring_px * 0.55, ring_s * 0.7, 3.0)
	_raid.arena.flash_walls("town", _c("wall_flash_s", 1.4), _c("wall_flash_intensity", 1.7))
	# the bonus essence: fresh mass-0 motes just off Relish, who gathers them into her cluster
	var n := RaidLogic.held_motes(loot)
	var r := _c("mote_ring_px", 46.0)
	for i in n:
		var p: Vector2 = pos + Vector2(r, 0).rotated(TAU * float(i) / maxf(1.0, float(n)) + 0.5)
		_raid.spawn_mote(_raid.resolve_walls(p, 6.0), 0.0, false)
	if _raid._standalone:
		print("RAID_HELD_CLEAR items=%d essence_motes=%d window_s=%.1f" % [
			int(RaidLogic.loot_counts(loot)["items"]), n, _c("clear_victory_s", 2.5)])
	var shot := RaidDev.cli_value("--raid-held-shot=")   # dev: save a screenshot a moment into the set piece
	if shot != "" and _raid._standalone:
		_raid.get_tree().create_timer(0.3, true, false, true).timeout.connect(func() -> void:
			if is_instance_valid(_raid):
				_raid.get_viewport().get_texture().get_image().save_png(shot))
	_raid.get_tree().create_timer(_c("clear_victory_s", 2.5), true, false, true).timeout.connect(_end)


## The window is over: retreat with everything found plus whatever motes she gathered.
func _end() -> void:
	if not is_instance_valid(_raid):
		return   # the scene was freed during the window
	_raid.endings.confirm_exit("held_clear")   # no-op if the run already ended (death or a manual retreat)
