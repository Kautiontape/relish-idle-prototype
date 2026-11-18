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


## The workforce the town keeps (the workers cell's "→ steady N"): the view's value when it carries
## one, else TownStandins.steady_kept (the stand-in).
static func kept(town: Dictionary, hud: Dictionary) -> float:
	return TownStandins.steady_kept(town, hud)


## The surplus streaming to WAR (/s): the live muster whenever it runs; else `muster_steady` (only if
## the view has it) when steady exceeds kept by more than the arrow's tolerance; 0 hides it.
static func surplus_rate(town: Dictionary, steady: float, kept_n: float, hcfg: Dictionary) -> float:
	var w: Dictionary = town.get("workers", {})
	var m := float(w.get("muster", 0.0))
	if m > 0.0:
		return m
	if steady - kept_n <= maxf(float(hcfg.get("tol_min", 0.5)), absf(steady) * float(hcfg.get("tol_frac", 0.02))):
		return 0.0
	return maxf(float(w.get("muster_steady", 0.0)), 0.0) if w.has("muster_steady") else 0.0


## Why the town keeps fewer workers than its raw steady state: "kept: 9 slots + 10 idle cap", from
## TownStandins.kept_inputs (api-request #12). "" when `kept_n` is not below `steady` by more than
## the arrow's tolerance, or when the view carries its own kept value.
static func kept_reason(town: Dictionary, hud: Dictionary, steady: float, kept_n: float, idle_cap: float, hcfg: Dictionary) -> String:
	var inputs := TownStandins.kept_inputs(town, hud, idle_cap)
	if inputs.is_empty():
		return ""
	if steady - kept_n <= maxf(float(hcfg.get("tol_min", 0.5)), absf(steady) * float(hcfg.get("tol_frac", 0.02))):
		return ""
	return BuildSort.fmt(_t(hcfg, "kept_reason"), inputs)


## The workers cell's idle line while idle hands are a need (BuildSort.idle_need), as parts
## [[text, oblique]], built from the same suggestion the Build tab shows (`tab` = BuildSort.tab_suggestion,
## computed here when not given): when the suggestion is a job building (new, or one more level of one), the
## line names it: "10 idle: build a Charnel House (+3 jobs) or let them muster" / "10 idle: upgrade the
## Market to L2 (+2 jobs) or let them muster". When it isn't (a save-for target, a building with no jobs), the
## first buildable job item of the same list (upgrades merged, the next tier's lots kept free) is named
## instead; one the relics held can't pay for (BuildSort.relic_blocked) is never named while a relic-free job
## item is buildable. A new build's gain is the catalog row's `projected` rates (api-request #9, oblique, "now") or
## else its job count; an upgrade's, the building's jobs per level. "10 idle: no job building affordable;
## mustering to FLOOD (Vei's queue)" (muster_to's name; or "waiting at the crypt" while nobody musters) only when no job build or upgrade can
## be paid for. [] when the idle hands are no need. `short` (the HUD cell, whose width clips the full line; the
## tooltip keeps it whole): the job count as the gain and hud.text's `_short` templates, with no "or let them muster".
static func idle_parts(views: Dictionary, vcfg: Dictionary, bview: Dictionary, bcfg: Dictionary, tab: Dictionary = {},
		short := false) -> Array:
	var hcfg: Dictionary = vcfg.get("hud", {})
	var need := BuildSort.idle_need(views, vcfg.get("needs", {}), bcfg)
	if need.is_empty():
		return []
	var n := roundi(float(need["idle"]))
	if tab.is_empty():
		tab = BuildSort.tab_suggestion(views, bview, bcfg, vcfg)
	var best: Dictionary = {}
	var sug: Dictionary = tab["sug"]
	var st: Dictionary = tab.get("stocks", {})
	var cands := BuildSort.candidates(tab["items"], tab["ups"], tab["reserved"])
	var sug_blocked := false  # the suggestion is the relic wall itself: it is not the line's building
	for it in cands:
		if String(it["row"].get("building_id", "")) == String(sug.get("building_id", "")) and bool(it.get("upgrade", false)) == bool(sug.get("upgrade", false)):
			sug_blocked = BuildSort.relic_blocked(it["row"], st)
			break
	if not sug.is_empty() and not bool(sug.get("save", false)) and not sug_blocked and BuildSort.job_slots(String(sug.get("building_id", "")), bcfg) > 0:
		best = {"row": {"building_id": sug["building_id"], "upgrade": bool(sug.get("upgrade", false)), "level": int(sug.get("level", 1))}}
		for it in tab["items"]:  # its catalog row, for `projected`
			if String(it["row"].get("building_id", "")) == String(sug["building_id"]) and not bool(sug.get("upgrade", false)):
				best["row"] = it["row"]
				break
	else:
		# the first buildable job item the relics pay for; only when there is none, a relic-blocked one (the wall)
		for free_only in [true, false]:
			for it in cands:
				var row: Dictionary = it["row"]
				if free_only and BuildSort.relic_blocked(row, st):
					continue
				if bool(row.get("can_build", false)) and not (row.get("lots", []) as Array).is_empty() and BuildSort.job_slots(String(row.get("building_id", "")), bcfg) > 0:
					best = it
					break
			if not best.is_empty():
				break
	if not best.is_empty():
		var row: Dictionary = best["row"]
		var bid := String(row.get("building_id", ""))
		var gain: Array = []
		if not short and not bool(row.get("upgrade", false)) and row.get("projected") is Dictionary:
			var rt := BuildSort.rate_texts(row["projected"], vcfg)
			if not rt.is_empty():
				gain = [[", ".join(rt), true]]
		if gain.is_empty():
			gain = [[BuildSort.fmt(_t(hcfg, "idle_jobs"), {"n": BuildSort.job_slots(bid, bcfg)}), false]]
		var key := "idle_upgrade" if bool(row.get("upgrade", false)) else "idle_build"
		if short and (hcfg.get("text", {}) as Dictionary).has(key + "_short"):
			key += "_short"
		return fill_parts(_t(hcfg, key),
			{"n": str(n), "label": BuildSort.label_of(bid, bview), "level": int(row.get("level", 0)), "gain": gain})
	var mustering := float(views.get("town", {}).get("workers", {}).get("muster", 0.0)) > 0.0
	var key := "idle_none" if mustering else "idle_none_wait"
	if short and mustering and (hcfg.get("text", {}) as Dictionary).has("idle_none_short"):
		key = "idle_none_short"  # the cell: muster_word ("idle → FLOOD") already stands before it
	return [[BuildSort.fmt(_t(hcfg, key), {"n": n, "to": muster_name(views, vcfg)}), false]]


