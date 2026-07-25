extends CharacterBody3D

## Looping AI traffic car. Follows a closed waypoint loop, slows for corners,
## brakes for the player bus / other traffic ahead, and builds its own
## detailed car body (shell, cabin glass, lights, 4 wheels) at runtime.

@export var speed: float = 11.0
@export var turn_speed: float = 2.4
@export var waypoint_radius: float = 4.0
@export var body_hue: float = 0.02

var waypoints: PackedVector3Array = PackedVector3Array()

var _index: int = 0
var _current_speed: float = 0.0
var _wheels: Array[Node3D] = []
var _brake_materials: Array[StandardMaterial3D] = []
var _head_materials: Array[StandardMaterial3D] = []
var _detector: RayCast3D = null
var _blocked: bool = false
var _stuck_time: float = 0.0


func _ready() -> void:
	add_to_group("traffic")
	floor_max_angle = deg_to_rad(60.0)
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP

	_build_collision()
	_build_car_body()
	_build_detector()

	if GameState != null:
		GameState.night_factor_changed.connect(_on_night_changed)


func setup_route(points: PackedVector3Array, start_index: int) -> void:
	waypoints = points
	if waypoints.size() > 0:
		_index = start_index % waypoints.size()
		global_position = waypoints[_index]
		_face_next()


func _face_next() -> void:
	if waypoints.size() < 2:
		return
	var next_index: int = (_index + 1) % waypoints.size()
	var target: Vector3 = waypoints[next_index]
	var flat: Vector3 = Vector3(target.x, global_position.y, target.z)
	if flat.distance_to(global_position) > 0.1:
		look_at(flat, Vector3.UP)


func _physics_process(delta: float) -> void:
	if waypoints.size() < 2:
		return

	var target: Vector3 = waypoints[_index]
	var to_target: Vector3 = target - global_position
	to_target.y = 0.0

	if to_target.length() < waypoint_radius:
		_index = (_index + 1) % waypoints.size()
		target = waypoints[_index]
		to_target = target - global_position
		to_target.y = 0.0

	var desired_dir: Vector3 = to_target.normalized()

	# Smoothly rotate toward the waypoint.
	var forward: Vector3 = -global_transform.basis.z
	var angle: float = forward.signed_angle_to(desired_dir, Vector3.UP)
	var turn: float = clampf(angle, -turn_speed * delta, turn_speed * delta)
	rotate_y(turn)

	# Slow down in corners.
	var corner_factor: float = clampf(1.0 - absf(angle) * 0.8, 0.35, 1.0)
	var target_speed: float = speed * corner_factor

	_update_blocked()
	if _blocked:
		target_speed = 0.0

	var accel: float = 6.0
	if target_speed < _current_speed:
		accel = 12.0
	_current_speed = move_toward(_current_speed, target_speed, accel * delta)

	forward = -global_transform.basis.z
	var horizontal: Vector3 = forward * _current_speed

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 22.0 * delta

	move_and_slide()

	_spin_wheels(delta)
	_update_brake_lights()

	# Anti-stuck: if we barely move for a while, skip to the next waypoint.
	if _current_speed < 0.4 and not _blocked:
		_stuck_time += delta
		if _stuck_time > 3.0:
			_stuck_time = 0.0
			_index = (_index + 1) % waypoints.size()
	else:
		_stuck_time = 0.0


func _update_blocked() -> void:
	_blocked = false
	if _detector == null or not is_instance_valid(_detector):
		return
	_detector.force_raycast_update()
	if not _detector.is_colliding():
		return
	var hit: Object = _detector.get_collider()
	if hit == null:
		return
	if hit is Node:
		var node: Node = hit as Node
		if node.is_in_group("bus") or node.is_in_group("traffic"):
			_blocked = true


func _spin_wheels(delta: float) -> void:
	var spin: float = _current_speed / 0.35 * delta
	var i: int = 0
	while i < _wheels.size():
		var wheel: Node3D = _wheels[i]
		if is_instance_valid(wheel):
			wheel.rotate_x(-spin)
		i += 1


