extends Node3D
## First-person diver gliding along the path: mouse look, W/S along the path, drift inside the safety tube,
## and the cinematic autowalk: a slow, deliberate camera operator driven by the gaze cues of PathDef.cues().
##
## The operator: the cues blend a target direction in azimuth/elevation (never through the nadir); a critically
## damped spring in image space follows it with a gentle ease-in, a top angular speed and an image-roll cap, so a
## look straight down can never spin the picture around the view axis.

signal reached_end

## The autowalk glides to rest over the last metres of the path: an S-curve from the cruising speed to zero over
## this many seconds (about 4.7 m at the end speed of ~1.35 m/s). The approach parallax (the float rising into
## place) then eases out instead of stopping dead when the walk ends.
const END_GLIDE := 7.0
## Manual control: the deceleration (m/s^2) that brings a player who holds W to a gentle stop at the end.
const END_BRAKE := 0.45

var cam: Camera3D
var s := 0.0                    # distance along the path
var offset := Vector3.ZERO      # free drift around the path line
var speed := 0.0
var yaw := 0.0
var pitch := 0.0
var yaw_v := 0.0
var pitch_v := 0.0
var autowalk := false
var controls_enabled := false
var ended := false
var clock := 0.0
var _play_clock := 0.0          # real seconds since play began (controls enabled; the load warm-up does not count)
var _cues: Array = []
var _cue_pos: Array = []        # per cue: low-passed target position (null while the cue is idle)
var _end_d := 0.0
var _fov_push := 0.0            # current FOV offset of the autowalk push-in (degrees)
var _snap := 0.0                # after a jump along the path: aim straight at the cue targets for a moment
var _glide := -1.0              # time into the final glide to rest (s); < 0 while cruising
var _glide_len := 0.0           # duration of this glide (s), END_GLIDE or shorter after a jump close to the end
var _glide_v0 := 0.0            # speed when the glide began (m/s)
var _glide_s0 := 0.0            # path distance when the glide began
var _end_clock := -1.0          # clock when the end was reached (the gaze log keeps writing until the diver rests)
# QA gaze log (user args "--gaze-log <name> [--gaze-log-end <s>]"): one CSV line per frame with the camera state and
# every gaze target, written to res://QA/camera_gaze/<name>.csv; the game quits at the end (fast with --fixed-fps).
var _log: FileAccess
var _log_end := -1.0
var _last_dir := Vector3.FORWARD
const LOG_TARGETS := ["boat", "wall_look_1", "school_m1", "lip_roof", "lip_look", "wall_back", "dark_line",
	"coils_b4", "coils_b5", "neck", "head", "eye", "float"]

func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = Config.FOV
	cam.near = Config.CAMERA_NEAR
	cam.far = Config.CAMERA_FAR
	add_child(cam)
	cam.make_current()
	Game.camera = cam
	Game.player = self
	_cues = PathDef.cues()
	_cue_pos.resize(_cues.size())
	_end_d = PathDef.length - 0.05
	_open_log()

func place_at_distance(d: float) -> void:
	s = clampf(d, 0.0, PathDef.length)
	_glide = -1.0
	offset = Vector3.ZERO
	global_position = PathDef.point(s)
	_cue_pos.fill(null)
	_snap = 0.5     # moving targets (the creature's markers) may still hold their old place for a frame or two
	var dir := _autowalk_dir(0.0)
	yaw = atan2(-dir.x, -dir.z)
	pitch = asin(clampf(dir.y, -1.0, 1.0))
	yaw_v = 0.0
	pitch_v = 0.0
	_fov_push = PathDef.fov_push(PathDef.time_at(s))
	cam.fov = Config.FOV + _fov_push
	_apply_rotation(0.0)
	_publish()

func _unhandled_input(e: InputEvent) -> void:
	if not controls_enabled or ended:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var r: Vector2 = e.relative
		if autowalk and not Game.harness and r.length() > 3.0:
			autowalk = false
		if not autowalk:
			yaw -= r.x * Config.LOOK_SENS
			pitch = clampf(pitch - r.y * Config.LOOK_SENS, deg_to_rad(-Config.PITCH_LIMIT), deg_to_rad(Config.PITCH_LIMIT))
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_C:
			autowalk = not autowalk
			yaw_v = 0.0
			pitch_v = 0.0
		elif autowalk and not Game.harness and e.keycode in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_SHIFT, KEY_SPACE]:
			autowalk = false
	elif e is InputEventMouseButton and e.pressed and autowalk and not Game.harness:
		autowalk = false

