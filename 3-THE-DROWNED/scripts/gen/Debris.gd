class_name Debris
extends RefCounted
## Human-scale wreck debris. Each function appends to a MeshBuilder at transform xf (metres, y up,
## origin on the ground) and leaves mb.xf at identity.


static func crate(mb: MeshBuilder, xf: Transform3D, size := Vector3(1.2, 1.0, 1.0)) -> void:
	mb.xf = xf
	mb.color = Color(0.9, 0.0, 0.3, 0.7)
	mb.box(Vector3(0, size.y * 0.5, 0), size * 0.94)
	var t := minf(size.x, size.z) * 0.07
	for y: float in [t, size.y * 0.5, size.y - t]:
		mb.box(Vector3(0, y, 0), Vector3(size.x, t * 1.4, size.z))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			mb.box(Vector3(sx * (size.x - t) * 0.5, size.y * 0.5, sz * (size.z - t) * 0.5), Vector3(t, size.y, t))
	mb.xf = Transform3D.IDENTITY


## Admiralty anchor of height s: shank, stock with ball ends, ring, curved arms and flukes.
## Returns the ring position (world).
static func anchor(mb: MeshBuilder, xf: Transform3D, s := 1.8) -> Vector3:
	mb.xf = xf
	mb.color = Color(0.9, 0.0, 0.7, 0.4)
	var r := s * 0.04
	mb.cylinder(Vector3(0, 0.02 * s, 0), Vector3(0, 0.95 * s, 0), r * 1.2, r, 8)
	mb.cylinder(Vector3(0, 0.82 * s, -0.45 * s), Vector3(0, 0.82 * s, 0.45 * s), r * 0.7, r * 0.7, 8)
	for sz: float in [-1.0, 1.0]:
		mb.sphere(Vector3(0, 0.82 * s, sz * 0.47 * s), r * 1.1, 8)
	mb.torus(Vector3(0, 1.04 * s, 0), Vector3(0, 0, 1), 0.08 * s, 0.017 * s, 12, 6)
	var arm := PackedVector3Array()
	for i in 9:
		var x := lerpf(-0.42, 0.42, float(i) / 8.0) * s
		arm.append(Vector3(x, 0.03 * s + 1.6 * x * x / s, 0))
	Rope.tube(arm, r * 0.9, 8, mb)
	for sx: float in [-1.0, 1.0]:
		var c := Vector3(sx * 0.37 * s, 0.27 * s, 0)
		mb.box(c, Vector3(0.035 * s, 0.26 * s, 0.22 * s), Basis(Vector3(0, 0, 1), -sx * 0.6))
	mb.xf = Transform3D.IDENTITY
	return xf * Vector3(0, 1.12 * s, 0)


## Mooring buoy of radius r with a band and eyes; returns the bottom eye (world).
static func buoy(mb: MeshBuilder, xf: Transform3D, r := 0.6) -> Vector3:
	mb.xf = xf
	mb.color = Color(1.0, 0.0, 0.4, 0.6)
	mb.sphere(Vector3.ZERO, r, 14, Vector3(1, 0.9, 1))
	mb.torus(Vector3.ZERO, Vector3.UP, r * 1.0, r * 0.07, 20, 6)
	mb.torus(Vector3(0, r * 0.98, 0), Vector3(1, 0, 0), r * 0.16, r * 0.04, 10, 5)
	mb.torus(Vector3(0, -r * 0.98, 0), Vector3(1, 0, 0), r * 0.16, r * 0.04, 10, 5)
	mb.xf = Transform3D.IDENTITY
	return xf * Vector3(0, -r * 1.1, 0)


