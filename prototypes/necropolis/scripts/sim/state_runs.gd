class_name StateRuns
extends RefCounted
## Runs and their results (STATE-API 4.5, 7, 8), static only, taking the GameState they act on: the
## dungeon and boss seeds, opening and aborting a run, apply_result's checks and its two writebacks,
## and Relish's death. GameState keeps the public commands and apply_result, with their signatures,
## and forwards here; the small config helpers a seed shares with the views (_garrison, _fronts, ...)
## stay in GameState.


static func derived_rng_seed(gs: GameState, run_id: int) -> String:
	var hi: int = hash([gs.game_seed, run_id])
	var lo: int = hash([run_id, gs.game_seed])
	return str((hi << 32) | lo)


static func party_entries(gs: GameState, with_front := false) -> Array:
	var out: Array = []
	for uid in gs.party_uids:
		for b in gs.big_undead:
			if b["uid"] == uid:
				var e: Dictionary = {
					"uid": b["uid"], "name": b["name"], "kind": b["kind"], "role": b["role"],
					"stats": (b["stats"] as Dictionary).duplicate(),
					"filled_slots": GameState.filled_slots_of(b),  # v8 (E3-3, api-request #6): both seeds' party
				}
				if with_front:
					e["front"] = b["front"]
				out.append(e)
	return out


static func dungeon_seed(gs: GameState, fort_id: String, run_id: int, seed_rev: int) -> Dictionary:
	var f := gs.realm.fort_by_id(fort_id)
	var g := gs._garrison(fort_id)
	var first := gs._is_first_dungeon(fort_id)
	var archetype := gs._warden_archetype(fort_id)
	var tier := int(f["tier"])
	return {
		"v": 2, "kind": "raid", "run_id": run_id, "seed_rev": seed_rev,
		"rng_seed": derived_rng_seed(gs, run_id),
		"fort": {
			"id": fort_id, "name": str(f["name"]), "tier": tier, "cap": float(f["cap"]),
			"first_clear": not gs.cleared_forts.has(fort_id), "first_dungeon": first,
			"clears_since_retaken": int(f.get("clears_since_retaken", 0)), "yield_mult": gs._yield_mult(f),
		},
		"living": float(f["living"]), "dead": float(f["dead"]), "undead": float(f["undead"]),
		"garrison_units": g[0], "garrison_in_mass": g[1], "garrison_mass_div": gs._garrison_div(),
		"starter_units": gs._starter_units(fort_id),
		"party": party_entries(gs),
		"digest_q": gs.digest_q(),
		"phylactery_charges": gs._phylactery_charges,
		"phylactery_max_per_dungeon": gs._phylactery_max(),
		"clones_ready": gs.clones_ready,
		"warden": {"archetype": archetype, "tier": tier}, "warden_spec": {},
		"loot_table_id": "t%d.%s" % [tier, archetype],
		"loot_hint": gs._loot_hint(fort_id),
		"chest_husk": first, "watchtower": false,
		"relish_hp": gs._relish_hp(),
		"death_ends": death_ends(gs, "raid"),
	}


