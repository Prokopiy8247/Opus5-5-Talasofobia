class_name Submarine
extends RefCounted
## Parametric submarine standing on its stern (the forest of beat 3).
## Local frame: +Y is the hull axis (stern tip at 0, bow tip at L), the sail and the deck casing face +Z.
## Dive planes and tail fins are plates that contain the axis (vertical when the boat stands upright).
## UV in metres: UV.x = girth around the hull (or around the sail outline), UV.y = height along the axis
## (on the sail: height out of the hull) -> shaders/sub.gdshader.
## Vertex COLOR: r = ambient occlusion (1 open), g = rubber tile coverage (1 tiled skin, 0 bare steel),
## b = rust bias, a = surface kind: 0 plating; OPENING (0.35) on the dark interiors of flood slots, torpedo tubes
## and open missile tubes (UV.x = 0 at the centre .. 1 at the rim); 1 on window quads (UV.x = the light id +- 0.2
## across the window, UV.y 0..1 up it, so the shader can draw a hot centre).
## sail_windows() gives the bridge window centres (mesh units) for lights placed by the beat.
## filler_mesh() is a low-poly tower (round hull, sail, planes, fins; same frame, UV and colours) for the
## mid-distance rows of the forest.

const OPENING := 0.35

const STERN := 0.24      # stern cone, fraction of the length
const BOW := 0.13        # bow dome


## Key dimensions (mesh units) shared by mesh() and the placement code (Beat03_Forest.gd).
## o: sail_t (sail centre / L), seed, casing "attack" | "boomer", planes "sail" | "bow", tail "cross" | "x",
## broken (0 = intact, else the height of the break / L).
static func info(L: float, R: float, o: Dictionary) -> Dictionary:
	var boomer: bool = o.get("casing", "attack") == "boomer"
	var brk: float = o.get("broken", 0.0)
	var d := {
		"L": L, "R": R, "boomer": boomer, "broken": brk,
		"sail_y": L * float(o.get("sail_t", 0.68)),
		"sail_c": L * (0.112 if boomer else 0.1),
		"sail_h": R * (1.15 if boomer else 1.3),
		"sail_tx": R * 0.19,
		"wc": R * (0.5 if boomer else 0.3),
		"hc": R * 0.09,
		"hump": R * (0.26 if boomer else 0.0),
		"top": L * brk if brk > 0.0 else L,
		"fin_y0": L * 0.05, "fin_y1": L * 0.12, "fin_tip": R * 1.06,
		"plane_span": R * 0.95,
	}
	d["reach"] = R + d["hc"] + d["sail_h"] + 2.0          # axis -> sail top (periscopes excluded)
	d["ground_y"] = L * 0.025                              # where the seabed meets the stern cone
	return d


static func radius_at(y: float, L: float, R: float) -> float:
	var t := clampf(y / L, 0.0, 1.0)
	if t < STERN:
		var k := t / STERN
		return R * (0.075 + 0.925 * (1.0 - pow(1.0 - k, 2.3)))
	if t > 1.0 - BOW:
		var k := (t - (1.0 - BOW)) / BOW
		return R * pow(maxf(1.0 - pow(k, 2.5), 0.0), 0.4)
	return R


## Casing deck height above the axis at axial height y. The casing fairs into the hull at its ends: there its
## deck sinks to where its side walls meet the hull circle, so the box ends inside the hull (a casing that kept
## its width down to r left two corners standing proud of the bow dome: a step in the bow outline).
static func _deck(y: float, r: float, d: Dictionary) -> float:
	var L: float = d["L"]
	var w := smoothstep(L * 0.2, L * 0.27, y) * (1.0 - smoothstep(L * 0.86, L * 0.93, y))
	var sy: float = d["sail_y"]
	var hump: float = d["hump"] * smoothstep(L * 0.3, L * 0.36, y) * (1.0 - smoothstep(sy - L * 0.02, sy, y))
	var wc: float = d["wc"]
	var h0 := sqrt(maxf(r * r - wc * wc, 0.0))
	return lerpf(h0, r + float(d["hc"]) + hump, w)


## Distance from the axis to the hull + casing outline along angle a (0 = +X, PI/2 = +Z): the union of the
## hull circle and the casing box [-wc, wc] x [0, H] (continuous as the box sinks into the circle).
static func _section_r(a: float, r: float, wc: float, H: float) -> float:
	var s := sin(a)
	if s <= 1e-4:
		return r
	var t := H / s
	var c := absf(cos(a))
	if c > 1e-4:
		t = minf(t, wc / c)
	return maxf(r, t)


