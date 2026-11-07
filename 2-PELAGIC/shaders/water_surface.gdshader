shader_type spatial;
// The surface seen from below: the sky refracted through Snell's window (Fresnel edge wobbling with the waves,
// sun glitter), total internal reflection of the deep water outside it. Detail dissolves into the backdrop with depth.
// The window is the brightest thing overhead (HDR, so the glow blooms); the mirror around it reflects the dark
// depths, so the window reads as a hole of light in a dark ceiling.
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://shaders/water_common.gdshaderinc"

uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_air = vec3(0.287, 0.866, 0.41);   // sun direction above the water (towards the light)
uniform vec4 sky_zenith : source_color = vec4(0.36, 0.62, 0.92, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.70, 0.87, 0.98, 1.0);
uniform vec4 sun_col : source_color = vec4(1.0, 0.957, 0.863, 1.0);
uniform float energy = 2.2;          // HDR: the window crosses the glow threshold (1.15) and blooms
uniform float wave_slope = 0.42;
uniform float detail_depth = 55.0;   // e-folding depth of the window detail
uniform float mirror_gain = 0.4;     // total internal reflection of the dark water below
uniform float rim_gain = 0.35;       // thin bright ring just inside the critical angle

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 rel = wpos - water_cam_pos;
	float dist = length(rel);
	vec3 view = rel / max(dist, 0.001);                        // from the eye up to the surface
	float d = max(-water_cam_pos.y, 0.0);
	vec2 p = wpos.xz;
	vec3 na = texture(wave_a, p * 0.031 + TIME * vec2(0.013, 0.008)).xyz * 2.0 - 1.0;
	vec3 nb = texture(wave_b, p * 0.083 + TIME * vec2(-0.011, 0.017)).xyz * 2.0 - 1.0;
	vec3 nc = texture(wave_b, p * 0.19 + TIME * vec2(0.02, -0.013)).xyz * 2.0 - 1.0;
	vec2 slope = (na.xy * 0.55 + nb.xy * 0.35 + nc.xy * 0.2) * wave_slope;
	vec3 n = normalize(vec3(slope.x, 1.0, slope.y));           // surface normal (up)
	// water -> air refraction and Fresnel (R -> 1 continuously at the critical angle: total internal reflection)
	const float ETA = 1.333;
	float cos_i = clamp(dot(view, n), 0.0, 1.0);
	float k = 1.0 - ETA * ETA * (1.0 - cos_i * cos_i);
	float cos_t = sqrt(max(k, 0.0));
	float rs = (ETA * cos_i - cos_t) / max(ETA * cos_i + cos_t, 1e-4);
	float rp = (cos_i - ETA * cos_t) / max(cos_i + ETA * cos_t, 1e-4);
	float R = clamp(0.5 * (rs * rs + rp * rp), 0.0, 1.0);
	float T = (1.0 - R) * smoothstep(0.0, 0.2, k);    // soften the very edge (scattering blurs it)
	// sky through the window: zenith to the (brighter) horizon, which lands just inside the rim
	vec3 r_air = normalize(ETA * view + (cos_t - ETA * cos_i) * n);
	vec3 sky = mix(sky_horizon.rgb, sky_zenith.rgb, sqrt(clamp(r_air.y, 0.0, 1.0)));
	float cs = max(dot(r_air, normalize(sun_air)), 0.0);
	float glint_fade = 1.0 - smoothstep(25.0, 120.0, dist);   // far glitter would only alias
	sky += sun_col.rgb * (pow(cs, 1500.0) * 40.0 * glint_fade + pow(cs, 90.0) * 1.6 + pow(cs, 10.0) * 0.22);
	// the waves focus and spread the light coming through: +/-25 %
	float ripple = water_caustic(p * 0.9 + slope * 6.0, TIME * 1.3);
	sky *= 0.75 + 0.5 * ripple;
	// the band next to the edge (the whole horizon squeezed into the last degrees, broken up by the waves) stays below
	// white: it shows sky colour with soft edges instead of clipping into hard white fragments
	float edge_e = mix(0.6, 1.0, smoothstep(0.02, 0.4, k));
	vec3 through = sky * T * water_trans(dist) * energy * edge_e;
	// a thin bright ring where the window ends (the whole horizon squeezed into the edge)
	float rim = smoothstep(0.0, 0.05, k) * (1.0 - smoothstep(0.05, 0.14, k)) * exp(-d / 18.0);
	through += sky_horizon.rgb * rim * rim_gain * energy * (1.0 - R);
	// outside the window: the deep water mirrored by the surface, dark and blue (the dark ring around the window);
	// at grazing angles it mirrors the horizontal water, so the far surface meets the horizon without a seam
	vec3 r_w = reflect(view, n);
	float steep = smoothstep(0.03, 0.35, -r_w.y);
	vec3 mirror = mix(wb_backdrop(r_w, d, 1.0), wb_water_col(d + 200.0), 0.45 * steep) * mix(1.0, mirror_gain, steep) * (0.85 + 0.3 * ripple);
	vec3 col = through + mirror * R;
	col *= mix(1.0, water_light_scale, 0.5);
	// with depth the window, its edge and the glitter dissolve into the soft glow of the far water
	vec3 far = wb_sky(view, d, water_shaft_amount, normalize(water_sun_dir), TIME, 1.0);
	col = mix(far, col, exp(-d / detail_depth) * (1.0 - smoothstep(50.0, 115.0, d)));
	ALBEDO = col;
	// the surface IS the far light overhead (not an occluder in front of it): its fog keeps the full sky, so from
	// mid-depth the visible upper hemisphere is exactly wb_sky (sun glow, last-light spot and rays included)
	FOG = vec4(far, 1.0 - exp(-water_fog_density * dist));
}
