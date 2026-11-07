extends RefCounted
## Beat 1, the Shallows (s 0-118 m, depth 3-27 m): sunlit teal sand, soft sun shafts, the dive boat at
## the surface, the shot weight tied to the line and a human-scale debris cluster (sizes 1-10 m).
## The small hulls get what Hull.gd's smooth loft lacks up close: the dive boat a keel, spray rails and a fouled
## bottom (from below it read as a featureless lozenge), the capsized rowboat a keel, clinker laps and a gunwale
## (it read as a smooth pill).

const BOAT_SHIFT := Vector3(0.0, 0.0, 5.0)   # keeps the boat hull 10 m clear of the start of the walk
const BOAT_YAW := 75.0
const BOAT_LEN := 9.0
const SHAFT_CLEAR := 18.0                     # shaft axis distance from the walk (half width + 10 m)

var path: PathDef


func build(parent: Node3D) -> void:
	path = PathDef.main
	_shafts(parent)
	_boat(parent)
	var wood := MeshBuilder.new()
	var steel := MeshBuilder.new()
	var stone := MeshBuilder.new()
	var bronze := MeshBuilder.new()
	var paint := MeshBuilder.new()
	var strands := MeshBuilder.new()
	_weight(parent, stone, steel)
	_debris(parent, wood, steel, bronze, paint, strands)
	var wood_c := Palette.RUST.lerp(Palette.BONE, 0.3).darkened(0.4)
	# every piece casts a sun shadow on the bright sand (each builder is one small cluster: its range is exact)
	var parts := [
		[wood, Mats.solid(wood_c, 0.0, 0.55, {"roughness": 0.85}), "Crates"],
		[steel, Mats.solid(Palette.STEEL_DARK, 0.7, 0.35), "Iron"],
		[stone, Mats.solid(Palette.BONE.darkened(0.45), 0.0, 0.6, {"noise_scale": 0.5}), "Concrete"],
		[bronze, Mats.solid(Palette.VERDIGRIS.darkened(0.25), 0.15, 0.25, {"roughness": 0.5}), "Propeller"],
		[paint, Mats.solid(Palette.RUST.lerp(Palette.BONE, 0.15), 0.3, 0.3), "Buoy"],
		[strands, Mats.solid(Color(0.1, 0.13, 0.11), 0.0, 0.45, {"roughness": 0.9}), "Net"],
	]
	for it: Array in parts:
		var mb: MeshBuilder = it[0]
		if mb.tri_count() == 0:
			continue
		var mi := mb.instance(it[1], parent, 160.0)
		mi.name = it[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, Terrain.height(p.x, p.z), p.z)


func _seg_clear(samples: PackedVector3Array, a: Vector3, b: Vector3, d: float) -> bool:
	for p in samples:
		if Geometry3D.get_closest_point_to_segment(p, a, b).distance_squared_to(p) < d * d:
			return false
	return true


