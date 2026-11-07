class_name Terrain
extends RefCounted
## Seabed heightfield: sand shallows, a steep slope of wrecks cut by fall-line chutes and rock ribs, a
## meandering cliff lip down to the submarine plateau, a slope down to the statue basin and the floor at the
## foot of the wall. height(x, z) is public so builders can rest objects on the ground.
## Beat-2 wrecks lie in sediment beds carved into height(): the bed geometry and the wreck poses both come from
## ship_pose() (Config.SHIP_* + Hull.KINDS proportions), so the terrain and the hulls always agree. Where a
## SHIP_* entry has "fill" (fraction of the depth), silt fills in under the rising stern (Hull._bottom: the run
## or the counter) up to that height above the keel and drifts out behind it, so the rudder and the propeller
## sit in the sediment instead of over a gap.
## mesh_height(x, z) is the height of the rendered mesh (its triangles), for props that must touch the drawn
## ground exactly (valid after build()).
## Within ~22 m of the walk (|x - path x| at the same z) the meander, ribs and beds are faded out, so the path
## keeps its clearance (tools_gd/placement_gate.gd checks it).

# depth profile along z (monotone cubic interpolation)
const PROFILE := [
	Vector2(160, -3.0), Vector2(60, -6.0), Vector2(30, -8.0), Vector2(0, -13.0), Vector2(-45, -22.5),
	Vector2(-85, -38.0), Vector2(-130, -76.0), Vector2(-175, -118.0), Vector2(-215, -168.0),
	Vector2(-250, -219.0), Vector2(-274, -262.0), Vector2(-283, -284.0), Vector2(-287, -330.0),
	Vector2(-292, -560.0), Vector2(-298, -745.0), Vector2(-310, -790.0), Vector2(-485, -792.0),
	Vector2(-520, -812.0), Vector2(-580, -880.0), Vector2(-640, -952.0), Vector2(-690, -985.0),
	Vector2(-1100, -985.0),
]
# mesh sampling: [from, to, spacing] bands (ascending). Beyond the x bands the spacing grows with distance.
# (finer around the trawler's stern drift, which the camera studies from 10-20 m)
const X_BANDS := [[-700.0, -130.0, 5.0], [-130.0, -60.0, 3.0], [-60.0, 14.0, 2.5], [14.0, 62.0, 1.6],
	[62.0, 340.0, 3.0]]
const Z_BANDS := [[-975.0, -880.0, 1.5], [-880.0, -560.0, 3.2], [-560.0, -330.0, 4.5], [-330.0, -314.0, 1.6],
	[-314.0, -246.0, 0.7], [-246.0, -128.0, 2.0], [-128.0, -100.0, 1.4], [-100.0, 60.0, 2.0], [60.0, 170.0, 3.0]]
const FILL_N := 48                      # stern profile samples (Hull._bottom over the aft 30 % of the length)
const FILL_EMBED := 0.15                # the stern silt reaches this far up into the hull (no sliver of water)
const X_EXTENT := 1600.0
const TILE := 48                        # quads per tile side (one MeshInstance3D per tile, for culling)
const SHIP_KEYS := ["liner", "tanker", "cargo", "trawler", "small"]   # beds carved biggest first
const PT_Z0 := 200.0                    # profile lookup table: z from PT_Z0 down, PT_STEP apart
const PT_STEP := 0.25
const PX_Z0 := 60.0                     # path-x lookup table: z from PX_Z0 down, 1 m apart

static var _noise: FastNoiseLite        # broad relief (unchanged since v1: the deep floor depends on it)
static var _noise2: FastNoiseLite       # sand dunes
static var _nw: FastNoiseLite           # contour / lip meander
static var _nr: FastNoiseLite           # rock ribs and chutes (single octave, sampled anisotropically)
static var _slopes := PackedFloat32Array()
static var _ptab := PackedFloat32Array()
static var _pxtab := PackedFloat32Array()
static var _pytab := PackedFloat32Array()
static var _liner_x := Vector2(-650.0, -40.0)
static var _tanker_x := Vector2(45.0, 345.0)
static var _beds: Array = []
static var _bed_state := 0             # 0 not built, 1 building, 2 ready
static var _poses := {}
static var material: ShaderMaterial     # the seabed material (set by build(); Beat01 sets the boat's soft shadow)
static var _mxs := PackedFloat32Array() # the mesh grid (build()): columns, rows (+z to -z), heights
static var _mzs := PackedFloat32Array()
static var _mh := PackedFloat32Array()


