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
	var cap := {"bodies": ts.body_cap(), "gold": ts.gold_cap(), "bone": ts.bone_cap(), "living": ts.living_cap()}
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
		"war_overflow": float(gs.realm.r_war_to_vei), "war_supports": war_supports(gs, gs._fort_wars()),
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
	var tide_bias := gs._req_f("realm.relish.tide_bias")
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
	var wars := gs._fort_wars()
	for i in gs.realm.forts.size():
		var f: Dictionary = gs.realm.forts[i]
		forts.append(fort_entry(gs, f, wars[i]))
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
## staging included), ship_in (tithe surges included), held, the hold's readouts (garrison,
## garrison_rate, fall_s, margin, margin_cause, grace_s_left; MECHANICS §3.5, at the WAR the current
## valve sends it: `w_in`, gs._fort_wars()), relish_here, tide, redirect, siege, tithe, can_descend.
## held_s_left is deprecated (0.0). Threat and warden are still stubs.
static func fort_entry(gs: GameState, f: Dictionary, w_in: float) -> Dictionary:
	var id: String = f["id"]
	var why := gs._descend_reason(id)
	var fx := gs._relish_effects()
	var archetype := gs._warden_archetype(id)
	var ro := gs._fort_readout(f, w_in)
	var held := RealmSim.is_held(f)
	return {
		"id": id, "name": str(f["name"]), "tier": int(f["tier"]), "cap": float(f["cap"]),
		"pos": GameState._xy(f["pos"]),
		"living": float(f["living"]), "undead": float(f["undead"]), "dead": float(f["dead"]),
		"space": float(gs.realm.space(f)), "war_in": float(f["r_in"]), "ship_in": float(f["r_shipped"]),
		"held": held, "held_s_left": 0.0,
		"garrison": float(f["undead"]) if held else 0.0, "garrison_rate": float(ro["garrison_rate"]),
		"fall_s": float(ro["fall_s"]), "margin": str(ro["margin"]), "margin_cause": str(ro["margin_cause"]),
		"grace_s_left": maxf(0.0, float(f.get("grace_s", 0.0))) if held else 0.0,
		"flipped_count": int(f.get("flipped_count", 0)),
		"first_clear": not gs.cleared_forts.has(id), "first_dungeon": gs._is_first_dungeon(id),
		"clears_since_retaken": int(f.get("clears_since_retaken", 0)), "yield_mult": gs._yield_mult(f),
		"warden": {"archetype": archetype, "name": gs._warden_name(archetype), "tells": gs._warden_tells(archetype)},
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
	var i := 0
	while gs.realm.forts[i]["id"] != id:
		i += 1
	var out := {"rev": gs.rev}
	out.merge(fort_entry(gs, f, float(gs._fort_wars()[i])))
	return out


## §5.7 · E1: the legacy village control, with live dominance. A player village sends TownSim
## economy.json town.migrant_rate living/s (its held_villages input). A field that is not finite
## there (ticked at a step far past its stable dt) reads 0.0: the API carries no NaN or INF, and
## the owner is what the last field tick decided (GameState._dominance treats it as 0, so "none").
static func villages(gs: GameState) -> Dictionary:
	var rate := gs._req_f("economy.town.migrant_rate")
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
	var p_per_pit := gs._req_f("realm.P_per_pit")
	var haul_rate := gs._haul_rate()
	var staffed: Dictionary = ts.staffing.get("lots", {})
	var ups := projections(gs, "upgrades")
	var buildings: Array = []
	for lot_id in BuildRules.built_lots(gs):
		var b: Dictionary = ts.buildings[lot_id]
		var bid: String = b["building_id"]
		var cl := ts.construction_left(lot_id)
		var top := int(BuildRules.buildings_cfg(gs).get(bid, {}).get("max_level", 1))
		buildings.append({
			"lot_id": lot_id, "building_id": bid, "level": int(b["level"]),
			"state": str(b["state"]), "progress": float(b["progress"]), "slots": ts.lot_slots(lot_id),
			"staffed": float(staffed.get(lot_id, 0.0)), "staff_cap": int(b["staff_cap"]),
			"foreman": gs._foreman_of(lot_id), "output": ts.lot_output(lot_id, p_per_pit, haul_rate), "upkeep": BuildRules.upkeep_of(gs, bid),
			# v6 (E2b-2 T3.2, api-request #17): construction time, TownSim's own numbers
			"work_left": float(cl["left"]), "eta_s": float(cl["eta_s"]),
			"upgrade_work": ts.construction_work(bid, int(b["level"]) + 1) if int(b["level"]) < top else 0.0,
			# v6 (E2b-2 T3.2, api-request #9): the change in each net rate if its next level were finished now
			"upgrade_projected": (ups.get(lot_id, {}) as Dictionary).duplicate(),
			# v6 (T3.4a): why its mills milled less than their hands want (TownSim's last step); "" for a building without mill slots
			"starved": ts.mill_starved if ts.lot_mill_slots(lot_id) > 0 else "",
		})
	var effective := ts.effective_ladder(ts.ladder)
	var jobs := job_rows(effective, ts.staffing.get("jobs", {}))
	var r: Dictionary = ts.rates
	var w: Dictionary = r["workers"]
	return {
		"rev": gs.rev, "tier": gs.town_tier, "next_tier": BuildRules.next_tier(gs), "lots": lots, "buildings": buildings,
		"ladder": ts.ladder.duplicate(), "ladder_effective": effective, "jobs": jobs,
		"workers": {
			"total": ts.workers, "idle": float(ts.staffing.get("idle", 0.0)), "in": float(w["in"]), "rot": float(w["rot"]),
			"muster": float(w["muster"]), "steady": gs._workers_steady(),
			"steady_kept": float(gs._workers_steady_kept()["kept"]), "muster_steady": float(gs._workers_steady_kept()["muster"]), "lifetime_s": ts.lifetime_s(gs.relish["state"] == "home"),
		},
		"living": ts.living, "living_cap": ts.living_cap(),
		"migrants": float(r["living"]["in"]), "departures": float(r["living"]["out"]),
		"morale": {"value": ts.morale, "target": ts.morale_target(), "factors": ts.morale_factors()},
		"gold": ts.gold, "bone": ts.bone, "bodies": ts.bodies, "bodies_cap": ts.body_cap(), "trade_rate": float(r["trade_rate"]),
		"gold_cap": ts.gold_cap(), "bone_cap": ts.bone_cap(),
		"queue": BuildRules.queue_rows(gs), "queue_max": BuildRules.queue_max(gs),
		"haul": {"target": gs.haul_target, "current": str(ts.haul["current"]), "convoys": convoys(gs)},
		"relish_home": gs.relish["state"] == "home",
	}


## view_town's and the projection's `jobs`: the jobs with slots, in `order` (an effective ladder), from
## a staffing's {job: {slots, staffed}}.
static func job_rows(order: Array, by_job: Dictionary) -> Array:
	var jobs: Array = []
	for job in order:
		var js: Dictionary = by_job.get(job, {})
		if int(js.get("slots", 0)) > 0:
			jobs.append({"id": str(job), "slots": int(js["slots"]), "staffed": float(js["staffed"])})
	return jobs


## §5.16 · E2b (api_version 5, api-request #16): TownSim's staffing allocation (TownSim.staff_allocate,
## the one `_restaff` runs) on today's workforce, buildings and staff caps, with the job order replaced
## by `order` and `vats` overriding the staffed vats. Pure: nothing changes and `rev` stays. `jobs` lists
## the jobs with slots in the effective order of `order`, as view_town lists them in ladder_effective
## order; `buildings` every built lot (BuildRules.built_lots, view_town's order). An `order`
## cmd_set_job_priority would refuse returns its reason, with empty jobs and buildings and idle 0.0.
static func staffing_projection(gs: GameState, order: Array, vats: Dictionary) -> Dictionary:
	var why := gs._job_order_reason(order)
	if why != "":
		return {"rev": gs.rev, "jobs": [], "buildings": [], "idle": 0.0, "reason": why}
	var ts := gs.town_sim
	var o: Array = []
	for j in order:
		o.append(str(j))
	var st: Dictionary = ts.project_staffing(o, vats)["staffing"]
	var lots: Dictionary = st["lots"]
	var buildings: Array = []
	for lot_id in BuildRules.built_lots(gs):
		buildings.append({"lot_id": str(lot_id), "staffed": float(lots.get(lot_id, 0.0))})
	return {"rev": gs.rev, "jobs": job_rows(ts.effective_ladder(o), st["jobs"]), "buildings": buildings,
		"idle": float(st["idle"]), "reason": ""}


## view_hud.war_supports and view_projection's: {n: held forts whose garrison_rate ≥ 0 at `wars` (each
## fort's WAR, mass/s), m: held forts}.
static func war_supports(gs: GameState, wars: Array) -> Dictionary:
	var n := 0
	var m := 0
	for i in gs.realm.forts.size():
		var f: Dictionary = gs.realm.forts[i]
		if RealmSim.is_held(f):
			m += 1
			if gs._fort_rate(f, float(wars[i])) >= 0.0:
				n += 1
	return {"n": n, "m": m}


## §5.17 · E2b-2 (api_version 6, api-requests #7 c, #13): the readouts at another valve, pure. The
## valve is normalised as cmd_set_valve normalises it; one it would refuse, or one within 1e-12 of
## the current valve, is the current valve. At it: the split is this substep's mint × the valve (WAR
## plus TownSim's muster as it is now), split.war_overflow the WAR that falls through to Vei, each
## fort's WAR the last dispatch's split of that WAR (RealmSim.war_at), workers_steady TownSim's
## steady workforce scaled by the WORK share (the steady state is linear in WORK), backlog_diff the
## sustained differential (view_vei.diff_ema) moved by the FLOOD, the fall-through and the WAR to the
## forts whose garrison isn't pinned at 0 (it drains on to her queue) against today's, and the held
## forts' margins and war_supports as view_fort and view_hud compute them. At the current valve every
## field equals the live views'.
static func projection(gs: GameState, valve_in: Dictionary) -> Dictionary:
	var v := gs._projection_valve(valve_in)
	var mint := float(gs._split["mint"])
	var war: float = mint * v["war"] + float(gs._split["muster"])
	var split := {"work": mint * v["work"], "war": war, "flood": mint * v["flood"]}
	var wa: Array = gs.realm.war_at(war)
	var wars: Array = wa[0]
	split["war_overflow"] = float(wa[1])
	var cur_work := float(gs.valve["work"])
	var steady := 0.0
	if cur_work > 0.0:
		steady = gs._workers_steady() * (float(v["work"]) / cur_work)
	else:
		steady = mint * float(v["work"]) / gs.worker_mass() * gs.town_sim.lifetime_s(gs.relish["state"] == "home")
	var now_wars := gs._fort_wars()
	var diff := float(gs._readout["diff_ema"]) + (float(split["flood"]) - float(gs._split["flood"])) \
		+ (float(wa[1]) - float(gs.realm.r_war_to_vei))
	var margins := {}
	for i in gs.realm.forts.size():
		var f: Dictionary = gs.realm.forts[i]
		if float(f["undead"]) > 0.0:
			diff += float(wars[i]) - float(now_wars[i])
		if RealmSim.is_held(f):
			var ro := gs._fort_readout(f, float(wars[i]))
			margins[str(f["id"])] = {"margin": str(ro["margin"]), "margin_cause": str(ro["margin_cause"]),
				"fall_s": float(ro["fall_s"]), "garrison_rate": float(ro["garrison_rate"])}
	return {"rev": gs.rev, "valve": v.duplicate(), "split": split, "workers_steady": steady, "backlog_diff": diff,
		"war_supports": war_supports(gs, wars), "margins": margins}


## §5.10 · E2 (crafts E3): buildings.json in file order, with live gating.
static func catalog(gs: GameState) -> Dictionary:
	var rows := BuildRules.catalog_rows(gs)
	var out: Array = rows["buildings"]
	var proj := projections(gs, "catalog")
	for r in out:  # v6 (E2b-2 T3.2, api-request #9): the change in each net rate if it were finished now
		r["projected"] = (proj.get(r["building_id"], {}) as Dictionary).duplicate()
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


# ------------------------------------------------------------ build benefit ----
## The lot a catalog row's hypothetical goes on when no free unlocked lot fits it: after the last lot in
## TownSim's order, so it is staffed last in each job.
const HYPOTHETICAL_LOT := "lot-hypothetical"


## §5.10 / §5.9 (E2b-2 T3.2, api-request #9): the change in each net rate (RATE_IDS) if a building, or a
## built lot's next level, were finished now and staffed by the ladder, at today's state. The sim's own
## code, never a mirrored formula: a clone of TownSim with it finished (place_building, so TownSim's own
## allocation restaffs it), stepped one substep from the inputs the next core step will give TownSim,
## against a clone of today's TownSim stepped from the same inputs, so the step's own drift cancels. The
## mint is the next step's (GameState._mint at the clone's working pits and the feed now); work, war and
## flood are Δmint × the valve that step splits with (the current valve slewed one substep toward its
## target); backlog is Δflood plus the change in the WAR that falls through to Vei at that WAR
## (RealmSim.war_at, the split view_projection reads); corpses 0.0. Pure: the clones are thrown away.
## `part` is "catalog" ({building_id: projection}, view_catalog's) or "upgrades" ({lot_id: projection},
## view_town's; {} at max_level or while constructing).
## A row costs about one TownSim step (pre_vei: 21 catalog rows and 20 lots, about 20 ms for all), so the
## rows are cached and refreshed off the view calls: the views only read (a row not yet computed reads
## {}), and GameState._advance refreshes at most economy.json town.projection_rows_per_frame of them on a
## frame that ran no substep, late in the substep interval (projection_frame below). A row is stale once
## the structure changes (TownSim.structure_rev: a building's arrival or removal, level, state or staff
## cap, the ladder, the vats; the tier, the valve target or Relish's being home) or once
## town.projection_refresh_s (5 s) of sim time has passed since it was computed; a stale row keeps its last
## value until its turn, except that an upgrades row reads {} once its lot holds another building or level
## than the one it was computed for (a demolish and rebuild, a finished upgrade).
## town.projection_rows_per_call > 0 (a test override; the shipped value is 0) lets a call refresh that
## many of its own part's rows too, exactly, so a large value computes the view in full.
static func projections(gs: GameState, part: String) -> Dictionary:
	if part == "catalog":
		gs._proj_cache["wanted_t"] = gs.t  # the frame refresh runs only while the catalog is being read
	var per_call := int(gs._req_f("economy.town.projection_rows_per_call"))
	if per_call > 0:
		_proj_refresh(gs, [part], maxi(2, per_call), false)  # the baseline and at least one row
	var rows: Dictionary = _proj_part(gs, part)
	var out := {}
	for k in _proj_keys(gs, part):
		var r: Dictionary = rows.get(k[0], {})
		out[k[0]] = r["value"] if k[1] and not r.is_empty() and r["for"] == _proj_for(gs, part, k[0]) else {}
	return out


## What a row is computed for: an upgrades row, the lot's [building_id, level] (another building or level
## on the lot makes it read {} until it is refreshed); a catalog row, its building at level 1 (keyed by
## building id, so it can't belong to another building).
static func _proj_for(gs: GameState, part: String, key: String) -> Array:
	if part == "catalog":
		return [key, 1]
	var bl: Dictionary = gs.town_sim.buildings.get(key, {})
	return [str(bl.get("building_id", "")), int(bl.get("level", 0))]


## The frame refresh, called by GameState._advance on the frame path (a substep cap) after the loop, with
## `substeps` the substeps that call ran. It works only while the catalog is wanted (view_catalog() read
## within the last projection_refresh_s of sim; view_town() doesn't count, so the map and the raids pay
## nothing), and only on a frame that ran no substep with the substep accumulator holding at least
## town.projection_phase of a substep: there it refreshes at most town.projection_rows_per_frame units.
## Scenes refetch when rev moves, so their work bunches up in the frames just after a substep; background
## work belongs in the later part of the interval. When every frame substeps (fast-forward), one row goes
## through after town.projection_starve_frames such frames in a row (with the baseline it needs), whatever
## the phase. Returns the units computed.
static func projection_frame(gs: GameState, substeps: int) -> int:
	var since := gs.t - float(gs._proj_cache.get("wanted_t", -INF))
	if not (since >= 0.0 and since < gs._req_f("economy.town.projection_refresh_s")):
		gs._proj_cache["starve"] = 0
		return 0
	var budget := int(gs._req_f("economy.town.projection_rows_per_frame"))
	if substeps > 0:
		var starve := int(gs._proj_cache.get("starve", 0)) + 1
		gs._proj_cache["starve"] = starve
		if starve < int(gs._req_f("economy.town.projection_starve_frames")):
			return 0
		budget = 2 if (gs._proj_cache.get("base", {}) as Dictionary).get("state", []) != _proj_state(gs) else 1
	gs._proj_cache["starve"] = 0
	if substeps == 0 and gs._acc < gs._req_f("economy.town.projection_phase") * gs.substep_s():
		return 0  # early in the interval: the scenes' own work is here
	return _proj_refresh(gs, ["catalog", "upgrades"], budget, true)


## Refreshes at most `budget` stale units of `parts`, in a fixed order: the baseline first (recomputed only
## when the state has moved since it was made; it counts as one), then the stale rows of each part in view
## order (the catalog in buildings.json order, then the lots in lot order). With `tol` (the frame path) a
## refreshed row keeps its old value unless some rate moved past town.projection_tol, so the floats don't
## churn the town's row signatures every window; without it (a call's override) the value is exact.
## Drops the rows of lots that are gone. Returns the units computed. A scan of both parts that finds
## nothing stale leaves `fresh` [sig, the time the oldest row ages out, the scan's t]: until the sig moves or
## the time leaves that span no row can be stale, so the frames in between skip the scan (about 60 µs at
## pre_vei).
static func _proj_refresh(gs: GameState, parts: Array, budget: int, tol: bool) -> int:
	var sig := [gs.town_sim.structure_rev, gs.town_tier, gs.valve_target.duplicate(), gs.relish["state"] == "home"]
	var fresh: Array = gs._proj_cache.get("fresh", [])
	if not fresh.is_empty() and fresh[0] == sig and gs.t < float(fresh[1]) and gs.t >= float(fresh[2]):
		return 0
	var refresh := gs._req_f("economy.town.projection_refresh_s")
	var stale: Array = []
	var oldest := INF
	for part in parts:
		var rows := _proj_part(gs, part)
		var live := {}
		for k in _proj_keys(gs, part):
			live[k[0]] = true
			if k[1]:
				var r: Dictionary = rows.get(k[0], {})
				var age := gs.t - float(r.get("t", INF))
				if r.is_empty() or r["sig"] != sig or not (age >= 0.0 and age < refresh):
					stale.append([part, k[0]])
				else:
					oldest = minf(oldest, float(r["t"]))
		for key in rows.keys():
			if not live.has(key):
				rows.erase(key)
	if stale.is_empty() and parts.size() == 2:
		gs._proj_cache["fresh"] = [sig, oldest + refresh, gs.t]
	if stale.is_empty() or budget <= 0:
		return 0
	var used := 0
	var state := _proj_state(gs)
	var base: Dictionary = gs._proj_cache.get("base", {})
	if base.get("state", []) != state:
		base = _proj_base(gs)
		base["state"] = state
		gs._proj_cache["base"] = base
		used += 1
	for s in stale:
		if used >= budget:
			break
		var rows := _proj_part(gs, s[0])
		var v := _proj_row(gs, s[0], s[1], base)
		var old: Dictionary = rows.get(s[1], {})
		var made_for := _proj_for(gs, s[0], s[1])
		if tol and not old.is_empty() and old["for"] == made_for and not _proj_moved(gs, old["value"], v):
			v = old["value"]
		else:
			gs._proj_cache["rows_replaced"] = int(gs._proj_cache.get("rows_replaced", 0)) + 1
		rows[s[1]] = {"value": v, "t": gs.t, "sig": sig, "for": made_for}
		used += 1
	return used


## The state a baseline belongs to: a new rev, t or structure needs a new one.
static func _proj_state(gs: GameState) -> Array:
	return [gs.rev, gs.t, gs.town_sim.structure_rev]


## A part's cached rows {key: {value, t, sig, for}}, made empty on first use.
static func _proj_part(gs: GameState, part: String) -> Dictionary:
	if not gs._proj_cache.has(part):
		gs._proj_cache[part] = {}
	return gs._proj_cache[part]


## Whether a fresh projection `v` differs from the cached `old` by more than town.projection_tol: some
## rate moved by more than rel × |old| + abs (or the rate ids differ).
static func _proj_moved(gs: GameState, old: Dictionary, v: Dictionary) -> bool:
	if old.size() != v.size():
		return true
	var rel := gs._req_f("economy.town.projection_tol.rel")
	var floor_abs := gs._req_f("economy.town.projection_tol.abs")
	for id in v:
		if not old.has(id):
			return true
		var o := float(old[id])
		if absf(float(v[id]) - o) > rel * absf(o) + floor_abs:
			return true
	return false


## A part's rows in view order, as [key, projected]: the catalog's building ids in buildings.json order
## (every one projected); the built lots in lot order, projected unless constructing or at max_level.
static func _proj_keys(gs: GameState, part: String) -> Array:
	var out: Array = []
	if part == "catalog":
		for bid in BuildRules.buildings_cfg(gs):
			out.append([str(bid), true])
		return out
	for lot_id in BuildRules.built_lots(gs):
		var bl: Dictionary = gs.town_sim.buildings[lot_id]
		var top := int(BuildRules.buildings_cfg(gs).get(bl["building_id"], {}).get("max_level", 1))
		out.append([str(lot_id), bl["state"] != "constructing" and int(bl["level"]) < top])
	return out


## The baseline the rows diff against: the next step's inputs and valve, and today's TownSim stepped once.
## Shared by both parts at one state; counts as a row in a call's budget.
static func _proj_base(gs: GameState) -> Dictionary:
	gs._proj_cache["rows_computed"] = int(gs._proj_cache.get("rows_computed", 0)) + 1
	var dt := gs.substep_s()
	var b := {"dt": dt, "valve": gs._slewed_valve(dt), "feed": float(gs.town_sim.rates.get("feed", 0.0)),
		"inputs": gs._town_inputs(0.0)}
	b["rates"] = _proj_step(gs, gs.town_sim.clone(), b)
	return b


## Steps a hypothetical TownSim `ts` once from the baseline's inputs: {mint, muster, <town id>: net}.
static func _proj_step(gs: GameState, ts: TownSim, b: Dictionary) -> Dictionary:
	var dt := float(b["dt"])
	var mint := gs._mint(ts.pits(), float(b["feed"]))
	var inp: Dictionary = (b["inputs"] as Dictionary).duplicate()
	inp["work_mass"] = mint * float(b["valve"]["work"]) * dt + gs.work_pending
	var o := ts.step(dt, inp)
	var io := GameState._town_io(ts)
	var out := {"mint": mint, "muster": float(o["muster_mass"]) / dt}
	for id in io:
		out[id] = float(io[id][0]) - float(io[id][1])
	return out


## A stepped hypothetical `r` against the baseline `b`: {rate_id: Δ} over every RATE_IDS id.
static func _proj_diff(gs: GameState, r: Dictionary, b: Dictionary) -> Dictionary:
	var r0: Dictionary = b["rates"]
	var v: Dictionary = b["valve"]
	var dm := float(r["mint"]) - float(r0["mint"])
	var war0 := float(r0["mint"]) * float(v["war"]) + float(r0["muster"])
	var fell := float(gs.realm.war_at(war0 + dm * float(v["war"]))[1]) - float(gs.realm.war_at(war0)[1])
	var out := {}
	for id in GameState.RATE_IDS:
		match id:
			"mint":
				out[id] = dm
			"work", "war", "flood":
				out[id] = dm * float(v[id])
			"backlog":
				out[id] = dm * float(v["flood"]) + fell
			"corpses":
				out[id] = 0.0
			_:
				out[id] = float(r[id]) - float(r0[id])
	return out


## One row's projection against the baseline `b` (computed at the same state). A catalog row (`key` a
## building id): finished at level 1 on its first free lot (the catalog row's `lots[0]`), or, when none
## fits, on HYPOTHETICAL_LOT. An upgrades row (`key` a lot id): the lot's building one level up.
static func _proj_row(gs: GameState, part: String, key: String, b: Dictionary) -> Dictionary:
	gs._proj_cache["rows_computed"] = int(gs._proj_cache.get("rows_computed", 0)) + 1
	var ts := gs.town_sim.clone()
	if part == "catalog":
		var lots := BuildRules.free_lots(gs, int(BuildRules.buildings_cfg(gs)[key].get("lot_size", 1)))
		var lot_id: String = HYPOTHETICAL_LOT
		if lots.is_empty():
			ts._lots = ts._lots.duplicate()
			ts._lots.append(HYPOTHETICAL_LOT)
		else:
			lot_id = str(lots[0])
		ts.place_building(lot_id, key, 1)
	else:
		var bl: Dictionary = gs.town_sim.buildings[key]
		ts.place_building(key, str(bl["building_id"]), int(bl["level"]) + 1)
	return _proj_diff(gs, _proj_step(gs, ts, b), b)
