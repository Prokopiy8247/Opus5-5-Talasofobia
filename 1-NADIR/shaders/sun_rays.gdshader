shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
// Sun rays of the shallows as one full-screen raymarch (replaces the old billboard shaft quads, which ended
// mid-water, had round caps and collapsed into thin wires far away). The waves focus sunlight into a moving
// caustic net at the surface; every point under it is lit by the net cell it sees along the sun direction,
// so the rays are infinite sheets parallel to the light: they converge on the sun looking up and on the
// anti-solar point looking down, fade with depth and distance, and the boat casts a shadow column.
// Drawn after the shared water-light multiply (render_priority -128), never darkened by it.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D ray_tex : filter_linear_mipmap, repeat_enable;   // cellular F2-F1, 256 px tile
global uniform float g_time;
global uniform float g_daylight;

uniform vec3 to_sun = vec3(0.3403, 0.9007, 0.2702);  // underwater direction toward the sun (= -WaterEnv.SUN_DIR)
uniform vec3 sun_col = vec3(0.55, 0.85, 0.80);       // linear
uniform float ray_gain = 0.85;
uniform float sigma = 0.0085;                        // extinction per metre (= env.fog_density)
uniform float aniso = 0.6;                           // Henyey-Greenstein g of the forward lobe
uniform float aniso_mix = 0.55;                      // share of the forward lobe vs isotropic
uniform float max_dist = 90.0;
uniform vec4 boat = vec4(0.0);                       // x, z, yaw (rad), on (> 0)
uniform float adapt = 1.0;                           // eye adaptation (adapted / raw water colour), set per frame

const int STEPS = 32;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float hg(float c, float g) {
	return (1.0 - g * g) / (4.0 * PI * pow(1.0 + g * g - 2.0 * g * c, 1.5));
}

// Ray brightness at world point p: the caustic net at the surface entry point q of the sun ray through p.
float rays_at(vec3 p, float lod_step, float len_dq) {
	vec2 q = p.xz - to_sun.xz * (p.y / to_sun.y);
	float dep = max(-p.y, 0.0);
	// the focus blurs with depth; the step-based LOD keeps a coarse march from aliasing. A view almost exactly along
	// the light marches one single net column for the whole distance (no averaging): blur it, or the anti-solar
	// point shows a glowing knot
	float lod = clamp(max(dep / 28.0, lod_step), 0.0, 5.0);
	lod = max(lod, 3.0 * (1.0 - smoothstep(0.0, 0.25, len_dq)));
	vec2 w = vec2(sin(q.y * 0.07 + g_time * 0.31), cos(q.x * 0.06 - g_time * 0.27)) * 1.6;
	float a = textureLod(ray_tex, (q + w) / 64.0 + g_time * vec2(0.004, 0.0025), lod).r;
	float b = textureLod(ray_tex, (q - w) / 41.0 - g_time * vec2(0.003, -0.004), lod).r;
	// High powers keep the gaps between rays dark. Only the focused excess over the mean light counts (the mean
	// is already in the water colour). The waves focus the light within a metre or two, so the rays start right at
	// the ceiling (softer in the top few metres): no ray-less band over a rayed floor in the first seconds.
	float c = pow(1.0 - a, 7.0) * pow(1.0 - b, 3.5);
	c = max(c - 0.04, 0.0) * (1.0 / 0.96) * mix(0.35, 1.0, smoothstep(0.0, 4.0, dep));
	if (boat.w > 0.0) {
		vec2 o = q - boat.xy;
		vec2 l = vec2(cos(boat.z) * o.x - sin(boat.z) * o.y, sin(boat.z) * o.x + cos(boat.z) * o.y);
		c *= smoothstep(0.8, 1.15, length(l / vec2(3.3, 1.2)));
	}
	return c * exp(-dep / 45.0);
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float scene_d = length(view.xyz);
	vec3 dir = normalize((INV_VIEW_MATRIX * vec4(view.xyz, 0.0)).xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;

	// interleaved-gradient jitter, rotated every frame: temporal noise the grain pass masks (a FRAGCOORD-only
	// jitter is a static 45-degree hatch fixed to the screen; the project has no TAA)
	float jit = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))) + 0.6180339 * floor(g_time * 60.0));
	float tmax = min(scene_d, max_dist);
	float dt = tmax / float(STEPS);
	// how far the surface entry point moves per step, in texels of the 64 m tile (256 px)
	vec2 dq = dir.xz - to_sun.xz * (dir.y / to_sun.y);
	float len_dq = length(dq);
	float lod_step = log2(max(len_dq * dt * 4.0 * 0.5, 1.0));
	float s = 0.0;
	for (int i = 0; i < STEPS; i++) {
		float t = (float(i) + jit) * dt;
		vec3 p = cam + dir * t;
		if (p.y > 0.0) {
			break;
		}
		s += rays_at(p, lod_step, len_dq) * exp(-sigma * t) * dt;
	}
	float ph = mix(1.0 / (4.0 * PI), hg(dot(dir, to_sun), aniso), aniso_mix);
	// rays_at already carries the light lost above each point; sqrt(daylight) only keeps the rays in step
	// with the darkening water around the diver (full daylight would count that loss twice)
	ALBEDO = sun_col * (s * ph * ray_gain * sqrt(g_daylight) * adapt);
}
