shader_type spatial;
// Soft rope: twisted strands, gentle sway, depth tint. Matte (no specular at all), and its shading normals always
// face the viewer: a sun-lit rim a fraction of a pixel wide (the diver looks into the light) sparkles along the line
// as MSAA catches it now and then. Coverage-aware width: a rope thinner than ~1.5 px is drawn 1.5 px wide (so it never breaks into crawling
// dashes) and melts towards the water behind it by the share of the pixel it really covers, through the fog term
// (no transparency needed); such a rope is shaded as the average of its width (normals bent towards the viewer,
// strands faded to their mean), so nothing a fraction of a pixel wide can flicker. Optionally the rope fades out
// along its length above fade_from (the float line rising into the dark), the way a thin line is lost in real water
// within a few tens of metres.
render_mode cull_back, shadows_disabled, diffuse_lambert, specular_disabled;
#include "res://shaders/water_common.gdshaderinc"

uniform vec4 color : source_color = vec4(0.82, 0.78, 0.66, 1.0);
uniform float sway = 0.25;
uniform float radius = 0.028;       // the tube radius the mesh was built with (m)
uniform float min_px = 1.5;         // minimum drawn width in pixels
uniform float fade_from = 1e9;      // world height where the along-length fade starts
uniform float fade_len = 0.0;       // metres over which the rope fades out above fade_from (0 = off)
varying vec3 v_w;
varying float v_cov;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = clamp(UV.y, 0.0, 1.0);
	vec3 sw = vec3(sin(TIME * 0.5 + w.y * 0.15) * sway * k * (1.0 - k) * 4.0, 0.0,
		cos(TIME * 0.37 + w.y * 0.11) * sway * k * (1.0 - k) * 2.0);
	vec3 centre = VERTEX - NORMAL * radius + sw;
	float depth = max(-(MODELVIEW_MATRIX * vec4(centre, 1.0)).z, 0.01);
	float px = 2.0 * depth / max(abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y, 1.0);   // y scale is negative here
	float r = max(radius, 0.5 * min_px * px);
	v_cov = radius / r;
	VERTEX = centre + NORMAL * r;
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// three twisted strands; where one strand period spans less than ~3 pixels they fade to their mean
	float ph = UV.x * 3.0 + (v_w.x + v_w.y + v_w.z) * 4.0;
	float strand = 0.82 + 0.18 * sin(ph * 6.2831853) * (1.0 - smoothstep(0.2, 0.5, fwidth(ph)));
	ALBEDO = color.rgb * strand * water_rel_light(v_w.y);
	ROUGHNESS = 0.85;
	SPECULAR = 0.0;
	// the silhouette: MSAA shades an edge pixel once, at its centre, which can lie just outside the rope, so the
	// interpolated normal there is extrapolated past the rim and faces away from the camera. With the sun ahead (the
	// diver looks into the light) such a normal faces the sun and catches full sunlight and sky light: a row of single
	// bright pixels along one edge of the line. Keep every shading normal turned towards the viewer, and let the
	// outermost rim (and anything extrapolated past it) melt into the water through the fog term, so the edge of a
	// rope a few pixels wide is soft instead of a line of single lit samples (a thin rope's rim reads like that in
	// real water too). A sub-pixel rope already melts by its coverage, so it keeps its full width here.
	float nv0 = dot(NORMAL, VIEW);
	float rim = mix(1.0, smoothstep(-0.05, 0.4, nv0), clamp(v_cov, 0.0, 1.0));
	NORMAL = normalize(NORMAL + VIEW * max(0.35 - nv0, 0.0));
	// an inflated (sub-pixel) rope: its lit and its shaded rim are less than a pixel apart, so shade the average
	float infl = 1.0 - clamp(v_cov, 0.0, 1.0);
	NORMAL = normalize(mix(NORMAL, normalize(NORMAL + VIEW), infl));
	vec4 f = water_fog(v_w);
	float keep = (1.0 - f.a) * clamp(v_cov, 0.0, 1.0) * rim;
	if (fade_len > 0.0) {
		keep *= 1.0 - smoothstep(0.0, fade_len, v_w.y - fade_from);
	}
	FOG = vec4(f.rgb, 1.0 - keep);
}
