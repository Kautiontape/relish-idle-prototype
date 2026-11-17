extends RefCounted
## The margins' truth check (E2b-2 T3.4b; MECHANICS §3.5; tests/run.sh --slow --only=margin_truth, a few
## minutes): does a held fort that reads "safe" still stand 8 h later? From each start, live 0.5 s steps
## (tick) for 12 h with no input; at the first substep (t0: before it a loaded state's readouts read the
## saved flows) and every 30 min up to 4 h, each held fort's margin (view_fort: the wave train's) and the
## one-wave margin at the same moment (readout_of with no train verdict: view_projection's drag), then what
## happened in the following 8 h.
## - Starts: midgame_2flips, pre_vei and fresh (convergence.gd's: cmd_new_game(1) run 10 min), loaded from
##   the same JSON into a GameState with the field shrunk (convergence.gd's cfgs). pre_vei and fresh hold no
##   fort, so they give no samples. Constructed: "pre_vei+2", pre_vei run 10 min (its first substeps carry a
##   muster burst, 192 mass/s of WAR against 49.7 by 300 s, which a t0 sample would read), then Ashgate and
##   Vespers held, contested, and her clock started; and "midgame, WAR 0.05", midgame_2flips with its
##   valve's WAR share cut to 0.05 and the rest to FLOOD, where both held forts fall. (A cut to WORK doesn't
##   do it: TownSim musters the WORK it can't use, and Ashgate keeps its 1.12 mass/s.) And (E4 must-fix #1)
##   "pre_vei+2 burst, WORK 0.10": pre_vei+2's setup with no tick(600), so its t0 sample reads the opening muster
##   burst, and the valve at (0.10, 0.05, 0.85). One substep in the split's WAR is 175.6 mass/s against the 4.15 the
##   train reads settled (GameState._train_war_at); the sim retakes Vespers at 675 s and Ashgate at 952 s. Read on
##   the instant support (before E4), both forts' t0 samples said safe; settled, Vespers reads will_fall and
##   Ashgate thin. Its revert proof, never committed: the instant support with no siege credited fails it.
## - Asserted: every "safe" sample's fort is still held 8 h on (the worst lie is safe, then broken
##   overnight; safe_broke()), and at least one safe sample over all starts (else the check is vacuous). No
##   fall is excused. R1 (the E2b-2 vision review; MECHANICS §4.3) deleted E2b-2's known gap, which counted a
##   safe fort that fell after a town store's floor and its WAR's drop apart as "its WAR fell: supply (E4)":
##   with the WAR chain shed last, pre_vei+2's gold floor (7 092 s) sheds the Statue and the passive buildings,
##   its pits keep raising, and its 18 samples all read safe and all hold (before, its 8 safe samples all
##   fell about 2 h in, all exempt: 8 of the 16 safe samples then). Relish's own moves are no excuse either
##   (the train reads her committed arrival; midgame's Old Sluice at t0 is the case).
## - Reported: per start, the samples by word (train and one-wave), the thin forts that held (how
##   pessimistic it is), each will_fall sample's fall_s against when it fell, and the town stores' first floor
##   (gold or bone: upkeep is paid from them, and at 0 buildings go unpaid), printed, not judged.

const HOURS := 12.0
const SAMPLE_EVERY_S := 1800.0
const SAMPLE_UNTIL_S := 4.0 * 3600.0
const AHEAD_S := 8.0 * 3600.0
## The town stores whose first floor is printed (upkeep is paid from them; at 0 buildings go unpaid), and how
## close to that floor of 0 counts as at it: one unit (pre_vei's gold reads 0.007 as its buildings go unpaid:
## upkeep idles them before the stock goes under).
const STORES := ["gold", "bone"]
const FLOOR_EPS := 1.0

var t := TestUtil.new()


