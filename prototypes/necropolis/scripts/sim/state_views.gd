class_name StateViews
extends RefCounted
## The view_* bodies (STATE-API 5), static only, taking the GameState they read: every view is a
## fresh deep copy with `rev` first, an unknown id gives {}. GameState keeps the public view_*
## methods, with their signatures, and forwards here. view_field (the live field) and the seed
## views (StateRuns) stay in GameState. The lane callout bookkeeping that the tick and the
## commands drive stays in GameState too; the lanes view only reads it.


static func relish(gs: GameState) -> Dictionary:
	var at: String = gs.relish["at"]
	var reason := gs._descend_reason(at)
	var travelling: bool = gs.relish["state"] == "travelling"
	return {
		"rev": gs.rev, "state": gs.relish["state"], "at": at, "target": gs.relish["target"],
		"pos": (gs.relish["pos"] as Array).duplicate(), "heading": float(gs.relish["heading"]),
		"speed": gs.travel_speed() if travelling else 0.0, "eta_s": gs._eta(),
		"dead_s_left": float(gs.relish["dead_s_left"]),
		"respawn_with_clone": bool(gs.relish["respawn_with_clone"]),
		"phylactery_charges": gs._phylactery_charges, "clones_ready": gs.clones_ready,
		"can_descend": reason == "" and not gs.realm.fort_by_id(at).is_empty(),
		"reason": reason,
		"run_id": int(gs.run.get("run_id", -1)), "run_kind": str(gs.run.get("kind", "")),
		"effects": gs._relish_effects().merged({"home": gs.relish["state"] == "home"}),
	}


## §5.1 · E2. Live: t, the time controls, relics and essence with their caps, won, the readout
## (sign, drain_s, odds), the valve and its split, the mint's rate, and TownSim's stocks, caps and
## net rates.
static func hud(gs: GameState) -> Dictionary:
	var ro := gs._vei_readout()
	var ts := gs.town_sim
	var stock := {"mint": -1.0, "workers": ts.workers, "bodies": ts.bodies, "gold": ts.gold, "bone": ts.bone, "living": ts.living}
	var cap := {"bodies": ts.body_cap(), "living": ts.living_cap()}
	var io := gs._rate_io()
	var rates: Array = []
	for id in GameState.HUD_RATE_IDS:
		var rate := float(io[id][0]) if id == "mint" else float(io[id][0]) - float(io[id][1])
		rates.append({"id": id, "rate": rate, "stock": float(stock[id]), "cap": float(cap.get(id, -1.0)), "unit": GameState._RATE_UNITS[id]})
	return {
		"rev": gs.rev, "game_id": gs.game_id, "t": float(gs.t), "time_scale": float(gs.time_scale), "paused": gs.paused, "rates": rates,
		"split": {"work": float(gs._split["work"]), "war": float(gs._split["war"]), "flood": float(gs._split["flood"])},
		"valve": gs.valve.duplicate(), "valve_target": gs.valve_target.duplicate(),
		"workers_steady": gs._workers_steady(), "workers_steady_kept": float(gs._workers_steady_kept()["kept"]),
		"war_overflow": float(gs.realm.r_war_to_vei),
		"relics": gs.relics, "relics_cap": gs._cap_of("relics"), "essence": gs.essence, "essence_cap": gs._cap_of("essence"),
		"sign": ro["sign"], "drain_s": ro["drain_s"], "odds": ro["odds"], "won": gs.won,
	}


## §5.2 · E2, live for every id from E2a (_rate_io): the valve streams and the realm's corpses and
## backlog are the last substep's (session only), the town's are TownSim's. `net` is in − out (0 for
## the pass-throughs); backlog's is view_vei's raw `diff`.
static func rates(gs: GameState) -> Dictionary:
	var rates := {}
	var io := gs._rate_io()
	for id in GameState.RATE_IDS:
		var e: Array = io[id]
		rates[id] = {"in": float(e[0]), "out": float(e[1]), "net": float(e[0]) - float(e[1]), "unit": GameState._RATE_UNITS[id]}
	return {"rev": gs.rev, "rates": rates}


