class_name InfluenceField
extends RefCounted
## Necrosis influence grid. Two scalar layers (green = UNDEAD, orange = LIVING)
## plus a signed entrenchment layer: the longer a side dominates a cell, the
## faster it gains there (necrosis growth); opposing pressure erodes the
## entrenchment before it flips the territory. Not literal Gray-Scott — the
## organic look comes from diffusion + contest + the renderer's banding.
##
## Time-sliced, `lag_ticks` (L) late at every budget (STATE-API §3 step 9, §5.6):
## - Each tick j queues a job: step the field by dt from (result of job j-1 + the injects made
##   since tick j-1). That is exactly the E1 chain, so result j equals E1's field after tick j.
## - advance(budget_cells) computes queued jobs, in order, into their own buffers: at most that many
##   cells per call (0 = all queued work). It never touches the live arrays.
## - tick j publishes result j-L (finishing any of it still owed, synchronously) and replays the
##   injects made since onto it. So the arrays sim code reads (dominance_at, view_field) are always
##   the field as of L ticks ago plus every inject since, whatever the budget or frame cadence. The
##   budget is a cost setting only.
## - L = 2 because GameState runs the field ticks in pairs inside one substep: lag 1 would make the
##   second tick of a pair compute the first's job on the spot. One substep of lag is invisible to
##   sim code (nothing reads the field between the two ticks of a pair).
## - flush() computes and publishes everything queued; nothing stays in flight. The next L ticks
##   after a flush have nothing new to publish (the lag starting again).
##
## Catch-up (IDLE §4) steps the field with catchup_step(dt) instead: one call stands for dt seconds
## of live ticks, at any dt, for about the cost of one live tick (see catchup_step).

var w := 128
var h := 90
var green := PackedFloat32Array()
var orange := PackedFloat32Array()
var entrench := PackedFloat32Array()  # + entrenched green, - entrenched orange
var world_size := Vector2(2048, 1440)
var cfg := {}
## Cells the last advance() call computed (tests and readouts; never sim input).
var last_advance_cells := 0

var _lag := 2
var _n := 0  # ticks so far
var _pub_n := 0  # the tick whose result the live arrays hold (0 = the setup state)
var _head_n := 0  # the last tick whose job is computed
var _head: Array = []  # [g, o, e] result of tick _head_n: the next job's base
var _ticks := {}  # tick j > _pub_n -> {dt, seg}: seg = the injects made before tick j (since tick j-1)
var _results := {}  # tick j in (_pub_n, _head_n] -> [g, o, e], computed but not yet published
var _open: Array = []  # injects since the last tick: the next tick's seg
# The job being computed (tick _job_n; 0 = none): its input, its output, its constants, its progress.
var _job_n := 0
var _next := 0
var _k := {}
var _in_g := PackedFloat32Array()
var _in_o := PackedFloat32Array()
var _in_e := PackedFloat32Array()
var _out_g := PackedFloat32Array()
var _out_o := PackedFloat32Array()
var _out_e := PackedFloat32Array()
# catch-up scratch (catchup_step), reused between calls; never state: each call rebuilds them
var _c_phi := PackedFloat32Array()  # the signed field green - orange being solved
var _c_ig := PackedFloat32Array()  # one live period's injects, green
var _c_io := PackedFloat32Array()  # ... orange
var _c_src := PackedByteArray()  # 1: the cell or a 4-neighbour has an inject; 2: a grid edge cell
var _c_slo := PackedInt32Array()  # per row, the span of the cells marked 1 in _c_src
var _c_shi := PackedInt32Array()
## Cells catchup_step's last call updated, summed over its sweeps (tests and readouts only).
var last_catchup_cells := 0
## The injects catchup_step's last call consumed (its sources, in order), for overlay_in_flight.
var last_catchup_injects: Array = []
## catchup_step's ticks per call are capped here (1e15 ticks is about 6e6 years): long past every
## mode's relaxation, it keeps the tick counts finite (dt = INF) and their int casts in range.
const MAX_TICKS := 1e15


