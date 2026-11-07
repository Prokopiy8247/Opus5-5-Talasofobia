extends RefCounted
## Beat 1 — Under the boat: a small dive boat at the surface, its anchor line down to the reef top. The diver starts
## just behind and below it, so the first image (under the PELAGIC title) is the dark hull crossing Snell's window
## with the sun beside it; the anchor line then leads the eye down to the reef.

const BOAT_POS := Vector3(1.2, 0.0, -8.0)
const BOAT_YAW := 24.0          # degrees; the bow points ahead-left, towards the anchor on the reef
const ANCHOR := Vector3(-42.0, -15.0, -40.0)
const LEN := 7.4                # hull length (m), bow at local -Z
const RINGS := 44

func build(parent: Node3D) -> void:
	var boat := Node3D.new()
	boat.name = "Boat"
	boat.position = BOAT_POS
	boat.rotation.y = deg_to_rad(BOAT_YAW)
	parent.add_child(boat)
	var fwd := boat.transform.basis * Vector3.FORWARD
	var hull_mat := _mat(0, fwd)
	var alloy := _mat(1, fwd)
	var steel := _mat(2, fwd)
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	hull.mesh = _hull_mesh()
	hull.material_override = hull_mat
	boat.add_child(hull)
	# outboard on the transom: streamlined leg, anti-ventilation plate, gearcase torpedo, skeg, three-blade propeller
	var z0 := LEN * 0.5 + 0.2
	_part(boat, _strut(0.11, 0.035, 0.45, -0.78, 14), Vector3(0, 0, z0), alloy)
	var plate := BoxMesh.new()
	plate.size = Vector3(0.26, 0.012, 0.3)
	_part(boat, plate, Vector3(0, -0.6, z0 + 0.03), alloy)
	var torp := MeshInstance3D.new()
	torp.mesh = Geo.lathe(PackedVector2Array([Vector2(0.0, -0.24), Vector2(0.035, -0.22), Vector2(0.058, -0.15),
		Vector2(0.062, 0.0), Vector2(0.056, 0.14), Vector2(0.04, 0.2), Vector2(0.0, 0.21)]), 16)
	torp.rotation.x = PI * 0.5             # lathe axis +Y -> +Z (towards the stern)
	torp.position = Vector3(0, -0.82, z0)
	torp.material_override = alloy
	boat.add_child(torp)
	var skeg := BoxMesh.new()
	skeg.size = Vector3(0.016, 0.17, 0.2)
	_part(boat, skeg, Vector3(0, -0.94, z0 + 0.03), alloy)
	_part(boat, _propeller(0.165, 0.045, 3), Vector3(0, -0.82, z0 + 0.25), alloy)
	# swim ladder on the port quarter of the transom, clear of the outboard (human scale reference)
	var lx := -0.72
	for side: float in [lx - 0.2, lx + 0.2]:
		_part(boat, Geo.tube(PackedVector3Array([Vector3(side, 0.45, LEN * 0.5 + 0.05), Vector3(side, -0.95, LEN * 0.5 + 0.22)]), 0.02, 8), Vector3.ZERO, steel)
	for k in 4:
		var y := 0.05 - k * 0.3
		var z := LEN * 0.5 + 0.08 + (0.05 - y) * 0.12
		_part(boat, Geo.tube(PackedVector3Array([Vector3(lx - 0.2, y, z), Vector3(lx + 0.2, y, z)]), 0.016, 8), Vector3.ZERO, steel)
	# anchor line from the bow eye on the stem to the reef top, a short chain and the anchor. The line starts inside
	# the forefoot, 12 cm above the keel line (more than the hull's ~7 cm swell motion), so it always comes out of the
	# hull bottom about 20 cm under the waterline, right beside the keel: from below it visibly leaves the boat
	# (a bow fitting above the water would make it end at the surface ahead of the stem, seemingly in mid-water).
	var u_eye := 0.22
	var keel_y: float = (_section(u_eye)[0] as PackedVector2Array)[0].y
	var bow := boat.transform * Vector3(0, keel_y + 0.12, lerpf(-LEN * 0.5, LEN * 0.5, u_eye))
	var line := MeshInstance3D.new()
	line.mesh = Geo.tube(Geo.sag(bow, ANCHOR + Vector3(2.0, 1.2, 1.0), 4.0, 80), 0.028, 8)
	line.material_override = Geo.rope_mat()
	parent.add_child(line)
	var iron := _mat(3, fwd)
	iron.set_shader_parameter("swell", 0.0)
	var chain := MeshInstance3D.new()
	chain.mesh = Geo.tube(Geo.sag(ANCHOR + Vector3(2.0, 1.2, 1.0), ANCHOR + Vector3(0, 0.15, 0), 0.4, 8), 0.035, 6)
	chain.material_override = iron
	parent.add_child(chain)
	var anchor := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.9, 0.12, 0.35)
	anchor.mesh = am
	anchor.position = ANCHOR + Vector3(0, 0.12, 0)
	anchor.rotation = Vector3(0.2, 0.7, 0.15)
	anchor.material_override = iron
	parent.add_child(anchor)
	var t := Node3D.new()
	t.name = "T_boat"
	parent.add_child(t)
	t.global_position = BOAT_POS + Vector3(0, -0.6, 0)
	Game.targets["boat"] = t

