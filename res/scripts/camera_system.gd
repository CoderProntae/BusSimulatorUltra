extends Node3D

## Three camera modes: chase (anti-clip raycast), interior at the steering
## wheel, and top-down orthographic. Attach as a sibling of the bus and set
## the "target" NodePath (or let it auto-find the bus group).

enum CameraMode { CHASE, INTERIOR, TOPDOWN }

const MODE_NAMES: Array[String] = ["CHASE", "INTERIOR", "TOP"]

@export var target_path: NodePath
@export var chase_distance: float = 11.0
@export var chase_height: float = 4.4
@export var chase_smoothing: float = 5.0
@export var look_smoothing: float = 8.0

var mode: int = CameraMode.CHASE
var target: Node3D = null

var _camera: Camera3D = null
var _ray: RayCast3D = null
var _current_pos: Vector3 = Vector3.ZERO
var _current_look: Vector3 = Vector3.ZERO
var _initialized: bool = false
## Interior camera: driver head lean into corners, and engine/road shake.
var _head_lean: float = 0.0
var _shake_time: float = 0.0


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "GameCamera"
	_camera.current = true
	_camera.fov = 68.0
	_camera.near = 0.08
	_camera.far = 700.0
	add_child(_camera)

	_ray = RayCast3D.new()
	_ray.name = "AntiClipRay"
	_ray.enabled = true
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	add_child(_ray)

	_resolve_target()
	set_mode(CameraMode.CHASE)


func _resolve_target() -> void:
	if target_path != NodePath("") and has_node(target_path):
		target = get_node(target_path) as Node3D
	if target == null:
		var buses: Array = get_tree().get_nodes_in_group("bus")
		if buses.size() > 0:
			target = buses[0] as Node3D


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_resolve_target()
		return
	if _camera == null:
		return

	if mode == CameraMode.CHASE:
		_update_chase(delta)
	elif mode == CameraMode.INTERIOR:
		_update_interior(delta)
	else:
		_update_topdown(delta)


func _update_chase(delta: float) -> void:
	var basis: Basis = target.global_transform.basis
	var origin: Vector3 = target.global_transform.origin

	# The bus is a VehicleBody3D: its forward is +Z (Vector3.MODEL_FRONT),
	# so "back" (where the chase camera sits) is -Z.
	var back: Vector3 = -basis.z.normalized()
	var up: Vector3 = Vector3.UP

	var desired: Vector3 = origin + back * chase_distance + up * chase_height

	# Anti-clip: cast from just above the bus toward the desired camera spot.
	var from: Vector3 = origin + up * 2.2
	_ray.global_position = from
	_ray.target_position = _ray.to_local(desired)
	_ray.force_raycast_update()
	if _ray.is_colliding():
		var hit: Vector3 = _ray.get_collision_point()
		var to_hit: Vector3 = hit - from
		var safe: Vector3 = from + to_hit * 0.86
		if safe.distance_to(from) > 2.0:
			desired = safe
		else:
			desired = from + to_hit.normalized() * 2.0

	var look_at_point: Vector3 = origin + up * 1.6 - back * 3.0

	if not _initialized:
		_current_pos = desired
		_current_look = look_at_point
		_initialized = true

	var t: float = clampf(chase_smoothing * delta, 0.0, 1.0)
	var lt: float = clampf(look_smoothing * delta, 0.0, 1.0)
	_current_pos = _current_pos.lerp(desired, t)
	_current_look = _current_look.lerp(look_at_point, lt)

	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	# Restore the default near plane; the interior mode tightens it to 0.02.
	_camera.near = 0.08
	_camera.global_position = _current_pos
	_safe_look_at(_current_look)

	# subtle speed FOV
	var speed: float = 0.0
	if target is VehicleBody3D:
		speed = (target as VehicleBody3D).linear_velocity.length() * 3.6
	_camera.fov = lerpf(_camera.fov, 66.0 + clampf(speed / 80.0, 0.0, 1.0) * 8.0, t)


