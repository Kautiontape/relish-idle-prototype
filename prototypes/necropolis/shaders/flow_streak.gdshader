shader_type canvas_item;
// Draws one flow particle's segment into the trail buffer. Additive, so
// crossing streaks heat up like the HTML's 'lighter' composite. The quad's
// local y is the streak width: soften it so 1-2 px lines don't stair-step.
render_mode blend_add;

void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	COLOR = vec4(COLOR.rgb, COLOR.a * across);
}
