extends VehicleBody3D

## Heavy city bus. Builds a DETAILED CSG bus at runtime, or loads
## res://assets/models/bus.glb when the CI download succeeded.
##
## CODING RULES followed here:
##  - no inline-if inside a "%" format tuple (that breaks the parser)
##  - string concatenation / str() instead of "%" tuples
##  - tabs for indentation
##  - every load() guarded by ResourceLoader.exists()

signal door_state_changed(is_open: bool)
signal headlights_changed(is_on: bool)
signal horn_pressed()

const BUS_MODEL_PATH: String = "res://assets/models/bus.glb"

const MAX_SPEED_KMH: float = 80.0
const MAX_STEER_ANGLE: float = 0.42
const STEER_SPEED: float = 2.6
const STEER_RETURN_SPEED: float = 3.4
const ENGINE_POWER: float = 3400.0
const BRAKE_POWER: float = 90.0
const HANDBRAKE_POWER: float = 220.0
const IDLE_DRAG: float = 6.0

const FUEL_IDLE_RATE: float = 0.055
const FUEL_DRIVE_RATE: float = 0.85

# --- runtime input (set by the HUD or keyboard) ---
var steer_input: float = 0.0
var throttle_input: float = 0.0
var brake_input: float = 0.0
var handbrake: bool = false

var speed_kmh: float = 0.0
var doors_open: bool = false
var headlights_on: bool = false
var engine_running: bool = true

var _steer_current: float = 0.0
var _door_slide: float = 0.0
var _wiper_time: float = 0.0
var _wipers_on: bool = false
var _using_glb: bool = false

var _wheels: Array[VehicleWheel3D] = []
var _wheel_visuals: Array[Node3D] = []
var _headlight_meshes: Array[MeshInstance3D] = []
var _headlight_lights: Array[OmniLight3D] = []
var _spotlights: Array[SpotLight3D] = []
var _taillight_meshes: Array[MeshInstance3D] = []
var _door_node: Node3D = null
var _wiper_nodes: Array[Node3D] = []
var _sign_material: StandardMaterial3D = null
var _interior_light: OmniLight3D = null

@onready var _horn_player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()


func _ready() -> void:
	mass = 10000.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.6, 0.0)
	max_contacts_reported = 4
	contact_monitor = true
	can_sleep = false
	add_to_group("bus")

	_build_collision()
	_build_wheels()
	_build_body()
	_build_camera_mounts()

	add_child(_horn_player)
	_horn_player.stream = _make_horn_stream()
	_horn_player.unit_size = 24.0
	_horn_player.max_db = 3.0

	if GameState != null:
		GameState.night_factor_changed.connect(_on_night_factor_changed)


func _physics_process(delta: float) -> void:
	var vel: Vector3 = linear_velocity
	speed_kmh = vel.length() * 3.6

	_update_steering(delta)
	_update_drive(delta)
	_update_fuel(delta)
	_update_door(delta)
	_update_wipers(delta)


func _update_steering(delta: float) -> void:
	var target: float = clampf(steer_input, -1.0, 1.0)

	# Steering authority shrinks with speed so the bus feels heavy.
	var speed_factor: float = clampf(1.0 - speed_kmh / 140.0, 0.35, 1.0)
	target *= speed_factor

	var rate: float = STEER_SPEED
	if absf(target) < 0.05:
		rate = STEER_RETURN_SPEED
	_steer_current = move_toward(_steer_current, target, rate * delta)
	steering = _steer_current * MAX_STEER_ANGLE


func _update_drive(_delta: float) -> void:
	var throttle: float = clampf(throttle_input, 0.0, 1.0)
	var braking: float = clampf(brake_input, 0.0, 1.0)

	var has_fuel: bool = true
	if GameState != null:
		has_fuel = GameState.has_fuel()
	if not has_fuel:
		throttle = 0.0
		engine_running = false
	else:
		engine_running = true

	var forward: Vector3 = -global_transform.basis.z
	var forward_speed: float = linear_velocity.dot(forward) * 3.6

	# Speed cap
	if forward_speed >= MAX_SPEED_KMH:
		throttle = 0.0

	# Reverse when braking while nearly stopped.
	var drive: float = throttle
	if braking > 0.01 and forward_speed < 1.5:
		drive = -braking * 0.45

	engine_force = drive * ENGINE_POWER

	var brake_amount: float = 0.0
	if braking > 0.01 and forward_speed > 1.5:
		brake_amount = braking * BRAKE_POWER
	if throttle < 0.01 and braking < 0.01:
		brake_amount = IDLE_DRAG
	if handbrake:
		brake_amount = HANDBRAKE_POWER
	if doors_open and speed_kmh > 1.0:
		brake_amount = maxf(brake_amount, 25.0)
	brake = brake_amount

	_spin_wheel_visuals()


