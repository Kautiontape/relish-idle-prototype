shader_type canvas_item;
// Fortress wall: dark obsidian core rimmed with slow-drifting rainbow neon,
// subtle shimmer/pulse, soft glow spilling onto the floor. Techno-dream.
// Geometry: a rect drawn from (0, -half_h) to (seg_len, +half_h), where
// half_h = core_half + glow_px. Local +x runs along the wall's length.

uniform float seg_len = 200.0;
uniform float core_half = 15.0;    // half the solid wall thickness
uniform float glow_px = 26.0;      // glow apron beyond the core
uniform float world_off = 0.0;     // world offset along the wall axis → hue continuity
uniform float wavelength = 1100.0; // px per full hue cycle along the wall
uniform float drift_speed = 0.05;  // hue cycles per second

varying vec2 v_pos;

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	float along = v_pos.x + world_off;
	float d = abs(v_pos.y);
	float hue = fract(along / wavelength - TIME * drift_speed);
	vec3 neon = hsv2rgb(vec3(hue, 0.8, 1.0));
	float pulse = 0.5 + 0.5 * sin(TIME * 1.6 + along * 0.011);
	float shimmer = smoothstep(0.72, 1.0, 0.5 + 0.5 * sin(along * 0.045 - TIME * 2.3));
	vec3 col;
	float a;
	if (d <= core_half) {
		// solid wall: a clearly-filled neon slab, brightest at the rim
		float inner = d / core_half; // 0 center → 1 rim
		vec3 base = neon * (0.34 + 0.12 * pulse) + vec3(0.06, 0.05, 0.10);
		float rim = smoothstep(0.45, 0.95, inner);
		col = mix(base, neon * (0.92 + 0.08 * pulse), rim);
		col += neon * shimmer * 0.28 * (1.0 - inner * 0.4);
		a = 1.0;
	} else {
		// soft glow apron spilling onto the floor
		float g = clamp((d - core_half) / glow_px, 0.0, 1.0);
		float fall = (1.0 - g) * (1.0 - g);
		col = neon;
		a = fall * (0.26 + 0.12 * pulse + shimmer * 0.10);
		// fade the glow near the segment ends so door gaps read as crisp jambs
		float endf = smoothstep(0.0, glow_px, v_pos.x) * smoothstep(0.0, glow_px, seg_len - v_pos.x);
		a *= endf;
	}
	COLOR = vec4(col, a);
}
