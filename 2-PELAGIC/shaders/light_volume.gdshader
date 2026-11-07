shader_type spatial;
// Near-field sun rays around the diver. A few camera-facing slices (one mesh, far to near, 8.7-60 m) each stand for a
// thick slab of water; the slabs tile the view depth in log steps from ~6 to ~83 m (WaterWorld does not build the
// nearest slice of the spacing, 3-6 m: almost no water, and the pattern fades in from 6 m). Each slab adds to the
// picture the DIFFERENCE between the light its water scatters towards the eye with a caustic ray pattern projected
// along the refracted sun (beams where the surface focuses the light, darker gaps between them), cut by the sun's
// shadow map in light() (the lip, the boat, schools), and the average in-scatter the water fog has already put there.
// The beam pattern is INTEGRATED over the slab, not sampled at the slice plane: along the view ray through the slab,
// the point where the light entered the water slides across the surface by the slab's footprint, and the beam field
// is averaged over that segment (trilinear lookups of a mipmapped, pre-shaped field, a few per slab, each
// blurred over its share). A beam crossing the slab draws as the streak it really is and joins the streaks of the
// neighbouring slabs; it never shows as a disc where it cuts the slice plane. Seen along the light (up at the sun,
// down into the abyss) the streaks converge on the light axis: a sunburst overhead, rays sinking into the abyss.
// Rays read by contrast; the mean fog and anything behind the water (reef, creature) are not fogged a second time.
// Signed additive blend: EMISSION removes the average (never more than the fog added), ALBEDO * shadow adds the
// patterned light back.
// Cost: each layer is a full-screen blend + one shadow lookup + 11 trilinear lookups + the depth; colour and
// opacity are computed per vertex on a coarse grid (they vary slowly over the screen). ~0.72 ms for the 4 layers at
// 1080p MSAA 4 (RTX 5070, -- --ray-bench). Hardware anisotropic lookups drew sharper streaks but cost ~2.5 ms.
// No hardware depth test: a slab that straddles a surface must count partly, not vanish at the slice plane (that
// drew contour steps on the reef and on the surface seen edge-on); the slab simply ends where the scene begins.
render_mode blend_add, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, ambient_light_disabled, specular_disabled, skip_vertex_transform;
#include "res://shaders/water_common.gdshaderinc"

uniform float near_d = 4.5;           // first slice of the log spacing (view depth, m; that slice itself is not built)
uniform float far_d = 60.0;           // last slice
uniform float slices = 5.0;           // slices of the log spacing (WaterWorld.RAY_SLICES; the mesh has one fewer)
uniform float amount = 1.0;           // overall strength (story schedule, depth, swell flicker)
uniform float strength = 0.55;        // ray contrast: how strongly the pattern and the shadows re-shape the in-scatter
uniform float wide_gain = 0.85;       // contrast of the wide veils
uniform float fine_gain = 0.85;       // contrast of the narrow focused beams (mostly near the surface)
uniform float lift = 0.22;            // looking down: rays a little brighter than the dark water behind them
uniform float tint_mix = 0.45;        // how much of the sunlight colour the beams carry (rest: the water colour)
uniform float fine_norm = 6.3;        // 1 / mean of the narrow beam field (R, G), measured when the field is baked
uniform float wide_norm = 3.05;       // 1 / mean of the wide veil field (B)
// Seamless noises, shaped BEFORE the mipmaps were built (WaterWorld._ray_noise): R and G two shapes of the narrow
// focus pattern (the beams morph from one to the other), B wide veils, A a raw noise. A blurred lookup is therefore
// the true average of the beam field.
uniform sampler2D ray_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 v_world;
varying float v_s;      // view depth of this slice
varying vec3 v_col;     // patterned in-scatter colour: the water in this direction with the sunlight tint of this depth
varying vec3 v_bg;      // the average in-scatter colour the fog already holds (the water in this direction)
varying float v_w;      // fraction of the fog's in-scatter that comes from this slab
varying float v_g;      // ray contrast for this slab (story amount, forward scatter)
varying float v_axis;   // pattern contrast kept (low right on the light axis)

// half the log-thickness of a slab: slab i covers view depths s_i * exp(-h) .. s_i * exp(h), and the slabs tile
float slab_h() {
	return 0.5 * log(far_d / near_d) / max(slices - 1.0, 1.0);
}

