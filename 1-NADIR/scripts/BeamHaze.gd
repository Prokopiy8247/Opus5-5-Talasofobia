extends MeshInstance3D
## Light scattered by the water toward the eye: the torch cone and one optional point lamp, drawn as a single
## full-screen pass that reads the depth buffer (shaders/beam_haze.gdshader). Replaces engine volumetric fog,
## which only hazed geometry: fully fogged objects in the beam showed as hard silhouettes against the backdrop.

var mat: ShaderMaterial


func build(cam: Camera3D) -> void:
	name = "BeamHaze"
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	mesh = q
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/beam_haze.gdshader")
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.045
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 3
	fn.seed = 7
	var nt := NoiseTexture3D.new()
	nt.width = 64
	nt.height = 64
	nt.depth = 64
	nt.seamless = true
	nt.normalize = true
	nt.noise = fn
	mat.set_shader_parameter("noise_tex", nt)
	Config.apply_torch_profile(mat)
	mat.set_shader_parameter("range", Config.TORCH_RANGE)
	mat.set_shader_parameter("torch_col", Palette.TORCH.srgb_to_linear())
	mat.set_shader_parameter("torch_gain", Config.HAZE_GAIN)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	position = Vector3(0.0, 0.0, -1.0)
	cam.add_child(self)
	G.haze = self


func set_gain(v: float) -> void:
	mat.set_shader_parameter("torch_gain", v)


func set_extinction(sigma: float) -> void:
	mat.set_shader_parameter("sigma", sigma)


## Bottom nepheloid layer: the beam thickens within ~10 m of the floor at world y (-1e9 switches it off).
func set_floor(y: float) -> void:
	mat.set_shader_parameter("floor_y", y)


## One point lamp hazes the water around it (range 0 switches it off).
func set_lamp(pos: Vector3, col: Color, lamp_range: float, gain: float) -> void:
	mat.set_shader_parameter("lamp", Vector4(pos.x, pos.y, pos.z, lamp_range))
	mat.set_shader_parameter("lamp_col", col.srgb_to_linear())
	mat.set_shader_parameter("lamp_gain", gain)
