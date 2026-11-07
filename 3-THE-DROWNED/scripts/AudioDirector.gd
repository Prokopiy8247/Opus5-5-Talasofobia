class_name AudioDirector
extends Node
## All of the game's sound: depth-crossfaded drones (with harmonic layers so they carry on phone
## speakers), scored reveals that swell (never jump), breathing as performance (a tension curve, held
## breath at the reveals, a shaky exhale after), the distant bell, creaks of the sunken giants, the wall
## waking up and dying, and the ending (a lamp stutter, three knocks, hard silence, the deep bell).
##
## INTERFACE (all optional for Main):
##   signal exhaled(strength)    every exhale, strength 0.5 (calm) .. 1.0 (shaky, after a held breath);
##                               connect it to the bubbles. While it has a connection, breath_pos() stays
##                               constant so the old Main._breathe() emits nothing (no double bubbles).
##   update(s, cam, dt)          every frame while not paused (signature unchanged)
##   sting(name)                 play a scored reveal now (its bloom comes STINGS[name].lead s later);
##                               each name fires once, the automatic trigger from EVENTS is then skipped
##   one_shot(name)              "stone_groan" (= sting m3, Main fires it as the head turns), "lamp_on",
##                               "whale", "knock", "flicker", "bubbles", "bell", or any sting name
##   set_tension(x)              external tension 0..1, combined as max with the built-in curve; < 0 clears
##   hold_breath(seconds, delay) sharp intake (after delay s), hold, then a shaky exhale
##   set_wave(x), set_dark(x)    optional: feed uw_reveal.x / uw_dark each frame so the relay clicks and the
##                               contactor clunks follow the visible waves exactly (else WALL_WAVE/DARK_WAVE)
##   on_end()                    the diver reached the door (timeline in END_*: flicker, gasp, knocks,
##                               hard silence, deep bell)
##   breath_pos()                compatibility for Main._breathe(): a virtual position that crosses
##                               Main.EXHALES [2.25, 6.85] exactly once per exhale (never returns -1)
##   --audio-rec FILE            user arg: record the master output to a WAV (saved on exit) plus an
##                               event log FILE.events.txt; tools_py/mix_report.py measures it

signal exhaled(strength: float)

# ============================== tuning (retune freely) ==============================
## Path distance s (m) at which each scored moment lands. Stings start STINGS[name].lead seconds earlier
## (estimated from the walking speed), so the bloom falls on s. A negative value disables the automatic
## trigger (Main can still call sting(name) / one_shot(name)).
const EVENTS := {
	"m1": 342.0,          # M1 the liner's deck and wall
	"m2": 612.0,          # M2 the receding forest
	"whale": 590.0,       # fallback: Main calls one_shot("whale_call") as the leviathan starts (s 588)
	"m3": 884.0,          # M3 the head turn: fallback only, Main fires one_shot("stone_groan") at the turn
	"m4": 1005.0,         # M4 the liner in the palm
	"wall": 1058.0,       # the wall wakes up: breaker + generator spin-up as the porthole wave starts
	"power": 1268.0,      # the lights die: generator spin-down as the darkness wave starts
	"door_bell": 1392.0,  # one bell strike when the door is framed
}
## file, lead = seconds from the start of the file to its bloom, db = level, duck = ambience dip (dB)
## from the start to the bloom, hold = breath held over the bloom (s, 0 = none)
const STINGS := {
	"m1": {"file": "sting_m1", "lead": 7.0, "db": -2.0, "duck": 6.0, "hold": 4.5},
	"m2": {"file": "sting_m2", "lead": 6.0, "db": -2.5, "duck": 6.0, "hold": 4.0},
	"m3": {"file": "stone_groan", "lead": 1.6, "db": -2.5, "duck": 8.0, "hold": 6.0},
	"m4": {"file": "sting_m4", "lead": 6.0, "db": -0.5, "duck": 6.0, "hold": 3.5},
	"wall": {"file": "wall_wake", "lead": 1.0, "db": 0.0, "duck": 5.0, "hold": 5.0},
	"power": {"file": "power_down", "lead": 0.5, "db": -0.5, "duck": 4.0, "hold": 0.0},
}
const WALL_WAVE := Vector2(1014.0, 1144.0)   # s range of the porthole wave when set_wave() is not fed
const DARK_WAVE := Vector2(1265.0, 1450.0)   # s range of the lights dying when set_dark() is not fed
const WAVE_ORIGIN := Vector2(-380.0, -340.0) # wall shader wave_origin (x, y): the lights wake behind the statue
const DARK_ORIGIN := Vector2(170.0, -985.0)  # the lights die toward the door
const BELL_MUTE := Vector2(820.0, 1012.0)    # no bell over the statue
const BELL_START_S := 140.0
const BELL_GAP := Vector2(35.0, 70.0)        # seconds between strikes
## [peak s, rise m, fall m, level, event]: the breathing quickens toward each reveal (period 9 s calm ..
## 5 s tense); once the named event has fired the zone is released (the held breath and the shaky exhale
## take over). M3 peaks at s 800: Main turns the head as soon as the diver has looked at the face (s > 790).
const TENSION := [[340.0, 120.0, 30.0, 0.8, "m1"], [612.0, 100.0, 30.0, 0.65, "m2"], [800.0, 120.0, 90.0, 0.95, "m3"],
	[1005.0, 110.0, 30.0, 0.75, "m4"], [1058.0, 25.0, 60.0, 0.7, "wall"], [1330.0, 100.0, 60.0, 0.6, ""],
	[1544.0, 120.0, 1.0, 0.9, ""]]
