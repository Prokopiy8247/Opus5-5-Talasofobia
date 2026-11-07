extends Node3D
## THE DROWNED: builds the world behind a black screen, warms up shaders, runs the walk, the
## cinematic autowalk and the recording harness (--autowalk --start-at --end-at --capture-every
## --quit-at-end --perf).

const BEATS := [
	"res://scripts/beats/Beat01_Shallows.gd", "res://scripts/beats/Beat02_Hulls.gd",
	"res://scripts/beats/Beat03_Forest.gd", "res://scripts/beats/Beat04_Statue.gd",
	"res://scripts/beats/Beat05_Wall.gd", "res://scripts/beats/Beat06_Door.gd",
]

var path: PathDef
var choreo: Choreo
var world: WorldEnv
var player: Player
var ui: UI
var audio: Node
var args := {}
var harness := false
var started := false
var time := 0.0
var _next_capture := 0.0
var _frame_ms: Array[float] = []
var _frame_t: Array[float] = []      # walk time of each measured frame (perf hot spots)
var _ending := false
var _end_timer := -1.0
var _capture_list: Array[float] = []
var _skip_perf := 0
var bubbles: Bubbles
var _breath_prev := 0.0
var _head := 0.0
var _head_started := false
var _face_look := 0.0
var _lamp_t := 0.0
var _has_dark := false
var leviathan: Leviathan
var statue_key: DirectionalLight3D
var statue_rim: DirectionalLight3D
var _leviathan_done := false
const DARK_S := Vector2(1265.0, 1450.0)   # uw_dark ramp (the wall's lights die toward the door)
const LEVIATHAN_S := 588.0          # it passes behind the far rows while the gaze crosses the forest (M2)
const EXHALES := [2.25, 6.85]      # bubble bursts inside the 9 s breathing loop (just after each exhale starts)


func _ready() -> void:
	_parse_args()
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui = UI.new()
	add_child(ui)
	ui.resume_pressed.connect(func(): _set_paused(false))
	ui.quit_pressed.connect(func(): get_tree().quit())
	DisplayServer.window_set_title("THE DROWNED")
	if harness:
		Engine.max_fps = 60
		get_viewport().msaa_3d = Viewport.MSAA_2X
	else:
		get_viewport().msaa_3d = Viewport.MSAA_4X
	if args.has("msaa4"):
		get_viewport().msaa_3d = Viewport.MSAA_4X
	await get_tree().process_frame
	await _build()


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k := a[i].trim_prefix("--")
		if k in ["start-at", "end-at", "capture-every", "speed", "survey", "start-s", "end-s", "end-hold"] and i + 1 < a.size():
			args[k] = float(a[i + 1])
			i += 1
		elif k in ["beats", "capture-at", "out", "shots", "views", "at-s"] and i + 1 < a.size():
			args[k] = a[i + 1]
			i += 1
		else:
			args[k] = true
		i += 1
	harness = args.has("autowalk") or args.has("capture-every") or args.has("perf") or args.has("quit-at-end") \
		or args.has("survey") or args.has("shots") or args.has("at-s")


