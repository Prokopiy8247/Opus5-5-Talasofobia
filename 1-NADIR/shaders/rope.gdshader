shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Weathered descent line (ROPE LOOK CONTRACT): a 56 mm 3-strand laid rope (0.18 m lay, rounded strand crowns,
// counter-laid yarns, loose fibres) that fades to a plain tone once the strands get smaller than a pixel (no
// moire); a radius that inflates with distance so the line never breaks into dashes (>= ~1.3 px), and its
// brightness scaled by the true coverage of that inflated width, so far away it reads as a thin dim thread
// instead of a glowing bar. The tube is wound clockwise from outside, so the near half is drawn and lit.
// Never a bar: the round tube darkens toward its limbs, the wet strand crowns catch thin glints, in the blue
// the line answers the water light around it (water_lin, set by Rope.gd; it is 0 below the lit zone and on the
// B6 coil), and while the torch is on the metre or two in front of the mask is exposure-compensated (near_comp)
// so the line beside the diver is never the brightest thing in the beam.
uniform vec4 rope_col : source_color = vec4(0.31, 0.275, 0.21, 1.0);
uniform vec3 water_lin = vec3(0.0);      // eye-adapted water colour (linear); Rope.gd, fades out by 520 m
uniform float amb_gain = 1.15;           // water-light response of the line in the blue
uniform float near_comp = 1.0;           // the B6 coil and remnants set 0
uniform float near_on = 0.0;             // Rope.gd: 1 while the torch is on, eases back to 0 over 3 s after it dies
// Caustic net of the sunlit shallows: the same cellular texture and scrolls as the sun rays (sun_rays.gdshader),
// so the line brightens in moving bands exactly where it crosses a ray sheet. Rope.gd builds the texture.
uniform sampler2D caustic_tex : filter_linear_mipmap, repeat_enable;
uniform float caustic_k = 3.5;           // x water luminance: the line peaks near ~1.2x the water behind it
global uniform float g_time;
global uniform float g_torch;
global uniform float g_daylight;
const float BASE_R = 0.028;
const vec3 TO_SUN = vec3(0.3403, 0.9007, 0.2702);   // = -WaterEnv.SUN_DIR, as in sun_rays.gdshader

varying float cover;
varying vec3 v_wp;

// = rays_at() of sun_rays.gdshader (no boat term), at the point itself.
float caustic_at(vec3 p) {
	vec2 q = p.xz - TO_SUN.xz * (p.y / TO_SUN.y);
	float dep = max(-p.y, 0.0);
	float lod = clamp(dep / 28.0, 0.0, 5.0);
	vec2 w = vec2(sin(q.y * 0.07 + g_time * 0.31), cos(q.x * 0.06 - g_time * 0.27)) * 1.6;
	float a = textureLod(caustic_tex, (q + w) / 64.0 + g_time * vec2(0.004, 0.0025), lod).r;
	float b = textureLod(caustic_tex, (q - w) / 41.0 - g_time * vec2(0.003, -0.004), lod).r;
	float c = pow(1.0 - a, 7.0) * pow(1.0 - b, 3.5);
	c = max(c - 0.04, 0.0) * (1.0 / 0.96) * mix(0.35, 1.0, smoothstep(0.0, 4.0, dep));
	return c * exp(-dep / 45.0);
}

// Slow sway of the hanging line in the current: waves travelling down from the boat, a few cm at depth,
// up to ~9 cm near the surface, zero at the top and on the floor (the B6 coil and remnants never move).
// Must match Rope.sway() exactly: the tags, tapes and weight ride on the same curve.
vec3 rope_sway(float depth, float t) {
	float amp = 0.03 * smoothstep(0.0, 10.0, depth) + 0.10 * (1.0 - exp(-depth / 5.0)) * exp(-depth / 35.0);
	amp *= 1.0 - smoothstep(1490.0, 1550.0, depth);
	return amp * vec3(0.7 * sin(0.105 * depth - 0.70 * t) + 0.3 * sin(0.043 * depth - 0.37 * t + 1.3), 0.0,
		0.7 * sin(0.083 * depth - 0.55 * t + 2.1) + 0.3 * sin(0.031 * depth - 0.29 * t + 4.0));
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 sw = rope_sway(-wp.y, g_time);
	wp += sw;
	float d = length(wp - CAMERA_POSITION_WORLD);
	float r = max(BASE_R, d * 0.00104);   // ~0.65 px at 72 deg / 720p
	cover = BASE_R / r;
	v_wp = wp;
	// NORMAL points outward: the tube only ever grows. Line meshes are built in world space (identity
	// transforms), and the sway is zero wherever another user of this shader (the B6 floor) places a mesh.
	VERTEX += NORMAL * (r - BASE_R) + sw;
}

void fragment() {
	// 3 strands with a 0.18 m lay (UV.y unit = 0.09 m; v0 wraps at 100 units = 150 strand periods, seamless)
	float ph = fract(3.0 * UV.x + 1.5 * UV.y);
	float crown = sqrt(max(1.0 - pow(2.0 * ph - 1.0, 2.0), 0.0));      // rounded strand cross-section
	float yarn = sin((12.0 * UV.x - 9.0 * UV.y) * 6.2831);             // counter-laid yarns inside each strand
	// pattern cycles per pixel: fade each scale before it aliases
	float aa = 1.0 - smoothstep(0.2, 0.55, fwidth(UV.y) * 1.5 + fwidth(UV.x) * 3.0);
	float ya = 1.0 - smoothstep(0.2, 0.55, fwidth(UV.y) * 9.0 + fwidth(UV.x) * 12.0);
	float fib = fract(sin(dot(floor(UV * vec2(24.0, 60.0)), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	float groove = (1.0 - smoothstep(0.0, 0.35, crown)) * aa;           // dark lay grooves between strands
	float shade = mix(0.82, 0.42 + 0.5 * crown + 0.07 * yarn * crown * ya + 0.08 * fib * ya, aa);
	// A round tube: darker toward the limbs. Only where the tube is several pixels wide; a thread of 1-3 px
	// keeps its old flat tone (the far line stays as it was).
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float wide = 1.0 - smoothstep(0.12, 0.4, fwidth(UV.x));
	float limb = mix(1.0, mix(0.3, 1.0, sqrt(ndv)), wide);
	// Near-exposure compensation, only while the torch is on and only within ~6 m of the eye: at arm's length the
	// line takes several times the torch light of steel 15-30 m away. It switches with the torch being on (not its
	// level), so a stutter or the dying torch dims the line with everything else instead of brightening it.
	// Looking down near the floor the line hangs over lit silt, not black water: lift most of the compensation
	// there, or the line turns into a black bar (INV_VIEW_MATRIX[2].y > 0 when the camera pitches down).
	float down = smoothstep(0.3, 0.7, INV_VIEW_MATRIX[2].y) * smoothstep(1490.0, 1530.0, -v_wp.y);
	float on = max(near_on, smoothstep(0.0, 0.004, g_torch)) * near_comp * (1.0 - 0.8 * down);
	float near_k = mix(1.0, mix(0.16, 1.0, smoothstep(1.0, 6.0, length(VERTEX))), clamp(on, 0.0, 1.0));
	float cv = max(cover, 0.05);
	ALBEDO = rope_col.rgb * shade * limb * near_k * cv;
	// wet strand crowns: thin glints along each strand, matte in the grooves
	ROUGHNESS = mix(0.5, 0.9, groove);
	SPECULAR = 0.3 * cv * (1.0 - groove) * near_k;
	// Water light in the blue: a brown line under pure-blue ambient would go black (the downwell points straight
	// down at a near-vertical line). A hemispherical response, brighter on the side facing the sun's azimuth and
	// from above, plus the backlit fibres at the silhouette.
	vec3 nw = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float sunside = 0.5 + 0.5 * dot(nw, vec3(0.783, 0.0, 0.622));
	float hemi = mix(0.15, 1.0, clamp(0.6 * sunside + 0.4 * (0.5 + 0.5 * nw.y), 0.0, 1.0));
	float limb_e = mix(1.0, mix(0.65, 1.0, sqrt(ndv)), wide);
	// in the bright shallows the sun and ambient already light the line: less water light there
	float shallow = 1.0 - 0.6 * smoothstep(0.2, 0.8, g_daylight);
	EMISSION = water_lin * (amb_gain * hemi * shade * limb_e + 0.2 * pow(1.0 - ndv, 3.0) * wide) * cv * shallow;
	// moving caustic bands in the sunlit shallows (nothing once the daylight is gone, ~150 m)
	if (g_daylight > 0.003) {
		float wl = dot(water_lin, vec3(0.2126, 0.7152, 0.0722));
		EMISSION += vec3(0.55, 0.85, 0.80) * caustic_at(v_wp) * max(dot(nw, TO_SUN), 0.0) * g_daylight * caustic_k
			* wl * shade * cv;
	}
}
