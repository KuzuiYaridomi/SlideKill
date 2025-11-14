extends Node3D
# Single-file motion blur for Godot 4.5
# Attach this node as a child of your Camera3D (or set camera_path to the camera).
# It creates a fullscreen quad and shader at runtime and updates motion parameters.

@export var camera_path: NodePath = NodePath("..") # default: parent (use when child of Camera3D)
@export var enabled: bool = true
@export var intensity: float = 0.9               # overall intensity multiplier
@export var iteration_count: int = 6             # shader sample iterations (quality vs cost)
@export var start_radius: float = 0.18
@export var motion_scale: float = 1.0
@export var downsample: int = 1                  # not used for render targets here, kept for parity

# tweak how sensitive the motion magnitude is to linear / angular motion:
@export var linear_weight: float = 0.02
@export var angular_weight: float = 0.5

# internal nodes
var _camera: Camera3D = null
var _quad: MeshInstance3D = null
var _mat: ShaderMaterial = null

# previous transform for motion calc
var _last_transform: Transform3D
var _last_time: float = 0.0

func _ready() -> void:
	# Resolve camera (try explicit path, else check parents)
	_camera = get_node_or_null(camera_path) as Camera3D
	if not _camera:
		# try to find camera in parent chain
		var n = get_parent()
		while n:
			if n is Camera3D:
				_camera = n
				break
			n = n.get_parent()
	if not _camera:
		push_error("motion_blur_single.gd: No Camera3D found. Set camera_path or make this node child of a Camera3D.")
		return

	# Create the fullscreen quad mesh (QuadMesh sized to cover frustum at near plane)
	_quad = MeshInstance3D.new()
	_quad.name = "MotionBlurQuad"
	_quad.mesh = QuadMesh.new()
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.visible = enabled
	_quad.material_override = _create_shader_material()
	add_child(_quad)
	_quad.owner = owner

	# place quad in camera-local space
	_update_quad_transform_and_size()

	# init last transform/time
	_last_transform = _camera.global_transform
	_last_time = Engine.get_physics_frames() / 60.0

	# ensure process runs
	set_process(true)

func _physics_process(delta: float) -> void:
	# keep quad fitted if camera FOV/aspect changes during runtime (cheap)
	if _camera:
		_update_quad_transform_and_size()
	_update_shader_params(delta)

func _process(delta: float) -> void:
	# keep visibility synced to enabled flag
	if _quad:
		_quad.visible = enabled

# create ShaderMaterial with embedded shader code
func _create_shader_material() -> ShaderMaterial:
	var shader_code := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float intensity : hint_range(0.0, 4.0) = 0.9;
uniform int iterations : hint_range(1, 32) = 6;
uniform float start_radius : hint_range(0.0, 1.0) = 0.18;
uniform float motion_amount : hint_range(0.0, 8.0) = 0.0;
uniform float downsample : hint_range(1.0, 4.0) = 1.0;

vec2 screen_uv() {
	return SCREEN_UV;
}

vec4 sample_offset(vec2 uv, vec2 offset) {
	return texture(SCREEN_TEXTURE, uv + offset);
}

void fragment() {
	vec2 uv = screen_uv();
	float rad = start_radius + motion_amount * 0.5 * intensity;
	vec4 accum = vec4(0.0);
	float total = 0.0;
	// spiral sampling
	for (int i = 0; i < iterations; i++) {
		float pct = float(i) / max(1.0, float(iterations - 1));
		float a = pct * 6.28318530718 * 3.0;
		float r = rad * pct;
		vec2 off = vec2(cos(a), sin(a)) * r;
		accum += sample_offset(uv, off);
		total += 1.0;
	}
	if (total <= 0.0) {
		COLOR = texture(SCREEN_TEXTURE, uv);
	} else {
		COLOR = accum / total;
	}
}
"""
	var shader = Shader.new()
	shader.code = shader_code
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	# initial uniforms
	_mat.set_shader_parameter("intensity", intensity)
	_mat.set_shader_parameter("iterations", iteration_count)
	_mat.set_shader_parameter("start_radius", start_radius)
	_mat.set_shader_parameter("motion_amount", 0.0)
	_mat.set_shader_parameter("downsample", float(downsample))
	return _mat

# Compute screen-covering quad dimensions and put it slighty in front of camera near plane
func _update_quad_transform_and_size() -> void:
	if not _camera or not _quad:
		return
	# distance from camera to place the quad (slightly in front of near plane)
	var d = max(0.01, _camera.near + 0.01)
	# fov is vertical in degrees; compute quad height/width at distance d
	var fov_rad = deg_to_rad(_camera.fov)
	var height = 2.0 * d * tan(fov_rad * 0.5)
	var aspect = _camera.get_viewport().size.x / max(1.0, _camera.get_viewport().size.y)
	var width = height * aspect

	# update QuadMesh size
	var qm := _quad.mesh as QuadMesh
	qm.size = Vector2(width, height)
	_quad.mesh = qm

	# set transform: put the quad forward along -Z (camera looks -Z) so use local -Z
	var local_xform = Transform3D.IDENTITY
	# position: in camera local coords, forward = -Z
	local_xform.origin = Vector3(0.0, 0.0, -d)
	# rotate to face camera: identity is fine (quad plane faces +Z), but in Godot QuadMesh face normal is +Z; we want it to face camera so rotate 180 around X? Simpler: set billboard by aligning basis.
	# We want quad's +Z to point toward camera, so set basis to camera basis
	local_xform.basis = Basis(Vector3(1,0,0), Vector3(0,1,0), Vector3(0,0,1)) # identity
	# Parent to camera (so transform is camera-local)
	if _quad.get_parent() != _camera:
		_camera.add_child(_quad)
	_quad.transform = local_xform
	_quad.transform = local_xform
	# ensure quad is directly in front and inherits camera orientation (child of camera)
	_quad.rotation = Vector3.ZERO

# Update shader inputs using camera motion (linear + angular)
func _update_shader_params(delta: float) -> void:
	if not _camera or not _mat:
		return
	var dt = max(delta, 0.000001)
	var now_transform = _camera.global_transform

	# linear velocity
	var lin_vel = (now_transform.origin - _last_transform.origin) / dt
	# angular velocity approx via quaternion delta -> euler
	var from_basis = _last_transform.basis
	var to_basis = now_transform.basis
	var r = (to_basis * from_basis.inverse()).get_rotation_quaternion()
	var ang = r.get_euler() / dt

	# motion magnitude
	var motion_mag = (lin_vel.length() * linear_weight + ang.length() * angular_weight) * motion_scale

	# set shader params (clamp to reasonable)
	var motion_amount = clamp(motion_mag, 0.0, 12.0)
	_mat.set_shader_parameter("motion_amount", motion_amount)
	_mat.set_shader_parameter("intensity", intensity)
	_mat.set_shader_parameter("iterations", iteration_count)
	_mat.set_shader_parameter("start_radius", start_radius)
	_mat.set_shader_parameter("downsample", float(downsample))

	_last_transform = now_transform

# Public API
func set_enabled(on: bool) -> void:
	enabled = on
	if _quad:
		_quad.visible = enabled

func set_intensity(v: float) -> void:
	intensity = v
	if _mat:
		_mat.set_shader_parameter("intensity", intensity)

func enable() -> void:
	set_enabled(true)

func disable() -> void:
	set_enabled(false)
