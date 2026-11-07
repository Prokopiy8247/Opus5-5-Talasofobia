shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Rust flake (beat 4 settle event) and rust / silt shed by the sinking hull (beat 3): snow_draw's mote, tinted
// desaturated brown by reflectance (never a glowing ember: amber is reserved for B6), lit only by the torch
// computed here (cone smoothstep(0.82, 0.95) stand-in for the shared torch profile, 82 m range window, water
// extinction), soft near-lens bokeh. Flat flakes tumble: they flash briefly as they turn face-on to the beam.
// Same mote law as the shared snow: the light is computed and compressed PER MOTE (col /= 1 + max(col)),
// then shaped by a gaussian profile (no per-pixel soft clip, so no flat plateaus with hard rims).
// Far flakes dissolve (they are not kept >= 1 px), and the patch edge fades out (no straight edge).
uniform float opacity = 1.0;
uniform float gain = 5.0;
uniform float size_mul = 3.0;
uniform float fade_near = 28.0;
uniform float fade_far = 40.0;
uniform float streak = 1.0;
uniform float shutter = 0.022;
uniform vec3 tint = vec3(0.50, 0.36, 0.27);
uniform vec3 tint_b = vec3(0.50, 0.36, 0.27);   // second tint for CUSTOM.x > 0.5 (beat 3: grey silt)
uniform float range = 82.0;
uniform float decay = 0.55;
uniform float sigma = 0.0175;
uniform float life = 16.0;
uniform vec4 edge = vec4(0.0, 0.0, 0.0, -1.0);   // xz centre, radius of full strength (z), radius of zero (w); w < 0 = off
global uniform vec3 g_torch_pos;
global uniform vec3 g_torch_dir;
global uniform float g_torch;
global uniform vec3 g_cam_pos;
global uniform vec3 g_cam_vel;
global uniform float g_time;

varying vec3 col;      // per-mote light, compressed and faded
varying float elong;
varying float blur;

void vertex() {
	float sc0 = length(MODEL_MATRIX[0].xyz);
	vec3 wpos = MODEL_MATRIX[3].xyz;
	vec4 cu = INSTANCE_CUSTOM;
	float dc = length(wpos - g_cam_pos);
	// --- light, per mote
	vec3 Lt = wpos - g_torch_pos;
	float d = length(Lt);
	float cone = smoothstep(0.82, 0.95, dot(Lt / max(d, 0.001), g_torch_dir));
	float win = pow(max(1.0 - pow(d / range, 4.0), 0.0), 2.0);
	float torch = g_torch * cone * gain * win * pow(max(d, 0.4), -decay) * exp(-sigma * (d + dc));
	// --- size: far flakes shrink below a pixel and dissolve instead of glittering
	float sc = max(sc0 * size_mul, dc * 0.0022);
	blur = smoothstep(2.2, 0.6, dc);
	float scb = sc + blur * 0.03;
	float energy = (sc * sc) / (scb * scb) * mix(1.0, 0.35, blur);
	vec3 vc = (VIEW_MATRIX * vec4(wpos, 1.0)).xyz;
	vec3 vrel = (VIEW_MATRIX * vec4(vec3(0.0, -0.7, 0.0) - g_cam_vel, 0.0)).xyz;
	vec3 p1 = vc + vrel * shutter * streak;
	vec2 s0 = vc.xy / max(-vc.z, 0.05);
	vec2 s1 = p1.xy / max(-p1.z, 0.05);
	vec2 m = (s1 - s0) * max(-vc.z, 0.05);
	float L = min(length(m), scb * mix(10.0, 0.25, smoothstep(0.0, 0.3, blur)));   // same rule as snow_draw: soft flakes stay round
	vec2 ax = L > 1e-5 ? normalize(m) : vec2(1.0, 0.0);
	vec2 ay = vec2(-ax.y, ax.x);
	elong = (scb + L) / scb;
	energy /= elong;
	MODELVIEW_MATRIX = mat4(vec4(ax * (scb + L), 0.0, 0.0), vec4(ay * scb, 0.0, 0.0),
		vec4(0.0, 0.0, scb, 0.0), vec4(vc, 1.0));
	// tumbling flat flakes: mostly edge-on and dim, a brief flash when they turn face-on to the beam
	float tw = 0.12 + 0.88 * pow(abs(sin(g_time * (1.2 + 2.5 * cu.y) + cu.z * 6.283)), 6.0);
	float agef = smoothstep(0.0, 1.5, cu.w) * (1.0 - smoothstep(life - 3.0, life, cu.w));
	float fade = (1.0 - smoothstep(fade_near, fade_far, dc)) * smoothstep(0.35, 1.2, dc) * opacity;
	if (edge.w > 0.0) {
		fade *= smoothstep(edge.w, edge.z, length(wpos.xz - edge.xy));
	}
	vec3 c = (cu.x > 0.5 ? tint_b : tint) * torch * energy * tw * agef * fade;
	col = c / (1.0 + max(max(c.r, c.g), c.b)) * 1.15;   // per-mote compression keeps the hue and the profile
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	q.x *= elong;
	float r = length(vec2(max(abs(q.x) - (elong - 1.0), 0.0), q.y));
	float edge_fade = 1.0 - smoothstep(0.75, 1.0, r);
	float sharp = exp(-4.0 * r * r) * edge_fade;
	float bokeh = exp(-2.2 * r * r) * edge_fade;
	ALBEDO = col * mix(sharp, bokeh, blur);
	ALPHA = 1.0;
	FOG = vec4(0.0);
}
