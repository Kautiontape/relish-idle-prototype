class_name BuildSort
extends RefCounted
## The Build tab's logic, pure (no autoloads, no Engine, no Nodes): live-need detection, the
## mission-aware catalog order, reason text, cost parts, the lot inspector's state, the queue's
## context and the store caps' fill. Tuning (thresholds, texts, serves-by-need) lives in
## configs/town.json `view`; per-building text in configs/buildings_view.json.
##   var needs := BuildSort.needs(views, fort_names, vcfg)
##   var order := BuildSort.sort_rows(catalog.buildings, needs, buildings_view, vcfg)


## "{a} of {b}" style templates: every `{key}` replaced from `vars`.
static func fmt(tpl: String, vars: Dictionary) -> String:
	var out := tpl
	for k in vars:
		out = out.replace("{%s}" % k, str(vars[k]))
	return out


## `hud.rates` entry for `id` ({} if absent).
static func hud_rate(hud: Dictionary, id: String) -> Dictionary:
	for r in hud.get("rates", []):
		if String(r.get("id", "")) == id:
			return r
	return {}


## Stocks the build checks read: {gold, bone, relics}, the net rates the time estimates divide by
## (`rates`: {gold, bone} from view_hud), each building's `max_level` from view_catalog, and the
## big undead's names by uid (a foreman is shown by name).
static func stocks(views: Dictionary) -> Dictionary:
	var town: Dictionary = views.get("town", {})
	var hud: Dictionary = views.get("hud", {})
	var count := {}
	var placeable := {}
	var max_level := {}
	for r in views.get("catalog", {}).get("buildings", []):
		var bid := String(r.get("building_id", ""))
		count[bid] = int(r.get("count", 0))
		placeable[bid] = bool(r.get("can_build", false))
		max_level[bid] = int(r.get("max_level", 1))
	var names := {}
	for u in views.get("big_undead", {}).get("big_undead", []):
		names[String(u.get("uid", ""))] = String(u.get("name", ""))
	return {"gold": float(town.get("gold", 0.0)), "bone": float(town.get("bone", 0.0)),
		"relics": float(hud.get("relics", 0)), "count": count, "placeable": placeable,
		"max_level": max_level, "foreman_names": names,
		"rates": {"gold": float(hud_rate(hud, "gold").get("rate", 0.0)), "bone": float(hud_rate(hud, "bone").get("rate", 0.0))},
		"next_tier": town.get("next_tier", {})}


# ------------------------------------------------------------------ needs ----
## The live needs, in `view.needs.order`: [{id, chip, serves: Array[String]}]. `fort_names` is
## {fort id: name} (view_realm), used for chips and to tell a fort from Covington or Vei. `bcfg`
## (buildings.json) names the buildings with job slots, which serve `idle_hands`.
static func needs(views: Dictionary, fort_names: Dictionary, vcfg: Dictionary, bview: Dictionary = {}, bcfg: Dictionary = {}) -> Array:
	var ncfg: Dictionary = vcfg.get("needs", {})
	var out: Array = []
	for id in ncfg.get("order", []):
		if String(id) == "idle_hands":
			var n := idle_need(views, ncfg, bcfg)
			if not n.is_empty():
				out.append(n)
			continue
		if String(id) == "tier":
			var nt: Dictionary = views.get("town", {}).get("next_tier", {})
			var placed := {}  # `missing` lists buildings under construction too: those are already asked for
			for pb in views.get("town", {}).get("buildings", []):
				placed[String(pb.get("building_id", ""))] = true
			for m in nt.get("missing", []):
				if placed.has(String(m)):
					continue
				out.append({"id": "tier", "chip": fmt(String((ncfg.get("chips", {}) as Dictionary).get("tier", "")),
					{"tier": String(nt.get("tier", "")).capitalize(), "label": label_of(String(m), bview)}), "serves": ["building:" + String(m)]})
			continue
		var chip := _chip(String(id), views, fort_names, ncfg, vcfg, bview)
		if chip != "":
			out.append({"id": String(id), "chip": chip, "serves": (ncfg.get("serves", {}) as Dictionary).get(id, [])})
	return out


## Unspent workers are a need: `workers.idle` at or over `needs.idle_hands_min`, or a muster running
## (idle beyond the cap leaving for WAR). Served by every building with job slots (buildings.json
## `jobs`). {id, chip, serves, idle}, or {} when the hands are spent.
static func idle_need(views: Dictionary, ncfg: Dictionary, bcfg: Dictionary) -> Dictionary:
	var w: Dictionary = views.get("town", {}).get("workers", {})
	var idle := float(w.get("idle", 0.0))
	if idle < float(ncfg.get("idle_hands_min", INF)) and float(w.get("muster", 0.0)) <= 0.0:
		return {}
	var serves: Array = []
	for bid in bcfg:
		if job_slots(String(bid), bcfg) > 0:
			serves.append("building:" + String(bid))
	return {"id": "idle_hands", "chip": fmt(String((ncfg.get("chips", {}) as Dictionary).get("idle_hands", "")), {"n": roundi(idle)}),
		"serves": serves, "idle": idle}


## The job slots a building offers at level 1 (the sum of its buildings.json `jobs`); 0 for none.
static func job_slots(bid: String, bcfg: Dictionary) -> int:
	var d: Variant = bcfg.get(bid)
	if not d is Dictionary:
		return 0
	var n := 0
	var jobs: Dictionary = (d as Dictionary).get("jobs", {})
	for j in jobs:
		n += int(jobs[j])
	return n


