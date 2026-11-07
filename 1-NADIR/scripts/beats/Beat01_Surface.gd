extends Node3D
## Beat 1 — Surface (0:00-0:40, 0-80 m). Snell's window overhead, wave-distorted sun, raymarched sun rays,
## the small boat the line hangs from, a school of fish, the weight below. Calm before the drop.

const SUN_YAW := -128.5          # horizontal direction toward the (refracted) sun
const WaterEnvScript := preload("res://scripts/WaterEnv.gd")
var depth_range := Vector2(0.0, 420.0)
var surface: MeshInstance3D
var boat: Node3D
var rays: MeshInstance3D
var _surf_mat: ShaderMaterial
var _rays_mat: ShaderMaterial
var _fish_mat: ShaderMaterial
var _boat_mats: Array[ShaderMaterial] = []
var _school: Node3D
var _school_centre := Vector3(-9.0, -31.0, -6.0)
var _ray_tex: NoiseTexture2D      # the caustic net: the ray pass, and the light playing on the fish and the hull


func build(parent: Node3D) -> void:
	name = "Beat01_Surface"
	parent.add_child(self)
	_build_surface()
	_build_sun_rays()
	_build_boat()
	_school = _build_fish()
	var P := G.path
	var down_line := func(): return G.path.rope_at(G.player.s + 26.0)
	P.add_cue_depth(0.0, 9.0, Vector2(SUN_YAW, 58.0), 2.5)
	P.add_cue_depth(9.0, 25.0, boat, 3.0)
	P.add_cue_depth(25.0, 44.0, _school, 3.5)
	P.add_cue_depth(44.0, 58.0, down_line, 3.0)
	# the last look up: the window shrinking overhead, the rays converging on it, the boat a speck
	P.add_cue_depth(58.0, 76.0, Vector2(SUN_YAW, 75.0), 3.0)
	P.add_cue_depth(76.0, 82.0, down_line, 3.0)


## Underwater direction toward the sun (the refracted sun the DirectionalLight and the rays use).
static func to_sun() -> Vector3:
	return -WaterEnvScript.SUN_DIR.normalized()


func _build_surface() -> void:
	surface = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(7000, 7000)
	surface.mesh = pm
	_surf_mat = ShaderMaterial.new()
	_surf_mat.shader = load("res://shaders/surface.gdshader")
	# Snell's law backwards: the sun disc in the window sits exactly where the rays converge.
	var u := to_sun()
	var h := Vector2(u.x, u.z) * 1.333
	_surf_mat.set_shader_parameter("sun_air", Vector3(h.x, sqrt(maxf(1.0 - h.length_squared(), 0.0)), h.y))
	_surf_mat.set_shader_parameter("to_sun", u)
	# capillary ripples: a tiling normal map, sampled at two scales in the shader
	var rn := FastNoiseLite.new()
	rn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	rn.frequency = 0.012
	rn.fractal_octaves = 3
	rn.seed = 5
	var rtx := NoiseTexture2D.new()
	rtx.width = 512
	rtx.height = 512
	rtx.seamless = true
	rtx.as_normal_map = true
	rtx.bump_strength = 4.0
	rtx.generate_mipmaps = true
	rtx.noise = rn
	_surf_mat.set_shader_parameter("ripple_tex", rtx)
	# faint clouds in the refracted sky
	var cn := FastNoiseLite.new()
	cn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cn.frequency = 0.006
	cn.fractal_octaves = 5
	cn.seed = 9
	var ctx := NoiseTexture2D.new()
	ctx.width = 512
	ctx.height = 512
	ctx.seamless = true
	ctx.generate_mipmaps = true
	ctx.noise = cn
	_surf_mat.set_shader_parameter("cloud_tex", ctx)
	surface.material_override = _surf_mat
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.custom_aabb = AABB(Vector3(-3500, -1, -3500), Vector3(7000, 2, 7000))
	add_child(surface)


## Sun rays: one full-screen raymarch pass on the camera (shaders/sun_rays.gdshader), like BeamHaze.
func _build_sun_rays() -> void:
	rays = MeshInstance3D.new()
	rays.name = "SunRays"
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	rays.mesh = q
	_rays_mat = ShaderMaterial.new()
	_rays_mat.shader = load("res://shaders/sun_rays.gdshader")
	var cn := FastNoiseLite.new()
	cn.noise_type = FastNoiseLite.TYPE_CELLULAR
	cn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cn.fractal_type = FastNoiseLite.FRACTAL_NONE
	cn.frequency = 0.03
	cn.seed = 11
	var rt := NoiseTexture2D.new()
	rt.width = 256
	rt.height = 256
	rt.seamless = true
	rt.generate_mipmaps = true
	rt.noise = cn
	_ray_tex = rt
	_rays_mat.set_shader_parameter("ray_tex", rt)
	_rays_mat.set_shader_parameter("to_sun", to_sun())
	rays.material_override = _rays_mat
	rays.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rays.extra_cull_margin = 16384.0
	rays.position = Vector3(0.0, 0.0, -1.0)
	G.camera.add_child(rays)


