// Shared body motion, staging and procedural skin for SCP-3000 (the finished mesh and its endless procedural body).
// All motion happens in MODEL space (the prefab root carries the scale, the slow drift and the rise).

uniform float spine_len = 136.2;          // model metres from snout (s = 0) to tail tip (s = 1)
uniform float wave_period = 32.0;         // seconds
uniform float wave_count = 1.2;           // wavelengths along the body
uniform float amp_head = 0.25;            // lateral amplitude near the head (model m)
uniform float amp_tail = 8.0;             // lateral amplitude towards the tail (model m)
uniform float slow_period = 80.0;
uniform float slow_amp = 1.6;
uniform float motion_time = 0.0;          // driven by the prefab script (keeps waves continuous)
// Staging (SCP3000.gd haze_at / line_boost / rim_melt_at). Visibility depends on the distance from the camera and
// the path time only; the one exception is the dark-line boost on the far body (boost_s = body parameter range).
uniform float haze_k = 0.0;               // extra optical depth per metre, creature only
uniform float line_boost = 1.0;           // > 1: the far body keeps a stronger silhouette (the dark line, beat 4)
uniform vec2 boost_s = vec2(2.0, 3.0);
uniform float rim_melt = 0.0;             // grazing-angle melt of the silhouette (0 while the creature emerges)
uniform float lock_k = 0.0;               // eye-lock veil per metre, over the first 120 m only (SCP3000.LOCK_RANGE)
uniform float rim_glow = 0.0;             // faint backscatter rim on the upper silhouette (SCP3000.rim_glow_at)
uniform float far_k = 0.0;                // per metre beyond 170 m (max 260 m of it): the far body keeps its silhouette
                                          // deeper into the murk (SCP3000.far_k_at; < the fog density, so visibility
                                          // still falls monotonically with distance)
uniform float top_scatter = 0.0;          // far body: share of the water's glow its upper side returns (SCP3000.top_scatter_at)
// The one-off travelling flex of the dark line (SCP3000.flex_*): an S-bend centred at body arc flex_c (model m,
// s * spine_len), half-width flex_w, peak lateral offset flex_amp (model m). Mirrored in SCP3000.body_wave().
uniform float flex_c = -10000.0;
uniform float flex_w = 20.0;
uniform float flex_amp = 0.0;

// Mirror of SCP3000.vis_mult(): multiplier on the water transmittance of a body point.
float creature_vis(float s, float d) {
	float b = 1.0 + (line_boost - 1.0) * smoothstep(boost_s.x, boost_s.y, s) * smoothstep(170.0, 240.0, d);
	return exp(-haze_k * d - lock_k * min(d, 120.0) + far_k * clamp(d - 170.0, 0.0, 260.0)) * b;
}

// Normalize that never returns NaN (a NaN pixel shows black and the glow pass blooms it into a disc).
vec3 creature_safe_n(vec3 v) {
	return v * inversesqrt(max(dot(v, v), 1e-12));
}

// Soft limb of a far body: the share (0..0.85) of the body's darkness the water's small-angle forward scatter takes
// off its silhouette. A body hundreds of metres away is seen through an angular blur (a fixed share of the screen
// height), so its edge fades towards the water instead of ending in a 1-px step. Three parts: the outer ~15 % of the
// radius (grazing normal), a band of ~1 % of the screen height inside the silhouette (distance to the limb in pixels
// estimated from ndv and its screen derivative, ~1.5-2x the true distance), and the outermost ~2 px, which fade
// further (the silhouette pixel keeps ~15 % of the core's darkness, so even the belly edge, which gets no top scatter,
// is a short ramp and not a step). The core keeps its darkness. ramp = distance (m) over which it comes in: the
// finished mesh uses 150-330 m (the close emergence stays solid), the far body starts earlier.
// ndv = facing of the SMOOTH body normal, vp_h = viewport height in pixels. Call from fragment() only.
float creature_limb(float ndv, float d, float vp_h, vec2 ramp) {
	float n = clamp(ndv, 0.0, 1.0);
	float grazing = smoothstep(0.45, 1.0, 1.0 - n);
	float edge_px = n / max(fwidth(n), 1e-4);
	float band = 1.0 - smoothstep(0.0, 0.016 * vp_h, edge_px);
	float outer = 1.0 - smoothstep(0.0, 5.0, edge_px);
	return max(grazing, band) * (0.6 + 0.25 * outer) * smoothstep(ramp.x, ramp.y, d);
}

