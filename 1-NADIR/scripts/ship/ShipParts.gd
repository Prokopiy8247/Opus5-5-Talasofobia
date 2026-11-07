extends RefCounted
## Detail generators for the colossal ship: hull chunks, portholes, ladder, hawsehole, anchor chain and anchor,
## davits, bilge keel, the torn top edge, rusticles. All positions in design space (the beat node itself sinks).
## Draft marks are painted in hull.gdshader (they live on whichever hull chunk covers them).

const P = preload("res://scripts/ship/ShipProfile.gd")
const SM = preload("res://scripts/ship/ShipMesh.gd")

const X_CHUNKS := [[-600.0, -200.0, 40.0], [-200.0, -70.0, 10.0], [-70.0, 70.0, 10.0], [70.0, 200.0, 10.0], [200.0, 600.0, 40.0]]
const RUST_VIS := 120.0


## Hull surface over profile range [v0, v1], split into chunks (60 m of v x 5 x-bands).
static func hull(parent: Node3D, v0: float, v1: float, dv: float) -> void:
	var nv := maxi(1, int(ceil((v1 - v0) / 60.0)))
	for j in nv:
		var a := lerpf(v0, v1, float(j) / nv)
		var b := lerpf(v0, v1, float(j + 1) / nv)
		for c in X_CHUNKS:
			var mi := SM.mesh_node(SM.hull_chunk(c[0], c[1], a, b, c[2], dv), Transform3D.IDENTITY, 330.0)
			mi.name = "Hull_%d_%d" % [j, int(c[0])]
			parent.add_child(mi)


## Rows of heavy-rimmed portholes (rows with design depth in [d_min, d_max]).
static func portholes(parent: Node3D, d_min: float, d_max: float) -> void:
	var rim := SM.torus(1.8, 1.8, 0.28, 24, 8).mesh()
	var glass := SM.disc(1.62, 20).mesh()
	var broken := []
	for k in 3:
		broken.append(SM.disc(1.62, 16, 0.9, 11 + k).mesh())
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for d in P.PORT_ROWS:
		if d < d_min or d > d_max:
			continue
		var v := P.v_at_depth(d)
		var xr := []
		var xg := []
		var xb := [[], [], []]
		var n := int(P.PORT_XMAX / P.PORT_DX)
		for k in range(-n, n + 1):
			var x := k * P.PORT_DX
			xr.append(P.frame(x, v, 0.12))
			var r := rng.randf()
			var f := P.frame(x, v, 0.1)
			if r < 0.6:
				xg.append(f)
			elif r < 0.86:
				f.basis = f.basis * Basis(Vector3(0, 0, 1), rng.randf() * TAU)
				xb[rng.randi() % 3].append(f)
		parent.add_child(SM.mm_node(rim, xr, 240.0, SM.metal_material("rim")))
		if xg.size() > 0:
			parent.add_child(SM.mm_node(glass, xg, 160.0, SM.porthole_glass_material()))
		for k in 3:
			if xb[k].size() > 0:
				parent.add_child(SM.mm_node(broken[k], xb[k], 160.0, SM.glass_material()))


