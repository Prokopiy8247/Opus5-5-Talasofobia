extends RefCounted
## Beat 2 — The Wall: the reef-top plateau (seen in beat 1), the vast wall face dropping out of sight on the left
## in bays and buttresses, detached pinnacles in front of it and bommies on the reef top (scripts/reef/ReefGen.gd),
## and its dressing (coral heads, barrel and tube sponges, plate corals, sea fans, sea rods; scripts/reef/ReefDress.gd).
## Beat03_Lip.gd adds the overhang.

const ReefGen := preload("res://scripts/reef/ReefGen.gd")
const ReefDress := preload("res://scripts/reef/ReefDress.gd")

func build(parent: Node3D) -> void:
	var t0 := Time.get_ticks_msec()
	var gen = ReefGen.new()
	var root := Node3D.new()
	root.name = "Reef"
	root.set_script(load("res://scripts/reef/ReefVisibility.gd"))
	parent.add_child(root)
	var rock := ShaderMaterial.new()
	rock.shader = load("res://shaders/reef.gdshader")
	root.set_meta("rock", rock)
	root.set_meta("gen", gen)       # Beat03 builds the lip against the same wall, then drops it
	var pts: Array = []
	var wall := MeshInstance3D.new()
	wall.name = "WallFace"
	wall.mesh = gen.wall_mesh(pts)
	wall.material_override = rock
	root.add_child(wall)
	var t1 := Time.get_ticks_msec()
	var plateau := MeshInstance3D.new()
	plateau.name = "Plateau"
	plateau.mesh = gen.plateau_mesh(pts, Vector3(-42.0, -15.0, -40.0))
	plateau.material_override = rock
	plateau.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(plateau)
	var t2 := Time.get_ticks_msec()
	var vs := ReefDress.variants()
	root.set_meta("variants", vs)
	var n := ReefDress.dress(root, pts, 404, vs)
	var look := Node3D.new()
	look.name = "T_wall_look_1"
	root.add_child(look)
	look.global_position = _nearest_face(pts, Vector3(-28.0, -38.0, -165.0))
	Game.targets["wall_look_1"] = look
	print("PELAGIC reef: wall %d ms (%d rock columns), plateau %d ms, dressing %d ms (%d props)" % [t1 - t0, gen.columns, t2 - t1, Time.get_ticks_msec() - t2, n])

func _nearest_face(pts: Array, q: Vector3) -> Vector3:
	var best := q
	var bd := 1e9
	for p in pts:
		if p[3] != 0:
			continue
		var d: float = (p[0] as Vector3).distance_squared_to(q)
		if d < bd:
			bd = d; best = p[0]
	return best