func _build() -> void:
	var t0 := Time.get_ticks_msec()
	path = PathDef.new()
	PathDef.main = path
	choreo = Choreo.new(path)
	world = WorldEnv.new()
	world.name = "WorldEnv"
	add_child(world)
	var root := Node3D.new()
	root.name = "World"
	add_child(root)
	Terrain.build(root)
	Rope.build(root, path)
	Atmos.build_surface(root)
	Atmos.build_snow(root)
	await get_tree().process_frame
	for bi in BEATS.size():
		var b: String = BEATS[bi]
		if args.has("beats") and not str(bi + 1) in str(args["beats"]).split(","):
			continue
		if ResourceLoader.exists(b):
			var bt0 := Time.get_ticks_msec()
			var beat = load(b).new()
			var node := Node3D.new()
			node.name = b.get_file().get_basename()
			root.add_child(node)
			beat.build(node)
			print("built %s in %d ms" % [node.name, Time.get_ticks_msec() - bt0])
			await get_tree().process_frame
	_life(root)
	_statue_rim(root)
	player = Player.new()
	player.name = "Player"
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.setup(path, choreo)
	player.reached_end.connect(_on_end)
	player.first_input.connect(func(): ui.hide_hint())
	bubbles = Bubbles.new()
	bubbles.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(bubbles)
	_has_dark = ProjectSettings.has_setting("shader_globals/uw_dark")
	if ResourceLoader.exists("res://scripts/AudioDirector.gd"):
		audio = load("res://scripts/AudioDirector.gd").new()
		audio.name = "Audio"
		add_child(audio)
		audio.setup(path)
		if audio.has_signal("exhaled"):
			audio.exhaled.connect(_on_exhaled)
	print("world built in %d ms; path %.1f m; autowalk %.1f s; beats at %s" % [Time.get_ticks_msec() - t0, path.length, choreo.total_time, str(path.beat_s)])
	if harness:
		var marks := []
		for ms in [118.0, 340.0, 425.0, 612.0, 718.0, 872.0, 1005.0, 1044.0, 1100.0, 1170.0, 1424.0, 1540.0]:
			marks.append("s%d=t%.0f" % [ms, choreo.t_of_s(ms)])
		print("timeline: ", " ".join(marks))
	await _warm_up()
	_start()


## Life in the sunlit water only: small fish under the boat and around the debris, a few larger
## ones over the trawler. Nothing lives deeper - the emptiness is the point.
func _life(root: Node3D) -> void:
	if args.has("beats") and not "1" in str(args["beats"]).split(",") and not "2" in str(args["beats"]).split(","):
		return
	var life := Node3D.new()
	life.name = "Life"
	root.add_child(life)
	Fish.school(life, Config.BOAT_POS + Vector3(5, -5, -14), 90, 0.16, Vector3(4, 1.2, 3), Vector3(6, 1, 5), 7)
	Fish.school(life, Config.F_DEBRIS + Vector3(2, 4.5, 0), 150, 0.2, Vector3(5, 1.8, 4), Vector3(9, 2, 7), 11)
	leviathan = Leviathan.new()
	root.add_child(leviathan)
	var tp: Vector3 = Config.SHIP_TRAWLER.pos
	Fish.school(life, Vector3(tp.x, Terrain.height(tp.x, tp.z) + 12.0, tp.z), 36, 0.55, Vector3(9, 3, 7),
		Vector3(14, 4, 10), 23, Color(0.55, 0.6, 0.6))


## A cold back light that only the statue receives (render layer 2): it edges the giant's silhouette
## against the dark water, from behind and above, the way a film lights a subject in the dark.
func _statue_rim(root: Node3D) -> void:
	var st := root.find_child("Statue", true, false) as GeometryInstance3D
	if st == null:
		return
	# everything of the statue beat (the stone, its silt banks, the liner in the palm, the chain, the trawler by
	# the right hand) is on layer 2, so the statue's key and rim lights fall on all of it alike
	var beat := root.find_child("Beat04_Statue", false, false)
	for g in (beat if beat else st).find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers |= 2
	st.layers = 1 | 2
	var rim := DirectionalLight3D.new()
	rim.name = "StatueRim"
	rim.light_color = Palette.SHAFT.lerp(Palette.TEAL_NEAR, 0.35)
	rim.light_energy = 1.3
	rim.light_specular = 0.0
	rim.light_cull_mask = 2
	rim.shadow_enabled = false
	root.add_child(rim)
	rim.look_at_from_position(Vector3.ZERO, Vector3(0.25, -0.45, 1.0).normalized(), Vector3.UP)
	statue_rim = rim
	# a pale cold key from above the diver's shoulder: the giant is lighter than the water around it, so the
	# bowed head, the shoulders and the offering read through the murk; it fades as the wall wakes behind it
	# and the statue becomes a silhouette against the lights (energy set per frame in _update_reveals)
	var key := DirectionalLight3D.new()
	key.name = "StatueKey"
	key.light_color = Palette.SHAFT.lerp(Color(0.8, 0.9, 1.0), 0.6)
	key.light_energy = 0.0
	key.light_specular = 0.0
	key.light_cull_mask = 2
	key.shadow_enabled = false
	root.add_child(key)
	key.look_at_from_position(Vector3.ZERO, Vector3(-0.2, -0.78, -0.6).normalized(), Vector3.UP)
	statue_key = key