## §7.2. The fronts (live from E3-5, v8) are VeiFronts.have_need's on the seed's own backlog, living pool, digest_q and
## party (VeiFronts.info_from_boss_seed), so they are exactly what the fight computes from this seed (BossLogic.party_lanes;
## vei_boss.gd's _fronts_for when they are all zero), with `assigned` cmd_assign_front's echo. They are view_vei's at issue:
## the same backlog, pool and q, and the same units counted, as only party members have a front or the party place
## (cmd_assign_front, _leave_party, cmd_set_party).
static func boss_seed_v2(gs: GameState, run_id: int, seed_rev: int) -> Dictionary:
	var ro := gs._vei_readout()
	var sd := {
		"v": 2, "kind": "boss", "run_id": run_id, "seed_rev": seed_rev,
		"rng_seed": derived_rng_seed(gs, run_id),
		"backlog": float(gs.realm.vei["undead_queue"]), "living_pool": float(gs.realm.vei["living_pool"]),
		"odds": ro["odds"], "sign": ro["sign"], "drain_s": ro["drain_s"], "digest_q": gs.digest_q(),
		"vei_capacity": gs._req_f("realm.R_vei"),
		"fronts": [],  # filled below, from the seed itself (its key keeps its place)
		"fronts_required": gs._fronts_required(),
		"party": party_entries(gs, true),
		"phylactery_charges": gs._phylactery_charges, "clones_ready": gs.clones_ready,
		"relish_hp": gs._relish_hp(),
		"death_ends": death_ends(gs, "boss"),
	}
	sd["fronts"] = gs._fronts(VeiFronts.info_from_boss_seed(sd), false)
	return sd


## The seeds' `death_ends` (§7.1, §7.2; E2b-2 T3.3c, the dungeon's D-e): what a death that ends the run ends
## in, {outcome: "clone" | "unmade", respawn_s}, from view_backups' death rule (StateViews.death_rule) past its
## phylactery step: a revive in place doesn't end the run, so a death that does is past them (Results.validate
## takes only clone or unmade here). E3-2: respawn_s is the outcome's, backups.clone_respawn_s or unmade_respawn_s.
## - A raid: after any phylactery revives (each revives in place, at most phylactery.max_per_dungeon), the
##   death that ends the run wakes her from a ready clone, else unmakes her: the rule at the clones ready now,
##   so it equals view_backups().death's outcome and respawn_s while no charge is left (with one, view_backups
##   reads "phylactery") and what death() then does.
## - A boss run: each death spends a phylactery charge, then a clone (§8.2, MECHANICS §6), and the fight ends
##   in a death only when none is left (a final death, relish_deaths = the backups spent + 1), so that death
##   is "unmade": the rule with no clone ready. (writeback_boss's death reads the clones left after the ones
##   spent: a final death with a clone still ready would wake from it, which the boss scene never sends. A clone
##   grown mid-fight (the sim ticks on) stays in its vat: writeback_boss passes death() 0 clones, this rule.)
static func death_ends(gs: GameState, kind: String) -> Dictionary:
	var d := StateViews.death_rule(gs, gs.clones_ready if kind == "raid" else 0)
	return {"outcome": str(d["outcome"]), "respawn_s": float(d["respawn_s"])}


static func open_run(gs: GameState, kind: String, fort_id: String) -> Dictionary:
	var run_id := gs.next_run_id
	gs.next_run_id += 1
	gs.rev += 1
	var seed_d := dungeon_seed(gs, fort_id, run_id, gs.rev) if kind == "raid" else boss_seed_v2(gs, run_id, gs.rev)
	# `held`: the fort was held when the run began (the seed carries no such field: the dungeon reads
	# view_fort.held live), for counter_garrison_cleared (writeback_raid)
	var held := kind == "raid" and RealmSim.is_held(gs.realm.fort_by_id(fort_id))
	gs.run = {"run_id": run_id, "kind": kind, "fort_id": fort_id, "seed_rev": gs.rev, "seed": seed_d, "held": held}
	gs.relish["state"] = "in_dungeon" if kind == "raid" else "in_boss"
	gs.time_scale = 1.0
	gs.paused = false
	return {"ok": true, "reason": "", "seed": seed_d.duplicate(true), "run_id": run_id, "seed_rev": gs.rev}


static func begin_dungeon(gs: GameState, fort_id: String) -> Dictionary:
	var fail := {"ok": false, "reason": "", "seed": {}, "run_id": -1, "seed_rev": -1}
	if gs.realm.fort_by_id(fort_id).is_empty():
		fail["reason"] = "unknown_fort"
		return fail
	var why := gs._descend_reason(fort_id)
	if why != "":
		fail["reason"] = why
		return fail
	return open_run(gs, "raid", fort_id)


