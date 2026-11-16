class_name StandinResolver
extends RefCounted
## E3-6a: a headless stand-in for the dungeon scene (BALANCE §8, IDLE §8). The autoplayer (E3-6b) can't run the
## dungeon headless, so it turns a real dungeon seed (STATE-API §7.1, as cmd_begin_dungeon issued it) into a raid
## result v2 (§8.1) that passes Results.validate and the real apply_result, with outcomes, loot and masses drawn from
## what the dungeon unit measured (configs/balance_standins.json). A test harness, not game logic: nothing under
## scripts/ reads it or the stand-ins. Static, no Engine, no autoloads. It calls the dungeon's pure static code read-only
## and copies none of it: RaidLoot's rolls (scaled_count, chest, held_clear, first_blueprint) and its loot-table readers
## _remnant and _by_tier (underscore-named: private by convention, called read-only because no public reader returns
## a typed remnant or a tier's husk kinds), RaidLogic's mass mappings, revive count, held-door rule and score class,
## and RaidLogic.LedgerV2, the scene's own result builder.
##
## resolve(seed, standins, cfgs, opts) -> {result: Dictionary, duration_s: float, died: bool, notes: Dictionary}
## - `standins`: balance_standins.json, parsed. `cfgs`: the parsed configs (GameState.load_configs), raid and loot.
## - `opts`: `deaths` "human" (default) or "frozen" (death_rate_frozen: E3-6b's sensitivity pass); `door` (default
##   false): the bot sends a spare big through the held door when the gate allows; `held` (default false): the fort
##   was held when the run began. The seed has no such key (the run records it, StateRuns.open_run, and the scene
##   reads view_fort live), so the caller passes view_fort(id).held at issue; `blueprints` (default []): the
##   blueprints owned, for the chest's first-clear pick (the scene reads view_inventory).
## - Deterministic: its rng is seeded from seed.rng_seed ^ SALT, so the same seed gives a byte-identical result.
##
## The entry: "held" with opts.held (the tier's entry with the held GUESSes), else "first_dungeon" with
## seed.fort.first_dungeon, else "held_door" when the door is taken (door_pick), else the tier's, "1".."4".
## The outcome: a death at death_rate (death_rate_frozen with deaths "frozen"; × held.death_rate_mult when held). A
## death the seed has a phylactery charge for (RaidLogic.can_revive: at most min(phylactery_charges,
## phylactery_max_per_dungeon) in a run) revives her in place (revived_in_place +1), and the rest of the run rolls
## again at the same rate. Otherwise the warden is beaten, or a held fort's counter-garrison is cleared (retreated).
## The bot never retreats a fresh fort and never times out: the frozen bot's own retreats (left with no army; t1 3 of
## 48 rows, t2 and t3 1 of 60, t4 0) and timeouts (0 in every row) fold into the clear, so the flip rate is
## 1 - death_rate.
## Duration: the entry's duration_s (× held.duration_mult), or death_t_frac of it on a death.
## Loot: each kind's count is RaidLoot.scaled_count(rng, mean_loot × (kept_frac on a death), seed.fort.yield_mult),
## as the scene scales its drops; essence is the motes she carried, not a drop, and the scene doesn't scale it, so it
## counts at 1.0. Typed items come from the seed's loot table, t<tier>.<archetype>: remnants by RaidLoot._remnant,
## husk kinds from the tier's chest_by_tier husk_kinds, blueprints by RaidLoot.first_blueprint. On a win the chest's
## unscaled part is RaidLoot.chest at yield 0 with the seed's first_clear and chest_husk: the first-clear blueprint (a
## relic when all are owned) and the first dungeon's husk. A held fort's clear is RaidLoot.held_clear; its death
## banks nothing.
## Masses (the rows carry no raised, chaff or garrison mass: BALANCE §8's GUESSes): killed = killed_frac × the seed's
## living (exactly the living on a held clear, so the writeback raises counter_garrison_cleared). One raised bucket at
## standins.score: count = raised_per_living_unit × RaidLogic.enemy_count(seed); fresh mass = count ×
## RaidLogic.mass_per_enemy, capped at killed + the seed's dead (raised_count counts re-raises of recycled motes, which
## carry no fresh mass, so the cap binds). Survivors: the garrison taken in × garrison_survive_frac, and
## raised_survivors_per_living_unit × enemy_count raised units of mass_per_enemy each, by RaidLogic.score_class:
## score 70 is a soldier, which stays at the fort, so chaff_mass is 0 by the dungeon's own rule (LedgerV2: chaff
## leaves with Relish, garrison stays, both bound by the garrison taken in plus the mass raised).
## Party: on a win each member is lost at party_lost_per_member (× held.party_lost_mult when held), the held door's
## big excepted (it sits the fight out); the door's big is lost by RaidLogic.held_door_lost (a death or a retreat,
## never a win); on a death LedgerV2 lists the whole party, as the writeback loses it anyway.

