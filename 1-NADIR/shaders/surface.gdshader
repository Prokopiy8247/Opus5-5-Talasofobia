shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;
// The ocean surface seen from below. Inside Snell's window (~48.6 deg) the refracted sky (faint drifting clouds)
// and a wave-distorted sun, broken by swell and capillary ripples; outside it total internal reflection, i.e. a
// mirror of the water below, fogged at the scene rate so it meets the backdrop at the horizon without a seam.
// With depth the window recedes as a shrinking porthole whose edge softens, then dissolves into a glow around the
// sun; it is gone by 410 m.
// The shared water-light pass skips this plane (wp.y > -0.6): it applies the same contract (wl_ratio) itself.
uniform vec3 sun_air = vec3(0.4535, 0.8152, 0.3603);   // direction toward the sun, in air (set from code)
uniform vec3 to_sun = vec3(0.3403, 0.9007, 0.2702);    // the same sun underwater (= -WaterEnv.SUN_DIR)
uniform vec4 sky_zenith : source_color = vec4(0.36, 0.60, 0.88, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.88, 0.94, 0.95, 1.0);
uniform float sky_energy = 1.35;
uniform float sun_energy = 26.0;
uniform float scene_fog = 0.0085;                        // = env.fog_density, set per frame
uniform sampler2D ripple_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
global uniform float g_depth;
global uniform float g_time;
uniform vec4 water_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);  // set per frame, same path as the backdrop
uniform float adapt = 1.0;   // eye adaptation (adapted / raw water colour), set per frame: the window dims with it

varying vec3 wpos;

