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
##   - held forts: forts[i].held_s counts down here; expiry records `fort_retaken` in `events`.
##   - redirect: at the redirect fort (Relish) and at every simulacrum's fort, garrison kills stay
##     as corpses and corpses are raised into that fort's undead (MECHANICS §3.3, §3.6).
##
## `step(dt, inputs)` is pure on its inputs (MECHANICS §3.1): the mint, `q` and Relish's position
## come in `inputs`; `t` holds only realm.json tunables. Inputs (a missing key means 0 or ""):
##   war: float            mass/s of WAR to dispatch over the forts
##   flood: float          mass/s of FLOOD, straight into vei.undead_queue
##   digest_q: float       Vei's digest cost q (floored at 1, so missing means 1)
##   tide_fort: String     the fort whose WAR dispatch weight is multiplied by tide_bias
##   tide_bias: float      the tide's multiplier; missing means 1 (neutral), not 0
##   redirect_fort: String the fort where Relish redirects (garrison kills stay, she raises)
##   redirect_rate: float  mass/s she raises there, bounded by the fort's dead

var t := {}
var forts: Array = []
## Kept for the save shape: `undead` is always 0 (WAR leaves in the step it arrives); `r_out` is the
## mass/s Covington sent into the realm last step (WAR + FLOOD).
var cov := {"undead": 0.0, "r_out": 0.0}
## `r_in_undead` is everything entering the undead queue last step, per second: fort drain + FLOOD +
## WAR that fell through. `r_in_dead` is garrison kills shipped to her.
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
## Where last step's WAR went: "forts" (forts with living), "staged" (no living target: the held
## forts), "vei" (nothing held either: Vei's undead queue).
var war_route := "forts"
var r_flood := 0.0  # mass/s of FLOOD last step
var r_war_to_vei := 0.0  # mass/s of WAR that fell through to Vei last step
var digest_q := 1.0  # the q of the last step; readout() uses it
## Events since the last drain_events(): {type: "fort_retaken", fort_id, cause: "expired"}. No `t`:
## RealmSim never knows the sim time; GameState stamps it.
var events: Array = []


## Fort dict rates, all mass/s over the last step:
##   r_in          WAR arriving (staging included)       r_staged      WAR staged at a held fort
##   r_kills       living killed by undead (corpses stay) r_dead_out    garrison kills shipped to Vei
##   r_redirected  garrison kills kept as corpses at a redirect site (Relish's fort, a simulacrum's)
##   r_raised      corpses raised into undead there (Relish + simulacra)
##   r_drain       undead draining on to Vei              r_shipped     Vei's living arriving
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
			"r_staged": 0.0, "r_redirected": 0.0, "r_kills": 0.0,
		})


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
	var inv: float = 1.0 / dt if dt > 0.0 else 0.0
	digest_q = q
	vei["r_shipped"] = 0.0
	# who holds a fort for this whole step (expiry is applied at the end)
	var held := {}
	for f in forts:
		if is_held(f):
			held[f["id"]] = true

	# ---- 1. WAR dispatch: living forts, else staging at held forts, else Vei ---
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
	var made := 0.0
	var headroom: float = maxf(0.0, float(t.get("vei_pool_cap", 1e18)) - vei["living_pool"])
	if headroom > 0.0:
		var cap_units: float = float(t.get("R_vei", 50.0)) * dt
		var policy: String = str(t.get("veiPolicy", "cheap"))
		if policy == "proportional":
			var tot_q: float = vei["undead_queue"] * q + vei["dead_queue"]
			if tot_q > 0.0:
				var cap_u: float = cap_units * (vei["undead_queue"] * q) / tot_q
				var took_u: float = minf(vei["undead_queue"], cap_u / q)
				var took_d: float = minf(vei["dead_queue"], cap_units - cap_u)
				if took_u + took_d > headroom:
					var sc: float = headroom / (took_u + took_d)
					took_u *= sc
					took_d *= sc
				vei["undead_queue"] -= took_u
				vei["dead_queue"] -= took_d
				made = took_u + took_d
		else:
			var order := ["dead", "undead"] if policy == "cheap" else ["undead", "dead"]
			for kind in order:
				if kind == "undead":
					var take_u: float = minf(minf(vei["undead_queue"], cap_units / q), headroom - made)
					vei["undead_queue"] -= take_u
					cap_units -= take_u * q
					made += take_u
				else:
					var take_d: float = minf(minf(vei["dead_queue"], cap_units), headroom - made)
					vei["dead_queue"] -= take_d
					cap_units -= take_d
					made += take_d
		vei["living_pool"] += made
	vei["r_converted"] = made * inv

	# ---- 7. Vei ships living into fortress SPACE, capacity-limited per fort ---
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
		forts[i]["r_shipped"] = give * inv
		given += give
	vei["living_pool"] = maxf(0.0, vei["living_pool"] - given)
	vei["r_shipped"] = given * inv

	# ---- 8. Holds count down; expiry hands the fort back ---------------------
	for f in forts:
		if held.has(f["id"]):
			f["held_s"] = maxf(0.0, float(f["held_s"]) - dt)
			if f["held_s"] <= 0.0:
				events.append({"type": "fort_retaken", "fort_id": f["id"], "cause": "expired"})
		f["held"] = is_held(f)

	elapsed += dt


