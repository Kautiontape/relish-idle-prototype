class_name RaidCapture
extends RefCounted
## Capture mode (D-e; NOTES-RAID "Capture mode"): a live dungeon run appends one JSONL record of how it
## went, local only. `--capture` writes to DEFAULT_PATH, `--capture=<path>` to that file (RaidLogic.capture_path;
## a player passes it before `--`, so the boot rule keeps the save). Off unless given.
## It reads the run and writes nothing the sim reads: no random draw, no goal, no state but its own. Every tell-attack
## is classified from the game side (the warden's state, Relish's `hits`, the danger edge's targeted call),
## never from the bot: a human has no `_answers` roll. Per tell, first match (RaidLogic.capture_outcome):
## struck (a blow of it reached her hp), countered (muffled, intercepted, pinned, snuffed during it), dodged
## (aimed at her: the edge warned through its tell, or a toll was placed at her feet), else clear; a tell a
## horn took before it struck is "cancelled". The raid ticks it each live physics frame, tells it when the
## edge warns, and asks it to write in RaidEndings.finish (every ending: a death, the win, a retreat, the
## router's window close) and, if nothing finished, on a window close or as the scene is freed.

const DEFAULT_PATH := "user://raid_capture.jsonl"

var closing := false            # a window close is ending the run (raid._notification sets it)
var _raid: Node2D
var _path := ""
var _written := false
var _t0_ms := 0                 # Time.get_ticks_msec at the build
var _last_ms := 0
var _scene_s := 0.0             # live scene seconds (physics steps; the end beat is not in it)
var _wall_live_ms := 0          # wall-clock ms over those steps
var _rooms := {}                # room index -> {first_s, scene_s, wall_ms, entries}
var _room := -1                 # the room she is in (a doorway band keeps the last)
var _tally := {}                # RaidLogic.capture_count's tally, by tell-attack
var _open: Array = []           # the open tells: {kind, id, shown, aimed, ...}
var _seen_id := -1.0            # the last tell id seen on the warden (its tell clock)
var _targeted := false          # the danger edge warned since the last look
var _archetype := ""            # the warden's (kept: a beaten warden is freed)


func _init(p_raid: Node2D, p_path: String) -> void:
	_raid = p_raid
	_path = p_path


## The path a run's record goes to, or "" (off): `--capture[=<path>]` in the user args or the engine args.
static func path_from_cli() -> String:
	return RaidLogic.capture_path(OS.get_cmdline_user_args(), OS.get_cmdline_args(), DEFAULT_PATH)


func start() -> void:
	_t0_ms = Time.get_ticks_msec()
	_last_ms = _t0_ms
	var w = _raid.warden_run.warden if _raid.warden_run != null else null
	_archetype = str(w.spec.get("archetype", "")) if w != null and is_instance_valid(w) else ""


## Each live physics frame (raid._physics_process): the room clocks, then the warden's tells.
func physics_tick(delta: float) -> void:
	if _written:
		return
	var now := Time.get_ticks_msec()
	var rel: RaidRelish = _raid.relish
	if rel != null and is_instance_valid(rel):
		var r := RaidLogic.room_of(_raid.layout, rel.global_position)
		if r >= 0 and r != _room:
			_room = r
			if not _rooms.has(r):
				_rooms[r] = {"first_s": snappedf(_scene_s, 0.01), "scene_s": 0.0, "wall_ms": 0, "entries": 0}
			_rooms[r]["entries"] = int(_rooms[r]["entries"]) + 1
	if _room >= 0:
		_rooms[_room]["scene_s"] = float(_rooms[_room]["scene_s"]) + delta
		_rooms[_room]["wall_ms"] = int(_rooms[_room]["wall_ms"]) + (now - _last_ms)
	_scene_s += delta
	_wall_live_ms += now - _last_ms
	_last_ms = now
	_observe()


## The danger edge warned (raid.danger_targeted): a tell is aimed at her this frame.
func on_targeted() -> void:
	_targeted = true


# ------------------------------------------------------------------- tells ---
## Read the warden's tell state (as the last physics frame left it) and open and close tells.
func _observe() -> void:
	var w = _raid.warden_run.warden if _raid.warden_run != null else null
	if w == null or not is_instance_valid(w) or not w.alive:
		_close_all()
		_targeted = false
		return
	if w is RaidBellringer:
		_bell(w)
	elif w is RaidHuntsman:
		_hunt(w)
	elif w is RaidShieldwall:
		_wall(w)
	elif w is RaidPyrePriest:
		_pyre(w)
	if _targeted:
		for o in _open:
			if not bool(o.get("undead", false)):
				o["aimed"] = true
	_targeted = false


func _in_warden_room() -> bool:
	var rel: RaidRelish = _raid.relish
	if rel == null or not is_instance_valid(rel):
		return false
	var wr := int(_raid.layout.get("warden_room", -1))
	return wr >= 0 and RaidLogic.room_of(_raid.layout, rel.global_position) == wr


