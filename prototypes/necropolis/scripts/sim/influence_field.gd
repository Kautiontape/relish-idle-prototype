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


func setup(cfg_in: Dictionary, world_size_in: Vector2) -> void:
	cfg = cfg_in
	w = int(cfg.get("w", 128))
	h = int(cfg.get("h", 90))
	_lag = maxi(1, int(cfg.get("lag_ticks", 2)))
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
