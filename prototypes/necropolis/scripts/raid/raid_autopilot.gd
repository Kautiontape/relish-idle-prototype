class_name RaidAutopilot
extends RefCounted
## Headless raid bot: plays a dungeon with a plausible, simple policy and a target circle score,
## then prints one `AUTOPILOT_RESULT {json}` line and quits. DEV TOOLING (the measuring instrument
## for BALANCE 3's risk targets and the economy's stand-in values), never a game feature.
## Standalone only: RaidDev creates it when `--raid-autopilot=<target_score>` is given.
##   --raid-autopilot-seed=<n>    overrides the seed's rng_seed (combat + loot); the layout stays per fort
##   (it also heads for an exit and retreats when nothing has changed for autopilot.idle_s)
##   --raid-autopilot-bail=<0..1> run for an exit and retreat at or below this hp fraction (default: raid.json autopilot.bail_hp_frac, 0 = never)
##   --raid-autopilot-log         a status line every 2 scene seconds
##   --raid-autopilot-answer-mult=<x> scales the chance to answer a warden tell (1 - react_miss; the context runs)
## Run it fast and deterministic with `--headless --fixed-fps 60 --disable-vsync --max-fps 0`.
## All policy numbers live in raid.json `autopilot`.
##
## Policy, every `think_frames` physics frames (scene time only; the bot never reads the wall clock):
##   route   BFS the room graph to the warden room (held fort: the deepest room, then out an exit).
##   advance hold back while living enemies are near or in the current/next room; kite from the
##           nearest enemy and let the undead fight; else walk the path through the wall gaps.
##   collect walk to loose motes and corpse piles when no enemy is near.
##   raise   when the trance is ready and enough motes are near, draw a 44-point circle whose jitter
##           is binary-searched to land within a few points of the target score.
##   pickup  walk to remnants lying on the floor when no foe is near (before the chest ends the run).
##   react   every warden tell goes through one rule (`_answers`): answered with chance 1 - react_miss
##           (rolled once per tell from `_rng_react`, a stream of its own) and acted on react_delay_s after
##           she first sees it, both set by the target score (RaidLogic.react_at); until then, and all
##           through a missed tell, she does what she would do with no tell. The kite from the living
##           starts react_delay_s after a foe comes within kite_px (no miss).
##   warden  Bellringer: go in for motes (and raise) when the trip in and out fits before the next tell
##           with `slam_safe_beats` to spare (WardenLogic.slam_window_open), work inside until she
##           answers a tell (or a slam ring is out), then get out; otherwise wait `bell_stage_px`
##           outside the slam (so the army stays in reach of the bell).
##           Huntsman: fight inside its room (it hunts the undead when she hides), sidestep a lunge
##           tell she answers.
##           Shieldwall: while she answers a bash tell, keep out of its bash arc (the front arc within its
##           reach, plus `wall_margin_*`) and fetch only what lies outside it; wait on its side
##           (`wall_side_deg` off its facing, `wall_stand_px` beyond the bash) so the raises there walk in
##           from the side, going round the wall the short way as it turns.
##           Pyre-priest: on a fire tell she answers, step off a lit burn area that covers her, first
##           carrying a mote out of a lit area when the trip in and out fits before the beat, and fetch
##           only what lies outside the fire; while
##           acolytes live wait `pyre_stand_px` beyond the nearest one and hold a raise until within
##           `pyre_raise_px` of one (unless the carry is full, she is out of its room or a living foe
##           is within `kite_px`), so the raised undead go for it; once
##           it is exposed wait `pyre_exposed_px` from it. Then the chest.
## The bot does NOT use the trance's time dilation: a real player slows time to draw. That is a
## conservative approximation (the bot raises instantly but never gets the slow-mo aim and dodge window).
## Measuring fields (read only, never fed back): `split` (scene seconds per RaidLogic.time_class bucket),
## the frame counters (`frames_drawn`, `physics_frames`, `frames_at_start`, `run_ticks`: the lockstep
## check), `walk_px`, `walk_travel_px`, `route_px`, `rooms_entered`, `killed_by`, `react` (the reaction rule's
## miss chance and delay, the warden tells seen and answered). See NOTES-RAID "Run length and risk calibration".

var _raid: Node2D
var _cfg: Dictionary = {}
var _target := 70
var _seed := 0
var _rng := RandomNumberGenerator.new()   # the trace jitter
# the reaction rule (_answers; raid.json autopilot react_*): set from the target score in start()
var _miss := 0.18               # chance a warden tell goes unanswered
var _delay := 0.45              # scene seconds from first seeing a tell (or a foe within kite_px) to acting on it
var _rng_react := RandomNumberGenerator.new()   # its own stream: the tell rolls never shift the trace draws
var _tell_id := ""              # the tell the roll was made for ("<kind>:<beat>")
var _tell_seen := 0.0           # scene time the bot first saw it
var _tell_ok := false           # rolled: she answers it
var _tell_side := 1.0           # rolled with it: the sidestep's side when nothing else decides
var _tells := 0                 # warden tells seen / answered (the react dict)
var _tells_ok := 0
var _threat_t := -1.0           # scene time a living foe in her room came within kite_px (-1: none now)
var _threat_last := -1.0        # scene time one was last within kite_px
var _bell_goal = null           # the Bellringer fight's last point inside the slam she was making for

var _sim_t := 0.0               # scene seconds the run has lasted (physics steps only)
var _frame := 0
var _timed_out := false
var _done := false
var _scores: Array = []         # score of every successful raise
var _first_raise_s := -1.0      # scene time of the first successful raise (-1: none)
var _wake_s := -1.0             # scene time the warden woke (-1: it never did)
var _raises_wake := 0           # successful raises after the warden woke (circles during the fight)
var _attacks := 0               # the warden's slams or lunges so far (read off it each think)
var _attacks_wp := 0            # of them: muffled slams, or intercepted lunges (the weak point)
var _catches := 0               # Huntsman catches of Relish
var _cur_room := -1
var _prev_room := -1
var _hold_t := 0.0              # continuous seconds spent holding back in the current room
var _archetype := ""
var _sig := ""                  # progress signature: raises, living, warden hp, chest
var _sig_t := 0.0               # scene time the signature last changed
var _giving_up := false         # nothing has moved for idle_s: head for an exit and retreat
var _why := ""                 # which policy branch chose the last goal (log only)
var _foes: Array = []          # living enemies this think (for the retreat's heading choice)
var _bail := 0.0               # retreat to an exit once hp is at or below this fraction (0 = never)
var _log := false              # --raid-autopilot-log: one status line every 2 scene seconds
var _gaps_cache := {}           # "a>b" -> Array[Rect2] of the gaps joining two rooms
var _stick = null               # the mote, pile or pickup being walked to (kept while still valid)
var _avoid_arc := {}            # the Shieldwall's bash arc this think ({} for every other fight): spots in it are not safe
var _wall_side := 0.0           # which side of the Shieldwall she keeps to (+1 / -1; 0 before the first pick)
var _shield := {}               # the Shieldwall's hit and bash counts, read off it each think, once more as it dies and at the finish
var _avoid_burn := {}           # the Pyre-priest's lit burn areas this think ({areas, r}; {} for every other fight): spots in them are not safe
var _pyre := {}                 # the Pyre-priest's counts, read off it each think, once more as it dies and at the finish
var _min_hp := INF              # Relish's lowest hp so far (the pyre dict reports it)
# measuring only (D-d/E): read off the run each physics tick, never fed back into a decision
const SPLIT_MOVE_PX := 1.0      # a tick in which Relish moved more than this is travel (she walks 4 px a tick)
var _split := {"travel": 0.0, "fight": 0.0, "trance": 0.0, "idle": 0.0}   # scene seconds per RaidLogic.time_class bucket
var _last_pos := Vector2.INF    # Relish's position at the previous tick
var _walk_px := 0.0             # how far Relish walked in all
var _walk_travel_px := 0.0      # of it: in travel ticks
var _rooms_entered := 0         # room changes (_track_room): decision points for the human factor
var _frames0 := [0, 0]          # the process and physics frame counters at start()
var _living_start := 0          # living on the field when the run starts
var _pack := {}                 # the warden's pack counts (a warden with a pack only), read like _shield / _pyre
var _det := {}                  # the guarded detour's site (RaidLogic.detour_site); {} on a fort without one
var _det_state := ""            # "" until she decides; then "taken", "declined", "done" or "abandoned"
var _det_at := {}               # what she decided on: scene time, hp fraction, army, guard standing
var _det_done_s := -1.0         # scene time the cache was hers (-1: not)


