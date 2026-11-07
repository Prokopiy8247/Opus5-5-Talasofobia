shader_type particles;
// Rust flakes and silt shaken loose when the ship settles (beat 4, one shot). They rain THROUGH the diver:
// 80% are born in a 13 m column around the camera, between the steel and ~8 m below the camera, most of them
// near the diver (the
// column follows the diver, so later-born flakes keep falling around him), 20% are born 0.5-2 m under the steel
// above that disc (the bilge arc or the flat bottom, from the hull profile). Then they sink slowly with a little
// wobble. World-space particles. CUSTOM = (size rand, tumble rate, tumble phase, age) for rust_draw.
uniform vec4 arc = vec4(84.0, 743.0, 40.0, 44.75);   // bilge arc centre z, centre depth (+ sink), radius, z where the arc starts
uniform vec4 spawn_rect = vec4(0.0, 47.0, 13.0, 0.0);  // column centre x, centre z, radius
uniform float cam_y = -800.0;                          // camera world y (Beat04 sets it every frame)

float hash(uint x) {
	x ^= x >> 16u; x *= 0x7feb352du; x ^= x >> 15u; x *= 0x846ca68bu; x ^= x >> 16u;
	return float(x) / 4294967295.0;
}

// world depth of the steel above (x, z): the bilge arc, the flat bottom beyond it, the arc start before it
float steel_depth(float z) {
	float dz = arc.x - z;
	return dz > 0.0 ? arc.y + sqrt(max(arc.z * arc.z - dz * dz, 0.0)) : arc.y + arc.z;
}

void start() {
	uint s = INDEX * 7u + RANDOM_SEED * 131u + 17u;
	float a = hash(s + 8u) * 6.2831;
	float rr = spawn_rect.z * sqrt(hash(s));
	float x = spawn_rect.x + rr * cos(a);
	float z = spawn_rect.y + rr * sin(a);
	float y;
	if (hash(s + 6u) < 0.8) {
		// the column through the diver: from just under the steel down to 8 m below the camera
		float sy = -steel_depth(max(z, arc.w)) - 0.5;
		y = min(mix(sy, cam_y - 8.0, pow(hash(s + 7u), 0.4)), sy);
	} else {
		// just under the steel (the side wall is far above: fold those under the turn of the bilge)
		float zs = z < arc.w ? arc.w + (arc.w - z) * 0.6 : z;
		y = -steel_depth(zs) - 0.5 - 1.5 * hash(s + 2u);
		z = zs;
	}
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = vec3(x, y, z);
	VELOCITY = vec3(0.0, -0.15, 0.0);
	CUSTOM = vec4(hash(s + 3u), hash(s + 4u), hash(s + 5u), 0.0);
}

void process() {
	CUSTOM.w += DELTA;
	float age = CUSTOM.w;
	float ph = CUSTOM.z * 6.2831;
	vec3 wob = vec3(sin(age * 1.3 + ph), 0.0, cos(age * 1.1 + ph * 1.7)) * (0.05 + 0.1 * CUSTOM.y);
	vec3 target = vec3(0.0, -0.55 - 0.4 * CUSTOM.x, 0.0) + wob;
	VELOCITY = mix(target, VELOCITY, exp(-DELTA * 0.8));
	float sz = mix(0.01, 0.036, CUSTOM.x * CUSTOM.x);
	TRANSFORM[0].xyz = vec3(sz, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, sz, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, sz);
}