## Ring angles, starting at the back (-Z) so the UV seam is hidden; dense around the casing corners.
static func _angles(d: Dictionary) -> PackedFloat32Array:
	var R: float = d["R"]
	var wc: float = d["wc"]
	var a_b := acos(wc / R)
	var a_c := atan2(R + float(d["hc"]), wc)
	var a_h := atan2(R + float(d["hc"]) + float(d["hump"]), wc)
	var a_lo := a_b - deg_to_rad(7.0)
	var sp := [a_lo, a_b - deg_to_rad(2.5), a_b, lerpf(a_b, a_c, 0.5), a_c]
	var top0 := a_c
	if float(d["hump"]) > 0.0:
		sp.append(lerpf(a_c, a_h, 0.5))
		sp.append(a_h)
		top0 = a_h
	sp.append(lerpf(top0, PI * 0.5, 0.4))
	sp.append(lerpf(top0, PI * 0.5, 0.75))
	var out := []
	for i in 40:
		var a := -PI * 0.5 + TAU * float(i) / 40.0
		if a > a_lo - deg_to_rad(2.0) and a < PI - a_lo + deg_to_rad(2.0):
			continue
		out.append(a)
	for a: float in sp:
		out.append(a)
		out.append(PI - a)
	out.append(PI * 0.5)
	out.sort()
	return PackedFloat32Array(out)


## Axial ring heights: dense at the tips, at the casing ramps and around the sail.
static func _ys(d: Dictionary) -> PackedFloat32Array:
	var L: float = d["L"]
	var sy: float = d["sail_y"]
	var c: float = d["sail_c"]
	var top: float = d["top"]
	var marks := []
	for i in 13:
		var k := float(i) / 12.0
		marks.append(L * STERN * (0.55 * k * k + 0.45 * k))
	for f: float in [0.27, 0.3, 0.33, 0.36, 0.86, 0.895]:
		marks.append(L * f)
	for o: float in [-0.5, -0.25, 0.0, 0.25, 0.5]:
		marks.append(sy + c * o)
	marks.append(sy - L * 0.02)
	marks.append(sy - L * 0.01)
	marks.append(sy + L * 0.02)
	for i in 12:
		var k := float(i) / 12.0
		marks.append(L * (1.0 - BOW) + L * BOW * (1.0 - pow(1.0 - k, 1.7)))
	marks.append(L * (1.0 - BOW * 0.006))
	marks.sort()
	var out := []
	for y: float in marks:
		if y > top + 0.01:
			continue
		if not out.is_empty() and y - float(out[out.size() - 1]) < 1.2:
			continue
		# fill long gaps in the midbody
		if not out.is_empty():
			var y0: float = out[out.size() - 1]
			var n := int(floor((y - y0) / 14.0))
			for k in n:
				out.append(y0 + (y - y0) * float(k + 1) / float(n + 1))
		out.append(y)
	return PackedFloat32Array(out)


## Loft through rings of equal size (each closed), with a duplicate seam column. UV = (girth, height).
## col_fn(p: Vector3) -> Color. inward: normals point toward the ring centre.
static func _loft(mb: MeshBuilder, rings: Array, col_fn: Callable, inward := false, uv_y_fn := Callable()) -> void:
	var nr := rings.size()
	var np: int = (rings[0] as PackedVector3Array).size()
	var base := mb.v.size()
	for i in nr:
		var ring: PackedVector3Array = rings[i]
		var prev: PackedVector3Array = rings[maxi(i - 1, 0)]
		var nxt: PackedVector3Array = rings[mini(i + 1, nr - 1)]
		var cen := Vector3.ZERO
		for p in ring:
			cen += p
		cen /= float(np)
		var g := 0.0
		for j in np + 1:
			var jj := j % np
			if j > 0:
				g += ring[jj].distance_to(ring[j - 1])
			var du := nxt[jj] - prev[jj]
			var dv := ring[(jj + 1) % np] - ring[(jj - 1 + np) % np]
			var nn := du.cross(dv)
			var outv := ring[jj] - cen
			if nn.length_squared() < 1e-10:
				nn = outv
			nn = nn.normalized()
			if nn.dot(outv) < 0.0:
				nn = -nn
			if inward:
				nn = -nn
			var vy: float = uv_y_fn.call(ring[jj]) if uv_y_fn.is_valid() else ring[jj].y
			mb.vert(ring[jj], nn, Vector2(g, vy), col_fn.call(ring[jj]))
	for i in nr - 1:
		for j in np:
			var a := base + i * (np + 1) + j
			var b := base + (i + 1) * (np + 1) + j
			mb.quad(a, b, b + 1, a + 1)


## Flat cap (fan) of a ring with a given normal; UV = the two in-plane coordinates in metres.
static func _cap(mb: MeshBuilder, ring: PackedVector3Array, nrm: Vector3, c: Color) -> void:
	var cen := Vector3.ZERO
	for p in ring:
		cen += p
	cen /= float(ring.size())
	var t1 := nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := nrm.cross(t1)
	var c0 := mb.vert(cen, nrm, Vector2(cen.dot(t1), cen.dot(t2)), c)
	var first := mb.v.size()
	for p in ring:
		mb.vert(p, nrm, Vector2(p.dot(t1), p.dot(t2)), c)
	for j in ring.size():
		mb.tri(c0, first + j, first + (j + 1) % ring.size())


