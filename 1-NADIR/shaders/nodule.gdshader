shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;
// Manganese nodules and rocks sitting proud of the silt (~40% of each lump above it): near-black knobbly oxide
// with a compact wet glint on the bare flanks toward the torch and a thin dusting of silt on the upward-facing
// tops. A raised silhouette, a paler top, dark flanks and a highlight read as lumps, not as holes (a silt-
// coloured cap with only its dark far rim showing read as a crater).
uniform vec3 nod_col = vec3(0.11, 0.095, 0.08);     // linear albedo
uniform vec3 silt_col = vec3(0.27, 0.26, 0.235);   // linear, matches silt.gdshader
uniform float dust_k = 0.28;                        // how much silt settles on the tops
global uniform vec3 g_torch_pos;
varying vec3 wpos;
varying vec3 wnrm;

// integer lattice hash: exact, so neighbouring cells always agree on a shared corner (no seams)
float hashi(vec3 p) {
	uvec3 q = uvec3(ivec3(floor(p)) + ivec3(65536));
	uint h = (q.x * 1597334677u) ^ (q.y * 3812015801u) ^ (q.z * 2798796415u);
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	h *= 3266489917u;
	h ^= h >> 16u;
	return float(h >> 8u) * (1.0 / 16777216.0);
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hashi(i), hashi(i + vec3(1, 0, 0)), f.x), mix(hashi(i + vec3(0, 1, 0)), hashi(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hashi(i + vec3(0, 0, 1)), hashi(i + vec3(1, 0, 1)), f.x), mix(hashi(i + vec3(0, 1, 1)), hashi(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;   // uniform scale only, so no inverse transpose needed
}

void fragment() {
	float n = vnoise(wpos * 9.0) * 0.6 + vnoise(wpos * 31.0) * 0.4;
	vec3 nod = nod_col * (0.75 + 0.5 * n);
	float up = normalize(wnrm).y;
	float mask = smoothstep(0.55, 0.9, up + (n - 0.5) * 0.25);
	vec3 alb = mix(nod, silt_col * 1.12, mask * dust_k);
	alb *= 1.0 - smoothstep(50.0, 78.0, length(wpos - g_torch_pos));   // same range fade as the silt
	ALBEDO = alb;
	// wet oxide: a compact highlight toward the torch on the bare flanks (a broad sheen greyed the lumps out)
	ROUGHNESS = mix(0.38, 0.95, mask);
	SPECULAR = mix(0.25, 0.1, mask);
}
