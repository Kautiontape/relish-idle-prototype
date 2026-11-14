class_name RaidLoot
extends RefCounted
## Pure, seeded dungeon loot (MECHANICS 5.3, configs/loot.json). No scene tree, no autoloads: every
## roll takes a RandomNumberGenerator, so the same seed and call order give the same loot.
## Luck sets pace, never ceiling: yield_mult scales how much drops, never what can drop.
##
## API (loot shape = STATE-API 8.1 {relics, blueprints, husks, remnants, essence}):
##   scaled_count(rng, n, yield_mult) -> int          expected-value rounding of n * yield
##   ding(rng, tier, archetype, yield_mult, cfg)      {} or one remnant {aspect, rarity, magnitude}
##   chest(rng, info, owned_blueprints, cfg)          the warden's chest; info = {tier, archetype,
##                                                    first_clear, chest_husk, yield_mult}
##   held_clear(rng, tier, yield_mult, cfg)           a held fort's counter-garrison reward
##   hint(table_id, first_dungeon, cfg)               the short "loot_hint" phrase
##   card_line(fort, cfg) -> String                   ONE line for the map's fort card, from a
##       view_fort entry (reads tier, warden.archetype, first_clear, first_dungeon, yield_mult,
##       held). Shows what the fort holds now and how much has recovered, e.g.
##       "loot: blueprint · relics 1–2 · remnants (beef) · yield 100%", "refilling · yield 55%",
##       "held · counter-garrison: relics 0–1 · remnants 1 · essence 2–4 · yield 100%".
##       Signature is stable; the map unit calls it.

const ASPECTS: Array[String] = ["power", "beef", "wits", "presence", "speed"]
const RARITIES: Array[String] = ["common", "uncommon", "rare", "legendary"]


# ------------------------------------------------------------------ helpers ---
## The config entry for `tier` in a by-tier dictionary (keys "1".."N"); tiers past the last
## key use the last, below the first use the first.
static func _by_tier(d: Dictionary, tier: int) -> Variant:
	if d.is_empty():
		return {}
	var best := 1
	for k in d.keys():
		var kt := int(str(k))
		if kt <= tier and kt >= best:
			best = kt
	if d.has(str(best)):
		return d[str(best)]
	return d[d.keys()[0]]


static func _range(rng: RandomNumberGenerator, r: Array) -> int:
	if r.size() < 2:
		return 0
	return rng.randi_range(int(r[0]), int(r[1]))


static func _pick_weighted(rng: RandomNumberGenerator, order: Array, weights: Dictionary) -> String:
	var total := 0.0
	for k in order:
		total += maxf(0.0, float(weights.get(k, 0.0)))
	if total <= 0.0:
		return str(order[0])
	var x := rng.randf() * total
	for k in order:
		x -= maxf(0.0, float(weights.get(k, 0.0)))
		if x < 0.0:
			return str(k)
	return str(order[order.size() - 1])


static func _remnant(rng: RandomNumberGenerator, tier: int, archetype: String, cfg: Dictionary) -> Dictionary:
	var ding: Dictionary = cfg.get("ding", {})
	var rarity := _pick_weighted(rng, RARITIES, _by_tier(ding.get("rarity_weights_by_tier", {}), tier))
	var aw: Dictionary = cfg.get("aspect_weights_by_archetype", {})
	var aspect := _pick_weighted(rng, ASPECTS, aw.get(archetype, aw.get("default", {})))
	var mag := _range(rng, (cfg.get("magnitude_by_rarity", {}) as Dictionary).get(rarity, [1, 1]))
	return {"aspect": aspect, "rarity": rarity, "magnitude": mag}


static func empty_loot() -> Dictionary:
	return {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0}


# -------------------------------------------------------------------- rolls ---
## Expected-value rounding of n * yield_mult: floor, plus one with the fractional probability.
static func scaled_count(rng: RandomNumberGenerator, n: float, yield_mult: float) -> int:
	var v := maxf(0.0, n * maxf(0.0, yield_mult))
	var base := int(floor(v))
	return base + (1 if rng.randf() < v - float(base) else 0)


## A remnant ding off a kill, or {}. The chance is multiplied by yield_mult.
static func ding(rng: RandomNumberGenerator, tier: int, archetype: String, yield_mult: float,
		cfg: Dictionary) -> Dictionary:
	var chance := float(_by_tier(cfg.get("ding", {}).get("chance_by_tier", {}), tier)) * maxf(0.0, yield_mult)
	if rng.randf() >= clampf(chance, 0.0, 1.0):
		return {}
	return _remnant(rng, tier, archetype, cfg)


