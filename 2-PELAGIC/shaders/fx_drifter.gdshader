shader_type spatial;
// Gelatinous drifters of the open blue (scripts/fauna/Drifters.gd): salp chains and a long siphonophore, one
// MultiMesh instance per zooid, bell, stem segment or cormidium (a unit sphere stretched along its Y axis by the
// instance transform). INSTANCE_CUSTOM = (s: position along the animal 0..1, kind + seed (kind = integer part:
// 0 salp zooid, 1 stem, 2 swimming bell, 3 cormidium), window start, window end (story clock, s)).
// Look: glass in water, read by its rim and its gut, never by a filled body.
// Glass parts (salp zooids, swimming bells) are traced per pixel as the exact ellipsoid of their instance (the low
// sphere mesh, drawn 1.3x larger, only bounds it): the polygon edges of a 6-sided sphere drew every zooid as a crisp
// little pill. The clear centre shows the water and rock behind it (alpha ~0.28, slightly displaced: refraction);
// a wide rim band, measured in projected radius so it survives on 8-15 px zooids, is where the light is bent away
// (a little darker) and the surface catches the light from above (a faint, iridescent sheen; forward scatter when
// looking towards the light), alpha ~0.65; the silhouette fades out over at least ~1.5 px (no outline). A salp's
// small dark-amber gut sits on the long axis near one end of its barrel, traced as a sphere along the view ray, so
// it is seen from any side (the dark beads that give a real salp chain away).
// The thin parts of the siphonophore (stem, cormidia) keep the filled, coverage-faded look: never drawn thinner
// than ~1.2 px, they fade with their coverage instead of breaking into dots.
// Nothing is brighter than the open water of the frame (at most 1.4x in linear light, ~1.15x in pixel values, the
// far water at the frame's highest direction or in the view direction, or 1.15x what lies behind), and every animal
// fades in and out on the story clock (no pop).
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, world_vertex_coords;

#include "res://shaders/water_common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float story_t = 0.0;        // Game.path_time, kept current by Drifters.gd
uniform float sway = 0.22;          // m: slow undulation of the animals

varying float v_alpha;   // presence (time window) x coverage (thin parts)
varying float v_kind;
varying float v_seed;
// the part's ellipsoid (world space, after the sway): centre and the columns of the inverse of its linear map
varying vec3 v_ctr;
varying vec3 v_i0;
varying vec3 v_i1;
varying vec3 v_i2;
varying vec4 v_gut;      // salp gut: centre (world) and radius (m); radius 0 for the other kinds

// normalize() that never returns NaN (a NaN pixel shows black and the glow pass blooms it into a disc)
vec3 safe_norm(vec3 v, vec3 fb) {
	float l2 = dot(v, v);
	return l2 > 1e-12 ? v * inversesqrt(l2) : fb;
}

bool is_glass(float kind) {
	return kind < 0.5 || (kind > 1.5 && kind < 2.5);
}

