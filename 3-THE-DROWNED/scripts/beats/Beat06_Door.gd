extends RefCounted
## Beat 6 - The Door: a very small watertight door (about 2 m) set into the hull plating at the foot of the
## wall, under an amber lamp that lights the floor: a doubler plate round the opening (wall shader, so it is
## part of the hull and lit by the lamp like the plating), a low coaming, the leaf on its frame. Rubble and bent
## plate shards, a coil of silted rope and a ladder climbing into the dark. The line ends here, tied to a
## pad-eye beside the door.
## The lamp is a DoorLamp node (group "door_lamp", set_power(p)).

const DoorLamp := preload("res://scripts/gen/DoorLamp.gd")
const Wall := preload("res://scripts/beats/Beat05_Wall.gd")
const BULB := Vector3(0.0, 2.56, 0.42)
const RING := Vector3(-1.1, 0.33, 0.27)
const SILL_H := 0.42                 # coaming height over the silt (the old 0.85 m sill stood on a stool)
const WALL_KEYS := ["wave_origin", "door_pos", "digits_rect", "backdrop", "rail_y", "tier_k0",
	"reveal_override", "dark_override"]

var _xf := Transform3D.IDENTITY      # door frame: origin on the sill, +Z out of the wall, +X along it
var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _lumps: Array = []               # rubble lumps [centre, plan radius] (door frame): the tie keeps clear


## Floor height in door-local coordinates.
func _floor(lx: float, lz: float) -> float:
	var w := _xf * Vector3(lx, 0.0, lz)
	return Terrain.height(w.x, w.z) - _xf.origin.y


func build(parent: Node3D) -> void:
	_rng.seed = 66
	_noise.seed = 6
	_noise.frequency = 0.9
	var dx := Config.DOOR_POS.x
	var wz := Wall.surface_z(dx)
	var floor_y := Terrain.height(dx, wz + 3.0)
	var yaw := -atan(dx / Wall.CURVE_R)          # local +Z along the wall normal, +X along the curve
	_xf = Transform3D(Basis(Vector3.UP, yaw), Vector3(dx, floor_y + SILL_H, wz))
	var root := Node3D.new()
	root.name = "Door"
	root.transform = _xf
	parent.add_child(root)
	# the doubler plate round the opening: hull plating (the wall shader, plain), a shade darker, from under
	# the silt to above the lamp; on the wall's layer, so the shader lights it from the lamp like the wall
	var dp := {"plain": 1.0, "tone": 0.8}
	if Wall.wall_material:
		for k in WALL_KEYS:
			dp[k] = Wall.wall_material.get_shader_parameter(k)
	var doubler := MeshBuilder.new()
	doubler.box(Vector3(0, 0.75, 0.035), Vector3(2.6, 4.7, 0.07))
	var dmi := doubler.instance(Mats.make("wall", dp), root)
	dmi.name = "Doubler"
	dmi.layers = DoorLamp.WALL_LAYER
	var steel := _prop(Palette.STEEL_DARK, 0.55, 0.25, 0.3, 0.3)
	var frame := MeshBuilder.new()
	# the frame: a flat bar welded round the opening (1.16 x 2.0 m), proud of the doubler by 16 cm; the
	# coaming at the bottom stands a little further out
	frame.box(Vector3(-0.65, 0.98, 0.15), Vector3(0.14, 2.1, 0.16))
	frame.box(Vector3(0.65, 0.98, 0.15), Vector3(0.14, 2.1, 0.16))
	frame.box(Vector3(0, 2.07, 0.15), Vector3(1.44, 0.14, 0.16))
	frame.box(Vector3(0, -0.07, 0.17), Vector3(1.44, 0.14, 0.2))
	frame.box(RING + Vector3(0, 0.09, -0.17), Vector3(0.24, 0.24, 0.16))  # pad-eye plate for the line
	frame.box(RING + Vector3(0, 0.09, -0.06), Vector3(0.05, 0.13, 0.12))  # its lug
	frame.torus(RING, Vector3(1, 0, 0), 0.075, 0.016, 12, 6)              # the ring through the lug
	# lamp: wall bracket, conical shade, wire cage
	frame.box(Vector3(0, 2.86, 0.16), Vector3(0.07, 0.07, 0.6))
	frame.cylinder(Vector3(0, 2.86, 0.42), Vector3(0, 2.72, 0.42), 0.02, 0.02, 6)
	frame.cylinder(Vector3(0, 2.74, 0.42), Vector3(0, 2.6, 0.42), 0.05, 0.19, 14, false)
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		frame.cylinder(Vector3(cos(a) * 0.17, 2.62, 0.42 + sin(a) * 0.17), Vector3(cos(a) * 0.08, 2.44, 0.42 + sin(a) * 0.08), 0.008, 0.008, 4, false)
	frame.torus(Vector3(0, 2.45, 0.42), Vector3.UP, 0.08, 0.008, 10, 4)
	_shadowed(frame.instance(steel, root))
	# the leaf closes on the outside of the frame, overlapping it: hinges on one side, dogs on the other
	var door := MeshBuilder.new()
	door.box(Vector3(0, 1.0, 0.265), Vector3(1.24, 2.08, 0.07))
	for k in 3:
		door.box(Vector3(0.68, 0.35 + k * 0.65, 0.27), Vector3(0.16, 0.12, 0.07))   # hinges
	for yk in [0.45, 1.55]:
		door.box(Vector3(-0.68, yk, 0.27), Vector3(0.12, 0.07, 0.07))               # dogs
	door.box(Vector3(0, 2.1, 0.27), Vector3(0.07, 0.12, 0.07))
	door.torus(Vector3(-0.32, 1.0, 0.33), Vector3(0, 0, 1), 0.1, 0.022, 12, 6)    # handle wheel
	door.torus(Vector3(0, 1.45, 0.31), Vector3(0, 0, 1), 0.15, 0.025, 16, 6)      # window rim
	_shadowed(door.instance(_prop(Palette.STEEL_DARK.lightened(0.15), 0.7, 0.2, 0.2, 0.25), root))
	# round window in the door, lit from inside
	var win := MeshBuilder.new()
	win.cylinder(Vector3(0, 1.45, 0.29), Vector3(0, 1.45, 0.305), 0.13, 0.13, 16)
	var win_mat := Mats.emissive(Palette.AMBER, 2.2)
	win.instance(win_mat, root).layers = DoorLamp.PROP_LAYER
	var lamp := DoorLamp.new()
	root.add_child(lamp)
	lamp.setup(BULB)
	lamp.add_emitter(win_mat, "emission_energy", 2.2, true)
	var dbg_power: float = Wall._arg("door-power", -1.0)      # harness only: --door-power X
	if dbg_power >= 0.0:
		lamp.set_power(dbg_power)
	for i in 3:
		_rng.randf()          # the old stair's draws: the rubble keeps its layout
	_rubble(root)
	_rope(root)
	_ladder(root)


