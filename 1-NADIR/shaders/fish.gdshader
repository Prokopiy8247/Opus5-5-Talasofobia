shader_type spatial;
render_mode world_vertex_coords, cull_disabled, diffuse_burley, specular_schlick_ggx;
// A milling bait ball of small silver fish near the line: the only crowd of life in the whole descent.
// Fully GPU-driven: each instance circles one of three slowly drifting lobe centres, so the school is one dense,
// irregular mass with no hollow core that changes shape over ~20 s. INSTANCE_CUSTOM = phase, radial jitter,
// height jitter, size. A roll wave rolls through the school: when a fish's flank (a vertical mirror) tilts so it
// reflects the bright water overhead, the whole body flashes silver, in moving bands. Backs are dark (seen from
// above the fish are darker than the water), bellies pale; the school bulges away from the diver.
uniform vec3 center = vec3(0.0);
uniform float radius = 5.5;
uniform float omega = 0.16;
uniform vec4 water_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);   // set per frame
// the sun-ray caustic net (Beat01 passes the same cellular texture the ray pass uses)
uniform sampler2D caustic_tex : filter_linear_mipmap, repeat_enable;
uniform float caustic_gain = 0.0;   // 0 until the texture is set
global uniform float g_time;
global uniform float g_daylight;
global uniform vec3 g_cam_pos;

const vec3 TO_SUN = vec3(0.3403, 0.9007, 0.2702);   // = -WaterEnv.SUN_DIR

varying vec3 v_side;
varying vec3 v_wp;
varying float v_tail;

// The caustic net at world point p: identical to rays_at() in sun_rays.gdshader (without the boat shadow).
float caustic_at(vec3 p) {
	vec2 q = p.xz - TO_SUN.xz * (p.y / TO_SUN.y);
	float dep = max(-p.y, 0.0);
	float lod = clamp(dep / 28.0, 0.0, 5.0);
	vec2 w = vec2(sin(q.y * 0.07 + g_time * 0.31), cos(q.x * 0.06 - g_time * 0.27)) * 1.6;
	float a = textureLod(caustic_tex, (q + w) / 64.0 + g_time * vec2(0.004, 0.0025), lod).r;
	float b = textureLod(caustic_tex, (q - w) / 41.0 - g_time * vec2(0.003, -0.004), lod).r;
	float c = pow(1.0 - a, 7.0) * pow(1.0 - b, 3.5);
	c = max(c - 0.04, 0.0) * (1.0 / 0.96) * mix(0.35, 1.0, smoothstep(0.0, 4.0, dep));
	return c * exp(-dep / 45.0);
}

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float tm = g_time;
	vec3 ctr = center + vec3(sin(tm * 0.05), 0.3 * sin(tm * 0.08), cos(tm * 0.04)) * 3.0;
	// three overlapping lobes ~2 m off the centre, each drifting on its own slow rhythm (they average out to the
	// centre, so Beat01's gaze-cue marker stays on the school)
	float lobe = floor(fract(c.w * 7.31 + c.y * 3.17) * 3.0);
	float la = lobe * 2.0944 + 0.45 * sin(tm * (0.07 + 0.023 * lobe) + lobe * 1.9);
	ctr += vec3(cos(la), 0.4 * sin(tm * (0.11 + 0.03 * lobe) + lobe * 2.3), sin(la)) * 2.0;
	// a dense middle with no hole and a ragged, breathing outline; inner fish circle faster (shear); the lobes
	// differ in size, and each fish wanders in and out a little
	float a = c.x * 6.2831 + tm * omega * (1.4 - 0.5 * c.y);
	float rn = pow(c.y, 0.45);
	float rad = radius * (0.95 - 0.15 * lobe);
	float wan = sin(tm * 0.35 + c.x * 53.0);
	float r = rad * rn * (1.0 + 0.22 * sin(a * 3.0 + tm * 0.13 + 1.7 + lobe * 2.1) + 0.12 * sin(a * 5.0 - tm * 0.09 + lobe));
	r *= 1.0 + 0.12 * wan;
	float hh = 2.4 * sqrt(max(1.0 - 0.6 * rn * rn, 0.0));
	float bob = sin(tm * 0.4 + c.x * 20.0);
	// each orbit is tilted a little, so seen from above or below the school is not a set of concentric rings
	float tph = a + c.w * 6.2831;
	vec3 off = vec3(cos(a) * r, (c.z - 0.5) * 2.0 * hh + bob * 0.4 + r * 0.25 * sin(tph), sin(a) * r);
	vec3 fwd = normalize(vec3(-sin(a), 0.25 * cos(tph) + 0.03 * cos(tm * 0.4 + c.x * 20.0), cos(a))
			+ vec3(cos(a), 0.0, sin(a)) * 0.3 * cos(tm * 0.35 + c.x * 53.0));
	// and each lobe mills in its own tilted plane (Rodrigues rotation about a horizontal axis)
	float tilt = 0.42 * (lobe - 1.0) + 0.12 * sin(tm * 0.05 + lobe * 1.3);
	vec3 k = vec3(cos(lobe * 2.1 + 0.6), 0.0, sin(lobe * 2.1 + 0.6));
	float ct = cos(tilt);
	float stl = sin(tilt);
	off = off * ct + cross(k, off) * stl + k * dot(k, off) * (1.0 - ct);
	fwd = normalize(fwd * ct + cross(k, fwd) * stl + k * dot(k, fwd) * (1.0 - ct));
	vec3 pos = ctr + off;
	// flash wave: the fish roll together as a wave passes through the school
	float wave = sin(dot(pos.xz, vec2(0.45, 0.3)) - tm * 2.2 + c.x * 1.5);
	float roll = 0.55 * wave;
	vec3 s0 = normalize(cross(fwd, vec3(0.0, 1.0, 0.0)));
	vec3 u0 = cross(s0, fwd);
	vec3 up = u0 * cos(roll) + s0 * sin(roll);
	vec3 side = normalize(cross(fwd, up));
	// part around the diver
	vec3 aw = pos - g_cam_pos;
	float dd = length(aw);
	pos += aw / max(dd, 0.01) * 3.5 * smoothstep(8.0, 2.5, dd);
	v_tail = smoothstep(-0.10, -0.17, VERTEX.x);
	vec3 v = VERTEX * (0.75 + c.w * 0.6);
	float wig = sin(tm * 11.0 + c.x * 37.0 + v.x * 14.0) * 0.045 * smoothstep(0.08, -0.22, v.x);
	VERTEX = pos + fwd * v.x + up * v.y + side * (v.z + wig);
	vec3 n = NORMAL;
	NORMAL = normalize(fwd * n.x + up * n.y + side * n.z);
	v_side = side;
	v_wp = VERTEX;
}

