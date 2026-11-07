shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// One air bubble: a camera-facing disc lit by the light that actually reaches it (the refracted sun near the
// surface, the torch in the dark), never an even outline:
// - from the side: a faint rim, a bright crescent on the side facing the light and a small catchlight where a
//   sphere would mirror the light (halfway between the eye and the light)
// - from below: the flattened underside mirrors the water light by total internal reflection, so the bubble
//   reads as a bright, silvery, wobbling disc, not a ring
// - shape: an oblate spheroid in WORLD space (flat side down, the process shader's squash), projected for the
//   real view angle (round from below, flattened from the side), with a wobbling outline on big bubbles
// Lit with the shared torch_profile() (plus a little scattered light at arm's length).
// Near the mask a bubble is out of focus: it fades out inside ~0.2 m and defocuses (bigger, dimmer, softer)
// inside 0.4 m, and it never covers more than 0.035 rad of the view, so no soap bubbles or glass marbles.
global uniform vec3 g_torch_pos;
global uniform vec3 g_torch_dir;
global uniform float g_torch;
global uniform float g_daylight;
global uniform vec4 g_water_col;
global uniform float g_time;
uniform float gain = 1.0;
uniform vec3 sun_up = vec3(0.3403, 0.9007, 0.2702); // toward the refracted sun (-WaterEnv.SUN_DIR)
uniform vec4 lobe_cos = vec4(0.9396926, 0.8660254, 0.8290376, 0.7431448);  // cos of Config.TORCH_LOBES angles 1-4
uniform vec4 lobe_exp = vec4(1.0, 1.0, 0.5, 0.5);                           // their spot_angle_attenuation
uniform vec4 lobe_w = vec4(0.3287, 0.1516, 0.2641, 0.2170);                  // their energy weights
uniform vec3 lobe_5 = vec3(0.6156615, 0.6, 0.0437);                          // lobe 5: cos, attenuation, weight

const float QUAD_PAD = 1.08;

varying vec3 wpos;
varying float blur;
varying float vis;
varying float seed;
varying float wob;      // outline wobble amplitude (big bubbles only)
varying float below;    // 1 = seen from below (the silvery underside)
varying vec3 oax;       // xy: screen direction of the world-vertical (short) axis, z: projected axis ratio
varying vec2 lgt;       // screen direction toward the light (length = how side-on)
varying vec2 hl;        // catchlight position on the disc (view xy of the half vector)

// --- TORCH PROFILE CONTRACT: the same function in beam_haze, snow_draw and bubble_draw (see beam_haze).
float torch_profile(float c, float d) {
	vec4 rim = clamp((1.0 - c) / (1.0 - lobe_cos), vec4(0.0001), vec4(1.0));
	float rim5 = clamp((1.0 - c) / (1.0 - lobe_5.x), 0.0001, 1.0);
	return dot(lobe_w, vec4(1.0) - pow(rim, lobe_exp)) + lobe_5.z * (1.0 - pow(rim5, lobe_5.y));
}

