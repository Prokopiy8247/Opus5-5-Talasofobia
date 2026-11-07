shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// The submarine towers of beat 3 (scripts/gen/Submarine.gd): dark steel under near-black matte rubber anechoic
// tiles, ragged clusters of tiles fallen off (dark grey steel with dull brown rust where they went), patchy silt
// on upward faces, a dirty sediment band at the foot. Openings (flood slots, torpedo tubes, open missile tubes)
// show the dim water inside them, never pure black. One lamp left on in one sail (hero_lamp) lights the plating
// around it (hero_light). Near towers get a soft form light (the diver's lamp spill and the water light wrapping
// the girth) so they read as round towers, not black slabs; far towers sink to one dark value.
// UV (metres): x = girth, y = height along the axis. COLOR: r = AO, g = tile coverage, b = rust bias,
// a = surface kind: < 0.2 plating, 0.2..0.5 opening interior (UV.x = 0 at its centre .. 1 at its rim),
// >= 0.5 window (UV.x = light id + in-window offset, UV.y = 0..1 across the window).
// INSTANCE_CUSTOM: r = seed 0..1, g = seabed height along the axis / 100 (mesh units).
// hero_lamp (Beat03_Forest.gd): the one window "someone left on"; w = its brightness, driven by a flicker tween.
// hero_light: xyz where its light sits (in front of that window), w its reach in metres (0 = no pool).
#include "res://shaders/inc/uw.gdshaderinc"

uniform vec3 tint = vec3(1.0);
uniform float rust_amount : hint_range(0.0, 1.0) = 0.45;
uniform float silt_amount : hint_range(0.0, 1.0) = 0.75;
uniform vec2 tile_size = vec2(1.6, 1.05);
uniform float tile_loss : hint_range(0.0, 1.0) = 0.4;
uniform float amber_fraction : hint_range(0.0, 1.0) = 0.0;   // other lit windows (0: the hero lamp is the only warm point)
uniform float amber_energy = 1.1;
uniform vec3 lamp_color = vec3(1.0, 0.42, 0.11);       // linear: ~(255, 170, 70) after the tonemap
uniform vec4 hero_lamp = vec4(0.0, 0.0, 0.0, -1.0);    // xyz world centre of the hero window, w brightness (<0 off)
uniform float hero_energy = 5.0;
uniform vec4 hero_light = vec4(0.0);                   // xyz the lamp's light (world), w its reach (m); 0 = none
uniform float pool_gain = 95.0;                        // how far that light lifts the near-black plating
uniform float form_light = 1.3;                        // strength of the near-tower form light
uniform vec3 form_tint = vec3(0.16, 0.42, 0.40);       // the cold water light that wraps the girth (linear)
uniform float far_start = 100.0;                       // beyond this the towers fade to one dark value (m)
uniform float far_end = 320.0;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;
varying float hloc;
varying flat float iseed;
varying flat float ground;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
	hloc = VERTEX.y;
	iseed = floor(INSTANCE_CUSTOM.r * 97.0 + 0.5);
	ground = INSTANCE_CUSTOM.g * 100.0;
}