func _init(p_raid: Node2D) -> void:
	_raid = p_raid


# ------------------------------------------------------------------- flags ---
static func enabled() -> bool:
	return RaidDev.cli_value("--raid-autopilot=") != ""


## `--raid-autopilot-seed=<n>`: the seed's rng_seed for this run (combat and loot variety).
static func apply_seed(sd: Dictionary) -> void:
	var s := RaidDev.cli_value("--raid-autopilot-seed=")
	if s != "":
		sd["rng_seed"] = str(int(s))


## Called once the scene is built (RaidDev.start).
func start() -> void:
	_cfg = (_raid.rcfg().get("autopilot", {}) as Dictionary)
	_target = int(RaidDev.cli_value("--raid-autopilot="))
	_log = RaidDev.cli_flag("--raid-autopilot-log")
	var bl := RaidDev.cli_value("--raid-autopilot-bail=")
	_bail = clampf(float(bl) if bl != "" else float(_cfg.get("bail_hp_frac", 0.0)), 0.0, 1.0)
	_seed = int(str(_raid.seed_data.get("rng_seed", "1")).to_int())
	_rng.seed = _seed ^ 0x0A170B07
	_rng_react.seed = _seed ^ 0x5EAC7105
	var pts: Array = _cfg.get("react_score", [50, 70, 90])
	_miss = clampf(RaidLogic.react_at(float(_target), pts, _cfg.get("react_miss", [0.30, 0.18, 0.08])), 0.0, 1.0)
	_delay = maxf(0.0, RaidLogic.react_at(float(_target), pts, _cfg.get("react_delay_s", [0.60, 0.45, 0.30])))
	var am := RaidDev.cli_value("--raid-autopilot-answer-mult=")
	if am != "":
		_miss = 1.0 - clampf((1.0 - _miss) * float(am), 0.0, 1.0)
	var w = _raid.warden_run.warden
	_archetype = str(w.spec.get("archetype", "")) if w != null and is_instance_valid(w) else ""
	_frames0 = [Engine.get_process_frames(), Engine.get_physics_frames()]
	_living_start = _raid.enemies.size()
	_det = RaidLogic.detour_site(_raid.layout, _raid.fort_tier(), _raid.rcfg())
	if w != null and is_instance_valid(w) and w.spec.has("pack"):
		_pack = w.pack_telemetry()
	_pin_clock()


func _c(key: String, def: float) -> float:
	return float(_cfg.get(key, def))


## The Pulse reads the wall clock (Time.get_ticks_msec) unless a test pins it. The warden's beat
## clock aligns to the next Pulse boundary at wake, so pin it to scene time: a headless run
## then does not depend on how fast it runs.
func _pin_clock() -> void:
	Pulse.clock_ms = _sim_t * 1000.0


# ---------------------------------------------------------------- the tick ---
## Per physics frame while the run is live (raid._physics_process, before units move).
func physics_tick(delta: float) -> void:
	if _done:
		return
	_sim_t += delta
	_pin_clock()
	var rel_hp: RaidRelish = _raid.relish
	if rel_hp != null and is_instance_valid(rel_hp):
		_min_hp = minf(_min_hp, rel_hp.hp)
	_split_tick(delta)
	_frame += 1
	if _frame % maxi(1, int(_c("think_frames", 3.0))) != 0:
		return
	var rel: RaidRelish = _raid.relish
	if rel == null or not is_instance_valid(rel) or not rel.alive:
		return
	if _sim_t > _c("max_s", 600.0):
		_time_out()
		return
	var pos := rel.global_position
	var ww = _raid.warden_run.warden
	if ww != null and is_instance_valid(ww):
		if _wake_s < 0.0 and ww.awake:
			_wake_s = _sim_t
		if ww is RaidBellringer:
			_attacks = ww._slams
			_attacks_wp = ww.slams_muffled
		elif ww is RaidHuntsman:
			_attacks = ww._lunges
			_attacks_wp = ww.intercepts
			_catches = ww.catches
		elif ww is RaidShieldwall:
			_attacks = ww.bashes
			_attacks_wp = ww.flanks
			_shield = ww.telemetry()
		elif ww is RaidPyrePriest:
			_attacks = ww.burns
			_attacks_wp = ww.snuffs
			_pyre = ww.telemetry()
		if not _pack.is_empty():
			_pack = ww.pack_telemetry()
	_track_room(pos)
	if not _raid.held_clear.started:   # the cleared fort's bonus motes are kept, not circled away
		_try_raise(pos)
	_watch_progress()
	var goal := _decide(pos)
	rel.move_target = goal
	if _log and _frame % 120 == 0:
		print("AUTOPILOT t=%.1f room=%d pos=(%d,%d) goal=(%d,%d) hp=%.0f enemies=%d allies=%d carried=%d loose=%d piles=%d trance=%d why=%s hold=%.0f near=%d wide=%d warden=%s" % [
			_sim_t, _cur_room, pos.x, pos.y, goal.x, goal.y, rel.hp, _living().size(), _raid.allies.size(),
			_raid.carried_count(), _raid.get_tree().get_nodes_in_group("raid_essence").size() - _raid.carried_count(),
			_raid.get_tree().get_nodes_in_group("raid_piles").size(), _raid.trance.state, _why, _hold_t,
			_motes_near(pos, _c("raise_reach_px", 300.0)).size(), _motes_near(pos, 350.0).size(), _warden_log()])


## One tick of the time split (RaidLogic.time_class; NOTES-RAID "Run length and risk calibration"):
## reads the run, changes nothing. Runs every live physics tick, so the buckets sum to duration_s.
func _split_tick(delta: float) -> void:
	var rel: RaidRelish = _raid.relish
	var rpos := Vector2.INF
	var moved := 0.0
	if rel != null and is_instance_valid(rel):
		rpos = rel.global_position
		if _last_pos != Vector2.INF:
			moved = rpos.distance_to(_last_pos)
		_last_pos = rpos
	var tr: RaidTrance = _raid.trance
	var k := RaidLogic.time_class(tr != null and tr.state == RaidTrance.State.ACTIVE, _engaged(rpos), moved, SPLIT_MOVE_PX)
	_split[k] = float(_split[k]) + delta
	_walk_px += moved
	if k == "travel":
		_walk_travel_px += moved


## The split's "engaged": the warden from its wake while it lives (standing off a slam or waiting out a
## tell is its fight), or a hostile living foe in her room or within combat.aggro_px of her.
func _engaged(rpos: Vector2) -> bool:
	var w = _raid.warden_run.warden
	if w != null and is_instance_valid(w) and w.alive and w.awake:
		return true
	if rpos == Vector2.INF:
		return false
	var fight_px := float((_raid.rcfg().get("combat", {}) as Dictionary).get("aggro_px", 260.0))
	var rr := RaidLogic.room_of(_raid.layout, rpos)
	for e in _raid.enemies:
		if not is_instance_valid(e) or not e.alive or not e._aggro:
			continue
		if RaidLogic.foe_engaged(rpos, rr, e.global_position, RaidLogic.room_of(_raid.layout, e.global_position), true, fight_px):
			return true
	return false


## The shortest walk the bot's own routing takes from the spawn to the goal room's centre: the BFS room
## path, through the nearest gap of each pair in turn (the human factor's route baseline).
func _route_px() -> float:
	var at: Vector2 = _raid.layout["spawn"]
	var goal := int(_raid.layout.get("warden_room", -1))
	if goal < 0:
		goal = _goal_room()
	var p := _path(RaidLogic.room_of(_raid.layout, at), goal)
	var px := 0.0
	for i in range(1, p.size()):
		var best := _room_center(p[i])
		var bd := INF
		for g in _gaps_between(p[i - 1], p[i]):
			var c := (g as Rect2).get_center()
			if at.distance_to(c) < bd:
				bd = at.distance_to(c)
				best = c
		px += at.distance_to(best)
		at = best
	return px + at.distance_to(_room_center(goal))


func _warden_log() -> String:
	var w = _raid.warden_run.warden
	if w == null or not is_instance_valid(w):
		return "none"
	return "%s awake=%s hp=%d at=(%d,%d) room=%d/%d" % [_archetype, str(w.awake), int(w.hp), w.global_position.x,
		w.global_position.y, int(_raid.layout.get("warden_room", -1)), int(_raid.layout.get("ante_room", -1))]


