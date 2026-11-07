extends RefCounted
## The lip: a heavy rock shelf growing out of the wall above the path just before the prow. One closed surface, polar
## around a centre buried in the wall: a top that rises into the face, a broken rounded front, and an underside that
## steps down towards the face in hanging tiers (each tier's outer lip a steep face towards the open water, its tread
## rising behind into a dark recess), with hanging masses, keels, lumps, pockets and crevices. The rim is lobed at two
## scales (broad lobes, 8-20 m scallops) and carries rounded hanging pendants, so the outline seen from below is
## never a smooth arc.
## Path clearance never flattens the relief: the full relief is built first, then every place where it would come
## closer than CLEAR to the path asks for a vertical lift; those requests are spread (dilated, then blurred) into a
## smooth lift field that raises the whole local section, top and bottom together. The lowest hanging lumps end up
## exactly CLEAR above the path and keep their shape.
## Vertex colour alpha = AO: multi-scale relief (a vertex behind its 3 m / 12 m neighbourhood is darker, a lip or a
## hanging mass in front of it lighter), how much open water a point sees (dark towards the wall, opening towards the
## rim) and which way it faces (towards the open water or into the recess). Dress samples
## [position, normal, depth, where, cavity]: where 3 = top / front / tier faces, 4 = underside, 5 = rim (the lower
## front edge that forms the silhouette seen from below).

const C := Vector3(-68.0, -84.0, -384.0)
const R0 := 82.0
const PHI := 1.45           # half opening angle (rad); the section shrinks to the buried centre at +-PHI
const NPHI := 288          # ~0.85 m columns at the rim: the lobed outline stays round, not faceted
const NSEC := 176
const NDENSE := 521
const NLIFT := 64           # lift field resolution across the section (per column)
const CLEAR := 14.8         # minimum distance from the path line to the rock (the old flat clamp left 14.7 m)
const IF_STEP := 2.0        # face distance cache along each column (every vertex stays in its column's vertical plane)
const IF_N := 60

