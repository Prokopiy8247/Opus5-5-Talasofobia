class_name Config
## All tunable constants, metres / seconds. Depth is POSITIVE metres below the surface (world y = -depth).

const START_DEPTH := 2.5
const FLOOR_DEPTH := 1560.0
const END_DEPTH := 1556.5            # camera stops here, above the hatch

# Beat depth ranges (top, bottom), metres.
const BEATS := {
	1: Vector2(0.0, 80.0),
	2: Vector2(80.0, 330.0),
	3: Vector2(330.0, 720.0),
	4: Vector2(720.0, 960.0),
	5: Vector2(960.0, 1260.0),
	6: Vector2(1260.0, 1560.0),
}

# Movement
const SPEED_SHALLOW := 2.0           # 0..80 m
const SPEED_DEEP := 3.0
const SHALLOW_END := 80.0
const BRISK_MULT := 1.8
const ACCEL_TIME := 0.3
const TUBE_RADIUS := 6.0
const MOUSE_SENS := 0.0022

# Camera
const FOV := 72.0
const NEAR := 0.1
const FAR := 9000.0

# Torch
const TORCH_ON_DEPTH := 245.0
const TORCH_HALF_ANGLE := 27.5      # gaze maths (where the beam reads as "lit")
# Beam profile: a hot core that rolls off smoothly into a faint spill (77% at 10 deg, 33% at 20, 16% at 28,
# 4.5% at 36, 0.8% at 44, 0 at 52) instead of a flat disc with a hard rim. Built from concentric SpotLight3D
# lobes [half angle deg, spot_angle_attenuation, weight] whose sum fits exp(-(theta/22 deg)^1.8) within ~14%
# with small slope breaks at the lobe edges (no visible inner rings); torch_profile() in the shaders evaluates
# exactly the same sum. (A projector texture would need shadows on, too costly here.)
const TORCH_LOBES := [[20.0, 1.0, 0.3287], [30.0, 1.0, 0.1516], [34.0, 0.5, 0.2641], [42.0, 0.5, 0.2170],
	[52.0, 0.6, 0.0437]]
const TORCH_OUTER := 34.0            # where the beam has fallen to ~6% (reference for beats)
const TORCH_SPILL := 52.0            # the widest lobe: the faint spill ends here
const TORCH_RANGE := 82.0


## Pass the beam profile to a shader that has torch_profile() (beam_haze, snow_draw, bubble_draw).
static func apply_torch_profile(m: ShaderMaterial) -> void:
	var c := Vector4.ZERO
	var e := Vector4.ZERO
	var w := Vector4.ZERO
	for i in 4:
		c[i] = cos(deg_to_rad(TORCH_LOBES[i][0]))
		e[i] = TORCH_LOBES[i][1]
		w[i] = TORCH_LOBES[i][2]
	m.set_shader_parameter("lobe_cos", c)
	m.set_shader_parameter("lobe_exp", e)
	m.set_shader_parameter("lobe_w", w)
	var l5: Array = TORCH_LOBES[4]
	m.set_shader_parameter("lobe_5", Vector3(cos(deg_to_rad(l5[0])), l5[1], l5[2]))
const TORCH_ENERGY := 12.0
const HAZE_GAIN := 0.07              # brightness of the light the water scatters out of the beam (BeamHaze)

# The descent line hangs this far from the path (the camera rides the path).
const ROPE_OFFSET := Vector3(-0.25, -0.4, 1.45)
const ROPE_RADIUS := 0.028
const TAG_SPACING := 25.0

# Marine snow
const SNOW_BOX := 40.0
const SNOW_COUNT := 9000

# UI timing
const FADE_IN := 2.5
const TITLE_TIME := 4.2
const HINT_TIME := 6.0
const END_FADE := 4.0
