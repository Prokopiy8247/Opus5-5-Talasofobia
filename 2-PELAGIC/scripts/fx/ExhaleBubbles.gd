extends Node3D
## Diver exhale bubbles, in sync with the regulator breathing of AudioDirector ('breath' loop, held during the two
## hushes). Each exhale releases a gush of large wobbling mushroom caps and medium bubbles plus a fizz of small ones
## from the regulator exhaust below the mouth; the release of a held breath is one big burst, part of which is pushed
## out in front of the mask so it rises through the view (the visible relief after each hush).
## The glide is a drift with the current: the water carries diver and bubbles alike (bubbles follow the diver's smoothed
## track, lagging a little), so they rise in a column above the mask whatever the speed.
## A ring buffer of N bubbles is simulated here (closed-form paths) and written to one MultiMesh buffer per frame
## (preallocated, no allocations); shaders/fx_bubble.gdshader gives them their shape and look.

const N := 320
const LOOP := 30.0
const STRIDE := 16                                   # 12 transform floats + 4 custom
const TR := 0.35                                     # rise acceleration time constant (s)
const NEAR_FADE := Vector2(0.15, 0.6)                # m from the eye: invisible .. fully visible (round bubbles)
## Mushroom caps: they fade in further out. Closer than ~0.35 m a cap's outline is hundreds of pixels long and, seen
## edge-on, collapses into a long white hair across the lens.
const NEAR_FADE_CAP := Vector2(0.35, 0.9)
## On-screen radius (px at a 720-px-high view) over which a bubble fades out: nothing that big belongs in the
## picture (a bubble that size is a smear on the mask glass, not a sphere in the water).
const MAX_PX := Vector2(90.0, 140.0)
const JET_T := 0.8                                   # decay time of the forward push of the in-view burst (s)
const AHEAD_TIME := 2.6                              # duration of the in-view part of a release burst (s)
const AHEAD_RATE := [26.0, 16.0, 6.0]                # small, medium, caps per second in front of the mask
## Exhale windows inside the 30 s breath.wav loop (s), measured from the file's 150-600 Hz band energy.
const EXHALES := [Vector2(1.85, 3.55), Vector2(6.65, 8.15), Vector2(11.9, 13.45), Vector2(16.7, 18.25),
	Vector2(22.2, 23.55), Vector2(27.1, 28.7)]
const CAP_AT := [0.0, 0.1, 0.24, 0.45, 0.68]        # big gush pulses through an exhale (fraction)

var _mm: MultiMesh
var _mi: MultiMeshInstance3D
var _buf := PackedFloat32Array()
var _p0 := PackedVector3Array()                      # release point
var _s0 := PackedVector3Array()                      # diver track at release
var _t0 := PackedFloat32Array()                      # release time (-1 = free slot)
var _prm := PackedVector4Array()                     # radius, rise, life, wobble
var _kind := PackedByteArray()                       # 0 round, 1 mushroom cap
var _v0 := PackedVector3Array()                      # initial push relative to the water (in-view burst)
var _alive := 0
var _next := 0
var _clock := 0.0
var _last_cam := Vector3.INF
var _vel := Vector3.ZERO
var _track := Vector3.ZERO                           # integral of the smoothed diver velocity (no teleports)
var _rng := RandomNumberGenerator.new()
var _in_exhale := false
var _caps := 0
var _acc_small := 0.0
var _acc_mid := 0.0
var _burst := 0.0             # remaining time of a breath-release burst (s)
var _ahead := 0.0             # remaining time of the in-view part of a release burst (s)
var _acc_ahead := [0.0, 0.0, 0.0]
var _held_prev := false
var _fb_clock := 0.0          # fallback breath clock when the audio director is missing
var _force := false           # --fx-exhale: always exhaling (look checks)
var _debug := false           # --fx-debug: print the breath state changes and the in-view burst
var _dbg_t := 0.0
var _dbg_v := Vector3.ZERO     # --fx-debug: the last raw camera velocity estimate
var _dbg_rej := 0              # --fx-debug: velocity samples rejected as jumps
var _jumped := false          # the camera or the story clock jumped this frame (or a few frames ago)
var _jump_frames := 0
var _last_pt := -1e9


