extends Node3D
## SCP-3000 prefab: finished mesh + wet skin material, an endless procedural body that continues the spine into
## the deep, and the slow life: serpentine wave, head turn towards a target, jaw sway, eye pulse and gaze.
##
## Staging (beat 4 -> 5) without any per-part fade: how much of the creature shows depends only on where a point
## is relative to the camera (the water fog, plus a light creature-only haze that depends on the path time) and on
## the body's own motion. The front of the body (head, neck, coils) lies RISE metres deeper at the start of beat 4
## and slowly rises out of the dark to its final pose; the far body (the dark line) lies still the whole time and is
## the only part that gets a stronger silhouette while it is the subject (line_boost). From the eye lock on, every
## part of the body beyond 170 m keeps its dark silhouette further into the murk (far_k_at, distance only), so the
## coils behind the neck and the endless body read as one continuous giant instead of a neck ending in a cap.

const WAVE_PERIOD := 32.0          # seconds: a giant moves slowly
const WAVE_COUNT := 1.2            # wavelengths along the finished body
const WAVE_AMP := 7.5              # lateral amplitude towards the tail (model m)
const SLOW_PERIOD := 80.0
const SLOW_AMP := 1.6
const AMP_SETTLED := 0.6           # wave amplitude scale after the flex has settled
const RISE := 120.0                # world m the front of the body lies deeper at the start of beat 4
const RISE_T := Vector2(236.0, 360.0)
const RISE_ARC := Vector2(30.0, 380.0)    # world m along the extension: the rise blends out here (the line lies still)
const BOOST_ARC := Vector2(100.0, 350.0)  # world m along the extension: the line boost blends in here
const GIRTH_HOLD := 6.6            # model m: the trunk keeps this radius from s ~0.5 to the cut (no tail taper)
const GIRTH_FAR := 8.0             # model m: the endless body grows to this (about 1.15x the neck)
const LOCK_RANGE := 120.0          # world m over which the eye-lock veil acts (mirror in creature_vis())
const FAR_K := 0.005               # per world m beyond 170 m: far silhouette kept from the eye lock on (far_k_at)
const TOP_SCATTER := 0.45          # far body: share of the water's glow its upper side returns (top_scatter_at)
# the flex ("it is alive", Config.EVENTS flex): one S-bend travels down the dark line, away from the front of the body
const FLEX_AMP := 25.0             # world m: peak lateral offset of the S-bend
const FLEX_W := 140.0              # world m: half-width of the S (it spans about 2.8x this; wide enough that the
                                   # bend it adds never pinches the inner corner of the line's hook)
const FLEX_ARC0 := 330.0           # world m along the extension: centre of the S at the flex event
const FLEX_SPEED := 10.0           # world m/s down the body
const EYE_GLOW := 1.4             # iris emission at full wake (x eye_gain from the gaze alignment, x hold)
const EYE_GAIN := 3.2              # eyeshine gain when an eye looks straight at the camera (1 when it ignores it)
const HALO_K := 0.04               # share of the iris emission the water around the eye glows with (at its centre)
const HALO_SIZE := 4.0             # halo disc half-size in iris radii (the iris is ~0.5 eye radius across)
const EXT_FINE_ARC := 420.0        # model m of the extension sampled finely (the part ever seen from < ~400 m)
const EXT_SEGMENTS := 56           # ring segments of the extension
const FOLD_KEEP := 0.35            # on a tight bend the swim wave may compress the tube's inner side to this share
const WAVE_FREE_ARC := 70.0        # model m from the junction where the extension always sways like the mesh (the
                                   # coils behind the neck keep the motion they had; the dark line starts beyond)

@export var creature_scale := 7.0
@export var undulation_amplitude := WAVE_AMP
@export var undulation_period := WAVE_PERIOD
@export var wave_count := WAVE_COUNT
@export var jaw_sway := 0.05                # radians
@export var head_turn_target: Node3D        # the head turns towards this when look_weight > 0
@export var look_weight := 0.0              # 0 = rest pose, 1 = locked on target
@export var away_yaw := -0.32               # radians, where the head turns when it loses interest
@export var drift_speed := 0.45             # world m/s along the head direction (slow, heavy)
@export var s_cut := 0.75                   # the tail beyond this folds away; the procedural body continues
@export var extension_world: PackedVector3Array

const META := "res://assets/creatures/scp3000_meta.json"
const EYE_LOOK: Array[StringName] = [&"eye_look0", &"eye_look1"]
const EYE_CATCH: Array[StringName] = [&"eye_catch0", &"eye_catch1"]
var meta: Dictionary
var mat: ShaderMaterial
var body_mat: ShaderMaterial
var base_pos := Vector3.ZERO
var heading := Vector3.FORWARD
var riders: Array[Node3D] = []      # nodes that ride along with the slow drift and the rise (cleaner fish)
var motion_time := 0.0
var jaw_extra := 0.0
var head_yaw := 0.0
var head_pitch := 0.0
var _yaw_v := 0.0
var _pitch_v := 0.0
var _gaze := 0.3
var _wake := 0.5
var spine: PackedVector3Array
var tangents: PackedVector3Array
var radii: PackedFloat32Array
var markers := {}
var eye_lights: Array[OmniLight3D] = []
var amp_scale := 0.12                        # the line lies still until it flexes (beat 4)
var ribbon_mat: ShaderMaterial               # fluid seeps under the neck (Beat05), faded with the head
var rise := 0.0                              # current rise offset (world m, the front of the body is this much lower)
var boost_s := Vector2(2.0, 3.0)             # body parameter range where the line boost blends in
var _ext_s0 := 0.0
var _ext_pts: PackedVector3Array             # sparse extension samples (model space) for presence()
var _ext_ss: PackedFloat32Array
var _ext_r: PackedFloat32Array
var _line_mid := Vector3.ZERO                # model-space point of the dark line (gaze target)
var _line_s := 0.0
var _line_tan := Vector3.FORWARD
var _line_marker: Node3D
var _mats: Array[ShaderMaterial] = []
var _presence := 0.0
var _head_vis := 0.0
var _flex_c := -10000.0                      # model m (body arc s * spine_len) of the flex S-bend centre
var _flex_amp := 0.0                         # model m
var _eye_gain := Vector2.ONE
var _eye_glow := 0.0
var _halos: Array[MeshInstance3D] = []
var _halo_mats: Array[ShaderMaterial] = []

