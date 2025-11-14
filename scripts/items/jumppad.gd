# JumpPad.gd
extends Area3D

@export var jump_strength: float = 30.0 # Adjustable vertical velocity
@export var forward_velocity: float = 30.0
@onready var particles = $Particles # Assumes your Particles node is named 'Particles'

# Connect this function to the Area3D's 'body_entered' signal via the Node dock
func _on_body_entered(body: Node3D):
	# CRITICAL CHECK: Ensure the body can actually be moved (i.e., has a 'velocity' property)
	if body is CharacterBody3D:
		# 1. APPLY JUMP FORCE
		# Reset vertical velocity (y) to zero first to prevent compounding jumps
		body.velocity.y = 0 
		body.velocity.x = 0
		
		
		# Add the jump strength to the vertical velocity
		body.velocity.y += jump_strength
		body.velocity.x += forward_velocity
		
		# Manually call move_and_slide() on the body to immediately apply the force
		# Note: In Godot 4, the body's script usually calls move_and_slide in _physics_process.
		# This is often optional but guarantees the new velocity is registered instantly.
		# For CharacterBody3D, simply modifying 'body.velocity' is usually sufficient
		# if the body's _physics_process runs immediately after this.
		
	elif body is RigidBody3D:
		# For RigidBody3D, you must use apply_central_impulse() for instant force.
		# Use world coordinates (Vector3.UP) * the jump_strength.
		body.apply_central_impulse(Vector3.UP * jump_strength)
		
	# 2. TRIGGER PARTICLES (Visual Feedback)
	if particles and particles.is_class("GPUParticles3D"):
		# Stop and then restart the particles to ensure a visible burst effect
		particles.emitting = true
		# The particles will run for their duration and stop automatically