const SALT := 0x57A7D1E5
const TABLES := ["1", "2", "3", "4", "first_dungeon", "held_door"]
const KINDS := ["relics", "remnants", "husks", "blueprints", "essence"]
## Every key the resolver reads, with no fallback (GameState.REQUIRED's style): problem() checks a file has each,
## and a read of one that is missing is reported loudly (push_error) and reads as 0, never a silent default.
const TOP_KEYS := ["v", "measured_at", "score", "held"]
const ENTRY_KEYS := ["death_rate", "death_rate_frozen", "duration_s", "duration_s_frozen", "death_t_frac", "mean_loot",
	"kept_frac", "mass", "party_lost_per_member", "revives", "source"]
const MASS_KEYS := ["killed_frac", "raised_per_living_unit", "garrison_survive_frac", "raised_survivors_per_living_unit"]
const HELD_KEYS := ["death_rate_mult", "duration_mult", "party_lost_mult", "source"]


## "" when `s` has every key the resolver reads, else the first one missing.
static func problem(s: Dictionary) -> String:
	for k in TOP_KEYS:
		if not s.has(k):
			return "balance_standins has no %s" % k
	for k in HELD_KEYS:
		if not (s["held"] is Dictionary and (s["held"] as Dictionary).has(k)):
			return "balance_standins held has no %s" % k
	for name in TABLES:
		if not (s.get(name) is Dictionary):
			return "balance_standins has no entry %s" % name
		var e: Dictionary = s[name]
		for k in ENTRY_KEYS:
			if not e.has(k):
				return "balance_standins %s has no %s" % [name, k]
		for part in ["mean_loot", "kept_frac"]:
			for k in KINDS:
				if not (e[part] is Dictionary and (e[part] as Dictionary).has(k)):
					return "balance_standins %s.%s has no %s" % [name, part, k]
		for ex in ["won", "died"]:
			for k in MASS_KEYS:
				var m: Variant = (e["mass"] as Dictionary).get(ex) if e["mass"] is Dictionary else null
				if not (m is Dictionary and (m as Dictionary).has(k)):
					return "balance_standins %s.mass.%s has no %s" % [name, ex, k]
	return ""


static func _req(d: Dictionary, key: String, where: String) -> Variant:
	if not d.has(key):
		push_error("StandinResolver: balance_standins %s is missing" % (key if where == "" else where + "." + key))
		return null
	return d[key]


static func _f(d: Dictionary, key: String, where: String) -> float:
	var v: Variant = _req(d, key, where)
	return float(v) if v is float or v is int else 0.0


static func _d(d: Dictionary, key: String, where: String) -> Dictionary:
	var v: Variant = _req(d, key, where)
	return v if v is Dictionary else {}


