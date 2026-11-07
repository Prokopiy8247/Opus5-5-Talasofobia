shader_type particles;
// The Bloop's bioluminescent shear wake (world space). Dinoflagellates fire where the fins, the flukes and the
// tail stock shear the water: each emission picks one of 8 body points (Beat05 fills em[] every frame from the
// Bloop's CPU replica, so they follow the tail wave) by weight, and is left behind in the water, drifting with
// the current. Emission is gated per particle (ACTIVE = false), so a zero weight sum emits nothing.
// CUSTOM: x flash-rate seed, y age (s), z flash-phase seed, w emitter class (0 fluke, 1 fin, 2 flank).
uniform vec3 em[8];
uniform float em_w[8];
uniform float w_max = 4.0;       // weight sum at full strength: the spawn probability is sum / w_max
uniform float spread = 6.0;      // m, radius of the spawn ball around each point
uniform vec3 drift = vec3(0.0);  // world current (m/s), G.flow

float hash(uint x) {
	x ^= x >> 16u; x *= 0x7feb352du; x ^= x >> 15u; x *= 0x846ca68bu; x ^= x >> 16u;
	return float(x) / 4294967295.0;
}

void start() {
	uint s = NUMBER * 2654435761u + INDEX * 97u + 13u;
	float wsum = 0.0;
	for (int i = 0; i < 8; i++) {
		wsum += max(em_w[i], 0.0);
	}
	TRANSFORM = mat4(1.0);
	VELOCITY = vec3(0.0);
	CUSTOM = vec4(0.0);
	if (wsum < 1e-4 || hash(s) > wsum / w_max) {
		ACTIVE = false;
	} else {
		float pick = hash(s + 1u) * wsum;
		int k = 7;
		float acc = 0.0;
		for (int i = 0; i < 8; i++) {
			acc += max(em_w[i], 0.0);
			if (pick <= acc) {
				k = i;
				break;
			}
		}
		vec3 dir = normalize(vec3(hash(s + 2u), hash(s + 3u), hash(s + 4u)) * 2.0 - 1.0 + vec3(1e-4));
		float rad = spread * pow(hash(s + 5u), 0.3333);
		TRANSFORM[3].xyz = em[k] + dir * rad;
		VELOCITY = dir * (0.15 + 0.45 * hash(s + 6u));   // the shed eddy spreads, then settles
		float cls = k < 2 ? 0.0 : (k < 4 ? 1.0 : 2.0);
		CUSTOM = vec4(hash(s + 7u), 0.0, hash(s + 8u), cls);
	}
}

void process() {
	CUSTOM.y += DELTA;
	vec3 p = TRANSFORM[3].xyz + (VELOCITY * exp(-CUSTOM.y / 2.5) + drift) * DELTA;
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = p;
}
