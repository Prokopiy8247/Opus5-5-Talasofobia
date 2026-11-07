extends RefCounted
## Procedural reef geometry. The wall face is a displaced sheet along an outline polyline; its top rows roll over a
## rounded crest and dip back into the reef top. The plateau heightfield is snapped to a line under that crest, so
## neither sheet ever shows a free edge. Free-standing rock columns (pinnacles rising out of the deep in the bays,
## bommies on the reef top) are appended to the wall surface, so they cast shadows and the fauna wall index sees them.
## Vertex colour = linear rock albedo, alpha = AO; UV = (life cover, colony bias).

## Outline of the reef massif in XZ, walked with the open water on the right-hand (outward) side. Both ends turn
## away into the haze so the sheet's end edges are never seen.
const OUTLINE := [Vector2(-240, 650), Vector2(-100, 565), Vector2(-44, 440), Vector2(-34, 320), Vector2(-38, 230),
	Vector2(-31, 150), Vector2(-36, 70), Vector2(-32, 0), Vector2(-37, -70), Vector2(-31, -140), Vector2(-36, -200), Vector2(-32, -265),
	Vector2(-35, -330), Vector2(-36, -384), Vector2(-42, -408), Vector2(-56, -424), Vector2(-92, -434), Vector2(-150, -448), Vector2(-205, -437), Vector2(-260, -452),
	Vector2(-335, -440), Vector2(-420, -449), Vector2(-520, -430), Vector2(-760, -330), Vector2(-900, -160), Vector2(-960, 60)]
## Far interior points closing the outline into the massif polygon (inside tests).
const CLOSE := [Vector2(-1200, 300), Vector2(-1150, 820), Vector2(-420, 840)]
## Large meanders of the outline, laid along the outward normal over the base arc length u (m):
## [u0, u1, offset (m, + = out into the open water), skew (+ moves the extreme towards u1)]. Raised-cosine lobes,
## smooth at both ends. Where the path runs along the face (u 744-1072) there are only bays, so the face never
## comes closer to the path; the far side of each bay faces the approaching diver, so the wall ahead steps back in
## layers. The prow and the lip's buried flank (u 1072-1215) are left exactly as they were.
const MEANDERS := [
	[300.0, 470.0, -24.0, -0.1],
	[470.0, 610.0, 16.0, 0.0],
	[610.0, 735.0, -16.0, 0.0],
	[785.0, 962.0, -27.0, 0.4],     # bay A, z -45..-215
	[962.0, 1072.0, -22.0, 0.3],    # bay B, z -215..-325; closes before the lip
	[1215.0, 1335.0, 20.0, 0.0],    # south face west of the prow: headlands and bays stepping into the haze
	[1335.0, 1460.0, -24.0, -0.15],
	[1460.0, 1590.0, 26.0, 0.1],
	[1590.0, 1700.0, -18.0, 0.0],
]
const PROW_U := Vector2(1072.0, 1215.0)   # no curvature limits here: the prow keeps its old relief around the lip
## The far straight segment, the prow and the south-face headland (base arc length): seen edge-on from the shallows
## (the far end of the wall ahead), beside the path under the lip and looking back past the prow. Depth-varying relief keeps their silhouette from being one vertical
## line: [fade in from, full from, full to, fade out at].
const FAR_U := Vector4(1030.0, 1058.0, 1318.0, 1345.0)
## Where the lip roots in the face (y): no inward relief there, so the lip's flank stays buried in the rock.
## Headlands between the bays that the path sees edge-on ahead (the point between bays A and B is the vertical edge
## under the crest in the 45-60 s ahead views): [u centre, half width] (base arc length).
const HEADLANDS := [Vector2(972.0, 44.0)]
const LIP_Y := Vector4(-116.0, -106.0, -68.0, -59.0)
## Detached pinnacles in front of the bay faces: free spires near the top that flare into buttresses and merge with
## the face below (seen ahead from the shallows, beside the path in beat 2): [x, z, top y, top radius].
## (No pinnacle beyond the prow: the drop into the open abyss stays empty.)
const PINNACLES := [[-47.0, -150.0, -27.0, 5.5], [-46.0, -284.0, -46.0, 6.0]]
const ANCHOR_XZ := Vector2(-38.0, -38.0)   # anchor line end and the beat-1 reef fish: the reef top stays calm here
const CREST_Y := -14.5      # mean reef-top height
const TOP_MIN := -19.0      # crest / reef-top limits (the crest roll needs a few metres above FACE_TOP)
const TOP_MAX := -6.0
const FACE_TOP := -22.0     # face rows end here; the crest profile takes over above
const BOTTOM_Y := -1250.0
const CLIP := 4.0           # the plateau ends this far behind the face top (hidden under the crest)
const BK := 30.0            # outline bucket size (m)

var big := FastNoiseLite.new()
var mid := FastNoiseLite.new()
var fine := FastNoiseLite.new()
var ledge_n := FastNoiseLite.new()
var colour_n := FastNoiseLite.new()
var cell := FastNoiseLite.new()
var ledges: Array = []      # [y, amplitude]
var caves: Array = []       # [u, y, radius_u, radius_y, depth]
var outline_pts := PackedVector2Array()
var outline_len := PackedFloat32Array()   # base arc length before the meanders: the noise coordinate along the face
var outline_out := PackedVector2Array()   # outward normal per sample
var lim_out := PackedFloat32Array()       # largest outward displacement the local bend allows (concave side)
var lim_in := PackedFloat32Array()        # largest inward displacement (convex side)
var d_top := PackedFloat32Array()         # face displacement at FACE_TOP per sample
var poly := PackedVector2Array()
var columns := 0                          # rock columns built (pinnacles + bommies)
var _bk := {}
var _bk_near := {}                        # buckets within 2 of an outline sample (fast reject in nearest)
var _path_z := PackedFloat32Array()       # path height by z (ascending z), for depth-relative relief
var _path_y := PackedFloat32Array()
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.seed = 77
	big.seed = 3; big.frequency = 0.011; big.fractal_octaves = 3
	mid.seed = 13; mid.frequency = 0.075; mid.fractal_type = FastNoiseLite.FRACTAL_RIDGED; mid.fractal_octaves = 3
	fine.seed = 9; fine.frequency = 0.35; fine.fractal_octaves = 2
	ledge_n.seed = 21; ledge_n.frequency = 0.02
	colour_n.seed = 5; colour_n.frequency = 0.05; colour_n.fractal_octaves = 2
	cell.seed = 31; cell.noise_type = FastNoiseLite.TYPE_CELLULAR; cell.frequency = 0.06
	cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE; cell.fractal_type = FastNoiseLite.FRACTAL_NONE
	var y := -28.0
	while y > -420.0:
		ledges.append([y, rng.randf_range(2.5, 7.0)])
		y -= rng.randf_range(16.0, 38.0) * (1.0 + (-y) / 250.0)
	_build_outline()
	_build_path_table()
	var total := outline_len[outline_len.size() - 1]
	for i in 30:        # big recesses
		caves.append([rng.randf_range(40.0, total - 40.0), rng.randf_range(-260.0, -30.0),
			rng.randf_range(5.0, 12.0), rng.randf_range(3.0, 7.0), rng.randf_range(4.0, 8.0)])
	for i in 260:       # small dark holes, dense where the path runs
		caves.append([rng.randf_range(180.0, 1100.0), rng.randf_range(-160.0, -26.0),
			rng.randf_range(1.2, 3.5), rng.randf_range(0.9, 2.4), rng.randf_range(1.5, 3.5)])

