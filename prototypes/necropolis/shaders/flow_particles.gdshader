shader_type particles;
// Flow-field ground: each particle is one streak head advected through a
// velocity field built from Game.field (green, orange, entrench), then drawn
// as a short segment into a persistent trail buffer (see flow_ground.gd).
// Ported from realm-snapshot aesthetics/04-flow-field-synthwave.html:
//   drift toward Vei · turbulence at the front · stillness on settled ground.
// Necropolis reading (the non-hue channels):
//   UNDEAD ground flows TOWARD Vei, continuous streaks, brightest luminance.
//   LIVING ground circulates on its own pressure contours, dashed streaks
//   (dash rhythm by distance).
//   The FRONT (both sides present) is violet churn: curl-noise turbulence.
//   ENTRENCHED ground is slow and laminar: no noise, saturated toward the core.
render_mode disable_velocity, disable_force;

uniform sampler2D field_g : filter_linear, repeat_disable;
uniform sampler2D field_o : filter_linear, repeat_disable;
uniform sampler2D field_e : filter_linear, repeat_disable;
uniform vec2 world_size = vec2(2048.0, 1440.0);
uniform vec2 grid_size = vec2(128.0, 90.0);
uniform vec2 cov_pos = vec2(1780.0, 1270.0);
uniform vec2 vei_pos = vec2(1024.0, 130.0);
uniform float t = 0.0;

uniform float speed = 64.0;
uniform float speed_empty = 0.55;
uniform float speed_settled = 0.4;
uniform float front_boost = 0.7;
uniform float speed_living = 0.7;
uniform float draught = 1.0;
uniform float draught_empty = 0.3;
uniform float push = 0.9;
uniform float orbit_strength = 1.0;
uniform float turbulence = 1.6;
uniform float turbulence_empty = 0.6;
uniform float turbulence_land = 0.15;
uniform float noise_scale = 0.0032;
uniform float noise_evolve = 0.12;
uniform vec2 presence = vec2(0.01, 0.22);
uniform vec2 front_range = vec2(0.03, 0.22);
uniform float commit_dominance = 3.0;
uniform float commit_entrench = 0.35;
uniform float entrench_ref = 2.5;
// The exhale is Pulse's beat (one tempo, one clock): beat = Pulse.phase(0) at
// Covington, and the lag grows to Pulse.wave_spread at Vei's distance, the
// same lag her node pulse gets two hops out.
uniform float beat = 0.0;
uniform float wave_spread = 0.5;
uniform float tempo_amp = 0.53;
uniform vec2 life_s = vec2(2.5, 6.5);
uniform float spawn_empty_weight = 0.3;
uniform float dash_px = 15.0;
uniform float dash_duty = 0.5;
uniform float streak_width_px = 1.35;   // on screen, at any zoom
// the camera (flow_ground.gd sets these every frame, in frame_pre_draw)
uniform vec4 spawn_rect = vec4(0.0, 0.0, 2048.0, 1440.0);   // visible world: x, y, w, h
uniform vec4 keep_rect = vec4(-64.0, -64.0, 2176.0, 1568.0); // visible world + margin
uniform float active = 1.0;        // share of particles alive (constant ink across zoom)
uniform float regrow = 0.0;        // share to respawn this frame (zoom-out uncovered world)
uniform float frame_seed = 0.0;
uniform float px_world = 1.0;      // world units per screen px
uniform float alpha_empty = 0.2;
uniform float alpha_land = 0.95;
uniform float alpha_front = 0.95;
uniform float core_mix = 0.3;
uniform vec4 col_green = vec4(0.224, 1.0, 0.62, 1.0);
uniform vec4 col_green_core = vec4(0.788, 1.0, 0.91, 1.0);
uniform vec4 col_orange = vec4(1.0, 0.416, 0.169, 1.0);
uniform vec4 col_orange_core = vec4(1.0, 0.839, 0.69, 1.0);
uniform vec4 col_violet = vec4(0.588, 0.376, 1.0, 1.0);

float hash1(uint n) {
	n = n * 747796405u + 2891336453u;
	uint w = ((n >> ((n >> 28u) + 4u)) ^ n) * 277803737u;
	w = (w >> 22u) ^ w;
	return float(w) / 4294967295.0;
}

float h3(ivec3 c) {
	uint n = uint(c.x) * 73856093u ^ uint(c.y) * 19349663u ^ uint(c.z) * 83492791u;
	return hash1(n);
}

// 3D value noise, smoothstep fade — the lab's vnoise, curled below.
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = x - i;
	vec3 u = f * f * (3.0 - 2.0 * f);
	ivec3 c = ivec3(i);
	float a = mix(h3(c), h3(c + ivec3(1, 0, 0)), u.x);
	float b = mix(h3(c + ivec3(0, 1, 0)), h3(c + ivec3(1, 1, 0)), u.x);
	float d = mix(h3(c + ivec3(0, 0, 1)), h3(c + ivec3(1, 0, 1)), u.x);
	float e = mix(h3(c + ivec3(0, 1, 1)), h3(c + ivec3(1, 1, 1)), u.x);
	return mix(mix(a, b, u.y), mix(d, e, u.y), u.z);
}

