extends RefCounted
## All the animals of PELAGIC, the scale references: reef fish under the boat and at the anchor (beat 1), dense
## schools, two turtles and a reef shark along the wall (beat 2), stragglers (beat 3), a long dark shoal passing high
## in the empty blue and schools that flee the creature (beat 4), fish dust in front of the coils and cleaner fish
## on its skin and by its eye (beat 5). Motion lives in shaders/fish.gdshader.

const School := preload("res://scripts/fauna/FishSchool.gd")
const SP := preload("res://scripts/fauna/Species.gd")
const META := "res://assets/creatures/scp3000_meta.json"
const CLEAR := 15.0          # path line to the nearest animal (14 m rule + 1 m path sampling margin)
const WALL_LIMIT := -26.0    # fallback: animals stay right of this x when the wall mesh cannot be read
const WALL_CELL := 4.0       # (z, y) cell size of the wall-face index (m)
const WALL_MARGIN := 3.5     # extra clearance off the face for coral heads and fans on it

## Look of the big schools: true-size far fish (no inflation into strokes), 3D milling with crossing orbit planes,
## heading and roll noise, a slowly deforming outline, a denser core, satellite sub-groups and stragglers.
const BIG := {"max_infl": 1.25, "tilt": 0.35, "deform": 0.24, "sub": 0.1, "stray": 0.035, "falloff": 0.55}

var _root: Node3D
var _pts := PackedVector3Array()
var _count := 0
var _wall_x := {}            # Vector2i(z cell, y cell) -> max x of the actual wall face mesh in that cell


func build(parent: Node3D) -> void:
	_root = Node3D.new()
	_root.name = "Fauna"
	_root.top_level = true
	parent.add_child(_root)
	for i in int(PathDef.length / 2.0) + 1:
		_pts.append(PathDef.point(i * 2.0))
	_index_wall(parent)
	_beat1()
	_beat2()
	_beat3()
	_beat4()
	_beat5()
	print("PELAGIC fauna: %d groups, %d animals, %d wall cells" % [_root.get_child_count(), _count, _wall_x.size()])


static func _with(base: Dictionary, extra: Dictionary) -> Dictionary:
	var d := base.duplicate()
	d.merge(extra, true)
	return d


## Adds a group; unless opt.clear == false its centre is pushed until every animal keeps CLEAR from the path
## (and, with opt.wall, stays off the wall face (plus opt.wall_gap m) by going deeper instead).
func _add(species: String, center: Vector3, radii: Vector3, count: int, opt := {}) -> School:
	var basis: Basis = opt.get("basis", Basis.IDENTITY)
	var turb := float(opt.get("turbulence", 0.3))
	var spread := 1.12 + 0.55 * turb + 0.6 * float(opt.get("deform", 0.0))
	if float(opt.get("sub", 0.0)) > 0.0:
		spread = maxf(spread, 1.45)
	var ext := radii * spread + Vector3.ONE * float(opt.get("len", SP.DATA[species]["len"])) * 0.6
	var c := center
	if opt.get("clear", true):
		c = _clear(c, ext, basis, bool(opt.get("wall", false)), float(opt.get("wall_gap", 0.0)))
		if OS.is_debug_build() and "--fauna-debug" in OS.get_cmdline_user_args():
			print("fauna %s: %s -> %s" % [species, str(center.snapped(Vector3.ONE * 0.1)), str(c.snapped(Vector3.ONE * 0.1))])
	var s := School.new()
	s.name = "%s_%d" % [species, _root.get_child_count()]
	var host: Node3D = opt.get("parent", _root)
	host.add_child(s)
	s.setup(species, c, basis, radii, count, opt, 7919 * _root.get_child_count() + count)
	_count += count
	return s


func _support(ext: Vector3, basis: Basis, dir: Vector3) -> float:
	return (ext * (basis.transposed() * dir)).length()


func _closest(p: Vector3) -> Vector3:
	var best := _pts[0]
	var bd := INF
	for q in _pts:
		var d := p.distance_squared_to(q)
		if d < bd:
			bd = d
			best = q
	return best


