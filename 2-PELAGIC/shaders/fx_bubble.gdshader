shader_type spatial;
// Diver exhale bubbles (scripts/fx/ExhaleBubbles.gd moves them; one MultiMesh instance per bubble). The instance
// transform carries position and radius; INSTANCE_CUSTOM = (age s, shape: 0 round / 0.5 wobbling / 1 mushroom cap,
// seed, alpha). Look: an air bubble in water is a silvery shell. Beyond the critical angle (total internal reflection,
// cos < ~0.66) its surface is a perfect mirror of the water light field: a crisp bright rim that is brightest
// where it reflects Snell's window and the sun (HDR, so the glow catches the glints), with a thin darker line just
// inside it. The centre is a clear air lens that shows the background minified (screen refraction) and almost no
// colour of its own. In the deep the rim reflects mostly the faint glow overhead, never anything darker than the
// water behind it. A mushroom cap seen from below is a wobbling mercury dome: its rippling flat base is a silvery
// mirror of the light above, filled, not an empty outline.
// Every thin line (the cap's edge, the TIR edge, the dark contour line) is kept at least ~1.2 px wide with its
// intensity scaled to keep its energy: seen from below these bands are far under a pixel and would alias into dots.
// A small round bubble (under ~14 px across its radius) is shaded as an exact sphere traced per pixel on a mesh
// drawn ~1.2 px larger, with an analytic, anti-aliased silhouette: its mirror rim lies right on the silhouette, and
// with the mesh's own edge (pixel centres in or out) that one-pixel ring broke into a dotted wire.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

#include "res://shaders/water_common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

varying float v_alpha;
varying float v_rad;
varying float v_ly;      // height on the unit sphere before shaping (-1 base centre .. 0 cap edge .. 1 dome top)
varying float v_cap;     // 1 = mushroom cap
varying vec3 v_axis;     // world up axis of the bubble (tilted with its rocking)
varying vec3 v_lq;       // position on the unit sphere before shaping (the ripple pattern of a cap's base)
varying float v_age;
varying float v_seed;
varying float v_ana;     // 0..1: shaded as an analytic sphere (small round bubbles)
varying float v_rpx;     // true radius in pixels
varying vec3 v_cv;       // centre in view space

// normalize() that never returns NaN (a NaN pixel shows black and the glow pass blooms it into a disc)
vec3 safe_norm(vec3 v, vec3 fb) {
	float l2 = dot(v, v);
	return l2 > 1e-12 ? v * inversesqrt(l2) : fb;
}

vec3 rot_x(vec3 q, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(q.x, q.y * c - q.z * s, q.y * s + q.z * c);
}

void vertex() {
	float age = INSTANCE_CUSTOM.x;
	float shape = INSTANCE_CUSTOM.y;
	float seed = INSTANCE_CUSTOM.z;
	v_alpha = INSTANCE_CUSTOM.w;
	v_rad = length(MODEL_MATRIX[0].xyz);
	vec3 q = VERTEX;
	vec3 sc = vec3(1.0);
	vec3 off = vec3(0.0);
	v_ly = q.y;
	v_lq = q;
	v_age = age;
	v_seed = seed;
	v_cap = step(0.75, shape);
	v_cv = MODELVIEW_MATRIX[3].xyz;
	v_rpx = v_rad * abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y * 0.5 / max(-v_cv.z, 0.05);
	v_ana = (1.0 - v_cap) * (1.0 - smoothstep(10.0, 14.0, v_rpx));
	if (shape > 0.75) {
		// spherical cap: domed top, flat rippling base, rim wobbling around its circumference
		// (atan(0, 0) at the two pole vertices is undefined: guarded)
		float az = abs(q.x) + abs(q.z) > 1e-6 ? atan(q.z, q.x) : 0.0;
		float rim = 1.0 + 0.12 * sin(2.0 * az + age * 7.0 + seed * 5.0) + 0.08 * sin(3.0 * az - age * 11.0 + seed * 2.0)
			+ 0.05 * sin(5.0 * az + age * 17.0 + seed * 9.0);
		sc = vec3(1.25 * rim, q.y > 0.0 ? 0.66 : 0.22, 1.25 * rim);
		off.y = q.y > 0.0 ? 0.0 : -0.07 * sin(4.0 * az + age * 13.0 + seed) * (1.0 - q.y * q.y);
	} else if (shape > 0.25) {
		// a few millimetres: oblate, shape-oscillating
		float wv = sin(age * 23.0 + seed * 17.0);
		sc = vec3(1.0 + 0.12 * wv, 0.78 - 0.1 * wv, 1.0 + 0.12 * wv);
		// (a small one is drawn round: its wobble is under a pixel, and the traced sphere needs a round mesh)
		sc = mix(sc, vec3(1.0), v_ana);
	}
	// the traced sphere's fringe: the mesh reaches ~1.2 px beyond the true silhouette
	sc *= 1.0 + v_ana * 1.2 / max(v_rpx, 0.5);
	float tilt = (shape > 0.75 ? 0.22 : 0.1) * sin(age * 3.1 + seed * 13.0);
	VERTEX = rot_x(q * sc + off, tilt);
	NORMAL = rot_x(safe_norm(NORMAL / sc, NORMAL), tilt);
	v_axis = safe_norm(mat3(MODEL_MATRIX) * rot_x(vec3(0.0, 1.0, 0.0), tilt), vec3(0.0, 1.0, 0.0));
}

