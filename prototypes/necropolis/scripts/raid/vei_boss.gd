extends "res://scripts/raid/raid.gd"
## Vei's final test (MECHANICS 6, GAMEPLAY 3d, VISUAL-LANGUAGE 2c): the game's last beat. It reuses
## the raid machinery (Relish, the trance and its scoring, the units, the arena, the HUD) and fights
## on fronts, then the break. The rules are VeiFronts'; BossLogic places and counts; BossLanes draws
## the fronts; RaidVei is Vei and her weaves.
##   fronts (phase 1)  four lanes (giants, swarm, carvers, raw) run from the south to Vei's court.
##                     Each front's stream marches into her guard line (VeiFronts.phase1_step). A
##                     raise adds raise_have_per_mult * sum(stat_mults) to the lane nearest the
##                     circle (phase1_add_raise). fronts_required cleared -> the break;
##                     phase1_max_s -> lost.
##   the break         the horde H (the seed's backlog) is ferried away at F
##   (phase 2)         (VeiFronts.ferry_rate). Motes fall at the anchors at a rate tied to F; Relish
##                     raises there, and every tempo beat feeds VeiFronts.break_beat(raised value
##                     that beat, F per beat). break_beats in a row -> victory; H at 0 -> lost.
##                     Uncleared lanes send guards (they hunt Relish and the undead), more of them
##                     on a fuller pool (VeiFronts.pressured: rate and cap x pressure_mult); raised undead
##                     fight; Vei's weaves hunt Relish on the beat (vei.gd).
##   backups           a Relish death spends VeiFronts.next_backup (a phylactery, then a clone): she
##                     revives in place under a cracked violet ring that stays. None left: the final
##                     death, lost (relish_deaths = spent + 1).
## Setup: `{mode: "boss", run_id, seed_rev, ...}` (STATE-API 2.3; the router's merged legacy keys are
## ignored) reads Game.state.view_boss_seed() (7.2); a standalone run uses vei.json `demo`. The
## result is VeiFronts.boss_result (8.2), emitted exactly once after the closing set piece;
## standalone runs print `BOSS_RESULT {json}`. There is no retreat from this fight; a window close
## mid-fight ends it at once (close_result).
## Dev flags: boss_dev.gd; the bot: boss_autopilot.gd.

enum Phase { FRONTS, BREAK, OVER }

var phase: int = Phase.FRONTS
var fronts: Array = []          # the seed's fronts with have/need, FRONT_IDS order
var p1 := {}                    # VeiFronts phase-1 state
var fronts_cleared: Array = []  # ids cleared in phase 1, frozen when the break begins (_result)
var lanes: Array = []           # BossLogic.lanes
var lanes_node: BossLanes = null
var party_lane := {}            # uid -> lane index (the front VeiFronts counts it on)
var party_units := {}           # uid -> RaidUnit (the break)
var party_lost: Array = []      # party uids whose units died in the scene
var horde := 0.0                # H, the horde left
var horde0 := 0.0
var ferry := 0.0                # F, mass/s
var ferry_beat := 0.0           # F per beat on the break's scale
var uncleared := 0
var pressure := 1.0             # VeiFronts.pressure_mult at the seed's living pool (the break's guards)
var _gvc := {}                  # vcfg() with the guards pressured (VeiFronts.pressured), from the break's start
var brk := {}                   # VeiFronts break state
var streak_max := 0
var lapses := 0                 # beats that lapsed with a streak to lose (the meter's running count)
var lapse_lost := 0             # break pips those lapses cost in all
var lapse_lo := -1              # the last lapse took pips lapse_lo..lapse_hi-1 (flashed while _lapse_t > 0)
var lapse_hi := -1
var _lapse_t := 0.0             # real seconds the last lapse still shows
var beat_raised := 0.0          # raised value this beat
var beat_hist: Array = []       # the last meter.eta_window_beats beats, 1 = gained a pip, 0 = lapsed (the ETA's pace)
var revive_cue := false         # a revive's i-frames are running (BossLanes.SafeCue draws them)
var revive_total := 0.0         # ... of this many seconds
var t2 := 0.0                   # the break's scene clock (beat 0 on a tempo boundary)
var anchors: Array = []
var spent := {"phylactery": 0, "clones": 0}
var deaths := 0
var end_reason := ""
var fight_t := 0.0              # scene seconds of fighting
var phase1_s := -1.0            # how long the fronts took (-1: the break never began)
var stress := false             # DEV --boss-stress (BossDev)

var _mote_acc: Array = [0.0, 0.0, 0.0, 0.0]
var _p1_acc := 0.0              # scene seconds since phase 1 last stepped
var _anchor_acc := 0.0
var _anchor_next := 0
var _guard_acc := 0.0
var _p1_raises := 0
var _p2_raises := 0
var _seq_kind := ""             # "win" | "lose" while the closing set piece plays
var _seq_t := 0.0
var _emitted := false
var _win_r := {}                # the win's result, frozen as Vei breaks (_record_win): recorded, then sent by the press
var _card: VeiCard = null       # the win or loss card, once the closing set piece is done
var _rcfg_cache := {}
var _vw_cache := {}              # vwords(), read once per ConfigDb.data
var _vw_src := {}                # the ConfigDb.data _vw_cache was read from (a reload replaces it)
var _tag_p := -1.0               # the pressure _tag_text was built for (hud_info runs every frame)
var _tag_text := ""
var _bdev: BossDev = null
var _bot: BossAutopilot = null


func vcfg() -> Dictionary:
	return ConfigDb.data.get("vei", {})


## raid.json `vei_fight`: the fight's banners, hints, HUD words and end-card words.
## The walk runs once per ConfigDb.data (the HUD reads this every frame); a reload (ConfigDb.reload, the map's F6)
## replaces that Dictionary, so the next read walks the new one. The Dictionary itself stays ConfigDb's.
func vwords() -> Dictionary:
	if not is_same(_vw_src, ConfigDb.data):
		_vw_src = ConfigDb.data
		_vw_cache = ConfigDb.data.get("raid", {}).get("vei_fight", {})
	return _vw_cache


