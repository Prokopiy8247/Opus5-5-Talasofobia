shader_type spatial;
// Suspended particles / marine snow wrapped in a box around the camera (no simulation, no popping).
// Each speck keeps its real light (energy ~ size^2) but is never drawn smaller than ~2 px, so nothing crawls or
// twinkles; it glows looking towards the light (forward scatter) and nearly vanishes looking down; flakes close to
// the mask are out of focus (larger, softer, dimmer per pixel) and fade out before they could flash.
// A thicker particulate layer at about 200-260 m is a landmark the diver sinks through.
// The marker float's strobe (lamp_pos / lamp_flash, set by WaterWorld from the float's OmniLight) lights the specks
// around it on each flash: warm-white backscatter, brightest in front of the lamp (forward scatter to the eye).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;
#include "res://shaders/water_common.gdshaderinc"

uniform float box = 36.0;
uniform float amount = 1.0;
uniform vec4 color : source_color = vec4(0.75, 0.9, 1.0, 1.0);
uniform float min_px = 2.0;          // smallest drawn size in pixels
uniform float focus = 2.5;           // metres: closer than this the lens blurs the flakes
uniform float band_top = 195.0;      // the particulate layer (depth range, m)
uniform float band_bottom = 265.0;
uniform vec3 lamp_pos = vec3(0.0, -100000.0, 0.0);
uniform float lamp_flash = 0.0;      // 0..1 strobe pulse (0 between flashes and before the float is near)
uniform vec4 lamp_color : source_color = vec4(1.0, 0.82, 0.55, 1.0);
uniform float lamp_gain = 3.0;
uniform float lamp_reach = 5.0;      // metres: specks further from the lamp stay dark

varying vec3 v_light;    // colour and brightness after energy conservation, phase and fades
varying float v_soft;    // 0 = small crisp speck, 1 = soft defocused disc
varying vec3 v_lamp;     // the strobe's light on this speck

void vertex() {
	float ph = INSTANCE_CUSTOM.w;
	vec3 base = INSTANCE_CUSTOM.xyz * box;
	vec3 drift = vec3(sin(TIME * 0.11 + ph * 6.0) * 0.7, -TIME * (0.03 + ph * 0.05), cos(TIME * 0.09 + ph * 4.0) * 0.7);
	vec3 rel = mod(base + drift - water_cam_pos, vec3(box)) - box * 0.5;
	vec3 w = water_cam_pos + rel;
	vec4 vp = VIEW_MATRIX * vec4(w, 1.0);
	float dist = max(-vp.z, 0.05);
	// a few larger flakes among the specks
	bool flake = fract(ph * 13.7) > 0.93;
	float size = mix(0.010, 0.030, fract(ph * 7.31)) * (flake ? 2.4 : 1.0);
	// out of focus near the mask: the disc grows, its light spreads
	float coc = 0.03 * max(focus / dist - 1.0, 0.0);
	float s_true = size + coc;
	// metres per pixel at this distance (the y scale is negative in this pipeline, hence abs)
	float px = 2.0 * dist / max(abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y, 1.0);
	float s_draw = max(s_true, min_px * px);
	float e = (size / s_draw) * (size / s_draw);                           // energy conservation
	// the layer: some specks exist only inside the band, the rest everywhere
	float dp = max(-w.y, 0.0);
	float band = smoothstep(band_top - 15.0, band_top + 15.0, dp) * (1.0 - smoothstep(band_bottom - 15.0, band_bottom + 15.0, dp));
	float exists = fract(ph * 29.17) < 0.7 ? 1.0 : band;
	// forward scatter: bright towards the sun, dim looking down
	vec3 vdir = rel / max(length(rel), 1e-3);
	float phase = mix(0.3, 1.7, pow(max(dot(vdir, normalize(water_sun_dir)), 0.0), 3.0));
	float fade = smoothstep(1.5, 4.0, dist) * (1.0 - smoothstep(box * 0.28, box * 0.48, dist));
	v_light = color.rgb * water_rel_light(w.y) * water_light_scale * (e * phase * fade * exists * (1.0 + 0.35 * band));
	v_soft = clamp(coc / max(s_draw, 1e-4) * 1.5 + (flake ? 0.4 : 0.0), 0.0, 1.0);
	// the strobe: irradiance falling off over ~2 m from the lamp (absorption and spreading), forward scatter towards
	// the eye; specks nearer the mask than the usual fade still catch it (out of focus: the classic backscatter)
	v_lamp = vec3(0.0);
	if (lamp_flash > 0.001) {
		vec3 lr = w - lamp_pos;
		float ld = length(lr);
		float reach = 1.0 - smoothstep(lamp_reach * 0.75, lamp_reach * 1.1, ld);
		float cos_s = dot(lr / max(ld, 1e-3), -vdir);    // lamp -> speck vs speck -> eye
		float ph_l = mix(0.45, 1.8, pow(max(cos_s, 0.0), 2.0));
		float fade_l = smoothstep(1.0, 2.5, dist) * (1.0 - smoothstep(box * 0.40, box * 0.49, dist));
		v_lamp = lamp_color.rgb * (lamp_flash * lamp_gain * exp(-ld / 2.0) * reach * ph_l * fade_l * e * exists);
	}
	vp.xy += (UV - 0.5) * s_draw;
	VERTEX = vp.xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float crisp = smoothstep(1.0, 0.0, r);
	float soft = smoothstep(1.0, 0.35, r) * 0.6;
	ALBEDO = (v_light * amount * 0.55 + v_lamp) * mix(crisp, soft, v_soft);
}
