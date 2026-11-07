extends CanvasLayer
## Black fades, title card, one controls hint, the closing line and the minimal pause overlay.

signal resume_pressed
signal quit_pressed

var black: ColorRect
var title: Label
var hint: Label
var end_line: Label
var pause_box: Control
var _hint_tween: Tween
var _title_tween: Tween
var _hint_on_ms := -1      # Time.get_ticks_msec() when the scheduled hint began to fade in (< 0: not yet on screen)

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	black = ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	title = _label("P E L A G I C", 54, 0.0, 0.0, 22)
	hint = _label("mouse  look      W / S  glide      Shift  faster      C  cinematic      Esc  pause", 17, 0.0, 0.40, 3)
	end_line = _label("", 30, 0.0, 0.0, 10)
	_build_pause()

func _font(spacing: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.spacing_glyph = spacing
	f.variation_embolden = -0.35
	return f

func _label(text: String, size: int, alpha: float, y_offset: float, spacing: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font = _font(spacing)
	ls.font_size = size
	ls.font_color = Color(0.93, 0.97, 1.0)
	l.label_settings = ls
	l.modulate.a = alpha
	l.position.y = y_offset * 1080.0
	add_child(l)
	return l

func _build_pause() -> void:
	pause_box = Control.new()
	pause_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_box.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0.02, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_box.add_child(dim)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	vb.position = Vector2(-90, -50)
	vb.custom_minimum_size = Vector2(180, 100)
	pause_box.add_child(vb)
	for t in ["Resume", "Quit"]:
		var b := Button.new()
		b.text = t
		b.flat = true
		b.add_theme_font_override("font", _font(6))
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(func(): (resume_pressed if t == "Resume" else quit_pressed).emit())
		vb.add_child(b)
	add_child(pause_box)

func show_pause(on: bool) -> void:
	pause_box.visible = on

## Title card timing (seconds from the start of the fade-in): it rises out of the dark as the picture appears, is
## fully legible over the faded-in opening shot for about four seconds while the operator still holds the hull, and
## dissolves as the gaze begins to leave the surface (the first gaze cue ramps out at 7-22 s).
const TITLE_START := 1.2
const TITLE_IN := 1.8
const TITLE_FULL := 4.0
const TITLE_OUT := 2.5
## The controls hint (manual start only) rises at the lower edge as the title begins to dissolve: the player learns
## the keys right after the title, and the two never compete for the centre of the frame.
const HINT_START := TITLE_START + TITLE_IN + TITLE_FULL
## A hint that has appeared stays readable at least this long, even if the player is already moving the mouse.
const HINT_MIN_READ := 3.0

func fade_in(cinematic: bool, show_title := true) -> void:
	var tw := create_tween()
	tw.tween_property(black, "color:a", 0.0, Config.FADE_IN).set_trans(Tween.TRANS_SINE)
	if show_title:   # a mid-path start (QA --start-at) skips the title card
		_title_tween = create_tween()
		_title_tween.tween_interval(TITLE_START)
		_title_tween.tween_property(title, "modulate:a", 0.9, TITLE_IN).set_trans(Tween.TRANS_SINE)
		_title_tween.tween_interval(TITLE_FULL)
		_title_tween.tween_property(title, "modulate:a", 0.0, TITLE_OUT).set_trans(Tween.TRANS_SINE)
	if not cinematic:
		start_hint(HINT_START if show_title else 2.8)

## QA (Harness): drop the title card at once when a tour or a capture window jumps away from the opening, so frames of
## later stops never carry it. Returns true if a title was still on screen or still to come.
func skip_title() -> bool:
	var was := title.modulate.a > 0.0 or (_title_tween != null and _title_tween.is_valid())
	if _title_tween and _title_tween.is_valid():
		_title_tween.kill()
	_title_tween = null
	title.modulate.a = 0.0
	return was

## Schedules the controls hint `delay` seconds from now: it fades in, holds and fades out on its own.
func start_hint(delay := HINT_START) -> void:
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_on_ms = -1
	_hint_tween = create_tween()
	_hint_tween.tween_interval(delay)
	_hint_tween.tween_callback(func(): _hint_on_ms = Time.get_ticks_msec())
	_hint_tween.tween_property(hint, "modulate:a", 0.7, 1.0)
	_hint_tween.tween_interval(Config.HINT_TIME - 1.0)
	_hint_tween.tween_property(hint, "modulate:a", 0.0, 1.5)

## Main calls this on the player's first input (a key, or the first mouse move). A hint still waiting for the title is
## left to appear: the player has touched the mouse but does not know the keys yet; it then fades out on its own. A
## hint already on screen fades out once it has been readable for HINT_MIN_READ. force (the ending) hides it at once.
func hide_hint(force := false) -> void:
	var live := _hint_tween != null and _hint_tween.is_valid()
	if live and _hint_on_ms < 0 and not force:
		return
	if live:
		_hint_tween.kill()
	_hint_tween = null
	if hint.modulate.a <= 0.0:
		return
	var shown := 1e9 if (force or _hint_on_ms < 0) else (Time.get_ticks_msec() - _hint_on_ms) / 1000.0
	_hint_tween = create_tween()
	if shown < 1.0:     # still fading in: finish the fade-in first
		_hint_tween.tween_property(hint, "modulate:a", 0.7, 1.0 - shown)
	if shown < HINT_MIN_READ:
		_hint_tween.tween_interval(HINT_MIN_READ - maxf(shown, 1.0))
	_hint_tween.tween_property(hint, "modulate:a", 0.0, 0.8)

## The ending, from the moment the diver comes to rest: hold the final still image (the float in the upper third, its
## lamp flashing) for Config.END_HOLD, fade to black, show the depth line, then free the mouse and leave the game
## (quit_pressed, which Main connects to Game.quit) instead of sitting on a silent black screen.
func ending(depth_m: int) -> void:
	hide_hint(true)
	end_line.text = "%d m" % depth_m
	print("PELAGIC end: at rest, holding the final image %.1f s (ticks %.2f s)" % [Config.END_HOLD, Time.get_ticks_msec() / 1000.0])
	var tw := create_tween()
	tw.tween_interval(Config.END_HOLD)
	tw.tween_callback(func(): print("PELAGIC end: fade to black (ticks %.2f s)" % (Time.get_ticks_msec() / 1000.0)))
	tw.tween_property(black, "color:a", 1.0, Config.END_FADE).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(1.5)
	tw.tween_callback(_end_line_shown)
	tw.tween_property(end_line, "modulate:a", 0.85, 2.5)
	tw.tween_interval(5.0)
	tw.tween_property(end_line, "modulate:a", 0.0, 3.0)
	tw.tween_interval(Config.END_QUIT_DELAY)
	tw.tween_callback(_end_quit)

func _end_line_shown() -> void:
	print("PELAGIC end: depth line, mouse free (ticks %.2f s)" % (Time.get_ticks_msec() / 1000.0))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _end_quit() -> void:
	print("PELAGIC end: quit (ticks %.2f s)" % (Time.get_ticks_msec() / 1000.0))
	quit_pressed.emit()