static func begin_boss(gs: GameState) -> Dictionary:
	var why := gs._boss_reason()
	if why != "":
		return {"ok": false, "reason": why, "seed": {}, "run_id": -1, "seed_rev": -1}
	return open_run(gs, "boss", "vei")


## cmd_abort_dungeon. A dead run's refusal (no_run) is checked before catching_up (STATE-API §4.5, E2b-2
## T3.3c): no run is open during a catch-up (every open run ends before one starts), so a dungeon scene still
## sitting on an ended run learns it is over instead of being told to wait.
static func abort_dungeon(gs: GameState) -> Dictionary:
	if gs.run.is_empty():
		return {"ok": false, "reason": "no_run", "run_id": -1}
	if gs._catchup.active:
		return GameState._refuse_catching_up({"run_id": -1})
	var run_id: int = gs.run["run_id"]
	gs.relish["state"] = "at_fort" if gs.run["kind"] == "raid" else "at_vei"
	gs.run = {}
	gs.rev += 1
	return {"ok": true, "reason": "", "run_id": run_id}


## The exits a checkpoint can name (STATE-API §4.5 cmd_run_checkpoint; the raid result's three, §8.1).
const OUTCOMES := ["retreated", "warden_beaten", "relish_died"]


## The raid result's `loot` (§8.1) in its canonical form: the five keys, ints as ints, each husk and remnant
## with its own keys only, a deep copy. `l` has passed Results.validate (inside a result).
static func loot_of(l: Dictionary) -> Dictionary:
	var husks: Array = []
	for h in l["husks"]:
		husks.append({"kind": str(h["kind"])})
	var remnants: Array = []
	for m in l["remnants"]:
		remnants.append({"aspect": str(m["aspect"]), "rarity": str(m["rarity"]), "magnitude": int(m["magnitude"])})
	var bps: Array = []
	for b in l["blueprints"]:
		bps.append(str(b))
	return {"relics": int(l["relics"]), "blueprints": bps, "husks": husks, "remnants": remnants, "essence": int(l["essence"])}


static func empty_loot() -> Dictionary:
	return {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0}


## The raid result an ended run applies (IDLE I5; STATE-API §4.5): its `outcome` as the exit, `loot` as the
## banked loot, and nothing else the scene would report: no kills, no raises, no chaff, no revives, no party
## member lost, and `garrison_mass` equal to the seed's `garrison_in_mass`, so the garrison taken in stays and
## the fort's undead don't move (§8.3 step 5). `run` is the run ({run_id, seed_rev, fort_id, seed}).
static func end_result(run: Dictionary, loot: Dictionary, outcome: String) -> Dictionary:
	return {
		"v": 2, "run_id": int(run["run_id"]), "seed_rev": int(run["seed_rev"]), "fort_id": str(run["fort_id"]),
		"warden_beaten": outcome == "warden_beaten", "retreated": outcome == "retreated", "relish_died": outcome == "relish_died",
		"revived_in_place": 0, "killed_living_mass": 0.0, "raised": [], "chaff_mass": 0.0,
		"garrison_mass": float(run.get("seed", {}).get("garrison_in_mass", 0.0)), "party_lost": [], "loot": loot,
	}


