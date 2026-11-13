class_name RaidLogic
extends RefCounted
## Pure raid logic: mass-ledger math, tier mappings, raise, statlines, the result builder,
## sacrifice, essence, telemetry and checkpoint/revive math. The fortress layout generator lives in
## LayoutLogic (RaidLogic keeps one-line delegates). No scene-tree or autoload dependencies —
## every function takes a cfg Dictionary (parsed configs/raid.json) so tests run headless.


# ------------------------------------------------------------ mass mappings --
static func enemy_count(living: float, cap: float, cfg: Dictionary) -> int:
	var m: Dictionary = cfg.get("mass", {})
	var per: float = float(m.get("enemies_per_cap", 26.0))
	return clampi(int(round(living / maxf(1.0, cap) * per)),
		int(m.get("enemy_min", 5)), int(m.get("enemy_max", 34)))


static func mass_per_enemy(living: float, cap: float, cfg: Dictionary) -> float:
	return living / float(enemy_count(living, cap, cfg))


static func pile_count(dead: float, cfg: Dictionary) -> int:
	var m: Dictionary = cfg.get("mass", {})
	return clampi(int(dead / float(m.get("pile_mass_div", 8.0))),
		int(m.get("pile_min", 2)), int(m.get("pile_max", 24)))


static func garrison_count(undead: float, cfg: Dictionary) -> int:
	var m: Dictionary = cfg.get("mass", {})
	return clampi(int(undead / float(m.get("garrison_mass_div", 10.0))),
		0, int(m.get("garrison_max", 12)))


# ---------------------------------------------------------- raise mappings ---
static func score_class(score: int, cfg: Dictionary) -> String:
	var r: Dictionary = cfg.get("raise", {})
	if score >= int(r.get("elite_min_score", 90)):
		return "elite"
	if score >= int(r.get("soldier_min_score", 60)):
		return "soldier"
	return "chaff"


## What a scored circle raises from N orbs of total mass M.
## Big sloppy circle = many weak idiots; small perfect circle = few strong ones.
static func raise_spec(score: int, total_mass: float, orb_count: int, cfg: Dictionary) -> Dictionary:
	if orb_count <= 0:
		return {"kind": "", "count": 0, "unit_mass": 0.0}
	var r: Dictionary = cfg.get("raise", {})
	match score_class(score, cfg):
		"elite":
			return {"kind": "elite",
				"count": maxi(1, int(orb_count / float(r.get("elite_orb_div", 4.0)))),
				"unit_mass": 0.0}
		"soldier":
			return {"kind": "soldier",
				"count": maxi(1, int(orb_count / float(r.get("soldier_orb_div", 3.0)))),
				"unit_mass": 0.0}
	return {"kind": "chaff", "count": orb_count, "unit_mass": total_mass / orb_count}


