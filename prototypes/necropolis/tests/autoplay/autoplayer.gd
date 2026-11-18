class_name Autoplayer
extends RefCounted
## E3-6b: the autoplayer (IDLE §8, the run's pacing-spine §4, BALANCE §2 and §8). It plays a real GameState headless,
## through its commands and views only, for simulated days under a player profile, and prints what E3-7's report reads:
## `AUTOPLAY_ROW <json>` per sample and `AUTOPLAY_SUMMARY <json>` once at a profile's end. A test harness: nothing under
## scripts/ reads it. Each profile is its own slow suite (tests/slow/autoplay_<profile>.gd, thin wrappers over
## run_profile()); tests/test_autoplay_smoke.gd runs first30 and 40 min of sessions in the default suite. It measures; it
## asserts no balance number (E4 calibrates). IDLE §8 has one paragraph per profile and the policy list.
##
## The rules (the run's manager, for Shawn):
## - Commands only. A profile starts from cmd_new_game(SEED) (away_risk's fallback from the midgame_2flips fixture) and from
##   then on calls only cmd_* and view_*. Every GameState it plays has debug_enabled false, so a cmd_debug_* would be
##   refused; the only fields it sets are a fresh state's save seams (save_dir, clock_override) before its cmd_load.
## - Closed is cmd_save, a fresh GameState, then cmd_load with clock_override the gap later, so the real catch-up runs
##   (close()). Open is the same GameState ticked live through the frame path, tick(FRAME_DT, max_substeps_per_frame()).
## - A raid takes its duration live (_raid): Relish walks to the fort (ticked until she arrives), cmd_begin_dungeon, E3-6a's
##   StandinResolver turns the seed into a result and its duration_s (deaths "human", door true, held = view_fort().held
##   read just before the begin, the blueprints owned), the game ticks live that long, then apply_result("raid", r). A
##   death leaves her dead for the real respawn_s and the bot waits; else she walks home.
## - The field is 8 x 6 (tests/test_catchup.gd's cfgs(), the harness convention): the shipped 128 x 90 costs 11.5 ms a
##   live substep against 0.64 ms, which no profile can afford. The field decides the villages' owners, so the migrants
##   (living, gold) are labelled with it (labels()).
##
## The schedule (sessions-type profiles): three 20 min sessions a sim day, at 00:00, 04:00 and 08:00 from the new game,
## closed 3 h 40 m, 3 h 40 m, then a 15 h 40 m night (the brief's "8 h apart, then a 16 h night" can't fit three sessions
## in 24 h; this keeps the 16 h night, which "Vei's odds 12 h after closing" needs). A day ends at the next day's 00:00
## load, before the bot acts: its `day_end` row and the I1 sample are taken there.

const CLOCK0 := 1_800_000_000  # the unix "now" of t = 0
const SEED := 1
const DAY := 86400
const SESSION_S := 1200
const SESSION_OFFSETS := [0, 14400, 28800]
const FIRST30_S := 1800
const FRAME_DT := 0.5  # one substep a frame call: the frame path's cadence changes cost, never results (STATE-API §3)
const OPEN_ROW_S := 1800.0  # an `open` row every 30 min of sim in open profiles
const FINE_S := 10.0  # the mint and bodies_net sample (live time only)
const ACT_S := 60.0  # while it waits in a session the bot looks at the town this often
const PROBE_S := 43200  # Vei's odds this long into each night (a probe load; the run itself loads once)
const PARTY_MAX := 3  # the largest standard party: raid.json autopilot.party_profiles "4", three bigs
const HELD_RAID_YIELD := 0.5  # raid a held fort once its yield_mult is back to this
const STANCES := ["vigil", "harvest"]
const BANK_FRONTS := ["giants", "carvers"]  # bank_bigs: the fronts only the bigs fill (no backlog term; carvers' q aside)
const VEI_READY_ODDS := 0.6  # BALANCE §1's Vei-ready: odds >= 0.6 and fronts_required fronts met (E4 step 3: the odds gate)
# (since Phase I P3's odds split the gate reads view_vei's readiness, the old formula, not its first-attempt odds)
const KEEP_SHARE := 0.25  # keep_fronts: a keeper brings at least this share of what the bigs must bring to its front
const RAID_ROOM := 2  # keep_fronts: keepers leave the crypt room for this many raiders (two raiders reach t3)
const SLOT := "ap"
## BALANCE §2's "removed" for ablation (b): the dead's buildings (BALANCE §7's list) cost no bone at any level.
const DEAD_BUILDINGS := ["raising_pit", "charnel_house", "bone_mill", "stables", "graveyard", "embalmer", "forge"]
const BANDS := [["S0", 0.0, 1800.0], ["S1", 1800.0, 86400.0], ["S2", 86400.0, 432000.0], ["S3", 432000.0, 1.0e15]]

## The queue's fixed priority list, [building, lot, level], walked top first (_fill). Justified from BALANCE: the spine's
## S0 row (gold to Market L2, a pit and a mill, one house; bone to the pit, charnel, mill and market), the Village gate
## (economy.json town.tiers: a Market and a House, 6 buildings), each producer bought with the other resource and the
## mill and Market climbing in step so every price fits a cap (BALANCE §5, §7), the tier-defining buildings on the lots
## BALANCE §5 keeps for them (the Chapel on lot-13, Walls on lot-23, the Reliquary on lot-24, the Ossuary on lot-16, so
## no house fills them: G3's failure), the Town gate (Walls, the Chapel, 12 buildings), then pits for the mint, the Forge
## for q, the Stables for the haul, the Embalmer and the backups' Ossuary. The Bone Mill is not first by fiat: with the
## start's 30 bone and no mill the Market's level 2 reads -1, and the reorder rule picks the soonest-affordable entry.
const BUILD_LIST := [
	["market", "lot-04", 2], ["raising_pit", "lot-05", 1], ["bone_mill", "lot-06", 1], ["house", "lot-07", 1],
	["bone_mill", "lot-06", 2], ["raising_pit", "lot-02", 2], ["charnel_house", "lot-03", 2], ["house", "lot-08", 1],
	["chapel_of_vats", "lot-13", 1], ["walls", "lot-23", 1], ["market", "lot-04", 3], ["bone_mill", "lot-06", 3],
	["forge", "lot-14", 1], ["raising_pit", "lot-09", 1], ["raising_pit", "lot-05", 2], ["stables", "lot-15", 1],
	["house", "lot-10", 1], ["embalmer", "lot-12", 1], ["raising_pit", "lot-11", 1], ["ossuary_tower", "lot-16", 1],
	["reliquary", "lot-24", 1], ["raising_pit", "lot-17", 1], ["raising_pit", "lot-18", 1], ["house", "lot-19", 1],
	["house", "lot-20", 1], ["raising_pit", "lot-21", 1], ["raising_pit", "lot-22", 1],
]
## Then the level ladder (BALANCE §7: upgrading in place is the compounding that survives the lot caps), level by level
## to each building's max_level: the mill and the Market first (the caps), the pits, the charnel house, the Forge and the
## Chapel, the houses.
const LADDER := [
	["bone_mill", "lot-06"], ["market", "lot-04"], ["raising_pit", "lot-02"], ["raising_pit", "lot-05"],
	["raising_pit", "lot-09"], ["charnel_house", "lot-03"], ["forge", "lot-14"], ["chapel_of_vats", "lot-13"],
	["raising_pit", "lot-11"], ["raising_pit", "lot-17"], ["raising_pit", "lot-18"], ["raising_pit", "lot-21"],
	["raising_pit", "lot-22"], ["house", "lot-07"], ["house", "lot-08"], ["house", "lot-10"], ["house", "lot-19"],
	["house", "lot-20"], ["stables", "lot-15"], ["embalmer", "lot-12"], ["ossuary_tower", "lot-16"],
]

## The crypt's levels (E4 step 2's sizing, ruling 2: economy.json big_undead.per_crypt_level, a place a level), put at
## the head of the list from the first look that keeps a big, or finds the crypt full while a husk waits (_crypt_up).
const CRYPT_LEVELS := [["crypt", "lot-01", 2], ["crypt", "lot-01", 3]]

static var _list_cache: Array = []

var profile := ""
var c: Dictionary = {}
var sb: Dictionary = {}
var s: GameState
var dir := ""
# policy switches
var deaths := "human"
var reorder := true
var no_held := false  # ablation (a): never raid a held (or refilled) fort
var static_raids := false  # static: one raid a session at the day's tier
var stop_at_vei := false
var war_topup := true  # ruling 3 (03:28): WAR set in-session for the held forts, where a player would (_war_topup)
var war_log: Array = []  # each valve change _war_topup made: {t, from, to, low_before, low_after, covered, let_go}
const WAR_STEP := 0.05  # _war_topup and prepare_away move WAR in these steps
const WAR_MAX := 0.95  # the most WAR either sets
var bank_bigs := false  # bank_bigs (E3-7): no raid takes a big once the giants or carvers front is short
var _banking := false  # bank_bigs' latch: set at the first look that finds giants or carvers short
var keep_fronts := true  # E4 step 2: good front bigs stay home (_keepers) and the rest raid; off = the E3 policy
var _keep: Array = []  # keep_fronts: the keepers' uids at the last look (_place); _raid leaves them home
var park_relics := true  # Phase I P2 (_fill): keep one no_relics entry parked in the queue (the wall's chip); off = skip every gated item
## Phase I P3 (the run's manager's ruling 2 of 2026-11-18 03:10): players park gated builds, since it costs nothing, so the
## bot does too. On (the default), _fill's spare list room takes the priority list's next items that land skipped_gate on a
## gate time or play clears (_park, PARK_GATES); off is P2's skip fill, the ablation_skip_fill profile's row.
var park_gated := true
const PARK_GATES := ["needs_tier", "no_relics", "lot_locked", "needs_blueprint", "needs_building"]
var _crypt_up := false  # the crypt-level latch (_fill): set at the first look that keeps a big, or finds the crypt full while a husk waits
var crypt_up_t := -1.0  # when _crypt_up set (s.t), -1 never; it never clears, so it can't churn (the E4 review's item 5)
## The keepers' churn (the E4 review's item 5, a report): looks whose keepers changed, keepers dropped while still held
## (churn proper: a big leaves the fronts with nothing lost), drops re-kept later (flip_backs), and the looks where the
## other front order won, by the tie-break that chose it (_keepers: met, kept, cov).
var keep_churn := {"looks": 0, "changes": 0, "drops_held": 0, "flip_backs": 0, "alt_by": {"met": 0, "kept": 0, "cov": 0}}
var _dropped := {}  # uid: true, a keeper dropped while held (keep_churn's flip_backs)
var raised: Array = []  # every big raised: [t_h, kind, wits, beef]
var crafted: Array = []  # every husk crafted (_craft_husk): [t_h, kind]
var print_rows := true
var open_rows := false
var live_days := false  # emit a day_end row when live time crosses a day boundary (continuous)
var record := false  # log every command for a lockstep replay (the I1 gate's leader)
var sample_i1 := false
# what it saw
var cmd_log: Array = []
var div: Array = []
var thr_row := {}  # the replay's first command answered otherwise than the leader's, with its thresholds (threshold_row)
var bodies_row := {"n": 0, "worst": -1.0, "worst_t": -1.0, "worst_bound": 0.0, "breaks": 0, "first_break": {}}  # (bodies_gap_add)
var rows: Array = []
var i1: Array = []
var wave_targets := {}  # with sample_i1: each tithe wave's fort and start t, by wave_id (the I1 report's target row)
var notes: Array = []
var builds: Array = []
var done: Array = []
var deaths_ev: Array = []
var flips: Array = []
var retakes: Array = []
var loot: Array = []
var unpaid: Array = []
var tiers: Array = []
var clears: Array = []
var closes: Array = []
var raids: Array = []
var fronts_daily: Array = []
var input_limited: Array = []
var first_raid := {}
var beats := {}
var reorders := 0
var refusals := {}
var results := {"validated": 0, "invalid": 0, "applied": 0, "refused": 0, "errors": []}
var ledger_max := 0.0
var vei_ready_t := -1.0
var vei_ready_wave_t := -1.0  # the old readout beside it (the sizing stop's ruling R2): fronts at her pool then, at the look
var first :={"vat": -1.0, "chapel": -1.0, "clone": -1.0, "wall_queue": -1.0, "wall_report": -1.0, "full_raid": -1.0,
	"bone_wait_seen": -1.0, "bone_wait_event": -1.0, "lots_full": -1.0}
var _fine_day := {}
## Q-h (Phase I P3): the muster rate per day of live time, at each FINE_S sample: {n, muster_sum, work_sum} (GameState's
## split: the muster TownSim took from the WORK stream, and that stream), for summary's workers.muster_per_day
var _muster_day := {}
var _win := {}
var _next_fine := 0.0
var _next_open_row := 0.0
var _next_day := float(DAY)
var _pending := {}
var _cap := 16
var _clock := 0.0  # the replay's schedule clock (_open_to)


func _init(p: String, cfgs_in: Dictionary, save_dir := "") -> void:
	profile = p
	c = cfgs_in
	sb = cfgs_in.get("balance_standins", {})
	dir = save_dir if save_dir != "" else "user://autoplay_%d_%s" % [OS.get_process_id(), p]
	DirAccess.make_dir_recursive_absolute(dir)
	_win = _stat0()


# ------------------------------------------------------------------------------------------- configs ---
## The shipped configs with the field at 8 x 6 and its pre-warm off (test_catchup.gd's cfgs(), the harness convention),
## and a variant: "no_bone_prices" is ablation (b), the dead's buildings at 0 bone (cost and every level_costs entry;
## their gold prices unchanged).
static func cfgs(variant := "") -> Dictionary:
	var out := TestUtil.shipped_configs()  # (Phase I P3) the shipped default: the bots get Grow because it is on
	out["realm"]["field"]["w"] = 8
	out["realm"]["field"]["h"] = 6
	out["economy"]["sim"]["prewarm_ticks"] = 0
	if variant == "no_bone_prices":
		for id in DEAD_BUILDINGS:
			var b: Dictionary = out["buildings"][id]
			(b["cost"] as Dictionary)["bone"] = 0.0
			for lc in b.get("level_costs", []):
				(lc as Dictionary)["bone"] = 0.0
	return out


## AUTOPLAY_DAYS (a positive whole number) shortens or lengthens every multi-day profile; else `default`.
static func days_env(default: int) -> int:
	var e := OS.get_environment("AUTOPLAY_DAYS")
	return int(e) if e.is_valid_int() and int(e) > 0 else default


func _fresh() -> GameState:
	var g := GameState.new(c)
	g.debug_enabled = false
	g.save_dir = dir
	_cap = g.max_substeps_per_frame()
	return g


func new_game(seed := SEED) -> void:
	s = _fresh()
	s.cmd_new_game(seed)
	s.drain_events()
	# one substep first: until the first step the town has no rates and every short queue entry reads -1
	_frame()


func cleanup() -> void:
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(dir)


# ------------------------------------------------------------------------------------------- ticking ---
func _frame() -> void:
	s.tick(FRAME_DT, _cap)
	for e in s.drain_events():
		_on_event(e, "live")
	if s.t >= _next_fine - 1e-9:
		_fine_sample()
		_next_fine = s.t + FINE_S
	if live_days and s.t >= _next_day - 1e-9:
		_next_day += DAY
		_day_end()
	if open_rows and s.t >= _next_open_row - 1e-9:
		_next_open_row += OPEN_ROW_S
		_row("open")


func _tick_to(target: float) -> void:
	while s.t < target - 1e-9:
		_frame()


func _frames(n: int) -> void:
	for i in n:
		_frame()


## Ticks until `cond` holds, at most to `limit`; whether it held.
func _tick_until(cond: Callable, limit: float) -> bool:
	while not cond.call():
		if s.t >= limit - 1e-9:
			return false
		_frame()
	return true


# ------------------------------------------------------------------------------------------ commands ---
func _exec(op: String, a: Array) -> Dictionary:
	match op:
		"queue":
			return s.cmd_queue_build(str(a[0]), str(a[1]))
		"reorder":
			return s.cmd_reorder_queue(a[0])
		"raise":
			return s.cmd_raise_big_undead(str(a[0]), a[1], str(a[2]))
		"party":
			return s.cmd_set_party(a[0])
		"front":
			return s.cmd_assign_front(str(a[0]), str(a[1]))
		"place":
			return s.cmd_place_big_undead(str(a[0]), str(a[1]))
		"vat":
			return s.cmd_staff_vat(int(a[0]), bool(a[1]))
		"craft":
			return s.cmd_craft(str(a[0]))
		"craft_husk":
			return s.cmd_craft_husk(str(a[0]))
		"stance":
			return s.cmd_set_stance(str(a[0]), bool(a[1]))
		"move":
			return s.cmd_move_relish(str(a[0]))
		"valve":
			return s.cmd_set_valve(float(a[0]), float(a[1]), float(a[2]))
		"deploy":
			return s.cmd_deploy_simulacrum(str(a[0]))
		"begin":
			return s.cmd_begin_dungeon(str(a[0]))
		"apply":
			return s.apply_result("raid", a[0])
		"abort":
			return s.cmd_abort_dungeon()
	push_error("Autoplayer: unknown op %s" % op)
	return {"ok": false, "reason": "unknown_op"}


func _after(op: String, a: Array, r: Dictionary) -> void:
	if not bool(r.get("ok", false)):
		var k := "%s:%s" % [op, str(r.get("reason", ""))]
		refusals[k] = int(refusals.get(k, 0)) + 1
		return
	match op:
		"reorder":
			reorders += 1
		"vat":
			if first["vat"] < 0.0:
				first["vat"] = s.t
		"raise":
			if beats.has("first_big") and float(beats["first_big"]["t"]) < 0.0:
				beats["first_big"] = {"happened": true, "t": s.t, "uid": str((r["big_undead"] as Dictionary).get("uid", ""))}


