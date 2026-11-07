extends Node
## Test/recording harness driven by user args after "--":
##   --autowalk  --start-at <s>  --end-at <s>  --capture-every <s>  --quit-at-end  --perf
##   extras: --shot-at t1,t2,...  --shots-dir <res path>  --msaa 2|4
##   --sweep: every capture also looks around (8 views, clock frozen) for free-look QA
##   --views t:dyaw:pitch,... : at time t freeze the clock and capture with yaw = cinematic yaw + dyaw (deg) and
##     pitch (deg, or "c" = keep the cinematic pitch); entries sharing a t are taken in one freeze (stills, framing)
## Captures are taken in game time (the autowalk timeline), PNGs go to QA/shots/ (or --shots-dir).

var _every := 0.0
var _next := 0.0
var _shots: Array = []
var _dir := "res://QA/shots"
var _frames := PackedFloat32Array()
var _perf := false
var _warm := 0.0
var _vram_peak := 0
var _done := false
var _skip := 0
var _sweep := false
var _busy := false
var _views: Array = []   # [t, dyaw, pitch or NAN]
## --sweep: at every capture time the clock freezes and the camera also looks around (free-look QA).
## [suffix, yaw offset from the current view (deg), absolute pitch (deg) or NAN = keep]
const SWEEP_VIEWS := [["f", 0.0, NAN], ["l", 90.0, 0.0], ["b", 180.0, 0.0], ["r", -90.0, 0.0],
	["u", 0.0, 72.0], ["d", 0.0, -80.0], ["dl", 55.0, -40.0], ["dr", -55.0, -40.0]]


func _ready() -> void:
	var a: Dictionary = G.args
	_every = float(a.get("capture-every", "0"))
	_next = G.t + 1.0
	if a.has("shot-at"):
		for v in String(a["shot-at"]).split(","):
			_shots.append(float(v))
		_shots.sort()
	if a.has("shots-dir"):
		_dir = String(a["shots-dir"])
	_perf = a.has("perf")
	_sweep = a.has("sweep")
	if a.has("views"):
		for e in String(a["views"]).split(","):
			var f := e.split(":")
			if f.size() >= 3:
				# yaw "=N" = absolute yaw N (deg); otherwise an offset from the cinematic yaw
				var absy := f[1].begins_with("=")
				_views.append([float(f[0]), float(f[1].trim_prefix("=")), NAN if f[2] == "c" else float(f[2]), absy])
		_views.sort_custom(func(x, y): return x[0] < y[0])
	if _every > 0.0 or not _shots.is_empty() or not _views.is_empty() or a.has("orbit"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))


func _process(delta: float) -> void:
	if _done or _busy:
		return
	if _perf:
		_warm += delta
		if _warm > 3.0 and _skip <= 0:
			_frames.append(delta)
			if delta > 0.04:
				print("HITCH %.0f ms  t %.1f  depth %.0f" % [delta * 1000.0, G.t, G.depth])
			_vram_peak = max(_vram_peak, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))
	_skip -= 1
	if _every > 0.0 and G.t >= _next:
		_next += _every
		_shoot("t%04d" % int(round(G.t)))
		return
	if not _shots.is_empty() and G.t >= _shots[0]:
		_shoot("shot_%04d" % int(round(_shots.pop_front())))
		return
	if not _views.is_empty() and G.t >= _views[0][0]:
		var t0: float = _views[0][0]
		var group := []
		while not _views.is_empty() and is_equal_approx(_views[0][0], t0):
			var v: Array = _views.pop_front()
			var tag := "%s%+04d_%s" % ["a" if v[3] else "", int(v[1]), "c" if is_nan(v[2]) else "%+03d" % int(v[2])]
			group.append([tag, v[1], v[2], v[3]])
		_shoot("view_%05.1f" % t0, group)
		return
	if G.args.has("orbit") and not _orbit_done:
		var o := String(G.args["orbit"]).split(":")
		if G.t >= float(o[0]):
			_orbit_done = true
			_orbit(float(o[1]) if o.size() > 1 else 230.0)
			return
	if G.args.has("end-at") and G.t >= float(G.args["end-at"]) + 0.5:
		finish()


var _orbit_done := false

