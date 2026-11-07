class_name Fish
extends RefCounted
## Schools of small fish in the sunlit shallows: one MultiMesh per school, every fish animated in
## shaders/fish.gdshader: the school roams and turns as one body (each fish keeps its place in a formation
## stretched along the heading and faces the heading; the turn ripples from front to back), tail beat, shying
## away from the diver. Far away a fish keeps a minimum size on screen and the school thins out, so a distant
## school reads as a few silver dashes, not pepper noise. Life thins out with depth: none below the first wrecks.


## A spindle body with a forked tail, 1 m long along +Z (nose at +Z), flattened sideways.
static func _mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var prof := [[0.5, 0.0, 0.0], [0.36, 0.07, 0.035], [0.12, 0.11, 0.05], [-0.15, 0.08, 0.035], [-0.33, 0.025, 0.012]]
	var rings := []
	var uu := PackedFloat32Array()
	for pr in prof:
		var ring := PackedVector3Array()
		for j in 6:
			var a := TAU * float(j) / 6.0
			ring.append(Vector3(cos(a) * float(pr[2]), sin(a) * float(pr[1]) - 0.01, float(pr[0])))
		rings.append(ring)
		uu.append(float(pr[0]))
	var vv := PackedFloat32Array()
	for j in 6:
		vv.append(float(j) / 6.0)
	mb.grid(rings, uu, vv, true, true)
	# forked tail fin (two thin blades in the vertical plane)
	for sgn in [-1.0, 1.0]:
		var a := mb.vert(Vector3(0.0, 0.0, -0.31), Vector3.RIGHT, Vector2(-0.31, 0.5))
		var b := mb.vert(Vector3(0.0, 0.16 * sgn, -0.52), Vector3.RIGHT, Vector2(-0.52, 0.5))
		var c := mb.vert(Vector3(0.0, 0.05 * sgn, -0.44), Vector3.RIGHT, Vector2(-0.44, 0.5))
		mb.tri(a, b, c)
		var a2 := mb.vert(Vector3(0.0, 0.0, -0.31), Vector3.LEFT, Vector2(-0.31, 0.5))
		var b2 := mb.vert(Vector3(0.0, 0.16 * sgn, -0.52), Vector3.LEFT, Vector2(-0.52, 0.5))
		var c2 := mb.vert(Vector3(0.0, 0.05 * sgn, -0.44), Vector3.LEFT, Vector2(-0.44, 0.5))
		mb.tri(a2, b2, c2)
	return mb.build()


## count fish of length ~size around center; radius = formation half extents (across, up, along the heading),
## roam = how far the school wanders from center; seed varies the school.
static func school(parent: Node3D, center: Vector3, count: int, size: float, radius: Vector3, roam: Vector3,
		seed: int, tint := Color(0.75, 0.8, 0.78)) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh()
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in count:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), size * rng.randf_range(0.75, 1.25), rng.randf()))
	var mi := MultiMeshInstance3D.new()
	mi.name = "FishSchool"
	mi.multimesh = mm
	mi.material_override = Mats.make("fish", {"center": center, "radius": radius, "roam": roam,
		"school_seed": float(seed % 97), "tint": tint})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var ext := radius + roam + Vector3.ONE * 10.0
	mi.custom_aabb = AABB(center - ext, ext * 2.0)
	mi.visibility_range_end = 140.0
	mi.visibility_range_end_margin = 20.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)
	return mi
