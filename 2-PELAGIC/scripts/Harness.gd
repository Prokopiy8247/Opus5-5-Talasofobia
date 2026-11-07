extends Node
## Test/recording harness driven by user args after "--":
## --autowalk --start-at <s> --end-at <s> --capture-every <s> --shots <s,s,...> --quit-at-end --perf --msaa <2|4>
## --tour <s,s,...> [--settle <s>] [--looks dulrb]: jump to each path time, let the autowalk settle, capture, then quit.
## --looks adds extra views at each tour stop: d = down, u = up, l = left, r = right, b = back (relative to the gaze).
## --out <dir>: captures and perf.txt go to res://QA/<dir>/ (default "shots"; perf.txt then stays in res://QA/).
## --capture-end <s>: once the diver is at rest (the path clock stops), keep capturing every --capture-every seconds of
## real time for <s> seconds (files end_<seconds after rest>.png): the final still image, its lamp flashes, the fade.
## --windows <t0:t1:step,...>: several continuous captures in one run (instead of one run per window): for each window
## jump to t0 - 8 s (the operator settles into its natural move during the lead-in), then capture every <step> s of
## path time from t0 to t1 (files t<time>.png as with --capture-every); quits after the last window. A window
## starting at 0 starts from the very beginning (title card included). With --capture-end, a window that reaches the
## end keeps capturing the resting image before the run quits. A jump restarts story springs from where they were (the
## creature's head turn, its eye wake): for a window right after a story event (e.g. head_away 423), let its lead-in
## start before the event, or capture one long window through it.
## Tours and windows drop the title card (UI.skip_title) whenever they jump away from the opening, so only the opening
## stop's ahead view (or a window that starts the game from 0) shows it, as in play.
## --qa-hint: also run the controls hint of a manual start (cinematic runs have none), to check it against the title;
## --qa-hint-input <s>: at <s> s after the start, send it the player's first input (Main calls UI.hide_hint() then).

var autowalk := false
var start_at := 0.0
var end_at := -1.0
var capture_every := 0.0
var shots: Array = []
var quit_at_end := false
var perf := false
var msaa := 0
var active := false
var tour: Array = []
var settle := 3.0
var looks := ""
var out_dir := "shots"
var capture_end := 0.0
var windows: Array = []     # Vector3(t0, t1, step)
const WINDOW_LEAD := 8.0
## Path time by which the title card has dissolved in a natural start (UI time 9.5 s; the path clock lags ~2 s behind
## at the start): a tour stop at or beyond it never shows the title.
const TITLE_PATH_END := 7.0
var qa_hint := false
var qa_hint_input := -1.0
var _end_ms := -1           # Time.get_ticks_msec() when the diver came to rest (< 0 before)
var _next_end_cap := 0.0

var _next_cap := 0.0
var _frames := PackedFloat32Array()
var _gpu := PackedFloat32Array()
var _t := 0.0
var _vram_max := 0.0
var _busy := false
var _worst: Array = []      # [ms, path_time]
var _begun := false

func parse() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k: String = a[i]
		var v: String = a[i + 1] if i + 1 < a.size() else ""
		match k:
			"--autowalk": autowalk = true
			"--start-at": start_at = float(v); i += 1
			"--end-at": end_at = float(v); i += 1
			"--capture-every": capture_every = float(v); i += 1
			"--shots":
				for p in v.split(","): shots.append(float(p))
				i += 1
			"--quit-at-end": quit_at_end = true
			"--perf": perf = true
			"--msaa": msaa = int(v); i += 1
			"--settle": settle = float(v); i += 1
			"--looks": looks = v; i += 1
			"--out": out_dir = v; i += 1
			"--capture-end": capture_end = float(v); i += 1
			"--qa-hint": qa_hint = true
			"--qa-hint-input": qa_hint_input = float(v); i += 1
			"--windows":
				for p in v.split(","):
					var w := p.split(":")
					if w.size() == 3:
						windows.append(Vector3(float(w[0]), float(w[1]), float(w[2])))
				i += 1
			"--tour":
				for p in v.split(","): tour.append(float(p))
				i += 1
		i += 1
	active = capture_every > 0.0 or perf or end_at > 0.0 or quit_at_end or not shots.is_empty() or not tour.is_empty()
	active = active or not windows.is_empty()
	if not windows.is_empty():
		start_at = maxf(windows[0].x - WINDOW_LEAD, 0.0) if windows[0].x > 0.0 else 0.0
	process_mode = Node.PROCESS_MODE_ALWAYS

func begin() -> void:
	_begun = true
	_next_cap = start_at
	if active:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://QA/" + out_dir))
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if qa_hint and Game.main and Game.main.ui:
		Game.main.ui.start_hint()
		print("QA: controls hint scheduled as in a manual start")
		if qa_hint_input >= 0.0:
			_qa_first_input(qa_hint_input)
	if not tour.is_empty():
		_run_tour()
	elif not windows.is_empty():
		_run_windows()