func _spin_wheel_visuals() -> void:
	var count: int = mini(_wheels.size(), _wheel_visuals.size())
	var i: int = 0
	while i < count:
		var wheel: VehicleWheel3D = _wheels[i]
		var visual: Node3D = _wheel_visuals[i]
		if is_instance_valid(wheel) and is_instance_valid(visual):
			# VehicleWheel3D already rotates itself; the visual is parented to
			# it so it inherits both spin and steering automatically.
			visual.visible = true
		i += 1


func _update_fuel(delta: float) -> void:
	if GameState == null:
		return
	var rate: float = FUEL_IDLE_RATE
	var throttle: float = clampf(throttle_input, 0.0, 1.0)
	rate += FUEL_DRIVE_RATE * throttle * clampf(speed_kmh / MAX_SPEED_KMH, 0.05, 1.0)
	GameState.consume_fuel(rate * delta)


func _update_door(delta: float) -> void:
	var target: float = 0.0
	if doors_open:
		target = 1.0
	_door_slide = move_toward(_door_slide, target, delta * 1.8)
	if _door_node != null and is_instance_valid(_door_node):
		var base_x: float = 1.02
		_door_node.position = Vector3(base_x, _door_node.position.y, 1.55 - _door_slide * 1.05)
		_door_node.scale = Vector3(1.0, 1.0, maxf(0.06, 1.0 - _door_slide * 0.92))


func _update_wipers(delta: float) -> void:
	if _wiper_nodes.is_empty():
		return
	if not _wipers_on:
		return
	_wiper_time += delta * 2.4
	var swing: float = sin(_wiper_time) * 0.5
	var i: int = 0
	while i < _wiper_nodes.size():
		var node: Node3D = _wiper_nodes[i]
		if is_instance_valid(node):
			var phase: float = swing
			if i == 1:
				phase = sin(_wiper_time + 0.35) * 0.5
			node.rotation.z = phase
		i += 1


# ---------------------------------------------------------------------------
# Public API used by the HUD / passenger system
# ---------------------------------------------------------------------------

func set_doors_open(value: bool) -> void:
	if doors_open == value:
		return
	doors_open = value
	emit_signal("door_state_changed", doors_open)


func toggle_doors() -> void:
	set_doors_open(not doors_open)


func toggle_headlights() -> void:
	set_headlights(not headlights_on)


func set_headlights(value: bool) -> void:
	headlights_on = value
	var energy: float = 0.0
	if headlights_on:
		energy = 6.0
	var i: int = 0
	while i < _headlight_meshes.size():
		var mesh: MeshInstance3D = _headlight_meshes[i]
		if is_instance_valid(mesh):
			var mat: StandardMaterial3D = mesh.get_surface_override_material(0) as StandardMaterial3D
			if mat != null:
				mat.emission_energy_multiplier = energy
		i += 1
	i = 0
	while i < _headlight_lights.size():
		var light: OmniLight3D = _headlight_lights[i]
		if is_instance_valid(light):
			light.visible = headlights_on
		i += 1
	i = 0
	while i < _spotlights.size():
		var spot: SpotLight3D = _spotlights[i]
		if is_instance_valid(spot):
			spot.visible = headlights_on
		i += 1
	_wipers_on = headlights_on
	emit_signal("headlights_changed", headlights_on)


func honk() -> void:
	if _horn_player.stream != null:
		_horn_player.play()
	emit_signal("horn_pressed")


func is_stopped() -> bool:
	return speed_kmh < 3.0


func _on_night_factor_changed(night: float) -> void:
	if _sign_material != null:
		_sign_material.emission_energy_multiplier = 1.6 + night * 2.4
	if _interior_light != null and is_instance_valid(_interior_light):
		_interior_light.light_energy = 0.25 + night * 1.35


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _build_collision() -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2.55, 2.5, 10.5)
	shape.shape = box
	shape.position = Vector3(0.0, 0.35, 0.0)
	shape.name = "BodyCollision"
	add_child(shape)


