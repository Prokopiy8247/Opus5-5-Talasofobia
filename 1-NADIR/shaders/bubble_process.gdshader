shader_type particles;
// Exhaled regulator bubbles: born at the left/right exhaust of the regulator (emitter = the diver's mouth),
// they burst sideways, then rise with a size-dependent speed and a zig-zag wobble. World-space particles.

uniform float side_offset = 0.11;

float hash(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 0x7fffffffu) / float(0x7fffffff);
}

void start() {
	uint s = NUMBER * 7u + RANDOM_SEED;
	float side = (NUMBER % 2u == 0u) ? 1.0 : -1.0;
	vec3 jit = vec3(hash(s), hash(s + 1u), hash(s + 2u)) - 0.5;
	if (RESTART_POSITION) {
		vec3 xs = normalize(EMISSION_TRANSFORM[0].xyz);
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = EMISSION_TRANSFORM[3].xyz + xs * side * side_offset + jit * 0.04;
	}
	float r = hash(s + 3u);
	float size = mix(0.0025, 0.016, r * r * r);         // bubble radius, m (a few big, many small)
	CUSTOM = vec4(size, hash(s + 4u) * 6.2831, 0.0, side);
	if (RESTART_VELOCITY) {
		vec3 xs = normalize(EMISSION_TRANSFORM[0].xyz);
		VELOCITY = xs * side * (0.25 + 0.35 * hash(s + 5u)) + jit * 0.2;
	}
}

void process() {
	float size = CUSTOM.x;
	CUSTOM.z += DELTA;
	float age = CUSTOM.z;
	float rise = 0.32 + size * 42.0;                     // larger bubbles rise faster
	float w = CUSTOM.y + age * mix(11.0, 6.0, size / 0.016);
	vec3 wob = vec3(cos(w), 0.0, sin(w * 1.3)) * (0.06 + size * 4.0);
	vec3 target = vec3(0.0, rise, 0.0) + wob;
	VELOCITY = mix(target, VELOCITY, exp(-DELTA * 3.5));  // the sideways burst dies quickly
	float grow = 1.0 + age * 0.04;                       // they expand slowly as they rise
	// small bubbles stay nearly round; above ~4 mm they flatten and wobble (oblate spheroids)
	float sq = mix(0.92 + 0.04 * sin(w * 2.0), 0.7 + 0.12 * sin(age * 9.0 + CUSTOM.y * 37.0),
		smoothstep(0.0035, 0.0045, size));
	TRANSFORM[0].xyz = vec3(size * grow, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, size * grow * sq, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, size * grow);
}
