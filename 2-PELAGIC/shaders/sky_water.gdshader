shader_type sky;
// The infinite water around the diver (all of it lives in water_backdrop.gdshaderinc, shared with object fog).
#include "res://shaders/water_backdrop.gdshaderinc"

uniform float cam_depth = 0.0;
uniform vec3 sun_w = vec3(0.21, 0.93, 0.30);   // refracted sun direction (towards the light)
uniform float shaft_amount = 1.0;

void sky() {
	COLOR = wb_sky(EYEDIR, cam_depth, shaft_amount, sun_w, TIME, AT_CUBEMAP_PASS ? 0.25 : 1.0);
}
