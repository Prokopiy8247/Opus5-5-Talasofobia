extends Node3D
## Beat 6 — The Floor and the Lights (7:20-9:00, 1260-1560 m). The beam finds silt; the line ends coiled
## beside a small hatch with an amber lamp. Looking up and around, the far slope of a trench wall is revealed
## by hundreds of tiny amber points, each the lamp at the end of another line. M5: the field of amber lights.

const FLOOR_Y := -1560.0
const WALL_LAMPS := 540
const PLAIN_LAMPS := 150
const ROPE_COL := Color("#4f4636")          # same literal as Rope.gd (Palette.ROPE stays unchanged)
const FLOOR_SIZE := 1800.0
const FLOOR_N := 300                          # 6 m cells: the far horizon reads as an irregular dune line
const PATCH_SIZE := 32.0                      # near-field sediment patch around the end point
const PATCH_N := 128                          # 0.25 m cells
const HAZE_LAMP_COL := Color(1.0, 0.80, 0.62)
const BULB_EMISSION := 9.0
const LAMP_ENERGY := 1.6
const LAMP_HAZE_GAIN := 0.3
const WALL_DIR := Vector3(-1.0, 0.0, 0.0)     # the trench wall and the lamp field lie toward -X
const PILE_OFF := Vector2(-0.3, 0.25)         # rope pile centre relative to where the line meets the floor
const CUE_LEAD := 2.0                        # the bulb flickers and a relay clunks this long before the wave
const REVEAL_TIMEOUT := 20.0                  # manual play: the wave starts anyway after this long
const SHADOW_DEPTH := 1490.0                  # below this the torch casts shadows (shared Player hook)
const LINES_IN := Vector2(1530.0, 1552.0)     # the other lines show only at the floor, rising from their lamp pools (never as hairlines beside the descent line on the approach)
const CAGE_LAYER := 2                         # render layer of the lamp cage: excluded from the bulb's own light

var depth_range := Vector2(1180.0, 1600.0)
var _mats: Array = []                         # lamp field materials that follow reveal_time
var _lamp_mat: ShaderMaterial
var _far_line_mat: ShaderMaterial              # the other descent lines near the diver's own
var _rocks: Array = []                         # Vector3(x, z, radius) of the boulders
var _sh := false                             # torch shadows requested (below SHADOW_DEPTH)
var _end: Vector3
var _hatch_pos: Vector3
var _coil_c: Vector3                         # where the hanging line meets the floor
var _pile_c: Vector3                         # centre of the rope pile
var _hatch_lamp: Node3D
var _bulb: MeshInstance3D
var _bulb_mat: StandardMaterial3D
var _lamp_light: OmniLight3D
var _hnoise := FastNoiseLite.new()           # large floor swell (250 m)
var _dnoise := FastNoiseLite.new()           # dunes (50 m), only far from the end point
var _base_h := PackedFloat32Array()          # rendered floor heights (offset from FLOOR_Y) on the FLOOR_N grid
var _patch_h := PackedFloat32Array()         # near-field relief on top of the floor (PATCH_N grid)

# reveal (gaze-gated for free-look play; autowalk keeps the timeline)
var _reveal_s := 0.0
var _auto_cue_s := 0.0
var _reveal_t := -1.0
var _cue_t := -1.0
var _cues := 0
var _arrive_t := -1.0
var _faced := 0.0
var _end_ready := false
var _floor_set := false
var _haze_on := false


func build(parent: Node3D) -> void:
	name = "Beat06_Floor"
	parent.add_child(self)
	_end = G.path.pos_at(G.path.length)
	_hatch_pos = Vector3(_end.x + 1.9, FLOOR_Y, _end.z - 1.4)
	_coil_c = G.path.rope_at(G.path.length)
	_pile_c = Vector3(_coil_c.x + PILE_OFF.x, FLOOR_Y, _coil_c.z + PILE_OFF.y)
	_hnoise.seed = 3
	_hnoise.frequency = 0.004
	_dnoise.seed = 11
	_dnoise.frequency = 0.02
	var t0 := Time.get_ticks_msec()
	_build_floor()
	_build_patch()
	_build_nodules()
	_build_remnants()
	_build_hatch()
	_build_coil()
	_build_trench_and_lamps()
	print("B6: built in %d ms" % (Time.get_ticks_msec() - t0))
	_reveal_s = G.path.s_at_depth(1536.0)
	_auto_cue_s = G.path.s_at_time(G.path.time_at(_reveal_s) - CUE_LEAD)
	var P := G.path
	# B5 films the creature's exit down to 1345 m (its cue ends there); only then does the gaze go down
	P.add_cue_depth(1345.0, 1360.0, Vector2(30.0, -40.0), 4.0)
	P.add_cue_depth(1360.0, 1505.0, Vector2(20.0, -84.0), 4.0)   # the beam finally finds silt
	P.add_cue_depth(1505.0, 1536.0, _hatch_lamp, 3.0)              # the hatch and its amber lamp
	P.add_cue_depth(1536.0, 1600.0, Vector2(92.0, 13.0), 5.0)     # up and around: the field of lights