// Water fog plus the creature haze; rim = silhouette term (0..1) for the soft forward-scatter edge, limb =
// creature_limb() (the share of the darkness the limb loses), life = slow large-scale variation of the far body's
// darkness (1 = none).
vec4 creature_fog(vec3 wp, float s, float rim, float limb, float life) {
	vec4 f = water_fog(wp);
	float d = length(wp - water_cam_pos);
	float tr = (1.0 - f.a) * creature_vis(s, d) * (1.0 - rim_melt * rim) * (1.0 - clamp(limb, 0.0, 1.0)) * life;
	f.a = 1.0 - clamp(tr, 0.0, 1.0);
	return f;
}

// The water's downwelling glow on the upper side of a far body (added to EMISSION as a share of the fog colour behind
// the fragment, so the body stays darker than the water everywhere: no bright contour, the silhouette still comes
// first). Strongest on the upper flank and its limb (the back reads round, with a thin lighter lip), none on the
// belly (it melts into the dark water below). ndv / ny = facing and world y of the smooth body normal.
vec3 creature_top_scatter(vec3 fog_rgb, float ndv, float ny, float d) {
	float limb = smoothstep(0.3, 1.0, 1.0 - clamp(ndv, 0.0, 1.0));
	return fog_rgb * top_scatter * smoothstep(-0.2, 0.9, ny) * (0.4 + 0.6 * limb) * smoothstep(120.0, 220.0, d);
}

// 1 = shallow-water gloss; falls with depth (only dim, diffuse blue light from above down there, no sharp sun glints).
float deep_gloss(float world_y) {
	return mix(1.0, 0.3, smoothstep(180.0, 480.0, -world_y));
}

// Albedo scale for skin far below the diver: lit from above it would read lighter than the abyss behind it;
// a body deep below must read as a dark mass receding into the indigo (most of the way there by 140 m below).
float below_dark(float world_y) {
	return mix(1.0, 0.08, smoothstep(30.0, 180.0, water_cam_pos.y - world_y));
}

// Far or deep-below skin takes the water's hue: the red and green the olive skin reflects do not survive that much
// water (no lit grey-green pipe in the indigo). fog_rgb = fog colour of the fragment (the water behind it); the
// albedo keeps its luminance in the dominant channel of the water, so it only ever gets darker.
vec3 creature_water_hue(vec3 alb, vec3 fog_rgb, float dist, float world_y) {
	float below = water_cam_pos.y - world_y;
	float k = max(0.85 * smoothstep(80.0, 260.0, dist), 0.95 * smoothstep(40.0, 160.0, below));
	vec3 hue = fog_rgb / max(max(fog_rgb.r, fog_rgb.g), max(fog_rgb.b, 1e-5));
	float l = dot(alb, vec3(0.3, 0.59, 0.11));
	return mix(alb, l * hue, k);
}

// Distance cues for a body hundreds of metres long: lit skin detail fades before the silhouette does, so far parts
// read as a dark mass, near parts as skin. Returns (near detail 1..0, far darkening 0..1, top light 1..0).
vec3 creature_dist(float d) {
	return vec3(1.0 - smoothstep(35.0, 170.0, d), smoothstep(110.0, 280.0, d), 1.0 - smoothstep(150.0, 245.0, d));
}

// Backscatter rim (added to EMISSION): a little of the water's own colour on silhouettes that face upwards, away
// from the head. fog_rgb = the fog colour of the fragment, rim = creature_rim(), ny = world normal y.
vec3 creature_rim_glow(vec3 fog_rgb, float rim, float ny, float s) {
	return fog_rgb * rim_glow * rim * smoothstep(-0.2, 0.7, ny) * smoothstep(0.16, 0.28, s);
}

// Fresnel-ish silhouette term from a view-space normal.
float creature_rim(vec3 n, vec3 view) {
	float k = 1.0 - clamp(dot(creature_safe_n(n), creature_safe_n(view)), 0.0, 1.0);
	return k * k * k;
}

mat3 rot_y(float a) {
	float c = cos(a); float s = sin(a);
	return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c));
}

mat3 rot_axis(vec3 ax, float a) {
	float c = cos(a); float s = sin(a); float t = 1.0 - c;
	return mat3(
		vec3(t * ax.x * ax.x + c, t * ax.x * ax.y + s * ax.z, t * ax.x * ax.z - s * ax.y),
		vec3(t * ax.x * ax.y - s * ax.z, t * ax.y * ax.y + c, t * ax.y * ax.z + s * ax.x),
		vec3(t * ax.x * ax.z + s * ax.y, t * ax.y * ax.z - s * ax.x, t * ax.z * ax.z + c));
}

