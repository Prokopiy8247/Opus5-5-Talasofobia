shader_type spatial;
// The dive boat seen from below (the first image of the game). kind 0 hull: dark antifouling bottom that goes
// darker towards the keel, a black boot-top stripe at the waterline, orange topsides (above the surface, hidden
// by it); a slime film and olive algae streaks near the waterline; a thin bright meniscus rim where the hull meets
// the surface. kind 1 dark alloy (outboard leg, propeller), kind 2 stainless (swim ladder), kind 3 rusty iron
// (anchor, chain). No emission besides the rim: from below the hull is a silhouette against Snell's window.
// The whole boat rocks gently on the swell (shared world-space motion, so every part moves together).
render_mode cull_back;
#include "res://shaders/water_common.gdshaderinc"

uniform int kind = 0;
uniform vec3 boat_origin = vec3(0.0);       // world pivot of the swell motion (the boat node's position)
uniform vec3 boat_fwd = vec3(0.0, 0.0, -1.0);
uniform float swell = 1.0;                  // 0 = static (the anchor and chain on the reef)

varying vec3 v_w;
varying vec3 v_l;
varying vec3 v_n;

vec3 rock(vec3 w) {
	vec3 r = w - boat_origin;
	vec3 side = normalize(cross(boat_fwd, vec3(0.0, 1.0, 0.0)));
	float roll = 0.018 * sin(TIME * 0.61) + 0.007 * sin(TIME * 1.37 + 0.8);
	float pitch = 0.008 * sin(TIME * 0.43 + 1.1);
	float heave = 0.035 * sin(TIME * 0.52 + 0.4) + 0.012 * sin(TIME * 1.21 + 2.0);
	return boat_origin + r + (cross(boat_fwd, r) * roll + cross(side, r) * pitch + vec3(0.0, heave, 0.0)) * swell;
}

void vertex() {
	v_l = VERTEX;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wr = rock(w);
	// the node transforms are rotation + translation only: the inverse basis is the transpose
	VERTEX += transpose(mat3(MODEL_MATRIX)) * (wr - w);
	v_w = wr;
	v_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = v_n * inversesqrt(max(dot(v_n, v_n), 1e-8));   // guarded: interpolated normals can cancel at a crease
	float y = v_w.y;                              // the surface is at world y = 0
	float hy = v_l.y;                             // hull paint lines move with the hull (its waterline is at 0)
	vec3 col;
	float rough = 0.6;
	float spec = 0.3;
	float metal = 0.0;
	float ao = 1.0;
	if (kind == 0) {
		vec3 antifoul = vec3(0.062, 0.016, 0.013);   // oxblood antifouling (linear)
		vec3 boot = vec3(0.010, 0.011, 0.014);
		vec3 topside = vec3(0.78, 0.15, 0.011);      // the marker orange of the float at the end
		float above = smoothstep(0.055, 0.075, hy);
		float band = smoothstep(-0.075, -0.055, hy) * (1.0 - above);
		col = mix(antifoul, topside, above);
		col = mix(col, boot, band);
		// fouling: a pale slime film and olive algae streaks along the flow, densest just under the waterline
		float near_wl = smoothstep(-0.75, -0.06, hy) * (1.0 - above);
		float flow = water_noise(vec2(v_l.z * 0.9, (v_l.y - abs(v_l.x) * 0.35) * 15.0));
		float fine = water_noise(vec2(v_l.z * 7.0, v_l.y * 40.0 + v_l.x * 3.0));
		float alg = smoothstep(0.52, 0.86, flow * 0.75 + fine * 0.25) * near_wl;
		col = mix(col, vec3(0.045, 0.07, 0.016), alg * 0.85);
		col = mix(col, vec3(0.11, 0.115, 0.08), near_wl * 0.3 * fine);
		// the bottom sees only the deep below: darker towards the keel
		float keel = smoothstep(-0.08, -0.65, hy);
		col *= mix(1.0, 0.5, keel);
		ao = mix(1.0, 0.55, keel * smoothstep(0.2, -0.9, n.y));
		// wet slime gives the bottom a soft sheen: the strakes and the chine read as lines of reflected light
		rough = mix(0.5, 0.4, above);
		spec = mix(0.42, 0.4, above);
	} else if (kind == 1) {
		col = vec3(0.022, 0.024, 0.027);
		rough = 0.42;
		spec = 0.35;
		metal = 0.3;
	} else if (kind == 2) {
		col = vec3(0.30, 0.31, 0.32);
		rough = 0.32;
		spec = 0.5;
		metal = 0.8;
	} else {
		float rust = water_noise(v_w.xz * 3.0 + v_w.y * 2.0);
		col = mix(vec3(0.035, 0.032, 0.03), vec3(0.09, 0.04, 0.018), smoothstep(0.35, 0.8, rust));
		rough = 0.8;
		spec = 0.2;
	}
	vec3 rl = water_rel_light(y);
	// shallow caustic flicker on whatever faces the sun (the topsides and the leg near the surface)
	vec3 s = normalize(water_sun_dir);
	vec2 cp = v_w.xz - v_w.y * s.xz / s.y;
	float c = water_caustic(cp * 2.4, TIME * 1.7) * (1.0 - smoothstep(3.0, 22.0, -y)) * clamp(dot(n, s), 0.0, 1.0);
	ALBEDO = col * rl * (1.0 + c * 1.6);
	ROUGHNESS = rough;
	SPECULAR = spec * water_spec_dim(y);
	METALLIC = metal;
	AO = ao;
	AO_LIGHT_AFFECT = 0.0;
	// meniscus: a thin bright line where the hull pierces the surface (the light bent into the water there)
	if (kind != 3) {
		float rim = smoothstep(-0.05, -0.012, y) * (1.0 - smoothstep(-0.012, 0.004, y));
		EMISSION = vec3(0.55, 0.85, 0.95) * rim * 0.9 * water_light_scale;
	}
	FOG = water_fog(v_w);
}
