class_name Atmos
extends RefCounted
## Marine snow around the camera, soft sun shafts, the water surface seen from below.
## surface_material: the surface's ShaderMaterial once build_surface() ran (Beat01 sets the boat on it:
## shaders/surface.gdshader `boat`, `boat_size`).

static var surface_material: ShaderMaterial

static func build_snow(parent: Node3D, count := 9000, box := 36.0) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in count:
		var p := Vector3(rng.randf() * box, rng.randf() * box, rng.randf() * box)
		var r := rng.randf()
		var b := verts.size()
		for c in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			verts.append(p)
			uvs.append(c)
			uv2.append(Vector2(r, 0))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "MarineSnow"
	mi.mesh = mesh
	mi.material_override = Mats.make("snow", {"box": box})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-50000, -50000, -50000), Vector3(100000, 100000, 100000))
	parent.add_child(mi)
	return mi


## Sun shafts falling from the surface along Config.SUN_DIR. centers: Array of Vector3 (top point at the
## surface); widths (optional, one per centre) overrides the random width. Each shaft is a strip of axis
## points; shaders/shaft.gdshader turns it around its axis to face the camera (UV.x side, UV.y along, UV2 =
## random, half width; COLOR = brightness, rays in the bundle / 8, length / 300 m). It widens 2.6-4x with depth.
static func build_shafts(parent: Node3D, centers: Array, len_range := Vector2(60, 140), width_range := Vector2(3, 9),
		intensity := 0.35, widths := PackedFloat32Array()) -> MeshInstance3D:
	const SEG := 12
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var dir := Config.SUN_DIR.normalized()
	var lsum := 0.0
	for ci in centers.size():
		var top: Vector3 = centers[ci]
		var ln := rng.randf_range(len_range.x, len_range.y)
		var w := rng.randf_range(width_range.x, width_range.y)
		if ci < widths.size():
			w = widths[ci]
		var r := rng.randf()
		var spread := rng.randf_range(2.6, 4.0)
		# thin shafts hold one or two rays; wide ones are faint bundles of many. A thin one no brighter than
		# the rest: alone in the frame it read as a lit pole
		var thin := 1.0 - smoothstep(2.0, 9.0, w)
		var bright := clampf(rng.randf_range(0.45, 1.0) * lerpf(0.75, 0.9, thin), 0.0, 1.0)
		var rays := lerpf(4.5, 1.6, thin) * rng.randf_range(0.8, 1.25)
		var col := Color(bright, rays / 8.0, ln / 300.0, 0.0)    # vertex colours are 8-bit unorm
		lsum += ln
		var b := verts.size()
		for i in SEG + 1:
			var t := float(i) / float(SEG)
			var p := top + dir * (ln * t)
			var hw := w * 0.5 * lerpf(1.0, spread, t)
			for sd in 2:
				verts.append(p)
				uvs.append(Vector2(float(sd), t))
				uv2.append(Vector2(r, hw))
				cols.append(col)
		for i in SEG:
			var a := b + i * 2
			idx.append_array([a, a + 1, a + 3, a, a + 3, a + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Shafts"
	mi.mesh = mesh
	mi.material_override = Mats.make("shaft", {"intensity": intensity, "shaft_dir": dir,
		"shaft_len": lsum / maxf(float(centers.size()), 1.0)})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 60.0
	parent.add_child(mi)
	return mi


static func build_surface(parent: Node3D) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = pm
	surface_material = Mats.make("surface", {"sun_dir": Config.SUN_DIR})
	mi.material_override = surface_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, Config.SURFACE_Y, 0)
	parent.add_child(mi)
	return mi