func run() -> int:
	t.suite("margin_truth")
	check_safe_broke()
	var c = load("res://tests/slow/convergence.gd").new()
	c.t = t
	var starts := [["midgame_2flips", "midgame_2flips", ""], ["pre_vei", "pre_vei", ""], ["fresh", "fresh", ""],
		["pre_vei+2", "pre_vei", "hold2"], ["midgame, WAR 0.05", "midgame_2flips", "war05"],
		["pre_vei+2 burst, WORK 0.10", "pre_vei", "burst"]]
	var safe_total := 0
	var lines: Array = []
	for st in starts:
		var s: GameState = c.load_state(c.start_json(st[1]))
		if st[2] == "hold2":
			s.tick(600.0)  # past pre_vei's opening muster burst
			s.realm.hold("ashgate", 0.0)
			s.realm.hold("vespers", 0.0)
			s.realm.start_tithe()
		elif st[2] == "burst":  # (E4 must-fix #1) no tick(600): the t0 sample reads pre_vei's opening muster burst
			s.realm.hold("ashgate", 0.0)
			s.realm.hold("vespers", 0.0)
			s.realm.start_tithe()
			t.ok(s.cmd_set_valve(0.10, 0.05, 0.85)["ok"], "(setup) the valve's WORK share 0.10 and WAR 0.05, the rest to FLOOD")
		elif st[2] == "war05":
			t.ok(s.cmd_set_valve(0.40, 0.05, 0.55)["ok"], "(setup) the valve's WAR share 0.05, the rest to FLOOD")
		var r := _run(s)
		safe_total += int(r["safe"])
		lines.append_array(_report(st[0], r))
		t.ok(r["safe_broke"].is_empty(), "%s: every safe fort stands 8 h on (%d safe samples)%s" % [st[0], r["safe"],
			"" if r["safe_broke"].is_empty() else ": broke " + str(r["safe_broke"])])
	for ln in lines:
		print(ln)
	t.ok(safe_total > 0, "the check is not vacuous: %d safe samples over all starts" % safe_total)
	return t.failures


## The safe samples (`samples` as _run() returns them: [t, fort_id, margin, ...]) whose fort was retaken
## (`retaken`: {fort_id: t}) after the sample and within AHEAD_S of it, each a line; every one is a failure.
static func safe_broke(samples: Array, retaken: Dictionary) -> Array:
	var out: Array = []
	for smp in samples:
		if smp[2] != "safe":
			continue
		var at := float(retaken.get(smp[1], INF))
		if at > float(smp[0]) and at <= float(smp[0]) + AHEAD_S:
			out.append("%s at %.0f s (WAR %.2f), retaken %.0f s later" % [smp[1], smp[0], smp[7], at - float(smp[0])])
	return out


## safe_broke() on made-up samples. E2b-2's exempt case (a fort read safe at 0 s with WAR 10, gold at its floor
## 41 s on, its WAR under half from 51 s, retaken 250 s on, the town's supply to blame) is a failure now, as is
## a safe fort retaken just inside 8 h; a fort retaken after 8 h, a safe fort never retaken, one retaken before
## its sample, and a thin or will_fall reading retaken are not. Returns the failures it added.
func check_safe_broke() -> int:
	var f0 := t.failures
	var smp := func(at: float, id: String, margin: String) -> Array:
		return [at, id, margin, "", -1.0, margin, "", 10.0]
	var cases := [
		["a safe fort retaken 250 s on after a gold floor and a WAR drop (E2b-2's exemption)", [smp.call(0.0, "a", "safe")], {"a": 250.0}, 1],
		["a safe fort retaken just inside 8 h", [smp.call(1800.0, "a", "safe")], {"a": 1800.0 + AHEAD_S}, 1],
		["a safe fort retaken just after 8 h", [smp.call(0.0, "a", "safe")], {"a": AHEAD_S + 1.0}, 0],
		["a safe fort never retaken", [smp.call(0.0, "a", "safe")], {}, 0],
		["a safe sample after its fort's retake", [smp.call(1800.0, "a", "safe")], {"a": 900.0}, 0],
		["thin and will_fall readings retaken", [smp.call(0.0, "a", "thin"), smp.call(0.0, "b", "will_fall")], {"a": 250.0, "b": 250.0}, 0],
	]
	for c in cases:
		var r := safe_broke(c[1], c[2])
		t.ok(r.size() == c[3], "safe_broke, %s: %d broke %s" % [c[0], r.size(), str(r)])
	return t.failures - f0


