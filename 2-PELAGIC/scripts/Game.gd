class_name Game
## Shared runtime references (filled by Main). Beats read these instead of searching the tree.

static var main: Node3D
static var world: Node3D           # parent of all beat content
static var curve: Curve3D
static var camera: Camera3D
static var player: Node3D
static var path_time := 0.0        # autowalk-clock position of the player on the path (s)
static var path_dist := 0.0        # distance along the path (m)
static var targets := {}           # name -> Node3D, used by gaze cues
static var harness := false        # unattended test run (no mouse capture, no input cancel)

static func cam_pos() -> Vector3:
	return camera.global_position if camera else Vector3.ZERO

## Quit; static references (curve, cached meshes) are released in Main._exit_tree() so the engine exits cleanly.
static func quit(tree: SceneTree) -> void:
	tree.quit()

static func release() -> void:
	curve = null; camera = null; player = null; world = null; main = null
	targets.clear()
	PathDef.curve = null
	PathDef.layout = {}
	var fm = load("res://scripts/fauna/FaunaMesh.gd")
	if fm and "_cache" in fm:
		fm._cache.clear()
