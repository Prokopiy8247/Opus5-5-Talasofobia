extends RefCounted
## Beat 5 - The Wall: a hull so large it has no ends, gently concave so it wraps the view,
## rising from the basin floor to the surface. Its porthole lights wake deck by deck behind the statue.
##
## Interface for the choreography (world space, on the wall surface; z = wall_z(x) with WALL_Z -940):
##  WAVE_ORIGIN   where the porthole light wave starts (uw_reveal.x 0.3 -> 1 switches the rows on outward
##                from this deck, each spreading sideways; 0 -> 0.3 only fades the dark hull in out of the fog).
##  DIGITS_CENTER centre of the stencilled "07" (digits 196 m tall, 300 m wide: x 100..400, y -918..-722).
##                The door sits under the "0". Aim the reveal cue at about DIGITS_CENTER + (0, -20, 0).
##  STATUE_BACKDROP the lit zone behind the statue (centre x, y, radii x, y): densely lit, so the statue's
##                silhouette stands against lights in M5.
##  RAIL_Y        rub rail centres. They sit on the deck lines of the bare belts (decks TIER_K0 + 5n and the
##                deck under them carry no ports), so no rail or rusticle ever cuts a port.
##  TIER_K0       a belt deck index (12 m decks, tiers of five: belt, three rows, a fourth row in places).
##  wall_material gets "walk_s" (the diver's s on the line) every frame from a small driver node; the shader
##                times a few early lamp failures (s 1205-1345), a row browning out (s 1236) and a shadow
##                passing behind a row (s 1208-1283) during the long look up the wall (cue s 1182-1252) with it.
##  Wall glow     the driver also runs the warm light the lit wall throws forward, following the lit share of
##                the wall near each light (rises with the wave, falls as the rows die): "WallGlowStatue", a
##                directional on render layer 2 only (a thin amber rim on the statue against the lights), and
##                "WallGlowSilt*", omnis along the wall foot on layer 1 (the silt, the statue's heels).
## Debug (harness only): --wall-reveal X and --wall-dark X override uw_reveal.x / uw_dark on the wall (and the
## wall glow lights).

const DoorLamp := preload("res://scripts/gen/DoorLamp.gd")
const CURVE_R := 2500.0
const HALF_W := 2300.0
const NX := 96
const WAVE_ORIGIN := Vector3(-380.0, -340.0, -911.1)    # behind the statue's head and shoulder as seen in M5
const DIGITS_RECT := Rect2(100.0, -918.0, 300.0, 196.0)
const DIGITS_CENTER := Vector3(250.0, -820.0, -927.5)
const STATUE_BACKDROP := Vector4(-380.0, -380.0, 330.0, 330.0)  # where the statue projects from the M5 camera
const RAIL_Y: Array[float] = [-924.0, -684.0, -564.0, -384.0]
const TIER_K0 := -82.0         # decks -82 + 5n are bare belts (the lowest row, 7 m over the silt, is one)
const RAIL_DEPTH := 3.5        # how far the rails stand off the plating (deeper ledges hide the row above)
const GLOW_COLOR := Color(1.0, 0.47, 0.17)   # deeper than the lamps' average: on verdigris and silt it must not turn green
const GLOW_STATUE_ENERGY := 3.5       # the directional rim on the statue (layer 2) at a fully lit wall
const GLOW_SILT_ENERGY := 130.0       # each omni over the silt along the wall foot (layer 1)
# (none behind the statue: its heels stand 10 m off the wall and would flare)
const GLOW_SILT_X: Array[float] = [-360.0, 150.0, 310.0, 470.0]

static var wall_material: ShaderMaterial


