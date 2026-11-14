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
##   - held forts: forts[i].held_s counts down here; expiry records `fort_retaken` in `events`. A
##     held fort always pulls WAR as staging (MECHANICS §3.2).
##   - redirect: at the redirect fort (Relish) and at every simulacrum's fort, garrison kills stay
##     as corpses and corpses are raised into that fort's undead (MECHANICS §3.3, §3.6).
##   - tithe waves: from the first flip (start_tithe()), Vei warns, then surges living into one
##     fort, past its cap; a wave that overwhelms a held fort's garrison ends its hold (MECHANICS §3.4).
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

var t := {}
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
## siege_block}. No `t`: RealmSim never knows the sim time; GameState stamps it.
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
# the dispatch's scratch (step 3, read at step 2's end): per fort, WAR filled it (_filled); the
# water-filling's targets at their limit and the WAR it left over
var _filled: Array[bool] = []
var _capped: Array[bool] = []
var _water_left := 0.0


## Fort dict rates, all mass/s over the last step:
##   r_in          WAR arriving (staging included)       r_staged      WAR staged at a held fort
##   r_kills       living killed by undead (corpses stay) r_dead_out    garrison kills shipped to Vei
##   r_redirected  garrison kills kept as corpses at a redirect site (Relish's fort, a simulacrum's)
##   r_raised      corpses raised into undead there (Relish + simulacra)
##   r_drain       undead draining on to Vei              r_shipped     Vei's living arriving (surge too)
##   r_surge       the tithe surge's part of r_shipped
## Plus held_s (seconds of hold left) and held (held_s > 0).
func setup(world: Dictionary, tunables: Dictionary) -> void:
	t = tunables.duplicate(true)
	cov_pos = _vec(world.get("covington", {}).get("pos", [1780, 1270]))
	vei_pos = _vec(world.get("vei", {}).get("pos", [1024, 130]))
	forts = []
	for f in world.get("forts", []):
		var cap := float(f.get("cap", 100))
		forts.append({
			"id": f.get("id", ""), "name": f.get("name", "?"), "desc": f.get("desc", ""),
			"pos": _vec(f.get("pos", [0, 0])), "tier": int(f.get("tier", 1)), "cap": cap,
			"living": float(f.get("living", cap * float(t.get("start_living_frac", 0.85)))),
			"dead": float(f.get("dead", 0.0)), "undead": float(f.get("undead", 0.0)),
			"held_s": 0.0, "held": false,
			"r_in": 0.0, "r_drain": 0.0, "r_shipped": 0.0, "r_dead_out": 0.0, "r_raised": 0.0,
			"r_staged": 0.0, "r_redirected": 0.0, "r_kills": 0.0, "r_surge": 0.0,
		})
	tithe = _tithe_idle()


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


static func is_held(f: Dictionary) -> bool:
	return float(f.get("held_s", 0.0)) > 0.0


## Holds a fort for `seconds` (0 releases it without an event). False for an unknown fort.
func hold(fort_id: String, seconds: float) -> bool:
	var f := fort_by_id(fort_id)
	if f.is_empty():
		return false
	f["held_s"] = maxf(0.0, seconds)
	f["held"] = f["held_s"] > 0.0
	return true


## The events recorded since the last call, oldest first; the queue is emptied.
func drain_events() -> Array:
	var out := events
	events = []
	return out


## Vei's odds now: backlog / (backlog + K).
func odds() -> float:
	var b: float = vei["undead_queue"]
	return b / (b + float(t.get("K", 12000.0)))


func _tcfg() -> Dictionary:
	var d: Variant = t.get("tithe", {})
	return d if d is Dictionary else {}


## The tithe interval when it is scheduled: period_s · (1 − backlog_scale · odds), never below 0.
func tithe_period() -> float:
	var tc := _tcfg()
	return float(tc.get("period_s", 420.0)) * maxf(0.0, 1.0 - float(tc.get("backlog_scale", 0.5)) * odds())


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
	var w := 1.0 / pow(d, float(t.get("covFalloff", 1.0)))
	return w * tide_bias if f["id"] == tide_fort else w


