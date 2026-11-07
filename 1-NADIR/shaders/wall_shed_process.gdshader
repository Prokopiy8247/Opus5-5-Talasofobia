shader_type particles;
// Rust flakes and silt shed by the sinking hull (beat 3): born in a thin layer on the side wall around the
// camera's design depth (a triangular band, so it has no edge), they drift off the steel and sink more slowly
// than the hull (0.12 m/s), so they rise past the plating in the beam. World-space particles, continuous.
// CUSTOM = (kind/size rand, tumble rate, tumble phase, age) for rust_draw (CUSTOM.x > 0.5: grey silt).
uniform float cam_dd = 500.0;                               // design depth level with the camera
uniform vec4 wall = vec4(26.0, 525.0, 2700.0, 0.0);         // WALL_A, WALL_D0, WALL_K, sink (world = design + sink)
uniform float cam_x = 0.0;

float hash(uint x) {
	x ^= x >> 16u; x *= 0x7feb352du; x ^= x >> 15u; x *= 0x846ca68bu; x ^= x >> 16u;
	return float(x) / 4294967295.0;
}

float wall_z(float d) {
	return wall.x + (d - wall.y) * (d - wall.y) / wall.z;
}

void start() {
	uint s = INDEX * 11u + RANDOM_SEED * 173u + 29u;
	float depth = cam_dd + 28.0 * (hash(s) + hash(s + 1u) - 1.0);
	float x = cam_x + (hash(s + 2u) - 0.5) * 44.0;
	float z = wall_z(depth) - 0.2 - 1.0 * hash(s + 3u);
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = vec3(x, -(depth + wall.w), z);
	CUSTOM = vec4(hash(s + 4u), hash(s + 5u), hash(s + 6u), 0.0);
	float hv = hash(s + 7u);
	VELOCITY = vec3(0.0, -0.02 - 0.05 * hv, -0.01 - 0.03 * hv);
}

void process() {
	CUSTOM.w += DELTA;
	float age = CUSTOM.w;
	float ph = CUSTOM.z * 6.2831;
	float hv = fract(CUSTOM.y * 7.31);
	vec3 wob = vec3(sin(age * 0.9 + ph), 0.0, cos(age * 0.7 + ph * 1.7)) * (0.02 + 0.04 * CUSTOM.y);
	vec3 target = vec3(0.0, -0.02 - 0.05 * hv, -0.01 - 0.03 * hv) + wob;
	VELOCITY = mix(target, VELOCITY, exp(-DELTA * 0.5));
	float k = fract(CUSTOM.x * 2.0);
	float sz = mix(0.012, 0.04, k * k);
	TRANSFORM[0].xyz = vec3(sz, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, sz, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, sz);
}
