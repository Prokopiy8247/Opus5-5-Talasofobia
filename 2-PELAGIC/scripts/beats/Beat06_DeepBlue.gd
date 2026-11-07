extends RefCounted
## Beat 6 — The deep blue: the goal, a small orange marker float with a blinking lamp, hanging on a line that rises
## out of sight. The endless body below comes from the creature prefab. The float sits a few metres ahead of the end
## of the path, a little below eye level: the last image is the float in the upper third, its lamp the brightest
## point of the last minute, the body passing beneath it in the dark.

const AHEAD := 4.5              # metres beyond the end of the path
const DROP := 0.6               # below the eye
const BELOW_LAYER := 2          # render layer of the parts in the float's shadow (the lamp's light skips it)

func build(parent: Node3D) -> void:
	var end := PathDef.point(PathDef.length)
	var tg := PathDef.tangent(PathDef.length - 1.0)
	var flat := Vector3(tg.x, 0.0, tg.z).normalized()
	var pos := end + flat * AHEAD + Vector3(0, -DROP, 0)
	var root := Node3D.new()
	root.name = "MarkerFloat"
	root.position = pos
	root.set_script(load("res://scripts/beats/FloatBob.gd"))
	parent.add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = Geo.lathe(PackedVector2Array([Vector2(0.0, -0.36), Vector2(0.12, -0.35), Vector2(0.2, -0.33),
		Vector2(0.28, -0.27), Vector2(0.33, -0.18), Vector2(0.36, -0.09), Vector2(0.37, 0.0), Vector2(0.36, 0.09),
		Vector2(0.33, 0.18), Vector2(0.28, 0.27), Vector2(0.2, 0.33), Vector2(0.06, 0.37), Vector2(0.0, 0.37)]), 32)
	body.material_override = _mat(0)
	root.add_child(body)
	var band := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.34; tm.outer_radius = 0.385
	band.mesh = tm
	band.material_override = _mat(1)
	root.add_child(band)
	# the lamp: a strobe. Its lens and the float's top are lit by its own light (the OmniLight above it; the float's
	# shader takes only the flash part of that light, so the float is dark between flashes); the flash itself is a soft
	# camera-facing halo of light scattered in the water around the lens. FloatBob drives the halo's emission energy
	# (0.25 .. ~22), so its core peaks at ~6 (well over the glow threshold) and it is nearly dark between flashes:
	# the brightest point of the last minute.
	var lamp := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.05; lm.bottom_radius = 0.06; lm.height = 0.14
	lamp.mesh = lm
	lamp.position = Vector3(0, 0.43, 0)
	lamp.material_override = _mat(1)
	root.add_child(lamp)
	var halo := MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(1.3, 1.3)
	halo.mesh = hq
	halo.position = Vector3(0, 0.45, 0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var em := StandardMaterial3D.new()
	em.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	em.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	em.no_depth_test = true
	em.disable_fog = true
	em.disable_receive_shadows = true
	em.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	em.metallic_specular = 0.0
	em.roughness = 1.0
	em.emission_enabled = true
	em.emission = Color(1.0, 0.82, 0.55) * 0.27
	em.emission_energy_multiplier = 0.25
	em.emission_texture = _halo_tex()
	em.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	em.render_priority = 2
	halo.material_override = em
	root.add_child(halo)
	# ... and the wide in-water scatter of each flash: a ~5 m soft glow behind the lamp, depth-tested so the float
	# stands dark against it (shaders/float_halo.gdshader). It follows the lamp's flash every frame (the flash is
	# FloatBob's emission energy of the small halo: 0.25 + 22 * flash), right before the frame is drawn.
	var wide := MeshInstance3D.new()
	var wq := QuadMesh.new()
	wq.size = Vector2(5.0, 5.0)
	wide.mesh = wq
	wide.position = Vector3(0, 0.45, 0)
	wide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wide.extra_cull_margin = 1.5      # the vertex shader turns the quad to face the camera
	var scatter := ShaderMaterial.new()
	scatter.shader = load("res://shaders/float_halo.gdshader")
	scatter.set_shader_parameter("half_size", wq.size.x * 0.5)
	wide.material_override = scatter
	root.add_child(wide)
	var drive := func() -> void:
		scatter.set_shader_parameter("flash", maxf(em.emission_energy_multiplier - 0.25, 0.0) / 22.0)
	RenderingServer.frame_pre_draw.connect(drive)
	var undrive := func() -> void:
		if RenderingServer.frame_pre_draw.is_connected(drive):
			RenderingServer.frame_pre_draw.disconnect(drive)
	root.tree_exiting.connect(undrive)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 0.6, 0)
	light.light_color = Color(1.0, 0.78, 0.5)
	light.omni_range = 9.0
	light.light_energy = 0.4
	light.shadow_enabled = false
	# no shadows (cost), so the line and the weight hanging below the float, which sit in its shadow, are kept out
	# of the lamp's light by layer instead of glowing under it
	light.light_cull_mask = 0xFFFFF & ~BELOW_LAYER
	root.add_child(light)
	root.set("lamp_mat", em)
	root.set("light", light)
	# line rising out of sight (it fades out within ~25 m, as a thin line does in real water), short line and weight
	var rope := Geo.rope_mat()
	rope.set_shader_parameter("sway", 0.08)
	rope.set_shader_parameter("radius", 0.022)
	rope.set_shader_parameter("color", Color(0.45, 0.42, 0.36))
	rope.set_shader_parameter("fade_from", pos.y + 6.0)
	rope.set_shader_parameter("fade_len", 22.0)
	var up := MeshInstance3D.new()
	up.mesh = Geo.tube(Geo.sag(Vector3(0, 0.37, 0), Vector3(3.0, 260.0, -2.0), -1.5, 80), 0.022, 6)
	up.material_override = rope
	root.add_child(up)
	var dn := MeshInstance3D.new()
	dn.mesh = Geo.tube(PackedVector3Array([Vector3(0, -0.36, 0), Vector3(0.1, -3.0, 0.05), Vector3(0.15, -5.5, 0.1)]), 0.022, 6)
	dn.material_override = rope
	dn.layers = BELOW_LAYER
	root.add_child(dn)
	var wgt := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.07; wm.bottom_radius = 0.09; wm.height = 0.3
	wgt.mesh = wm
	wgt.position = Vector3(0.15, -5.7, 0.1)
	wgt.material_override = _mat(2)
	wgt.layers = BELOW_LAYER
	root.add_child(wgt)
	Game.targets["float"] = root

## Radial falloff of the strobe halo: a hot core and a wide faint skirt (no visible quad edge).
func _halo_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.05, 0.14, 0.32, 0.6, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1), Color(0.6, 0.6, 0.6), Color(0.24, 0.24, 0.24), Color(0.08, 0.08, 0.08), Color(0.015, 0.015, 0.015), Color(0, 0, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t

func _mat(kind: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/float.gdshader")
	m.set_shader_parameter("kind", kind)
	return m