## A player whose army is stuck, with no motes to circle, goes home. If raises, the living count,
## the warden's hp and the chest have not changed for `idle_s` scene seconds, the bot retreats.
func _watch_progress() -> void:
	var w = _raid.warden_run.warden
	var sig := "%d|%d|%d|%s" % [_raid.raises, _living().size(), int(w.hp) if w != null and is_instance_valid(w) else -1,
		str(_raid.warden_run.chest != null)]
	if sig != _sig:
		_sig = sig
		_sig_t = _sim_t
	elif _sim_t - _sig_t > _c("idle_s", 60.0):
		_giving_up = true


## The warden died (RaidWardenRun.on_warden_died, before it lets go of it): read its counts one last
## time, so the killing blow is in the `shield` / `pyre` dicts. The think-tick snapshots run before
## the units' and the warden's physics, so they miss the last event of the run. Only those two dicts:
## the older `_attacks` counters stay as the think tick leaves them (they feed every fort's line).
func on_warden_died(w: RaidWarden) -> void:
	_read_final(w)


func _read_final(w) -> void:
	if _done or w == null or not is_instance_valid(w):
		return
	if w is RaidShieldwall:
		_shield = w.telemetry()
	elif w is RaidPyrePriest:
		_pyre = w.telemetry()
	if not _pack.is_empty():
		_pack = w.pack_telemetry()


## The run ended (RaidEndings.finish): print the line once and quit.
func on_finish(result: Dictionary) -> void:
	if _done:
		return
	_read_final(_raid.warden_run.warden)   # still there when Relish died or the run timed out: its last counts
	_done = true
	var exit := "timeout" if _timed_out else ("relish_died" if bool(result.get("relish_died", false)) \
		else ("warden_beaten" if bool(result.get("warden_beaten", false)) else "retreated"))
	var fort: Dictionary = _raid.seed_data.get("fort", {})
	var loot: Dictionary = result.get("loot", {})
	var raised := 0
	for b in _raid.ledger_v2.buckets:
		raised += int(b["count"])
	var avg := 0.0
	for s in _scores:
		avg += float(s)
	if not _scores.is_empty():
		avg /= float(_scores.size())
	var lost := _unbanked_lost(result)
	var out := {"fort": str(fort.get("id", "")), "tier": _raid.fort_tier(), "archetype": _archetype,
		"held": _raid.held, "first_dungeon": bool(fort.get("first_dungeon", false)),
		"target_score": _target, "seed": _seed, "exit": exit,
		"duration_s": snappedf(_sim_t, 0.01), "revives": _raid.endings.revived,
		"raises": _raid.raises, "avg_score": snappedf(avg, 0.1), "raised_count": raised,
		"first_raise_s": snappedf(_first_raise_s, 0.01), "warden_hp_frac_end": snappedf(_warden_hp_frac(), 0.001),
		"warden_wake_s": snappedf(_wake_s, 0.01), "raises_after_wake": _raises_wake,
		"warden_attacks": _attacks, "warden_attacks_weak_point": _attacks_wp, "catches": _catches,
		"pickups_left": _raid.pickups_left(), "unbanked_lost": int(lost["items"]), "unbanked_lost_essence": int(lost["essence"]),
		"killed_living_mass": snappedf(float(result.get("killed_living_mass", 0.0)), 0.01),
		"seed_living": snappedf(float(_raid.seed_data.get("living", 0.0)), 0.01), "held_cleared": _raid.held_clear.started,
		"loot": {"relics": int(loot.get("relics", 0)), "blueprints": (loot.get("blueprints", []) as Array).size(),
			"husks": (loot.get("husks", []) as Array).size(), "remnants": (loot.get("remnants", []) as Array).size(),
			"essence": int(loot.get("essence", 0))},
		"party_lost": result.get("party_lost", []),
		"relish_hp_end": snappedf(_raid.relish.hp if _raid.relish != null and is_instance_valid(_raid.relish) else 0.0, 0.1),
		"allies_end": _allies_alive()}
	if _archetype == "shieldwall":   # its own counts (the other wardens' lines keep their shape)
		out["shield"] = _shield
	if _archetype == "pyre_priest":
		var py := _pyre.duplicate()
		var low := _min_hp
		if _raid.relish != null and is_instance_valid(_raid.relish):
			low = minf(low, _raid.relish.hp)   # the killing blow lands after the last tick
		py["relish_min_hp"] = snappedf(maxf(0.0, low) if low < INF else -1.0, 0.1)
		out["pyre"] = py
	# measuring only (D-d/E): the time split, the frame counters (lockstep), the walk, the death's cause
	out["split"] = {"travel_s": snappedf(float(_split["travel"]), 0.01), "fight_s": snappedf(float(_split["fight"]), 0.01),
		"trance_s": snappedf(float(_split["trance"]), 0.01), "idle_s": snappedf(float(_split["idle"]), 0.01)}
	out["frames_drawn"] = Engine.get_process_frames()
	out["physics_frames"] = Engine.get_physics_frames()
	out["frames_at_start"] = {"drawn": int(_frames0[0]), "physics": int(_frames0[1])}
	out["run_ticks"] = _frame
	out["walk_px"] = roundi(_walk_px)
	out["walk_travel_px"] = roundi(_walk_travel_px)
	out["route_px"] = roundi(_route_px())
	out["rooms_entered"] = _rooms_entered
	out["living_start"] = _living_start
	if not _pack.is_empty():
		out["pack"] = _pack
	if not _det.is_empty():
		var st := _det_state
		out["detour"] = {"room": int(_det["room"]), "guard": _raid.detour_guard.size(), "offered": st != "",
			"taken": st in ["taken", "done", "abandoned"], "done": st == "done", "abandoned": st == "abandoned",
			"at": _det_at, "done_s": snappedf(_det_done_s, 0.01),
			"cache_left": _det_cache_left(), "cache": _raid.detour_cache.size()}
	var died := exit == "relish_died"
	var src: String = _raid.relish.last_hit_src if _raid.relish != null and is_instance_valid(_raid.relish) else ""
	out["killed_by"] = (src if src != "" else "wound") if died else ""
	out["react"] = {"miss": snappedf(_miss, 0.001), "delay_s": snappedf(_delay, 0.001), "tells": _tells, "answered": _tells_ok}
	print("AUTOPILOT_RESULT ", JSON.stringify(out))
	RaidQuit.finish(_raid.get_tree())


func _allies_alive() -> int:
	var n := 0
	for a in _raid.allies:
		if is_instance_valid(a) and a.alive:
			n += 1
	return n


## Scene end: the warden's hp fraction (0 once killed, 1 while it never woke, -1 with no warden: a
## held fort).
func _warden_hp_frac() -> float:
	var w = _raid.warden_run.warden
	if w != null and is_instance_valid(w):
		return clampf(w.hp / maxf(1.0, w.max_hp), 0.0, 1.0)
	return 0.0 if _archetype != "" else -1.0


## What the run lost that was found or carried and not banked: found_loot (and carried essence) minus
## what the result actually paid out. Zero for a retreat or a beaten warden (they bank everything);
## positive for a death or a timeout away from an exit (both pay the last checkpoint's loot).
func _unbanked_lost(result: Dictionary) -> Dictionary:
	var paid: Dictionary = RaidLogic.loot_counts(result.get("loot", {}))
	var had: Dictionary = RaidLogic.loot_counts(RaidLogic.loot_snapshot(_raid.found_loot, _raid.carried_count()))
	return {"items": maxi(0, int(had["items"]) - int(paid["items"])), "essence": maxi(0, int(had["essence"]) - int(paid["essence"]))}


## Past max_s: retreat if Relish stands at an exit (the retreat banks everything found plus the
## carried motes), else just end the run: the result then carries only the last checkpoint's
## banked loot (like a death), so timeout loot is never more than a bot could have banked.
func _time_out() -> void:
	_timed_out = true
	var e: RaidEndings = _raid.endings
	if e.can_retreat():
		e.confirm_exit()
	elif not e.ended:
		e.ended = true
		_raid.trance.force_end()
		var r := e.build_result("retreated")
		r["retreated"] = false   # it did not leave: no exit flag, loot is the last checkpoint's
		r["loot"] = e.banked.duplicate(true) if not e.banked.is_empty() else RaidLogic.empty_loot()
		e.finish(r)