func _build_wheels() -> void:
	var positions: Array[Vector3] = [
		Vector3(-1.15, -0.55, -3.45),
		Vector3(1.15, -0.55, -3.45),
		Vector3(-1.15, -0.55, 3.35),
		Vector3(1.15, -0.55, 3.35),
	]
	var names: Array[String] = ["FrontLeft", "FrontRight", "RearLeft", "RearRight"]

	var i: int = 0
	while i < positions.size():
		var wheel: VehicleWheel3D = VehicleWheel3D.new()
		wheel.name = "Wheel" + names[i]
		wheel.position = positions[i]

		var is_front: bool = i < 2
		wheel.use_as_steering = is_front
		wheel.use_as_traction = not is_front

		wheel.wheel_radius = 0.52
		wheel.wheel_rest_length = 0.32
		wheel.wheel_friction_slip = 3.2
		wheel.suspension_stiffness = 25.0
		wheel.suspension_travel = 0.35
		wheel.suspension_max_force = 90000.0
		wheel.damping_compression = 3.0
		wheel.damping_relaxation = 4.0
		if not is_front:
			wheel.wheel_friction_slip = 3.6

		add_child(wheel)
		_wheels.append(wheel)

		var visual: Node3D = _make_wheel_visual(i)
		wheel.add_child(visual)
		_wheel_visuals.append(visual)
		i += 1


func _make_wheel_visual(index: int) -> Node3D:
	var root: Node3D = Node3D.new()
	var side_label: String = "L"
	if index == 1 or index == 3:
		side_label = "R"
	root.name = "WheelVisual_" + side_label + str(index)

	# Tire
	var tire: MeshInstance3D = MeshInstance3D.new()
	tire.name = "Tire"
	var tire_mesh: CylinderMesh = CylinderMesh.new()
	tire_mesh.top_radius = 0.52
	tire_mesh.bottom_radius = 0.52
	tire_mesh.height = 0.34
	tire_mesh.radial_segments = 24
	tire.mesh = tire_mesh
	tire.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	var tire_mat: StandardMaterial3D = StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.055, 0.055, 0.06)
	tire_mat.roughness = 0.95
	tire_mat.metallic = 0.0
	tire.set_surface_override_material(0, tire_mat)
	root.add_child(tire)

	# Metallic rim
	var rim: MeshInstance3D = MeshInstance3D.new()
	rim.name = "Rim"
	var rim_mesh: CylinderMesh = CylinderMesh.new()
	rim_mesh.top_radius = 0.31
	rim_mesh.bottom_radius = 0.31
	rim_mesh.height = 0.36
	rim_mesh.radial_segments = 20
	rim.mesh = rim_mesh
	rim.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	var rim_mat: StandardMaterial3D = StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.76, 0.78, 0.82)
	rim_mat.metallic = 0.95
	rim_mat.roughness = 0.22
	rim.set_surface_override_material(0, rim_mat)
	root.add_child(rim)

	# Hub bolts ring
	var bolts: MeshInstance3D = MeshInstance3D.new()
	bolts.name = "Hub"
	var bolt_mesh: CylinderMesh = CylinderMesh.new()
	bolt_mesh.top_radius = 0.12
	bolt_mesh.bottom_radius = 0.12
	bolt_mesh.height = 0.4
	bolt_mesh.radial_segments = 10
	bolts.mesh = bolt_mesh
	bolts.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	var bolt_mat: StandardMaterial3D = StandardMaterial3D.new()
	bolt_mat.albedo_color = Color(0.42, 0.44, 0.48)
	bolt_mat.metallic = 0.9
	bolt_mat.roughness = 0.35
	bolts.set_surface_override_material(0, bolt_mat)
	root.add_child(bolts)

	return root


func _build_body() -> void:
	if _try_load_glb():
		_using_glb = true
		# Still add lights + door so gameplay features work with the GLB.
		_build_lights_only()
		return
	_build_csg_bus()


func _try_load_glb() -> bool:
	if not ResourceLoader.exists(BUS_MODEL_PATH):
		return false
	if not FileAccess.file_exists(BUS_MODEL_PATH):
		return false
	var packed: Resource = load(BUS_MODEL_PATH)
	if packed == null:
		return false
	if not (packed is PackedScene):
		return false
	var scene: PackedScene = packed as PackedScene
	var instance: Node = scene.instantiate()
	if instance == null:
		return false
	var holder: Node3D = Node3D.new()
	holder.name = "BusModel"
	holder.position = Vector3(0.0, -1.0, 0.0)
	holder.scale = Vector3(1.6, 1.6, 1.6)
	add_child(holder)
	holder.add_child(instance)
	return true


func _make_body_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.42, 0.78)
	mat.metallic = 0.55
	mat.metallic_specular = 0.6
	mat.roughness = 0.28
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.7
	mat.clearcoat_roughness = 0.15
	return mat


func _make_glass_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.20, 0.26, 0.42)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.85
	mat.roughness = 0.06
	mat.refraction_enabled = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _make_dark_material(rough: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.085, 0.095)
	mat.metallic = 0.3
	mat.roughness = rough
	return mat


