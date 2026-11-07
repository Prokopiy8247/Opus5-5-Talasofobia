class_name Rope
extends RefCounted
## The descent line along the path, with small depth tags every Config.TAG_EVERY metres and, where it runs a
## few metres over the seabed, stays down to clump weights on the ground (what holds a line in midwater).
## One continuous rope from the surface buoy to the door: the down-line from the buoy runs into the guide line
## without a corner; at every tie-off (the stays, the shot weight's tie in the shallows) the line is pulled into
## a shallow V toward what holds it, at a steel collar with a shackle, so it never peaks over its supports.
## The rope shader keeps the line at least LINE_MIN_PX wide and lets the fog fade it (a receding line that
## thinned to a hair turned every bend into a hairpin); the stays are their own darker, thinner rope that
## shrinks away beyond STAY_FADE (far ones bunched under the foreshortened line like a wire tripod).
## Also generic rope/tube helpers used by the beats: tube() through points, lay() for a line laid on a floor.
## Interface: line_pos(s) = where the drawn line is at path distance s (rope_pos + the tie-off dips); after
## build(). SHOT_S / SHOT_W / SHOT_SIDE / shot_ground(): the shallows' shot weight (Beat01 puts it there),
## shot_tie: the shackle its line ties to (after build()).

const RADIUS := 0.025
const TAG_SIZE := Vector2(0.3, 0.15)     # depth tag plate (m)
const STAY_EVERY := 36.0                 # metres of line between stays
const STAY_H := Vector2(3.0, 40.0)       # stays only where the line runs this high over the ground
const STAY_END_H := Vector2(1.5, 4.5)    # ... and before the door only this low (in the dark a long stay's
                                         # weight is never seen: it ran out of the frame as a scratch)
const STAY_R := 0.014
const STAY_FADE := Vector2(24.0, 40.0)   # the stays shrink away over this distance from the camera
const LINE_MIN_PX := 3.0                 # floor width of the guide line on screen (px at 1080p)
const DIP := 0.32                        # how far a stay pulls the line down at its collar (m)
const DIP_W := 9.0                       # ... blended out over this many metres of line each side
const SHOT_S := 54.0                     # the shallows' shot weight ties onto the line here
const SHOT_W := 58.0                     # the weight lies on the sand abeam of this s ...
const SHOT_SIDE := -9.5                  # ... this far to the right of the walk (negative = left)
const COLLAR := Color(0.16, 0.15, 0.13)

static var _path: PathDef
static var _sites: Array = []            # [s, pull direction (unit), depth (m), half width (m of line)]
static var shot_tie := Vector3.ZERO      # the shackle under the shot weight's collar (after build())


## Tube through world points (already in world space). Returns the builder (identity transform).
static func tube(points: PackedVector3Array, radius: float, seg := 6, mb: MeshBuilder = null) -> MeshBuilder:
	if mb == null:
		mb = MeshBuilder.new()
	var rings := []
	var uu := PackedFloat32Array()
	var acc := 0.0
	var prev_x := Vector3.RIGHT
	for i in points.size():
		var t := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var x := prev_x - t * prev_x.dot(t)
		if x.length_squared() < 1e-6:
			x = t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT)
		x = x.normalized()
		prev_x = x
		var y := t.cross(x)
		if i > 0:
			acc += points[i].distance_to(points[i - 1])
		var ring := PackedVector3Array()
		for j in seg:
			var a := TAU * float(j) / float(seg)
			ring.append(points[i] + (x * cos(a) + y * sin(a)) * radius)
		rings.append(ring)
		uu.append(acc)
	var vv := PackedFloat32Array()
	for j in seg:
		vv.append(float(j) / float(seg))
	mb.grid(rings, uu, vv, true, true)
	return mb


## Ground point of the shallows' shot weight (Beat01_Shallows puts its block here).
static func shot_ground(path: PathDef) -> Vector3:
	var q := path.pos(SHOT_W) + path.right(SHOT_W) * SHOT_SIDE
	return Vector3(q.x, Terrain.height(q.x, q.z), q.z)


## Where the drawn line is at path distance s: rope_pos(s) pulled toward each tie-off it is near.
static func line_pos(s: float) -> Vector3:
	var path := _path if _path else PathDef.main
	var p := path.rope_pos(s)
	for st: Array in _sites:
		var x := absf(s - float(st[0])) / float(st[3])
		if x < 1.0:
			p += (st[1] as Vector3) * float(st[2]) * (1.0 - x) * (1.0 - x)
	return p


