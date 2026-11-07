class_name Chain
extends RefCounted
## Chains as a MultiMeshInstance3D of stadium (torus-like) links alternating 90 degrees.
## The unit link is 1 m long along X (width 0.62, wire 0.17) and is scaled by link_size.

static var _link: ArrayMesh
static var _mat: ShaderMaterial


static func link_mesh() -> ArrayMesh:
	if _link:
		return _link
	var mb := MeshBuilder.new()
	var R := 0.225
	var a := 0.19
	var r := 0.085
	var rings := []
	var uu := PackedFloat32Array()
	for i in 11:
		var th := TAU * float(i % 10) / 10.0
		var d := Vector3(cos(th), 0.0, sin(th))
		var c := Vector3(a * signf(snappedf(cos(th), 0.001)) + R * cos(th), 0.0, R * sin(th))
		var ring := PackedVector3Array()
		for j in 5:
			var ph := TAU * float(j) / 5.0
			ring.append(c + d * r * cos(ph) + Vector3.UP * r * sin(ph))
		rings.append(ring)
		uu.append(float(i) * 0.1)
	mb.grid(rings, uu, PackedFloat32Array([0, 0.1, 0.2, 0.3, 0.4]), true, true)
	_link = mb.build()
	return _link


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = Mats.solid(Palette.STEEL_DARK.lerp(Palette.RUST, 0.35), 0.75, 0.3)
	return _mat


## Chain through world points (resampled at the link pitch). Returns the MultiMeshInstance3D.
static func chain(points: PackedVector3Array, link_size: float, parent: Node3D = null, vis_end := 0.0,
		mat: Material = null) -> MultiMeshInstance3D:
	var pitch := link_size * 0.68
	var joints := PackedVector3Array([points[0]])
	var need := pitch
	var i := 0
	var cur := points[0]
	while i < points.size() - 1:
		var nxt := points[i + 1]
		var seg := cur.distance_to(nxt)
		if seg >= need and seg > 1e-6:
			cur = cur.lerp(nxt, need / seg)
			joints.append(cur)
			need = pitch
		else:
			need -= seg
			cur = nxt
			i += 1
	var n := maxi(joints.size() - 1, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = link_mesh()
	mm.instance_count = n
	for k in n:
		var dir := (joints[k + 1] - joints[k]).normalized()
		var up := Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
		var y := (up - dir * up.dot(dir)).normalized()
		var z := dir.cross(y)
		if k % 2 == 1:
			var t := y
			y = z
			z = -t
		var c := (joints[k] + joints[k + 1]) * 0.5
		mm.set_instance_transform(k, Transform3D(Basis(dir * link_size, y * link_size, z * link_size), c))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Chain"
	mmi.multimesh = mm
	mmi.set_meta("joints", joints)
	mmi.material_override = mat if mat else material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end
		mmi.visibility_range_end_margin = vis_end * 0.15
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if parent:
		parent.add_child(mmi)
	return mmi


## Chain split into ~seg_len pieces, each with its own small bounds so visibility ranges are exact: links up to
## `near` metres, beyond that a thin rope-shader line (1 px floor, fogs out) instead of shimmering sub-pixel
## links. Casts shadows. Returns the parent node holding the pieces (meta "joints": all joints, world).
static func chain_lod(points: PackedVector3Array, link_size: float, parent: Node3D, near := 110.0, seg_len := 24.0,
		mat: Material = null) -> Node3D:
	var root := Node3D.new()
	root.name = "ChainLod"
	parent.add_child(root)
	var all := PackedVector3Array()
	var piece := PackedVector3Array([points[0]])
	var run := 0.0
	var rope_mat := Mats.make("rope", {"radius": link_size * 0.3, "rope_color": Color(0.2, 0.15, 0.11)})
	for i in range(1, points.size()):
		piece.append(points[i])
		run += points[i].distance_to(points[i - 1])
		if run >= seg_len or i == points.size() - 1:
			var mmi := chain(piece, link_size, root, near, mat)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mmi.visibility_range_end_margin = near * 0.18
			all.append_array(mmi.get_meta("joints"))
			var tube := Rope.tube(piece, link_size * 0.3, 4).instance(rope_mat, root)
			tube.name = "ChainFar"
			tube.visibility_range_begin = near * 0.85
			tube.visibility_range_begin_margin = near * 0.18
			tube.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			piece = PackedVector3Array([points[i]])
			run = 0.0
	root.set_meta("joints", all)
	root.set_meta("link", link_size)
	return root


## Points of a chain leaving `start` (optionally first along `out`, e.g. a hawse pipe's outward normal, so it
## clears the plating), hanging down to the seabed in a curve that meets the ground tangentially, then trailing
## over it along dir_h with a slow lateral wiggle (Terrain.height keeps it on the ground). The chain always
## reaches the ground: `length` (3D) is extended when the drop needs more.
static func trail(start: Vector3, dir_h: Vector3, length: float, link_size: float, seed := 0,
		out := Vector3.ZERO) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var d := Vector3(dir_h.x, 0.0, dir_h.z).normalized()
	var side := Vector3(-d.z, 0.0, d.x)
	var pts := PackedVector3Array()
	var p0 := start
	if out != Vector3.ZERO:
		pts.append(start)
		p0 = start + out.normalized() * maxf(link_size * 2.5, 0.6) + Vector3(0, -link_size, 0)
	var lift := link_size * 0.3
	# touchdown distance: iterate, since the ground under the hanging part may fall away (slopes)
	var hang := 1.0
	var gt := Terrain.height(p0.x, p0.z) + lift
	for it in 6:
		var drop := maxf(p0.y - gt, 0.0)
		hang = clampf(drop * 0.55, 1.0, maxf(drop * 2.0, 1.0))
		var touch := p0 + d * hang
		gt = minf(Terrain.height(touch.x, touch.z) + lift, p0.y)
	var arc := sqrt(hang * hang + pow(p0.y - gt, 2.0)) * 1.15
	var total := maxf(length, arc + 6.0)
	var step := maxf(link_size * 1.2, 0.4)
	var ph := rng.randf() * TAU
	var amp := rng.randf_range(2.0, 5.0) * link_size
	var s := 0.0
	var run := 0.0
	while true:
		var w := clampf((s - hang) / 10.0, 0.0, 1.0)
		var p := p0 + d * s + side * sin(s * 0.09 + ph) * amp * w
		var gy := Terrain.height(p.x, p.z) + lift
		if s < hang:
			var t := s / hang
			p.y = maxf(gt + (p0.y - gt) * (1.0 - t) * (1.0 - t), gy)
		else:
			p.y = gy
		if not pts.is_empty():
			run += p.distance_to(pts[pts.size() - 1])
		pts.append(p)
		s += step
		if run >= total and s > hang + step:
			break
		if s > total * 4.0 + hang:
			break
	# where the ground bulges above a chord between two points, add a point on it (no links inside a ridge)
	var res := PackedVector3Array()
	for i in pts.size():
		if i > 0:
			var m := (pts[i - 1] + pts[i]) * 0.5
			var gm := Terrain.height(m.x, m.z) + lift
			if gm > m.y + link_size * 0.15:
				res.append(Vector3(m.x, gm, m.z))
		res.append(pts[i])
	return res