## The warden's chest. Relics, remnants and the husk chance scale with yield; the first-clear
## blueprint and the first-dungeon husk do not.
static func chest(rng: RandomNumberGenerator, info: Dictionary, owned_blueprints: Array,
		cfg: Dictionary) -> Dictionary:
	var tier := maxi(1, int(info.get("tier", 1)))
	var arche := str(info.get("archetype", ""))
	var y := float(info.get("yield_mult", 1.0))
	var t: Dictionary = _by_tier(cfg.get("chest_by_tier", {}), tier)
	var out := empty_loot()
	out["relics"] = scaled_count(rng, float(_range(rng, t.get("relics", [0, 0]))), y)
	var n_rem := scaled_count(rng, float(_range(rng, t.get("remnants", [0, 0]))), y)
	for i in n_rem:
		(out["remnants"] as Array).append(_remnant(rng, tier, arche, cfg))
	var kinds: Array = t.get("husk_kinds", [])
	if not kinds.is_empty() and rng.randf() < clampf(float(t.get("husk_chance", 0.0)) * maxf(0.0, y), 0.0, 1.0):
		(out["husks"] as Array).append({"kind": str(kinds[rng.randi_range(0, kinds.size() - 1)])})
	if bool(info.get("chest_husk", false)):
		(out["husks"] as Array).append({"kind": str(cfg.get("first_dungeon_husk", "skeleton"))})
	if bool(info.get("first_clear", false)):
		var bp := first_blueprint(tier, owned_blueprints, cfg)
		if bp == "":
			out["relics"] = int(out["relics"]) + 1   # everything unlockable is owned
		else:
			(out["blueprints"] as Array).append(bp)
	return out


## The first blueprint (in config order, tiers 1..tier) not in `owned`; "" when all are owned.
static func first_blueprint(tier: int, owned: Array, cfg: Dictionary) -> String:
	var by_tier: Dictionary = cfg.get("first_clear_blueprint_by_tier", {})
	var tiers: Array = []
	for k in by_tier.keys():
		if int(str(k)) <= tier:
			tiers.append(int(str(k)))
	tiers.sort()
	for tk in tiers:
		for id in by_tier[str(tk)]:
			if not owned.has(str(id)):
				return str(id)
	return ""


## Clearing a held fort's counter-garrison: a smaller table. `essence` is the bonus of fresh motes
## (the scene spawns them; the loot shape carries the count).
static func held_clear(rng: RandomNumberGenerator, tier: int, yield_mult: float, cfg: Dictionary) -> Dictionary:
	var h: Dictionary = cfg.get("held_clear", {})
	var out := empty_loot()
	out["relics"] = scaled_count(rng, float(_range(rng, h.get("relics", [0, 0]))), yield_mult)
	var n_rem := scaled_count(rng, float(_range(rng, h.get("remnants", [0, 0]))), yield_mult)
	for i in n_rem:
		(out["remnants"] as Array).append(_remnant(rng, tier, "", cfg))
	out["essence"] = scaled_count(rng, float(_range(rng, h.get("essence_motes", [0, 0]))), yield_mult)
	return out


# ------------------------------------------------------------------- text ----
static func hint(table_id: String, first_dungeon: bool, cfg: Dictionary) -> String:
	var h: Dictionary = cfg.get("hints", {})
	if first_dungeon:
		return str(h.get("first_dungeon_hint", ""))
	return str(h.get(table_id, ""))


static func _span(r: Array) -> String:
	if r.size() < 2:
		return "0"
	return str(int(r[0])) if int(r[0]) == int(r[1]) else "%d–%d" % [int(r[0]), int(r[1])]


## The aspect an archetype leans on, or "" when no single aspect leads.
static func _lean(archetype: String, cfg: Dictionary) -> String:
	var aw: Dictionary = cfg.get("aspect_weights_by_archetype", {})
	var w: Dictionary = aw.get(archetype, aw.get("default", {}))
	var best := ""
	var best_w := -1.0
	var tie := false
	for a in ASPECTS:
		var x := float(w.get(a, 0.0))
		if x > best_w:
			best_w = x
			best = a
			tie = false
		elif x == best_w:
			tie = true
	return "" if tie else best


static func card_line(fort: Dictionary, cfg: Dictionary) -> String:
	var tier := maxi(1, int(fort.get("tier", 1)))
	var y := clampf(float(fort.get("yield_mult", 1.0)), 0.0, 1.0)
	var pct := "yield %d%%" % int(round(y * 100.0))
	var full := y * 100.0 >= float(cfg.get("card", {}).get("full_yield_pct", 99.5))
	var parts: Array[String] = []
	if bool(fort.get("held", false)):
		var h: Dictionary = cfg.get("held_clear", {})
		parts = ["held · counter-garrison: relics %s" % _span(h.get("relics", [])),
			"remnants %s" % _span(h.get("remnants", [])), "essence %s" % _span(h.get("essence_motes", []))]
		parts.append(pct)
		return " · ".join(parts)
	var arche := str((fort.get("warden", {}) as Dictionary).get("archetype", ""))
	var t: Dictionary = _by_tier(cfg.get("chest_by_tier", {}), tier)
	if bool(fort.get("first_clear", false)):
		parts.append("blueprint")
	if bool(fort.get("first_dungeon", false)):
		parts.append("husk")
	if full:
		parts.append("relics %s" % _span(t.get("relics", [])))
		var lean := _lean(arche, cfg)
		parts.append("remnants (%s)" % lean if lean != "" else "remnants")
		parts.append(pct)
		return "loot: " + " · ".join(parts)
	parts.push_front("refilling")
	parts.append(pct)
	return " · ".join(parts)
