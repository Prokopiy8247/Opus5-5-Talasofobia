class_name Bubbles
extends MultiMeshInstance3D
## The diver's exhaled air: a burst of bubbles from the regulator's exhaust on every exhale, rising
## past the mask and wobbling. Simulated on the CPU (a few dozen), drawn as refracting discs
## (shaders/bubble.gdshader). Bubbles leave with the diver's own motion and then lag behind.

const MAX := 64
const LIFE := 3.2
const DRAG := 1.6                 # 1/s: how fast a bubble forgets the diver's motion

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _rad := PackedFloat32Array()
var _age := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _pending: Array = []       # [delay, side, radius]
var _rng := RandomNumberGenerator.new()
var _next := 0
var _last_cam := Vector3.ZERO
var _cam_vel := Vector3.ZERO
var _has_last := false


func _init() -> void:
	name = "Bubbles"
	_rng.seed = 404
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = MAX
	multimesh = mm
	material_override = Mats.make("bubble")
	material_override.render_priority = 20         # always over the snow and the shafts
	sorting_use_aabb_center = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-50000, -50000, -50000), Vector3(100000, 100000, 100000))
	_pos.resize(MAX)
	_vel.resize(MAX)
	_rad.resize(MAX)
	_age.resize(MAX)
	_seed.resize(MAX)
	for i in MAX:
		_age[i] = LIFE
		_hide(i)


## One exhale: about a second of bubbles from the two exhaust ports beside the mouth.
func exhale(strength := 1.0) -> void:
	var n := int(round(_rng.randi_range(6, 10) * clampf(strength, 0.4, 2.0)))
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	for k in n:
		# a few big ones first in a tight cluster, then a trail of small ones; mostly from one port
		var big := k < 2
		var r := _rng.randf_range(0.02, 0.034) if big else _rng.randf_range(0.004, 0.013)
		var sd := side if _rng.randf() < 0.75 else -side
		_pending.append([(0.04 * float(k) if big else _rng.randf_range(0.1, 0.8)), sd, r])


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or dt <= 0.0:
		return
	var cp := cam.global_position
	if _has_last:
		_cam_vel = _cam_vel.lerp((cp - _last_cam) / dt, 1.0 - exp(-dt * 6.0))
	_last_cam = cp
	_has_last = true
	var j := 0
	while j < _pending.size():
		_pending[j][0] -= dt
		if _pending[j][0] <= 0.0:
			_spawn(cam, _pending[j][1], _pending[j][2])
			_pending.remove_at(j)
		else:
			j += 1
	var mm := multimesh
	for i in MAX:
		if _age[i] >= LIFE:
			continue
		_age[i] += dt
		if _age[i] >= LIFE:
			_hide(i)
			continue
		var r := _rad[i]
		var s := _seed[i]
		# terminal rise speed grows with size; small ones zig-zag, big ones rock
		var rise := 0.25 + r * 9.0
		_vel[i] = _vel[i].lerp(Vector3(0, rise, 0), 1.0 - exp(-dt * DRAG))
		_pos[i] += _vel[i] * dt
		var t := _age[i]
		var wob := Vector3(sin(t * (7.0 + s * 5.0) + s * 20.0), 0.0, cos(t * (6.0 + s * 4.0) + s * 11.0)) * (0.01 + r * 0.5)
		var p := _pos[i] + wob
		var a := smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(LIFE - 0.8, LIFE, t))
		a *= smoothstep(0.12, 0.28, p.distance_to(cp))   # never a blob over the lens
		var sq := clampf((r - 0.012) / 0.02, 0.0, 1.0) * (0.6 + 0.4 * sin(t * 9.0 + s * 7.0))
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * r), p))
		mm.set_instance_custom_data(i, Color(s, a, sq, 0))


func _spawn(cam: Camera3D, side: float, r: float) -> void:
	var b := cam.global_basis
	var i := _next
	_next = (_next + 1) % MAX
	# the regulator's exhaust ports sit beside the mouth: bubbles stream up past the mask's edges
	_pos[i] = cam.global_position + b * Vector3(side * (0.14 + _rng.randf_range(-0.02, 0.03)), -0.1, -0.02)
	_vel[i] = _cam_vel + b * Vector3(side * _rng.randf_range(0.25, 0.45), 0.25, _rng.randf_range(-0.05, 0.05))
	_rad[i] = r
	_age[i] = 0.0
	_seed[i] = _rng.randf()


func _hide(i: int) -> void:
	multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -1e5, 0)))
	multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))
