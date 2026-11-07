extends Node3D
## Beat 4 "The Under" (720-960 m): the hull turns under at the bilge (a bilge keel edge crosses the beam),
## the line drifts beneath the ship, the beam falls into nothing below, then the ship's underside hangs
## overhead as a ceiling of steel and rusticles fading into black. The anchor chain keeps falling into the
## void and ends in an anchor, swaying very slowly. One event inside the silence: at 800 m the ship settles
## (a groan from overhead, the steel lurches 1.4 m, rust rains through the beam).

const P = preload("res://scripts/ship/ShipProfile.gd")
const SP = preload("res://scripts/ship/ShipParts.gd")
const SM = preload("res://scripts/ship/ShipMesh.gd")

const SETTLE_DEPTH := 800.0
const LURCH := 1.4
const RAIN_R := 13.0     # radius of the rain column around the diver
const JOLT_LEN := 5.0    # the settle jolt (push, current, snow surge) is over after this many seconds

var depth_range := Vector2(600.0, 1110.0)   # camera depths where this beat can be visible
var _chain_pivot: Node3D
var _rain: GPUParticles3D
var _settle_t := -1.0
var _jolt := false


func build(parent: Node3D) -> void:
	name = "Beat04_Under"
	parent.add_child(self)
	SP.hull(self, P.v_bilge(), P.v_bottom(), 2.0)
	SP.hull(self, P.v_bottom(), P.v_end(), 6.0)
	SP.bilge_keel(self)
	SP.rusticles_under(self)
	# the lower chain and the anchor hang from a pivot at the 740 m link (no seam with beat 3's part)
	var end := SP.chain_end()
	_chain_pivot = Node3D.new()
	_chain_pivot.name = "ChainPivot"
	_chain_pivot.position = Vector3(end.x, -P.CHAIN_SPLIT_D, end.z)
	add_child(_chain_pivot)
	SP.chain(_chain_pivot, P.CHAIN_SPLIT_D, 1.0e9, _chain_pivot.position)
	SP.anchor(_chain_pivot, end - _chain_pivot.position)
	_build_rain()
	_add_cues()
	_process(0.0)


func _add_cues() -> void:
	if G.path == null:
		return
	G.path.add_cue_depth(722.0, 776.0, Vector2(181.0, -12.0), 3.0)   # bilge keel edge rises across the beam
	G.path.add_cue_depth(776.0, 800.0, Vector2(196.0, -80.0), 3.0)   # M3: straight down into nothing
	# the groan at 800 m pulls the gaze back up just as the first flakes break off: a ceiling of steel, raining rust
	G.path.add_cue_depth(800.0, 848.0, _ceiling_target, 2.2)
	G.path.add_cue_depth(848.0, 962.0, Vector2(168.0, -22.0), 4.0)   # calm, forward and down


## Profile length of the underside nearest above a camera at (z, design depth cd).
func _overhead_v(cz: float, cd: float) -> float:
	var c := P.arc_centre()
	var a1 := P.angle_at(P.v_bilge())
	var phi := clampf(atan2(cd - c.y, c.x - cz), a1, PI * 0.5)
	return P.v_bilge() + P.BILGE_R * (phi - a1)

## The nearest point of the underside, pushed 10 m further under the ship and 14 m along -x so the line rises
## along the left third and the lit steel fills the right two thirds: the gaze climbs while the steel overhead
## recedes into black as the line keeps sinking.
func _ceiling_target() -> Vector3:
	var cz := 50.0
	var cx := 0.0
	if G.camera:
		cz = G.camera.global_position.z
		cx = G.camera.global_position.x
	var v := _overhead_v(cz, G.depth - P.sink_at(G.t)) + 10.0
	return to_global(P.point(cx - 14.0, v))