static func _chip(id: String, views: Dictionary, names: Dictionary, ncfg: Dictionary, vcfg: Dictionary = {}, bview: Dictionary = {}) -> String:
	var chips: Dictionary = ncfg.get("chips", {})
	var town: Dictionary = views.get("town", {})
	if id.begins_with("starved_"):
		return _starved_chip(id.trim_prefix("starved_"), views, ncfg, vcfg, bview)
	match id:
		"tithe":
			var tithe: Dictionary = views.get("vei", {}).get("tithe", {})
			if not (bool(tithe.get("warning", false)) or bool(tithe.get("wave_active", false))):
				return ""
			var target := String(tithe.get("target", ""))
			if target == "":
				return String(chips.get("tithe_unknown", ""))
			return fmt(String(chips.get("tithe", "")), {"fort": names.get(target, target)})
		"front":
			for f in views.get("vei", {}).get("fronts", []):
				var need := float(f.get("need", 0.0))
				if need > 0.0 and float(f.get("have", 0.0)) < need:
					return fmt(String(chips.get("front", "")), {"front": f.get("id", ""),
						"have": int(float(f.get("have", 0.0))), "need": int(need)})
			return ""
		"warden":
			var rel: Dictionary = views.get("relish", {})
			var travelling := String(rel.get("state", "")) == "travelling" or String(rel.get("target", "")) != ""
			var fort := String(rel.get("target", "")) if travelling else String(rel.get("at", ""))
			if not names.has(fort):
				return ""
			return fmt(String(chips.get("warden_to" if travelling else "warden_at", "")), {"fort": names[fort]})
		"gold":
			var g := hud_rate(views.get("hud", {}), "gold")
			return String(chips.get("gold", "")) if float(g.get("rate", 0.0)) < 0.0 else ""
		"bodies":
			var cap := float(town.get("bodies_cap", 0.0))
			if cap > 0.0 and float(town.get("bodies", 0.0)) < float(ncfg.get("bodies_frac", 0.0)) * cap:
				return fmt(String(chips.get("bodies", "")), {"have": int(float(town.get("bodies", 0.0))), "cap": int(cap)})
			return ""
		"housing":
			var lcap := float(town.get("living_cap", 0.0))
			return String(chips.get("housing", "")) if lcap > 0.0 and float(town.get("living", 0.0)) >= lcap else ""
		"morale":
			var m: Dictionary = town.get("morale", {})
			if m.has("value") and float(m["value"]) < float(ncfg.get("morale_below", 0.0)):
				return String(chips.get("morale", ""))
			return ""
	return ""


## A starved stream (`resource` = a `shortage_fix` key): its net rate is <= 0 and its producer is not
## built, or (the stock is under the cheapest catalog cost in it and) the producer has no staff. A
## producer still under construction is no need (it is already on its way). "" when not starved.
static func _starved_chip(resource: String, views: Dictionary, ncfg: Dictionary, vcfg: Dictionary, bview: Dictionary) -> String:
	var producer := String((vcfg.get("shortage_fix", {}) as Dictionary).get(resource, ""))
	var rate := hud_rate(views.get("hud", {}), resource)
	if producer == "" or rate.is_empty() or float(rate.get("rate", 0.0)) > 0.0:
		return ""
	var chips: Dictionary = ncfg.get("chips", {})
	var vars := {"resource": resource, "label": label_of(producer, bview)}
	var staffed := 0.0
	var present := false
	for b in views.get("town", {}).get("buildings", []):
		if String(b.get("building_id", "")) == producer:
			if String(b.get("state", "")) == "constructing":
				return ""
			present = true
			staffed += float(b.get("staffed", 0.0))
	if not present:
		return fmt(String(chips.get("starved_none", "")), vars)
	var cheapest := INF
	for r in views.get("catalog", {}).get("buildings", []):
		var c := float((r.get("cost", {}) as Dictionary).get(resource, 0.0))
		if c > 0.0:
			cheapest = minf(cheapest, c)
	if staffed <= 0.0 and float(views.get("town", {}).get(resource, 0.0)) < cheapest:
		return fmt(String(chips.get("starved_staff", "")), vars)
	return ""


# ------------------------------------------------------------------- sort ----
static func is_gated(row: Dictionary, vcfg: Dictionary) -> bool:
	return not bool(row.get("can_build", false)) and String(row.get("reason", "")) in vcfg.get("gate_reasons", [])


## Sort classes, in display order.
const CLS_NEED_BUILDABLE := 0  ## buildable and serving a live need
const CLS_BUILDABLE := 1
const CLS_NEED_SHORT := 2  ## serving a live need but short of funds (or lots)
const CLS_SHORT := 3  ## other blocked rows
const CLS_GATED := 4  ## tier, blueprint or building gate


## A unique building (buildings_view `unique`) that is already built is never offered again.
static func is_hidden(row: Dictionary, bview: Dictionary) -> bool:
	return bool(bview.get(String(row.get("building_id", "")), {}).get("unique", false)) and int(row.get("count", 0)) >= 1


## Catalog rows in display order: buildable rows serving a live need, then buildable, then rows
## serving a need but short of funds, then other blocked rows, gated (tier/blueprint/building)
## last; catalog order inside a class. Built unique buildings are left out.
## Returns [{row, idx, need: String, chip: String, cls: CLS_*}].
static func sort_rows(rows: Array, needs_in: Array, bview: Dictionary, vcfg: Dictionary) -> Array:
	var items: Array = []
	for i in rows.size():
		var row: Dictionary = rows[i]
		if is_hidden(row, bview):
			continue
		var serves: Array = (bview.get(String(row.get("building_id", "")), {}).get("serves", []) as Array).duplicate()
		serves.append("building:" + String(row.get("building_id", "")))
		var need_id := ""
		var chip := ""
		var rank := needs_in.size()  # no need: after every row that serves one
		for ni in needs_in.size():
			var n: Dictionary = needs_in[ni]
			for s in n["serves"]:
				if s in serves:
					need_id = n["id"]
					chip = n["chip"]
					rank = ni
					break
			if need_id != "":
				break
		var cls := CLS_BUILDABLE
		if is_gated(row, vcfg):
			cls = CLS_GATED
		elif not bool(row.get("can_build", false)):
			cls = CLS_NEED_SHORT if need_id != "" else CLS_SHORT
		elif need_id != "":
			cls = CLS_NEED_BUILDABLE
		items.append({"row": row, "idx": i, "need": need_id, "chip": chip, "cls": cls, "rank": rank})
	items.sort_custom(func(a, b):
		if a["cls"] != b["cls"]:
			return a["cls"] < b["cls"]
		if a["rank"] != b["rank"]:
			return a["rank"] < b["rank"]  # the more important need's row first, no-need rows last
		return a["idx"] < b["idx"])
	return items


