class_name RealmSim
extends RefCounted
## Port of the canonical REALM simulation (relish-realms lib/realm-sim.js) with
## necropolis extensions. Autoload-free and headless-testable: pass config dicts in.
##
## THE CRITICAL ASYMMETRY
##   UNDEAD killing LIVING  -> DEAD stays at the fortress. Relish's material.
##   LIVING destroying UNDEAD -> DEAD is shipped to Vei, who makes it LIVING again.
##
## Extensions over the JS canon (documented deviations, BRIEF §10; MECHANICS §3):
##   - EMPTY: fortress space = cap - living - undead - dead; Vei ships into space only.
##   - k_clear: garrisons clear corpses off the board (denies Relish material).
##   - vei_pool_cap: Vei converts at most her pool's headroom, so nothing is discarded above it.
##   - per-fort shipping capacity: fort i receives at most S_vei · cap_i / Σcap per second; a held
##     fort's share is lost, not redistributed (MECHANICS §3.4).
##   - held forts (IDLE §3, MECHANICS §3.4): a flip starts a grace (forts[i].grace_s counts down here)
##     in which Vei ships nothing there and no wave targets it; then the fort is contested: your
##     undead there (the garrison, fed by WAR staging: a held fort always pulls WAR, MECHANICS §3.2)
##     against her living (the counter-garrison: she reships there at hold.reship_share of her
##     share, more as her odds rise, and waves surge into it), fought by the usual fort combat. The
##     fort is retaken (`fort_retaken`, cause "broken") once the garrison has sat at 0 for
##     hold.break_s (forts[i].zero_s). A step is split inside at every grace end and break, so both
##     land at their time. readout_of() and war_at() give the views' readouts (garrison_rate, fall_s,
##     margin; MECHANICS §3.5), pure.
##   - redirect: at the redirect fort (Relish) and at every simulacrum's fort, garrison kills stay
##     as corpses and corpses are raised into that fort's undead (MECHANICS §3.3, §3.6).
##   - tithe waves: from the first flip (start_tithe()), Vei warns, then surges living into one
##     fort, past its cap (MECHANICS §3.4).
##   - march-back: at every fort, living above the fort's cap march back to Vei's pool at
##     (L − cap) / tithe.march_back_s; what lands above her pool's cap is lost (pool_overflow).
##
## `step(dt, inputs)` is pure on its inputs (MECHANICS §3.1): the mint, `q` and Relish's position
## come in `inputs`; `t` holds only realm.json tunables. Inputs (a missing key means 0, "" or {}):
##   war: float            mass/s of WAR to dispatch over the forts
##   flood: float          mass/s of FLOOD, straight into vei.undead_queue
##   digest_q: float       Vei's digest cost q (floored at 1, so missing means 1)
##   tide_fort: String     the fort whose WAR dispatch weight is multiplied by tide_bias. It is
##                         where Relish stands (at the fort or in its dungeon), so a tithe wave
##                         there is halved too
##   tide_bias: float      the tide's multiplier; missing means 1 (neutral), not 0
##   redirect_fort: String the fort where Relish redirects (garrison kills stay, she raises)
##   redirect_rate: float  mass/s she raises there, bounded by the fort's dead
##   siege_block: Dictionary  fort_id -> fraction 0..1 of a tithe surge a siege cancels there (E3)

## Every realm.json key RealmSim reads, as "key" or "section.key" paths. setup() reads them once into
## the members below (no defaults in the code: the numbers live in the config alone), and
## tests/test_game_state_configs.gd asserts each one is present. `t` keeps the whole config for
## readers outside (tests); nothing changes it after setup().
const REQUIRED := ["k_kill", "k_destroy", "k_clear", "r_drain", "R_vei", "S_vei", "vei_pool_cap", "K", "covFalloff",
	"veiPolicy", "start_living_frac", "tithe.period_s", "tithe.backlog_scale", "tithe.warning_s", "tithe.surge_s",
	"tithe.surge_mult", "tithe.relish_mult", "tithe.march_back_s", "hold.reship_share", "hold.break_s",
	"hold.safe_horizon_s", "hold.probe_dt_s", "hold.probe_s"]
## A step's rates that a split step (step()) averages over its parts, weighted by time.
const _PART_FORT_RATES := ["r_in", "r_drain", "r_shipped", "r_dead_out", "r_raised", "r_staged", "r_redirected", "r_kills", "r_surge"]
const _PART_VEI_RATES := ["r_in_undead", "r_in_dead", "r_converted", "r_shipped"]
## Seconds under which a grace end or a break counts as now (no part of a step is shorter).
const _EPS_S := 1e-9

var t := {}
# ---- tunables, read once in setup() from REQUIRED (E2b T4.P: they were read per fort per step) ----
var _k_kill := 0.0
var _k_destroy := 0.0
var _k_clear := 0.0
var _r_drain := 0.0
var _R_vei := 0.0
var _S_vei := 0.0
var _pool_cap := 0.0
var _K := 0.0
var _falloff := 0.0
var _policy := ""
var _period_s := 0.0
var _backlog_scale := 0.0
var _warning_s := 0.0
var _surge_s := 0.0
var _surge_mult_t := 0.0
var _relish_mult := 0.0
var _march := 0.0  # tithe.march_back_s, kept above 0
var _reship_share := 0.0
var _break_s := 0.0
var _horizon_s := 0.0
var _probe_dt := 0.0
var _probe_s := 0.0
## _load calls a step made and skipped (a bound showed the room it computes can't cut the give), for
## tests (not saved).
var _n_load := 0
var _n_load_skipped := 0
var forts: Array = []
## Kept for the save shape: `undead` is always 0 (WAR leaves in the step it arrives); `r_out` is the
## mass/s Covington sent into the realm last step (WAR + FLOOD).
var cov := {"undead": 0.0, "r_out": 0.0}
## `r_in_undead` is everything entering the undead queue last step, per second: fort drain + FLOOD +
## WAR that fell through. `r_in_dead` is garrison kills shipped to her. `r_shipped` is all the
## living she sent, tithe surges included.
var vei := {
	"undead_queue": 0.0, "dead_queue": 0.0, "living_pool": 0.0,
	"r_in_undead": 0.0, "r_in_dead": 0.0, "r_converted": 0.0, "r_shipped": 0.0,
}
var simulacra: Array = []  # [{fort_id, charges (mass left), rate (mass/s)}]
var elapsed := 0.0
var cov_pos := Vector2.ZERO
var vei_pos := Vector2.ZERO
var cleared_total := 0.0
var raised_by_sims := 0.0
## Where last step's WAR went: "forts" (some target has living; held forts stage alongside),
## "staged" (only held forts were targets), "vei" (no target at all: Vei's undead queue).
var war_route := "forts"
var r_flood := 0.0  # mass/s of FLOOD last step
var r_war_to_vei := 0.0  # mass/s of WAR that fell through to Vei last step
var digest_q := 1.0  # the q of the last step; readout() uses it
## Living that marched back to her pool last step from above their forts' caps, mass/s (MECHANICS §3.4).
var r_marched := 0.0
## The mass that landed above her pool's cap last step and was lost: the ledger's pool_overflow.
var pool_overflow := 0.0
## Undead Vei actually took from her queue last step, per second (the readout's digestion).
var r_digested_undead := 0.0
## The most undead she could have taken last step, per second: her rate at `q` after the dead
## she took first, and her pool's headroom. -1 before the first step (readout() then falls back).
var r_cap_undead := -1.0
## Vei's tithe cycle (MECHANICS §3.4), all countdowns (RealmSim never knows the sim time):
##   started  the cycle runs (start_tithe(), at the first flip)
##   next_s   seconds until the next wave starts
##   next_id  the wave_id the next warning gets
##   warning  {} or {wave_id, fort_id, eta_s, surge}: the announced wave, as announced
##   wave     {} or {wave_id, fort_id, s_left, duration_s, mult, delivered}: the wave in progress;
##            mult is surge_mult × the counters of the last step, delivered the living mass so far
var tithe := {}
## Events since the last drain_events(), oldest first: fort_retaken {fort_id, cause}, tithe_warning
## {wave_id, fort_id, eta_s, surge}, tithe_wave {wave_id, fort_id, surge, duration_s, relish_here,
## siege_block}. No `t`: RealmSim never knows the sim time; GameState stamps it. Each carries `_at`
## while queued, the seconds into its step it happened (drain_timed() hands them over; a retake is
## at its moment, the rest at the end of the step's part that raised them).
var events: Array = []
## Step 2's conversion plan (what she could make this step before her headroom), which shipping
## drew on; step 7 can always fall back to it. Session only, rebuilt every step.
var _plan := {}
# fort_step's results for the fort it last stepped, mass this step (no allocation per fort)
var _kills := 0.0
var _destroyed := 0.0
var _drained := 0.0
var _cleared := 0.0
var _raised := 0.0
var _marched := 0.0
# seconds of this step the running wave covers (_tithe_clock, read by _wave_tail)
var _wave_run := 0.0
# the paths' scratch: undead end, mean, destroyed, drained, out time; living end, mean, out time,
# marched back; the excess over cap's end and integral (_above)
var _ue := 0.0
var _um := 0.0
var _ud := 0.0
var _ug := 0.0
var _ut := -1.0
var _le := 0.0
var _lm := 0.0
var _lt := -1.0
var _lb := 0.0
var _bx := 0.0
var _bi := 0.0
# the dispatch's scratch (step 3, read at step 2's end): per fort, WAR filled it (_filled) and the
# most Vei ships it then (_fill_cap, mass this step); the water-filling's targets at their limit and
# the WAR it left over
var _filled: Array[bool] = []
var _fill_cap: Array[float] = []
var _capped: Array[bool] = []
var _water_left := 0.0
# the last step's final dispatch: each fort's WAR weight and limit (session only; war_at() reads them)
var _disp_w: Array[float] = []
var _disp_lim: Array[float] = []


