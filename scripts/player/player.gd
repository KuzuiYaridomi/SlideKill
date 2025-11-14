extends RigidBody3D
# Karlson + Krunker inspired RigidBody3D movement (patched)
# Attach to a RigidBody3D root. See notes below for setup.

# ----------------- Exported tuning parameters -----------------
@export var mass_override: float = 1.2
@export var gravity_strength: float = 18.0

# Ground / air forces (these are treated as "max acceleration (m/s^2)")
@export var ground_force: float = 180.0
@export var air_force: float = 80.0
@export var max_speed: float = 18.0         # horizontal hard cap
@export var max_walk_speed: float = 8.0     # normal walking target
@export var acceleration: float = 60.0
@export var slide_hit_speed_threshold: float = 4.0
@export var slide_knockback_scale: float = 1.0

# Strafing (air & ground)
@export var strafe_force: float = 12.0
@export var strafe_air_force: float = 6.0
# how much horizontal speed (m/s) we can add per second while in air (soft control)
@export var air_control_accel: float = 10.0

# Jump / wall jump
@export var jump_velocity: float = 7.0
@export var jump_cooldown: float = 0.14
@export var wall_jump_vertical: float = 6.5
@export var wall_jump_horizontal: float = 8.5

# Sliding / slide hop
@export var slide_impulse: float = 8.0       # horizontal impulse on slide start (m/s * mass will be used)
@export var slide_boost_multiplier: float = 1.12
@export var slide_duration: float = 0.6
@export var slidehop_increase: float = 0.035
@export var max_slidehop_multiplier: float = 2.0
@export var slide_min_speed_for_transfer: float = 1.5
@export var post_boost_friction_duration: float = 0.18  # how long to keep frictionless after a boost

# slide damage tuning
@export var slide_damage_scale: float = 0.12
@export var slide_damage_min: int = 1

# slope / ramp assist
@export var slope_assist_threshold_degrees: float = 8.0
@export var slope_assist_force: float = 15.0
@export var slope_slide_force: float = 3000.0  # heavy downhill push when sliding

# damping values (we toggle these dynamically)
@export var ground_linear_damp_high: float = 10.0   # when grounded & no input -> immediate stop
@export var low_linear_damp: float = 0.08          # when sliding/airborne -> preserve momentum

# camera tuning (visual)
@export var mouse_sensitivity: float = 0.18
@export var camera_smooth_speed: float = 10.0
@export var fov_base: float = 70.0
@export var fov_max_speed: float = 20.0
@export var fov_delta: float = 8.0

# misc
@export var ground_ray_length: float = 1.1
@export var wall_ray_distance: float = 0.9

# ----------------- runtime state -----------------
var input_dir: Vector3 = Vector3.ZERO
var is_crouching: bool = false
var is_sliding: bool = false
var slide_timer: float = 0.0
var queued_slidehop: bool = false
var speed_multiplier: float = 1.0
var last_crouch_press_time: float = -10.0
var _last_slidehop_time: float = -10.0
var ready_to_jump: bool = true
var was_on_ground: bool = false

# health
@export var max_health: int = 3
var health: int = 0

# nodes (expected children)
@onready var cam_pivot: Node3D = $CameraPivot
@onready var cam: Camera3D = $CameraPivot/Camera3D
@onready var ground_ray: RayCast3D = $GroundRay
# optional wall rays; if missing, fallback ray queries are used
@onready var wall_ray_front: RayCast3D = get_node_or_null("WallRayFront")
@onready var wall_ray_back: RayCast3D = get_node_or_null("WallRayBack")
@onready var wall_ray_left: RayCast3D = get_node_or_null("WallRayLeft")
@onready var wall_ray_right: RayCast3D = get_node_or_null("WallRayRight")
@onready var slide_area: Area3D = get_node_or_null("SlideHitArea")

# internal visual smoothing & orientation
var _cam_target_pitch: float = 0.0
var _cam_visual_pitch: float = 0.0
var _cam_visual_roll: float = 0.0
var _yaw: float = 0.0   # stored yaw (radians) — use this as the authoritative yaw applied in _integrate_forces()