## Indexes the built wall face (Beat02 runs first): the furthest-out x of the east face per (z, y) cell, so schools
## are kept off the real geometry whatever its relief.
func _index_wall(parent: Node3D) -> void:
	var mi := parent.get_node_or_null("Reef/WallFace") as MeshInstance3D
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return
	var xf := mi.global_transform
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v in verts:
		var p := xf * v
		if p.x < -80.0 or p.z < -470.0 or p.z > 340.0:
			continue
		var k := Vector2i(floori(p.z / WALL_CELL), floori(p.y / WALL_CELL))
		if p.x > float(_wall_x.get(k, -INF)):
			_wall_x[k] = p.x


## Smallest x a group centred at c (half extents sy, sz) may reach with its left edge.
func _wall_limit(c: Vector3, sy: float, sz: float) -> float:
	if _wall_x.is_empty():
		return WALL_LIMIT
	var lim := -INF
	for kz in range(floori((c.z - sz) / WALL_CELL), floori((c.z + sz) / WALL_CELL) + 1):
		for ky in range(floori((c.y - sy) / WALL_CELL), floori((c.y + sy) / WALL_CELL) + 1):
			lim = maxf(lim, float(_wall_x.get(Vector2i(kz, ky), -INF)))
	return lim + WALL_MARGIN if lim > -INF else -INF


func _clear(c: Vector3, ext: Vector3, basis: Basis, wall: bool, gap := 0.0) -> Vector3:
	var sx := _support(ext, basis, Vector3.RIGHT) + gap
	var sy := _support(ext, basis, Vector3.UP)
	var sz := _support(ext, basis, Vector3.BACK)
	for it in 16:
		if wall:
			c.x = maxf(c.x, _wall_limit(c, sy, sz) + sx)
		var dv := c - _closest(c)
		var d := maxf(dv.length(), 0.001)
		var u := dv / d
		var need := CLEAR + _support(ext, basis, u) - d
		if need <= 0.0:
			break
		var step := u * (need + 0.5)
		if wall and c.x + step.x - sx < _wall_limit(c + step, sy, sz):
			step = Vector3.DOWN * (need + 0.5)
		c += step
	if wall:
		c.x = maxf(c.x, _wall_limit(c, sy, sz) + sx)
	return c


func _beat1() -> void:
	# a small cloud of chromis in the shade under the boat (Beat01_Boat.BOAT_POS (1.2, 0, -8): the hull's shadow
	# falls a little towards the diver, the sun being ahead); the diver glides through its lower edge (x ~0,
	# y -3.2..-3.6) and the cloud parts around the mask (avoid: no fish within 2 m of the lens)
	_add("chromis", Vector3(1.4, -2.6, -7.9), Vector3(2.6, 0.7, 3.2), 150,
		{"clear": false, "tightness": 0.6, "turbulence": 0.25, "avoid": 2.0})
	# reef fish around the anchor line end on the reef top
	_add("anthias", Vector3(-31.0, -11.0, -40.0), Vector3(4.2, 1.8, 5.0), 280, {"tightness": 0.4, "deform": 0.15})
	_add("sergeant", Vector3(-35.5, -12.2, -31.0), Vector3(2.4, 1.0, 2.6), 80, {"tightness": 0.35})
	_add("fusilier", Vector3(-25.0, -8.0, -50.0), Vector3(3.0, 1.6, 6.5), 170,
		{"len": 0.18, "tightness": 0.6, "deform": 0.15, "stray": 0.05})