## Step 1. `amount` is WAR mass this step. Forts with living take it by weight; with no living
## target the held forts take it as staging (same weights); with nothing held it falls through to
## Vei's undead queue. Sets each fort's r_in (staging included) and r_staged.
func _dispatch(amount: float, inv: float, held: Dictionary, tide_fort: String, tide_bias: float) -> void:
	var live: Array[float] = []
	var stage: Array[float] = []
	var total_live := 0.0
	var total_stage := 0.0
	for f in forts:
		var w := _war_weight(f, tide_fort, tide_bias)
		var wl := w if f["living"] > 0.0 else 0.0
		var ws := w if held.has(f["id"]) else 0.0
		live.append(wl)
		stage.append(ws)
		total_live += wl
		total_stage += ws
		f["r_in"] = 0.0
		f["r_staged"] = 0.0
	r_war_to_vei = 0.0
	if total_live > 0.0:
		war_route = "forts"
		for i in forts.size():
			var share: float = amount * live[i] / total_live
			forts[i]["undead"] += share
			forts[i]["r_in"] = share * inv
	elif total_stage > 0.0:
		war_route = "staged"
		for i in forts.size():
			var share: float = amount * stage[i] / total_stage
			forts[i]["undead"] += share
			forts[i]["r_in"] = share * inv
			forts[i]["r_staged"] = share * inv
	else:
		war_route = "vei"
		vei["undead_queue"] += amount
		r_war_to_vei = amount * inv


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
## vei.r_in_undead); capacity is Vei's undead digestion at the last step's q.
func readout() -> Dictionary:
	var q: float = maxf(1.0, digest_q)
	var inflow: float = vei["r_in_undead"]
	var cap_undead: float
	var policy: String = str(t.get("veiPolicy", "cheap"))
	if policy == "threat":
		cap_undead = float(t.get("R_vei", 50.0)) / q
	elif policy == "cheap":
		cap_undead = maxf(0.0, float(t.get("R_vei", 50.0)) - vei["r_in_dead"]) / q
	else:
		var u_w: float = vei["undead_queue"] * q
		var d_w: float = vei["dead_queue"]
		var frac: float = u_w / (u_w + d_w) if (u_w + d_w) > 0.0 else 1.0
		cap_undead = float(t.get("R_vei", 50.0)) * frac / q
	if vei["living_pool"] >= float(t.get("vei_pool_cap", 1e18)):
		cap_undead = 0.0
	var massed: float = vei["undead_queue"]
	return {
		"inflow": inflow, "capacity": cap_undead, "differential": inflow - cap_undead,
		"massed": massed, "odds": massed / (massed + float(t.get("K", 12000.0))),
		"winning": inflow > cap_undead,
	}


func total_matter() -> float:
	var sum: float = cov["undead"] + vei["undead_queue"] + vei["dead_queue"] + vei["living_pool"]
	for f in forts:
		sum += f["living"] + f["dead"] + f["undead"]
	return sum
