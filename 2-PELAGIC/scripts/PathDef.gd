class_name PathDef
## The single fixed path (Curve3D from assets/layout.json), its speed profile, the time<->distance table,
## beat boundaries and the autowalk gaze cues.

const LAYOUT := "res://assets/layout.json"
## Beat start times on the autowalk clock (seconds).
const BEATS := {"b1": 0.0, "b2": 35.0, "b3": 150.0, "b4": 240.0, "b5": 330.0, "b6": 450.0}

static var layout := {}
static var curve: Curve3D
static var length := 0.0
static var _dist := PackedFloat32Array()   # sampled distance (every STEP m)
static var _time := PackedFloat32Array()   # autowalk time at that distance
static var _mult := PackedFloat32Array()   # speed multiplier at that distance
const STEP := 1.0

static func load_layout() -> Dictionary:
	if layout.is_empty():
		var f := FileAccess.open(LAYOUT, FileAccess.READ)
		layout = JSON.parse_string(f.get_as_text())
	return layout

static func v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

static func build() -> Curve3D:
	load_layout()
	var wps: Array = layout["waypoints"]
	curve = Curve3D.new()
	curve.bake_interval = 0.5
	var n := wps.size()
	for i in n:
		var p := v3(wps[i][0])
		var prev := v3(wps[maxi(i - 1, 0)][0])
		var next := v3(wps[mini(i + 1, n - 1)][0])
		var h := (next - prev) / 6.0
		curve.add_point(p, -h if i > 0 else Vector3.ZERO, h if i < n - 1 else Vector3.ZERO)
	length = curve.get_baked_length()
	# speed multiplier per waypoint, interpolated by distance
	var wd := PackedFloat32Array()
	for i in n:
		wd.append(curve.get_closest_offset(v3(wps[i][0])))
	var count := int(length / STEP) + 2
	_dist.resize(count); _time.resize(count); _mult.resize(count)
	var t := 0.0
	var k := 0
	for j in count:
		var d := minf(j * STEP, length)
		while k < n - 2 and d > wd[k + 1]:
			k += 1
		var a := clampf((d - wd[k]) / maxf(wd[k + 1] - wd[k], 0.001), 0.0, 1.0)
		a = a * a * (3.0 - 2.0 * a)
		var m := lerpf(float(wps[k][1]), float(wps[k + 1][1]), a)
		_dist[j] = d; _mult[j] = m; _time[j] = t
		t += STEP / (Config.SPEED * maxf(m, 0.05))
	print("PELAGIC path: %.0f m, autowalk %.0f s (%d:%02d)" % [length, total_time(), int(total_time()) / 60, int(total_time()) % 60])
	return curve

static func speed_mult(d: float) -> float:
	var j := clampi(int(d / STEP), 0, _mult.size() - 2)
	return lerpf(_mult[j], _mult[j + 1], clampf(d / STEP - j, 0.0, 1.0))

static func time_at(d: float) -> float:
	var j := clampi(int(d / STEP), 0, _time.size() - 2)
	return lerpf(_time[j], _time[j + 1], clampf(d / STEP - j, 0.0, 1.0))

static func dist_at(t: float) -> float:
	var lo := 0
	var hi := _time.size() - 1
	if t <= 0.0:
		return 0.0
	if t >= _time[hi]:
		return length
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _time[mid] <= t: lo = mid
		else: hi = mid
	return lerpf(_dist[lo], _dist[hi], (t - _time[lo]) / maxf(_time[hi] - _time[lo], 0.0001))

static func total_time() -> float:
	return _time[_time.size() - 1]

static func point(d: float) -> Vector3:
	return curve.sample_baked(clampf(d, 0.0, length), true)

static func point_at_time(t: float) -> Vector3:
	return point(dist_at(t))

static func tangent(d: float) -> Vector3:
	var a := point(d - 1.0)
	var b := point(d + 1.0)
	return (b - a).normalized()

