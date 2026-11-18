class_name NodeLogic
extends RefCounted
## Pure logic for the map's nodes (no autoloads, so headless tests compile it): pip counts and
## arc fractions, tier notches, each fort's state glyph and tithe badge, the held and tithe
## countdowns, the backlog ring stack, the valve glyph's widths and directions, Relish's
## interpolation, size, wake and light, the label plate, and the --nodes=demo stand-ins.
## Pulse-derived values come in as arguments. Tuning: configs/map_view.json "nodes".

const COVINGTON := "covington"
const MATTERS := ["living", "undead", "dead"]
## A fort's state glyph when it is not held (held forts show their margin: IdleLogic's safe / thin
## / will_fall), or HELD when a held fort has no margin.
const HELD := "held"
const HERS := "hers"
const OVERRUN := "overrun"
const CONTESTED := "contested"
const EMPTIED := "emptied"


static func ncfg() -> Dictionary:
	return MapLogic.cfg().get("nodes", {})


static func _n(key: String) -> float:
	return float(ncfg().get(key, 0.0))


## The node labels' texts, keyed war / flood / work / covington / vei (configs/map_view.json
## "node_names"): the one source the layers draw from and IdleLogic's obstacles are measured from.
static func node_names() -> Dictionary:
	return MapLogic.cfg().get("node_names", {})


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


## The one glanceable state a fort shows (its centre glyph). Held: its margin, `margin` (the
## model's margin_of, so it always agrees with the chip): safe, thin or will_fall. Only "safe" is
## safe: "" or anything else is HELD, held with no margin to show (never SAFE). Not held, a side is present at
## state_present_frac of capacity or more (the mass that rounds to one pip):
##   overrun    your undead present and the living not: still Vei's (never taken in a raid), so it
##              draws like hers, contested and emptied: the hairline ring, no core;
##   contested  both sides present, and the undead at least contested_frac of the living, or
##              both at contested_floor_frac of capacity or more;
##   hers       otherwise, when the living are present;
##   emptied    neither side present (the dead remain, or nothing does).
## Held beats everything; overrun and contested never overlap; contested beats hers.
static func fort_state(f: Dictionary, margin: String) -> String:
	if bool(f.get("held", false)):
		return margin if margin in [IdleLogic.SAFE, IdleLogic.THIN, IdleLogic.WILL_FALL] else HELD
	var cap := maxf(float(f.get("cap", 0.0)), 0.0)
	var u := float(f.get("undead", 0.0))
	var l := float(f.get("living", 0.0))
	var present := _n("state_present_frac") * cap
	var und_here := cap > 0.0 and u >= present and u > 0.0
	var liv_here := cap > 0.0 and l >= present and l > 0.0
	var floor_m := _n("contested_floor_frac") * cap
	if und_here and not liv_here:
		return OVERRUN
	if und_here and (u >= _n("contested_frac") * l or (u >= floor_m and l >= floor_m)):
		return CONTESTED
	if liv_here:
		return HERS
	return EMPTIED


## Ownership by weight, so it survives greyscale: forts you hold (held, any margin: you broke the
## warden in a raid) draw the outer ring held_ring_weight times the hairline. Hers, contested,
## emptied and overrun (your undead inside, never taken) keep the hairline (1).
## In the overview tiers (nodes.overview_tiers: every tier below near) it is held_overview_mult
## heavier again, so ownership reads in greyscale at a glance.
static func ring_weight(state: String, zoom_tier := "") -> float:
	if not yours(state):
		return 1.0
	return _n("held_ring_weight") * (_n("held_overview_mult") if is_overview(zoom_tier) else 1.0)


## Whether `zoom_tier` is one of the overview tiers (far and mid; near is not).
static func is_overview(zoom_tier: String) -> bool:
	return zoom_tier in ncfg().get("overview_tiers", [])


## The palette key a fort's name is drawn in: full text in the overview tiers (so Whitecross and
## Sable Hold read when the map is small), text_dim at near.
static func fort_label_key(zoom_tier: String) -> String:
	return "text" if is_overview(zoom_tier) else "text_dim"


## The same forts fill their inner core; hers, contested, emptied and overrun stay open.
static func has_core(state: String) -> bool:
	return yours(state)


