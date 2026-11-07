extends Node
## Procedural sound director. The lead adds it once the world and Game.targets exist:
##   var a = load("res://scripts/AudioDirector.gd").new(); add_child(a)
## Everything is a function of Game.path_time and Config.EVENTS, so a mid-path start (--start-at) works;
## one-shots fire only when the clock crosses their trigger. Public: set_paused(bool), end_fade(seconds),
## breath_state() (ExhaleBubbles).
## Story of the mix: the lip roof closes the room in (142-178 s) and releases into a wide airy reverb with a low
## swell as the gaze drops into the abyss; one far moan from below in the open blue (208 s); hush, swell, flex groan
## and a quickened breath after the line; hush, heartbeat and quickened breath around the eye lock; a second thrum
## rides the endless body under the diver to the end. Small gear creaks below 120 m, never inside the hushes.
## QA switches (user args): --audio-debug prints the mix state every 2 s of path time; --audio-rec records the
## Master, Breath, SFX, Ambience and Heart buses in 20 s chunks to res://QA/<out>/audio_<bus>_<path time>.wav.

const DIR := "res://assets/audio/"
const HUSH_DB := -26.0        # "near silence" of the beds during the two hushes
const PAUSE_DB := -14.0
const THIN_START := 500.0     # from here the mix thins to nearly silent
const GROAN_GAP := Vector2(20.0, 40.0)
const ROOF_T := Vector4(142.0, 160.0, 178.0, 186.0)   # under the lip: the roof eases in 142-160 s, releases 178-186 s
const OPEN_T := Vector4(178.0, 186.0, 196.0, 222.0)   # the airy release room after the roof (in, hold, out)
const RELEASE_AT := 179.5     # the low release swell as the gaze drops into the abyss
const MOAN_AT := 208.0        # one far moan from below and ahead in the open blue, long before the hush
const MOAN_DIST := 380.0      # metres from the diver (ahead and below), fixed in the world when it starts
const BREATH_FAST := 1.3      # breath tempo after the line and the eye lock (pitch restored on the Breath bus)
const BREATH_FAST_MIN := 1.03 # slowest tempo of the shifter's fast mode (just above 1.0 its frames thin the level)
const BREATH_LOOKAHEAD := 6.0 # fast mode starts this long before a tempo ramp (inside the held breath)
## Silent stretches of breath.wav after each exhale (file time, s, with margins: 0.08 s after the gap starts, 0.2 s
## before it ends). The Breath bus pitch shifter changes mode only here. From: python -I Tools/audio/bands.py --gaps breath
const BREATH_GAPS := [Vector2(3.91, 4.50), Vector2(8.62, 9.80), Vector2(13.77, 14.70), Vector2(18.79, 20.10),
	Vector2(23.98, 24.90), Vector2(29.00, 29.80)]
const CREAK_DEPTH := 120.0    # gear creaks only below this depth (m)
const CREAK_GAP := Vector2(20.0, 50.0)                # seconds between gear creaks, shallow -> deep
const PASSBY_T := Vector2(436.0, 460.0)               # the second thrum on the endless body fades in here
const PASSBY_MAX := 120.0     # the passby source sits on the body's skin nearest the diver, at most this far away

var _p := {}                  # key -> AudioStreamPlayer / AudioStreamPlayer3D
var _base := {}               # key -> base volume dB
var _g := {}                  # key -> smoothed linear gain (looped layers)
var _shot_db := {}            # key -> extra dB of the one-shot currently playing
var _groans: Array[AudioStream] = []
var _bubbles: Array[AudioStream] = []
var _creaks: Array[AudioStream] = []
var _ev := {}
var _rng := RandomNumberGenerator.new()
var _amb_lp: AudioEffectLowPassFilter
var _amb_rv: AudioEffectReverb
var _sfx_lp: AudioEffectLowPassFilter
var _sfx_rv: AudioEffectReverb
var _breath_ps: AudioEffectPitchShift
var _breath_bus := -1
var _breath_ps_idx := -1
var _ok := false
var _clock := 0.0
var _last_t := 0.0
var _depth := 0.0
var _pause := 1.0
var _pause_target := 1.0
var _end := 1.0
var _end_rate := 0.0
var _held := false
var _breath_restart := -1.0
var _next_groan := INF
var _next_bubble := INF
var _next_creak := INF
var _last_creak := -1
var _last_creak_t := -INF
var _last_groan := -1
var _roof := 0.0
var _open := 0.0
var _bps := 1.0               # breath playback speed (tempo)
var _breath_fast := false     # Breath bus shifter mode: true = phase vocoder at 1/_bps, false = pass-through at 1.0
var _next_beat := INF         # heartbeat retrigger time on the real clock
var _beat_i := 0
var _beating := false
var _passby_d := -1.0         # distance of the passby source from the camera (m), -1 = no body found
var _passby_skin := -1.0      # true distance of the body's nearest skin (m); beyond PASSBY_MAX it sets the level
var _was_live := false
var _snap := false            # first live frame: gains jump to their targets (silent, the master is still at zero)
var _seek_clock := 0.0        # real clock of the last jump of the path clock
var _debug := false
var _dbg_next := -INF
var _rec := {}                # bus name -> AudioEffectRecord (QA --audio-rec)
var _rec_t0 := 0.0
var _rec_pt0 := 0.0
var _rec_dir := ""
var _rec_on := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for k in Config.EVENTS:
		_ev[k] = float(Config.EVENTS[k])
	var args := OS.get_cmdline_user_args()
	_debug = "--audio-debug" in args
	_setup_buses()
	if "--audio-rec" in args:
		_setup_rec()
	_setup.call_deferred()


