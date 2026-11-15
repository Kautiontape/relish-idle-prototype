extends RefCounted
## The margins' truth check (E2b-2 T3.4b; MECHANICS §3.5; tests/run.sh --slow --only=margin_truth, a few
## minutes): does a held fort that reads "safe" still stand 8 h later? From each start, live 0.5 s steps
## (tick) for 12 h with no input; at the first substep (t0: before it a loaded state's readouts read the
## saved flows) and every 30 min up to 4 h, each held fort's margin (view_fort: the wave train's) and the
## one-wave margin at the same moment (readout_of with no train verdict: view_projection's drag), then what
## happened in the following 8 h.
## - Starts: midgame_2flips, pre_vei and fresh (convergence.gd's: cmd_new_game(1) run 10 min), loaded from
##   the same JSON into a GameState with the field shrunk (convergence.gd's cfgs). pre_vei and fresh hold no
##   fort, so they give no samples. Constructed: pre_vei with Ashgate and Vespers held, contested, and her
##   clock started at once ("pre_vei+2"), and midgame_2flips with its valve's WAR share cut to 0.05 and the
##   rest to FLOOD, where both held forts fall ("midgame, WAR 0.05": the will_fall clocks). (A cut to WORK
##   doesn't do it: TownSim musters the WORK it can't use, and Ashgate keeps its 1.12 mass/s.)
## - Asserted: every "safe" sample's fort is still held 8 h on (the worst lie is safe, then broken
##   overnight), and at least one safe sample over all starts (else the check is vacuous). A margin reads
##   today's flows (MECHANICS §3.5): a safe fort that falls after the WAR the valve sends it has dropped
##   below FLOW_DROP of what it was at the sample, before its last break began (the retake less break_s)
##   (the town's economy failing: pre_vei's gold runs out at
##   about 2.2 h, its pits stop and the WAR goes from 49.7 to 0.95 mass/s) is counted apart, as "its WAR
##   fell", printed and not failed: neither probe reads the town. Relish's own moves are no such excuse (the
##   train reads her committed arrival; midgame's Old Sluice at t0 is the case).
## - Reported: per start, the samples by word (train and one-wave), the thin forts that held (how
##   pessimistic it is), each will_fall sample's fall_s against when it fell, and any safe one that fell.

const HOURS := 12.0
const SAMPLE_EVERY_S := 1800.0
const SAMPLE_UNTIL_S := 4.0 * 3600.0
const AHEAD_S := 8.0 * 3600.0
## A safe fort that falls after its WAR dropped below this share of its sampled WAR fell to the flows, not
## the waves (see above).
const FLOW_DROP := 0.5
## The WAR series' spacing, seconds.
const WAR_EVERY_S := 10.0

var t := TestUtil.new()


func run() -> int:
	t.suite("margin_truth")
	var c = load("res://tests/slow/convergence.gd").new()
	c.t = t
	var starts := [["midgame_2flips", "midgame_2flips", ""], ["pre_vei", "pre_vei", ""], ["fresh", "fresh", ""],
		["pre_vei+2", "pre_vei", "hold2"], ["midgame, WAR 0.05", "midgame_2flips", "war05"]]
	var safe_total := 0
	var lines: Array = []
	for st in starts:
		var s: GameState = c.load_state(c.start_json(st[1]))
		if st[2] == "hold2":
			s.realm.hold("ashgate", 0.0)
			s.realm.hold("vespers", 0.0)
			s.realm.start_tithe()
		elif st[2] == "war05":
			t.ok(s.cmd_set_valve(0.40, 0.05, 0.55)["ok"], "(setup) the valve's WAR share 0.05, the rest to FLOOD")
		var r := _run(s)
		safe_total += int(r["safe"])
		lines.append_array(_report(st[0], r))
		t.ok(r["safe_broke"].is_empty(), "%s: every safe fort stands 8 h on, or fell after its WAR fell (%d safe samples%s)%s" % [st[0], r["safe"],
			"; %d fell after their WAR fell: %s" % [r["war_fell"].size(), str(r["war_fell"])] if not r["war_fell"].is_empty() else "",
			"" if r["safe_broke"].is_empty() else ": broke " + str(r["safe_broke"])])
	for ln in lines:
		print(ln)
	t.ok(safe_total > 0, "the check is not vacuous: %d safe samples over all starts" % safe_total)
	return t.failures


