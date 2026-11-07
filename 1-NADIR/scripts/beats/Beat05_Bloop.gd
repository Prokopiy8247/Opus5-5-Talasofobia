extends Node3D
## Beat 5 — The Bloop (5:40-7:20, 960-1260 m). A low groan; the snow starts streaming sideways, drawn toward
## something. The diver is carried along a flank too big to measure, past the eye, past fangs like trees, across
## the front of the open maw (snow pouring into the black throat), then under the jaw as the animal moves on,
## its belly passing overhead and its flukes sweeping away into the black. Never seen whole, never touching.
##
## The choreography is written in the animal's body frame (metres, 10x model, +X forward, +Z = the side facing
## the diver): KEYS give where the diver is relative to the animal over the encounter clock. The animal is placed
## each frame from the diver's path point, so the relative geometry holds whatever the descent speed.
##
## No pops: the animal is switched on far outside the 82 m torch range (nearest skin 113 m), its light ramps in
## with `presence`, and it is first lit by the torch at tau ~7 when the flukes reach the edge of the range. It
## leaves the same way, and is filmed leaving: the gaze rides the near fluke lobe to 1345 m while the animal glides
## away (the lit fluke recedes from ~33 m to the edge of the light over ~12 s), then it is 280 m away and black long
## before it is switched off. A cold bioluminescent shear wake (fins, flukes, tail stock) traces it in the dark
## beyond the beam on the way in and lingers behind it on the way out.

const TRIGGER_DEPTH := 960.0
## Diver position in the body frame (m) over tau (s). Interpolated with a time-parameterised cubic Hermite.
## Checked offline every 0.25 s against the real mesh (x10; head turn, gulp, fin stroke and 8 tail-wave phases
## applied): nearest skin >= 31 m from the eye (31.0 at tau 72, 32.3 at the fluke pass), the descent line >= 10.7 m
## from the body (above and below the diver), peak relative acceleration 4.6 m/s^2, gape centre 48-57 m during M4.
## The exit glides at 7-10 m/s (was 14-21) and sinks to the diver's level, so the ±21 m fluke stroke cannot carry
## the lobe out of the light: it is lit at every wave phase from tau 108 to 117, peaks at ~107 and is gone at ~120.
const KEYS := [
	[0.0, Vector3(-230.0, 13.0, 120.0)],   # beyond the light
	[16.0, Vector3(-95.0, 5.0, 98.0)],     # the flukes have passed at the edge of the beam, the flank comes
	[40.0, Vector3(45.0, 0.0, 94.0)],
	[48.0, Vector3(92.0, -4.0, 88.0)],     # the eye
	[57.0, Vector3(134.0, -14.0, 90.0)],   # wide of the snout while the head turns toward the diver
	[66.0, Vector3(172.0, -26.0, 30.0)],   # M4: in front of the open maw
	[73.0, Vector3(167.0, -31.0, 11.0)],
	[80.0, Vector3(168.0, -58.0, 8.0)],
	[87.0, Vector3(122.0, -70.0, 78.0)],   # under and beside the jaw: the line stays clear of the body
	[95.0, Vector3(28.0, -66.0, 80.0)],    # the pectoral fin sweeps ~35 m overhead
	[103.0, Vector3(-82.0, -60.0, 76.0)],
	[111.0, Vector3(-170.0, -62.0, 56.0)],  # the flukes sweep overhead >= 32 m away at any wave phase
	[120.0, Vector3(-232.0, -36.0, 40.0)],  # ...and glide away, sinking to the diver's level, the gaze on them
	[136.0, Vector3(-430.0, -24.0, -8.0)],
]
const FLUKE_BODY := Vector3(-145.0, -12.0, 40.0)   # body-frame point where the flukes first meet the light
const END_TAU := 140.0
const PRESENCE_IN := Vector2(0.0, 7.0)
const PRESENCE_OUT := Vector2(110.0, 121.0)   # the filmed exit sinks into the dark over ~11 s, before the torch range cuts it
const CUE_END_DEPTH := 1345.0            # paired with Beat06's first cues (1345 / 1360 m)
const WAKE_TAU := Vector2(0.0, 125.0)    # the shear wake is shed while the animal swims through the water
## Wake emitters: fluke tips, pectoral fin tips, tail stock (both sides) and their base weights.
const WAKE_W := [1.0, 1.0, 0.6, 0.6, 0.2, 0.2, 0.2, 0.2]
## Body radius (m) by body-frame x, measured sections: drives the strength of the wake.
const RADII := [[-150.0, 16.0], [-100.0, 20.0], [-50.0, 30.0], [0.0, 48.0], [50.0, 46.0], [100.0, 37.0], [150.0, 25.0]]
const GULP := Vector2(81.0, 84.5)        # the maw closes after feeding
const THUMP_PITCH := 0.55