## §5.3 · E2. Kinds in LANE_KINDS order, forts in world order: war covington→fort (staging at held
## forts included) and covington→vei (WAR that fell through); flood covington→vei and fort→vei
## (drain); work covington→covington (the valve's WORK); dead fort→vei; living vei→fort (shipping and
## surges); haul fort→covington (the convoy's fort, trip-averaged); redirect fort→fort (raised by
## Relish or a simulacrum). Rates are last substep's mass/s.
static func lanes(gs: GameState) -> Dictionary:
	var lanes: Array = []
	var tide: String = gs._relish_effects()["tide_fort"]
	var tide_bias := float(gs._cfg().get("relish", {}).get("tide_bias", 3.0))
	var wave: Dictionary = gs.realm.tithe.get("wave", {})
	var wave_fort: String = str(wave.get("fort_id", ""))
	for f in gs.realm.forts:
		add_lane(gs, lanes, "war", "covington", f["id"], f["r_in"], tide_bias if f["id"] == tide else 1.0)
	add_lane(gs, lanes, "war", "covington", "vei", gs.realm.r_war_to_vei, 1.0)
	add_lane(gs, lanes, "flood", "covington", "vei", gs.realm.r_flood, 1.0)
	for f in gs.realm.forts:
		add_lane(gs, lanes, "flood", f["id"], "vei", f["r_drain"], 1.0)
	add_lane(gs, lanes, "work", "covington", "covington", float(gs._split["work"]), 1.0)
	for f in gs.realm.forts:
		add_lane(gs, lanes, "dead", f["id"], "vei", f["r_dead_out"], 1.0)
	for f in gs.realm.forts:
		add_lane(gs, lanes, "living", "vei", f["id"], f["r_shipped"], float(wave.get("mult", 1.0)) if f["id"] == wave_fort else 1.0)
	var haul_fort := str(gs.town_sim.haul["current"])
	var haul_rate := gs._haul_rate()
	for f in gs.realm.forts:
		add_lane(gs, lanes, "haul", f["id"], "covington", haul_rate if f["id"] == haul_fort else 0.0, 1.0)
	for f in gs.realm.forts:
		add_lane(gs, lanes, "redirect", f["id"], f["id"], f["r_raised"], 1.0)
	return {"rev": gs.rev, "lanes": lanes}


## Appends a lane when it carries mass or a live callout (zero-rate lanes are otherwise omitted).
static func add_lane(gs: GameState, lanes: Array, kind: String, from: String, to: String, rate: float, bias: float) -> void:
	var id := GameState._lane_id(kind, from, to)
	var why := why_of(gs, id)
	if rate > 0.0 or why != "":
		lanes.append({"id": id, "from": from, "to": to, "kind": kind, "rate": float(rate), "bias": float(bias), "why": why})


static func why_of(gs: GameState, lane_id: String) -> String:
	var e: Variant = gs._why.get(lane_id)
	return str(e[0]) if e != null and gs.t < float(e[1]) else ""


## §5.4 · E1 (held_count live from E2a).
static func realm(gs: GameState) -> Dictionary:
	var forts: Array = []
	var held := 0
	for f in gs.realm.forts:
		forts.append(fort_entry(gs, f))
		if RealmSim.is_held(f):
			held += 1
	return {
		"rev": gs.rev, "size": gs._world_size(),
		"covington": {"pos": GameState._xy(gs.realm.cov_pos)},
		"vei": {
			"pos": GameState._xy(gs.realm.vei_pos),
			"radius": float(gs._cfgs.get("world", {}).get("vei", {}).get("radius", 150.0)),
			"living_pool": float(gs.realm.vei["living_pool"]), "pool_cap": gs._pool_cap(),
			"backlog": float(gs.realm.vei["undead_queue"]),
		},
		"forts": forts, "held_count": held, "digest_q": gs.digest_q(),
	}


static func simulacrum_charges(gs: GameState, fort_id: String) -> float:
	var n := 0.0
	for s in gs.realm.simulacra:
		if str(s.get("fort_id", "")) == fort_id:
			n += float(s.get("charges", 0.0))
	return n


## A fort in the view_fort shape, without `rev`. Live: masses, positions, war_in (WAR arriving,
## staging included), ship_in (tithe surges included), held, held_s_left, relish_here, tide,
## redirect, siege, tithe, can_descend. Threat and warden are still stubs.
static func fort_entry(gs: GameState, f: Dictionary) -> Dictionary:
	var id: String = f["id"]
	var why := gs._descend_reason(id)
	var fx := gs._relish_effects()
	var archetype := gs._warden_archetype(id)
	return {
		"id": id, "name": str(f["name"]), "tier": int(f["tier"]), "cap": float(f["cap"]),
		"pos": GameState._xy(f["pos"]),
		"living": float(f["living"]), "undead": float(f["undead"]), "dead": float(f["dead"]),
		"space": float(gs.realm.space(f)), "war_in": float(f["r_in"]), "ship_in": float(f["r_shipped"]),
		"held": RealmSim.is_held(f), "held_s_left": float(f.get("held_s", 0.0)),
		"flipped_count": int(f.get("flipped_count", 0)),
		"first_clear": not gs.cleared_forts.has(id), "first_dungeon": gs._is_first_dungeon(id),
		"clears_since_retaken": int(f.get("clears_since_retaken", 0)), "yield_mult": 1.0,
		"warden": {"archetype": archetype, "tells": (GameState._WARDEN_TELLS.get(archetype, []) as Array).duplicate()},
		"loot_hint": gs._loot_hint(id),
		"threat": {"party_strength": 0.0, "garrison_strength": 0.0, "risk": "low", "risk_pct": -1.0},
		"relish_here": gs._standing_fort() == id, "tide": fx["tide_fort"] == id, "redirect": fx["redirect_fort"] == id,
		"simulacrum_charges": simulacrum_charges(gs, id),
		"siege": gs._uids_at("fort:" + id),
		"tithe": fort_tithe(gs, id),
		"can_descend": why == "", "reason": why,
	}