# ---------------------------------------------------------------- terrain
## Analytic floor relief (offset from FLOOR_Y): flat around the end point, swells and dunes further out.
func _relief(x: float, z: float) -> float:
	var r := Vector2(x - _end.x, z - _end.z).length()
	return _hnoise.get_noise_2d(x, z) * 9.0 * smoothstep(12.0, 160.0, r) \
		+ _dnoise.get_noise_2d(x, z) * 2.2 * smoothstep(25.0, 140.0, r)


## Height of the RENDERED floor mesh (triangle-interpolated, offset from FLOOR_Y), so props sit exactly on it.
func floor_h(x: float, z: float) -> float:
	var cell := FLOOR_SIZE / FLOOR_N
	var fx := clampf((x - _end.x) / cell + FLOOR_N * 0.5, 0.0, FLOOR_N - 0.001)
	var fz := clampf((z - _end.z) / cell + FLOOR_N * 0.5, 0.0, FLOOR_N - 0.001)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var w := FLOOR_N + 1
	var h00 := _base_h[j * w + i]
	var h10 := _base_h[j * w + i + 1]
	var h01 := _base_h[(j + 1) * w + i]
	var h11 := _base_h[(j + 1) * w + i + 1]
	# same split as the index buffer: (a, a+1, a+w) and (a+1, a+w+1, a+w)
	if u + v <= 1.0:
		return h00 + (h10 - h00) * u + (h01 - h00) * v
	return h11 + (h01 - h11) * (1.0 - u) + (h10 - h11) * (1.0 - v)


## Near-field relief on top of the floor (0 outside the patch), bilinear like the patch mesh.
func patch_h(x: float, z: float) -> float:
	if _patch_h.is_empty():
		return 0.0
	var cell := PATCH_SIZE / PATCH_N
	var fx := (x - _end.x) / cell + PATCH_N * 0.5
	var fz := (z - _end.z) / cell + PATCH_N * 0.5
	if fx < 0.0 or fz < 0.0 or fx >= PATCH_N or fz >= PATCH_N:
		return 0.0
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var w := PATCH_N + 1
	var a := lerpf(_patch_h[j * w + i], _patch_h[j * w + i + 1], u)
	var b := lerpf(_patch_h[(j + 1) * w + i], _patch_h[(j + 1) * w + i + 1], u)
	return lerpf(a, b, v)


## World height of the visible ground at (x, z): floor plus the near-field patch.
func ground_y(x: float, z: float) -> float:
	return FLOOR_Y + floor_h(x, z) + patch_h(x, z)


func _build_floor() -> void:
	var w := FLOOR_N + 1
	var cell := FLOOR_SIZE / FLOOR_N
	_base_h.resize(w * w)
	for j in w:
		for i in w:
			var x := _end.x + (i - FLOOR_N * 0.5) * cell
			var z := _end.z + (j - FLOOR_N * 0.5) * cell
			_base_h[j * w + i] = _relief(x, z)
	var verts := PackedVector3Array()
	var nrms := PackedVector3Array()
	verts.resize(w * w)
	nrms.resize(w * w)
	for j in w:
		for i in w:
			var k := j * w + i
			var hx := _base_h[j * w + mini(i + 1, FLOOR_N)] - _base_h[j * w + maxi(i - 1, 0)]
			var hz := _base_h[mini(j + 1, FLOOR_N) * w + i] - _base_h[maxi(j - 1, 0) * w + i]
			verts[k] = Vector3(_end.x + (i - FLOOR_N * 0.5) * cell, FLOOR_Y + _base_h[k], _end.z + (j - FLOOR_N * 0.5) * cell)
			nrms[k] = Vector3(-hx / (2.0 * cell), 1.0, -hz / (2.0 * cell)).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = _grid_mesh(verts, nrms, PackedColorArray(), FLOOR_N)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/silt.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The most-viewed square metres as soft sediment: bioturbation mounds with burrows, a drift banked against