void vertex() {
	wpos = MODEL_MATRIX[3].xyz;
	seed = INSTANCE_CUSTOM.y;
	vec2 scl = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	float obl = clamp(scl.y / max(scl.x, 1e-6), 0.3, 1.0);   // world-space squash (process shader)
	wob = 0.06 * smoothstep(0.003, 0.008, scl.x);
	vec3 rel = wpos - CAMERA_POSITION_WORLD;
	float dist = length(rel);
	below = smoothstep(0.2, 0.8, rel.y / max(dist, 1e-4));
	float rad = scl.x * min(1.0, 0.035 * dist / max(scl.x, 1e-5));   // projected radius <= 0.035 rad
	blur = smoothstep(0.4, 0.12, dist);
	float sb = rad + blur * 0.012;                       // defocus: the disc grows ...
	vis = (rad * rad) / (sb * sb)                        // ... and its energy spreads
		* smoothstep(0.12, 0.3, dist)                    // gone right at the mask
		* smoothstep(0.0, 0.12, INSTANCE_CUSTOM.z);      // fades in after leaving the regulator
	// the oblate spheroid seen at the real angle: round from straight below, flattest from the side
	vec3 upv = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	float s2 = clamp(dot(upv.xy, upv.xy), 0.0, 1.0);
	oax = vec3(normalize(upv.xy + vec2(0.0, 1e-4)), sqrt(1.0 - s2 + obl * obl * s2));
	// light direction in the view: the sun from above by day, the torch in the dark
	vec3 vc = (VIEW_MATRIX * vec4(wpos, 1.0)).xyz;
	vec3 ls = (VIEW_MATRIX * vec4(sun_up, 0.0)).xyz;
	vec3 lt = normalize((VIEW_MATRIX * vec4(g_torch_pos - wpos, 0.0)).xyz + vec3(0.0, 0.0, 1e-4));
	vec3 lv = normalize(mix(ls, lt, clamp(g_torch * 4.0, 0.0, 1.0)) + vec3(0.0, 0.0, 1e-4));
	lgt = lv.xy;
	hl = normalize(normalize(-vc) + lv + vec3(0.0, 0.0, 1e-3)).xy * 0.85;
	float qs = sb * 2.0 * QUAD_PAD;                      // room for the wobble, so no straight quad edge
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * qs, INV_VIEW_MATRIX[1] * qs,
		INV_VIEW_MATRIX[2] * qs, vec4(wpos, 1.0));
}

void fragment() {
	vec2 uv = (UV * 2.0 - 1.0) * QUAD_PAD;   // uv.y = -1 at the top of the view; |uv| = 1 is the bubble edge
	if (vis < 0.002) {
		discard;
	}
	// into the bubble's frame: the world-vertical axis on screen is squashed by the projected ratio
	vec2 au = vec2(oax.x, -oax.y);
	vec2 bu = vec2(dot(uv, vec2(au.y, -au.x)), dot(uv, au) / oax.z);
	float r = length(bu);
	// a living, not a drawn, outline: two slow shape modes, so it never settles into a clean ellipse or triangle
	float ang = atan(bu.y, bu.x);
	r *= 1.0 + wob * (0.6 * sin(ang * 2.0 + g_time * 7.0 + seed * 23.0)
		+ 0.5 * sin(ang * 3.0 + g_time * 9.0 + seed * 37.0));
	if (r > 1.0) {
		discard;
	}
	float aa = fwidth(r) * 1.5 + blur * 0.5;
	float disc = 1.0 - smoothstep(1.0 - aa, 1.0, r);
	float rim = smoothstep(0.78 - 0.4 * blur, 0.98, r) * disc * (1.0 - 0.7 * blur);   // out of focus: no edge
	vec2 lu = vec2(lgt.x, -lgt.y);
	float side = smoothstep(0.05, 0.35, length(lu));     // a light straight behind/ahead gives no crescent
	float crescent = rim * side * smoothstep(0.2, 0.9, dot(normalize(uv + vec2(1e-4)), normalize(lu + vec2(1e-4))));
	vec2 cl = uv - vec2(hl.x, -hl.y);
	float catchl = exp(-dot(cl, cl) / 0.02) * disc;
	vec3 L = wpos - g_torch_pos;
	float d = max(length(L), 0.05);
	float torch = g_torch * (0.03 + torch_profile(dot(L / d, g_torch_dir), d)) * 2.2 / (1.0 + d * d * 0.8);
	vec3 day = mix(vec3(0.75, 0.95, 1.0), g_water_col.rgb * 4.0, 0.25) * g_daylight * 1.4;
	vec3 lit = day + vec3(0.85, 0.93, 1.0) * torch;
	float fill = 0.02 + 0.30 * below * mix(0.7 + 0.3 * r * r, 1.0, blur);   // the silvery TIR underside
	ALBEDO = min(lit * (rim * 0.12 + crescent * 0.8 + catchl * 0.45 + disc * fill) * gain * vis, vec3(1.2));
}