func _build_csg_bus() -> void:
	var root: CSGCombiner3D = CSGCombiner3D.new()
	root.name = "BusCSG"
	root.use_collision = false
	add_child(root)

	var body_mat: StandardMaterial3D = _make_body_material()
	var glass_mat: StandardMaterial3D = _make_glass_material()
	var trim_mat: StandardMaterial3D = _make_dark_material(0.45)

	# --- main hull (rounded via corner radius) ---
	var hull: CSGBox3D = CSGBox3D.new()
	hull.name = "Hull"
	hull.size = Vector3(2.5, 2.35, 10.4)
	hull.position = Vector3(0.0, 0.32, 0.0)
	hull.material = body_mat
	root.add_child(hull)

	# rounded roof cap
	var roof: CSGCylinder3D = CSGCylinder3D.new()
	roof.name = "RoofCap"
	roof.radius = 1.25
	roof.height = 10.4
	roof.sides = 18
	roof.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	roof.position = Vector3(0.0, 1.12, 0.0)
	roof.material = body_mat
	root.add_child(roof)

	# lower skirt (slightly darker)
	var skirt: CSGBox3D = CSGBox3D.new()
	skirt.name = "Skirt"
	skirt.size = Vector3(2.56, 0.55, 10.2)
	skirt.position = Vector3(0.0, -0.72, 0.0)
	var skirt_mat: StandardMaterial3D = StandardMaterial3D.new()
	skirt_mat.albedo_color = Color(0.10, 0.11, 0.13)
	skirt_mat.metallic = 0.4
	skirt_mat.roughness = 0.5
	skirt.material = skirt_mat
	root.add_child(skirt)

	# white livery stripe
	var stripe: CSGBox3D = CSGBox3D.new()
	stripe.name = "Stripe"
	stripe.size = Vector3(2.54, 0.28, 10.3)
	stripe.position = Vector3(0.0, -0.28, 0.0)
	var stripe_mat: StandardMaterial3D = StandardMaterial3D.new()
	stripe_mat.albedo_color = Color(0.93, 0.94, 0.96)
	stripe_mat.metallic = 0.3
	stripe_mat.roughness = 0.3
	stripe.material = stripe_mat
	root.add_child(stripe)

	_build_windshield(root, glass_mat, trim_mat)
	_build_side_windows(root, glass_mat, trim_mat)
	_build_bumpers(root)
	_build_lights_csg(root)
	_build_mirrors(root, trim_mat)
	_build_destination_sign(root)
	_build_roof_ac(root)
	_build_door(root, glass_mat, trim_mat)
	_build_wipers(root)
	_build_interior(root)


func _build_windshield(root: Node3D, glass_mat: StandardMaterial3D, trim_mat: StandardMaterial3D) -> void:
	# slanted front windshield
	var front: CSGBox3D = CSGBox3D.new()
	front.name = "Windshield"
	front.size = Vector3(2.35, 1.5, 0.1)
	front.position = Vector3(0.0, 0.72, -5.12)
	front.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	front.material = glass_mat
	root.add_child(front)

	var front_frame: CSGBox3D = CSGBox3D.new()
	front_frame.name = "WindshieldFrame"
	front_frame.size = Vector3(2.46, 1.62, 0.06)
	front_frame.position = Vector3(0.0, 0.72, -5.16)
	front_frame.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	front_frame.material = trim_mat
	root.add_child(front_frame)

	# rear window
	var rear: CSGBox3D = CSGBox3D.new()
	rear.name = "RearWindow"
	rear.size = Vector3(2.3, 1.15, 0.1)
	rear.position = Vector3(0.0, 0.72, 5.14)
	rear.material = glass_mat
	root.add_child(rear)


func _build_side_windows(root: Node3D, glass_mat: StandardMaterial3D, trim_mat: StandardMaterial3D) -> void:
	# 6 transparent side windows per side, each with a frame
	var z_positions: Array[float] = [-3.5, -2.05, -0.6, 0.85, 2.3, 3.75]
	var sides: Array[float] = [-1.0, 1.0]

	var s: int = 0
	while s < sides.size():
		var side: float = sides[s]
		var side_label: String = "L"
		if side > 0.0:
			side_label = "R"
		var i: int = 0
		while i < z_positions.size():
			var z: float = z_positions[i]

			var frame: CSGBox3D = CSGBox3D.new()
			frame.name = "WinFrame_" + side_label + str(i)
			frame.size = Vector3(0.08, 1.16, 1.28)
			frame.position = Vector3(side * 1.255, 0.68, z)
			frame.material = trim_mat
			root.add_child(frame)

			var glass: CSGBox3D = CSGBox3D.new()
			glass.name = "Window_" + side_label + str(i)
			glass.size = Vector3(0.1, 1.0, 1.14)
			glass.position = Vector3(side * 1.262, 0.68, z)
			glass.material = glass_mat
			root.add_child(glass)

			i += 1
		s += 1