static func _setup() -> void:
	if _noise:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = 7
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.004
	_noise.fractal_octaves = 4
	_noise2 = FastNoiseLite.new()
	_noise2.seed = 11
	_noise2.frequency = 0.05
	_noise2.fractal_octaves = 2
	_nw = FastNoiseLite.new()
	_nw.seed = 23
	_nw.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_nw.frequency = 0.0065
	_nw.fractal_octaves = 2
	_nr = FastNoiseLite.new()
	_nr.seed = 31
	_nr.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_nr.frequency = 1.0
	_nr.fractal_type = FastNoiseLite.FRACTAL_NONE
	# Fritsch-Carlson slopes (profile is ordered by decreasing z)
	var nn := PROFILE.size()
	var d := PackedFloat32Array()
	for i in nn - 1:
		d.append((PROFILE[i + 1].y - PROFILE[i].y) / (PROFILE[i + 1].x - PROFILE[i].x))
	_slopes.resize(nn)
	_slopes[0] = d[0]
	_slopes[nn - 1] = d[nn - 2]
	for i in range(1, nn - 1):
		if d[i - 1] * d[i] <= 0.0:
			_slopes[i] = 0.0
		else:
			_slopes[i] = 2.0 / (1.0 / d[i - 1] + 1.0 / d[i])
	var n := int((PT_Z0 + 1100.0) / PT_STEP) + 2
	_ptab.resize(n)
	for i in n:
		_ptab[i] = profile(PT_Z0 - float(i) * PT_STEP)
	# path x by z (the path's z decreases monotonically along s)
	var path := PathDef.main if PathDef.main else PathDef.new()
	var zs := PackedFloat32Array()
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var s := 0.0
	while s <= path.length:
		var p := path.pos(s)
		zs.append(p.z)
		xs.append(p.x)
		ys.append(p.y)
		s += 1.0
	var m := int(PX_Z0 + 1000.0)
	_pxtab.resize(m)
	_pytab.resize(m)
	var k := 0
	for i in m:
		var z := PX_Z0 - float(i)
		while k < zs.size() - 2 and zs[k + 1] > z:
			k += 1
		var t := clampf((z - zs[k]) / minf(zs[k + 1] - zs[k], -1e-4), 0.0, 1.0)
		_pxtab[i] = lerpf(xs[k], xs[k + 1], t)
		_pytab[i] = lerpf(ys[k], ys[k + 1], t)
	# x ranges of the liner and the tanker: no bays in the lip below them (a ledge under the liner)
	_liner_x = _x_range(Config.SHIP_LINER)
	_tanker_x = _x_range(Config.SHIP_TANKER)


static func _x_range(c: Dictionary) -> Vector2:
	var lp: Vector3 = c["pos"]
	var lf := Basis(Vector3.UP, deg_to_rad(float(c["yaw"]))) * Vector3.FORWARD
	var half := float(c["length"]) * 0.5
	return Vector2(minf(lp.x - lf.x * half, lp.x + lf.x * half), maxf(lp.x - lf.x * half, lp.x + lf.x * half))


## The cubic depth profile at z (exact; height() uses a lookup table of it).
static func profile(z: float) -> float:
	if z >= PROFILE[0].x:
		return PROFILE[0].y
	for i in PROFILE.size() - 1:
		var a: Vector2 = PROFILE[i]
		var b: Vector2 = PROFILE[i + 1]
		if z <= a.x and z >= b.x:
			var h := b.x - a.x
			var t := (z - a.x) / h
			var t2 := t * t
			var t3 := t2 * t
			return (2 * t3 - 3 * t2 + 1) * a.y + (t3 - 2 * t2 + t) * h * _slopes[i] \
				+ (-2 * t3 + 3 * t2) * b.y + (t3 - t2) * h * _slopes[i + 1]
	return PROFILE[PROFILE.size() - 1].y