## Fort dict rates, all mass/s over the last step:
##   r_in          WAR arriving (staging included)       r_staged      WAR staged at a held fort
##   r_kills       living killed by undead (corpses stay) r_dead_out    garrison kills shipped to Vei
##   r_redirected  garrison kills kept as corpses at a redirect site (Relish's fort, a simulacrum's)
##   r_raised      corpses raised into undead there (Relish + simulacra)
##   r_drain       undead draining on to Vei              r_shipped     Vei's living arriving (surge too)
##   r_surge       the tithe surge's part of r_shipped
## The hold (saved): held (flipped and not yet retaken), grace_s (grace left; contested at 0) and
## zero_s (seconds the garrison has sat at 0 since it last wasn't, counted while contested). held_s is
## deprecated: a copy of grace_s kept for old readers, not saved.
func setup(world: Dictionary, tunables: Dictionary) -> void:
	t = tunables.duplicate(true)
	_k_kill = _tf("k_kill")
	_k_destroy = _tf("k_destroy")
	_k_clear = _tf("k_clear")
	_r_drain = _tf("r_drain")
	_R_vei = _tf("R_vei")
	_S_vei = _tf("S_vei")
	_pool_cap = _tf("vei_pool_cap")
	_K = _tf("K")
	_falloff = _tf("covFalloff")
	_policy = str(_tv("veiPolicy"))
	_period_s = _tf("tithe.period_s")
	_backlog_scale = _tf("tithe.backlog_scale")
	_warning_s = _tf("tithe.warning_s")
	_surge_s = _tf("tithe.surge_s")
	_surge_mult_t = _tf("tithe.surge_mult")
	_relish_mult = _tf("tithe.relish_mult")
	_march = maxf(1e-6, _tf("tithe.march_back_s"))
	_reship_share = maxf(0.0, _tf("hold.reship_share"))
	_break_s = maxf(0.0, _tf("hold.break_s"))
	_horizon_s = maxf(0.0, _tf("hold.safe_horizon_s"))
	_probe_dt = maxf(0.01, _tf("hold.probe_dt_s"))
	_probe_s = maxf(0.0, _tf("hold.probe_s"))
	var start_frac := _tf("start_living_frac")
	cov_pos = _vec(world.get("covington", {}).get("pos", [1780, 1270]))
	vei_pos = _vec(world.get("vei", {}).get("pos", [1024, 130]))
	forts = []
	for f in world.get("forts", []):
		var cap := float(f.get("cap", 100))
		forts.append({
			"id": f.get("id", ""), "name": f.get("name", "?"), "desc": f.get("desc", ""),
			"pos": _vec(f.get("pos", [0, 0])), "tier": int(f.get("tier", 1)), "cap": cap,
			"living": float(f.get("living", cap * start_frac)),
			"dead": float(f.get("dead", 0.0)), "undead": float(f.get("undead", 0.0)),
			"held": false, "grace_s": 0.0, "zero_s": 0.0, "held_s": 0.0,
			"r_in": 0.0, "r_drain": 0.0, "r_shipped": 0.0, "r_dead_out": 0.0, "r_raised": 0.0,
			"r_staged": 0.0, "r_redirected": 0.0, "r_kills": 0.0, "r_surge": 0.0,
		})
	tithe = _tithe_idle()


## The tunable at a REQUIRED path in `t`. A missing one is reported loudly and reads as null.
func _tv(path: String) -> Variant:
	assert(REQUIRED.has(path), "RealmSim reads %s; add it to REQUIRED" % path)
	var v: Variant = t
	for k in path.split("."):
		if not (v is Dictionary and (v as Dictionary).has(k)):
			push_error("RealmSim: realm.json %s is missing" % path)
			return null
		v = v[k]
	return v


func _tf(path: String) -> float:
	var v: Variant = _tv(path)
	return float(v) if v is float or v is int else 0.0


static func _vec(a) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


func fort_by_id(id: String) -> Dictionary:
	for f in forts:
		if f["id"] == id:
			return f
	return {}


func space(f: Dictionary) -> float:
	return maxf(0.0, f["cap"] - f["living"] - f["undead"] - f["dead"])


func node_pos(id: String) -> Vector2:
	if id == "covington":
		return cov_pos
	if id == "vei":
		return vei_pos
	var f := fort_by_id(id)
	return f.get("pos", cov_pos) if not f.is_empty() else cov_pos


## Flipped and not yet retaken (in grace or contested).
static func is_held(f: Dictionary) -> bool:
	return bool(f.get("held", false))


## Held and still in grace: Vei ships nothing there and no wave targets it.
static func in_grace(f: Dictionary) -> bool:
	return is_held(f) and float(f.get("grace_s", 0.0)) > 0.0


## Held and past its grace: the two pools contest it.
static func is_contested(f: Dictionary) -> bool:
	return is_held(f) and not (float(f.get("grace_s", 0.0)) > 0.0)


## Starts a hold on a fort with `grace` seconds of grace (0: contested at once), its garrison's zero
## clock at 0. A pending tithe warning naming it is dropped while it is in grace (no wave targets a
## fort in grace; the clock warns again for another target). False for an unknown fort.
func hold(fort_id: String, grace: float) -> bool:
	var f := fort_by_id(fort_id)
	if f.is_empty():
		return false
	f["held"] = true
	f["grace_s"] = maxf(0.0, grace) if is_finite(grace) else 0.0
	f["held_s"] = f["grace_s"]
	f["zero_s"] = 0.0
	_drop_grace_warning()
	return true


## Ends a hold without an event (tests, debug). False for an unknown fort.
func release(fort_id: String) -> bool:
	var f := fort_by_id(fort_id)
	if f.is_empty():
		return false
	f["held"] = false
	f["grace_s"] = 0.0
	f["held_s"] = 0.0
	f["zero_s"] = 0.0
	return true


## A pending warning whose fort is in grace is dropped (hold(), and each step's tithe clock for a
## save that holds one): the step's end, or its clock if the wave is due within it, warns again.
func _drop_grace_warning() -> void:
	var w: Dictionary = tithe.get("warning", {})
	if not w.is_empty() and in_grace(fort_by_id(str(w["fort_id"]))):
		tithe["warning"] = {}


## The events recorded since the last call, oldest first; the queue is emptied.
func drain_events() -> Array:
	var out: Array = []
	for e in drain_timed():
		out.append(e[1])
	return out


## drain_events() with each event's moment: [[seconds into the step that raised it, event], ...]
## (−1 for one raised outside a step). GameState stamps `t` from it.
func drain_timed() -> Array:
	var out: Array = []
	for e in events:
		var at := float(e.get("_at", -1.0))
		e.erase("_at")
		out.append([at, e])
	events = []
	return out


## Vei's odds now: backlog / (backlog + K).
func odds() -> float:
	var b: float = vei["undead_queue"]
	return b / (b + _K)


## The tithe interval when it is scheduled: period_s · (1 − backlog_scale · odds), never below 0.
func tithe_period() -> float:
	return _period_s * maxf(0.0, 1.0 - _backlog_scale * odds())


static func _tithe_idle() -> Dictionary:
	return {"started": false, "next_s": 0.0, "next_id": 1, "warning": {}, "wave": {}}


## Starts the tithe cycle (the first flip): the first wave comes one tithe_period() from now. A
## cycle that already runs is left alone.
func start_tithe() -> void:
	if not bool(tithe.get("started", false)):
		tithe["started"] = true
		tithe["next_s"] = tithe_period()


## Restores the tithe state from a save's `realm.tithe` (types coerced; unknown forts dropped):
##   - the saved shape (it has `started`) is restored as is;
##   - the E1 placeholder `{warning: {wave_id, fort_id, eta_s, surge}}` becomes a running cycle with
##     that warning, eta_s read as the time left;
##   - anything else (`{}`) starts the cycle now if a fort was ever flipped (`flipped`), else idles.
func load_tithe(d: Dictionary, flipped: bool) -> void:
	tithe = _tithe_idle()
	var w := _tithe_entry(d.get("warning", {}), ["eta_s", "surge"])
	var wv := _tithe_entry(d.get("wave", {}), ["s_left", "duration_s", "mult", "delivered"])
	tithe["warning"] = w
	tithe["wave"] = wv
	var top := 0
	for e in [w, wv]:
		if not e.is_empty():
			top = maxi(top, int(e["wave_id"]))
	if d.has("started"):
		tithe["started"] = bool(d["started"])
		tithe["next_s"] = float(d.get("next_s", 0.0)) if _num(d.get("next_s")) else 0.0
		tithe["next_id"] = maxi(int(d.get("next_id", 1)) if _num(d.get("next_id")) else 1, top + 1)
	elif not w.is_empty() or not wv.is_empty():
		tithe["started"] = true
		tithe["next_s"] = float(w["eta_s"]) if not w.is_empty() else tithe_period()
		tithe["next_id"] = top + 1
	elif flipped:
		start_tithe()


static func _num(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))


## A saved warning or wave entry with its types restored, or {} when it is not one.
func _tithe_entry(e: Variant, floats: Array) -> Dictionary:
	if not (e is Dictionary) or e.is_empty():
		return {}
	if not _num(e.get("wave_id")) or fort_by_id(str(e.get("fort_id", ""))).is_empty():
		return {}
	var out := {"wave_id": int(e["wave_id"]), "fort_id": str(e["fort_id"])}
	for k in floats:
		if not _num(e.get(k)):
			return {}
		out[k] = float(e[k])
	return out