## Soft shafts around the start (tops at the surface 10-140 m from the line) + long faint ones over the hulls.
## They come in irregular groups (where the waves above focus the light): one or two broad faint bundles and a
## few thin bright rays at uneven spacing, plus loners, never an even row. Every shaft axis stays SHAFT_CLEAR
## from the walk.
func _shafts(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	var dir := Config.SUN_DIR.normalized()
	var samples := PackedVector3Array()
	var s := 0.0
	while s < 520.0:
		samples.append(path.pos(s))
		s += 4.0
	for pass_i in 2:
		var tops := []
		var widths := PackedFloat32Array()
		var want := 40 if pass_i == 0 else 12
		var ln := 120.0 if pass_i == 0 else 260.0
		var tries := 0
		while tops.size() < want and tries < 3000:
			tries += 1
			var sr := rng.randf_range(-10.0, 130.0) if pass_i == 0 else rng.randf_range(120.0, 430.0)
			var lat := rng.randf_range(10.0, 140.0) if pass_i == 0 else rng.randf_range(20.0, 160.0)
			lat *= 1.0 if rng.randf() < 0.5 else -1.0
			var sc := maxf(sr, 0.0)
			var c := path.pos(sc) + path.forward_h(0.0) * minf(sr, 0.0) + path.right(sc) * lat
			c.y = Config.SURFACE_Y
			# a group: members strung along a random horizontal direction, uneven gaps, mixed widths
			var n := 1 if rng.randf() < 0.3 else rng.randi_range(2, 4)
			var ga := rng.randf() * TAU
			var gd := Vector3(cos(ga), 0.0, sin(ga))
			var off := 0.0
			for k in n:
				var w := rng.randf_range(5.0, 11.0) if k == 0 and rng.randf() < 0.6 else rng.randf_range(2.0, 4.5)
				if pass_i == 1:
					w *= 1.3
				var top := c + gd * off + Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.5, 1.5))
				off += rng.randf_range(2.5, 9.0) * (1.0 + 0.4 * float(k))
				if tops.size() < want and _seg_clear(samples, top, top + dir * ln, SHAFT_CLEAR + w * 0.5):
					tops.append(top)
					widths.append(w)
		if pass_i == 0:
			Atmos.build_shafts(parent, tops, Vector2(55, 120), Vector2(3, 8), 0.3, widths)
		else:
			Atmos.build_shafts(parent, tops, Vector2(150, 260), Vector2(4, 9), 0.1, widths).name = "ShaftsFar"


## The dive boat floating at the surface: keel ~1.2 m down, a dark silhouette in the bright surface. It sits IN
## the surface: shaders/surface.gdshader mirrors its hull in the sheet and draws the meniscus at its waterline
## (Atmos.surface_material), its shadow on the sand is soft (the terrain shader; the shadow map drew a crisp
## ellipse that read as a decal), an anchor line runs from the bow down to the sand and a swim ladder hangs from
## the transom.
func _boat(parent: Node3D) -> void:
	var b := Hull.ship("motorboat", BOAT_LEN, 3, {"shadows": false})
	b.name = "DiveBoat"
	b.rotation = Vector3(0.02, deg_to_rad(BOAT_YAW), 0.035)
	b.position = Config.BOAT_POS + BOAT_SHIFT + Vector3(0, -1.2, 0)
	parent.add_child(b)
	_boat_detail(b)
	var beam := BOAT_LEN * 0.33
	var bow := b.basis * Vector3.FORWARD
	var fh := Vector2(bow.x, bow.z).normalized()
	var c := Vector2(b.position.x, b.position.z)
	if Atmos.surface_material:
		Atmos.surface_material.set_shader_parameter("boat", Vector4(c.x, c.y, fh.x, fh.y))
		Atmos.surface_material.set_shader_parameter("boat_size", Vector4(BOAT_LEN * 0.44, beam * 0.46, 1.25, 0.0))
	if Terrain.material:
		Terrain.material.set_shader_parameter("boat", Vector4(c.x, c.y, fh.x, fh.y))
		Terrain.material.set_shader_parameter("boat_size", Vector2(BOAT_LEN * 0.5, beam * 0.5))
	var steel := MeshBuilder.new()
	var rope := MeshBuilder.new()
	# anchor line: from the bow fairlead through the surface, sagging down to a small anchor 14 m ahead, the
	# last metres a short chain on the sand
	var fair := b.transform * Vector3(0.0, 1.55, -BOAT_LEN * 0.47)
	var fwd := Vector3(fh.x, 0.0, fh.y)
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var ap := _ground(fair + fwd * 14.0 + side * 1.5)
	var cp := _ground(ap - fwd * 3.2 + side * 0.6) + Vector3(0, 0.05, 0)
	var line := PackedVector3Array()
	for i in 25:
		var t := float(i) / 24.0
		line.append(fair.lerp(cp, t) + Vector3(0, -sin(t * PI) * 0.9, 0))
	Rope.tube(line, 0.02, 6, rope)
	# the anchor on its side, shank (ring) toward the boat, one fluke in the sand
	var ring := Debris.anchor(steel, Transform3D(Basis(Vector3.UP, atan2(-fwd.z, fwd.x)) * Basis(Vector3.BACK, 1.3),
		ap + Vector3(0, 0.06, 0)), 0.8)
	var cpts := PackedVector3Array()
	for i in 9:
		var t := float(i) / 8.0
		var q := cp.lerp(ring, t) + side * sin(t * PI) * 0.35
		cpts.append(Vector3(q.x, maxf(Terrain.height(q.x, q.z) + 0.05, lerpf(cp.y, ring.y, t * t * t)), q.z))
	cpts[cpts.size() - 1] = ring
	var ac := Chain.chain(cpts, 0.1, parent, 120.0)
	ac.name = "BoatAnchorChain"
	# swim ladder over the transom: two rails from the gunwale to a metre under the waterline, round rungs
	for sx: float in [-0.24, 0.24]:
		var top := b.transform * Vector3(sx, 1.75, BOAT_LEN * 0.5 + 0.05)
		var bot := b.transform * Vector3(sx, 0.15, BOAT_LEN * 0.5 + 0.3)
		steel.cylinder(top, bot, 0.02, 0.02, 6, true)
	for k in 4:
		var y := 0.3 + float(k) * 0.32
		var z := BOAT_LEN * 0.5 + 0.3 - 0.25 * (y - 0.15) / 1.6
		steel.cylinder(b.transform * Vector3(-0.24, y, z), b.transform * Vector3(0.24, y, z), 0.016, 0.016, 6, false)
	var mi := steel.instance(Mats.solid(Palette.STEEL_DARK.lightened(0.25), 0.3, 0.2, {"roughness": 0.5}), parent, 160.0)
	mi.name = "BoatSteel"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ml := rope.instance(Mats.make("rope", {"radius": 0.02, "rope_color": Color(0.62, 0.58, 0.45)}), parent, 160.0)
	ml.name = "AnchorLine"


