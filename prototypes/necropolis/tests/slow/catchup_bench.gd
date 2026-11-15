extends RefCounted
## The catch-up's budget (IDLE §4 Budget, E2b-2 T3.3b): 12 h in under 2 s and 7 days in under 10 s on this
## machine, field steps included, through the real runner (Catchup, as cmd_load runs it). Run with
## tests/run.sh --slow --only=catchup_bench (a few minutes). Wall clock is printed, never asserted.
## - Starts: midgame_2flips, pre_vei and fresh (convergence.gd's: cmd_new_game(1) run 10 min), each saved
##   once to JSON with the shipped configs (the full 128 × 90 field) and loaded into a fresh GameState
##   for every run, so every run starts bit-identical. The load's own field pre-warm isn't timed.
## - Each run is the catch-up of 12 h and of 7 d, run one core step per chunk (chunking never changes the
##   result) so each chunk is timed: the chunks that made a field call carry its cost, which is their time
##   less the run's median core-step chunk. Best of RUNS by total, with the load average beside it.
## - Also: a default chunk's wall time at each start (idle.catchup_steps_per_chunk; sized at about 50 ms at
##   pre_vei), and a view read after a chunk (view_fort of every held fort, the train's re-probe; T3.4b put
##   it at about 1.2 ms at midgame), median over a 12 h catch-up's chunks.

const STARTS := ["midgame_2flips", "pre_vei", "fresh"]
const SPANS := [43200.0, 604800.0]
const RUNS := 3
const BUDGET := {43200.0: 2.0, 604800.0: 10.0}

var t := TestUtil.new()


func run() -> int:
	t.suite("catchup_bench")
	var c = load("res://tests/slow/convergence.gd").new()
	print("  [catchup_bench] load average: %s" % c._loadavg())
	var lines: Array = ["  [catchup_bench] the catch-up through the runner, best of %d (s; core = core steps and the runner, field = the field steps)" % RUNS,
		"  | start | span | steps | field calls | total s | core s | field s | µs / core step | ms / field call | budget s | load average |",
		"  |---|---|---|---|---|---|---|---|---|---|---|"]
	var worst := {}
	for st in STARTS:
		var js: String = c.start_json(st)
		for span in SPANS:
			var best := {}
			for i in RUNS:
				var r := _timed(js, span)
				if best.is_empty() or float(r["total"]) < float(best["total"]):
					best = r
					best["load"] = c._loadavg()
			worst[span] = maxf(float(worst.get(span, 0.0)), float(best["total"]))
			lines.append("  | %s | %s | %d | %d | %.2f | %.2f | %.2f | %.0f | %.2f | %.0f | %s |" % [st, _span(span), int(best["steps"]),
				int(best["calls"]), float(best["total"]), float(best["core"]), float(best["field"]), float(best["us_step"]),
				float(best["ms_call"]), float(BUDGET[span]), best["load"]])
	print("\n".join(PackedStringArray(lines)))
	for span in SPANS:
		print("  [catchup_bench] %s: worst start %.2f s against the %.0f s budget (%s)" % [_span(span), float(worst[span]),
			float(BUDGET[span]), "within" if float(worst[span]) <= float(BUDGET[span]) else "over, ×%.2f" % (float(worst[span]) / float(BUDGET[span]))])
	_chunks(c)
	_profile(c)
	return t.failures


func _span(s: float) -> String:
	return "12 h" if s < 86400.0 else "7 d"


func _state(js: String) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	t.ok(s.from_dict(JSON.parse_string(js))["ok"], "the start loads")
	return s


## One catch-up of `span` from `js`, one core step per chunk, each chunk timed.
func _timed(js: String, span: float) -> Dictionary:
	var s := _state(js)
	var cu := s._catchup
	cu.begin(s, span, true)
	var core: Array = []
	var field_chunks := 0
	var field_us := 0
	var total := 0
	while cu.active:
		var calls := cu.field_calls
		var u0 := Time.get_ticks_usec()
		cu.run(s, 1)
		var us := Time.get_ticks_usec() - u0
		total += us
		if cu.field_calls != calls:
			field_chunks += 1
			field_us += us
		else:
			core.append(us)
	core.sort()
	var med := float(core[int(core.size() / 2.0)]) if not core.is_empty() else 0.0
	var field := maxf(0.0, float(field_us) - med * field_chunks)
	t.ok(s.t == float(cu.end_t) and GameState.Ledger.error(s.ledger()) < 1e-6, "%s: done, the ledger balanced" % _span(span))
	return {"steps": cu.steps, "calls": cu.field_calls, "total": total / 1e6, "field": field / 1e6, "core": (total - field) / 1e6,
		"us_step": (total - field) / maxf(1.0, float(cu.steps)), "ms_call": field / 1000.0 / maxf(1.0, float(cu.field_calls))}