## WAR's dispatch weight for a fort: 1/(dist/100)^covFalloff, times the tide at the tide fort.
func _war_weight(f: Dictionary, tide_fort: String, tide_bias: float) -> float:
	var d := maxf(1e-3, cov_pos.distance_to(f["pos"]) / 100.0)
	var w := 1.0 / pow(d, _falloff)
	return w * tide_bias if f["id"] == tide_fort else w


## One step of `dt` (MECHANICS §3.1). It runs as one part unless a held fort's grace ends or its
## garrison's break completes inside it: then it is split there (IDLE §4: a step never straddles
## those events), each part with every fort in one regime (in grace, contested, unheld) for all of
## it, so a grace end and a retake land at their time. A split step's rates are its parts'
## time-weighted means and its pool_overflow their sum; a step with no such event is one part, as
## before.
func step(dt: float, inputs: Dictionary) -> void:
	pool_overflow = 0.0  # per step: a step that does nothing leaves nothing to book
	if not (dt > 0.0) or not is_finite(dt):
		return
	var done := 0.0
	var parts := 0
	var acc := {}
	var lost := 0.0
	var t_out := {}  # fort_id -> [t_living_out, t_undead_out], seconds into the step, -1 if not
	while true:
		var rem := dt - done
		var h := _next_part(rem)
		var last := h >= rem - _EPS_S
		if last:
			h = rem
		_step_part(h, inputs, done)
		lost += pool_overflow
		parts += 1
		if not last or parts > 1:
			_accumulate(acc, t_out, h, done)
		done += h
		if last:
			break
	pool_overflow = lost
	if parts > 1:
		_average(acc, t_out, dt)


## The longest first part of `rem` seconds of step: up to the nearest grace end, or the moment a
## contested garrison that sits at exactly 0 completes its break (hold.break_s of zero_s). An event
## within _EPS_S of now is taken at the part's start. `rem` when none falls inside.
func _next_part(rem: float) -> float:
	var h := rem
	for f in forts:
		if not is_held(f):
			continue
		var g := float(f["grace_s"])
		if g > 0.0 and g <= _EPS_S:
			f["grace_s"] = 0.0
			f["held_s"] = 0.0
			g = 0.0
		if g > 0.0:
			h = minf(h, g)
		elif float(f["undead"]) <= 0.0:
			var c := _break_s - float(f["zero_s"])
			if c > _EPS_S:
				h = minf(h, c)
	return h


## A split step's running sums: each part's rates × its length, and the first moment living or
## undead reached 0 at each fort.
func _accumulate(acc: Dictionary, t_out: Dictionary, h: float, at: float) -> void:
	for f in forts:
		var id: String = f["id"]
		for k in _PART_FORT_RATES:
			acc[id + "." + k] = float(acc.get(id + "." + k, 0.0)) + float(f[k]) * h
		var to: Array = t_out.get(id, [-1.0, -1.0])
		for j in 2:
			var tk := float(f.get("t_living_out" if j == 0 else "t_undead_out", -1.0))
			if to[j] < 0.0 and tk >= 0.0:
				to[j] = at + tk
		t_out[id] = to
	for k in _PART_VEI_RATES:
		acc["vei." + k] = float(acc.get("vei." + k, 0.0)) + float(vei[k]) * h
	for k in ["r_war_to_vei", "r_marched", "r_digested_undead", "r_cap_undead"]:
		acc[k] = float(acc.get(k, 0.0)) + float(get(k)) * h


## A split step's rates as the time-weighted means of its parts' (see step()).
func _average(acc: Dictionary, t_out: Dictionary, dt: float) -> void:
	var inv := 1.0 / dt
	for f in forts:
		var id: String = f["id"]
		for k in _PART_FORT_RATES:
			f[k] = float(acc[id + "." + k]) * inv
		f["t_living_out"] = t_out[id][0]
		f["t_undead_out"] = t_out[id][1]
	for k in _PART_VEI_RATES:
		vei[k] = float(acc["vei." + k]) * inv
	for k in ["r_war_to_vei", "r_marched", "r_digested_undead", "r_cap_undead"]:
		set(k, float(acc[k]) * inv)


