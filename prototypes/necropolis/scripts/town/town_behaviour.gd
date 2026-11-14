class_name TownBehaviour
extends RefCounted
## Pure helpers for the Jobs and Stances tabs (MECHANICS §4.5): reorder math, the ladder diff, the
## staffing-cap stepper, staffing-change detection, the stance slot breakdown and the projected
## effect text. No autoloads, no Engine, no Nodes, so the suite can exercise it.


## `order` with the element at `i` moved so it ends at index `j` (a permutation of `order`).
static func move(order: Array, i: int, j: int) -> Array:
	var out := order.duplicate()
	if i < 0 or i >= out.size():
		return out
	var item = out[i]
	out.remove_at(i)
	out.insert(clampi(j, 0, out.size()), item)
	return out


## Where the dragged row (at `i`) ends up when dropped on the upper or lower half of row `k`.
static func drop_index(i: int, k: int, lower: bool) -> int:
	var insert_at := k + (1 if lower else 0)  # a slot in the list as it stands before the removal
	return insert_at - 1 if i < insert_at else insert_at


## Jobs whose place differs between the player's `ladder` and `ladder_effective` (a stance moved
## them): [{job, from, to}] in effective order. Index 0 is the top.
static func ladder_moves(ladder: Array, effective: Array) -> Array:
	var out: Array = []
	if effective.is_empty():
		return out
	for to in effective.size():
		var from := ladder.find(effective[to])
		if from >= 0 and from != to:
			out.append({"job": String(effective[to]), "from": from, "to": to})
	return out


## The next staffing cap. `cap` -1 means no cap; the sequence going up is -1, 0, 1 ... slots, then
## back to -1 (dir = +1); going down it is the reverse. A cap above `slots` counts as `slots`.
static func cap_step(cap: int, slots: int, dir: int) -> int:
	var c := mini(cap, maxi(slots, 0)) if cap >= 0 else -1
	var top := maxi(slots, 0)
	if dir >= 0:
		return -1 if (c >= top) else c + 1
	if c == -1:
		return top
	return c - 1


static func cap_text(cap: int, slots: int, all_text: String) -> String:
	return all_text if cap < 0 else str(mini(cap, maxi(slots, 0)))


## Jobs whose staffed count moved by more than `eps` since `prev` (job -> float). Empty when `prev`
## is empty (no baseline yet).
static func staffing_changes(prev: Dictionary, jobs: Array, eps: float) -> Array:
	var out: Array = []
	if prev.is_empty():
		return out
	for j in jobs:
		var id := String(j.get("id", ""))
		if prev.has(id) and absf(float(j.get("staffed", 0.0)) - float(prev[id])) > eps:
			out.append(id)
	return out


## The stance slot count as parts: the base, the Guildhall (what is left over) and 1 while Relish
## is home. `home` is 0 when she is away, so the Guildhall never goes negative.
static func slot_breakdown(slots: int, base: int, relish_home: bool) -> Dictionary:
	var home := 1 if relish_home else 0
	return {"base": base, "home": home, "guild": maxi(slots - base - home, 0)}


## Display parts for a stance's `projected` ({rate_id: delta/s}): "+0.40/s bodies". Sorted by the
## size of the change, biggest first; zero entries dropped.
static func projected_parts(projected: Dictionary, units: Dictionary) -> Array:
	var rows: Array = []
	for k in projected:
		var v := float(projected[k])
		if absf(v) < 0.005:
			continue
		rows.append([String(k), v])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return absf(a[1]) > absf(b[1]))
	var out: Array = []
	for r in rows:
		var unit := String(units.get(r[0], {}).get("unit", r[0]))
		var sign_ch := "−" if r[1] < 0.0 else "+"
		out.append("%s%.2f/s %s" % [sign_ch, absf(r[1]), unit])
	return out


## Jobs of the buildings that turned idle between two town views. `prev_idle` is lot id -> bool
## (the last view's idle state); `job_of_building` is building id -> Array of job ids.
static func idled_jobs(prev_idle: Dictionary, buildings: Array, job_of_building: Dictionary) -> Array:
	var out: Array = []
	for b in buildings:
		var lot := String(b.get("lot_id", ""))
		if String(b.get("state", "")) == "idle" and prev_idle.has(lot) and not bool(prev_idle[lot]):
			for j in job_of_building.get(String(b.get("building_id", "")), []):
				if not out.has(j):
					out.append(j)
	return out
