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
## the work is in. A `unique` building (the Crypt) is refused while one stands (api_version 3). `bump`
## false: the build queue's start inside a substep, whose own rev bump covers it.
static func build(gs: GameState, building_id: String, lot_id: String, bump := true) -> Dictionary:
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
	if bump:
		gs.rev += 1
	return {"ok": true, "reason": "", "cost": cost}


## §4.3 · E2: pays level_costs and constructs the next level. The building works at its old level
## meanwhile (TownSim). Reasons in order: unknown_lot, empty_lot, under_construction, unpaid,
## max_level, needs_tier, no_gold, no_bone, no_relics. `bump` as build()'s.
static func upgrade(gs: GameState, lot_id: String, bump := true) -> Dictionary:
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
	if bump:
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
			"work": gs.town_sim.construction_work(str(bid), 1),  # v6 (T3.2, api-request #17): a new build's work
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


# ---------------------------------------------------------------- the build queue ----
## The build queue (IDLE §5, STATE-API §4.3, api-request #3; MECHANICS §4.4). GameState keeps the
## entries, {building_id, lot_id, upgrade, waited_on}, in order (`gs.build_queue`); everything else an
## entry shows is derived from today's state by queue_walk(), which the view, cmd_queue_build and the
## core step's processing all run, so a status always says what the next processing does.

## economy.json queue.max_len (GameState.REQUIRED: a missing key is an error, never a silent 0 that would
## make every cmd_queue_build queue_full).
static func queue_max(gs: GameState) -> int:
	return int(gs._req_f("economy.queue.max_len"))


## The building whose effects raise `store`'s cap (gold_cap, bone_cap, relic_cap), the first in
## buildings.json file order; "" when none does.
static func cap_building(gs: GameState, store: String) -> String:
	var key: String = {"gold": "gold_cap", "bone": "bone_cap", "relics": "relic_cap"}.get(store, "")
	var cfg := buildings_cfg(gs)
	for bid in cfg:
		var fx: Variant = cfg[bid].get("effects", {})
		if fx is Dictionary and (fx as Dictionary).has(key):
			return str(bid)
	return ""


## The lowest level of `store`'s cap building (cap_building) at which the store's cap covers `price`: the
## cap now with that building's highest-level copy raised to that level, or with one built at it when none
## stands (so 1 when it isn't built yet and its level 1 is enough). −1 when no level covers it, or no
## building raises that cap. cmd_queue_build's `cap_level` (STATE-API §4.3): what to build first.
static func cap_level(gs: GameState, store: String, price: float) -> int:
	var bid := cap_building(gs, store)
	if bid == "":
		return -1
	var key: String = {"gold": "gold_cap", "bone": "bone_cap", "relics": "relic_cap"}[store]
	var now := gs.town_sim.gold_cap() if store == "gold" else (gs.town_sim.bone_cap() if store == "bone" else float(gs._cap_of("relics")))
	var have := 0
	for lot_id in gs.town_sim.buildings:
		var b: Dictionary = gs.town_sim.buildings[lot_id]
		if b["building_id"] == bid:
			have = maxi(have, int(b["level"]))
	var base := now - gs.town_sim.effect_at(bid, key, have)
	for lv in range(have + 1, int(buildings_cfg(gs).get(bid, {}).get("max_level", 1)) + 1):
		if base + gs.town_sim.effect_at(bid, key, lv) >= price:
			return lv
	return -1


## The store whose current cap `cost` is above (gold, bone, then relics), or "".
static func over_cap(gs: GameState, cost: Dictionary) -> String:
	if float(cost["gold"]) > gs.town_sim.gold_cap():
		return "gold"
	if float(cost["bone"]) > gs.town_sim.bone_cap():
		return "bone"
	if int(cost["relics"]) > gs._cap_of("relics"):
		return "relics"
	return ""


## The building an upgrade queued on `lot_id` would upgrade: the one there (built or under
## construction), else the first new build queued for the lot; "" when neither.
static func queued_building(gs: GameState, lot_id: String, entries: Array) -> String:
	var b: Dictionary = gs.town_sim.buildings.get(lot_id, {})
	if not b.is_empty():
		return str(b["building_id"])
	for e in entries:
		if e["lot_id"] == lot_id and not bool(e["upgrade"]):
			return str(e["building_id"])
	return ""