# ------------------------------------------------------------------ routing ---
func _track_room(pos: Vector2) -> void:
	var r := RaidLogic.room_of(_raid.layout, pos)
	if r >= 0 and r != _cur_room:
		_prev_room = _cur_room
		_cur_room = r
		_hold_t = 0.0
		_rooms_entered += 1


func _rooms() -> Array:
	return _raid.layout["rooms"]


func _room_center(i: int) -> Vector2:
	return (_rooms()[i] as Rect2).get_center()


## BFS room path from a to b over layout.adj, inclusive of both ends; [] if unreachable.
func _path(a: int, b: int) -> Array[int]:
	var out: Array[int] = []
	if a < 0 or b < 0:
		return out
	if a == b:
		out.append(a)
		return out
	var adj: Array = _raid.layout["adj"]
	var prev := {a: -1}
	var q: Array[int] = [a]
	var qi := 0
	while qi < q.size():
		var c: int = q[qi]
		qi += 1
		for nb in adj[c]:
			if not prev.has(nb):
				prev[nb] = c
				if nb == b:
					var at: int = b
					while at != -1:
						out.push_front(at)
						at = prev[at]
					return out
				q.append(nb)
	return out


## Gap rects joining two rooms (the grown-gap test the layout's own adjacency uses).
func _gaps_between(a: int, b: int) -> Array:
	var key := "%d>%d" % [a, b]
	if _gaps_cache.has(key):
		return _gaps_cache[key]
	var out: Array = []
	var pad := float(_raid.layout["wall_t"]) * 0.5 + 4.0
	for g in _raid.layout.get("gaps", []):
		var grown := (g as Rect2).grow(pad)
		if grown.intersects(_rooms()[a] as Rect2) and grown.intersects(_rooms()[b] as Rect2):
			out.append(g)
	_gaps_cache[key] = out
	return out


## The gaps joining rooms a and b that really open between them: those within half a gap's width of one
## of the layout's portals for the pair. A gap at a T-junction can touch both rooms' rects and still open
## elsewhere; walking to it, then toward the far room's centre, sent the bot back to it (a dither that
## stalled chime-fort until the bot gave up). Every gap when the layout has no portal for the pair.
func _real_gaps(a: int, b: int) -> Array:
	var all := _gaps_between(a, b)
	var pts: Array = (_raid.layout.get("portals", {}) as Dictionary).get("%d:%d" % [a, b], [])
	if pts.is_empty():
		return all
	var half := float(_raid.rcfg().get("layout", {}).get("inner_gap_width", 165.0)) * 0.5
	var keep: Array = []
	for g in all:
		for p in pts:
			if (g as Rect2).get_center().distance_to(p) <= half:
				keep.append(g)
				break
	return keep if not keep.is_empty() else all


## The point to walk to now, to get to room `goal_room` and then `final` inside it: through the
## nearest gap into the next room on the path, then that room's centre.
func _toward_room(pos: Vector2, goal_room: int, final: Vector2) -> Vector2:
	if _cur_room < 0:
		return final
	if _cur_room == goal_room:
		return final
	var p := _path(_cur_room, goal_room)
	if p.size() < 2:
		return final
	var nxt: int = p[1]
	var best := Vector2.ZERO
	var bd := INF
	for g in _real_gaps(_cur_room, nxt):
		var c := (g as Rect2).get_center()
		var d := pos.distance_to(c)
		if d < bd:
			bd = d
			best = c
	if bd == INF:
		return _room_center(nxt)
	if bd > _c("arrive_px", 30.0):
		return best
	return _room_center(nxt)


## Walk to a point through the room graph (a straight line would stick on a wall).
func _to_point(pos: Vector2, p: Vector2) -> Vector2:
	var r := RaidLogic.room_of(_raid.layout, p)
	return _toward_room(pos, r, p) if r >= 0 else p


func _next_room() -> int:
	var p := _path(_cur_room, _goal_room())
	return p[1] if p.size() >= 2 else -1


## The warden room, or on a held fort the deepest room from the spawn.
func _goal_room() -> int:
	if _det_state == "taken":
		return int(_det["room"])   # the guarded detour, until the cache is hers or she abandons it
	var wr := int(_raid.layout.get("warden_room", -1))
	if wr >= 0:
		return wr
	var hops: Array = _raid.layout["hops"]
	var best := 0
	for i in hops.size():
		if int(hops[i]) > int(hops[best]):
			best = i
	return best


## Where a step back goes: of 16 headings, the open one (not into a wall) that ends farthest from
## the nearest living enemy, with a lean toward the previous room's centre. `stay_in` (when set)
## keeps the step inside that rect.
func _back_step(pos: Vector2, from: Vector2, stay_in: Rect2 = Rect2()) -> Vector2:
	var step := _c("retreat_step_px", 90.0)
	var rad: float = _raid.relish.radius
	var lean := Vector2.ZERO
	if _prev_room >= 0:
		lean = (_room_center(_prev_room) - pos).normalized()
	var best := pos
	var bs := -INF
	for k in 16:
		var dir := Vector2.RIGHT.rotated(TAU * float(k) / 16.0)
		var p: Vector2 = pos + dir * step
		var q: Vector2 = _raid.resolve_walls(p, rad)
		var open := q.distance_to(p) <= 4.0
		for f in [0.25, 0.5, 0.75]:   # and nothing in the way on the walk there
			var m: Vector2 = pos + dir * step * f
			open = open and (_raid.resolve_walls(m, rad) as Vector2).distance_to(m) <= 4.0
		if not open:
			continue   # a wall is in the way
		if stay_in.size != Vector2.ZERO and not stay_in.has_point(q):
			continue
		var nearest := q.distance_to(from)
		for e in _foes:
			nearest = minf(nearest, q.distance_to(e.global_position))
		var score := nearest + dir.dot(lean) * 25.0
		if score > bs:
			bs = score
			best = q
	return best


# ------------------------------------------------------------------- policy ---
## True when `p` is in the room the bot is in (or in a doorway band, which belongs to no room).
func _shares_room(p: Vector2) -> bool:
	var r := RaidLogic.room_of(_raid.layout, p)
	return r < 0 or _cur_room < 0 or r == _cur_room


func _living() -> Array:
	var out: Array = []
	for e in _raid.enemies:
		if is_instance_valid(e) and e.alive:
			out.append(e)
	return out


