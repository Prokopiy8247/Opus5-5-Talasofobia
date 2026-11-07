class_name WorldEnv
extends Node3D
## Environment, sky (= fog backdrop), the lost sun, and the per-frame global shader uniforms.

var _fog_k := Vector2(-1.0, -1.0)
var env: Environment
var sun: DirectionalLight3D


func _ready() -> void:
	Palette.push_to_shaders()
	_push_fog()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = Mats.shader("sky")
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.TEAL_NEAR.lerp(Palette.SHAFT, 0.3)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = Config.EXPOSURE
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for i in 7:
		env.set_glow_level(i, 0.0)
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 0.7)
	env.set_glow_level(4, 0.5)
	env.set_glow_level(5, 0.35)
	# environment fog only as a fallback for built-in materials (labels); our shaders write FOG
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sky_affect = 0.0
	env.fog_density = 0.01
	env.volumetric_fog_enabled = false
	env.ssao_enabled = false
	env.sdfgi_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Palette.SHAFT.lerp(Color.WHITE, 0.4)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 600.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.6
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Config.SUN_DIR.normalized(), Vector3.FORWARD)


func _push_fog() -> void:
	set_fog_scale(1.0, 1.0)
	var c := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var w := c.duplicate()
	var s := c.duplicate()
	for i in mini(Config.BANDS.size(), 8):
		c[i] = Config.BANDS[i][0]
		w[i] = Config.BANDS[i][1]
		s[i] = Config.BANDS[i][2]
	RenderingServer.global_shader_parameter_set("uw_bands_c0", Vector4(c[0], c[1], c[2], c[3]))
	RenderingServer.global_shader_parameter_set("uw_bands_c1", Vector4(c[4], c[5], c[6], c[7]))
	RenderingServer.global_shader_parameter_set("uw_bands_w0", Vector4(w[0], w[1], w[2], w[3]))
	RenderingServer.global_shader_parameter_set("uw_bands_w1", Vector4(w[4], w[5], w[6], w[7]))
	RenderingServer.global_shader_parameter_set("uw_bands_s0", Vector4(s[0], s[1], s[2], s[3]))
	RenderingServer.global_shader_parameter_set("uw_bands_s1", Vector4(s[4], s[5], s[6], s[7]))
	# band colours are constant: computed once here instead of in every pixel (mirrors uw_band_col)
	for i in 8:
		RenderingServer.global_shader_parameter_set("uw_bcol%d" % i, _band_col(c[i]))


## Thin the deep water for the statue and the wall: band strength and deep density multipliers (1 = as set).
func set_fog_scale(bands: float, deep: float) -> void:
	if is_equal_approx(bands, _fog_k.x) and is_equal_approx(deep, _fog_k.y):
		return
	_fog_k = Vector2(bands, deep)
	RenderingServer.global_shader_parameter_set("uw_fog", Vector4(Config.FOG_DENSITY_SHALLOW,
		Config.FOG_DENSITY_DEEP * deep, Config.FOG_BAND_GAIN * bands, 1.0))


static func _uw_light(y: float) -> float:
	return exp(minf(y, 0.0) / 230.0)


static func _water_col(y: float) -> Vector3:
	var l := _uw_light(y)
	var c := Palette.lin(Palette.DEEP).lerp(Palette.lin(Palette.TEAL_FAR), smoothstep(0.0, 0.45, l))
	c = c.lerp(Palette.lin(Palette.TEAL_NEAR), smoothstep(0.35, 1.0, l))
	return c * (0.82 + 0.5 * l * l * l * l)


static func _band_col(cy: float) -> Vector3:
	return _water_col(cy) * 1.55 + Palette.lin(Palette.TEAL_FAR) * 0.22 * (1.0 - _uw_light(cy))


## Called every frame with the camera position.
func update(cam: Vector3, time: float) -> void:
	RenderingServer.global_shader_parameter_set("uw_cam_pos", cam)
	RenderingServer.global_shader_parameter_set("uw_time", time)
	var l := exp(minf(cam.y, 0.0) / 230.0)
	var dens := lerpf(Config.FOG_DENSITY_DEEP, Config.FOG_DENSITY_SHALLOW, exp(minf(cam.y, 0.0) / 120.0))
	env.fog_density = dens
	var fc := Palette.DEEP.lerp(Palette.TEAL_FAR, smoothstep(0.0, 0.45, l)).lerp(Palette.TEAL_NEAR, smoothstep(0.35, 1.0, l))
	env.fog_light_color = fc
	# the sun dies with depth: lit sand in the shallows, silhouettes edged by water light in the deep
	var lk := exp(minf(cam.y, 0.0) / 250.0)
	env.ambient_light_energy = lerpf(0.26, 0.55, lk)
	sun.light_energy = lerpf(0.9, 1.7, lk)
	sun.light_specular = 0.5 * clampf(exp(minf(cam.y, 0.0) / 70.0), 0.0, 1.0)
	# crisp debris shadows in the shallows (short cascade range), the long range once the slope opens up
	sun.directional_shadow_max_distance = lerpf(250.0, 600.0, smoothstep(-80.0, -160.0, cam.y))
	# no sun shadows in the deep: the sun is only a faint top light there, and its shadow map stair-stepped
	# on the statue's folds (it also saves the shadow passes)
	sun.shadow_enabled = cam.y > -380.0


## The diver's lamp for the unshaded effects (snow sparkle, beam): position, direction, power 0..1.
func set_lamp(pos: Vector3, dir: Vector3, power: float) -> void:
	RenderingServer.global_shader_parameter_set("uw_lamp_pos", pos)
	RenderingServer.global_shader_parameter_set("uw_lamp_dir", Vector4(dir.x, dir.y, dir.z, power))


func set_reveal(wall: float, head: float, door: float, ending: float) -> void:
	RenderingServer.global_shader_parameter_set("uw_reveal", Vector4(wall, head, door, ending))
