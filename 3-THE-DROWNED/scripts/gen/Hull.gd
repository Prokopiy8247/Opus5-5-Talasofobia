class_name Hull
extends RefCounted
## Parametric ships (procedural colossi toolkit). Geometry is built in a ship frame: bow toward +X, keel
## bottom at y = 0, beam along Z (+Z = starboard), length centred on x = 0. UV in metres as hull.gdshader
## expects (UV.x along the length, UV.y height above the keel); vertex COLOR.g = 1 where portholes may be.
## ship() returns a Node3D whose bow points to its local -Z (rotation.y = yaw aims the bow), +X starboard,
## origin at the keel bottom mid-length. Metadata (node frame): length, beam, depth, hawse, tops, tris.

const KINDS := {
	# b, d: beam and depth as fractions of the length; sheer as a fraction of the depth
	"rowboat": {"b": 0.34, "d": 0.15, "taper": 0.45, "rake": 0.35, "stern": "transom", "dead": 0.45, "sheer": 0.35},
	"motorboat": {"b": 0.33, "d": 0.2, "taper": 0.45, "rake": 0.9, "stern": "transom", "dead": 0.35, "sheer": 0.25},
	"small": {"b": 0.25, "d": 0.13, "taper": 0.38, "rake": 0.5, "stern": "round", "dead": 0.08, "sheer": 0.18},
	"trawler": {"b": 0.22, "d": 0.115, "taper": 0.42, "rake": 0.45, "stern": "transom", "dead": 0.06, "sheer": 0.45},
	"cargo": {"b": 0.15, "d": 0.085, "taper": 0.3, "rake": 0.45, "stern": "transom", "dead": 0.0, "sheer": 0.2},
	"tanker": {"b": 0.165, "d": 0.088, "taper": 0.22, "rake": 0.3, "stern": "transom", "dead": 0.0, "sheer": 0.1},
	"liner": {"b": 0.117, "d": 0.075, "taper": 0.3, "rake": 0.65, "stern": "round", "dead": 0.0, "sheer": 0.12},
}
# rust, moss, hull tint, superstructure tint, amber fraction (superstructure windows only), old load line (fraction of the depth)
const LOOK := {
	"small": [0.7, 0.55, Vector3(1.1, 1.0, 0.95), Vector3(2.6, 2.7, 2.5), 0.0, 0.55],
	"trawler": [0.75, 0.5, Vector3(1.2, 1.0, 0.9), Vector3(2.6, 2.8, 2.6), 0.0, 0.55],
	"cargo": [0.65, 0.45, Vector3(1.25, 1.0, 0.9), Vector3(3.0, 3.1, 2.9), 0.006, 0.6],
	"tanker": [0.6, 0.4, Vector3(1.05, 1.0, 0.95), Vector3(3.4, 3.5, 3.2), 0.012, 0.62],
	"liner": [0.5, 0.45, Vector3(0.85, 0.9, 0.9), Vector3(4.6, 4.8, 4.3), 0.045, 0.55],
}
const RAIL_R := 0.03                    # railing tube radius (m): the same on every ship, a scale cue
# the liner's distance fog floor (hull.gdshader fog_floor): from far off its tiers stood out of the fog band
const LINER_FOG_FLOOR := Vector2(215.0, 320.0)

static var _pmat: ShaderMaterial


## Hull loft: keyframed sections (flat bottom + bilge radius, vertical sides, flared raked bow, transom or
## round stern), open top closed by a cambered deck with bulwarks (or an inner skin when opts.open).
## opts: stern, sheer (m), bulwark (m), dead (deadrise), open, zone (portholes), stations, thick, bilge.
static func hull(length: float, beam: float, depth: float, taper := 0.3, rake := 0.5, opts := {},
		mb: MeshBuilder = null) -> MeshBuilder:
	if mb == null:
		mb = MeshBuilder.new()
	var hb := beam * 0.5
	var stern: String = opts.get("stern", "transom")
	var sheer: float = opts.get("sheer", depth * 0.1)
	var bw: float = opts.get("bulwark", clampf(depth * 0.08, 0.06, 1.6))
	var dead: float = opts.get("dead", 0.0)
	var open: bool = opts.get("open", false)
	var zone: bool = opts.get("zone", false)
	var ns: int = opts.get("stations", 44)
	var th: float = opts.get("thick", clampf(beam * 0.008, 0.04, 0.5))
	var rb0: float = opts.get("bilge", minf(beam, depth) * 0.22)
	var run: float = opts.get("run", 0.42)                # transom: rise of the run (fraction of the depth)
	var run_exp: float = opts.get("run_exp", 1.7)
	var st: float = opts.get("run_len", 0.12) if stern == "transom" else 0.17
	var outer := []
	var inner := []
	var deck := []
	var strips := [[], [], [], []]
	var us := PackedFloat32Array()
	for i in ns:
		var u := 0.5 - 0.5 * cos(PI * float(i) / float(ns - 1))
		var tb := clampf((u - 1.0 + taper) / taper, 0.0, 1.0)
		var ts := clampf((st - u) / st, 0.0, 1.0)
		var lo := 1.0 - pow(tb, 1.5)
		var hi := 1.0 - pow(tb, 2.6)
		var yk := depth * 0.42 * pow(tb, 3.0)
		var over := 0.0
		if stern == "transom":
			lo *= 1.0 - 0.35 * ts * ts
			hi *= 1.0 - 0.12 * ts * ts
			yk += depth * run * pow(ts, run_exp)
		else:
			lo *= sqrt(maxf(1.0 - ts * ts, 0.0))
			hi *= sqrt(maxf(1.0 - pow(ts, 2.6), 0.0))
			yk += depth * 0.55 * pow(ts, 1.3)
			over = ts * ts * 0.5
		var yd := depth + sheer * tb * tb + sheer * 0.3 * ts * ts
		var ytop := yd + bw
		var wl := maxf(lo * hb, 0.01)
		var wh := maxf(hi * hb, 0.012)
		var wi := maxf(wh - th, 0.0)
		var x0 := -length * 0.5 + u * length
		var kr := rake * tb * tb
		var xt := x0 + (kr - over) * bw
		us.append(x0)
		outer.append(_ring(_section(wl, wh, yk, yd, ytop, rb0, dead), x0, yd, kr, over, false))
		if open:
			inner.append(_ring(_section(maxf(wl - th, 0.005), maxf(wi, 0.006), yk + th, yd, ytop, rb0 - th, dead),
				x0, yd, kr, over, true))
		else:
			var dr := PackedVector3Array()
			for q in 5:
				var z := wi * (1.0 - 0.5 * float(q))
				dr.append(Vector3(x0, yd + beam * 0.008 * (1.0 - pow(z / hb, 2.0)), z))
			deck.append(dr)
			strips[0].append(PackedVector3Array([Vector3(xt, ytop, wi), Vector3(x0, yd, wi)]))
			strips[1].append(PackedVector3Array([Vector3(x0, yd, -wi), Vector3(xt, ytop, -wi)]))
		strips[2].append(PackedVector3Array([Vector3(xt, ytop, wh), Vector3(xt, ytop, wi)]))
		strips[3].append(PackedVector3Array([Vector3(xt, ytop, -wi), Vector3(xt, ytop, -wh)]))
	var vv := PackedFloat32Array()
	var r0: PackedVector3Array = outer[0]
	vv.resize(r0.size())
	var b0 := mb.v.size()
	mb.grid(outer, us, vv, false, true)
	if stern == "transom":
		mb.cap(outer[0], Vector3.LEFT)
	else:
		_close_end(mb, outer[0], Vector3.LEFT)
	_close_end(mb, outer[outer.size() - 1], Vector3.RIGHT)
	_paint(mb, b0, length, depth, 0, zone)
	# UV.y across the flat bottom is girth below the bilge (negative at the keel), not the constant height
	# of the keel: the bottom plating gets lengthwise strakes and seams (UV only, the shell is unchanged)
	var np := r0.size()
	var kc := np / 2
	for i in outer.size():
		var qk := b0 + i * np + kc
		var qs := qk + 1
		if absf(mb.n[qk].x) <= 0.8 and absf(mb.n[qs].x) <= 0.8:
			mb.uv[qk].y = mb.uv[qs].y - mb.v[qk].distance_to(mb.v[qs])
	b0 = mb.v.size()
	if open:
		mb.grid(inner, us, vv, false, false)
		if stern == "transom":
			mb.cap(inner[0], Vector3.RIGHT)
	else:
		mb.grid(deck, us, PackedFloat32Array([0, 0, 0, 0, 0]), false, false)
	for k in 4:
		if not (open and k < 2):
			mb.grid(strips[k], us, PackedFloat32Array([0, 0]), false, false)
	_paint(mb, b0, length, depth, 1, false)
	return mb