## Welded human-scale ladder down the wall (rungs 8 cm, every 0.4 m), torn in one place. Thin parts use the
## coverage-scaled thin_metal shader, so far away they read as a dim thread instead of crawling dots.
static func ladder(parent: Node3D) -> void:
	var rung := CylinderMesh.new()
	rung.top_radius = 0.042
	rung.bottom_radius = 0.042
	rung.height = 0.66
	rung.radial_segments = 6
	rung.rings = 1
	var stringer := BoxMesh.new()
	stringer.size = Vector3(0.1, 1.0, 0.08)
	var bracket := BoxMesh.new()
	bracket.size = Vector3(0.07, 0.34, 0.07)   # long axis Y (laid along the normal below)
	var lx: float = P.LADDER_X
	# the ladder starts just below the torn edge (never in open water above it)
	var v0 := maxf(P.v_at_depth(P.LADDER_D.x), maxf(P.tear(lx - 0.3), P.tear(lx + 0.3)) + 1.5)
	var v1 := P.v_at_depth(P.LADDER_D.y)
	var t0 := P.v_at_depth(P.LADDER_TORN.x)
	var t1 := P.v_at_depth(P.LADDER_TORN.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var nchunk := int(ceil((v1 - v0) / 60.0))
	for c in nchunk:
		var a := v0 + c * 60.0
		var b := minf(v1, a + 60.0)
		var xr := []
		var xs := []
		var xk := []
		var v := a
		while v < b:   # rungs
			var torn := v > t0 and v < t1
			if not torn and rng.randf() > 0.05:
				var n := P.normal(v)
				xr.append(Transform3D(Basis(P.up(v), Vector3(1, 0, 0), n), P.point(lx, v) + n * 0.32))
			v += 0.4
		v = a
		while v < b:   # stringers
			for side in [-1.0, 1.0]:
				if v > t0 and v < t1 and side < 0.0:
					continue
				var f := P.frame(lx + side * 0.28, v + 0.45, 0.32)
				if v > t0 and v < t1 and v < t0 + 4.0:   # bent piece sticking out of the tear
					f.basis = f.basis * Basis(Vector3(1, 0, 0), deg_to_rad(28.0 + (v - t0) * 6.0))
					f.origin += P.normal(v) * (v - t0) * 0.35
				xs.append(f)
			v += 0.9
		v = a
		while v < b:   # brackets
			for side in [-1.0, 1.0]:
				var f := P.frame(lx + side * 0.28, v, 0.17)
				xk.append(Transform3D(Basis(f.basis.x, f.basis.z, -f.basis.y), f.origin))
			v += 3.0
		for item in [[rung, xr, "rung"], [stringer, xs, "stringer"], [bracket, xk, "bracket"]]:
			parent.add_child(SM.mm_node(item[0], item[1], 120.0, SM.thin_material(item[2])))


## The hawsehole: an elliptical opening as big as a house with a heavy bolster lip and a dark rising pipe.
## Returns a marker at its mouth.
static func hawse(parent: Node3D) -> Node3D:
	var vh := P.v_at_depth(P.HAWSE_D)
	var f := P.frame(P.HAWSE_X, vh)
	var r: Vector2 = P.HAWSE_R
	# a broad, flat cast flange (~1 m proud), not a round tyre: the tube is squashed along the normal
	# (normals by the inverse scale, so the flat face shades flat)
	var lip := SM.torus(r.x + 1.6, r.y + 1.6, 2.2, 44, 12)
	var lsc := Vector3(1.0, 1.0, 0.38)
	for k in lip.v.size():
		lip.v[k] = lip.v[k] * lsc + Vector3(0, 0, 0.3)
		lip.n[k] = (lip.n[k] / lsc).normalized()
	parent.add_child(SM.mesh_node(lip.mesh(), f, 260.0, SM.metal_material("lip")))
	var path := PackedVector3Array()
	for k in 8:
		var t := k / 7.0
		path.append(Vector3(0, 4.5 * t * t, 1.0 - 17.0 * t))
	var tube := SM.sweep(path, Vector3(1, 0, 0), SM.ring(1.0, 20, r.x + 0.2, r.y + 0.2), false, true)
	parent.add_child(SM.mesh_node(tube.mesh(), f, 200.0, SM.metal_material("throat")))
	var cap := SM.disc(maxf(r.x, r.y) + 1.0, 20)
	cap.xform(Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(15.0)), Vector3(0, 4.4, -15.6)))
	parent.add_child(SM.mesh_node(cap.mesh(), f, 200.0, SM.black_material()))
	var m := Node3D.new()
	m.name = "HawseMarker"
	m.position = f.origin + f.basis.z * 1.0
	parent.add_child(m)
	return m