## Render every part of the world once behind the black screen so no shader compiles mid-walk.
func _warm_up() -> void:
	var n := 12
	for i in n + 1:
		var s := path.length * float(i) / float(n)
		player.s = s
		for yaw in [0.0, PI * 0.5, PI, PI * 1.5]:
			player.yaw = yaw
			player.pitch = -0.4
			player._place()
			world.update(player.global_position, 0.0)
			await get_tree().process_frame
	player.s = 0.0


## Still-frame capture modes (--survey, --at-s, --shots).
func _still() -> bool:
	return args.has("survey") or args.has("shots") or args.has("at-s")


## Look-around views of the survey: [name, yaw offset deg, pitch deg (null = keep the cinematic pitch)]
const SURVEY_VIEWS := [["a", 0.0, null], ["l", 90.0, -5.0], ["r", -90.0, -5.0], ["b", 180.0, -5.0],
	["u", 0.0, 55.0], ["d", 0.0, -65.0]]


## --survey <step m> [--start-s a --end-s b]: stand every <step> metres along the line and capture six
## directions (ahead = cinematic gaze, left, right, back, up, down) as QA/<out>/s####_<v>.png.
## --shots "s,yaw,pitch;...": single views, yaw relative to the line's heading (deg, + = left).
func _survey() -> void:
	var dir := _out_dir() + "/QA/" + str(args.get("out", "survey"))
	DirAccess.make_dir_recursive_absolute(dir)
	player.active = false
	var jobs := []
	if args.has("shots"):
		for item in str(args["shots"]).split(";", false):
			var p := item.split(",")
			jobs.append([float(p[0]), "y%d_p%d" % [int(p[1]), int(p[2])], float(p[1]), float(p[2]), true])
	var views := str(args.get("views", "alrbud"))
	var stations: Array[float] = []
	if args.has("at-s"):
		for v in str(args["at-s"]).split(","):
			stations.append(float(v))
	elif args.has("survey"):
		var s := float(args.get("start-s", 0.0))
		var s1 := minf(float(args.get("end-s", path.length)), path.length)
		while s <= s1 + 0.01:
			stations.append(s)
			s += float(args["survey"])
	for s in stations:
		for v in SURVEY_VIEWS:
			if str(v[0]) in views:
				jobs.append([s, v[0], v[1], v[2], false])
	for j in jobs:
		var s: float = j[0]
		player.s = clampf(s, 0.0, path.length)
		player._place()
		if j[4]:
			var f := path.forward_h(player.s)
			player.yaw = atan2(-f.x, -f.z) + deg_to_rad(j[2])
			player.pitch = deg_to_rad(j[3])
		else:
			player.snap_look()
			player.yaw += deg_to_rad(j[2])
			if j[3] != null:
				player.pitch = deg_to_rad(j[3])
		player._place()
		for k in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/s%04d_%s.png" % [dir, int(round(s)), j[1]])
	get_tree().quit()