## Sorted `items` that fit a lot of `lot_size` (the lot card's rows), order kept.
static func fitting(items: Array, lot_size: int) -> Array:
	return items.filter(func(it): return int(it["row"].get("lot_size", 1)) <= lot_size)


## The day-1 suggestion: the first buildable item with a free lot, as {building_id, label, lots};
## {} when nothing is buildable. With `st` (stocks(views)) and `vcfg` it saves for a needed build:
## when the top-ranked row serving a live need is blocked only by funds and the time to afford it
## (shortage / net rate) is within view.suggest_wait_s, the suggestion is that row, labelled "save for
## <Label> (~70 s)" with `save: true` and `eta_s`, instead of a lower-ranked buildable one. A stream
## that isn't flowing, or a longer wait, falls back to the plain rule.
static func suggest(items: Array, bview: Dictionary, st: Dictionary = {}, vcfg: Dictionary = {}) -> Dictionary:
	if not st.is_empty() and not vcfg.is_empty():
		var saving := _save_for(items, bview, st, vcfg)
		if not saving.is_empty():
			return saving
	var best: Dictionary = {}
	for it in items:
		var row: Dictionary = it["row"]
		if not (bool(row.get("can_build", false)) and not (row.get("lots", []) as Array).is_empty()):
			continue
		if String(it["need"]) != "":
			best = it  # a row serving a live need leads, as ever
			break
		if best.is_empty() or _variety_less(it, best, bview):
			best = it  # no need served: variety (see _variety_less)
	if not best.is_empty() and String(best["need"]) == "" and _third_amenity(best["row"], bview) and not st.is_empty() and not vcfg.is_empty():
		var vs := _variety_save(items, bview, st, vcfg)
		if not vs.is_empty():
			return vs
	if best.is_empty():
		return {}
	var brow: Dictionary = best["row"]
	var bid := String(brow.get("building_id", ""))
	return {"building_id": bid, "label": label_of(bid, bview), "lots": (brow["lots"] as Array).duplicate()}


const PRODUCES := ["gold", "bone", "bodies", "mint"]


## Fallback order among buildable rows serving no live need: fewest built first, then producers (a
## `serves` tag in PRODUCES) before amenities, then the cheaper, then catalog order.
static func _variety_less(a: Dictionary, b: Dictionary, bview: Dictionary) -> bool:
	var ka := _variety_key(a, bview)
	var kb := _variety_key(b, bview)
	for i in ka.size():
		if ka[i] != kb[i]:
			return ka[i] < kb[i]
	return false


static func _variety_key(it: Dictionary, bview: Dictionary) -> Array:
	var row: Dictionary = it["row"]
	var serves: Array = bview.get(String(row.get("building_id", "")), {}).get("serves", [])
	var producer := false
	for s in serves:
		producer = producer or s in PRODUCES
	var cost: Dictionary = row.get("cost", {})
	return [int(row.get("count", 0)), 0 if producer else 1, float(cost.get("gold", 0.0)) + float(cost.get("bone", 0.0)), int(it["idx"])]


static func _save_for(items: Array, bview: Dictionary, st: Dictionary, vcfg: Dictionary) -> Dictionary:
	var top: Dictionary = {}  # the row serving the most important live need
	for it in items:
		if String(it["need"]) != "" and (top.is_empty() or int(it["rank"]) < int(top["rank"])):
			top = it
	for it in [top] if not top.is_empty() else []:
		var row: Dictionary = it["row"]
		if bool(row.get("can_build", false)) or not String(row.get("reason", "")) in ["no_gold", "no_bone"] \
				or (row.get("lots", []) as Array).is_empty():
			return {}
		return _saving(row, bview, st, vcfg)
	return {}


## Time to afford `row` from the stocks and net rates, within view.suggest_wait_s: the suggestion
## {building_id, lots, save, eta_s, label}, or {} (a stream not flowing, relics short, or too long).
static func _saving(row: Dictionary, bview: Dictionary, st: Dictionary, vcfg: Dictionary) -> Dictionary:
	var cost: Dictionary = row.get("cost", {})
	if float(cost.get("relics", 0.0)) > float(st.get("relics", 0.0)):
		return {}
	var eta := 0.0
	for k in ["gold", "bone"]:
		var n := float(cost.get(k, 0.0)) - float(st.get(k, 0.0))
		if n <= 0.0:
			continue
		var rate := float((st.get("rates", {}) as Dictionary).get(k, 0.0))
		if rate <= 0.0:
			return {}
		eta = maxf(eta, n / rate)
	if eta > float(vcfg.get("suggest_wait_s", 0.0)):
		return {}
	var bid := String(row.get("building_id", ""))
	return {"building_id": bid, "lots": (row["lots"] as Array).duplicate(), "save": true, "eta_s": eta,
		"label": fmt(String(vcfg.get("suggest_save_text", "")), {"label": label_of(bid, bview), "eta": fmt_eta(eta, vcfg)})}


## True for a repeat (count >= 2) of a building that serves only morale or housing.
static func _third_amenity(row: Dictionary, bview: Dictionary) -> bool:
	if int(row.get("count", 0)) < 2:
		return false
	var serves: Array = bview.get(String(row.get("building_id", "")), {}).get("serves", [])
	for s in serves:
		if not s in ["morale", "housing"]:
			return false
	return true


