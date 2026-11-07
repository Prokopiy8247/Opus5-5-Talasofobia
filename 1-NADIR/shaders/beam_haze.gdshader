shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
// Light scattered toward the eye by the water: the torch cone (and one optional point lamp), integrated per pixel
// along the view ray up to the scene depth read from the depth buffer. One full-screen pass replaces engine
// volumetric fog, so the haze is identical over geometry, the backdrop sphere and the surface plane (no
// silhouettes against the backdrop), has no froxel blocks and does not smear when the view turns.
// Turbulent particulate density (3D noise drifting with the snow current) keeps the beam alive; a bottom
// nepheloid layer (resuspended silt) thickens it within ~10 m of the floor.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler3D noise_tex : filter_linear, repeat_enable;
global uniform vec3 g_torch_pos;
global uniform vec3 g_torch_dir;
global uniform float g_torch;
global uniform float g_time;
global uniform vec3 g_flow;

uniform vec3 torch_col = vec3(0.62, 0.81, 1.0);   // linear
uniform float torch_gain = 1.0;                    // overall brightness (Config.HAZE_GAIN, faded at the end)
uniform vec4 lobe_cos = vec4(0.9396926, 0.8660254, 0.8290376, 0.7431448);  // cos of Config.TORCH_LOBES angles 1-4
uniform vec4 lobe_exp = vec4(1.0, 1.0, 0.5, 0.5);                           // their spot_angle_attenuation
uniform vec4 lobe_w = vec4(0.3287, 0.1516, 0.2641, 0.2170);                  // their energy weights
uniform vec3 lobe_5 = vec3(0.6156615, 0.6, 0.0437);                          // lobe 5: cos, attenuation, weight
uniform float range = 82.0;
uniform float decay = 0.55;                        // SpotLight3D distance attenuation exponent
uniform float sigma = 0.0175;                      // extinction per metre (kept equal to the exponential fog)
uniform float noise_amt = 0.55;
uniform float noise_scale = 0.045;                 // 1 / metres per noise tile
uniform float floor_y = -1.0e9;                    // world y of the sea floor (BeamHaze.set_floor), far = off
uniform vec4 lamp = vec4(0.0);                     // point lamp: xyz world position, w range (0 = off)
uniform vec3 lamp_col = vec3(1.0, 0.46, 0.1);     // linear
uniform float lamp_gain = 0.0;
uniform float lamp_decay = 1.3;

const int STEPS = 36;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float phase(float c) {
	// mostly isotropic with a forward lobe (water scatters forward; a diver mostly sees the side/back scatter)
	float g = 0.6;
	float hg = (1.0 - g * g) / (4.0 * PI * pow(1.0 + g * g - 2.0 * g * c, 1.5));
	return mix(1.0 / (4.0 * PI), hg, 0.35);
}

float win(float d, float r) {
	float nd = d / r;
	nd *= nd;
	nd *= nd;
	nd = max(1.0 - nd, 0.0);
	return nd * nd;
}

// --- TORCH PROFILE CONTRACT: the same function in beam_haze, snow_draw and bubble_draw. It reproduces the
// concentric SpotLight3D lobes of the torch in Player.gd exactly (Godot's spot cone law per lobe:
// 1 - rim^attenuation), a hot core rolling off smoothly to 0 at 52 deg. c = cos of the angle to the beam axis;
// d (distance) is kept for the signature.
float torch_profile(float c, float d) {
	vec4 rim = clamp((1.0 - c) / (1.0 - lobe_cos), vec4(0.0001), vec4(1.0));
	float rim5 = clamp((1.0 - c) / (1.0 - lobe_5.x), 0.0001, 1.0);
	return dot(lobe_w, vec4(1.0) - pow(rim, lobe_exp)) + lobe_5.z * (1.0 - pow(rim5, lobe_5.y));
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float scene_d = length(view.xyz);
	vec3 dir = normalize((INV_VIEW_MATRIX * vec4(view.xyz, 0.0)).xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;

	// march jitter: interleaved gradient noise, rotated every frame (golden ratio) so the step residual is a
	// fine temporal noise the grain pass hides, not a static hatch fixed to the screen (no TAA here)
	float jit = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))
		+ 0.6180339 * floor(g_time * 60.0));
	vec3 acc = vec3(0.0);
	vec3 drift = g_flow + vec3(0.11, 0.05, -0.08) * g_time;

	if (g_torch * torch_gain > 0.0005) {
		float tmax = min(scene_d, range);
		float dt = tmax / float(STEPS);
		for (int i = 0; i < STEPS; i++) {
			float t = (float(i) + jit) * dt;
			vec3 p = cam + dir * t;
			vec3 L = p - g_torch_pos;
			float d = max(length(L), 0.6);
			vec3 l = L / d;
			float cone = torch_profile(dot(l, g_torch_dir), d);
			if (cone <= 0.0) {
				continue;
			}
			float n = texture(noise_tex, (p - drift) * noise_scale).r;
			float dens = max(1.0 + noise_amt * (n * 2.0 - 1.0), 0.0);
			dens *= 1.0 + 1.6 * exp(-max(p.y - floor_y, 0.0) / 9.0);
			float att = win(d, range) * pow(d, -decay) * exp(-sigma * (t + d));
			acc += torch_col * (cone * att * phase(dot(l, -dir)) * dens * dt);
		}
		acc *= g_torch * torch_gain;
	}

	if (lamp.w > 0.0 && lamp_gain > 0.0) {
		// the lamp only matters near it: march the part of the ray inside its sphere
		vec3 oc = cam - lamp.xyz;
		float b = dot(oc, dir);
		float c = dot(oc, oc) - lamp.w * lamp.w;
		float h = b * b - c;
		if (h > 0.0) {
			h = sqrt(h);
			float t0 = max(-b - h, 0.0);
			float t1 = min(-b + h, scene_d);
			if (t1 > t0) {
				float dt = (t1 - t0) / 16.0;
				vec3 la = vec3(0.0);
				for (int i = 0; i < 16; i++) {
					float t = t0 + (float(i) + jit) * dt;
					vec3 p = cam + dir * t;
					float d = max(length(p - lamp.xyz), 0.15);
					float n = texture(noise_tex, (p - drift) * noise_scale * 2.0).r;
					float dens = max(1.0 + noise_amt * (n * 2.0 - 1.0), 0.0);
					la += lamp_col * (win(d, lamp.w) * pow(d, -lamp_decay) * exp(-sigma * (t + d)) * dens * dt);
				}
				acc += la * lamp_gain / (4.0 * PI);
			}
		}
	}
	ALBEDO = acc;
}