func _process(delta: float) -> void:
	if not active or _busy or not _begun:
		return
	_t += delta
	var pt := Game.path_time
	if not tour.is_empty():
		return
	if perf and _t > 3.0:
		_frames.append(delta)
		if delta > 0.04:
			_worst.append([snappedf(delta * 1000.0, 0.1), snappedf(pt, 0.1)])
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		_vram_max = maxf(_vram_max, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0)
	if capture_every > 0.0 and pt >= _next_cap and _t > 1.0:
		_next_cap = pt + capture_every
		_capture(_time_name("t", pt, capture_every))
	elif capture_end > 0.0 and capture_every > 0.0 and Game.player and Game.player.ended:
		if _end_ms < 0:
			_end_ms = Time.get_ticks_msec()
		var et := (Time.get_ticks_msec() - _end_ms) / 1000.0
		if et >= _next_end_cap and et <= capture_end:
			_next_end_cap = et + capture_every
			_capture("end_%05.2f" % et)
	for s in shots.duplicate():
		if pt >= s and _t > 1.0:
			shots.erase(s)
			_capture(_time_name("shot_", s, 1.0 if is_equal_approx(s, floorf(s)) else 0.1))
	if end_at > 0.0 and pt >= end_at:
		finish()

## Capture file name for a path time. Steps of 1 s or more keep the integer name (t0123); finer steps get decimals
## (t0123.5, or t0123.25 below 0.1 s) so frames inside the same second never overwrite each other.
func _time_name(prefix: String, t: float, step: float) -> String:
	if step >= 1.0:
		return prefix + "%04d" % int(t)
	if step >= 0.1:
		return prefix + "%06.1f" % t
	return prefix + "%07.2f" % t

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

## QA --qa-hint-input: the player's first input, as Main forwards it to the UI.
func _qa_first_input(at: float) -> void:
	await _wait(at)
	print("QA: first player input at %.2f s (hint %s)" % [at, "on screen" if Game.main.ui.hint.modulate.a > 0.0 else "not yet shown"])
	Game.main.ui.hide_hint()

## Tours and windows: the title card belongs to the opening shot only (see UI.skip_title()).
func _skip_title() -> void:
	var ui = Game.main.ui if Game.main else null
	if ui and ui.has_method("skip_title") and ui.skip_title():
		print("QA: title card dropped at the jump away from the opening")

func _run_tour() -> void:
	const VIEWS := {"d": Vector2(0.0, -1.35), "u": Vector2(0.0, 1.05), "l": Vector2(1.5, -0.1), "r": Vector2(-1.5, -0.1), "b": Vector2(PI, -0.15)}
	var p: Node3D = Game.player
	for i in tour.size():
		if i > 0 or tour[i] >= TITLE_PATH_END:
			_skip_title()
		p.place_at_distance(PathDef.dist_at(tour[i] - 1.5))
		await _wait(settle)
		await _capture("tour_%02d_%04d" % [i, int(tour[i])])
		var aw: bool = p.autowalk
		var y0: float = p.yaw
		for k in looks:
			if not VIEWS.has(k):
				continue
			_skip_title()     # the extra views inspect the scene; the title stays on the opening's ahead view only
			p.autowalk = false
			p.yaw = y0 + VIEWS[k].x
			p.pitch = VIEWS[k].y
			p.yaw_v = 0.0; p.pitch_v = 0.0
			await _wait(0.7)
			await _capture("tour_%02d_%04d_%s" % [i, int(tour[i]), k])
		p.autowalk = aw
	finish()

func _run_windows() -> void:
	var p: Node3D = Game.player
	for i in windows.size():
		var w: Vector3 = windows[i]
		if i > 0:
			_skip_title()
			p.place_at_distance(PathDef.dist_at(maxf(w.x - WINDOW_LEAD, 0.0)))
		print("QA window %.1f-%.1f s every %.2f s" % [w.x, w.y, w.z])
		_next_cap = w.x
		capture_every = w.z
		while Game.path_time < w.y and not p.ended:
			await get_tree().process_frame
		if p.ended and capture_end > 0.0:
			# the final still image and the fade (the end captures run in _process until capture_end has passed)
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < int((capture_end + 0.5) * 1000.0):
				await get_tree().process_frame
		capture_every = 0.0
	finish()

func _capture(name: String) -> void:
	_busy = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://QA/%s/%s.png" % [out_dir, name]))
	_busy = false

func finish() -> void:
	if perf:
		_write_perf()
	active = false
	Game.quit(get_tree())

func _write_perf() -> void:
	if _frames.is_empty():
		return
	var sorted := _frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in _frames: total += f
	var avg_fps := _frames.size() / total
	var n1 := maxi(1, _frames.size() / 100)
	var worst_sum := 0.0
	for i in n1: worst_sum += sorted[sorted.size() - 1 - i]
	var low1 := n1 / worst_sum
	var gs := _gpu.duplicate()
	gs.sort()
	var gavg := 0.0
	for g in _gpu: gavg += g
	gavg /= maxf(_gpu.size(), 1)
	_worst.sort_custom(func(a, b): return a[0] > b[0])
	var txt := "frames %d\navg_fps %.1f\none_percent_low_fps %.1f\nworst_frame_ms %.1f\ngpu_avg_ms %.2f\ngpu_p99_ms %.2f\ngpu_max_ms %.2f\nvram_max_mb %.0f\nresolution %s\nframes_over_40ms %s\n" % [
		_frames.size(), avg_fps, low1, sorted[sorted.size() - 1] * 1000.0, gavg, gs[int(gs.size() * 0.99)], gs[gs.size() - 1], _vram_max, str(get_viewport().get_visible_rect().size), str(_worst.slice(0, 8))]
	var pp := "res://QA/perf.txt" if out_dir == "shots" else "res://QA/%s/perf.txt" % out_dir
	var f := FileAccess.open(ProjectSettings.globalize_path(pp), FileAccess.WRITE)
	f.store_string(txt)
	print("PERF ", txt.replace("\n", " | "))