# ---------------------------------------------------------------- the ship settles
func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "RustRain"
	_rain.amount = 6000
	_rain.lifetime = 16.0
	_rain.one_shot = true
	_rain.explosiveness = 0.25
	_rain.local_coords = false
	_rain.emitting = false
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/rust_rain_process.gdshader")
	_rain.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var dm := ShaderMaterial.new()
	dm.shader = load("res://shaders/rust_draw.gdshader")
	dm.set_shader_parameter("life", _rain.lifetime)
	quad.material = dm
	_rain.draw_pass_1 = quad
	_rain.visibility_aabb = AABB(Vector3(-40, -80, -40), Vector3(80, 110, 80))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)

## The rain is a 13 m column around the diver, from the steel (bilge arc / bottom) down past the camera. It
## follows the diver every frame, so flakes born later keep falling around him while he sinks.
func _rain_params() -> void:
	var pm := _rain.process_material as ShaderMaterial
	var c := P.arc_centre()
	var sink := P.sink_at(G.t)
	pm.set_shader_parameter("arc", Vector4(c.x, c.y + sink, P.BILGE_R, P.wall_z(P.BILGE_D)))
	var cam := G.camera.global_position if G.camera else Vector3(0, -G.depth, 37)
	pm.set_shader_parameter("spawn_rect", Vector4(cam.x, cam.z + 2.0, RAIN_R, 0.0))
	pm.set_shader_parameter("cam_y", cam.y)
	_rain.global_position = Vector3(cam.x, cam.y + 15.0, cam.z + 2.0)
	var dm := (_rain.draw_pass_1 as QuadMesh).material as ShaderMaterial
	dm.set_shader_parameter("edge", Vector4(cam.x, cam.z + 2.0, RAIN_R - 4.0, RAIN_R))
	if G.env:
		dm.set_shader_parameter("sigma", G.env.fog_density)

func _start_rain() -> void:
	_rain_params()
	_rain.restart()
	_rain.emitting = true

func _settle_update() -> void:
	if not G.running:
		return
	if _settle_t < 0.0 and G.depth >= SETTLE_DEPTH:
		_settle_t = G.t
		if G.depth > SETTLE_DEPTH + 25.0:
			_settle_t -= 10.0   # started past it (harness jump): the ship has already settled, silently
		else:
			var cam := G.camera.global_position if G.camera else Vector3(0, -SETTLE_DEPTH, 37)
			var over := to_global(P.point(cam.x, _overhead_v(cam.z, G.depth - P.sink_at(G.t))))
			if G.audio and G.audio.has_method("hull_settle"):
				G.audio.hull_settle(over)
			if G.player and G.player.has_method("torch_stutter"):
				G.player.torch_stutter(0.3)
			_start_rain()
			_jolt = true
	if _settle_t >= 0.0:
		P.lurch = LURCH * smoothstep(0.0, 2.6, G.t - _settle_t)
		if G.t - _settle_t < 30.0:   # until the last flake (born <= 12 s, lives 16 s) has died
			_rain_params()
	_jolt_update()

## The body feels the settle: a short shove down and away from the line, the water lurches (snow current),
## and the stirred silt brightens in the beam (G.snow_mult). Everything returns to exactly zero / 1.0, long
## before 960 m where the creature takes over cam_push and flow_target.
func _jolt_update() -> void:
	if not _jolt:
		return
	var dt := G.t - _settle_t
	var over := dt < 0.0 or dt >= JOLT_LEN or G.depth > 940.0 or not visible
	if "cam_push" in G:
		G.set("cam_push", Vector3.ZERO if over or dt >= 1.5 else Vector3(0.0, -0.35, -0.1) * (1.0 - dt / 1.5))
	G.flow_target = Vector3.ZERO if over or dt >= 3.0 else Vector3(0.0, -0.5, 0.2)
	if "snow_mult" in G:
		G.set("snow_mult", 1.0 if over or dt >= 5.0 else 1.0 + 0.6 * exp(-dt / 1.5))
	if over:
		_jolt = false


func _process(_delta: float) -> void:
	_settle_update()
	position.y = -P.sink_at(G.t)
	SM.update_env(G.depth, SM.presence_at(G.depth))
	var t := G.t
	_chain_pivot.rotation = Vector3(0.0035 * sin(t * 0.11), 0.0, 0.0028 * sin(t * 0.083 + 1.3))
