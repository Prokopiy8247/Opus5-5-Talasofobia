shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// Marine snow: a fixed set of flakes wrapped into a box that always surrounds the camera.
// VERTEX holds the flake seed position, UV the quad corner, UV2.x a random value.
// Flakes sparkle inside the diver's lamp beam; in the deep a few plankton specks pulse blue-green.
// Near a warm lamp (warm_pos, set by DoorLamp: the bulb over the door) flakes drift lit amber, brighter
// under its shade than above it, falling off over ~7 m.
#include "res://shaders/inc/uw.gdshaderinc"

uniform float box = 36.0;
uniform float size = 0.035;
uniform float brightness = 1.0;
uniform vec3 warm_pos = vec3(0.0, 100000.0, 0.0);   // world position of the warm lamp's bulb
uniform vec3 warm_col : source_color = vec3(1.0, 0.55, 0.2);
uniform float warm_power = 0.0;                      // 0 = no warm lamp (DoorLamp.set_power drives it)
uniform float warm_range = 7.5;                      // metres to black

varying float alpha;
varying float depthy;
varying float lampv;
varying float warmv;
varying float rndv;
varying float dcam;

void vertex() {
	float rnd = UV2.x;
	vec3 drift = vec3(sin(uw_time * 0.13 + rnd * 40.0) * 0.6, -uw_time * (0.04 + rnd * 0.05),
		cos(uw_time * 0.11 + rnd * 23.0) * 0.6);
	vec3 rel = mod(VERTEX + drift - uw_cam_pos + box * 0.5, vec3(box)) - box * 0.5;
	vec3 wp = uw_cam_pos + rel;
	vec4 vp = VIEW_MATRIX * vec4(wp, 1.0);
	float s = size * (0.5 + rnd);
	vp.xy += (UV - 0.5) * s;
	POSITION = PROJECTION_MATRIX * vp;
	float d = length(rel);
	alpha = (1.0 - smoothstep(box * 0.25, box * 0.5, d)) * smoothstep(0.4, 1.4, d);
	depthy = wp.y;
	lampv = uw_lamp_at(wp);
	warmv = 0.0;
	if (warm_power > 0.0) {
		vec3 lv = wp - warm_pos;
		float dl = length(lv);
		float shade = mix(0.3, 1.0, smoothstep(0.35, -0.2, lv.y / max(dl, 1e-3)));   // the shade keeps the light low
		warmv = warm_power * exp(-dl / (warm_range * 0.33)) * (1.0 - smoothstep(warm_range * 0.6, warm_range, dl)) * shade;
	}
	rndv = rnd;
	dcam = d;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = (1.0 - smoothstep(0.2, 1.0, r)) * alpha;
	float l = uw_light(depthy);
	vec3 c = mix(pal_teal_far * 0.9, pal_shaft * 0.55, l) * brightness;
	// in the warm light the diver's white sparkle gives way to amber (it reads as the lamp's light)
	c += vec3(1.0, 0.95, 0.86) * lampv * 2.2 * (1.0 - 0.6 * clamp(warmv * 2.0, 0.0, 1.0));
	c += warm_col * warmv * 4.5;
	// bioluminescent plankton: rare specks near the diver below ~350 m, short slow pulses
	float deep = smoothstep(-330.0, -450.0, depthy);
	float near = 1.0 - smoothstep(1.5, 6.0, dcam);
	float pulse = pow(max(sin(uw_time * (0.35 + rndv * 0.3) + rndv * 61.0), 0.0), 12.0);
	c += vec3(0.12, 0.8, 0.95) * 2.4 * deep * near * pulse * step(0.86, fract(rndv * 13.7));
	ALBEDO = c * a;
}
