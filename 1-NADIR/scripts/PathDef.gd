class_name PathDef
extends RefCounted
## The descent line = the path. Curve3D built in code, plus:
##  - depth <-> path distance lookup
##  - the cinematic autowalk timeline (speed profile, time <-> distance)
##  - gaze cues registered by beats (autowalk look targets)
## Depth is positive metres (world y = -depth). Yaw 0 looks toward -Z, +yaw turns left; pitch + looks up.

# Control points (x, y, z). The line is vertical down to 700 m, then drifts under the ship hull (+Z).
const POINTS := [
	Vector3(0, -2.5, 0), Vector3(0, -40, 0), Vector3(0, -150, 0), Vector3(0, -330, 0),
	Vector3(0, -520, 0), Vector3(0, -700, 0), Vector3(0, -745, 9), Vector3(0, -790, 33),
	Vector3(0, -840, 51), Vector3(0, -900, 60), Vector3(0, -960, 62),
	Vector3(0, -1110, 62), Vector3(0, -1260, 62), Vector3(0, -1420, 62), Vector3(0, -1556.5, 62),
]

# The cinematic now runs at the Shift (brisk) speed. The original slower pacing is kept as the DESIGN pace: the
# time-based choreography (the creature encounter) and the gaze-cue turn times were authored against it.
const AUTO_END_EASE := 25.0          # m: the cinematic eases to a stop over the last metres above the floor
# Design pace multiplier keys (depth, mult): slower at reveals.
const DESIGN_MULT := [
	[0.0, 1.0], [75.0, 1.0], [110.0, 0.93], [280.0, 0.92], [300.0, 0.9], [350.0, 0.84], [420.0, 1.08],
	[690.0, 1.0], [740.0, 0.84], [830.0, 0.84], [900.0, 1.25], [960.0, 1.05], [1000.0, 0.92], [1160.0, 0.92],
	[1210.0, 1.15], [1300.0, 1.45], [1460.0, 1.25], [1530.0, 0.75], [1556.5, 0.4],
]

var curve := Curve3D.new()
var length := 0.0
var _depth_tab := PackedFloat32Array()   # depth at s = i metres
var _time_tab := PackedFloat32Array()    # autowalk time at s = i metres
var _dtime_tab := PackedFloat32Array()   # design-pace time at s = i metres
var cues: Array = []                     # {s0, s1, target, smooth}


func _init() -> void:
	curve.bake_interval = 0.5
	var n := POINTS.size()
	for i in n:
		var p: Vector3 = POINTS[i]
		var prev: Vector3 = POINTS[max(i - 1, 0)]
		var next: Vector3 = POINTS[min(i + 1, n - 1)]
		var dir := (next - prev).normalized()
		var h_in := dir * (p.distance_to(prev) / 3.0)
		var h_out := dir * (p.distance_to(next) / 3.0)
		curve.add_point(p, -h_in, h_out)
	length = curve.get_baked_length()
	var steps := int(ceil(length)) + 1
	_depth_tab.resize(steps)
	_time_tab.resize(steps)
	_dtime_tab.resize(steps)
	for i in steps:
		_depth_tab[i] = -curve.sample_baked(minf(float(i), length), true).y
	var t := 0.0
	var td := 0.0
	for i in steps:
		var s: float = min(float(i), length)
		_time_tab[i] = t
		_dtime_tab[i] = td
		if i < steps - 1:
			var mid: float = min(s + 0.5, length)
			t += 1.0 / max(auto_speed(mid), 0.05)
			td += 1.0 / max(design_speed(mid), 0.05)


# ---------------------------------------------------------------- queries
func pos_at(s: float) -> Vector3:
	return curve.sample_baked(clampf(s, 0.0, length), true)

func tangent_at(s: float) -> Vector3:
	var a := pos_at(s - 0.5)
	var b := pos_at(s + 0.5)
	return (b - a).normalized()

## Position of the visible descent line (rope) at path distance s.
func rope_at(s: float) -> Vector3:
	return pos_at(s) + Config.ROPE_OFFSET

func depth_at(s: float) -> float:
	return _lerp_tab(_depth_tab, s)

## Path distance where the path reaches the given depth (positive metres).
func s_at_depth(d: float) -> float:
	return _inverse(_depth_tab, d)

## World point of the path at a depth (convenient for beats).
func point_at_depth(d: float) -> Vector3:
	return pos_at(s_at_depth(d))

