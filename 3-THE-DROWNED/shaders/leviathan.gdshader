shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
// The shape behind the forest: a dark, unlit body that only reads as a moving occlusion of the fog
// bands. A slow lateral swimming wave runs from head (z = 0) to tail (z = body_len).
#include "res://shaders/inc/uw.gdshaderinc"

uniform float body_len = 170.0;

varying vec3 wpos;

void vertex() {
	float z = VERTEX.z / body_len;
	VERTEX.x += 7.0 * sin(z * 5.5 - uw_time * 0.55) * smoothstep(0.05, 0.6, z);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = pal_deep * 0.25;
	ROUGHNESS = 1.0;
	EMISSION = vec3(0.0);
	FOG = uw_fog_eval(CAMERA_POSITION_WORLD, wpos);
}
