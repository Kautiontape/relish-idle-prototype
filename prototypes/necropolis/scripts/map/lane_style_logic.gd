class_name LaneStyle
extends RefCounted
## Pure lane styling for the routes renderer (map_routes.gd). Names no autoload, so headless
## tests compile it: Pulse channel dicts and u values are passed in. Holds:
##   - the ribbon mesh builder (a triangle strip; UV.x = arc length, UV.y = -1..1 across);
##   - the per-kind style table (configs/map_view.json lane_kinds plus the commit and hot rules);
##   - the stroke-layer tables the lane shader composites, outermost first: a lit lane's
##     LineGlow.layers() (halos capped at halo_max_px, the core a hairline), the dead gutter's
##     spill / cut / lip / rim (06-three-flow-geometry c5, the spill kept off the host's core),
##     the phantom bank;
##   - the on-screen stroke rules the shader applies (drawn_stroke, spill_clip), as pure mirrors;
##   - dash motion per kind, ring dash quantisation, haul cart spacing and pips.
## Ribbon sides: UV.y = +1 is MapLogic's +perp side, (-dir.y, dir.x), the right of travel on
## screen. Lanes bow and gutters shift to -perp, so a gutter's host lies on its +UV.y side.

const OFF := -1.0  # Pulse.OFF (a logic file may not name the autoload)
const COVINGTON := "covington"
const VEI := "vei"
const MAX_LAYERS := 4


static func _cfg() -> Dictionary:
	return MapLogic.cfg()


static func _num(key: String) -> float:
	return float(_cfg().get(key, 0.0))


static func _sub(block: String) -> Dictionary:
	return _cfg().get(block, {})


# --- ribbon mesh -----------------------------------------------------------------

## A triangle-strip ribbon along `pts`, two vertices per point at +/- half_width along the
## point's normal (+UV.y first). UV.x is the arc length in world px from the first point;
## `cum` holds it per point. `closed` (a ring whose last point repeats the first) takes the
## normal at the seam from the wrap-around neighbours, so the ring has no kink.
static func ribbon(pts: PackedVector2Array, half_width: float, closed := false) -> Dictionary:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cum := PackedFloat32Array()
	var n := pts.size()
	var s := 0.0
	for i in n:
		if i > 0:
			s += pts[i - 1].distance_to(pts[i])
		var nrm := _normal(pts, i, closed)
		verts.append(pts[i] + nrm * half_width)
		uvs.append(Vector2(s, 1.0))
		verts.append(pts[i] - nrm * half_width)
		uvs.append(Vector2(s, -1.0))
		cum.append(s)
	return {"verts": verts, "uvs": uvs, "cum": cum, "length": s}


## The unit normal at point i (+perp of the local tangent; wrap-around neighbours on a ring).
static func _normal(pts: PackedVector2Array, i: int, closed: bool) -> Vector2:
	var n := pts.size()
	var prev := pts[maxi(i - 1, 0)]
	var next := pts[mini(i + 1, n - 1)]
	if closed and n > 2 and (i == 0 or i == n - 1):
		prev = pts[n - 2]
		next = pts[1]
	var t := (next - prev).normalized()
	return Vector2(-t.y, t.x)


## The smallest cosine between the curve's normals and its chord's normal (1 for a straight
## lane; ~0.95 at a lane_bow lane's ends). A gutter is its host translated across the chord, so
## the lateral gap between them shrinks by this factor where the curve turns away from the chord.
static func lateral_cos_min(pts: PackedVector2Array, from_pos: Vector2, to_pos: Vector2) -> float:
	var dir := (to_pos - from_pos).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var c := 1.0
	for i in pts.size():
		c = minf(c, absf(_normal(pts, i, false).dot(perp)))
	return c