## Welds the two halves of an end ring together (the stem, a round stern): the loft keeps them a couple of
## centimetres apart there, a slit that showed the water through the ship as a dashed line down its centre.
static func _close_end(mb: MeshBuilder, ring: PackedVector3Array, nrm: Vector3) -> void:
	var kc := ring.size() / 2
	for j in kc:
		var a := mb.vert(ring[kc - j], nrm)
		var b := mb.vert(ring[kc - j - 1], nrm)
		var c := mb.vert(ring[kc + j + 1], nrm)
		mb.tri(a, b, c)
		if j > 0:
			mb.tri(a, c, mb.vert(ring[kc + j], nrm))


## Half section (z >= 0) from the keel centre round the bilge and up the side to the bulwark top.
static func _section(wl: float, wh: float, yk: float, yd: float, ytop: float, rb0: float, dead: float) -> PackedVector2Array:
	var h := PackedVector2Array()
	var rb := clampf(minf(rb0, wl * 0.9), 0.002, maxf((yd - yk) * 0.4, 0.002))
	var zf := maxf(wl - rb, 0.0)
	var yb := minf(yk + dead * zf, yd - rb - 0.01)
	h.append(Vector2(0.0, yk))
	h.append(Vector2(zf, yb))
	for k in range(1, 5):
		var a := -PI * 0.5 + PI * 0.125 * float(k)
		h.append(Vector2(zf + cos(a) * rb, yb + rb + sin(a) * rb))
	var ys := yb + rb
	for k in range(1, 6):
		var y := lerpf(ys, ytop, float(k) / 5.0)
		var s := clampf((y - ys) / maxf(yd - ys, 0.01), 0.0, 1.0)
		h.append(Vector2(lerpf(wl, wh, pow(s, 1.6)), y))
	return h


## Full ring (starboard top -> keel -> port top, or reversed for the inner skin) with rake / overhang.
static func _ring(h: PackedVector2Array, x0: float, yd: float, kr: float, over: float, rev: bool) -> PackedVector3Array:
	var r := PackedVector3Array()
	var sg := -1.0 if rev else 1.0
	for j in range(h.size() - 1, 0, -1):
		r.append(Vector3(x0 + (over - kr) * (yd - h[j].y), h[j].y, -sg * h[j].x))
	for j in h.size():
		r.append(Vector3(x0 + (over - kr) * (yd - h[j].y), h[j].y, sg * h[j].x))
	return r


static func _paint(mb: MeshBuilder, from: int, L: float, D: float, mode: int, zone: bool) -> void:
	for q in range(from, mb.v.size()):
		var p := mb.v[q]
		var u := p.x / L + 0.5
		if mode == 1:
			mb.uv[q] = Vector2(p.x + L * 0.5, p.y + absf(p.z))
			mb.col[q] = Color(0.8, 0.0, 0.5, 0.8)
		elif absf(mb.n[q].x) > 0.8:
			mb.uv[q] = Vector2(p.z + L, p.y)
			mb.col[q] = Color(0.8, 0.0, 0.5, 0.4)
		else:
			mb.uv[q] = Vector2(p.x + L * 0.5, p.y)
			var g := 1.0 if zone and p.y > D * 0.25 and p.y < D * 1.02 and u > 0.06 and u < 0.92 else 0.0
			mb.col[q] = Color(lerpf(0.45, 1.0, clampf(p.y / (D * 0.75), 0.0, 1.0)), g, clampf(0.9 - p.y / D, 0.2, 0.8), 0.35)


## Rounded block (deckhouse tier) on y = c.y, plan lx * wz centred at c, corner radii as fractions of the
## half width (front rf, back rbk). UV.y = y - y_ref so window rows line up across tiers. caps: 1 top, 2 bottom.
static func block(mb: MeshBuilder, c: Vector3, lx: float, wz: float, h: float, rf := 0.4, rbk := 0.15,
		y_ref := 0.0, zone := true, caps := 1, n := 3) -> void:
	var hx := lx * 0.5
	var hz := wz * 0.5
	var r0 := PackedVector3Array()
	var r1 := PackedVector3Array()
	var per := PackedFloat32Array()
	var acc := 0.0
	var cs := [Vector4(-1, -1, rbk, 1.0), Vector4(1, -1, rf, 1.5), Vector4(1, 1, rf, 0.0), Vector4(-1, 1, rbk, 0.5)]
	for cc: Vector4 in cs:
		var r := clampf(cc.z * hz, 0.03, minf(hx, hz) * 0.98)
		for k in n + 1:
			var a := PI * cc.w + PI * 0.5 * float(k) / float(n)
			var p := Vector3(c.x + (hx - r) * cc.x + cos(a) * r, c.y, c.z + (hz - r) * cc.y + sin(a) * r)
			if not r0.is_empty():
				acc += p.distance_to(r0[r0.size() - 1])
			per.append(acc)
			r0.append(p)
			r1.append(p + Vector3(0, h, 0))
	var b0 := mb.v.size()
	mb.grid([r0, r1], PackedFloat32Array([0.0, h]), per, true, true)
	for q in range(b0, mb.v.size()):
		var lowv := mb.v[q].y - c.y < h * 0.5
		mb.uv[q] = Vector2(mb.uv[q].y, mb.v[q].y - y_ref)     # grid's v is the perimeter (seam column included)
		mb.col[q] = Color(0.7 if lowv else 1.0, 1.0 if zone else 0.0, 0.5, 0.4)
	mb.color = Color(0.95, 0.0, 0.4, 0.8)
	if caps & 1:
		mb.cap(r1, Vector3.UP)
	if caps & 2:
		mb.cap(r0, Vector3.DOWN)


## Stacked tiers stepping back (front step_f, back step_b per tier) with thin overhanging deck slabs.
## Returns the height of the top. rails (with rng): railings along both sides of every tier roof. gap (a wreck,
## gap.x < gap.y, with pm): the top tiers are broken over that x range and crushed into it (_collapse).
static func stack(mb: MeshBuilder, xb: float, xf: float, width: float, y0: float, n: int, dh: float,
		step_f: float, step_b: float, narrow: float, rf: float, slabs := true, rails: MeshBuilder = null,
		rng: RandomNumberGenerator = null, gap := Vector2.ZERO, pm: MeshBuilder = null) -> float:
	var y := y0
	var nb := (2 if n >= 4 else 1) if gap.y > gap.x else 0
	for t in n:
		var a := xb + step_b * t
		var b := xf - step_f * t
		var w := width * (1.0 - narrow * t)
		var last := t == n - 1
		var spans := [Vector2(a, b)]
		if t >= n - nb:
			spans = [Vector2(a, gap.x), Vector2(gap.y, b)]
		for si in spans.size():
			var sp: Vector2 = spans[si]
			if sp.y - sp.x < dh:
				continue
			if si == 1:
				# the part ahead of the break has settled on its buckled frames
				mb.xf = _about(Vector3(sp.x, y0 + float(n - nb) * dh, 0.0),
					Basis(Vector3.BACK, deg_to_rad(-2.5)) * Basis(Vector3.RIGHT, deg_to_rad(2.0)))
			var cx := (sp.x + sp.y) * 0.5
			block(mb, Vector3(cx, y, 0.0), sp.y - sp.x, w, dh, rf, rf * 0.3, y0, true, 1 if (last or not slabs) else 0)
			var edge := w * 0.5
			var yr := y + dh
			if slabs and not last:
				block(mb, Vector3(cx + dh * 0.1, y + dh * 0.9, 0.0), sp.y - sp.x + dh * 0.5, w + dh * 0.4, dh * 0.12,
					rf, rf * 0.3, y0, false, 3)
				edge += dh * 0.2
				yr = y + dh * 1.02
			if rails != null and rng != null:
				# along the straight sides, clear of the rounded ends
				var x0 := sp.x + rf * 0.3 * w * 0.5 + 0.5
				var x1 := sp.y - rf * w * 0.5 - 0.5
				if x1 > x0 + 2.0:
					for sd: float in [-1.0, 1.0]:
						_railing(rails, PackedVector3Array([Vector3(x0, yr, sd * (edge - 0.08)), Vector3(x1, yr, sd * (edge - 0.08))]),
							1.0, rng, 1.0 if nb > 0 else 0.0, mb.xf)
			mb.xf = Transform3D.IDENTITY
		y += dh
	if nb > 0 and pm != null and rng != null:
		_collapse(mb, pm, gap, y0 + float(n - nb) * dh, width * (1.0 - narrow * float(n - nb)), dh, rf, y0, rng)
	return y