## Ship propeller (blades twisted on a hub along X); blade 0 is bent toward +X by `bent`.
static func propeller(mb: MeshBuilder, xf: Transform3D, dia := 1.7, blades := 4, bent := 0.7) -> void:
	mb.xf = xf
	mb.color = Color(0.9, 0.0, 0.2, 0.5)
	var R := dia * 0.5
	var hr := R * 0.18
	mb.cylinder(Vector3(-hr * 1.4, 0, 0), Vector3(hr * 1.4, 0, 0), hr, hr * 0.85, 12)
	mb.sphere(Vector3(hr * 1.4, 0, 0), hr * 0.8, 10)
	var ex := Vector3(1, 0, 0)
	for b in blades:
		var a0 := TAU * float(b) / float(blades)
		var er := Vector3(0, cos(a0), sin(a0))
		var et := Vector3(0, -sin(a0), cos(a0))
		var rings := []
		var uu := PackedFloat32Array()
		for i in 7:
			var t := float(i) / 6.0
			var rad := lerpf(hr * 0.8, R, t)
			var chord := R * lerpf(0.5, 0.22, t * t) * (1.0 if t < 0.95 else 0.55)
			var pt := lerpf(0.95, 0.4, t)
			var cd := et * cos(pt) + ex * sin(pt)
			var td := -et * sin(pt) + ex * cos(pt)
			var curl := (bent * pow(maxf(t - 0.35, 0.0), 2.0) * R * 2.2) if b == 0 else 0.0
			var c := er * rad + ex * curl + et * (R * 0.12 * t * t)
			var ring := PackedVector3Array()
			for j in 6:
				var ang := TAU * float(j) / 6.0
				ring.append(c + cd * cos(ang) * chord * 0.5 + td * sin(ang) * chord * 0.07)
			rings.append(ring)
			uu.append(rad)
		mb.grid(rings, uu, PackedFloat32Array([0, 0.1, 0.2, 0.3, 0.4, 0.5]), true, true)
		mb.cap(rings[6], er)
	mb.xf = Transform3D.IDENTITY


## Net draped on the ground and over bumps ([top centre (world), flat radius, fall-off k]) and over any rock under
## it (Rocks.placed): a diamond mesh (the strands run diagonally to its edges), jittered, with torn holes, a ragged
## outline, folds, strands sagging between the knots, patches sunk under the sand, and one corner lifted by its
## floats. gather > 0 bunches the long sides toward the middle (a collapsed trawl body). Returns the float
## positions.
static func net(mb: MeshBuilder, center: Vector3, size: Vector2, yaw: float, bumps: Array, cell := 0.18,
		radius := 0.011, lift := 1.3, seed := 3, gather := 0.0, tear := 0.03, fold_amp := 0.16) -> PackedVector3Array:
	var bs := Basis(Vector3.UP, yaw)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var nz := FastNoiseLite.new()
	nz.seed = seed
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 1.0
	var ph := Vector2(rng.randf() * TAU, rng.randf() * TAU)
	var all := bumps.duplicate()
	var reach := maxf(size.x, size.y) * 0.75
	for r: Array in Rocks.placed:
		var c: Vector3 = r[0]
		var rad: float = r[1]
		if Vector2(c.x - center.x, c.z - center.z).length() < reach + rad:
			all.append([c + Vector3(0, rad * 0.5, 0), rad * 0.3, 1.2 / maxf(rad, 0.2)])
	var half := Vector2(size.x, size.y) * 0.5
	var R := half.length() + cell
	var m := int(R * 2.0 / cell) + 1
	var ca := cos(PI * 0.25)
	var grid := []                     # [m][m] of Vector3 or null (a hole / outside)
	for i in m:
		var row := []
		for j in m:
			var u := -R + float(i) * cell
			var v := -R + float(j) * cell
			var lx := (u - v) * ca
			var lz := (u + v) * ca
			# ragged outline and torn holes
			var edge := 1.0 + 0.1 * nz.get_noise_2d(lx * 0.6 + 40.0, lz * 0.6)
			var hole := nz.get_noise_2d(lx * 0.45 + 90.0, lz * 0.45 - 30.0)
			if absf(lx) > half.x * edge or absf(lz) > half.y * edge or hole > 0.62 - tear * 2.0:
				row.append(null)
				continue
			var fx := lx / size.x + 0.5
			var fz := lz / size.y + 0.5
			lx *= 1.0 - gather * (0.5 + 0.5 * sin(fz * 6.0 + ph.x) * sin(fz * 2.3 + ph.y))
			var jit := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * cell * 0.28
			var w := center + bs * Vector3(lx, 0, lz) + jit
			var g := Terrain.height(w.x, w.z) + 0.03
			var y := g
			for bb: Array in all:
				var c: Vector3 = bb[0]
				var d := maxf(Vector2(w.x - c.x, w.z - c.z).length() - float(bb[1]), 0.0)
				# over the top of a crate or a rock, then a steep sag down its side to the ground
				y = maxf(y, c.y + 0.02 - float(bb[2]) * 2.2 * d * d - 0.9 * d)
			# folds and creases along noisy ridges (bunched nets fold more)
			var fo := 1.0 - absf(nz.get_noise_2d(lx * 0.35 + 7.0, lz * 0.22 - 3.0))
			y += fo * fo * fo * fold_amp * (1.0 + gather * 2.0)
			# one corner lifted by its floats, swaying up into the water
			var cd := Vector2(1.0 - fx, 1.0 - fz).length()
			y += lift * pow(maxf(1.0 - cd / 0.75, 0.0), 2.0)
			y = maxf(y, g)
			# where it lies flat, patches sink under the sand
			if y < g + 0.05 and nz.get_noise_2d(lx * 0.5 - 60.0, lz * 0.5 + 15.0) > 0.3:
				y = g - 0.06
			row.append(Vector3(w.x, y, w.z))
		grid.append(row)
	mb.color = Color(0.32, 0.0, 0.2, 0.8)
	for i in m:
		var run := []
		for j in m:
			run.append(grid[i][j])
		_net_line(mb, run, radius, tear, rng)
	for j in m:
		var run := []
		for i in m:
			run.append(grid[i][j])
		_net_line(mb, run, radius, tear, rng)
	var floats := PackedVector3Array()
	if lift > 0.0:
		for k in 4:
			var want := center + bs * Vector3(half.x * 0.95, 0, half.y * (0.95 - 0.16 * float(k)))
			var best := Vector3.ZERO
			var bd := 1e9
			for row: Array in grid:
				for q in row:
					if q == null:
						continue
					var dd := Vector2((q as Vector3).x - want.x, (q as Vector3).z - want.z).length()
					if dd < bd:
						bd = dd
						best = q
			if bd < 1e8:
				floats.append(best + Vector3(0, 0.1, 0))
	return floats