## the ending, seconds after on_end() (Main._door_lamp_fx stutters the door lamp from 0.6 s to 1.45 s)
const END_FLICKER_T := 0.6
const END_GASP_T := 0.75
const END_KNOCK_T := 2.4       # three knocks, 0.62 s apart
const END_SILENCE_T := 3.95    # hard silence: every voice stops ...
const END_BELL_T := 5.75       # ... for 1.8 s, then the deep bell under the closing number

# ============================== levels (dB) ==============================
const DIR := "res://assets/audio/"
const LOOPS := ["drone_shallow", "drone_mid", "drone_deep", "rumble", "surface", "hum"]
const LEVEL := {"drone_shallow": -0.5, "drone_mid": -2.5, "drone_deep": -1.5, "rumble": -5.0,
	"surface": -6.0, "hum": -7.0}   # loop volume at full layer gain
const BREATH_DB := -7.0
const BREATH_KIND_DB := {"calm_in": -3.0, "calm_out": 0.0, "tense_in": -3.0, "tense_out": 0.0,
	"sharp_in": -5.0, "shaky_out": 0.0}
const BREATH_FILES := {"calm_in": ["inhale_calm_1", "inhale_calm_2", "inhale_calm_3"],
	"calm_out": ["exhale_calm_1", "exhale_calm_2", "exhale_calm_3"],
	"tense_in": ["inhale_tense_1", "inhale_tense_2"], "tense_out": ["exhale_tense_1", "exhale_tense_2"],
	"sharp_in": ["inhale_sharp_1", "inhale_sharp_2"], "shaky_out": ["exhale_shaky_1", "exhale_shaky_2"]}
const EXHALE_STRENGTH := {"calm": 0.55, "tense": 0.75, "shaky": 1.0}
const CREAK_DB := [-9.0, -8.0, -7.0, -7.0]              # beats 2..5
const BELL_DB := Vector2(-24.0, -7.0)                   # far (start) .. near (the door)
const BELL_DEEP_DB := -1.0
const RELAY_DB := -2.0
const CLUNK_DB := 0.0
const KNOCK_DB := -14.7          # file peak -1.3 dBFS -> about -16 dBFS, dry
const FLICKER_DB := -16.0
const LAMP_DB := -14.0
const WHALE_DB := -4.0
const BUBBLES_DB := Vector2(-24.0, -18.0)               # occasional bursts / the entry splash
const DUCK_PAUSE_DB := -14.0
const SILENT := 0.00001
const ONE_SHOTS := ["sting_m1", "sting_m2", "stone_groan", "sting_m4", "wall_wake", "power_down",
	"whale_call", "knock", "flicker", "lamp_on", "bubbles", "relay_1", "relay_2", "relay_3", "relay_4",
	"clunk_1", "clunk_2", "clunk_3"]

enum Breath { REST, IN, GAP, OUT, HOLD }

var path: PathDef
var rng := RandomNumberGenerator.new()
var loops := {}       # name -> AudioStreamPlayer
var gain := {}        # name -> smoothed linear gain
var target := {}      # name -> target linear gain (set by update)
var streams := {}     # one-shot name -> AudioStream
var bell: AudioStreamPlayer3D
var bell_deep: AudioStreamPlayer3D
var whale: AudioStreamPlayer3D
var creak_players: Array[AudioStreamPlayer3D] = []
var creak_streams: Array[AudioStream] = []
var creak_next := 0
var pool3d: Array[AudioStreamPlayer3D] = []   # relays, clunks
var pool3d_next := 0
var score: Array[AudioStreamPlayer] = []      # stings
var score_next := 0
var misc: Array[AudioStreamPlayer] = []       # knock, flicker, lamp, bubbles
var misc_next := 0
var breath_in: AudioStreamPlayer
var breath_out: AudioStreamPlayer

var bus := {}         # name -> index
var lp_amb: AudioEffectLowPassFilter
var rv_amb: AudioEffectReverb
var rv_sfx: AudioEffectReverb
var lp_bell: AudioEffectLowPassFilter
var rv_bell: AudioEffectReverb
var lp_master: AudioEffectLowPassFilter
var lp_master_idx := 0
var rec: AudioEffectRecord
var rec_path := ""
var rec_log := PackedStringArray()

var started := false
var snapped := false
var fade_in := 3.0
var t_run := 0.0
var ended := false
var t_end := 0.0
var end_step := 0
var silenced := false
var paused := false
var pause_duck := 0.0
var s_now := 0.0
var s_prev := 0.0
var has_s := false
var v_est := 2.75
var depth_now := 0.0
var fired := {}           # event / sting name -> true
var ducks: Array = []     # {t0, bloom, depth}
var amb_lp_k := 1.0       # band-crossing low-pass dip (smoothed)
var band_db := 0.0
var bell_db := -30.0
var bell_next := -1.0
var block_until := -1.0   # no bell / creaks until this t_run (after a sting)
var creak_timer := 12.0
var bubble_timer := 60.0
var lamp_s := 432.0
var lamp_done := false
var wave_ext := 0.0
var wave_ext_t := -100.0
var wave_prev := 0.0
var dark_ext := 0.0
var dark_ext_t := -100.0
var dark_prev := 0.0
var relay_acc := 0.0
var clunk_acc := 0.0
var hum_pitch := 1.0
var whale_at := -1.0      # t_run when the far call plays (deferred out of a sting's bloom)
var whale_src: Node3D     # Main's leviathan, if there is one: the call comes from it

