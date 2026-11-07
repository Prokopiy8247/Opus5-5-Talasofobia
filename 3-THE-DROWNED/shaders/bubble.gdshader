shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// Exhaled air bubbles near the mask: camera-facing discs with a thin bright rim, a dark band inside it,
// a highlight at the top left and a see-through, slightly refracting middle. Bubbles close to the lens
// are out of focus (soft edge, blurred, fainter). Big ones flatten into wobbling caps.
// INSTANCE_CUSTOM: x = seed, y = alpha, z = squash.
#include "res://shaders/inc/uw.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying float alpha;
varying float depthy;
varying float sq;
varying float dof;

void vertex() {
	vec3 c = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float r = length(MODEL_MATRIX[0].xyz);
	sq = INSTANCE_CUSTOM.z;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 w = c + right * VERTEX.x * 2.0 * r * (1.0 + sq * 0.3) + up * VERTEX.y * 2.0 * r;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(w, 1.0));
	alpha = INSTANCE_CUSTOM.y;
	depthy = c.y;
	dof = clamp(1.0 - length(c - CAMERA_POSITION_WORLD) / 0.7, 0.0, 1.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;                  // +y is down on screen
	if (p.y > 0.0) {
		p.y *= 1.0 + 0.9 * sq;                   // flat bottom on the big ones
	}
	float d = length(p);
	float soft = fwidth(d) * 1.5 + 0.35 * dof;
	float disc = 1.0 - smoothstep(1.0 - soft, 1.0, d);
	if (disc <= 0.001) {
		discard;
	}
	float lod = 1.0 + 2.0 * dof;
	vec2 off = -p * 0.06 * (1.0 - d * d) * (1.0 - dof);
	vec3 bg = textureLod(screen_tex, SCREEN_UV + off, lod).rgb;
	float rim = smoothstep(0.84 - 0.3 * dof, 0.99, d);
	float band = smoothstep(0.66, 0.82, d) * (1.0 - smoothstep(0.82, 0.93, d));
	float hl = 1.0 - smoothstep(0.0, 0.26 + 0.2 * dof, length((p - vec2(-0.38, -0.4)) * vec2(1.0, 1.35)));
	hl *= 1.0 - 0.7 * dof;
	float l = uw_light(depthy);
	vec3 rim_col = mix(uw_water_col(depthy) * 2.2 + vec3(0.05), vec3(0.85, 0.95, 0.95) * (0.5 + 0.5 * l), 0.6);
	vec3 col = bg * (1.0 - 0.35 * band) + rim_col * rim * 0.8 + vec3(1.0) * hl * (0.3 + 0.6 * l);
	ALBEDO = col;
	ALPHA = disc * alpha * clamp(0.55 + rim * 0.45 + hl, 0.0, 1.0) * (1.0 - 0.45 * dof);
}
