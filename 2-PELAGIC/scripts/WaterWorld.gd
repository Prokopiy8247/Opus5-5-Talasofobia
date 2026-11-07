extends Node3D
## The water itself: environment, sun, sky backdrop, surface from below, sun shafts, near-field ray volume,
## suspended particles. Everything is driven by the camera depth and the path time every frame.

const SHAFT_ROWS := 16      # ribbon subdivisions along the light, so the swell can rock a shaft along its length
const RAY_SLICES := 5       # slab spacing of the ray volume (light_volume.gdshader); the nearest is not built

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var surface: MeshInstance3D
var shaft_mat: ShaderMaterial
var ray_mat: ShaderMaterial
var ray_node: MeshInstance3D
var thread_mat: ShaderMaterial
var thread_mm: MultiMesh
var _threads_anchored := false
var snow_mat: ShaderMaterial
var bokeh_mat: ShaderMaterial
var fog_scale := 1.0
var _bench := false
var _bench_t := 0.0
var _bench_frames := 0
var _bench_sum := [0.0, 0.0]
var _bench_n := [0, 0]

func _ready() -> void:
	_build_environment()
	_build_sun()
	_build_surface()
	_build_shafts()
	_build_threads()
	_build_rays()
	# QA switches: -- --no-rays hides the near-field ray volume (A/B captures); -- --ray-bench shows and hides it
	# every 0.5 s and prints the average GPU frame time of both states (cost of the volume, same frames, same run)
	var qa_args := OS.get_cmdline_user_args()
	if "--no-rays" in qa_args:
		ray_node.visible = false
	_bench = "--ray-bench" in qa_args
	_build_snow()
	_build_bokeh()

func _build_environment() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky_water.gdshader")
	sky_mat.set_shader_parameter("sun_w", Config.sun_dir_water())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.tonemap_white = 6.0
	# grade: a little less saturation, a little more contrast (exposure and contrast follow the depth in update_water)
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.86
	env.adjustment_contrast = 1.06
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for i in 7:
		env.set_glow_level(i, i >= 2 and i <= 5)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.008
	env.fog_aerial_perspective = 1.0
	env.fog_sky_affect = 0.0
	env.fog_light_color = Palette.SURF_TURQ
	env.fog_sun_scatter = 0.0
	# No volumetric fog: shaders that write FOG (all custom ones) never receive it, so it only made the few
	# standard-material objects mismatch the water. Rays are the lit ray volume and ribbons cut by the shadow map.
	env.volumetric_fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _build_sun() -> void:
	sun = DirectionalLight3D.new()
	# light travels along the refracted direction under water (shadows and shafts agree)
	sun.basis = Basis.looking_at(-Config.sun_dir_water(), Vector3.UP)
	sun.light_color = Palette.SUN
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 170.0
	sun.directional_shadow_blend_splits = true   # no straight seams where the cascades change (rays, reef)
	sun.shadow_blur = 1.5
	sun.light_angular_distance = 0.6
	add_child(sun)