func _cmd(op: String, a: Array, extra := {}) -> Dictionary:
	var t0 := s.t
	var pre := _stock_snap() if record else {}
	var r := _exec(op, a)
	_after(op, a, r)
	if record:
		var e := {"t": t0, "op": op, "args": [] if op == "apply" else a.duplicate(true), "ok": bool(r.get("ok", false)),
			"reason": str(r.get("reason", "")), "snap": pre}
		e.merge(extra)
		cmd_log.append(e)
	return r


## The town stocks a command's answer can turn on, read just before it (the I1 replay's threshold row).
func _stock_snap() -> Dictionary:
	var tn := s.view_town()
	var inv := s.view_inventory()
	return {"bone": float(tn["bone"]), "gold": float(tn["gold"]), "relics": int(inv["relics"]),
		"remnants": (inv["remnants"] as Array).size(), "husks": (inv["husks"] as Array).size(),
		"queue_len": (tn["queue"] as Array).size(), "queue_slots": int(tn["queue_slots"]), "bodies": float(tn["bodies"])}


## The thresholds `op`'s answer turns on, read from this run's state: [stock, "ge" | "lt", value]. A husk craft needs the
## bone and the remnants at their price; a queue command needs a slot (queue_slots under queue_max) and the list under its
## cap (Phase I P2's queue rule). Other ops: none known.
func _thresholds(op: String) -> Array:
	match op:
		"craft_husk":
			var cost: Dictionary = s.view_catalog()["husk_craft"]["cost"]
			return [["bone", "ge", float(cost["bone"])], ["remnants", "ge", float(cost["remnants"])]]
		"queue":
			var tn := s.view_town()
			return [["queue_slots", "lt", float(tn["queue_max"])], ["queue_len", "lt", float(tn["queue_list_max"])]]
	return []


## The I1 replay's threshold row (the E4 review's item 9; a report row, not a gate), for the first command answered
## otherwise than the leader's: each of its thresholds with the closed run's stock (logged before the leader's command)
## and the open run's (just before the replayed one), and whether the threshold lies between them (a straddle: one run
## on each side). The other stocks that differ are listed too. {} when nothing diverged. Each threshold row carries
## its stock gap, closed − open and |closed − open| ÷ max(|open|, 1) (`gap_rel`), and `stock_gap` is the largest: a
## straddle on a gap well over catchup_tol means the runs were already apart, not a tie on the line (the step 4
## review's item 7: 328.92 against 284.09 bone is 15.8%).
static func threshold_row(e: Dictionary, open_snap: Dictionary, thr: Array) -> Dictionary:
	var closed: Dictionary = e.get("snap", {})
	var rows: Array = []
	var straddle := false
	var gap := 0.0
	for th in thr:
		var k := str(th[0])
		var c := float(closed.get(k, 0.0))
		var o := float(open_snap.get(k, 0.0))
		var v := float(th[2])
		var pc := c >= v if str(th[1]) == "ge" else c < v
		var po := o >= v if str(th[1]) == "ge" else o < v
		var rel := absf(c - o) / maxf(absf(o), 1.0)
		rows.append({"stock": k, "need": "%s %s" % ["≥" if str(th[1]) == "ge" else "<", str(_r(v))], "closed": _r(c), "open": _r(o),
			"straddle": pc != po, "gap": _r(c - o), "gap_rel": _r(rel)})
		straddle = straddle or pc != po
		gap = maxf(gap, rel)
	var other := {}
	for k in closed:
		if not open_snap.has(k) or absf(float(closed[k]) - float(open_snap[k])) <= 1e-6:
			continue
		other[k] = [_r(float(closed[k])), _r(float(open_snap[k]))]
	return {"t": float(e["t"]), "op": str(e["op"]), "args": str(e.get("args", [])), "closed": "%s %s" % [str(e["ok"]), str(e["reason"])],
		"thresholds": rows, "straddle": straddle, "stock_gap": _r(gap), "differ": other}


## A fraction as a percent for the I1 report rows: 0.158 → "15.8%".
static func conv_pct(x: float) -> String:
	return "%.1f%%" % (100.0 * x)


## The I1 replay's bodies row (the step 4 review's item 7; a report row, not a gate): the gate samples the bodies at day
## ends only, against one convoy load, so a gap over the load between them is unseen there. This samples it at every
## replayed command, as the probe did: the closed run's bodies (logged before the leader's command) against the open
## run's (just before the replayed one), against the open run's one-load bound then. `row` accumulates {n, worst,
## worst_t, worst_bound, breaks, first_break: {t, gap, bound} or {}}.
static func bodies_gap_add(row: Dictionary, t: float, closed: float, open: float, bound: float) -> void:
	var g := absf(closed - open)
	row["n"] = int(row.get("n", 0)) + 1
	if g > float(row.get("worst", -1.0)):
		row["worst"] = _r(g)
		row["worst_t"] = _r(t)
		row["worst_bound"] = _r(bound)
	if g > bound:
		row["breaks"] = int(row.get("breaks", 0)) + 1
		if (row.get("first_break", {}) as Dictionary).is_empty():
			row["first_break"] = {"t": _r(t), "gap": _r(g), "bound": _r(bound), "closed": _r(closed), "open": _r(open)}


# ----------------------------------------------------------------------------------- the town's turn ---
## The bot's look at the town (between raids, at a session's start and every ACT_S while it waits): stances, the slab,
## the party and the foreman, the vats, the phylactery charge, then the queue.
func _act(queue_set := true) -> void:
	if s.view_catchup()["active"]:
		return
	var rel := s.view_relish()
	if int(rel["run_id"]) != -1:
		return
	if str(rel["state"]) == "at_fort" or str(rel["state"]) == "at_vei":
		_cmd("move", ["covington"])
	_stances()
	_war_topup()
	_craft_husk()
	_raise()
	_place()
	_vats()
	_craft()
	if queue_set:
		_fill()
		if reorder:
			_reorder()
	_observe()


func _stances() -> void:
	for st in s.view_stances()["stances"]:
		if str(st["id"]) in STANCES and not bool(st["on"]):
			_cmd("stance", [str(st["id"]), true])


## Ruling 3 (03:28; E4 step 5): in every look the bot sets the valve's WAR (WORK and FLOOD keeping their ratio) to the
## least WAR_STEP that covers every held fort WAR can save, floored at the new game's (economy.json opening.valve): what a
## player reading view_fort().hold does in a session. A fort's support scales with the valve's WAR (the bot never runs
## the Muster stance, so the settled WAR is mint × war), so it needs war × need / war_in. A fort with no WAR yet (war_in
## 0: no dispatch has reached it since its flip) waits for the next look. One needing more than WAR_MAX is let go: a
## player can't hold it with WAR, and every step costs growth. WAR comes back down as the need allows (the need grows as
## mint^α, the WAR as mint) or a fort falls, but only with two steps of slack, and then to a step above the need (to
## the floor when no fort needs more): a player doesn't trim WAR every minute. (Without that band the bot flipped 0.75
## ↔ 0.80 each look in continuous, 69 changes, the margin at the lower step dipping under 0 a minute later.) One
## command, then one more step while a covered fort still reads short. Each change goes in war_log.
func _war_topup() -> void:
	if not war_topup:
		return
	var tg: Dictionary = s.view_hud()["valve_target"]
	var v0 := float(tg["war"])
	var v_floor := float(s._cfgs["economy"]["opening"]["valve"]["war"])
	var want := v_floor
	var low := INF
	var cover: Array = []
	var gone: Array = []
	for f in s.view_realm()["forts"]:
		var h: Dictionary = f["hold"]
		if not bool(f["held"]) or float(h["war_in"]) <= 0.0:
			continue
		low = minf(low, float(h["margin"]))
		var v := v0 * float(h["need"]) / float(h["war_in"])
		if v > WAR_MAX + 1e-9:
			gone.append(str(f["id"]))
		else:
			want = maxf(want, v)
			cover.append(str(f["id"]))
	var war := minf(WAR_MAX, ceilf(want / WAR_STEP - 1e-6) * WAR_STEP)
	if war < v0 - 1e-6:
		if war > v0 - 2.0 * WAR_STEP + 1e-6:
			return
		if war > v_floor + 1e-6:
			war += WAR_STEP
	if absf(war - v0) < 1e-6:
		return
	var wf := maxf(1e-9, float(tg["work"]) + float(tg["flood"]))
	_cmd("valve", [float(tg["work"]) / wf * (1.0 - war), war, float(tg["flood"]) / wf * (1.0 - war)])
	if war < WAR_MAX - 1e-9 and _low_of(cover) < 0.0:
		war = minf(WAR_MAX, war + WAR_STEP)
		_cmd("valve", [float(tg["work"]) / wf * (1.0 - war), war, float(tg["flood"]) / wf * (1.0 - war)])
	war_log.append({"t": _r(s.t), "from": _r(v0), "to": _r(war), "low_before": _r(low), "low_after": _r(_low_of(cover)),
		"covered": cover, "let_go": gone})


## The lowest view_fort().hold.margin among `ids`, INF with none.
func _low_of(ids: Array) -> float:
	var low := INF
	for id in ids:
		low = minf(low, float(s.view_fort(str(id))["hold"]["margin"]))
	return low


## Raise: whenever a husk is held and the crypt has room, with every remnant that fits (SlabLogic.evaluate, read-only: a
## remnant it can't place would refuse the whole raise as invalid_recipe), the largest magnitude first (keep_fronts:
## _slab_fill's front-first fill). She must be home. Each raise is logged in `raised`.
func _raise() -> void:
	if str(s.view_relish()["state"]) != "home":
		return
	var slab: Dictionary = c["town"]["slab"]
	for _guard in 16:
		var bu := s.view_big_undead()
		if int(bu["count"]) >= int(bu["cap"]):
			return
		var inv := s.view_inventory()
		var done := false
		for h in inv["husks"]:
			var kind := str(h["kind"])
			var pick := _slab_fill(kind, inv["remnants"], slab)
			if pick.is_empty():
				continue
			var uids: Array = []
			for r in pick:
				uids.append(str(r["uid"]))
			var nm := str(SlabLogic.evaluate(kind, pick, slab)["name"]).substr(0, 24).strip_edges()
			var rr := _cmd("raise", [str(h["uid"]), uids, nm if nm != "" else "Raised"])
			if bool(rr["ok"]):
				var st: Dictionary = rr["big_undead"]["stats"]
				raised.append([_r(s.t / 3600.0), kind, float(st.get("wits", 0.0)), float(st.get("beef", 0.0))])
				done = true
				break
		if not done:
			return


static func _uid_n(uid: String) -> int:
	return int(uid.substr(1)) if uid.length() > 1 else 0


## Remnants tried in key order, each kept if SlabLogic can still place them all: the aspect `prefer` first (none: no
## preference), then the larger magnitude, then the older uid.
static func _fit_key(r: Dictionary, prefer: String) -> int:
	var first := 0 if prefer == "" or str(r["aspect"]) == prefer else 1
	return first * 10000000000000 + (1000 - int(r["magnitude"])) * 1000000000 + _uid_n(str(r["uid"]))


static func _fit(kind: String, remnants: Array, slab: Dictionary, prefer := "") -> Array:
	var cands := remnants.duplicate()
	cands.sort_custom(func(a, b): return _fit_key(a, prefer) < _fit_key(b, prefer))
	var pick: Array = []
	for r in cands:
		var trial := pick.duplicate()
		trial.append(r)
		if (SlabLogic.evaluate(kind, trial, slab)["unplaced"] as Array).is_empty():
			pick = trial
	return pick


## keep_fronts' fill (E4 step 2): of the magnitude fill and the fills with the stat of giants or carvers first, the one
## that brings the larger share of that front's want (_big_want; ties to the earlier, giants before carvers). A front
## whose want is met without bigs is not tried. Off: the magnitude fill.
func _slab_fill(kind: String, remnants: Array, slab: Dictionary) -> Array:
	var pick := _fit(kind, remnants, slab)
	if not keep_fronts:
		return pick
	var want := _big_want()
	var best := 0.0
	for fid in BANK_FRONTS:
		var w := float(want.get(fid, 0.0))
		if w <= 0.0:
			continue
		var st := str(c["vei"]["fronts"][fid]["stat"])
		var trial := _fit(kind, remnants, slab, st)
		if trial.is_empty():
			continue
		var sc := float(SlabLogic.evaluate(kind, trial, slab)["stats"].get(st, 0.0)) / w
		if sc > best:
			best = sc
			pick = trial
	return pick


## What the bigs must bring to each front: its need at Vei's full pool (need_base + need_per_pool x pool_cap) less its
## backlog and q terms now (VeiFronts.have_need's have, without the stat sum), from view_vei and the vei config. The
## full pool's need, not today's (E4 step 3): her pool dips through every tithe wave, and a want read in the dip let one
## keeper meet it alone, so the second was released, raided and was lost (sessions lost a keeper so at 168.09 h and
## 168.17 h). A dip lasts the wave's surge (realm.json tithe.surge_s, 40 s) and the refill after it (11–24 s), and
## between waves she sits at her cap, the state the player sees most. The fight is judged at the pool she has then.
func _big_want() -> Dictionary:
	var v := s.view_vei()
	var cap := float(v["pool_cap"])
	var out := {}
	for fr in v["fronts"]:
		var fid := str(fr["id"])
		var fc: Dictionary = c["vei"]["fronts"][fid]
		out[fid] = _full_need(fid, cap) - float(fc["per_backlog"]) * float(v["backlog"]) \
			- float(fc["per_q"]) * float(v["digest_q"])
	return out


## A front's need at Vei's full pool `cap`: need_base + need_per_pool x cap (VeiFronts.have_need's need at living_pool
## = cap). _big_want and the Vei-ready readout (_full_met) both read it.
func _full_need(fid: String, cap: float) -> float:
	var fc: Dictionary = c["vei"]["fronts"][fid]
	return float(fc["need_base"]) + float(fc["need_per_pool"]) * cap


## How many of view_vei `v`'s fronts are met at her full pool: each front's have (which doesn't read the pool) against
## _full_need at v's pool_cap. The bot's Vei-ready reads this (the sizing stop's ruling R2), so the pacing number doesn't
## hang on where in a tithe wave the look falls; the fight still judges the fronts at the pool she has then.
func _full_met(v: Dictionary) -> int:
	var n := 0
	for fr in v["fronts"]:
		if float(fr["have"]) >= _full_need(str(fr["id"]), float(v["pool_cap"])):
			n += 1
	return n


## keep_fronts' keepers (E4 step 2; two fronts from the sizing stop's ruling, IDLE §8): the bigs that stay home on giants
## and carvers while the rest raid. On each of the two whose want (_big_want) is positive, the candidates are the bigs
## whose stat there brings at least KEEP_SHARE of the want, best first (ties to the older uid). The front whose candidates
## alone cover the larger share of its want (ties to giants) takes its keepers first, as many as meet its want; the other
## then takes its own from the bigs left, as many as meet its want. At most cap - RAID_ROOM in all, and a big keeps one
## front. The other order is taken instead when it meets more fronts, or as many and keeps more of today's keepers
## (_kept_of), or as many of both with more coverage (_alloc's cov): a front of weak bigs that fills every place first
## would leave a front it could have met unkept, and a keeper meeting a front isn't sent to raid for a sliver of cover
## elsewhere (sessions at 96 h: two new beef-3 skeletons took giants' wits 5 and 4 places, 1.43 against 1.41).
## {uids: the keepers in that order, front_of: {uid: front}}; {} when no big qualifies.
func _keepers() -> Dictionary:
	if not keep_fronts:
		return {}
	var bu := s.view_big_undead()
	var k := int(bu["cap"]) - RAID_ROOM
	if k <= 0:
		return {}
	var want := _big_want()
	var order: Array = []  # [the share its candidates cover alone, front, candidates, want]
	for fid in BANK_FRONTS:
		var w := float(want.get(fid, 0.0))
		if w <= 0.0:
			continue
		var fc: Dictionary = c["vei"]["fronts"][fid]
		var rows: Array = []
		for b in bu["big_undead"]:
			var x := float(fc["per_stat"]) * float(b["stats"].get(str(fc["stat"]), 0.0))
			if x >= KEEP_SHARE * w:
				rows.append([x, str(b["uid"])])
		if rows.is_empty():
			continue
		rows.sort_custom(func(r1, r2): return float(r1[0]) > float(r2[0]) or (float(r1[0]) == float(r2[0]) and _uid_n(str(r1[1])) < _uid_n(str(r2[1]))))
		var sum := 0.0
		for r in rows.slice(0, k):
			sum += float(r[0])
			if sum >= w:
				break
		order.append([sum / w, fid, rows, w])
	order.sort_custom(func(o1, o2): return float(o1[0]) > float(o2[0]) or (float(o1[0]) == float(o2[0]) and str(o1[1]) == "giants"))
	var best := _alloc(order, k)
	if order.size() == 2:  # the other order, when it meets more fronts, or as many and keeps more of today's keepers, or covers more
		var alt := _alloc([order[1], order[0]], k)
		var ka := _kept_of(alt["uids"])
		var kb := _kept_of(best["uids"])
		if int(alt["met"]) > int(best["met"]) or (int(alt["met"]) == int(best["met"]) and (ka > kb
				or (ka == kb and float(alt["cov"]) > float(best["cov"]) + 1e-9))):
			var by := "met" if int(alt["met"]) > int(best["met"]) else ("kept" if ka > kb else "cov")
			keep_churn["alt_by"][by] = int(keep_churn["alt_by"][by]) + 1
			best = alt
	return {} if (best["uids"] as Array).is_empty() else {"uids": best["uids"], "front_of": best["front_of"]}


