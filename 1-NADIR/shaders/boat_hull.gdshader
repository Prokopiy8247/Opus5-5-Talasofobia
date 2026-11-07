shader_type spatial;
render_mode cull_back, depth_draw_always, diffuse_burley, specular_schlick_ggx;
// The small boat seen from below: a dark painted hull with a thin bright rippling meniscus where it pierces the
// surface, and the sun-ray caustic net playing over the sides that face the sun. Its own fog goes to the
// water-light colour of its direction (what the surface shows around it), and it dissolves with depth (`fade`),
// so it never pops out as a speck in the window.
uniform vec4 albedo : source_color = vec4(0.08, 0.085, 0.09, 1.0);
uniform float roughness = 0.75;
uniform float fade = 1.0;            // 1 = solid, 0 = gone (set per frame by depth)
uniform float scene_fog = 0.0085;    // = env.fog_density, set per frame
uniform vec4 water_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);   // set per frame, same as the surface
// the sun-ray caustic net (Beat01 passes the same cellular texture the ray pass uses)
uniform sampler2D caustic_tex : filter_linear_mipmap, repeat_enable;
uniform float caustic_gain = 0.0;   // 0 until the texture is set
global uniform float g_time;
global uniform float g_daylight;
global uniform float g_depth;

const vec3 TO_SUN = vec3(0.3403, 0.9007, 0.2702);   // = -WaterEnv.SUN_DIR

varying vec3 wpos;

// WATER LIGHT CONTRACT (identical in surface.gdshader and the shared pass).
float wl_grad(float depth) { return 1.0 - smoothstep(150.0, 330.0, depth); }
vec3 wl_ratio(vec3 d, float depth) {
	float dn = smoothstep(0.0, 0.95, -d.y);
	dn = dn * dn * (3.0 - 2.0 * dn);
	vec3 r = mix(vec3(1.0), vec3(0.30, 0.36, 0.48), dn) * (1.0 + 0.35 * smoothstep(0.0, 0.66, d.y));
	return mix(vec3(1.0), r, wl_grad(depth));
}

// The caustic net at world point p: identical to rays_at() in sun_rays.gdshader (without the boat shadow).
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
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	// meniscus: a thin rippling band of light at the waterline (kept under the glow threshold)
	float wl = 1.0 - smoothstep(0.0, 0.11, abs(wpos.y + 0.02 + 0.03 * sin(wpos.x * 4.0 + g_time * 2.5)));
	vec3 nw = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// the ray net on the hull: full on the sides facing the sun, a faint flicker on the shaded bottom
	float cs = caustic_at(wpos) * (max(dot(nw, TO_SUN), 0.0) + 0.1) * caustic_gain;
	EMISSION = (vec3(0.7, 0.9, 0.95) * wl * 0.85 + vec3(0.55, 0.85, 0.80) * cs * albedo.rgb * 6.0) * g_daylight;
	vec3 to_frag = wpos - CAMERA_POSITION_WORLD;
	float dist = length(to_frag);
	FOG = vec4(water_col.rgb * wl_ratio(to_frag / max(dist, 0.001), g_depth), 1.0 - exp(-dist * scene_fog));
	ALPHA = fade;
}