# breathing
var tension := 0.2
var ext_tension := -1.0
var aftershock := 0.0
var br_state := Breath.REST
var br_timer := 2.5
var br_kind := "calm"
var br_hold_at := -1.0
var br_hold_len := 0.0
var br_hold_next := false
var br_emit := -1.0
var br_emit_str := 0.0
var bp_virtual := 0.0
var bp_after := -1.0
var bp_slot := 0
var br_cycle := 0.0   # seconds spent in the current cycle's inhale + gap + exhale


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(p: PathDef) -> void:
	path = p
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.seed = 7741
	var ua := OS.get_cmdline_user_args()
	for i in ua.size():
		if ua[i] == "--audio-rec" and i + 1 < ua.size():
			rec_path = ua[i + 1]
			if rec_path.is_relative_path():
				rec_path = ProjectSettings.globalize_path("res://").path_join(rec_path)
	var cm: Dictionary = load("res://scripts/Config.gd").get_script_constant_map()
	lamp_s = float(cm.get("LAMP_ON_S", 432.0))
	_build_buses()
	for n in LOOPS:
		var pl := AudioStreamPlayer.new()
		pl.name = n
		pl.stream = _load(n, true)
		pl.bus = "Ambience"
		pl.volume_db = -80.0
		add_child(pl)
		loops[n] = pl
		gain[n] = 0.0
		target[n] = 0.0
	for n in ONE_SHOTS:
		var st := _load(n, false)
		if st:
			streams[n] = st
	for k in BREATH_FILES:
		for n: String in BREATH_FILES[k]:
			var st := _load(n, false)
			if st:
				streams[n] = st
	bell = _p3d("Bell", "Bell", Config.DOOR_POS + Vector3(0, 40, 0), "bell")
	bell.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	bell.panning_strength = 0.6
	bell.max_polyphony = 2
	bell.volume_db = bell_db
	bell_deep = _p3d("BellDeep", "Bell", Config.DOOR_POS + Vector3(0, 20, 0), "bell_deep")
	bell_deep.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	bell_deep.panning_strength = 0.4
	bell_deep.volume_db = BELL_DEEP_DB
	whale = _p3d("Whale", "Score", Vector3.ZERO, "")
	whale.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	whale.panning_strength = 0.5
	for i in 4:
		var st := _load("creak_%d" % (i + 1), false)
		if st:
			creak_streams.append(st)
	for i in 2:
		var c := _p3d("Creak%d" % i, "SFX", Vector3.ZERO, "")
		c.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		c.unit_size = 100.0
		c.max_db = 0.0
		c.attenuation_filter_cutoff_hz = 2200.0
		c.attenuation_filter_db = -18.0
		creak_players.append(c)
	for i in 6:
		var r := _p3d("Relay%d" % i, "SFX", Vector3.ZERO, "")
		r.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		r.unit_size = 400.0
		r.max_db = -2.0
		r.max_distance = 8000.0
		r.attenuation_filter_cutoff_hz = 2500.0
		r.attenuation_filter_db = -12.0
		pool3d.append(r)
	for i in 3:
		score.append(_p2d("Score%d" % i, "Score"))
	for i in 4:
		misc.append(_p2d("Misc%d" % i, "Dry"))
	breath_in = _p2d("BreathIn", "Breath")
	breath_out = _p2d("BreathOut", "Breath")


func start(fade_time: float) -> void:
	fade_in = maxf(fade_time, 0.05)
	t_run = 0.0
	started = true
	snapped = false
	for n in loops:
		var pl: AudioStreamPlayer = loops[n]
		if pl.stream:
			pl.play(rng.randf() * pl.stream.get_length() * 0.9)
	creak_timer = rng.randf_range(8.0, 16.0)
	bubble_timer = rng.randf_range(60.0, 110.0)
	br_timer = rng.randf_range(1.5, 3.0)
	if rec:
		rec.set_recording_active(true)


