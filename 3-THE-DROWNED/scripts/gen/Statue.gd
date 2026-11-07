class_name Statue
extends RefCounted
## Beat 4: the kneeling faceless giant of verdigris stone (assets/generated/statue.glb, built by
## tools_py/statue_sdf.py). Local frame: metres, faces +Z, its left hand on +X, origin on the floor
## between the knees. The head turns with the global uw_reveal.y (see shaders/stone.gdshader).

const GLB := "res://assets/generated/statue.glb"
const FACE_CENTER := Vector3(0.0, 396.9, 123.2)     # surface centre of the blank face plane
const FACE_DIR := Vector3(0.0, -0.766, 0.643)       # the face looks down-forward (bowed 50 deg)
const CROWN := Vector3(0.0, 451.9, 139.8)
const HEAD_CENTER := Vector3(0.0, 421.0, 103.0)
const NECK_PIVOT := Vector3(0.0, 372.0, 72.0)
const NECK_AXIS := Vector3(0.0, 0.866, 0.5)
const PALM_CENTER := Vector3(111.3, 199.4, 249.2)   # top of the open left palm (shallow dish)
const PALM_UP := Vector3(0.190, 0.975, -0.117)
const HAND_FWD := Vector3(-0.099, 0.138, 0.986)     # wrist -> fingertips of the left hand
const RIGHT_HAND := Vector3(-100.0, 158.0, 221.0)   # palm down on the slope
## Coarse capsule proxy of the figure (statue-local, from tools_py/statue_sdf.py): [a, b, radius].
## Generous radii: used to keep other objects clear of the stone (Beat03_Forest.gd).
const PROXY := [
	[Vector3(74, 336, 88), Vector3(124, 254, 128), 47.0], [Vector3(124, 254, 128), Vector3(113.5, 188, 214.5), 42.0],
	[Vector3(113.5, 188, 214.5), Vector3(102.3, 203.8, 326.9), 38.0],
	[Vector3(-74, 336, 88), Vector3(-112, 236, 126), 47.0], [Vector3(-112, 236, 126), Vector3(-103.3, 135, 193.6), 42.0],
	[Vector3(-103.3, 135, 193.6), Vector3(-92.9, 207.8, 280.3), 38.0],
	[Vector3(70, 30, 34), Vector3(50, 92, -60), 46.0], [Vector3(-70, 30, 34), Vector3(-50, 92, -60), 46.0],
	[Vector3(0, 105, -62), Vector3(0, 300, 52), 95.0], [Vector3(0, 405, 92), Vector3(0, 425, 110), 55.0],
	[Vector3(-80, 20, 20), Vector3(80, 20, 20), 50.0],
]


## Distance from the world segment a-b to the proxy surface (negative inside).
static func clearance(a: Vector3, b: Vector3, origin: Vector3, yaw_deg := 0.0) -> float:
	var best := INF
	for c: Array in PROXY:
		var p0 := world_point(c[0], origin, yaw_deg)
		var p1 := world_point(c[1], origin, yaw_deg)
		var q := Geometry3D.get_closest_points_between_segments(a, b, p0, p1)
		best = minf(best, q[0].distance_to(q[1]) - float(c[2]))
	return best


static func build(parent: Node3D, origin: Vector3, yaw_deg := 0.0) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = "Statue"
	mi.mesh = _load_mesh()
	var mat := Mats.make("stone", {"neck_pivot": NECK_PIVOT, "neck_axis": NECK_AXIS})
	# QA: --stone-shader=res://<file>.gdshader renders the statue with another stone shader (before/after shots)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stone-shader="):
			var sh := load(a.get_slice("=", 1)) as Shader
			if sh:
				mat.shader = sh
				mat.set_shader_parameter("neck_pivot", NECK_PIVOT)
				mat.set_shader_parameter("neck_axis", NECK_AXIS)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.position = origin
	mi.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	parent.add_child(mi)
	return mi


static func world_point(local: Vector3, origin: Vector3, yaw_deg: float) -> Vector3:
	return origin + local.rotated(Vector3.UP, deg_to_rad(yaw_deg))


static func world_dir(local_dir: Vector3, yaw_deg: float) -> Vector3:
	return local_dir.rotated(Vector3.UP, deg_to_rad(yaw_deg))


static func _load_mesh() -> Mesh:
	var ps := load(GLB) as PackedScene
	if ps == null:
		push_error("Statue: cannot load %s" % GLB)
		return null
	var root := ps.instantiate()
	var m := _find_mesh(root)
	root.free()
	return m


static func _find_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return (n as MeshInstance3D).mesh
	for c in n.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null
