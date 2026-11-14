extends RefCounted
## What capping the influence field does to village owners (E2b T3.0, IDLE §4): 12 h with no input
## from midgame_2flips, core steps at 0.5 s throughout, the shipped field (128 × 90). Run with
## tests/run.sh --slow --only=field_cap (about 8 min on jenova: the reference ticks the field 86 400
## times).
## - reference: the field injected and ticked every 0.5 s, at dt 0.5 (owners updated each tick);
## - capped at the step: CAP_TICKS ticks spread evenly, each at the elapsed dt (12 h / CAP_TICKS),
##   which is what IDLE §4's "the field ticks once per catch-up step with that step's dt" gives under
##   a cap;
## - capped at the live period: the same ticks, each at the live 1 / field.tick_hz.
## Each capped tick is flushed (published at once). Owners are compared every SAMPLE_S, village by
## village; owners feed TownSim's migrants, so Covington's living is compared too.

const HOURS := 12.0
const CAP_TICKS := 144
const SAMPLE_S := 300.0
const START := "midgame_2flips"


func run() -> int:
	var t := TestUtil.new()
	t.suite("field_cap")
	var base := GameState.new(TestUtil.configs())
	base.debug_enabled = true
	t.ok(base.cmd_debug_load_fixture(START)["ok"], "%s loads" % START)
	var js := JSON.stringify(base.to_dict())
	var period := 1.0 / float(TestUtil.configs()["realm"]["field"]["tick_hz"])
	var every := HOURS * 3600.0 / CAP_TICKS
	var u0 := Time.get_ticks_usec()
	var ref := _run(js, 0.5, 0.5, false)
	var ref_s := float(Time.get_ticks_usec() - u0) / 1e6
	u0 = Time.get_ticks_usec()
	var big := _run(js, every, every, true)
	var big_s := float(Time.get_ticks_usec() - u0) / 1e6
	u0 = Time.get_ticks_usec()
	var live := _run(js, every, period, true)
	var live_s := float(Time.get_ticks_usec() - u0) / 1e6
	var lines: Array = ["  [field_cap] %s, %.0f h, no input, core at 0.5 s; village owners every %.0f s vs the field ticked every 0.5 s" % [START, HOURS, SAMPLE_S],
		"  | run | field ticks | tick dt s | owners matching | samples with green_towns off | non-finite dominance | end green_towns | end town living | wall s |",
		"  |---|---|---|---|---|---|---|---|---|"]
	for row in [["every 0.5 s (reference)", ref, 0.5, ref_s], ["capped, elapsed dt", big, every, big_s], ["capped, live dt", live, period, live_s]]:
		var r: Dictionary = row[1]
		var m := _match(ref, r)
		lines.append("  | %s | %d | %.1f | %.1f%% | %d / %d | %d | %d | %.2f | %.1f |" % [row[0], int(r["ticks"]), row[2], m[0] * 100.0,
			int(m[1]), (r["owners"] as Array).size(), int(r["nan"]), int(r["green"][-1]), float(r["living"][-1]), row[3]])
	lines.append("  owners at the end: reference %s · capped elapsed %s · capped live %s" % [str(ref["owners"][-1]), str(big["owners"][-1]), str(live["owners"][-1])])
	print("\n".join(PackedStringArray(lines)))
	t.ok(int(ref["ticks"]) == int(HOURS * 7200.0) and int(big["ticks"]) == CAP_TICKS, "the reference ticked every 0.5 s; the capped runs %d times" % CAP_TICKS)
	return t.failures


## 12 h of core steps at 0.5 s from `js`; every `every` s the field is injected for `tick_dt` and
## ticked once at `tick_dt` (flushed when `flush`), then the owners are updated. Samples owners,
## green_towns and Covington's living every SAMPLE_S.
func _run(js: String, every: float, tick_dt: float, flush: bool) -> Dictionary:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.from_dict(JSON.parse_string(js))
	var owners: Array = []
	var green: Array = []
	var living: Array = []
	var ticks := 0
	var nan := 0
	var n := int(HOURS * 7200.0)
	var per_tick := int(round(every / 0.5))
	var per_sample := int(round(SAMPLE_S / 0.5))
	for i in n:
		s._core_step(0.5)
		if (i + 1) % per_tick == 0:
			s._inject_sources(tick_dt)
			s.field.tick(tick_dt)
			if flush:
				s.field.flush()
			s._update_towns(s._cfg())
			ticks += 1
		if (i + 1) % per_sample == 0:
			var o: Array = []
			for tw in s.towns:
				o.append(tw["control"])
				if not is_finite(float(s.field.dominance_at(tw["pos"]))):
					nan += 1
			owners.append(o)
			green.append(s.green_towns)
			living.append(s.town_sim.living)
			s.drain_events()
	return {"owners": owners, "green": green, "living": living, "ticks": ticks, "nan": nan}


## [the share of village-samples whose owner matches the reference, samples whose green_towns differ].
static func _match(ref: Dictionary, r: Dictionary) -> Array:
	var same := 0
	var all := 0
	var off := 0
	for i in (ref["owners"] as Array).size():
		for j in (ref["owners"][i] as Array).size():
			all += 1
			if ref["owners"][i][j] == r["owners"][i][j]:
				same += 1
		if int(ref["green"][i]) != int(r["green"][i]):
			off += 1
	return [float(same) / maxf(1.0, float(all)), off]
