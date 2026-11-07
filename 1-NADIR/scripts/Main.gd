extends Node3D
## NADIR entry point. Builds everything behind a black screen, warms up materials, then runs the descent.
## Order each frame: Main updates the player, shared state, environment and audio; beats run their own _process after.

const BEAT_SCRIPTS := [
	"res://scripts/beats/Beat01_Surface.gd",
	"res://scripts/beats/Beat02_Blue.gd",
	"res://scripts/beats/Beat03_Wall.gd",
	"res://scripts/beats/Beat04_Under.gd",
	"res://scripts/beats/Beat05_Bloop.gd",
	"res://scripts/beats/Beat06_Floor.gd",
]
const WARM_DEPTHS := [3.0, 60.0, 200.0, 420.0, 760.0, 1080.0, 1400.0, 1550.0]

var ui: Node
var water: Node
var player: Node
var harness: Node
var beats: Array = []
var running := false
var torch_done := false
var released := false
var _cam_vel := Vector3.ZERO


func _ready() -> void:
	G.args = _parse_args()
	_setup_input()
	ui = preload("res://scripts/UI.gd").new()
	add_child(ui)
	await get_tree().process_frame
	await get_tree().process_frame
	_build()
	await _warm_up()
	_start()


func _parse_args() -> Dictionary:
	var a := {}
	var list := OS.get_cmdline_user_args()
	var i := 0
	while i < list.size():
		var k: String = list[i]
		if k.begins_with("--"):
			var key := k.substr(2)
			if i + 1 < list.size() and not list[i + 1].begins_with("--"):
				a[key] = list[i + 1]
				i += 1
			else:
				a[key] = true
		i += 1
	return a


