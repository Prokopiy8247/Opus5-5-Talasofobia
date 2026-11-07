extends RefCounted
## Reef dressing: places prop variants on surface samples and chunks them into spatial cells, one MultiMesh per
## (variant, cell), so visibility ranges act per cell and nothing near the player is ever in a fade band.
## Sample = [position, normal, depth, where, cavity, ...]; where: 0 face, 1 crest, 2 reef top, 3 roof top/front,
## 4 roof underside (props hang), 5 roof rim (the lower front edge that forms the silhouette seen from below).
## Life grows in patches (a low-frequency mask leaves bare rock between them) and each patch has its own mix of
## species (a second, broader zone field). Steep rock gets encrusting colonies and tiered plates, never round heads;
## the crest and the lip rim carry big gorgonian trees, black coral and whips that stand out against the bright water.

const ReefProps := preload("res://scripts/reef/ReefProps.gd")
const ReefRoof := preload("res://scripts/reef/ReefRoof.gd")
const CELL := 90.0
const PLATE_CAV := 0.25       # no plates in hollows (a lit shelf top in a shaded hollow reads as a pale chip)
const PLATE_MAX := 3          # at most this many plates per 5 m cell (tiers, not confetti)
const ANCHOR_CELL := 7.0      # hash cell for the spacing of the lip silhouettes (>= their largest gap)

## Offline probes only: when `collect` is set, every placed item is also recorded as [key, origin, scale, tag].
static var collect := false
static var collected: Array = []

const HEAD_COLS := [Color(0.5, 0.42, 0.28), Color(0.4, 0.35, 0.3), Color(0.36, 0.4, 0.27), Color(0.48, 0.37, 0.34),
	Color(0.55, 0.5, 0.38), Color(0.3, 0.27, 0.24)]
const CRUST_COLS := [Color(0.52, 0.4, 0.3), Color(0.42, 0.4, 0.3), Color(0.5, 0.34, 0.36), Color(0.58, 0.5, 0.36),
	Color(0.36, 0.38, 0.32)]
const SPONGE_COLS := [Color(0.5, 0.28, 0.18), Color(0.6, 0.4, 0.22), Color(0.4, 0.25, 0.36), Color(0.62, 0.52, 0.3),
	Color(0.36, 0.3, 0.27)]
const TUBE_COLS := [Color(0.72, 0.48, 0.18), Color(0.46, 0.28, 0.48), Color(0.66, 0.62, 0.32), Color(0.56, 0.32, 0.27)]
const PLATE_COLS := [Color(0.37, 0.3, 0.21), Color(0.32, 0.29, 0.23), Color(0.41, 0.35, 0.26), Color(0.29, 0.26, 0.22),
	Color(0.38, 0.32, 0.28)]
const FAN_COLS := [Color(0.45, 0.14, 0.3), Color(0.66, 0.37, 0.16), Color(0.7, 0.6, 0.27), Color(0.4, 0.22, 0.46),
	Color(0.6, 0.26, 0.2), Color(0.2, 0.16, 0.14)]
const SOFT_COLS := [Color(0.62, 0.36, 0.44), Color(0.5, 0.34, 0.52), Color(0.7, 0.6, 0.48), Color(0.66, 0.42, 0.3)]
const ROD_COLS := [Color(0.56, 0.44, 0.28), Color(0.46, 0.28, 0.38), Color(0.3, 0.26, 0.22), Color(0.64, 0.5, 0.34)]
## Big silhouettes: gorgonian trees (dark red-brown), black coral (near black), whips (rust, ochre).
const TREE_COLS := [Color(0.42, 0.17, 0.12), Color(0.3, 0.17, 0.11), Color(0.5, 0.3, 0.14), Color(0.36, 0.12, 0.16)]
const BLACK_COLS := [Color(0.14, 0.12, 0.09), Color(0.2, 0.17, 0.11), Color(0.16, 0.15, 0.13)]
const WHIP_COLS := [Color(0.6, 0.24, 0.12), Color(0.66, 0.5, 0.22), Color(0.36, 0.2, 0.16), Color(0.5, 0.42, 0.36)]

