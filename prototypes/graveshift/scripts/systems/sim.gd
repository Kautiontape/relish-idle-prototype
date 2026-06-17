class_name Sim
extends RefCounted
## The work-machine. Pure logic + Vector2 math, no rendering — so the smoke test
## can tick it headlessly. One chain, self-hauled:
##
##   Quarry crew  : stand at the quarry, harvest raw bone into its stock.
##   Workshop crew: walk to a quarry, take one bone, walk to the bench, craft a
##                  good, carry it to the storehouse → Supplies +1, repeat.
##   Storehouse   : passive sink. Bone Pit: where the idle (unassigned) loiter.
##
## The bottleneck is the crew RATIO: too many at the bench and they pile up at an
## empty quarry (visible starvation); too many at the quarry and bone stock just
## grows (wasted labor). Aptitude scales work + walk speed, so WHO you place
## where matters. Only quarry/workshop are assignable; everything else is idle.

var rng: RandomNumberGenerator
var workers: Array = []     # worker dicts (Roster.make_worker + sim fields)
var stations: Array = []    # station dicts (from yard.json + pos/stock)
var living: Array = []      # ambient dicts {pos,target,timer}
var supplies: int = 0
var living_enabled: bool = true

var _next_id: int = 1
var _deliveries: Array = []  # sim_time stamps of each delivery (rolling rate)
var _sim_time: float = 0.0

func _init(rng_: RandomNumberGenerator) -> void:
	rng = rng_

# ---------- setup ----------

func setup() -> void:
	_build_stations()
	workers.clear()
	living.clear()
	supplies = 0
	_deliveries.clear()
	_sim_time = 0.0
	_next_id = 1
	for i in int(ConfigDb.v("workers", "start_count")):
		_spawn_worker()
	_set_living_count(int(ConfigDb.v("stats", "num_living")))

func reset() -> void:
	setup()

func _build_stations() -> void:
	stations.clear()
	for s in ConfigDb.v("yard", "stations"):
		var st: Dictionary = (s as Dictionary).duplicate(true)
		st["pos"] = Vector2(float(st["x"]), float(st["y"]))
		st["stock"] = 0
		stations.append(st)

func _spawn_worker() -> Dictionary:
	var w := Roster.make_worker(_next_id, rng)
	_next_id += 1
	w["pos"] = _pit_pos() + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
	w["station_id"] = ""
	w["state"] = "idle"
	w["timer"] = rng.randf_range(0.0, 1.5)
	w["carrying"] = ""           # "", "bone", "good"
	w["target"] = w["pos"]
	w["src"] = ""                # the quarry a bench worker is sourcing from
	w["dragging"] = false
	workers.append(w)
	return w

## "The crypt sends N." Faked roster growth, mirrors the Slab's haul button.
func send_more(n: int = -1) -> Array:
	if n < 0:
		n = int(ConfigDb.v("workers", "send_count"))
	var out: Array = []
	for i in n:
		out.append(_spawn_worker())
	return out

# ---------- station helpers ----------

func station_by_id(id: String) -> Dictionary:
	for s in stations:
		if s["id"] == id:
			return s
	return {}

func _pit_pos() -> Vector2:
	var p := station_by_id("pit")
	return (p["pos"] as Vector2) if not p.is_empty() else Vector2(200, 200)

func _nearest_of_kind(from: Vector2, kind: String) -> Dictionary:
	var best := {}
	var best_d := INF
	for s in stations:
		if s["kind"] != kind:
			continue
		var d := from.distance_to(s["pos"])
		if d < best_d:
			best_d = d
			best = s
	return best

## A bench worker's source: the nearest quarry that has stock; else the nearest
## quarry at all (so they walk there and visibly wait for bone).
func _source_quarry(w: Dictionary) -> Dictionary:
	var best := {}
	var best_d := INF
	var stocked := {}
	var stocked_d := INF
	for s in stations:
		if s["kind"] != "quarry":
			continue
		var d: float = (w["pos"] as Vector2).distance_to(s["pos"])
		if d < best_d:
			best_d = d
			best = s
		if int(s["stock"]) > 0 and d < stocked_d:
			stocked_d = d
			stocked = s
	return stocked if not stocked.is_empty() else best