## Runs `s` for HOURS of 0.5 s ticks, sampling as above. Returns {samples: [[t, fort_id, margin, cause,
## fall_s, one-wave margin, one-wave cause, WAR to it]], retaken: {fort_id: t}, safe, safe_broke, war_fell}.
func _run(s: GameState) -> Dictionary:
	var step := s.substep_s()
	var t0 := s.t
	var samples: Array = []
	var retaken := {}
	var war_t := {}  # fort_id -> PackedFloat64Array of its WAR every WAR_EVERY_S
	var next_sample := 0.0
	var n := int(HOURS * 3600.0 / step)
	var every := int(WAR_EVERY_S / step)
	for i in n:
		s.tick(step)
		for e in s.drain_events():
			if e["type"] == "fort_retaken" and not retaken.has(e["fort_id"]):
				retaken[e["fort_id"]] = float(e["t"]) - t0
		var el := s.t - t0
		if i % every == 0:
			var ws := s._fort_wars()
			for k in s.realm.forts.size():
				var id: String = s.realm.forts[k]["id"]
				var series: PackedFloat64Array = war_t.get(id, PackedFloat64Array())
				series.append(float(ws[k]))
				war_t[id] = series  # a packed array is a value: write it back
		if el >= next_sample - 1e-9 and next_sample <= SAMPLE_UNTIL_S + 1e-9:
			var wars := s._fort_wars()
			for k in s.realm.forts.size():
				var f: Dictionary = s.realm.forts[k]
				if not RealmSim.is_held(f):
					continue
				var v := s.view_fort(f["id"])
				var one := s._fort_readout(f, float(wars[k]))
				samples.append([el, str(f["id"]), str(v["margin"]), str(v["margin_cause"]), float(v["fall_s"]), str(one["margin"]), str(one["margin_cause"]),
					float(wars[k])])
			next_sample = SAMPLE_EVERY_S if next_sample == 0.0 else next_sample + SAMPLE_EVERY_S
	var safe := 0
	var safe_broke: Array = []
	var war_fell: Array = []
	for smp in samples:
		if smp[2] == "safe":
			safe += 1
			var at := float(retaken.get(smp[1], INF))
			if at > float(smp[0]) and at <= float(smp[0]) + AHEAD_S:
				# the WAR from the sample until the garrison's last break began (the retake less break_s, sample
				# j taken at j × WAR_EVERY_S + one substep): a drop after that came with the fall, not before it
				var series: PackedFloat64Array = war_t[smp[1]]
				var low := INF
				var until := at - float(s._cfgs["realm"]["hold"]["break_s"]) - step
				for j in range(int(float(smp[0]) / WAR_EVERY_S), mini(series.size(), int(floorf(until / WAR_EVERY_S)) + 1)):
					low = minf(low, series[j])
				var line := "%s at %.0f s (WAR %.2f), retaken %.0f s later (its WAR fell to %.2f)" % [smp[1], smp[0], smp[7], at - float(smp[0]), low]
				(war_fell if low < FLOW_DROP * float(smp[7]) else safe_broke).append(line)
	return {"samples": samples, "retaken": retaken, "safe": safe, "safe_broke": safe_broke, "war_fell": war_fell}


## The report lines for one start: the counts by word (train and one-wave), with what happened next.
func _report(name: String, r: Dictionary) -> Array:
	var out: Array = []
	var samples: Array = r["samples"]
	var retaken: Dictionary = r["retaken"]
	out.append("  [margin_truth] %s: %d samples, retaken %s" % [name, samples.size(), str(retaken)])
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