## Door props cast the lamp's shadows and sit on DoorLamp.PROP_LAYER (the silt decal skips them).
func _shadowed(mi: MeshInstance3D, layer := DoorLamp.PROP_LAYER) -> MeshInstance3D:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED   # open shade, thin plates
	mi.layers = layer
	return mi


## Steel / stone lit by the lamp: see shaders/door_prop.gdshader.
func _prop(base: Color, rust: float, moss: float, noise: float, metal: float, silt := 0.0) -> ShaderMaterial:
	return Mats.make("door_prop", {"base_color": base, "rust_amount": rust, "moss_amount": moss,
		"noise_scale": noise, "metallic": metal, "roughness": 0.75, "silt_amount": silt})


## Noise-displaced lump (radii = size / 2), centre c, orientation b, broken by two cut planes (flat fracture
## faces: rubble, not pebbles). Smooth normals (the faces around each vertex, averaged) so it reads as worn
## rock, not flat facets flipping colour; darker where it sinks into the silt (vertex AO).
func _rock(mb: MeshBuilder, c: Vector3, size: Vector3, b: Basis) -> void:
	_lumps.append([c, maxf(size.x, size.z) * 0.7])
	var rows := 7
	var cols := 11
	# the lump's detail draws from its own generator; the main sequence moves on by a fixed count, so the
	# rubble layout does not depend on the lump's resolution
	var r := RandomNumberGenerator.new()
	r.seed = _rng.randi()
	for i in 98:
		_rng.randf()
	var off := Vector3(r.randf() * 50.0, r.randf() * 50.0, r.randf() * 50.0)
	var cuts: Array[Vector4] = []
	for k in 2:
		var cn := Vector3(r.randf_range(-1.0, 1.0), r.randf_range(-0.2, 1.0), r.randf_range(-1.0, 1.0)).normalized()
		cuts.append(Vector4(cn.x, cn.y, cn.z, r.randf_range(0.5, 0.78)))
	var pts: Array[Vector3] = []
	for i in rows + 1:
		var th := PI * float(i) / float(rows)
		var n_ring := 1 if i == 0 or i == rows else cols
		for j in n_ring:
			var ph := TAU * (float(j) + 0.5 * float(i % 2) + r.randf_range(-0.15, 0.15)) / float(cols)
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var disp := 1.0 + 0.34 * _noise.get_noise_3dv(d * 1.7 + off) + 0.12 * _noise.get_noise_3dv(d * 4.3 + off * 1.3)
			disp *= 1.0 - 0.18 * maxf(d.y, 0.0)          # a flatter, silted top
			var q := d * disp
			for cut in cuts:
				var cn := Vector3(cut.x, cut.y, cut.z)
				var h := q.dot(cn) - cut.w
				if h > 0.0:
					q -= cn * h
			pts.append(c + b * (q * size * 0.5))
	var vi := func(i: int, j: int) -> int:               # index of ring i, column j (poles are single points)
		if i == 0:
			return 0
		if i == rows:
			return 1 + (rows - 1) * cols
		return 1 + (i - 1) * cols + posmod(j, cols)
	var tris: Array[Vector3i] = []
	for i in rows:
		for j in cols:
			var a: int = vi.call(i, j)
			var b1: int = vi.call(i, j + 1)
			var c1: int = vi.call(i + 1, j + 1)
			var d1: int = vi.call(i + 1, j)
			if i > 0:
				tris.append(Vector3i(a, b1, c1))
			if i < rows - 1:
				tris.append(Vector3i(a, c1, d1))
	var nrm := PackedVector3Array()
	nrm.resize(pts.size())
	for t in tris:
		var fn := (pts[t.y] - pts[t.x]).cross(pts[t.z] - pts[t.x])     # area weighted
		if fn.dot((pts[t.x] + pts[t.y] + pts[t.z]) / 3.0 - c) < 0.0:
			fn = -fn
		nrm[t.x] += fn
		nrm[t.y] += fn
		nrm[t.z] += fn
	var base := mb.v.size()
	for k in pts.size():
		var p: Vector3 = pts[k]
		var fl := _floor(p.x, p.z)
		var ao := lerpf(0.4, 1.0, smoothstep(fl - 0.05, fl + 0.3 * size.y + 0.05, p.y))
		mb.vert(p, nrm[k].normalized() if nrm[k].length_squared() > 1e-12 else (p - c).normalized(), Vector2(p.x, p.z), Color(ao, 0, 0.5, 0.5))
	for t in tris:
		mb.tri(base + t.x, base + t.y, base + t.z)