## Flat quad (window, limber hole) facing nrm; UV.x = id for lights. Lit quads (col.a 1) also carry the
## position inside the quad: UV.x = id +- 0.2, UV.y = 0..1 (the shader's hot centre).
static func _rect(mb: MeshBuilder, c: Vector3, u: Vector3, v: Vector3, nrm: Vector3, col: Color, id := 0.0) -> void:
	var k := 1.0 if col.a > 0.5 else 0.0
	var a := mb.vert(c - u - v, nrm, Vector2(id - 0.2 * k, 0.0), col)
	var b := mb.vert(c + u - v, nrm, Vector2(id + 0.2 * k, 0.0), col)
	var e := mb.vert(c + u + v, nrm, Vector2(id + 0.2 * k, k), col)
	var f := mb.vert(c - u + v, nrm, Vector2(id - 0.2 * k, k), col)
	mb.quad(a, b, e, f)


## Rounded slot (flood hole) facing nrm: half length hl along u, half width hw along v. A fan from the centre,
## UV.x = 0 there and 1 on the rim (the shader's recess gradient).
static func _slot(mb: MeshBuilder, c: Vector3, u: Vector3, v: Vector3, nrm: Vector3, hl: float, hw: float, col: Color) -> void:
	var rim := PackedVector3Array()
	var e := maxf(hl - hw, 0.0)
	for end: float in [1.0, -1.0]:
		for k in 7:
			var a := -PI * 0.5 + PI * float(k) / 6.0
			rim.append(c + u * end * (e + cos(a) * hw) + v * end * sin(a) * hw)
	_fan(mb, c, rim, nrm, col)


## Round disc (torpedo door, open tube) of radius r facing nrm; UV.x 0 at the centre, 1 on the rim.
static func _disc(mb: MeshBuilder, c: Vector3, nrm: Vector3, r: float, seg: int, col: Color) -> void:
	var t1 := nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := nrm.cross(t1)
	var rim := PackedVector3Array()
	for k in seg:
		var a := TAU * float(k) / float(seg)
		rim.append(c + (t1 * cos(a) + t2 * sin(a)) * r)
	_fan(mb, c, rim, nrm, col)


static func _fan(mb: MeshBuilder, c: Vector3, rim: PackedVector3Array, nrm: Vector3, col: Color) -> void:
	var c0 := mb.vert(c, nrm, Vector2(0.0, 0.0), col)
	var first := mb.v.size()
	for p in rim:
		mb.vert(p, nrm, Vector2(1.0, 0.0), col)
	for j in rim.size():
		mb.tri(c0, first + j, first + (j + 1) % rim.size())


## Bridge windows near the sail's leading edge, both sides (mesh units): [[centre, outward normal], ...].
## mesh() builds them from this list; the beat uses it to put a lamp behind one of them.
static func sail_windows(L: float, R: float, o := {}) -> Array:
	var d := info(L, R, o)
	var sy: float = d["sail_y"]
	var sc: float = d["sail_c"]
	var tx: float = d["sail_tx"]
	var wz := _deck(sy, R, d) + float(d["sail_h"]) * 0.88
	var out := []
	for sg: float in [-1.0, 1.0]:
		for k in 3:
			var wy := sy + (sc * 0.5 - tx) * 0.93 - 1.1 - float(k) * 2.4
			out.append([Vector3(sg * (tx + 0.06), wy, wz), Vector3(sg, 0, 0)])
	return out


## A plate (fin, dive plane): quadrilateral root_a -> root_b (root chord), tip_b -> tip_a (tip chord),
## thickness th along `thick`. Flat shaded; the root face is left open (it sits inside the hull).
static func _plate(mb: MeshBuilder, ra: Vector3, rb: Vector3, tb: Vector3, ta: Vector3, thick: Vector3, th: float,
		col: Color) -> void:
	var h := thick.normalized() * th * 0.5
	var cen := (ra + rb + tb + ta) * 0.25
	var span := ((ta + tb) * 0.5 - (ra + rb) * 0.5)
	var sl := span.length()
	var span_n := span / maxf(sl, 1e-4)
	var chord_n := (rb - ra).normalized()
	for sg: float in [-1.0, 1.0]:
		var n := thick.normalized() * sg
		var q := []
		for p: Vector3 in [ra, rb, tb, ta]:
			var rel := p - ra
			q.append(mb.vert(p + h * sg, n, Vector2(rel.dot(chord_n), rel.dot(span_n)), col))
		mb.quad(q[0], q[1], q[2], q[3])
	for e: Array in [[rb, tb], [tb, ta], [ta, ra]]:
		var p0: Vector3 = e[0]
		var p1: Vector3 = e[1]
		var n := h.cross(p1 - p0).normalized()
		if n.dot((p0 + p1) * 0.5 - cen) < 0.0:
			n = -n
		var l := p0.distance_to(p1)
		var a := mb.vert(p0 - h, n, Vector2(0.0, 0.0), col)
		var b := mb.vert(p1 - h, n, Vector2(l, 0.0), col)
		var c := mb.vert(p1 + h, n, Vector2(l, th), col)
		var dd := mb.vert(p0 + h, n, Vector2(0.0, th), col)
		mb.quad(a, b, c, dd)