func _ready() -> void:
	# after the Player (and Main, 100) in every frame: the camera has already moved this frame, so its velocity is
	# its step over this frame's delta and the bubbles are placed against the pose that is rendered. (Run before
	# the Player, a step was divided by the next frame's delta: with uneven frames (hitches, slow captures) the
	# estimate swung between ~0 and a rejected 'jump', the diver's track stalled and a release burst was left
	# behind the camera within a second.)
	process_priority = 110
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.seed = 4242
	_force = "--fx-exhale" in OS.get_cmdline_user_args()
	_debug = "--fx-debug" in OS.get_cmdline_user_args()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32      # the caps are big on screen: a round silhouette, no facets
	sphere.rings = 16
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fx_bubble.gdshader")
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = sphere
	_mm.instance_count = N
	_mm.custom_aabb = AABB(Vector3.ONE * -40.0, Vector3.ONE * 80.0)
	_buf.resize(N * STRIDE)
	_buf.fill(0.0)
	_p0.resize(N)
	_s0.resize(N)
	_t0.resize(N)
	_t0.fill(-1.0)
	_prm.resize(N)
	_kind.resize(N)
	_v0.resize(N)
	_mm.buffer = _buf
	_mi = MultiMeshInstance3D.new()
	_mi.multimesh = _mm
	_mi.material_override = mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mi.custom_aabb = _mm.custom_aabb
	add_child(_mi)


func _process(delta: float) -> void:
	# the same step as the diver's clock (Player clamps a long frame to 0.1 s): after a hitch the bubbles do not
	# jump ahead of the camera, and slow-frame captures show what a player sees
	delta = minf(delta, 0.1)
	_clock += delta
	var cam := Game.camera
	if cam == null or delta <= 0.0:
		return
	var cp := cam.global_position
	_jumped = false
	if _last_cam.x != INF:
		var v := (cp - _last_cam) / delta
		_dbg_v = v
		if v.length() < 12.0:           # ignore teleports (tour jumps, seeks)
			_vel = _vel.lerp(v, 1.0 - exp(-delta / 0.3))
		else:
			_dbg_rej += 1
		# a jump is metres in one frame; a frame hitch (the movement catching up after a stall) is not
		if cp.distance_to(_last_cam) > 3.0:
			_jumped = true
	if absf(Game.path_time - _last_pt) > 1.0:
		_jumped = true
	_last_pt = Game.path_time
	# the audio director updates its held state in its own frame step (it may run after us): stay deaf to a release
	# for a few frames after a jump
	if _jumped:
		_jump_frames = 4
	elif _jump_frames > 0:
		_jump_frames -= 1
		_jumped = true
	if _jumped:
		# a jump of the story clock (the load warm-up, a tour stop, a seek) is no release of a held breath, and a
		# burst in progress belongs to the place left behind
		if _debug and (_burst > 0.0 or _ahead > 0.0):
			print("exhale: jump at path %.2f s ends the burst" % Game.path_time)
		_burst = 0.0
		_ahead = 0.0
	_track += _vel * delta
	_last_cam = cp
	if cp.y < -0.6:
		_emit(cam, delta)
	if _alive > 0:
		_update(cam)