func _keep_clear(p: Vector3, r: float) -> bool:
	if absf(p.x) < 1.25 + r and p.z < 3.0 + r:                      # the doorway's apron
		return false
	if Vector2(p.x - 2.05, p.z - 1.75).length() < 0.95 + r:          # the rope coil
		return false
	if absf(p.x - 1.75) < 0.5 + r and p.z < 0.8 + r:                 # the ladder foot
		return false
	return true


## Rubble fallen from the wall: lumps with a lognormal size mix, bent plate shards, all partly buried.
func _rubble(root: Node3D) -> void:
	var rocks := MeshBuilder.new()
	var placed := 0
	var tries := 0
	while placed < 58 and tries < 600:
		tries += 1
		var s := clampf(exp(_rng.randfn(-1.05, 0.75)), 0.07, 1.9)
		var p := Vector3(_rng.randf_range(-9.0, 9.0), 0.0, 0.5 + 10.0 * pow(_rng.randf(), 1.7))
		if not _keep_clear(p, s * 0.5):
			continue
		var size := Vector3(s * _rng.randf_range(0.8, 1.4), s * _rng.randf_range(0.45, 0.9), s * _rng.randf_range(0.7, 1.2))
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.35, 0.35))
		p.y = _floor(p.x, p.z) + size.y * (0.5 - _rng.randf_range(0.3, 0.55))
		_rock(rocks, p, size, b)
		placed += 1
	# rock (concretion and broken stone, hardly any rust) under a skin of silt like the seabed's
	_shadowed(rocks.instance(_prop(Color(0.2, 0.19, 0.17), 0.08, 0.12, 0.35, 0.0, 0.75), root))
	var shards := MeshBuilder.new()
	placed = 0
	tries = 0
	while placed < 10 and tries < 300:
		tries += 1
		var ln := _rng.randf_range(0.4, 1.9)
		var w := ln * _rng.randf_range(0.35, 0.7)
		var p := Vector3(_rng.randf_range(-7.5, 7.5), 0.0, 0.6 + 8.0 * pow(_rng.randf(), 1.4))
		if not _keep_clear(p, ln * 0.5):
			continue
		p.y = _floor(p.x, p.z) + _rng.randf_range(-0.05, 0.12)
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.BACK, _rng.randf_range(-0.7, 0.7)) \
			* Basis(Vector3.RIGHT, _rng.randf_range(-0.35, 0.35))
		p.y -= ln * _rng.randf_range(0.05, 0.2)                     # one end sunk in the silt
		var fold := _rng.randf_range(0.12, 0.5) * (1.0 if _rng.randf() < 0.5 else -1.0)
		shards.box(p + b * Vector3(-ln * 0.25, 0, 0), Vector3(ln * 0.5, 0.035, w), b)
		var b2 := b * Basis(Vector3(0.25, 0.0, 1.0).normalized(), fold)      # a skewed, torn bend
		shards.box(p + b2 * Vector3(ln * 0.22, 0, 0), Vector3(ln * 0.44, 0.035, w * _rng.randf_range(0.55, 0.9)), b2)
		placed += 1
	_shadowed(shards.instance(_prop(Palette.STEEL_DARK.darkened(0.2), 0.35, 0.2, 0.2, 0.2, 0.45), root))


