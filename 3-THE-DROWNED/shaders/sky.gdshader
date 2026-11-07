shader_type sky;
// The far backdrop: the same fog integral as every material, taken to a great distance.
#include "res://shaders/inc/uw.gdshaderinc"

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = uw_water_col(uw_cam_pos.y);
	} else {
		vec4 f = uw_fog_eval(uw_cam_pos, uw_cam_pos + EYEDIR * 7000.0);
		COLOR = f.rgb;
	}
}