## Anchor chain: out of the hawse pipe, over the lip, then straight down into the void.
static func chain_points() -> Array:
	var vh := P.v_at_depth(P.HAWSE_D)
	var h := P.point(P.HAWSE_X, vh)
	var n := P.normal(vh)
	var u := P.up(vh)
	var ry: float = P.HAWSE_R.y
	var ctrl := [h - n * 8.0 + u * 3.0, h - n * 1.0 - u * (ry - 1.2), h + n * 2.6 - u * (ry + 0.6),
		h + n * 3.4 - u * (ry + 2.6)]
	var last: Vector3 = ctrl[3]
	ctrl.append(Vector3(last.x, last.y - 5.0, last.z))
	var dense := PackedVector3Array()
	for i in ctrl.size() - 1:   # Catmull-Rom through the bend
		var p0: Vector3 = ctrl[max(i - 1, 0)]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[i + 1]
		var p3: Vector3 = ctrl[min(i + 2, ctrl.size() - 1)]
		for s in 12:
			dense.append(p1.cubic_interpolate(p2, p0, p3, s / 12.0))
	dense.append(ctrl[ctrl.size() - 1])
	dense.append(Vector3(last.x, -P.CHAIN_END_D, last.z))
	# resample at the link pitch
	var pitch := 1.8
	var out := []
	var carry := 0.0
	for i in dense.size() - 1:
		var a := dense[i]
		var b := dense[i + 1]
		var seg := a.distance_to(b)
		var s := carry
		while s < seg:
			out.append([a.lerp(b, s / seg), (b - a) / seg])
			s += pitch
		carry = s - seg
	return out

## Builds the links whose design depth lies in [d_min, d_max), relative to 'origin' (the parent's position in
## design space). Returns the chain's hanging x/z (for gaze and the pivot).
static func chain(parent: Node3D, d_min: float, d_max: float, origin := Vector3.ZERO) -> Vector2:
	var pts := chain_points()
	var link := SM.chain_link()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var xf := []
	for k in pts.size():
		var c: Vector3 = pts[k][0]
		var t: Vector3 = -(pts[k][1] as Vector3)
		var twist := deg_to_rad(90.0 * (k % 2) + rng.randf_range(-9.0, 9.0) + 30.0)
		if -c.y < d_min or -c.y >= d_max:
			continue
		var side := t.cross(Vector3(0, 0, 1))
		if side.length() < 0.1:
			side = t.cross(Vector3(1, 0, 0))
		var x := side.normalized().rotated(t, twist)
		xf.append(Transform3D(Basis(x, t, x.cross(t)), c - origin))
	var i := 0
	while i < xf.size():
		var nd := SM.mm_node(link, xf.slice(i, i + 50), 170.0)
		parent.add_child(nd)
		i += 50
	var last: Vector3 = pts[pts.size() - 1][0]
	return Vector2(last.x, last.z)

## Last link position of the chain (design space).
static func chain_end() -> Vector3:
	var pts := chain_points()
	return pts[pts.size() - 1][0]


## A stockless anchor hanging from the last link ('top' in the parent's space): shackle, 9 m shank, crown and
## two flukes tilted 40 deg up and out with pointed tips. ~12.4 m tall.
static func anchor(parent: Node3D, top: Vector3) -> void:
	var mat := SM.metal_material("chain")
	var sh := SM.torus(0.8, 1.1, 0.2, 20, 8)
	parent.add_child(SM.mesh_node(sh.mesh(), Transform3D(Basis(Vector3.UP, 0.6), top + Vector3(0, -1.6, 0)), 170.0, mat))
	var s0 := top + Vector3(0, -2.5, 0)
	var shank := SM.sweep(PackedVector3Array([s0, s0 + Vector3(0, -9.0, 0)]), Vector3(1, 0, 0), SM.ring(0.55, 8, 1.0, 0.75))
	parent.add_child(SM.mesh_node(shank.mesh(), Transform3D.IDENTITY, 170.0, mat))
	var crown := BoxMesh.new()
	crown.size = Vector3(4.8, 1.3, 1.6)
	var cp := s0 + Vector3(0, -9.3, 0)
	parent.add_child(SM.mesh_node(crown, Transform3D(Basis.IDENTITY, cp), 170.0, mat))
	var fluke := BoxMesh.new()
	fluke.size = Vector3(3.8, 0.35, 1.6)
	var tip := CylinderMesh.new()
	tip.top_radius = 0.02
	tip.bottom_radius = 0.8
	tip.height = 1.2
	tip.radial_segments = 4
	tip.rings = 1
	var ang := deg_to_rad(40.0)
	for side in [-1.0, 1.0]:
		var dir := Vector3(side * cos(ang), sin(ang), 0.0)
		var root := cp + Vector3(side * 2.2, 0.2, 0.0)
		parent.add_child(SM.mesh_node(fluke, Transform3D(Basis(Vector3(0, 0, 1), side * ang), root + dir * 1.9), 170.0, mat))
		var tb := Basis(Vector3(0, 0, 1), -side * deg_to_rad(50.0))
		parent.add_child(SM.mesh_node(tip, Transform3D(tb, root + dir * 4.3), 170.0, mat))


