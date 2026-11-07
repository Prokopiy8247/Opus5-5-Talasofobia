extends RefCounted
## Mesh builders and shared materials for the colossal ship (beats 3 and 4).
## Godot front faces are clockwise: every quad/triangle is oriented against its intended normal.

const P = preload("res://scripts/ship/ShipProfile.gd")

static var _hull_mat: ShaderMaterial
static var _metal := {}
static var _thin := {}
static var _rusticle_mat: ShaderMaterial
static var _glass: ShaderMaterial
static var _port_glass: ShaderMaterial
static var _black: ShaderMaterial
static var _rusticle_mesh: ArrayMesh
static var _wl_on := -1.0

const BARN_COL := Color(0.66, 0.52, 0.45)   # pale rust-stained calcareous crust (pink enough to grey, not go olive, with distance)
const BIOFILM_COL := Color(0.07, 0.075, 0.06)   # dark biofilm (nothing photosynthesises down here)


## Mesh arrays under construction (members are modified in place by its own methods).
class MA:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var t := PackedFloat32Array()
	var i := PackedInt32Array()

	func vert(p: Vector3, nrm: Vector3, tex := Vector2.ZERO) -> int:
		v.append(p)
		n.append(nrm)
		uv.append(tex)
		return v.size() - 1

	func tangent(tx: Vector3, w := 1.0) -> void:
		t.append_array([tx.x, tx.y, tx.z, w])

	func tri(i0: int, i1: int, i2: int, nrm: Vector3) -> void:
		if (v[i1] - v[i0]).cross(v[i2] - v[i0]).dot(nrm) > 0.0:
			i.append_array([i0, i2, i1])
		else:
			i.append_array([i0, i1, i2])

	func quad(i0: int, i1: int, i2: int, i3: int, nrm: Vector3) -> void:
		if (v[i1] - v[i0]).cross(v[i2] - v[i0]).dot(nrm) > 0.0:
			i.append_array([i0, i2, i1, i0, i3, i2])
		else:
			i.append_array([i0, i1, i2, i0, i2, i3])

	func merge(b: MA) -> MA:
		var off := v.size()
		v.append_array(b.v)
		n.append_array(b.n)
		uv.append_array(b.uv)
		t.append_array(b.t)
		for k in b.i:
			i.append(k + off)
		return self

	func xform(xf: Transform3D) -> MA:
		for k in v.size():
			v[k] = xf * v[k]
			n[k] = (xf.basis * n[k]).normalized()
		return self

	func mesh(mat: Material = null) -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		if uv.size() == v.size():
			arr[Mesh.ARRAY_TEX_UV] = uv
		if t.size() == v.size() * 4:
			arr[Mesh.ARRAY_TANGENT] = t
		arr[Mesh.ARRAY_INDEX] = i
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		if mat:
			m.surface_set_material(0, mat)
		return m


# ---------------------------------------------------------------- materials
static func hull_material() -> ShaderMaterial:
	if _hull_mat == null:
		_hull_mat = ShaderMaterial.new()
		_hull_mat.shader = load("res://shaders/hull.gdshader")
		_hull_mat.set_shader_parameter("c_steel", Palette.STEEL)
		_hull_mat.set_shader_parameter("c_barn", BARN_COL)
		_hull_mat.set_shader_parameter("c_algae", BIOFILM_COL)
		_hull_mat.set_shader_parameter("boot_v", P.v_at_depth(P.BOOT_D))
		_hull_mat.set_shader_parameter("bilge_v", P.v_bilge())
		var rows := PackedFloat32Array()
		for d in P.PORT_ROWS:
			rows.append(P.v_at_depth(d))
		_hull_mat.set_shader_parameter("port_rows", rows)
		_hull_mat.set_shader_parameter("port_count", rows.size())
		_hull_mat.set_shader_parameter("port_dx", P.PORT_DX)
		_hull_mat.set_shader_parameter("port_xmax", P.PORT_XMAX + 1.0)
		_hull_mat.set_shader_parameter("hawse", Vector4(P.HAWSE_X, P.v_at_depth(P.HAWSE_D), P.HAWSE_R.x, P.HAWSE_R.y))
		# draft marks painted into the plating: bottom of each mark, 120 m above the keel down to 2 m
		var keel := P.bottom_depth()
		var marks := PackedFloat32Array()
		for h in range(120, 0, -2):
			marks.append(P.v_at_depth(keel - h))
		_hull_mat.set_shader_parameter("mark_v", marks)
		_hull_mat.set_shader_parameter("draft_x", P.DRAFT_X)
	return _hull_mat