## §4.5 cmd_run_checkpoint (api-request #4; IDLE I5): the open raid records the loot banked so far and the exit
## it would end in now, replacing any earlier checkpoint. A dead run's refusals (no_run, wrong_run) come before
## catching_up, so a dungeon scene on an ended run learns it is over; a boss run has nothing to bank (a boss
## result carries no loot, §8.2): wrong_kind. Then invalid (Results.validate on a retreat result carrying
## `loot`) and bad_outcome.
static func checkpoint(gs: GameState, run_id: int, loot: Dictionary, outcome: String) -> Dictionary:
	var fail := {"ok": false, "reason": ""}
	if gs.run.is_empty():
		fail["reason"] = "no_run"
	elif int(gs.run["run_id"]) != run_id:
		fail["reason"] = "wrong_run"
	elif gs.run["kind"] != "raid":
		fail["reason"] = "wrong_kind"
	elif gs._catchup.active:
		fail["reason"] = "catching_up"  # (unreachable: no run is open during a catch-up)
	elif not Results.validate("raid", end_result(gs.run, loot, "retreated")).is_empty():
		fail["reason"] = "invalid"
	elif not OUTCOMES.has(outcome):
		fail["reason"] = "bad_outcome"
	if fail["reason"] != "":
		return fail
	gs.run["checkpoint"] = {"loot": loot_of(loot), "outcome": outcome}
	gs.rev += 1
	return {"ok": true, "reason": ""}


## The open run as the save writes it (§9.1 `pending_retreat`): {run_id, kind, fort_id, seed_rev, loot,
## outcome}, its last checkpoint's loot and outcome, or empty loot and "retreated" when it has none (a boss
## run never has one).
static func pending_of(gs: GameState) -> Dictionary:
	var cp: Dictionary = gs.run.get("checkpoint", {})
	return {
		"run_id": int(gs.run["run_id"]), "kind": str(gs.run["kind"]), "fort_id": str(gs.run["fort_id"]),
		"seed_rev": int(gs.run["seed_rev"]),
		"loot": (cp["loot"] as Dictionary).duplicate(true) if cp.has("loot") else empty_loot(),
		"outcome": str(cp.get("outcome", "retreated")),
	}


## Ends the open run from its last checkpoint (IDLE I5): a raid through the normal writeback as a result of
## the checkpoint's outcome (end_result), so a retreat banks the loot with no flip and Relish at_fort,
## warden_beaten flips the fort, relish_died is a death; the run's id joins applied_runs (a late result for it
## is duplicate_run). `held` is cleared first: an ended run's kills aren't known (the checkpoint carries
## none), so it never clears a counter-garrison. A boss run is forfeited as cmd_abort_dungeon forfeits it: no
## writeback, the party intact, Relish at_vei, and its id is not an applied run (a late result is wrong_run).
## Returns the outcome applied.
static func end_open(gs: GameState) -> String:
	var pr := pending_of(gs)
	if pr["kind"] != "raid":
		gs.relish["state"] = "at_vei"
		gs.run = {}
		gs.rev += 1
		return "retreated"
	gs.run["held"] = false
	var r := apply_result(gs, "raid", end_result(gs.run, pr["loot"], pr["outcome"]))
	if not r["ok"]:  # (never: the result is built to pass every check)
		push_error("StateRuns: an ended run's writeback was refused (%s %s); forfeiting it" % [r["reason"], str(r["errors"])])
		gs.relish["state"] = "at_fort"
		gs.run = {}
	return str(pr["outcome"])


## A gap above idle.gap_s in the open game with a run open (the machine asleep in a dungeon; IDLE I5): the
## event run_ended {run_id, kind, outcome, cause} first, so the dungeon scene knows to leave, then the end
## (end_open) and its writeback's events, all queued live, before the gap's catch-up starts.
static func end_for_gap(gs: GameState) -> void:
	var pr := pending_of(gs)
	gs._emit({"type": "run_ended", "run_id": pr["run_id"], "kind": pr["kind"],
		"outcome": pr["outcome"] if pr["kind"] == "raid" else "retreated", "cause": "gap"})
	end_open(gs)


