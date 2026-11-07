shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Marine snow mote (also drawn by the Bloop's maw stream).
// - torch light computed per mote with the SAME law as the torch lights: torch_profile(), range window,
//   d^-decay and extinction both ways, so the snow cone is the light cone and motes dim with distance
// - water light: motes scatter the ambient water light (brighter looking up, a glint toward the sun), so the
//   snow drifts visibly in the blue before the torch
// - streaks: stretched along its motion across the view during a short exposure, energy kept constant
// - soft whenever it is out of focus (within ~4.5 m of the mask), a loose aggregate, or simply wider than a
//   few pixels on screen: a dim gaussian orb with no rim and no motion streak (no grey or cyan "pills")
// - cold bioluminescent sparks outside the beam (450-1350 m), more when the diver stirs the water, and a
//   displacement shell (set_wave) when the creature pushes the water ahead of it; a flash is a round point
//   beyond arm's length, never a streak or a blob on the lens
// Brightness is compressed per mote (col / (1 + peak)), never per pixel: the gaussian keeps its falloff
// instead of flattening into a plateau with a 1-px rim.
uniform float opacity = 1.0;
uniform float gain = 10.0;
uniform float size_mul = 1.4;
uniform float fade_near = 12.0;
uniform float fade_far = 19.0;
uniform float streak = 1.0;
uniform float shutter = 0.022;
uniform float range = 82.0;                         // torch range (Config.TORCH_RANGE)
uniform float decay = 0.55;                         // SpotLight3D distance exponent
uniform float sigma = 0.0175;                       // extinction per metre (MarineSnow sets the fog density)
uniform vec4 lobe_cos = vec4(0.9396926, 0.8660254, 0.8290376, 0.7431448);  // cos of Config.TORCH_LOBES angles 1-4
uniform vec4 lobe_exp = vec4(1.0, 1.0, 0.5, 0.5);                           // their spot_angle_attenuation
uniform vec4 lobe_w = vec4(0.3287, 0.1516, 0.2641, 0.2170);                  // their energy weights
uniform vec3 lobe_5 = vec3(0.6156615, 0.6, 0.0437);                          // lobe 5: cos, attenuation, weight
uniform vec3 water_lin = vec3(0.0);                 // linear water colour (MarineSnow sets it per frame)
uniform float amb_gain = 1.2;
uniform vec3 sun_up = vec3(0.3403, 0.9007, 0.2702); // toward the refracted sun (-WaterEnv.SUN_DIR)
uniform float spark_amt = 1.0;                      // bioluminescent sparks (0 = off)
uniform vec4 wave = vec4(0.0, 0.0, 0.0, -1.0);      // displacement shell: xyz origin, w radius (< 0 = off)
uniform float wave_amp = 0.0;
uniform float view_h = 1080.0;                      // viewport height in px (MarineSnow sets it every frame)
global uniform vec3 g_torch_pos;
global uniform vec3 g_torch_dir;
global uniform float g_torch;
global uniform float g_daylight;
global uniform float g_depth;
global uniform vec3 g_cam_pos;
global uniform vec3 g_cam_vel;
global uniform float g_time;

varying vec3 col;      // per-mote scattered light (depends only on the mote's centre), faded and compressed
varying vec3 gcol;     // per-mote bioluminescent flash, faded and compressed
varying float elong;
varying float blur;
varying float gk;      // flash core radius in quad units (a ~2-3 px point, wider only when defocused)

float win(float d, float r) {
	float nd = d / r;
	nd *= nd;
	nd *= nd;
	nd = max(1.0 - nd, 0.0);
	return nd * nd;
}

// --- TORCH PROFILE CONTRACT: the same function in beam_haze, snow_draw and bubble_draw (see beam_haze).
float torch_profile(float c, float d) {
	vec4 rim = clamp((1.0 - c) / (1.0 - lobe_cos), vec4(0.0001), vec4(1.0));
	float rim5 = clamp((1.0 - c) / (1.0 - lobe_5.x), 0.0001, 1.0);
	return dot(lobe_w, vec4(1.0) - pow(rim, lobe_exp)) + lobe_5.z * (1.0 - pow(rim5, lobe_5.y));
}

void vertex() {
	float sc0 = length(MODEL_MATRIX[0].xyz);
	vec3 wpos = MODEL_MATRIX[3].xyz;
	vec4 cu = INSTANCE_CUSTOM;
	float dc = length(wpos - g_cam_pos);
	// --- light, per mote
	vec3 Lt = wpos - g_torch_pos;
	float d = length(Lt);
	float cone = torch_profile(dot(Lt / max(d, 0.001), g_torch_dir), d);
	float torch = g_torch * cone * gain * win(d, range) * pow(max(d, 0.4), -decay) * exp(-sigma * (d + dc));
	// ambient water light scattered by the mote (+ a glint toward the sun in the sunlit zone)
	vec3 vdir = (wpos - g_cam_pos) / max(dc, 0.001);
	float upf = max(vdir.y, 0.0);
	float sunf = pow(max(dot(vdir, sun_up), 0.0), 6.0);
	vec3 amb = water_lin * (0.6 + 2.5 * upf * upf) * amb_gain
		+ vec3(0.70, 0.90, 0.85) * g_daylight * (0.04 + 1.2 * sunf);
	vec3 c = vec3(0.86, 0.92, 1.0) * torch + amb * exp(-sigma * dc);
	// cold bioluminescence outside the beam: rare sparks, a swirl around the mask while moving, and the
	// displacement shell (set_wave) ahead of the creature
	float glow = 0.0;
	float bio = smoothstep(450.0, 600.0, g_depth) * (1.0 - smoothstep(1350.0, 1450.0, g_depth)) * spark_amt;
	if (bio > 0.0) {
		float stir = smoothstep(6.0, 2.0, dc) * smoothstep(0.4, 2.0, length(g_cam_vel));
		float k = g_time * 3.0 + cu.y * 7.0;
		float pick = step(0.988 - 0.3 * stir, fract(sin(floor(k) * 12.9898 + cu.z * 78.233) * 43758.5453));
		float fl = 1.0 - fract(k);
		glow += pick * fl * fl * (0.35 + stir) * 2.4 * bio;
	}
	if (wave.w > 0.0 && wave_amp > 0.0) {
		glow += exp(-pow((length(wpos - wave.xyz) - wave.w) / 2.5, 2.0)) * wave_amp * step(0.6, cu.x) * 1.6;
	}
	glow *= 1.0 - clamp(cone, 0.0, 1.0) * step(0.001, g_torch);
	glow *= smoothstep(1.5, 3.5, dc);                          // no flashes on the lens
	// --- size: minimum on-screen size so distant motes do not shimmer as sub-pixel dots; a flashing mote
	// gets a quad of at least 6 px, so its round point (fragment) never touches the quad edge
	// pixels per metre at 1 m. abs(): the RD renderer flips Y in the projection, so [1][1] is negative (a negative
	// scale silently turned every size test off and shrank the flashes to nothing)
	float fpx = abs(PROJECTION_MATRIX[1][1]) * max(view_h, 100.0) * 0.5;
	float sc = max(sc0 * size_mul, dc * 0.0026);
	float sq = glow > 0.005 ? max(sc, dc * 6.0 / fpx) : sc;
	float bt = smoothstep(4.5, 1.2, dc);                       // defocus near the mask
	float fluffy = smoothstep(0.02, 0.055, sc0 * size_mul);    // big aggregates are loose and translucent
	float big = smoothstep(2.5, 6.0, sq * fpx / max(dc, 0.05));    // wider than a few px: never a crisp edge
	blur = max(max(bt, 0.85 * fluffy), big);                   // shape softness (fragment)
	float scb = sq * (1.0 + 0.6 * blur) + bt * 0.03;           // a soft disc needs room to fall off
	// out of focus: dim, so near motes are faint orbs, not grey pills; big flakes are soft and dimmer
	float ek = mix(1.0, 0.15, bt) * mix(1.0, 0.5, fluffy) * mix(1.0, 0.5, big);
	vec3 vc = (VIEW_MATRIX * vec4(wpos, 1.0)).xyz;
	vec3 vrel = (VIEW_MATRIX * vec4(vec3(0.0, -0.06, 0.0) - g_cam_vel, 0.0)).xyz;
	// motion across the view during the exposure, in metres at the mote's depth (perspective-correct, so
	// motes ahead of a sinking diver stream outward radially)
	vec3 p1 = vc + vrel * shutter * streak;
	vec2 s0 = vc.xy / max(-vc.z, 0.05);
	vec2 s1 = p1.xy / max(-p1.z, 0.05);
	vec2 m = (s1 - s0) * max(-vc.z, 0.05);
	// soft motes are not streaked into capsules: they stay round orbs; a flash reads as a point
	float L = min(length(m), scb * mix(12.0, 0.25, smoothstep(0.0, 0.3, blur)));
	if (glow > 0.005) {
		L = min(L, scb * 1.2);
	}
	vec2 ax = L > 1e-5 ? normalize(m) : vec2(1.0, 0.0);
	vec2 ay = vec2(-ax.y, ax.x);
	elong = (scb + L) / scb;
	MODELVIEW_MATRIX = mat4(vec4(ax * (scb + L), 0.0, 0.0), vec4(ay * scb, 0.0, 0.0),
		vec4(0.0, 0.0, scb, 0.0), vec4(vc, 1.0));
	// scattered light keeps its energy over the drawn area; the glow is emitted by a point inside the mote,
	// so a flash on a big loose aggregate is still a small round point, not a cyan blob
	float tw = 0.72 + 0.28 * sin(g_time * (0.8 + 3.2 * cu.y) + cu.z * 6.2831);
	float fade = (1.0 - smoothstep(fade_near, fade_far, dc)) * smoothstep(0.5, 1.8, dc) * opacity;
	col = c * tw * (sc * sc) / (scb * scb) * ek / elong * fade;
	col /= 1.0 + max(col.r, max(col.g, col.b));               // compress per mote, not per pixel
	gcol = vec3(0.12, 0.75, 1.0) * glow * ek * fade;
	gcol /= 1.0 + max(gcol.r, max(gcol.g, gcol.b));
	gk = clamp(max(1.2 * max(dc, 0.05) / fpx / (0.5 * scb), 0.6 * bt), 0.05, 0.45);
}

void fragment() {
	// shape: a streak with a gaussian cross-section and tapered ends, or a soft defocused gaussian disc
	// (no ring, no flat top: the disc falls off from the centre in every direction)
	vec2 q = (UV - 0.5) * 2.0;
	q.x *= elong;
	float r = length(vec2(max(abs(q.x) - (elong - 1.0), 0.0), q.y));
	float sharp = exp(-2.2 * r * r) * (1.0 - smoothstep(0.8, 1.0, r));
	sharp *= 1.0 - 0.6 * smoothstep(0.6, 1.0, abs(q.x) / elong) * (1.0 - blur);
	// the soft disc is an elliptical gaussian (no flat core along a short streak)
	float re = length(vec2(q.x / elong, q.y));
	float bokeh = exp(-4.0 * re * re);
	float spark = exp(-dot(q, q) / (gk * gk));                 // round, whatever the streak
	ALBEDO = (col * mix(sharp, bokeh, blur) + gcol * spark) * 1.15;
	ALPHA = 1.0;
	FOG = vec4(0.0);
}
