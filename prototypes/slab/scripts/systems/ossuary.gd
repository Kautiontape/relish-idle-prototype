class_name Ossuary
extends RefCounted
## The bone pit. One meter (fullness 0..1) IS the quality dial: feeding scraps
## raises it with diminishing returns (cheap to mediocre, dear to full); a pull
## ALWAYS yields something, its quality scales with fullness, and the pull
## consumes a chunk. Output is hard-capped below looted gear — a floor that
## keeps you off zero, never a substitute for raiding.

var fullness := 0.0
var rng: RandomNumberGenerator

func _init(shared_rng: RandomNumberGenerator = null) -> void:
	rng = shared_rng if shared_rng != null else RandomNumberGenerator.new()

func feed(scraps: int) -> void:
	var gain := float(ConfigDb.v("ossuary", "fill_per_scrap"))
	for i in scraps:
		fullness += gain * (1.0 - fullness)  # diminishing returns toward the top
	fullness = clampf(fullness, 0.0, 1.0)

func decay(delta: float) -> void:
	if bool(ConfigDb.v("ossuary", "decay_enabled")):
		fullness = maxf(0.0, fullness - float(ConfigDb.v("ossuary", "decay_per_s")) * delta)

## Always returns {quality, form_id, remnant}; consumes a chunk of fullness.
func pull() -> Dictionary:
	var cfg: Dictionary = ConfigDb.data["ossuary"]
	var band := float(cfg["quality_rng_band"])
	var q := clampf(fullness + rng.randf_range(-band, band), 0.0, 1.0)
	var out := {"quality": q, "form_id": _pull_form(q), "remnant": _pull_remnant(q)}
	fullness = maxf(0.0, fullness - float(cfg["drop_per_pull"]))
	return out

func _pull_form(q: float) -> String:
	var cfg: Dictionary = ConfigDb.data["ossuary"]
	if rng.randf() < q * float(cfg["mid_form_chance_at_full"]):
		return Loot.roll_husk(rng)  # high quality: a shot at any form
	return Loot.weighted_pick(rng, cfg["scrap_form_weights"])

func _pull_remnant(q: float) -> Dictionary:
	var cfg: Dictionary = ConfigDb.data["ossuary"]
	var stat: String = Loot.STATS[rng.randi_range(0, Loot.STATS.size() - 1)]
	var lo := int(cfg["min_magnitude"])
	var hi := int(cfg["max_magnitude"])
	var magnitude := lo + int(round(q * float(hi - lo)))
	magnitude = clampi(magnitude + rng.randi_range(-1, 0), lo, hi)
	# Rarity caps at uncommon — the pit never births a rare/legendary specialist.
	var rarity := "uncommon" if q >= float(cfg["uncommon_quality_threshold"]) else "common"
	var echoes: Array = []
	var combat_pts := 0
	if rng.randf() < q * float(cfg["echo_chance_at_full"]):
		var pool: Array = ConfigDb.data["echoes"]["combat"].keys()
		var pts := rng.randi_range(1, 2)
		echoes.append({"id": pool[rng.randi_range(0, pool.size() - 1)], "points": pts, "side": "combat"})
		combat_pts = pts
	return {"stat": stat, "magnitude": magnitude, "rarity": rarity,
		"echoes": echoes, "combat_points": combat_pts, "town_points": 0, "from_pit": true}
