shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Distant amber lamps: camera-facing points kept a few pixels wide at any range, with their own gentle
// distance attenuation (exponential fog would erase them), staggered switch-on (reveal) and faint flicker.
// Graded by distance: near floor lamps are larger points than the wall lamps 1 km away (a size cue for depth),
// far lamps get a wider forward-scatter halo and lose a little red, so the field reads as a 1 km space rather
// than wallpaper. The hatch beacon gets the wide halo from afar: a lure seen from 100+ m above.
// INSTANCE_CUSTOM: x = reveal delay (s), y = brightness, z = seed, w = kind (1 always on, 0.5 foreshadow).
uniform vec4 lamp_col : source_color = vec4(1.0, 0.706, 0.353, 1.0);
uniform float reveal_time = -1.0;
uniform float energy = 6.0;
uniform float foreshadow = 0.0;     // on-level of the foreshadow lamps before the wave (ramped by depth)
uniform float beacon = 1.0;         // on-level of the always-on hatch lamp (ramped by depth, never popped)
global uniform vec3 g_cam_pos;
global uniform float g_time;

varying float v_int;
varying float v_k;
varying vec3 v_tint;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	float d = length(c - g_cam_pos);
	float size = max(0.3, d * mix(0.016, 0.010, smoothstep(150.0, 1500.0, d)));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size, INV_VIEW_MATRIX[2] * size, vec4(c, 1.0));
	float on = smoothstep(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.x + 1.4, reveal_time);
	v_k = smoothstep(100.0, 1500.0, d);
	if (INSTANCE_CUSTOM.w > 0.75) {
		on = beacon;
		v_k = max(v_k, smoothstep(15.0, 60.0, d));
	} else if (INSTANCE_CUSTOM.w > 0.25) {
		// chance lights: each foreshadow lamp at its own faint level (0.55-1.2 x, i.e. 0.08-0.18 at full)
		on = max(on, foreshadow * mix(0.55, 1.2, INSTANCE_CUSTOM.z));
	}
	float flick = 0.92 + 0.08 * sin(g_time * (1.1 + INSTANCE_CUSTOM.z * 2.3) + INSTANCE_CUSTOM.z * 61.0);
	float atten = exp(-d * 0.0011);
	v_int = on * flick * atten * INSTANCE_CUSTOM.y;
	v_tint = mix(vec3(1.0), vec3(0.88, 1.0, 0.8), smoothstep(150.0, 2000.0, d));
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float core = exp(-r * r * 14.0);
	float halo = exp(-r * r * mix(3.5, 1.6, v_k)) * mix(0.12, 0.3, v_k) * (1.0 - smoothstep(0.6, 1.0, r));
	ALBEDO = lamp_col.rgb * v_tint * ((core + halo) * energy * v_int);
	FOG = vec4(0.0);
}