## Concrete shot weight on the sand (Rope.shot_ground) with its rope up to the shackle on the line (Rope pulls
## the line into a V there): taut, the weight holds the line down, so it barely sags.
func _weight(parent: Node3D, stone: MeshBuilder, steel: MeshBuilder) -> void:
	var p := Rope.shot_ground(path) - Vector3(0, 0.15, 0)
	var eye := Debris.weight_block(stone, steel, Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, 0.05), p))
	var tgt := Rope.shot_tie if Rope.shot_tie != Vector3.ZERO else Rope.line_pos(Rope.SHOT_S)
	var pts := PackedVector3Array()
	for i in 13:
		var t := float(i) / 12.0
		pts.append(eye.lerp(tgt, t) + Vector3(0, -sin(t * PI) * 0.12, 0))
	var mi := Rope.tube(pts, 0.028, 6).instance(Mats.make("rope", {"radius": 0.028, "min_px": Rope.LINE_MIN_PX * 0.9,
		"thin_exp": 0.3}), parent, 120.0)
	mi.name = "LineTie"


## The anchor's chain: it drops from the ring onto the sand within half a metre, lies in a loose C across the
## diver's view (a chain heading straight away from the camera read as a stick standing up in the water) and its
## far end runs under the sand.
func _slack_chain(ring: Vector3) -> PackedVector3Array:
	var ctl := [Vector3(0, 0, 0), Vector3(-0.45, 0, -0.15), Vector3(-1.9, 0, -0.55), Vector3(-3.3, 0, -1.5),
		Vector3(-4.1, 0, -3.0), Vector3(-4.0, 0, -4.6), Vector3(-3.4, 0, -5.9)]
	var cv := Curve3D.new()
	for i in ctl.size():
		var p: Vector3 = ring + ctl[i]
		var a: Vector3 = ctl[maxi(i - 1, 0)]
		var b: Vector3 = ctl[mini(i + 1, ctl.size() - 1)]
		cv.add_point(Vector3(p.x, 0.0, p.z), -(b - a) / 6.0, (b - a) / 6.0)
	var total := cv.get_baked_length()
	var pts := PackedVector3Array()
	var d := 0.0
	while d <= total + 1e-3:
		var q := cv.sample_baked(minf(d, total))
		var g := Terrain.height(q.x, q.z) + 0.05
		var y := g
		if d < 0.6:
			y = maxf(g, lerpf(ring.y, g, smoothstep(0.0, 0.6, d)))
		y -= 0.16 * smoothstep(total - 1.2, total, d)       # the last links sink into the sand
		pts.append(Vector3(q.x, y, q.z))
		d += 0.12
	pts[0] = ring
	return pts


