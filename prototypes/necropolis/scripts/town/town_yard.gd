extends Control
## The Covington yard — a live diorama in the graveshift mold (stations as
## labeled circles, worker dots walking loops), but PRESENTATIONAL ONLY: the
## real economy ticks in the Game autoload. This just animates one green dot
## per assigned worker on a cosmetic station<->supply loop, loiters the idle
## pool by the Slab, ambles a few living traders past the Trading Post, and
## trundles the gather convoy in/out at the yard edge. It reads assignment
## counts live off the TownLogic every frame; it owns no numbers.

signal station_clicked(task: String)

const COL_UNDEAD := Color("#39FF9E")
const COL_LIVING := Color("#FF6A2B")
const COL_DEAD := Color("#6E6A7E")
const COL_VIOLET := Color("#C04CFF")
const COL_TEXT := Color("#E8E8EC")
const COL_DIM := Color("#8888A0")
const COL_GROUND := Color("#0E0E12")
const COL_ROAD := Color("#1A1A21")

var logic: TownLogic = null
var cfg := {}
var seed_data := {}
var rng := RandomNumberGenerator.new()

var dots := {}                 # task -> Array[Dictionary]; also key "idle"
var living: Array = []
var convoy := {}               # {t, phase, wait, alpha}
var highlight_task := ""
var highlight_t := 0.0
var _anim_t := 0.0
var _specks: Array = []        # normalized ground texture points
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	rng.randomize()
	var srng := RandomNumberGenerator.new()
	srng.seed = 1337
	for i in 70:
		_specks.append(Vector2(srng.randf(), srng.randf()))


func bind(logic_: TownLogic, seed_data_: Dictionary, cfg_: Dictionary) -> void:
	logic = logic_
	seed_data = seed_data_.duplicate(true)
	cfg = cfg_
	for t in TownLogic.TASKS:
		dots[t] = []
	dots["idle"] = []
	living.clear()
	convoy = {"t": 0.0, "wait": 0.0, "alpha": 1.0}
	set_process(true)


func highlight(task: String) -> void:
	highlight_task = task
	highlight_t = 1.6


# ------------------------------------------------------------------ config ---
func _y(key: String, def):
	return (cfg.get("yard", {}) as Dictionary).get(key, def)


func _stations() -> Dictionary:
	return _y("stations", {})


func _station_pos(id: String) -> Vector2:
	var s: Dictionary = _stations().get(id, {})
	return _np(s.get("pos", [0.5, 0.5]))


func _station_r(id: String) -> float:
	var s: Dictionary = _stations().get(id, {})
	return float(s.get("r", 26.0))


func _supply_pos(task: String) -> Vector2:
	var sp: Dictionary = _y("supply_points", {})
	return _np(sp.get(task, [0.5, 0.5]))


func _np(arr) -> Vector2:
	if arr is Array and arr.size() >= 2:
		return Vector2(float(arr[0]) * size.x, float(arr[1]) * size.y)
	return size * 0.5


# ------------------------------------------------------------------ ticking --
func _process(delta: float) -> void:
	if logic == null or size.x < 100.0:
		return
	_anim_t += delta
	highlight_t = maxf(0.0, highlight_t - delta)
	_sync_counts()
	for task in dots:
		for d in dots[task]:
			if task == "idle":
				_tick_idle(d, delta)
			else:
				_tick_worker(d, delta)
	_tick_living(delta)
	_tick_convoy(delta)
	queue_redraw()


func _sync_counts() -> void:
	for t in TownLogic.TASKS:
		_match_count(t, int(logic.assignments.get(t, 0)))
	_match_count("idle", logic.idle_undead)
	var want := int(_y("living_count", 3))
	while living.size() < want:
		living.append(_mk_living())
	while living.size() > want:
		living.pop_back()


func _match_count(task: String, want: int) -> void:
	var arr: Array = dots[task]
	while arr.size() < want:
		arr.append(_mk_dot(task))
	while arr.size() > want:
		arr.pop_back()