// lateral displacement (model m) and its derivative per model metre of arc, at body parameter s (may exceed 1)
vec2 body_wave(float s) {
	float amp = mix(amp_head, amp_tail, smoothstep(0.06, 0.95, min(s, 1.0)));
	float ph = 6.2831853 * (wave_count * s - motion_time / wave_period);
	float ps = 6.2831853 * (0.55 * s - motion_time / slow_period) + 1.3;
	float sa = slow_amp * smoothstep(0.05, 0.5, s);
	float d = amp * sin(ph) + sa * sin(ps);
	float dd = (amp * cos(ph) * 6.2831853 * wave_count + sa * cos(ps) * 6.2831853 * 0.55) / spine_len;
	// the travelling flex: one S-bend (a Gaussian derivative, peak +-flex_amp) running down the far body
	float fw = max(flex_w, 1e-3);
	float x = (s * spine_len - flex_c) / fw;
	float g = exp(-min(x * x, 60.0));
	d += flex_amp * 2.3316 * x * g;                       // 2.3316 = sqrt(2e): the peak is exactly flex_amp
	dd += flex_amp * 2.3316 * (1.0 - 2.0 * x * x) * g / fw;
	return vec2(d, dd);
}

float skin_hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.31, 289.17))) * 15731.743);
}

