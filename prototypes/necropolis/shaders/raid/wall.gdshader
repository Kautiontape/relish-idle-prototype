shader_type canvas_item;
// Fortress wall: a thin glowing stroke along the wall's centre line (VISUAL-LANGUAGE law 2:
// everything is a line). The 30 px collision band is not drawn; only the stroke and a narrow
// halo are. The colour cycles between two palette colours (violet and the fortress's
// controller colour) and stays dimmer than the units. The shimmer runs on the Pulse beat,
// not TIME: the beat crosses the walls as a wave from Relish (law 5). All colours and
// numbers are uniforms set from Palette / Pulse / configs/raid.json by wall_segment.gd.
// Geometry: a rect drawn from (0, -half_h) to (seg_len, +half_h), where
// half_h = stroke_half + halo_px. Local +x runs along the wall's length; the segment ends
// are crisp, so door gaps read as clean jambs.

uniform float seg_len = 200.0;
uniform float stroke_half = 1.5;   // half the stroke width
uniform float halo_px = 9.0;       // soft halo beyond the stroke
uniform float intensity = 0.34;    // overall brightness of the stroke (units stay brighter)
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
	// equal perceived brightness whichever colours are cycling (cream vei is far brighter than blue town)
	neon *= 0.45 / max(dot(neon, vec3(0.2126, 0.7152, 0.0722)), 0.12);

	// the beat, lagged by distance from Relish: a wave crossing the walls
	float lag = clamp(distance(v_world, relish_pos) / arena_diag, 0.0, 1.0) * wave_spread;
	float w = steady >= 0.0 ? steady : exp(-wave_decay * fract(beat - lag + 1.0));
	float shimmer = smoothstep(0.72, 1.0, 0.5 + 0.5 * sin(along * 0.045)) * w;
	float hot = 1.0 + heat;

	float lit = intensity * hot * (0.85 + 0.15 * w) + shimmer * 0.12 * hot;
	vec3 col = min(neon * lit, vec3(1.0));
	float a;
	if (d <= stroke_half) {
		a = 1.0; // the stroke
	} else {
		float g = clamp((d - stroke_half) / halo_px, 0.0, 1.0);
		a = (1.0 - g) * (1.0 - g) * 0.4;
	}
	COLOR = vec4(col, min(a, 1.0));
}