## The held door's gate (raid.json held_door; NOTES-RAID "D-e task 6"): only with opts.door, never at the first
## dungeon or a held fort, only on a fort whose tier is in held_door.tiers (t2: vespers, lantern-keep, chime-fort),
## and only when the dungeon's own rule spends a big (RaidLogic.held_door_pick: at least autopilot.door_min_bigs
## bigs, and the counter to this warden's weak point kept; one big always declines). The index in seed.party of the
## big spent, or -1.
static func door_pick(seed: Dictionary, rcfg: Dictionary, opts: Dictionary) -> int:
	var fort: Dictionary = seed.get("fort", {})
	if not bool(opts.get("door", false)) or bool(opts.get("held", false)) or bool(fort.get("first_dungeon", false)):
		return -1
	var gated := false
	for x in (rcfg.get("held_door", {}) as Dictionary).get("tiers", []):
		gated = gated or int(x) == int(fort.get("tier", 0))
	if not gated:
		return -1
	var arche := str((seed.get("warden", {}) as Dictionary).get("archetype", ""))
	var archetypes: Dictionary = (rcfg.get("wardens", {}) as Dictionary).get("archetypes", {})
	var wp: Dictionary = (archetypes.get(arche, {}) as Dictionary).get("weak_point", {})
	var vals: Array = []
	for p in seed.get("party", []):
		vals.append(float(((p as Dictionary).get("stats", {}) as Dictionary).get(str(wp.get("stat", "")), 0.0)))
	return RaidLogic.held_door_pick(vals, float(wp.get("threshold", 0.0)), rcfg.get("autopilot", {}))


## The entry a seed resolves on (see the header).
static func table_name(seed: Dictionary, door: int, held: bool) -> String:
	var fort: Dictionary = seed.get("fort", {})
	if held:
		return "held"
	if bool(fort.get("first_dungeon", false)):
		return "first_dungeon"
	if door >= 0:
		return "held_door"
	return str(clampi(int(fort.get("tier", 1)), 1, 4))