## keep_churn's tally for one look: `was` the last look's keepers, `held` the bigs held now (uids).
func _count_churn(was: Array, held: Array) -> void:
	keep_churn["looks"] = int(keep_churn["looks"]) + 1
	var same := was.size() == _keep.size() and was.all(func(u): return _keep.has(u))
	if not same:
		keep_churn["changes"] = int(keep_churn["changes"]) + 1
	for u in was:
		if not _keep.has(u) and held.has(u):
			keep_churn["drops_held"] = int(keep_churn["drops_held"]) + 1
			_dropped[u] = true
	for u in _keep:
		if _dropped.has(u):
			keep_churn["flip_backs"] = int(keep_churn["flip_backs"]) + 1
			_dropped.erase(u)


## How many of `uids` are keepers now (_keep, the last look's).
func _kept_of(uids: Array) -> int:
	var n := 0
	for u in uids:
		n += 1 if _keep.has(u) else 0
	return n


## _keepers' fill in one front order: each front in turn takes its candidates not yet kept, best first, until its want is
## met, at most k in all. {uids, front_of, met: the fronts whose want it meets, cov: the sum of each front's share, at
## most 1}.
static func _alloc(order: Array, k: int) -> Dictionary:
	var uids: Array = []
	var front_of := {}
	var met := 0
	var cov := 0.0
	for o in order:
		var sum := 0.0
		for r in o[2]:
			if uids.size() >= k or sum >= float(o[3]):
				break
			var u := str(r[1])
			if front_of.has(u):
				continue
			uids.append(u)
			front_of[u] = str(o[1])
			sum += float(r[0])
		met += 1 if sum >= float(o[3]) else 0
		cov += minf(1.0, sum / float(o[3]))
	return {"uids": uids, "front_of": front_of, "met": met, "cov": cov}


## Placement: the party fills first (the oldest bigs, up to PARTY_MAX), each assigned the front of its best stat; the
## first spare big goes foreman at the Market, or at the Bone Mill while bone binds (the queue's head waits on bone);
## later spares stay in the crypt. Sieges only in away_risk's prepared setup.
## bank_bigs (E3-7, the manager's ruling 4 at the E3-6b stop): once the giants or carvers front is short (_bank_now), the
## party holds the bigs on giants and carvers between raids (_bank_fronts: only a party member has a front), and _raid
## empties it before each raid, so no raid takes a big (_reach: t1 only; the held door off). This look puts them back.
## keep_fronts (E4 step 2): the keepers (_keepers) join the party first, on their front, and the party fills from the
## other bigs as above; _raid leaves the keepers home (_reach counts the raiders only). No keeper: the E3 placement.
func _place() -> void:
	var uids: Array = []
	for b in s.view_big_undead()["big_undead"]:
		uids.append(str(b["uid"]))
	var keep := _keepers()
	var was: Array = _keep
	_keep = (keep.get("uids", []) as Array).duplicate()
	_count_churn(was, uids)
	var rest: Array = []
	for u in uids:
		if not _keep.has(u):
			rest.append(u)
	var want: Array = _keep + rest.slice(0, PARTY_MAX)
	var have: Array = []
	for p in s.view_party()["party"]:
		have.append(str(p["uid"]))
	if have != want:
		_cmd("party", [want])
	if bank_bigs and _bank_now():
		_bank_fronts()
	else:
		for b in s.view_big_undead()["big_undead"]:
			if str(b["place"]) == "party":
				var f := str(keep["front_of"][str(b["uid"])]) if _keep.has(str(b["uid"])) else _best_front(b["stats"])
				if str(b["front"]) != f:
					_cmd("front", [str(b["uid"]), f])
	if rest.size() > PARTY_MAX:
		var spare := str(rest[PARTY_MAX])
		var lot := _foreman_lot(s.view_town())
		var cur := ""
		for b in s.view_big_undead()["big_undead"]:
			if str(b["uid"]) == spare:
				cur = str(b["place"])
		if lot != "" and cur != "town:" + lot:
			_cmd("place", [spare, "town:" + lot])


## bank_bigs' latch: true from the first look that reads giants or carvers short (have < need) to the run's end.
func _bank_now() -> bool:
	if not _banking:
		for fr in s.view_vei()["fronts"]:
			if str(fr["id"]) in BANK_FRONTS and float(fr["have"]) < float(fr["need"]):
				_banking = true
	return _banking


## bank_bigs' fronts: a party member already on giants or carvers stays there; any other goes to the one of the two
## still short where its stat is higher (both short or neither: the higher stat; ties to giants).
func _bank_fronts() -> void:
	for b in s.view_big_undead()["big_undead"]:
		if str(b["place"]) != "party" or str(b["front"]) in BANK_FRONTS:
			continue
		var short := {}
		for fr in s.view_vei()["fronts"]:
			short[str(fr["id"])] = float(fr["have"]) < float(fr["need"])
		var best := ""
		var bv := -INF
		var any_short := bool(short.get("giants", false)) or bool(short.get("carvers", false))
		for fid in BANK_FRONTS:
			if any_short and not bool(short.get(fid, false)):
				continue
			var v := float(b["stats"].get(str(c["vei"]["fronts"][fid]["stat"]), 0.0))
			if v > bv:
				bv = v
				best = fid
		if best != "":
			_cmd("front", [str(b["uid"]), best])


func _best_front(stats: Dictionary) -> String:
	var best := ""
	var bv := -INF
	for fid in GameState.FRONT_IDS:
		var v := float(stats.get(str(c["vei"]["fronts"][fid]["stat"]), 0.0))
		if v > bv:
			bv = v
			best = fid
	return best


func _foreman_lot(tn: Dictionary) -> String:
	var market := ""
	var mill := ""
	for b in tn["buildings"]:
		if int(b["level"]) < 1:
			continue
		if str(b["building_id"]) == "market" and market == "":
			market = str(b["lot_id"])
		elif str(b["building_id"]) == "bone_mill" and mill == "":
			mill = str(b["lot_id"])
	var q: Array = tn["queue"]
	var h := _funds_head(q)
	var bone_binds := h >= 0 and str(q[h]["reason"]) == "no_bone"
	return mill if bone_binds and mill != "" else market


## Vats: staffed as soon as a Chapel of Vats exists ("best case").
func _vats() -> void:
	for v in s.view_backups()["vats"]:
		if not bool(v["staffed"]):
			_cmd("vat", [int(v["slot"]), true])


## Crafting: one phylactery charge whenever the catalog says it can be crafted and none is held; no simulacra.
func _craft() -> void:
	if int(s.view_inventory()["phylactery_charges"]) > 0:
		return
	for cr in s.view_catalog()["crafts"]:
		if str(cr["item_id"]) == "phylactery_charge" and bool(cr["can_craft"]):
			_cmd("craft", ["phylactery_charge"])


## The husk craft (E4 step 2's sizing stop, the manager's ruling 2: lever (b); every profile): one t1 husk from the
## weakest remnants and bone (cmd_craft_husk) whenever _husk_kind finds one worth making. Each is logged in `crafted`.
func _craft_husk() -> void:
	var kind := _husk_kind(false)
	if kind != "" and bool(_cmd("craft_husk", [kind])["ok"]):
		crafted.append([_r(s.t / 3600.0), kind])


## The husk the bot would craft now, "" for none. It reads the player's source, view_catalog().husk_craft (the E4 review:
## its kinds, its price and the reason the craft would answer), never the raw configs. It crafts when the craft would
## go (reason ""; `ignore_room` also takes at_cap, the crypt full, for _fill's crypt trigger), giants or carvers is
## short (_short_fronts), a remnant would be left for the raise, and the bone left after the price still covers the
## queue head's bone (the E4 review: a craft mustn't make the head wait on bone, nor delay one that already does). The kind
## (husk_craft.kinds) is the one whose slab fill (_slab_fill, on the remnants the craft leaves:
## GameState.husk_craft_pick) brings the larger share of a short front's want, in list order on a tie; none is made
## unless that share is at least KEEP_SHARE, so the body would be a keeper candidate there (a body too weak to keep isn't
## worth the remnants: continuous at e299d87 ground its thin remnants into wits-2 skeletons and its giants front sat at
## 9/14 from day 3).
func _husk_kind(ignore_room: bool) -> String:
	var hc: Dictionary = s.view_catalog()["husk_craft"]
	var why := str(hc["reason"])
	if why != "" and not (ignore_room and why == "at_cap"):
		return ""
	var n := int(hc["cost"]["remnants"])
	var inv := s.view_inventory()
	var rems: Array = inv["remnants"]
	if rems.size() <= n:
		return ""
	var bu := s.view_big_undead()
	var tn := s.view_town()
	var q: Array = tn["queue"]
	var h := _head(q, true)
	if h >= 0 and float(tn["bone"]) - float(hc["cost"]["bone"]) < float(q[h]["cost"]["bone"]):
		return ""
	var short := _short_fronts(bu)
	if short.is_empty():
		return ""
	var picked := {}
	for r in GameState.husk_craft_pick(rems, n):
		picked[str(r["uid"])] = true
	var rest: Array = rems.filter(func(r): return not picked.has(str(r["uid"])))
	var slab: Dictionary = c["town"]["slab"]
	var best := ""
	var best_sc := 0.0
	for kind in hc["kinds"]:
		var st: Dictionary = SlabLogic.evaluate(str(kind), _slab_fill(str(kind), rest, slab), slab)["stats"]
		for fid in short:
			var fc: Dictionary = c["vei"]["fronts"][fid]
			var sc := float(fc["per_stat"]) * float(st.get(str(fc["stat"]), 0.0)) / float(short[fid])
			if sc > best_sc:
				best_sc = sc
				best = str(kind)
	return best if best_sc >= KEEP_SHARE else ""


## Giants and carvers where the bigs on the front (front == it) bring less than its want (_big_want, at Vei's full pool):
## {front: want}.
func _short_fronts(bu: Dictionary) -> Dictionary:
	var want := _big_want()
	var out := {}
	for fid in BANK_FRONTS:
		var w := float(want.get(fid, 0.0))
		if w <= 0.0:
			continue
		var fc: Dictionary = c["vei"]["fronts"][fid]
		var have := 0.0
		for b in bu["big_undead"]:
			if str(b["front"]) == fid:
				have += float(fc["per_stat"]) * float(b["stats"].get(str(fc["stat"]), 0.0))
		if have < w:
			out[fid] = w
	return out


static func _list(cfg: Dictionary) -> Array:
	if not _list_cache.is_empty():
		return _list_cache
	var out: Array = BUILD_LIST.duplicate(true)
	var seen := {}
	for it in out:
		seen["%s/%s/%d" % [it[0], it[1], it[2]]] = true
	for lv in range(2, 9):
		for e in LADDER:
			var key := "%s/%s/%d" % [e[0], e[1], lv]
			if lv <= int(cfg["buildings"][e[0]]["max_level"]) and not seen.has(key):
				seen[key] = true
				out.append([e[0], e[1], lv])
	_list_cache = out
	return out


## The queue: kept filled from the priority list. An item is queued once the level below it on its lot is built,
## building or queued; a refusal (cost_exceeds_cap, mostly) leaves it for a later look. From the first look that keeps a
## big (_keep), or finds the crypt full (big undead at the cap) while a husk waits or the bot would craft one but for the
## room (_husk_kind), the crypt's levels (CRYPT_LEVELS) head the list: a keeper takes a place a raider would use, a husk
## that can't be raised is a big lost, and a level is a place (big_undead.per_crypt_level).
## Phase I P2 (the run's manager's ruling 2 of 2026-11-17 22:40, test hygiene): the fill skips gated entries. Before
## each command it reads the walk with the item appended (BuildRules.queue_walk, statuses only: no command, nothing
## logged), and an item that would be skipped_gate is passed over this look, with two exceptions: an upgrade waiting on its own lot's construction (under_construction: it starts when that
## ends; the shipped fill queued these, and they still count toward the fill's queue_max as they did, so its mix of
## builds is unchanged), and one no_relics entry while the queue holds no other (park_relics: the build a player
## parks behind the relics, so the wall's chip shows, IDLE §7; it counts toward nothing). Within the list's cap
## (queue_list_max). Before P2 every entry counted, so a fill of gated entries jammed the queue (town_only at 8.0 h).
func _fill() -> void:
	if not _crypt_up:
		var bu := s.view_big_undead()
		_crypt_up = not _keep.is_empty() or (int(bu["count"]) >= int(bu["cap"])
			and (not (s.view_inventory()["husks"] as Array).is_empty() or _husk_kind(true) != ""))
		if _crypt_up:
			crypt_up_t = s.t
	var tn := s.view_town()
	var q: Array = tn["queue"]
	var qmax := int(tn["queue_max"])
	var plan := {}
	for b in tn["buildings"]:
		plan[str(b["lot_id"])] = [str(b["building_id"]), int(b["level"]) + (1 if str(b["state"]) == "constructing" else 0)]
	for e in q:
		var cur: Array = plan.get(str(e["lot_id"]), ["", 0])
		plan[str(e["lot_id"])] = [str(e["building_id"]), maxi(int(cur[1]), int(e["level"]))]
	# the fill's own count: what the shipped fill counted, less the gated entries it now skips (an upgrade on its lot's
	# construction still counts, so the fill's mix of builds is the shipped one's)
	var n := 0
	var m := q.size()
	var list_max := int(tn["queue_list_max"])
	var parked := false
	for e in q:
		var gated := str(e["status"]) == "skipped_gate" and str(e["reason"]) != "under_construction"
		n += 0 if gated else 1
		parked = parked or (gated and str(e["reason"]) == "no_relics")
	var walk: Array = CRYPT_LEVELS + _list(c) if _crypt_up else _list(c)
	for it in walk:
		if n >= qmax or m >= list_max:
			break
		var lot: String = it[1]
		var lv: int = it[2]
		var cur: Array = plan.get(lot, ["", 0])
		if (str(cur[0]) != "" and str(cur[0]) != str(it[0])) or int(cur[1]) != lv - 1:
			continue
		# the walk with the item appended, read only (the statuses of the entries ahead don't change): the status it would
		# take, so a gated item is passed over without a command
		var row: Dictionary = BuildRules.queue_walk(s, s.build_queue + [{"building_id": str(it[0]), "lot_id": lot,
			"upgrade": lv > 1, "waited_on": ""}], false)["rows"].back()
		var counts := str(row["status"]) != "skipped_gate" or str(row["reason"]) == "under_construction"
		var park := not counts and park_relics and str(row["reason"]) == "no_relics" and not parked
		if not (counts or park):
			continue
		if not bool(_cmd("queue", [str(it[0]) if lv == 1 else "", lot])["ok"]):
			continue
		m += 1
		n += 1 if counts else 0
		parked = parked or park
		plan[lot] = [str(it[0]), lv]
	if park_gated:
		_park(walk, plan, list_max - m)


## Phase I P3, ruling 2 (the parking fill): after the skip fill, up to `room` (the list's spare places, queue_list_max)
## of `walk`'s next items whose walk row, read with the item appended (no command), is skipped_gate on one of
## PARK_GATES: each starts when its tier rises, its relics come or its lot opens, as a real player queues what they
## want. Gated entries hold no slot (A14), so this never keeps a relic-free build out, and the slot rule (A14's
## amendment) keeps the active queue at queue.max_len however many park. `plan` is _fill's lot plan (updated).
## The queue-hours probe's QH_PARK=1 bot (Phase I P2, wip/tools-p2/qh_bot.gd), made the default.
func _park(walk: Array, plan: Dictionary, room: int) -> void:
	for it in walk:
		if room <= 0:
			return
		var lot: String = it[1]
		var lv: int = it[2]
		var cur: Array = plan.get(lot, ["", 0])
		if (str(cur[0]) != "" and str(cur[0]) != str(it[0])) or int(cur[1]) != lv - 1:
			continue
		var row: Dictionary = BuildRules.queue_walk(s, s.build_queue + [{"building_id": str(it[0]), "lot_id": lot,
			"upgrade": lv > 1, "waited_on": ""}], false)["rows"].back()
		if not (str(row["status"]) == "skipped_gate" and PARK_GATES.has(str(row["reason"]))):
			continue
		if bool(_cmd("queue", [str(it[0]) if lv == 1 else "", lot])["ok"]):
			plan[lot] = [str(it[0]), lv]
			room -= 1


## The first entry that isn't skipped_gate (the one the queue saves toward), or -1. `never`: a never row (Phase I P3,
## ruling 3: skipped because no income can pay it) counts too, for the bot's own savings (the craft keeps its bone).
static func _head(q: Array, never := false) -> int:
	for i in q.size():
		if str(q[i]["status"]) != "skipped_gate" or (never and BuildRules.never_row(q[i])):
			return i
	return -1


## The first entry short of funds: a head waiting on them, or one skipped because no income can pay it (Phase I P3,
## ruling 3: BuildRules.never_row, which the queue passes over but a player still reads as the store that binds), or -1.
static func _funds_head(q: Array) -> int:
	for i in q.size():
		if str(q[i]["status"]) == "waiting_funds" or BuildRules.never_row(q[i]):
			return i
	return -1


## The reorder rule: when the head's affordable_in_s is -1, or later than another entry's, the soonest-affordable entry
## (ties in queue order; gated entries hold nothing and are left where they are) moves to the head.
func _reorder() -> void:
	for _guard in 8:
		var q: Array = s.view_town()["queue"]
		var h := -1
		var best := -1
		for i in q.size():
			if str(q[i]["status"]) == "skipped_gate":
				continue
			if h < 0:
				h = i
			var a := float(q[i]["affordable_in_s"])
			if a >= 0.0 and (best < 0 or a < float(q[best]["affordable_in_s"])):
				best = i
		if h < 0 or best < 0 or best == h:
			return
		var ah := float(q[h]["affordable_in_s"])
		if ah >= 0.0 and float(q[best]["affordable_in_s"]) >= ah:
			return
		var order: Array = [best]
		for i in q.size():
			if i != best:
				order.append(i)
		if not bool(_cmd("reorder", [order])["ok"]):
			return