## --orbit t:dist : at time t freeze and photograph the creature from 8 sides with a separate camera at dist m
## (a still-only tool: clearer water and a key light from the camera's side, the diver's camera is restored).
func _orbit(dist: float) -> void:
	var beat = G.world.get_node_or_null("Beat05_Bloop")
	if beat == null or not beat.bloop.visible:
		print("orbit: creature not active")
		return
	_busy = true
	Engine.time_scale = 0.0
	G.reveal = true
	_reveal_light(true)
	var b: Transform3D = beat.bloop.global_transform
	var c := b.origin
	var fx := b.basis.x.normalized()      # head
	var fy := b.basis.y.normalized()      # back
	var fz := b.basis.z.normalized()
	var cam := Camera3D.new()
	cam.fov = Config.FOV
	cam.far = Config.FAR
	add_child(cam)
	var sides := [["side_right", fz, fy], ["side_left", -fz, fy], ["front", fx, fy], ["back", -fx, fy],
		["top", fy, fx], ["bottom", -fy, fx], ["three_quarter_front", (fx + fz + 0.5 * fy).normalized(), fy],
		["three_quarter_back", (-fx + fz - 0.4 * fy).normalized(), fy]]
	for sd in sides:
		var d: Vector3 = sd[1]
		cam.look_at_from_position(c + d * dist, c, sd[2])
		cam.current = true
		_rl.look_at_from_position(Vector3.ZERO, -(d * 0.8 + fy * 0.6).normalized(), sd[2])
		for i in 24:
			await get_tree().process_frame
		_capture("orbit_" + sd[0])
	G.camera.current = true
	cam.queue_free()
	_reveal_light(false)
	_rl.look_at_from_position(Vector3.ZERO, Vector3(0.25, -1.0, -0.35), Vector3.FORWARD)
	G.reveal = false
	Engine.time_scale = 1.0
	_busy = false


func _shoot(name: String, views: Array = []) -> void:
	if views.is_empty():
		if not _sweep:
			_capture(name)
			return
		views = SWEEP_VIEWS
	_busy = true
	var p = G.player
	var keep := [p.yaw, p.pitch, p.yaw_v, p.pitch_v]
	Engine.time_scale = 0.0
	G.reveal = G.args.has("reveal")
	if G.reveal:
		_reveal_light(true)
	for v in views:
		var pitch_deg: float = rad_to_deg(keep[1]) if is_nan(v[2]) else v[2]
		var yaw_deg: float = v[1] if (v.size() > 3 and v[3]) else rad_to_deg(keep[0]) + v[1]
		p.look_at_angles(yaw_deg, pitch_deg)
		for i in 24:   # let temporal effects settle on the new view
			await get_tree().process_frame
		_capture(name + "_" + v[0])
	if G.reveal:
		_reveal_light(false)
		G.reveal = false
	p.yaw = keep[0]
	p.pitch = keep[1]
	p.yaw_v = keep[2]
	p.pitch_v = keep[3]
	Engine.time_scale = 1.0
	_skip = 3
	_busy = false


var _rl: DirectionalLight3D

## --reveal (stills only): a faint cold light from above so a whole 300 m creature reads beyond the torch range.
func _reveal_light(on: bool) -> void:
	if _rl == null:
		_rl = DirectionalLight3D.new()
		_rl.light_color = Color(0.55, 0.72, 0.95)
		_rl.light_energy = float(G.args.get("reveal-energy", "0.25"))
		_rl.light_specular = 0.3
		add_child(_rl)
		_rl.look_at_from_position(Vector3.ZERO, Vector3(0.25, -1.0, -0.35), Vector3.FORWARD)
	_rl.visible = on


func _capture(name: String) -> void:
	_skip = 2   # the PNG save itself stalls this frame; keep it out of the perf stats
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(_dir.path_join(name + ".png"))
	img.save_png(path)
	print("capture ", path, "  depth %.1f m  s %.1f  yaw %.0f pitch %.0f" % [G.depth, G.player.s, rad_to_deg(G.player.yaw), rad_to_deg(G.player.pitch)])


## Called by Main when the end line is shown.
func on_end() -> void:
	if G.args.has("quit-at-end"):
		await get_tree().create_timer(3.2, false).timeout
		if _every > 0.0 or G.args.has("shot-at"):
			_capture("end_line")
		await get_tree().create_timer(0.8, false).timeout
		finish()


func finish() -> void:
	if _done:
		return
	_done = true
	if _perf and _frames.size() > 10:
		var sorted := _frames.duplicate()
		sorted.sort()
		var total := 0.0
		for f in _frames:
			total += f
		var avg_fps := _frames.size() / total
		var n1: int = max(1, _frames.size() / 100)
		var worst_sum := 0.0
		for i in n1:
			worst_sum += sorted[sorted.size() - 1 - i]
		var low1 := n1 / worst_sum
		var txt := "frames %d\navg_fps %.1f\nlow1_fps %.1f\nworst_ms %.1f\nvram_peak_mb %.0f\nresolution %s\nmsaa %d\n" % [
			_frames.size(), avg_fps, low1, sorted[sorted.size() - 1] * 1000.0, _vram_peak / 1048576.0,
			str(get_viewport().get_visible_rect().size), get_viewport().msaa_3d]
		# exported builds cannot write res://: put perf.txt next to the executable
		var out := "res://QA/perf.txt" if not OS.has_feature("template") else OS.get_executable_path().get_base_dir().path_join("perf.txt")
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(txt)
		f.close()
		print(txt)
	if G.args.has("quit-at-end"):
		G.quit_game()
