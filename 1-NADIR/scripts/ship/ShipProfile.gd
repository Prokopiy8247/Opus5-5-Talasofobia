extends RefCounted
## Colossal ship hull geometry in DESIGN space (before sinking). The hull is an extrusion along X of one
## cross-section in (z, depth). v = profile arc length in metres from the top edge, down the side wall,
## round the bilge and along the flat bottom toward +Z. Depth is positive metres (world y = -depth).
## Local frame on the hull: X = -world X (text reads left->right seen from the line), Y = up along the
## surface (toward smaller v), Z = outward normal (toward the line / downward under the ship).

const TOP_D := 258.0          # design top of the plating; the real edge is torn 3-24 m lower (tear())
const WALL_A := 26.0          # closest wall distance from the line (at WALL_D0)
const WALL_D0 := 525.0
const WALL_K := 2700.0        # z = A + (d - D0)^2 / K
const BILGE_D := 750.0        # side wall turns into the bilge here
const BILGE_R := 40.0         # bilge radius (tight enough that the underside hangs over the drifting line)
const Z_END := 300.0          # flat bottom extends to this z
const X_HALF := 600.0         # hull built over x in [-X_HALF, X_HALF]
const KEEL_PHI := 45.0        # bilge keel position on the bilge arc, degrees

const SINK_RATE := 0.12       # m/s, the hull sinks (driven by G.t)
const SINK_MAX := 16.0        # clamp of the sink offset around the reference time
const SINK_REF_DEPTH := 600.0 # design depths are exact when the camera is here

# Layout of the details (design depths, metres; x along the hull, the line is at x = 0).
const PORT_ROWS := [338.0, 372.0, 400.0, 428.0, 456.0, 484.0, 512.0, 576.0, 604.0, 632.0]
const PORT_DX := 11.0
const PORT_XMAX := 165.0
const LADDER_X := -5.5
const LADDER_D := Vector2(266.0, 736.0)
const LADDER_TORN := Vector2(470.0, 483.0)
const HAWSE_X := -32.0
const HAWSE_D := 548.0
const HAWSE_R := Vector2(8.5, 6.5)
const CHAIN_END_D := 996.0     # last link; the anchor below ends ~1008.5 (<= 1026 m in the world)
const CHAIN_SPLIT_D := 740.0   # links above belong to beat 3, below to beat 4
const DAVIT_XS := [-17.0, -26.0]
const DAVIT_BASE_D := 368.0
const DRAFT_X := 5.0
const BOOT_D := 655.0          # boot-top: antifouling paint below

const CRUMPLE_V := 40.0        # the top 40 m of plating (v) is bent by crumple()

const STEP := 0.5
static var _vtab := PackedFloat32Array()
static var _alpha1 := 0.0
static var _c := Vector2.ZERO   # bilge arc centre (z, d)
static var _v1 := 0.0           # v where the bilge starts
static var _v2 := 0.0           # v where the flat bottom starts
static var _vend := 0.0
static var _t_ref := INF
static var lurch := 0.0         # extra sink of the B4 settle event (moves B3 and B4 together)


static func _ensure() -> void:
	if _vtab.size() > 0:
		return
	var n := int(round((BILGE_D - TOP_D) / STEP)) + 1
	_vtab.resize(n)
	_vtab[0] = 0.0
	var v := 0.0
	for i in range(1, n):
		var s := wall_slope(TOP_D + (i - 0.5) * STEP)
		v += STEP * sqrt(1.0 + s * s)
		_vtab[i] = v
	_v1 = v
	_alpha1 = atan(wall_slope(BILGE_D))
	_c = Vector2(wall_z(BILGE_D) + BILGE_R * cos(_alpha1), BILGE_D - BILGE_R * sin(_alpha1))
	_v2 = _v1 + BILGE_R * (PI * 0.5 - _alpha1)
	_vend = _v2 + (Z_END - _c.x)


static func wall_z(d: float) -> float:
	return WALL_A + (d - WALL_D0) * (d - WALL_D0) / WALL_K

static func wall_slope(d: float) -> float:
	return 2.0 * (d - WALL_D0) / WALL_K

static func v_bilge() -> float:
	_ensure()
	return _v1

static func v_bottom() -> float:
	_ensure()
	return _v2

static func v_end() -> float:
	_ensure()
	return _vend

static func bottom_depth() -> float:
	_ensure()
	return _c.y + BILGE_R

static func arc_centre() -> Vector2:
	_ensure()
	return _c

static func v_keel() -> float:
	_ensure()
	return _v1 + BILGE_R * (deg_to_rad(KEEL_PHI) - _alpha1)


## Profile length at a design depth (side wall and bilge; clamps to the bottom start).
static func v_at_depth(d: float) -> float:
	_ensure()
	if d <= TOP_D:
		return (d - TOP_D) * sqrt(1.0 + pow(wall_slope(TOP_D), 2.0))
	if d <= BILGE_D:
		var f := (d - TOP_D) / STEP
		var i := int(f)
		var j: int = min(i + 1, _vtab.size() - 1)
		return lerpf(_vtab[i], _vtab[j], f - i)
	var sphi := clampf((d - _c.y) / BILGE_R, sin(_alpha1), 1.0)
	return _v1 + BILGE_R * (asin(sphi) - _alpha1)


