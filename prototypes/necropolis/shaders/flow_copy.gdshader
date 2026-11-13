shader_type canvas_item;
// The trail's history: a straight copy of last frame's HDR trail buffer, so
// the next frame's reprojection can read it (a viewport can't sample itself).
render_mode blend_disabled;

uniform sampler2D src : filter_nearest, repeat_disable;

void fragment() {
	COLOR = texture(src, UV);
}
