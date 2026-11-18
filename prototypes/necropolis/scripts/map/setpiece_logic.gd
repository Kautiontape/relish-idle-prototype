class_name SetpieceLogic
extends RefCounted
## Pure timing for the map's set pieces (VISUAL-LANGUAGE 2e; no autoloads, so headless tests
## compile it): the valve swing, the flip (and the first flip's larger treatment), the tithe tide,
## the garrison cleared and victory. Each runs on the tempo: its clock is beats since it started,
## from Pulse's wall clock and tempo (passed in), divided by the debug --setpiece-slow factor, so
## it elapses under reduced motion too, where each one goes straight to its end state.
## Tuning: configs/map_view.json "setpieces".

const VALVE := "valve"
const FLIP := "flip"
const FIRST_FLIP := "first_flip"
const TITHE := "tithe"
const GARRISON := "garrison"
const VICTORY := "victory"
const RETREAT := "retreat"  # back from a raid that left the fort Vei's: one callout line
const KINDS := [VALVE, FLIP, FIRST_FLIP, TITHE, GARRISON, VICTORY, RETREAT]
const TAKEN := "taken"  # return_kind: the raid took the fort (its set piece is FLIP or FIRST_FLIP)
const RUN := "run"    # victory: every lane green, running toward Vei
const STOP := "stop"  # victory: every dash frozen, the victory line up
const NONE := Vector2(-1.0, -1.0)  # no band this frame


static func cfg() -> Dictionary:
	return MapLogic.cfg().get("setpieces", {})


static func _n(key: String) -> float:
	return float(cfg()[key])


static func _s(key: String) -> String:
	return str(cfg()[key])


# --- the clock ------------------------------------------------------------------------------

## Beats since `start_ms` on Pulse's clock (`now_ms`, `tempo_ms`), stretched by the debug slow factor.
static func beats(start_ms: float, now_ms: float, tempo_ms: float, slow := 1.0) -> float:
	return maxf(now_ms - start_ms, 0.0) / maxf(tempo_ms, 1.0) / maxf(slow, 0.001)


## The beat number at hop 0 (Covington): the tempo pulse sounds when it changes. Taken from the
## clock, not Pulse.phase, so reduced motion (a steady phase) never silences it.
static func beat_index(now_ms: float, tempo_ms: float) -> int:
	return floori(now_ms / maxf(tempo_ms, 1.0))


# --- the valve swing ------------------------------------------------------------------------

## Covington's stem shares `t` beats into a swing from `from` to `to`: the dive's in-out ease over
## valve_beats; reduced motion snaps to `to`.
static func valve_shares(from: Dictionary, to: Dictionary, t: float, reduced: bool) -> Dictionary:
	var e := 1.0 if reduced else TransitionLogic.ease_t(t / _n("valve_beats"), _n("valve_ease_power"))
	var out := {}
	for k in ValveLogic.KEYS:
		out[k] = lerpf(float(from.get(k, 0.0)), float(to.get(k, 0.0)), e)
	return out


## How much brighter the stems draw (1 at the commit, 0 after the beat): fading over the beat, or
## held for the beat under reduced motion (a step, not a motion).
static func valve_bright(t: float, reduced: bool) -> float:
	var d := _n("valve_beats")
	if t >= d:
		return 0.0
	return 1.0 if reduced else 1.0 - t / d


static func valve_done(t: float) -> bool:
	return t >= _n("valve_beats")


## True when two valves differ by more than valve_eps in any share.
static func valve_moved(a: Dictionary, b: Dictionary) -> bool:
	for k in ValveLogic.KEYS:
		if absf(float(a.get(k, 0.0)) - float(b.get(k, 0.0))) > _n("valve_eps"):
			return true
	return false


# --- the flip -------------------------------------------------------------------------------

## How many of the ring's reink_segments have turned green `t` beats in: one more each
## reink_beats / reink_segments, the last exactly at reink_beats; all at once under reduced motion.
static func reink_count(t: float, reduced: bool) -> int:
	var n := int(_n("reink_segments"))
	if reduced:
		return n
	return clampi(floori(n * t / _n("reink_beats")), 0, n)


static func reink_done(t: float, reduced: bool) -> bool:
	return reduced or t >= _n("reink_beats")


## Segment `i` of `n` around a ring, in order from 12 o'clock clockwise (screen y is down): its
## start and end angles.
static func segment_arc(i: int, n: int) -> Vector2:
	var w := TAU / maxf(n, 1)
	return Vector2(-PI * 0.5 + w * i, -PI * 0.5 + w * (i + 1))