## An unbuilt type blocked only by funds that is affordable within the wait ({} if none): the
## fallback saves for it instead of repeating an amenity.
static func _variety_save(items: Array, bview: Dictionary, st: Dictionary, vcfg: Dictionary) -> Dictionary:
	var cands: Array = items.filter(func(it): return int(it["row"].get("count", 0)) == 0 and String(it["need"]) == "" \
		and not bool(it["row"].get("can_build", false)) and String(it["row"].get("reason", "")) in ["no_gold", "no_bone"] \
		and not (it["row"].get("lots", []) as Array).is_empty())
	cands.sort_custom(func(a, b): return _variety_less(a, b, bview))
	for it in cands:
		var s := _saving(it["row"], bview, st, vcfg)
		if not s.is_empty():
			return s
	return {}


## The lot of `lots` nearest the crypt: smallest `hops[lot_id]` (street distance), the first listed
## on a tie or when unknown. "" for none.
static func nearest_lot(lots: Array, hops: Dictionary) -> String:
	var best := ""
	var best_h := INF
	for l in lots:
		var h := float(hops.get(String(l), INF))
		if best == "" or h < best_h:
			best = String(l)
			best_h = h
	return best


## The debug autoplayer's move (`--town-grow`): the top buildable row of the mission sort, the one
## `suggest` marks, on its suggested lot (`nearest_lot`). `cfgs` = {town, buildings_view, buildings,
## economy} (the configs the town view's model takes); `views` as the shell fetches them. Returns
## {building_id, lot_id}, or {} when nothing is buildable. Never offers a built unique building.
static func autoplay_pick(views: Dictionary, cfgs: Dictionary) -> Dictionary:
	var vcfg: Dictionary = cfgs.get("town", {}).get("view", {})
	var bview: Dictionary = cfgs.get("buildings_view", {})
	var rows: Array = views.get("catalog", {}).get("buildings", [])
	var items := sort_rows(rows, needs(views, views.get("fort_names", {}), vcfg, bview, cfgs.get("buildings", {})), bview, vcfg)
	var sug := suggest(items, bview, stocks(views), vcfg)
	if sug.is_empty() or bool(sug.get("save", false)):
		return {}
	var ref: Array = vcfg.get("ref_px", [1600, 900])
	var model := TownModel.new(cfgs.get("town", {}), bview, cfgs.get("buildings", {}), cfgs.get("economy", {}))
	model.update(views, Rect2(0, 0, float(ref[0]), float(ref[1])))
	var hops := {}
	for l in model.lots:
		hops[String(l["id"])] = l["hops"]
	var lot_id := nearest_lot(sug["lots"], hops)
	if lot_id == "":
		return {}
	return {"building_id": sug["building_id"], "lot_id": lot_id}


## A row can be queued: not gated and it has a lot to take.
static func can_queue(row: Dictionary, vcfg: Dictionary) -> bool:
	return not is_gated(row, vcfg) and not (row.get("lots", []) as Array).is_empty()


# ---------------------------------------------------------------- reasons ----
## Human text for a reason id (STATE-API 4.3 families). `row` is the catalog row (or any dict
## with `cost`, `requires`, `lot_size`, `building_id`); `st` is `stocks(views)`; `bview` gives
## building labels. Unknown ids get `reasons._unknown`, never the raw id.
static func reason_text(reason: String, row: Dictionary, st: Dictionary, bview: Dictionary, vcfg: Dictionary) -> String:
	var rs: Dictionary = vcfg.get("reasons", {})
	if not rs.has(reason) or reason.begins_with("_"):
		return String(rs.get("_unknown", ""))
	var req: Dictionary = row.get("requires", {})
	var cost: Dictionary = row.get("cost", {})
	var bp := String(req.get("blueprint", ""))
	var vars := {
		"tier": String(req.get("tier", "")).capitalize(),
		"label": label_of(bp if bp != "" else String(row.get("building_id", "")), bview),
		"building": label_of(String(req.get("building", "")), bview),
		"size": int(row.get("lot_size", 1)),
		"n": 0,
	}
	var key := reason.trim_prefix("no_")
	var tt: Dictionary = vcfg.get("shortage_text", {})
	if reason in ["no_gold", "no_bone", "no_relics"]:
		var n := maxi(int(ceil(float(cost.get(key, 0.0)) - float(st.get(key, 0.0)))), 0)
		vars["n"] = n
		vars["unit"] = String(tt.get("unit_relics_one" if n == 1 else "unit_relics", "relics")) if key == "relics" else key
		vars["fix"] = _fix_hint(key, st, bview, vcfg)
		if key != "relics" and st.has("rates") and n > 0:
			# With the live net rate: "needs 28 more bone, about 3 min at +0.15/s", or that it isn't flowing.
			var rate := float((st["rates"] as Dictionary).get(key, 0.0))
			if rate > 0.0:
				vars["eta"] = fmt_eta(float(n) / rate, vcfg)
				vars["rate"] = TownUI.fmt_rate(rate)
				return fmt(String(tt.get("eta", "")), vars)
			return fmt(String(tt.get("stuck", "")), vars)
	vars["progress"] = ""
	var nt: Dictionary = st.get("next_tier", {})
	if reason == "needs_tier" and String(nt.get("tier", "")) == String(req.get("tier", "")) and int(nt.get("need", 0)) > 0:
		var miss: Array = []
		for m in nt.get("missing", []):
			miss.append(label_of(String(m), bview))
		vars["progress"] = fmt(String(tt.get("tier_progress", "")), {"have": int(nt.get("have", 0)),
			"need": int(nt.get("need", 0)), "missing": ", ".join(miss) if not miss.is_empty() else "none"})
	return fmt(String(rs[reason]), vars)