func setup(cfg_in: Dictionary, world_size_in: Vector2) -> void:
	cfg = cfg_in
	w = int(cfg.get("w", 128))
	h = int(cfg.get("h", 90))
	_lag = maxi(1, int(cfg.get("lag_ticks", 2)))
	if float(cfg.get("decay", 0.012)) <= 0.0 and float(cfg.get("diffuse", 0.16)) <= 0.0:
		push_error("field: decay and diffuse are both 0; catchup_step's local solve divides by their sum")
	world_size = world_size_in
	green.resize(w * h)
	orange.resize(w * h)
	entrench.resize(w * h)
	green.fill(0.0)
	orange.fill(0.0)
	entrench.fill(0.0)
	_n = 0
	_pub_n = 0
	_head_n = 0
	_head = [green.duplicate(), orange.duplicate(), entrench.duplicate()]
	_ticks = {}
	_results = {}
	_open = []
	_job_n = 0
	_next = 0
	last_advance_cells = 0


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(pos.x / world_size.x * w), 0, w - 1),
		clampi(int(pos.y / world_size.y * h), 0, h - 1))


## Writes the live arrays now, so dominance_at sees it at once, and records it for the next tick's
## job (whose input is the previous result plus these injects, in order).
func inject(pos: Vector2, is_green: bool, amount: float, radius := 1) -> void:
	_apply_inject(false, pos, is_green, amount, radius)
	_open.append([pos, is_green, amount, radius])


## One inject onto the live arrays, or onto the job's input (`to_input`). Same arithmetic either way.
func _apply_inject(to_input: bool, pos: Vector2, is_green: bool, amount: float, radius: int) -> void:
	var c := cell_of(pos)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := c.x + dx
			var y := c.y + dy
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var fall := 1.0 / (1.0 + dx * dx + dy * dy)
			var i := y * w + x
			if to_input:
				if is_green:
					_in_g[i] = minf(4.0, _in_g[i] + amount * fall)
				else:
					_in_o[i] = minf(4.0, _in_o[i] + amount * fall)
			elif is_green:
				green[i] = minf(4.0, green[i] + amount * fall)
			else:
				orange[i] = minf(4.0, orange[i] + amount * fall)


## Computes queued field work, in order, at most `budget_cells` cells (0 = all of it). Work units,
## not time: sim code never reads the clock. Publishing happens only inside tick() and flush().
func advance(budget_cells: int) -> void:
	last_advance_cells = _work(budget_cells if budget_cells > 0 else -1)


## Computes and publishes everything queued; nothing stays in flight. Called once after the pre-warm
## on new game and on load (and at the end of catch-up), so the published field is complete there.
func flush() -> void:
	if _n > _pub_n:
		_work(-1)
		_publish(_n)


func tick(dt: float) -> void:
	_n += 1
	_ticks[_n] = {"dt": dt, "seg": _open}
	_open = []
	var target := _n - _lag
	if target > _pub_n:
		_work(-1, target)
		_publish(target)