## Lifeboat davits high on the wall: gooseneck arms, hanging blocks and broken falls. Returns swaying pivots.
static func davits(parent: Node3D) -> Array:
	var pivots := []
	var mat := SM.metal_material("davit")
	var cable := CylinderMesh.new()
	cable.top_radius = 0.07
	cable.bottom_radius = 0.07
	cable.height = 1.0
	cable.radial_segments = 5
	cable.rings = 1
	var cmat := SM.thin_material("cable")
	var block := BoxMesh.new()
	block.size = Vector3(1.1, 1.6, 0.7)
	var base := BoxMesh.new()
	base.size = Vector3(2.4, 3.2, 0.5)
	var vb := P.v_at_depth(P.DAVIT_BASE_D)
	for k in P.DAVIT_XS.size():
		var f := P.frame(P.DAVIT_XS[k], vb)
		var path := PackedVector3Array([Vector3(0, -0.5, 0.3), Vector3(0, 6.0, 0.3)])
		for s in range(1, 13):
			var a := PI * s / 12.0
			path.append(Vector3(0, 6.0 + 5.0 * sin(a), 5.3 - 5.0 * cos(a)))
		path.append(Vector3(0, 4.6, 10.35))
		var arm := SM.sweep(path, Vector3(1, 0, 0), SM.ring(0.5, 4, 1.0, 1.0, PI * 0.25))
		parent.add_child(SM.mesh_node(arm.mesh(), f, 260.0, mat))
		parent.add_child(SM.mesh_node(base, f * Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0.25)), 260.0, mat))
		var pv := Node3D.new()
		pv.position = f * Vector3(0, 4.6, 10.35)
		parent.add_child(pv)
		pivots.append(pv)
		# [x offset, top, length] strands; blocks at the given depth below the tip
		var strands := [[-0.25, 0.0, 9.6], [0.25, 0.0, 9.6], [-0.2, 10.8, 12.0], [0.22, 10.8, 7.0]] if k == 0 \
			else [[0.0, 0.0, 16.6], [0.3, 0.0, 2.6], [0.1, 17.8, 4.5]]
		for st in strands:
			var c := SM.mesh_node(cable, Transform3D(Basis.from_scale(Vector3(1, st[2], 1)),
				Vector3(st[0], -st[1] - st[2] * 0.5, 0)), 0.0, cmat)
			pv.add_child(c)
		var by := -10.2 if k == 0 else -17.2
		pv.add_child(SM.mesh_node(block, Transform3D(Basis(Vector3(0, 1, 0), 0.4 * k), Vector3(0, by, 0)), 0.0, mat))
	return pivots


## Bilge keel fin (~3 m) along the turn of the bilge, plus docking strips on the flat bottom.
static func bilge_keel(parent: Node3D) -> Vector3:
	var vk := P.v_keel()
	var n := P.normal(vk)
	var u := P.up(vk)
	var mat := SM.metal_material("keel")
	var fin := BoxMesh.new()
	fin.size = Vector3(200.0, 3.0, 0.32)
	var bulb := CylinderMesh.new()
	bulb.top_radius = 0.4
	bulb.bottom_radius = 0.4
	bulb.height = 200.0
	bulb.radial_segments = 10
	var strip := BoxMesh.new()
	strip.size = Vector3(200.0, 0.9, 1.6)
	var bd := P.bottom_depth()
	for k in 4:
		var xc := -300.0 + k * 200.0
		var p := P.point(xc, vk)
		parent.add_child(SM.mesh_node(fin, Transform3D(Basis(Vector3(1, 0, 0), n, u), p + n * 1.4), 260.0, mat))
		parent.add_child(SM.mesh_node(bulb, Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), p + n * 2.95), 260.0, mat))
		for z in [118.0, 165.0, 225.0]:
			parent.add_child(SM.mesh_node(strip, Transform3D(Basis.IDENTITY, Vector3(xc, -(bd + 0.4), z)), 260.0, mat))
	return P.point(0.0, vk) + n * 3.0


