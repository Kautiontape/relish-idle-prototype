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
##   do it: TownSim musters the WORK it can't use, and Ashgate keeps its 1.12 mass/s.)
## - Asserted: every "safe" sample's fort is still held 8 h on (the worst lie is safe, then broken
##   overnight), and at least one safe sample over all starts (else the check is vacuous).
## - The known gap (the run's manager: accepted for E2b-2 only, labelled and counted, not a pass): a margin
##   reads today's flows and neither probe reads the town. A safe fort that falls is counted apart as "its
##   WAR fell: supply (E4)" only when a town store (gold or bone: the stores upkeep is paid from, whose floor
##   of 0 idles buildings) reached its floor before the fort's WAR first went below FLOW_DROP × its sampled
##   value, and that drop came before its last break began (the retake less break_s): classify(). A WAR
##   drop with no store at its floor fails, and so does a break with the WAR intact. pre_vei+2 is the case:
##   pre_vei's gold reaches its floor at about 2 h, its buildings go unpaid, its pits stop and the WAR goes
##   from 49.7 to 0.95 mass/s. Relish's own moves are no such excuse (the train reads her committed
##   arrival; midgame's Old Sluice at t0 is the case).
##   E4's done-criterion: this check passes with the exemption deleted (classify() returning "broke" always).
## - Reported: per start, the samples by word (train and one-wave), the thin forts that held (how
##   pessimistic it is), each will_fall sample's fall_s against when it fell, the exempt cases with their
##   store and floor time, and their count against the safe total.

const HOURS := 12.0
const SAMPLE_EVERY_S := 1800.0
const SAMPLE_UNTIL_S := 4.0 * 3600.0
const AHEAD_S := 8.0 * 3600.0
## A safe fort whose WAR went below this share of its sampled WAR (after a store's floor) fell to the town.
const FLOW_DROP := 0.5
## The town stores whose floor is a supply failure (upkeep is paid from them; at 0 buildings go unpaid), and
## how close to that floor of 0 counts as at it: one unit (pre_vei's gold reads 0.007 as its buildings go
## unpaid: upkeep idles them before the stock goes under). Bodies, workers and living sit at 0 in ordinary
## play (the pits burn every body), so their floor says nothing about supply.
const STORES := ["gold", "bone"]
const FLOOR_EPS := 1.0

var t := TestUtil.new()


func run() -> int:
	t.suite("margin_truth")
	check_classify()
	var c = load("res://tests/slow/convergence.gd").new()
	c.t = t
	var starts := [["midgame_2flips", "midgame_2flips", ""], ["pre_vei", "pre_vei", ""], ["fresh", "fresh", ""],
		["pre_vei+2", "pre_vei", "hold2"], ["midgame, WAR 0.05", "midgame_2flips", "war05"]]
	var safe_total := 0
	var exempt_total := 0
	var lines: Array = []
	for st in starts:
		var s: GameState = c.load_state(c.start_json(st[1]))
		if st[2] == "hold2":
			s.tick(600.0)  # past pre_vei's opening muster burst
			s.realm.hold("ashgate", 0.0)
			s.realm.hold("vespers", 0.0)
			s.realm.start_tithe()
		elif st[2] == "war05":
			t.ok(s.cmd_set_valve(0.40, 0.05, 0.55)["ok"], "(setup) the valve's WAR share 0.05, the rest to FLOOD")
		var r := _run(s)
		safe_total += int(r["safe"])
		exempt_total += (r["supply"] as Array).size()
		lines.append_array(_report(st[0], r))
		t.ok(r["safe_broke"].is_empty(), "%s: every safe fort stands 8 h on (%d safe samples, %d exempt)%s" % [st[0], r["safe"],
			(r["supply"] as Array).size(), "" if r["safe_broke"].is_empty() else ": broke " + str(r["safe_broke"])])
	for ln in lines:
		print(ln)
	print("  [margin_truth] the known gap: %d of %d safe samples fell after their WAR fell: supply (E4)" % [exempt_total, safe_total])
	t.ok(safe_total > 0, "the check is not vacuous: %d safe samples over all starts" % safe_total)
	return t.failures


## A safe sample that fell, classified (see the header). `war` is the fort's WAR and `stores` {store:
## Array} the town's stocks (floats), entry i at (i + 1) · dt seconds into the run; the sample is at
## `sample_t` with WAR `w_sampled`, the retake at `retake_t`. Returns {kind: "supply" or "broke", store,
## floor_t (the store's first floor time in the run, −1 when none), drop_t (when the WAR first went below
## FLOW_DROP × w_sampled after the sample, −1 when never), break_t (the last break's start)}.
static func classify(sample_t: float, w_sampled: float, retake_t: float, war: Array, stores: Dictionary,
		dt: float, break_s: float) -> Dictionary:
	var out := {"kind": "broke", "store": "", "floor_t": -1.0, "drop_t": -1.0, "break_t": retake_t - break_s}
	for i in war.size():
		var at := (i + 1) * dt
		if at > sample_t and float(war[i]) < FLOW_DROP * w_sampled:
			out["drop_t"] = at
			break
	var drop := float(out["drop_t"])
	if drop < 0.0 or drop >= float(out["break_t"]):
		return out  # the WAR held until the break began
	for name in stores:
		var series: Array = stores[name]
		for i in series.size():
			if float(series[i]) <= FLOOR_EPS:
				var ft := (i + 1) * dt
				if ft <= drop and ft < float(out["break_t"]) and (out["floor_t"] < 0.0 or ft < float(out["floor_t"])):
					out["kind"] = "supply"
					out["store"] = name
					out["floor_t"] = ft
				break
	return out


