class_name MeshBuilder
extends RefCounted
## Accumulates triangles and builds an ArrayMesh. Every triangle is auto-oriented so that its
## front face agrees with the supplied vertex normals (Godot front faces are clockwise).
## Vertex COLOR convention: r = ambient occlusion (1 open), g = porthole zone, b = rust bias, a = moss bias.

var v := PackedVector3Array()
var n := PackedVector3Array()
var uv := PackedVector2Array()
var col := PackedColorArray()
var idx := PackedInt32Array()
var color := Color(1, 0, 0.5, 0.5)
var xf := Transform3D.IDENTITY


func vert(p: Vector3, nn: Vector3, t := Vector2.ZERO, c := color) -> int:
	v.append(xf * p)
	n.append((xf.basis * nn).normalized())
	uv.append(t)
	col.append(c)
	return v.size() - 1


func tri(a: int, b: int, c: int) -> void:
	var fn := (v[c] - v[a]).cross(v[b] - v[a])
	if fn.dot(n[a] + n[b] + n[c]) < 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


func quad(a: int, b: int, c: int, d: int) -> void:
	tri(a, b, c)
	tri(a, c, d)


## Loft through rings of equal size. rings[i] is a PackedVector3Array (local positions).
## u_vals[i] / v_vals[j] give UV coordinates (metres). Normals from the grid, oriented away
## from each ring centre when outward_from_center is true. closed: last point connects to first;
## a duplicate seam column (v continued past the last column) keeps the texture from being squeezed
## into the closing quad. Each ring then has np + 1 vertices.
func grid(rings: Array, u_vals: PackedFloat32Array, v_vals: PackedFloat32Array, closed := true,
		outward_from_center := true, colors: Array = []) -> void:
	var nr := rings.size()
	var np: int = rings[0].size()
	var base := v.size()
	var v_wrap := 0.0
	if closed:
		var d0 := v_vals[1] - v_vals[0] if np > 1 else 0.0
		var dl := v_vals[np - 1] - v_vals[np - 2] if np > 1 else 0.0
		if absf(dl - d0) <= 1e-3 * maxf(absf(v_vals[np - 1] - v_vals[0]), 1e-3):
			v_wrap = v_vals[np - 1] + d0                       # evenly spaced columns: one more step
		else:
			var acc := 0.0
			for r: PackedVector3Array in rings:
				acc += r[np - 1].distance_to(r[0])
			v_wrap = v_vals[np - 1] + acc / float(nr)           # metres along the closing edge
	var stride := np + 1 if closed else np
	for i in nr:
		var ring: PackedVector3Array = rings[i]
		var prev: PackedVector3Array = rings[maxi(i - 1, 0)]
		var nxt: PackedVector3Array = rings[mini(i + 1, nr - 1)]
		var center := Vector3.ZERO
		for p in ring:
			center += p
		center /= float(np)
		for j in np:
			var jp: int = (j - 1 + np) % np if closed else maxi(j - 1, 0)
			var jn: int = (j + 1) % np if closed else mini(j + 1, np - 1)
			var du := nxt[j] - prev[j]
			var dv := ring[jn] - ring[jp]
			var nn := du.cross(dv)
			if nn.length_squared() < 1e-12:
				nn = ring[j] - center
			nn = nn.normalized()
			if outward_from_center and nn.dot(ring[j] - center) < 0.0:
				nn = -nn
			var c: Color = colors[i] if colors.size() == nr else color
			vert(ring[j], nn, Vector2(u_vals[i], v_vals[j]), c)
			if closed and j == np - 1:
				var s0 := base + i * stride
				vert(ring[0], n[s0], Vector2(u_vals[i], v_wrap), col[s0])
	var segs := np if closed else np - 1
	for i in nr - 1:
		for j in segs:
			quad(base + i * stride + j, base + (i + 1) * stride + j, base + (i + 1) * stride + j + 1, base + i * stride + j + 1)


## Flat cap of a ring (fan around its centre), normal given.
func cap(ring: PackedVector3Array, normal: Vector3) -> void:
	var center := Vector3.ZERO
	for p in ring:
		center += p
	center /= float(ring.size())
	var c0 := vert(center, normal)
	var first := v.size()
	for p in ring:
		vert(p, normal, Vector2((p - center).x, (p - center).z))
	for j in ring.size():
		tri(c0, first + j, first + (j + 1) % ring.size())