func _ready() -> void:
	meta = JSON.parse_string(FileAccess.open(META, FileAccess.READ).get_as_text())
	for p in meta["spine"]: spine.append(Vector3(p[0], p[1], p[2]))
	for p in meta["tangent"]: tangents.append(Vector3(p[0], p[1], p[2]))
	for r in meta["radius"]: radii.append(float(r))
	scale = Vector3.ONE * creature_scale
	base_pos = position
	heading = (global_basis * (spine_at(0.0) - spine_at(0.2))).normalized()
	var L := float(meta["spine_length"])
	_ext_s0 = s_cut - 0.015
	boost_s = Vector2(_ext_s0 + BOOST_ARC.x / creature_scale / L, _ext_s0 + BOOST_ARC.y / creature_scale / L)
	var glb: Node3D = load("res://assets/creatures/SCP3000.glb").instantiate()
	add_child(glb)
	var detail := _detail_tex()
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/scp3000.gdshader")
	mat.set_shader_parameter("albedo_tex", load("res://assets/creatures/scp3000_albedo.png"))
	mat.set_shader_parameter("normal_tex", load("res://assets/creatures/scp3000_normal.png"))
	mat.set_shader_parameter("mask_tex", load("res://assets/creatures/scp3000_mask.png"))
	mat.set_shader_parameter("detail_tex", detail)
	mat.set_shader_parameter("spine_tex", _spine_tex())
	mat.set_shader_parameter("s_cut", s_cut)
	mat.set_shader_parameter("s_neck", float(meta["s_turn"][0]) + 0.04)
	mat.set_shader_parameter("head_pivot", _v(meta["neck_pivot"]))
	mat.set_shader_parameter("jaw_hinge", _v(meta["jaw_hinge"]))
	mat.set_shader_parameter("eye_c0", _v(meta["eyes"][0]["center"]))
	mat.set_shader_parameter("eye_c1", _v(meta["eyes"][1]["center"]))
	mat.set_shader_parameter("eye_r0", float(meta["eyes"][0]["radius"]))
	mat.set_shader_parameter("eye_r1", float(meta["eyes"][1]["radius"]))
	mat.set_shader_parameter("eye_g0", _v(meta["eyes"][0]["gaze"]).normalized())
	mat.set_shader_parameter("eye_g1", _v(meta["eyes"][1]["gaze"]).normalized())
	mat.set_shader_parameter("eye_color", Palette.EYE_CYAN)
	mat.set_shader_parameter("girth_hold", GIRTH_HOLD)
	for mi in glb.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16.0 + RISE / creature_scale
	body_mat = ShaderMaterial.new()
	body_mat.shader = load("res://shaders/scp3000_body.gdshader")
	body_mat.set_shader_parameter("ext_s0", _ext_s0)
	body_mat.set_shader_parameter("rise_arc", RISE_ARC / creature_scale)
	_mats = [mat, body_mat]
	var relief := _relief_tex()
	for m in _mats:
		m.set_shader_parameter("detail_tex", detail)
		m.set_shader_parameter("relief_tex", relief)
		m.set_shader_parameter("spine_len", L)
		m.set_shader_parameter("olive", Palette.SERPENT_OLIVE)
		m.set_shader_parameter("dark", Palette.SERPENT_DARK)
		m.set_shader_parameter("boost_s", boost_s)
	_push_wave_params()
	if extension_world.size() > 0:
		_build_extension()
	for i in 2:
		var l := OmniLight3D.new()
		l.light_color = Palette.EYE_CYAN
		l.omni_range = 34.0
		l.omni_attenuation = 1.6
		# a faint cyan wash on the brow and lids only: a point light this close to the wet eyeball would put a
		# ring of single-pixel HDR highlights on the rim of the cap (and the iris glows on its own)
		l.light_specular = 0.0
		l.shadow_enabled = false
		l.visible = false
		l.light_energy = 0.0
		get_parent().add_child.call_deferred(l)
		eye_lights.append(l)
	# the eye's glow in the water around it (scp3000_eye_halo.gdshader): a camera-facing additive disc per eye
	var halo_shader: Shader = load("res://shaders/scp3000_eye_halo.gdshader")
	for i in 2:
		var iris_r := float(meta["eyes"][i]["radius"]) * creature_scale * 0.5
		var hm := ShaderMaterial.new()
		hm.shader = halo_shader
		hm.set_shader_parameter("color", Palette.EYE_CYAN)
		hm.set_shader_parameter("iris_r", iris_r)
		hm.set_shader_parameter("radius", iris_r * HALO_SIZE)
		hm.set_shader_parameter("fade_m", iris_r * 1.5)
		hm.set_shader_parameter("intensity", 0.0)
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		var h := MeshInstance3D.new()
		h.name = "EyeHalo%d" % i
		h.mesh = q
		h.material_override = hm
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.extra_cull_margin = iris_r * HALO_SIZE * 2.0
		h.visible = false
		get_parent().add_child.call_deferred(h)
		_halos.append(h)
		_halo_mats.append(hm)
	for k in ["eye", "head", "neck", "coils_b5", "coils_b4", "creature_body"]:
		var m := Node3D.new()
		m.name = "T_" + k
		get_parent().add_child.call_deferred(m)
		markers[k] = m
		Game.targets[k] = m