func _emit(cam: Camera3D, delta: float) -> void:
	var st := _breath()
	var u: float = st.x                 # phase inside the current exhale, -1 = not exhaling
	var gain: float = st.y
	if bool(st.z):
		_burst = 1.1
		_ahead = AHEAD_TIME
		if _debug:
			print("exhale: release burst at path %.2f s, cam %s" % [Game.path_time, str(cam.global_position.snapped(Vector3.ONE * 0.1))])
	if u >= 0.0:
		if not _in_exhale:
			_in_exhale = true
			_caps = 0
		while _caps < CAP_AT.size() and u >= CAP_AT[_caps]:
			_caps += 1
			if gain > 0.25:
				for k in (2 if _caps == 1 else 1):
					_spawn(cam, 2)
				for k in 3:
					_spawn(cam, 1)
		var env := smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.7, 1.0, u)) * gain
		_acc_small += 30.0 * env * delta
		_acc_mid += 7.0 * env * delta
	else:
		_in_exhale = false
	if _burst > 0.0:
		_burst -= delta
		_acc_small += 60.0 * delta
		_acc_mid += 20.0 * delta
		if _rng.randf() < 7.0 * delta:
			_spawn(cam, 2)
	if _ahead > 0.0:
		_ahead -= delta
		for k in 3:
			_acc_ahead[k] += AHEAD_RATE[k] * delta
			while _acc_ahead[k] >= 1.0:
				_acc_ahead[k] -= 1.0
				_spawn_ahead(cam, k)
	while _acc_small >= 1.0:
		_acc_small -= 1.0
		_spawn(cam, 0)
	while _acc_mid >= 1.0:
		_acc_mid -= 1.0
		_spawn(cam, 1)


## Moves every live bubble along its path and writes the instance buffer (radius, minimum pixel size, fades).
func _update(cam: Camera3D) -> void:
	var cp := cam.global_position
	# real pixels of the 3D render (the window), not the stretched canvas size
	var vp := get_viewport()
	var vh := float((vp as Window).size.y) if vp is Window else float(vp.get_visible_rect().size.y)
	var mpp_k := 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / maxf(vh, 1.0)     # metres per pixel per metre
	var alive := 0
	for i in N:
		var t0 := _t0[i]
		if t0 < 0.0:
			continue
		var o := i * STRIDE
		var age := _clock - t0
		var pr := _prm[i]
		if age > pr.z:
			_t0[i] = -1.0
			for k in 12:
				_buf[o + k] = 0.0
			_buf[o + 15] = 0.0
			continue
		alive += 1
		var sd := float(i) * 0.6180339
		var w := 6.0 + 5.0 * fposmod(sd * 7.3, 1.0)
		var ramp := minf(age * 3.0, 1.0)
		var sa := sd * 91.7
		var c := _p0[i] + (_track - _s0[i]) * 0.92 + Vector3.UP * (pr.w * 6.0 * minf(age, 0.4))
		c += _v0[i] * (JET_T * (1.0 - exp(-age / JET_T)))
		c.y += pr.y * (age - TR * (1.0 - exp(-age / TR)))
		c.x += pr.w * sin(age * w + sd * 40.0) * ramp + cos(sa) * 0.16 * sqrt(age)
		c.z += pr.w * cos(age * w * 0.93 + sd * 23.0) * ramp + sin(sa) * 0.16 * sqrt(age)
		var r := pr.x * pow((10.0 - _p0[i].y) / (10.0 - minf(c.y, 0.0)), 0.3333)   # grows as it rises
		var dist := c.distance_to(cp)
		var mpp := mpp_k * dist
		var rp := r / maxf(mpp, 1e-6)
		var rd := maxf(r, 0.9 * mpp)      # never thinner than ~0.9 px: tiny ones fade instead of sparkling
		var a := smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(pr.z * 0.65, pr.z, age))
		var nf := NEAR_FADE_CAP if _kind[i] == 1 else NEAR_FADE
		a *= smoothstep(nf.x, nf.y, dist) * (1.0 - smoothstep(-0.6, -0.1, c.y))
		a *= minf(rp / 0.9, 1.0) * minf(rp / 0.9, 1.0)
		# (a cap is drawn 1.25x its radius wide)
		var rp720 := rp * (1.25 if _kind[i] == 1 else 1.0) * 720.0 / maxf(vh, 1.0)
		a *= 1.0 - smoothstep(MAX_PX.x, MAX_PX.y, rp720)
		_buf[o] = rd
		_buf[o + 1] = 0.0
		_buf[o + 2] = 0.0
		_buf[o + 3] = c.x
		_buf[o + 4] = 0.0
		_buf[o + 5] = rd
		_buf[o + 6] = 0.0
		_buf[o + 7] = c.y
		_buf[o + 8] = 0.0
		_buf[o + 9] = 0.0
		_buf[o + 10] = rd
		_buf[o + 11] = c.z
		_buf[o + 12] = age
		_buf[o + 13] = float(_kind[i]) + (0.5 if r > 0.0025 else 0.0)
		_buf[o + 14] = fposmod(sd, 1.0)
		_buf[o + 15] = a
	_alive = alive
	if _debug and _clock - _dbg_t > 0.5:
		_dbg_t = _clock
		var near := INF
		var vis := 0
		var in_view := 0
		for i in N:
			if _t0[i] >= 0.0 and _buf[i * STRIDE + 15] > 0.01:
				vis += 1
				var bp := Vector3(_buf[i * STRIDE + 3], _buf[i * STRIDE + 7], _buf[i * STRIDE + 11])
				near = minf(near, bp.distance_to(cp))
				if _buf[i * STRIDE + 15] > 0.05 and cam.is_position_in_frustum(bp):
					in_view += 1
		# the in-view burst bubbles in camera space (x right, y up, z ahead; m): where the release goes
		var sample := ""
		var ns := 0
		var ib := cam.global_transform.affine_inverse()
		for i in N:
			if ns < 4 and _t0[i] >= 0.0 and _v0[i] != Vector3.ZERO and _clock - _t0[i] < 4.0:
				var q := ib * Vector3(_buf[i * STRIDE + 3], _buf[i * STRIDE + 7], _buf[i * STRIDE + 11])
				sample += " (%.2f %.2f %.2f a%.2f)" % [q.x, q.y, -q.z, _buf[i * STRIDE + 15]]
				ns += 1
		if sample != "":
			print("exhale: burst sample" + sample)
		print("exhale: t %.2f clock %.2f alive %d visible %d in view %d nearest %.2f m held %s burst %.2f ahead %.2f vel %.2f raw %.2f rejected %d" % [
			Game.path_time, _clock, alive, vis, in_view, near, str(_held_prev), _burst, _ahead, _vel.length(),
			_dbg_v.length(), _dbg_rej])
	_mi.custom_aabb = AABB(cp - Vector3.ONE * 40.0, Vector3.ONE * 80.0)
	RenderingServer.multimesh_set_buffer(_mm.get_rid(), _buf)