## You hold the fort: held at any margin. Overrun is not yours (it is Vei's until you break its
## warden in a raid).
static func yours(state: String) -> bool:
	return state in [IdleLogic.SAFE, IdleLogic.THIN, IdleLogic.WILL_FALL, HELD]


## The state glyph's alpha on the forts' beat (`w`: Pulse.wave at their hop). MapNodes sets it as
## the beating glyph layer's modulate, so the beat costs no redraw.
static func state_alpha(w: float) -> float:
	return _n("state_alpha_base") + _n("state_alpha_wave") * w


## What a fort's static rings draw, quantized to static_sig_steps of a turn so sub-pixel drift (a
## few bodies, a second of the held countdown) does not redraw it: the pip layout, each matter's
## arc, held and its countdown sweep, a simulacrum, the name tag's text (name_tag), tier and name, the
## ring's weight and core (from the fort's `state`, NodeLogic.fort_state) and the raid marker
## (`raid`: MapModel.raid_why for the fort, its why in the model's raid set or "").
## MapNodes redraws a fort's static layer only when this (or the zoom, selection or light) changes.
static func fort_static_sig(f: Dictionary, flip: Dictionary, state := "", raid := "", zoom_tier := "") -> Array:
	var steps := _n("static_sig_steps")
	var fr := arc_fracs(f)
	return [pip_layout(f), roundi(fr["living"] * steps), roundi(fr["undead"] * steps), roundi(fr["dead"] * steps),
		bool(f.get("held", false)), roundi(held_fraction(f, flip) * steps), float(f.get("simulacrum_charges", 0.0)) > 0.0,
		str(name_tag(f).get("text", "")), int(f.get("tier", 1)), str(f.get("name", "")), ring_weight(state, zoom_tier), has_core(state),
		raid != ""]


## A tithe is on its way to this fort (targeted, or the wave is on): the glyph's triangle badge.
static func tithe_badge(f: Dictionary) -> bool:
	var m := tithe_mode(f)
	return m == "warning" or m == "wave"


## Half the state glyph's extent in world px at `zoom`: state_glyph_px on screen at every zoom.
static func state_glyph_half(zoom: float) -> float:
	return _n("state_glyph_px") * 0.5 / maxf(zoom, 0.001)


## How long a flip holds: hold_s x (1 + tier_mult x tier) (realm.json "flip").
# TODO(api E2): grace total not in view_fort
static func grace_total(flip: Dictionary, tier: int) -> float:
	return float(flip.get("hold_s", 0.0)) * (1.0 + float(flip.get("tier_mult", 0.0)) * tier)


## The held countdown's sweep, 0..1: grace_s_left / grace_total (0 when not held). grace_s_left is
## the seconds of grace left after you take a fort; at 0 Vei contests it (the fort is not lost).
static func held_fraction(f: Dictionary, flip: Dictionary) -> float:
	if not bool(f.get("held", false)):
		return 0.0
	var g := grace_total(flip, int(f.get("tier", 1)))
	if g <= 0.0:
		return 0.0
	return clampf(float(f.get("grace_s_left", 0.0)) / g, 0.0, 1.0)


## "wave" while the tithe wave is on this fort, "warning" while it is targeted, "next" while it is
## only Vei's next pick, else "".
static func tithe_mode(f: Dictionary) -> String:
	var t: Dictionary = f.get("tithe", {})
	if bool(t.get("wave_active", false)):
		return "wave"
	if bool(t.get("targeted", false)):
		return "warning"
	if bool(t.get("next", false)):
		return "next"
	return ""


## The fort is Vei's next tithe pick (not yet warned): the quiet hollow triangle, no ring.
static func tithe_next(f: Dictionary) -> bool:
	return tithe_mode(f) == "next"


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


