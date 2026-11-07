shader_type spatial;
// The strobe's light scattered in the water around the marker float: a wide, soft glow that blooms with each flash
// and is gone between them. A camera-facing quad placed a little behind the lamp (away from the viewer), depth-tested,
// so the float itself stands dark against its own glow; additive, unfogged (it is the water's own light). Its profile
// is a hot core, an exponential scatter glow and a faint wide veil, all under a smooth polynomial window that reaches
// zero at the quad's inscribed circle with zero slope (the deep water behind is so dark that any cut-off tail would
// show as a ring). `flash` (0..~1) is driven every frame from the lamp's flash (Beat06_DeepBlue).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform float flash = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.8, 0.56);
uniform float peak = 2.4;          // HDR brightness at the centre at full flash
uniform float core_r = 0.12;       // m: radius of the hot core (Gaussian)
uniform float glow_r = 0.3;        // m: e-folding length of the scatter glow
uniform float veil_r = 0.9;        // m: radius of the faint veil (Gaussian)
uniform vec3 mixw = vec3(0.55, 0.33, 0.12);   // shares of core, glow and veil at the centre
uniform float push = 0.45;         // m: the quad sits this far behind the lamp, away from the camera
uniform float half_size = 2.5;     // m: half the quad size (the mesh is 2 * half_size wide)

varying vec2 v_q;

void vertex() {
	// lamp centre in view space, pushed away from the camera; the quad lies in the view plane around it
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = length(c);
	c += c * (push / max(d, 1e-3));
	v_q = VERTEX.xy;
	POSITION = PROJECTION_MATRIX * vec4(c + vec3(VERTEX.xy, 0.0), 1.0);
}

void fragment() {
	float r = length(v_q);
	float g = mixw.x * exp(-(r * r) / (core_r * core_r)) + mixw.y * exp(-r / glow_r)
		+ mixw.z * exp(-(r * r) / (veil_r * veil_r));
	float u = clamp(r / (0.96 * half_size), 0.0, 1.0);
	float win = 1.0 - u * u;
	g *= win * win * win;
	ALBEDO = tint * (peak * clamp(flash, 0.0, 4.0) * g);
	ALPHA = 1.0;
}