func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

# ---------------------------------------------------------------------------------------------------------------
# Staging, shared with Tools/qa/creature_check.gd and mirrored in scp3000_common.gdshaderinc. All functions of the
# path time t (Game.path_time, which is position based) and of the distance from the camera; none of a body part,
# except the dark-line boost on the far body.

## World metres the front of the body (finished mesh + the start of the extension) lies below its final pose.
static func rise_at(t: float) -> float:
	return RISE * (1.0 - smoothstep(RISE_T.x, RISE_T.y, t))

## Extra optical depth per metre on the creature only: a reveal haze that relaxes as beat 4 begins (the dark line
## comes out of the murk).
static func haze_at(t: float) -> float:
	return 0.0065 * (1.0 - smoothstep(222.0, 282.0, t))

## A light veil around the eye lock so the head sits back in the water at 90-100 m (per metre over the first
## LOCK_RANGE m only, so the body further back keeps its dark silhouette instead of vanishing).
static func lock_haze_at(t: float) -> float:
	# released only after the camera has let the eye go (~458 s): an earlier release relit the eye as it left the frame
	return 0.0045 * smoothstep(365.0, 400.0, t) * (1.0 - smoothstep(456.0, 492.0, t))

## While the dark line is the subject (beat 4) the far body keeps a stronger silhouette than the deep fog alone
## would leave; back to plain fog once the coils take over.
static func line_boost(t: float) -> float:
	return 1.0 + 1.55 * smoothstep(240.0, 274.0, t) * (1.0 - smoothstep(282.0, 336.0, t))

## Grazing-angle melt of the silhouette (soft forward-scatter edge). None while the creature emerges: a big dark
## shape arrives silhouette first.
static func rim_melt_at(t: float) -> float:
	return 0.1 * smoothstep(345.0, 385.0, t)

## Faint backscatter rim on the upper silhouette of the body (the water's own glow wrapping round a curve that
## turns away: the neck's bend reads as a bend, not as the end of the body). Only once the creature is fully there.
static func rim_glow_at(t: float) -> float:
	return 0.22 * smoothstep(350.0, 385.0, t)

## The water's downwelling glow on the upper side of the far body (beyond ~150 m; creature_top_scatter()): from the
## dark line on, the back reads round with a slightly lighter upper flank and the belly melts into the water. Always
## a share (< 1) of the water colour behind the body, so the silhouette never gets a bright contour.
static func top_scatter_at(t: float) -> float:
	return TOP_SCATTER * smoothstep(244.0, 262.0, t)

## Peak lateral offset (world m) of the one-off travelling flex: it grows as the line comes alive and dies out
## once the S has run down the visible line.
static func flex_amp_at(t: float) -> float:
	var f: float = Config.EVENTS["flex"]
	return FLEX_AMP * smoothstep(f - 3.0, f + 5.0, t) * (1.0 - smoothstep(f + 21.0, f + 31.0, t))

## Centre of the flex S-bend: world m along the extension from the junction (it runs down the body, head to tail).
static func flex_arc_at(t: float) -> float:
	return FLEX_ARC0 + FLEX_SPEED * (t - float(Config.EVENTS["flex"]))

## From the eye lock on, the body beyond 170 m keeps its silhouette deeper into the murk: optical depth taken back per
## metre beyond 170 m (at most 260 m of it). Smaller than the deep fog density (0.0064), so visibility still falls
## monotonically with distance; eased back towards the end so the last image keeps its plain deep-blue fog.
static func far_k_at(t: float) -> float:
	return FAR_K * smoothstep(385.0, 430.0, t) * (1.0 - 0.6 * smoothstep(470.0, 515.0, t))

## Transmittance multiplier of a body point at parameter s and distance d (mirror of creature_vis() in the shader).
static func vis_mult(t: float, s: float, d: float, bs: Vector2) -> float:
	var b := 1.0 + (line_boost(t) - 1.0) * smoothstep(bs.x, bs.y, s) * smoothstep(170.0, 240.0, d)
	return exp(-haze_at(t) * d - lock_haze_at(t) * minf(d, LOCK_RANGE) + far_k_at(t) * clampf(d - 170.0, 0.0, 260.0)) * b

## Wave amplitude scale: the line lies nearly still until it flexes, then settles to a slow swell.
static func amp_scale_at(t: float) -> float:
	var ev: Dictionary = Config.EVENTS
	return 0.12 + (AMP_SETTLED - 0.12) * smoothstep(ev["flex"] - 3.0, ev["flex"] + 18.0, t)

## The extension follows the rise of the front body near the junction and lies still further out (model m offset
## added back in the body shader).
func ext_rise_model(s: float) -> float:
	var arc := (s - _ext_s0) * float(meta["spine_length"]) * creature_scale
	return rise / creature_scale * smoothstep(RISE_ARC.x, RISE_ARC.y, arc)

## How visible the creature is overall right now from the camera, 0..1: the strongest share of its own colour that
## survives the water between it and the camera (same model as the shaders). For other systems that should follow
## the reveal (cleaner fish, sound).
func presence() -> float:
	return _presence

## Visibility (0..1) of the creature's body at a world point (e.g. a cleaner-fish group on the skin), s = body
## parameter of that point (0 head, ~0.4 coils, > 0.62 endless body).
func visibility_at(world_pos: Vector3, s := 0.4) -> float:
	var d := world_pos.distance_to(Game.cam_pos())
	return clampf(exp(-_fog_density() * d) * vis_mult(Game.path_time, s, d, boost_s), 0.0, 1.0)