func _beat2() -> void:
	# dense schools between the path and the wall, mostly below the path so they stay 14 m clear
	var p := PathDef.point_at_time(58.0)
	_add("fusilier", p + Vector3(-17.0, -16.0, -6.0), Vector3(6.0, 4.5, 13.0), 3000,
		_with(BIG, {"wall": true, "tightness": 0.45, "max_infl": 1.3, "tilt": 0.2}))
	# money shot M1: a dense, slow-churning bait ball standing out from the wall up in the light, so the gaze looks up
	# into the sun at it: a dark, self-shaded mass with lit rims and travelling flank flashes against the bright water.
	# It casts sun shadows, so it also darkens the light rays below it.
	p = PathDef.point_at_time(104.0)
	var m1 := _add("sardine", p + Vector3(-6.0, 20.0, -2.0), Vector3(5.5, 6.0, 6.5), 11000,
		_with(BIG, {"wall": true, "wall_gap": 9.0, "tightness": 0.55, "turbulence": 0.35, "speed": 0.8, "len": 0.3,
		"tilt": 0.6, "head_jit": 0.35, "deform": 0.26, "sub": 0.1, "stray": 0.04, "falloff": 0.6, "shade": 2.5,
		"flash": 0.9, "flash_rate": 0.16, "shadow": true}))
	Game.targets["school_m1"] = m1
	# a jack tornado: big fish milling in a column (tilted orbits and a lumpy outline: no perfect ring from above)
	p = PathDef.point_at_time(122.0)
	_add("jack", p + Vector3(-18.0, -22.0, -8.0), Vector3(5.5, 9.0, 5.5), 1400,
		_with(BIG, {"wall": true, "wall_gap": 3.0, "tightness": 0.45, "turbulence": 0.4, "spin": -1.0,
		"hollow": 0.32, "tilt": 0.3, "deform": 0.22, "sub": 0.05, "stray": 0.05, "shade": 3.5}))
	# far below along the wall: the cliff keeps going down
	p = PathDef.point_at_time(140.0)
	_add("sardine", p + Vector3(-14.0, -45.0, -10.0), Vector3(6.0, 6.0, 18.0), 2500,
		_with(BIG, {"wall": true, "max_infl": 1.3, "sub": 0.06}))
	# two green turtles gliding on slow loops: one against the wall, one out in the blue on the right
	p = PathDef.point_at_time(50.0)
	_add("turtle", p + Vector3(-20.0, -5.0, -8.0), Vector3(5.0, 1.5, 12.0), 1,
		{"wall": true, "tightness": 1.0, "turbulence": 0.12})
	p = PathDef.point_at_time(100.0)
	_add("turtle", p + Vector3(19.0, -6.0, -22.0), Vector3(6.0, 2.0, 12.0), 1,
		{"tightness": 1.0, "turbulence": 0.12, "spin": -1.0})
	# a blacktip reef shark cruising a sinuous loop below the path near the wall foot
	p = PathDef.point_at_time(75.0)
	_add("shark", p + Vector3(-14.0, -20.0, -10.0), Vector3(8.0, 2.5, 12.0), 1,
		{"wall": true, "tightness": 1.0, "turbulence": 0.15})


func _beat3() -> void:
	# one small school left behind at the lip, drifting back along the wall as the player leaves
	var p := PathDef.point_at_time(158.0)
	var s := _add("sardine", p + Vector3(-20.0, -16.0, 6.0), Vector3(5.0, 4.0, 9.0), 450,
		{"wall": true, "speed": 1.0, "max_infl": 1.6, "deform": 0.2, "tilt": 0.25, "stray": 0.05})
	s.set_drift(Vector3(0.0, -0.05, 0.55))
	# loose stragglers: a few jacks each
	var spots := [[170.0, Vector3(20.0, -18.0, -10.0)], [192.0, Vector3(-24.0, -14.0, -6.0)],
		[216.0, Vector3(22.0, -30.0, -12.0)]]
	for sp in spots:
		_add("jack", PathDef.point_at_time(sp[0]) + sp[1], Vector3(9.0, 4.0, 9.0), 7,
			{"wall": true, "tightness": 0.15, "turbulence": 0.45, "speed": 0.8})


