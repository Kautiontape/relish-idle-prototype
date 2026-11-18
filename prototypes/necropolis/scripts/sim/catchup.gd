class_name Catchup
extends RefCounted
## The catch-up runner (IDLE §4, E2b-2 T3.3b): the real time since a save, or a long gap in the open game,
## run through GameState's own core step (_core_step, the code live play runs) in adaptive, event-clipped
## steps. GameState owns one (`_catchup`) and resets it on a new game and every load; it holds no
## reference back (the state is passed in), so nothing cycles.
##
## - The step: dt = clamp(total_s / idle.catchup_max_steps, sim.substep_s, idle.catchup_dt_max_s), and past
##   the first idle.catchup_dt_long_after_s (12 h) of the catch-up the same with idle.catchup_dt_long_s (15
##   s) for the cap (the budget's lever 2: a week steps at 15 s from 12 h on), then shortened so it never
##   straddles a clip event (next_event_s): dt = min(dt, t_next_event − t). An event within CLIP_MIN_S of
##   now is taken as now (the step isn't shortened for it). The last step ends on t0 + total_s exactly.
## - The field (api-request #14): field_n field steps over the catch-up (idle.field_steps, fewer for a
##   short one so that none is under idle.field_step_min_s), each on the first core-step boundary at or
##   after its planned moment t0 + total_s · k / field_n, the last on the catch-up's end: one live period's
##   sources (GameState._inject_sources), then field.catchup_step(the seconds since the last field call),
##   then field.overlay_in_flight (the step's injects lag_ticks times on the published arrays, as live
##   play reads the field: E4, I1's village in a cell both colours inject), then the village owners
##   (GameState._update_towns). Nothing injects between field calls, and the catch-up ends with the field
##   published.
## - Chunks: run() advances at most `max_steps` core steps per call. The step sequence and the field
##   steps' moments depend only on (the state at begin(), total_s, the configs), so chunking never changes
##   the result.
## - Events: with `report`, each chunk's events move out of the scenes' queue into `events` (with their
##   t) for the away report; without it they stay queued as live. A load's catch-up and an open-game gap of
##   idle.report_min_s or more report; a shorter gap queues. At a reporting catch-up's end the report is built
##   (GameState._report_away: StateViews.away_report from `before`, taken at begin, the state then and
##   `events`) and its away_report event queued (E2b-2 T3.3c).
## - The presentation step doesn't run inside it: at the end the lanes' callouts take the net change once
##   (GameState._note_lane_causes) and the field accumulator is reset.

## A clip event this close to now is now: the step isn't shortened for it (the convergence harness's
## threshold, kept so its tables are unchanged).
const CLIP_MIN_S := 1e-6
## Phase I P3 (ruling 3's hold timeout): build_start_s's clip lands this far past a held head's hold end, so the float
## sum of the step's start and its length is at or past it (BuildRules.held_out's >=) and the skip isn't a step late.
const HOLD_EPS_S := 1e-6

var active := false
var report := true  ## events go to `events`, not the queue
var capped := false  ## the elapsed time was above idle.catchup_max_s (cmd_load, or an open-game gap: GameState.tick)
var t0 := 0.0  ## the sim time the catch-up started at
var total_s := 0.0  ## whole seconds it runs
var end_t := 0.0  ## t0 + total_s
var dt := 0.0  ## the base step
var dt_long := 0.0  ## the base step past idle.catchup_dt_long_after_s
var long_after_s := 0.0  ## idle.catchup_dt_long_after_s
var steps := 0  ## core steps run so far
var field_n := 0  ## field steps planned
var field_k := 0  ## planned moments passed
var field_calls := 0  ## field.catchup_step calls made
var field_last_t := 0.0  ## the sim time of the last field call (t0 before the first)
## The events a report replaces ([{t, type, ...}], in queue order): the last reporting catch-up's.
var events: Array = []
## The buildings the Thrift stance idled and resumed during the last reporting catch-up, in order: [[t, lot_id,
## idled]] (GameState._note_thrift, E3-1), for the away report's Thrift lines (IDLE §7). Not events: Thrift raises
## none (a building it idles reads state "idle" in view_town).
var thrift_log: Array = []
## The frames' own sim seconds while a chunked catch-up is active (GameState.tick adds them; they run
## once it is done). Session only.
var frame_acc := 0.0
## With `report`: what the catch-up started from, for the away report's before-and-after
## (StateViews.away_before; E2b-2 T3.3c).
var before := {}
## Tests: when an Array, each core step appends [t at its start, its length, next_event_s before it].
var trace: Variant = null
var _last_evs: Array = []  # the last core step's realm events (the lanes' callouts at the end)


