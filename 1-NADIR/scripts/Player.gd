extends Node3D
## The diver: rides the path (Curve3D) with a small drift inside the safety tube, free mouse look,
## cinematic autowalk with critically damped gaze cues, breathing sway, and the hand-held torch.

const TORCH_HAND := Vector3(0.30, -0.26, 0.0)   # torch in the right hand, below and beside the mask
const TORCH_AIM := 15.0                          # the beam crosses the line of sight this far ahead
const TORCH_LAG := 0.16                          # s, hand-held lag of the aim
# click-on: [seconds, level] steps, then a short ramp to full (a contact catching, not a strobe)
const CLICK := [[0.06, 0.8], [0.14, 0.04], [0.05, 0.5], [0.30, 0.04]]
const CLICK_RAMP := 0.25

var s := 0.0
var speed := 0.0
var yaw := 0.0            # radians, 0 looks toward -Z, + turns left
var pitch := 0.0          # radians, + looks up
var yaw_v := 0.0
var pitch_v := 0.0
var torch_level := 0.0    # 0..1 switch level (click-on, steady)
var torch_out := 0.0      # what reaches the light and the shaders: level x scale x stutter x dying
var torch_scale := 1.0    # hook: beats scale the torch (light, haze, snow) every frame
var _torch_target := 0.0
var _click_t := -1.0      # time into the click-on pattern (< 0 idle)
var _stutter_t := -1.0
var _stutter_len := 0.5
var _off_t := -1.0
var _off_len := 3.0
var _push := Vector3.ZERO
var _locked_auto := false
var camera: Camera3D
var torch: SpotLight3D
var _lobes: Array[SpotLight3D] = []
var _torch_pivot: Node3D
var _bubbles: Node


func build() -> void:
	name = "Player"
	camera = Camera3D.new()
	camera.fov = Config.FOV
	camera.near = Config.NEAR
	camera.far = Config.FAR
	add_child(camera)
	camera.current = true
	_torch_pivot = Node3D.new()
	add_child(_torch_pivot)
	# Concentric lobes (Config.TORCH_LOBES): a hot core that rolls off smoothly into a faint spill, no hard
	# disc. The first lobe is G.torch (position and direction for the shaders); all share range and decay.
	for lobe in Config.TORCH_LOBES:
		var l := SpotLight3D.new()
		l.position = TORCH_HAND
		l.light_color = Palette.TORCH
		l.spot_angle = lobe[0]
		l.spot_angle_attenuation = lobe[1]
		l.spot_range = Config.TORCH_RANGE
		l.spot_attenuation = 0.55
		l.light_energy = 0.0
		l.light_specular = 0.7
		l.light_volumetric_fog_energy = 0.0   # the beam haze is drawn by BeamHaze
		l.shadow_enabled = false
		_torch_pivot.add_child(l)
		_lobes.append(l)
	torch = _lobes[0]
	preload("res://scripts/BeamHaze.gd").new().build(camera)
	preload("res://scripts/WaterLight.gd").new().build(camera)
	_bubbles = preload("res://scripts/Bubbles.gd").new()
	_bubbles.build(camera)
	G.player = self
	G.camera = camera
	G.torch = torch
	_locked_auto = G.args.has("autowalk") and G.args.has("quit-at-end")


func place(new_s: float) -> void:
	s = clampf(new_s, 0.0, G.path.length)
	speed = 0.0
	global_position = G.path.pos_at(s)
	_apply_camera(0.0)
	_aim_torch(1.0)


func look_at_angles(yaw_deg: float, pitch_deg: float) -> void:
	yaw = deg_to_rad(yaw_deg)
	pitch = deg_to_rad(pitch_deg)
	yaw_v = 0.0
	pitch_v = 0.0
	_apply_camera(0.0)
	_aim_torch(1.0)


func set_torch(v: float) -> void:
	torch_level = v
	_torch_target = v
	_click_t = -1.0
	_apply_torch()


func torch_click_on() -> void:
	_torch_target = 1.0
	_click_t = 0.0


## Hook (ship): the torch dips twice over `sec` seconds, to 0.15 and to 0.4 (a loose contact).
func torch_stutter(sec: float) -> void:
	_stutter_len = maxf(sec, 0.2)
	_stutter_t = 0.0


