shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// The far trench wall: black rock revealed only by its own lamps; additive, so it never occludes or mismatches
// the backdrop. Two baked layers: small warm pools right around each lamp, and a faint low-frequency body of
// light the whole field throws on the slope (~50 m blur), broken by vertical gullies. Dense clusters show a
// warm-brown rock face behind their lamps, sparse areas stay black: lamps ON a slope, not stars in a void.
// The layers fade out toward the wall's foot and its ends, so the field thins into darkness instead of stopping
// at a straight edge. Custom distance attenuation instead of the exponential fog (which would erase it at ~1 km).
uniform sampler2D pools : filter_linear, repeat_disable;
uniform sampler2D glow : filter_linear, repeat_disable;
uniform vec4 lamp_col : source_color = vec4(1.0, 0.706, 0.353, 1.0);
uniform float reveal_time = -1.0;
uniform float gain = 1.1;
uniform float glow_gain = 0.09;
uniform vec2 glow_size = vec2(256.0, 64.0);

varying vec3 wpos;

// integer lattice hash: exact and associative, so neighbouring cells always agree on a shared corner
float hashi(vec2 p, uint s) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(32768));
	uint h = (q.x * 1597334677u) ^ (q.y * 3812015801u) ^ (s * 2654435761u);
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	return float(h >> 8u) * (1.0 / 16777216.0);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hashi(i, 0u), hashi(i + vec2(1.0, 0.0), 0u), f.x),
		mix(hashi(i + vec2(0.0, 1.0), 0u), hashi(i + vec2(1.0, 1.0), 0u), f.x), f.y);
}

// cubic B-spline sample from 4 bilinear taps: the coarse glow map has no creases at texel borders
vec4 tex_bicubic(sampler2D tex, vec2 uv, vec2 size) {
	vec2 st = uv * size - 0.5;
	vec2 i = floor(st);
	vec2 f = st - i;
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;
	vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
	vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 s0 = w0 + w1;
	vec2 s1 = w2 + w3;
	vec2 c0 = (i - 0.5 + w1 / s0) / size;
	vec2 c1 = (i + 1.5 + w3 / s1) / size;
	return mix(mix(texture(tex, vec2(c1.x, c1.y)), texture(tex, vec2(c0.x, c1.y)), s0.x),
		mix(texture(tex, vec2(c1.x, c0.y)), texture(tex, vec2(c0.x, c0.y)), s0.x), s0.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float pool = min(texture(pools, UV).r, 1.0);
	float rock = 0.45 + 0.55 * vnoise(wpos.zy * 0.05) * vnoise(wpos.zy * 0.21 + 3.1);
	// gullies: spurs ~35 m apart running down the slope catch the glow, the gullies between them stay dark
	float gully = 1.0 - abs(2.0 * vnoise(vec2(wpos.z * 0.028, wpos.y * 0.004)) - 1.0);
	float spur = gully * gully * gully;
	float relief = 0.15 + 0.85 * spur * (0.6 + 0.4 * vnoise(wpos.zy * 0.03)) * (0.55 + 0.45 * vnoise(wpos.zy * 0.05 + 11.0));
	float g = min(tex_bicubic(glow, UV, glow_size).r, 3.0);
	float on = smoothstep(1.5, 11.0, reveal_time);
	float d = length(wpos - CAMERA_POSITION_WORLD);
	float atten = exp(-d * 0.0011);
	float edge = smoothstep(0.02, 0.12, UV.y) * smoothstep(0.0, 0.18, min(UV.x, 1.0 - UV.x));
	ALBEDO = lamp_col.rgb * ((pool * rock * gain + g * relief * glow_gain) * on * atten * edge);
	FOG = vec4(0.0);
}