func _update_interior(delta: float) -> void:
	var anchor: Node3D = _find_child_node("InteriorAnchor")
	var pos: Vector3 = target.global_transform.origin
	if anchor != null:
		pos = anchor.global_transform.origin
	else:
		pos = target.to_global(Vector3(0.66, 0.30, 8.0))

	var basis: Basis = target.global_transform.basis

	# Subtle head motion so the cab feels inhabited rather than bolted down.
	# Leaning INTO the corner is what a driver actually does.
	var lateral: float = 0.0
	var speed_ms: float = 0.0
	if target is VehicleBody3D:
		var body: VehicleBody3D = target as VehicleBody3D
		speed_ms = body.linear_velocity.length()
		# Sideways acceleration in the bus's own frame.
		lateral = body.linear_velocity.dot(basis.x)
	_head_lean = lerpf(_head_lean, clampf(lateral * 0.035, -0.09, 0.09),
		clampf(delta * 3.0, 0.0, 1.0))

	# Engine shake, strongest at low speed under load, plus road buzz.
	_shake_time += delta * (7.0 + speed_ms * 0.7)
	var idle_shake: float = 0.0016
	var road_shake: float = clampf(speed_ms / 22.0, 0.0, 1.0) * 0.0042
	var shake: float = idle_shake + road_shake
	var bob: Vector3 = Vector3(
		sin(_shake_time * 1.7) * shake,
		sin(_shake_time * 2.3) * shake * 1.3,
		0.0
	)

	pos += basis.x * _head_lean + basis * bob

	# Look out through the windshield, i.e. along the bus forward (+Z),
	# aimed slightly down at the road rather than at the sky.
	var look_point: Vector3 = pos + basis.z * 14.0 - Vector3.UP * 0.9
	# Glance into the turn a little; makes cornering far more readable.
	look_point += basis.x * (-_head_lean * 9.0)

	# Snap on the first frame so the camera never flies in from the old mode.
	if not _initialized:
		_current_pos = pos
		_current_look = look_point
		_initialized = true

	var t: float = clampf(24.0 * delta, 0.0, 1.0)
	_current_pos = _current_pos.lerp(pos, t)
	_current_look = _current_look.lerp(look_point, t)

	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	# Slightly wider than the chase view: a cab feels cramped otherwise.
	_camera.fov = lerpf(_camera.fov, 78.0, t)
	# Near plane must be tight or the steering wheel and dash clip away.
	_camera.near = 0.02
	_camera.global_position = _current_pos
	_safe_look_at(_current_look)


func _update_topdown(delta: float) -> void:
	var origin: Vector3 = target.global_transform.origin
	var desired: Vector3 = origin + Vector3(0.0, 48.0, 0.01)

	var t: float = clampf(6.0 * delta, 0.0, 1.0)
	_current_pos = _current_pos.lerp(desired, t)
	_current_look = _current_look.lerp(origin, t)

	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 62.0
	_camera.global_position = _current_pos
	_safe_look_at(_current_look)


func _safe_look_at(point: Vector3) -> void:
	var to_point: Vector3 = point - _camera.global_position
	if to_point.length() < 0.05:
		return
	var dir: Vector3 = to_point.normalized()
	if absf(dir.dot(Vector3.UP)) > 0.999:
		_camera.look_at(point, Vector3.FORWARD)
		return
	_camera.look_at(point, Vector3.UP)


func _find_child_node(node_name: String) -> Node3D:
	if target == null:
		return null
	var found: Node = target.find_child(node_name, false, false)
	if found != null and found is Node3D:
		return found as Node3D
	return null


func cycle_mode() -> int:
	var next: int = mode + 1
	if next > CameraMode.TOPDOWN:
		next = CameraMode.CHASE
	set_mode(next)
	return mode


func set_mode(new_mode: int) -> void:
	mode = clampi(new_mode, 0, 2)
	_initialized = false
	if target != null and is_instance_valid(target):
		_current_pos = target.global_transform.origin
		_current_look = target.global_transform.origin


func mode_name() -> String:
	var index: int = clampi(mode, 0, MODE_NAMES.size() - 1)
	return MODE_NAMES[index]


func get_camera() -> Camera3D:
	return _camera
