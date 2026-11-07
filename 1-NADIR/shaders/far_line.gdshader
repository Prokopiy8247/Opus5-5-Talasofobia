shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// Other descent lines hanging in the dark 18-35 m from the diver's own ("you are not the first"). The same
// coverage law as rope.gdshader: the radius inflates with distance so the line never breaks into dashes
// (>= ~0.65 px); here the true coverage of that inflated width goes into ALPHA, so the beam catches faint
// threads, never bars, and never anything brighter than the diver's own line (always nearer, always lit harder).
// Blended, not opaque: no depth write, so the beam haze behind a line is never cut into a dark thread, and
// `fade` (by depth, after the creature has gone) brings the lines in from nothing, with no pop at the 1160 m
// visibility toggle. The same 3-strand lay as the main line. These have hung here for years: furred with
// settled snow (a paler albedo, light wraps a little past the terminator, and the fuzz catches the torch at
// grazing angles, so a line seen nearly end-on from above still shows as a thread converging toward the floor),
// and seen through a little less murk than the solid world, so the beam picks them out at 30-80 m.
// After the lamp reveal, the bottom few metres of each line glow from the lamp hanging at its end.
// UV2 = (height above its lamp, reveal delay), COLOR.r = lamp brightness.
uniform vec4 rope_col : source_color = vec4(0.18, 0.16, 0.12, 1.0);
uniform vec4 lamp_col : source_color = vec4(1.0, 0.706, 0.353, 1.0);
uniform float fade = 0.0;
uniform float reveal_time = -1.0;
uniform float glow_gain = 0.5;
uniform float fog_density = 0.02;   // the scene's (set every frame); these lines use 0.6x of it
uniform vec4 fog_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);   // G.env.fog_light_color (the one water colour)
uniform float fuzz = 2.0;           // grazing back-scatter of the fibres (only matters seen nearly end-on)
const float BASE_R = 0.035;

varying float cover;
varying float v_h;
varying float v_on;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(wp - CAMERA_POSITION_WORLD);
	float r = max(BASE_R, d * 0.00104);   // ~0.65 px at 72 deg / 720p
	cover = BASE_R / r;
	VERTEX += NORMAL * (r - BASE_R);      // world-space mesh (identity transform), NORMAL points outward
	v_h = max(UV2.x, 0.0);
	v_on = smoothstep(UV2.y, UV2.y + 1.4, reveal_time) * COLOR.r;
}

void fragment() {
	float ph = fract(3.0 * UV.x + 1.5 * UV.y);                 // 3 strands, 0.18 m lay (UV.y unit 0.09 m)
	float crown = sqrt(max(1.0 - pow(2.0 * ph - 1.0, 2.0), 0.0));
	float aa = 1.0 - smoothstep(0.2, 0.55, fwidth(UV.y) * 1.5 + fwidth(UV.x) * 3.0);
	// exposure hold on the nearest stretch (18-25 m, in the torch's hot core): never brighter than the diver's own
	// line (<= ~80 sRGB in the torch, rope package). It eases off with distance about as fast as the beam and the
	// murk dim a line, so a thread keeps an even, faint tone along its length down toward the floor.
	float near_k = mix(0.15, 1.0, smoothstep(18.0, 80.0, length(VERTEX)));
	ALBEDO = rope_col.rgb * mix(0.75, 0.5 + 0.4 * crown, aa) * near_k;
	ROUGHNESS = 0.85;
	// its own lamp hangs 0.9 m above the silt at the end of the line: a short warm glow up the strands
	float lit = exp(-v_h / 3.5) + 0.015 * exp(-v_h / 30.0);
	EMISSION = lamp_col.rgb * (lit * v_on * glow_gain);
	ALPHA = clamp(fade * max(cover, 0.05), 0.0, 1.0);
	FOG = vec4(fog_col.rgb, 1.0 - exp(-length(VERTEX) * fog_density * 0.6));
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float wrap = max(ndl + 0.3, 0.0) / 1.3;
	// fibre fuzz: back-scatter toward a light behind the viewer, strongest where the surface is seen edge-on
	float sheen = fuzz * pow(1.0 - ndv, 2.0) * max(dot(LIGHT, VIEW), 0.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (wrap + sheen) / PI;
	vec3 h = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * 0.02 * pow(max(dot(NORMAL, h), 0.0), 16.0) * max(ndl, 0.0);
}
