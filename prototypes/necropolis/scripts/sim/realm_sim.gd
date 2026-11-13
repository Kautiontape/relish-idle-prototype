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
##     fort; a wave that overwhelms a held fort's garrison ends its hold (MECHANICS §3.4).
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

## A tithe surge into the fort Relish stands at is multiplied by this (MECHANICS §3.4: halved).
const RELISH_SURGE_MULT := 0.5

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
	var inv: float = 1.0 / dt if dt > 0.0 else 0.0
	digest_q = q
	vei["r_shipped"] = 0.0
	# who holds a fort for this whole step (a hold that ends this step still counts as held)
	var held := {}
	for f in forts:
		if is_held(f):
			held[f["id"]] = true

	# ---- 1. WAR dispatch: forts with living and every held fort, else Vei ------
	_dispatch(war * dt, inv, held, tide_fort, tide_bias)
	# ---- 2. FLOOD goes straight to Vei's undead queue --------------------------
	vei["undead_queue"] += flood * dt
	r_flood = flood
	cov["undead"] = 0.0
	cov["r_out"] = war + flood

	# ---- 3. Fortress combat, resolved off start-of-tick values ---------------
	# Redirect sites keep their garrison kills as corpses: Relish's fort and every live simulacrum's.
	var keeps := {}
	if redirect_fort != "":
		keeps[redirect_fort] = true
	for s in simulacra:
		if float(s["charges"]) > 0.0:
			keeps[str(s["fort_id"])] = true
	var dead_to_vei := 0.0
	for f in forts:
		var L0: float = f["living"]
		var U0: float = f["undead"]
		# undead grind living into corpses that STAY HERE
		var killed: float = minf(L0, float(t.get("k_kill", 0.018)) * U0 * dt)
		f["living"] -= killed
		f["dead"] += killed
		f["r_kills"] = killed * inv
		# garrison destroys undead; those corpses are SHIPPED TO VEI, unless redirected
		var destroyed: float = minf(f["undead"], float(t.get("k_destroy", 0.006)) * L0 * dt / q)
		f["undead"] -= destroyed
		if keeps.has(f["id"]):
			f["dead"] += destroyed
			f["r_redirected"] = destroyed * inv
			f["r_dead_out"] = 0.0
		else:
			dead_to_vei += destroyed
			f["r_redirected"] = 0.0
			f["r_dead_out"] = destroyed * inv
		# garrison clears corpses off the board (extension)
		var cleared: float = minf(f["dead"], float(t.get("k_clear", 0.0)) * L0 * dt)
		f["dead"] -= cleared
		cleared_total += cleared
		f["r_raised"] = 0.0
	vei["dead_queue"] += dead_to_vei
	vei["r_in_dead"] = dead_to_vei * inv

	# ---- 4. Redirect raises: corpses into that fort's undead (Relish, then simulacra)
	if redirect_fort != "":
		var rf := fort_by_id(redirect_fort)
		if not rf.is_empty():
			var raised: float = minf(rf["dead"], redirect_rate * dt)
			rf["dead"] -= raised
			rf["undead"] += raised
			rf["r_raised"] += raised * inv
	_step_simulacra(dt, inv)

	# ---- 5. Surviving undead drain onward toward Vei -------------------------
	var drained := 0.0
	for f in forts:
		var leaving: float = f["undead"] * float(t.get("r_drain", 0.06)) * dt
		f["undead"] -= leaving
		drained += leaving
		f["r_drain"] = leaving * inv
	vei["undead_queue"] += drained
	vei["r_in_undead"] = drained * inv + r_flood + r_war_to_vei

	# ---- 6. Vei converts, at most her pool's headroom; dead costs 1, undead q
	_convert(dt, inv, q)

	# ---- 7. The tithe: its clock, the warning, the wave and its surge --------
	for f in forts:
		f["r_surge"] = 0.0
	_step_tithe(dt, inv, tide_fort, siege if siege is Dictionary else {})

	# ---- 8. Vei ships living into fortress SPACE, capacity-limited per fort ---
	# Fort i takes at most S_vei · cap_i / Σcap (Σ over every fort, held included). A held fort's
	# share and the unused part of a full fort's share are lost, not redistributed.
	var sum_cap := 0.0
	for f in forts:
		sum_cap += float(f["cap"])
	var per_cap: float = float(t.get("S_vei", 8.0)) * dt / sum_cap if sum_cap > 0.0 else 0.0
	var gives: Array[float] = []
	var want := 0.0
	for f in forts:
		var g := 0.0
		if not held.has(f["id"]):
			g = minf(space(f), per_cap * float(f["cap"]))
		gives.append(g)
		want += g
	var scale: float = minf(1.0, vei["living_pool"] / want) if want > 0.0 else 0.0
	var given := 0.0
	for i in forts.size():
		var give: float = gives[i] * scale
		forts[i]["living"] += give
		forts[i]["r_shipped"] = give * inv + float(forts[i]["r_surge"])
		given += give
	vei["living_pool"] = maxf(0.0, vei["living_pool"] - given)
	vei["r_shipped"] += given * inv

	# ---- 9. Holds count down; expiry hands the fort back ---------------------
	for f in forts:
		# a wave that ended the hold this step already recorded the retake
		if held.has(f["id"]) and is_held(f):
			f["held_s"] = maxf(0.0, float(f["held_s"]) - dt)
			if f["held_s"] <= 0.0:
				_retaken(f, "expired")
		f["held"] = is_held(f)

	elapsed += dt


