class_name RaidEndings
extends RefCounted
## Everything about ending a run and what is banked: checkpoint tracking and snapshots, retreat,
## phylactery revives, the result dict, the death beat and the single `finished` emit.
## RefCounted, not a Node: it has no tree presence (the raid calls `track_position()` and `tick()`, the checkpoint
## resend check, from its physics step); it borrows the raid's tree for its timers.
## `_exit_result` / `_death_result` stay on the raid as overridable hooks (the boss scene
## replaces them) and delegate to `build_result` here.

var ended := false      # run is over; gameplay stops (raid._ended forwards here)
var finished := false   # `finished` already emitted
var win_result := {}    # the warden's win, built once at chest open on the clear-card path ({} for the bot); what the card shows and every exit emits
var pending_exit := ""  # the exit an ending beat will emit (relish_died, warden_beaten); a close keeps it

var banked := {}                 # the last checkpoint snapshot (full loot shape)
var _ending_loot := {}           # the loot checkpoint_ending sent for the ending (sticky: every later send repeats it)
var banked_rooms := {}          # checkpoint room index -> true once it has banked
var revived := 0                 # phylactery revives spent this run
var exit_idx := -1               # index into layout.doors of the exit Relish stands at, else -1
var left_spawn_exit := false     # Relish has been outside the spawn exit's radius once
var retreat_by := ""             # what ended a retreat (capture's retreat_by): click | bot | dev | held_clear | close | gap
var _gap := false                # the state ended the run under us (gap_end): one beat, one finish
var _pending_cp := {}            # a checkpoint the state refused with catching_up: {run_id, loot, outcome}, resent by tick()

var _raid: Node2D
var _room := -2                  # Relish's current room
var _spawn_exit := -1            # the exit Relish spawns inside (spawn sits within its radius)
var _card: Control = null         # the death card, freed at finish (a standalone result panel replaces it)
var _seen := {}                  # room index -> true once Relish has stood in it (the HUD's "n of m rooms seen")


func _init(p_raid: Node2D) -> void:
	_raid = p_raid


## Called once the arena is built (dungeon only): the spawn room's checkpoint banks at once.
func start() -> void:
	var radius := float(_raid.rcfg().get("exits", {}).get("radius_px", 120.0))
	_spawn_exit = RaidLogic.near_exit(_raid.layout, _raid.layout["spawn"], radius)
	_room = RaidLogic.room_of(_raid.layout, _raid.relish.position)
	if _room >= 0:
		_seen[_room] = true
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
		_seen[room] = true
		if RaidLogic.checkpoint_entered(layout, prev, room):
			take_checkpoint(room, true)


## Rooms Relish has stood in so far (read-only for the HUD; the sim never reads it).
func rooms_seen() -> int:
	return _seen.size()


## Bank loot: snapshot what was found plus what is carried now (MECHANICS 7).
func take_checkpoint(room: int, announce: bool) -> void:
	if ended:
		return   # an ending has begun: its checkpoint stands (belt and braces; _send_checkpoint is sticky too)
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
	if ended:
		return
	var clamped := RaidLogic.clamp_banked_essence(banked, _raid.carried_count())
	if clamped == banked:
		return
	banked = clamped
	_send_checkpoint()


## Tell the state what is banked and the exit the run would end in now (Game.state.cmd_run_checkpoint; a
## save written from here, or a crash, ends the run from it on the next load). The outcome comes from
## `pending_exit` and the loot from `_ending_loot` (RaidLogic.checkpoint_payload), so both are sticky: once an
## ending beat has begun, no later call can write "retreated" or the pre-ending `banked` back over it.
## `loot` (only checkpoint_ending passes one) is the ending's loot: it is stored in `_ending_loot`.
func _send_checkpoint(loot := {}) -> void:
	if not _raid._from_run or _gap:
		return
	if not loot.is_empty():
		_ending_loot = loot
	var p := RaidLogic.checkpoint_payload(pending_exit, _ending_loot, banked)
	_post_checkpoint({"run_id": int(_raid.seed_data.get("run_id", 0)), "loot": p["loot"], "outcome": p["outcome"]})


## Send one payload; a catching_up refusal keeps it as the pending one (RaidLogic.checkpoint_pending_after: each
## send replaces what was pending, so a newer checkpoint supersedes an older one; gap_end drops it).
func _post_checkpoint(payload: Dictionary) -> void:
	var res: Dictionary = Game.state.cmd_run_checkpoint(int(payload["run_id"]), payload["loot"], str(payload["outcome"]))
	_pending_cp = RaidLogic.checkpoint_pending_after(payload, res)


## Every frame of the raid's _process: a refused checkpoint is resent once the catch-up is over (one dictionary
## test per frame when nothing is pending).
func tick() -> void:
	if _pending_cp.is_empty() or not RaidLogic.checkpoint_resend_due(_pending_cp, Game.state.catching_up()):
		return
	_post_checkpoint(_pending_cp)