## The one line under a fort's name, {text, key} (key: a Palette key), or {} for none:
##   the first dungeon (its first clear still pays a blueprint): relish;
##   retaken (not held, flipped before: Vei took it back): danger;
##   overrun (not held, your undead inside, never taken): `label_tag_keys.overrun` (text).
## Drawn at tag_size() px, at least the name's.
static func name_tag(f: Dictionary) -> Dictionary:
	var n := ncfg()
	var keys: Dictionary = n["label_tag_keys"]
	if first_dungeon_pulse(f):
		return {"text": str(n["label_first_dungeon"]), "key": str(keys["first"])}
	if not bool(f.get("held", false)):
		if int(f.get("flipped_count", 0)) > 0:
			return {"text": str(n["label_retaken"]), "key": str(keys["retaken"])}
		if fort_state(f, "") == OVERRUN:
			return {"text": str(n["label_overrun"]), "key": str(keys["overrun"])}
	return {}


## The tag line's font size in screen px (the name's is font_label).
static func tag_size() -> int:
	return int(_n("label_tag_px"))


## A label's plate in screen px around its anchor, as MapNodeLayer.draw_label draws it: the text of
## width `w` starting at x, its baseline `dy` below the anchor, `size` px tall.
static func label_plate(x: float, w: float, size: int, dy: float) -> Rect2:
	var pad := _n("plate_pad_px")
	return Rect2(x - pad, dy - size * _n("plate_ascent"), w + pad * 2.0, size * _n("plate_height"))


## The plates a fort's labels cover, in screen px around the label anchor (the fort's position plus
## r + label_off_px down): its name (baseline `size`), and, when `tag_w` >= 0, its tag line under it
## (baseline `size` + label_line_px). Both are centred. The lane callouts keep clear of them.
static func fort_label_rects(name_w: float, tag_w: float, size: int) -> Array:
	var out: Array = [label_plate(-name_w * 0.5, name_w, size, float(size))]
	if tag_w >= 0.0:
		out.append(label_plate(-tag_w * 0.5, tag_w, tag_size(), float(size) + _n("label_line_px")))
	return out


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


## Where the valve's four labels go, in SCREEN px from Covington's centre (the glyph scales with
## the zoom, the text does not). Each stem's label sits beyond the stem's end along its direction
## and is pushed further out until its rect clears every other label and every other piece of
## the glyph; COVINGTON sits centred below the glyph, pushed down (else up) until clear of the
## stems and the WORK hook. `widths`: valve_widths (a stem with 0 is not drawn, so it is no
## obstacle and has no label); `labels_on`: stem labels show (not at far zoom); `text_w`: each
## label's width in screen px, keyed war / flood / work / covington; `size`: the font size.
## Returns {key: {off, align (-1 left, 0 centre, 1 right), dy, rect}}: `off` is the text anchor,
## `dy` the baseline drop (MapNodeLayer.text's convention), `rect` the plate the text covers.
static func valve_label_layout(dirs: Dictionary, widths: Dictionary, labels_on: bool, zoom: float,
		text_w: Dictionary, size: float) -> Dictionary:
	var pad := _n("valve_label_pad_px")
	var step := maxf(_n("valve_label_step_px"), 1.0)
	var tries := int(_n("valve_label_tries"))
	var gap := _n("valve_label_gap_px")
	var inner := _n("valve_in_px") * zoom
	var tip := inner + _n("valve_len_px") * zoom
	var hr := _n("valve_hook_r_px") * zoom
	var eps := _n("valve_label_axis_eps")
	var half_w := _n("valve_glyph_max_w") * 0.5
	var h := _n("cov_half_px") * zoom
	var obstacles := {"glyph": Rect2(-h, -h, h * 2.0, h * 2.0).grow(_n("cov_width_px"))}
	for k in ["war", "flood"]:
		if widths.get(k, 0.0) > 0.0:
			var d: Vector2 = dirs[k]
			obstacles[k] = Rect2(d * inner, Vector2.ZERO).expand(d * tip).grow(half_w)
	var hook_c: Vector2 = dirs["work"] * (inner + hr)
	if widths.get("work", 0.0) > 0.0:
		obstacles["work"] = Rect2(hook_c - Vector2(hr, hr), Vector2(hr, hr) * 2.0).grow(half_w)
	var out := {}

	var plate := func(off: Vector2, align: int, dy: float, w: float) -> Rect2:
		var x := off.x - (w * 0.5 if align == 0 else (w if align == 1 else 0.0))
		return Rect2(x, off.y + dy - size * _n("plate_ascent"), w, size * _n("plate_height"))
	var clear := func(r: Rect2) -> bool:
		for k in obstacles:
			if r.grow(pad).intersects(obstacles[k]):
				return false
		for k in out:
			if r.grow(pad).intersects(out[k]["rect"]):
				return false
		return true

	if labels_on:
		var order := [["war", tip + gap], ["flood", tip + gap], ["work", inner + hr * 2.0 + gap]]
		for e in order:
			var k: String = e[0]
			if widths.get(k, 0.0) <= 0.0:
				continue
			var d: Vector2 = dirs[k]
			var align := 0
			if d.x < -eps:
				align = 1
			elif d.x > eps:
				align = -1
			var dy := size * (1.0 if d.y > eps else (_n("text_mid_ratio") if absf(d.y) <= eps else 0.0))
			var r: float = e[1]
			var rect: Rect2
			var off := Vector2.ZERO
			for i in tries + 1:
				off = d * r
				rect = plate.call(off, align, dy, float(text_w[k]))
				if clear.call(rect):
					break
				r += step
			out[k] = {"off": off, "align": align, "dy": dy, "rect": rect}

	# COVINGTON: centred under the glyph, then pushed down (else up) until it clears everything
	var cw := float(text_w["covington"])
	var cgap := _n("cov_label_gap_px")
	var best := {}
	for sgn in [1.0, -1.0]:
		var y: float = (h + cgap) * sgn
		for i in tries + 1:
			var off := Vector2(0.0, y)
			var dy := size if sgn > 0.0 else 0.0
			var rect: Rect2 = plate.call(off, 0, dy, cw)
			if best.is_empty():
				best = {"off": off, "align": 0, "dy": dy, "rect": rect}
			if clear.call(rect):
				best = {"off": off, "align": 0, "dy": dy, "rect": rect}
				break
			y += step * sgn
		if clear.call(best["rect"]):
			break
		best = {}
	if best.is_empty():
		var off0 := Vector2(0.0, h + cgap)
		best = {"off": off0, "align": 0, "dy": size, "rect": plate.call(off0, 0, size, cw)}
	out["covington"] = best
	return out


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


