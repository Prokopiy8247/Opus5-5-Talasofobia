shader_type spatial;
// Thin dark viscous seep drifting in the water: slow sway, twisting strips (built in Beat05_Coils.gd) that vanish
// edge-on and break up into wisps along and across their length, soft edges, a faint wet sheen.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://shaders/water_common.gdshaderinc"

uniform vec4 color : source_color = vec4(0.184, 0.227, 0.239, 1.0);
uniform float reveal = 1.0;               // follows the creature's head visibility (SCP3000.gd)
instance uniform float phase = 0.0;
varying vec3 v_w;

void vertex() {
	float t = UV.y;
	VERTEX.x += sin(TIME * 0.11 + phase + t * 6.0) * t * 1.2;
	VERTEX.z += cos(TIME * 0.09 + phase * 1.3 + t * 5.0) * t * 1.0;
	VERTEX.y += sin(TIME * 0.07 + phase + t * 3.0) * t * 0.5;
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	// a soft veil: Gaussian across the strip, no edge line
	float edge = exp(-across * across * 3.5) * (1.0 - smoothstep(0.8, 1.0, across));
	float a = edge * smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	// wisps: soft erosion into blobs along the length, slowly flowing down the seep. Coarse across the strip (at most
	// ~1.5 cells over its width): finer noise across splits a wide strip into thin parallel streaks
	float n1 = water_noise(vec2(UV.y * 7.0 - TIME * 0.03 + phase * 3.1, UV.x * 1.2 + phase));
	float n2 = water_noise(vec2(UV.y * 19.0 - TIME * 0.05 + phase * 7.3, UV.x * 1.6 - phase));
	a *= smoothstep(0.22, 0.75, n1 * 0.7 + n2 * 0.3 + 0.1 * (1.0 - UV.y));
	// a flat strip seen edge-on would be a hard dark line: let it vanish well before that
	vec3 n = NORMAL * inversesqrt(max(dot(NORMAL, NORMAL), 1e-12));
	float facing = abs(dot(n, VIEW));
	a *= smoothstep(0.2, 0.6, facing);
	// and wherever the strip covers only a few pixels across (edge-on or far away) it would read as a drawn line,
	// not as fluid: projected width in pixels from the screen derivative of the across coordinate
	float px_across = 1.0 / max(fwidth(UV.x), 1e-4);
	a *= smoothstep(4.0, 11.0, px_across);
	ALBEDO = color.rgb * 0.6 * water_rel_light(v_w.y);
	ROUGHNESS = 0.35;
	SPECULAR = 0.25 * water_spec_dim(v_w.y);
	// a thin veil of fluid, never an opaque band
	ALPHA = clamp(a * 1.6, 0.0, 0.45) * reveal;
	FOG = water_fog(v_w);
}