void vertex() {
	float s = INSTANCE_CUSTOM.x;
	v_kind = floor(INSTANCE_CUSTOM.y);
	v_seed = fract(INSTANCE_CUSTOM.y);
	vec4 w = INSTANCE_CUSTOM;
	float pres = smoothstep(w.z, w.z + 5.0, story_t) * (1.0 - smoothstep(w.w - 5.0, w.w, story_t));
	// never thinner than ~1.2 px across: thin parts are inflated about their axis and fade with their coverage
	vec3 ctr = MODEL_MATRIX[3].xyz;
	vec3 ax = MODEL_MATRIX[1].xyz;
	vec3 axn = safe_norm(ax, vec3(0.0, 1.0, 0.0));
	float hl = length(ax);
	float rad = max(length(MODEL_MATRIX[0].xyz), 1e-4);
	float dist = max(length(ctr - water_cam_pos), 0.05);
	float mpp = 2.0 * dist / max(abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y, 1.0);   // metres per pixel
	float infl = max(1.0, 0.6 * mpp / rad);
	vec3 rel = VERTEX - ctr;
	// the true normal of the stretched sphere (the engine carries a MultiMesh normal through the plain instance
	// matrix, which bends it towards the long axis of a thin segment): the unit sphere's normal is its position
	mat3 minv = inverse(mat3(MODEL_MATRIX));
	NORMAL = safe_norm(transpose(minv) * (minv * rel), axn);
	vec3 along = axn * dot(rel, axn);
	// slow undulation travelling along the animal (coherent over neighbouring segments; one offset per part)
	float ph = s * 5.0 + v_seed * 31.0;
	vec3 sw = vec3(sin(TIME * 0.21 + ph), 0.6 * sin(TIME * 0.17 + ph * 0.74 + 1.3), cos(TIME * 0.19 + ph * 0.86 + 0.4))
		* sway;
	// a glass part is traced per pixel: its mesh only has to bound the ellipsoid (the faces of the low sphere lie
	// inside the true surface, down to ~0.82 of the radius; 1.3x puts them all outside)
	float grow = is_glass(v_kind) ? 1.3 : 1.0;
	VERTEX = ctr + sw + (along + (rel - along) * infl) * grow;
	v_ctr = ctr + sw;
	// inverse of the inflated map (cross axes x infl): the rows 0 and 2 of minv divided by infl
	vec3 ri = vec3(1.0 / infl, 1.0, 1.0 / infl);
	v_i0 = minv[0] * ri;
	v_i1 = minv[1] * ri;
	v_i2 = minv[2] * ri;
	// a salp's gut (nucleus): a small sphere on the long axis, near the back end of the barrel
	v_gut = vec4(ctr + sw - axn * hl * 0.55, v_kind < 0.5 ? 0.4 * rad : 0.0);
	v_alpha = pres / infl;
}

