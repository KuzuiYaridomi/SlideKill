extends Node3D

@export var bullet_scene: PackedScene
@export var fire_rate: float = 0.2
@export var muzzle_node: NodePath
@export var player_controlled: bool = true  # True = player gun, False = enemy gun

@onready var muzzle: Node3D = get_node(muzzle_node)
var can_fire := true

@warning_ignore("unused_parameter")
func _process(delta):
	# Only player-controlled gun reacts to player input
	if player_controlled and Input.is_action_pressed("shoot") and can_fire:
		_fire()

# For enemies: call this externally from AI when they should shoot
func enemy_fire():
	if not player_controlled and can_fire:
		_fire()

func _fire():
	can_fire = false
	if not bullet_scene:
		push_warning("AKM: bullet_scene not assigned.")
		can_fire = true
		return
	var bullet = bullet_scene.instantiate()
	var root = get_tree().current_scene if get_tree().current_scene != null else get_tree().get_root()
	root.add_child(bullet)
	# spawn at muzzle transform (bullet should move forward from this transform)
	if muzzle:
		bullet.global_transform = muzzle.global_transform
	else:
		bullet.global_transform = global_transform
	# (Direction unchanged — bullet goes straight along muzzle forward)
	await get_tree().create_timer(fire_rate).timeout
	can_fire = true
	
func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		$AnimationPlayer.play("rotate_gun")
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		$AnimationPlayer.play("rotate_gun")


	
