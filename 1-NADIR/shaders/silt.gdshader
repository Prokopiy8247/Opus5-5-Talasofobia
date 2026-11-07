shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;
// Abyssal silt: fine pale sediment with soft ripples, darker detritus grains and faint creature trails.
// Ripples are an analytic world-space normal of realistic slope (3 cm, <= ~3.5 deg) that flattens at grazing
// view, so the low torch never turns ripple flanks pitch black (no NORMAL_MAP, so no tangents needed).
// Every noise octave runs on a rotated domain with quintic fade, and the lattice hash is integer (exact and
// associative): a sin() hash fed values ~1e5 hashed a shared cell corner differently from each side, which
// showed as straight-edged tiles in the silt.
uniform bool use_vcol = false;      // near-field patch: vertex colour darkens burrows
global uniform vec3 g_torch_pos;
varying vec3 wpos;

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
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hashi(i, 0u), hashi(i + vec2(1.0, 0.0), 0u), f.x),
		mix(hashi(i + vec2(0.0, 1.0), 0u), hashi(i + vec2(1.0, 1.0), 0u), f.x), f.y);
}
mat2 rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// round dark grains of detritus on a jittered grid (value-noise thresholds made triangular specks)
float grains(vec2 p) {
	vec2 q = rot(0.35) * p * 9.0;
	vec2 qi = floor(q);
	float g = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = qi + vec2(float(i), float(j));
			if (hashi(c, 5u) < 0.8) {
				continue;
			}
			vec2 o = vec2(hashi(c, 1u), hashi(c, 2u));
			float r = mix(0.1, 0.32, hashi(c, 3u));
			float d = length(q - c - o);
			g = max(g, (1.0 - smoothstep(r * 0.45, r, d)) * mix(0.5, 1.0, hashi(c, 4u)));
		}
	}
	float fw = fwidth(q.x) + fwidth(q.y);
	return g * (1.0 - smoothstep(0.25, 0.7, fw));   // fade before the grains alias
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float n = vnoise(rot(0.5) * p * 0.3) * 0.5 + vnoise(rot(1.7) * p * 1.6 + 3.1) * 0.3 + vnoise(rot(2.9) * p * 6.5 + 7.7) * 0.2;
	float warp = vnoise(rot(0.9) * p * 0.15) * 7.0;
	float ph = p.x * 1.9 + p.y * 0.6 + warp;
	float speck = grains(p) * 0.45;
	float trail = smoothstep(0.035, 0.0, abs(vnoise(rot(2.2) * p * 0.08) - 0.5)) * 0.10;
	vec3 base = mix(vec3(0.21, 0.20, 0.18), vec3(0.31, 0.295, 0.265), n);

	vec3 to_cam = CAMERA_POSITION_WORLD - wpos;
	float dist = length(to_cam);
	float fade = 1.0 - smoothstep(20.0, 60.0, dist);
	vec3 nb = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float graze = smoothstep(0.06, 0.3, dot(nb, to_cam / max(dist, 1e-3)));
	float A = 0.03 * fade * graze;
	vec2 g = A * cos(ph) * vec2(1.9, 0.6);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nb + vec3(-g.x, 0.0, -g.y)), 0.0)).xyz);

	vec3 alb = base * (1.0 - speck) * (1.0 - trail) * (1.0 + 0.035 * sin(ph) * fade);
	if (use_vcol) {
		alb *= COLOR.rgb;
	}
	// fade the silt out before the torch's 82 m range window, so the lit floor never ends in a straight cut
	// (from above, the hatch lamp's pool is carried by its fog-attenuated beacon pool, Beat06_Lights)
	alb *= 1.0 - smoothstep(50.0, 78.0, length(wpos - g_torch_pos));
	ALBEDO = alb;
	ROUGHNESS = 0.96;
	SPECULAR = 0.15;
}
