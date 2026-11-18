class_name TownForecast
extends RefCounted
## "If you leave now" (Q-f; review-town-c's must-fix 3): one line, from the numbers the views already carry, of
## what the away time will do, so the player sets it up before leaving. The same facts the away report later
## tells (STATE-API §5.19: the queue head's affordable_in_s, the stores, the held forts' margins), read ahead:
## - the queue's head: starts at once, in ~t (`affordable_in_s`), never at today's income, or nothing queued;
## - the first store to fill within view.forecast.horizon_s (stores past the cap aren't kept);
## - idle hands, which muster away (view_hud.split.muster_to);
## - each held fort whose margin reads will_fall.
## Pure; texts in configs/town.json view.forecast.


static func line(views: Dictionary, vcfg: Dictionary, bview: Dictionary) -> String:
	var parts := parts_of(views, vcfg, bview)
	if parts.is_empty():
		return ""
	var fc: Dictionary = vcfg.get("forecast", {})
	return String(fc.get("lead", "")) + String(fc.get("sep", " · ")).join(parts)


static func parts_of(views: Dictionary, vcfg: Dictionary, bview: Dictionary) -> Array:
	var fc: Dictionary = vcfg.get("forecast", {})
	var out: Array = []
	var q := queue_part(views, vcfg, bview)
	if q != "":
		out.append(q)
	var s := store_part(views, fc, vcfg)
	if s != "":
		out.append(s)
	var town: Dictionary = views.get("town", {})
	var idle := int(floor(float((town.get("workers", {}) as Dictionary).get("idle", 0.0))))
	if idle >= int(fc.get("idle_min", 1)):
		out.append(BuildSort.fmt(String(fc.get("idle", "")), {"n": idle, "to": HudModel.muster_name(views, vcfg)}))
	for f in views.get("forts", []):
		if bool(f.get("held", false)) and String(f.get("margin", "")) == "will_fall":
			out.append(BuildSort.fmt(String(fc.get("falls", "")), {"fort": String(f.get("name", ""))}))
	return out


## The queue's part: its first entry that isn't gated, by its own `affordable_in_s`; the first gated entry's wait
## when every entry is gated; `queue_empty` when nothing is queued. "" without a real queue (the stand-in).
static func queue_part(views: Dictionary, vcfg: Dictionary, bview: Dictionary) -> String:
	var town: Dictionary = views.get("town", {})
	if not town.has("queue"):
		return ""
	var fc: Dictionary = vcfg.get("forecast", {})
	var q: Array = town["queue"]
	if q.is_empty():
		return String(fc.get("queue_empty", ""))
	for e in q:
		var status := String(e.get("status", ""))
		if status == "skipped_gate":
			continue
		var label := BuildSort.label_of(String(e.get("building_id", "")), bview)
		var a := float(e.get("affordable_in_s", 0.0 if status == "next" else -1.0))
		if status == "next" or a == 0.0:
			return BuildSort.fmt(String(fc.get("starts_now", "")), {"label": label})
		if a > 0.0:
			return BuildSort.fmt(String(fc.get("starts_in", "")), {"label": label, "t": BuildSort.fmt_eta(a, vcfg)})
		return BuildSort.fmt(String(fc.get("never", "")), {"label": label})
	var first: Dictionary = q[0]
	return BuildSort.fmt(String(fc.get("gated", "")), {"label": BuildSort.label_of(String(first.get("building_id", "")), bview)})


## The first of forecast.stores to fill within horizon_s at its net rate ("bone full in 6 min"), or one full now.
static func store_part(views: Dictionary, fc: Dictionary, vcfg: Dictionary) -> String:
	var best := ""
	var best_s := float(fc.get("horizon_s", 28800.0))
	for id in fc.get("stores", []):
		var r := BuildSort.hud_rate(views.get("hud", {}), String(id))
		var cap := float(r.get("cap", -1.0))
		var stock := float(r.get("stock", 0.0))
		var net := float(r.get("rate", 0.0))
		if cap <= 0.0:
			continue
		if stock >= cap and net >= 0.0:
			return BuildSort.fmt(String(fc.get("full_now", "")), {"id": id})
		if net > 0.0 and (cap - stock) / net < best_s:
			best_s = (cap - stock) / net
			best = BuildSort.fmt(String(fc.get("full_in", "")), {"id": id, "t": BuildSort.fmt_eta(best_s, vcfg)})
	return best
