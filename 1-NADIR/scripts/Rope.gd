extends Node3D
## The descent line (a soft tube along the path at Config.ROPE_OFFSET), the cast-lead weight near the top,
## and the small numbered depth tags every 25 m, each with a band of retro-reflective tape on the line above it
## (a pool recycled around the player). Godot front faces are clockwise: every triangle here is wound that way.

const SIDES := 10
const SEG := 1.25
const TAG_POOL := 10
const ROPE_COL := Color("#4f4636")     # the same literal as the B6 coil (Palette.ROPE is left alone)
const UV_LEN := 0.09                   # metres of line per strand-pattern unit (rope.gdshader)
const TAPE_ABOVE := 0.16               # the tape band sits this far up the line from its tag

var _tags: Array = []
var _tapes: Array = []
var _weight: Node3D
var _shackle: Node3D
var _weight_p := Vector3.ZERO
var _mat: ShaderMaterial               # the line (water_lin is driven every frame)
var _caustic: NoiseTexture2D           # the sun-ray caustic net, shared by the line and the weight
var _near_on := 0.0                    # near-exposure compensation of the line (rope.gdshader near_on)


## Slow sway of the hanging line (world metres). The same curve as rope_sway() in rope.gdshader.
static func sway(depth: float, t: float) -> Vector3:
	var amp := 0.03 * smoothstep(0.0, 10.0, depth) + 0.10 * (1.0 - exp(-depth / 5.0)) * exp(-depth / 35.0)
	amp *= 1.0 - smoothstep(1490.0, 1550.0, depth)
	return amp * Vector3(0.7 * sin(0.105 * depth - 0.70 * t) + 0.3 * sin(0.043 * depth - 0.37 * t + 1.3), 0.0,
		0.7 * sin(0.083 * depth - 0.55 * t + 2.1) + 0.3 * sin(0.031 * depth - 0.29 * t + 4.0))


func build() -> void:
	name = "Rope"
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/rope.gdshader")
	mat.set_shader_parameter("rope_col", ROPE_COL)
	_mat = mat
	_caustic = _caustic_tex()
	mat.set_shader_parameter("caustic_tex", _caustic)
	# The line hangs from the boat (y = +0.2) down to the coil on the floor (beat 6 draws the coil).
	var pts := PackedVector3Array()
	var top := G.path.rope_at(0.0)
	pts.append(Vector3(top.x, 0.25, top.z))
	var s := 0.0
	while s < G.path.length:
		pts.append(G.path.rope_at(s))
		s += SEG
	var last := G.path.rope_at(G.path.length)
	pts.append(Vector3(last.x, -Config.FLOOR_DEPTH + 0.3, last.z))
	# Split into chunks so culling and precision stay sane; the strand pattern runs on across chunk joins.
	var chunk := 160
	var i := 0
	var v0 := 0.0
	while i < pts.size() - 1:
		var j: int = min(i + chunk, pts.size() - 1)
		var mi := MeshInstance3D.new()
		mi.mesh = _tube(pts.slice(i, j + 1), v0)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 0.5   # the shader sways and inflates the tube
		add_child(mi)
		for k in range(i + 1, j + 1):
			v0 += pts[k].distance_to(pts[k - 1]) / UV_LEN
		v0 = fposmod(v0, 100.0)   # whole pattern periods: keeps UV.y small (shader sin precision) and seamless
		i = j
	_build_weight()
	_build_tags()


## The caustic net of the sun rays: identical to Beat01_Surface._build_sun_rays (cellular F2-F1, 256 px, seed 11),
## so the bands on the line and the weight move with the ray sheets around them.
static func _caustic_tex() -> NoiseTexture2D:
	var cn := FastNoiseLite.new()
	cn.noise_type = FastNoiseLite.TYPE_CELLULAR
	cn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cn.fractal_type = FastNoiseLite.FRACTAL_NONE
	cn.frequency = 0.03
	cn.seed = 11
	var rt := NoiseTexture2D.new()
	rt.width = 256
	rt.height = 256
	rt.seamless = true
	rt.generate_mipmaps = true
	rt.noise = cn
	return rt


