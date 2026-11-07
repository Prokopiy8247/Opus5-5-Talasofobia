extends RefCounted
## Beat 3 - The Forest: dozens of submarines standing on their sterns on the plateau below the cliff,
## in loose rows 100-150 m apart, dissolving into the fog bands. The line sinks between them.
## Every tower is tested against the line, the cliff (Terrain.height), the statue (Statue.clearance)
## and its neighbours. Its foot stands in a silt mound (terrain material); the heroes get debris.
## Between the heroes, staggered rows of low-poly fillers (Submarine.filler_mesh, 45-250 m from the line,
## slightly tilted) give every view down through the forest several layers of towers fading into the fog.
## One sail keeps a lamp on: its window glows, its light lifts the plating round it (sub.gdshader hero_light)
## and a few motes of snow drifting through it; it only comes on once the diver is among the towers (a
## distance gate), so it never hangs in the fog as a sourceless ember seen from the cliff.

# length, radius, Submarine options
const VARIANTS := [
	[330.0, 19.0, {"sail_t": 0.68, "casing": "attack", "planes": "sail", "tail": "cross", "seed": 17}],
	[390.0, 22.0, {"sail_t": 0.72, "casing": "boomer", "planes": "sail", "tail": "cross", "seed": 18}],
	[420.0, 23.0, {"sail_t": 0.7, "casing": "boomer", "planes": "bow", "tail": "x", "seed": 19}],
	[265.0, 16.5, {"sail_t": 0.66, "casing": "attack", "planes": "bow", "tail": "cross", "seed": 20}],
	[380.0, 21.0, {"sail_t": 0.62, "casing": "attack", "planes": "sail", "tail": "cross", "seed": 21, "broken": 0.76}],
]
const ROW_WEIGHTS := [0.3, 0.22, 0.2, 0.18, 0.1]
# mid-distance fillers (Submarine.filler_mesh): length, radius, options; their infos follow VARIANTS' in `infos`.
# Tall and slim: the diver passes their upper halves (the seabed is 300-450 m below the walk here), so only
# towers that reach -340..-430 m stand in the frame
const FILL_VARIANTS := [
	[440.0, 18.5, {"sail_t": 0.72, "casing": "boomer", "planes": "sail", "seed": 31}],
	[410.0, 17.0, {"sail_t": 0.7, "casing": "attack", "planes": "sail", "seed": 32}],
	[465.0, 19.5, {"sail_t": 0.66, "casing": "attack", "planes": "bow", "seed": 33}],
	[385.0, 16.0, {"sail_t": 0.68, "casing": "attack", "planes": "sail", "seed": 34}],
]
# lines of sight the fillers keep clear: [s of the eye on the line..., target] (Choreo's M2, the lamp, M3)
const FILL_SIGHTS := [
	[[590.0, 615.0, 640.0], Vector3(245, -395, -400)],
	[[662.0, 688.0, 712.0], Vector3(-205, -480, -432)],
	[[735.0, 770.0, 805.0, 850.0, 885.0], Config.STATUE_FACE + Vector3(0, -45, 0)],
]
const FILL_TRIES := 700                   # random darts thrown into the filler area
const FILL_MAX := 34
const FILL_CLEAR := 45.0                  # fillers keep this far from the line (3D)
const FILL_FAR := 280.0                   # and stand no farther from it than this (horizontal): the last fade into fog
const FILL_Z := Vector2(-342.0, -452.0)   # rows between the cliff foot and the open water before the statue
const FILL_X := Vector2(-420.0, 430.0)
# hero towers near the line: x, z, variant, scale, sail bearing (deg; 0 = the sail points at the
# nearest stretch of the line, + = counter-clockwise from above), lean (deg), lean direction (deg)
const HEROES := [
	[-72.0, -345.0, 1, 1.06, 70.0, 0.0, 0.0],
	[84.0, -338.0, 0, 1.0, -55.0, 0.0, 0.0],
	[150.0, -385.0, 2, 1.12, -80.0, 0.0, 0.0],
	[245.0, -400.0, 1, 1.1, -95.0, 0.0, 0.0],
	[-98.0, -412.0, 4, 1.0, 40.0, 5.0, 200.0],
	[192.0, -446.0, 0, 1.08, 60.0, 0.0, 0.0],
	[-205.0, -432.0, 2, 1.15, -70.0, 0.0, 0.0],
]
# the lamp "someone left on" (Choreo holds on it at s 660-714): HEROES index; of the bridge windows seen
# from the line at s, the one nearest the line of sight to "near" (the gaze target) gets the lamp
const HERO_LAMP := {"hero": 6, "near": Vector3(-205.0, -480.0, -432.0), "s": 690.0}
const LAMP_COLOR := Color(1.0, 0.62, 0.26)
const LAMP_OUT := 2.2            # the light sits this far out from the window glass (m)
const LAMP_RANGE := 12.0         # the omni: specular glints on the plating, the masts and the planes
const LAMP_ENERGY := 6.0
const LAMP_POOL := 18.0          # reach of the warm pool it paints on the near-black plating (sub.gdshader)
const LAMP_GLOW := 0.7
const LAMP_HALO := 7.0           # halo sprite size (m): the window is ~5 px at 194 m, the halo carries it
const LAMP_GATE := Vector2(203.0, 214.0)   # camera distance (m): fully on inside x, off beyond y (cliff: 250+)
const MOTES := 500               # snow drifting through the lamp's light
const MOTE_BOX := 11.0           # half size of the cube they drift in, centred on the light (m)
# brightness keyframes [k, seconds]: a steady glow that dips, stutters and browns out (loops, ~19 s)
const FLICKER := [[1.0, 2.6], [0.86, 1.7], [1.0, 3.2], [0.35, 0.07], [0.95, 0.12], [0.55, 0.06], [1.0, 0.25],
	[0.92, 3.6], [0.97, 1.4], [0.22, 0.7], [0.14, 1.3], [0.6, 0.18], [0.3, 0.12], [0.85, 0.5], [1.0, 2.3], [0.9, 1.5]]