func _beat4() -> void:
	var cp := PathDef.v3(PathDef.load_layout()["creature_pos"])
	var ev := float(Config.EVENTS["hush_line"])
	# the one event of the long empty blue (about 180-245 s): far ahead and high, in the sun's quarter, a long dark
	# shoal of big jacks streams across from right to left at the edge of visibility (about 95-120 m), a smudge of
	# smoke against the glow; it bolts upward at the hush, before anything else is seen. Timed for the long look up at
	# the light (PathDef cue 199-240): it slides in from the top right as the view rises (~211 s), crosses the upper
	# half under the sun's glow during the hold and leaves at the top left as the view sinks to the dark line (~232 s)
	# (a living shoal, not one uniform cigar: four sub-schools of varying thickness along a curved, slowly
	# undulating spine (each its own soft-ended mill, drifting at slightly different speeds so the spine keeps
	# changing shape), two thin trailing tendrils, and a panic that runs along the shoal at the hush)
	var t0 := 215.0
	var dir := Vector3(-0.92, 0.0, -0.39).normalized()
	var sb := Basis(dir, Vector3.UP, dir.cross(Vector3.UP)).orthonormalized()
	var c0 := PathDef.point_at_time(t0) + Vector3(57.0, 68.0, -70.0)
	# spine (shoal space: x along the stream, y up, z across): u -1 (tail) .. 1 (head)
	var spine := func(u: float) -> Vector3:
		return Vector3(u * 40.0, 5.0 * sin(u * 2.3 + 0.6), 9.0 * sin(u * 1.7 - 0.3))
	# u, radii, count, drift tweak (m/s along the stream, m/s up)
	var subs := [[-0.72, Vector3(12.0, 3.5, 6.0), 1100, Vector2(-0.06, 0.02)],
		[-0.22, Vector3(13.0, 7.5, 8.0), 1500, Vector2(0.0, -0.03)],
		[0.26, Vector3(12.5, 9.0, 8.5), 1400, Vector2(0.05, 0.03)],
		[0.74, Vector3(11.0, 4.5, 6.5), 900, Vector2(0.09, -0.02)]]
	var stream: School = null
	for k in subs.size():
		var sp: Array = subs[k]
		var u: float = sp[0]
		var tg: Vector3 = (spine.call(u + 0.05) - spine.call(u - 0.05)).normalized()
		var bx: Vector3 = sb * tg
		var bz := bx.cross(Vector3.UP).normalized()
		var sbk := Basis(bx, bz.cross(bx), bz).orthonormalized()
		var s := _add("jack", c0 + sb * spine.call(u), sp[1], sp[2],
			{"basis": sbk, "near": false, "len": 0.75, "view_end": 420.0, "tightness": 0.4, "turbulence": 0.45,
			"speed": 1.0, "max_infl": 1.4, "deform": 0.26, "sub": 0.08, "tilt": 0.18, "falloff": 0.5,
			"stray": 0.045, "shade": 2.5, "clear": false})
		var tw: Vector2 = sp[3]
		s.set_path_drift(dir * (2.8 + tw.x) + Vector3.UP * tw.y, t0)
		s.set_window(Vector4(176.0, 196.0, 262.0, 280.0))
		# the panic runs along the shoal from its head
		s.flee(ev + 1.5 + 0.45 * float(subs.size() - 1 - k), (Vector3.UP * 0.5 + dir).normalized(), 4.0)
		s.flee_fade = Vector2(60.0, 150.0)
		if k == 1:
			stream = s
	# two thin trailing tendrils: one straggling behind the tail, one sagging below the middle
	var tendrils := [[Vector3(-50.0, 7.0, 4.0), Vector3(1.0, 0.25, 0.1), 260],
		[Vector3(4.0, -10.0, 6.0), Vector3(0.8, -0.65, 0.3), 150]]
	for td in tendrils:
		var bx: Vector3 = (sb * (td[1] as Vector3)).normalized()
		var ref := Vector3.UP if absf(bx.y) < 0.8 else Vector3.RIGHT
		var bz := bx.cross(ref).normalized()
		var s := _add("jack", c0 + sb * (td[0] as Vector3), Vector3(7.5, 2.0, 2.8), td[2],
			{"basis": Basis(bx, bz.cross(bx), bz).orthonormalized(), "near": false, "len": 0.75, "view_end": 420.0,
			"tightness": 0.25, "turbulence": 0.6, "speed": 1.0, "max_infl": 1.4, "deform": 0.3, "tilt": 0.3,
			"falloff": 0.2, "stray": 0.12, "shade": 1.0, "clear": false})
		s.set_path_drift(dir * 2.75, t0)
		s.set_window(Vector4(176.0, 196.0, 262.0, 280.0))
		s.flee(ev + 2.4, (Vector3.UP * 0.5 + dir).normalized(), 4.0)
		s.flee_fade = Vector2(60.0, 150.0)
	Game.targets["fish_stream"] = stream
	# gelatinous drifters (salp chains, one siphonophore) through the empty blue, gone before the dark line
	var drifters: Node3D = load("res://scripts/fauna/Drifters.gd").new()
	drifters.name = "Drifters"
	_root.add_child(drifters)
	# two schools far below the path, ahead under the dark line; at the hush they tighten and bolt sideways away from
	# the creature, streaming across the lower part of the view as it sinks to the dark line (238-260 s), then fade
	var specs := [[255.0, Vector3(-22.5, -79.5, -47.5), "sardine", Vector3(14.0, 6.0, 14.0), 2600, 4.5, 0.3],
		[285.0, Vector3(36.7, -98.8, -34.6), "jack", Vector3(12.0, 7.0, 12.0), 1800, 5.5, 0.55]]
	for sp in specs:
		var s := _add(sp[2], PathDef.point_at_time(sp[0]) + sp[1], sp[3], sp[4],
			_with(BIG, {"near": false, "len": sp[6], "view_end": 420.0, "tightness": 0.5, "max_infl": 1.3,
			"sub": 0.06}))
		var away: Vector3 = s.position - cp
		away.y = 0.0
		var lateral := Vector3(signf(sp[1].x), 0.0, 0.0)
		s.flee(ev, away.normalized() + lateral * 1.4, sp[5])