## Prop variants: name -> [mesh, material, visibility end (m), casts sun shadow]. Built once by the wall, kept as meta
## on the Reef node. No prop casts sun shadows: under the high sun a shelf's shadow falls down the steep rock as a long,
## hard-edged dark trapezoid (a 'black square'); the plates' own AO and dark undersides ground them instead.
static func variants() -> Dictionary:
	var _variants := {}
	var mats := {}
	for k in 4:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/reef_prop.gdshader")
		m.set_shader_parameter("kind", k)
		mats[k] = m
	var wallm := ShaderMaterial.new()
	wallm.shader = load("res://shaders/reef_prop.gdshader")
	wallm.set_shader_parameter("kind", 2)
	wallm.set_shader_parameter("wall_plate", true)
	var fanm := ShaderMaterial.new()
	fanm.shader = load("res://shaders/reef_fan.gdshader")
	# sponges hanging under the lip roof get the roof's side light from the open water (reef_prop.gdshader roof_*)
	var roofm := ShaderMaterial.new()
	roofm.shader = load("res://shaders/reef_prop.gdshader")
	roofm.set_shader_parameter("kind", 1)
	roofm.set_shader_parameter("roof_open", 1.0)
	roofm.set_shader_parameter("roof_side", 3.2)     # same as the roof rock (Beat03_Lip)
	roofm.set_shader_parameter("roof_centre", ReefRoof.C)
	roofm.set_shader_parameter("roof_radius", ReefRoof.R0)
	for s in 3:
		_variants["head%d" % s] = [ReefProps.coral_head(11 + s), mats[0], 420.0, false]
		_variants["barrel%d" % s] = [ReefProps.barrel(21 + s), mats[1], 330.0, false]
		_variants["tubes%d" % s] = [ReefProps.tubes(31 + s), mats[1], 230.0, false]
		_variants["rtubes%d" % s] = [_variants["tubes%d" % s][0], roofm, 230.0, false]
		_variants["plate%d" % s] = [ReefProps.plate(41 + s), wallm, 300.0, false]
		_variants["bush%d" % s] = [ReefProps.bush(51 + s), mats[3], 170.0, false]
		_variants["soft%d" % s] = [ReefProps.bush(71 + s, 9, 0.55, 2.4), mats[3], 170.0, false]
		_variants["whips%d" % s] = [ReefProps.whips(81 + s), mats[3], 220.0, false]
		_variants["tree%d" % s] = [ReefProps.tree(91 + s, 0.85, 1.9, 1.0), mats[3], 280.0, false]
	for s in 2:
		_variants["table%d" % s] = [ReefProps.table(61 + s), mats[2], 320.0, false]
		_variants["black%d" % s] = [ReefProps.tree(101 + s, 0.2, 1.1, 1.6), mats[3], 260.0, false]
	_variants["fan"] = [ReefProps.fan(), fanm, 280.0, false]
	return _variants

