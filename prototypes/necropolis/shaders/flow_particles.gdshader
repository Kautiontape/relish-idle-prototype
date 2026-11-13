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
// Figure over ground (the routes stay figure): every streak that exists clears
// 3:1 at its core, and the ink is set by how many there are, never by dimming.
//   - EMPTY ground is a sparse current (spawn_empty_weight), not a dense dim one,
//     and held ground is thinned the same way (spawn_land_weight);
//   - a streak born on empty ground fades and respawns once it is seam_land into
//     living ground, so the draught can't pile violet seams along a vortex rim;
//   - streaks thin out in a narrow moat beside each live lane (moat_*), except
//     near the lane's ends, where held ground round a node keeps its streaks.
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
uniform float spawn_land_weight = 1.0;   // < 1: fewer streaks on held ground (less overlap, same core)
// Seams: streaks born on empty ground fade and respawn once they are this far
// into held living ground, so the draught can't pile them up along a vortex rim.
uniform float seam_land = 0.35;
// Clumps: an empty-born streak whose spot in last frame's trail is already this
// bright (HDR buffer, mean rgb) respawns elsewhere. Caps sinks and pile-ups
// in the empty current without dimming any one streak. <= 0 turns it off.
uniform sampler2D trail_prev : filter_linear, repeat_disable;
uniform vec2 tr_x = vec2(1.0, 0.0);   // world -> history-buffer px, as columns
uniform vec2 tr_y = vec2(0.0, 1.0);
uniform vec2 tr_o = vec2(0.0, 0.0);
uniform vec2 tr_size = vec2(1600.0, 900.0);
uniform float clump_limit = 0.0;
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
// Lanes (figure over ground): each live route as a quadratic bow, refreshed
// by flow_ground.gd at field_hz. Streaks thin out in a moat beside each lane.
const int MAX_LANES = 64;
uniform vec4 lane_ac[MAX_LANES];   // start.xy, control.xy
uniform vec4 lane_bw[MAX_LANES];   // end.xy, half width (world), rate u
uniform int lane_count = 0;
uniform float moat_px = 10.0;      // moat beyond the lane's edge, screen px
uniform float moat_strength = 0.0; // 0 = off; 1 = the moat's core is empty
uniform vec2 moat_end = vec2(25.0, 70.0);  // world px from a lane's ends: no moat -> full moat
                                           // (held ground round a node keeps its streaks)
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

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float f = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	return distance(p, a + ab * f);
}