## "3 min", "45 s", "1.5 h": the time estimate's duration (thresholds in view.shortage_text).
static func fmt_eta(seconds: float, vcfg: Dictionary) -> String:
	var tt: Dictionary = vcfg.get("shortage_text", {})
	if seconds < float(tt.get("eta_s_max_s", 0.0)):
		return fmt(String(tt.get("eta_s", "")), {"n": maxi(int(ceil(seconds)), 1)})
	if seconds < float(tt.get("eta_min_max_s", 0.0)):
		return fmt(String(tt.get("eta_min", "")), {"n": maxi(roundi(seconds / 60.0), 1)})
	return fmt(String(tt.get("eta_h", "")), {"n": ("%.1f" % (seconds / 3600.0)).trim_suffix(".0")})


static func _fix_hint(key: String, st: Dictionary, bview: Dictionary, vcfg: Dictionary) -> String:
	var tt: Dictionary = vcfg.get("shortage_text", {})
	var fix := String((vcfg.get("shortage_fix", {}) as Dictionary).get(key, ""))
	if fix == "":
		return String(tt.get(key, ""))
	var built := int((st.get("count", {}) as Dictionary).get(fix, 0)) > 0
	return fmt(String(tt.get("staff" if built else "build", "")), {"label": label_of(fix, bview)})


## The building a refusal's hint points at when it can be placed right now (so the hint can be a
## button that selects its row): the shortage's fix building while none is built, or the missing
## `requires.building`. "" otherwise.
static func fix_target(reason: String, row: Dictionary, st: Dictionary, vcfg: Dictionary) -> String:
	var cand := ""
	if reason in ["no_gold", "no_bone", "no_relics"]:
		cand = String((vcfg.get("shortage_fix", {}) as Dictionary).get(reason.trim_prefix("no_"), ""))
		if cand != "" and int((st.get("count", {}) as Dictionary).get(cand, 0)) > 0:
			return ""
	elif reason == "needs_building":
		cand = String(row.get("requires", {}).get("building", ""))
	if cand != "" and bool((st.get("placeable", {}) as Dictionary).get(cand, false)):
		return cand
	return ""


## "needs 2 relics: raid a fort" when the row's relic cost is over the relics held ("" otherwise).
static func relic_text(row: Dictionary, st: Dictionary, bview: Dictionary, vcfg: Dictionary) -> String:
	if float((row.get("cost", {}) as Dictionary).get("relics", 0.0)) <= float(st.get("relics", 0.0)) + 0.0001:
		return ""
	return reason_text("no_relics", row, st, bview, vcfg)


## A blocked row's refusal in words (reason_text), followed by its unmet relic cost when the reason
## names something else (funds, a lot), so the relic gate is always said; "" for a buildable row. A
## tier, blueprint or building gate is said alone.
static func row_reason(row: Dictionary, st: Dictionary, bview: Dictionary, vcfg: Dictionary) -> String:
	if bool(row.get("can_build", false)):
		return ""
	var reason := String(row.get("reason", ""))
	var why := reason_text(reason, row, st, bview, vcfg)
	var rel := relic_text(row, st, bview, vcfg)
	if rel != "" and reason != "no_relics" and reason != "unique" and not is_gated(row, vcfg):
		why += String((vcfg.get("shortage_text", {}) as Dictionary).get("also", "; ")) + rel
	return why


## What relics are holding back: the next tier's missing buildings (not yet placed) when their summed
## relic cost is over the relics held, and the tab's top need-serving row (the first of `items`, from
## sort_rows, that serves a need and isn't tier-gated) when its own relic cost is. {ids: Array[String], need: int (summed relic cost), have: int, text: String
## (view.relic_gate)}; {} when relics block neither.
static func relic_gate(views: Dictionary, items: Array, st: Dictionary, bview: Dictionary, vcfg: Dictionary) -> Dictionary:
	var cat := {}
	for r in views.get("catalog", {}).get("buildings", []):
		cat[String(r.get("building_id", ""))] = r
	var placed := {}
	for b in views.get("town", {}).get("buildings", []):
		placed[String(b.get("building_id", ""))] = true
	var have := int(st.get("relics", 0.0))
	var ids: Array = []
	var need := 0
	for m in views.get("town", {}).get("next_tier", {}).get("missing", []):
		var n := _relics(cat.get(String(m), {}))
		if not placed.has(String(m)) and n > 0 and not ids.has(String(m)):
			ids.append(String(m))
			need += n
	if need <= have:
		ids.clear()
		need = 0
	var top: Dictionary = {}  # the first row of the tab that serves a need and isn't tier-gated
	for it in items:
		if String(it["need"]) != "" and int(it.get("cls", CLS_BUILDABLE)) != CLS_GATED:
			top = it
			break
	if not top.is_empty():
		var tid := String(top["row"].get("building_id", ""))
		var tn := _relics(top["row"])
		if tn > have and not ids.has(tid):
			ids.append(tid)
			need += tn
	if ids.is_empty():
		return {}
	var rg: Dictionary = vcfg.get("relic_gate", {})
	var tt: Dictionary = vcfg.get("shortage_text", {})
	var labels: Array = ids.map(func(i): return label_of(String(i), bview))
	return {"ids": ids, "need": need, "have": have, "text": fmt(String(rg.get("text", "")), {
		"list": String(rg.get("join", " and ")).join(labels), "verb": String(rg.get("one" if ids.size() == 1 else "many", "")),
		"n": need, "unit": String(tt.get("unit_relics_one" if need == 1 else "unit_relics", "relics")), "have": have})}


static func _relics(row: Dictionary) -> int:
	return int((row.get("cost", {}) as Dictionary).get("relics", 0))


## Why a click on `lot` (a view_town lots entry, {} if unknown) can't take building `row`.
static func lot_refusal(lot: Dictionary, row: Dictionary) -> String:
	if lot.is_empty():
		return "unknown_lot"
	if not bool(lot.get("unlocked", false)):
		return "lot_locked"
	if String(lot.get("building_id", "")) != "":
		return "lot_taken"
	if int(lot.get("size", 1)) < int(row.get("lot_size", 1)):
		return "lot_too_small"
	return "lot_taken"