// WATER LIGHT CONTRACT (identical in the shared pass and the ship shaders).
float wl_grad(float depth) { return 1.0 - smoothstep(150.0, 330.0, depth); }
vec3 wl_ratio(vec3 d, float depth) {
	float dn = smoothstep(0.0, 0.95, -d.y);
	dn = dn * dn * (3.0 - 2.0 * dn);
	vec3 r = mix(vec3(1.0), vec3(0.30, 0.36, 0.48), dn) * (1.0 + 0.35 * smoothstep(0.0, 0.66, d.y));
	return mix(vec3(1.0), r, wl_grad(depth));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// share of a wave of wavelength lambda that a pixel of footprint fp can still show (gone at ~1/3 wavelength)
float keep(float fp, float lambda) {
	return 1.0 - smoothstep(0.12, 0.35, fp / lambda);
}

// Sum of swell octaves, each filtered by the pixel footprint (no zipper on the rim).
vec2 wave_grad(vec2 p, float t, float fp) {
	vec2 g = vec2(0.0);
	vec2 d[5] = vec2[](vec2(0.8, 0.6), vec2(-0.5, 0.86), vec2(0.15, -0.99), vec2(-0.93, -0.37), vec2(0.6, -0.8));
	float k[5] = float[](0.21, 0.37, 0.63, 1.05, 1.9);
	float a[5] = float[](0.55, 0.32, 0.18, 0.09, 0.045);
	float w[5] = float[](0.9, 1.25, 1.7, 2.3, 3.2);
	for (int i = 0; i < 5; i++) {
		float ph = dot(d[i], p) * k[i] + t * w[i];
		g += d[i] * (a[i] * k[i] * cos(ph)) * keep(fp, 6.2831 / k[i]);
	}
	return g;
}

void fragment() {
	vec3 V = normalize(wpos - CAMERA_POSITION_WORLD);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float fp = max(length(dFdx(wpos.xz)), length(dFdy(wpos.xz)));   // pixel footprint on the plane, m
	// scattering blurs the wave pattern with depth (deep); the window edge softens much more slowly (soft), so the
	// window recedes overhead as a bounded, shrinking porthole of light instead of dissolving by 60 m
	float deep = smoothstep(12.0, 120.0, g_depth);
	float soft = smoothstep(25.0, 200.0, g_depth);
	float flt = clamp(dist / 900.0, 0.0, 1.0);
	vec2 g = wave_grad(wpos.xz, g_time, fp) * mix(0.19, 0.0, smoothstep(0.0, 0.5, flt)) * (1.0 - 0.88 * deep);
	// capillary ripples (two scrolling normal-map octaves) break the regular swell; shallows only
	vec2 r1 = texture(ripple_tex, wpos.xz / 7.0 + vec2(0.031, 0.017) * g_time).xy * 2.0 - 1.0;
	vec2 r2 = texture(ripple_tex, wpos.xz / 2.9 - vec2(0.022, -0.038) * g_time).xy * 2.0 - 1.0;
	g += (r1 * 0.06 * keep(fp, 1.2) + r2 * 0.035 * keep(fp, 0.5)) * (1.0 - smoothstep(10.0, 90.0, g_depth));
	vec3 N = normalize(vec3(-g.x, 1.0, -g.y));
	float cosi = dot(V, N);
	float kt = 1.0 - 1.777 * (1.0 - cosi * cosi);   // > 0 inside Snell's window (= cos^2 of the zenith angle in air)
	float ew = mix(0.10, 0.40, soft);
	float win = smoothstep(-0.1 * ew, ew, kt);       // no horizon smoke spilled outside the edge
	// Fresnel water->air transmission: it falls to 0 at the critical angle, so the window is NOT brightest at its
	// edge (that was the white 'cotton donut'); with depth, scattering hides the falloff in the soft edge
	float T = mix(smoothstep(0.0, 0.14, kt), 1.0, soft);

	// --- window: refracted sky; just outside the geometric edge it continues with the horizon colour
	vec3 R = kt > 0.0 ? refract(V, -N, 1.333) : normalize(vec3(V.x, 0.002, V.z));
	float el = clamp(R.y, 0.0, 1.0);
	// The pale horizon sky is squeezed into the outermost ~2.5 deg of the window (where T already fades it): a
	// broad pale band there reads as a white ring or halo around a blue disc, not as a window.
	vec3 sky = mix(sky_horizon.rgb, sky_zenith.rgb, smoothstep(0.0, 0.28, el)) * sky_energy;
	// faint drifting clouds, only in the upper sky with a gentle projection (no concentric streaks in the
	// compressed rim); 30 m of water erases them
	float cl = smoothstep(0.55, 0.8, texture(cloud_tex, R.xz / (R.y + 0.35) * 0.30 + vec2(g_time * 0.002, 0.0)).r);
	cl *= smoothstep(0.30, 0.65, R.y) * (1.0 - smoothstep(6.0, 30.0, g_depth));
	sky = mix(sky, vec3(1.05, 1.02, 0.98) * sky_energy * 0.9, cl * 0.35);
	float sd = max(dot(R, normalize(sun_air)), 0.0);
	float sharp = mix(900.0, 40.0, smoothstep(8.0, 140.0, g_depth));
	float sun = pow(sd, sharp) * sun_energy * sqrt(sharp / 900.0) + pow(sd, 40.0) * 1.6 + pow(sd, 6.0) * 0.35;
	// the opening shallows: centimetre capillaries (slopes up to ~0.2) break the sun into a shimmering cluster of
	// glints spread a few degrees around it; keep() switches them off before a pixel covers more than ~10 cm of
	// surface, and the mipmapped ripple map averages the slopes away first, so they never alias
	float kg = keep(fp, 0.30) * (1.0 - smoothstep(4.0, 30.0, g_depth));
	vec2 r3 = texture(ripple_tex, wpos.xz / 1.5 + vec2(0.13, -0.09) * g_time).xy * 2.0 - 1.0;
	vec3 Ng = normalize(N + vec3(-r3.x, 0.0, -r3.y) * 2.5);   // the map's slopes are ~0.1: scale to ~0.25
	float glint = pow(max(dot(refract(V, -Ng, 1.333), normalize(sun_air)), 0.0), 3000.0) * 30.0;
	sun = mix(sun, sun * 0.4 + glint, kg);
	sun *= 1.0 - smoothstep(180.0, 260.0, g_depth);
	float rim = smoothstep(0.635, 0.655, V.y) * (1.0 - smoothstep(0.655, 0.668, V.y));   // a thin 1-2 deg edge line
	// (deeper down the inner rim keeps more light, so the receding window stays a bounded disc, not a glow)
	vec3 skyc = sky * mix(mix(0.55, 0.85, soft), 1.0, el) + vec3(1.0, 0.95, 0.85) * sun + sky * rim * 0.35;
	// soft window-edge shimmer, only in the shallows
	skyc += vec3(0.6, 0.85, 0.9) * (1.0 - smoothstep(0.0, 0.025, abs(V.y - 0.661))) * 0.25 * (1.0 - deep);
	// far down the window dissolves into a glow centred on the sun (the aureole): a faint glow by 200 m
	float aur = pow(max(dot(V, to_sun), 0.0), 8.0);
	skyc = mix(skyc, sky_zenith.rgb * sky_energy * (0.25 + 3.0 * aur), smoothstep(80.0, 220.0, g_depth) * 0.8);
	// light lost on the way up through the water column (window light only), along the actual slant path: the
	// rim's path is ~1.5x the vertical one, so with depth the window darkens and blues from the edge inward and
	// recedes as a shrinking porthole (negligible in the shallows)
	float path = g_depth / max(V.y, 0.5);
	float absorb = exp(-path / 92.0);
	vec3 tint = mix(vec3(1.0), vec3(0.35, 0.65, 1.0), clamp(path / 140.0, 0.0, 0.85));

	// --- water seen looking up (the backdrop in direction V) and the mirrored water below (TIR)
	vec3 wc_up = water_col.rgb * wl_ratio(V, g_depth);
	vec3 mirror = water_col.rgb * wl_ratio(reflect(V, N), g_depth);   // total internal reflection: reflectance 1
	vec3 tir_f = mix(mirror, wc_up, 1.0 - exp(-dist * scene_fog));
	vec3 win_f = mix(skyc * tint * absorb * adapt, wc_up, 1.0 - exp(-dist * 0.0024));
	// the window only ever adds light to the water around it: deep down, its dimmed slant-path rim must not
	// read as a dark ring or disc against the backdrop
	win_f = max(win_f, wc_up);
	win_f = mix(win_f, wc_up, smoothstep(330.0, 410.0, g_depth));   // gone before the beat is culled at 440 m
	ALBEDO = mix(tir_f, win_f, win * T);
	FOG = vec4(0.0);
}