## A default chunk's wall time at each start, and a view read after a chunk (median over a 12 h catch-up).
func _chunks(c) -> void:
	var per := int(TestUtil.configs()["economy"]["idle"]["catchup_steps_per_chunk"])
	for st in STARTS:
		var s := _state(c.start_json(st))
		var cu := s._catchup
		cu.begin(s, 43200.0, true)
		var chunk: Array = []
		var view: Array = []
		var held: Array = []
		for f in s.realm.forts:
			if RealmSim.is_held(f):
				held.append(str(f["id"]))
		while cu.active:
			var u0 := Time.get_ticks_usec()
			cu.run(s, per)
			chunk.append(Time.get_ticks_usec() - u0)
			if not held.is_empty():
				var v0 := Time.get_ticks_usec()
				for id in held:
					s.view_fort(id)
				view.append(Time.get_ticks_usec() - v0)
		chunk.sort()
		view.sort()
		print("  [catchup_bench] %s: a chunk of %d core steps, median %.1f ms (max %.1f ms, %d chunks)%s" % [st, per,
			chunk[int(chunk.size() / 2.0)] / 1000.0, chunk[-1] / 1000.0, chunk.size(),
			"" if view.is_empty() else "; view_fort of the %d held forts after a chunk (the train's re-probe): median %.2f ms" % [
				held.size(), view[int(view.size() / 2.0)] / 1000.0]])


## Lever 1's profile (IDLE §4 Budget): a core step at 10 s from pre_vei and midgame_2flips, and its pieces,
## µs per call (median of 9 batches): TownSim's step and RealmSim's step (on copies of the state, the
## inputs the core step gives them), what GameState does around them, and the runner's next_event_s.
## The field is shrunk (the core step never touches it).
func _profile(c) -> void:
	for st in ["pre_vei", "midgame_2flips"]:
		var js: String = JSON.stringify(c.load_state(c.start_json(st)).to_dict())
		var base: GameState = c.load_state(js)
		for i in 30:
			base._core_step(10.0)  # into the run, off the load
		var at := JSON.stringify(base.to_dict())
		var core := _batches(func(s: GameState) -> void: s._core_step(10.0), c, at)
		var town := _batches(func(s: GameState) -> void:
			var w: float = s._mint(s.town_sim.pits(), float(s.town_sim.rates.get("feed", 0.0))) * float(s.valve["work"])
			s.town_sim.step(10.0, s._town_inputs(w * 10.0)), c, at)
		var realm := _batches(func(s: GameState) -> void: s.realm.step(10.0, s._realm_inputs), c, at)
		var inputs := _batches(func(s: GameState) -> void: s._town_inputs(1.0), c, at, 50)
		var dq := _batches(func(s: GameState) -> void: s.digest_q(), c, at, 50)
		var mint := _batches(func(s: GameState) -> void: s._mint(3, 0.5), c, at, 50)
		var slew := _batches(func(s: GameState) -> void: s._slewed_valve(10.0), c, at, 50)
		var tiers := _batches(func(s: GameState) -> void: BuildRules.rise_tiers(s), c, at, 50)
		var queue := _batches(func(s: GameState) -> void: BuildRules.process_queue(s), c, at, 50)
		var flows := _batches(func(s: GameState) -> void: s._note_realm_flows(10.0, 0.0), c, at, 50)
		var readout := _batches(func(s: GameState) -> void: s._update_readout(10.0, 1.0, 1.0), c, at, 50)
		var ev := _batches(func(s: GameState) -> void: Catchup.next_event_s(s), c, at, 50)
		var req := _batches(func(s: GameState) -> void: s._req_f("realm.q.q0"), c, at, 200)
		print("  [catchup_bench] profile, %s at 10 s (µs per call): core step %.0f = TownSim.step %.0f + RealmSim.step %.0f + GameState's %.0f; of GameState's: _town_inputs %.1f, digest_q %.1f, _mint %.1f, the slew %.1f, rise_tiers %.1f, process_queue %.1f, _note_realm_flows %.1f, _update_readout %.1f; the runner's next_event_s %.1f; one _req_f %.2f" % [
			st, core, town, realm, core - town - realm, inputs, dq, mint, slew, tiers, queue, flows, readout, ev, req])


## µs per call of `f` on a copy of the state `js`: the median of 9 batches of `per` calls, each batch on a
## fresh copy (f may move the state; a batch of a moving f times its first `per` steps from there).
func _batches(f: Callable, c, js: String, per := 20) -> float:
	var out: Array = []
	for b in 9:
		var s: GameState = c.load_state(js)
		var u0 := Time.get_ticks_usec()
		for i in per:
			f.call(s)
		out.append(float(Time.get_ticks_usec() - u0) / per)
	out.sort()
	return out[4]