func _decide(pos: Vector2) -> Vector2:
	_why = "adv"
	_detour_tick()
	_avoid_arc = {}
	_avoid_burn = {}
	var hold_px := _c("hold_px", 200.0)
	var kite_px := _c("kite_px", 240.0)
	if _hold_t >= _c("stall_s", 30.0):
		# the army has had its time and the way on is still shut: commit, so a lone foe on the edge of
		# kite range cannot hold the bot at the boundary (kite, advance, kite...)
		kite_px = _c("kite_committed_px", 110.0)
		hold_px = minf(hold_px, kite_px)
	var run: RaidWardenRun = _raid.warden_run

	# a held fort's counter-garrison is cleared: stand and gather the bonus motes, the run ends itself
	if _raid.held_clear.started:
		_why = "cleared"
		return pos

	if _giving_up:
		return _head_for_exit(pos)

	# a beaten-up Relish with no revive left bails out of the dungeon
	if _bail > 0.0 and _raid.relish.hp <= _bail * _raid.relish.max_hp and _raid.phylactery_left() <= 0 \
			and (run.chest == null or not is_instance_valid(run.chest)):
		return _head_for_exit(pos)

	var living := _living()
	_foes = living

	# the chest: walk to it (opening it ends the run: sweep up what lies on the floor first)
	if run.chest != null and is_instance_valid(run.chest):
		var keep: bool = _still_target(_stick, living) and _stick.is_in_group("raid_pickups")
		var pk0 = _stick if keep else _pickup_node(pos, living)
		_stick = pk0
		if pk0 != null:
			_why = "pickup"
			return _to_point(pos, pk0.global_position)
		return _to_point(pos, run.chest.global_position)

	var ne = null
	var nd := INF
	for e in living:
		if not _shares_room(e.global_position):
			continue   # a foe behind a wall is no threat yet (kiting from it made the bot dither at the wall)
		var d: float = pos.distance_to(e.global_position)
		if d < nd:
			nd = d
			ne = e
	_watch_threat(ne, nd)

	# the warden, once awake
	var w = run.warden
	if w != null and is_instance_valid(w) and w.alive and w.awake:
		_why = "warden"
		return _vs_warden(pos, w, living, ne, nd)

	# an enemy too close: step back and let the undead fight (once she reacts: her old plan runs until then)
	if ne != null and nd < kite_px:
		if not _kite_due():
			_why = "kite-wait"
			return _raid.relish.move_target
		_why = "kite"
		return _back_step(pos, ne.global_position)
	var near_enemy := ne != null and nd < hold_px
	if near_enemy:
		_why = "near"
		return pos
	# loose motes and piles, then pickups: the one chosen is kept until it is gone or unsafe (re-picking
	# the nearest each think flip-flopped at a range edge: a pile just past pile_px, a pickup the other way)
	var tgt = _stick if _still_target(_stick, living) else null
	if tgt == null:
		tgt = _collect_node(pos, living)
	if tgt == null:
		tgt = _pickup_node(pos, living)
	_stick = tgt
	if tgt != null:
		_why = "pickup" if tgt.is_in_group("raid_pickups") else "loot"
		return _to_point(pos, tgt.global_position)
	# hold while living remain in this room or the next
	var nxt := _next_room()
	var blocked := false
	for e in living:
		var er := RaidLogic.room_of(_raid.layout, e.global_position)
		if er >= 0 and (er == _cur_room or er == nxt) \
				and not (_det_state == "taken" and er == int(_det["room"]) and er != _cur_room):
			blocked = true   # (a taken detour is a push: its guard does not hold her at its door)
			break
	if blocked:
		_hold_t += _c("think_frames", 3.0) / 60.0
		if _hold_t < _c("stall_s", 30.0):
			_why = "hold"
			return pos
	# nothing left to wait for: advance (a held fort ends with an exit)
	var goal := _goal_room()
	if int(_raid.layout.get("warden_room", -1)) < 0 and _cur_room == goal and living.is_empty():
		return _head_for_exit(pos)
	if int(_raid.layout.get("warden_room", -1)) < 0 and _cur_room == goal and ne != null:
		# the deepest room is reached but living remain elsewhere: go and find them (the army engages
		# what is within its reach once Relish brings it close)
		var er := RaidLogic.room_of(_raid.layout, ne.global_position)
		if er >= 0:
			return _toward_room(pos, er, ne.global_position)
	return _toward_room(pos, goal, _room_center(goal))


## The reaction rule, the one place every warden tell goes through (NOTES-RAID "the bot's reaction
## model"): the first time the bot sees a tell (`kind` and its attack beat name it) it rolls once, from
## its own stream, whether she answers it (1 - `_miss`); she acts on it `_delay` scene seconds after that
## first sight. Until then, and all through a missed tell, she does what she would do with no tell.
func _answers(kind: String, beat: float) -> bool:
	var id := "%s:%.4f" % [kind, beat]
	if id != _tell_id:
		_tell_id = id
		_tell_seen = _sim_t
		_tell_ok = _rng_react.randf() >= _miss
		_tell_side = 1.0 if _rng_react.randf() < 0.5 else -1.0
		_tells += 1
		if _tell_ok:
			_tells_ok += 1
	return _tell_ok and _sim_t - _tell_seen >= _delay - 1e-6


## The living have no one-beat tell, so no miss: the kite starts `_delay` after a living foe in her room
## first comes within kite_px, and stays on while one is there. A foe that steps out of kite_px and back
## within `_delay` is the same threat (she has seen it: no fresh delay at the kite's edge).
func _watch_threat(ne, nd: float) -> void:
	if ne != null and nd < _c("kite_px", 240.0):
		if _threat_t < 0.0:
			_threat_t = _sim_t
		_threat_last = _sim_t
	elif _threat_t >= 0.0 and _sim_t - _threat_last > _delay + 1e-6:
		_threat_t = -1.0


func _kite_due() -> bool:
	return _threat_t >= 0.0 and _sim_t - _threat_t >= _delay - 1e-6


## The guarded detour's rule (RaidLogic.detour_take; raid.json autopilot detour_*), applied once, at the
## first think she stands in the antechamber before the wake (the approach is behind her): take the
## cache when her hp is at least detour_hp_frac of its most and her army at least detour_army_mult times
## the guard still standing.
func _detour_decide() -> void:
	var rel: RaidRelish = _raid.relish
	var hpf: float = rel.hp / maxf(1.0, rel.max_hp)
	var army := _allies_alive()
	var guard := _det_guard()
	_det_at = {"t": snappedf(_sim_t, 0.01), "hp_frac": snappedf(hpf, 0.01), "army": army, "guard": guard}
	_det_state = "taken" if RaidLogic.detour_take(hpf, army, guard, _cfg) else "declined"
	print("AUTOPILOT_DETOUR %s hp=%.2f army=%d guard=%d frame=%d" % [_det_state, hpf, army, guard, Engine.get_process_frames()])


## Each think: the decision, at her first think in the antechamber before the wake; while a detour is
## taken, done once the cache is hers, abandoned below detour_abandon_hp_frac.
func _detour_tick() -> void:
	if _det_state == "" and not _det.is_empty() and _cur_room >= 0 and _cur_room == int(_raid.layout.get("ante_room", -1)):
		var w = _raid.warden_run.warden
		if w == null or not is_instance_valid(w) or not w.awake:
			_detour_decide()
	if _det_state != "taken":
		return
	var rel: RaidRelish = _raid.relish
	if _det_cache_left() == 0:
		_det_state = "done"
		_det_done_s = _sim_t
	elif rel.hp < _c("detour_abandon_hp_frac", 0.3) * rel.max_hp:
		_det_state = "abandoned"


func _det_guard() -> int:
	var n := 0
	for e in _raid.detour_guard:
		if is_instance_valid(e) and e.alive:
			n += 1
	return n


func _det_cache_left() -> int:
	var n := 0
	for pk in _raid.detour_cache:
		if is_instance_valid(pk) and pk.is_in_group("raid_pickups"):
			n += 1
	return n


## Walk to the exit nearest by rooms, and retreat once standing in it.
func _head_for_exit(pos: Vector2) -> Vector2:
	if _raid.endings.can_retreat():
		_raid.endings.try_retreat()
		return pos
	var best := -1
	var bh := 1 << 30
	var doors: Array = _raid.layout["doors"]
	for i in doors.size():
		var d: Dictionary = doors[i]
		if not bool(d.get("exit", false)):
			continue
		var p := _path(_cur_room, int(d.get("room", -1)))
		var h := p.size() if not p.is_empty() else (1 << 29)
		if h < bh:
			bh = h
			best = i
	if best < 0:
		return pos
	var door: Dictionary = doors[best]
	return _toward_room(pos, int(door.get("room", _cur_room)), door["inner"])


## The nearest loose mote within collect_px, else the nearest unstirred corpse pile within
## pile_px (stirring a pile turns it into motes), when the carried cluster has room. Spots within
## `foe_clear_px` of a living enemy, and inside the warden's danger circle (`avoid`, `avoid_r`), are skipped.
func _collect_target(pos: Vector2, living: Array, avoid: Vector2 = Vector2.INF, avoid_r := 0.0, in_room := Rect2()):
	var o = _collect_node(pos, living, avoid, avoid_r, in_room)
	return o.global_position if o != null else null


## `_collect_target`'s node (the mote or pile itself), or null.
func _collect_node(pos: Vector2, living: Array, avoid: Vector2 = Vector2.INF, avoid_r := 0.0, in_room := Rect2()):
	if _raid.carry_room() <= 0:
		return null
	var clear := _c("foe_clear_px", 170.0)
	var best = null
	var bd := _c("collect_px", 320.0)
	for o in _raid.get_tree().get_nodes_in_group("raid_essence"):
		if not is_instance_valid(o) or o.absorbing or o.carried:
			continue
		var p: Vector2 = o.global_position
		var d := pos.distance_to(p)
		if d < bd and _in(in_room, p) and _spot_ok(p, living, clear, avoid, avoid_r):
			bd = d
			best = o
	if best != null:
		return best
	bd = _c("pile_px", 900.0)
	for o in _raid.get_tree().get_nodes_in_group("raid_piles"):
		if not is_instance_valid(o) or o._stirred or o._shrink >= 0.0:
			continue
		var p2: Vector2 = o.global_position
		var d2 := pos.distance_to(p2)
		if d2 < bd and _in(in_room, p2) and _spot_ok(p2, living, clear, avoid, avoid_r):
			bd = d2
			best = o
	return best


