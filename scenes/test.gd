extends RigidBody3D
@export var move_force: float = 50.0
@export var jump_impulse: float = 10.0
@export var air_control: float = 0.5
@export var max_speed: float = 20.0

func _integrate_forces(state):
	var input_dir = Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		input_dir -= transform.basis.z
	if Input.is_action_pressed("move_back"):
		input_dir += transform.basis.z
	if Input.is_action_pressed("move_left"):
		input_dir -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		input_dir += transform.basis.x
	input_dir = input_dir.normalized()
	
	if input_dir != Vector3.ZERO:
		apply_central_force(input_dir * move_force)
	
	# Jump (simple)
	if Input.is_action_just_pressed("jump"):
		apply_central_impulse(Vector3.UP * jump_impulse)
