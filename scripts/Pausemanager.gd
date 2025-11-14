# res://PauseManager.gd
extends Node

@export var pause_menu_scene_path: String = "res://ui/PauseMenu.tscn"
var pause_menu_scene: PackedScene = null
var pause_menu_inst: CanvasLayer = null

func _ready() -> void:
	# load the scene at runtime so bad path yields a clear error
	if not FileAccess.file_exists(pause_menu_scene_path):
		push_error("PauseManager: PauseMenu scene not found at %s" % pause_menu_scene_path)
		return
	pause_menu_scene = load(pause_menu_scene_path) as PackedScene
	if not pause_menu_scene:
		push_error("PauseManager: Failed to load PauseMenu scene as PackedScene")
		return

	# instantiate and add to current scene root; keep it hidden initially
	pause_menu_inst = pause_menu_scene.instantiate()
	pause_menu_inst.visible = false
	get_tree().current_scene.add_child(pause_menu_inst)

func _unhandled_input(event):
	# toggle on the "pause" input action (add in InputMap -> Escape)
	if event.is_action_pressed("pause"):
		_toggle_pause()

func _toggle_pause() -> void:
	if not pause_menu_inst:
		return
	if get_tree().paused:
		# if paused, unpause by calling the menu hide function (if it exists)
		if pause_menu_inst.has_method("hide_pause"):
			pause_menu_inst.call("hide_pause")
		else:
			get_tree().paused = false
			pause_menu_inst.visible = false
	else:
		# show pause
		if pause_menu_inst.has_method("show_pause"):
			pause_menu_inst.call("show_pause")
		else:
			get_tree().paused = true
			pause_menu_inst.visible = true