## Runs of knots (null = a hole) as strands sagging a little between the knots, broken at the holes and at
## random torn segments.
static func _net_line(mb: MeshBuilder, knots: Array, radius: float, tear: float, rng: RandomNumberGenerator) -> void:
	var run := PackedVector3Array()
	for k in knots.size():
		var q = knots[k]
		if q == null or (run.size() > 0 and rng.randf() < tear):
			if run.size() > 1:
				Rope.tube(run, radius, 3, mb)
			run = PackedVector3Array()
			if q == null:
				continue
		var p: Vector3 = q
		if run.size() > 0:
			var a := run[run.size() - 1]
			var mid := (a + p) * 0.5
			var g := Terrain.height(mid.x, mid.z) + 0.03
			mid.y = maxf(mid.y - 0.025, minf(g, mid.y))
			run.append(mid)
		run.append(p)
	if run.size() > 1:
		Rope.tube(run, radius, 3, mb)


## Thin strand through pts, broken at random segments (torn mesh).
static func _strands(mb: MeshBuilder, pts: PackedVector3Array, radius: float, tear: float, rng: RandomNumberGenerator) -> void:
	var run := PackedVector3Array()
	for k in pts.size():
		run.append(pts[k])
		if k < pts.size() - 1 and rng.randf() < tear:
			if run.size() > 1:
				Rope.tube(run, radius, 3, mb)
			run = PackedVector3Array()
	if run.size() > 1:
		Rope.tube(run, radius, 3, mb)


