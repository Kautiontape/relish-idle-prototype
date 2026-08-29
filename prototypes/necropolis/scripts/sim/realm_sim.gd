class_name RealmSim
extends RefCounted
## Port of the canonical REALM simulation (relish-realms lib/realm-sim.js) with
## necropolis extensions. Autoload-free and headless-testable: pass config dicts in.
##
## THE CRITICAL ASYMMETRY
##   UNDEAD killing LIVING  -> DEAD stays at the fortress. Relish's material.
##   LIVING destroying UNDEAD -> DEAD is shipped to Vei, who makes it LIVING again.
##
## Extensions over the JS canon (documented deviations, BRIEF §10):
##   - EMPTY: fortress space = cap - living - undead - dead; Vei ships into space only.
##   - k_clear: garrisons clear corpses off the board (denies Relish material).
##   - vei_pool_cap: Vei stops converting while her fielded-army pool is full
##     (fixes the dead-end reservoir; filling her forts stalls her digestion).
##   - simulacra: limited-charge auto-raise channels (chaff -> streams at Vei).
##   - raiding flag: while the player fights a raid, the map-level Relish channel is off.

var t := {}
var forts: Array = []
var cov := {"undead": 0.0, "r_out": 0.0}
var vei := {
	"undead_queue": 0.0, "dead_queue": 0.0, "living_pool": 0.0,
	"r_in_undead": 0.0, "r_in_dead": 0.0, "r_converted": 0.0, "r_shipped": 0.0,
}
var relish := {"at": "covington", "target": "", "state": "idle", "progress": 0.0, "travel_total": 0.0}
var simulacra: Array = []
var raiding := false
var elapsed := 0.0
var cov_pos := Vector2.ZERO
var vei_pos := Vector2.ZERO
var cleared_total := 0.0
var raised_by_sims := 0.0


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
			"r_in": 0.0, "r_drain": 0.0, "r_shipped": 0.0, "r_dead_out": 0.0, "r_raised": 0.0,
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


func step(dt: float) -> void:
	var q: float = maxf(1.0, float(t.get("q", 1.0)))
	vei["r_in_undead"] = 0.0
	vei["r_shipped"] = 0.0

	# ---- 1. Covington produces, then dispatches everything -------------------
	var prod: float = float(t.get("P_base", 0.0))
	if relish["at"] == "covington" and relish["state"] == "raising" and not raiding:
		prod += float(t.get("P_relish", 0.0))
	cov["undead"] += prod * dt
	cov["r_out"] = prod

	var weights: Array[float] = []
	var total := 0.0
	for f in forts:
		var w := 0.0
		if f["living"] > 0.0:
			w = 1.0 / pow(cov_pos.distance_to(f["pos"]) / 100.0, float(t.get("covFalloff", 1.0)))
		weights.append(w)
		total += w
	var ds: float = float(t.get("directShare", 0.22))
	var w_direct: float = total * (ds / (1.0 - ds)) if total > 0.0 else 1.0
	total += w_direct

	var dispatch: float = cov["undead"]
	cov["undead"] = 0.0
	for i in forts.size():
		var share: float = dispatch * (weights[i] / total) if total > 0.0 else 0.0
		forts[i]["undead"] += share
		forts[i]["r_in"] = share / dt if dt > 0.0 else 0.0
	var direct: float = dispatch * (w_direct / total) if total > 0.0 else dispatch
	vei["undead_queue"] += direct

	# ---- 2. Fortress combat, resolved off start-of-tick values ---------------
	var dead_to_vei := 0.0
	for f in forts:
		var L0: float = f["living"]
		var U0: float = f["undead"]

		# undead grind living into corpses that STAY HERE
		var killed: float = minf(L0, float(t.get("k_kill", 0.018)) * U0 * dt)
		f["living"] -= killed
		f["dead"] += killed

		# garrison destroys undead; those corpses are SHIPPED TO VEI
		var destroyed: float = minf(f["undead"], float(t.get("k_destroy", 0.006)) * L0 * dt / q)
		f["undead"] -= destroyed
		dead_to_vei += destroyed
		f["r_dead_out"] = destroyed / dt if dt > 0.0 else 0.0

		# garrison clears corpses off the board (extension)
		var cleared: float = minf(f["dead"], float(t.get("k_clear", 0.0)) * L0 * dt)
		f["dead"] -= cleared
		cleared_total += cleared

		# ---- 3. surviving undead drain onward toward Vei ----------------------
		var leaving: float = f["undead"] * float(t.get("r_drain", 0.06)) * dt
		f["undead"] -= leaving
		vei["undead_queue"] += leaving
		f["r_drain"] = leaving / dt if dt > 0.0 else 0.0
	vei["dead_queue"] += dead_to_vei
	vei["r_in_dead"] = dead_to_vei / dt if dt > 0.0 else 0.0

	# ---- 4. Relish channel + simulacra ---------------------------------------
	_step_relish(dt)
	_step_simulacra(dt)

	# ---- 5. Vei converts. capacity shared; dead costs 1, undead costs q ------
	var made := 0.0
	var pool_cap: float = float(t.get("vei_pool_cap", 1e18))
	if vei["living_pool"] < pool_cap:
		var cap_units: float = float(t.get("R_vei", 50.0)) * dt
		var policy: String = str(t.get("veiPolicy", "cheap"))
		if policy == "proportional":
			var tot_q: float = vei["undead_queue"] * q + vei["dead_queue"]
			if tot_q > 0.0:
				var cap_u: float = cap_units * (vei["undead_queue"] * q) / tot_q
				var took_u: float = minf(vei["undead_queue"], cap_u / q)
				var took_d: float = minf(vei["dead_queue"], cap_units - cap_u)
				vei["undead_queue"] -= took_u
				vei["dead_queue"] -= took_d
				made = took_u + took_d
		else:
			var order := ["dead", "undead"] if policy == "cheap" else ["undead", "dead"]
			for kind in order:
				if kind == "undead":
					var take_u: float = minf(vei["undead_queue"], cap_units / q)
					vei["undead_queue"] -= take_u
					cap_units -= take_u * q
					made += take_u
				else:
					var take_d: float = minf(vei["dead_queue"], cap_units)
					vei["dead_queue"] -= take_d
					cap_units -= take_d
					made += take_d
		vei["living_pool"] = minf(pool_cap, vei["living_pool"] + made)
	vei["r_converted"] = made / dt if dt > 0.0 else 0.0

	# ---- 6. Vei ships living out into fortress SPACE, neediest first ---------
	var budget: float = minf(vei["living_pool"], float(t.get("S_vei", 8.0)) * dt)
	var deficits: Array[float] = []
	var total_deficit := 0.0
	for f in forts:
		var d := space(f)
		deficits.append(d)
		total_deficit += d
	if total_deficit > 0.0 and budget > 0.0:
		for i in forts.size():
			var give: float = minf(deficits[i], budget * (deficits[i] / total_deficit))
			forts[i]["living"] += give
			forts[i]["r_shipped"] = give / dt if dt > 0.0 else 0.0
			vei["r_shipped"] += give / dt if dt > 0.0 else 0.0
			vei["living_pool"] -= give
	else:
		for f in forts:
			f["r_shipped"] = 0.0

	elapsed += dt