## Elliptic raked funnel with a dark top band; returns the top centre.
static func funnel(mb: MeshBuilder, base: Vector3, h: float, rx: float, rz: float, rake := 0.12, seg := 14) -> Vector3:
	var rings := []
	var cols := []
	var uu := PackedFloat32Array()
	var vv := PackedFloat32Array()
	for t: float in [0.0, 0.35, 0.7, 0.86, 0.88, 1.0]:
		var s := lerpf(1.0, 0.9, t)
		var c := base + Vector3(-rake * h * t, h * t, 0.0)
		var ring := PackedVector3Array()
		for j in seg:
			var a := TAU * float(j) / float(seg)
			ring.append(c + Vector3(cos(a) * rx * s, 0.0, sin(a) * rz * s))
		rings.append(ring)
		cols.append(Color(0.9 if t < 0.87 else 0.22, 0.0, 0.6, 0.3))
		uu.append(h * t)
	for j in seg:
		vv.append(TAU * float(j) / float(seg) * (rx + rz) * 0.5)
	var b0 := mb.v.size()
	mb.grid(rings, uu, vv, true, true, cols)
	for q in range(b0, mb.v.size()):
		mb.uv[q] = Vector2(mb.uv[q].y, mb.uv[q].x)
	mb.color = Color(0.03, 0.0, 0.5, 0.0)
	mb.cap(rings[rings.size() - 1], Vector3.UP)
	return base + Vector3(-rake * h, h, 0.0)


static func mast(mb: MeshBuilder, base: Vector3, h: float, r: float) -> Vector3:
	mb.cylinder(base, base + Vector3(0, h, 0), r, r * 0.6, 8, true)
	return base + Vector3(0, h, 0)


## Rigging line with a parabolic sag (Rope.tube).
static func rig(mb: MeshBuilder, a: Vector3, b: Vector3, sag: float, radius: float, n := 10) -> void:
	var pts := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / float(n)
		pts.append(a.lerp(b, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0))
	Rope.tube(pts, radius, 5, mb)


## Pilot ladder on the hull side at z (sign = side), from y0 to y1.
static func ladder(mb: MeshBuilder, x: float, z: float, y0: float, y1: float) -> void:
	var s := signf(z)
	for dx: float in [-0.28, 0.28]:
		mb.box(Vector3(x + dx, (y0 + y1) * 0.5, z + s * 0.1), Vector3(0.09, y1 - y0, 0.09))
	var y := y0 + 0.2
	while y < y1:
		mb.box(Vector3(x, y, z + s * 0.16), Vector3(0.56, 0.08, 0.08))
		y += 0.36


static func _deck_y(x: float, L: float, D: float, k: Dictionary) -> float:
	var u := x / L + 0.5
	var taper: float = k["taper"]
	var tb := clampf((u - 1.0 + taper) / taper, 0.0, 1.0)
	var st := 0.12 if k["stern"] == "transom" else 0.17
	var ts := clampf((st - u) / st, 0.0, 1.0)
	var sh: float = D * float(k["sheer"])
	return D + sh * tb * tb + sh * 0.3 * ts * ts


static func _parts() -> ShaderMaterial:
	if _pmat == null:
		_pmat = Mats.solid(Palette.STEEL_DARK, 0.6, 0.35)
	return _pmat


static func _r(p: Vector3) -> Vector3:   # ship frame -> node frame (bow +X -> -Z)
	return Vector3(p.z, p.y, -p.x)


## Station shape of the loft at fraction u (0 stern .. 1 bow); mirrors hull() exactly (keep them in sync).
static func _station(L: float, B: float, D: float, taper: float, rake: float, ho: Dictionary, u: float) -> Dictionary:
	var hb := B * 0.5
	var stern: String = ho.get("stern", "transom")
	var sheer: float = ho.get("sheer", D * 0.1)
	var dead: float = ho.get("dead", 0.0)
	var rb0: float = ho.get("bilge", minf(B, D) * 0.22)
	var st: float = ho.get("run_len", 0.12) if stern == "transom" else 0.17
	var tb := clampf((u - 1.0 + taper) / taper, 0.0, 1.0)
	var ts := clampf((st - u) / st, 0.0, 1.0)
	var lo := 1.0 - pow(tb, 1.5)
	var hi := 1.0 - pow(tb, 2.6)
	var yk := D * 0.42 * pow(tb, 3.0)
	var over := 0.0
	if stern == "transom":
		lo *= 1.0 - 0.35 * ts * ts
		hi *= 1.0 - 0.12 * ts * ts
		yk += D * float(ho.get("run", 0.42)) * pow(ts, float(ho.get("run_exp", 1.7)))
	else:
		lo *= sqrt(maxf(1.0 - ts * ts, 0.0))
		hi *= sqrt(maxf(1.0 - pow(ts, 2.6), 0.0))
		yk += D * 0.55 * pow(ts, 1.3)
		over = ts * ts * 0.5
	var yd := D + sheer * tb * tb + sheer * 0.3 * ts * ts
	var wl := maxf(lo * hb, 0.01)
	var wh := maxf(hi * hb, 0.012)
	var rb := clampf(minf(rb0, wl * 0.9), 0.002, maxf((yd - yk) * 0.4, 0.002))
	var zf := maxf(wl - rb, 0.0)
	var yb := minf(yk + dead * zf, yd - rb - 0.01)
	return {"x0": -L * 0.5 + u * L, "wl": wl, "wh": wh, "yk": yk, "yd": yd, "sk": over - rake * tb * tb,
		"rb": rb, "zf": zf, "yb": yb, "ys": yb + rb}


## Starboard shell point of a station at height y (on the side, above the bilge).
static func _shell(s: Dictionary, y: float) -> Vector3:
	var ys: float = s["ys"]
	var yd: float = s["yd"]
	var t := clampf((y - ys) / maxf(yd - ys, 0.01), 0.0, 1.0)
	var z := lerpf(s["wl"], s["wh"], pow(t, 1.6))
	return Vector3(float(s["x0"]) + float(s["sk"]) * (yd - y), y, z)


## Lowest point of the hull on the centre line at ship-frame x (1e9 where no hull is above).
static func _bottom(L: float, B: float, D: float, k: Dictionary, ho: Dictionary, x: float) -> float:
	var prev := _station(L, B, D, k["taper"], k["rake"], ho, 0.0)
	var xk0: float = float(prev["x0"]) + float(prev["sk"]) * (float(prev["yd"]) - float(prev["yk"]))
	if x < xk0:
		# aft of the keel's end: under the stern profile (raked counter) or open water
		var x0: float = prev["x0"]
		if x < x0 or float(prev["sk"]) <= 1e-4:
			return 1e9
		return float(prev["yd"]) - (x - x0) / float(prev["sk"])
	var xp := xk0
	var yp: float = prev["yk"]
	for i in range(1, 161):
		var s := _station(L, B, D, k["taper"], k["rake"], ho, float(i) / 160.0 * 0.6)
		var xk: float = float(s["x0"]) + float(s["sk"]) * (float(s["yd"]) - float(s["yk"]))
		if xk >= x:
			return lerpf(yp, s["yk"], clampf((x - xp) / maxf(xk - xp, 1e-4), 0.0, 1.0))
		xp = xk
		yp = s["yk"]
	return yp


