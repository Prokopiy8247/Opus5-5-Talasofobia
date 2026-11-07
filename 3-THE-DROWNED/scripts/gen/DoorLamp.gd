extends Node3D
## The amber lamp over the door: a shadowed omni under the shade, a shadowed spot pool on the steps and the
## silt, the bulb and its glow halos, a faint decal haze on the silt, plus any emitters registered with
## add_emitter() (the door's window).
## In group "door_lamp". set_power(p) with p 0..1 dims all of it together (the ending flicker);
## set_power(p, w) drives the window separately (w 0..1, default = p).
##
## Every material darkens ALBEDO with depth (uw_albedo_light, ~0.18 at the floor) as a stand-in for the lost
## sun, which would swallow a lamp's light. The lamp's energies carry DEPTH_GAIN (~1 / uw_albedo_light) so it
## lights the floor, the props and the wall with their true albedo; light_specular is divided by the same
## gain so highlights stay physical. The door props sit on PROP_LAYER (render layer 10) so the decal (layer 1)
## skips them. Layer 2 is the statue's rim light: not used here.
## The marine snow (shaders/snow.gdshader) is lit amber around the bulb: setup() hands it the bulb's world
## position, set_power() its power.
## The wall sits on WALL_LAYER (render layer 11), outside the omni's and the spot's cull masks: the wall shader
## lights itself from this lamp (lamp_pos / lamp_col / lamp_power, set here) with a soft shade shadow, since
## the omni's hard shadows of the shade, the lintel and the ladder read as stray pale edges and dark wedges.
## (So does the door's doubler plate: every "wall" material made before setup() gets the lamp.)
## The halos are depth-correct (glow.gdshader inscatter): a camera-facing quad this close to the wall used
## to cut into it, leaving a hard vertical line in the pool (amber on one side of the ladder, dark on the other).

const PROP_LAYER := 1 << 9       # render layer 10
const WALL_LAYER := 1 << 10      # render layer 11
const DEPTH_GAIN := 5.5
const OMNI_ENERGY := 9.0
const SPOT_ENERGY := 22.0
const SPECULAR := 0.6
const POOL_ENERGY := 0.15        # warm lit-silt haze on top (decal emission, unshadowed)

var omni: OmniLight3D
var spot: SpotLight3D
var pool: Decal
var power := 1.0
var _emitters: Array = []     # [material, parameter, base value, follows window]
var _lights: Array = []       # [light, base energy]
var _snow: Array[ShaderMaterial] = []
var _walls: Array[ShaderMaterial] = []


func _init() -> void:
	name = "DoorLamp"
	add_to_group("door_lamp")


func _omni(pos: Vector3, energy: float, mask: int, shadow: bool, spec: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = Palette.AMBER
	l.light_energy = energy
	l.omni_range = 18.0
	l.omni_attenuation = 1.0
	l.shadow_enabled = shadow
	l.shadow_bias = 0.03
	l.shadow_normal_bias = 1.0
	l.shadow_blur = 1.5
	l.light_specular = spec
	l.light_cull_mask = mask
	l.position = pos
	add_child(l)
	_lights.append([l, energy])
	return l


func _spot(pos: Vector3, dir: Vector3, energy: float, angle: float, mask: int, shadow: bool, spec: float) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = Palette.AMBER.lerp(Color(1, 0.85, 0.6), 0.25)
	l.light_energy = energy
	l.spot_range = 16.0
	l.spot_angle = angle
	l.spot_angle_attenuation = 1.6
	l.spot_attenuation = 1.0
	l.shadow_enabled = shadow
	l.shadow_bias = 0.03
	l.shadow_blur = 1.5
	l.light_specular = spec
	l.light_cull_mask = mask
	l.transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), pos)
	add_child(l)
	_lights.append([l, energy])
	return l


