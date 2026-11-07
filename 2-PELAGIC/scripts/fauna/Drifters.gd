extends Node3D
## Gelatinous drifters of the open blue (about 170-245 s): salp chains and one long siphonophore hanging in the
## water between the drop off the wall and the dark line, the life of the empty blue at the scale of the diver.
## They are passive plankton, still in the water (the diver glides past them), placed off the path where the gaze
## of each moment finds them: below while it looks down into the abyss, overhead against the light during the long
## look up, below again as it sinks towards the dark line. One MultiMesh (one instance per zooid, bell, stem
## segment or cormidium); shaders/fx_drifter.gdshader gives the glassy look (zooids and bells traced as exact
## ellipsoids, read by their rims and the salps' dark guts) and the slow undulation, and fades each animal in and out
## on the story clock (no pop). The node is hidden outside the drifters' time span.

const SHADER := preload("res://shaders/fx_drifter.gdshader")

## kind ("salp" chain or "siph" siphonophore, which hangs from its first point), story time of the reference path
## point, first and last point of the body relative to that path point (m), story window (fade in starts, fade
## out ends; the shader fades over 5 s at each end). Gone by 245 s: the dark-line views stay clean.
const ANIMALS := [
	["salp", 172.0, Vector3(-4.5, -9.8, -10.7), Vector3(-1.0, -11.3, -13.7), Vector2(166.0, 184.0)],
	["salp", 176.0, Vector3(-5.1, -15.4, -15.3), Vector3(-0.6, -16.9, -19.8), Vector2(170.0, 191.0)],
	["salp", 186.0, Vector3(-4.9, -19.8, -18.0), Vector3(0.1, -21.8, -23.0), Vector2(178.0, 202.0)],
	["siph", 192.0, Vector3(0.2, -13.7, -24.0), Vector3(-4.8, -33.7, -29.0), Vector2(183.0, 208.0)],
	# seen as the gaze swings up from the abyss to the light
	["salp", 202.0, Vector3(-1.7, -7.6, -18.8), Vector3(3.3, -9.6, -21.8), Vector2(194.0, 211.0)],
	# in the lower half of the long look up, against the brighter water, below the far shoal
	["salp", 212.0, Vector3(4.6, 2.5, -16.0), Vector3(8.6, 1.0, -20.0), Vector2(198.0, 221.0)],
	["salp", 220.0, Vector3(5.7, 3.7, -19.0), Vector3(11.7, 1.7, -22.0), Vector2(208.0, 230.0)],
	# as the gaze sinks towards the dark line
	["salp", 238.0, Vector3(-2.8, -8.7, -11.3), Vector3(1.2, -10.2, -14.3), Vector2(228.0, 245.0)],
]
const SALP_STEP := 0.13       # m between zooids along a chain (a double row: alternate sides)
const STEM_STEP := 0.35       # m between the siphonophore's stem segments (they overlap into one thread)
const CORM_STEP := 0.35       # m between its cormidia (the stem reads as a fuzzy rope)