func _mk_dot(task: String) -> Dictionary:
	var speed := float(_y("walk_speed", 44.0)) + rng.randf_range(-1.0, 1.0) * float(_y("walk_jitter", 14.0))
	if task == "idle":
		var slab := _station_pos("slab")
		var w := float(_y("idle_wander_px", 56.0))
		var p := slab + Vector2(rng.randf_range(-w, w), rng.randf_range(-w, w))
		return {"task": task, "pos": p, "target": p, "state": "wait", "timer": rng.randf_range(0.2, 1.8), "speed": speed * 0.6}
	# Spawn scattered along the loop so the yard looks mid-shift immediately.
	var a := _jitter(_station_pos(task), 10.0)
	var b := _jitter(_supply_pos(task), 10.0)
	var d := {
		"task": task,
		"pos": a.lerp(b, rng.randf()),
		"target": b,
		"state": ["to_a", "work_a", "to_b", "work_b"][rng.randi_range(0, 3)],
		"timer": rng.randf_range(0.3, 1.5),
		"speed": speed,
	}
	if d["state"] == "to_a" or d["state"] == "work_a":
		d["target"] = a
	return d


func _jitter(p: Vector2, r: float) -> Vector2:
	return p + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r))


func _work_time() -> float:
	return rng.randf_range(float(_y("work_min_s", 0.8)), float(_y("work_max_s", 2.0)))


func _tick_worker(d: Dictionary, dt: float) -> void:
	var task: String = String(d.get("task", "slab"))
	match String(d["state"]):
		"to_a":
			if _step(d, dt):
				d["state"] = "work_a"
				d["timer"] = _work_time()
		"work_a":
			d["timer"] = float(d["timer"]) - dt
			if float(d["timer"]) <= 0.0:
				d["state"] = "to_b"
				d["target"] = _jitter(_supply_pos(task), 10.0)
		"to_b":
			if _step(d, dt):
				d["state"] = "work_b"
				d["timer"] = _work_time()
		"work_b":
			d["timer"] = float(d["timer"]) - dt
			if float(d["timer"]) <= 0.0:
				d["state"] = "to_a"
				d["target"] = _jitter(_station_pos(task), _station_r(task) * 0.5)
		_:
			d["state"] = "to_a"
			d["target"] = _jitter(_station_pos(task), 10.0)


func _tick_idle(d: Dictionary, dt: float) -> void:
	if _step(d, dt):
		d["timer"] = float(d["timer"]) - dt
		if float(d["timer"]) <= 0.0:
			var w := float(_y("idle_wander_px", 56.0))
			d["target"] = _station_pos("slab") + Vector2(rng.randf_range(-w, w), rng.randf_range(-w, w))
			d["timer"] = rng.randf_range(0.8, 2.6)


func _step(d: Dictionary, dt: float) -> bool:
	var to: Vector2 = (d["target"] as Vector2) - (d["pos"] as Vector2)
	var dist := to.length()
	if dist <= float(_y("reach_px", 3.0)):
		return true
	var step := float(d["speed"]) * dt
	d["pos"] = (d["pos"] as Vector2) + to / dist * minf(step, dist)
	return false


# --------------------------------------------------------- living traders ----
func _mk_living() -> Dictionary:
	var p := _jitter(_supply_pos("trade"), 26.0)
	return {"pos": p, "target": p, "timer": rng.randf_range(0.0, 2.0)}


func _tick_living(dt: float) -> void:
	var sp := float(_y("living_walk_speed", 22.0))
	for l in living:
		var to: Vector2 = (l["target"] as Vector2) - (l["pos"] as Vector2)
		var d := to.length()
		if d <= 5.0:
			l["timer"] = float(l["timer"]) - dt
			if float(l["timer"]) <= 0.0:
				var anchor := _station_pos("trade") if rng.randf() < 0.5 else _supply_pos("trade")
				l["target"] = _jitter(anchor, 30.0)
				l["timer"] = rng.randf_range(1.4, 4.0)
		else:
			l["pos"] = (l["pos"] as Vector2) + to / d * minf(sp * dt, d)


# ------------------------------------------------------------------ convoy ---
func _convoy_phase() -> String:
	return str((seed_data.get("gather", {}) as Dictionary).get("phase", "idle"))