## bulb: local position of the bulb centre. Builds lights, bulb and halos as children.
func setup(bulb: Vector3) -> void:
	var lamp := bulb + Vector3(0, -0.06, 0.0)          # under the shade: the wall above stays dark
	var down := Vector3(0.0, -0.78, 0.62)
	var all := 0xFFFFF & ~WALL_LAYER
	omni = _omni(lamp, OMNI_ENERGY * DEPTH_GAIN, all, true, SPECULAR / DEPTH_GAIN)
	omni.light_size = 0.06                 # soft edge of the shade's shadow on the wall (PCSS)
	spot = _spot(lamp + Vector3(0, 0, 0.12), down, SPOT_ENERGY * DEPTH_GAIN, 58.0, all, true, SPECULAR / DEPTH_GAIN)
	spot.spot_attenuation = 1.1            # a pool that falls off on the silt
	var mb := MeshBuilder.new()
	mb.sphere(bulb, 0.085, 12)
	var bulb_mat := Mats.emissive(Palette.AMBER, 16.0)
	mb.instance(bulb_mat, self).layers = PROP_LAYER
	add_emitter(bulb_mat, "emission_energy", 16.0)
	for g in [[Vector3(0, 0, 0.03), 3.0, 2.2], [Vector3(0, -0.16, 0.3), 18.0, 0.28], [Vector3(0, -1.0, 1.2), 32.0, 0.04]]:
		# depth-correct halos: a camera-facing quad this close to the wall used to cut into it along a vertical
		# line (amber on one side of the ladder, dark on the other)
		var spr := Mats.glow_sprite(self, bulb + g[0], g[1], Palette.AMBER, g[2], -1.0, true)
		add_emitter(spr.material_override, "energy", g[2])
	# a faint warm haze on the silt in front of the door (unshadowed, seabed only)
	pool = Decal.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1))
	gr.set_color(1, Color(0, 0, 0))
	gr.add_point(0.3, Color(0.5, 0.5, 0.5))
	gr.add_point(0.65, Color(0.1, 0.1, 0.1))
	var tex := GradientTexture2D.new()
	tex.gradient = gr
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.25)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 128
	tex.height = 128
	pool.texture_emission = tex
	pool.modulate = Palette.AMBER
	pool.emission_energy = POOL_ENERGY
	pool.size = Vector3(14.0, 6.0, 12.0)
	pool.position = Vector3(0.0, -1.5, 5.1)
	pool.normal_fade = 0.35
	pool.upper_fade = 0.15
	pool.lower_fade = 0.3
	pool.cull_mask = 1
	add_child(pool)
	# warm motes: the snow drifting through the lamp's light
	_snow = Mats.with_shader("snow")
	for m in _snow:
		m.set_shader_parameter("warm_pos", to_global(bulb))
		m.set_shader_parameter("warm_col", Palette.AMBER.lerp(Color(1, 0.85, 0.6), 0.2))
		m.set_shader_parameter("warm_power", power)
	# the wall (and its rails) light themselves from the lamp, with a soft shade shadow
	_walls = Mats.with_shader("wall")
	for m in _walls:
		m.set_shader_parameter("lamp_pos", to_global(lamp))
		m.set_shader_parameter("lamp_col", Palette.AMBER)
		m.set_shader_parameter("lamp_power", OMNI_ENERGY * power)


func add_emitter(mat: Material, param: String, base: float, window := false) -> void:
	_emitters.append([mat, param, base, window])
	(mat as ShaderMaterial).set_shader_parameter(param, base * power)


func set_power(p: float, window := -1.0) -> void:
	power = clampf(p, 0.0, 1.0)
	var w := power if window < 0.0 else clampf(window, 0.0, 1.0)
	for l in _lights:
		(l[0] as Light3D).light_energy = float(l[1]) * power
		(l[0] as Light3D).visible = power > 0.001
	if pool:
		pool.emission_energy = POOL_ENERGY * power
		pool.visible = power > 0.001
	for e in _emitters:
		(e[0] as ShaderMaterial).set_shader_parameter(e[1], float(e[2]) * (w if e[3] else power))
	for m in _snow:
		m.set_shader_parameter("warm_power", power)
	for m in _walls:
		m.set_shader_parameter("lamp_power", OMNI_ENERGY * power)
