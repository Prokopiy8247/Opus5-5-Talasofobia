// The Bloop: wet skin material + vertex-shader swimming (Part 10 / 10B).
// Mesh space = model units (30 m long, head +X, belly -Y). Vertex colour masks baked by Tools/bloop_build_mesh.py:
//   R lower jaw, G pectoral fins, B rigid head, A gum / jaw-skin wobble.  UV2: x throat depth, y teeth.
// Animation state (wave_phase, jaw_angle, head_yaw/pitch, body_bend, anim_time) is driven by scripts/Bloop.gd.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms material;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float albedo_mult = 1.15;
uniform vec3 skin_tint : source_color = vec3(0.93, 0.97, 1.0);
uniform vec3 teeth_tint : source_color = vec3(1.0, 0.97, 0.88);
uniform float normal_strength = 1.0;
uniform float rough_mult = 1.0;
uniform float specular_amount = 0.6;
uniform float wet_coat = 0.55;
uniform float wet_coat_roughness = 0.18;
uniform float throat_dark = 0.96;
uniform float light_gain = 5.0;         // diffuse response to the torch (hero readability at 35-60 m)
uniform float spec_gain = 1.5;
uniform float wrap = 0.3;               // wrap lighting so big forms read past the terminator
uniform float rim_gain = 0.5;           // faint lit-edge sheen for the silhouette in the beam
uniform float presence = 1.0;           // 0..1 on all light: unlit, the body is black on black water (no pop)
// soft knee on the linear albedo: skin ~0.15 keeps its value, teeth and belly (0.37-0.49) settle near 0.21
uniform float knee_a = 0.29;
uniform float knee_b = 0.15;
uniform vec3 gum_floor = vec3(0.10, 0.07, 0.08);   // linear: flesh of lips, gums and palate around the teeth

group_uniforms eyeshine;
// Retro-reflection from a tapetum: the dull eye returns the torch straight back down the beam.
uniform vec3 eye_pos = vec3(8.08, 2.31, 4.06);   // model units, mirrored in z
uniform float eye_r = 0.28;
uniform float eyeshine = 0.0;
uniform float eyeshine_gain = 2.0;   // peak stays under the 1.05 glow threshold after the water (no bloom)
uniform vec3 eyeshine_col = vec3(0.34, 0.71, 0.51); // linear, cold green-white (sRGB 0.62/0.86/0.74)

group_uniforms detail;
// Metre-scale skin over the 10x model texture (whose barnacles are metres wide), so the flank reads as hundreds of
// metres of hide: triplanar on the undeformed mesh in metres, only near the camera and never finer than the pixels.
uniform sampler2D detail_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_val : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float detail_amp = 0.0;         // 0 = off (set once the generated textures are assigned)
uniform float detail_tile = 73.0;       // metres per repeat: ~1.2 m cells
uniform float fine_tile = 21.0;         // ~0.35 m cells
uniform float detail_near = 20.0;
uniform float detail_far = 70.0;
uniform float speck_amt = 0.08;         // pale whale-lice speckles, linear albedo added
uniform float scar_amt = 0.05;          // long thin scars along the body

group_uniforms swim;
uniform float body_len = 30.0;
uniform float head_x = 15.0;
uniform float wave_phase = 0.0;
uniform float wave_amp = 1.65;          // model units at the tail tip (before tail follow-through)
uniform float wave_count = 1.0;         // wavelengths along the body
uniform float tail_amp = 0.35;          // extra fluke swing (fraction of wave_amp)
uniform float tail_lag = 1.1;           // radians behind the body wave
uniform float body_bend = 0.0;          // yaw curvature, 1/model-unit (z += bend * x^2 / 2)
uniform float neck_x = 5.0;
uniform float anim_time = 0.0;
uniform float jaw_angle = 0.0;          // radians, + opens the gape
uniform vec2 jaw_hinge = vec2(7.6, -0.8);
uniform float gum_amp = 0.02;
uniform float fin_amp = 0.12;           // radians
uniform float fin_speed = 0.9;
uniform vec3 fin_root = vec3(0.0, -1.7, 4.3);
uniform float head_yaw = 0.0;           // radians, + turns the head toward +Z
uniform float head_pitch = 0.0;         // radians, + raises the head
uniform vec3 head_pivot = vec3(4.0, 0.0, 0.0);
uniform float ripple_amp = 0.012;
uniform float ripple_freq = 1.7;
uniform float ripple_speed = 1.2;