# timing & input ignore helpers
var _time_accum: float = 0.0
var _ground_ignore_until: float = 0.0    # ignore ground detection until this time
var _ignore_input_until: float = 0.0     # block movement input until this time (used after wall jumps/separation)
var _post_boost_frictionless_until: float = 0.0

# store original material friction so we can restore
var _orig_friction: float = 0.0
var _orig_bounce: float = 0.0

# --- scale / collision helpers (dynamic, keep movement identical across sizes) ---
@onready var _collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")
var _scale_factor: float = 1.0
var _capsule_total_height: float = 2.0
var _eye_height: float = 1.6

# ----------------- UTILS -----------------
func _ready() -> void:
	# compute dynamic scale factor (use maximum axis scale so non-uniform scale still works)
	var s = global_transform.basis.get_scale()
	_scale_factor = max(s.x, s.y, s.z, 1.0)

	# If we have a CollisionShape3D and it's a CapsuleShape3D, compute total visual height
	if _collision_shape and _collision_shape.shape and _collision_shape.shape is CapsuleShape3D:
		var cap := _collision_shape.shape as CapsuleShape3D
		# Capsule total height = cylinder height + 2 * radius
		_capsule_total_height = (cap.height + 2.0 * cap.radius) * _scale_factor
	else:
		# fallback: estimate from current node scale (2.0 was original target height)
		_capsule_total_height = 2.0 * _scale_factor

	# derive eye height and ground ray length from capsule so camera + ground checks remain correct
	_eye_height = clamp(_capsule_total_height * 0.9, 0.4, 10.0)
	ground_ray_length = max(ground_ray_length, _capsule_total_height * 0.55)

	# place camera pivot at computed eye height (local position)
	if cam_pivot:
		var p = cam_pivot.position
		p.y = _eye_height
		cam_pivot.position = p

	# if RayCast3D exists, set its target position downward to match the new ray length
	if ground_ray:
		ground_ray.target_position = Vector3(0, -ground_ray_length, 0)

	# optional override of mass for predictable impulses (keep mass constant so movement numbers stay identical)
	if mass_override > 0.0:
		self.mass = mass_override

	# health init
	health = max_health

	# capture mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# initialize camera pitch from pivot
	_cam_visual_pitch = cam_pivot.rotation_degrees.x
	_cam_target_pitch = _cam_visual_pitch
	if cam:
		cam.fov = fov_base

	# init yaw from current transform (so look doesn't snap)
	_yaw = rotation.y

	# connect slide area if present
	if slide_area:
		if not slide_area.is_connected("body_entered", Callable(self, "_on_slide_body_enter")):
			slide_area.connect("body_entered", Callable(self, "_on_slide_body_enter"))

	# ensure wall rays are enabled (if present)
	for rc in [wall_ray_front, wall_ray_back, wall_ray_left, wall_ray_right]:
		if rc:
			rc.enabled = true

	# store or create physics material override so we can change friction
	if physics_material_override:
		_orig_friction = physics_material_override.friction
		_orig_bounce = physics_material_override.bounce
	else:
		var pm = PhysicsMaterial.new()
		_orig_friction = pm.friction
		_orig_bounce = pm.bounce
		physics_material_override = pm

	# make sure the body doesn't tumble (we'll zero angular velocity in integrator)
	angular_damp = 100.0

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# immediate yaw target update (store yaw; apply during physics integration)
		_yaw += deg_to_rad(-event.relative.x * mouse_sensitivity)
		# pitch target on pivot (clamped)
		_cam_target_pitch = clamp(_cam_target_pitch - event.relative.y * mouse_sensitivity, -89.0, 89.0)

# small helper to get horizontal velocity and set it
func _get_horizontal_vel() -> Vector3:
	var lv = linear_velocity
	lv.y = 0
	return lv

func _set_horizontal_vel(v: Vector3) -> void:
	linear_velocity.x = v.x
	linear_velocity.z = v.z