## The break's guard config: vcfg() with the guards pressured by her living reserve (VeiFronts.pressured), set at
## the break's start ({} before it). BossDev's --boss-stress reads it.
func guard_cfg() -> Dictionary:
	return _gvc


## The boss scene's own warm list (vei.json `sound.warm`): unravel and the param kinds, no warden kinds.
func sound_warm() -> Array:
	return Array(vcfg().get("sound", {}).get("warm", []))


## raid.json with vei.json `arena.layout` merged over its layout (built once): the base build then
## lays out the open boss arena (no partitions across the lanes).
func rcfg() -> Dictionary:
	if _rcfg_cache.is_empty():
		var c: Dictionary = (ConfigDb.data.get("raid", {}) as Dictionary).duplicate(true)
		var lay: Dictionary = c.get("layout", {})
		var over: Dictionary = vcfg().get("arena", {}).get("layout", {})
		for k in over:
			lay[k] = over[k]
		c["layout"] = lay
		_rcfg_cache = c
	return _rcfg_cache


func is_boss() -> bool:
	return true


func fort_name() -> String:
	return str(vwords().get("name", ""))


func fort_tier() -> int:
	return 5


func is_over() -> bool:
	return phase == Phase.OVER


func in_break() -> bool:
	return phase == Phase.BREAK


## The boss's own beat (phase 2: the clock weaves land and pips fill on, which slows with the trance;
## otherwise the Pulse). Its visuals (Vei's rings, the anchor ticks) read these so they stay on it.
func beat_phase() -> float:
	if Pulse.reduced_motion:
		return Pulse.reduced_phase
	if phase == Phase.BREAK:
		return fposmod(BossLogic.beat_of(t2, tempo_s()), 1.0)
	return Pulse.phase()


func beat_wave() -> float:
	if Pulse.reduced_motion:
		return Pulse.reduced_wave
	if phase == Phase.BREAK:
		return exp(-beat_phase() * Pulse.wave_decay)
	return Pulse.wave()


func tempo_s() -> float:
	return Pulse.tempo_ms / 1000.0


## Standalone: the demo seed (setup reads it from vei.json).
func demo_seed() -> Dictionary:
	return {"mode": "boss"}


# ------------------------------------------------------------------- setup ---
func setup(args: Dictionary) -> void:
	seed_data = _boss_seed(args)
	_setup_called = true
	if is_inside_tree() and not _built:
		_build()


## The open run's seed (view_boss_seed), else the demo. Only `run_id` of the args is looked at.
func _boss_seed(args: Dictionary) -> Dictionary:
	var standalone := is_inside_tree() and get_tree().current_scene == self
	if standalone:
		BossDev.apply_cfg_overrides(vcfg())
	var sd: Dictionary = Game.state.view_boss_seed()
	if sd.is_empty():
		if not standalone:
			push_warning("necropolis: boss has no open run; using the demo seed")
		sd = BossLogic.demo_seed(vcfg())
		_from_run = false
		if standalone:
			BossDev.apply_seed_overrides(sd)
	else:
		_from_run = true
		if args.has("run_id") and int(args["run_id"]) != int(sd.get("run_id", -1)):
			push_warning("necropolis: boss args run_id %s is not the open run %s" % [str(args["run_id"]), str(sd.get("run_id"))])
	for e in Results.validate("boss_seed", sd):
		push_error("necropolis: boss seed invalid: " + e)
	sd["fort_id"] = "vei"   # the arena's layout seed for gen_layout; not part of the seed contract
	sd["tier"] = 5
	return sd


## The seed's fronts with have/need, in FRONT_IDS order.
func _fronts_for(sd: Dictionary, vc: Dictionary) -> Array:
	if BossLogic.seed_fronts_empty(sd):
		# TODO(E3): seed fronts. Economy's boss seed carries have/need 0 until E3, so the scene
		# computes them from the seed's party, backlog, pool and q.
		return VeiFronts.have_need(VeiFronts.info_from_boss_seed(sd), vc)
	var out: Array = []
	for id in VeiFronts.FRONT_IDS:
		var f := {"id": id, "need": 0.0, "have": 0.0, "assigned": []}
		for g in sd.get("fronts", []):
			if typeof(g) == TYPE_DICTIONARY and str(g.get("id", "")) == id:
				f = (g as Dictionary).duplicate(true)
		out.append(f)
	return out


func _build_extra() -> void:
	var vc := vcfg()
	rng_combat.seed = BossLogic.rng_int(str(seed_data.get("rng_seed", "1"))) ^ 0x7E1B055
	rng_loot.seed = rng_combat.seed ^ 0x10075EED
	relish.hp = float(seed_data.get("relish_hp", relish.hp))
	relish.max_hp = relish.hp
	ally_engage_px = float(vc.get("raised", {}).get("engage_px", 900.0))
	_fit_camera(vc)
	var size: Vector2 = layout["size"]
	var wt: float = layout["wall_t"]
	vei = RaidVei.new()
	vei.position = Vector2(size.x * 0.5, wt + float(vc.get("court", {}).get("y_px", 200.0)))
	units_root.add_child(vei)
	vei.configure(self, vc)

	fronts = _fronts_for(seed_data, vc)
	if _standalone:
		fronts = BossDev.apply_fronts(fronts, vc)
	p1 = VeiFronts.phase1_start(fronts)
	party_lane = BossLogic.party_lanes(seed_data, vc)
	lanes = BossLogic.lanes(size, wt, vei.position, vc)
	lanes_node = BossLanes.new()
	add_child(lanes_node)
	lanes_node.setup(self, lanes, vc)
	lanes_node.fronts = p1["fronts"]
	var pc: Array = [0, 0, 0, 0]
	for uid in party_lane:
		pc[int(party_lane[uid])] += 1
	lanes_node.party_count = pc

	var marks := BossLanes.BackupMarks.new()
	marks.boss = self
	marks.z_index = 1   # relative: just above Relish
	relish.add_child(marks)
	var safe := BossLanes.SafeCue.new()
	safe.boss = self
	safe.z_index = 1
	relish.add_child(safe)

	hud.show_banner(RaidLogic.word_fmt(vwords(), "banner_court", [VeiFronts.required(vc)]), 3.2, "vei")
	if _standalone:
		var met := 0
		for f in fronts:
			if float(f["have"]) >= float(f["need"]):
				met += 1
		print("BOSS_START from_run=%s fronts_met=%d/%d required=%d backlog=%.0f pool=%.0f q=%.2f backups=%d+%d hp=%.0f" % [
			str(_from_run), met, fronts.size(), VeiFronts.required(vc), float(seed_data.get("backlog", 0.0)),
			float(seed_data.get("living_pool", 0.0)), float(seed_data.get("digest_q", 0.0)),
			int(seed_data.get("phylactery_charges", 0)), int(seed_data.get("clones_ready", 0)), relish.hp])
		_bdev = BossDev.new(self)
		if BossAutopilot.enabled():
			_bot = BossAutopilot.new(self)
			_bot.start()
		_bdev.start()