varying float v_wet;
varying float v_teeth;
varying float v_eye;     // eye mask from the undeformed mesh (vertex -> fragment)
varying float v_shine;   // the same, handed on to light()
varying vec3 v_mp;       // undeformed position, metres (skin detail sticks to the hide while it swims)
varying vec3 v_mn;       // undeformed normal
varying float v_fin;     // pectoral fins and flukes: thinner, rougher, darker hide (not smooth latex)

vec2 rot2(vec2 v, float a) {
	float c = cos(a), s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// triplanar helpers on the undeformed hide: w = blend weights from the undeformed normal
vec2 tri_xy(sampler2D t, vec3 p, vec3 w, float tile) {
	vec2 a = texture(t, p.zy / tile).xy * 2.0 - 1.0;
	vec2 b = texture(t, p.xz / tile).xy * 2.0 - 1.0;
	vec2 c = texture(t, p.xy / tile).xy * 2.0 - 1.0;
	return a * w.x + b * w.y + c * w.z;
}

float tri_r(sampler2D t, vec3 p, vec3 w, float tile) {
	return texture(t, p.zy / tile).r * w.x + texture(t, p.xz / tile).r * w.y + texture(t, p.xy / tile).r * w.z;
}

void vertex() {
	vec3 p = VERTEX;
	vec3 n = NORMAL;
	vec3 t = TANGENT;
	vec3 b = BINORMAL;
	float mR = COLOR.r, mG = COLOR.g, mB = COLOR.b, mA = COLOR.a;
	float x0 = VERTEX.x;
	v_eye = 1.0 - smoothstep(eye_r * 0.55, eye_r, distance(vec3(VERTEX.x, VERTEX.y, abs(VERTEX.z)), eye_pos));
	v_mp = VERTEX * 10.0;
	v_mn = NORMAL;

	// 1. jaw sway: rigid rotation about the hinge axis (Z), weighted by the lower-jaw mask
	float ja = -jaw_angle * mR;
	p.xy = jaw_hinge + rot2(p.xy - jaw_hinge, ja);
	n.xy = rot2(n.xy, ja); t.xy = rot2(t.xy, ja); b.xy = rot2(b.xy, ja);

	// 2. gum / jaw-skin wobble along the normal (teeth excluded in the mask)
	float gw = sin(anim_time * 1.3 + p.x * 2.1 + p.z * 1.7) * (0.6 + 0.4 * sin(anim_time * 0.71 + p.y * 2.9));
	p += n * gum_amp * mA * gw;

	// 3. pectoral fin paddling: rotation about the fin root line (along X), mirrored per side
	float side = p.z >= 0.0 ? 1.0 : -1.0;
	float fa = fin_amp * mG * sin(anim_time * fin_speed + side * 0.9 + p.x * 0.35);
	vec2 q = vec2((p.z - side * fin_root.z) * side, p.y - fin_root.y);
	q = rot2(q, fa);
	p.z = side * q.x + side * fin_root.z; p.y = q.y + fin_root.y;
	vec2 nq = rot2(vec2(n.z * side, n.y), fa); n.z = nq.x * side; n.y = nq.y;
	vec2 tq = rot2(vec2(t.z * side, t.y), fa); t.z = tq.x * side; t.y = tq.y;
	vec2 bq = rot2(vec2(b.z * side, b.y), fa); b.z = bq.x * side; b.y = bq.y;

	// 4. head pitch + yaw (counter-sway and look-at), rigid on the head mask
	float hp = head_pitch * mB, hy = head_yaw * mB;
	vec3 h = p - head_pivot;
	h.xy = rot2(h.xy, hp); n.xy = rot2(n.xy, hp); t.xy = rot2(t.xy, hp); b.xy = rot2(b.xy, hp);
	h.xz = rot2(h.xz, hy); n.xz = rot2(n.xz, hy); t.xz = rot2(t.xz, hy); b.xz = rot2(b.xz, hy);
	p = head_pivot + h;

	// 5. tiny skin ripple travelling along the flanks
	float rw = (1.0 - 0.7 * mB) * (1.0 - mG) * (1.0 - mR) * smoothstep(0.2, 0.7, abs(NORMAL.z));
	float rph = x0 * ripple_freq + anim_time * ripple_speed + VERTEX.y * 0.6;
	p += n * (ripple_amp * rw * sin(rph));
	n.x -= ripple_amp * ripple_freq * rw * cos(rph) * 2.0;

	// 6. body wave (up-down, head -> tail) with tail follow-through; zero on the rigid head
	float u = clamp((head_x - x0) / body_len, 0.0, 1.0);
	v_fin = max(mG, smoothstep(0.85, 0.98, u));
	float bw = 1.0 - mB;
	float env = bw * u * u;
	float denv = bw * 2.0 * u;
	float k = 6.2831853 * wave_count;
	float ph = wave_phase - k * u;
	float tw = smoothstep(0.62, 1.0, u);
	float tt = clamp((u - 0.62) / 0.38, 0.0, 1.0);
	float dtw = 6.0 * tt * (1.0 - tt) / 0.38;
	float s1 = sin(ph), c1 = cos(ph), s2 = sin(ph - tail_lag), c2 = cos(ph - tail_lag);
	p.y += wave_amp * (env * s1 + tail_amp * tw * s2);
	float fx = -wave_amp * (denv * s1 - env * k * c1 + tail_amp * (dtw * s2 - tw * k * c2)) / body_len;

	// 7. yaw bend so the body follows a curving path (arc through the root, rigid-ish head)
	float xb = min(x0, neck_x);
	p.z += body_bend * (0.5 * xb * xb + neck_x * max(x0 - neck_x, 0.0));
	float hx = body_bend * xb;

	// shear normals / tangents: y += f(x), z += g(x)
	n = vec3(n.x - fx * n.y - hx * n.z, n.y, n.z);
	t = vec3(t.x, t.y + fx * t.x, t.z + hx * t.x);
	b = vec3(b.x, b.y + fx * b.x, b.z + hx * b.x);
	VERTEX = p;
	NORMAL = normalize(n);
	TANGENT = normalize(t);
	BINORMAL = normalize(b);
}

void fragment() {
	float throat = UV2.x;
	float teeth = UV2.y;
	vec3 col = texture(albedo_tex, UV).rgb * albedo_mult;
	col *= mix(skin_tint, teeth_tint, teeth);
	// soft knee: under a coaxial torch the brightest albedo (teeth, belly) must not float alone in the dark
	col = knee_a * col / (col + knee_b);
	vec3 tw = pow(abs(normalize(v_mn)), vec3(4.0));
	tw /= tw.x + tw.y + tw.z + 1e-5;
	// lips, gums and palate (vertex alpha) get a flesh floor so the jaw line reads around the teeth (~2:1).
	// The floor only lifts the texture's dark inner lip, so a constant floor reads as a painted band: lift it
	// in ~1 m patches (some of the dark tissue shows through, so the edge is ragged) and mottle it like wet
	// tissue, slightly less saturated than the raw floor.
	float gn = tri_r(detail_val, v_mp + vec3(5.0, 9.0, 3.0), tw, 14.0);
	float gum = smoothstep(0.15, 0.85, COLOR.a) * (1.0 - teeth) * mix(0.2, 1.0, smoothstep(0.32, 0.62, gn))
		* (0.55 + 0.45 * tri_r(detail_val, v_mp, tw, 6.0));
	vec3 gfl = mix(gum_floor, vec3(dot(gum_floor, vec3(0.3, 0.55, 0.15))), 0.3);
	col = mix(col, max(col, gfl * (0.6 + 0.8 * tri_r(detail_val, v_mp + vec3(17.0), tw, 3.0))), gum);
	float deep = smoothstep(0.0, 0.9, throat);
	// fins and flukes: darker, mottled hide (the clean convex lobes read as pale latex otherwise)
	col *= mix(1.0, 0.6 + 0.32 * tri_r(detail_val, v_mp, tw, 18.0), v_fin);
	// metre-scale hide (skin only): bumps near the camera, speckles and scars; all fade before going sub-pixel
	float px = length(fwidth(v_mp));   // metres per pixel
	float skin = detail_amp * (1.0 - teeth) * (1.0 - deep) * (1.0 - v_eye) * (1.0 - gum);
	float sk = step(0.001, detail_amp) * (1.0 - teeth) * (1.0 - deep) * (1.0 - v_eye) * (1.0 - gum)
		* (1.0 - smoothstep(0.12, 0.25, px));
	float sp = tri_r(detail_val, v_mp, tw, 9.0);
	col += speck_amt * smoothstep(0.78, 0.84, sp) * sk;
	// scars: the value noise stretched 12:1 along the body, its median contour as thin lines, in sparse patches
	float sc = texture(detail_val, vec2(v_mp.x / 96.0, (v_mp.y * (tw.z + tw.x) + v_mp.z * tw.y) / 8.0)).r;
	float sm = tri_r(detail_val, v_mp + vec3(91.0, 13.0, 57.0), tw, 260.0);
	float line = 1.0 - smoothstep(0.0, max(fwidth(sc) * 1.5, 0.015), abs(sc - 0.5));
	col += scar_amt * line * smoothstep(0.55, 0.7, sm) * sk;
	col *= 1.0 - throat_dark * deep;
	ALBEDO = col;
	vec2 dxy = tri_xy(detail_nrm, v_mp, tw, detail_tile) * (1.0 - smoothstep(0.2, 0.4, px))
		+ tri_xy(detail_nrm, v_mp + vec3(37.0, 11.0, 23.0), tw, fine_tile) * (0.6 * (1.0 - smoothstep(0.06, 0.12, px)));
	// fins and flukes keep their hide further out (they are seen at 35-60 m)
	float reach = smoothstep(mix(detail_far, 120.0, v_fin), detail_near, length(VERTEX));
	dxy *= skin * reach;
	// fin rays and creases across the span, warped so they never read as ruled lines
	dxy += v_fin * 0.3 * (1.0 - teeth) * reach
		* vec2(sin(v_mp.z * 0.8 + 6.0 * tri_r(detail_val, v_mp, tw, 40.0)), 0.0);
	vec2 mxy = texture(normal_tex, UV).xy * 2.0 - 1.0;
	NORMAL_MAP = vec3(clamp((mxy + dxy) * 0.5 + 0.5, 0.0, 1.0), 1.0);   // whiteout blend (Godot rebuilds z)
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = clamp(texture(rough_tex, UV).r * rough_mult, 0.04, 1.0);
	SPECULAR = specular_amount * (1.0 - 0.9 * deep) * (1.0 - 0.35 * v_fin);
	v_wet = wet_coat * (1.0 - deep) * (1.0 - 0.4 * teeth) * (1.0 - 0.5 * v_fin);   // less plastic sheen on fins
	v_teeth = teeth;
	v_shine = v_eye;
}

float ggx(float ndh, float r) {
	float a2 = r * r * r * r;
	float d = ndh * ndh * (a2 - 1.0) + 1.0;
	return a2 / (PI * d * d);
}

// Torch-only lighting: wrapped diffuse + GGX skin lobe + sharp wet coat lobe (glints), shadows via ATTENUATION.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float nl = clamp(ndl, 0.0, 1.0);
	float dif = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 4.0) * clamp(ndl + 0.35, 0.0, 1.0) * rim_gain;
	vec3 lc = ATTENUATION * LIGHT_COLOR * presence;
	DIFFUSE_LIGHT += (dif + rim) * lc / PI * light_gain;
	// eyeshine: only where the eye faces the viewer and the light comes from the viewer (the torch)
	float retro = v_shine * pow(ndv, 6.0) * pow(clamp(dot(LIGHT, VIEW), 0.0, 1.0), 24.0);
	SPECULAR_LIGHT += eyeshine_col * (retro * eyeshine * eyeshine_gain) * lc;
	vec3 hv = normalize(LIGHT + VIEW);
	float ndh = clamp(dot(NORMAL, hv), 0.0, 1.0);
	float fr = pow(1.0 - clamp(dot(LIGHT, hv), 0.0, 1.0), 5.0);
	float f0 = 0.08 * SPECULAR_AMOUNT + 0.03 * v_teeth;
	float sp = (f0 + (1.0 - f0) * fr) * ggx(ndh, max(ROUGHNESS, 0.06));
	float sw = (0.04 + 0.96 * fr) * ggx(ndh, wet_coat_roughness) * v_wet;
	SPECULAR_LIGHT += (sp + sw) * 0.25 * nl * lc * spec_gain;
}