## kind: "rim", "lip", "chain", "davit", "keel", "throat" (heavy parts; thin ones use thin_material)
static func metal_material(kind: String) -> ShaderMaterial:
	if not _metal.has(kind):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/ship_metal.gdshader")
		m.set_shader_parameter("c_base", Palette.STEEL)
		m.set_shader_parameter("c_barn", BARN_COL)
		var cfg := {"rim": [0.35, 0.55, 1.2], "lip": [0.3, 0.9, 0.9], "chain": [0.25, 0.6, 1.4], "ladder": [0.08, 0.3, 1.15],
			"davit": [0.2, 0.55, 1.1], "keel": [0.65, 0.8, 1.0], "throat": [0.3, 0.7, 0.6]}
		var c: Array = cfg.get(kind, [0.3, 0.6, 1.0])
		m.set_shader_parameter("crust", c[0])
		m.set_shader_parameter("rust_amt", c[1])
		m.set_shader_parameter("gain", c[2])
		m.set_shader_parameter("throat_ao", 1.0 if kind == "throat" else 0.0)
		if kind == "lip":   # cast steel bolster: rough, no sheen
			m.set_shader_parameter("rough_lo", 0.7)
		_metal[kind] = m
	return _metal[kind]

## Thin steel (thin_metal.gdshader): base_r = the mesh's own radius (cross-section in local XZ).
## kind: "rung" 0.042, "stringer" 0.05, "bracket" 0.035, "cable" 0.07, "unit" 1.0 (unit cylinders scaled per instance)
static func thin_material(kind: String) -> ShaderMaterial:
	if not _thin.has(kind):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/thin_metal.gdshader")
		m.set_shader_parameter("c_base", Palette.STEEL)
		m.set_shader_parameter("c_barn", BARN_COL)
		var r := {"rung": 0.042, "stringer": 0.05, "bracket": 0.035, "cable": 0.07, "unit": 1.0}
		m.set_shader_parameter("base_r", r.get(kind, 0.05))
		m.set_shader_parameter("crust", 0.08)
		m.set_shader_parameter("rust_amt", 0.45 if kind == "cable" or kind == "unit" else 0.3)
		m.set_shader_parameter("gain", 1.15)
		_thin[kind] = m
	return _thin[kind]

static func rusticle_material() -> ShaderMaterial:
	if _rusticle_mat == null:
		_rusticle_mat = ShaderMaterial.new()
		_rusticle_mat.shader = load("res://shaders/rusticle.gdshader")
	return _rusticle_mat

## Porthole glass: dark, glossy (ship_metal with flat settings, so it fades in with the hull).
static func glass_material() -> ShaderMaterial:
	if _glass == null:
		_glass = _flat_material(Color(0.012, 0.02, 0.022), 0.07, 0.9)
	return _glass

## Intact porthole glass: black and glossy, with a cabin behind it that the torch can light through the glass
## (interior mapping, porthole_glass.gdshader). Broken panes keep glass_material (their hole shows black).
static func porthole_glass_material() -> ShaderMaterial:
	if _port_glass == null:
		_port_glass = ShaderMaterial.new()
		_port_glass.shader = load("res://shaders/porthole_glass.gdshader")
	return _port_glass

static func black_material() -> ShaderMaterial:
	if _black == null:
		_black = _flat_material(Color(0.004, 0.004, 0.005), 1.0, 0.0)
	return _black

