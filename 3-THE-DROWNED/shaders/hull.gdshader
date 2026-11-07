shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// Sunken steel: plates, seams, rivets, rust patches, streaks and curtains, silt and growth, porthole rows with
// a few amber lights, painted draft marks, antifouling and boot-top. UV is in metres: UV.x along the length,
// UV.y height above the keel (or girth; below 0 across the flat bottom). Vertex COLOR: r = ambient occlusion,
// g = porthole zone, b = rust bias, a = moss bias (< 0.5 on the shell plating, 0.8 on decks). Every
// thresholded random choice uses a flat integer seed and an integer hash (no per-pixel flicker); portholes
// and seams keep their average coverage when they get sub-pixel, so far or grazing surfaces never darken.
// Sun caustics are added in light() for the directional light only (its shadow map masks them), on
// upward-facing surfaces, fading with depth exactly as on the seabed (gone by ~90 m).
#include "res://shaders/inc/uw.gdshaderinc"

uniform vec3 tint = vec3(1.0);
uniform float rust_amount : hint_range(0.0, 1.0) = 0.5;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.4;
uniform vec2 plate_size = vec2(9.0, 2.6);
uniform float seam_width = 0.035;
uniform float porthole_spacing = 4.0;
uniform float porthole_radius = 0.45;
uniform float porthole_row_start = 6.0;
uniform float porthole_row_step = 3.0;
uniform float porthole_rows = 2.0;
uniform float amber_fraction : hint_range(0.0, 1.0) = 0.04;
uniform float amber_energy = 7.0;
uniform float seed = 0.0;
uniform bool instanced = false;
uniform float scale_ref = 1.0;   // >1 for colossi: makes plates/rust patterns bigger
// draft marks: x = UV.x of the stern column, y = UV.x of the bow column, z = digit height (m), w = 1 to paint
uniform vec4 draft = vec4(0.0);
uniform float draft_max = 12.0;  // highest mark (m above the keel)
uniform float rusticles = 1.0;   // rust curtains under overhangs
// ---- wear (all in metres of UV.y unless noted)
uniform float wear = 1.0;                 // rust streaks, silt, growth (0 = clean paint)
uniform float deck_height = -1.0;         // where the side plating ends: rust bleeds down from it, growth band under it (< 0: none)
uniform float waterline = -1.0;           // old load line: antifouling below, boot-top band above it (< 0: none)
uniform float boot_width = 1.2;
uniform vec3 antifoul = vec3(0.2, 0.075, 0.05);
uniform float paint_dull = 0.0;           // 0..1: wreck paint (pale stripes and tints washed toward rust and silt)
uniform float caustic_gain = 0.85;
uniform float door_spacing = 0.0;        // superstructure: a door slot every ~this many metres of each tier's wall (0 = none)
// distance fog floor (m): x where it starts, y where the surface is fully fogged (0 = off). The liner's upper tiers
// stand above the fog band its hull lies in: from far off they hung in the water as dark rectangles
uniform vec2 fog_floor = vec2(0.0);

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;
varying flat int iseed;
varying float vside;             // model-space normal z: > 0 starboard, < 0 port
varying float vny;               // model-space normal y: the plating's own up (sides ~0 even when the wreck lies heeled)
varying float caus_v;            // fragment -> light: caustic intensity on this pixel
varying vec3 f0_v;               // fragment -> light: specular reflectance

uint pcg(uint v) {
	uint s = v * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return (w >> 22u) ^ w;
}

// noise lattices turned off the ship's axes: on a hull lying along a world axis, lattice-aligned value noise
// lined its blobs up with the plate seams (a regular grid of smudges)
const mat3 NROT = mat3(vec3(0.8, 0.36, -0.48), vec3(-0.6, 0.48, -0.64), vec3(0.0, 0.8, 0.6));
const mat2 UROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

// 0..1 hash of an integer cell and the seed (exact: no threshold flicker)
float hcell(ivec2 c, int sd) {
	return float(pcg(uint(c.x) ^ pcg(uint(c.y) ^ pcg(uint(sd))))) / 4294967295.0;
}

