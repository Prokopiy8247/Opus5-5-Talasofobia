shader_type canvas_item;
// Full-screen finish on top of the 3D image (first child of the UI layer, under the fades and text):
// per-beat colour grade (lift / gain / gamma / contrast / saturation with warm lights protected / tint),
// a dive mask's soft edges (slight blur and colour fringing toward the corners), a smooth superellipse
// vignette and fine film grain tuned for video compression (2 px cells, 24 Hz, none in the blacks).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float aberration = 0.0025;      // colour fringing at the corners (fraction of the screen)
uniform float edge_blur = 0.5;          // mip level reached in the corners (more reads as a tilt-shift miniature)
uniform float grain = 0.014;
uniform float black_floor = 0.012;      // the darkest value (no clipped flat black: water, and video encoders band it)
uniform float vignette = 0.5;
uniform float strength = 1.0;           // 0 disables the lens effects (grade stays)
// grade (Main sets these from Config.GRADE by the diver's position)
uniform vec3 g_tint = vec3(1.0);
uniform float g_lift = 0.0;
uniform float g_gain = 1.0;
uniform float g_gamma = 1.0;
uniform float g_contrast = 1.0;
uniform float g_sat = 1.0;
uniform float g_wobble = 0.0;           // fog-band crossing: a faint refraction wobble

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	uv += g_wobble * 0.0025 * vec2(sin(uv.y * 40.0 + TIME * 1.3), cos(uv.x * 32.0 - TIME * 1.1));
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 c = uv - 0.5;
	c.x *= aspect;
	float r2 = dot(c, c);
	float edge = smoothstep(0.30, 0.80, r2) * strength;
	float lod = edge * edge_blur;
	vec2 dir = (uv - 0.5) * aberration * edge;
	vec3 col;
	col.r = textureLod(screen_tex, uv + dir, lod).r;
	col.g = textureLod(screen_tex, uv, lod).g;
	col.b = textureLod(screen_tex, uv - dir, lod).b;
	// grade
	col = max(col * g_gain + g_lift * (1.0 - col), vec3(0.0));
	col = pow(col, vec3(1.0 / g_gamma));
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	float warm = smoothstep(0.04, 0.18, col.r - col.b);      // amber lamps and portholes keep their colour
	col = mix(vec3(luma), col, mix(g_sat, 1.0, warm));
	col = max((col - 0.22) * g_contrast + 0.22, vec3(0.0));
	col *= g_tint;
	// superellipse vignette (no visible ring in flat fog)
	vec2 q = (uv - 0.5) * 2.0;
	float d = pow(pow(abs(q.x), 4.0) + pow(abs(q.y), 4.0), 0.25);
	float v = smoothstep(0.5, 1.3, d);
	col *= 1.0 - vignette * v * v * strength;
	// grain: 2 px cells, refreshed at 24 Hz, strongest in the mid-darks, none in true black
	vec2 cell = floor(FRAGCOORD.xy * 0.5);
	float tq = floor(TIME * 24.0);
	float n = hash(cell + fract(tq * 0.618) * 917.0) + hash(cell * 1.37 + fract(tq * 0.381) * 311.0) - 1.0;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	// a soft toe: nothing below the floor, so the deep stays water (moving grain, no flat card)
	col = col + black_floor * (1.0 - smoothstep(0.0, 0.08, col));
	col += n * grain * strength * (0.35 + 0.65 * smoothstep(0.015, 0.09, lum)) * (1.0 - 0.6 * smoothstep(0.3, 0.8, lum));
	COLOR = vec4(col, 1.0);
}
