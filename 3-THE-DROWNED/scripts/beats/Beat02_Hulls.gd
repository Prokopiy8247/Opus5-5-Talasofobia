extends RefCounted
## Beat 2, the Hulls (s 118-425 m): trawler, cargo ship, tanker and liner settled across the 40-60 deg slope,
## each bigger than the last, a small ship at the liner's foot (money shot M1). Every hull lies in a sediment
## bed carved into the terrain (Terrain.ship_pose: heel from the cross-slope, a scarp above, a talus berm below).
## Gear the line passes over: the trawler's warps run down its gallows, across the slope under the walk to the
## trawl doors and a ghost net held up by its floats; the cargo ship's stern hawser snakes across the slope to a
## fallen mast; anchor chains leave the hawse pipes and drape onto the slope. Every hull stays >= 10 m from the
## walk (tools_gd/placement_gate.gd checks it).

const SEEDS := {"trawler": 11, "cargo": 23, "tanker": 37, "liner": 41, "small": 5}
const MIN_GEAR := 10.0                  # chains and gear end this far from the walk (3D)
const CHAIN_FAR_END := 105.0            # the far chain lines start fading here (m), gone 20 m on, before the hulls (150 m)
# the trawl: ghost-net headline ends (x, z; on the slope west of the walk)
const NET_A := Vector2(-9.0, -121.0)
const NET_B := Vector2(-35.0, -137.0)
# the cargo hawser ends on a fallen mast east of the walk: mast foot / tip (x, z)
const MAST_A := Vector2(34.0, -188.0)
const MAST_B := Vector2(52.0, -203.0)

var path: PathDef
var samples := PackedVector3Array()


func build(parent: Node3D) -> void:
	path = PathDef.main
	var s := 60.0
	while s <= 560.0:
		samples.append(path.pos(s))
		s += 2.0
	var ships := {}
	for key: String in Terrain.SHIP_KEYS:
		ships[key] = _place(parent, key)
	var gear := Node3D.new()
	gear.name = "Gear"
	parent.add_child(gear)
	_chains(gear, ships)
	var wire := MeshBuilder.new()
	var steel := MeshBuilder.new()
	var floats := MeshBuilder.new()
	var net := MeshBuilder.new()
	_trawl(ships["trawler"], wire, steel, floats, net)
	var hawser := MeshBuilder.new()
	_hawser(ships["cargo"], hawser, steel)
	_inst(wire, Mats.make("rope", {"radius": 0.022, "rope_color": Color(0.2, 0.19, 0.17)}), gear, "Warps")
	_inst(net, Mats.solid(Color(0.09, 0.12, 0.1), 0.05, 0.55, {"roughness": 0.9}), gear, "GhostNet")
	_inst(hawser, Mats.make("rope", {"radius": 0.09, "rope_color": Color(0.3, 0.26, 0.19)}), gear, "Hawser")
	_inst(steel, Mats.solid(Palette.STEEL_DARK, 0.75, 0.4), gear, "GearSteel")
	_inst(floats, Mats.solid(Palette.RUST.lerp(Palette.BONE, 0.35).darkened(0.25), 0.15, 0.55, {"roughness": 0.6}), gear,
		"Floats")


func _inst(mb: MeshBuilder, mat: Material, parent: Node3D, nm: String) -> void:
	if mb.tri_count() == 0:
		return
	var mi := mb.instance(mat, parent)
	mi.name = nm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _place(parent: Node3D, key: String) -> Node3D:
	var ps := Terrain.ship_pose(key)
	var xf: Transform3D = ps["transform"]
	# deploy the anchor on the downslope side (its chain drapes down the slope), stow the other one
	var down := 0 if xf.basis.x.z < 0.0 else 1
	var node := Hull.ship(key, ps["length"], SEEDS[key], {"stow": [1 - down]})
	node.transform = xf
	node.set_meta("down_hawse", down)
	parent.add_child(node)
	return node


func _hawse(node: Node3D, i: int) -> Array:
	var hw: Array = node.get_meta("hawse")
	var ho: Array = node.get_meta("hawse_out")
	var k := mini(i, hw.size() - 1)
	return [node.transform * (hw[k] as Vector3), node.transform.basis * (ho[k] as Vector3)]


func _near_walk(p: Vector3, d: float) -> bool:
	for q in samples:
		if q.distance_squared_to(p) < d * d:
			return true
	return false


