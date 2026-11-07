shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
// Directional water light (WATER LIGHT CONTRACT): daylight comes from above, so the water is brighter looking up
// and fades to a blue abyss looking down. Multiplies the frame by mix(1, wl_ratio(dir), f) where f is the
// exponential-fog amount along the pixel's ray: fully fogged geometry and the backdrop get exactly the same
// ratio (no silhouettes), nearby lit surfaces keep their colour. Surface-plane pixels (y > -0.6) shade themselves.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float fog_density = 0.0085;
global uniform float g_depth;

// --- contract: keep identical in every shader that uses it
float wl_grad(float depth) {
	return 1.0 - smoothstep(150.0, 330.0, depth);
}

vec3 wl_ratio(vec3 d, float depth) {
	float dn = smoothstep(0.0, 0.95, -d.y);
	dn = dn * dn * (3.0 - 2.0 * dn);
	vec3 r = mix(vec3(1.0), vec3(0.30, 0.36, 0.48), dn) * (1.0 + 0.35 * smoothstep(0.0, 0.66, d.y));
	return mix(vec3(1.0), r, wl_grad(depth));
}
// ---

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float dist = length(view.xyz);
	vec3 d = normalize((INV_VIEW_MATRIX * vec4(view.xyz, 0.0)).xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 wp = cam + d * dist;
	float f = 1.0;   // the backdrop sphere (r 5200 m) is "fully fogged" by definition
	if (dist < 5000.0) {
		f = wp.y > -0.6 ? 0.0 : 1.0 - exp(-fog_density * dist);
	}
	ALBEDO = mix(vec3(1.0), wl_ratio(d, g_depth), f);
}