## Place props on samples; returns the number placed and prints one PELAGIC reef dress line with the counts.
static func dress(root: Node3D, pts: Array, seed: int, vs: Dictionary) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mask := FastNoiseLite.new()        # where life grows (patches, bare rock between)
	mask.seed = seed + 5; mask.frequency = 1.0 / 34.0; mask.fractal_octaves = 2
	var zone := FastNoiseLite.new()        # which species dominate a stretch of reef
	zone.seed = seed + 11; zone.frequency = 1.0 / 95.0; zone.fractal_octaves = 1
	var cells := {}
	for k in vs:
		cells[k] = {}
	var st := {"plates": 0, "tiers": 0, "outline": 0, "rim": 0, "front": 0, "crest": 0, "old_plates": 0.0}
	# face samples by 2.5 m cell (plates grow in tiers on real rock below each other); the lip's rim samples
	var grid := {}
	var rim_idx: Array = []
	var low_idx: Array = []       # the lip's lower rock (rim, tier lips, underside): where its outline can be
	for i in pts.size():
		var q: Array = pts[i]
		var wq := int(q[3])
		if wq == 0:
			var g := Vector3i(floori(q[0].x / 2.5), floori(q[0].y / 2.5), floori(q[0].z / 2.5))
			if not grid.has(g):
				grid[g] = []
			grid[g].append(i)
		elif wq >= 3:
			if wq == 5:
				rim_idx.append(i)
			if (q[1] as Vector3).y < 0.5:
				low_idx.append(i)
	var count := 0
	var used := {}        # lip samples that became silhouette anchors
	if not rim_idx.is_empty():
		count += _lip_silhouettes(cells, pts, low_idx, rim_idx, rng, seed, used, st)
	var plate_cells := {}     # plates per 5 m cell
	for pi in pts.size():
		if used.has(pi):
			continue
		var p: Array = pts[pi]
		var pos: Vector3 = p[0]
		var nrm: Vector3 = p[1]
		var depth: float = p[2]
		var where: int = p[3]
		var cav: float = p[4]
		if cav > 0.4:
			continue
		var rich := 1.0 - smoothstep(25.0, 170.0, depth)
		if collect and where == 0 and nrm.y > -0.45 and nrm.y <= 0.55 and depth > 14.0:
			# the plate count the original (pre-polish) dressing placed here: 10 % of the kept face samples
			var pd0 := PathDef.curve.get_closest_point(pos).distance_to(pos)
			if pd0 >= 11.0:
				st["old_plates"] += 0.1 * (0.1 + 0.9 * (1.0 - smoothstep(30.0, 150.0, pd0))) * (0.25 + 0.75 * rich)
		var patch := smoothstep(-0.28, 0.32, mask.get_noise_3d(pos.x, pos.y * 1.4, pos.z))
		# big trees and whips on the lip front and the crest edge (not masked away; the rim has its own pass above)
		var front := where == 3 and absf(nrm.y) < 0.6
		var crest_edge := where == 1 and nrm.y > 0.1 and nrm.y < 0.9
		var p_sil := 0.12 if front else (0.2 * (0.35 + 0.8 * patch) if crest_edge else 0.0)
		# density without the path term first (cheap), the path distance only for samples that survive it
		# (the shallow reef top keeps a richer floor: the title shot looks over it)
		var keep := lerpf(0.4, 1.3, patch) if where >= 3 else (0.25 + 0.75 * rich) * (0.75 if where == 1 else 1.0) * lerpf(0.35 if where == 2 else 0.1, 1.35, patch)
		var r_sil := rng.randf()
		var r_keep := rng.randf()
		if r_sil >= p_sil and r_keep > keep:
			continue
		var pd := PathDef.curve.get_closest_point(pos).distance_to(pos)
		if pd < (13.0 if where == 4 else 11.0):
			continue
		var near := 1.0 - smoothstep(30.0, 150.0, pd)
		if pd > 15.0 and r_sil < p_sil * (0.15 + 0.85 * near):
			var tag := "front" if front else "crest"
			var ns := _silhouette(cells, pos, nrm, rng, front, pd, tag)
			st[tag] += ns
			count += ns
			continue
		if r_keep > keep * ((0.2 + 0.8 * near) if where >= 3 else (0.1 + 0.9 * near)):
			continue
		var z := zone.get_noise_3d(pos.x, pos.y * 0.6, pos.z)
		var s3 := str(rng.randi() % 3)
		var items: Array = []        # [key, [transform, colour]]
		if where == 4 or where == 5:
			# hanging from the roof: tube and rope sponges, sea rods and whips (short over the path), small fans
			var down := -Vector3.UP
			var lmax := clampf(pd - 12.0, 0.5, 1.0 if pd < 22.0 else 2.6)
			var w4 := _pick({"tubes": 0.35, "bush": 0.3, "whips": 0.2, "fan": 0.15}, rng.randf())
			match w4:
				"tubes": items.append(["rtubes" + s3, [Transform3D(_basis_on(down, rng, minf(lmax, 1.8) * rng.randf_range(0.6, 1.0), 0.25, 1.0), pos + Vector3.UP * 0.1), _col(TUBE_COLS, rng, 0.8)]])
				"bush": items.append(["bush" + s3, [Transform3D(_basis_on(down, rng, lmax * rng.randf_range(0.6, 1.0), 0.3, 1.0), pos + Vector3.UP * 0.1), _col(ROD_COLS, rng, 0.7)]])
				"whips": items.append(["whips" + s3, [Transform3D(_basis_on(down, rng, lmax * rng.randf_range(0.7, 1.0), 0.35, 1.0), pos + Vector3.UP * 0.05), _col(WHIP_COLS, rng, 0.7)]])
				_: items.append(["fan", [_fan_xf(pos, nrm, rng, 0.3, true, minf(lmax, 1.2)), _col(FAN_COLS, rng, 0.8)]])
		elif nrm.y > 0.55 or where == 1 or where == 2:
			# reef top, crest, roof top and ledge shelves; round heads only where the rock faces up. The rounded crest
			# edge is the skyline seen from the face below: few heads (a row of similar domes reads as potatoes on a
			# shelf) of mixed sizes, more rods, whips, fans and sponges of mixed heights; the flat crest top keeps its
			# heads (the title shot looks down on it)
			var skyline := where == 1 and nrm.y < 0.85
			var w := {"head": 0.3, "table": 0.1 if (where == 2 and depth < 30.0) else 0.0, "barrel": 0.1, "tubes": 0.18,
				"soft": 0.1, "bush": 0.1, "fan": 0.12, "whips": 0.0}
			if skyline:
				w = {"head": 0.12, "table": 0.0, "barrel": 0.07, "tubes": 0.1, "soft": 0.18, "bush": 0.19, "fan": 0.2, "whips": 0.14}
			if z < -0.2:
				w["barrel"] *= 2.2; w["tubes"] *= 1.6; w["fan"] *= 0.5
			elif z > 0.25:
				w["soft"] *= 1.8; w["fan"] *= 1.6; w["head"] *= 0.6; w["whips"] *= 1.5
			var key := _pick(w, rng.randf())
			if key == "head" and nrm.y < 0.3:
				key = "crust"
			match key:
				"head":
					var s := rng.randf_range(0.6, 1.9) * (1.0 + 0.4 * rich) * (1.5 if rng.randf() < 0.08 else 1.0)
					if skyline:
						s = lerpf(0.4, 2.4, pow(rng.randf(), 1.7)) * (1.0 + 0.25 * rich)     # mostly small, a few big
					# deeper heads a little darker: seen from above on a ledge, a sunlit dome is the palest thing around
					items.append(["head" + s3, [Transform3D(_basis_on(nrm, rng, s, 0.25, 0.7), pos - nrm * 0.18 * s), _col(HEAD_COLS, rng, lerpf(1.0, 0.8, smoothstep(20.0, 70.0, depth)))]])
				"crust":
					items.append(["head" + s3, [_crust_xf(pos, nrm, rng, rng.randf_range(0.5, 1.3)), _col(CRUST_COLS, rng)]])
				"table":
					var s := rng.randf_range(0.7, 1.8)
					items.append(["table" + str(rng.randi() % 2), [Transform3D(_basis_on(nrm, rng, s, 0.1, 0.9), pos), _col(PLATE_COLS, rng)]])
				"barrel":
					items.append(["barrel" + s3, [Transform3D(_basis_on(nrm, rng, rng.randf_range(0.7, 1.5) * (1.35 if rng.randf() < 0.12 else 1.0), 0.3, 0.6), pos - nrm * 0.15), _col(SPONGE_COLS, rng)]])
				"tubes":
					items.append(["tubes" + s3, [Transform3D(_basis_on(nrm, rng, rng.randf_range(0.6, 1.4), 0.3, 0.6), pos - nrm * 0.05), _col(TUBE_COLS, rng)]])
				"soft":
					items.append(["soft" + s3, [Transform3D(_basis_on(nrm, rng, rng.randf_range(0.8, 1.6), 0.25, 0.6), pos - nrm * 0.05), _col(SOFT_COLS, rng)]])
				"bush":
					items.append(["bush" + s3, [Transform3D(_basis_on(nrm, rng, rng.randf_range(0.8, 1.9) * (1.3 if skyline else 1.0), 0.25, 0.7), pos - nrm * 0.05), _col(ROD_COLS, rng)]])
				"whips":
					items.append(["whips" + s3, [Transform3D(_basis_on(nrm, rng, rng.randf_range(1.2, 2.4), 0.3, 0.5), pos - nrm * 0.05), _col(WHIP_COLS, rng)]])
				_:
					items.append(["fan", [_fan_xf(pos, nrm, rng, rich, false), _col(FAN_COLS, rng)]])
		elif nrm.y > -0.45:
			# the vertical face: fans, sponges, soft corals, encrusting colonies, tiered plates in the deeper part (not in
			# hollows, at most PLATE_MAX per 5 m cell); sponges grow up toward the light (seen from the path as tubes and
			# vases, not as mouths staring out)
			var w := {"plate": 0.035 if (depth > 14.0 and cav <= PLATE_CAV) else 0.0, "fan": 0.2, "barrel": 0.07, "tubes": 0.08,
				"soft": 0.17, "bush": 0.13, "crust": 0.12, "whips": 0.05}
			if z < -0.2:
				w["barrel"] *= 2.0; w["tubes"] *= 1.8; w["fan"] *= 0.55
			elif z > 0.25:
				w["fan"] *= 1.5; w["soft"] *= 1.4; w["whips"] *= 1.6
			else:
				w["crust"] *= 1.4
			match _pick(w, rng.randf()):
				"plate":
					if _plate_room(plate_cells, pos):
						var s := rng.randf_range(1.0, 2.1) * (1.0 + 0.25 * smoothstep(20.0, 80.0, depth))
						items.append(["plate" + s3, [_plate_xf(pos, nrm, rng, s), _plate_col(rng, cav)]])
						st["plates"] += 1
						# a tier of one or two smaller shelves growing on the rock just below
						for j in _tier(pts, grid, pos, nrm, rng):
							var q: Array = pts[j]
							if not _plate_room(plate_cells, q[0]):
								break
							s *= rng.randf_range(0.7, 0.9)
							items.append(["plate" + str(rng.randi() % 3), [_plate_xf(q[0], q[1], rng, s), _plate_col(rng, q[4])]])
							st["plates"] += 1
							st["tiers"] += 1
				"fan":
					items.append(["fan", [_fan_xf(pos, nrm, rng, rich, false), _col(FAN_COLS, rng)]])
				"barrel":
					if nrm.y < -0.15:
						# under an overhang a vase that clears the rock juts out like a pipe: tube sponges there instead
						# (same random draws as a barrel, so the rest of the dressing is unchanged)
						items.append(["tubes" + s3, [Transform3D(_basis_on(nrm, rng, rng.randf_range(0.6, 1.3), 0.25, 0.15), pos - nrm * 0.1), _col(TUBE_COLS, rng)]])
					else:
						items.append(["barrel" + s3, [_barrel_wall_xf(pos, nrm, rng, rng.randf_range(0.6, 1.4)), _col(SPONGE_COLS, rng)]])
				"tubes":
					items.append(["tubes" + s3, [Transform3D(_basis_on(nrm, rng, rng.randf_range(0.6, 1.3), 0.25, 0.15), pos - nrm * 0.1), _col(TUBE_COLS, rng)]])
				"soft":
					items.append(["soft" + s3, [Transform3D(_basis_on(nrm, rng, rng.randf_range(0.8, 1.5), 0.25, 0.4), pos - nrm * 0.05), _col(SOFT_COLS, rng)]])
				"bush":
					items.append(["bush" + s3, [Transform3D(_basis_on(nrm, rng, rng.randf_range(0.9, 2.2), 0.25, 0.35), pos - nrm * 0.05), _col(ROD_COLS, rng)]])
				"whips":
					items.append(["whips" + s3, [Transform3D(_basis_on(nrm, rng, rng.randf_range(1.0, 2.0), 0.3, 0.55), pos - nrm * 0.05), _col(WHIP_COLS, rng)]])
				_:
					items.append(["head" + s3, [_crust_xf(pos, nrm, rng, rng.randf_range(0.5, 1.4)), _col(CRUST_COLS, rng)]])
		else:
			continue
		for it in items:
			_add(cells, it[0], it[1])
			count += 1
	for k in vs:
		var v: Array = vs[k]
		var d: Dictionary = cells[k]
		for c in d:
			_mm(root, v[0], v[1], d[c], v[2], v.size() > 3 and v[3])
	var old := (", original rule ~%d" % roundi(st["old_plates"])) if collect else ""
	print("PELAGIC reef dress: %d props from %d samples; plates %d (%d in tiers)%s; silhouettes: lip outline %d + rim %d (from %d rim samples), lip front %d, crest %d" % [
		count, pts.size(), st["plates"], st["tiers"], old, st["outline"], st["rim"], rim_idx.size(), st["front"], st["crest"]])
	return count