func _start() -> void:
	if _still():
		ui.fade.color.a = 0.0
		started = true
		_survey()
		return
	var start_at: float = args.get("start-at", 0.0)
	player.active = true
	if start_at > 0.0:
		player.jump_to_time(start_at)
		ui.tween_alpha(ui.fade, 0.0, 0.3)
	else:
		player.s = 0.0
		player.snap_look()
		ui.intro(not args.has("autowalk"))
	if args.has("autowalk"):
		player.start_auto()
		if start_at > 0.0:
			player.auto_t = start_at
	if not harness:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_next_capture = start_at
	if args.has("capture-at"):
		for v in str(args["capture-at"]).split(","):
			_capture_list.append(float(v))
		_capture_list.sort()
	if args.has("speed"):
		Engine.time_scale = float(args["speed"])
	started = true
	if audio:
		audio.start(0.3 if start_at > 0.0 else 3.0)


func _process(dt: float) -> void:
	if not started:
		return
	if not get_tree().paused:
		time += dt
	var cam := player.cam.global_position
	world.update(cam, time)
	_update_reveals(player.s, 0.0 if get_tree().paused else dt)
	if audio and not get_tree().paused:
		audio.update(player.s, cam, dt)
	if not get_tree().paused and not (audio and audio.has_signal("exhaled")):
		_breathe()
	if harness:
		_harness(dt)
	if _end_timer >= 0.0:
		var before := _end_timer
		_end_timer += dt
		_door_lamp_fx(_end_timer)
		if args.has("capture-at") and before < 9.0 and _end_timer >= 9.0:
			var dir3 := _out_dir() + "/QA/" + str(args.get("out", "final"))
			DirAccess.make_dir_recursive_absolute(dir3)
			get_viewport().get_texture().get_image().save_png(dir3 + "/end_line.png")
			_skip_perf = 2
		if args.has("quit-at-end") and _end_timer > float(args.get("end-hold", 11.0)):
			_quit()


## Exhaled bubbles on every exhale of the breathing sound (strength 0.5 calm .. 1.0 shaky).
func _on_exhaled(strength: float) -> void:
	if not _ending and not _still():
		bubbles.exhale(lerpf(0.7, 1.4, clampf((strength - 0.5) * 2.0, 0.0, 1.0)))


## Fallback without the audio director: a bubble burst twice per 9 s breathing loop.
func _breathe() -> void:
	var bp := -1.0
	if audio:
		bp = audio.breath_pos()
	if bp < 0.0:
		bp = fmod(time, 9.0)
	for et: float in EXHALES:
		var hit := (_breath_prev < et and bp >= et) if bp >= _breath_prev else (et > _breath_prev or et <= bp)
		if hit and not _ending and not _still():
			bubbles.exhale()
	_breath_prev = bp