func step(dt: float, inputs: Dictionary) -> void:
	var war: float = maxf(0.0, float(inputs.get("war", 0.0)))
	var flood: float = maxf(0.0, float(inputs.get("flood", 0.0)))
	var q: float = maxf(1.0, float(inputs.get("digest_q", 1.0)))
	var tide_fort: String = str(inputs.get("tide_fort", ""))
	var tide_bias: float = maxf(0.0, float(inputs.get("tide_bias", 1.0)))
	var redirect_fort: String = str(inputs.get("redirect_fort", ""))
	var redirect_rate: float = maxf(0.0, float(inputs.get("redirect_rate", 0.0)))
	var siege: Variant = inputs.get("siege_block", {})
	pool_overflow = 0.0  # per step: a step that does nothing leaves nothing to book
	if not (dt > 0.0) or not is_finite(dt):
		return
	var inv: float = 1.0 / dt
	digest_q = q
	# who holds a fort for this whole step (a hold that ends this step still counts as held)
	var held := {}
	for f in forts:
		if is_held(f):
			held[f["id"]] = true
		f["r_surge"] = 0.0

	# ---- 1. The tithe clock: a wave's start, this step's surge (the warning is step 8's) ----
	var surge := _tithe_clock(dt, tide_fort, siege if siege is Dictionary else {})

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
	var load: Array[float] = []
	var raise_in: Array[float] = []
	for i in forts.size():
		var f: Dictionary = forts[i]
		raise_in.append(minf(want_r[i], float(f["dead"]) * inv))  # the raises, as far as the corpses now cover them
		load.append(_load(f, dt, 0.0, raise_in[i], raise_at.has(f["id"]), q, 1))
	var sum_cap := 0.0
	for f in forts:
		sum_cap += float(f["cap"])
	var per_cap: float = float(t.get("S_vei", 8.0)) * dt / sum_cap if sum_cap > 0.0 else 0.0
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
		if not held.has(f["id"]):
			var room: float = maxf(0.0, f["cap"] - load[i] - (surge_amt if i == surge_fort else 0.0))
			g = minf(room, per_cap * float(f["cap"]))
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
	# leaves room for its give, so its give isn't cut (the load here leaves out the raise of the
	# living Vei ships in, which the fill counts).
	var given := 0.0
	for i in forts.size():
		var f: Dictionary = forts[i]
		var s_i: float = surge_amt if i == surge_fort else 0.0
		if gives[i] > 0.0 and not _filled[i]:
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
	for i in forts.size():
		var f: Dictionary = forts[i]
		var keep: bool = raise_at.has(f["id"])
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

	# ---- 8. The wave delivered its surge; it ends after surge_s. The next wave's warning -----
	_wave_tail(surge_amt)
	_tithe_warn()

	# ---- 9. Holds count down; expiry hands the fort back ---------------------
	for f in forts:
		# a wave that ended the hold this step already recorded the retake
		if held.has(f["id"]) and is_held(f):
			f["held_s"] = maxf(0.0, float(f["held_s"]) - dt)
			if f["held_s"] <= 0.0:
				_retaken(f, "expired")
		f["held"] = is_held(f)

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
	var k_kill := float(t.get("k_kill", 0.018))
	var k_dq := float(t.get("k_destroy", 0.006)) / maxf(1.0, q)
	var k_clear := float(t.get("k_clear", 0.0))
	var r := float(t.get("r_drain", 0.06))
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
	var k_kill := float(t.get("k_kill", 0.018))
	var k_dq := float(t.get("k_destroy", 0.006)) / maxf(1.0, q)
	var k_clear := float(t.get("k_clear", 0.0))
	var r := float(t.get("r_drain", 0.06))
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
	return maxf(1e-6, float(_tcfg().get("march_back_s", 60.0)))


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


