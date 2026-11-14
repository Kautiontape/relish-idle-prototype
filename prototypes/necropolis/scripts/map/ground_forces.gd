class_name GroundForces
extends RefCounted
## What the game does to the flow ground's current (phase B): the routes push it, Vei's backlog
## spins into a clot at her gates, Relish bends it toward her, and tithe waves and flips sweep it.
## Pure (names no autoload, so headless tests run it): flow_ground.gd feeds it views, events and
## its own clock, and uploads what comes back to flow_particles.gdshader as uniforms. Render-only:
## none of it reaches InfluenceField, so the sim never sees it.
## Tuning: configs/ground.json "forces".

const MAX_SURGES := 3   # flow_particles.gdshader's MAX_SURGES
const MAX_INKS := 3     # flow_particles.gdshader's MAX_INKS

var cfg := {}
## Running sweeps: {kind: "surge", fort, a, c, b, t0, dur, strength} or {kind: "ink", fort, pos,
## t0, dur, side}. Times are flow_ground's real-time clock, so a sweep plays at the same pace at
## any sim speed.
var sweeps: Array = []
var _next_surge := {}   # fort id -> clock time of its next repeat


func _init(forces_cfg := {}) -> void:
	cfg = forces_cfg


func _sub(k: String) -> Dictionary:
	return cfg.get(k, {})


## A lane's push weight: its kind's weight (route.kinds) times Pulse's u. Off lanes (u < 0) and
## unlisted kinds push nothing; dead's weight is 0 by default, because dead stays matte.
func lane_weight(kind: String, u: float) -> float:
	if u <= 0.0:
		return 0.0
	return float(_sub("route").get("kinds", {}).get(kind, 0.0)) * clampf(u, 0.0, 1.0)


## Vei's backlog clot, from view_vei(): Vector4(strength 0..1, outer radius, spin, inner radius),
## radii in world px from Vei (the clot is the band between them, at her gates).
## Strength is the win meter itself: odds (backlog / (backlog + K)) over vortex.full_odds. Spin is
## the sustained sign: +1 the clot tightens inward (her queue grows), -1 it unwinds outward, 0 it
## only circulates.
func vortex(vei: Dictionary) -> Vector4:
	var v := _sub("vortex")
	var s := clampf(float(vei.get("odds", 0.0)) / maxf(1e-3, float(v.get("full_odds", 0.8))), 0.0, 1.0)
	if s < float(v.get("min_strength", 0.02)):
		return Vector4.ZERO
	var r: Array = v.get("radius_px", [150.0, 420.0])
	var radius := lerpf(float(r[0]), float(r[1]), s)
	return Vector4(s, radius, float(clampi(int(vei.get("sign", 0)), -1, 1)), float(v.get("inner_px", 110.0)))


## Relish's pull, from view_relish(): Vector4(x, y, strength, radius world px). Strength is her
## state's weight (relish.states), times relish.tide_mult while her tide applies
## (effects.tide_fort). Dead, or a state without a weight: 0.
func relish(rel: Dictionary) -> Vector4:
	var c := _sub("relish")
	var w := float(c.get("states", {}).get(str(rel.get("state", "")), 0.0))
	if w <= 0.0:
		return Vector4.ZERO
	if str(rel.get("effects", {}).get("tide_fort", "")) != "":
		w *= float(c.get("tide_mult", 1.0))
	var p: Array = rel.get("pos", [0.0, 0.0])
	return Vector4(float(p[0]), float(p[1]), w, float(c.get("radius_px", 220.0)))


## A game event (Game.game_event). Starts the sweeps it names: a flip inks the ground round the fort
## green (+1), a retake orange (-1); a tithe warning or wave sends its surge now. Events older than
## event_stale_s sim seconds (the burst after a catch-up) start nothing.
##   now    flow_ground's clock; hud_t  view_hud().t; pos  node id -> world position
func on_event(ev: Dictionary, now: float, hud_t: float, pos: Dictionary) -> void:
	if hud_t - float(ev.get("t", hud_t)) > float(cfg.get("event_stale_s", 10.0)):
		return
	var fort := str(ev.get("fort_id", ""))
	match str(ev.get("type", "")):
		"fort_flipped":
			_ink(fort, 1.0, now, pos)
		"fort_retaken":
			_ink(fort, -1.0, now, pos)
		"tithe_warning", "tithe_wave":
			_next_surge.erase(fort)   # the state check below sends it at once