## The lip's backlit silhouettes. Seen from the path under the lip, the dark roof meets the light along the lowest rock
## in each direction (tier lips and hanging masses as much as the rim itself), so the anchors come from the viewpoints:
## for path points every 8 m under (or entering) the lip, the lowest sample (in elevation angle) in each 1.5-degree
## azimuth bin lies on that outline (unless it is almost overhead). Trees there lean away from the viewer and droop,
## their crowns across the line of sight, so they hang against the light. Anchors keep 2.4-5 m apart (a noise clumps
## them into groves), so their number follows the length of the outline, not how densely the lip is sampled; the rest
## of the rim gets a sparser fringe (3.5-7 m) for the views from afar. Returns the number placed; marks the anchors in
## `used`.
static func _lip_silhouettes(cells: Dictionary, pts: Array, low_idx: Array, rim_idx: Array, rng: RandomNumberGenerator, seed: int, used: Dictionary, st: Dictionary) -> int:
	var clump := FastNoiseLite.new()
	clump.seed = seed + 23; clump.frequency = 1.0 / 24.0; clump.fractal_octaves = 1
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in low_idx:
		var p: Vector3 = pts[i][0]
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var curve := PathDef.curve
	var view := {}          # outline sample -> the viewpoint it was found from
	var off := 0.0
	while off < curve.get_baked_length():
		var e := curve.sample_baked(off)
		off += 8.0
		if e.x < lo.x - 60.0 or e.x > hi.x + 60.0 or e.z < lo.y - 60.0 or e.z > hi.y + 60.0:
			continue
		var bins := {}      # azimuth bin -> [tan(elevation), sample]
		var over := 0       # samples overhead: is this viewpoint under (or entering) the lip?
		for i in low_idx:
			var d: Vector3 = pts[i][0] - e
			var hd := Vector2(d.x, d.z).length()
			if d.y < 4.0 or hd > 100.0:
				continue
			if hd < 40.0:
				over += 1
			var b := int((atan2(d.x, d.z) + PI) * (240.0 / TAU))
			var el := d.y / maxf(hd, 0.5)
			var cur = bins.get(b)
			if cur == null or el < cur[0]:
				bins[b] = [el, i]
		if over < 25:
			continue
		for b in bins:
			if bins[b][0] > 1.2:
				continue        # an edge almost overhead is a hanging lump seen against the roof, not the light
			var i: int = bins[b][1]
			if not view.has(i):
				view[i] = e
	var anchors := {}     # placed anchors by ANCHOR_CELL cell
	var count := 0
	for pass_rim in [false, true]:
		var order: Array = rim_idx.duplicate() if pass_rim else view.keys()
		for i in range(order.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = order[i]
			order[i] = order[j]
			order[j] = t
		for i in order:
			if used.has(i):
				continue
			var q: Array = pts[i]
			var pos: Vector3 = q[0]
			if float(q[4]) > 0.4:
				continue
			var cl := smoothstep(-0.35, 0.3, clump.get_noise_3dv(pos))
			var gap := lerpf(7.0, 3.5, cl) if pass_rim else lerpf(5.0, 2.4, cl)
			if _near_anchor(anchors, pos, gap):
				continue
			var pd := PathDef.curve.get_closest_point(pos).distance_to(pos)
			if pd < 14.0:
				continue
			var n := 0
			if pass_rim:
				n = _silhouette(cells, pos, q[1], rng, true, pd, "rim")
				st["rim"] += n
			else:
				var e: Vector3 = view[i]
				var away := Vector3(pos.x - e.x, 0.0, pos.z - e.z)
				var far := smoothstep(40.0, 90.0, away.length())
				n = _silhouette(cells, pos, q[1], rng, true, pd, "outline", away.normalized(), 1.0 + 0.3 * far)
				st["outline"] += n
			if n > 0:
				var g := Vector3i(floori(pos.x / ANCHOR_CELL), floori(pos.y / ANCHOR_CELL), floori(pos.z / ANCHOR_CELL))
				if not anchors.has(g):
					anchors[g] = []
				anchors[g].append(pos)
				used[i] = true
				count += n
	return count

## Is a placed anchor closer than gap (<= ANCHOR_CELL) to pos?
static func _near_anchor(anchors: Dictionary, pos: Vector3, gap: float) -> bool:
	var g := Vector3i(floori(pos.x / ANCHOR_CELL), floori(pos.y / ANCHOR_CELL), floori(pos.z / ANCHOR_CELL))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var k := Vector3i(g.x + dx, g.y + dy, g.z + dz)
				if anchors.has(k):
					for a in anchors[k]:
						if (a as Vector3).distance_to(pos) < gap:
							return true
	return false

## Big backlit silhouette on the crest edge, the lip front or the lip rim: a gorgonian tree, black coral or a whip
## cluster, standing out from the rock (up and out on the crest; out and drooping from the rim, the crown across the
## line of sight from below). `out` (horizontal) overrides the rock's outward direction (the lip outline: away from
## the viewer); `grow` scales it. Crest trees are bigger: they are mostly seen from 40-80 m. Returns the number placed.
static func _silhouette(cells: Dictionary, pos: Vector3, nrm: Vector3, rng: RandomNumberGenerator, rim: bool, pd: float, tag := "",
		out := Vector3.ZERO, grow := 1.0) -> int:
	var nh := Vector3(nrm.x, 0.0, nrm.z)
	nh = nh.normalized() if nh.length() > 0.1 else Vector3.RIGHT
	if out.length() > 0.5:
		nh = out
	var size := minf((rng.randf_range(2.2, 4.2) if rim else rng.randf_range(2.4, 4.8)) * grow, pd - 12.0)
	if size < 1.4:
		return 0
	var up: Vector3
	if rim:
		# out from the edge and drooping (from below: a crown against the light), sometimes hanging straight down
		if rng.randf() < 0.8:
			up = (nh * 0.8 + Vector3.DOWN * rng.randf_range(0.15, 0.7)).normalized()
		else:
			up = (Vector3.DOWN * 0.85 + nh * 0.35).normalized()
	else:
		up = (Vector3.UP * 0.7 + nh * 0.55).normalized()
	var r := rng.randf()
	var key := ""
	var col := Color()
	if r < 0.45:
		key = "tree" + str(rng.randi() % 3); col = _col(TREE_COLS, rng)
	elif r < 0.7:
		key = "black" + str(rng.randi() % 2); col = _col(BLACK_COLS, rng)
	else:
		key = "whips" + str(rng.randi() % 3); col = _col(WHIP_COLS, rng); size *= 0.85
	# the crown faces the open water (perpendicular to the current along the wall)
	var x := up.cross(nh)
	if x.length() < 0.1:
		x = up.cross(Vector3.FORWARD)
	x = x.normalized()
	var zz := x.cross(up).normalized()
	var b := Basis(x, up, zz).rotated(up, rng.randf_range(-0.35, 0.35)).scaled(Vector3.ONE * size)
	_add(cells, key, [Transform3D(b, pos - nrm * 0.1), col], tag)
	return 1

static func _add(cells: Dictionary, key: String, item: Array, tag := "") -> void:
	var pos: Vector3 = (item[0] as Transform3D).origin
	if collect:
		collected.append([key, pos, (item[0] as Transform3D).basis.get_scale().x, tag])
	var c := Vector3i(floori(pos.x / CELL), floori(pos.y / CELL), floori(pos.z / CELL))
	var d: Dictionary = cells[key]
	if not d.has(c):
		d[c] = []
	d[c].append(item)

## Weighted pick from {key: weight} with r in 0..1.
static func _pick(w: Dictionary, r: float) -> String:
	var total := 0.0
	for k in w:
		total += w[k]
	var acc := 0.0
	var last := ""
	for k in w:
		acc += w[k]
		last = k
		if r * total <= acc and w[k] > 0.0:
			return k
	return last

## One more plate in the 5 m cell of pos, if the cell has room (PLATE_MAX).
static func _plate_room(plate_cells: Dictionary, pos: Vector3) -> bool:
	var c := Vector3i(floori(pos.x / 5.0), floori(pos.y / 5.0), floori(pos.z / 5.0))
	var n: int = plate_cells.get(c, 0)
	if n >= PLATE_MAX:
		return false
	plate_cells[c] = n + 1
	return true

## Plate colour, darkened by the cavity of the rock it grows from (a shelf in a hollow sits in the hollow's shade).
static func _plate_col(rng: RandomNumberGenerator, cav: float) -> Color:
	var c := _col(PLATE_COLS, rng)
	var k := 1.0 - 0.6 * clampf(cav, 0.0, 1.0)
	return Color(c.r * k, c.g * k, c.b * k, c.a)

## One or two face samples 0.8-3 m below a plate and within 2.5 m along the rock, facing the same way, not in a hollow.
static func _tier(pts: Array, grid: Dictionary, pos: Vector3, nrm: Vector3, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var want := rng.randi_range(1, 2)
	var g := Vector3i(floori(pos.x / 2.5), floori(pos.y / 2.5), floori(pos.z / 2.5))
	for dy in [-1, -2, 0]:
		for dx in [0, -1, 1]:
			for dz in [0, -1, 1]:
				var key := Vector3i(g.x + dx, g.y + dy, g.z + dz)
				if not grid.has(key):
					continue
				for j in grid[key]:
					var q: Array = pts[j]
					var d: Vector3 = q[0] - pos
					if d.y < -3.0 or d.y > -0.8 or Vector2(d.x, d.z).length() > 2.5:
						continue
					if (q[1] as Vector3).dot(nrm) < 0.6 or float(q[4]) > PLATE_CAV:
						continue
					out.append(j)
					if out.size() >= want:
						return out
	return out

static func _mm(root: Node3D, mesh: Mesh, mat: Material, items: Array, vis_end: float, shadow := false) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_custom_data(i, items[i][1])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = vis_end
	mi.visibility_range_end_margin = vis_end * 0.25
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(mi)

## Basis with +Y between the surface normal and world up (`lean` = how much it follows the normal), random yaw.
static func _basis_on(n: Vector3, rng: RandomNumberGenerator, scale: float, tilt: float, lean: float) -> Basis:
	var up := n.lerp(Vector3.UP, 1.0 - lean).normalized()
	up = (up + Vector3(rng.randf_range(-tilt, tilt), 0.0, rng.randf_range(-tilt, tilt))).normalized()
	var ref := Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT
	var side := up.cross(ref).normalized()
	var b := Basis(side, up, side.cross(up)).orthonormalized()
	b = b.rotated(up, rng.randf() * TAU)
	return b.scaled(Vector3.ONE * scale)

## Barrel sponge on steep rock: a vase that grows out of the wall and turns up towards the light. Its axis turns
## from the rock normal towards world up only as far as BARREL_OFF_N: then the back of the rim (radius up to ~0.9 at
## height ~1.4, plus the mesh's own lean) stays clear of the rock even on an overhanging face, so it is never cut by
## the rock into an open 'C' (an upright vase on a vertical face had the back half of its rim inside the wall). On a
## vertical face the axis ends up ~38 degrees off vertical. The base is seated just into the rock. Same random draws
## as _basis_on (the layout of the reef is unchanged).
const BARREL_OFF_N := 0.9      # rad (~52 degrees): the largest angle between the barrel axis and the rock normal
static func _barrel_wall_xf(pos: Vector3, n: Vector3, rng: RandomNumberGenerator, s: float) -> Transform3D:
	var nn := n.normalized() if n.length_squared() > 1e-8 else Vector3.UP
	var up := Vector3.UP
	var off := acos(clampf(nn.dot(Vector3.UP), -1.0, 1.0))     # angle between the rock normal and world up
	var ax := nn.cross(Vector3.UP)
	if off > BARREL_OFF_N and ax.length_squared() > 1e-6:
		up = nn.rotated(ax.normalized(), BARREL_OFF_N)    # from the normal towards up, at most BARREL_OFF_N
	# a little natural jitter (small: it must not tip the rim back into the rock)
	up = (up + Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12))).normalized()
	if up.dot(nn) < cos(BARREL_OFF_N + 0.08):
		up = (up + nn * 0.25).normalized()
	var ref := Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT
	var side := up.cross(ref).normalized()
	var b := Basis(side, up, side.cross(up)).orthonormalized().rotated(up, rng.randf() * TAU)
	return Transform3D(b.scaled(Vector3.ONE * s), pos - nn * 0.08 * s)

