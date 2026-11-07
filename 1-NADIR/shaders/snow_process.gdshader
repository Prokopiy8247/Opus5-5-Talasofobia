shader_type particles;
// Deterministic wrapped motes around the camera: no emission bias, no popping (draw shader fades the box edge).
uniform float box = 40.0;
uniform float turb = 0.0;          // slow eddies (MarineSnow.set_turbulence, eased by the caller); stateless
global uniform vec3 g_cam_pos;
global uniform vec3 g_flow;
global uniform float g_time;

float hash(uint x) {
	x ^= x >> 16u; x *= 0x7feb352du; x ^= x >> 15u; x *= 0x846ca68bu; x ^= x >> 16u;
	return float(x) / 4294967295.0;
}

void start() {
	uint s = INDEX * 5u + 11u;
	CUSTOM = vec4(hash(s), hash(s + 1u), hash(s + 2u), hash(s + 3u));
	TRANSFORM = mat4(1.0);
	VELOCITY = vec3(0.0);
}

void process() {
	float ph = CUSTOM.w * 6.2831;
	vec3 base = CUSTOM.xyz * box;
	vec3 wob = vec3(sin(g_time * 0.31 + ph), 0.6 * sin(g_time * 0.23 + ph * 1.7), cos(g_time * 0.27 + ph * 2.3)) * 0.4;
	vec3 sink = vec3(0.0, -0.05 - 0.04 * CUSTOM.w, 0.0) * g_time;
	vec3 p = base + g_flow * (0.85 + 0.3 * CUSTOM.w) + sink + wob;
	if (turb > 0.0) {
		vec3 q = base * 0.11;
		p += turb * 2.5 * vec3(sin(q.y * 2.1 + g_time * 0.9 + ph), sin(q.z * 1.7 + g_time * 0.7),
			sin(q.x * 1.9 + g_time * 0.8 + ph * 1.3));
	}
	p = mod(p - g_cam_pos + box * 0.5, box) - box * 0.5 + g_cam_pos;
	float r = hash(INDEX * 7u + 3u);
	float sz = mix(0.010, 0.045, r * r * r);
	TRANSFORM = mat4(vec4(sz, 0.0, 0.0, 0.0), vec4(0.0, sz, 0.0, 0.0), vec4(0.0, 0.0, sz, 0.0), vec4(p, 1.0));
	VELOCITY = vec3(0.0);
}
