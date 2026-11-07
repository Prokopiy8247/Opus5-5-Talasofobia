class_name Player
extends Node3D
## The diver: follows the line (W/S), free mouse look, small drift inside the safety tube,
## cinematic autowalk with critically damped gaze (C or --autowalk). Never rolls.

signal reached_end
signal first_input

const LOOK_W := 1.5          # gaze spring angular frequency (rad/s)
const SWAY_DEG := 0.25

var path: PathDef
var choreo: Choreo
var cam: Camera3D
var s := 0.0
var v := 0.0
var auto := false
var auto_t := 0.0
var yaw := 0.0
var pitch := -0.3
var yaw_v := 0.0
var pitch_v := 0.0
var drift := Vector2.ZERO
var active := false
var ended := false
var _t := 0.0
var _input_seen := false
var fov_target := Config.FOV        # cues may narrow the view for slow push-ins
var lamp: SpotLight3D               # the diver's hand lamp (switched on in the deep by Main)
var lamp_dir := Vector3.FORWARD
var lamp_power := 0.0
var beam: MeshInstance3D            # in-water glow of the lamp (shaders/beam.gdshader)


func setup(p: PathDef, c: Choreo) -> void:
	path = p
	choreo = c
	cam = Camera3D.new()
	cam.fov = Config.FOV
	cam.near = 0.1
	cam.far = 9000.0
	add_child(cam)
	cam.current = true
	lamp = SpotLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = Color(1.0, 0.93, 0.82)
	lamp.spot_range = 40.0
	lamp.spot_angle = 24.0
	lamp.spot_angle_attenuation = 1.6
	lamp.spot_attenuation = 0.55
	lamp.light_specular = 0.25
	lamp.shadow_enabled = false
	lamp.light_energy = 0.0
	lamp.visible = false
	add_child(lamp)
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	beam = MeshInstance3D.new()
	beam.name = "LampBeam"
	beam.mesh = q
	beam.material_override = Mats.make("beam")
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	beam.visible = false
	add_child(beam)
	_place()


func start_auto() -> void:
	auto = true
	auto_t = choreo.t_of_s(s)


## Jump to a point of the autowalk timeline and snap the gaze there (harness --start-at).
func jump_to_time(t: float) -> void:
	auto_t = t
	s = choreo.s_of_t(t)
	_place()
	var d := choreo.look_dir(s, global_position)
	yaw = atan2(-d.x, -d.z)
	pitch = asin(clampf(d.y, -1.0, 1.0))
	yaw_v = 0.0
	pitch_v = 0.0
	_place()


func snap_look() -> void:
	var d := choreo.look_dir(s, global_position)
	yaw = atan2(-d.x, -d.z)
	pitch = asin(clampf(d.y, -1.0, 1.0))


func _cancel_auto() -> void:
	if auto:
		auto = false
		v = choreo.speed_at(s)


func _notice_input() -> void:
	if not _input_seen:
		_input_seen = true
		first_input.emit()


func _unhandled_input(e: InputEvent) -> void:
	if not active or get_tree().paused:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = e.relative
		if auto and rel.length() < 3.0:
			return
		_cancel_auto()
		_notice_input()
		yaw -= rel.x * Config.MOUSE_SENS
		pitch = clampf(pitch - rel.y * Config.MOUSE_SENS, -1.45, 1.45)
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_C:
			if auto:
				_cancel_auto()
			else:
				start_auto()
			_notice_input()
		elif e.keycode in [KEY_W, KEY_S, KEY_UP, KEY_DOWN, KEY_SHIFT]:
			_cancel_auto()
			_notice_input()


func _process(dt: float) -> void:
	if path == null:
		return
	_t += dt
	if active and not ended:
		if auto:
			auto_t += dt
			s = choreo.s_of_t(auto_t)
			drift = drift.lerp(choreo.drift_at(s), 1.0 - exp(-dt * 0.5 * choreo.pace_ratio))
			_auto_look(dt)
		else:
			_manual(dt)
		if s >= path.length - 0.3:
			s = path.length
			ended = true
			reached_end.emit()
	_place()
	if cam and absf(cam.fov - fov_target) > 0.01:
		cam.fov = lerpf(cam.fov, fov_target, 1.0 - exp(-dt * 0.6 * (choreo.pace_ratio if auto else 1.0)))


