class_name BuildRules
extends RefCounted
## The build family's rules (STATE-API 4.3), static only, taking the GameState they act on: the
## building and lot lookups, costs, gates and payment, cmd_build / cmd_upgrade / cmd_demolish /
## cmd_cancel_build's bodies, the town tiers, the caps the buildings give, and the catalog's
## building rows. GameState keeps the commands, with their signatures, and forwards here.


static func buildings_cfg(gs: GameState) -> Dictionary:
	var d: Variant = gs._cfgs.get("buildings", {})
	return d if d is Dictionary else {}


static func lots_cfg(gs: GameState) -> Array:
	var d: Variant = gs._cfgs.get("town", {}).get("lots", [])
	return d if d is Array else []


static func lot(gs: GameState, lot_id: String) -> Dictionary:
	for l in lots_cfg(gs):
		if str(l.get("id", "")) == lot_id:
			return l
	return {}


## The lot ids a tier opens (economy.json town.tiers.<tier>.lot_ids; BALANCE §5). `.lots` is the count.
static func tier_lots(gs: GameState, tier: String) -> Array:
	var d: Variant = gs._sec("economy", "town").get("tiers", {}).get(tier, {}).get("lot_ids", [])
	return d if d is Array else []


static func lot_unlocked(gs: GameState, lot_id: String) -> bool:
	return tier_lots(gs, gs.town_tier).has(lot_id)


## Lots holding a building (built, or a first build under way), in lot order.
static func built_lots(gs: GameState) -> Array:
	var out: Array = []
	for l in lots_cfg(gs):
		var id := str(l.get("id", ""))
		if gs.town_sim.buildings.has(id):
			out.append(id)
	return out


## Buildings of that id that have finished their first build (level ≥ 1); every building when "".
static func count_built(gs: GameState, building_id: String) -> int:
	var n := 0
	for lot_id in gs.town_sim.buildings:
		var b: Dictionary = gs.town_sim.buildings[lot_id]
		if int(b["level"]) >= 1 and (building_id == "" or b["building_id"] == building_id):
			n += 1
	return n


## A `unique` building (buildings.json; the Crypt) that already stands on a lot, finished or under
## construction: a second one is refused (`unique`).
static func unique_taken(gs: GameState, building_id: String) -> bool:
	if not bool(buildings_cfg(gs).get(building_id, {}).get("unique", false)):
		return false
	for lot_id in gs.town_sim.buildings:
		if gs.town_sim.buildings[lot_id]["building_id"] == building_id:
			return true
	return false


## A building's job slots per job id (buildings.json `jobs`).
static func jobs_of(gs: GameState, building_id: String) -> Dictionary:
	var d: Variant = buildings_cfg(gs).get(building_id, {}).get("jobs", {})
	return d if d is Dictionary else {}


static func slots_of(gs: GameState, building_id: String) -> int:
	var jobs := jobs_of(gs, building_id)
	var n := 0
	for j in jobs:
		n += int(jobs[j])
	return n


static func cost_of(gs: GameState, d: Variant) -> Dictionary:
	var c: Dictionary = d if d is Dictionary else {}
	return {"gold": float(c.get("gold", 0.0)), "bone": float(c.get("bone", 0.0)), "relics": int(c.get("relics", 0))}


static func upkeep_of(gs: GameState, building_id: String) -> Dictionary:
	var d: Variant = buildings_cfg(gs).get(building_id, {}).get("upkeep", {})
	var u: Dictionary = d if d is Dictionary else {}
	return {"gold": float(u.get("gold", 0.0)), "bone": float(u.get("bone", 0.0))}


static func zero_cost(gs: GameState) -> Dictionary:
	return {"gold": 0.0, "bone": 0.0, "relics": 0}


## A building's `requires` as {tier, blueprint, building} strings.
static func req_of(gs: GameState, building_id: String) -> Dictionary:
	var r: Variant = buildings_cfg(gs).get(building_id, {}).get("requires", {})
	var d: Dictionary = r if r is Dictionary else {}
	return {"tier": str(d.get("tier", "")), "blueprint": str(d.get("blueprint", "")), "building": str(d.get("building", ""))}


## The tier, blueprint and building gates, in order: needs_tier, needs_blueprint, needs_building.
static func req_reason(gs: GameState, req: Dictionary) -> String:
	if GameState.TIERS.find(req["tier"]) > GameState.TIERS.find(gs.town_tier):
		return "needs_tier"
	if req["blueprint"] != "" and not gs.blueprints.has(req["blueprint"]):
		return "needs_blueprint"
	if req["building"] != "" and count_built(gs, req["building"]) == 0:
		return "needs_building"
	return ""


## no_gold, no_bone, no_relics: gold and bone are TownSim's stocks, as view_town shows them.
static func afford_reason(gs: GameState, cost: Dictionary) -> String:
	if gs.town_sim.gold < cost["gold"]:
		return "no_gold"
	if gs.town_sim.bone < cost["bone"]:
		return "no_bone"
	if gs.relics < cost["relics"]:
		return "no_relics"
	return ""


