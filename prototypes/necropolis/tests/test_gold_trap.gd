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
	_cleanup()
	return t.failures


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
