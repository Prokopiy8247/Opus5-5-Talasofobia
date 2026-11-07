extends Node3D
## Marker float: a slow bob and a tiny blinking lamp (the only warm light in the deep).

var lamp_mat: StandardMaterial3D
var light: OmniLight3D
var _t := 0.0
var _base := Vector3.ZERO

func _ready() -> void:
	_base = position

func _process(delta: float) -> void:
	_t += delta
	position = _base + Vector3(sin(_t * 0.4) * 0.06, sin(_t * 0.55) * 0.12, cos(_t * 0.33) * 0.05)
	rotation = Vector3(sin(_t * 0.5) * 0.06, _t * 0.05, cos(_t * 0.41) * 0.05)
	var ph := fmod(_t, 2.6)
	var flash := exp(-pow((ph - 0.15) / 0.09, 2.0)) + 0.6 * exp(-pow((ph - 0.5) / 0.08, 2.0))
	if lamp_mat:
		lamp_mat.emission_energy_multiplier = 0.25 + 22.0 * flash
	if light:
		light.light_energy = 0.35 + 3.0 * flash