## Breath loop state for the exhale bubbles: (loop playback position in s, -1 while not playing, -2 when there is
## no breath audio at all; gain 0..1; held 0/1). The position is in the 30 s file's own time, whatever the tempo.
func breath_state() -> Vector3:
	var p = _p.get("breath")
	if not is_instance_valid(p) or p.stream == null:
		return Vector3(-2.0, 0.0, 1.0 if _held else 0.0)
	var g: float = float(_g.get("breath", 0.0))
	var pos: float = p.get_playback_position() if p.playing else -1.0
	return Vector3(pos, clampf(g, 0.0, 1.0), 1.0 if _held else 0.0)


## Duck everything about -14 dB over ~0.3 s (the director keeps running while the tree is paused).
func set_paused(paused: bool) -> void:
	_pause_target = db_to_linear(PAUSE_DB) if paused else 1.0


## Fade everything to silence over `seconds`, then stop all players.
func end_fade(seconds: float) -> void:
	_end_rate = 1.0 / maxf(seconds, 0.05)


# ---------------------------------------------------------------- setup
func _effect(bus: int, fx: AudioEffect) -> AudioEffect:
	for i in AudioServer.get_bus_effect_count(bus):
		var e := AudioServer.get_bus_effect(bus, i)
		if e.get_class() == fx.get_class():
			return e
	AudioServer.add_bus_effect(bus, fx)
	return fx


func _effect_index(bus: int, fx: AudioEffect) -> int:
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) == fx:
			return i
	return -1


func _bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, &"Master")
	return i


func _setup_buses() -> void:
	var lim := _effect(0, AudioEffectHardLimiter.new()) as AudioEffectHardLimiter
	lim.ceiling_db = -1.0
	for bus_name in ["Ambience", "SFX"]:
		var i := _bus(bus_name)
		var lp := _effect(i, AudioEffectLowPassFilter.new()) as AudioEffectLowPassFilter
		lp.resonance = 0.45
		lp.db = AudioEffectFilter.FILTER_12DB
		var rv := _effect(i, AudioEffectReverb.new()) as AudioEffectReverb
		rv.predelay_msec = 70.0
		rv.predelay_feedback = 0.25
		rv.hipass = 0.15
		rv.spread = 1.0
		rv.dry = 1.0
		if bus_name == "Ambience":
			_amb_lp = lp
			_amb_rv = rv
		else:
			_sfx_lp = lp
			_sfx_rv = rv
	# the regulator breath: its tempo rises after the line and the eye lock (player pitch_scale, so the bubbles that
	# follow its playback position stay in sync); this pitch shifter gives the pitch back. It is enabled in the first
	# hush and passes the breath straight through (ratio 1.0) except in its fast mode (see _breath_tempo).
	_breath_bus = _bus("Breath")
	_breath_ps = _effect(_breath_bus, AudioEffectPitchShift.new()) as AudioEffectPitchShift
	_breath_ps.fft_size = AudioEffectPitchShift.FFT_SIZE_1024   # short frames: valve clicks and bubbles stay crisp
	_breath_ps.oversampling = 4
	_breath_ps.pitch_scale = 1.0
	_breath_ps_idx = _effect_index(_breath_bus, _breath_ps)
	AudioServer.set_bus_effect_enabled(_breath_bus, _breath_ps_idx, false)
	_bus("Heart")     # the heartbeat, dry (its own bus only so QA can record it apart)
	_update_fx()


## QA: one recorder at the end of each bus chain (added last: adding effects later would re-instance it).
func _setup_rec() -> void:
	var out := "audio_rec"
	var m = Game.main
	if is_instance_valid(m) and m.get("harness") != null and str(m.harness.get("out_dir")) != "":
		out = str(m.harness.out_dir)
	_rec_dir = "res://QA/%s/" % out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_rec_dir))
	for bus_name in ["Master", "Breath", "SFX", "Ambience", "Heart"]:
		var i := AudioServer.get_bus_index(bus_name)
		if i < 0:
			continue
		var r := AudioEffectRecord.new()
		r.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(i, r)
		_rec[bus_name] = r
	# recording starts on the first live frame (_process), so each chunk is named by the true path time at its start
	# also on a mid-path start (the load warm-up jumps the path clock behind the black screen)


