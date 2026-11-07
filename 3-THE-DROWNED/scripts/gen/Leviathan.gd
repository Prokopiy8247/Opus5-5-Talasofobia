class_name Leviathan
extends Node3D
## An ambiguous presence: once, while the diver looks across the submarine forest, a long dark shape
## slides behind the far rows at the edge of visibility. Never framed, never lit, never explained.
## Main calls start() once; the body swims along a straight line and then is gone.

const LENGTH := 170.0
const SPEED := 9.0
const FROM := Vector3(470.0, -468.0, -170.0)
const TO := Vector3(500.0, -485.0, -760.0)

var _t := -1.0
var _dur := 1.0
var _body: MeshInstance3D


func _init() -> void:
	name = "Leviathan"
	visible = false
	_body = MeshInstance3D.new()
	_body.mesh = _mesh()
	_body.material_override = Mats.make("leviathan", {"body_len": LENGTH})
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.extra_cull_margin = 60.0
	add_child(_body)
	_dur = FROM.distance_to(TO) / SPEED


## Spine along -Z (head at z = 0, tail at +LENGTH), radius profile thick behind the head, long taper.
static func _mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var rings := []
	var uu := PackedFloat32Array()
	var n := 48
	for i in n + 1:
		var t := float(i) / float(n)
		var r := 10.0 * sin(PI * pow(t, 0.55)) * (1.0 - 0.65 * t) + 0.3
		var ring := PackedVector3Array()
		for j in 12:
			var a := TAU * float(j) / 12.0
			ring.append(Vector3(cos(a) * r * 1.15, sin(a) * r * 0.8, t * LENGTH))
		rings.append(ring)
		uu.append(t * LENGTH)
	var vv := PackedFloat32Array()
	for j in 12:
		vv.append(float(j))
	mb.grid(rings, uu, vv, true, true)
	# two long trailing fins near the tail
	for sgn in [-1.0, 1.0]:
		var a := mb.vert(Vector3(sgn * 4.0, 0.0, LENGTH * 0.62), Vector3.UP)
		var b := mb.vert(Vector3(sgn * 26.0, -3.0, LENGTH * 0.8), Vector3.UP)
		var c := mb.vert(Vector3(sgn * 3.0, 0.0, LENGTH * 0.78), Vector3.UP)
		mb.tri(a, b, c)
		var a2 := mb.vert(Vector3(sgn * 4.0, 0.0, LENGTH * 0.62), Vector3.DOWN)
		var b2 := mb.vert(Vector3(sgn * 26.0, -3.0, LENGTH * 0.8), Vector3.DOWN)
		var c2 := mb.vert(Vector3(sgn * 3.0, 0.0, LENGTH * 0.78), Vector3.DOWN)
		mb.tri(a2, b2, c2)
	return mb.build()


## speed_mult: the autowalk's pace ratio, so the crossing still falls inside the look across the forest.
func start(speed_mult := 1.0) -> void:
	if _t < 0.0:
		_t = 0.0
		_dur = FROM.distance_to(TO) / (SPEED * maxf(speed_mult, 0.1))
		visible = true


func _process(dt: float) -> void:
	if _t < 0.0:
		return
	_t += dt
	var k := _t / _dur
	if k >= 1.0:
		visible = false
		set_process(false)
		return
	var dir := (TO - FROM).normalized()
	global_position = FROM.lerp(TO, k) + Vector3(0, sin(_t * 0.12) * 6.0, 0)
	look_at(global_position + dir, Vector3.UP)
	# the body trails behind the head (+Z local is behind when looking along -Z)