# ----------------- PHYSICS STEP -----------------
func _physics_process(delta: float) -> void:
	_time_accum += delta
	_read_input()

	# ground detection via RayCast3D (GroundRay points downwards) with safe ray query fallback
	var on_ground: bool = false
	if ground_ray and ground_ray.is_enabled():
		on_ground = ground_ray.is_colliding()
	else:
		var space = get_world_3d().direct_space_state
		var fromp = global_transform.origin
		var to = fromp + Vector3.DOWN * ground_ray_length
		var params = PhysicsRayQueryParameters3D.new()
		params.from = fromp
		params.to = to
		params.exclude = [self]
		var rr = space.intersect_ray(params)
		on_ground = rr and rr.size() > 0

	# ignore ground detection temporarily if we've recently jumped/received an impulse
	if _time_accum < _ground_ignore_until:
		on_ground = false

	# restore friction after boost window automatically if passed
	if physics_material_override and _time_accum > _post_boost_frictionless_until and is_sliding == false:
		physics_material_override.friction = _orig_friction
		physics_material_override.bounce = _orig_bounce

	# dynamic damping toggles for instant stops or momentum preservation
	if on_ground and not is_sliding and input_dir == Vector3.ZERO:
		linear_damp = ground_linear_damp_high
	else:
		# very low damping when sliding/airborne/queued hop to preserve momentum
		if is_sliding or queued_slidehop:
			linear_damp = low_linear_damp * 0.2
		else:
			linear_damp = low_linear_damp

	# prevent tiny upward velocity 'pops' when truly grounded and not in ignore window
	if on_ground and _time_accum >= _ground_ignore_until:
		if linear_velocity.y > 0.15:
			linear_velocity.y = 0.0

	# apply movement forces (force-based, respects mass)
	_apply_movement_forces(delta, on_ground)

	# slope assist
	_apply_slope_assist(on_ground, delta)

	# slide timer decay
	if is_sliding:
		slide_timer -= delta
		if slide_timer <= 0.0 or not Input.is_action_pressed("crouch"):
			# restore friction & damping when slide ends
			is_sliding = false
			if physics_material_override:
				physics_material_override.friction = _orig_friction
				physics_material_override.bounce = _orig_bounce
			linear_damp = low_linear_damp

	# landing event -> apply queued slidehop if any
	if (not was_on_ground) and on_ground:
		_on_landed()

	# clamp horizontal speed (hard cap)
	var hv = _get_horizontal_vel()
	var hlen = hv.length()
	if hlen > max_speed:
		hv = hv.normalized() * max_speed
		_set_horizontal_vel(hv)

	was_on_ground = on_ground

