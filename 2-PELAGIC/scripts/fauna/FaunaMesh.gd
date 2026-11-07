extends RefCounted
## Procedural fauna meshes (cached). Fish space: forward +X, up +Y, side +Z, unit length (tail tip x = -0.5,
## snout x = +0.5). Vertex COLOR: r fin/skin, g dorsoventral (0 belly .. 1 back), b turtle shell, a tip weight.
## UV2: x animated part (0 body, 1 front flipper, 2 rear flipper, 3 head), y side (-1 / +1).

const BODY := Color(0.0, 0.0, 0.0, 0.0)
const FIN := Color(1.0, 0.5, 0.0, 0.0)
const SKIN := Color(1.0, 0.5, 0.0, 0.0)

## Ring profiles (x, centre y, half height h, half width w), snout apex, tail apex x, fins in the x-y plane.
const PROFILES := {
	"slender": {
		"x": [0.47, 0.42, 0.32, 0.18, 0.02, -0.14, -0.26, -0.33],
		"y": [-0.005, 0.0, 0.002, 0.004, 0.003, 0.0, 0.0, 0.0],
		"h": [0.025, 0.055, 0.082, 0.095, 0.09, 0.07, 0.042, 0.026],
		"w": [0.02, 0.038, 0.05, 0.054, 0.05, 0.038, 0.022, 0.013],
		"lo": [3, 6],
		"nose": Vector3(0.5, -0.008, 0.0), "tail": -0.35,
		"caudal": [Vector2(-0.31, 0.0), Vector2(-0.31, 0.03), Vector2(-0.5, 0.14), Vector2(-0.41, 0.0),
			Vector2(-0.5, -0.13), Vector2(-0.31, -0.03)],
		"caudal_lo": [Vector2(-0.3, 0.0), Vector2(-0.5, 0.14), Vector2(-0.41, 0.0), Vector2(-0.5, -0.13)],
		"dorsal": [Vector2(0.12, 0.09), Vector2(-0.05, 0.165), Vector2(-0.07, 0.075)],
		"anal": [Vector2(-0.08, -0.068), Vector2(-0.21, -0.105), Vector2(-0.2, -0.042)],
		"pec": [Vector3(0.27, -0.025, 0.04), Vector3(0.16, -0.06, 0.09), Vector3(0.23, -0.04, 0.045)],
	},
	"deep": {
		"x": [0.46, 0.40, 0.30, 0.16, 0.0, -0.14, -0.25, -0.32],
		"y": [-0.02, -0.01, 0.0, 0.0, -0.005, -0.005, 0.0, 0.0],
		"h": [0.04, 0.09, 0.14, 0.165, 0.155, 0.12, 0.06, 0.03],
		"w": [0.025, 0.045, 0.06, 0.065, 0.06, 0.045, 0.025, 0.014],
		"lo": [3, 6],
		"nose": Vector3(0.5, -0.025, 0.0), "tail": -0.34,
		"caudal": [Vector2(-0.3, 0.0), Vector2(-0.3, 0.035), Vector2(-0.52, 0.18), Vector2(-0.41, 0.0),
			Vector2(-0.52, -0.17), Vector2(-0.3, -0.035)],
		"caudal_lo": [Vector2(-0.29, 0.0), Vector2(-0.52, 0.18), Vector2(-0.41, 0.0), Vector2(-0.52, -0.17)],
		"dorsal": [Vector2(0.08, 0.15), Vector2(0.02, 0.23), Vector2(-0.24, 0.12), Vector2(-0.24, 0.06)],
		"anal": [Vector2(-0.04, -0.14), Vector2(-0.1, -0.2), Vector2(-0.25, -0.1), Vector2(-0.25, -0.058)],
		"pec": [Vector3(0.25, -0.04, 0.05), Vector3(0.13, -0.08, 0.1), Vector3(0.2, -0.06, 0.055)],
	},
	"shark": {
		"x": [0.47, 0.43, 0.36, 0.26, 0.14, 0.02, -0.08, -0.17, -0.24, -0.30, -0.34],
		"y": [-0.008, -0.004, 0.0, 0.002, 0.003, 0.003, 0.002, 0.002, 0.003, 0.005, 0.008],
		"h": [0.018, 0.032, 0.048, 0.062, 0.068, 0.066, 0.058, 0.044, 0.03, 0.02, 0.014],
		"w": [0.022, 0.04, 0.056, 0.066, 0.07, 0.066, 0.056, 0.04, 0.026, 0.017, 0.012],
		"nose": Vector3(0.5, -0.006, 0.0), "tail": -0.355,
		"caudal": [Vector2(-0.31, 0.008), Vector2(-0.31, 0.022), Vector2(-0.5, 0.17), Vector2(-0.46, 0.06),
			Vector2(-0.41, 0.0), Vector2(-0.45, -0.1), Vector2(-0.31, -0.008)],
		"dorsal": [Vector2(0.10, 0.062), Vector2(-0.02, 0.17), Vector2(-0.05, 0.09), Vector2(-0.07, 0.058)],
		"dorsal2": [Vector2(-0.2, 0.042), Vector2(-0.255, 0.075), Vector2(-0.25, 0.03)],
		"anal": [Vector2(-0.2, -0.035), Vector2(-0.26, -0.062), Vector2(-0.25, -0.026)],
		"pec": [Vector3(0.22, -0.035, 0.05), Vector3(0.05, -0.085, 0.25), Vector3(0.11, -0.055, 0.12),
			Vector3(0.14, -0.04, 0.055)],
		"pelvic": [Vector3(-0.08, -0.055, 0.03), Vector3(-0.14, -0.08, 0.07), Vector3(-0.13, -0.05, 0.03)],
	},
}

