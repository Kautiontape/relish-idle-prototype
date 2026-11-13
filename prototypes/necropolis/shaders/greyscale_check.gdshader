shader_type canvas_item;
// Debug: whole-screen greyscale by relative luminance (linearised, then
// re-encoded), to check that colour is never the only signal.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

vec3 to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float to_srgb(float l) {
	return l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1.0 / 2.4) - 0.055;
}

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float y = dot(to_lin(c), vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(vec3(to_srgb(y)), 1.0);
}