# ------------------------------------------------- v2: seed, raise, statlines --
## A dungeon seed in the STATE-API 7.1 shape for standalone runs.
static func demo_seed(cfg: Dictionary) -> Dictionary:
	var d: Dictionary = cfg.get("demo", {})
	var div := float(cfg.get("mass", {}).get("garrison_mass_div", 10.0))
	var undead := float(d.get("undead", 0.0))
	var units := garrison_count(undead, cfg)
	var bu: Dictionary = d.get("big_undead", {})
	var st: Dictionary = bu.get("stats", {})
	var party: Array = []
	if not bu.is_empty():
		party.append({"uid": str(bu.get("uid", "u1")), "name": str(bu.get("name", "")),
			"kind": str(bu.get("kind", "")), "role": str(bu.get("role", "")),
			"stats": {"power": float(st.get("power", 0.0)), "beef": float(st.get("beef", 0.0)),
				"wits": float(st.get("wits", 0.0)), "presence": float(st.get("presence", 0.0)),
				"speed": float(st.get("speed", 0.0))}})
	var w: Dictionary = d.get("warden", {})
	var tier := int(d.get("tier", 1))
	return {
		"v": 2, "kind": "raid", "run_id": int(d.get("run_id", 0)), "seed_rev": int(d.get("seed_rev", 0)),
		"rng_seed": str(d.get("rng_seed", "1")),
		"fort": {"id": str(d.get("fort_id", "")), "name": str(d.get("fort_name", "")), "tier": tier,
			"cap": float(d.get("cap", 100.0)), "first_clear": bool(d.get("first_clear", false)),
			"first_dungeon": bool(d.get("first_dungeon", false)),
			"clears_since_retaken": int(d.get("clears_since_retaken", 0)),
			"yield_mult": float(d.get("yield_mult", 1.0))},
		"living": float(d.get("living", 0.0)), "dead": float(d.get("dead", 0.0)), "undead": undead,
		"garrison_units": units, "garrison_in_mass": float(units) * div, "garrison_mass_div": div,
		"starter_units": int(d.get("starter_units", 0)), "party": party,
		"digest_q": float(d.get("digest_q", 1.0)),
		"phylactery_charges": int(d.get("phylactery_charges", 0)),
		"phylactery_max_per_dungeon": int(d.get("phylactery_max_per_dungeon", 1)),
		"clones_ready": int(d.get("clones_ready", 0)),
		"warden": {"archetype": str(w.get("archetype", "bellringer")), "tier": int(w.get("tier", tier))},
		"warden_spec": {},
		"loot_table_id": "t%d.%s" % [tier, str(w.get("archetype", "bellringer"))],
		"loot_hint": str(d.get("loot_hint", "")), "chest_husk": bool(d.get("chest_husk", false)),
		"watchtower": bool(d.get("watchtower", false)),
		"relish_hp": float(cfg.get("relish", {}).get("hp", 30.0)),
	}


## Pure twin of CircleScorer.multiplier (circle.json keys).
static func stat_mult(score: int, circle_cfg: Dictionary) -> float:
	return float(circle_cfg.get("multiplier_base", 0.5)) \
		+ float(circle_cfg.get("multiplier_per_100", 1.0)) * float(score) / 100.0


## MECHANICS 5.3: every mote raises one undead at stat_mult(score). `motes` is
## [{mass: float, recycled: bool}]. Recycled motes carry mass but are not newly
## raised dead, so they stay out of fresh_mass.
static func raise_spec_v2(score: int, motes: Array, cfg: Dictionary, circle_cfg: Dictionary) -> Dictionary:
	var masses: Array[float] = []
	var fresh := 0.0
	for m in motes:
		var mm := maxf(0.0, float(m.get("mass", 0.0)))
		masses.append(mm)
		if not bool(m.get("recycled", false)):
			fresh += mm
	return {"tier": score_class(score, cfg) if not motes.is_empty() else "",
		"count": motes.size(), "stat_mult": stat_mult(score, circle_cfg),
		"unit_masses": masses, "fresh_mass": fresh}


static func undead_stats(mult: float, tier: String, cfg: Dictionary) -> Dictionary:
	var u: Dictionary = cfg.get("undead", {})
	var b: Dictionary = u.get("base", {})
	return {"hp": float(b.get("hp", 10.0)) * mult, "dmg": float(b.get("dmg", 2.0)) * mult,
		"speed": float(b.get("speed", 118.0)), "cadence_s": float(b.get("cadence_s", 0.9)),
		"radius": float(u.get("radius_by_tier", {}).get(tier, b.get("radius", 9.0)))}


static func big_undead_stats(stats: Dictionary, cfg: Dictionary) -> Dictionary:
	var p: Dictionary = cfg.get("party", {})
	return {"hp": float(p.get("hp_base", 30.0)) + float(p.get("hp_per_beef", 8.0)) * float(stats.get("beef", 0.0)),
		"dmg": float(p.get("dmg_base", 3.0)) + float(p.get("dmg_per_power", 1.2)) * float(stats.get("power", 0.0)),
		"speed": float(p.get("speed_base", 90.0)) + float(p.get("speed_per_speed", 10.0)) * float(stats.get("speed", 0.0)),
		"cadence_s": float(p.get("cadence_s", 1.0)), "radius": float(p.get("radius", 20.0))}


static func empty_loot() -> Dictionary:
	return {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0}