var depth_range := Vector2(930.0, 1320.0)
var bloop: Node3D
var _stream: GPUParticles3D
var _stream_draw: ShaderMaterial
var _stream_proc: ShaderMaterial
var _stream_gain := 75.0
var _wake: GPUParticles3D
var _wake_proc: ShaderMaterial
var _wake_draw: ShaderMaterial
var _turb := 0.0
var _thump: AudioStreamPlayer3D
var _thump_t := -1.0
var _s_trig := 0.0
var _tau := -1.0
var _groan1 := false
var _groan2 := false
var _gulped := false
var _wave_origin := Vector3.ZERO
var _wave_d0 := 0.0
var _wave_state := 0     # 0 not started, 1 running, 2 done
var _pushing := false
var _ended := false


func build(parent: Node3D) -> void:
	name = "Beat05_Bloop"
	parent.add_child(self)
	bloop = (load("res://scenes/Bloop.tscn") as PackedScene).instantiate()
	add_child(bloop)
	bloop.visible = false
	_no_shadows(bloop)
	var m: ShaderMaterial = bloop.shader_material() if bloop.has_method("shader_material") else null
	if m:
		m.set_shader_parameter("throat_dark", 0.8)
		m.set_shader_parameter("light_gain", 5.0)
		m.set_shader_parameter("normal_strength", 1.5)   # relief survives the coaxial torch
		_skin_detail(m)
	_build_stream()
	_build_wake()
	_build_thump()
	_s_trig = G.path.s_at_depth(TRIGGER_DEPTH)
	# the exit is filmed to 1345 m; Beat06 hands over from there (cue_at picks the largest s0)
	G.path.add_cue(_s_trig, G.path.s_at_depth(CUE_END_DEPTH), _gaze, 2.4)


## Metre-scale hide for bloop.gdshader: cellular bumps (normal map) and a value noise for speckles and scars.
## Generated in the background at load; the encounter is minutes away.
func _skin_detail(m: ShaderMaterial) -> void:
	var cn := FastNoiseLite.new()
	cn.noise_type = FastNoiseLite.TYPE_CELLULAR
	cn.frequency = 0.06
	cn.fractal_type = FastNoiseLite.FRACTAL_FBM
	cn.fractal_octaves = 3
	cn.seed = 5
	var nrm := NoiseTexture2D.new()
	nrm.width = 1024
	nrm.height = 1024
	nrm.seamless = true
	nrm.as_normal_map = true
	nrm.bump_strength = 8.0
	nrm.noise = cn
	var vn := FastNoiseLite.new()
	vn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	vn.frequency = 0.03
	vn.fractal_type = FastNoiseLite.FRACTAL_FBM
	vn.fractal_octaves = 3
	vn.seed = 11
	var val := NoiseTexture2D.new()
	val.width = 512
	val.height = 512
	val.seamless = true
	val.normalize = true
	val.noise = vn
	m.set_shader_parameter("detail_nrm", nrm)
	m.set_shader_parameter("detail_val", val)
	m.set_shader_parameter("detail_amp", 0.35)


func _no_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_no_shadows(c)


func _build_stream() -> void:
	_stream = GPUParticles3D.new()
	_stream.amount = 2600
	_stream.lifetime = 3600.0
	_stream.explosiveness = 1.0
	_stream.local_coords = true
	_stream_proc = ShaderMaterial.new()
	_stream_proc.shader = load("res://shaders/maw_stream.gdshader")
	_stream.process_material = _stream_proc
	var quad := QuadMesh.new()
	_stream_draw = ShaderMaterial.new()
	_stream_draw.shader = load("res://shaders/snow_draw.gdshader")
	# With the shared physical snow law (82 m range window + water extinction) a much lower gain gives the same
	# brightness at 30 m, and the throat swallows the snow into darkness. The old law has no range: keep 75.
	var phys := false
	for u in _stream_draw.shader.get_shader_uniform_list():
		if String(u.get("name", "")) == "sigma":
			phys = true
	_stream_gain = 12.0 if phys else 75.0
	_stream_draw.set_shader_parameter("gain", _stream_gain)
	_stream_draw.set_shader_parameter("size_mul", 1.0)
	_stream_draw.set_shader_parameter("fade_near", 400.0)
	_stream_draw.set_shader_parameter("fade_far", 500.0)
	quad.material = _stream_draw
	_stream.draw_pass_1 = quad
	# covers the volume in front of the head turned up to 20 deg either way
	_stream.visibility_aabb = AABB(Vector3(20, -110, -160), Vector3(270, 210, 320))
	_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bloop.add_child(_stream)


