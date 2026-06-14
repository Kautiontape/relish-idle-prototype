class_name CombatSim
extends RefCounted
## The faked fights. A raid rolls a THREAT; how well your composition counters it
## sets your losses (never random), and losses fall on your weakest first — the
## Hollow screen dies for the champions. Vei is the end-state: a set of fronts,
## each answered by a counter-stat, met or not. Win = enough fronts covered.
## "Do I feel ready?" is the player judging these fronts by eye, thresholds hidden.

static func roll_raid(rng: RandomNumberGenerator) -> Dictionary:
	var threats: Array = ConfigDb.data["raid"]["threats"]
	return threats[rng.randi_range(0, threats.size() - 1)]

static func _counter_strength(units: Array, counter_stat: String) -> float:
	var s := 0.0
	if counter_stat == "power":
		for u in units:
			s += float(u["power"])
	else:
		for u in units:
			s += float(u["stats"][counter_stat])
	return s

static func raid_coverage(units: Array, threat: Dictionary) -> float:
	var cfg: Dictionary = ConfigDb.data["raid"]
	var strength := _counter_strength(units, String(threat["counter_stat"]))
	return minf(float(cfg["max_coverage"]), strength * float(cfg["coverage_per_counter_point"]))

## {coverage, n_losses, lost_indices}. lost_indices = weakest power first (ablative).
static func resolve_raid(units: Array, threat: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	var cfg: Dictionary = ConfigDb.data["raid"]
	var coverage := raid_coverage(units, threat)
	var n := int(round(float(units.size()) * float(threat["base_loss_frac"]) * (1.0 - coverage)))
	if units.size() > 0 and coverage < 0.34:
		n = maxi(n, int(cfg["min_losses_if_uncovered"]))
	n = clampi(n, 0, units.size())
	var order: Array = range(units.size())
	order.sort_custom(func(a, b): return float(units[a]["power"]) < float(units[b]["power"]))
	return {"coverage": coverage, "n_losses": n, "lost_indices": order.slice(0, n), "threat": threat}

## Each front: your counter strength vs a hidden threshold. The hint is shown;
## the number is not — you decide whether you 'feel ready'.
static func vei_fronts(units: Array) -> Array:
	var out: Array = []
	for f in ConfigDb.data["vei"]["fronts"]:
		var strength := _counter_strength(units, String(f["counter_stat"]))
		if f.has("alt_stat"):
			strength += _counter_strength(units, String(f["alt_stat"]))
		out.append({"id": f["id"], "hint": String(f["hint"]), "counter_stat": String(f["counter_stat"]),
			"strength": strength, "threshold": float(f["threshold"]), "met": strength >= float(f["threshold"])})
	return out

static func resolve_vei(units: Array) -> Dictionary:
	var fronts := vei_fronts(units)
	var met := 0
	for f in fronts:
		if f["met"]:
			met += 1
	var need := int(ConfigDb.data["vei"]["fronts_required"])
	return {"fronts": fronts, "met": met, "need": need, "won": met >= need}
