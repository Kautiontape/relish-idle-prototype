extends RefCounted
## E4 step 4, the gold trap (BALANCE §6; reports/economy/e4-notes.md "Step 4 diagnosis"). A town whose full gold upkeep
## is over its income sheds buildings when the gold runs out (MECHANICS §4.3 Upkeep). The resume rule then re-admits
## each one the moment the gold covers one hold of the paying upkeep plus its own, so any surplus is spent re-admitting
## the next, and the gold pins at about (paying upkeep + the last one's) × unpaid_hold_s and never climbs: no entry
## costing more can ever start, the Market level that would pay for it among them. pre_vei past its gold floor is that
## state (a City on one Market: the stalls' 0.60 g/s against 1.07 of upkeep, MECHANICS §4.3 "the gold then sits at 18").
## From there, with the queue empty so nothing spends it, the gold must climb past the gold lever, the Market's next
## level's gold cost, within one night away (12 h).
## tests/run.sh --only=gold_trap

var t := TestUtil.new()
var _dir := "user://test_gold_trap_%d" % OS.get_process_id()
const CLOCK := 1_800_000_000  # a "now" for the saves (unix seconds)


func run() -> int:
	t.suite("gold_trap")
	DirAccess.make_dir_recursive_absolute(_dir)
	var c := TestUtil.configs()
	var s := _mk(c)
	t.ok(s.cmd_debug_load_fixture("pre_vei")["ok"], "(setup) pre_vei loads")
	s.build_queue.clear()
	s.tick(0.5)
	var n := _away(c, s, "trap_a", 3 * 3600)
	var unpaid := _unpaid(n)
	var g0 := n.town_sim.gold
	t.ok(not unpaid.is_empty(), "(setup) 3 h away, past pre_vei's floor: %d buildings unpaid (%s), gold %.2f, income %.3f g/s" % [
		unpaid.size(), ", ".join(PackedStringArray(unpaid)), g0, n.town_sim.gold_income()])
	var mk := ""
	var lv := 0
	for lot_id in n.town_sim.buildings:
		var b: Dictionary = n.town_sim.buildings[lot_id]
		if str(b["building_id"]) == "market" and int(b["level"]) > lv:
			mk = str(lot_id)
			lv = int(b["level"])
	var lever := float(BuildRules.construction_cost(n, "market", lv + 1)["gold"])
	t.ok(mk != "", "(setup) the gold lever: the Market on %s, level %d -> %d for %.0f gold" % [mk, lv, lv + 1, lever])
	_tie(c, n)
	var m := _away(c, n, "trap_b", 12 * 3600)
	t.ok(m.town_sim.gold > lever,
		"a night later (12 h) the gold has climbed past the lever: %.2f against %.0f (it was %.2f; %d buildings unpaid at the end)" % [
			m.town_sim.gold, lever, g0, _unpaid(m).size()])
	# the resume rule's income test (the manager's ruling (i)): what stays unpaid stays for the income, never for the
	# stocks (the gold covers a hold many times over), and the player is told why, and that a Market fixes it
	var held: Array = []
	var hold_lot := ""
	var due := 0.0
	for lot_id in m.town_sim.buildings:
		var b: Dictionary = m.town_sim.buildings[lot_id]
		if str(b["state"]) == "unpaid" and m.town_sim.held_by_income(str(lot_id)):
			held.append(str(b["building_id"]))
			hold_lot = str(lot_id) if hold_lot == "" else hold_lot
	for e in m.town_sim._lists()["work"]:  # the paying buildings: [lot_id, upkeep gold, upkeep bone]
		due += float(e[1])
	var income := m.town_sim.gold_income()
	t.ok(held.size() == _unpaid(m).size() and not held.is_empty() and income - due > 0.0,
		"every unpaid building is held by the income (%s), and the paying upkeep %.3f is under the income %.3f" % [str(held), due, income])
	var lines: Array = (m.view_away()["ready"] as Array).filter(func(l): return str(l["text"]).begins_with("Still stopped, "))
	t.ok(lines.size() == 1 and str(lines[0]["text"]).contains("can't pay their upkeep") and str(lines[0]["text"]).ends_with("Build a Market"),
		"the away report says why they're off and that a Market fixes it: \"%s\"" % (str(lines[0]["text"]) if not lines.is_empty() else ""))
	t.ok(bool(m.cmd_queue_build("", hold_lot)["ok"]), "(setup) an upgrade queued on a held lot (%s)" % hold_lot)
	var row: Dictionary = (m.view_town()["queue"] as Array)[0]
	t.ok(row["status"] == "skipped_gate" and row["reason"] == "upkeep",
		"the queue reads the income as its reason, not the stocks: %s / %s" % [row["status"], row["reason"]])
	# the trap's exit (the E4 step 4 review's item 4): with the lever queued too, one more night (12 h) away starts the
	# Market's upgrade, and its stalls' income brings the held buildings back
	var n_held := _unpaid(m).size()
	t.ok(bool(m.cmd_queue_build("", mk)["ok"]), "(setup) the lever queued: the Market on %s to level %d" % [mk, lv + 1])
	var x := _away(c, m, "trap_c", 12 * 3600)
	var lv_x := int(x.town_sim.buildings[mk]["level"])
	t.ok(lv_x == lv + 1 and str(x.town_sim.buildings[mk]["state"]) != "constructing",
		"a night later the Market is built to level %d (%s)" % [lv_x, str(x.town_sim.buildings[mk]["state"])])
	var still_ok := true
	for lot_id in x.town_sim.buildings:
		if str(x.town_sim.buildings[lot_id]["state"]) == "unpaid":
			still_ok = still_ok and x.town_sim.held_by_income(str(lot_id))
	t.ok(_unpaid(x).size() < n_held and still_ok and x.town_sim.gold_income() > income,
		"and the held buildings come back as the income allows: %d unpaid (was %d; the rest still held by the income), income %.3f g/s (was %.3f)" % [
			_unpaid(x).size(), n_held, x.town_sim.gold_income(), income])
	_cleanup()
	return t.failures