static var _cache := {}


class Builder:
	var p := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var u := PackedVector2Array()
	var idx := PackedInt32Array()

	func vert(pos: Vector3, col: Color, uv2: Vector2) -> int:
		p.append(pos)
		n.append(Vector3.ZERO)
		c.append(col)
		u.append(uv2)
		return p.size() - 1

	## Smooth triangle, wound so that its front face points away from `inside`.
	func tri(a: int, b: int, d: int, inside: Vector3) -> void:
		var fn := (p[d] - p[a]).cross(p[b] - p[a])
		if fn.dot((p[a] + p[b] + p[d]) / 3.0 - inside) < 0.0:
			var tmp := b
			b = d
			d = tmp
			fn = -fn
		idx.append(a)
		idx.append(b)
		idx.append(d)
		n[a] = n[a] + fn
		n[b] = n[b] + fn
		n[d] = n[d] + fn

	## Flat double-sided polygon (fan from pts[0]); vertices listed in `tips` get COLOR.a = 1.
	func fin(pts: Array, col: Color, tips: Array = [], uv2 := Vector2.ZERO) -> void:
		var fn: Vector3 = (pts[2] - pts[0]).cross(pts[1] - pts[0]).normalized()
		for s in [1.0, -1.0]:
			var base := p.size()
			for i in pts.size():
				var cc := col
				if i in tips:
					cc.a = 1.0
				vert(pts[i], cc, uv2)
				n[base + i] = fn * s
			for i in range(1, pts.size() - 1):
				idx.append(base)
				if s > 0.0:
					idx.append(base + i)
					idx.append(base + i + 1)
				else:
					idx.append(base + i + 1)
					idx.append(base + i)

	## Tube through ring centres: ra / rl = radius above / below the centre, rb = half width.
	## cap0 / cap1: apex points closing the ends, or null to leave the end open (hidden inside another part).
	func tube(ctr: Array, ra: Array, rl: Array, rb: Array, sides: int, col: Color, uv2: Vector2,
			cap0, cap1, limb := false, shell := false) -> void:
		var m := ctr.size()
		var base := p.size()
		for i in m:
			var t: Vector3 = (ctr[mini(i + 1, m - 1)] - ctr[maxi(i - 1, 0)]).normalized()
			var up := (Vector3.UP - t * t.dot(Vector3.UP)).normalized()
			var sd := t.cross(up)
			for k in sides:
				var ph := TAU * float(k) / float(sides)
				var cy := cos(ph)
				var r_up: float = ra[i] if cy >= 0.0 else rl[i]
				var pos: Vector3 = ctr[i] + up * (r_up * cy) + sd * (float(rb[i]) * sin(ph))
				var cc := col
				cc.g = 0.5 + 0.5 * cy
				cc.a = float(i) / float(m - 1) if limb else 0.0
				if shell:
					cc.b = smoothstep(-0.3, 0.15, cy)
				vert(pos, cc, uv2)
		for i in m - 1:
			var inside: Vector3 = (ctr[i] + ctr[i + 1]) * 0.5
			for k in sides:
				var k1 := (k + 1) % sides
				var a := base + i * sides + k
				var b := base + i * sides + k1
				var e := base + (i + 1) * sides + k1
				var d := base + (i + 1) * sides + k
				tri(a, b, e, inside)
				tri(a, e, d, inside)
		if cap0 != null:
			_cap(cap0, base, sides, ctr[0], col, uv2, 0.0)
		if cap1 != null:
			_cap(cap1, base + (m - 1) * sides, sides, ctr[m - 1], col, uv2, 1.0 if limb else 0.0)

	func _cap(apex: Vector3, ring: int, sides: int, inside: Vector3, col: Color, uv2: Vector2, tip: float) -> void:
		var cc := col
		cc.g = 0.5
		cc.a = tip
		var ai := vert(apex, cc, uv2)
		for k in sides:
			tri(ai, ring + k, ring + (k + 1) % sides, inside)

	func commit() -> ArrayMesh:
		for i in n.size():
			n[i] = n[i].normalized()
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = p
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV2] = u
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return mesh


