extends Node3D
## The Bloop prefab: places the creature on a Curve3D and drives the swim shader (shaders/bloop.gdshader).
## Mesh space is "model units" (30 long, head +X, belly -Y); the Model child is scaled by model_scale.
## Every *_world_position() includes model_scale and the current swim deformation (CPU replica of the shader).

const BODY_LEN := 30.0
const HEAD_X := 15.0
const NECK_X := 5.0
const HINGE := Vector2(7.6, -0.8)
const HEAD_PIVOT := Vector3(4.0, 0.0, 0.0)
const EYE := Vector3(8.08, 2.31, 4.06)
const MOUTH := Vector3(12.4, -1.8, 0.0)
const THROAT := Vector3(5.6, -0.25, 0.0)
const TAIL := Vector3(-14.5, -0.7, 0.0)
const FANGS := [Vector3(13.79, -0.10, 1.36), Vector3(13.36, 0.20, 1.90), Vector3(12.33, -3.47, 1.59), Vector3(10.48, -2.85, 1.84)]
const FANG_JAW := [0.0, 0.0, 1.0, 1.0]   # 0 = upper (skull), 1 = lower jaw
const FLUKE_TIP := Vector3(-14.65, -1.49, 4.33)   # fluke lobe tips (mirrored in z), measured on the mesh
const FIN_TIP := Vector3(1.49, -3.04, 6.77)       # pectoral fin tips (mirrored in z)
const FIN_ROOT := Vector3(0.0, -1.7, 4.3)         # fin paddling axis (shader fin_root)
const FLANK := [Vector3(13.90, 2.79, 2.37), Vector3(12.48, 3.06, 3.12), Vector3(11.05, 3.06, 3.24), Vector3(9.64, 2.96, 3.73),
	Vector3(8.21, 3.01, 4.46), Vector3(6.94, 1.19, 4.10), Vector3(5.42, 1.16, 4.43), Vector3(3.92, 0.00, 4.43),
	Vector3(2.64, 0.32, 4.37), Vector3(1.03, 0.46, 4.31), Vector3(-0.21, 0.13, 4.26), Vector3(-1.63, 0.12, 3.86),
	Vector3(-3.08, 0.50, 3.38), Vector3(-4.50, 0.81, 2.74), Vector3(-5.94, 1.52, 2.27), Vector3(-7.39, 1.48, 1.89),
	Vector3(-8.78, 1.47, 1.67), Vector3(-10.36, 1.89, 1.51), Vector3(-11.82, 1.10, 1.43), Vector3(-13.27, 0.18, 2.97),
	Vector3(-14.65, -1.51, 4.26)]

@export var model_scale := 10.0: set = set_model_scale
@export var swim_speed := 22.0               ## m/s; used for wave sync, and for travel when auto_advance
@export var auto_advance := false            ## true: progress += swim_speed * delta along the curve
@export_range(0.0, 0.12) var wave_amplitude := 0.055   ## tail-tip wave amplitude as a fraction of body length
@export var wave_period := 10.5              ## s; idle period, and clamp centre when synced to speed
@export var phase_speed_ratio := 1.3         ## wave phase speed / swim speed
@export var jaw_sway_deg := 4.0
@export var jaw_period := 14.0
@export var fin_amp_deg := 7.0
@export var head_turn_deg := 20.0            ## max head yaw toward head_target (pitch limit is half)
@export var head_turn_rate := 0.45           ## 1/s smoothing of the head turn
@export var head_sway_deg := 1.4             ## counter-sway against the body wave
@export var body_bend := 0.0                 ## manual yaw curvature (1/model unit) when auto_bend is off
@export var auto_bend := true
@export var material: ShaderMaterial

var curve: Curve3D                           ## world-space path; set progress to place the root on it
var progress := 0.0: set = set_progress      ## arc length (m) of the root (model centre) along curve
var head_target = null                       ## Vector3 world point or null
var jaw_extra := 0.0                         ## radians added to the jaw sway (- closes the gape: the gulp)
var presence := 1.0                          ## 0..1 scales all light on the skin (emerge from / sink into the dark)
var eyeshine := 0.0                          ## 0..1 retro-reflection of the torch from the eyes

var _model: Node3D
var _mi: MeshInstance3D
var _mat: ShaderMaterial
var _t := 0.0
var _phase := 0.0
var _omega := 0.0
var _jaw := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _hy := 0.0
var _hp := 0.0
var _bend := 0.0
var _bend_target := 0.0
var _last_progress := 0.0
var _speed_est := 0.0
var _moved_t := 99.0