## A hold ends: the event, and the fort's yield refreshes (MECHANICS §5.3).
func _retaken(f: Dictionary, cause: String) -> void:
	f["held_s"] = 0.0
	f["held"] = false
	f["clears_since_retaken"] = 0
	events.append({"type": "fort_retaken", "fort_id": f["id"], "cause": cause})


## Step 1. `amount` is WAR mass this step. The forts with living and every held fort (as staging)
## take it by weight, a fort counted once however many reasons it has; with no target at all it
## falls through to Vei's undead queue. Sets each fort's r_in (staging included) and r_staged.
func _dispatch(amount: float, inv: float, held: Dictionary, tide_fort: String, tide_bias: float) -> void:
	var weights: Array[float] = []
	var total := 0.0
	var any_living := false
	for f in forts:
		var live: bool = f["living"] > 0.0
		var w := _war_weight(f, tide_fort, tide_bias) if live or held.has(f["id"]) else 0.0
		any_living = any_living or (live and w > 0.0)
		weights.append(w)
		total += w
		f["r_in"] = 0.0
		f["r_staged"] = 0.0
	r_war_to_vei = 0.0
	if total > 0.0:
		war_route = "forts" if any_living else "staged"
		for i in forts.size():
			var share: float = amount * weights[i] / total
			forts[i]["undead"] += share
			forts[i]["r_in"] = share * inv
			if held.has(forts[i]["id"]):
				forts[i]["r_staged"] = share * inv
	else:
		war_route = "vei"
		vei["undead_queue"] += amount
		r_war_to_vei = amount * inv


## Step 6. Vei converts up to R_vei units per second into living, at most her pool's headroom;
## a dead costs 1 unit, an undead `q`. Records r_converted, r_digested_undead and r_cap_undead.
func _convert(dt: float, inv: float, q: float) -> void:
	var made := 0.0
	var took_u := 0.0
	var cap_u := 0.0
	var headroom: float = maxf(0.0, float(t.get("vei_pool_cap", 1e18)) - vei["living_pool"])
	if headroom > 0.0:
		var cap_units: float = float(t.get("R_vei", 50.0)) * dt
		var policy: String = str(t.get("veiPolicy", "cheap"))
		if policy == "proportional":
			var tot_q: float = vei["undead_queue"] * q + vei["dead_queue"]
			var frac: float = vei["undead_queue"] * q / tot_q if tot_q > 0.0 else 1.0
			var cap_u_units: float = cap_units * frac
			var took_d := 0.0
			if tot_q > 0.0:
				took_u = minf(vei["undead_queue"], cap_u_units / q)
				took_d = minf(vei["dead_queue"], cap_units - cap_u_units)
				var sc := 1.0
				if took_u + took_d > headroom:
					sc = headroom / (took_u + took_d)
					took_u *= sc
					took_d *= sc
				vei["undead_queue"] -= took_u
				vei["dead_queue"] -= took_d
				made = took_u + took_d
			cap_u = minf(cap_u_units / q, maxf(0.0, headroom - took_d))
		else:
			var order := ["dead", "undead"] if policy == "cheap" else ["undead", "dead"]
			for kind in order:
				if kind == "undead":
					cap_u = minf(cap_units / q, headroom - made)
					took_u = minf(vei["undead_queue"], cap_u)
					vei["undead_queue"] -= took_u
					cap_units -= took_u * q
					made += took_u
				else:
					var take_d: float = minf(minf(vei["dead_queue"], cap_units), headroom - made)
					vei["dead_queue"] -= take_d
					cap_units -= take_d
					made += take_d
		vei["living_pool"] += made
	vei["r_converted"] = made * inv
	r_digested_undead = took_u * inv
	r_cap_undead = maxf(0.0, cap_u) * inv