func _noise_tex(freq: float, seed_: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.seed = seed_
	n.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 6.0
	t.noise = n
	return t

## Seamless 0..1 noise (256 x 256, L8 bytes) for the ray field.
func _ray_noise_bytes(seed_: int) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.03
	n.seed = seed_
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 2
	var img := n.get_seamless_image(256, 256, false, false, 0.1, true)
	img.convert(Image.FORMAT_L8)
	return img.get_data()

## The ray volume's beam field, built synchronously (no first-frames pop): R and G two shapes of the narrow focus
## pattern (each the focus spots of one noise times the slow modulation of another; the shader morphs between them),
## B wide veils, A a raw noise. The shaping happens BEFORE the mipmaps are built, so a blurred lookup (the shader
## averages the field over each slab's footprint) is the true average of the beams; the means set below keep the
## volume's average at zero.
func _ray_noise(mat: ShaderMaterial) -> ImageTexture:
	var na := _ray_noise_bytes(41)
	var nb := _ray_noise_bytes(42)
	var nc := _ray_noise_bytes(43)
	var nd := _ray_noise_bytes(44)
	var px := na.size()
	var out := PackedByteArray()
	out.resize(px * 4)
	var sf := 0.0
	var sw := 0.0
	for i in px:
		var a := na[i] / 255.0
		var p1 := smoothstep(0.45, 0.85, a) * lerpf(0.35, 1.0, smoothstep(0.30, 0.80, nb[i] / 255.0))
		var p2 := smoothstep(0.45, 0.85, nc[i] / 255.0) * lerpf(0.35, 1.0, smoothstep(0.30, 0.80, nd[i] / 255.0))
		var w := smoothstep(0.45, 0.75, a)
		out[i * 4] = int(round(p1 * 255.0))
		out[i * 4 + 1] = int(round(p2 * 255.0))
		out[i * 4 + 2] = int(round(w * 255.0))
		out[i * 4 + 3] = na[i]
		sf += 0.5 * (p1 + p2)
		sw += w
	var img := Image.create_from_data(256, 256, false, Image.FORMAT_RGBA8, out)
	img.generate_mipmaps()
	mat.set_shader_parameter("fine_norm", float(px) / maxf(sf, 1.0))
	mat.set_shader_parameter("wide_norm", float(px) / maxf(sw, 1.0))
	return ImageTexture.create_from_image(img)

func _build_surface() -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water_surface.gdshader")
	m.set_shader_parameter("wave_a", _noise_tex(0.012, 3))
	m.set_shader_parameter("wave_b", _noise_tex(0.03, 7))
	m.set_shader_parameter("sun_air", Config.sun_dir())
	var pm := PlaneMesh.new()
	pm.size = Vector2(5000, 5000)
	surface = MeshInstance3D.new()
	surface.mesh = pm
	surface.material_override = m
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)

## A unit quad (x -0.5..0.5, y 0..1) split into `rows` strips along y.
func _quad_mesh(rows := 1) -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in rows + 1:
		var y := float(j) / float(rows)
		v.append(Vector3(-0.5, y, 0.0)); uv.append(Vector2(0.0, y))
		v.append(Vector3(0.5, y, 0.0)); uv.append(Vector2(1.0, y))
	for j in rows:
		var b := j * 2
		idx.append_array(PackedInt32Array([b, b + 1, b + 3, b, b + 3, b + 2]))
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m

func _multimesh_node(count: int, mat: ShaderMaterial, rng: RandomNumberGenerator, width: Vector2, rows := 1) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _quad_mesh(rows)
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		if width.x > 0.0:
			mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), lerpf(width.x, width.y, pow(rng.randf(), 2.2)), rng.randf()))
		else:
			mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	add_child(node)
	return node

func _build_shafts() -> void:
	shaft_mat = ShaderMaterial.new()
	shaft_mat.shader = load("res://shaders/shaft.gdshader")
	shaft_mat.render_priority = -1        # behind the ray volume, which then shades them like any far light
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var node := _multimesh_node(150, shaft_mat, rng, Vector2.ZERO, SHAFT_ROWS)
	# wide faint veils, a few narrower ones (the ray volume draws the fine beams near the diver; thin far ribbons
	# only ever read as scratches)
	var mm := node.multimesh
	for i in mm.instance_count:
		var narrow := rng.randf() < 0.3
		var w := lerpf(4.0, 5.5, rng.randf()) if narrow else lerpf(5.0, 16.0, pow(rng.randf(), 1.4))
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), w, rng.randf()))