static func to_mesh(r: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = r["verts"]
	arrays[Mesh.ARRAY_TEX_UV] = r["uvs"]
	var m := ArrayMesh.new()
	if (r["verts"] as PackedVector2Array).size() >= 4:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	return m


## `n` + 1 points round a circle, clockwise on screen, the last one repeating the first.
static func ring_points(center: Vector2, radius: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := maxi(n, 3)
	for i in steps + 1:
		pts.append(center + Vector2.from_angle(TAU * float(i % steps) / steps) * radius)
	return pts


## The point `s` px along a sampled curve (`cum` from ribbon()), clamped to its ends.
static func point_at(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	var n := pts.size()
	if n == 0:
		return Vector2.ZERO
	if s <= 0.0 or n == 1:
		return pts[0]
	var hi := cum.bsearch(s)
	if hi >= n:
		return pts[n - 1]
	var span := cum[hi] - cum[hi - 1]
	var f := 0.0 if span <= 0.0 else (s - cum[hi - 1]) / span
	return pts[hi - 1].lerp(pts[hi], f)


## Radius of a self-loop's ring: WORK circles Covington at work_ring_radius_px; a REDIRECT
## circles its fort outside the fort's rings (fort_radius(tier) + redirect_ring_pad_px).
static func ring_radius(row: Dictionary, tier: int) -> float:
	if str(row["from"]) == COVINGTON:
		return _num("work_ring_radius_px")
	return MapLogic.fort_radius(tier) + _num("redirect_ring_pad_px")


# --- the style table -----------------------------------------------------------------

## The id of the lane a dead row's gutter rides: that fort's fort -> vei FLOOD (the undead
## drain, same direction of travel). "" for any other kind.
static func host_id(row: Dictionary) -> String:
	if str(row["kind"]) != "dead":
		return ""
	return "flood:%s:%s" % [str(row["from"]), VEI]


## How a view_lanes row looks:
##   hue_key   Palette key whose hue feeds Pulse.channels
##   core      the core stroke's colour (LineGlow.NO_CORE = the line's own)
##   glow      halo strength for LineGlow.layers (0 for matte)
##   duty      dash / period (< 0: Pulse's own dash)
##   period_mult  scales the dash period AND speed, so the mark rate (Pulse's >= 0.8 Hz) holds
##   width_mult   commit_width_mult on committed flows (from Covington, not a loop), times
##                flood_hot_mult on the direct cov -> vei FLOOD
##   alpha_mult   flood_hot_mult on the direct FLOOD, else 1
##   matte, loop, commit, direct, host_id
static func style_for(row: Dictionary) -> Dictionary:
	var kind := str(row["kind"])
	var k: Dictionary = _sub("lane_kinds").get(kind, {})
	var from := str(row["from"])
	var loop := from == str(row["to"])
	var direct := MapLogic.is_direct_flood(row)
	var commit := from == COVINGTON and not loop
	var matte := bool(k.get("matte", false))
	var width_mult := _num("commit_width_mult") if commit else 1.0
	var alpha_mult := 1.0
	var glow := 0.0 if matte else float(k.get("glow", 1.0))
	if direct:
		width_mult *= _num("flood_hot_mult")
		alpha_mult = _num("flood_hot_mult")
		glow = _num("flood_direct_glow")
	var core_key := str(k.get("core", ""))
	var core := LineGlow.NO_CORE
	if core_key != "" and not matte:
		core = Palette.c(core_key).lightened(float(k.get("core_lighten", 0.0)))
	return {
		"kind": kind, "hue_key": str(k.get("hue", "undead")), "core_key": core_key, "core": core,
		"glow": glow, "duty": float(k.get("duty", -1.0)), "period_mult": float(k.get("period_mult", 1.0)),
		"width_mult": width_mult, "alpha_mult": alpha_mult, "matte": matte, "loop": loop,
		"commit": commit, "direct": direct, "host_id": host_id(row),
	}


## The rows the routes draw: every row of a kind in lane_kinds, plus, for a dead row whose
## host FLOOD row is missing, that host at rate 0 (so the phantom bank has a line to follow).
static func plan_rows(rows: Array) -> Array:
	var kinds := _sub("lane_kinds")
	var out: Array = []
	var ids := {}
	for r in rows:
		if kinds.has(str(r["kind"])):
			out.append(r)
			ids[str(r["id"])] = true
	for r in rows:
		var hid := host_id(r)
		if hid != "" and kinds.has("flood") and not ids.has(hid):
			ids[hid] = true
			out.append({"id": hid, "from": str(r["from"]), "to": VEI, "kind": "flood",
				"rate": 0.0, "bias": 1.0, "why": ""})
	return out


# --- what a lane draws ----------------------------------------------------------------

## "lit" when the lane is on; "phantom" when it is off but hosts a dead gutter that is on (the
## gutter is anchored to the host's geometry, never its visibility); "off" otherwise.
static func lane_mode(u: float, hosts_live_dead: bool) -> String:
	if u >= 0.0:
		return "lit"
	return "phantom" if hosts_live_dead else "off"


## The phantom bank shows exactly when the dead flow is on and its host is off.
static func needs_phantom(u_dead: float, u_host: float) -> bool:
	return u_dead >= 0.0 and u_host < 0.0


## A dead flow that is off has no gutter at all.
static func gutter_on(u_dead: float) -> bool:
	return u_dead >= 0.0


static func _layer(width: float, color: Color, offset := 0.0, dashed := true, hairline := false) -> Dictionary:
	return {"width": width, "color": color, "offset": offset, "dashed": dashed, "hairline": hairline}


## A lit lane's alpha: Pulse's alpha floored at lane_alpha_floor, times alpha_mult, capped at 1.
static func lane_alpha(ch: Dictionary, style: Dictionary) -> float:
	return minf(maxf(float(ch["alpha"]), _num("lane_alpha_floor")) * float(style["alpha_mult"]), 1.0)


## A lit lane's drawn core width: Pulse's width times the style's width_mult.
static func lane_width(ch: Dictionary, style: Dictionary) -> float:
	return float(ch["width"]) * float(style["width_mult"])


## A lit lane's strokes, outermost first: LineGlow.layers() of the hue colour at the lane's
## alpha, so the hue carries the halos and the core is the pale core at that alpha. Dashed. The
## core is a hairline (never under a screen pixel, never faded by coverage). Halos wider than
## halo_max_px are pulled in toward the core (capped_halo); the core keeps its width.
static func lit_layers(ch: Dictionary, style: Dictionary) -> Array:
	var col := Color(ch["color"], lane_alpha(ch, style))
	var stack := LineGlow.layers(col, lane_width(ch, style), float(style["glow"]), style["core"])
	var n := stack.size()
	var core_w: float = stack[n - 1][0]
	var outer: float = stack[0][0]
	var out: Array = []
	for i in n:
		var w: float = stack[i][0]
		if i < n - 1:
			w = capped_halo(w, core_w, outer)
		out.append(_layer(w, stack[i][1], 0.0, true, i == n - 1))
	return out


## A halo `w` wide in a stack whose core is `core_w` and outermost halo `outer`: unchanged while
## `outer` <= halo_max_px; past it, every halo is pulled toward the core by the same share, so the
## outermost lands on halo_max_px (or on the core, if the core alone is wider) and the order holds.
static func capped_halo(w: float, core_w: float, outer: float) -> float:
	var hmax := _num("halo_max_px")
	if hmax <= 0.0 or outer <= hmax or outer <= core_w:
		return w
	return core_w + (w - core_w) * maxf(hmax - core_w, 0.0) / (outer - core_w)


## How the shader draws a stroke `width` world px wide at `alpha` when one screen pixel spans
## `world_per_px` world px: {width_px, alpha}. Never thinner than 1 px; below a pixel a hairline
## (a lit lane's core) keeps its alpha, any other stroke's alpha scales with its coverage.
static func drawn_stroke(width: float, alpha: float, world_per_px: float, hairline: bool) -> Dictionary:
	var wpx := width / maxf(world_per_px, 1e-6)
	if wpx >= 1.0:
		return {"width_px": wpx, "alpha": alpha}
	return {"width_px": 1.0, "alpha": alpha if hairline else alpha * wpx}


## The colour the shader draws a lit lane's core in (the innermost stroke).
static func core_color(ch: Dictionary, style: Dictionary) -> Color:
	var layers := lit_layers(ch, style)
	return layers[layers.size() - 1]["color"]


## Lateral distance from a gutter's centre to its host's centre (gutter_curve's shift), times
## `min_cos` (lateral_cos_min of the curve) so it holds along the whole lane.
static func host_edge(host_half: float, gw: float, min_cos := 1.0) -> float:
	return (host_half + gw * 0.5 + _num("gutter_offset_px")) * min_cos


## The shadow gutter (06 c5), from the dead flow's channels (their colour is ignored), for a host
## whose core is 2 x host_half wide: spill, a wide black wash, undashed, that eats the host's
## halos but stops at the host core's outer edge; the cut, pure black, dashed; the lip on the near
## edge (toward the host, +UV.y), dead lightened, alpha lip_alpha_base + lip_alpha_per_a x a,
## dashed; the far rim, dead darkened, dimmer, dashed. Never glows. Width follows u_dead.
static func gutter_layers(ch: Dictionary, host_half: float, min_cos := 1.0, lit := false) -> Array:
	var g := _sub("gutter")
	var a := float(ch["alpha"])
	var gw := MapLogic.gutter_width(float(ch["u"]))
	var dead := Palette.c("dead_lit" if lit else "dead")
	var half := (gw + float(g["spill_px"])) * 0.5
	var inner := minf(half, host_edge(host_half, gw, min_cos) - host_half)
	return [
		_layer(inner + half, Palette.c("void", float(g["spill_alpha"])), (inner - half) * 0.5, false),
		_layer(gw, Palette.c("void")),
		_layer(float(g["lip_width_px"]), Color(dead.lightened(float(g["lip_lighten"])),
			float(g["lip_alpha_base"]) + float(g["lip_alpha_per_a"]) * a), gw * 0.5),
		_layer(float(g["rim_width_px"]), Color(dead.darkened(float(g["rim_darken"])),
			float(g["rim_alpha_base"]) + float(g["rim_alpha_per_a"]) * a), -gw * 0.5),
	]


## Where the shader stops the spill (lateral, from the gutter's centre toward the host) at a
## zoom where one screen pixel spans `world_per_px`: its antialiased edge ends where the host
## core's drawn band (drawn_stroke, a hairline) and its antialiased edge begin.
static func spill_clip(edge: float, host_half: float, world_per_px: float) -> float:
	return edge - maxf(host_half, 0.5 * world_per_px) - world_per_px


## The phantom bank: one undashed phantom_width_px line along the host, host-coloured, at
## phantom_alpha.
static func phantom_layers(host_style: Dictionary) -> Array:
	return [_layer(_num("phantom_width_px"), Palette.c(str(host_style["hue_key"]), _num("phantom_alpha")), 0.0, false)]


## A layer table packed for the shader's vec4 uniforms, padded with empty layers.
static func pack(layers: Array) -> Dictionary:
	var w := Vector4.ZERO
	var o := Vector4.ZERO
	var d := Vector4.ZERO
	var h := Vector4.ZERO
	var cols: Array[Color] = []
	for i in MAX_LAYERS:
		if i < layers.size():
			var l: Dictionary = layers[i]
			w[i] = float(l["width"])
			o[i] = float(l["offset"])
			d[i] = 1.0 if l["dashed"] else 0.0
			h[i] = 1.0 if l.get("hairline", false) else 0.0
			cols.append(l["color"])
		else:
			cols.append(Palette.c("void", 0.0))
	return {"widths": w, "offsets": o, "dashed": d, "hairline": h, "colors": cols}


# --- chevrons -------------------------------------------------------------------------

## Static chevrons show direction (06 chevrons()): on under reduced motion, and at mid zoom
## and nearer (VISUAL-LANGUAGE §2d); none at far zoom otherwise.
static func chevrons_on(reduced_motion: bool, tier: String) -> bool:
	return reduced_motion or tier != "far"


static func chevron_stroke(size: float) -> float:
	return maxf(_num("chevron_stroke_min_px"), size * _num("chevron_stroke_ratio"))


## A gutter's chevrons: the lip grey at the dead flow's alpha x chevron_alpha_mult.
static func gutter_chevron_color(ch: Dictionary, lit := false) -> Color:
	var g := _sub("gutter")
	return Color(Palette.c("dead_lit" if lit else "dead").lightened(float(g["lip_lighten"])),
		float(ch["alpha"]) * float(g["chevron_alpha_mult"]))


# --- extents --------------------------------------------------------------------------

## Half the ribbon a lit lane of this style needs: its widest (capped) halo at u = 1, or a
## chevron's half span, plus ribbon_margin_px for the antialiased edge.
static func lit_half_extent(style: Dictionary) -> float:
	var w := MapLogic.lane_half_width(1.0) * 2.0 * float(style["width_mult"])
	var outer: float = LineGlow.layers(Palette.c("void"), w, maxf(float(style["glow"]), 1.0))[0][0]
	outer = capped_halo(outer, w, outer)
	var size := _num("chevron_size_px")
	return maxf(outer * 0.5, size * 0.8 + chevron_stroke(size)) + _num("ribbon_margin_px")


## Half the ribbon the gutter needs: the widest spill (u_dead = 1) or a chevron, plus margin.
static func gutter_half_extent() -> float:
	var spill := MapLogic.gutter_width(1.0) + float(_sub("gutter")["spill_px"])
	var size := _num("gutter_chevron_size_px")
	return maxf(spill * 0.5, size * 0.8 + chevron_stroke(size)) + _num("ribbon_margin_px")


# --- motion ---------------------------------------------------------------------------

## Dash motion for a lane: {period, dash, speed}. period and speed scale together by the
## style's period_mult; dash = period x duty (duty < 0: Pulse's own dash share). On a ring of
## length `ring_len` the period is rounded so a whole number of dashes fits (no seam), and
## speed scales with it. Walk with Pulse.dash_offset(speed, period) of exactly these values.
static func motion(ch: Dictionary, style: Dictionary, ring_len := 0.0) -> Dictionary:
	var k := float(style["period_mult"])
	var period := float(ch["period"]) * k
	var speed := float(ch["speed"]) * k
	var duty := float(style["duty"])
	if duty < 0.0:
		duty = float(ch["dash"]) / maxf(float(ch["period"]), 0.001)
	if ring_len > 0.0:
		var q := ring_period(ring_len, period)
		speed *= q / period
		period = q
	return {"period": period, "dash": period * duty, "speed": speed}


## The dash offset shown at `now_ms` for a ribbon whose motion was last changed at `anchor_ms`
## (its offset then: `anchor_off`): the anchor walked at `speed` px/s, wrapped to `period`.
## Reduced motion: 0 (dashes hold still). The clock is Pulse's (Pulse.now_ms()), passed in.
static func phase_offset(anchor_off: float, anchor_ms: float, now_ms: float, speed: float, period: float, reduced: bool) -> float:
	if reduced or period <= 0.0:
		return 0.0
	return fposmod(anchor_off + (now_ms - anchor_ms) * 0.001 * speed, period)


## The new `anchor_off` for a ribbon whose motion changes at `now_ms` from (speed, old_period)
## to a new period: the offset it is showing right now (never the reduced-motion zero, so F8
## does not lose the phase), rescaled by new / old period so the dash fraction holds. Re-anchor
## with anchor_ms = now_ms and set the new speed and period.
static func rebase_offset(anchor_off: float, anchor_ms: float, now_ms: float, speed: float, old_period: float, new_period: float) -> float:
	if new_period <= 0.0 or old_period <= 0.0:
		return 0.0
	var shown := phase_offset(anchor_off, anchor_ms, now_ms, speed, old_period, false)
	return fposmod(shown * new_period / old_period, new_period)


## Where the train's first cart (the one nearest the lane's start) stands for a base offset.
static func cart_lead(base: float, spacing: float, length: float) -> float:
	if spacing <= 0.0:
		return 0.0
	return fposmod(base + 0.5 * minf(spacing, length), spacing)


## The new cart-train anchor when its spacing changes at `now_ms` (or its speed: pass the old
## speed): chosen so the first cart stays exactly where it stands, instead of the whole train
## teleporting. Re-anchor with anchor_ms = now_ms.
static func cart_anchor(anchor_off: float, anchor_ms: float, now_ms: float, old_speed: float, old_spacing: float, new_spacing: float, length: float) -> float:
	if new_spacing <= 0.0 or old_spacing <= 0.0:
		return 0.0
	var base := phase_offset(anchor_off, anchor_ms, now_ms, old_speed, old_spacing, false)
	var lead := cart_lead(base, old_spacing, length)
	return fposmod(lead - 0.5 * minf(new_spacing, length), new_spacing)


## The period nearest `period` that tiles `circumference` a whole number of times (at least once).
static func ring_period(circumference: float, period: float) -> float:
	if period <= 0.0 or circumference <= 0.0:
		return maxf(period, 1.0)
	return circumference / maxf(roundf(circumference / period), 1.0)


# --- carts on haul lanes --------------------------------------------------------------

## Carts on a haul lane carrying `rate` corpses/s at `speed` px/s along a lane `length` px
## long. Each cart carries carts.load corpses, so they are spaced speed x load / rate apart
## (more rate, closer carts), but never closer than length / count_max. When that cap binds,
## each cart carries more (the flow is conserved). pips = load units (carts.pip_units corpses
## each) per cart, 1..pips_max. count = the most carts on the lane at once. Off: count 0.
static func carts(rate: float, speed: float, length: float) -> Dictionary:
	var c := _sub("carts")
	if rate <= 0.0 or speed <= 0.0 or length <= 0.0:
		return {"spacing": 0.0, "count": 0, "pips": 0}
	var spacing := maxf(speed * float(c["load"]) / rate, length / maxf(float(c["count_max"]), 1.0))
	var load := rate * spacing / speed
	var pips := clampi(roundi(load / float(c["pip_units"])), 1, int(c["pips_max"]))
	return {"spacing": spacing, "count": int(ceil(length / spacing)), "pips": pips}


## Arc positions of the carts on a lane: a train `spacing` apart walked by `base` (from
## Pulse.dash_offset(speed, spacing), 0 under reduced motion), starting half a gap in so a
## still frame shows a cart. Only positions on the lane (0 .. length) are returned.
static func cart_positions(base: float, spacing: float, length: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if spacing <= 0.0 or length <= 0.0:
		return out
	var s := fposmod(base + 0.5 * minf(spacing, length), spacing)
	while s < length:
		out.append(s)
		s += spacing
	return out
