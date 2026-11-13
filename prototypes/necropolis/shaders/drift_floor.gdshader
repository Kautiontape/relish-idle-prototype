shader_type particles;
// DriftFloor (scripts/fx/drift_floor.gd): the shared slow current under town
// and dungeon (VISUAL-LANGUAGE law 1). Each particle is one faint streak head
// advected through a drift field the scene provides (baked to `field`, RG =
// drift vector, length = strength). The streak is a comet: drift_floor.gd's
// gradient texture is bright at the head and fades to the tail, so a still
// frame (reduced motion) still shows which way the floor runs.
// Source look: realm-snapshot aesthetics/04-flow-field-synthwave.html, as a
// sparse, slow, stateless-draw variant (no trail buffer).
render_mode disable_velocity, disable_force;

uniform sampler2D field : filter_linear, repeat_disable;
uniform vec4 rect = vec4(0.0, 0.0, 1600.0, 900.0);   // x, y, w, h in the floor's local space
uniform vec4 tint : source_color = vec4(0.243, 0.361, 0.561, 1.0);
uniform float alpha = 1.0;
uniform float speed = 16.0;          // px/s at drift strength 1
uniform float motion = 1.0;          // 0 under reduced motion: positions and ages freeze
uniform float length_px = 28.0;
uniform float width_px = 1.6;
uniform vec2 tex_size = vec2(64.0, 8.0);   // the gradient texture's size
uniform vec2 life_s = vec2(4.0, 9.0);
uniform float min_strength = 0.04;
// the exhale: Pulse's beat, lagged by distance from the scene's source
uniform float beat = 0.0;
uniform float wave_spread = 0.5;
uniform vec2 source = vec2(0.0);
uniform float reach = 1000.0;        // distance at which the lag reaches wave_spread
uniform float exhale_speed = 0.8;
uniform float exhale_length = 0.35;

float hash1(uint n) {
	n = n * 747796405u + 2891336453u;
	uint w = ((n >> ((n >> 28u) + 4u)) ^ n) * 277803737u;
	w = (w >> 22u) ^ w;
	return float(w) / 4294967295.0;
}

// Respawn seed from the index and the dying head's position bits (CUSTOM has
// no room for a generation counter: x age, y life, zw the head position).
uint seed_of(uint idx, vec2 p) {
	return idx * 2654435761u ^ (floatBitsToUint(p.x) * 2246822519u + floatBitsToUint(p.y) * 3266489917u + 374761393u);
}

vec2 drift(vec2 p) {
	return texture(field, (p - rect.xy) / rect.zw).rg;
}

bool outside(vec2 p) {
	return p.x < rect.x || p.y < rect.y || p.x > rect.x + rect.z || p.y > rect.y + rect.w;
}

// Uniform in the rect, thinned where the drift is weak (density follows strength).
vec2 spawn(uint s) {
	vec2 sp = rect.xy + vec2(hash1(s), hash1(s ^ 0x9e3779b9u)) * rect.zw;
	for (uint k = 1u; k < 4u; k++) {
		if (hash1(s + k * 101u) < clamp(length(drift(sp)), 0.0, 1.0)) {
			break;
		}
		sp = rect.xy + vec2(hash1(s + k * 7919u), hash1((s + k * 7919u) ^ 0x9e3779b9u)) * rect.zw;
	}
	return sp;
}

// A fresh head: (age 0, life, position). Built-ins only exist inside
// start()/process(), so the callers write CUSTOM, COLOR and TRANSFORM.
vec4 respawn(uint s) {
	vec2 p = spawn(s);
	return vec4(0.0, mix(life_s.x, life_s.y, hash1(s + 17u)), p);
}

void start() {
	uint s = seed_of(INDEX, vec2(0.0));
	CUSTOM = respawn(s);             // x age, y life, zw the head's true position
	CUSTOM.x = hash1(s + 29u) * CUSTOM.y;   // random starting age: respawns never synchronise
	COLOR = vec4(0.0);
	TRANSFORM = mat4(1.0);
	TRANSFORM[0] = vec4(0.0);
	TRANSFORM[1] = vec4(0.0);
	TRANSFORM[3].xy = CUSTOM.zw;
}

void process() {
	vec2 p = CUSTOM.zw;
	CUSTOM.x += DELTA * motion;
	vec2 v = drift(p);
	float s = length(v);
	if (CUSTOM.x > CUSTOM.y || outside(p) || s < min_strength) {
		CUSTOM = respawn(seed_of(INDEX, p + vec2(CUSTOM.x, CUSTOM.y)));
		COLOR = vec4(0.0);
		TRANSFORM[0] = vec4(0.0);    // zero-size quad until the next frame draws it
		TRANSFORM[1] = vec4(0.0);
		TRANSFORM[3].xy = CUSTOM.zw;
	} else {
		vec2 dir = v / s;
		float lag = wave_spread * clamp(distance(p, source) / max(1.0, reach), 0.0, 1.0);
		float c = 0.5 + 0.5 * cos(fract(beat - lag) * 6.2831853);
		float surge = c * c * c;
		p += dir * min(s, 1.5) * speed * (1.0 + exhale_speed * surge) * DELTA * motion;
		CUSTOM.zw = p;
		float a = alpha;
		a *= smoothstep(0.0, 0.8, CUSTOM.x) * (1.0 - smoothstep(CUSTOM.y - 0.8, CUSTOM.y, CUSTOM.x));
		COLOR = vec4(tint.rgb, a);
		float len = length_px * (1.0 + exhale_length * surge);
		// quad along the drift, head at p, tail behind it
		TRANSFORM[0] = vec4(dir * (len / tex_size.x), 0.0, 0.0);
		TRANSFORM[1] = vec4(vec2(-dir.y, dir.x) * (width_px / tex_size.y), 0.0, 0.0);
		TRANSFORM[3].xy = p - dir * len * 0.5;
	}
}
