shader_type canvas_item;
// Fortress wall: a dark slab rimmed with neon that cycles only between two
// palette colours (violet and the fortress's controller colour). The shimmer
// runs on the Pulse beat, not TIME: the beat crosses the walls as a wave from
// Relish (VISUAL-LANGUAGE law 5). All colours and tempo numbers are uniforms
// set from Palette / Pulse / configs/raid.json by wall_segment.gd.
// Geometry: a rect drawn from (0, -half_h) to (seg_len, +half_h), where
// half_h = core_half + glow_px. Local +x runs along the wall's length.

uniform float seg_len = 200.0;
uniform float core_half = 15.0;    // half the solid wall thickness
uniform float glow_px = 26.0;      // glow apron beyond the core
uniform float world_off = 0.0;     // world offset along the wall axis, for colour continuity
uniform float wavelength = 1100.0; // px per full colour cycle along the wall
uniform vec4 color_a : source_color = vec4(1.0);  // Palette relish
uniform vec4 color_b : source_color = vec4(1.0);  // Palette controller colour
uniform float heat = 0.0;          // 0 = normal; the boss room runs hotter
uniform float drift = 0.0;         // colour drift position in cycles (frozen by reduced motion)
uniform float beat = 0.0;          // Pulse.phase() at the source
uniform vec2 relish_pos = vec2(0.0);
uniform float arena_diag = 1000.0;
uniform float wave_spread = 0.5;   // Pulse.wave_spread
uniform float wave_decay = 3.2;    // Pulse.wave_decay
uniform float steady = -1.0;       // >= 0: reduced motion, a steady wave level

varying vec2 v_pos;
varying vec2 v_world;

void vertex() {
	v_pos = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float along = v_pos.x + world_off;
	float d = abs(v_pos.y);
	float k = 0.5 + 0.5 * sin(6.2831853 * (along / wavelength - drift));
	vec3 neon = mix(color_a.rgb, color_b.rgb, k);

	// the beat, lagged by distance from Relish: a wave crossing the walls
	float lag = clamp(distance(v_world, relish_pos) / arena_diag, 0.0, 1.0) * wave_spread;
	float w = steady >= 0.0 ? steady : exp(-wave_decay * fract(beat - lag + 1.0));
	float shimmer = smoothstep(0.72, 1.0, 0.5 + 0.5 * sin(along * 0.045)) * w;
	float hot = 1.0 + heat;

	vec3 col;
	float a;
	if (d <= core_half) {
		// solid wall: a filled neon slab, brightest at the rim
		float inner = d / core_half; // 0 center to 1 rim
		vec3 base = neon * (0.34 + 0.12 * w) * hot;
		float rim = smoothstep(0.45, 0.95, inner);
		col = mix(base, neon * (0.92 + 0.08 * w) * hot, rim);
		col += neon * shimmer * 0.28 * hot * (1.0 - inner * 0.4);
		a = 1.0;
	} else {
		// soft glow apron spilling onto the floor
		float g = clamp((d - core_half) / glow_px, 0.0, 1.0);
		float fall = (1.0 - g) * (1.0 - g);
		col = neon;
		a = fall * (0.26 + 0.12 * w + shimmer * 0.10) * hot;
		// fade the glow near the segment ends so door gaps read as crisp jambs
		float endf = smoothstep(0.0, glow_px, v_pos.x) * smoothstep(0.0, glow_px, seg_len - v_pos.x);
		a *= endf;
	}
	COLOR = vec4(min(col, vec3(1.0)), min(a, 1.0));
}
