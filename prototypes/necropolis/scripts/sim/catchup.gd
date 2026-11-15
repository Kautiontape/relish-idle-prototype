class_name Catchup
extends RefCounted
## The catch-up runner (IDLE §4, E2b-2 T3.3b): the real time since a save, or a long gap in the open game,
## run through GameState's own core step (_core_step, the code live play runs) in adaptive, event-clipped
## steps. GameState owns one (`_catchup`) and resets it on a new game and every load; it holds no
## reference back (the state is passed in), so nothing cycles.
##
## - The step: dt = clamp(total_s / idle.catchup_max_steps, sim.substep_s, idle.catchup_dt_max_s), then
##   shortened so it never straddles a clip event (next_event_s): dt = min(dt, t_next_event − t). An
##   event within CLIP_MIN_S of now is taken as now (the step isn't shortened for it). The last step ends
##   on t0 + total_s exactly.
## - The field (api-request #14): field_n field steps over the catch-up (idle.field_steps, fewer for a
##   short one so that none is under idle.field_step_min_s), each on the first core-step boundary at or
##   after its planned moment t0 + total_s · k / field_n, the last on the catch-up's end: one live period's
##   sources (GameState._inject_sources), then field.catchup_step(the seconds since the last field call),
##   then the village owners (GameState._update_towns). Nothing injects between field calls, and the
##   catch-up ends with the field published.
## - Chunks: run() advances at most `max_steps` core steps per call. The step sequence and the field
##   steps' moments depend only on (the state at begin(), total_s, the configs), so chunking never changes
##   the result.
## - Events: with `report`, each chunk's events move out of the scenes' queue into `events` (with their
##   t) for the away report (T3.3c); without it they stay queued as live. A load's catch-up and an
##   open-game gap of idle.report_min_s or more report; a shorter gap queues.
## - The presentation step doesn't run inside it: at the end the lanes' callouts take the net change once
##   (GameState._note_lane_causes) and the field accumulator is reset.

## A clip event this close to now is now: the step isn't shortened for it (the convergence harness's
## threshold, kept so its tables are unchanged).
const CLIP_MIN_S := 1e-6

var active := false
var report := true  ## events go to `events`, not the queue
var capped := false  ## the elapsed time was above idle.catchup_max_s (cmd_load)
var t0 := 0.0  ## the sim time the catch-up started at
var total_s := 0.0  ## whole seconds it runs
var end_t := 0.0  ## t0 + total_s
var dt := 0.0  ## the base step
var steps := 0  ## core steps run so far
var field_n := 0  ## field steps planned
var field_k := 0  ## planned moments passed
var field_calls := 0  ## field.catchup_step calls made
var field_last_t := 0.0  ## the sim time of the last field call (t0 before the first)
## The events a report replaces ([{t, type, ...}], in queue order): the last reporting catch-up's.
var events: Array = []
## The frames' own sim seconds while a chunked catch-up is active (GameState.tick adds them; they run
## once it is done). Session only.
var frame_acc := 0.0
## Tests: when an Array, each core step appends [t at its start, its length, next_event_s before it].
var trace: Variant = null
var _last_evs: Array = []  # the last core step's realm events (the lanes' callouts at the end)


## Starts a catch-up of `seconds` (whole seconds) from the state now. `with_report`: its events are
## collected for the report instead of queued. A catch-up of 0 s doesn't start.
func begin(gs: GameState, seconds: float, with_report: bool) -> void:
	active = seconds > 0.0
	report = with_report
	t0 = gs.t
	total_s = maxf(0.0, seconds)
	end_t = t0 + total_s
	dt = base_dt(gs, total_s)
	steps = 0
	field_k = 0
	field_calls = 0
	field_last_t = t0
	var min_s := gs._req_f("economy.idle.field_step_min_s")
	var most := int(gs._req_f("economy.idle.field_steps"))
	field_n = clampi(int(floor(total_s / min_s)) if min_s > 0.0 else most, 1, maxi(1, most))
	frame_acc = 0.0
	_last_evs = []
	if with_report:
		events = []


## The base step for a catch-up of `seconds`: clamp(seconds / idle.catchup_max_steps, sim.substep_s,
## idle.catchup_dt_max_s).
static func base_dt(gs: GameState, seconds: float) -> float:
	var n := gs._req_f("economy.idle.catchup_max_steps")
	return clampf(seconds / n if n > 0.0 else INF, gs.substep_s(), gs._req_f("economy.idle.catchup_dt_max_s"))


## Seconds of the catch-up run so far.
func done_s(gs: GameState) -> float:
	return clampf(gs.t - t0, 0.0, total_s) if active else total_s


## Runs at most `max_steps` core steps (all that are left when `max_steps` < 1). Returns the steps run.
## Finishes the catch-up when its last step is done.
func run(gs: GameState, max_steps := -1) -> int:
	if not active:
		return 0
	var mark: int = gs._events.size()  # this chunk's events start here (commands can't run inside a chunk)
	var n := 0
	while active and (max_steps < 1 or n < max_steps):
		var left := end_t - gs.t
		var h := minf(dt, left)
		var last := h >= left
		var e := next_event_s(gs)
		if e > CLIP_MIN_S and e < h:
			h = e
			last = false
		if trace is Array:
			(trace as Array).append([gs.t, h, e])
		if h > 0.0:
			_last_evs = gs._core_step(h)
			gs.rev += 1
			steps += 1
			n += 1
		if last:
			gs.t = end_t  # (already exact: the last step is end_t − t, and t ≥ end_t / 2)
		_field_steps(gs, last)
		if last:
			_finish(gs)
	if report:
		events.append_array(gs._events.slice(mark))
		gs._events.resize(mark)
	return n


