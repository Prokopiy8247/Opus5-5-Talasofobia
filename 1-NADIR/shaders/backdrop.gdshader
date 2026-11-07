shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
// Backdrop sphere around the camera: exactly the palette water colour of the current depth (fully fogged
// geometry converges to the same colour, and the surface plane fades to it at the horizon).
uniform vec4 water_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	ALBEDO = water_col.rgb;
	FOG = vec4(0.0);
}