func _debris(parent: Node3D, wood: MeshBuilder, steel: MeshBuilder, bronze: MeshBuilder, paint: MeshBuilder,
		strands: MeshBuilder) -> void:
	var f := Config.F_DEBRIS
	# upside-down rowboat, gunwale 0.35 m in the sand
	var rb := Hull.ship("rowboat", 4.4, 7)
	var rd: float = rb.get_meta("depth")
	rb.name = "Rowboat"
	rb.transform = Transform3D(Basis(Vector3.UP, 0.35) * Basis(Vector3.BACK, PI - 0.12),
		_ground(f + Vector3(4.5, 0, 1.5)) + Vector3(0, rd + 0.1, 0))
	parent.add_child(rb)
	_rowboat_detail(rb)
	# anchor on its side, one fluke in the sand, with a chain trailing away from the line
	var ring := Debris.anchor(steel, Transform3D(Basis(Vector3.UP, 1.2) * Basis(Vector3.BACK, 1.35),
		_ground(f + Vector3(2.5, 0, -3.5)) + Vector3(0, 0.15, 0)), 1.8)
	var ac := Chain.chain(_slack_chain(ring), 0.18, parent, 120.0)
	ac.name = "AnchorChain"
	ac.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# crates, two of them under a draped net
	var crates := [[Vector3(9.5, 0, -1.0), Vector3(1.3, 1.0, 1.0), 0.3, 0.0], [Vector3(10.9, 0, 0.5), Vector3(1.0, 0.9, 0.9), -0.4, 0.12],
		[Vector3(12.2, 0, -2.9), Vector3(1.2, 0.8, 1.2), 0.9, -0.1], [Vector3(8.4, 0, -3.8), Vector3(0.9, 0.7, 0.9), 0.1, 0.22]]
	var bumps := []
	for c: Array in crates:
		var sz: Vector3 = c[1]
		var off: Vector3 = c[0]
		var p := _ground(f + off) - Vector3(0, 0.12, 0)
		Debris.crate(wood, Transform3D(Basis(Vector3.UP, float(c[2])) * Basis(Vector3.RIGHT, float(c[3])), p), sz)
		bumps.append([p + Vector3(0, sz.y, 0), sz.x * 0.62, 1.6])
	var fl := Debris.net(strands, _ground(f + Vector3(10.2, 0, -0.4)), Vector2(3.6, 3.2), 0.5, bumps.slice(0, 2), 0.18,
		0.015, 1.2, 5)
	for p in fl:
		paint.sphere(p, 0.11, 8, Vector3(1.0, 0.8, 1.0))
	# a mooring buoy held 2.5 m above its sinker by a short chain
	var bp := _ground(f + Vector3(4.0, 0, -9.0))
	var eye := Debris.weight_block(steel, steel, Transform3D(Basis(Vector3.UP, 0.7), bp - Vector3(0, 0.1, 0)),
		Vector3(0.6, 0.35, 0.6))
	var bottom := Debris.buoy(paint, Transform3D(Basis(Vector3.RIGHT, 0.12), eye + Vector3(0.35, 3.1, 0.1)), 0.6)
	var cpts := PackedVector3Array()
	for i in 7:
		var t := float(i) / 6.0
		cpts.append(eye.lerp(bottom, t) + Vector3(sin(t * PI) * 0.18, 0, 0))
	var bc := Chain.chain(cpts, 0.16, parent, 120.0)
	bc.name = "BuoyChain"
	bc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# the bent propeller, half buried
	Debris.propeller(bronze, Transform3D(Basis(Vector3.UP, 2.2) * Basis(Vector3.BACK, 1.15),
		_ground(f + Vector3(6.8, 0, 4.8)) + Vector3(0, 0.2, 0)), 1.7, 4, 0.8)


# ------------------------------------------------------------------------------------- small hull details