func _tick_convoy(dt: float) -> void:
	var phase := _convoy_phase()
	if phase != "out" and phase != "back":
		return
	var path_len := _station_pos("gather").distance_to(_np(_y("exit_point", [0.03, 0.8])))
	var speed := float(_y("convoy_speed", 34.0)) / maxf(1.0, path_len)
	if float(convoy["wait"]) > 0.0:
		convoy["wait"] = float(convoy["wait"]) - dt
		convoy["alpha"] = clampf(float(convoy["alpha"]) - dt * 2.0, 0.0, 1.0)
		if float(convoy["wait"]) <= 0.0:
			convoy["t"] = 0.0
			convoy["alpha"] = 1.0
		return
	convoy["t"] = float(convoy["t"]) + speed * dt
	if float(convoy["t"]) >= 1.0:
		convoy["t"] = 1.0
		convoy["wait"] = 2.2


func _convoy_pos() -> Vector2:
	var camp := _station_pos("gather")
	var exit := _np(_y("exit_point", [0.03, 0.8]))
	var t := float(convoy["t"])
	if _convoy_phase() == "out":
		return camp.lerp(exit, t)
	return exit.lerp(camp, t)


# ------------------------------------------------------------------ drawing --
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_GROUND)
	if logic == null:
		return
	for sp in _specks:
		draw_circle(Vector2(sp.x * size.x, sp.y * size.y), 1.4, Color("#16161c"))
	_draw_roads()
	_draw_body_pile()
	# Dots go under the station rings/labels so text stays legible; the
	# translucent fills read as workers stepping inside the buildings.
	_draw_convoy()
	var lr := float(_y("living_r", 3.5))
	for l in living:
		draw_circle(l["pos"], lr + 1.2, Color(0, 0, 0, 0.6))
		draw_circle(l["pos"], lr, COL_LIVING)
	_draw_workers()
	for id in ["forge", "jobs", "trade", "gather"]:
		_draw_station(id)
	_draw_slab()
	_draw_vats()
	if logic.station_built():
		_draw_station("sim")
	_draw_highlight()
	draw_string(_font, Vector2(12, 20), "the factory yard", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_DIM)


func _draw_roads() -> void:
	for pair in _y("roads", []):
		if not (pair is Array) or pair.size() < 2:
			continue
		if String(pair[1]) == "sim" and not logic.station_built():
			continue
		draw_line(_station_pos(String(pair[0])), _station_pos(String(pair[1])), COL_ROAD, 3.0)
	# gather road to the yard edge (the convoy route)
	draw_line(_station_pos("gather"), _np(_y("exit_point", [0.03, 0.8])), COL_ROAD, 3.0)


func _draw_station(id: String) -> void:
	var s: Dictionary = _stations().get(id, {})
	var pos := _station_pos(id)
	var r := _station_r(id)
	var col := Color.html(str(s.get("color", "#888888")))
	draw_circle(pos, r, Color(col.r, col.g, col.b, 0.16))
	draw_arc(pos, r, 0, TAU, 48, Color(col.r, col.g, col.b, 0.85), 2.0)
	_text_c(pos + Vector2(0, r + 14), str(s.get("label", id)), 12, Color("#c9c9d4"))
	var crew := int(logic.assignments.get(id, -1))
	if crew >= 0:
		_text_c(pos + Vector2(0, r + 28), "crew %d" % crew, 11, COL_UNDEAD if crew > 0 else COL_DIM)


func _draw_slab() -> void:
	var pos := _station_pos("slab")
	var r := _station_r("slab")
	var col := Color.html(str(_stations().get("slab", {}).get("color", "#7a6b96")))
	var pulse := 0.5 + 0.5 * sin(_anim_t * 2.0)
	draw_circle(pos, r, Color(col.r, col.g, col.b, 0.20))
	draw_arc(pos, r, 0, TAU, 64, Color(col.r, col.g, col.b, 0.9), 2.5)
	draw_arc(pos, r + 5.0 + 3.0 * pulse, 0, TAU, 64, Color(COL_VIOLET.r, COL_VIOLET.g, COL_VIOLET.b, 0.20 + 0.15 * pulse), 1.5)
	_text_c(pos + Vector2(0, -6), "THE SLAB", 14, COL_TEXT)
	_text_c(pos + Vector2(0, 10), "x%d" % int(logic.town["slabs"]), 13, COL_VIOLET)
	var crew := int(logic.assignments.get("slab", 0))
	_text_c(pos + Vector2(0, r + 19), "bodies become undead", 11, COL_DIM)
	_text_c(pos + Vector2(0, r + 33), "crew %d" % crew, 11, COL_UNDEAD if crew > 0 else COL_DIM)