## Catch-up's field step (IDLE §4): dt seconds of live ticks, as if the injects made since the last
## tick or step were made before every one of them. Any dt > 0, stable and finite at every dt; dt <= 0
## changes nothing and leaves the injects queued.
##
## Cadence (agreed with economy): catch-up calls this once per *field step*, about 150 per catch-up,
## with dt = the catch-up time run since the previous call. Right before each call it runs
## _inject_sources(1.0 / field.tick_hz) once: ONE live period's sources, as they stand at that
## moment. The core steps between two calls make no injects; injects must not pile up across core
## steps, because the call reads them as one period's worth and repeats them dt * tick_hz times.
## _update_towns can read the result straight after.
##
## It finishes any queued live work first and publishes its result at once: in_flight() is 0 after
## it, dominance_at and view_field read the new field, and the lag pipeline restarts as after
## flush(), so live tick() / advance() carry on as usual afterwards. A pure function of (field state,
## injects, dt, config): no clock, no RNG, nothing carried between calls, so the way catch-up is
## chunked can't change it. The live path (tick, advance, flush) is untouched by it.
##
## Method. The live tick with fixed sources is a map T, and dt seconds are n = dt * tick_hz of it.
## Its contest (above 1 per tick) leaves every cell one colour, so the step solves one signed value per
## cell. Each cell's target is the backward-Euler blend, in tick units, of its value at the start of
## the step toward its own fixed point of T given its neighbours, found exactly piece by piece (green
## holds, orange holds, or both are wiped out). n is stretched to n_eff so the slowest mode (decay)
## relaxes exactly, and a large dt reaches T's fixed point. Red-black sweeps over-relax toward the
## targets (by field.catchup_omega, never across zero), no more sweeps than half the step's ticks (a
## sweep carries a change two cells, a live tick one):
## - field.catchup_sweeps base sweeps over each row's live span (cells beyond field.catchup_eps, plus
##   the inject cells; rows +-1, dilated 2). Each cell update also takes the entrench layer's exact
##   closed form for n / catchup_sweeps ticks at the target's dom. Cells no base sweep reaches are
##   within eps of zero: their entrench takes live's decay toward 0 for the n ticks.
## - then up to field.catchup_extra_sweeps extra sweeps over only the cells the previous sweep moved
##   by more than field.catchup_extra_tol (a front still moving after a fort flips). An extra sweep
##   pushes entrench toward the dominant side only, never decays it, and pushes by none of the base
##   ramp for steps up to field.catchup_extra_ramp_ticks[0] ticks and all of it from [1] up: the
##   fronts' creep that a held-dom ramp misses matters only once a step is long enough to finish it.
## A step of up to field.catchup_exact_ticks ticks is that many live ticks instead (exact; backward
## Euler reaches too far over a few ticks), plus one solve for what is left of a tick; so it costs
## them. Assumes the shipped contest (contest * 5 / tick_hz >= 1) and inject amounts >= 0. Tests:
## test_field_catchup.gd; cost and owner agreement with live ticks: tests/slow/field_catchup_bench.gd.
func catchup_step(dt: float) -> void:
	last_catchup_cells = 0
	last_catchup_injects = []  # a step that changes nothing has nothing to overlay
	if not (dt > 0.0):
		return
	last_catchup_injects = _open.duplicate()
	var period := 1.0 / float(cfg.get("tick_hz", 5.0))
	var n := minf(dt / period, MAX_TICKS)
	var whole := int(floor(n + 1e-9))
	if whole < 1 or n > float(cfg.get("catchup_exact_ticks", 8)):
		_solve(dt)
		return
	# a short step: its whole ticks are live ticks (exact), the rest of a tick one solve
	var injs := _open.duplicate()
	for k in whole:
		if k > 0:
			for r in injs:
				inject(r[0], r[1], r[2], r[3])
		tick(period)
	flush()
	var frac := n - float(whole)
	if frac > 1e-6:
		for r in injs:
			inject(r[0], r[1], r[2], r[3])
		_solve(frac * period)


## The live arrays as live play reads them after a catchup_step: live play publishes a result lag_ticks
## old with the ticks still in flight re-applied on top (_publish), so dominance_at at an inject cell
## carries lag_ticks periods of its injects. catchup_step publishes its bare result (as after flush()),
## and where both colours inject the contest wipes that result, so a village there would read none
## although live play reads it for the stronger inject (E4: the I1 test's Bellwether, in Covington's
## cell). This re-applies the last step's injects lag_ticks times, in order, onto the live arrays only
## (green and orange; _apply_inject's arithmetic, capped at 4 as live's), never onto the pipeline's base
## (_head), so the next tick or step is unchanged. GameState's catch-up calls it after each field step,
## before it reads the village owners.
func overlay_in_flight() -> void:
	for k in _lag:
		for r in last_catchup_injects:
			_apply_inject(false, r[0], r[1], r[2], r[3])