## Vei's drain line: "queue empty" when there is no backlog (a drain time would read 0s),
## else "drain " + MapLogic.fmt_drain (holding, -1.0, is "∞").
static func drain_line(backlog: float, drain_s: float) -> String:
	if backlog <= 0.0:
		return str(ncfg()["queue_empty_text"])
	return str(ncfg()["drain_prefix"]) + MapLogic.fmt_drain(drain_s)


## The line under Vei's odds: the differential's sign, labelled as her strain, then the drain line
## ("strain ▲ · drain 8m 40s"). The ▲/▼ is the backlog's sign, while the odds are mostly time
## (MECHANICS §3.5), so it never sits beside the percent (E4 step 10, the step 9 review's item 4).
static func strain_line(sign: int, backlog: float, drain_s: float) -> String:
	return str(ncfg()["strain_line_fmt"]) % [MapLogic.sign_glyph(sign), drain_line(backlog, drain_s)]


## Odds as the integer percent the map prints.
static func fmt_odds(odds: float) -> String:
	return "%d%%" % roundi(clampf(odds, 0.0, 1.0) * 100.0)


# --- lane trim -----------------------------------------------------------------------------

## A node's outermost drawn radius, where lanes stop: a fort's ring stack out to its tithe ring,
## Covington's glyph, Vei's structure plus the outer edge of her countable backlog stack (the
## rings shown for `backlog`) or her beat ring, whichever reaches further, plus
## lane_trim_pad_px. kind: "fort", "covington", "vei" (anything else, e.g. a village, gets no trim).
static func outer_radius(kind: String, tier: int, vei_domain_radius: float, backlog := 0.0) -> float:
	var pad := _n("lane_trim_pad_px")
	if kind == "fort":
		return MapLogic.fort_radius(tier) + _n("tithe_off_px") + _n("tithe_halo_max_px") * 0.5 + pad
	if kind == "covington":
		return _n("cov_half_px") + pad
	if kind == "vei":
		return vei_reach(vei_domain_radius, backlog) + pad
	return 0.0