float skin_noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(skin_hash(i), skin_hash(i + vec2(1.0, 0.0)), u.x), mix(skin_hash(i + vec2(0.0, 1.0)), skin_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Blotch field: value noise on two differently rotated lattices at the same scale (no single grid to align to),
// gently domain-warped by a slower noise, so the blotches are rounded, irregular patches with no straight edges.
// Evaluated at the same point it returns the same value (skin_proc relies on that for its seamless wrap).
float skin_blot_noise(vec2 q) {
	vec2 w = vec2(skin_noise(q * 0.3 + vec2(1.7, 9.2)), skin_noise(q * 0.3 + vec2(8.3, 2.8))) - 0.5;
	q += w * 0.9;
	vec2 a = mat2(vec2(0.799, 0.602), vec2(-0.602, 0.799)) * q;     // +37 deg
	vec2 b = mat2(vec2(0.5, -0.866), vec2(0.866, 0.5)) * q;          // -60 deg
	vec2 c = mat2(vec2(0.974, 0.225), vec2(-0.225, 0.974)) * q;      // +13 deg
	float n = mix(skin_noise(a), skin_noise(b * 1.13 + 5.3), 0.5);
	// two lattices averaged have less contrast than one: stretch back around 0.5
	return (n * 0.75 + skin_noise(c * 2.3 + 7.1) * 0.18 + skin_noise(a * 5.1 + 3.3) * 0.07 - 0.5) * 1.5 + 0.5;
}

// Procedural mottled olive skin. arc: model metres along the body, ang: radians around it (0 = top), far: 0..1
// distance fade of the blotch contrast (a body seen through 100+ m of water shows its mass, not its pattern).
// Returns albedo in rgb and a blotch factor in a.
vec4 skin_proc(float arc, float ang, vec3 olive, vec3 dark, float far) {
	// periodic around the body (no seam at ang = +-PI): blend two copies one period apart
	float u = (ang + 3.14159265) / 6.2831853;
	vec2 q = vec2(arc * 0.55, u * 20.0);
	vec2 q2 = vec2(arc * 0.55, (u - 1.0) * 20.0);
	float n = mix(skin_blot_noise(q), skin_blot_noise(q2), u);
	n = (n - 0.5) * (1.0 + 0.8 * u * (1.0 - u)) + 0.5;
	float blot = smoothstep(0.5, 0.72, n) * mix(1.0, 0.6, far);
	float ql = (abs(ang) - 1.57) * 4.0;
	float lateral = exp(-ql * ql);
	float belly = smoothstep(2.2, 3.1, abs(ang));
	vec2 qs = mat2(vec2(0.6, 0.8), vec2(-0.8, 0.6)) * q;
	float tone = mix(skin_noise(qs * 0.4 + 3.0), skin_noise(mat2(vec2(0.6, 0.8), vec2(-0.8, 0.6)) * q2 * 0.4 + 3.0), u);
	vec3 c = olive * (0.78 + 0.36 * tone);
	c = mix(c, dark, blot * 0.5);
	c = mix(c, vec3(0.5, 0.52, 0.47), lateral * 0.16);
	c = mix(c, olive * 1.2, belly * 0.3);
	return vec4(c, blot);
}

// Tangent-space relief of the procedural skin (shared so the mesh blends into exactly the body's relief at the
// cut). rt = smooth FBM normal map (SCP3000._relief_tex): a coarse layer of soft swells and transverse folds at the
// world scale of the sculpted mesh relief (no straight cellular creases at that scale); dt = the cellular wrinkle
// map, only for the two fine layers.
vec3 skin_relief(sampler2D rt, sampler2D dt, float arc, float ang) {
	float u = ang / 6.2831853;
	vec3 n0 = texture(rt, vec2(arc * 0.11 + 0.13, u * 2.0)).xyz;
	vec3 n1 = texture(dt, vec2(arc * 0.31 + 0.71, u * 11.0)).xyz;
	vec3 n2 = texture(dt, vec2(arc * 1.3 + 0.37, u * 41.0)).xyz;
	vec3 n = (n0 - 0.5) * 1.1 + (n1 - 0.5) * 0.45 + (n2 - 0.5) * 0.3;
	return normalize(vec3(n.xy, 0.5)) * 0.5 + 0.5;
}

// Cross-section of the procedural body (mirror of SCP3000.ext_shape): radius factor at model arc a from the
// junction and angle ang around the body (0 = top): a slightly flattened oval with a dorsal crest that continues the
// finished mesh's crest (taller and serrated near the junction, then a low keel). The mesh takes this exact profile
// over its last metres.
float ext_profile(float a, float ang) {
	float crest = mix(0.25, 0.13, smoothstep(0.0, 60.0, a)) + 0.06 * sin(a * 1.3) * (1.0 - smoothstep(0.0, 40.0, a));
	float qc = ang / 0.22;                   // (squares written out: pow() of a negative base is undefined in GLSL)
	float qb = (abs(ang) - 3.14159265) / 0.5;
	float shape = 1.0 - 0.1 * cos(2.0 * ang) + crest * exp(-qc * qc) - 0.05 * exp(-qb * qb);
	// helical skin ripples near the junction only: on the far body (seen from 150+ m) a ripple of a few tenths of a
	// metre every 12-35 m only bends its outline into a chain of straight runs and kinks
	float rip = 1.0 - smoothstep(40.0, 110.0, a);
	return shape * (1.0 + rip * (0.012 * sin(a * 0.9 + ang + 0.4) + 0.006 * sin(a * 2.6 - ang * 2.0)));
}

// Soft transverse skin folds, irregular in spacing and depth (no ring banding along a body hundreds of metres long).
float skin_folds(float arc, float ang) {
	float w = skin_noise(vec2(arc * 0.11, ang * 0.8 + 3.0));
	return 0.5 + 0.5 * sin(arc * 2.3 + sin(ang * 3.0) * 1.5 + w * 5.0) * (0.35 + 0.65 * w);
}

// Shared by the mesh (near the cut) and the procedural body, so the junction has no seam.
const float PROC_SKIN = 0.36;             // albedo scale of the procedural skin
// soft light from above: darker flanks and belly (world-space normal y)
float skin_top(float ny) {
	return mix(0.5, 1.3, smoothstep(-0.6, 0.9, ny));
}
// The light from above as the creature's skin gets it: fading with distance (dc_z = creature_dist().z) and dimmed
// for skin well below the diver (its lit back would otherwise glow lighter than the abyss behind it; the top stays
// <= 0.85 there, flanks and belly keep their shading so the form still reads).
float creature_top(float ny, float dc_z, float world_y) {
	float top = mix(skin_top(ny), 0.45, 1.0 - dc_z);
	return top * mix(1.0, 0.65, smoothstep(30.0, 70.0, water_cam_pos.y - world_y));
}
// deep wet sheen of the procedural skin: (roughness, specular). No clearcoat anywhere on the creature: Godot's
// clearcoat lobe is near-mirror (roughness mapped to 0.001-0.1) and full strength at grazing angles, which throws
// HDR fireflies (and NaN pixels) on curved wet skin.
vec2 proc_gloss(float shimmer, float blot, float gl) {
	return vec2(mix(0.62, 0.48, shimmer) - blot * 0.06, mix(0.22, 0.32, gl));
}
