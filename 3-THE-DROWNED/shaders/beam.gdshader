shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;
// The diver's lamp seen in the water: light scattered back toward the eye along each view ray inside
// the lamp's cone, up to the first surface (depth texture). Drawn as one full-screen quad.
#include "res://shaders/inc/uw.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float density = 0.012;
uniform float max_dist = 38.0;
uniform vec3 lamp_color : source_color = vec3(1.0, 0.93, 0.82);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	if (uw_lamp_dir.w <= 0.001) {
		discard;
	}
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vec3 pv = vp.xyz / vp.w;
	float scene = length(pv);
	vec3 ray = pv / max(scene, 1e-4);
	vec3 lp = (VIEW_MATRIX * vec4(uw_lamp_pos, 1.0)).xyz;
	vec3 ld = normalize((VIEW_MATRIX * vec4(uw_lamp_dir.xyz, 0.0)).xyz);
	float t1 = min(scene, max_dist);
	const int N = 14;
	float acc = 0.0;
	vec3 accc = vec3(0.0);
	float prev = 0.0;
	for (int i = 1; i <= N; i++) {
		float f = float(i) / float(N);
		float t = t1 * f * f;                       // denser near the eye
		float dt = t - prev;
		prev = t;
		vec3 p = ray * t;
		vec3 lv = p - lp;
		float dl = length(lv);
		float cone = smoothstep(0.84, 0.975, dot(lv / max(dl, 1e-3), ld));
		float fall = 1.0 / (1.0 + dl * dl * 0.055);    // a cone near the lamp, no veil far down the axis
		float near = smoothstep(0.8, 4.0, t);                      // the first metres are out of the beam's edge
		vec3 absorb = exp(-vec3(0.11, 0.035, 0.03) * (t + dl));   // red is lost first in water
		accc += cone * fall * near * absorb * dt;
	}
	// looking straight down the beam sees its weakest (back-scattered) light: the subject stays clear
	float view_along = max(dot(ray, ld), 0.0);
	float phase = 1.0 - 0.45 * smoothstep(0.85, 1.0, view_along);
	vec3 col = lamp_color * accc * density * phase * uw_lamp_dir.w;
	col *= 0.95 + 0.1 * uw_vnoise2(SCREEN_UV * vec2(24.0, 13.5) + uw_time * 0.25);
	ALBEDO = col;
}
