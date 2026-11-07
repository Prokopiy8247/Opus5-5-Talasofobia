shader_type canvas_item;
// Soft dark vignette that deepens with depth (strength set from UI.gd).
uniform float strength = 0.3;

void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(uv);
	float v = smoothstep(0.28, 0.95, r);
	COLOR = vec4(0.0, 0.0, 0.0, v * v * strength * 1.6);
}