## The whole arena on screen: the lanes, her court and the anchors all read at once.
func _fit_camera(vc: Dictionary) -> void:
	var ac: Dictionary = vc.get("arena", {})
	var size: Vector2 = layout["size"]
	var view := get_viewport_rect().size
	var m := float(ac.get("margin_px", 40.0))
	var z := minf(view.x / (size.x + 2.0 * m), view.y / (size.y + 2.0 * m))
	cam.zoom = Vector2.ONE * clampf(z, float(ac.get("zoom_min", 0.6)), float(ac.get("zoom_max", 1.0)))
	_cam_follow()
	cam.reset_smoothing()


# ----------------------------------------------------------------- runtime ---
func _post_physics(delta: float) -> void:
	if phase == Phase.OVER:
		return
	fight_t += delta
	if _bdev != null:
		_bdev.physics_tick(delta)
	if _bot != null:
		_bot.physics_tick(delta)
	var t0 := BossDev.pt()
	if phase == Phase.FRONTS:
		_step_fronts(delta)
	elif phase == Phase.BREAK:
		_step_break(delta)
	BossDev.pa("step", t0)


func _process(delta: float) -> void:
	super._process(delta)
	_lapse_t = maxf(0.0, _lapse_t - delta / maxf(0.05, Engine.time_scale))
	if _bdev != null:
		_bdev.tick()
	if _seq_kind != "":
		_step_sequence(delta)


# --- phase 1: the fronts ---
## The fronts advance at phase1.step_s (VeiFronts.phase1_step is pure and builds new state; it is
## linear in dt, so stepping it at 10 Hz is the same fight with fewer allocations per tick).
func _step_fronts(delta: float) -> void:
	var vc := vcfg()
	_front_motes(delta, vc)
	_p1_acc += delta
	if _p1_acc < float(vc.get("phase1", {}).get("step_s", 0.1)):
		return
	var before := 0
	var fs: Array = p1["fronts"]
	for i in fs.size():
		if bool(fs[i]["cleared"]):
			before |= 1 << i
	p1 = VeiFronts.phase1_step(p1, _p1_acc, vc)
	_p1_acc = 0.0
	fs = p1["fronts"]
	for i in fs.size():
		if bool(fs[i]["cleared"]) and (before & (1 << i)) == 0:
			_on_front_cleared(i)
	lanes_node.fronts = fs
	match VeiFronts.phase1_outcome(p1, vc):
		"phase2":
			_begin_break()
		"lost":
			_lose("fronts_held")


func _on_front_cleared(i: int) -> void:
	lanes_node.on_cleared(i)
	RaidFx.ring(fx_root, lanes[i]["b"], Palette.c("undead"), 70.0, 0.6, 3.0)
	var n := VeiFronts.fronts_met(p1["fronts"])
	hud.show_banner(RaidLogic.word_fmt(vwords(), "banner_front", [front_label(String(lanes[i]["id"])), n, VeiFronts.required(vcfg())]),
		2.0, "undead")
	if _standalone:
		print("BOSS_FRONT cleared=%s t=%.1f" % [lanes[i]["id"], float(p1["t"])])


## The fallen along each contested lane's front drop fresh motes (mass 0).
func _front_motes(delta: float, vc: Dictionary) -> void:
	var pc: Dictionary = vc.get("phase1", {})
	var rate := float(pc.get("mote_rate", 0.25))
	var spread := float(pc.get("mote_spread_px", 46.0))
	for i in lanes.size():
		var f: Dictionary = p1["fronts"][i]
		if bool(f["cleared"]):
			continue
		var r := BossLogic.accrue(float(_mote_acc[i]), rate, delta)
		_mote_acc[i] = r["acc"]
		for k in int(r["n"]):
			var head := BossLogic.point_at(lanes[i], BossLogic.contact_s(float(f["progress"]), vc))
			_mote(head + Vector2(rng_combat.randf_range(-spread, spread), rng_combat.randf_range(-spread, spread) * 0.6))


func _mote(p: Vector2) -> void:
	spawn_mote(resolve_walls(p, 6.0), 0.0, false,
		Vector2(rng_combat.randf_range(20.0, 50.0), 0.0).rotated(rng_combat.randf() * TAU))