## A rect with no size means "anywhere".
func _in(room: Rect2, p: Vector2) -> bool:
	return room.size == Vector2.ZERO or room.has_point(p)


## The nearest remnant on the floor within `pickup_px` that is safe to fetch (no living foe within
## `pickup_foe_clear_px`, outside the warden's danger circle `avoid`/`avoid_r`, inside `in_room` when
## given). Pickups need no carry room.
func _pickup_target(pos: Vector2, living: Array, avoid: Vector2 = Vector2.INF, avoid_r := 0.0, in_room := Rect2()):
	var o = _pickup_node(pos, living, avoid, avoid_r, in_room)
	return o.global_position if o != null else null


## `_pickup_target`'s node, or null.
func _pickup_node(pos: Vector2, living: Array, avoid: Vector2 = Vector2.INF, avoid_r := 0.0, in_room := Rect2()):
	var best = null
	var bd := _c("pickup_px", 900.0)
	var clear := _c("pickup_foe_clear_px", 90.0)
	for o in _raid.get_tree().get_nodes_in_group("raid_pickups"):
		if not is_instance_valid(o):
			continue
		var p: Vector2 = o.global_position
		var d := pos.distance_to(p)
		if d < bd and _in(in_room, p) and _spot_ok(p, living, clear, avoid, avoid_r):
			bd = d
			best = o
	return best


## The sticky target is still worth walking to: it exists, is still collectable (a mote neither
## absorbing nor carried, a pile not yet stirred, with carry room; or a pickup on the floor) and no
## living foe stands by it.
func _still_target(o, living: Array) -> bool:
	if o == null or not is_instance_valid(o):
		return false
	if o.is_in_group("raid_pickups"):
		return _spot_ok(o.global_position, living, _c("pickup_foe_clear_px", 90.0), Vector2.INF, 0.0)
	if _raid.carry_room() <= 0:
		return false
	if o.is_in_group("raid_essence"):
		if o.absorbing or o.carried:
			return false
	elif o.is_in_group("raid_piles"):
		if o._stirred or o._shrink >= 0.0:
			return false
	else:
		return false
	return _spot_ok(o.global_position, living, _c("foe_clear_px", 170.0), Vector2.INF, 0.0)


func _spot_ok(p: Vector2, living: Array, clear: float, avoid: Vector2, avoid_r: float) -> bool:
	if avoid != Vector2.INF and p.distance_to(avoid) < avoid_r:
		return false
	if not _avoid_arc.is_empty() and WardenLogic.bash_hits(float(_avoid_arc["facing"]), _avoid_arc["from"], p,
			float(_avoid_arc["half"]), float(_avoid_arc["reach"]), 0.0):
		return false
	if not _avoid_burn.is_empty() and WardenLogic.in_burn(p, _avoid_burn["areas"], float(_avoid_burn["r"]), 0.0):
		return false
	for e in living:
		if p.distance_to(e.global_position) < clear:
			return false
	return true


# ------------------------------------------------------------------- warden ---
func _vs_warden(pos: Vector2, w: RaidWarden, living: Array, ne, nd: float) -> Vector2:
	var kite_px := _c("kite_px", 240.0)
	var at: Dictionary = w.spec.get("attack", {})
	var wp := w.global_position
	var safe_px := kite_px
	if _archetype == "bellringer":
		safe_px = float(at.get("radius_px", 360.0)) + float(at.get("band_px", 36.0)) * 0.5 + _c("bell_margin_px", 24.0)
	elif _archetype == "huntsman":
		var h: RaidHuntsman = w as RaidHuntsman
		var hr := int(_raid.layout.get("warden_room", -1))
		if hr >= 0 and RaidLogic.room_of(_raid.layout, pos) != hr:
			# it only hunts inside its room: go back in and fight it there (kiting, dodging its tells). The
			# live room, not _cur_room: standing in the doorway band kept the stale room, so the bot idled
			# at the door while the Huntsman, seeing her outside, lunged through the army instead
			return _toward_room(pos, hr, _room_center(hr))
		var dodge_to = _dodge_step(pos, h)
		if dodge_to != null:
			return dodge_to
	if _archetype == "pyre_priest":
		return _vs_pyre(pos, w as RaidPyrePriest, living, ne, nd)
	# other living first (once she reacts: her old plan runs until then)
	if ne != null and nd < kite_px:
		return _back_step(pos, ne.global_position) if _kite_due() else _raid.relish.move_target
	if _archetype == "bellringer":
		return _vs_bell(pos, w as RaidBellringer, living, safe_px)
	if _archetype == "shieldwall":
		return _vs_wall(pos, w as RaidShieldwall, living)
	var wr_rect := Rect2()
	if _archetype == "huntsman" and int(_raid.layout.get("warden_room", -1)) >= 0:
		wr_rect = (_rooms()[int(_raid.layout["warden_room"])] as Rect2)   # stay in its room: it hunts the undead if she hides
	if pos.distance_to(wp) < safe_px:
		if _archetype == "huntsman":
			# it only hunts inside its room: Relish stays in there too (kiting, and dodging its tells)
			# rather than waiting outside while the army does the work
			var wr := int(_raid.layout.get("warden_room", -1))
			return _back_step(pos, wp, (_rooms()[wr] as Rect2).grow(-float(_raid.relish.radius) - 6.0))
		return _warden_retreat(pos, w, safe_px)
	# outside the danger: collect what is safe to reach
	var loot = _collect_target(pos, living, wp, safe_px, wr_rect)
	if loot != null:
		return _to_point(pos, loot)
	var pk = _pickup_target(pos, living, wp, safe_px, wr_rect)
	if pk != null:
		return _to_point(pos, pk)
	return pos


## The Bellringer fight: raise through it. The beat count says when to go in: for motes the dying
## undead drop (the raise circle needs them) or a pickup, when the trip in and back out fits before the
## next tell with `slam_safe_beats` to spare (`_bell_target`). Inside she works (on to the point she was
## making for, else the motes in reach, else she holds) until she answers a slam tell (`_answers`) or a
## slam ring is out (in plain sight: no roll); then out of the slam. The exit is the tell's answer, not
## the beat count. Outside she gathers what is safe and waits `bell_stage_px` beyond the slam.
func _vs_bell(pos: Vector2, b: RaidBellringer, living: Array, safe_px: float) -> Vector2:
	var wp := b.global_position
	var beats := _bell_beats_to_tell(b)
	var inside := pos.distance_to(wp) < safe_px
	var leave := b._slam_beat >= 0.0
	if not leave and beats <= 0.0:
		leave = _answers("slam", b._next_attack)
	if leave:
		_bell_goal = null
		if inside:
			_why = "bell-out"
			return _warden_retreat(pos, b, safe_px)
	else:
		if beats > 0.0:
			var t = _bell_target(pos, b, living, safe_px, beats)
			if t != null:
				_bell_goal = t
				_why = "bell-in"
				return _to_point(pos, t)
		if inside:
			if _bell_goal != null and pos.distance_to(_bell_goal) > _c("arrive_px", 30.0):
				_why = "bell-in"
				return _to_point(pos, _bell_goal)
			var work = _collect_target(pos, living)
			if work != null:
				_why = "bell-work"
				return _to_point(pos, work)
			_why = "bell-hold"
			return pos
	var loot = _collect_target(pos, living, wp, safe_px)
	if loot != null:
		return _to_point(pos, loot)
	var pk = _pickup_target(pos, living, wp, safe_px)
	if pk != null:
		return _to_point(pos, pk)
	# wait just outside the slam, close enough that the army (which follows her) engages the bell: a
	# far corner left it idle out of the undead's engage leash, and the run stalled out
	if pos.distance_to(wp) > safe_px + _c("bell_stage_px", 120.0):
		_why = "bell-stage"
		return _to_point(pos, wp)
	return pos


## Beats until the next slam's tell begins (negative while a slam is in flight or its tell shows).
func _bell_beats_to_tell(b: RaidBellringer) -> float:
	if b._slam_beat >= 0.0:
		return -1.0
	var tell := float(b.spec.get("attack", {}).get("tell_beats", 1.0))
	return (b._next_attack - tell) - b.beat()