func _draw_body_pile() -> void:
	var n := clampi(int(float((seed_data.get("res", {}) as Dictionary).get("bodies", 0.0)) / 2.0), 0, 9)
	if n <= 0:
		return
	var base := _supply_pos("slab")
	var prng := RandomNumberGenerator.new()
	prng.seed = 99
	for i in n:
		var p := base + Vector2(prng.randf_range(-10, 10), prng.randf_range(-7, 7))
		draw_circle(p, 2.6, COL_DEAD)
	_text_c(base + Vector2(0, 16), "the pile", 10, Color(COL_DEAD.r, COL_DEAD.g, COL_DEAD.b, 0.8))


func _draw_vats() -> void:
	var count := int(logic.town["vats"])
	if count <= 0:
		return
	var s: Dictionary = _stations().get("vats", {})
	var base := _station_pos("vats")
	var r := float(_y("vat_pod_r", 11.0))
	var spacing := float(_y("vat_pod_spacing", 30.0))
	var col := Color.html(str(s.get("color", "#5f8f7a")))
	for i in count:
		var p := base + Vector2(spacing * i, 0)
		draw_circle(p, r, Color(col.r, col.g, col.b, 0.18))
		draw_arc(p, r, 0, TAU, 24, Color(col.r, col.g, col.b, 0.8), 1.5)
		draw_circle(p, 3.0, Color(COL_VIOLET.r, COL_VIOLET.g, COL_VIOLET.b, 0.75))
	var mid := base + Vector2(spacing * (count - 1) * 0.5, 0)
	_text_c(mid + Vector2(0, r + 14), "%s x%d" % [str(s.get("label", "Clone Vats")), count], 11, Color("#c9c9d4"))


func _draw_convoy() -> void:
	var phase := _convoy_phase()
	if phase != "out" and phase != "back":
		return
	var p := _convoy_pos()
	var a := float(convoy["alpha"])
	draw_circle(p, 5.5, Color(0, 0, 0, 0.6 * a))
	draw_circle(p, 4.5, Color("#9a8b73") * Color(1, 1, 1, a))
	var loaded: bool = phase == "back" and float((seed_data.get("gather", {}) as Dictionary).get("load", 0.0)) > 0.01
	if loaded:
		draw_circle(p + Vector2(0, -7), 3.0, Color(COL_DEAD.r, COL_DEAD.g, COL_DEAD.b, a))
	var lbl := "convoy out" if phase == "out" else "convoy returning"
	_text_c(p + Vector2(0, 14), lbl, 10, Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, a))


func _draw_workers() -> void:
	var r := float(_y("worker_r", 4.0))
	for task in dots:
		var idle: bool = task == "idle"
		for d in dots[task]:
			var p: Vector2 = d["pos"]
			draw_circle(p, r + 1.4, Color(0, 0, 0, 0.7))
			draw_circle(p, r, Color(COL_UNDEAD.r, COL_UNDEAD.g, COL_UNDEAD.b, 0.55 if idle else 0.95))


func _draw_highlight() -> void:
	if highlight_task == "" or highlight_t <= 0.0:
		return
	var a := clampf(highlight_t, 0.0, 1.0)
	var pos := _station_pos(highlight_task)
	var r := _station_r(highlight_task) + 7.0
	draw_arc(pos, r, 0, TAU, 48, Color(COL_UNDEAD.r, COL_UNDEAD.g, COL_UNDEAD.b, 0.8 * a), 2.5)


func _text_c(center: Vector2, text: String, fsize: int, color: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(_font, center + Vector2(-w * 0.5, fsize * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)


# ------------------------------------------------------------------ input ----
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _station_at(event.position)
		if hit != "":
			highlight(hit)
			station_clicked.emit(hit)
			accept_event()


func _station_at(pos: Vector2) -> String:
	if logic == null:
		return ""
	for id in _stations():
		if id == "sim" and not logic.station_built():
			continue
		if id == "vats":
			var count := int(logic.town["vats"])
			if count <= 0:
				continue
			var base := _station_pos("vats")
			var spacing := float(_y("vat_pod_spacing", 30.0))
			var rect := Rect2(base - Vector2(16, 16), Vector2(spacing * (count - 1) + 32, 32))
			if rect.has_point(pos):
				return "vats"
			continue
		if pos.distance_to(_station_pos(id)) <= _station_r(id) + 8.0:
			return String(id)
	return ""