static func pay(gs: GameState, cost: Dictionary) -> void:
	gs.town_sim.gold -= float(cost["gold"])
	gs.town_sim.bone -= float(cost["bone"])
	gs.relics -= int(cost["relics"])


## What a construction heading to `level` cost: the building's cost for level 1, else the upgrade's
## level_costs[level - 2].
static func construction_cost(gs: GameState, building_id: String, level: int) -> Dictionary:
	var def: Dictionary = buildings_cfg(gs).get(building_id, {})
	if level <= 1:
		return cost_of(gs, def.get("cost", {}))
	var lc: Variant = def.get("level_costs", [])
	var arr: Array = lc if lc is Array else []
	return cost_of(gs, arr[level - 2]) if level - 2 < arr.size() else zero_cost(gs)


## §4.3 · E2: pays the cost at once and starts construction on a free, unlocked lot. TownSim's
## `build` job advances it; `building_started` comes out of the next substep, `building_done` when
## the work is in. A `unique` building (the Crypt) is refused while one stands (api_version 3).
static func build(gs: GameState, building_id: String, lot_id: String) -> Dictionary:
	var def: Dictionary = buildings_cfg(gs).get(building_id, {})
	var lot := lot(gs, lot_id)
	var cost := construction_cost(gs, building_id, 1)
	var why := ""
	if def.is_empty():
		why = "unknown_building"
	elif lot.is_empty():
		why = "unknown_lot"
	elif unique_taken(gs, building_id):
		why = "unique"
	elif not lot_unlocked(gs, lot_id):
		why = "lot_locked"
	elif gs.town_sim.buildings.has(lot_id):
		why = "lot_taken"
	elif int(lot.get("size", 1)) < int(def.get("lot_size", 1)):
		why = "lot_too_small"
	else:
		why = req_reason(gs, req_of(gs, building_id))
		if why == "":
			why = afford_reason(gs, cost)
	if why != "":
		return {"ok": false, "reason": why, "cost": {}}
	var r := gs.town_sim.start_construction(lot_id, building_id, 1)
	if not r["ok"]:
		return {"ok": false, "reason": str(r["reason"]), "cost": {}}  # unreachable: every gate is checked above
	pay(gs, cost)
	gs.rev += 1
	return {"ok": true, "reason": "", "cost": cost}


## §4.3 · E2: pays level_costs and constructs the next level. The building works at its old level
## meanwhile (TownSim). Reasons in order: unknown_lot, empty_lot, under_construction, unpaid,
## max_level, needs_tier, no_gold, no_bone, no_relics.
static func upgrade(gs: GameState, lot_id: String) -> Dictionary:
	var b: Dictionary = gs.town_sim.buildings.get(lot_id, {})
	var why := ""
	var level := 0
	var cost := {}
	if lot(gs, lot_id).is_empty():
		why = "unknown_lot"
	elif b.is_empty():
		why = "empty_lot"
	elif b["state"] == "constructing":
		why = "under_construction"
	elif b["state"] == "unpaid":
		why = "unpaid"
	else:
		var bid: String = b["building_id"]
		level = int(b["level"]) + 1
		if level > int(buildings_cfg(gs).get(bid, {}).get("max_level", 1)):
			why = "max_level"
		else:
			cost = construction_cost(gs, bid, level)
			why = req_reason(gs, {"tier": req_of(gs, bid)["tier"], "blueprint": "", "building": ""})
			if why == "":
				why = afford_reason(gs, cost)
	if why != "":
		return {"ok": false, "reason": why, "level": 0, "cost": {}}
	var r := gs.town_sim.start_construction(lot_id, b["building_id"], level)
	if not r["ok"]:
		return {"ok": false, "reason": str(r["reason"]), "level": 0, "cost": {}}  # unreachable
	pay(gs, cost)
	gs.rev += 1
	return {"ok": true, "reason": "", "level": level, "cost": cost}


## A foreman placed on a lot that is cleared goes back to the crypt.
static func foreman_home(gs: GameState, lot_id: String) -> void:
	for b in gs.big_undead:
		if b["place"] == "town:" + lot_id:
			b["place"] = "crypt"


## §4.3 · E2: removes a finished building, no refund. The Crypt is protected.
static func demolish(gs: GameState, lot_id: String) -> Dictionary:
	var b: Dictionary = gs.town_sim.buildings.get(lot_id, {})
	var why := ""
	if lot(gs, lot_id).is_empty():
		why = "unknown_lot"
	elif b.is_empty():
		why = "empty_lot"
	elif b["state"] == "constructing":
		why = "under_construction"
	elif b["building_id"] == "crypt":
		why = "protected"
	if why != "":
		return {"ok": false, "reason": why}
	gs.town_sim.demolish(lot_id)
	foreman_home(gs, lot_id)
	gs.rev += 1
	return {"ok": true, "reason": ""}