# --- phase 2: the break ---
func _begin_break() -> void:
	if phase != Phase.FRONTS:
		return
	var vc := vcfg()
	phase = Phase.BREAK
	phase1_s = fight_t
	fronts_cleared = []
	for f in p1["fronts"]:
		if bool(f["cleared"]):
			fronts_cleared.append(String(f["id"]))
	uncleared = VeiFronts.FRONT_IDS.size() - fronts_cleared.size()
	ferry = VeiFronts.ferry_rate({"living_pool": float(seed_data.get("living_pool", 0.0)),
		"digest_q": float(seed_data.get("digest_q", 1.0))}, uncleared, vc)
	pressure = VeiFronts.pressure_mult(float(seed_data.get("living_pool", 0.0)), vc)
	_gvc = VeiFronts.pressured(vc, float(seed_data.get("living_pool", 0.0)))
	horde0 = maxf(0.0, float(seed_data.get("backlog", 0.0)))
	horde = horde0
	ferry_beat = BossLogic.ferry_per_beat(ferry, tempo_s(), vc)
	brk = VeiFronts.break_start()
	t2 = BossLogic.align_t(WardenLogic.wake_phase(Pulse.now_ms(), Pulse.tempo_ms), tempo_s())
	anchors = BossLogic.anchors(lanes, vc)
	lanes_node.phase = 2
	lanes_node.anchors = anchors
	lanes_node.party_shown = false
	_spawn_party(vc)
	vei.start_weaves(float(vc.get("weaves", {}).get("first_beat", 3.0)))
	vei.flare()
	RaidFx.ring(fx_root, vei.global_position, Palette.c("vei"), vei.radius * 3.0, 0.8, 4.0)
	hud.show_banner(str(vwords().get("banner_break", "")), 3.5, "vei")
	if _bdev != null:
		_bdev.on_break()
	if _standalone:
		print("BOSS_BREAK t=%.1f cleared=%s uncleared=%d ferry=%.2f ferry_per_beat=%.3f horde=%.0f pressure=%.3f" % [
			fight_t, str(fronts_cleared), uncleared, ferry, ferry_beat, horde, pressure])


## The party's big undead step out of the streams they led, as units that fight.
func _spawn_party(vc: Dictionary) -> void:
	for e in seed_data.get("party", []):
		var uid := str(e.get("uid", ""))
		var li := int(party_lane.get(uid, -1))
		var pos: Vector2 = relish.position + Vector2(120.0, 0.0).rotated(rng_combat.randf() * TAU)
		if li >= 0:
			var lane: Dictionary = lanes[li]
			var s := 1.0 if bool(p1["fronts"][li]["cleared"]) else BossLogic.contact_s(float(p1["fronts"][li]["progress"]), vc)
			pos = BossLogic.point_at(lane, s) - BossLogic.lane_dir(lane) * 40.0 \
				+ BossLogic.lane_dir(lane).orthogonal() * rng_combat.randf_range(-30.0, 30.0)
		var st: Dictionary = e.get("stats", {})
		var u := spawn_ally_v2("party", "big", 1.0, 0.0, uid, RaidLogic.big_undead_stats(st, rcfg()),
			resolve_walls(pos, 20.0), false, "big")
		u.beef = float(st.get("beef", 0.0))
		u.speed_stat = float(st.get("speed", 0.0))
		u.slots = maxi(1, int(e.get("filled_slots", 1)))
		party_units[uid] = u


func _step_break(delta: float) -> void:
	var vc := vcfg()
	var ts := tempo_s()
	var b0 := BossLogic.beat_of(t2, ts)
	t2 += delta
	var b1 := BossLogic.beat_of(t2, ts)
	horde = BossLogic.horde_step(horde, ferry, delta)
	lanes_node.horde_frac = horde / horde0 if horde0 > 0.0 else 0.0
	for k in BossLogic.beats_crossed(b0, b1):
		var before := int(brk.get("streak", 0))
		brk = VeiFronts.break_beat(brk, beat_raised, ferry_beat, vc)
		if int(brk["streak"]) > before:
			RaidSound.play("streak", {"step": int(brk["streak"])})
		elif int(brk["streak"]) < before:
			lapses += 1
			lapse_lost += before - int(brk["streak"])
			lapse_lo = int(brk["streak"])
			lapse_hi = before
			_lapse_t = float(vc.get("meter", {}).get("lapse_flash_s", 1.2))
		beat_hist = BossLogic.push_beat(beat_hist, int(brk["streak"]) > before, int(vc.get("meter", {}).get("eta_window_beats", 8)))
		beat_raised = 0.0
		streak_max = maxi(streak_max, int(brk["streak"]))
		if VeiFronts.broken(brk, vc):
			_win()
			return
	_anchor_motes(delta, vc)
	if stress and _bdev != null:
		_bdev.stress_tick()   # DEV: the top-up alone holds the guards at the live ceiling (the spawner would stack on top, up to the pressured cap)
	else:
		_spawn_guards(delta, _gvc)
	vei.weave_step(b1)
	if phase == Phase.BREAK and horde <= 0.0:
		_lose("horde_ferried")


## Where the ferried fall: motes at the anchors, round robin, at a rate tied to F.
func _anchor_motes(delta: float, vc: Dictionary) -> void:
	if anchors.is_empty():
		return
	var r := BossLogic.accrue(_anchor_acc, BossLogic.anchor_mote_rate(ferry, vc), delta)
	_anchor_acc = r["acc"]
	var spread := float(vc.get("anchors", {}).get("spread_px", 42.0))
	for k in int(r["n"]):
		var p: Vector2 = anchors[_anchor_next % anchors.size()]
		_anchor_next += 1
		_mote(p + Vector2(rng_combat.randf_range(0.0, spread), 0.0).rotated(rng_combat.randf() * TAU))


func guards_alive() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.alive:
			n += 1
	return n


func _spawn_guards(delta: float, vc: Dictionary) -> void:
	var r := BossLogic.guard_spawn(_guard_acc, delta, uncleared, guards_alive(), vc)
	_guard_acc = r["acc"]
	for k in int(r["n"]):
		spawn_guard()