func _rec_start() -> void:
	_rec_on = true
	_rec_t0 = _clock
	_rec_pt0 = Game.path_time
	for k in _rec:
		(_rec[k] as AudioEffectRecord).set_recording_active(true)


func _rec_flush(restart: bool) -> void:
	for k in _rec:
		var r := _rec[k] as AudioEffectRecord
		if not r.is_recording_active():
			continue
		r.set_recording_active(false)
		var w := r.get_recording()
		if w:
			var f := "%saudio_%s_%06.1f.wav" % [_rec_dir, k, _rec_pt0]
			w.save_to_wav(ProjectSettings.globalize_path(f))
	print("AudioDirector: rec chunk path %.1f-%.1f s (real %.1f s)" % [_rec_pt0, Game.path_time, _clock - _rec_t0])
	if restart:
		_rec_start()


func _exit_tree() -> void:
	if _rec_on:
		_rec_flush(false)


func _stream(file: String, loop: bool) -> AudioStream:
	var path := DIR + file + ".wav"
	if not ResourceLoader.exists(path):
		return null
	var s := load(path) as AudioStream
	var w := s as AudioStreamWAV
	if w:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		if loop:
			w.loop_begin = 0
			w.loop_end = roundi(w.get_length() * float(w.mix_rate))
	return s


func _new_3d(unit: float, max_dist: float, db: float) -> AudioStreamPlayer3D:
	var p3 := AudioStreamPlayer3D.new()
	p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p3.unit_size = unit
	p3.max_distance = max_dist
	p3.max_db = clampf(db + 4.0, -24.0, 6.0)
	p3.attenuation_filter_db = 0.0
	p3.panning_strength = 0.6
	return p3


## Creates a player: 3D under Game.targets[target] when that node exists, a free 3D player under the director when
## target is "*" (placed by the director), else 2D under the director.
func _add(key: String, file: String, loop: bool, bus: String, db: float, target := "", unit := 0.0, max_dist := 0.0) -> void:
	var anchor = Game.targets.get(target) if target != "" and target != "*" else null
	var p
	if is_instance_valid(anchor) and anchor is Node3D:
		p = _new_3d(unit, max_dist, db)
		(anchor as Node3D).add_child(p)
	elif target == "*":
		var p3 := _new_3d(unit, max_dist, db)
		p3.top_level = true
		add_child(p3)
		p = p3
	else:
		p = AudioStreamPlayer.new()
		add_child(p)
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.bus = StringName(bus)
	p.volume_db = -80.0
	p.stream = _stream(file, loop) if file != "" else null
	_p[key] = p
	_base[key] = db
	_g[key] = 0.0
	_shot_db[key] = 0.0


func _setup() -> void:
	_add("open", "amb_open_water", true, "Ambience", -14.0)
	_add("deep", "amb_deep", true, "Ambience", -13.0)
	_add("clicks", "clicks_far", true, "Ambience", -24.0)
	_add("breath", "breath", true, "Breath", -18.0)
	_add("boat", "boat_hull", true, "SFX", -10.0, "boat", 10.0, 90.0)
	_add("thrum", "creature_thrum", true, "SFX", -8.0, "creature_body", 160.0, 3000.0)
	_add("passby", "creature_thrum", true, "SFX", -12.0, "*", PASSBY_MAX, 3000.0)
	_add("eye", "eye_hum", true, "SFX", -16.0, "eye", 120.0, 2000.0)
	_add("groan", "", false, "SFX", -8.0, "creature_body", 200.0, 3000.0)
	_add("jaw", "jaw_exhale", false, "SFX", -10.0, "eye", 150.0, 2000.0)
	_add("swell", "swell_dark", false, "SFX", -10.5)       # its new 110-420 Hz band makes it ~2.5 LU louder: -1.5 dB
	_add("release", "swell_release", false, "Ambience", -18.0)
	_add("moan", "moan_far", false, "SFX", -15.0, "*", MOAN_DIST, 4000.0)
	_add("creak", "", false, "SFX", -16.0)
	_add("heart0", "heartbeat", false, "Heart", -24.0)
	_add("heart1", "heartbeat", false, "Heart", -24.0)
	_add("bubble", "", false, "SFX", -14.0)
	var pb = _p.get("passby")
	if is_instance_valid(pb) and pb is AudioStreamPlayer3D:
		pb.panning_strength = 1.0       # the body slides beneath: let it pan
	for i in 3:
		var s := _stream("creature_groan_%d" % (i + 1), false)
		if s:
			_groans.append(s)
		var b := _stream("bubbles_%d" % (i + 1), false)
		if b:
			_bubbles.append(b)
	for i in 4:
		var c := _stream("suit_creak_%d" % (i + 1), false)
		if c:
			_creaks.append(c)
	var t := Game.path_time
	_last_t = t
	_held = _breath_hold(t)
	_reschedule(t)
	var loaded := 0
	for k in _p:
		var p = _p[k]
		if p.stream == null:
			continue
		loaded += 1
		var looped: bool = k in ["open", "deep", "clicks", "breath", "boat", "thrum", "eye"]
		if looped and not (k == "breath" and _held) and not (k == "boat" and t > 40.0):
			p.play()
	print("AudioDirector: %d/%d players have streams, %d groans, %d bubbles, %d creaks, start t=%.1f s" % [loaded, _p.size(), _groans.size(), _bubbles.size(), _creaks.size(), t])
	_ok = true


