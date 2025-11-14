extends Node
class_name DamageSystem

# Health component script (adjust path to your actual Health.gd)
@warning_ignore("shadowed_global_identifier")
const Health = preload("res://scripts/Health.gd")

# tuning (exposed so you can tweak in Inspector if you make this a scene/autoload)
@export var force_to_damage_scale: float = 0.12   # damage per unit of force magnitude
@export var min_force_damage_threshold: float = 1.0  # ignore tiny knocks
@export var knockback_scale: float = 1.0            # scale applied to force when imparting knockback

# -------------------------
# Find a Health component on node, its children, or ancestors
# -------------------------
func find_health_component(node: Node) -> Health:
	if node == null:
		return null
	# If node itself is a Health instance
	if node is Health:
		return node
	# If it has a child named "Health"
	if node.has_node("Health"):
		var c = node.get_node_or_null("Health")
		if c and c is Health:
			return c
	# shallow search children
	for child in node.get_children():
		if child is Health:
			return child
	# walk upward
	var p = node.get_parent()
	if p:
		return find_health_component(p)
	return null

# -------------------------
# Primary API - deal damage (amount OR force-based)
# returns true if a Health component was found and apply_damage returned true
# -------------------------
func deal_damage(target: Node, amount: int = 0, instigator: Node = null, force: Vector3 = Vector3.ZERO, damage_type: String = "") -> bool:
	# compute damage from force if amount is zero
	var computed_amount: int = amount
	if computed_amount <= 0 and force.length() >= min_force_damage_threshold:
		computed_amount = int(ceil(force.length() * force_to_damage_scale))

	var applied = false
	var h = find_health_component(target)
	if h and computed_amount > 0:
		# call existing Health.apply_damage signature (amount, instigator, hit_force, damage_type)
		# adapt if your Health.gd signature differs
		applied = h.apply_damage(computed_amount, instigator, force, damage_type)
	# always apply knockback/force if provided
	_apply_force_to_target(target, force)
	return applied

# Convenience wrapper when you only have an impulse/force
func deal_force_damage(target: Node, force: Vector3, instigator: Node = null, damage_type: String = "") -> bool:
	return deal_damage(target, 0, instigator, force, damage_type)

# -------------------------
# Internal: apply the force / impulse to the target in a safe way
# - Prefer calling target.receive_force(force) if exists (CharacterBody3D compatibility)
# - Otherwise, if target is RigidBody3D, use apply_central_impulse()
# - If neither, try to find a parent RigidBody3D and apply impulse there
# -------------------------
func _apply_force_to_target(target: Node, force: Vector3) -> void:
	if force == Vector3.ZERO or target == null:
		return

	# prefer the target exposing a receive_force method (CharacterBody3D code often uses this)
	if target.has_method("receive_force"):
		target.call_deferred("receive_force", force * knockback_scale)
		return

	# if it's directly a RigidBody3D, apply central impulse
	if target is RigidBody3D:
		(target as RigidBody3D).apply_central_impulse(force * knockback_scale)
		return

	# if it's a CharacterBody3D with a velocity field, try to call receive_force
	if target is CharacterBody3D:
		if target.has_method("receive_force"):
			target.call_deferred("receive_force", force * knockback_scale)
			return

	# fallback: search for a RigidBody3D in ancestors (e.g. you hit a child collision shape)
	var rb := _find_rigidbody_on_node_or_parent(target)
	if rb:
		rb.apply_central_impulse(force * knockback_scale)
		return

# -------------------------
# Helper: find a RigidBody3D on the node or a parent node
# -------------------------
func _find_rigidbody_on_node_or_parent(node: Node) -> RigidBody3D:
	var n := node
	while n:
		if n is RigidBody3D:
			return n
		n = n.get_parent()
	return null