func _manual(dt: float) -> void:
	fov_target = Config.FOV
	var inp := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		inp += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		inp -= 1.0
	var target := inp * Config.SPEED * (Config.BRISK if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	v += (target - v) * (1.0 - exp(-dt / Config.ACCEL_TIME))
	s = clampf(s + v * dt, 0.0, path.length)
	# drift a little toward where the diver looks, only while moving
	var d := -cam.global_basis.z
	var lat := Vector2(d.dot(path.right(s)), d.dot(path.up(s)))
	var want := lat * 5.0 * clampf(absf(v) / Config.SPEED, 0.0, 1.0)
	want = want.limit_length(Config.TUBE_RADIUS - 1.0)
	drift = drift.lerp(want, 1.0 - exp(-dt * 0.35))


func _auto_look(dt: float) -> void:
	fov_target = choreo.fov_at(s)
	var d := choreo.look_dir(s, global_position)
	var ty := atan2(-d.x, -d.z)
	var tp := asin(clampf(d.y, -1.0, 1.0))
	var dy := wrapf(ty - yaw, -PI, PI)
	var dp := tp - pitch
	var w := LOOK_W * sqrt(choreo.pace_ratio)       # a quicker walk needs a slightly quicker gaze
	yaw_v += (w * w * dy - 2.0 * w * yaw_v) * dt
	pitch_v += (w * w * dp - 2.0 * w * pitch_v) * dt
	yaw += yaw_v * dt
	pitch = clampf(pitch + pitch_v * dt, -1.45, 1.45)


func _place() -> void:
	var p := path.at(s, Vector3(drift.x, drift.y, 0.0))
	p.y += sin(_t * TAU / 4.6) * 0.035
	var floor_y := Terrain.height(p.x, p.z) + 1.4
	if p.y < floor_y:
		p.y = floor_y
	global_position = p
	var sw := deg_to_rad(SWAY_DEG)
	var sy := (sin(_t * 0.53) * 0.6 + sin(_t * 1.31) * 0.4) * sw
	var sp := (sin(_t * 0.71 + 1.0) * 0.6 + sin(_t * 1.13) * 0.4) * sw
	if cam:
		cam.global_basis = Basis.from_euler(Vector3(pitch + sp, yaw + sy, 0.0))
		_place_lamp()


## The lamp hangs at the diver's right hand: it trails the gaze a little and aims slightly low.
func _place_lamp() -> void:
	if lamp == null:
		return
	var dt := get_process_delta_time()
	# near the seabed the diver points the lamp down at the ground ahead (silt, rocks, the line)
	var h := cam.global_position.y - Terrain.height(cam.global_position.x, cam.global_position.z)
	var low := 0.07 + 0.45 * (1.0 - smoothstep(8.0, 45.0, h)) * smoothstep(-700.0, -900.0, cam.global_position.y)
	var want := (-cam.global_basis.z + Vector3(0, -low, 0)).normalized()
	lamp_dir = lamp_dir.slerp(want, clampf(1.0 - exp(-dt * 3.2), 0.0, 1.0)) if lamp_dir.length() > 0.5 else want
	var lp := cam.global_position + cam.global_basis * Vector3(0.42, -0.3, 0.05)   # held low at the right hand
	lamp.global_position = lp
	if absf(lamp_dir.dot(Vector3.UP)) < 0.999:
		lamp.look_at(lp + lamp_dir, Vector3.UP)
	lamp.visible = lamp_power > 0.001
	beam.visible = lamp.visible
	# surfaces in the deep keep a stylised dark albedo (uw_albedo_light), so the lamp compensates
	var al := 0.1 + 0.06 * smoothstep(-700.0, -300.0, lp.y) + 0.84 * exp(minf(lp.y, 0.0) / 420.0)
	lamp.light_energy = lamp_power * 4.2 / al


func depth() -> float:
	return -global_position.y