## Sail outline in its own plane: x = across (thickness), y = along the axis relative to the sail centre.
## Rounded leading edge toward the bow (+y), flat sides, tapered trailing edge.
static func _sail_outline(c: float, tx: float) -> PackedVector2Array:
	var tt := tx * 0.5
	var yl := c * 0.5 - tx
	var yct := -c * 0.5 + tt
	var yt0 := -c * 0.5 + c * 0.42
	var half := []
	for k in 4:
		var th := PI * 0.5 * float(k) / 3.0
		half.append(Vector2(tt * sin(th), yct - tt * cos(th)))
	for f: float in [0.33, 0.66, 1.0]:
		half.append(Vector2(lerpf(tt, tx, f), lerpf(yct, yt0, f)))
	for f: float in [0.33, 0.66]:
		half.append(Vector2(tx, lerpf(yt0, yl, f)))
	for k in 5:
		var ph := PI * 0.5 * float(k) / 4.0
		half.append(Vector2(tx * cos(ph), yl + tx * sin(ph)))
	var out := PackedVector2Array()
	for p: Vector2 in half:
		out.append(p)
	for i in range(half.size() - 2, 0, -1):
		var p: Vector2 = half[i]
		out.append(Vector2(-p.x, p.y))
	return out


## Builds one submarine mesh. L ~ 260-420 m, R ~ 0.055 L. See info() for the options.
static func mesh(L: float, R: float, o := {}) -> ArrayMesh:
	var d := info(L, R, o)
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(o.get("seed", 0))
	var sy: float = d["sail_y"]
	var sc: float = d["sail_c"]
	var sh: float = d["sail_h"]
	var tx: float = d["sail_tx"]
	var wc: float = d["wc"]
	var top: float = d["top"]
	var brk: float = d["broken"]
	var angles := _angles(d)
	var cross_tail: bool = o.get("tail", "cross") == "cross"
	var fin_angles := [0.0, PI * 0.5, PI, PI * 1.5] if cross_tail else [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]
	var fy0: float = d["fin_y0"]
	var fy1: float = d["fin_y1"]

	# ---- hull + casing
	var ys := _ys(d)
	var hull_col := func(p: Vector3) -> Color:
		var ao := 1.0
		var r := radius_at(p.y, L, R)
		# under the sail
		if p.z > R * 0.5:
			var dx := maxf(absf(p.x) - tx, 0.0)
			var dy := maxf(absf(p.y - sy) - sc * 0.5, 0.0)
			ao *= lerpf(0.5, 1.0, smoothstep(0.0, R * 0.45, Vector2(dx, dy).length()))
		# the inner corner where the casing side meets the hull
		var H := _deck(p.y, r, d)
		var tiled := 1.0
		if H > r + 0.3:
			var zb := sqrt(maxf(r * r - wc * wc, 0.0))
			if absf(absf(p.x) - wc) < 0.05 and absf(p.z - zb) < 0.6:
				ao *= 0.62
			if p.z > H - 0.05:
				tiled = 0.0
		# tail fin roots
		if p.y < fy1 + R * 0.4:
			var ang := atan2(p.z, p.x)
			for fa: float in fin_angles:
				var da := absf(wrapf(ang - fa, -PI, PI)) * maxf(r, 1.0)
				ao *= lerpf(0.6, 1.0, smoothstep(0.0, R * 0.3, da))
		return Color(ao, tiled, 0.35 if tiled > 0.5 else 0.7, 0.0)
	var rings := []
	var top_jag := PackedFloat32Array()
	if brk > 0.0:
		for j in angles.size():
			var a: float = angles[j]
			top_jag.append(L * clampf(0.022 * sin(a * 3.0 + rng.randf() * 0.4 + 1.3) + 0.012 * sin(a * 7.0 + 2.1)
				+ rng.randf_range(-0.012, 0.012), -0.034, 0.05))
	var ylist := []
	for y in ys:
		if brk > 0.0 and y > top - L * 0.045:
			continue
		ylist.append(y)
	if brk > 0.0:
		ylist.append(top - L * 0.045)
	for y: float in ylist:
		var r := radius_at(y, L, R)
		var H := _deck(y, r, d)
		var ring := PackedVector3Array()
		for a in angles:
			var rr := _section_r(a, r, wc, H)
			ring.append(Vector3(cos(a) * rr, y, sin(a) * rr))
		rings.append(ring)
	var jag_ring := PackedVector3Array()
	if brk > 0.0:
		for j in angles.size():
			var a: float = angles[j]
			var y := top + top_jag[j]
			var r := radius_at(y, L, R)
			var rr := _section_r(a, r, wc, _deck(y, r, d))
			jag_ring.append(Vector3(cos(a) * rr, y, sin(a) * rr))
		rings.append(jag_ring)
	_loft(mb, rings, hull_col)
	var steel := Color(0.85, 0.0, 0.7, 0.0)
	_cap(mb, rings[0], Vector3.DOWN, Color(0.5, 0.0, 0.7, 0.0))
	if brk <= 0.0:
		_cap(mb, rings[rings.size() - 1], Vector3.UP, Color(1.0, 1.0, 0.35, 0.0))
	else:
		# the torn end: rim, inner skin, a dark bulkhead and a few plates bent outward
		var inner_top := PackedVector3Array()
		var inner_low := PackedVector3Array()
		var yl := top - L * 0.075
		for j in jag_ring.size():
			var p: Vector3 = jag_ring[j]
			inner_top.append(Vector3(p.x * 0.95, p.y, p.z * 0.95))
			var a: float = angles[j]
			var r := radius_at(yl, L, R)
			var rr := _section_r(a, r, wc, _deck(yl, r, d)) * 0.95
			inner_low.append(Vector3(cos(a) * rr, yl, sin(a) * rr))
		var dark := func(_p: Vector3) -> Color:
			return Color(0.12, 0.0, 0.8, 0.0)
		_loft(mb, [inner_low, inner_top], dark, true)
		_cap(mb, inner_low, Vector3.UP, Color(0.06, 0.0, 0.8, 0.0))
		for j in jag_ring.size():
			var j2 := (j + 1) % jag_ring.size()
			var a0 := mb.vert(jag_ring[j], Vector3.UP, Vector2(0, 0), Color(0.8, 0.0, 0.9, 0.0))
			var a1 := mb.vert(jag_ring[j2], Vector3.UP, Vector2(1, 0), Color(0.8, 0.0, 0.9, 0.0))
			var b1 := mb.vert(inner_top[j2], Vector3.UP, Vector2(1, 1), Color(0.5, 0.0, 0.9, 0.0))
			var b0 := mb.vert(inner_top[j], Vector3.UP, Vector2(0, 1), Color(0.5, 0.0, 0.9, 0.0))
			mb.quad(a0, a1, b1, b0)
		# hull plates peeled outward from the rim like petals (chains of thin boxes curling out)
		for k in 3:
			var j := (int(float(jag_ring.size()) * (float(k) + rng.randf_range(0.1, 0.7)) / 3.0)) % jag_ring.size()
			var p: Vector3 = jag_ring[j]
			var outw := Vector3(p.x, 0.0, p.z).normalized()
			var tang := Vector3(-outw.z, 0.0, outw.x)
			var wid := R * rng.randf_range(0.35, 0.6)
			var seg := L * rng.randf_range(0.007, 0.011)
			var curl := rng.randf_range(0.35, 0.6)
			var c := p - outw * 0.2
			var ang := 0.15
			mb.color = Color(0.75, 0.0, 0.9, 0.0)
			for i in 3:
				var up := (Vector3.UP * cos(ang) + outw * sin(ang)).normalized()
				mb.box(c + up * seg * 0.5, Vector3(wid * (1.0 - 0.15 * float(i)), seg, 0.45), Basis(tang, up, tang.cross(up)))
				c += up * seg * 0.96
				ang += curl

	# ---- flood slots along the casing sides: elongated along the axis, in groups of uneven length and spacing
	# with long plain runs between them (an even ladder of square holes read as tower windows)
	var hole := Color(1.0, 0.0, 0.5, OPENING)
	var ly := L * 0.28 + rng.randf_range(0.0, 10.0)
	var y_end := minf(L * 0.85, top - L * 0.05)
	while ly < y_end:
		var n_in := rng.randi_range(2, 6)
		var sl := rng.randf_range(2.2, 4.6)
		var row_z := rng.randf_range(0.4, 0.62)
		for i in n_in:
			var ln := sl * rng.randf_range(0.55, 1.3)
			var yy := ly + ln * 0.5
			ly += ln + rng.randf_range(0.5, 1.0) * (1.0 if rng.randf() < 0.7 else 3.2)
			if yy > y_end or absf(yy - sy) < sc * 0.5 + 3.0:
				continue
			var r := radius_at(yy, L, R)
			var H := _deck(yy, r, d)
			var zb := sqrt(maxf(r * r - wc * wc, 0.0))
			var side := H - zb
			if side < 1.6:
				continue
			var hw := minf(side * 0.13, 0.42)
			for sg: float in [-1.0, 1.0]:
				if rng.randf() < 0.15:
					continue                         # plated over on this side
				var zc := lerpf(zb, H, row_z + rng.randf_range(-0.07, 0.07))
				_slot(mb, Vector3(sg * (wc + 0.06), yy, zc), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(sg, 0, 0),
					ln * 0.5, hw * rng.randf_range(0.85, 1.1), hole)
		ly += rng.randf_range(9.0, 34.0)
	# torpedo tubes: three pairs of round doors clustered round the bow tip, keel-side, each in a raised lip so
	# it reads recessed
	if top > L * 0.95:
		var dr := R * 0.062
		for pr: Array in [[-52.0, 0.903], [-128.0, 0.903], [-90.0, 0.921]]:
			var yy: float = L * float(pr[1])
			for off: float in [-7.0, 7.0]:
				var a := deg_to_rad(float(pr[0]) + off)
				var radial := Vector3(cos(a), 0.0, sin(a))
				var r := radius_at(yy, L, R)
				var slope := (radius_at(yy + 0.5, L, R) - radius_at(yy - 0.5, L, R))
				var nrm := (radial - Vector3(0, slope, 0)).normalized()
				var c := radial * r + Vector3(0, yy, 0)
				mb.color = Color(0.7, 0.0, 0.55, 0.0)
				mb.torus(c + nrm * 0.12, nrm, dr * 1.16, dr * 0.18, 18, 5)
				_disc(mb, c + nrm * 0.1, nrm, dr, 18, hole)
	var nlit := 0
	if d["boomer"]:
		# missile deck: two columns of hatches behind the sail, a few open
		var hr := R * 0.16
		var yy := sy - sc * 0.5 - hr * 1.6
		var row := 0
		while yy > L * 0.37 and row < 10:
			for sg: float in [-1.0, 1.0]:
				var H := _deck(yy, R, d)
				var c := Vector3(sg * wc * 0.48, yy, H)
				if rng.randf() < 0.2:
					# an open missile tube: the dark water inside a round rim, its door swung back
					mb.color = steel
					mb.cylinder(c + Vector3(0, 0, -0.3), c + Vector3(0, 0, 0.45), hr, hr * 0.96, 12, false)
					_disc(mb, c + Vector3(0, 0, 0.4), Vector3(0, 0, 1), hr * 0.9, 14, hole)
					var hinge := c + Vector3(sg * hr, 0, 0.2)
					var door := Basis(Vector3(0, 1, 0), sg * rng.randf_range(1.2, 1.9))
					mb.color = steel
					mb.box(hinge + door * Vector3(-sg * hr, 0, 0) + Vector3(0, 0, 0.3), Vector3(hr * 2.0, hr * 2.0, 0.5), door)
				else:
					mb.color = steel
					mb.cylinder(c + Vector3(0, 0, -0.3), c + Vector3(0, 0, 0.45), hr, hr * 0.96, 12, false)
					_cap(mb, _circle(c + Vector3(0, 0, 0.45), hr * 0.96, 12), Vector3(0, 0, 1), steel)
			yy -= hr * 3.0
			row += 1
	else:
		for f: float in [-0.9, 1.6]:
			var hy := sy + sc * f
			if hy > top - L * 0.05:
				continue
			var H := _deck(hy, radius_at(hy, L, R), d)
			var c := Vector3(0, hy, H)
			mb.color = steel
			mb.cylinder(c + Vector3(0, 0, -0.3), c + Vector3(0, 0, 0.5), R * 0.1, R * 0.095, 12, false)
			_cap(mb, _circle(c + Vector3(0, 0, 0.5), R * 0.095, 12), Vector3(0, 0, 1), steel)

	# ---- sail: stadium/teardrop section with flat sides, bevelled top, masts, windows
	var outl := _sail_outline(sc, tx)
	var z_root := R * 0.8
	var z_base := _deck(sy, R, d)
	var z_top := z_base + sh
	var levels := [[z_root, 1.0], [z_base, 1.0], [z_base + sh * 0.33, 1.0], [z_base + sh * 0.66, 1.0],
		[z_top - sh * 0.07, 1.0], [z_top - sh * 0.025, 0.95], [z_top - sh * 0.005, 0.86], [z_top, 0.74]]
	var srings := []
	for lv: Array in levels:
		var z: float = lv[0]
		var k: float = lv[1]
		var chord_k := 1.0 - 0.07 * clampf((z - z_base) / sh, 0.0, 1.0)
		var ring := PackedVector3Array()
		for p in outl:
			var py := p.y * chord_k
			# the bevel shrinks the thickness and the chord toward the top
			ring.append(Vector3(p.x * k, sy + py * (1.0 - (1.0 - k) * 0.35), z))
		srings.append(ring)
	var sail_col := func(p: Vector3) -> Color:
		var ao := lerpf(0.55, 1.0, smoothstep(z_base - 1.0, z_base + R * 0.4, p.z))
		return Color(ao, 1.0 if p.z < z_top - sh * 0.03 else 0.0, 0.45, 0.0)
	_loft(mb, srings, sail_col, false, func(p: Vector3) -> float: return p.z)
	_cap(mb, srings[srings.size() - 1], Vector3(0, 0, 1), Color(0.85, 0.0, 0.6, 0.0))
	# periscopes and masts out of the top, one bent
	mb.color = Color(0.8, 0.0, 0.8, 0.0)
	for k in 2:
		var my := sy + sc * (0.18 - 0.2 * float(k))
		var mr := R * (0.05 if k == 0 else 0.07)
		var mh := sh * rng.randf_range(0.12, 0.24)
		var a := Vector3(0, my, z_top - 0.5)
		var b := Vector3(0, my, z_top + mh)
		if k == 1 and rng.randf() < 0.5:
			var kink := a.lerp(b, 0.6)
			mb.cylinder(a, kink, mr, mr * 0.95, 8, false)
			mb.cylinder(kink, kink + Vector3(0, -0.6, 0.55).normalized() * mh * 0.5, mr * 0.95, mr * 0.9, 8)
		else:
			mb.cylinder(a, b, mr, mr * 0.85, 8)
	# bridge windows near the leading edge, both sides
	for w: Array in sail_windows(L, R, o):
		_rect(mb, w[0], Vector3(0, 0.75, 0), Vector3(0, 0, 0.55), w[1], Color(0.6, 0.0, 0.5, 1.0), float(nlit))
		nlit += 1

	# ---- dive planes: vertical plates (span X, chord along the axis, thin along Z)
	var pc := Color(0.85, 0.0, 0.45, 0.0)       # planes and fins: dark steel, little rust (no tan faces)
	if o.get("planes", "sail") == "sail":
		var pz := z_base + sh * 0.55
		var c0 := sy + sc * 0.02
		var c1 := sy + sc * 0.4
		for sg: float in [-1.0, 1.0]:
			var x0 := sg * tx * 0.6
			var x1 := sg * (tx + float(d["plane_span"]))
			_plate(mb, Vector3(x0, c0, pz), Vector3(x0, c1, pz), Vector3(x1, c1 - sc * 0.08, pz),
				Vector3(x1, c0 + sc * 0.08, pz), Vector3(0, 0, 1), maxf(R * 0.05, 0.9), pc)
	else:
		var by := L * 0.8
		var c0 := by - L * 0.025
		var c1 := by + L * 0.025
		var pz := R * 0.15
		for sg: float in [-1.0, 1.0]:
			var x0 := sg * R * 0.9
			var x1 := sg * (R + float(d["plane_span"]) * 0.8)
			_plate(mb, Vector3(x0, c0, pz), Vector3(x0, c1, pz), Vector3(x1, c1 - L * 0.012, pz),
				Vector3(x1, c0 + L * 0.004, pz), Vector3(0, 0, 1), maxf(R * 0.05, 0.9), pc)

	# ---- tail: cruciform or X fins on the stern cone, swept leading edge, trailing edge square
	for fa: float in fin_angles:
		var dir := Vector3(cos(fa), 0.0, sin(fa))
		var thick := Vector3(-sin(fa), 0.0, cos(fa))
		var tip: float = d["fin_tip"] * (1.12 if absf(fa - PI * 0.5) < 0.1 else 1.0)
		var ra := dir * radius_at(fy0, L, R) * 0.8 + Vector3(0, fy0, 0)
		var rb := dir * radius_at(fy1, L, R) * 0.8 + Vector3(0, fy1, 0)
		var ta := dir * tip + Vector3(0, fy0 + L * 0.003, 0)
		var tb := dir * tip + Vector3(0, fy0 + L * 0.034, 0)
		_plate(mb, ra, rb, tb, ta, thick, maxf(R * 0.075, 1.2), pc)
	# shaft boss under the stern tip (buried)
	mb.color = Color(0.5, 0.0, 0.8, 0.0)
	mb.cylinder(Vector3(0, -L * 0.012, 0), Vector3(0, L * 0.004, 0), R * 0.05, R * 0.075, 10)
	return mb.build()


