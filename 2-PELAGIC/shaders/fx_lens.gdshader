shader_type canvas_item;
// Dive-mask / lens finish, drawn below the UI layer: a soft darkening only at the far edges of the mask window,
// faint lateral chromatic aberration at the extreme edges, and fine animated grain that also dithers away the
// banding of the deep blue gradients. The centre of the frame is untouched.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float vignette = 0.3;       // darkening at the very corners (0..1)
uniform float aberration = 0.001;   // red/blue split at the corners (uv units); small enough that snow specks
                                    // do not split into RGB triplets
uniform float grain = 0.012;        // grain amplitude (display units)

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float asp = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	// mask window: a rounded rectangle (super-ellipse); 1 at the edge midpoints, ~1.19 in the corners
	// (powers by multiplication and a double sqrt of a non-negative sum: no pow() of zero, never NaN)
	vec2 ex = abs(d) * 2.0 * vec2(1.0, mix(1.0, 0.92, step(1.0, asp)));
	ex *= ex;
	float e = sqrt(sqrt(dot(ex, ex)));
	float ca = aberration * smoothstep(0.55, 1.2, e);
	vec2 o = d * ca / max(length(d), 1e-4);
	vec3 col;
	col.r = texture(screen_tex, uv + o).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - o).b;
	col *= 1.0 - vignette * smoothstep(0.72, 1.22, e);
	// triangular grain, re-seeded every frame, a little stronger in the darks where banding shows
	vec2 px = floor(FRAGCOORD.xy);
	float f = floor(fract(TIME * 0.5) * 240.0);
	float n = h12(px + f * vec2(17.0, 59.0)) + h12(px * 1.37 + f * vec2(83.0, 7.0) + 11.0) - 1.0;
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col += n * grain * mix(1.0, 0.5, l);
	COLOR = vec4(col, 1.0);
}