// HDR water light field for the mirror: backdrop gradient, Snell's window (2.6x), the refracted sun disc and halo.
// disc: weight of the pin-sharp sun disc (0 for the rippling cap base, whose wandering normal turned it into
// single-pixel sparkles).
vec3 bubble_env_k(vec3 dir, float d, float disc) {
	vec3 col = wb_backdrop(dir, d, 1.0);
	col += mix(WB_SURF, vec3(1.0), 0.6) * smoothstep(0.52, 0.74, dir.y) * exp(-d / 85.0) * 2.6;
	float cs = max(dot(dir, safe_norm(water_sun_dir, vec3(0.0, 1.0, 0.0))), 0.0);
	col += vec3(1.0, 0.913, 0.716) * (pow(cs, 500.0) * 9.0 * disc + pow(cs, 40.0) * 1.4) * exp(-d / 110.0);
	return col;
}

vec3 bubble_env(vec3 dir, float d) {
	return bubble_env_k(dir, d, 1.0);
}

void fragment() {
	if (v_alpha < 0.002) {
		discard;
	}
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 vd = safe_norm(wp - water_cam_pos, vec3(0.0, 0.0, -1.0));
	vec3 nview = safe_norm(NORMAL, vec3(0.0, 0.0, 1.0));
	float cover = 1.0;
	if (v_ana > 0.0) {
		// the exact sphere along this pixel's ray (view space, eye at the origin): normal and anti-aliased edge
		vec3 dir = safe_norm(VERTEX, vec3(0.0, 0.0, -1.0));
		float tc = dot(dir, v_cv);
		float rho = length(v_cv - dir * tc) / max(v_rad, 1e-6);
		float rc = min(rho, 0.999);
		vec3 hit = dir * (tc - v_rad * sqrt(max(1.0 - rc * rc, 0.0)));
		vec3 na = safe_norm(hit - v_cv, nview);
		nview = safe_norm(mix(nview, na, v_ana), na);
		float aw = 0.6 / max(v_rpx, 0.5);
		cover = mix(1.0, 1.0 - smoothstep(1.0 - aw, 1.0 + aw, rho), v_ana);
	}
	vec3 n = safe_norm((INV_VIEW_MATRIX * vec4(nview, 0.0)).xyz, -vd);
	float c = clamp(-dot(n, vd), 0.0, 1.0);
	float d = max(-wp.y, 0.0);
	float deep = smoothstep(25.0, 180.0, d);
	// the water seen straight behind the bubble (the floor of its brightness)
	vec3 behind = wb_backdrop(vd, d, 1.0);
	// mirror: the reflected ray, bent up towards the overhead glow with depth (the deep below is black)
	vec3 r = reflect(vd, n);
	r = safe_norm(vec3(r.x, mix(r.y, abs(r.y) * 0.85 + 0.15, 0.25 + 0.35 * deep), r.z), vec3(0.0, 1.0, 0.0));
	// floor: in the shallows the sideways water (so against Snell's window the rim reads as a darker ring with
	// bright arcs where it mirrors the window), in the deep the water behind (never a dark pebble)
	// (in the deep the faint glow overhead is what a mirror can catch: the shell stays a pale silver against the dark)
	vec3 side = wb_backdrop(safe_norm(vec3(vd.x, 0.0, vd.z), vec3(1.0, 0.0, 0.0)), d, 1.0);
	vec3 glow_up = wb_backdrop(vec3(0.0, 1.0, 0.0), d, 1.0);
	vec3 base = max(behind, glow_up * 0.8);
	// A cap seen side-on shows its flat, wobbling base at a grazing angle. That face mirrors the water much like the
	// water around it (nearly invisible); only the true outline and the sharp edge where the dome meets the base
	// catch the light. So the bright floor and the silvery lift belong to the outline, not to the whole mirror.
	float base_in = v_cap * smoothstep(-0.12, -0.6, v_ly);        // inside the flat base (0 at the cap's edge)
	// a cap seen exactly edge-on: its edge and contour lines collapse into one long hairline, so they fade out and
	// the cap shows its body (the dome's outline) instead
	float face = mix(1.0, smoothstep(0.15, 0.5, abs(dot(v_axis, vd))), v_cap);
	// the cap's edge, a bright ellipse side-on (at least ~1.2 px wide, same energy). Its centre sits one width
	// inside the base: seen from below the edge is the mesh silhouette, and a line centred on it lost its outer
	// half to the rasterizer, leaving a dotted rim.
	float wr = max(0.09, 1.2 * fwidth(v_ly));
	float ly_r = v_ly + wr;
	float ring = v_cap * exp(-ly_r * ly_r / (wr * wr)) * (0.09 / wr) * face;
	float sil = pow(1.0 - c, 3.0) * (1.0 - base_in);             // the outline of the shell
	// total internal reflection beyond the critical angle: a crisp inner edge (never sharper than a pixel), a thin
	// dark line just inside it; the grazing base is a faint mirror, the cap's edge a crisp line
	float fc = fwidth(c);
	float tir0 = 1.0 - smoothstep(0.625 - fc, 0.665 + fc, c);
	vec3 mir = max(bubble_env(r, d), mix(side * 1.1, base * (1.0 + 0.7 * sil), deep));
	// a view-independent silvery lift towards the silhouette and along the cap's edge: the shell reads as a shell;
	// and a gentler one over the whole mirror band (on a small bubble the extreme silhouette alone is under a
	// pixel: it broke into a dotted wire ring, its lower half reflecting the darker water)
	mir += base * (sil * (0.35 + 1.4 * deep) + ring * (0.3 + 0.9 * deep) + tir0 * (1.0 - base_in) * (0.25 + 0.35 * deep));
	float tir = tir0 * (1.0 - 0.7 * base_in);
	tir = max(tir, ring * 0.85);
	float lw = max(0.028, 1.2 * fc);
	float lx = (c - 0.69) / lw;
	// (a contour of the curved shell: on the flat base the angle is the same everywhere, it would fill the base)
	float line = exp(-lx * lx) * (0.028 / lw) * (1.0 - base_in) * face;
	float fres = 0.02 + 0.2 * pow(1.0 - c, 5.0);
	// centre: the clear air lens shows the background, minified (a diverging lens) and a little brighter
	vec3 nv = nview;
	float rad_uv = v_rad * abs(PROJECTION_MATRIX[1][1]) / max(-VERTEX.z, 0.05) * 0.5;
	vec2 off = vec2(nv.x * VIEWPORT_SIZE.y / max(VIEWPORT_SIZE.x, 1.0), -nv.y) * rad_uv * 0.6;
	vec2 suv = clamp(SCREEN_UV + off, vec2(0.001), vec2(0.999));
	vec3 through = textureLod(screen_tex, suv, 0.0).rgb * 1.05;
	vec3 col = mix(through, mir, max(tir, fres));
	col = mix(col, behind * 0.55, line * (1.0 - tir) * 0.8);
	float a = mix(0.13, 0.62, tir);
	a = max(a, line * 0.42);
	// A cap seen from below: its rippling flat base is a silvery mirror of the light above (a wobbling mercury dome),
	// a little more opaque towards its edge, where the base curves up into the rim.
	float bf = base_in * smoothstep(0.2, 0.6, vd.y);
	if (bf > 0.0) {
		// the ripples: two incommensurate octaves drifting at different rates (one octave alone drew a regular
		// four-lobed pattern, a moon jelly), tilting the mirror gently enough that it mostly keeps reflecting the
		// light overhead
		vec2 hq = v_lq.xz;
		vec2 wob = 0.6 * vec2(sin(5.3 * hq.x + 3.1 * hq.y + v_age * 6.0 + v_seed * 11.0),
			cos(4.7 * hq.y - 2.9 * hq.x - v_age * 5.0 + v_seed * 7.0))
			+ 0.4 * vec2(sin(8.6 * hq.x - 7.9 * hq.y - v_age * 8.7 + v_seed * 3.0),
			cos(9.4 * hq.x + 6.3 * hq.y + v_age * 7.3 + v_seed * 5.0));
		vec3 nb = safe_norm(mix(n, vec3(0.0, -1.0, 0.0), 0.6) + vec3(wob.x, 0.0, wob.y) * 0.3, vec3(0.0, -1.0, 0.0));
		vec3 rb = reflect(vd, nb);
		rb = safe_norm(vec3(rb.x, abs(rb.y), rb.z), vec3(0.0, 1.0, 0.0));
		// floored at the glow overhead: the ripples vary between shades of silver, never dark holes; a little
		// desaturated (mercury, not blue glass); the soft sun only (no single-pixel glints)
		// (the floor follows what is really above/behind: under the lip roof the cap mirrors dark rock, not the open
		// glow, or it read as a pale pebble against the roof)
		vec3 env = max(bubble_env_k(rb, d, 0.0), min(glow_up * 0.8, through * 1.6));
		env = mix(env, vec3(dot(env, WB_LUMA)), 0.2);
		col = mix(col, env * 1.3, 0.55 * bf);
		float ef = sqrt(max(1.0 - v_ly * v_ly, 0.0));          // 0 at the base's centre .. 1 at its edge
		a = max(a, bf * mix(0.3, 0.45, ef));
	}
	// A cap seen from below (or above): its edge (the equator) is the mesh silhouette, and an opaque mirror band
	// ending on the polygon edge stepped into a dotted outline. It fades out over the last ~1.5 px instead. (Seen
	// side-on the equator is the line across the cap where dome and base meet: left alone.)
	float eq_fade = smoothstep(0.0, max(1.5 * fwidth(v_ly), 1e-4), abs(v_ly));
	a *= mix(1.0, eq_fade, v_cap * smoothstep(0.5, 0.8, abs(dot(v_axis, vd))));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * v_alpha * cover;
	FOG = water_fog(wp);
}