## Stern and bow fittings that sell the size: rudder, propeller(s) on shafts with bossings or A-brackets,
## bilge keels, hawse pipes with a stowed stockless anchor. Fills hawse / hawse_out (ship frame).
static func _fittings(kind: String, L: float, B: float, D: float, k: Dictionary, ho: Dictionary, pm: MeshBuilder,
		bz: MeshBuilder, rng: RandomNumberGenerator, stow: Array, hawse: Array, hawse_out: Array) -> void:
	var twin := kind == "liner"
	var R := clampf(L * (0.011 if twin else 0.017), 0.35, 7.0)
	R = minf(R, D * 0.22)
	var yp := R + D * 0.05
	var need := yp + R * 0.92
	# the propeller sits as far forward under the run as its tip clears the hull
	var xp := -L * 0.5
	var x := -L * 0.5
	while x < -L * 0.2:
		if _bottom(L, B, D, k, ho, x) < need:
			break
		xp = x
		x += L * 0.0025
	var chord := maxf(L * (0.02 if twin else 0.026), 0.35)
	var xr := xp - R * 0.8 - chord * 0.5
	var xr_min := -L * 0.5 + chord * 0.4
	if xr < xr_min:
		xp += xr_min - xr
		xr = xr_min
	var rt := minf(_bottom(L, B, D, k, ho, xr), D * 0.75) + D * 0.04
	var rb := D * 0.03
	var thick := clampf(L * 0.004, 0.06, 1.6)
	pm.color = Color(0.8, 0.0, 0.7, 0.3)
	# jammed hard over (a wreck's rudder rarely sits amidships): from astern it shows its blade, not an edge
	pm.xf = _about(Vector3(xr + chord * 0.22, 0.0, 0.0), Basis(Vector3.UP, deg_to_rad(26.0 if int(L) % 2 == 0 else -26.0)))
	_rudder(pm, xr, rb, rt, chord)
	pm.xf = Transform3D.IDENTITY
	# the stock: up out of the blade's head into the counter, so the blade visibly hangs from the hull
	pm.cylinder(Vector3(xr + chord * 0.22, rt - D * 0.08, 0.0), Vector3(xr + chord * 0.22, rt + D * 0.08, 0.0),
		chord * 0.09, chord * 0.09, 10, false)
	var props := [Vector3(xp, yp, 0.0)]
	if twin:
		var Rw := clampf(L * 0.0115, 0.35, 7.5)
		var ypw := Rw + D * 0.05
		var xw := xp
		x = xp
		while x < -L * 0.2:
			if _bottom(L, B, D, k, ho, x) < ypw + Rw * 0.92:
				break
			xw = x
			x += L * 0.0025
		xw += Rw * 0.6
		for sd: float in [-1.0, 1.0]:
			props.append(Vector3(xw, ypw, sd * B * 0.2))
	for pi in props.size():
		var p: Vector3 = props[pi]
		var r := R if pi == 0 else clampf(L * 0.0115, 0.35, 7.5)
		var blades := 4 if L < 200.0 else (5 if kind == "tanker" else 4)
		var bent := rng.randf_range(0.0, 0.35) if L > 60.0 else 0.0
		_propeller(bz, Transform3D(Basis(Vector3.RIGHT, rng.randf() * TAU), p), r * 2.0, blades, bent)
		# shaft out of the hull (bossing) and, off the centre line, an A-bracket
		var hub := p + Vector3(r * 0.25, 0.0, 0.0)
		var xe := p.x + r * (2.2 if pi == 0 else 5.0)
		var ye := minf(_bottom(L, B, D, k, ho, xe), D * 0.8) + r * 0.25
		pm.cylinder(hub, Vector3(xe, ye, p.z * 0.9), r * 0.11, r * 0.2, 10, false)
		if pi > 0:
			var yb := minf(_bottom(L, B, D, k, ho, p.x + r * 0.3), D * 0.8) + r * 0.2
			for dz: float in [-0.35, 0.35]:
				pm.cylinder(hub + Vector3(0.0, 0.0, dz * r * 0.2), Vector3(p.x + r * 0.3, yb, p.z * (0.75 + dz * 0.3)), r * 0.05, r * 0.05, 6, false)
	# a skeg ahead of the centre propeller ties the shaft to the keel line
	var xs1 := xp + R * 3.2
	var ys1 := minf(_bottom(L, B, D, k, ho, xs1), D * 0.6)
	if ys1 > D * 0.04:
		var xs0 := xp + R * 0.5
		var ys0 := minf(_bottom(L, B, D, k, ho, xs0), D * 0.75)
		pm.box(Vector3((xs0 + xs1) * 0.5, (yp - R * 0.15 + ys0) * 0.5, 0.0),
			Vector3(xs1 - xs0, ys0 - yp + R * 0.15, thick * 0.8))
		pm.box(Vector3((xs0 + xs1) * 0.5, (D * 0.02 + ys1) * 0.5, 0.0), Vector3((xs1 - xs0) * 0.6, ys1, thick * 0.6))
	# bilge keels along the midbody
	if L >= 60.0:
		var s := _station(L, B, D, k["taper"], k["rake"], ho, 0.5)
		var rbl: float = s["rb"]
		var zb := float(s["zf"]) + rbl * 0.7071
		var yb2 := float(s["yb"]) + rbl * (1.0 - 0.7071)
		var hk := clampf(B * 0.02, 0.15, 1.2)
		for sd: float in [-1.0, 1.0]:
			# a tapered wedge welded into the bilge, not a razor-thin plate: seen edge-on from far below the
			# plate was sub-pixel and broke into a dashed light line along the bottom
			var nrm := Vector3(0.0, -0.7071, 0.7071 * sd)
			var tg := Vector3(0.0, 0.7071, 0.7071 * sd)
			var root := Vector3(0.0, yb2, zb * sd) - nrm * hk * 0.15
			var rings := []
			var uu := PackedFloat32Array()
			for i in 9:
				var t := float(i) / 8.0
				var e := clampf(minf(t, 1.0 - t) / 0.12, 0.15, 1.0)
				var c := root + Vector3(L * 0.34 * (t - 0.5), 0.0, 0.0)
				var tip := c + nrm * hk * (0.15 + 1.0 * e)
				rings.append(PackedVector3Array([c - tg * hk * 0.28, c + tg * hk * 0.28, tip + tg * hk * 0.07,
					tip - tg * hk * 0.07]))
				uu.append(L * 0.34 * t)
			pm.color = Color(0.75, 0.0, 0.6, 0.3)
			pm.grid(rings, uu, PackedFloat32Array([0.0, hk * 0.5, hk * 1.6, hk * 2.1]), true, true)
			pm.cap(rings[0], Vector3.LEFT)
			pm.cap(rings[8], Vector3.RIGHT)
	# hawse pipes at the bow (anchors), and on the liner a pair near the stern (mooring chains)
	var hr := clampf(L * 0.0055, 0.12, 3.4)
	for side in (4 if kind == "liner" else 2):
		var uh := (0.955 if kind != "small" else 0.94) if side < 2 else 0.075
		var stn := _station(L, B, D, k["taper"], k["rake"], ho, uh)
		var yh := float(stn["yd"]) * (0.84 if side < 2 else 0.78)
		var sg := 1.0 if side % 2 == 0 else -1.0
		var p0 := _shell(stn, yh)
		var pu := _shell(_station(L, B, D, k["taper"], k["rake"], ho, uh + 0.004), yh)
		var py := _shell(stn, yh + 0.5)
		var nrm := (pu - p0).cross(py - p0).normalized()
		if nrm.z < 0.0:
			nrm = -nrm
		p0.z *= sg
		nrm.z *= sg
		var pd := _shell(stn, yh - 0.5)
		var down := (Vector3(pd.x, pd.y, pd.z * sg) - p0).normalized()
		# the stern pair stays a metadata point only: a dark ring the size of a house on the round stern read
		# as an eye from below (the liner's stern shows no mooring pipe)
		if side < 2:
			pm.color = Color(0.85, 0.0, 0.6, 0.3)
			pm.torus(p0 + nrm * hr * 0.12, nrm, hr * 1.12, hr * 0.22, 14, 6)
			pm.color = Color(0.04, 0.0, 0.5, 0.3)
			pm.cylinder(p0 - nrm * hr * 0.6, p0 + nrm * hr * 0.06, hr * 0.98, hr * 0.98, 12, true)
		pm.color = Color(1, 0, 0.5, 0.5)
		hawse.append(p0 + nrm * hr * 0.4)
		hawse_out.append(nrm)
		if side in stow:
			var s_a := clampf(L * 0.012, 0.3, 7.5)
			var ya := down
			var za := nrm
			var xa := ya.cross(za).normalized()
			za = xa.cross(ya).normalized()
			var crown := p0 + ya * s_a * 0.92 + za * s_a * 0.1
			Debris.anchor_stockless(pm, Transform3D(Basis(xa, -ya, za), crown), s_a)


## Rudder blade under the counter: a lofted foil (round leading edge toward the bow, thin trailing edge), thick
## enough (22 % of the chord) to read as a blade, its foot cut back and rounded; xr is the chord centre.
static func _rudder(pm: MeshBuilder, xr: float, rb: float, rt: float, chord: float) -> void:
	var rings := []
	var uu := PackedFloat32Array()
	var n := 7
	for i in n + 1:
		var t := float(i) / float(n)
		var y := lerpf(rb, rt, t)
		# the foot: the trailing edge sweeps up and the chord narrows over the lowest fifth
		var foot := 1.0 - smoothstep(0.0, 0.22, t)
		var c := chord * (1.0 - 0.35 * foot * foot)
		var xl := xr + chord * 0.5                   # leading edge (bow side) stays straight
		var th := c * 0.22
		var ring := PackedVector3Array()
		for j in 12:
			var a := TAU * float(j) / 12.0
			# x from the leading edge (u 0) to the trailing edge (u 1); fattest a quarter chord back
			var u := 0.5 - 0.5 * cos(a)
			var z := signf(sin(a)) * th * 0.5 * 2.6 * sqrt(u) * (1.0 - u) * (1.0 - 0.3 * u)
			ring.append(Vector3(xl - u * c, y, z))
		rings.append(ring)
		uu.append(y)
	var vv := PackedFloat32Array()
	for j in 12:
		vv.append(chord * float(j) / 12.0)
	pm.grid(rings, uu, vv, true, true)
	pm.cap(rings[0], Vector3.DOWN)