## Starts a catch-up of `seconds` (whole seconds) from the state now. `with_report`: its events are
## collected for the report instead of queued. A catch-up of 0 s doesn't start.
func begin(gs: GameState, seconds: float, with_report: bool) -> void:
	active = seconds > 0.0
	report = with_report
	capped = false  # (cmd_load and the gap path in GameState.tick set it after begin)
	t0 = gs.t
	total_s = maxf(0.0, seconds)
	end_t = t0 + total_s
	dt = base_dt(gs, total_s)
	dt_long = base_dt(gs, total_s, true)
	long_after_s = gs._req_f("economy.idle.catchup_dt_long_after_s")
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
		thrift_log = []
		before = StateViews.away_before(gs) if active else {}


## The base step for a catch-up of `seconds`: clamp(seconds / idle.catchup_max_steps, sim.substep_s,
## idle.catchup_dt_max_s), or with `long` (past idle.catchup_dt_long_after_s) idle.catchup_dt_long_s for the
## cap.
static func base_dt(gs: GameState, seconds: float, long := false) -> float:
	var n := gs._req_f("economy.idle.catchup_max_steps")
	var cap := gs._req_f("economy.idle.catchup_dt_long_s" if long else "economy.idle.catchup_dt_max_s")
	return clampf(seconds / n if n > 0.0 else INF, gs.substep_s(), cap)


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
	var done := false
	while active and (max_steps < 1 or n < max_steps):
		var left := end_t - gs.t
		var h := minf(dt_long if gs.t - t0 >= long_after_s else dt, left)
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
			done = true
	if report:
		events.append_array(gs._events.slice(mark))
		gs._events.resize(mark)
		if done:  # the away report (IDLE §7, T3.3c): built at the end, its event queued after the collection
			gs._report_away(before, events, total_s, capped)
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
	gs.field.overlay_in_flight()  # the owners read the field as live play does (its in-flight injects on top)
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
## - Relish's respawn while she is dead (her dead_s_left; E3-2), so a save closed while she is dead wakes her at the
##   right moment, and the stance slot and Vigil follow from there;
## - an unpaid building's hold ending (its unpaid_s);
## - a construction finishing (TownSim.construction_left's eta_s: the work left over its builders' rate);
## - the build queue's head waiting on funds starting: (cost − stock) / net income for each currency it
##   lacks, the later of them, while every one of those nets is positive (the last step's TownSim rates,
##   before the cap's clip: BuildRules.queue_net, affordable_in_s's; build_start_s).
##   A gated entry starts on a tier rise or a building finishing, which are clipped already;
## - gold or bone reaching its floor (stock / −net, while the stock is above 1 and the net negative);
## - the tithe: its warning (next_s − tithe.warning_s), a wave starting (next_s) and a wave ending
##   (its s_left);
## - a simulacrum running out of charges (E3-4: simulacrum_out_s, guarded);
## - a tended vat filling (Phase I P2, the run's manager's ruling 4, Q-c: vat_fill_s), so a ready clone gives its tend
##   hand back at the moment it fills, as live play's 0.5 s substeps do, not up to one catch-up step late (IDLE §8).
## A grace ending, a garrison reaching 0 and a break are solved inside RealmSim's step, and the store
## caps inside TownSim's, so they aren't clipped. tests/slow/convergence.gd's harness clips with this.
static func next_event_s(gs: GameState) -> float:
	var e := INF
	if gs.relish["state"] == "travelling":
		e = minf(e, maxf(0.0, gs._dist_to(gs.relish["target"]) - GameState.ARRIVE_EPS) / gs.travel_speed())
	elif gs.relish["state"] == "dead" and float(gs.relish["dead_s_left"]) > 0.0:
		e = minf(e, float(gs.relish["dead_s_left"]))  # her respawn (E3-2)
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
	e = minf(e, BuildRules.grow_start_s(gs))  # (Phase I P3) the Grow stance's pick becoming affordable
	var r := gs.realm
	var ti: Dictionary = r.tithe
	if bool(ti.get("started", false)):
		var ns := float(ti["next_s"])
		var warn := gs._tithe_warning_s
		if (ti["warning"] as Dictionary).is_empty() and ns - warn > 0.0:
			e = minf(e, ns - warn)
		if ns > 0.0:
			e = minf(e, ns)
		var wv: Dictionary = ti["wave"]
		if not wv.is_empty() and float(wv["s_left"]) > 0.0:
			e = minf(e, float(wv["s_left"]))
	if not r.simulacra.is_empty():
		e = minf(e, simulacrum_out_s(gs))
	if not gs.vats_staffed.is_empty():
		e = minf(e, vat_fill_s(gs))
	return e