## A deep copy of `found` (loot shape minus essence) in the full loot shape, with essence set to
## what Relish carries now: the checkpoint's banked loot (MECHANICS 7).
static func loot_snapshot(found: Dictionary, carried: int) -> Dictionary:
	var out := empty_loot()
	for k in out:
		if found.has(k) and k != "essence":
			out[k] = found[k].duplicate(true) if (found[k] is Array or found[k] is Dictionary) else found[k]
	out["essence"] = maxi(0, carried)
	return out


## The checkpoint snapshot with its essence capped at what is still carried: motes circled into
## undead after the checkpoint are spent, so a death must not pay them out. A copy; an empty
## snapshot stays empty.
static func clamp_banked_essence(banked: Dictionary, carried: int) -> Dictionary:
	var out := banked.duplicate(true)
	if out.has("essence"):
		out["essence"] = mini(int(out["essence"]), maxi(0, carried))
	return out


## True when a phylactery charge is left to spend in this dungeon (MECHANICS 7).
static func can_revive(revived: int, seed: Dictionary) -> bool:
	return revives_left(revived, seed) > 0


## Phylactery charges still spendable this run: min(charges, max_per_dungeon) - revived.
static func revives_left(revived: int, seed: Dictionary) -> int:
	return maxi(0, mini(int(seed.get("phylactery_charges", 0)), int(seed.get("phylactery_max_per_dungeon", 0))) - revived)


## Sacrifice chain (MECHANICS 5.0): rank 0 chaff tier (raised chaff, garrison, starters),
## 1 soldier, 2 elite, 3 big undead (party).
static func ally_rank(role: String, tier: String) -> int:
	if role == "party" or tier == "big":
		return 3
	match tier:
		"soldier":
			return 1
		"elite":
			return 2
	return 0


## Candidates are [{rank: int, dist: float}]. The lowest rank wins, then the nearest.
## Returns its index, or -1 when there are none.
static func sacrifice_pick(candidates: Array) -> int:
	var best := -1
	for i in candidates.size():
		var c: Dictionary = candidates[i]
		if best < 0:
			best = i
			continue
		var b: Dictionary = candidates[best]
		var cr := int(c.get("rank", 0))
		var br := int(b.get("rank", 0))
		if cr < br or (cr == br and float(c.get("dist", 0.0)) < float(b.get("dist", 0.0))):
			best = i
	return best


## RTS-drift guard (MECHANICS 5.0): move clicks per successful raise.
static func drift_ratio(moves: int, raises: int) -> float:
	if raises <= 0:
		return float(moves)
	return float(moves) / float(raises)


static func is_drifting(moves: int, raises: int, cfg: Dictionary) -> bool:
	return drift_ratio(moves, raises) > float(cfg.get("telemetry", {}).get("drift_ratio", 8.0))


## Split a mass into n equal parts (n >= 1); the parts sum to mass.
static func split_mass(mass: float, n: int) -> Array:
	var k := maxi(1, n)
	var out: Array = []
	var each := mass / float(k)
	var acc := 0.0
	for i in k - 1:
		out.append(each)
		acc += each
	out.append(mass - acc)
	return out


## Free places in Relish's carried cluster.
static func carry_room(carried: int, cfg: Dictionary) -> int:
	return maxi(0, int(cfg.get("essence", {}).get("carry_max", 12)) - carried)