## One part of a step (step()): MECHANICS §3.1's order, every held fort in grace or contested for
## all of it. `at` is the seconds of the step before it (the moment its events carry).
func _step_part(dt: float, inputs: Dictionary, at: float) -> void:
	var war: float = maxf(0.0, float(inputs.get("war", 0.0)))
	var flood: float = maxf(0.0, float(inputs.get("flood", 0.0)))
	var q: float = maxf(1.0, float(inputs.get("digest_q", 1.0)))
	var tide_fort: String = str(inputs.get("tide_fort", ""))
	var tide_bias: float = maxf(0.0, float(inputs.get("tide_bias", 1.0)))
	var redirect_fort: String = str(inputs.get("redirect_fort", ""))
	var redirect_rate: float = maxf(0.0, float(inputs.get("redirect_rate", 0.0)))
	var siege: Variant = inputs.get("siege_block", {})
	pool_overflow = 0.0
	var ev0 := events.size()
	var inv: float = 1.0 / dt
	digest_q = q
	# the held forts, in grace or contested for this whole part (step() splits at every grace end);
	# her reship into a contested fort rises with her odds now, before this part's FLOOD
	var held := {}
	var grace := {}
	for f in forts:
		if is_held(f):
			held[f["id"]] = true
			if in_grace(f):
				grace[f["id"]] = true
		f["r_surge"] = 0.0
	var reship_k: float = _reship_share * (1.0 + _backlog_scale * odds())

	# ---- 1. The tithe clock: a wave's start, this step's surge (the warning is step 8's); a wave
	# delivers nothing into a fort in grace ----
	var surge := _tithe_clock(dt, tide_fort, siege if siege is Dictionary else {}, grace)

	# Redirect sites keep their garrison kills as corpses and raise corpses into undead: Relish's fort
	# (redirect_rate) and every live simulacrum's fort (its rate, until its charges run out). The
	# raises are a rate inside the step like WAR, Relish's first, then the simulacra in order (step 5).
	var raise_at := {}  # fort_id -> [Relish's mass/s, [[simulacrum, mass/s], ...]]
	if redirect_fort != "" and not fort_by_id(redirect_fort).is_empty():
		raise_at[redirect_fort] = [redirect_rate, []]
	for sm in simulacra:
		if float(sm["charges"]) > 0.0 and not fort_by_id(str(sm["fort_id"])).is_empty():
			var fid := str(sm["fort_id"])
			if not raise_at.has(fid):
				raise_at[fid] = [0.0, []]
			(raise_at[fid][1] as Array).append([sm, minf(float(sm["rate"]), float(sm["charges"]) * inv)])
	var want_r: Array[float] = []
	for f in forts:
		var w := 0.0
		if raise_at.has(f["id"]):
			w = float(raise_at[f["id"]][0])
			for e in raise_at[f["id"]][1]:
				w += float(e[1])
		want_r.append(w)

	# ---- 2. Vei's shipping and the surge, from her pool plus what she can make this step
	# Shipping: fort i takes at most S_vei · cap_i / Σcap per second (Σ over every fort, held
	# included) into its room over the step: cap less its load at the step's end without Vei's
	# living (_load: what its undead's path over the step leaves, with this step's WAR and raises
	# arriving), less the surge. Never below 0. A held fort's share and the unused part of a full
	# fort's share are lost, not redistributed. The surge goes first, all it wants, past the
	# shipping share, the space and the cap (the living above the cap march back in step 5). Both
	# are drawn from her pool now plus her conversion this step (M, before her headroom), so a long
	# step ships what the short ones would; conversion then refills the pool (step 7). WAR's
	# dispatch (step 3) reads the living arriving, so shipping is planned on the load before WAR
	# (`load`, the garrison's pull read from the living now), then each give is cut to the room this
	# step's WAR leaves; what that cuts stays in her pool.
	# Held forts: nothing in grace. A contested fort gets her reship, reship_k × its share (IDLE §3:
	# hold.reship_share of it, × (1 + tithe.backlog_scale · odds)), drawn from her pool pro rata with
	# the rest but, like the surge, not cut to the fort's room: a fort full of corpses, or a garrison
	# above its cap, would otherwise shut her out for good (MECHANICS §3.4).
	var raise_in: Array[float] = []
	for i in forts.size():
		var f: Dictionary = forts[i]
		raise_in.append(minf(want_r[i], float(f["dead"]) * inv))  # the raises, as far as the corpses now cover them
	var sum_cap := 0.0
	for f in forts:
		sum_cap += float(f["cap"])
	var per_cap: float = _S_vei * dt / sum_cap if sum_cap > 0.0 else 0.0
	vei["undead_queue"] += flood * dt  # FLOOD (step 4) counts toward what she can make
	_plan = _make(dt, q, INF, false)
	var avail: float = vei["living_pool"] + float(_plan["made"])
	var surge_fort := -1
	var surge_amt := 0.0
	if not surge.is_empty():
		for i in forts.size():
			if forts[i]["id"] == surge["fort_id"]:
				surge_fort = i
		if surge_fort >= 0:
			surge_amt = minf(avail, float(surge["want"]))
			avail -= surge_amt
	var gives: Array[float] = []
	var want := 0.0
	for i in forts.size():
		var f: Dictionary = forts[i]
		var g := 0.0
		if held.has(f["id"]):
			if not grace.has(f["id"]):
				g = reship_k * per_cap * float(f["cap"])
		else:
			# the load (the 1-pass _load) is read only where the room could be under the share (_load_cuts);
			# a held fort's is never needed
			var share: float = per_cap * float(f["cap"])
			var s_i: float = surge_amt if i == surge_fort else 0.0
			g = share
			if _load_cuts(f, dt, 0.0, raise_in[i], raise_at.has(f["id"]), s_i, share):
				g = minf(maxf(0.0, f["cap"] - _load(f, dt, 0.0, raise_in[i], raise_at.has(f["id"]), q, 1) - s_i), share)
		gives.append(g)
		want += g
	var scale: float = minf(1.0, avail / want) if want > 0.0 else 0.0
	var arriving: Array[float] = []
	arriving.resize(forts.size())
	for i in forts.size():
		gives[i] *= scale
		arriving[i] = gives[i] + (surge_amt if i == surge_fort else 0.0)

	# ---- 3. WAR dispatch (a rate over the step): forts with living, or living arriving, and every
	# held fort; else Vei
	var war_in := _dispatch(war, dt, held, arriving, surge_fort, tide_fort, tide_bias, want_r)
	# (step 2's end) this step's WAR takes its room: each give is cut to cap less the load with WAR
	# and the garrison's pull solved as fort_step solves it, without her living (which only adds to
	# the pull). A fort WAR filled (no living, at its fill rate: _filled) took exactly the WAR that
	# leaves room for its give, so the load doesn't cut its give (it leaves out the raise of the
	# living Vei ships in, which the fill counts); only what its undead kill does (_fill_cap).
	var given := 0.0
	for i in forts.size():
		var f: Dictionary = forts[i]
		var s_i: float = surge_amt if i == surge_fort else 0.0
		if held.has(f["id"]):
			pass  # her reship is not cut to the room (above)
		elif gives[i] > 0.0 and _filled[i]:
			gives[i] = minf(gives[i], _fill_cap[i])
		elif gives[i] > 0.0 and _load_cuts(f, dt, war_in[i], raise_in[i], raise_at.has(f["id"]), s_i, gives[i]):
			gives[i] = minf(gives[i], maxf(0.0, f["cap"] - _load(f, dt, war_in[i], raise_in[i], raise_at.has(f["id"]), q, 4) - s_i))
		arriving[i] = gives[i] + s_i
		f["r_surge"] = s_i * inv
		f["r_shipped"] = arriving[i] * inv
		given += gives[i]
	vei["living_pool"] -= given + surge_amt  # may dip below 0 until step 7's conversion refills it
	vei["r_shipped"] = (given + surge_amt) * inv
	# ---- 4. FLOOD went straight to Vei's undead queue (above)
	r_flood = flood
	cov["undead"] = 0.0
	cov["r_out"] = war + flood

	# ---- 5. Fort combat over the step, off each fort's path (MECHANICS §3.1), with the raises
	# (raise_at, above) and the march-back of living above each fort's cap ----
	var dead_to_vei := 0.0
	var drained := 0.0
	var marched := 0.0
	var u_start: Array[float] = []  # each fort's undead before its combat (the zero clock, step 9)
	u_start.resize(forts.size())
	for i in forts.size():
		var f: Dictionary = forts[i]
		var keep: bool = raise_at.has(f["id"])
		u_start[i] = maxf(0.0, float(f["undead"]))
		fort_step(f, dt, arriving[i] * inv, war_in[i], want_r[i], keep, q)
		f["r_kills"] = _kills * inv
		f["r_drain"] = _drained * inv
		drained += _drained
		marched += _marched
		cleared_total += _cleared
		if keep:
			f["r_redirected"] = _destroyed * inv
			f["r_dead_out"] = 0.0
			# the raised mass, Relish's share first, then each simulacrum's
			var left := _raised
			var mine: float = minf(left, float(raise_at[f["id"]][0]) * dt)
			left -= mine
			for e in raise_at[f["id"]][1]:
				var sm: Dictionary = e[0]
				var got: float = minf(left, float(e[1]) * dt)
				left -= got
				sm["charges"] = float(sm["charges"]) - got
				raised_by_sims += got
			f["r_raised"] = _raised * inv
		else:
			dead_to_vei += _destroyed
			f["r_redirected"] = 0.0
			f["r_dead_out"] = _destroyed * inv
			f["r_raised"] = 0.0
	vei["dead_queue"] += dead_to_vei
	vei["r_in_dead"] = dead_to_vei * inv
	vei["undead_queue"] += drained
	vei["r_in_undead"] = drained * inv + r_flood + r_war_to_vei
	# the marched-back living land in her pool after this step's shipping and before her conversion,
	# which then fills only the headroom they leave; what lands above her cap is lost (step 7)
	vei["living_pool"] += marched
	r_marched = marched * inv
	# ---- 6. Spent simulacra crumble
	var alive: Array = []
	for sm in simulacra:
		if float(sm["charges"]) > 0.01:
			alive.append(sm)
	simulacra = alive

	# ---- 7. The march-back past her pool's cap is lost (pool_overflow); then Vei converts, at most
	# her pool's headroom (which this step's shipping freed and the march-back took); dead costs 1,
	# undead q
	_convert(dt, inv, q)

	# ---- 8. The wave delivered its surge; it ends after surge_s -----
	_wave_tail(surge_amt)

	# ---- 9. The holds: grace counts down; a contested garrison's zero clock (zero_s) runs while it
	# sits at 0 (fort_step's clamped regime: the pull meets or exceeds its inflow, or nothing comes or
	# pulls at all) and restarts whenever it doesn't; break_s of it retakes the fort, at that moment
	for i in forts.size():
		var f: Dictionary = forts[i]
		if not held.has(f["id"]):
			continue
		if grace.has(f["id"]):
			var g: float = float(f["grace_s"]) - dt
			f["grace_s"] = g if g > _EPS_S else 0.0
			f["held_s"] = f["grace_s"]
			f["zero_s"] = 0.0
			continue
		var tz := float(f.get("t_undead_out", -1.0))
		var u0: float = u_start[i]
		if not (tz >= 0.0 or (u0 <= 0.0 and float(f["undead"]) <= 0.0)):
			f["zero_s"] = 0.0
			continue
		# at 0 from tz (from the start when it began there) to the part's end
		f["zero_s"] = (dt - tz) if u0 > 0.0 else float(f["zero_s"]) + dt
		if float(f["zero_s"]) >= _break_s - _EPS_S:
			_retaken(f, "broken", at + clampf(dt - (float(f["zero_s"]) - _break_s), 0.0, dt))

	# ---- 10. The next wave's warning, its target read from the forts as this part leaves them ----
	_tithe_warn()
	for k in range(ev0, events.size()):
		if not (events[k] as Dictionary).has("_at"):
			events[k]["_at"] = at + dt

	elapsed += dt


## A fort's load at the step's end without Vei's living (step 2's room): its living and corpses
## now (kills move living to corpses), plus its undead's path over the step with `w_in` mass/s of
## WAR and the raises (`raise_in` mass/s) arriving, under the drain and the garrison's pull
## k_destroy · L̄ / q, less the corpses that leave: the clearing k_clear · L̄ · dt and the raises,
## together at most the corpses there (those now, the kills of the living's path and, where
## `keep`, what the garrison destroys, which otherwise leaves for Vei). L̄ is the living's mean with
## nothing shipped in: `passes` 1 reads the pull from the living now (the predictor), 4 alternates
## the two paths as fort_step does (a predictor and two corrections, then U's path). Shipping only
## adds living, so the real pull and clearing are at least these and the real load at most this
## (at a `keep` fort, up to the drain that pull's extra kills skip). The march-back isn't
## subtracted: with nothing shipped in it only runs from living above the cap, and it never takes
## them below it, so such a fort has no room either way. Overwrites the paths' scratch.
## E2b T4.C: the clearing used to be left out ("it only frees room"), so a fort whose room came
## from its clearing took one step's clearing less at every step; at 15 s that cut Ashgate's
## shipping from 0.206 to 0.038/s for a step (midgame_2flips, t 510 s), the seed of its early fall.
func _load(f: Dictionary, dt: float, w_in: float, raise_in: float, keep: bool, q: float, passes: int) -> float:
	_n_load += 1
	var k_kill := _k_kill
	var k_dq := _k_destroy / maxf(1.0, q)
	var k_clear := _k_clear
	var r := _r_drain
	var cap := float(f["cap"])
	var tau := _march_s()
	var l0 := maxf(0.0, float(f["living"]))
	var u0 := maxf(0.0, float(f["undead"]))
	var d0 := maxf(0.0, float(f["dead"]))
	var lm := l0
	for p in passes:
		_u_path(dt, u0, w_in + raise_in, k_dq * lm, r)
		if p < passes - 1:
			_l_path(dt, l0, 0.0, k_kill * _um, cap, tau)
			lm = _lm
	var ud := _ud if keep else 0.0
	if passes <= 1:
		_l_path(dt, l0, 0.0, k_kill * _um, cap, tau)  # the clearing reads the living's mean
	var dead := d0 + maxf(0.0, l0 - _le - _lb) + ud
	var gone := minf(dead, (k_clear * _lm + raise_in) * dt)
	return l0 + d0 + _ue + ud - gone