## The level each entry builds (MECHANICS §4.4): a new build 1; an upgrade one above what its lot will
## have once every entry ahead of it for that lot, and the construction under way there, are done. The
## lot's level starts at its building's (its construction's target while constructing) and only entries
## of that building move it; the first new build queued for an empty lot sets it at 1.
static func queue_levels(gs: GameState, entries: Array) -> Array:
	var proj := {}  # lot_id -> [building_id, level]
	for lot_id in gs.town_sim.buildings:
		var b: Dictionary = gs.town_sim.buildings[lot_id]
		proj[lot_id] = [str(b["building_id"]), int(b["build_level"]) if b["state"] == "constructing" else int(b["level"])]
	var out: Array = []
	for e in entries:
		var lot_id: String = e["lot_id"]
		var bid: String = e["building_id"]
		var p: Array = proj.get(lot_id, [])
		if not bool(e["upgrade"]):
			out.append(1)
			if p.is_empty():
				proj[lot_id] = [bid, 1]
		elif not p.is_empty() and p[0] == bid:
			p[1] = int(p[1]) + 1
			out.append(int(p[1]))
		else:
			out.append(2)  # nothing of its building there or queued: it shows empty_lot
	return out


## One walk of the queue (MECHANICS §4.4) on a copy of today's stocks and lots, the one rule the view,
## cmd_queue_build and the core step's processing share. In order: an entry blocked by a gate is
## `skipped_gate` with its reason and the walk goes on (it holds nothing: no funds, no lot); the first
## entry that isn't gated is the head: `next` when the gold and bone cover it, and the copy pays and takes
## its lot as the start would, so the walk goes on to the next head; else `waiting_funds` (no_gold,
## no_bone) and every later entry that isn't gated is `queued`. An upgrade behind an entry for its lot that
## hasn't started shows that entry's gate (none: queued).
## R2 (the E2b-2 vision review; the run's manager): the same walk times each entry's funds, its
## `affordable_in_s` (_afford_at): the entries that aren't gated start in queue order, each when the stocks,
## grown at queue_net's rates held fixed (each up to its cap) and less what the entries ahead paid at their own
## starts, cover it; a gated entry gets its own time there and pays nothing. An entry that never starts (−1.0)
## pays nothing either, and its store is `starved`: a later entry that costs any of it is −1.0 too, one that
## doesn't is timed as if it weren't there. Up to the head the timeline's stocks are the walk's copy, so `next`
## reads 0.0 and `waiting_funds` never does. Returns {rows: the view's entries, start: the indices that start,
## in order, waits: per entry the store that sets its time ("gold", "bone", "relics"; "" when its stocks cover
## it at the clock: 0.0, or the start of the entry ahead)}. `timed` false (the core step's processing, which reads
## only the statuses, every step and every catch-up step) skips the times: no affordable_in_s, waits [].
static func queue_walk(gs: GameState, entries: Array, timed := true) -> Dictionary:
	var levels := queue_levels(gs, entries)
	var gold := gs.town_sim.gold
	var bone := gs.town_sim.bone
	var relics := gs.relics
	var lots := {}  # lot_id -> {building_id, level, state}: the copy the walk takes lots in
	for lot_id in gs.town_sim.buildings:
		var b: Dictionary = gs.town_sim.buildings[lot_id]
		lots[lot_id] = {"building_id": str(b["building_id"]), "level": int(b["level"]), "state": str(b["state"])}
	var pending := {}  # lot_id -> the gate of the last entry for it that hasn't started ("" when not gated)
	var stopped := false
	var rows: Array = []
	var start: Array = []
	# R2: the funds' timeline: `fund` the stocks at `clock` (the last timed start) after what the entries
	# started by then paid; `starved` the stores an entry that never starts waits on
	var tl := {"clock": 0.0, "fund": {"gold": gold, "bone": bone, "relics": float(relics)}, "net": queue_net(gs),
		"cap": {"gold": gs.town_sim.gold_cap(), "bone": gs.town_sim.bone_cap(), "relics": float(gs._cap_of("relics"))}, "starved": {}} if timed else {}
	var waits: Array = []
	for i in entries.size():
		var e: Dictionary = entries[i]
		var lot_id: String = e["lot_id"]
		var bid: String = e["building_id"]
		var up := bool(e["upgrade"])
		var level: int = levels[i]
		var cost := construction_cost(gs, bid, level)
		var why := _queue_gate(gs, e, level, cost, lots, pending, relics)
		var status := "skipped_gate"
		if why == "":
			if stopped or (up and pending.has(lot_id)):
				status = "queued"
			elif gold < float(cost["gold"]):
				status = "waiting_funds"
				why = "no_gold"
			elif bone < float(cost["bone"]):
				status = "waiting_funds"
				why = "no_bone"
			else:
				status = "next"
		if status == "next":
			gold -= float(cost["gold"])
			bone -= float(cost["bone"])
			relics -= int(cost["relics"])
			if up:
				lots[lot_id]["state"] = "constructing"
			else:
				lots[lot_id] = {"building_id": bid, "level": 0, "state": "constructing"}
				pending.erase(lot_id)
			start.append(i)
		else:
			pending[lot_id] = why if status == "skipped_gate" else ""
			stopped = stopped or status == "waiting_funds"
		var row := {"building_id": bid, "lot_id": lot_id, "upgrade": up, "level": level, "cost": cost,
			"work": gs.town_sim.construction_work(bid, level),
			"status": status, "reason": why, "waited_on": str(e.get("waited_on", ""))}
		if timed:
			var at := _afford_at(gs, cost, tl, status != "skipped_gate")
			waits.append(at[1])
			row["affordable_in_s"] = float(at[0])
		rows.append(row)
	return {"rows": rows, "start": start, "waits": waits}


