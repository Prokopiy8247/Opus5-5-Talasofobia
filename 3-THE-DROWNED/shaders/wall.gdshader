shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// The Wall: the side of a ship of impossible size. Coordinates are world metres (x along the wall, y = height;
// the wall mesh's UV is the same), so the rub rails and the door's doubler plate share this shader (plain = 1).
// Decks are 12 m with one porthole row each, lapped strakes at the deck lines. Decks come in tiers of five
// (tier_k0 + 5n is a bare belt, then three rows, a fourth in some stretches; the rub rails sit on the belts).
// Along a row the ports come in cabins of two or three with gaps; some bays have no ports, some compartments
// stay dark. Ports are large discs with a dark rim; a lit port throws a tight warm spill on the plate round
// it. The plating is dark steel: the lit field lights it only faintly (the water scatters some light back),
// enough to show the pale weathered paint of the stencilled "07" (painted round the ports: its windows are lit like any other).
// uw_reveal.x 0 -> 0.3 fades the dark hull in out of the fog (it stays a shade darker than the water),
// 0.3 -> 1 switches the lights on deck by deck from wave_origin: rows start in turn outward from the origin's
// deck and spread sideways fast, cabin by cabin (AudioDirector puts its relay clicks on the matching ellipse,
// x radius rf, y radius rf / 1.5). uw_dark 0 -> 1 kills them again from the far ends toward the door. The
// wall dissolves into the water toward its top, its far ends and on steep upward views, so no edge shows.
// walk_s (the diver's s, set every frame by Beat05_Wall) times a few early failures, a deck browning out
// and a shadow passing behind a row during the long look up the wall.
#include "res://shaders/inc/uw.gdshaderinc"

global uniform float uw_dark;

uniform vec2 wave_origin = vec2(-380.0, -340.0);         // x, y on the wall where the light wave starts
uniform vec3 door_pos = vec3(170.0, -985.0, -934.2);     // foot of the door (world)
uniform vec4 digits_rect = vec4(100.0, -918.0, 300.0, 196.0);   // x, y (bottom-left), width, height
uniform vec4 backdrop = vec4(-380.0, -380.0, 330.0, 330.0);     // lit zone behind the statue: centre, radii
uniform vec4 rail_y = vec4(-924.0, -684.0, -564.0, -384.0);    // rub rail centres (deck lines of the belts)
uniform float deck = 12.0;
uniform float tier_k0 = -82.0;         // a belt deck index: decks tier_k0 + 5n carry no ports
uniform float spacing = 7.0;           // porthole pitch inside a cabin (cabins are four sites wide)
uniform float hole_r = 1.8;
uniform float lit_fraction = 0.5;      // share of lit cabins away from the lit zones
uniform float amber_energy = 5.5;
uniform float far_boost = 1.0;         // extra emission far away, so the lights carry through fog
uniform float spill_gain = 1.0;        // warm light on the plating right round each lit port
uniform float sheen_gain = 1.0;        // the lit field's faint light on the plating and the paint
uniform float haze_gain = 1.0;         // warm in-scatter in the water in front of densely lit areas
uniform vec2 door_dark = vec2(34.0, 50.0);   // a dead compartment over the door: half width, height (m)
uniform float walk_s = 0.0;            // the diver's s on the line (Beat05_Wall sets it every frame)
uniform vec2 brownout = vec2(1236.0, -654.0);  // s when one row browns out and comes back, y of that row
uniform vec2 passer = vec2(1208.0, -702.0);    // s when a shadow starts crossing behind a row, its y
uniform float plain = 0.0;             // 1 = rub rail / doubler plate: plating, rust and the field's light only
uniform float tone = 1.0;              // plating tone (the door's doubler plate is a little darker)
// The door lamp lights the plate here, softly, instead of through its omni (the wall is on DoorLamp.WALL_LAYER,
// outside the lamp's cull masks): the omni's hard shadows of the shade, the lintel and the ladder made two
// thin pale edges in a V and a dark wedge on the plate. DoorLamp sets these.
uniform vec3 lamp_pos = vec3(0.0, 100000.0, 0.0);
uniform vec3 lamp_col : source_color = vec3(1.0, 0.7, 0.35);
uniform float lamp_power = 0.0;        // light energy (DoorLamp.OMNI_ENERGY x power)
uniform float reveal_override = -1.0;  // debug: >= 0 replaces uw_reveal.x
uniform float dark_override = -1.0;    // debug: >= 0 replaces uw_dark

