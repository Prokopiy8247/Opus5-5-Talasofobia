class_name Config
## All tunable constants (metres, seconds, degrees).

const SPEED := 2.6                 # default glide speed along the path (m/s)
const BRISK_MULT := 1.8            # Shift
## The cinematic (key C / --autowalk) glides at Shift speed: the whole tuned walk (PathDef speed profile, story
## clock, gaze cues and the camera operator) plays CINEMATIC_MULT times faster, so every framing stays as tuned.
const CINEMATIC_MULT := BRISK_MULT
## Real seconds from the start of play over which the cinematic picks up from 1x to CINEMATIC_MULT: the opening shot
## under the title (the hull crossing Snell's window) keeps its pace while the title is on screen.
const CINEMATIC_RAMP := Vector2(6.0, 12.0)
const ACCEL_TIME := 0.3            # time constant of speed changes
const FOV := 74.0
const TUBE_RADIUS := 10.0          # free drift around the path
const LOOK_SENS := 0.0021          # radians per mouse pixel
const PITCH_LIMIT := 86.0
const LOOK_AHEAD := 18.0           # autowalk looks this far ahead along the path
const LOOK_OMEGA := 0.7            # autowalk critically damped look (rad/s natural frequency)
const LOOK_MAX_RATE := 7.0         # autowalk top angular speed of the view (deg/s)
const LOOK_MAX_ACCEL := 3.0        # autowalk ease-in: angular acceleration limit while speeding up (deg/s^2)
const LOOK_MAX_ROLL := 2.5         # autowalk cap on the image roll that yaw causes in a steep view (deg/s)
const LOOK_MIN_PITCH := -65.0      # gaze cue targets are clamped to this range (degrees); the nadir stays in frame
const LOOK_MAX_PITCH := 62.0
const LOOK_MIN_PITCH_BEHIND := -78.0  # a steep target behind the diver is framed by looking this far down the path
const LOOK_HARD_PITCH := 80.0      # the autowalk view never goes steeper than this
const LOOK_TARGET_TAU := 2.5       # low-pass of moving gaze targets (s): follow a swimming body, not its every wave
const LOOK_FOV_PUSH := -4.0        # eased push-in of the autowalk during the eye lock (degrees, 74 -> 70)
const SWAY_DEG := 0.25             # handheld sway amplitude in autowalk (degrees)

const SUN_ELEVATION := 50.0        # in air; about 61 deg after refraction
const SUN_AZIMUTH := 155.0         # degrees from +Z towards +X: ahead-right of the glide (-Z), so the diver looks into the light
const CAMERA_NEAR := 0.1
const CAMERA_FAR := 6000.0

const FADE_IN := 2.5
const TITLE_HOLD := 4.0
const HINT_TIME := 6.0
const END_FADE := 4.0
const END_HOLD := 3.5              # the final still image holds this long at rest before the fade (~1.5 lamp cycles)
const END_QUIT_DELAY := 2.0        # after the depth line has faded out, the game quits this much later

const CREATURE_SCALE := 7.0

## Story events on the autowalk clock (seconds). Beats and audio react when Game.path_time passes them.
const EVENTS := {
	"hush_line": 236.0,     # sound drops to near silence
	"dark_line": 248.0,     # the dark line is first framed far below
	"flex": 262.0,          # the line flexes: it is alive
	"hush_head": 402.0,     # second near-silence before the head turns
	"head_turn": 407.0,     # head starts turning towards the player (about 7 s)
	"eye_hold": 415.0,      # eyes hold the player for about 5-8 s
	"jaw_open": 416.0,      # jaw opens a little more, long exhale
	"head_away": 423.0,     # head turns slowly away
	"end": 550.0,           # approximate arrival at the marker float
}

## Light absorption per metre (r, g, b) used by shaders (water_common.gdshaderinc) and the sun colour.
const WATER_K := Vector3(0.0048, 0.0021, 0.0010)

static func sun_dir() -> Vector3:
	var el := deg_to_rad(SUN_ELEVATION)
	var az := deg_to_rad(SUN_AZIMUTH)
	return Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)).normalized()

## Sun direction after refraction into the water (Snell), pointing towards the light.
static func sun_dir_water() -> Vector3:
	var s := sun_dir()
	var h := Vector3(s.x, 0.0, s.z).normalized()
	var sin_t := sqrt(1.0 - s.y * s.y) / 1.333
	return (h * sin_t + Vector3(0.0, sqrt(1.0 - sin_t * sin_t), 0.0)).normalized()

static func transmittance(depth: float) -> Vector3:
	var d := maxf(depth, 0.0)
	return Vector3(exp(-WATER_K.x * d), exp(-WATER_K.y * d), exp(-WATER_K.z * d))