// 1 on a lane, 0 beyond its moat (smooth). Bounding-box reject first.
float moat_at(vec2 p) {
	float m = 0.0;
	float mw = moat_px * px_world;
	for (int i = 0; i < lane_count; i++) {
		vec2 a = lane_ac[i].xy;
		vec2 c = lane_ac[i].zw;
		vec2 b = lane_bw[i].xy;
		float hw = lane_bw[i].z;
		float reach = hw + mw;
		vec2 lo = min(min(a, b), c) - reach;
		vec2 hi = max(max(a, b), c) + reach;
		if (p.x < lo.x || p.y < lo.y || p.x > hi.x || p.y > hi.y) {
			continue;
		}
		float d = 1e9;
		vec2 prev = a;
		for (int k = 1; k <= 10; k++) {
			float s = float(k) / 10.0;
			vec2 q = mix(mix(a, c, s), mix(c, b, s), s);
			d = min(d, seg_dist(p, prev, q));
			prev = q;
		}
		float ends = smoothstep(moat_end.x, moat_end.y, min(distance(p, a), distance(p, b)));
		m = max(m, ends * (1.0 - smoothstep(hw, reach, d)));
	}
	return m;
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

float land_at(vec2 p) {
	vec2 uv = p / world_size;
	return smoothstep(presence.x, presence.y, texture(field_g, uv).r + texture(field_o, uv).r);
}

// Where a streak is born. Up to four tries in view; each is kept with
// mix(spawn_empty_weight, spawn_land_weight, land), less beside a lane (the moat). Held ground
// is where the information is, so it fills first; empty ground gets a sparse
// current of legible streaks, not a dense dim one. If no try is kept, the
// streak sleeps one life (z = 0) and tries again: no forced fallback.
// Returns xy = the point, z = 1 if kept, w = land there.
vec4 pick_spawn(uint s) {
	vec2 sp = spawn_pos(s);
	for (uint k = 0u; k < 4u; k++) {
		if (k > 0u) {
			sp = spawn_pos(s + k * 7919u);
		}
		float lnd = land_at(sp);
		float keep_here = mix(spawn_empty_weight, spawn_land_weight, lnd);
		if (moat_strength > 0.0 && lane_count > 0) {
			keep_here *= 1.0 - moat_strength * moat_at(sp);
		}
		if (hash1(s + (k + 1u) * 101u) < keep_here) {
			return vec4(sp, 1.0, lnd);
		}
	}
	return vec4(sp, 0.0, 0.0);
}

void start() {
	uint s = seed_of(INDEX, 0.0);
	vec4 sp = pick_spawn(s);
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xy = sp.xy;
	TRANSFORM[0] = vec4(0.0);
	TRANSFORM[1] = vec4(0.0);
	float life = life_of(s);
	// CUSTOM: x age (random start, so respawns never synchronise); y life,
	// negative for a streak born on empty ground (the seam rule); z distance
	// travelled (dash rhythm), -1 while asleep; w generation.
	CUSTOM = vec4(hash1(s + 29u) * life, sp.w < 0.5 ? -life : life, sp.z > 0.5 ? 0.0 : -1.0, 0.0);
	VELOCITY = vec3(0.0);
	COLOR = vec4(0.0);
}

void process() {
	vec2 p = TRANSFORM[3].xy;
	// Parked: beyond the active share (zoomed in, fewer, longer streaks). Marked
	// dead so it respawns in view the moment it is active again.
	bool parked = hash1(INDEX * 0x2c1b3c6du + 11u) > active;
	if (parked) {
		CUSTOM.x = abs(CUSTOM.y) + 1.0;
		COLOR = vec4(0.0);
		TRANSFORM[0] = vec4(0.0);
		TRANSFORM[1] = vec4(0.0);
	} else {
		CUSTOM.x += DELTA;
		bool regrown = hash1(INDEX * 0x165667b1u ^ uint(frame_seed) * 0x27d4eb2fu) < regrow;
		// empty-born streak deep enough into living ground: a seam in the making
		vec2 uvs = p / world_size;
		float gs = texture(field_g, uvs).r;
		float os = texture(field_o, uvs).r;
		float liv_here = smoothstep(presence.x, presence.y, gs + os) * clamp((os - gs) / 0.04, 0.0, 1.0);
		bool seam = CUSTOM.y < 0.0 && liv_here > seam_land;
		if (CUSTOM.y < 0.0 && clump_limit > 0.0 && CUSTOM.x > 0.5) {
			vec2 tuv = (tr_x * p.x + tr_y * p.y + tr_o) / tr_size;
			if (tuv.x > 0.0 && tuv.y > 0.0 && tuv.x < 1.0 && tuv.y < 1.0) {
				vec3 here = texture(trail_prev, tuv).rgb;
				seam = seam || (here.r + here.g + here.b) / 3.0 > clump_limit;
			}
		}
		if (CUSTOM.x > abs(CUSTOM.y) || regrown || seam || outside(p, keep_rect)
				|| p.x < 0.0 || p.y < 0.0 || p.x > world_size.x || p.y > world_size.y) {
			CUSTOM.w += 1.0;
			uint s = seed_of(INDEX, CUSTOM.w);
			vec4 sp = pick_spawn(s);
			TRANSFORM = mat4(1.0);
			TRANSFORM[3].xy = sp.xy;
			TRANSFORM[0] = vec4(0.0);
			TRANSFORM[1] = vec4(0.0);
			float lf = life_of(s);
			CUSTOM.x = 0.0;
			CUSTOM.y = sp.w < 0.5 ? -lf : lf;   // negative: born on empty ground
			CUSTOM.z = sp.z > 0.5 ? 0.0 : -1.0;  // -1: asleep this life
			COLOR = vec4(0.0);
		} else if (CUSTOM.z < 0.0) {
			// asleep: draws nothing until its life runs out, then tries again
			COLOR = vec4(0.0);
			TRANSFORM[0] = vec4(0.0);
			TRANSFORM[1] = vec4(0.0);
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
			float lf = abs(CUSTOM.y);
		a *= smoothstep(0.0, 0.35, CUSTOM.x) * (1.0 - smoothstep(lf - 0.6, lf, CUSTOM.x));
		// figure over ground: streaks thin out beside the lanes
		if (moat_strength > 0.0 && lane_count > 0) {
			a *= 1.0 - moat_strength * moat_at(np);
		}
		// an empty-born streak fades as it nears the seam line, instead of piling up there
		if (CUSTOM.y < 0.0) {
			a *= 1.0 - smoothstep(seam_land * 0.3, seam_land, liv);
		}
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