func box(center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for d in dirs:
		var a: Vector3 = d
		var t1 := Vector3.UP if absf(a.y) < 0.5 else Vector3.RIGHT
		var t2 := a.cross(t1)
		var corners := []
		for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p: Vector3 = a * h + (t1 * s.x + t2 * s.y) * h
			corners.append(vert(center + basis * p, basis * a, Vector2((t1 * s.x * h).length() * s.x, (t2 * s.y * h).length() * s.y)))
		quad(corners[0], corners[1], corners[2], corners[3])


## Tapered cylinder between a and b.
func cylinder(a: Vector3, b: Vector3, ra: float, rb: float, seg := 12, caps := true) -> void:
	var axis := b - a
	var ln := axis.length()
	var z := axis / maxf(ln, 1e-5)
	var x := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized()
	var y := x.cross(z)
	var r0 := PackedVector3Array()
	var r1 := PackedVector3Array()
	var vv := PackedFloat32Array()
	for j in seg:
		var ang := TAU * float(j) / float(seg)
		var d := x * cos(ang) + y * sin(ang)
		r0.append(a + d * ra)
		r1.append(b + d * rb)
		vv.append(ang * (ra + rb) * 0.5)
	grid([r0, r1], PackedFloat32Array([0.0, ln]), vv, true, true)
	if caps:
		cap(r0, -z)
		cap(r1, z)


func sphere(c: Vector3, r: float, seg := 12, squash := Vector3.ONE) -> void:
	var rings := []
	var uu := PackedFloat32Array()
	var vv := PackedFloat32Array()
	var rows := maxi(seg / 2, 3)
	for i in rows + 1:
		var th := PI * float(i) / float(rows)
		var ring := PackedVector3Array()
		for j in seg:
			var ph := TAU * float(j) / float(seg)
			ring.append(c + Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)) * r * squash)
		rings.append(ring)
		uu.append(th * r)
	for j in seg:
		vv.append(TAU * float(j) / float(seg) * r)
	grid(rings, uu, vv, true, true)


## Lathe a profile of (radius, height) points around the Y axis.
func lathe(profile: PackedVector2Array, seg := 24, center := Vector3.ZERO) -> void:
	var rings := []
	var uu := PackedFloat32Array()
	var vv := PackedFloat32Array()
	var acc := 0.0
	for i in profile.size():
		if i > 0:
			acc += profile[i].distance_to(profile[i - 1])
		var ring := PackedVector3Array()
		for j in seg:
			var ph := TAU * float(j) / float(seg)
			ring.append(center + Vector3(cos(ph) * profile[i].x, profile[i].y, sin(ph) * profile[i].x))
		rings.append(ring)
		uu.append(acc)
	for j in seg:
		vv.append(TAU * float(j) / float(seg) * 2.0)
	grid(rings, uu, vv, true, true)


func torus(c: Vector3, axis: Vector3, R: float, r: float, seg_major := 16, seg_minor := 8) -> void:
	var z := axis.normalized()
	var x := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized()
	var y := x.cross(z)
	var rings := []
	var uu := PackedFloat32Array()
	var vv := PackedFloat32Array()
	for i in seg_major + 1:
		var a := TAU * float(i) / float(seg_major)
		var d := x * cos(a) + y * sin(a)
		var ring := PackedVector3Array()
		for j in seg_minor:
			var b := TAU * float(j) / float(seg_minor)
			ring.append(c + d * (R + r * cos(b)) + z * r * sin(b))
		rings.append(ring)
		uu.append(a * R)
	for j in seg_minor:
		vv.append(TAU * float(j) / float(seg_minor) * r)
	grid(rings, uu, vv, true, true)


func append(other: MeshBuilder) -> void:
	var off := v.size()
	v.append_array(other.v)
	n.append_array(other.n)
	uv.append_array(other.uv)
	col.append_array(other.col)
	for i in other.idx:
		idx.append(i + off)


func tri_count() -> int:
	return idx.size() / 3


func build(mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if idx.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Convenience: build a MeshInstance3D with a material and optional visibility range.
func instance(material: Material, parent: Node3D = null, vis_end := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = build()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = vis_end * 0.15
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if parent:
		parent.add_child(mi)
	return mi
