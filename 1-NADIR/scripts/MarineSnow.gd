extends GPUParticles3D
## Marine snow: a few thousand world-space motes wrapped in a 40 m box around the camera (process shader),
## drifting slowly down and with the beat-driven current (g_flow). Lit in the draw shader by the torch (same law
## as the lights), by the ambient water light (visible in the blue before the torch), plus cold sparks in the dark.

var _dm: ShaderMaterial


func build() -> void:
	name = "MarineSnow"
	amount = Config.SNOW_COUNT
	lifetime = 3600.0
	explosiveness = 1.0
	one_shot = false
	local_coords = false
	fixed_fps = 0
	interpolate = false
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/snow_process.gdshader")
	pm.set_shader_parameter("box", Config.SNOW_BOX)
	process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_dm = ShaderMaterial.new()
	_dm.shader = load("res://shaders/snow_draw.gdshader")
	_dm.set_shader_parameter("range", Config.TORCH_RANGE)
	Config.apply_torch_profile(_dm)
	_dm.set_shader_parameter("sun_up", -preload("res://scripts/WaterEnv.gd").SUN_DIR.normalized())
	quad.material = _dm
	draw_pass_1 = quad
	var h := Config.SNOW_BOX * 0.6
	visibility_aabb = AABB(Vector3(-h, -h, -h), Vector3(h, h, h) * 2.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitting = true
	G.snow = self


## Hook (B5): slow eddies in the snow (the water churned by the creature). Stateless in the process shader, so
## an eased value gives smoothly moving motes; 0 = still water. Callers must ease it, never step it.
func set_turbulence(a: float) -> void:
	(process_material as ShaderMaterial).set_shader_parameter("turb", clampf(a, 0.0, 1.0))


## Hook (B5): a shell of cold light sweeping through the snow, the water displaced ahead of the creature.
## radius < 0 or amp 0 switches it off.
func set_wave(origin: Vector3, radius: float, amp: float) -> void:
	_dm.set_shader_parameter("wave", Vector4(origin.x, origin.y, origin.z, radius))
	_dm.set_shader_parameter("wave_amp", maxf(amp, 0.0))


func _process(_dt: float) -> void:
	if G.camera:
		global_position = G.camera.global_position
		var dens := smoothstep(8.0, 140.0, G.depth)
		_dm.set_shader_parameter("opacity", lerpf(0.6, 1.0, dens) * clampf(G.snow_mult, 0.0, 2.0))
		# the one water colour (eye-adapted, WaterEnv)
		var w := (G.env.fog_light_color if G.env else Palette.water_at(G.depth)).srgb_to_linear()
		_dm.set_shader_parameter("water_lin", Vector3(w.r, w.g, w.b))
		if G.env:
			_dm.set_shader_parameter("sigma", G.env.fog_density)
		_dm.set_shader_parameter("view_h", get_viewport().get_visible_rect().size.y)