## Whether _load(f, dt, w_in, raise_in, keep, ·, ·) could leave a room under `give` (cap − load − s_i
## < give). False when a cheap upper bound on the load already leaves `give` room: the caller then
## skips _load and keeps `give`, bit for bit (min(give, a room ≥ give) is `give`). The bound leaves
## out what only lowers the load: the garrison's pull (it only lowers U's path, which without it is
## U0 · e^(−r·dt) + (inflow / r)(1 − e^(−r·dt))) and the corpses that leave; where `keep`, what the
## garrison destroys stays as corpses, so U's end plus that is at most U0 + inflow · dt. A relative
## margin of 1e-9 covers the paths' rounding. E2b T4.P (M4).
func _load_cuts(f: Dictionary, dt: float, w_in: float, raise_in: float, keep: bool, s_i: float, give: float) -> bool:
	var l0 := maxf(0.0, float(f["living"]))
	var u0 := maxf(0.0, float(f["undead"]))
	var d0 := maxf(0.0, float(f["dead"]))
	var a := w_in + raise_in
	var u_hi := u0 + a * dt
	if _r_drain * dt > 1e-9 and not keep:
		var e := exp(-_r_drain * dt)
		u_hi = u0 * e + (a / _r_drain) * (1.0 - e)
	var hi := (l0 + d0 + u_hi) * (1.0 + 1e-9) + 1e-9
	if float(f["cap"]) - hi - s_i >= give:
		_n_load_skipped += 1
		return false
	return true


## One fort's combat over a step of `dt` (MECHANICS §3.1), exact in its pieces and mass-exact.
## Updates `f`'s living, undead and dead, its t_living_out and t_undead_out, and sets _kills,
## _destroyed, _drained, _cleared, _raised and _marched (mass this step):
## - living gets `s_in` mass/s (Vei's shipping and a surge) and loses k_kill · U to the undead and,
##   above the fort's cap, (L − cap) / tithe.march_back_s marching back to Vei (_marched);
## - undead get `w_in` mass/s (WAR) plus the raises, and lose r_drain · U to the drain and
##   k_destroy · L / q to the garrison;
## - corpses get the kills (and, where `keep`, the garrison's kills too), lose k_clear · ∫L to
##   clearing and the raises (`raise_want` mass/s, as far as the corpses cover them).
## Each pool stops at 0: living pinned at 0 has every arrival killed at once, undead pinned at 0
## have every arrival destroyed at once.
## - U is held at its mean over the step for the kills, so living's path is linear below the cap
##   (it reaches 0 at t* = L0 / (k_kill · Ū − s_in) and stays there; kills then equal the inflow)
##   and exponential above it (_l_path).
## - U's own path is exact for its linear ODE under the garrison's mean pull k_destroy · L̄ / q,
##   including the moment it reaches 0. Ū and L̄ come from alternating the two paths (a predictor
##   from L0, then two corrections).
## t_living_out / t_undead_out: seconds into the step when that pool reached 0 (0 when it started
## there), −1 when it did not. Natural event boundaries (IDLE §4); read by nothing yet.
func fort_step(f: Dictionary, dt: float, s_in: float, w_in: float, raise_want: float, keep: bool, q: float) -> void:
	var k_kill := _k_kill
	var k_dq := _k_destroy / maxf(1.0, q)
	var k_clear := _k_clear
	var r := _r_drain
	var cap := float(f["cap"])
	var tau := _march_s()
	var l0 := maxf(0.0, float(f["living"]))
	var u0 := maxf(0.0, float(f["undead"]))
	var d0 := maxf(0.0, float(f["dead"]))
	var raise_r := raise_want
	_u_path(dt, u0, w_in + raise_r, k_dq * l0, r)
	_l_path(dt, l0, s_in, k_kill * _um, cap, tau)
	for _pass in 2:
		_u_path(dt, u0, w_in + raise_r, k_dq * _lm, r)
		_l_path(dt, l0, s_in, k_kill * _um, cap, tau)
		if raise_want > 0.0:
			var d1 := d0 + maxf(0.0, l0 + s_in * dt - _le - _lb) + (_ud if keep else 0.0)
			raise_r = minf(raise_want, maxf(0.0, d1 - minf(d1, k_clear * _lm * dt)) / dt)
	_u_path(dt, u0, w_in + raise_r, k_dq * _lm, r)
	# what left the living: marched back (the path's own, at most all that left) and the kills (the
	# rest), so living + kills + marched is exactly what was there plus what arrived
	var marched := minf(_lb, maxf(0.0, l0 + s_in * dt - _le))
	var kills := maxf(0.0, l0 + s_in * dt - _le - marched)
	var dead := d0 + kills + (_ud if keep else 0.0)
	var cleared := minf(dead, k_clear * _lm * dt)
	var raised := raise_r * dt
	var short := raised - (dead - cleared)
	if short > 0.0:
		# the last correction left the corpses a hair short of the raises U already took in: take it
		# back out of U (what stays, then what drained, then, where the garrison's kills go to Vei,
		# what it destroyed); if U can't give it back, raise nothing this step
		var back := minf(short, _ue)
		_ue -= back
		var rest := short - back
		var g := minf(rest, _ug)
		_ug -= g
		rest -= g
		if rest > 0.0 and not keep:
			var dd := minf(rest, _ud)
			_ud -= dd
			rest -= dd
		if rest > 1e-12:
			raise_r = 0.0
			_u_path(dt, u0, w_in, k_dq * _lm, r)
			dead = d0 + kills + (_ud if keep else 0.0)
			cleared = minf(dead, k_clear * _lm * dt)
			raised = 0.0
		else:
			raised = dead - cleared
	f["living"] = _le
	f["undead"] = _ue
	f["dead"] = maxf(0.0, dead - cleared - raised)
	f["t_living_out"] = _lt
	f["t_undead_out"] = _ut
	_kills = kills
	_destroyed = _ud
	_drained = _ug
	_cleared = cleared
	_raised = raised
	_marched = marched


## tithe.march_back_s, the march-back's time constant τ (MECHANICS §3.4); kept above 0.
func _march_s() -> float:
	return _march


## Living over a step (MECHANICS §3.1 step 5, §3.4): L' = c − max(0, L − cap) / tau with
## c = s_in − kill (kill = k_kill · Ū, constant), stopping at 0. At or below the cap the path is
## linear: it reaches 0 at L / −c or rises through the cap at (cap − L) / c. Above it the excess
## x = L − cap relaxes toward c · tau with time constant tau, falling back to the cap at
## tau · ln(1 + x / (−c · tau)) when c < 0 (_above). Sets _le (end), _lm (mean), _lb (the mass that
## marched back, ∫x dt / tau) and _lt (when it reached 0, −1 if it did not).
func _l_path(dt: float, l0: float, s_in: float, kill: float, cap: float, tau: float) -> void:
	var c := s_in - kill
	_lb = 0.0
	if l0 <= cap and not (c > 0.0 and l0 + c * dt > cap):
		# never above the cap: the linear path alone
		if c >= 0.0 or l0 + c * dt > 0.0:
			_le = maxf(0.0, l0 + c * dt)
			_lm = l0 + 0.5 * c * dt
			_lt = -1.0
			return
		var ts := l0 / -c  # ≤ dt
		_le = 0.0
		_lm = 0.5 * l0 * ts / dt
		_lt = ts
		return
	_lt = -1.0
	var l := l0
	var used := 0.0  # seconds of the step done
	var area := 0.0  # ∫L over them
	if l > cap:
		used = _above(dt, l - cap, c, tau)
		area = cap * used + _bi
		_lb = _bi / tau
		l = cap + _bx
	if used < dt:
		var rem := dt - used
		if c > 0.0 and l + c * rem > cap:
			# rises through the cap, then the excess grows toward c · tau
			var tu := maxf(0.0, (cap - l) / c)
			area += l * tu + 0.5 * c * tu * tu
			var tb := _above(rem - tu, 0.0, c, tau)
			area += cap * tb + _bi
			_lb += _bi / tau
			l = cap + _bx
		elif c >= 0.0 or l + c * rem > 0.0:
			area += l * rem + 0.5 * c * rem * rem
			l = maxf(0.0, l + c * rem)
		else:
			var ts := l / -c  # ≤ rem
			area += 0.5 * l * ts
			_lt = used + ts
			l = 0.0
	_le = l
	_lm = area / dt


## The excess over the cap, x' = c − x / tau from x0 ≥ 0 for at most `span` seconds:
## x = c·tau + (x0 − c·tau) · e^(−t/tau). Returns how long x stays above 0 (`span`, or when c < 0 the
## moment tau · ln(1 + x0 / (−c·tau)) it falls back to 0 if that is sooner) and sets _bx (x then, 0
## if it fell back) and _bi (∫x over it). With u = t / tau: ∫x = tau · (c·tau · (u − g) + x0 · g),
## g = 1 − e^(−u); both small-u forms are series, so a short step loses no digits.
func _above(span: float, x0: float, c: float, tau: float) -> float:
	var xs := c * tau
	var tb := span
	if xs < 0.0:
		var z := x0 / -xs
		var td := tau * (z * (1.0 - z * (0.5 - z / 3.0)) if z < 1e-4 else log(1.0 + z))
		if td < span:
			tb = td
	var u := tb / tau
	var g := 0.0  # 1 − e^(−u)
	var h := 0.0  # u − g
	if u < 1e-3:
		g = u * (1.0 - u * (0.5 - u * (1.0 / 6.0 - u / 24.0)))
		h = u * u * (0.5 - u * (1.0 / 6.0 - u * (1.0 / 24.0 - u / 120.0)))
	else:
		g = 1.0 - exp(-u)
		h = u - g
	_bi = maxf(0.0, tau * (xs * h + x0 * g))
	_bx = maxf(0.0, x0 * (1.0 - g) + xs * g) if tb >= span else 0.0
	return tb