## Hook (floor): soft torch shadows from the two widest strong lobes (B6, below ~1490 m). The other lobes stay
## unshadowed, so ~41% of the light still fills the shadow side: nodules, the coil and the hatch dogs read as
## solid without black holes.
func set_torch_shadows(on: bool) -> void:
	for i in [0, 2]:
		var l: SpotLight3D = _lobes[i]
		l.shadow_enabled = on
		l.shadow_bias = 0.03
		l.shadow_normal_bias = 1.2
		l.shadow_blur = 2.0


## Hook (ending): the torch dies over `sec` seconds and stays off.
func torch_off_slow(sec := 3.0) -> void:
	_off_len = maxf(sec, 0.1)
	_off_t = 0.0


func on_autowalk_toggled() -> void:
	yaw_v = 0.0
	pitch_v = 0.0


func step(dt: float) -> void:
	# --- speed along the path
	var target := 0.0
	if G.ending:
		target = 0.0
	elif G.autowalk:
		target = G.path.auto_speed(s)
	else:
		var dir := Input.get_axis("move_back", "move_fwd")
		target = G.path.base_speed(s) * dir
		if dir < 0.0:
			target *= 0.6
		if Input.is_action_pressed("brisk"):
			target *= Config.BRISK_MULT
	var stop_at: float = G.path.length
	if G.args.has("end-at"):
		stop_at = minf(stop_at, G.path.s_at_time(float(G.args["end-at"])))
	speed = lerpf(speed, target, 1.0 - exp(-dt / 0.11))
	s = clampf(s + speed * dt, 0.0, stop_at)
	# --- position: path + slow drift inside the tube
	var tt := G.t
	# wander gently, biased away from the line so the camera never brushes it
	var away := -Vector3(Config.ROPE_OFFSET.x, 0.0, Config.ROPE_OFFSET.z).normalized() * 0.35
	var drift := away + Vector3(0.4 * sin(tt * 0.071 + 1.3) + 0.15 * sin(tt * 0.163 + 0.4), 0.0,
		0.4 * sin(tt * 0.059 + 2.1) + 0.15 * sin(tt * 0.137 + 5.0))
	drift = drift.limit_length(Config.TUBE_RADIUS)
	# --- push (creature wake, G.cam_push): smoothed, limited, never into the line
	_push = _push.lerp(G.cam_push.limit_length(2.5), 1.0 - exp(-dt / 1.2)).limit_length(2.5)
	var pos: Vector3 = G.path.pos_at(s) + drift + _push
	if _push.length_squared() > 1e-6:
		var off: Vector3 = pos - G.path.rope_at(s)
		off.y = 0.0
		var l := off.length()
		if l < 0.9:
			pos += (off / l if l > 0.001 else Vector3.LEFT) * (0.9 - l)
	global_position = pos
	# --- look
	if G.autowalk:
		_auto_look(dt)
	pitch = clampf(pitch, deg_to_rad(-88.0), deg_to_rad(88.0))
	_apply_camera(dt)
	# --- torch: hand-held lag, click-on, hooks
	_aim_torch(1.0 - exp(-dt / TORCH_LAG))
	if _click_t >= 0.0:
		_click_t += dt
		torch_level = _click_level(_click_t)
	else:
		torch_level = move_toward(torch_level, _torch_target, dt * 2.0)
	if _stutter_t >= 0.0:
		_stutter_t += dt
		if _stutter_t > _stutter_len:
			_stutter_t = -1.0
	if _off_t >= 0.0:
		_off_t += dt
	_apply_torch()
	var end_k := smoothstep(G.path.length - 28.0, G.path.length - 4.0, s)
	G.haze.set_gain(Config.HAZE_GAIN * lerpf(1.0, 0.3, end_k))
	_bubbles.step(dt)


## torch_out = switch level x torch_scale x stutter x dying; drives the lights and (via Main) g_torch.
func _apply_torch() -> void:
	var fx := 1.0
	if _stutter_t >= 0.0:
		var x := _stutter_t / _stutter_len
		if x > 0.10 and x < 0.30:
			fx = 0.15
		elif x > 0.55 and x < 0.72:
			fx = 0.4
	if _off_t >= 0.0:
		# a dying cell: sags, catches once, then fades out for good
		var x := clampf(_off_t / _off_len, 0.0, 1.0)
		var base := 1.0 - smoothstep(0.0, 1.0, x)
		if x > 0.16 and x < 0.22:
			base *= 0.25
		elif x > 0.40 and x < 0.43:
			base *= 0.1
		fx *= base
	torch_out = torch_level * torch_scale * fx
	for i in _lobes.size():
		_lobes[i].light_energy = Config.TORCH_ENERGY * torch_out * Config.TORCH_LOBES[i][2]


