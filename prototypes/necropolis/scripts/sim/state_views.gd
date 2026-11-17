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
		"returned": gs.relish_returned.duplicate(),
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
	var train: Dictionary = gs._train_live()["forts"]
	var plan := gs._train_support(gs._train_war(), true)
	for i in gs.realm.forts.size():
		var f: Dictionary = gs.realm.forts[i]
		forts.append(fort_entry(gs, f, wars[i], train.get(str(f["id"]), {}), plan.get(str(f["id"]), [])))
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
## valve sends it: `w_in`, gs._fort_wars(); the margin the wave train's, `train` being the fort's
## gs._train_live() entry; fall_s the earlier at the current and the planned support, `plan` the fort's
## gs._train_support() entry), relish_here, tide, redirect, siege, tithe, can_descend. held_s_left is
## deprecated (0.0). Threat and warden are still stubs.
static func fort_entry(gs: GameState, f: Dictionary, w_in: float, train := {}, plan := []) -> Dictionary:
	var id: String = f["id"]
	var why := gs._descend_reason(id)
	var fx := gs._relish_effects()
	var archetype := gs._warden_archetype(id)
	var ro := gs._fort_readout(f, w_in, train, plan)
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
	var held := RealmSim.is_held(f)
	var train: Dictionary = gs._train_live()["forts"].get(id, {}) if held else {}
	var plan: Array = gs._train_support(gs._train_war(), true).get(id, []) if held else []
	out.merge(fort_entry(gs, f, float(gs._fort_wars()[i]), train, plan))
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
## morale and its factors, the stocks and caps, trade, the convoy. ladder_effective is the ladder after the
## stances acting (E3-1: TownSim.effective_ladder).
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
			# E3-1: a building the Thrift stance idles reads "idle" (§5.9: "no staff, or a stance idles it")
			"lot_id": lot_id, "building_id": bid, "level": int(b["level"]),
			"state": "idle" if b["state"] == "thrift" else str(b["state"]), "progress": float(b["progress"]), "slots": ts.lot_slots(lot_id),
			"staffed": float(staffed.get(lot_id, 0.0)), "staff_cap": int(b["staff_cap"]),
			"foreman": gs._foreman_of(lot_id), "output": ts.lot_output(lot_id, p_per_pit, haul_rate), "upkeep": BuildRules.upkeep_of(gs, bid),
			# v6 (E2b-2 T3.2, api-request #17): construction time, TownSim's own numbers
			"work_left": float(cl["left"]), "eta_s": float(cl["eta_s"]),
			"upgrade_work": ts.construction_work(bid, int(b["level"]) + 1) if int(b["level"]) < top else 0.0,
			# v6 (E2b-2 T3.2, api-request #9): the change in each net rate if its next level were finished now
			"upgrade_projected": (ups.get(lot_id, {}) as Dictionary).duplicate(),
			# v6 (T3.4a): why its mills milled less than their hands want (TownSim's last step); "" for a building without mill slots
			"starved": ts.mill_starved if ts.lot_mill_slots(lot_id) > 0 else "",
			# v8 (E3-3): the multiplier its foreman gives its job output now (1.0 with none, or where one gives nothing)
			"foreman_mult": ts.foreman_mult(lot_id),
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
## field equals the live views', the margins with `settled` (E2b-2 T3.4b).
## Margins: by default (a drag) the one-wave probe, each row margin_verified false; with `settled` the wave
## train at that valve (gs._train_valve, cached on the valve's WAR and the state), margin_verified true, the
## same verdict view_fort reads at the current valve. The train and the fall clock's plan read the settled WAR
## at the valve (gs._train_war_at: the trough feed's mint and the steady muster at its WORK; E4 must-fix #1).
static func projection(gs: GameState, valve_in: Dictionary, settled := false) -> Dictionary:
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
	# the train and the fall clock's plan read the settled WAR at that valve (gs._train_war_at, E4 must-fix #1),
	# as view_fort reads it at the valve's target; garrison_rate and war_supports stay at the split above
	var war_s := gs._train_war_at(v)
	var train: Dictionary = gs._train_valve(war_s)["forts"] if settled else {}
	var plan := gs._train_support(war_s, false)  # the valve's split with Relish where she is travelling to
	for i in gs.realm.forts.size():
		var f: Dictionary = gs.realm.forts[i]
		if float(f["undead"]) > 0.0:
			diff += float(wars[i]) - float(now_wars[i])
		if RealmSim.is_held(f):
			var id := str(f["id"])
			var ro := gs._fort_readout(f, float(wars[i]), train.get(id, {}), plan.get(id, []))
			margins[id] = {"margin": str(ro["margin"]), "margin_cause": str(ro["margin_cause"]),
				"fall_s": float(ro["fall_s"]), "garrison_rate": float(ro["garrison_rate"]), "margin_verified": settled}
	return {"rev": gs.rev, "valve": v.duplicate(), "split": split, "workers_steady": steady, "backlog_diff": diff,
		"war_supports": war_supports(gs, wars), "margins": margins}