## R2: the net rates the queue's times hold fixed (STATE-API §5.9, MECHANICS §4.4): each capped store's income
## in TownSim's last step before its cap's clip, less the upkeep it paid (gold `trade` − `out`, bone `mill` −
## `out`; a save older than those keys reads `in` + `overflow`). Below the cap that is view_rates' and the HUD's
## net exactly; at the cap their `in` is clipped down to the upkeep, so they read 0 while this keeps the income
## that comes back once an entry ahead spends the store under its cap. Relics have no idle income: 0.
static func queue_net(gs: GameState) -> Dictionary:
	var r: Dictionary = gs.town_sim.rates
	var out := {"relics": 0.0}
	for k in [["gold", "trade"], ["bone", "mill"]]:
		var s: Dictionary = r[k[0]]
		out[k[0]] = float(s.get(k[1], float(s["in"]) + float(s.get("overflow", 0.0)))) - float(s["out"])
	return out


## R2: an entry's funds time on the walk's timeline `tl` (queue_walk), as [affordable_in_s, the store it waits
## on]: 0.0 when the stocks at the clock cover its gold, bone and relics; else the clock plus the longest of
## (cost − stock) / net over the short stores, every store grown at its net up to its cap meanwhile; −1.0 (and
## the store) when a cost is above its store's cap (over_cap), a relic cost is short (no idle income), it costs
## a starved store, a short store's net is ≤ 0, or a store that covers it now falls under it by then at a
## negative net. One that `holds` (isn't gated) starts at its time: the clock moves there and the stocks pay its
## cost; one that never does starves its store. A gated one changes nothing.
static func _afford_at(gs: GameState, cost: Dictionary, tl: Dictionary, holds: bool) -> Array:
	var fund: Dictionary = tl["fund"]
	var net: Dictionary = tl["net"]
	var never := ""
	for s in ["gold", "bone", "relics"]:  # over_cap's check and order, on the caps the walk read once
		if never == "" and float(cost[s]) > float(tl["cap"][s]):
			never = s
	if never == "" and float(cost["relics"]) > float(fund["relics"]):
		never = "relics"
	for s in tl["starved"]:
		if never == "" and float(cost[s]) > 0.0:
			never = str(s)
	var dt := 0.0
	var wait := ""
	for s in ["gold", "bone"]:
		var short := float(cost[s]) - float(fund[s])
		if never != "" or short <= 0.0:
			continue
		if float(net[s]) <= 0.0:
			never = s
		elif short / float(net[s]) > dt:
			dt = short / float(net[s])
			wait = s
	for s in ["gold", "bone"]:
		if never == "" and float(net[s]) < 0.0 and float(fund[s]) + float(net[s]) * dt < float(cost[s]):
			never = s
	if never != "":
		if holds:
			tl["starved"][never] = true
		return [-1.0, never]
	var at := float(tl["clock"]) + dt
	if holds:
		for s in ["gold", "bone"]:
			var grown := float(fund[s]) + float(net[s]) * dt
			if float(net[s]) > 0.0 and grown > float(tl["cap"][s]):
				grown = maxf(float(tl["cap"][s]), float(fund[s]))  # a full store wastes what comes in; one above its cap keeps its excess
			fund[s] = maxf(0.0, grown - float(cost[s]))  # (an ulp under 0 after a timed wait would starve a store that costs nothing)
		fund["relics"] = float(fund["relics"]) - float(cost["relics"])
		tl["clock"] = at
	return [at, wait]