## Stockless (hall) anchor of shank length s: crown at the origin, shank up +Y, the flukes spread in +-X and
## angled away from the shank, flat in the XY plane. Returns the shackle (world).
static func anchor_stockless(mb: MeshBuilder, xf: Transform3D, s := 2.0) -> Vector3:
	var oc := mb.color
	mb.xf = xf
	mb.color = Color(0.85, 0.0, 0.7, 0.3)
	var t := s * 0.07
	mb.cylinder(Vector3(0, s * 0.1, 0), Vector3(0, s, 0), t * 1.15, t * 0.8, 6)
	mb.box(Vector3(0, s * 0.08, 0), Vector3(s * 0.44, s * 0.17, t * 2.4))
	for sx: float in [-1.0, 1.0]:
		mb.box(Vector3(sx * s * 0.24, s * 0.31, 0), Vector3(s * 0.2, s * 0.5, t * 1.3), Basis(Vector3(0, 0, 1), -sx * 0.55))
		mb.box(Vector3(sx * s * 0.39, s * 0.56, 0), Vector3(s * 0.08, s * 0.1, t * 1.6), Basis(Vector3(0, 0, 1), -sx * 0.55))
	mb.torus(Vector3(0, s * 1.06, 0), Vector3(0, 0, 1), s * 0.07, s * 0.022, 10, 5)
	mb.xf = Transform3D.IDENTITY
	mb.color = oc
	return xf * Vector3(0, s * 1.1, 0)


## Trawl door (otter board): a curved steel plate with a shoe, lying at xf (local: plate in XY, Y up).
static func otter_board(mb: MeshBuilder, xf: Transform3D, size := Vector2(2.6, 1.3)) -> Vector3:
	mb.xf = xf
	mb.color = Color(0.85, 0.0, 0.8, 0.4)
	for k in 3:
		var a := (float(k) - 1.0) * 0.18
		mb.box(Vector3(sin(a) * size.x * 0.34, size.y * 0.5, cos(a) * 0.12 - 0.12), Vector3(size.x * 0.34, size.y, 0.06),
			Basis(Vector3.UP, a))
	mb.box(Vector3(0, 0.05, 0), Vector3(size.x * 1.02, 0.1, 0.2))
	mb.torus(Vector3(size.x * 0.1, size.y * 0.55, 0.12), Vector3(0, 0, 1), 0.09, 0.025, 8, 4)
	mb.xf = Transform3D.IDENTITY
	return xf * Vector3(size.x * 0.1, size.y * 0.55, 0.2)


## Double mooring bitts (a bollard torn off a deck) on a base plate; returns the top of the first post.
static func bollard(mb: MeshBuilder, xf: Transform3D, r := 0.3) -> Vector3:
	mb.xf = xf
	mb.color = Color(0.85, 0.0, 0.8, 0.4)
	mb.box(Vector3(0, r * 0.15, 0), Vector3(r * 6.0, r * 0.3, r * 2.6))
	for sx: float in [-1.0, 1.0]:
		mb.cylinder(Vector3(sx * r * 1.6, r * 0.3, 0), Vector3(sx * r * 1.6, r * 2.6, 0), r, r, 12, true)
		mb.cylinder(Vector3(sx * r * 1.6, r * 2.6, 0), Vector3(sx * r * 1.6, r * 2.8, 0), r * 1.25, r * 1.25, 12, true)
	mb.xf = Transform3D.IDENTITY
	return xf * Vector3(-r * 1.6, r * 2.0, 0)


## A broken mast lying on the ground from a to b (radius r), with a crosstree and a snapped, splintered end at b.
static func fallen_mast(mb: MeshBuilder, a: Vector3, b: Vector3, r: float) -> void:
	mb.color = Color(0.85, 0.0, 0.8, 0.5)
	mb.cylinder(a, b, r, r * 0.8, 10, true)
	var ax := (b - a).normalized()
	var side := ax.cross(Vector3.UP).normalized()
	var c := a.lerp(b, 0.72)
	mb.cylinder(c - side * r * 9.0 + Vector3(0, r * 2.0, 0), c + side * r * 9.0 + Vector3(0, r * 0.5, 0), r * 0.35, r * 0.35, 6, true)
	for k in 5:
		var d := Basis(ax, TAU * float(k) / 5.0) * side
		mb.cylinder(b - ax * r * 0.3, b + ax * r * (0.8 + 0.5 * float(k % 3)) + d * r * 0.5, r * 0.22, r * 0.04, 4, false)