func _update_reveals(s: float, dt: float) -> void:
	var b5 := path.beat_s[4]
	var wall := smoothstep(b5 - 30.0, b5 + 100.0, s)
	# the statue's head turns toward the diver once, slowly: when the diver has been looking at the face
	# for a moment, or at the M3 mark at the latest
	if not _head_started and s > 790.0:
		var to_face := (Config.STATUE_FACE - player.cam.global_position).normalized()
		var looking := (-player.cam.global_basis.z).dot(to_face) > cos(deg_to_rad(10.0))
		_face_look = _face_look + dt if looking else 0.0
		if _face_look > 2.5 or s >= Choreo.HEAD_TURN_S:
			_head_started = true
			if audio and audio.has_method("one_shot"):
				audio.one_shot("stone_groan")
	if _head_started:
		_head = move_toward(_head, 1.0, dt / 4.0)
	if _still():      # still frames: show the settled state at s
		_head = 1.0 if s >= Choreo.HEAD_TURN_S else 0.0
		_head_started = _head > 0.0
		if s > Config.LAMP_ON_S:
			_lamp_t = maxf(_lamp_t, 1.0)
	var head := smoothstep(0.0, 1.0, _head)
	var door := smoothstep(path.beat_s[5] - 40.0, path.beat_s[5] + 20.0, s)
	var ending := 1.0 if _ending else 0.0
	world.set_reveal(wall, head, door, ending)
	# the lights die while the diver still looks up the wall: from its far ends toward the door
	var dark := smoothstep(DARK_S.x, DARK_S.y, s)
	if _has_dark:
		RenderingServer.global_shader_parameter_set("uw_dark", dark)
	var lit := smoothstep(0.28, 0.9, wall) * (1.0 - smoothstep(0.15, 0.75, dark))
	RenderingServer.global_shader_parameter_set("uw_glow", Vector4(0.0062 * lit, 0.0029 * lit, 0.0007 * lit, Config.WALL_Z))
	if audio and not _still():
		audio.set_wave(wall)
		audio.set_dark(dark)
	if leviathan and s >= LEVIATHAN_S and s < LEVIATHAN_S + 80.0 and not _still() and leviathan.visible == false \
			and not _leviathan_done:
		_leviathan_done = true
		leviathan.start(choreo.pace_ratio)
		if audio and audio.has_method("one_shot"):
			audio.one_shot("whale_call")
	# the water thins around the giant (its fog layers would hide it) and stays clearer for the wall
	var clear1 := smoothstep(440.0, 530.0, s)          # a little clearer over the forest
	var clear := smoothstep(660.0, 780.0, s)
	world.set_fog_scale(lerpf(lerpf(1.0, 0.72, clear1), 0.45, clear), lerpf(lerpf(1.0, 0.92, clear1), 0.82, clear))
	if statue_key:
		statue_key.light_energy = 2.4 * smoothstep(560.0, 700.0, s) * (1.0 - 0.85 * smoothstep(1050.0, 1110.0, s))
		statue_rim.light_energy = (1.3 + 1.2 * smoothstep(1050.0, 1110.0, s)) * (1.0 - 0.5 * lit)   # the wall's warm rim reads
	_update_grade(s)
	_update_lamp(s, dt)


## Per-beat colour grade (Config.GRADE), blended over 80 m around each beat start; fog-band wobble.
func _update_grade(s: float) -> void:
	var g: Dictionary = Config.GRADE[0].duplicate()
	for i in range(1, Config.GRADE.size()):
		var w := smoothstep(path.beat_s[i] - 40.0, path.beat_s[i] + 40.0, s)
		if w <= 0.0:
			break
		var gi: Dictionary = Config.GRADE[i]
		for k in g:
			g[k] = lerp(g[k], gi[k], w)
	var cy := player.cam.global_position.y
	var band := 0.0
	for b in Config.BANDS:
		band = maxf(band, exp(-0.5 * pow((cy - float(b[0])) / float(b[1]), 2.0)))
	g["g_wobble"] = band * 0.8
	ui.set_post(g)


## The diver switches the lamp on at the cliff edge (with a stutter), off again only if walking back up.
func _update_lamp(s: float, dt: float) -> void:
	var on := s > Config.LAMP_ON_S or (_lamp_t > 0.0 and s > Config.LAMP_ON_S - 12.0)
	if on:
		_lamp_t += dt
	else:
		_lamp_t = 0.0
	var p := 0.0
	if _lamp_t > 0.0:
		var t := _lamp_t
		p = 1.0
		if t < 0.08:
			p = 0.0
		elif t < 0.16:
			p = 0.8
		elif t < 0.3:
			p = 0.15
		elif t < 0.55:
			p = 0.95
		elif t < 0.62:
			p = 0.4
		p *= smoothstep(0.0, 0.05, t)
	if _ending:
		p *= 1.0 - smoothstep(0.0, 4.0, _end_timer) * 0.6
	player.lamp_power = p
	world.set_lamp(player.lamp.global_position, player.lamp_dir, p)


