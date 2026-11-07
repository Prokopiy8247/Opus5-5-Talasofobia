class_name Mats
extends RefCounted
## Material factory. All materials are ShaderMaterials built on shaders/inc/uw.gdshaderinc, so
## every surface gets the same depth light and fog. Created materials are registered for warm-up.

static var _shaders := {}
static var all_materials: Array[Material] = []


static func shader(name: String) -> Shader:
	if not _shaders.has(name):
		_shaders[name] = load("res://shaders/%s.gdshader" % name)
	return _shaders[name]


static func make(shader_name: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(shader_name)
	for k in params:
		m.set_shader_parameter(k, params[k])
	all_materials.append(m)
	return m


## Every material made so far from a shader (e.g. so the door lamp can light the marine snow).
static func with_shader(shader_name: String) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	var sh := shader(shader_name)
	for m in all_materials:
		if m is ShaderMaterial and (m as ShaderMaterial).shader == sh:
			out.append(m)
	return out


## Ships, submarines: see shaders/hull.gdshader for the parameters.
static func hull(params := {}) -> ShaderMaterial:
	return make("hull", params)


static func solid(base: Color, rust := 0.3, moss := 0.3, params := {}) -> ShaderMaterial:
	var p := {"base_color": base, "rust_amount": rust, "moss_amount": moss}
	p.merge(params, true)
	return make("solid", p)


static func emissive(c: Color, energy: float) -> ShaderMaterial:
	return make("solid", {"base_color": Color(0.02, 0.02, 0.02), "rust_amount": 0.0, "moss_amount": 0.0,
		"emission_color": c, "emission_energy": energy, "use_vertex_ao": false})


## inscatter: the halo of a lamp right in front of a surface (see shaders/glow.gdshader): it is not cut where
## the camera-facing quad would pass through that surface, and it falls off evenly round the lamp.
static func glow(c: Color, energy := 1.0, falloff := 3.0, reveal_channel := -1.0, inscatter := false) -> ShaderMaterial:
	return make("glow", {"glow_color": c, "energy": energy, "falloff": falloff, "uw_reveal_channel": reveal_channel,
		"inscatter": 1.0 if inscatter else 0.0})


## A billboard halo node (additive, fogged) at a world position.
static func glow_sprite(parent: Node3D, pos: Vector3, size: float, c: Color, energy := 1.0, reveal_channel := -1.0,
		inscatter := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	mi.material_override = glow(c, energy, 3.0, reveal_channel, inscatter)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = size   # the quad is billboarded in the shader: never cull it by its flat AABB
	mi.position = pos
	parent.add_child(mi)
	return mi