## A few thin shafts anchored near the head at the eye lock (positions set in _anchor_threads at ~380 s).
func _build_threads() -> void:
	thread_mat = ShaderMaterial.new()
	thread_mat.shader = load("res://shaders/shaft.gdshader")
	thread_mat.render_priority = -1
	thread_mat.set_shader_parameter("threads", true)
	thread_mat.set_shader_parameter("amount", 0.0)
	thread_mat.set_shader_parameter("gain", 0.035)
	thread_mat.set_shader_parameter("shaft_len", 700.0)   # reaching well below the eye-lock depth (~290 m)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	thread_mm = _multimesh_node(3, thread_mat, rng, Vector2.ZERO, SHAFT_ROWS).multimesh

## Threads pass beside the creature's eye (or 70 m ahead when it is missing), fixed in the world from then on.
func _anchor_threads(cam_pos: Vector3) -> void:
	_threads_anchored = true
	var p := cam_pos + Vector3(0.0, 0.0, -70.0)
	var cam := get_viewport().get_camera_3d()
	if cam:
		p = cam_pos - cam.global_transform.basis.z * 70.0
	var eye = Game.targets.get("eye")
	if eye is Node3D:
		p = eye.global_position
	var to := Vector3(p.x - cam_pos.x, 0.0, p.z - cam_pos.z).normalized()
	if to.length() < 0.5:
		to = Vector3.FORWARD
	var side := Vector3(-to.z, 0.0, to.x)
	var sun := Config.sun_dir_water()
	# (side, behind) in metres from the eye: at least ~20 m to the side, so no thread passes behind the eye (the eye
	# stays the only point of light) - two in the open water beside the snout, one beyond the body
	var offs := [Vector2(-22.0, 6.0), Vector2(-40.0, -10.0), Vector2(46.0, 14.0)]
	for i in 3:
		var o: Vector2 = offs[i]
		var q := p + side * o.x + to * o.y
		var entry := Vector2(q.x, q.z) + Vector2(sun.x, sun.z) * (maxf(-q.y, 0.0) / maxf(sun.y, 0.2))
		# wide soft columns (9-13 m: 75-110 px at the head), so they read as light, never as lines
		thread_mm.set_instance_custom_data(i, Color(entry.x, entry.y, 9.0 + 2.0 * i, 0.31 + 0.23 * i))

## Near-field ray volume: camera-facing layers in ONE mesh (signed additive, so their order does not matter). The
## shader places them in view space; the node only sorts them among transparents. Cost at 1080p MSAA 4 on an
## RTX 5070: -- --ray-bench measures it (A/B in the same run); -- --no-rays hides it for A/B captures.
func _build_rays() -> void:
	ray_mat = ShaderMaterial.new()
	ray_mat.shader = load("res://shaders/light_volume.gdshader")
	ray_mat.set_shader_parameter("ray_noise", _ray_noise(ray_mat))
	ray_mat.set_shader_parameter("slices", float(RAY_SLICES))
	ray_node = MeshInstance3D.new()
	ray_node.mesh = _slice_mesh(RAY_SLICES)
	ray_node.material_override = ray_mat
	ray_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ray_node.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	add_child(ray_node)