varying vec3 wpos;
varying vec3 wnrm;
varying float sk_v;     // the lost sun's specular fades with depth (no white hotspot at 1 km)
varying float f0_v;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// integer hash of an integer-valued cell (exact: no lit/unlit flicker at the threshold)
float ihash(vec2 p, uint salt) {
	uvec2 q = uvec2(ivec2(p) + ivec2(1048576));
	uint h = (q.x * 73856093u) ^ (q.y * 19349663u) ^ (salt * 83492791u);
	h = (h ^ (h >> 13u)) * 1274126177u;
	h ^= h >> 16u;
	return float(h & 65535u) / 65535.0;
}

// line mask with an explicit footprint; sub-pixel lines fade to their coverage instead of aliasing
float aa_line(float x, float hw, float fw) {
	float c = 1.0 - smoothstep(hw - fw, hw + fw, abs(x));
	return c * clamp(2.0 * hw / fw, 0.0, 1.0);
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// signed distance in metres to the stencilled "07" (negative = paint), with stencil bridges
float sd_07(vec2 uv) {
	vec2 o = digits_rect.xy;
	float W = digits_rect.z;
	float H = digits_rect.w;
	float sw = H * 0.085;          // stroke half width
	float gw = W * 0.4;            // glyph width (the rest is the gap between the glyphs)
	float br = H * 0.03;           // bridge half width
	// 0: rounded ring, bridged top and bottom
	vec2 q0 = uv - (o + vec2(gw * 0.5, H * 0.5));
	float rr = (gw * 0.5 - sw) * 0.8;
	float d0 = abs(sd_box(q0, vec2(gw * 0.5 - sw, H * 0.5 - sw) - rr) - rr) - sw;
	d0 = max(d0, br - abs(q0.x));
	// 7: bar and a diagonal with a bridge under the bar, flat foot
	vec2 q7 = uv - (o + vec2(W - gw * 0.5, H * 0.5));
	float bar = sd_box(q7 - vec2(0.0, H * 0.5 - sw), vec2(gw * 0.5, sw));
	float top = H * 0.5 - 2.0 * sw - 2.0 * br;
	float diag = sd_seg(q7, vec2(gw * 0.5 - sw * 1.2, top + sw), vec2(-gw * 0.12, -H * 0.5)) - sw;
	diag = max(diag, max(q7.y - top, -q7.y - H * 0.5));
	return min(d0, min(bar, diag));
}

// 1 if deck k carries a porthole row at x: tiers of five decks (a bare belt, three rows, a fourth row in
// some 192 m stretches, the first one missing in a few 144 m stretches), never next to a rub rail
float row_has(float k, float x) {
	float j = mod(k - tier_k0, 5.0);
	float tier = floor((k - tier_k0) / 5.0);
	float h = step(1.5, j) * step(j, 3.5) + step(3.5, j) * step(0.5, ihash(vec2(floor(x / 192.0), tier), 71u))
		+ step(0.5, j) * step(j, 1.5) * step(0.15, ihash(vec2(floor(x / 144.0 + 0.5), tier), 73u));
	vec4 g = step(vec4(7.0), abs(vec4((k + 0.5) * deck) - rail_y));
	return h * g.x * g.y * g.z * g.w;
}

// The porthole site of deck k nearest to x along its row (each row has its own offset): cx its centre, si its
// index, cab its cabin (four sites: two or three ports, then a gap). Returns 1 when a port is there.
float port_site(float k, float x, out float cx, out float si, out float cab) {
	float roff = ihash(vec2(k, 5.0), 17u) * spacing * 4.0;
	si = floor((x + roff) / spacing);
	cab = floor(si / 4.0);
	cx = (si + 0.5) * spacing - roff;
	float nports = 2.0 + step(0.4, ihash(vec2(cab, k), 19u));
	float tier = floor((k - tier_k0) / 5.0);
	float bare = step(ihash(vec2(floor((cx + 57.0 * tier) / 96.0), tier), 61u), 0.12);   // a bay with no ports
	return row_has(k, cx) * step(si - cab * 4.0 + 0.5, nports) * (1.0 - bare);
}

// 0..1: densely lit around the digits and behind the statue (large soft ellipses: no frame round the number)
float lit_zone(vec2 p) {
	vec2 dc = digits_rect.xy + digits_rect.zw * 0.5;
	float z = 1.0 - smoothstep(0.45, 1.0, length((p - dc) / vec2(330.0, 230.0)));
	return max(z, 1.0 - smoothstep(0.6, 1.0, length((p - backdrop.xy) / backdrop.zw)));
}

// share of port sites with a lit lamp (before the wave and the dying), smooth: the far average
float lit_share(vec2 p) {
	float zone = lit_zone(p);
	float slow = uw_vnoise2(p * vec2(0.0017, 0.0045) + 3.1);
	return mix(lit_fraction * (0.45 + 0.9 * slow), 0.86, zone) * (1.0 - 0.22 * (1.0 - 0.7 * zone)) * 0.94;
}

void fragment() {
	vec2 uv = wpos.xy;
	float fwx = max(fwidth(uv.x), 1e-4);
	float fwy = max(fwidth(uv.y), 1e-4);
	float fwi = max(fwx, fwy);
	float R = reveal_override >= 0.0 ? reveal_override : uw_reveal.x;
	float D = dark_override >= 0.0 ? dark_override : uw_dark;
	float fade_in = smoothstep(0.0, 0.3, R);
	float wv = clamp((R - 0.3) / 0.7, 0.0, 1.0);
	// the wave: the front crosses the reveal frame at a steady pace, then races away (AudioDirector: same rf)
	float rf = 480.0 * wv + 2520.0 * pow(wv, 10.0);
	// the lights die behind you: a shrinking front toward the door, row by row. The far ends (out of sight)
	// go within D 0.05; the rows in view die over D 0.05-0.78 (AudioDirector mirrors F for the clunks)
	float F = -45.0 + 1200.0 * pow(1.0 - D, 2.2) + 1900.0 * (1.0 - smoothstep(0.0, 0.05, D));
	vec2 door = door_pos.xy;
	vec3 n = normalize(wnrm);
	vec3 to_cam = CAMERA_POSITION_WORLD - wpos;
	float dist = length(to_cam);
	vec3 vw = to_cam / max(dist, 1e-3);
	// lights carry through the murk: past ~400 m (behind the statue in M5) they are boosted further
	float boost = 1.0 + far_boost * smoothstep(120.0, 420.0, dist) + 2.0 * far_boost * smoothstep(400.0, 900.0, dist);
	float port_ok = 1.0 - plain;
	float sdig = sd_07(uv);
	// the wall never shows an edge: it dissolves into the water on steep upward views (into the light from
	// above), toward its top and toward its far ends
	float vanish = max(max(smoothstep(0.64, 0.98, -vw.y), smoothstep(-200.0, 0.0, wpos.y)),
		smoothstep(1500.0, 2200.0, abs(wpos.x)));

	// ---- plating: one strake per deck, lapped at the deck line, 24 m plates with staggered butts
	float kd = floor(uv.y / deck);
	float fy = uv.y - kd * deck;                       // metres above this strake's lower (lapped) edge
	float under = deck - fy;                           // metres below the next lap above
	float bx = (uv.x + 12.0 * mod(kd, 2.0)) / 24.0;
	float fxp = (0.5 - abs(fract(bx) - 0.5)) * 24.0;   // metres to the nearest butt
	float pvar = ihash(vec2(floor(bx), kd), 3u) - 0.5;
	vec3 col = pal_steel * (1.0 + pvar * 0.35) * tone;
	// the upper plate's edge stands proud (a lip) and shades a band of the plate under it; kept faint so the
	// laps do not draw a line under every row
	float lip = aa_line(fy - 0.07, 0.07, fwy);
	float lap_sh = aa_line(under - 0.2, 0.2, fwy);
	float seam = aa_line(fxp, 0.04, fwx);
	float dfr = abs(fract((uv.x - 24.0) / 48.0 + 0.5) - 0.5) * 48.0;
	float frame = aa_line(dfr, 0.3, fwx);              // internal frames show as faint vertical lines
	float rivet = 0.0;
	if (fwi < 0.05) {      // close up only (no derivatives inside: safe to branch)
		float rx_ = (fract(uv.x / 0.55) - 0.5) * 0.55;
		float rd = min(length(vec2(rx_, fy - 0.3)), length(vec2(rx_, under - 0.55)));
		rivet = (1.0 - smoothstep(0.045, 0.075, rd)) * (1.0 - smoothstep(0.025, 0.05, fwi));
	}
	col *= (1.0 + 0.5 * lip + 0.6 * rivet) * (1.0 - 0.35 * lap_sh) * (1.0 - 0.4 * seam) * (1.0 - 0.15 * frame);

	// ---- the porthole of this deck's row nearest to this point
	float cy = (kd + 0.5) * deck;
	float cxp, si, cab;
	float port_here = port_site(kd, uv.x, cxp, si, cab) * port_ok;
	vec2 c = vec2(cxp, cy);
	vec2 dv = uv - c;
	float dm = length(dv);
	float tier = floor((kd - tier_k0) / 5.0);
	float hw = ihash(vec2(kd, 7.0), 41u);              // this row's timing

	// ---- rust: a few long weeping runs under some ports (not one per port), rust bleeding from the laps,
	// runs under the rub rails, broken patches. Dark brown: in a port's spill it reads as a stain, not a glow.
	float ka = kd + step(cy, uv.y);                    // the deck whose port is the nearest above
	float below = (ka + 0.5) * deck - uv.y;            // metres under that row (0..12)
	float cxa, sia, caba;
	float pa = port_site(ka, uv.x, cxa, sia, caba);
	float ha = ihash(vec2(sia, ka), 53u);
	float wob = (uw_vnoise2(vec2(uv.y * 0.25, sia * 1.7)) - 0.5) * 0.9;
	float dwid = hole_r * (0.15 + 0.35 * fract(ha * 3.1));
	float dlen = 3.0 + 9.0 * fract(ha * 7.7);
	float drip = (1.0 - smoothstep(dwid * 0.4, dwid, abs(uv.x - cxa + wob))) * smoothstep(hole_r * 1.2, hole_r * 1.6, below)
		* (1.0 - smoothstep(dlen * 0.3, dlen, below)) * step(0.88, ha) * pa * port_ok;
	float breakup = 0.5 + 0.5 * uw_vnoise2(uv * vec2(1.4, 0.14));
	vec4 rb = rail_y - 1.5 - uv.y;
	vec4 rr4 = smoothstep(vec4(0.0), vec4(1.0), rb) * (1.0 - smoothstep(vec4(3.0), vec4(26.0), rb));
	float rail_run = max(max(rr4.x, rr4.y), max(rr4.z, rr4.w))
		* smoothstep(0.45, 0.85, uw_vnoise2(vec2(uv.x / 2.3, uv.y / 38.0))) * breakup;
	float lap_run = smoothstep(0.68, 0.92, uw_vnoise2(vec2(uv.x / 1.9, kd * 3.1)))
		* (1.0 - smoothstep(1.0, 3.0 + 6.0 * uw_vnoise2(vec2(uv.x / 0.9, kd * 1.7)), under)) * breakup;
	float patchy = smoothstep(0.6, 0.88, uw_fbm2(uv * 0.011)) * 0.5;
	float runs = clamp(drip * 0.8 + rail_run * 0.7 + lap_run * 0.5, 0.0, 1.0) * mix(0.35, 1.0, smoothstep(6.0, 30.0, length(uv - door)));
	float rust = clamp(runs + patchy, 0.0, 1.0);
	vec3 rc = mix(pal_rust * 0.2, pal_rust * 0.36, uw_vnoise2(uv * 0.3));
	rc = mix(rc, vec3(dot(rc, vec3(0.333))), 0.4);
	col = mix(col, rc, rust);
	float low = 1.0 - smoothstep(-985.0, -900.0, wpos.y);
	if (low > 0.0) {      // (no derivatives inside: safe to branch)
		col = mix(col, pal_moss * 0.7, low * smoothstep(0.3, 0.7, uw_fbm2(uv * 0.08)) * 0.8);
	}

	// ---- stencilled number: pale weathered paint over the steel (flaking, stained by the runs from above)
	float stencil = (1.0 - smoothstep(-fwi, fwi, sdig)) * port_ok;
	float ink = 0.0;
	if (stencil > 0.0) {      // (no derivatives inside: safe to branch)
		float wear = uw_fbm2(uv * 0.045 + 1.7);
		ink = stencil * smoothstep(0.26, 0.46, wear + 0.16) * (1.0 - 0.65 * rust);
	}
	vec3 paint = mix(pal_bone * 0.36, pal_bone * 0.5, uw_vnoise2(uv * 0.2));
	col = mix(col, paint, ink);
	vec3 col_plate = col;                              // plate + rust + paint, before the port

	// ---- which portholes are lit: cabins switch together; dead compartments are whole blocks of a tier
	float hl = ihash(vec2(cab, kd), 13u);              // cabin: lit or not, its wave timing
	float hk = ihash(vec2(cab, kd), 67u);              // cabin: lamp colour and brightness
	float hp = ihash(vec2(si, kd), 23u);
	float hq = ihash(vec2(si, kd), 37u);
	float hf = ihash(vec2(si, kd), 83u);
	float zone = lit_zone(c);
	float slow = uw_vnoise2(c * vec2(0.0017, 0.0045) + 3.1);
	float p_cab = mix(lit_fraction * (0.45 + 0.9 * slow), 0.86, zone);
	float dead = step(ihash(vec2(floor((c.x + 31.0 * tier) / 84.0), tier), 29u), 0.22 * (1.0 - 0.7 * zone));
	// a dead compartment over the door, aligned to the decks (the lamp is the accent there)
	float dwd = door_dark.x * (0.7 + 0.6 * ihash(vec2(kd, 9.0), 43u));
	float door_ok = 1.0 - step(abs(c.x - door.x), dwd) * step(c.y, door.y + door_dark.y);
	float lit = step(hl, p_cab) * (1.0 - dead) * step(hp, 0.94) * door_ok * port_here;
	// deck by deck: each row starts when the front reaches it (|dy| x 1.5, like the audio's ellipse) and
	// spreads sideways three times as fast, cabin by cabin
	float dw = abs(cy - wave_origin.y) * 1.5 + abs(c.x - wave_origin.x) / 3.0 + (hw - 0.5) * 30.0 + (hl - 0.5) * 6.0;
	float age = rf - dw;
	float young = exp(-max(age, 0.0) / 10.0);
	float strobe = step(0.3, ihash(vec2(cab + kd * 31.0, floor(uw_time * 14.0)), 5u));
	float on = smoothstep(0.0, 2.0, age) * mix(1.0, strobe, young) * (1.0 + 1.2 * young);
	// just ahead of the front the filaments warm up: a dull red-brown glow in the row about to light
	float warmup = 0.05 * smoothstep(-25.0, -2.0, age) * (1.0 - smoothstep(0.0, 2.0, age));
	float dd = length((c - door) * vec2(1.0, 1.6)) + (hw - 0.5) * 60.0 + (hl - 0.5) * 14.0;
	float alive = 1.0 - smoothstep(F - 3.0, F + 3.0, dd);
	float dying = smoothstep(F - 30.0, F - 2.0, dd) * step(0.001, D);
	alive *= mix(1.0, step(0.45, ihash(vec2(cab * 3.0 + kd, floor(uw_time * 9.0)), 7u)), dying);

	// ---- every cabin has its own lamp: deep sodium amber to a sickly yellow-white, dim to bright; some
	// lamps are failing (a dull brown glow), a few stutter in bursts; all of them shimmer a little
	float tk = hk * hk * 0.9;
	vec3 tint = mix(vec3(1.0), vec3(1.0, 1.85, 4.6), tk) / (1.0 + 0.45 * tk);
	tint = mix(tint, vec3(0.7, 1.95, 8.5), step(0.985, hq));                 // a rare pale lamp
	float bright = (0.4 + 0.85 * fract(hk * 7.31)) * (0.85 + 0.3 * hq);
	float fail = step(hf, 0.07);
	bright *= mix(1.0, 0.08 + 0.17 * fract(hf * 91.7), fail);
	tint = mix(tint, vec3(1.0, 0.7, 0.5), fail);
	float fast = step(0.4, ihash(vec2(si * 7.0 + kd, floor(uw_time * 11.0)), 13u));
	float burst = smoothstep(0.6, 0.7, uw_vnoise2(vec2(uw_time * 0.4, hf * 977.0)));
	bright *= mix(1.0, 0.1 + 0.9 * fast, burst * step(0.07, hf) * step(hf, 0.085));
	bright *= 1.0 + 0.018 * sin(uw_time * 0.83 + hq * 40.0) + 0.012 * sin(uw_time * 2.1 + hp * 57.0);
	// foreshadowing on the long look up the wall: 4 % of the lamps stutter and die, one by one
	float early = step(0.085, hf) * step(hf, 0.125);
	float s_die = 1205.0 + 140.0 * fract(hf * 53.3);
	float e_fl = step(0.5, ihash(vec2(si + kd * 17.0, floor(uw_time * 12.0)), 9u));
	float e_alive = 1.0 - early * (step(s_die, walk_s) + step(s_die - 5.0, walk_s) * step(walk_s, s_die) * (1.0 - e_fl));
	// one deck browns out along its length and comes back; something passes behind a row of cabins
	float bo_ph = walk_s - brownout.x - (c.x - 250.0) / 70.0;
	float bo = smoothstep(0.0, 3.0, bo_ph) * (1.0 - smoothstep(12.0, 18.0, bo_ph)) * step(abs(cy - brownout.y), 0.5);
	bright *= 1.0 - bo * (0.62 + 0.18 * fast);
	float ps_x = digits_rect.x - 60.0 + (walk_s - passer.x) * 6.0;   // crosses the number left to right
	float ps = exp(-pow((c.x - ps_x) / 5.5, 2.0)) * step(abs(cy - passer.y), 0.5) * step(passer.x, walk_s);
	bright *= 1.0 - 0.88 * ps;
	float Lw = lit * on * alive * e_alive;
	vec3 lamp = pal_amber * tint * bright * amber_energy * boost;

	// ---- porthole disc, filtered by the pixel footprint (energy and coverage conserving)
	float rx = sqrt(hole_r * hole_r + 0.64 * fwx * fwx);
	float ry = sqrt(hole_r * hole_r + 0.64 * fwy * fwy);
	float dn = length(dv / vec2(rx, ry));
	float e = clamp(max(fwx / rx, fwy / ry), 0.05, 0.9);
	float hole = (1.0 - smoothstep(1.0 - e, 1.0 + e, dn)) * port_here;
	float hole_cov = hole * hole_r * hole_r / (rx * ry);
	float glass_fall = 0.5 + 0.5 * clamp(1.0 - dn * dn, 0.0, 1.0);
	// far or grazing: once the ports along a row merge (horizontal footprint over ~2 m) the row turns into a
	// streak of its average light, as tall as the filtered port (not a band filling the whole deck)
	float lod = smoothstep(2.2, 4.0, fwx);
	float ryc = min(ry, deck * 0.5);
	float cov = PI * hole_r * hole_r / (spacing * 2.0 * ryc) * (1.0 - smoothstep(ryc - fwy, ryc + fwy, abs(dv.y)));
	// a cold light passing once behind a row of ports near the door as the last lamps die (D 0.56-0.93 =
	// s ~1363-1418 with Main.DARK_S 1265-1450): two or three ports at a time, a little light on rims and plate
	float mv_env = smoothstep(0.56, 0.62, D) * (1.0 - smoothstep(0.86, 0.93, D));
	float mv_x = mix(330.0, door.x + 14.0, smoothstep(0.58, 0.88, D));
	float mv_y = floor((door.y + 43.0) / deck) * deck + deck * 0.5;
	float mv = exp(-pow((c.x - mv_x) / 4.0, 2.0)) * mv_env * (1.0 - step(1.0, abs(cy - mv_y))) * port_here;
	vec3 cold = vec3(0.75, 0.88, 1.0) * 3.0;
	vec3 emis = lamp * (Lw + vec3(1.0, 0.4, 0.12) * (lit * warmup)) + cold * mv;
	vec3 emis_port = emis * hole_cov * glass_fall;
	// a dark rim round the glass, a tight warm spill on the plate beyond it (gone before the next port)
	float r_rim = hole_r * 1.3;
	float in_rim = (1.0 - smoothstep(r_rim - fwi, r_rim + fwi, dm)) * port_here;
	float rim = max(in_rim - hole, 0.0) * (1.0 - lod);
	float spill = exp(-max(dm - r_rim, 0.0) / 0.6) * (1.0 - smoothstep(spacing * 0.4, spacing * 0.5, dm)) * (1.0 - in_rim) * port_here;
	float bolts = rim * step(0.75, cos(atan(dv.y, dv.x) * 12.0)) * (1.0 - smoothstep(0.03, 0.06, fwi));
	emis_port += emis * (col_plate * spill * spill_gain * 1.3 + pal_steel * rim * 0.4);

	// ---- the lights' smooth density (share of port sites lit, after the wave and the dying): the far-away
	// average of a row, the faint light of the whole field on the plate and the paint, the haze in front
	float plit = lit_share(uv);     // (the dead compartment over the door still gets the field's light)
	float alive_s = 1.0 - smoothstep(F - 30.0, F + 30.0, length((uv - door) * vec2(1.0, 1.6)));
	float wa = rf - (abs(uv.y - wave_origin.y) * 1.5 + abs(uv.x - wave_origin.x) / 3.0);
	float dens_v = plit * smoothstep(-15.0, 15.0, wa) * alive_s * (0.7 * 0.65 * 0.88);   // all decks averaged
	float wa_r = rf - (abs(cy - wave_origin.y) * 1.5 + abs(uv.x - wave_origin.x) / 3.0 + (hw - 0.5) * 30.0);
	float pres = row_has(kd, uv.x) * 0.65 * 0.88 * port_ok;                               // this row's port share
	float dens_row = plit * smoothstep(-6.0, 6.0, wa_r) * alive_s * pres;
	vec3 warm = pal_amber * vec3(1.0, 1.25, 1.6);       // the mixed lamps on average
	float field = amber_energy * dens_v;                // ~ the light of the ports around
	vec3 emis_avg = (warm * amber_energy * boost * dens_row * 0.75 + cold * mv) * cov * 1.08;
	float face = mix(1.0, 0.75 + 0.45 * n.y, plain);    // rails: the top catches the light from above
	// (only part of the far boost: far away the plate must not turn into a glowing tan panel)
	vec3 veil = col_plate * warm * field * (1.0 + 0.35 * (boost - 1.0)) * sheen_gain * 0.5 * face;
	vec3 glass = pal_deep * 0.35;
	float gcov = mix(hole_cov, cov * pres, lod);
	col = mix(col, glass, gcov);
	col = mix(col, pal_steel * 0.45, rim);
	col = mix(col, pal_steel * 1.6, bolts * 0.6);
	// unlit glass: a faint reflection of the brighter water above
	float ndv = clamp(dot(n, vw), 0.0, 1.0);
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
	vec3 refl = uw_water_col(wpos.y + 40.0) * (0.3 + 2.5 * fres);
	emis_port += refl * hole_cov * (1.0 - clamp(Lw, 0.0, 1.0)) * 0.3;
	vec3 emis_all = mix(emis_port, emis_avg, lod) + veil * (1.0 - gcov) * (1.0 - rim);

	// ---- the wall foot: contact darkening and a silt line
	float foot = mix(0.42, 1.0, smoothstep(-985.0, -963.0, wpos.y));
	col *= foot;
	emis_all *= mix(foot, 1.0, 0.5);
	col = mix(col, mix(pal_moss * 0.5, pal_teal_far * 0.6, 0.5), (1.0 - smoothstep(-984.5, -980.5, wpos.y)) * 0.6);
	// the door lamp: like its omni (wrap diffuse, 1/d decay, 18 m range) on the plate's true albedo (the lamp
	// carries the depth compensation), with the shade's shadow above it soft, as from a large bulb
	if (lamp_power > 0.0) {
		vec3 lv = wpos - lamp_pos;
		float ld = max(length(lv), 1e-3);
		if (ld < 18.0) {
			float shade = max(1.0 - smoothstep(0.1, 0.6, lv.y / ld), 0.04);
			float ndl = max(dot(n, -lv) / ld, 0.0);
			float win = pow(max(1.0 - pow(ld / 18.0, 4.0), 0.0), 2.0);
			emis_all += col * lamp_col * lamp_power * shade * (ndl + 0.6) / 2.56 * win / max(ld, 0.35);
		}
	}

	// ---- shading: glossy glass, rough rust; the sun's specular is guarded in light()
	float gl = hole_cov * (1.0 - lod);
	float al = uw_albedo_light(wpos.y);
	// the stylised top light barely shows the paint once the lights are dead (a pale "0" arc, a moon, read
	// alone at the frame's edge); the field's light, the lamps' spill and the door lamp still see it whole
	ALBEDO = col * al * (1.0 - 0.7 * ink);
	ROUGHNESS = mix(mix(0.5, 0.9, max(rust, ink * 0.8)), 0.12, gl);
	METALLIC = 0.2 * (1.0 - rust) * (1.0 - ink) * (1.0 - gl);
	sk_v = clamp(uw_light(wpos.y) * 4.0, 0.0, 1.0);
	f0_v = mix(0.0144 * (1.0 - METALLIC) + 0.04 * METALLIC, 0.04, gl);
	EMISSION = (emis_all + uw_ambient_glow(n, vw, wpos.y) * 0.8) * (1.0 - vanish);
	// fog: a shade darker than the water (the hull reads as a mass); where it dissolves, fog only (past its top
	// is the water surface at the same distance, past its ends water far away: no edge)
	vec4 f = uw_fog_eval(CAMERA_POSITION_WORLD, wpos);
	f.a = mix(min(f.a, 0.9), 1.0, vanish);
	f.a = max(f.a, (1.0 - fade_in) * smoothstep(110.0, 240.0, dist));   // hidden until the reveal
	// the lit field's light scattered in the water in front of it: a warm haze over dense areas
	f.rgb += warm * field * haze_gain * 0.012 * (1.0 - vanish);
	FOG = f;
}

// diffuse_lambert_wrap + GGX like the built-ins, except that the lost sun has no specular at depth
// (no white hotspot on the plating at 1 km, whatever the sun's own light_specular is).
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float r = ROUGHNESS;
	float wrap = max(0.0, (ndl + r) / ((1.0 + r) * (1.0 + r))) / PI;
	DIFFUSE_LIGHT += LIGHT_COLOR * wrap * ATTENUATION;
	float cndl = clamp(ndl, 0.0, 1.0);
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
	float a = max(r * r, 0.002);
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float dist_ggx = a2 / (PI * dd * dd);
	float k = a * 0.5;
	float vis = 0.25 / ((cndl * (1.0 - k) + k) * (ndv * (1.0 - k) + k));
	float fr = f0_v + (1.0 - f0_v) * pow(1.0 - clamp(dot(LIGHT, h), 0.0, 1.0), 5.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * dist_ggx * vis * fr * cndl
		* (LIGHT_IS_DIRECTIONAL ? sk_v : 1.0);
}
