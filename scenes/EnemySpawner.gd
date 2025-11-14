extends Node3D

@export var enemy_scene: PackedScene
@export var spawn_interval: float = 5.0           # base interval (seconds)
@export var spawn_randomness: float = 0.5         # ± variation per spawn
@export var spawn_burst_count: int = 1            # enemies per spawn event
@export var max_active_enemies: int = 6
@export var player_nodepath: NodePath
@export var use_object_pooling: bool = true
@export var pool_size: int = 10

@onready var spawn_area: Area3D = $SpawnArea
var _spawn_points: Array = []
var _spawn_timer: float = 0.0
var _active_enemies: Array = []
var _player_in_range: bool = false

# Object pool storage
var _enemy_pool: Array = []

func _ready() -> void:
	# Collect all spawn points (Marker3D)
	for child in get_children():
		if child is Marker3D:
			_spawn_points.append(child)
	if _spawn_points.is_empty():
		push_warning("No spawn points found under EnemySpawner!")

	# Connect player detection
	if spawn_area:
		if not spawn_area.is_connected("body_entered", Callable(self, "_on_body_entered")):
			spawn_area.connect("body_entered", Callable(self, "_on_body_entered"))
		if not spawn_area.is_connected("body_exited", Callable(self, "_on_body_exited")):
			spawn_area.connect("body_exited", Callable(self, "_on_body_exited"))

	# Initialize pooling if enabled
	if use_object_pooling:
		_init_pool()

	_spawn_timer = spawn_interval


func _process(delta: float) -> void:
	if not _player_in_range:
		return

	# Clean dead references
	_active_enemies = _active_enemies.filter(func(e): return e and e.is_inside_tree())

	if _active_enemies.size() < max_active_enemies:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			for i in range(spawn_burst_count):
				if _active_enemies.size() >= max_active_enemies:
					break
				_spawn_enemy()
			# Randomize next spawn time
			_spawn_timer = spawn_interval + randf_range(-spawn_randomness, spawn_randomness)


# --- SPAWN LOGIC ---
func _spawn_enemy() -> void:
	if not enemy_scene or _spawn_points.is_empty():
		return

	var sp = _spawn_points[randi() % _spawn_points.size()]
	var enemy: Node3D

	if use_object_pooling:
		enemy = _get_enemy_from_pool()
		if not enemy:
			return
	else:
		enemy = enemy_scene.instantiate()
		get_tree().current_scene.add_child(enemy)

	enemy.global_transform.origin = sp.global_transform.origin
	enemy.visible = true
	enemy.set_physics_process(true)
	_active_enemies.append(enemy)
	print("Spawned enemy at", sp.name)


# --- PLAYER DETECTION ---
func _on_body_entered(body: Node) -> void:
	if player_nodepath == NodePath("") or not is_instance_valid(body):
		return
	if body == get_node_or_null(player_nodepath):
		_player_in_range = true
		print("Player entered spawn area")


func _on_body_exited(body: Node) -> void:
	if player_nodepath == NodePath("") or not is_instance_valid(body):
		return
	if body == get_node_or_null(player_nodepath):
		_player_in_range = false
		print("Player left spawn area")


# --- OBJECT POOLING SYSTEM ---
func _init_pool() -> void:
	for i in range(pool_size):
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


# Call this from your enemy when it dies to return to pool
func return_enemy_to_pool(enemy: Node3D) -> void:
	if not use_object_pooling:
		return
	enemy.visible = false
	enemy.set_physics_process(false)
	enemy.global_position = Vector3.ZERO