## A coil of silted rope beside the door (touching turns, two flat layers) and the end of the line
## lying across the silt to the ring on the pad-eye.
func _rope(root: Node3D) -> void:
	var rr := 0.03
	var pitch := 2.0 * rr + 0.003
	var cc := Vector3(2.05, 0.0, 1.75)
	var fy := _floor(cc.x, cc.z)
	var pts := PackedVector3Array()
	var r0 := 0.15
	var turns := 7.0
	var a := 0.0
	while a <= turns * TAU:
		var r := r0 + a / TAU * pitch
		pts.append(cc + Vector3(cos(a) * r, fy + rr + 0.004 * sin(a * 3.7), sin(a) * r))
		a += 0.2
	var a1 := a
	var r1 := r0 + turns * pitch
	while a <= a1 + 4.6 * TAU:
		var u := (a - a1) / TAU
		var r := r1 - 0.02 - u * pitch
		var y := fy + rr + lerpf(0.0, 1.75 * rr, smoothstep(0.0, 0.5, u))
		pts.append(cc + Vector3(cos(a) * r, y + 0.004 * sin(a * 2.9), sin(a) * r))
		a += 0.2
	# the free end crosses the coil and trails off on the silt
	var last := pts[pts.size() - 1]
	var out := Vector3(cos(a + 0.6), 0, sin(a + 0.6))
	for i in range(1, 9):
		var t := float(i) / 8.0
		var q := last.lerp(cc + out * (r1 + 0.7) + Vector3(0.0, 0.0, 0.25 * sin(t * 3.0)), t)
		q.y = maxf(_floor(q.x, q.z) + rr, lerpf(last.y + 0.05, fy + rr, smoothstep(0.0, 0.6, t)) + 0.04 * sin(t * PI))
		pts.append(q)
	var coil := Rope.tube(pts, rr, 6)
	var end: Vector3 = root.to_local(PathDef.main.rope_pos(PathDef.main.length))
	var ring_low := RING + Vector3(0, -0.075, 0)
	# the line comes down along its own heading, lies on the silt in a smooth curve clear of the rubble, the coil
	# and the doorway, and rises to the ring (Rope.lay)
	var avoid := _lumps.duplicate()
	avoid.append([cc, r1 + 0.12])
	avoid.append([Vector3(0.0, 0.0, 1.3), 0.7])                      # the doorway's apron
	var tan: Vector3 = _xf.basis.inverse() * PathDef.main.tangent(PathDef.main.length)
	var tie := Rope.lay(end, ring_low, func(x: float, z: float) -> float: return _floor(x, z), 0.025, avoid, 0.1, tan)
	Rope.tube(tie, 0.025, 6, coil)
	_shadowed(coil.instance(Mats.make("rope", {"radius": 0.03, "rope_color": Color(0.3, 0.28, 0.2)}), root))


## A rung ladder beside the door, climbing to the first rub rail, far out of the lamp's reach.
func _ladder(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var x0 := 1.5
	var x1 := 2.0
	var zr := 0.2
	var y0 := _floor(1.75, zr) - 0.15
	var y1 := Wall.RAIL_Y[0] - 1.5 - _xf.origin.y
	for x in [x0, x1]:
		mb.box(Vector3(x, (y0 + y1) * 0.5, zr), Vector3(0.065, y1 - y0, 0.014))
		var yb := y0 + 0.6
		while yb < y1:
			mb.box(Vector3(x, yb, zr * 0.5), Vector3(0.05, 0.05, zr))     # stand-off brackets
			yb += 2.4
	var y := y0 + 0.45
	while y < y1 - 0.2:
		if _rng.randf() > 0.06:
			var sag := 0.0 if _rng.randf() > 0.05 else _rng.randf_range(0.02, 0.06)
			mb.cylinder(Vector3(x0, y, zr), Vector3((x0 + x1) * 0.5, y - sag, zr + sag), 0.012, 0.012, 6, false)
			mb.cylinder(Vector3((x0 + x1) * 0.5, y - sag, zr + sag), Vector3(x1, y, zr), 0.012, 0.012, 6, false)
		y += 0.3
	_shadowed(mb.instance(_prop(Palette.STEEL_DARK.lerp(Palette.RUST, 0.3), 0.75, 0.15, 0.15, 0.15), root))
