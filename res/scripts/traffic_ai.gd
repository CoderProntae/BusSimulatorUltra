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

# --- crash / damage state ---
enum CarState { DRIVING, REVERSING, WRECKED, BURNING, EXPLODED }
var car_state: int = CarState.DRIVING
var health: float = 100.0
var _reverse_timer: float = 0.0
var _burn_timer: float = 0.0
var _respawn_timer: float = 0.0
var _fire: GPUParticles3D = null
var _smoke: GPUParticles3D = null
var _explosion: GPUParticles3D = null
var _fire_light: OmniLight3D = null
var _body_materials: Array[StandardMaterial3D] = []
var _hidden_parts: Array[Node3D] = []
var _spawn_point: Vector3 = Vector3.ZERO
var _last_velocity: Vector3 = Vector3.ZERO


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
	if car_state == CarState.WRECKED or car_state == CarState.BURNING:
		_update_wreck(delta)
		return
	if car_state == CarState.EXPLODED:
		_update_respawn(delta)
		return
	if car_state == CarState.REVERSING:
		_update_reversing(delta)
		return
	if waypoints.size() < 2:
		return

	_detect_collisions()
	if car_state != CarState.DRIVING:
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

	_last_velocity = velocity
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
	# Tracked so crash damage can scorch the paint and _respawn() can reset it.
	_body_materials.append(paint)

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
	_hidden_parts.append(lower)

	# cabin
	var cabin: MeshInstance3D = MeshInstance3D.new()
	cabin.name = "Cabin"
	var cabin_mesh: BoxMesh = BoxMesh.new()
	cabin_mesh.size = Vector3(1.62, 0.62, 2.1)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0.0, 1.24, 0.1)
	cabin.set_surface_override_material(0, paint)
	add_child(cabin)
	_hidden_parts.append(cabin)

	# greenhouse glass
	var glass_box: MeshInstance3D = MeshInstance3D.new()
	glass_box.name = "CabinGlass"
	var glass_mesh: BoxMesh = BoxMesh.new()
	glass_mesh.size = Vector3(1.66, 0.5, 2.0)
	glass_box.mesh = glass_mesh
	glass_box.position = Vector3(0.0, 1.28, 0.1)
	glass_box.set_surface_override_material(0, glass)
	add_child(glass_box)
	_hidden_parts.append(glass_box)

	# hood + boot slabs
	var hood: MeshInstance3D = MeshInstance3D.new()
	hood.name = "Hood"
	var hood_mesh: BoxMesh = BoxMesh.new()
	hood_mesh.size = Vector3(1.72, 0.28, 1.1)
	hood.mesh = hood_mesh
	hood.position = Vector3(0.0, 1.05, -1.6)
	hood.set_surface_override_material(0, paint)
	add_child(hood)
	_hidden_parts.append(hood)

	var boot: MeshInstance3D = MeshInstance3D.new()
	boot.name = "Boot"
	var boot_mesh: BoxMesh = BoxMesh.new()
	boot_mesh.size = Vector3(1.72, 0.26, 0.9)
	boot.mesh = boot_mesh
	boot.position = Vector3(0.0, 1.04, 1.7)
	boot.set_surface_override_material(0, paint)
	add_child(boot)
	_hidden_parts.append(boot)

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
		_hidden_parts.append(bumper)
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
		_hidden_parts.append(pivot)
		i += 1


# ---------------------------------------------------------------------------
# Crash, damage, fire and explosion
# ---------------------------------------------------------------------------

func _detect_collisions() -> void:
	## move_and_slide() reports what we hit this frame. A hard hit from the bus
	## (or another car) damages this car; a light tap just makes it reverse and
	## re-align, so traffic can recover instead of jamming forever.
	var count: int = get_slide_collision_count()
	if count <= 0:
		return

	var i: int = 0
	while i < count:
		var col: KinematicCollision3D = get_slide_collision(i)
		if col == null:
			i += 1
			continue
		var other: Object = col.get_collider()
		if other == null or not (other is Node):
			i += 1
			continue
		var node: Node = other as Node

		var is_vehicle: bool = node.is_in_group("bus") or node.is_in_group("traffic")
		if not is_vehicle:
			i += 1
			continue

		# Closing speed along the contact normal drives the damage.
		var other_vel: Vector3 = Vector3.ZERO
		if node is VehicleBody3D:
			other_vel = (node as VehicleBody3D).linear_velocity
		elif node.has_method("get_velocity"):
			var v: Variant = node.call("get_velocity")
			if v is Vector3:
				other_vel = v as Vector3

		var relative: Vector3 = _last_velocity - other_vel
		var impact: float = absf(relative.dot(col.get_normal()))

		if impact > 6.0:
			_take_damage(impact * 7.0, col.get_normal())
		elif impact > 1.2:
			_begin_reverse()
		i += 1


