class_name Config
extends RefCounted
## All constants in metres / seconds. y = 0 is the sea surface, depth is negative y. Forward is -Z.

# --- movement -------------------------------------------------------------------------------
const SPEED := 2.75              # default walk speed along the line (m/s)
const BRISK := 1.8               # Shift multiplier
const ACCEL_TIME := 0.3
const TUBE_RADIUS := 8.0
const FOV := 63.0              # vertical; cues push in further for the money shots
const MOUSE_SENS := 0.0022

# --- the descent line (path control points, Catmull-Rom) -------------------------------------
const PATH_POINTS: Array[Vector3] = [
	Vector3(0, -3.5, 30), Vector3(1, -8, -5), Vector3(-3, -15, -45), Vector3(0, -27, -85),
	Vector3(8, -58, -130), Vector3(12, -100, -175), Vector3(5, -150, -215), Vector3(-5, -200, -250),
	Vector3(-6, -255, -282),
	Vector3(0, -318, -305), Vector3(10, -385, -335), Vector3(8, -452, -370), Vector3(0, -515, -410),
	Vector3(25, -565, -440), Vector3(60, -625, -470), Vector3(115, -700, -500), Vector3(170, -762, -532),
	Vector3(252, -812, -604), Vector3(248, -896, -714),
	Vector3(196, -969, -850), Vector3(170, -982.0, -925.5),
]
# index of the control point where each beat starts (beat 1..6)
const BEAT_START_POINT := [0, 3, 8, 12, 16, 18]
const BEAT6_S := 1424.0                         # the door beat starts here (between points 18 and 19)
const BEAT_NAMES := ["Shallows", "Hulls", "Forest", "Statue", "Wall", "Door"]
const ROPE_OFFSET := Vector3(-1.3, -1.6, 0.0)   # rope relative to the walker, in path frame (right, up, fwd)
const TAG_EVERY := 25.0

# --- world layout ---------------------------------------------------------------------------
const SURFACE_Y := 0.0
const FLOOR_DEEP := -985.0                       # basin floor (statue, wall foot, door)
const FOREST_FLOOR := -790.0                     # plateau the submarines stand on
const STATUE_ORIGIN := Vector3(-40, -985, -770)  # between the knees on the floor, statue faces +Z
const STATUE_SCALE := 1.0
const WALL_Z := -940.0                           # the wall plane (faces +Z), ~10 m behind the statue's heels
const DOOR_POS := Vector3(170, -985, -934)       # foot of the door, on the (curved) wall

# focus points shared by the builders and the choreography (world space)
const BOAT_POS := Vector3(-3, 0.0, 37)
const F_DEBRIS := Vector3(8, -15, -32)          # beat 1 cluster: rowboat, anchor, crates
# Beat-2 wrecks (Terrain.ship_pose carves their sediment beds and returns the resting pose): pos = keel centre
# (x, z; y is derived), yaw of the bow (deg, bow = local -Z), heel = extra roll (deg) on top of `follow` x the
# cross-slope, cut = how much of the bed is cut into the slope (0..1), sink = burial (fraction of the depth).
const SHIP_TRAWLER := {"pos": Vector3(40, 0, -114), "yaw": 256.0, "heel": 0.0, "length": 40.0, "follow": 0.7, "cut": 0.3, "sink": 0.16, "fill": 0.42}
const SHIP_CARGO := {"pos": Vector3(-82, 0, -176), "yaw": 95.0, "heel": 0.0, "length": 120.0, "follow": 0.7, "cut": 0.3, "sink": 0.15, "fill": 0.42}
const SHIP_TANKER := {"pos": Vector3(195, 0, -229), "yaw": 88.0, "heel": 0.0, "length": 300.0, "follow": 0.6, "cut": 0.3, "sink": 0.14}
const SHIP_LINER := {"pos": Vector3(-345, 0, -240), "yaw": 92.0, "heel": 0.0, "length": 600.0, "follow": 0.62, "cut": 0.45, "sink": 0.12}
const SHIP_SMALL := {"pos": Vector3(-60, 0, -281), "yaw": 97.0, "heel": 0.0, "length": 26.0, "follow": 0.5, "cut": 0.3, "sink": 0.18, "fill": 0.42}
const STATUE_FACE := Vector3(-40, -588, -647)     # Statue.FACE_CENTER in world space
const STATUE_PALM := Vector3(71, -786, -500)      # palm centre + 20 m toward the fingertips

# --- fog / light ----------------------------------------------------------------------------
const FOG_DENSITY_SHALLOW := 0.0125
const FOG_DENSITY_DEEP := 0.0024
const FOG_BAND_GAIN := 1.0
# horizontal fog bands: centre depth, half-width (sigma), extra density
const BANDS := [
	[-42.0, 7.0, 0.020], [-150.0, 12.0, 0.022], [-262.0, 14.0, 0.020], [-385.0, 16.0, 0.016],
	[-520.0, 18.0, 0.013], [-650.0, 20.0, 0.011], [-780.0, 22.0, 0.010], [-905.0, 20.0, 0.010],
]
const SUN_DIR := Vector3(0.18, -1.0, -0.22)      # direction the sunlight travels
const EXPOSURE := 1.0
# colour grade per beat (post.gdshader): each beat colder and darker than the last, warm lights protected
const GRADE := [
	{"g_tint": Vector3(1.0, 1.0, 1.0), "g_lift": 0.0, "g_gain": 1.0, "g_gamma": 1.0, "g_contrast": 1.0, "g_sat": 1.05},
	{"g_tint": Vector3(0.97, 1.02, 0.98), "g_lift": -0.004, "g_gain": 1.0, "g_gamma": 1.0, "g_contrast": 1.05, "g_sat": 1.0},
	{"g_tint": Vector3(0.9, 0.98, 1.06), "g_lift": -0.012, "g_gain": 0.98, "g_gamma": 0.97, "g_contrast": 1.12, "g_sat": 0.88},
	{"g_tint": Vector3(0.93, 0.98, 1.03), "g_lift": -0.016, "g_gain": 0.95, "g_gamma": 0.96, "g_contrast": 1.15, "g_sat": 0.76},
	{"g_tint": Vector3(0.93, 0.97, 1.03), "g_lift": -0.018, "g_gain": 0.97, "g_gamma": 0.96, "g_contrast": 1.15, "g_sat": 0.8},
	{"g_tint": Vector3(0.96, 0.97, 1.0), "g_lift": -0.018, "g_gain": 0.97, "g_gamma": 0.96, "g_contrast": 1.12, "g_sat": 0.85},
]
const LAMP_ON_S := 441.0                          # the diver switches the lamp on at the cliff edge

# --- harness --------------------------------------------------------------------------------
const HARNESS_MSAA := 1          # 2x during test runs (Viewport.MSAA_2X)