## Where the idle muster goes now: view_hud.split.muster_to, else view_town.workers.muster_to ("flood", Vei's
## queue, or "war" while the Muster stance acts). "flood" when neither view says: it is the rule without the stance.
static func muster_to(views: Dictionary) -> String:
	var to := String(((views.get("hud", {}) as Dictionary).get("split", {}) as Dictionary).get("muster_to", ""))
	if to == "":
		to = String(((views.get("town", {}) as Dictionary).get("workers", {}) as Dictionary).get("muster_to", "flood"))
	return to


## The muster's destination as the valve names it, with where that is: "FLOOD (Vei's queue)" / "WAR (your forts)"
## (town.json view.muster_names).
static func muster_name(views: Dictionary, vcfg: Dictionary) -> String:
	var to := muster_to(views)
	return String((vcfg.get("muster_names", {}) as Dictionary).get(to, to.to_upper()))


## The workers cell's word after the muster rate, "idle → FLOOD", and its tooltip (hud.text muster_word / muster_tip).
static func muster_word(views: Dictionary, hcfg: Dictionary) -> String:
	var to := muster_to(views)
	return String(((hcfg.get("text", {}) as Dictionary).get("muster_word", {}) as Dictionary).get(to, "→ " + to.to_upper()))


static func muster_tip(views: Dictionary, hcfg: Dictionary) -> String:
	return String(((hcfg.get("text", {}) as Dictionary).get("muster_tip", {}) as Dictionary).get(muster_to(views), ""))


## `tpl` with each `{key}` replaced by vars[key]: a String (upright) or parts [[text, oblique]].
## Returns parts, neighbouring upright texts merged; an unknown key stays as written.
static func fill_parts(tpl: String, vars: Dictionary) -> Array:
	var out: Array = []
	var rest := tpl
	while true:
		var i := rest.find("{")
		var j := rest.find("}", i + 1) if i >= 0 else -1
		if i < 0 or j < 0:
			_push(out, rest, false)
			break
		var key := rest.substr(i + 1, j - i - 1)
		_push(out, rest.substr(0, i), false)
		if vars.has(key):
			var v: Variant = vars[key]
			if v is Array:
				for p in v:
					_push(out, String(p[0]), bool(p[1]))
			else:
				_push(out, str(v), false)
		else:
			_push(out, rest.substr(i, j - i + 1), false)
		rest = rest.substr(j + 1)
	return out