float psi(vec2 q, float z) {
	return vnoise(vec3(q, z)) * 0.6667 + vnoise(vec3(q * 2.0, z * 1.3 + 7.1)) * 0.3333;
}

// Curl of a scalar potential: divergence-free, so the churn never pools.
vec2 curl(vec2 p) {
	vec2 q = p * noise_scale;
	float z = t * noise_evolve;
	float e = 0.05;
	float dy = psi(q + vec2(0.0, e), z) - psi(q - vec2(0.0, e), z);
	float dx = psi(q + vec2(e, 0.0), z) - psi(q - vec2(e, 0.0), z);
	vec2 c = vec2(dy, -dx);
	float l = length(c);
	return l > 1e-6 ? c / l : vec2(0.0);
}

vec2 spawn_pos(uint s) {
	return spawn_rect.xy + vec2(hash1(s), hash1(s ^ 0x9e3779b9u)) * spawn_rect.zw;
}

bool outside(vec2 p, vec4 r) {
	return p.x < r.x || p.y < r.y || p.x > r.x + r.z || p.y > r.y + r.w;
}

float life_of(uint s) {
	return mix(life_s.x, life_s.y, hash1(s + 17u));
}

uint seed_of(uint idx, float gen) {
	return idx * 2654435761u ^ (uint(gen) * 2246822519u + 374761393u);
}

void start() {
	uint s = seed_of(INDEX, 0.0);
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xy = spawn_pos(s);
	TRANSFORM[0] = vec4(0.0);
	TRANSFORM[1] = vec4(0.0);
	float life = life_of(s);
	// random starting age so respawns never synchronise
	CUSTOM = vec4(hash1(s + 29u) * life, life, 0.0, 0.0);
	VELOCITY = vec3(0.0);
	COLOR = vec4(0.0);
}