func _setup_input() -> void:
	var keys := {
		"move_fwd": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "brisk": [KEY_SHIFT],
		"cinematic": [KEY_C], "pause": [KEY_ESCAPE], "fullscreen": [KEY_F11],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for kc in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = kc
			InputMap.action_add_event(action, ev)


func _build() -> void:
	var harness_mode: bool = G.args.has("capture-every") or G.args.has("quit-at-end") or G.args.has("perf") or G.args.has("shot-at")
	if harness_mode:
		Engine.max_fps = 60
	var msaa := int(G.args.get("msaa", "4" if not harness_mode else "2"))
	get_viewport().msaa_3d = Viewport.MSAA_4X if msaa >= 4 else (Viewport.MSAA_2X if msaa >= 2 else Viewport.MSAA_DISABLED)
	G.path = PathDef.new()
	G.world = Node3D.new()
	G.world.name = "World"
	water = preload("res://scripts/WaterEnv.gd").new()
	add_child(water)
	water.build()
	player = preload("res://scripts/Player.gd").new()
	add_child(player)
	player.build()
	add_child(G.world)
	var rope = preload("res://scripts/Rope.gd").new()
	G.world.add_child(rope)
	rope.build()
	var snow = preload("res://scripts/MarineSnow.gd").new()
	add_child(snow)
	snow.build()
	for p in BEAT_SCRIPTS:
		if ResourceLoader.exists(p):
			var b = load(p).new()
			b.build(G.world)
			beats.append(b)
	if ResourceLoader.exists("res://scripts/AudioDirector.gd"):
		var ad = load("res://scripts/AudioDirector.gd").new()
		add_child(ad)
		ad.setup()
		G.audio = ad
	harness = preload("res://scripts/Harness.gd").new()
	add_child(harness)
	var marks := ""
	for d in [80.0, 245.0, 330.0, 720.0, 960.0, 1260.0, 1556.0]:
		marks += " %d m@%.0fs" % [d, G.path.time_at(G.path.s_at_depth(d))]
	print("NADIR: path %.0f m, autowalk %.1f s |%s" % [G.path.length, G.path.total_time(), marks])


func _warm_up() -> void:
	# Render each region once behind the black screen so pipelines/materials are ready before the walk.
	player.set_torch(1.0)
	for d in WARM_DEPTHS:
		var s: float = G.path.s_at_depth(d)
		player.place(s)
		for yaw in [0.0, 180.0]:
			player.look_at_angles(yaw, -20.0)
			_push_globals()
			water.update(G.depth, 0.016)
			await get_tree().process_frame
	player.set_torch(0.0)


func _start() -> void:
	var s0 := 0.0
	if G.args.has("start-at"):
		s0 = G.path.s_at_time(float(G.args["start-at"]))
	G.t = G.path.time_at(s0)
	player.place(s0)
	# opening frame: already on the first cue's target (the boat), no pan during the fade-in
	if s0 < 5.0:
		player.look_at_angles(-128.5, 58.0)
	else:
		player.look_at_angles(-25.0, -15.0)
	G.autowalk = G.args.has("autowalk")
	G.depth = -G.camera.global_position.y
	torch_done = G.depth >= Config.TORCH_ON_DEPTH
	player.set_torch(1.0 if torch_done else 0.0)
	released = s0 > 5.0
	if not G.args.has("capture-every") and not G.args.has("quit-at-end"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.begin(s0 > 5.0, G.autowalk)
	running = true
	G.running = true


func _process(delta: float) -> void:
	if not running:
		return
	G.t += delta
	var cam_before: Vector3 = G.camera.global_position
	player.step(delta)
	G.depth = -G.camera.global_position.y
	if delta > 0.0:
		var v: Vector3 = ((G.camera.global_position - cam_before) / delta).limit_length(8.0)
		_cam_vel = _cam_vel.lerp(v, 1.0 - exp(-delta / 0.08))
		RenderingServer.global_shader_parameter_set("g_cam_vel", _cam_vel)
	G.flow = G.flow.lerp(G.flow_target, 1.0 - exp(-delta / 2.5))
	G.flow_offset += G.flow * delta
	_push_globals()
	water.update(G.depth, delta)
	if G.audio:
		G.audio.update(G.depth, delta)
	if not released and G.t > 1.5:
		released = true
		if G.audio:
			G.audio.play_release()
	if not torch_done and G.depth >= Config.TORCH_ON_DEPTH:
		torch_done = true
		player.torch_click_on()
		if G.audio:
			G.audio.play_torch_click()
	_cull_beats()
	if not G.ending and player.s >= G.path.length - 0.6:
		_end_sequence()


func _push_globals() -> void:
	var rs := RenderingServer
	rs.global_shader_parameter_set("g_depth", G.depth)
	rs.global_shader_parameter_set("g_time", G.t)
	rs.global_shader_parameter_set("g_cam_pos", G.camera.global_position)
	rs.global_shader_parameter_set("g_flow", G.flow_offset)
	rs.global_shader_parameter_set("g_torch_pos", G.torch.global_position)
	rs.global_shader_parameter_set("g_torch_dir", -G.torch.global_transform.basis.z)
	rs.global_shader_parameter_set("g_torch", player.torch_out)


func _cull_beats() -> void:
	for b in beats:
		var r = b.get("depth_range")
		if r is Vector2:
			b.visible = G.depth > r.x - 20.0 and G.depth < r.y + 20.0


## Arrival: wait until the floor beat says its reveal has been watched (G.end_ready, capped at 45 s),
## then the breathing stops, the torch dies over 3 s, and only then the picture fades to the end line.
func _end_sequence() -> void:
	G.ending = true
	var waited := 0.0
	while waited < 45.0 and not bool(G.get("end_ready")):
		await get_tree().process_frame
		if not get_tree().paused:
			waited += get_process_delta_time()
	await get_tree().create_timer(6.0, false).timeout
	if G.audio:
		G.audio.stop_breathing(0.6)
	await get_tree().create_timer(1.2, false).timeout
	player.torch_off_slow(3.0)
	await get_tree().create_timer(4.8, false).timeout
	ui.fade_out(Config.END_FADE)
	if G.audio:
		G.audio.fade_out_all(Config.END_FADE + 1.5)
	await get_tree().create_timer(Config.END_FADE + 1.4, false).timeout
	ui.show_end_line(_depth_text(G.depth))
	harness.on_end()


## The camera rests ~0.4 m above END_DEPTH and sways with the breath: round, but never above the floor of
## END_DEPTH, so the line reads "1 556 m" (not 1 555 or 1 557).
static func _depth_text(d: float) -> String:
	var n := int(round(minf(d, floorf(Config.END_DEPTH))))
	var txt := str(n)
	if n >= 1000:
		txt = "%d %03d" % [n / 1000, n % 1000]
	return txt + " m"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	elif running and event.is_action_pressed("cinematic") and not G.ending:
		G.autowalk = not G.autowalk
		player.on_autowalk_toggled()
		ui.hide_hint()