## Gaze cues for the cinematic autowalk. Times on the autowalk clock: ramp in t0->t1, hold, ramp out t2->t3.
## target: Vector3 world point, String key into Game.targets, or {"rel": Vector3} relative to the player
## (a fixed direction). "w" is the maximum blend weight (0..1) away from looking ahead along the path; optional
## "lift" raises (or lowers) the aim above the target in degrees; optional "az_out" [t2, t3] gives the azimuth pull its
## own (later) ramp-out, so the view can first tilt away from a subject and turn only afterwards (the subject then leaves
## through the top or bottom edge, the nearest one, instead of a corner). Consecutive cues overlap so the gaze passes from
## one subject straight to the next instead of returning to the path in between; ramps are long enough that the
## operator (Player._autowalk_look) rarely needs its speed cap.
static func cues() -> Array:
	# the last look: a fixed point in the deep beyond the marker float, so the gaze stays steady while the diver
	# sinks to the float's level and glides to rest (Player.END_GLIDE); the float rises into the upper third and
	# settles there (about +0.4 of the half-height above the centre at rest), the endless body stays in the lower
	# third. Full weight: at rest the view is exactly this direction, not pulled towards the steep path tangent.
	# The aim sits low enough that a strip of open water shows under the body band at rest (the body reads as a body
	# passing beneath, not as a hill or a horizon), while the float stays in the upper third.
	var tg := tangent(length - 1.0)
	var aim := point(length) + Vector3(tg.x, 0.0, tg.z).normalized() * 44.5 + Vector3(0.0, -24.0, 0.0)
	return [
		# b1: looking up towards the surface and the sun; the dark hull crosses Snell's window under the title
		{"t": [0.0, 0.0, 7.0, 22.0], "target": {"rel": Vector3(8.7, 55.2, -82.9)}, "w": 0.95},
		# ... then down the anchor line to the reef top and the edge of the wall
		{"t": [9.0, 24.0, 28.0, 37.0], "target": {"rel": Vector3(-14, -9, -12)}, "w": 0.5},
		# b2: the wall, the sardine curtain overhead, a look down the face
		{"t": [38.0, 47.0, 56.0, 66.0], "target": "wall_look_1", "w": 0.55},
		# the M1 bait ball: a slow tilt up towards it while it climbs the upper half of the frame; the operator follows
		# it only part of the way (w 0.45), so it is still tilting up when the ball slides out over the top edge
		# (~96 s, at ~3 deg/s relative), then eases back down to the lip prow ahead (settled ~109 s)
		{"t": [72.0, 83.0, 95.0, 105.0], "target": "school_m1", "w": 0.45, "lift": 3.0},
		{"t": [112.0, 121.0, 127.0, 137.0], "target": {"rel": Vector3(-6, -40, -12)}, "w": 0.6},
		# b3: under the lip, up and ahead-right: the dark roof above, its broken rim against the light beyond ...
		{"t": [136.0, 150.0, 157.0, 177.0], "target": {"rel": Vector3(15, 22.5, -42)}, "w": 0.85},
		# ... straight down into the open abyss as the wall ends ...
		{"t": [159.0, 186.0, 194.0, 207.0], "target": {"rel": Vector3(-20, -100, -40)}, "w": 0.9},
		# ... and one long look up at the shrinking light (the sun glow, the last rays) before the hush
		{"t": [199.0, 220.0, 225.0, 240.0], "target": {"rel": Vector3(26, 72, -62)}, "w": 0.78},
		# b4: the dark line far below, then the coils
		{"t": [231.0, 258.0, 276.0, 293.0], "target": "dark_line", "w": 0.9},
		{"t": [282.0, 304.0, 324.0, 339.0], "target": "coils_b4", "w": 0.6},
		# b5: the coils hand the gaze to the neck, the neck to the eye (with the eased FOV push-in of fov_push())
		{"t": [326.0, 340.0, 360.0, 373.0], "target": "coils_b5", "w": 0.65},
		{"t": [360.0, 373.0, 394.0, 405.0], "target": "neck", "w": 0.65},
		# the eye at about the frame centre: the camera is at the eye's height ~90 m away, so the open jaw needs the
		# room below it (a higher aim only adds empty water above the skull and crops the jaw at FOV 70)
		# The camera does not end the lock: it stays on the eye while the head turns away and the eye dims, then lets
		# go slowly (at most ~3 deg/s, look_rate()) and in order: the view first tilts down towards the deep it is sinking
		# into while it still keeps the eye's bearing, so the head rises out over the top edge (~458 s, ~38 deg off axis)
		# instead of being dragged into a corner, where the wide-angle stretch would enlarge the still-glowing eye; only
		# then does it turn to the path (az_out).
		{"t": [394.0, 407.0, 440.0, 462.0], "az_out": [452.0, 480.0], "target": "eye", "w": 0.9, "lift": 0.0},
		# b6: down into the deep blue (the path itself dives here, so this only deepens the look a little), then the
		# marker float with the endless body passing beneath it
		{"t": [458.0, 476.0, 482.0, 494.0], "target": {"rel": Vector3(30, -100, -40)}, "w": 0.3},
		{"t": [480.0, 500.0, 600.0, 610.0], "target": aim, "w": 1.0},
	]

## Eased FOV push-in of the autowalk (degrees added to Config.FOV): 74 -> 70 while the eye holds the diver; it eases
## out with the release of the eye cue.
static func fov_push(t: float) -> float:
	var k := smoothstep(400.0, 430.0, t) * (1.0 - smoothstep(444.0, 470.0, t))
	return Config.LOOK_FOV_PUSH * k

## Small additive pitch offsets of the autowalk gaze (degrees, + = up), eased in and out: at the breath release after
## the dark-line hush (bubbles at ~254 s) the operator lifts the view a little, almost stopping its slow tilt down,
## so the rising bubbles cross the frame instead of leaving it at once. The dark line stays framed.
static func look_nudge(t: float) -> float:
	return 3.5 * smoothstep(248.0, 252.5, t) * (1.0 - smoothstep(253.5, 258.0, t))

## Top angular speed of the autowalk operator (deg/s): Config.LOOK_MAX_RATE, except for the long hand-off from the eye
## to the deep (a slow tilt down, then the turn to the path: ~75 degrees in all), which is held to a calm 3.2 deg/s.
static func look_rate(t: float) -> float:
	var k := smoothstep(434.0, 440.0, t) * (1.0 - smoothstep(490.0, 496.0, t))
	return lerpf(Config.LOOK_MAX_RATE, 3.2, k)