## Where to stand to raise (else fetch a pickup) inside the slam, the trip in and out fitting before the tell. The
## raise reaches `raise_reach_px`, so Relish need not reach the motes: she stops `slam_stand_frac` of
## that from a cluster (`slam_cluster_frac` wide, at least `min_motes`) once the trance will be ready.
## The trip there plus the walk back out of the slam must fit in `beats` less `slam_safe_beats`.
func _bell_target(pos: Vector2, b: RaidBellringer, living: Array, safe_px: float, beats: float):
	var wp := b.global_position
	var speed: float = _raid.relish.speed
	var tempo: float = b.tempo_s()
	var margin := _c("slam_safe_beats", 0.25)
	var reach := _c("raise_reach_px", 300.0)
	var stand := reach * _c("slam_stand_frac", 0.5)
	var cluster := reach * _c("slam_cluster_frac", 0.4)
	var clear := _c("foe_clear_px", 170.0)
	var tr: RaidTrance = _raid.trance
	var ready_in := 0.0
	if tr.state == RaidTrance.State.COOLDOWN or tr.state == RaidTrance.State.LOCKOUT:
		ready_in = tr.cooldown_left
	elif tr.state == RaidTrance.State.ACTIVE or not tr.enabled:
		ready_in = 1.0e9
	var best = null
	var bd := _c("slam_reach_px", 600.0)
	if _raid.carry_room() > 0 and ready_in < 1.0e8:
		var free: Array[Vector2] = []
		for o in _raid.get_tree().get_nodes_in_group("raid_essence"):
			if is_instance_valid(o) and not o.absorbing and not o.carried \
					and _spot_ok(o.global_position, living, clear, Vector2.INF, 0.0):
				free.append(o.global_position)
		for m in free:
			if pos.distance_to(m) >= bd:
				continue
			var ring := RaidLogic.ghost_ring(free, m, cluster, 0.0)
			if int(ring["count"]) < int(_c("min_motes", 3.0)):
				continue
			var c: Vector2 = ring["center"]
			var from_c := pos - c
			var stand_pt := pos if from_c.length() <= reach * 0.9 \
				else c + from_c.normalized() * stand
			var trip := pos.distance_to(stand_pt)
			if ready_in > trip / maxf(1.0, speed):
				continue   # the trance will not be ready by the time she is there
			var out_px := trip + maxf(0.0, safe_px - stand_pt.distance_to(wp))
			if trip < bd and WardenLogic.slam_window_open(beats, out_px, speed, tempo, margin):
				bd = trip
				best = stand_pt
	if best != null:
		return best
	bd = _c("slam_reach_px", 600.0)
	for o in _raid.get_tree().get_nodes_in_group("raid_pickups"):
		if not is_instance_valid(o):
			continue
		var p: Vector2 = o.global_position
		var d := pos.distance_to(p)
		if d >= bd or not _spot_ok(p, living, _c("pickup_foe_clear_px", 90.0), Vector2.INF, 0.0):
			continue
		var out_px2 := d + maxf(0.0, safe_px - p.distance_to(wp))
		if WardenLogic.slam_window_open(beats, out_px2, speed, tempo, margin):
			bd = d
			best = p
	return best


## The Shieldwall fight. While she answers a bash tell (`_answers`): out of the bash arc (its front
## within reach, with `wall_margin_px` and `wall_margin_deg` to spare), fetching only what lies outside
## it. Otherwise she fetches what lies in its room, else waits on its side: `wall_side_deg` off its
## facing, `wall_stand_px` beyond the arc, so a raise there walks in from the side. The side is the
## nearer one, kept until the other is `wall_switch_deg` nearer.
func _vs_wall(pos: Vector2, w: RaidShieldwall, living: Array) -> Vector2:
	var wp := w.global_position
	var at: Dictionary = w.spec.get("attack", {})
	var reach: float = float(at.get("reach_px", 140.0)) + float(_raid.relish.radius) + _c("wall_margin_px", 30.0)
	var half := w.front_half_deg() + _c("wall_margin_deg", 15.0)
	var wr := int(_raid.layout.get("warden_room", -1))
	var room: Rect2 = (_rooms()[wr] as Rect2) if wr >= 0 else Rect2()
	if w.planted and _answers("bash", w._next_attack):
		_avoid_arc = {"from": wp, "facing": w.facing, "half": half, "reach": reach}
		if WardenLogic.bash_hits(w.facing, wp, pos, half, reach, 0.0):
			_why = "wall-out"
			return _wall_stand(pos, w, reach, room)
	var loot = _collect_target(pos, living, Vector2.INF, 0.0, room)
	if loot != null:
		_why = "wall-loot"
		return _to_point(pos, loot)
	var pk = _pickup_target(pos, living, Vector2.INF, 0.0, room)
	if pk != null:
		_why = "wall-pickup"
		return _to_point(pos, pk)
	_why = "wall-side"
	return _wall_stand(pos, w, reach, room)


## The point on the Shieldwall's side to head for: round the wall the short way (WardenLogic.flank_step
## on a circle `wall_stand_px` beyond the bash) toward `wall_side_deg` off its facing, kept in its room.
func _wall_stand(pos: Vector2, w: RaidShieldwall, reach: float, room: Rect2) -> Vector2:
	var wp := w.global_position
	var side := deg_to_rad(_c("wall_side_deg", 110.0))
	var cur := (pos - wp).angle()
	var off_p := absf(WardenLogic.angle_diff(cur, w.facing + side))
	var off_m := absf(WardenLogic.angle_diff(cur, w.facing - side))
	var sw := deg_to_rad(_c("wall_switch_deg", 20.0))
	if _wall_side == 0.0:
		_wall_side = 1.0 if off_p <= off_m else -1.0
	elif _wall_side > 0.0 and off_m + sw < off_p:
		_wall_side = -1.0
	elif _wall_side < 0.0 and off_p + sw < off_m:
		_wall_side = 1.0
	var p := WardenLogic.flank_step(wp, pos, w.facing + side * _wall_side, reach + _c("wall_stand_px", 40.0), _c("wall_step_deg", 45.0))
	if room.size != Vector2.ZERO:
		p = WardenLogic.leash_clamp(room, p, float(_raid.relish.radius) + 8.0)
	return _to_point(pos, p)


## The Pyre-priest fight. On a fire tell she answers (`_answers`): carry a mote out of a lit area when
## the trip in and out fits before the beat (`burn_safe_beats` to spare), else step off the lit area
## that covers her, and fetch only what lies outside the fire. Then the living, then what lies in its
## room, then her stand (_pyre_stand).
func _vs_pyre(pos: Vector2, pp: RaidPyrePriest, living: Array, ne, nd: float) -> Vector2:
	var wr := int(_raid.layout.get("warden_room", -1))
	var room: Rect2 = (_rooms()[wr] as Rect2) if wr >= 0 else Rect2()
	var rel: RaidRelish = _raid.relish
	var clear: float = rel.radius + _c("burn_clear_px", 16.0)
	var stepping := pp.lit and _answers("fire", pp._tell_for)
	if stepping:
		_avoid_burn = {"areas": pp.areas, "r": pp.area_r + _c("burn_clear_px", 16.0)}
		var grab = _burn_fetch(pos, pp, living, room, clear)
		if grab != null:
			_why = "pyre-grab"
			return _to_point(pos, grab)
		if WardenLogic.in_burn(pos, pp.areas, pp.area_r, clear):
			_why = "pyre-off"
			return _to_point(pos, WardenLogic.burn_exit(pos, pp.areas, pp.area_r, clear, room, rel.radius + 8.0))
	if ne != null and nd < _c("kite_px", 240.0):
		return _back_step(pos, ne.global_position) if _kite_due() else rel.move_target
	var loot = _collect_target(pos, living, Vector2.INF, 0.0, room)
	if loot != null:
		_why = "pyre-loot"
		return _to_point(pos, loot)
	var pk = _pickup_target(pos, living, Vector2.INF, 0.0, room)
	if pk != null:
		_why = "pyre-pickup"
		return _to_point(pos, pk)
	_why = "pyre-stand"
	return _to_point(pos, _pyre_stand(pos, pp, room, clear, stepping))