func _fog_density() -> float:
	var w := get_world_3d()
	if w and w.environment:
		return w.environment.fog_density
	return 0.0064

func _measure_presence(t: float) -> float:
	var cam := Game.cam_pos()
	var dens := _fog_density()
	var best := 0.0
	var head_best := 0.0
	var xf := global_transform
	for k in 26:
		var s := 0.6 * k / 25.0
		var w := xf * deformed(spine_at(s), s, s < 0.1)
		var d := maxf(w.distance_to(cam) - _radius_at(s) * creature_scale, 1.0)
		var v := exp(-dens * d) * vis_mult(t, s, d, boost_s)
		best = maxf(best, v)
		if s < 0.1:
			head_best = maxf(head_best, v)
	for k in _ext_pts.size():
		var s := _ext_ss[k]
		var p := _ext_pts[k] + Vector3(0.0, ext_rise_model(s), 0.0)
		var d := maxf((xf * p).distance_to(cam) - _ext_r[k] * creature_scale, 1.0)
		best = maxf(best, exp(-dens * d) * vis_mult(t, s, d, boost_s))
	_head_vis = clampf(head_best, 0.0, 1.0)
	return clampf(best, 0.0, 1.0)

func spine_at(s: float) -> Vector3:
	var f := clampf(s, 0.0, 1.0) * (spine.size() - 1)
	var i := mini(int(f), spine.size() - 2)
	return spine[i].lerp(spine[i + 1], f - i)

func tangent_at(s: float) -> Vector3:
	var f := clampf(s, 0.0, 1.0) * (tangents.size() - 1)
	var i := mini(int(f), tangents.size() - 2)
	return tangents[i].lerp(tangents[i + 1], f - i).normalized()

func _radius_at(s: float) -> float:
	var f := clampf(s, 0.0, 1.0) * (radii.size() - 1)
	var i := mini(int(f), radii.size() - 2)
	return lerpf(radii[i], radii[i + 1], f - i)

func _spine_tex() -> ImageTexture:
	var n := spine.size()
	var img := Image.create(n, 3, false, Image.FORMAT_RGBAF)
	for i in n:
		img.set_pixel(i, 0, Color(spine[i].x, spine[i].y, spine[i].z, 1.0))
		img.set_pixel(i, 1, Color(tangents[i].x, tangents[i].y, tangents[i].z, 1.0))
		img.set_pixel(i, 2, Color(radii[i], 0.0, 0.0, 1.0))
	return ImageTexture.create_from_image(img)

func _detail_tex() -> NoiseTexture2D:
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_CELLULAR
	nz.frequency = 0.035
	nz.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 4.0
	t.noise = nz
	return t

## Smooth FBM normal map for the coarse skin relief (soft swells and folds a few metres across). The cellular map
## above is only fine wrinkles: at the coarse scale its cells read as straight cuts and seams under the top light.
func _relief_tex() -> NoiseTexture2D:
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 0.02
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 4
	nz.fractal_gain = 0.45
	nz.seed = 7
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 6.0
	t.noise = nz
	return t

func _push_wave_params() -> void:
	for m in _mats:
		m.set_shader_parameter("wave_period", undulation_period)
		m.set_shader_parameter("wave_count", wave_count)
		m.set_shader_parameter("slow_period", SLOW_PERIOD)

## GDScript mirror of body_wave() in scp3000_common.gdshaderinc (for gaze targets on the moving body).
func body_wave(s: float) -> Vector2:
	var amp := lerpf(0.25, undulation_amplitude * amp_scale, smoothstep(0.06, 0.95, minf(s, 1.0)))
	var ph := TAU * (wave_count * s - motion_time / undulation_period)
	var ps := TAU * (0.55 * s - motion_time / SLOW_PERIOD) + 1.3
	var sa := SLOW_AMP * (0.3 + 0.7 * amp_scale / AMP_SETTLED) * smoothstep(0.05, 0.5, s)
	var L := float(meta["spine_length"])
	var w := Vector2(amp * sin(ph) + sa * sin(ps), (amp * cos(ph) * TAU * wave_count + sa * cos(ps) * TAU * 0.55) / L)
	# the travelling flex S-bend (mirror of the flex term in scp3000_common.gdshaderinc)
	var fw := FLEX_W / creature_scale
	var x := (s * L - _flex_c) / fw
	var g := exp(-minf(x * x, 60.0))
	return w + Vector2(_flex_amp * 2.3316 * x * g, _flex_amp * 2.3316 * (1.0 - 2.0 * x * x) * g / fw)

func _side(t: Vector3) -> Vector3:
	return Vector3(-t.z, 0.0, t.x).normalized()

## Model-space position of a body point after the wave (and the head turn for head points).
func deformed(p: Vector3, s: float, head: bool) -> Vector3:
	if head:
		var sn: float = mat.get_shader_parameter("s_neck")
		var wn := body_wave(sn)
		var pivot := _v(meta["neck_pivot"])
		var lat := Vector3.UP.cross(tangent_at(sn)).normalized()
		var yaw := head_yaw - atan(wn.y) * 0.6
		var hb := Basis(Vector3.UP, yaw) * Basis(lat, head_pitch)
		return hb * (p - pivot) + pivot + _side(tangent_at(sn)) * wn.x
	var w := body_wave(s)
	return p + _side(tangent_at(s)) * w.x

## Extension radius (model m) at model arc a from the junction: starts at the held trunk girth and grows to
## GIRTH_FAR, so the body feels larger the further it goes.
static func ext_radius(a: float, r0: float) -> float:
	var r := lerpf(r0, GIRTH_FAR, smoothstep(60.0, 150.0, a))
	# slow girth swells (a living body, not an extruded tube); none at the junction with the mesh
	return r * (1.0 + smoothstep(10.0, 60.0, a) * (0.06 * sin(a * 0.045 + 0.7) + 0.04 * sin(a * 0.113 + 2.1)))