func update(s: float, cam: Vector3, dt: float) -> void:
	if not started or path == null:
		return
	if bp_after >= 0.0:
		bp_virtual = bp_after
		bp_after = -1.0
	s_now = s
	if has_s and dt > 0.0:
		var v := (s - s_prev) / dt
		if absf(v) < 40.0:
			v_est = lerpf(v_est, v, 1.0 - exp(-dt / 1.5))
	s_prev = s
	has_s = true
	var bs := path.beat_s
	var depth := clampf(-cam.y, 0.0, 1100.0)
	depth_now = depth
	var beat := _beat(s)
	# drones crossfade by depth (equal power); the door beat sinks to a remnant
	var w_sh := 1.0 - smoothstep(60.0, 80.0, depth)
	var w_deep := smoothstep(380.0, 450.0, depth)
	var w_mid := (1.0 - w_sh) * (1.0 - w_deep)
	var quiet := smoothstep(bs[5] - 30.0, bs[5] + 40.0, s)
	var dr := lerpf(1.0, 0.5, quiet)
	target["drone_shallow"] = sqrt(w_sh) * dr
	target["drone_mid"] = sqrt(w_mid) * dr
	target["drone_deep"] = sqrt(w_deep) * dr
	target["surface"] = 1.0 - smoothstep(4.0, 32.0, depth)
	var rise := 0.55 * smoothstep(bs[3] + 40.0, bs[3] + 200.0, s) + 0.45 * smoothstep(bs[4] - 20.0, bs[4] + 90.0, s)
	target["rumble"] = rise * (1.0 - smoothstep(bs[5] - 45.0, bs[5] + 30.0, s))
	# the wall's machinery: on after the generator has spun up, sagging as the lights die
	var wave := _wave(s)
	var dark := _dark(s)
	target["hum"] = smoothstep(0.02, 0.2, wave) * (1.0 - 0.7 * dark)
	hum_pitch = 1.0 - 0.06 * dark
	if not snapped:
		snapped = true
		for n in loops:
			gain[n] = target[n]
		for e in EVENTS:
			if EVENTS[e] >= 0.0 and s > float(EVENTS[e]) + 2.0:
				fired[e] = true
		lamp_done = s > lamp_s
		wave_prev = wave
		dark_prev = dark
		if s < 10.0:
			bubble_timer = 1.2   # the entry splash
	# buses follow depth: darker and bigger the deeper we go; a soft low-pass dip through each fog band
	var k := clampf(depth / 1000.0, 0.0, 1.0)
	var prog := clampf(s / maxf(path.length, 1.0), 0.0, 1.0)
	var band := 0.0
	for b in Config.BANDS:
		band = maxf(band, exp(-0.5 * pow((cam.y - float(b[0])) / float(b[1]), 2.0)))
	var a := 1.0 - exp(-dt / 0.6)
	amb_lp_k = lerpf(amb_lp_k, lerpf(1.0, 0.45, band), a)
	band_db = lerpf(band_db, -2.0 * band, a)
	lp_amb.cutoff_hz = maxf(6000.0 * pow(0.12, k) * amb_lp_k, 550.0)   # keep the harmonics phones need
	rv_amb.room_size = lerpf(0.45, 0.9, k)
	rv_amb.wet = lerpf(0.12, 0.28, k)
	rv_amb.dry = lerpf(0.95, 0.85, k)
	rv_sfx.room_size = lerpf(0.8, 0.92, k)
	rv_sfx.wet = lerpf(0.3, 0.42, k)
	lp_bell.cutoff_hz = lerpf(1300.0, 5000.0, prog * prog)
	rv_bell.wet = lerpf(0.6, 0.3, prog)
	rv_bell.dry = lerpf(0.3, 0.9, prog)
	bell_db = lerpf(BELL_DB.x, BELL_DB.y, pow(prog, 0.85))
	tension = _tension(s, depth)
	aftershock *= exp(-dt / 14.0)
	_breath(dt)
	if ended:
		return
	_events(s, cam)
	_bell_update(s)
	_waves(cam, wave, dark, dt)
	if whale_at >= 0.0 and t_run >= whale_at:
		if _event_soon(20.0) or t_run < block_until - 5.0 or br_state == Breath.HOLD:
			whale_at = t_run + 1.0   # wait until the sting has bloomed and settled
		else:
			whale_at = -1.0
			_play_whale()
	if not lamp_done and s > lamp_s:
		lamp_done = true
		one_shot("lamp_on")
	if beat >= 1 and beat <= 4 and not creak_streams.is_empty():
		creak_timer -= dt
		if creak_timer <= 0.0:
			if t_run < block_until or br_state == Breath.HOLD or _event_soon(10.0):
				creak_timer = 4.0
			else:
				creak_timer = rng.randf_range(14.0, 30.0)
				_creak(beat, cam)
	bubble_timer -= dt
	if bubble_timer <= 0.0:
		bubble_timer = rng.randf_range(60.0, 120.0)
		var lv := BUBBLES_DB.y if s < 10.0 else rng.randf_range(BUBBLES_DB.x - 3.0, BUBBLES_DB.x)
		_misc("bubbles", lv, "Breath")


## Compatibility for Main._breathe(): crosses Main.EXHALES (2.25 / 6.85) exactly once per exhale. When
## `exhaled` is connected it stays constant, so the old clock emits nothing.
func breath_pos() -> float:
	if not exhaled.get_connections().is_empty():
		return 0.0
	return bp_virtual


func sting(name: String) -> void:
	if name == "stone_groan":
		name = "m3"
	if not STINGS.has(name) or fired.get(name + "_played", false) or ended:
		return
	fired[name] = true
	fired[name + "_played"] = true
	var st: Dictionary = STINGS[name]
	var f: String = st["file"]
	var tail := 12.0
	if streams.has(f):
		tail = maxf(tail, (streams[f] as AudioStream).get_length() - float(st["lead"]) - 3.0)
		var pl: AudioStreamPlayer = score[score_next]
		score_next = (score_next + 1) % score.size()
		pl.stream = streams[f]
		pl.volume_db = float(st["db"])
		pl.play()
	var lead := float(st["lead"])
	var bloom := t_run + lead
	if float(st["duck"]) > 0.0:
		ducks.append({"t0": t_run, "bloom": bloom, "depth": float(st["duck"])})
	if float(st["hold"]) > 0.0:
		hold_breath(float(st["hold"]), maxf(lead - 1.0, 0.0))
	block_until = maxf(block_until, bloom + tail)   # no bell or creak over the sting's tail
	_log("sting %s (bloom at %.2f)" % [name, bloom])


