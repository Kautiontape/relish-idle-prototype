shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;
// One lane ribbon of the realm map (scripts/map/map_routes.gd). The mesh is a triangle strip
// along the lane, built once: UV.x = arc length in world px from the lane's start, UV.y = -1..1
// across (half_extent world px each side).
// Up to four strokes, each {width, lateral offset, dashed?, colour}, composited outermost first,
// which is exactly what stacked strokes give: a lit lane carries LineGlow.layers(), the dead
// gutter its spill / cut / lip / rim, the phantom bank one faint line (scripts/map/lane_style_logic.gd).
// Dashes walk along UV.x by `offset`, which GDScript sets from Pulse.dash_offset (never TIME),
// so reduced motion freezes them for free. Lit lanes (round_caps) give every dash round caps, a
// capsule per dash as 06 strokes lit strands with lineCap 'round'; the gutter keeps butt ends.
// A stroke thinner than one screen pixel is drawn one pixel wide: a hairline layer (a lit lane's
// core) keeps its full alpha, any other layer has its alpha scaled by its coverage
// (LaneStyle.drawn_stroke). clip_edge / clip_half (gutters only) keep layer 0, the spill, off
// the host lane's drawn core band and its antialiased edge (LaneStyle.spill_clip).
// The trim (the lane's drawn range, trim_start .. lane_len - trim_end) multiplies the premultiplied
// output by a one-pixel coverage ramp, so the cut is antialiased and nothing is discarded.
// Chevrons: 3 static arrowheads at 1/4, 1/2
// and 3/4 of the lane (06 chevrons()), when chev_on. With chev_snap (reduced motion: the dashes
// are frozen) each moves to the nearest gap centre, so it never hides inside a dash's pale core.
// Near zoom (glyph_kind > 0, glyph_mix > 0: GlyphLogic): every dash becomes a unit glyph centred
// on it, heading +UV.x (the direction of travel), so glyphs ride the same anchored offset as the
// dashes. The glyph's stroke is its own stack (gwidths / gcol0..3: LaneStyle.glyph_layers, the
// lane's LineGlow profile and cap in the lane colour; one hairline when quiet); its head (the
// undead's solid dot, the living's hollow ring) is drawn over it in glyph_core, the lane's core
// colour. The composite crossfades from dashes to glyphs by glyph_mix (zoom, never time), and
// chevrons fade out as glyphs fade in: a glyph's heading shows the direction, frozen or not.

uniform float half_extent = 1.0;
uniform float lane_len = 0.0;
uniform float trim_start = 0.0; // arc-length px not drawn at the start (inside the from node)
uniform float trim_end = 0.0;   // ... and at the end (inside the to node)
uniform vec4 widths = vec4(0.0);
uniform vec4 offsets = vec4(0.0);
uniform vec4 dashed = vec4(0.0);
uniform vec4 hairline = vec4(0.0);
uniform float round_caps = 0.0;
uniform float clip_edge = 1e6;
uniform float clip_half = 0.0;
uniform vec4 col0 : source_color = vec4(0.0);
uniform vec4 col1 : source_color = vec4(0.0);
uniform vec4 col2 : source_color = vec4(0.0);
uniform vec4 col3 : source_color = vec4(0.0);
uniform float period = 96.0;
uniform float dash = 48.0;
uniform float offset = 0.0;
uniform float chev_on = 0.0;
uniform float chev_snap = 0.0;
uniform float chev_size = 5.0;
uniform float chev_width = 1.7;
uniform vec4 chev_col : source_color = vec4(0.0);
uniform float glyph_kind = 0.0;   // 0 none (dashes stay), 1 undead worker, 2 living
uniform float glyph_mix = 0.0;    // 0 dashes .. 1 glyphs: the near crossfade, by zoom
uniform vec4 gwidths = vec4(0.0); // the glyph stroke's layers, outermost first (hairline flags shared)
uniform vec4 gcol0 : source_color = vec4(0.0);
uniform vec4 gcol1 : source_color = vec4(0.0);
uniform vec4 gcol2 : source_color = vec4(0.0);
uniform vec4 gcol3 : source_color = vec4(0.0);
uniform vec4 glyph_core : source_color = vec4(0.0);
uniform float glyph_len = 0.0;    // undead: the stroke; living: the arc's chord
uniform float glyph_sag = 0.0;    // living: the arc's bulge toward +UV.y (negative: -UV.y)
uniform float head_r = 0.0;       // undead: the dot's radius; living: the ring's
uniform float head_w = 0.0;       // living: the ring's stroke

vec4 over(vec4 acc, vec4 col, float cover) {
	float a = col.a * cover;
	return vec4(col.rgb * a, a) + acc * (1.0 - a);
}

// coverage of a stroke `w` wide at distance `dist` from its centre (px = world per pixel). Never
// thinner than a pixel; below a pixel a hairline keeps its alpha, anything else fades with coverage.
float stroke(float dist, float px, float w, float hl) {
	float ww = max(w, px);
	float fade = hl > 0.5 ? 1.0 : min(w / px, 1.0);
	return clamp((ww * 0.5 - dist) / px + 0.5, 0.0, 1.0) * fade;
}

