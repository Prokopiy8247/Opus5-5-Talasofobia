extends Node3D
## Beat 3 "The Wall" (330-720 m): the flank of a colossal sunken ship hanging in the water on the +Z side
## of the line, sinking ~0.12 m/s. Colossal riveted strakes, porthole rows, a welded ladder, a hawsehole with an
## anchor chain falling into the void, lifeboat davits, painted draft marks, a torn top edge and rusticles.
## Only what the torch touches is seen. The node turns visible at 100 m, but the whole ship condenses out of the
## blue between 150 and 235 m (presence fog in the ship shaders), so it never pops in.

const P = preload("res://scripts/ship/ShipProfile.gd")
const SP = preload("res://scripts/ship/ShipParts.gd")
const SM = preload("res://scripts/ship/ShipMesh.gd")

var depth_range := Vector2(120.0, 840.0)   # camera depths where this beat can be visible
var _pivots: Array = []
var _chain_xz := Vector2.ZERO
var _shed: GPUParticles3D


func build(parent: Node3D) -> void:
	name = "Beat03_Wall"
	parent.add_child(self)
	SP.hull(self, 0.0, P.v_bilge(), 4.0)
	SP.portholes(self, 0.0, 2000.0)
	SP.ladder(self)
	var hawse := SP.hawse(self)
	_chain_xz = SP.chain(self, 0.0, P.CHAIN_SPLIT_D)
	_pivots = SP.davits(self)
	SP.top_edge(self)
	SP.rusticles_wall(self)
	_build_shed()
	_add_cues(hawse)
	_process(0.0)


func _add_cues(hawse: Node3D) -> void:
	if G.path == null:
		return
	var find := _marker("FindWall", P.point(-4.0, P.v_at_depth(338.0)) + P.normal(P.v_at_depth(338.0)) * 0.5)
	var davit := _marker("Davit", (_pivots[0] as Node3D).position + Vector3(-4.0, -7.0, 0.0))
	var port := _marker("Porthole", P.point(11.0, P.v_at_depth(428.0)))
	var c := func(d: float) -> float: return P.cam_depth(d)
	# camera-depth windows follow the sinking hull (cam_depth maps design depth -> camera depth)
	G.path.add_cue_depth(298.0, c.call(345.0), find, 4.0)               # the beam finds steel
	G.path.add_cue_depth(c.call(345.0), c.call(392.0), davit, 3.2)     # davit, blocks, broken falls
	G.path.add_cue_depth(c.call(392.0), c.call(436.0), port, 3.0)      # plates and a porthole row
	G.path.add_cue_depth(c.call(436.0), c.call(474.0), Vector2(188.0, 50.0), 3.5)   # look up: no top
	G.path.add_cue_depth(c.call(474.0), c.call(512.0), _ladder_target, 3.0)         # the ladder (human scale)
	G.path.add_cue_depth(c.call(512.0), c.call(562.0), hawse, 3.0)     # hawsehole as big as a house
	G.path.add_cue_depth(c.call(562.0), c.call(604.0), _chain_target, 3.0)          # the chain falling past
	G.path.add_cue_depth(c.call(604.0), c.call(644.0), Vector2(176.0, -56.0), 3.5)  # look down: no bottom
	G.path.add_cue_depth(c.call(644.0), c.call(668.0), _ladder_target, 3.0)
	G.path.add_cue_depth(c.call(668.0), 722.0, _draft_target, 3.0)     # draft marks counting down


func _marker(n: String, p: Vector3) -> Node3D:
	var m := Node3D.new()
	m.name = n
	m.position = p
	add_child(m)
	return m


## Design depth level with the camera now.
func _cam_design_depth() -> float:
	return G.depth - P.sink_at(G.t)

func _ladder_target() -> Vector3:
	return to_global(P.point(P.LADDER_X, P.v_at_depth(_cam_design_depth() + 9.0)))

func _chain_target() -> Vector3:
	return to_global(Vector3(_chain_xz.x, -(_cam_design_depth() + 5.0), _chain_xz.y))

func _draft_target() -> Vector3:
	return to_global(P.point(P.DRAFT_X - 1.5, P.v_at_depth(_cam_design_depth() + 5.0)))


# ---------------------------------------------------------------- rust and silt shed by the sinking hull
## A slow drizzle of rust flakes and grey silt peeling off the plates. The hull sinks faster than they fall,
## so in the beam they rise past the steel: the wreck is alive, decaying and moving. 300-740 m only.
func _build_shed() -> void:
	_shed = GPUParticles3D.new()
	_shed.name = "WallShed"
	_shed.amount = 900
	_shed.lifetime = 30.0
	_shed.explosiveness = 0.0
	_shed.local_coords = false
	_shed.emitting = false
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/wall_shed_process.gdshader")
	_shed.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var dm := ShaderMaterial.new()
	dm.shader = load("res://shaders/rust_draw.gdshader")
	dm.set_shader_parameter("tint_b", Vector3(0.55, 0.55, 0.5))   # half of them grey silt
	dm.set_shader_parameter("size_mul", 3.0)
	dm.set_shader_parameter("fade_near", 45.0)
	dm.set_shader_parameter("fade_far", 65.0)
	dm.set_shader_parameter("life", _shed.lifetime)
	dm.set_shader_parameter("opacity", 0.0)
	quad.material = dm
	_shed.draw_pass_1 = quad
	_shed.visibility_aabb = AABB(Vector3(-40.0, -70.0, -40.0), Vector3(80.0, 140.0, 60.0))
	_shed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shed)

func _shed_update() -> void:
	var d := G.depth
	_shed.emitting = d > 290.0 and d < 750.0
	var dd := _cam_design_depth()
	var cam := G.camera.global_position if G.camera else Vector3(0.0, -d, 0.0)
	var wz := P.wall_z(clampf(dd, P.TOP_D, P.BILGE_D))
	var pm := _shed.process_material as ShaderMaterial
	pm.set_shader_parameter("cam_dd", dd)
	pm.set_shader_parameter("cam_x", cam.x)
	pm.set_shader_parameter("wall", Vector4(P.WALL_A, P.WALL_D0, P.WALL_K, P.sink_at(G.t)))
	var dm := (_shed.draw_pass_1 as QuadMesh).material as ShaderMaterial
	dm.set_shader_parameter("opacity", smoothstep(300.0, 340.0, d) * (1.0 - smoothstep(700.0, 740.0, d)))
	dm.set_shader_parameter("edge", Vector4(cam.x, wz, 16.0, 22.0))   # no straight patch end along the wall
	if G.env:
		dm.set_shader_parameter("sigma", G.env.fog_density)
	_shed.global_position = Vector3(cam.x, cam.y, wz)


func _process(_delta: float) -> void:
	position.y = -P.sink_at(G.t)
	SM.update_env(G.depth, SM.presence_at(G.depth))
	_shed_update()
	var t := G.t
	for i in _pivots.size():
		var pv: Node3D = _pivots[i]
		pv.rotation = Vector3(0.03 * sin(t * 0.23 + i * 1.7), 0.0, 0.02 * sin(t * 0.17 + i * 2.3))