## classify() on made-up series (1 s apart, 300 s; the sample at 0 with WAR 10, the retake at 250 s and
## break_s 120, so the last break began at 130 s): gold at its floor at 41 s, then the WAR under half at
## 51 s, is supply; the same WAR drop with gold never at its floor is broke; the WAR intact is broke; gold
## at its floor at 200 s, after the last break began, is broke. Returns the failures it added.
func check_classify() -> int:
	var f0 := t.failures
	var mk := func(n: int, before: float, after: float, at: int) -> Array:
		var a: Array = []
		for i in n:
			a.append(before if i < at else after)
		return a
	var drop: Array = mk.call(300, 10.0, 2.0, 50)
	var held: Array = mk.call(300, 10.0, 10.0, 0)
	var cases := [
		["a store's floor, then the WAR drop", drop, {"gold": mk.call(300, 50.0, 0.5, 40), "bone": held}, "supply"],
		["the WAR drop with no store at its floor", drop, {"gold": held, "bone": held}, "broke"],
		["the WAR intact", held, {"gold": mk.call(300, 50.0, 0.5, 40), "bone": held}, "broke"],
		["a store's floor after the last break began", drop, {"gold": mk.call(300, 50.0, 0.5, 199), "bone": held}, "broke"],
	]
	for c in cases:
		var r := classify(0.0, 10.0, 250.0, c[1], c[2], 1.0, 120.0)
		t.ok(r["kind"] == c[3], "classify, %s: %s (floor %.0f s, drop %.0f s, break %.0f s)" % [c[0], r["kind"], r["floor_t"], r["drop_t"], r["break_t"]])
	return t.failures - f0


## Runs `s` for HOURS of 0.5 s ticks, sampling as above. Returns {samples: [[t, fort_id, margin, cause,
## fall_s, one-wave margin, one-wave cause, WAR to it]], retaken: {fort_id: t}, floors: {store: first floor
## t or −1}, safe, safe_broke, supply: [the exempt cases' lines]}.
func _run(s: GameState) -> Dictionary:
	var step := s.substep_s()
	var t0 := s.t
	var samples: Array = []
	var retaken := {}
	# the series after each tick, in plain Arrays (shared, so appending copies nothing): each fort held at
	# the start's WAR, each store's stock
	var war_t := {}
	for f in s.realm.forts:
		if RealmSim.is_held(f):
			war_t[f["id"]] = []
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
		for k in s.realm.forts.size():
			var id: String = s.realm.forts[k]["id"]
			if war_t.has(id):
				(war_t[id] as Array).append(float(ws[k]))
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
	var safe := 0
	var safe_broke: Array = []
	var supply: Array = []
	var break_s := float(s._cfgs["realm"]["hold"]["break_s"])
	for smp in samples:
		if smp[2] == "safe":
			safe += 1
			var at := float(retaken.get(smp[1], INF))
			if at > float(smp[0]) and at <= float(smp[0]) + AHEAD_S:
				var cl := classify(float(smp[0]), float(smp[7]), at, war_t[smp[1]], store_t, step, break_s)
				var line := "%s at %.0f s (WAR %.2f), retaken %.0f s later: its WAR fell: %s%s" % [smp[1], smp[0], smp[7], at - float(smp[0]),
					"supply (E4), %s at its floor at %.0f s, the WAR under %.1f at %.0f s, its last break from %.0f s" % [cl["store"], cl["floor_t"],
					FLOW_DROP * float(smp[7]), cl["drop_t"], cl["break_t"]] if cl["kind"] == "supply" else "no (broke: drop %.0f s, floors %s, break %.0f s)" % [
					cl["drop_t"], str(floors), cl["break_t"]], ""]
				(supply if cl["kind"] == "supply" else safe_broke).append(line)
	return {"samples": samples, "retaken": retaken, "floors": floors, "safe": safe, "safe_broke": safe_broke, "supply": supply}


## The report lines for one start: the counts by word (train and one-wave), with what happened next.
func _report(name: String, r: Dictionary) -> Array:
	var out: Array = []
	var samples: Array = r["samples"]
	var retaken: Dictionary = r["retaken"]
	out.append("  [margin_truth] %s: %d samples, retaken %s, the stores' first floor %s" % [name, samples.size(), str(retaken), str(r["floors"])])
	for ln in r["supply"]:
		out.append("  [margin_truth] %s: %s" % [name, ln])
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