## the hatch, the coil pressed in. A 32 m patch 4 mm above the floor, edges blended back to it.
func _build_patch() -> void:
	var w := PATCH_N + 1
	var cell := PATCH_SIZE / PATCH_N
	var half := PATCH_SIZE * 0.5
	_patch_h.resize(w * w)
	_patch_h.fill(0.0)
	var dark := PackedFloat32Array()
	dark.resize(w * w)
	dark.fill(0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 606
	# mounds with a dark burrow on top, kept off the hatch, the coil and the lamp post
	var placed := 0
	var tries := 0
	while placed < 25 and tries < 400:
		tries += 1
		var ang := rng.randf() * TAU
		var r := lerpf(2.6, half - 2.5, sqrt(rng.randf()))
		var c := Vector2(_end.x + cos(ang) * r, _end.z + sin(ang) * r)
		if c.distance_to(Vector2(_hatch_pos.x, _hatch_pos.z)) < 2.6 or c.distance_to(Vector2(_pile_c.x, _pile_c.z)) < 1.8:
			continue
		placed += 1
		var hgt := rng.randf_range(0.12, 0.3)
		var rad := rng.randf_range(0.6, 1.2)
		var ext := int(ceil(rad * 2.6 / cell))
		var ci := int((c.x - _end.x + half) / cell)
		var cj := int((c.y - _end.z + half) / cell)
		for j in range(maxi(cj - ext, 0), mini(cj + ext, PATCH_N) + 1):
			for i in range(maxi(ci - ext, 0), mini(ci + ext, PATCH_N) + 1):
				var x := _end.x - half + i * cell
				var z := _end.z - half + j * cell
				var d2 := (x - c.x) * (x - c.x) + (z - c.y) * (z - c.y)
				var k := j * w + i
				_patch_h[k] += hgt * exp(-d2 / (rad * rad * 0.5)) - 0.07 * exp(-d2 / 0.03)
				dark[k] = maxf(dark[k], exp(-d2 / 0.05))
	# drift banked against one side of the hatch (away from the camera, beside the lamp)
	var drift_dir := Vector2(0.5, -0.87)
	var hc := Vector2(_hatch_pos.x, _hatch_pos.z)
	for j in w:
		for i in w:
			var x := _end.x - half + i * cell
			var z := _end.z - half + j * cell
			var k := j * w + i
			var v := Vector2(x, z) - hc
			var dh := v.length()
			if dh < 3.0:
				var side := smoothstep(-0.1, 0.75, v.normalized().dot(drift_dir))
				_patch_h[k] += 0.22 * exp(-pow((dh - 1.1) / 0.45, 2.0)) * side
			# the coil pressed into the silt
			var dc := Vector2(x - _pile_c.x, z - _pile_c.z).length()
			_patch_h[k] -= 0.03 * exp(-pow(dc / 0.6, 2.0))
			# edges blend back to the floor
			var e := minf(minf(i, PATCH_N - i), minf(j, PATCH_N - j)) * cell
			_patch_h[k] *= smoothstep(0.0, 3.0, e)
	var verts := PackedVector3Array()
	var nrms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(w * w)
	nrms.resize(w * w)
	cols.resize(w * w)
	var hh := PackedFloat32Array()
	hh.resize(w * w)
	for j in w:
		for i in w:
			var x := _end.x - half + i * cell
			var z := _end.z - half + j * cell
			hh[j * w + i] = floor_h(x, z) + _patch_h[j * w + i]
	for j in w:
		for i in w:
			var k := j * w + i
			var hx := hh[j * w + mini(i + 1, PATCH_N)] - hh[j * w + maxi(i - 1, 0)]
			var hz := hh[mini(j + 1, PATCH_N) * w + i] - hh[maxi(j - 1, 0) * w + i]
			verts[k] = Vector3(_end.x - half + i * cell, FLOOR_Y + hh[k] + 0.004, _end.z - half + j * cell)
			nrms[k] = Vector3(-hx / (2.0 * cell), 1.0, -hz / (2.0 * cell)).normalized()
			var b := 1.0 - 0.5 * dark[k] + 0.12 * clampf(_patch_h[k] * 4.0, -0.5, 0.5)
			cols[k] = Color(b, b * 0.99, b * 0.97)
	var mi := MeshInstance3D.new()
	mi.mesh = _grid_mesh(verts, nrms, cols, PATCH_N)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/silt.gdshader")
	m.set_shader_parameter("use_vcol", true)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON   # mounds throw the lamp's long shadows
	add_child(mi)


## Square grid mesh (n x n cells), faces clockwise seen from above (Godot front face).
func _grid_mesh(verts: PackedVector3Array, nrms: PackedVector3Array, cols: PackedColorArray, n: int) -> ArrayMesh:
	var w := n + 1
	var idx := PackedInt32Array()
	idx.resize(n * n * 6)
	var q := 0
	for j in n:
		for i in n:
			var a := j * w + i
			idx[q] = a
			idx[q + 1] = a + 1
			idx[q + 2] = a + w
			idx[q + 3] = a + 1
			idx[q + 4] = a + w + 1
			idx[q + 5] = a + w
			q += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrms
	if not cols.is_empty():
		arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


# ---------------------------------------------------------------- props
## Manganese nodules and a few rocks: 5 baked lumpy nodule shapes and 3 finer, more irregular boulders, uniform
## scale only (correct normals). They sit proud of the silt (a low cap of a buried sphere read as a crater).
func _build_nodules() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var nn := FastNoiseLite.new()
	nn.seed = 5
	nn.frequency = 1.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/nodule.gdshader")
	var meshes: Array = []
	var squash: Array = []
	for m in 5:
		var sq := Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.35, 0.6), rng.randf_range(0.7, 1.1))
		squash.append(sq)
		meshes.append(_lump_mesh(sq, nn, m * 17.0))
	# boulders: own RNG (the nodule/rock placement sequence stays as before), 28x16 spheres with a second,
	# finer displacement octave, so their outlines are irregular instead of 1 m polygon segments
	var rrng := RandomNumberGenerator.new()
	rrng.seed = 63
	var rock_meshes: Array = []
	var rock_sq: Array = []
	for m in 3:
		var sq := Vector3(rrng.randf_range(0.85, 1.3), rrng.randf_range(0.45, 0.7), rrng.randf_range(0.75, 1.1))
		rock_sq.append(sq)
		rock_meshes.append(_lump_mesh(sq, nn, 101.0 + m * 23.0, 28, 16, 0.08))
	var xforms: Array = [[], [], [], [], [], [], [], []]   # 5 nodule shapes, then 3 boulders
	var hc := Vector2(_hatch_pos.x, _hatch_pos.z)
	var cc := Vector2(_pile_c.x, _pile_c.z)
	var lp := Vector2(_hatch_pos.x + 0.95, _hatch_pos.z + 0.35)
	var count := 0
	var tries := 0
	while count < 520 and tries < 3000:
		tries += 1
		var small := count < 380
		var ang := rng.randf() * TAU
		var r: float
		var s: float
		if small:   # nodules: fist-sized, densest near the end point
			r = 1.2 + pow(rng.randf(), 1.4) * 38.0
			s = rng.randf_range(0.1, 0.32) * (1.0 + r * 0.01)
		else:       # scattered rocks further out
			r = 6.0 + pow(rng.randf(), 1.3) * 125.0
			s = rng.randf_range(0.45, 1.5) * (0.7 + r * 0.006)
		var p := Vector3(_end.x + cos(ang) * r, 0.0, _end.z + sin(ang) * r)
		var p2 := Vector2(p.x, p.z)
		if p2.distance_to(hc) < 1.25 + s * 0.6 or p2.distance_to(cc) < 0.75 + s * 0.6 or p2.distance_to(lp) < 0.15 + s * 0.6:
			continue
		count += 1
		var mk := rng.randi() % 5
		var sq: Vector3 = squash[mk]
		if not small:
			mk = 5 + mk % 3
			sq = rock_sq[mk - 5]
		# seat on the lowest ground under the footprint, so no lump floats on a mound's downhill side
		var gy := ground_y(p.x, p.z)
		var fr := 0.4 * s * maxf(sq.x, sq.z)
		for q in 4:
			var qa := TAU * q / 4.0 + 0.4
			gy = minf(gy, ground_y(p.x + cos(qa) * fr, p.z + sin(qa) * fr))
		p.y = gy - (0.08 if small else 0.15) * s * sq.y      # ~40% of a nodule stands above the silt
		if not small:
			_rocks.append(Vector3(p.x, p.z, 0.6 * s * maxf(sq.x, sq.z)))   # the lamps keep their pools clear
		xforms[mk].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
	for m in 8:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[m] if m < 5 else rock_meshes[m - 5]
		mm.instance_count = xforms[m].size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, xforms[m][i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)