func one_shot(name: String) -> void:
	if name == "stone_groan" or STINGS.has(name):
		sting(name)
		return
	match name:
		"whale", "whale_call":
			if fired.get("whale_played", false) or not streams.has("whale_call"):
				return
			fired["whale"] = true
			fired["whale_played"] = true
			whale_at = t_run   # played as soon as no sting is swelling or blooming
		"bell":
			_strike()
		"knock":
			_misc("knock", KNOCK_DB, "Dry")
		"flicker":
			_misc("flicker", FLICKER_DB, "Dry")
		"lamp_on":
			_misc("lamp_on", LAMP_DB, "Breath")
		"bubbles":
			_misc("bubbles", BUBBLES_DB.x, "Breath")
		_:
			if streams.has(name):
				_misc(name, -6.0, "Dry")
	_log("one_shot " + name)


func _play_whale() -> void:
	whale_src = get_parent().get_node_or_null("World/Leviathan") as Node3D if get_parent() else null
	if whale_src:
		whale.global_position = whale_src.global_position
	else:
		whale.global_position = path.pos(s_now) - path.right(s_now) * 380.0 + Vector3(0, -60, 0)
	whale.stream = streams["whale_call"]
	whale.volume_db = WHALE_DB
	whale.play()
	_log("whale")


func set_tension(x: float) -> void:
	ext_tension = x


func hold_breath(seconds: float, delay := 0.0) -> void:
	br_hold_at = t_run + maxf(delay, 0.0)
	br_hold_len = seconds


func set_wave(x: float) -> void:
	wave_ext = x
	wave_ext_t = t_run


func set_dark(x: float) -> void:
	dark_ext = x
	dark_ext_t = t_run


func on_end() -> void:
	if ended:
		return
	ended = true
	t_end = 0.0
	end_step = 0
	hold_breath(9999.0, END_GASP_T)
	_log("end")


func set_paused(p: bool) -> void:
	paused = p


func _process(delta: float) -> void:
	if not started:
		return
	t_run += delta
	if ended:
		t_end += delta
		_end_steps()
	var a := 1.0 - exp(-delta / 1.2)
	for n in loops:
		var g: float = lerpf(gain[n], target[n], a)
		gain[n] = g
		var pl: AudioStreamPlayer = loops[n]
		pl.volume_db = float(LEVEL[n]) + linear_to_db(maxf(g, SILENT))
	var hp: AudioStreamPlayer = loops["hum"]
	hp.pitch_scale = hum_pitch
	if is_instance_valid(whale_src) and whale.playing:
		whale.global_position = whale_src.global_position
	bell.volume_db = bell_db
	# ambience dips before each bloom ("the silence before the reveal") and comes back after it
	var duck_db := 0.0
	var keep: Array = []
	for d: Dictionary in ducks:
		var t0: float = d["t0"]
		var bl: float = d["bloom"]
		if t_run > bl + 4.5:
			continue
		keep.append(d)
		var w := smoothstep(t0, t0 + maxf(1.0, (bl - t0) * 0.55), t_run) * (1.0 - smoothstep(bl + 0.8, bl + 4.0, t_run))
		duck_db = minf(duck_db, -float(d["depth"]) * w)
	ducks = keep
	var end_db := 0.0
	if ended:
		end_db = linear_to_db(maxf(1.0 - 0.9 * smoothstep(0.0, END_KNOCK_T + 0.2, t_end), SILENT))
	AudioServer.set_bus_volume_db(bus["Ambience"], duck_db + band_db + end_db)
	AudioServer.set_bus_volume_db(bus["SFX"], duck_db * 0.6 + end_db)
	AudioServer.set_bus_volume_db(bus["Bell"], duck_db * 0.8)
	# master: fade in from silence, the hard silence at the end, pause duck with a darker low-pass
	pause_duck = move_toward(pause_duck, 1.0 if paused else 0.0, delta / 0.35)
	var gm := smoothstep(0.0, fade_in, t_run)
	if ended and t_end >= END_SILENCE_T and t_end < END_BELL_T:
		gm = 0.0
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(gm, SILENT)) + DUCK_PAUSE_DB * pause_duck)
	lp_master.cutoff_hz = lerpf(18000.0, 900.0, pause_duck)
	AudioServer.set_bus_effect_enabled(0, lp_master_idx, pause_duck > 0.001)


func _exit_tree() -> void:
	_save_rec()
	# stop every voice and give the mixer a moment to release them (avoids leak reports on quit)
	for c in get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()
		elif c is AudioStreamPlayer3D:
			(c as AudioStreamPlayer3D).stop()
	OS.delay_msec(150)


# ------------------------------------------------------------------ the ending
func _end_steps() -> void:
	if end_step == 0 and t_end >= END_FLICKER_T:
		end_step = 1
		one_shot("flicker")
	if end_step == 1 and t_end >= END_KNOCK_T:
		end_step = 2
		one_shot("knock")
	if end_step == 2 and t_end >= END_SILENCE_T:
		end_step = 3
		_hard_silence()
	if end_step == 3 and t_end >= END_BELL_T:
		end_step = 4
		AudioServer.set_bus_mute(bus["Bell"], false)
		if bell_deep.stream:
			bell_deep.play()
		_log("bell_deep")


