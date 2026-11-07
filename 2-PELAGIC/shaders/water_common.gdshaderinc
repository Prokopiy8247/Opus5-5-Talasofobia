// Shared underwater helpers. Keep WATER_K equal to Config.WATER_K.
global uniform vec3 water_cam_pos;
global uniform vec3 water_sun_dir;      // towards the (refracted) sun
global uniform float water_light_scale;
global uniform float water_fog_density;
global uniform float water_shaft_amount;
#include "res://shaders/water_backdrop.gdshaderinc"

const vec3 WATER_K = vec3(0.0048, 0.0021, 0.0010);

vec3 water_trans(float depth) {
	return exp(-WATER_K * max(depth, 0.0));
}

// Sunlight reaching a world height, relative to the light at the camera depth
// (the DirectionalLight colour already carries the camera-depth tint).
vec3 water_rel_light(float world_y) {
	vec3 a = water_trans(-world_y);
	vec3 b = water_trans(-water_cam_pos.y);
	// things far below the diver sink into darkness (so a body deep below reads as a dark line)
	vec3 below = exp(-vec3(0.0040, 0.0028, 0.0022) * max(water_cam_pos.y - world_y - 40.0, 0.0));
	return clamp(a / max(b, vec3(0.03)), vec3(0.0), vec3(1.6)) * below;
}

float water_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float water_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(water_hash(i), water_hash(i + vec2(1.0, 0.0)), u.x),
		mix(water_hash(i + vec2(0.0, 1.0)), water_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// 0..1 scale for specular/clearcoat of things far below the diver (their reflections of the bright shallow sky
// would otherwise make them glow lighter than the water around them).
float water_spec_dim(float world_y) {
	vec3 rl = water_rel_light(world_y);
	return clamp(dot(rl, vec3(0.2, 0.6, 0.2)), 0.0, 1.0);
}

// Cheap animated caustic network (0..1), p in metres on a plane facing the sun.
float water_caustic(vec2 p, float t) {
	vec2 q = p * 0.42;
	float c = 0.0;
	for (int i = 0; i < 3; i++) {
		vec2 o = vec2(sin(t * 0.31 + float(i) * 2.1), cos(t * 0.27 + float(i) * 1.7)) * 0.6;
		float n = water_noise(q * (1.0 + float(i) * 0.63) + o + vec2(t * 0.05 * float(i + 1), 0.0));
		c += pow(1.0 - abs(n * 2.0 - 1.0), 6.0);
	}
	return clamp(c * 0.55, 0.0, 1.0);
}

// Per-fragment fog for every custom spatial shader: write  FOG = water_fog(world_position);
// (Godot's own aerial perspective samples a blurred radiance mip that is brighter than the deep backdrop.)
// The fog colour is the far water in that direction, but an object in front of the light hides what lies behind
// it: the sun disc and the painted ray fans are images of the far light, so a near object never carries them (they
// return only as it melts completely into the sky), and the glow around the sun is mostly in-scatter of the far
// water (a near occluder keeps a fifth of it). So the boat hull, a school or the lip rim in front of the sun stay
// dark silhouettes, while a fully fogged far fragment still equals the sky behind it exactly (no pop when hidden).
vec4 water_fog(vec3 wp) {
	vec3 rel = wp - water_cam_pos;
	float dist = length(rel);
	float a = 1.0 - exp(-water_fog_density * dist);
	float far_w = smoothstep(0.5, 0.95, a);
	vec3 w = vec3(smoothstep(0.85, 1.0, a), mix(0.2, 1.0, far_w), far_w);
	vec3 col = wb_sky_w(rel / max(dist, 0.001), -water_cam_pos.y, water_shaft_amount, normalize(water_sun_dir), TIME, w);
	return vec4(col, a);
}