## A ghost net hanging from a floated headline down to the slope and lying on it: columns every `cell` metres
## along the headline drop toward the ground (billowing downstream along `drift`), rows of mesh across them.
## Returns the float positions along the headline.
static func ghost_net(mb: MeshBuilder, head: PackedVector3Array, drift: Vector3, cell := 0.45, radius := 0.012,
		seed := 7) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# resample the headline every `cell` metres
	var hp := PackedVector3Array([head[0]])
	var need := cell
	var cur := head[0]
	var hi := 0
	while hi < head.size() - 1:
		var nxt := head[hi + 1]
		var seg := cur.distance_to(nxt)
		if seg >= need and seg > 1e-6:
			cur = cur.lerp(nxt, need / seg)
			hp.append(cur)
			need = cell
		else:
			need -= seg
			cur = nxt
			hi += 1
	var cols := []
	var nrows := 0
	var ph := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	for i in hp.size():
		var h := hp[i]
		var g := Terrain.height(h.x, h.z)
		# parts of the curtain have collapsed: it hangs to the ground in some places, folds over in others
		var fi := float(i)
		var col_k := clampf(0.55 + 0.45 * sin(fi * 0.17 + ph) * sin(fi * 0.071 + ph2), 0.25, 1.0)
		var hh := maxf((h.y - g) * col_k, 0.3)
		var top := Vector3(h.x, g + hh, h.z)
		var n := int(hh / cell) + 4
		nrows = maxi(nrows, n)
		var col := PackedVector3Array()
		var bill := 0.5 + 0.5 * sin(fi * 0.21 + ph)
		for r in n + 1:
			var w := float(r) / float(n - 3)
			var p := top + drift * (sin(minf(w, 1.0) * PI) * hh * 0.4 * bill + maxf(w - 1.0, 0.0) * hh * 0.9)
			p.y = top.y - hh * minf(w, 1.0)
			p += Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.5, 0.5), rng.randf_range(-1.0, 1.0)) * cell * 0.3
			p.y = maxf(p.y, Terrain.height(p.x, p.z) + 0.05)
			col.append(p)
		cols.append(col)
	mb.color = Color(0.32, 0.0, 0.2, 0.8)
	for c: PackedVector3Array in cols:
		_strands(mb, c, radius, 0.05, rng)
	for r in nrows + 1:
		var row := PackedVector3Array()
		for c: PackedVector3Array in cols:
			if r < c.size():
				row.append(c[r])
			elif row.size() > 1:
				_strands(mb, row, radius, 0.04, rng)
				row = PackedVector3Array()
		if row.size() > 1:
			_strands(mb, row, radius, 0.04, rng)
	var floats := PackedVector3Array()
	var k := 0
	while k < hp.size():
		floats.append(hp[k] + Vector3(0, 0.14, 0))
		k += 3
	return floats


## Concrete weight block with an iron eye on top (eye into `steel`); returns the eye (world).
static func weight_block(mb: MeshBuilder, steel: MeshBuilder, xf: Transform3D, size := Vector3(1.3, 0.85, 1.3)) -> Vector3:
	mb.xf = xf
	mb.color = Color(0.85, 0.0, 0.1, 0.8)
	mb.box(Vector3(0, size.y * 0.5, 0), size)
	mb.box(Vector3(0, size.y + 0.04, 0), Vector3(size.x * 0.8, 0.08, size.z * 0.8))
	mb.xf = Transform3D.IDENTITY
	steel.xf = xf
	steel.color = Color(0.9, 0.0, 0.7, 0.3)
	steel.torus(Vector3(0, size.y + 0.17, 0), Vector3(0, 0, 1), 0.12, 0.025, 12, 5)
	steel.xf = Transform3D.IDENTITY
	return xf * Vector3(0, size.y + 0.27, 0)