static func build(parent: Node3D, path: PathDef) -> Node3D:
	_path = path
	_sites = []
	var root := Node3D.new()
	root.name = "Line"
	parent.add_child(root)
	# the tie-offs first: they shape the line
	var stays := _stay_sites(path)
	for st: Dictionary in stays:
		_sites.append([st["s"], Vector3.DOWN, DIP, DIP_W])
	var shot_eye := shot_ground(path) + Vector3(0, 1.0, 0)
	var shot_pull := (shot_eye - path.rope_pos(SHOT_S)).normalized()
	_sites.append([SHOT_S, shot_pull, 0.4, 8.0])
	# the line: 1 m steps, 0.25 m near a tie-off (a crisp V, not a rounded sag)
	var pts := PackedVector3Array()
	var s := 0.0
	while s < path.length:
		pts.append(line_pos(s))
		var near := false
		for st: Array in _sites:
			if absf(s - float(st[0])) < 2.0:
				near = true
				break
		s += 0.25 if near else 1.0
	pts.append(line_pos(path.length))
	# from the surface buoy down to the start of the line: one rope, turning into the line's heading
	var start := pts[0]
	var t0 := (pts[2] - pts[0]).normalized()
	var buoy := Vector3(start.x - 2.0, Config.SURFACE_Y - 0.3, start.z + 6.0)
	var top := buoy + Vector3(0, -0.45, 0)
	var c1 := top + Vector3(0.4, -2.0, 0.0)
	var c2 := start - t0 * 2.2
	var hang := PackedVector3Array()
	for i in 16:
		var t := float(i) / 16.0
		var u := 1.0 - t
		hang.append(top * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + start * t * t * t)
	hang.append_array(pts)
	var mb := tube(hang, RADIUS, 6)
	var mi := mb.instance(Mats.make("rope", {"radius": RADIUS, "min_px": LINE_MIN_PX, "thin_exp": 0.25,
		"deep_glow": 0.09}), root)
	mi.name = "Rope"
	# stays, their clump weights and the hardware
	var sm := MeshBuilder.new()
	var weights := MeshBuilder.new()
	var hw := MeshBuilder.new()
	hw.color = Color(0.85, 0.0, 0.8, 0.4)
	for st: Dictionary in stays:
		_stay(st, sm, weights, hw)
	# the shot weight's tie: a collar and shackle where its line meets the guide line, and a small float on a
	# short leash above it (it is what holds the junction up: without it the line peaked over nothing)
	shot_tie = _collar(hw, SHOT_S, shot_pull)
	var fp := line_pos(SHOT_S) + Vector3(0.0, 0.62, 0.0)
	var leash := PackedVector3Array([line_pos(SHOT_S) + Vector3(0, RADIUS * 1.75, 0), fp + Vector3(0, -0.13, 0)])
	tube(leash, 0.008, 4, hw)
	var fl := MeshBuilder.new()
	fl.sphere(fp, 0.15, 12, Vector3(1.0, 0.85, 1.0))
	var fmi := fl.instance(Mats.solid(Color("#c8643a").darkened(0.15), 0.1, 0.1), root)
	fmi.name = "TieFloat"
	if sm.tri_count() > 0:
		var si := sm.instance(Mats.make("rope", {"radius": STAY_R, "rope_color": Color(0.5, 0.47, 0.36),
			"min_px": 1.5, "thin_exp": 0.4, "fade_far": STAY_FADE}), root)
		si.name = "Stays"
	if weights.tri_count() > 0:
		var wi := weights.instance(Mats.solid(Palette.BONE.darkened(0.4), 0.1, 0.6, {"noise_scale": 0.5}), root)
		wi.name = "StayWeights"
	var hi := hw.instance(Mats.solid(COLLAR, 0.6, 0.2, {"roughness": 0.6}), root)
	hi.name = "LineHardware"
	root.set_meta("stays", stays.size())
	# buoy
	var bb := MeshBuilder.new()
	bb.sphere(buoy, 0.45, 14, Vector3(1, 0.8, 1))
	bb.instance(Mats.solid(Color("#c8643a"), 0.1, 0.0), root)
	_tags(root, path)
	return root


