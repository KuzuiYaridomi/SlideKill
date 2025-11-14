extends Node3D

@export var enemy_scene: PackedScene
@export var spawn_interval: float = 5.0
@export var max_active_enemies: int = 6
@export var player_nodepath: NodePath
@export var use_object_pooling: bool = true
@export var pool_size: int = 10
@export var spawn_count_per_tick: int = 1  # how many enemies to spawn each timer tick

@onready var spawn_area: Area3D = $SpawnArea
@onready var _spawn_timer: Timer = $SpawnTimer
var _spawn_points: Array = []
var _active_enemies: Array = []
var _player_in_range: bool = false

# Object pool storage
var _enemy_pool: Array = []

func _ready() -> void:
	# collect spawn points under this node (Marker3D)
	for child in get_children():
		if child is Marker3D:
			_spawn_points.append(child)
	if _spawn_points.is_empty():
		push_warning("EnemySpawner: no spawn points found as Marker3D children!")

	# Setup spawn timer (create if not present)
	if not _spawn_timer:
		_spawn_timer = Timer.new()
		_spawn_timer.name = "SpawnTimer"
		add_child(_spawn_timer)
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.one_shot = false
	_spawn_timer.autostart = false
	if not _spawn_timer.is_connected("timeout", Callable(self, "_on_spawn_timeout")):
		_spawn_timer.connect("timeout", Callable(self, "_on_spawn_timeout"))

	# Connect player detection
	if spawn_area:
		if not spawn_area.is_connected("body_entered", Callable(self, "_on_body_entered")):
			spawn_area.connect("body_entered", Callable(self, "_on_body_entered"))
		if not spawn_area.is_connected("body_exited", Callable(self, "_on_body_exited")):
			spawn_area.connect("body_exited", Callable(self, "_on_body_exited"))

	# Pool init
	if use_object_pooling:
		_init_pool()

func _set_timer(t):
	_spawn_timer = t

# start/stop timer on player enter/exit
func _on_body_entered(body: Node) -> void:
	if player_nodepath == NodePath("") or not is_instance_valid(body):
		return
	if body == get_node_or_null(player_nodepath):
		_player_in_range = true
		# start timer if we have capacity
		if not _spawn_timer.is_stopped() and _spawn_timer.autostart:
			return
		_spawn_timer.start()
		print("Player entered spawn area — spawning started")

func _on_body_exited(body: Node) -> void:
	if player_nodepath == NodePath("") or not is_instance_valid(body):
		return
	if body == get_node_or_null(player_nodepath):
		_player_in_range = false
		_spawn_timer.stop()
		print("Player left spawn area — spawning stopped")

# Timer handler
func _on_spawn_timeout() -> void:
	# clean dead refs
	_active_enemies = _active_enemies.filter(func(e): return e and e.is_inside_tree())

	# while we have room, spawn up to spawn_count_per_tick (but not over max)
	var can_spawn = max_active_enemies - _active_enemies.size()
	if can_spawn <= 0:
		return
	var to_spawn = min(spawn_count_per_tick, can_spawn)
	for i in range(to_spawn):
		_spawn_enemy()

# Spawn logic
func _spawn_enemy() -> void:
	if not enemy_scene or _spawn_points.is_empty():
		return

	# choose a random spawn point
	var sp = _spawn_points[randi() % _spawn_points.size()]
	var enemy: Node3D = null

	if use_object_pooling:
		enemy = _get_enemy_from_pool()
		if not enemy:
			# pool exhausted — skip spawn (or instantiate new if you prefer)
			return
		# re-enable and parent if needed
		enemy.visible = true
		enemy.set_physics_process(true)
		# ensure parent is scene root (so transforms work predictably)
		if enemy.get_parent() != get_tree().current_scene:
			get_tree().current_scene.add_child(enemy)
	else:
		enemy = enemy_scene.instantiate()
		get_tree().current_scene.add_child(enemy)

	# position it (optionally add small jitter)
	var pos = sp.global_transform.origin
	# simple safety: raycast downwards to snap to ground if needed (optional)
	enemy.global_transform = Transform3D(enemy.global_transform.basis, pos)
	_active_enemies.append(enemy)

	# OPTIONAL: connect to a 'died' or 'returned' signal so spawner can remove it when it dies
	if enemy.has_signal("died"):
		if not enemy.is_connected("died", Callable(self, "_on_enemy_died")):
			enemy.connect("died", Callable(self, "_on_enemy_died"))
	print("Spawned enemy at", sp.name)

# Pool init / get / return
func _init_pool() -> void:
	for i in range(pool_size):
		if not enemy_scene:
			continue
		var enemy = enemy_scene.instantiate()
		enemy.visible = false
		enemy.set_physics_process(false)
		get_tree().current_scene.add_child(enemy)
		_enemy_pool.append(enemy)

func _get_enemy_from_pool() -> Node3D:
	for e in _enemy_pool:
		if not e.visible:
			return e
	return null

func return_enemy_to_pool(enemy: Node3D) -> void:
	if not use_object_pooling:
		enemy.queue_free()
		return
	if not is_instance_valid(enemy):
		return
	# detach / hide and reset transforms
	_active_enemies.erase(enemy)
	enemy.visible = false
	enemy.set_physics_process(false)
	enemy.global_transform = Transform3D.IDENTITY

# called when enemy emits "died" (optional)
func _on_enemy_died(enemy_ref: Node) -> void:
	if is_instance_valid(enemy_ref):
		_active_enemies.erase(enemy_ref)
		# if pooling, call return_to_pool method on enemy or handle here
		if use_object_pooling:
			return_enemy_to_pool(enemy_ref)
		else:
			enemy_ref.queue_free()