## view_fort.tithe: targeted while a warning names the fort or its wave runs; eta_s is the time to
## the warned wave, 0.0 while the wave runs, else -1.0.
static func fort_tithe(gs: GameState, id: String) -> Dictionary:
	var w: Dictionary = gs.realm.tithe.get("warning", {})
	var wv: Dictionary = gs.realm.tithe.get("wave", {})
	var warned: bool = not w.is_empty() and w["fort_id"] == id
	var active: bool = not wv.is_empty() and wv["fort_id"] == id
	var eta := maxf(0.0, float(gs.realm.tithe["next_s"])) if warned else (0.0 if active else -1.0)
	return {"targeted": warned or active, "eta_s": eta, "wave_active": active}


## view_vei.tithe: the running wave's fort (eta_s 0.0), else the warned one (eta_s to its wave),
## else "" and -1.0 (no target chosen yet).
static func vei_tithe(gs: GameState) -> Dictionary:
	var w: Dictionary = gs.realm.tithe.get("warning", {})
	var wv: Dictionary = gs.realm.tithe.get("wave", {})
	var out := {"target": "", "eta_s": -1.0, "warning": not w.is_empty(), "wave_active": not wv.is_empty(), "wave_s_left": 0.0}
	if not wv.is_empty():
		out["target"] = str(wv["fort_id"])
		out["eta_s"] = 0.0
		out["wave_s_left"] = maxf(0.0, float(wv["s_left"]))
	elif not w.is_empty():
		out["target"] = str(w["fort_id"])
		out["eta_s"] = maxf(0.0, float(gs.realm.tithe["next_s"]))
	return out


## §5.5 · E1. can_descend/reason are cmd_begin_dungeon(id)'s own check.
static func fort(gs: GameState, id: String) -> Dictionary:
	var f := gs.realm.fort_by_id(id)
	if f.is_empty():
		return {}
	var out := {"rev": gs.rev}
	out.merge(fort_entry(gs, f))
	return out


## §5.7 · E1: the legacy village control, with live dominance. A player village sends TownSim
## economy.json town.migrant_rate living/s (its held_villages input). A field that is not finite
## there (ticked at a step far past its stable dt) reads 0.0: the API carries no NaN or INF, and
## the owner is what the last field tick decided (GameState._dominance treats it as 0, so "none").
static func villages(gs: GameState) -> Dictionary:
	var rate := float(gs._sec("economy", "town").get("migrant_rate", 0.012))
	var out: Array = []
	for tw in gs.towns:
		var owner: String = {"green": "player", "orange": "vei"}.get(tw["control"], "none")
		out.append({
			"id": str(tw["id"]), "name": str(tw["name"]), "pos": GameState._xy(tw["pos"]), "owner": owner,
			"dominance": gs._dominance(tw["pos"]), "migrants": rate if owner == "player" else 0.0,
		})
	return {"rev": gs.rev, "villages": out}


## TownSim's convoy as §5.9 convoys: out is Covington → fort, back is fort → Covington.
static func convoys(gs: GameState) -> Array:
	var out: Array = []
	for c in gs.town_sim.haul["convoys"]:
		var fid := str(c["fort"])
		var back: bool = c["phase"] == "back"
		out.append({"from": fid if back else "covington", "to": "covington" if back else fid,
			"phase": str(c["phase"]), "t": float(c["t"]), "load": float(c["load"])})
	return out


