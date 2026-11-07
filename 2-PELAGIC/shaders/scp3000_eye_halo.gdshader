shader_type spatial;
// The glow of SCP-3000's eye in the water around it: a camera-facing additive disc that SCP3000.gd places a little
// in front of each eyeball, towards the camera. Light from the iris scatters in the water between the eye and the
// diver, so a light seen through ~90 m of water glows into the water around it instead of ending at its rim like a
// sticker. Exponential falloff in units of the iris radius; soft where the disc meets the skin (depth fade, no
// intersection line); no fog of its own (the script scales it by the water's transmittance to the eye).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 color : source_color = vec4(0.31, 0.94, 0.88, 1.0);
uniform float intensity = 0.0;            // linear radiance at the centre (already scaled by the water to the eye)
uniform float radius = 14.0;              // world m: half-size of the disc
uniform float iris_r = 3.5;               // world m: the falloff is in units of the iris radius
uniform float fade_m = 5.0;               // world m: depth fade where the disc meets the skin

void vertex() {
	// billboard: the node's origin in view space, the quad spread in the view plane
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX = c + vec3((UV - 0.5) * 2.0 * radius, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float r = length((UV - 0.5) * 2.0);                    // 0 centre, 1 edge of the disc
	float rho = r * radius / max(iris_r, 1e-3);            // in iris radii
	// hollow inside the iris: the glow starts at the iris edge, so the pupil stays dark (a halo over it made the eye a
	// glowing 'O')
	float halo = (exp(-1.15 * rho) + 0.18 * exp(-0.45 * rho)) * (1.0 - smoothstep(0.6, 1.0, r)) * smoothstep(0.7, 1.15, rho);
	float zb = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zb, 1.0);
	float scene_z = -sv.z / max(sv.w, 1e-6);
	float soft = clamp((scene_z + VERTEX.z) / max(fade_m, 1e-3), 0.0, 1.0);
	ALBEDO = color.rgb * max(intensity, 0.0) * halo * soft;
}
