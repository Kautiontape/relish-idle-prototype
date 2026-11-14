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
			"clears_since_retaken": int(f.get("clears_since_retaken", 0)), "yield_mult": 1.0,
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
	}


static func boss_seed_v2(gs: GameState, run_id: int, seed_rev: int) -> Dictionary:
	var ro := gs._vei_readout()
	return {
		"v": 2, "kind": "boss", "run_id": run_id, "seed_rev": seed_rev,
		"rng_seed": derived_rng_seed(gs, run_id),
		"backlog": float(gs.realm.vei["undead_queue"]), "living_pool": float(gs.realm.vei["living_pool"]),
		"odds": ro["odds"], "sign": ro["sign"], "drain_s": ro["drain_s"], "digest_q": gs.digest_q(),
		"vei_capacity": float(gs._cfg().get("R_vei", 50.0)),
		"fronts": gs._fronts(false),
		"fronts_required": gs._fronts_required(),
		"party": party_entries(gs, true),
		"phylactery_charges": gs._phylactery_charges, "clones_ready": gs.clones_ready,
		"relish_hp": gs._relish_hp(),
	}


static func open_run(gs: GameState, kind: String, fort_id: String) -> Dictionary:
	var run_id := gs.next_run_id
	gs.next_run_id += 1
	gs.rev += 1
	var seed_d := dungeon_seed(gs, fort_id, run_id, gs.rev) if kind == "raid" else boss_seed_v2(gs, run_id, gs.rev)
	gs.run = {"run_id": run_id, "kind": kind, "fort_id": fort_id, "seed_rev": gs.rev, "seed": seed_d}
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


static func abort_dungeon(gs: GameState) -> Dictionary:
	if gs.run.is_empty():
		return {"ok": false, "reason": "no_run", "run_id": -1}
	var run_id: int = gs.run["run_id"]
	gs.relish["state"] = "at_fort" if gs.run["kind"] == "raid" else "at_vei"
	gs.run = {}
	gs.rev += 1
	return {"ok": true, "reason": "", "run_id": run_id}


static func view_dungeon_seed(gs: GameState, fort_id: String) -> Dictionary:
	if gs.run.get("kind", "") == "raid" and gs.run["fort_id"] == fort_id:
		return (gs.run["seed"] as Dictionary).duplicate(true)
	return {}


static func view_boss_seed(gs: GameState) -> Dictionary:
	if gs.run.get("kind", "") == "boss":
		return (gs.run["seed"] as Dictionary).duplicate(true)
	return {}


## Relish's death until E3 (§8.3 step 10, the E1-safe rule): a ready clone if there is one (it is
## spent), else she is unmade and the town takes morale.death_shock; she respawns home at once.
## The caller has closed the run.
static func death(gs: GameState, run_id: int) -> void:
	gs.stats["deaths"] += 1
	var at_node: String = gs.relish["at"]
	var clone := gs.clones_ready > 0
	if clone:
		gs.clones_ready -= 1
	else:
		gs.town_sim.add_shock(float(gs._sec("economy", "morale").get("death_shock", 0.3)))
	gs._emit({"type": "relish_died", "outcome": "clone" if clone else "unmade", "in_place": false,
		"at": at_node, "run_id": run_id, "respawn_s": 0.0})
	gs._place_relish("covington")
	gs._emit({"type": "relish_respawned", "with_clone": clone, "at": "covington"})


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


## §8.3 raid steps 1-11 (death by the E1-safe rule until E3). The result is already validated and
## matched to the open run. Returns the minted uids.
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
	# 2. the flip
	var flip_ev := {}
	if r["warden_beaten"]:
		f["dead"] += f["living"]
		f["living"] = 0.0
		var fl: Dictionary = gs._cfg().get("flip", {})
		var hold_s := float(fl.get("hold_s", 300.0)) * (1.0 + float(fl.get("tier_mult", 0.25)) * float(f["tier"]))
		gs.realm.hold(fort_id, hold_s)  # RealmSim counts it down and stops her shipping there
		gs.realm.start_tithe()  # the first flip starts Vei's tithe cycle (a running one is left alone)
		f["flipped_count"] = int(f.get("flipped_count", 0)) + 1
		f["clears_since_retaken"] = int(f.get("clears_since_retaken", 0)) + 1
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
	# 10. death: the whole party is lost (A8), then the death rule; 11. otherwise she stays
	if died:
		for uid in party:
			remove_big_undead(gs, uid)
		death(gs, run_id)
	else:
		gs.relish["state"] = "at_fort"
	return minted


## §8.3 boss steps 1-5 (a final death by the E1-safe rule until E3).
static func writeback_boss(gs: GameState, r: Dictionary) -> void:
	var sd: Dictionary = gs.run["seed"]
	var run_id: int = gs.run["run_id"]
	var did_win: bool = r["won"]
	var bs: Dictionary = r["backups_spent"]
	var clones := int(bs["clones"])
	var deaths := int(r["relish_deaths"])
	var final_death := deaths == int(bs["phylactery"]) + clones + 1
	if did_win:
		gs.won = true
	else:
		var keep := float(gs._cfgs.get("vei", {}).get("loss_backlog_keep", 0.35))
		var before: float = gs.realm.vei["undead_queue"]
		gs.realm.vei["undead_queue"] = before * keep
		gs._ledger.sink("vei_fight", before - float(gs.realm.vei["undead_queue"]))
		for uid in seed_party_uids(gs, sd):
			remove_big_undead(gs, uid)
	for uid in r["party_lost"]:
		remove_big_undead(gs, uid)
	gs._phylactery_charges = maxi(0, gs._phylactery_charges - int(bs["phylactery"]))
	gs.clones_ready = maxi(0, gs.clones_ready - clones)
	gs.run = {}
	var cleared: Array = []
	for fid in r["fronts_cleared"]:
		cleared.append(str(fid))
	gs._emit({"type": "vei_result", "run_id": run_id, "won": did_win, "fronts_cleared": cleared,
		"relish_deaths": deaths, "backlog_after": float(gs.realm.vei["undead_queue"])})
	if final_death:
		death(gs, run_id)
	else:
		gs.relish["state"] = "at_vei"
