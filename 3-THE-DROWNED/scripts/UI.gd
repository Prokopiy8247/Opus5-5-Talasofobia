class_name UI
extends CanvasLayer
## Black fades, title card, controls hint, closing line and the minimal pause overlay.

signal resume_pressed
signal quit_pressed

var fade: ColorRect
var post: ColorRect
var title: Label
var hint: Label
var end_line: Label
var pause_box: Control
var _font: FontVariation


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = FontVariation.new()
	_font.base_font = ThemeDB.fallback_font
	_font.spacing_glyph = 6
	_font.variation_embolden = -0.35
	post = ColorRect.new()
	post.name = "Post"
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/post.gdshader")
	post.material = pm
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(post)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	title = _label("T H E    D R O W N E D", 40, 0.0)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint = _label("W / S   move        Shift   faster        C   cinematic        Esc   pause", 17, 0.0)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -100
	hint.offset_bottom = -60
	end_line = _label("", 30, 0.0)
	end_line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_pause()


func _label(text: String, size: int, alpha: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.86, 0.92, 0.88))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.modulate.a = alpha
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(l)
	return l


func _build_pause() -> void:
	pause_box = Control.new()
	pause_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_box.visible = false
	add_child(pause_box)
	var dim := ColorRect.new()
	dim.color = Color(0, 0.02, 0.03, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_box.add_child(dim)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vb.grow_vertical = Control.GROW_DIRECTION_BOTH
	vb.add_theme_constant_override("separation", 22)
	pause_box.add_child(vb)
	for item in [["Resume", resume_pressed], ["Quit", quit_pressed]]:
		var b := Button.new()
		b.text = item[0]
		b.flat = true
		b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_color_override("font_color", Color(0.75, 0.84, 0.8))
		b.add_theme_color_override("font_hover_color", Color(1.0, 0.82, 0.6))
		var sig: Signal = item[1]
		b.pressed.connect(func(): sig.emit())
		vb.add_child(b)


## Colour grade and lens parameters for shaders/post.gdshader (keys = uniform names).
func set_post(params: Dictionary) -> void:
	var m := post.material as ShaderMaterial
	for k in params:
		m.set_shader_parameter(k, params[k])


func show_pause(on: bool) -> void:
	pause_box.visible = on


func tween_alpha(node: CanvasItem, to: float, time: float, delay := 0.0) -> Tween:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(node, "modulate:a" if node != fade else "color:a", to, time)
	return tw


## Title sequence: fade in from black (2.5 s), title for ~4 s, hint for ~6 s.
func intro(show_hint: bool) -> void:
	tween_alpha(fade, 0.0, 2.5, 0.4)
	tween_alpha(title, 1.0, 1.6, 0.6)
	tween_alpha(title, 0.0, 1.8, 4.2)
	if show_hint:
		tween_alpha(hint, 0.75, 1.2, 3.0)
		tween_alpha(hint, 0.0, 1.5, 9.0)


func hide_hint() -> void:
	if hint.modulate.a > 0.0:
		create_tween().tween_property(hint, "modulate:a", 0.0, 0.6)
		hint.visible = false


func ending(depth_m: float) -> void:
	var d := int(round(depth_m))
	var txt := str(d)
	if d >= 1000:
		txt = "%d %03d" % [d / 1000, d % 1000]
	end_line.text = txt + " m"
	tween_alpha(fade, 1.0, 3.2, 1.6)          # after the door lamp has died
	tween_alpha(end_line, 0.85, 2.5, 5.6)
	tween_alpha(end_line, 0.0, 3.0, 12.5)
