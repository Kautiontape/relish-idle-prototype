class_name HudModel
extends RefCounted
## The town HUD's logic, pure (no autoloads, no Nodes): signed net rates with their sign glyphs,
## the workers' steady-state arrow, store "full in" readouts, the morale factor line, the next-tier
## line and the bottleneck line. Tuning and texts live in configs/town.json `view.hud`.
##   var net := HudModel.net_text(-0.05, hcfg)        # "−0.05/s"; "±0.00/s" inside the dead band


static func _t(hcfg: Dictionary, key: String) -> String:
	return String((hcfg.get("text", {}) as Dictionary).get(key, ""))


## True when |x| rounds to zero at the display precision (the dead band, `rate_eps`).
static func is_flat(x: float, hcfg: Dictionary) -> bool:
	return absf(x) < float(hcfg.get("rate_eps", 0.005))


## "+0.42/s", "−0.10/s" (true minus), "±0.00/s" for a flat rate. `unit` replaces "s".
static func net_text(x: float, hcfg: Dictionary, unit := "s") -> String:
	if is_flat(x, hcfg):
		return "±0.00/%s" % unit
	return TownUI.fmt_rate(x, unit)


## The in/out split under a net rate: [[label, signed value]] -> "in +0.30 · out −0.14 /s" (one `/s`
## for all parts; outflows are passed negative).
static func split_text(parts: Array, hcfg: Dictionary) -> String:
	var out: Array = []
	for p in parts:
		out.append("%s %s" % [p[0], net_text(float(p[1]), hcfg, "").trim_suffix("/")])
	return _t(hcfg, "factor_sep").join(out) + " /s"


## The sign glyph beside a net rate (shape, so the sign is never colour only): up, down or flat.
static func glyph(x: float, hcfg: Dictionary) -> String:
	var g: Dictionary = hcfg.get("glyph", {})
	if is_flat(x, hcfg):
		return String(g.get("flat", ""))
	return String(g.get("up", "")) if x > 0.0 else String(g.get("down", ""))


## Direction of the workforce toward its steady state: 1 = rising (count below steady), -1 = falling
## (above), 0 = at it (within `tol_frac` of steady, at least `tol_min` workers).
static func steady_dir(total: float, steady: float, hcfg: Dictionary) -> int:
	var tol := maxf(float(hcfg.get("tol_min", 0.5)), absf(steady) * float(hcfg.get("tol_frac", 0.02)))
	if total < steady - tol:
		return 1
	if total > steady + tol:
		return -1
	return 0


## The arrow for `steady_dir`: the glyph's up / down / flat shape.
static func steady_arrow(total: float, steady: float, hcfg: Dictionary) -> String:
	var g: Dictionary = hcfg.get("glyph", {})
	match steady_dir(total, steady, hcfg):
		1:
			return String(g.get("up", ""))
		-1:
			return String(g.get("down", ""))
	return String(g.get("flat", ""))


static func steady_text(steady: float, hcfg: Dictionary) -> String:
	return BuildSort.fmt(_t(hcfg, "steady"), {"n": roundi(steady)})


## "45 s", "3 min", "6 h", "3 d": the duration, switching unit at the `dur_*_from_s` thresholds.
static func fmt_dur(seconds: float, hcfg: Dictionary) -> String:
	var tx: Dictionary = hcfg.get("text", {})
	if seconds < float(tx.get("dur_min_from_s", 90.0)):
		return BuildSort.fmt(_t(hcfg, "dur_s"), {"n": maxi(int(ceil(seconds)), 1)})
	if seconds < float(tx.get("dur_h_from_s", 5400.0)):
		return BuildSort.fmt(_t(hcfg, "dur_min"), {"n": maxi(roundi(seconds / 60.0), 1)})
	if seconds < float(tx.get("dur_d_from_s", 172800.0)):
		return BuildSort.fmt(_t(hcfg, "dur_h"), {"n": ("%.1f" % (seconds / 3600.0)).trim_suffix(".0")})
	return BuildSort.fmt(_t(hcfg, "dur_d"), {"n": ("%.1f" % (seconds / 86400.0)).trim_suffix(".0")})


## The store readout: "no cap" (cap < 0), "full: overflowing" (at the cap), "full in 6 h" (net > 0
## and room left), "" (room left, not filling). IDLE 6.
static func store_text(stock: float, cap: float, net: float, hcfg: Dictionary) -> String:
	if cap < 0.0:
		return _t(hcfg, "no_cap")
	if stock >= cap:
		return _t(hcfg, "full")
	if net > 0.0 and not is_flat(net, hcfg):
		return BuildSort.fmt(_t(hcfg, "full_in"), {"t": fmt_dur((cap - stock) / net, hcfg)})
	return ""


## Morale factor ids in display order (`morale_order`: base, dread, shock, then amenities), a
## stable sort that keeps the view's order inside a group. Zero deltas are dropped.
static func morale_factors(morale: Dictionary, hcfg: Dictionary, bview: Dictionary) -> Array:
	var order: Array = hcfg.get("morale_order", [])
	var out: Array = []
	var seq := 0
	for f in morale.get("factors", []):
		var id := String(f.get("id", ""))
		var delta := float(f.get("delta", 0.0))
		if absf(delta) < 0.005:
			continue
		var group := id.get_slice(":", 0)
		var rank := order.find(group)
		var label := id
		if group == "amenity":
			label = BuildSort.label_of(id.get_slice(":", 1), bview).to_lower()
		elif _t(hcfg, group) != "":
			label = _t(hcfg, group)
		out.append({"label": label, "delta": delta, "rank": rank if rank >= 0 else order.size(), "seq": seq})
		seq += 1
	out.sort_custom(func(a, b):
		if a["rank"] != b["rank"]:
			return a["rank"] < b["rank"]
		return a["seq"] < b["seq"])
	return out