func _hits(keys: Array) -> int:
	var rel: RaidRelish = _raid.relish
	if rel == null or not is_instance_valid(rel):
		return 0
	var n := 0
	for k in keys:
		n += int(rel.hits.get(k, 0))
	return n


func _open_tell(kind: String, id: float, extra: Dictionary) -> Dictionary:
	var o := {"kind": kind, "id": id, "shown": _in_warden_room(), "aimed": false}
	o.merge(extra)
	_open.append(o)
	return o


func _close(o: Dictionary, outcome: String) -> void:
	RaidLogic.capture_count(_tally, str(o["kind"]), outcome, bool(o["shown"]))
	_open.erase(o)


## Close every open tell as it stands (a new tell began, the warden fell, or the run ended): a blow of it
## since it opened is struck; a slam that rang is read by its own flags; any other never struck (a horn,
## the warden's fall or the run's end took it first): cancelled.
func _close_all() -> void:
	for o in _open.duplicate():
		if _hits(o["src"]) > int(o["hits0"]):
			_close(o, "struck")
		elif bool(o.get("rang", false)):
			_close(o, RaidLogic.capture_outcome(false, bool(o.get("countered", false)), bool(o["aimed"])))
		else:
			_close(o, "cancelled")


## The Bellringer: a slam tell opens when it sounds (`_tell_for`), with a toll beside it when one was placed
## at her feet; the toll resolves as the slam rings (its mark: struck, muffled or placed), the slam once its
## ring has run out (a slam blow since it opened: struck; muffled as it rang: countered).
func _bell(b: RaidBellringer) -> void:
	if b._tell_for >= 0.0 and b._tell_for != _seen_id:
		_seen_id = b._tell_for
		_close_all()   # a tell still open never rang: a horn took it
		_open_tell("slam", b._tell_for, {"src": ["slam"], "hits0": _hits(["slam"]), "ctr0": b.slams_muffled, "rang": false})
		if b.toll_at != Vector2.INF:
			_open_tell("toll", b._tell_for, {"src": ["toll"], "hits0": _hits(["toll"]), "aimed": true})
	for o in _open.duplicate():
		var rang: bool = b._slam_beat >= 0.0 and is_equal_approx(b._slam_beat, float(o["id"]))
		if o["kind"] == "toll":
			if rang or (b._slam_beat < 0.0 and b._last_attack >= float(o["id"])):
				var mark: String = str(b.toll_marks.get("%.4f" % float(o["id"]), "placed"))
				_close(o, RaidLogic.capture_outcome(mark == "struck" or _hits(["toll"]) > int(o["hits0"]), mark == "muffled", true))
		else:
			if rang:
				o["rang"] = true
				o["countered"] = b.slams_muffled > int(o["ctr0"])
			elif bool(o["rang"]) and b._slam_beat < 0.0:
				_close(o, RaidLogic.capture_outcome(_hits(["slam"]) > int(o["hits0"]), bool(o.get("countered", false)), bool(o["aimed"])))


## The Huntsman: a lunge tell opens as it locks (`_locked`, `_next_attack`); it resolves when the lunge
## starts (`_lunges` counts it): a lunge blow on her is struck, an interceptor countered. A lock aimed at an
## undead never counts as aimed at her. Unlocked with no lunge: a horn took it.
func _hunt(h: RaidHuntsman) -> void:
	if h._locked and h._next_attack != _seen_id:
		_seen_id = h._next_attack
		_close_all()
		_open_tell("lunge", h._next_attack, {"src": ["lunge"], "hits0": _hits(["lunge"]), "ctr0": h.intercepts,
			"lunges0": h._lunges, "undead": h._lock_undead})
	for o in _open.duplicate():
		if h._lunges > int(o["lunges0"]):
			_close(o, RaidLogic.capture_outcome(_hits(["lunge"]) > int(o["hits0"]), h.intercepts > int(o["ctr0"]), bool(o["aimed"])))
		elif not h._locked:
			_close(o, "cancelled")


## The Shieldwall: a tell opens as it plants (`_tell_for`), a "rush" when it rushes (the aimed lane too),
## else a "bash" (a pinned tell: its plain bash; the pin is its counter); it resolves when it bashes.
func _wall(w: RaidShieldwall) -> void:
	if w._tell_for >= 0.0 and w._tell_for != _seen_id and w.planted:
		_seen_id = w._tell_for
		_close_all()
		_open_tell("rush" if w.rushing else "bash", w._tell_for, {"src": ["bash", "rush"], "hits0": _hits(["bash", "rush"]),
			"bashes0": w.bashes, "pinned": w.pinned_tell, "lane": w.lane})
	for o in _open.duplicate():
		if w.bashes > int(o["bashes0"]):
			_close(o, RaidLogic.capture_outcome(_hits(["bash", "rush"]) > int(o["hits0"]), bool(o["pinned"]), bool(o["aimed"])))