static func _prof(z: float) -> float:
	var f := clampf((PT_Z0 - z) / PT_STEP, 0.0, float(_ptab.size() - 2))
	var i := int(f)
	return lerpf(_ptab[i], _ptab[i + 1], f - float(i))


## x of the walk where it crosses depth-row z.
static func path_x(z: float) -> float:
	_setup()
	var f := clampf(PX_Z0 - z, 0.0, float(_pxtab.size() - 2))
	var i := int(f)
	return lerpf(_pxtab[i], _pxtab[i + 1], f - float(i))


## y of the walk where it crosses depth-row z.
static func path_y(z: float) -> float:
	_setup()
	var f := clampf(PX_Z0 - z, 0.0, float(_pytab.size() - 2))
	var i := int(f)
	return lerpf(_pytab[i], _pytab[i + 1], f - float(i))


## 0 within ~22 m of the walk, 1 beyond ~60 m: regional features (meander, ribs, beds) fade in with it.
static func keep(x: float, z: float) -> float:
	return smoothstep(22.0, 60.0, absf(x - path_x(z)))


## Lip offset in z (negative = a bay cut back into the slope, positive = a spur): broad bays and spurs beyond
## the big wrecks, a gentle ledge under the liner, no bay under the tanker, a short irregular meander everywhere.
static func _lip(x: float) -> float:
	var o := _nw.get_noise_2d(x, 300.0) * 34.0 - 9.0
	o = clampf(o, -26.0, 6.0)
	var out := maxf(_liner_x.x - 40.0 - x, x - _liner_x.y - 25.0)
	o = lerpf(5.0, o, smoothstep(0.0, 80.0, out))
	var out_t := maxf(_tanker_x.x - 30.0 - x, x - _tanker_x.y - 30.0)
	o = lerpf(maxf(o, -3.0), o, smoothstep(0.0, 60.0, out_t))
	return o + _nw.get_noise_2d(x * 4.0, 900.0) * 7.0


static func _warp(x: float, z: float) -> float:
	var ws := _nw.get_noise_2d(x, 0.0) * 20.0 * smoothstep(-70.0, -112.0, z)
	var lb := smoothstep(-226.0, -258.0, z) * (1.0 - smoothstep(-300.0, -372.0, z))
	return lerpf(ws, _lip(x), lb)


## Rock ribs and fall-line chutes: ridged noise stretched along the fall line (-z), metres.
static func _ribs(x: float, z: float) -> Vector2:
	var n := _nr.get_noise_2d(x * 0.032, z * 0.011)
	var r := 1.0 - minf(sqrt(n * n + 0.004) * 2.2, 1.0)          # soft |n|: rounded crests
	var n2 := _nr.get_noise_2d(x * 0.12 + 40.0, z * 0.032 - 17.0)
	var r2 := 1.0 - minf(sqrt(n2 * n2 + 0.004) * 2.2, 1.0)
	var r3 := r * r * r
	return Vector2(r3 * 5.0 + r2 * r2 * r2 * 1.8 - 1.6, r3)


## Natural ground (no wreck beds): Vector3(height, rib factor 0..1, keep factor).
static func natural_ex(x: float, z: float) -> Vector3:
	_setup()
	var kp := keep(x, z)
	var zw := z
	if kp > 0.0 and z < -60.0 and z > -380.0:
		zw = z + _warp(x, z) * kp
	var base := _prof(zw)
	# regional relief amplitude, every change blended over 20-70 m (follows the warped contours)
	var amp := lerpf(lerpf(1.2, 3.0, clampf(absf(x) / 120.0, 0.0, 1.0)), 7.0, smoothstep(-78.0, -104.0, zw))
	amp = lerpf(amp, 18.0, smoothstep(-270.0, -287.0, zw))
	amp = lerpf(amp, 12.0, smoothstep(-296.0, -318.0, zw))
	# keep the ground calm at the foot of the wall, at the door and under the statue's knees
	var near_wall := smoothstep(-885.0, -930.0, z)
	var dd := Vector2(x - Config.DOOR_POS.x, z - Config.DOOR_POS.z).length()
	var near_door := 1.0 - smoothstep(30.0, 110.0, dd)
	amp *= (1.0 - 0.85 * near_wall) * (1.0 - near_door)
	var h := base + _noise.get_noise_2d(x, z) * amp
	if z > -110.0:
		h += _noise2.get_noise_2d(x * 0.6, z) * 0.6 * (1.0 - smoothstep(-80.0, -105.0, z))
	var rib := 0.0
	if kp > 0.0 and z < -86.0 and z > -300.0:
		var band := smoothstep(-88.0, -126.0, zw) * (1.0 - smoothstep(-262.0, -284.0, zw))
		if band > 0.0:
			var rr := _ribs(x, z)
			h += rr.x * band * kp
			rib = rr.y * band * kp
	# rising flanks far to the sides make the slope read as a valley
	h += maxf(absf(x) - 500.0, 0.0) * 0.12
	# a gentle silt drift banked against the foot of the wall (none near the door)
	var wd := z - (Config.WALL_Z + x * x / 5000.0)
	if wd < 45.0:
		h += 2.4 * exp(-maxf(wd, 0.0) / 9.0) * smoothstep(38.0, 75.0, dd)
	return Vector3(h, rib, kp)