## Ship propeller: a hub with a cone and wide skewed blades whose outline runs smoothly to a round tip
## (13 stations, lens sections); bent > 0 curls one blade (a strike). Same frame as Debris.propeller: the shaft
## along X, dia the diameter.
static func _propeller(mb: MeshBuilder, xf: Transform3D, dia: float, blades: int, bent: float) -> void:
	mb.xf = xf
	mb.color = Color(0.9, 0.0, 0.2, 0.5)
	var R := dia * 0.5
	var hr := R * 0.19
	mb.cylinder(Vector3(-hr * 1.3, 0, 0), Vector3(hr * 1.3, 0, 0), hr, hr * 0.88, 16)
	mb.cylinder(Vector3(hr * 1.3, 0, 0), Vector3(hr * 2.3, 0, 0), hr * 0.88, hr * 0.12, 16)
	var ex := Vector3(1, 0, 0)
	for b in blades:
		var a0 := TAU * float(b) / float(blades)
		var er := Vector3(0, cos(a0), sin(a0))
		var et := Vector3(0, -sin(a0), cos(a0))
		var rings := []
		var uu := PackedFloat32Array()
		var n := 12
		for i in n + 1:
			var t := float(i) / float(n)
			var rad := lerpf(hr * 0.85, R, t)
			# outline: from the root, widest at ~0.6 R, then an elliptic run to the tip (no step anywhere)
			var chord := R * 1.05 * sqrt(maxf(1.0 - pow(t, 2.6), 0.0004)) * (0.5 + 0.5 * sin(PI * 0.5 * minf(t / 0.6, 1.0)))
			var skew := R * 0.22 * t * t                   # the blade sweeps back toward its tip
			var pt := lerpf(0.95, 0.42, t)
			var cd := et * cos(pt) + ex * sin(pt)
			var td := -et * sin(pt) + ex * cos(pt)
			var curl := (bent * pow(maxf(t - 0.35, 0.0), 2.0) * R * 2.2) if b == 0 else 0.0
			var c := er * rad + ex * curl - cd * skew
			var thk := R * lerpf(0.055, 0.012, t)
			var ring := PackedVector3Array()
			for j in 8:
				var ang := TAU * float(j) / 8.0
				ring.append(c + cd * cos(ang) * chord * 0.5 + td * sin(ang) * thk)
			rings.append(ring)
			uu.append(rad)
		mb.grid(rings, uu, PackedFloat32Array([0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7]), true, true)
		mb.cap(rings[n], er)
	mb.xf = Transform3D.IDENTITY


