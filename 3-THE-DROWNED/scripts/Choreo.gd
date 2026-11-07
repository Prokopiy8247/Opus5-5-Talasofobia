class_name Choreo
extends RefCounted
## Cinematic autowalk choreography: speed easing (slower at reveals, quicker through empty water), gaze
## cues per beat with optional slow push-ins (narrower field of view), and a camera drift off the line.
## The autowalk is a fixed timeline t -> s precomputed from the speed profile, so --start-at is exact.
## Consecutive cues overlap their fades (no gap where the gaze would fall back to the plain heading).

# [centre s, half width, speed multiplier]
const SPEED_ZONES := [
	[60.0, 50.0, 0.92], [185.0, 20.0, 1.25], [255.0, 30.0, 1.1], [340.0, 32.0, 0.68], [395.0, 22.0, 0.85],
	[470.0, 18.0, 1.2], [520.0, 45.0, 1.3], [612.0, 42.0, 0.78], [690.0, 30.0, 1.0], [760.0, 30.0, 0.9],
	[870.0, 45.0, 0.66], [1005.0, 42.0, 0.68], [1100.0, 45.0, 0.62], [1165.0, 35.0, 0.75], [1265.0, 50.0, 1.3],
	[1360.0, 45.0, 1.4], [1469.0, 35.0, 1.3], [1524.0, 22.0, 0.7],
]

const Wall := preload("res://scripts/beats/Beat05_Wall.gd")

## The cinematic autowalk (C) moves on average as fast as the diver swims with Shift (Config.SPEED x BRISK);
## the speed zones keep its relative pacing (slower at the reveals, quicker through empty water).
const PACE := Config.SPEED * Config.BRISK
const REF_TIME := 552.0       # the 9:12 pacing the gaze cues and timed effects were first tuned at
const HEAD_TURN_S := 872.0    # the statue's head turns toward the diver here (Main), unless seen earlier

var path: PathDef
var cues: Array = []          # {s0, s1, fade, target: Vector3, fov}
var t_tab := PackedFloat32Array()
var s_tab := PackedFloat32Array()
var total_time := 0.0
var pace_ratio := 1.0         # REF_TIME / total_time: how much faster than the original pacing (time-based effects scale by it)
var _time_k := 1.0            # timeline seconds per second of the raw speed profile


func _init(p: PathDef) -> void:
	path = p
	_define_cues()
	_build_table()
	if OS.is_debug_build():
		_check_gaps()


func add_cue(s0: float, s1: float, target: Vector3, fade := 18.0, fov := 0.0) -> void:
	cues.append({"s0": s0, "s1": s1, "fade": fade, "target": target, "fov": fov if fov > 0.0 else Config.FOV})


## A point above the seabed under a ship's Config placement (decks rest on the slope).
func _ship(d: Dictionary, up: float, off := Vector3.ZERO) -> Vector3:
	var p: Vector3 = d["pos"] + off
	return Vector3(p.x, Terrain.height(p.x, p.z) + up, p.z)


func _define_cues() -> void:
	var face := Config.STATUE_FACE
	# beat 1: look back up at the dive boat in Snell's window, the light ahead, the debris, the last daylight
	add_cue(-20.0, 7.0, Config.BOAT_POS + Vector3(0, -1.0, 5.0), 8.0)
	add_cue(9.0, 28.0, Vector3(0, 4, -45), 9.0)
	add_cue(34.0, 62.0, Config.F_DEBRIS, 12.0)
	add_cue(76.0, 98.0, Vector3(14, 0, -75), 12.0)
	# beat 2: each ship dwarfs the last (targets measured on the placed hulls, Terrain.ship_pose); decks
	# lean downslope, so the gaze takes sterns and bows first and the decks once the diver is level with them
	add_cue(108.0, 183.0, Vector3(21, -59, -120), 14.0)                                 # trawler gallows
	add_cue(196.0, 226.0, Vector3(-22, -126, -184), 14.0)                               # cargo stern
	add_cue(226.0, 250.0, Vector3(-82, -119, -182), 12.0)                               # cargo midship
	add_cue(262.0, 302.0, Vector3(59, -187, -249), 14.0)                                # tanker bow, chain
	add_cue(310.0, 362.0, Vector3(-240, -182, -272), 16.0, 56.0)                        # M1 along the liner (600 m)
	add_cue(364.0, 418.0, Vector3(-60, -202, -272), 14.0, 58.0)                         # its stern looms overhead
	add_cue(432.0, 458.0, path.pos(520.0) + Vector3(70, -240, -20), 14.0)              # over the cliff edge (the line from the side)
	# beat 3: the forest
	add_cue(476.0, 560.0, Vector3(-85, -455, -380), 18.0)                              # between two heroes, at body height
	add_cue(578.0, 645.0, Vector3(245, -425, -400), 20.0, 54.0)                         # M2 a hero hull, bow up
	add_cue(660.0, 714.0, Vector3(-205, -480, -432), 16.0)                              # amber in a sail
	# beat 4: the statue: the bowed face; as the head turns the gaze follows it; down the arm to the palm
	add_cue(730.0, 800.0, face + Vector3(0, -45, 0), 26.0, 68.0)                        # M3 wide: the giant among the hulls
	add_cue(806.0, 890.0, Vector3(-28, -577, -654), 26.0, 54.0)                         # M3 push in as the head turns
	add_cue(925.0, 1030.0, Vector3(58, -786, -512), 34.0, 52.0)                         # M4 the offering (a slow tilt down the arm)
	# beat 5: the diver looks back at the giant as the wall wakes up right behind it (the light wave starts
	# behind its shoulders, Beat05_Wall.WAVE_ORIGIN): its key light fades and it becomes a silhouette (M5);
	# then the wave reaches the stencilled "07" ahead; then up the wall
	add_cue(1040.0, 1112.0, Vector3(-40, -585, -685), 16.0, 60.0)                       # M5
	add_cue(1120.0, 1172.0, Wall.DIGITS_CENTER + Vector3(0, -20, 0), 14.0)            # the wave reaches "07"
	add_cue(1182.0, 1252.0, Vector3(120, -560, Config.WALL_Z + 3.0), 18.0, 66.0)        # up the wall, into the dark
	add_cue(1262.0, 1350.0, Vector3(430, -760, Config.WALL_Z + 37.0), 16.0, 72.0)      # wide along the wall (away from the statue): the far rows die first
	# beat 6: the door
	add_cue(1370.0, 1760.0, Config.DOOR_POS + Vector3(0, 1.4, 0), 30.0, 50.0)