## Whether `fort_id`'s flip is the game's first: no other fort has ever flipped and this one at most
## once. That holds whether the views already count this flip or not yet.
static func first_flip(fort_id: String, forts: Array) -> bool:
	for f in forts:
		var c := int(f.get("flipped_count", 0))
		if str(f.get("id", "")) == fort_id:
			if c > 1:
				return false
		elif c > 0:
			return false
	return true


static func first_flip_text(fort_name: String) -> String:
	return _s("first_flip_fmt") % fort_name


## The map's last dive into a fort: {fort, held} (held when Relish dove), or {}. Static so it
## outlives the map scene, which is freed during the raid (as MapHud._next does).
static var _last_dive := {}


## The map dove into `fort_id` (an empty id, for Covington or Vei, records nothing to match) while the
## fort was `held` or not. Only the last dive is kept.
static func note_dive(fort_id: String, held: bool) -> void:
	_last_dive = {"fort": fort_id, "held": held}


## What the map says on mounting after a scene: TAKEN, RETREAT or "" (no line). `arrive_from` is the
## node just left, `fort` its view (empty for Covington, Vei or none), `taken_event` whether the
## router replayed this fort's fort_flipped, `relish` view_relish, `dive` note_dive's record (default
## the last one). A real event is always taken. Without one, a fort held within its grace counts as
## taken (the no-snapshot swap can deliver fort_flipped after the map mounts), unless it was already
## held when Relish dove: that raid took nothing, so it says nothing. No record for this fort (a
## harness teleport that never dove from the map) allows the fallback. A fort still Vei's with Relish
## alive is a retreat (she keeps what she found); a death, a held fort past its grace and any other
## scene say nothing.
static func return_kind(arrive_from: String, fort: Dictionary, taken_event: bool, relish: Dictionary, dive := _last_dive) -> String:
	if arrive_from == "" or fort.is_empty() or str(fort.get("id", "")) != arrive_from:
		return ""
	if taken_event:
		return TAKEN
	var held := bool(fort.get("held", false))
	if held:
		var was_held := str(dive.get("fort", "")) == arrive_from and bool(dive.get("held", false))
		return TAKEN if float(fort.get("grace_s_left", 0.0)) > 0.0 and not was_held else ""
	if float(relish.get("dead_s_left", 0.0)) > 0.0 or str(relish.get("state", "")) == "dead":
		return ""
	return RETREAT


## The return line for `kind` (TAKEN or RETREAT) at a fort named `fort_name`; "" for any other kind.
static func return_text(kind: String, fort_name: String) -> String:
	match kind:
		TAKEN:
			return _s("taken_fmt") % fort_name
		RETREAT:
			return _s("retreat_fmt") % fort_name
	return ""


## The first flip's green ripple at the fort's beat `phase` (Pulse.phase at its hops): {reach
## (0..1 of ripple_reach_px), alpha} while t < ripple_beats; {} after it and under reduced motion.
static func ripple(phase: float, t: float, reduced: bool) -> Dictionary:
	if reduced or t >= _n("ripple_beats"):
		return {}
	return {"reach": phase, "alpha": pow(1.0 - phase, 2.0) * _n("ripple_alpha")}


## A callout's alpha `t` beats into its `dur`: 1, fading out over the last callout_fade_beats,
## 0 after; under reduced motion 1 for the whole of it, with no fade.
static func callout_alpha(t: float, dur: float, reduced: bool) -> float:
	if t < 0.0 or t >= dur:
		return 0.0
	if reduced:
		return 1.0
	return clampf((dur - t) / maxf(_n("callout_fade_beats"), 0.001), 0.0, 1.0)


# --- bands along a lane (the tithe tide, the garrison's WAR pulse) ---------------------------

## A lane's track for a band: the curve MapLogic.lane_curve_for draws for `row` from `a` to `b`,
## sampled, its cumulative arc length, and the drawn range lo..hi (NodeLogic.trim_lengths of the
## two nodes' outer radii, so a band never crosses a node's rings).
static func track(row: Dictionary, a: Vector2, b: Vector2, r_from: float, r_to: float, samples: int) -> Dictionary:
	var c := MapLogic.lane_curve_for(row, a, b, 0.0)
	var pts := MapLogic.sample_quad(c["a"], c["c"], c["b"], samples)
	var cum := cumulative(pts)
	var length := cum[cum.size() - 1] if cum.size() > 0 else 0.0
	var trim := NodeLogic.trim_lengths(r_from, r_to, length)
	return {"pts": pts, "cum": cum, "lo": float(trim["start"]), "hi": length - float(trim["end"])}