const PATH_CLEAR_HERO := 16.0
const PATH_CLEAR_ROW := 45.0
const STATUE_CLEAR := 10.0

var infos := []
var placed := []        # {xf, v, scl, ground, axis_a, axis_b, sail_a, sail_b, r}
var path_pts := PackedVector3Array()
var fill_rejects := {}


func build(parent: Node3D) -> void:
	var path := PathDef.main
	var rng := RandomNumberGenerator.new()
	rng.seed = 3303
	for vd: Array in VARIANTS + FILL_VARIANTS:
		infos.append(Submarine.info(vd[0], vd[1], vd[2]))
	var s := path.beat_s[1]
	while s < path.beat_s[4] + 20.0:
		path_pts.append(path.pos(s))
		s += 4.0
	# heroes first: the sail turned toward the walk (bearing offset), report every failed test
	for hi in HEROES.size():
		var h: Array = HEROES[hi]
		var v: int = h[2]
		var d: Dictionary = infos[v]
		var yaw := _face_line(path, h[0], h[1], d, float(h[3])) + deg_to_rad(h[4])
		var why := ""
		for off: float in [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0]:
			var t := _make(h[0], h[1], v, h[3], yaw + deg_to_rad(off), h[5], deg_to_rad(h[6]))
			why = _check(t, PATH_CLEAR_HERO)
			if why == "":
				t["bearing"] = float(h[4]) + off
				t["hero"] = hi
				placed.append(t)
				break
		if why != "":
			push_warning("forest: hero at (%.0f, %.0f) rejected: %s" % [h[0], h[1], why])
	var nhero := placed.size()
	var rejects := {}
	# loose rows receding into the haze: three staggered rows on the plateau, more on the basin floor
	# (the 30-60 deg slope between them is left bare: the footprint test rejects it anyway)
	var row_zs := [-345.0, -412.0, -468.0]
	var fz := -705.0
	while fz > -880.0:
		row_zs.append(fz)
		fz -= rng.randf_range(95.0, 125.0)
	for ri in row_zs.size():
		var row_z: float = row_zs[ri]
		var x := -1250.0 + rng.randf() * 60.0 + (55.0 if ri % 2 == 1 else 0.0)
		while x < 1250.0:
			var px := x + rng.randf_range(-30.0, 30.0)
			var pz := row_z + rng.randf_range(-22.0, 22.0)
			x += rng.randf_range(105.0, 145.0)
			if pz < -455.0 and px > -430.0 and px < 470.0:
				continue      # the water opens before the statue
			var wz: float = Config.WALL_Z + px * px / 5000.0
			if pz < wz + 60.0:
				continue
			if absf(px) > 900.0 and rng.randf() < 0.4:
				continue
			var v := _pick(rng)
			var scl := rng.randf_range(0.82, 1.12)
			var lean := rng.randf_range(2.0, 5.0) if rng.randf() < 0.12 else 0.0
			var ldir := rng.randf() * TAU
			var y0 := rng.randf() * TAU
			var why := ""
			for k in 6:
				var t := _make(px, pz, v, scl, y0 + float(k) * TAU / 6.0, lean, ldir)
				why = _check(t, PATH_CLEAR_ROW)
				if why == "":
					placed.append(t)
					break
			if why != "":
				var key := why.get_slice(" (", 0)
				rejects[key] = int(rejects.get(key, 0)) + 1
	# the fillers draw from their own stream: every other tower, mound and piece of debris stays where it was
	var frng := RandomNumberGenerator.new()
	frng.seed = 3304
	var nfill := _fillers(frng)
	# instances
	var mat := Submarine.material(0.0)
	var lists := []
	for v in infos.size():
		lists.append([])
	for t: Dictionary in placed:
		lists[int(t["v"])].append(t)
	for v in infos.size():
		var ts: Array = lists[v]
		if ts.is_empty():
			continue
		var vd: Array = _vdef(v)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = Submarine.mesh(vd[0], vd[1], vd[2]) if v < VARIANTS.size() else Submarine.filler_mesh(vd[0], vd[1], vd[2])
		mm.instance_count = ts.size()
		for i in ts.size():
			var t: Dictionary = ts[i]
			mm.set_instance_transform(i, t["xf"])
			var crng := rng if v < VARIANTS.size() else frng
			mm.set_instance_custom_data(i, Color(crng.randf(), float(t["ground"]) / 100.0, 0.0, 0.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = ("Submarines%d" % v) if v < VARIANTS.size() else ("SubFillers%d" % (v - VARIANTS.size()))
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
	_mounds(parent, rng)
	_debris(parent, rng, nhero)
	_hero_lamp(parent, mat, path)
	var msg := "forest: %d submarines (%d heroes, %d fillers), rejected %s, fillers rejected %s" % [placed.size(), nhero, nfill,
		str(rejects), str(fill_rejects)]
	for i in nhero:
		var t: Dictionary = placed[i]
		msg += "\n  hero v%d bearing %.0f at (%.0f, %.0f) base %.1f lift %.1f slope %.1f path %.1f statue %.1f sail top y %.0f" % [
			t["v"], t["bearing"], t["xf"].origin.x, t["xf"].origin.z, t["xf"].origin.y, t["lift"], t["slope"], t["path_cl"],
			t["statue_cl"], t["sail_b"].y]
	print(msg)


## Variant definition [length, radius, options] for an index into `infos` (VARIANTS, then FILL_VARIANTS).
func _vdef(v: int) -> Array:
	return VARIANTS[v] if v < VARIANTS.size() else FILL_VARIANTS[v - VARIANTS.size()]


## Mid-distance fillers: low-poly towers of mixed sizes thrown into the gaps between the heroes and the rows,
## 45-250 m from the line, each a few degrees off vertical; the same clearance tests as every tower (a tighter
## spacing between towers: they are thinner). Returns the count.
func _fillers(rng: RandomNumberGenerator) -> int:
	var n := 0
	for i in FILL_TRIES:
		if n >= FILL_MAX:
			break
		var px := rng.randf_range(FILL_X.x, FILL_X.y)
		var pz := rng.randf_range(FILL_Z.y, FILL_Z.x)
		var dmin := INF
		for p in path_pts:
			dmin = minf(dmin, Vector2(p.x - px, p.z - pz).length())
		if dmin > FILL_FAR:
			continue
		var v := VARIANTS.size() + rng.randi_range(0, FILL_VARIANTS.size() - 1)
		var scl := rng.randf_range(0.9, 1.06)
		var lean := rng.randf_range(1.0, 4.0)
		var ldir := rng.randf() * TAU
		var y0 := rng.randf() * TAU
		var why := ""
		for k in 4:
			var t := _make(px, pz, v, scl, y0 + float(k) * TAU / 4.0, lean, ldir)
			why = _check(t, FILL_CLEAR, true)
			if why == "":
				why = _sights(t)
			if why == "":
				t["fill"] = true
				placed.append(t)
				n += 1
				break
		if why != "":
			var key := why.get_slice(" (", 0)
			fill_rejects[key] = int(fill_rejects.get(key, 0)) + 1
	return n


## "" when a filler leaves the FILL_SIGHTS clear (its hull 10 m off each eye -> target segment, which stops
## 30 m short of the target), else the reason.
func _sights(t: Dictionary) -> String:
	var path := PathDef.main
	for sg: Array in FILL_SIGHTS:
		var tgt: Vector3 = sg[1]
		for s: float in sg[0]:
			var eye := path.pos(s)
			var e := tgt - (tgt - eye).normalized() * 30.0
			var cp := Geometry3D.get_closest_points_between_segments(t["axis_a"], t["axis_b"], eye, e)
			if cp[0].distance_to(cp[1]) < float(t["r"]) * 1.4 + 10.0:
				return "blocks a sightline (s %.0f)" % s
	return ""


func _pick(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	for v in ROW_WEIGHTS.size():
		r -= float(ROW_WEIGHTS[v])
		if r <= 0.0:
			return v
	return 0


## Yaw (radians) that points the sail (+Z local) at the closest point of the line at sail height.
func _face_line(path: PathDef, x: float, z: float, d: Dictionary, scl: float) -> float:
	var sail := Vector3(x, Terrain.height(x, z) + (float(d["sail_y"]) - float(d["ground_y"])) * scl, z)
	var best := INF
	var bp := Vector3.ZERO
	for p in path_pts:
		var dd := p.distance_squared_to(sail)
		if dd < best:
			best = dd
			bp = p
	return atan2(bp.x - x, bp.z - z)


## Local reach of the tower from its axis at axial height y (mesh units); with_sail on the sail side.
static func _reach(d: Dictionary, y: float, with_sail := true) -> float:
	var L: float = d["L"]
	var R: float = d["R"]
	var r := Submarine.radius_at(y, L, R) + float(d["hc"]) + float(d["hump"])
	if y < float(d["fin_y1"]) + 2.0:
		r = maxf(r, float(d["fin_tip"]) * 1.12)
	if with_sail and absf(y - float(d["sail_y"])) < float(d["sail_c"]) * 0.5 + 4.0:
		r = maxf(r, float(d["reach"]))
	if y > float(d["top"]):
		r = 0.0
	return r


func _make(x: float, z: float, v: int, scl: float, yaw: float, lean: float, ldir: float) -> Dictionary:
	var d: Dictionary = infos[v]
	var R: float = d["R"]
	# seabed under the footprint: sink to the lowest point of a ring as wide as the fins
	var hmin := Terrain.height(x, z)
	var hmax := hmin
	var rr := float(d["fin_tip"]) * scl * 1.05
	for k in 10:
		var a := TAU * float(k) / 10.0
		var h := Terrain.height(x + cos(a) * rr, z + sin(a) * rr)
		hmin = minf(hmin, h)
		hmax = maxf(hmax, h)
	var b := Basis(Vector3.UP, yaw)
	if lean > 0.0:
		b = Basis(Vector3(cos(ldir), 0.0, sin(ldir)), deg_to_rad(lean)) * b
	var xf := Transform3D(b.scaled(Vector3.ONE * scl), Vector3(x, hmin - float(d["ground_y"]) * scl, z))
	# raise until every fin clears the silt by 2 m
	var lift := 0.0
	var tail_angles := [0.0, PI * 0.5, PI, PI * 1.5] if (_vdef(v)[2] as Dictionary).get("tail", "cross") == "cross" \
		else [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]
	for fa: float in tail_angles:
		for f: float in [0.6, 1.0]:
			var w := xf * Vector3(cos(fa) * float(d["fin_tip"]) * f, float(d["fin_y0"]), sin(fa) * float(d["fin_tip"]) * f)
			lift = maxf(lift, Terrain.height(w.x, w.z) + 2.0 - w.y)
	xf.origin.y += lift
	var axis_a := xf * Vector3.ZERO
	var axis_b := xf * Vector3(0, float(d["top"]), 0)
	var sy: float = d["sail_y"]
	var sail_a := xf * Vector3(0, sy, 0)
	var sail_b := xf * Vector3(0, sy, float(d["reach"]))
	# seabed height along the axis (mesh units) for the shader's sediment band
	var ground := (hmin - xf.origin.y) / scl
	return {"xf": xf, "v": v, "scl": scl, "ground": ground, "lift": lift, "slope": hmax - hmin, "axis_a": axis_a,
		"axis_b": axis_b, "sail_a": sail_a, "sail_b": sail_b, "r": R * scl, "tx": float(d["sail_tx"]) * scl,
		"path_cl": 0.0, "statue_cl": 0.0}


## "" when the tower fits; otherwise the reason. tight: a filler (closer spacing to its neighbours).
func _check(t: Dictionary, path_clear: float, tight := false) -> String:
	var d: Dictionary = infos[int(t["v"])]
	var xf: Transform3D = t["xf"]
	var scl: float = t["scl"]
	var top: float = d["top"]
	if float(t["slope"]) > 16.0 * scl:
		return "ground too steep (%.0f m across the footprint)" % t["slope"]
	if float(t["lift"]) > float(d["ground_y"]) * scl + 3.0:
		return "stern would float (lift %.0f m)" % t["lift"]
	# the cliff / slopes: no part of the tower above the mound may be under the seabed
	var y := float(d["fin_y1"])
	while y < top:
		for k in 8:
			var a := TAU * float(k) / 8.0
			var rch := _reach(d, y, k == 2)
			var w := xf * Vector3(cos(a) * rch, y, sin(a) * rch)
			if Terrain.height(w.x, w.z) > w.y - 1.0:
				return "inside the terrain at y %.0f" % w.y
		y += 18.0
	# the statue (hands, arms, knees)
	var scl_min := INF
	y = 0.0
	while y < top:
		var c := xf * Vector3(0, y, 0)
		var cl := Statue.clearance(c, c, Config.STATUE_ORIGIN, 0.0) - _reach(d, y) * scl
		scl_min = minf(scl_min, cl)
		y += 10.0
	t["statue_cl"] = scl_min
	if scl_min < STATUE_CLEAR:
		return "too close to the statue (%.1f m)" % scl_min
	# the line
	var inv := xf.affine_inverse()
	var pmin := INF
	for p in path_pts:
		var q := inv * p
		var cl := 0.0
		if q.y > top:
			cl = q.distance_to(Vector3(0, top, 0)) * scl
		else:
			var rch := _reach(d, q.y, q.z > 0.0)
			cl = (Vector2(q.x, q.z).length() - rch) * scl
		pmin = minf(pmin, cl)
	t["path_cl"] = pmin
	if pmin < path_clear:
		return "too close to the line (%.1f m)" % pmin
	# neighbours: hulls, sails against hulls, sails against sails
	for o: Dictionary in placed:
		var hh := Geometry3D.get_closest_points_between_segments(t["axis_a"], t["axis_b"], o["axis_a"], o["axis_b"])
		if hh[0].distance_to(hh[1]) < (float(t["r"]) + float(o["r"])) * (1.05 if tight else 1.3) + (3.0 if tight else 8.0):
			return "hull overlaps a neighbour"
		var s1 := Geometry3D.get_closest_points_between_segments(t["sail_a"], t["sail_b"], o["axis_a"], o["axis_b"])
		var s2 := Geometry3D.get_closest_points_between_segments(o["sail_a"], o["sail_b"], t["axis_a"], t["axis_b"])
		if s1[0].distance_to(s1[1]) < float(o["r"]) * 1.25 + float(t["tx"]) + 6.0:
			return "sail hits a neighbour"
		if s2[0].distance_to(s2[1]) < float(t["r"]) * 1.25 + float(o["tx"]) + 6.0:
			return "a neighbour's sail hits the hull"
		var ss := Geometry3D.get_closest_points_between_segments(t["sail_a"], t["sail_b"], o["sail_a"], o["sail_b"])
		if ss[0].distance_to(ss[1]) < (float(t["r"]) + float(o["r"])) * 0.6 + 4.0:
			return "sails cross"
	return ""


## Silt mounds around every foot (terrain material, so they melt into the seabed), darker at the hull.
func _mounds(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var mb := MeshBuilder.new()
	var nseg := 16
	for t: Dictionary in placed:
		var d: Dictionary = infos[int(t["v"])]
		var xf: Transform3D = t["xf"]
		var scl: float = t["scl"]
		var R := float(d["R"]) * scl
		var c := xf * Vector3(0, float(t["ground"]), 0)
		var hm := R * 0.24
		var r0 := Submarine.radius_at(float(t["ground"]) + hm / scl, d["L"], d["R"]) * scl * 0.85
		var radii := [r0, R * 0.65, R * 1.05, R * 1.55, R * 2.2]
		var lift := [hm, hm * 0.8, hm * 0.5, hm * 0.18, -1.5]
		var aos := [0.45, 0.7, 0.85, 0.95, 1.0]
		# (fillers take their phase from their position: the rng stream of the debris after this stays put)
		var ph := (rng.randf() if not t.get("fill", false) else fposmod(xf.origin.x * 0.137 + xf.origin.z * 0.071, 1.0)) * TAU
		var base := mb.v.size()
		for i in radii.size():
			for j in nseg + 1:
				var a := TAU * float(j % nseg) / float(nseg)
				var wob := 1.0 + 0.18 * sin(a * 3.0 + ph) + 0.1 * sin(a * 5.0 + ph * 2.0)
				var rad: float = float(radii[i]) * (1.0 if i == 0 else wob)
				var px := c.x + cos(a) * rad
				var pz := c.z + sin(a) * rad
				var hgt: float = float(lift[i]) * (1.0 if i == radii.size() - 1 else (0.75 + 0.25 * wob))
				var py := Terrain.height(px, pz) + hgt
				if i == 0:
					py = maxf(py, c.y + hm * 0.6)
				mb.vert(Vector3(px, py, pz), Vector3.UP, Vector2(px, pz), Color(aos[i], 0.0, 0.0, 1.0))
		for i in radii.size() - 1:
			for j in nseg:
				var a0 := base + i * (nseg + 1) + j
				var b0 := base + (i + 1) * (nseg + 1) + j
				mb.quad(a0, b0, b0 + 1, a0 + 1)
		# smooth normals from the ring neighbours
		for i in radii.size():
			for j in nseg + 1:
				var k := base + i * (nseg + 1) + j
				var ip := base + mini(i + 1, radii.size() - 1) * (nseg + 1) + j
				var im := base + maxi(i - 1, 0) * (nseg + 1) + j
				var jn := base + i * (nseg + 1) + (j + 1) % (nseg + 1)
				var jm := base + i * (nseg + 1) + (j + nseg) % (nseg + 1)
				var nn := (mb.v[ip] - mb.v[im]).cross(mb.v[jn] - mb.v[jm]).normalized()
				if nn.y < 0.0:
					nn = -nn
				mb.n[k] = nn
	# triangles were oriented against the provisional up normals; keep them (mounds face up)
	var mi := mb.instance(Mats.make("terrain"), parent)
	mi.name = "SubMounds"


## Debris at the heroes' feet: torn plates, a fallen hatch lid, a giant propeller, chain stubs.
func _debris(parent: Node3D, rng: RandomNumberGenerator, nhero: int) -> void:
	var mb := MeshBuilder.new()
	for i in nhero:
		var t: Dictionary = placed[i]
		var d: Dictionary = infos[int(t["v"])]
		var R := float(d["R"]) * float(t["scl"])
		var c: Vector3 = t["axis_a"]
		for k in 7:
			var a := rng.randf() * TAU
			var r := R * rng.randf_range(1.4, 3.2)
			var p := Vector3(c.x + cos(a) * r, 0.0, c.z + sin(a) * r)
			p.y = Terrain.height(p.x, p.z) - 0.3
			var sz := Vector3(rng.randf_range(3.0, 9.0), 0.35, rng.randf_range(2.0, 6.0))
			var bs := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.6, 0.6))
			mb.color = Color(0.75, 0.0, 0.8, 0.6)
			mb.box(p, sz, bs)
		if i == 4 or i == 1:
			# a propeller lying on its face, half in the silt
			var a := rng.randf() * TAU
			var p := Vector3(c.x + cos(a) * R * 2.6, 0.0, c.z + sin(a) * R * 2.6)
			p.y = Terrain.height(p.x, p.z) + 0.4
			var bs := Basis(Vector3(0, 0, 1), PI * 0.5 - 0.25) * Basis(Vector3(1, 0, 0), rng.randf() * TAU)
			Debris.propeller(mb, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * bs, p), R * 0.95, 7, 0.6)
	var mi := mb.instance(Mats.solid(Palette.STEEL_DARK.lerp(Palette.RUST, 0.3), 0.7, 0.4), parent, 900.0)
	mi.name = "SubDebris"


## The amber lamp left on in one hero's sail: the window glows warm (sub.gdshader hero_lamp), its light lifts
## the near-black plating round it into a warm pool (hero_light), an omni adds glints on the steel, motes of
## snow drift lit through it, a soft halo hangs in the water in front of it; all flicker and brown out together.
## A distance gate keeps it all off until the diver is among the towers (LAMP_GATE).
func _hero_lamp(parent: Node3D, mat: ShaderMaterial, path: PathDef) -> void:
	var t := {}
	for o: Dictionary in placed:
		if int(o.get("hero", -1)) == int(HERO_LAMP["hero"]):
			t = o
	if t.is_empty():
		push_warning("forest: the lamp hero was not placed")
		return
	var vd: Array = _vdef(int(t["v"]))
	var xf: Transform3D = t["xf"]
	var eye := path.pos(float(HERO_LAMP["s"]))
	var best := INF
	var wp := Vector3.ZERO
	var wn := Vector3.ZERO
	for w: Array in Submarine.sail_windows(vd[0], vd[1], vd[2]):
		var p := xf * (w[0] as Vector3)
		var nrm := (xf.basis * (w[1] as Vector3)).normalized()
		if nrm.dot(eye - p) <= 0.0:
			continue
		var dd := (p - eye).angle_to((HERO_LAMP["near"] as Vector3) - eye)
		if dd < best:
			best = dd
			wp = p
			wn = nrm
	if best == INF:
		push_warning("forest: no window of the lamp hero faces the line")
		return
	var lp := wp + wn * LAMP_OUT
	mat.set_shader_parameter("hero_lamp", Vector4(wp.x, wp.y, wp.z, 0.0))
	mat.set_shader_parameter("hero_light", Vector4(lp.x, lp.y, lp.z, LAMP_POOL))
	var light := OmniLight3D.new()
	light.name = "SailLamp"
	light.light_color = LAMP_COLOR
	light.omni_range = LAMP_RANGE
	light.light_energy = 0.0
	light.light_specular = 0.6
	light.shadow_enabled = false
	light.position = lp
	parent.add_child(light)
	var halo := Mats.glow_sprite(parent, wp + wn * 2.5, LAMP_HALO, LAMP_COLOR, 0.0)
	halo.name = "SailLampHalo"
	var hmat := halo.material_override as ShaderMaterial
	var motes := _motes(parent, lp, wn)
	var mmat := motes.material_override as ShaderMaterial
	var set_k := func(k: float) -> void:
		var g := 0.0
		var cam := light.get_viewport().get_camera_3d() if light.is_inside_tree() else null
		if cam:
			g = 1.0 - smoothstep(LAMP_GATE.x, LAMP_GATE.y, cam.global_position.distance_to(wp))
		var kk := k * g
		light.light_energy = LAMP_ENERGY * kk
		light.visible = kk > 0.002
		hmat.set_shader_parameter("energy", LAMP_GLOW * kk)
		mmat.set_shader_parameter("k", kk)
		mat.set_shader_parameter("hero_lamp", Vector4(wp.x, wp.y, wp.z, kk))
	var tw := light.create_tween().set_loops()
	var k0: float = FLICKER[FLICKER.size() - 1][0]
	for f: Array in FLICKER:
		tw.tween_method(set_k, k0, float(f[0]), float(f[1])).set_trans(Tween.TRANS_SINE)
		k0 = f[0]
	print("forest: sail lamp at %s (facing %s), %.0f m from the line at s %.0f, %.1f deg off the gaze" % [wp, wn,
		wp.distance_to(eye), HERO_LAMP["s"], rad_to_deg(best)])


const MOTE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// Snow drifting through the sail lamp's light (Beat03_Forest.gd): flakes wrap inside a cube centred on the light,
// lit by its falloff on the window side only, dimmed by the water between them and the eye.
#include "res://shaders/inc/uw.gdshaderinc"
uniform float k = 0.0;                        // lamp brightness (flicker x distance gate)
uniform vec3 lamp_dir = vec3(1.0, 0.0, 0.0);   // the window's outward normal
uniform vec3 warm = vec3(1.0, 0.5, 0.17);
uniform float half_box = 13.0;
uniform float size = 0.6;
uniform float gain = 8.0;
varying float glow;
void vertex() {
	float rnd = UV2.x;
	vec3 drift = vec3(sin(uw_time * 0.09 + rnd * 40.0) * 0.7, -uw_time * (0.05 + rnd * 0.06),
		cos(uw_time * 0.07 + rnd * 23.0) * 0.7);
	vec3 rel = mod(VERTEX + drift + half_box, vec3(2.0 * half_box)) - half_box;
	vec3 wp = (MODEL_MATRIX * vec4(rel, 1.0)).xyz;
	vec4 vp = VIEW_MATRIX * vec4(wp, 1.0);
	vp.xy += (UV - 0.5) * size * (0.6 + 0.8 * rnd);
	POSITION = PROJECTION_MATRIX * vp;
	float d = length(rel);
	float fall = 1.0 - smoothstep(0.0, half_box, d);
	fall = fall * fall / (1.0 + d * d * 0.03);
	float front = smoothstep(-0.3, 0.4, dot(rel / max(d, 1e-3), lamp_dir));
	vec4 fg = uw_fog_eval(uw_cam_pos, wp);
	glow = k * fall * front * (1.0 - fg.a) * (0.5 + rnd);
}
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	ALBEDO = warm * glow * gain * (1.0 - smoothstep(0.15, 1.0, r));
}
"""


## The motes: MOTES quads (each four corners at one seed position, UV the corner, UV2.x a random value) that the
## shader billboards, drifts and wraps around the light at `at`.
func _motes(parent: Node3D, at: Vector3, out: Vector3) -> MeshInstance3D:
	var sh := Shader.new()
	sh.code = MOTE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("lamp_dir", out)
	mat.set_shader_parameter("half_box", MOTE_BOX)
	Mats.all_materials.append(mat)
	var rng := RandomNumberGenerator.new()
	rng.seed = 707
	var vs := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in MOTES:
		var p := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * MOTE_BOX
		var r := rng.randf()
		var b := vs.size()
		for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			vs.append(p)
			uvs.append(c)
			uv2s.append(Vector2(r, 0.0))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = AABB(Vector3.ONE * -MOTE_BOX * 1.2, Vector3.ONE * MOTE_BOX * 2.4)
	var mi := MeshInstance3D.new()
	mi.name = "SailLampMotes"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	parent.add_child(mi)
	return mi
