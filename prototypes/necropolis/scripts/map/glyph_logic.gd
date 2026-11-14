class_name GlyphLogic
extends RefCounted
## Pure logic for the map's unit glyphs at near zoom (VISUAL-LANGUAGE §2d; no autoloads, so
## headless tests compile it). The shared cross-scene glyph set:
##   undead worker  a straight stroke along its heading with a solid core dot at its head;
##   living         a small arc with a hollow ring head;
##   big undead     a diamond outline with a core dot, nested outlines by filled remnant slots;
##   cart           map_carts.gd's U-box (haul lanes keep it).
## Here: the glyph a lane kind carries and where its glyphs stand (one per dash period at the dash
## centres, so they ride the dashes' anchored phase); the near crossfade weight; the siege arc
## outside a fort's rings and Relish's party; the held forts' garrison slots inside the pip ring.
## Sizes are world px. Tuning: configs/map_view.json "glyphs" and glyph_fade.

const NONE := "none"
const UNDEAD := "undead"
const LIVING := "living"
const CART := "cart"
## Big undead carry no filled remnant slots in the views yet (api-request #6, E3): one each.
# TODO(api-request #6): view_big_undead entries' filled_slots
const FILLED_SLOTS_STANDIN := 1
const STROKES_MAX := 3


static func gcfg() -> Dictionary:
	return MapLogic.cfg().get("glyphs", {})


static func _g(key: String) -> float:
	return float(gcfg().get(key, 0.0))


# --- lanes ------------------------------------------------------------------------

## The glyph a lane of `lane_kind` carries at near zoom: war, flood and work carry undead
## workers, living lanes the living, haul keeps its carts; redirect and the dead gutter none
## (they keep their dashes: dead matter has no unit glyph).
static func kind_for(lane_kind: String) -> String:
	match lane_kind:
		"war", "flood", "work":
			return UNDEAD
		"living":
			return LIVING
		"haul":
			return CART
	return NONE


## The lane shader's glyph_kind: 1 undead, 2 living, 0 anything it does not draw (carts, none).
static func shader_kind(glyph: String) -> float:
	if glyph == UNDEAD:
		return 1.0
	if glyph == LIVING:
		return 2.0
	return 0.0


## The glyph's shape for the lane shader, world px: {len (the undead stroke or the living arc's
## chord), sag (the living arc's bulge, + toward +UV.y), head_r (the dot or the ring's radius),
## head_w (the ring's stroke), width (the stroke's core)}. Zeros for a kind it does not draw.
static func shape(glyph: String) -> Dictionary:
	var k: Dictionary = gcfg().get(glyph, {})
	var ring := glyph == LIVING
	return {"len": float(k.get("len_px", 0.0)), "sag": float(k.get("sag_px", 0.0)) if ring else 0.0,
		"head_r": float(k.get("ring_r_px" if ring else "head_r_px", 0.0)),
		"head_w": float(k.get("ring_w_px", 0.0)) if ring else 0.0, "width": float(k.get("width_px", 0.0))}


## How far a glyph reaches across its lane from the centre line, with a halo `halo_half` wide on
## each side of its stroke: the arc's bulge plus the halo, or the head's outer edge.
static func lateral_reach(glyph: String, halo_half: float) -> float:
	var s := shape(glyph)
	return maxf(absf(float(s["sag"])) + halo_half, float(s["head_r"]) + float(s["head_w"]) * 0.5)


## The crossfade into glyphs by zoom (not time, so reduced motion keeps it): 0 below
## zoom_near_above - glyph_fade, 1 from zoom_near_above, linear in between.
static func near_weight(zoom: float) -> float:
	var near := float(MapLogic.cfg().get("zoom_near_above", 0.0))
	var fade := float(MapLogic.cfg().get("glyph_fade", 0.0))
	if fade <= 0.0:
		return 1.0 if zoom >= near else 0.0
	return clampf(1.0 + (zoom - near) / fade, 0.0, 1.0)