void fragment() {
	if (v_alpha < 0.002) {
		discard;
	}
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 vd = safe_norm(wp - cam, vec3(0.0, 0.0, -1.0));
	bool glass = is_glass(v_kind);
	// the exact ellipsoid along this pixel's ray (in the unit sphere's space): rr = distance of the ray from the
	// centre (0 centre .. 1 silhouette, the projected radius), pc = the ray's closest point to the centre
	mat3 mi = mat3(v_i0, v_i1, v_i2);
	vec3 o = mi * (cam - v_ctr);
	vec3 dr = mi * vd;
	float aa = max(dot(dr, dr), 1e-12);
	vec3 pc = o - dr * (dot(o, dr) / aa);
	float rho2 = dot(pc, pc);
	float rr = sqrt(max(rho2, 0.0));
	float fw = fwidth(rr);
	// the gut: distance of the gut's centre from this pixel's ray, and the pixel size there (m)
	float dg = length(cross(v_gut.xyz - cam, vd));
	float pw = max(fwidth(dg), 1e-5);
	if (glass && rr >= 1.0) {
		discard;
	}
	vec3 n;
	if (glass) {
		vec3 hit = pc - dr * sqrt(max(1.0 - rho2, 0.0) / aa);
		n = safe_norm(transpose(mi) * hit, -vd);
	} else {
		n = safe_norm((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, -vd);
	}
	float c = clamp(-dot(n, vd), 0.0, 1.0);
	float d = max(-wp.y, 0.0);
	// the light around: the glow overhead on the upper side, the sideways water below it
	vec3 l_top = wb_zenith(d) * 1.35;
	vec3 l_side = wb_water_col(d + 18.0);
	float up = smoothstep(-0.35, 0.9, n.y);
	vec3 lin = mix(l_side, l_top, up);
	// forward scatter: looking towards the light, the glassy tissue glows (the rims most); looking away or down
	// it is lit from above only
	float fs = max(dot(vd, safe_norm(water_sun_dir, vec3(0.0, 1.0, 0.0))), 0.0);
	fs *= fs;
	float glow_up = smoothstep(0.0, 0.7, vd.y);
	float e = 1.0 - c;
	// the water behind, displaced by the curved surface (refraction)
	vec3 nv = safe_norm((VIEW_MATRIX * vec4(n, 0.0)).xyz, vec3(0.0, 0.0, 1.0));
	vec2 off = vec2(nv.x, -nv.y) * e * 0.004;
	vec3 bg = textureLod(screen_tex, clamp(SCREEN_UV + off, vec2(0.001), vec2(0.999)), 0.0).rgb;
	// faint thin-film iridescence along the rim (a comb-jelly shimmer, hue turning with the angle)
	vec3 irid = 0.5 + 0.5 * cos(6.2831853 * (c * 1.6 + v_seed + vec3(0.0, 0.33, 0.67)));
	vec3 col;
	float a;
	if (glass) {
		// the silhouette fades out over at least ~1.5 px (a small zooid is soft all over rather than outlined)
		float wf = clamp(1.5 * fw, 0.12, 0.7);
		float fade = 1.0 - smoothstep(1.0 - wf, 1.0, rr);
		// the rim band (rising over the outer two thirds of the projected radius): light bent away, a sheen from
		// above. A zooid only a few pixels across has no room for a clear centre and a rim: it is all rim, a soft
		// pale bead (a far chain stays a faint dotted line instead of vanishing)
		float small = smoothstep(0.2, 0.45, fw);
		float band = mix(smoothstep(0.3, 0.9, rr), 1.0, small);
		// (the sheen comes from above: the upper rim catches the light, the lower one bends the darker water below
		// into view; a lit glass barrel, not a drawn outline)
		col = bg * mix(0.96, mix(0.8, 0.92, up), band);
		col += lin * mix(vec3(1.0), irid * 1.2, 0.25) * band * 0.32 * (0.2 + 1.0 * up + 1.2 * fs * glow_up);
		// the tissue scatters a very little of the light around
		col += lin * 0.04;
		a = mix(0.28, 0.72, band) * fade;
		if (v_gut.w > 0.0) {
			// salp: the small dark-amber gut seen through the clear barrel, from any side (never under ~1.4 px
			// across: a smaller one fades with its coverage)
			float gr = max(v_gut.w, 0.7 * pw);
			float gcov = v_gut.w / gr;
			gcov *= gcov;
			float gut = (1.0 - smoothstep(gr - 0.6 * pw, gr + 0.6 * pw, dg)) * gcov;
			// (in the shade of the body: the blue light leaves an amber gut dark)
			vec3 gutc = vec3(0.42, 0.2, 0.07) * l_side * 0.7;
			col = mix(col, gutc, gut * 0.9);
			a = max(a, gut * 0.65);
		}
	} else {
		// thin stem and cormidia: a filled thread and beads, soft at the silhouette
		float rim = e * e * smoothstep(0.0, 0.3, c);
		float edge = smoothstep(0.75, 0.05, c);
		col = bg * mix(0.93, 0.66, edge);
		col += lin * mix(vec3(1.0), irid * 1.2, 0.2) * rim * (0.8 + 1.0 * up + 1.5 * fs * glow_up);
		col += lin * (0.1 + 0.08 * up);
		a = 0.85 * smoothstep(0.0, 0.3, c);
		if (v_kind < 1.5) {
			// stem: a pale, slightly pinkish thread
			col += lin * vec3(0.12, 0.08, 0.1) * (0.4 + 0.6 * up);
		} else {
			// cormidium: warm pink-orange tissue, which the blue light down here turns dusky
			col = mix(col, vec3(0.9, 0.35, 0.25) * lin * 1.4, 0.55);
		}
	}
	// never brighter than the open water of the frame: the far water in the highest direction the frame shows (the
	// water brightens upwards; its top edge, or the zenith when that is in view) or in this direction, or a little
	// over what lies behind
	float dcam = max(-cam.y, 0.0);
	vec3 fwd = safe_norm(-INV_VIEW_MATRIX[2].xyz, vec3(0.0, 0.0, -1.0));
	float half_fov = atan(1.0 / max(abs(PROJECTION_MATRIX[1][1]), 1e-3));
	float top_y = sin(min(asin(clamp(fwd.y, -1.0, 1.0)) + half_fov, 1.5707963));
	vec3 top_dir = vec3(sqrt(max(1.0 - top_y * top_y, 0.0)), top_y, 0.0);
	// (1.4x in linear light is ~1.15x in pixel values: a rim catching the light from above may just outshine the
	// dark water of a frame that looks down, never glow)
	vec3 water = max(wb_backdrop(vd, dcam, 1.0), wb_backdrop(top_dir, dcam, 1.0)) * 1.4;
	col = min(col, max(bg * 1.15, water) + vec3(0.002));
	ALBEDO = col;
	ALPHA = clamp(a * v_alpha, 0.0, 1.0);
	FOG = water_fog(wp);
}