func _hard_silence() -> void:
	silenced = true
	for c in get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()
		elif c is AudioStreamPlayer3D:
			(c as AudioStreamPlayer3D).stop()
	for b in ["Ambience", "SFX", "Score", "Breath", "Dry", "Bell"]:
		AudioServer.set_bus_mute(bus[b], true)   # also drops the reverb tails
	br_state = Breath.HOLD
	br_timer = 9999.0
	_log("silence")


# ------------------------------------------------------------------ scored moments
func _ev(name: String) -> float:
	return float(EVENTS.get(name, -1.0))


func _lead(name: String) -> float:
	return float(STINGS[name]["lead"]) if STINGS.has(name) else 0.0


## True when an automatic event is due within `secs` seconds (bells and creaks keep out of its way).
func _event_soon(secs: float) -> bool:
	for e in EVENTS:
		var es := _ev(e)
		if es < 0.0 or fired.get(e, false):
			continue
		if (es - s_now) / maxf(v_est, 0.3) - _lead(e) < secs and es > s_now - 2.0:
			return true
	return false


func _events(s: float, _cam: Vector3) -> void:
	for e in EVENTS:
		var es := _ev(e)
		if es < 0.0 or fired.get(e, false):
			continue
		if s > es + 6.0:
			fired[e] = true   # walked past it (or jumped there)
			continue
		var eta := (es - s) / maxf(v_est, 0.2)
		if eta <= _lead(e):
			fired[e] = true
			if STINGS.has(e):
				sting(e)
			elif e == "door_bell":
				_strike()
				_log("door bell")
			else:
				one_shot(e)


func _tension(s: float, depth: float) -> float:
	var t := lerpf(0.12, 0.4, clampf(depth / 1000.0, 0.0, 1.0))
	for z in TENSION:
		if str(z[4]) != "" and fired.get(str(z[4]) + "_played", false):
			continue
		var d := s - float(z[0])
		var w := smoothstep(-float(z[1]), 0.0, d) if d <= 0.0 else 1.0 - smoothstep(0.0, float(z[2]), d)
		t = maxf(t, float(z[3]) * w)
	t = maxf(t, aftershock)
	if ext_tension >= 0.0:
		t = maxf(t, ext_tension)
	return clampf(t, 0.0, 1.0)


# ------------------------------------------------------------------ breathing
func _breath(dt: float) -> void:
	br_timer -= dt
	if br_emit >= 0.0:
		br_emit -= dt
		if br_emit < 0.0:
			_exhaled(br_emit_str)
	match br_state:
		Breath.REST:
			if br_hold_at >= 0.0 and t_run >= br_hold_at:
				br_hold_at = -1.0
				br_hold_next = true
				_inhale("sharp")
			elif br_timer <= 0.0 and not (br_hold_at >= 0.0 and br_hold_at - t_run < 3.8):
				br_kind = "tense" if rng.randf() < smoothstep(0.35, 0.75, tension) else "calm"
				_inhale(br_kind)
		Breath.IN:
			if br_hold_at >= 0.0 and br_hold_at <= t_run + br_timer + 0.8:
				br_hold_at = -1.0
				br_hold_next = true
			if br_timer <= 0.0:
				if br_hold_next:
					br_hold_next = false
					br_state = Breath.HOLD
					br_timer = br_hold_len
				else:
					br_state = Breath.GAP
					br_timer = lerpf(0.42, 0.16, tension) * rng.randf_range(0.85, 1.15)
		Breath.GAP:
			if br_hold_at >= 0.0 and t_run >= br_hold_at - 0.3:
				br_hold_at = -1.0   # lungs are full already: just stop breathing
				br_state = Breath.HOLD
				br_timer = br_hold_len
			elif br_timer <= 0.0:
				_exhale(br_kind)
		Breath.HOLD:
			if br_timer <= 0.0:
				_exhale("shaky")
				aftershock = maxf(aftershock, 0.7)
		Breath.OUT:
			if br_timer <= 0.0:
				br_state = Breath.REST
				var period := lerpf(9.0, 5.0, tension) * rng.randf_range(0.9, 1.1)
				br_timer = maxf(0.4, period - br_cycle)



func _inhale(kind: String) -> void:
	var dur := _breath_play(breath_in, kind + "_in")
	br_state = Breath.IN
	br_timer = maxf(dur - 0.2, 0.3)
	br_cycle = br_timer
	if kind == "sharp":
		_log("breath hold %.1f s" % br_hold_len)


func _exhale(kind: String) -> void:
	var dur := _breath_play(breath_out, kind + "_out")
	br_state = Breath.OUT
	br_timer = maxf(dur - 0.75, 0.5)
	br_cycle += br_timer + 0.3
	br_emit = 0.12
	br_emit_str = clampf(float(EXHALE_STRENGTH.get(kind, 0.6)) + rng.randf_range(-0.05, 0.05), 0.0, 1.0)


func _breath_play(pl: AudioStreamPlayer, key: String) -> float:
	var names: Array = BREATH_FILES[key]
	var n: String = names[rng.randi() % names.size()]
	if not streams.has(n) or silenced:
		return 1.5
	pl.stream = streams[n]
	pl.pitch_scale = rng.randf_range(0.97, 1.03)
	pl.volume_db = BREATH_DB + float(BREATH_KIND_DB[key])
	pl.play()
	return (pl.stream as AudioStream).get_length() / pl.pitch_scale


