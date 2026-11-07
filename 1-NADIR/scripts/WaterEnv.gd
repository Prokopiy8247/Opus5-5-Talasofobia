extends Node
## Depth-driven water look: WorldEnvironment (exponential fog for range; beam haze is BeamHaze), the refracted
## sun, the downwelling light, ambient light. Fog colour == backdrop colour at every depth; the directional
## water light (brighter above, abyss below) is one full-screen pass on top of both (WaterLight).
## Eye adaptation: once the torch is on, the dazzled eye loses the residual blue of the water (x0.5 linear,
## fast then slower, like light adaptation) and gets it back slowly when the light goes out.
## CONTRACT: env.fog_light_color is the ONE water colour (eye-adapted); every consumer reads it.

# depth -> exponential fog density (thicker in the last 30 m: the floor emerges through bottom murk)
const FOG_KEYS := [[0.0, 0.0085], [60.0, 0.011], [150.0, 0.0145], [330.0, 0.0175], [800.0, 0.0175], [1500.0, 0.018],
	[1530.0, 0.022]]
const SUN_DIR := Vector3(-0.34, -0.9, -0.27)   # refracted sun, travelling downward
const WATER_LIGHT_MAX := 340.0                  # the water light gradient is 0 below 330 m
const ADAPT_MIN := 0.5                          # water colour (linear) once the eye has adapted to the torch
const ADAPT_TAU_LIT := 1.1                      # s, light adaptation (fast: the pupil and the cones)
const ADAPT_TAU_DARK := 4.0                     # s, back to the dark (slower)

var env: Environment
var sun: DirectionalLight3D
var downwell: DirectionalLight3D
var daylight := 1.0
var adapt := 0.0                                # 0 = dark-adapted eye, 1 = adapted to the torch
var _adapt_snap := true                         # snap on the first running frame (no fade after loading)
var _back_mat: ShaderMaterial
var _backdrop: MeshInstance3D


func build() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	# The backdrop is a huge inside-out sphere around the camera, fogged exactly like far geometry,
	# so fully fogged objects always match it (BG colour/sky are not treated like geometry by volumetric fog).
	_back_mat = ShaderMaterial.new()
	_back_mat.shader = load("res://shaders/backdrop.gdshader")
	_backdrop = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 5200.0
	sph.height = 10400.0
	sph.radial_segments = 32
	sph.rings = 16
	_backdrop.mesh = sph
	_backdrop.material_override = _back_mat
	_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_backdrop)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.SURF_TEAL
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.0)
	env.set_glow_level(2, 0.6)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.6)
	env.set_glow_level(5, 0.3)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_energy = 1.0
	env.fog_sky_affect = 1.0
	env.fog_aerial_perspective = 0.0
	# Sun scatter brightened fogged geometry toward the sun but not the fog-less backdrop: silhouettes. Off.
	env.fog_sun_scatter = 0.0
	# No engine volumetric fog: it hazed geometry but not the backdrop (hard silhouettes in the beam), smeared
	# when the view turned and showed froxel blocks. Scattered light is drawn by BeamHaze instead.
	env.volumetric_fog_enabled = false
	# No contrast adjustment: contrast 1.06 (applied around mid-grey after tonemapping) clipped everything
	# below ~7/255 to black, so every fade into the dark (beam rim, haze, fog, the spill) ended in a hard edge.
	env.adjustment_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	G.env = env
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, SUN_DIR, Vector3.FORWARD)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = false
	sun.light_specular = 0.4
	# Downwelling light: the diffuse water light from above that survives below the sunlit zone. Tops of the
	# line, tags and weight read lit grey-blue, undersides dark, instead of black cut-outs in the blue.
	downwell = DirectionalLight3D.new()
	downwell.name = "Downwell"
	add_child(downwell)
	downwell.look_at_from_position(Vector3.ZERO, Vector3.DOWN, Vector3.FORWARD)
	downwell.shadow_enabled = false
	downwell.light_specular = 0.15
	update(0.0, 0.0)


func update(depth: float, dt: float) -> void:
	# eye adaptation: torch stutters (0.3 s) are too short to move it; while loading it follows the torch at once
	var lit: bool = G.player != null and float(G.player.get("torch_out")) > 0.5
	var want := 1.0 if lit else 0.0
	if not G.running or _adapt_snap:
		adapt = want
		_adapt_snap = not G.running
	else:
		adapt = lerpf(adapt, want, 1.0 - exp(-maxf(dt, 0.0) / (ADAPT_TAU_LIT if lit else ADAPT_TAU_DARK)))
	var k := lerpf(1.0, ADAPT_MIN, adapt)
	Palette.adapt_k = k
	var wl := Palette.water_base_at(depth).srgb_to_linear()
	var water := Color(wl.r * k, wl.g * k, wl.b * k).linear_to_srgb()
	daylight = exp(-depth / 42.0) * (1.0 - smoothstep(180.0, 260.0, depth))
	var lit_zone := 1.0 - smoothstep(330.0, 520.0, depth)   # where any daylight is left at all
	# Fully fogged geometry converges to the fog colour == the backdrop colour == the palette water colour.
	_back_mat.set_shader_parameter("water_col", water)
	if G.camera:
		_backdrop.global_position = G.camera.global_position
	env.fog_light_color = water
	env.fog_density = _keyed(FOG_KEYS, depth)
	if G.reveal:
		env.fog_density *= 0.22   # harness stills only: see the whole creature
	if G.haze:
		G.haze.set_extinction(env.fog_density)
	if G.water_light:
		G.water_light.visible = depth < WATER_LIGHT_MAX
		G.water_light.set_fog_density(env.fog_density)
	env.ambient_light_color = water.lerp(Color(0.55, 0.8, 0.85), 0.35 * daylight)
	# the 0.45 floor keeps objects in the blue from going black (the palette colour already holds absorption);
	# it fades in below the shallows so B1 keeps its look
	env.ambient_light_energy = (0.45 * smoothstep(5.0, 40.0, depth) + 1.4 * daylight) * lit_zone + 0.02
	downwell.light_color = water.lightened(0.15)
	downwell.light_energy = 1.6 * lit_zone * smoothstep(5.0, 40.0, depth)
	downwell.visible = depth < 540.0 and downwell.light_energy > 0.001
	sun.light_energy = 2.4 * daylight
	sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(0.45, 0.8, 0.85), smoothstep(0.0, 70.0, depth))
	sun.visible = daylight > 0.002
	RenderingServer.global_shader_parameter_set("g_water_col", water)
	RenderingServer.global_shader_parameter_set("g_daylight", daylight)


static func _keyed(keys: Array, x: float) -> float:
	if x <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if x <= keys[i][0]:
			var f: float = (x - keys[i - 1][0]) / (keys[i][0] - keys[i - 1][0])   # linear: no stall at keys
			return lerpf(keys[i - 1][1], keys[i][1], f)
	return keys[keys.size() - 1][1]
