// NADIR - thin ship steel (ladder rungs and stringers, cables, falls, rails): ship_metal plus the rope's coverage
// trick. Below ~1.3 px the cross-section is inflated so the part never breaks into crawling dots, and its
// brightness is scaled by the true coverage of that width, so far away it reads as a dim thread, not a bright
// wire. The long axis must be the mesh's local Y (cylinders / boxes); base_r = mesh radius (scaled per instance).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 c_base : source_color = vec3(0.231, 0.165, 0.133);
uniform vec3 c_rust : source_color = vec3(0.33, 0.24, 0.19);
uniform vec3 c_barn : source_color = vec3(0.45, 0.42, 0.33);
uniform float crust = 0.08;
uniform float rust_amt = 0.3;
uniform float gain = 1.15;
uniform float base_r = 0.05;
// presence and water light (ShipMesh.update_env, every frame)
uniform float fog_density = 0.0175;
uniform vec4 fog_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float presence = 1.0;
uniform float wl_on = 0.0;
global uniform float g_depth;
// path-length colour absorption (torch -> surface -> eye), same law as hull.gdshader
global uniform vec3 g_torch_pos;
global uniform float g_torch;

varying vec3 np;
varying float cover;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x);
	float b = mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x);
	float c = mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x);
	float d = mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

// WATER LIGHT CONTRACT
float wl_grad(float depth) {
	return 1.0 - smoothstep(150.0, 330.0, depth);
}
vec3 wl_ratio(vec3 d, float depth) {
	float dn = smoothstep(0.0, 0.95, -d.y);
	dn = dn * dn * (3.0 - 2.0 * dn);
	vec3 r = mix(vec3(1.0), vec3(0.30, 0.36, 0.48), dn) * (1.0 + 0.35 * smoothstep(0.0, 0.66, d.y));
	return mix(vec3(1.0), r, wl_grad(depth));
}

// water eats the red first (hull.gdshader): 52 m path = the wall at 26 m stays as is; FOG is untouched
vec3 absorb(vec3 vtx, mat4 inv_view) {
	vec3 wp = (inv_view * vec4(vtx, 1.0)).xyz;
	float path = length(vtx) + length(wp - g_torch_pos);
	vec3 ab = clamp(exp(-vec3(0.020, 0.008, 0.005) * (path - 52.0)), vec3(0.0), vec3(1.25));
	return mix(vec3(1.0), ab, clamp(g_torch, 0.0, 1.0));
}

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz - NODE_POSITION_WORLD;
	np = VERTEX + inst * 0.37;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float r = base_r * length(MODEL_MATRIX[0].xyz);
	float k = max(1.0, length(wp - CAMERA_POSITION_WORLD) * 0.0011 / max(r, 1e-4));
	VERTEX.xz *= k;
	cover = 1.0 / k;
}

void fragment() {
	float n1 = vnoise3(np * 1.3);
	float n2 = vnoise3(np * 4.1 + 7.0);
	float r = smoothstep(0.35, 0.85, n1 * 0.7 + n2 * 0.3) * rust_amt;
	vec3 col = mix(c_base * (0.8 + 0.4 * n2), c_rust * (0.7 + 0.5 * n2), r);
	float bn = vnoise3(np * 0.6 + 3.0) * 0.55 + vnoise3(np * 2.2 + 9.0) * 0.3 + vnoise3(np * 7.5) * 0.15;
	bn = 0.5 + (bn - 0.5) * 1.5;
	float b = smoothstep(1.0 - crust, 1.0 - crust * 0.4, bn) * step(0.01, crust);
	col *= gain * 3.5;
	col = mix(col, c_barn * 0.95 * (0.45 + 0.6 * n2), b * 0.7);
	ALBEDO = col * max(cover, 0.08) * absorb(VERTEX, INV_VIEW_MATRIX);
	ROUGHNESS = mix(0.62, 0.9, max(r, b));
	SPECULAR = 0.35 * cover;
	METALLIC = 0.0;

	vec3 dw = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
	float fa = 1.0 - exp(-fog_density * length(VERTEX));
	vec3 wr = mix(vec3(1.0), wl_ratio(dw, g_depth), wl_on);
	FOG = vec4(fog_col.rgb * wr / mix(vec3(1.0), wr, fa), max(fa, 1.0 - presence));
}
