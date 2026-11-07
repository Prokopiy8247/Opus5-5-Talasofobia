extends RefCounted
## Reef prop meshes (unit sized, base at the origin, +Y up). Vertex colour: r = AO, g = cavity (inside of a sponge)
## or, on tubes (kind 3), the tube radius / TUBE_R_MAX (the shader keeps thin stems at least ~1 px wide),
## b = shape parameter (radius for plates, height for branches). Read by reef_prop.gdshader.

const TUBE_R_MAX := 0.06

## Smooth surface of revolution from a profile walked from the base upwards (outer side first; a profile may go
## over a rim and down an inner wall). rad(a) modulates the radius around the axis. AO comes from the profile height
## (ao_y range), or per profile point from ao_prof when given.
static func _lathe(prof: Array, seg: int, rad: Callable, ao_y: Vector2, inner_from := 99, ao_prof := PackedFloat32Array()) -> Dictionary:
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	var nv := prof.size()
	for i in seg:
		var a := TAU * i / seg
		var k: float = rad.call(a)
		for j in nv:
			var p: Vector3 = prof[j]       # (r, y, b)
			pos.append(Vector3(cos(a) * p.x * k, p.y, sin(a) * p.x * k))
			var ao := ao_prof[j] if j < ao_prof.size() else lerpf(0.45, 1.0, smoothstep(ao_y.x, ao_y.y, p.y))
			col.append(Color(ao * (0.75 if j >= inner_from else 1.0), 1.0 if j >= inner_from else 0.0, p.z))
	var idx := PackedInt32Array()
	for i in seg:
		var i2 := (i + 1) % seg
		for j in nv - 1:
			var a := i * nv + j
			var b := i2 * nv + j
			idx.append_array([a, b, a + 1, b, b + 1, a + 1])
	return {"pos": pos, "col": col, "idx": idx}

## Merge parts {pos, col, idx} with optional transforms, compute smooth normals, commit.
static func _commit(parts: Array) -> ArrayMesh:
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for part in parts:
		var xf: Transform3D = part.get("xf", Transform3D.IDENTITY)
		var off := pos.size()
		for p in part["pos"]:
			pos.append(xf * p)
		col.append_array(part["col"])
		for i in part["idx"]:
			idx.append(i + off)
	var nrm := PackedVector3Array(); nrm.resize(pos.size())
	for t in range(0, idx.size(), 3):
		var a := idx[t]; var b := idx[t + 1]; var c := idx[t + 2]
		var fn := (pos[c] - pos[a]).cross(pos[b] - pos[a])
		nrm[a] += fn; nrm[b] += fn; nrm[c] += fn
	for i in nrm.size():
		nrm[i] = nrm[i].normalized() if nrm[i].length_squared() > 1e-12 else Vector3.UP
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos; arr[Mesh.ARRAY_NORMAL] = nrm; arr[Mesh.ARRAY_COLOR] = col; arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## Massive coral head (brain / boulder): a lumpy dome sunk into the ground. Flattened along its axis by the dresser
## it also serves as an encrusting colony on steep rock.
static func coral_head(seed: int) -> ArrayMesh:
	var n := FastNoiseLite.new()
	n.seed = seed; n.frequency = 1.1; n.fractal_octaves = 2
	var seg := 20; var rings := 10
	var pos := PackedVector3Array(); var col := PackedColorArray()
	var sq := 0.62 + 0.25 * (seed % 3) / 2.0
	for i in seg:
		var a := TAU * i / seg
		for j in rings + 1:
			var th := lerpf(-0.35, PI * 0.5, float(j) / rings)
			var d := Vector3(cos(th) * cos(a), sin(th), cos(th) * sin(a))
			var k := 1.0 + 0.2 * n.get_noise_3dv(d * 1.6) + 0.05 * n.get_noise_3dv(d * 5.0)
			var p := Vector3(d.x, d.y * sq, d.z) * k
			p.y = maxf(p.y, -0.25)
			pos.append(p)
			col.append(Color(lerpf(0.4, 1.0, smoothstep(-0.25, 0.25, p.y)), 0.0, float(j) / rings))
	var idx := PackedInt32Array()
	for i in seg:
		var i2 := (i + 1) % seg
		for j in rings:
			var a := i * (rings + 1) + j
			var b := i2 * (rings + 1) + j
			idx.append_array([a, b, a + 1, b, b + 1, a + 1])
	return _commit([{"pos": pos, "col": col, "idx": idx}])

