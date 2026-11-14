class_name BossAutopilot
extends RefCounted
## DEV: the headless boss bot (`--boss-autoplay=<target_score>`). It plays Vei's final test with a
## minimal policy and prints `BOSS_RESULT {json}` (the scene's) then `BOSS_AUTOPLAY {json}` (its own
## numbers), then quits. The measuring instrument for the boss, never a game feature. Standalone
## only: vei_boss.gd creates it. Run it fast and deterministic with
## `--headless --fixed-fps 60 --disable-vsync --max-fps 0`; `--boss-seed=<n>` varies the run.
## Policy, every `think_frames` physics frames (scene time only):
##   dodge   when a weave tell is laid across Relish, sidestep it with probability `dodge`
##           (`--boss-autoplay-dodge=<0..1>` overrides), decided once per tell.
##   raise   when the trance is ready and `min_motes` motes lie within raise_reach_px, draw a
##           trace_points circle round them whose jitter is binary-searched to land within
##           score_tol of the target score (RaidAutopilot's approach, copied).
##   walk    to the nearest mote cluster (phase 1: they fall by the lanes; phase 2: at the
##           anchors); with none, to the nearest contested lane's front or the nearest anchor.
## `--boss-autoplay-log` prints a status line every 2 scene seconds.
## Like RaidAutopilot it never uses the trance's time dilation. All numbers: vei.json autopilot.

var _boss: Node2D
var _cfg: Dictionary = {}
var _target := 70
var _dodge := 0.5
var _rng := RandomNumberGenerator.new()
var _sim_t := 0.0
var _frame := 0
var _done := false
var _scores: Array = []
var _tell_seen := -INF        # the tell (by its start beat) already decided
var _dodging := false
var _dodge_to := Vector2.ZERO
var _dodges := 0
var _log := false


func _init(p_boss: Node2D) -> void:
	_boss = p_boss


static func enabled() -> bool:
	return BossDev.cli_value("--boss-autoplay=") != ""


func start() -> void:
	_cfg = (_boss.vcfg().get("autopilot", {}) as Dictionary)
	_target = int(BossDev.cli_value("--boss-autoplay="))
	var d := BossDev.cli_value("--boss-autoplay-dodge=")
	_dodge = clampf(float(d) if d != "" else _c("dodge", 0.5), 0.0, 1.0)
	_rng.seed = BossLogic.rng_int(str(_boss.seed_data.get("rng_seed", "1"))) ^ 0x0B055B07
	_log = BossDev.cli_flag("--boss-autoplay-log")
	_pin_clock()


func _c(key: String, def: float) -> float:
	return float(_cfg.get(key, def))


## The Pulse reads the wall clock unless pinned; the break's beat 0 aligns to it, so pin it to scene
## time and a headless run does not depend on how fast it runs.
func _pin_clock() -> void:
	Pulse.clock_ms = _sim_t * 1000.0


func physics_tick(delta: float) -> void:
	if _done:
		return
	_sim_t += delta
	_pin_clock()
	_frame += 1
	if _frame % maxi(1, int(_c("think_frames", 3.0))) != 0:
		return
	var rel: RaidRelish = _boss.relish
	if rel == null or not is_instance_valid(rel) or not rel.alive or _boss.is_over():
		return
	if _sim_t > _c("max_s", 600.0):
		print("BOSS_AUTOPLAY timeout t=%.1f" % _sim_t)
		_boss._lose("timeout")
		return
	var pos := rel.global_position
	if _log and _frame % 120 == 0:
		_status(rel)
	_try_raise(pos)
	if _dodge_step(pos):
		return
	rel.move_target = _goal(pos)


func _status(rel: RaidRelish) -> void:
	var raised := 0
	var party := 0
	for a in _boss.allies:
		if is_instance_valid(a) and a.alive:
			if a.role == "party":
				party += 1
			else:
				raised += 1
	print("BOSS_LOG t=%.1f hp=%.0f raised=%d party=%d guards=%d motes=%d streak=%d ema=%.2f/%.2f deaths=%d" % [_sim_t, rel.hp,
		raised, party, _boss.guards_alive(), _motes().size(), int(_boss.brk.get("streak", 0)), float(_boss.brk.get("ema", 0.0)),
		_boss.ferry_beat, _boss.deaths])


# ------------------------------------------------------------------ dodge ---
func _dodge_step(pos: Vector2) -> bool:
	var v: RaidVei = _boss.vei
	if v == null or not v.tell_on or (v.hold_tell and not v.first_done):
		_dodging = false   # (a held dev tell never lands: keep raising under it)
		return false
	var half: float = float(v.wcfg().get("width_px", 64.0)) * 0.5 + float(_boss.relish.radius)
	if v.tell_start != _tell_seen:
		_tell_seen = v.tell_start
		_dodging = BossLogic.weave_hits(v.tell_from, v.tell_to, pos, half) and _rng.randf() < _dodge
		if _dodging:
			_dodges += 1
			var n := (v.tell_to - v.tell_from).normalized().orthogonal()
			var side := signf((pos - v.tell_from).dot(n))
			if side == 0.0:
				side = 1.0 if _rng.randf() < 0.5 else -1.0
			var dist := BossLogic.seg_dist(pos, v.tell_from, v.tell_to)
			var margin := _c("dodge_margin_px", 30.0)
			var want := pos + n * side * maxf(half + margin - dist, 0.0)
			_dodge_to = _boss.resolve_walls(want, _boss.relish.radius)
			if _dodge_to.distance_to(want) > 4.0:   # a wall on that side: cross the thread instead
				_dodge_to = _boss.resolve_walls(pos - n * side * (half + margin + dist), _boss.relish.radius)
	if _dodging:
		_boss.relish.move_target = _dodge_to
		return true
	return false


