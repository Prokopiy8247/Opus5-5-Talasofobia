extends RefCounted
## Helper for Beat 6: the far trench wall (a dark slope revealed by small warm pools around its lamps and a faint
## body of light the whole field throws on its gullies, both baked into textures), the field of amber lamp
## points (one MultiMesh of fog-compensated billboards, no real lights), for the near floor lamps the faint
## threads rising above them and their pools on the silt, and a few other descent lines hanging in the dark
## close to the diver's own ("you are not the first"), each ending at a lamp on the floor.

const WALL_DIST := 950.0
const WALL_HALF := 3000.0
const WALL_H := 1150.0
const NU := 140
const NV := 36
const POOL_W := 2048                 # ~2.9 x 2.4 m per texel: pools of ~6-9 m, a small halo per lamp
const POOL_H := 512
const GLOW_W := 256                  # ~23 x 19 m per texel: the low-frequency glow body (sigma ~2 texels)
const GLOW_H := 64
const THREAD_RANGE := 450.0          # threads only on plain lamps this close (far ones would read as scratches)
const FORESHADOW_N := 5              # wall lamps faintly on during the approach
## Foreshadow targets (u, v) on the wall: scattered chance lights, never one row of runway lights.
const FORESHADOW_UV := [Vector2(0.33, 0.07), Vector2(0.42, 0.31), Vector2(0.51, 0.14), Vector2(0.58, 0.44),
	Vector2(0.68, 0.22)]
const NEAR_LINES := 5                # other descent lines hanging 18-35 m from the diver's own
const NEAR_LINE_TOP := 450.0         # they reach this far up from the floor (the top is never near the diver)
const NEAR_LINE_R := 0.035           # heavier, older lines (must match BASE_R in far_line.gdshader)
const NEAR_LINE_COL := Color(0.38, 0.355, 0.30)  # #4f4636 furred with settled snow and silt (sRGB)
const NEAR_LINE_SEG := 3.0           # ring spacing: the coverage law needs vertices along the line
const BEACON_POOL := 12.0            # m across: the hatch lamp's pool as seen from above
const BEACON_POOL_GAIN := 0.9

var _noise := FastNoiseLite.new()
var _end: Vector3
var _floor_y: float
var _rocks: Array = []               # Vector3(x, z, radius) of the floor boulders


## A floor lamp pushed clear of the boulders: its additive pool is depth-tested, so a rock under it read as a
## black hole in the light. Deterministic (no RNG), so the field's layout only moves where it has to.
func _clear_of_rocks(p: Vector3) -> Vector3:
	for it in 2:
		for rk in _rocks:
			var rv: Vector3 = rk
			var dv := Vector2(p.x - rv.x, p.z - rv.y)
			var need := rv.z + 3.5   # the pool's hot centre (r < ~0.4 of 6-9 m) stays on bare silt
			if dv.length() < need:
				var dir := dv.normalized() if dv.length() > 0.01 else Vector2(1.0, 0.0)
				p.x = rv.x + dir.x * need
				p.z = rv.y + dir.y * need
	return p