void fragment() {
	vec2 uv = UV;
	vec3 n = normalize(wnrm);
	vec3 dv = CAMERA_POSITION_WORLD - wpos;
	float dist = length(dv);
	vec3 vw = dv / max(dist, 1e-3);
	float far_k = smoothstep(far_start, far_end, dist);
	vec2 fw2 = max(fwidth(uv), vec2(1e-4));
	float fw = max(fw2.x, fw2.y);                                    // metres per pixel
	float lod = smoothstep(0.1, 0.3, fw / tile_size.y);              // 1 = tiles a few px: draw their average
	float win = step(0.5, vcol.a);
	float hole = step(0.2, vcol.a) * (1.0 - win);
	// ---- rubber tiles (staggered rows). Each tile is an inset rounded rect, so every per-tile choice (lost,
	// tone, loose) fades out before the cell edge: the edges are anti-aliased and there is no staircase
	vec2 tc = uv / tile_size;
	float trow = floor(tc.y);
	float shift = 0.5 * mod(trow, 2.0);
	tc.x += shift;
	vec2 tid = floor(tc);
	vec2 tp = (fract(tc) - 0.5) * tile_size;                         // metres from the tile centre
	vec2 hb = tile_size * 0.5 - 0.035;
	vec2 q = abs(tp) - hb + 0.1;
	float sdf = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.1;
	float cov_t = 1.0 - smoothstep(-fw, fw, sdf);
	float cov_avg = (1.0 - 0.07 / tile_size.x) * (1.0 - 0.07 / tile_size.y);
	// the loss field: smooth noise (clusters) + a per-tile random that only decides the ragged edges of a
	// cluster (in noise standard deviations: most of the skin keeps its tiles, no speckle of strays)
	vec2 pscale = vec2(0.032, 0.021);
	vec2 poff = vec2(iseed * 1.7, iseed);
	vec2 tcen = (tid + 0.5 - vec2(shift, 0.0)) * tile_size;
	float thr = mix(1.7, 0.0, tile_loss);
	float patch_p = (uw_fbm2(uv * pscale + poff) - 0.47) / 0.12;
	float lost_s = clamp((patch_p - thr) / 0.9 + 0.5, 0.0, 1.0);     // fraction of tiles gone around here
	float hr = uw_hash12(tid + vec2(iseed * 0.37, 3.1));
	float lost_t = step(thr, (uw_fbm2(tcen * pscale + poff) - 0.47) / 0.12 + (hr - 0.5) * 0.9);
	float rubber = mix((1.0 - lost_t) * cov_t, (1.0 - lost_s) * cov_avg, lod) * vcol.g * (1.0 - hole) * (1.0 - win);
	float tvar = (uw_hash12(tid + vec2(7.0, iseed)) - 0.5) * (1.0 - lod);
	// a few tiles at the edge of a bare patch hang loose: tilted, they catch the light differently
	float loose = step(0.93, uw_hash12(tid + vec2(iseed, 11.0))) * smoothstep(0.15, 0.4, lost_s)
		* (1.0 - smoothstep(0.6, 0.85, lost_s)) * (1.0 - lod) * rubber;
	n = normalize(n + vec3(0.0, 0.55 * (hr - 0.5) * 2.0, 0.0) * loose);
	// exposed steel: where tiles went (smooth field), the narrow gaps between tiles, and the untiled plating
	float bare_s = clamp(max(lost_s * vcol.g, 1.0 - vcol.g), 0.0, 1.0);
	// ---- welded plating under the tiles: ring seams and long seams, only where the steel shows
	float near_f = 1.0 - smoothstep(0.1, 0.4, fw / tile_size.y);
	vec2 pq = uv / vec2(4.6, 6.2);
	vec2 pd = (0.5 - abs(fract(pq + vec2(0.5 * mod(floor(pq.y), 2.0), 0.0)) - 0.5)) * vec2(4.6, 6.2);
	float seam = max(uw_aa_line(pd.x, 0.05), uw_aa_line(pd.y, 0.06)) * bare_s * (1.0 - rubber) * near_f;
	// ---- colours: near-black matte rubber with a faint biofilm; dark grey steel; dull brown rust on the steel
	float film = uw_fbm3(wpos * 0.02 + vec3(iseed));
	vec3 rub = mix(pal_steel * 0.72, pal_moss * 0.34, 0.04 + 0.1 * film) * tint * (1.0 + tvar * 0.14);
	// the gaps in a tiled area are shadowed grooves (as dark as the rubber); bare patches are lighter
	vec3 steel = pal_steel * 1.1 * tint * mix(0.62, 1.0, bare_s);
	vec3 rustc = mix(pal_rust * 0.17, pal_rust * 0.34, uw_vnoise3(wpos * 0.45));
	float streak = smoothstep(0.64, 0.95, uw_vnoise3(vec3(wpos.x * 0.3, wpos.y * 0.017, wpos.z * 0.3) + vec3(iseed)));
	streak *= 0.55 + 0.45 * uw_vnoise3(vec3(wpos.x * 0.05, wpos.y * 0.004, wpos.z * 0.05) + vec3(iseed * 3.0));
	float rn = uw_vnoise3(wpos * 0.25 + vec3(iseed));
	float rust = bare_s * smoothstep(0.42, 0.85, rn + vcol.b * 0.3) * 0.75 + streak * (0.12 + 0.4 * bare_s) + seam * 0.3;
	// painted fins, planes and decks (never tiled) stay dark steel: rust is where the tiles came off
	rust = clamp(rust * rust_amount * 1.3, 0.0, 1.0) * (1.0 - rubber) * mix(0.3, 1.0, vcol.g);
	vec3 col = mix(steel, rustc, rust);
	col = mix(col, rub, rubber);
	col *= 1.0 - seam * 0.35;
	// ---- silt and moss in drifts on faces that look up (fin tops, plane and sail edges); on the nose dome it
	// lies in patches between bare tiles, never as one pale cap, and it is gone on the far towers
	float upf = smoothstep(0.35, 0.9, n.y);
	float sn = uw_fbm3(wpos * 0.12 + vec3(2.0, 0.0, 5.0));
	float sp = uw_fbm3(wpos * 0.045 + vec3(iseed, 3.0, 1.0));
	float silt = upf * smoothstep(0.42, 0.62, sn * 0.6 + sp * 0.55 + upf * 0.08) * silt_amount;
	silt = clamp(silt * (1.0 - far_k) * (1.0 - hole), 0.0, 1.0);
	col = mix(col, mix(pal_bone * 0.1, pal_moss * 0.3, smoothstep(0.4, 0.7, sn)), silt);
	// ---- sediment band and contact shadow at the foot
	float hg = hloc - ground;
	float band = 1.0 - smoothstep(0.0, 16.0, hg + (sn - 0.5) * 8.0);
	col = mix(col, mix(pal_moss * 0.4, pal_teal_far * 0.45, sn), band * 0.8);
	float contact = mix(0.35, 1.0, smoothstep(-1.0, 7.0, hg));
	// far towers: one dark uniform value (no lit caps, no patterns that shimmer)
	col = mix(col, pal_steel * 1.05 * tint, far_k * 0.93);
	// ---- windows: dark glass; the hero window lit, it flickers (other lit windows only if amber_fraction > 0)
	float wid = floor(uv.x + 0.5);
	float lit = win * step(1.0 - amber_fraction, uw_hash12(vec2(wid * 1.31, iseed * 1.37 + 5.0)));
	float hero = 0.0;
	float pool_on = 0.0;
	if (hero_lamp.w >= 0.0) {
		float hd = length(wpos - hero_lamp.xyz);
		hero = win * (1.0 - step(2.2, hd));
		lit *= step(16.0, hd);          // the only light left on in that sail
		pool_on = step(0.001, hero_light.w) * max(hero_lamp.w, 0.0);
	}
	col = mix(col, vec3(0.01, 0.012, 0.012), win);
	// a lamp behind dirty glass: hot in the middle, dimmer toward the frame
	vec2 wq = vec2((uv.x - wid) * 2.5, uv.y - 0.5);
	float hot = mix(0.45, 1.0, 1.0 - smoothstep(0.0, 0.62, length(wq * vec2(1.0, 1.25))));
	float flick = 0.85 + 0.15 * sin(uw_time * 0.6 + iseed * 2.3 + uv.x);
	vec3 emis = lamp_color * hot * mix(amber_energy * lit * flick * (1.0 - far_k * 0.5), hero_energy * max(hero_lamp.w, 0.0), hero);
	// ---- openings: the dim water inside, darker toward the middle (the recess), never black
	vec3 inside = uw_water_col(wpos.y) * mix(0.2, 0.5, smoothstep(0.3, 1.0, uv.x));
	col = mix(col, vec3(0.004), hole);
	float ao = mix(1.0, vcol.r, 0.9) * contact;
	ALBEDO = col * ao * uw_albedo_light(wpos.y);
	ROUGHNESS = mix(mix(mix(0.9, 0.55, bare_s * (1.0 - rubber)), 0.92, max(rust, silt)), 1.0, hole);
	METALLIC = 0.25 * bare_s * (1.0 - rubber) * (1.0 - rust) * (1.0 - hole);
	SPECULAR = 0.3 * (1.0 - hole);
	// ---- form light: the diver's lamp spills on the near girth (bright where the hull faces the diver) and
	// the water light wraps it from above and one side, so a tower shades round; patterns stay in it
	float spill = uw_lamp_dir.w * exp(-dist / 55.0);
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), vw) + vec3(0.0, 0.001, 0.0));
	float ndv = clamp(dot(n, vw), 0.0, 1.0);
	float wrap = clamp(dot(n, normalize(vw * 0.55 + side * 0.65 + vec3(0.0, 0.5, 0.0))) * 0.6 + 0.4, 0.0, 1.0);
	vec3 form = col * ao * (pal_shaft * spill * (0.15 + 0.85 * ndv * ndv) * 1.6
		+ form_tint * wrap * wrap) * form_light * (1.0 - far_k);
	// ---- the lamp's own light on the plating, the masts and the planes around it (a warm pool, not a sticker)
	vec3 pool = vec3(0.0);
	if (pool_on > 0.0) {
		vec3 lv = hero_light.xyz - wpos;
		float ld = length(lv);
		float att = 1.0 - smoothstep(0.0, hero_light.w, ld);
		att = att * att / (1.0 + ld * ld * 0.015);
		float ndl = clamp(dot(n, lv / max(ld, 1e-3)) * 0.8 + 0.2, 0.0, 1.0);
		pool = lamp_color * col * ao * (pool_gain * pool_on * att * ndl) * (1.0 - win) * (1.0 - hole);
	}
	EMISSION = emis + form + pool + inside * hole * (1.0 - far_k * 0.6)
		+ uw_ambient_glow(n, vw, wpos.y) * ao * mix(1.0, 0.55, far_k) * (1.0 - hole);
	FOG = uw_fog_eval(CAMERA_POSITION_WORLD, wpos);
}
