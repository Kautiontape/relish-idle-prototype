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


## Stocks the build checks read: {gold, bone, relics}.
static func stocks(views: Dictionary) -> Dictionary:
	var town: Dictionary = views.get("town", {})
	var count := {}
	var placeable := {}
	for r in views.get("catalog", {}).get("buildings", []):
		var bid := String(r.get("building_id", ""))
		count[bid] = int(r.get("count", 0))
		placeable[bid] = bool(r.get("can_build", false))
	return {"gold": float(town.get("gold", 0.0)), "bone": float(town.get("bone", 0.0)),
		"relics": float(views.get("hud", {}).get("relics", 0)), "count": count, "placeable": placeable,
		"next_tier": town.get("next_tier", {})}


# ------------------------------------------------------------------ needs ----
## The live needs, in `view.needs.order`: [{id, chip, serves: Array[String]}]. `fort_names` is
## {fort id: name} (view_realm), used for chips and to tell a fort from Covington or Vei.
static func needs(views: Dictionary, fort_names: Dictionary, vcfg: Dictionary) -> Array:
	var ncfg: Dictionary = vcfg.get("needs", {})
	var out: Array = []
	for id in ncfg.get("order", []):
		var chip := _chip(String(id), views, fort_names, ncfg)
		if chip != "":
			out.append({"id": String(id), "chip": chip, "serves": (ncfg.get("serves", {}) as Dictionary).get(id, [])})
	return out


static func _chip(id: String, views: Dictionary, names: Dictionary, ncfg: Dictionary) -> String:
	var chips: Dictionary = ncfg.get("chips", {})
	var town: Dictionary = views.get("town", {})
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


# ------------------------------------------------------------------- sort ----
static func is_gated(row: Dictionary, vcfg: Dictionary) -> bool:
	return not bool(row.get("can_build", false)) and String(row.get("reason", "")) in vcfg.get("gate_reasons", [])


## Catalog rows in display order: rows serving a live need first (each with its chip), then
## buildable, then unbuildable, gated (tier/blueprint/building) last, then catalog order.
## Returns [{row, idx, need: String, chip: String, cls: 0 buildable | 1 blocked | 2 gated}].
static func sort_rows(rows: Array, needs_in: Array, bview: Dictionary, vcfg: Dictionary) -> Array:
	var items: Array = []
	for i in rows.size():
		var row: Dictionary = rows[i]
		var serves: Array = bview.get(String(row.get("building_id", "")), {}).get("serves", [])
		var need_id := ""
		var chip := ""
		for n in needs_in:
			for s in n["serves"]:
				if s in serves:
					need_id = n["id"]
					chip = n["chip"]
					break
			if need_id != "":
				break
		var cls := 0
		if not bool(row.get("can_build", false)):
			cls = 2 if is_gated(row, vcfg) else 1
		items.append({"row": row, "idx": i, "need": need_id, "chip": chip, "cls": cls})
	items.sort_custom(func(a, b):
		var sa := 0 if a["need"] != "" else 1
		var sb := 0 if b["need"] != "" else 1
		if sa != sb:
			return sa < sb
		if a["cls"] != b["cls"]:
			return a["cls"] < b["cls"]
		return a["idx"] < b["idx"])
	return items


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
	vars["progress"] = ""
	var nt: Dictionary = st.get("next_tier", {})
	if reason == "needs_tier" and String(nt.get("tier", "")) == String(req.get("tier", "")) and int(nt.get("need", 0)) > 0:
		var miss: Array = []
		for m in nt.get("missing", []):
			miss.append(label_of(String(m), bview))
		vars["progress"] = fmt(String(tt.get("tier_progress", "")), {"have": int(nt.get("have", 0)),
			"need": int(nt.get("need", 0)), "missing": ", ".join(miss) if not miss.is_empty() else "none"})
	return fmt(String(rs[reason]), vars)


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
static func upgrade_cost(bdef: Dictionary, level: int) -> Dictionary:
	var lc: Array = bdef.get("level_costs", [])
	if level < 1 or level > lc.size() or level >= int(bdef.get("max_level", 1)):
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
	var max_level := int(bdef.get("max_level", 1))
	var state := String(entry.get("state", ""))
	var constructing := state == "constructing"
	var slots := int(entry.get("slots", 0))
	var up_cost := upgrade_cost(bdef, level)
	var up_reason := ""
	if constructing:
		up_reason = "under_construction"
	elif level >= max_level:
		up_reason = "max_level"
	else:
		up_reason = shortfall_reason(up_cost, st)
	var refund: Dictionary = {}
	if constructing:
		refund = upgrade_cost(bdef, level) if level >= 1 else bdef.get("cost", {})
	var tpl := String((vcfg.get("states", {}) as Dictionary).get(state, ""))
	var fm := String(entry.get("foreman", ""))
	var up: Dictionary = entry.get("upkeep", {})
	return {
		"building_id": bid, "label": label_of(bid, bview), "flavour": String(bview.get(bid, {}).get("flavour", "")),
		"level": level, "max_level": max_level, "state": state,
		"state_text": fmt(tpl, {"pct": int(round(float(entry.get("progress", 0.0)) * 100.0))}),
		"staffing": ("staffed %.1f of %d" % [float(entry.get("staffed", 0.0)), slots]) if slots > 0 else "no jobs here",
		"foreman": ("foreman " + fm) if fm != "" else "no foreman",
		"upkeep": {"gold": float(up.get("gold", 0.0)), "bone": float(up.get("bone", 0.0))},
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
			"max_level": int(bcfg.get(bid, {}).get("max_level", 1)), "state": String(b.get("state", ""))}
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