static func natural(x: float, z: float) -> float:
	return natural_ex(x, z).x


## Ground height at (x, z), wreck beds included.
static func height(x: float, z: float) -> float:
	var h := natural_ex(x, z).x
	if _bed_state == 0:
		_setup_beds()
	if _bed_state == 2:
		h = _bed(x, z, h).x
	return h


## Height of the drawn ground mesh at (x, z): its triangles, which cut a little under or over the smooth
## height() between the samples (up to ~0.2 m on the ribs). Falls back to height() before build().
static func mesh_height(x: float, z: float) -> float:
	var nx := _mxs.size()
	var nz := _mzs.size()
	if nx < 2 or nz < 2:
		return height(x, z)
	var j := clampi(_mxs.bsearch(x) - 1, 0, nx - 2)
	# rows run from +z to -z: bisect by hand
	var lo := 0
	var hi := nz - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _mzs[mid] >= z:
			lo = mid
		else:
			hi = mid
	var i := lo
	var u := clampf((x - _mxs[j]) / (_mxs[j + 1] - _mxs[j]), 0.0, 1.0)
	var v := clampf((z - _mzs[i]) / (_mzs[i + 1] - _mzs[i]), 0.0, 1.0)
	var ha := _mh[i * nx + j]
	var hb := _mh[i * nx + j + 1]
	var hd := _mh[(i + 1) * nx + j]
	var he := _mh[(i + 1) * nx + j + 1]
	# the quad's triangles are (a, d, e) and (a, e, b) (see _tile): split along the a-e diagonal
	if v >= u:
		return ha + (hd - ha) * v + (he - hd) * u
	return ha + (hb - ha) * u + (he - hb) * v


## Ground normal from central differences (e metres apart).
static func normal(x: float, z: float, e := 1.0) -> Vector3:
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


# ------------------------------------------------------------------------------------------- wreck beds

static func ship_config(key: String) -> Dictionary:
	match key:
		"trawler":
			return Config.SHIP_TRAWLER
		"cargo":
			return Config.SHIP_CARGO
		"tanker":
			return Config.SHIP_TANKER
		"liner":
			return Config.SHIP_LINER
	return Config.SHIP_SMALL


## Resting pose of a Beat-2 wreck: {"transform" (node frame of Hull.ship: bow -Z, keel bottom at the origin),
## "length", "beam", "depth", "heel", "pitch", "slope" (cross-slope, rad), "bed_y" (sediment level at the centre)}.
static func ship_pose(key: String) -> Dictionary:
	_setup()
	if _bed_state == 0:
		_setup_beds()
	return _poses.get(key, {})


static func _setup_beds() -> void:
	if _bed_state != 0:
		return
	_bed_state = 1
	_setup()
	for key: String in SHIP_KEYS:
		var bd := _make_bed(key, ship_config(key))
		_beds.append(bd)
		_poses[key] = bd["pose"]
	_bed_state = 2