# ---------------------------------------------------------------- runtime
## False while Main warms the world up behind the black screen (the path clock jumps through every beat then):
## the mix stays silent and nothing fires; the sound fades in with the picture.
func _live() -> bool:
	var m = Game.main
	if not is_instance_valid(m):
		return true
	var r = m.get("running")
	return r == null or bool(r)


func _process(delta: float) -> void:
	if not _ok:
		return
	var dt := minf(delta, 0.1)
	var t := Game.path_time
	var live := _live()
	if live and not _was_live:
		# the first live frame: settle on the start place at once (the master is still at zero, nothing is heard)
		_was_live = true
		_snap = true
		_last_t = t
		_reschedule(t)
		if is_instance_valid(Game.camera):
			_depth = maxf(-Game.camera.global_position.y, 0.0)
		if not _rec.is_empty() and not _rec_on:
			_rec_start()
	if live:
		_clock += dt
	if not live or absf(t - _last_t) > 3.0:     # warm-up, seek or late start: re-evaluate state, fire nothing
		_reschedule(t)
		_seek_clock = _clock
		_dbg_next = t
	else:
		_triggers(_last_t, t)
	_last_t = t
	if is_instance_valid(Game.camera):
		var d := maxf(-Game.camera.global_position.y, 0.0)
		_depth += (d - _depth) * (1.0 - exp(-dt / 1.0))
	_roof = smoothstep(ROOF_T.x, ROOF_T.y, t) * (1.0 - smoothstep(ROOF_T.z, ROOF_T.w, t))
	_open = smoothstep(OPEN_T.x, OPEN_T.y, t) * (1.0 - smoothstep(OPEN_T.z, OPEN_T.w, t))
	_update_fx()
	_pause += (_pause_target - _pause) * (1.0 - exp(-dt / 0.1))
	if _end_rate > 0.0:
		_end = maxf(_end - dt * _end_rate, 0.0)
	var master := smoothstep(0.0, Config.FADE_IN, _clock) * _pause * _end * _end
	_mix(t, dt, master)
	_heart(t)
	if _debug and live and t >= _dbg_next:
		_dbg_next = floorf(t / 2.0) * 2.0 + 2.0
		_print_state(t, master)
	if _rec_on and _clock - _rec_t0 >= 20.0:
		_rec_flush(true)
	if _end_rate > 0.0 and _end <= 0.0:
		for k in _p:
			if is_instance_valid(_p[k]):
				_p[k].stop()
		_ok = false


func _update_fx() -> void:
	var k := clampf(_depth / 450.0, 0.0, 1.0)
	if _amb_lp:
		# under the lip the bed closes in (dull and short) and opens wide and airy as the roof falls behind
		var amb_cut := clampf(7000.0 * exp(-_depth / 210.0), 800.0, 7000.0)
		_amb_lp.cutoff_hz = exp(lerpf(log(amb_cut), log(minf(1200.0, amb_cut)), _roof))
		_amb_rv.room_size = lerpf(lerpf(lerpf(0.4, 0.9, k), 0.3, _roof), 0.97, _open)
		_amb_rv.damping = lerpf(lerpf(lerpf(0.5, 0.75, k), 0.8, _roof), 0.4, _open)
		_amb_rv.wet = lerpf(0.06, 0.24, k) + 0.08 * _roof + 0.1 * _open
		_amb_rv.predelay_msec = lerpf(lerpf(70.0, 18.0, _roof), 120.0, _open)
	if _sfx_lp:
		var sfx_cut := clampf(12000.0 * exp(-_depth / 350.0), 2200.0, 12000.0)
		_sfx_lp.cutoff_hz = exp(lerpf(log(sfx_cut), log(minf(2400.0, sfx_cut)), _roof))
		_sfx_rv.room_size = lerpf(lerpf(lerpf(0.45, 0.92, k), 0.3, _roof), 0.97, _open)
		_sfx_rv.damping = lerpf(lerpf(lerpf(0.45, 0.7, k), 0.8, _roof), 0.4, _open)
		_sfx_rv.wet = lerpf(0.1, 0.36, k) + 0.08 * _roof + 0.1 * _open
		_sfx_rv.predelay_msec = lerpf(lerpf(70.0, 18.0, _roof), 120.0, _open)


## 0 outside, 1 inside a hush window (fall over `fall` s from a, rise over `rise` s from b).
func _dip(t: float, a: float, fall: float, b: float, rise: float) -> float:
	return smoothstep(a, a + fall, t) * (1.0 - smoothstep(b, b + rise, t))


func _breath_hold(t: float) -> bool:
	return (t >= _ev.hush_line + 0.5 and t < _ev.dark_line + 6.0) or (t >= _ev.hush_head + 0.5 and t < _ev.head_away + 1.0)