func _ready() -> void:
	_model = get_node_or_null("Model")
	if _model == null:
		_model = (load("res://assets/creatures/Bloop.glb") as PackedScene).instantiate()
		_model.name = "Model"
		add_child(_model)
	_mi = _find_mesh(_model)
	_mat = (material if material else _default_material()).duplicate()
	if _mi:
		_mi.material_override = _mat
		_mi.extra_cull_margin = 10.0
	set_model_scale(model_scale)
	_omega = TAU / _period()
	_last_progress = progress
	set_progress(progress)
	_bend = _bend_target if auto_bend and curve else body_bend
	_apply_uniforms()


func _default_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/bloop.gdshader")
	m.set_shader_parameter("albedo_tex", load("res://assets/creatures/Bloop_albedo.png"))
	m.set_shader_parameter("normal_tex", load("res://assets/creatures/Bloop_normal.png"))
	m.set_shader_parameter("rough_tex", load("res://assets/creatures/Bloop_rough.png"))
	return m


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _find_mesh(c)
		if m:
			return m
	return null


func set_model_scale(v: float) -> void:
	model_scale = v
	if _model:
		_model.scale = Vector3.ONE * v


func set_progress(v: float) -> void:
	progress = v
	if curve == null or curve.point_count < 2 or not is_inside_tree():
		return
	var L := curve.get_baked_length()
	var s := clampf(v, 0.0, L)
	var pos := curve.sample_baked(s, true)
	var tg := _tangent(s, 2.0)
	var up := (Vector3.UP - tg * tg.dot(Vector3.UP))
	up = up.normalized() if up.length() > 0.01 else Vector3.BACK
	var zax := tg.cross(up).normalized()
	global_transform = Transform3D(Basis(tg, up, zax), pos)
	# signed curvature toward local +Z, sampled over a body-scale window -> shader bend (1/model unit)
	var h := clampf(BODY_LEN * model_scale * 0.15, 5.0, 60.0)
	var dt := _tangent(minf(s + h, L), 2.0) - _tangent(maxf(s - h, 0.0), 2.0)
	_bend_target = dt.dot(zax) / (2.0 * h) * model_scale


func _tangent(s: float, h: float) -> Vector3:
	var L := curve.get_baked_length()
	var d := curve.sample_baked(minf(s + h, L), true) - curve.sample_baked(maxf(s - h, 0.0), true)
	return d.normalized() if d.length() > 1e-4 else Vector3.RIGHT


func _period() -> float:
	var spd := _speed_est if _moved_t < 1.0 else swim_speed
	if spd < 0.5 or phase_speed_ratio <= 0.0:
		return wave_period
	return clampf(BODY_LEN * model_scale / (phase_speed_ratio * spd), wave_period * 0.6, wave_period * 1.8)


func _process(delta: float) -> void:
	_t += delta
	if auto_advance and curve:
		progress += swim_speed * delta
	var dp := absf(progress - _last_progress)
	_last_progress = progress
	if dp > 0.0 and not auto_advance:
		_moved_t = 0.0
		_speed_est = lerpf(_speed_est, dp / maxf(delta, 1e-4), 1.0 - exp(-delta * 2.0))
	else:
		_moved_t += delta
	_omega = lerpf(_omega, TAU / _period(), 1.0 - exp(-delta * 0.5))
	_phase = fposmod(_phase + _omega * delta, TAU)
	_jaw = deg_to_rad(jaw_sway_deg) * (0.85 * sin(TAU * _t / jaw_period) + 0.15 * sin(TAU * _t / (jaw_period * 0.43) + 1.3)) + jaw_extra
	var want_yaw := 0.0
	var want_pitch := 0.0
	if head_target is Vector3 and _model:
		var lp: Vector3 = _model.global_transform.affine_inverse() * (head_target as Vector3) - HEAD_PIVOT
		var lim := deg_to_rad(head_turn_deg)
		want_yaw = clampf(atan2(lp.z, maxf(lp.x, 0.1)), -lim, lim)
		want_pitch = clampf(atan2(lp.y, Vector2(lp.x, lp.z).length()), -lim * 0.5, lim * 0.5)
	var k := 1.0 - exp(-delta * head_turn_rate)
	_yaw = lerpf(_yaw, want_yaw, k)
	_pitch = lerpf(_pitch, want_pitch, k)
	_hp = _pitch - deg_to_rad(head_sway_deg) * sin(_phase - 0.6)
	_hy = _yaw + deg_to_rad(head_sway_deg * 0.6) * sin(TAU * _t / (wave_period * 1.7))
	var bt := _bend_target if (auto_bend and curve) else body_bend
	_bend = lerpf(_bend, bt, 1.0 - exp(-delta * 0.8))
	_apply_uniforms()