## Depth tags: dark weathered plates with pale numbers, readable from both sides. Each hangs on a short lanyard
## beside the line, on the walker's side (the line runs to the walker's left: ROPE_OFFSET), turned a little toward
## the walker, so the line never crosses its digits; the text is sized to fit the plate.
static func _tags(root: Node3D, path: PathDef) -> void:
	var tag_mat := Mats.solid(Color(0.07, 0.075, 0.07), 0.2, 0.25, {"roughness": 0.7})
	var tags := MeshBuilder.new()
	var font := ThemeDB.fallback_font
	var s := Config.TAG_EVERY
	while s < path.length - 5.0:
		var p := line_pos(s)
		var t := path.tangent(s)
		var fh := Vector3(t.x, 0, t.z).normalized()
		var side := path.right(s)
		var face := (-fh + side * 0.3).normalized()      # back up the line, a little toward the walker
		var b := Basis(Vector3.UP.cross(face).normalized(), Vector3.UP, face)
		var eye := p + side * 0.2 + Vector3(0, -0.16, 0)
		var c := eye + Vector3(0, -TAG_SIZE.y * 0.5 - 0.015, 0)
		tags.box(c, Vector3(TAG_SIZE.x, TAG_SIZE.y, 0.012), b)
		# the lanyard droops from the line to the tag's eye (a stiff horizontal wire read as a spike)
		var lan := PackedVector3Array()
		var a0 := p + Vector3(0, -RADIUS * 0.6, 0)
		for k in 6:
			var u := float(k) / 5.0
			lan.append(a0.lerp(eye, u) + Vector3(0, -0.05 * sin(u * PI), 0))
		tube(lan, 0.005, 4, tags)
		tags.torus(eye, b.z, 0.014, 0.004, 8, 4)                                          # its eye
		var txt := "%d m" % int(round(-p.y))
		var w_px := 100.0
		if font:
			w_px = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 48).x
		var ps := minf(0.0019, (TAG_SIZE.x - 0.05) / maxf(w_px, 1.0))
		for sd in 2:
			var lab := Label3D.new()
			lab.text = txt
			lab.font_size = 48
			lab.pixel_size = ps
			lab.modulate = Color(0.72, 0.74, 0.66)
			lab.outline_size = 0
			lab.shaded = true
			lab.double_sided = false
			var f := face if sd == 0 else -face
			lab.position = c + f * 0.008
			lab.basis = b if sd == 0 else b.rotated(Vector3.UP, PI)
			lab.visibility_range_end = 32.0
			lab.visibility_range_end_margin = 6.0
			lab.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			root.add_child(lab)
		s += Config.TAG_EVERY
	tags.instance(tag_mat, root)    # ~60 small plates: no visibility range (a merged AABB would cull them)


## Stay sites: where the line runs STAY_H over the ground (the wreck slope; STAY_END_H on the floor before the
## door), every STAY_EVERY metres, clear of the Beat-2 hulls (Terrain.ship_pose boxes) and the rocks
## (Rocks.placed). Not in the shallows (the shot weight is there) nor among the forest, the statue and the wall.
## Each: {s, base (clump centre), bs (clump basis), nrm (ground normal)}.
static func _stay_sites(path: PathDef) -> Array:
	var boxes := []
	for key: String in Terrain.SHIP_KEYS:
		var ps := Terrain.ship_pose(key)
		if not ps.is_empty():
			boxes.append(ps)
	var out := []
	var s := 120.0
	while s < path.length - 45.0:
		if s > 430.0 and s < 1380.0:      # the forest, the statue, the wall: the line is high or near the giant
			s = 1380.0
		var p := path.rope_pos(s)
		var g := Terrain.height(p.x, p.z)
		var h := p.y - DIP - g
		var lim := STAY_H if s < 1380.0 else STAY_END_H
		if h < lim.x or h > lim.y or not _stay_clear(p, g, boxes):
			s += 4.0                     # try a little further on
			continue
		# the clump weight settles on the slope: tilted to the ground, its downhill edge sunk in
		var nrm := Terrain.normal(p.x, p.z, 0.6)
		var bs := Basis(Vector3.UP, fposmod(s * 0.37, TAU))
		var ax := Vector3.UP.cross(nrm)
		if ax.length_squared() > 1e-6:
			bs = Basis(ax.normalized(), Vector3.UP.angle_to(nrm)) * bs
		var base := Vector3(p.x, g, p.z) + nrm * 0.12
		var lift := -1e9                  # the ground is not a plane: no bottom corner may stand above it
		for k in 4:
			var q := base + bs * Vector3(0.34 * (1.0 if k % 2 == 0 else -1.0), -0.22, 0.29 * (1.0 if k < 2 else -1.0))
			var gq := minf(Terrain.height(q.x, q.z), Terrain.mesh_height(q.x, q.z))
			lift = maxf(lift, q.y - gq)
		base.y -= maxf(lift + 0.04, 0.0)
		out.append({"s": s, "base": base, "bs": bs, "nrm": nrm})
		s += STAY_EVERY
	return out