## Breath tempo: quickens after each hush (the line, the eye lock), eased over ~6 s, calming back slowly.
func _breath_speed(t: float) -> float:
	var a := smoothstep(_ev.dark_line + 8.0, _ev.dark_line + 14.0, t) * (1.0 - smoothstep(294.0, 306.0, t))
	var b := smoothstep(_ev.head_away + 3.0, _ev.head_away + 9.0, t) * (1.0 - smoothstep(462.0, 476.0, t))
	return 1.0 + (BREATH_FAST - 1.0) * maxf(a, b)


## Quiet windows: the two hushes with their lead-in and recovery, and the far moan. No small sounds fire here.
func _quiet(t: float) -> bool:
	return (t > _ev.hush_line - 4.0 and t < _ev.dark_line + 8.0) \
		or (t > _ev.hush_head - 6.0 and t < _ev.head_away + 12.0) \
		or (t > MOAN_AT - 4.0 and t < MOAN_AT + 12.0)


func _mix(t: float, dt: float, master: float) -> void:
	var hush := maxf(_dip(t, _ev.hush_line, 3.0, _ev.dark_line + 6.0, 12.0), _dip(t, _ev.hush_head, 3.0, _ev.head_away, 10.0))
	var bed := db_to_linear(HUSH_DB * hush)
	var thin := smoothstep(THIN_START, THIN_START + 30.0, t)
	var soft := db_to_linear(-4.0 * smoothstep(150.0, 210.0, t))          # beat 3: the sound softens
	var w_deep := smoothstep(90.0, 190.0, _depth)
	var tg := {}
	tg["open"] = (1.0 - w_deep) * soft * bed * db_to_linear(-20.0 * thin)
	tg["deep"] = w_deep * bed * db_to_linear(-18.0 * thin)
	tg["clicks"] = smoothstep(30.0, 50.0, t) * (1.0 - smoothstep(280.0, 380.0, _depth)) * soft * bed * (1.0 - thin)
	tg["boat"] = 1.0 - smoothstep(24.0, 38.0, t)
	tg["thrum"] = smoothstep(_ev.dark_line + 4.0, _ev.flex + 18.0, t) * bed * (1.0 - thin)
	# the endless body sliding beneath: exempt from the thinning, only the end fade takes it
	# (the source sits at most PASSBY_MAX m away; a body further off is quieter as inverse distance would make it)
	tg["passby"] = smoothstep(PASSBY_T.x, PASSBY_T.y, t) * (PASSBY_MAX / maxf(_passby_skin, PASSBY_MAX) if _place_passby(t) else 0.0)
	var eye_base := 0.22 * smoothstep(385.0, _ev.hush_head, t) * (1.0 - smoothstep(_ev.head_away + 6.0, _ev.head_away + 30.0, t))
	var eye_peak := smoothstep(_ev.eye_hold - 3.0, _ev.eye_hold + 1.5, t) * (1.0 - smoothstep(_ev.head_away - 0.5, _ev.head_away + 10.0, t))
	tg["eye"] = maxf(eye_base, eye_peak)
	# breathing: held during both hushes, resumes with a relief burst of bubbles and a fresh inhale
	var hold := _breath_hold(t)
	if hold != _held:
		_held = hold
		if not hold:
			_fire("bubble", _bubbles[2] if _bubbles.size() > 2 else null, 0.0, 1.0)
			_breath_restart = _clock + 1.3
	if _breath_restart >= 0.0 and _clock >= _breath_restart:
		_breath_restart = -1.0
		var bp = _p.get("breath")
		if is_instance_valid(bp) and bp.stream:
			_g["breath"] = 0.0
			bp.play(0.0)
	tg["breath"] = 0.0 if (_held or _breath_restart >= 0.0) else db_to_linear(-9.0 * thin)
	var mdb := linear_to_db(maxf(master, 0.00001))
	for k in _p:
		var p = _p[k]
		if not is_instance_valid(p):
			continue
		if tg.has(k):
			var tau := 1.0 if k == "boat" else (0.45 if k == "breath" else 0.4)
			_g[k] += (float(tg[k]) - _g[k]) * (1.0 if _snap else 1.0 - exp(-dt / tau))
			p.volume_db = _base[k] + linear_to_db(maxf(_g[k] * master, 0.00001))
			if p.playing and _g[k] < 0.002 and ((k == "breath" and _held) or (k == "boat" and t > 40.0) or (k == "passby" and tg[k] <= 0.0)):
				p.stop()
			elif k == "passby" and not p.playing and tg[k] > 0.0 and p.stream:
				p.pitch_scale = 0.93            # a little lower than the coils' thrum, and out of phase with it
				p.play(_rng.randf_range(5.0, 30.0))
		else:
			p.volume_db = _base[k] + _shot_db[k] + mdb
	var dp = _p.get("deep")
	if is_instance_valid(dp):
		dp.pitch_scale = lerpf(1.0, 0.86, smoothstep(150.0, 520.0, _depth))   # the drone deepens
	_breath_tempo(t)
	_snap = false