## §5.9 · E2: TownSim's town. Lots from town.json; buildings with their state, progress, slots,
## staffing, cap, foreman, output and upkeep; the ladder and its jobs; the workforce, the living,
## morale and its factors, the stocks and caps, trade, the convoy. Stances (ladder_effective) are E3.
static func town(gs: GameState) -> Dictionary:
	var ts := gs.town_sim
	var lots: Array = []
	for l in BuildRules.lots_cfg(gs):
		var id := str(l.get("id", ""))
		lots.append({"id": id, "size": int(l.get("size", 1)), "unlocked": BuildRules.lot_unlocked(gs, id),
			"building_id": str(ts.buildings.get(id, {}).get("building_id", ""))})
	var p_per_pit := float(gs._cfg().get("P_per_pit", 6.0))
	var haul_rate := gs._haul_rate()
	var staffed: Dictionary = ts.staffing.get("lots", {})
	var buildings: Array = []
	for lot_id in BuildRules.built_lots(gs):
		var b: Dictionary = ts.buildings[lot_id]
		var bid: String = b["building_id"]
		buildings.append({
			"lot_id": lot_id, "building_id": bid, "level": int(b["level"]),
			"state": str(b["state"]), "progress": float(b["progress"]), "slots": ts.lot_slots(lot_id),
			"staffed": float(staffed.get(lot_id, 0.0)), "staff_cap": int(b["staff_cap"]),
			"foreman": gs._foreman_of(lot_id), "output": ts.lot_output(lot_id, p_per_pit, haul_rate), "upkeep": BuildRules.upkeep_of(gs, bid),
		})
	var jobs: Array = []
	var by_job: Dictionary = ts.staffing.get("jobs", {})
	for job in ts.ladder:
		var js: Dictionary = by_job.get(job, {})
		if int(js.get("slots", 0)) > 0:
			jobs.append({"id": str(job), "slots": int(js["slots"]), "staffed": float(js["staffed"])})
	var r: Dictionary = ts.rates
	var w: Dictionary = r["workers"]
	return {
		"rev": gs.rev, "tier": gs.town_tier, "next_tier": BuildRules.next_tier(gs), "lots": lots, "buildings": buildings,
		"ladder": ts.ladder.duplicate(), "ladder_effective": ts.ladder.duplicate(), "jobs": jobs,
		"workers": {
			"total": ts.workers, "idle": float(ts.staffing.get("idle", 0.0)), "in": float(w["in"]), "rot": float(w["rot"]),
			"muster": float(w["muster"]), "steady": gs._workers_steady(),
			"steady_kept": float(gs._workers_steady_kept()["kept"]), "muster_steady": float(gs._workers_steady_kept()["muster"]), "lifetime_s": ts.lifetime_s(gs.relish["state"] == "home"),
		},
		"living": ts.living, "living_cap": ts.living_cap(),
		"migrants": float(r["living"]["in"]), "departures": float(r["living"]["out"]),
		"morale": {"value": ts.morale, "target": ts.morale_target(), "factors": ts.morale_factors()},
		"gold": ts.gold, "bone": ts.bone, "bodies": ts.bodies, "bodies_cap": ts.body_cap(), "trade_rate": float(r["trade_rate"]),
		"haul": {"target": gs.haul_target, "current": str(ts.haul["current"]), "convoys": convoys(gs)},
		"relish_home": gs.relish["state"] == "home",
	}


## §5.10 · E2 (crafts E3): buildings.json in file order, with live gating.
static func catalog(gs: GameState) -> Dictionary:
	var rows := BuildRules.catalog_rows(gs)
	var out: Array = rows["buildings"]
	var bps: Array = rows["blueprints"]
	var crafts: Array = []
	for id in GameState.CRAFT_IDS:
		var c: Dictionary = gs._sec("economy", "craft").get(id, {})
		var cost := {"essence": int(c.get("essence", 0)), "relics": int(c.get("relics", 0))}
		var why := ""
		if gs._count_built("ossuary_tower") == 0:
			why = "needs_building"
		elif gs.essence < cost["essence"]:
			why = "no_essence"
		elif gs.relics < cost["relics"]:
			why = "no_relics"
		crafts.append({"item_id": id, "cost": cost, "can_craft": why == "", "reason": why})
	var bp_list: Array = []
	for b in bps:
		bp_list.append({"id": b, "owned": gs.blueprints.has(b)})
	return {"rev": gs.rev, "buildings": out, "crafts": crafts, "blueprints": bp_list}


static func beat_id(gs: GameState) -> int:
	var beat_s := float(gs._cfgs.get("pulse", {}).get("tempo_ms", 1714)) / 1000.0
	return int(floor(gs.t / beat_s)) if beat_s > 0.0 else 0