## The state ended this run underneath the raid (a gap above idle.gap_s: run_ended, or the away_report backstop):
## stop like an ending, close what is open, say so, and emit the one result after gap_end.beat_s. `outcome` is
## what the state recorded (RaidLogic.gap_outcome). No checkpoint goes out after this (the run is gone).
func gap_end(outcome: String) -> void:
	if finished or _gap:
		return
	_gap = true
	# A gap drops a still-pending checkpoint: that only matters if state_runs ever refuses a death or win checkpoint
	# with catching_up (it does not today; see RaidLogic.checkpoint_pending_after).
	_pending_cp = {}
	var plan := RaidLogic.gap_plan(ended, pending_exit, _raid.is_boss())
	if bool(plan["leave"]):
		return   # a death or victory beat is running and already matches the state: it keeps its card and its one finish
	if bool(plan["cut_end"]):
		_raid.gap_cut_end()   # the Vei fight's end set piece or card contradicts the forfeit the state recorded
	if not ended:
		retreat_by = "gap"
	ended = true
	_raid.trance.force_end()
	if _raid.hud != null:
		_raid.hud.close_retreat()   # (no death or clear card can be open here: both are made only once pending_exit is set, and that returned above)
		var gcfg: Dictionary = _raid.rcfg().get("gap_end", {})
		_raid.hud.show_banner(RaidLogic.gap_banner(gcfg, _raid.is_boss()), float(gcfg.get("banner_s", 4.0)), "danger")
	_raid.get_tree().create_timer(float(_raid.rcfg().get("gap_end", {}).get("beat_s", 2.5))).timeout.connect(_finish_gap.bind(outcome))


## The gap beat is over: the one emit, shaped as the state already recorded the run (close_request's shapes: a retreat
## pays the last checkpoint, a death or a win the beat's own result). The router ignores it (the run is ended).
func _finish_gap(outcome: String) -> void:
	if not is_instance_valid(_raid) or finished:
		return
	if _raid.is_boss():
		finish(_raid.close_result())
		return
	var plan := RaidLogic.close_plan(true, outcome)
	if plan["exit"] == "warden_beaten" and not win_result.is_empty():
		finish(win_result)
	else:
		finish(_raid._death_result() if plan["exit"] == "relish_died" else build_result(plan["exit"], plan["closing"]))


## An ending beat has begun (`pending_exit` is set): record it with the state and save now, so a crash in
## the beat resumes as that ending and not as a retreat (the autosave clock is 30 s of real time).
## `loot` is the win's loot, or `banked` for a death (it keeps the last checkpoint snapshot; with none banked,
## the empty loot shape: the state refuses {}). It is stored, and every later send repeats it.
func checkpoint_ending(loot := {}) -> void:
	if not _raid._from_run:
		return
	var l: Dictionary = loot if not loot.is_empty() else banked
	_send_checkpoint(RaidLogic.empty_loot() if l.is_empty() else l)
	Game.autosave()


# ------------------------------------------------------------------ retreat ---
## The "AT EXIT" hint: Relish stands at an exit, and has either left the spawn exit's radius once
## or raised (spawn is inside that radius, so the hint would hide the circle hint from frame one).
func exit_hint_ready() -> bool:
	return exit_idx >= 0 and not ended and (left_spawn_exit or _raid.first_raise_done)


## Retreat is open only at an exit. There is no retreat from the Vei fight (the boss scene also
## overrides this).
func can_retreat() -> bool:
	return not _raid.is_boss() and exit_idx >= 0


## The HUD's confirmed RETREAT: re-checks the exit, since Relish may have drifted off.
func try_retreat(by := "") -> void:
	if can_retreat():
		confirm_exit(by)


## `by` labels the retreat for the capture (the retreat panel's click, the bot, a dev flag, the held clear).
func confirm_exit(by := "") -> void:
	if ended:
		return
	ended = true
	retreat_by = by
	_raid.trance.force_end()
	RaidFx.ring(_raid.fx_root, _raid.relish.global_position, Palette.c("relish"), 60.0, 0.5, 4.0)
	finish(_raid._exit_result())


# ------------------------------------------------------------------- close ---
## "No run survives a close" (IDLE I5): the window is asked to close mid-run, so the run ends now. Only a
## router-launched run does this (not standalone); it must emit before the quit save, see raid.gd
## `_notification`. True when it emitted.
##   dungeon  a retreat paying the last checkpoint snapshot (what was found since is lost, the same
##            bound as a death), with the phylactery revives spent; but during an ending beat it is
##            the ending it already was (`pending_exit` from RaidLogic.pending_on, RaidLogic.close_plan): Relish's death beat
##            stays a death, and the warden's victory beat stays the win with the chest in its loot
##            (the same result the beat's timer would have built).
##   boss     the boss scene's close_result(): lost with the backups spent so far still spent (a
##            final-death beat counts its death), or the win if Vei already broke.
func close_request() -> bool:
	if finished or _raid._standalone or not _raid._from_run or not _raid._built:
		return false
	if _raid.is_boss():
		var r: Dictionary = _raid.close_result()
		ended = true
		_raid.trance.force_end()
		finish(r)
		return true
	var plan := RaidLogic.close_plan(ended, pending_exit)
	if not ended:
		retreat_by = "close"
	ended = true
	_raid.trance.force_end()
	if plan["exit"] == "warden_beaten" and not win_result.is_empty():
		finish(win_result)   # the clear card's frozen win: the same dict the card shows
	else:
		finish(_raid._death_result() if plan["exit"] == "relish_died" else build_result(plan["exit"], plan["closing"]))
	return true


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
	_raid.hud.show_banner(RaidLogic.revive_banner(rc, phylactery_left()), float(rc.get("banner_s", 4.0)))   # says she was saved
	if _raid._standalone:
		print("RAID_REVIVE n=%d left=%d hp=%.1f" % [revived, phylactery_left(), relish.hp])
		print("REVIVE_DEMO frame=%d charges_left=%d" % [Engine.get_process_frames(), phylactery_left()])
	return true


