extends Node
## Autoload "G": shared runtime state that beats and systems read. Main writes it every frame.

var path: PathDef                 # the descent path (Curve3D + timeline + gaze cues)
var world: Node3D                 # root for all generated content
var player: Node3D                # player rig (follows the path)
var camera: Camera3D
var torch: SpotLight3D
var audio: Node                   # AudioDirector (may be null until built)
var env: Environment
var haze: Node                    # BeamHaze (full-screen scattered light of the torch and one lamp)
var water_light: Node             # WaterLight (full-screen directional water light, above 340 m)
var snow: Node                    # MarineSnow (set_wave hook for the creature's displacement shell)

## Hooks written by beats (all optional).
var reveal := false               # harness --reveal: clearer water + a faint cold top light, during stills only
var end_ready := false           # B6: the lamp reveal has been watched, the ending may run
var cam_push := Vector3.ZERO      # B5: world-space push of the diver (creature wake), smoothed by Player
var snow_mult := 1.0              # B4 settle surge: marine-snow opacity multiplier (0..2), restore exactly 1.0

var s := 0.0                      # distance along the path, m
var depth := 0.0                  # camera depth, positive metres
var t := 0.0                      # game clock, s (starts at the timeline time of the start point)
var autowalk := false
var ending := false
var paused := false
var running := false              # false during loading / warm-up: beats must not start events

## Marine-snow current. Beats write flow_target (m/s, world); Main smooths it into flow and integrates flow_offset.
var flow_target := Vector3.ZERO
var flow := Vector3.ZERO
var flow_offset := Vector3.ZERO

var args := {}                    # harness flags parsed from user args


## Quit cleanly: stop every audio player first (playing streams would otherwise be reported as leaked).
func quit_game() -> void:
	var players := get_tree().root.find_children("*", "AudioStreamPlayer", true, false)
	players.append_array(get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false))
	for p in players:
		p.stop()
	await get_tree().create_timer(0.3, true).timeout
	for p in players:
		p.stream = null
	await get_tree().process_frame
	get_tree().quit()


func _ready() -> void:
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()