static func _near(p: Vector2) -> bool:
	return p.y > -490.0 and p.y < 190.0 and p.x > -240.0

## Outward offset of the outline at base arc length u (see MEANDERS).
static func meander(u: float) -> float:
	var m := 0.0
	for b in MEANDERS:
		if u > b[0] and u < b[1]:
			var v: float = (u - b[0]) / (b[1] - b[0])
			v -= b[3] * sin(PI * v) / PI
			m += b[2] * 0.5 * (1.0 - cos(TAU * v))
	return m

func _build_outline() -> void:
	# Catmull-Rom resample: ~2 m columns along the part the path passes, ~4.5 m elsewhere
	var p: Array = OUTLINE
	var base := PackedVector2Array()
	for i in range(p.size() - 1):
		var p0: Vector2 = p[maxi(i - 1, 0)]; var p1: Vector2 = p[i]; var p2: Vector2 = p[i + 1]; var p3: Vector2 = p[mini(i + 2, p.size() - 1)]
		var step := 2.0 if _near((p1 + p2) * 0.5) else 4.5
		var n := maxi(2, int(p1.distance_to(p2) / step))
		for k in n:
			var t := float(k) / n
			base.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	base.append(p[p.size() - 1])
	var cnt := base.size()
	var acc := 0.0
	for i in cnt:
		if i > 0: acc += base[i].distance_to(base[i - 1])
		outline_len.append(acc)
	# meanders along the base normal (columns stretch by at most ~25 % on the bay flanks)
	for i in cnt:
		var t := (base[mini(i + 1, cnt - 1)] - base[maxi(i - 1, 0)]).normalized()
		outline_pts.append(base[i] + Vector2(-t.y, t.x) * meander(outline_len[i]))
	for i in cnt:
		var a := outline_pts[maxi(i - 1, 0)]
		var b := outline_pts[mini(i + 1, cnt - 1)]
		var t := (b - a).normalized()
		outline_out.append(Vector2(-t.y, t.x))      # right-hand side of the walking direction (+X on the east face)
		var key := Vector2i(floori(outline_pts[i].x / BK), floori(outline_pts[i].y / BK))
		if not _bk.has(key):
			_bk[key] = PackedInt32Array()
		_bk[key].append(i)
	for key in _bk:
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				_bk_near[key + Vector2i(dx, dz)] = true
	# bend radius per sample: displacement towards the centre of a bend is kept below it, so bays never fold
	lim_out.resize(cnt); lim_in.resize(cnt)
	for i in cnt:
		lim_out[i] = 1e6; lim_in[i] = 1e6
		var u := outline_len[i]
		if u > PROW_U.x and u < PROW_U.y:
			continue
		var a := outline_pts[maxi(i - 3, 0)]; var b := outline_pts[i]; var c := outline_pts[mini(i + 3, cnt - 1)]
		var cr := (b - a).cross(c - b)
		var den := 2.0 * absf((b - a).cross(c - a))
		if den < 1e-6:
			continue
		var rad := a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / den
		if cr > 0.0:
			lim_out[i] = 0.8 * rad      # bends towards the water: the open side is concave
		else:
			lim_in[i] = 0.8 * rad
	for q in outline_pts: poly.append(q)
	for q in CLOSE: poly.append(q)

func _build_path_table() -> void:
	if PathDef.curve == null:
		return
	var l := PathDef.curve.get_baked_length()
	var off := l
	while off >= 0.0:
		var q := PathDef.curve.sample_baked(off)
		if _path_z.is_empty() or q.z > _path_z[_path_z.size() - 1]:
			_path_z.append(q.z); _path_y.append(q.y)
		off -= 2.0

## Path height at z (the path runs down -z); the start height beyond its ends.
func path_y_at(z: float) -> float:
	if _path_z.is_empty():
		return lerpf(-2.5, -117.0, clampf(-z / 392.0, 0.0, 1.0))
	var n := _path_z.size()
	if z >= _path_z[n - 1]:
		return _path_y[n - 1]
	if z <= _path_z[0]:
		return _path_y[0]
	var k := _path_z.bsearch(z)
	var t := (z - _path_z[k - 1]) / maxf(_path_z[k] - _path_z[k - 1], 1e-4)
	return lerpf(_path_y[k - 1], _path_y[k], t)

func outward(i: int) -> Vector2:
	return outline_out[i]

## Nearest outline sample within ~2 BK, or -1.
func nearest(q: Vector2) -> int:
	var cx := floori(q.x / BK); var cz := floori(q.y / BK)
	if not _bk_near.has(Vector2i(cx, cz)):
		return -1        # no outline sample within two buckets
	var best := 1e18
	var bi := -1
	for ring in 3:
		if ring == 0:
			continue
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring and ring > 1:
					continue      # the inner block was searched already
				var key := Vector2i(cx + dx, cz + dz)
				if not _bk.has(key):
					continue
				var arr: PackedInt32Array = _bk[key]
				for i in arr:
					var dd := outline_pts[i].distance_squared_to(q)
					if dd < best:
						best = dd; bi = i
		if best <= BK * BK * float(ring * ring):
			break         # nothing outside this block can be closer
	return bi

