extends RefCounted
## Diver effects: exhale bubbles in sync with the regulator breathing (scripts/fx/ExhaleBubbles.gd) and the
## dive-mask lens finish (scripts/fx/MaskLens.gd).

func build(parent: Node3D) -> void:
	var bubbles: Node3D = load("res://scripts/fx/ExhaleBubbles.gd").new()
	bubbles.name = "ExhaleBubbles"
	parent.add_child(bubbles)
	var lens: CanvasLayer = load("res://scripts/fx/MaskLens.gd").new()
	lens.name = "MaskLens"
	parent.add_child(lens)
