extends MeshInstance3D
## Directional water light field: the abyss below is darker and bluer, the water above slightly brighter.
## One full-screen multiplicative pass (shaders/water_light_pass.gdshader) that scales fogged geometry and the
## backdrop by the same ratio, so "fully fogged == backdrop" keeps holding in every view direction.
## Drawn first in the transparent pass (render_priority -128), before snow, haze, bubbles and sun rays.

var mat: ShaderMaterial


func build(cam: Camera3D) -> void:
	name = "WaterLight"
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	mesh = q
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/water_light_pass.gdshader")
	mat.render_priority = Material.RENDER_PRIORITY_MIN
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	position = Vector3(0.0, 0.0, -1.0)
	cam.add_child(self)
	G.water_light = self


func set_fog_density(sigma: float) -> void:
	mat.set_shader_parameter("fog_density", sigma)