func build(parent: Node3D, end: Vector3, floor_y: float, wall_n: int, plain_n: int, hatch_lamp: Vector3, ground: Callable, rocks: Array = []) -> Dictionary:
	_end = end
	_floor_y = floor_y
	_rocks = rocks
	_noise.seed = 19
	_noise.frequency = 1.0
	_noise.fractal_octaves = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	# --- lamp placements
	var lamps: Array = []     # [pos, delay, brightness, kind (0 plain/wall, 0.5 foreshadow, 1 always on)]
	lamps.append([hatch_lamp, 0.0, 0.8, 1.0])
	var pool_data := PackedFloat32Array()
	pool_data.resize(POOL_W * POOL_H)
	var glow_data := PackedFloat32Array()
	glow_data.resize(GLOW_W * GLOW_H)
	# lamps where lines come down: loose clusters plus scattered singles, never a grid; the field thins out
	# toward the wall's ends and starts a little above its foot (no ruler-straight lower edge)
	var clusters: Array = []
	for c in 34:
		clusters.append(Vector2(clampf(0.5 + rng.randfn(0.0, 0.21), 0.02, 0.98), 0.05 + pow(rng.randf(), 1.3) * 0.82))
	var wall_idx: Array = []
	for i in wall_n:
		var u := clampf(0.5 + rng.randfn(0.0, 0.21), 0.02, 0.98)
		var v := 0.05 + pow(rng.randf(), 1.35) * 0.88
		if rng.randf() < 0.55:
			var c: Vector2 = clusters[rng.randi() % clusters.size()]
			u = clampf(c.x + rng.randfn(0.0, 0.012), 0.0, 1.0)
			v = clampf(c.y + rng.randfn(0.0, 0.03), 0.03, 0.95)
		var p := _wall(u, v) + _wall_normal(u, v) * 1.5
		wall_idx.append(lamps.size())
		var lb := rng.randf_range(0.55, 1.15)
		lamps.append([p, 0.0, lb, 0.0, u, v])
		var pw := rng.randf_range(0.6, 1.0)
		_stamp(pool_data, POOL_W, POOL_H, u * POOL_W, v * POOL_H, pw, 3, 1.0)
		_stamp(glow_data, GLOW_W, GLOW_H, u * GLOW_W, v * GLOW_H, pw * lb, 6, 4.0)
	# foreshadow: a few wall lamps scattered over the field (different heights, uneven spacing), faintly on
	# while the diver descends; each gets its own faint level in the shader (seed)
	for f in FORESHADOW_N:
		var best := -1
		var best_d := 1e9
		var fs: Vector2 = FORESHADOW_UV[f]
		for wi in wall_idx:
			var L: Array = lamps[wi]
			if L[3] > 0.0 or L[5] > 0.5:
				continue
			var dd := absf(L[4] - fs.x) + absf(L[5] - fs.y) * 0.5
			if dd < best_d:
				best_d = dd
				best = wi
		if best >= 0:
			lamps[best][3] = 0.5
	var plain_first := lamps.size()
	for i in plain_n:
		var ang := rng.randf_range(PI * 0.55, PI * 1.45) if rng.randf() < 0.8 else rng.randf() * TAU
		var r := lerpf(45.0, 480.0, pow(rng.randf(), 1.5))
		var p := _clear_of_rocks(_end + Vector3(cos(ang) * r, 0.0, sin(ang) * r))
		p.y = float(ground.call(p.x, p.z)) + 0.9
		lamps.append([p, 0.0, rng.randf_range(0.6, 1.1), 0.0])
	# reveal order: a wave from near to far, with jitter
	var dmin := 1e9
	var dmax := 0.0
	for L in lamps:
		var d: float = (L[0] as Vector3).distance_to(_end)
		dmin = minf(dmin, d)
		dmax = maxf(dmax, d)
	for L in lamps:
		var d: float = (L[0] as Vector3).distance_to(_end)
		L[1] = 0.6 + (d - dmin) / maxf(dmax - dmin, 1.0) * 8.5 + rng.randf_range(0.0, 1.6)
	# other descent lines near the diver's own: own RNG and appended last, so every other placement, delay and
	# seed of the field stays exactly as before (they are nearer than any plain lamp, dmin is the hatch lamp)
	var lrng := RandomNumberGenerator.new()
	lrng.seed = 4242
	var line_first := lamps.size()
	var line_bear := [PI * 0.78, PI * 1.22, PI * 1.72, PI * 0.12, PI * 0.42]   # two inside the M5 cone
	for k in NEAR_LINES:
		var ang: float = line_bear[k] + lrng.randf_range(-0.12, 0.12)
		var r := lrng.randf_range(18.0, 35.0)   # never close enough to outshine the diver's own line
		var p := _clear_of_rocks(_end + Vector3(cos(ang) * r, 0.0, sin(ang) * r))
		p.y = float(ground.call(p.x, p.z)) + 0.9
		var d := p.distance_to(_end)
		lamps.append([p, 0.6 + (d - dmin) / maxf(dmax - dmin, 1.0) * 8.5 + lrng.randf_range(0.0, 0.8),
			lrng.randf_range(0.7, 1.0), 0.0])
	var mats: Array = []
	# --- lamp points
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	mm.mesh = quad
	mm.instance_count = lamps.size()
	for i in lamps.size():
		var L: Array = lamps[i]
		mm.set_instance_transform(i, Transform3D(Basis(), L[0]))
		var seed_v := rng.randf() if i < line_first else lrng.randf()
		mm.set_instance_custom_data(i, Color(L[1], L[2], seed_v, L[3]))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var lamp_mat := ShaderMaterial.new()
	lamp_mat.shader = load("res://shaders/lamps.gdshader")
	lamp_mat.set_shader_parameter("lamp_col", Palette.AMBER)
	mi.material_override = lamp_mat
	mi.custom_aabb = AABB(_end - Vector3(4000, 400, 4000), Vector3(8000, 2200, 8000))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mats.append(lamp_mat)
	# --- threads (plain lamps only: the near lines are real lines) and floor pools (both)
	var near: Array = []
	var pooled: Array = []
	for i in range(plain_first, lamps.size()):
		var L: Array = lamps[i]
		if (L[0] as Vector3).distance_to(_end) < THREAD_RANGE:
			pooled.append(L)
			if i < line_first:
				near.append(L)
	var tm := MultiMesh.new()
	tm.transform_format = MultiMesh.TRANSFORM_3D
	tm.use_custom_data = true
	tm.mesh = quad
	tm.instance_count = near.size()
	for i in near.size():
		var L: Array = near[i]
		tm.set_instance_transform(i, Transform3D(Basis(), L[0]))
		tm.set_instance_custom_data(i, Color(L[1], L[2], 0.0, 0.0))
	var pm := MultiMesh.new()
	pm.transform_format = MultiMesh.TRANSFORM_3D
	pm.use_custom_data = true
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	pm.mesh = plane
	pm.instance_count = pooled.size() + 1
	for i in pooled.size():
		var L: Array = pooled[i]
		pm.set_instance_transform(i, _pool_xform(L[0], lerpf(6.0, 9.0, clampf((float(L[2]) - 0.6) / 0.5, 0.0, 1.0)), ground))
		pm.set_instance_custom_data(i, Color(L[1], L[2], 0.0, 0.0))
	# the hatch beacon's pool, seen from above through the murk during the approach (kind 1, lamp_pool.gdshader)
	pm.set_instance_transform(pooled.size(), _pool_xform(hatch_lamp, BEACON_POOL, ground))
	pm.set_instance_custom_data(pooled.size(), Color(0.0, BEACON_POOL_GAIN, 0.0, 1.0))
	var line_mat := ShaderMaterial.new()
	line_mat.shader = load("res://shaders/lamp_line.gdshader")
	line_mat.set_shader_parameter("lamp_col", Palette.AMBER)
	var ti := MultiMeshInstance3D.new()
	ti.multimesh = tm
	ti.material_override = line_mat
	ti.custom_aabb = AABB(_end - Vector3(600, 50, 600), Vector3(1200, 250, 1200))
	ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ti)
	mats.append(line_mat)
	var pool_mat := ShaderMaterial.new()
	pool_mat.shader = load("res://shaders/lamp_pool.gdshader")
	pool_mat.set_shader_parameter("lamp_col", Palette.AMBER)
	var pi := MultiMeshInstance3D.new()
	pi.multimesh = pm
	pi.material_override = pool_mat
	pi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(pi)
	mats.append(pool_mat)
	# --- the other descent lines: one mesh, lit by the torch, the bottom few metres glow from their own lamp
	var far_line_mat := ShaderMaterial.new()
	far_line_mat.shader = load("res://shaders/far_line.gdshader")
	far_line_mat.set_shader_parameter("rope_col", NEAR_LINE_COL)
	far_line_mat.set_shader_parameter("lamp_col", Palette.AMBER)
	far_line_mat.set_shader_parameter("fade", 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for k in NEAR_LINES:
		var L: Array = lamps[line_first + k]
		var lp: Vector3 = L[0]
		var lean_a := lrng.randf() * TAU
		var lean := Vector3(cos(lean_a), 0.0, sin(lean_a)) * lrng.randf_range(1.0, 3.0)
		var sag := Vector3(-sin(lean_a), 0.0, cos(lean_a)) * lrng.randf_range(-0.6, 0.6)
		var pts := PackedVector3Array()
		var n := int(ceil(NEAR_LINE_TOP / NEAR_LINE_SEG))
		for q in n + 1:
			var f := float(q) / n
			pts.append(lp + Vector3(0.0, 0.25 + f * (NEAR_LINE_TOP - 0.25), 0.0) + lean * f + sag * (4.0 * f * (1.0 - f)))
		base = _line_tube(st, pts, base, 6, float(L[1]), float(L[2]), lp.y)
	var lines := MeshInstance3D.new()
	lines.mesh = st.commit()
	lines.material_override = far_line_mat
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lines.extra_cull_margin = 2.0   # the shader inflates the tubes with distance
	parent.add_child(lines)
	mats.append(far_line_mat)
	# --- trench wall
	var pool := Image.create_from_data(POOL_W, POOL_H, false, Image.FORMAT_RF, pool_data.to_byte_array())
	var glow := Image.create_from_data(GLOW_W, GLOW_H, false, Image.FORMAT_RF, glow_data.to_byte_array())
	var wall := MeshInstance3D.new()
	wall.mesh = _wall_mesh()
	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = load("res://shaders/trench.gdshader")
	wall_mat.set_shader_parameter("pools", ImageTexture.create_from_image(pool))
	wall_mat.set_shader_parameter("glow", ImageTexture.create_from_image(glow))
	wall_mat.set_shader_parameter("glow_size", Vector2(GLOW_W, GLOW_H))
	wall_mat.set_shader_parameter("lamp_col", Palette.AMBER)
	wall.material_override = wall_mat
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(wall)
	mats.append(wall_mat)
	return {"lamp_mat": lamp_mat, "wall_mat": wall_mat, "far_line_mat": far_line_mat, "mats": mats}


## The pool quad of a floor lamp: laid on the local slope, `size` metres across, lifted just enough that the
## curved floor (6 m cells, dunes) never cuts into it, but no more (a high quad floats like a decal).
func _pool_xform(lp: Vector3, size: float, ground: Callable) -> Transform3D:
	var e := 2.0
	var gx := float(ground.call(lp.x + e, lp.z)) - float(ground.call(lp.x - e, lp.z))
	var gz := float(ground.call(lp.x, lp.z + e)) - float(ground.call(lp.x, lp.z - e))
	var n := Vector3(-gx / (2.0 * e), 1.0, -gz / (2.0 * e)).normalized()
	var bx := n.cross(Vector3.FORWARD).normalized()
	var bz := bx.cross(n).normalized()
	var g0 := Vector3(lp.x, float(ground.call(lp.x, lp.z)), lp.z)
	var dev := 0.0
	for k in 12:
		var a := TAU * k / 12.0
		var rr := size * (0.5 if k % 2 == 0 else 0.3)
		var q := Vector3(lp.x + cos(a) * rr, 0.0, lp.z + sin(a) * rr)
		var yp := g0.y - (n.x * (q.x - g0.x) + n.z * (q.z - g0.z)) / n.y
		dev = maxf(dev, float(ground.call(q.x, q.z)) - yp)
	var off := clampf(dev + 0.03, 0.05, 0.6)
	return Transform3D(Basis(bx * size, n, bz * size), g0 + n * off)


## One line tube appended to st (rings of `sides`, wound clockwise from outside like Rope.gd). UV.y runs by arc
## length at the rope's strand scale; UV2 = (height above its lamp, reveal delay); COLOR.r = lamp brightness.
func _line_tube(st: SurfaceTool, p: PackedVector3Array, base: int, sides: int, delay: float, bright: float, lamp_y: float) -> int:
	var n := p.size()
	var acc := 0.0
	for k in n:
		var t := (p[mini(k + 1, n - 1)] - p[maxi(k - 1, 0)]).normalized()
		var side := t.cross(Vector3.FORWARD).normalized()
		if side.length() < 0.5:
			side = t.cross(Vector3.RIGHT).normalized()
		var up := side.cross(t).normalized()
		if k > 0:
			acc += p[k].distance_to(p[k - 1])
		for a in sides + 1:
			var ang := TAU * float(a) / sides
			var nrm := side * cos(ang) + up * sin(ang)
			st.set_normal(nrm)
			st.set_uv(Vector2(float(a) / sides, acc / 0.09))   # <= ~5000: no wrap inside a tube (it would smear)
			st.set_uv2(Vector2(p[k].y - lamp_y, delay))
			st.set_color(Color(bright, 0.0, 0.0))
			st.add_vertex(p[k] + nrm * NEAR_LINE_R)
	for k in n - 1:
		for a in sides:
			var i0 := base + k * (sides + 1) + a
			var i1 := i0 + sides + 1
			st.add_index(i0)
			st.add_index(i0 + 1)
			st.add_index(i1)
			st.add_index(i0 + 1)
			st.add_index(i1 + 1)
			st.add_index(i1)
	return base + n * (sides + 1)


func _wall(u: float, v: float) -> Vector3:
	var z := lerpf(-WALL_HALF, WALL_HALF, u)
	var h := v * WALL_H
	var n := _noise.get_noise_2d(u * 9.0, v * 5.0)
	var x := _end.x - WALL_DIST - h * 0.42 + pow(z / WALL_HALF, 2.0) * 520.0 + n * 40.0
	return Vector3(x, _floor_y - 20.0 + h + n * 25.0, _end.z + z)


func _wall_normal(u: float, v: float) -> Vector3:
	var e := 0.002
	var a := _wall(u + e, v) - _wall(u - e, v)
	var b := _wall(u, v + e) - _wall(u, v - e)
	var nrm := a.cross(b).normalized()
	return nrm if nrm.x > 0.0 else -nrm


func _wall_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in NV + 1:
		for i in NU + 1:
			var u := float(i) / NU
			var v := float(j) / NV
			st.set_uv(Vector2(u, v))
			st.add_vertex(_wall(u, v))
	for j in NV:
		for i in NU:
			var a := j * (NU + 1) + i
			st.add_index(a)
			st.add_index(a + NU + 1)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(a + NU + 1)
			st.add_index(a + NU + 2)
	st.generate_normals()
	return st.commit()


## A gaussian blob exp(-d^2 / s2) of weight w around (cx, cy) in texels, accumulated (the shader clamps).
## Pools: rad 3, s2 1 (sigma ~0.7 texel, ~2 m). Glow body: rad 6, s2 4 (sigma ~1.4 texels, ~30 m).
func _stamp(data: PackedFloat32Array, dw: int, dh: int, cx: float, cy: float, w: float, rad: int, s2: float) -> void:
	for y in range(int(cy) - rad, int(cy) + rad + 1):
		if y < 0 or y >= dh:
			continue
		for x in range(int(cx) - rad, int(cx) + rad + 1):
			if x < 0 or x >= dw:
				continue
			var d2 := (x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy)
			data[y * dw + x] += w * exp(-d2 / s2)