## Raid result v2 builder (STATE-API 8.1). Pure bookkeeping, no scene state.
class LedgerV2:
	extends RefCounted
	var garrison_in_mass := 0.0
	var cap := 1.0
	var keep_frac := 0.25
	var killed := 0.0
	var buckets: Array = []  # {score, count, mass}
	var _cfg: Dictionary = {}

	func _init(seed: Dictionary, cfg: Dictionary) -> void:
		_cfg = cfg
		garrison_in_mass = float(seed.get("garrison_in_mass", 0.0))
		cap = maxf(1.0, float(seed.get("fort", {}).get("cap", 1.0)))
		keep_frac = float(cfg.get("mass", {}).get("garrison_keep_cap_frac", 0.25))

	func on_kill(mass: float) -> void:
		killed += maxf(0.0, mass)

	func on_raise(score: int, fresh_mass: float, count: int) -> void:
		if count <= 0:
			return
		for b in buckets:
			if int(b["score"]) == score:
				b["count"] = int(b["count"]) + count
				b["mass"] = float(b["mass"]) + maxf(0.0, fresh_mass)
				return
		buckets.append({"score": score, "count": count, "mass": maxf(0.0, fresh_mass)})

	func raised_counts() -> Dictionary:
		var out := {"chaff": 0, "soldier": 0, "elite": 0}
		for b in buckets:
			var tier := RaidLogic.score_class(int(b["score"]), _cfg)
			out[tier] = int(out[tier]) + int(b["count"])
		return out

	func build_result(seed: Dictionary, exit: String, survivors: Array, party_died: Array,
			revived: int, loot: Dictionary, cfg: Dictionary) -> Dictionary:
		var garrison := 0.0
		var pool := 0.0
		for s in survivors:
			var m := maxf(0.0, float(s.get("mass", 0.0)))
			match str(s.get("role", "")):
				"garrison":
					garrison += m
				"raised":
					if str(s.get("tier", "chaff")) == "chaff":
						pool += m
					else:
						garrison += m
		var kept := minf(pool, keep_frac * cap)
		garrison += kept
		var chaff := pool - kept
		var raised_total := 0.0
		for b in buckets:
			raised_total += float(b["mass"])
		var limit := garrison_in_mass + raised_total
		var total := garrison + chaff
		if total > limit + 1e-6:
			var f := limit / total
			garrison *= f
			chaff *= f
		var lost: Array = []
		for u in seed.get("party", []):
			var uid := str(u.get("uid", ""))
			if (exit == "relish_died" or party_died.has(uid)) and not lost.has(uid):
				lost.append(uid)
		var full := RaidLogic.empty_loot()
		for k in full:
			if loot.has(k):
				full[k] = loot[k]
		var raised_out: Array = []
		for b in buckets:
			raised_out.append(b.duplicate())
		return {"v": 2, "run_id": int(seed.get("run_id", 0)), "seed_rev": int(seed.get("seed_rev", 0)),
			"fort_id": str(seed.get("fort", {}).get("id", "")),
			"warden_beaten": exit == "warden_beaten", "retreated": exit == "retreated",
			"relish_died": exit == "relish_died", "revived_in_place": maxi(0, revived),
			"killed_living_mass": killed, "raised": raised_out,
			"chaff_mass": maxf(0.0, chaff), "garrison_mass": maxf(0.0, garrison),
			"party_lost": lost, "loot": full}


## Which enemy kinds a tier fields (keys of the tier's mix).
static func tier_kinds(tier: int, cfg: Dictionary) -> Array:
	var mix: Dictionary = cfg.get("tier_mix", {}).get(str(clampi(tier, 1, 4)), {"spearman": 1.0})
	return mix.keys()


static func roll_enemy_kind(rng: RandomNumberGenerator, tier: int, cfg: Dictionary) -> String:
	var mix: Dictionary = cfg.get("tier_mix", {}).get(str(clampi(tier, 1, 4)), {"spearman": 1.0})
	var total := 0.0
	for k in mix:
		total += float(mix[k])
	var roll := rng.randf() * maxf(0.0001, total)
	for k in mix:
		roll -= float(mix[k])
		if roll <= 0.0:
			return k
	return "spearman"


