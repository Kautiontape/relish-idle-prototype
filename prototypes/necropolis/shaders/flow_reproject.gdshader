shader_type canvas_item;
// First draw of every trail frame (flow_ground.gd): last frame's trail (the
// history copy) moved by the camera delta and faded by `keep`. Replaces the
// old world-space fade pass, so the trail buffer can follow the camera at
// screen resolution and stay crisp at any zoom. Off-screen history is black.
render_mode blend_disabled;

uniform sampler2D prev : filter_linear, repeat_disable;
uniform vec2 size = vec2(1600.0, 900.0);   // trail buffer px
// M = prev_xform * now_xform^-1, as columns: trail px now -> trail px last frame
uniform vec2 m_x = vec2(1.0, 0.0);
uniform vec2 m_y = vec2(0.0, 1.0);
uniform vec2 m_o = vec2(0.0, 0.0);
uniform float keep = 0.93;

void fragment() {
	vec2 q = UV * size;
	vec2 uv = (m_x * q.x + m_y * q.y + m_o) / size;
	vec4 c = vec4(0.0);
	if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0) {
		c = texture(prev, uv);
	}
	COLOR = c * keep;
}
