class_name Rocks
extends RefCounted
## Boulders and rock chunks (scale and parallax cues): low-poly displaced variants of distinct kinds (rounded
## boulders, blocky broken ones, an elongated one, knobbly weathered ones, a slab) drawn as MultiMeshes with
## shaders/rock.gdshader, tilted at random and partly buried in the ground. build() scatters them on the wreck
## slope (denser on the talus below the hulls) and on the floor over the last 250 m before the door, never within
## CLEAR metres of the walk. Rocks.placed lists every rock as [centre (world), radius] after build() (the line's
## stays and the nets keep clear of them / drape over them).
## Each rock darkens the ground round its base (a contact shadow: without it they looked pasted on the sand):
## build() bakes the rings into two small L8 maps over the rocks' ground and hands them to the seabed material
## (terrain.gdshader rock_ao_a / rock_ao_b and their rects).

const VARIANTS := 8                      # the last one is the slab
const CLEAR := 3.0                       # metres between any rock and the walk (3D)
const AO_CELL := 0.2                     # metres per texel of the contact maps
const AO_LAT := 140.0                    # slope rocks further than this from the walk get none (never seen close)

static var placed: Array = []
static var _meshes: Array = []
static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = Mats.make("rock")
	return _mat


## Unit rock variant (radius ~1, base near y = -0.3): a subdivided icosahedron displaced by noise, cut by a
## few planes for flat faces, squashed. Smooth shaded with creases kept at the cut faces (a flat-shaded
## low-poly rock reads as a cut gem up close). Vertex COLOR.r = occlusion toward the base.
static func mesh(v: int) -> ArrayMesh:
	if _meshes.size() > v and _meshes[v]:
		return _meshes[v]
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + v * 17
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t),
		Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1),
		Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for i in verts.size():
		verts[i] = (verts[i] as Vector3).normalized()
	# two subdivisions (320 faces)
	var f2 := faces
	for _sub in 2:
		var mid := {}
		var nf := []
		for f: Array in f2:
			var m := []
			for e in 3:
				var a: int = f[e]
				var b: int = f[(e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not mid.has(key):
					verts.append(((verts[a] as Vector3) + (verts[b] as Vector3)).normalized())
					mid[key] = verts.size() - 1
				m.append(mid[key])
			nf.append([f[0], m[0], m[2]])
			nf.append([f[1], m[1], m[0]])
			nf.append([f[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		f2 = nf
	var nz := FastNoiseLite.new()
	nz.seed = 77 + v
	nz.frequency = 0.9
	# kinds: rounded boulders (0, 4), blocky ones broken along many planes (1, 5), an elongated one (2), knobbly
	# weathered ones (3, 6), the slab (last): identical smooth lumps read as eggs or soap
	var kind := v if v < VARIANTS - 1 else -1
	var amp := 0.22
	var amp2 := 0.08
	var cuts := 3 + v % 3
	var cut_r := Vector2(0.55, 0.85)
	var squash := Vector3(rng.randf_range(0.85, 1.25), rng.randf_range(0.5, 0.8), rng.randf_range(0.8, 1.15))
	match kind:
		0, 4:
			# rounded, but lumpy and broken: smooth ones read as pills or eggs
			amp = 0.27
			amp2 = 0.12
			cuts = 4 + v % 2
		1, 5:
			amp = 0.1
			amp2 = 0.05
			cuts = 6 + v % 3
			cut_r = Vector2(0.4, 0.68)
			squash.y = rng.randf_range(0.65, 0.9)
		2:
			squash = Vector3(1.45, 0.62, 0.78)
			cuts = 5
		3, 6:
			amp = 0.3
			amp2 = 0.15
			cuts = 2 + v % 2
		-1:
			squash = Vector3(1.4, 0.26, 1.0)       # a flat slab / shard
	var planes := []
	for k in cuts:
		planes.append([Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)).normalized(),
			rng.randf_range(cut_r.x, cut_r.y)])
	for i in verts.size():
		var p: Vector3 = verts[i]
		p *= 1.0 + amp * nz.get_noise_3dv(p * 1.3) + amp2 * nz.get_noise_3dv(p * 4.0 + Vector3(9, 3, 1))
		for pl: Array in planes:
			var n: Vector3 = pl[0]
			var c: float = pl[1]
			var dd := p.dot(n) - c
			if dd > 0.0:
				p -= n * dd
		verts[i] = p * squash
	# face normals, then area-weighted vertex normals; a corner keeps its face normal where the faces meet
	# at a crease (the plane cuts), so the rock is rounded but its broken faces stay crisp
	var fn := []
	var vn := []
	vn.resize(verts.size())
	vn.fill(Vector3.ZERO)
	for f: Array in f2:
		var a: Vector3 = verts[f[0]]
		var b: Vector3 = verts[f[1]]
		var c: Vector3 = verts[f[2]]
		var cr := (b - a).cross(c - a)
		if cr.dot(a + b + c) < 0.0:
			cr = -cr
		fn.append(cr.normalized())
		for k in 3:
			vn[f[k]] += cr
	var cos_crease := cos(deg_to_rad(38.0))
	var mb := MeshBuilder.new()
	for fi in f2.size():
		var f: Array = f2[fi]
		var n: Vector3 = fn[fi]
		var ids := []
		for k in 3:
			var p: Vector3 = verts[f[k]]
			var sn: Vector3 = (vn[f[k]] as Vector3).normalized()
			var nk := sn if sn.dot(n) > cos_crease else n
			ids.append(mb.vert(p, nk, Vector2.ZERO, Color(_occ(p.y, squash.y), 0, 0, 0)))
		mb.tri(ids[0], ids[1], ids[2])
	while _meshes.size() <= v:
		_meshes.append(null)
	_meshes[v] = mb.build()
	return _meshes[v]


static func _occ(y: float, h: float) -> float:
	return clampf(0.45 + 0.55 * (y / h + 0.6), 0.35, 1.0)


## Draws rock transforms (Array of [variant, Transform3D]) as one MultiMesh per variant under parent.
static func draw(parent: Node3D, items: Array, name := "Rocks", shadows := true) -> int:
	var lists := []
	for v in VARIANTS:
		lists.append([])
	for it: Array in items:
		lists[int(it[0])].append(it[1])
	var n := 0
	for v in VARIANTS:
		var xfs: Array = lists[v]
		if xfs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh(v)
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			mm.set_instance_custom_data(i, Color(fposmod(float(i) * 0.618 + float(v) * 0.31, 1.0), 0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s%d" % [name, v]
		mmi.multimesh = mm
		mmi.set_meta("xforms", xfs)       # for tools_gd/placement_gate.gd (headless has no multimesh buffers)
		mmi.material_override = material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
		n += xfs.size()
	return n


## A rock of radius r resting on the ground at (x, z): tilted toward the ground normal, sunk ~30 %.
static func place(rng: RandomNumberGenerator, x: float, z: float, r: float, slabs := true) -> Array:
	var v := rng.randi() % (VARIANTS if slabs else VARIANTS - 1)
	var nrm := Terrain.normal(x, z, maxf(r, 1.0))
	var up := Vector3.UP.slerp(nrm, rng.randf_range(0.75, 1.0))
	var ta := rng.randf() * TAU
	# boulders lean at random; a slab only a little (tilted up, its unlit underside read as a dark hole)
	var tilt := rng.randf_range(-0.32, 0.32) * (0.3 if v == VARIANTS - 1 else 1.0)
	var b := Basis(Vector3(cos(ta), 0.0, sin(ta)), tilt) * Basis(Vector3.UP, rng.randf() * TAU)
	var ax := Vector3.UP.cross(up)
	if ax.length_squared() > 1e-6:
		b = Basis(ax.normalized(), Vector3.UP.angle_to(up)) * b
	var sc := r * rng.randf_range(0.85, 1.15)
	# sunk along the ground normal, deeper on steep ground so the downslope edge never floats
	var slope := 1.0 - nrm.y
	var sink := sc * (rng.randf_range(0.15, 0.3) + slope * 0.8)
	var g := Vector3(x, Terrain.height(x, z), z)
	var xf := Transform3D(b.scaled(Vector3.ONE * sc), g - nrm * sink)
	# no part of the base ring may hang above the ground (uneven ground under big rocks)
	var lift := 0.0
	for k in 8:
		var a := TAU * float(k) / 8.0
		var q := xf * Vector3(cos(a) * 0.75, -0.42, sin(a) * 0.75)
		lift = maxf(lift, q.y - Terrain.height(q.x, q.z) + 0.05 * sc)
	xf.origin.y -= lift
	return [v, xf, Vector3(x, g.y - lift, z)]       # + the ground point it sits on (its contact shadow's centre)


static func _clear(path_pts: PackedVector3Array, p: Vector3, r: float) -> bool:
	for q in path_pts:
		if q.distance_squared_to(p) < pow(r + CLEAR + 0.5, 2.0):
			return false
	return true


## All scattered rocks (built with the terrain). Needs PathDef.main.
static func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Rocks"
	parent.add_child(root)
	placed = []
	var path := PathDef.main
	if path == null:
		return root
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# ---- the wreck slope (beat 2): talus below and around the hulls, parallax near the walk
	var pts := PackedVector3Array()
	var s := 90.0
	while s < 470.0:
		pts.append(path.pos(s))
		s += 2.0
	var hulls := []
	for key: String in Terrain.SHIP_KEYS:
		var ps := Terrain.ship_pose(key)
		hulls.append(ps)
	var items := []
	var tries := 0
	while items.size() < 340 and tries < 20000:
		tries += 1
		var x := rng.randf_range(-720.0, 470.0)
		var z := rng.randf_range(-282.0, -92.0)
		var w := 0.18
		var px := Terrain.path_x(z)
		var lat := absf(x - px)
		w += 0.7 * (1.0 - smoothstep(25.0, 110.0, lat))
		var inside := false
		var talus := 0.0
		for ps: Dictionary in hulls:
			var xf: Transform3D = ps["transform"]
			var L: float = ps["length"]
			var B: float = ps["beam"]
			var lp := xf.affine_inverse() * Vector3(x, xf.origin.y, z)
			var du := maxf(absf(lp.z) - L * 0.5, 0.0)
			var dv := maxf(absf(lp.x) - B * 0.55, 0.0)
			var dd := Vector2(du, dv).length()
			if dd < 1.5:
				inside = true
				break
			talus = maxf(talus, 1.0 - smoothstep(B * 0.3, B * 2.0, dd))
		if inside:
			continue
		w += 1.2 * talus
		if rng.randf() * 2.1 > w:
			continue
		var h := Terrain.height(x, z)
		if h < -300.0:
			continue
		var r := 0.35 + 4.5 * pow(rng.randf(), 3.0) * (1.0 + talus)
		if lat < 30.0:
			r = minf(r, 2.5)
		var it := place(rng, x, z, r, false)
		if not _clear(pts, (it[1] as Transform3D).origin, r * 1.3):
			continue
		items.append(it)
	_register(items)
	_contact_map(items, "a", AO_LAT)
	var n1 := draw(root, items, "SlopeRocks")
	# ---- the floor before the door: the last 250 m, within ~40 m of the line
	pts.clear()
	s = path.length - 270.0
	while s <= path.length:
		pts.append(path.pos(s))
		s += 2.0
	items = []
	tries = 0
	while items.size() < 230 and tries < 20000:
		tries += 1
		var sa := rng.randf_range(path.length - 250.0, path.length)
		var c := path.pos(sa)
		var lat := rng.randf_range(-40.0, 40.0)
		var p := c + path.right(sa) * lat + path.forward_h(sa) * rng.randf_range(-6.0, 6.0)
		var wz := Config.WALL_Z + p.x * p.x / 5000.0
		if p.z < wz + 4.0:
			continue
		if Vector2(p.x - Config.DOOR_POS.x, p.z - Config.DOOR_POS.z).length() < 26.0:
			continue
		var r := 0.22 + 2.4 * pow(rng.randf(), 2.6)
		var it := place(rng, p.x, p.z, r)
		if not _clear(pts, (it[1] as Transform3D).origin, r * 1.3):
			continue
		items.append(it)
	_register(items)
	_contact_map(items, "b")
	var n2 := draw(root, items, "FloorRocks")
	root.set_meta("count", n1 + n2)
	return root


static func _register(items: Array) -> void:
	for it: Array in items:
		var xf: Transform3D = it[1]
		placed.append([xf.origin, xf.basis.get_scale().x * 1.15])


## Contact darkening round the rocks' bases as an L8 map (1 under the rock, a soft ring falling off over
## ~0.06 + 0.14 x the rock's size), set on the seabed material as rock_ao_<slot> with its rect (x0, z0, 1 / width,
## 1 / depth in metres). Rocks further than lat_max from the walk are left out (the map stays small).
static func _contact_map(items: Array, slot: String, lat_max := 1e9) -> void:
	if Terrain.material == null:
		return
	var rocks := []
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for it: Array in items:
		var xf: Transform3D = it[1]
		var sc := xf.basis.get_scale().x
		# the rock's origin is sunk along the slope normal (upslope of the rock seen on the ground): centre the
		# ring on the ground point it was placed on
		var gp: Vector3 = it[2] if it.size() > 2 else xf.origin
		if absf(gp.x - Terrain.path_x(gp.z)) > lat_max:
			continue
		# ... and the visible rock sits a little downslope of that point (its sunk body leans out of the slope)
		var nrm := Terrain.normal(gp.x, gp.z, maxf(sc, 1.0))
		var c := Vector2(gp.x + nrm.x * sc * 0.35, gp.z + nrm.z * sc * 0.35)
		var rf := sc * 0.5
		var fall := 0.06 + sc * 0.14
		var ext := rf + fall * 2.2
		rocks.append([c, rf, fall, ext])
		lo = lo.min(c - Vector2.ONE * ext)
		hi = hi.max(c + Vector2.ONE * ext)
	if rocks.is_empty():
		return
	var w := int(ceil((hi.x - lo.x) / AO_CELL)) + 1
	var h := int(ceil((hi.y - lo.y) / AO_CELL)) + 1
	var data := PackedByteArray()
	data.resize(w * h)
	data.fill(0)
	for r: Array in rocks:
		var c: Vector2 = r[0]
		var rf: float = r[1]
		var inv := 1.0 / float(r[2])
		var ext: float = r[3]
		var i0 := clampi(int((c.x - ext - lo.x) / AO_CELL), 0, w - 1)
		var i1 := clampi(int((c.x + ext - lo.x) / AO_CELL) + 1, 0, w - 1)
		var j0 := clampi(int((c.y - ext - lo.y) / AO_CELL), 0, h - 1)
		var j1 := clampi(int((c.y + ext - lo.y) / AO_CELL) + 1, 0, h - 1)
		for j in range(j0, j1 + 1):
			var dz := lo.y + (float(j) + 0.5) * AO_CELL - c.y
			for i in range(i0, i1 + 1):
				var dx := lo.x + (float(i) + 0.5) * AO_CELL - c.x
				var d := (sqrt(dx * dx + dz * dz) - rf) * inv
				var b := 255 if d <= 0.0 else int(exp(-d * d) * 255.0)
				var k := j * w + i
				if b > data[k]:
					data[k] = b
	var img := Image.create_from_data(w, h, false, Image.FORMAT_L8, data)
	Terrain.material.set_shader_parameter("rock_ao_" + slot, ImageTexture.create_from_image(img))
	Terrain.material.set_shader_parameter("rock_ao_%s_rect" % slot, Vector4(lo.x, lo.y, 1.0 / (float(w) * AO_CELL),
		1.0 / (float(h) * AO_CELL)))