## §5.10 · E2 (crafts E3): buildings.json in file order, with live gating. The crafts' reasons are cmd_craft's
## (GameState._craft_reason, E3-4) and their costs economy.json craft.<id>'s.
static func catalog(gs: GameState) -> Dictionary:
	var rows := BuildRules.catalog_rows(gs)
	var out: Array = rows["buildings"]
	var proj := projections(gs, "catalog")
	for r in out:  # v6 (E2b-2 T3.2, api-request #9): the change in each net rate if it were finished now
		r["projected"] = (proj.get(r["building_id"], {}) as Dictionary).duplicate()
	var bps: Array = rows["blueprints"]
	var crafts: Array = []
	for id in GameState.CRAFT_IDS:
		var why := gs._craft_reason(id)
		crafts.append({"item_id": id, "cost": gs._craft_cost(id), "can_craft": why == "", "reason": why})
	var bp_list: Array = []
	for b in bps:
		bp_list.append({"id": b, "owned": gs.blueprints.has(b)})
	# v9 (E4, lever (b)): the husk craft (cmd_craft_husk), its kinds, price and the kind-free reason it would answer now
	var hw := gs._husk_craft_reason("")
	var husk := {"kinds": gs.husk_craft_kinds(), "cost": {"bone": gs._req_f("economy.craft.husk.bone"),
		"remnants": int(gs._req_f("economy.craft.husk.remnants"))}, "can_craft": hw == "", "reason": hw}
	return {"rev": gs.rev, "buildings": out, "crafts": crafts, "blueprints": bp_list, "husk_craft": husk}


static func beat_id(gs: GameState) -> int:
	var beat_s := float(gs._cfgs.get("pulse", {}).get("tempo_ms", 1714)) / 1000.0
	return int(floor(gs.t / beat_s)) if beat_s > 0.0 else 0


## §5.11 · E3 (live from E3-1, MECHANICS §4.5): each stance's toggle and suspension, its condition (`active`, for
## every stance, on or off: GameState._stance_step), the beat of its last change, its hold left, and `projected`
## (stance_projections).
static func stances(gs: GameState) -> Dictionary:
	var slots := gs._stance_slots()
	var proj := stance_projections(gs)
	var list: Array = []
	for id in GameState.STANCE_IDS:
		var idx := gs.stances_on.find(id)
		list.append({"id": id, "on": idx >= 0, "suspended": idx >= slots, "active": gs._stance_active.has(id),
			"fired_beat_id": int(gs._stance_fired.get(id, -1)), "hold_s_left": maxf(0.0, float(gs._stance_hold.get(id, 0.0))),
			"projected": (proj[id] as Dictionary).duplicate()})
	return {"rev": gs.rev, "slots": slots, "used": mini(gs.stances_on.size(), slots), "beat_id": beat_id(gs), "stances": list}


## view_stances' `projected` (STATE-API §5.11, E3-1): for each stance, the change in each net rate per second if it
## were toggled now, as cmd_set_stance would toggle it (turning one on that no slot has room for changes nothing;
## turning an older one off can free a slot for a suspended one). Pure, no rev, no event: the stances that would act
## then (GameState._acting_of; `active` as it stands) give TownSim.stance_flows' flows from the one allocation
## (staff_allocate) on the effective ladder they make, Muster's idle cap and Thrift's buildings (the ones it idles
## now, or TownSim.thrift_pick's when it would start acting), against the same flows for the stances acting now:
## - workers, bodies, gold, bone, living: the change in that net (per second);
## - mint: the change in the next step's mint (GameState._mint at the pits' feed); work, war and flood: Δmint × the
##   valve the next step splits with (the current valve slewed one substep), war plus Δmuster × worker.mass;
##   backlog: Δflood plus the change in the WAR that falls through to Vei (RealmSim.war_at), as the build card's;
## - corpses: minus the change in the haul (the convoy takes the corpses it brings).
## Sparse: a rate the toggle leaves alone is absent, and a stance whose toggle changes no stance's acting (an
## inactive one, or one no slot has room for) reads {}. Cached on [rev, t, structure_rev] (gs._stance_proj).
static func stance_projections(gs: GameState) -> Dictionary:
	var key := [gs.rev, gs.t, gs.town_sim.structure_rev]
	var cached: Array = gs._stance_proj
	if not cached.is_empty() and cached[0] == key:
		return cached[1]
	var out := {}
	var now := gs._acting_of(gs.stances_on)
	var base := {}
	for id in GameState.STANCE_IDS:
		var on_list: Array = gs.stances_on.duplicate()
		if on_list.has(id):
			on_list.erase(id)
		elif on_list.size() < gs._stance_slots():
			on_list.append(id)
		var acting := gs._acting_of(on_list)
		if acting == now:
			out[id] = {}
			continue
		if base.is_empty():
			base = _stance_flows(gs, now, now)
		out[id] = _stance_diff(gs, _stance_flows(gs, acting, now), base)
	gs._stance_proj = [key, out]
	return out


## TownSim.stance_flows for the stances `acting`, `now` those acting today (Thrift's buildings: the ones it idles
## while it acts and keeps acting, thrift_pick's when it would start).
static func _stance_flows(gs: GameState, acting: Dictionary, now: Dictionary) -> Dictionary:
	var ts := gs.town_sim
	var thrift := {}
	if acting.has("thrift"):
		for lot_id in (ts.thrift_pick() if not now.has("thrift") else ts._lists()["thrift"]):
			thrift[lot_id] = true
	return ts.stance_flows(gs._top_jobs_of(acting), acting.has("muster"), thrift, gs.relish["state"] == "home", gs.green_towns)