## Breath tempo through the player's pitch_scale (ExhaleBubbles reads the playback position, which stays in the
## file's own time); the Breath bus pitch shifter takes the pitch back down by the same ratio.
## Godot's pitch shifter passes the audio straight through at a ratio of exactly 1.0 and runs its phase vocoder at
## any other ratio, 16 ms later and starting from whatever its buffers last held: a switch between the two cuts a
## hole into a playing breath. So the shifter changes mode only while the breath is silent. Fast mode starts inside
## the held breath before each tempo ramp (BREATH_LOOKAHEAD) and ends in the first silent gap after the ramp has
## calmed down; in between the ratio stays well away from 1.0 (BREATH_FAST_MIN). Outside fast mode both the player
## and the shifter sit at exactly 1.0, so the normal breath is untouched.
func _breath_tempo(t: float) -> void:
	var bp = _p.get("breath")
	if not is_instance_valid(bp) or _breath_ps == null or _breath_ps_idx < 0:
		return
	var silent := _breath_silent(bp)
	var on := AudioServer.is_bus_effect_enabled(_breath_bus, _breath_ps_idx)
	var want: bool = t >= float(_ev.hush_line)
	if want != on and _was_live and silent:
		AudioServer.set_bus_effect_enabled(_breath_bus, _breath_ps_idx, want)
		on = want
		print("AudioDirector: breath pitch shifter %s at t=%.1f s (breath silent)" % ["on" if on else "off", t])
	var s := _breath_speed(t)
	var want_fast: bool = on and (_breath_speed(t + BREATH_LOOKAHEAD) > 1.0005 or s > BREATH_FAST_MIN + 0.01)
	if want_fast != _breath_fast and _was_live and (silent or not on):
		_breath_fast = want_fast
		print("AudioDirector: breath shifter %s at t=%.1f s (breath %s, file pos %.2f s)" % [
			"fast mode" if want_fast else "pass-through", t, "playing" if bp.playing else "stopped",
			bp.get_playback_position() if bp.playing else -1.0])
	_bps = maxf(s, BREATH_FAST_MIN) if _breath_fast else 1.0
	bp.pitch_scale = _bps
	_breath_ps.pitch_scale = 1.0 / _bps if _breath_fast else 1.0


## True while nothing of the breath can be heard now or in the next ~0.2 s: not playing, faded out, the silent first
## live frame, or inside one of the silent gaps after an exhale (BREATH_GAPS, file time) with its bus actually quiet.
func _breath_silent(bp) -> bool:
	if _snap or not bp.playing or float(_g.get("breath", 0.0)) < 0.01:
		return true
	var pos: float = bp.get_playback_position()
	for gap in BREATH_GAPS:
		if pos > gap.x and pos < gap.y:
			return AudioServer.get_bus_peak_volume_left_db(_breath_bus, 0) < -60.0 \
				and AudioServer.get_bus_peak_volume_right_db(_breath_bus, 0) < -60.0
	return false


## Moves the passby thrum to the endless body's skin nearest the camera (at most PASSBY_MAX m away, on the line
## towards it). Returns false when there is no body to follow.
func _place_passby(t: float) -> bool:
	var pb = _p.get("passby")
	if t < PASSBY_T.x - 2.0 or not is_instance_valid(pb) or not (pb is AudioStreamPlayer3D) or not is_instance_valid(Game.camera):
		_passby_d = -1.0
		_passby_skin = -1.0
		return false
	var c = Game.targets.get("creature")
	if not is_instance_valid(c) or not (c is Node3D):
		_passby_d = -1.0
		_passby_skin = -1.0
		return false
	# SCP3000 keeps the extension samples (model space, every 8 model m) in _ext_pts/_ext_ss/_ext_r
	var pts = c.get("_ext_pts")
	var ss = c.get("_ext_ss")
	var rr = c.get("_ext_r")
	if not (pts is PackedVector3Array) or pts.size() < 2:
		_passby_d = -1.0
		_passby_skin = -1.0
		return false
	var has_ss: bool = ss is PackedFloat32Array and ss.size() == pts.size()
	var has_r: bool = rr is PackedFloat32Array and rr.size() == pts.size()
	var can_rise: bool = has_ss and c.has_method("ext_rise_model")
	var sc := float(c.get("creature_scale")) if c.get("creature_scale") != null else 1.0
	var xf: Transform3D = (c as Node3D).global_transform
	var cam := Game.camera.global_position
	var best := INF
	var bp := Vector3.ZERO
	var br := 0.0
	var prev: Vector3 = xf * (pts[0] + Vector3(0.0, c.ext_rise_model(ss[0]) if can_rise else 0.0, 0.0))
	for k in range(1, pts.size()):
		var cur: Vector3 = xf * (pts[k] + Vector3(0.0, c.ext_rise_model(ss[k]) if can_rise else 0.0, 0.0))
		var q := Geometry3D.get_closest_point_to_segment(cam, prev, cur)
		var d2 := q.distance_squared_to(cam)
		if d2 < best:
			best = d2
			bp = q
			if has_r:
				var seg := prev.distance_to(cur)
				var f := clampf(prev.distance_to(q) / seg, 0.0, 1.0) if seg > 1e-3 else 0.0
				br = lerpf(rr[k - 1], rr[k], f) * sc
		prev = cur
	var to_cam := cam - bp
	var dist := to_cam.length()
	_passby_skin = maxf(dist - br, 1.0)
	if dist > 1e-3:
		# from the spine to the skin, then no further than PASSBY_MAX from the diver (same direction: the pan holds)
		bp = cam - to_cam / dist * minf(_passby_skin, PASSBY_MAX)
	_passby_d = bp.distance_to(cam)
	(pb as AudioStreamPlayer3D).global_position = bp
	return true


