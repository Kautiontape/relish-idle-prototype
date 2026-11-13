shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;
// One lane ribbon of the realm map (scripts/map/map_routes.gd). The mesh is a triangle strip
// along the lane, built once: UV.x = arc length in world px from the lane's start, UV.y = -1..1
// across (half_extent world px each side).
// Up to four strokes, each {width, lateral offset, dashed?, colour}, composited outermost first,
// which is exactly what stacked strokes give: a lit lane carries LineGlow.layers(), the dead
// gutter its spill / cut / lip / rim, the phantom bank one faint line (scripts/map/lane_style_logic.gd).
// Dashes walk along UV.x by `offset`, which GDScript sets from Pulse.dash_offset (never TIME),
// so reduced motion freezes them for free. A stroke thinner than one screen pixel is drawn one
// pixel wide with its alpha scaled by its coverage. Chevrons: 3 static arrowheads at 1/4, 1/2
// and 3/4 of the lane (06 chevrons()), when chev_on.

uniform float half_extent = 1.0;
uniform float lane_len = 0.0;
uniform vec4 widths = vec4(0.0);
uniform vec4 offsets = vec4(0.0);
uniform vec4 dashed = vec4(0.0);
uniform vec4 col0 : source_color = vec4(0.0);
uniform vec4 col1 : source_color = vec4(0.0);
uniform vec4 col2 : source_color = vec4(0.0);
uniform vec4 col3 : source_color = vec4(0.0);
uniform float period = 96.0;
uniform float dash = 48.0;
uniform float offset = 0.0;
uniform float chev_on = 0.0;
uniform float chev_size = 5.0;
uniform float chev_width = 1.7;
uniform vec4 chev_col : source_color = vec4(0.0);

vec4 over(vec4 acc, vec4 col, float cover) {
	float a = col.a * cover;
	return vec4(col.rgb * a, a) + acc * (1.0 - a);
}

// coverage of a stroke `w` wide centred `o` across, at lateral position d (px = world per pixel)
float stroke(float d, float px, float w, float o) {
	float ww = max(w, px);
	return clamp((ww * 0.5 - abs(d - o)) / px + 0.5, 0.0, 1.0) * min(w / px, 1.0);
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	float s = UV.x;
	float d = UV.y * half_extent;
	float px = max(length(vec2(dFdx(d), dFdy(d))), 1e-4);
	float ps = max(length(vec2(dFdx(s), dFdy(s))), 1e-4);
	float ph = mod(s - offset, period);
	float sd = ph < dash ? min(ph, dash - ph) : -min(ph - dash, period - ph);
	float on = clamp(sd / ps + 0.5, 0.0, 1.0);
	vec4 acc = vec4(0.0);
	acc = over(acc, col0, stroke(d, px, widths.x, offsets.x) * mix(1.0, on, dashed.x));
	acc = over(acc, col1, stroke(d, px, widths.y, offsets.y) * mix(1.0, on, dashed.y));
	acc = over(acc, col2, stroke(d, px, widths.z, offsets.z) * mix(1.0, on, dashed.z));
	acc = over(acc, col3, stroke(d, px, widths.w, offsets.w) * mix(1.0, on, dashed.w));
	if (chev_on > 0.5) {
		vec2 tip = vec2(0.55 * chev_size, 0.0);
		vec2 wing = vec2(-chev_size, 0.8 * chev_size);
		float cd = 1e6;
		for (int i = 1; i <= 3; i++) {
			vec2 p = vec2(s - lane_len * float(i) * 0.25, d);
			cd = min(cd, min(seg_dist(p, wing, tip), seg_dist(p, tip, vec2(wing.x, -wing.y))));
		}
		acc = over(acc, chev_col, stroke(cd, px, chev_width, 0.0));
	}
	COLOR = acc;
}