## The shear wake: world-space flecks shed by the fins, flukes and tail stock (shaders/bloop_wake_*). Always
## emitting so both pipelines are ready at load; with all weights 0 every emission is discarded.
func _build_wake() -> void:
	_wake = GPUParticles3D.new()
	_wake.name = "ShearWake"
	_wake.amount = 1600
	_wake.lifetime = 7.0
	_wake.explosiveness = 0.0
	_wake.randomness = 0.0
	_wake.local_coords = false
	_wake.fixed_fps = 0
	_wake.interpolate = false
	_wake_proc = ShaderMaterial.new()
	_wake_proc.shader = load("res://shaders/bloop_wake_process.gdshader")
	_wake_proc.set_shader_parameter("em", PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
		Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]))
	_wake_proc.set_shader_parameter("em_w", PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
	var wsum := 0.0
	for x in WAKE_W:
		wsum += x
	_wake_proc.set_shader_parameter("w_max", wsum)
	_wake.process_material = _wake_proc
	var quad := QuadMesh.new()
	_wake_draw = ShaderMaterial.new()
	_wake_draw.shader = load("res://shaders/bloop_wake_draw.gdshader")
	Config.apply_torch_profile(_wake_draw)
	_wake_draw.set_shader_parameter("range", Config.TORCH_RANGE)
	quad.material = _wake_draw
	_wake.draw_pass_1 = quad
	# the node rides the camera; the particles stay where they were shed (world space)
	_wake.visibility_aabb = AABB(Vector3(-320, -320, -320), Vector3(640, 640, 640))
	_wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wake.emitting = true
	add_child(_wake)


## Wake emitters follow the body (tail wave, fin stroke) every frame; the shed rate follows how fast the body
## shears the water (|v_rel|, with a floor: the flukes beat even when the animal glides).
func _wake_update(tau: float, v_rel: Vector3) -> void:
	_wake.global_position = G.camera.global_position
	var sp := clampf(v_rel.length() / 12.0, 0.25, 1.0) if (tau >= WAKE_TAU.x and tau < WAKE_TAU.y) else 0.0
	var pts := PackedVector3Array([
		bloop.fluke_tip_world_position(1.0), bloop.fluke_tip_world_position(-1.0),
		bloop.fin_tip_world_position(1.0), bloop.fin_tip_world_position(-1.0),
		bloop.flank_world_position(0.86), bloop.flank_far_world_position(0.86),
		bloop.flank_world_position(0.94), bloop.flank_far_world_position(0.94)])
	var w := PackedFloat32Array()
	w.resize(8)
	for i in 8:
		w[i] = WAKE_W[i] * sp
	_wake_proc.set_shader_parameter("em", pts)
	_wake_proc.set_shader_parameter("em_w", w)
	_wake_proc.set_shader_parameter("drift", G.flow)
	_wake_draw.set_shader_parameter("scale", smoothstep(0.0, 4.0, tau) * (1.0 - smoothstep(118.0, 130.0, tau)))
	if G.env:
		_wake_draw.set_shader_parameter("sigma", G.env.fog_density)


## The gulp's thump: the first groan pitched down, cut short.
func _build_thump() -> void:
	_thump = AudioStreamPlayer3D.new()
	_thump.stream = load("res://assets/audio/bloop_groan_1.wav")
	_thump.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_thump.unit_size = 260.0
	_thump.max_db = 6.0
	_thump.max_distance = 0.0
	_thump.panning_strength = 0.8
	_thump.attenuation_filter_db = 0.0
	_thump.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	_thump.pitch_scale = THUMP_PITCH
	add_child(_thump)


# ------------------------------------------------------------------ encounter
func _process(delta: float) -> void:
	if G.player == null:
		return
	if not G.running:
		# warm-up: draw the animal and the maw stream once in front of the camera so their pipelines are ready
		if G.camera:
			bloop.visible = true
			var fwd := -G.camera.global_basis.z
			bloop.global_transform = Transform3D(Basis(), G.camera.global_position + fwd * 160.0 - Vector3(124, 0, 0))
		return
	if _tau < 0.0:
		bloop.visible = false
		if G.player.s < _s_trig:
			return
		_tau = maxf(_design_tau(), 0.0)
	else:
		# The encounter clock runs in real time, but never falls behind the diver's progress on the design pace:
		# at the cinematic (Shift) speed the choreography plays over the same depths it was authored for.
		_tau = maxf(_tau + delta, _design_tau())
	var tau := _tau
	var active := tau < END_TAU
	bloop.visible = active
	# While it is out there the beat must not be culled by depth (the diver may swim back up): no pop.
	depth_range = Vector2(-1.0e9, 1.0e9) if active else Vector2(930.0, 1320.0)
	if not active:
		_end_effects()
		return
	# place the animal from the diver's path point and the body-frame key
	var pb := _key(tau)
	var yaw := deg_to_rad(8.0) * smoothstep(80.0, 120.0, tau) + deg_to_rad(2.0) * sin(tau * 0.05)
	var bb := Basis(Vector3.UP, yaw)
	var anchor := G.path.pos_at(G.player.s)
	bloop.global_transform = Transform3D(bb, anchor - bb * pb)
	bloop.head_target = G.camera.global_position if tau > 44.0 and tau < 82.0 else null
	var presence := smoothstep(PRESENCE_IN.x, PRESENCE_IN.y, tau) * (1.0 - smoothstep(PRESENCE_OUT.x, PRESENCE_OUT.y, tau))
	bloop.presence = presence
	# eyeshine while the eye faces the diver, with one slow blink (a membrane sweeping over the tapetum)
	var blink := 1.0 - 0.9 * smoothstep(46.85, 46.95, tau) * (1.0 - smoothstep(47.1, 47.2, tau))
	bloop.eyeshine = smoothstep(38.0, 44.0, tau) * (1.0 - smoothstep(74.0, 82.0, tau)) * blink
	bloop.jaw_extra = -deg_to_rad(7.0) * smoothstep(GULP.x, GULP.y, tau) * (1.0 - smoothstep(98.0, 112.0, tau))
	_spark_wave(tau)
	var v_rel := _current(tau, bb, pb, presence, delta)
	_wake_update(tau, v_rel)
	_maw_stream(tau)
	_sound(tau, delta)


## The current: snow drifts toward the head from tau 2, pours into the maw, is pushed back out by the gulp,
## and the passing body drags the water (and the diver) with it; the snow boils into slow eddies where the body
## has just passed and after the gulp (guarded hook, eased). Returns the body's velocity relative to the diver.
func _current(tau: float, bb: Basis, pb: Vector3, presence: float, delta: float) -> Vector3:
	var fwd := bb.x
	var to_throat: Vector3 = (bloop.throat_world_position() - G.camera.global_position).normalized()
	var w_drift := smoothstep(2.0, 28.0, tau) * (1.0 - smoothstep(56.0, 64.0, tau))
	var w_in := smoothstep(56.0, 64.0, tau) * (1.0 - smoothstep(GULP.x - 0.5, GULP.x + 1.0, tau))
	var w_out := smoothstep(GULP.x, GULP.x + 0.6, tau) * (1.0 - smoothstep(GULP.x + 1.3, GULP.x + 2.5, tau))
	var flow := fwd * (1.3 * w_drift) + (to_throat * 2.4 + fwd * 0.4) * w_in - to_throat * (1.8 * w_out)
	# wake: relative velocity of the body, weighted by how close the diver is to its surface
	var v_rel: Vector3 = -(bb * (_key(tau + 0.05) - _key(tau - 0.05)) / 0.1)
	var dn := maxf(Vector2(pb.y, pb.z).length() - _radius(pb.x), 0.0)
	var w := clampf(v_rel.length() / 12.0, 0.0, 1.0) * exp(-dn / 45.0) * presence
	flow += v_rel * (0.3 * w)
	G.flow_target = flow
	if "cam_push" in G:
		G.set("cam_push", v_rel.normalized() * (2.5 * w))
		_pushing = true
	var turb := clampf(v_rel.length() / 14.0, 0.0, 1.0) * exp(-dn / 35.0) \
		+ 0.8 * smoothstep(GULP.x, GULP.x + 0.5, tau) * (1.0 - smoothstep(GULP.x + 2.0, GULP.x + 7.0, tau))
	_turb = lerpf(_turb, turb * presence, 1.0 - exp(-delta / 2.5))
	var sn = G.get("snow")
	if sn and sn.has_method("set_turbulence"):
		sn.set_turbulence(_turb)
	return v_rel


func _radius(x: float) -> float:
	if x <= RADII[0][0]:
		return RADII[0][1]
	for i in range(1, RADII.size()):
		if x <= RADII[i][0]:
			var a: Array = RADII[i - 1]
			var b: Array = RADII[i]
			return lerpf(a[1], b[1], (x - a[0]) / (b[0] - a[0]))
	return RADII[RADII.size() - 1][1]


## A displacement front from the animal, still out in the dark, sweeps through the snow toward and past the
## diver (cold sparks, drawn by the shared marine snow) before the flukes reach the light. Guarded hook.
func _spark_wave(tau: float) -> void:
	var sn = G.get("snow")
	if sn == null or not sn.has_method("set_wave") or _wave_state == 2:
		return
	if _wave_state == 0:
		_wave_origin = bloop.tail_world_position()
		_wave_d0 = _wave_origin.distance_to(G.camera.global_position)
		_wave_state = 1
	if tau < 10.0:
		var amp := smoothstep(0.0, 1.5, tau) * (1.0 - smoothstep(7.0, 9.5, tau))
		sn.set_wave(_wave_origin, maxf(_wave_d0 - 45.0 + 9.0 * tau, 0.0), amp)   # crosses the diver at tau ~5
	else:
		sn.set_wave(_wave_origin, 0.0, 0.0)
		_wave_state = 2


func _maw_stream(tau: float) -> void:
	var feed := smoothstep(22.0, 50.0, tau)
	var pull := feed * (1.0 - smoothstep(GULP.x, GULP.x + 1.5, tau))   # the current stops when the maw closes
	_stream_proc.set_shader_parameter("pull", maxf(pull, 0.05))
	var op := feed * (1.0 - smoothstep(GULP.x + 1.0, GULP.x + 11.0, tau))  # the last motes settle and disperse
	_stream_draw.set_shader_parameter("opacity", op)
	_stream.visible = op > 0.01
	if not _stream.visible:
		return
	var ha: Vector2 = bloop.head_angles()
	_stream_proc.set_shader_parameter("head_yaw", ha.x)
	_stream_proc.set_shader_parameter("head_pitch", ha.y)
	_stream_proc.set_shader_parameter("cam_local", bloop.to_local(G.camera.global_position))
	# shared snow law inputs (no-ops on the old snow shader)
	if G.env:
		_stream_draw.set_shader_parameter("sigma", G.env.fog_density)
	# the one (eye-adapted) water colour: G.env.fog_light_color
	var wc: Color = G.env.fog_light_color if G.env else Palette.water_at(G.depth)
	var wl := wc.srgb_to_linear()
	_stream_draw.set_shader_parameter("water_lin", Vector3(wl.r, wl.g, wl.b))


## Sound: the groan as the encounter starts (the animal still unseen), the rush while the maw feeds, a thump
## when it closes, a second groan as the tail leaves.
func _sound(tau: float, delta: float) -> void:
	if G.audio:
		if not _groan1 and tau >= 0.5 and tau < 30.0:
			_groan1 = true
			G.audio.bloop_groan(1, bloop.mouth_world_position())
		if not _groan2 and tau >= 96.0 and tau < 125.0:
			_groan2 = true
			G.audio.bloop_groan(2, bloop.tail_world_position())
		G.audio.set_bloop_position(bloop.tail_world_position() if _groan2 else bloop.mouth_world_position())
		var rush := smoothstep(20.0, 64.0, tau) * (1.0 - smoothstep(GULP.x, GULP.x + 0.5, tau))
		G.audio.set_bloop_rush(rush)
	if not _gulped and tau >= GULP.x + 0.4 and tau < GULP.x + 10.0:
		_gulped = true
		if AudioServer.get_bus_index(&"SFX") >= 0:
			_thump.bus = &"SFX"
		_thump.global_position = bloop.mouth_world_position()
		_thump.volume_db = -1.0
		_thump.play()
		_thump_t = 0.0
		# the pressure pulse reaches the diver: the torch contact jolts
		if G.player and G.player.has_method("torch_stutter"):
			G.player.torch_stutter(0.35)
	if _thump_t >= 0.0:
		_thump_t += delta
		_thump.global_position = bloop.mouth_world_position()
		var env := 1.0 - smoothstep(0.8, 4.5, _thump_t)
		_thump.volume_db = -1.0 + linear_to_db(maxf(env, 0.0001))
		if env <= 0.0:
			_thump.stop()
			_thump_t = -1.0


func _end_effects() -> void:
	if _ended:
		return
	_ended = true
	G.flow_target = Vector3.ZERO
	if _pushing:
		G.set("cam_push", Vector3.ZERO)
		_pushing = false
	if _thump_t >= 0.0:
		_thump.stop()
		_thump_t = -1.0
	# the wake has long faded (scale 0 from tau 130); stop shedding
	_wake_proc.set_shader_parameter("em_w", PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
	_wake_draw.set_shader_parameter("scale", 0.0)
	_turb = 0.0
	var sn = G.get("snow")
	if sn and sn.has_method("set_turbulence"):
		sn.set_turbulence(0.0)


## Diver position in the body frame at tau: cubic Hermite with tangents from the neighbouring keys divided by
## their real time span (m/s), zero at both ends, so the speed is continuous through every key.
## Encounter time the design pace would have reached at the diver's current path point.
func _design_tau() -> float:
	return G.path.design_time_at(G.player.s) - G.path.design_time_at(_s_trig)


func _key(t: float) -> Vector3:
	var n := KEYS.size()
	if t <= KEYS[0][0]:
		return KEYS[0][1]
	if t >= KEYS[n - 1][0]:
		return KEYS[n - 1][1]
	var i := 0
	while i < n - 2 and t > KEYS[i + 1][0]:
		i += 1
	var t0: float = KEYS[i][0]
	var h: float = KEYS[i + 1][0] - t0
	var f := (t - t0) / h
	var f2 := f * f
	var f3 := f2 * f
	var p1: Vector3 = KEYS[i][1]
	var p2: Vector3 = KEYS[i + 1][1]
	return (2.0 * f3 - 3.0 * f2 + 1.0) * p1 + (f3 - 2.0 * f2 + f) * h * _tan(i) \
		+ (-2.0 * f3 + 3.0 * f2) * p2 + (f3 - f2) * h * _tan(i + 1)


func _tan(j: int) -> Vector3:
	if j <= 0 or j >= KEYS.size() - 1:
		return Vector3.ZERO
	return ((KEYS[j + 1][1] as Vector3) - (KEYS[j - 1][1] as Vector3)) / (KEYS[j + 1][0] - KEYS[j - 1][0])


## Body-frame point (metres, 10x) -> world.
func _bw(p: Vector3) -> Vector3:
	return bloop.global_transform * p


## Autowalk gaze during the encounter.
func _gaze() -> Vector3:
	var cam := G.camera.global_position
	if _tau < 0.0 or _tau > END_TAU:
		return cam + PathDef.cue_dir(Vector2(40.0, -35.0), Vector3.ZERO) * 20.0
	var t := _tau
	var pb := _key(t)
	if t < 17.0:
		# into the dark where the animal is: the flukes reach the edge of the beam (tau 8-16), then on to the flank
		return _bw(FLUKE_BODY.lerp(Vector3(pb.x + 34.0, pb.y - 4.0, 26.0), smoothstep(10.0, 17.0, t)))
	if t < 23.0:
		return _bw(Vector3(pb.x + 34.0, pb.y - 4.0, 26.0))      # skin appears at the edge of the beam
	if t < 40.0:
		return _bw(Vector3(pb.x + 12.0, pb.y * 0.4 + 4.0, 30.0)) # the flank fills the beam
	if t < 46.5:
		return bloop.eye_world_position()                        # the dull eye catches the beam, and shines
	if t < 52.0:
		return bloop.fang_world_position(3)                      # one fang the size of a tree
	if t < 59.0:
		return bloop.fang_world_position(0)                      # then rows of them
	if t < 87.0:
		# M4: into the maw, both lips and the fangs in frame, the lower teeth in the hot core, the snow pouring
		# over them into the black throat; held through the gulp (81-84.5) so the closing jaw is filmed
		return bloop.mouth_world_position().lerp(bloop.throat_world_position(), 0.15)
	if t < 92.0:
		# the jaw closes and slides over: hand over from the maw to the underside
		return bloop.mouth_world_position().lerp(_bw(Vector3(pb.x - 18.0, -38.0, 36.0)), smoothstep(87.0, 92.0, t))
	if t < 100.0:
		return _bw(Vector3(pb.x - 30.0, -34.0, 40.0))           # the belly and the fin overhead
	# the flukes sweep overhead and glide away into the black: ride the near lobe (it follows the tail wave)
	return bloop.flank_world_position(lerpf(0.9, 1.0, smoothstep(100.0, 104.0, t)))