func _crossed(t0: float, t1: float, x: float) -> bool:
	return t0 < x and t1 >= x


func _fire(key: String, stream: AudioStream, extra_db: float, pitch: float) -> void:
	var p = _p.get(key)
	if not is_instance_valid(p):
		return
	if stream:
		p.stream = stream
	if p.stream == null:
		return
	_shot_db[key] = extra_db
	p.pitch_scale = pitch
	p.play()


func _busy(key: String) -> bool:
	var p = _p.get(key)
	return is_instance_valid(p) and p.playing


func _groan_ok(x: float) -> float:
	if x > _ev.hush_head - 12.0 and x < _ev.head_away + 8.0:
		x = _ev.head_away + _rng.randf_range(8.0, 16.0)
	return x if x < THIN_START - 5.0 else INF


## Next gear creak after time x: 20-50 s apart (rarer with depth), pushed out of the quiet windows.
func _creak_after(x: float) -> float:
	var k := smoothstep(CREAK_DEPTH, 480.0, _depth)
	var nx := x + maxf(lerpf(CREAK_GAP.x, CREAK_GAP.y, k) * _rng.randf_range(0.85, 1.25), CREAK_GAP.x)
	for i in 3:
		if not _quiet(nx):
			break
		nx += 4.0
		while _quiet(nx):
			nx += 1.0
		nx += _rng.randf_range(2.0, 8.0)
	return nx


func _reschedule(t: float) -> void:
	var first: float = _ev.flex + 3.0
	_next_groan = _groan_ok(first if t < first else t + _rng.randf_range(8.0, 16.0))
	_next_bubble = t + _rng.randf_range(6.0, 14.0)
	_next_creak = _creak_after(t - CREAK_GAP.x + _rng.randf_range(6.0, 14.0))


func _triggers(t0: float, t1: float) -> void:
	if t1 <= t0:
		return
	if _crossed(t0, t1, _ev.dark_line + 6.0):
		_fire("swell", null, 0.0, 1.0)
		print("AudioDirector: swell (the line) at t=%.1f s" % t1)
	if _crossed(t0, t1, _ev.jaw_open):
		_fire("jaw", null, 0.0, 1.0)
	if _crossed(t0, t1, RELEASE_AT):
		_fire("release", null, 0.0, 1.0)
		print("AudioDirector: release swell at t=%.1f s (roof %.2f)" % [t1, _roof])
	if _crossed(t0, t1, MOAN_AT):
		_moan(t1)
	if t1 >= _next_groan:
		if _groans.is_empty():
			_next_groan = INF
		elif _busy("groan") or _busy("jaw"):
			_next_groan = t1 + 4.0
		else:
			var i := _rng.randi_range(0, _groans.size() - 1)
			if i == _last_groan and _groans.size() > 1:
				i = (i + 1) % _groans.size()
			_last_groan = i
			_fire("groan", _groans[i], 0.0, _rng.randf_range(0.9, 1.04))
			_next_groan = _groan_ok(t1 + _rng.randf_range(GROAN_GAP.x, GROAN_GAP.y))
	if t1 >= _next_bubble:
		_next_bubble = t1 + _rng.randf_range(10.0, 28.0)
		if t1 > 5.0 and t1 < 330.0 and not _held and not _bubbles.is_empty() and not _busy("bubble"):
			_fire("bubble", _bubbles[_rng.randi_range(0, mini(1, _bubbles.size() - 1))], -8.0, _rng.randf_range(0.85, 1.2))
	if t1 >= _next_creak:
		_creak(t1)


## One far moan from below and ahead, fixed in the world where it starts (the diver glides past it slowly).
func _moan(t: float) -> void:
	var p = _p.get("moan")
	if not is_instance_valid(p) or p.stream == null:
		return
	var fw := Vector3(0.0, 0.0, -1.0)
	if Game.curve != null:
		var tg := PathDef.tangent(PathDef.dist_at(t))
		if Vector2(tg.x, tg.z).length() > 0.1:
			fw = Vector3(tg.x, 0.0, tg.z).normalized()
	var dir := (fw * 0.75 + Vector3.DOWN * 0.66).normalized()
	if p is AudioStreamPlayer3D:
		p.global_position = Game.cam_pos() + dir * MOAN_DIST
	_fire("moan", null, 0.0, 1.0)
	print("AudioDirector: far moan at t=%.1f s, %.0f m ahead and below" % [t, MOAN_DIST])