static func _push(out: Array, text: String, oblique: bool) -> void:
	if text == "":
		return
	if not out.is_empty() and bool(out[-1][1]) == oblique and not oblique:
		out[-1][0] = String(out[-1][0]) + text
	else:
		out.append([text, oblique])


## The parts joined into one string (tests, tooltips).
static func parts_text(parts: Array) -> String:
	var s := ""
	for p in parts:
		s += String(p[0])
	return s


## "+0.07/s" (the oblique part); the upright word after it is muster_word(), which names where it goes.
static func war_text(rate: float, hcfg: Dictionary) -> String:
	return net_text(rate, hcfg)


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


## The top-right line: today's next-tier line, except while the relics held can't pay for the next tier's
## missing gate buildings: "next: Town — needs 4 relics (have 3): raid a fort". N is those buildings' relic
## costs summed (BuildSort.relic_wall: view_catalog costs of what view_town().next_tier.missing still asks for,
## minus what stands or is being built), M the relics held (view_inventory().relics). {text, relics: bool (the
## wall is the line), need, have}.
static func next_line(views: Dictionary, hcfg: Dictionary, bview: Dictionary) -> Dictionary:
	var town: Dictionary = views.get("town", {})
	var next: Dictionary = town.get("next_tier", {})
	var wall := BuildSort.relic_wall(views) if String(next.get("tier", "")) != "" else {}
	if wall.is_empty():
		return {"text": next_tier_line(String(town.get("tier", "")), next, hcfg, bview), "relics": false, "need": 0, "have": 0}
	return {"text": BuildSort.fmt(_t(hcfg, "next_relics"), {"tier": String(next["tier"]).capitalize(), "n": wall["need"],
		"unit": _unit(int(wall["need"]), hcfg), "have": wall["have"]}), "relics": true, "need": wall["need"], "have": wall["have"]}


static func _unit(n: int, hcfg: Dictionary) -> String:
	return String((hcfg.get("relic_units", {}) as Dictionary).get("one" if n == 1 else "many", ""))


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
		var staffed := 0.0
		var cause := ""  # the producer's own reason (view_town buildings[].starved, STATE-API §5.9)
		for b in views.get("town", {}).get("buildings", []):
			if String(b.get("building_id", "")) == fix:
				staffed += float(b.get("staffed", 0.0))
				if String(b.get("starved", "")) != "":
					cause = String(b["starved"])
		if staffed > 0.0:  # it has hands but nothing to work on: the sim's cause when it gives one, else the input it lacks
			var sw: Dictionary = tx.get("starved_why", {})
			if sw.has(cause):
				return BuildSort.fmt(String(sw[cause]), vars)
			vars["input"] = String((hcfg.get("producer_input", {}) as Dictionary).get(fix, ""))
			return BuildSort.fmt(String(tx.get("starved", "")), vars)
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
	for b in town.get("buildings", []):  # a staff cap is not a shortage: only min(slots, cap) hands are wanted
		var cap := int(b.get("staff_cap", -1))
		if cap >= 0 and int(b.get("slots", 0)) > cap:
			short -= float(int(b.get("slots", 0)) - cap)
	return maxi(int(floor(short + 0.0001)), 0)


## What is stuck, one string per line item, most wanted first: (1) the first resource-short row of
## the mission-sorted catalog (gold or bone, its net rate in the dead band or negative, its
## `shortage_fix` producer named); (2) any other fixed stream with no flowing producer; (3) workers
## short of slots. [] when nothing is stuck. `views.fort_names` feeds the mission sort; `bcfg`
## (buildings.json) lets idle hands rank the job buildings.
static func bottleneck(views: Dictionary, vcfg: Dictionary, bview: Dictionary, bcfg: Dictionary = {}, tab: Dictionary = {}) -> Array:
	var hcfg: Dictionary = vcfg.get("hud", {})
	var fixes: Dictionary = vcfg.get("shortage_fix", {})
	var out: Array = []
	var seen := {}
	if tab.is_empty():
		tab = BuildSort.tab_suggestion(views, bview, bcfg, vcfg)
	for it in tab["items"]:
		var row: Dictionary = it["row"]
		var reason := String(row.get("reason", ""))
		if bool(row.get("can_build", false)) or not reason in ["no_gold", "no_bone"]:
			continue
		var id := reason.trim_prefix("no_")
		var line := stuck_line(id, String(fixes.get(id, "")), views, hcfg, bview)
		if line != "":  # an empty line (that stream flows) must not hide a second stuck one
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