## The solve behind catchup_step: dt seconds in one go (any dt > 0).
func _solve(dt: float) -> void:
	_work(-1)  # the queued live work, so the base is the chain's latest result
	var cells := w * h
	var w1 := w - 1
	var h1 := h - 1
	var bg: PackedFloat32Array = _head[0]
	var bo: PackedFloat32Array = _head[1]
	var e: PackedFloat32Array = (_head[2] as PackedFloat32Array).duplicate()
	_c_ig.resize(cells)
	_c_io.resize(cells)
	_c_src.resize(cells)
	_c_ig.fill(0.0)
	_c_io.fill(0.0)
	_c_src.fill(0)
	_c_slo.resize(h)
	_c_shi.resize(h)
	_c_slo.fill(w)
	_c_shi.fill(-1)
	for r in _open:
		_stamp(r[0], r[1], r[2], r[3])
	var ig_ := _c_ig
	var io_ := _c_io
	var src := _c_src
	var period := 1.0 / float(cfg.get("tick_hz", 5.0))
	var k5 := period * 5.0
	var n := minf(dt / period, MAX_TICKS)
	var d := float(cfg.get("diffuse", 0.16)) * k5
	var kk := clampf(1.0 - float(cfg.get("decay", 0.012)) * k5, 1e-6, 1.0)
	var con := float(cfg.get("contest", 1.35)) * k5
	var er := float(cfg.get("entrench_rate", 0.025)) * k5
	var em := float(cfg.get("entrench_max", 2.5))
	var ed := clampf(float(cfg.get("entrench_decay", 0.08)) * k5, 0.0, 1.0)
	var sweeps := maxi(1, int(cfg.get("catchup_sweeps", 1)))
	# a red-black sweep carries a change two cells and a live tick one: a short step gets no more
	# sweeps than half its ticks, so it spreads a change no faster than the ticks it stands for
	var extra := clampi(int(ceil(n * 0.5)) - sweeps, 0, maxi(0, int(cfg.get("catchup_extra_sweeps", 10))))
	var tol := float(cfg.get("catchup_extra_tol", 0.02))
	var om := float(cfg.get("catchup_omega", 1.85))
	var eps := float(cfg.get("catchup_eps", 0.003))
	var xr: Array = cfg.get("catchup_extra_ramp_ticks", [300.0, 1500.0])
	var lam := -log(kk)  # decay per tick: the slowest mode's rate
	var nn := n if lam < 1e-9 else (exp(minf(n * lam, 28.0)) - 1.0) / lam  # n_eff
	var m := n / float(sweeps)  # entrench ticks per base-sweep update
	var edp := pow(1.0 - ed, m)
	# an extra sweep's push, in ticks: none for steps up to xr[0] ticks, all of m from xr[1] up
	var mx := m * clampf((n - float(xr[0])) / maxf(1.0, float(xr[1]) - float(xr[0])), 0.0, 1.0)
	var inv2er := 0.5 / er if er > 0.0 else INF
	# the grid's edge cells take the general path (2: it clamps neighbour indices); 1 = next to an inject
	for x in w:
		if src[x] == 0:
			src[x] = 2
		if src[h1 * w + x] == 0:
			src[h1 * w + x] = 2
	for y in h:
		if src[y * w] == 0:
			src[y * w] = 2
		if src[y * w + w1] == 0:
			src[y * w + w1] = 2
	_c_phi.resize(cells)
	var phi := _c_phi
	var lo := PackedInt32Array()
	var hi := PackedInt32Array()
	lo.resize(h)
	hi.resize(h)
	for i in cells:
		phi[i] = bg[i] - bo[i]
	# live spans: each row's first and last cell beyond eps, scanned in from both ends, joined with
	# the row's inject cells
	for y in h:
		var row := y * w
		var a := 0
		while a < w and absf(phi[row + a]) <= eps:
			a += 1
		var b := w1
		while b > a and absf(phi[row + b]) <= eps:
			b -= 1
		if a == w:
			b = -1
		if _c_slo[y] <= _c_shi[y]:
			a = mini(a, _c_slo[y])
			b = maxi(b, _c_shi[y])
		lo[y] = a
		hi[y] = b
	var x0 := phi.duplicate()
	var kq := kk * 0.25
	var ra := PackedInt32Array()
	var rb := PackedInt32Array()
	var ua := PackedInt32Array()
	var ub := PackedInt32Array()
	ra.resize(h)
	rb.resize(h)
	ua.resize(h)
	ub.resize(h)
	ua.fill(w)
	ub.fill(-1)
	var mlo := PackedInt32Array()  # per row, the cells the last sweep moved by more than tol
	var mhi := PackedInt32Array()
	mlo.resize(h)
	mhi.resize(h)
	var ba := PackedInt32Array()  # per row, the base sweeps' reach
	var bb := PackedInt32Array()
	ba.resize(h)
	bb.resize(h)
	ba.fill(w)
	bb.fill(-1)
	var done := 0
	for s in sweeps + extra:
		var base := s < sweeps
		# a base sweep covers rows y-1..y+1's live spans, an extra sweep their moving spans; dilated 2
		var sl_ := lo if base else mlo
		var sh_ := hi if base else mhi
		var rows := 0
		for y in h:
			var a := w
			var b := -1
			for yy in range(maxi(0, y - 1), mini(h, y + 2)):
				if sh_[yy] >= 0:
					a = mini(a, sl_[yy])
					b = maxi(b, sh_[yy])
			if b >= 0:
				a = maxi(0, a - 2)
				b = mini(w1, b + 2)
				done += b - a + 1
				rows += 1
				ua[y] = mini(ua[y], a)
				ub[y] = maxi(ub[y], b)
				if base:
					ba[y] = mini(ba[y], a)
					bb[y] = maxi(bb[y], b)
			ra[y] = a
			rb[y] = b
		if rows == 0:
			break
		if base:
			lo.fill(w)
			hi.fill(-1)
		mlo.fill(w)
		mhi.fill(-1)
		for par in 2:
			for y in h:
				var a := ra[y]
				var b := rb[y]
				if b < a:
					continue
				var row := y * w
				var rlo := w
				var rhi := -1
				var mvlo := w
				var mvhi := -1
				for x in range(a + ((a + y + par) & 1), b + 1, 2):
					var i := row + x
					var p := phi[i]
					var ei := e[i]
					var dg := d * (1.0 + ei) if ei > 0.0 else d
					var dq := d * (1.0 - ei) if ei < 0.0 else d
					var x0v := x0[i]
					var tgt := 0.0
					var dom := 0.0
					var sr := src[i]
					if sr == 0:
						# interior, no inject at the cell or its neighbours
						var sg := 0.0
						var so := 0.0
						var v := phi[i - 1]
						if v > 0.0:
							sg += v
						else:
							so -= v
						v = phi[i + 1]
						if v > 0.0:
							sg += v
						else:
							so -= v
						v = phi[i - w]
						if v > 0.0:
							sg += v
						else:
							so -= v
						v = phi[i + w]
						if v > 0.0:
							sg += v
						else:
							so -= v
						var g0t := kq * dg * sg
						var o0t := kq * dq * so
						var xs := 0.0
						var den := 1.0 - kk + kk * dg
						var xg := (g0t - con * o0t) / den
						if xg > 0.0:
							xs = xg
						else:
							den = 1.0 - kk + kk * dq
							var xo := (o0t - con * g0t) / den
							if xo > 0.0:
								xs = -xo
							else:
								den = 1.0
						var wv := nn * den
						tgt = (x0v + wv * xs) / (1.0 + wv)
						dom = g0t - o0t + kk * tgt * ((1.0 - dg) if tgt > 0.0 else (1.0 - dq))
					else:
						# next to an inject, or on the grid's edge: inputs are value + inject, capped
						# at 4 (the live _apply_inject); off-grid neighbours read the cell itself
						var jl := i - 1 if x > 0 else i
						var jr := i + 1 if x < w1 else i
						var ju := i - w if y > 0 else i
						var jd := i + w if y < h1 else i
						var vl := phi[jl]
						var vr := phi[jr]
						var vu := phi[ju]
						var vd := phi[jd]
						var ag := (minf(4.0, maxf(vl, 0.0) + ig_[jl]) + minf(4.0, maxf(vr, 0.0) + ig_[jr])
							+ minf(4.0, maxf(vu, 0.0) + ig_[ju]) + minf(4.0, maxf(vd, 0.0) + ig_[jd])) * 0.25
						var ao := (minf(4.0, maxf(-vl, 0.0) + io_[jl]) + minf(4.0, maxf(-vr, 0.0) + io_[jr])
							+ minf(4.0, maxf(-vu, 0.0) + io_[ju]) + minf(4.0, maxf(-vd, 0.0) + io_[jd])) * 0.25
						var ig := ig_[i]
						var io := io_[i]
						var g0t := kk * (minf(4.0, ig) * (1.0 - dg) + dg * ag)
						var o0t := kk * (minf(4.0, io) * (1.0 - dq) + dq * ao)
						var sg := kk * (1.0 - dg)
						var xg := (sg * ig + kk * dg * ag - con * o0t) / (1.0 - sg)
						if xg + ig > 4.0:
							xg = minf(4.0, kk * (4.0 * (1.0 - dg) + dg * ag) - con * o0t)
							sg = 0.0
						var so := kk * (1.0 - dq)
						var xo := (so * io + kk * dq * ao - con * g0t) / (1.0 - so)
						if xo + io > 4.0:
							xo = minf(4.0, kk * (4.0 * (1.0 - dq) + dq * ao) - con * g0t)
							so = 0.0
						var xs := 0.0
						var sl := 0.0
						# both can hold where both sides inject: the cell keeps its side
						if xg > 0.0 and (p >= 0.0 or xo <= 0.0):
							xs = xg
							sl = sg
						elif xo > 0.0:
							xs = -xo
							sl = so
						var wv := nn * (1.0 - sl)
						tgt = (x0v + wv * xs) / (1.0 + wv)
						if tgt > 0.0:
							dom = kk * (minf(4.0, tgt + ig) * (1.0 - dg) + dg * ag) - o0t
						elif tgt < 0.0:
							dom = g0t - kk * (minf(4.0, -tgt + io) * (1.0 - dq) + dq * ao)
						else:
							dom = g0t - o0t
					var np := p + om * (tgt - p)
					if np * tgt <= 0.0 or tgt * p <= 0.0:
						np = tgt
					if np > 4.0:
						np = 4.0
					elif np < -4.0:
						np = -4.0
					phi[i] = np
					if np - p > tol or p - np > tol:
						if mvlo == w:
							mvlo = x
						mvhi = x
					# entrench: the live update's closed form for m ticks at the target's dom. An extra
					# sweep only pushes it toward the dominant side, by mx ticks, and never decays it
					var mr := m if base else mx
					if mr > 0.0:
						if dom > 0.05:
							if ei < em:
								if ei >= 0.0:
									ei = minf(em, ei + mr * er * minf(1.0, dom))
								else:
									var t0 := -ei * inv2er
									ei = ei + 2.0 * er * mr if mr <= t0 else minf(em, (mr - t0) * er * minf(1.0, dom))
								e[i] = ei
						elif dom < -0.05:
							if ei > -em:
								if ei <= 0.0:
									ei = maxf(-em, ei - mr * er * minf(1.0, -dom))
								else:
									var t1 := ei * inv2er
									ei = ei - 2.0 * er * mr if mr <= t1 else maxf(-em, -(mr - t1) * er * minf(1.0, -dom))
								e[i] = ei
						elif base and ei != 0.0:
							e[i] = ei * edp
					if np > eps or np < -eps or sr == 1:
						if rlo == w:
							rlo = x
						rhi = x
				if base:
					if rlo < lo[y]:
						lo[y] = rlo
					if rhi > hi[y]:
						hi[y] = rhi
				if mvlo < mlo[y]:
					mlo[y] = mvlo
				if mvhi > mhi[y]:
					mhi[y] = mvhi
	# the cells no base sweep reached sit within eps of zero, where the live tick lerps entrench
	# toward 0 every tick: they take n ticks of that (left alone, an old front's entrench would outlive
	# the front for the whole catch-up and speed the next one)
	var edn := pow(1.0 - ed, n)
	for y in h:
		var row := y * w
		var a := ba[y]
		var b := bb[y]
		for x in (range(0, w) if b < 0 else range(0, a)):
			if e[row + x] != 0.0:
				e[row + x] *= edn
		if b >= 0:
			for x in range(b + 1, w):
				if e[row + x] != 0.0:
					e[row + x] *= edn
	# only cells inside some sweep's range moved; the rest keep the base (both colours as they were)
	var ng := bg.duplicate()
	var no := bo.duplicate()
	for y in h:
		var row := y * w
		for x in range(ua[y], ub[y] + 1):
			var i := row + x
			var v := phi[i]
			if v > 0.0:
				ng[i] = v
				no[i] = 0.0
			else:
				ng[i] = 0.0
				no[i] = -v
	last_catchup_cells = done
	# restart the pipeline on the new result, published at once (as after flush)
	_n += 1
	_head = [ng, no, e]
	_head_n = _n
	_pub_n = _n
	_results = {}
	_ticks = {}
	_open = []
	green = ng.duplicate()
	orange = no.duplicate()
	entrench = e.duplicate()


