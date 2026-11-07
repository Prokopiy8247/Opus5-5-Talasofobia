extends GPUParticles3D
## The diver's exhaled bubbles: a burst from both sides of the regulator on every exhale (synced to the
## breathing loop: exhale ~0.42-0.80 of each 4.5 s cycle), rising past the mask. World-space particles.

const EXHALE := Vector2(0.43, 0.78)
var _phase_fallback := 0.0


func build(cam: Camera3D) -> void:
	name = "Bubbles"
	amount = 90
	lifetime = 5.0
	explosiveness = 0.0
	randomness = 0.3
	local_coords = false
	fixed_fps = 0
	interpolate = true
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/bubble_process.gdshader")
	process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var dm := ShaderMaterial.new()
	dm.shader = load("res://shaders/bubble_draw.gdshader")
	Config.apply_torch_profile(dm)
	q.material = dm
	draw_pass_1 = q
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 14, 12))
	position = Vector3(0.0, -0.13, -0.05)   # the regulator, just below and in front of the eyes
	emitting = false
	cam.add_child(self)


func step(dt: float) -> void:
	var ph := 0.0
	var breathing := true
	if G.audio and G.audio.has_method("get_breath_phase"):
		ph = G.audio.get_breath_phase()
		breathing = G.audio.get_breath_level() > 0.05
	else:
		_phase_fallback = fmod(_phase_fallback + dt / 4.5, 1.0)
		ph = _phase_fallback
	emitting = breathing and G.running and ph > EXHALE.x and ph < EXHALE.y
