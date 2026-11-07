extends RefCounted
## Beat 3 — The Lip: a massive overhanging rock roof juts out over the path just before the wall ends in its prow
## (compress), then the face turns away and only open blue remains (release). The prow itself is the wall outline.

const ReefGen := preload("res://scripts/reef/ReefGen.gd")
const ReefRoof := preload("res://scripts/reef/ReefRoof.gd")
const ReefDress := preload("res://scripts/reef/ReefDress.gd")

func build(parent: Node3D) -> void:
	var reef: Node3D = parent.get_node_or_null("Reef")
	if reef == null:
		reef = parent
	var gen = reef.get_meta("gen") if reef.has_meta("gen") else null
	if gen == null:
		gen = ReefGen.new()
		gen.wall_mesh([])
	var rock: Material = reef.get_meta("rock") if reef.has_meta("rock") else null
	if rock == null:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/reef.gdshader")
		rock = sm
	var t0 := Time.get_ticks_msec()
	var pts: Array = []
	var roof := MeshInstance3D.new()
	roof.name = "Overhang"
	roof.mesh = ReefRoof.mesh(gen, pts)
	# the roof's own copy of the rock material: its undersides are lit sideways by the open water around the lip
	# (reef.gdshader roof_*; the wall keeps the plain rock shading)
	var roof_mat := rock.duplicate() as ShaderMaterial
	if roof_mat != null:
		roof_mat.set_shader_parameter("roof_open", 1.0)
		# a little gentler than the shader default (4.0): at full strength the side light showed the roof's flat tier
		# facets and straight creases as crumpled paper (final review); the relief still reads
		roof_mat.set_shader_parameter("roof_side", 3.2)
		roof_mat.set_shader_parameter("roof_centre", ReefRoof.C)
		roof.material_override = roof_mat
	else:
		roof.material_override = rock
	reef.add_child(roof)
	var t1 := Time.get_ticks_msec()
	var vs: Dictionary = reef.get_meta("variants") if reef.has_meta("variants") else ReefDress.variants()
	var n := ReefDress.dress(reef, pts, 99, vs)
	print("PELAGIC lip build: roof %d ms, dressing %d ms (%d props)" % [t1 - t0, Time.get_ticks_msec() - t1, n])
	if reef.has_meta("gen"):
		reef.remove_meta("gen")       # the generator is only needed while building
	var t := Node3D.new()
	t.name = "T_lip_look"
	reef.add_child(t)
	t.global_position = Vector3(-33.0, -112.0, -408.0)
	Game.targets["lip_look"] = t
	# the roof gaze point sits just under the real underside above the path (its height follows the relief)
	var rf := Node3D.new()
	rf.name = "T_lip_roof"
	reef.add_child(rf)
	rf.global_position = _under_roof(roof.mesh, Vector3(-6.0, -93.0, -372.0))
	Game.targets["lip_roof"] = rf
	# looking back on the way into the open blue: the lip's south rim, a dark shelf against the light above (the far
	# face of the wall is lost in the haze from there)
	var b := Node3D.new()
	b.name = "T_wall_back"
	reef.add_child(b)
	b.global_position = _under_roof(roof.mesh, Vector3(-8.0, -92.0, -425.0))
	Game.targets["wall_back"] = b

## The lowest underside point of the roof within 3 m (horizontally) of `q`, lowered by 2 m; `q` if none is found.
static func _under_roof(mesh: Mesh, q: Vector3) -> Vector3:
	if mesh == null or mesh.get_surface_count() == 0:
		return q
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var best := INF
	for v in verts:
		if absf(v.x - q.x) < 3.0 and absf(v.z - q.z) < 3.0 and v.y > q.y - 15.0 and v.y < best:
			best = v.y
	return Vector3(q.x, best - 2.0, q.z) if best < INF else q