## `count` camera-facing layers in one mesh, far to near; each a gx x gy grid (the shader computes colour and
## opacity per vertex). UV = position on the layer 0..1, UV2.x = 0 (nearest) .. 1 (farthest).
## The nearest slab (~3-6 m) is not built: it holds ~3 % of the in-scatter and no beam pattern (the pattern fades in
## from 6 m), so it only cost a full-screen layer (~0.17 ms); the volume starts at ~6 m.
func _slice_mesh(count: int, gx := 6, gy := 4) -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in count - 1:
		var f := 1.0 - float(i) / float(count - 1)
		var b := v.size()
		for y in gy + 1:
			for x in gx + 1:
				var c := Vector2(float(x) / gx, float(y) / gy)
				v.append(Vector3(c.x - 0.5, c.y - 0.5, -1.0 - f))
				uv.append(c)
				uv2.append(Vector2(f, 0.0))
		for y in gy:
			for x in gx:
				var o := b + y * (gx + 1) + x
				idx.append_array(PackedInt32Array([o, o + 1, o + gx + 2, o, o + gx + 2, o + gx + 1]))
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_TEX_UV2] = uv2
	a[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m

func _build_snow() -> void:
	snow_mat = ShaderMaterial.new()
	snow_mat.shader = load("res://shaders/snow.gdshader")
	snow_mat.render_priority = 1          # in front of the ray volume layers
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_multimesh_node(9000, snow_mat, rng, Vector2.ZERO)

func _build_bokeh() -> void:
	bokeh_mat = ShaderMaterial.new()
	bokeh_mat.shader = load("res://shaders/water_bokeh.gdshader")
	bokeh_mat.render_priority = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	_multimesh_node(60, bokeh_mat, rng, Vector2.ZERO)

## QA cost bench (-- --ray-bench): alternates the ray volume every 0.5 s and averages the GPU frame time of each state,
## skipping the first frames after a switch (the measurement lags). Prints a summary every 10 s.
func _process(delta: float) -> void:
	if not _bench:
		return
	var vp := get_viewport().get_viewport_rid()
	if _bench_t == 0.0:
		RenderingServer.viewport_set_measure_render_time(vp, true)
	_bench_t += delta
	_bench_frames += 1
	if _bench_t > 3.0 and _bench_frames > 6:
		var k := 1 if ray_node.visible else 0
		_bench_sum[k] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		_bench_n[k] += 1
	if fmod(_bench_t, 0.5) < delta:
		ray_node.visible = not ray_node.visible
		_bench_frames = 0
	if fmod(_bench_t, 10.0) < delta and _bench_n[0] > 0 and _bench_n[1] > 0:
		var off: float = _bench_sum[0] / _bench_n[0]
		var on: float = _bench_sum[1] / _bench_n[1]
		print("RAY_BENCH t=%.0f path=%.0f off=%.3f(%d) rays=%.3f(%d) cost=%.3f ms" % [
			_bench_t, Game.path_time, off, _bench_n[0], on, _bench_n[1], on - off])

## The marker float's strobe lights the marine snow around it (backscatter on each flash; the glow of the water
## itself is the float's own scatter quad, Beat06_DeepBlue). The pulse is read back from the float's OmniLight
## (FloatBob: energy 0.35 + 3 * flash); only once the camera is close enough for the snow box to hold specks around
## the lamp (the last ~20 s), otherwise the uniform stays 0.
func _update_lamp(cam_pos: Vector3) -> void:
	var flash := 0.0
	var pos := Vector3(0.0, -100000.0, 0.0)
	var fl = Game.targets.get("float")
	if is_instance_valid(fl) and fl is Node3D:
		var light = fl.get("light")
		if is_instance_valid(light) and light is OmniLight3D and light.is_visible_in_tree():
			pos = light.global_position
			flash = clampf((light.light_energy - 0.35) / 3.0, 0.0, 1.0)
			flash *= 1.0 - smoothstep(22.0, 30.0, pos.distance_to(cam_pos))
	snow_mat.set_shader_parameter("lamp_pos", pos)
	snow_mat.set_shader_parameter("lamp_flash", flash)

## Per-frame update from the camera position and the path time.
func update_water(cam_pos: Vector3, path_time: float) -> void:
	var d := maxf(-cam_pos.y, 0.0)
	RenderingServer.global_shader_parameter_set("water_cam_pos", cam_pos)
	RenderingServer.global_shader_parameter_set("water_sun_dir", Config.sun_dir_water())
	var tr := Config.transmittance(d)
	var lum := tr.x * 0.2 + tr.y * 0.6 + tr.z * 0.2
	RenderingServer.global_shader_parameter_set("water_light_scale", clampf(lum, 0.0, 1.0))
	sky_mat.set_shader_parameter("cam_depth", d)
	var mx := maxf(tr.x, maxf(tr.y, tr.z))
	sun.light_color = Color(tr.x / mx, tr.y / mx, tr.z / mx).lerp(Palette.SUN, 0.25 * exp(-d / 30.0))
	# the swell focuses and defocuses the light near the surface: +/-4 % at 0.6-1 Hz, calming by 30 m
	var clock := Time.get_ticks_msec() * 0.001
	var flick := 1.0 + 0.04 * (0.6 * sin(clock * TAU * 0.62) + 0.4 * sin(clock * TAU * 0.97 + 1.3)) * (1.0 - smoothstep(10.0, 30.0, d))
	sun.light_energy = maxf(2.1 * pow(lum, 0.8), 0.05) * flick
	# fog: water already thick with light in the top ~50 m (the reef never looks like tinted air, the far
	# massif melts away), easing to the clear mid-water by 110 m; hazier below ~150 m so huge shapes emerge
	# gradually (density 0.0064 there: 80 m -> 60 % visible, 200 m -> 28 %, 300 m -> 15 %, 450 m -> 6 %).
	# Below 110 m this is exactly the profile the creature reveal is tuned to.
	var dens := lerpf(0.0115, 0.0056, smoothstep(45.0, 110.0, d))
	dens = lerpf(dens, 0.0064, smoothstep(110.0, 190.0, d))
	env.fog_density = dens * fog_scale
	RenderingServer.global_shader_parameter_set("water_fog_density", env.fog_density)   # ReefVisibility reads env
	# eye adaptation feel: airy shallows, the deep dark and heavy but readable
	env.tonemap_exposure = lerpf(1.05, 1.28, smoothstep(30.0, 420.0, d))   # only part of the light loss is made up
	env.adjustment_contrast = lerpf(1.12, 1.06, smoothstep(20.0, 50.0, d))   # punchier sunlit shallows
	env.adjustment_saturation = lerpf(0.9, 0.8, smoothstep(40.0, 300.0, d))
	# shafts fade out with the story: strong until the lip, the last blue shafts at the head, none in the deep
	var shafts := 1.0 - smoothstep(330.0, 460.0, path_time) * 0.85
	shafts *= 1.0 - smoothstep(450.0, 500.0, path_time)
	shaft_mat.set_shader_parameter("amount", shafts * flick)
	sky_mat.set_shader_parameter("shaft_amount", shafts)
	RenderingServer.global_shader_parameter_set("water_shaft_amount", shafts)
	# the last threads of light around the head at the eye lock
	if path_time >= 380.0 and not _threads_anchored:
		_anchor_threads(cam_pos)
	elif path_time < 370.0:
		_threads_anchored = false
	thread_mat.set_shader_parameter("amount", smoothstep(385.0, 400.0, path_time) * (1.0 - smoothstep(430.0, 446.0, path_time)))
	# near-field rays: strongest in the sunlit top, gone where the light has become diffuse, and gone before the
	# dark-line reveal (246-284 s, camera ~160-200 m): nothing moves over the line but the creature
	ray_mat.set_shader_parameter("amount", shafts * flick * (1.0 - smoothstep(118.0, 158.0, d)))
	# marine snow does not thicken with depth (that read as a star field); bokeh specks near the lens in the dark,
	# and in the sunlit shallows only looking towards the light
	snow_mat.set_shader_parameter("amount", lerpf(0.55, 0.45, smoothstep(10.0, 250.0, d)))
	bokeh_mat.set_shader_parameter("amount", smoothstep(50.0, 220.0, d))   # the sunlit shallow glints come from the shader
	_update_lamp(cam_pos)
	surface.global_position = Vector3(snappedf(cam_pos.x, 50.0), 0.0, snappedf(cam_pos.z, 50.0))
	# sort the ray layers just in front of the camera: drawn after far transparents (fluid seeps), before the
	# exhale bubbles at the mask
	var cam := get_viewport().get_camera_3d()
	if cam:
		ray_node.global_position = cam_pos - cam.global_transform.basis.z * 3.0