static func _flat_material(c: Color, rough: float, spec: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ship_metal.gdshader")
	m.set_shader_parameter("c_base", c)
	m.set_shader_parameter("crust", 0.0)
	m.set_shader_parameter("rust_amt", 0.0)
	m.set_shader_parameter("gain", 1.0 / 3.5)
	m.set_shader_parameter("rough_lo", rough)
	m.set_shader_parameter("rough_hi", rough)
	m.set_shader_parameter("spec", spec)
	return m


## Presence 0..1 of the whole ship at a camera depth: it condenses out of the blue over ~35 s of late B2.
static func presence_at(depth: float) -> float:
	return smoothstep(150.0, 235.0, depth)

## Every frame (both beats call it with the same values): engine-equivalent fog, the water colour, presence,
## and the water-light contract switch for every ship material.
static func update_env(depth: float, presence: float) -> void:
	var dens := G.env.fog_density if G.env else 0.0175
	if _wl_on < 0.0:   # the shared water-light pass exists (checked once)
		_wl_on = 1.0 if ResourceLoader.exists("res://scripts/WaterLight.gd") else 0.0
	var wl := _wl_on
	# the ONE water colour (eye-adapted after the torch click): fogged steel always equals the backdrop
	var water: Color = G.env.fog_light_color if G.env else Palette.water_at(depth)
	var mats: Array = [hull_material(), rusticle_material(), glass_material(), black_material(), porthole_glass_material()]
	mats.append_array(_metal.values())
	mats.append_array(_thin.values())
	for m: ShaderMaterial in mats:
		m.set_shader_parameter("fog_density", dens)
		m.set_shader_parameter("fog_col", water)
		m.set_shader_parameter("presence", presence)
		m.set_shader_parameter("wl_on", wl)


# ---------------------------------------------------------------- hull
## Hull surface patch over x in [x0, x1] and profile length v in [v0, v1]. UV = (x, v) in metres.
static func hull_chunk(x0: float, x1: float, v0: float, v1: float, dx: float, dv: float) -> ArrayMesh:
	var xs := steps(x0, x1, dx)
	var vs := steps(v0, v1, dv)
	var a := MA.new()
	var nx := xs.size()
	for v in vs:
		var p := P.zd(v)
		var n := P.normal(v)
		for x in xs:
			if v > P.CRUMPLE_V + 1.0:
				a.vert(Vector3(x, -p.y, p.x), n, Vector2(x, v))
				a.tangent(Vector3(1, 0, 0))
				continue
			# torn upper plating bent in and out: displaced position, normal and tangent from the surface
			var tx := (_hull_pos(x + 0.5, v) - _hull_pos(x - 0.5, v)).normalized()
			var tv := (_hull_pos(x, v + 0.5) - _hull_pos(x, v - 0.5)).normalized()
			var nn := tv.cross(tx).normalized()
			if nn.dot(n) < 0.0:
				nn = -nn
			a.vert(_hull_pos(x, v), nn, Vector2(x, v))
			a.tangent(tx)
	for j in vs.size() - 1:
		var n := P.normal((vs[j] + vs[j + 1]) * 0.5)
		for i in nx - 1:
			var k := j * nx + i
			a.quad(k, k + 1, k + 1 + nx, k + nx, n)
	return a.mesh(hull_material())

static func _hull_pos(x: float, v: float) -> Vector3:
	return P.point(x, v) + P.normal(v) * P.crumple(x, v)

static func steps(a: float, b: float, step: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := maxi(1, int(ceil((b - a) / step - 0.001)))
	for i in n + 1:
		out.append(lerpf(a, b, float(i) / n))
	return out


# ---------------------------------------------------------------- sweeps
static func ring(r: float, segs: int, sx := 1.0, sy := 1.0, rot := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for j in segs:
		var a := TAU * j / segs + rot
		out.append(Vector2(cos(a) * r * sx, sin(a) * r * sy))
	return out

## Sweeps a closed 2D profile along a path. Frame: n = up_ref made perpendicular to the tangent, b = t x n.
## Normals are radial from the path (round / near-round profiles); inward flips them (tube interiors).
static func sweep(path: PackedVector3Array, up_ref: Vector3, prof: PackedVector2Array, closed := false, inward := false,
		scales := PackedFloat32Array()) -> MA:
	var a := MA.new()
	var m := path.size()
	var ps := prof.size()
	var acc := 0.0
	for i in m:
		var prev: Vector3 = path[(i - 1 + m) % m] if (closed or i > 0) else path[i]
		var next: Vector3 = path[(i + 1) % m] if (closed or i < m - 1) else path[i]
		var t := (next - prev).normalized()
		var nn := (up_ref - t * up_ref.dot(t)).normalized()
		var b := t.cross(nn)
		if i > 0:
			acc += path[i].distance_to(path[i - 1])
		var sc := scales[i] if i < scales.size() else 1.0
		for j in ps:
			var off := (nn * prof[j].x + b * prof[j].y) * sc
			a.vert(path[i] + off, -off.normalized() if inward else off.normalized(), Vector2(acc, float(j) / ps))
	var segs := m if closed else m - 1
	for i in segs:
		var i2 := (i + 1) % m
		for j in ps:
			var j2 := (j + 1) % ps
			var k0 := i * ps + j
			var k1 := i * ps + j2
			var k2 := i2 * ps + j2
			var k3 := i2 * ps + j
			a.quad(k0, k1, k2, k3, a.n[k0] + a.n[k1] + a.n[k2] + a.n[k3])
	return a

## Closed (elliptical) torus in the XY plane, axis +Z.
static func torus(rx: float, ry: float, r: float, segs := 24, rsegs := 8) -> MA:
	var path := PackedVector3Array()
	for i in segs:
		var a := TAU * i / segs
		path.append(Vector3(cos(a) * rx, sin(a) * ry, 0.0))
	return sweep(path, Vector3(0, 0, 1), ring(r, rsegs), true)

## Flat disc in the XY plane facing +Z. jagged > 0 makes a broken-glass annulus instead.
static func disc(r: float, segs := 20, jagged := 0.0, seed := 0) -> MA:
	var a := MA.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := Vector3(0, 0, 1)
	if jagged <= 0.0:
		a.vert(Vector3.ZERO, n)
		for k in segs:
			var ang := TAU * k / segs
			a.vert(Vector3(cos(ang) * r, sin(ang) * r, 0), n)
		for k in segs:
			a.tri(0, 1 + k, 1 + (k + 1) % segs, n)
		return a
	for k in segs:   # outer ring + jagged inner ring: shards hang from the rim
		var ang := TAU * k / segs
		var inner := r * (1.0 - jagged * rng.randf_range(0.15, 1.0))
		if rng.randf() < 0.3:
			inner = r * 0.93
		a.vert(Vector3(cos(ang) * r, sin(ang) * r, 0), n)
		a.vert(Vector3(cos(ang) * inner, sin(ang) * inner, 0), n)
	for k in segs:
		var k2 := (k + 1) % segs
		a.quad(k * 2, k2 * 2, k2 * 2 + 1, k * 2 + 1, n)
	return a

## Rusticle: a 7-sided tube along a slightly wavy 1 m path hanging down from y = 0 to the tip at y = -1, wide at
## the anchor and tapering to a point, with lumps. Shared by every rusticle MultiMesh.
static func rusticle_mesh() -> ArrayMesh:
	if _rusticle_mesh == null:
		var path := PackedVector3Array()
		var sc := PackedFloat32Array()
		var n := 12
		for k in n:
			var t := float(k) / (n - 1)
			path.append(Vector3(0.05 * sin(t * 5.0), -t, 0.04 * sin(t * 7.0 + 1.0)))
			sc.append(0.32 * pow(1.0 - t, 1.4) + 0.015)
		var a := sweep(path, Vector3(1, 0, 0), ring(1.0, 7), false, false, sc)
		for k in a.v.size():   # lumps
			var i := k / 7
			var j := k % 7
			var t := float(i) / (n - 1)
			var c := path[i]
			a.v[k] = c + (a.v[k] - c) * (1.0 + 0.22 * sin(9.0 * t + j * 2.1))
		_rusticle_mesh = a.mesh()
	return _rusticle_mesh

## Stud-link anchor chain link: long axis Y, lies in the XY plane. Outer length 3.0, width 1.8, bar 0.3.
static func chain_link() -> ArrayMesh:
	var path := PackedVector3Array()
	var rr := 0.6
	var hy := 0.6
	for k in 10:   # top semicircle, right -> left
		var a := PI * k / 9.0
		path.append(Vector3(cos(a) * rr, hy + sin(a) * rr, 0))
	for k in 10:   # bottom semicircle, left -> right
		var a := PI + PI * k / 9.0
		path.append(Vector3(cos(a) * rr, -hy + sin(a) * rr, 0))
	var m := sweep(path, Vector3(0, 0, 1), ring(0.3, 8), true)
	m.merge(sweep(PackedVector3Array([Vector3(-0.62, 0, 0), Vector3(0.62, 0, 0)]), Vector3(0, 0, 1), ring(0.15, 6)))
	return m.mesh(metal_material("chain"))


# ---------------------------------------------------------------- nodes
static func multimesh(mesh: Mesh, xforms: Array) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	return mm

static func mm_node(mesh: Mesh, xforms: Array, vis_end: float, mat: Material = null) -> MultiMeshInstance3D:
	var nd := MultiMeshInstance3D.new()
	nd.multimesh = multimesh(mesh, xforms)
	if mat:
		nd.material_override = mat
	nd.visibility_range_end = vis_end
	return nd

static func mesh_node(mesh: Mesh, xf := Transform3D.IDENTITY, vis_end := 0.0, mat: Material = null) -> MeshInstance3D:
	var nd := MeshInstance3D.new()
	nd.mesh = mesh
	nd.transform = xf
	if mat:
		nd.material_override = mat
	nd.visibility_range_end = vis_end
	return nd