func _step_relish(dt: float) -> void:
	if raiding:
		return
	if relish["state"] == "travelling":
		relish["progress"] += float(t.get("travelSpeed", 220.0)) * dt
		if relish["progress"] >= relish["travel_total"]:
			relish["at"] = relish["target"]
			relish["target"] = ""
			relish["state"] = "raising"
			relish["progress"] = 0.0
		return
	if relish["state"] == "raising" and relish["at"] != "covington":
		var f := fort_by_id(relish["at"])
		if not f.is_empty():
			var raised: float = minf(f["dead"], float(t.get("raiseRate", 30.0)) * dt)
			f["dead"] -= raised
			vei["undead_queue"] += raised
			vei["r_in_undead"] += raised / dt if dt > 0.0 else 0.0


func _step_simulacra(dt: float) -> void:
	var alive: Array = []
	for s in simulacra:
		var f := fort_by_id(s["fort_id"])
		if not f.is_empty():
			var raised: float = minf(f["dead"], minf(float(s["rate"]) * dt, float(s["charges"])))
			f["dead"] -= raised
			f["r_raised"] = raised / dt if dt > 0.0 else 0.0
			vei["undead_queue"] += raised
			vei["r_in_undead"] += raised / dt if dt > 0.0 else 0.0
			raised_by_sims += raised
			s["charges"] = float(s["charges"]) - raised
		if float(s["charges"]) > 0.01:
			alive.append(s)
	simulacra = alive


func send_relish(id: String) -> void:
	if relish["state"] == "travelling" and relish["target"] == id:
		return
	if relish["at"] == id:
		relish["target"] = ""
		relish["state"] = "raising"
		relish["progress"] = 0.0
		return
	relish["target"] = id
	relish["state"] = "travelling"
	relish["progress"] = 0.0
	relish["travel_total"] = node_pos(relish["at"]).distance_to(node_pos(id))


func readout() -> Dictionary:
	var q: float = maxf(1.0, float(t.get("q", 1.0)))
	var inflow := 0.0
	for f in forts:
		inflow += f["r_drain"]
	inflow += vei["r_in_undead"] + cov["r_out"] * float(t.get("directShare", 0.22))
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