## A hold ends: the event, and the fort's yield refreshes (MECHANICS §5.3).
func _retaken(f: Dictionary, cause: String) -> void:
	f["held_s"] = 0.0
	f["held"] = false
	f["clears_since_retaken"] = 0
	events.append({"type": "fort_retaken", "fort_id": f["id"], "cause": cause})


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
	var r := float(t.get("r_drain", 0.06))
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
## _filled (step 2's end reads it); returns each fort's WAR rate.
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
	_filled = []
	_filled.resize(n)
	for i in n:
		_filled[i] = limits[i] < INF and _capped[i]
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
	var n := weights.size()
	var rates: Array[float] = []
	rates.resize(n)
	_capped = []
	_capped.resize(n)
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
				_capped[i] = true
				capped = true
		if capped:
			continue
		for i in n:
			if open[i] > 0.0:
				rates[i] += left * open[i] / total
		left = 0.0
	_water_left = maxf(0.0, left)
	return rates


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
		var cap_units: float = float(t.get("R_vei", 50.0)) * dt
		var policy: String = str(t.get("veiPolicy", "cheap"))
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
	var pool_cap := float(t.get("vei_pool_cap", 600.0))
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
## wave running in this step.
func _tithe_clock(dt: float, relish_fort: String, siege: Dictionary) -> Dictionary:
	_wave_run = 0.0
	if not bool(tithe.get("started", false)):
		_wave_run = dt  # (a saved wave with the clock stopped counts down as before)
		return {}
	var tc := _tcfg()
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
			var duration := float(tc.get("surge_s", 40.0))
			var mult := _surge_mult(fid, relish_fort, block)
			tithe["wave"] = {"wave_id": w["wave_id"], "fort_id": fid, "s_left": duration, "duration_s": duration,
				"mult": mult, "delivered": 0.0}
			tithe["warning"] = {}
			events.append({"type": "tithe_wave", "wave_id": w["wave_id"], "fort_id": fid,
				"surge": mult * float(t.get("S_vei", 8.0)), "duration_s": duration,
				"relish_here": relish_fort == fid, "siege_block": block})
		tithe["next_s"] = float(tithe["next_s"]) + tithe_period()
	var wv: Dictionary = tithe["wave"]
	if wv.is_empty():
		return {}
	_wave_run = clampf(minf(dt - from, float(wv["s_left"])), 0.0, dt)
	if _wave_run <= 0.0 or fort_by_id(wv["fort_id"]).is_empty():
		return {}
	var mult := _surge_mult(wv["fort_id"], relish_fort, _siege_at(siege, wv["fort_id"]))
	wv["mult"] = mult
	return {"fort_id": wv["fort_id"], "want": mult * float(t.get("S_vei", 8.0)) * _wave_run}


## The warning, once the clock is within `warning_s` of the wave: the target (_tithe_target, which
## reads this step's WAR) is chosen and announced. Called at the step's end (step 8), after dispatch.
func _tithe_warn() -> void:
	if not bool(tithe.get("started", false)) or not (tithe["warning"] as Dictionary).is_empty():
		return
	var tc := _tcfg()
	if float(tithe["next_s"]) > float(tc.get("warning_s", 150.0)):
		return
	var target := _tithe_target()
	if target == "":
		return
	var base: float = float(tc.get("surge_mult", 3.0)) * float(t.get("S_vei", 8.0))
	var w := {"wave_id": int(tithe["next_id"]), "fort_id": target, "eta_s": maxf(0.0, tithe["next_s"]), "surge": base}
	tithe["warning"] = w
	tithe["next_id"] = int(tithe["next_id"]) + 1
	events.append({"type": "tithe_warning", "wave_id": w["wave_id"], "fort_id": target, "eta_s": w["eta_s"], "surge": base})


## Step 8. The running wave books what it delivered this step and counts down the part of the step
## it covered (_wave_run); after surge_s it ends. When it ends, a held fort whose undead are fewer
## than the living it delivered is retaken.
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
	var m := float(_tcfg().get("surge_mult", 3.0)) * (1.0 - block)
	return m * float(_tcfg().get("relish_mult", 0.5)) if relish_fort == fort_id else m


## The wave ends: a held fort it overwhelmed (delivered > the undead there now) is retaken.
func _end_wave() -> void:
	var wv: Dictionary = tithe["wave"]
	tithe["wave"] = {}
	var f := fort_by_id(wv["fort_id"])
	if not f.is_empty() and is_held(f) and float(wv["delivered"]) > float(f["undead"]):
		_retaken(f, "tithe_wave")


## The next wave's target: the held fort with the most undead, else the fort receiving the most
## WAR now (this step's r_in); ties go to the first in world order. "" only with no forts.
func _tithe_target() -> String:
	var best := {}
	for f in forts:
		if is_held(f) and (best.is_empty() or f["undead"] > best["undead"]):
			best = f
	if best.is_empty():
		for f in forts:
			if best.is_empty() or f["r_in"] > best["r_in"]:
				best = f
	return str(best.get("id", ""))


## The legacy macro readout. inflow = Σ fort drain + FLOOD + WAR that fell through (= last step's
## vei.r_in_undead); capacity is the most undead she could have digested last step, per second
## (r_cap_undead: her rate at the last step's q after the dead she took first, and her pool's
## headroom), or before any step her rate alone (0 with a full pool).
func readout() -> Dictionary:
	var q: float = maxf(1.0, digest_q)
	var inflow: float = vei["r_in_undead"]
	var cap_undead: float = r_cap_undead
	if cap_undead < 0.0:
		cap_undead = float(t.get("R_vei", 50.0)) / q
		if vei["living_pool"] >= float(t.get("vei_pool_cap", 600.0)):
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