## Hull.ship()'s loft options for a small boat (L < 20 m: no fittings, the default run).
func _ho(kind: String, D: float) -> Dictionary:
	var k: Dictionary = Hull.KINDS[kind]
	return {"stern": k["stern"], "sheer": D * float(k["sheer"]), "dead": k["dead"], "open": kind == "rowboat"}


## A line along a small hull's shell in its ship frame (bow +X, keel bottom at y 0; Hull._station/_shell):
## f in [-1, 0) runs over the bottom from the keel (-1) out to the bilge (0), f in [0, 1] up the side from the
## bilge to the sheer; side +-1; `out` metres off the shell. u0..u1: stern .. bow fraction of the length.
func _hull_line(kind: String, L: float, f: float, side: float, out: float, u0 := 0.02, u1 := 0.95,
		n := 30) -> PackedVector3Array:
	var k: Dictionary = Hull.KINDS[kind]
	var B := L * float(k["b"])
	var D := L * float(k["d"])
	var ho := _ho(kind, D)
	var pts := PackedVector3Array()
	for i in n + 1:
		var u := lerpf(u0, u1, float(i) / float(n))
		var st := Hull._station(L, B, D, float(k["taper"]), float(k["rake"]), ho, u)
		var p: Vector3
		var nrm: Vector3
		if f >= 0.0:
			p = Hull._shell(st, lerpf(float(st["ys"]), float(st["yd"]), f))
			nrm = Vector3(0.0, 0.0, 1.0)
		else:
			var t := 1.0 + f
			var y := lerpf(float(st["yk"]), float(st["yb"]), t)
			var z := float(st["zf"]) * t
			p = Vector3(float(st["x0"]) + float(st["sk"]) * (float(st["yd"]) - y), y, z)
			var sl := (float(st["yb"]) - float(st["yk"])) / maxf(float(st["zf"]), 0.01)
			nrm = Vector3(0.0, -1.0, sl).normalized()
		p.z *= side
		nrm.z *= side
		pts.append(p + nrm * out)
	return pts


## The dive boat from below: a keel bar, two spray rails a side on the vee, a darker fouled bottom with a few
## weed tails, the outboard's clamp bracket over the transom and a small propeller under its leg.
func _boat_detail(b: Node3D) -> void:
	var geo := b.get_node_or_null("Geo") as Node3D
	if geo == null:
		return
	var L := BOAT_LEN
	var D := L * float(Hull.KINDS["motorboat"]["d"])
	var mb := MeshBuilder.new()
	mb.color = Color(0.8, 0.0, 0.3, 0.5)
	Rope.tube(_hull_line("motorboat", L, -1.0, 1.0, 0.035, 0.03, 0.9), 0.045, 6, mb)
	mb.color = Color(0.62, 0.0, 0.3, 0.5)           # rails and chine a shade darker: lines, not glints
	for sd: float in [-1.0, 1.0]:
		for f: float in [-0.62, -0.25]:
			Rope.tube(_hull_line("motorboat", L, f, sd, 0.015, 0.06, 0.82), 0.024, 6, mb)
		Rope.tube(_hull_line("motorboat", L, 0.06, sd, 0.02, 0.03, 0.9), 0.032, 6, mb)    # the chine
	mb.color = Color(0.8, 0.0, 0.3, 0.5)
	# outboard: a clamp bracket bridging motor and transom top, the leg's anti-cavitation plate and a prop
	mb.box(Vector3(-L * 0.5 - 0.12, D * 1.02, 0.0), Vector3(0.3, 0.12, 0.34))
	mb.box(Vector3(-L * 0.52, D * 0.2, 0.0), Vector3(0.42, 0.03, 0.3))
	var hull_mi := geo.get_node_or_null("Hull") as MeshInstance3D
	var mat: Material = hull_mi.material_override if hull_mi else Mats.solid(Palette.BONE.darkened(0.3), 0.08, 0.3)
	var mi := mb.instance(mat, geo)
	mi.name = "BoatDetail"
	var prop := MeshBuilder.new()
	Debris.propeller(prop, Transform3D(Basis.IDENTITY, Vector3(-L * 0.52 - 0.12, D * 0.12, 0.0)), 0.32, 3, 0.0)
	var pmi := prop.instance(Mats.solid(Palette.STEEL_DARK, 0.4, 0.2, {"roughness": 0.5}), geo)
	pmi.name = "Outboard Prop"
	# the bottom fouled below the waterline: darker blotches (vertex occlusion of the hull loft)
	if hull_mi and hull_mi.mesh is ArrayMesh:
		var am := hull_mi.mesh as ArrayMesh
		var nm := ArrayMesh.new()
		var nz := FastNoiseLite.new()
		nz.seed = 19
		nz.frequency = 1.3
		for si in am.get_surface_count():
			var arr := am.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			if cs.size() == vs.size():
				for i in vs.size():
					var v := vs[i]
					var wet := 1.0 - smoothstep(D * 0.38, D * 0.55, v.y)
					var blot := 0.5 + 0.5 * nz.get_noise_3dv(v)
					var c := cs[i]
					c.r *= 1.0 - wet * (0.3 + 0.35 * blot)
					cs[i] = c
				arr[Mesh.ARRAY_COLOR] = cs
			nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		hull_mi.mesh = nm
	# a few weed tails trailing from the keel and the chines (silhouettes against the bright surface)
	var weed := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in 26:
		var f := -1.0 if i % 3 == 0 else 0.06
		var sd := 1.0 if i % 2 == 0 else -1.0
		var u := rng.randf_range(0.08, 0.7)
		var root_p := _hull_line("motorboat", L, f, sd, 0.0, u, u, 1)[0]
		var ln := rng.randf_range(0.25, 0.6)
		var pts := PackedVector3Array()
		for kk in 5:
			var t := float(kk) / 4.0
			pts.append(root_p + Vector3(-ln * 0.7 * t, -ln * 0.7 * t + 0.01, sd * 0.03 * sin(t * 3.0 + float(i))))
		Rope.tube(pts, 0.014, 3, weed)
	var wmi := weed.instance(Mats.solid(Palette.MOSS.darkened(0.2), 0.0, 0.0, {"roughness": 0.9}), geo)
	wmi.name = "Weed"