## One stay: a concrete clump with an iron eye, a taut line up to the shackle under the collar on the line.
static func _stay(st: Dictionary, sm: MeshBuilder, weights: MeshBuilder, hw: MeshBuilder) -> void:
	var s: float = st["s"]
	var base: Vector3 = st["base"]
	var bs: Basis = st["bs"]
	var nrm: Vector3 = st["nrm"]
	weights.box(base, Vector3(0.68, 0.44, 0.58), bs)
	weights.box(base + nrm * 0.24, Vector3(0.5, 0.06, 0.42), bs)      # a chamfered top: not a dice
	var eye := base + nrm * 0.36
	hw.torus(eye, bs.x, 0.07, 0.016, 10, 5)
	var shackle := _collar(hw, s, Vector3.DOWN)
	var line := PackedVector3Array()
	for i in 9:
		line.append(shackle.lerp(eye + nrm * 0.06, float(i) / 8.0))
	tube(line, STAY_R, 5, sm)


## A steel collar clamped on the line at s and a shackle hanging from it toward pull; returns the shackle's
## lower end (where the tie-off's own line starts).
static func _collar(hw: MeshBuilder, s: float, pull: Vector3) -> Vector3:
	var p := line_pos(s)
	var t := (line_pos(s + 0.3) - line_pos(s - 0.3)).normalized()
	hw.cylinder(p - t * 0.08, p + t * 0.08, RADIUS * 1.75, RADIUS * 1.75, 8, true)
	var d := (pull - t * pull.dot(t)).normalized()
	var ring_c := p + d * (RADIUS * 1.75 + 0.045)
	hw.torus(ring_c, t, 0.04, 0.011, 10, 4)
	return ring_c + d * 0.045


static func _stay_clear(p: Vector3, g: float, boxes: Array) -> bool:
	for ps: Dictionary in boxes:
		var xf: Transform3D = ps["transform"]
		var L: float = ps["length"]
		var B: float = ps["beam"]
		var D: float = ps["depth"]
		for k in 5:
			var q := Vector3(p.x, lerpf(p.y, g, float(k) / 4.0), p.z)
			var lp := xf.affine_inverse() * q
			if absf(lp.z) < L * 0.5 + 4.0 and absf(lp.x) < B * 0.5 + 4.0 and lp.y > -2.0 and lp.y < D * 1.6 + 4.0:
				return false
	for r: Array in Rocks.placed:
		var c: Vector3 = r[0]
		if Vector2(c.x - p.x, c.z - p.z).length() < float(r[1]) + 0.9:
			return false
	return true


