class_name Geo
## Small procedural geometry helpers.

## Tube along a polyline (ropes, lines). radius in metres; at least ~3 cm so it never shimmers.
static func tube(points: PackedVector3Array, radius: float, sides := 8) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var prev_side := Vector3.RIGHT
	for i in n:
		var t := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := prev_side - t * prev_side.dot(t)
		if side.length() < 0.01:
			side = t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT)
		side = side.normalized()
		prev_side = side
		var up := t.cross(side).normalized()
		for j in sides + 1:
			var a := TAU * j / sides
			var nrm := side * cos(a) + up * sin(a)
			st.set_normal(nrm)
			st.set_uv(Vector2(float(j) / sides, float(i) / maxf(n - 1, 1)))
			st.add_vertex(points[i] + nrm * radius)
	for i in n - 1:
		for j in sides:
			var a := i * (sides + 1) + j
			var b := a + sides + 1
			st.add_index(a); st.add_index(b); st.add_index(a + 1)
			st.add_index(a + 1); st.add_index(b); st.add_index(b + 1)
	return st.commit()

## Quadratic sag curve between two points (a hanging line).
static func sag(a: Vector3, b: Vector3, sag_m: float, count := 40) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in count + 1:
		var t := float(i) / count
		pts.append(a.lerp(b, t) + Vector3.DOWN * sag_m * 4.0 * t * (1.0 - t))
	return pts

## Surface of revolution around +Y from a (radius, y) profile.
static func lathe(profile: PackedVector2Array, sides := 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size():
		for j in sides + 1:
			var a := TAU * j / sides
			st.set_uv(Vector2(float(j) / sides, float(i) / (profile.size() - 1)))
			st.add_vertex(Vector3(cos(a) * profile[i].x, profile[i].y, sin(a) * profile[i].x))
	for i in profile.size() - 1:
		for j in sides:
			var a := i * (sides + 1) + j
			var b := a + sides + 1
			st.add_index(a); st.add_index(a + 1); st.add_index(b)
			st.add_index(a + 1); st.add_index(b + 1); st.add_index(b)
	st.generate_normals()
	return st.commit()

static func mat(color: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

static func rope_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/rope.gdshader")
	return m