# ---------- aptitude (live-read, so sliders bite immediately) ----------

func _stat_sum(w: Dictionary, keys: Array) -> float:
	var s := 0.0
	for k in keys:
		s += float((w["stats"] as Dictionary).get(k, 0))
	return s

## 1.0 + strength·Σ(relevant stats). kind ∈ {"quarry","workshop"}.
func aptitude_mult(w: Dictionary, kind: String) -> float:
	var keys: Array = ConfigDb.v("stats", "%s_aptitude_stats" % kind)
	return 1.0 + float(ConfigDb.v("stats", "aptitude_strength")) * _stat_sum(w, keys)

func _harvest_time(w: Dictionary) -> float:
	return float(ConfigDb.v("stats", "harvest_time_s")) / aptitude_mult(w, "quarry")

func _craft_time(w: Dictionary) -> float:
	return float(ConfigDb.v("stats", "craft_time_s")) / aptitude_mult(w, "workshop")

func _move_speed(w: Dictionary) -> float:
	return float(ConfigDb.v("stats", "base_walk_px")) \
		+ float(ConfigDb.v("stats", "walk_per_speed")) * float((w["stats"] as Dictionary).get("speed", 0))

## Which assignable station this worker is best suited to — for the UI hint.
func best_station_kind(w: Dictionary) -> String:
	return "quarry" if aptitude_mult(w, "quarry") >= aptitude_mult(w, "workshop") else "workshop"

# ---------- assignment ----------

func assign(worker_id: int, station_id: String) -> void:
	for w in workers:
		if int(w["id"]) != worker_id:
			continue
		var st := station_by_id(station_id)
		var kind: String = String(st.get("kind", "")) if not st.is_empty() else ""
		if kind == "quarry":
			w["station_id"] = station_id
			w["state"] = "to_work"
		elif kind == "workshop":
			w["station_id"] = station_id
			w["state"] = "to_source"
		else:
			# Storehouse / pit / inn / market / empty ground → unassigned.
			w["station_id"] = ""
			w["state"] = "idle"
			w["target"] = _pit_pos() + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
		w["carrying"] = ""
		w["src"] = ""
		w["timer"] = 0.0
		return

func crew(station_id: String) -> int:
	var n := 0
	for w in workers:
		if w["station_id"] == station_id:
			n += 1
	return n

func idle_count() -> int:
	var n := 0
	for w in workers:
		if String(w["station_id"]) == "":
			n += 1
	return n

# ---------- the tick ----------

func tick(dt: float) -> void:
	_sim_time += dt
	for w in workers:
		_tick_worker(w, dt)
	if living_enabled:
		_tick_living(dt)
	var window := float(ConfigDb.v("stats", "throughput_window_s"))
	while _deliveries.size() > 0 and _sim_time - float(_deliveries[0]) > window:
		_deliveries.pop_front()

func throughput_per_min() -> float:
	var window := float(ConfigDb.v("stats", "throughput_window_s"))
	if window <= 0.0:
		return 0.0
	return _deliveries.size() / window * 60.0

func _tick_worker(w: Dictionary, dt: float) -> void:
	if w["dragging"]:
		return
	var sid: String = String(w["station_id"])
	if sid == "":
		_tick_idle(w, dt)
		return
	var st := station_by_id(sid)
	if st.is_empty():
		assign(int(w["id"]), "")
		return
	match String(st["kind"]):
		"quarry":
			_tick_quarry(w, st, dt)
		"workshop":
			_tick_workshop(w, st, dt)
		_:
			assign(int(w["id"]), "")

func _tick_idle(w: Dictionary, dt: float) -> void:
	if _step_toward(w, dt):
		w["timer"] = float(w["timer"]) - dt
		if float(w["timer"]) <= 0.0:
			var wander := float(ConfigDb.v("yard", "idle_wander_px"))
			w["target"] = _pit_pos() + Vector2(rng.randf_range(-wander, wander), rng.randf_range(-wander, wander))
			w["timer"] = rng.randf_range(0.8, 2.6)