# -------------------------------------------------------------- the ledger ---
## Tracks how in-scene events map onto the abstract map-mass result dict.
## Conservation invariant: everything reported as raised (chaff out + good mass
## + garrison) can never exceed initial dead + mass of living killed. Chaff that
## is re-killed inside the raid drops out of the pool (its corpse stays at the
## fort), so the surviving pool is what splits at the exit.
class Ledger:
	extends RefCounted
	var initial_dead := 0.0
	var cap := 0.0
	var killed := 0.0          # mass of living killed this raid
	var chaff_pool := 0.0      # mass currently walking around as raised chaff
	var soldiers := 0
	var elites := 0
	var good_mass := 0.0       # mass consumed by soldier/elite raises
	var raised_any := false
	var essence_consumed := 0.0

	func _init(dead0: float, cap0: float) -> void:
		initial_dead = maxf(0.0, dead0)
		cap = maxf(1.0, cap0)

	func on_kill(mass: float) -> void:
		killed += maxf(0.0, mass)

	## Apply a scored raise of N orbs totalling M mass. Returns the spawn spec.
	func on_raise(score: int, total_mass: float, orb_count: int, cfg: Dictionary) -> Dictionary:
		var spec := RaidLogic.raise_spec(score, total_mass, orb_count, cfg)
		if spec["count"] <= 0:
			return spec
		raised_any = true
		essence_consumed += total_mass
		if spec["kind"] == "chaff":
			chaff_pool += total_mass
		else:
			good_mass += total_mass
			if spec["kind"] == "soldier":
				soldiers += int(spec["count"])
			else:
				elites += int(spec["count"])
		return spec

	func on_chaff_death(mass: float) -> void:
		chaff_pool = maxf(0.0, chaff_pool - mass)

	func aborted() -> bool:
		return killed <= 0.0 and not raised_any

	## Final result dict. Surviving chaff mass splits: up to keep_frac*cap stays
	## as garrison, the remainder leaves with Relish as chaff mass.
	func result(fort_id: String, relish_died: bool, cfg: Dictionary) -> Dictionary:
		var keep_frac: float = float(cfg.get("mass", {}).get("garrison_keep_cap_frac", 0.25))
		var garrison := minf(chaff_pool, keep_frac * cap)
		var chaff_out := chaff_pool - garrison
		# safety clamp: never report more raised mass than existed (never expected
		# to trigger — orbs only ever carry killed or pile mass)
		var avail := initial_dead + killed
		var total := chaff_out + garrison + good_mass
		if total > avail and total > 0.0:
			var s := avail / total
			chaff_out *= s
			garrison *= s
			good_mass *= s
		return {
			"fort_id": fort_id,
			"killed_living_mass": killed,
			"raised_chaff_mass": chaff_out,
			"raised_soldiers": soldiers,
			"raised_elites": elites,
			"good_mass": good_mass,
			"garrison_mass": garrison,
			"relish_died": relish_died,
			"aborted": aborted(),
		}


# ------------------------------------------- layout (LayoutLogic delegates) ----
static func gen_layout(fort_id: String, tier: int, is_boss: bool, cfg: Dictionary, opts: Dictionary = {}) -> Dictionary:
	return LayoutLogic.gen_layout(fort_id, tier, is_boss, cfg, opts)


static func room_of(layout: Dictionary, p: Vector2) -> int:
	return LayoutLogic.room_of(layout, p)


static func room_adjacency(layout: Dictionary) -> Array:
	return LayoutLogic.room_adjacency(layout)


static func room_hops(adj: Array, start: int) -> Array[int]:
	return LayoutLogic.room_hops(adj, start)


static func layout_reachable(layout: Dictionary, cell: float) -> bool:
	return LayoutLogic.layout_reachable(layout, cell)


static func populate_enemies(fort_id: String, layout: Dictionary, count: int, tier: int, cfg: Dictionary) -> Array:
	return LayoutLogic.populate_enemies(fort_id, layout, count, tier, cfg)


static func populate_piles(fort_id: String, layout: Dictionary, count: int) -> Array:
	return LayoutLogic.populate_piles(fort_id, layout, count)


static func near_exit(layout: Dictionary, p: Vector2, radius: float) -> int:
	return LayoutLogic.near_exit(layout, p, radius)


static func merge_walls(rects: Array) -> Array:
	return LayoutLogic.merge_walls(rects)


static func wall_touches_room(wall: Rect2, room: Rect2) -> bool:
	return LayoutLogic.wall_touches_room(wall, room)


static func checkpoint_entered(layout: Dictionary, prev_room: int, room: int) -> bool:
	return LayoutLogic.checkpoint_entered(layout, prev_room, room)


## Warden spec for a fort {id, tier, archetype?, first_dungeon?} (see WardenLogic.spec).
static func warden_spec(fort: Dictionary, cfg: Dictionary) -> Dictionary:
	return WardenLogic.spec(fort, cfg)