# ----------------- MOVEMENT FORCE APPLY (physics-style) -----------------
func _apply_movement_forces(delta: float, on_ground: bool) -> void:
	# compute desired direction (world)
	var forward = -global_transform.basis.z
	var right = global_transform.basis.x
	var desired_dir = Vector3.ZERO
	# if input ignore window active, drop movement input for a short time (used after wall jumps)
	if _time_accum < _ignore_input_until:
		desired_dir = Vector3.ZERO
	elif input_dir.length() > 0.001:
		desired_dir = (forward * input_dir.z + right * input_dir.x).normalized()

	# choose max acceleration (m/s^2)
	var max_acc = ground_force if on_ground else air_force
	var m = mass

	# --- GROUND MOVEMENT: continuous thrust toward target walking speed using forces ---
	if on_ground:
		if desired_dir != Vector3.ZERO:
			var hv = _get_horizontal_vel()
			var target_vel = desired_dir * (max_walk_speed * speed_multiplier)
			# compute acceleration required to reach target_vel this physics frame
			var needed_acc = (target_vel - hv) / max(delta, 0.0001)
			# clamp accel magnitude to max_acc
			if needed_acc.length() > max_acc:
				needed_acc = needed_acc.normalized() * max_acc
			# force = mass * acceleration
			var force = needed_acc * m
			apply_central_force(force)
		# ground air-strafe bonus handled elsewhere (diagonal boost)
	else:
		# --- AIR CONTROL (momentum-preserving) ---
		# allow limited change of horizontal velocity toward desired_dir each physics frame.
		if desired_dir != Vector3.ZERO:
			var hv = _get_horizontal_vel()
			var current_along = hv.dot(desired_dir)
			var target_along = max_walk_speed * speed_multiplier
			# how much speed (m/s) can we add this frame
			var max_add = air_control_accel * delta
			var to_add = clamp(target_along - current_along, -max_add, max_add)
			# impulse = mass * delta_v
			if abs(to_add) > 0.0001:
				apply_central_impulse(desired_dir * to_add * m)
		# also allow limited air strafing perpendicular to facing (additive)
		var strafe_dir = Vector3.ZERO
		if Input.is_action_pressed("move_right"):
			strafe_dir += right
		if Input.is_action_pressed("move_left"):
			strafe_dir -= right
		if strafe_dir != Vector3.ZERO:
			var hv2 = _get_horizontal_vel()
			var spd = hv2.length()
			var factor = 1.0
			if spd > max_walk_speed:
				factor = clamp(1.0 - ((spd - max_walk_speed) / max(max_speed - max_walk_speed, 0.0001)), 0.15, 1.0)
			var desired_acc = strafe_air_force * factor
			var dv = desired_acc * delta
			apply_central_impulse(strafe_dir.normalized() * dv * m)

	# Strafing boost while moving on ground (reward diagonal runs)
	if on_ground and (Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")) and Input.is_action_pressed("move_forward"):
		var lateral = right * (1 if Input.is_action_pressed("move_right") else -1)
		var force = lateral * strafe_force * m
		apply_central_force(force)

	# JUMP / WALL-JUMP - apply impulses (additive) with stronger separation
	if Input.is_action_just_pressed("jump"):
		print("[DBG] Jump pressed ready:", ready_to_jump, "on_ground:", on_ground, "is_sliding:", is_sliding, "linvel.y:", linear_velocity.y, "time:", _time_accum)

	if Input.is_action_just_pressed("jump") and ready_to_jump:
		if on_ground:
			# set vertical velocity for crisp jump (reliable separation)
			linear_velocity.y = jump_velocity
			# reduce damping so we don't kill vertical velocity immediately
			linear_damp = low_linear_damp
			# ignore ground detection briefly to allow separation
			_ground_ignore_until = _time_accum + 0.14
			_ignore_input_until = _time_accum + 0.06
			ready_to_jump = false
			_start_jump_cooldown()
		else:
			var wn = _detect_wall_normal()
			if wn != Vector3.ZERO:
				# zero out velocity component into the wall to avoid sticking
				var vel = linear_velocity
				var into_wall = wn * vel.dot(wn)
				linear_velocity -= into_wall
				# vertical + outward push
				linear_velocity.y = wall_jump_vertical
				linear_velocity += Vector3(wn.x, 0, wn.z).normalized() * wall_jump_horizontal
				# separation windows
				_ground_ignore_until = _time_accum + 0.18
				_ignore_input_until = _time_accum + 0.18
				ready_to_jump = false
				_start_jump_cooldown()

	# CROUCH / SLIDE: start slide impulse on crouch pressed and on ground & moving
	if Input.is_action_just_pressed("crouch"):
		last_crouch_press_time = _time_accum
		#print("[DBG] crouch pressed time:", last_crouch_press_time, "on_ground:", on_ground)
		if on_ground and _get_horizontal_vel().length() > 1.0:
			if not is_sliding:
				is_sliding = true
				slide_timer = slide_duration
				var hv3 = _get_horizontal_vel()
				if hv3.length() > 0.01:
					# use desired direction (input or aim) for slide impulse to avoid misaligned boosts
					var forward_dir = -global_transform.basis.z
					var right_dir = global_transform.basis.x
					var desired = Vector3.ZERO
					if input_dir.length() > 0.001:
						desired = (forward_dir * input_dir.z + right_dir * input_dir.x).normalized()
					else:
						desired = Vector3(forward_dir.x, 0.0, forward_dir.z).normalized()
					var impulse = desired * (slide_impulse * m)
					apply_central_impulse(impulse)
					# frictionless slide: temporarily set friction to zero
					if physics_material_override:
						physics_material_override.friction = 0.0
						physics_material_override.bounce = 0.0
					linear_damp = low_linear_damp * 0.05
					_ground_ignore_until = _time_accum + 0.06
					_post_boost_frictionless_until = _time_accum + post_boost_friction_duration
		elif not on_ground:
			queued_slidehop = true

# ----------------- SLOPE ASSIST -----------------
func _apply_slope_assist(on_ground: bool, delta: float) -> void:
	if not on_ground:
		return
	var normal = Vector3.UP
	if ground_ray and ground_ray.is_colliding():
		normal = ground_ray.get_collision_normal()
	var angle_deg = rad_to_deg(acos(clamp(normal.dot(Vector3.UP), -1.0, 1.0)))
	if angle_deg > slope_assist_threshold_degrees:
		var downhill = Vector3(-normal.x, 0.0, -normal.z)
		if downhill.length() > 0.001:
			downhill = downhill.normalized()
			if is_sliding:
				# exponential boost factor based on current horizontal speed:
				var hv_len = _get_horizontal_vel().length()
				var ratio = hv_len / max(max_walk_speed, 0.0001)
				# EXPONENTIAL factor - tuned by slidehop_increase:
				var boost_factor = exp(slidehop_increase * ratio)
				boost_factor = clamp(boost_factor, 1.0, 12.0)
				apply_central_force(downhill * slope_slide_force * delta * mass * boost_factor)
			else:
				apply_central_force(downhill * slope_assist_force * delta * mass)

# ----------------- LANDING / SLIDE-HOP -----------------
func _on_landed() -> void:
	# landing; apply queued slidehop (inspired from CharacterBody logic)
	if queued_slidehop or (_time_accum - last_crouch_press_time <= 0.15):
		var hv = _get_horizontal_vel()
		if hv.length() > 0.9:
			var now = _time_accum
			if now - _last_slidehop_time >= 0.08:
				# EXponential multiplicative boost based on current speed
				var hv_len = hv.length()
				var ratio = hv_len / max(max_walk_speed, 0.0001)
				var boost_factor = exp(slidehop_increase * ratio)
				# limit growth with speed_multiplier cap
				speed_multiplier = min(speed_multiplier * boost_factor, max_slidehop_multiplier)
				# direction: input preferred else forward look
				var forward_dir = -global_transform.basis.z
				var right_dir = global_transform.basis.x
				var desired = Vector3.ZERO
				if input_dir.length() > 0.001:
					desired = (forward_dir * input_dir.z + right_dir * input_dir.x).normalized()
				else:
					desired = Vector3(forward_dir.x, 0.0, forward_dir.z).normalized()
				# compute target horizontal velocity and impulse
				var target_speed = hv_len * boost_factor
				var target_vel = desired * target_speed
				var delta_v = (target_vel - hv)
				var impulse = delta_v * mass
				apply_central_impulse(impulse)
				_last_slidehop_time = now
				is_sliding = true
				slide_timer = slide_duration
				# frictionless slide on landing boost
				if physics_material_override:
					physics_material_override.friction = 0.0
					physics_material_override.bounce = 0.0
				linear_damp = low_linear_damp * 0.05
				_ground_ignore_until = _time_accum + 0.06
				_post_boost_frictionless_until = _time_accum + post_boost_friction_duration
	queued_slidehop = false

# ----------------- WALL DETECTION -----------------
func _detect_wall_normal() -> Vector3:
	# 1) Prefer explicit RayCast3D nodes if present and colliding.
	for rc in [wall_ray_front, wall_ray_back, wall_ray_left, wall_ray_right]:
		if rc and rc.enabled and rc.is_colliding():
			var n = rc.get_collision_normal()
			if n != Vector3.ZERO:
				return n.normalized()

	# 2) Fallback: do short outward ray queries from a slightly raised origin
	var origin = global_transform.origin + Vector3.UP * 0.2   # bump up to avoid ground/self hits
	var dirs = [
		global_transform.basis.x,     # right
		-global_transform.basis.x,    # left
		global_transform.basis.z,    # forward/back depending on your orientation setup
		global_transform.basis.z * -1.0
	]

	var space = get_world_3d().direct_space_state
	for d in dirs:
		var params = PhysicsRayQueryParameters3D.new()
		params.from = origin
		params.to = origin + d.normalized() * max(wall_ray_distance, 0.6)
		params.exclude = [self]
		var res = space.intersect_ray(params)
		if res and res.has("normal"):
			return (res.get("normal") as Vector3).normalized()

	return Vector3.ZERO

# ----------------- INPUT READ -----------------
func _read_input() -> void:
	var x = 0.0
	var z = 0.0
	if Input.is_action_pressed("move_forward"):
		z += 1.0
	if Input.is_action_pressed("move_back"):
		z -= 1.0
	if Input.is_action_pressed("move_right"):
		x += 1.0
	if Input.is_action_pressed("move_left"):
		x -= 1.0
	input_dir = Vector3(x, 0.0, z)
	if input_dir.length() > 0.001:
		input_dir = input_dir.normalized()
	# crouch flag
	is_crouching = Input.is_action_pressed("crouch")

# ----------------- JUMP COOLDOWN -----------------
func _start_jump_cooldown() -> void:
	ready_to_jump = false
	_reset_jump_after_delay()

func _reset_jump_after_delay() -> void:
	await get_tree().create_timer(jump_cooldown).timeout
	ready_to_jump = true

# ----------------- SLIDE AREA COLLISION (for dealing damage optionally) -----------------
func _on_slide_body_enter(body: Node) -> void:
	if not body:
		return
	var speed = _get_horizontal_vel().length()
	if is_sliding and speed > slide_hit_speed_threshold:
		var slide_force_vec = _get_horizontal_vel().normalized() * (speed * slide_knockback_scale)
		var damage_amount = int(max(slide_damage_min, floor(speed * slide_damage_scale)))
		if Engine.has_singleton("Damagesystem"):
			var ds = Engine.get_singleton("Damagesystem")
			if ds.has_method("deal_damage"):
				ds.call_deferred("deal_damage", body, damage_amount, self, slide_force_vec, "slide")
		else:
			if typeof(Damagesystem) != TYPE_NIL and is_instance_valid(Damagesystem):
				if Damagesystem.has_method("deal_damage"):
					Damagesystem.deal_damage(body, damage_amount, self, slide_force_vec, "slide")

# ----------------- VISUAL / CAMERA SMOOTHING -----------------
func _process(delta: float) -> void:
	# camera pitch visual smoothing
	_cam_visual_pitch = lerp(_cam_visual_pitch, _cam_target_pitch, clamp(camera_smooth_speed * delta, 0.0, 1.0))
	var target_rot = Vector3(_cam_visual_pitch, 0.0, 0.0)
	cam_pivot.rotation_degrees.x = target_rot.x

	# small FOV change based on speed
	if cam:
		var h = _get_horizontal_vel().length()
		var t = clamp(h / fov_max_speed, 0.0, 1.0)
		cam.fov = lerp(fov_base, fov_base + fov_delta, t)

	# simple visual camera roll on slide
	var target_roll = 0.0
	if is_sliding:
		target_roll = lerp(0.0, -6.0, clamp(_get_horizontal_vel().length() / max_speed, 0.0, 1.0))
	_cam_visual_roll = lerp(_cam_visual_roll, target_roll, clamp(camera_smooth_speed * delta, 0.0, 1.0))
	cam_pivot.rotation_degrees.z = _cam_visual_roll

# ----------------- PHYSICS INTEGRATOR (stabilize rotations & apply yaw) -----------------
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Prevent body from rotating/tumbling (ragdoll-like). Zero angular velocity and reapply yaw-only orientation.
	state.angular_velocity = Vector3.ZERO
	# maintain current position, but set basis to yaw-only so forward vectors are stable
	var t = state.transform
	var yaw_basis = Basis(Vector3.UP, _yaw)
	t.basis = yaw_basis
	state.transform = t

	# apply explicit gravity (if you want a custom gravity stronger than engine's)
	var gravity_force = Vector3.DOWN * gravity_strength * mass
	state.apply_central_force(gravity_force)
