// Reef helpers (include after water_common): 3D value noise, 3D cells (colonies), life palette, depth colour loss,
// direction-aware water fill, sun caustics, macro relief, reef fog.

// Rotation used to decorrelate noise octaves (hides the value-noise lattice).
const mat3 RF_ROT = mat3(vec3(0.00, 0.80, 0.60), vec3(-0.80, 0.36, -0.48), vec3(-0.60, -0.48, 0.64));

float rf_hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

vec3 rf_hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float rf_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = rf_hash3(i);
	float b = rf_hash3(i + vec3(1.0, 0.0, 0.0));
	float c = rf_hash3(i + vec3(0.0, 1.0, 0.0));
	float d = rf_hash3(i + vec3(1.0, 1.0, 0.0));
	float e = rf_hash3(i + vec3(0.0, 0.0, 1.0));
	float g = rf_hash3(i + vec3(1.0, 0.0, 1.0));
	float h = rf_hash3(i + vec3(0.0, 1.0, 1.0));
	float k = rf_hash3(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y), mix(mix(e, g, u.x), mix(h, k, u.x), u.y), u.z);
}

// 3D cells: x = F1, y = F2, z = cell id (0..1).
vec3 rf_cells(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float f1 = 9.0;
	float f2 = 9.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 r = g + rf_hash33(i + g) * 0.9 - f;
				float d = dot(r, r);
				if (d < f1) {
					f2 = f1;
					f1 = d;
					id = rf_hash3(i + g + 17.17);
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}
	return vec3(sqrt(f1), sqrt(f2), id);
}

// Encrusting life (linear albedo): sponges, coralline crusts, turf, colonies. bias shifts the family by region.
vec3 rf_life(float id, float bias) {
	float t = fract(id * 7.31 + bias * 0.6);
	if (t < 0.14) return vec3(0.44, 0.25, 0.05);   // ochre sponge
	if (t < 0.26) return vec3(0.15, 0.16, 0.06);   // olive turf
	if (t < 0.38) return vec3(0.17, 0.09, 0.20);   // purple crust
	if (t < 0.47) return vec3(0.36, 0.16, 0.16);   // rose
	if (t < 0.58) return vec3(0.46, 0.42, 0.31);   // pale coralline
	if (t < 0.66) return vec3(0.05, 0.04, 0.035);  // dark sponge
	if (t < 0.73) return vec3(0.52, 0.18, 0.03);   // orange sponge
	if (t < 0.81) return vec3(0.52, 0.43, 0.10);   // yellow sponge
	if (t < 0.91) return vec3(0.20, 0.22, 0.16);   // grey-green colony
	return vec3(0.28, 0.20, 0.13);                 // brown colony
}

// Continuous muted ramp of encrusting life (linear), t wraps: olive turf, ochre, rose-grey, purple-grey, pale crust,
// grey-green.
vec3 rf_ramp(float t) {
	t = fract(t) * 6.0;
	float f = smoothstep(0.15, 0.85, fract(t));
	int i = int(floor(t));
	vec3 a = vec3(0.20, 0.20, 0.09);
	vec3 b = vec3(0.38, 0.26, 0.10);
	if (i == 1) { a = vec3(0.38, 0.26, 0.10); b = vec3(0.30, 0.17, 0.17); }
	else if (i == 2) { a = vec3(0.30, 0.17, 0.17); b = vec3(0.17, 0.12, 0.21); }
	else if (i == 3) { a = vec3(0.17, 0.12, 0.21); b = vec3(0.31, 0.29, 0.22); }
	else if (i == 4) { a = vec3(0.31, 0.29, 0.22); b = vec3(0.16, 0.20, 0.15); }
	else if (i == 5) { a = vec3(0.16, 0.20, 0.15); b = vec3(0.20, 0.20, 0.09); }
	return mix(a, b, f);
}

// Albedo colour loss with depth (sunlight path): reds go first, then everything drifts to blue-grey.
vec3 rf_depth_mute(vec3 c, float depth) {
	float k = smoothstep(3.0, 30.0, depth);
	c *= mix(vec3(1.0), vec3(0.42, 0.82, 1.0), k) * vec3(1.0 - 0.3 * smoothstep(2.0, 18.0, depth), 1.0, 1.0);
	float l = dot(c, vec3(0.25, 0.6, 0.15));
	return mix(c, vec3(l) * vec3(0.92, 1.0, 1.06), 0.5 * smoothstep(12.0, 90.0, depth));
}

// normalize(v), or fb where v is (near) zero or not finite. An interpolated vertex normal across a sharp fold (vertex
// normals pointing nearly opposite ways) can pass through zero inside a triangle: normalize() would give NaN there,
// a black pixel that the glow pass can bloom into a disc.
vec3 rf_safe_normal(vec3 v, vec3 fb) {
	float l2 = dot(v, v);
	return (l2 > 1e-12 && !isnan(l2) && !isinf(l2)) ? v * inversesqrt(l2) : fb;
}

// Screen-space bump: perturb world normal n by the gradient of height h (any units) with strength k.
vec3 rf_bump(vec3 wp, vec3 n, float h, float k) {
	vec3 dpx = dFdx(wp);
	vec3 dpy = dFdy(wp);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpy, n);
	vec3 r2 = cross(n, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	// Degenerate screen derivatives (far grazing pixels, silhouettes) make this vector zero: normalize() would return
	// NaN, which shows as a black pixel and blooms into a soft glowing disc (the glow pass clamps NaN to its cap).
	vec3 r = abs(det) * n - grad * k;
	float l2 = dot(r, r);
	return (l2 > 1e-24 && !isnan(l2) && !isinf(l2)) ? r * inversesqrt(l2) : n;
}

