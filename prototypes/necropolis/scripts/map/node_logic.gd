class_name NodeLogic
extends RefCounted
## Pure logic for the map's nodes (no autoloads, so headless tests compile it): pip counts and
## arc fractions, tier notches, the held and tithe countdowns, the backlog ring stack, the valve
## glyph's widths and directions, Relish's interpolation, wake and light, and the --nodes=demo
## stand-ins. Pulse-derived values come in as arguments. Tuning: configs/map_view.json "nodes".

const COVINGTON := "covington"
const MATTERS := ["living", "undead", "dead"]


static func ncfg() -> Dictionary:
	return MapLogic.cfg().get("nodes", {})


static func _n(key: String) -> float:
	return float(ncfg().get(key, 0.0))


## LineGlow's stroke stack for one glowing line, with every halo pulled toward the core by the
## same share so the outermost is at most `halo_max` wide (the same cap LaneStyle.capped_halo
## applies to lanes). [[width, Color], ...], outermost first, the core last.
static func capped_layers(col: Color, width: float, glow: float, halo_max: float, core := LineGlow.NO_CORE) -> Array:
	var stack := LineGlow.layers(col, width, glow, core)
	var n := stack.size()
	if n < 2 or halo_max <= 0.0:
		return stack
	var core_w: float = stack[n - 1][0]
	var outer: float = stack[0][0]
	if outer > halo_max and outer > core_w:
		var k := maxf(halo_max - core_w, 0.0) / (outer - core_w)
		for i in n - 1:
			stack[i][0] = core_w + (stack[i][0] - core_w) * k
	return stack


# --- fortress rings ------------------------------------------------------------------

## How many pips a full ring holds: 100 / pip_pct (10).
static func pip_slots() -> int:
	return maxi(roundi(100.0 / maxf(_n("pip_pct"), 1.0)), 1)


## Pips per matter: round(mass / cap x slots), so 47% living is 5. If rounding overfills the
## ring, the last matters in arc order (dead first) give up pips until it fits.
static func pip_counts(f: Dictionary) -> Dictionary:
	var out := {"living": 0, "undead": 0, "dead": 0}
	var cap := float(f.get("cap", 0.0))
	if cap <= 0.0:
		return out
	var n := pip_slots()
	var total := 0
	for k in MATTERS:
		out[k] = clampi(roundi(maxf(float(f.get(k, 0.0)), 0.0) / cap * n), 0, n)
		total += out[k]
	for k in ["dead", "undead", "living"]:
		while total > n and out[k] > 0:
			out[k] -= 1
			total -= 1
	return out


## One entry per slot, in arc order from 12 o'clock: the matter that slot holds, or "" (empty).
static func pip_layout(f: Dictionary) -> Array:
	var counts := pip_counts(f)
	var out: Array = []
	for k in MATTERS:
		for i in int(counts[k]):
			out.append(k)
	while out.size() < pip_slots():
		out.append("")
	return out


## The angle of pip slot `i` (radians, 12 o'clock first, clockwise).
static func pip_angle(i: int) -> float:
	return -PI * 0.5 + (i + 0.5) * TAU / pip_slots()


## Each matter's share of the circle (mass / cap), scaled down together if they sum past 1.
static func arc_fracs(f: Dictionary) -> Dictionary:
	var out := {"living": 0.0, "undead": 0.0, "dead": 0.0}
	var cap := float(f.get("cap", 0.0))
	if cap <= 0.0:
		return out
	var sum := 0.0
	for k in MATTERS:
		out[k] = clampf(float(f.get(k, 0.0)) / cap, 0.0, 1.0)
		sum += out[k]
	if sum > 1.0:
		for k in MATTERS:
			out[k] /= sum
	return out


