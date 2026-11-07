class_name Palette
## Colour tokens (sRGB). Single source for scripts; shaders receive them as uniforms.

const SURF_TURQ := Color("#2aa7d0")    # 0 m: an open-ocean cerulean (was a lagoon turquoise)
const BLUE_CLEAR := Color("#0a56b3")   # reached by ~70 m, held to 100 m
const BLUE_DEEP := Color("#0a2a6e")    # ~250 m
const INDIGO := Color("#071440")       # ~500 m
const ABYSS := Color("#02060f")        # far below everything
const SUN := Color("#fff4dc")
const REEF_DARK := Color("#2b3a3f")
const REEF_WARM := Color("#c8774a")
const SAND := Color("#d9c7a0")
const SERPENT_OLIVE := Color("#5b6350")
const SERPENT_DARK := Color("#262c26")
const FLUID := Color("#2f3a3d")
const EYE_CYAN := Color("#4ff0e0")
const MARKER_ORANGE := Color("#ff7a1a")

## Backdrop (horizontal far-water) colour at a depth in metres (positive down).
## Mirrors wb_water_col() in shaders/water_backdrop.gdshaderinc (which blends in linear space).
static func water_at(depth: float) -> Color:
	var d := maxf(depth, 0.0)
	if d < 100.0:
		return SURF_TURQ.lerp(BLUE_CLEAR, smoothstep(0.0, 70.0, d))
	if d < 250.0:
		return BLUE_CLEAR.lerp(BLUE_DEEP, smoothstep(100.0, 250.0, d))
	if d < 500.0:
		return BLUE_DEEP.lerp(INDIGO, smoothstep(250.0, 500.0, d))
	return INDIGO.lerp(ABYSS, smoothstep(500.0, 900.0, d))