static func _make_bed(key: String, cfg: Dictionary) -> Dictionary:
	var k: Dictionary = Hull.KINDS[key]
	var L: float = cfg["length"]
	var B := L * float(k["b"])
	var D := L * float(k["d"])
	var pos: Vector3 = cfg["pos"]
	var yb := Basis(Vector3.UP, deg_to_rad(float(cfg["yaw"])))
	var fwd := yb * Vector3.FORWARD
	var rgt := yb * Vector3.RIGHT
	# least-squares plane of the natural ground under the footprint: h = a + b u + c v
	var sa := 0.0
	var sbu := 0.0
	var suu := 0.0
	var scv := 0.0
	var svv := 0.0
	var cnt := 0.0
	for i in 9:
		for j in 7:
			var u := (float(i) / 8.0 - 0.5) * L * 0.9
			var v := (float(j) / 6.0 - 0.5) * B
			var qx := pos.x + fwd.x * u + rgt.x * v
			var qz := pos.z + fwd.z * u + rgt.z * v
			var h := _bed(qx, qz, natural(qx, qz)).x      # earlier wrecks' beds included
			sa += h
			sbu += u * h
			suu += u * u
			scv += v * h
			svv += v * v
			cnt += 1.0
	var a := sa / cnt
	var pitch := atan(sbu / suu)
	var slope := atan(scv / svv)                       # > 0: ground rises toward starboard
	var heel := slope * float(cfg.get("follow", 0.7)) + deg_to_rad(float(cfg.get("heel", 0.0)))
	var bs := yb * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, heel)
	var up := bs.y
	# the bed plane follows the hull bottom; it crosses the natural ground a little downslope of the keel
	# line, so more of the bed is cut into the slope (a scarp above) than piled up below it (a talus berm)
	var rest := absf(tan(slope) - tan(heel)) * B * 0.5 * cos(heel)
	var yc := a - float(cfg.get("cut", 0.3)) * rest
	var sink := float(cfg.get("sink", 0.14)) * D
	var origin := Vector3(pos.x, yc - sink / up.y, pos.z)
	var p0 := origin + up * sink
	var hw := B * 0.5 * cos(heel) + 0.4
	var hl := L * 0.5 * cos(pitch)
	var wfill := clampf(B * 0.6, 8.0, 32.0)
	var reach := wfill * 2.5 + 2.0
	var c := Vector2(pos.x, pos.z)
	var ext := Vector2(absf(fwd.x) * hl + absf(rgt.x) * hw, absf(fwd.z) * hl + absf(rgt.z) * hw) + Vector2.ONE * reach
	var pose := {"transform": Transform3D(bs, origin), "length": L, "beam": B, "depth": D, "heel": heel,
		"pitch": pitch, "slope": slope, "bed_y": yc}
	# the stern: its run (or counter) rises off the flat bed, which left the rudder and the propeller over a
	# gap of sand. Height of the hull's centre-line bottom above the keel over the aft 30 %, behind the aft end
	# the value there (the drift tails off behind it).
	var scap := float(cfg.get("fill", 0.0)) * D
	var stab := PackedFloat32Array()
	var sx0 := -L * 0.5 - 2.0
	var sx1 := -L * 0.5 + L * 0.3
	var s_aft := sx0
	if scap > sink:
		var ho := {"stern": k["stern"], "sheer": D * float(k["sheer"]), "dead": k["dead"]}
		if L >= 20.0 and k["stern"] == "transom":     # as Hull.ship() with fittings: the deeper run
			ho["run"] = 0.55
			ho["run_exp"] = 1.3
		var first := -1
		for i in FILL_N + 1:
			var sx := lerpf(sx0, sx1, float(i) / float(FILL_N))
			var bt := Hull._bottom(L, B, D, k, ho, sx)
			stab.append(bt)
			if first < 0 and bt < 1e8:
				first = i
		if first < 0:
			scap = 0.0
		else:
			s_aft = lerpf(sx0, sx1, float(first) / float(FILL_N))
			for i in first:
				stab[i] = stab[first]
	return {"c": c, "ax": Vector2(fwd.x, fwd.z), "cr": Vector2(rgt.x, rgt.z), "hl": hl, "hw": hw,
		"rb": minf(hw * 0.95, hl), "rs": hw * 0.45, "n": up, "p0": p0, "wfill": wfill,
		"ks": maxf(1.9, absf(tan(slope)) + 0.7), "fcap": maxf(D * 0.25, 1.0),
		"berm": clampf(D * 0.13, 0.4, 6.0), "bw": maxf(B * 0.16, 1.5), "rect": Rect2(c - ext, ext * 2.0),
		"B": B, "pose": pose, "scap": scap, "sink": sink, "stab": stab, "sx0": sx0, "sx1": sx1, "s_aft": s_aft,
		"cp": cos(pitch), "tail": clampf(B * 0.4, 2.0, 9.0)}


