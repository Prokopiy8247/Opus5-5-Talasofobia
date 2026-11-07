class_name Palette
extends RefCounted
## Single source of colour for code and shaders (sRGB tokens).
## push_to_shaders() writes the linear versions into the global shader uniforms pal_*.

const TEAL_NEAR := Color("#3f8f86")
const TEAL_FAR := Color("#1d4d4f")
const DEEP := Color("#07191d")
const MOSS := Color("#2e5a45")
const STEEL_DARK := Color("#2a2f31")
const RUST := Color("#8a4a2b")
const VERDIGRIS := Color("#5f9c8f")
const BONE := Color("#c9d3c4")
const SHAFT := Color("#bfe8d8")
const AMBER := Color("#ffb45a")

const TOKENS := {
	"pal_teal_near": TEAL_NEAR, "pal_teal_far": TEAL_FAR, "pal_deep": DEEP, "pal_moss": MOSS,
	"pal_steel": STEEL_DARK, "pal_rust": RUST, "pal_verdigris": VERDIGRIS, "pal_bone": BONE,
	"pal_shaft": SHAFT, "pal_amber": AMBER,
}


static func lin(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


static func push_to_shaders() -> void:
	for k in TOKENS:
		RenderingServer.global_shader_parameter_set(k, lin(TOKENS[k]))