## Cross-section shape factor at model arc a and angle ang around the body (0 = top): a slightly flattened oval with
## a dorsal crest that continues the finished mesh's crest (taller, serrated near the junction, then a low keel).
## Mirror of ext_profile() in scp3000_common.gdshaderinc (the mesh takes this profile over its last metres).
static func ext_shape(a: float, ang: float) -> float:
	var crest := lerpf(0.25, 0.13, smoothstep(0.0, 60.0, a)) + 0.06 * sin(a * 1.3) * (1.0 - smoothstep(0.0, 40.0, a))
	var shape := 1.0 - 0.1 * cos(2.0 * ang) + crest * exp(-pow(ang / 0.22, 2.0)) - 0.05 * exp(-pow((absf(ang) - PI) / 0.5, 2.0))
	# helical skin ripples near the junction only (on the far body they bend the outline into straight runs and kinks)
	var rip := 1.0 - smoothstep(40.0, 110.0, a)
	return shape * (1.0 + rip * (0.012 * sin(a * 0.9 + ang + 0.4) + 0.006 * sin(a * 2.6 - ang * 2.0)))

## Lateral swim-wave scale along the extension, per path sample: (scale 0..1, its derivative per model m of arc). The
## wave shifts every ring along its horizontal side vector, so on the inner side of a bend it pulls the tube surface
## together; once wave + flank radius approach the bend radius the inner side folds through itself and the body shows
## a crease at some wave phases (it read as a capped tube end at the arch under the float). Where a bend is too tight
## for the full wave, the wave is scaled down until the inner side keeps FOLD_KEEP of its length, eased in and out
## over ~50 model m (C1, so no lighting seam). Never within WAVE_FREE_ARC of the junction (there the extension must
## sway exactly like the finished mesh). The CPU body_wave() needs no mirror: no marker sits on the extension's sway.
func _ext_wave_scale(path: Array[Vector3], arcs: PackedFloat32Array, r0: float) -> PackedVector2Array:
	var n := path.size()
	var out := PackedVector2Array()
	out.resize(n)
	out.fill(Vector2(1.0, 0.0))
	if n < 16:
		return out
	var tg := PackedVector3Array()
	tg.resize(n)
	for i in n:
		tg[i] = (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
	# 1 model m bins of the largest scale each bend allows
	var nb := int(ceil(arcs[n - 1])) + 2
	var kb := PackedFloat32Array()
	kb.resize(nb)
	kb.fill(1.0)
	var a_wave := WAVE_AMP * AMP_SETTLED + SLOW_AMP
	# while the flex runs, its S adds to a wave that has not settled yet (about +3 model m over the settled wave)
	var flex_lo := (FLEX_ARC0 - 2.5 * FLEX_W) / creature_scale
	var flex_hi := (FLEX_ARC0 + 31.0 * FLEX_SPEED + 2.5 * FLEX_W) / creature_scale
	for i in n:
		var a := arcs[i]
		if a < WAVE_FREE_ARC:
			continue
		var i0 := maxi(i - 6, 0)
		var i1 := mini(i + 6, n - 1)
		var ds := arcs[i1] - arcs[i0]
		if ds < 1e-3:
			continue
		# curvature towards the ring's side vector (the vertical part of a bend is not folded by a sideways wave)
		var k_side := absf(((tg[i1] - tg[i0]) / ds).dot(_side(tg[i])))
		if k_side < 1e-5:
			continue
		var amp := a_wave + (3.0 if (a >= flex_lo and a <= flex_hi) else 0.0)
		var r_flank := ext_radius(a, r0) * 1.1
		var k := clampf(((1.0 - FOLD_KEEP) / k_side - r_flank) / amp, 0.0, 1.0)
		var b := int(a)
		kb[b] = minf(kb[b], k)
	if _min_of(kb) >= 0.999:
		return out
	# widen each minimum by +-8 m, ramp back to 1 over 40 m, then blur twice by +-6 m (C1 ease, the minimum kept)
	var km := PackedFloat32Array()
	km.resize(nb)
	for b in nb:
		var m := 1.0
		for j in range(maxi(b - 8, 0), mini(b + 9, nb)):
			m = minf(m, kb[j])
		km[b] = m
	for b in range(1, nb):
		km[b] = minf(km[b], km[b - 1] + 1.0 / 40.0)
	for b in range(nb - 2, -1, -1):
		km[b] = minf(km[b], km[b + 1] + 1.0 / 40.0)
	for _pass in 2:
		var acc := PackedFloat32Array()
		acc.resize(nb + 1)
		acc[0] = 0.0
		for b in nb:
			acc[b + 1] = acc[b] + km[b]
		var bl := PackedFloat32Array()
		bl.resize(nb)
		for b in nb:
			var lo := maxi(b - 6, 0)
			var hi := mini(b + 7, nb)
			bl[b] = (acc[hi] - acc[lo]) / float(hi - lo)
		km = bl
	var kmin := 1.0
	var eased := 0.0
	var spans := ""
	var span_from := -1.0
	var span_min := 1.0
	for i in n:
		var a := arcs[i]
		var free := 1.0 - smoothstep(WAVE_FREE_ARC - 20.0, WAVE_FREE_ARC, a)
		var k0 := _bin_lerp(km, a - 0.5)
		var k1 := _bin_lerp(km, a + 0.5)
		var k := _bin_lerp(km, a)
		var dk := k1 - k0
		# junction: back to the full wave (the blend's own slope folded into the derivative)
		var dfree := -(smoothstep(WAVE_FREE_ARC - 20.0, WAVE_FREE_ARC, a + 0.5) - smoothstep(WAVE_FREE_ARC - 20.0, WAVE_FREE_ARC, a - 0.5))
		var kk := lerpf(k, 1.0, free)
		var dkk := dk * (1.0 - free) + (1.0 - k) * dfree
		out[i] = Vector2(kk, dkk)
		if kk < 0.99 and i > 0:
			eased += arcs[i] - arcs[i - 1]
			if span_from < 0.0:
				span_from = a
				span_min = 1.0
			span_min = minf(span_min, kk)
		elif span_from >= 0.0:
			spans += " %.0f-%.0f (%.2f)" % [span_from, a, span_min]
			span_from = -1.0
		kmin = minf(kmin, kk)
	if span_from >= 0.0:
		spans += " %.0f-end (%.2f)" % [span_from, span_min]
	print("PELAGIC creature: swim wave eased on tight bends over %.0f model m, min scale %.2f; arcs:%s" % [eased, kmin, spans])
	return out

static func _min_of(a: PackedFloat32Array) -> float:
	var m := INF
	for v in a:
		m = minf(m, v)
	return m

## Linear interpolation of 1 m bins at arc a (clamped to the ends).
static func _bin_lerp(bins: PackedFloat32Array, a: float) -> float:
	var f := clampf(a, 0.0, float(bins.size() - 1))
	var i := mini(int(f), bins.size() - 2)
	return lerpf(bins[i], bins[i + 1], f - i)

func _build_extension() -> void:
	var inv := global_transform.affine_inverse()
	var s0 := _ext_s0
	var L := float(meta["spine_length"])
	var r0 := GIRTH_HOLD * 1.012     # the mesh's last metres take this same profile at GIRTH_HOLD (no step)
	var pts: Array[Vector3] = [spine_at(s0 - 0.04), spine_at(s0), spine_at(s_cut), spine_at(s_cut) + tangent_at(s_cut) * 14.0]
	for w in extension_world:
		pts.append(inv * w)
	# Catmull-Rom sampling: every ~0.3 model m over the part of the body the path ever sees from closer than ~400 m
	# (its outline stays a smooth curve, no polyline), every ~0.6 model m beyond (only deep fog sees it)
	var t_build := Time.get_ticks_usec()
	var path: Array[Vector3] = []
	var acc := 0.0
	for i in range(1, pts.size() - 1):
		var p0 := pts[i - 1]; var p1 := pts[i]; var p2 := pts[i + 1]; var p3 := pts[mini(i + 2, pts.size() - 1)]
		var step := 0.3 if acc < EXT_FINE_ARC else 0.6
		var steps := maxi(2, int(p1.distance_to(p2) / step))
		acc += p1.distance_to(p2)
		for k in steps:
			var t := float(k) / steps
			path.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	path.append(pts[pts.size() - 2])
	var arcs := PackedFloat32Array()
	arcs.resize(path.size())
	arcs[0] = 0.0
	for i in range(1, path.size()):
		arcs[i] = arcs[i - 1] + path[i].distance_to(path[i - 1])
	var wk := _ext_wave_scale(path, arcs, r0)
	var seg := EXT_SEGMENTS
	var verts := PackedVector3Array(); var norms := PackedVector3Array(); var uv2 := PackedVector2Array(); var tans := PackedFloat32Array()
	var cust := PackedFloat32Array(); var idx := PackedInt32Array()
	var arc := 0.0
	var next_sample := 0.0
	var ring: Array[Vector3] = []
	ring.resize(seg + 1)
	var ca := PackedFloat32Array(); var sa := PackedFloat32Array()
	for j in seg + 1:
		ca.append(cos(-PI + TAU * j / seg)); sa.append(sin(-PI + TAU * j / seg))
	for i in path.size():
		if i > 0: arc += path[i].distance_to(path[i - 1])
		var tg := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var sd := _side(tg)
		var up := sd.cross(tg).normalized()      # world up side: angle 0 is the back (crest), PI the belly
		var s := s0 + arc / L
		var r := ext_radius(arc, r0)
		for j in seg + 1:
			var a := -PI + TAU * j / seg
			var nrm := (up * ca[j] - sd * sa[j]).normalized()
			ring[j] = path[i] + nrm * r * ext_shape(arc, a)
		for j in seg + 1:
			var a := -PI + TAU * j / seg
			var radial := (up * ca[j] - sd * sa[j]).normalized()
			# normal of the shaped ring (crest and oval), not just the radial direction
			var around := ring[mini(j + 1, seg)] - ring[maxi(j - 1, 0)]
			if j == 0 or j == seg:
				around = ring[1] - ring[seg - 1]
			var n := around.cross(tg).normalized()
			if n.dot(radial) < 0.0:
				n = -n
			verts.append(ring[j])
			norms.append(n.lerp(radial, 0.25).normalized())
			tans.append_array([tg.x, tg.y, tg.z, 1.0])
			uv2.append(Vector2(s, wk[i].x))
			cust.append_array([sd.x, sd.z, a, wk[i].y])
		if i > 0:
			var b0 := (i - 1) * (seg + 1); var b1 := i * (seg + 1)
			for j in seg:
				idx.append_array([b0 + j, b0 + j + 1, b1 + j, b0 + j + 1, b1 + j + 1, b1 + j])
		if arc >= next_sample:
			_ext_pts.append(path[i]); _ext_ss.append(s); _ext_r.append(r)
			next_sample += 8.0
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_NORMAL] = norms; arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_CUSTOM0] = cust; arr[Mesh.ARRAY_INDEX] = idx; arr[Mesh.ARRAY_TANGENT] = tans
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = body_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16.0 + (RISE + FLEX_AMP) / creature_scale
	add_child(mi)
	print("PELAGIC creature: extension %d rings x %d segments (%d vertices) in %.0f ms" % [path.size(), seg + 1, verts.size(), (Time.get_ticks_usec() - t_build) / 1000.0])
	var want: Vector3 = inv * PathDef.v3(PathDef.load_layout().get("dark_line_target", [0, -500, -600]))
	var best := 0
	for k in path.size():
		if path[k].distance_squared_to(want) < path[best].distance_squared_to(want):
			best = k
	_line_mid = path[best]
	_line_tan = (path[mini(best + 1, path.size() - 1)] - path[maxi(best - 1, 0)]).normalized()
	var la := 0.0
	for k in range(1, best + 1):
		la += path[k].distance_to(path[k - 1])
	_line_s = s0 + la / L
	_line_marker = Node3D.new()
	_line_marker.name = "T_dark_line"
	get_parent().add_child.call_deferred(_line_marker)
	_line_marker.set_deferred("global_position", global_transform * _line_mid)
	Game.targets["dark_line"] = _line_marker

