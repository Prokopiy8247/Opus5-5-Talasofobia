shader_type spatial;
// Far sun shafts: soft camera-facing ribbons along the refracted sun direction, wrapped around the camera.
// Lit only through the sun's shadow term (light()), so the boat, the reef and the lip cut them (softly).
// The water closer than ~30 m belongs to the ray volume (light_volume.gdshader); these carry the rays that recede
// into the blue. Each ribbon is subdivided (16 rows) so the swell can rock it along its length.
render_mode blend_add, depth_draw_never, cull_disabled, fog_disabled, ambient_light_disabled, specular_disabled, skip_vertex_transform;
#include "res://shaders/water_common.gdshaderinc"

uniform float tile = 300.0;
uniform float shaft_len = 420.0;
uniform float amount = 1.0;
uniform float depth_scale = 60.0;
uniform float gain = 0.14;
uniform float near_start = 18.0;        // ribbons fade in from here (the ray volume owns the near water)
// Thread mode (a second material): a few thin shafts anchored in the world (INSTANCE_CUSTOM.xy = the absolute surface
// entry point), reaching the deep: the last threads of light around the head at the eye lock.
uniform bool threads = false;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 v_world;
varying vec4 v_data;    // x: across 0..1, y: seed, z: metres along the shaft from the surface, w: instance fade
varying float v_gain;
varying float v_width;
varying vec3 v_side;
varying float v_flicker;