## The suggestion tag's dismiss hit box: at least 44 px square, starting at the x's cell and
## growing outward (right, and away from the lot: up when the tag sits `above` it, else down), so
## it covers the x and never the tag's text.
static func dismiss_box(cell: Rect2, plate: Rect2, above: bool) -> Rect2:
	var s := Vector2(maxf(44.0, cell.size.x), maxf(44.0, plate.size.y))
	return Rect2(Vector2(cell.position.x, plate.end.y - s.y if above else plate.position.y), s)


## How far dismiss_box reaches past the tag's right end, for an x cell `cell_w` wide.
static func dismiss_room(cell_w: float) -> float:
	return maxf(44.0 - cell_w, 0.0)


static func label_of(building_id: String, bview: Dictionary) -> String:
	return String(bview.get(building_id, {}).get("label", building_id.capitalize()))


## Cost as display parts [{text, short}] for gold, bone, relics. A part the stock can't cover
## starts with `!` (text marker, not colour only) and is flagged `short`.
static func cost_parts(cost: Dictionary, st: Dictionary) -> Array:
	var out: Array = []
	for k in ["gold", "bone", "relics"]:
		var need := float(cost.get(k, 0.0))
		var short := need > float(st.get(k, 0.0)) + 0.0001
		out.append({"text": "%s%d %s" % ["! " if short else "", int(ceil(need)), k], "short": short, "key": k})
	return out


## First unaffordable part of `cost` as its reason id ("" when affordable).
static func shortfall_reason(cost: Dictionary, st: Dictionary) -> String:
	for k in ["gold", "bone", "relics"]:
		if float(cost.get(k, 0.0)) > float(st.get(k, 0.0)) + 0.0001:
			return "no_" + k
	return ""


# ------------------------------------------------------------- inspector ----
## `buildings.json` level_costs entry for upgrading from `level` ({} at the top or level < 1).
static func upgrade_cost(bdef: Dictionary, level: int, max_level := -1) -> Dictionary:
	var lc: Array = bdef.get("level_costs", [])
	var top := max_level if max_level > 0 else int(bdef.get("max_level", 1))
	if level < 1 or level > lc.size() or level >= top:
		return {}
	return lc[level - 1]


## Everything the lot inspector shows for the built/constructing `entry` (a view_town buildings
## entry): {building_id, label, flavour, level, max_level, state, state_text, staffing, foreman,
## upkeep: {gold, bone}, upgrade: {visible, enabled, reason, cost, level, can_queue}, cancel:
## {visible, refund}, demolish_visible}. `bcfg` = buildings.json, `bview` = buildings_view.json.
static func inspect(entry: Dictionary, st: Dictionary, bcfg: Dictionary, bview: Dictionary, vcfg: Dictionary) -> Dictionary:
	var bid := String(entry.get("building_id", ""))
	var bdef: Dictionary = bcfg.get(bid, {})
	var level := int(entry.get("level", 0))
	var max_level := int((st.get("max_level", {}) as Dictionary).get(bid, bdef.get("max_level", 1)))  # view_catalog's, buildings.json only as a fallback
	var state := String(entry.get("state", ""))
	var constructing := state == "constructing"
	var slots := int(entry.get("slots", 0))
	var up_cost := upgrade_cost(bdef, level, max_level)
	var up_reason := ""
	if constructing:
		up_reason = "under_construction"
	elif state == "unpaid":
		up_reason = "unpaid"
	elif level >= max_level:
		up_reason = "max_level"
	else:
		up_reason = shortfall_reason(up_cost, st)
	var refund: Dictionary = {}
	if constructing:
		refund = upgrade_cost(bdef, level, max_level) if level >= 1 else bdef.get("cost", {})
	var tpl := String((vcfg.get("states", {}) as Dictionary).get(state, ""))
	var fm := String((st.get("foreman_names", {}) as Dictionary).get(String(entry.get("foreman", "")), entry.get("foreman", "")))
	var up: Dictionary = entry.get("upkeep", {})
	return {
		"building_id": bid, "label": label_of(bid, bview), "flavour": String(bview.get(bid, {}).get("flavour", "")),
		"level": level, "max_level": max_level, "state": state,
		"state_text": fmt(tpl, {"pct": int(round(float(entry.get("progress", 0.0)) * 100.0))}),
		"staffing": ("staffed %.1f of %d" % [float(entry.get("staffed", 0.0)), slots]) if slots > 0 else "no jobs here",
		"foreman": ("foreman " + fm) if fm != "" else "no foreman",
		"upkeep": {"gold": float(up.get("gold", 0.0)), "bone": float(up.get("bone", 0.0))},
		"upgrade_projected": entry.get("upgrade_projected", {}),  # TODO(api-request #9): view_town buildings[i].upgrade_projected
		"upgrade": {
			"visible": max_level > 1, "enabled": up_reason == "", "reason": up_reason,
			"cost": up_cost, "level": level + 1, "can_queue": not constructing and level >= 1 and level < max_level,
		},
		"cancel": {"visible": constructing, "refund": refund},
		"demolish_visible": not bid in vcfg.get("protected", []),
	}


# ----------------------------------------------------------------- queue ----
## What the stand-in queue evaluates against, from the fetched views: stocks, store caps (-1 =
## none), the catalog by building id, and the built lots with their max level.
static func queue_context(views: Dictionary, bcfg: Dictionary, vcfg: Dictionary) -> Dictionary:
	var st := stocks(views)
	var hud: Dictionary = views.get("hud", {})
	var catalog := {}
	for r in views.get("catalog", {}).get("buildings", []):
		catalog[String(r.get("building_id", ""))] = r
	var built := {}
	for b in views.get("town", {}).get("buildings", []):
		var bid := String(b.get("building_id", ""))
		built[String(b.get("lot_id", ""))] = {"building_id": bid, "level": int(b.get("level", 0)),
			"max_level": int(catalog.get(bid, {}).get("max_level", bcfg.get(bid, {}).get("max_level", 1))), "state": String(b.get("state", ""))}
	return {"gold": st["gold"], "bone": st["bone"], "relics": st["relics"],
		"gold_cap": float(hud_rate(hud, "gold").get("cap", -1.0)), "bone_cap": float(hud_rate(hud, "bone").get("cap", -1.0)),
		"catalog": catalog, "built": built, "gates": vcfg.get("gate_reasons", [])}


