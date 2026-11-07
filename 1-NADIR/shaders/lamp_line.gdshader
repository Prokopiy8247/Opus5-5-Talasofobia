shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Faint threads rising from the near floor lamps: every lamp is the end of another line. A camera-facing
// vertical strip kept >= ~1.3 px wide (no dashes), its brightness scaled by the true coverage of a 3 cm line
// (same trick as rope.gdshader), lit by its own lamp at the bottom and fading up into the black.
// INSTANCE_CUSTOM: x = reveal delay (s), y = brightness (same as the lamp it hangs from).
uniform vec4 lamp_col : source_color = vec4(1.0, 0.706, 0.353, 1.0);
uniform float reveal_time = -1.0;
uniform float height = 120.0;
uniform float gain = 0.45;
global uniform vec3 g_cam_pos;

varying float v_on;
varying float v_cover;
varying float v_y;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 to = base - g_cam_pos;
	float d = length(to);
	float w = max(0.03, d * 0.0021);
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), to));
	float hy = VERTEX.y + 0.5;                     // 0 at the lamp, 1 at the top
	VERTEX = vec3(0.0, hy * height, 0.0) + side * (VERTEX.x * w);   // instance basis is identity
	v_y = hy * height;
	v_cover = 0.03 / w;
	v_on = smoothstep(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.x + 1.4, reveal_time) * exp(-d * 0.0011) * INSTANCE_CUSTOM.y;
}

void fragment() {
	float lit = exp(-v_y / 5.0) + 0.012 * exp(-v_y / 40.0);
	ALBEDO = lamp_col.rgb * (lit * v_cover * v_on * gain);
}