## How much faster than the tuned walk the cinematic plays right now: Shift speed (Config.CINEMATIC_MULT), eased in
## from 1x over the opening shot (Config.CINEMATIC_RAMP).
func cine_mult() -> float:
	return lerpf(1.0, Config.CINEMATIC_MULT, smoothstep(Config.CINEMATIC_RAMP.x, Config.CINEMATIC_RAMP.y, _play_clock))

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	clock += delta
	if controls_enabled:
		_play_clock += delta
	var tan := PathDef.tangent(s)
	var target_speed := 0.0
	# the cinematic runs the tuned walk faster: speed along the path and the camera operator both use the story clock
	var k_cine := cine_mult() if autowalk else 1.0
	if ended:
		target_speed = 0.0
	elif autowalk:
		target_speed = Config.SPEED * k_cine * PathDef.speed_mult(s)
		offset = offset.lerp(Vector3.ZERO, 1.0 - exp(-0.35 * delta))
	elif controls_enabled:
		var f := 0.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): f += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): f -= 1.0
		target_speed = f * Config.SPEED * (Config.BRISK_MULT if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		if target_speed > 0.0:
			# a gentle constant deceleration into the end instead of a dead stop against it
			target_speed = minf(target_speed, maxf(0.25, sqrt(2.0 * END_BRAKE * maxf(PathDef.length - s, 0.0))))
	var tc := Config.ACCEL_TIME if not autowalk else 1.2
	speed = lerpf(speed, target_speed, 1.0 - exp(-delta / tc))
	# the autowalk glides to rest: once the remaining distance equals what an S-curve stop from the current speed
	# covers (v0 * T / 2), speed follows v0 * (1 - smoothstep(0, T, t)) and the distance its exact integral, so the
	# diver arrives at the very end with zero speed and zero deceleration
	if autowalk and not ended:
		var left := PathDef.length - s
		if _glide < 0.0 and speed > 0.05 and left <= speed * END_GLIDE * 0.5:
			_glide = 0.0
			_glide_v0 = speed
			_glide_s0 = s
			_glide_len = maxf(2.0 * left / speed, 0.01)
	elif not autowalk:
		_glide = -1.0       # the player took over; a glide already under way at the end runs to rest
	# advance along the path; lateral drift towards where the player looks (manual only)
	if _glide >= 0.0:
		_glide = minf(_glide + delta, _glide_len)
		var u := _glide / _glide_len
		s = minf(_glide_s0 + _glide_v0 * _glide_len * (u - u * u * u + 0.5 * u * u * u * u), PathDef.length)
		speed = _glide_v0 * (1.0 - u * u * (3.0 - 2.0 * u))
	else:
		s = clampf(s + speed * delta, 0.0, PathDef.length)
	if not autowalk and absf(speed) > 0.05:
		var look := -cam.global_basis.z
		var lat := look - tan * look.dot(tan)
		offset += lat * absf(speed) * 0.55 * delta
	offset -= tan * offset.dot(tan)
	var r := offset.length()
	if r > Config.TUBE_RADIUS:
		offset = offset * (Config.TUBE_RADIUS / r)
	global_position = PathDef.point(s) + offset
	if autowalk:
		# the operator's spring, speed caps and target low-pass were tuned in story seconds: at k_cine they run k_cine
		# times faster in real time, so the gaze keeps up with the faster walk and every framing stays as tuned
		_autowalk_look(delta * k_cine)
	# the push-in belongs to the cinematic operator: it eases out again when the player takes the camera
	var push := PathDef.fov_push(PathDef.time_at(s)) if autowalk else 0.0
	_fov_push = lerpf(_fov_push, push, 1.0 - exp(-delta * k_cine / 1.5))
	cam.fov = Config.FOV + _fov_push
	_apply_rotation(delta)
	_publish()
	# the end: the moment the diver is at rest (a running glide finishes first, so the ending's hold on the final
	# image counts from a still picture, not from the last centimetres of the glide)
	if not ended and s >= _end_d and (_glide < 0.0 or _glide >= _glide_len):
		ended = true
		_end_clock = clock
		print("PELAGIC end: diver at rest (clock %.1f s, path time %.1f s)" % [clock, Game.path_time])
		reached_end.emit()
	if _log and controls_enabled:
		_write_log()

func _publish() -> void:
	Game.path_dist = s
	Game.path_time = PathDef.time_at(s)

func _apply_rotation(_delta: float) -> void:
	var sway_y := 0.0
	var sway_p := 0.0
	if autowalk:
		var a := deg_to_rad(Config.SWAY_DEG)
		sway_y = a * (0.6 * sin(clock * 0.37) + 0.4 * sin(clock * 0.83 + 1.3))
		sway_p = a * (0.6 * sin(clock * 0.29 + 0.7) + 0.4 * sin(clock * 0.71 + 2.1))
		# yaw sway turns into image roll when the view is steep: keep the hand-held feel in the picture plane
		sway_y *= cos(pitch)
	var breath := sin(clock * TAU / 4.8)
	cam.position = Vector3(0.0, 0.022 * breath, 0.0)
	cam.basis = Basis.from_euler(Vector3(pitch + sway_p + deg_to_rad(0.12) * breath, yaw + sway_y, 0.0))

## Target view direction of the autowalk: the path ahead, blended towards every active cue in azimuth/elevation.
## Blending angles (not slerping vectors) never swings the view through the nadir; targets are clamped to
## LOOK_MIN_PITCH..LOOK_MAX_PITCH, a target almost straight below gives no azimuth, and one behind the path never
## turns the diver around. delta > 0 advances the low-pass of moving targets (the creature's slow body wave).
func _autowalk_dir(delta: float) -> Vector3:
	var p := global_position
	var ahead := PathDef.point(minf(s + Config.LOOK_AHEAD, PathDef.length))
	var dir := (ahead - p).normalized() if ahead.distance_to(p) > 0.5 else -cam.global_basis.z
	if s + Config.LOOK_AHEAD > PathDef.length:
		dir = PathDef.tangent(PathDef.length - 1.0)
	dir = (dir + Vector3(0, -0.12, 0)).normalized()
	var az := atan2(-dir.x, -dir.z)
	var el := asin(clampf(dir.y, -1.0, 1.0))
	var az0 := az
	var lo := deg_to_rad(Config.LOOK_MIN_PITCH)
	var hi := deg_to_rad(Config.LOOK_MAX_PITCH)
	var t := PathDef.time_at(s)
	var k_lp := 1.0 - exp(-delta / Config.LOOK_TARGET_TAU) if delta > 0.0 else 0.0
	if _snap > 0.0:
		k_lp = 1.0
	for i in _cues.size():
		var c: Dictionary = _cues[i]
		var tt: Array = c["t"]
		var w_in := smoothstep(tt[0], tt[1], t) if tt[1] > tt[0] else (1.0 if t >= tt[0] else 0.0)
		var w := w_in * (1.0 - smoothstep(tt[2], tt[3], t)) * float(c["w"])
		var w_az := w     # optional "az_out": the azimuth pull lets go on its own, later ramp (see PathDef.cues())
		if c.has("az_out"):
			var ta: Array = c["az_out"]
			w_az = w_in * (1.0 - smoothstep(ta[0], ta[1], t)) * float(c["w"])
		if maxf(w, w_az) <= 0.001:
			_cue_pos[i] = null
			continue
		var raw = _target_pos(c["target"], p)
		if raw == null:
			continue
		if _cue_pos[i] == null:
			_cue_pos[i] = raw
		else:
			_cue_pos[i] = (_cue_pos[i] as Vector3).lerp(raw, k_lp)
		var td: Vector3 = (_cue_pos[i] as Vector3) - p
		if td.length() < 0.5:
			continue
		td = td.normalized()
		var hz := Vector2(td.x, td.z).length()
		var t_az := atan2(-td.x, -td.z)
		var t_el := asin(clampf(td.y, -1.0, 1.0)) + deg_to_rad(float(c.get("lift", 0.0)))
		var goal := clampf(t_el, lo, hi)
		# behind the path: no azimuth pull; a steep target there is framed by looking further down along the path
		# (a steeper pitch with a steady yaw never rolls the picture), any other one is ignored
		var b := smoothstep(deg_to_rad(100.0), deg_to_rad(150.0), absf(wrapf(t_az - az0, -PI, PI))) * smoothstep(0.05, 0.2, hz)
		if b > 0.0:
			var proj := atan2(td.y, -td.x * sin(az0) - td.z * cos(az0))
			var steep := smoothstep(deg_to_rad(-50.0), deg_to_rad(-65.0), t_el)
			goal = lerpf(goal, lerpf(el, clampf(proj, deg_to_rad(Config.LOOK_MIN_PITCH_BEHIND), hi), steep), b)
		var k := smoothstep(0.12, 0.35, hz) * (1.0 - b)
		az += wrapf(t_az - az, -PI, PI) * w_az * k
		el += (goal - el) * w
	el += deg_to_rad(PathDef.look_nudge(t))
	return Vector3(-sin(az) * cos(el), sin(el), -cos(az) * cos(el))

func _target_pos(tg, p: Vector3):
	if tg is Vector3:
		return tg
	if tg is String:
		var n: Node3D = Game.targets.get(tg)
		return n.global_position if n and n.is_inside_tree() else null
	if tg is Dictionary and tg.has("rel"):
		return p + (tg["rel"] as Vector3)
	return null

## The operator's hands: a critically damped spring measured in the picture (a yaw step counts cos(pitch)), easing
## into every move (LOOK_MAX_ACCEL, braking stays with the spring so it never overshoots), with a top speed
## (LOOK_MAX_RATE) and a cap on the image roll that yaw causes in a steep view (LOOK_MAX_ROLL).
func _autowalk_look(delta: float) -> void:
	var dir := _autowalk_dir(delta)
	if _snap > 0.0:
		# right after place_at_distance (harness tours, the start): no operator move, just look where the cues say
		_snap -= delta
		_last_dir = dir
		yaw = atan2(-dir.x, -dir.z)
		pitch = asin(clampf(dir.y, -1.0, 1.0))
		yaw_v = 0.0
		pitch_v = 0.0
		return
	_last_dir = dir
	var ty := atan2(-dir.x, -dir.z)
	var tp := asin(clampf(dir.y, -1.0, 1.0))
	var w := Config.LOOK_OMEGA
	var cp := maxf(cos(pitch), 0.05)
	var vel := Vector2(yaw_v * cp, pitch_v)
	var acc := Vector2(w * w * wrapf(ty - yaw, -PI, PI) * cp, w * w * (tp - pitch)) - 2.0 * w * vel
	var a_max := deg_to_rad(Config.LOOK_MAX_ACCEL)
	var vl := vel.length()
	if vl > 1e-4:
		var u := vel / vl
		var along := acc.dot(u)
		var perp := acc - u * along
		along = minf(along, a_max)
		if perp.length() > a_max:
			perp = perp.normalized() * a_max
		acc = u * along + perp
	elif acc.length() > a_max:
		acc = acc.normalized() * a_max
	vel += acc * delta
	var v_max := deg_to_rad(PathDef.look_rate(PathDef.time_at(s)))
	if vel.length() > v_max:
		vel = vel.normalized() * v_max
	yaw_v = vel.x / cp
	pitch_v = vel.y
	var sp := absf(sin(pitch))
	var roll_max := deg_to_rad(Config.LOOK_MAX_ROLL)
	if absf(yaw_v) * sp > roll_max:
		yaw_v = signf(yaw_v) * roll_max / sp
	yaw += yaw_v * delta
	var hard := maxf(deg_to_rad(Config.LOOK_HARD_PITCH), absf(pitch))     # a steeper manual view eases back, no snap
	pitch = clampf(pitch + pitch_v * delta, -hard, hard)

func _open_log() -> void:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--gaze-log")
	if i < 0 or i + 1 >= a.size():
		return
	var j := a.find("--gaze-log-end")
	if j >= 0 and j + 1 < a.size():
		_log_end = float(a[j + 1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://QA/camera_gaze"))
	_log = FileAccess.open(ProjectSettings.globalize_path("res://QA/camera_gaze/%s.csv" % a[i + 1]), FileAccess.WRITE)
	if _log == null:
		return
	var h := "t,clock,s,px,py,pz,yaw,pitch,roll,fov,dx,dy,dz"
	for k in LOG_TARGETS:
		h += ",%s_x,%s_y,%s_z" % [k, k, k]
	_log.store_line(h)

func _write_log() -> void:
	var line := "%.4f,%.4f,%.3f,%.3f,%.3f,%.3f,%.6f,%.6f,%.6f,%.3f,%.6f,%.6f,%.6f" % [Game.path_time, clock, s,
		global_position.x, global_position.y, global_position.z, yaw, pitch, cam.rotation.z, cam.fov,
		_last_dir.x, _last_dir.y, _last_dir.z]
	for k in LOG_TARGETS:
		var n: Node3D = Game.targets.get(k)
		if n and n.is_inside_tree():
			var p := n.global_position
			line += ",%.3f,%.3f,%.3f" % [p.x, p.y, p.z]
		else:
			line += ",nan,nan,nan"
	_log.store_line(line)
	if (ended and clock - _end_clock > 2.5) or (_log_end > 0.0 and Game.path_time >= _log_end):
		_log.close()
		_log = null
		Game.quit(get_tree())
