shader_type canvas_item;
// Draws one flow particle's segment into the trail buffer. Additive, so
// crossing streaks heat up like the HTML's 'lighter' composite. The quad's
// local y is the streak width: soften it so 1-2 px lines don't stair-step.
// Reduced motion (comet = 1): the quad is a still comet, head at local +x
// (UV.x = 1), fading to its tail; on living ground (the particle's CUSTOM.z,
// its living share) it is dashed, the non-hue channel the moving streaks get
// from their dash rhythm.
render_mode blend_add;

uniform float comet = 0.0;
uniform float comet_power = 1.6;   // head-to-tail falloff
uniform float comet_dashes = 3.0;  // dashes along a living comet
uniform float dash_duty = 0.5;

varying float v_living;

void vertex() {
	v_living = INSTANCE_CUSTOM.z;
}

void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float a = COLOR.a * across;
	if (comet > 0.5) {
		a *= pow(UV.x, comet_power);
		float on = step(fract((1.0 - UV.x) * comet_dashes), dash_duty);
		a *= mix(1.0, on, clamp(v_living, 0.0, 1.0));
	}
	COLOR = vec4(COLOR.rgb, a);
}
