shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Twilight siphonophore (B2): a string of cold living lights in the navy, drawn like the B6 lamps as
// camera-facing points (core + soft halo) kept ~1.5 px wide at any range, with their own gentle attenuation
// instead of fog. The zooids bunch into cormidia along a faint glowing stem (stem points: halo only), the string
// undulates slowly and a wide pulse of light runs down it every 9 s (it starts before the first zooid and ends
// after the last, so nothing pops at the ends).
// Cold cyan only (colour script). Beat02 drives `gain` (fades in with depth) and `alarm` (seconds since the
// torch came on: a warning flash races down the string and each light dies as it passes).
// INSTANCE_CUSTOM: x = position along the string (0..1), y = brightness of this point, z = seed, w = 1 for stem.
uniform vec4 chain_col : source_color = vec4(0.275, 0.784, 1.0, 1.0);   // #46c8ff
uniform float energy = 0.45;
uniform float gain = 0.0;
uniform float count = 56.0;
uniform float alarm = -1.0;
uniform vec3 wave_axis = vec3(0.0, 1.0, 0.0);
uniform vec3 wave_axis2 = vec3(1.0, 0.0, 0.0);
global uniform vec3 g_cam_pos;
global uniform float g_time;

varying float v_int;
varying float v_stem;

void vertex() {
	float fi = INSTANCE_CUSTOM.x;
	float i = fi * count;
	vec3 c = MODEL_MATRIX[3].xyz
		+ wave_axis * 0.8 * sin(g_time * 0.4 + i * 0.25)
		+ wave_axis2 * 0.35 * sin(g_time * 0.23 + i * 0.11 + 1.7);
	float d = length(c - g_cam_pos);
	float size = max(0.3, d * 0.016);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size, INV_VIEW_MATRIX[2] * size, vec4(c, 1.0));
	float head = fract(g_time / 9.0) * 1.8 - 0.4;
	float pulse = 0.5 + exp(-pow((fi - head) * 6.0, 2.0));
	float flick = mix(0.9 + 0.1 * sin(g_time * (0.7 + INSTANCE_CUSTOM.z * 1.9) + INSTANCE_CUSTOM.z * 40.0), 1.0,
		INSTANCE_CUSTOM.w);
	v_int = gain * pulse * flick * INSTANCE_CUSTOM.y * exp(-0.018 * d);
	if (alarm >= 0.0) {
		float a = alarm - fi * 0.9;                       // the flash runs down the string in 0.9 s
		v_int *= (1.0 + 6.0 * exp(-pow(a / 0.1, 2.0))) * (1.0 - smoothstep(0.05, 0.35, a));
	}
	v_int = min(v_int, 1.9);                              // energy x core stays under the 1.05 glow threshold
	v_stem = INSTANCE_CUSTOM.w;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float core = exp(-r * r * 14.0) * (1.0 - v_stem);
	float halo = max(exp(-r * r * 3.5) - 0.0302, 0.0) * 0.31;   // reaches exactly 0 at the quad edge
	ALBEDO = chain_col.rgb * (core + halo) * energy * v_int;
	FOG = vec4(0.0);
}