## kind: "slender" (sardine, fusilier, wrasse), "deep" (jacks, reef fish), "shark", "turtle"; lod 0 = hi, 1 = lo.
static func get_mesh(kind: String, lod: int) -> ArrayMesh:
	var key := "%s%d" % [kind, lod]
	if not _cache.has(key):
		if kind == "turtle":
			_cache[key] = _turtle()
		else:
			_cache[key] = _fish(PROFILES[kind], lod, 10 if kind == "shark" else 8)
	return _cache[key]


static func _fish(pr: Dictionary, lod: int, sides: int) -> ArrayMesh:
	var b := Builder.new()
	var ids: Array = pr["lo"] if lod > 0 else range(pr["x"].size())
	var ctr := []
	var hh := []
	var ww := []
	for i in ids:
		ctr.append(Vector3(pr["x"][i], pr["y"][i], 0.0))
		hh.append(pr["h"][i])
		ww.append(pr["w"][i])
	var tail := Vector3(pr["tail"], 0.0, 0.0)
	b.tube(ctr, hh, hh, ww, 4 if lod > 0 else sides, BODY, Vector2.ZERO, pr["nose"], tail)
	if lod > 0:
		b.fin(_flat(pr["caudal_lo"]), FIN)
		return b.commit()
	var shark := pr.has("pelvic")
	b.fin(_flat(pr["caudal"]), FIN, [2, 5] if shark else [])
	b.fin(_flat(pr["dorsal"]), FIN, [1])
	b.fin(_flat(pr["anal"]), FIN, [1])
	b.fin(pr["pec"], FIN, [1])
	b.fin(_mirror(pr["pec"]), FIN, [1])
	if shark:
		b.fin(_flat(pr["dorsal2"]), FIN, [1])
		b.fin(pr["pelvic"], FIN)
		b.fin(_mirror(pr["pelvic"]), FIN)
	return b.commit()


## Sea turtle, unit length (beak +0.5, shell rear -0.42), flippers flat and swept back.
static func _turtle() -> ArrayMesh:
	var b := Builder.new()
	var ctr := []
	for x in [0.30, 0.26, 0.18, 0.08, -0.04, -0.16, -0.27, -0.35, -0.40]:
		ctr.append(Vector3(x, 0.0, 0.0))
	var top := [0.035, 0.07, 0.10, 0.12, 0.125, 0.115, 0.09, 0.06, 0.025]
	var bot := [0.02, 0.035, 0.045, 0.05, 0.05, 0.048, 0.04, 0.03, 0.015]
	var wid := [0.10, 0.17, 0.22, 0.245, 0.245, 0.225, 0.18, 0.12, 0.05]
	b.tube(ctr, top, bot, wid, 14, BODY, Vector2.ZERO, Vector3(0.315, 0.0, 0.0), Vector3(-0.42, 0.0, 0.0), false, true)
	var hc := [Vector3(0.22, 0.0, 0.0), Vector3(0.30, 0.012, 0.0), Vector3(0.37, 0.018, 0.0),
		Vector3(0.43, 0.016, 0.0), Vector3(0.475, 0.008, 0.0)]
	var hh := [0.045, 0.05, 0.054, 0.045, 0.026]
	b.tube(hc, hh, hh, [0.05, 0.056, 0.06, 0.05, 0.03], 10, SKIN, Vector2(3.0, 0.0), null, Vector3(0.505, 0.0, 0.0))
	for s in [-1.0, 1.0]:
		var fc := [Vector3(0.17, -0.01, 0.15 * s), Vector3(0.14, -0.012, 0.28 * s), Vector3(0.08, -0.016, 0.42 * s),
			Vector3(0.0, -0.02, 0.53 * s), Vector3(-0.07, -0.025, 0.6 * s)]
		var ft := [0.025, 0.018, 0.013, 0.009, 0.004]
		b.tube(fc, ft, ft, [0.07, 0.085, 0.07, 0.045, 0.014], 8, SKIN, Vector2(1.0, s), null,
			Vector3(-0.09, -0.026, 0.62 * s), true)
		var rc := [Vector3(-0.30, -0.02, 0.10 * s), Vector3(-0.36, -0.025, 0.16 * s), Vector3(-0.41, -0.03, 0.21 * s)]
		var rt := [0.018, 0.012, 0.006]
		b.tube(rc, rt, rt, [0.05, 0.055, 0.035], 8, SKIN, Vector2(2.0, s), null, Vector3(-0.44, -0.03, 0.235 * s), true)
	return b.commit()


static func _flat(pts: Array) -> Array:
	var out := []
	for q in pts:
		out.append(Vector3(q.x, q.y, 0.0))
	return out


static func _mirror(pts: Array) -> Array:
	var out := []
	for q in pts:
		out.append(Vector3(q.x, q.y, -q.z))
	return out
