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
	"forge": {"q": 0.04}, "tend": {"q": 0.02},
}
const DEMO_FORTS := ["old-sluice", "greywall", "ashgate"]
const DEMO_WORKERS := 180.0
const DEMO_LIVING := 64.0
const DEMO_LIVING_CAP := 80.0
const DEMO_TRADE := 2.0


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
# are stubbed. Returns {pips: int, pip_key: String}.
static func staffing_pips(b: Dictionary, jobs: Dictionary, vcfg: Dictionary) -> Dictionary:
	if jobs.is_empty() or int(b.get("slots", 0)) <= 0:
		return {"pips": 0, "pip_key": ""}
	var out_key := String(vcfg.get("standin_job_output", {}).get(String(jobs.keys()[0]), ""))
	var pips := clampi(roundi(float(b.get("staffed", 0.0))), 0, int(vcfg.get("pip_max", 0)))
	return {"pips": pips, "pip_key": String(vcfg.get("pip_ink", {}).get(out_key, ""))}


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
		var slots := 0
		for j in jobs:
			slots += int(jobs[j])
		var active: bool = st[0] == "active"
		var output := {}
		if active and not jobs.is_empty():
			var job := String(jobs.keys()[0])
			if job == "pit":
				var eff: Dictionary = def.get("effects", {})
				output = {"mint": float(eff.get("mint", 0.0)), "burn": float(eff.get("burn", 0.0))}
			else:
				output = (DEMO_OUTPUT.get(job, {}) as Dictionary).duplicate()
			for j in jobs:
				job_slots[j] = int(job_slots.get(j, 0)) + int(jobs[j])
			staffed_total += float(slots)
		var up: Dictionary = def.get("upkeep", {})
		buildings.append({
			"lot_id": lot_id, "building_id": bid, "level": int(st[2]), "state": String(st[0]),
			"progress": float(st[1]), "slots": slots, "staffed": float(slots) if active else 0.0,
			"staff_cap": 0 if st[0] == "idle" else -1, "foreman": "", "output": output,
			"upkeep": {"gold": float(up.get("gold", 0.0)), "bone": float(up.get("bone", 0.0))},
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
	workers["total"] = DEMO_WORKERS
	workers["idle"] = DEMO_WORKERS - staffed_total
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
		if r.get("id", "") == "workers":
			r["stock"] = DEMO_WORKERS
		elif r.get("id", "") == "living":
			r["stock"] = DEMO_LIVING
			r["cap"] = DEMO_LIVING_CAP
	return v