## Encrusting colony on steep rock: a coral-head mesh pressed flat against the surface (axis = rock normal).
static func _crust_xf(pos: Vector3, n: Vector3, rng: RandomNumberGenerator, s: float) -> Transform3D:
	var up := (n + Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.1, 0.15), rng.randf_range(-0.15, 0.15))).normalized()
	var ref := Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT
	var side := up.cross(ref).normalized()
	var b := Basis(side, up, side.cross(up)).orthonormalized().rotated(up, rng.randf() * TAU)
	b = b * Basis.from_scale(Vector3(s, s * rng.randf_range(0.2, 0.32), s * rng.randf_range(0.7, 1.0)))
	return Transform3D(b, pos - n * 0.06 * s)

## Plate coral: a shelf growing out of the face, a third of it buried in the rock; local +X points away from the
## rock (the shader darkens the attached side), the outer edge tilts down by 5-15 degrees. The rock's normal travels
## with it for the shader (which lights a far shelf top like the face it grows from): its horizontal direction is
## local +X (within the yaw jitter), its height n.y is coded in the z / x scale ratio (1 + 0.1 n.y, a 5 % ellipse).
static func _plate_xf(pos: Vector3, n: Vector3, rng: RandomNumberGenerator, s: float) -> Transform3D:
	var nh := Vector3(n.x, 0.0, n.z)
	nh = nh.normalized() if nh.length() > 0.15 else Vector3.RIGHT
	nh = nh.rotated(Vector3.UP, rng.randf_range(-0.4, 0.4))
	var tilt := rng.randf_range(0.09, 0.26)
	var up := (Vector3.UP * cos(tilt) + nh * sin(tilt)).normalized()
	var x := (nh - up * nh.dot(up)).normalized()
	var z := x.cross(up).normalized()
	var b := Basis(x, up, z) * Basis.from_scale(Vector3(s, s * 0.7, s * (1.0 + 0.1 * clampf(n.normalized().y, -0.9, 0.9))))
	return Transform3D(b, pos + nh * 0.25 * s)