func _update_brake_lights() -> void:
	var braking: bool = _blocked or _current_speed < speed * 0.35
	var energy: float = 0.8
	if braking:
		energy = 3.2
	var i: int = 0
	while i < _brake_materials.size():
		var mat: StandardMaterial3D = _brake_materials[i]
		if mat != null:
			mat.emission_energy_multiplier = energy
		i += 1


func _on_night_changed(night: float) -> void:
	var energy: float = 0.15 + night * 3.4
	var i: int = 0
	while i < _head_materials.size():
		var mat: StandardMaterial3D = _head_materials[i]
		if mat != null:
			mat.emission_energy_multiplier = energy
		i += 1


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _build_collision() -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.85, 1.35, 4.3)
	shape.shape = box
	shape.position = Vector3(0.0, 0.7, 0.0)
	add_child(shape)


func _build_detector() -> void:
	var ray: RayCast3D = RayCast3D.new()
	ray.name = "ForwardDetector"
	ray.position = Vector3(0.0, 0.75, 0.0)
	ray.target_position = Vector3(0.0, 0.0, -9.0)
	ray.enabled = true
	ray.collide_with_areas = false
	ray.collide_with_bodies = true
	add_child(ray)
	_detector = ray


func _build_car_body() -> void:
	var paint: StandardMaterial3D = StandardMaterial3D.new()
	paint.albedo_color = Color.from_hsv(body_hue, 0.75, 0.78)
	paint.metallic = 0.75
	paint.roughness = 0.22
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.8
	paint.clearcoat_roughness = 0.1

	var glass: StandardMaterial3D = StandardMaterial3D.new()
	glass.albedo_color = Color(0.12, 0.16, 0.22, 0.45)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.9
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED

	var trim: StandardMaterial3D = StandardMaterial3D.new()
	trim.albedo_color = Color(0.08, 0.08, 0.09)
	trim.metallic = 0.6
	trim.roughness = 0.35

	# lower body
	var lower: MeshInstance3D = MeshInstance3D.new()
	lower.name = "Chassis"
	var lower_mesh: BoxMesh = BoxMesh.new()
	lower_mesh.size = Vector3(1.8, 0.72, 4.2)
	lower.mesh = lower_mesh
	lower.position = Vector3(0.0, 0.62, 0.0)
	lower.set_surface_override_material(0, paint)
	add_child(lower)

	# cabin
	var cabin: MeshInstance3D = MeshInstance3D.new()
	cabin.name = "Cabin"
	var cabin_mesh: BoxMesh = BoxMesh.new()
	cabin_mesh.size = Vector3(1.62, 0.62, 2.1)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0.0, 1.24, 0.1)
	cabin.set_surface_override_material(0, paint)
	add_child(cabin)

	# greenhouse glass
	var glass_box: MeshInstance3D = MeshInstance3D.new()
	glass_box.name = "CabinGlass"
	var glass_mesh: BoxMesh = BoxMesh.new()
	glass_mesh.size = Vector3(1.66, 0.5, 2.0)
	glass_box.mesh = glass_mesh
	glass_box.position = Vector3(0.0, 1.28, 0.1)
	glass_box.set_surface_override_material(0, glass)
	add_child(glass_box)

	# hood + boot slabs
	var hood: MeshInstance3D = MeshInstance3D.new()
	hood.name = "Hood"
	var hood_mesh: BoxMesh = BoxMesh.new()
	hood_mesh.size = Vector3(1.72, 0.28, 1.1)
	hood.mesh = hood_mesh
	hood.position = Vector3(0.0, 1.05, -1.6)
	hood.set_surface_override_material(0, paint)
	add_child(hood)

	var boot: MeshInstance3D = MeshInstance3D.new()
	boot.name = "Boot"
	var boot_mesh: BoxMesh = BoxMesh.new()
	boot_mesh.size = Vector3(1.72, 0.26, 0.9)
	boot.mesh = boot_mesh
	boot.position = Vector3(0.0, 1.04, 1.7)
	boot.set_surface_override_material(0, paint)
	add_child(boot)

	# bumpers
	var bumper_zs: Array[float] = [-2.12, 2.12]
	var bi: int = 0
	while bi < bumper_zs.size():
		var bumper: MeshInstance3D = MeshInstance3D.new()
		bumper.name = "Bumper" + str(bi)
		var bumper_mesh: BoxMesh = BoxMesh.new()
		bumper_mesh.size = Vector3(1.84, 0.3, 0.2)
		bumper.mesh = bumper_mesh
		bumper.position = Vector3(0.0, 0.5, bumper_zs[bi])
		bumper.set_surface_override_material(0, trim)
		add_child(bumper)
		bi += 1

	_build_car_lights()
	_build_car_wheels(trim)


