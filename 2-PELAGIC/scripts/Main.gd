extends Node3D
## Boot: black screen, build everything, warm up, fade in. Then pause, fullscreen and the ending.

const BEATS := [
	"res://scripts/beats/Beat01_Boat.gd",
	"res://scripts/beats/Beat02_Wall.gd",
	"res://scripts/beats/Beat03_Lip.gd",
	"res://scripts/beats/Beat04_DarkLine.gd",
	"res://scripts/beats/Beat05_Coils.gd",
	"res://scripts/beats/Beat06_DeepBlue.gd",
	"res://scripts/beats/Fauna.gd",
	"res://scripts/beats/DiverFX.gd",
]

var water: Node3D
var player: Node3D
var ui: CanvasLayer
var harness: Node
var audio: Node
var running := false
var paused := false
var _hint_live := false

func _ready() -> void:
	process_priority = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	harness = load("res://scripts/Harness.gd").new()
	add_child(harness)
	harness.parse()
	Game.main = self
	Game.harness = harness.active
	if harness.active:
		Engine.max_fps = 60
	var msaa: int = harness.msaa if harness.msaa > 0 else (2 if harness.active and not harness.perf else 4)
	get_viewport().msaa_3d = Viewport.MSAA_2X if msaa == 2 else Viewport.MSAA_4X
	get_window().title = "PELAGIC"
	ui = load("res://scripts/UI.gd").new()
	add_child(ui)
	ui.resume_pressed.connect(func(): set_paused(false))
	ui.quit_pressed.connect(func(): Game.quit(get_tree()))
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	PathDef.build()
	Game.curve = PathDef.curve
	water = load("res://scripts/WaterWorld.gd").new()
	water.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(water)
	var world := Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	Game.world = world
	player = load("res://scripts/Player.gd").new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.reached_end.connect(_on_end)
	var qa := OS.get_cmdline_user_args()
	for b in BEATS:
		# QA A/B switches: build the world without the fish or without the diver effects (bubbles, lens)
		if ("--no-fauna" in qa and b.ends_with("Fauna.gd")) or ("--no-diverfx" in qa and b.ends_with("DiverFX.gd")):
			continue
		load(b).new().build(world)
		await get_tree().process_frame
	if "--no-glow" in qa:   # QA A/B switch
		water.env.glow_enabled = false
	if ResourceLoader.exists("res://scripts/AudioDirector.gd"):
		audio = load("res://scripts/AudioDirector.gd").new()
		add_child(audio)
	await _warm_up()
	print("PELAGIC loaded in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var hi := qa.find("--hide")
	if hi >= 0 and hi + 1 < qa.size():   # QA A/B switch: --hide snow,shaft hides every node drawn with those shaders
		_qa_hide(qa[hi + 1].split(","))
	player.place_at_distance(PathDef.dist_at(harness.start_at))
	player.autowalk = harness.autowalk
	water.update_water(Game.cam_pos(), Game.path_time)
	# the fade-in (and its title card) starts before the harness: a tour or capture window that jumps away from the
	# opening then drops the title it would otherwise start afterwards (UI.skip_title)
	ui.fade_in(player.autowalk or harness.active, harness.start_at < 1.0)
	_hint_live = not (player.autowalk or harness.active)
	harness.begin()
	await get_tree().process_frame
	running = true
	player.controls_enabled = true
	if not harness.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_tree() -> void:
	Game.release()

func _warm_up() -> void:
	# visit every beat behind the black screen so pipelines, textures and LODs are ready before the fade-in
	for t in [0.0, 20.0, 60.0, 100.0, 140.0, 175.0, 200.0, 250.0, 290.0, 340.0, 380.0, 415.0, 440.0, 480.0, 530.0]:
		player.place_at_distance(PathDef.dist_at(t))
		for look in [Vector2(0, 0), Vector2(0, -1.2), Vector2(1.6, -0.3), Vector2(-1.6, -0.3)]:
			player.yaw += look.x
			player.pitch = look.y
			player._apply_rotation(0.0)
			water.update_water(Game.cam_pos(), Game.path_time)
			await get_tree().process_frame

## QA only: hides every geometry node whose shader file name contains one of `names`.
func _qa_hide(names: PackedStringArray) -> void:
	var n := 0
	for node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		var mat: Material = gi.material_override
		if mat == null and gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null and (gi as MeshInstance3D).mesh.get_surface_count() > 0:
			mat = (gi as MeshInstance3D).mesh.surface_get_material(0)
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
			var f := (mat as ShaderMaterial).shader.resource_path.get_file()
			for s in names:
				if s in f:
					gi.visible = false
					gi.layers = 0   # sticky even if a script shows the node again
					n += 1
					break
	print("QA hide %s: %d nodes" % [names, n])

func _process(_delta: float) -> void:
	if running and not paused:
		water.update_water(Game.cam_pos(), Game.path_time)

func _unhandled_input(e: InputEvent) -> void:
	if not running:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_ESCAPE:
			set_paused(not paused)
		elif e.keycode == KEY_F11:
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
	# (after the ending the UI frees the mouse for good: a click must not capture it again)
	if e is InputEventMouseButton and e.pressed and not paused and not harness.active and not player.ended:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _hint_live and (e is InputEventKey or (e is InputEventMouseMotion and e.relative.length() > 4.0)):
		_hint_live = false
		ui.hide_hint()

func set_paused(p: bool) -> void:
	if player and player.ended:
		if p:
			Game.quit(get_tree())
		return
	paused = p
	get_tree().paused = p
	ui.show_pause(p)
	if audio and audio.has_method("set_paused"):
		audio.set_paused(p)
	if not harness.active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED

func _on_end() -> void:
	var depth := int(round(-player.global_position.y))
	ui.ending(depth)
	if harness.quit_at_end:
		_quit_after_end()
	# the picture holds the final still for Config.END_HOLD before it fades: sound and picture fade together
	await get_tree().create_timer(Config.END_HOLD).timeout
	if audio and audio.has_method("end_fade"):
		audio.end_fade(Config.END_FADE + 2.0)

func _quit_after_end() -> void:
	await get_tree().create_timer(Config.END_HOLD + Config.END_FADE + 9.0).timeout
	harness.finish()
