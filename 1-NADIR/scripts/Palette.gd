class_name Palette
## Colour tokens (sRGB). The single source of colour for code; shaders receive them as uniforms.

const SURF_TEAL := Color("#2f8f93")   # near surface
const BLUE_MID := Color("#0e3b66")    # ~100 m
const BLUE_DEEP := Color("#04101c")   # ~300 m
const VOID := Color("#01040a")        # abyss
const TORCH := Color("#cfe8ff")       # cold white torch
const ROPE := Color("#857558")       # weathered line: the torch at arm's length must not blow it out
const STEEL := Color("#3b2a22")       # dark rusted steel
const ALGAE := Color("#1c2a22")
const BARNACLE := Color("#8c7f6e")
const AMBER := Color("#ffb45a")       # the ONLY warm colour: final lamps, emissive

# Water (fog / backdrop) colour keys by depth in metres. The deep keys lean cold navy, not grey-green.
const WATER_KEYS := [
	[0.0, Color("#3a9a98")],
	[25.0, Color("#2f8f93")],
	[80.0, Color("#16507a")],
	[110.0, Color("#0e3b66")],
	[200.0, Color("#05173a")],
	[300.0, Color("#020916")],
	[520.0, Color("#01050c")],
	[800.0, Color("#01040a")],
]

## Eye adaptation (written by WaterEnv every frame): linear scale of every water colour the eye sees, 1 = dark-
## adapted, 0.5 = adapted to the torch. water_at() applies it, so it always agrees with G.env.fog_light_color (the
## one water colour) and a consumer that still calls water_at() never glows against the adapted backdrop.
static var adapt_k := 1.0


## The water colour as the eye sees it now (eye-adapted). Same as G.env.fog_light_color at the camera depth.
static func water_at(depth: float) -> Color:
	var c := _keyed(WATER_KEYS, depth)
	if adapt_k >= 0.9999:
		return c
	var l := c.srgb_to_linear()
	return Color(l.r * adapt_k, l.g * adapt_k, l.b * adapt_k).linear_to_srgb()


## The palette water colour before eye adaptation (WaterEnv only).
static func water_base_at(depth: float) -> Color:
	return _keyed(WATER_KEYS, depth)

## Light is absorbed exponentially with depth: interpolate linear-light values in log space with a linear f,
## so the colour drains at a steady rate (no stall at each key and surge between keys).
static func _keyed(keys: Array, x: float) -> Color:
	if x <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if x <= keys[i][0]:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var f: float = (x - a[0]) / (b[0] - a[0])
			var ca: Color = (a[1] as Color).srgb_to_linear()
			var cb: Color = (b[1] as Color).srgb_to_linear()
			return Color(_log_lerp(ca.r, cb.r, f), _log_lerp(ca.g, cb.g, f), _log_lerp(ca.b, cb.b, f)).linear_to_srgb()
	return keys[keys.size() - 1][1]

static func _log_lerp(a: float, b: float, f: float) -> float:
	return maxf(exp(lerpf(log(a + 1e-4), log(b + 1e-4), f)) - 1e-4, 0.0)
