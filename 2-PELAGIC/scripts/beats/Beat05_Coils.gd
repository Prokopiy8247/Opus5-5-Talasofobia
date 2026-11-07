extends RefCounted
## Beat 5 — The coils: thin wisps of dark viscous fluid seeping from under the neck (children of the creature, in
## its model space, so they ride with it). Each seep is a narrow, slowly twisting strip whose path curls with a smooth
## drift field; fluid_ribbon.gdshader fades it edge-on and erodes it into wisps. Cleaner fish come from Fauna.gd; the
## head choreography from SCP3000.gd.

const SAMPLES := 72

func build(_parent: Node3D) -> void:
	var c: Node3D = Game.targets.get("creature")
	if c == null:
		return
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/fluid_ribbon.gdshader")
	m.set_shader_parameter("color", Palette.FLUID)
	m.set_shader_parameter("reveal", 0.0)
	c.set("ribbon_mat", m)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in 12:
		var s := rng.randf_range(0.13, 0.27)
		var sp: Vector3 = c.spine_at(s)
		var tg: Vector3 = c.tangent_at(s)
		var side := Vector3(-tg.z, 0.0, tg.x).normalized() * rng.randf_range(-0.6, 0.6)
		var start := sp + Vector3(0, -4.2, 0) + side * 4.0
		var length := rng.randf_range(9.0, 22.0)
		# a soft plume metres across that spreads as it sinks, like ink in water (thin strips read as hairs or cables)
		var width := rng.randf_range(1.0, 1.9)
		var ph := rng.randf() * 10.0
		# each seep sinks its own way: the along-body drift turned about the vertical by up to +-40 deg, and a
		# heavier or lighter fall (all strips sharing one drift read as parallel planks)
		var yaw := deg_to_rad(rng.randf_range(-40.0, 40.0))
		var horiz := (tg * length * 0.55 + side * 3.0).rotated(Vector3.UP, yaw)
		var fall := rng.randf_range(0.5, 1.0) * length
		var curl_amp := rng.randf_range(6.0, 10.0)
		var pts := PackedVector3Array()
		for k in SAMPLES:
			var t := float(k) / (SAMPLES - 1)
			var drift := horiz * t + Vector3(0, -t * fall, 0)
			# the curl sets in just below the source (the visible upper part of a seep must already bend): two
			# octaves, so strips bend, loop and cross
			# (field scaled so a seep bends within the ~5-10 model m of it that shows at once, not over its whole length)
			var q := (start + drift * 0.6) * 1.7
			var cw := smoothstep(0.0, 0.3, t) * (0.6 + 0.4 * t)
			drift += (_curl(q, ph) + 0.45 * _curl(q * 2.3 + Vector3(5.1, 1.7, 3.3), ph * 1.9 + 2.0)) * cw * curl_amp * 0.6
			pts.append(start + drift)
		var mi := MeshInstance3D.new()
		mi.mesh = _ribbon(pts, width, rng.randf_range(0.4, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0), ph)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_instance_shader_parameter("phase", ph)
		c.add_child(mi)

## A smooth divergence-free-looking drift field (sum of rotated sines), model m.
static func _curl(p: Vector3, ph: float) -> Vector3:
	return Vector3(
		sin(p.y * 0.31 + ph) + 0.5 * sin(p.z * 0.57 + ph * 1.7),
		0.35 * sin(p.x * 0.43 + p.z * 0.21 + ph * 2.3),
		cos(p.y * 0.27 + ph * 0.6) + 0.5 * cos(p.x * 0.49 + ph * 2.9))

## Strip along pts, its cross direction rotating about the tangent by `turns` half-turns over the length (a lazy
## twist), narrow at the source and spreading as it sinks (the fluid diffuses), breathing along the length.
func _ribbon(pts: PackedVector3Array, width: float, turns: float, ph: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	var t0 := (pts[1] - pts[0]).normalized()
	var side0 := t0.cross(Vector3.FORWARD if absf(t0.z) < 0.9 else Vector3.RIGHT).normalized()
	for i in n:
		var u := float(i) / (n - 1)
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		side0 = (side0 - t * side0.dot(t)).normalized()     # parallel transport: no flips along the strip
		var side := side0.rotated(t, PI * turns * u + ph)
		var w := width * (0.2 + 1.1 * u) * (0.8 + 0.2 * sin(u * 9.0 + ph))
		var nrm := t.cross(side).normalized()
		for e in 2:
			st.set_uv(Vector2(float(e), u))
			st.set_normal(nrm)
			st.add_vertex(pts[i] + side * (float(e) - 0.5) * w)
	for i in n - 1:
		var a := i * 2
		st.add_index(a); st.add_index(a + 2); st.add_index(a + 1)
		st.add_index(a + 1); st.add_index(a + 2); st.add_index(a + 3)
	return st.commit()