## One living guard out of an uncleared lane's guard line; it hunts Relish and the undead in its way
## at once (BossGuard). Built here, not via spawn_unit (which reads raid.json's legacy boss block):
## stats from vei.json.
func spawn_guard() -> RaidUnit:
	var open: Array = []
	for i in lanes.size():
		if not bool(p1["fronts"][i]["cleared"]):
			open.append(i)
	if open.is_empty():
		return null
	var vc := vcfg()
	var li: int = open[rng_combat.randi_range(0, open.size() - 1)]
	var lane: Dictionary = lanes[li]
	var dir := BossLogic.lane_dir(lane)
	var p := BossLogic.point_at(lane, BossLogic.contact_s(float(p1["fronts"][li]["progress"]), vc)) \
		+ dir * rng_combat.randf_range(10.0, 50.0) + dir.orthogonal() * rng_combat.randf_range(-26.0, 26.0)
	var u := BossGuard.new()
	u.position = resolve_walls(p, 10.0)
	units_root.add_child(u)
	u.configure(self, "enemy", "guard", vc.get("guards", {}).get("unit", {}))
	u.block_px = float(vc.get("guards", {}).get("block_px", 70.0))
	u.life_left = float(vc.get("guards", {}).get("life_s", 0.0))
	var size: Vector2 = layout["size"]
	var wt: float = layout["wall_t"]
	u.home_room = Rect2(Vector2(wt, wt), size - Vector2(wt, wt) * 2.0)
	u._aggro = true
	u.grow_in()
	enemies.append(u)
	return u


# ------------------------------------------------------------------- raise ---
## A released, scored circle (the trance's, or the bot's). One undead per enclosed mote at
## stat_mult(score). Phase 1: the lane nearest the circle gains the have, and the raised run into
## its stream. Phase 2: the value counts toward this beat's raise rate, and the raised fight.
func perform_raise(g: Dictionary) -> void:
	if phase == Phase.OVER or _ended:
		return
	var center: Vector2 = g["center"]
	var radius: float = g["radius"]
	var picked: Array = raiser.motes_inside(center, radius)
	if picked.is_empty():
		return
	for e in picked:
		e.absorb()
	var score := int(g["score"])
	var n := picked.size()
	var mult := RaidLogic.stat_mult(score, ConfigDb.data.get("circle", {}))
	var tier := RaidLogic.score_class(score, rcfg())
	var mults: Array = []
	for i in n:
		mults.append(mult)
	raises += 1
	first_raise_done = true
	RaidSound.play("raise")
	var fb := raiser._last_feedback
	if fb != null and is_instance_valid(fb):
		fb.raised_n = n
		fb.raised_tier = tier
		fb.raised_mult = mult
	var vc := vcfg()
	if phase == Phase.FRONTS:
		var li := BossLogic.nearest_lane(center, lanes)
		var before := float(p1["fronts"][li]["have"])
		p1 = VeiFronts.phase1_add_raise(p1, String(lanes[li]["id"]), mults, vc)
		lanes_node.fronts = p1["fronts"]
		lanes_node.add_runners(li, n, relish.global_position, rng_combat)
		lanes_node.flash(li)
		_p1_raises += 1
		RaidFx.ring(fx_root, relish.global_position, Palette.c("undead"), 78.0, 0.5, 3.0)
		if _standalone:
			print("BOSS_RAISE fronts lane=%s n=%d score=%d have %.1f -> %.1f" % [lanes[li]["id"], n, score,
				before, float(p1["fronts"][li]["have"])])
	else:
		var v := VeiFronts.raise_value(mults, vc)
		beat_raised += v
		_spawn_raised(n, tier, mult, vc)
		_p2_raises += 1
		if _standalone:
			print("BOSS_RAISE break n=%d score=%d value=%.2f ferry_per_beat=%.3f streak=%d" % [n, score, v, ferry_beat,
				int(brk.get("streak", 0))])


func _spawn_raised(n: int, tier: String, mult: float, vc: Dictionary) -> void:
	var alive := 0
	for a in allies:
		if is_instance_valid(a) and a.alive and a.role == "raised":
			alive += 1
	var k := mini(n, maxi(0, int(vc.get("raised", {}).get("unit_cap", 40)) - alive))
	var stats := RaidLogic.undead_stats(mult, tier, rcfg())
	var ring_px := float(rcfg().get("raise", {}).get("spawn_ring_px", 52.0))
	var rp := relish.global_position
	for i in k:
		var ang := TAU * i / float(maxi(1, k)) + rng_combat.randf() * 0.8
		var pos := rp + Vector2(ring_px + rng_combat.randf_range(-10.0, 26.0), 0.0).rotated(ang)
		spawn_ally_v2("raised", tier, mult, 0.0, "", stats, resolve_walls(pos, 10.0), true)
	if k > 0:
		RaidFx.ring(fx_root, rp, Palette.c("undead"), ring_px + 26.0, 0.5, 3.0)


## A guard's time is up (BossGuard.life_left): it falls back to her line. Not a kill, so no mote.
func recall_guard(u: RaidUnit) -> void:
	if not u.alive:
		return
	u.alive = false
	enemies.erase(u)
	RaidFx.ring(fx_root, u.global_position, Palette.c("living", 0.45), 24.0, 0.35, 1.5)
	u.queue_free()


func on_unit_died(u: RaidUnit, sacrificed: bool) -> void:
	if u.faction == "enemy":
		enemies.erase(u)
		for i in int(vcfg().get("guards", {}).get("motes_on_death", 1)):
			_mote(u.global_position)
		RaidFx.ring(fx_root, u.global_position, Palette.c("living", 0.6), 26.0, 0.3, 2.0)
		return
	allies.erase(u)
	if u.role == "party" and u.uid != "" and not party_lost.has(u.uid):
		party_lost.append(u.uid)
		party_units.erase(u.uid)
	if not sacrificed:
		RaidFx.ring(fx_root, u.global_position, Palette.c("undead", 0.4), 20.0, 0.25, 2.0)


# ----------------------------------------------------------------- backups ---
func backups_spent_total() -> int:
	return int(spent["phylactery"]) + int(spent["clones"])


func backups_left() -> int:
	return BossLogic.backups_left(spent, int(seed_data.get("phylactery_charges", 0)), int(seed_data.get("clones_ready", 0)))