## Angles of a tier's radial notches: `tier` ticks centred on 6 o'clock, notch_step_deg apart.
static func notch_angles(tier: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var step := deg_to_rad(_n("notch_step_deg"))
	for i in maxi(tier, 0):
		out.append(PI * 0.5 + (i - (tier - 1) * 0.5) * step)
	return out


## Who the fort's centre mark shows: "undead" when the undead outnumber the living, else
## "living" when any live, else "dead".
static func controller(f: Dictionary) -> String:
	var u := float(f.get("undead", 0.0))
	var l := float(f.get("living", 0.0))
	if u > l:
		return "undead"
	if l > 0.0:
		return "living"
	return "dead"


## How long a flip holds: hold_s x (1 + tier_mult x tier) (realm.json "flip").
# TODO(api E2): grace total not in view_fort
static func grace_total(flip: Dictionary, tier: int) -> float:
	return float(flip.get("hold_s", 0.0)) * (1.0 + float(flip.get("tier_mult", 0.0)) * tier)


## The held countdown's sweep, 0..1: held_s_left / grace_total (0 when not held).
static func held_fraction(f: Dictionary, flip: Dictionary) -> float:
	if not bool(f.get("held", false)):
		return 0.0
	var g := grace_total(flip, int(f.get("tier", 1)))
	if g <= 0.0:
		return 0.0
	return clampf(float(f.get("held_s_left", 0.0)) / g, 0.0, 1.0)


## "wave" while the tithe wave is on this fort, "warning" while it is targeted, else "".
static func tithe_mode(f: Dictionary) -> String:
	var t: Dictionary = f.get("tithe", {})
	if bool(t.get("wave_active", false)):
		return "wave"
	if bool(t.get("targeted", false)):
		return "warning"
	return ""


## The tithe countdown's sweep, 0..1: eta_s / tithe_warning_s (0 for eta_s < 0, the API's "none").
# TODO(api E2): tithe_warning_s comes from map_view.json until E2's config lands
static func tithe_fraction(eta_s: float) -> float:
	var w := _n("tithe_warning_s")
	if eta_s < 0.0 or w <= 0.0:
		return 0.0
	return clampf(eta_s / w, 0.0, 1.0)


## "m:ss": 88 -> "1:28", 5 -> "0:05"; negative counts as 0.
static func fmt_eta(eta_s: float) -> String:
	var s := maxi(roundi(eta_s), 0)
	return "%d:%02d" % [s / 60, s % 60]


## The first-dungeon fort pulses (its first clear still pays a blueprint).
static func first_dungeon_pulse(f: Dictionary) -> bool:
	return bool(f.get("first_dungeon", false)) and bool(f.get("first_clear", false))


## Fort name labels: shown at mid and near zoom; at far zoom only forts of label_far_min_tier+.
static func fort_label_shown(zoom_tier: String, tier: int) -> bool:
	if zoom_tier == "far":
		return tier >= int(_n("label_far_min_tier"))
	return true


## Fort pips show at mid and near zoom; at far only the arcs.
static func pips_shown(zoom_tier: String) -> bool:
	return zoom_tier != "far"


# --- Covington's valve glyph -------------------------------------------------------------

## Stem widths from the valve shares: max_w x share; a share of 0 is 0 (nothing drawn).
static func valve_widths(valve: Dictionary) -> Dictionary:
	var out := {}
	for k in ["work", "war", "flood"]:
		var s := clampf(float(valve.get(k, 0.0)), 0.0, 1.0)
		out[k] = _n("valve_glyph_max_w") * s if s > 0.0 else 0.0
	return out


## Mean position of the forts (WAR's aim).
static func fort_centroid(forts: Array) -> Vector2:
	if forts.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for f in forts:
		sum += MapModel.to_vec(f["pos"])
	return sum / forts.size()


## Stem directions (unit vectors): WAR toward the forts' centroid, FLOOD toward Vei, pushed
## apart to at least valve_min_sep_deg when they nearly coincide; WORK points away from both
## (its hook curls back home).
static func valve_dirs(cov: Vector2, centroid: Vector2, vei: Vector2) -> Dictionary:
	var war := (centroid - cov).normalized() if centroid != cov else Vector2.UP
	var flood := (vei - cov).normalized() if vei != cov else Vector2.UP
	var sep := war.angle_to(flood)
	var need := deg_to_rad(_n("valve_min_sep_deg"))
	if absf(sep) < need:
		var push := (need - absf(sep)) * 0.5
		var sgn := 1.0 if sep >= 0.0 else -1.0
		war = war.rotated(-sgn * push)
		flood = flood.rotated(sgn * push)
	var away := -(war + flood)
	var work := away.normalized() if away.length() > 1e-3 else -war
	return {"war": war, "flood": flood, "work": work}


# --- Vei's domain -----------------------------------------------------------------------

## Backlog ring stack: one ring per backlog_ring_mass, up to backlog_ring_max, the rest as "+N".
static func backlog_rings(backlog: float) -> Dictionary:
	var per := maxf(_n("backlog_ring_mass"), 1.0)
	var total := maxi(floori(backlog / per), 0)
	var shown := mini(total, int(_n("backlog_ring_max")))
	return {"rings": shown, "overflow": total - shown}


## Digestion rings' angular speed, rad/s, proportional to Vei's capacity R_vei.
static func vei_spin(r_vei: float) -> float:
	return r_vei * _n("vei_rot_per_R")


## Radius of Vei's drawn structure from the domain radius the view reports.
static func vei_struct_radius(domain_radius: float) -> float:
	return domain_radius * _n("vei_struct_frac")


## Odds as the integer percent the map prints.
static func fmt_odds(odds: float) -> String:
	return "%d%%" % roundi(clampf(odds, 0.0, 1.0) * 100.0)


# --- Relish -----------------------------------------------------------------------------

## Sim seconds to extrapolate Relish by: the real time since the model refreshed, capped at
## relish_extrap_max_s, times the sim speed (0 while paused). The cap is on real time so a fast
## sim speed still glides to the next hop instead of stopping short.
static func extrap_dt(real_s: float, speed_scale: float) -> float:
	return clampf(real_s, 0.0, _n("relish_extrap_max_s")) * maxf(speed_scale, 0.0)


## Where to draw her: while travelling, the model's `pos` advanced along `heading` at `speed`
## px/s for `dt` sim seconds, never past `target` when there is one; otherwise `pos` itself.
static func relish_drawn_pos(state: String, pos: Vector2, heading: float, speed: float,
		dt: float, target: Vector2, has_target: bool) -> Vector2:
	if state != "travelling" or speed <= 0.0 or dt <= 0.0:
		return pos
	var step := dt * speed
	if has_target:
		step = minf(step, pos.distance_to(target))
	return pos + Vector2.from_angle(heading) * step


## Adds a wake point (x, y, t) unless she has not moved wake_min_step_px since the last one,
## then drops the oldest past wake_max_points.
static func wake_add(buf: Array, p: Vector2, now_s: float) -> void:
	if buf.is_empty() or Vector2(buf.back().x, buf.back().y).distance_to(p) >= _n("wake_min_step_px"):
		buf.append(Vector3(p.x, p.y, now_s))
	while buf.size() > int(_n("wake_max_points")):
		buf.pop_front()


## Drops the points older than wake_s.
static func wake_prune(buf: Array, now_s: float) -> void:
	while not buf.is_empty() and now_s - buf[0].z > _n("wake_s"):
		buf.pop_front()


## Alpha of each wake point, 1 at the head fading to 0 at the tail. Live: by age (so it also
## decays while she stands still). Frozen (reduced motion): by position along the buffer.
static func wake_alphas(buf: Array, now_s: float, frozen: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := buf.size()
	for i in n:
		if frozen:
			out.append(float(i) / maxf(n - 1, 1.0))
		else:
			out.append(clampf(1.0 - (now_s - buf[i].z) / maxf(_n("wake_s"), 0.001), 0.0, 1.0))
	return out


## Ids of the forts within `radius` of Relish: their dead turn dead_lit.
static func lit_fort_ids(forts: Array, relish_pos: Vector2, radius: float) -> Array:
	var out: Array = []
	for f in forts:
		if MapModel.to_vec(f["pos"]).distance_to(relish_pos) <= radius:
			out.append(f["id"])
	return out


# --- villages ------------------------------------------------------------------------------

## Palette key of a village's edge by owner: player undead, vei living, none town blue.
static func village_edge_key(owner: String) -> String:
	if owner == "player":
		return "undead"
	if owner == "vei":
		return "living"
	return "town"


# --- --nodes=demo stand-ins -----------------------------------------------------------------

## Overlays stand-in values on the model's fort, vei and relish entries (in place) so one
## screenshot shows what E2 will: a held fort, a tithe warning, a live wave, the first-dungeon
## pulse, a simulacrum, Relish mid-travel and a full backlog stack. Values: map_view.json
## "demo_nodes". Relish stands still (speed 0) so her place holds between refreshes.
# TODO(api E2): debug stand-in
static func demo_overlay(forts: Array, vei: Dictionary, relish: Dictionary, cov_pos: Vector2, flip: Dictionary) -> void:
	var d: Dictionary = MapLogic.cfg().get("demo_nodes", {})
	var by_id := {}
	for f in forts:
		by_id[f["id"]] = f
	var held: Dictionary = d.get("held", {})
	if by_id.has(held.get("fort", "")):
		var f: Dictionary = by_id[held["fort"]]
		f["held"] = true
		f["flipped_count"] = 1
		f["held_s_left"] = float(held["frac"]) * grace_total(flip, int(f["tier"]))
	var tithe: Dictionary = d.get("tithe", {})
	if by_id.has(tithe.get("fort", "")):
		by_id[tithe["fort"]]["tithe"] = {"targeted": true, "eta_s": float(tithe["eta_s"]), "wave_active": false}
		vei["tithe"] = {"target": tithe["fort"], "eta_s": float(tithe["eta_s"]), "warning": true,
			"wave_active": false, "wave_s_left": 0.0}
	var wave: Dictionary = d.get("wave", {})
	if by_id.has(wave.get("fort", "")):
		by_id[wave["fort"]]["tithe"] = {"targeted": true, "eta_s": 0.0, "wave_active": true}
	if by_id.has(d.get("first_dungeon", "")):
		by_id[d["first_dungeon"]]["first_dungeon"] = true
		by_id[d["first_dungeon"]]["first_clear"] = true
	var sim: Dictionary = d.get("simulacrum", {})
	if by_id.has(sim.get("fort", "")):
		by_id[sim["fort"]]["simulacrum_charges"] = float(sim["charges"])
	var rd: Dictionary = d.get("relish", {})
	if by_id.has(rd.get("target", "")) and not relish.is_empty():
		var to := MapModel.to_vec(by_id[rd["target"]]["pos"])
		var p := cov_pos.lerp(to, float(rd["frac"]))
		relish["state"] = "travelling"
		relish["at"] = COVINGTON
		relish["target"] = rd["target"]
		relish["pos"] = [p.x, p.y]
		relish["heading"] = cov_pos.angle_to_point(to)
		relish["speed"] = 0.0
	var vd: Dictionary = d.get("vei", {})
	if not vd.is_empty():
		vei["backlog"] = float(vd["backlog"])
		vei["sign"] = int(vd["sign"])
		vei["drain_s"] = float(vd["drain_s"])
		vei["odds"] = float(vd["odds"])


## A trail of `n` wake points behind `pos` along `heading`, newest last, spread over the
## wake's life (for the demo, where she stands still).
# TODO(api E2): debug stand-in
static func demo_wake(pos: Vector2, heading: float, n: int, now_s: float) -> Array:
	var out: Array = []
	var life := _n("wake_s") * _n("demo_wake_life")
	var back := Vector2.from_angle(heading + PI)
	for i in n:
		var k := float(n - 1 - i) / maxf(n - 1, 1.0)
		var q := pos + back * k * float(MapLogic.cfg().get("demo_nodes", {}).get("wake_spacing_px", 10.0)) * n
		out.append(Vector3(q.x, q.y, now_s - k * life))
	return out