func _beat5() -> void:
	var f := FileAccess.open(META, FileAccess.READ)
	if f == null:
		return
	var meta: Dictionary = JSON.parse_string(f.get_as_text())
	var lay := PathDef.load_layout()
	var cp := PathDef.v3(lay["creature_pos"])
	var sc := float(lay.get("creature_scale", Config.CREATURE_SCALE))
	var rot := Basis(Vector3.UP, deg_to_rad(float(lay["creature_yaw"])))
	var cr = Game.targets.get("creature")
	var crn: Node3D = cr if is_instance_valid(cr) and cr is Node3D else null
	var spine: Array = meta["spine"]
	var last := spine.size() - 1

	# faint fish dust drifting across the line of sight to the coils (330-375 s): parallax against the giant
	var cam := PathDef.point_at_time(350.0)
	var coil := cp + rot * (PathDef.v3(spine[int(0.42 * last)]) * sc)
	var dust := _add("sardine", cam.lerp(coil, 0.24), Vector3(14.0, 3.0, 9.0), 900,
		{"near": false, "len": 0.26, "view_end": 300.0, "tightness": 0.25, "turbulence": 0.55, "speed": 0.7,
		"max_infl": 1.4, "deform": 0.3, "stray": 0.08, "shade": 1.0, "glint": 0.25})
	dust.set_path_drift(Vector3(0.0, 0.05, 1.1), 350.0)
	dust.set_window(Vector4(322.0, 336.0, 368.0, 382.0))

	# pilot fish (small silver jacks) 5-6 m off the skin on the upper side facing the path, the scale ladder of the
	# coils; they ride the body wave and are only as present as the creature (no glitter in mid-water around an
	# invisible body)
	var picks := [[86, 40], [102, 55], [118, 30], [134, 50], [148, 35]]
	var rig: Node3D = null
	if crn == null or not crn.has_method("deformed"):
		# fallback: the groups ride along with the creature's slow drift (SCP3000.riders)
		rig = Node3D.new()
		rig.name = "CleanerRig"
		_root.add_child(rig)
		if crn != null and "riders" in crn:
			crn.riders.append(rig)
	var inv := rot.inverse()
	for pk in picks:
		var i: int = pk[0]
		var sp := cp + rot * (PathDef.v3(spine[i]) * sc)
		var tg := (rot * PathDef.v3(meta["tangent"][i])).normalized()
		var r := float(meta["radius"][i]) * sc
		var to_path := _closest(sp) - sp
		var up := (Vector3.UP - tg * tg.dot(Vector3.UP)).normalized()
		var tp := (to_path - tg * tg.dot(to_path)).normalized()
		var n := (up + tp).normalized()
		var bz := tg.cross(n).normalized()
		var bx := n.cross(bz)
		var g := _add("jack", sp + n * (r + 5.5), Vector3(4.0, 1.4, 4.0), pk[1],
			{"basis": Basis(bx, n, bz), "near": false, "len": 0.45, "speed": 0.6, "tightness": 0.4,
			"turbulence": 0.3, "max_infl": 2.5, "shade": 0.0, "parent": rig if rig else _root})
		if crn != null:
			var anchor := PathDef.v3(spine[i]) + (inv * n) * ((r + 5.5) / sc)
			g.ride(crn, anchor, float(i) / float(last), false, 2)

	# The scale ladder of the giant (345-410 s): a school of big jacks (1.1 m fish, 16-20 px) swims along with the
	# diver about 32 m out, between the camera and the creature, crossing the view from in front of the coils and
	# the neck to in front of the head; the creature, 130-220 m behind it, slides past in parallax. At the hush
	# before the head turns they bolt (left and up, away from the head) and thin out; the eye lock is clear of them.
	var head_m = Game.targets.get("head")
	if is_instance_valid(head_m):
		var pass_pt := PathDef.point_at_time(372.0)
		var ladder := _add("jack", pass_pt + Vector3(32.0, -4.0, 0.0), Vector3(8.0, 3.0, 14.0), 380,
			{"clear": false, "len": 1.1, "speed": 0.9, "tightness": 0.4, "turbulence": 0.45, "tilt": 0.25,
			"deform": 0.25, "sub": 0.1, "stray": 0.06, "falloff": 0.3, "shade": 1.2, "glint": 0.6, "max_infl": 1.3,
			"view_end": 140.0, "head_jit": 0.2})
		# (6 m above the line to the head: it crosses over the skull and the neck, never over the eye)
		ladder.sightline(head_m, 32.0, 22.0, -0.55, 6.0, 350.0)
		ladder.set_window(Vector4(343.0, 353.0, 401.0, 410.0))
		ladder.flee(float(Config.EVENTS["hush_head"]), Vector3(-0.744, 0.5, -0.652), 3.5)
		ladder.flee_fade = Vector2(15.0, 45.0)
		Game.targets["scale_school"] = ladder

	# the scale reference of the eye lock: a group of silver jacks 30 m out on the line of sight to the eye, high
	# in the upper third of the frame and to the left (open water: the eye and the jaw stay clear through the head
	# turn), close enough to read as fish (0.9 m, ~14 px) beside the skull 90 m away
	var eye_marker = Game.targets.get("eye")
	var head := _add("jack", PathDef.point_at_time(415.0) + Vector3(25.0, 11.0, 0.0), Vector3(6.0, 2.2, 4.5),
		70, {"clear": false, "len": 0.9, "speed": 0.6, "tightness": 0.45, "turbulence": 0.3,
		"max_infl": 1.5, "shade": 0.0, "glint": 1.0, "roll_jit": 0.5, "view_end": 140.0})
	if is_instance_valid(eye_marker):
		head.sightline(eye_marker, 30.0, -8.0, 0.12, 11.0, 415.0)
	# (the camera holds the eye until ~440 s and then tilts down, the head leaving over the top edge ~458 s: the
	# group stays with the head and leaves over the top edge with it, fading late)
	head.set_window(Vector4(397.0, 405.0, 448.0, 460.0))
	Game.targets["head_fish"] = head