## An entry's gate on the walk's copy (`lots`, `pending`, the relics left), in the build family's check
## order, or "". An upgrade: empty_lot (another building there, or nothing there or queued for it),
## max_level, then an earlier entry's gate for that lot while one hasn't started, else under_construction,
## unpaid, needs_tier. A new build: unique, lot_locked, lot_taken (a building stands or is under
## construction there), lot_too_small, needs_tier, needs_blueprint, needs_building. Then both:
## cost_exceeds_cap (a cost over its store's cap now, after a cap building went), no_relics.
static func _queue_gate(gs: GameState, e: Dictionary, level: int, cost: Dictionary, lots: Dictionary, pending: Dictionary,
		relics: int) -> String:
	var lot_id: String = e["lot_id"]
	var bid: String = e["building_id"]
	var def: Dictionary = buildings_cfg(gs).get(bid, {})
	var why := ""
	if bool(e["upgrade"]):
		var b: Dictionary = lots.get(lot_id, {})
		if (not b.is_empty() and b["building_id"] != bid) or (b.is_empty() and not pending.has(lot_id)):
			why = "empty_lot"
		elif level > int(def.get("max_level", 1)):
			why = "max_level"
		elif pending.has(lot_id):
			why = str(pending[lot_id])
		elif b["state"] == "constructing":
			why = "under_construction"
		elif b["state"] == "unpaid":
			why = "unpaid"
		else:
			why = req_reason(gs, {"tier": req_of(gs, bid)["tier"], "blueprint": "", "building": ""})
	else:
		var unique := bool(def.get("unique", false))
		var taken := false
		for l in lots:
			taken = taken or (unique and lots[l]["building_id"] == bid)
		if taken:
			why = "unique"
		elif not lot_unlocked(gs, lot_id):
			why = "lot_locked"
		elif lots.has(lot_id):
			why = "lot_taken"
		elif int(lot(gs, lot_id).get("size", 1)) < int(def.get("lot_size", 1)):
			why = "lot_too_small"
		else:
			why = req_reason(gs, req_of(gs, bid))
	if why == "" and over_cap(gs, cost) != "":
		why = "cost_exceeds_cap"
	if why == "" and relics < int(cost["relics"]):
		why = "no_relics"
	return why


## The core step's processing (§3 step 3, right after rise_tiers): one walk, then each `next` entry starts
## through cmd_build's or cmd_upgrade's own path, in order, and leaves the queue with `queue_started
## {building_id, lot_id, level, upgrade, waited_on}`. Every entry that stays and was skipped or waited on
## funds keeps that reason as its waited_on, and one queued behind the head that waits on funds takes the
## head's (no_gold, no_bone): the funds hold it now. A start its command refuses (it never should: the walk
## checks what they check) keeps its entry and stops this step's starts.
static func process_queue(gs: GameState) -> void:
	if gs.build_queue.is_empty():
		return
	var w := queue_walk(gs, gs.build_queue, false)  # the statuses only: the times are the views'
	var gone := {}
	for i in w["start"]:
		var e: Dictionary = gs.build_queue[i]
		var row: Dictionary = w["rows"][i]
		var r := upgrade(gs, e["lot_id"], false) if bool(e["upgrade"]) else build(gs, e["building_id"], e["lot_id"], false)
		if not r["ok"]:
			push_warning("BuildRules: the queue's %s on %s was refused (%s)" % [e["building_id"], e["lot_id"], r["reason"]])
			e["waited_on"] = str(r["reason"])
			break
		gone[i] = true
		gs._emit({"type": "queue_started", "building_id": str(e["building_id"]), "lot_id": str(e["lot_id"]),
			"level": int(row["level"]), "upgrade": bool(e["upgrade"]), "waited_on": str(e.get("waited_on", ""))})
	var keep: Array = []
	var held := ""  # the reason of the head waiting on funds, once the walk has reached it
	for i in gs.build_queue.size():
		var st: String = w["rows"][i]["status"]
		if st == "waiting_funds" and held == "":
			held = str(w["rows"][i]["reason"])
		if gone.has(i):
			continue
		var e: Dictionary = gs.build_queue[i]
		if st == "skipped_gate" or st == "waiting_funds":
			e["waited_on"] = str(w["rows"][i]["reason"])
		elif st == "queued" and held != "":
			e["waited_on"] = held  # the head's funds hold it now, whatever gate held it before
		keep.append(e)
	gs.build_queue = keep