func _click_level(t: float) -> float:
	var acc := 0.0
	for st in CLICK:
		acc += st[0]
		if t < acc:
			return st[1]
	var k := (t - acc) / CLICK_RAMP
	if k >= 1.0:
		_click_t = -1.0
		return _torch_target
	return lerpf(0.04, _torch_target, smoothstep(0.0, 1.0, k))


## Aim the hand at a point on the line of sight; k = 1 snaps (teleports, sweeps). On fast turns the beam
## trails the view, so its cone shows in the haze.
func _aim_torch(k: float) -> void:
	var cb := camera.global_basis
	var aim := camera.global_position - cb.z * TORCH_AIM
	for i in (2 if k >= 1.0 else 1):
		var from := _torch_pivot.global_position + _torch_pivot.global_basis * TORCH_HAND
		var want := Basis.looking_at(aim - from, cb.y)
		if k >= 1.0:
			_torch_pivot.global_basis = want
		else:
			_torch_pivot.global_basis = _torch_pivot.global_basis.slerp(want, k).orthonormalized()


func _auto_look(dt: float) -> void:
	var cue: Dictionary = G.path.cue_at(s)
	var smooth := 3.0
	var dir := Vector3.ZERO
	if not cue.is_empty():
		dir = PathDef.cue_dir(cue.target, camera.global_position)
		# cue turn times were authored for the slower design pace: at the Shift-speed cinematic each cue window
		# passes sooner, so the camera turns proportionally quicker (capped, so it never snaps)
		smooth = cue.smooth / clampf(G.path.pace_ratio(s, speed), 1.0, 1.8)
	if dir == Vector3.ZERO:
		dir = PathDef.cue_dir(Vector2(-20.0 + 25.0 * sin(G.t * 0.05), -14.0), Vector3.ZERO)
	var ty := atan2(-dir.x, -dir.z)
	var tp := asin(clampf(dir.y, -0.999, 0.999))
	tp = clampf(tp, deg_to_rad(-86.0), deg_to_rad(86.0))
	var w := 2.4 / maxf(smooth, 0.3)
	var dy := wrapf(ty - yaw, -PI, PI)
	# Near-vertical gazes make yaw ill-defined: let yaw relax instead of spinning.
	var yaw_w := w * clampf(cos(tp) * 3.0, 0.15, 1.0)
	yaw_v += (yaw_w * yaw_w * dy - 2.0 * yaw_w * yaw_v) * dt
	pitch_v += (w * w * (tp - pitch) - 2.0 * w * pitch_v) * dt
	yaw += yaw_v * dt
	pitch += pitch_v * dt


func _apply_camera(_dt: float) -> void:
	var phase := 0.0
	if G.audio and G.audio.has_method("get_breath_phase"):
		phase = G.audio.get_breath_phase()
	else:
		phase = fmod(G.t / 4.5, 1.0)
	var depth_k := clampf(G.depth / 1500.0, 0.0, 1.0)
	var breath := sin(phase * TAU - 0.6)
	var sway_y := breath * lerpf(0.010, 0.016, depth_k)
	var sway_p := deg_to_rad(0.10) * breath
	var hand_y := 0.0
	var hand_p := 0.0
	if G.autowalk:
		hand_y = deg_to_rad(0.18) * (sin(G.t * 0.53) * 0.6 + sin(G.t * 1.31 + 1.0) * 0.4)
		hand_p = deg_to_rad(0.14) * (sin(G.t * 0.61 + 2.0) * 0.6 + sin(G.t * 1.13) * 0.4)
	camera.position = Vector3(0.0, sway_y, 0.0)
	camera.basis = Basis(Vector3.UP, yaw + hand_y) * Basis(Vector3.RIGHT, pitch + sway_p + hand_p)


func _unhandled_input(event: InputEvent) -> void:
	if not G.player or G.paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m: InputEventMouseMotion = event
		if G.autowalk:
			if _locked_auto or m.relative.length() < 2.0:
				return
			G.autowalk = false
		yaw -= m.relative.x * Config.MOUSE_SENS
		pitch -= m.relative.y * Config.MOUSE_SENS
	elif event is InputEventKey and event.pressed and not event.echo and G.autowalk and not _locked_auto:
		if event.is_action("move_fwd") or event.is_action("move_back") or event.is_action("brisk"):
			G.autowalk = false
