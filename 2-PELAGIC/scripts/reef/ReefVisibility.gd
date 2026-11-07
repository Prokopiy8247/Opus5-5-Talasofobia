extends Node3D
## The reef is hidden only while its nearest point is certainly invisible, so hiding never pops: either beyond the
## reef shaders' far fade (rf_fog: exactly the backdrop colour past 500 m) or lost in the fog (transmittance < 0.3 %).
## Distance is measured to the massif's bounding box.

const BOX_MIN := Vector3(-1060.0, -1250.0, -500.0)   # z covers the south face headlands
const BOX_MAX := Vector3(24.0, 0.0, 720.0)     # x reaches past the face for the lip roof (its rim lobes reach ~19.5)
const FADE_END := 520.0     # > the 500 m end of rf_fog in shaders/reef_common.gdshaderinc
const OPAQUE := 5.8         # fog optical depth at which the reef is invisible

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	var d := p.distance_to(p.clamp(BOX_MIN, BOX_MAX))
	var w := get_world_3d()
	var env: Environment = cam.environment if cam.environment else (w.environment if w else null)
	var dens := env.fog_density if env else 0.0
	visible = d < FADE_END and d * dens < OPAQUE