## Barrel sponge: a thick, lumpy, ribbed and lopsided vase that leans a little, with an uneven rim and a dark cavity.
static func barrel(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var nz := FastNoiseLite.new()
	nz.seed = seed; nz.frequency = 2.2; nz.fractal_octaves = 3
	var ph := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var flare := rng.randf_range(0.85, 1.15)
	# (closed at the base: on a steep face the tilted vase's foot can stand a few cm out of the rock)
	var prof := [Vector3(0.0, -0.3, 0.0), Vector3(0.30, -0.25, 0.0), Vector3(0.36, 0.0, 0.08), Vector3(0.46, 0.25, 0.2),
		Vector3(0.56, 0.5, 0.35), Vector3(0.64 * flare, 0.8, 0.52), Vector3(0.70 * flare, 1.05, 0.68), Vector3(0.72 * flare, 1.3, 0.85),
		Vector3(0.70 * flare, 1.48, 0.96), Vector3(0.63 * flare, 1.58, 1.0), Vector3(0.54 * flare, 1.56, 1.0),
		Vector3(0.50 * flare, 1.38, 0.9), Vector3(0.45 * flare, 1.1, 0.75), Vector3(0.36, 0.8, 0.55), Vector3(0.0, 0.66, 0.45)]
	var ao := PackedFloat32Array([0.35, 0.4, 0.55, 0.7, 0.8, 0.88, 0.94, 1.0, 1.0, 1.0, 0.95, 0.75, 0.6, 0.5, 0.45])
	# lopsided outline: low-order lobes plus knobby vertical ribs
	var rib := func(a: float) -> float:
		return 1.0 + 0.11 * sin(a + ph) + 0.06 * sin(a * 2.0 + ph2) + 0.08 * absf(sin(a * 4.5 + ph)) + 0.03 * sin(a * 11.0 + ph * 2.0)
	var part := _lathe(prof, 30, rib, Vector2(-0.25, 0.6), 11, ao)
	var pos: PackedVector3Array = part["pos"]
	var lean := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(0.1, 0.22)
	for i in pos.size():
		var p := pos[i]
		var a := atan2(p.z, p.x)
		var hh := clampf(p.y / 1.5, 0.0, 1.2)
		# uneven, slightly wavy rim
		p.y += (0.13 * sin(a * 2.0 + ph2) + 0.05 * sin(a * 5.0 + ph)) * smoothstep(1.0, 1.5, p.y)
		# lumpy wall: displace along the horizontal radius
		var rr := Vector2(p.x, p.z)
		if rr.length() > 0.05:
			var bump := 0.05 * nz.get_noise_3d(p.x * 1.5, p.y, p.z * 1.5) + 0.025 * nz.get_noise_3d(p.x * 4.0 + 9.0, p.y * 4.0, p.z * 4.0)
			rr = rr.normalized() * maxf(rr.length() + bump, 0.0)
		# leaning, curved trunk
		p.x = rr.x + lean.x * hh * hh
		p.z = rr.y + lean.y * hh * hh
		pos[i] = p
	part["pos"] = pos
	return _commit([part])

## Tube sponge cluster: 4-6 tapered tubes with open dark mouths.
static func tubes(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var parts: Array = []
	var count := rng.randi_range(4, 6)
	for t in count:
		var h := rng.randf_range(0.6, 1.0) * (1.0 if t == 0 else rng.randf_range(0.55, 0.95))
		var r := rng.randf_range(0.085, 0.12)
		var prof := [Vector3(r * 0.9, -0.1, 0), Vector3(r, h * 0.3, 0.3), Vector3(r * 1.12, h * 0.8, 0.8), Vector3(r * 1.18, h, 1.0),
			Vector3(r * 0.86, h * 0.97, 1.0), Vector3(r * 0.8, h * 0.7, 0.8), Vector3(0.0, h * 0.62, 0.7)]
		var wob := rng.randf() * TAU
		var part := _lathe(prof, 9, func(a: float) -> float: return 1.0 + 0.06 * sin(a * 3.0 + wob), Vector2(-0.1, 0.4), 4)
		var ang := TAU * t / count + rng.randf_range(-0.4, 0.4)
		var off := Vector3(cos(ang), 0, sin(ang)) * (0.0 if t == 0 else rng.randf_range(0.14, 0.3))
		var tilt := Basis(Vector3(-off.z, 0, off.x).normalized() if off.length() > 0.01 else Vector3.RIGHT, rng.randf_range(0.05, 0.3))
		part["xf"] = Transform3D(tilt, off)
		parts.append(part)
	return _commit(parts)

## Plate coral growing out of a wall: a wavy, slightly cupped shelf whose growing margin is a rolled bead (about
## 5 cm high, 10-15 cm wide at the usual scales) standing above a shallow groove: the bead's upper side catches the
## light, the groove inside it and the bead's underside are shaded, so the edge reads as a lip with thickness.
## b = radius parameter (rings, groove r 0.84-0.9, pale bead r 0.9-1.0). AO: dark underneath and toward the centre,
## a little less in the groove, full on the bead and the open top.
static func plate(seed: int) -> ArrayMesh:
	var ph := float(seed) * 2.3
	var prof := [Vector3(0.0, -0.045, 0.0), Vector3(0.3, -0.04, 0.3), Vector3(0.6, -0.027, 0.6), Vector3(0.8, -0.012, 0.8),
		Vector3(0.9, -0.002, 0.9), Vector3(0.95, 0.006, 0.95), Vector3(0.985, 0.024, 0.985), Vector3(1.0, 0.05, 1.0),
		Vector3(0.99, 0.074, 1.0), Vector3(0.965, 0.088, 0.98), Vector3(0.93, 0.087, 0.95), Vector3(0.9, 0.074, 0.9),
		Vector3(0.87, 0.064, 0.87), Vector3(0.8, 0.062, 0.8), Vector3(0.6, 0.047, 0.62), Vector3(0.3, 0.031, 0.32),
		Vector3(0.0, 0.026, 0.0)]
	var ao := PackedFloat32Array([0.55, 0.58, 0.64, 0.72, 0.8, 0.86, 0.94, 1.0, 1.0, 1.0, 1.0, 0.92, 0.86, 0.9, 0.92, 0.86, 0.8])
	# lobed, crinkled margin (a smooth wavy disc reads as a paper cut-out)
	var wav := func(a: float) -> float:
		return 1.0 + 0.12 * sin(a * 3.0 + ph) + 0.06 * sin(a * 7.0 + ph * 1.3) + 0.035 * sin(a * 13.0 + ph * 0.7) + 0.02 * sin(a * 23.0 + ph * 2.1)
	var part := _lathe(prof, 48, wav, Vector2(0.0, 1.0), 99, ao)
	# ruffle the rim up and down at two scales
	var pos: PackedVector3Array = part["pos"]
	for i in pos.size():
		var p := pos[i]
		var r := Vector2(p.x, p.z).length()
		var a := atan2(p.z, p.x)
		pos[i].y += r * r * (0.05 * sin(a * 5.0 + ph) + 0.025 * sin(a * 11.0 + ph * 1.7))
	part["pos"] = pos
	return _commit([part])

## Table coral on a short stalk (reef top).
static func table(seed: int) -> ArrayMesh:
	var ph := float(seed) * 1.9
	var prof := [Vector3(0.16, -0.15, 0.0), Vector3(0.12, 0.3, 0.1), Vector3(0.18, 0.46, 0.2), Vector3(0.45, 0.53, 0.45),
		Vector3(0.85, 0.58, 0.85), Vector3(0.97, 0.61, 0.97), Vector3(1.0, 0.64, 1.0), Vector3(0.97, 0.675, 1.0),
		Vector3(0.88, 0.685, 0.9), Vector3(0.6, 0.675, 0.6), Vector3(0.0, 0.665, 0.0)]
	var ao := PackedFloat32Array([0.35, 0.4, 0.45, 0.5, 0.65, 0.85, 1.0, 1.0, 1.0, 0.97, 0.92])
	var wav := func(a: float) -> float: return 1.0 + 0.1 * sin(a * 4.0 + ph) + 0.05 * sin(a * 9.0 + ph)
	return _commit([_lathe(prof, 26, wav, Vector2(-0.15, 0.55), 99, ao)])

## Branching sea rods / whips: a few stems curving up from one holdfast, each with `side` side branches.
static func bush(seed: int, stems_n := 5, length := 1.0, thick := 1.0, side := Vector2i(1, 2)) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var parts: Array = []
	for s in stems_n:
		var dir := Vector3(rng.randf_range(-0.6, 0.6), 1.0, rng.randf_range(-0.6, 0.6)).normalized()
		var pts := _bent(Vector3.ZERO, dir, length * rng.randf_range(0.65, 1.0), rng, 9)
		parts.append(_tube_part(pts, 0.03 * thick, 0.011 * thick))
		for b in rng.randi_range(side.x, side.y):
			var at := rng.randi_range(2, 5)
			var bd := (dir + Vector3(rng.randf_range(-0.8, 0.8), 0.3, rng.randf_range(-0.8, 0.8))).normalized()
			var bp := _bent(pts[at], bd, length * rng.randf_range(0.3, 0.5), rng, 6)
			parts.append(_tube_part(bp, 0.019 * thick, 0.009 * thick))
	return _commit(parts)

## Whip corals: 3-6 long unbranched whips from one holdfast, gently curving and corkscrewing (1 unit tall).
static func whips(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var parts: Array = []
	var n := rng.randi_range(3, 6)
	for s in n:
		var dir := Vector3(rng.randf_range(-0.35, 0.35), 1.0, rng.randf_range(-0.35, 0.35)).normalized()
		var length := rng.randf_range(0.6, 1.0)
		var pts := PackedVector3Array()
		var p := Vector3(rng.randf_range(-0.03, 0.03), 0.0, rng.randf_range(-0.03, 0.03))
		var d := dir
		var spin := rng.randf_range(0.6, 1.4) * (1.0 if rng.randf() < 0.5 else -1.0)
		var seg := 14
		for i in seg:
			pts.append(p)
			var f := float(i) / (seg - 1)
			# droop and corkscrew toward the tip
			d = (d + Vector3(sin(f * 7.0 * spin + s) * 0.12, -0.05 * f, cos(f * 7.0 * spin + s) * 0.12)).normalized()
			p += d * length / (seg - 1)
		parts.append(_tube_part(pts, 0.016, 0.006))
	return _commit(parts)

## Gorgonian / black-coral tree (~1 unit tall): a short trunk, 3-5 primary branches fanning out and curving up,
## each with alternating (pinnate) side branches that carry short twigs. flat = how much the crown keeps to one plane
## (a gorgonian grows across the current; a black-coral bush is rounder); spread = fan angle (rad); dens = twig density.
static func tree(seed: int, flat := 0.85, spread := 1.9, dens := 1.0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var parts: Array = []
	var tr := _curve(Vector3.ZERO, Vector3(rng.randf_range(-0.1, 0.1), 1.0, 0.0).normalized(), 0.16, 3, 0.0, 0.05, flat, rng)
	parts.append(_tube_part(tr, 0.045, 0.04, 5))
	var top := tr[tr.size() - 1]
	var npri := rng.randi_range(3, 5)
	for k in npri:
		var a := (float(k) / (npri - 1) - 0.5) * spread * rng.randf_range(0.85, 1.15) + rng.randf_range(-0.15, 0.15)
		var d := Vector3(sin(a), cos(a), rng.randf_range(-1.0, 1.0) * (1.0 - flat) * 0.9).normalized()
		var pri := _curve(top, d, rng.randf_range(0.6, 0.9) * (1.0 - 0.25 * absf(a)), 8, 0.07, 0.08, flat, rng)
		parts.append(_tube_part(pri, 0.032, 0.008, 5))
		var nsec := int(rng.randi_range(6, 9) * dens)
		for j in nsec:
			var t := 0.2 + 0.75 * j / nsec
			var fi := t * 7.0
			var i0 := mini(int(fi), 6)
			var base := pri[i0].lerp(pri[i0 + 1], fi - i0)
			var tan := (pri[i0 + 1] - pri[i0]).normalized()
			var side := tan.cross(Vector3.BACK).normalized() if flat > 0.5 else Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
			var sgn := 1.0 if j % 2 == 0 else -1.0
			var sd := (tan * 0.55 + side * sgn * 0.8 + Vector3(0.0, 0.35, rng.randf_range(-0.3, 0.3) * (1.0 - flat))).normalized()
			var sec := _curve(base, sd, rng.randf_range(0.14, 0.3) * (1.1 - 0.5 * t), 4, 0.12, 0.15, flat, rng)
			parts.append(_tube_part(sec, 0.016, 0.005, 4))
			for m in rng.randi_range(1, 3):
				var fj := rng.randf_range(0.3, 0.9) * 3.0
				var i2 := mini(int(fj), 2)
				var b2 := sec[i2].lerp(sec[i2 + 1], fj - i2)
				var t2 := (sec[i2 + 1] - sec[i2]).normalized()
				var td := (t2 * 0.6 + Vector3(rng.randf_range(-0.6, 0.6), 0.4, rng.randf_range(-0.6, 0.6) * (1.0 - flat))).normalized()
				parts.append(_tube_part(_curve(b2, td, rng.randf_range(0.06, 0.12), 3, 0.1, 0.2, flat, rng), 0.008, 0.003, 3))
	return _commit(parts)

## Points along a gently bending, jittered curve (the jitter keeps to the crown plane by `flat`).
static func _curve(start: Vector3, dir: Vector3, length: float, n: int, bend: float, jit: float, flat: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var p := start
	var d := dir
	for i in n:
		pts.append(p)
		d = (d + Vector3(rng.randf_range(-jit, jit), bend, rng.randf_range(-jit, jit) * (1.0 - flat))).normalized()
		p += d * length / (n - 1)
	return pts

static func _bent(start: Vector3, dir: Vector3, length: float, rng: RandomNumberGenerator, n: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var p := start
	var d := dir
	for i in n:
		pts.append(p)
		d = (d + Vector3(rng.randf_range(-0.25, 0.25), 0.12, rng.randf_range(-0.25, 0.25))).normalized()
		p += d * length / (n - 1)
	return pts

## Tapered tube along points; r = AO ramp, g = radius / TUBE_R_MAX, b = height (sway weight).
static func _tube_part(pts: PackedVector3Array, r0: float, r1: float, sides := 5) -> Dictionary:
	var pos := PackedVector3Array(); var col := PackedColorArray(); var idx := PackedInt32Array()
	var n := pts.size()
	var side := Vector3.RIGHT
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		side = (side - t * side.dot(t))
		if side.length() < 0.01: side = t.cross(Vector3.FORWARD)
		side = side.normalized()
		var up := t.cross(side)
		var f := float(i) / (n - 1)
		var r := lerpf(r0, r1, f) * (0.15 if i == n - 1 else 1.0)
		for k in sides:
			var a := TAU * k / sides
			pos.append(pts[i] + (side * cos(a) + up * sin(a)) * r)
			col.append(Color(lerpf(0.6, 1.0, f), clampf(r / TUBE_R_MAX, 0.0, 1.0), clampf(pts[i].y, 0.0, 1.0)))
	for i in n - 1:
		for k in sides:
			var a := i * sides + k
			var b := i * sides + (k + 1) % sides
			idx.append_array([a, a + sides, b, b, a + sides, b + sides])
	return {"pos": pos, "col": col, "idx": idx}

## Gorgonian sea fan: a flat fan of triangles, the lattice is cut in reef_fan.gdshader.
static func fan() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 18
	for k in segs:
		var a0 := lerpf(-1.25, 1.25, float(k) / segs)
		var a1 := lerpf(-1.25, 1.25, float(k + 1) / segs)
		for v in [Vector2.ZERO, Vector2(sin(a0), cos(a0)), Vector2(sin(a1), cos(a1))]:
			st.set_normal(Vector3(0, 0, 1))
			st.set_uv(v)
			st.add_vertex(Vector3(v.x, v.y, 0.0))
	return st.commit()