func _take_damage(amount: float, normal: Vector3) -> void:
	if car_state == CarState.EXPLODED:
		return
	health -= amount
	_apply_damage_tint()

	# Shove the car away from the impact so it visibly reacts.
	velocity += normal * -3.0
	_current_speed *= 0.3

	if health <= 0.0:
		_start_burning()
	elif health < 45.0:
		_start_wreck()
	else:
		_begin_reverse()

	if GameState != null and amount > 45.0:
		GameState.notify("Crash!")


func _apply_damage_tint() -> void:
	var ratio: float = clampf(health / 100.0, 0.0, 1.0)
	var i: int = 0
	while i < _body_materials.size():
		var mat: StandardMaterial3D = _body_materials[i]
		if mat != null:
			# Scorch the paint as the car gets wrecked.
			mat.albedo_color = mat.albedo_color.lerp(Color(0.10, 0.09, 0.08), (1.0 - ratio) * 0.12)
			mat.roughness = clampf(0.22 + (1.0 - ratio) * 0.7, 0.0, 1.0)
		i += 1


func _begin_reverse() -> void:
	if car_state != CarState.DRIVING:
		return
	car_state = CarState.REVERSING
	_reverse_timer = randf_range(0.9, 1.7)


func _update_reversing(delta: float) -> void:
	## Back away from whatever we bumped into, then resume the route.
	_reverse_timer -= delta
	var back: Vector3 = global_transform.basis.z
	velocity.x = back.x * 4.0
	velocity.z = back.z * 4.0
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 22.0 * delta
	move_and_slide()
	_spin_wheels(-delta)

	# Reversing lights + brake lights on
	var i: int = 0
	while i < _brake_materials.size():
		var mat: StandardMaterial3D = _brake_materials[i]
		if mat != null:
			mat.emission_energy_multiplier = 3.2
		i += 1

	if _reverse_timer <= 0.0:
		car_state = CarState.DRIVING
		_current_speed = 0.0


func _start_wreck() -> void:
	if car_state == CarState.WRECKED or car_state == CarState.BURNING:
		return
	car_state = CarState.WRECKED
	_burn_timer = randf_range(2.5, 5.0)
	_ensure_effects()
	if _smoke != null:
		_smoke.emitting = true


func _start_burning() -> void:
	if car_state == CarState.BURNING:
		return
	car_state = CarState.BURNING
	_burn_timer = randf_range(2.0, 3.5)
	_ensure_effects()
	if _smoke != null:
		_smoke.emitting = true
	if _fire != null:
		_fire.emitting = true
	if _fire_light != null:
		_fire_light.visible = true
	if GameState != null:
		GameState.notify("A car caught fire!")


func _update_wreck(delta: float) -> void:
	# Roll to a stop.
	_current_speed = move_toward(_current_speed, 0.0, 14.0 * delta)
	var forward: Vector3 = -global_transform.basis.z
	velocity.x = forward.x * _current_speed
	velocity.z = forward.z * _current_speed
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 22.0 * delta
	move_and_slide()

	if _fire_light != null and is_instance_valid(_fire_light):
		_fire_light.light_energy = 2.2 + sin(Time.get_ticks_msec() * 0.02) * 1.1

	_burn_timer -= delta
	if _burn_timer > 0.0:
		return

	if car_state == CarState.WRECKED:
		_start_burning()
	else:
		_explode()


func _explode() -> void:
	car_state = CarState.EXPLODED
	_respawn_timer = 6.0
	_ensure_effects()

	if _explosion != null:
		_explosion.emitting = true
	if _fire != null:
		_fire.emitting = false
	if _fire_light != null:
		_fire_light.light_energy = 14.0

	# Hide the bodywork: the car has blown apart.
	var i: int = 0
	while i < _hidden_parts.size():
		var node: Node3D = _hidden_parts[i]
		if is_instance_valid(node):
			node.visible = false
		i += 1

	velocity = Vector3.ZERO
	_current_speed = 0.0

	if GameState != null:
		GameState.notify("Explosion!")