## One lumpy nodule or boulder: a sphere squashed and noise-displaced (plus an optional finer octave), smooth
## normals regenerated.
func _lump_mesh(sq: Vector3, nn: FastNoiseLite, seed_off: float, segs := 14, rings := 9, fine := 0.0) -> ArrayMesh:
	var sph := SphereMesh.new()
	sph.radial_segments = segs
	sph.rings = rings
	var arr := sph.get_mesh_arrays()
	var src: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in ind:
		var v: Vector3 = src[k]
		var d := 1.0 + 0.22 * nn.get_noise_3d(v.x * 1.6 + seed_off, v.y * 1.6, v.z * 1.6)
		if fine > 0.0:
			d += fine * nn.get_noise_3d(v.x * 5.0 + seed_off, v.y * 5.0 - seed_off, v.z * 5.0)
		st.add_vertex(v * sq * d)
	st.index()
	st.generate_normals()
	return st.commit()


## Old rope remnants lying in the silt ("bones of old rope"): silt-dusted, half sunk, vanishing into the sediment.
func _build_remnants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 62
	var rope_mat := ShaderMaterial.new()
	rope_mat.shader = load("res://shaders/rope.gdshader")
	rope_mat.set_shader_parameter("rope_col", Color(0.55, 0.51, 0.44))   # silt-dusted (sRGB)
	rope_mat.set_shader_parameter("near_comp", 0.0)   # rope.gdshader near-exposure compensation is for the hanging line only
	var sink := FastNoiseLite.new()
	sink.seed = 23
	sink.frequency = 0.35
	for k in 9:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(7.0, 45.0)
		var c := _end + Vector3(cos(ang) * r, 0, sin(ang) * r)
		var pts := PackedVector3Array()
		var dir := rng.randf() * TAU
		var p := c
		var n := 26
		for q in n:
			dir += rng.randf_range(-0.35, 0.35)
			p += Vector3(cos(dir), 0, sin(dir)) * 0.6
			var nz := sink.get_noise_2d(p.x, p.z) * 0.5 + 0.5
			var off := lerpf(0.012, -0.05, smoothstep(0.34, 0.26, nz))
			if q == 0 or q == n - 1:
				off = -0.06   # both cut ends buried
			pts.append(Vector3(p.x, ground_y(p.x, p.z) + off, p.z))
		var mi2 := MeshInstance3D.new()
		mi2.mesh = _tube(pts, 0.032)
		mi2.material_override = rope_mat
		mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON   # torch and lamp shadows seat it in the silt
		add_child(mi2)