## Undead over a step: U' = w_in − pull − r · U while U > 0 (pull = the garrison's k_destroy · L̄ / q);
## at 0 with pull ≥ w_in every arrival is destroyed at once. Exact. Sets _ue (end), _um (mean), _ud
## (destroyed), _ug (drained) and _ut (when it reached 0, −1 if it did not), with
## u0 + w_in · dt = _ue + _ud + _ug.
func _u_path(dt: float, u0: float, w_in: float, pull: float, r: float) -> void:
	var a := w_in - pull
	var span := dt  # how long U stays above 0
	var integral := 0.0  # ∫U over [0, span]
	var end := 0.0
	if r * dt > 1e-9:
		var ss := a / r
		if ss < 0.0 and u0 <= 0.0:
			span = 0.0
		elif ss < 0.0:
			var tz := log((u0 - ss) / -ss) / r
			if tz < dt:
				span = tz
		var e := exp(-r * span)
		integral = ss * span + (u0 - ss) * (1.0 - e) / r
		end = (ss + (u0 - ss) * e) if span >= dt else 0.0
	else:
		# no drain (r = 0): linear
		if a < 0.0 and u0 + a * dt <= 0.0:
			span = u0 / -a if u0 > 0.0 else 0.0
		integral = u0 * span + 0.5 * a * span * span
		end = maxf(0.0, u0 + a * dt) if span >= dt else 0.0
	_ut = span if span < dt else -1.0
	_ue = maxf(0.0, end)
	_um = maxf(0.0, integral) / dt
	var total := u0 + w_in * dt
	_ug = maxf(0.0, minf(r * maxf(0.0, integral), total - _ue))
	_ud = maxf(0.0, total - _ue - _ug)


## A hold ends, `at` seconds into the step (IDLE I6): the event, the fort's yield refreshes (MECHANICS
## §5.3), and a simulacrum planted there is lost. GameState sends a siege big undead there home.
## TODO(E3): cmd_deploy_simulacrum is still a stub, so only a save or a test plants a simulacrum today;
## when E3 deploys them this is their loss at a retake.
func _retaken(f: Dictionary, cause: String, at: float) -> void:
	f["held"] = false
	f["grace_s"] = 0.0
	f["held_s"] = 0.0
	f["zero_s"] = 0.0
	f["clears_since_retaken"] = 0
	var alive: Array = []
	for sm in simulacra:
		if str(sm.get("fort_id", "")) != str(f["id"]):
			alive.append(sm)
	simulacra = alive
	events.append({"type": "fort_retaken", "fort_id": f["id"], "cause": cause, "_at": at})


## The raises at a fort without living over a step, mass/s: `want` (Relish's and the simulacra's,
## raise_at) as far as its corpses cover it, those now plus `shipped` (Vei's living, killed on
## arrival). 0 where nobody raises.
static func _raise_rate(f: Dictionary, dt: float, want: float, shipped: float) -> float:
	if not (want > 0.0):
		return 0.0
	return minf(want, (maxf(0.0, float(f["dead"])) + shipped) / dt)


## What flows into the undead of a fort without living (WAR plus the raises `rho`, mass/s) to bring
## it to full by the step's end, before the floor at 0: undead drain while they arrive, so
## U_end = U0 · e^(−r·dt) + (inflow / r)(1 − e^(−r·dt)) is set to cap − the corpses at the end,
## D − rho · dt + what Vei ships in (killed on arrival, it ends as corpses).
func _fill_inflow(f: Dictionary, dt: float, shipped: float, rho: float) -> float:
	var r := _r_drain
	var target: float = float(f["cap"]) - (float(f["dead"]) - rho * dt) - shipped
	if r * dt <= 1e-9:
		return (target - float(f["undead"])) / dt
	var e := exp(-r * dt)
	return r * (target - float(f["undead"]) * e) / (1.0 - e)


## The WAR rate (mass/s) that brings a fort without living to full by the step's end, with `rho`
## mass/s raised into its undead (_fill_inflow less the raises). Never below 0. E2b T4.C (M1): the
## raises used to be left out, so at a fort where Relish raises the step ended short of the cap by
## rho · (dt − (1 − e^(−r·dt)) / r) and that WAR went elsewhere (1.05 of Ashgate's 80 at 15 s with
## Relish there in pre_vei, 0.002 at 0.5 s; 20 at 15 s with rho at her 4/s).
func _fill_rate(f: Dictionary, dt: float, shipped: float, rho: float) -> float:
	return maxf(0.0, _fill_inflow(f, dt, shipped, rho) - rho)


## Step 3. `war` is WAR mass/s this step. The forts with living (or living arriving this step: Vei's
## shipping or a surge) and every held fort (as staging) take it by weight, a fort counted once
## however many reasons it has. A fort whose only living is Vei's shipping (no living now, no
## surge, not held) takes at most what fills it by the step's end (_fill_rate, with the raises
## `want_r` there): WAR it can't take goes to the other targets by weight, and to Vei's undead
## queue when every target is full or there is none. That is the continuous version of a full fort
## flickering in and out of the targets as its drain opens room, so the split doesn't depend on the
## step. Sets each fort's r_in (staging included) and r_staged, r_war_to_vei and war_route, and
## _filled and _fill_cap (step 2's end reads them); returns each fort's WAR rate.
##
## A fort WAR fills (it takes its fill rate) takes from Vei only the living its undead kill over
## the step (_fill_cap), and WAR fills the room the rest would have taken. More would leave it a
## sliver of living, and a fort with living takes its whole weight's share with no limit, so the
## next step would pour that share into it (E2b T4.C: pre_vei with no haulers, every fort full of
## corpses, Vei's drain-room shipping outran the few undead's kills, since r_drain > k_kill, and a
## fort with 0.04 living took all 32.7/s of WAR for a whole step, a burst that scaled with dt; the
## forts' undead didn't converge: 56% between 0.25 and 0.5 s). With WAR to spare that is what the
## rules do in continuous time: the moment living appear the WAR pours in, the room closes and
## they die, so the fort stays at 0 living and full, its kills taking Vei's living. A fort WAR
## doesn't fill (too little WAR) keeps her living, as before; whether it fills is judged on the give
## cut to the kills (below).
func _dispatch(war: float, dt: float, held: Dictionary, arriving: Array[float], surge_fort: int,
		tide_fort: String, tide_bias: float, want_r: Array[float]) -> Array[float]:
	var n := forts.size()
	var weights: Array[float] = []
	var limits: Array[float] = []
	var any_target := false
	var any_living := false
	for i in n:
		var f: Dictionary = forts[i]
		var live: bool = f["living"] > 0.0 or arriving[i] > 0.0
		var w := _war_weight(f, tide_fort, tide_bias) if live or held.has(f["id"]) else 0.0
		var lim := INF
		if w > 0.0 and not held.has(f["id"]) and not (f["living"] > 0.0) and i != surge_fort:
			lim = _fill_rate(f, dt, arriving[i], _raise_rate(f, dt, want_r[i], arriving[i]))
		any_target = any_target or w > 0.0
		any_living = any_living or (live and w > 0.0)
		weights.append(w)
		limits.append(lim)
		f["r_in"] = 0.0
		f["r_staged"] = 0.0
	var rates := _water(war, weights, limits)
	# a filled fort whose undead can't kill what Vei ships in takes only what they kill: K, from U's
	# path under the least inflow any smaller give leaves it (with no living there is no pull), so
	# the give, cut to K, is killed whole. Its fill then rises and the second water-filling re-splits.
	# Raising a limit only lowers the others' shares, so no fort fills that didn't, but one can stop
	# filling: this fort, when its share lies between its old limit and its new one, or another whose
	# share fell. That fort isn't _filled: it takes her give into the room its WAR leaves (the load
	# cut) and gathers living, as one with too little WAR does. Over 12 h from the three starts at 0.5,
	# 10 and 15 s it happened once (another fort, pre_vei at 15 s), and that fort ended with no living
	_fill_cap = []
	_fill_cap.resize(n)
	_fill_cap.fill(INF)
	var k_kill := _k_kill
	var r := _r_drain
	var slid := false
	for i in n:
		if not (limits[i] < INF and _capped[i] and arriving[i] > 0.0):
			continue
		var f: Dictionary = forts[i]
		var s0: float = arriving[i]
		var least := maxf(_raise_rate(f, dt, want_r[i], 0.0), _fill_inflow(f, dt, s0, _raise_rate(f, dt, want_r[i], s0)))
		_u_path(dt, maxf(0.0, float(f["undead"])), maxf(0.0, least), 0.0, r)
		var kill := k_kill * _um * dt * (1.0 - 1e-9)
		if kill < s0:
			_fill_cap[i] = kill
			limits[i] = _fill_rate(f, dt, kill, _raise_rate(f, dt, want_r[i], kill))
			slid = true
	if slid:
		rates = _water(war, weights, limits)
	_filled = []
	_filled.resize(n)
	for i in n:
		_filled[i] = limits[i] < INF and _capped[i]
	_disp_w = weights.duplicate()
	_disp_lim = limits.duplicate()
	var left := _water_left
	for i in n:
		forts[i]["r_in"] = rates[i]
		if held.has(forts[i]["id"]):
			forts[i]["r_staged"] = rates[i]
	war_route = ("forts" if any_living else "staged") if any_target else "vei"
	vei["undead_queue"] += left * dt
	r_war_to_vei = left
	return rates


## Water-filling: each target (weight > 0) takes its weight's share of `war` mass/s, at most its
## limit; what a target over its limit can't take is re-split by weight over the rest. Returns the
## rates; sets _capped (the target took its limit) and _water_left (what no target took).
func _water(war: float, weights: Array[float], limits: Array[float]) -> Array[float]:
	_capped = []
	var out := _water_into(war, weights, limits, _capped)
	_water_left = out[1]
	return out[0]