## Default (manual) walking speed at path distance s.
func base_speed(s: float) -> float:
	var d := depth_at(s)
	var f := smoothstep(Config.SHALLOW_END - 10.0, Config.SHALLOW_END + 10.0, d)
	return lerpf(Config.SPEED_SHALLOW, Config.SPEED_DEEP, f)

## Cinematic autowalk speed at s: the same as swimming with Shift held, easing to a stop above the floor.
func auto_speed(s: float) -> float:
	var end_f := clampf((length - s) / AUTO_END_EASE, 0.0, 1.0)
	return base_speed(s) * Config.BRISK_MULT * lerpf(0.2, 1.0, sqrt(end_f)) + 0.05

## The original (design) cinematic pace: slower at reveals, to a stop at the end.
func design_speed(s: float) -> float:
	var d := depth_at(s)
	var m := _keyed_f(DESIGN_MULT, d)
	var end_f := clampf((length - s) / 14.0, 0.0, 1.0)
	return base_speed(s) * m * lerpf(0.22, 1.0, sqrt(end_f)) + 0.05

## Autowalk timeline (seconds at the cinematic speed): --start-at / --end-at / --shot-at use it.
func time_at(s: float) -> float:
	return _lerp_tab(_time_tab, s)

## Design-pace timeline: the clock the time-based choreography was authored against.
func design_time_at(s: float) -> float:
	return _lerp_tab(_dtime_tab, s)

## How much faster the diver moves through s than the design pace assumed (>= 1 at the cinematic speed).
func pace_ratio(s: float, speed: float) -> float:
	return maxf(speed, 0.0) / maxf(design_speed(s), 0.05)

func s_at_time(t: float) -> float:
	return _inverse(_time_tab, t)

func total_time() -> float:
	return _time_tab[_time_tab.size() - 1]


# ---------------------------------------------------------------- gaze cues
## Register an autowalk gaze cue for path range [s0, s1].
## target: Vector3 world point | Node3D (follows it) | Callable -> Vector3 | Vector2(yaw_deg, pitch_deg) absolute.
## smooth: critically damped look time constant in seconds (bigger = slower, heavier turn).
func add_cue(s0: float, s1: float, target, smooth := 2.0) -> void:
	cues.append({"s0": s0, "s1": s1, "target": target, "smooth": smooth})
	cues.sort_custom(func(a, b): return a.s0 < b.s0)

func add_cue_depth(d0: float, d1: float, target, smooth := 2.0) -> void:
	add_cue(s_at_depth(d0), s_at_depth(d1), target, smooth)

## Returns the active cue for s (the one with the largest s0 that still covers s) or {}.
func cue_at(s: float) -> Dictionary:
	var best := {}
	for c in cues:
		if c.s0 <= s and s <= c.s1:
			best = c
	return best

## Unit look direction for a cue target seen from 'from'. Returns Vector3.ZERO if unusable.
static func cue_dir(target, from: Vector3) -> Vector3:
	var p = null
	if target is Vector2:
		var yaw := deg_to_rad(target.x)
		var pitch := deg_to_rad(target.y)
		return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	elif target is Vector3:
		p = target
	elif target is Node3D:
		if is_instance_valid(target) and target.is_inside_tree():
			p = target.global_position
	elif target is Callable:
		p = target.call()
	if p == null:
		return Vector3.ZERO
	var v: Vector3 = p - from
	return v.normalized() if v.length() > 0.01 else Vector3.ZERO


# ---------------------------------------------------------------- helpers
func _lerp_tab(tab: PackedFloat32Array, s: float) -> float:
	var x := clampf(s, 0.0, float(tab.size() - 1))
	var i := int(floor(x))
	var j: int = min(i + 1, tab.size() - 1)
	return lerpf(tab[i], tab[j], x - i)

func _inverse(tab: PackedFloat32Array, v: float) -> float:
	var lo := 0
	var hi := tab.size() - 1
	if v <= tab[lo]:
		return 0.0
	if v >= tab[hi]:
		return min(float(hi), length)
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if tab[mid] < v:
			lo = mid
		else:
			hi = mid
	var f: float = (v - tab[lo]) / maxf(tab[hi] - tab[lo], 1e-6)
	return min(lo + f, length)

static func _keyed_f(keys: Array, x: float) -> float:
	if x <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if x <= keys[i][0]:
			var f: float = smoothstep(0.0, 1.0, (x - keys[i - 1][0]) / (keys[i][0] - keys[i - 1][0]))
			return lerpf(keys[i - 1][1], keys[i][1], f)
	return keys[keys.size() - 1][1]
