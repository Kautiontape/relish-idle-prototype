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
// Chevrons: 3 static arrowheads at 1/4, 1/2
// and 3/4 of the lane (06 chevrons()), when chev_on. With chev_snap (reduced motion: the dashes
// are frozen) each moves to the nearest gap centre, so it never hides inside a dash's pale core.

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

void fragment() {
	float s = UV.x;
	if (s < trim_start || s > lane_len - trim_end) {
		discard;
	}
	float d = UV.y * half_extent;
	float px = max(length(vec2(dFdx(d), dFdy(d))), 1e-4);
	float ps = max(length(vec2(dFdx(s), dFdy(s))), 1e-4);
	float ph = mod(s - offset, period);
	float sd = ph < dash ? min(ph, dash - ph) : -min(ph - dash, period - ph);
	float butt = clamp(sd / ps + 0.5, 0.0, 1.0);
	float ds = ph < dash ? 0.0 : min(ph - dash, period - ph);
	float c0 = layer(d, px, widths.x, offsets.x, dashed.x, hairline.x, ds, butt);
	float lim = clip_edge - max(clip_half, 0.5 * px) - px;
	c0 *= clamp((lim - d) / px + 0.5, 0.0, 1.0);
	vec4 acc = vec4(0.0);
	acc = over(acc, col0, c0);
	acc = over(acc, col1, layer(d, px, widths.y, offsets.y, dashed.y, hairline.y, ds, butt));
	acc = over(acc, col2, layer(d, px, widths.z, offsets.z, dashed.z, hairline.z, ds, butt));
	acc = over(acc, col3, layer(d, px, widths.w, offsets.w, dashed.w, hairline.w, ds, butt));
	if (chev_on > 0.5) {
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
		acc = over(acc, chev_col, stroke(cd, px, chev_width, 0.0));
	}
	COLOR = acc;
}