func _build_bumpers(root: Node3D) -> void:
	var bumper_mat: StandardMaterial3D = StandardMaterial3D.new()
	bumper_mat.albedo_color = Color(0.13, 0.14, 0.16)
	bumper_mat.metallic = 0.65
	bumper_mat.roughness = 0.38

	var front: CSGBox3D = CSGBox3D.new()
	front.name = "FrontBumper"
	front.size = Vector3(2.62, 0.46, 0.42)
	front.position = Vector3(0.0, -0.62, -5.28)
	front.material = bumper_mat
	root.add_child(front)

	var rear: CSGBox3D = CSGBox3D.new()
	rear.name = "RearBumper"
	rear.size = Vector3(2.62, 0.46, 0.42)
	rear.position = Vector3(0.0, -0.62, 5.28)
	rear.material = bumper_mat
	root.add_child(rear)

	# front grille
	var grille: CSGBox3D = CSGBox3D.new()
	grille.name = "Grille"
	grille.size = Vector3(1.5, 0.3, 0.12)
	grille.position = Vector3(0.0, -0.2, -5.24)
	var grille_mat: StandardMaterial3D = StandardMaterial3D.new()
	grille_mat.albedo_color = Color(0.06, 0.06, 0.07)
	grille_mat.metallic = 0.8
	grille_mat.roughness = 0.3
	grille.material = grille_mat
	root.add_child(grille)


func _build_lights_csg(root: Node3D) -> void:
	var xs: Array[float] = [-0.86, 0.86]

	var i: int = 0
	while i < xs.size():
		var x: float = xs[i]
		var label: String = "L"
		if x > 0.0:
			label = "R"

		var lamp: CSGCylinder3D = CSGCylinder3D.new()
		lamp.name = "Headlight_" + label
		lamp.radius = 0.2
		lamp.height = 0.16
		lamp.sides = 16
		lamp.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		lamp.position = Vector3(x, -0.18, -5.26)
		var lamp_mat: StandardMaterial3D = StandardMaterial3D.new()
		lamp_mat.albedo_color = Color(0.95, 0.94, 0.85)
		lamp_mat.emission_enabled = true
		lamp_mat.emission = Color(1.0, 0.96, 0.86)
		lamp_mat.emission_energy_multiplier = 0.0
		lamp_mat.metallic = 0.4
		lamp_mat.roughness = 0.15
		lamp.material = lamp_mat
		root.add_child(lamp)

		# keep a MeshInstance3D twin for material toggling
		var proxy: MeshInstance3D = MeshInstance3D.new()
		proxy.name = "HeadlightProxy_" + label
		var proxy_mesh: CylinderMesh = CylinderMesh.new()
		proxy_mesh.top_radius = 0.205
		proxy_mesh.bottom_radius = 0.205
		proxy_mesh.height = 0.06
		proxy_mesh.radial_segments = 16
		proxy.mesh = proxy_mesh
		proxy.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		proxy.position = Vector3(x, -0.18, -5.34)
		proxy.set_surface_override_material(0, lamp_mat)
		add_child(proxy)
		_headlight_meshes.append(proxy)

		var omni: OmniLight3D = OmniLight3D.new()
		omni.name = "HeadlightGlow_" + label
		omni.position = Vector3(x, -0.18, -5.5)
		omni.light_color = Color(1.0, 0.95, 0.85)
		omni.light_energy = 2.2
		omni.omni_range = 6.0
		omni.visible = false
		add_child(omni)
		_headlight_lights.append(omni)

		var spot: SpotLight3D = SpotLight3D.new()
		spot.name = "HeadlightBeam_" + label
		spot.position = Vector3(x, -0.15, -5.4)
		spot.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
		spot.light_color = Color(1.0, 0.96, 0.88)
		spot.light_energy = 5.0
		spot.spot_range = 42.0
		spot.spot_angle = 34.0
		spot.spot_angle_attenuation = 1.2
		spot.shadow_enabled = false
		spot.visible = false
		add_child(spot)
		_spotlights.append(spot)

		# tail light
		var tail: CSGBox3D = CSGBox3D.new()
		tail.name = "TailLight_" + label
		tail.size = Vector3(0.34, 0.22, 0.1)
		tail.position = Vector3(x, -0.12, 5.24)
		var tail_mat: StandardMaterial3D = StandardMaterial3D.new()
		tail_mat.albedo_color = Color(0.42, 0.03, 0.03)
		tail_mat.emission_enabled = true
		tail_mat.emission = Color(1.0, 0.12, 0.06)
		tail_mat.emission_energy_multiplier = 2.4
		tail_mat.roughness = 0.25
		tail.material = tail_mat
		root.add_child(tail)

		var tail_proxy: MeshInstance3D = MeshInstance3D.new()
		tail_proxy.name = "TailProxy_" + label
		var tail_mesh: BoxMesh = BoxMesh.new()
		tail_mesh.size = Vector3(0.345, 0.225, 0.02)
		tail_proxy.mesh = tail_mesh
		tail_proxy.position = Vector3(x, -0.12, 5.31)
		tail_proxy.set_surface_override_material(0, tail_mat)
		add_child(tail_proxy)
		_taillight_meshes.append(tail_proxy)

		i += 1