## A line laid from a (where it hangs in the water) to b (its tie point), lying on the floor between: it leaves a
## along a_tan (the direction it arrives at a; zero = toward b), touches down tangentially, runs over the floor
## in a smooth curve that keeps `clear` metres (plan) from every [centre: Vector3, radius: float] in avoid, and
## rises to b. floor: Callable(x, z) -> floor height, in the same space as a and b. Points every ~0.1 m: no
## polyline corners, never under the floor.
static func lay(a: Vector3, b: Vector3, floor: Callable, radius := RADIUS, avoid: Array = [], clear := 0.1,
		a_tan := Vector3.ZERO) -> PackedVector3Array:
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var span := a2.distance_to(b2)
	var n := maxi(int(span / 0.1), 12)
	var th := Vector2(a_tan.x, a_tan.z)
	th = th.normalized() if th.length_squared() > 1e-6 else (b2 - a2).normalized()
	# plan route: a Bezier leaving a along the line's heading, pushed out of the props and relaxed
	var c1 := a2 + th * span * 0.35
	var c2 := b2 + (a2 - b2).normalized() * span * 0.2
	var xz := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		var u := 1.0 - t
		xz.append(a2 * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b2 * t * t * t)
	var ghost_a := a2 - th * (span / float(n))
	# props only matter where the line is down near the floor: not under its first, hanging stretch
	var drop0 := a.y - float(floor.call(a.x, a.z))
	var free := clampf(drop0 * 3.0, 0.6, span * 0.55) * 0.55
	var pw := PackedFloat32Array()
	for i in n + 1:
		pw.append(smoothstep(free, free * 1.5 + 0.3, a2.distance_to(xz[i])))
	for it in 80:
		for i in range(1, n):
			xz[i] = xz[i].lerp(_push(xz[i], avoid, radius + clear), pw[i])
		var nxt := xz.duplicate()
		for i in range(1, n):
			var prev := ghost_a if i == 1 and it < 40 else xz[i - 1]
			nxt[i] = xz[i].lerp((prev + xz[i + 1]) * 0.5, 0.45)
		xz = nxt
	for i in range(1, n):
		xz[i] = xz[i].lerp(_push(xz[i], avoid, radius + clear), pw[i])
	# arc length along the route
	var arc := PackedFloat32Array([0.0])
	for i in range(1, n + 1):
		arc.append(arc[i - 1] + xz[i].distance_to(xz[i - 1]))
	var L := arc[n]
	# heights: a Hermite drop from a (its own slope) to a tangential touchdown, the floor, a Hermite rise to b
	var ga := float(floor.call(a.x, a.z)) + radius
	var gb := float(floor.call(b.x, b.z)) + radius
	var slope_a := 0.0
	var ah := Vector2(a_tan.x, a_tan.z).length()
	if ah > 1e-4:
		slope_a = clampf(a_tan.y / ah, -1.0, 0.0)
	var td := clampf((a.y - ga) * 3.0, 0.6, L * 0.55)
	var tr := clampf((b.y - gb) * 1.1, 0.25, L * 0.3)
	var out := PackedVector3Array()
	for i in n + 1:
		var q := xz[i]
		var g := float(floor.call(q.x, q.y)) + radius
		var sd := arc[i]
		var y := g
		if sd < td:
			var u := sd / td
			var h00 := 2.0 * u * u * u - 3.0 * u * u + 1.0
			var h10 := u * u * u - 2.0 * u * u + u
			var h01 := -2.0 * u * u * u + 3.0 * u * u
			y = _smax(g, h00 * a.y + h10 * td * slope_a + h01 * g, 0.06)
		elif sd > L - tr:
			var u := (sd - (L - tr)) / tr
			var h01 := -2.0 * u * u * u + 3.0 * u * u
			var h11 := u * u * u - u * u
			y = _smax(g, (1.0 - h01) * g + h01 * b.y + h11 * tr * 1.2, 0.06)
		out.append(Vector3(q.x, y, q.y))
	out[0] = a
	out[n] = b
	# two Chaikin passes take out what is left of any kink; keep it on the floor
	for pass_i in 2:
		var sm := PackedVector3Array([out[0]])
		for i in out.size() - 1:
			sm.append(out[i].lerp(out[i + 1], 0.25))
			sm.append(out[i].lerp(out[i + 1], 0.75))
		sm.append(out[out.size() - 1])
		out = sm
	for i in range(1, out.size() - 1):
		var q := out[i]
		var w := smoothstep(free, free * 1.5 + 0.3, a2.distance_to(Vector2(q.x, q.z)))
		var pq := Vector2(q.x, q.z).lerp(_push(Vector2(q.x, q.z), avoid, radius + clear * 0.8), w)
		q = Vector3(pq.x, maxf(q.y, float(floor.call(pq.x, pq.y)) + radius * 0.8), pq.y)
		out[i] = q
	return out


static func _push(q: Vector2, avoid: Array, pad: float) -> Vector2:
	for av: Array in avoid:
		var c: Vector3 = av[0]
		var r: float = float(av[1]) + pad
		var d := q - Vector2(c.x, c.z)
		var l := d.length()
		if l < r:
			q = Vector2(c.x, c.z) + (d / l if l > 1e-4 else Vector2(1.0, 0.0)) * r
	return q


static func _smax(a: float, b: float, k: float) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return maxf(a, b) + h * h * k * 0.25
