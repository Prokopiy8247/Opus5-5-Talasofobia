shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// The Bloop's shear wake fleck: a tiny additive gaussian point of cold cyan light (colour script: bioluminescence
// is cold cyan only; it adds no light source). Each fleck fires short flashes on its own rhythm and dims as the
// stimulated cells tire (age). It is seen only OUTSIDE the torch beam (1 - torch_profile, the same lobes as the
// lights), like the snow sparks, up to the end of the beam's reach, and fades with water extinction, so it reads
// at 30-120 m in the dark around and beyond the beam, never as an outline of lit skin. Peak per fleck stays under
// the 1.05 glow threshold (no bloom).
uniform float gain = 3.0;
uniform float scale = 0.0;          // Beat05 envelope over the encounter
uniform float sigma = 0.0175;       // water extinction per metre (fog density)
uniform float range = 82.0;         // torch range (Config.TORCH_RANGE)
uniform float size_min = 0.14;      // m
uniform float size_k = 0.008;       // on-screen floor: ~4 px quad (a ~2 px soft point) at 720p
uniform float peak = 0.95;
uniform float base_glow = 0.14;     // the dim afterglow between flashes
uniform float duty = 0.12;          // fraction of each flash cycle that is lit
uniform vec4 lobe_cos = vec4(0.9396926, 0.8660254, 0.8290376, 0.7431448);
uniform vec4 lobe_exp = vec4(1.0, 1.0, 0.5, 0.5);
uniform vec4 lobe_w = vec4(0.3287, 0.1516, 0.2641, 0.2170);
uniform vec3 lobe_5 = vec3(0.6156615, 0.6, 0.0437);
global uniform vec3 g_torch_pos;
global uniform vec3 g_torch_dir;
global uniform float g_torch;
global uniform vec3 g_cam_pos;

varying vec3 col;

// --- TORCH PROFILE CONTRACT: the same function as beam_haze, snow_draw and bubble_draw.
float torch_profile(float c) {
	vec4 rim = clamp((1.0 - c) / (1.0 - lobe_cos), vec4(0.0001), vec4(1.0));
	float rim5 = clamp((1.0 - c) / (1.0 - lobe_5.x), 0.0001, 1.0);
	return dot(lobe_w, vec4(1.0) - pow(rim, lobe_exp)) + lobe_5.z * (1.0 - pow(rim5, lobe_5.y));
}

void vertex() {
	vec3 wpos = MODEL_MATRIX[3].xyz;
	vec4 cu = INSTANCE_CUSTOM;
	float age = cu.y;
	float dc = length(wpos - g_cam_pos);
	vec3 Lt = wpos - g_torch_pos;
	float d = max(length(Lt), 0.001);
	// masked inside the beam, as far as the beam reaches (82 m range); past it the water is dark again
	float cone = clamp(torch_profile(dot(Lt / d, g_torch_dir)), 0.0, 1.0) * step(0.001, g_torch)
		* (1.0 - smoothstep(range * 1.05, range * 1.5, d));
	// a flash: fast rise, short decay, once per cycle (0.6-1.6 s); between flashes a faint afterglow
	float ph = fract(cu.z + age * (0.6 + cu.x));
	float on = smoothstep(0.0, 0.015, ph) * (1.0 - smoothstep(duty * 0.35, duty, ph));
	float flash = exp(-age / 2.2) * mix(base_glow, 1.0, on) * smoothstep(0.0, 0.25, age);
	float k = gain * scale * flash * exp(-sigma * dc) * (1.0 - cone);
	col = vec3(0.12, 0.75, 1.0) * min(k, peak);
	float sz = max(size_min, dc * size_k);
	vec3 vc = (VIEW_MATRIX * vec4(wpos, 1.0)).xyz;
	MODELVIEW_MATRIX = mat4(vec4(sz, 0.0, 0.0, 0.0), vec4(0.0, sz, 0.0, 0.0), vec4(0.0, 0.0, sz, 0.0), vec4(vc, 1.0));
	if (k < 1e-4) {
		col = vec3(0.0);
	}
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r2 = dot(q, q);
	ALBEDO = col * exp(-4.0 * r2) * (1.0 - smoothstep(0.81, 1.0, r2));
	ALPHA = 1.0;
	FOG = vec4(0.0);
}
