# PauseManager.gd
extends Node

@export var pause_menu_path: NodePath = NodePath("") # optional: a CanvasLayer/UI to show/hide on pause

var _master_bus: int = -1

func _ready() -> void:
	# get the master bus index (should exist by default)
	_master_bus = AudioServer.get_bus_index("Master")
	# Note: set this node's Process > Mode = "Always" in the Inspector so it receives input when paused.

func _input(event: InputEvent) -> void:
	# use the default "ui_cancel" action (Escape by default). This is simple and editable in Input Map.
	if Input.is_action_just_pressed("ui_cancel"):
		_toggle_pause()

func _toggle_pause() -> void:
	var paused = not get_tree().paused
	get_tree().paused = paused

	# free/capture mouse
	if paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# mute/unmute master audio bus so music stops
	if _master_bus >= 0:
		AudioServer.set_bus_mute(_master_bus, paused)

	# optional: show/hide pause UI if you provided a path
	if pause_menu_path != NodePath(""):
		var pm = get_node_or_null(pause_menu_path)
		if pm:
			pm.visible = paused
			# If the pause UI needs to receive input while paused, ensure its CanvasLayer/controls are set:
			# - CanvasLayer.process_mode = "When Paused" (Inspector: Process -> Mode = When Paused)