## Signed distance (m) of (x, z) behind the face top (> 0 inside the massif). Far points return +-60.
func inside_face(x: float, z: float) -> float:
	var q := Vector2(x, z)
	var i := nearest(q)
	if i < 0:
		return 60.0 if Geometry2D.is_point_in_polygon(q, poly) else -60.0
	return -(q - outline_pts[i]).dot(outline_out[i]) + d_top[i]

## Large and mid scale outward displacement of the face (metres, + = towards open water). No horizontal strata:
## vertical buttresses, rock masses, ridged blocks and small relief.
func disp_base(u: float, y: float) -> float:
	var rib := 1.0 - absf(big.get_noise_2d(u * 2.6, y * 0.5))
	var d := 9.0 * (rib - 0.6)
	d += 4.5 * big.get_noise_2d(u * 0.8 + 100.0, y * 0.8)
	d += 4.0 * big.get_noise_2d(u * 2.8 + 300.0, y * 2.8)
	d += 9.0 * pow(maxf(big.get_noise_2d(u * 3.5 + 900.0, y * 3.5), 0.0), 1.5)      # isolated outcrops
	d += 2.4 * mid.get_noise_2d(u, y * 1.25)
	d += 0.55 * fine.get_noise_2d(u, y)
	# far below the path the face can swing much further in and out: big buttresses and bays
	d += 11.0 * big.get_noise_2d(u * 1.4 + 1300.0, y * 1.3) * smoothstep(-150.0, -240.0, y)
	return d

## Deep spurs: vertical buttresses (~60 m apart) and broad bays, long down the face. Faded in from ~30 m below the
## path, so the deep outline seen from above is never a straight plate.
func spur(u: float, y: float) -> float:
	var b := 1.0 - absf(big.get_noise_2d(u * 1.5 + 2100.0, y * 0.35))
	var g := big.get_noise_2d(u * 0.55 + 2600.0, y * 0.25)
	return 24.0 * (b - 0.62) + 20.0 * g

## Outward reach of the face near the path's level: buttresses (up to the old 10 m limit, so the path clearance
## holds) alternate with grooves held to 3.5 m every 20-30 m along the wall, and the reach also swells and shrinks
## down each buttress (~40 m rhythm), so the face seen edge-on or from above is a row of buttresses, never one plane
## or one straight vertical edge.
func reach(u: float, y: float) -> float:
	var n := big.get_noise_2d(u * 2.0 + 3300.0, y * 0.4) + 0.5 * big.get_noise_2d(u * 0.9 + 3700.0, y * 2.3)
	return 3.5 + 6.5 * smoothstep(-0.25, 0.45, n)

## Outward cap far below the path: 12-19 m, varying down the face (~55 m rhythm).
func deep_cap(u: float, y: float) -> float:
	return 12.0 + 7.0 * smoothstep(-0.3, 0.3, big.get_noise_2d(u * 0.7 + 4100.0, y * 1.65))

## Relief of the far straight segment, the prow and the south face (FAR_U), added after the knee, so it is never
## flattened. Seen edge-on from the shallows the far end must not be one vertical edge under a flat crest:
## - undercuts on a ~100 m rhythm shared along the segment (its phase drifts along u) plus ~28 m notches;
## - the upper face of the far end is bevelled back (up to ~22 m at the crest, nothing at the lip's band), so seen
##   from the shallows the crest ends well before the edge below it and the corner is a slope, not a right angle;
## - a deep keel buttress juts from the prow tip 20+ m below the path.
## In the lip's root band (LIP_Y, up to the prow) only outward relief. The prow tip (the path 45+ m away) gets
## outward buttresses at every depth, on the south face (no lip, the path 60+ m away) they stand out as well.
func far_relief(u: float, y: float) -> float:
	var w := smoothstep(FAR_U.x, FAR_U.y, u) * (1.0 - smoothstep(FAR_U.z, FAR_U.w, u))
	if w <= 0.0:
		return 0.0
	var lip := smoothstep(LIP_Y.x, LIP_Y.y, y) * (1.0 - smoothstep(LIP_Y.z, LIP_Y.w, y)) * (1.0 - smoothstep(1205.0, 1222.0, u))
	var ph := 14.0 * big.get_noise_1d(u * 1.2 + 7300.0) + 5.0 * big.get_noise_1d(u * 4.0 + 7900.0)
	var nl := big.get_noise_2d(u * 0.2 + 7000.0, (y + ph) * 0.9)
	var ns := big.get_noise_2d(u * 1.1 + 7600.0, (y + ph) * 3.2)
	var cut := -11.0 * smoothstep(-0.12, 0.3, nl) - 5.0 * smoothstep(-0.05, 0.4, ns)
	var sh := smoothstep(1058.0, 1092.0, u) * (1.0 - smoothstep(1170.0, 1198.0, u)) * smoothstep(-66.0, -24.0, y)
	cut = maxf(cut - sh * (20.0 + 5.0 * smoothstep(-0.3, 0.3, ns)), -27.0)
	var tip := smoothstep(1140.0, 1156.0, u) * (1.0 - smoothstep(1186.0, 1202.0, u))
	var nb := big.get_noise_2d(u * 1.3 + 8800.0, y * 4.6)
	var bulge := minf(6.0 * smoothstep(-0.1, 0.5, -ns) + 5.0 * smoothstep(0.05, 0.45, nb), 8.0) * tip
	var butt := 8.0 * smoothstep(0.0, 0.45, -nl) * smoothstep(1215.0, 1240.0, u)
	var keel := smoothstep(1136.0, 1150.0, u) * (1.0 - smoothstep(1172.0, 1190.0, u)) * smoothstep(-136.0, -152.0, y) * (1.0 - smoothstep(-250.0, -320.0, y))
	return w * ((cut + butt) * (1.0 - lip) + bulge) + keel * (9.0 + 4.0 * smoothstep(-0.3, 0.3, nl))

