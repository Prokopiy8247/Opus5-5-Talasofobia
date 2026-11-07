shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// The warm pool each floor lamp casts on the silt from 0.9 m above: a quad laid on the local slope (6-9 m,
// scaled by the lamp's brightness), additive, depth-tested (dunes hide some), with the same reveal and distance
// attenuation as the lamp points. A hot spot under the lamp with an inverse-square tail (not a flat disc),
// modulated by the silt's own mottling, so it reads as lit sediment rather than a decal.
// The hatch beacon (w = 1) has its pool always on and seen from above through the murk instead: water-
// attenuated, so it emerges slowly under the beacon point during the approach, and it hands over to the lamp's
// real light on the silt (which only shows inside the torch range) over the last ~60 m.
// INSTANCE_CUSTOM: x = reveal delay (s), y = brightness, w = kind (1 = the hatch beacon).
uniform vec4 lamp_col : source_color = vec4(1.0, 0.706, 0.353, 1.0);
uniform float reveal_time = -1.0;
uniform float gain = 0.25;
uniform float beacon_ext = 0.010;   // the beacon pool's extinction with distance (1/m)
global uniform vec3 g_cam_pos;

varying float v_on;
varying vec3 wpos;

float hashi(vec2 p, uint s) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(32768));
	uint h = (q.x * 1597334677u) ^ (q.y * 3812015801u) ^ (s * 2654435761u);
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	return float(h >> 8u) * (1.0 / 16777216.0);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hashi(i, 0u), hashi(i + vec2(1.0, 0.0), 0u), f.x),
		mix(hashi(i + vec2(0.0, 1.0), 0u), hashi(i + vec2(1.0, 1.0), 0u), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(MODEL_MATRIX[3].xyz - g_cam_pos);
	v_on = smoothstep(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.x + 1.4, reveal_time) * exp(-d * 0.0011) * INSTANCE_CUSTOM.y;
	if (INSTANCE_CUSTOM.w > 0.75) {
		v_on = exp(-d * beacon_ext) * smoothstep(22.0, 70.0, d) * INSTANCE_CUSTOM.y;
	}
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float fall = max(1.0 / (1.0 + r * r * 14.0) - 0.067, 0.0) * (1.0 - smoothstep(0.8, 1.0, r));
	// octaves fade to their mean once a cell gets smaller than ~2 px (far pools would sparkle)
	float fw = length(fwidth(wpos.xz));
	float n1 = mix(vnoise(wpos.xz * 1.6), 0.5, smoothstep(0.15, 0.5, fw * 1.6));
	float n2 = mix(vnoise(wpos.xz * 0.3 + 7.3), 0.5, smoothstep(0.15, 0.5, fw * 0.3));
	float silt = mix(0.55, 1.15, n1 * 0.5 + n2 * 0.5);
	ALBEDO = lamp_col.rgb * (fall * silt * gain * 1.6 * v_on);
}