# ---------------------------------------------------------------- torn top edge
## The torn top of the hull (ShipProfile.tear): broken frames sticking up out of the ragged plating every
## 4 m (30% gone, leaning +-25 deg), bent rail remnants between them, and three cables draped down the face.
## The beam finds a wreck's broken rail instead of a razor-straight cut.
static func top_edge(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2601
	var rib := BoxMesh.new()
	rib.size = Vector3(0.4, 1.0, 0.4)
	var unit := CylinderMesh.new()
	unit.top_radius = 1.0
	unit.bottom_radius = 1.0
	unit.height = 1.0
	unit.radial_segments = 6
	unit.rings = 1
	var ribs := []
	var thin := []
	var tops := {}
	var k := 0
	var x := -150.0
	while x <= 150.0:
		if rng.randf() > 0.3:
			var v := P.tear(x) + 0.8
			var h := rng.randf_range(1.6, 3.0) * (1.0 + 0.8 * pow(rng.randf(), 3.0))
			var f := P.frame(x, v, -0.25 + P.crumple(x, v))   # just behind the (bent) plating
			var b := f.basis * Basis(Vector3(1, 0, 0), deg_to_rad(rng.randf_range(-25.0, 25.0))) \
				* Basis(Vector3(0, 0, 1), deg_to_rad(rng.randf_range(-8.0, 8.0)))
			ribs.append(Transform3D(b * Basis.from_scale(Vector3(1.0, h, 1.0)), f.origin + b.y * (h * 0.5 - 0.8)))
			tops[k] = f.origin + b.y * (h - 1.1)
		x += 4.0
		k += 1
	# rail remnants: runs between neighbouring frames, sagging, with gaps
	for i in k - 1:
		if tops.has(i) and tops.has(i + 1) and rng.randf() < 0.55:
			var a: Vector3 = tops[i]
			var b: Vector3 = tops[i + 1]
			var mid := (a + b) * 0.5 + Vector3(0, -rng.randf_range(0.1, 0.7), 0)
			thin.append(_seg(a, mid, 0.09))
			thin.append(_seg(mid, b, 0.09))
	# cables draped down the face: two sagging loops and one hanging free end
	for c in 3:
		var xa := rng.randf_range(-60.0, 45.0)
		var pts := PackedVector3Array()
		if c < 2:
			var span := rng.randf_range(9.0, 18.0)
			var length := rng.randf_range(20.0, 40.0)
			var sag := sqrt(maxf(length * length - span * span, 1.0) * 3.0 / 16.0)
			var va := P.tear(xa) + 0.6
			var vb := P.tear(xa + span) + 0.6
			for i in 25:
				var t := i / 24.0
				var v := lerpf(va, vb, t) + 4.0 * sag * t * (1.0 - t)
				pts.append(P.point(xa + span * t, v) + P.normal(v) * (0.2 + P.crumple(xa + span * t, v)))
		else:
			var length := rng.randf_range(20.0, 32.0)
			var va := P.tear(xa) + 0.6
			for i in 17:
				var t := i / 16.0
				var v := va + length * t
				var xx := xa + 1.4 * sin(t * 2.5) + 0.6 * t
				pts.append(P.point(xx, v) + P.normal(v) * (0.2 + P.crumple(xx, v)))
		for i in pts.size() - 1:
			thin.append(_seg(pts[i], pts[i + 1], 0.1))
	parent.add_child(SM.mm_node(rib, ribs, 200.0, SM.metal_material("ladder")))
	parent.add_child(SM.mm_node(unit, thin, 200.0, SM.thin_material("unit")))

## Transform of a unit cylinder (height 1 along Y, radius 1) spanning a -> b with radius r (slight overlap).
static func _seg(a: Vector3, b: Vector3, r: float) -> Transform3D:
	var y := b - a
	var l := maxf(y.length(), 0.001)
	var yn := y / l
	var x := yn.cross(Vector3(0, 0, 1))
	if x.length() < 0.2:
		x = yn.cross(Vector3(1, 0, 0))
	x = x.normalized()
	return Transform3D(Basis(x * r, yn * l * 1.04, x.cross(yn) * r), (a + b) * 0.5)


# ---------------------------------------------------------------- rusticles
## Rusticles on the wall (beat 3): under 60% of the portholes, along the lower hawse lip, under the davit arms,
## sparse colonies on the strake seams. They hang world-down; on the upper wall (which leans back) they are
## lifted so the tip clears the steel below.
static func rusticles_wall(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var items := []
	for d in P.PORT_ROWS:
		var v := P.v_at_depth(d)
		var n := int(P.PORT_XMAX / P.PORT_DX)
		for k in range(-n, n + 1):
			if rng.randf() > 0.6:
				continue
			for m in rng.randi_range(2, 6):
				var dx := rng.randf_range(-1.5, 1.5)
				var vv := v + sqrt(maxf(3.24 - dx * dx, 0.0)) + 0.2
				var l := lerpf(1.2, 6.0, pow(rng.randf(), 1.8))
				items.append(_wall_rusticle(rng, k * P.PORT_DX + dx, vv, l, rng.randf_range(0.7, 1.4), 0.25))
	# the lower half of the hawse lip
	var vh := P.v_at_depth(P.HAWSE_D)
	var fh := P.frame(P.HAWSE_X, vh)
	var r: Vector2 = P.HAWSE_R
	for i in rng.randi_range(18, 25):
		var th := rng.randf_range(PI * 1.08, PI * 1.92)
		var a: Vector3 = fh * Vector3(cos(th) * (r.x + 1.2), sin(th) * (r.y + 1.2) - 1.3, 1.1)
		var l := lerpf(1.2, 5.0, pow(rng.randf(), 1.6))
		items.append([vh + 9.0, _rust_xf(rng, a, l, rng.randf_range(0.6, 1.1))])
	# under the davit arms (the overhanging part of the gooseneck)
	var vb := P.v_at_depth(P.DAVIT_BASE_D)
	for dx in P.DAVIT_XS:
		var f := P.frame(dx, vb)
		for i in rng.randi_range(4, 7):
			var a := rng.randf_range(PI * 0.4, PI * 0.95)
			var p: Vector3 = f * Vector3(rng.randf_range(-0.25, 0.25), 6.0 + 5.0 * sin(a) - 0.45, 5.3 - 5.0 * cos(a))
			items.append([vb, _rust_xf(rng, p, lerpf(0.8, 3.0, rng.randf()), rng.randf_range(0.4, 0.8))])
	# sparse colonies along the strake seams (the lapped lower edge), |x| < 80
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.03
	var seam0: float = P.v_at_depth(P.PORT_ROWS[1]) - 3.5
	var vend := P.v_bilge() - 5.0
	var sv := seam0 - 7.0 * floorf(seam0 / 7.0)
	while sv < vend:
		if sv > 3.0:
			for i in 19:
				var x := rng.randf_range(-80.0, 80.0)
				if noise.get_noise_2d(x, sv) < 0.12 or absf(x - P.LADDER_X) < 2.0 or sv < P.tear(x) + 1.0:
					continue
				var l := lerpf(0.8, 3.5, pow(rng.randf(), 2.0))
				items.append(_wall_rusticle(rng, x, sv + 0.12, l, rng.randf_range(0.35, 0.7), 0.12))
		sv += 7.0
	_rusticle_nodes(parent, items)

## Rusticles under the ship (beat 4): clumps on the down-facing steel of the bilge and the flat bottom, most of
## them hanging from a strake seam or a frame line, bare steel between; clumps with bare stretches along the
## bilge-keel bulb (no even comb).
static func rusticles_under(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8086
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.07
	var vk := P.v_keel()
	var v0 := vk - 6.0
	var v1 := P.v_bottom() + 80.0
	# strake seams of the hull shader's plate grid (every 7 m of v) and frame lines (every 3.5 m of x)
	var seam0: float = P.v_at_depth(P.PORT_ROWS[1]) - 3.5
	var items := []
	var tries := 0
	while items.size() < 500 and tries < 30000:
		tries += 1
		var x := rng.randf_range(-70.0, 90.0)
		var v := rng.randf_range(v0, v1)
		if noise.get_noise_2d(x, v) < 0.35:
			continue
		var along := 0   # 0 = a loose clump, 1 = along a seam (x spread), 2 = along a frame (v spread)
		if rng.randf() < 0.7:
			if rng.randf() < 0.5:
				v = seam0 + 7.0 * roundf((v - seam0) / 7.0) + rng.randf_range(-0.3, 0.3)
				along = 1
			else:
				x = 3.5 * roundf(x / 3.5) + rng.randf_range(-0.3, 0.3)
				along = 2
		if v < v0 or v > v1 or P.normal(v).y > -0.35:
			continue
		var n := rng.randi_range(6, 14)
		var big := rng.randi() % n
		for m in n:
			var a := rng.randf() * TAU
			var rr := 1.5 * sqrt(rng.randf())
			var ox := rr * cos(a)
			var ov := rr * sin(a)
			if along == 1:
				ov *= 0.2
			elif along == 2:
				ox *= 0.2
			var l := rng.randf_range(3.0, 5.0) if m == big else rng.randf_range(0.5, 1.5)
			var s := rng.randf_range(0.8, 1.2) if m == big else rng.randf_range(0.4, 0.85)
			items.append([v, _rust_xf(rng, P.point(x + ox, v + ov) + Vector3(0, 0.12, 0), l, s)])
	# the bilge-keel bulb: clumps of 4-10 (1-2 long ones) where the noise allows, bare keel between
	var bulb := P.normal(vk) * 2.95 + Vector3(0, -0.3, 0)
	var kn := FastNoiseLite.new()
	kn.seed = 19
	kn.frequency = 0.08
	var placed := 0
	var kt := 0
	while placed < 130 and kt < 4000:
		kt += 1
		var xc := rng.randf_range(-70.0, 90.0)
		if kn.get_noise_1d(xc) < 0.2:
			continue
		var n := rng.randi_range(4, 10)
		var nl := rng.randi_range(1, 2)
		for m in n:
			var x := xc + rng.randf_range(-1.5, 1.5)
			var l := rng.randf_range(2.5, 4.5) if m < nl else rng.randf_range(0.4, 1.4)
			items.append([vk, _rust_xf(rng, P.point(x, vk) + bulb, l, rng.randf_range(0.35, 0.75))])
		placed += n
	_rusticle_nodes(parent, items)

static func _wall_rusticle(rng: RandomNumberGenerator, x: float, v: float, l: float, s: float, lift0: float) -> Array:
	var slope := tan(P.angle_at(v))
	var lift := lift0 + 0.12 * s + maxf(0.0, -slope) * l + P.crumple(x, v)
	return [v, _rust_xf(rng, P.point(x, v) + P.normal(v) * lift, l, s)]

static func _rust_xf(rng: RandomNumberGenerator, anchor: Vector3, l: float, s: float) -> Transform3D:
	var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08)) \
		* Basis.from_scale(Vector3(s, l, s))
	return Transform3D(b, anchor)

## One MultiMesh per 60 m band of v (items: [v, Transform3D]).
static func _rusticle_nodes(parent: Node3D, items: Array) -> void:
	var bands := {}
	for it in items:
		var key := int(floorf(float(it[0]) / 60.0))
		if not bands.has(key):
			bands[key] = []
		bands[key].append(it[1])
	for key in bands:
		var nd := SM.mm_node(SM.rusticle_mesh(), bands[key], RUST_VIS, SM.rusticle_material())
		nd.name = "Rusticles_%d" % key
		parent.add_child(nd)
