shader_type spatial;
// Reef rock (wall, crest, plateau, lip): vertex colour = rock albedo (linear) with AO in alpha, UV = (life cover,
// colour bias). Per pixel: continuous multi-scale mottling of encrusting life through a muted ramp (no hard
// patches), bare rock where cover is low, rock relief at three scales plus a macro relief that never fades, depth
// colour loss, direction-aware water fill, sun caustics in direct sun only (light()), shared water fog.
render_mode cull_disabled, depth_draw_opaque;
#include "res://shaders/water_common.gdshaderinc"
#include "res://shaders/reef_common.gdshaderinc"

// The lip roof (Beat03_Lip sets these on its own copy of the material; 0 everywhere else): its undersides are lit
// sideways by the open blue off the path side, so facets that turn towards it catch light and facets that turn back
// towards the face, or along the wall, stay dark (the generic down-facing fill is the abyss colour, the same for every
// facet); the lip's ends, where the shelf runs into the face, stay as dark as the face.
uniform float roof_open = 0.0;
uniform vec3 roof_centre = vec3(-68.0, -84.0, -384.0);   // ReefRoof.C: horizontal 'out' = away from it
uniform float roof_side = 4.0;     // side scatter from the open water onto facets turned towards the open blue
uniform float roof_floor = 0.1;    // the water column below seen by every open underside facet
uniform float roof_bump = 1.5;     // extra macro relief for the side light's orientation (x the shared macro height)
uniform float roof_blue = 0.85;    // how far 'out' turns from the radial direction towards the open blue (+X)
uniform float roof_end = 0.12;     // what is left of the side light at the lip's ends
uniform float roof_soft = 0.6;     // calmer encrusting-life blotches and nodule crackle on the lit undersides

varying vec3 v_w;
varying vec3 v_n;
varying vec3 v_caus;     // fragment -> light: caustic multiplier on the sun
varying float v_f0;      // fragment -> light: specular reflectance
varying vec3 v_sn;       // the lip roof: its form's normal smoothed over ~2 m (ReefRoof CUSTOM0; zero on other rock)