## One inject's cells into the catch-up's per-period source arrays (the arithmetic of
## _apply_inject, uncapped: the solve caps value + inject at 4 the way the live input does). Marks
## the cells whose update reads an inject: the stamped cells and their 4-neighbours.
func _stamp(pos: Vector2, is_green: bool, amount: float, radius: int) -> void:
	var c := cell_of(pos)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := c.x + dx
			var y := c.y + dy
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var i := y * w + x
			var a := amount * (1.0 / (1.0 + dx * dx + dy * dy))
			if is_green:
				_c_ig[i] += a
			else:
				_c_io[i] += a
			_c_src[i] = 1
			for yy in range(maxi(0, y - 1), mini(h, y + 2)):
				_c_slo[yy] = mini(_c_slo[yy], maxi(0, x - 1))
				_c_shi[yy] = maxi(_c_shi[yy], mini(w - 1, x + 1))
			if x > 0:
				_c_src[i - 1] = 1
			if x < w - 1:
				_c_src[i + 1] = 1
			if y > 0:
				_c_src[i - w] = 1
			if y < h - 1:
				_c_src[i + w] = 1


## Ticks whose result isn't published yet (0 after a flush).
func in_flight() -> int:
	return _n - _pub_n


## Cells of queued work not yet computed.
func queued_cells() -> int:
	return (_n - _head_n) * w * h - (_next if _job_n != 0 else 0)