## _water's body, pure: [rates, what no target took]; `capped` is filled with which targets took their
## limit.
static func _water_into(war: float, weights: Array[float], limits: Array[float], capped_out: Array[bool]) -> Array:
	var n := weights.size()
	var rates: Array[float] = []
	rates.resize(n)
	capped_out.resize(n)
	capped_out.fill(false)
	var left := war
	var open := weights.duplicate()
	for _pass in n + 1:
		var total := 0.0
		for i in n:
			total += open[i]
		if total <= 0.0 or left <= 0.0:
			break
		var capped := false
		for i in n:
			if open[i] > 0.0 and left * open[i] / total > limits[i] - rates[i]:
				var take: float = maxf(0.0, limits[i] - rates[i])
				rates[i] += take
				left -= take
				open[i] = 0.0
				capped_out[i] = true
				capped = true
		if capped:
			continue
		for i in n:
			if open[i] > 0.0:
				rates[i] += left * open[i] / total
		left = 0.0
	return [rates, maxf(0.0, left)]


## What Vei converts from her queues in `dt`: up to R_vei · dt units, at most `headroom` mass; a
## dead costs 1 unit, an undead `q`, in veiPolicy's order. `apply` takes it off the queues.
## {made, took_u, took_d, cap_u}: cap_u is the most undead she could have taken (the readout's).
func _make(dt: float, q: float, headroom: float, apply: bool) -> Dictionary:
	var made := 0.0
	var took_u := 0.0
	var took_d := 0.0
	var cap_u := 0.0
	var uq: float = vei["undead_queue"]
	var dq: float = vei["dead_queue"]
	if headroom > 0.0:
		var cap_units: float = _R_vei * dt
		var policy: String = _policy
		if policy == "proportional":
			var tot_q: float = uq * q + dq
			var frac: float = uq * q / tot_q if tot_q > 0.0 else 1.0
			var cap_u_units: float = cap_units * frac
			if tot_q > 0.0:
				took_u = minf(uq, cap_u_units / q)
				took_d = minf(dq, cap_units - cap_u_units)
				if took_u + took_d > headroom:
					var sc: float = headroom / (took_u + took_d)
					took_u *= sc
					took_d *= sc
			cap_u = minf(cap_u_units / q, maxf(0.0, headroom - took_d))
		else:
			var order := ["dead", "undead"] if policy == "cheap" else ["undead", "dead"]
			for kind in order:
				if kind == "undead":
					cap_u = minf(cap_units / q, headroom - made)
					took_u = minf(uq, cap_u)
					cap_units -= took_u * q
					made += took_u
				else:
					took_d = minf(minf(dq, cap_units), headroom - made)
					cap_units -= took_d
					made += took_d
		made = took_u + took_d
	if apply:
		vei["undead_queue"] = uq - took_u
		vei["dead_queue"] = dq - took_d
	return {"made": made, "took_u": took_u, "took_d": took_d, "cap_u": maxf(0.0, cap_u)}


## Step 7. What the march-back (step 5's end) took past her pool's cap is lost: pool_overflow, the
## ledger's sink. Then Vei converts into her pool, at most its headroom now (this step's shipping
## freed it, the march-back took it). Records r_converted, r_digested_undead and r_cap_undead.
## Shipping drew on step 2's plan
## (`_plan`), which is still in her queues (they only grew since), so she can always cover it; a
## policy that would now pick less mass (undead first at q > 1) takes that plan instead, scaled to
## the headroom.
func _convert(dt: float, inv: float, q: float) -> void:
	var pool_cap := _pool_cap
	pool_overflow = maxf(0.0, vei["living_pool"] - pool_cap)  # the march-back that found no room
	vei["living_pool"] -= pool_overflow
	var headroom: float = pool_cap - vei["living_pool"]
	var m := _make(dt, q, headroom, false)
	if vei["living_pool"] + float(m["made"]) < 0.0 and float(_plan.get("made", 0.0)) > float(m["made"]):
		var sc: float = minf(1.0, headroom / float(_plan["made"]))
		m = {"made": float(_plan["made"]) * sc, "took_u": float(_plan["took_u"]) * sc,
			"took_d": float(_plan["took_d"]) * sc, "cap_u": m["cap_u"]}
	vei["undead_queue"] = float(vei["undead_queue"]) - float(m["took_u"])
	vei["dead_queue"] = float(vei["dead_queue"]) - float(m["took_d"])
	vei["living_pool"] = maxf(0.0, vei["living_pool"] + float(m["made"]))
	vei["r_converted"] = float(m["made"]) * inv
	r_digested_undead = float(m["took_u"]) * inv
	r_cap_undead = float(m["cap_u"]) * inv


## Step 1. The clock counts down once started; at 0 the wave starts and the next is scheduled one
## tithe_period() on (start to start). The warning (`warning_s` before) is made at the step's end,
## after dispatch (_tithe_warn), unless a single step crosses both points: then it is made here.
## A wave starts at its exact time inside the step: it covers the step's last −next_s seconds (none
## when the step ends exactly at its start), and at most its s_left, so its end is exact too
## (_wave_run, which _wave_tail counts down). Returns this step's surge, {fort_id, want} (want:
## surge_mult · S_vei · counters living/s over _wave_run, before her pool limits it), or {} with no
## wave running in this step. No wave targets a fort in grace (`grace`, this part's): a warning
## naming one (the fort flipped after it, or a save) is dropped and made again for another target,
## and a running wave delivers nothing there while the grace lasts (it still counts down).
func _tithe_clock(dt: float, relish_fort: String, siege: Dictionary, grace: Dictionary = {}) -> Dictionary:
	_wave_run = 0.0
	if not bool(tithe.get("started", false)):
		_wave_run = dt  # (a saved wave with the clock stopped counts down as before)
		return {}
	_drop_grace_warning()
	tithe["next_s"] = float(tithe["next_s"]) - dt
	var w: Dictionary = tithe["warning"]
	if w.is_empty() and tithe["next_s"] <= 0.0:
		_tithe_warn()
		w = tithe["warning"]
	var from := 0.0  # seconds into this step the running wave began (0 when it was already running)
	if tithe["next_s"] <= 0.0:
		if not w.is_empty():
			from = clampf(dt + float(tithe["next_s"]), 0.0, dt)
			if not (tithe["wave"] as Dictionary).is_empty():
				_end_wave()  # only when a period is shorter than a wave
			var fid: String = w["fort_id"]
			var block := _siege_at(siege, fid)
			var duration := _surge_s
			var mult := _surge_mult(fid, relish_fort, block)
			tithe["wave"] = {"wave_id": w["wave_id"], "fort_id": fid, "s_left": duration, "duration_s": duration,
				"mult": mult, "delivered": 0.0}
			tithe["warning"] = {}
			events.append({"type": "tithe_wave", "wave_id": w["wave_id"], "fort_id": fid,
				"surge": mult * _S_vei, "duration_s": duration,
				"relish_here": relish_fort == fid, "siege_block": block})
		tithe["next_s"] = float(tithe["next_s"]) + tithe_period()
	var wv: Dictionary = tithe["wave"]
	if wv.is_empty():
		return {}
	_wave_run = clampf(minf(dt - from, float(wv["s_left"])), 0.0, dt)
	if _wave_run <= 0.0 or fort_by_id(wv["fort_id"]).is_empty() or grace.has(wv["fort_id"]):
		return {}
	var mult := _surge_mult(wv["fort_id"], relish_fort, _siege_at(siege, wv["fort_id"]))
	wv["mult"] = mult
	return {"fort_id": wv["fort_id"], "want": mult * _S_vei * _wave_run}


## The warning, once the clock is within `warning_s` of the wave: the target (_tithe_target, which
## reads this step's WAR) is chosen and announced. Called at the step's end (step 8), after dispatch.
func _tithe_warn() -> void:
	if not bool(tithe.get("started", false)) or not (tithe["warning"] as Dictionary).is_empty():
		return
	if float(tithe["next_s"]) > _warning_s:
		return
	var target := _tithe_target()
	if target == "":
		return
	var base: float = _surge_mult_t * _S_vei
	var w := {"wave_id": int(tithe["next_id"]), "fort_id": target, "eta_s": maxf(0.0, tithe["next_s"]), "surge": base}
	tithe["warning"] = w
	tithe["next_id"] = int(tithe["next_id"]) + 1
	events.append({"type": "tithe_warning", "wave_id": w["wave_id"], "fort_id": target, "eta_s": w["eta_s"], "surge": base})


## Step 8. The running wave books what it delivered this step and counts down the part of the step
## it covered (_wave_run); after surge_s it ends.
func _wave_tail(amount: float) -> void:
	var wv: Dictionary = tithe.get("wave", {})
	if wv.is_empty():
		return
	wv["delivered"] = float(wv["delivered"]) + amount
	wv["s_left"] = float(wv["s_left"]) - _wave_run
	if wv["s_left"] <= 1e-9:
		_end_wave()


static func _siege_at(siege: Dictionary, fort_id: String) -> float:
	var v: Variant = siege.get(fort_id, 0.0)
	return clampf(float(v), 0.0, 1.0) if _num(v) else 0.0


## surge_mult × the counters: × tithe.relish_mult (halved) where Relish stands, less the siege's share.
func _surge_mult(fort_id: String, relish_fort: String, block: float) -> float:
	var m := _surge_mult_t * (1.0 - block)
	return m * _relish_mult if relish_fort == fort_id else m


## The wave ends. (E2a retook a held fort whose undead were fewer than the living it delivered; from
## E2b-2 the wave surges into her counter-garrison and the contest decides, MECHANICS §3.4.)
func _end_wave() -> void:
	tithe["wave"] = {}


