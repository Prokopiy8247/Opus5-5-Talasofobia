shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// Ropes and lines (any transform). Far away the tube is widened so it never gets thinner than a floor width on
// screen (no shimmer), and its colour is blended into the fog by the coverage ratio (thin_exp).
//   min_px = 0 (default): the old floor, a fixed angle (about 1.4 px at 720p, 2.1 px at 1080p), thin_exp 0.6:
//            rigging, rails, warps keep their look.
//   min_px > 0: a floor in pixels of the frame height at 1080p (scaled with the viewport, so 720p and 1080p
//            read the same); the guide line uses it with a low thin_exp so the far line stays one continuous
//            rope that the fog fades, instead of a hair that every bend turns into a hairpin.
// fade_far (start, end metres, 0 = off): the tube shrinks to nothing with distance (and fogs a little on the
// way): the line's stays show only near the camera, where their weights can be seen; far away they bunched
// under the foreshortened line like the legs of a wire tripod. (A full fog alpha would still draw the fog
// colour over the nearer slope behind them.)
// deep_glow: a faint self-light in the dark (the pale line keeps a dim presence past the lamp's reach).
#include "res://shaders/inc/uw.gdshaderinc"

uniform float radius = 0.025;
uniform vec3 rope_color : source_color = vec3(0.78, 0.72, 0.5);
uniform float min_px = 0.0;
uniform float thin_exp = 0.6;
uniform vec2 fade_far = vec2(0.0, 0.0);
uniform float deep_glow = 0.0;

varying vec3 wpos;
varying vec3 wnrm;
varying float thin;
varying float gone;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(wp - uw_cam_pos);
	float r_min = dist * 0.0012;
	if (min_px > 0.0 && PROJECTION_MATRIX[3][3] < 0.5) {      // not in an orthographic (sun shadow) pass
		// half the floor width in metres: px * (2 d / (P11 height)) / 2, with px scaled from 1080p
		float px = min_px * VIEWPORT_SIZE.y / 1080.0;
		r_min = px * dist / max(abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y, 1.0);    // [1][1] < 0 when Y is flipped
	}
	float r_eff = max(radius, r_min);
	thin = radius / r_eff;
	gone = 0.0;
	if (fade_far.y > fade_far.x) {
		gone = smoothstep(fade_far.x, fade_far.y, dist);
		r_eff *= 1.0 - gone;
	}
	VERTEX += normalize(NORMAL) * (r_eff - radius);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float tw = fract(UV.x * 9.0 + UV.y * 3.0);
	float strand = smoothstep(0.0, 0.25, tw) * smoothstep(1.0, 0.6, tw);
	vec3 col = rope_color * (0.7 + 0.3 * strand);
	float grime = uw_vnoise2(vec2(UV.x * 0.2, 0.0));
	col = mix(col, pal_moss * 0.8, smoothstep(0.55, 0.9, grime) * 0.6);
	// deeper down the line is silted and dull: still a guide, no longer a neon thread
	float deep = smoothstep(-250.0, -750.0, wpos.y);
	col = mix(col, pal_bone * 0.45, 0.45 * deep) * mix(1.0, 0.6, deep);
	ALBEDO = col * uw_albedo_light(wpos.y);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	vec3 vw = normalize(CAMERA_POSITION_WORLD - wpos);
	EMISSION = (uw_ambient_glow(wnrm, vw, wpos.y) + col * 0.02) * mix(1.0, 0.6, deep);
	EMISSION += col * deep_glow * (1.0 - uw_light(wpos.y));
	vec4 f = uw_fog_eval(CAMERA_POSITION_WORLD, wpos);
	f.a = 1.0 - (1.0 - f.a) * pow(thin, thin_exp);    // a receding line stays a continuous line a little longer
	f.a = mix(f.a, 1.0, gone * 0.5);
	FOG = f;
}