# ------------------------------------------------------------------- walk ---
func _motes() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for o in _boss.get_tree().get_nodes_in_group("raid_essence"):
		if is_instance_valid(o) and not o.absorbing:
			pts.append(o.global_position)
	return pts


## The nearest mote with at least min_motes motes within cluster_px of it; else a fallback.
func _goal(pos: Vector2) -> Vector2:
	var pts := _motes()
	var cl := _c("cluster_px", 120.0)
	var need := int(_c("min_motes", 3.0))
	var best := Vector2.INF
	var bd := INF
	for p in pts:
		var n := 0
		var c := Vector2.ZERO
		for q in pts:
			if p.distance_to(q) <= cl:
				n += 1
				c += q
		if n < need:
			continue
		c /= float(n)
		var d := pos.distance_to(c)
		if d < bd:
			bd = d
			best = c
	if best != Vector2.INF:
		return best
	if _boss.in_break() and not _boss.anchors.is_empty():
		var ba: Vector2 = _boss.anchors[0]
		for a in _boss.anchors:
			if pos.distance_to(a) < pos.distance_to(ba):
				ba = a
		return ba
	# phase 1, no cluster yet: the nearest contested lane's front
	var target := pos
	var td := INF
	for i in _boss.lanes.size():
		var f: Dictionary = _boss.p1["fronts"][i]
		if bool(f["cleared"]):
			continue
		var head := BossLogic.point_at(_boss.lanes[i], BossLogic.contact_s(float(f["progress"]), _boss.vcfg()))
		if pos.distance_to(head) < td:
			td = pos.distance_to(head)
			target = head
	return target


# ------------------------------------------------------------------ raise ---
func _try_raise(pos: Vector2) -> void:
	var tr: RaidTrance = _boss.trance
	if tr == null or not tr.enabled or tr.state != RaidTrance.State.READY:
		return
	var ring := RaidLogic.ghost_ring(_motes(), pos, _c("raise_reach_px", 260.0), _c("raise_pad_px", 14.0))
	if not bool(ring["ok"]) or int(ring["count"]) < int(_c("min_motes", 3.0)):
		return
	var trace := _trace_for(ring["center"], ring["radius"])
	var g := CircleScorer.grade(trace)
	_boss.show_trace_feedback(g, trace.duplicate())
	var before: int = _boss.raises
	if g["valid"]:
		_boss.perform_raise(g)
	var raised: bool = _boss.raises > before
	tr.bot_raise_cooldown(raised)
	if raised:
		_scores.append(int(g["score"]))


## trace_points round the circle with seeded radial jitter; the amplitude is binary-searched so the
## scorer's grade lands within score_tol of the target (copied from RaidAutopilot._trace_for).
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


func _ring(c: Vector2, rad: float, u: Array[float], amp: float) -> PackedVector2Array:
	var n := u.size()
	var out := PackedVector2Array()
	for i in n:
		var ang := TAU * float(i) / float(n - 1)
		out.append(c + Vector2(rad * (1.0 + amp * u[i]), 0).rotated(ang))
	return out


# ----------------------------------------------------------------- finish ---
## The fight ended (vei_boss._emit, after BOSS_RESULT): print the bot's line once and quit.
func on_finish(result: Dictionary) -> void:
	if _done:
		return
	_done = true
	var avg := 0.0
	for s in _scores:
		avg += float(s)
	if not _scores.is_empty():
		avg /= float(_scores.size())
	var v: RaidVei = _boss.vei
	var out := {"target_score": _target, "seed": str(_boss.seed_data.get("rng_seed", "")), "won": result.get("won", false),
		"end": _boss.end_reason, "phase_reached": "break" if _boss.phase1_s >= 0.0 else "fronts",
		"fronts_cleared": result.get("fronts_cleared", []), "relish_deaths": result.get("relish_deaths", 0),
		"backups_spent": result.get("backups_spent", {}), "duration_s": snappedf(_sim_t, 0.01),
		"phase1_s": snappedf(_boss.phase1_s, 0.01), "streak_max": _boss.streak_max,
		"beats": int(_boss.brk.get("beats", 0)), "raises": _scores.size(), "avg_score": snappedf(avg, 0.1),
		"horde_left": snappedf(_boss.horde, 1.0), "ferry": snappedf(_boss.ferry, 0.01),
		"weaves": v.weaves if v != null else 0, "weave_hits": v.hits if v != null else 0, "dodges": _dodges,
		"party_lost": result.get("party_lost", []), "backlog_spent": snappedf(float(result.get("backlog_spent", 0.0)), 0.1)}
	print("BOSS_AUTOPLAY ", JSON.stringify(out))
	_boss.get_tree().quit()
