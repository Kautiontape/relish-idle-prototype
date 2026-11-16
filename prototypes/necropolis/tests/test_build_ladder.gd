extends RefCounted
## Every building level's price fits a cap the player can reach (BALANCE §5 "Nothing stuck" and §7; the run's
## manager's config check, T7). Every building in buildings.json, at every level 1..max_level (level 1 is
## `cost`, level L `level_costs[L − 2]`: BuildRules.construction_cost), for each store (gold, bone, relics) it
## prices above 0:
## - (a) Coverable: from a new game with no cap building built (the start Market demolished), the store's cap
##   building (BuildRules.cap_building) has a level whose cap covers the price: BuildRules.cap_level ≠ −1, the
##   level cmd_queue_build's cost_exceeds_cap names. Relics: the relic cap with every building that raises it
##   (a `relic_cap` effect) at its max level.
## - (b) Reachable no later than the building's own tier (`requires.tier`: an upgrade needs only that tier,
##   BuildRules.upgrade, so it is the tier that unlocks every level): the climb. Tiers in economy.json
##   town.tiers order; from the base caps with no cap building built, every cap building (gold's, bone's and
##   relics') whose tier is at or under the tier, and whose next level's whole cost (gold, bone and relics)
##   fits the caps now, is built or upgraded, in buildings.json order, one level each per pass, until a pass
##   changes nothing. Caps only grow, so where it ends doesn't depend on the order (only the printed sequence
##   does). The price must fit the caps reached by its tier. This catches a ladder whose next level outgrows
##   the cap it gives, and a cap building bought with a store whose cap another must raise first (the Market,
##   bought with bone, needs the mill's levels). Relic costs also need relic income, which isn't this test's
##   business: only the relic cap is checked.
## The caps are the game's own (TownSim gold_cap(), bone_cap(), GameState._cap_of("relics")) with the cap
## buildings placed at their levels, so a per-level Array effect reads as the game reads it. Also: every Array
## effect has one entry per level (TownSim holds its last entry past the end, so a short one plateaus unseen).
## Printed: the climb, each tier's buys in order and the caps it reaches; each check's PASS line carries the
## level (cap_level) of the cap building each price needs, "base" where the base cap covers it. Headless, no
## autoloads. Economy's suite.

const STORES := ["gold", "bone", "relics"]

var t: TestUtil


func run() -> int:
	t = TestUtil.new()
	t.suite("build_ladder")
	check(TestUtil.configs())
	return t.failures


## A new game with every cap building on its lots demolished: the base caps.
static func bare(cfgs: Dictionary) -> GameState:
	var s := GameState.new(cfgs)
	s.cmd_new_game(1)
	s.debug_enabled = true
	var cbs := cap_buildings(s)
	for lot_id in s.town_sim.buildings.keys():
		if cbs.has(s.town_sim.buildings[lot_id]["building_id"]):
			s.town_sim.demolish(lot_id)
	return s


## The cap buildings (BuildRules.cap_building of gold, bone and relics), in buildings.json order.
static func cap_buildings(s: GameState) -> Array:
	var ids := STORES.map(func(st): return BuildRules.cap_building(s, st))
	var out: Array = []
	for bid in BuildRules.buildings_cfg(s):
		if ids.has(bid) and not out.has(bid):
			out.append(str(bid))
	return out


static func caps(s: GameState) -> Dictionary:
	return {"gold": s.town_sim.gold_cap(), "bone": s.town_sim.bone_cap(), "relics": float(s._cap_of("relics"))}


static func fits(cost: Dictionary, c: Dictionary) -> bool:
	for st in STORES:
		if float(cost[st]) > float(c[st]):
			return false
	return true


## The first lot, any tier's, that is free, not in `taken` and fits `bid`'s size: the climb places its cap
## buildings there (TownSim.place_building checks neither).
static func free_lot(s: GameState, bid: String, taken: Array) -> String:
	var size := int(BuildRules.buildings_cfg(s).get(bid, {}).get("lot_size", 1))
	for l in BuildRules.lots_cfg(s):
		var id := str(l.get("id", ""))
		if not s.town_sim.buildings.has(id) and not taken.has(id) and int(l.get("size", 1)) >= size:
			return id
	return ""


## The climb (the header) on `s` (bare()): {tier: {caps, levels: {cap building: level}, bought: ["market L1",
## ...], the tier's own buys in order}} for each tier in economy.json town.tiers order.
static func climb(s: GameState) -> Dictionary:
	var tiers: Array = (s._sec("economy", "town").get("tiers", {}) as Dictionary).keys()
	var cfg := BuildRules.buildings_cfg(s)
	var order := cap_buildings(s)
	var level := {}
	var lot := {}
	var taken: Array = []
	for bid in order:
		level[bid] = 0
		lot[bid] = free_lot(s, bid, taken)
		taken.append(lot[bid])
	var out := {}
	for ti in tiers.size():
		var bought: Array = []
		var changed := true
		while changed:
			changed = false
			for bid in order:
				var lv: int = level[bid]
				if lv >= int(cfg[bid]["max_level"]) or tiers.find(BuildRules.req_of(s, bid)["tier"]) > ti:
					continue
				if fits(BuildRules.construction_cost(s, bid, lv + 1), caps(s)):
					level[bid] = lv + 1
					s.town_sim.place_building(lot[bid], bid, lv + 1)
					bought.append("%s L%d" % [bid, lv + 1])
					changed = true
		out[tiers[ti]] = {"caps": caps(s), "levels": level.duplicate(), "bought": bought}
	return out