var _mat: ShaderMaterial
var _mi: MultiMeshInstance3D
var _span := Vector2(INF, -INF)
var _xf: Array[Transform3D] = []
var _cd := PackedColorArray()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.seed = 9137
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for an in ANIMALS:
		var p0 := PathDef.point_at_time(an[1])
		var a: Vector3 = p0 + an[2]
		var b: Vector3 = p0 + an[3]
		var w: Vector2 = an[4]
		_span = Vector2(minf(_span.x, w.x), maxf(_span.y, w.y))
		var sd := _rng.randf() * 0.95
		if an[0] == "siph":
			_siphonophore(a, b, w, sd)
		else:
			_salp_chain(a, b, w, sd)
		lo = lo.min(a.min(b))
		hi = hi.max(a.max(b))
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 6       # ~40 vertices a part: under 20k for the whole MultiMesh
	sphere.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = sphere
	mm.instance_count = _xf.size()
	for i in _xf.size():
		mm.set_instance_transform(i, _xf[i])
		mm.set_instance_custom_data(i, _cd[i])
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mi = MultiMeshInstance3D.new()
	_mi.multimesh = mm
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mi.custom_aabb = AABB(lo - Vector3.ONE * 4.0, hi - lo + Vector3.ONE * 8.0)
	add_child(_mi)
	_xf.clear()
	var nv: int = (sphere.get_mesh_arrays()[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	print("PELAGIC drifters: %d animals, %d parts, %d vertices" % [ANIMALS.size(), mm.instance_count,
		mm.instance_count * nv])
	_process(0.0)


func _process(_delta: float) -> void:
	var t := Game.path_time
	var on := t > _span.x - 1.0 and t < _span.y + 1.0
	if on:
		_mat.set_shader_parameter("story_t", t)
	if visible != on:
		visible = on


## One part: a unit sphere stretched to half length hl along axis (its Y axis) and radius r across.
func _part(pos: Vector3, axis: Vector3, hl: float, r: float, s: float, kind: int, seed_: float, w: Vector2) -> void:
	var ay := axis.normalized()
	var ref := Vector3.UP if absf(ay.y) < 0.9 else Vector3.RIGHT
	var ax := ay.cross(ref).normalized()
	var az := ax.cross(ay)
	_xf.append(Transform3D(Basis(ax * r, ay * hl, az * r), pos))
	_cd.append(Color(s, float(kind) + seed_, w.x, w.y))


## A gently bent body line from a to b: point and tangent at s (0..1); side and normal of the bend.
func _curve(a: Vector3, b: Vector3, s: float, bend: Vector2, ph: float) -> Vector3:
	var t := (b - a).normalized()
	var side := t.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.1 else Vector3.RIGHT
	var nrm := side.cross(t)
	var l := a.distance_to(b)
	return a + (b - a) * s + side * sin(PI * s) * bend.x * l + nrm * sin(TAU * s + ph) * bend.y * l


## A salp chain: barrel-shaped zooids in a double row, each set obliquely to the chain, a slow curve. A living chain
## is never a regular zipper: each zooid's size (+-15 %), spacing (+-20 %), angle to the chain (+-12 deg) and roll
## about it (+-12 deg) vary.
func _salp_chain(a: Vector3, b: Vector3, w: Vector2, sd: float) -> void:
	var l := a.distance_to(b)
	var n := maxi(int(l / SALP_STEP), 4)
	var bend := Vector2(_rng.randf_range(0.06, 0.14), _rng.randf_range(0.03, 0.07))
	var ph := _rng.randf() * TAU
	var size := _rng.randf_range(0.85, 1.15)
	# the irregularity comes from a generator of its own, so the other animals keep their shapes
	var jr := RandomNumberGenerator.new()
	jr.seed = 7919 + int(sd * 1000003.0)
	var at := PackedFloat32Array()
	var acc := 0.0
	for i in n:
		at.append(acc)
		acc += jr.randf_range(0.8, 1.2)
	var span := maxf(at[n - 1], 1e-3)
	for i in n:
		var s := at[i] / span
		var p := _curve(a, b, s, bend, ph)
		var tg := (_curve(a, b, minf(s + 0.01, 1.0), bend, ph) - _curve(a, b, maxf(s - 0.01, 0.0), bend, ph)).normalized()
		var side := tg.cross(Vector3.UP)
		side = side.normalized() if side.length() > 0.1 else Vector3.RIGHT
		side = side.rotated(tg, deg_to_rad(jr.randf_range(-12.0, 12.0)))
		var sg := 1.0 if i % 2 == 0 else -1.0
		var ang := deg_to_rad(55.0 + jr.randf_range(-12.0, 12.0))
		var axis := tg * cos(ang) + side * sin(ang) * sg
		var k := size * _rng.randf_range(0.85, 1.15)
		var fat := jr.randf_range(0.9, 1.1)
		# big oceanic salps (Salpa maxima: barrels of 20-25 cm)
		_part(p + side * 0.07 * sg * k, axis, 0.12 * k, 0.065 * k * fat, s, 0, sd, w)


## A siphonophore: a cluster of swimming bells at the top, a long thin stem hanging from it, and cormidia (small
## feeding polyps) along the stem.
func _siphonophore(a: Vector3, b: Vector3, w: Vector2, sd: float) -> void:
	var l := a.distance_to(b)
	var bend := Vector2(0.07, 0.04)
	var ph := 1.0
	var tg0 := (b - a).normalized()
	var side0 := tg0.cross(Vector3.UP)
	side0 = side0.normalized() if side0.length() > 0.1 else Vector3.RIGHT
	for i in 8:
		var s := 0.03 * float(i) / 7.0
		var sg := 1.0 if i % 2 == 0 else -1.0
		var p := _curve(a, b, s, bend, ph) + side0 * 0.09 * sg
		_part(p, tg0 + side0 * 0.35 * sg, 0.12, 0.09, s, 2, sd, w)
	var ns := maxi(int(l / STEM_STEP), 2)
	for i in ns:
		var s := (float(i) + 0.5) / float(ns)
		var p := _curve(a, b, s, bend, ph)
		var tg := _curve(a, b, minf(s + 0.01, 1.0), bend, ph) - _curve(a, b, maxf(s - 0.01, 0.0), bend, ph)
		_part(p, tg, STEM_STEP * 0.7, 0.025, s, 1, sd, w)
	var nc := maxi(int(l / CORM_STEP), 1)
	for i in nc:
		var s := 0.04 + 0.96 * float(i) / float(nc)
		var sg := 1.0 if i % 2 == 0 else -1.0
		var p := _curve(a, b, s, bend, ph) + side0 * 0.05 * sg
		_part(p, tg0 + side0 * 0.6 * sg, 0.08, 0.045, s, 3, sd, w)