## A save's pending_retreat applied on load (from_dict, before any catch-up; IDLE I5): the run it records is
## opened again as it stood (run_id, seed_rev, its fort, Relish in its dungeon) and ended by end_open. The seed
## the writeback reads is dungeon_seed at the load, which gives the fields it uses as the run had them: its
## party (the save's party: no command changes it while a run is open), its phylactery fields (the stock, which
## nothing changes while a run is open) and garrison_in_mass (which the end result's garrison_mass equals, so
## the fort's undead don't move whatever it is). Its events are queued as live: they happened before the time
## away. A boss run needs nothing: the save already holds it forfeited (Relish at_vei, no run).
static func apply_pending(gs: GameState, pr: Dictionary) -> void:
	if str(pr["kind"]) != "raid":
		return
	var run_id := int(pr["run_id"])
	var fort_id := str(pr["fort_id"])
	var seed_rev := int(pr["seed_rev"])
	gs.run = {"run_id": run_id, "kind": "raid", "fort_id": fort_id, "seed_rev": seed_rev,
		"seed": dungeon_seed(gs, fort_id, run_id, seed_rev), "held": false,
		"checkpoint": {"loot": loot_of(pr["loot"]), "outcome": str(pr["outcome"])}}
	gs.relish["state"] = "in_dungeon"
	end_open(gs)


static func view_dungeon_seed(gs: GameState, fort_id: String) -> Dictionary:
	if gs.run.get("kind", "") == "raid" and gs.run["fort_id"] == fort_id:
		return (gs.run["seed"] as Dictionary).duplicate(true)
	return {}


static func view_boss_seed(gs: GameState) -> Dictionary:
	if gs.run.get("kind", "") == "boss":
		return (gs.run["seed"] as Dictionary).duplicate(true)
	return {}


## Relish's death that ends a run (§8.3 raid step 10, boss step 4; E3-2, MECHANICS §7), by the death rule past the
## phylactery (StateViews.death_rule with no charge: the dungeon spent its revives in place already, and a death that
## ends the run is past them): a ready clone if there is one (spent: the lowest ready vat empties back to 0, else a
## spare clone goes; GameState.spend_clones), else she is unmade and the town takes morale.death_shock. She is `dead`
## at the node she died at, `dead_s_left` the outcome's respawn_s (backups.clone_respawn_s or unmade_respawn_s) and
## `respawn_with_clone` which it was. `clones` is the clone count the rule judges by: a raid passes the clones ready now
## (gs.clones_ready), a boss fight 0, as the seed's death_ends does (a clone grown while the fight ran stays in its
## vat: the seed promised unmade). The backups step counts it down and wakes her at Covington with
## relish_respawned (GameState._count_down_respawn). A respawn_s of 0 wakes her at once. The caller has closed the run
## and removed the party.
static func death(gs: GameState, run_id: int, clones: int) -> void:
	gs.stats["deaths"] += 1
	var at_node: String = gs.relish["at"]
	var d := StateViews.death_rule(gs, clones)
	var clone := str(d["outcome"]) == "clone"
	if clone:
		gs.spend_clones(1)
	else:
		gs.town_sim.add_shock(gs._req_f("economy.morale.death_shock"))
	var respawn_s := float(d["respawn_s"])
	gs._emit({"type": "relish_died", "outcome": str(d["outcome"]), "in_place": false,
		"at": at_node, "run_id": run_id, "respawn_s": respawn_s})
	gs.relish["state"] = "dead"
	gs.relish["target"] = ""
	gs.relish["pos"] = gs._node_xy(at_node)
	gs.relish["dead_s_left"] = respawn_s
	gs.relish["respawn_with_clone"] = clone
	if respawn_s <= 0.0:
		gs._respawn()


static func ar_fail(gs: GameState, reason: String, errors: Array = []) -> Dictionary:
	return {"ok": false, "reason": reason, "errors": errors, "minted": []}