## A toggled stance's flows `r` against today's `b` (stance_projections): {rate_id: Δ}, only the rates that move.
static func _stance_diff(gs: GameState, r: Dictionary, b: Dictionary) -> Dictionary:
	var v := gs._slewed_valve(gs.substep_s())
	var dm := gs._mint(float(r["pits"]), float(r["feed"])) - gs._mint(float(b["pits"]), float(b["feed"]))
	var d_must := (float(r["muster"]) - float(b["muster"])) * gs.worker_mass()
	var war0 := float(gs._split["mint"]) * float(v["war"]) + float(gs._split["muster"])
	var d_war := dm * float(v["war"]) + d_must
	var fell := 0.0
	if d_war != 0.0:
		fell = float(gs.realm.war_at(war0 + d_war)[1]) - float(gs.realm.war_at(war0)[1])
	var all := {"mint": dm, "work": dm * float(v["work"]), "war": d_war, "flood": dm * float(v["flood"]),
		"backlog": dm * float(v["flood"]) + fell, "corpses": -(float(r["haul"]) - float(b["haul"]))}
	for id in ["workers", "bodies", "gold", "bone", "living"]:
		all[id] = float(r[id]) - float(b[id])
	var out := {}
	for id in GameState.RATE_IDS:
		if float(all[id]) != 0.0:
			out[id] = float(all[id])
	return out


## §5.12 · E1. The simulacra ready and the phylactery charges are GameState's stocks (E3-4: cmd_craft adds to them;
## a raid's revives in place spend the charges, E3-2).
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
		"simulacra_ready": gs.simulacra_ready, "phylactery_charges": gs._phylactery_charges,
	}


## A big undead as views and command extras show it (§5.12).
static func bu_entry(gs: GameState, b: Dictionary) -> Dictionary:
	var st := {}
	for k in GameState.STATS:
		st[k] = float(b["stats"].get(k, 0.0))
	return {"uid": b["uid"], "name": b["name"], "kind": b["kind"], "role": b["role"], "stats": st,
		"place": b["place"], "front": b["front"], "filled_slots": GameState.filled_slots_of(b)}  # filled_slots: v8, E3-3


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


## §5.13 · E3, live from E3-2: each vat's `grow` is its clone (GameState.vats_grow, grown while it is tended), ready
## at 1, and clones_ready is the vats at 1 plus any spare clones (the old-save rule); `death` is the death rule at the
## charges and clones now (death_rule), and dead_s_left her respawn's seconds left.
static func backups(gs: GameState) -> Dictionary:
	var n := gs._vat_slots()
	var vats: Array = []
	for i in n:
		vats.append(gs._vat_entry(i))
	return {
		"rev": gs.rev, "phylactery_charges": gs._phylactery_charges, "phylactery_max_per_dungeon": gs._phylactery_max(),
		"clones_ready": gs.clones_ready, "vats": vats, "death": death_rule(gs, gs.clones_ready, gs._phylactery_charges),
		"dead_s_left": float(gs.relish["dead_s_left"]),
	}


## The death rule (§5.13 `death`; E3-2, MECHANICS §7's order): what a death at HP 0 in the next run costs with
## `charges` phylactery charges and `clones` clones ready:
## 1. a charge, while phylactery.max_per_dungeon lets a dungeon use one: she revives in place and the run goes on, so
##    it loses nothing ("phylactery", respawn_s 0.0, loses []);
## 2. a ready clone: she wakes at Covington after backups.clone_respawn_s ("clone");
## 3. else she is unmade: she reforms after backups.unmade_respawn_s, and the town takes the morale shock ("unmade").
## `loses` for a death that ends the run: the party (if any: the whole party, in both outcomes, A8), the unbanked
## loot, and the morale when unmade. view_backups' death reads it at the charges and clones now; a death that ends
## the run (StateRuns.death) and the seeds' death_ends (StateRuns.death_ends) read it with no charge, past the
## revives.
static func death_rule(gs: GameState, clones: int, charges := 0) -> Dictionary:
	if mini(charges, gs._phylactery_max()) > 0:
		return {"outcome": "phylactery", "respawn_s": 0.0, "loses": []}
	var outcome := "clone" if clones > 0 else "unmade"
	var loses: Array = []
	if not gs.party_uids.is_empty():
		loses.append("party")
	loses.append("unbanked_loot")
	if outcome == "unmade":
		loses.append("morale")
	var respawn_s := gs._req_f("backups.backups.clone_respawn_s" if outcome == "clone" else "backups.backups.unmade_respawn_s")
	return {"outcome": outcome, "respawn_s": respawn_s, "loses": loses}