## Small gear sounds under pressure (mask, suit, hose), rarer and lower with depth; never in a quiet window.
func _creak(t: float) -> void:
	if _creaks.is_empty():
		_next_creak = INF
		return
	if _depth < CREAK_DEPTH or t >= THIN_START + 40.0:
		_next_creak = t + _rng.randf_range(4.0, 8.0) if t < THIN_START + 40.0 else INF
		return
	# never over a creature event or another creak (they would mask each other)
	var busy := _busy("moan") or _busy("creak") or _busy("groan") or _busy("swell") or _busy("jaw") or _busy("release")
	if _quiet(t) or _held or busy or t - _last_creak_t < CREAK_GAP.x:
		_next_creak = _creak_after(maxf(t, _last_creak_t + 1.0) - CREAK_GAP.x + 2.0)
		return
	var i := _rng.randi_range(0, _creaks.size() - 1)
	if i == _last_creak and _creaks.size() > 1:
		i = (i + 1 + _rng.randi_range(0, _creaks.size() - 2)) % _creaks.size()
	_last_creak = i
	var k := smoothstep(CREAK_DEPTH, 480.0, _depth)
	var thin := smoothstep(THIN_START, THIN_START + 30.0, t)
	var extra := -7.0 * k - 6.0 * thin + _rng.randf_range(-2.0, 1.0)
	_fire("creak", _creaks[i], extra, _rng.randf_range(0.9, 1.08))
	print("AudioDirector: gear creak %d at t=%.1f s (%.0f dB, depth %.0f m, %.1f s after the last)" % [i + 1, t, _base["creak"] + extra, _depth, t - _last_creak_t if _last_creak_t > -1e9 else 0.0])
	_last_creak_t = t
	_next_creak = _creak_after(t)


## Heartbeat through the second hush and the eye lock: 70 -> 95 bpm by the eye hold, settling as the head turns
## away, gone by ~437 s. Quiet (-24 .. -21 dB) and low; retriggered on the real clock, two players so tails overlap.
func _heart(t: float) -> void:
	var hb := smoothstep(_ev.hush_head, _ev.hush_head + 4.0, t) * (1.0 - smoothstep(_ev.head_away + 6.0, _ev.head_away + 14.0, t))
	var on := hb > 0.02 and _pause_target >= 1.0 and _end_rate <= 0.0 and _was_live and _clock - _seek_clock > 0.5
	if on != _beating:
		_beating = on
		print("AudioDirector: heartbeat %s at t=%.1f s" % ["on" if on else "off", t])
		if on:
			_next_beat = _clock
	if not on:
		return
	if _clock < _next_beat:
		return
	var bpm := 70.0 + 25.0 * smoothstep(_ev.hush_head, _ev.eye_hold, t) - 12.0 * smoothstep(_ev.head_away, _ev.head_away + 10.0, t)
	var key := "heart%d" % (_beat_i % 2)
	_beat_i += 1
	var extra := 3.0 * smoothstep(_ev.hush_head, _ev.eye_hold, t) + linear_to_db(maxf(hb, 0.00001)) + _rng.randf_range(-0.8, 0.4)
	_fire(key, null, extra, _rng.randf_range(0.98, 1.02))
	_next_beat = _clock + 60.0 / bpm * _rng.randf_range(0.98, 1.02)


func _print_state(t: float, master: float) -> void:
	var g := ""
	for k in ["open", "deep", "thrum", "passby", "eye", "breath"]:
		g += " %s %.2f" % [k, float(_g.get(k, 0.0))]
	var bpm := 70.0 + 25.0 * smoothstep(_ev.hush_head, _ev.eye_hold, t) - 12.0 * smoothstep(_ev.head_away, _ev.head_away + 10.0, t)
	var bp = _p.get("breath")
	var bpos: float = bp.get_playback_position() if is_instance_valid(bp) and bp.playing else -1.0
	print("AudioDirector: t %.1f depth %.0f roof %.2f open %.2f amb_lp %.0f room %.2f damp %.2f wet %.2f pre %.0f | breath x%.3f %s pos %.2f held %s | heart %s %.0f bpm | passby %.0f m (skin %.0f m) |%s | master %.2f" % [
		t, _depth, _roof, _open, _amb_lp.cutoff_hz if _amb_lp else 0.0, _amb_rv.room_size if _amb_rv else 0.0,
		_amb_rv.damping if _amb_rv else 0.0, _amb_rv.wet if _amb_rv else 0.0, _amb_rv.predelay_msec if _amb_rv else 0.0,
		_bps, "fast" if _breath_fast else "thru", bpos, str(_held), str(_beating), bpm, _passby_d, _passby_skin, g, master])