## Low-poly tower for the mid-distance rows (40-250 m from the line): round hull (24 sides, ~20 rings), the
## sail, its planes or bow planes, the tail fins. No casing, openings or windows. Same frame, UV and vertex
## colours as mesh(), so it shares shaders/sub.gdshader (and the instance custom data).
static func filler_mesh(L: float, R: float, o := {}) -> ArrayMesh:
	var d := info(L, R, o)
	var mb := MeshBuilder.new()
	var sy: float = d["sail_y"]
	var sc: float = d["sail_c"]
	var sh: float = d["sail_h"]
	var tx: float = d["sail_tx"]
	var na := 24
	var ys := []
	for i in 7:
		var k := float(i) / 6.0
		ys.append(L * STERN * (0.55 * k * k + 0.45 * k))
	var y := L * STERN + 30.0
	while y < L * (1.0 - BOW) - 10.0:
		if absf(y - sy) > sc * 0.7:
			ys.append(y)
		y += 30.0
	for f: float in [-0.6, -0.5, 0.5, 0.6]:
		ys.append(sy + sc * f)
	for i in 8:
		var k := float(i) / 7.0
		ys.append(L * (1.0 - BOW) + L * BOW * (1.0 - pow(1.0 - k, 1.7)) * (1.0 if i < 7 else 0.994))
	ys.sort()
	var rings := []
	for yy: float in ys:
		var r := radius_at(yy, L, R)
		var ring := PackedVector3Array()
		for j in na:
			var a := -PI * 0.5 + TAU * float(j) / float(na)
			ring.append(Vector3(cos(a) * r, yy, sin(a) * r))
		rings.append(ring)
	var col := func(p: Vector3) -> Color:
		var ao := 1.0
		if p.z > R * 0.5:
			var dx := maxf(absf(p.x) - tx, 0.0)
			var dy := maxf(absf(p.y - sy) - sc * 0.5, 0.0)
			ao = lerpf(0.55, 1.0, smoothstep(0.0, R * 0.45, Vector2(dx, dy).length()))
		return Color(ao, 1.0, 0.35, 0.0)
	_loft(mb, rings, col)
	_cap(mb, rings[0], Vector3.DOWN, Color(0.5, 0.0, 0.6, 0.0))
	_cap(mb, rings[rings.size() - 1], Vector3.UP, Color(1.0, 1.0, 0.35, 0.0))
	# the sail: three levels of the real outline
	var outl := _sail_outline(sc, tx)
	var z_base := R + float(d["hc"]) + float(d["hump"]) * 0.6
	var z_top := z_base + sh
	var srings := []
	for lv: Array in [[R * 0.8, 1.0], [z_base, 1.0], [z_top - sh * 0.04, 1.0], [z_top, 0.78]]:
		var ring := PackedVector3Array()
		for p in outl:
			ring.append(Vector3(p.x * float(lv[1]), sy + p.y, lv[0]))
		srings.append(ring)
	var sail_col := func(p: Vector3) -> Color:
		return Color(lerpf(0.55, 1.0, smoothstep(z_base - 1.0, z_base + R * 0.4, p.z)), 1.0 if p.z < z_top - sh * 0.03 else 0.0, 0.45, 0.0)
	_loft(mb, srings, sail_col, false, func(p: Vector3) -> float: return p.z)
	_cap(mb, srings[srings.size() - 1], Vector3(0, 0, 1), Color(0.85, 0.0, 0.5, 0.0))
	var pc := Color(0.85, 0.0, 0.45, 0.0)
	if o.get("planes", "sail") == "sail":
		var pz := z_base + sh * 0.55
		for sg: float in [-1.0, 1.0]:
			var x0 := sg * tx * 0.6
			var x1 := sg * (tx + float(d["plane_span"]))
			_plate(mb, Vector3(x0, sy + sc * 0.02, pz), Vector3(x0, sy + sc * 0.4, pz), Vector3(x1, sy + sc * 0.32, pz),
				Vector3(x1, sy + sc * 0.1, pz), Vector3(0, 0, 1), maxf(R * 0.05, 0.9), pc)
	else:
		var by := L * 0.8
		for sg: float in [-1.0, 1.0]:
			var x0 := sg * R * 0.9
			var x1 := sg * (R + float(d["plane_span"]) * 0.8)
			_plate(mb, Vector3(x0, by - L * 0.025, R * 0.15), Vector3(x0, by + L * 0.025, R * 0.15),
				Vector3(x1, by + L * 0.013, R * 0.15), Vector3(x1, by - L * 0.021, R * 0.15), Vector3(0, 0, 1), maxf(R * 0.05, 0.9), pc)
	var fy0: float = d["fin_y0"]
	var fy1: float = d["fin_y1"]
	for fa: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dir := Vector3(cos(fa), 0.0, sin(fa))
		var tip: float = d["fin_tip"]
		_plate(mb, dir * radius_at(fy0, L, R) * 0.8 + Vector3(0, fy0, 0), dir * radius_at(fy1, L, R) * 0.8 + Vector3(0, fy1, 0),
			dir * tip + Vector3(0, fy0 + L * 0.034, 0), dir * tip + Vector3(0, fy0 + L * 0.003, 0),
			Vector3(-sin(fa), 0.0, cos(fa)), maxf(R * 0.075, 1.2), pc)
	return mb.build()


static func _circle(c: Vector3, r: float, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for j in n:
		var a := TAU * float(j) / float(n)
		out.append(c + Vector3(cos(a) * r, sin(a) * r, 0.0))
	return out


## The shared material (shaders/sub.gdshader). INSTANCE_CUSTOM: r = seed 0..1, g = seabed height
## along the axis / 100 (mesh units).
static func material(amber := 0.0) -> ShaderMaterial:
	return Mats.make("sub", {"amber_fraction": amber})