void vertex() {
	float f = UV2.x;                                       // 0 = nearest slice, 1 = farthest
	float s = near_d * pow(far_d / near_d, f);
	vec2 ndc = UV * 2.0 - 1.0;
	// a grid that exactly covers the view frustum at depth s (a small margin against edge gaps)
	VERTEX = vec3(ndc.x * s / PROJECTION_MATRIX[0][0], ndc.y * s / PROJECTION_MATRIX[1][1], -s) * vec3(1.03, 1.03, 1.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world = wp;
	v_s = s;
	vec3 sun = normalize(water_sun_dir);
	vec3 rel = wp - water_cam_pos;
	float r = length(rel);
	vec3 vdir = rel / max(r, 1e-3);
	// in-scatter weight of this slab: the water's own fog law between its near and far faces
	float h = slab_h();
	float sig = water_fog_density;
	v_w = exp(-sig * r * exp(-h)) - exp(-sig * r * exp(h));
	// forward scatter: strongest towards the light, but the rays must still read in the main gaze (60-90 degrees
	// from the sun, where the diver looks)
	float ph = mix(0.6, 1.9, pow(max(dot(vdir, sun), 0.0), 2.0));
	v_g = strength * amount * ph;
	// Right on the light axis the slab footprint shrinks to nothing (one looks along the beams), so the pattern there
	// is only the cross-section of the beam the diver happens to be in: kept faint. Further out the integrated streaks
	// converge on the axis (a soft sunburst overhead, rays sinking into the abyss below), at reduced contrast.
	float ax = dot(vdir, sun);
	float axis_cut = max(0.92 * smoothstep(0.88, 0.985, abs(ax)), 0.3 * smoothstep(0.45, 0.88, -ax));
	axis_cut = max(axis_cut, 0.5 * smoothstep(0.62, 0.9, ax));
	v_axis = 1.0 - axis_cut;
	// the layer colour: the water in this direction, lifted a little when looking into the dark below, with part
	// of the sunlight colour at this depth in the beams
	float dcam = max(-water_cam_pos.y, 0.0);
	float dp = max(-wp.y, 0.0);
	vec3 bg = wb_backdrop(vdir, dcam, 1.0);
	float lb = max(dot(bg, WB_LUMA), 1e-4);
	float lh = dot(wb_water_col(dcam + 18.0), WB_LUMA);
	float lref = mix(lb, max(lh, lb), lift);
	vec3 tint = wb_light_tint(dp);
	tint *= lb / max(dot(tint, WB_LUMA), 1e-4);
	// (looking down from mid-depth the fog holds the darker nadir well of the sky: the slabs scale with it, so the
	// average they remove is still exactly what the fog added there)
	vec3 rl = water_rel_light(wp.y) * wb_nadir_well(vdir, dcam);
	v_col = mix(bg, tint, tint_mix) * (lref / lb) * rl;
	v_bg = bg * rl;
}

// Where the light now at p entered the water (m on the surface plane): projected back along the refracted sun.
vec2 ray_entry(vec3 p, vec3 sun) {
	return p.xz + sun.xz * (max(-p.y, 0.0) / max(sun.y, 0.2));
}

// Relative in-scatter (mean ~1) of the water between two points of a view ray (distances ra, rb from the eye) whose
// light entered the water at qa and qb: the beam field averaged over the segment qa..qb, so every bright spot becomes
// the streak its beam draws across the slab. dp: depth of the slab (for the pulses running down the beams).
// A beam passing a few metres from the eye would fill half the view: the pattern fades in over the first metres of
// the ray, per lookup, so a beam never steps in brightness where it crosses from one slab into the next.
float ray_field(vec2 qa, vec2 qb, float ra, float rb, float dp, float t, float cf, float cb) {
	vec2 dq = qb - qa;
	float fp = length(dq);
	// brightness varies slowly along each beam, and pulses run down it
	vec2 qm = qa + dq * 0.5;
	float n4 = textureLod(ray_noise, vec2(dot(qm, vec2(0.0071, 0.0043)) + dp * 0.004 - t * 0.02, dot(qm, vec2(-0.0049, 0.0083))), 0.0).a;
	// the focus pattern morphs from one shape to the other in broad bands (~300 m) drifting over the water; mostly one
	// shape or the other, with a quicker crossfade (two overlaid shapes read as a busier, blurrier pattern; half-way
	// the spread is kept constant). A phase that varied over a few metres spliced the two shapes into worm-like cells.
	float m = smoothstep(0.2, 0.8, 0.5 + 0.5 * sin(t * 0.45 + dot(qm, vec2(0.021, 0.013))));
	float morph_gain = inversesqrt(m * m + (1.0 - m) * (1.0 - m));
	// narrow focused beams: six lookups spread over the segment, each a trilinear average over its sixth of it, so the
	// streak stays continuous along its length and as sharp sideways as the budget allows. (A fixed count: a count
	// that changed with the footprint drew rings around the light axis where it switched.)
	const int NF = 6;
	float stepf = 1.0 / float(NF);
	float lodf = log2(max(fp * stepf * (256.0 / 26.0), 1.0));
	vec2 o1 = vec2(0.031, 0.017) * t;
	float fine = 0.0;
	for (int i = 0; i < NF; i++) {
		float k = (float(i) + 0.5) * stepf;
		vec2 pr = textureLod(ray_noise, (qa + dq * k) * (1.0 / 26.0) + o1, lodf).rg;
		fine += (mix(pr.x, pr.y, m) * fine_norm - 1.0) * smoothstep(6.0, 13.0, mix(ra, rb, k));
	}
	fine *= stepf * morph_gain;
	// wide veils: broad, slow, they survive deeper (four lookups: fewer drew them as round blobs)
	const int NW = 4;
	float stepw = 1.0 / float(NW);
	float lodw = log2(max(fp * stepw * (256.0 / 85.0), 1.0));
	vec2 o3 = vec2(0.006, -0.004) * t + vec2(0.17, 0.29);
	float wide = 0.0;
	for (int i = 0; i < NW; i++) {
		float k = (float(i) + 0.5) * stepw;
		wide += (textureLod(ray_noise, (qa + dq * k) * (1.0 / 85.0) + o3, lodw).b * wide_norm - 1.0)
			* smoothstep(6.0, 13.0, mix(ra, rb, k));
	}
	wide *= stepw;
	// The average over a long footprint is smoother than the field (its spread falls like 1/sqrt(footprint/beam
	// width)): the beams are made that much more concentrated there, so a streak seen from the side reads as clearly
	// as the light seen end-on, and the far slabs (most of the in-scatter) keep their rays.
	// A footprint shorter than a beam is wide (looking nearly along the light, or a short path up to the surface)
	// can only show the beam's cross-section, a soft blob: those slabs keep a fraction of the contrast.
	float bf = clamp(sqrt(fp * (1.0 / 2.0)), 1.0, 4.5) * mix(0.55, 1.0, smoothstep(0.5, 4.0, fp));
	float bw = clamp(sqrt(fp * (1.0 / 12.0)), 1.0, 1.6) * mix(0.5, 1.0, smoothstep(3.0, 18.0, fp));
	// veils modulate the beams (two independent factors of mean 1)
	return max(1.0 + cb * bw * wide, 0.0) * max(1.0 + cf * bf * fine, 0.0) * (0.65 + 0.7 * n4);
}

void fragment() {
	float s = v_s;
	float h = slab_h();
	float t0 = exp(-h);
	float t1 = exp(h);
	// the slab ends where the scene begins (reef, creature, surface): only the water in front of it scatters, and
	// only that part of the beams is integrated (soft: no contour lines where the slices cut the reef)
	float zb = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zb, 1.0);
	float scene_z = -sv.z / sv.w;
	float te = clamp(scene_z / s, t0, t1);
	float cover = (te - t0) / (t1 - t0);
	if (cover <= 0.0 || v_g <= 0.0) {
		discard;   // behind the reef / the creature / the surface, or rays off: skip all the work
	}
	vec3 sun = normalize(water_sun_dir);
	vec3 rel = v_world - water_cam_pos;
	float dp = max(-v_world.y, 0.0);
	// beam contrast: narrow beams strongest near the surface (still many, softer, deeper, so looking up at the sun
	// from the deep gives a soft sunburst, not a few-armed star); wide veils fade deeper
	float cf = fine_gain * mix(1.0, 0.45, smoothstep(6.0, 45.0, dp));
	// (and calmer in the first metres under the surface: seen towards the sun over a short path they only make a
	// glowing patch at the surface line)
	float cb = wide_gain * mix(1.0, 0.3, smoothstep(30.0, 140.0, dp)) * mix(0.4, 1.0, smoothstep(2.0, 12.0, dp));
	vec2 qa = ray_entry(water_cam_pos + rel * t0, sun);
	vec2 qb = ray_entry(water_cam_pos + rel * te, sun);
	float r = length(rel);
	float F = ray_field(qa, qb, r * t0, r * te, dp, TIME, cf, cb);
	F = 1.0 + (F - 1.0) * v_axis;
	float a = v_w * cover;
	ALBEDO = v_col * (F * a * v_g);
	EMISSION = -v_bg * (a * min(v_g, 1.0));
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		// ATTENUATION carries the reef, lip and boat shadows (in shadow: no rays, a darker slab). The colour is
		// already in ALBEDO (water colour + sunlight tint at this depth), so the mean colour of the water is kept.
		DIFFUSE_LIGHT += vec3(ATTENUATION);
	}
}