func phylactery_left() -> int:
	return maxi(0, int(seed_data.get("phylactery_charges", 0)) - int(spent["phylactery"]))


func clones_left() -> int:
	return maxi(0, int(seed_data.get("clones_ready", 0)) - int(spent["clones"]))


## Relish's hp reached 0 (relish.gd): spend the next backup and revive her in place.
func try_phylactery() -> bool:
	if phase == Phase.OVER or _ended:
		return false
	var kind := VeiFronts.next_backup(spent, int(seed_data.get("phylactery_charges", 0)), int(seed_data.get("clones_ready", 0)))
	if kind == "":
		return false
	var key := "phylactery" if kind == "phylactery" else "clones"
	spent[key] = int(spent[key]) + 1
	deaths += 1
	var bc: Dictionary = vcfg().get("backups", {})
	relish.revive(relish.max_hp * float(bc.get("revive_hp_frac", 0.6)), float(bc.get("iframes_s", 2.0)))
	revive_cue = true   # her i-frames get a ring and a count (BossLanes.SafeCue), not only the thin danger arc
	revive_total = maxf(0.05, float(bc.get("iframes_s", 2.0)))
	# the backup-crack set piece: a violet ring holds, then cracks; a cracked ring stays on her
	# the loudest moment on screen: a wide violet crack, a white one inside it, a white flare ring
	var cr := float(bc.get("crack_radius_px", 190.0))
	RaidFx.crack(fx_root, relish.global_position, Palette.c("relish"), cr, float(bc.get("crack_s", 1.2)))
	RaidFx.crack(fx_root, relish.global_position, Palette.c("text"), cr * 0.55, float(bc.get("crack_s", 1.2)) * 0.8)
	RaidFx.ring(fx_root, relish.global_position, Palette.c("text"), cr * 1.3, 0.6, 5.0)
	_revive_shove(bc)
	if bool(bc.get("ready_trance", true)):
		trance.ready_now()   # her circle is ready at once (no stored free raise): a real second chance
	hud.flash(Palette.c("relish"))
	var left := backups_left()
	var vw := vwords()
	hud.show_banner(RaidLogic.word_fmt(vw, "banner_crack", [str(vw.get("crack_phyl", "")) if kind == "phylactery" else str(vw.get("crack_clone", "")), left,
		"" if left == 1 else str(vw.get("plural", ""))]), float(bc.get("banner_s", 2.2)), "relish" if left > 0 else "danger")
	if _standalone:
		print("BOSS_BACKUP kind=%s deaths=%d left=%d t=%.1f frame=%d" % [kind, deaths, left, fight_t, Engine.get_process_frames()])
	return true


## The revive shockwave: guards within backups.shove_px are thrown back to it and lose her for
## shove_recover_s, so a revive among guards gives her a fair moment instead of a second death.
## (Under vei.json `backups.ready_trance` the revive also readies her trance, try_phylactery: she can
## raise a new ward at once; the shipped config has it off.)
func _revive_shove(bc: Dictionary) -> void:
	var rp := relish.global_position
	var px := float(bc.get("shove_px", 360.0))
	var secs := float(bc.get("shove_s", 0.35))
	for e in enemies:
		if is_instance_valid(e) and e.alive and e is BossGuard and e.global_position.distance_to(rp) < px:
			e.knock(rp, px, secs, float(bc.get("shove_recover_s", 6.0)))
	RaidFx.ring(fx_root, rp, Palette.c("relish", 0.9), px, secs + 0.25, 4.0)


## No backup left: the final death (relish_deaths = spent + 1).
func on_relish_died() -> void:
	if phase == Phase.OVER:
		return
	deaths += 1
	RaidFx.ring(fx_root, relish.global_position, Palette.c("danger"), 90.0, 0.8, 4.0)
	RaidFx.ring(fx_root, relish.global_position, Palette.c("relish"), 50.0, 0.8, 3.0)
	_lose("relish_unmade")


## There is no retreat from the Vei fight.
func can_retreat() -> bool:
	return false


func try_retreat() -> void:
	pass


func confirm_exit() -> void:
	pass


func exit_hint_ready() -> bool:
	return false


## A window close mid-fight (RaidEndings.close_request; IDLE I5: no run survives a close): the fight
## ends now, emitted synchronously before the quit save. The backups spent so far stay spent. Once
## she broke (her unravel playing) it is the win; otherwise lost, with relish_deaths = the backups
## spent, plus one if the final-death beat was playing (BossLogic.close_fields). The win is the dict frozen
## as she broke (_record_win), the one the state recorded.
func close_result() -> Dictionary:
	var f := BossLogic.close_fields(end_reason, backups_spent_total())
	deaths = int(f["relish_deaths"])
	if phase != Phase.OVER:
		end_reason = "closed"
		phase = Phase.OVER
	_emitted = true   # the closing set piece must not emit again
	_seq_kind = ""
	var r := _win_r if bool(f["won"]) and not _win_r.is_empty() else _result(bool(f["won"]))
	for e in Results.validate("boss", r):
		push_error("necropolis: boss close result invalid: " + e)
	return r


func _exit_result() -> Dictionary:
	return _result(false)


func _death_result() -> Dictionary:
	return _result(false)


# ----------------------------------------------------------------- endings ---
func on_first_weave() -> void:
	hud.show_banner(str(vwords().get("banner_weave", "")), 2.6, "danger")
	RaidFx.ring(fx_root, vei.global_position, Palette.c("vei"), vei.radius * 4.0, 0.9, 4.0)
	RaidFx.ring(fx_root, vei.global_position, Palette.c("danger", 0.8), vei.radius * 2.4, 0.7, 3.0)
	if _standalone:
		print("BOSS_WEAVE first t=%.1f" % fight_t)


func _win() -> void:
	if phase == Phase.OVER:
		return
	end_reason = "broken"
	_end_common()
	_record_win()
	RaidSound.play("unravel")
	vei.unravel_f = 0.0
	_seq_kind = "win"
	_seq_t = 0.0