## A whole ship: "rowboat", "motorboat", "small", "trawler", "cargo", "tanker", "liner".
## opts: fittings (default true: rudder, propellers, bilge keels, hawse pipes and anchors for L >= 20 m; the
## transom ships also get a deeper run for the propeller), stow (hawse indices with a stowed anchor, default [1] =
## port), shadows (default true), rails (default true for L >= 20 m: human-scale railings, 1 m posts every ~2 m,
## on the deck edge and every tier roof; they stay the same size on every ship, so the big hulls read big),
## wreck (default false: a real wreck ABOVE THE DECK ONLY: the superstructure broken and crushed in its middle,
## the funnel there fallen across it, another leaning, the rest broken short; lifeboats gone, fallen or hanging
## from bent davits; the foremast snapped onto the forecastle; heavier rust, rusticles and dulled paint. The
## "Hull" mesh, the shell and deck below the deck line, is identical with or without it).
## Metadata (node frame): length, beam, depth, hawse (hawse pipes: [0] bow starboard, [1] bow port; the liner adds
## [2] stern starboard, [3] stern port, points on the shell only; without fittings one point on deck), hawse_out
## (their outward normals), tops (mast tops), warp_blocks (trawler gallows blocks), tris.
static func ship(kind: String, length: float, seed: int, opts := {}) -> Node3D:
	var k: Dictionary = KINDS.get(kind, KINDS["cargo"])
	var L := length
	var B := L * float(k["b"])
	var D := L * float(k["d"])
	var sh := D * float(k["sheer"])
	var fit: bool = bool(opts.get("fittings", true)) and L >= 20.0 and kind in ["small", "trawler", "cargo", "tanker", "liner"]
	var wreck: bool = bool(opts.get("wreck", false))
	var rails: bool = bool(opts.get("rails", true)) and L >= 20.0 and kind in ["small", "trawler", "cargo", "tanker", "liner"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# the rails and the damage draw from their own stream: the fittings keep their look with or without them
	var wrng := RandomNumberGenerator.new()
	wrng.seed = seed * 7919 + 13
	var root := Node3D.new()
	root.name = kind.capitalize()
	var geo := Node3D.new()
	geo.name = "Geo"
	geo.rotation.y = PI * 0.5
	root.add_child(geo)
	var hm := MeshBuilder.new()
	var sm := MeshBuilder.new()
	var pm := MeshBuilder.new()
	var rm := MeshBuilder.new()      # rigging and wires (rope shader: 1 px floor, fogs out)
	var bz := MeshBuilder.new()      # bronze propellers
	var rl := MeshBuilder.new()      # railings (rope shader at their own, human-scale radius)
	var rlb: MeshBuilder = rl if rails and L <= 300.0 else null   # tier-roof rails (a colossus: deck edge only)
	var ho := {"stern": k["stern"], "sheer": sh, "dead": k["dead"], "open": kind == "rowboat",
		"zone": kind in ["liner", "trawler", "small"], "stations": clampi(int(L / 5.0) + 26, 30, 96)}
	if fit and k["stern"] == "transom":
		ho["run"] = 0.55
		ho["run_exp"] = 1.3
	hull(L, B, D, k["taper"], k["rake"], ho, hm)
	var dh := clampf(L / 170.0, 2.3, 3.6)
	var rr := clampf(L * 0.001, 0.06, 0.25)
	var tiers := 0
	var tops := []
	var blocks := []
	var ladders := []
	var hawse := []
	var hawse_out := []
	match kind:
		"rowboat":
			hm.color = Color(0.8, 0.0, 0.3, 0.6)
			for f: float in [-0.22, 0.05, 0.28]:
				hm.box(Vector3(L * f, D * 0.62, 0), Vector3(L * 0.05, D * 0.08, B * 0.8))
		"motorboat":
			block(sm, Vector3(L * 0.06, D, 0), L * 0.34, B * 0.72, D * 0.85, 0.7, 0.15, D, false)
			block(sm, Vector3(L * 0.02, D * 1.85, 0), L * 0.2, B * 0.6, D * 0.12, 0.3, 0.2, D, false, 3)
			pm.box(Vector3(-L * 0.52, D * 0.62, 0), Vector3(0.35, D * 0.9, 0.4))
		"small":
			tiers = 2
			var top := stack(sm, -L * 0.1, L * 0.1, B * 0.7, D, 2, dh, 0.6, 0.0, 0.06, 0.4, true, rlb, wrng)
			_funnel_wreck(sm, Vector3(-L * 0.17, D, 0), 3.8, 0.8, 0.6, 0.15, 1 if wreck else 0, wrng)
			var mt := mast(pm, Vector3(L * 0.3, _deck_y(L * 0.3, L, D, k), 0), 7.5, 0.14)
			rig(rm, mt, Vector3(L * 0.5, D + sh, 0), 0.3, rr)
			rig(rm, mt, Vector3(0.0, top, 0), 0.2, rr)
			tops.append(mt)
		"trawler":
			tiers = 2
			var top := stack(sm, L * 0.02, L * 0.22, B * 0.72, D, 2, dh, 0.5, 0.0, 0.05, 0.35, true, rlb, wrng)
			_funnel_wreck(sm, Vector3(-L * 0.03, D, 0), 4.6, 0.85, 0.65, 0.15, 1 if wreck else 0, wrng)
			var mt := mast(pm, Vector3(L * 0.15, top, 0), 7.0, 0.16)
			pm.cylinder(mt + Vector3(0, -1.6, -2.4), mt + Vector3(0, -1.6, 2.4), 0.07, 0.07, 6)
			var gx := -L * 0.45
			var gy := _deck_y(gx, L, D, k)
			var gt := Vector3(gx, gy + 7.0, 0)
			for zz: float in [-B * 0.38, B * 0.38]:
				pm.cylinder(Vector3(gx, gy, zz), Vector3(gx, gy + 7.0, zz * 0.85), 0.22, 0.18, 8)
				# warp block hanging under the gallows head
				pm.sphere(Vector3(gx - 0.2, gy + 6.3, zz * 0.85), 0.32, 8, Vector3(1.0, 1.3, 0.6))
				blocks.append(Vector3(gx - 0.25, gy + 5.9, zz * 0.85))
				var be := Vector3(L * 0.1, D + 7.5, zz * 1.4 + signf(zz) * 4.0)
				pm.cylinder(Vector3(L * 0.1, D + 1.0, zz * 0.9), be, 0.14, 0.1, 6)
				rig(rm, mt, be, 0.3, rr)
			pm.cylinder(Vector3(gx, gy + 7.0, -B * 0.34), Vector3(gx, gy + 7.0, B * 0.34), 0.2, 0.2, 8)
			pm.cylinder(Vector3(-L * 0.28, gy + 1.2, -B * 0.3), Vector3(-L * 0.28, gy + 1.2, B * 0.3), 1.0, 1.0, 14)
			rig(rm, mt, Vector3(L * 0.5, D + sh + 0.8, 0), 0.4, rr)
			rig(rm, mt, gt, 0.6, rr)
			rig(rm, gt, Vector3(-L * 0.28, gy + 2.2, 0), 0.3, rr)
			tops.append(mt)
			tops.append(gt)
		"cargo":
			tiers = 4
			var top := stack(sm, -L * 0.455, -L * 0.345, B * 0.86, D, 4, dh, 0.4, 0.0, 0.02, 0.15, true, rlb, wrng)
			# bridge wings: their roof sits just above the top tier's roof (no coplanar z-fight)
			block(sm, Vector3(-L * 0.36, top - 0.6, 0), dh * 2.0, B * 1.02, 0.68, 0.2, 0.2, D, false, 3)
			_funnel_wreck(sm, Vector3(-L * 0.43, top - 0.3, 0), L * 0.06, L * 0.02, L * 0.015, 0.1, 1 if wreck else 0, wrng)
			hm.color = Color(0.85, 0.0, 0.6, 0.7)
			for hi in 4:
				var hx := lerpf(-L * 0.24, L * 0.33, float(hi) / 3.0)
				hm.box(Vector3(hx, D + 0.9, 0), Vector3(L * 0.1, 1.8, B * 0.62))
				if hi == 3:
					continue
				var kx := hx + L * 0.095
				var kt := []
				for sd: float in [-1.0, 1.0]:
					var bp := Vector3(kx, D, sd * B * 0.3)
					var tp := bp + Vector3(0, L * 0.11, 0)
					pm.cylinder(bp, tp, 0.4, 0.3, 8)
					# the boom stowed low over the hatch ahead, near its crutch (raised booms with taut topping
					# lifts drew a row of wire triangles that read as scaffolding from far below)
					var be := bp + Vector3(L * 0.09, 2.6 + wrng.randf_range(0.0, 1.2), -sd * B * 0.06)
					pm.cylinder(bp + Vector3(0, 2.0, 0), be, 0.25, 0.18, 6)
					if wrng.randf() < 0.5:
						rig(rm, tp, be, L * 0.02, rr)          # a slack topping lift
					kt.append(tp)
				pm.cylinder(kt[0] + Vector3(0, -1.5, 0), kt[1] + Vector3(0, -1.5, 0), 0.25, 0.25, 6)
				tops.append(kt[0])
			var fm := mast(pm, Vector3(L * 0.43, _deck_y(L * 0.43, L, D, k), 0), L * 0.12, 0.35)
			rig(rm, fm, Vector3(L * 0.5, D + sh, 0), 0.6, rr)
			tops.append(fm)
		"tanker":
			tiers = 6
			var top := stack(sm, -L * 0.475, -L * 0.385, B * 0.8, D, 6, dh, 0.6, 0.0, 0.0, 0.12, true, rlb, wrng)
			block(sm, Vector3(-L * 0.4, top - 0.7, 0), dh * 2.2, B * 1.0, 0.78, 0.2, 0.2, D, false, 3)
			_funnel_wreck(sm, Vector3(-L * 0.46, top - 0.5, 0), L * 0.045, L * 0.017, L * 0.012, 0.08, 1 if wreck else 0, wrng)
			for zz: float in [-B * 0.06, 0.0, B * 0.06]:
				pm.cylinder(Vector3(-L * 0.36, D + 1.5, zz), Vector3(L * 0.38, D + 1.5, zz), B * 0.011, B * 0.011, 8, false)
			pm.box(Vector3(0.0, D + 3.2, B * 0.12), Vector3(L * 0.74, 0.4, 2.0))
			for sd: float in [-1.0, 1.0]:
				var cp := Vector3(0.0, D, sd * B * 0.3)
				var ct := mast(pm, cp, 14.0, 0.6)
				var ce := cp + Vector3(10.0, 12.0, -sd * 10.0)
				pm.cylinder(cp + Vector3(0, 3, 0), ce, 0.4, 0.3, 6)
				rig(rm, ct, ce, 0.3, rr)
			var fm := mast(pm, Vector3(L * 0.44, _deck_y(L * 0.44, L, D, k), 0), L * 0.06, 0.6)
			rig(rm, fm, Vector3(L * 0.5, D + sh, 0), 0.6, rr)
			tops.append(fm)
		"liner":
			tiers = clampi(roundi(D * 0.75 / dh), 4, 10)
			var xb := -L * 0.31
			var xf := L * 0.29
			var w0 := B * 0.84
			var nf := 4 if L > 300.0 else 3
			var fxs := []
			for f in nf:
				fxs.append(lerpf(xb + L * 0.12, xf - L * 0.16, float(f) / float(nf - 1)))
			var fbreak := int(nf / 2.0)
			var gap := Vector2.ZERO
			if wreck:
				# the superstructure broke round the middle funnel and its top two tiers fell in
				var gw := (xf - xb) * 0.2
				gap = Vector2(float(fxs[fbreak]) - gw * 0.45, float(fxs[fbreak]) + gw * 0.55)
			var top := stack(sm, xb, xf, w0, D, tiers, dh, L * 0.011, L * 0.005, 0.02, 0.7, true, rlb, wrng, gap, pm)
			var nb := 2 if tiers >= 4 else 1
			var y_gap := D + float(tiers - nb) * dh + dh * 0.02
			for f in nf:
				var fx: float = fxs[f]
				var fh := L * 0.055
				if not wreck:
					funnel(sm, Vector3(fx, top - 0.5, 0), fh, L * 0.0135, L * 0.009, 0.13)
				elif f == fbreak:
					# fallen across the broken decks, its top over the side
					var sd := 1.0 if wrng.randf() < 0.5 else -1.0
					var piv := Vector3(fx + L * 0.004, y_gap + dh * 0.45 + L * 0.0085, -sd * w0 * 0.12)
					sm.xf = _about(piv, Basis(Vector3.RIGHT, sd * deg_to_rad(97.0)) * Basis(Vector3.UP, deg_to_rad(wrng.randf_range(-15.0, 15.0))))
					funnel(sm, piv, fh, L * 0.0135, L * 0.009, 0.13)
					sm.xf = Transform3D.IDENTITY
				else:
					_funnel_wreck(sm, Vector3(fx, top - 0.5, 0), fh, L * 0.0135, L * 0.009, 0.13, 1 if f == 0 else 2, wrng)
			var bl := L * 0.016
			var wt := w0 * (1.0 - 0.02 * float(tiers - 1))
			var x := xb + L * 0.06
			while x < xf - L * 0.12:
				for sd: float in [-1.0, 1.0]:
					var bc := Vector3(x, top - dh + bl * 0.2, sd * (wt * 0.5 + bl * 0.12))
					var d0 := bc + Vector3(0, bl * 0.1, -sd * bl * 0.1)
					var d1 := bc + Vector3(0, bl * 0.4, -sd * bl * 0.25)
					if not wreck:
						pm.sphere(bc, bl * 0.5, 10, Vector3(1.0, 0.34, 0.32))
						pm.cylinder(d0, d1, bl * 0.03, bl * 0.03, 4, false)
						continue
					if x > gap.x - bl and x < gap.y + bl:
						continue                    # went down with the collapse
					var r := wrng.randf()
					if r < 0.35:
						# gone: the davit arm bent out and down over the side
						pm.cylinder(d0, d0 + Vector3(wrng.randf_range(-0.3, 0.3) * bl, -bl * 0.12, sd * bl * 0.4), bl * 0.03, bl * 0.025, 4, false)
					elif r < 0.6:
						# torn from one fall: hangs bow down from its aft davit against the deckhouse side
						var piv := bc + Vector3(-bl * 0.45, bl * 0.1, 0.0)
						pm.xf = _about(piv, Basis(Vector3.BACK, -deg_to_rad(wrng.randf_range(45.0, 70.0))) * Basis(Vector3.RIGHT, sd * deg_to_rad(wrng.randf_range(10.0, 30.0))))
						pm.sphere(bc, bl * 0.5, 10, Vector3(1.0, 0.34, 0.32))
						pm.xf = Transform3D.IDENTITY
						pm.cylinder(d0 - Vector3(bl * 0.45, 0, 0), d1 - Vector3(bl * 0.45, 0, 0), bl * 0.03, bl * 0.03, 4, false)
						pm.cylinder(d0 + Vector3(bl * 0.3, 0, 0), d0 + Vector3(bl * 0.3, -bl * 0.05, sd * bl * 0.35), bl * 0.03, bl * 0.03, 4, false)
					else:
						# still in its chocks, listing a little
						pm.xf = _about(bc, Basis(Vector3.RIGHT, sd * deg_to_rad(wrng.randf_range(4.0, 14.0))))
						pm.sphere(bc, bl * 0.5, 10, Vector3(1.0, 0.34, 0.32))
						pm.xf = Transform3D.IDENTITY
						pm.cylinder(d0, d1, bl * 0.03, bl * 0.03, 4, false)
				x += bl * 1.7
			if wreck:
				# a few boats lie fallen on the main deck beside the deckhouse
				for i in 3:
					var sd := 1.0 if i % 2 == 0 else -1.0
					var fb := Vector3(lerpf(xb + L * 0.05, xf - L * 0.1, wrng.randf()), _deck_y(0.0, L, D, k) + bl * 0.12,
						sd * (w0 * 0.5 + (B * 0.5 - w0 * 0.5) * 0.45))
					pm.xf = _about(fb, Basis(Vector3.UP, deg_to_rad(wrng.randf_range(-25.0, 25.0))) * Basis(Vector3.RIGHT, sd * deg_to_rad(wrng.randf_range(60.0, 100.0))))
					pm.sphere(fb, bl * 0.5, 10, Vector3(1.0, 0.34, 0.32))
					pm.xf = Transform3D.IDENTITY
			var mab := Vector3(L * 0.37, _deck_y(L * 0.37, L, D, k), 0)
			var mbb := Vector3(-L * 0.38, _deck_y(-L * 0.38, L, D, k), 0)
			if not wreck:
				var ma := mast(pm, mab, L * 0.085, L * 0.0012)
				var mb2 := mast(pm, mbb, L * 0.08, L * 0.0012)
				rig(rm, ma, mb2, L * 0.012, rr, 24)
				rig(rm, ma, Vector3(L * 0.5, D + sh, 0), L * 0.004, rr, 14)
				rig(rm, mb2, Vector3(-L * 0.48, D, 0), L * 0.004, rr, 14)
				for m: Vector3 in [ma, mb2]:
					for sd: float in [-1.0, 1.0]:
						rig(rm, m, Vector3(m.x - L * 0.03, D + 0.3, sd * B * 0.45), 0.0, rr, 6)
				tops.append(ma)
				tops.append(mb2)
			else:
				# the foremast snapped low, its top lies across the forecastle and over the rail; the mainmast
				# stands with one slack stay left to the stern and one torn shroud down to the deck
				var mh := L * 0.085
				var ma := mast(pm, mab, mh * 0.3, L * 0.0012)
				var sd := 1.0 if wrng.randf() < 0.5 else -1.0
				var fa := ma + Vector3(L * 0.004, -mh * 0.05, 0.0)
				var fe := Vector3(mab.x + mh * 0.25, mab.y - B * 0.03, sd * B * 0.62)
				pm.cylinder(fa, fe, L * 0.0012, L * 0.0008, 8)
				var mb2 := mast(pm, mbb, L * 0.08, L * 0.0012)
				rig(rm, mb2, Vector3(-L * 0.48, D, 0), L * 0.012, rr, 14)
				rig(rm, mb2, Vector3(mbb.x + L * 0.025, mbb.y + 0.3, -sd * B * 0.4), L * 0.004, rr, 8)
				tops.append(ma)
				tops.append(mb2)
	if fit:
		_fittings(kind, L, B, D, k, ho, pm, bz, rng, opts.get("stow", [1]), hawse, hawse_out)
	else:
		hawse = [Vector3(L * 0.44, _deck_y(L * 0.44, L, D, k) * 0.85, B * 0.1)]
		hawse_out = [Vector3(0, 0, 1)]
	if L >= 100.0:
		for f: float in [-0.28, -0.05, 0.15]:
			for sd: float in [-1.0, 1.0]:
				var lm := MeshBuilder.new()
				ladder(lm, L * f + rng.randf_range(-4.0, 4.0), sd * B * 0.5, D * 0.3, D)
				ladders.append(lm)
	if rails:
		_deck_rails(rl, L, B, D, k, ho, kind, wrng, 1.0 if wreck else 0.0)
	# materials
	var sref := clampf(L / 120.0, 1.0, 4.0)
	var hmat: Material
	var smat: Material
	if L < 12.0:
		var paint := Palette.BONE.darkened(0.3) if kind == "motorboat" else Palette.RUST.lerp(Palette.BONE, 0.3).darkened(0.4)
		hmat = Mats.solid(paint, 0.08, 0.3 if kind == "motorboat" else 0.6, {"roughness": 0.75})
		smat = Mats.solid(Palette.BONE.darkened(0.15), 0.05, 0.2, {"roughness": 0.6})
	else:
		var lk: Array = LOOK.get(kind, LOOK["cargo"])
		var pr := clampf(0.14 + L * 0.0007, 0.18, 0.6)
		var rows := 1 if L < 60.0 else clampi(roundi(D * 0.6 / (pr * 7.5)), 2, 8)
		var stp := minf(pr * 7.5, D * 0.6 / float(rows))
		var rust_h: float = float(lk[0]) + (0.3 if wreck else 0.0)
		# hull ports stay dark: lit ones on the shell read as eyes from below and as specks in the fog
		var hp := {"tint": lk[2], "rust_amount": minf(rust_h, 1.0), "moss_amount": lk[1], "porthole_spacing": pr * 7.0,
			"porthole_radius": pr, "porthole_row_start": D * (0.62 if L < 60.0 else 0.36), "porthole_row_step": stp,
			"porthole_rows": float(rows), "amber_fraction": 0.0, "seed": float(seed % 97), "scale_ref": sref,
			"deck_height": D, "waterline": D * float(lk[5]), "boot_width": clampf(D * 0.045, 0.35, 2.2),
			"wear": 1.4 if wreck else 1.0, "paint_dull": 1.0 if wreck else 0.0, "rusticles": 1.8 if wreck else 1.0,
			# the silted decks are far darker than the sand round them: a stronger web so it still reads on them
			"caustic_gain": 1.4}
		if fit:
			var us := 0.05 if k["stern"] == "transom" else 0.085
			var dg := clampf(D * 0.035, 0.2, 1.0)
			hp["draft"] = Vector4(us * L, 0.955 * L, dg, 1.0)
			hp["draft_max"] = floorf(D * 0.7)
		if kind == "liner":
			hp["fog_floor"] = LINER_FOG_FLOOR
		hmat = Mats.hull(hp)
		var wr := clampf(dh * 0.15, 0.3, 0.55)
		var st: Vector3 = lk[3]
		smat = Mats.hull({"tint": st * (0.5 if wreck else 1.0), "rust_amount": minf(float(lk[0]) * 0.8 + (0.4 if wreck else 0.0), 1.0),
			"moss_amount": lk[1], "porthole_spacing": wr * 4.2, "porthole_radius": wr, "porthole_row_start": dh * 0.55,
			"porthole_row_step": dh, "porthole_rows": float(maxi(tiers, 1)), "amber_fraction": 0.0 if wreck else lk[4],
			"seed": float(seed % 97) + 13.0, "scale_ref": sref, "plate_size": Vector2(6.0, dh), "door_spacing": 8.0,
			"wear": 1.5 if wreck else 1.0, "paint_dull": 1.0 if wreck else 0.0, "rusticles": 2.0 if wreck else 1.0,
			"fog_floor": LINER_FOG_FLOOR if kind == "liner" else Vector2.ZERO})
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(opts.get("shadows", true)) \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tris := hm.tri_count() + sm.tri_count() + pm.tri_count() + rm.tri_count() + bz.tri_count() + rl.tri_count()
	var mi := hm.instance(hmat, geo)
	mi.name = "Hull"
	mi.cast_shadow = shadow
	if sm.tri_count() > 0:
		var ms := sm.instance(smat, geo)
		ms.name = "Super"
		ms.cast_shadow = shadow
	if pm.tri_count() > 0:
		var mp := pm.instance(_parts(), geo)
		mp.name = "Parts"
		mp.cast_shadow = shadow
	if bz.tri_count() > 0:
		var mz := bz.instance(_bronze(), geo)
		mz.name = "Propellers"
		mz.cast_shadow = shadow
	if rm.tri_count() > 0:
		var mr := rm.instance(Mats.make("rope", {"radius": rr, "rope_color": Color(0.24, 0.23, 0.21)}), geo, _line_range(L))
		mr.name = "Rigging"
		mr.cast_shadow = shadow
	if rl.tri_count() > 0:
		var mrl := rl.instance(_rail_mat(), geo, _line_range(L))
		mrl.name = "Rails"
		mrl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for lm: MeshBuilder in ladders:
		tris += lm.tri_count()
		var ml := lm.instance(_parts(), geo, 90.0)
		ml.name = "Ladder"
	var th := []
	for p: Vector3 in tops:
		th.append(_r(p))
	var hw := []
	for p: Vector3 in hawse:
		hw.append(_r(p))
	var ho2 := []
	for p: Vector3 in hawse_out:
		ho2.append(_r(p))
	var wb := []
	for p: Vector3 in blocks:
		wb.append(_r(p))
	root.set_meta("length", L)
	root.set_meta("beam", B)
	root.set_meta("depth", D)
	root.set_meta("tops", th)
	root.set_meta("hawse", hw)
	root.set_meta("hawse_out", ho2)
	root.set_meta("warp_blocks", wb)
	root.set_meta("tris", tris)
	return root


static var _rlmat: ShaderMaterial


## Rigging and railings are drawn with a 1 px floor: past this distance (m) the hull they belong to has gone into
## the fog, and the lines alone hung in the water (the cargo ship's derricks read as floating scaffolding).
static func _line_range(L: float) -> float:
	return clampf(L * 1.2, 110.0, 260.0)


static func _rail_mat() -> ShaderMaterial:
	if _rlmat == null:
		_rlmat = Mats.make("rope", {"radius": RAIL_R, "rope_color": Color(0.2, 0.19, 0.17)})
	return _rlmat


## Transform rotating by bs about the point p.
static func _about(p: Vector3, bs: Basis) -> Transform3D:
	return Transform3D(bs, p - bs * p)


## Funnel with damage: mode 0 upright (as funnel()), 1 leaning hard over on its buckled base, 2 broken short and
## leaning a little the other way.
static func _funnel_wreck(mb: MeshBuilder, base: Vector3, h: float, rx: float, rz: float, rake: float, mode: int,
		rng: RandomNumberGenerator) -> Vector3:
	if mode == 0:
		return funnel(mb, base, h, rx, rz, rake)
	var sd := 1.0 if rng.randf() < 0.5 else -1.0
	var b := base - Vector3(0, rz * 0.4, 0)
	# over to one side and toward the stern, so the lean reads from any side
	var bs := Basis(Vector3.RIGHT, sd * deg_to_rad(rng.randf_range(20.0, 26.0))) * Basis(Vector3.BACK, deg_to_rad(rng.randf_range(12.0, 17.0)))
	var hh := h
	if mode == 2:
		bs = Basis(Vector3.RIGHT, -sd * deg_to_rad(rng.randf_range(7.0, 11.0))) * Basis(Vector3.BACK, -deg_to_rad(rng.randf_range(4.0, 8.0)))
		hh = h * rng.randf_range(0.6, 0.72)
	mb.xf = _about(b, bs)
	var top := funnel(mb, b, hh, rx, rz, rake)
	mb.xf = Transform3D.IDENTITY
	return _about(b, bs) * top


## Railing along a polyline of deck-edge points (ship frame, then xf): 1 m-class posts every `step` m with a top
## and a mid rail; runs are missing here and there and a few posts are bent over (far more of both when broken).
static func _railing(rl: MeshBuilder, base: PackedVector3Array, h: float, rng: RandomNumberGenerator, broken := 0.0,
		xf := Transform3D.IDENTITY, step := 2.0) -> void:
	var posts := PackedVector3Array()
	var carry := 0.0
	for i in base.size() - 1:
		var a := base[i]
		var b := base[i + 1]
		var ln := a.distance_to(b)
		var d := carry
		while d < ln:
			posts.append(a.lerp(b, d / maxf(ln, 1e-4)))
			d += step
		carry = d - ln
	var up := xf.basis * Vector3(0, h, 0)
	var run := PackedVector3Array()
	var skip := 0
	for p0 in posts:
		var p := xf * p0
		if skip > 0:
			skip -= 1
			continue
		if rng.randf() < 0.008 + broken * 0.035:
			skip = rng.randi_range(2, 5 + int(broken * 8.0))
			_rail_run(rl, run, up)
			run = PackedVector3Array()
			continue
		if rng.randf() < 0.02 + broken * 0.07:
			# bent over: the rail is torn here
			var lean := Vector3(rng.randf_range(-1.0, 1.0), -0.3, rng.randf_range(-1.0, 1.0)).normalized() * h * 0.7
			Rope.tube(PackedVector3Array([p, p + up * 0.45, p + up * 0.45 + lean]), RAIL_R, 3, rl)
			_rail_run(rl, run, up)
			run = PackedVector3Array()
			continue
		Rope.tube(PackedVector3Array([p, p + up]), RAIL_R, 3, rl)
		run.append(p + up)
	_rail_run(rl, run, up)


static func _rail_run(rl: MeshBuilder, tops: PackedVector3Array, up: Vector3) -> void:
	if tops.size() < 2:
		return
	Rope.tube(tops, RAIL_R, 3, rl)
	var mid := PackedVector3Array()
	for p in tops:
		mid.append(p - up * 0.5)
	Rope.tube(mid, RAIL_R, 3, rl)


## Railings on the main deck edge (on the bulwark top, round the stern of a round-sterned ship, across the
## transom of the cargo ship and the tanker), following the sheer.
static func _deck_rails(rl: MeshBuilder, L: float, B: float, D: float, k: Dictionary, ho: Dictionary, kind: String,
		rng: RandomNumberGenerator, broken: float) -> void:
	var bw := clampf(D * 0.08, 0.06, 1.6)
	var h := clampf(1.1 - bw, 0.4, 1.0)
	var rnd: bool = k["stern"] == "round"
	var u0 := 0.0 if rnd else 0.004
	var n := clampi(int(L / 3.0), 24, 220)
	for sd: float in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		for i in n + 1:
			var u := lerpf(u0, 0.985, float(i) / float(n))
			var s := _station(L, B, D, k["taper"], k["rake"], ho, u)
			pts.append(Vector3(float(s["x0"]) - float(s["sk"]) * bw, float(s["yd"]) + bw, sd * maxf(float(s["wh"]) - 0.06, 0.0)))
		_railing(rl, pts, h, rng, broken)
	if not rnd and kind in ["cargo", "tanker"]:
		var s := _station(L, B, D, k["taper"], k["rake"], ho, u0)
		var p := Vector3(float(s["x0"]) - float(s["sk"]) * bw + 0.06, float(s["yd"]) + bw, 0.0)
		var hw := maxf(float(s["wh"]) - 0.1, 0.0)
		_railing(rl, PackedVector3Array([p + Vector3(0, 0, -hw), p + Vector3(0, 0, hw)]), h, rng, broken)


## The broken middle of a wrecked superstructure: one tier crushed to half height and sagging into the gap,
## deck slabs fallen in from the broken ends, a scatter of debris on the floor of the gap.
static func _collapse(mb: MeshBuilder, pm: MeshBuilder, gap: Vector2, y: float, w: float, dh: float, rf: float,
		y_ref: float, rng: RandomNumberGenerator) -> void:
	var gl := gap.y - gap.x
	var cx := (gap.x + gap.y) * 0.5
	var fy := y + dh * 0.02
	var heel := deg_to_rad(rng.randf_range(6.0, 11.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
	mb.xf = _about(Vector3(cx, fy, 0.0), Basis(Vector3.RIGHT, heel) * Basis(Vector3.BACK, deg_to_rad(rng.randf_range(-7.0, 7.0))))
	block(mb, Vector3(cx + rng.randf_range(-0.08, 0.08) * gl, fy - dh * 0.12, 0.0), gl * 0.6, w * 0.9, dh * 0.6, rf * 0.5,
		rf * 0.2, y_ref, true, 1)
	for e in 2:
		var xe := gap.x if e == 0 else gap.y
		var dirn := 1.0 if e == 0 else -1.0                   # toward the middle of the gap
		var ang := deg_to_rad(rng.randf_range(16.0, 28.0)) * dirn
		mb.xf = _about(Vector3(xe, y + dh, 0.0), Basis(Vector3.BACK, -ang) * Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(-6.0, 6.0))))
		block(mb, Vector3(xe + dirn * gl * 0.2, y + dh * 0.94, rng.randf_range(-0.08, 0.08) * w), gl * 0.4, w * 0.85,
			dh * 0.12, 0.2, 0.2, y_ref, false, 3)
	mb.xf = Transform3D.IDENTITY
	for i in 7:
		var s := Vector3(rng.randf_range(0.3, 1.0), rng.randf_range(0.15, 0.5), rng.randf_range(0.3, 1.0)) * dh * 0.6
		var p := Vector3(cx + rng.randf_range(-0.45, 0.45) * gl, fy + s.y * 0.3, rng.randf_range(-0.4, 0.4) * w)
		pm.box(p, s, Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))))


static var _bmat: ShaderMaterial


static func _bronze() -> ShaderMaterial:
	if _bmat == null:
		# lighter than the hull bottom so the blades read against it, not as dark crosses
		_bmat = Mats.solid(Palette.VERDIGRIS.lerp(Palette.RUST, 0.3).darkened(0.22), 0.25, 0.35, {"roughness": 0.55})
	return _bmat
