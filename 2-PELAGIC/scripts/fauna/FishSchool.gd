extends Node3D
## One shader-animated group of animals: a fish school (MultiMesh, one fish per instance, hi/lo mesh by distance)
## or a single turtle / shark gliding on a slow loop. All per-animal motion runs in shaders/fish.gdshader.
## The node position is the school centre (move it freely); set_contract() tightens the school;
## flee() makes it bolt away when Game.path_time passes a story time (a burst of panic flashes, then it streams out
## along the flight direction; the flight is a function of the story clock, so load warm-up, tours and seeks always
## find it in the right state);
## set_drift() moves it slowly on the real clock, set_path_drift() on the story clock (where it is at a given path
## time, whatever the player's speed); set_window() fades it in and out on the story clock and ride() lets it live
## on the creature (it follows the skin and is only as present as the creature); sightline() keeps it on the line
## of sight from the diver's path to a moving point (a scale reference that swims along with the diver, between the
## camera and a distant subject). A group that is not present melts into the water colour, no pop.

const FM := preload("res://scripts/fauna/FaunaMesh.gd")
const SP := preload("res://scripts/fauna/Species.gd")
const SHADER := preload("res://shaders/fish.gdshader")

var radii := Vector3(8.0, 4.0, 8.0)
var count := 0
var fish_len := 0.25
var drift := Vector3.ZERO                 # constant node velocity (m/s)
var flee_at := -1.0                       # autowalk time that triggers the flight (-1 = never)
var flee_dir := Vector3.ZERO
var flee_speed := 5.0
var flee_fade := Vector2(140.0, 240.0)    # distance travelled over which the fleeing school fades out
var path_vel := Vector3.ZERO              # story-clock drift: position = start + path_vel * (path_time - path_t0)
var path_t0 := 0.0
var window := Vector4(-1.0, -1.0, 1e9, 1e9)   # presence on the story clock: fade in x->y, out z->w
var ride_node: Node3D = null              # creature this group lives on (SCP3000): follows its skin, fades with it
var ride_anchor := Vector3.ZERO           # creature model-space anchor point
var ride_s := 0.0
var ride_head := false
var ride_part := 2                        # reveal component used when the creature has no presence(): 0 head .. 3 body
var hover_node: Node3D = null             # a point to hover by (e.g. the creature's eye), on the camera side of it
var hover_off := Vector2.ZERO             # (m towards the camera, m up) from hover_node
var sight_node: Node3D = null             # sightline(): the subject the group keeps in front of
var sight_dist := 30.0                    # m from the diver's path point along the line of sight
var sight_lat := Vector2.ZERO             # across the line (m, + = right) at sight_t0, and its rate (m/s of story time)
var sight_lift := 0.0                     # m up, across the line
var sight_t0 := 0.0

var _mats: Array[ShaderMaterial] = []
var _flee_t := -1.0           # flight clock (s since flee_at), -1 = not fleeing
var _flee_off := Vector3.ZERO # where the flight has carried the school (closed form of _flee_t)
var _flee_k := -1.0           # last flight shape sent to the shader (contract / stretch / effort)
var _startle := -1.0          # last panic level sent to the shader
var _last_pt := -1e9          # story clock of the previous frame (a jump = load warm-up, tour stop or seek)
var _start := Vector3.ZERO
var _vel_sent := Vector3(INF, 0.0, 0.0)
var _pres_sent := -1.0
var _flee_pres := 1.0
var _ride_pos0 := Vector3.ZERO
var _shadow := false
var _dbg := -1.0              # --fauna-debug: clock of the last state print of a riding / windowed group
var _look_dbg := false        # --fish-dbg: cycle the shader's lighting debug modes