## Feeds the wall shader the diver's s on the line (from the camera: works for the walk and the stills) and
## runs the wall glow lights from the shader's own wave and death fronts.
class Driver extends Node:
	var mats: Array[ShaderMaterial] = []
	var glows: Array = []                   # [Light3D, energy at full, wall point (x, y) it follows]
	var origin := Vector2(-380.0, -340.0)   # the shader's wave_origin
	var door := Vector2(170.0, -985.0)
	var reveal_override := -1.0
	var dark_override := -1.0
	var dark_s := Vector2(1265.0, 1450.0)   # Main.DARK_S, read from the running scene when it has it

	func _ready() -> void:
		var sc := get_tree().current_scene
		if sc and sc.get_script():
			var cm: Dictionary = (sc.get_script() as Script).get_script_constant_map()
			if cm.has("DARK_S"):
				dark_s = cm["DARK_S"]

	func _process(_dt: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or PathDef.main == null:
			return
		var s := PathDef.main.closest_s(cam.global_position)
		for m in mats:
			m.set_shader_parameter("walk_s", s)
		if glows.is_empty():
			return
		# Main's uw_reveal.x / uw_dark (from s), the shader's front radii (wall.gdshader: rf, F)
		var b5: float = PathDef.main.beat_s[4]
		var r := reveal_override if reveal_override >= 0.0 else smoothstep(b5 - 30.0, b5 + 100.0, s)
		var d := dark_override if dark_override >= 0.0 else smoothstep(dark_s.x, dark_s.y, s)
		var wv := clampf((r - 0.3) / 0.7, 0.0, 1.0)
		var rf := 480.0 * wv + 2520.0 * pow(wv, 10.0)
		var f := -45.0 + 1200.0 * pow(1.0 - d, 2.2) + 1900.0 * (1.0 - smoothstep(0.0, 0.05, d))
		for g in glows:
			var p: Vector2 = g[2]
			var dw := absf(p.y - origin.y) * 1.5 + absf(p.x - origin.x) / 3.0
			var dd := Vector2(p.x - door.x, (p.y - door.y) * 1.6).length()
			var k := smoothstep(dw - 10.0, dw + 120.0, rf) * (1.0 - smoothstep(f - 40.0, f + 40.0, dd))
			var l: Light3D = g[0]
			l.light_energy = float(g[1]) * k
			l.visible = k > 0.002


static func wall_z(x: float) -> float:
	return Config.WALL_Z + x * x / (2.0 * CURVE_R)


static func _col_x(i: int) -> float:
	var t := float(i) / float(NX) * 2.0 - 1.0
	return signf(t) * pow(absf(t), 1.3) * HALF_W


## z of the actual (piecewise flat) wall mesh at x: things that touch the wall use this.
static func surface_z(x: float) -> float:
	var t := signf(x) * pow(absf(x) / HALF_W, 1.0 / 1.3)
	var i := clampi(int(floor((t + 1.0) * 0.5 * NX)), 0, NX - 1)
	var x0 := _col_x(i)
	var x1 := _col_x(i + 1)
	return lerpf(wall_z(x0), wall_z(x1), clampf((x - x0) / (x1 - x0), 0.0, 1.0))


static func _arg(name: String, def: float) -> float:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--" + name)
	if i >= 0 and i + 1 < a.size():
		return float(a[i + 1])
	return def


func build(parent: Node3D) -> void:
	var mb := MeshBuilder.new()
	var rings := []
	var uu := PackedFloat32Array()
	var xs := PackedFloat32Array()
	for i in NX + 1:
		xs.append(_col_x(i))
	var ys := PackedFloat32Array([-1010.0, -960.0, -900.0, -800.0, -650.0, -450.0, -250.0, 0.0])
	for x in xs:
		var ring := PackedVector3Array()
		for y in ys:
			ring.append(Vector3(x, y, wall_z(x)))
		rings.append(ring)
		uu.append(x)
	mb.color = Color(1, 0, 0, 0)
	mb.grid(rings, uu, ys, false, false)
	for i in mb.n.size():
		if mb.n[i].z < 0.0:
			mb.n[i] = -mb.n[i]
	mb.idx.clear()
	var ny := ys.size()
	for i in NX:
		for j in ny - 1:
			var a := i * ny + j
			mb.quad(a, a + ny, a + ny + 1, a + 1)
	var door := Vector3(Config.DOOR_POS.x, Config.DOOR_POS.y, wall_z(Config.DOOR_POS.x))
	var params := {
		"wave_origin": Vector2(WAVE_ORIGIN.x, WAVE_ORIGIN.y),
		"door_pos": door,
		"digits_rect": Vector4(DIGITS_RECT.position.x, DIGITS_RECT.position.y, DIGITS_RECT.size.x, DIGITS_RECT.size.y),
		"backdrop": STATUE_BACKDROP,
		"rail_y": Vector4(RAIL_Y[0], RAIL_Y[1], RAIL_Y[2], RAIL_Y[3]),
		"tier_k0": TIER_K0,
		"reveal_override": _arg("wall-reveal", -1.0),
		"dark_override": _arg("wall-dark", -1.0),
	}
	wall_material = Mats.make("wall", params)
	var mi := mb.instance(wall_material, parent)
	mi.name = "Wall"
	mi.extra_cull_margin = 200.0
	mi.layers = DoorLamp.WALL_LAYER      # the door lamp's lights skip it: the shader lights it from the lamp
	var driver := Driver.new()
	driver.name = "WallDriver"
	driver.mats.append(wall_material)
	driver.origin = Vector2(WAVE_ORIGIN.x, WAVE_ORIGIN.y)
	driver.door = Vector2(door.x, door.y)
	driver.reveal_override = params["reveal_override"]
	driver.dark_override = params["dark_override"]
	parent.add_child(driver)
	_glow_lights(parent, driver)
	params["plain"] = 1.0
	_rails(parent, Mats.make("wall", params))


## The warm light the lit wall throws forward (see the header): a directional on the statue's layer only (no
## shadows: it only lights faces turned to the wall, i.e. the rims seen from the walk) and a row of omnis
## over the silt along the foot. The driver scales each by the lit share of the wall near it.
func _glow_lights(parent: Node3D, driver: Driver) -> void:
	var dl := DirectionalLight3D.new()
	dl.name = "WallGlowStatue"
	dl.light_color = GLOW_COLOR
	dl.light_energy = 0.0
	dl.light_specular = 0.0
	dl.light_cull_mask = 2
	dl.shadow_enabled = false
	dl.visible = false
	parent.add_child(dl)
	# from the lit field behind and above the head as the walk sees it (the camera is below the statue there,
	# so the silhouette's normals face up: a light from straight behind would miss them)
	dl.look_at_from_position(Vector3.ZERO, Vector3(0.1, -0.45, 0.9).normalized(), Vector3.UP)
	driver.glows.append([dl, GLOW_STATUE_ENERGY, Vector2(STATUE_BACKDROP.x, STATUE_BACKDROP.y)])
	for x in GLOW_SILT_X:
		var z := wall_z(x) + 10.0
		var o := OmniLight3D.new()
		o.name = "WallGlowSilt%d" % int(x)
		o.light_color = GLOW_COLOR
		o.light_energy = 0.0
		o.light_specular = 0.0
		o.omni_range = 160.0
		o.omni_attenuation = 0.5
		o.light_cull_mask = 1
		o.shadow_enabled = false
		o.visible = false
		o.position = Vector3(x, Terrain.height(x, z) + 30.0, z)
		parent.add_child(o)
		driver.glows.append([o, GLOW_SILT_ENERGY, Vector2(x, -972.0)])


## Rub rails: long horizontal ledges that give the plane depth and parallax, with rusticles hanging
## under them near the walk. They share the wall shader (plain), so they carry the plating, the rust and the
## lights' warm sheen, and read as ledges in front of the lit field; hidden in the fog until the reveal.
func _rails(parent: Node3D, mat: ShaderMaterial) -> void:
	var rails := MeshBuilder.new()
	var drips := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 505
	for ry in RAIL_Y:
		var prev := Vector3.ZERO
		var k := 0
		var x := -HALF_W
		while x <= HALF_W:
			var p := Vector3(x, ry, wall_z(x) + RAIL_DEPTH * 0.5)
			if k > 0:
				var mid := (prev + p) * 0.5
				var dir := (p - prev)
				var b := Basis(dir.normalized(), Vector3.UP, dir.normalized().cross(Vector3.UP).normalized() * -1.0)
				rails.box(mid, Vector3(dir.length() + 0.5, 3.0, RAIL_DEPTH), b.orthonormalized())
			prev = p
			x += 60.0
			k += 1
		# rusticles: clusters of thin cones under the ledge, dense where the walk can see them; short enough
		# to end above the porthole row below (a deck under the rail)
		x = -900.0
		while x < 1100.0:
			var near := 1.0 - smoothstep(250.0, 900.0, absf(x - 200.0))
			x += rng.randf_range(3.0, 9.0) / maxf(near, 0.25)
			if rng.randf() > 0.35 + 0.6 * near:
				continue
			for m in rng.randi_range(1, 3):
				var top := Vector3(x + rng.randf_range(-1.5, 1.5), ry - 1.4, 0.0)
				top.z = wall_z(top.x) + rng.randf_range(0.5, RAIL_DEPTH - 0.3)
				var ln := rng.randf_range(0.8, 2.6) * (1.0 if rng.randf() < 0.8 else 1.3)
				var r := ln * rng.randf_range(0.07, 0.12)
				var bot := top + Vector3(rng.randf_range(-0.2, 0.2), -ln, rng.randf_range(-0.2, 0.2))
				drips.cylinder(top, bot, r, r * 0.12, 5, false)
	var rmi := rails.instance(mat, parent)
	rmi.name = "RubRails"
	rmi.extra_cull_margin = 50.0
	var dmi := drips.instance(Mats.solid(Palette.RUST.darkened(0.45), 1.0, 0.0, {"noise_scale": 0.6, "hide_until_reveal": true}), parent)
	dmi.name = "Rusticles"
