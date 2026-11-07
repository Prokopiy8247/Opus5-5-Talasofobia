shader_type spatial;
// Gorgonian sea fan: forking radial branches and an irregular reticulate mesh (warped 2D cells). The mesh is sized in
// world metres and steps to coarser lattice levels with distance (cross-faded), so holes never shrink to sub-pixel
// specks and never close into a solid disc: about half of a far fan stays open water. Edges are antialiased with
// alpha to coverage (MSAA). Far fans melt toward the water colour, reading as soft lace. Gentle sway.
render_mode cull_disabled, alpha_to_coverage;
#include "res://shaders/water_common.gdshaderinc"
#include "res://shaders/reef_common.gdshaderinc"

varying vec3 v_w;
varying vec4 v_c;
varying vec2 v_p;
varying float v_s;
varying vec3 v_n;

void vertex() {
	v_p = VERTEX.xy;
	float r = length(VERTEX.xy);
	VERTEX.z += sin(TIME * 0.7 + INSTANCE_CUSTOM.a * 30.0 + VERTEX.x) * 0.06 * r * r;
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_n = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	v_s = length(MODEL_MATRIX[1].xyz);
	v_c = INSTANCE_CUSTOM;
}

// 2D cells: distance to the nearest cell border (F2 - F1).
float fan_mesh(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(water_hash(i + g), water_hash(i + g + 17.3)) * 0.85 + 0.075;
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return sqrt(f2) - sqrt(f1);
}

// Lattice at level lv (cell = 0.07 m * 2^lv): signed strand field in cell units (> 0 on a strand).
float fan_level(vec2 pm, float lv, float w) {
	float cell = 0.07 * exp2(lv);
	vec2 q = pm / cell + lv * 31.7;
	return w - fan_mesh(q);
}

void fragment() {
	vec2 p = v_p;
	float r = length(p);
	float ang = atan(p.x, p.y);
	float dist = length(v_w - water_cam_pos);
	float seed = v_c.a;
	// outline (unit fan space): an irregular half-disc
	float edge = 0.8 + 0.2 * water_noise(vec2(ang * 4.0 + seed * 9.0, 1.0)) + 0.06 * water_noise(vec2(ang * 13.0, seed * 3.0));
	float in_sd = edge - r;                                          // inside the outline (> 0)
	// lattice in metres, warped; the level follows the screen size of a cell (>= ~7 px per cell)
	vec2 pm = p * v_s;
	pm += (vec2(water_noise(p * 3.0 + seed * 7.0), water_noise(p * 3.0 + 5.0)) - 0.5) * 0.12 * v_s;
	float px = length(fwidth(pm));                                   // metres per pixel
	float lvf = clamp(log2(max(px * 7.0 / 0.07, 1.0)), 0.0, 4.0);
	float l0 = floor(lvf);
	float lt = smoothstep(0.25, 0.75, lvf - l0);
	// strands: thin near (about a third covered), about half covered on the coarse far levels
	float w0 = mix(0.14, 0.25, smoothstep(0.0, 2.0, l0));
	float w1 = mix(0.14, 0.25, smoothstep(0.0, 2.0, l0 + 1.0));
	float lat = fan_level(pm, l0, w0);
	if (lt > 0.0) {
		lat = mix(lat, fan_level(pm, l0 + 1.0, w1), lt);
	}
	// forking radial branches (always solid), thicker toward the holdfast
	float br = abs(fract(ang * (1.4 + 2.4 * r) + water_noise(vec2(r * 4.0, seed * 5.0)) * 0.6) - 0.5);
	float bw = 0.045 + 0.05 * (1.0 - r);
	float branch_sd = max((bw - br) * 3.0, 0.1 - r);
	float sd = max(lat, branch_sd * 2.0);
	// one signed field: inside the outline AND (strand OR branch); alpha 0.75 at the boundary, A2C feathers 1 px
	float a = min(sd * 2.5, in_sd * 8.0);
	ALPHA = clamp(0.75 + a, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	float is_branch = smoothstep(-0.02, 0.05, branch_sd);
	vec3 col = v_c.rgb * (0.75 + 0.35 * water_noise(p * 9.0)) * mix(0.7, 1.05, smoothstep(0.1, 0.8, r)) * mix(1.0, 0.85, is_branch);
	col = rf_depth_mute(col, -v_w.y);
	vec3 n = FRONT_FACING ? v_n : -v_n;
	vec3 rl = water_rel_light(v_w.y);
	BACKLIGHT = col * 0.3;
	ALBEDO = col * rl;
	EMISSION = col * rl * rf_water_fill(n, -water_cam_pos.y) * 0.25;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2 * water_spec_dim(v_w.y);
	// far fans soften into the water (lace, not cut-out discs)
	vec4 fog = rf_fog(v_w);
	fog.a = 1.0 - (1.0 - fog.a) * (1.0 - 0.45 * smoothstep(25.0, 90.0, dist));
	FOG = fog;
}