## Runs `s` for HOURS of 0.5 s ticks, sampling as above. Returns {samples: [[t, fort_id, margin, cause,
## fall_s, one-wave margin, one-wave cause, WAR to it]], retaken: {fort_id: t}, floors: {store: first floor
## t or −1}, safe, safe_broke: [safe_broke()'s lines]}.
func _run(s: GameState) -> Dictionary:
	var step := s.substep_s()
	var t0 := s.t
	var samples: Array = []
	var retaken := {}
	# each store's stock after each tick, in plain Arrays (shared, so appending copies nothing): its first floor
	var store_t := {}
	for k in STORES:
		store_t[k] = []
	var next_sample := 0.0
	var n := int(HOURS * 3600.0 / step)
	for i in n:
		s.tick(step)
		for e in s.drain_events():
			if e["type"] == "fort_retaken" and not retaken.has(e["fort_id"]):
				retaken[e["fort_id"]] = float(e["t"]) - t0
		var el := s.t - t0
		var ws := s._fort_wars()
		for k in STORES:
			(store_t[k] as Array).append(float(s.town_sim.get(k)))
		if el >= next_sample - 1e-9 and next_sample <= SAMPLE_UNTIL_S + 1e-9:
			for k in s.realm.forts.size():
				var f: Dictionary = s.realm.forts[k]
				if not RealmSim.is_held(f):
					continue
				var v := s.view_fort(f["id"])
				var one := s._fort_readout(f, float(ws[k]))
				samples.append([el, str(f["id"]), str(v["margin"]), str(v["margin_cause"]), float(v["fall_s"]), str(one["margin"]), str(one["margin_cause"]),
					float(ws[k])])
			next_sample = SAMPLE_EVERY_S if next_sample == 0.0 else next_sample + SAMPLE_EVERY_S
	var floors := {}
	for k in STORES:
		floors[k] = -1.0
		var ss: Array = store_t[k]
		for i in ss.size():
			if float(ss[i]) <= FLOOR_EPS:
				floors[k] = (i + 1) * step
				break
	var safe := samples.filter(func(smp): return smp[2] == "safe").size()
	return {"samples": samples, "retaken": retaken, "floors": floors, "safe": safe, "safe_broke": safe_broke(samples, retaken)}


## The report lines for one start: the counts by word (train and one-wave), with what happened next.
func _report(name: String, r: Dictionary) -> Array:
	var out: Array = []
	var samples: Array = r["samples"]
	var retaken: Dictionary = r["retaken"]
	out.append("  [margin_truth] %s: %d samples, retaken %s, the stores' first floor %s" % [name, samples.size(), str(retaken), str(r["floors"])])
	for ln in r["safe_broke"]:
		out.append("  [margin_truth] %s: safe, then broke: %s" % [name, ln])
	if samples.is_empty():
		out.append("  [margin_truth] %s: no fort held, no sample (vacuous here)" % name)
		return out
	for col in [[2, 3, "train"], [5, 6, "one-wave"]]:
		var tally := {}
		for smp in samples:
			var w: String = "%s/%s" % [smp[col[0]], smp[col[1]]]
			var at := float(retaken.get(smp[1], INF))
			var fell := at > float(smp[0]) and at <= float(smp[0]) + AHEAD_S
			var e: Array = tally.get(w, [0, 0])
			e[0] += 1
			if fell:
				e[1] += 1
			tally[w] = e
		var parts: Array = []
		for w in tally:
			parts.append("%s %d (%d fell within 8 h, %d held)" % [w, tally[w][0], tally[w][1], tally[w][0] - tally[w][1]])
		out.append("  [margin_truth] %s, %s: %s" % [name, col[2], ", ".join(parts)])
	for smp in samples:
		if smp[2] == "will_fall":
			var at := float(retaken.get(smp[1], INF))
			out.append("  [margin_truth] %s: %s at %.0f s will_fall, fall_s %.0f s, fell %s (fall_s %s)" % [name, smp[1], smp[0], smp[4],
				"%.0f s later" % (at - float(smp[0])) if at < INF else "not within the run",
				("early by %.0f s" % (at - float(smp[0]) - float(smp[4])) if at - float(smp[0]) >= float(smp[4]) else "late by %.0f s" % (float(smp[4]) - (at - float(smp[0])))) if at < INF else "-"])
	for smp in samples:
		out.append("  [margin_truth] %s: t %5.0f s %-12s WAR %6.2f train %-9s %-4s one-wave %-9s %-4s %s" % [name, smp[0], smp[1], smp[7], smp[2], smp[3], smp[5], smp[6],
			"retaken %.0f s later" % (float(retaken[smp[1]]) - float(smp[0])) if retaken.has(smp[1]) and float(retaken[smp[1]]) > float(smp[0]) else ""])
	return out
