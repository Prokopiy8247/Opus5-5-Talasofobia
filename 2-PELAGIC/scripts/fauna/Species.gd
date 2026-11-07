extends RefCounted
## Species presets for FishSchool: mesh kind, length (m), cruise speed (m/s), tail-beat or stroke rate (Hz),
## body wave (amplitude, cycles along the body), roll, colours (sRGB), surface, eye = (x, y, radius) in unit
## fish space, lodk = hi-mesh distance per metre of length, view = default draw distance (m), head_jit / roll_jit =
## slow individual heading / roll noise (rad; schools stop moving like one rigid pattern).

const DATA := {
	"sardine": {
		"mesh": "slender", "len": 0.22, "speed": 1.3, "hz": 3.0, "wave": 0.1, "cycles": 0.9, "roll": 0.1, "flash": 0.55,
		"back": "#203f57", "flank": "#a9bcc8", "belly": "#eef3f5", "fin": "#93a7b1", "mark": "#3f6f8c",
		"metal": 0.8, "rough": 0.2, "glint": 1.3, "eye": Vector3(0.40, 0.018, 0.022), "view": 170.0,
		"head_jit": 0.25, "roll_jit": 0.42,
	},
	"fusilier": {
		"mesh": "slender", "len": 0.26, "speed": 1.1, "hz": 2.6, "wave": 0.1, "cycles": 0.9, "roll": 0.1, "flash": 0.4,
		"back": "#24488a", "flank": "#6a96cc", "belly": "#e6eef8", "fin": "#e2b62c", "mark": "#d9b12a",
		"mode": 1.0, "stripe": 0.6, "metal": 0.5, "rough": 0.3, "glint": 0.9,
		"eye": Vector3(0.40, 0.018, 0.022), "view": 170.0, "head_jit": 0.22, "roll_jit": 0.35,
	},
	"chromis": {
		"mesh": "deep", "len": 0.15, "speed": 0.45, "hz": 2.4, "wave": 0.11, "cycles": 0.85, "roll": 0.2,
		"back": "#2b7ea6", "flank": "#57bcd6", "belly": "#c9ecf0", "fin": "#3f9fbf", "mark": "#8be0c8",
		"variety": 0.35, "metal": 0.3, "rough": 0.3, "glint": 0.8, "eye": Vector3(0.36, 0.03, 0.03), "view": 110.0,
		"head_jit": 0.5, "roll_jit": 0.2,
	},
	"anthias": {
		"mesh": "deep", "len": 0.15, "speed": 0.4, "hz": 2.4, "wave": 0.11, "cycles": 0.85, "roll": 0.2,
		"back": "#e2643a", "flank": "#f28a52", "belly": "#f7c6a3", "fin": "#ee7044", "mark": "#a874d4",
		"variety": 0.25, "metal": 0.12, "rough": 0.35, "glint": 0.6, "eye": Vector3(0.36, 0.03, 0.03), "view": 110.0,
		"head_jit": 0.6, "roll_jit": 0.15,
	},
	"sergeant": {
		"mesh": "deep", "len": 0.17, "speed": 0.45, "hz": 2.2, "wave": 0.1, "cycles": 0.85, "roll": 0.2,
		"back": "#b9a83e", "flank": "#e6deae", "belly": "#f1f0e4", "fin": "#cfc487", "mark": "#1e2426",
		"mode": 2.0, "metal": 0.18, "rough": 0.35, "glint": 0.6, "eye": Vector3(0.36, 0.03, 0.03), "view": 110.0,
		"head_jit": 0.5, "roll_jit": 0.15,
	},
	"jack": {
		"mesh": "deep", "len": 0.65, "speed": 1.1, "hz": 1.4, "wave": 0.08, "cycles": 0.8, "roll": 0.08, "flash": 0.45,
		"back": "#34495a", "flank": "#aab7be", "belly": "#e3e8e8", "fin": "#4b5b66", "mark": "#2a3640",
		"metal": 0.8, "rough": 0.25, "glint": 1.0, "eye": Vector3(0.36, 0.035, 0.032), "lodk": 60.0, "view": 230.0,
		"head_jit": 0.2, "roll_jit": 0.35,
	},
	"cleaner": {
		"mesh": "slender", "len": 0.15, "speed": 0.35, "hz": 2.6, "wave": 0.1, "cycles": 0.9, "roll": 0.3,
		"back": "#1f5fcc", "flank": "#5fb0f2", "belly": "#e2f2ff", "fin": "#1c2230", "mark": "#0d1116",
		"mode": 1.0, "stripe": 0.5, "metal": 0.4, "rough": 0.25, "glint": 2.5,
		"eye": Vector3(0.40, 0.018, 0.022), "view": 260.0, "head_jit": 0.5, "roll_jit": 0.3,
	},
	"shark": {
		"mesh": "shark", "len": 1.8, "speed": 0.9, "hz": 0.55, "wave": 0.075, "cycles": 0.75, "roll": 0.06,
		"back": "#676b5f", "flank": "#8b8f86", "belly": "#e8eae4", "fin": "#63675b", "mark": "#141618",
		"tip": 1.0, "metal": 0.05, "rough": 0.55, "glint": 0.15, "eye": Vector3(0.415, 0.018, 0.009),
		"size_var": 0.0, "min_px": 0.0, "view": 180.0,
	},
	"turtle": {
		"mesh": "turtle", "body": 1.0, "len": 1.2, "speed": 0.45, "hz": 0.27, "roll": 0.05,
		"back": "#5a4628", "flank": "#5a4628", "belly": "#d6c08a", "fin": "#3b3a28", "mark": "#a2783a",
		"metal": 0.0, "rough": 0.6, "glint": 0.1, "eye": Vector3(0.43, 0.03, 0.014),
		"size_var": 0.0, "min_px": 0.0, "view": 180.0,
	},
}
