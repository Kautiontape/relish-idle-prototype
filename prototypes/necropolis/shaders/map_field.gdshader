shader_type canvas_item;
// Necrosis field look: posterized bands + faint living shimmer over the
// influence texture. Kept subtle — the field is information, not wallpaper.

uniform float bands = 5.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float n = hash21(floor(UV * vec2(256.0, 180.0)) + floor(TIME * 2.0));
	float a = floor(c.a * bands + n * 0.4) / bands;
	a += 0.035 * sin(TIME * 0.75 + UV.x * 9.0 + UV.y * 7.0) * step(0.02, c.a);
	COLOR = vec4(c.rgb, clamp(a, 0.0, 0.92));
}