void fragment() {
	// Reflections are off in this project, so the flash is computed: the flank facing the eye is a vertical
	// mirror; when it sends the view ray up toward the bright water overhead the whole fish flashes. It needs the
	// flank broadside to the eye (a fish seen from straight below shows its dark belly), never on the tail.
	vec3 Vw = normalize(v_wp - CAMERA_POSITION_WORLD);
	float fd = dot(v_side, -Vw);
	vec3 fl = v_side * sign(fd);
	float broad = smoothstep(0.3, 0.7, abs(fd));
	float flash = smoothstep(0.55, 0.8, reflect(Vw, fl).y) * broad * (1.0 - 0.85 * v_tail);
	vec3 nw = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float belly = smoothstep(0.2, -0.4, nw.y);
	// countershading: a dark blue-green back (under the white sun of the shallows a grey back reads as a pale
	// fleck against the teal from above), a pale belly
	vec3 alb = mix(vec3(0.012, 0.028, 0.040), vec3(0.30, 0.34, 0.36), belly);
	ALBEDO = alb;
	METALLIC = 0.0;
	ROUGHNESS = mix(0.7, 0.45, belly);   // matte backs: no sun glint turning every fish into a white fleck from above
	SPECULAR = mix(0.2, 0.5, belly);
	vec3 e = water_col.rgb * mix(0.12, 0.35, belly) + vec3(0.85, 0.95, 1.0) * flash * 1.6;
	// the ray net plays over the backs and flanks that face the sun (reflected by the albedo: a flicker on the
	// dark backs, never a white fleck)
	e += vec3(0.55, 0.85, 0.80) * caustic_at(v_wp) * max(dot(nw, TO_SUN), 0.0) * alb * caustic_gain;
	EMISSION = min(e * g_daylight, vec3(0.9));   // stays under the 1.05 glow threshold
}