## Store fill 0..1 for a stock against its cap; -1.0 when uncapped (cap < 0). A zero cap is full.
static func fill(stock: float, cap: float) -> float:
	if cap < 0.0:
		return -1.0
	if cap == 0.0:
		return 1.0
	return clampf(stock / cap, 0.0, 1.0)


# --------------------------------------------------------------- benefit ----
## "+0.30/s gold now" lines for a `projected` dict ({rate_id: float}: the immediate rate change at
## today's state; api-request #9), zero changes left out.
static func rate_texts(projected: Dictionary, vcfg: Dictionary) -> Array:
	var out: Array = []
	var now := String((vcfg.get("benefit", {}) as Dictionary).get("now", "now"))
	for id in projected:
		if absf(float(projected[id])) > 0.00001:
			out.append("%s %s %s" % [TownUI.fmt_rate(float(projected[id])), id, now])
	return out


## What a building brings, for the lot card: {rates: Array[String] (signed, oblique), plain:
## Array[String] (upright), now: bool}. A stand-in rate of a building with job slots is labelled
## `benefit.standin` ("at full staffing": the effect, not today's staffing); `projected` rates "now".
## TODO(api-request #9): while a catalog row has no `projected` ({rate_id: float}, the immediate
## rate change), the rates are the `buildings.json` effects stand-in (attract only since E2a: a pit's
## mint and burn are no longer effects keys, so a pit reads "+1 raising pit"; no "now" label) and plain text is the cap/slot effects, the jobs, or the buildings_view `benefit` line.
## Once `projected` is present its rates (labelled "now") replace the stand-in rates, and the cap and
## lifetime effects stay as plain text beside them.
static func benefit(bid: String, row: Dictionary, bcfg: Dictionary, bview: Dictionary, vcfg: Dictionary) -> Dictionary:
	var bc: Dictionary = vcfg.get("benefit", {})
	var def: Dictionary = bcfg.get(bid, {})
	var eff: Dictionary = def.get("effects", {})
	var rate_fx: Dictionary = bc.get("rate_effects", {})
	var rates: Array = []
	var plain: Array = []
	var now: bool = row.get("projected") is Dictionary
	if now:
		rates = rate_texts(row["projected"], vcfg)
	else:
		for k in rate_fx:
			if eff.has(k) and absf(float(eff[k])) > 0.00001:
				var txt := "%s %s" % [TownUI.fmt_rate(float(eff[k]) * float(rate_fx[k].get("sign", 1.0))), rate_fx[k].get("unit", k)]
				if job_slots(bid, bcfg) > 0:
					txt += " " + String(bc.get("standin", ""))
				rates.append(txt.strip_edges())
	for k in eff:
		if not rate_fx.has(k) and (bc.get("plain_effects", {}) as Dictionary).has(k):
			plain.append(fmt(String(bc["plain_effects"][k]), {"n": _num(float(eff[k]))}))
	for j in def.get("jobs", {}):
		plain.append(fmt(String(bc.get("job_text", "")), {"n": int(def["jobs"][j]), "job": j}))
	if rates.is_empty() and plain.is_empty():
		var fallback := String(bview.get(bid, {}).get("benefit", ""))
		if fallback != "":
			plain.append(fallback)
	return {"rates": rates, "plain": plain, "now": now}


static func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else "%.2f" % x


# ----------------------------------------------------------------- ghosts ----
## The reason text of a queue entry (a shortage with its time estimate, a gate with its
## requirement), using the catalog row for the building's requirements. A head saving for its cost
## names the store that holds it longest (one that isn't flowing first, else the longest shortage /
## net rate), so its estimate matches the queue's ETA line, whichever store the queue recorded.
static func entry_reason(e: Dictionary, catalog: Dictionary, st: Dictionary, bview: Dictionary, vcfg: Dictionary) -> String:
	if String(e.get("reason", "")) == "":
		return ""
	var row: Dictionary = (catalog.get(String(e.get("building_id", "")), {}) as Dictionary).duplicate()
	row["cost"] = e.get("cost", {})
	row["building_id"] = e.get("building_id", "")
	var reason := String(e["reason"])
	if String(e.get("status", "")) == "waiting_funds" and st.has("rates"):
		var slowest := -1.0
		for k in ["gold", "bone"]:
			var short := float((row["cost"] as Dictionary).get(k, 0.0)) - float(st.get(k, 0.0))
			if short <= 0.0001:
				continue
			var rate := float((st["rates"] as Dictionary).get(k, 0.0))
			if rate <= 0.0:
				reason = "no_" + k
				break
			if short / rate > slowest:
				slowest = short / rate
				reason = "no_" + k
	return reason_text(reason, row, st, bview, vcfg)


## The queue as canvas ghosts, same entries and numbers as the panel: [{lot_id, number (1-based),
## building_id, upgrade, level, status, shape: "ring" (next) | "hold" (waiting_funds, "||") | "struck"
## (skipped_gate) | "plain" (queued), text: the shortage or gate text (shown on hover)}].
static func ghosts(entries: Array, catalog: Dictionary, st: Dictionary, bview: Dictionary, vcfg: Dictionary) -> Array:
	var shapes := {"next": "ring", "waiting_funds": "hold", "skipped_gate": "struck", "queued": "plain"}
	var out: Array = []
	for i in entries.size():
		var e: Dictionary = entries[i]
		out.append({
			"lot_id": String(e.get("lot_id", "")), "number": i + 1, "building_id": String(e.get("building_id", "")),
			"upgrade": bool(e.get("upgrade", false)), "level": int(e.get("level", 1)), "status": String(e.get("status", "queued")),
			"shape": String(shapes.get(String(e.get("status", "queued")), "plain")),
			"text": entry_reason(e, catalog, st, bview, vcfg),
		})
	return out


