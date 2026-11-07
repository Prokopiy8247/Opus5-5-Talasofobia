shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Retro-reflective tape collar on the descent line above every depth tag (Rope.gd). A plain silver-grey band
// lit like any surface (never a black cut-out in the blue), plus the retro glint: the sheeting sends light back
// toward its source within ~1 deg, so only tapes far enough that the torch beside the eye is inside that lobe
// flash. Near tapes stay plain bands; looking down the line, the far ones are shrinking sparks at 25 / 50 m.
// The collar has end caps, so seen end-on down the line it still shows a face. It grows with distance like
// the rope (>= ~2 px) with its energy kept constant.
// Torch cone: the stand-in smoothstep(0.82, 0.95) and the light's own 82 m range window (torch contract).
global uniform vec3 g_torch_pos;
global uniform vec3 g_torch_dir;
global uniform float g_torch;
uniform float torch_range = 82.0;
uniform float glint_gain = 28.0;                    // sheeting is ~100x brighter than white paint toward the source
uniform float retro_lobe = 0.021;                     // observation angle of the sheeting, radians (~1.2 deg)
const float BASE_R = 0.034;
const float HALF_H = 0.07;

varying vec3 wp;
varying float cover;
varying float ax;
varying float capf;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;                       // collar centre; local Y runs along the line
	float d = length(c - CAMERA_POSITION_WORLD);
	float r = max(BASE_R, d * 0.0022);
	float hh = max(HALF_H, d * 0.0016);
	capf = step(0.5, abs(NORMAL.y));
	ax = VERTEX.y / HALF_H;                             // -1..1 along the band
	VERTEX.xz *= r / BASE_R;
	VERTEX.y *= hh / HALF_H;
	cover = mix((BASE_R / r) * (HALF_H / hh), (BASE_R / r) * (BASE_R / r), capf);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// three reflective stripes round the band (the caps are all tape), averaged before they alias
	float sv = ax * 1.5 + 1.5;
	float stripe = mix(step(0.5, fract(sv)), 0.5, smoothstep(0.25, 0.7, fwidth(sv)));
	stripe = mix(stripe, 1.0, capf);
	vec3 L = wp - g_torch_pos;
	float d = length(L);
	vec3 l = L / max(d, 0.001);
	float cone = smoothstep(0.82, 0.95, dot(l, g_torch_dir));
	float win = pow(max(1.0 - pow(d / torch_range, 4.0), 0.0), 2.0);
	vec3 V = normalize(CAMERA_POSITION_WORLD - wp);
	float obs = length(cross(-l, V));                   // ~ angle between the torch and the eye, seen from the tape
	float retro = exp(-pow(obs / retro_lobe, 2.0));
	float glint = g_torch * cone * win * retro * stripe * glint_gain * cover / (1.0 + 0.15 * d) * smoothstep(1.5, 3.0, d);
	glint = glint / (1.0 + 0.8 * glint);                // a spark, never a blown disc (<= 1.25)
	ALBEDO = vec3(0.30, 0.315, 0.32) * mix(0.6, 1.0, stripe) * max(cover, 0.05);
	ROUGHNESS = 0.55;
	SPECULAR = 0.3 * cover;
	EMISSION = vec3(0.85, 0.9, 0.95) * glint;
}
