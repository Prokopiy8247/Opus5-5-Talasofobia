shader_type spatial;
// A few large out-of-focus specks drifting right in front of the lens. In the deep they sell scale and darkness;
// in the sunlit shallows they are soft glints of particles catching the light (forward scatter, towards the sun).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;
#include "res://shaders/water_common.gdshaderinc"

uniform float box = 7.0;
uniform float amount = 0.0;
uniform vec4 color : source_color = vec4(0.62, 0.82, 1.0, 1.0);

varying float v_alpha;

void vertex() {
	float ph = INSTANCE_CUSTOM.w;
	vec3 base = INSTANCE_CUSTOM.xyz * box;
	vec3 drift = vec3(sin(TIME * 0.07 + ph * 6.0) * 0.5, -TIME * (0.012 + ph * 0.02), cos(TIME * 0.05 + ph * 4.0) * 0.5);
	vec3 rel = mod(base + drift - water_cam_pos, vec3(box)) - box * 0.5;
	vec3 w = water_cam_pos + rel;
	vec4 vp = VIEW_MATRIX * vec4(w, 1.0);
	float dist = -vp.z;
	// out of focus: the closer, the bigger and fainter the disc
	float size = mix(0.05, 0.16, fract(ph * 7.31)) * (1.0 + 0.6 * smoothstep(2.0, 0.5, dist));
	vp.xy += (UV - 0.5) * size;
	float fade = smoothstep(0.35, 0.9, dist) * (1.0 - smoothstep(box * 0.3, box * 0.48, length(rel)));
	// sunlit shallows: brighter specks, but only looking towards the light
	float d = max(-water_cam_pos.y, 0.0);
	vec3 vdir = rel / max(length(rel), 1e-3);
	float fwd = pow(max(dot(vdir, normalize(water_sun_dir)), 0.0), 3.0);
	float sunlit = (1.0 - smoothstep(15.0, 70.0, d)) * fwd * 3.5;
	// deep specks (amount, from WaterWorld) scatter forward too: brighter towards the light, faint looking down
	v_alpha = fade * (0.5 + 0.5 * fract(ph * 3.17)) / (1.0 + 3.0 * size) * (mix(0.45, 1.3, fwd) * amount + sunlit);
	VERTEX = vp.xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	// soft disc with a faintly brighter rim, like a real lens bokeh
	float disc = smoothstep(1.0, 0.45, r) * (0.9 + 0.1 * smoothstep(0.3, 0.85, r));
	ALBEDO = color.rgb * disc * v_alpha * 0.016 * water_light_scale;
}