// anti-aliased line of half width hw whose coverage fades with its true width once it is sub-pixel
float seam_line(float x, float hw) {
	float fw = max(fwidth(x), 1e-5);
	return (1.0 - smoothstep(hw - fw, hw + fw, abs(x))) * min(1.0, 2.0 * hw / fw);
}

// distance (in digit heights) from p to a 7-segment numeral d (cell 0.62 x 1)
float seg_digit(vec2 p, int d) {
	int m = 0;
	if (d == 0) m = 63; else if (d == 1) m = 6; else if (d == 2) m = 91; else if (d == 3) m = 79;
	else if (d == 4) m = 102; else if (d == 5) m = 109; else if (d == 6) m = 125; else if (d == 7) m = 7;
	else if (d == 8) m = 127; else m = 111;
	float dist = 1e3;
	// a top, b top-right, c bottom-right, d bottom, e bottom-left, f top-left, g middle
	vec2 hs = vec2(0.17, 0.0);
	vec2 vs = vec2(0.0, 0.2);
	if ((m & 1) != 0) dist = min(dist, length(max(abs(p - vec2(0.31, 0.92)) - hs, 0.0)));
	if ((m & 2) != 0) dist = min(dist, length(max(abs(p - vec2(0.52, 0.71)) - vs, 0.0)));
	if ((m & 4) != 0) dist = min(dist, length(max(abs(p - vec2(0.52, 0.29)) - vs, 0.0)));
	if ((m & 8) != 0) dist = min(dist, length(max(abs(p - vec2(0.31, 0.08)) - hs, 0.0)));
	if ((m & 16) != 0) dist = min(dist, length(max(abs(p - vec2(0.1, 0.29)) - vs, 0.0)));
	if ((m & 32) != 0) dist = min(dist, length(max(abs(p - vec2(0.1, 0.71)) - vs, 0.0)));
	if ((m & 64) != 0) dist = min(dist, length(max(abs(p - vec2(0.31, 0.5)) - hs, 0.0)));
	return dist - 0.075;
}

// signed distance (m) to the draft numerals of one column (glyph x already mirrored for the port side)
float draft_column(float gx, float gy, float dh, float stepm) {
	float level = floor(gy / stepm + 0.25) * stepm;
	if (level < stepm - 0.01 || level > draft_max + 0.01) return 1e3;
	float ly = (gy - level) / dh + 0.1;
	if (ly < -0.2 || ly > 1.2) return 1e3;
	int num = int(level + 0.5);
	int nd = num >= 10 ? 2 : 1;
	float lx = gx / dh + float(nd) * 0.4;        // the label is centred on the column
	int di = int(floor(lx / 0.8));
	if (lx < 0.0 || di >= nd) return 1e3;
	int dig = nd == 2 ? (di == 0 ? num / 10 : num % 10) : num;
	return seg_digit(vec2(lx - float(di) * 0.8, ly), dig) * dh;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
	iseed = int(floor(seed + (instanced ? INSTANCE_CUSTOM.x * 97.0 : 0.0) + 0.5));
	vside = NORMAL.z;
	vny = NORMAL.y;
}