## §4.3 · E2: cancels the construction under way and refunds its cost in full (relics clamped to the
## cap). A cancelled first build frees the lot; a cancelled upgrade keeps the old level.
static func cancel_build(gs: GameState, lot_id: String) -> Dictionary:
	if lot(gs, lot_id).is_empty():
		return {"ok": false, "reason": "unknown_lot", "refund": {}}
	var r := gs.town_sim.cancel_construction(lot_id)
	if not r["ok"]:
		return {"ok": false, "reason": str(r["reason"]), "refund": {}}
	var cost := construction_cost(gs, str(r["building_id"]), int(r["level"]))
	gs.town_sim.gold += float(cost["gold"])
	gs.town_sim.bone += float(cost["bone"])
	var back := mini(int(cost["relics"]), maxi(0, gs._cap_of("relics") - gs.relics))
	gs.relics += back
	if not r["upgrade"]:
		foreman_home(gs, lot_id)
	gs.rev += 1
	return {"ok": true, "reason": "", "refund": {"gold": float(cost["gold"]), "bone": float(cost["bone"]), "relics": back}}


static func next_tier(gs: GameState) -> Dictionary:
	var have := count_built(gs, "")
	var idx := GameState.TIERS.find(gs.town_tier)
	if idx < 0 or idx >= GameState.TIERS.size() - 1:
		return {"tier": "", "have": have, "need": 0, "missing": []}
	var nt: String = GameState.TIERS[idx + 1]
	var spec: Dictionary = gs._sec("economy", "town").get("tiers", {}).get(nt, {})
	var missing: Array = []
	for b in spec.get("requires", []):
		if count_built(gs, str(b)) == 0:
			missing.append(str(b))
	return {"tier": nt, "have": have, "need": int(spec.get("buildings", 0)), "missing": missing}


## The tier a town holds: it rises while the next tier's requirements hold (enough finished
## buildings and every required building id), one `tier_up` per rise. Tiers never fall.
static func rise_tiers(gs: GameState) -> void:
	while true:
		var nt := next_tier(gs)
		if nt["tier"] == "" or int(nt["have"]) < int(nt["need"]) or not (nt["missing"] as Array).is_empty():
			return
		var from := gs.town_tier
		gs.town_tier = str(nt["tier"])
		gs._emit({"type": "tier_up", "tier": gs.town_tier, "from": from})
		gs.rev += 1


## Free unlocked lots that fit a building of `size`, in lot order.
static func free_lots(gs: GameState, size: int) -> Array:
	var out: Array = []
	for l in lots_cfg(gs):
		var id := str(l.get("id", ""))
		if lot_unlocked(gs, id) and not gs.town_sim.buildings.has(id) and int(l.get("size", 1)) >= size:
			out.append(id)
	return out


## view_catalog's reason, in order: the gates of `cmd_build` (unique first, as cmd_build checks it
## before the lot), then no_lot (no free unlocked lot fits), then what it costs.
static func build_gate(gs: GameState, building_id: String, req: Dictionary, cost: Dictionary, lots: Array) -> String:
	if unique_taken(gs, building_id):
		return "unique"
	var why := req_reason(gs, req)
	if why == "" and lots.is_empty():
		why = "no_lot"
	if why == "":
		why = afford_reason(gs, cost)
	return why


## The building rows of view_catalog, buildings.json in file order with live gating, and the
## blueprint ids they require (first seen first).
static func catalog_rows(gs: GameState) -> Dictionary:
	var cfg := buildings_cfg(gs)
	var out: Array = []
	var bps: Array = []
	for bid in cfg:
		var def: Dictionary = cfg[bid]
		var req := req_of(gs, bid)
		var cost := cost_of(gs, def.get("cost", {}))
		var lots := free_lots(gs, int(def.get("lot_size", 1)))
		var why := build_gate(gs, bid, req, cost, lots)
		out.append({
			"building_id": str(bid), "cost": cost, "upkeep": upkeep_of(gs, bid),
			"build_work": float(def.get("build_work", 0.0)), "lot_size": int(def.get("lot_size", 1)),
			"max_level": int(def.get("max_level", 1)), "count": count_built(gs, bid), "requires": req,
			"can_build": why == "", "reason": why, "lots": lots,
		})
		if req["blueprint"] != "" and not bps.has(req["blueprint"]):
			bps.append(req["blueprint"])
	return {"buildings": out, "blueprints": bps}


## What the buildings add to a capped stock's cap (GameState._cap_of adds the economy.json base): the
## Reliquary's `relic_cap` and `essence_cap`; big undead: `per_crypt_level` per Crypt level above 1.
static func cap_bonus(gs: GameState, section: String) -> int:
	var sec := gs._sec("economy", section)
	var n := 0
	match section:
		"relics":
			n += int(gs.town_sim.built_effect("relic_cap"))
		"essence":
			n += int(gs.town_sim.built_effect("essence_cap"))
		"big_undead":
			for lot_id in gs.town_sim.buildings:
				var b: Dictionary = gs.town_sim.buildings[lot_id]
				if b["building_id"] == "crypt":
					n += int(sec.get("per_crypt_level", 0)) * maxi(0, int(b["level"]) - 1)
	return n