## Arc positions of a lane's glyphs between `lo` and `hi` (the drawn range inside the trims): one
## at the centre of every dash of the pattern the shader draws (a dash spans offset + k period ..
## + dash), so they move with the dashes' offset and tighten with rate exactly as the dashes do.
static func centres(lo: float, hi: float, offset: float, period: float, dash: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if period <= 0.0 or hi < lo:
		return out
	var first := offset + dash * 0.5
	var s := first + ceilf((lo - first) / period) * period
	while s <= hi:
		out.append(s)
		s += period
	return out


# --- big undead ---------------------------------------------------------------------

## Nested outlines a big undead draws: its filled remnant slots, 1..3. `entry` is a
## view_big_undead entry; until it carries filled_slots, the stand-in (one outline).
# TODO(api-request #6): filled_slots lands in E3
static func stroke_count(entry: Dictionary) -> int:
	return clampi(int(entry.get("filled_slots", FILLED_SLOTS_STANDIN)), 1, STROKES_MAX)


## The nested outlines' half sizes (centre to tip), outermost first, each big_nest_step smaller.
static func nest_halves(half: float, strokes: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in clampi(strokes, 1, STROKES_MAX):
		out.append(half * (1.0 - _g("big_nest_step") * i))
	return out


## How far a diamond `half` wide reaches from its centre, its capped halo included.
static func big_extent(half: float) -> float:
	return half + _g("big_halo_max_px") * 0.5


## The siege arc's radius round a fort of `tier`: past the REDIRECT lane ring (fort radius +
## redirect_ring_pad_px) and its widest capped halo, then siege_gap_px, then a diamond.
static func siege_radius(tier: int) -> float:
	return MapLogic.fort_radius(tier) + float(MapLogic.cfg().get("redirect_ring_pad_px", 0.0)) \
		+ float(MapLogic.cfg().get("halo_max_px", 0.0)) * 0.5 + _g("siege_gap_px") + big_extent(_g("big_half_px"))


## Where `n` sieging big undead stand round the fort at `centre`: on siege_radius, centred on
## siege_arc_deg (upper right: clear of the idle chips on the left, the tithe text on the right,
## the name below and Relish's standing token above), siege_gap_px apart.
static func siege_layout(centre: Vector2, tier: int, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r := siege_radius(tier)
	var step := (big_extent(_g("big_half_px")) * 2.0 + _g("siege_gap_px")) / maxf(r, 1.0)
	var a0 := deg_to_rad(_g("siege_arc_deg")) - step * (n - 1) * 0.5
	for i in maxi(n, 0):
		out.append(centre + Vector2.from_angle(a0 + step * i) * r)
	return out


## The siege's alpha on the forts' beat (`w`: Pulse.wave at their hop); MapNodes sets it as the
## siege layer's modulate.
static func siege_alpha(w: float) -> float:
	return _g("siege_alpha_base") + _g("siege_alpha_wave") * w


## How far from Relish's centre her token's marks reach at `zoom`: the wide beat ring and half
## its capped halo.
static func relish_clear(zoom: float) -> float:
	var n := NodeLogic.ncfg()
	return float(NodeLogic.relish_radii(zoom)["wide"]) + float(n.get("relish_wide_halo_max_px", 0.0)) * 0.5 / maxf(zoom, 0.001)


## Where Relish's party (in party order) stands round her token at `rp`: travelling, a file
## behind her along her `heading`; standing, a row beside her (party_row_dir: -1 left), since
## below her are the node's own rings. Small diamonds, party_gap_px apart, clear of her token.
static func party_layout(rp: Vector2, heading: float, travelling: bool, n: int, zoom: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ext := big_extent(_g("party_half_px"))
	var dir := -Vector2.from_angle(heading) if travelling else Vector2(1.0 if _g("party_row_dir") > 0.0 else -1.0, 0.0)
	var d0 := relish_clear(zoom) + _g("party_gap_px") + ext
	for k in maxi(n, 0):
		out.append(rp + dir * (d0 + k * (ext * 2.0 + _g("party_gap_px"))))
	return out


# --- garrison --------------------------------------------------------------------------

## The ring the garrison's worker glyphs stand on inside a held fort of `tier` at `zoom`: clear of
## the state glyph (constant on screen, so its world size shrinks as you zoom in) and inside the
## pip ring. {radius, slots}: slots = how many tangential workers fit (0 when none do).
static func garrison_ring(tier: int, zoom: float) -> Dictionary:
	var n := NodeLogic.ncfg()
	var z := maxf(zoom, 0.001)
	var s := shape(UNDEAD)
	var half_len := float(s["len"]) * 0.5
	var head := float(s["head_r"])
	var halo := maxf(_g("garrison_halo_max_px"), float(s["width"])) * 0.5
	var gap := _g("garrison_gap_px")
	var h := NodeLogic.state_glyph_half(zoom)
	# the held state diamond's tip, or its will-fall slash, with the state halo round either
	var state_r := maxf(h, h * sqrt(2.0) * float(n.get("state_slash_ext", 0.0))) + float(n.get("state_halo_max_px", 0.0)) * 0.5 / z
	var pip_r := maxf(float(n.get("pip_radius_px", 0.0)), float(n.get("pip_min_screen_px", 0.0)) / z * 0.5)
	var edge := MapLogic.fort_radius(tier) - float(n.get("pip_inset_px", 0.0)) - pip_r
	var r_min := state_r + gap + halo
	var reach := edge - gap - maxf(head, halo)
	if reach <= half_len:
		return {"radius": 0.0, "slots": 0}
	var r := sqrt(reach * reach - half_len * half_len)
	if r < r_min:
		return {"radius": 0.0, "slots": 0}
	var need := head + halo + gap
	var slots := 1
	var most := int(_g("garrison_slots_max"))
	while slots < most and _head_to_tail(r, half_len, TAU / (slots + 1)) >= need:
		slots += 1
	return {"radius": r, "slots": slots}


## Distance from one tangential worker's head to the next one's tail, on a ring of radius `r`,
## `step` radians apart (clockwise on screen).
static func _head_to_tail(r: float, half_len: float, step: float) -> float:
	var head := Vector2(r, 0.0) + Vector2(0.0, 1.0) * half_len
	var t1 := Vector2.from_angle(step + PI * 0.5)
	var tail := Vector2.from_angle(step) * r - t1 * half_len
	return head.distance_to(tail)


## The garrison's slots round the fort at `centre`: [{pos, dir}] from 12 o'clock clockwise, each a
## worker's centre and its heading (along the ring, clockwise).
static func garrison_slots(centre: Vector2, tier: int, zoom: float) -> Array:
	var ring := garrison_ring(tier, zoom)
	var out: Array = []
	var n := int(ring["slots"])
	for i in n:
		var a := -PI * 0.5 + TAU * i / n
		out.append({"pos": centre + Vector2.from_angle(a) * float(ring["radius"]), "dir": Vector2.from_angle(a + PI * 0.5)})
	return out


## How `units` (IdleLogic.garrison_units: the chip's number) fill `slots` slots: {shown, plus}.
## All of them when they fit under garrison_glyph_max; else up to the max (one slot kept back
## when the ring is full) and the rest as "+plus" in the next slot, so shown + plus == units
## whenever there is a slot at all.
static func garrison_fill(units: int, slots: int) -> Dictionary:
	var u := maxi(units, 0)
	var most := int(_g("garrison_glyph_max"))
	if slots <= 0:
		return {"shown": 0, "plus": 0}
	if u <= mini(most, slots):
		return {"shown": u, "plus": 0}
	var shown := mini(most, slots - 1)
	return {"shown": shown, "plus": u - shown}