func _boat_material(col: Color, rough: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/boat_hull.gdshader")
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("roughness", rough)
	if _ray_tex:
		m.set_shader_parameter("caustic_tex", _ray_tex)
		m.set_shader_parameter("caustic_gain", 1.0)
	_boat_mats.append(m)
	return m


func _build_boat() -> void:
	boat = Node3D.new()
	boat.name = "Boat"
	var rope_top := G.path.rope_at(0.0)
	# the line sits inside the hull (boat-local x -0.52, z 0.965) and leaves the hull skin ~0.18 m under the
	# waterline at every bob phase, so it always reads as hanging from the boat, never as a pole beside it
	boat.position = Vector3(rope_top.x + 0.2, 0.05, rope_top.z - 1.08)
	boat.rotation_degrees = Vector3(0, 18, 0)
	add_child(boat)
	var hull := MeshInstance3D.new()
	hull.mesh = _hull_mesh(6.4, 2.3, 0.85)
	hull.material_override = _boat_material(Color(0.08, 0.085, 0.09), 0.75)
	boat.add_child(hull)
	# outboard leg + propeller housing at the stern, keel strip: readable silhouette details
	var dark := _boat_material(Color(0.06, 0.06, 0.07), 0.5)
	var leg := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.85, 0.12)
	leg.mesh = bm
	leg.material_override = dark
	leg.position = Vector3(-3.3, -0.45, 0)
	boat.add_child(leg)
	var pod := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.09
	cm.height = 0.5
	pod.mesh = cm
	pod.material_override = dark
	pod.position = Vector3(-3.3, -0.85, 0)
	pod.rotation_degrees = Vector3(0, 0, 90)
	boat.add_child(pod)
	var keel := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(5.2, 0.12, 0.06)
	keel.mesh = km
	keel.material_override = dark
	keel.position = Vector3(0.1, -0.86, 0)
	boat.add_child(keel)
	for mi in [hull, leg, pod, keel]:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_fish() -> Node3D:
	# A milling bait ball of ~320 small fish 9-12 m from the line around 30 m depth: life, and a human scale.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _fish_mesh()
	mm.instance_count = 320
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in mm.instance_count:
		mm.set_instance_transform(i, Transform3D())
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	_fish_mat = ShaderMaterial.new()
	_fish_mat.shader = load("res://shaders/fish.gdshader")
	_fish_mat.set_shader_parameter("center", _school_centre)
	if _ray_tex:
		_fish_mat.set_shader_parameter("caustic_tex", _ray_tex)
		_fish_mat.set_shader_parameter("caustic_gain", 2.0)
	mi.material_override = _fish_mat
	mi.custom_aabb = AABB(_school_centre - Vector3(16, 8, 16), Vector3(32, 16, 32))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var marker := Node3D.new()
	marker.position = _school_centre
	add_child(marker)
	return marker


## A small fusiform bait fish (~0.38 m before the per-instance scale), snout at +X: 5 elliptic rings x 6 sides
## between a snout and a peduncle point with smooth analytic normals, and a thin forked tail of 3 triangles
## (63 triangles, clockwise front faces). The flank plane's normal is the instance's `side` axis (Z), which the
## shader uses as the mirror.
func _fish_mesh() -> ArrayMesh:
	const SIDES := 6
	var xs: Array[float] = [0.17, 0.125, 0.075, 0.03, -0.025, -0.08, -0.12]
	var hs: Array[float] = [0.0, 0.026, 0.040, 0.045, 0.036, 0.018, 0.0]    # half height
	var ws: Array[float] = [0.0, 0.013, 0.019, 0.022, 0.018, 0.009, 0.0]    # half width
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# vertex 0: snout, 1..5*SIDES: rings, last: peduncle
	st.set_normal(Vector3(1, 0, 0))
	st.add_vertex(Vector3(xs[0], 0.002, 0))
	for i in range(1, 6):
		var dh := (hs[i + 1] - hs[i - 1]) / (xs[i + 1] - xs[i - 1])
		var dw := (ws[i + 1] - ws[i - 1]) / (xs[i + 1] - xs[i - 1])
		for j in SIDES:
			var ph := TAU * float(j) / SIDES
			var s := sin(ph)
			var c := cos(ph)
			# outward normal of p(x, ph) = (x, h c, w s): (-(h w' s^2 + w h' c^2), w c, h s)
			var n := Vector3(-(hs[i] * dw * s * s + ws[i] * dh * c * c), ws[i] * c, hs[i] * s).normalized()
			st.set_normal(n)
			st.add_vertex(Vector3(xs[i], hs[i] * c, ws[i] * s))
	var tail := 1 + 5 * SIDES
	st.set_normal(Vector3(-1, 0, 0))
	st.add_vertex(Vector3(xs[6], 0.002, 0))
	for j in SIDES:
		var j1 := (j + 1) % SIDES
		st.add_index(0)
		st.add_index(1 + j1)
		st.add_index(1 + j)
		for i in 4:
			var a := 1 + i * SIDES
			var b := a + SIDES
			st.add_index(a + j)
			st.add_index(a + j1)
			st.add_index(b + j)
			st.add_index(b + j)
			st.add_index(a + j1)
			st.add_index(b + j1)
		var last := 1 + 4 * SIDES
		st.add_index(last + j)
		st.add_index(last + j1)
		st.add_index(tail)
	# forked tail, flat in the flank plane
	var base := tail + 1
	for p in [Vector3(-0.112, 0.008, 0), Vector3(-0.112, -0.007, 0), Vector3(-0.165, 0.0, 0),
			Vector3(-0.215, 0.058, 0), Vector3(-0.212, -0.05, 0)]:
		st.set_normal(Vector3(0, 0, -1))   # matches the winding below (front face seen from -Z)
		st.add_vertex(p)
	for k in [0, 3, 2, 1, 2, 4, 0, 2, 1]:
		st.add_index(base + k)
	return st.commit()


