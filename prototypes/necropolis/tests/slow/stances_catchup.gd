extends RefCounted
## E3-1, the stances in catch-up and Thrift's flicker (MECHANICS §4.5, IDLE §4). Run with
## tests/run.sh --slow --only=stances_catchup (a few minutes). The field is shrunk (8 × 6) as in test_catchup.
## - With stances on, catch-up matches live: midgame_2flips with Vigil, Harvest and Thrift on, 6 h caught up at the
##   shipped step (a load 6 h on: 5 s steps) against 6 h live at 0.5 s from the same save (test_catchup's
##   accuracy() and compare()). The outcomes (builds, flips, retakes, waves, upkeep switches, tier, the forts held and
##   holding living) must match, each flip and retake within convergence.gd's TIME_BOUND_STEPS of the catch-up's step;
##   the stocks and rates are printed. Each run's stance_fired are counted. The same for pre_vei with Thrift and Muster
##   on (both act there), printed.
## - Thrift's flicker (the run's manager): pre_vei with Thrift on, 12 h live at 0.5 s; every building Thrift idles or
##   resumes, with its time; R1's measure: no building idled and resumed again within 30 s
##   (economy.json upkeep.unpaid_hold_s), nor resumed and idled again within it. Measured and reported; the rule isn't
##   changed for it.

const HOURS := 6.0
const FLICKER_H := 12.0

var t := TestUtil.new()


func run() -> int:
	t.suite("stances_catchup")
	var cu = load("res://tests/test_catchup.gd")
	var conv = load("res://tests/slow/convergence.gd").new()
	conv.t = t
	var c: Dictionary = cu.cfgs()
	var tol := float(c["economy"]["idle"]["catchup_tol"])
	for pair in [["midgame_2flips", ["vigil", "harvest", "thrift"]], ["pre_vei", ["thrift", "muster"]]]:
		var s := GameState.new(c)
		s.debug_enabled = true
		s.from_dict(JSON.parse_string(conv.start_json(pair[0])))
		for id in pair[1]:
			s.cmd_set_stance(id, true)
		var r: Dictionary = _accuracy(cu, c, JSON.stringify(s.to_dict()), HOURS * 3600.0, tol)
		print("  [stances_catchup] %s, %s on, %.0f h caught up vs live at 0.5 s: %s; stance_fired caught up %s, live %s; Thrift idles at the end %s / %s" % [
			pair[0], str(pair[1]), HOURS, r["lines"], str(r["fired"][0]), str(r["fired"][1]), str(r["thrift"][0]), str(r["thrift"][1])])
		if pair[0] == "midgame_2flips":
			t.ok((r["outcomes"] as Array).is_empty() and (r["late"] as Array).is_empty() and r["town_same"],
				"%s with %s on: %.0f h caught up at the shipped step matches live at 0.5 s: the same outcomes, flips and retakes within %s steps, Covington identical: %s" % [
				pair[0], str(pair[1]), HOURS, str(conv.TIME_BOUND_STEPS), r["lines"]])
	_flicker(c, conv)
	return t.failures


## test_catchup's accuracy(), with each run's stance_fired counted by stance and Thrift's buildings at the end.
func _accuracy(cu, c: Dictionary, js: String, seconds: float, tol: float) -> Dictionary:
	var dir := "user://test_stances_slow_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var src := GameState.new(c)
	src.debug_enabled = true
	src.from_dict(JSON.parse_string(js))
	src.save_dir = dir
	src.clock_override = cu.CLOCK
	src.cmd_save("acc")
	var a := GameState.new(c)
	a.debug_enabled = true
	a.save_dir = dir
	a.clock_override = cu.CLOCK + int(seconds)
	a.cmd_load("acc")
	var b := GameState.new(c)
	b.debug_enabled = true
	b.save_dir = dir
	b.clock_override = cu.CLOCK
	b.cmd_load("acc")
	b.drain_events()
	b.tick(seconds)
	var b_evs := b.drain_events()
	var out: Dictionary = cu.compare(a, a.catchup_events(), b, b_evs, tol)
	out["fired"] = [_fired(a.catchup_events()), _fired(b_evs)]
	out["thrift"] = [a.town_sim._lists()["thrift"], b.town_sim._lists()["thrift"]]
	DirAccess.remove_absolute(dir + "/acc.json")
	DirAccess.remove_absolute(dir)
	return out


static func _fired(evs: Array) -> Dictionary:
	var n := {}
	for e in evs:
		if e["type"] == "stance_fired":
			var k := "%s %s" % [e["stance_id"], "on" if bool(e["active"]) else "off"]
			n[k] = int(n.get(k, 0)) + 1
	return n


## pre_vei with Thrift on, FLICKER_H live at 0.5 s: each Thrift idle and resume as [t − t0, lot, building, idled],
## and R1's measure on them.
func _flicker(c: Dictionary, conv) -> void:
	var s := GameState.new(c)
	s.debug_enabled = true
	s.from_dict(JSON.parse_string(conv.start_json("pre_vei")))
	s.cmd_set_stance("thrift", true)
	var hold := float(c["economy"]["upkeep"]["unpaid_hold_s"])
	var t0 := s.t
	var prev: Array = s.town_sim._lists()["thrift"].duplicate()
	var switches: Array = []
	var fired: Array = []
	var unpaid := 0
	for i in int(FLICKER_H * 3600.0 / s.substep_s()):
		s.tick(s.substep_s())
		var now: Array = s.town_sim._lists()["thrift"]
		if now != prev:
			for lot in now:
				if not prev.has(lot):
					switches.append([s.t - s.substep_s() - t0, lot, s.town_sim.buildings[lot]["building_id"], true])
			for lot in prev:
				if not now.has(lot):
					switches.append([s.t - s.substep_s() - t0, lot, str(s.town_sim.buildings.get(lot, {}).get("building_id", "")), false])
			prev = now.duplicate()
		for e in s.drain_events():
			if e["type"] == "stance_fired" and e["stance_id"] == "thrift":
				fired.append([float(e["t"]) - t0, bool(e["active"])])
			elif e["type"] == "building_unpaid":
				unpaid += 1
	var flicker: Array = []
	var last := {}
	for sw in switches:
		var lot: String = sw[1]
		if last.has(lot) and float(sw[0]) - float(last[lot][0]) < hold:
			flicker.append("%s %s at %.1f s and %s at %.1f s" % [lot, "idled" if last[lot][1] else "resumed", float(last[lot][0]),
				"idled" if sw[3] else "resumed", float(sw[0])])
		last[lot] = [float(sw[0]), bool(sw[3])]
	var lines: Array = switches.map(func(sw): return "%.1f s %s %s %s" % [float(sw[0]), sw[1], sw[2], "idled" if sw[3] else "resumed"])
	print("  [stances_catchup] Thrift's flicker, pre_vei %.0f h live at 0.5 s with Thrift on: %d switches: %s; Thrift's stance_fired %s; %d building_unpaid; at the end Thrift idles %s, gold %.1f" % [
		FLICKER_H, switches.size(), "; ".join(PackedStringArray(lines)), str(fired), unpaid, str(s.town_sim._lists()["thrift"]), s.town_sim.gold])
	t.ok(flicker.is_empty(), "Thrift's flicker (R1's measure): no building idled and resumed again within %.0f s over %.0f h: %s" % [hold, FLICKER_H,
		"none" if flicker.is_empty() else ", ".join(PackedStringArray(flicker))])
