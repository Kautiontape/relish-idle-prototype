class_name RaidLogic
extends RefCounted
## Pure raid logic: mass-ledger math, tier mappings, and the seeded fortress
## layout generator. No scene-tree or autoload dependencies — every function
## takes a cfg Dictionary (parsed configs/raid.json) so tests run headless.


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


# ------------------------------------------------------ layout generation ----
## Deterministic per fort_id: each fortress is recognizably itself on revisits.
## Returns { size, wall_t, walls (all Rect2), inner_walls, doors, rooms, spawn }.
static func gen_layout(fort_id: String, tier: int, is_boss: bool, cfg: Dictionary) -> Dictionary:
	var lay: Dictionary = cfg.get("layout", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(fort_id)
	var last := {}
	for attempt in 8:
		last = _gen_once(rng, tier, is_boss, lay)
		if layout_reachable(last, float(lay.get("grid_cell", 32.0))):
			return last
	return last


static func _gen_once(rng: RandomNumberGenerator, tier: int, is_boss: bool, lay: Dictionary) -> Dictionary:
	var w: float
	var h: float
	if is_boss:
		w = float(lay.get("boss_w", 2600))
		h = float(lay.get("boss_h", 1800))
	else:
		var tk := str(clampi(tier, 1, 4))
		w = float((lay.get("tier_w", {}) as Dictionary).get(tk, 1400))
		h = float((lay.get("tier_h", {}) as Dictionary).get(tk, 1000))
	var t := float(lay.get("wall_thickness", 30.0))
	var door_w := float(lay.get("door_width", 150.0))

	# --- doors: 2+tier gaps around the perimeter, south always served first ---
	var n_doors := int(lay.get("boss_doors", 7)) if is_boss else 2 + tier
	var sides: Array = []
	if is_boss:
		sides = ["s", "s", "s", "n", "e", "w", "s"]
		while sides.size() > n_doors:
			sides.pop_back()
		while sides.size() < n_doors:
			sides.append(["e", "w", "n"][sides.size() % 3])
	else:
		var order := ["s", "n", "e", "w"]
		for i in n_doors:
			sides.append(order[i % 4])
	var doors: Array = []
	for side in ["s", "n", "e", "w"]:
		var k: int = sides.count(side)
		if k == 0:
			continue
		var span := (w if (side == "s" or side == "n") else h) - 2.0 * (t + 70.0)
		var slot := span / k
		for i in k:
			var lo := (t + 70.0) + slot * i + 30.0
			var hi := (t + 70.0) + slot * (i + 1) - door_w - 30.0
			var a := rng.randf_range(lo, maxf(lo, hi))
			doors.append(_mk_door(side, a, door_w, w, h, t))

	# --- outer walls minus door gaps ---
	var walls: Array = []
	walls.append_array(_side_segments("s", doors, w, h, t))
	walls.append_array(_side_segments("n", doors, w, h, t))
	walls.append_array(_side_segments("e", doors, w, h, t))
	walls.append_array(_side_segments("w", doors, w, h, t))

	# --- internal partitions: BSP into 2+tier rooms with wide gap doorways ---
	var interior := Rect2(t, t, w - 2.0 * t, h - 2.0 * t)
	var min_room := float(lay.get("min_room_px", 300.0))
	var gap_w := float(lay.get("inner_gap_width", 165.0))
	var inner_walls: Array = []
	var rooms: Array = []
	if is_boss:
		# the north zone stays one open audience chamber for Vei
		var split_y := t + (h - 2.0 * t) * 0.42
		var south := Rect2(t, split_y, w - 2.0 * t, h - t - split_y)
		rooms = _bsp([south], int(lay.get("boss_rooms", 4)) - 1, min_room, gap_w, t, rng, inner_walls)
		rooms.push_front(Rect2(t, t, w - 2.0 * t, split_y - t))
	else:
		rooms = _bsp([interior], 2 + tier, min_room, gap_w, t, rng, inner_walls)
	walls.append_array(inner_walls)

	# --- Relish spawns just inside the southernmost door ---
	var s_door := {}
	for d in doors:
		if d["side"] == "s":
			if s_door.is_empty() or (is_boss and absf(d["center"].x - w * 0.5) < absf(s_door["center"].x - w * 0.5)):
				s_door = d
	if s_door.is_empty():
		s_door = doors[0]
	var spawn: Vector2 = Vector2(s_door["center"].x, h - t - 70.0)

	return {"size": Vector2(w, h), "wall_t": t, "walls": walls,
		"inner_walls": inner_walls, "doors": doors, "rooms": rooms,
		"spawn": spawn, "boss": is_boss}


static func _mk_door(side: String, along: float, dw: float, w: float, h: float, t: float) -> Dictionary:
	match side:
		"s":
			return {"side": "s", "rect": Rect2(along, h - t, dw, t),
				"center": Vector2(along + dw * 0.5, h - t * 0.5),
				"inner": Vector2(along + dw * 0.5, h - t - 50.0)}
		"n":
			return {"side": "n", "rect": Rect2(along, 0.0, dw, t),
				"center": Vector2(along + dw * 0.5, t * 0.5),
				"inner": Vector2(along + dw * 0.5, t + 50.0)}
		"w":
			return {"side": "w", "rect": Rect2(0.0, along, t, dw),
				"center": Vector2(t * 0.5, along + dw * 0.5),
				"inner": Vector2(t + 50.0, along + dw * 0.5)}
	return {"side": "e", "rect": Rect2(w - t, along, t, dw),
		"center": Vector2(w - t * 0.5, along + dw * 0.5),
		"inner": Vector2(w - t - 50.0, along + dw * 0.5)}


## One perimeter side as wall segments with this side's door intervals cut out.
static func _side_segments(side: String, doors: Array, w: float, h: float, t: float) -> Array:
	var horizontal := side == "s" or side == "n"
	var lo := t if horizontal else 0.0          # N/S walls sit between E/W walls
	var hi := (w - t) if horizontal else h      # E/W walls run the full height
	var cuts: Array = []
	for d in doors:
		if d["side"] != side:
			continue
		var r: Rect2 = d["rect"]
		cuts.append([r.position.x, r.end.x] if horizontal else [r.position.y, r.end.y])
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var segs: Array = []
	var x := lo
	for c in cuts:
		if c[0] - x > 8.0:
			segs.append(_band_rect(side, x, c[0], w, h, t))
		x = maxf(x, c[1])
	if hi - x > 8.0:
		segs.append(_band_rect(side, x, hi, w, h, t))
	return segs


static func _band_rect(side: String, a: float, b: float, w: float, h: float, t: float) -> Rect2:
	match side:
		"s":
			return Rect2(a, h - t, b - a, t)
		"n":
			return Rect2(a, 0.0, b - a, t)
		"w":
			return Rect2(0.0, a, t, b - a)
	return Rect2(w - t, a, t, b - a)


## Split leaves until `target` rooms exist; each split line becomes a wall with
## 1-2 wide gaps (multiple routes, never a single corridor).
static func _bsp(leaves: Array, target: int, min_room: float, gap_w: float, t: float,
		rng: RandomNumberGenerator, out_walls: Array) -> Array:
	var ls: Array = leaves.duplicate()
	while ls.size() < target:
		var bi := -1
		var ba := 0.0
		for i in ls.size():
			var r: Rect2 = ls[i]
			if maxf(r.size.x, r.size.y) >= 2.0 * min_room + t and r.get_area() > ba:
				ba = r.get_area()
				bi = i
		if bi < 0:
			break
		var r: Rect2 = ls[bi]
		ls.remove_at(bi)
		var vert := r.size.x >= r.size.y
		var dim := r.size.x if vert else r.size.y
		var cut := clampf(rng.randf_range(0.42, 0.58) * dim, min_room, dim - min_room)
		if vert:
			var x := r.position.x + cut
			_wall_with_gaps(Rect2(x - t * 0.5, r.position.y, t, r.size.y), gap_w, rng, out_walls)
			ls.append(Rect2(r.position, Vector2(cut - t * 0.5, r.size.y)))
			ls.append(Rect2(Vector2(x + t * 0.5, r.position.y), Vector2(r.size.x - cut - t * 0.5, r.size.y)))
		else:
			var y := r.position.y + cut
			_wall_with_gaps(Rect2(r.position.x, y - t * 0.5, r.size.x, t), gap_w, rng, out_walls)
			ls.append(Rect2(r.position, Vector2(r.size.x, cut - t * 0.5)))
			ls.append(Rect2(Vector2(r.position.x, y + t * 0.5), Vector2(r.size.x, r.size.y - cut - t * 0.5)))
	return ls


static func _wall_with_gaps(band: Rect2, gap_w: float, rng: RandomNumberGenerator, out_walls: Array) -> void:
	var horizontal := band.size.x >= band.size.y
	var lo := band.position.x if horizontal else band.position.y
	var hi := band.end.x if horizontal else band.end.y
	var length := hi - lo
	var n_gaps := 2 if length > 620.0 else 1
	var margin := 40.0
	var span := length - 2.0 * margin
	var slot := span / n_gaps
	var x := lo
	for i in n_gaps:
		var glo := lo + margin + slot * i + 10.0
		var ghi := lo + margin + slot * (i + 1) - gap_w - 10.0
		var g := rng.randf_range(glo, maxf(glo, ghi))
		if g - x > 10.0:
			out_walls.append(_sub_band(band, horizontal, x, g))
		x = g + gap_w
	if hi - x > 10.0:
		out_walls.append(_sub_band(band, horizontal, x, hi))


static func _sub_band(band: Rect2, horizontal: bool, a: float, b: float) -> Rect2:
	if horizontal:
		return Rect2(a, band.position.y, b - a, band.size.y)
	return Rect2(band.position.x, a, band.size.x, b - a)


# ------------------------------------------------------------ reachability ---
## Flood fill on a coarse grid: every room center and every door must be
## walkable from the spawn point.
static func layout_reachable(layout: Dictionary, cell: float) -> bool:
	var size: Vector2 = layout["size"]
	var cols := int(ceil(size.x / cell))
	var rows := int(ceil(size.y / cell))
	if cols <= 0 or rows <= 0:
		return false
	var blocked := PackedByteArray()
	blocked.resize(cols * rows)
	for wrect in layout["walls"]:
		var r: Rect2 = wrect
		var x0 := clampi(int(r.position.x / cell), 0, cols - 1)
		var x1 := clampi(int((r.end.x - 0.01) / cell), 0, cols - 1)
		var y0 := clampi(int(r.position.y / cell), 0, rows - 1)
		var y1 := clampi(int((r.end.y - 0.01) / cell), 0, rows - 1)
		for cy in range(y0, y1 + 1):
			for cx in range(x0, x1 + 1):
				blocked[cy * cols + cx] = 1
	var start := _cell_index(layout["spawn"], cell, cols, rows)
	if blocked[start] == 1:
		return false
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	seen[start] = 1
	var queue := [start]
	var qi := 0
	while qi < queue.size():
		var c: int = queue[qi]
		qi += 1
		var cx := c % cols
		var cy := c / cols
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + d[0]
			var ny: int = cy + d[1]
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var ni := ny * cols + nx
			if seen[ni] == 0 and blocked[ni] == 0:
				seen[ni] = 1
				queue.append(ni)
	for room in layout["rooms"]:
		if seen[_cell_index((room as Rect2).get_center(), cell, cols, rows)] == 0:
			return false
	for d in layout["doors"]:
		if seen[_cell_index(d["inner"], cell, cols, rows)] == 0:
			return false
	return true


static func _cell_index(p: Vector2, cell: float, cols: int, rows: int) -> int:
	var cx := clampi(int(p.x / cell), 0, cols - 1)
	var cy := clampi(int(p.y / cell), 0, rows - 1)
	return cy * cols + cx


# ------------------------------------------------------------- population ----
## Enemy placement: rooms weighted away from the spawn; never right on top of
## Relish. Deterministic per fort (rng chained off fort_id).
static func populate_enemies(fort_id: String, layout: Dictionary, count: int, tier: int,
		cfg: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(fort_id) * 31 + 7919
	var spawn: Vector2 = layout["spawn"]
	var rooms: Array = layout["rooms"]
	var weights: Array = []
	var total := 0.0
	for r in rooms:
		var d: float = (r as Rect2).get_center().distance_to(spawn)
		var wt := pow(maxf(d, 40.0), 1.5)
		weights.append(wt)
		total += wt
	var out: Array = []
	for i in count:
		var roll := rng.randf() * total
		var ri := 0
		for j in weights.size():
			roll -= weights[j]
			if roll <= 0.0:
				ri = j
				break
		var room: Rect2 = rooms[ri]
		var inner := room.grow(-70.0) if room.size.x > 200.0 and room.size.y > 200.0 else room.grow(-30.0)
		var pos := Vector2.ZERO
		for attempt in 20:
			pos = Vector2(rng.randf_range(inner.position.x, inner.end.x),
				rng.randf_range(inner.position.y, inner.end.y))
			if pos.distance_to(spawn) > 320.0:
				break
		out.append({"kind": roll_enemy_kind(rng, tier, cfg), "pos": pos, "room": ri})
	return out


## Corpse piles scattered anywhere open.
static func populate_piles(fort_id: String, layout: Dictionary, count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(fort_id) * 17 + 977
	var rooms: Array = layout["rooms"]
	var out: Array = []
	for i in count:
		var room: Rect2 = rooms[rng.randi_range(0, rooms.size() - 1)]
		var inner := room.grow(-60.0) if room.size.x > 180.0 and room.size.y > 180.0 else room.grow(-24.0)
		out.append(Vector2(rng.randf_range(inner.position.x, inner.end.x),
			rng.randf_range(inner.position.y, inner.end.y)))
	return out
