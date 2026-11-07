shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Soft additive halo around a lamp. Use on a QuadMesh; the quad is billboarded in the vertex shader.
// inscatter = 1 (lamps right in front of a surface, e.g. the door lamp): the halo is the lamp's light scattered
// by the water in front of whatever lies behind it. The quad is pulled toward the camera (same size on screen)
// so the depth test never cuts it where a camera-facing quad would pass through the wall, and the scene depth
// is compared with the lamp's own depth instead of the quad's (the share of the scattering path that lies in
// front of the surface, closed form): the halo falls off evenly round the lamp, with no hard line across it.
#include "res://shaders/inc/uw.gdshaderinc"

uniform vec3 glow_color : source_color = vec3(1.0, 0.7, 0.35);
uniform float energy = 1.0;
uniform float falloff = 3.0;
uniform float uw_reveal_channel = -1.0;   // 0..3 multiplies by uw_reveal[channel], -1 = always on
uniform float soft_dist = 2.5;            // fade where the quad meets geometry (no hard intersection lines)
uniform float inscatter = 0.0;            // 1 = depth-correct halo in front of a surface (see above)
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 center;
varying float c_depth;    // view depth of the halo's centre
varying float q_half;     // half the quad's size in metres

void vertex() {
	center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	c_depth = -(VIEW_MATRIX * vec4(center, 1.0)).z;
	q_half = abs(VERTEX.x) * length(MODEL_MATRIX[0].xyz);
	// scaling the view-space position toward the eye keeps the quad's projection and moves only its depth
	vec3 vp = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = 1.0;
	if (inscatter > 0.5 && c_depth > 0.2) {
		k = max(c_depth - q_half - 0.5, 0.15) / c_depth;
	}
	POSITION = PROJECTION_MATRIX * vec4(vp * k, 1.0);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = pow(max(1.0 - r, 0.0), falloff);
	vec4 f = uw_fog_eval(CAMERA_POSITION_WORLD, center);
	float ch = 1.0;
	if (uw_reveal_channel >= 0.0) {
		int c = int(uw_reveal_channel);
		ch = c == 0 ? uw_reveal.x : (c == 1 ? uw_reveal.y : (c == 2 ? uw_reveal.z : uw_reveal.w));
	}
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -vp.z / vp.w;
	float soft;
	if (inscatter > 0.5) {
		// 1/(h^2 + t^2) along the ray, integrated up to the surface, over the whole ray
		soft = 0.5 + atan((scene_z - c_depth) / max(r * q_half, 0.05)) / PI;
	} else {
		soft = clamp((scene_z + VERTEX.z) / soft_dist, 0.0, 1.0);
	}
	ALBEDO = glow_color * energy * a * (1.0 - f.a) * ch * soft;
}