func _process(delta: float) -> void:
	motion_time += delta
	var pt := Game.path_time
	rise = rise_at(pt)
	global_position = base_pos + heading * drift_speed * (pt - Config.EVENTS["head_turn"]) + Vector3(0.0, -rise, 0.0)
	for r in riders:
		r.position = global_position - base_pos
	amp_scale = amp_scale_at(pt)
	_flex_amp = flex_amp_at(pt) / creature_scale
	_flex_c = _ext_s0 * float(meta["spine_length"]) + flex_arc_at(pt) / creature_scale
	_presence = _measure_presence(pt)
	# no toggle the eye can see: while the whole creature is melted into the far water (< 0.2 % of its own colour
	# survives) it renders as the backdrop, so hiding it then only saves GPU time
	var shown := _presence > 0.002
	if shown != visible:
		visible = shown
		for l in eye_lights:
			l.visible = shown
		for h in _halos:
			h.visible = shown
	if not visible:
		_update_markers()     # gaze/audio targets stay on the body even before it shows
		return
	var ev: Dictionary = Config.EVENTS
	# story: idle -> turn to the player -> hold -> slowly away (a heavy head: low spring frequencies)
	var tgt_yaw := 0.06 * sin(motion_time / 13.0)
	var tgt_pitch := 0.0
	var omega := 0.26
	var gaze_t := 0.3
	if pt >= ev["head_turn"] and pt < ev["head_away"] and head_turn_target:
		var lp := to_local(head_turn_target.global_position)
		var pivot := _v(meta["neck_pivot"])
		var fwd := spine_at(0.0) - spine_at(0.12)
		var to := lp - pivot
		tgt_yaw = clampf(wrapf(atan2(to.x, to.z) - atan2(fwd.x, fwd.z), -PI, PI), -1.0, 1.0)
		tgt_pitch = clampf(-(atan2(to.y, Vector2(to.x, to.z).length()) - atan2(fwd.y, Vector2(fwd.x, fwd.z).length())) * 0.6, -0.2, 0.2)
		omega = 0.3
		gaze_t = 1.0
	elif pt >= ev["head_away"]:
		tgt_yaw = away_yaw
		omega = 0.18
	_gaze = lerpf(_gaze, gaze_t, 1.0 - exp(-delta * 0.9))     # the pupils follow the diver smoothly, no snap
	_yaw_v += (omega * omega * (tgt_yaw - head_yaw) - 2.0 * omega * _yaw_v) * delta
	head_yaw += _yaw_v * delta
	_pitch_v += (omega * omega * (tgt_pitch - head_pitch) - 2.0 * omega * _pitch_v) * delta
	head_pitch += _pitch_v * delta
	var jaw_t := 0.11 if (pt >= ev["jaw_open"] and pt < ev["head_away"] + 10.0) else 0.0
	jaw_extra = lerpf(jaw_extra, jaw_t, 1.0 - exp(-delta * 0.2))
	# eyes: dim while it ignores the diver, waking up through the head turn, strongest in the hold (all ramps, no steps)
	var hold := smoothstep(ev["eye_hold"] - 3.0, ev["eye_hold"] + 2.0, pt) * (1.0 - smoothstep(ev["head_away"], ev["head_away"] + 6.0, pt))
	# after the turn away the eye keeps dimming while the camera lets it go (it leaves the frame at ~458 s)
	_wake = 0.5 + 0.5 * smoothstep(ev["head_turn"] - 4.0, ev["eye_hold"], pt) - 0.2 * smoothstep(ev["head_away"], ev["head_away"] + 20.0, pt) \
		- 0.25 * smoothstep(ev["head_away"] + 18.0, ev["head_away"] + 33.0, pt)
	_eye_glow = EYE_GLOW * _wake * (1.0 + 0.5 * hold)
	mat.set_shader_parameter("eye_glow", _eye_glow)
	mat.set_shader_parameter("eye_lock", hold)
	var hz := haze_at(pt)
	var lk := lock_haze_at(pt)
	var lb := line_boost(pt)
	var rm := rim_melt_at(pt)
	var rg := rim_glow_at(pt)
	var fk := far_k_at(pt)
	var ts := top_scatter_at(pt)
	for m in _mats:
		m.set_shader_parameter("top_scatter", ts)
		m.set_shader_parameter("flex_c", _flex_c)
		m.set_shader_parameter("flex_w", FLEX_W / creature_scale)
		m.set_shader_parameter("flex_amp", _flex_amp)
		m.set_shader_parameter("far_k", fk)
		m.set_shader_parameter("motion_time", motion_time)
		m.set_shader_parameter("amp_tail", undulation_amplitude * amp_scale)
		m.set_shader_parameter("slow_amp", SLOW_AMP * (0.3 + 0.7 * amp_scale / AMP_SETTLED))
		m.set_shader_parameter("haze_k", hz)
		m.set_shader_parameter("line_boost", lb)
		m.set_shader_parameter("rim_melt", rm)
		m.set_shader_parameter("lock_k", lk)
		m.set_shader_parameter("rim_glow", rg)
	body_mat.set_shader_parameter("rise_model", rise / creature_scale)
	if ribbon_mat:
		ribbon_mat.set_shader_parameter("reveal", smoothstep(0.04, 0.3, _head_vis))
	mat.set_shader_parameter("head_yaw", head_yaw)
	mat.set_shader_parameter("head_pitch", head_pitch)
	mat.set_shader_parameter("jaw_angle", jaw_sway * (0.5 + 0.5 * sin(TAU * motion_time / 19.0)) + jaw_extra)
	mat.set_shader_parameter("eye_pulse", 0.5 + 0.5 * sin(TAU * motion_time / 7.0) + hold * 0.6)
	_update_eyes(hold)
	_update_markers()