## Computes up to `budget` cells (-1 = unlimited) of queued jobs, through tick `upto` at most
## (default: all ticks so far). Returns the cells computed.
func _work(budget: int, upto := -1) -> int:
	var last := _n if upto < 0 else mini(upto, _n)
	var done := 0
	while budget < 0 or done < budget:
		if _job_n > last:  # a job past `upto` waits for its own tick or advance()
			break
		if _job_n == 0:
			if _head_n >= last:
				break
			_start_job(_head_n + 1)
		var n := w * h - _next
		if budget >= 0:
			n = mini(n, budget - done)
		_compute(n)
		done += n
		if _next >= w * h:
			_finish_job()
	return done


func _start_job(j: int) -> void:
	var dt: float = _ticks[j]["dt"]
	_k = {
		"d": float(cfg.get("diffuse", 0.16)) * dt * 5.0,
		"decay": float(cfg.get("decay", 0.012)) * dt * 5.0,
		"contest": float(cfg.get("contest", 1.35)) * dt * 5.0,
		"e_rate": float(cfg.get("entrench_rate", 0.025)) * dt * 5.0,
		"e_max": float(cfg.get("entrench_max", 2.5)),
		"e_decay": float(cfg.get("entrench_decay", 0.08)) * dt * 5.0,
	}
	_in_g = (_head[0] as PackedFloat32Array).duplicate()
	_in_o = (_head[1] as PackedFloat32Array).duplicate()
	_in_e = _head[2]  # read only
	for r in _ticks[j]["seg"]:
		_apply_inject(true, r[0], r[1], r[2], r[3])
	_out_g = PackedFloat32Array()
	_out_o = PackedFloat32Array()
	_out_e = PackedFloat32Array()
	_out_g.resize(w * h)
	_out_o.resize(w * h)
	_out_e.resize(w * h)
	_job_n = j
	_next = 0


