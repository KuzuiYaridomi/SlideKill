extends Node3D

const SPEED = 100.0
@export var damage: int = 20

@onready var mesh = $MeshInstance3D
@onready var ray = $RayCast3D
@onready var particles = $GPUParticles3D

func _process(delta):
	position += transform.basis * Vector3(0, 0, SPEED) * delta

	if ray.is_colliding():
		var collider = ray.get_collider()
		if collider and collider.has_method("take_damage") and not collider.is_in_group("player"):
			collider.take_damage(damage)
		
		mesh.visible = false
		particles.emitting = true
		await get_tree().create_timer(0.5).timeout
		queue_free()


func _on_timer_timeout() -> void:
	pass # Replace with function body.