## Tube along p. UV.x runs around the line, UV.y along it (continuing from v0).
func _tube(p: PackedVector3Array, v0: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := p.size()
	var v := v0
	for k in n:
		var t := (p[min(k + 1, n - 1)] - p[max(k - 1, 0)]).normalized()
		var side := t.cross(Vector3.FORWARD).normalized()
		if side.length() < 0.5:
			side = t.cross(Vector3.RIGHT).normalized()
		var up := side.cross(t).normalized()
		if k > 0:
			v += p[k].distance_to(p[k - 1]) / UV_LEN
		for a in SIDES + 1:
			var ang := TAU * float(a) / SIDES
			var nrm := side * cos(ang) + up * sin(ang)
			st.set_normal(nrm)
			st.set_uv(Vector2(float(a) / SIDES, v))
			st.add_vertex(p[k] + nrm * Config.ROPE_RADIUS)
	# Clockwise seen from outside (the ring turns from side to up, i.e. clockwise around t).
	for k in n - 1:
		for a in SIDES:
			var i0 := k * (SIDES + 1) + a
			var i1 := i0 + SIDES + 1
			st.add_index(i0)
			st.add_index(i0 + 1)
			st.add_index(i1)
			st.add_index(i0 + 1)
			st.add_index(i1 + 1)
			st.add_index(i1)
	return st.commit()


func _build_weight() -> void:
	# A cast-lead clump hanging on the line below the start: "the line and its weight below".
	var p := G.path.rope_at(G.path.s_at_depth(17.0))
	_weight_p = p
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/lead.gdshader")
	mat.set_shader_parameter("caustic_tex", _caustic)
	var m := MeshInstance3D.new()
	m.mesh = _lead_mesh()
	m.material_override = mat
	m.position = p
	m.rotation.y = 0.7
	add_child(m)
	_weight = m
	var shackle := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.035
	tor.outer_radius = 0.075
	tor.rings = 24
	tor.ring_segments = 10
	shackle.mesh = tor
	shackle.material_override = mat
	shackle.position = p + Vector3(0, 0.33, 0)
	shackle.rotation_degrees = Vector3(90, 0, 0)
	add_child(shackle)
	_shackle = shackle


## Lathe of a hand-cast sinker: flat base with a 4 mm bevel, gently tapering sides, a tight rounded shoulder,
## a slightly domed top with a small boss for the shackle eye, and a few % of casting irregularity and dings
## so it is not a perfect CG frustum (more reads as a soft lump at arm's length).
func _lead_mesh() -> ArrayMesh:
	const SEGS := 24
	var prof := [
		Vector2(0.0, -0.275), Vector2(0.214, -0.275), Vector2(0.2185, -0.2735), Vector2(0.220, -0.271),
		Vector2(0.214, -0.15), Vector2(0.204, -0.03), Vector2(0.193, 0.09), Vector2(0.181, 0.19),
		Vector2(0.174, 0.232), Vector2(0.167, 0.252), Vector2(0.155, 0.265), Vector2(0.137, 0.2725),
		Vector2(0.105, 0.2765), Vector2(0.045, 0.2795), Vector2(0.039, 0.2835), Vector2(0.0, 0.2845),
	]
	var rings := prof.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rings:
		var pr: Vector2 = prof[j]
		for i in SEGS:
			var th := TAU * float(i) / SEGS
			var dent := 0.022 * sin(3.0 * th + 11.0 * pr.y + 0.7) * cos(2.0 * th - 5.0 * pr.y)
			if j >= 4 and j <= 10:
				dent += 0.012 * (_hash2(i, j) * 2.0 - 1.0)
				# two dings where it has knocked against things
				dent -= 0.05 * exp(-pow(wrapf(th - 1.1, -PI, PI) / 0.22, 2.0) - pow((pr.y + 0.02) / 0.07, 2.0))
				dent -= 0.035 * exp(-pow(wrapf(th - 4.0, -PI, PI) / 0.18, 2.0) - pow((pr.y - 0.14) / 0.05, 2.0))
			var r := pr.x * (1.0 + dent)
			st.add_vertex(Vector3(r * cos(th), pr.y, r * sin(th)))
	# Clockwise from outside: (A, B, C) and (B, D, C) with A=(j,i), B=(j,i+1), C=(j+1,i), D=(j+1,i+1).
	for j in rings - 1:
		for i in SEGS:
			var a := j * SEGS + i
			var b := j * SEGS + (i + 1) % SEGS
			var c := a + SEGS
			var d := b + SEGS
			if (prof[j] as Vector2).x > 0.0:
				st.add_index(a)
				st.add_index(b)
				st.add_index(c)
			if (prof[j + 1] as Vector2).x > 0.0:
				st.add_index(b)
				st.add_index(d)
				st.add_index(c)
	st.generate_normals()
	return st.commit()


static func _hash2(i: int, j: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + float(j) * 78.233) * 43758.5453, 1.0)


