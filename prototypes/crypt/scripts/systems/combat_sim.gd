class_name CombatSim
extends RefCounted
## The faked fights. A raid rolls a THREAT; how well your composition counters it
## sets the party-wide DANGER. Who dies is then a per-unit roll weighted by
## survivability — the frail soak most of the risk, but no one is safe (a champion
## can get out of position and fall) and no one is doomed (a Hollow sometimes
## scrapes through). Survivability reads toughness stats AND combat perks like
## life steal. Vei is the end-state: a set of fronts, each answered by a
## counter-stat, met or not. Win = enough fronts covered.
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

## How hard a single unit is to kill. Toughness stats (beef=HP, persistence,
## wits, speed) plus survivability ECHOES — life_drain (life steal) heals you
## through a fight; frenzy keeps you swinging. Offensive echoes (heavy_blow,
## volatile, vengeful) await real combat and don't touch the faked loss model yet.
static func survivability(u: Dictionary) -> float:
	var scfg: Dictionary = ConfigDb.data["raid"]["survival"]
	var sw: Dictionary = scfg["stat_weights"]
	var st: Dictionary = u["stats"]
	var s := 0.0
	for k in sw:
		s += float(st.get(k, 0.0)) * float(sw[k])
	var ech: Dictionary = u.get("echoes", {})
	var ew: Dictionary = scfg["echo_survival"]
	for k in ew:
		s += float(ech.get(k, 0)) * float(ew[k])
	return s

## Per-unit death chance for this party against this threat. Coverage sets the
## party-wide base danger; it's redistributed by survivability (frail soak more),
## then clamped to [death_floor, death_cap] so even the tough can die and even
## the frail can live. Returns one probability per unit, index-aligned.
static func death_chances(units: Array, threat: Dictionary, coverage: float) -> Array:
	var out: Array = []
	var n := units.size()
	if n == 0:
		return out
	var cfg: Dictionary = ConfigDb.data["raid"]
	var scfg: Dictionary = cfg["survival"]
	var base := float(threat["base_loss_frac"]) * (1.0 - coverage)
	if coverage < 0.34:
		base = maxf(base, float(cfg["min_losses_if_uncovered"]) / float(n))
	var risk: Array = []
	var total := 0.0
	for u in units:
		var rw := 1.0 / (1.0 + survivability(u) * float(scfg["coeff"]))
		risk.append(rw)
		total += rw
	var avg := total / float(n)
	for i in n:
		var p: float = base
		if avg > 0.0:
			p = base * (float(risk[i]) / avg)
		out.append(clampf(p, float(scfg["death_floor"]), float(scfg["death_cap"])))
	return out

## {coverage, n_losses, lost_indices, death_chances}. Each unit rolls its own
## death independently — losses are frail-leaning, not weakest-by-fiat.
static func resolve_raid(units: Array, threat: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var coverage := raid_coverage(units, threat)
	var ps := death_chances(units, threat, coverage)
	var lost: Array = []
	for i in units.size():
		if rng.randf() < float(ps[i]):
			lost.append(i)
	return {"coverage": coverage, "n_losses": lost.size(), "lost_indices": lost,
		"death_chances": ps, "threat": threat}

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