func _harness(dt: float) -> void:
	var t := player.auto_t
	if args.has("perf") and time > 1.0:
		if _skip_perf > 0:
			_skip_perf -= 1
		else:
			_frame_ms.append(dt * 1000.0 / Engine.time_scale)
			_frame_t.append(player.auto_t)
	if args.has("capture-every") and t >= _next_capture - 1e-3:
		var img := get_viewport().get_texture().get_image()
		var dir := _out_dir() + "/QA/shots"
		DirAccess.make_dir_recursive_absolute(dir)
		img.save_png("%s/t%04d.png" % [dir, int(round(t))])
		_next_capture += float(args["capture-every"])
	if args.has("capture-at") and not _capture_list.is_empty() and t >= _capture_list[0]:
		var img2 := get_viewport().get_texture().get_image()
		var dir2 := _out_dir() + "/QA/" + str(args.get("out", "final"))
		DirAccess.make_dir_recursive_absolute(dir2)
		img2.save_png("%s/t%04d.png" % [dir2, int(round(_capture_list[0]))])
		_capture_list.remove_at(0)
		_skip_perf = 2
	if args.has("end-at") and t >= float(args["end-at"]):
		if args.has("quit-at-end"):
			_quit()


## Project folder when run from the editor/project, the exe folder when exported.
func _out_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").trim_suffix("/")
	return OS.get_executable_path().get_base_dir()


func _quit() -> void:
	if args.has("perf") and _frame_ms.size() > 10:
		var arr: Array[float] = _frame_ms.duplicate()
		arr.sort()
		var total := 0.0
		for m in arr:
			total += m
		var avg_fps := 1000.0 / (total / arr.size())
		var worst: float = arr[arr.size() - 1]
		var n1 := maxi(arr.size() / 100, 1)
		var low := 0.0
		for i in n1:
			low += arr[arr.size() - 1 - i]
		var low_fps := 1000.0 / (low / n1)
		# hot spots: the slow frames (> 18 ms) per 5 s of walk time, and the 12 worst frames
		var slow := {}
		var worst_list := []
		for i in _frame_ms.size():
			if _frame_ms[i] > 18.0:
				var b := int(_frame_t[i] / 5.0) * 5
				slow[b] = int(slow.get(b, 0)) + 1
			worst_list.append([_frame_ms[i], _frame_t[i]])
		worst_list.sort_custom(func(x, y): return x[0] > y[0])
		var hot := "slow_frames_per_5s"
		for b in slow:
			hot += " t%d:%d" % [b, slow[b]]
		hot += "\nworst"
		for i in mini(12, worst_list.size()):
			hot += " %.0fms@t%.1f" % [worst_list[i][0], worst_list[i][1]]
		print(hot)
		var vram := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
		var txt := "frames %d\navg_fps %.1f\none_percent_low_fps %.1f\nworst_frame_ms %.1f\nvideo_mem_mb %.0f\nresolution %s\n" % [
			arr.size(), avg_fps, low_fps, worst, vram, str(get_viewport().get_visible_rect().size)]
		DirAccess.make_dir_recursive_absolute(_out_dir() + "/QA")
		var f := FileAccess.open(_out_dir() + "/QA/perf.txt", FileAccess.WRITE)
		if f:
			f.store_string(txt)
			f.close()
		print(txt)
	get_tree().quit()


## At the door the lamp above it stutters and dies before the fade.
func _door_lamp_fx(t: float) -> void:
	var p := 1.0
	for st: Array in [[0.6, 0.2], [0.67, 1.0], [0.85, 0.1], [0.95, 0.8], [1.2, 0.05], [1.28, 0.5], [1.45, 0.0]]:
		if t >= float(st[0]):
			p = float(st[1])
	for n in get_tree().get_nodes_in_group("door_lamp"):
		if n.has_method("set_power"):
			n.set_power(p)


func _on_end() -> void:
	_ending = true
	_end_timer = 0.0
	ui.ending(player.depth())
	if audio:
		audio.on_end()


func _unhandled_input(e: InputEvent) -> void:
	if not started:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_ESCAPE:
			_set_paused(not get_tree().paused)
		elif e.keycode == KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif e is InputEventMouseButton and e.pressed and not get_tree().paused and not harness:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_paused(p: bool) -> void:
	get_tree().paused = p
	ui.show_pause(p)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED
	if audio:
		audio.set_paused(p)