func _build_lights_only() -> void:
	# Used when the GLB model loaded: still provide functional lights.
	var xs: Array[float] = [-0.86, 0.86]
	var i: int = 0
	while i < xs.size():
		var x: float = xs[i]
		var label: String = "L"
		if x > 0.0:
			label = "R"
		var spot: SpotLight3D = SpotLight3D.new()
		spot.name = "HeadlightBeam_" + label
		spot.position = Vector3(x, -0.1, -5.2)
		spot.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
		spot.light_color = Color(1.0, 0.96, 0.88)
		spot.light_energy = 5.0
		spot.spot_range = 42.0
		spot.spot_angle = 34.0
		spot.visible = false
		add_child(spot)
		_spotlights.append(spot)
		i += 1
	_build_camera_only_door()


func _build_camera_only_door() -> void:
	var door: Node3D = Node3D.new()
	door.name = "DoorPivot"
	door.position = Vector3(1.02, -0.1, 1.55)
	add_child(door)
	_door_node = door


func _build_mirrors(root: Node3D, trim_mat: StandardMaterial3D) -> void:
	var sides: Array[float] = [-1.0, 1.0]
	var i: int = 0
	while i < sides.size():
		var side: float = sides[i]
		var label: String = "L"
		if side > 0.0:
			label = "R"

		var arm: CSGCylinder3D = CSGCylinder3D.new()
		arm.name = "MirrorArm_" + label
		arm.radius = 0.035
		arm.height = 0.5
		arm.sides = 8
		arm.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		arm.position = Vector3(side * 1.5, 0.95, -4.6)
		arm.material = trim_mat
		root.add_child(arm)

		var glass: CSGBox3D = CSGBox3D.new()
		glass.name = "Mirror_" + label
		glass.size = Vector3(0.08, 0.5, 0.3)
		glass.position = Vector3(side * 1.78, 0.78, -4.6)
		var mirror_mat: StandardMaterial3D = StandardMaterial3D.new()
		mirror_mat.albedo_color = Color(0.72, 0.76, 0.82)
		mirror_mat.metallic = 1.0
		mirror_mat.roughness = 0.05
		glass.material = mirror_mat
		root.add_child(glass)
		i += 1


func _build_destination_sign(root: Node3D) -> void:
	var sign: CSGBox3D = CSGBox3D.new()
	sign.name = "DestinationSign"
	sign.size = Vector3(1.7, 0.34, 0.08)
	sign.position = Vector3(0.0, 1.42, -5.14)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.05, 0.06)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.62, 0.12)
	mat.emission_energy_multiplier = 1.8
	mat.roughness = 0.4
	sign.material = mat
	_sign_material = mat
	root.add_child(sign)

	# route number panel on the side
	var side_sign: CSGBox3D = CSGBox3D.new()
	side_sign.name = "RouteSign"
	side_sign.size = Vector3(0.06, 0.26, 0.7)
	side_sign.position = Vector3(1.27, 1.3, -3.0)
	side_sign.material = mat
	root.add_child(side_sign)