func speed_mult(s: float) -> float:
	var m := 1.0
	for z in SPEED_ZONES:
		var d: float = absf(s - z[0]) / z[1]
		if d < 1.0:
			var w := 0.5 + 0.5 * cos(PI * d)
			m += (z[2] - 1.0) * w
	m *= lerpf(0.35, 1.0, smoothstep(0.0, 10.0, s))
	m *= lerpf(0.45, 1.0, smoothstep(0.0, 14.0, path.length - s))
	return m


func _build_table() -> void:
	var s := 0.0
	var t := 0.0
	var ds := 0.25
	t_tab.append(0.0)
	s_tab.append(0.0)
	while s < path.length:
		var v := Config.SPEED * speed_mult(s + ds * 0.5)
		t += ds / v
		s = minf(s + ds, path.length)
		t_tab.append(t)
		s_tab.append(s)
	# keep the relative pacing but land the whole walk on the Shift-speed duration
	var target := path.length / PACE
	_time_k = target / t
	for i in t_tab.size():
		t_tab[i] *= _time_k
	total_time = target
	pace_ratio = REF_TIME / total_time


## Speed of the autowalk at s (m/s).
func speed_at(s: float) -> float:
	return Config.SPEED * speed_mult(s) / _time_k


func s_of_t(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= total_time:
		return path.length
	var i := t_tab.bsearch(t)
	var t0 := t_tab[i - 1]
	var t1 := t_tab[i]
	return lerpf(s_tab[i - 1], s_tab[i], (t - t0) / maxf(t1 - t0, 1e-6))


func t_of_s(s: float) -> float:
	var i := clampi(s_tab.bsearch(s), 1, s_tab.size() - 1)
	var s0 := s_tab[i - 1]
	var s1 := s_tab[i]
	return lerpf(t_tab[i - 1], t_tab[i], clampf((s - s0) / maxf(s1 - s0, 1e-6), 0.0, 1.0))


func _w(c: Dictionary, s: float) -> float:
	return smoothstep(c.s0 - c.fade, c.s0, s) * (1.0 - smoothstep(c.s1, c.s1 + c.fade, s))


## Desired look direction at s from camera position cam.
func look_dir(s: float, cam: Vector3) -> Vector3:
	var base := (path.forward_h(s) + Vector3(0, -0.28, 0)).normalized()
	var acc := Vector3.ZERO
	var wsum := 0.0
	for c in cues:
		var w := _w(c, s)
		if w > 0.0:
			acc += (c.target - cam).normalized() * w
			wsum += w
	if wsum <= 0.0:
		return base
	var k := smoothstep(0.0, 0.6, wsum)       # crossfading cues never let the plain heading leak in
	return (base * (1.0 - k) + acc / wsum * k).normalized()


## Field of view at s (cues can push in slowly).
func fov_at(s: float) -> float:
	var acc := 0.0
	var wsum := 0.0
	for c in cues:
		var w := _w(c, s)
		acc += float(c.fov) * w
		wsum += w
	if wsum <= 0.0:
		return Config.FOV
	var k := minf(wsum, 1.0)
	return lerpf(Config.FOV, acc / wsum, k)


## Camera offset from the line in the path frame (x right, y up): at the offering and the look back at the
## giant (both to the left) the diver moves to the left of and below the guide line, so the line stays behind
## the camera instead of cutting those shots in half (the statue is > 50 m away there).
func drift_at(s: float) -> Vector2:
	return Vector2(-3.6, -2.2) * smoothstep(900.0, 932.0, s) * (1.0 - smoothstep(1100.0, 1130.0, s))


## Warn about gaps between cues where the gaze would swing back to the plain heading.
func _check_gaps() -> void:
	var s := 0.0
	var prev_in := false
	var warned := false
	while s < path.length:
		var wsum := 0.0
		for c in cues:
			wsum += _w(c, s)
		var inside := wsum > 0.6
		if inside:
			warned = false
		elif prev_in or not warned:
			# a dip between two cues is only a problem when another cue starts soon after
			if not warned:
				for c in cues:
					if c.s0 > s and c.s0 - c.fade - s < 25.0:
						push_warning("Choreo: gaze dips between cues at s %.0f (weight %.2f)" % [s, wsum])
						warned = true
						break
		prev_in = inside
		s += 1.0