static func cumulative(pts: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	for i in range(1, pts.size()):
		cum[i] = cum[i - 1] + pts[i - 1].distance_to(pts[i])
	return cum


## A band `band` px long whose head is `x` (0..1) of the way from lo to hi: its arc range.
static func band_range(x: float, band: float, lo: float, hi: float) -> Vector2:
	var s := lerpf(lo, hi, clampf(x, 0.0, 1.0))
	return Vector2(maxf(lo, s - band), s)


## The tithe tide `t` beats in, from Vei (lo) toward the fort (hi): the band's arc range over
## tide_beats; under reduced motion the whole lane, still, for tide_beats; NONE after.
static func tide(t: float, reduced: bool, lo: float, hi: float) -> Vector2:
	var d := _n("tide_beats")
	if t >= d:
		return NONE
	if reduced:
		return Vector2(lo, hi)
	return band_range(t / d, _n("tide_band_px"), lo, hi)


## The points of a sampled curve between arc lengths s0 and s1 (its end points interpolated).
static func sub_polyline(pts: PackedVector2Array, cum: PackedFloat32Array, s0: float, s1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2 or s1 <= s0:
		return out
	out.append(LaneStyle.point_at(pts, cum, s0))
	for i in pts.size():
		if cum[i] > s0 and cum[i] < s1:
			out.append(pts[i])
	out.append(LaneStyle.point_at(pts, cum, s1))
	return out


# --- the garrison cleared -------------------------------------------------------------------

## The real event (api-request #10), counter_garrison_cleared {fort_id, killed_mass}: {fort_id, n}
## with n her killed mass, rounded. {} for any other event.
static func garrison_from_event(ev: Dictionary) -> Dictionary:
	if str(ev.get("type", "")) != "counter_garrison_cleared":
		return {}
	return {"fort_id": str(ev.get("fort_id", "")), "n": maxi(roundi(float(ev.get("killed_mass", 0.0))), 0)}


## The callout: "Vei's living routed: −N".
static func garrison_text(n: int) -> String:
	return _s("garrison_fmt") % MapLogic.fmt_mass(n)


## Her counter-garrison as the chip counts it down, x (0..1) of the way through the drain: n at
## the start, 0 only at the end.
static func drain_count(n: int, x: float) -> int:
	return clampi(ceili(n * (1.0 - clampf(x, 0.0, 1.0))), 0, n)


## The garrison set piece `t` beats in, for a counter-garrison of `n`:
##   pulse    0..1, the WAR band from Covington to the fort (-1: none);
##   burst    0..1, the green rings at the fort once the pulse lands (-1: none);
##   ring     true: the burst's still ring (reduced motion);
##   chip     the chip's line two: {} the live chip; {text, key, squash} her counter draining to 0,
##            then flipping (squash 1 -> 0) to {live: true,
##            squash 0 -> 1}, the live margin word;
##   callout  its alpha; done.
## Reduced motion: the end state at once (the live word, the callout, the still ring).
static func garrison(t: float, n: int, reduced: bool) -> Dictionary:
	var pb := _n("garrison_pulse_beats")
	var db := _n("garrison_drain_beats")
	var fb := _n("garrison_flip_beats")
	var cb := _n("garrison_callout_beats")
	var out := {"pulse": -1.0, "burst": -1.0, "ring": false, "chip": {}, "callout": 0.0, "done": false}
	if reduced:
		out["ring"] = t < cb
		out["callout"] = callout_alpha(t, cb, true)
		out["done"] = t >= cb
		return out
	var end := maxf(pb + _n("garrison_burst_beats"), maxf(pb + db + fb, pb + cb))
	out["done"] = t >= end
	if t < pb:
		out["pulse"] = t / pb
		return out
	var u := t - pb
	if u < _n("garrison_burst_beats"):
		out["burst"] = u / _n("garrison_burst_beats")
	out["callout"] = callout_alpha(u, cb, false)
	var text := _s("garrison_counter_fmt") % MapLogic.fmt_mass(drain_count(n, u / db))
	if u < db:
		out["chip"] = {"text": text, "key": "living", "squash": 1.0}
	elif u < db + fb * 0.5:
		out["chip"] = {"text": text, "key": "living", "squash": 1.0 - (u - db) / (fb * 0.5)}
	elif u < db + fb:
		out["chip"] = {"live": true, "squash": (u - db - fb * 0.5) / (fb * 0.5)}
	return out


# --- a finished build (the callout at Covington) ----------------------------------------------
# The sim's own projection (view_catalog's `projected`, view_town's `upgrade_projected`) is the
# honest number, but it moves on to the next level once a build is done, so the model keeps the
# last real one it read per pending build in a store: {"lot:level": {building_id, rates}}.

static func proj_key(lot_id: String, level: int) -> String:
	return "%s:%d" % [lot_id, level]


## Built lots from view_town().buildings: {lot_id: {building_id, level}}. A first build under way is
## level 0 and an upgrade under way still reads its old level, so a level only rises on `done`.
static func lot_levels(buildings: Array) -> Dictionary:
	var out := {}
	for b in buildings:
		out[str(b["lot_id"])] = {"building_id": str(b["building_id"]), "level": int(b["level"])}
	return out


## The builds that finished between two snapshots of lot_levels: a lot whose level rose, or whose
## building changed, [{lot_id, building_id, level}] by lot id. A level-0 lot has built nothing yet.
static func rises(before: Dictionary, now: Dictionary) -> Array:
	var out: Array = []
	var ids := now.keys()
	ids.sort()
	for id in ids:
		var n: Dictionary = now[id]
		if int(n["level"]) < 1:
			continue
		var b: Dictionary = before.get(id, {})
		if b.is_empty() or str(b["building_id"]) != str(n["building_id"]) or int(n["level"]) > int(b["level"]):
			out.append({"lot_id": str(id), "building_id": str(n["building_id"]), "level": int(n["level"])})
	return out


## The mount's `rises` to announce: none when the away panel opens for this return (the away
## report already lists the builds that finished, so a callout would say them twice).
static func mount_builds(mount_rises: Array, away_opens: bool) -> Array:
	return [] if away_opens else mount_rises


## Whether a catalog read is worth its cost: a build is queued or under construction.
static func has_pending(town: Dictionary) -> bool:
	if not (town.get("queue", []) as Array).is_empty():
		return true
	for b in town.get("buildings", []):
		if str(b.get("state", "")) == "constructing":
			return true
	return false


## The new builds (not upgrades) waiting or under way, whose projection the catalog holds by
## building id: queued rows, and a first build under construction. [{lot_id, building_id, level: 1}].
static func pending_new(town: Dictionary) -> Array:
	var out: Array = []
	for q in town.get("queue", []):
		if not bool(q.get("upgrade", false)) and str(q.get("lot_id", "")) != "":
			out.append({"lot_id": str(q["lot_id"]), "building_id": str(q["building_id"]), "level": 1})
	for b in town.get("buildings", []):
		if str(b.get("state", "")) == "constructing" and int(b["level"]) == 0:
			out.append({"lot_id": str(b["lot_id"]), "building_id": str(b["building_id"]), "level": 1})
	return out


## Stores each built lot's upgrade_projected at the lot's next level. An empty one (cold, or the lot
## is constructing) never overwrites the last real value.
static func note_upgrades(store: Dictionary, buildings: Array) -> void:
	for b in buildings:
		var p: Dictionary = b.get("upgrade_projected", {})
		if not p.is_empty():
			store[proj_key(str(b["lot_id"]), int(b["level"]) + 1)] = {"building_id": str(b["building_id"]), "rates": p.duplicate()}


## Stores the catalog's `projected` for each pending new build (by building id) at its lot, level 1;
## an empty row keeps what was stored.
static func note_catalog(store: Dictionary, pending: Array, rows: Array) -> void:
	for p in pending:
		for r in rows:
			if str(r.get("building_id", "")) == str(p["building_id"]):
				var rates: Dictionary = r.get("projected", {})
				if not rates.is_empty():
					store[proj_key(str(p["lot_id"]), int(p["level"]))] = {"building_id": str(p["building_id"]), "rates": rates.duplicate()}
				break


## The stored rates of `building_id` on `lot_id` at `level`: {} when none (or another building's).
static func projection_for(store: Dictionary, lot_id: String, building_id: String, level: int) -> Dictionary:
	var e: Dictionary = store.get(proj_key(lot_id, level), {})
	if e.is_empty() or str(e["building_id"]) != building_id:
		return {}
	return e["rates"]


## `build` joins the callout's builds unless that lot and level is already in it (the router
## re-emits a building_done it held while the map mounted, and the mount's diff found the same one).
static func add_build(builds: Array, build: Dictionary) -> Array:
	for b in builds:
		if str(b["lot_id"]) == str(build["lot_id"]) and int(b["level"]) == int(build["level"]):
			return builds
	return builds + [build]


## The stream with the biggest |change| among build_rate_ids (the HUD's own streams, so work, war
## and flood, which are the mint again, and corpses and backlog, which have no label, never lead):
## {id, delta}, or {} when none reaches build_eps. A tie goes to the earlier stream.
static func biggest(rates: Dictionary) -> Dictionary:
	var best := {}
	for id in cfg()["build_rate_ids"]:
		var d := float(rates.get(id, 0.0))
		if absf(d) >= _n("build_eps") and (best.is_empty() or absf(d) > absf(float(best["delta"]))):
			best = {"id": str(id), "delta": d}
	return best


## The callout's line: "Inn built · MINT +0.8/s"; several builds, rates summed: "2 builds: Inn ·
## Bakery · MINT +1.1/s"; with no recorded projection (or every change under build_eps) the
## builds alone. `names` maps a building id to its label (buildings_view.json).
static func build_text(builds: Array, store: Dictionary, names: Dictionary) -> String:
	var labels: Array = []
	var sum := {}
	for b in builds:
		var id := str(b["building_id"])
		labels.append(str(names.get(id, id.capitalize())))
		var rates := projection_for(store, str(b["lot_id"]), id, int(b["level"]))
		for k in rates:
			sum[k] = float(sum.get(k, 0.0)) + float(rates[k])
	var sep := _s("build_sep")
	var head := _s("build_one_fmt") % labels[0] if labels.size() == 1 else _s("build_many_fmt") % [labels.size(), sep.join(labels)]
	var big := biggest(sum)
	if big.is_empty():
		return head
	return "%s%s%s %s" % [head, sep, str(HudLogic.LABELS.get(big["id"], str(big["id"]).to_upper())), MapLogic.fmt_rate(float(big["delta"]))]


## The line's runs by font (AwayLogic.spans): the signed rate is the rate face, the rest labels.
static func build_spans(text: String) -> Array:
	return AwayLogic.spans(text)


## The plate's alpha `t` beats in: full, fading over the last callout_fade_beats; under reduced
## motion full until it is gone.
static func build_alpha(t: float, reduced: bool) -> float:
	return callout_alpha(t, _n("build_beats"), reduced)


static func build_done(t: float) -> bool:
	return t >= _n("build_beats")


# --- victory --------------------------------------------------------------------------------

## RUN for victory_run_beats (every lane green, running toward Vei), then STOP (every dash frozen,
## the victory line up). Reduced motion: STOP at once.
static func victory_phase(t: float, reduced: bool) -> String:
	return STOP if reduced or t >= _n("victory_run_beats") else RUN


## The u a lane draws at in victory: its own, floored at victory_u_floor, so a dark lane lights.
static func victory_u(u: float) -> float:
	return maxf(u, _n("victory_u_floor"))


# --- debug triggers -------------------------------------------------------------------------

## --setpiece=<kind> and --setpiece-slow=<k>, debug sessions only: {kind ("" none), slow (1 none)}.
static func debug_args(args: Array, debug: bool) -> Dictionary:
	var out := {"kind": "", "slow": 1.0}
	if not debug:
		return out
	for a in args:
		var s := str(a)
		if s.begins_with("--setpiece="):
			var k := s.trim_prefix("--setpiece=")
			if KINDS.has(k):
				out["kind"] = k
		elif s.begins_with("--setpiece-slow=") and s.trim_prefix("--setpiece-slow=").is_valid_float():
			var f := s.trim_prefix("--setpiece-slow=").to_float()
			if f > 0.0:
				out["slow"] = f
	return out


## The debug trigger's fort: `preferred` if the realm has it, else the first held fort, else the
## first fort ("" with none).
static func demo_target(forts: Array, preferred: String) -> String:
	var held := ""
	for f in forts:
		if str(f.get("id", "")) == preferred:
			return preferred
		if held == "" and bool(f.get("held", false)):
			held = str(f["id"])
	if held != "":
		return held
	return str(forts[0].get("id", "")) if not forts.is_empty() else ""


## The debug swing's valve: debug_valve, or debug_valve_alt when the target already is it.
static func demo_valve(target: Dictionary) -> Dictionary:
	var v: Array = cfg()["debug_valve"]
	var out := {"work": float(v[0]), "war": float(v[1]), "flood": float(v[2])}
	if not valve_moved(out, target):
		var alt: Array = cfg()["debug_valve_alt"]
		out = {"work": float(alt[0]), "war": float(alt[1]), "flood": float(alt[2])}
	return out