func _update_respawn(delta: float) -> void:
	_respawn_timer -= delta

	# Fade the blast light out quickly.
	if _fire_light != null and is_instance_valid(_fire_light):
		_fire_light.light_energy = maxf(0.0, _fire_light.light_energy - delta * 9.0)
		if _fire_light.light_energy <= 0.05:
			_fire_light.visible = false

	if _respawn_timer > 0.0:
		return
	_respawn()


func _respawn() -> void:
	health = 100.0
	car_state = CarState.DRIVING
	_current_speed = 0.0
	velocity = Vector3.ZERO

	if _fire != null:
		_fire.emitting = false
	if _smoke != null:
		_smoke.emitting = false
	if _explosion != null:
		_explosion.emitting = false
	if _fire_light != null and is_instance_valid(_fire_light):
		_fire_light.visible = false

	var i: int = 0
	while i < _hidden_parts.size():
		var node: Node3D = _hidden_parts[i]
		if is_instance_valid(node):
			node.visible = true
		i += 1

	# Reset the paint and drop back onto the route.
	i = 0
	while i < _body_materials.size():
		var mat: StandardMaterial3D = _body_materials[i]
		if mat != null:
			mat.albedo_color = Color.from_hsv(body_hue, 0.75, 0.78)
			mat.roughness = 0.22
		i += 1

	if waypoints.size() > 0:
		_index = randi() % waypoints.size()
		global_position = waypoints[_index]
		_face_next()


func _ensure_effects() -> void:
	if _fire != null:
		return
	_smoke = _make_particles("Smoke", false)
	_fire = _make_particles("Fire", true)
	_explosion = _make_explosion()

	var light: OmniLight3D = OmniLight3D.new()
	light.name = "FireLight"
	light.position = Vector3(0.0, 1.1, -1.2)
	light.light_color = Color(1.0, 0.55, 0.18)
	light.light_energy = 0.0
	light.omni_range = 12.0
	light.shadow_enabled = false
	light.visible = false
	add_child(light)
	_fire_light = light


func _make_particles(node_name: String, is_fire: bool) -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = node_name
	particles.position = Vector3(0.0, 1.0, -1.6)
	particles.emitting = false
	particles.one_shot = false
	particles.local_coords = false

	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 22.0
	mat.gravity = Vector3(0.0, 1.2, 0.0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.35

	var mesh: QuadMesh = QuadMesh.new()
	var draw_mat: StandardMaterial3D = StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_mat.vertex_color_use_as_albedo = true

	if is_fire:
		particles.amount = 26
		particles.lifetime = 0.7
		mat.initial_velocity_min = 1.6
		mat.initial_velocity_max = 3.4
		mat.scale_min = 0.5
		mat.scale_max = 1.2
		mesh.size = Vector2(0.9, 0.9)
		draw_mat.albedo_color = Color(1.0, 0.55, 0.12, 0.9)
		draw_mat.emission_enabled = true
		draw_mat.emission = Color(1.0, 0.45, 0.08)
		draw_mat.emission_energy_multiplier = 4.0
	else:
		particles.amount = 20
		particles.lifetime = 2.4
		mat.initial_velocity_min = 0.8
		mat.initial_velocity_max = 1.8
		mat.scale_min = 0.8
		mat.scale_max = 2.4
		mesh.size = Vector2(1.4, 1.4)
		draw_mat.albedo_color = Color(0.12, 0.12, 0.13, 0.5)

	mesh.material = draw_mat
	particles.draw_pass_1 = mesh
	particles.process_material = mat
	add_child(particles)
	return particles


func _make_explosion() -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "Explosion"
	particles.position = Vector3(0.0, 0.9, 0.0)
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 48
	particles.lifetime = 1.1
	particles.explosiveness = 0.95
	particles.local_coords = false

	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 180.0
	mat.gravity = Vector3(0.0, -6.0, 0.0)
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 13.0
	mat.scale_min = 0.6
	mat.scale_max = 2.0
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.5
	particles.process_material = mat

	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(1.3, 1.3)
	var draw_mat: StandardMaterial3D = StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_mat.albedo_color = Color(1.0, 0.72, 0.22, 0.95)
	draw_mat.emission_enabled = true
	draw_mat.emission = Color(1.0, 0.5, 0.1)
	draw_mat.emission_energy_multiplier = 6.0
	mesh.material = draw_mat
	particles.draw_pass_1 = mesh

	add_child(particles)
	return particles