## The tie (the E4 step 4 review's must-fix: one margin, TownSim.income_pays). pre_vei 3 h on sits on it: the House,
## the Well and the Bakery each have an upkeep (0.01) that would take the paying upkeep (0.59) to exactly the stalls'
## 0.60, a net of about −1e-16 g/s. Every reader refuses it: the resume rule's test, held_by_income and the queue's gate,
## and a rise in the income of 2 ulps still refuses (the old rule, `income − due − own > 0` on the step's gold_in / dt,
## would resume there), while one past the margin passes. Then the same state run 10 min open (0.5 s ticks) and closed
## (a load 10 min on: the catch-up's long steps) ends with the same buildings unpaid, the tied ones among them.
func _tie(c: Dictionary, n: GameState) -> void:
	var ts := n.town_sim
	var income := ts.gold_income()
	var due := 0.0
	for e in ts._lists()["work"]:
		due += float(e[1])
	var tied: Array = []
	for lot_id in ts.buildings:
		var b: Dictionary = ts.buildings[lot_id]
		var own := ts.upkeep_gold_of(str(b["building_id"]))
		if str(b["state"]) == "unpaid" and float(b["unpaid_s"]) <= 0.0 and absf(income - due - own) <= BuildRules.NET_EPS:
			tied.append(str(lot_id))
	t.ok(not tied.is_empty(), "(setup) pre_vei 3 h on sits on the tie: %s unpaid, each at income %.17f = paying %.17f + its own" % [
		str(tied), income, due])
	if tied.is_empty():
		return
	var lot0: String = tied[0]
	var own0 := ts.upkeep_gold_of(str(ts.buildings[lot0]["building_id"]))
	var up := income + 2.0e-16  # 2 ulps of 0.6
	t.ok(up > income and up - due - own0 > 0.0, "(setup) 2 ulps up, the old strict test would pass: net %s" % str(up - due - own0))
	t.ok(not ts._income_pays(income, due, own0, false) and not ts._income_pays(up, due, own0, false) and ts.held_by_income(lot0),
		"the tie is refused, at the income and 2 ulps above it (the resume rule's test), and held_by_income agrees")
	t.ok(not ts.income_pays(due + own0, due + own0) and not ts.income_pays(due + own0 + 0.5e-9, due + own0)
		and ts.income_pays(due + own0 + 2.0e-9, due + own0),
		"the one margin: an income equal to the bill, or 0.5e-9 over it, doesn't pay it; 2e-9 over does")
	var lots := {}  # the gate's bill for a new House: the paying buildings alone (the tie), then the gate's own reading
	for e in ts._lists()["work"]:
		lots[str(e[0])] = ts.buildings[str(e[0])]
	t.ok(BuildRules.upkeep_short(n, "house", lots) == not ts.income_pays(income, due + ts.upkeep_gold_of("house")),
		"the queue's gate reads the same rule on the same bill (a House on the paying lots: %s)" % str(BuildRules.upkeep_short(n, "house", lots)))
	# open against closed, 10 min
	var o := _away(c, n, "tie_open", 0)
	o.drain_events()
	var o_up: Array = []
	for i in 1200:
		o.tick(0.5)
		for e in o.drain_events():
			if str(e["type"]) == "building_unpaid" and not bool(e["unpaid"]):
				o_up.append(str(e["lot_id"]))
	var k := _away(c, n, "tie_closed", 600)
	var k_up: Array = []
	for e in k.catchup_events():
		if str(e["type"]) == "building_unpaid" and not bool(e["unpaid"]):
			k_up.append(str(e["lot_id"]))
	var kept := true
	for l in tied:
		kept = kept and str(o.town_sim.buildings[l]["state"]) == "unpaid" and str(k.town_sim.buildings[l]["state"]) == "unpaid"
		kept = kept and not o_up.has(l) and not k_up.has(l)
	t.ok(absf(o.t - k.t) < 1e-6 and _unpaid(o) == _unpaid(k) and kept,
		"10 min open and closed end with the same buildings unpaid (%s), the tied ones never resumed (resumed: open %s, closed %s)" % [
			str(_unpaid(k)), str(o_up), str(k_up)])


func _mk(c: Dictionary) -> GameState:
	var s := GameState.new(c)
	s.debug_enabled = true
	s.save_dir = _dir
	return s


## Saves `s` at CLOCK; a fresh state loads it with the clock `away` s on (the catch-up runs in cmd_load).
func _away(c: Dictionary, s: GameState, slot: String, away: int) -> GameState:
	s.clock_override = CLOCK
	t.ok(s.cmd_save(slot)["ok"], "(setup) %s saved" % slot)
	var n := _mk(c)
	n.clock_override = CLOCK + away
	t.ok(n.cmd_load(slot)["ok"], "(setup) %s loads %d s later" % [slot, away])
	return n


static func _unpaid(s: GameState) -> Array:
	var out: Array = []
	for lot_id in s.town_sim.buildings:
		if str(s.town_sim.buildings[lot_id]["state"]) == "unpaid":
			out.append(str(s.town_sim.buildings[lot_id]["building_id"]))
	return out


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(_dir)
