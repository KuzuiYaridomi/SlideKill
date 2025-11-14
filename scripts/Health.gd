extends Node
class_name Health

signal damaged(amount: int, instigator: Node)
signal healed(amount: int)
signal died(instigator: Node)
signal health_changed(current: int, max: int)

@export var max_health: int = 3
@export var invulnerable: bool = false
@export var team: String = ""               # optional team tag for friendly-fire checks
@export var auto_kill_owner: bool = false   # if true, Health will queue_free the owner when dead
@export var owner_kill_delay: float = 2.0   # delay before owner is freed

var current_health: int = 0

func _ready() -> void:
	current_health = max_health

func is_dead() -> bool:
	return current_health <= 0

# Apply damage. Returns true if damage was applied.
# amount: integer damage (DamageSystem converts force->amount before calling)
# instigator: node that caused damage (may be null)
# force: optional Vector3 impulse to pass to the owner (knockback)
# damage_type: optional string ("bullet","slide","melee" etc)
func apply_damage(amount: int, instigator: Node = null, force: Vector3 = Vector3.ZERO, damage_type: String = "") -> bool:
	# invalid cases
	if amount <= 0:
		return false
	if is_dead():
		return false
	if invulnerable:
		return false

	# Friendly-fire check (if both have teams and same -> ignore)
	if instigator:
		var inst_health = null
		if instigator.has_node("Health"):
			inst_health = instigator.get_node_or_null("Health")
		elif instigator is Health:
			inst_health = instigator

		if inst_health and inst_health is Health and inst_health.team != "" and team != "" and inst_health.team == team:
			return false

	# apply health change
	current_health = max(0, current_health - amount)
	emit_signal("damaged", amount, instigator)
	emit_signal("health_changed", current_health, max_health)

	# apply force / knockback to owner if supported
	if force != Vector3.ZERO:
		var owner_node = _get_owner_node()
		if owner_node:
			# prefer receive_force method (CharacterBody compatibility)
			if owner_node.has_method("receive_force"):
				owner_node.call_deferred("receive_force", force)
			# fallback: if owner is RigidBody3D, apply impulse
			elif owner_node is RigidBody3D:
				(owner_node as RigidBody3D).apply_central_impulse(force)

	# handle death
	if current_health <= 0:
		emit_signal("died", instigator)
		_on_death(instigator)
	return true

func heal(amount: int) -> void:
	if amount <= 0 or is_dead():
		return
	current_health = min(max_health, current_health + amount)
	emit_signal("healed", amount)
	emit_signal("health_changed", current_health, max_health)

func set_max_health(new_max: int, keep_fraction: bool = true) -> void:
	if new_max <= 0:
		return
	var frac = 1.0
	if keep_fraction and max_health > 0:
		frac = float(current_health) / float(max_health)
	max_health = new_max
	current_health = clamp(round(frac * max_health), 0, max_health)
	emit_signal("health_changed", current_health, max_health)

# Internal: find the "owner" actor (prefer parent if Health is a child)
func _get_owner_node() -> Node:
	if get_parent() != null and get_parent() != self:
		return get_parent()
	return self

# Default death behavior: call owner's die() if present; optionally remove owner
func _on_death(instigator: Node) -> void:
	var owner_node = _get_owner_node()
	# notify owner
	if owner_node and owner_node.has_method("die"):
		owner_node.call_deferred("die")
	# optional auto-kill owner (useful for quick prototypes)
	if auto_kill_owner and owner_node:
		await get_tree().create_timer(owner_kill_delay).timeout
		if is_instance_valid(owner_node):
			owner_node.queue_free()

	# this Health node can be left or freed; owner code should handle cleanup normally
