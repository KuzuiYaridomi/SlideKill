# res://ui/PauseMenu.gd
extends CanvasLayer

@export var main_menu_scene_path: String = "res://MainMenu.tscn" # change if needed

@onready var _panel := $Panel
@onready var _resume_btn := $Panel/VBoxContainer/ResumeButton
@onready var _quit_btn := $Panel/VBoxContainer/QuitButton
@onready var _anim_player := $Panel/AnimationPlayer if has_node("Panel/AnimationPlayer") else null

# hover/fade tuning
const HOVER_COLOR := Color(1.0, 0.9, 0.6, 1.0)
const NORMAL_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const HOVER_TWEEN_TIME := 0.12
const FADE_TIME := 0.18

func _ready() -> void:
	visible = false

	if _resume_btn and not _resume_btn.is_connected("pressed", Callable(self, "_on_resume_pressed")):
		_resume_btn.connect("pressed", Callable(self, "_on_resume_pressed"))
	if _quit_btn and not _quit_btn.is_connected("pressed", Callable(self, "_on_quit_pressed")):
		_quit_btn.connect("pressed", Callable(self, "_on_quit_pressed"))

	_setup_button_hover(_resume_btn)
	_setup_button_hover(_quit_btn)

	# ensure panel starts visible in editor/play when not paused
	if _panel:
		_panel.modulate.a = 1.0
		_panel.scale = Vector2.ONE

func show_pause() -> void:
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if _panel:
		_panel.modulate.a = 0.0
		_panel.scale = Vector2(0.98, 0.98)

	if _anim_player and _anim_player.has_animation("open"):
		_anim_player.play("open")
	else:
		var tw = get_tree().create_tween()
		tw.tween_property(_panel, "modulate:a", 1.0, FADE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_panel, "scale", Vector2.ONE, FADE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if _resume_btn:
		_resume_btn.grab_focus()

func hide_pause() -> void:
	get_tree().paused = false
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_resume_pressed() -> void:
	hide_pause()

func _on_quit_pressed() -> void:
	get_tree().paused = false
	if main_menu_scene_path == "" or not FileAccess.file_exists(main_menu_scene_path):
		push_warning("PauseMenu: main_menu_scene_path not set or invalid.")
		return
	get_tree().change_scene_to_file(main_menu_scene_path)

# --- hover helpers (smooth color tween) ---
func _setup_button_hover(btn: Button) -> void:
	if not btn:
		return
	btn.modulate = NORMAL_COLOR

func _on_button_mouse_enter(btn: Button) -> void:
	get_tree().create_tween().tween_property(btn, "modulate", HOVER_COLOR, HOVER_TWEEN_TIME)

func _on_button_mouse_exit(btn: Button) -> void:
	get_tree().create_tween().tween_property(btn, "modulate", NORMAL_COLOR, HOVER_TWEEN_TIME)