## Returns (exhale phase 0..1 or -1, breath gain 0..1, a held breath was just released).
func _breath() -> Vector3:
	var released := false
	if _force:
		var f := fmod(_clock, 2.0) / 1.6
		return Vector3(f if f <= 1.0 else -1.0, 1.0, 0.0)
	var a = Game.main.get("audio") if is_instance_valid(Game.main) else null
	var bs := Vector3(-2.0, 0.0, 0.0)
	if is_instance_valid(a) and a.has_method("breath_state"):
		bs = a.breath_state()      # (playback position, -1 not playing, -2 no audio; gain; held)
	if bs.x > -1.5:
		var held: bool = bs.z > 0.5
		if _held_prev and not held and not _jumped:
			released = true
		_held_prev = held
		if held or bs.x < 0.0 or bs.y < 0.05:
			return Vector3(-1.0, 0.0, 1.0 if released else 0.0)
		return Vector3(_window(fmod(bs.x, LOOP)), bs.y, 1.0 if released else 0.0)
	# no audio: same timing on our own clock, held through the two hushes
	var t := Game.path_time
	var ev := Config.EVENTS
	var hold: bool = (t >= ev.hush_line + 0.5 and t < ev.dark_line + 6.0) or (t >= ev.hush_head + 0.5 and t < ev.head_away + 1.0)
	if _held_prev and not hold and not _jumped:
		released = true
		_fb_clock = -1.3
	_held_prev = hold
	if hold:
		return Vector3(-1.0, 0.0, 0.0)
	_fb_clock += get_process_delta_time()
	return Vector3(_window(fmod(maxf(_fb_clock, 0.0), LOOP)) if _fb_clock >= 0.0 else -1.0, 1.0, 1.0 if released else 0.0)