void vertex() {
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_n = rf_safe_normal((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz, vec3(0.0, 1.0, 0.0));
	v_sn = roof_open > 0.0 ? (MODEL_MATRIX * vec4(CUSTOM0.xyz, 0.0)).xyz : vec3(0.0);
}

void fragment() {
	// reef meshes are only ever seen from their outside: trust the stored normal (guarded: across a sharp fold the
	// interpolated normal can pass through zero)
	vec3 n = rf_safe_normal(v_n, vec3(0.0, 1.0, 0.0));
	float dist = length(v_w - water_cam_pos);
	float depth = -v_w.y;
	float near = 1.0 - smoothstep(10.0, 45.0, dist);
	float mid = 1.0 - smoothstep(40.0, 160.0, dist);
	vec3 p = v_w;
	vec3 pr = RF_ROT * p;
	vec3 pq = RF_ROT * pr;
	float g1 = rf_noise(p * 0.8);
	float g2 = rf_noise(pr * 2.3 + 11.0);
	float g3 = rf_noise(pq * 6.1 + 5.0);
	float cover = UV.x;
	// warped multi-scale field: where life grows and which colour it has
	vec3 wv = vec3(rf_noise(p * 0.21), rf_noise(p * 0.21 + 19.1), rf_noise(p * 0.21 + 37.7)) - 0.5;
	vec3 q = p + wv * 5.0;
	float f1 = rf_noise(RF_ROT * q * 0.35);
	float f2 = rf_noise(q * 1.1 + 3.0);
	float f3 = rf_noise(pr * 3.2 + 9.0);
	float grow = smoothstep(0.34, 0.6, 0.38 * f1 + 0.36 * f2 + 0.26 * mix(0.5, f3, mid) + cover * 0.55 - 0.3);
	// lip undersides: lit by the even side light of the water and not by the sun, the albedo pattern shows on its own
	// there (no sunlit relief over it): calmer life blotches and nodule crackle, or they read as camouflage and scales
	float soft = roof_open > 0.0 ? roof_soft * roof_open * smoothstep(0.1, -0.5, n.y) : 0.0;
	grow = mix(grow, 0.45, 0.5 * soft);
	float hue = 0.45 * f1 + 0.37 * f2 + 0.18 * mix(0.5, f3, mid) + UV.y * 0.45;
	vec3 life = rf_ramp(hue * 1.7) * (0.75 + 0.5 * mix(0.5, g3, near)) * (0.8 + 0.35 * mix(0.5, f3, mid));
	vec3 rock = COLOR.rgb * (0.72 + 0.4 * g1) * (0.86 + 0.28 * mix(0.5, g2, mid));
	vec3 col = mix(rock, life, grow * 0.85);
	// relief: rock lumps, crusts slightly raised, fine grain close up
	float h = 0.3 * g1 + 0.14 * g2 + 0.05 * g3 * near + 0.06 * grow * f2;
	if (near > 0.0) {
		// crunchy nodules (polyp heads, rubble, crust knobs) with dark gaps between them
		vec3 cb = rf_cells(pq * 3.4 + wv * 2.0);
		float gap = smoothstep(0.0, 0.3, cb.y - cb.x);
		h += (0.06 * (1.0 - smoothstep(0.0, 0.7, cb.x)) + 0.03 * gap) * near;
		float crk = near * (1.0 - 0.75 * soft);
		col *= mix(1.0, 0.7 + 0.3 * gap, crk * (0.5 + 0.5 * grow));
		col *= mix(1.0, 0.85 + 0.3 * fract(cb.z * 7.7), crk * grow);
	}
	// macro relief and tone (6-40 m), kept at every distance: no single flat tone on far rock
	vec2 mac = rf_macro(p);
	col *= 0.74 + 0.52 * mac.y;
	h = h * 0.75 * (1.0 - smoothstep(25.0, 110.0, dist)) + mac.x;
	vec3 nb = rf_bump(v_w, n, h, 1.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(nb, 0.0)).xyz);
	col = rf_depth_mute(col, depth);
	float ao = clamp(COLOR.a, 0.0, 1.0) * (0.82 + 0.18 * smoothstep(0.2, 0.7, g2)) * (0.8 + 0.2 * smoothstep(0.6, 2.6, mac.x));
	vec3 rl = water_rel_light(v_w.y);
	ALBEDO = col * ao * rl;
	// water fill: what the surrounding water scatters onto the rock along its normal (dark under overhangs; the
	// vertex AO carries the openness of the lip underside, dark toward the wall, opening toward the rim)
	EMISSION = col * ao * sqrt(ao) * rl * rf_water_fill(nb, -water_cam_pos.y) * 0.25;
	if (roof_open > 0.0) {
		// lip underside: oriented side scatter from the open water around the roof. Facets turned out towards the rim
		// (tier lips, keel flanks, the outer sides of hanging masses) catch the horizontal water; facets turned back
		// towards the face see rock and stay dark; the baked openness (vertex AO: dark towards the wall, open towards
		// the rim) scales both, so the recess next to the wall stays the darkest part of the roof.
		// The orientation comes from the form only: the form's normal smoothed over ~2 m (so the light changes across a
		// crevice or a block crease as a gradient, not as a step between flat sheets: crumpled paper; the tiers, masses
		// and keels still turn it), tilted by the macro relief (strengthened) and the metre-scale lumps. The fine crust
		// relief's screen-space normal is constant per 2x2 pixel quad, which a direction-sensitive light this strong
		// turns into blocky pixel noise. (The tilt is found on the true facet normal and carried over to the smoothed
		// one: the screen-space bump needs the normal of the surface it differentiates.)
		float hs = mac.x * (1.0 + roof_bump) + 0.3 * g1 * 0.75 * (1.0 - smoothstep(25.0, 110.0, dist));
		vec3 ns = rf_safe_normal(rf_safe_normal(v_sn, n) + rf_bump(v_w, n, hs, 1.0) - n, n);
		float und = roof_open * smoothstep(0.1, -0.5, ns.y);
		// where the light comes from: the open blue lies off the path side (+X). The wall fills the other half of every
		// horizontal view and the roof the view back towards its root, so 'out' is the radial direction turned most of
		// the way towards +X: at the lip's ends the facets that face back along the path (towards the approaching
		// diver) look along the wall, not into the open blue, and stay dim
		vec2 rd = v_w.xz - roof_centre.xz;
		float rdl = length(rd);
		rd = rdl > 1e-3 ? rd / rdl : vec2(1.0, 0.0);
		vec2 od = mix(rd, vec2(1.0, 0.0), roof_blue);
		float odl = length(od);
		od = odl > 1e-3 ? od / odl : vec2(1.0, 0.0);
		float hzl = length(ns.xz);
		float facing = hzl > 1e-3 ? dot(ns.xz, od) / hzl : 0.0;
		float open = smoothstep(0.25, 0.75, COLOR.a);
		// the lip's ends (radial direction swinging round to +-Z): the shelf narrows into the face and lies in the
		// wall's shadow, as dark as the face it grows from; the full side light only where the roof reaches far out
		// over the path
		float reach = mix(roof_end, 1.0, smoothstep(0.58, 0.96, rd.x));
		// the horizontal water's light, half way to grey-blue: rock lit by it keeps the grey-blue of the sunlit rock
		// elsewhere instead of turning electric blue
		vec3 hz = wb_backdrop(vec3(1.0, 0.0, 0.0), -water_cam_pos.y, 0.0);
		hz = mix(hz, dot(hz, WB_LUMA) * vec3(0.75, 0.95, 1.3), 0.5);
		float side = hzl * smoothstep(-0.2, 0.9, facing) * mix(0.15, 1.0, open * open);
		EMISSION += col * rl * hz * (roof_side * side + roof_floor * open) * und * reach;
	}
	v_caus = rf_caustic(v_w, TIME);
	v_f0 = 0.16 * 0.04 * water_spec_dim(v_w.y);
	ROUGHNESS = 0.92;
	SPECULAR = 0.2 * water_spec_dim(v_w.y);
	FOG = rf_fog(v_w);
}

void light() {
	vec3 k = LIGHT_IS_DIRECTIONAL ? v_caus : vec3(1.0);
	DIFFUSE_LIGHT += rf_light_diffuse(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, k);
	SPECULAR_LIGHT += rf_light_specular(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, ROUGHNESS, v_f0) * k;
}