void process() {
	vec2 p = TRANSFORM[3].xy;
	// Parked: beyond the active share (zoomed in, fewer, longer streaks). Marked
	// dead so it respawns in view the moment it is active again.
	bool parked = hash1(INDEX * 0x2c1b3c6du + 11u) > active;
	if (parked) {
		CUSTOM.x = CUSTOM.y + 1.0;
		COLOR = vec4(0.0);
		TRANSFORM[0] = vec4(0.0);
		TRANSFORM[1] = vec4(0.0);
	} else {
		CUSTOM.x += DELTA;
		bool regrown = hash1(INDEX * 0x165667b1u ^ uint(frame_seed) * 0x27d4eb2fu) < regrow;
		if (CUSTOM.x > CUSTOM.y || regrown || outside(p, keep_rect)
				|| p.x < 0.0 || p.y < 0.0 || p.x > world_size.x || p.y > world_size.y) {
			CUSTOM.w += 1.0;
			uint s = seed_of(INDEX, CUSTOM.w);
			// respawn biased toward held ground: that is where the information is
			vec2 sp = spawn_pos(s);
			for (uint k = 1u; k < 4u; k++) {
				vec2 uv = sp / world_size;
				float lnd = smoothstep(presence.x, presence.y, texture(field_g, uv).r + texture(field_o, uv).r);
				if (hash1(s + k * 101u) < mix(spawn_empty_weight, 1.0, lnd)) {
					break;
				}
				sp = spawn_pos(s + k * 7919u);
			}
			TRANSFORM = mat4(1.0);
			TRANSFORM[3].xy = sp;
			TRANSFORM[0] = vec4(0.0);
			TRANSFORM[1] = vec4(0.0);
			CUSTOM.x = 0.0;
			CUSTOM.y = life_of(s);
			CUSTOM.z = 0.0;
			COLOR = vec4(0.0);
		} else {
			vec2 cell = world_size / grid_size;
			vec2 h = cell * 1.5;
			vec2 inv = 1.0 / world_size;
			float g = texture(field_g, p * inv).r;
			float o = texture(field_o, p * inv).r;
			float e = texture(field_e, p * inv).r;
			float gr = texture(field_g, (p + vec2(h.x, 0.0)) * inv).r;
			float gl = texture(field_g, (p - vec2(h.x, 0.0)) * inv).r;
			float gd = texture(field_g, (p + vec2(0.0, h.y)) * inv).r;
			float gu = texture(field_g, (p - vec2(0.0, h.y)) * inv).r;
			float orr = texture(field_o, (p + vec2(h.x, 0.0)) * inv).r;
			float ol = texture(field_o, (p - vec2(h.x, 0.0)) * inv).r;
			float od = texture(field_o, (p + vec2(0.0, h.y)) * inv).r;
			float ou = texture(field_o, (p - vec2(0.0, h.y)) * inv).r;

			float pr = g - o;                      // + undead, - living
			float land = smoothstep(presence.x, presence.y, g + o);
			// gradient of pressure, per cell
			vec2 gp = vec2((gr - orr) - (gl - ol), (gd - od) - (gu - ou)) * (1.0 / 3.0);
			float gpl = length(gp);
			vec2 gpn = gpl > 1e-5 ? gp / gpl : vec2(0.0);
			// the FRONT: both sides present within ~1.5 cells
			float gmax = max(g, max(max(gr, gl), max(gd, gu)));
			float omax = max(o, max(max(orr, ol), max(od, ou)));
			float front = smoothstep(front_range.x, front_range.y, min(gmax, omax));
			// SETTLED: entrenched and not contested
			float settle = smoothstep(0.15, 0.9, abs(e) / entrench_ref) * (1.0 - front);
			float side = clamp(pr / 0.04, -1.0, 1.0);   // smooth sign of who holds it

			// direction. UNDEAD streams toward Vei and down the pressure slope into
			// the front. LIVING circulates along its own pressure contours (perp of a
			// gradient: divergence-free, so held ground never empties or pools); a
			// plateau with no slope orbits Vei instead. EMPTY ground drifts weakly
			// toward Vei. The front and empty ground churn with curl noise.
			vec2 to_vei = vei_pos - p;
			float dv = length(to_vei);
			to_vei = dv > 1e-3 ? to_vei / dv : vec2(0.0, -1.0);
			float und = land * clamp(side, 0.0, 1.0);
			float liv = land * clamp(-side, 0.0, 1.0);
			float slope = min(1.0, gpl / 0.08);
			vec2 stream = to_vei * draught - gpn * slope * push;
			vec2 orbit = vec2(-gpn.y, gpn.x) * slope + vec2(-to_vei.y, to_vei.x) * (1.0 - slope);
			vec2 dir = stream * und + orbit * orbit_strength * liv + to_vei * draught_empty * (1.0 - land);
			float turb = mix(turbulence_empty, turbulence_land, land) + turbulence * front;
			turb *= 1.0 - settle;
			dir += curl(p) * turb;
			float dl = length(dir);
			dir = dl > 1e-5 ? dir / dl : to_vei;

			// the exhale, phase-offset by distance from Covington (Pulse's wave)
			float lag = wave_spread * clamp(distance(p, cov_pos) / max(1.0, distance(vei_pos, cov_pos)), 0.0, 1.0);
			float ph = fract(beat - lag);
			float c = 0.5 + 0.5 * cos(ph * 6.2831853);
			float tempo = 1.0 + tempo_amp * (c * c * c - 0.18);

			float spd = speed * mix(speed_empty, 1.0, land) * mix(1.0, speed_settled, settle)
				* mix(1.0, speed_living, liv)
				* (1.0 + front_boost * front) * tempo;
			vec2 np = p + dir * spd * DELTA;
			vec2 d = np - p;
			float len = length(d);
			vec2 sd = len > 1e-6 ? d / len : dir;

			// colour: violet = uncommitted / front, saturating to green or orange
			float commit = clamp(abs(pr) * commit_dominance + abs(e) * commit_entrench, 0.0, 1.0);
			commit *= land * (1.0 - front);
			vec4 tgt = pr >= 0.0 ? col_green : col_orange;
			vec4 core = pr >= 0.0 ? col_green_core : col_orange_core;
			vec3 col = mix(col_violet.rgb, tgt.rgb, pow(commit, 0.85));
			col = mix(col, core.rgb, core_mix * settle * commit);
			float a = mix(alpha_empty, alpha_land, land);
			a = max(a, alpha_front * front);
			// living: dash rhythm by distance travelled (a non-hue channel)
			CUSTOM.z += len;
			float living = liv * (1.0 - front);
			float on = step(fract(CUSTOM.z / dash_px + hash1(INDEX + 3u)), dash_duty);
			a *= mix(1.0, on, living);
			// fade in after spawn, out before respawn
			a *= smoothstep(0.0, 0.35, CUSTOM.x) * (1.0 - smoothstep(CUSTOM.y - 0.6, CUSTOM.y, CUSTOM.x));
			COLOR = vec4(col, a);

			// segment p -> np, drawn as a quad of length 2*len centred on np.
			// Successive quads tile the path, so deposit per unit path is
			// independent of frame rate.
			TRANSFORM[0] = vec4(sd * max(len * 2.0, 1e-4), 0.0, 0.0);
			TRANSFORM[1] = vec4(vec2(-sd.y, sd.x) * streak_width_px * px_world, 0.0, 0.0);
			TRANSFORM[3].xy = np;
		}
	}
}