## What a look sees and the summary needs: the first ready clone (observed), the first head waiting on bone, a head the
## current income never affords while its store's producer stands (the "build a Market / Bone Mill" case), the relics
## wall read off the queue.
func _observe() -> void:
	if int(s.view_backups()["clones_ready"]) >= 1 and first["clone"] < 0.0:
		first["clone"] = s.t
	var tn := s.view_town()
	var q: Array = tn["queue"]
	var h := _funds_head(q)
	if h >= 0:
		var why := str(q[h]["reason"])
		if why == "no_bone" and first["bone_wait_seen"] < 0.0:
			first["bone_wait_seen"] = s.t
		if float(q[h]["affordable_in_s"]) < 0.0:
			var producer := "market" if why == "no_gold" else "bone_mill"
			if _stands(tn, producer):
				var key := "%s/%s/%d/%s" % [q[h]["building_id"], q[h]["lot_id"], int(q[h]["level"]), why]
				if input_limited.is_empty() or str(input_limited[-1].get("key", "")) != key:
					input_limited.append({"t": s.t, "where": "queue", "key": key, "store": why.trim_prefix("no_"),
						"standing": producer})
	if _queue_wall(q) and first["wall_queue"] < 0.0:
		first["wall_queue"] = s.t


static func _stands(tn: Dictionary, building_id: String) -> bool:
	for b in tn["buildings"]:
		if str(b["building_id"]) == building_id and int(b["level"]) >= 1:
			return true
	return false


## W2's relics wall read off the queue (IDLE §7): no entry can start (no `next`, no waiting head that will be afforded)
## and at least one is skipped on no_relics.
static func _queue_wall(q: Array) -> bool:
	if q.is_empty():
		return false
	var relic := false
	for e in q:
		var st := str(e["status"])
		if st == "next" or (st == "waiting_funds" and float(e["affordable_in_s"]) >= 0.0):
			return false
		relic = relic or (st == "skipped_gate" and str(e["reason"]) == "no_relics")
	return relic


static func _next_afford(q: Array) -> float:
	var best := -1.0
	for e in q:
		if str(e["status"]) == "skipped_gate":
			continue
		var a := float(e["affordable_in_s"])
		if a >= 0.0 and (best < 0.0 or a < best):
			best = a
	return best


# ------------------------------------------------------------------------------------------------ raids ---
## The raid target: the highest tier the party reaches (tier T needs at least raid.json autopilot.party_profiles[T]'s
## bigs in the party: the party the stand-ins were measured with, since the sim itself gates no tier), the first dungeon
## while it is flagged, then the higher yield, an unheld fort before a held one, world order. A held fort only once its
## yield_mult is back to HELD_RAID_YIELD (never, under ablation a). static: the day's tier instead. {} for none.
func _pick() -> Dictionary:
	var realm := s.view_realm()
	var reach := _reach()
	var day_tier := mini(4, 1 + int(floorf(s.t / DAY / 2.0)))
	var best := {}
	var bk: Array = []
	for f in realm["forts"]:
		var tier := int(f["tier"])
		var held := bool(f["held"])
		var y := float(f["yield_mult"])
		if static_raids:
			if tier != day_tier:
				continue
		elif tier > reach:
			continue
		if held and (no_held or y < HELD_RAID_YIELD - 1e-9):
			continue
		var k := [1 if bool(f["first_dungeon"]) else 0, tier, y, 0 if held else 1]
		if best.is_empty() or _gt(k, bk):
			best = f
			bk = k
	if not best.is_empty():
		best["cov"] = realm["covington"]["pos"]
	return best


static func _gt(a: Array, b: Array) -> bool:
	for i in a.size():
		if float(a[i]) > float(b[i]):
			return true
		if float(a[i]) < float(b[i]):
			return false
	return false


func _reach() -> int:
	if _banking:
		return 1  # bank_bigs: the party is emptied before every raid
	var n := 0
	for p in s.view_party()["party"]:
		if not _keep.has(str(p["uid"])):
			n += 1  # keep_fronts: the keepers stay home, so only the raiders count
	var profs: Dictionary = c["raid"]["autopilot"]["party_profiles"]
	var reach := 1
	for tier in [2, 3, 4]:
		if n >= (profs[str(tier)]["party"] as Array).size():
			reach = tier
	return reach


## The longest a raid there can take (the stand-in entries it can resolve on, a death's death_t_frac above 1 included),
## plus the walk there and back: a session starts a raid only if this fits.
func _est(f: Dictionary) -> float:
	var cp: Array = f["cov"]
	var fp: Array = f["pos"]
	var d := Vector2(float(cp[0]), float(cp[1])).distance_to(Vector2(float(fp[0]), float(fp[1])))
	return 2.0 * d / float(c["realm"]["relish"]["travel_speed"]) + _dur_max(f) + 4.0 * FRAME_DT


func _dur_max(f: Dictionary) -> float:
	var tier := clampi(int(f["tier"]), 1, 4)
	var names: Array = [str(tier)]
	if not bool(f["held"]):
		if bool(f["first_dungeon"]):
			names = ["first_dungeon"]
		else:
			for x in c["raid"]["held_door"]["tiers"]:
				if int(x) == tier:
					names.append("held_door")
	var best := 0.0
	for nm in names:
		var e: Dictionary = sb[nm]
		best = maxf(best, float(e["duration_s"]) * maxf(1.0, float(e["death_t_frac"])))
	if bool(f["held"]):
		best *= float(sb["held"]["duration_mult"])
	return best


func _at(fid: String) -> bool:
	var rel := s.view_relish()
	return str(rel["state"]) == "at_fort" and str(rel["at"]) == fid


func _resolve(seed: Dictionary, held: bool) -> Dictionary:
	# bank_bigs sends no big through the held door either, once it banks
	return StandinResolver.resolve(seed, sb, c, {"deaths": deaths, "door": not _banking, "held": held,
		"blueprints": s.view_inventory()["blueprints"]})


func _raid(fid: String, limit: float) -> Dictionary:
	if _banking and not (s.view_party()["party"] as Array).is_empty():
		_cmd("party", [[]])  # bank_bigs: no raid takes a big (their fronts go with them; the next look restores both)
	elif not _keep.is_empty():
		var go: Array = []
		var pty: Array = s.view_party()["party"]
		for p in pty:
			if not _keep.has(str(p["uid"])):
				go.append(str(p["uid"]))
		if go.size() != pty.size():
			_cmd("party", [go])  # keep_fronts: the keepers stay home (as above, the next look restores them)
	if not bool(_cmd("move", [fid])["ok"]):
		return {}
	if not _tick_until(func(): return _at(fid), s.t + 600.0):
		notes.append("t %.1f: Relish never arrived at %s" % [s.t, fid])
		return {}
	var f := s.view_fort(fid)
	var held := bool(f["held"])
	var b := _cmd("begin", [fid], {"held": held})
	if not bool(b["ok"]):
		return {}
	_begin_note(fid, f, held)
	var t0 := s.t
	var o := _resolve(b["seed"], held)
	_tick_to(t0 + float(o["duration_s"]))
	_apply(o, {"died": bool(o["died"]), "duration_s": float(o["duration_s"]), "table": str(o["notes"]["table"])})
	if bool(o["died"]):
		_tick_until(func(): return str(s.view_relish()["state"]) != "dead", limit)
	else:
		_cmd("move", ["covington"])
		_tick_until(func(): return str(s.view_relish()["state"]) == "home", s.t + 600.0)
	return o


func _apply(o: Dictionary, extra: Dictionary) -> void:
	var errs := Results.validate("raid", o["result"])
	results["validated"] = int(results["validated"]) + 1
	if not errs.is_empty():
		results["invalid"] = int(results["invalid"]) + 1
		(results["errors"] as Array).append("t %.1f: %s" % [s.t, ", ".join(PackedStringArray(errs))])
	var a := _cmd("apply", [o["result"]], extra)
	if bool(a["ok"]):
		results["applied"] = int(results["applied"]) + 1
	else:
		results["refused"] = int(results["refused"]) + 1
		(results["errors"] as Array).append("t %.1f: apply_result refused %s %s" % [s.t, str(a["reason"]), str(a.get("errors", []))])
		_cmd("abort", [])
	var r: Dictionary = raids[-1] if not raids.is_empty() else {}
	r["died"] = bool(o["died"])
	r["duration_s"] = float(o["duration_s"])
	r["table"] = str(o["notes"]["table"])
	r["revived"] = int(o["notes"]["revived"])
	r["door"] = bool(o["notes"]["door_taken"])
	r["exit"] = "relish_died" if bool(o["result"]["relish_died"]) else ("warden_beaten" if bool(o["result"]["warden_beaten"]) else "retreated")
	r["party_lost"] = (o["result"]["party_lost"] as Array).size()
	r["applied"] = bool(a["ok"])


func _begin_note(fid: String, f: Dictionary, held: bool) -> void:
	var tier := int(f["tier"])
	raids.append({"t": s.t, "fort": fid, "tier": tier, "held": held, "yield": float(f["yield_mult"]),
		"party": (s.view_party()["party"] as Array).size()})
	var key := "t%d" % tier
	if (tier == 2 or tier == 3) and not first_raid.has(key):
		var bk := s.view_backups()
		first_raid[key] = {"t": s.t, "fort": fid, "held": held, "big": _big_counts(s.view_big_undead()),
			"phylactery_charge": int(bk["phylactery_charges"]) > 0, "clone_ready": int(bk["clones_ready"]) > 0,
			"since_first_vat_s": s.t - float(first["vat"]) if first["vat"] >= 0.0 else -1.0,
			"chapel_to_first_clone_s": float(first["clone"]) - float(first["chapel"]) if first["clone"] >= 0.0 and first["chapel"] >= 0.0 else -1.0,
			"label": "big undead held and placed lean on the GUESS stand-ins: the masses raised are an upper bound, and a won raid loses each party member at t2 0.712, t3 0.48, t4 0.41 (BALANCE §8); vats best case"}


## Vei-ready (BALANCE §1, IDLE §8): odds >= VEI_READY_ODDS and fronts_required fronts met at her full pool (_full_met;
## the sizing stop's ruling R2), at the look and again on arrival at her node. vei_ready_wave_t is the readout before
## R2 (the fronts at the pool she has then), recorded at the look only, so it never moves Relish: today's need is never
## over the full pool's, so it falls at or before vei_ready_t, inside a tithe wave's dip or between waves.
func _vei_check(end_t: float) -> void:
	if vei_ready_t >= 0.0:
		return
	var v := s.view_vei()
	if float(v["readiness"]) < VEI_READY_ODDS or str(s.view_relish()["state"]) != "home":
		return
	if vei_ready_wave_t < 0.0 and int(v["fronts_met"]) >= int(v["fronts_required"]):
		vei_ready_wave_t = s.t
	if _full_met(v) < int(v["fronts_required"]):
		return
	if not bool(_cmd("move", ["vei"])["ok"]):
		return
	_tick_until(func(): return str(s.view_relish()["state"]) == "at_vei", end_t)
	var v2 := s.view_vei()
	if bool(v2["can_begin"]) and _full_met(v2) >= int(v2["fronts_required"]) and float(v2["readiness"]) >= VEI_READY_ODDS:
		vei_ready_t = s.t
	_cmd("move", ["covington"])
	_tick_until(func(): return str(s.view_relish()["state"]) == "home", end_t + 600.0)


# --------------------------------------------------------------------------------------------- sessions ---
## One session to `end_t`: the town's turn, then raids while one fits (as many as `max_raids`, -1 for no limit), the
## town's turn after each, and a look every ACT_S while it waits. Rows `k0` at its start and `k1` at its end ("" none).
func _session(end_t: float, max_raids: int, raid_on: bool, k0: String, k1: String) -> void:
	if k0 != "":
		_row(k0)
	_act()
	_vei_check(end_t)
	var n := 0
	while s.t < end_t - 1e-9:
		if stop_at_vei and vei_ready_t >= 0.0:
			break
		var f := {}
		if raid_on and (max_raids < 0 or n < max_raids) and str(s.view_relish()["state"]) == "home":
			f = _pick()
			if not f.is_empty() and s.t + _est(f) > end_t:
				f = {}
		if not f.is_empty():
			_raid(str(f["id"]), end_t)
			n += 1
			_act()
			_vei_check(end_t)
		else:
			_tick_to(minf(end_t, s.t + ACT_S))
			_act()
	if k1 != "":
		_row(k1)


## Three sessions a day for `days`, closed between them; the last night is closed too (so day `days` ends at its load)
## unless `final_close` is false (away_risk takes the state at the last session's end).
func play_sessions(days: int, max_raids := -1, raid_on := true, final_close := true) -> void:
	for d in days:
		for k in 3:
			var start := float(d * DAY + int(SESSION_OFFSETS[k]))
			_tick_to(start)
			_session(start + SESSION_S, max_raids, raid_on, "session_start", "session_end")
			if d == days - 1 and k == 2 and not final_close:
				return
			var nxt := float(d * DAY + int(SESSION_OFFSETS[k + 1])) if k < 2 else float((d + 1) * DAY)
			close(int(nxt - ceilf(s.t)), k == 2)
			if k == 2:
				_day_end()


## Open and acting all the time: raids back to back, the queue always fed, a `day_end` row at each boundary, until
## Vei-ready or `days`.
func play_continuous(days: int) -> void:
	open_rows = true
	live_days = true
	stop_at_vei = true
	_next_open_row = OPEN_ROW_S
	_next_day = float(DAY)
	_session(float(days * DAY), -1, true, "start", "")
	_row("end")


## One 20 min setup (the queue filled and reordered, the stances set, the valve at its default; no raids), then closed for
## `days` (at most idle.catchup_max_s: 7 days is exactly it). The timeline is the catch-up's own events.
func play_pure_idle(days: int) -> void:
	_session(float(SESSION_S), 0, false, "setup_start", "setup_end")
	close(days * DAY)
	_row("end")


## GAMEPLAY §6's opening, scripted: the first dungeon (the fort flagged first_dungeon: Old Sluice), its flip, the first
## big undead at the slab, one queue set (filled and reordered once), then left to 30:00 (the close is the caller's).
func play_first30() -> void:
	beats = {"first_dungeon": {"happened": false, "begin_t": -1.0, "result_t": -1.0, "exit": ""},
		"flip": {"happened": false, "t": -1.0}, "first_big": {"happened": false, "t": -1.0},
		"queue_set": {"happened": false, "t": -1.0, "entries": 0}, "close": {"happened": false, "t": -1.0}}
	_row("start")
	var fd := ""
	for f in s.view_realm()["forts"]:
		if bool(f["first_dungeon"]) and fd == "":
			fd = str(f["id"])
	if fd != "":
		var o := _raid(fd, float(FIRST30_S))
		if not o.is_empty() and not raids.is_empty():
			beats["first_dungeon"] = {"happened": bool(raids[-1].get("applied", false)), "fort": fd, "begin_t": float(raids[0]["t"]),
				"result_t": float(raids[0]["t"]) + float(o["duration_s"]), "exit": str(raids[-1].get("exit", ""))}
	for fl in flips:
		if str(fl["fort"]) == fd and not bool(beats["flip"]["happened"]):
			beats["flip"] = {"happened": true, "t": float(fl["t"])}
	_act()
	var q: Array = s.view_town()["queue"]
	beats["queue_set"] = {"happened": not q.is_empty() or not builds.is_empty(), "t": s.t, "entries": q.size(),
		"reordered": reorders > 0}
	_tick_to(float(FIRST30_S))
	_row("end")


## The close: cmd_save at a whole second, a fresh GameState, cmd_load with clock_override `gap` s later (the real
## catch-up). A night's close also loads the save into a throwaway state PROBE_S on, for Vei's odds 12 h after closing.
## The odds_* records are view_vei's readiness (Phase I P3's odds split: the series P2 measured, the old formula).
func close(gap: int, night := false) -> Dictionary:
	_tick_to(ceilf(s.t - 1e-9))
	var t0 := s.t
	var v0 := s.view_vei()
	var rec := {"t": t0, "gap": gap, "night": night, "backlog_before": float(v0["backlog"]), "odds_close": float(v0["readiness"]),
		"value_done_before": _value_done()}
	s.clock_override = CLOCK0 + int(t0)
	var sv := s.cmd_save(SLOT)
	if not bool(sv["ok"]):
		notes.append("t %.1f: cmd_save refused %s" % [t0, str(sv["reason"])])
	s.drain_events()
	if night and gap >= PROBE_S:
		var p := _fresh()
		p.clock_override = CLOCK0 + int(t0) + PROBE_S
		if bool(p.cmd_load(SLOT)["ok"]):
			var pv := p.view_vei()
			rec["odds_12h"] = float(pv["readiness"])
			rec["backlog_12h"] = float(pv["backlog"])
	var n := _fresh()
	n.clock_override = CLOCK0 + int(t0) + gap
	var lr := n.cmd_load(SLOT)
	if not bool(lr["ok"]) or int(lr["away_s"]) != gap:
		notes.append("t %.1f: cmd_load %s, away %s of %d" % [t0, str(lr["reason"]), str(lr["away_s"]), gap])
	s = n
	for e in s.catchup_events():
		_on_event(e, "away")
	for e in s.drain_events():
		_on_event(e, "live")
	var aw := s.view_away()
	var ready: Array = []
	for line in aw["ready"]:
		ready.append(str(line["text"]))
	_scan_away(ready)
	var v1 := s.view_vei()
	rec["backlog_after"] = float(v1["backlog"])
	rec["odds_load"] = float(v1["readiness"])
	rec["ready"] = ready
	closes.append(rec)
	_next_fine = s.t
	return rec