func _build_roof_ac(root: Node3D) -> void:
	var ac_mat: StandardMaterial3D = StandardMaterial3D.new()
	ac_mat.albedo_color = Color(0.80, 0.81, 0.83)
	ac_mat.metallic = 0.6
	ac_mat.roughness = 0.42

	var unit: CSGBox3D = CSGBox3D.new()
	unit.name = "RoofAC"
	unit.size = Vector3(1.7, 0.32, 2.6)
	unit.position = Vector3(0.0, 1.52, -1.2)
	unit.material = ac_mat
	root.add_child(unit)

	var vent: CSGBox3D = CSGBox3D.new()
	vent.name = "RoofVent"
	vent.size = Vector3(0.9, 0.18, 0.9)
	vent.position = Vector3(0.0, 1.55, 2.4)
	vent.material = ac_mat
	root.add_child(vent)

	var hatch: CSGBox3D = CSGBox3D.new()
	hatch.name = "RoofHatch"
	hatch.size = Vector3(0.7, 0.12, 0.7)
	hatch.position = Vector3(0.0, 1.55, 0.9)
	var hatch_mat: StandardMaterial3D = StandardMaterial3D.new()
	hatch_mat.albedo_color = Color(0.35, 0.37, 0.40)
	hatch_mat.roughness = 0.6
	hatch.material = hatch_mat
	root.add_child(hatch)


func _build_door(root: Node3D, glass_mat: StandardMaterial3D, trim_mat: StandardMaterial3D) -> void:
	# Door frame cut into the right side
	var frame: CSGBox3D = CSGBox3D.new()
	frame.name = "DoorFrame"
	frame.size = Vector3(0.1, 1.95, 1.25)
	frame.position = Vector3(1.26, -0.05, 1.55)
	frame.material = trim_mat
	root.add_child(frame)

	# Sliding leaf (animated in _update_door)
	var door: CSGBox3D = CSGBox3D.new()
	door.name = "DoorLeaf"
	door.size = Vector3(0.09, 1.85, 1.1)
	door.position = Vector3(1.02, -0.05, 1.55)
	door.material = glass_mat
	add_child(door)
	_door_node = door

	var step: CSGBox3D = CSGBox3D.new()
	step.name = "DoorStep"
	step.size = Vector3(0.3, 0.1, 1.1)
	step.position = Vector3(1.2, -1.0, 1.55)
	var step_mat: StandardMaterial3D = StandardMaterial3D.new()
	step_mat.albedo_color = Color(0.2, 0.21, 0.23)
	step_mat.roughness = 0.85
	step.material = step_mat
	root.add_child(step)


func _build_wipers(root: Node3D) -> void:
	var wiper_mat: StandardMaterial3D = StandardMaterial3D.new()
	wiper_mat.albedo_color = Color(0.05, 0.05, 0.06)
	wiper_mat.metallic = 0.5
	wiper_mat.roughness = 0.5

	var xs: Array[float] = [-0.6, 0.6]
	var i: int = 0
	while i < xs.size():
		var pivot: Node3D = Node3D.new()
		var label: String = "L"
		if xs[i] > 0.0:
			label = "R"
		pivot.name = "WiperPivot_" + label
		pivot.position = Vector3(xs[i], 0.12, -5.2)
		add_child(pivot)

		var blade: MeshInstance3D = MeshInstance3D.new()
		blade.name = "WiperBlade_" + label
		var blade_mesh: BoxMesh = BoxMesh.new()
		blade_mesh.size = Vector3(0.05, 0.9, 0.04)
		blade.mesh = blade_mesh
		blade.position = Vector3(0.0, 0.42, 0.0)
		blade.set_surface_override_material(0, wiper_mat)
		pivot.add_child(blade)

		_wiper_nodes.append(pivot)
		i += 1