## Relief of a headland point between two bays and the flank behind it (HEADLANDS). Seen from up the path, the
## point and the curving bay flank behind it form one edge-on silhouette, so the relief is shared across them:
## shelves stand out and undercuts cut in on a ~32 m vertical rhythm (the silhouette steps in and out), and the top
## is bevelled back up to ~12 m, so the crest rounds off before the edge instead of meeting it at a right angle.
## Near the path's level the point only ever moves in (the path passes 23 m off its tip); shelves stand out only on
## the flank deeper in the bay or 30+ m below the path.
func headland_relief(u: float, y: float) -> float:
	var r := 0.0
	for h in HEADLANDS:
		var w := 1.0 - smoothstep(h.y * 0.55, h.y, absf(u - h.x))
		if w <= 0.0:
			continue
		var ph := 10.0 * big.get_noise_1d(u * 1.5 + 9100.0)
		var n := big.get_noise_2d(u * 0.6 + 9300.0, (y + ph) * 2.8) + 0.4 * big.get_noise_2d(u * 1.4 + 9500.0, y * 6.5)
		var bevel := 12.0 * smoothstep(-54.0, -23.0, y)
		var deep := 1.0 - smoothstep(-250.0, -330.0, y)
		var cut := 9.0 * smoothstep(-0.12, 0.38, n) * deep
		var out := 7.0 * smoothstep(0.12, -0.38, n) * deep * maxf(smoothstep(h.x + 12.0, h.x + 28.0, u), smoothstep(-90.0, -106.0, y))
		r += w * (out * (1.0 - bevel / 12.0) - minf(bevel + cut * (1.0 - 0.6 * bevel / 12.0), 17.0))
	return r

## Lateral drift (m along the face) of the deep relief with depth: buttresses twist and wander as they go down, so
## the deep layers seen from above never copy each other's outline.
func deep_warp(u: float, y: float) -> float:
	return 26.0 * big.get_noise_2d(u * 0.6 + 8000.0, y * 1.8) + 9.0 * big.get_noise_2d(u * 1.7 + 8400.0, y * 4.5)

## Relief compression: identity up to 60 % of `cap`, then a slope of 0.35 easing into the cap, so the tips keep
## their own heights (a hard or saturating clamp lines them up into one flat plane).
static func knee(d: float, cap: float) -> float:
	cap = maxf(cap, 1.0)
	var k := cap * 0.6
	if d <= k:
		return d
	var room := cap - k
	return k + room * tanh((d - k) * 0.35 / room)

static func _softplus(x: float, k: float) -> float:
	return k * log(1.0 + exp(clampf(x / k, -30.0, 30.0)))

## 0 around the anchor line end and the beat-1 reef fish, 1 away from them.
static func _calm(x: float, z: float) -> float:
	return smoothstep(30.0, 80.0, Vector2(x, z).distance_to(ANCHOR_XZ))

## Reef-top base height: long swells and hollows that break the horizon (flat around the anchor) plus small relief.
func plateau_base(x: float, z: float) -> float:
	var swell := 4.5 * big.get_noise_2d(x * 0.55 + 700.0, z * 0.55) + 0.6 * big.get_noise_2d(x * 2.0, z * 2.0)
	return CREST_Y + 1.3 * big.get_noise_2d(x * 2.0, z * 2.0) + swell * _calm(x, z) + 0.45 * fine.get_noise_2d(x * 0.15, z * 0.15)

## Extra height along the crest (u) at `inward` m behind the face top: saddles and high points on the rim, and
## spur-and-groove notches cut into its edge.
## Where the crest is the skyline ahead (z < -200, out to the prow) the saddles and high points are deeper and taller.
func crest_relief(u: float, inward: float) -> float:
	var far := smoothstep(900.0, 1000.0, u) * (1.0 - smoothstep(1190.0, 1240.0, u))
	var hi := lerpf(4.0, 8.5, far) * big.get_noise_1d(u * 0.8 + 5000.0) + lerpf(1.8, 2.6, far) * mid.get_noise_1d(u * 0.3 + 70.0)
	var groove := lerpf(-3.2, -4.2, far) * pow(1.0 - absf(ledge_n.get_noise_1d(u * 2.6 + 900.0)), 5.0)
	return hi * (1.0 - smoothstep(12.0, 70.0, inward)) + groove * (1.0 - smoothstep(3.0, 13.0, inward))

## Reef-top height at (x, z), `inward` m behind the face top of outline sample u. Crest and plateau both use it,
## so they always meet.
func top_height(x: float, z: float, u: float, inward: float) -> float:
	var y := plateau_base(x, z)
	if inward < 70.0:      # the crest relief is zero further in
		y += crest_relief(u, inward) * _calm(x, z)
	y = TOP_MIN + _softplus(y - TOP_MIN, 1.0)
	return TOP_MAX - _softplus(TOP_MAX - y, 1.0)

## Face rows: dense in the sunlit top where the path runs, <= 7 m down to the depth the corridor sees, coarse in
## the depth that fog swallows.
func face_rows() -> PackedFloat32Array:
	var r := PackedFloat32Array()
	var y := FACE_TOP
	while y > BOTTOM_Y:
		r.append(y)
		if y > -150.0: y -= 1.0
		elif y > -210.0: y -= 2.0
		elif y > -330.0: y -= 5.0
		elif y > -560.0: y -= 7.0
		elif y > -800.0: y -= 16.0
		else: y -= 30.0
	r.append(BOTTOM_Y)
	return r

## Crest profile above the face top, ordered from the buried tail to the face: Vector3(inward, blend, dy).
## y = lerp(FACE_TOP, crest_y + dy, blend).
func crest_profile() -> Array:
	var c: Array = [Vector3(14.0, 1.0, -5.5), Vector3(12.5, 1.0, -3.4), Vector3(11.0, 1.0, -1.7), Vector3(9.5, 1.0, -0.5),
		Vector3(8.0, 1.0, 0.4), Vector3(6.5, 1.0, 0.75)]
	var rw := 5.0
	for k in range(8, 0, -1):
		var a := PI * 0.5 * k / 8.0
		c.append(Vector3(rw * (1.0 - cos(a)), sin(a), 0.7))
	return c