static func _wall_depth(v: float) -> float:
	if v <= 0.0:
		return TOP_D + v / sqrt(1.0 + pow(wall_slope(TOP_D), 2.0))
	var lo := 0
	var hi := _vtab.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _vtab[mid] < v:
			lo = mid
		else:
			hi = mid
	var f: float = (v - _vtab[lo]) / maxf(_vtab[hi] - _vtab[lo], 1e-6)
	return TOP_D + (lo + clampf(f, 0.0, 1.0)) * STEP


## Profile slope angle at v: 0 = vertical wall, PI/2 = flat bottom.
static func angle_at(v: float) -> float:
	_ensure()
	if v <= _v1:
		return atan(wall_slope(_wall_depth(v)))
	if v <= _v2:
		return _alpha1 + (v - _v1) / BILGE_R
	return PI * 0.5


## (z, depth) of the profile at v.
static func zd(v: float) -> Vector2:
	_ensure()
	if v <= _v1:
		var d := _wall_depth(v)
		return Vector2(wall_z(d), d)
	if v <= _v2:
		var phi := _alpha1 + (v - _v1) / BILGE_R
		return _c + BILGE_R * Vector2(-cos(phi), sin(phi))
	return Vector2(_c.x + (v - _v2), _c.y + BILGE_R)


static func point(x: float, v: float) -> Vector3:
	var p := zd(v)
	return Vector3(x, -p.y, p.x)

static func normal(v: float) -> Vector3:
	var a := angle_at(v)
	return Vector3(0.0, -sin(a), -cos(a))

static func up(v: float) -> Vector3:
	var a := angle_at(v)
	return Vector3(0.0, cos(a), -sin(a))

## Hull-surface frame at (x, v), lifted 'lift' metres off the surface along the normal.
static func frame(x: float, v: float, lift := 0.0) -> Transform3D:
	var n := normal(v)
	return Transform3D(Basis(Vector3(-1, 0, 0), up(v), n), point(x, v) + n * lift)


# ---------------------------------------------------------------- slow sinking
## Sink offset in metres (positive = deeper) at game time t. Design depths are exact at SINK_REF_DEPTH.
static func sink_at(t: float) -> float:
	if _t_ref == INF:
		if G.path == null:
			return 0.0
		_t_ref = G.path.time_at(G.path.s_at_depth(SINK_REF_DEPTH))
	return clampf(SINK_RATE * (t - _t_ref), -SINK_MAX, SINK_MAX) + lurch

## Camera depth at which an object at design depth d is level with the camera (autowalk timeline).
static func cam_depth(d: float) -> float:
	var c := d
	for i in 3:
		c = d + sink_at(G.path.time_at(G.path.s_at_depth(c)))
	return c


# ---------------------------------------------------------------- torn top edge
## Profile length v of the torn top edge at x (same formula as tear_line() in hull.gdshader).
static func tear(x: float) -> float:
	return 3.0 + 7.0 * _vnoise(x * 0.04, 1.3) + 4.0 * _vnoise(x * 0.13, 2.9) \
		+ 3.0 * absf(2.0 * _vnoise(x * 0.37, 7.1) - 1.0) + 7.0 * smoothstep(0.78, 0.84, _vnoise(x * 0.02, 4.0))

## Torn upper plating bent in and out (metres along the outward normal; + toward the line). Seen from below
## along the wall, a cut in v is foreshortened to a straight line: the bends make the silhouette ragged.
## Zero beside the ladder (it stays welded flat to the wall).
static func crumple(x: float, v: float) -> float:
	var w := clampf(1.0 - v / CRUMPLE_V, 0.0, 1.0)
	if w <= 0.0:
		return 0.0
	var a := 8.0 * clampf((_vnoise(x * 0.035, 3.3) - 0.5) * 3.5, -1.0, 1.0) \
		+ 3.5 * clampf((_vnoise(x * 0.11, 5.5) - 0.5) * 3.0, -1.0, 1.0)
	return a * pow(w, 1.2) * smoothstep(4.0, 12.0, absf(x - LADDER_X))

static func _fract(a: float) -> float:
	return a - floorf(a)

## hash12 / vnoise of the ship shaders, ported 1:1.
static func _hash12(x: float, y: float) -> float:
	var p3 := Vector3(_fract(x * 0.1031), _fract(y * 0.1031), _fract(x * 0.1031))
	var d := p3.dot(Vector3(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33))
	p3 += Vector3(d, d, d)
	return _fract((p3.x + p3.y) * p3.z)

static func _vnoise(x: float, y: float) -> float:
	var ix := floorf(x)
	var iy := floorf(y)
	var fx := x - ix
	var fy := y - iy
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	var a := _hash12(ix, iy)
	var b := _hash12(ix + 1.0, iy)
	var c := _hash12(ix, iy + 1.0)
	var e := _hash12(ix + 1.0, iy + 1.0)
	return lerpf(lerpf(a, b, ux), lerpf(c, e, ux), uy)