## §5.14 · E2 (fronts live from E3-5, v8). The readout, q and the tithe are live; the fronts are VeiFronts.have_need's
## on the state now (GameState._fronts on _front_info), with `assigned` cmd_assign_front's echo and `counted` the uids
## VeiFronts counted, and fronts_met is VeiFronts.fronts_met of them. can_begin/reason are cmd_begin_boss()'s check.
static func vei(gs: GameState) -> Dictionary:
	var ro := gs._vei_readout()
	var why := gs._boss_reason()
	var fronts := gs._fronts(gs._front_info(), true)
	return {
		"rev": gs.rev, "backlog": float(gs.realm.vei["undead_queue"]), "living_pool": float(gs.realm.vei["living_pool"]),
		"pool_cap": gs._pool_cap(), "diff": float(ro["diff"]), "diff_ema": float(ro["diff_ema"]),
		"sign": ro["sign"], "drain_s": ro["drain_s"], "odds": ro["odds"], "digest_q": gs.digest_q(),
		"fronts": fronts, "fronts_required": gs._fronts_required(), "fronts_met": VeiFronts.fronts_met(fronts),
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
	var mint := gs._mint(ts.pit_weight(), float(b["feed"]))
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


# ---------------------------------------------------------------- the away report ----
## §5.19 · E2b-2 (v6, T3.3c; IDLE §7, api-request #7 d): the last away report, kept until dismissed (gs._away;
## {} before any), as a deep copy.
static func away(gs: GameState) -> Dictionary:
	var a: Dictionary = gs._away
	return {
		"rev": gs.rev, "shown": bool(a.get("shown", false)), "away_s": float(a.get("away_s", 0.0)),
		"capped": bool(a.get("capped", false)), "gains": (a.get("gains", []) as Array).duplicate(true),
		"ready": (a.get("ready", []) as Array).duplicate(true), "losses": (a.get("losses", []) as Array).duplicate(true),
	}


## The stream stocks the report's gains diff (IDLE §7): Vei's backlog, the mint booked so far (the ledger's
## sources.mint), and Covington's workers, bodies, gold, bone and living.
static func away_streams(gs: GameState) -> Dictionary:
	var ts := gs.town_sim
	return {"backlog": float(gs.realm.vei["undead_queue"]), "mint": float(gs._ledger.sources.get("mint", 0.0)),
		"workers": float(ts.workers), "bodies": float(ts.bodies), "gold": float(ts.gold), "bone": float(ts.bone),
		"living": float(ts.living)}


## What a reporting catch-up starts from (Catchup.begin), for the report's before-and-after: the time, the
## stream stocks, the caps' overflow tallies (ledger().stores), each fort's hold and loot yield, the
## village owners, and the lots whose building is unpaid (R1: their unpaid lines count from the start) or idled by
## the Thrift stance (E3-1: their Thrift lines too).
static func away_before(gs: GameState) -> Dictionary:
	var forts := {}
	for f in gs.realm.forts:
		forts[str(f["id"])] = {"held": RealmSim.is_held(f), "yield": gs._yield_mult(f)}
	var villages := {}
	for tw in gs.towns:
		villages[str(tw["id"])] = str(tw["control"])
	var unpaid: Array = []
	var thrift: Array = []  # E3-1: the lots the Thrift stance idles (their Thrift lines count from the start)
	for lot_id in gs.town_sim.buildings:
		if gs.town_sim.buildings[lot_id]["state"] == "unpaid":
			unpaid.append(str(lot_id))
		elif gs.town_sim.buildings[lot_id]["state"] == "thrift":
			thrift.append(str(lot_id))
	return {"t": gs.t, "streams": away_streams(gs), "overflow": _overflow(gs), "forts": forts, "villages": villages,
		"unpaid": unpaid, "thrift": thrift}


static func _overflow(gs: GameState) -> Dictionary:
	var tally := gs._ledger.stores_copy()
	var out := {}
	for k in ["gold", "bone"]:
		out[k] = float(tally.get(k, {}).get("overflow", 0.0))
	return out


## The report (IDLE §7) of a catch-up of `away_s` seconds (`capped`) from `b` (away_before) to now, with the
## events it collected (`evs`): gains, ready and losses, each line {text, kind, target}, the text from
## economy.json idle.report. Numbers in the text are the map's tokens: a signed rate ending in /s, a mass a
## bare number with thousands commas, nothing glued to a word (AwayLogic.spans).
static func away_report(gs: GameState, b: Dictionary, evs: Array, away_s: float, capped: bool) -> Dictionary:
	var rep: Dictionary = gs._req("economy.idle.report")
	var gains: Array = []
	var ready: Array = []
	var losses: Array = []
	# gains: each stream's net rate and net total, the backlog with its arrow and Vei's odds before and after (E4 step 3:
	# "away: +N, odds A → B"; odds = backlog / (backlog + K), MECHANICS §3 step 8)
	var now := away_streams(gs)
	var k_odds := gs._req_f("realm.K")
	for id in rep["streams"]:
		var total := float(now[id]) - float(b["streams"][id])
		var rate := total / away_s if away_s > 0.0 else 0.0
		var arrow := str(rep["arrow_up"]) if total > 0.0 else (str(rep["arrow_down"]) if total < 0.0 else str(rep["arrow_flat"]))
		var fmt := str(rep["backlog_fmt"] if id == "backlog" else rep["stream_fmt"])
		var b0 := float(b["streams"]["backlog"])
		var b1 := float(now["backlog"])
		gains.append(_away_line(fmt.format({"label": str(rep["stream_labels"][id]), "arrow": arrow,
			"rate": _fmt_rate(rep, rate), "total": _fmt_signed(rep, total),
			"odds_from": "%.2f" % (b0 / (b0 + k_odds)), "odds_to": "%.2f" % (b1 / (b1 + k_odds))}), "stream", ""))
	# builds finished, then each queued build that started, with when (since you left) and why
	var done: Array = []
	for e in evs:
		if e["type"] == "building_done":
			done.append(_building_name(gs, rep, str(e["building_id"]), int(e["level"])))
	if not done.is_empty():
		var fmt := str(rep["builds_one_fmt"] if done.size() == 1 else rep["builds_fmt"])
		gains.append(_away_line(fmt.format({"n": _fmt_count(rep, done.size()), "names": str(rep["list_sep"]).join(PackedStringArray(done))}), "build", ""))
	for e in evs:
		if e["type"] != "queue_started":
			continue
		var name := _building_name(gs, rep, str(e["building_id"]), int(e["level"]))
		var w := str(e["waited_on"])
		if w == "":
			gains.append(_away_line(str(rep["started_now_fmt"]).format({"name": name}), "build", ""))
		else:
			var since := float(e["t"]) - float(b["t"])
			# W2: it waited but began under a minute in (the same cutoff as _unpaid_lines' "briefly": where _when
			# would read "0 m")
			if since < 60.0:
				gains.append(_away_line(str(rep["started_brief_fmt"]).format({"name": name, "why": _why_started(rep, w)}), "build", ""))
			else:
				gains.append(_away_line(str(rep["started_fmt"]).format({"name": name, "when": _when(rep, since),
					"why": _why_started(rep, w)}), "build", ""))
	# forts refilled: held now, not retaken while away, the loot yield below full when you left and full now
	var retaken: Array = []
	var walked := {}
	for e in evs:
		if e["type"] == "fort_retaken":
			retaken.append(str(e["fort_id"]))
		elif e["type"] == "relish_returned":
			walked[str(e["fort_id"])] = true
	for f in gs.realm.forts:
		var id := str(f["id"])
		var was: Dictionary = b["forts"].get(id, {})
		if RealmSim.is_held(f) and not retaken.has(id) and float(was.get("yield", 1.0)) < 1.0 and gs._yield_mult(f) >= 1.0:
			gains.append(_away_line(str(rep["refilled_fmt"]).format({"fort": str(f["name"])}), "refilled", ""))
			ready.append(_away_line(str(rep["raid_fmt"]).format({"fort": str(f["name"])}), "raid", id))
	# ready: husks waiting while the crypt has room for a big undead; an empty queue, or with the stores full the
	# prompt to raid in its place (W: no build can be planned without relics, so "Queue empty" would contradict
	# it); else (R2) the queue's head still waiting on funds, when its funds come or that they don't
	if not gs.husks.is_empty() and gs.big_undead.size() < gs._cap_of("big_undead"):
		var fmt := str(rep["husk_one_fmt"] if gs.husks.size() == 1 else rep["husks_fmt"])
		ready.append(_away_line(fmt.format({"n": _fmt_count(rep, gs.husks.size())}), "slab", "slab"))
	# E4 step 4 (the resume rule's income test): the buildings still unpaid because the gold income can't pay them,
	# in lot order, on one line, so the player sees why they're off and that a Market fixes it
	var held: Array = []
	for lot_id in gs.town_sim.buildings:
		if gs.town_sim.held_by_income(str(lot_id)):
			var hb: Dictionary = gs.town_sim.buildings[lot_id]
			held.append(_building_name(gs, rep, str(hb["building_id"]), int(hb["level"])))
	if not held.is_empty():
		ready.append(_away_line(str(rep["unpaid_upkeep_fmt"]).format({"names": str(rep["list_sep"]).join(PackedStringArray(held)),
			"rate": _fmt_rate(rep, gs.town_sim.gold_income())}), "queue", "queue"))
	if gs.build_queue.is_empty():
		if stores_full(gs, float(rep["full_tol"])):
			ready.append(_away_line(str(rep["full_raid"]), "raid", ""))
		else:
			ready.append(_away_line(str(rep["queue_empty"]), "queue", "queue"))
	else:
		# the queue's lines, in queue order: the head still waiting on funds (R2), and W2's relics wall, the first
		# entry skipped on `no_relics` when no entry can start. "No entry can start" is read off the walk's statuses:
		# no row is `next` and no `waiting_funds` head will be afforded (affordable_in_s >= 0). An entry `queued`
		# behind a head at −1.0 can't start either (the queue never jumps), so it doesn't clear the wall. A head at −1.0 on gold or bone
		# ahead of (or behind) a relic-gated entry shows both lines: each names a different build.
		var w := BuildRules.queue_walk(gs, gs.build_queue)
		var rows: Array = w["rows"]
		var stuck := true
		var wall := -1
		var upk := -1  # E4 step 4: the first entry the upkeep gate holds (BuildRules.upkeep_short), its own line
		for i in rows.size():
			var row: Dictionary = rows[i]
			match str(row["status"]):
				"skipped_gate":
					if wall < 0 and str(row["reason"]) == "no_relics":
						wall = i
					if upk < 0 and str(row["reason"]) == "upkeep":
						upk = i
				"waiting_funds":
					if float(row["affordable_in_s"]) >= 0.0:
						stuck = false
				"next":
					stuck = false
				# "queued" changes nothing: it sits behind a head (the queue never jumps), so it starts only if
				# that head does, and a head that will be afforded has already cleared `stuck`
		for i in rows.size():
			var row: Dictionary = rows[i]
			if row["status"] == "waiting_funds":
				ready.append(_away_line(afford_text(gs, rep, row, str(w["waits"][i]), BuildRules.queue_net(gs), _move_down_helps(gs, i)), "queue", "queue"))
			elif i == wall and stuck:
				ready.append(_away_line(afford_text(gs, rep, row, "relics", {}, false), "queue", "queue"))
			elif i == upk:
				ready.append(_away_line(str(rep["afford_upkeep_fmt"]).format({
					"name": _building_name(gs, rep, str(row["building_id"]), int(row["level"])),
					"rate": _fmt_rate(rep, gs.town_sim.gold_income())}), "queue", "queue"))
	# E4 step 7 (the brief's "stores full: queue more, or raid for relics"): each store that filled up is a ready action,
	# not a loss: what came in over its cap, and what would use it (a queued build, or the relics a gated one needs).
	# Kind overflow as before; its target is now the queue
	var o := _overflow(gs)
	for k in ["gold", "bone"]:
		var lost := float(o[k]) - float(b["overflow"][k])
		if lost >= float(rep["overflow_min"]):
			ready.append(_away_line(str(rep["overflow_fmt"]).format({"store": str(rep["store_labels"][k]), "n": _fmt_count(rep, lost)}), "overflow", "queue"))
	# losses: each fort retaken (Relish's walk home with it), each village lost, each building unpaid or idled
	for id in retaken:
		var f := gs.realm.fort_by_id(id)
		var fmt := str(rep["retaken_home_fmt"] if walked.has(id) else rep["retaken_fmt"])
		losses.append(_away_line(fmt.format({"fort": str(f.get("name", id))}), "retaken", id))
	for tw in gs.towns:
		if str(b["villages"].get(str(tw["id"]), "")) == "green" and str(tw["control"]) == "orange":
			losses.append(_away_line(str(rep["village_lost_fmt"]).format({"village": str(tw["name"])}), "village_lost", ""))
	losses.append_array(_unpaid_lines(gs, rep, b, evs))
	losses.append_array(_thrift_lines(gs, rep, b, gs._catchup.thrift_log))
	return {"shown": true, "away_s": away_s, "capped": capped, "gains": gains, "ready": ready, "losses": losses}


static func _away_line(text: String, kind: String, target: String) -> Dictionary:
	return {"text": text, "kind": kind, "target": target}


## R2 (the run's manager, from Shawn's "needs relics: raid a fort"; IDLE §7): every capped store, gold and bone, is
## full: each within `tol` (idle.report.full_tol, a fraction of its cap) of its cap, or above it.
static func stores_full(gs: GameState, tol: float) -> bool:
	var ts := gs.town_sim
	return ts.gold >= ts.gold_cap() * (1.0 - tol) and ts.bone >= ts.bone_cap() * (1.0 - tol)


## F2 (the phase review; IDLE §7): whether moving the queue's entry `i` (the stuck head) down would let another
## entry start in its place: the walk of the queue less that entry (a copy; the queue is not touched) has a row
## that isn't `skipped_gate` (a gated entry passes the head anyway) and whose affordable_in_s is ≥ 0.0 (affordable
## now, or later at the current income). The walk with the entry in can't answer this: its later rows are timed as if
## the head started at its time (or, at −1.0, starved its store), so they say nothing about the head not being ahead.
static func _move_down_helps(gs: GameState, i: int) -> bool:
	var rest: Array = gs.build_queue.duplicate()
	rest.remove_at(i)
	for row in BuildRules.queue_walk(gs, rest, true)["rows"]:
		if row["status"] != "skipped_gate" and float(row["affordable_in_s"]) >= 0.0:
			return true
	return false


## R2 (the E2b-2 vision review's item 3; IDLE §7): the away report's line for the queue's head still waiting on
## funds, from its view row (affordable_in_s, building_id, level), the store that sets its time (queue_walk's
## `waits`; the row's no_gold / no_bone when it names none), the net rates (BuildRules.queue_net) and whether moving it
## down would let another entry start in its place (`movable`; _move_down_helps, F2). A positive time: afford_wait_fmt, "Inn is waiting on gold: affordable in
## 6 m", rounded up to the minute so a wait under one never reads "0 m". −1.0: that store's net rate (a rate
## token) and what raises it, afford_raise's words, "House can't be afforded at the current income of 0/s bone:
## move it down, or build a Bone Mill" (afford_never_fmt), without the move down when it can't help: nothing
## behind it could start in its place (afford_never_last_fmt). F1 (the run's manager): when the entry is its store's own producer
## (idle.report.afford_producer, matched on the building, so an upgrade counts) the raise never names it:
## afford_raise_self's fact instead, "Bone Mill level 2 can't be afforded at the current income of 0/s bone, and
## nothing else makes bone: move it down" (afford_never_self_fmt; afford_never_self_last_fmt when moving down can't
## help). W (the run's manager, Shawn's words): short of relics, which have no idle income, no rate and no raise:
## "Crypt level 2 needs relics: raid a fort" (afford_relics_last_fmt, never with a move down: W2, a gated entry
## holds nothing). The away report's walk gates a relic shortfall (no_relics) before any head waits on funds, so no
## head reaches this form; W2's relics wall (away_report) calls it for the first `no_relics` entry.
static func afford_text(gs: GameState, rep: Dictionary, row: Dictionary, store: String, net: Dictionary, movable: bool) -> String:
	var s := store if store != "" else ("bone" if str(row.get("reason", "")) == "no_bone" else "gold")
	var name := _building_name(gs, rep, str(row["building_id"]), int(row["level"]))
	var a := float(row["affordable_in_s"])
	if a < 0.0:
		if s == "relics":
			return str(rep["afford_relics_last_fmt"]).format({"name": name})
		var own := str(row["building_id"]) == str((rep["afford_producer"] as Dictionary).get(s, ""))
		var fmt := ("afford_never_self" if own else "afford_never") + ("_fmt" if movable else "_last_fmt")
		return str(rep[fmt]).format({"name": name, "store": str(rep["afford_stores"][s]),
			"rate": _fmt_rate(rep, float(net.get(s, 0.0))), "raise": str(rep["afford_raise_self" if own else "afford_raise"][s])})
	return str(rep["afford_wait_fmt"]).format({"name": name, "store": str(rep["afford_stores"][s]),
		"when": _when(rep, ceilf(a / 60.0) * 60.0)})


## R1 (the run's manager; IDLE §7): the losses' unpaid lines, one per building unpaid at some time during the
## absence, in lot order: idle.report.unpaid_fmt, "Statue of Relish stopped for 1 h 12 m, gold ran out: lifted no
## morale, deaths shook the town harder" (kind `unpaid`, target its lot). Its time is the sum of its spells from the
## `building_unpaid` events in `evs` (unpaid true, then false); a building unpaid when you left (`b.unpaid`, or a
## resume with no spell open) counts from the start, one still unpaid at the end to the end. What it stopped is
## one unpaid_stopped phrase per GameState.unpaid_keys (its jobs, then its working effects), each phrase once,
## joined by unpaid_sep. F2: an effect nothing reads yet (idle.report.unpaid_inert) stopped nothing, so it has no
## phrase. W (the run's manager): the store that ran out is each store its buildings.json upkeep is above 0 in
## (BuildRules.upkeep_of: the same at every level; gold for every building today), afford_stores' words joined by
## list_sep; under a minute in all, where when_m_fmt would read "0 m", it stopped "briefly" (unpaid_brief_fmt); one
## that stopped nothing has no tail (unpaid_none_fmt, unpaid_none_brief_fmt): "Watchtower stopped for 59 m, gold ran out".
static func _unpaid_lines(gs: GameState, rep: Dictionary, b: Dictionary, evs: Array) -> Array:
	var t0 := float(b["t"])
	var spells := {}  # lot_id -> [seconds unpaid so far, the open spell's start or −1]
	for lot_id in b.get("unpaid", []):
		spells[str(lot_id)] = [0.0, t0]
	var bids := {}  # lot_id -> the building id its events named
	for e in evs:
		if e["type"] != "building_unpaid":
			continue
		var lot := str(e["lot_id"])
		bids[lot] = str(e["building_id"])
		var sp: Array = spells.get(lot, [0.0, -1.0])
		if bool(e["unpaid"]):
			if float(sp[1]) < 0.0:
				sp[1] = float(e["t"])
		else:
			sp[0] = float(sp[0]) + float(e["t"]) - (float(sp[1]) if float(sp[1]) >= 0.0 else t0)
			sp[1] = -1.0
		spells[lot] = sp
	var out: Array = []
	var stopped_words: Dictionary = rep["unpaid_stopped"]
	var cfg := BuildRules.buildings_cfg(gs)
	for l in BuildRules.lots_cfg(gs):
		var lot_id := str(l.get("id", ""))
		if not spells.has(lot_id):
			continue
		var sp: Array = spells[lot_id]
		var secs := float(sp[0]) + (gs.t - float(sp[1]) if float(sp[1]) >= 0.0 else 0.0)
		var bl: Dictionary = gs.town_sim.buildings.get(lot_id, {})
		var bid := str(bl.get("building_id", bids.get(lot_id, "")))
		var phrases: Array = []
		for key in GameState.unpaid_keys(cfg.get(bid, {}), rep["unpaid_inert"]):
			if not stopped_words.has(key):
				push_warning("StateViews: economy.json idle.report.unpaid_stopped has no words for %s" % key)
				continue
			var w := str(stopped_words[key])
			if not phrases.has(w):
				phrases.append(w)
		var paid: Array = []
		var up := BuildRules.upkeep_of(gs, bid)
		for k in up:
			if float(up[k]) > 0.0:
				paid.append(str(rep["afford_stores"][k]))
		var fmt := "unpaid" + ("_none" if phrases.is_empty() else "") + ("_brief" if secs < 60.0 else "") + "_fmt"
		out.append(_away_line(str(rep[fmt]).format({"name": _building_name(gs, rep, bid, maxi(1, int(bl.get("level", 1)))),
			"when": _when(rep, secs), "store": str(rep["list_sep"]).join(PackedStringArray(paid)),
			"stopped": str(rep["unpaid_sep"]).join(PackedStringArray(phrases))}), "unpaid", lot_id))
	return out


## E3-1 (the run's manager's ruling; IDLE §7): the losses' Thrift lines, one per building the Thrift stance idled at
## some time during the absence, in lot order, after the unpaid lines: idle.report.thrift_fmt, "Statue of Relish idled
## by Thrift for 2 h 10 m: lifted no morale, deaths shook the town harder", naming Thrift, not the gold. Kind `unpaid` with
## the building's lot as its target, as R1's lines have it (no new kind or target). Its time is the sum of its spells
## from `idles` (Catchup.thrift_log: [t, lot_id, idled], in order); one idled when you left (`b.thrift`) counts from the
## start, one still idled at the end to the end. What it stopped is the unpaid line's phrases (GameState.unpaid_keys),
## and under a minute it was idled "briefly" (thrift_brief_fmt); one that stopped nothing has no tail
## (thrift_none_fmt, thrift_none_brief_fmt).
static func _thrift_lines(gs: GameState, rep: Dictionary, b: Dictionary, idles: Array) -> Array:
	var spells := {}  # lot_id -> [seconds idled so far, the open spell's start or −1]
	for lot_id in b.get("thrift", []):
		spells[str(lot_id)] = [0.0, float(b["t"])]
	for e in idles:
		var lot := str(e[1])
		var sp: Array = spells.get(lot, [0.0, -1.0])
		if bool(e[2]):
			if float(sp[1]) < 0.0:
				sp[1] = float(e[0])
		elif float(sp[1]) >= 0.0:
			sp[0] = float(sp[0]) + float(e[0]) - float(sp[1])
			sp[1] = -1.0
		spells[lot] = sp
	var out: Array = []
	var stopped_words: Dictionary = rep["unpaid_stopped"]
	var cfg := BuildRules.buildings_cfg(gs)
	for l in BuildRules.lots_cfg(gs):
		var lot_id := str(l.get("id", ""))
		if not spells.has(lot_id):
			continue
		var sp: Array = spells[lot_id]
		var secs := float(sp[0]) + (gs.t - float(sp[1]) if float(sp[1]) >= 0.0 else 0.0)
		var bl: Dictionary = gs.town_sim.buildings.get(lot_id, {})
		var bid := str(bl.get("building_id", ""))
		var phrases: Array = []
		for key in GameState.unpaid_keys(cfg.get(bid, {}), rep["unpaid_inert"]):
			var w := str(stopped_words.get(key, key))
			if not phrases.has(w):
				phrases.append(w)
		var fmt := "thrift" + ("_none" if phrases.is_empty() else "") + ("_brief" if secs < 60.0 else "") + "_fmt"
		out.append(_away_line(str(rep[fmt]).format({"name": _building_name(gs, rep, bid, maxi(1, int(bl.get("level", 1)))),
			"when": _when(rep, secs), "stopped": str(rep["unpaid_sep"]).join(PackedStringArray(phrases))}), "unpaid", lot_id))
	return out


## `digits` (an unsigned integer's decimal digits) with the report's thousands separator every three.
static func _commas(rep: Dictionary, digits: String) -> String:
	var sep := str(rep["thousands"])
	var out := ""
	var n := digits.length()
	for i in n:
		if i > 0 and (n - i) % 3 == 0:
			out += sep
		out += digits[i]
	return out


## |x| at `dec` decimals with thousands separators on the integer part (no sign).
static func _fmt_abs(rep: Dictionary, x: float, dec: int) -> String:
	var s := ("%." + str(dec) + "f") % absf(x)
	var parts := s.split(".")
	return _commas(rep, parts[0]) + ("." + parts[1] if parts.size() > 1 else "")


## A count or a store's waste: |x| rounded, with thousands separators, unsigned ("120", "2").
static func _fmt_count(rep: Dictionary, x: float) -> String:
	return _fmt_abs(rep, roundf(x), 0)


## A mass total: rounded, signed with idle.report's plus or minus, "0" when it rounds to 0 ("+69,552").
static func _fmt_signed(rep: Dictionary, x: float) -> String:
	var r := roundf(x)
	if r == 0.0:
		return "0"
	return (str(rep["plus"]) if r > 0.0 else str(rep["minus"])) + _fmt_abs(rep, r, 0)


## A rate: rate_sig_digits significant digits, at most rate_max_decimals decimals, signed, with rate_unit
## ("+2.1/s", "−0.43/s"); "0/s" when it rounds to 0 there.
static func _fmt_rate(rep: Dictionary, x: float) -> String:
	var unit := str(rep["rate_unit"])
	var most := int(rep["rate_max_decimals"])
	var dec := most
	if absf(x) > 0.0:
		dec = clampi(int(rep["rate_sig_digits"]) - 1 - int(floor(log(absf(x)) / log(10.0))), 0, most)
	var body := _fmt_abs(rep, x, dec)
	if float(body.replace(str(rep["thousands"]), "")) == 0.0:
		return "0" + unit
	return (str(rep["plus"]) if x > 0.0 else str(rep["minus"])) + body + unit


## How long after you left: when_hm_fmt ("3 h 12 m"), or when_m_fmt under an hour ("12 m").
static func _when(rep: Dictionary, s: float) -> String:
	var secs := maxf(0.0, s)
	var h := int(secs / 3600.0)
	var m := int(fmod(secs, 3600.0) / 60.0)
	return str(rep["when_hm_fmt"] if h > 0 else rep["when_m_fmt"]).format({"h": h, "m": m})


## The reason a queued build waited, as idle.report.waited_on words it (one per waited_on value; STATE-API §6
## queue_started). A value it doesn't word is reported (push_warning) and shown as itself.
static func _why_started(rep: Dictionary, w: String) -> String:
	var words: Dictionary = rep["waited_on"]
	if words.has(w):
		return str(words[w])
	push_warning("StateViews: economy.json idle.report.waited_on has no words for %s" % w)
	return w


## A building as the report names it: its label in buildings_view.json (town's, the name the town shows),
## or its id capitalised when it has none; with level_fmt past level 1 ("Market level 2").
static func _building_name(gs: GameState, rep: Dictionary, bid: String, level: int) -> String:
	var view: Variant = gs._cfgs.get("buildings_view", {})
	var row: Variant = (view as Dictionary).get(bid, {}) if view is Dictionary else {}
	var name := str((row as Dictionary).get("label", bid.capitalize())) if row is Dictionary else bid.capitalize()
	return str(rep["level_fmt"]).format({"name": name, "level": level}) if level > 1 else name