## Truncates a ground polyline before it comes within MIN_GEAR of the walk or reaches the cliff lip.
func _clip(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in pts:
		if _near_walk(p, MIN_GEAR) or Terrain.height(p.x, p.z) < -287.0:
			break
		out.append(p)
	return out


## Anchor chains: from the downslope bow hawse pipe (out along the pipe, clear of the plating) down to the
## slope, then trailing over it; the liner also pays out a chain from its stern pipe along the slope.
func _chains(parent: Node3D, ships: Dictionary) -> void:
	# [ship, hawse index (-1 = the deployed bow pipe), horizontal direction, length, link, seed]
	var jobs := [
		["trawler", -1, Vector3(0.5, 0, -1.0), 34.0, 0.42, 1],
		["cargo", -1, Vector3(-0.6, 0, -1.0), 70.0, 0.8, 2],
		["tanker", -1, Vector3(-1.0, 0, 0.18), 95.0, 1.1, 3],
		["liner", -1, Vector3(-1.0, 0, 0.12), 150.0, 1.4, 4],
	]
	for j: Array in jobs:
		var node: Node3D = ships[j[0]]
		var idx: int = j[1]
		if idx < 0:
			idx = node.get_meta("down_hawse")
		var h := _hawse(node, idx)
		var link: float = j[4]
		var pts := Chain.trail(h[0], j[2], j[3], link, j[5], h[1])
		pts = _clip(pts)
		if pts.size() < 4:
			push_warning("Beat02: chain %s/%d clipped away" % [j[0], idx])
			continue
		var near := clampf(link * 110.0, 60.0, 160.0)
		var c := Chain.chain_lod(pts, link, parent, near)
		c.name = "Chain_%s_%d" % [j[0], idx]
		# the far line (rope shader, 1 px floor) outlived its ship in the fog: the cargo chain hung alone in
		# mid-water seen from the liner. It now fades out where the hulls do.
		for ch in c.get_children():
			if ch is GeometryInstance3D and str(ch.name).begins_with("ChainFar"):
				var g := ch as GeometryInstance3D
				g.visibility_range_end = maxf(near * 1.25, CHAIN_FAR_END)
				g.visibility_range_end_margin = 20.0


## Points along the ground from a to b (every step m), lifted by `lift`, with a slow meander.
func _ground_line(a: Vector3, b: Vector3, step: float, lift: float, amp: float, seed: int) -> PackedVector3Array:
	var n := maxi(int(a.distance_to(b) / step), 2)
	var side := Vector3(-(b - a).z, 0.0, (b - a).x).normalized()
	var pts := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / float(n)
		var p := a.lerp(b, t) + side * sin(t * PI * 2.0 + float(seed)) * amp * sin(t * PI)
		p.y = Terrain.height(p.x, p.z) + lift
		pts.append(p)
	return pts


## A wire hanging from `top` in a catenary-like curve to the ground at `touch` (meets it tangentially), clamped
## above the ground everywhere.
func _hang(top: Vector3, touch: Vector3, lift: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var g := Terrain.height(touch.x, touch.z) + lift
	for i in 17:
		var t := float(i) / 16.0
		var p := top.lerp(touch, t)
		p.y = g + (top.y - g) * (1.0 - t) * (1.0 - t)
		p.y = maxf(p.y, Terrain.height(p.x, p.z) + lift)
		pts.append(p)
	return pts


## The trawler's gear: two warps from the gallows blocks down to the slope and across it (under the walk) to
## the trawl doors, bridles to a ghost net whose floated headline holds it up off the slope like a curtain;
## the net's body lies collapsed on the slope behind it.
func _trawl(node: Node3D, wire: MeshBuilder, steel: MeshBuilder, floats: MeshBuilder, net: MeshBuilder) -> void:
	var blocks: Array = node.get_meta("warp_blocks")
	if blocks.size() < 2:
		return
	var na := Vector3(NET_A.x, Terrain.height(NET_A.x, NET_A.y), NET_A.y)
	var nb := Vector3(NET_B.x, Terrain.height(NET_B.x, NET_B.y), NET_B.y)
	var across := (nb - na)
	across.y = 0.0
	across = across.normalized()
	var away := Vector3(across.z, 0.0, -across.x)          # across the headline, down the slope
	if away.z > 0.0:
		away = -away
	var doors := [na - across * 5.0 - away * 7.0, nb + across * 5.0 - away * 7.0]
	var stern := node.transform * Vector3(0, 0, float(node.get_meta("length")) * 0.5)
	for i in 2:
		var top: Vector3 = node.transform * (blocks[i] as Vector3)
		var dpos: Vector3 = doors[i]
		dpos.y = Terrain.height(dpos.x, dpos.z)
		# the door lies on its side on the slope, facing up
		var nrm := Terrain.normal(dpos.x, dpos.z, 2.0)
		var fwd := (dpos - stern)
		fwd = (fwd - nrm * fwd.dot(nrm)).normalized()
		var eye := Debris.otter_board(steel, Transform3D(Basis(fwd, nrm.cross(fwd), nrm), dpos + nrm * 0.12),
			Vector2(2.4, 1.2))
		var touch := stern.lerp(dpos, 0.12)
		touch += Vector3(0, 0, 3.0 * (float(i) - 0.5))
		var hang := _hang(top, Vector3(touch.x, 0, touch.z), 0.05)
		var lie := _ground_line(hang[hang.size() - 1], eye, 2.0, 0.05, 1.5, i + 3)
		hang.append_array(lie.slice(1))
		Rope.tube(hang, 0.022, 4, wire)
		# bridles: door to the headline end and to the footrope end
		var hd: Vector3 = na if i == 0 else nb
		Rope.tube(_ground_line(eye, hd + Vector3(0, 0.6, 0), 1.0, 0.05, 0.4, i + 7), 0.016, 3, wire)
		Rope.tube(_ground_line(eye, hd + away * 1.5, 1.0, 0.05, 0.3, i + 9), 0.016, 3, wire)
	# the floated headline: rises 2-4.5 m off the slope between the doors, sagging and swaying
	var head := PackedVector3Array()
	for k in 33:
		var t := float(k) / 32.0
		var p := na.lerp(nb, t) + away * sin(t * PI) * 3.0
		var g := Terrain.height(p.x, p.z)
		# floats hold it up in lobes; between them the headline sags
		p.y = g + 0.7 + 5.0 * pow(sin(t * PI), 0.6) * (0.55 + 0.45 * sin(t * 13.0 + 1.0) * sin(t * 5.0 + 0.4))
		head.append(p)
	Rope.tube(head, 0.02, 4, wire)
	var drift := away
	var fl := Debris.ghost_net(net, head, drift, 0.4, 0.028, 21)
	for p in fl:
		floats.sphere(p, 0.16, 8, Vector3(1.0, 0.85, 1.0))
	# the body of the net lies collapsed on the slope behind the mouth
	var mid := na.lerp(nb, 0.5) + away * 10.0
	var yaw := atan2(away.x, away.z)
	var fl2 := Debris.net(net, Vector3(mid.x, 0, mid.z), Vector2(12.0, 16.0), yaw, [], 0.45, 0.028, 0.0, 33, 0.55, 0.05,
		0.35)
	for p in fl2:
		floats.sphere(p, 0.16, 8)


## The cargo ship's stern hawser: from a bollard on the stern deck down over the side, across the slope under
## the walk to a broken mast lying on the slope, hitched round it.
func _hawser(node: Node3D, rope: MeshBuilder, steel: MeshBuilder) -> void:
	var L: float = node.get_meta("length")
	var B: float = node.get_meta("beam")
	var D: float = node.get_meta("depth")
	var down: int = node.get_meta("down_hawse")
	var sd := 1.0 if down == 0 else -1.0
	var bitt := node.transform * Vector3(sd * B * 0.36, D + 0.9, L * 0.42)
	var ma := Vector3(MAST_A.x, 0, MAST_A.y)
	var mb := Vector3(MAST_B.x, 0, MAST_B.y)
	ma.y = Terrain.height(ma.x, ma.z) + 0.35
	mb.y = Terrain.height(mb.x, mb.z) + 0.3
	Debris.fallen_mast(steel, ma, mb, 0.42)
	var rail := node.transform * Vector3(sd * B * 0.53, D + 1.3, L * 0.43)
	var over := rail + node.transform.basis.x * sd * 0.4
	# it sags out in a long slack curve to the slope (straight down it read as a plumb line ending in the water)
	var touch := over + (ma - over) * 0.17
	var pts := PackedVector3Array([bitt])
	pts.append_array(_hang(over, touch, 0.09))
	var lie := _ground_line(pts[pts.size() - 1], ma + Vector3(0, 0.3, 0), 2.0, 0.09, 4.0, 5)
	pts.append_array(lie.slice(1))
	# two turns round the mast
	var ax := (mb - ma).normalized()
	var s1 := ax.cross(Vector3.UP).normalized()
	for k in 13:
		var a := TAU * 2.0 * float(k) / 12.0
		pts.append(ma + ax * (0.6 + float(k) * 0.06) + (s1 * cos(a) + Vector3.UP * sin(a)) * 0.52)
	Rope.tube(pts, 0.09, 6, rope)
