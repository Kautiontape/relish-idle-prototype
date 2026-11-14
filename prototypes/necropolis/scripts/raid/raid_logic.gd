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


## What a scored circle raises from N orbs of total mass M. Test-only (Ledger.on_raise, see there).
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


## BALANCE 3's standard "party of tier T" against a world.json fort (DEV: the autopilot's P2/P3
## profiles; GameState seeds real runs). `fort` is the world.json entry {id, name, tier, cap}. The
## fort holds living = cap * autopilot.profile_living_frac and dead = cap * profile_dead_frac, its
## warden is wardens.by_fort's, the first_* flags are false, and there is no phylactery charge.
## The party comes from autopilot.party_profiles[party_tier] (clamped to 1..4):
## {garrison_units, starter_units, party: [{stats, name?, kind?, role?}]}. Validates as raid_seed.
static func profile_seed(fort: Dictionary, party_tier: int, cfg: Dictionary) -> Dictionary:
	var ap: Dictionary = cfg.get("autopilot", {})
	var profs: Dictionary = ap.get("party_profiles", {})
	var prof: Dictionary = profs.get(str(clampi(party_tier, 1, 4)), {})
	var div := float(cfg.get("mass", {}).get("garrison_mass_div", 10.0))
	var units := clampi(int(prof.get("garrison_units", 0)), 0, int(cfg.get("mass", {}).get("garrison_max", 12)))
	var tier := clampi(int(fort.get("tier", 1)), 1, 4)
	var cap := float(fort.get("cap", 100.0))
	var fid := str(fort.get("id", ""))
	var arche := str(cfg.get("wardens", {}).get("by_fort", {}).get(fid, WardenLogic.DEFAULT_ARCHETYPE))
	var party: Array = []
	var entries: Array = prof.get("party", [])
	for i in entries.size():
		var e: Dictionary = entries[i]
		var st: Dictionary = e.get("stats", {})
		party.append({"uid": "p%d" % (i + 1), "name": str(e.get("name", "Profile big %d" % (i + 1))),
			"kind": str(e.get("kind", "hulk")), "role": str(e.get("role", "brute")),
			"stats": {"power": float(st.get("power", 0.0)), "beef": float(st.get("beef", 0.0)),
				"wits": float(st.get("wits", 0.0)), "presence": float(st.get("presence", 0.0)),
				"speed": float(st.get("speed", 0.0))}})
	return {
		"v": 2, "kind": "raid", "run_id": 0, "seed_rev": 0, "rng_seed": "1",
		"fort": {"id": fid, "name": str(fort.get("name", fid)), "tier": tier, "cap": cap,
			"first_clear": false, "first_dungeon": false, "clears_since_retaken": 0, "yield_mult": 1.0},
		"living": cap * float(ap.get("profile_living_frac", 0.85)), "dead": cap * float(ap.get("profile_dead_frac", 0.0)),
		"undead": float(units) * div,
		"garrison_units": units, "garrison_in_mass": float(units) * div, "garrison_mass_div": div,
		"starter_units": maxi(0, int(prof.get("starter_units", 0))), "party": party,
		"digest_q": 1.0, "phylactery_charges": 0, "phylactery_max_per_dungeon": 1, "clones_ready": 0,
		"warden": {"archetype": arche, "tier": tier}, "warden_spec": {},
		"loot_table_id": "t%d.%s" % [tier, arche], "loot_hint": "", "chest_husk": false, "watchtower": false,
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


## `found` with `add` (the loot shape) merged in: relics add, arrays append, essence is skipped
## (it is the carried cluster, counted when the loot is banked). A new dictionary; inputs unchanged.
static func merge_loot(found: Dictionary, add: Dictionary) -> Dictionary:
	var out := found.duplicate(true)
	for k in add:
		if k == "essence":
			continue
		if add[k] is Array:
			var cur: Array = out.get(k, [])
			cur.append_array((add[k] as Array).duplicate(true))
			out[k] = cur
		elif k == "relics":
			out[k] = int(out.get(k, 0)) + int(add[k])
		else:
			out[k] = add[k]
	return out


## A deep copy of `found` (loot shape minus essence) in the full loot shape, with essence set to
## what Relish carries now: the checkpoint's banked loot (MECHANICS 7).
static func loot_snapshot(found: Dictionary, carried: int) -> Dictionary:
	var out := empty_loot()
	for k in out:
		if found.has(k) and k != "essence":
			out[k] = found[k].duplicate(true) if (found[k] is Array or found[k] is Dictionary) else found[k]
	out["essence"] = maxi(0, carried)
	return out


## What a close, a load or a crash pays (IDLE I5): the last checkpoint snapshot, as a deep copy in
## the full loot shape. Whatever was found since is lost, the same bound as a death.
static func close_loot(banked: Dictionary) -> Dictionary:
	var out := empty_loot()
	for k in out:
		if banked.has(k):
			out[k] = banked[k].duplicate(true) if (banked[k] is Array or banked[k] is Dictionary) else banked[k]
	return out


## How a window close mid-run ends a dungeon (IDLE I5: no run survives a close): as a retreat,
## unless an ending beat is already playing (`ended`, with `pending_exit` the exit it will emit):
## Relish's death beat (`relish_died`) or the warden's victory beat (`warden_beaten`). That ending
## happened while she was present, so it stands; a close can't turn a death or a win into a retreat.
static func close_exit(ended: bool, pending_exit: String) -> String:
	return pending_exit if ended and pending_exit in ["relish_died", "warden_beaten"] else "retreated"


## The exit an ending beat leaves pending when it starts: `chest_opened` (the warden's victory beat)
## -> warden_beaten, `relish_died` (her death beat) -> relish_died; "" for anything else.
static func pending_on(event: String) -> String:
	match event:
		"chest_opened":
			return "warden_beaten"
		"relish_died":
			return "relish_died"
	return ""


## How a window close finishes a dungeon run (RaidEndings.close_request): {exit (close_exit), closing}.
## `closing` (the result pays only the last checkpoint snapshot, RaidLogic.result_loot) is true for the
## retreat a close stands in for; an ending beat already playing finishes as that beat would have.
static func close_plan(ended: bool, pending_exit: String) -> Dictionary:
	var exit := close_exit(ended, pending_exit)
	return {"exit": exit, "closing": exit == "retreated"}


## The loot a raid result carries (RaidEndings.build_result): a retreat or a win banks everything found
## plus the carried motes, a death keeps the last checkpoint snapshot (`banked`), and a close
## (`closing`) pays that snapshot whatever the exit. Always the full loot shape; inputs unchanged.
static func result_loot(exit: String, closing: bool, found: Dictionary, carried: int, banked: Dictionary) -> Dictionary:
	var loot := loot_snapshot(found, carried) if exit in ["retreated", "warden_beaten"] else banked.duplicate(true)
	if closing:
		loot = close_loot(banked)
	if loot.is_empty():
		loot = empty_loot()
	return loot


## The warden is a target for an undead of `radius` at `pos` when it is within `reach` px of walking
## (LayoutLogic.walk_within: the same walking leash as the enemies; a straight line through a sealed
## wall does not count). RaidWardenRun.target_in delegates here.
static func warden_in_reach(layout: Dictionary, pos: Vector2, warden_pos: Vector2, reach: float, radius: float) -> bool:
	return LayoutLogic.walk_within(layout, pos, warden_pos, reach, radius)


## A held fort's counter-garrison is cleared when its last living enemy falls (IDLE I3).
## `living_left` counts the living still alive; `started` is true once the clear has fired.
static func held_clear_due(held: bool, boss: bool, living_left: int, started: bool) -> bool:
	return held and not boss and living_left <= 0 and not started


## A held fort with no living at all when the raid builds has no last kill to trigger the clear:
## it clears `held.empty_clear_s` after the build instead. That delay, or -1 when it does not apply
## (not held, the boss, or living spawned).
static func held_empty_clear_s(held: bool, boss: bool, living_spawned: int, cfg: Dictionary) -> float:
	if not held_clear_due(held, boss, living_spawned, false):
		return -1.0
	return maxf(0.0, float(cfg.get("held", {}).get("empty_clear_s", 1.0)))


static func held_banner(fort_name: String) -> String:
	return "COUNTER-GARRISON CLEARED" if fort_name == "" else "COUNTER-GARRISON CLEARED · %s holds" % fort_name


## The banner's second line: what the clear paid (the essence bonus counts as the motes that spawn).
static func held_payoff(loot: Dictionary) -> String:
	var c := loot_counts(loot)
	return "+%d relics · +%d remnants · +%d essence" % [int(c["relics"]), int(c["remnants"]), int(c["essence"])]


## The held_clear roll's essence bonus: how many fresh mass-0 motes the scene spawns.
static func held_motes(loot: Dictionary) -> int:
	return maxi(0, int(loot.get("essence", 0)))


## The checkpoint snapshot with its essence capped at what is still carried: motes circled into
## undead after the checkpoint are spent, so a death must not pay them out. A copy; an empty
## snapshot stays empty.
static func clamp_banked_essence(banked: Dictionary, carried: int) -> Dictionary:
	var out := banked.duplicate(true)
	if out.has("essence"):
		out["essence"] = mini(int(out["essence"]), maxi(0, carried))
	return out


## Item counts of a loot-shaped dictionary (relics, remnants, husks, blueprints) plus essence:
## `items` is the four without essence, `total` is all five. `{}` counts as zeros.
static func loot_counts(loot: Dictionary) -> Dictionary:
	var out := {"relics": int(loot.get("relics", 0)), "remnants": (loot.get("remnants", []) as Array).size(),
		"husks": (loot.get("husks", []) as Array).size(), "blueprints": (loot.get("blueprints", []) as Array).size(),
		"essence": int(loot.get("essence", 0))}
	out["items"] = int(out["relics"]) + int(out["remnants"]) + int(out["husks"]) + int(out["blueprints"])
	out["total"] = int(out["items"]) + int(out["essence"])
	return out


## What a death would lose right now (MECHANICS 7): found loot plus the carried essence, minus the
## last checkpoint snapshot (`banked`, {} before the first), as counts. Never negative.
static func unbanked(found: Dictionary, carried: int, banked: Dictionary) -> Dictionary:
	var f := loot_counts(found)
	var b := loot_counts(banked)
	var out := {}
	for k in ["relics", "remnants", "husks", "blueprints"]:
		out[k] = maxi(0, int(f[k]) - int(b[k]))
	out["essence"] = maxi(0, carried - int(b["essence"]))
	out["items"] = int(out["relics"]) + int(out["remnants"]) + int(out["husks"]) + int(out["blueprints"])
	out["total"] = int(out["items"]) + int(out["essence"])
	return out


## The first-dungeon ghost ring (and the autopilot's raise circle): the centroid of the motes within
## `reach_px` of Relish, and the radius to the farthest of them plus `pad_px`. {ok, center, radius,
## count}; ok is false with no mote in reach.
static func ghost_ring(mote_positions: Array, relish_pos: Vector2, reach_px: float, pad_px: float) -> Dictionary:
	var near: Array[Vector2] = []
	for p in mote_positions:
		if (p as Vector2).distance_to(relish_pos) <= reach_px:
			near.append(p)
	if near.is_empty():
		return {"ok": false, "center": relish_pos, "radius": 0.0, "count": 0}
	var c := Vector2.ZERO
	for p in near:
		c += p
	c /= float(near.size())
	var rad := 0.0
	for p in near:
		rad = maxf(rad, p.distance_to(c))
	return {"ok": true, "center": c, "radius": rad + pad_px, "count": near.size()}


## True when a phylactery charge is left to spend in this dungeon (MECHANICS 7).
static func can_revive(revived: int, seed: Dictionary) -> bool:
	return revives_left(revived, seed) > 0


## Phylactery charges still spendable this run: min(charges, max_per_dungeon) - revived.
static func revives_left(revived: int, seed: Dictionary) -> int:
	return maxi(0, mini(int(seed.get("phylactery_charges", 0)), int(seed.get("phylactery_max_per_dungeon", 0))) - revived)


## A BANKED / UNBANKED line from loot_counts / unbanked: the non-zero kinds only ("relics 1 ·
## remnants 2 · essence 5"); "" when every kind is zero (the HUD shows one dim word then).
static func loot_line(c: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in ["relics", "remnants", "husks", "blueprints", "essence"]:
		if int(c.get(k, 0)) > 0:
			parts.append("%s %d" % [k, int(c[k])])
	return " · ".join(parts)


## The 8-way compass word for a direction on the dungeon floor (y grows down, so N is up the screen):
## "N", "NE", "E", "SE", "S", "SW", "W", "NW"; "" for a zero vector.
static func compass(v: Vector2) -> String:
	if v.length() < 0.001:
		return ""
	var words := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
	var i := int(posmod(roundi(v.angle() / (PI / 4.0)), 8))
	return words[i]


## What a death would lose, as a phrase: "1 remnant + 5 essence at risk", "nothing at risk".
static func risk_phrase(c: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in ["relics", "remnants", "husks", "blueprints"]:
		var n := int(c.get(k, 0))
		if n > 0:
			parts.append("%d %s" % [n, k if n > 1 else k.trim_suffix("s")])
	if int(c.get("essence", 0)) > 0:
		parts.append("%d essence" % int(c["essence"]))
	return "nothing at risk" if parts.is_empty() else " + ".join(parts) + " at risk"


## The push-or-retreat line (D-b review MF-5): "LIVING 6 left · exit W, 2 rooms · 1 remnant at risk".
## `at_exit`: Relish stands at an exit ("AT EXIT"). Otherwise `exit_word` is the compass word of the
## way to the nearest exit (the first step of its route, so never through a wall), "" when there is
## none (the clause is dropped); `hops` the rooms between her room and the exit's (0 this room, -1
## unknown: a doorway band).
static func push_line(living: int, exit_word: String, hops: int, at_risk: Dictionary, at_exit := false, rooms_seen := 0, rooms_total := 0) -> String:
	var parts: PackedStringArray = []
	if rooms_total > 0:
		parts.append(rooms_phrase(rooms_seen, rooms_total))
	parts.append("LIVING %d left" % maxi(0, living))
	if at_exit:
		parts.append("AT EXIT")
	elif exit_word != "":
		parts.append("exit " + exit_word + ("" if hops <= 0 else (", next room" if hops == 1 else ", %d rooms" % hops)))
	parts.append(risk_phrase(at_risk))
	return " · ".join(parts)


## The run's shape: "3 of 7 rooms seen" (rooms Relish has stood in, of the layout's rooms). Seen, not
## cleared: a room can be crossed with the living still in it. Never below 1 once she is in one.
static func rooms_phrase(seen: int, total: int) -> String:
	return "%d of %d rooms seen" % [clampi(seen, 0, maxi(0, total)), maxi(0, total)]


## What the death card says killed her: `src` is Relish.last_hit_src ("slam", "lunge", "bash", "fire", "hound", "living", or ""
## when nothing named it, e.g. a dev kill), `warden_name` the warden's spec name ("The Bellringer").
static func death_cause(src: String, warden_name: String) -> String:
	var who := warden_name if warden_name != "" else "The warden"
	match src:
		"slam":
			return "%s's slam" % who
		"lunge":
			return "%s's lunge" % who
		"bash":
			return "%s's bash" % who
		"rush":
			return "%s's rush" % who
		"fire":
			return "%s's fire" % who
		"hound":
			return "%s's hounds" % who
		"pack":
			return "%s's pack" % who
		"living":
			return "the living"
	return "a wound"


## The tell the killing attack showed, for the death card (D-d/E 3c: "missed: the swing"): the
## Bellringer's clapper swing, the Huntsman's locked line, the Shieldwall's lit arc (bash or rush), the
## Pyre-priest's marked ground. "" for a source with no one-beat tell (a pack, the living, a wound).
static func death_tell(src: String) -> String:
	match src:
		"slam":
			return "the swing"
		"lunge":
			return "the line"
		"bash", "rush":
			return "the lit arc"
		"fire":
			return "the marked ground"
	return ""


## The death card's KILLED BY text: the cause, then the tell she missed when the attack had one
## ("The Bellringer's slam · missed: the swing").
static func death_line(src: String, warden_name: String) -> String:
	var tell := death_tell(src)
	var cause := death_cause(src, warden_name)
	return cause if tell == "" else "%s · missed: %s" % [cause, tell]


## What she loses with the party: the unbanked loot ("relics 1 · essence 4") and the big undead of the
## party (a death costs the whole party; the garrison and raised survive). "nothing" when neither.
static func death_lost_line(unbanked: Dictionary, party_n: int) -> String:
	var parts: PackedStringArray = []
	var l := loot_line(unbanked)
	if l != "":
		parts.append(l)
	if party_n > 0:
		parts.append("%d big undead" % party_n)
	return "nothing" if parts.is_empty() else " · ".join(parts)


## The death card's rows [{label, text, key}] (key: a Palette key): who killed her, what the last
## checkpoint banked, what is lost.
static func death_card_rows(cause: String, banked_counts: Dictionary, unbanked: Dictionary, party_n: int) -> Array:
	var bl := loot_line(banked_counts)
	var lost := death_lost_line(unbanked, party_n)
	return [
		{"label": "KILLED BY", "text": cause, "key": "danger"},
		{"label": "BANKED", "text": bl if bl != "" else "nothing", "key": "text" if bl != "" else "text_dim"},
		{"label": "LOST", "text": lost, "key": "danger" if lost != "nothing" else "text_dim"},
	]


## How much loose essence can still be banked: what lies loose, capped by the carry room left.
static func bankable(loose: int, carried: int, cfg: Dictionary) -> int:
	return mini(maxi(0, loose), carry_room(carried, cfg))


## An angle for a new mark on a ring that already has marks at `taken`: `want` when nothing lies
## within `sep` of it, else the first of want + sep, want + 2 sep, ... that is clear (want itself
## when the ring is full). Keeps marks countable when they keep coming from the same side.
static func spread_angle(want: float, taken: PackedFloat32Array, sep: float) -> float:
	var steps := maxi(1, ceili(TAU / maxf(0.01, sep)))
	for k in steps:
		var a := want + sep * k
		var clear := true
		for t in taken:
			if absf(angle_difference(a, t)) < sep - 0.0001:
				clear = false
				break
		if clear:
			return wrapf(a, -PI, PI)
	return wrapf(want, -PI, PI)


## The antechamber's last-chance banner, with the loose essence lit there (D-b review SF-4).
static func last_chance_banner(lit: int) -> String:
	return "LAST CHANCE · a free trance" + ("" if lit <= 0 else " · %d loose essence to gather" % lit)


## The held-fort clear's effect on the map (D-b review SF-5): the counter-garrison mass this run
## killed comes off the fort's living.
static func held_map_effect(killed_mass: float) -> String:
	return "on the map: counter-garrison −%d" % roundi(maxf(0.0, killed_mass))


## How exposed Relish is, 0..1, for her halo's danger rim. 0 while a phylactery charge is left.
## With none, a faint `danger.exposed_min` at full hp rising to `exposed_max` as her hp falls: a hit
## still has to get through the sacrifice chain and her hp first, so this is a rim, never an alarm
## (day 1 starts with no charges, and a steady strong halo would be noise).
static func exposed_level(phyl_left: int, hp_frac: float, cfg: Dictionary) -> float:
	if phyl_left > 0:
		return 0.0
	var d: Dictionary = cfg.get("danger", {})
	return lerpf(float(d.get("exposed_min", 0.2)), float(d.get("exposed_max", 1.0)), 1.0 - clampf(hp_frac, 0.0, 1.0))


## How far an exposed_level sits from the faint full-hp rim (0) to the strong no-hp one (1): the
## PHYLACT. words lean from text_dim to danger by it, as the halo does.
static func exposed_tint(level: float, cfg: Dictionary) -> float:
	var d: Dictionary = cfg.get("danger", {})
	return clampf(inverse_lerp(float(d.get("exposed_min", 0.2)), float(d.get("exposed_max", 1.0)), level), 0.0, 1.0)


## The PHYLACT. row's words: "" while a charge is left; with none, what a death would mean (true
## whatever her hp: the chain and her hp still stand between her and it).
static func phylactery_word(phyl_left: int) -> String:
	return "" if phyl_left > 0 else "NO REVIVE · death ends the run"


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


## The angle of a carried-cluster slot around Relish: the position that COUNTS (enclosure, the bot's
## aim, the absorb streak). It reads no animation state, so reduced motion cannot change a raid.
static func carry_slot_angle(slot: int, slots: int) -> float:
	return -PI * 0.5 + TAU * slot / float(maxi(1, slots))


## The swing the cluster is DRAWN rocking through at sim time `t`: a sine of at most `swing_rad`
## either way (0 under reduced motion), so a drawn mote stays within ~orbit * swing_rad px of the
## slot it counts at. Draw only: nothing that scores, aims or collides may read it.
static func carry_draw_spin(t: float, rad_s: float, swing_rad: float, reduced: bool) -> float:
	return 0.0 if reduced else sin(t * rad_s) * swing_rad


## The most a drawn carried mote can be from where it counts, in px (the knob the swing is made from).
static func carry_swing_rad(swing_px: float, orbit_px: float) -> float:
	return swing_px / maxf(1.0, orbit_px)


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
## TEST-ONLY v1 result builder: no scene uses it any more (the dungeon is LedgerV2, the boss has its
## own result). Kept because tests/test_results.gd (from_v1) builds its v1 fixture with it; delete it
## with that fixture. Tracks how in-scene events map onto the abstract map-mass result dict.
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


## D-d/E Step 3: the guarded detour's site and guard (LayoutLogic.detour_site / detour_guard).
static func detour_site(layout: Dictionary, tier: int, cfg: Dictionary) -> Dictionary:
	return LayoutLogic.detour_site(layout, tier, cfg)


static func detour_guard(fort_id: String, layout: Dictionary, tier: int, cfg: Dictionary) -> Array:
	return LayoutLogic.detour_guard(fort_id, layout, tier, cfg)


## The measuring bot's detour rule (raid.json autopilot detour_*; NOTES-RAID "the detour rule"): take the
## cache when her hp fraction is at least `detour_hp_frac` (`detour_hp_frac_revive` with a revive left) and
## her army is at least `detour_army_mult` times the guard she can see.
static func detour_take(hp_frac: float, revives: int, allies: int, guard: int, ap: Dictionary) -> bool:
	var need := float(ap.get("detour_hp_frac_revive", 0.4)) if revives > 0 else float(ap.get("detour_hp_frac", 0.6))
	return hp_frac >= need and float(allies) >= float(ap.get("detour_army_mult", 1.5)) * float(guard)


## On the way in: turn back when her hp fraction is below `detour_retreat_hp_frac` (`..._revive` with a
## revive left) or her army is below `detour_retreat_army_mult` times the guard still standing.
static func detour_retreat(hp_frac: float, revives: int, allies: int, guard: int, ap: Dictionary) -> bool:
	var floor_hp := float(ap.get("detour_retreat_hp_frac_revive", 0.3)) if revives > 0 else float(ap.get("detour_retreat_hp_frac", 0.5))
	return hp_frac < floor_hp or float(allies) < float(ap.get("detour_retreat_army_mult", 1.0)) * float(guard)


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


# ------------------------------------------------------ the run's time split ---
## The measuring bot's time split (D-d/E; NOTES-RAID "Run length and risk calibration"): every physics
## tick of a live run goes to one bucket, the first that matches: "trance" (the trance is open),
## "fight" (something is engaged, `foe_engaged` or an awake warden), "travel" (Relish moved more than
## `move_px` this tick), else "idle". The bot never opens the trance (its raise is instant), so its
## trance share is 0 by construction.
const SPLIT_BUCKETS := ["travel", "fight", "trance", "idle"]


static func time_class(in_trance: bool, engaged: bool, moved_px: float, move_px: float) -> String:
	if in_trance:
		return "trance"
	if engaged:
		return "fight"
	if moved_px > move_px:
		return "travel"
	return "idle"


## A living foe is engaged once it is hostile (aggro'd: it never calms) and stands in Relish's room
## (`rel_room` >= 0, a doorway band is no room) or within `fight_px` of her, wherever the wall is.
static func foe_engaged(rel_pos: Vector2, rel_room: int, foe_pos: Vector2, foe_room: int, hostile: bool, fight_px: float) -> bool:
	if not hostile:
		return false
	if rel_room >= 0 and foe_room == rel_room:
		return true
	return rel_pos.distance_to(foe_pos) <= fight_px


## The measuring bot's reaction rule (raid.json autopilot react_*): a value set at a few target scores,
## linear between them and clamped outside (`pts` ascending, `vals` the same length). Empty: 0.
static func react_at(score: float, pts: Array, vals: Array) -> float:
	var n := mini(pts.size(), vals.size())
	if n == 0:
		return 0.0
	if score <= float(pts[0]):
		return float(vals[0])
	for i in range(1, n):
		if score <= float(pts[i]):
			var f := (score - float(pts[i - 1])) / maxf(1e-9, float(pts[i]) - float(pts[i - 1]))
			return lerpf(float(vals[i - 1]), float(vals[i]), f)
	return float(vals[n - 1])