func _scan_away(ready: Array) -> void:
	var rep: Dictionary = c["economy"]["idle"]["report"]
	var wall := str(rep["afford_relics_last_fmt"]).replace("{name}", "").strip_edges()
	var tn := s.view_town()
	for text in ready:
		if str(text).ends_with(wall) and first["wall_report"] < 0.0:
			first["wall_report"] = s.t
		if str(text) == str(rep["full_raid"]) and first["full_raid"] < 0.0:
			first["full_raid"] = s.t
		for store in ["gold", "bone"]:
			var producer := "market" if store == "gold" else "bone_mill"
			if str(text).contains(str(rep["afford_raise"][store])) and _stands(tn, producer):
				input_limited.append({"t": s.t, "where": "report", "text": str(text), "store": store, "standing": producer})


func _value_done() -> float:
	var v := 0.0
	for d in done:
		v += float(d["value"])
	return v


# ---------------------------------------------------------------------------------------- the I1 replay ---
## sessions_open: the leader's (a closed sessions run's) commands, issued at the same sim t on a GameState left open
## between them, ticked through the frame path for exactly the frames the time takes. Raids re-resolve from this run's
## own seeds. A command answered otherwise than the leader's, or a raid resolved otherwise, is a divergence (div).
func replay(lead_log: Array, days: int) -> void:
	open_rows = true
	_next_open_row = OPEN_ROW_S
	_clock = s.t
	var bi := 1
	for e in lead_log:
		var et := float(e["t"])
		while bi <= days and float(bi * DAY) <= et:
			_open_to(float(bi * DAY))
			_day_end()
			bi += 1
		_open_to(et)
		if absf(s.t - et) > 1e-9:
			_div(e, "at t %.2f" % s.t)
		_replay_one(e)
	while bi <= days:
		_open_to(float(bi * DAY))
		_day_end()
		bi += 1


## The open game's time: the frames from the schedule's last mark to `target`, counted on the leader's schedule (a
## clock of its own, not the state's t), so a frame the game skips stays skipped and shows at the next comparison.
func _open_to(target: float) -> void:
	_frames(int(round((target - _clock) / FRAME_DT)))
	_clock = target


func _replay_one(e: Dictionary) -> void:
	var op := str(e["op"])
	var a: Array = e["args"]
	var r := {}
	var pre := _stock_snap() if thr_row.is_empty() else {}
	var thr := _thresholds(op) if thr_row.is_empty() else []
	var snap: Dictionary = e.get("snap", {})
	if snap.has("bodies"):  # (the bodies row: every command, closed against open, against one load now)
		bodies_gap_add(bodies_row, float(e["t"]), float(snap["bodies"]), float(s.view_town()["bodies"]), float(_one_load()["bound"]))
	if op == "begin":
		var fid := str(a[0])
		var f := s.view_fort(fid)
		var held := bool(f["held"])
		if held != bool(e.get("held", false)):
			_div(e, "held %s" % str(held))
		r = _exec(op, a)
		_after(op, a, r)
		if bool(r["ok"]):
			_begin_note(fid, f, held)
			_pending = _resolve(r["seed"], held)
	elif op == "apply":
		if _pending.is_empty():
			_div(e, "no open raid")
			return
		if bool(_pending["died"]) != bool(e["died"]) or absf(float(_pending["duration_s"]) - float(e["duration_s"])) > 1e-9 \
				or str(_pending["notes"]["table"]) != str(e["table"]):
			_div(e, "resolved %s %.2f s %s" % [str(_pending["died"]), float(_pending["duration_s"]), str(_pending["notes"]["table"])])
		var o := _pending
		_pending = {}
		var errs := Results.validate("raid", o["result"])
		results["validated"] = int(results["validated"]) + 1
		if not errs.is_empty():
			results["invalid"] = int(results["invalid"]) + 1
		r = _exec(op, [o["result"]])
		_after(op, [], r)
		results["applied" if bool(r["ok"]) else "refused"] = int(results["applied" if bool(r["ok"]) else "refused"]) + 1
		if not raids.is_empty():
			raids[-1]["died"] = bool(o["died"])
			raids[-1]["exit"] = "relish_died" if bool(o["result"]["relish_died"]) else ("warden_beaten" if bool(o["result"]["warden_beaten"]) else "retreated")
	else:
		r = _exec(op, a)
		_after(op, a, r)
	if bool(r.get("ok", false)) != bool(e["ok"]) or str(r.get("reason", "")) != str(e["reason"]):
		_div(e, "answered %s %s" % [str(r.get("ok", false)), str(r.get("reason", ""))])
		if thr_row.is_empty():
			thr_row = threshold_row(e, pre, thr)
			thr_row["open"] = "%s %s" % [str(r.get("ok", false)), str(r.get("reason", ""))]


func _div(e: Dictionary, why: String) -> void:
	div.append({"t": float(e["t"]), "op": str(e["op"]), "args": str(e.get("args", [])), "leader": "%s %s" % [str(e["ok"]), str(e["reason"])],
		"why": why})


## What the I1 gate compares at a day's end: every stock, the backlog, the buildings and levels, the held forts, and t.
func _i1_sample() -> Dictionary:
	var tn := s.view_town()
	var v := s.view_vei()
	var inv := s.view_inventory()
	var stocks := {"gold": float(tn["gold"]), "bone": float(tn["bone"]), "bodies": float(tn["bodies"]),
		"workers": float(tn["workers"]["total"]), "living": float(tn["living"]), "relics": float(inv["relics"]),
		"essence": float(inv["essence"]), "husks": float((inv["husks"] as Array).size()),
		"remnants": float((inv["remnants"] as Array).size()), "backlog": float(v["backlog"]), "vei_pool": float(v["living_pool"])}
	# each judged against max(|open|, floor): 1% of the cap for the stores the town spends to the floor, Vei's pool cap
	# for her pool (test_catchup compare()'s), 1.0 for the rest
	var floors := {"gold": 0.01 * float(tn["gold_cap"]), "bone": 0.01 * float(tn["bone_cap"]),
		"bodies": 0.01 * float(tn["bodies_cap"]), "vei_pool": float(v["pool_cap"])}
	# the bodies are judged within one convoy load instead (the manager's ruling at the E3-6b stop): a closed run's
	# convoys can be at another phase of their trip at the sample than an open run's, so the store can differ by up
	# to a load (_one_load)
	var bounds := {"bodies": _one_load()}
	var bl := {}
	for b in tn["buildings"]:
		bl[str(b["lot_id"])] = "%s L%d" % [str(b["building_id"]), int(b["level"])]
	return {"t": s.t, "stocks": stocks, "floors": floors, "bounds": bounds, "buildings": bl, "held": _held_ids(),
		"pool_wave": _pool_wave()}


## One convoy load, the I1 bodies bound: {bound, carry, haulers}, job.haul.carry × the haulers staffed in this run now
## (as view_town's jobs row counts them).
func _one_load() -> Dictionary:
	var haulers := 0.0
	for j in s.view_town()["jobs"]:
		if str(j["id"]) == "haul":
			haulers = float(j["staffed"])
	var carry := float(c["economy"]["job"]["haul"]["carry"])
	return {"bound": carry * haulers, "carry": carry, "haulers": haulers}


## Vei's tithe clock and her pool's rates at an I1 sample, for i1_compare's pool bound (E4 step 3, the manager's
## ruling (ii)): the running wave (wave_id -1 when none, its s_left and multiplier), the clock (next_s counts down to
## wave next_id: the warned one, else the next to be warned), the period it would schedule now, her q and the fort
## shipping of the last step (r_shipped less the surge), and the configs the bound reads.
func _pool_wave() -> Dictionary:
	var tp: Dictionary = s.realm.tithe
	var wv: Dictionary = tp.get("wave", {})
	var wn: Dictionary = tp.get("warning", {})
	var give := float(s.realm.vei["r_shipped"])
	for f in s.realm.forts:
		give -= float(f.get("r_surge", 0.0))
	var r: Dictionary = c["realm"]
	return {"started": bool(tp.get("started", false)), "wave_id": int(wv.get("wave_id", -1)),
		"s_left": float(wv.get("s_left", 0.0)), "mult": float(wv.get("mult", -1.0)), "next_s": float(tp.get("next_s", 0.0)),
		"next_id": int(wn["wave_id"]) if not wn.is_empty() else int(tp.get("next_id", 0)), "period": s.realm.tithe_period(),
		"q": maxf(1.0, s.realm.digest_q), "give": maxf(0.0, give), "surge_s": float(r["tithe"]["surge_s"]),
		"surge_mult": float(r["tithe"]["surge_mult"]), "S_vei": float(r["S_vei"]), "R_vei": float(r["R_vei"])}