## How far Vei's marks reach from her centre: the structure, then the further of the backlog
## stack's outermost ring (with its halo) and the beat ring at its full reach (with its halo).
static func vei_reach(vei_domain_radius: float, backlog: float) -> float:
	var ro := vei_struct_radius(vei_domain_radius)
	var rings := int(backlog_rings(backlog)["rings"])
	var beat := ro + _n("vei_beat_reach_px") + _n("source_halo_max_px") * 0.5
	if rings <= 0:
		return beat
	var stack := ro + _n("backlog_first_gap_px") + (rings - 1) * _n("backlog_step_px") + _n("backlog_halo_max_px") * 0.5
	return maxf(stack, beat)


## Arc lengths to skip at a lane's two ends: {start, end}. Radii approximate arc length (lanes
## leave nodes nearly radially); the pair is scaled down together so at least half the lane stays.
static func trim_lengths(start_radius: float, end_radius: float, length: float) -> Dictionary:
	var s := maxf(start_radius, 0.0)
	var e := maxf(end_radius, 0.0)
	var room := length * 0.5
	if s + e > room and s + e > 0.0:
		var k := room / (s + e)
		s *= k
		e *= k
	return {"start": s, "end": e}


# --- Relish -----------------------------------------------------------------------------

## Sim seconds to extrapolate Relish by: the real time since the model refreshed, capped at
## relish_extrap_max_s, times the sim speed (0 while paused). The cap is on real time so a fast
## sim speed still glides to the next hop instead of stopping short.
static func extrap_dt(real_s: float, speed_scale: float) -> float:
	return clampf(real_s, 0.0, _n("relish_extrap_max_s")) * maxf(speed_scale, 0.0)


## What the extrapolation clock keys on: her model position, state and target. A model refresh
## that leaves all three alone (a command, an autosave) must not restart the clock.
static func relish_sig(rel: Dictionary) -> Array:
	if rel.is_empty():
		return []
	return [MapModel.to_vec(rel["pos"]), str(rel.get("state", "")), str(rel.get("target", ""))]


## True when her drawn position moved farther than wake_jump_px since the last refresh (a new
## game, a fixture, a teleport): the wake must be cleared, not stretched across the map.
static func wake_jumped(prev: Vector2, cur: Vector2) -> bool:
	return prev.distance_to(cur) > _n("wake_jump_px")


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


## Relish's token radii in world px at `zoom`, {core, halo, wide}: the core and halo never under
## relish_min_core_px / relish_min_halo_px screen px (radii), the wide faint beat ring
## relish_wide_mult x the halo.
static func relish_radii(zoom: float) -> Dictionary:
	var z := maxf(zoom, 0.001)
	var halo := maxf(_n("relish_halo_r_px"), _n("relish_min_halo_px") / z)
	return {"core": maxf(_n("relish_core_r_px"), _n("relish_min_core_px") / z), "halo": halo,
		"wide": halo * _n("relish_wide_mult")}


## Ids of the forts within `radius` of Relish: their dead turn dead_lit.
static func lit_fort_ids(forts: Array, relish_pos: Vector2, radius: float) -> Array:
	var out: Array = []
	for f in forts:
		if MapModel.to_vec(f["pos"]).distance_to(relish_pos) <= radius:
			out.append(f["id"])
	return out


# --- labels ---------------------------------------------------------------------------------