func _build_car_lights() -> void:
	var xs: Array[float] = [-0.62, 0.62]

	var i: int = 0
	while i < xs.size():
		var x: float = xs[i]
		var label: String = "L"
		if x > 0.0:
			label = "R"

		var head_mat: StandardMaterial3D = StandardMaterial3D.new()
		head_mat.albedo_color = Color(0.92, 0.92, 0.85)
		head_mat.emission_enabled = true
		head_mat.emission = Color(1.0, 0.95, 0.82)
		head_mat.emission_energy_multiplier = 0.6
		head_mat.roughness = 0.15
		_head_materials.append(head_mat)

		var head: MeshInstance3D = MeshInstance3D.new()
		head.name = "Headlight_" + label
		var head_mesh: BoxMesh = BoxMesh.new()
		head_mesh.size = Vector3(0.34, 0.16, 0.1)
		head.mesh = head_mesh
		head.position = Vector3(x, 0.86, -2.14)
		head.set_surface_override_material(0, head_mat)
		add_child(head)

		var brake_mat: StandardMaterial3D = StandardMaterial3D.new()
		brake_mat.albedo_color = Color(0.42, 0.04, 0.04)
		brake_mat.emission_enabled = true
		brake_mat.emission = Color(1.0, 0.10, 0.05)
		brake_mat.emission_energy_multiplier = 1.2
		brake_mat.roughness = 0.25
		_brake_materials.append(brake_mat)

		var tail: MeshInstance3D = MeshInstance3D.new()
		tail.name = "TailLight_" + label
		var tail_mesh: BoxMesh = BoxMesh.new()
		tail_mesh.size = Vector3(0.32, 0.15, 0.1)
		tail.mesh = tail_mesh
		tail.position = Vector3(x, 0.88, 2.14)
		tail.set_surface_override_material(0, brake_mat)
		add_child(tail)

		i += 1


func _build_car_wheels(trim: StandardMaterial3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(-0.92, 0.35, -1.42),
		Vector3(0.92, 0.35, -1.42),
		Vector3(-0.92, 0.35, 1.42),
		Vector3(0.92, 0.35, 1.42),
	]

	var rim_mat: StandardMaterial3D = StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.72, 0.74, 0.78)
	rim_mat.metallic = 0.95
	rim_mat.roughness = 0.2

	var i: int = 0
	while i < positions.size():
		var pivot: Node3D = Node3D.new()
		pivot.name = "Wheel" + str(i)
		pivot.position = positions[i]
		add_child(pivot)

		var tire: MeshInstance3D = MeshInstance3D.new()
		tire.name = "Tire"
		var tire_mesh: CylinderMesh = CylinderMesh.new()
		tire_mesh.top_radius = 0.35
		tire_mesh.bottom_radius = 0.35
		tire_mesh.height = 0.24
		tire_mesh.radial_segments = 16
		tire.mesh = tire_mesh
		tire.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		tire.set_surface_override_material(0, trim)
		pivot.add_child(tire)

		var rim: MeshInstance3D = MeshInstance3D.new()
		rim.name = "Rim"
		var rim_mesh: CylinderMesh = CylinderMesh.new()
		rim_mesh.top_radius = 0.2
		rim_mesh.bottom_radius = 0.2
		rim_mesh.height = 0.26
		rim_mesh.radial_segments = 12
		rim.mesh = rim_mesh
		rim.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		rim.set_surface_override_material(0, rim_mat)
		pivot.add_child(rim)

		_wheels.append(pivot)
		i += 1