## §4.5. Refusals are checked in the documented order and change nothing (no rev, no events,
## no uids, no rng). Ints may arrive as integral floats, so every int is read with int().
static func apply_result(gs: GameState, kind: String, result: Dictionary) -> Dictionary:
	if kind != "raid" and kind != "boss":
		return ar_fail(gs, "unknown_kind")
	if not Results.has_v2(result):
		return ar_fail(gs, "unknown_v")
	var errs := Results.validate(kind, result)
	if not errs.is_empty():
		return ar_fail(gs, "invalid", errs)
	var run_id := int(result["run_id"])
	if gs.applied_runs.has(run_id):
		return ar_fail(gs, "duplicate_run")
	if gs.run.is_empty() or int(gs.run["run_id"]) != run_id:
		return ar_fail(gs, "wrong_run")
	if gs.run["kind"] != kind:
		return ar_fail(gs, "wrong_kind")
	if int(result["seed_rev"]) != int(gs.run["seed_rev"]):
		return ar_fail(gs, "stale_seed")
	var sd: Dictionary = gs.run["seed"]
	if kind == "raid":
		if str(result["fort_id"]) != str(gs.run["fort_id"]):
			return ar_fail(gs, "wrong_fort")
		if int(result["revived_in_place"]) > mini(int(sd["phylactery_charges"]), int(sd["phylactery_max_per_dungeon"])):
			return ar_fail(gs, "bad_revives")
	var party := seed_party_uids(gs, sd)
	for uid in result["party_lost"]:
		if not party.has(uid):
			return ar_fail(gs, "bad_party")
	if kind == "boss":
		var bs: Dictionary = result["backups_spent"]
		if int(bs["phylactery"]) > int(sd["phylactery_charges"]) or int(bs["clones"]) > int(sd["clones_ready"]):
			return ar_fail(gs, "bad_backups")
	var minted: Array = []
	if kind == "raid":
		minted = writeback_raid(gs, result)
	else:
		writeback_boss(gs, result)
	gs.applied_runs.append(run_id)
	while gs.applied_runs.size() > 32:
		gs.applied_runs.remove_at(0)
	gs.rev += 1
	return {"ok": true, "reason": "", "errors": [], "minted": minted}


static func seed_party_uids(gs: GameState, sd: Dictionary) -> Array:
	var out: Array = []
	for e in sd["party"]:
		out.append(e["uid"])
	return out


## Removes a big undead for good (death in a run), from the party too.
static func remove_big_undead(gs: GameState, uid: String) -> void:
	for i in gs.big_undead.size():
		if gs.big_undead[i]["uid"] == uid:
			gs.big_undead.remove_at(i)
			break
	gs.party_uids.erase(uid)