func _apply_uniforms() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("wave_phase", _phase)
	_mat.set_shader_parameter("wave_amp", wave_amplitude * BODY_LEN)
	_mat.set_shader_parameter("anim_time", fmod(_t, 3600.0))
	_mat.set_shader_parameter("jaw_angle", _jaw)
	_mat.set_shader_parameter("fin_amp", deg_to_rad(fin_amp_deg))
	_mat.set_shader_parameter("head_yaw", _hy)
	_mat.set_shader_parameter("head_pitch", _hp)
	_mat.set_shader_parameter("body_bend", _bend)
	_mat.set_shader_parameter("presence", presence)
	_mat.set_shader_parameter("eyeshine", eyeshine)


## Current head turn (yaw, pitch) in radians as the shader applies it, for effects that follow the head.
func head_angles() -> Vector2:
	return Vector2(_hy, _hp)


# ---- CPU replica of the shader deformation (jaw, head, wave, bend) for gaze/camera points
func _ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _deform(p: Vector3, jaw_w: float) -> Vector3:
	var x0 := p.x
	var mb := _ss(3.0, 6.5, x0)
	var d := Vector2(p.x, p.y) - HINGE
	d = d.rotated(-_jaw * jaw_w)
	p.x = HINGE.x + d.x; p.y = HINGE.y + d.y
	var h := p - HEAD_PIVOT
	var xy := Vector2(h.x, h.y).rotated(_hp * mb); h.x = xy.x; h.y = xy.y
	var xz := Vector2(h.x, h.z).rotated(_hy * mb); h.x = xz.x; h.z = xz.y
	p = HEAD_PIVOT + h
	var u := clampf((HEAD_X - x0) / BODY_LEN, 0.0, 1.0)
	var ph := _phase - TAU * u
	var tw := _ss(0.62, 1.0, u)
	var amp := wave_amplitude * BODY_LEN
	p.y += amp * ((1.0 - mb) * u * u * sin(ph) + 0.35 * tw * sin(ph - 1.1))
	var xb := minf(x0, NECK_X)
	p.z += _bend * (0.5 * xb * xb + NECK_X * maxf(x0 - NECK_X, 0.0))
	return p


func _world(p: Vector3, jaw_w := 0.0) -> Vector3:
	var m: Node3D = _model if _model else self
	return m.global_transform * _deform(p, jaw_w)


func eye_world_position() -> Vector3:
	return _world(EYE)


func mouth_world_position() -> Vector3:
	return _world(MOUTH, 0.5)


func fang_world_position(i: int) -> Vector3:
	i = clampi(i, 0, FANGS.size() - 1)
	return _world(FANGS[i], FANG_JAW[i])


func throat_world_position() -> Vector3:
	return _world(THROAT)


func tail_world_position() -> Vector3:
	return _world(TAIL)


func flank_world_position(u: float) -> Vector3:
	var f := clampf(u, 0.0, 1.0) * (FLANK.size() - 1)
	var i := mini(int(f), FLANK.size() - 2)
	return _world((FLANK[i] as Vector3).lerp(FLANK[i + 1], f - i))


## The same flank line on the far side (z mirrored), with the tail wave.
func flank_far_world_position(u: float) -> Vector3:
	var f := clampf(u, 0.0, 1.0) * (FLANK.size() - 1)
	var i := mini(int(f), FLANK.size() - 2)
	var p: Vector3 = (FLANK[i] as Vector3).lerp(FLANK[i + 1], f - i)
	return _world(Vector3(p.x, p.y, -p.z))


## Fluke lobe tip, side +1 (toward +Z, the diver's side) or -1, following the tail wave.
func fluke_tip_world_position(side: float) -> Vector3:
	return _world(Vector3(FLUKE_TIP.x, FLUKE_TIP.y, FLUKE_TIP.z * signf(side)))


## Pectoral fin tip, side +1 or -1, with the paddling stroke (same law as the shader).
func fin_tip_world_position(side: float) -> Vector3:
	var sd := 1.0 if side >= 0.0 else -1.0
	var p := Vector3(FIN_TIP.x, FIN_TIP.y, FIN_TIP.z * sd)
	var fa := deg_to_rad(fin_amp_deg) * sin(fmod(_t, 3600.0) * 0.9 + sd * 0.9 + p.x * 0.35)
	var q := Vector2((p.z - sd * FIN_ROOT.z) * sd, p.y - FIN_ROOT.y).rotated(fa)
	p.z = sd * q.x + sd * FIN_ROOT.z
	p.y = q.y + FIN_ROOT.y
	return _world(p)


func shader_material() -> ShaderMaterial:
	return _mat