func _mat(kind: int, fwd: Vector3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/boat.gdshader")
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("boat_origin", BOAT_POS)
	m.set_shader_parameter("boat_fwd", fwd)
	return m

func _part(boat: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	boat.add_child(mi)
	return mi

# --- hull -----------------------------------------------------------------------------------------------------------

## Half section of the hull at u (0 bow .. 1 transom), right side (x >= 0), keel -> sheer: a deep-V planing bottom
## with two lifting strakes, a hard chine with a spray rail, flared topsides. Returns [points, creases].
static func _section(u: float) -> Array:
	var hb := 1.2 * pow(sin(minf(u / 0.56, 1.0) * PI * 0.5), 0.72) * (1.0 - 0.05 * u)
	var sheer := 0.62 + 0.34 * (1.0 - smoothstep(0.0, 0.42, u))
	var keel := lerpf(0.5, -0.58, pow(smoothstep(0.0, 0.4, u), 0.62)) + 0.07 * smoothstep(0.55, 1.0, u)
	var dead := deg_to_rad(lerpf(50.0, 17.0, smoothstep(0.08, 0.85, u)))
	var cx := 0.87 * hb
	var cy := minf(keel + cx * tan(dead), sheer - 0.22 * smoothstep(0.0, 0.2, u) - 0.02)
	var k := Vector2(0.0, keel)
	var ch := Vector2(cx, cy)
	var d := ch - k
	var nout := Vector2(d.y, -d.x).normalized()             # outward (down-out) normal of the bottom panel
	var sh := smoothstep(0.03, 0.2, u) * (1.0 - smoothstep(0.62, 0.88, u)) * 0.04 * smoothstep(0.0, 0.3, hb)
	var pts := PackedVector2Array([k])
	var creases := [true]
	for f: float in [0.34, 0.67]:
		var a: Vector2 = k + d * f
		var b: Vector2 = k + d * (f + 0.012 / maxf(d.length(), 0.05))
		pts.append(a); creases.append(true)
		pts.append(a + nout * sh + d.normalized() * 0.008); creases.append(true)
		pts.append(b + d.normalized() * 0.03); creases.append(true)
	pts.append(ch); creases.append(true)
	pts.append(ch + Vector2(0.045 * smoothstep(0.0, 0.3, hb), 0.008)); creases.append(true)
	pts.append(Vector2(lerpf(cx + 0.045, hb, 0.8), lerpf(cy, sheer, 0.5))); creases.append(false)
	pts.append(Vector2(hb, sheer)); creases.append(true)
	return [pts, creases]

static func _hull_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var secs: Array = []
	for i in RINGS + 1:
		var u := float(i) / RINGS
		var z := lerpf(-LEN * 0.5, LEN * 0.5, u)
		var sec: Array = _section(u)
		var p3 := PackedVector3Array()
		for q in (sec[0] as PackedVector2Array):
			p3.append(Vector3(q.x, q.y, z))
		secs.append([p3, sec[1]])
	var m: int = (secs[0][0] as PackedVector3Array).size()
	for side: float in [1.0, -1.0]:
		var mir := Vector3(side, 1.0, 1.0)
		# vertex normals per ring: per segment across the section x along the hull, averaged at smooth joints
		var segn: Array = []
		for i in RINGS + 1:
			var p: PackedVector3Array = secs[i][0]
			var pa: PackedVector3Array = secs[maxi(i - 1, 0)][0]
			var pb: PackedVector3Array = secs[mini(i + 1, RINGS)][0]
			var row := []
			for j in m - 1:
				var across := (p[j + 1] - p[j]) * mir
				var along := ((pb[j] + pb[j + 1]) - (pa[j] + pa[j + 1])) * 0.5 * mir
				# along (+Z) x across (keel -> sheer) points into the hull on the right side, out of it on the left
				var n: Vector3 = along.cross(across) * -side
				n = n.normalized() if n.length() > 1e-7 else Vector3(side, -0.3, 0.0).normalized()
				row.append(n)
			segn.append(row)
		for i in RINGS:
			var p0: PackedVector3Array = secs[i][0]
			var p1: PackedVector3Array = secs[i + 1][0]
			var cr: Array = secs[i][1]
			for j in m - 1:
				var n00 := _vn(segn[i], cr, j, true)
				var n01 := _vn(segn[i], cr, j + 1, false)
				var n10 := _vn(segn[i + 1], cr, j, true)
				var n11 := _vn(segn[i + 1], cr, j + 1, false)
				var outn: Vector3 = (segn[i][j] + segn[i + 1][j]).normalized()
				_quad(st, p0[j] * mir, p0[j + 1] * mir, p1[j] * mir, p1[j + 1] * mir, n00, n01, n10, n11, outn)
	# deck (slightly cambered) and the closed transom
	for i in RINGS:
		var a: PackedVector3Array = secs[i][0]
		var b: PackedVector3Array = secs[i + 1][0]
		var ra := a[m - 1]; var rb := b[m - 1]
		var ca := Vector3(0.0, ra.y + 0.05, ra.z); var cb := Vector3(0.0, rb.y + 0.05, rb.z)
		for side: float in [1.0, -1.0]:
			var mir := Vector3(side, 1.0, 1.0)
			_quad(st, ca, ra * mir, cb, rb * mir, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP)
	var tr: PackedVector3Array = secs[RINGS][0]
	var outline := PackedVector3Array()
	for j in m:
		outline.append(tr[j])
	outline.append(Vector3(0.0, tr[m - 1].y + 0.05, tr[0].z))
	for j in range(m - 1, -1, -1):
		outline.append(tr[j] * Vector3(-1.0, 1.0, 1.0))
	var c := Vector3(0.0, (tr[0].y + tr[m - 1].y) * 0.5, tr[0].z)
	for j in outline.size() - 1:
		_tri(st, c, outline[j], outline[j + 1], Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK)
	return st.commit()

static func _vn(row: Array, creases: Array, j: int, left_of_seg: bool) -> Vector3:
	# normal of point j for the segment that starts (left_of_seg) or ends at it; smooth joints average both segments
	var s_idx := j if left_of_seg else j - 1
	var n: Vector3 = row[s_idx]
	if not creases[j]:
		var other := j - 1 if left_of_seg else j
		if other >= 0 and other < row.size():
			n = (n + (row[other] as Vector3)).normalized()
	return n

## Adds triangle a, b, c facing out_n (Godot front faces are clockwise seen from the front).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, out_n: Vector3) -> void:
	if (b - a).cross(c - a).dot(out_n) > 0.0:
		var t := b; b = c; c = t
		var tn := nb; nb = nc; nc = tn
	st.set_normal(na); st.add_vertex(a)
	st.set_normal(nb); st.add_vertex(b)
	st.set_normal(nc); st.add_vertex(c)

static func _quad(st: SurfaceTool, p00: Vector3, p01: Vector3, p10: Vector3, p11: Vector3,
		n00: Vector3, n01: Vector3, n10: Vector3, n11: Vector3, out_n: Vector3) -> void:
	_tri(st, p00, p10, p01, n00, n10, n01, out_n)
	_tri(st, p01, p10, p11, n01, n10, n11, out_n)

# --- outboard parts -------------------------------------------------------------------------------------------------

## Vertical streamlined strut (the outboard leg): a symmetric foil section of chord 2*cz and thickness 2*tx,
## from y_top down to y_bot, closed at the bottom.
static func _strut(cz: float, tx: float, y_top: float, y_bot: float, n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := PackedVector3Array()
	var nr := PackedVector3Array()
	for i in n:
		var a := TAU * i / n
		var z := cz * cos(a)
		var x := tx * sin(a) * (0.75 + 0.25 * cos(a)) * 1.25      # blunt leading edge (-z), fine trailing edge (+z)
		ring.append(Vector3(x, 0.0, -z))
		nr.append(Vector3(sin(a) / tx, 0.0, -cos(a) / cz).normalized())
	for i in n:
		var j := (i + 1) % n
		var a0 := ring[i] + Vector3(0, y_top, 0); var a1 := ring[j] + Vector3(0, y_top, 0)
		var b0 := ring[i] + Vector3(0, y_bot, 0); var b1 := ring[j] + Vector3(0, y_bot, 0)
		_quad(st, a0, a1, b0, b1, nr[i], nr[j], nr[i], nr[j], (nr[i] + nr[j]).normalized())
		_tri(st, Vector3(0, y_bot, 0), b0, b1, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN)
	return st.commit()

## Three-blade propeller around +Z: twisted, rounded blades (two-sided) on a small hub.
static func _propeller(r1: float, r0: float, blades: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nr := 7
	var nc := 5
	for b in blades:
		var a0 := TAU * b / blades
		var grid: Array = []
		for i in nr:
			var f := float(i) / (nr - 1)
			var r := lerpf(r0, r1, f)
			var chord := 0.11 * pow(sin(lerpf(0.25, 1.0, f) * PI * 0.92), 0.6) + 0.012
			var twist := atan(0.32 / (TAU * r))                     # constant-pitch blade: steeper near the hub
			var ang := a0 + 0.35 * f * f                             # gentle skew
			var radial := Vector3(cos(ang), sin(ang), 0.0)
			var tang := Vector3(-sin(ang), cos(ang), 0.0)
			var row := PackedVector3Array()
			for k in nc:
				var c := (float(k) / (nc - 1) - 0.5) * chord
				row.append(radial * r + tang * c * cos(twist) + Vector3(0, 0, 1) * c * sin(twist))
			grid.append(row)
		for i in nr - 1:
			for k in nc - 1:
				var p00: Vector3 = grid[i][k]; var p01: Vector3 = grid[i][k + 1]
				var p10: Vector3 = grid[i + 1][k]; var p11: Vector3 = grid[i + 1][k + 1]
				var n := (p10 - p00).cross(p01 - p00).normalized()
				_quad(st, p00, p01, p10, p11, n, n, n, n, n)
				_quad(st, p00, p01, p10, p11, -n, -n, -n, -n, -n)
	var hub := Geo.lathe(PackedVector2Array([Vector2(0.0, -0.06), Vector2(0.045, -0.05), Vector2(0.05, 0.03), Vector2(0.03, 0.08), Vector2(0.0, 0.09)]), 12)
	var arr := hub.surface_get_arrays(0)
	var hv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var hn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var hi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for idx in hi:
		var v := hv[idx]
		var nn := hn[idx]
		st.set_normal(Vector3(nn.x, -nn.z, nn.y))
		st.add_vertex(Vector3(v.x, -v.z, v.y))                     # lathe axis +Y -> +Z
	return st.commit()