void fragment() {
	vec2 uv = UV;
	vec2 fw2 = max(fwidth(uv), vec2(1e-4));
	float fw = max(fw2.x, fw2.y);                         // isotropic footprint (m per pixel)
	vec3 cam = CAMERA_POSITION_WORLD;
	float dist = length(wpos - cam);
	vec3 vw = (cam - wpos) / max(dist, 1e-4);
	vec3 nw = normalize(wnrm);
	float ndv = abs(dot(nw, vw));
	float fs = float(iseed);
	float sr = sqrt(scale_ref);
	float shell = 1.0 - step(0.5, vcol.a);                // side plating, transom, superstructure walls
	float side_m = 1.0 - smoothstep(0.45, 0.8, abs(vny));  // walls in the ship's own frame
	// ---- plates (staggered), seams and rivets
	vec2 pc = uv / plate_size;
	float row = floor(pc.y);
	pc.x += 0.5 * mod(row, 2.0);
	vec2 pid = floor(pc);
	vec2 pf = fract(pc) - 0.5;
	float pvar = hcell(ivec2(pid), iseed) - 0.5;
	vec2 sd = (0.5 - abs(pf)) * plate_size;               // metres to the nearest seam
	float seam = max(seam_line(sd.x, seam_width), seam_line(sd.y, seam_width));
	vec2 rp = vec2(fract(uv.x / 0.45) - 0.5, sd.y - 0.12);
	float rivets = 1.0 - smoothstep(0.035, 0.035 + fw, length(vec2(rp.x * 0.45, rp.y)));
	rivets *= 1.0 - smoothstep(0.02, 0.06, fw);
	// ---- paint: antifouling below the old load line, a dark boot-top band, the topsides above
	vec3 steel = pal_steel * 1.7 * tint;
	if (waterline > 0.0 && shell > 0.5) {
		float lo = 1.0 - smoothstep(waterline - fw, waterline + fw, uv.y);
		float boot = (1.0 - lo) * (1.0 - smoothstep(waterline + boot_width - fw, waterline + boot_width + fw, uv.y));
		steel = mix(steel, antifoul * (1.0 - 0.35 * paint_dull), lo);
		steel = mix(steel, pal_steel * 0.75, boot);
	}
	// plate-to-plate tone (strong enough to read in the fog) and each strake a little darker at its lower lap
	steel *= (1.0 + pvar * 0.36) * (1.0 - 0.1 * smoothstep(0.05, 0.5, -pf.y));
	float h01 = clamp(uv.y / 30.0, 0.0, 1.0);
	steel = mix(steel * mix(vec3(0.75, 1.05, 0.9), vec3(1.0), h01), steel, 0.5);
	// ---- rust: patches from world noise + streaks running down from seams and portholes
	vec3 wq = wpos / (14.0 * scale_ref);
	float n1 = uw_fbm3(wq + fs);
	float streak = uw_vnoise2(vec2(wpos.x / (2.5 * scale_ref) + fs * 3.1, wpos.y / (22.0 * scale_ref)));
	streak = smoothstep(0.55, 0.95, streak) * smoothstep(-0.2, 0.6, -wnrm.y + 0.6);
	float ra = clamp(rust_amount + paint_dull * 0.25, 0.0, 1.0);
	float rust = smoothstep(0.62 - ra * 0.35, 0.9, n1 + vcol.b * 0.25) + streak * ra * 0.8;
	rust = clamp(rust * (0.4 + ra), 0.0, 1.0);
	vec3 rustc = mix(pal_rust * 0.55, pal_rust, uw_vnoise3(wpos * 0.7 / scale_ref));
	vec3 col = mix(steel, rustc, rust);
	// ---- rust bleeding down the plating (ship frame): from the deck edge, from every strake seam and
	// from each porthole; thin columns with broken lengths, averaged once they get sub-pixel
	float wr = wear * side_m * shell;
	if (wr > 0.001) {
		float cw = 0.55 * sr;                                  // streak column width (m)
		float cx = uv.x / cw;
		float colmask = smoothstep(0.52, 0.82, uw_vnoise2(vec2(cx * 2.3, fs * 0.37 + 0.5)));
		float brk = uw_vnoise2(vec2(cx * 1.1 + 7.0, uv.y / (3.5 * sr) + fs));
		float dd = deck_height > 0.0 ? max(deck_height - uv.y, 0.0) : 1e4;
		float from_deck = exp(-dd / ((2.5 + 10.0 * brk) * sr));
		float ds = (1.0 - fract(pc.y)) * plate_size.y;          // metres below the seam above
		// only some plates weep from their upper seam, each its own length (not one smudge under every plate)
		float pg = hcell(ivec2(pid) + ivec2(31, 7), iseed * 13 + 5);
		float from_seam = exp(-ds / (0.4 + 2.6 * brk * pg)) * 0.5 * step(0.64, pg);
		float lodc = smoothstep(0.25, 0.9, fw / cw);           // 1 = the columns are sub-pixel
		float rs = mix(colmask, 0.14, lodc) * max(from_deck, from_seam) * smoothstep(0.15, 0.55, brk + 0.2);
		// under each porthole of the row above
		float ka = floor((uv.y - porthole_row_start) / porthole_row_step) + 1.0;
		float za = step(0.5, vcol.g) * step(0.0, ka) * step(ka, porthole_rows - 1.0);
		float cxa = floor(uv.x / porthole_spacing);
		vec2 ca = vec2((cxa + 0.5) * porthole_spacing, porthole_row_start + ka * porthole_row_step);
		float dxa = abs(uv.x - ca.x) / porthole_radius;
		float dya = (ca.y - uv.y) / porthole_radius;           // > 0 under the port
		float ph = hcell(ivec2(int(cxa), int(ka)), iseed * 3 + 11);
		float plen = 2.5 + 8.0 * ph;
		float ps = za * (1.0 - smoothstep(0.3, 0.75 + dya * 0.05, dxa)) * smoothstep(1.0, 1.5, dya)
			* (1.0 - smoothstep(plen * 0.35, plen, dya)) * step(0.45, fract(ph * 7.31));   // about half the ports weep
		ps *= 1.0 - smoothstep(0.3, 0.8, fw / porthole_radius);
		rs = clamp(max(rs, ps * 0.9) * wr, 0.0, 1.0);
		col = mix(col, mix(pal_rust * 0.62, pal_rust * 0.24, brk), rs * 0.8);
		rust = max(rust, rs);
		// growth band: a ragged mantle of encrusting life just under the deck edge, where the current feeds it
		if (deck_height > 0.0) {
			float gw = (1.0 + 2.2 * uw_vnoise2(vec2(uv.x / (5.0 * sr), fs + 3.0))) * sr;
			float gb = (1.0 - smoothstep(gw * 0.55, gw, dd + (uw_fbm2(UROT * uv * 0.9 / sr) - 0.5) * 1.1 * sr));
			// soft fractal mottling, low contrast: single-octave speckle read as rows of dark smudges from afar
			float spk = mix(uw_fbm2(UROT * uv * 1.4 / sr + fs), 0.47, smoothstep(0.08, 0.3, fw / sr));
			col = mix(col, mix(pal_moss * 0.7, pal_bone * 0.24, smoothstep(0.25, 0.7, spk)), gb * wr * 0.85);
			// the lowest plating, in and against the sediment bed: mud-stained and darker
			float mud = 1.0 - smoothstep(0.03 * deck_height, 0.2 * deck_height + n1 * 0.12 * deck_height, uv.y);
			col = mix(col, (pal_moss * 0.35 + pal_rust * 0.05) * 0.8, mud * wr * 0.7);
		}
	}
	// ---- rust curtains / rusticles hanging under overhangs (bilge, counter, deck edges, wings)
	vec3 th = cross(wnrm, vec3(0.0, 1.0, 0.0));
	float hc = length(th) > 0.25 ? dot(wpos, normalize(th)) : (wpos.x + wpos.z) * 0.7;
	float drip = uw_vnoise2(vec2(hc * 2.4 / sr, fs * 1.7));
	float dlen = uw_vnoise2(vec2(hc * 0.5 / scale_ref + fs, wpos.y * 0.12 / scale_ref));
	float facing = 1.0 - smoothstep(-0.6, 0.35, wnrm.y);
	float curtain = smoothstep(0.58, 0.82, drip) * smoothstep(0.3, 0.65, dlen) * facing * rusticles;
	curtain *= 1.0 - smoothstep(0.08, 0.3, fw);
	col = mix(col, mix(pal_rust * 0.32, pal_rust * 0.62, dlen), clamp(curtain * (0.5 + ra * 0.6), 0.0, 0.85));
	rust = max(rust, curtain);
	// ---- silt settled on everything facing up (decks, hatch tops, the upslope flank of a heeled hull),
	// moss and algae patches in it
	float up = smoothstep(0.15, 0.85, wnrm.y);
	float upf = smoothstep(0.5, 0.92, wnrm.y);
	float silt = 0.0;
	if (upf * wear > 0.001) {
		vec3 wr3 = NROT * wpos;
		float sn = uw_vnoise3(wr3 * 0.42 / sr + fs) * 0.65 + uw_vnoise3(wr3 * 1.6 / sr + 3.0) * 0.35;
		silt = clamp(upf * smoothstep(0.3, 0.6, sn + upf * 0.3) * wear, 0.0, 1.0);
		col = mix(col, mix(pal_bone * 0.2, pal_bone * 0.31, sn) * vec3(0.92, 1.0, 0.9), silt * 0.88);
	}
	float mn = uw_fbm3(NROT * wpos / (6.0 * scale_ref) + 5.0);
	float moss = clamp(up * smoothstep(0.35, 0.7, mn + vcol.a * 0.3) * moss_amount * 1.6, 0.0, 1.0);
	col = mix(col, pal_moss * (0.8 + 0.4 * mn), moss * (1.0 - silt * 0.6));
	col *= 1.0 - seam * 0.55;
	col = mix(col, pal_bone * 0.35, rivets * 0.35);
	// ---- draft marks: pale painted numerals near bow and stern, every 1-2 m (a scale cue)
	if (draft.w > 0.5 && abs(vside) > 0.5 && vcol.a < 0.5) {
		float side = vside > 0.0 ? 1.0 : -1.0;
		float dh = draft.z;
		float stepm = dh < 0.45 ? 1.0 : 2.0;
		float dmin = min(draft_column((uv.x - draft.x) * side, uv.y, dh, stepm),
			draft_column((uv.x - draft.y) * side, uv.y, dh, stepm));
		float paintm = (1.0 - smoothstep(-fw, fw, dmin)) * (1.0 - smoothstep(dh * 0.08, dh * 0.3, fw));
		col = mix(col, pal_bone * 0.5, paintm * (0.8 - 0.55 * rust) * (1.0 - moss * 0.7) * (1.0 - silt));
	}
	// ---- portholes: per-port discs up close, their average coverage once the rows get small on screen
	float k = floor((uv.y - porthole_row_start) / porthole_row_step + 0.5);
	float zone_g = step(0.5, vcol.g);
	float zone = zone_g * step(0.0, k) * step(k, porthole_rows - 1.0);
	// ---- doors at the foot of the superstructure tiers: 0.85 x 1.95 m on every ship (a human-scale cue)
	if (door_spacing > 0.0 && zone > 0.5) {
		float dc = floor(uv.x / door_spacing);
		float hd = hcell(ivec2(int(dc), int(k)), iseed * 5 + 17);
		if (hd < 0.45) {
			float dx = (dc + 0.25 + hd) * door_spacing;
			float fl = k * porthole_row_step;                 // the tier's floor (UV.y from the main deck)
			vec2 dq = abs(vec2(uv.x - dx, uv.y - fl - 1.05)) - vec2(0.43, 0.98);
			float dsd = max(dq.x, dq.y);
			float dfade = 1.0 - smoothstep(0.25, 0.7, fw);
			float door = (1.0 - smoothstep(-fw, fw, dsd)) * dfade;
			float dframe = (1.0 - smoothstep(-fw, fw, abs(dsd - 0.05) - 0.04)) * dfade * (1.0 - smoothstep(0.04, 0.1, fw));
			col = mix(col, pal_steel * mix(0.25, 0.5, hd), door * 0.92);
			col = mix(col, rustc * 0.8, dframe * 0.6);
			zone *= step(0.43 + porthole_radius * 1.6, abs(uv.x - dx));    // no port through a door
		}
	}
	float cy = porthole_row_start + k * porthole_row_step;
	float cxi = floor(uv.x / porthole_spacing);
	vec2 c = vec2((cxi + 0.5) * porthole_spacing, cy);
	float d = length(uv - c);
	float r_eff = max(porthole_radius, fw * 1.2);
	float hole = (1.0 - smoothstep(r_eff - fw, r_eff + fw, d)) * zone;
	float energy = (porthole_radius * porthole_radius) / (r_eff * r_eff);
	float rimd = abs(d - porthole_radius * 1.25) - porthole_radius * 0.18;
	float rim = (1.0 - smoothstep(-fw, fw, rimd)) * zone * (1.0 - smoothstep(0.05, 0.15, fw));
	float lit = step(1.0 - amber_fraction, hcell(ivec2(int(cxi), int(k)), iseed * 7 + 3));
	float cell_px = min(porthole_spacing, porthole_row_step) / fw;
	float lod = 1.0 - smoothstep(3.0, 7.0, cell_px);                     // 1 = average the cell
	float lo_y = porthole_row_start - 0.5 * porthole_row_step;
	float hi_y = porthole_row_start + (porthole_rows - 0.5) * porthole_row_step;
	float band = zone_g * smoothstep(lo_y - fw, lo_y + fw, uv.y) * (1.0 - smoothstep(hi_y - fw, hi_y + fw, uv.y));
	float cover = clamp(PI * porthole_radius * porthole_radius / (porthole_spacing * porthole_row_step), 0.0, 1.0) * band;
	float dark_p = mix(hole * energy * (1.0 - lit), cover * (1.0 - amber_fraction), lod);
	float lit_p = mix(hole * energy * lit, cover * amber_fraction, lod);
	col = mix(col, pal_steel * 0.25, dark_p);
	col = mix(col, pal_bone * 0.3, rim * 0.5 * (1.0 - lod));
	float flick = 0.85 + 0.15 * sin(uw_time * 0.7 + cxi * 1.7);
	vec4 fg = uw_fog_eval(cam, wpos);
	if (fog_floor.y > 0.0) {
		fg.a = max(fg.a, smoothstep(fog_floor.x, fog_floor.y, dist));
	}
	// a lit port shows only where its plating reads too: no amber specks hanging in the fog, and no
	// smeared slivers at grazing angles (the isotropic footprint stretches the disc along the surface); far off the
	// plating sinks into the water colour before the fog hides it, so the lights go first
	float vis = smoothstep(0.06, 0.4, 1.0 - fg.a) * smoothstep(0.12, 0.4, ndv) * (1.0 - smoothstep(55.0, 110.0, dist));
	vec3 emis = pal_amber * amber_energy * lit_p * mix(flick, 1.0, lod) * vis;
	col = mix(col, vec3(0.0), lit_p);
	float ao = mix(1.0, vcol.r, 0.85);
	vec3 alb = col * ao * uw_albedo_light(wpos.y);
	ALBEDO = alb;
	ROUGHNESS = mix(0.55, 0.9, max(rust, silt));
	float metal = 0.25 * (1.0 - rust) * (1.0 - silt);
	METALLIC = metal;
	SPECULAR = 0.3;
	f0_v = mix(vec3(0.0144), alb, metal);
	// ---- caustics (sunlight, applied in light()): upward-facing surfaces in the shallows only
	caus_v = 0.0;
	if (wpos.y > -62.0 && dist < 85.0 && nw.y > 0.0) {
		float l = uw_light(wpos.y);
		float cs = uw_caustics(wpos.xz * 1.8, uw_time);
		cs *= l * l * (1.0 - smoothstep(22.0, 60.0, -wpos.y)) * (1.0 - smoothstep(30.0, 85.0, dist));
		cs *= (1.0 - smoothstep(0.06, 0.22, fw)) * smoothstep(0.05, 0.75, nw.y);
		caus_v = cs * caustic_gain;
	}
	// the water-coloured rim keeps far silhouettes readable; close up it made the flanks read as glass
	float rimk = mix(0.35, 1.0, smoothstep(25.0, 140.0, dist));
	EMISSION = emis + uw_ambient_glow(nw, vw, wpos.y) * ao * rimk;
	FOG = fg;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float r = ROUGHNESS;
	// diffuse_lambert_wrap (energy conserving wrap, as Godot's built-in)
	float wrap = max(0.0, (ndl + r) / ((1.0 + r) * (1.0 + r))) / PI;
	DIFFUSE_LIGHT += LIGHT_COLOR * wrap * ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL && caus_v > 0.0) {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (caus_v * clamp(ndl * 1.4 + 0.25, 0.0, 1.0) / PI);
	}
	// GGX lobe (Schlick fresnel, Schlick-Smith visibility)
	float cndl = clamp(ndl, 0.0, 1.0);
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
	float a = r * r;
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float dist_ggx = a2 / (PI * dd * dd);
	float k = a * 0.5;
	float vis = 0.25 / ((cndl * (1.0 - k) + k) * (ndv * (1.0 - k) + k));
	float fc = pow(1.0 - clamp(dot(LIGHT, h), 0.0, 1.0), 5.0);
	vec3 fr = f0_v + (vec3(1.0) - f0_v) * fc;
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * dist_ggx * vis * fr * cndl;
}