func _exhaled(strength: float) -> void:
	exhaled.emit(strength)
	if bp_slot == 0:
		bp_virtual = 2.3
		bp_after = 6.8
	else:
		bp_virtual = 6.9
		bp_after = -1.0
	bp_slot = 1 - bp_slot
	if rec:
		_log("exhale %.2f" % strength)


# ------------------------------------------------------------------ bell
func _bell_update(s: float) -> void:
	if s < BELL_START_S or fired.get("door_bell", false):
		return
	if bell_next < 0.0:
		bell_next = t_run + rng.randf_range(10.0, 22.0)
	if t_run < bell_next:
		return
	var muted := (s > BELL_MUTE.x and s < BELL_MUTE.y) or t_run < block_until or br_state == Breath.HOLD
	if muted or _event_soon(14.0):
		bell_next = t_run + 6.0
		return
	_strike()
	bell_next = t_run + rng.randf_range(BELL_GAP.x, BELL_GAP.y)


func _strike() -> void:
	if bell.stream and not silenced:
		bell.play()
		_log("bell %.1f dB" % bell_db)


# ------------------------------------------------------------------ the wall waking up and dying
func _wave(s: float) -> float:
	return wave_ext if t_run - wave_ext_t < 0.5 else smoothstep(WALL_WAVE.x, WALL_WAVE.y, s)


func _dark(s: float) -> float:
	return dark_ext if t_run - dark_ext_t < 0.5 else smoothstep(DARK_WAVE.x, DARK_WAVE.y, s)


func _waves(cam: Vector3, wave: float, dark: float, dt: float) -> void:
	if dt <= 0.0:
		return
	# relays click on where the porthole wave front is (about 60 over the whole wave)
	var dw := maxf(wave - wave_prev, 0.0) / dt
	wave_prev = wave
	if wave > 0.0 and wave < 0.98:
		relay_acc += dt * 1.6 * clampf(dw / 0.025, 0.0, 2.0) * rng.randf_range(0.4, 1.6)
		while relay_acc >= 1.0:
			relay_acc -= 1.0
			var wv := clampf((wave - 0.3) / 0.7, 0.0, 1.0)          # the shader's wave front radius
			_wall_click("relay_%d" % rng.randi_range(1, 4), maxf(480.0 * wv + 2520.0 * pow(wv, 10.0), 30.0),
				RELAY_DB + rng.randf_range(-5.0, 0.0), 420.0, cam, WAVE_ORIGIN, true)
	# heavy contactors drop as the darkness closes in toward the door (about 25, coming nearer)
	var dd := maxf(dark - dark_prev, 0.0) / dt
	dark_prev = dark
	if dark > 0.0 and dark < 0.99:
		clunk_acc += dt * 0.7 * clampf(dd / 0.02, 0.0, 2.0) * rng.randf_range(0.4, 1.6)
		while clunk_acc >= 1.0:
			clunk_acc -= 1.0
			# the wall shader's death front (Beat05 wall.gdshader: F = -45 + 1200 (1-D)^2.2 + 1900 (1 - smoothstep(0, 0.05, D)))
			var front := -45.0 + 1200.0 * pow(1.0 - dark, 2.2) + 1900.0 * (1.0 - smoothstep(0.0, 0.05, dark))
			_wall_click("clunk_%d" % rng.randi_range(1, 3), maxf(front, 40.0), CLUNK_DB + rng.randf_range(-4.0, 0.0), 220.0, cam,
				DARK_ORIGIN, false)


func _wall_click(n: String, radius: float, db: float, unit: float, cam: Vector3, origin: Vector2, ring: bool) -> void:
	if not streams.has(n):
		return
	var th := rng.randf_range(0.0, TAU) if ring else rng.randf_range(0.05, PI - 0.05)
	var x := origin.x + radius * cos(th)
	var y := clampf(origin.y + radius * sin(th) / 1.5, -980.0, -40.0)
	var p := pool3d[pool3d_next]
	pool3d_next = (pool3d_next + 1) % pool3d.size()
	p.global_position = Vector3(x, y, Config.WALL_Z + x * x / 5000.0)
	if p.global_position.distance_to(cam) < 25.0:
		p.global_position = cam + (p.global_position - cam).normalized() * 25.0
	p.unit_size = unit
	p.stream = streams[n]
	p.pitch_scale = rng.randf_range(0.9, 1.1)
	p.volume_db = db
	p.play()


# ------------------------------------------------------------------ helpers
func _misc(n: String, db: float, bus_name: String) -> void:
	if not streams.has(n) or silenced:
		return
	var pl: AudioStreamPlayer = misc[misc_next]
	misc_next = (misc_next + 1) % misc.size()
	pl.bus = bus_name
	pl.stream = streams[n]
	pl.volume_db = db
	pl.play()