static func mesh(gen, dress: Array) -> ArrayMesh:
	var n1 := FastNoiseLite.new(); n1.seed = 12; n1.frequency = 0.045; n1.fractal_octaves = 3
	var n2 := FastNoiseLite.new(); n2.seed = 17; n2.frequency = 0.15; n2.fractal_type = FastNoiseLite.FRACTAL_RIDGED; n2.fractal_octaves = 2
	var n3 := FastNoiseLite.new(); n3.seed = 23; n3.frequency = 0.55; n3.fractal_octaves = 2
	var n4 := FastNoiseLite.new(); n4.seed = 29; n4.frequency = 0.11; n4.fractal_octaves = 1
	var n5 := FastNoiseLite.new(); n5.seed = 41; n5.frequency = 0.028; n5.fractal_octaves = 2      # big hanging masses
	var pk := FastNoiseLite.new(); pk.seed = 47; pk.noise_type = FastNoiseLite.TYPE_CELLULAR; pk.frequency = 0.16
	pk.cellular_return_type = FastNoiseLite.RETURN_DISTANCE; pk.fractal_type = FastNoiseLite.FRACTAL_NONE
	var blk := FastNoiseLite.new(); blk.seed = 53; blk.frequency = 0.07; blk.fractal_type = FastNoiseLite.FRACTAL_RIDGED; blk.fractal_octaves = 2
	var rim := FastNoiseLite.new(); rim.seed = 5; rim.frequency = 0.025; rim.fractal_octaves = 2
	# rim scallops: one smooth octave (8-20 m), no finer one (that cut block-like teeth into the silhouette)
	var rim_m := FastNoiseLite.new(); rim_m.seed = 61; rim_m.frequency = 0.07; rim_m.fractal_type = FastNoiseLite.FRACTAL_NONE
	var rim_s := FastNoiseLite.new(); rim_s.seed = 67; rim_s.frequency = 0.16; rim_s.fractal_type = FastNoiseLite.FRACTAL_NONE   # ~6 m
	var tn := FastNoiseLite.new(); tn.seed = 71; tn.frequency = 0.03; tn.fractal_octaves = 2       # tier edges
	var td := FastNoiseLite.new(); td.seed = 73; td.frequency = 0.02; td.fractal_type = FastNoiseLite.FRACTAL_NONE   # tier drop
	var kn := FastNoiseLite.new(); kn.seed = 83; kn.frequency = 1.0; kn.fractal_type = FastNoiseLite.FRACTAL_NONE     # keels
	var nv := NPHI * NSEC
	var base := PackedVector3Array(); base.resize(nv)
	var sec_n := PackedVector2Array(); sec_n.resize(nv)       # section normal (horizontal, up)
	var rho_v := PackedFloat32Array(); rho_v.resize(nv)       # horizontal distance from the centre
	var rcol := PackedFloat32Array(); rcol.resize(NPHI)       # rim radius per column
	var dense := PackedVector2Array(); dense.resize(NDENSE)
	for i in NPHI:
		var phi := lerpf(-PHI, PHI, float(i) / (NPHI - 1))
		var s := phi * R0
		# rim radius: broad lobes plus rounded scallops (a soft-cornered profile of one smooth octave)
		var nm := rim_m.get_noise_1d(s) * 1.6
		var scallop := signf(nm) * pow(minf(absf(nm), 1.0), 0.7)
		var r := R0 * pow(maxf(cos(phi / PHI * PI * 0.5), 0.0), 0.5) * (1.0 + 0.13 * rim.get_noise_1d(s) + 0.035 * rim.get_noise_1d(s * 1.9 + 40.0) + 0.06 * scallop + 0.022 * rim_s.get_noise_1d(s))
		rcol[i] = r
		var yc := C.y + 2.5 * rim.get_noise_1d(s * 0.7 + 90.0)
		var hh := 8.0 + 2.0 * rim.get_noise_1d(s * 0.9 + 170.0)
		var dir := Vector3(cos(phi), 0.0, sin(phi))
		# dense superellipse section (h = horizontal distance from C, y), top inner -> front -> bottom inner
		var total := 0.0
		for k in NDENSE:
			var th := lerpf(PI * 0.5, -PI * 0.5, k / float(NDENSE - 1))
			var ct := cos(th); var st := sin(th)
			var rho := pow(absf(ct), 2.0 / 3.2)
			var sy := signf(st) * pow(absf(st), 2.0 / 3.2)
			var y := yc + hh * sy
			if sy > 0.0:
				y += 9.0 * pow(1.0 - smoothstep(0.0, 0.45, rho), 2.0)
			else:
				y -= 18.0 * pow(1.0 - smoothstep(0.0, 0.55, rho), 2.0)
				y += _tier(C.x + dir.x * rho * r, C.z + dir.z * rho * r, rho, r, tn, td)
			dense[k] = Vector2(rho * r, y)
			if k > 0: total += dense[k].distance_to(dense[k - 1])
		# resample by arc length (the tier risers get their own rows)
		var k := 0
		var acc := 0.0
		for j in NSEC:
			var target := total * j / (NSEC - 1)
			while k < NDENSE - 2 and acc + dense[k].distance_to(dense[k + 1]) < target:
				acc += dense[k].distance_to(dense[k + 1])
				k += 1
			var seg := maxf(dense[k].distance_to(dense[k + 1]), 1e-5)
			var q := dense[k].lerp(dense[k + 1], clampf((target - acc) / seg, 0.0, 1.0))
			var t := (dense[k + 1] - dense[k]) / seg
			base[i * NSEC + j] = Vector3(C.x, 0.0, C.z) + dir * q.x + Vector3(0.0, q.y, 0.0)
			sec_n[i * NSEC + j] = Vector2(-t.y, t.x)
			rho_v[i * NSEC + j] = q.x
	# the path near the lip, by z (z descending): clearance requests and the pendant placement use it
	var pz := PackedFloat32Array(); var pxy := PackedVector2Array()
	var curve: Curve3D = PathDef.curve
	if curve != null:
		var off := 0.0
		while off < curve.get_baked_length():
			var q := curve.sample_baked(off)
			if q.z < -560.0:
				break
			if q.z < -240.0:
				pz.append(q.z); pxy.append(Vector2(q.x, q.y))
			off += 1.0
	# rounded pendants hanging from the lower rim every 8-18 m (shortened where the tip would come near the path;
	# the lift field would otherwise raise the whole rim there)
	var pend: Array = []      # [phi, sigma (m along the rim), depth (m), rf centre]
	var prng := RandomNumberGenerator.new()
	prng.seed = 131
	var sp := -PHI * R0 + prng.randf_range(4.0, 12.0)
	while sp < PHI * R0:
		var ph := sp / R0
		var ic := clampi(roundi((ph + PHI) / (2.0 * PHI) * (NPHI - 1)), 0, NPHI - 1)
		var rr := rcol[ic]
		var sig := prng.randf_range(2.0, 4.2)
		var depth := prng.randf_range(3.5, 8.0) * smoothstep(18.0, 45.0, rr)
		var rc := prng.randf_range(0.9, 0.97)
		var low := 0.0      # lower rim height of this column
		for j in NSEC:
			if rho_v[ic * NSEC + j] > 0.85 * rr:
				low = minf(low, base[ic * NSEC + j].y)
		var pp := _path_at(C.z + sin(ph) * rr, pz, pxy)
		if pp.z > 0.0:
			var gap := Vector2(C.x + cos(ph) * rr - pp.x, low - depth - pp.y).length()
			depth -= maxf(CLEAR + 4.0 - gap, 0.0)
		if depth > 1.5:
			pend.append([ph, sig, depth, rc])
		sp += prng.randf_range(8.0, 18.0)
	# relief along the section normal (noise sampled on the base section)
	var disp := PackedVector3Array(); disp.resize(nv)
	for i in NPHI:
		var phi := lerpf(-PHI, PHI, float(i) / (NPHI - 1))
		var dir := Vector3(cos(phi), 0.0, sin(phi))
		var r := rcol[i]
		var pdrop := PackedFloat32Array(); pdrop.resize(2)      # this column's pendant: depth, rf centre
		for pp in pend:
			var g := exp(-pow((phi - float(pp[0])) * r / float(pp[1]), 2.0))
			if g * float(pp[2]) > pdrop[0]:
				pdrop[0] = g * float(pp[2]); pdrop[1] = pp[3]
		for j in NSEC:
			var k := i * NSEC + j
			var p := base[k]
			var sn := sec_n[k]
			var nrm := (dir * sn.x + Vector3.UP * sn.y).normalized()
			var rf := rho_v[k] / maxf(r, 1e-3)
			var front := 1.0 - absf(sn.y)
			var low := smoothstep(-0.05, -0.5, sn.y)       # lower front and underside
			var edge := smoothstep(0.7, 0.95, rf) * low     # the lower rim: the silhouette seen from below
			var d := 2.6 * n1.get_noise_3dv(p) + 1.1 * n2.get_noise_3dv(p) * (1.0 - 0.7 * edge) + 0.35 * n3.get_noise_3dv(p)
			# vertical cracks in the front: rounded, patchy, and fading out towards the lower rim
			var crack := pow(1.0 - absf(n4.get_noise_3d(p.x, p.y * 0.22, p.z)), 4.0) * smoothstep(-0.15, 0.3, n5.get_noise_3d(p.x * 2.0, p.y, p.z * 2.0))
			d -= 1.7 * crack * front * (1.0 - 0.85 * low)
			if sn.y < -0.15:
				# underside: big hanging masses (the tiers and masses are the forms that read from below; the rest is
				# subordinate detail), sharp-edged hanging blocks, lumps, rock pockets and a crevice network
				var w := smoothstep(0.15, 0.55, -sn.y)
				var mass := 6.5 * pow(maxf(n5.get_noise_3d(p.x, p.y * 0.6, p.z), 0.0), 1.25)
				var block := 2.0 * pow(clampf(blk.get_noise_3dv(p) * 0.5 + 0.5, 0.0, 1.0), 2.5) * (1.0 - 0.8 * edge)     # sharp ridges stay off the silhouette
				var lump := 2.8 * pow(maxf(n1.get_noise_3d(p.x * 2.3, p.y, p.z * 2.3), 0.0), 1.2) + 1.2 * pow(maxf(n3.get_noise_3d(p.x * 0.5, p.y, p.z * 0.5), 0.0), 1.4)
				# (pockets and crevices are sharp-edged: on the silhouette they would notch it, so they fade at the rim)
				var pocket := 1.6 * (1.0 - smoothstep(0.08, 0.42, pk.get_noise_3dv(p))) * (1.0 - 0.8 * edge)
				var crev := 2.2 * pow(1.0 - absf(n4.get_noise_3d(p.x * 1.6, p.y, p.z * 1.6)), 5.0) * (1.0 - 0.8 * edge)
				# hanging keels running out from the face towards the rim (~12 m apart): their flanks face sideways, so
				# from below they show as lit ribs between dark flutes whichever way the diver looks
				var kr := 1.0 - absf(kn.get_noise_2d(phi * rho_v[k] / 12.0, rho_v[k] / 40.0))
				var keel := 4.5 * pow(kr, 2.2) * smoothstep(0.45, 0.6, rf) * (1.0 - smoothstep(0.86, 0.95, rf))
				d += (mass + block + lump + keel - pocket - crev) * w
			var dv := nrm * d
			if pdrop[0] > 0.05:
				# pendant: a rounded bulb hanging from the lower rim
				var band := exp(-pow((rf - pdrop[1]) / 0.07, 2.0)) * smoothstep(0.1, -0.35, sn.y)
				dv += (Vector3.DOWN + dir * 0.12) * pdrop[0] * band
			disp[k] = dv
	# clearance: lift requests from the relieved surface, spread into a smooth field over (column, rho)
	var req := PackedFloat32Array(); req.resize(NPHI * NLIFT)
	var n_req := 0
	for i in NPHI:
		var r := rcol[i]
		for j in NSEC:
			var k := i * NSEC + j
			var p := base[k] + disp[k]
			if not _maybe_close(p, pz, pxy):
				continue
			var cp := curve.get_closest_point(p)
			var hd := Vector2(p.x - cp.x, p.z - cp.z).length()
			if hd >= CLEAR + 0.6 or p.y < cp.y - 2.0:
				continue
			var need := sqrt((CLEAR + 0.6) * (CLEAR + 0.6) - hd * hd) - (p.y - cp.y)
			if need > 0.0:
				var m := clampi(roundi(rho_v[k] / maxf(r, 1e-3) * (NLIFT - 1)), 0, NLIFT - 1)
				req[i * NLIFT + m] = maxf(req[i * NLIFT + m], need)
				n_req += 1
	var lift := _spread(req) if n_req > 0 else req
	var lift_max := 0.0
	for v in lift: lift_max = maxf(lift_max, v)
	var pos := PackedVector3Array(); pos.resize(nv)
	for i in NPHI:
		var r := rcol[i]
		for j in NSEC:
			var k := i * NSEC + j
			var fm := clampf(rho_v[k] / maxf(r, 1e-3) * (NLIFT - 1), 0.0, NLIFT - 1.001)
			var lm := lerpf(lift[i * NLIFT + int(fm)], lift[i * NLIFT + int(fm) + 1], fm - int(fm))
			pos[k] = base[k] + disp[k] + Vector3(0.0, lm, 0.0)
	# safety: nothing inside the clearance tube (pushes out radially; normally untouched)
	var pushed := 0
	for k in nv:
		var p := pos[k]
		if not _maybe_close(p, pz, pxy):
			continue
		var cp := curve.get_closest_point(p)
		var dv := p - cp
		var dl := dv.length()
		if dl < CLEAR:
			pos[k] = cp + (dv / dl if dl > 1e-3 else Vector3.UP) * CLEAR
			pushed += 1
	var idx := PackedInt32Array()
	for i in NPHI - 1:
		for j in NSEC - 1:
			var a := i * NSEC + j
			var b := a + NSEC
			idx.append_array([a, a + 1, b, a + 1, b + 1, b])
	var nrm := PackedVector3Array(); nrm.resize(nv)
	for t in range(0, idx.size(), 3):
		var a := idx[t]; var b := idx[t + 1]; var c := idx[t + 2]
		var fn := (pos[c] - pos[a]).cross(pos[b] - pos[a])
		nrm[a] += fn; nrm[b] += fn; nrm[c] += fn
	for k in nv:
		nrm[k] = nrm[k].normalized() if nrm[k].length_squared() > 1e-12 else Vector3.UP
	# the form's normal, smoothed over ~2 m (CUSTOM0.xyz): the underside's side light from the open water follows the
	# tiers, hanging masses and keels with it, not every crevice edge and block crease (a strong directional fill on
	# the raw facets turns them into flat sheets with straight crease lines: crumpled paper)
	var nsm := _blur(nrm, 2)
	var cust := PackedFloat32Array(); cust.resize(nv * 4)
	for k in nv:
		var s: Vector3 = nsm[k]
		s = s.normalized() if s.length_squared() > 1e-6 else nrm[k]
		cust[k * 4] = s.x; cust[k * 4 + 1] = s.y; cust[k * 4 + 2] = s.z; cust[k * 4 + 3] = 0.0
	# distance behind the face along each column (gen.inside_face is costly; it is close to linear along a column)
	var ifc := PackedFloat32Array(); ifc.resize(NPHI * IF_N)
	for i in NPHI:
		var phi := lerpf(-PHI, PHI, float(i) / (NPHI - 1))
		for m in IF_N:
			ifc[i * IF_N + m] = gen.inside_face(C.x + cos(phi) * m * IF_STEP, C.z + sin(phi) * m * IF_STEP)
	# relief at two neighbourhood scales: positions box-blurred over ~4 m and ~13 m of the grid
	var b1 := _blur(pos, 3)
	var b2 := _blur(pos, 10)
	var cols := PackedColorArray(); cols.resize(nv)
	var uvs := PackedVector2Array(); uvs.resize(nv)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var n_rim := 0
	var ao_sum := 0.0
	var ao_n := 0
	for i in NPHI:
		var phi := lerpf(-PHI, PHI, float(i) / (NPHI - 1))
		var dir := Vector3(cos(phi), 0.0, sin(phi))
		var r := rcol[i]
		for j in NSEC:
			var k := i * NSEC + j
			var p := pos[k]
			var n := nrm[k]
			# > 0: the vertex lies behind its surroundings (a recess, the inner corner of a tier); < 0: in front (a
			# tier lip, a hanging mass, a pendant). No vertex-scale term: that only speckles.
			var cav := (b1[k] - p).dot(n) * 0.36 + (b2[k] - p).dot(n) * 0.15
			var relief := clampf(0.8 - cav * 0.45, 0.14, 1.12)
			# openness: how far out from the face (towards open water) against how far in from the rim
			var dw := maxf(-_face_at(ifc, i, rho_v[k]), 0.0)
			var dr := maxf(r - rho_v[k], 0.0)
			var open := clampf(dw / (dw + 0.8 * dr + 1.5), 0.0, 1.0)
			var und := smoothstep(0.2, -0.5, n.y)
			# which way a steep face looks: out towards the open water (lit by it) or back into the recess
			var face_out := Vector2(n.x, n.z).dot(Vector2(dir.x, dir.z))
			var side := (1.0 - absf(n.y)) * lerpf(0.8, 1.14, smoothstep(-0.55, 0.55, face_out)) + absf(n.y)
			# undersides see little of the bright water above, except near the rim, where the open water wraps round
			var ao := relief * side * lerpf(lerpf(0.5, 0.92, open), 1.0, clampf(n.y * 0.7 + 0.7, 0.0, 1.0)) * lerpf(1.0, lerpf(0.42, 1.0, pow(open, 0.8)), und)
			var c: Color = gen.rock_colour(p.x * 1.3 + p.z, p.y).srgb_to_linear()
			var cool := open * und * 0.55
			c = Color(c.r * (1.0 - 0.16 * cool), c.g * (1.0 - 0.04 * cool), c.b * (1.0 + 0.08 * cool))
			c.a = clampf(ao, 0.14, 1.0)
			cols[k] = c
			var buried := _face_at(ifc, i, (p.x - C.x) * dir.x + (p.z - C.z) * dir.z) > -2.0
			if n.y < -0.2 and not buried:
				ao_sum += c.a; ao_n += 1
			# encrusting life grows on the lips and hanging masses, less in the recesses
			var cover := (0.85 if n.y > 0.5 else (0.5 if n.y > -0.4 else 0.62)) * lerpf(0.6, 1.2, smoothstep(0.35, 1.0, relief))
			uvs[k] = Vector2(clampf(cover, 0.0, 1.0), clampf(0.5 + 0.5 * n1.get_noise_3d(p.x * 0.3, p.y * 0.3, p.z * 0.3), 0.0, 1.0))
			if buried:
				continue          # buried in the wall
			var sn := sec_n[k]
			var is_rim := rho_v[k] > 0.84 * r and sn.y < 0.15 and sn.y > -0.8
			var pr := 0.14 if is_rim else (0.133 if n.y > 0.5 else (0.05 if n.y > -0.5 else 0.167))     # per vertex (NPHI 288)
			if rng.randf() < pr:
				var where := 5 if is_rim else (4 if n.y < -0.5 else 3)
				if where == 5: n_rim += 1
				dress.append([p, n, -p.y, where, clampf(cav * 0.25, 0.0, 1.0)])
	print("PELAGIC lip: %d verts, %d lift requests (max lift %.1f m), %d pushed, %d rim samples, %d pendants, underside AO mean %.2f" % [nv, n_req, lift_max, pushed, n_rim, pend.size(), ao_sum / maxf(ao_n, 1.0)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos; arr[Mesh.ARRAY_NORMAL] = nrm; arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs; arr[Mesh.ARRAY_INDEX] = idx
	arr[Mesh.ARRAY_CUSTOM0] = cust
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return m

## Hanging tiers of the underside (vertical offset, m) at (x, z), rf = rho / rim radius: 2-3 levels between the
## face and the rim whose edges wander with the noise. Going in from the rim, each tread rises gently into a recess,
## then the underside drops 4-8 m at a steep riser that faces the open water: a hanging lip. Zero mean, so the roof
## keeps its thickness; faded out at the face, near the rim (the pendants own it) and where the section is small.
static func _tier(x: float, z: float, rf: float, r: float, tn: FastNoiseLite, td: FastNoiseLite) -> float:
	var win := smoothstep(0.40, 0.50, rf) * (1.0 - smoothstep(0.84, 0.94, rf)) * smoothstep(25.0, 55.0, r)
	if win <= 0.0:
		return 0.0
	var v := 5.8 * (1.0 - rf) + 0.9 * tn.get_noise_2d(x, z)
	var fl := floorf(v)
	var stp := fl + smoothstep(0.78, 1.0, v - fl)
	var drop := 8.0 + 2.5 * td.get_noise_2d(x, z)
	return -drop * (stp - v + 0.39) * win

## Distance behind the face (gen.inside_face) at horizontal distance rho along column i, from the column cache.
static func _face_at(ifc: PackedFloat32Array, i: int, rho: float) -> float:
	var f := clampf(rho / IF_STEP, 0.0, IF_N - 1.001)
	var m := int(f)
	return lerpf(ifc[i * IF_N + m], ifc[i * IF_N + m + 1], f - m)

## The path point at z as (x, y, 1), or (0, 0, 0) when the path is not near.
static func _path_at(z: float, pz: PackedFloat32Array, pxy: PackedVector2Array) -> Vector3:
	if pz.is_empty() or z > pz[0] or z < pz[pz.size() - 1]:
		return Vector3.ZERO
	var k := 0
	while k < pz.size() - 1 and pz[k + 1] > z: k += 1
	return Vector3(pxy[k].x, pxy[k].y, 1.0)

## Box blur (twice, about a gaussian) of the vertex grid over +-rad rows and +-rad columns, clamped at the edges.
static func _blur(src: PackedVector3Array, rad: int) -> PackedVector3Array:
	var a := src.duplicate()
	var b := PackedVector3Array(); b.resize(src.size())
	var inv := 1.0 / (2 * rad + 1)
	for _it in 2:
		for i in NPHI:          # along the section
			var o := i * NSEC
			var acc := a[o] * rad
			for t in rad + 1:
				acc += a[o + mini(t, NSEC - 1)]
			for j in NSEC:
				b[o + j] = acc * inv
				acc += a[o + mini(j + rad + 1, NSEC - 1)] - a[o + maxi(j - rad, 0)]
		for j in NSEC:          # across the columns
			var acc := b[j] * rad
			for t in rad + 1:
				acc += b[mini(t, NPHI - 1) * NSEC + j]
			for i in NPHI:
				a[i * NSEC + j] = acc * inv
				acc += b[mini(i + rad + 1, NPHI - 1) * NSEC + j] - b[maxi(i - rad, 0) * NSEC + j]
	return a

## Cheap pre-test against the path point at the same z (generous: the path slopes, the true closest point may sit
## a few metres along it).
static func _maybe_close(p: Vector3, pz: PackedFloat32Array, pxy: PackedVector2Array) -> bool:
	if pz.is_empty() or p.z > pz[0] + CLEAR or p.z < pz[pz.size() - 1] - CLEAR:
		return false
	var k := clampi(int(pz[0] - p.z), 0, pz.size() - 1)     # samples are ~1 m apart along a path that runs down -z
	while k > 0 and pz[k] < p.z: k -= 1
	while k < pz.size() - 1 and pz[k + 1] > p.z: k += 1
	var q := pxy[k]
	return Vector2(p.x - q.x, p.y - q.y).length() < CLEAR + 12.0

## Spreads lift requests (NPHI x NLIFT) into a smooth field that still meets every request: a max filter wider than
## the blur that follows it.
static func _spread(req: PackedFloat32Array) -> PackedFloat32Array:
	var dil := PackedFloat32Array(); dil.resize(req.size())
	var tmp := PackedFloat32Array(); tmp.resize(req.size())
	const RD := 6
	for i in NPHI:
		for m in NLIFT:
			var v := 0.0
			for dm in range(-RD, RD + 1):
				v = maxf(v, req[i * NLIFT + clampi(m + dm, 0, NLIFT - 1)])
			tmp[i * NLIFT + m] = v
	for i in NPHI:
		for m in NLIFT:
			var v := 0.0
			for di in range(-RD, RD + 1):
				v = maxf(v, tmp[clampi(i + di, 0, NPHI - 1) * NLIFT + m])
			dil[i * NLIFT + m] = v
	for _it in 2:        # two box blurs of radius 2 in both directions (support 4 < RD)
		for i in NPHI:
			for m in NLIFT:
				var a := 0.0
				for dm in range(-2, 3):
					a += dil[i * NLIFT + clampi(m + dm, 0, NLIFT - 1)]
				tmp[i * NLIFT + m] = a / 5.0
		for i in NPHI:
			for m in NLIFT:
				var a := 0.0
				for di in range(-2, 3):
					a += tmp[clampi(i + di, 0, NPHI - 1) * NLIFT + m]
				dil[i * NLIFT + m] = a / 5.0
	return dil
