class_name TownStandins
extends RefCounted
## Stand-ins for town data the API does not deliver yet, and the synthetic demo city. Pure: no
## autoloads, no Engine. Every stand-in is marked and switches itself off when the real value
## arrives.

## Demo city layout: one building per lot, each fitting its lot's size. 14 size-1, 8 size-2 and
## 2 size-3 lots hold at most 18 distinct ids (13 ids need size >= 2), so graveyard, stables and
## plaza sit this one out.
const DEMO_PLAN := {
	"lot-01": "crypt", "lot-02": "inn", "lot-03": "charnel_house", "lot-04": "market",
	"lot-05": "raising_pit", "lot-06": "raising_pit", "lot-07": "well", "lot-08": "bakery",
	"lot-09": "house", "lot-10": "house", "lot-11": "watchtower", "lot-12": "house",
	"lot-13": "forge", "lot-14": "guildhall", "lot-15": "chapel_of_vats", "lot-16": "ossuary_tower",
	"lot-17": "watchtower", "lot-18": "bone_mill", "lot-19": "embalmer", "lot-20": "house",
	"lot-21": "statue", "lot-22": "well", "lot-23": "walls", "lot-24": "reliquary",
}
## Lots that are not simply active: [state, progress, level].
const DEMO_STATES := {
	"lot-21": ["constructing", 0.2, 0],
	"lot-16": ["constructing", 0.5, 0],
	"lot-12": ["constructing", 0.85, 0],
	"lot-14": ["unpaid", 1.0, 1],
	"lot-18": ["idle", 1.0, 1],
}
## Output per staffed job building (per second). The pit uses its real `effects` instead.
const DEMO_OUTPUT := {
	"haul": {"bodies": 1.2}, "stall": {"gold": 0.6}, "mill": {"bone": 0.4},
	"forge": {"q": 0.04}, "tend": {"q": 0.02}, "pit": {"mint": 3.0, "burn": 0.6},
}
## STANDIN: the workforce the town keeps (the HUD's "→ steady N"). The view's `workers.steady_kept`
## (or view_hud's `workers_steady_kept`) wins when present; until then the whole workforce while the
## sim is mustering (idle beyond the cap leaves for WAR), else `workers.steady`.
## TODO(api-request #12): drop once the views carry steady_kept (E2b).
static func steady_kept(town: Dictionary, hud: Dictionary) -> float:
	var w: Dictionary = town.get("workers", {})
	if w.has("steady_kept"):
		return float(w["steady_kept"])
	if hud.has("workers_steady_kept"):
		return float(hud["workers_steady_kept"])
	return float(w.get("total", 0.0)) if float(w.get("muster", 0.0)) > 0.0 else float(w.get("steady", 0.0))