func _build_tags() -> void:
	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.52, 0.51, 0.47)  # scuffed pale plastic: readable, under the ~200 sRGB ceiling face-on in the torch
	plate_mat.roughness = 0.62
	plate_mat.rim_enabled = true                      # faint fresnel edge so the plate separates from the water
	plate_mat.rim = 0.25
	plate_mat.rim_tint = 0.4
	var tape_mat := ShaderMaterial.new()
	tape_mat.shader = load("res://shaders/retro_tape.gdshader")
	var tape_mesh := CylinderMesh.new()
	tape_mesh.top_radius = 0.034
	tape_mesh.bottom_radius = 0.034
	tape_mesh.height = 0.14
	tape_mesh.radial_segments = 10
	tape_mesh.rings = 1   # end caps stay on: seen end-on down the line the collar still shows a face
	for k in TAG_POOL:
		var root := Node3D.new()
		var plate := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.17, 0.075, 0.008)
		plate.mesh = bm
		plate.material_override = plate_mat
		root.add_child(plate)
		var lbl := Label3D.new()
		lbl.font_size = 64
		lbl.pixel_size = 0.00072
		lbl.modulate = Color(0.1, 0.11, 0.12)
		lbl.outline_size = 0
		lbl.shaded = true
		lbl.double_sided = true
		lbl.position = Vector3(0, 0, 0.0065)
		root.add_child(lbl)
		var lbl2 := lbl.duplicate()
		lbl2.position = Vector3(0, 0, -0.0065)
		lbl2.rotation_degrees = Vector3(0, 180, 0)
		root.add_child(lbl2)
		add_child(root)
		_tags.append(root)
		var tape := MeshInstance3D.new()
		tape.mesh = tape_mesh
		tape.material_override = tape_mat
		tape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tape.extra_cull_margin = 0.5   # the shader inflates the band with distance
		add_child(tape)
		_tapes.append(tape)


func _process(dt: float) -> void:
	if G.player == null:
		return
	# Near-exposure compensation follows the torch being on: on at once with the click, and after the torch dies
	# it eases off over 3 s (the eye re-adapting), so lamp light on the line never pops.
	var lit: bool = float(G.player.get("torch_out")) > 0.002 if "torch_out" in G.player else false
	_near_on = 1.0 if lit else move_toward(_near_on, 0.0, dt / 3.0)
	_mat.set_shader_parameter("near_on", _near_on)
	# The line answers the (eye-adapted) water light around it in the lit zone: never a black cut-out in the blue.
	var w: Color = (G.env.fog_light_color if G.env else Palette.water_at(G.depth)).srgb_to_linear()
	_mat.set_shader_parameter("water_lin", Vector3(w.r, w.g, w.b) * (1.0 - smoothstep(330.0, 520.0, G.depth)))
	# The weight and shackle ride the swaying line.
	var ws := sway(-_weight_p.y, G.t)
	_weight.position = _weight_p + ws
	_shackle.position = _weight_p + Vector3(0, 0.33, 0) + ws
	var base := int(floor(G.depth / Config.TAG_SPACING)) - 3
	for k in TAG_POOL:
		var d := float(base + k) * Config.TAG_SPACING
		var tag: Node3D = _tags[k]
		var tape: Node3D = _tapes[k]
		if d < Config.TAG_SPACING or d > Config.FLOOR_DEPTH - 5.0:
			tag.visible = false
			tape.visible = false
			continue
		tag.visible = true
		tape.visible = true
		var sd := G.path.s_at_depth(d)
		var p := G.path.rope_at(sd)
		# The tag hangs just off the line, its face turned toward the path (where the diver is).
		var to_path := (G.path.pos_at(sd) - p)
		to_path.y = 0.0
		var yaw := atan2(to_path.x, to_path.z)
		p += sway(-p.y, G.t)
		tag.position = p + to_path.normalized() * 0.045 + Vector3(0, -0.02, 0)
		tag.rotation = Vector3(0, yaw, 0.06 * sin(G.t * 0.4 + d))
		# The tape is wrapped round the line itself, so it follows the line's direction, not the tag's swing.
		var tan := G.path.tangent_at(sd)
		tape.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, -tan)), p - tan * TAPE_ABOVE)
		var txt := "%d m" % int(d)
		if tag.get_meta("txt", "") != txt:
			tag.set_meta("txt", txt)
			for c in tag.get_children():
				if c is Label3D:
					c.text = txt
