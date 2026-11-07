// NADIR - rusticles: brittle rust icicles hanging world-down from the wreck (mesh: y 0 at the anchor, -1 at the
// tip, scaled per instance). Knobbly growth rings, vertical striations, wet dark tips, thin parts glow orange
// when the beam is behind them. Writes the same presence FOG as hull.gdshader.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float gain = 2.0;   // the hull is gained x4.6: rusticles must read as rust beside it, not soot
// presence and water light (ShipMesh.update_env, every frame)
uniform float fog_density = 0.0175;
uniform vec4 fog_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float presence = 1.0;
uniform float wl_on = 0.0;
global uniform float g_depth;
// path-length colour absorption (torch -> surface -> eye), same law as hull.gdshader
global uniform vec3 g_torch_pos;
global uniform float g_torch;

varying vec3 lp;
varying float seed;

float hash11(float x) {
	return fract(sin(x * 127.1 + 311.7) * 43758.5453);
}

// WATER LIGHT CONTRACT
float wl_grad(float depth) {
	return 1.0 - smoothstep(150.0, 330.0, depth);
}
vec3 wl_ratio(vec3 d, float depth) {
	float dn = smoothstep(0.0, 0.95, -d.y);
	dn = dn * dn * (3.0 - 2.0 * dn);
	vec3 r = mix(vec3(1.0), vec3(0.30, 0.36, 0.48), dn) * (1.0 + 0.35 * smoothstep(0.0, 0.66, d.y));
	return mix(vec3(1.0), r, wl_grad(depth));
}

// water eats the red first (hull.gdshader): 52 m path = the wall at 26 m stays as is; FOG is untouched
vec3 absorb(vec3 vtx, mat4 inv_view) {
	vec3 wp = (inv_view * vec4(vtx, 1.0)).xyz;
	float path = length(vtx) + length(wp - g_torch_pos);
	vec3 ab = clamp(exp(-vec3(0.020, 0.008, 0.005) * (path - 52.0)), vec3(0.0), vec3(1.25));
	return mix(vec3(1.0), ab, clamp(g_torch, 0.0, 1.0));
}

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz - NODE_POSITION_WORLD;   // anchor in the beat's design space (stable)
	seed = fract(sin(dot(floor(o * 4.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float band = floor(-VERTEX.y * 7.0);                   // knobbly growth rings
	VERTEX.xz *= 0.75 + 0.5 * hash11(band + seed * 17.0);
	lp = VERTEX;
}

void fragment() {
	float t = clamp(-lp.y, 0.0, 1.0);                      // 0 at the anchor, 1 at the tip
	float ang = atan(lp.z, lp.x);
	float stri = 0.5 + 0.5 * sin(ang * 6.0 + seed * 20.0 + t * 2.0);
	// rust brown-orange (redder and less yellow than raw orange, so it sits with the hull's rust streaks)
	vec3 col = mix(vec3(0.26, 0.10, 0.058), vec3(0.46, 0.19, 0.105), clamp(stri * 0.6 + seed * 0.4, 0.0, 1.0));
	col *= mix(1.0, 0.75, smoothstep(0.65, 1.0, t));       // wet, darker tips
	col *= 0.85 + 0.3 * hash11(floor(t * 7.0) + seed * 9.0);
	ALBEDO = col * gain * absorb(VERTEX, INV_VIEW_MATRIX);
	ROUGHNESS = mix(0.85, 0.55, smoothstep(0.45, 1.0, t));
	SPECULAR = 0.2;
	METALLIC = 0.0;
	BACKLIGHT = vec3(0.25, 0.10, 0.035);                   // thin tips glow when the beam is behind them

	vec3 dw = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
	float fa = 1.0 - exp(-fog_density * length(VERTEX));
	vec3 wr = mix(vec3(1.0), wl_ratio(dw, g_depth), wl_on);
	FOG = vec4(fog_col.rgb * wr / mix(vec3(1.0), wr, fa), max(fa, 1.0 - presence));
}
