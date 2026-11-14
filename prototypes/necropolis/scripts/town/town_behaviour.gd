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


# ------------------------------------------------------------- the preview ----
## `order` with `job` moved to the top (a copy, unchanged when `job` is absent).
static func to_top(order: Array, job: String) -> Array:
	var i := order.find(job)
	return move(order, i, 0) if i >= 0 else order.duplicate()


## The staffing change between two allocations ([{id, slots, staffed}], e.g. the staffing projection
## of today's order and of a moved one): [{id, delta}] in `after`'s order, then jobs only in `before`;
## changes under `eps` are left out. The total moved is conserved when both allocate the same hands.
static func staffing_diff(before: Array, after: Array, eps := 0.01) -> Array:
	var was := {}
	for j in before:
		was[String(j.get("id", ""))] = float(j.get("staffed", 0.0))
	var out: Array = []
	var seen := {}
	for j in after:
		var id := String(j.get("id", ""))
		seen[id] = true
		var d := float(j.get("staffed", 0.0)) - float(was.get(id, 0.0))
		if absf(d) >= eps:
			out.append({"id": id, "delta": d})
	for id in was:
		if not seen.has(id) and absf(float(was[id])) >= eps:
			out.append({"id": String(id), "delta": -float(was[id])})
	return out


## "Mill +2 hands, Pit −2": the diff as whole hands (rounded), gains first then losses, each the
## largest first; the unit word follows the first count only. `labels` maps job ids to names. "" when
## no whole hand moves.
static func diff_text(diff: Array, labels: Dictionary, unit_one: String, unit_many: String) -> String:
	var rows: Array = []
	for d in diff:
		var n := roundi(float(d["delta"]))
		if n != 0:
			rows.append([String(d["id"]), n])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if (a[1] > 0) != (b[1] > 0):
			return a[1] > 0
		return absi(a[1]) > absi(b[1]))
	var parts: Array = []
	for r in rows:
		var txt := "%s %s%d" % [String(labels.get(r[0], String(r[0]).capitalize())), "+" if r[1] > 0 else "−", absi(r[1])]
		if parts.is_empty():
			txt += " " + (unit_one if absi(r[1]) == 1 else unit_many)
		parts.append(txt)
	return ", ".join(parts)


## The ladder a stance acts on: `ladder_effective`, else `ladder`.
static func effective(town: Dictionary) -> Array:
	var eff: Array = town.get("ladder_effective", [])
	return eff if not eff.is_empty() else town.get("ladder", [])


## The job a stance moves to the top of the ladder (view.stance_jobs, when it names a ladder job),
## else "" (Thrift idles buildings, Muster sends idle hands to WAR).
static func stance_job(id: String, town: Dictionary, vcfg: Dictionary) -> String:
	var spec: Variant = (vcfg.get("stance_jobs", {}) as Dictionary).get(id, [])
	if spec is Array and not (spec as Array).is_empty() and String(spec[0]) in effective(town):
		return String(spec[0])
	return ""


## A stance's trade in the town's numbers, as parts [[text, oblique]]: its live condition read from
## the views and what it would move, e.g. "Now: bodies 2 / 200 (fires under 60) → it would fire; Haul
## to the top: no hands move". `before`/`after` are the staffing projections of today's ladder and of
## the ladder with the stance's job on top ([] for a stance that doesn't reorder). STANDIN(E3): the
## thresholds are view.stance_trade's display copies of MECHANICS §4.5 until stances are live.
static func stance_trade(id: String, views: Dictionary, before: Array, after: Array, vcfg: Dictionary) -> Array:
	var tx: Dictionary = vcfg.get("behaviour", {})
	var spec: Dictionary = (vcfg.get("stance_trade", {}) as Dictionary).get(id, {})
	var town: Dictionary = views.get("town", {})
	var w: Dictionary = town.get("workers", {})
	var now: Variant = ""
	var fires := false
	match String(spec.get("when", "")):
		"relish_away":
			fires = String(views.get("relish", {}).get("state", "home")) != "home"
			now = String(tx.get("now_relish_away" if fires else "now_relish_home", ""))
		"bodies_under":
			var cap := float(town.get("bodies_cap", 0.0))
			var limit := float(spec.get("frac", 0.0)) * cap
			fires = cap > 0.0 and float(town.get("bodies", 0.0)) < limit
			now = BuildSort.fmt(String(tx.get("now_bodies", "")), {"have": int(float(town.get("bodies", 0.0))), "cap": roundi(cap), "limit": roundi(limit)})
		"morale_under":
			var v := float(town.get("morale", {}).get("value", 0.0))
			fires = v < float(spec.get("below", 0.0))
			now = BuildSort.fmt(String(tx.get("now_morale", "")), {"v": "%.2f" % v, "limit": "%.2f" % float(spec.get("below", 0.0))})
		"gold_under_upkeep":
			var g: Dictionary = views.get("rates", {}).get("rates", {}).get("gold", {})
			fires = float(g.get("in", 0.0)) < float(g.get("out", 0.0))
			now = HudModel.fill_parts(String(tx.get("now_gold", "")), {"in": [[TownUI.fmt_rate(float(g.get("in", 0.0))), true]],
				"out": [[TownUI.fmt_rate(-float(g.get("out", 0.0))), true]]})
		"idle":
			fires = roundi(float(w.get("idle", 0.0))) >= 1
			now = BuildSort.fmt(String(tx.get("now_idle", "")), {"n": roundi(float(w.get("idle", 0.0)))})
	var move := ""
	var job := stance_job(id, town, vcfg)
	if job != "":
		var hands := diff_text(staffing_diff(before, after), vcfg.get("job_labels", {}), String(tx.get("hand", "")), String(tx.get("hands", "")))
		move = BuildSort.fmt(String(tx.get("trade_top", "")), {"job": String((vcfg.get("job_labels", {}) as Dictionary).get(job, job.capitalize())),
			"hands": hands if hands != "" else String(tx.get("no_hands", ""))})
	elif String(spec.get("when", "")) == "idle":
		move = BuildSort.fmt(String(tx.get("trade_muster", "")), {"n": roundi(float(w.get("idle", 0.0)))})
	elif String(spec.get("when", "")) == "gold_under_upkeep":
		move = String(tx.get("trade_thrift", ""))
	return HudModel.fill_parts(String(tx.get("trade_fires" if fires else "trade_holds", "")), {"now": now, "move": move})