## Step 7. The clock counts down once started; `warning_s` before the wave the target is chosen and
## announced; at 0 the wave starts and the next is scheduled one tithe_period() on (start to start).
## While a wave runs it moves surge_mult · S_vei · counters living/s from her pool into its fort,
## past the shipping share and the fort's space. When it ends, a held fort whose undead are fewer
## than the living it delivered is retaken.
func _step_tithe(dt: float, inv: float, relish_fort: String, siege: Dictionary) -> void:
	if not bool(tithe.get("started", false)):
		return
	var tc := _tcfg()
	var base: float = float(tc.get("surge_mult", 3.0)) * float(t.get("S_vei", 8.0))
	tithe["next_s"] = float(tithe["next_s"]) - dt
	var w: Dictionary = tithe["warning"]
	if w.is_empty() and tithe["next_s"] <= float(tc.get("warning_s", 150.0)):
		var target := _tithe_target()
		if target != "":
			w = {"wave_id": int(tithe["next_id"]), "fort_id": target, "eta_s": maxf(0.0, tithe["next_s"]), "surge": base}
			tithe["warning"] = w
			tithe["next_id"] = int(tithe["next_id"]) + 1
			events.append({"type": "tithe_warning", "wave_id": w["wave_id"], "fort_id": target,
				"eta_s": w["eta_s"], "surge": base})
	if tithe["next_s"] <= 0.0:
		if not w.is_empty():
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
		return
	var f := fort_by_id(wv["fort_id"])
	var mult := _surge_mult(wv["fort_id"], relish_fort, _siege_at(siege, wv["fort_id"]))
	var amount: float = minf(vei["living_pool"], mult * float(t.get("S_vei", 8.0)) * minf(dt, float(wv["s_left"])))
	f["living"] += amount
	f["r_surge"] = amount * inv
	vei["living_pool"] -= amount
	vei["r_shipped"] += amount * inv
	wv["mult"] = mult
	wv["delivered"] = float(wv["delivered"]) + amount
	wv["s_left"] = float(wv["s_left"]) - dt
	if wv["s_left"] <= 1e-9:
		_end_wave()


static func _siege_at(siege: Dictionary, fort_id: String) -> float:
	var v: Variant = siege.get(fort_id, 0.0)
	return clampf(float(v), 0.0, 1.0) if _num(v) else 0.0


## surge_mult × the counters: halved where Relish stands, less the siege's share.
func _surge_mult(fort_id: String, relish_fort: String, block: float) -> float:
	var m := float(_tcfg().get("surge_mult", 3.0)) * (1.0 - block)
	return m * RELISH_SURGE_MULT if relish_fort == fort_id else m


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


## Step 4, simulacra: each raises corpses at its fort into that fort's undead at its rate, until its
## charges (mass) run out.
func _step_simulacra(dt: float, inv: float) -> void:
	var alive: Array = []
	for s in simulacra:
		var f := fort_by_id(s["fort_id"])
		if not f.is_empty():
			var raised: float = minf(f["dead"], minf(float(s["rate"]) * dt, float(s["charges"])))
			f["dead"] -= raised
			f["undead"] += raised
			f["r_raised"] += raised * inv
			raised_by_sims += raised
			s["charges"] = float(s["charges"]) - raised
		if float(s["charges"]) > 0.01:
			alive.append(s)
	simulacra = alive


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
		if vei["living_pool"] >= float(t.get("vei_pool_cap", 1e18)):
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