## §4.3 cmd_queue_build: appends a build (or, with building_id "", an upgrade of the building on or queued
## for `lot_id`). Refuses only what waiting can't make valid, in order: queue_full, unknown_building,
## unknown_lot, unique (one stands, is under construction or is queued), lot_taken (one stands or is under
## construction there; queued entries don't claim lots), lot_too_small; an upgrade's empty_lot (nothing
## there or queued) and max_level (the level it would build); cost_exceeds_cap (a gold, bone or relic cost
## over that store's cap now; `store` names it and `cap_building` the building that raises it). Gates
## time or play can clear (the tier, a blueprint, a building, a locked lot, relics, a construction under
## way, an unpaid spell) are accepted and show as skipped_gate. Affordability never refuses. R2: the new
## entry's affordable_in_s, its row's from the walk (−1.0 on a refusal: no entry), warns at queue time.
static func queue_build(gs: GameState, building_id: String, lot_id: String) -> Dictionary:
	var out := {"ok": false, "reason": "", "index": -1, "cap_building": "", "store": "", "cap_level": -1, "affordable_in_s": -1.0}
	var q: Array = gs.build_queue
	var up := building_id == ""
	var bid := building_id
	var def: Dictionary = buildings_cfg(gs).get(bid, {})
	var why := ""
	if q.size() >= queue_max(gs):
		why = "queue_full"
	elif not up and def.is_empty():
		why = "unknown_building"
	elif lot(gs, lot_id).is_empty():
		why = "unknown_lot"
	elif up:
		bid = queued_building(gs, lot_id, q)
		def = buildings_cfg(gs).get(bid, {})
		if bid == "":
			why = "empty_lot"
	elif bool(def.get("unique", false)) and (unique_taken(gs, bid) or q.any(func(e): return e["building_id"] == bid and not bool(e["upgrade"]))):
		why = "unique"
	elif gs.town_sim.buildings.has(lot_id):
		why = "lot_taken"
	elif int(lot(gs, lot_id).get("size", 1)) < int(def.get("lot_size", 1)):
		why = "lot_too_small"
	var entry := {"building_id": bid, "lot_id": lot_id, "upgrade": up, "waited_on": ""}
	if why == "":
		var level: int = queue_levels(gs, q + [entry]).back()
		if up and level > int(def.get("max_level", 1)):
			why = "max_level"
		else:
			var cost := construction_cost(gs, bid, level)
			var store := over_cap(gs, cost)
			if store != "":
				why = "cost_exceeds_cap"
				out["cap_building"] = cap_building(gs, store)
				out["store"] = store
				out["cap_level"] = cap_level(gs, store, float(cost[store]))
	if why != "":
		out["reason"] = why
		return out
	q.append(entry)
	var row: Dictionary = queue_walk(gs, q)["rows"].back()
	if row["status"] == "skipped_gate" or row["status"] == "waiting_funds":
		entry["waited_on"] = str(row["reason"])
	gs.rev += 1
	return {"ok": true, "reason": "", "index": q.size() - 1, "cap_building": "", "store": "", "cap_level": -1,
		"affordable_in_s": float(row["affordable_in_s"])}


## §4.3 cmd_unqueue: removes entry `index` (unknown_index).
static func unqueue(gs: GameState, index: int) -> Dictionary:
	if index < 0 or index >= gs.build_queue.size():
		return {"ok": false, "reason": "unknown_index"}
	gs.build_queue.remove_at(index)
	gs.rev += 1
	return {"ok": true, "reason": ""}


## §4.3 cmd_reorder_queue: `order[k]` is the old index that moves to position k (a whole number; a
## permutation of the current indices, else bad_order).
static func reorder_queue(gs: GameState, order: Array) -> Dictionary:
	var n := gs.build_queue.size()
	var seen := {}
	if order.size() != n:
		return {"ok": false, "reason": "bad_order"}
	for i in order:
		if not (i is int or (i is float and is_finite(i) and float(i) == floorf(i))) or int(i) < 0 or int(i) >= n or seen.has(int(i)):
			return {"ok": false, "reason": "bad_order"}
		seen[int(i)] = true
	var out: Array = []
	for i in order:
		out.append(gs.build_queue[int(i)])
	gs.build_queue = out
	gs.rev += 1
	return {"ok": true, "reason": ""}


## view_town's `queue`: the walk's rows (STATE-API §5.9).
static func queue_rows(gs: GameState) -> Array:
	return queue_walk(gs, gs.build_queue)["rows"]