## Rock base colour (sRGB): grey to brown limestone with darker patches.
func rock_colour(a: float, b: float) -> Color:
	var n := colour_n.get_noise_2d(a * 0.3, b * 0.6)
	var n2 := colour_n.get_noise_2d(a * 1.7 + 40.0, b * 1.7)
	var c := Color(0.40, 0.385, 0.35).lerp(Color(0.43, 0.37, 0.29), clampf(0.5 + n, 0.0, 1.0))
	return c * (0.85 + 0.25 * n2)

## The wall face sheet with its crest, plus the rock columns. Fills dress with [position, normal, depth, kind, cavity]
## (kind 0 face, 1 crest / column top).
func wall_mesh(dress: Array) -> ArrayMesh:
	var ys := face_rows()
	var nf := ys.size()
	var crest := crest_profile()
	var nc := crest.size()
	var nr := nc + nf
	var cols := outline_pts.size()
	var verts := PackedVector3Array(); verts.resize(cols * nr)
	var cavity := PackedFloat32Array(); cavity.resize(cols * nr)     # extra darkness from caves
	d_top.resize(cols)
	var dcol := PackedFloat32Array(); dcol.resize(nf)
	var ccol := PackedFloat32Array(); ccol.resize(nf)
	var yneg := PackedFloat32Array(); yneg.resize(nf)     # ascending copy of -y for bsearch
	for j in nf: yneg[j] = -ys[j]
	for i in cols:
		var o := outline_out[i]
		var u := outline_len[i]
		var op := outline_pts[i]
		var ref_y := path_y_at(clampf(op.y, -460.0, 0.0))     # the diver's height where this column is seen
		var uws := PackedFloat32Array(); uws.resize(nf)       # deep relief is sampled at a laterally drifting u
		for j in nf:
			var wd := smoothstep(12.0, 50.0, ref_y - ys[j])
			uws[j] = u + deep_warp(u, ys[j]) * wd if wd > 0.0 else u
			dcol[j] = disp_base(uws[j], ys[j])
			ccol[j] = 0.0
		for l in ledges:      # short, tilted ledge segments with an up-facing shelf (never one continuous contour)
			var ly: float = l[0] + 9.0 * ledge_n.get_noise_2d(u * 0.7, l[0] * 3.0) + 3.0 * ledge_n.get_noise_2d(u * 3.0 + 500.0, l[0])
			var a: float = l[1] * clampf(-0.1 + 1.8 * ledge_n.get_noise_2d(u * 1.6, l[0]), 0.0, 1.3)
			if a <= 0.05:
				continue
			for j in range(yneg.bsearch(-(ly + 1.5)), nf):
				var y := ys[j]
				if y < ly - 10.0: break
				dcol[j] += a * smoothstep(ly - 9.0, ly - 1.0, y) * (1.0 - smoothstep(ly - 0.2, ly + 1.2, y))
		for c in caves:
			var du: float = (u - c[0]) / c[2]
			if absf(du) > 2.0:
				continue
			for j in range(yneg.bsearch(-(c[1] + 2.0 * c[3])), nf):
				var dy: float = (ys[j] - c[1]) / c[3]
				if dy < -2.0: break
				var q := du * du + dy * dy
				if q < 4.0:
					var e := exp(-q * 1.6)
					dcol[j] -= c[4] * e
					ccol[j] = maxf(ccol[j], e)
		var d_ft := disp_base(u, FACE_TOP)
		for j in nf:
			var y := ys[j]
			# the top few metres straighten into the crest
			var top := smoothstep(FACE_TOP - 8.0, FACE_TOP, y)
			var d := lerpf(dcol[j], d_ft, top * 0.6)
			# deep spurs and grooves, and a wider reach, from ~30 m below the diver's level down
			var deep := smoothstep(30.0, 100.0, ref_y - y)
			if deep > 0.0:
				d += spur(uws[j], y) * deep
			var far := smoothstep(-150.0, -240.0, y)
			var mx := maxf(deep, far)
			var cap_out := minf(lerpf(reach(u, y) if mx < 1.0 else 0.0, deep_cap(uws[j], y) if mx > 0.0 else 0.0, mx), lim_out[i])
			var cap_in := minf(22.0 + 16.0 * deep, lim_in[i])
			dcol[j] = (knee(d, cap_out) if d > 0.0 else -knee(-d, cap_in)) + far_relief(u, y) + headland_relief(u, y)
		var dt := dcol[0]
		d_top[i] = dt
		var ft := op + o * dt
		for k in nc:
			var cp: Vector3 = crest[k]
			var r := 0.45 * fine.get_noise_2d(u * 1.4 + 500.0, k * 4.0)
			var p := op + o * (dt - cp.x + r)
			var yc := top_height(ft.x, ft.y, u, maxf(cp.x - r, 0.0))
			verts[i * nr + k] = Vector3(p.x, lerpf(FACE_TOP, yc + cp.z, cp.y) + r * 0.5, p.y)
			cavity[i * nr + k] = 0.0
		for j in nf:
			var p := op + o * dcol[j]
			verts[i * nr + nc + j] = Vector3(p.x, ys[j], p.y)
			cavity[i * nr + nc + j] = ccol[j]
	var us := PackedFloat32Array(); us.resize(cols)
	for i in cols: us[i] = outline_len[i]
	var sh := _shade_grid(verts, cavity, cols, nr, false, us, nc, dress, 0)
	var all_v := verts
	var all_n: PackedVector3Array = sh[0]
	var all_c: PackedColorArray = sh[1]
	var all_uv: PackedVector2Array = sh[2]
	var all_i: PackedInt32Array = sh[3]
	# rock columns: detached pinnacles from the deep, bommies standing on the reef top
	var specs: Array = []
	for pn in PINNACLES:
		var pc := Vector2(pn[0], pn[1])
		var ni := nearest(pc)
		var back := -outline_out[ni] if ni >= 0 else Vector2(-1.0, 0.0)
		specs.append([pc, pn[2], -600.0, pn[3], 40.0, 150.0, 4.0, back, [0.75, 0.0, 0.0, 0.0, 0.0, 0.3]])
	for b in _bommies():
		specs.append(b)
	columns = specs.size()
	var seed_off := 0.0
	for s in specs:
		seed_off += 157.0
		var col: Array = _column(s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7], seed_off, s[8])
		var cv: PackedVector3Array = col[0]
		var cg := _shade_grid(cv, col[1], col[2], col[3], true, col[4], col[5], dress, all_v.size())
		all_v.append_array(cv)
		all_n.append_array(cg[0]); all_c.append_array(cg[1]); all_uv.append_array(cg[2]); all_i.append_array(cg[3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = all_v; arr[Mesh.ARRAY_NORMAL] = all_n; arr[Mesh.ARRAY_COLOR] = all_c
	arr[Mesh.ARRAY_TEX_UV] = all_uv; arr[Mesh.ARRAY_INDEX] = all_i
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## Normals, AO, colour, life cover and triangles for a grid surface (ncol x nr, k = i * nr + j, rows running down),
## index base `base`. `wrap` closes the grid around (a column); rows above `top_rows` sample as crest/top (kind 1).
## Returns [normals, colours, uvs, indices].
func _shade_grid(verts: PackedVector3Array, cavity: PackedFloat32Array, ncol: int, nr: int, wrap: bool,
		us: PackedFloat32Array, top_rows: int, dress: Array, base: int) -> Array:
	var norms := PackedVector3Array(); norms.resize(verts.size())
	var cols_a := PackedColorArray(); cols_a.resize(verts.size())
	var uvs := PackedVector2Array(); uvs.resize(verts.size())
	for i in ncol:
		var u := us[i]
		var ip := (i + 1) % ncol if wrap else mini(i + 1, ncol - 1)
		var im := (i - 1 + ncol) % ncol if wrap else maxi(i - 1, 0)
		var ip4 := (i + 4) % ncol if wrap else mini(i + 4, ncol - 1)
		var im4 := (i - 4 + ncol) % ncol if wrap else maxi(i - 4, 0)
		for j in nr:
			var k := i * nr + j
			var v := verts[k]
			var du := verts[ip * nr + j] - verts[im * nr + j]
			var dv := verts[i * nr + mini(j + 1, nr - 1)] - verts[i * nr + maxi(j - 1, 0)]
			var n := dv.cross(du)
			n = n.normalized() if n.length_squared() > 1e-12 else Vector3.UP
			norms[k] = n
			# concavity from two neighbourhood scales (holes and grooves get darker)
			var l1 := (verts[ip * nr + j] + verts[im * nr + j] + verts[i * nr + mini(j + 2, nr - 1)] + verts[i * nr + maxi(j - 2, 0)]) * 0.25 - v
			var l2 := (verts[ip4 * nr + j] + verts[im4 * nr + j] + verts[i * nr + mini(j + 6, nr - 1)] + verts[i * nr + maxi(j - 6, 0)]) * 0.25 - v
			var conc := l1.dot(n) * 0.9 + l2.dot(n) * 0.22
			var ao := clampf(0.92 - conc * 0.55 - cavity[k] * 0.55, 0.22, 1.0)
			ao *= lerpf(0.72, 1.0, clampf(n.y * 0.8 + 0.8, 0.0, 1.0))        # undersides see less of the bright sky
			var depth := -v.y
			var c := rock_colour(u, v.y).srgb_to_linear()
			c.a = ao
			cols_a[k] = c
			var cover := (1.0 - smoothstep(30.0, 160.0, depth)) * clampf(0.55 + 0.7 * n.y, 0.12, 1.0)
			cover *= clampf(0.8 + 0.6 * colour_n.get_noise_2d(u * 0.6, v.y * 0.8), 0.25, 1.2) * (1.0 - cavity[k] * 0.7)
			uvs[k] = Vector2(clampf(cover, 0.0, 1.0), clampf(0.5 + 0.8 * colour_n.get_noise_2d(u * 0.25 + 300.0, v.y * 0.25), 0.0, 1.0))
			if depth < 200.0 and rng.randf() < (0.4 if j < top_rows else 0.26):
				dress.append([v, n, depth, 1 if j < top_rows else 0, cavity[k]])
	var idx := PackedInt32Array()
	var ni := ncol if wrap else ncol - 1
	idx.resize(ni * (nr - 1) * 6)
	var w := 0
	for i in ni:
		var i2 := (i + 1) % ncol
		for j in nr - 1:
			var a := base + i * nr + j
			var b := base + i2 * nr + j
			idx[w] = a; idx[w + 1] = a + 1; idx[w + 2] = b
			idx[w + 3] = a + 1; idx[w + 4] = b + 1; idx[w + 5] = b
			w += 6
	return [norms, cols_a, uvs, idx]

## Rock towers on the far crest, where it is the skyline ahead from the shallows (breaks the flat top of the far
## end of the wall): [x, z, height above the reef top, top radius].
const CREST_TOWERS := [[-70.0, -343.0, 12.5, 4.4], [-80.0, -377.0, 8.5, 3.3]]

## Random crown shape [dome height / top radius, tilt, tilt azimuth, elongation, elongation azimuth, lobing]: flat
## tables, rounded heads and tall knobs, slanted, oval or strongly lobed, so no two bommies share a silhouette.
static func _crown(r: RandomNumberGenerator) -> Array:
	var kind := r.randf()
	var dk := r.randf_range(0.22, 0.42) if kind < 0.35 else (r.randf_range(0.55, 0.9) if kind < 0.7 else r.randf_range(1.0, 1.5))
	return [dk, r.randf_range(0.0, 0.55), r.randf_range(0.0, TAU), r.randf_range(0.0, 0.42), r.randf_range(0.0, TAU), r.randf_range(0.25, 0.6)]

## Bommies on the reef top 60-160 m from the path (they break the crest skyline), a few far ones on the horizon and
## the towers on the far crest: [centre, top y, bottom y, top radius, flare, flare length, lean, back, crown]. Some
## get a smaller satellite knob beside them. Must run after the face columns (uses d_top).
func _bommies() -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = 404
	var out: Array = []
	for t in CREST_TOWERS:
		var q := Vector2(t[0], t[1])
		var ins := inside_face(q.x, q.y)
		if ins < 9.0:
			continue
		var i := nearest(q)
		var ground := top_height(q.x, q.y, outline_len[i] if i >= 0 else 0.0, ins)
		var top := minf(ground + float(t[2]), -4.5)
		out.append([q, top, ground - 5.0, t[3], 3.5, 12.0, 1.6, Vector2.ZERO, _crown(r)])
	var placed: Array = []
	var tries := 0
	while placed.size() < 17 and tries < 600:
		tries += 1
		var near := placed.size() < 11
		var q := Vector2(r.randf_range(-165.0, -62.0), r.randf_range(-410.0, 110.0)) if near \
			else Vector2(r.randf_range(-330.0, -175.0), r.randf_range(-420.0, 160.0))
		if q.distance_to(ANCHOR_XZ) < 75.0:
			continue
		var ins := inside_face(q.x, q.y)
		if ins < 18.0:
			continue
		var ok := true
		for pq in placed:
			if q.distance_to(pq) < (38.0 if near else 60.0):
				ok = false; break
		if not ok:
			continue
		placed.append(q)
		var i := nearest(q)
		var u := outline_len[i] if i >= 0 else 0.0
		var ground := top_height(q.x, q.y, u, ins)
		var h := r.randf_range(4.5, 15.0) if near else r.randf_range(5.0, 19.0)
		var top := minf(ground + h, -4.5)
		if top - ground < 3.5:
			continue
		var tr := r.randf_range(3.0, 6.5) if near else r.randf_range(4.0, 9.0)
		out.append([q, top, ground - 4.0, tr, r.randf_range(2.0, 4.5), r.randf_range(9.0, 18.0), r.randf_range(0.8, 2.4), Vector2.ZERO, _crown(r)])
		if r.randf() < 0.45:      # a satellite knob leaning against it
			var a := r.randf_range(0.0, TAU)
			var sq := q + Vector2(cos(a), sin(a)) * tr * r.randf_range(1.1, 1.7)
			var sh := (top - ground) * r.randf_range(0.35, 0.7)
			var sins := inside_face(sq.x, sq.y)
			var sk := _crown(r)
			if sins > 8.0:
				var sg := top_height(sq.x, sq.y, u, sins)
				out.append([sq, sg + sh, sg - 4.0, tr * r.randf_range(0.4, 0.65), 2.0, 10.0, 1.0, Vector2.ZERO, sk])
	return out

## A free-standing rock column: a lumpy crown on top of rings running down to bottom_y. The axis wanders (`lean` m),
## the section is lobed, the girth swells and narrows with height and flares with depth (towards top_r + flare over
## ~flare_len m), so a pinnacle rises like a spire out of a broad buttress. The flare grows towards `back` (the
## wall): the column's open-water side stays near its top radius while its back merges into the face below.
## `crown` (see _crown) shapes the top: dome height, a slanted top, an oval section, lobing.
## Returns [verts, cavity, ncol, nrows, u per column, top rows].
func _column(c: Vector2, top_y: float, bottom_y: float, top_r: float, flare: float, flare_len: float, lean: float,
		back: Vector2, seed_off: float, crown: Array) -> Array:
	var nseg := (28 if top_r < 3.0 else 40) if top_y - bottom_y < 60.0 else 72
	var rows: Array = []      # [y, radius scale, dome blend (1 = top)]
	var dome_h := top_r * float(crown[0])
	var tilt: float = crown[1]
	var lobe_k: float = crown[5]
	var nd := 6
	for k in range(nd + 1):
		var a := PI * 0.5 * k / nd
		rows.append([top_y - dome_h * (1.0 - cos(a)), sin(a), 1.0 - float(k) / nd])     # k = 0: closed apex
	var y := top_y - dome_h
	while y > bottom_y:
		y -= clampf(1.5 + (top_y - dome_h - y) * 0.05, 1.5, 8.0)
		rows.append([maxf(y, bottom_y), 1.0, 0.0])
	var nr := rows.size()
	var verts := PackedVector3Array(); verts.resize(nseg * nr)
	var cav := PackedFloat32Array(); cav.resize(nseg * nr)
	var us := PackedFloat32Array(); us.resize(nseg)
	var circ := TAU * top_r
	for i in nseg:
		var th := TAU * i / nseg
		var dir := Vector3(cos(th), 0.0, -sin(th))     # clockwise from above: grid normals point outwards
		var ell := 1.0 + float(crown[3]) * cos(2.0 * (th - float(crown[4])))
		var tdir := cos(th - float(crown[2]))
		us[i] = seed_off * 7.0 + circ * i / nseg
		for j in nr:
			var row: Array = rows[j]
			var ry: float = row[0]
			var below := maxf(top_y - dome_h - ry, 0.0)
			var grow := flare * (1.0 - exp(-below / flare_len))
			var axis := c + Vector2(big.get_noise_1d(ry * 1.1 + seed_off), big.get_noise_1d(ry * 1.1 + seed_off + 517.0)) * lean * 1.6 + back * grow * 0.85
			var lobe := big.get_noise_3d(dir.x * 30.0 + seed_off, ry * 0.5, dir.z * 30.0)
			# the crown tapers into the shaft (no mushroom cap): girth swells only from ~10 m below the top
			var swell := 1.0 + 0.22 * big.get_noise_1d(ry * 3.0 + seed_off * 2.0) * smoothstep(8.0, 30.0, below)
			var taper := lerpf(0.72, 1.0, smoothstep(0.0, 22.0, below))
			var lk := lerpf(0.3, lobe_k, 1.0 - smoothstep(0.0, 3.0 * top_r, top_y - ry))
			var rad := (top_r * taper * float(row[1]) * swell * (1.0 + lk * lobe) + grow * (1.0 + 0.12 * lobe)) * ell
			var p := Vector3(axis.x, ry, axis.y) + dir * rad
			# a slanted top: one side of the crown stands higher than the other
			p.y += tilt * tdir * rad * (1.0 - smoothstep(0.0, 2.5 * top_r, top_y - ry))
			var q := p + Vector3(seed_off, 0.0, seed_off * 0.5)
			# craggy rock: vertical ribs and grooves, rock masses, patchy shelves, small relief
			var rib := 1.0 - absf(big.get_noise_3d(q.x * 3.2, q.y * 0.45, q.z * 3.2))
			var d := 4.2 * (rib - 0.55) + 3.6 * big.get_noise_3d(q.x * 3.0, q.y * 2.0, q.z * 3.0) + 1.6 * mid.get_noise_3d(q.x, q.y * 1.2, q.z) + 0.45 * fine.get_noise_3d(q.x, q.y, q.z)
			var shelf := smoothstep(0.5, 0.85, 0.5 + 0.5 * ledge_n.get_noise_1d(ry * 4.0 + seed_off))
			d += 2.8 * shelf * smoothstep(-0.2, 0.35, big.get_noise_3d(dir.x * 40.0 + seed_off, ry * 0.8, dir.z * 40.0)) * (1.0 - float(row[2]))
			d *= clampf(rad / 6.0, 0.35, 1.0 + below / 200.0)
			var dome: float = row[2]
			var nrm := (dir * (1.0 - dome) + Vector3.UP * dome * 1.2).normalized()
			verts[i * nr + j] = p + nrm * d
			cav[i * nr + j] = 0.0
	return [verts, cav, nseg, nr, us, nd + 1]

## Grid axis from a to b: `fine_step` inside [fa, fb], growing to `coarse` away from it.
static func _axis(a: float, b: float, fa: float, fb: float, fine_step: float, coarse: float) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	var x := a
	while x < b:
		r.append(x)
		var out := maxf(fa - x, x - fb)
		x += clampf(fine_step + maxf(out, 0.0) * 0.12, fine_step, coarse)
	r.append(b)
	return r

## The reef-top plateau. Must be called after wall_mesh (uses d_top). Vertices in front of the crest are snapped
## onto a line CLIP m behind the face top, so the plateau's edge always lies under the rolled crest.
func plateau_mesh(dress: Array, keep_flat: Vector3) -> ArrayMesh:
	var xs := _axis(-1060.0, -26.0, -180.0, -26.0, 2.5, 24.0)
	var zs := _axis(-500.0, 720.0, -500.0, 180.0, 2.5, 24.0)
	var nx := xs.size()
	var nz := zs.size()
	var verts := PackedVector3Array(); verts.resize(nx * nz)
	var keep := PackedByteArray(); keep.resize(nx * nz)
	var cols_a := PackedColorArray(); cols_a.resize(nx * nz)
	var uvs := PackedVector2Array(); uvs.resize(nx * nz)
	var insv := PackedFloat32Array(); insv.resize(nx * nz)
	for i in nx:
		for j in nz:
			var k := i * nz + j
			var q := Vector2(xs[i], zs[j])
			var ni := nearest(q)
			var ins := 0.0
			if ni < 0:
				ins = 60.0 if Geometry2D.is_point_in_polygon(q, poly) else -60.0
			else:
				ins = -(q - outline_pts[ni]).dot(outline_out[ni]) + d_top[ni]
			if ins < -45.0:
				keep[k] = 0
				continue
			keep[k] = 1
			if ins < CLIP and ni >= 0:
				q -= outline_out[ni] * (CLIP - ins)
				ins = CLIP
			insv[k] = ins
			var u := outline_len[ni] if ni >= 0 else 0.0
			var y := top_height(q.x, q.y, u, ins if ni >= 0 else 200.0)
			y -= 3.5 * (1.0 - smoothstep(CLIP, CLIP + 6.0, ins))       # dips under the crest
			# coral bommies away from the crest (cellular mounds, patchy)
			var cd := clampf((cell.get_noise_2d(q.x, q.y) + 1.0) * 1.4, 0.0, 1.0)
			var patch := smoothstep(-0.1, 0.35, colour_n.get_noise_2d(q.x * 0.35 + 70.0, q.y * 0.35))
			var mound := pow(1.0 - cd, 1.6) * patch * smoothstep(14.0, 30.0, ins)
			y += 3.2 * mound
			# far edges of the grid droop out of sight
			var edge := minf(q.x + 1060.0, 720.0 - q.y)
			y -= 60.0 * (1.0 - smoothstep(0.0, 90.0, edge))
			var fl := Vector2(q.x - keep_flat.x, q.y - keep_flat.z).length()
			y = lerpf(keep_flat.y, y, smoothstep(3.0, 9.0, fl))
			verts[k] = Vector3(q.x, y, q.y)
			var sand := smoothstep(0.1, 0.42, colour_n.get_noise_2d(q.x * 0.6, q.y * 0.6)) * (1.0 - mound * 1.5)
			sand = clampf(sand * smoothstep(12.0, 24.0, ins) + (1.0 - smoothstep(3.0, 9.0, fl)), 0.0, 1.0)
			var c := rock_colour(q.x * 1.3 + q.y, q.y).lerp(Palette.SAND * 0.92, sand).srgb_to_linear()
			c.a = lerpf(0.85, 1.0, mound)
			cols_a[k] = c
			uvs[k] = Vector2((1.0 - sand) * clampf(0.75 + 0.5 * mound, 0.0, 1.0), clampf(0.5 + 0.8 * colour_n.get_noise_2d(q.x * 0.25 + 300.0, q.y * 0.25), 0.0, 1.0))
	var idx := PackedInt32Array()
	var norms := PackedVector3Array(); norms.resize(verts.size())
	for i in nx - 1:
		for j in nz - 1:
			var k := i * nz + j
			if keep[k] == 0 or keep[k + nz] == 0 or keep[k + 1] == 0 or keep[k + nz + 1] == 0:
				continue
			idx.append_array([k, k + nz, k + 1, k + 1, k + nz, k + nz + 1])
			var n1 := (verts[k + 1] - verts[k]).cross(verts[k + nz] - verts[k])
			var n2 := (verts[k + nz + 1] - verts[k + 1]).cross(verts[k + nz] - verts[k + 1])
			norms[k] += n1; norms[k + nz] += n1 + n2; norms[k + 1] += n1 + n2; norms[k + nz + 1] += n2
	for k in norms.size():
		var n := norms[k]
		norms[k] = n.normalized() if n.length_squared() > 1e-10 else Vector3.UP
		if n.y < 0.0:
			norms[k] = -norms[k]
		var c := cols_a[k]
		c.a *= lerpf(0.8, 1.0, norms[k].y)
		cols_a[k] = c
		if keep[k] == 1 and insv[k] > 7.0 and uvs[k].x > 0.35 and verts[k].z > -470.0 and verts[k].z < 260.0 \
				and verts[k].x > -260.0 and rng.randf() < 0.18:
			dress.append([verts[k], norms[k], -verts[k].y, 2, 0.0])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_NORMAL] = norms; arr[Mesh.ARRAY_COLOR] = cols_a
	arr[Mesh.ARRAY_TEX_UV] = uvs; arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