# ------------------------------------------------------------------- ETAs ----
## The work a queue entry still needs: the catalog's `build_work` × the level it builds (MECHANICS §4,
## the build job: construction is `build_work · target level`), less what is done when its lot is
## already constructing that building.
static func entry_work(e: Dictionary, catalog: Dictionary, town: Dictionary) -> float:
	var bid := String(e.get("building_id", ""))
	var work := float((catalog.get(bid, {}) as Dictionary).get("build_work", 0.0)) * maxi(int(e.get("level", 1)), 1)
	for b in town.get("buildings", []):
		if String(b.get("lot_id", "")) == String(e.get("lot_id", "")) and String(b.get("building_id", "")) == bid \
				and String(b.get("state", "")) == "constructing":
			return work * clampf(1.0 - float(b.get("progress", 0.0)), 0.0, 1.0)
	return work


## Each queue entry's ETA text, in order (texts in view.queue_text). The start: "starts now" for the
## head that can be paid for; "starts in ~4 min" for a head saving for its cost (shortage / net rate,
## st.rates); "starts in ≈ 7 min" for a later entry, from the costs of every unskipped entry up to it;
## "won't start: gold isn't flowing" when a short store's net rate is <= 0. Then the build: "then done
## in ~2 min" from the measured `throughput` (work/s, Throughput; < 0 or 0 = unknown) or "build time:
## 90 work". A gate-skipped entry gets "" (it says why instead).
static func queue_etas(entries: Array, st: Dictionary, catalog: Dictionary, town: Dictionary, throughput: float, vcfg: Dictionary) -> Array:
	var qt: Dictionary = vcfg.get("queue_text", {})
	var rates: Dictionary = st.get("rates", {})
	var acc := {"gold": 0.0, "bone": 0.0}
	var out: Array = []
	for e in entries:
		var status := String(e.get("status", "queued"))
		if status == "skipped_gate":
			out.append("")
			continue
		var cost: Dictionary = e.get("cost", {})
		for k in acc:
			acc[k] = float(acc[k]) + float(cost.get(k, 0.0))
		var start := String(qt.get("eta_now", ""))
		if status != "next":
			var wait := 0.0
			var stuck := ""
			for k in ["gold", "bone"]:
				var short := float(acc[k]) - float(st.get(k, 0.0))
				if short <= 0.0001:
					continue
				var rate := float(rates.get(k, 0.0))
				if rate <= 0.0:
					stuck = k
					break
				wait = maxf(wait, short / rate)
			if stuck != "":
				out.append(fmt(String(qt.get("eta_stuck", "")), {"resource": stuck}))
				continue
			if status == "waiting_funds":
				start = fmt(String(qt.get("eta_head", "")), {"t": fmt_eta(wait, vcfg)})
			elif wait <= 0.0:
				start = String(qt.get("eta_later_now", ""))
			else:
				start = fmt(String(qt.get("eta_later", "")), {"t": fmt_eta(wait, vcfg)})
		var work := entry_work(e, catalog, town)
		var build := fmt(String(qt.get("eta_build", "")), {"t": fmt_eta(work / throughput, vcfg)}) if throughput > 0.0 \
			else fmt(String(qt.get("eta_work", "")), {"work": int(ceil(work))})
		out.append(start + String(qt.get("eta_sep", " · ")) + build)
	return out


## The live build throughput, measured from the views (not a sim formula): on each observe(), every
## lot constructing the same building at the same level as last time adds Δprogress × its work
## (build_work × target level) over Δt of view_hud.t (sim seconds); smoothed over `smooth_s`. `rate`
## is work/s, -1 until measured and again once nothing is constructing. A site's first sighting, a
## finished site and a Δt <= 0 add nothing.
class Throughput:
	extends RefCounted
	var rate := -1.0
	var smooth_s := 10.0
	var _last := {}  # lot_id -> {building_id, level, progress}
	var _t := -1.0

	func _init(smooth_s_ := 10.0) -> void:
		smooth_s = maxf(smooth_s_, 0.001)

	func observe(views: Dictionary) -> void:
		var t := float(views.get("hud", {}).get("t", -1.0))
		var work := {}
		for r in views.get("catalog", {}).get("buildings", []):
			work[String(r.get("building_id", ""))] = float(r.get("build_work", 0.0))
		var now := {}
		var done := 0.0
		var seen := false
		for b in views.get("town", {}).get("buildings", []):
			if String(b.get("state", "")) != "constructing":
				continue
			var lot := String(b.get("lot_id", ""))
			var e := {"building_id": String(b.get("building_id", "")), "level": int(b.get("level", 0)), "progress": float(b.get("progress", 0.0))}
			now[lot] = e
			var was: Dictionary = _last.get(lot, {})
			if not was.is_empty() and was["building_id"] == e["building_id"] and was["level"] == e["level"] and e["progress"] >= was["progress"]:
				done += (e["progress"] - was["progress"]) * float(work.get(e["building_id"], 0.0)) * float(e["level"] + 1)
				seen = true
		var dt := t - _t
		if now.is_empty():
			rate = -1.0
		elif seen and _t >= 0.0 and dt > 0.0:
			var inst := done / dt
			rate = inst if rate < 0.0 else rate + (inst - rate) * (1.0 - exp(-dt / smooth_s))
		if dt != 0.0 or _t < 0.0:
			_last = now
			_t = t
