extends Node3D
## Beat 2 — Blue to black (0:40-2:10, 80-330 m). Colour is absorbed, the boat shrinks to a dot, marine snow
## appears, tags tick by, the torch clicks on at ~245 m. M1: looking up at the boat and sun far above.
## First look straight down into emptiness. Mostly gaze choreography over the shared systems, plus one living
## thing: a siphonophore's cold light chain far off in the navy, which goes dark the moment the torch comes on.

const SUN_YAW := -128.5
const CHAIN_CUE := Vector2(-30.0, -8.0)    # where the chain hangs, seen from the line (it places the string)
const CHAIN_N := 56
const STEM_N := 96                         # faint stem points between the zooids (halo only)
const CHAIN_DIST := 45.0                   # metres from the line
const CHAIN_DEPTH := 232.0                 # centre depth; the string spans ~222-242 m, in frame through the cue
var depth_range := Vector2(80.0, 330.0)

var _chain: MultiMeshInstance3D
var _chain_centre := Vector3.ZERO
var _chain_mat: ShaderMaterial
var _chain_life := 1.0                     # 1 until the torch comes on, then 0 for good
var _chain_dying := false
var _was_running := false
var _gain := -1.0
var _alarm_t0 := -1.0                      # G.t when the torch first came on with the chain alive


func build(parent: Node3D) -> void:
	name = "Beat02_Blue"
	parent.add_child(self)
	var P := G.path
	_build_chain()
	P.add_cue_depth(80.0, 112.0, Vector2(70.0, -6.0), 4.0)
	P.add_cue_depth(112.0, 128.0, Vector2(150.0, 4.0), 4.0)
	# M1: up at the shrinking boat and the sun, the line rising to it.
	P.add_cue_depth(128.0, 197.0, Vector2(SUN_YAW + 25.0, 74.0), 4.5)
	# a glance down and behind: the torn rail of something enormous condensing out of the navy below
	P.add_cue_depth(197.0, 215.0, Vector2(165.0, -30.0), 3.0)
	# the gaze rests on the living string and follows it as the diver sinks past (up at it when the torch clicks on)
	P.add_cue_depth(215.0, 252.0, _chain_centre, 3.5)
	# torch on (~245 m): the beam falls straight down into nothing
	P.add_cue_depth(252.0, 292.0, Vector2(-10.0, -82.0), 3.5)
	P.add_cue_depth(292.0, 300.0, Vector2(150.0, -5.0), 3.5)


## A 30 m string of 56 zooids, gently bowed, running diagonally down across the cue direction.
func _build_chain() -> void:
	var dir := PathDef.cue_dir(CHAIN_CUE, Vector3.ZERO)
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var right := flat.cross(Vector3.UP).normalized()
	var centre := G.path.pos_at(G.path.s_at_depth(CHAIN_DEPTH)) + flat * CHAIN_DIST
	_chain_centre = centre
	var span := right * 22.0 + Vector3.DOWN * 20.0
	var along := span.normalized()
	var wave := (Vector3.UP - along * Vector3.UP.dot(along)).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	mm.mesh = q
	mm.instance_count = CHAIN_N + STEM_N
	var along_of := func(f: float) -> Vector3:
		return (centre + span * (f - 0.5) + wave * (2.6 * sin(PI * f) + 1.1 * sin(TAU * f + 0.6))
			+ flat * (3.5 * sin(PI * f + 0.3) - 1.8))
	var group_off := []
	for g in ceili(CHAIN_N / 4.0) + 1:
		group_off.append(rng.randf_range(-0.9, 0.9))   # uneven gaps between the groups
	for i in CHAIN_N:
		# zooids bunch into groups of four (cormidia) along the stem, with uneven gaps between the groups
		var g := floori(i / 4.0)
		var f := clampf((float(g) * 4.0 + float(group_off[g]) + float(i % 4) * 0.5 + rng.randf_range(-0.12, 0.12))
			/ float(CHAIN_N - 1), 0.0, 1.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, along_of.call(f)))
		var bright := rng.randf_range(0.65, 1.1) * (1.35 if i % 4 == 0 else 1.0)
		mm.set_instance_custom_data(i, Color(f, bright, rng.randf(), 0.0))
	# the stem: close-set halo-only points whose glows overlap into one faint thread linking the groups
	for k in STEM_N:
		var f := float(k) / float(STEM_N - 1)
		mm.set_instance_transform(CHAIN_N + k, Transform3D(Basis.IDENTITY, along_of.call(f)))
		mm.set_instance_custom_data(CHAIN_N + k, Color(f, 0.25 * (0.6 + 0.4 * sin(PI * f)), rng.randf(), 1.0))
	_chain_mat = ShaderMaterial.new()
	_chain_mat.shader = load("res://shaders/biolum_chain.gdshader")
	_chain_mat.set_shader_parameter("count", float(CHAIN_N))
	_chain_mat.set_shader_parameter("wave_axis", wave)
	_chain_mat.set_shader_parameter("wave_axis2", flat)
	_chain_mat.set_shader_parameter("gain", 0.0)
	_chain = MultiMeshInstance3D.new()
	_chain.name = "SiphonophoreChain"
	_chain.multimesh = mm
	_chain.material_override = _chain_mat
	_chain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_chain.extra_cull_margin = 4.0          # billboards and the undulation reach past the instance points
	add_child(_chain)


func _process(dt: float) -> void:
	if _chain_mat == null:
		return
	if not G.running or G.player == null:
		_set_gain(0.0)
		_chain.visible = true                # drawn at zero gain during the warm-up so its pipeline is ready
		return
	var torch: float = G.player.get("torch_level") if "torch_level" in G.player else 0.0
	if not _was_running:
		_was_running = true
		if torch > 0.3:                      # started below the click-on: it is already dark, no alarm
			_chain_life = 0.0
			_chain_dying = true
	# The siphonophore answers the torch: a warning flash races down the string, each light dying as it passes.
	if torch > 0.3 and not _chain_dying:
		_chain_dying = true
		_alarm_t0 = G.t
	if _chain_dying:
		if _alarm_t0 >= 0.0:
			var a := G.t - _alarm_t0
			_chain_mat.set_shader_parameter("alarm", a)
			_chain_life = minf(_chain_life, 1.0 - smoothstep(1.2, 1.8, a))
		else:
			_chain_life = move_toward(_chain_life, 0.0, dt / 0.6)
	# Brightness by depth, never by node visibility: it condenses out of the navy as the blue drains away.
	_set_gain(_chain_life * smoothstep(165.0, 200.0, G.depth))


func _set_gain(g: float) -> void:
	_chain.visible = g > 0.0
	if absf(g - _gain) < 0.002 and not (g == 0.0 and _gain != 0.0):
		return
	_gain = g
	_chain_mat.set_shader_parameter("gain", g)