## §5.11 · E3. E1 echoes cmd_set_stance: nothing fires, nothing is projected.
static func stances(gs: GameState) -> Dictionary:
	var slots := gs._stance_slots()
	var list: Array = []
	for id in GameState.STANCE_IDS:
		var idx := gs.stances_on.find(id)
		list.append({"id": id, "on": idx >= 0, "suspended": idx >= slots, "active": false,
			"fired_beat_id": -1, "hold_s_left": 0.0, "projected": {}})
	return {"rev": gs.rev, "slots": slots, "used": mini(gs.stances_on.size(), slots), "beat_id": beat_id(gs), "stances": list}


## §5.12 · E1. Simulacra and phylactery charges are E3 (0).
static func inventory(gs: GameState) -> Dictionary:
	var hs: Array = []
	for h in gs.husks:
		hs.append({"uid": h["uid"], "kind": h["kind"]})
	var rs: Array = []
	for r in gs.remnants:
		rs.append({"uid": r["uid"], "aspect": r["aspect"], "rarity": r["rarity"], "magnitude": int(r["magnitude"])})
	var bps := gs.blueprints.duplicate()
	bps.sort()
	return {
		"rev": gs.rev, "husks": hs, "remnants": rs, "blueprints": bps,
		"relics": gs.relics, "relics_cap": gs._cap_of("relics"), "essence": gs.essence, "essence_cap": gs._cap_of("essence"),
		"simulacra_ready": 0, "phylactery_charges": gs._phylactery_charges,
	}


## A big undead as views and command extras show it (§5.12).
static func bu_entry(gs: GameState, b: Dictionary) -> Dictionary:
	var st := {}
	for k in GameState.STATS:
		st[k] = float(b["stats"].get(k, 0.0))
	return {"uid": b["uid"], "name": b["name"], "kind": b["kind"], "role": b["role"], "stats": st,
		"place": b["place"], "front": b["front"]}


## §5.12 · E1.
static func big_undead(gs: GameState) -> Dictionary:
	var out: Array = []
	for b in gs.big_undead:
		out.append(bu_entry(gs, b))
	return {"rev": gs.rev, "cap": gs._cap_of("big_undead"), "count": gs.big_undead.size(), "big_undead": out}


## §5.12 · E1. The garrison and starter figures are §7.1's for the fort she stands at;
## strength is E2 (0).
static func party(gs: GameState) -> Dictionary:
	var out: Array = []
	for u in gs.party_uids:
		var b := gs._find_uid(gs.big_undead, u)
		if not b.is_empty():
			out.append(bu_entry(gs, b))
	var fid := gs._standing_fort()
	var g := gs._garrison(fid)
	return {"rev": gs.rev, "party": out, "fort_id": fid, "garrison_units": g[0], "garrison_in_mass": g[1],
		"starter_units": gs._starter_units(fid), "strength": 0.0}


## §5.13 · E3. Until E3: clones_ready is the stub stock and each ready clone is a vat slot; the
## E1-safe death rule (a clone if one is ready, else unmade with the morale shock) with an
## immediate respawn.
static func backups(gs: GameState) -> Dictionary:
	var n := gs._vat_slots()
	var vats: Array = []
	for i in n:
		vats.append(gs._vat_entry(i))
	var outcome := "clone" if gs.clones_ready > 0 else "unmade"
	var loses: Array = []
	if not gs.party_uids.is_empty():
		loses.append("party")
	loses.append("unbanked_loot")
	if outcome == "unmade":
		loses.append("morale")
	return {
		"rev": gs.rev, "phylactery_charges": gs._phylactery_charges, "phylactery_max_per_dungeon": gs._phylactery_max(),
		"clones_ready": gs.clones_ready, "vats": vats, "death": {"outcome": outcome, "respawn_s": 0.0, "loses": loses},
		"dead_s_left": float(gs.relish["dead_s_left"]),
	}


## §5.14 · E2 (fronts E3; assigned is live). The readout, q and the tithe are live.
## can_begin/reason are cmd_begin_boss()'s check.
static func vei(gs: GameState) -> Dictionary:
	var ro := gs._vei_readout()
	var why := gs._boss_reason()
	return {
		"rev": gs.rev, "backlog": float(gs.realm.vei["undead_queue"]), "living_pool": float(gs.realm.vei["living_pool"]),
		"pool_cap": gs._pool_cap(), "diff": float(ro["diff"]), "diff_ema": float(ro["diff_ema"]),
		"sign": ro["sign"], "drain_s": ro["drain_s"], "odds": ro["odds"], "digest_q": gs.digest_q(),
		"fronts": gs._fronts(true), "fronts_required": gs._fronts_required(), "fronts_met": 0,
		"tithe": vei_tithe(gs),
		"can_begin": why == "", "reason": why, "won": gs.won,
	}