## Vei broke (P3b, api-request #22): the win's result is frozen now, the one dict the card's press, its self-press
## and a window close send (_emit, close_result), and it is recorded with the open boss run (cmd_boss_won) and saved
## at once (the autosave clock is 30 s of real time, as long as the card waits before pressing itself). From here a
## gap, a quit or a crash resolves the run as this win, never a forfeit: a gap leaves the set piece and the card
## running (RaidLogic.gap_plan), and the press then reads duplicate_run, which the router takes as done
## (RouterLogic.result_done). Recorded at the break, not when the card appears, so the unravel's seconds are covered
## too: nothing in the result moves once the fight is over (the physics step stops at _ended). The demo and the
## standalone bot have no run to record.
func _record_win() -> void:
	_win_r = _result(true)
	if not _from_run:
		return
	var r: Dictionary = Game.state.cmd_boss_won(int(seed_data.get("run_id", 0)), _win_r)
	endings.win_recorded = bool(r.get("ok", false))
	if not endings.win_recorded:
		push_warning("necropolis: the boss win was not recorded: %s %s" % [str(r.get("reason", "")), str(r.get("errors", []))])
		return
	Game.autosave()


## The set piece is done: the board holds, dimmed, under the end card (VeiCard); its one button is
## the way back. The `finished` result is the same dict as ever and emits once, on the button (the
## router then opens the map) or on a window close (close_result: a broken Vei is the win), whichever
## comes first. The standalone bot has no hand to click: it emits at once, as before.
func _win_card() -> void:
	_seq_kind = ""
	if _card == null:
		var info := BossLogic.end_card(seed_data, spent, party_lost, fight_t, horde0, horde)
		info["phyl_total"] = int(seed_data.get("phylactery_charges", 0))
		info["clones_total"] = int(seed_data.get("clones_ready", 0))
		_card = VeiCard.new()
		hud.add_child(_card)
		# the win card presses itself after gap_end.win_card_auto_s (BossLogic.card_auto_due). The win was recorded
		# as she broke (_record_win), so a sleep with the card up keeps it: the gap leaves the card up.
		_card.setup(info, vcfg().get("card", {}), _emit.bind(true), vwords(), float(rcfg().get("gap_end", {}).get("win_card_auto_s", -1.0)))
	if _bot != null and not (_bdev != null and _bdev.hold_card):
		_emit(true)


func _lose(reason: String) -> void:
	if phase == Phase.OVER:
		return
	end_reason = reason
	_end_common()
	hud.show_banner(BossLogic.loss_banner(reason, rcfg().get("vei_loss", {})), 3.0, "danger")
	lanes_node.lose_f = 0.0
	vei.feed_f = 0.0
	_seq_kind = "lose"
	_seq_t = 0.0


## The drain is done: the board holds, dimmed, under the loss card (VeiCard, BossLogic.loss_card), the win
## card's twin. The same dict emits once, on its button (the router then opens the map) or on a window
## close (close_result: a lost fight is the loss), whichever comes first. The standalone bot emits at
## once, as it always has (unless --boss-hold-card).
func _lose_card() -> void:
	_seq_kind = ""
	if _card == null:
		var lw: Dictionary = rcfg().get("vei_loss", {})
		var info := BossLogic.loss_card(seed_data, spent, party_lost, fight_t, end_reason, float(vcfg().get("loss_backlog_keep", 0.35)), rcfg().get("death", {}), lw)
		info["cause"] = BossLogic.loss_cause(end_reason, {"last_hit_src": relish.last_hit_src if relish != null else "", "streak_max": streak_max,
			"break_beats": int(vcfg().get("break_beats", 8)), "fronts_cleared": _cleared_now(), "fronts_required": VeiFronts.required(vcfg())}, lw)
		info["pressure_row"] = BossLogic.pressure_row(pressure, float(seed_data.get("living_pool", 0.0)), lw) if phase1_s >= 0.0 else {}
		info["change"] = BossLogic.loss_change(end_reason, {"last_hit_src": relish.last_hit_src if relish != null else "", "fronts_cleared": _cleared_now()}, lw)
		info["phyl_total"] = int(seed_data.get("phylactery_charges", 0))
		info["clones_total"] = int(seed_data.get("clones_ready", 0))
		_card = VeiCard.new()
		hud.add_child(_card)
		_card.setup(info, vcfg().get("card", {}), _emit.bind(false), vwords())
	if _bot != null and not (_bdev != null and _bdev.hold_card):
		_emit(false)


## The ids of the fronts that have fallen: the list frozen at the break, or phase 1's own until then.
func _cleared_now() -> Array:
	if phase1_s >= 0.0:
		return fronts_cleared
	var out: Array = []
	for f in p1.get("fronts", []):
		if bool(f["cleared"]):
			out.append(String(f["id"]))
	return out


## A gap (RaidEndings.gap_end) forfeits a boss fight in the state (no writeback) unless its win was recorded
## (_record_win; then the gap leaves the end running), so a closing set piece or card still up would contradict
## it: stop the set piece and take the card down.
func gap_cut_end() -> void:
	_seq_kind = ""
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = null


func _end_common() -> void:
	phase = Phase.OVER
	_ended = true
	revive_cue = false   # the i-frames cue is gone with the fight (win card and loss both)
	trance.force_end()
	Engine.time_scale = 1.0
	vei.stop_weaves()
	if _standalone:
		print("BOSS_END reason=%s t=%.1f streak_max=%d deaths=%d horde=%.0f" % [end_reason, fight_t, streak_max, deaths, horde])