func _window(pos: float) -> float:
	for w in EXHALES:
		if pos >= w.x and pos < w.y:
			return (pos - w.x) / (w.y - w.x)
	return -1.0


## kind: 0 small, 1 medium, 2 mushroom cap. Returns the slot.
func _spawn(cam: Camera3D, kind: int) -> int:
	var b := cam.global_basis
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	# regulator exhaust tee: below and in front of the mouth, venting to both sides of the face
	var pos := cam.global_position - b.z * 0.09 - b.y * 0.13 + b.x * side * _rng.randf_range(0.03, 0.12)
	pos += Vector3(_rng.randf_range(-0.02, 0.02), _rng.randf_range(-0.02, 0.02), _rng.randf_range(-0.02, 0.02))
	var r: float
	var rise: float
	var wob: float
	match kind:
		0:
			r = _rng.randf_range(0.0012, 0.0032)
			rise = _rng.randf_range(0.5, 0.75)
			wob = _rng.randf_range(0.004, 0.012)
		1:
			r = _rng.randf_range(0.004, 0.009)
			rise = _rng.randf_range(0.7, 1.0)
			wob = _rng.randf_range(0.012, 0.03)
		_:
			r = _rng.randf_range(0.011, 0.022)
			rise = _rng.randf_range(0.95, 1.4)
			wob = _rng.randf_range(0.01, 0.025)
	var i := _next
	_next = (_next + 1) % N
	_p0[i] = pos
	_s0[i] = _track
	_t0[i] = _clock
	_prm[i] = Vector4(r, rise, _rng.randf_range(6.0, 10.0) / rise + 0.6, wob)
	_kind[i] = 1 if kind == 2 else 0
	_v0[i] = Vector3.ZERO
	_alive += 1
	return i


## Release burst, in-view part: bubbles pushed out in front of the mask (0.9-1.6 m, inside the lower part of the
## frame, wide lateral spread) that drift gently forward and rise slowly through the view for two to three seconds
## (the release is in view for over three seconds, also when the gaze is steep down at the dark line or the head).
func _spawn_ahead(cam: Camera3D, kind: int) -> void:
	var b := cam.global_basis
	var vs := get_viewport().get_visible_rect().size
	var th := tan(deg_to_rad(cam.fov) * 0.5)
	# 0.9-1.6 m: far enough that the slow rise takes two to four seconds to cross the frame (and clear of the caps'
	# near fade), spawned inside the frame, not below it
	var f := _rng.randf_range(0.9, 1.6)
	var x := f * th * (vs.x / maxf(vs.y, 1.0)) * _rng.randf_range(-0.75, 0.75)
	var y := f * th * _rng.randf_range(-0.9, -0.25)
	var i := _spawn(cam, kind)
	_p0[i] = cam.global_position + b.x * x + b.y * y - b.z * f
	# forward along the horizontal gaze (screen-up when looking straight down) and a little outwards: a gentle push,
	# a strong one sweeps them out of the top of a steep down view within a second
	var fw := Vector3(-b.z.x, 0.0, -b.z.z)
	if fw.length() < 0.3:
		fw = Vector3(b.y.x, 0.0, b.y.z)
	_v0[i] = fw.normalized() * _rng.randf_range(0.05, 0.12) + b.x * (x * 0.25)
	var pr := _prm[i]
	pr.y *= 0.4                       # rises slowly (0.2-0.55 m/s, a few-mm bubble's own rise): it stays in view
	pr.z = _rng.randf_range(6.0, 10.0) / pr.y + 0.6
	_prm[i] = pr
