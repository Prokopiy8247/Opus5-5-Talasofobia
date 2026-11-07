extends CanvasLayer
## Fades, title card, controls hint, end line, pause overlay, depth vignette + fine grain. Default font only.

var _fade: ColorRect
var _vignette: ColorRect
var _grain: ColorRect
var _title: Label
var _hint: Label
var _end: Label
var _pause: Control
var _hint_alive := false
var _ended := false
var _tweens := {}


func _init() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_vignette = _rect(Color(0, 0, 0, 0))
	_vignette.material = _shader_mat("res://shaders/vignette.gdshader")
	_grain = _rect(Color(1, 1, 1, 1))
	_grain.material = _shader_mat("res://shaders/grain.gdshader")
	_fade = _rect(Color(0, 0, 0, 1))
	_title = _label("N A D I R", 46, Color(0.82, 0.88, 0.93, 0.0), 22)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hint = _label("mouse  look        W / S  move        Shift  brisk        C  cinematic        Esc  pause", 17, Color(0.75, 0.82, 0.88, 0.0), 3)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position.y -= 70.0
	_end = _label("", 30, Color(0.78, 0.84, 0.9, 0.0), 6)   # tighter: "1 556 m" must read as one number
	_end.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_build_pause()


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(r)
	return r


func _shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


func _label(text: String, size: int, col: Color, spacing: int) -> Label:
	var l := Label.new()
	l.text = text
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.spacing_glyph = spacing
	fv.variation_embolden = -0.35
	l.add_theme_font_override("font", fv)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(l)
	return l


func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	add_child(_pause)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 26)
	_pause.add_child(box)
	for item in [["resume", _on_resume], ["quit", _on_quit]]:
		var b := Button.new()
		b.text = item[0]
		b.flat = true
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.spacing_glyph = 8
		fv.variation_embolden = -0.3
		b.add_theme_font_override("font", fv)
		b.add_theme_font_size_override("font_size", 24)
		b.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85))
		b.add_theme_color_override("font_hover_color", Color(0.95, 0.97, 1.0))
		b.pressed.connect(item[1])
		box.add_child(b)


func _tw(key: String) -> Tween:
	if _tweens.has(key) and _tweens[key].is_valid():
		_tweens[key].kill()
	var t := create_tween()
	_tweens[key] = t
	return t


## Start of the game: fade in from black with the title (unless skipping), show the hint unless cinematic.
func begin(skip: bool, cinematic: bool) -> void:
	_tw("fade").tween_property(_fade, "color:a", 0.0, 0.4 if skip else Config.FADE_IN).set_trans(Tween.TRANS_SINE)
	if skip:
		return
	var t := _tw("title")
	t.tween_property(_title, "theme_override_colors/font_color:a", 0.85, 1.2).set_delay(0.3)
	t.tween_property(_title, "theme_override_colors/font_color:a", 0.0, 1.4).set_delay(Config.TITLE_TIME - 2.9)
	if not cinematic:
		_hint_alive = true
		var h := _tw("hint")
		h.tween_property(_hint, "theme_override_colors/font_color:a", 0.6, 1.2).set_delay(3.2)
		h.tween_property(_hint, "theme_override_colors/font_color:a", 0.0, 1.5).set_delay(Config.HINT_TIME)


func hide_hint() -> void:
	if _hint_alive:
		_hint_alive = false
		_tw("hint").tween_property(_hint, "theme_override_colors/font_color:a", 0.0, 0.6)


func fade_out(seconds: float) -> void:
	_tw("fade").tween_property(_fade, "color:a", 1.0, seconds).set_trans(Tween.TRANS_SINE)


func show_end_line(text: String) -> void:
	_ended = true
	_end.text = text
	_tw("end").tween_property(_end, "theme_override_colors/font_color:a", 0.8, 2.5).set_trans(Tween.TRANS_SINE)


func _process(_dt: float) -> void:
	var k := clampf(G.depth / 700.0, 0.0, 1.0)
	(_vignette.material as ShaderMaterial).set_shader_parameter("strength", lerpf(0.22, 0.62, k))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif _hint_alive and event is InputEventKey and event.pressed:
		hide_hint()
	elif _hint_alive and event is InputEventMouseMotion and event.relative.length() > 3.0:
		hide_hint()


func _set_paused(p: bool) -> void:
	get_tree().paused = p
	G.paused = p
	_pause.visible = p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED
	if G.audio and G.audio.has_method("set_paused"):
		G.audio.set_paused(p)


func _on_resume() -> void:
	_set_paused(false)


func _on_quit() -> void:
	get_tree().paused = false
	G.quit_game()