## §8.3 raid steps 1-11 (E3-2: each revive in place spends a charge and raises relish_died{phylactery, in_place}; a
## death that ends the run is death()'s). The result is already validated and matched to the open run. Returns the
## minted uids.
static func writeback_raid(gs: GameState, r: Dictionary) -> Array:
	var sd: Dictionary = gs.run["seed"]
	var run_id: int = gs.run["run_id"]
	var fort_id: String = gs.run["fort_id"]
	var f := gs.realm.fort_by_id(fort_id)
	gs.stats["raids"] += 1
	# 1. kills, against the live fort
	var k := minf(float(r["killed_living_mass"]), float(f["living"]))
	f["living"] -= k
	f["dead"] += k
	# a held fort's raid that cleared its counter-garrison (api-request #10): held when the run began
	# (run["held"]) and still held now (the realm keeps stepping during a run, so Vei may have retaken
	# it: the fort is hers again, so it is no held clear and spends no yield, MECHANICS §5.3), a retreat, and
	# kills that reach the seed's living less half of one of the dungeon's living units
	var cg_cleared: bool = bool(gs.run.get("held", false)) and RealmSim.is_held(f) and bool(r["retreated"]) \
		and float(r["killed_living_mass"]) >= float(sd["living"]) - gs._clear_tolerance(sd)
	# 2. the flip
	var flip_ev := {}
	if r["warden_beaten"]:
		f["dead"] += f["living"]
		f["living"] = 0.0
		var hold_s := gs._req_f("realm.flip.hold_s") * (1.0 + gs._req_f("realm.flip.tier_mult") * float(f["tier"]))
		gs.realm.hold(fort_id, hold_s)  # RealmSim counts it down and stops her shipping there
		gs.realm.start_tithe()  # the first flip starts Vei's tithe cycle (a running one is left alone)
		f["flipped_count"] = int(f.get("flipped_count", 0)) + 1
		f["clears_since_retaken"] = int(f.get("clears_since_retaken", 0)) + 1
		gs._spend_yield(f)  # the flip paid loot: the next raid's yield halves and recovers (§5.3)
		flip_ev = {"type": "fort_flipped", "fort_id": fort_id, "run_id": run_id, "hold_s": hold_s}
	# 3. raised mass comes out of the dead
	var raised_total := 0.0
	for e in r["raised"]:
		raised_total += float(e["mass"])
	var raised_in := minf(raised_total, float(f["dead"]))
	f["dead"] -= raised_in
	# q's circle EMA, by the mass actually raised from the fort's dead (each mass scaled by R'/R)
	var raised_scale := raised_in / raised_total if raised_total > 0.0 else 0.0
	var raised_clamped: Array = []
	for e in r["raised"]:
		raised_clamped.append({"score": e["score"], "mass": float(e["mass"]) * raised_scale})
	gs._raise_ema(raised_clamped)
	# 4. what leaves cannot exceed what went in plus what was raised
	var garrison_out := float(r["garrison_mass"])
	var chaff := float(r["chaff_mass"])
	var garrison_in := float(sd["garrison_in_mass"])
	if garrison_out + chaff > garrison_in + raised_in + 1e-9:
		var sc := (garrison_in + raised_in) / (garrison_out + chaff)
		garrison_out *= sc
		chaff *= sc
	# 5. the net garrison delta, clamped at the live undead
	var undead_before: float = f["undead"]
	f["undead"] = maxf(0.0, undead_before + garrison_out - garrison_in)
	var undead_delta: float = f["undead"] - undead_before
	# 6. chaff leaves with Relish, but never more than actually left the fort (no mass from the clamp)
	chaff = minf(chaff, maxf(0.0, raised_in - undead_delta))
	gs.realm.vei["undead_queue"] += chaff
	# 7. whatever went in and did not come out, net of the step 5 clamp (>= 0 by construction)
	gs._ledger.sink("dungeon", raised_in - undead_delta - chaff)
	gs.stats["raised_total"] += raised_in
	# 8. loot
	var loot: Dictionary = r["loot"]
	var relics_in := mini(int(loot["relics"]), maxi(0, gs._cap_of("relics") - gs.relics))
	gs.relics += relics_in
	var essence_in := mini(int(loot["essence"]), maxi(0, gs._cap_of("essence") - gs.essence))
	gs.essence += essence_in
	var new_bps: Array = []
	for bp in loot["blueprints"]:
		if not gs.blueprints.has(bp):
			gs.blueprints.append(bp)
			new_bps.append(bp)
	var minted: Array = []
	for h in loot["husks"]:
		var uid := gs._mint_uid("h")
		gs.husks.append({"uid": uid, "kind": str(h["kind"]), "rarity": "common"})
		minted.append(uid)
	for m in loot["remnants"]:
		var uid := gs._mint_uid("r")
		gs.remnants.append({"uid": uid, "aspect": str(m["aspect"]), "rarity": str(m["rarity"]),
			"magnitude": int(m["magnitude"])})
		minted.append(uid)
	# The first-run flags are spent only by a win: a death or a retreat keeps the starter husk and
	# the guaranteed blueprint for the next first run (api-request #15).
	if bool(r["warden_beaten"]):
		gs.cleared_forts[fort_id] = true
		gs.first_dungeon_id = ""
	# 9. the dead party members go; each in-place revive spends a phylactery charge
	gs._phylactery_charges = maxi(0, gs._phylactery_charges - int(r["revived_in_place"]))
	for uid in r["party_lost"]:
		remove_big_undead(gs, uid)
	var died: bool = r["relish_died"]
	var party := seed_party_uids(gs, sd)
	gs.run = {}
	gs._emit({"type": "loot_banked", "run_id": run_id, "fort_id": fort_id, "relics": relics_in,
		"essence": essence_in, "blueprints": new_bps, "minted": minted.duplicate()})
	if not flip_ev.is_empty():
		gs._emit(flip_ev)
	if cg_cleared:
		gs._spend_yield(f)  # the clear paid loot (held_clear's roll)
		gs._emit({"type": "counter_garrison_cleared", "fort_id": fort_id, "killed_mass": k})
	# 9 (E3-2): each phylactery revive the dungeon reports was a death in place (she carried on in the run)
	for i in int(r["revived_in_place"]):
		gs._emit({"type": "relish_died", "outcome": "phylactery", "in_place": true, "at": fort_id, "run_id": run_id,
			"respawn_s": 0.0})
	# 10. death: the whole party is lost (A8), then the death rule; 11. otherwise she stays
	if died:
		for uid in party:
			remove_big_undead(gs, uid)
		death(gs, run_id, gs.clones_ready)
	else:
		gs.relish["state"] = "at_fort"
	return minted