func _update_eyes(hold: float) -> void:
	var cam := Game.cam_pos()
	var inv := global_basis.inverse()
	var unturn := Basis(Vector3.UP, -head_yaw)
	# the faint light from above (same direction as the old reflection catchlight), in the undeformed head frame
	var light_local := unturn * (inv * (Config.sun_dir_water() + Vector3(0.0, 1.5, 0.0)).normalized()).normalized()
	for i in 2:
		var e: Dictionary = meta["eyes"][i]
		var c := _v(e["center"])
		var rest := _v(e["gaze"]).normalized()
		var world_c := global_transform * deformed(c, 0.0, true)
		var to_cam_world := (cam - world_c).normalized()
		# into the undeformed head frame: undo the node rotation and the head yaw
		var local_dir := (inv * to_cam_world).normalized()
		local_dir = unturn * local_dir
		var look := rest.slerp(local_dir, _gaze * lerpf(0.85, 1.0, hold))
		var lim := lerpf(0.6, 0.85, hold)    # in the hold the pupil may roll further to meet the diver
		if look.angle_to(rest) > lim:
			look = rest.slerp(look, lim / look.angle_to(rest))
		look = look.normalized()
		mat.set_shader_parameter(EYE_LOOK[i], look)
		# the catchlight: the half vector between the camera and the light from above, kept on the cornea (within
		# ~0.35 rad of where the eye looks); unclamped it sat on the upper lid as a separate blob
		var hv := local_dir + light_local
		var catch_dir := look if hv.length_squared() < 1e-8 else hv.normalized()
		var ca := catch_dir.angle_to(look)
		if ca > 0.35:
			catch_dir = look.slerp(catch_dir, 0.35 / ca).normalized()
		mat.set_shader_parameter(EYE_CATCH[i], catch_dir)
		# eyeshine: dull while the eye ignores the diver, lit up as it looks straight at the camera
		_eye_gain[i] = lerpf(1.0, EYE_GAIN, smoothstep(0.86, 0.985, look.dot(local_dir)))
	mat.set_shader_parameter("eye_gain", _eye_gain)