## The I1 gate's bound on Vei's pool (E4 step 3, ruling (ii)), from a closed sample's `a` and an open one's `b`
## pool_wave. Vei draws her pool down through a wave (its surge plus her fort shipping, less what she converts) and
## refills it to the cap after; when her refill ends well inside a period, both runs' pools sit in [cap - D, cap]
## however far their wave clocks have slipped, D being one wave's net drawdown:
##   D = surge_s x max(0, mult x S_vei + give - R_vei / q),
## with the larger of the two runs' give and q (the larger q converts slower), and the running wave's multiplier (the
## larger of the two), else surge_mult (siege and Relish only lower it). `slip` is the closed run's start of a common
## wave less the open run's (> 0: the open run's waves come first). A run is drawn inside a wave or its refill
## (D / (R_vei / q - give) after the wave's end). `applies` when the two runs' wave states differ: one drawn and the
## other not, or both drawn on different clocks; with the same state the pool stays on catchup_tol. `premise` is false
## when she can't refill (R_vei / q <= give) or the refill doesn't end inside the shorter period; D then never applies.
static func pool_wave_bound(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.is_empty() or b.is_empty():
		return {}
	var q := maxf(float(a["q"]), float(b["q"]))
	var give := maxf(float(a["give"]), float(b["give"]))
	var mult := maxf(float(a["mult"]), float(b["mult"]))
	if mult < 0.0:
		mult = float(b["surge_mult"])
	var surge_s := float(b["surge_s"])
	var conv := float(b["R_vei"]) / q
	var d := surge_s * maxf(0.0, mult * float(b["S_vei"]) + give - conv)
	var refill := conv - give
	var refill_s := d / refill if refill > 0.0 else INF
	var premise := refill > 0.0 and surge_s + refill_s < minf(float(a["period"]), float(b["period"]))
	var n := maxi(int(a["next_id"]), int(b["next_id"]))
	var slip := (float(a["next_s"]) + float(n - int(a["next_id"])) * float(a["period"])) - (
		float(b["next_s"]) + float(n - int(b["next_id"])) * float(b["period"]))
	var drawn := []
	for w in [a, b]:
		var since := surge_s - float(w["s_left"]) if int(w["wave_id"]) >= 0 else float(w["period"]) - float(w["next_s"])
		drawn.append(bool(w["started"]) and (int(w["wave_id"]) >= 0 or since - surge_s <= refill_s))
	var same: bool = (not drawn[0] and not drawn[1]) or (absf(slip) < 1e-6 and int(a["wave_id"]) == int(b["wave_id"]))
	return {"bound": d, "slip": slip, "q": q, "give": give, "mult": mult, "refill_s": refill_s if refill > 0.0 else -1.0, "premise": premise,
		"drawn_closed": drawn[0], "drawn_open": drawn[1], "applies": premise and not same}


## The I1 gate's check of a closed sample `a` against the open one `b`: the same t exactly, every stock within `tol`, the
## same buildings and levels, the same held forts. A stock in either sample's `bounds` (the bodies: one convoy load) is
## judged by its absolute difference against that bound instead, never tighter than `tol` (with no haulers staffed the
## load is 0). The load is carry x the larger of the two runs' staffed haulers (E4 step 0, the E3 review's item 3: the
## open run's alone made a closed run with more haulers fail on a load it was allowed). `bounded` holds its delta, bound
## and both runs' haulers, and it stays out of `worst`. Vei's pool is judged the same way within one wave's drawdown
## (pool_wave_bound's D) when the two runs' wave states differ (E4 step 3, the manager's ruling (ii): her tithe clocks
## slip apart, so one run can be mid-surge while the other is full); with the same state it stays on `tol`. `pool_wave`
## holds the bound's working, applied or not. The first quantity that differs, and by how much, leads `why`.
## tests/test_i1_gate.gd proves each branch on synthetic samples (two loads dropped fails on the bodies; a pool gap over
## D fails).
static func i1_compare(a: Dictionary, b: Dictionary, tol: float) -> Dictionary:
	var why: Array = []
	var errs := {}
	var bounded := {}
	var worst := ["", 0.0]
	if float(a["t"]) != float(b["t"]):
		why.append("t %.2f closed vs %.2f open" % [float(a["t"]), float(b["t"])])
	var ba: Dictionary = a.get("bounds", {})
	var bb: Dictionary = b.get("bounds", {})
	var pw := pool_wave_bound(a.get("pool_wave", {}), b.get("pool_wave", {}))
	for k in b["stocks"]:
		var y := float(b["stocks"][k])
		var den := maxf(absf(y), float(b["floors"].get(k, 1.0)))
		var d := absf(float(a["stocks"][k]) - y)
		var e := d / maxf(den, 1e-12)
		errs[k] = e
		if k == "vei_pool" and bool(pw.get("applies", false)):
			var bd := maxf(float(pw["bound"]), tol * den)
			bounded[k] = {"delta": d, "bound": bd, "wave": pw}
			if d > bd:
				why.append("vei_pool %s closed vs %s open (delta %s over the bound %s: one wave's drawdown, the clocks %s s apart)" % [
					str(_r(float(a["stocks"][k]))), str(_r(y)), str(_r(d)), str(_r(bd)), str(_r(float(pw["slip"])))])
			continue
		if ba.has(k) or bb.has(k):
			var la: Dictionary = ba.get(k, {})
			var lb: Dictionary = bb.get(k, {})
			var carry := float(lb.get("carry", la.get("carry", 0.0)))
			var h_closed := float(la.get("haulers", 0.0))
			var h_open := float(lb.get("haulers", 0.0))
			var load := carry * maxf(h_closed, h_open)
			var bd := maxf(load, tol * den)
			bounded[k] = {"delta": d, "bound": bd, "load": load, "carry": carry, "haulers_closed": h_closed, "haulers_open": h_open}
			if d > bd:
				why.append("%s %s closed vs %s open (delta %s over the bound %s: %s x max(%s closed, %s open) haulers)" % [k,
					str(_r(float(a["stocks"][k]))), str(_r(y)), str(_r(d)), str(_r(bd)), str(_r(carry)), str(_r(h_closed)), str(_r(h_open))])
			continue
		if e > float(worst[1]):
			worst = [k, e]
		if e > tol:
			why.append("%s %s closed vs %s open (%s%% of %s)" % [k, str(_r(float(a["stocks"][k]))), str(_r(y)), str(_r(e * 100.0)), str(_r(den))])
	if a["buildings"] != b["buildings"]:
		for lot in b["buildings"]:
			if str((a["buildings"] as Dictionary).get(lot, "")) != str(b["buildings"][lot]):
				why.append("lot %s: %s closed vs %s open" % [lot, str((a["buildings"] as Dictionary).get(lot, "-")), str(b["buildings"][lot])])
				break
		if why.is_empty() or not str(why[-1]).begins_with("lot"):
			why.append("buildings %d closed vs %d open" % [(a["buildings"] as Dictionary).size(), (b["buildings"] as Dictionary).size()])
	if a["held"] != b["held"]:
		why.append("held %s closed vs %s open" % [str(a["held"]), str(b["held"])])
	return {"ok": why.is_empty(), "why": why, "errs": errs, "bounded": bounded, "worst": worst, "pool_wave": pw}


# -------------------------------------------------------------------------------------------- away risk ---
## away_risk's prepared setup before a 24 h absence: the weak held forts (margin will_fall or thin) raided, WAR raised
## until it supports every held fort (view_projection; WORK and FLOOD keep their ratio), a siege at the thinnest held
## fort (a spare big, else the last party member), and a simulacrum there if one is ready or can be crafted.
## "Prepared" (E4 step 5, ruling B1 (ii); IDLE §8): what a player does before a long absence, reading each held fort's
## margin forecast (view_fort().hold: its settled WAR against its one-wave need; the lowest margin draws the next wave).
## The counters go to the lowest margin (one siege big undead and one simulacrum); then the valve's WAR rises in 0.05
## steps, WORK and FLOOD keeping their ratio, until no held fort reads under its need, and no further: WAR is global,
## so a player raises it only as far as the weakest fort needs, and growth pays for every step. Relish goes home.
## Before B1 (ii) it raided the thin forts and raised WAR until war_supports (steady, flat in Vei's pressure) was met.
func prepare_away() -> Dictionary:
	var rec := {"raided": [], "valve": {}, "siege": {}, "simulacrum": {}}
	_act()
	var thin := _lowest_hold()
	if thin != "":
		var uid := ""
		var party: Array = []
		for b in s.view_big_undead()["big_undead"]:
			if str(b["place"]) == "party":
				party.append(str(b["uid"]))
			elif uid == "":
				uid = str(b["uid"])
		if uid == "" and not party.is_empty():
			uid = str(party[-1])
		if uid != "":
			var r := _cmd("place", [uid, "fort:" + thin])
			rec["siege"] = {"fort": thin, "uid": uid, "ok": bool(r["ok"]), "reason": str(r["reason"])}
		else:
			rec["siege"] = {"fort": thin, "uid": "", "ok": false, "reason": "no big undead"}
		var inv := s.view_inventory()
		if int(inv["simulacra_ready"]) < 1:
			var cr := _cmd("craft", ["simulacrum"])
			rec["simulacrum"]["craft"] = "ok" if bool(cr["ok"]) else str(cr["reason"])
		if int(s.view_inventory()["simulacra_ready"]) >= 1:
			var dr := _cmd("deploy", [thin])
			rec["simulacrum"]["deploy"] = "ok" if bool(dr["ok"]) else str(dr["reason"])
		_tick_to(s.t + 1.0)
	rec["valve"] = _pump_war()
	if str(s.view_relish()["state"]) != "home":
		_cmd("move", ["covington"])
		_tick_until(func(): return str(s.view_relish()["state"]) == "home", s.t + 600.0)
	return rec


## prepare_away's WAR: up in WAR_STEP steps (WORK and FLOOD keeping their ratio) until no held fort WAR can save reads a
## margin under 0, and never past WAR_MAX. A fort that needs more than WAR_MAX at the valve now (war × need ÷ war_in, as
## _war_topup reads it) is a lost cause: it is let go, as _war_topup lets it go in a session (E4 review item 11 (a);
## before, the pump ran to WAR_MAX for it, paying growth for a fort WAR can't hold). A fort no dispatch has reached yet
## (war_in 0) is still counted. {from, war, ok, min_margin (over the forts not let go), let_go}.
func _pump_war() -> Dictionary:
	var tg: Dictionary = s.view_hud()["valve_target"]
	var wf := maxf(1e-9, float(tg["work"]) + float(tg["flood"]))
	var war := float(tg["war"])
	var gone: Array = []
	for f in s.view_realm()["forts"]:
		var h: Dictionary = f["hold"]
		if bool(f["held"]) and float(h["war_in"]) > 0.0 and war * float(h["need"]) / float(h["war_in"]) > WAR_MAX + 1e-9:
			gone.append(str(f["id"]))
	var rec := {"from": war, "war": war, "min_margin": _min_hold_margin(gone), "let_go": gone}
	while float(rec["min_margin"]) < 0.0 and war < WAR_MAX - 1e-9:
		war = minf(WAR_MAX, war + WAR_STEP)
		var ok := bool(_cmd("valve", [float(tg["work"]) / wf * (1.0 - war), war, float(tg["flood"]) / wf * (1.0 - war)])["ok"])
		_tick_to(s.t + 1.0)
		rec = {"from": float(tg["war"]), "war": war, "ok": ok, "min_margin": _min_hold_margin(gone), "let_go": gone}
	return rec


## away_risk's default row (the 03:28 target's premise: the day-3 state at the default valve): the valve back to the new
## game's (economy.json opening.valve), undoing the in-session top-up (ruling 3, _war_topup).
func default_valve() -> Dictionary:
	var v: Dictionary = s._cfgs["economy"]["opening"]["valve"]
	var from: Dictionary = s.view_hud()["valve_target"].duplicate()
	var r := _cmd("valve", [float(v["work"]), float(v["war"]), float(v["flood"])])
	return {"from": from, "ok": bool(r["ok"]), "min_margin": _min_hold_margin()}


## away_risk_real's WAR cut: the valve's WAR to 0, WORK and FLOOD keeping their ratio (a player who turned WAR down for
## growth before leaving).
func cut_war() -> Dictionary:
	var tg: Dictionary = s.view_hud()["valve_target"]
	var wf := maxf(1e-9, float(tg["work"]) + float(tg["flood"]))
	var r := _cmd("valve", [float(tg["work"]) / wf, 0.0, float(tg["flood"]) / wf])
	return {"from": tg.duplicate(), "ok": bool(r["ok"]), "reason": str(r["reason"]),
		"war_supports": s.view_hud()["war_supports"].duplicate()}


## The held fort with the lowest margin in its forecast (view_fort().hold.margin; ties in world order), "" with none.
func _lowest_hold() -> String:
	var best := ""
	var low := INF
	for f in s.view_realm()["forts"]:
		if bool(f["held"]):
			var m := float(s.view_fort(str(f["id"]))["hold"]["margin"])
			if m < low:
				low = m
				best = str(f["id"])
	return best


## The lowest held margin (view_fort().hold.margin), INF with none held.
func _min_hold_margin(skip: Array = []) -> float:
	var low := INF
	for f in s.view_realm()["forts"]:
		if bool(f["held"]) and not skip.has(str(f["id"])):
			low = minf(low, float(s.view_fort(str(f["id"]))["hold"]["margin"]))
	return low


## The held forts, the most in need first: will_fall, thin, safe, then the lower garrison_rate, then world order.
func _held_forts_by_need() -> Array:
	var out: Array = []
	for f in s.view_realm()["forts"]:
		if bool(f["held"]):
			out.append(f)
	var rank := {"will_fall": 0, "thin": 1, "safe": 2}
	out.sort_custom(func(a, b): return int(rank.get(str(a["margin"]), 3)) * 1.0e9 + float(a["garrison_rate"]) < int(rank.get(str(b["margin"]), 3)) * 1.0e9 + float(b["garrison_rate"]))
	return out


func _held_ids() -> Array:
	var out: Array = []
	for f in s.view_realm()["forts"]:
		if bool(f["held"]):
			out.append(str(f["id"]))
	out.sort()
	return out


## An absence of `gap` s from the state as it stands: the held forts lost.
func leave(gap: int) -> Dictionary:
	var before := _held_ids()
	var n0 := retakes.size()
	var rec := close(gap)
	var after := _held_ids()
	var lost: Array = []
	for id in before:
		if not after.has(id):
			lost.append(id)
	var rt: Array = []
	for i in range(n0, retakes.size()):
		rt.append(str(retakes[i]["fort"]))
	return {"held_at_leave": before, "held_at_return": after, "lost": lost, "lost_n": lost.size(),
		"lost_frac": float(lost.size()) / float(before.size()) if not before.is_empty() else -1.0, "retaken": rt,
		"ready": rec.get("ready", [])}


# ------------------------------------------------------------------------------------------------ events ---
func _on_event(e: Dictionary, where: String) -> void:
	var t := float(e.get("t", s.t))
	match str(e["type"]):
		"queue_started":
			var cost := _cost(str(e["building_id"]), int(e["level"]))
			builds.append({"t": t, "b": str(e["building_id"]), "lot": str(e["lot_id"]), "level": int(e["level"]),
				"waited_on": str(e["waited_on"]), "gold": cost[0], "bone": cost[1], "relics": cost[2], "where": where})
			if str(e["waited_on"]) == "no_bone" and first["bone_wait_event"] < 0.0:
				first["bone_wait_event"] = t
		"grow_started":  # (Phase I P3, Q-b) the Grow stance's start: a build the bot didn't queue, waited_on "grow"
			var cost := _cost(str(e["building_id"]), int(e["level"]))
			builds.append({"t": t, "b": str(e["building_id"]), "lot": str(e["lot_id"]), "level": int(e["level"]),
				"waited_on": "grow", "gold": cost[0], "bone": cost[1], "relics": cost[2], "where": where})
		"building_done":
			var cost := _cost(str(e["building_id"]), int(e["level"]))
			done.append({"t": t, "b": str(e["building_id"]), "lot": str(e["lot_id"]), "level": int(e["level"]),
				"value": cost[0] + cost[1], "where": where})
			if str(e["building_id"]) == "chapel_of_vats" and int(e["level"]) == 1 and first["chapel"] < 0.0:
				first["chapel"] = t
		"building_unpaid":
			unpaid.append({"t": t, "b": str(e["building_id"]), "lot": str(e["lot_id"]), "unpaid": bool(e["unpaid"]), "where": where})
		"relish_died":
			deaths_ev.append({"t": t, "outcome": str(e["outcome"]), "in_place": bool(e["in_place"]), "where": where})
		"fort_flipped":
			flips.append({"t": t, "fort": str(e["fort_id"]), "where": where})
		"fort_retaken":
			retakes.append({"t": t, "fort": str(e["fort_id"]), "where": where})
		"loot_banked":
			loot.append({"t": t, "fort": str(e["fort_id"]), "relics": int(e["relics"]), "essence": int(e["essence"]),
				"blueprints": e["blueprints"], "where": where})
		"counter_garrison_cleared":
			clears.append({"t": t, "fort": str(e["fort_id"])})
		"tier_up":
			tiers.append({"t": t, "tier": str(e["tier"]), "where": where})
		"tithe_wave":
			if sample_i1:
				wave_targets[int(e["wave_id"])] = [str(e["fort_id"]), t]


## [gold, bone, relics] of a construction at `level` (buildings.json: cost, then level_costs).
func _cost(building_id: String, level: int) -> Array:
	var b: Dictionary = c["buildings"].get(building_id, {})
	var x: Dictionary = b.get("cost", {})
	if level > 1:
		var lc: Array = b.get("level_costs", [])
		x = lc[level - 2] if level - 2 < lc.size() else {}
	return [float(x.get("gold", 0.0)), float(x.get("bone", 0.0)), int(x.get("relics", 0))]


# -------------------------------------------------------------------------------------------------- rows ---
static func _stat0() -> Dictionary:
	return {"n": 0, "mint_min": INF, "mint_max": -INF, "mint_sum": 0.0, "bodies_min": INF, "bodies_max": -INF}


static func _stat_add(d: Dictionary, mint: float, bn: float) -> void:
	d["n"] = int(d["n"]) + 1
	d["mint_min"] = minf(float(d["mint_min"]), mint)
	d["mint_max"] = maxf(float(d["mint_max"]), mint)
	d["mint_sum"] = float(d["mint_sum"]) + mint
	d["bodies_min"] = minf(float(d["bodies_min"]), bn)
	d["bodies_max"] = maxf(float(d["bodies_max"]), bn)


static func _stat_out(d: Dictionary) -> Dictionary:
	if int(d["n"]) == 0:
		return {"n": 0}
	var mx := float(d["mint_max"])
	return {"n": int(d["n"]), "mint_min": _r(float(d["mint_min"])), "mint_max": _r(mx),
		"mint_mean": _r(float(d["mint_sum"]) / int(d["n"])), "mint_swing": _r((mx - float(d["mint_min"])) / mx) if mx > 0.0 else 0.0,
		"bodies_net_min": _r(float(d["bodies_min"])), "bodies_net_max": _r(float(d["bodies_max"]))}


func _fine_sample() -> void:
	var r: Dictionary = s.view_rates()["rates"]
	var mint := float(r["mint"]["in"])
	var bn := float(r["bodies"]["net"])
	var d := str(int(s.t / DAY))
	if not _fine_day.has(d):
		_fine_day[d] = _stat0()
	_stat_add(_fine_day[d], mint, bn)
	_stat_add(_win, mint, bn)
	if not _muster_day.has(d):
		_muster_day[d] = {"n": 0, "muster_sum": 0.0, "work_sum": 0.0}
	var md: Dictionary = _muster_day[d]
	md["n"] = int(md["n"]) + 1
	md["muster_sum"] = float(md["muster_sum"]) + float(s._split["muster"])
	md["work_sum"] = float(md["work_sum"]) + float(s._split["work"])


## Q-h (Phase I P3; BALANCE §5's "the wrong metric"): workers.muster_per_day from _muster_day: per day of live time the
## mean muster (mass/s), the mean WORK stream and the muster's share of it (0 with no WORK). The idle count sits at
## worker.idle_cap whenever the inflow outruns the slots, so the share of labour that streams on is the number.
func _muster_out() -> Dictionary:
	var out := {}
	for d in _muster_day:
		var md: Dictionary = _muster_day[d]
		var n := maxi(1, int(md["n"]))
		var wk := float(md["work_sum"])
		out[d] = {"n": int(md["n"]), "muster_mean": _r(float(md["muster_sum"]) / n), "work_mean": _r(wk / n),
			"muster_share": _r(float(md["muster_sum"]) / wk) if wk > 0.0 else 0.0}
	return out


static func _r(x: float) -> float:
	return snappedf(x, 0.0001)


static func _band(t: float) -> String:
	for b in BANDS:
		if t >= float(b[1]) and t < float(b[2]):
			return str(b[0])
	return "S3"


func _big_counts(bu: Dictionary) -> Dictionary:
	var out := {"held": int(bu["count"]), "cap": int(bu["cap"]), "party": 0, "foreman": 0, "siege": 0, "crypt": 0,
		"keep": _keep.size()}
	for b in bu["big_undead"]:
		var p := str(b["place"])
		if p == "party":
			out["party"] += 1
		elif p.begins_with("town:"):
			out["foreman"] += 1
		elif p.begins_with("fort:"):
			out["siege"] += 1
		else:
			out["crypt"] += 1
	return out


func _row(kind: String) -> Dictionary:
	var tn := s.view_town()
	var v := s.view_vei()
	var inv := s.view_inventory()
	var bk := s.view_backups()
	var rates: Dictionary = s.view_rates()["rates"]
	var q: Array = tn["queue"]
	var staffed := 0.0
	var slots := 0
	for j in tn["jobs"]:
		staffed += float(j["staffed"])
		slots += int(j["slots"])
	var free := 0
	for l in tn["lots"]:
		if bool(l["unlocked"]) and str(l["building_id"]) == "":
			free += 1
	var no_lot := false
	for b in s.view_catalog()["buildings"]:
		no_lot = no_lot or str(b["reason"]) == "no_lot"
	if free == 0 and no_lot and first["lots_full"] < 0.0:
		first["lots_full"] = s.t
	var nb := 0
	var lv := 0
	for b in tn["buildings"]:
		if int(b["level"]) >= 1:
			nb += 1
			lv += int(b["level"])
	var held: Array = []
	var margins := {}
	for f in s.view_realm()["forts"]:
		if bool(f["held"]):
			held.append(str(f["id"]))
			margins[str(f["id"])] = str(f["margin"])
	var fronts: Array = []
	for fr in v["fronts"]:
		fronts.append({"id": str(fr["id"]), "have": _r(float(fr["have"])), "need": _r(float(fr["need"]))})
	var vs := 0
	for vt in bk["vats"]:
		vs += 1 if bool(vt["staffed"]) else 0
	var h := _head(q)
	var head := {}
	if h >= 0:
		head = {"b": str(q[h]["building_id"]), "level": int(q[h]["level"]), "status": str(q[h]["status"]),
			"reason": str(q[h]["reason"]), "affordable_in_s": _r(float(q[h]["affordable_in_s"]))}
	_observe()
	ledger_max = maxf(ledger_max, GameState.Ledger.error(s.ledger()))
	var row := {"profile": profile, "kind": kind, "t": s.t, "day": _r(s.t / DAY), "band": _band(s.t),
		"gold": _r(float(tn["gold"])), "gold_cap": _r(float(tn["gold_cap"])), "bone": _r(float(tn["bone"])),
		"bone_cap": _r(float(tn["bone_cap"])), "bodies": _r(float(tn["bodies"])), "bodies_cap": _r(float(tn["bodies_cap"])),
		"workers": _r(float(tn["workers"]["total"])), "workers_idle": _r(float(tn["workers"]["idle"])),
		"workers_staffed": _r(staffed), "slots": slots, "living": _r(float(tn["living"])), "living_cap": _r(float(tn["living_cap"])),
		"tier": str(tn["tier"]), "lots_free": free, "no_lot": no_lot, "buildings": nb, "levels": lv,
		"queue_len": q.size(), "queue_head": head, "next_afford_s": _r(_next_afford(q)), "relics_wall": _queue_wall(q),
		"mint": _r(float(rates["mint"]["in"])), "bodies_net": _r(float(rates["bodies"]["net"])), "window": _stat_out(_win),
		"backlog": _r(float(v["backlog"])), "odds": _r(float(v["odds"])), "readiness": _r(float(v["readiness"])),
		"backups": int(v["backups"]), "sign": int(v["sign"]), "digest_q": _r(float(v["digest_q"])),
		"fronts": fronts, "fronts_met": int(v["fronts_met"]), "fronts_required": int(v["fronts_required"]),
		"relics": int(inv["relics"]), "essence": int(inv["essence"]), "husks": (inv["husks"] as Array).size(),
		"remnants": (inv["remnants"] as Array).size(), "big": _big_counts(s.view_big_undead()), "held": held,
		"margins": margins, "phylactery": int(bk["phylactery_charges"]), "clones_ready": int(bk["clones_ready"]),
		"vats": (bk["vats"] as Array).size(), "vats_staffed": vs, "relish": str(s.view_relish()["state"]),
		"raids": raids.size(), "deaths": deaths_ev.size()}
	rows.append(row)
	_win = _stat0()
	if print_rows:
		print("AUTOPLAY_ROW " + JSON.stringify(row))
	return row


func _day_end() -> void:
	var row := _row("day_end")
	fronts_daily.append({"day": int(round(s.t / DAY)), "fronts": row["fronts"], "met": row["fronts_met"],
		"met_full": _full_met(s.view_vei()), "required": row["fronts_required"]})
	if sample_i1:
		i1.append(_i1_sample())


# ----------------------------------------------------------------------------------------------- summary ---
func policy() -> Dictionary:
	return {
		"queue": "kept filled to queue_max from the fixed priority list (BUILD_LIST then LADDER, explicit lots; the crypt's levels 2 and 3 at its head from the first look that keeps a big, or finds the crypt full while a husk waits)%s" % (
			"; reorder: the soonest-affordable entry to the head when the head reads -1 or later than another" if reorder else "; no reorder (static)"),
		"raids": ("one a session at the day's tier (days 1-2 t1, 3-4 t2, 5-6 t3, 7-8 t4)" if static_raids else
			"the highest tier the party reaches (tier T needs raid.json party_profiles[T]'s bigs), the first dungeon first, higher yield, unheld before held") +
			"; never retreat; held forts once yield_mult >= %.1f%s; deaths %s; held door on" % [HELD_RAID_YIELD, " (never: ablation a)" if no_held else "", deaths] +
			("; bank_bigs: once giants or carvers is short, the party holds the bigs on those fronts between raids and is emptied before each raid (t1 only; the held door off)" if bank_bigs else "") +
			("; keep_fronts: keepers stay home, so the reach counts the raiders only" if keep_fronts else "; raid_all: every big in the party rides"),
		"raise": "whenever a husk is held and the crypt has room, with every remnant that fits (%s)" % (
			"giants' or carvers' stat first when that brings a larger share of the front's want, else the largest magnitude" if keep_fronts else "largest magnitude first"),
		"keep": ("the bigs whose stat brings >= %.2f of what the bigs must bring to giants or carvers, best first, as many as meet each front's want, the better-covered front first; at most cap - %d in all, one front a big" % [KEEP_SHARE, RAID_ROOM]) if keep_fronts else "none",
		"placement": "the party fills first (oldest bigs, up to %d), fronts by best stat; the first spare foreman at the Market, at the Bone Mill while the head waits on bone; later spares in the crypt; sieges only in away_risk's prepared setup" % PARTY_MAX,
		"vats": "best case: staffed as soon as a Chapel of Vats exists",
		"craft": "one phylactery charge whenever it can be crafted and none is held; no simulacra (except away_risk prepared); a t1 husk (view_catalog().husk_craft: the weakest remnants and bone) when giants or carvers is short of its want, the crypt has room, a remnant is left for the raise and the bone left covers the queue head's bone, of the kind whose fill brings the larger share of a short front's want",
		"stances": "vigil and harvest on", "valve": "in every look, WAR to the least 0.05 step covering every held fort WAR can save (WORK:FLOOD kept), floored at the opening valve's; a fort needing more than 0.95 is let go (ruling 3); away_risk's default row resets it, its prepared row raises it further",
		"schedule": "3 x 20 min sessions a sim day at 00:00, 04:00, 08:00; closed 3 h 40 m, 3 h 40 m, 15 h 40 m",
	}


static func labels() -> Dictionary:
	return {
		"held_raids": "GUESS: a held fort's raid has no measured stand-in (death x0.5, duration x0.5, party loss x0.5; BALANCE §8)",
		"big_undead": "GUESS: the masses raised are an upper bound (BALANCE §8); a won raid loses each party member at t2 0.712, t3 0.48, t4 0.41",
		"vats": "best case: vats staffed as soon as a Chapel exists",
		"field": "8 x 6 influence field (harness): village owners, so migrants and living, differ from the shipped 128 x 90",
		"tier_gate": "the sim gates no raid tier; the bot's reach rule keeps the stand-ins' party premise (raid.json party_profiles)",
		"margin": "today's margin chip credits no siege or simulacrum (STATE-API §5.5)",
		"closed_measures": "in closed profiles the time away is seen only through the catch-up's events and the session-boundary rows",
	}


static func _median(xs: Array) -> float:
	if xs.is_empty():
		return -1.0
	var a := xs.duplicate()
	a.sort()
	var n := a.size()
	var m := int(floorf(n / 2.0))
	return float(a[m]) if n % 2 == 1 else 0.5 * (float(a[m - 1]) + float(a[m]))


func summary() -> Dictionary:
	var t_end := s.t
	var out := {"profile": profile, "t_end": t_end, "days": _r(t_end / DAY), "seed": SEED, "policy": policy(), "labels": labels()}
	if not beats.is_empty():
		out["beats"] = beats
	# time to the next affordable item: the queue's own projection at each row, and the gaps between starts
	var na := {}
	for b in BANDS:
		na[b[0]] = {"projected": [], "gaps": []}
	for r in rows:
		if float(r["next_afford_s"]) >= 0.0:
			(na[r["band"]]["projected"] as Array).append(float(r["next_afford_s"]))
	var starts: Array = []
	for b in builds:
		starts.append(float(b["t"]))
	starts.sort()
	for i in range(1, starts.size()):
		(na[_band(float(starts[i]))]["gaps"] as Array).append(float(starts[i]) - float(starts[i - 1]))
	var nas := {"basis": "queue (policy above): affordable_in_s of the soonest non-gated entry at each row; and the gaps between queue starts, live and away"}
	for k in na:
		var p: Array = na[k]["projected"]
		var g: Array = na[k]["gaps"]
		nas[k] = {"rows": p.size(), "projected_median_s": _r(_median(p)), "starts": g.size(), "gap_median_s": _r(_median(g)),
			"gap_max_s": _r(g.max() if not g.is_empty() else -1.0)}
	out["next_affordable"] = nas
	# workers (Q-h, Phase I P3: the muster rate replaces idle_max_after_1h, which sat at worker.idle_cap by design)
	out["workers"] = {"muster_per_day": _muster_out(), "flat_runs": _flat_runs(t_end),
		"basis": "muster_per_day: GameState's split muster and work every 10 s of live time, the share muster / work; flat runs: over 30 min with no building finished (building_done, live and away)"}
	out["lots"] = {"first_full_with_no_lot_t": first["lots_full"]}
	out["stores"] = _stores()
	var sw := {}
	for d in _fine_day:
		sw[d] = _stat_out(_fine_day[d])
	out["mint_swing"] = {"per_day": sw, "basis": "view_rates mint.in and bodies.net every 10 s of live time"}
	out["growth_away"] = _growth_away()
	out["builds_per_6h"] = _per_6h()
	out["vei"] = {"ready_t": vei_ready_t, "ready_day": _r(vei_ready_t / DAY) if vei_ready_t >= 0.0 else -1.0,
		"never": vei_ready_t < 0.0, "ready_wave_t": vei_ready_wave_t,
		"ready_wave_day": _r(vei_ready_wave_t / DAY) if vei_ready_wave_t >= 0.0 else -1.0,
		"basis": "ready: fronts at her full pool, at the look and on arrival; ready_wave: at the pool she has then, at the look only",
		"fronts_daily": fronts_daily, "raised": raised, "crafted": crafted,
		"keep_churn": keep_churn, "crypt_up_h": _r(crypt_up_t / 3600.0) if crypt_up_t >= 0.0 else -1.0}
	out["relics"] = _relics()
	out["first_t2_raid"] = first_raid.get("t2", {})
	out["first_t3_raid"] = first_raid.get("t3", {})
	out["backups"] = {"first_vat_t": first["vat"], "first_chapel_t": first["chapel"], "first_clone_seen_t": first["clone"],
		"chapel_to_first_clone_s": float(first["clone"]) - float(first["chapel"]) if first["clone"] >= 0.0 and first["chapel"] >= 0.0 else -1.0,
		"label": "vats best case; a clone's fill raises no event, so it is the first look that saw one ready"}
	var nights: Array = []
	for cl in closes:
		if bool(cl["night"]):
			nights.append({"t": cl["t"], "odds_close": _r(float(cl["odds_close"])), "odds_12h": _r(float(cl.get("odds_12h", -1.0))),
				"odds_load": _r(float(cl["odds_load"])), "backlog_close": _r(float(cl["backlog_before"])),
				"backlog_12h": _r(float(cl.get("backlog_12h", -1.0)))})
	out["odds_12h_after_close"] = nights
	var fb := {}
	if not builds.is_empty():
		var b0: Dictionary = builds[0]
		for b in builds:
			if float(b["t"]) < float(b0["t"]):
				b0 = b
		fb = {"first_build": str(b0["b"]), "level": int(b0["level"]), "t": b0["t"], "is_bone_mill": str(b0["b"]) == "bone_mill" and int(b0["level"]) == 1}
	out["mill_first"] = fb
	out["wall"] = {"relics_wall_report_t": first["wall_report"], "relics_wall_queue_t": first["wall_queue"],
		"full_raid_report_t": first["full_raid"], "basis": "view_away's ready lines after each load; the queue's statuses at each look"}
	out["bone_binds"] = {"first_wait_seen_t": first["bone_wait_seen"], "first_start_after_bone_wait_t": first["bone_wait_event"]}
	out["stables"] = _stables(t_end)
	out["input_limited"] = input_limited
	var dc := {"count": 0, "phylactery": 0, "clone": 0, "unmade": 0}
	for d in deaths_ev:
		dc["count"] += 1
		dc[str(d["outcome"])] = int(dc.get(str(d["outcome"]), 0)) + 1
	out["deaths"] = dc
	var rt := {"count": raids.size(), "held": 0, "died": 0, "by_tier": {"1": 0, "2": 0, "3": 0, "4": 0}}
	for r in raids:
		rt["by_tier"][str(r["tier"])] += 1
		rt["held"] += 1 if bool(r["held"]) else 0
		rt["died"] += 1 if bool(r.get("died", false)) else 0
	out["raids"] = rt
	out["flips"] = flips.size()
	out["retakes"] = {"count": retakes.size(), "away": retakes.filter(func(x): return x["where"] == "away").size()}
	out["tiers"] = tiers
	out["results"] = results
	out["ledger_max_err"] = ledger_max
	out["reorders"] = reorders
	out["refusals"] = refusals
	out["notes"] = notes
	var wmax := 0.0
	for w in war_log:
		wmax = maxf(wmax, float(w["to"]))
	out["war_topup"] = {"on": war_topup, "changes": war_log.size(), "max": _r(wmax), "valve_war_end": _r(float(s.view_hud()["valve_target"]["war"])), "log": war_log.slice(0, 60)}
	return out


func _flat_runs(t_end: float) -> Array:
	var ts: Array = [0.0]
	for d in done:
		ts.append(float(d["t"]))
	ts.append(t_end)
	ts.sort()
	var out: Array = []
	for i in range(1, ts.size()):
		var a := float(ts[i - 1])
		var b := float(ts[i])
		if b - a > 1800.0:
			var where := "live"
			for cl in closes:
				var c0 := float(cl["t"])
				var c1 := c0 + float(cl["gap"])
				if a >= c0 - 1e-6 and b <= c1 + 1e-6:
					where = "away"
				elif a < c1 and b > c0:
					where = "mixed"
			var inside: Array = rows.filter(func(r): return float(r["t"]) >= a and float(r["t"]) <= b)
			var rec := {"start_t": a, "len_s": b - a, "where": where}
			if inside.size() >= 2:
				rec["gold"] = [inside[0]["gold"], inside[-1]["gold"]]
				rec["bone"] = [inside[0]["bone"], inside[-1]["bone"]]
			out.append(rec)
	return out


func _stores() -> Dictionary:
	var per: Array = []
	var prev := {}
	var spent_all := 0.0
	var bone0 := float(rows[0]["bone"]) if not rows.is_empty() else 0.0
	for r in rows:
		if str(r["kind"]) != "day_end":
			continue
		var day := int(round(float(r["t"]) / DAY))
		var spent := 0.0
		for b in builds:
			if float(b["t"]) > float(prev.get("t", -1.0)) and float(b["t"]) <= float(r["t"]):
				spent += float(b["bone"])
		var b_prev := float(prev.get("bone", bone0))
		var income := spent + float(r["bone"]) - b_prev
		per.append({"day": day, "gold": r["gold"], "bone": r["bone"],
			"gold_vs_24h": _r(float(r["gold"]) / float(prev["gold"])) if not prev.is_empty() and float(prev["gold"]) > 0.0 else -1.0,
			"bone_vs_24h": _r(float(r["bone"]) / float(prev["bone"])) if not prev.is_empty() and float(prev["bone"]) > 0.0 else -1.0,
			"bone_spent": _r(spent), "bone_income": _r(income), "bone_spent_share": _r(spent / income) if income > 0.0 else -1.0})
		spent_all += spent
		prev = r
	var tot_income := spent_all + (float(prev["bone"]) - bone0 if not prev.is_empty() else 0.0)
	return {"per_day": per, "bone_spent_share": _r(spent_all / tot_income) if tot_income > 0.0 else -1.0,
		"basis": "day_end rows; bone spent = the queue starts' bone prices; income = spent + the stock's change"}


func _growth_away() -> Dictionary:
	if closes.is_empty() or rows.is_empty():
		return {}
	var away_b := 0.0
	for cl in closes:
		away_b += float(cl["backlog_after"]) - float(cl["backlog_before"])
	var total_b := float(s.view_vei()["backlog"]) - float(rows[0]["backlog"])
	var away_v := 0.0
	var total_v := 0.0
	for d in done:
		total_v += float(d["value"])
		away_v += float(d["value"]) if str(d["where"]) == "away" else 0.0
	return {"backlog_share": _r(away_b / total_b) if absf(total_b) > 1e-9 else -1.0, "backlog_away": _r(away_b), "backlog_total": _r(total_b),
		"build_value_share": _r(away_v / total_v) if total_v > 0.0 else -1.0, "build_value_away": _r(away_v), "build_value_total": _r(total_v),
		"basis": "backlog: each close's change (save to load) over the run's; build value: gold + bone of every building_done, away (catch-up events) over all"}


func _per_6h() -> Dictionary:
	var c0 := 0.0
	var span := 0.0
	for cl in closes:
		if float(cl["gap"]) > span:
			span = float(cl["gap"])
			c0 = float(cl["t"])
	if span <= 0.0:
		return {}
	var bins: Array = []
	bins.resize(int(ceilf(span / 21600.0)))
	bins.fill(0)
	var last := -1.0
	for d in done:
		if str(d["where"]) == "away" and float(d["t"]) > c0 and float(d["t"]) <= c0 + span:
			bins[mini(bins.size() - 1, int((float(d["t"]) - c0) / 21600.0))] += 1
			last = maxf(last, float(d["t"]) - c0)
	return {"close_t": c0, "span_s": span, "per_6h": bins, "plateau_start_s": last,
		"basis": "the longest close's building_done events (each build or level), from its start; the plateau starts at the last one"}


func _relics() -> Dictionary:
	var per := {}
	var cum := 0
	var day25 := -1
	var by_t := loot.duplicate()
	by_t.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	for l in by_t:
		var d := int(float(l["t"]) / DAY) + 1
		per[str(d)] = int(per.get(str(d), 0)) + int(l["relics"])
		cum += int(l["relics"])
		if cum >= 25 and day25 < 0:
			day25 = d
	return {"per_day": per, "total": cum, "day_25_reached": day25, "basis": "loot_banked relics (after the cap), by sim day (1-based)"}


func _stables(t_end: float) -> Dictionary:
	var built := false
	for d in done:
		built = built or str(d["b"]) == "stables"
	var spell := -1.0
	var total := 0.0
	for u in unpaid:
		if str(u["b"]) != "stables":
			continue
		if bool(u["unpaid"]) and spell < 0.0:
			spell = float(u["t"])
		elif not bool(u["unpaid"]) and spell >= 0.0:
			total += float(u["t"]) - spell
			spell = -1.0
	if spell >= 0.0:
		total += t_end - spell
	return {"built": built, "unpaid_s": _r(total)}


## Prints the summary and checks what the harness itself promises (never a balance number): every applied result passed
## Results.validate and the real apply_result, and the ledger stayed balanced.
func finish(t: TestUtil, extra := {}) -> Dictionary:
	var sm := summary()
	sm.merge(extra, true)
	print("AUTOPLAY_SUMMARY " + JSON.stringify(sm))
	t.ok(int(results["invalid"]) == 0 and int(results["refused"]) == 0,
		"%s: every raid result (%d) passed Results.validate and apply_result: %s" % [profile, int(results["validated"]), str(results["errors"])])
	t.ok(ledger_max < 1e-6, "%s: the ledger stayed balanced at every row (worst %s)" % [profile, String.num_scientific(ledger_max)])
	return sm


# ------------------------------------------------------------------------------------------------ profiles ---
static func _bot(name: String, cfg: Dictionary, o := {}) -> Autoplayer:
	var b := Autoplayer.new(name, cfg, str(o.get("dir", "")))
	b.deaths = str(o.get("deaths", "human"))
	b.no_held = bool(o.get("no_held", false))
	b.static_raids = bool(o.get("static", false))
	b.reorder = not bool(o.get("static", false))
	b.bank_bigs = bool(o.get("bank_bigs", false))
	b.keep_fronts = not b.bank_bigs and not bool(o.get("raid_all", false))
	b.park_gated = not bool(o.get("skip_fill", false))
	b.print_rows = bool(o.get("print_rows", true))
	return b


## The smoke's run (tests/test_autoplay_smoke.gd): first30, its close (to the next session, 04:00), then one 40 min
## session of the sessions policy. Returns the bot, its summary and the hash of the summary and the final state.
static func smoke(cfg: Dictionary) -> Dictionary:
	var b := _bot("smoke", cfg, {"print_rows": false})
	b.new_game()
	b.play_first30()
	b.close(int(SESSION_OFFSETS[1]) - FIRST30_S)
	b.beats["close"] = {"happened": not b.closes.is_empty() and b.notes.is_empty(), "t": float(FIRST30_S)}
	b._session(float(int(SESSION_OFFSETS[1]) + 2 * SESSION_S), -1, true, "session_start", "session_end")
	var sm := b.summary()
	var h := (JSON.stringify(sm) + JSON.stringify(b.s.to_dict())).sha256_text()
	b.cleanup()
	return {"bot": b, "summary": sm, "hash": h}


static func run_profile(name: String, t: TestUtil) -> int:
	t.suite("autoplay_" + name)
	var u0 := Time.get_ticks_msec()
	var cfg := cfgs()
	match name:
		"first30":
			var b := _bot(name, cfg)
			b.new_game()
			b.play_first30()
			b.close(int(SESSION_OFFSETS[1]) - FIRST30_S)
			b.beats["close"] = {"happened": b.notes.is_empty(), "t": float(FIRST30_S)}
			b._row("after_close")
			b.finish(t)
			b.cleanup()
		"sessions", "once_per_session", "town_only", "static":
			var b := _bot(name, cfg, {"static": name == "static"})
			b.new_game()
			b.play_sessions(days_env(8), 1 if name == "once_per_session" or name == "static" else -1, name != "town_only")
			b.finish(t)
			b.cleanup()
		"continuous":
			var b := _bot(name, cfg)
			b.new_game()
			b.play_continuous(days_env(8))
			b.finish(t)
			b.cleanup()
		"pure_idle":
			var b := _bot(name, cfg)
			b.new_game()
			b.play_pure_idle(mini(7, days_env(7)))
			b.finish(t)
			b.cleanup()
		"sessions_open":
			_p_i1(t, cfg)
		"away_risk":
			_p_away_risk(t, cfg)
		"away_risk_real":
			_p_away_risk(t, cfg, true)
		"bank_bigs":
			_p_versus(t, name, cfg, {"bank_bigs": true}, cfg)
		"ablation_held":
			_p_versus(t, name, cfg, {"no_held": true}, cfg)
		"ablation_keep":
			_p_versus(t, name, cfg, {"raid_all": true}, cfg)
		"ablation_bone":
			_p_versus(t, name, cfgs("no_bone_prices"), {}, cfg)
		"ablation_skip_fill":
			_p_versus(t, name, cfg, {"skip_fill": true}, cfg)
		"sensitivity":
			_p_versus(t, name, cfg, {"deaths": "frozen"}, cfg)
		_:
			t.ok(false, "unknown autoplay profile %s" % name)
	print("  [autoplay] %s: %.1f s wall" % [name, (Time.get_ticks_msec() - u0) / 1000.0])
	return t.failures


## The I1 gate (a real assertion): sessions closed (the leader, its commands logged) against sessions_open, the same
## commands at the same sim t on a game left open between sessions. At each day's end: the same t exactly, the bodies
## within one convoy load (job.haul.carry x the larger of the two runs' haulers staffed, i1_compare's `bounds`), Vei's
## pool within one wave's drawdown when the wave states differ (pool_wave_bound), every other stock within
## idle.catchup_tol, the same buildings and levels, the same held forts; and every replayed command answered as the
## leader's was. Each day prints the wave clocks' slip and D; the run ends with a report row (not a gate): the first
## wave whose target fort differs between the runs (AUTOPLAY_DAYS=8 measures it over 8 days).
static func _p_i1(t: TestUtil, cfg: Dictionary) -> void:
	var days := days_env(2)
	var tol := float(cfg["economy"]["idle"]["catchup_tol"])
	var lead := _bot("sessions", cfg, {"print_rows": false})
	lead.record = true
	lead.sample_i1 = true
	lead.new_game()
	lead.play_sessions(days)
	var fol := _bot("sessions_open", cfg)
	fol.sample_i1 = true
	fol.new_game()
	fol.replay(lead.cmd_log, days)
	var per: Array = []
	var first_bad := ""
	for d in mini(lead.i1.size(), fol.i1.size()):
		var r := i1_compare(lead.i1[d], fol.i1[d], tol)
		var parts: Array = []
		for k in r["errs"]:
			if k == "vei_pool" and (r["bounded"] as Dictionary).has(k):
				var bp: Dictionary = r["bounded"][k]
				parts.append("vei_pool %s/%s delta %s, bound %s (one wave's drawdown)" % [str(_r(float(lead.i1[d]["stocks"][k]))),
					str(_r(float(fol.i1[d]["stocks"][k]))), str(_r(float(bp["delta"]))), str(_r(float(bp["bound"])))])
				continue
			if (r["bounded"] as Dictionary).has(k):
				var bk: Dictionary = r["bounded"][k]
				parts.append("%s %s/%s delta %s, bound %s (one load: %s x max(%s closed, %s open) haulers)" % [k,
					str(_r(float(lead.i1[d]["stocks"][k]))), str(_r(float(fol.i1[d]["stocks"][k]))), str(_r(float(bk["delta"]))),
					str(_r(float(bk["bound"]))), str(_r(float(bk["carry"]))), str(_r(float(bk["haulers_closed"]))), str(_r(float(bk["haulers_open"])))])
				continue
			parts.append("%s %s/%s %.4f%%" % [k, str(_r(float(lead.i1[d]["stocks"][k]))), str(_r(float(fol.i1[d]["stocks"][k]))),
				float(r["errs"][k]) * 100.0])
		print("  [autoplay] I1 day %d (t %.0f): %s; worst %s %.4f%%; buildings %s; held %s" % [d + 1, float(fol.i1[d]["t"]),
			", ".join(PackedStringArray(parts)), str(r["worst"][0]), float(r["worst"][1]) * 100.0,
			"same" if lead.i1[d]["buildings"] == fol.i1[d]["buildings"] else "DIFFER", str(fol.i1[d]["held"])])
		var pw: Dictionary = r["pool_wave"]
		if not pw.is_empty():
			print("  [autoplay] I1 day %d pool waves: clocks %s s apart (closed less open), D %s (q %s, give %s, x%s, refill %s s), drawn closed %s open %s: %s" % [
				d + 1, str(_r(float(pw["slip"]))), str(_r(float(pw["bound"]))), str(_r(float(pw["q"]))), str(_r(float(pw["give"]))),
				str(_r(float(pw["mult"]))), str(_r(float(pw["refill_s"]))), str(pw["drawn_closed"]), str(pw["drawn_open"]),
				"D applies" if bool(pw["applies"]) else ("same wave state: catchup_tol" if bool(pw["premise"]) else "no refill inside a period: catchup_tol")])
		per.append({"day": d + 1, "t": fol.i1[d]["t"], "ok": r["ok"], "why": r["why"], "errs": r["errs"], "bounded": r["bounded"],
			"pool_wave": pw})
		if not bool(r["ok"]) and first_bad == "":
			first_bad = "day %d: %s" % [d + 1, str(r["why"][0])]
		t.ok(bool(r["ok"]), "I1 day %d: sessions closed equals sessions_open at its end (t equal, the bodies within one convoy load, Vei's pool within one wave's drawdown when the wave states differ, every other stock within %.0f%%, buildings and levels, held forts)%s" % [
			d + 1, tol * 100.0, "" if bool(r["ok"]) else ": " + "; ".join(PackedStringArray(r["why"]))])
	t.ok(lead.i1.size() == days and fol.i1.size() == days, "I1: a sample at each of the %d days' ends (closed %d, open %d)" % [days, lead.i1.size(), fol.i1.size()])
	t.ok(fol.div.is_empty(), "I1: every one of the %d replayed commands was answered as the closed run's, and every raid resolved the same%s" % [
		lead.cmd_log.size(), "" if fol.div.is_empty() else ": first " + str(fol.div[0])])
	# a report row, not a gate (E4 step 3, the manager's ruling): the wave clocks slip apart (the catch-up's backlog gap,
	# within catchup_tol, moves her odds and so her period), and past the warning lead a wave can pick another target
	var ids: Array = lead.wave_targets.keys()
	ids.sort()
	var both := 0
	var first_target := {}
	for id in ids:
		if not fol.wave_targets.has(id):
			continue
		both += 1
		if str(lead.wave_targets[id][0]) != str(fol.wave_targets[id][0]):
			var tc := float(lead.wave_targets[id][1])
			first_target = {"wave_id": id, "day": int(tc / DAY) + 1, "closed": [lead.wave_targets[id][0], _r(tc)],
				"open": [fol.wave_targets[id][0], _r(float(fol.wave_targets[id][1]))]}
			break
	print("  [autoplay] I1 wave targets (a report row, not a gate): %d waves in both runs over %d days; %s" % [both, days,
		"none differs" if first_target.is_empty() else "the first to differ is wave %d on day %d: %s closed at t %s, %s open at t %s" % [
			int(first_target["wave_id"]), int(first_target["day"]), str(first_target["closed"][0]), str(first_target["closed"][1]),
			str(first_target["open"][0]), str(first_target["open"][1])]])
	# the threshold row (the E4 review's item 9, a report row, not a gate): the first command answered otherwise, the
	# stock its answer turns on and the threshold, closed against open, so a run says whether it is a straddle
	var tr: Dictionary = fol.thr_row
	if tr.is_empty():
		print("  [autoplay] I1 threshold (a report row, not a gate): every replayed command answered as the closed run's")
	else:
		var parts: Array = []
		for th in tr["thresholds"]:
			parts.append("%s %s: closed %s, open %s, a stock gap of %s%s" % [th["stock"], th["need"], str(th["closed"]), str(th["open"]),
				conv_pct(float(th["gap_rel"])), " (straddle)" if bool(th["straddle"]) else ""])
		var apart := float(tr["stock_gap"]) > tol
		print("  [autoplay] I1 threshold (a report row, not a gate): the first command answered otherwise is %s %s at t %s (closed %s, open %s); %s; %s; other stocks apart (closed, open): %s" % [
			tr["op"], tr["args"], str(_r(float(tr["t"]))), tr["closed"], tr["open"],
			"; ".join(PackedStringArray(parts)) if not parts.is_empty() else "no threshold known for this op",
			("a threshold straddle on a %s stock gap, over the %s tolerance: the runs were already apart" % [conv_pct(float(tr["stock_gap"])), conv_pct(tol)]
				if apart else "a threshold straddle within the tolerance") if bool(tr["straddle"]) else "not a straddle of a known threshold",
			JSON.stringify(tr["differ"])])
	# the bodies row (the step 4 review's item 7, a report row, not a gate): the bodies gap at every replayed command
	# against one load, since the gate's day-end samples miss a break between them
	var br: Dictionary = fol.bodies_row
	print("  [autoplay] I1 bodies at each command (a report row, not a gate): %d commands; the widest gap %s at t %s (one load %s); %d over one load%s" % [
		int(br["n"]), str(br["worst"]), str(br["worst_t"]), str(br["worst_bound"]), int(br["breaks"]),
		"" if (br["first_break"] as Dictionary).is_empty() else ", the first at t %s: closed %s, open %s, a gap of %s over %s" % [
			str(br["first_break"]["t"]), str(br["first_break"]["closed"]), str(br["first_break"]["open"]), str(br["first_break"]["gap"]),
			str(br["first_break"]["bound"])]])
	# the closed leader's own harness checks too (E4 step 0, the E3 review's item 4): its results validated and applied,
	# its ledger balanced. Its summary is tagged so a digest of this log can't take it for the sessions profile's.
	lead.finish(t, {"i1_role": "closed leader of sessions_open"})
	fol.finish(t, {"i1": {"days": per, "tol": tol, "first_difference": first_bad, "commands": lead.cmd_log.size(), "divergences": fol.div.slice(0, 10),
		"wave_targets": {"compared": both, "first_differs": first_target}, "threshold": tr, "bodies_at_commands": br}})
	lead.cleanup()
	fol.cleanup()


## away_risk: the sessions run to the end of day 3's last session (or the midgame_2flips fixture when nothing is held
## there, said so), then a 24 h absence twice from that save: as the sessions bot left it, and after the prepared setup.
## `real` (away_risk_real, E3-7, the manager's ruling 5 at the E3-6b stop: a setup where the risk is real) takes three
## absences from the same save instead: 24 h with WAR cut to 0 (cut_war), and 72 h as the sessions bot left it and
## after the prepared setup. (WAR cut then prepared would be `prepared` again: prepare_away raises WAR from the target.)
## Then the WAR-cut midgame: the midgame_2flips fixture, 24 h as it loads, with WAR cut, and after the prepared setup.
static func _p_away_risk(t: TestUtil, cfg: Dictionary, real := false) -> void:
	var lead := _bot("away_risk_real" if real else "away_risk", cfg)
	lead.new_game()
	lead.play_sessions(3, -1, true, false)
	var src := "the sessions run at the end of day 3's last session (t %.0f)" % lead.s.t
	if lead._held_ids().is_empty():
		src = "FALLBACK: the midgame_2flips fixture (nothing was held at the end of day 3)"
		var g := lead._fresh()
		g.debug_enabled = true
		g.cmd_debug_load_fixture("midgame_2flips")
		g.debug_enabled = false
		lead.s = g
		lead._frame()
		lead._act()
	lead._tick_to(ceilf(lead.s.t - 1e-9))  # a whole second: the save stamps whole seconds
	lead._row("leave")
	lead.s.clock_override = CLOCK0 + int(lead.s.t)
	t.ok(bool(lead.s.cmd_save("risk")["ok"]), "away_risk: the start is saved")
	var out := {"source": src, "t_leave": lead.s.t}
	# [name, away s, WAR cut first, the prepared setup]
	var variants: Array = [["default", DAY, false, false, true], ["as_left", DAY, false, false], ["prepared", DAY, false, true]]
	if real:
		variants = [["war_cut", DAY, true, false], ["default_72h", 3 * DAY, false, false], ["prepared_72h", 3 * DAY, false, true]]
	_away_variants(t, cfg, lead.dir, "risk", lead.s.t, variants, out)
	if not real:
		# E4 review item 11 (b): the default row grades the opening valve (default_valve undoes the bot's in-session top-up,
		# ruling 3), and as_left the bot's own WAR. Side by side, so the 03:28 target ("the default valve loses at least
		# half") is not read as met in play
		var dv: Dictionary = out["default"]
		var al: Dictionary = out["as_left"]
		var w_open := float(cfg["economy"]["opening"]["valve"]["war"])
		var w_play := float(dv["prep"]["valve_default"]["from"]["war"])
		out["default_vs_as_left"] = {"opening_war": w_open, "lost_default": int(dv["lost_n"]), "played_war": w_play,
			"lost_as_left": int(al["lost_n"]), "held": dv["held_at_leave"]}
		print("  [autoplay] away_risk default against as_left (24 h, held at leave %s): at the opening valve's WAR %.2f it loses %d; as left at the bot's in-session WAR %.2f it loses %d. The 03:28 target is graded at the opening valve, not at the WAR a player leaves" % [
			str(dv["held_at_leave"]), w_open, int(dv["lost_n"]), w_play, int(al["lost_n"])])
	if real:
		# the WAR-cut midgame (test_held_forts' setup: midgame_2flips with WAR cut retakes both held forts within about
		# 1 300 s): the fixture as it loads (one substep, no bot turn), 24 h as it stands, with WAR cut, and prepared
		var m := _bot("away_risk_midgame", cfg, {"dir": lead.dir})
		m.s = m._fresh()
		m.s.debug_enabled = true
		m.s.cmd_debug_load_fixture("midgame_2flips")
		m.s.debug_enabled = false
		m._frame()
		m._tick_to(ceilf(m.s.t - 1e-9))
		m.s.clock_override = CLOCK0 + int(m.s.t)
		t.ok(bool(m.s.cmd_save("risk_mid")["ok"]), "away_risk_real: the midgame_2flips start is saved")
		var mo := {"source": "the midgame_2flips fixture as it loads (one substep, no bot turn)", "t_leave": m.s.t}
		_away_variants(t, cfg, lead.dir, "risk_mid", m.s.t, [["midgame_default", DAY, false, false],
			["midgame_war_cut", DAY, true, false], ["midgame_prepared", DAY, false, true]], mo)
		out["midgame"] = mo
	lead.finish(t, {"away_risk": out})
	lead.cleanup()


## away_risk's absences: for each [name, away s, WAR cut first, the prepared setup], a fresh bot loads `slot` (saved at
## `t0`, 0 s away), sets itself up, and is away; its record goes in `out[name]`.
static func _away_variants(t: TestUtil, cfg: Dictionary, dir: String, slot: String, t0: float, variants: Array, out: Dictionary) -> void:
	for vr in variants:
		var variant := str(vr[0])
		var b := _bot("away_risk_" + variant, cfg, {"dir": dir})
		b.s = b._fresh()
		b.s.clock_override = CLOCK0 + int(t0)
		t.ok(bool(b.s.cmd_load(slot)["ok"]), "away_risk %s: the start loads (0 s away: the identity)" % variant)
		b.s.drain_events()
		var prep := {}
		if bool(vr[2]):
			prep["war_cut"] = b.cut_war()
		if vr.size() > 4 and bool(vr[4]):
			prep["valve_default"] = b.default_valve()
		if bool(vr[3]):
			prep.merge(b.prepare_away())
		b._row("leave")
		var rec := b.leave(int(vr[1]))
		rec["away_s"] = int(vr[1])
		rec["prep"] = prep
		b._row("return")
		out[variant] = rec
		print("  [autoplay] away_risk %s (%d h): held %s at leave, %s at return, lost %d%s" % [variant, int(float(vr[1]) / 3600.0),
			str(rec["held_at_leave"]), str(rec["held_at_return"]), int(rec["lost_n"]), "; prep %s" % JSON.stringify(prep) if not prep.is_empty() else ""])
		b.finish(t)


## An ablation or the sensitivity pass under sessions, with the sessions baseline run alongside for the deltas: in
## days to Vei-ready, or in fronts met and backlog at the end when either never gets there.
static func _p_versus(t: TestUtil, name: String, cfg: Dictionary, o: Dictionary, base_cfg: Dictionary) -> void:
	var days := days_env(8)
	var base := _bot("sessions_baseline", base_cfg, {"print_rows": false})
	base.new_game()
	base.play_sessions(days)
	var bs := base.summary()
	var b := _bot(name, cfg, o)
	b.new_game()
	b.play_sessions(days)
	var me := b.summary()
	var lr: Dictionary = b.rows[-1]
	var br: Dictionary = base.rows[-1]
	var dl := {"vei_ready_t": [me["vei"]["ready_t"], bs["vei"]["ready_t"]],
		"delta_days": _r((float(me["vei"]["ready_t"]) - float(bs["vei"]["ready_t"])) / DAY) if float(me["vei"]["ready_t"]) >= 0.0 and float(bs["vei"]["ready_t"]) >= 0.0 else null,
		"at_end": {"t": lr["t"], "fronts_met": [lr["fronts_met"], br["fronts_met"]], "backlog": [lr["backlog"], br["backlog"]],
			"backlog_delta_pct": _r(100.0 * (float(lr["backlog"]) - float(br["backlog"])) / float(br["backlog"])) if float(br["backlog"]) > 0.0 else null,
			"relics": [me["relics"]["total"], bs["relics"]["total"]], "buildings": [lr["buildings"], br["buildings"]], "levels": [lr["levels"], br["levels"]]},
		"basis": "[this, sessions]"}
	b.finish(t, {"versus_sessions": dl})
	base.cleanup()
	b.cleanup()