// one layer's coverage: undashed, butt-dashed (`butt` is the dash mask), or round-capped (a
// capsule round the nearest dash: `ds` is the distance along the lane to that dash)
float layer(float d, float px, float w, float o, float dsh, float hl, float ds, float butt) {
	if (round_caps > 0.5) {
		return stroke(length(vec2(ds * dsh, d - o)), px, w, hl);
	}
	return stroke(abs(d - o), px, w, hl) * mix(1.0, butt, dsh);
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// distance to a circular arc from (-h, 0) to (h, 0) whose apex is (0, g): the living glyph's body
float arc_dist(vec2 p, float h, float g) {
	if (abs(g) < 1e-3) {
		return seg_dist(p, vec2(-h, 0.0), vec2(h, 0.0));
	}
	vec2 q = vec2(p.x, g < 0.0 ? -p.y : p.y);
	float a = abs(g);
	float r = (h * h + a * a) / (2.0 * a);
	vec2 v = q - vec2(0.0, a - r);
	float lv = max(length(v), 1e-4);
	if (v.y / lv >= (r - a) / r) {
		return abs(lv - r);
	}
	return min(length(q - vec2(-h, 0.0)), length(q - vec2(h, 0.0)));
}

void fragment() {
	// every derivative first, before any branch (they are undefined in non-uniform control flow)
	float s = UV.x;
	float d = UV.y * half_extent;
	float px = max(length(vec2(dFdx(d), dFdy(d))), 1e-4);
	float ps = max(length(vec2(dFdx(s), dFdy(s))), 1e-4);
	// the trim is a coverage multiply, antialiased one pixel; a zero trim (a ring, a node with no
	// rings) is left alone so a seam at s = 0 or lane_len never fades
	float cov = 1.0;
	if (trim_start > 0.0) {
		cov *= clamp((s - trim_start) / ps + 0.5, 0.0, 1.0);
	}
	if (trim_end > 0.0) {
		cov *= clamp((lane_len - trim_end - s) / ps + 0.5, 0.0, 1.0);
	}
	float ph = mod(s - offset, period);
	float sd = ph < dash ? min(ph, dash - ph) : -min(ph - dash, period - ph);
	float butt = clamp(sd / ps + 0.5, 0.0, 1.0);
	float ds = ph < dash ? 0.0 : min(ph - dash, period - ph);
	float gm = glyph_kind > 0.5 ? glyph_mix : 0.0;
	vec4 acc = vec4(0.0);
	if (gm < 1.0) {
		float c0 = layer(d, px, widths.x, offsets.x, dashed.x, hairline.x, ds, butt);
		float lim = clip_edge - max(clip_half, 0.5 * px) - px;
		c0 *= clamp((lim - d) / px + 0.5, 0.0, 1.0);
		acc = over(acc, col0, c0);
		acc = over(acc, col1, layer(d, px, widths.y, offsets.y, dashed.y, hairline.y, ds, butt));
		acc = over(acc, col2, layer(d, px, widths.z, offsets.z, dashed.z, hairline.z, ds, butt));
		acc = over(acc, col3, layer(d, px, widths.w, offsets.w, dashed.w, hairline.w, ds, butt));
	}
	if (gm > 0.0) {
		// the glyph on the nearest dash centre, in its own frame (x along travel, y across)
		float g0 = offset + dash * 0.5;
		vec2 q = vec2(s - g0 - round((s - g0) / period) * period, d);
		float hl = glyph_len * 0.5;
		float gd = 0.0;
		float hc = 0.0;
		if (glyph_kind < 1.5) {
			gd = seg_dist(q, vec2(-hl, 0.0), vec2(hl, 0.0));
			hc = clamp((head_r - length(q - vec2(hl, 0.0))) / px + 0.5, 0.0, 1.0);
		} else {
			gd = arc_dist(q, hl, glyph_sag);
			hc = stroke(abs(length(q - vec2(hl + head_r, 0.0)) - head_r), px, head_w, 1.0);
		}
		vec4 g = vec4(0.0);
		g = over(g, gcol0, stroke(gd, px, gwidths.x, hairline.x));
		g = over(g, gcol1, stroke(gd, px, gwidths.y, hairline.y));
		g = over(g, gcol2, stroke(gd, px, gwidths.z, hairline.z));
		g = over(g, gcol3, stroke(gd, px, gwidths.w, hairline.w));
		g = over(g, glyph_core, hc);
		acc = mix(acc, g, gm);
	}
	if (chev_on > 0.5 && gm < 1.0) {
		vec2 tip = vec2(0.55 * chev_size, 0.0);
		vec2 wing = vec2(-chev_size, 0.8 * chev_size);
		// the arrowhead spans s0 - size .. s0 + 0.55 size: centre that span in the gap
		float gap_c = offset + dash + (period - dash) * 0.5 + 0.225 * chev_size;
		float cd = 1e6;
		for (int i = 1; i <= 3; i++) {
			float s0 = trim_start + (lane_len - trim_start - trim_end) * float(i) * 0.25;
			if (chev_snap > 0.5) {
				s0 = clamp(gap_c + round((s0 - gap_c) / period) * period, trim_start, lane_len - trim_end);
			}
			vec2 p = vec2(s - s0, d);
			cd = min(cd, min(seg_dist(p, wing, tip), seg_dist(p, tip, vec2(wing.x, -wing.y))));
		}
		acc = over(acc, chev_col, stroke(cd, px, chev_width, 0.0) * (1.0 - gm));
	}
	COLOR = acc * cov;
}