# RETIRED (town-i M2): the staffing a job order would give, display-only, from before GameState had
# `view_staffing_projection(order)`. The shell (covington.project_staffing) calls the real view now; this and
# `project` stay only as the tests' model of the vat preview's shape. Today's assigned hands
# (Σ jobs.staffed) fill the job slots top-down in `order`; a building's staff cap trims its job's room
# (`bcfg` = buildings.json names the building's job; a site under construction keeps its room).
# `taken` = hands a vat slot takes off the hands being filled (the backups panel's "staffing takes 1
# hand from <job>"): the bottom of `order` loses them first. It is signed: a negative `taken` gives
# hands back (a staffed vat already holds its hand in today's jobs, so unstaffing it frees one, and the
# first job in `order` with room takes it). Only the stand-in says so: TownSim's
# view_staffing_projection(order, {slot: on}) answers it for real, and `project` below maps one to the other.
# (`taken` went with the stand-in.)
# Returns {jobs: [{id, slots, staffed}] in `order`, idle}.
static func staffing_projection(views: Dictionary, order: Array, bcfg: Dictionary = {}, taken := 0) -> Dictionary:
	var town: Dictionary = views.get("town", {})
	var slots := {}
	var room := {}
	var hands := 0.0
	for j in town.get("jobs", []):
		var id := String(j.get("id", ""))
		slots[id] = int(slots.get(id, 0)) + int(j.get("slots", 0))
		room[id] = float(slots[id])
		hands += float(j.get("staffed", 0.0))
	# TownSim fills rooms top-down from all the workers and idle is what is left, so idle hands fill
	# a new slot before any job loses one
	hands += float(town.get("workers", {}).get("idle", 0.0))
	for b in town.get("buildings", []):
		var cap := int(b.get("staff_cap", -1))
		var def: Variant = bcfg.get(String(b.get("building_id", "")))
		if cap < 0 or String(b.get("state", "")) == "constructing" or not def is Dictionary:
			continue
		var jobs: Dictionary = (def as Dictionary).get("jobs", {})
		if jobs.is_empty() or not room.has(String(jobs.keys()[0])):
			continue
		var job := String(jobs.keys()[0])
		room[job] = maxf(float(room[job]) - float(maxi(int(b.get("slots", 0)) - cap, 0)), 0.0)
	var left := maxf(hands - float(taken), 0.0)  # a negative `taken` adds hands
	var out: Array = []
	for id in order:
		if not slots.has(String(id)):
			continue
		var take := minf(float(room[String(id)]), left)
		left -= take
		out.append({"id": String(id), "slots": int(slots[String(id)]), "staffed": take})
	return {"jobs": out, "idle": left}


