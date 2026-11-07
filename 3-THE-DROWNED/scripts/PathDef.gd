class_name PathDef
extends RefCounted
## The descent line: a Curve3D through Config.PATH_POINTS (Catmull-Rom handles), with helpers to
## place things relative to it. s = distance along the path in metres.

static var main: PathDef               # the game path, set by Main before the beats are built

var curve := Curve3D.new()
var length := 0.0
var beat_s: Array[float] = []      # start distance of each beat (6 entries)


func _init() -> void:
	var p := Config.PATH_POINTS
	curve.bake_interval = 0.5
	for i in p.size():
		var prev := p[maxi(i - 1, 0)]
		var nxt := p[mini(i + 1, p.size() - 1)]
		var tan := (nxt - prev) / (2.0 if i > 0 and i < p.size() - 1 else 1.0)
		curve.add_point(p[i], -tan / 3.0, tan / 3.0)
	length = curve.get_baked_length()
	for i in Config.BEAT_START_POINT:
		beat_s.append(curve.get_closest_offset(p[i]))
	beat_s[5] = Config.BEAT6_S


func pos(s: float) -> Vector3:
	return curve.sample_baked(clampf(s, 0.0, length), true)


func tangent(s: float) -> Vector3:
	var a := pos(s - 0.75)
	var b := pos(s + 0.75)
	return (b - a).normalized()


## Right vector: horizontal, perpendicular to the forward direction.
func right(s: float) -> Vector3:
	var t := tangent(s)
	var r := Vector3(-t.z, 0.0, t.x)
	if r.length_squared() < 1e-6:
		return Vector3.RIGHT
	return r.normalized()


## Up vector perpendicular to the tangent (points "above" the line).
func up(s: float) -> Vector3:
	return right(s).cross(tangent(s)).normalized()


## Horizontal forward direction (the way the line is heading, ignoring the descent).
func forward_h(s: float) -> Vector3:
	var t := tangent(s)
	var h := Vector3(t.x, 0.0, t.z)
	return h.normalized() if h.length_squared() > 1e-6 else Vector3.FORWARD


## World point at distance s with an offset in the path frame (x right, y up, z forward).
func at(s: float, offset := Vector3.ZERO) -> Vector3:
	return pos(s) + right(s) * offset.x + up(s) * offset.y + tangent(s) * offset.z


func rope_pos(s: float) -> Vector3:
	return at(s, Config.ROPE_OFFSET)


func closest_s(p: Vector3) -> float:
	return curve.get_closest_offset(p)


func beat_at(s: float) -> int:
	var b := 0
	for i in beat_s.size():
		if s >= beat_s[i] - 0.01:
			b = i
	return b


func beat_progress(s: float) -> float:
	var b := beat_at(s)
	var s0 := beat_s[b]
	var s1 := beat_s[b + 1] if b + 1 < beat_s.size() else length
	return clampf((s - s0) / maxf(s1 - s0, 1.0), 0.0, 1.0)
