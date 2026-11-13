shader_type canvas_item;
// Trail persistence: multiplies the (HDR) trail buffer by `keep` every frame.
// flow_ground.gd sets keep = keep_per_s ^ dt, so trail length is frame-rate
// independent. HDR float storage means it decays all the way to black.
render_mode blend_mul;

uniform float keep = 0.93;

void fragment() {
	COLOR = vec4(vec3(keep), 1.0);
}