## The stand-in answer to view_staffing_projection(order, extra): `extra` is {slot: on}, the vat slots
## asked to be staffed (true) or not (false). Today's jobs already hold the hands of the vats that are
## staffed (`views.backups.vats`), so only a change costs or frees a hand: a slot asked on that is off
## takes one, a slot asked off that is on gives one back. Returns {jobs, idle} like staffing_projection.
## Retired with staffing_projection (tests only).
static func project(views: Dictionary, order: Array, bcfg: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var staffed := {}
	for v in views.get("backups", {}).get("vats", []):
		staffed[int(v.get("slot", 0))] = bool(v.get("staffed", false))
	var taken := 0
	for slot in extra:
		var now := bool(staffed.get(int(slot), false))
		var want := bool(extra[slot])
		if want and not now:
			taken += 1
		elif now and not want:
			taken -= 1
	return staffing_projection(views, order, bcfg, taken)


## STANDIN: the inputs of steady_kept's reason (the HUD's "kept: 9 slots + 10 idle cap"): {slots:
## the hands in job slots (Σ jobs.staffed, rounded), cap: economy.json worker.idle_cap}. {} once the
## views carry steady_kept (the reason is then the view's to give).
## TODO(api-request #12): drop with steady_kept (E2b).
static func kept_inputs(town: Dictionary, hud: Dictionary, idle_cap: float) -> Dictionary:
	if (town.get("workers", {}) as Dictionary).has("steady_kept") or hud.has("workers_steady_kept"):
		return {}
	var in_slots := 0.0
	for j in town.get("jobs", []):
		in_slots += float(j.get("staffed", 0.0))
	return {"slots": roundi(in_slots), "cap": roundi(idle_cap)}


const DEMO_FORTS := ["old-sluice", "greywall", "ashgate"]
const DEMO_IDLE := 8.0
const DEMO_LIVING := 64.0
const DEMO_LIVING_CAP := 80.0
const DEMO_TRADE := 2.0
## The demo's flows {id: [in, out]} per second (workers rising toward their steady count), so the HUD shows signed rates.
const DEMO_FLOWS := {
	"workers": [0.30, 0.12], "living": [0.05, 0.02], "gold": [2.0, 0.65],
	"bone": [0.40, 0.55], "bodies": [1.60, 1.30],
}
const DEMO_STEADY := 120.0
const DEMO_ROT := 0.12
const DEMO_BODIES_CAP := 400.0
const DEMO_CAPS := {"gold": 600.0, "bone": 300.0}
const DEMO_MORALE := {"value": 0.64, "target": 0.72, "factors": [
	{"id": "base", "delta": 0.60}, {"id": "amenity:well", "delta": 0.03}, {"id": "dread", "delta": -0.12},
	{"id": "shock", "delta": -0.05}, {"id": "amenity:chapel_of_vats", "delta": 0.10}]}


# STANDIN(E2): view_town's `output` is {} for every building at E1. While that holds, glow and
# pips come from staffing. One non-empty output anywhere switches the stand-in off for the town.
static func outputs_stubbed(buildings: Array) -> bool:
	for b in buildings:
		if not (b.get("output", {}) as Dictionary).is_empty():
			return false
	return true


# STANDIN(E2): glow from staffed / slots while outputs are stubbed.
static func staffing_glow(b: Dictionary) -> float:
	var slots := int(b.get("slots", 0))
	if slots <= 0:
		return 0.0
	return clampf(float(b.get("staffed", 0.0)) / float(slots), 0.0, 1.0)


# STANDIN(E2): pips = round(staffed), in the matter of the building's first job, while outputs
# are stubbed. Returns {pips: int (capped at pip_max), pip_key: String, count: int (uncapped)}.
static func staffing_pips(b: Dictionary, jobs: Dictionary, vcfg: Dictionary) -> Dictionary:
	if jobs.is_empty() or int(b.get("slots", 0)) <= 0:
		return {"pips": 0, "pip_key": "", "count": 0}
	var out_key := String(vcfg.get("standin_job_output", {}).get(String(jobs.keys()[0]), ""))
	var n := maxi(roundi(float(b.get("staffed", 0.0))), 0)
	return {"pips": mini(n, int(vcfg.get("pip_max", 0))), "pip_key": String(vcfg.get("pip_ink", {}).get(out_key, "")), "count": n}


# STANDIN(E2): display only; real trade_rate arrives with E2a. view_town's trade_rate is 0 while
# outputs are stubbed, so the arcs run on staffing: sum of stall staffed x view.standin_sales_per_stall,
# capped at living x view.standin_sales_per_living. The caller uses it only while
# TownModel.staffing_standin holds (every output {}), so real outputs switch it off.
static func trade_rate(town: Dictionary, vcfg: Dictionary) -> float:
	var staffed := 0.0
	for j in town.get("jobs", []):
		if String(j.get("id", "")) == "stall":
			staffed += float(j.get("staffed", 0.0))
	var rate := staffed * float(vcfg.get("standin_sales_per_stall", 0.0))
	var cap := float(town.get("living", 0.0)) * float(vcfg.get("standin_sales_per_living", 0.0))
	return maxf(minf(rate, cap), 0.0)


# TODO(api-request #6): the filled-slot count of a big undead (`filled_slots: int` on its
# view_big_undead entry). One accessor, so the swap is a one-line change.
static func _filled_slots(entry: Dictionary) -> int:
	var f: Variant = entry.get("filled_slots")
	return int(f) if f is int else -1


# TODO(api-request #6): a foreman's diamond draws one stroke per filled remnant slot. Until the
# entry carries `filled_slots` it falls back to the kind's anatomy slots (SlabLogic.slots_for),
# then to view.foreman_strokes. `slab_cfg` = configs["town"]["slab"].
static func foreman_strokes(entry: Dictionary, vcfg: Dictionary, slab_cfg: Dictionary) -> int:
	var filled := _filled_slots(entry)
	if filled >= 0:
		return maxi(filled, 1)
	var n := SlabLogic.slots_for(String(entry.get("kind", "")), slab_cfg).size()
	if n > 0:
		return n
	return int(vcfg.get("foreman_strokes", 0))


# TODO(api-request #3): the build queue lives here until E2 ships `cmd_queue_build`,
# `cmd_unqueue`, `cmd_reorder_queue` and `view_town().queue` / `queue_max`. It mirrors that shape
# (entries `{building_id, lot_id, upgrade, level, cost, status, reason}`, statuses `next`,
# `waiting_funds`, `skipped_gate`, `queued`) and never touches GameState or calls a build command.
# Not saved. It switches itself off when `view_town()` carries a `queue` key.
static func queue_is_standin(town: Dictionary) -> bool:
	return not town.has("queue")


## The entries to show: the view's `queue` once it exists (even empty), else the stand-in's `local` ones.
static func queue_entries(town: Dictionary, local: Array) -> Array:
	return local if queue_is_standin(town) else town["queue"]


## The local queue. `ctx` (BuildSort.queue_context): {gold, bone, relics, gold_cap, bone_cap (-1 =
## none), catalog: {building_id: row}, built: {lot_id: {building_id, level, max_level, state}},
## gates: Array[String]}. IDLE 5: processed in order; a head blocked by a gate that time can't
## resolve (tier, blueprint, building, relics, a taken lot, max level) is flagged and skipped; a head
## blocked only by affordability holds the queue (everything behind it stays `queued`).
class BuildQueue:
	extends RefCounted
	var entries: Array = []
	var max_len := 8
	## store -> building id that raises that cap (config view.cap_buildings; stand-in names until E2).
	var cap_buildings: Dictionary = {}
	var _ctx: Dictionary = {}

	func _init(max_len_ := 8, cap_buildings_: Dictionary = {}) -> void:
		max_len = max_len_
		cap_buildings = cap_buildings_

	## `e`: {building_id, lot_id, upgrade: bool, level: int (the level it builds), cost}. Mirrors
	## cmd_queue_build: {ok, reason, index, cap_building}. Affordability never refuses.
	func add(e: Dictionary, ctx: Dictionary) -> Dictionary:
		var cost: Dictionary = e.get("cost", {})
		if entries.size() >= max_len:
			return _refuse("queue_full")
		for store in ["gold", "bone"]:
			var cap := float(ctx.get(store + "_cap", -1.0))
			if cap >= 0.0 and float(cost.get(store, 0.0)) > cap:
				var r := _refuse("cost_exceeds_cap")
				r["cap_building"] = String(cap_buildings.get(store, ""))
				r["store"] = store
				return r
		if not bool(e.get("upgrade", false)):
			var row: Dictionary = ctx.get("catalog", {}).get(String(e.get("building_id", "")), {})
			if row.is_empty():
				return _refuse("unknown_building")
			if String(row.get("reason", "")) in ctx.get("gates", []):
				return _refuse(String(row["reason"]))
			if not String(e.get("lot_id", "")) in row.get("lots", []):
				return _refuse("lot_taken")
		var ent := {
			"building_id": String(e.get("building_id", "")), "lot_id": String(e.get("lot_id", "")),
			"upgrade": bool(e.get("upgrade", false)), "level": int(e.get("level", 1)),
			"cost": (cost as Dictionary).duplicate(), "status": "queued", "reason": "",
		}
		entries.append(ent)
		evaluate(ctx)
		return {"ok": true, "reason": "", "index": entries.size() - 1, "cap_building": ""}

	## cmd_unqueue(index): {ok, reason}.
	func unqueue(index: int) -> Dictionary:
		if index < 0 or index >= entries.size():
			return {"ok": false, "reason": "unknown_index"}
		entries.remove_at(index)
		evaluate(_ctx)
		return {"ok": true, "reason": ""}

	## cmd_reorder_queue(order): `order[k]` is the old index that moves to position k; a
	## permutation of the current indices, else `bad_order`.
	func reorder(order: Array) -> Dictionary:
		var seen := {}
		for i in order:
			if not i is int or i < 0 or i >= entries.size() or seen.has(i):
				return {"ok": false, "reason": "bad_order"}
			seen[i] = true
		if order.size() != entries.size():
			return {"ok": false, "reason": "bad_order"}
		var out: Array = []
		for i in order:
			out.append(entries[i])
		entries = out
		evaluate(_ctx)
		return {"ok": true, "reason": ""}

	## Moves entry `index` by `delta` places (clamped); a convenience over reorder().
	func move(index: int, delta: int) -> Dictionary:
		var to := clampi(index + delta, 0, maxi(entries.size() - 1, 0))
		if index < 0 or index >= entries.size():
			return {"ok": false, "reason": "unknown_index"}
		var order: Array = range(entries.size())
		order.remove_at(index)
		order.insert(to, index)
		return reorder(order)

	## Recomputes every entry's status and reason against `ctx`.
	func evaluate(ctx: Dictionary) -> void:
		_ctx = ctx
		var head_taken := false
		for ent in entries:
			ent["reason"] = ""
			var gate := _gate(ent, ctx)
			if gate != "":
				ent["status"] = "skipped_gate"
				ent["reason"] = gate
			elif head_taken:
				ent["status"] = "queued"
			else:
				head_taken = true
				var why := ""
				for k in ["gold", "bone"]:
					if why == "" and float(ent["cost"].get(k, 0.0)) > float(ctx.get(k, 0.0)) + 0.0001:
						why = "no_" + k
				ent["status"] = "waiting_funds" if why != "" else "next"
				ent["reason"] = why

	func _gate(ent: Dictionary, ctx: Dictionary) -> String:
		if float(ent["cost"].get("relics", 0)) > float(ctx.get("relics", 0.0)) + 0.0001:
			return "no_relics"
		if ent["upgrade"]:
			var info: Dictionary = ctx.get("built", {}).get(ent["lot_id"], {})
			if info.is_empty() or info.get("building_id", "") != ent["building_id"]:
				return "empty_lot"
			if int(info.get("level", 0)) >= int(info.get("max_level", 1)):
				return "max_level"
			return ""
		var row: Dictionary = ctx.get("catalog", {}).get(ent["building_id"], {})
		var why := String(row.get("reason", ""))
		if why in ctx.get("gates", []):
			return why
		if not ent["lot_id"] in row.get("lots", []):
			return "lot_taken"
		return ""

	func _refuse(reason: String) -> Dictionary:
		return {"ok": false, "reason": reason, "index": -1, "cap_building": ""}


## A synthetic full city for `--town-demo=full`, built on `base` (the shell's views dict) so every
## view and key a real fetch has is present. Only `town` and the HUD's worker/living stocks change.
static func demo_views(base: Dictionary, buildings_cfg: Dictionary, town_cfg: Dictionary) -> Dictionary:
	var v: Dictionary = base.duplicate(true)
	var town: Dictionary = v.get("town", {})
	var lots: Array = []
	var buildings: Array = []
	var job_slots := {}
	var staffed_total := 0.0
	for l in town_cfg.get("lots", []):
		var lot_id := String(l.get("id", ""))
		var bid := String(DEMO_PLAN.get(lot_id, ""))
		lots.append({"id": lot_id, "size": int(l.get("size", 1)), "unlocked": true, "building_id": bid})
		if bid == "":
			continue
		var def: Dictionary = buildings_cfg.get(bid, {})
		var jobs: Dictionary = def.get("jobs", {})
		var st: Array = DEMO_STATES.get(lot_id, ["active", 1.0, 1])
		var lvl := int(st[2])
		if st[0] == "active" and not jobs.is_empty():
			lvl = maxi(int(def.get("max_level", 1)), 1)  # a full city: job buildings at their top level
		var slots := 0
		for j in jobs:
			slots += int(jobs[j]) * maxi(lvl, 1)
		var active: bool = st[0] == "active"
		var output := {}
		if active and not jobs.is_empty():
			var job := String(jobs.keys()[0])
			output = (DEMO_OUTPUT.get(job, {}) as Dictionary).duplicate()
			for j in jobs:
				job_slots[j] = int(job_slots.get(j, 0)) + int(jobs[j]) * lvl
			staffed_total += float(slots)
		var up: Dictionary = def.get("upkeep", {})
		buildings.append({
			"lot_id": lot_id, "building_id": bid, "level": lvl, "state": String(st[0]),
			"progress": float(st[1]), "slots": slots, "staffed": float(slots) if active else 0.0,
			"staff_cap": 0 if st[0] == "idle" else -1, "foreman": "", "output": output,
			"upkeep": {"gold": float(up.get("gold", 0.0)), "bone": float(up.get("bone", 0.0))},
			"work_left": float(def.get("build_work", 0.0)) * (lvl + 1) * (1.0 - float(st[1])) if st[0] == "constructing" else 0.0,
			"upgrade_work": float(def.get("build_work", 0.0)) * (lvl + 1) if lvl < int(def.get("max_level", 1)) else 0.0,
			"eta_s": -1.0,
			"upgrade_projected": {},
			"starved": "",
			"lever": "",  # v11 (E4's A1 day-1 ruling): the lever for `starved`; none in the demo
			"foreman_mult": 1.0,
		})
	var jobs_out: Array = []
	for j in town.get("ladder_effective", []):
		if job_slots.has(j):
			jobs_out.append({"id": String(j), "slots": int(job_slots[j]), "staffed": float(job_slots[j])})
	town["tier"] = "city"
	town["next_tier"] = {"tier": "", "have": buildings.size(), "need": 0, "missing": []}
	town["lots"] = lots
	town["buildings"] = buildings
	town["jobs"] = jobs_out
	var workers: Dictionary = town.get("workers", {})
	workers["total"] = staffed_total + DEMO_IDLE
	workers["idle"] = DEMO_IDLE
	town["workers"] = workers
	town["living"] = DEMO_LIVING
	town["living_cap"] = DEMO_LIVING_CAP
	town["trade_rate"] = DEMO_TRADE
	town["haul"] = {"target": "auto", "current": DEMO_FORTS[0], "convoys": [
		{"from": "covington", "to": DEMO_FORTS[0], "phase": "out", "t": 0.3, "load": 0.0},
		{"from": DEMO_FORTS[1], "to": "covington", "phase": "back", "t": 0.6, "load": 14.0},
		{"from": DEMO_FORTS[2], "to": "covington", "phase": "back", "t": 0.9, "load": 22.0},
	]}
	town["relish_home"] = true
	v["town"] = town
	for r in v.get("hud", {}).get("rates", []):
		var rid := String(r.get("id", ""))
		if rid == "workers":
			r["stock"] = staffed_total + DEMO_IDLE
		elif rid == "living":
			r["stock"] = DEMO_LIVING
			r["cap"] = DEMO_LIVING_CAP
		if DEMO_FLOWS.has(rid):
			r["rate"] = float(DEMO_FLOWS[rid][0]) - float(DEMO_FLOWS[rid][1])
			if DEMO_CAPS.has(rid):
				r["cap"] = float(DEMO_CAPS[rid])
			elif rid == "bodies":
				r["cap"] = DEMO_BODIES_CAP
	town["bodies_cap"] = DEMO_BODIES_CAP
	workers["steady"] = DEMO_STEADY
	workers["in"] = float(DEMO_FLOWS["workers"][0])
	workers["rot"] = DEMO_ROT
	town["migrants"] = float(DEMO_FLOWS["living"][0])
	town["departures"] = float(DEMO_FLOWS["living"][1])
	town["morale"] = DEMO_MORALE.duplicate(true)
	var rr: Dictionary = {}
	for id in DEMO_FLOWS:
		var f: Array = DEMO_FLOWS[id]
		rr[id] = {"in": float(f[0]), "out": float(f[1]), "net": float(f[0]) - float(f[1]), "unit": "%s/s" % id}
	v["rates"] = {"rev": int(v.get("hud", {}).get("rev", 0)), "rates": rr}
	return v