// Macro relief (metres) at 6-40 m scales. Never faded with distance, so far rock keeps broad light and shade
// instead of collapsing into one flat tone. x = height, y = a broad brightness field (0..1).
vec2 rf_macro(vec3 p) {
	float m1 = rf_noise(RF_ROT * p * 0.045 + 3.0);
	float m2 = rf_noise(RF_ROT * (RF_ROT * p) * 0.13 + 7.0);
	float m3 = rf_noise(p * 0.028 + 41.0);
	return vec2(2.4 * m1 + 0.8 * m2, m3);
}

// Diffuse light the water scatters onto a surface: the colour of the far water along its normal, blended over the
// hemisphere (not just the one direction), so even a small tilt of an underside towards the open water shows:
// undersides see the dark deep, walls the blue horizon, tops the bright water above. Multiply by AO.
vec3 rf_water_fill(vec3 n, float depth) {
	vec3 hz = wb_backdrop(vec3(1.0, 0.0, 0.0), depth, 0.0);
	float y = clamp(n.y + 0.12, -1.0, 1.0);
	if (y < 0.0) {
		return mix(hz, wb_backdrop(vec3(0.0, -1.0, 0.0), depth, 0.0), pow(-y, 1.15));
	}
	return mix(hz, wb_backdrop(vec3(0.0, 1.0, 0.0), depth, 0.0), y * 0.85);
}

// Water fog for reef surfaces: the shared water fog; rock far below the diver melts into the abyss (it must never
// read as a flat plate under the camera); beyond ~350 m the reef melts completely into the backdrop (by 500 m it is
// exactly the backdrop colour, so ReefVisibility can hide it without a pop).
vec4 rf_fog(vec3 wp) {
	vec4 f = water_fog(wp);
	float below = smoothstep(30.0, 110.0, water_cam_pos.y - wp.y) * 0.7;
	f.a = max(f.a, max(below, smoothstep(350.0, 500.0, length(wp - water_cam_pos))));
	return f;
}

// --- Sun caustics -----------------------------------------------------------------------------------------------

// 2D cells whose feature points orbit (animated): distance to the nearest cell border (F2 - F1).
float rf_cell_edge(vec2 p, float t, float spd, float salt) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec3 h = rf_hash33(vec3(i + g, salt));
			vec2 o = 0.5 + 0.38 * sin(t * spd * (0.7 + 0.6 * h.z) + 6.2831 * h.xy);
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

// Multiplier on direct sunlight (mean about 1, per channel) from the caustic net focused by the waves: a network of
// sharp bright filaments around darker cells (~1 m in the shallows, broader deeper), refocusing about once a second.
// Projected along the refracted sun onto the surface, so it is fixed on the reef wherever the camera looks. Strong
// near the surface, gone by ~30 m; fades out (to exactly 1) where a cell gets too small on screen.
vec3 rf_caustic(vec3 wp, float t) {
	float depth = -wp.y;
	vec3 s = normalize(water_sun_dir);
	vec2 cp = wp.xz - wp.y * s.xz / max(s.y, 0.2);
	vec2 q = cp / (0.85 + max(depth, 0.0) * 0.02);
	float fp = length(fwidth(q));                    // cells per pixel (derivatives before any branch)
	float g = (1.0 - smoothstep(4.0, 30.0, depth)) * (1.0 - smoothstep(0.1, 0.28, fp));
	if (g <= 0.0) {
		return vec3(1.0);
	}
	vec2 wv = vec2(rf_noise(vec3(q * 0.7, t * 0.35)), rf_noise(vec3(q * 0.7 + 5.2, t * 0.35 + 3.1))) - 0.5;
	vec2 qw = q + wv * 0.55;
	float a = rf_cell_edge(qw + vec2(t * 0.12, 0.0), t, 2.3, 7.0);
	float b = rf_cell_edge(mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * qw * 0.7 + vec2(-t * 0.09, t * 0.05), t, 1.4, 13.0);
	float lb = 0.04 / (0.04 + b * b);
	float w = max(0.07, fp * 1.3);
	vec3 w2 = vec3(w * 0.85, w, w * 1.2);
	w2 *= w2;
	vec3 la = pow(w2 / (w2 + a * a), vec3(1.5));
	vec3 c = la * (0.35 + 1.3 * lb) / (0.15 * vec3(0.85, 1.0, 1.2) * (w / 0.07));
	return max(vec3(1.0) + g * 0.5 * (c - 1.0), vec3(0.3));
}

// Direct light for the reef's custom light(), matching Godot's own normalisation (LIGHT_COLOR carries PI).
// Diffuse: Lambert times the caustic multiplier (1 for lights other than the sun).
vec3 rf_light_diffuse(vec3 N, vec3 L, vec3 lcol, float att, vec3 caus) {
	return lcol * att * max(dot(N, L), 0.0) * caus * (1.0 / PI);
}

// Specular: a soft GGX lobe with reflectance f0.
vec3 rf_light_specular(vec3 N, vec3 L, vec3 V, vec3 lcol, float att, float rough, float f0) {
	float ndl = max(dot(N, L), 0.0);
	vec3 h = (V + L) * inversesqrt(max(dot(V + L, V + L), 1e-12));   // safe when V = -L
	float ndh = max(dot(N, h), 0.0);
	float a = rough * rough;
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float D = a2 / (PI * dd * dd);
	float ndv = max(dot(N, V), 1e-3);
	float k = a * 0.5;
	float vis = 0.25 / ((ndl * (1.0 - k) + k) * (ndv * (1.0 - k) + k));
	return lcol * att * ndl * D * vis * f0;
}