## The hatch: a rusted coaming sunk in the silt, its lid dogged open a few degrees over a black gap.
func _build_hatch() -> void:
	var rust := _rust_material()
	var hp := _hatch_pos
	var collar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.78
	cm.bottom_radius = 0.86
	cm.height = 0.5
	cm.radial_segments = 32
	collar.mesh = cm
	collar.material_override = rust
	collar.position = hp + Vector3(0, -0.05, 0)        # only ~0.2 m of coaming shows above the silt
	add_child(collar)
	var top := hp.y + 0.2
	# the dark opening under the lid (seen only through the gap)
	var hole := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.64
	hm.bottom_radius = 0.64
	hm.height = 0.004
	hm.radial_segments = 32
	hole.mesh = hm
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color(0.0, 0.0, 0.0)
	hole.material_override = black
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hole.position = Vector3(hp.x, top + 0.003, hp.z)
	add_child(hole)
	# lid on a hinge on the far side from the end point, lifted 5 deg toward the diver
	var to_cam := Vector2(_end.x - hp.x, _end.z - hp.z).normalized()
	var hinge_dir := Vector3(-to_cam.x, 0.0, -to_cam.y)
	var hinge := Node3D.new()
	hinge.position = Vector3(hp.x, top, hp.z) + hinge_dir * 0.7
	hinge.basis = Basis.looking_at(-hinge_dir, Vector3.UP)   # local -Z points from the hinge to the centre
	add_child(hinge)
	hinge.rotate_object_local(Vector3.RIGHT, deg_to_rad(5.0))
	var lid := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.66
	lm.bottom_radius = 0.7
	lm.height = 0.08
	lm.radial_segments = 32
	lid.mesh = lm
	lid.material_override = rust
	lid.position = Vector3(0, 0.04, -0.7)
	hinge.add_child(lid)
	var hub := Vector3(0, 0.13, -0.7)
	var wheel := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.25
	wheel.mesh = tm
	wheel.material_override = rust
	wheel.position = hub + Vector3(0, 0.03, 0)
	hinge.add_child(wheel)
	for k in 4:
		var spoke := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.03, 0.035)
		spoke.mesh = bm
		spoke.material_override = rust
		var a := deg_to_rad(90.0 * k + 20.0)
		spoke.position = hub + Vector3(cos(a), 0.0, -sin(a)) * 0.115 + Vector3(0, 0.03, 0)
		spoke.rotation = Vector3(0, a, 0)
		hinge.add_child(spoke)
	var boss := MeshInstance3D.new()
	var bs := CylinderMesh.new()
	bs.top_radius = 0.05
	bs.bottom_radius = 0.06
	bs.height = 0.07
	boss.mesh = bs
	boss.material_override = rust
	boss.position = hub + Vector3(0, 0.02, 0)
	hinge.add_child(boss)
	# hinge block and six dog clamps around the coaming rim
	var hb := MeshInstance3D.new()
	var hbm := BoxMesh.new()
	hbm.size = Vector3(0.26, 0.11, 0.16)
	hb.mesh = hbm
	hb.material_override = rust
	hb.position = Vector3(0, -0.02, 0.08)
	hinge.add_child(hb)
	for k in 6:
		var a := TAU * (k + 0.5) / 6.0
		var dog := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(0.12, 0.06, 0.08)
		dog.mesh = dm
		dog.material_override = rust
		var dv := Vector3(cos(a), 0.0, sin(a))
		dog.position = Vector3(hp.x, top + 0.02, hp.z) + dv * 0.8
		dog.basis = Basis(Vector3.UP, -a)
		add_child(dog)
	_build_lamp(hp, rust)