func _finish_job() -> void:
	_head = [_out_g, _out_o, _out_e]
	_head_n = _job_n
	_results[_job_n] = _head
	_out_g = PackedFloat32Array()
	_out_o = PackedFloat32Array()
	_out_e = PackedFloat32Array()
	_in_g = PackedFloat32Array()
	_in_o = PackedFloat32Array()
	_in_e = PackedFloat32Array()
	_job_n = 0
	_next = 0


## The live arrays become a copy of result `j`, plus every inject made since tick j, in order. A
## copy: packed arrays held in Variants are shared by reference, and result j may still be the next
## job's base.
func _publish(j: int) -> void:
	var r: Array = _results[j]
	green = (r[0] as PackedFloat32Array).duplicate()
	orange = (r[1] as PackedFloat32Array).duplicate()
	entrench = (r[2] as PackedFloat32Array).duplicate()
	for m in range(j + 1, _n + 1):
		for inj in _ticks[m]["seg"]:
			_apply_inject(false, inj[0], inj[1], inj[2], inj[3])
	for inj in _open:
		_apply_inject(false, inj[0], inj[1], inj[2], inj[3])
	for m in range(_pub_n + 1, j + 1):
		_results.erase(m)
		_ticks.erase(m)
	_pub_n = j


## The field step for `n` cells of the current job from _next, reading its input and writing its
## output. Same arithmetic, in the same order, as E1's unsliced step, so any slicing is bit-identical.
func _compute(n: int) -> void:
	var d: float = _k["d"]
	var decay: float = _k["decay"]
	var contest: float = _k["contest"]
	var e_rate: float = _k["e_rate"]
	var e_max: float = _k["e_max"]
	var e_decay: float = _k["e_decay"]
	var g0 := _in_g
	var o0 := _in_o
	var e0 := _in_e
	var ng := _out_g
	var no := _out_o
	var ne := _out_e
	var i := _next
	var end := _next + n
	while i < end:
		@warning_ignore("integer_division")
		var y := i / w
		var row := y * w
		var x1 := mini(w, end - row)
		for x in range(i - row, x1):
			i = row + x
			var gl := g0[i - 1] if x > 0 else g0[i]
			var gr := g0[i + 1] if x < w - 1 else g0[i]
			var gu := g0[i - w] if y > 0 else g0[i]
			var gd := g0[i + w] if y < h - 1 else g0[i]
			var ol := o0[i - 1] if x > 0 else o0[i]
			var orr := o0[i + 1] if x < w - 1 else o0[i]
			var ou := o0[i - w] if y > 0 else o0[i]
			var od := o0[i + w] if y < h - 1 else o0[i]

			var e := e0[i]
			# entrenchment multiplies how fast the entrenched side flows/grows here
			var g_mult := 1.0 + maxf(0.0, e)
			var o_mult := 1.0 + maxf(0.0, -e)
			var g := g0[i] + d * g_mult * ((gl + gr + gu + gd) * 0.25 - g0[i])
			var o := o0[i] + d * o_mult * ((ol + orr + ou + od) * 0.25 - o0[i])
			g *= 1.0 - decay
			o *= 1.0 - decay
			# contest: opposing influence annihilates
			var clash := minf(g, o) * contest
			g -= clash
			o -= clash
			# entrenchment: dominance deepens, opposition erodes it first
			var dom := g - o
			if dom > 0.05:
				e = minf(e_max, e + e_rate * minf(1.0, dom)) if e >= 0.0 else e + e_rate * 2.0
			elif dom < -0.05:
				e = maxf(-e_max, e - e_rate * minf(1.0, -dom)) if e <= 0.0 else e - e_rate * 2.0
			else:
				e = lerpf(e, 0.0, e_decay)
			ng[i] = clampf(g, 0.0, 4.0)
			no[i] = clampf(o, 0.0, 4.0)
			ne[i] = e
		i = row + x1
	_next = end


func dominance_at(pos: Vector2) -> float:
	var c := cell_of(pos)
	var i := c.y * w + c.x
	return green[i] - orange[i]


func entrench_at(pos: Vector2) -> float:
	var c := cell_of(pos)
	return entrench[c.y * w + c.x]