## Where she waits: `pyre_stand_px` beyond the living acolyte nearest her (seen from the priest), so a
## raise there walks into it; once it is exposed, `pyre_exposed_px` from the priest on her side.
## Kept in its room, and off a lit area while she is stepping off this tell (`stepping`).
func _pyre_stand(pos: Vector2, pp: RaidPyrePriest, room: Rect2, clear: float, stepping: bool) -> Vector2:
	var wp := pp.global_position
	var rr: float = _raid.relish.radius + 8.0
	var a := pp.nearest_acolyte(pos)
	var p: Vector2
	if a != null:
		var d := a.global_position - wp
		p = a.global_position + (d.normalized() if d.length() > 1.0 else Vector2.UP) * _c("pyre_stand_px", 60.0)
	else:
		var d2 := pos - wp
		p = wp + (d2.normalized() if d2.length() > 1.0 else Vector2.DOWN) * _c("pyre_exposed_px", 170.0)
	if room.size != Vector2.ZERO:
		p = WardenLogic.leash_clamp(room, p, rr)
	if stepping:
		p = WardenLogic.burn_exit(p, pp.areas, pp.area_r, clear, room, rr)
	return p


## A loose mote inside a lit burn area that she can gather and still be out before the beat: the trip
## to it (less the gather radius) plus the way out of the deepest area covering it must fit in the
## beats left with `burn_safe_beats` to spare (WardenLogic.slam_window_open). The nearest such mote, or
## null (no carry room, or none worth it).
func _burn_fetch(pos: Vector2, pp: RaidPyrePriest, living: Array, room: Rect2, clear: float):
	if _raid.carry_room() <= 0:
		return null
	var speed: float = _raid.relish.speed
	var gather := float(_raid.rcfg().get("essence", {}).get("gather_radius_px", 28.0))
	var left := pp.beats_to_burn()
	var fclear := _c("foe_clear_px", 170.0)
	var best = null
	var bd := INF
	for o in _raid.get_tree().get_nodes_in_group("raid_essence"):
		if not is_instance_valid(o) or o.absorbing or o.carried:
			continue
		var p: Vector2 = o.global_position
		if not _in(room, p):
			continue
		var depth := 0.0
		for c in pp.areas:
			depth = maxf(depth, pp.area_r + clear - p.distance_to(c))
		if depth <= 0.0:
			continue   # outside the fire: the ordinary collection takes it
		var trip := maxf(0.0, pos.distance_to(p) - gather)
		if trip >= bd:
			continue
		var near_foe := false
		for e in living:
			near_foe = near_foe or p.distance_to(e.global_position) < fclear
		if near_foe:
			continue
		if WardenLogic.slam_window_open(left, trip + depth, speed, pp.tempo_s(), _c("burn_safe_beats", 0.35)):
			bd = trip
			best = p
	return best


## Hold a raise (the Pyre-priest, while acolytes live): she is in its room with no living foe within
## `kite_px`, farther than `pyre_raise_px` from every living acolyte, and her carry still has room, so
## the raise waits until the raised undead would walk into one. Out of its room or under threat she
## raises where she is.
func _pyre_hold(pos: Vector2) -> bool:
	var w = _raid.warden_run.warden
	if w == null or not is_instance_valid(w) or not (w is RaidPyrePriest) or not w.alive or not w.awake:
		return false
	var wr := int(_raid.layout.get("warden_room", -1))
	if wr < 0 or RaidLogic.room_of(_raid.layout, pos) != wr:
		return false
	for e in _living():
		if pos.distance_to(e.global_position) < _c("kite_px", 240.0):
			return false
	var a: RaidAcolyte = (w as RaidPyrePriest).nearest_acolyte(pos)
	return a != null and _raid.carry_room() > 0 and pos.distance_to(a.global_position) > _c("pyre_raise_px", 120.0)


## Where to wait out the warden: the farthest of the previous room's centre and this room's far
## corner from it (outside the slam when the geometry allows, otherwise as far as it goes).
func _warden_retreat(pos: Vector2, w: RaidWarden, safe_px: float) -> Vector2:
	var wp := w.global_position
	var cands: Array[Vector2] = []
	if _prev_room >= 0:
		cands.append(_room_center(_prev_room))
	if _cur_room >= 0:
		var r: Rect2 = (_rooms()[_cur_room] as Rect2).grow(-36.0)
		for c in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
			cands.append(c)
	var best := pos
	var bd := -1.0
	for c in cands:
		var d := c.distance_to(wp)
		# a far-enough spot is worth a longer walk; below that, farther is better
		var score := d if d < safe_px else safe_px + 200.0 - pos.distance_to(c) * 0.1
		if score > bd:
			bd = score
			best = c
	return _toward_room(pos, RaidLogic.room_of(_raid.layout, best) if RaidLogic.room_of(_raid.layout, best) >= 0 else _cur_room, best)


## A Huntsman lunge tell is showing and she answers it (`_answers`): step perpendicular to the lunge
## line. Returns the point to run to, or null.
func _dodge_step(pos: Vector2, h: RaidHuntsman):
	if not h._locked or not _answers("lunge", h._next_attack):
		return null
	var from := h.global_position
	var line := h._lock_pt - from
	if line.length() < 1.0:
		return null
	var dir := line.normalized()
	var perp := dir.orthogonal()
	var off := (pos - from).dot(perp)
	var need: float = float(h.spec.get("attack", {}).get("hit_radius_px", 22.0)) + _raid.relish.radius + 14.0
	if absf(off) >= need:
		return pos   # already clear of the line: hold still
	var side := signf(off) if absf(off) > 2.0 else _tell_side
	return pos + perp * side * (need - absf(off) + _c("dodge_step_px", 60.0))


# -------------------------------------------------------------------- raise ---
## Positions of the motes (loose or carried) within `reach` of `pos`.
func _motes_near(pos: Vector2, reach: float) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for o in _raid.get_tree().get_nodes_in_group("raid_essence"):
		if is_instance_valid(o) and not o.absorbing and o.global_position.distance_to(pos) <= reach:
			pts.append(o.global_position)
	return pts


## Raise when the trance is ready and enough motes lie near Relish.
func _try_raise(pos: Vector2) -> void:
	var tr: RaidTrance = _raid.trance
	if tr == null or not tr.enabled or tr.state != RaidTrance.State.READY:
		return
	if _archetype == "pyre_priest" and _pyre_hold(pos):
		return
	var ring := RaidLogic.ghost_ring(_motes_near(pos, 1.0e9), pos, _c("raise_reach_px", 300.0), _c("raise_pad_px", 14.0))
	if not bool(ring["ok"]) or int(ring["count"]) < int(_c("min_motes", 3.0)):
		return
	var trace := _trace_for(ring["center"], ring["radius"])
	var g := CircleScorer.grade(trace)
	_raid.show_trace_feedback(g, trace.duplicate())
	var before: int = _raid.raises
	if g["valid"]:
		_raid.perform_raise(g)
	var raised: bool = _raid.raises > before
	tr.bot_raise_cooldown(raised)
	if raised:
		_scores.append(int(g["score"]))
		if _wake_s >= 0.0:
			_raises_wake += 1
		if _first_raise_s < 0.0:
			_first_raise_s = _sim_t


## 44 points round the circle with seeded radial jitter; the jitter amplitude is binary-searched
## (a few tries) so the scorer's grade lands within `score_tol` of the target score.
func _trace_for(c: Vector2, rad: float) -> PackedVector2Array:
	var n := int(_c("trace_points", 44.0))
	var u: Array[float] = []
	for i in n:
		u.append(_rng.randf_range(-1.0, 1.0))
	var lo := 0.0
	var hi := _c("trace_amp_max", 0.6)
	var best := _ring(c, rad, u, 0.0)
	var best_err := absi(int(CircleScorer.grade(best)["score"]) - _target)
	var amp := hi * 0.5
	for k in int(_c("trace_tries", 8.0)):
		if best_err <= int(_c("score_tol", 5.0)):
			break
		var tr := _ring(c, rad, u, amp)
		var s := int(CircleScorer.grade(tr)["score"])
		if absi(s - _target) < best_err:
			best_err = absi(s - _target)
			best = tr
		if s > _target:
			lo = amp
		else:
			hi = amp
		amp = (lo + hi) * 0.5
	return best


## The loop starts and ends on the same angle (a closed circle), start angle seeded per call.
func _ring(c: Vector2, rad: float, u: Array[float], amp: float) -> PackedVector2Array:
	var n := u.size()
	var out := PackedVector2Array()
	for i in n:
		var ang := TAU * float(i) / float(n - 1)
		out.append(c + Vector2(rad * (1.0 + amp * u[i]), 0).rotated(ang))
	return out