## The plate behind every node label: the ground at label_plate_alpha.
static func label_plate_color() -> Color:
	return Palette.c("ground", _n("label_plate_alpha"))


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
## screenshot shows what E2 will: held forts at each margin, a tithe warning, a live wave, an
## overrun, a contested and an emptied fort (whatever the fixture holds), the first-dungeon pulse, a
## simulacrum, Relish mid-travel and a full backlog stack. Values: map_view.json "demo_nodes".
## Relish stands still (speed 0) so her place holds between refreshes; her ETA is the rest of the
## way at `travel_speed` (realm.json relish.travel_speed), so stills never read 0:00.
# TODO(api E2): debug stand-in
static func demo_overlay(forts: Array, vei: Dictionary, hud: Dictionary, relish: Dictionary, cov_pos: Vector2, flip: Dictionary, travel_speed := 0.0) -> void:
	var d: Dictionary = MapLogic.cfg().get("demo_nodes", {})
	var by_id := {}
	for f in forts:
		by_id[f["id"]] = f
	var held_all: Array = [d.get("held", {})]
	held_all.append_array(d.get("also_held", []))
	for held in held_all:
		if by_id.has(held.get("fort", "")):
			var f: Dictionary = by_id[held["fort"]]
			f["held"] = true
			f["flipped_count"] = 1
			f["grace_s_left"] = float(held["frac"]) * grace_total(flip, int(f["tier"]))
			f["ship_in"] = float(held.get("ship_in", 0.0))  # the idle surfaces' pressure and garrison
			f["undead"] = float(held.get("undead", f.get("undead", 0.0)))
			# the view's hold readouts, written out as the economy would give them
			f["garrison"] = f["undead"]
			f["margin"] = str(held.get("margin", ""))
			f["garrison_rate"] = float(held.get("garrison_rate", 0.0))
			f["fall_s"] = float(held.get("fall_s", -1.0))
	var supports := 0
	var held_n := 0
	for f in forts:
		if bool(f.get("held", false)):
			held_n += 1
			if str(f.get("margin", "")) != IdleLogic.WILL_FALL:
				supports += 1
	hud["war_supports"] = {"n": supports, "m": held_n}
	for mt in d.get("matter", []):  # fort state glyphs: an overrun, a contested and an emptied fort
		if by_id.has(mt.get("fort", "")):
			var mf: Dictionary = by_id[mt["fort"]]
			for k in MATTERS:
				mf[k] = float(mt.get(k, mf.get(k, 0.0)))
	if d.has("mint_rate"):  # the valve's WAR split needs a mint rate; E1's is 0
		var split := {}
		var v := ValveLogic.normalise(hud.get("valve_target", hud.get("valve", {})))
		for r in hud.get("rates", []):
			if str(r.get("id", "")) == "mint":
				r["rate"] = float(d["mint_rate"])
		for k in ValveLogic.KEYS:
			split[k] = float(d["mint_rate"]) * float(v[k])
		hud["split"] = split
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
		relish["eta_s"] = float(rd["eta_s"]) if rd.has("eta_s") else RelishLogic.eta_s(p.distance_to(to), travel_speed)  # demo_nodes.relish.eta_s, else the rest of the way at her real pace
	var vd: Dictionary = d.get("vei", {})
	if not vd.is_empty():
		vei["backlog"] = float(vd["backlog"])
		# the reading lives in view_hud (MapModel.readout); Vei's node and the top bar share it
		hud["sign"] = int(vd["sign"])
		hud["drain_s"] = float(vd["drain_s"])
		hud["odds"] = float(vd["odds"])


## Overlays a siege and Relish's party (in place) so one near-zoom shot shows the big undead on
## the map: demo_nodes.siege's units placed at its fort (fort.siege, and their entries in `units`
## and `names`), and demo_nodes.party as view_party().party. Entries are view_big_undead-shaped.
# TODO(api E2): debug stand-in
static func demo_army(forts: Array, party: Dictionary, units: Dictionary, names: Dictionary) -> void:
	var d: Dictionary = MapLogic.cfg().get("demo_nodes", {})
	var sg: Dictionary = d.get("siege", {})
	for f in forts:
		if str(f["id"]) == str(sg.get("fort", "")):
			var uids: Array = []
			for e in sg.get("units", []):
				var entry: Dictionary = (e as Dictionary).duplicate()
				entry["place"] = "fort:%s" % f["id"]
				uids.append(str(entry["uid"]))
				units[str(entry["uid"])] = entry
				names[str(entry["uid"])] = str(entry["name"])
			f["siege"] = uids
	if d.has("party"):
		var members: Array = []
		for e in d["party"]:
			var entry: Dictionary = (e as Dictionary).duplicate()
			entry["place"] = "party"
			members.append(entry)
			units[str(entry["uid"])] = entry
			names[str(entry["uid"])] = str(entry["name"])
		party["party"] = members


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