## Signed distance (plan, metres) to a hull footprint (rounded box, rounder at the bow, u > 0) and the unit
## direction (local u, v) from the nearest boundary point: Vector3(d, gu, gv).
static func _sd_hull(u: float, v: float, hl: float, hw: float, rb: float, rs: float) -> Vector3:
	var r := rb if u > 0.0 else rs
	var su := 1.0 if u >= 0.0 else -1.0
	var sv := 1.0 if v >= 0.0 else -1.0
	var qx := absf(u) - hl + r
	var qy := absf(v) - hw + r
	if qx > 0.0 and qy > 0.0:
		var l := sqrt(qx * qx + qy * qy)
		return Vector3(l - r, su * qx / l, sv * qy / l)
	if qx > qy:
		return Vector3(qx - r, su, 0.0)
	return Vector3(qy - r, 0.0, sv)


static func _smin(a: float, b: float, k: float) -> float:
	var hh := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - hh * hh * k * 0.25


static func _smax(a: float, b: float, k: float) -> float:
	var hh := maxf(k - absf(a - b), 0.0) / k
	return maxf(a, b) + hh * hh * k * 0.25


## Applies the wreck beds to natural height h: Vector3(height, bed mask, contact darkening 0..1).
## Inside the footprint the ground is the bed plane (the hull bottom, sunk); outside, from the bed level at the
## nearest edge, a scarp (62 deg) is cut up into the slope where the ground is higher, and a talus berm
## (33 deg, ending within wfill) is piled where it is lower. Sediment banks against the flanks.
static func _bed(x: float, z: float, h: float) -> Vector3:
	var mask := 0.0
	var contact := 0.0
	for bd: Dictionary in _beds:
		var rect: Rect2 = bd["rect"]
		if not rect.has_point(Vector2(x, z)):
			continue
		var c: Vector2 = bd["c"]
		var ax: Vector2 = bd["ax"]
		var cr: Vector2 = bd["cr"]
		var dx := x - c.x
		var dz := z - c.y
		var bu := dx * ax.x + dz * ax.y
		var bv := dx * cr.x + dz * cr.y
		var sd := _sd_hull(bu, bv, bd["hl"], bd["hw"], bd["rb"], bd["rs"])
		var d := sd.x
		var wf: float = bd["wfill"]
		if d > wf * 2.5:
			continue
		var n: Vector3 = bd["n"]
		var p0: Vector3 = bd["p0"]
		var hb := h
		var w := 1.0
		if d <= 0.0:
			hb = p0.y - (n.x * (x - p0.x) + n.z * (z - p0.z)) / n.y
		else:
			var ex := x - (ax.x * sd.y + cr.x * sd.z) * d
			var ez := z - (ax.y * sd.y + cr.y * sd.z) * d
			var pe := p0.y - (n.x * (ex - p0.x) + n.z * (ez - p0.z)) / n.y
			var talus := pe - d * 0.65
			var scarp := pe + d * float(bd["ks"])
			if h < talus:
				# the berm: no thicker than fcap (on a slope steeper than repose the rest has slid away)
				var fc: float = bd["fcap"]
				var fx := minf(talus - h, fc + maxf(pe - h - fc, 0.0) * (1.0 - smoothstep(0.0, 6.0, d)))
				hb = h + fx * (1.0 - smoothstep(wf * 0.45, wf, d))
			else:
				hb = _smin(h, scarp, 3.0)
			hb = lerpf(hb, h, smoothstep(wf * 2.0, wf * 2.5, d))
			w = 1.0 - smoothstep(0.0, wf * 0.8, d)
		# silt under the rising stern and a drift behind it: the bed plane + the fill (along the hull's up)
		var scap: float = bd["scap"]
		if scap > 0.0:
			var sx := bu / float(bd["cp"])
			var sx1: float = bd["sx1"]
			if sx < sx1:
				var sx0: float = bd["sx0"]
				var stab: PackedFloat32Array = bd["stab"]
				var fi := clampf((sx - sx0) / (sx1 - sx0) * float(FILL_N), 0.0, float(FILL_N) - 1e-3)
				var i0 := int(fi)
				var bt := lerpf(stab[i0], stab[i0 + 1], fi - float(i0))
				var sk: float = bd["sink"]
				var want := clampf(bt - sk + FILL_EMBED, 0.0, scap - sk)
				var aft := maxf(float(bd["s_aft"]) - sx, 0.0) / float(bd["tail"])
				var hw: float = bd["hw"]
				var lat := 1.0 - smoothstep(hw * 0.75, hw + float(bd["bw"]) * 1.4, absf(bv))
				var fh := want * exp(-aft * aft) * lat
				if fh > 0.005:
					var plane := p0.y - (n.x * (x - p0.x) + n.z * (z - p0.z)) / n.y
					hb = _smax(hb, plane + fh / n.y, 0.5)
		# the bed never carves into the cliff below the lip (there the berm ends as a ledge)
		var pf := smoothstep(-330.0, -292.0, h)
		hb = lerpf(h, hb, pf)
		# sediment banked against the hull flanks, higher on the downslope side
		var bw: float = bd["bw"]
		var low := smoothstep(-2.0, 2.0, hb - h)
		hb += exp(-pow((d - bw * 0.6) / bw, 2.0)) * float(bd["berm"]) * (0.45 + 0.55 * low) * pf
		# near the walk a berm may not rise closer than 7 m below it
		if d > 0.0 and hb > h:
			var cw := 1.0 - smoothstep(18.0, 30.0, absf(x - path_x(z)))
			if cw > 0.0:
				hb = lerpf(hb, minf(hb, maxf(h, path_y(z) - 7.0)), cw)
		h = hb
		mask = maxf(mask, w * pf)
		contact = maxf(contact, 1.0 - smoothstep(-bw * 0.5, bw * 0.9, d))   # narrow: a wide dark band read as a hole
	return Vector3(h, mask, contact)