## The caps with each store's cap building at its max level, and for relics every relic_cap building at its
## max level (a)'s relic cap.
static func top_caps(cfgs: Dictionary) -> Dictionary:
	var s := bare(cfgs)
	var cfg := BuildRules.buildings_cfg(s)
	var put: Array = []
	for st in ["gold", "bone"]:
		put.append(BuildRules.cap_building(s, st))
	for bid in cfg:
		var fx: Variant = cfg[bid].get("effects", {})
		if fx is Dictionary and (fx as Dictionary).has("relic_cap") and not put.has(bid):
			put.append(str(bid))
	var taken: Array = []
	for bid in put:
		if bid == "":
			continue
		var l := free_lot(s, bid, taken)
		taken.append(l)
		s.town_sim.place_building(l, bid, int(cfg[bid]["max_level"]))
	return caps(s)


static func _n(x: float) -> String:
	return "%d" % int(x) if x == floorf(x) else "%.2f" % x


func check(cfgs: Dictionary) -> void:
	var s := bare(cfgs)
	var eco: Dictionary = cfgs["economy"]
	var base := caps(s)
	t.ok(base["gold"] == float(eco["gold"]["cap"]) and base["bone"] == float(eco["bone"]["cap"])
		and base["relics"] == float(eco["relics"]["cap"]), "(setup) a new game with no cap building has the base caps: %s" % str(base))
	var tiers: Array = (eco["town"]["tiers"] as Dictionary).keys()
	t.ok(tiers == GameState.TIERS, "(setup) economy.json town.tiers lists GameState's tiers in order: %s" % str(tiers))
	var top := top_caps(cfgs)
	var cl := climb(bare(cfgs))
	print("  [build_ladder] the climb (the cap buildings %s, from the base caps %s; buildings.json order, one level each per pass, to a fixed point):" % [
		str(cap_buildings(s)), str(base)])
	for tier in cl:
		var c: Dictionary = cl[tier]
		var lv: Array = []
		for bid in c["levels"]:
			lv.append("%s L%d" % [bid, int(c["levels"][bid])])
		print("  [build_ladder]   %s: %s -> caps gold %s, bone %s, relics %s (%s)" % [tier,
			"nothing more" if (c["bought"] as Array).is_empty() else ", ".join(PackedStringArray(c["bought"])),
			_n(c["caps"]["gold"]), _n(c["caps"]["bone"]), _n(c["caps"]["relics"]), ", ".join(PackedStringArray(lv))])
	var cfg := BuildRules.buildings_cfg(s)
	for bid in cfg:
		var tier: String = BuildRules.req_of(s, bid)["tier"]
		var reach: Dictionary = cl.get(tier, {}).get("caps", base)
		for lv in range(1, int(cfg[bid]["max_level"]) + 1):
			var cost := BuildRules.construction_cost(s, bid, lv)
			var need: Array = []
			var miss_a: Array = []
			var miss_b: Array = []
			var priced: Array = []
			for st in STORES:
				var price := float(cost[st])
				if price <= 0.0:
					continue
				priced.append("%s %s" % [_n(price), st])
				if st == "relics":
					if price > float(top["relics"]):
						miss_a.append("relics %s over the relic cap %s with every relic-cap building at its max level" % [_n(price), _n(top["relics"])])
					else:
						need.append("relics %s: under %s" % [_n(price), _n(top["relics"])])
				else:
					var cb := BuildRules.cap_building(s, st)
					var at := BuildRules.cap_level(s, st, price)
					if at == -1:
						miss_a.append("%s %s: no level of %s covers it (%s at its max level)" % [st, _n(price), cb, _n(top[st])])
					else:
						need.append("%s %s: %s" % [st, _n(price), "base" if price <= float(base[st]) else "%s L%d" % [cb, at]])
				if price > float(reach[st]):
					miss_b.append("%s %s over the %s cap %s the climb reaches by %s" % [st, _n(price), st, _n(reach[st]), tier])
			if priced.is_empty():
				continue
			t.ok(miss_a.is_empty(), "(a) %s L%d (%s): %s" % [bid, lv, ", ".join(PackedStringArray(priced)),
				", ".join(PackedStringArray(need)) if miss_a.is_empty() else "; ".join(PackedStringArray(miss_a))])
			t.ok(miss_b.is_empty(), "(b) %s L%d (%s), tier %s: %s" % [bid, lv, ", ".join(PackedStringArray(priced)), tier,
				"fits the caps reached by %s (gold %s, bone %s, relics %s)" % [tier, _n(reach["gold"]), _n(reach["bone"]), _n(reach["relics"])]
				if miss_b.is_empty() else "; ".join(PackedStringArray(miss_b))])
	var short: Array = []
	for bid in cfg:
		var fx: Dictionary = cfg[bid].get("effects", {})
		for k in fx:
			if fx[k] is Array and (fx[k] as Array).size() != int(cfg[bid]["max_level"]):
				short.append("%s.%s has %d for max_level %d" % [bid, k, (fx[k] as Array).size(), int(cfg[bid]["max_level"])])
	t.ok(short.is_empty(), "every Array effect has one entry per level%s" % ("" if short.is_empty() else ": " + ", ".join(PackedStringArray(short))))