## The Pyre-priest: a fire tell opens as its areas are marked and lit; it resolves when it burns (`burns`):
## a fire blow on her is struck, an acolyte snuffed during it countered.
func _pyre(p: RaidPyrePriest) -> void:
	if p._tell_for != _seen_id:
		_seen_id = p._tell_for
		_close_all()
		if p.lit:
			_open_tell("fire", p._tell_for, {"src": ["fire"], "hits0": _hits(["fire"]), "ctr0": p.snuffs, "burns0": p.burns})
	for o in _open.duplicate():
		if p.burns > int(o["burns0"]):
			_close(o, RaidLogic.capture_outcome(_hits(["fire"]) > int(o["hits0"]), p.snuffs > int(o["ctr0"]), bool(o["aimed"])))


# ------------------------------------------------------------------- write ---
## The run ended (RaidEndings.finish, before the emit): one record, appended. Once.
func write(result: Dictionary) -> void:
	if _written:
		return
	_observe()   # the last frame's events (the killing blow ends the run before another tick)
	_close_all()
	_append(_record(RaidLogic.capture_exit(bool(result.get("relish_died", false)), bool(result.get("warden_beaten", false)),
		bool(result.get("retreated", false)))))


## Nothing finished (a standalone window close, or the scene freed without an ending): write what there is.
func flush_unfinished(why: String) -> void:
	if _written:
		return
	_close_all()
	_append(_record(RaidLogic.capture_unfinished(why, _raid.endings.pending_exit if _raid.endings != null else "")))


func _record(exit: String) -> Dictionary:
	var fort: Dictionary = _raid.seed_data.get("fort", {})
	var rel: RaidRelish = _raid.relish
	var died := exit == "relish_died"
	var src: String = rel.last_hit_src if rel != null and is_instance_valid(rel) else ""
	var wr := int(_raid.layout.get("warden_room", -1))
	var rooms: Array = []
	for r in _rooms.keys():
		var e: Dictionary = _rooms[r]
		var role := "room"
		if r == wr:
			role = "warden"
		elif r == int(_raid.layout.get("ante_room", -1)):
			role = "ante"
		elif r == RaidLogic.room_of(_raid.layout, _raid.layout.get("spawn", Vector2.ZERO)):
			role = "spawn"
		elif (_raid.layout.get("checkpoints", []) as Array).has(r):
			role = "checkpoint"
		rooms.append({"room": r, "role": role, "first_s": e["first_s"], "entries": e["entries"],
			"scene_s": snappedf(float(e["scene_s"]), 0.01), "wall_s": snappedf(float(e["wall_ms"]) / 1000.0, 0.01)})
	var rec := {"v": 1, "kind": "raid_capture", "at": Time.get_datetime_string_from_system(),
		"fort": str(fort.get("id", "")), "tier": _raid.fort_tier(), "first_dungeon": bool(fort.get("first_dungeon", false)),
		"held": _raid.held, "run_id": int(_raid.seed_data.get("run_id", 0)), "seed_rev": int(_raid.seed_data.get("seed_rev", 0)),
		"archetype": _archetype,
		"bot": RaidAutopilot.enabled(), "outcome": exit, "closed": closing,
		"retreat_by": _raid.endings.retreat_by if exit == "retreated" and _raid.endings != null else "",   # a gap's result is a retreat too (retreat_by "gap")
		"assist": RaidLogic.assist_on,   # LONGER WARNINGS was on at the row: runs with it on skew the miss and tell analysis
		"killed_by": (src if src != "" else "wound") if died else "", "missed_tell": RaidLogic.death_tell(src) if died else "",
		"scene_s": snappedf(_scene_s, 0.01), "wall_live_s": snappedf(float(_wall_live_ms) / 1000.0, 0.01),
		"wall_s": snappedf(float(Time.get_ticks_msec() - _t0_ms) / 1000.0, 0.01),
		"raises": _raid.raises, "relish_hits": rel.hits.duplicate() if rel != null and is_instance_valid(rel) else {},
		"rooms": rooms, "tells": _tally}
	if _raid.held_door != null:
		# D-e task 6: the door choice (only on a fort with a held door): taken or not (a big was sent), which
		# big, the scene times of the order, the door opening, the cache, the shut-in and the rejoin, and its fate
		var hd: RaidHeldDoor = _raid.held_door
		var dd := hd.telemetry()
		dd["taken"] = hd.holder_uid != "" or hd.fell > 0
		dd["name"] = hd.holder_name
		dd["fate"] = hd.fate(exit)
		rec["door"] = dd
	return rec


func _append(rec: Dictionary) -> void:
	_written = true
	var f: FileAccess = null
	if FileAccess.file_exists(_path):
		f = FileAccess.open(_path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_warning("necropolis: capture could not open %s (%s)" % [_path, error_string(FileAccess.get_open_error())])
		return
	f.store_line(JSON.stringify(rec))
	f.close()
