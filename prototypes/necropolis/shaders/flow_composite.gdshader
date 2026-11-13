shader_type canvas_item;
// Puts the HDR trail buffer on the map: additive over the #05060A ground, with
// a soft knee (1 - e^-x) so overlapping streaks get hotter without clipping
// their hue to white.
render_mode blend_add;

uniform float gain = 1.25;

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb * gain;
	COLOR = vec4(vec3(1.0) - exp(-c), 1.0);
}
