shader_type particles;
// Marine snow being drawn into the Bloop's maw. Local (body-frame, metres) coordinates of the Bloop root.
// Motes first fill the volume in front of the gape; afterwards they respawn only on the far slab (never within
// keep_out of the camera, so nothing appears at the lens), stream toward the gape, then down the throat, where
// they respawn. Every point follows the head turn (same pivot and rotation order as bloop.gdshader).
// CUSTOM: x speed/size seed, y twinkle rate, z twinkle phase (read by snow_draw), w respawn counter.
uniform vec3 throat = vec3(56.0, -2.5, 0.0);
uniform vec3 mouth = vec3(124.0, -18.0, 0.0);
uniform vec3 gape = vec3(0.0, 24.0, 30.0);    // each mote aims at its own point across the open gape (m)...
uniform vec3 gullet = vec3(0.0, 8.0, 10.0);   // ...and down the throat, so the stream never pinches to a point
uniform vec3 box_min = vec3(128.0, -60.0, -60.0);
uniform vec3 box_max = vec3(250.0, 30.0, 60.0);
uniform float slab_x = 225.0;               // respawns use x in [slab_x, box_max.x]
uniform vec3 pivot = vec3(40.0, 0.0, 0.0);  // head pivot, metres
uniform float head_yaw = 0.0;               // radians, Bloop.head_angles()
uniform float head_pitch = 0.0;
uniform vec3 cam_local = vec3(0.0, 100000.0, 0.0);   // camera in this frame, set every frame
uniform float keep_out = 35.0;
uniform float pull = 1.0;   // 0..1 strength of the current

float hash(uint x) {
	x ^= x >> 16u; x *= 0x7feb352du; x ^= x >> 15u; x *= 0x846ca68bu; x ^= x >> 16u;
	return float(x) / 4294967295.0;
}

vec2 rot2(vec2 v, float a) {
	float c = cos(a), s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// body frame -> head-turned frame: pitch on xy, then yaw on xz, about the pivot
vec3 head(vec3 p) {
	vec3 h = p - pivot;
	h.xy = rot2(h.xy, head_pitch);
	h.xz = rot2(h.xz, head_yaw);
	return pivot + h;
}

vec3 spawn(uint s, vec3 lo, vec3 hi) {
	vec3 r = vec3(hash(s), hash(s + 1u), hash(s + 2u));
	vec3 p = head(mix(lo, hi, r));
	vec3 dv = p - cam_local;
	if (length(dv) < keep_out) {
		p = cam_local + normalize(dv + vec3(1e-3)) * keep_out;
	}
	return p;
}

void start() {
	uint s = INDEX * 7u + 3u;
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = spawn(s, box_min, box_max);
	CUSTOM = vec4(hash(s + 5u), hash(s + 6u), hash(s + 7u), 0.0);
	VELOCITY = vec3(0.0);
}

void process() {
	vec3 p = TRANSFORM[3].xyz;
	vec3 off = vec3(0.0, CUSTOM.y - 0.5, CUSTOM.z - 0.5);
	vec3 th = head(throat + off * gullet);
	vec3 mo = head(mouth + off * gape);
	// through the gape first (aim at the mouth until close to it or inside the throat cone), then down the throat
	vec3 dm = p - mo;
	bool in_mouth = length(dm) < 12.0 || dot(dm, normalize(th - mo)) > 0.5 * length(dm);
	vec3 to = (in_mouth ? th : mo) - p;
	float dl = length(to);
	float d = distance(p, th);
	float spd = pull * mix(9.0, 2.2, clamp(d / 170.0, 0.0, 1.0)) * (0.7 + 0.6 * CUSTOM.x);
	vec3 v = to / max(dl, 0.001) * spd;
	p += v * DELTA;
	if (d < 10.0) {
		CUSTOM.w += 1.0;
		p = spawn(INDEX * 7u + 3u + uint(CUSTOM.w) * 131u, vec3(slab_x, box_min.y, box_min.z), box_max);
	}
	float sz = mix(0.03, 0.09, CUSTOM.x * CUSTOM.x);
	TRANSFORM = mat4(vec4(sz, 0.0, 0.0, 0.0), vec4(0.0, sz, 0.0, 0.0), vec4(0.0, 0.0, sz, 0.0), vec4(p, 1.0));
	VELOCITY = v;
}
