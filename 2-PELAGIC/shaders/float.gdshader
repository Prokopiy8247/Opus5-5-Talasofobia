shader_type spatial;
// The marker float at the end of the descent: an old, weathered marker, not a toy. Lit by almost nothing at this depth:
// between the strobe's flashes it sinks to a dark, dull rust (only a faint glow of the lamp carried in the translucent
// plastic under the lamp keeps it legible); each flash lights its top from the lamp above it.
// kind 0 orange hard plastic shell: sun-faded and dirty, a broad patchy biofilm towards the bottom, an old dull
// waterline band, scuffs and scratches that turn matte; kind 1 the reflective band (and the lamp housing), dulled
// and grimy; kind 2 dark lead weight. Uses the shared water fog like every custom shader.
render_mode cull_back;
#include "res://shaders/water_common.gdshaderinc"

uniform int kind = 0;
uniform vec4 shell : source_color = vec4(1.0, 0.478, 0.102, 1.0);   // Palette.MARKER_ORANGE
uniform float glow = 0.03;
// The lamp's OmniLight runs at lamp_base energy between flashes (FloatBob: 0.35 + 3 * flash; the snow and the
// water around it use that constant part). A strobe is dark between flashes, so the float takes only the flash part
// of that light: its constant base is subtracted here (for any non-directional light, which at the end of the
// descent is only the lamp).
uniform float lamp_base = 0.35;

varying vec3 v_w;
varying vec3 v_l;
varying float v_f0;

void vertex() {
	v_l = VERTEX;
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// value noise on the surface without a seam or a pole singularity: three planar projections blended by the local
// normal (the shell is a closed body around its origin)
float tri_noise(vec3 p, vec3 n, float s) {
	vec3 w = abs(n);
	w /= max(w.x + w.y + w.z, 1e-4);
	return water_noise(p.yz * s) * w.x + water_noise(p.xz * s + 3.7) * w.y + water_noise(p.xy * s + 7.1) * w.z;
}

void fragment() {
	vec3 col;
	float rough;
	float spec;
	vec3 n = v_l / max(length(v_l), 1e-4);
	if (kind == 0) {
		float up = clamp(v_l.y / 0.37, -1.0, 1.0);
		float big = tri_noise(v_l, n, 5.0);
		float mid = tri_noise(v_l, n, 13.0);
		float fine = tri_noise(v_l, n, 41.0);
		// sun-faded, dirty plastic: never the clean saturated orange of a new float
		col = mix(shell.rgb, vec3(0.42, 0.22, 0.10), 0.22 + 0.25 * big);
		// broad patchy biofilm from the bottom up (olive-brown), with ragged edges
		float film = smoothstep(0.35, -0.75, up + 0.45 * (big - 0.5) + 0.2 * (mid - 0.5));
		film *= 0.55 + 0.45 * mid;
		col = mix(col, vec3(0.10, 0.075, 0.035), film * 0.75);
		// the old waterline: a dull, darker band where it once floated at the surface
		float wl = 1.0 - smoothstep(0.035, 0.085, abs(up - 0.42 - 0.06 * (mid - 0.5)));
		col *= mix(1.0, 0.6, wl);
		// scuffs and scratches: lighter, matte
		float scuff = smoothstep(0.78, 0.93, tri_noise(v_l * vec3(1.0, 3.5, 1.0), n, 23.0)) * (1.0 - film);
		col = mix(col, vec3(0.62, 0.42, 0.28), scuff * 0.35);
		rough = clamp(0.48 + 0.25 * big + 0.1 * fine + 0.3 * film + 0.25 * wl + 0.25 * scuff, 0.0, 0.95);
		spec = 0.35;
		// the faint glow of the lamp carried in the translucent plastic, strongest just under the lamp
		EMISSION = col * glow * mix(0.25, 1.0, smoothstep(0.2, 0.95, up));
	} else if (kind == 1) {
		float g = tri_noise(v_l, n, 17.0);
		col = vec3(0.40, 0.385, 0.34) * (0.75 + 0.35 * g);
		rough = 0.5 + 0.25 * g;
		spec = 0.4;
		EMISSION = col * glow * 0.25;
	} else {
		col = vec3(0.05, 0.05, 0.055);
		rough = 0.55;
		spec = 0.4;
	}
	ALBEDO = col * water_rel_light(v_w.y);
	ROUGHNESS = rough;
	SPECULAR = spec;
	v_f0 = 0.08 * spec;
	FOG = water_fog(v_w);
}

void light() {
	float k = 1.0;
	float nl = dot(NORMAL, LIGHT);
	float ndl = max(nl, 0.0);
	float dif = ndl;
	if (!LIGHT_IS_DIRECTIONAL) {
		// LIGHT_COLOR = colour x energy x PI; the lamp's colour has red 1.0, so its red channel gives the energy
		float e = LIGHT_COLOR.r * (1.0 / PI);
		k = max(e - lamp_base, 0.0) / max(e, 1e-4);
		// the flash also lights the water all around the lamp, and that glow wraps a soft fill past the hard
		// terminator of the point light (the lamp sits only 0.23 m above the shell)
		float wrap = clamp((nl + 0.45) / 1.45, 0.0, 1.0);
		dif = 0.7 * ndl + 0.3 * wrap * wrap;
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (dif * k / PI);
	// a soft GGX lobe (worn plastic), guarded for V = -L
	vec3 hv = VIEW + LIGHT;
	vec3 h = hv * inversesqrt(max(dot(hv, hv), 1e-12));
	float ndh = max(dot(NORMAL, h), 0.0);
	float a = max(ROUGHNESS * ROUGHNESS, 0.02);
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float D = a2 / max(PI * dd * dd, 1e-6);
	float ndv = max(dot(NORMAL, VIEW), 1e-3);
	float kk = a * 0.5;
	float vis = 0.25 / max((ndl * (1.0 - kk) + kk) * (ndv * (1.0 - kk) + kk), 1e-4);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * (k * ndl * D * vis * v_f0);
}