void vertex() {
	vec3 L = -normalize(water_sun_dir);                  // light travel direction (downwards)
	float seed = INSTANCE_CUSTOM.w;
	float width = INSTANCE_CUSTOM.z;
	float t_cam = water_cam_pos.y / L.y;                  // distance along L from the surface to the camera depth
	vec2 c0 = water_cam_pos.xz - L.xz * t_cam;            // surface point whose shaft passes through the camera
	vec2 base = INSTANCE_CUSTOM.xy * tile;
	// slow lateral drift, as if the focusing wave crests wander
	base += vec2(sin(TIME * 0.031 + seed * 40.0), cos(TIME * 0.026 + seed * 23.0)) * (2.0 + width * 0.25);
	vec2 q = fract((base - c0) / tile + 0.5) - 0.5;        // -0.5..0.5 in the tile around the camera
	vec2 p0 = c0 + q * tile;
	float wrap_fade = (1.0 - smoothstep(0.36, 0.49, abs(q.x))) * (1.0 - smoothstep(0.36, 0.49, abs(q.y)));
	if (threads) {
		p0 = INSTANCE_CUSTOM.xy + vec2(sin(TIME * 0.031 + seed * 40.0), cos(TIME * 0.026 + seed * 23.0)) * 2.0;
		wrap_fade = 1.0;
	}
	vec3 top = vec3(p0.x, 0.0, p0.y);
	float along = UV.y * shaft_len;
	vec3 axis = top + L * along;
	// the swell refocuses the light: the shaft rocks sideways at 0.12-0.4 Hz, more the deeper it reaches
	// (about 0.5 m at 10 m, 3 m at 60 m), with a small rigid shift on top
	float dpt = max(-axis.y, 0.0);
	float amp = (0.35 + clamp(dpt * 0.05, 0.0, 3.6)) * (threads ? 0.35 : 1.0);
	float ph = seed * 61.0;
	float lag = along * 0.012;                            // the deeper part follows a little later
	vec2 sw = vec2(
		sin(TIME * 0.78 + ph - lag) * 0.55 + sin(TIME * 1.52 + ph * 1.7 - lag * 1.6) * 0.30 + sin(TIME * 2.41 + ph * 2.3) * 0.15,
		cos(TIME * 0.93 + ph * 1.3 - lag) * 0.40 + sin(TIME * 2.07 + ph * 0.7) * 0.20);
	axis.xz += sw * amp;
	// and a gentle long bend
	axis.xz += vec2(sin(TIME * 0.11 + seed * 17.0 + along * 0.012), cos(TIME * 0.09 + seed * 9.0 + along * 0.01)) * along * 0.004;
	vec3 to_cam = normalize(water_cam_pos - axis);
	vec3 side = normalize(cross(L, to_cam));
	float breath = 1.0 + 0.25 * sin(TIME * 0.07 + seed * 31.0 + along * 0.008);
	vec3 w = axis + side * (UV.x - 0.5) * width * breath;
	// camera distance from the shaft axis: a ribbon never slices the view when the camera is inside it
	vec3 rc = water_cam_pos - top;
	float perp = length(rc - L * dot(rc, L));
	float inside = threads ? 1.0 : smoothstep(width * 0.6 + 1.0, width * 1.6 + 6.0, perp);
	v_world = w;
	v_side = side;
	v_data = vec4(UV.x, seed, along, wrap_fade * inside);
	// narrow shafts only a touch brighter than the wide faint veils (bright thin ones read as scratches)
	v_gain = mix(0.5, 0.55, smoothstep(1.5, 9.0, width));
	v_width = width;
	// per-shaft flicker as the surface lens focuses and defocuses (0.55..1), calmer deeper down
	float fl = wb_noise(vec2(TIME * 1.4 + seed * 31.0, seed * 17.0));
	v_flicker = mix(mix(0.55, 1.0, fl), 0.85 + 0.15 * fl, smoothstep(30.0, 140.0, max(-water_cam_pos.y, 0.0)));
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float x = v_data.x * 2.0 - 1.0;
	// soft gaussian cross-section, exactly 0 at the quad border (threads: a broader, flatter glow)
	float across = exp(-x * x * (threads ? 2.0 : 4.0)) * (1.0 - x * x);
	float seed = v_data.y;
	float along = v_data.z;
	float depth = -v_world.y;
	vec3 rel = v_world - water_cam_pos;
	float dist = length(rel);
	vec3 vdir = rel / max(dist, 0.001);
	vec3 L = -normalize(water_sun_dir);
	float cam_d = max(-water_cam_pos.y, 0.0);
	float far_end = mix(70.0, 170.0, smoothstep(4.0, 40.0, cam_d));
	float fade;
	if (threads) {
		// threads: kept down to the deep, gone close to the eye, far away and far above
		fade = smoothstep(12.0, 35.0, dist) * (1.0 - smoothstep(140.0, 240.0, dist)) * smoothstep(0.3, 5.0, depth);
	} else {
		fade = smoothstep(near_start, near_start * 2.5, dist) * (1.0 - smoothstep(far_end * 0.35, far_end, dist));
		fade *= smoothstep(0.3, 5.0, depth) * exp(-depth / depth_scale);
	}
	// thin far shafts melt into the haze instead of reading as scratches
	fade *= smoothstep(0.03, 0.08, v_width / max(dist, 1.0));
	// looking down, the ray volume alone carries the light (ribbons there read as plates converging below)
	fade *= smoothstep(-0.85, -0.55, vdir.y);
	// the far end of the ribbon never shows as a cut
	fade *= 1.0 - smoothstep(0.75, 1.0, along / shaft_len);
	// a ribbon turning edge-on collapses into a hard line: fade it by how squarely it faces the eye
	vec3 rn = normalize(cross(L, v_side));
	fade *= smoothstep(0.15, 0.45, abs(dot(rn, vdir)));
	// looking along the light (down into the abyss, up at the sun) ribbons would converge into wedges: gone there,
	// the ray volume carries the rays in those views
	fade *= 1.0 - smoothstep(0.55, 0.8, abs(dot(vdir, L)));
	// broken along the length; the bright knots run down the shaft as the focus moves (wb_noise: an integer-hashed
	// noise, so a shaft never steps in brightness at a noise cell border)
	float scroll = TIME * 3.0;
	float brk = wb_noise(vec2((along - scroll) * 0.022 + seed * 37.0, TIME * 0.06 + seed * 11.0)) * 0.65
		+ wb_noise(vec2((along - scroll * 1.7) * 0.075 + seed * 13.0, seed * 5.0 + TIME * 0.1)) * 0.35;
	brk = smoothstep(0.2, 0.8, brk);
	if (threads) {
		brk = 1.0;   // a thread is a continuous glow, not a dashed line (and no face-on blotches)
	}
	float shimmer = 0.8 + 0.2 * sin(TIME * (0.35 + seed * 0.45) + seed * 30.0 - along * 0.05);
	// soft against the scene: no hard line where a ribbon passes into the reef or the deep wall
	float zb = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zb, 1.0);
	float scene_z = -sv.z / sv.w;
	float soft = clamp((scene_z + VERTEX.z) / clamp(dist * 0.4, 6.0, 35.0), 0.0, 1.0);
	float a = across * fade * brk * shimmer * v_flicker * soft * v_data.w * v_gain * amount * gain * water_light_scale;
	// the colour of sunlight at this depth (no warm grey), at constant brightness
	vec3 tc = wb_light_tint(depth);
	ALBEDO = tc * (0.9 / max(dot(tc, WB_LUMA), 1e-3)) * a;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		// sun colour only (its energy is already in water_light_scale); the shadow cut is softened, and far away
		// (where the shadow map is coarse and the splits change) it fades out entirely
		vec3 c = LIGHT_COLOR / max(max(LIGHT_COLOR.r, LIGHT_COLOR.g), max(LIGHT_COLOR.b, 1e-4));
		vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, FRAGCOORD.z, 1.0);
		float k = 0.7 * (1.0 - smoothstep(100.0, 150.0, length(vp.xyz / vp.w)));
		DIFFUSE_LIGHT += mix(1.0, ATTENUATION, k) * c;
	}
}