static func _col(list: Array, rng: RandomNumberGenerator, dim := 1.0) -> Color:
	var c: Color = list[rng.randi() % list.size()]
	c = c.lerp(Color(c.r * 0.7, c.g * 0.78, c.b * 0.88), rng.randf()) * dim
	var l := c.srgb_to_linear()
	return Color(l.r, l.g, l.b, rng.randf())

## A sea fan stands out from the rock, its plane facing the open water (perpendicular to the current).
static func _fan_xf(pos: Vector3, n: Vector3, rng: RandomNumberGenerator, richness: float, hang: bool, smax := 99.0) -> Transform3D:
	var s := minf(rng.randf_range(1.0, 1.9) * (1.0 + 0.4 * richness) * (1.4 if rng.randf() < 0.12 else 1.0), smax)
	var vert := Vector3.DOWN if hang else Vector3.UP
	var up := (vert * 0.75 + n * 0.45 + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))).normalized()
	var facing := Vector3(n.x, 0, n.z).normalized() if Vector2(n.x, n.z).length() > 0.2 else Vector3(1, 0, 0).rotated(Vector3.UP, rng.randf() * TAU)
	var x := up.cross(facing).normalized()
	var z := x.cross(up).normalized()
	return Transform3D(Basis(x, up, z).scaled(Vector3.ONE * s), pos - n * 0.2)