static func resolve(seed: Dictionary, standins: Dictionary, cfgs: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var rcfg: Dictionary = cfgs.get("raid", {})
	var lcfg: Dictionary = cfgs.get("loot", {})
	var fort: Dictionary = seed.get("fort", {})
	var tier := clampi(int(fort.get("tier", 1)), 1, 4)
	var held := bool(opts.get("held", false))
	var frozen := str(opts.get("deaths", "human")) == "frozen"
	var door := door_pick(seed, rcfg, opts)
	var table := table_name(seed, door, held)
	var where := str(tier) if held else table
	var e := _d(standins, where, "")
	var d := _f(e, "death_rate_frozen" if frozen else "death_rate", where)
	var dur := _f(e, "duration_s", where)
	var party_p := _f(e, "party_lost_per_member", where)
	if held:
		var h := _d(standins, "held", "")
		d *= _f(h, "death_rate_mult", "held")
		dur *= _f(h, "duration_mult", "held")
		party_p *= _f(h, "party_lost_mult", "held")
	var rng := RandomNumberGenerator.new()
	rng.seed = str(seed.get("rng_seed", "0")).to_int() ^ SALT

	# the outcome: a death; each charge this run may spend revives her in place, then the rest of the run rolls again
	var revived := 0
	var died := rng.randf() < d
	while died and RaidLogic.can_revive(revived, seed):
		revived += 1
		died = rng.randf() < d
	var exit := "relish_died" if died else ("retreated" if held else "warden_beaten")

	# the party: members lost on a win; the door's big by the dungeon's rule
	var party: Array = seed.get("party", [])
	var door_uid := str((party[door] as Dictionary).get("uid", "")) if door >= 0 else ""
	var lost: Array = []
	if not died:
		for p in party:
			var uid := str((p as Dictionary).get("uid", ""))
			if uid != door_uid and rng.randf() < party_p:
				lost.append(uid)
	if RaidLogic.held_door_lost(exit, door >= 0):
		lost.append(door_uid)

	# the masses, on the seed's own fort
	var mw := where + ".mass." + ("died" if died else "won")
	var m := _d(_d(e, "mass", where), "died" if died else "won", where + ".mass")
	var living := maxf(0.0, float(seed.get("living", 0.0)))
	var cap := float(fort.get("cap", 1.0))
	var killed := living if held and not died else living * _f(m, "killed_frac", mw)
	var units := RaidLogic.enemy_count(living, cap, rcfg)
	var per := RaidLogic.mass_per_enemy(living, cap, rcfg)
	var count := roundi(_f(m, "raised_per_living_unit", mw) * float(units))
	var fresh := minf(float(count) * per, killed + maxf(0.0, float(seed.get("dead", 0.0))))
	var score := int(_f(standins, "score", ""))
	var ledger := RaidLogic.LedgerV2.new(seed, rcfg)
	ledger.on_kill(killed)
	ledger.on_raise(score, fresh, count)
	var survivors: Array = [
		{"role": "garrison", "tier": "chaff",
			"mass": float(seed.get("garrison_in_mass", 0.0)) * _f(m, "garrison_survive_frac", mw)},
		{"role": "raised", "tier": RaidLogic.score_class(score, rcfg),
			"mass": _f(m, "raised_survivors_per_living_unit", mw) * float(units) * per}]

	var loot := _loot(rng, seed, e, where, held, died, lcfg, opts.get("blueprints", []))
	var result: Dictionary = ledger.build_result(seed, exit, survivors, lost, revived, loot, rcfg)
	return {"result": result, "duration_s": dur * _f(e, "death_t_frac", where) if died else dur, "died": died,
		"notes": {"table": table, "entry": where, "deaths": "frozen" if frozen else "human", "death_rate": d,
			"revived": revived, "door_taken": door >= 0, "door_uid": door_uid,
			"yield_mult": float(fort.get("yield_mult", 1.0)), "killed": killed, "raised_fresh_mass": fresh}}


## The run's loot (§8.1 shape). See the header.
static func _loot(rng: RandomNumberGenerator, seed: Dictionary, e: Dictionary, where: String, held: bool, died: bool,
		cfg: Dictionary, owned: Array) -> Dictionary:
	var fort: Dictionary = seed.get("fort", {})
	var tier := clampi(int(fort.get("tier", 1)), 1, 4)
	var y := float(fort.get("yield_mult", 1.0))
	if held:
		return RaidLoot.empty_loot() if died else RaidLoot.held_clear(rng, tier, y, cfg)
	var arche := str((seed.get("warden", {}) as Dictionary).get("archetype", ""))
	var mean := _d(e, "mean_loot", where)
	var kept := _d(e, "kept_frac", where)
	var n := {}
	for k in KINDS:
		n[k] = _f(mean, k, where + ".mean_loot") * (_f(kept, k, where + ".kept_frac") if died else 1.0)
	var out := RaidLoot.empty_loot()
	out["relics"] = RaidLoot.scaled_count(rng, float(n["relics"]), y)
	for i in RaidLoot.scaled_count(rng, float(n["remnants"]), y):
		(out["remnants"] as Array).append(RaidLoot._remnant(rng, tier, arche, cfg))
	var kinds: Array = (RaidLoot._by_tier(cfg.get("chest_by_tier", {}), tier) as Dictionary).get("husk_kinds", [])
	for i in RaidLoot.scaled_count(rng, float(n["husks"]), y):
		if not kinds.is_empty():
			(out["husks"] as Array).append({"kind": str(kinds[rng.randi_range(0, kinds.size() - 1)])})
	for i in RaidLoot.scaled_count(rng, float(n["blueprints"]), y):  # 0 in every entry: the chest gives the first clear's
		var bp := RaidLoot.first_blueprint(tier, owned + (out["blueprints"] as Array), cfg)
		if bp != "":
			(out["blueprints"] as Array).append(bp)
	out["essence"] = RaidLoot.scaled_count(rng, float(n["essence"]), 1.0)
	if not died:
		var chest := RaidLoot.chest(rng, {"tier": tier, "archetype": arche,
			"first_clear": bool(fort.get("first_clear", false)), "chest_husk": bool(seed.get("chest_husk", false)),
			"yield_mult": 0.0}, owned + (out["blueprints"] as Array), cfg)
		out["relics"] = int(out["relics"]) + int(chest["relics"])
		(out["blueprints"] as Array).append_array(chest["blueprints"])
		(out["husks"] as Array).append_array(chest["husks"])
	return out