## The capsized rowboat: a keel strip along the upturned bottom, clinker laps down each side, a gunwale rail
## at the sheer where it meets the sand and a sprung plank end at the stern.
func _rowboat_detail(rb: Node3D) -> void:
	var geo := rb.get_node_or_null("Geo") as Node3D
	if geo == null:
		return
	var L := 4.4
	var mb := MeshBuilder.new()
	mb.color = Color(0.75, 0.0, 0.5, 0.6)
	Rope.tube(_hull_line("rowboat", L, -1.0, 1.0, 0.03, 0.01, 0.97), 0.035, 6, mb)
	for sd: float in [-1.0, 1.0]:
		Rope.tube(_hull_line("rowboat", L, 0.98, sd, 0.02, 0.01, 0.96), 0.03, 6, mb)       # gunwale
		# the plank laps: dark shadow lines (thin bright tubes read as rows of dots at 20 m)
		mb.color = Color(0.45, 0.0, 0.5, 0.6)
		for f: float in [-0.3, 0.25, 0.6]:
			Rope.tube(_hull_line("rowboat", L, f, sd, 0.006, 0.015, 0.95), 0.018, 6, mb)
		mb.color = Color(0.75, 0.0, 0.5, 0.6)
	# a plank end sprung off the transom
	var st := _hull_line("rowboat", L, 0.3, 1.0, 0.02, 0.0, 0.08, 4)
	var spring := PackedVector3Array()
	for i in st.size():
		var t := float(i) / float(st.size() - 1)
		spring.append(st[i] + Vector3(0.0, 0.0, 0.06 * (1.0 - t) * (1.0 - t)))
	Rope.tube(spring, 0.016, 4, mb)
	var hull_mi := geo.get_node_or_null("Hull") as MeshInstance3D
	var mat: Material = hull_mi.material_override if hull_mi else Mats.solid(Palette.RUST.lerp(Palette.BONE, 0.3).darkened(0.45), 0.08, 0.6)
	var mi := mb.instance(mat, geo)
	mi.name = "Planking"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