## The next wave's target: the contested fort (held, past its grace) with the most undead, else the
## fort not in grace receiving the most WAR now (this step's r_in); ties go to the first in world
## order. "" only when every fort is in grace (or there are none).
func _tithe_target() -> String:
	var best := {}
	for f in forts:
		if is_contested(f) and (best.is_empty() or f["undead"] > best["undead"]):
			best = f
	if best.is_empty():
		for f in forts:
			if not in_grace(f) and (best.is_empty() or f["r_in"] > best["r_in"]):
				best = f
	return str(best.get("id", ""))


## ---- The held forts' readouts (MECHANICS §3.5): pure on the state, read by view_fort and
## view_projection --------------------------------------------------------------------------------

## Her reship into a contested fort now, mass/s, before her pool limits it (step 2): reship_share ×
## (1 + backlog_scale · odds now) × S_vei · cap / Σcap.
func reship_rate(f: Dictionary) -> float:
	var sum_cap := 0.0
	for g in forts:
		sum_cap += float(g["cap"])
	if not (sum_cap > 0.0):
		return 0.0
	return _reship_share * (1.0 + _backlog_scale * odds()) * _S_vei * float(f["cap"]) / sum_cap


## WAR's split at `war` mass/s over the last step's targets, with the weights and limits its dispatch
## ended with (_disp_w, _disp_lim): [each fort's mass/s, what falls through to Vei]. Pure. At the last
## step's WAR it is that step's r_in and r_war_to_vei, bit for bit. Before any step (after a load) no
## fort is a target yet: every fort 0 and all of it falls through.
func war_at(war: float) -> Array:
	if _disp_w.size() != forts.size():
		var z: Array[float] = []
		z.resize(forts.size())
		return [z, maxf(0.0, war)]
	var capped: Array[bool] = []
	return _water_into(maxf(0.0, war), _disp_w, _disp_lim, capped)


## A held fort's readouts (MECHANICS §3.5) with `w_in` mass/s of WAR to it, Relish's position there
## (`redirect`: she raises at up to `raise_max`; `tide`: a wave there is × tithe.relish_mult), the
## siege's `block` there and digest cost `q`: {garrison_rate, fall_s, margin, margin_cause}.
## - The support A = w_in + her sustained raise (her reship, killed on landing, is all the corpses a
##   supported fort makes: min(raise_max, S) where she redirects).
## - garrison_rate = A − min(r_drain · S / k_kill, k_destroy · (cap + τ · S) / q): the support against
##   the cheaper of the two ways to hold, keeping a garrison that kills her reship as it lands (its
##   drain) or outlasting her living at their most (their pull, with no kills: the march-back's
##   level). ≥ 0: it holds without waves; < 0: it falls.
## - fall_s = grace left + garrison / −rate + break_s while the rate is < 0, else −1.
## - margin: "will_fall" (cause "fall") when 0 ≤ fall_s ≤ safe_horizon_s; else "thin" (cause "wave")
##   when it falls beyond the horizon or one full wave breaks it (_wave_breaks); else "safe". "" when
##   not held.
func readout_of(f: Dictionary, w_in: float, redirect: bool, raise_max: float, tide: bool, block: float, q: float) -> Dictionary:
	if not is_held(f):
		return {"garrison_rate": 0.0, "fall_s": -1.0, "margin": "", "margin_cause": ""}
	var s := reship_rate(f)
	var qq := maxf(1.0, q)
	var a := maxf(0.0, w_in) + (minf(maxf(0.0, raise_max), s) if redirect else 0.0)
	var hold_off := _r_drain * s / _k_kill if _k_kill > 0.0 else INF
	var rate := garrison_rate_of(f, w_in, redirect, raise_max, q)
	var g := maxf(0.0, float(f["undead"]))
	var fall := -1.0
	if rate < 0.0:
		fall = maxf(0.0, float(f.get("grace_s", 0.0))) + g / -rate + _break_s
		if not is_finite(fall):
			fall = -1.0
	var out := {"garrison_rate": rate, "fall_s": fall, "margin": "safe", "margin_cause": ""}
	if fall >= 0.0 and fall <= _horizon_s:
		out["margin"] = "will_fall"
		out["margin_cause"] = "fall"
	elif rate < 0.0 or _wave_breaks(f, a, s, w_in, redirect, raise_max, tide, block, qq, hold_off):
		out["margin"] = "thin"
		out["margin_cause"] = "wave"
	return out


## readout_of's garrison_rate alone (war_supports reads only it): A − min(r_drain · S / k_kill,
## k_destroy · (cap + τ · S) / q). 0 when not held.
func garrison_rate_of(f: Dictionary, w_in: float, redirect: bool, raise_max: float, q: float) -> float:
	if not is_held(f):
		return 0.0
	var s := reship_rate(f)
	var a := maxf(0.0, w_in) + (minf(maxf(0.0, raise_max), s) if redirect else 0.0)
	var hold_off := _r_drain * s / _k_kill if _k_kill > 0.0 else INF
	var pile := _k_destroy * (float(f["cap"]) + _march * s) / maxf(1.0, q)
	return a - minf(hold_off, pile)


## Whether one full tithe wave breaks a held fort that holds without waves (readout_of): RealmSim's
## own fort_step on a scratch copy, at hold.probe_dt_s, for at most hold.probe_s. It starts from the
## weakest state the support leaves it in: its garrison at the least of now and its settled level, her
## living at the level her reship keeps there (none where the garrison kills it as it lands; the
## stalemate's pile where it doesn't), no corpses. The wave (surge_mult · S_vei × the counters, for
## surge_s) lands at once on top of her reship; the zero clock runs as step 9 runs it, and a probe step
## ends at the break's moment as step() splits at it. Broken when the clock reaches break_s. Survived
## once the wave is over and her living can no longer pin the garrison:
## where it kills her reship as it lands, once it does (k_kill · U ≥ S) and is no longer shrinking
## (A ≥ r_drain · U + her living's pull): from then her living only fall, so their pull only eases and
## the garrison only grows; held by the stalemate, once her living are back under its pile
## (cap + τ · S), whose pull the support covers.
func _wave_breaks(f: Dictionary, a: float, s: float, w_in: float, redirect: bool, raise_max: float, tide: bool,
		block: float, q: float, hold_off: float) -> bool:
	var cap := float(f["cap"])
	var r := _r_drain
	var g := maxf(0.0, float(f["undead"]))
	var ceil_l := cap + _march * s
	var kills_on_landing := a >= hold_off
	var u0 := g
	var l0 := 0.0
	if kills_on_landing:
		if r > 0.0:
			u0 = minf(g, a / r)
	else:
		l0 = ceil_l
		var den := 1.0 - _march * _k_kill * _k_destroy / (q * r) if r > 0.0 else 0.0
		if den > 0.0:
			l0 = maxf(cap, (cap + _march * s - _march * _k_kill * a / r) / den)
		if r > 0.0:
			u0 = minf(g, maxf(0.0, (a - _k_destroy * l0 / q) / r))
	var c := _surge_mult_t * _S_vei * (1.0 - clampf(block, 0.0, 1.0)) * (_relish_mult if tide else 1.0)
	var pf := {"cap": cap, "living": l0, "undead": u0, "dead": 0.0}
	var want := maxf(0.0, raise_max) if redirect else 0.0
	var el := 0.0
	var zero := 0.0
	while el < _probe_s - _EPS_S:
		var h := minf(_probe_dt, _probe_s - el)
		var s_in := s
		if el < _surge_s - _EPS_S:
			h = minf(h, _surge_s - el)
			s_in += c
		var ub := float(pf["undead"])
		if ub <= 0.0 and _break_s - zero > _EPS_S:
			h = minf(h, _break_s - zero)  # split at the break, as step() does
		fort_step(pf, h, s_in, maxf(0.0, w_in), want, redirect, q)
		var tz := float(pf["t_undead_out"])
		if tz >= 0.0 or (ub <= 0.0 and float(pf["undead"]) <= 0.0):
			zero = (h - tz) if ub > 0.0 else zero + h
			if zero >= _break_s - _EPS_S:
				return true
		else:
			zero = 0.0
		el += h
		if el >= _surge_s - _EPS_S and float(pf["undead"]) > 0.0:
			var ue := float(pf["undead"])
			if kills_on_landing and _k_kill * ue >= s and a >= r * ue + _k_destroy * float(pf["living"]) / q:
				return false
			if not kills_on_landing and float(pf["living"]) <= ceil_l:
				return false
	return false


## The legacy macro readout. inflow = Σ fort drain + FLOOD + WAR that fell through (= last step's
## vei.r_in_undead); capacity is the most undead she could have digested last step, per second
## (r_cap_undead: her rate at the last step's q after the dead she took first, and her pool's
## headroom), or before any step her rate alone (0 with a full pool).
func readout() -> Dictionary:
	var q: float = maxf(1.0, digest_q)
	var inflow: float = vei["r_in_undead"]
	var cap_undead: float = r_cap_undead
	if cap_undead < 0.0:
		cap_undead = _R_vei / q
		if vei["living_pool"] >= _pool_cap:
			cap_undead = 0.0
	var massed: float = vei["undead_queue"]
	return {
		"inflow": inflow, "capacity": cap_undead, "differential": inflow - cap_undead,
		"massed": massed, "odds": odds(),
		"winning": inflow > cap_undead,
	}


func total_matter() -> float:
	var sum: float = cov["undead"] + vei["undead_queue"] + vei["dead_queue"] + vei["living_pool"]
	for f in forts:
		sum += f["living"] + f["dead"] + f["undead"]
	return sum