func _tick_quarry(w: Dictionary, st: Dictionary, dt: float) -> void:
	match String(w["state"]):
		"to_work":
			w["target"] = st["pos"]
			if _step_toward(w, dt):
				w["state"] = "harvest"
				w["timer"] = _harvest_time(w)
		"harvest":
			w["timer"] = float(w["timer"]) - dt
			if float(w["timer"]) <= 0.0:
				st["stock"] = int(st["stock"]) + 1
				w["timer"] = _harvest_time(w)
		_:
			w["state"] = "to_work"

func _tick_workshop(w: Dictionary, bench: Dictionary, dt: float) -> void:
	match String(w["state"]):
		"to_source":
			var q := _source_quarry(w)
			if q.is_empty():
				return
			w["src"] = q["id"]
			w["target"] = q["pos"]
			if _step_toward(w, dt):
				w["state"] = "wait_bone"
		"wait_bone":
			var q := station_by_id(String(w["src"]))
			if q.is_empty() or q["kind"] != "quarry":
				w["state"] = "to_source"
				return
			# A stocked quarry nearer than ours? Re-route (keeps crews from
			# starving at one quarry while another piles up).
			var best := _source_quarry(w)
			if not best.is_empty() and best["id"] != q["id"] and int(best["stock"]) > 0:
				w["state"] = "to_source"
				return
			if int(q["stock"]) > 0:
				q["stock"] = int(q["stock"]) - 1
				w["carrying"] = "bone"
				w["state"] = "to_bench"
			# else: stand and wait — visible starvation, the bottleneck tell.
		"to_bench":
			w["target"] = bench["pos"]
			if _step_toward(w, dt):
				w["state"] = "craft"
				w["timer"] = _craft_time(w)
		"craft":
			w["timer"] = float(w["timer"]) - dt
			if float(w["timer"]) <= 0.0:
				w["carrying"] = "good"
				w["state"] = "to_store"
		"to_store":
			var store := _nearest_of_kind(w["pos"], "storehouse")
			if store.is_empty():
				w["state"] = "to_source"
				return
			w["target"] = store["pos"]
			if _step_toward(w, dt):
				w["state"] = "deliver"
		"deliver":
			supplies += 1
			_deliveries.append(_sim_time)
			w["carrying"] = ""
			w["state"] = "to_source"
		_:
			w["state"] = "to_source"

## Move toward w.target at the worker's speed. Returns true on arrival.
func _step_toward(w: Dictionary, dt: float) -> bool:
	var to: Vector2 = (w["target"] as Vector2) - (w["pos"] as Vector2)
	var d := to.length()
	if d <= float(ConfigDb.v("yard", "reach_px")):
		return true
	var step := _move_speed(w) * dt
	w["pos"] = (w["pos"] as Vector2) + to / d * minf(step, d)
	return false

# ---------- ambient living (pure vibe, no mechanic) ----------

func set_living_enabled(on: bool) -> void:
	living_enabled = on

func _set_living_count(n: int) -> void:
	living.clear()
	for i in n:
		var p := _amenity_pos()
		living.append({"pos": p, "target": p, "timer": rng.randf_range(0.0, 2.0)})

func _amenity_pos() -> Vector2:
	var spots: Array = []
	for s in stations:
		if s["kind"] == "inn" or s["kind"] == "market":
			spots.append(s["pos"])
	if spots.is_empty():
		return Vector2(200, 740)
	var base: Vector2 = spots[rng.randi_range(0, spots.size() - 1)]
	return base + Vector2(rng.randf_range(-26, 26), rng.randf_range(-26, 26))

func _tick_living(dt: float) -> void:
	var sp := float(ConfigDb.v("stats", "living_walk_px"))
	for l in living:
		var to: Vector2 = (l["target"] as Vector2) - (l["pos"] as Vector2)
		var d := to.length()
		if d <= 6.0:
			l["timer"] = float(l["timer"]) - dt
			if float(l["timer"]) <= 0.0:
				l["target"] = _amenity_pos()
				l["timer"] = rng.randf_range(1.6, 4.2)
		else:
			l["pos"] = (l["pos"] as Vector2) + to / d * minf(sp * dt, d)