## "base +0.60 · dread −0.12 · shock −0.05 · well +0.03" (signed, 2 decimals, true minus).
static func factor_line(morale: Dictionary, hcfg: Dictionary, bview: Dictionary) -> String:
	var parts: Array = []
	for f in morale_factors(morale, hcfg, bview):
		parts.append("%s %s%.2f" % [f["label"], "−" if f["delta"] < 0.0 else "+", absf(f["delta"])])
	return _t(hcfg, "factor_sep").join(parts)


## "next: Village — 4/6 buildings, missing: House"; at City (`next.tier` "") the tier alone: "City".
static func next_tier_line(tier: String, next: Dictionary, hcfg: Dictionary, bview: Dictionary) -> String:
	var nt := String(next.get("tier", ""))
	if nt == "":
		return BuildSort.fmt(_t(hcfg, "at_city"), {"tier": tier.capitalize()})
	var miss: Array = []
	for b in next.get("missing", []):
		miss.append(BuildSort.label_of(String(b), bview))
	var missing := ""
	if not miss.is_empty():
		missing = BuildSort.fmt(_t(hcfg, "next_missing"), {"list": ", ".join(miss)})
	return BuildSort.fmt(_t(hcfg, "next_tier"), {"tier": nt.capitalize(), "have": int(next.get("have", 0)),
		"need": int(next.get("need", 0)), "missing": missing})


# -------------------------------------------------------------- bottleneck ----
## Net rate of `id` (view_hud's signed net).
static func net_of(views: Dictionary, id: String) -> float:
	return float(BuildSort.hud_rate(views.get("hud", {}), id).get("rate", 0.0))


## How many of `building_id` stand finished (level >= 1) and how many are only being built.
static func presence(town: Dictionary, building_id: String) -> Dictionary:
	var done := 0
	var building := 0
	for b in town.get("buildings", []):
		if String(b.get("building_id", "")) != building_id:
			continue
		if int(b.get("level", 0)) >= 1:
			done += 1
		else:
			building += 1
	return {"done": done, "building": building}


## One stuck-stream line for resource `id` whose producer is `fix` ("gold: ±0.00/s, no Market"), or
## "" when the stream isn't stuck (net above the dead band) or has no producer to name.
static func stuck_line(id: String, fix: String, views: Dictionary, hcfg: Dictionary, bview: Dictionary) -> String:
	var net := net_of(views, id)
	if fix == "" or net > 0.0 and not is_flat(net, hcfg):
		return ""
	var tx: Dictionary = hcfg.get("text", {})
	var vars := {"id": id, "rate": net_text(net, hcfg), "label": BuildSort.label_of(fix, bview),
		"source": String((tx.get("source", {}) as Dictionary).get(id, ""))}
	var p := presence(views.get("town", {}), fix)
	if p["done"] > 0:
		if net < 0.0 and not is_flat(net, hcfg):
			return BuildSort.fmt(String(tx.get("upkeep", "")), vars)
		return BuildSort.fmt(String(tx.get("unstaffed", "")), vars)
	if p["building"] > 0:
		return BuildSort.fmt(String(tx.get("building", "")), vars)
	return BuildSort.fmt(String(tx.get("no_producer", "")), vars)


## Workers short of the slots the buildings offer: how many slots are unstaffed while no worker idles.
static func short_slots(town: Dictionary) -> int:
	if float(town.get("workers", {}).get("idle", 0.0)) >= 1.0:
		return 0
	var short := 0.0
	for j in town.get("jobs", []):
		short += maxf(float(j.get("slots", 0)) - float(j.get("staffed", 0.0)), 0.0)
	return int(floor(short + 0.0001))


## What is stuck, one string per line item, most wanted first: (1) the first resource-short row of
## the mission-sorted catalog (gold or bone, its net rate in the dead band or negative, its
## `shortage_fix` producer named); (2) any other fixed stream with no flowing producer; (3) workers
## short of slots. [] when nothing is stuck. `views.fort_names` feeds the mission sort.
static func bottleneck(views: Dictionary, vcfg: Dictionary, bview: Dictionary) -> Array:
	var hcfg: Dictionary = vcfg.get("hud", {})
	var fixes: Dictionary = vcfg.get("shortage_fix", {})
	var out: Array = []
	var seen := {}
	var needs := BuildSort.needs(views, views.get("fort_names", {}), vcfg, bview)
	for it in BuildSort.sort_rows(views.get("catalog", {}).get("buildings", []), needs, bview, vcfg):
		var row: Dictionary = it["row"]
		var reason := String(row.get("reason", ""))
		if bool(row.get("can_build", false)) or not reason in ["no_gold", "no_bone"]:
			continue
		var id := reason.trim_prefix("no_")
		var line := stuck_line(id, String(fixes.get(id, "")), views, hcfg, bview)
		if line != "":
			out.append(line)
			seen[id] = true
		break
	for id in ["gold", "bone"]:
		if seen.has(id):
			continue
		var line := stuck_line(id, String(fixes.get(id, "")), views, hcfg, bview)
		if line != "" and presence(views.get("town", {}), String(fixes.get(id, "")))["done"] == 0:
			out.append(line)
	var n := short_slots(views.get("town", {}))
	if n > 0:
		out.append(BuildSort.fmt(_t(hcfg, "short_slots"), {"n": n}))
	return out