## The closing set pieces on real time (the base physics step stops once the run has ended).
## Victory: her rings unravel stroke by stroke, then every lane runs green toward her and stops.
## Loss: the lanes drain into her and dim. Reduced motion: shorter and stepped, palette only.
func _step_sequence(delta: float) -> void:
	_seq_t += delta / maxf(0.05, Engine.time_scale)
	var ec: Dictionary = vcfg().get("end", {})
	var reduced: bool = Pulse.reduced_motion
	var k := float(ec.get("rm_scale", 0.6)) if reduced else 1.0
	if _seq_kind == "win":
		var un := float(ec.get("unravel_s", 1.3)) * k
		var gr := float(ec.get("green_s", 0.8)) * k
		var f := clampf(_seq_t / maxf(un, 0.01), 0.0, 1.0)
		vei.unravel_f = floorf(f * 4.0) / 4.0 if reduced else f
		if _seq_t >= un:
			if lanes_node.win_f < 0.0:
				lanes_node.win_f = 0.0
				for i in lanes.size():
					lanes_node.on_cleared(i)
			lanes_node.win_f = clampf((_seq_t - un) / maxf(gr, 0.01), 0.0, 1.0)
			if lanes_node.win_f >= 1.0:
				lanes_node.frozen = true   # every lane green toward her, and the lines stop
		if _seq_t >= un + gr + float(ec.get("hold_s", 0.7)) * k:
			_win_card()
	else:
		var dr := float(ec.get("drain_s", 1.4)) * k
		var f2 := clampf(_seq_t / maxf(dr, 0.01), 0.0, 1.0)
		lanes_node.lose_f = floorf(f2 * 3.0) / 3.0 if reduced else f2
		vei.feed_f = lanes_node.lose_f
		if _seq_t >= dr + float(ec.get("lose_hold_s", 0.5)) * k:
			_lose_card()


## The boss result (BossLogic.result_of, tested): fronts_cleared is the list frozen at the break, or,
## when the fight ended in phase 1 (a timeout, a final death, a window close), what phase 1 had
## cleared by then.
func _result(won: bool) -> Dictionary:
	return BossLogic.result_of(fight_state(), won)


## The fight's state as the result reads it; a plain dump of the fields, no logic.
func fight_state() -> Dictionary:
	return {"seed": seed_data, "p1": p1, "fronts_cleared": fronts_cleared, "phase1_s": phase1_s, "deaths": deaths,
		"spent": spent, "party_lost": party_lost, "horde0": horde0, "horde": horde}


func _emit(won: bool) -> void:
	if _emitted:
		return
	_emitted = true
	_seq_kind = ""
	var r := _win_r if won and not _win_r.is_empty() else _result(won)  # the win: the dict recorded as she broke
	for e in Results.validate("boss", r):
		push_error("necropolis: boss result invalid: " + e)
	if _card != null and _standalone:
		_card.visible = false   # the standalone result panel takes its place
	if _standalone:
		print("BOSS_RESULT ", JSON.stringify(r))
	endings.finish(r)
	if _bot != null:
		_bot.on_finish(r)


# --------------------------------------------------------------------- HUD ---
## Front `id`'s upper-cased name (vei_loss.front_names, BossLogic.front_label): the lane labels and the banner.
func front_label(id: String) -> String:
	return BossLogic.front_label(id, rcfg().get("vei_loss", {}))


## The guards tag (BossLogic.pressure_tag), rebuilt only when `pressure` changes: it is set once, in `_begin_break`
## (the pool it comes from is the seed's and never moves), so the per-frame HUD read costs one compare.
func _pressure_tag() -> String:
	if pressure != _tag_p:
		_tag_p = pressure
		_tag_text = BossLogic.pressure_tag(pressure, rcfg().get("vei_loss", {}))
	return _tag_text


## What the boss HUD block shows, read each frame (raid_hud.gd BossBlock).
func hud_info() -> Dictionary:
	var vc := vcfg()
	var met := VeiFronts.fronts_met(p1.get("fronts", [])) if phase1_s < 0.0 else fronts_cleared.size()
	var hint := ""
	if not _ended:
		if phase == Phase.FRONTS and _p1_raises == 0:
			hint = str(vwords().get("hint_fronts", ""))
		elif phase == Phase.BREAK and _p2_raises == 0:
			hint = str(vwords().get("hint_break", ""))
	var mc: Dictionary = vc.get("meter", {})
	var break_s := fight_t - phase1_s if phase1_s >= 0.0 else 0.0
	var eta := ""
	if phase == Phase.BREAK:
		eta = BossLogic.eta_text(BossLogic.break_eta_s(beat_hist, int(brk.get("streak", 0)), int(vc.get("break_beats", 8)),
			int(vc.get("lapse_cost", -1)), tempo_s(), int(mc.get("eta_min_beats", 4)), float(mc.get("eta_max_s", 240.0))), vwords())
	var rule_on := phase == Phase.BREAK and break_s < float(mc.get("hint_s", 14.0))
	return {"phase": phase, "break_began": phase1_s >= 0.0, "eta": eta, "rule_on": rule_on,
		"rule": BossLogic.phase2_hint(int(vc.get("break_beats", 8)), int(vc.get("lapse_cost", -1)), vwords()) if rule_on else "", "met": met, "required": VeiFronts.required(vc),
		"t": float(p1.get("t", 0.0)), "max_t": float(vc.get("phase1_max_s", 90.0)),
		"pressure": pressure, "pressure_tag": _pressure_tag(),
		"horde": horde, "ferry": ferry, "streak": int(brk.get("streak", 0)), "break_beats": int(vc.get("break_beats", 8)),
		"winning": float(brk.get("ema", 0.0)) > ferry_beat, "phyl_left": phylactery_left(), "clones_left": clones_left(),
		"spent_phyl": int(spent["phylactery"]), "spent_clones": int(spent["clones"]), "hint": hint,
		"over": phase == Phase.OVER, "won": end_reason == "broken",
		"lapses": lapses, "lapse_lost": lapse_lost, "lapse_lo": lapse_lo, "lapse_hi": lapse_hi, "lapse_on": _lapse_t > 0.0,
		"notch": int(vc.get("meter", {}).get("notch_every", 5))}