## species: key of Species.DATA. opt: speed, len, tightness, turbulence, spin, glint, near (build the hi-detail
## LOD, default true), view_end (m), avoid (m), max_infl, hollow (0..1, ring-shaped mill), flash (turn-wave roll),
## flash_rate (turn waves per second),
## tilt (rad, per-fish orbit plane tilt), head_jit (rad), roll_jit (rad), deform (0..0.35 outline lobes),
## sub (fraction in satellite sub-groups), stray (fraction of stragglers), falloff (0..1 denser core),
## shade (self-shading strength, 0 = off; default 3 for schools), fill (water fill gain), shadow (the school casts
## sun shadows: a dense ball darkens the light rays behind it).
func setup(species: String, center: Vector3, basis_: Basis, radii_: Vector3, count_: int, opt: Dictionary,
		seed_: int) -> void:
	var sp: Dictionary = SP.DATA[species]
	transform = Transform3D(basis_, center)
	_start = center
	radii = radii_
	count = maxi(count_, 1)
	fish_len = float(opt.get("len", sp["len"]))
	var turb := float(opt.get("turbulence", 0.3))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	# radial distribution: sqrt = uniform over the orbit disc; a larger exponent packs the core (density falloff)
	var rexp := 0.5 + 0.35 * clampf(float(opt.get("falloff", 0.0)), 0.0, 1.0)
	var buf := PackedFloat32Array()
	buf.resize(count * 16)
	for i in count:
		var o := i * 16
		buf[o] = 1.0
		buf[o + 5] = 1.0
		buf[o + 10] = 1.0
		buf[o + 12] = rng.randf()
		buf[o + 13] = pow(rng.randf(), rexp)
		buf[o + 14] = (rng.randf() + rng.randf() + rng.randf() - 1.5) / 1.5
		buf[o + 15] = rng.randf()
	if count == 1:
		buf[13] = 1.0
		buf[14] = 0.0

	# self-shading density of the school: fish per m3 times the area a fish shadows (about 0.15 len^2)
	var shade_k := 0.0
	if count > 1:
		var vol := 4.18879 * maxf(radii.x * radii.y * radii.z, 0.01)
		shade_k = clampf(float(opt.get("shade", 3.0)) * count * 0.15 * fish_len * fish_len / vol, 0.0, 0.6)
	var split := fish_len * float(sp.get("lodk", 100.0))
	var params := {
		"radii": radii, "speed": opt.get("speed", sp["speed"]), "tightness": opt.get("tightness", 0.5),
		"turbulence": turb, "spin": opt.get("spin", 1.0), "school_seed": rng.randf() * 10.0,
		"fish_len": fish_len, "size_var": sp.get("size_var", 0.25), "body_mode": sp.get("body", 0.0),
		"wave_amp": sp.get("wave", 0.1), "wave_cycles": sp.get("cycles", 0.9), "beat_hz": sp["hz"],
		"roll_amp": sp.get("roll", 0.25), "lod_split": split, "min_px": sp.get("min_px", 1.2),
		"max_infl": opt.get("max_infl", 2.5), "avoid_radius": opt.get("avoid", clampf(fish_len * 8.0, 1.0, 3.0)),
		"mark_mode": sp.get("mode", 0.0), "stripe_pos": sp.get("stripe", 0.6), "variety": sp.get("variety", 0.0),
		"tip_dark": sp.get("tip", 0.0), "metal": sp["metal"], "rough": sp["rough"],
		"glint": opt.get("glint", sp["glint"]), "eye_data": sp["eye"], "hollow": opt.get("hollow", 0.0),
		"flash_amp": opt.get("flash", sp.get("flash", 0.0)),
		"orbit_tilt": opt.get("tilt", 0.0), "head_jitter": opt.get("head_jit", sp.get("head_jit", 0.0)),
		"roll_jitter": opt.get("roll_jit", sp.get("roll_jit", 0.0)), "deform": opt.get("deform", 0.0),
		"sub_frac": opt.get("sub", 0.0), "stray_frac": opt.get("stray", 0.0), "shade_k": shade_k,
		"fill_gain": opt.get("fill", sp.get("fill", 0.6)),
		"flash_rate": opt.get("flash_rate", sp.get("flash_rate", 0.09)),
	}
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	for k in params:
		var v = params[k]
		mat.set_shader_parameter(k, float(v) if v is int else v)
	for k in ["back", "flank", "belly", "fin", "mark"]:
		mat.set_shader_parameter("col_" + k, Color(sp[k]))

	var kind: String = sp["mesh"]
	var dfm := float(opt.get("deform", 0.0))
	var ext := radii * (1.15 + 0.55 * turb + 0.6 * dfm) + Vector3.ONE * (fish_len * 2.0 + 3.0)
	if float(opt.get("sub", 0.0)) > 0.0 or float(opt.get("stray", 0.0)) > 0.0:
		ext = radii * (1.9 + 0.55 * turb) + Vector3.ONE * (fish_len * 2.0 + 3.0)
	var view_end := float(opt.get("view_end", sp.get("view", 170.0)))
	_shadow = bool(opt.get("shadow", false)) and "--fauna-noshadow" not in OS.get_cmdline_user_args()
	if kind == "slender" or kind == "deep":
		var near := bool(opt.get("near", true))
		if near:
			var hi := mat.duplicate() as ShaderMaterial
			hi.set_shader_parameter("lod_band", 1.0)
			_add_mmi(FM.get_mesh(kind, 0), buf, hi, ext, split + ext.length() + 2.0, false)
		mat.set_shader_parameter("lod_band", 2.0 if near else 0.0)
		_add_mmi(FM.get_mesh(kind, 1), buf, mat, ext, view_end, true)
		if _shadow:
			# the sun shadow of the school comes from a cheap shadow-only copy: every fish as the low mesh, true size
			var sh := mat.duplicate() as ShaderMaterial
			sh.set_shader_parameter("lod_band", 0.0)
			sh.set_shader_parameter("max_infl", 1.0)
			_add_mmi(FM.get_mesh(kind, 1), buf, sh, ext, 170.0, false, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	else:
		_add_mmi(FM.get_mesh(kind, 0), buf, mat, ext, view_end, true)
	# the shader sizes fish in real pixels of the 3D render (the window size, not the stretched canvas size)
	var vp := get_viewport()
	if vp:
		_apply_view_h()
		if not vp.size_changed.is_connected(_apply_view_h):
			vp.size_changed.connect(_apply_view_h)


## Height in pixels of the 3D render, for the fish shader's readability size and coverage fade.
static func render_height(vp: Viewport) -> float:
	if vp is Window:
		return float((vp as Window).size.y)
	if vp is SubViewport:
		return float((vp as SubViewport).size.y)
	return 1080.0


func _apply_view_h() -> void:
	set_param("view_h", maxf(render_height(get_viewport()), 1.0))


func _add_mmi(mesh: Mesh, buf: PackedFloat32Array, mat: ShaderMaterial, ext: Vector3, view_end: float,
		fade: bool, shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.buffer = buf
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = shadow
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.custom_aabb = AABB(-ext, ext * 2.0)
	mi.visibility_range_end = view_end
	if fade:
		mi.visibility_range_end_margin = view_end * 0.15
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mi)
	_mats.append(mat)


func set_param(key: String, value) -> void:
	for m in _mats:
		m.set_shader_parameter(key, value)


## 0 = relaxed, 1 = tight ball (radii shrink to 40 %).
func set_contract(c: float) -> void:
	set_param("contract", clampf(c, 0.0, 1.0))


func flee(at_time: float, dir: Vector3, spd: float) -> void:
	flee_at = at_time
	flee_dir = dir.normalized()
	flee_speed = spd
	if "--fauna-debug" in OS.get_cmdline_user_args():
		_dbg = 0.0
	set_process(true)


func set_drift(v: Vector3) -> void:
	drift = v
	set_process(true)


## Moves the school on the story clock: at path time t it is at start + v * (t - t0).
func set_path_drift(v: Vector3, t0: float) -> void:
	path_vel = v
	path_t0 = t0
	set_process(true)
	_process(0.0)


## Fades the group in over path times w.x -> w.y and out over w.z -> w.w.
func set_window(w: Vector4) -> void:
	window = w
	if "--fauna-debug" in OS.get_cmdline_user_args():
		_dbg = 0.0
	set_process(true)
	_process(0.0)


## Lets the group live on the creature: it follows the model-space anchor through the body wave (and the head
## turn when head is true) and is only as present as the creature itself.
func ride(cr: Node3D, anchor: Vector3, s: float, head: bool, part: int) -> void:
	ride_node = cr
	ride_anchor = anchor
	ride_s = s
	ride_head = head
	ride_part = part
	_ride_pos0 = cr.global_position
	if "--fauna-debug" in OS.get_cmdline_user_args():
		_dbg = 0.0
	set_process(true)
	_process(0.0)


## Lets the group hover by a moving point of the creature (its eye marker): toward_cam metres from it on the
## camera side and up metres above, eased so it drifts rather than jumps; it is as present as the creature there.
func hover(cr: Node3D, marker: Node3D, toward_cam: float, up: float, s: float, part: int) -> void:
	hover_node = marker
	hover_off = Vector2(toward_cam, up)
	ride(cr, Vector3.ZERO, s, true, part)


## Keeps the group on the line of sight from the diver's path point (PathDef, story clock) to target: dist m along
## it, lift m above it and lat m to its right, drifting across it at lat_rate m/s of story time (it crosses the
## view). Everything is a function of the story clock and the target's position: tours and seeks find it in place.
func sightline(target: Node3D, dist: float, lat: float, lat_rate: float, lift: float, t0: float) -> void:
	sight_node = target
	sight_dist = dist
	sight_lat = Vector2(lat, lat_rate)
	sight_lift = lift
	sight_t0 = t0
	if "--fauna-debug" in OS.get_cmdline_user_args():
		_dbg = 0.0
	set_process(true)


func _sight_pos(pt: float) -> Vector3:
	var p := PathDef.point_at_time(pt)
	var tg := p + Vector3.FORWARD * 100.0
	if is_instance_valid(sight_node) and sight_node.is_inside_tree():
		tg = sight_node.global_position
	var dir := tg - p
	dir = dir / dir.length() if dir.length() > 1.0 else Vector3.FORWARD
	var right := dir.cross(Vector3.UP)
	right = right / right.length() if right.length() > 0.1 else Vector3.RIGHT
	var up := right.cross(dir)
	return p + dir * sight_dist + right * (sight_lat.x + sight_lat.y * (pt - sight_t0)) + up * sight_lift


## Presence (0..1) of the creature for an animal at world point pos near body parameter s: the share of the
## creature's own colour that its staging (reveal haze) lets through there, relative to the plain water fog (which
## the fish shader applies itself), so fish on the skin show exactly as much as the skin. Falls back to
## SCP3000.presence(), then to its old staged reveal (part 0 head .. 3 body), then 1.
static func creature_presence(cr: Node, pos: Vector3, s: float, part: int) -> float:
	if not is_instance_valid(cr):
		return 1.0
	if cr.has_method("visibility_at"):
		var dens := 0.0
		var w: World3D = null
		if cr is Node3D:
			w = (cr as Node3D).get_world_3d()
		if w and w.environment:
			dens = w.environment.fog_density
		var fog := exp(-dens * pos.distance_to(Game.cam_pos()))
		return clampf(float(cr.call("visibility_at", pos, s)) / maxf(fog, 1e-4), 0.0, 1.0)
	if cr.has_method("presence") and cr.get_method_argument_count("presence") == 0:
		return clampf(float(cr.call("presence")), 0.0, 1.0)
	var rv = cr.get("reveal")
	if rv is Vector4:
		return clampf(rv[clampi(part, 0, 3)], 0.0, 1.0)
	return 1.0


func _ready() -> void:
	_look_dbg = "--fish-dbg" in OS.get_cmdline_user_args()
	set_process(drift != Vector3.ZERO or flee_at >= 0.0 or path_vel != Vector3.ZERO or ride_node != null
		or sight_node != null or window.x >= 0.0 or _look_dbg)


## Distance factor of a flight after ft seconds: the integral of smoothstep(1, 10, x) dx over 0..ft (the school
## accelerates over 1-10 s, then cruises at flee_speed). Times flee_speed it is the distance travelled.
static func flee_dist(ft: float) -> float:
	if ft <= 1.0:
		return 0.0
	if ft >= 10.0:
		return 4.5 + (ft - 10.0)
	var s := (ft - 1.0) / 9.0
	return 9.0 * (s * s * s - 0.5 * s * s * s * s)


## The flight follows the story clock: wherever the clock jumps (the load warm-up visits every beat, harness tours,
## seeks), the school is exactly where the story puts it, and it is back at rest whenever the clock is before
## flee_at. Between jumps the flight clock also runs on real time, so the school keeps fleeing if the diver stops.
## Returns the flight velocity (m/s, world).
func _update_flee(delta: float) -> Vector3:
	var pt := Game.path_time
	var jump := absf(pt - _last_pt) > 1.0
	_last_pt = pt
	var ft := pt - flee_at
	if ft < 0.0:
		if jump or _flee_t < 0.0:
			_flee_t = -1.0
		else:
			_flee_t += delta          # the diver swam back a little after the flight began: it does not undo it
	elif _flee_t < 0.0 or jump:
		_flee_t = ft
	else:
		_flee_t = maxf(_flee_t + delta, ft)
	var ftc := maxf(_flee_t, 0.0)
	# the school bunches up and streams out along the flight: an ellipsoid stretched along flee_dir
	var k := smoothstep(0.0, 4.0, ftc) if _flee_t >= 0.0 else 0.0
	if absf(k - _flee_k) > 1e-4:
		_flee_k = k
		set_contract(0.55 * k)
		var ax := (basis.inverse() * flee_dir).normalized()
		set_param("stretch", Vector4(ax.x, ax.y, ax.z, 1.5 * k))
		set_param("effort", 1.0 + 1.3 * k)
	# the bolt: a burst of panic flashes as the school turns and runs, settling after a few seconds
	var st := smoothstep(0.0, 0.8, ftc) * (1.0 - smoothstep(4.0, 9.0, ftc)) if _flee_t >= 0.0 else 0.0
	if absf(st - _startle) > 1e-3 or (st == 0.0) != (_startle == 0.0):
		_startle = st
		set_param("startle", st)
	var dist := flee_speed * flee_dist(ftc) if _flee_t >= 0.0 else 0.0
	_flee_off = flee_dir * dist
	_flee_pres = 1.0 - smoothstep(flee_fade.x, flee_fade.y, dist)
	return flee_dir * flee_speed * smoothstep(1.0, 10.0, ftc) if _flee_t >= 0.0 else Vector3.ZERO


func _process(delta: float) -> void:
	if _look_dbg:
		# --fish-dbg: the lighting terms one by one, one mode per story second (see dbg_mode in fish.gdshader)
		set_param("dbg_mode", int(Game.path_time) % 7)
	var vel := drift
	var fv := Vector3.ZERO
	var off0 := _flee_off
	if flee_at >= 0.0:
		fv = _update_flee(delta)
	var pres := _flee_pres
	if is_instance_valid(sight_node):
		# swims along with the diver on the line of sight (its heading follows that travel, story-clock velocity)
		var pt := Game.path_time
		position = _sight_pos(pt) + _flee_off
		vel = _sight_pos(pt + 0.5) - _sight_pos(pt - 0.5) + fv
	elif is_instance_valid(ride_node):
		if is_instance_valid(hover_node):
			if hover_node.is_inside_tree():
				var e := hover_node.global_position
				var tc := Game.cam_pos() - e
				tc.y = 0.0
				var target := e + tc.normalized() * hover_off.x + Vector3.UP * hover_off.y
				var snap := delta <= 0.0 or position.distance_to(target) > 40.0     # first frame, or after a seek
				position = target if snap else position.lerp(target, 1.0 - exp(-delta / 1.5))
		elif ride_node.has_method("deformed"):
			position = ride_node.global_transform * ride_node.call("deformed", ride_anchor, ride_s, ride_head)
		else:
			position = _start + (ride_node.global_position - _ride_pos0)
		if is_instance_valid(hover_node) and ride_node.has_method("presence"):
			# a scale reference in front of the head: it shows once the creature shows at all (it is not part of
			# the creature's staging haze, it is nearer the diver than the skin)
			pres *= smoothstep(0.03, 0.2, float(ride_node.call("presence")))
		else:
			pres *= creature_presence(ride_node, global_position, ride_s, ride_part)
	elif path_vel != Vector3.ZERO:
		position = _start + path_vel * (Game.path_time - path_t0) + _flee_off
		vel = path_vel + fv
	else:
		# real-clock drift integrates; the flight is added as the change of its closed-form offset
		position += vel * delta + (_flee_off - off0)
		vel += fv
	if window.x >= 0.0:
		var pt := Game.path_time
		pres *= smoothstep(window.x, window.y, pt) * (1.0 - smoothstep(window.z, window.w, pt))
	if _dbg >= 0.0:
		_dbg += delta
		if _dbg > 2.0:
			_dbg = 0.001
			var sp := Vector2(-1.0, -1.0)
			if Game.camera and not Game.camera.is_position_behind(position):
				sp = Game.camera.unproject_position(position)
			print("fauna %s: t %.1f pos %s presence %.3f cam %.1f m screen %s shown %s mat %s flee %.1f" % [name,
				Game.path_time, str(position.snapped(Vector3.ONE * 0.1)), pres, position.distance_to(Game.cam_pos()),
				str(sp.round()), str(is_visible_in_tree()),
				str(_mats[0].get_shader_parameter("presence")) if not _mats.is_empty() else "-", _flee_t])
			if Game.camera:
				print("fauna cam: t %.1f pos %s fwd %s" % [Game.path_time, str(Game.cam_pos().snapped(Vector3.ONE * 0.1)),
					str((-Game.camera.global_basis.z).snapped(Vector3.ONE * 0.001))])
	if absf(pres - _pres_sent) > 0.002 or (pres <= 0.0) != (_pres_sent <= 0.0):
		_pres_sent = pres
		set_param("presence", pres)
		visible = pres > 0.0
	var lv := basis.transposed() * vel
	if not lv.is_equal_approx(_vel_sent):
		_vel_sent = lv
		set_param("school_vel", lv)
