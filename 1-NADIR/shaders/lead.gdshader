shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Cast-lead sinker and its shackle: dull, non-metallic, mottled grey, with patchy oxide bloom on some of the faces
// that look up (where silt and oxide settle), never a pale cap: from above it must read as a dark lump of lead,
// not a foam float. The shackle eye in the top boss is a dark hole. No metallic: with reflections disabled a
// metal reads black.

// Caustic net of the sunlit shallows (same texture and scrolls as sun_rays.gdshader; Rope.gd builds it).
uniform sampler2D caustic_tex : filter_linear_mipmap, repeat_enable;
uniform float caustic_k = 2.0;           // x albedo x sun-facing: moving bands of extra sun on the lead
global uniform float g_time;
global uniform float g_daylight;
const vec3 TO_SUN = vec3(0.3403, 0.9007, 0.2702);

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 opos;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float caustic_at(vec3 p) {
	vec2 q = p.xz - TO_SUN.xz * (p.y / TO_SUN.y);
	float dep = max(-p.y, 0.0);
	float lod = clamp(dep / 28.0, 0.0, 5.0);
	vec2 w = vec2(sin(q.y * 0.07 + g_time * 0.31), cos(q.x * 0.06 - g_time * 0.27)) * 1.6;
	float a = textureLod(caustic_tex, (q + w) / 64.0 + g_time * vec2(0.004, 0.0025), lod).r;
	float b = textureLod(caustic_tex, (q - w) / 41.0 - g_time * vec2(0.003, -0.004), lod).r;
	float c = pow(1.0 - a, 7.0) * pow(1.0 - b, 3.5);
	c = max(c - 0.04, 0.0) * (1.0 / 0.96) * mix(0.35, 1.0, smoothstep(0.0, 4.0, dep));
	return c * exp(-dep / 45.0);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	opos = VERTEX;
}

void fragment() {
	// Weathered lead is a dark dull grey; the sunlit shallows (sun + strong teal ambient at 12-17 m) would turn a
	// paler albedo into a white plaster block or a foam float: from above the top stays near the water's own level.
	float n = vnoise(wpos * 6.0) * 0.7 + vnoise(wpos * 23.0) * 0.3;
	vec3 alb = vec3(0.05, 0.056, 0.06) * (0.7 + 0.6 * n);           // blue-grey lead, mottled
	float oxide = smoothstep(0.5, 0.9, normalize(wnrm).y) * smoothstep(0.45, 0.75, vnoise(wpos * 9.0)) * 0.6;
	alb = mix(alb, vec3(0.085, 0.09, 0.088), clamp(oxide, 0.0, 1.0));
	// the cast eye round the shackle boss (object space: the sinker's top is at y ~0.28)
	alb *= mix(1.0, mix(0.45, 1.0, smoothstep(0.04, 0.10, length(opos.xz))), smoothstep(0.18, 0.22, opos.y));
	ALBEDO = alb;
	EMISSION = alb * vec3(0.55, 0.85, 0.80) * caustic_at(wpos) * max(dot(normalize(wnrm), TO_SUN), 0.0) * g_daylight
		* caustic_k;
	METALLIC = 0.0;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
}