func _creak(beat: int, cam: Vector3) -> void:
	var dir := Vector3.ZERO
	match beat:
		1:   # the nearest wreck
			var best := INF
			for ship in [Config.SHIP_TRAWLER, Config.SHIP_CARGO, Config.SHIP_TANKER, Config.SHIP_LINER, Config.SHIP_SMALL]:
				var sp: Vector3 = ship["pos"]
				var ln: float = ship["length"]
				var h := Vector2(sp.x - cam.x, sp.z - cam.z)
				var d := h.length() - 0.4 * ln
				if d < best:
					best = d
					dir = Vector3(h.x, -0.25 * h.length(), h.y)
		2:   # somewhere in the forest of submarines
			var ang := rng.randf() * TAU
			dir = Vector3(cos(ang), rng.randf_range(-0.5, 0.15), sin(ang))
		3:   # the statue's chest
			dir = Config.STATUE_ORIGIN + Vector3(0, 350, 0) - cam
		_:   # the wall
			dir = Vector3(cam.x + rng.randf_range(-150.0, 150.0), cam.y + rng.randf_range(-60.0, 20.0), Config.WALL_Z) - cam
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	var pl := creak_players[creak_next]
	creak_next = (creak_next + 1) % creak_players.size()
	pl.position = cam + dir.normalized() * rng.randf_range(60.0, 250.0)
	pl.stream = creak_streams[rng.randi() % creak_streams.size()]
	pl.pitch_scale = rng.randf_range(0.85, 1.08)
	pl.volume_db = float(CREAK_DB[clampi(beat - 1, 0, 3)])
	pl.play()
	_log("creak")


func _beat(s: float) -> int:
	var b := 0
	for i in path.beat_s.size():
		if s >= path.beat_s[i] - 0.01:
			b = i
	return b


func _log(msg: String) -> void:
	if rec:
		rec_log.append("%.3f\t%.1f\t%s" % [t_run, s_now, msg])


func _save_rec() -> void:
	if rec == null or rec_path == "":
		return
	rec.set_recording_active(false)
	_log("rec_end")
	var w := rec.get_recording()
	if w:
		var err := w.save_to_wav(rec_path)
		print("AudioDirector: recorded %.1f s to %s (%s)" % [w.get_length(), rec_path, error_string(err)])
		var f := FileAccess.open(rec_path + ".events.txt", FileAccess.WRITE)
		if f:
			f.store_string("\n".join(rec_log) + "\n")
			f.close()
	rec = null


func _load(n: String, loop: bool) -> AudioStream:
	if not ResourceLoader.exists(DIR + n + ".wav"):
		push_warning("AudioDirector: missing %s.wav" % n)
		return null
	var st := load(DIR + n + ".wav") as AudioStreamWAV
	if st and loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(round(st.get_length() * st.mix_rate))
	return st


func _p2d(n: String, bus_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = n
	p.bus = bus_name
	add_child(p)
	return p


func _p3d(n: String, bus_name: String, pos: Vector3, stream_name: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = n
	p.bus = bus_name
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	if stream_name != "":
		p.stream = _load(stream_name, false)
	add_child(p)
	p.position = pos
	return p


func _bus(n: String) -> int:
	var idx := AudioServer.get_bus_index(n)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, n)
	AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_mute(idx, false)
	while AudioServer.get_bus_effect_count(idx) > 0:
		AudioServer.remove_bus_effect(idx, 0)
	bus[n] = idx
	return idx


func _reverb(room: float, damp: float, wet: float, dry: float, predelay: float, fb: float) -> AudioEffectReverb:
	var r := AudioEffectReverb.new()
	r.room_size = room
	r.damping = damp
	r.wet = wet
	r.dry = dry
	r.spread = 0.9
	r.hipass = 0.05
	r.predelay_msec = predelay
	r.predelay_feedback = fb
	return r


func _build_buses() -> void:
	var amb := _bus("Ambience")
	lp_amb = AudioEffectLowPassFilter.new()
	lp_amb.cutoff_hz = 6000.0
	lp_amb.resonance = 0.4
	AudioServer.add_bus_effect(amb, lp_amb)
	rv_amb = _reverb(0.45, 0.6, 0.12, 0.95, 80.0, 0.3)
	AudioServer.add_bus_effect(amb, rv_amb)
	var sfx := _bus("SFX")
	rv_sfx = _reverb(0.8, 0.45, 0.3, 0.75, 140.0, 0.45)
	AudioServer.add_bus_effect(sfx, rv_sfx)
	var bl := _bus("Bell")
	lp_bell = AudioEffectLowPassFilter.new()
	lp_bell.cutoff_hz = 1300.0
	lp_bell.resonance = 0.3
	AudioServer.add_bus_effect(bl, lp_bell)
	rv_bell = _reverb(0.95, 0.55, 0.6, 0.3, 160.0, 0.5)
	AudioServer.add_bus_effect(bl, rv_bell)
	_bus("Score")      # stings and the far call carry their own reverb
	_bus("Breath")     # inside the mask: dry and close
	_bus("Dry")        # the knocks, the lamp
	AudioServer.set_bus_mute(0, false)
	while AudioServer.get_bus_effect_count(0) > 0:
		AudioServer.remove_bus_effect(0, 0)
	lp_master = AudioEffectLowPassFilter.new()
	lp_master.cutoff_hz = 18000.0
	lp_master.resonance = 0.3
	AudioServer.add_bus_effect(0, lp_master)
	lp_master_idx = 0
	AudioServer.set_bus_effect_enabled(0, lp_master_idx, false)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.2      # sample ceiling a little under -1 so inter-sample peaks stay below -1 dBTP
	lim.pre_gain_db = 0.0
	lim.release = 0.12
	AudioServer.add_bus_effect(0, lim)
	if rec_path != "":
		rec = AudioEffectRecord.new()
		rec.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(0, rec)
	AudioServer.set_bus_volume_db(0, -80.0)
