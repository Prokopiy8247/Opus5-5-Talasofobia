shader_type canvas_item;
render_mode blend_add;
// Very fine additive grain: breaks banding in the dark gradients without being visible as noise.
global uniform float g_time;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 p = floor(FRAGCOORD.xy) + vec2(fract(g_time * 7.31) * 113.0, fract(g_time * 3.17) * 71.0);
	float n = h(p) + h(p + 17.13) - 1.0;
	COLOR = vec4(vec3(max(n, 0.0) * 0.010), 1.0);
}
