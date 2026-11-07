extends RefCounted
## Beat 4 — The dark line: SCP-3000 is placed in the deep. Its endless body (layout "extension") lies still far
## below and ahead of the path and crosses under it (the line, framed at layout "dark_line_target"); then its front
## (coils, neck, head) rises out of the dark below to its final pose. Nothing pops and no part fades on its own:
## SCP3000.gd stages it with the distance from the camera, the rise and a light creature haze, all driven by the
## path time, and drives its own slow life.

func build(parent: Node3D) -> void:
	var L := PathDef.load_layout()
	var c: Node3D = load("res://scenes/SCP3000.tscn").instantiate()
	c.name = "SCP3000"
	c.position = PathDef.v3(L["creature_pos"])
	c.rotation.y = deg_to_rad(float(L["creature_yaw"]))
	c.set("creature_scale", float(L["creature_scale"]))
	c.set("s_cut", float(L["s_cut"]))
	var ext := PackedVector3Array()
	for p in L["extension"]:
		ext.append(PathDef.v3(p))
	c.set("extension_world", ext)
	c.set("head_turn_target", Game.camera)
	parent.add_child(c)
	Game.targets["creature"] = c