## Phylactery charges still spendable this run.
func phylactery_left() -> int:
	return RaidLogic.revives_left(revived, _raid.seed_data)


func on_relish_died() -> void:
	if ended:
		return
	ended = true
	pending_exit = RaidLogic.pending_on("relish_died")
	checkpoint_ending()   # a death keeps the last checkpoint snapshot: a crash in the beat resumes as a death
	_raid.trance.force_end()
	RaidFx.ring(_raid.fx_root, _raid.relish.global_position, Palette.c("danger"), 90.0, 0.8, 4.0)
	RaidFx.ring(_raid.fx_root, _raid.relish.global_position, Palette.c("relish"), 50.0, 0.8, 3.0)
	var wait := 0.9
	var card_s := float(_raid.rcfg().get("death", {}).get("card_s", 0.0))
	if card_s > 0.0 and _raid.hud != null and not RaidAutopilot.enabled():   # the bot never waits on the card
		wait = card_s
		var card := RaidDeathCard.new()
		_raid.hud.add_child(card)
		card.setup(death_rows())
		_card = card
		card.dismissed.connect(_finish_death)
	_raid.get_tree().create_timer(wait).timeout.connect(_finish_death)


## The death beat is over (its timer, or a click on the card): the one emit. `finish` guards a double.
func _finish_death() -> void:
	if not is_instance_valid(_raid):
		return   # the scene was freed during the death beat
	finish(_raid._death_result())


## What a death costs her right now, the one source for the death card and the retreat panel's IF RELISH FALLS
## column: the unbanked loot, the big shut in at the held door (D-e task 6: lost too, on a row of its own apart
## from the party that fell) and the party's big count without it.
func death_inputs() -> Dictionary:
	var ub: Dictionary = RaidLogic.unbanked(_raid.found_loot, _raid.carried_count(), banked)
	var shut: String = _raid.held_door.shut_name() if _raid.held_door != null else ""
	var party_n := (_raid.seed_data.get("party", []) as Array).size() - (1 if shut != "" else 0)
	return {"unbanked": ub, "shut": shut, "party_n": party_n}


## The death card's rows: what killed her, what the last checkpoint banked, what is lost.
func death_rows() -> Array:
	var wname: String = _raid.warden_run.warden_name if _raid.warden_run != null else ""
	var dw: Dictionary = _raid.rcfg().get("death", {})
	var cause := RaidLogic.death_cause(dw, _raid.relish.last_hit_src, wname)
	var di := death_inputs()
	var ub: Dictionary = di["unbanked"]
	var shut: String = di["shut"]
	var party_n: int = di["party_n"]
	return RaidLogic.death_rows_with_shut(dw, RaidLogic.death_card_rows(dw, cause, RaidLogic.loot_counts(banked), ub, party_n,
		RaidLogic.death_tell(dw, _raid.relish.last_hit_src), RaidLogic.death_next_row(_raid.seed_data, dw), RaidLogic.death_attack(dw, _raid.relish.last_hit_src)), shut)


# ------------------------------------------------------------------- result ---
## Raid result v2 from the ledger and every living ally.
## `closing`: a window close, not a retreat the player chose: the loot is the last checkpoint snapshot.
func build_result(exit: String, closing := false) -> Dictionary:
	var survivors: Array = []
	for a in _raid.allies:
		if is_instance_valid(a) and a.alive:
			survivors.append({"role": a.role, "tier": a.tier, "mass": a.mass})
	var loot := RaidLogic.result_loot(exit, closing, _raid.found_loot, _raid.carried_count(), banked)
	var died: Array = _raid.party_died
	if _raid.held_door != null:
		died = died + _raid.held_door.lost_uids(exit)   # a big spent on the held door and not rejoined (RaidLogic.held_door_lost)
	var r: Dictionary = _raid.ledger_v2.build_result(_raid.seed_data, exit, survivors, died, revived, loot, _raid.rcfg())
	for e in Results.validate("raid", r):
		push_error("necropolis: raid result invalid: " + e)
	return r


func finish(result: Dictionary) -> void:
	if finished:
		return
	finished = true
	ended = true
	_pending_cp = {}
	if _raid.capture != null:
		_raid.capture.write(result)   # capture mode: synchronous, before the emit (the router frees the scene; the bot quits)
	if is_instance_valid(_card):
		_card.queue_free()
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
		if _raid._dev != null:
			_raid._dev.on_finish(result)


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