## The field steps due at this core-step boundary (see the header): one call for every planned moment
## passed, and the last on the end.
func _field_steps(gs: GameState, last: bool) -> void:
	var due := false
	while field_k < field_n and (gs.t >= t0 + total_s * float(field_k + 1) / float(field_n) or last):
		field_k += 1
		due = true
	if not due:
		return
	var tick_hz := float(gs._cfg().get("field", {}).get("tick_hz", 5.0))
	gs._inject_sources(1.0 / tick_hz)
	gs.field.catchup_step(gs.t - field_last_t)
	gs._update_towns(gs._cfg())
	field_last_t = gs.t
	field_calls += 1


func _finish(gs: GameState) -> void:
	active = false
	gs._note_lane_causes(_last_evs)  # the net change's callouts, once (the presentation step's)
	gs._field_acc = 0.0
	_last_evs = []


## The seconds from now to the next moment a catch-up step must not straddle (IDLE §4), INF when none
## is pending. The events, each projected from the state now:
## - Relish's arrival (her distance less GameState.ARRIVE_EPS over relish.travel_speed);
## - an unpaid building's hold ending (its unpaid_s);
## - a construction finishing (TownSim.construction_left's eta_s: the work left over its builders' rate);
## - the build queue's head waiting on funds starting: (cost − stock) / net income for each currency it
##   lacks, the later of them, while every one of those nets is positive (the last step's TownSim rates).
##   A gated entry starts on a tier rise or a building finishing, which are clipped already;
## - gold or bone reaching its floor (stock / −net, while the stock is above 1 and the net negative);
## - the tithe: its warning (next_s − tithe.warning_s), a wave starting (next_s) and a wave ending
##   (its s_left).
## A grace ending, a garrison reaching 0 and a break are solved inside RealmSim's step, and the store
## caps inside TownSim's, so they aren't clipped. tests/slow/convergence.gd's harness clips with this.
static func next_event_s(gs: GameState) -> float:
	var e := INF
	if gs.relish["state"] == "travelling":
		e = minf(e, maxf(0.0, gs._dist_to(gs.relish["target"]) - GameState.ARRIVE_EPS) / gs.travel_speed())
	var ts := gs.town_sim
	for lot in ts.buildings:
		var b: Dictionary = ts.buildings[lot]
		if b["state"] == "unpaid":
			if float(b["unpaid_s"]) > 0.0:
				e = minf(e, float(b["unpaid_s"]))
		elif b["state"] == "constructing":
			var eta := float(ts.construction_left(lot)["eta_s"])
			if eta > 0.0:
				e = minf(e, eta)
	for k in ["gold", "bone"]:
		var stock: float = ts.gold if k == "gold" else ts.bone
		var net := float(ts.rates[k]["in"]) - float(ts.rates[k]["out"])
		if stock > 1.0 and net < 0.0:
			e = minf(e, stock / -net)
	if not gs.build_queue.is_empty():
		e = minf(e, build_start_s(gs))
	var r := gs.realm
	var ti: Dictionary = r.tithe
	if bool(ti.get("started", false)):
		var ns := float(ti["next_s"])
		var warn := gs._req_f("realm.tithe.warning_s")
		if (ti["warning"] as Dictionary).is_empty() and ns - warn > 0.0:
			e = minf(e, ns - warn)
		if ns > 0.0:
			e = minf(e, ns)
		var wv: Dictionary = ti["wave"]
		if not wv.is_empty() and float(wv["s_left"]) > 0.0:
			e = minf(e, float(wv["s_left"]))
	return e


## The seconds until the build queue's head waiting on funds can pay (see next_event_s), INF when no
## entry waits on funds or a currency it lacks isn't growing. The core step's processing leaves that head
## with waited_on no_gold or no_bone (BuildRules.process_queue; the entries queued behind it take the
## same, so the head is the first), and the stocks at a step boundary are those its walk read.
static func build_start_s(gs: GameState) -> float:
	var q: Array = gs.build_queue
	var head := -1
	for i in q.size():
		var w := str(q[i].get("waited_on", ""))
		if w == "no_gold" or w == "no_bone":
			head = i
			break
	if head < 0:
		return INF
	var e: Dictionary = q[head]
	var level: int = BuildRules.queue_levels(gs, q)[head]
	var cost := BuildRules.construction_cost(gs, str(e["building_id"]), level)
	var ts := gs.town_sim
	var at := 0.0
	for k in ["gold", "bone"]:
		var lack := float(cost[k]) - (ts.gold if k == "gold" else ts.bone)
		if lack > 0.0:
			var net := float(ts.rates[k]["in"]) - float(ts.rates[k]["out"])
			if not (net > 0.0):
				return INF
			at = maxf(at, lack / net)
	return at