func _hull_mesh(length: float, beam: float, depth: float) -> ArrayMesh:
	# Half-ellipsoid hull, flat deck at y = 0.25, pointed bow at +X.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 28
	var nv := 10
	for i in nu + 1:
		var u := float(i) / nu
		var x := lerpf(-length * 0.5, length * 0.5, u)
		var taper := sqrt(maxf(1.0 - pow((x - 0.2) / (length * 0.56), 2.0), 0.0))
		if u < 0.06:
			taper = lerpf(0.75, taper, u / 0.06)
		for j in nv + 1:
			var a := PI * float(j) / nv
			var y := -sin(a) * depth * pow(taper, 0.6) + 0.25
			var z := cos(a) * beam * 0.5 * taper
			st.set_uv(Vector2(u, float(j) / nv))
			st.add_vertex(Vector3(x, y, z))
	for i in nu:
		for j in nv:
			var a := i * (nv + 1) + j
			var b := a + nv + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	st.generate_normals()
	return st.commit()


func _process(_dt: float) -> void:
	if not G.camera:
		return
	var c := G.camera.global_position
	# EYE-ADAPTATION CONTRACT: the one water colour every consumer reads (the shared package dims it after the
	# torch click); the surface plane, the boat fog and the fish follow it, so looking up never shows a lighter disc
	var raw := Palette.water_at(G.depth)
	var water: Color = G.env.fog_light_color if G.env else raw
	# the same adaptation for the light that is not water colour (window, rays): 1 until the shared package dims
	var raw_sum := raw.r + raw.g + raw.b
	var adapt: float = clampf((water.r + water.g + water.b) / raw_sum, 0.0, 1.5) if raw_sum > 0.00001 else 1.0
	var fog: float = G.env.fog_density if G.env else 0.0085
	surface.global_position = Vector3(c.x, 0.0, c.z)
	_surf_mat.set_shader_parameter("water_col", water)
	_surf_mat.set_shader_parameter("scene_fog", fog)
	_surf_mat.set_shader_parameter("adapt", adapt)
	# boat: bobbing; dissolves with depth instead of shrinking into a speck in the window
	boat.position.y = 0.05 + 0.06 * sin(G.t * 0.9)
	boat.rotation_degrees.z = 1.5 * sin(G.t * 0.7)
	var fade := 1.0 - smoothstep(150.0, 230.0, G.depth)
	boat.visible = fade > 0.0 and G.depth < 235.0
	for m in _boat_mats:
		m.set_shader_parameter("fade", fade)
		m.set_shader_parameter("scene_fog", fog)
		m.set_shader_parameter("water_col", water)
	# sun rays: off once daylight is gone
	var daylight := exp(-G.depth / 42.0) * (1.0 - smoothstep(180.0, 260.0, G.depth))
	rays.visible = G.depth < 250.0 and daylight > 0.003
	if rays.visible:
		_rays_mat.set_shader_parameter("sigma", fog)
		_rays_mat.set_shader_parameter("adapt", adapt)
		var bp := boat.global_position
		_rays_mat.set_shader_parameter("boat", Vector4(bp.x, bp.z, boat.rotation.y, 1.0 if boat.visible else 0.0))
	# fish: the gaze cue follows the school's slow drift (same Lissajous as fish.gdshader)
	var tt := G.t
	_school.position = _school_centre + Vector3(sin(tt * 0.05), 0.3 * sin(tt * 0.08), cos(tt * 0.04)) * 3.0
	_fish_mat.set_shader_parameter("water_col", water)