## §8.3 boss steps 1-5. Each backup the fight spent was a death in place (E3-5): one relish_died{in_place} per backup
## in backups_spent, the phylactery charges first, then the clones (VeiFronts.next_backup's order), queued after
## vei_result and before a final death's, as a raid's revives follow its loot_banked. A final death is death()'s (E3-2:
## the shared death rule at the clones left, so "unmade" once every clone is spent; dead, then the respawn).
static func writeback_boss(gs: GameState, r: Dictionary) -> void:
	var sd: Dictionary = gs.run["seed"]
	var run_id: int = gs.run["run_id"]
	var at: String = gs.run["fort_id"]  # "vei" (open_run)
	var did_win: bool = r["won"]
	var bs: Dictionary = r["backups_spent"]
	var clones := int(bs["clones"])
	var deaths := int(r["relish_deaths"])
	var final_death := deaths == int(bs["phylactery"]) + clones + 1
	if did_win:
		gs.won = true
	else:
		var keep := gs._req_f("vei.loss_backlog_keep")
		var before: float = gs.realm.vei["undead_queue"]
		gs.realm.vei["undead_queue"] = before * keep
		gs._ledger.sink("vei_fight", before - float(gs.realm.vei["undead_queue"]))
		for uid in seed_party_uids(gs, sd):
			remove_big_undead(gs, uid)
	for uid in r["party_lost"]:
		remove_big_undead(gs, uid)
	gs._phylactery_charges = maxi(0, gs._phylactery_charges - int(bs["phylactery"]))
	gs.spend_clones(clones)  # the lowest ready vats first, then spare clones (E3-2; clamped at what is ready)
	gs.run = {}
	var cleared: Array = []
	for fid in r["fronts_cleared"]:
		cleared.append(str(fid))
	gs._emit({"type": "vei_result", "run_id": run_id, "won": did_win, "fronts_cleared": cleared,
		"relish_deaths": deaths, "backlog_after": float(gs.realm.vei["undead_queue"])})
	# 3 (E3-5): the fight's revives, each in place (she carried on in the fight), in the order it spent them
	var charges := int(bs["phylactery"])
	for i in charges + clones:
		gs._emit({"type": "relish_died", "outcome": "phylactery" if i < charges else "clone", "in_place": true,
			"at": at, "run_id": run_id, "respawn_s": 0.0})
	if final_death:
		death(gs, run_id, 0)  # the seed's death_ends rule (no clone): a clone grown mid-fight stays in its vat
	else:
		gs.relish["state"] = "at_vei"