# ------------------------------------------------------------------------------------------- the mesh

static func _band_spacing(bands: Array, x: float, growth: float) -> float:
	for b: Array in bands:
		if x >= float(b[0]) and x < float(b[1]):
			return b[2]
	var first: Array = bands[0]
	var last: Array = bands[bands.size() - 1]
	if x < float(first[0]):
		return float(first[2]) + growth * (float(first[0]) - x)
	return float(last[2]) + growth * (x - float(last[1]))


static func _axis(bands: Array, lo: float, hi: float, growth: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var x := lo
	while x < hi - 1e-3:
		out.append(x)
		x += _band_spacing(bands, x, growth)
	if out.size() > 1 and hi - out[out.size() - 1] < 0.4 * (out[out.size() - 1] - out[out.size() - 2]):
		out[out.size() - 1] = hi
	else:
		out.append(hi)
	return out


## Index of the sample about `dist` metres before/after i (at least one step).
static func _offsets(a: PackedFloat32Array, dist: float) -> Array:
	var lo := PackedInt32Array()
	var hi := PackedInt32Array()
	var n := a.size()
	for i in n:
		var j := maxi(i - 1, 0)
		while j > 0 and absf(a[i] - a[j]) < dist:
			j -= 1
		lo.append(j)
		var m := mini(i + 1, n - 1)
		while m < n - 1 and absf(a[m] - a[i]) < dist:
			m += 1
		hi.append(m)
	return [lo, hi]


static func build(parent: Node3D) -> Node3D:
	var t0 := Time.get_ticks_msec()
	_setup()
	_setup_beds()
	var xs := _axis(X_BANDS, -X_EXTENT, X_EXTENT, 0.065)
	var zd := _axis(Z_BANDS, -975.0, 170.0, 0.0)
	var zs := PackedFloat32Array()          # rows from +z (shallows) to -z (the wall)
	for i in range(zd.size() - 1, -1, -1):
		zs.append(zd[i])
	var nx := xs.size()
	var nz := zs.size()
	var H := PackedFloat32Array()
	var C := PackedColorArray()
	H.resize(nx * nz)
	C.resize(nx * nz)
	for i in nz:
		var z := zs[i]
		for j in nx:
			var x := xs[j]
			var ne := natural_ex(x, z)
			var b := _bed(x, z, ne.x)
			H[i * nx + j] = b.x
			C[i * nx + j] = Color(1.0 - 0.35 * b.z, b.y, ne.y * (1.0 - b.y), 0.0)
	# normals (central differences) and ambient occlusion from the concavity over ~7 m
	var N := PackedVector3Array()
	N.resize(nx * nz)
	var ox := _offsets(xs, 7.0)
	var oz := _offsets(zs, 7.0)
	var oxl: PackedInt32Array = ox[0]
	var oxh: PackedInt32Array = ox[1]
	var ozl: PackedInt32Array = oz[0]
	var ozh: PackedInt32Array = oz[1]
	for i in nz:
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, nz - 1)
		for j in nx:
			var j0 := maxi(j - 1, 0)
			var j1 := mini(j + 1, nx - 1)
			var k := i * nx + j
			var gx := (H[i * nx + j1] - H[i * nx + j0]) / (xs[j1] - xs[j0])
			var gz := (H[i1 * nx + j] - H[i0 * nx + j]) / (zs[i1] - zs[i0])
			N[k] = Vector3(-gx, 1.0, -gz).normalized()
			var hn := (H[i * nx + oxl[j]] + H[i * nx + oxh[j]] + H[ozl[i] * nx + j] + H[ozh[i] * nx + j]) * 0.25
			var cc := C[k]
			cc.r *= clampf(1.0 - maxf(hn - H[k], 0.0) * 0.045, 0.5, 1.0)
			C[k] = cc
	_mxs = xs
	_mzs = zs
	_mh = H
	var root := Node3D.new()
	root.name = "Terrain"
	parent.add_child(root)
	var mat := Mats.make("terrain", {"wall_z": Config.WALL_Z, "sun_dir": Config.SUN_DIR})
	material = mat
	var tiles := 0
	var tris := 0
	var ti := 0
	while ti < nz - 1:
		var i_end := mini(ti + TILE, nz - 1)
		var tj := 0
		while tj < nx - 1:
			var j_end := mini(tj + TILE, nx - 1)
			# skip tiles entirely hidden behind the wall
			var xn := 0.0 if xs[tj] <= 0.0 and xs[j_end] >= 0.0 else minf(absf(xs[tj]), absf(xs[j_end]))
			if zs[ti] < Config.WALL_Z + xn * xn / 5000.0 - 20.0:
				tj = j_end
				continue
			var mesh := _tile(xs, zs, H, N, C, ti, i_end, tj, j_end)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.name = "T%d_%d" % [ti, tj]
			root.add_child(mi)
			tiles += 1
			tris += (i_end - ti) * (j_end - tj) * 2
			tj = j_end
		ti = i_end
	var rocks := Rocks.build(root)
	print("terrain: %d x %d samples, %d tiles, %d tris, %d rocks, %d ms" % [nx, nz, tiles, tris,
		int(rocks.get_meta("count", 0)), Time.get_ticks_msec() - t0])
	return root


static func _tile(xs: PackedFloat32Array, zs: PackedFloat32Array, H: PackedFloat32Array, N: PackedVector3Array,
		C: PackedColorArray, i0: int, i1: int, j0: int, j1: int) -> ArrayMesh:
	var nx := xs.size()
	var w := j1 - j0 + 1
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			var k := i * nx + j
			v.append(Vector3(xs[j], H[k], zs[i]))
			n.append(N[k])
			c.append(C[k])
	var idx := PackedInt32Array()
	for i in i1 - i0:
		for j in j1 - j0:
			var a := i * w + j            # (row i, col j); row i+1 lies further toward -z
			var b := a + 1
			var d := a + w
			var e := d + 1
			idx.append_array([a, d, e, a, e, b])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