## Rusted steel, metallic 0 (no reflections at depth): dark rust mottle and pitting from noise, world triplanar.
func _rust_material() -> StandardMaterial3D:
	var fn := FastNoiseLite.new()
	fn.seed = 9
	fn.frequency = 0.02
	fn.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.11, 0.075, 0.06))
	ramp.set_color(1, Color(0.33, 0.19, 0.11))
	ramp.add_point(0.55, Color(0.21, 0.135, 0.10))
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = fn
	tex.color_ramp = ramp
	var nrm := NoiseTexture2D.new()
	nrm.width = 256
	nrm.height = 256
	nrm.seamless = true
	nrm.noise = fn
	nrm.as_normal_map = true
	nrm.bump_strength = 3.0
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.normal_enabled = true
	m.normal_texture = nrm
	m.normal_scale = 0.6
	m.metallic = 0.0
	m.roughness = 0.8
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(1.4, 1.4, 1.4)
	return m


## The lamp: post, small caged amber bulb, a short-range light that falls off softly and throws long shadows.
func _build_lamp(hp: Vector3, steel: Material) -> void:
	_hatch_lamp = Node3D.new()
	_hatch_lamp.position = hp + Vector3(0.95, 0.75, 0.35)
	add_child(_hatch_lamp)
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.03
	pm.bottom_radius = 0.045
	pm.height = 0.9
	post.mesh = pm
	post.material_override = steel
	post.position = Vector3(0, -0.5, 0)
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	post.layers = CAGE_LAYER   # not lit by its own bulb from centimetres away (it clipped to white)
	_hatch_lamp.add_child(post)
	_bulb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.11
	_bulb.mesh = sm
	_bulb_mat = StandardMaterial3D.new()
	_bulb_mat.albedo_color = Palette.AMBER
	_bulb_mat.emission_enabled = true
	_bulb_mat.emission = Palette.AMBER
	_bulb_mat.emission_energy_multiplier = BULB_EMISSION
	_bulb.material_override = _bulb_mat
	_bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hatch_lamp.add_child(_bulb)
	# guard cage: 4 thin bars between a top and a bottom ring. From above it reads as a ring with 4 dots around
	# the bulb (three crossed vertical rings read as an asterisk). On CAGE_LAYER: lit by the torch only, so it
	# silhouettes dark against the bulb instead of clipping to white from its own light centimetres away.
	for k in 2:
		var ring := MeshInstance3D.new()
		var rt := TorusMesh.new()
		rt.inner_radius = 0.074
		rt.outer_radius = 0.086
		rt.rings = 24
		rt.ring_segments = 6
		ring.mesh = rt
		ring.material_override = steel
		ring.position = Vector3(0.0, 0.075 if k == 0 else -0.075, 0.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.layers = CAGE_LAYER
		_hatch_lamp.add_child(ring)
	for k in 4:
		var bar := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.0055
		bc.bottom_radius = 0.0055
		bc.height = 0.15
		bc.radial_segments = 6
		bc.rings = 1
		bar.mesh = bc
		bar.material_override = steel
		var a := TAU * (k + 0.5) / 4.0
		bar.position = Vector3(cos(a) * 0.08, 0.0, sin(a) * 0.08)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # 8 cm from the bulb: 8-deg wedges over the pool
		bar.layers = CAGE_LAYER
		_hatch_lamp.add_child(bar)
	_lamp_light = OmniLight3D.new()
	_lamp_light.light_cull_mask = 0xFFFFF & ~CAGE_LAYER
	_lamp_light.light_color = Color(1.0, 0.80, 0.58)   # the emissive bulb keeps the saturated amber
	_lamp_light.light_energy = LAMP_ENERGY
	_lamp_light.omni_range = 14.0
	_lamp_light.omni_attenuation = 2.0                 # reaches ~0 well before the range window: no rim
	_lamp_light.light_volumetric_fog_energy = 0.0
	_lamp_light.shadow_enabled = true
	_lamp_light.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
	_lamp_light.shadow_bias = 0.02
	_lamp_light.shadow_normal_bias = 0.6
	_lamp_light.shadow_blur = 1.5
	_hatch_lamp.add_child(_lamp_light)
	var hm = G.haze.get("mat") if G.haze else null
	if hm is ShaderMaterial:
		hm.set_shader_parameter("lamp_decay", 2.0)   # glow concentrates into a ball around the bulb
	_update_haze_lamp(1.0)


## A compact glow ball in the water around the bulb. Its radius always stays smaller than the camera's distance
## to the bulb, so the eye is never inside it (inside, every view ray integrated a uniform red veil).
## While B6 is culled the slot is released (switched off once), so nothing else is overwritten every frame.
func _update_haze_lamp(k: float) -> void:
	if G.haze == null or not G.haze.has_method("set_lamp"):
		return
	var bp := _bulb.global_position
	var r := 0.0
	if visible:
		r = 3.5 if G.camera == null else minf(3.5, G.camera.global_position.distance_to(bp) - 0.6)
	if r >= 0.4:
		G.haze.set_lamp(bp, HAZE_LAMP_COL, r, LAMP_HAZE_GAIN * k)
		_haze_on = true
	elif _haze_on:
		G.haze.set_lamp(bp, HAZE_LAMP_COL, 0.0, 0.0)
		_haze_on = false


## The line ends in a loose pile: loops of varying size that cross over each other, then a tail sliding off.
func _build_coil() -> void:
	var c := _coil_c
	var pc := Vector2(_pile_c.x, _pile_c.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var loops := 6
	var per := 28
	var rads: Array = []
	var cens: Array = []
	for l in loops + 1:
		rads.append(rng.randf_range(0.32, 0.5))
		cens.append(pc + Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12)))
	# the pile lies beside the hanging end: the top loop passes right under it, so the line drops onto its rim
	rads[0] = PILE_OFF.length()
	cens[0] = pc
	var a0 := atan2(-PILE_OFF.y, -PILE_OFF.x)
	var pts := PackedVector3Array()
	pts.append(Vector3(c.x, FLOOR_Y + 0.3, c.z))          # joins the hanging line (Rope.gd ends here)
	pts.append(Vector3(c.x, FLOOR_Y + 0.21, c.z))
	# the line lands on top of the pile: walk the loops from the top (last laid) down to the bottom one
	var total := loops * per
	var last := Vector3.ZERO
	var tang := Vector3.ZERO
	for g in total + 1:
		var f := float(g) / per
		var li := mini(int(f), loops - 1)
		var fr := smoothstep(0.0, 1.0, f - li)
		var rad: float = lerpf(rads[li], rads[li + 1], fr)
		var cen: Vector2 = (cens[li] as Vector2).lerp(cens[li + 1], fr)
		var layer := float(loops - 1) - f                    # 5 at the top .. 0 at the bottom (continuous)
		var a := a0 + TAU * f
		var y := FLOOR_Y + 0.02 + 0.045 * (maxf(layer, 0.0) * 0.5 + 0.5 * sin(a * 1.3 + layer))
		var p := Vector3(cen.x + cos(a) * rad, maxf(y, FLOOR_Y + 0.01), cen.y + sin(a) * rad)
		if g > 0:
			tang = (p - last).normalized()
		pts.append(p)
		last = p
	# a 1.5 m tail sliding off across the silt, half sunk, its cut end buried
	var dir := Vector3(tang.x, 0.0, tang.z).normalized()
	var p2 := last
	for q in 12:
		dir = dir.rotated(Vector3.UP, 0.09)
		p2 += dir * 0.125
		var k := float(q + 1) / 12.0
		var gy := ground_y(p2.x, p2.z)
		var y2 := lerpf(last.y, gy - 0.01, smoothstep(0.0, 0.5, k))
		if q == 11:
			y2 = gy - 0.05
		pts.append(Vector3(p2.x, y2, p2.z))
	var mi := MeshInstance3D.new()
	mi.mesh = _tube(pts, 0.028)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/rope.gdshader")
	m.set_shader_parameter("rope_col", ROPE_COL)
	m.set_shader_parameter("near_comp", 0.0)   # keeps its look under the near-exposure compensation (rope package)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON   # loops shadow each other and the silt
	add_child(mi)