func _update_markers() -> void:
	var e0 := _v(meta["eyes"][0]["center"])
	var e1 := _v(meta["eyes"][1]["center"])
	var cam := Game.cam_pos()
	var ew0 := global_transform * deformed(e0, 0.0, true)
	var ew1 := global_transform * deformed(e1, 0.0, true)
	for i in eye_lights.size():
		var e: Dictionary = meta["eyes"][i]
		var out := Basis(Vector3.UP, head_yaw) * _v(e["gaze"])
		if eye_lights[i].is_inside_tree():
			eye_lights[i].global_position = global_transform * (deformed(_v(e["center"]), 0.0, true) + out * (float(e["radius"]) + 1.2))
			eye_lights[i].light_energy = 1.6 * smoothstep(0.03, 0.3, _head_vis) * _wake
		if i < _halos.size() and _halos[i].is_inside_tree():
			var ew := global_transform * deformed(_v(e["center"]), 0.0, true)
			var to_cam := cam - ew
			var dc := to_cam.length()
			var dir := to_cam / maxf(dc, 1e-3)
			var r_w := float(e["radius"]) * creature_scale
			# a little in front of the eyeball (towards the camera), never past the camera
			_halos[i].global_position = ew + dir * minf(r_w * 1.3, dc * 0.5)
			# only while the eye faces the camera (no glow through the back of the head), scaled like the iris and by
			# the water between the eye and the diver
			var out_w := (global_basis * out).normalized()
			var facing := smoothstep(0.05, 0.45, out_w.dot(dir))
			_halo_mats[i].set_shader_parameter("intensity", HALO_K * _eye_glow * _eye_gain[i] * facing * visibility_at(ew, 0.0))
	if _line_marker and _line_marker.is_inside_tree():
		# the marker holds still (the lateral sway and the flex are left out on purpose): the gaze no longer follows
		# the line's motion and cancels it, so the line visibly moves and bends inside a steady frame
		var lp := _line_mid + Vector3(0.0, ext_rise_model(_line_s), 0.0)
		_line_marker.global_position = global_transform * lp
	if markers.has("eye") and markers["eye"].is_inside_tree():
		markers["eye"].global_position = ew0 if ew0.distance_to(cam) < ew1.distance_to(cam) else ew1
		markers["head"].global_position = global_transform * deformed(spine_at(0.04), 0.0, true)
		markers["neck"].global_position = global_transform * deformed(spine_at(0.22), 0.22, false)
		markers["coils_b5"].global_position = global_transform * deformed(spine_at(0.42), 0.42, false)
		markers["coils_b4"].global_position = global_transform * deformed(spine_at(0.62), 0.62, false)
		markers["creature_body"].global_position = global_transform * deformed(spine_at(0.4), 0.4, false)