## The seconds until the first tended vat fills (Phase I P2, ruling 4; MECHANICS §7), INF when none is tended. A vat
## grows linearly at vats.grow_per_s × its hands (TownSim.vat_hands: the staffing the next core step grows it on), so
## it fills at (1 − grow) / (grow_per_s × hands). The step that ends there must reach 1 exactly (GameState._grow_vats
## clamps at 1), or the vat sits a hair under it, keeps its hand, and fills inside the next step, a whole step late
## again: so a projection whose product falls short of 1 in floats is moved 1e-9 s later (grow_per_s × hands × 1e-9 is
## far above one ulp of 1, and the step then overshoots the fill by a nanosecond).
static func vat_fill_s(gs: GameState) -> float:
	var hands := gs.town_sim.vat_hands()
	var e := INF
	for i in hands.size():
		var h := float(hands[i])
		if h <= 0.0:
			continue
		var g := float(gs.vats_grow[i]) if i < gs.vats_grow.size() else 0.0
		if g >= 1.0:
			continue
		var p := gs._grow_per_s * h
		if not (p > 0.0):
			continue
		var at := (1.0 - g) / p
		if g + p * at < 1.0:
			at += 1e-9
		e = minf(e, at)
	return e


## The seconds until the first simulacrum runs out of charges (E3-4, IDLE §4), INF when none is clipped. RealmSim
## spreads a step's raise evenly over it (min(rate, charges / dt)), so a simulacrum running out inside a 15 s step
## raised its last charges over the whole step: its fort's undead read +8.5% at that step's end against live play
## (test_crafting). A step ends at the moment instead: charges / rate, a lower bound, since the raise never passes
## the rate (an early clip only splits a step, and the next projects again). Two guards:
## - corpses: only while the fort's dead now cover every raise wanted there until then (Relish's, where she
##   redirects, and each live simulacrum's there, up to its charges). A corpse-limited raise runs out later than
##   charges / rate, and a starved simulacrum would cut every step short for the rest of a week; such a one is not
##   clipped, and its last raise spreads over its step as Relish's corpse-limited raise does;
## - a floor: none under sim.substep_s, live play's own granularity, so a sliver of charges left doesn't make ever
##   shorter steps.
static func simulacrum_out_s(gs: GameState) -> float:
	var r := gs.realm
	var redirect: String = gs._relish_effects()["redirect_fort"]
	var e := INF
	for sm in r.simulacra:
		var rate := float(sm["rate"])
		var c := float(sm["charges"])
		if not (rate > 0.0 and c > 0.0):
			continue
		var at := c / rate
		if at < gs.substep_s() or at >= e:
			continue
		var fid := str(sm["fort_id"])
		var f := r.fort_by_id(fid)
		if f.is_empty():
			continue
		var want := gs._raise_rate * at if redirect == fid else 0.0
		for o in r.simulacra:
			if str(o["fort_id"]) == fid and float(o["charges"]) > 0.0:
				want += minf(float(o["charges"]), maxf(0.0, float(o["rate"])) * at)
		if float(f["dead"]) >= want:
			e = at
	return e


## The seconds until the build queue's head waiting on funds can pay (see next_event_s), INF when no
## entry waits on funds or a currency it lacks isn't growing. The core step's processing leaves that head
## with waited_on no_gold or no_bone (BuildRules.process_queue; the entries queued behind it take the
## same, so the head is the first), and the stocks at a step boundary are those its walk read. F1: the net
## is affordable_in_s's, BuildRules.queue_net (the income before the cap's clip, less the upkeep), so the two
## never drift: below the cap it is the HUD's in − out exactly; at a full store, where that clips to 0, an
## entry ahead that spent the store this step has brought the income back.
## Phase I P3 (ruling 3): a head with no path to its funds is skipped with the same no_gold or no_bone
## (BuildRules.head_never: a dry store whose producer has no staffed hands, or one that has read dry for
## queue.never_hold_s), so the first such entry may be one that never starts: it is passed over here too, and the
## head is the first that isn't. A dry head still held returns the seconds to its hold's end (BuildRules.hold_left_s,
## plus HOLD_EPS_S so the float sum lands past it): the entries behind it may start then.
static func build_start_s(gs: GameState) -> float:
	var q: Array = gs.build_queue
	var levels: Array = []
	var ts := gs.town_sim
	var nets := {}
	for i in q.size():
		var w := str(q[i].get("waited_on", ""))
		if w != "no_gold" and w != "no_bone":
			continue
		if levels.is_empty():
			levels = BuildRules.queue_levels(gs, q)
			nets = BuildRules.queue_net(gs)
		var e: Dictionary = q[i]
		var cost := BuildRules.construction_cost(gs, str(e["building_id"]), int(levels[i]))
		var at := 0.0
		var dry := ""
		for k in ["gold", "bone"]:
			var lack := float(cost[k]) - (ts.gold if k == "gold" else ts.bone)
			if lack > 0.0:
				var net := float(nets[k])
				if not (net > 0.0):
					at = INF
					dry = k
					break
				at = maxf(at, lack / net)
		if at < INF:
			return at
		# a head whose dry store's producer is staffed holds the queue until its hold timeout runs out (BuildRules.
		# head_never, held_out): the step ends just past that, so the walk that skips it runs when a live one would
		if not BuildRules.head_never(gs, e, dry):
			return BuildRules.hold_left_s(gs, e) + HOLD_EPS_S
	return INF