func _build_trench_and_lamps() -> void:
	var builder = load("res://scripts/beats/Beat06_Lights.gd").new()
	var res: Dictionary = builder.build(self, _end, FLOOR_Y, WALL_LAMPS, PLAIN_LAMPS, _bulb.global_position, ground_y, _rocks)
	_lamp_mat = res.lamp_mat
	_far_line_mat = res.far_line_mat
	_mats = res.mats


## A rope tube along p. Faces wind clockwise seen from outside (Godot's front face), so cull_back keeps the
## near half; UV.y runs by arc length at the same strand scale as Rope.gd (0.09 m).
func _tube(p: PackedVector3Array, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	var n := p.size()
	var acc := 0.0
	for k in n:
		var t := (p[min(k + 1, n - 1)] - p[max(k - 1, 0)]).normalized()
		var side := t.cross(Vector3.UP)
		if side.length() < 0.1:
			side = t.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(t).normalized()
		if k > 0:
			acc += p[k].distance_to(p[k - 1])
		for a in sides + 1:
			var ang := TAU * float(a) / sides
			var nrm := side * cos(ang) + up * sin(ang)
			st.set_normal(nrm)
			st.set_uv(Vector2(float(a) / sides, acc / 0.09))
			st.add_vertex(p[k] + nrm * radius)
	for k in n - 1:
		for a in sides:
			var i0 := k * (sides + 1) + a
			var i1 := i0 + sides + 1
			st.add_index(i0)
			st.add_index(i0 + 1)
			st.add_index(i1)
			st.add_index(i0 + 1)
			st.add_index(i1 + 1)
			st.add_index(i1)
	return st.commit()


# ---------------------------------------------------------------- runtime
## Two short dips of the hatch bulb (relay flicker), t seconds after the cue.
static func _flicker(t: float) -> float:
	if t < 0.0 or t > 0.5:
		return 1.0
	if t < 0.08 or (t > 0.2 and t < 0.31):
		return 2.0 / BULB_EMISSION
	return 1.0


func _fire_cue() -> void:
	_cue_t = 0.0
	_cues += 1
	if G.audio and G.audio.has_method("relay_clunk") and G.camera:
		var cp := G.camera.global_position
		G.audio.relay_clunk(cp + (WALL_DIR + Vector3(0.0, 0.3, 0.0)).normalized() * 35.0)   # from the wall's side


func _facing_field() -> bool:
	if G.camera == null:
		return false
	var fwd := -G.camera.global_basis.z
	return fwd.dot(WALL_DIR) > 0.45 and fwd.y > -0.5


func _process(dt: float) -> void:
	if G.player == null or _lamp_mat == null or not G.running:
		return
	var s: float = G.player.s
	var facing := _facing_field()
	# --- reveal: the wave of lamps waits until the diver looks at the field (autowalk keeps the timeline)
	if _cue_t >= 0.0:
		_cue_t += dt
	if _reveal_t < 0.0:
		if G.autowalk:
			if _cue_t < 0.0 and s >= _auto_cue_s:
				_fire_cue()
			if s >= _reveal_s and _cue_t >= CUE_LEAD:
				_start_wave()
		elif s >= _reveal_s:
			if _arrive_t < 0.0:
				_arrive_t = 0.0
			_arrive_t += dt
			if _cue_t < 0.0:
				_fire_cue()
			elif _cues < 2 and _arrive_t > 10.0 and not facing:
				_fire_cue()   # one reminder if the diver is still looking elsewhere
			if (facing and _cue_t >= CUE_LEAD) or _arrive_t >= REVEAL_TIMEOUT:
				_start_wave()
	else:
		_reveal_t += dt
		if facing:
			_faced += dt
		if not _end_ready and _reveal_t > 11.0 and (G.autowalk or _faced >= 4.0):
			_end_ready = true
			G.set("end_ready", true)
			print("B6: end_ready at t %.1f (reveal_t %.1f, faced %.1f s)" % [G.t, _reveal_t, _faced])
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter("reveal_time", _reveal_t)
	# faint foreshadow pinpoints on the far wall, ramped by depth (never by visibility)
	_lamp_mat.set_shader_parameter("foreshadow", 0.15 * smoothstep(1330.0, 1420.0, G.depth))
	# the single amber point far below (the hatch lamp) fades in after the 1160 m visibility toggle
	_lamp_mat.set_shader_parameter("beacon", smoothstep(1170.0, 1260.0, G.depth))
	# other descent lines in the dark: ramped by depth after the creature's exit, never by visibility
	_far_line_mat.set_shader_parameter("fade", smoothstep(LINES_IN.x, LINES_IN.y, G.depth))
	if G.env:
		_far_line_mat.set_shader_parameter("fog_density", G.env.fog_density)
		_far_line_mat.set_shader_parameter("fog_col", G.env.fog_light_color)   # the one (eye-adapted) water colour
	# torch shadows near the floor: every nodule, coil loop and hatch dog becomes a solid object (shared hook)
	var sh := G.depth > SHADOW_DEPTH
	if sh != _sh and G.player.has_method("set_torch_shadows"):
		G.player.set_torch_shadows(sh)
		_sh = sh
	# hatch bulb: relay flicker before the wave
	var k := _flicker(_cue_t)
	_bulb_mat.emission_energy_multiplier = BULB_EMISSION * k
	_lamp_light.light_energy = LAMP_ENERGY * k
	_update_haze_lamp(k)
	# eye adapting near the bright silt: the torch eases down over the last 28 m
	if G.depth > 1400.0:
		var ts := lerpf(1.0, 0.65, smoothstep(28.0, 5.0, -FLOOR_Y - G.depth))
		if "torch_scale" in G.player:
			G.player.set("torch_scale", ts)
		elif G.torch:
			G.torch.light_energy *= ts   # Player.step rewrites the energy every frame before beats run
	# bottom nepheloid layer: murkier beam haze near the floor (shared BeamHaze hook)
	var want := G.depth > 1300.0
	if want != _floor_set and G.haze and G.haze.has_method("set_floor"):
		_floor_set = want
		G.haze.set_floor(FLOOR_Y if want else -1.0e9)


func _start_wave() -> void:
	_reveal_t = 0.0
	print("B6: lamp wave starts at t %.1f, depth %.1f, autowalk %s, facing %s" % [G.t, G.depth, str(G.autowalk), str(_facing_field())])