func _build_interior(root: Node3D) -> void:
	var seat_mat: StandardMaterial3D = StandardMaterial3D.new()
	seat_mat.albedo_color = Color(0.16, 0.24, 0.42)
	seat_mat.roughness = 0.9

	var frame_mat: StandardMaterial3D = StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.35, 0.36, 0.38)
	frame_mat.metallic = 0.7
	frame_mat.roughness = 0.35

	# floor
	var floor_box: CSGBox3D = CSGBox3D.new()
	floor_box.name = "InteriorFloor"
	floor_box.size = Vector3(2.3, 0.08, 9.6)
	floor_box.position = Vector3(0.0, -0.92, 0.2)
	var floor_mat: StandardMaterial3D = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.22, 0.23, 0.25)
	floor_mat.roughness = 0.8
	floor_box.material = floor_mat
	root.add_child(floor_box)

	# rows of seats visible through the glass
	var rows: int = 6
	var r: int = 0
	while r < rows:
		var z: float = -2.6 + float(r) * 1.35
		var sides: Array[float] = [-0.72, 0.72]
		var s: int = 0
		while s < sides.size():
			var x: float = sides[s]
			var label: String = "L"
			if x > 0.0:
				label = "R"

			var cushion: CSGBox3D = CSGBox3D.new()
			cushion.name = "Seat_" + label + str(r)
			cushion.size = Vector3(0.78, 0.14, 0.62)
			cushion.position = Vector3(x, -0.5, z)
			cushion.material = seat_mat
			root.add_child(cushion)

			var back: CSGBox3D = CSGBox3D.new()
			back.name = "SeatBack_" + label + str(r)
			back.size = Vector3(0.78, 0.62, 0.13)
			back.position = Vector3(x, -0.18, z + 0.28)
			back.material = seat_mat
			root.add_child(back)
			s += 1
		r += 1

	# grab poles
	var poles: Array[float] = [-1.5, 0.4, 2.4]
	var p: int = 0
	while p < poles.size():
		var pole: CSGCylinder3D = CSGCylinder3D.new()
		pole.name = "Pole" + str(p)
		pole.radius = 0.035
		pole.height = 1.9
		pole.sides = 8
		pole.position = Vector3(0.55, 0.05, poles[p])
		pole.material = frame_mat
		root.add_child(pole)
		p += 1

	# driver area: dashboard + steering wheel
	var dash: CSGBox3D = CSGBox3D.new()
	dash.name = "Dashboard"
	dash.size = Vector3(2.2, 0.35, 0.7)
	dash.position = Vector3(0.0, -0.28, -4.5)
	var dash_mat: StandardMaterial3D = StandardMaterial3D.new()
	dash_mat.albedo_color = Color(0.10, 0.10, 0.12)
	dash_mat.roughness = 0.75
	dash.material = dash_mat
	root.add_child(dash)

	var wheel: CSGTorus3D = CSGTorus3D.new()
	wheel.name = "SteeringWheel"
	wheel.inner_radius = 0.20
	wheel.outer_radius = 0.26
	wheel.sides = 8
	wheel.ring_sides = 16
	wheel.rotation_degrees = Vector3(70.0, 0.0, 0.0)
	wheel.position = Vector3(-0.62, 0.02, -4.35)
	var wheel_mat: StandardMaterial3D = StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.07, 0.07, 0.08)
	wheel_mat.roughness = 0.6
	wheel.material = wheel_mat
	root.add_child(wheel)

	var driver_seat: CSGBox3D = CSGBox3D.new()
	driver_seat.name = "DriverSeat"
	driver_seat.size = Vector3(0.62, 0.16, 0.6)
	driver_seat.position = Vector3(-0.62, -0.5, -3.95)
	driver_seat.material = seat_mat
	root.add_child(driver_seat)

	var driver_back: CSGBox3D = CSGBox3D.new()
	driver_back.name = "DriverSeatBack"
	driver_back.size = Vector3(0.62, 0.7, 0.14)
	driver_back.position = Vector3(-0.62, -0.14, -3.68)
	driver_back.material = seat_mat
	root.add_child(driver_back)

	var cabin_light: OmniLight3D = OmniLight3D.new()
	cabin_light.name = "InteriorLight"
	cabin_light.position = Vector3(0.0, 1.0, 0.0)
	cabin_light.light_color = Color(1.0, 0.94, 0.82)
	cabin_light.light_energy = 0.4
	cabin_light.omni_range = 7.0
	cabin_light.shadow_enabled = false
	add_child(cabin_light)
	_interior_light = cabin_light


func _build_camera_mounts() -> void:
	var chase: Marker3D = Marker3D.new()
	chase.name = "ChaseAnchor"
	chase.position = Vector3(0.0, 3.4, 9.5)
	add_child(chase)

	var interior: Marker3D = Marker3D.new()
	interior.name = "InteriorAnchor"
	interior.position = Vector3(-0.62, 0.62, -4.05)
	add_child(interior)

	var look: Marker3D = Marker3D.new()
	look.name = "LookTarget"
	look.position = Vector3(0.0, 1.1, -2.0)
	add_child(look)


func _make_horn_stream() -> AudioStream:
	# Procedural two-tone horn so no audio asset download is required.
	var sample_rate: int = 22050
	var seconds: float = 0.75
	var frames: int = int(sample_rate * seconds)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)

	var i: int = 0
	while i < frames:
		var t: float = float(i) / float(sample_rate)
		var env: float = 1.0
		if t < 0.02:
			env = t / 0.02
		var tail: float = seconds - t
		if tail < 0.12:
			env = clampf(tail / 0.12, 0.0, 1.0)
		var wave: float = sin(TAU * 262.0 * t) * 0.5 + sin(TAU * 330.0 * t) * 0.35
		wave += sin(TAU * 524.0 * t) * 0.12
		var value: float = clampf(wave * env * 0.55, -1.0, 1.0)
		var sample: int = int(value * 32000.0)
		if sample < 0:
			sample += 65536
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
		i += 1

	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