## The standing tithe state, from view_vei().tithe, each refresh: a pending warning sends a faint
## surge from Vei to its fort every surge.warning_every_s, a running wave a full one every
## surge.wave_every_s. Driven by state, so a warning made before the map opened (or before a load)
## still shows. Also drops finished sweeps.
func update(now: float, tithe: Dictionary, pos: Dictionary) -> void:
	sweeps = sweeps.filter(func(s): return now - float(s["t0"]) < float(s["dur"]))
	var fort := str(tithe.get("target", ""))
	var wave := bool(tithe.get("wave_active", false))
	var warn := bool(tithe.get("warning", false))
	for k in _next_surge.keys():
		if k != fort:
			_next_surge.erase(k)
	if fort == "" or not (wave or warn) or not pos.has(fort) or not pos.has("vei"):
		return
	var c := _sub("surge")
	if now < float(_next_surge.get(fort, -INF)):
		return
	_next_surge[fort] = now + float(c.get("wave_every_s" if wave else "warning_every_s", 6.0))
	var strength := 1.0 if wave else float(c.get("warning_strength", 0.35))
	var curve := MapLogic.lane_curve(pos["vei"], pos[fort], 1.0)
	_add({"kind": "surge", "fort": fort, "a": curve["a"], "c": curve["c"], "b": curve["b"],
		"t0": now, "dur": float(c.get("seconds", 2.4)), "strength": strength}, MAX_SURGES)


func _ink(fort: String, side: float, now: float, pos: Dictionary) -> void:
	if not pos.has(fort):
		return
	_add({"kind": "ink", "fort": fort, "pos": pos[fort], "t0": now,
		"dur": float(_sub("ink").get("seconds", 5.0)), "side": side}, MAX_INKS)


## Keeps at most `cap` sweeps of a kind: a new one replaces the oldest.
func _add(s: Dictionary, cap: int) -> void:
	var same := sweeps.filter(func(o): return o["kind"] == s["kind"])
	if same.size() >= cap:
		sweeps.erase(same[0])
	sweeps.append(s)


## The surges as the shader's arrays: ac = (a.xy, c.xy), b = (b.xy, head, strength). The head runs
## 0 -> 1 + surge.tail along the curve over the sweep, so the tail leaves the fort too; strength
## fades out over the last surge.fade share. Under reduced motion the head stands at the fort and
## the strength fades in and out over the same share instead (the shader draws the whole line,
## brightening toward the fort: direction without travel).
func surge_arrays(now: float, reduced: bool) -> Dictionary:
	var ac := PackedVector4Array()
	var b := PackedVector4Array()
	ac.resize(MAX_SURGES)
	b.resize(MAX_SURGES)
	var c := _sub("surge")
	var tail := float(c.get("tail", 0.25))
	var fade := clampf(float(c.get("fade", 0.3)), 0.01, 1.0)
	var i := 0
	for s in sweeps:
		if s["kind"] != "surge":
			continue
		var k := clampf((now - float(s["t0"])) / maxf(1e-3, float(s["dur"])), 0.0, 1.0)
		var head := 1.0 if reduced else k * (1.0 + tail)
		var env := (smoothstep(0.0, fade, k) if reduced else 1.0) * (1.0 - smoothstep(1.0 - fade, 1.0, k))
		ac[i] = Vector4(s["a"].x, s["a"].y, s["c"].x, s["c"].y)
		b[i] = Vector4(s["b"].x, s["b"].y, head, float(s["strength"]) * env)
		i += 1
	return {"ac": ac, "b": b, "count": i}


## The inks as the shader's array: (x, y, front radius world px, signed strength: + green, - orange).
## A flip's front eases out to ink.radius_px, a retake's eases in from it to the fort, and the
## shader pushes the streaks with the front (out, or in), so the two differ by motion and by the way
## the streaks point, not only by hue. Strength fades over the sweep. Under reduced motion the front
## stands at full radius and only the strength rises and falls; the comets on it still point out or in.
func ink_array(now: float, reduced: bool) -> Dictionary:
	var out := PackedVector4Array()
	out.resize(MAX_INKS)
	var r := float(_sub("ink").get("radius_px", 200.0))
	var i := 0
	for s in sweeps:
		if s["kind"] != "ink":
			continue
		var k := clampf((now - float(s["t0"])) / maxf(1e-3, float(s["dur"])), 0.0, 1.0)
		var ease := 1.0 - pow(1.0 - minf(1.0, k * 2.0), 3.0)
		# a flip's front sweeps out from the fort, a retake's closes in on it (not only the hue)
		var front := r if reduced else (r * ease if float(s["side"]) > 0.0 else r * (1.0 - ease))
		var env := sin(k * PI) if reduced else 1.0 - k
		out[i] = Vector4(s["pos"].x, s["pos"].y, front, float(s["side"]) * env)
		i += 1
	return {"ink": out, "count": i}
