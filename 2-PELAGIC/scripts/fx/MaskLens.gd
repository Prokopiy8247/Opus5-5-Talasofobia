extends CanvasLayer
## Full-screen dive-mask finish (shaders/fx_lens.gdshader), drawn just below the UI CanvasLayer (layer 10) so the
## title, fades and pause menu stay clean. The vignette closes in a little with depth (the heavy deep feel).

var _mat: ShaderMaterial

func _ready() -> void:
	layer = 5
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/fx_lens.gdshader")
	r.material = _mat
	add_child(r)

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := maxf(-cam.global_position.y, 0.0)
	_mat.set_shader_parameter("vignette", lerpf(0.3, 0.45, smoothstep(60.0, 300.0, d)))
