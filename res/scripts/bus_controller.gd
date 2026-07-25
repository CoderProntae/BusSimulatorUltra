extends VehicleBody3D

## Heavy intercity coach bus (ETS / Ultimate Bus Simulator style).
##
## ORIENTATION - THIS IS CRITICAL:
## VehicleBody3D's local forward is Vector3.MODEL_FRONT, which is +Z.
## The whole model is therefore built facing +Z:
##   +Z = front (windshield, headlights)      -Z = rear (engine, tail lights)
##   +X = model LEFT  (driver, right-hand traffic)
##   -X = model RIGHT (passenger door, curb side)
## Building the bus facing -Z makes the gas pedal drive it backwards.
##
## CODING RULES followed here:
##  - no inline-if (ternary) anywhere, and never inside a "%" format tuple
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

# Body dimensions (metres)
const BODY_HALF_WIDTH: float = 1.27
const BODY_LENGTH: float = 12.0
const FRONT_Z: float = 5.95
const REAR_Z: float = -5.95
const DOOR_Z: float = 3.55
const DOOR_X: float = -1.27

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
var _headlight_materials: Array[StandardMaterial3D] = []
var _headlight_lights: Array[OmniLight3D] = []
var _spotlights: Array[SpotLight3D] = []
var _brake_materials: Array[StandardMaterial3D] = []
var _door_node: Node3D = null
var _wiper_nodes: Array[Node3D] = []
var _sign_material: StandardMaterial3D = null
var _interior_light: OmniLight3D = null

@onready var _horn_player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()


func _ready() -> void:
	mass = 10000.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.7, 0.0)
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
	speed_kmh = linear_velocity.length() * 3.6

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

	# The wheel is proportional: a small turn of the wheel is a small turn of
	# the bus. Ease the input slightly so the centre is precise while the
	# extremes still reach full lock.
	var eased: float = target * (0.55 + 0.45 * absf(target))

	var rate: float = STEER_SPEED
	if absf(eased) < 0.05:
		rate = STEER_RETURN_SPEED
	_steer_current = move_toward(_steer_current, eased, rate * delta)

	# SIGN: the bus faces +Z, so its right side is -X. Rotating a +Z vector by
	# a POSITIVE angle around +Y swings it toward +X, i.e. to the LEFT.
	# steer_input > 0 means the player steered RIGHT, so the angle is negated.
	steering = -_steer_current * MAX_STEER_ANGLE


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

	# VehicleBody3D forward is +Z (Vector3.MODEL_FRONT).
	var forward: Vector3 = global_transform.basis.z
	var forward_speed: float = linear_velocity.dot(forward) * 3.6

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

	_update_brake_lights(braking)


func _update_brake_lights(braking: float) -> void:
	var energy: float = 1.6
	if braking > 0.01:
		energy = 5.5
	var i: int = 0
	while i < _brake_materials.size():
		var mat: StandardMaterial3D = _brake_materials[i]
		if mat != null:
			mat.emission_energy_multiplier = energy
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
	if _door_node == null or not is_instance_valid(_door_node):
		return
	# Plug door: swings slightly out, then slides backwards (-Z).
	var out: float = sin(_door_slide * PI * 0.5) * 0.16
	_door_node.position = Vector3(
		DOOR_X - out,
		_door_node.position.y,
		DOOR_Z - _door_slide * 1.05
	)


func _update_wipers(delta: float) -> void:
	if _wiper_nodes.is_empty():
		return
	if not _wipers_on:
		return
	_wiper_time += delta * 2.4
	var i: int = 0
	while i < _wiper_nodes.size():
		var node: Node3D = _wiper_nodes[i]
		if is_instance_valid(node):
			var phase: float = sin(_wiper_time) * 0.5
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
	while i < _headlight_materials.size():
		var mat: StandardMaterial3D = _headlight_materials[i]
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
# Small mesh helpers (MeshInstance3D, not CSG: far cheaper on mobile)
# ---------------------------------------------------------------------------

func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


func _glass_mat() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.10, 0.14, 0.62)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.9
	mat.roughness = 0.06
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _emissive_mat(base: Color, glow: Color, energy: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = base
	mat.emission_enabled = true
	mat.emission = glow
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.2
	return mat


func _add_box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3,
		mat: Material, rot_deg: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = pos
	node.rotation_degrees = rot_deg
	if mat != null:
		node.set_surface_override_material(0, mat)
	parent.add_child(node)
	return node


func _add_cylinder(parent: Node3D, node_name: String, radius: float, height: float,
		pos: Vector3, mat: Material, rot_deg: Vector3, sides: int) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	node.mesh = mesh
	node.position = pos
	node.rotation_degrees = rot_deg
	if mat != null:
		node.set_surface_override_material(0, mat)
	parent.add_child(node)
	return node


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _build_collision() -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2.55, 2.9, BODY_LENGTH)
	shape.shape = box
	shape.position = Vector3(0.0, 0.35, 0.0)
	shape.name = "BodyCollision"
	add_child(shape)


func _build_wheels() -> void:
	# Front axle steers (+Z end), rear axle drives.
	var positions: Array[Vector3] = [
		Vector3(-1.12, -0.62, 3.95),
		Vector3(1.12, -0.62, 3.95),
		Vector3(-1.12, -0.62, -3.25),
		Vector3(1.12, -0.62, -3.25),
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
		wheel.wheel_rest_length = 0.3
		wheel.wheel_friction_slip = 3.2
		wheel.suspension_stiffness = 25.0
		wheel.suspension_travel = 0.32
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

	var tire_mat: StandardMaterial3D = _mat(Color(0.045, 0.045, 0.05), 0.0, 0.95)
	var rim_mat: StandardMaterial3D = _mat(Color(0.80, 0.82, 0.86), 0.95, 0.18)
	var hub_mat: StandardMaterial3D = _mat(Color(0.40, 0.42, 0.46), 0.9, 0.3)

	_add_cylinder(root, "Tire", 0.52, 0.36, Vector3.ZERO, tire_mat, Vector3(0, 0, 90), 24)
	_add_cylinder(root, "Rim", 0.33, 0.38, Vector3.ZERO, rim_mat, Vector3(0, 0, 90), 20)
	_add_cylinder(root, "Hub", 0.13, 0.42, Vector3.ZERO, hub_mat, Vector3(0, 0, 90), 10)

	# Rim spokes for a nicer alloy look.
	var s: int = 0
	while s < 5:
		var angle: float = float(s) * 72.0
		_add_box(root, "Spoke" + str(s), Vector3(0.40, 0.10, 0.055),
			Vector3.ZERO, rim_mat, Vector3(angle, 0, 90))
		s += 1

	return root


func _build_body() -> void:
	if _try_load_glb():
		_using_glb = true
		_build_lights_only()
		return
	_build_coach_bus()


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
	holder.position = Vector3(0.0, -1.1, 0.0)
	add_child(holder)
	holder.add_child(instance)
	return true


func _build_coach_bus() -> void:
	var root: Node3D = Node3D.new()
	root.name = "BusBody"
	add_child(root)

	# --- livery colours (ETS-style intercity coach) ---
	var body_mat: StandardMaterial3D = _mat(Color(0.93, 0.94, 0.96), 0.55, 0.22)
	body_mat.clearcoat_enabled = true
	body_mat.clearcoat = 0.85
	body_mat.clearcoat_roughness = 0.08

	var accent_mat: StandardMaterial3D = _mat(Color(0.06, 0.28, 0.62), 0.65, 0.20)
	accent_mat.clearcoat_enabled = true
	accent_mat.clearcoat = 0.8

	var skirt_mat: StandardMaterial3D = _mat(Color(0.09, 0.10, 0.12), 0.45, 0.45)
	var trim_mat: StandardMaterial3D = _mat(Color(0.10, 0.10, 0.12), 0.7, 0.3)
	var chrome_mat: StandardMaterial3D = _mat(Color(0.86, 0.88, 0.92), 1.0, 0.10)
	var glass_mat: StandardMaterial3D = _glass_mat()

	# --- main hull ---
	_add_box(root, "Hull", Vector3(2.50, 2.10, BODY_LENGTH - 0.4),
		Vector3(0.0, 0.25, 0.0), body_mat, Vector3.ZERO)

	# rounded roof crown running the length of the bus
	_add_cylinder(root, "RoofCrown", 1.25, BODY_LENGTH - 0.45,
		Vector3(0.0, 0.30, 0.0), body_mat, Vector3(90, 0, 0), 20)

	# lower skirt + luggage bays
	_add_box(root, "Skirt", Vector3(2.54, 0.62, BODY_LENGTH - 0.6),
		Vector3(0.0, -0.86, 0.0), skirt_mat, Vector3.ZERO)

	# blue accent band along the flanks
	_add_box(root, "AccentBand", Vector3(2.545, 0.30, BODY_LENGTH - 0.7),
		Vector3(0.0, -0.42, 0.0), accent_mat, Vector3.ZERO)
	_add_box(root, "ChromeStrip", Vector3(2.552, 0.06, BODY_LENGTH - 0.7),
		Vector3(0.0, -0.24, 0.0), chrome_mat, Vector3.ZERO)

	_build_glazing(root, glass_mat, trim_mat)
	_build_front(root, body_mat, trim_mat, chrome_mat, glass_mat)
	_build_rear(root, body_mat, trim_mat, accent_mat, glass_mat)
	_build_luggage_bays(root, skirt_mat, chrome_mat)
	_build_wheel_arches(root, skirt_mat)
	_build_mirrors(root, trim_mat)
	_build_roof(root, body_mat)
	_build_door(root, glass_mat, trim_mat)
	_build_interior(root)


func _build_glazing(root: Node3D, glass_mat: StandardMaterial3D,
		trim_mat: StandardMaterial3D) -> void:
	# Continuous coach glazing band on both flanks, with pillars.
	var sides: Array[float] = [-1.0, 1.0]
	var s: int = 0
	while s < sides.size():
		var side: float = sides[s]
		var label: String = "R"
		if side > 0.0:
			label = "L"

		# dark band behind the glass so the interior reads as tinted
		_add_box(root, "GlassBand_" + label, Vector3(0.05, 1.05, 8.6),
			Vector3(side * 1.252, 0.80, -0.7), trim_mat, Vector3.ZERO)
		_add_box(root, "Glass_" + label, Vector3(0.05, 0.95, 8.5),
			Vector3(side * 1.262, 0.80, -0.7), glass_mat, Vector3.ZERO)

		# window pillars
		var pillar_zs: Array[float] = [-4.9, -3.4, -1.9, -0.4, 1.1, 2.6, 3.5]
		var p: int = 0
		while p < pillar_zs.size():
			_add_box(root, "Pillar_" + label + str(p), Vector3(0.07, 1.06, 0.14),
				Vector3(side * 1.266, 0.80, pillar_zs[p]), trim_mat, Vector3.ZERO)
			p += 1
		s += 1


func _build_front(root: Node3D, body_mat: StandardMaterial3D, trim_mat: StandardMaterial3D,
		chrome_mat: StandardMaterial3D, glass_mat: StandardMaterial3D) -> void:
	# Large raked windshield. Negative X rotation leans the top backwards (-Z).
	_add_box(root, "WindshieldFrame", Vector3(2.44, 1.55, 0.10),
		Vector3(0.0, 0.72, FRONT_Z - 0.10), trim_mat, Vector3(-12, 0, 0))
	_add_box(root, "Windshield", Vector3(2.30, 1.42, 0.06),
		Vector3(0.0, 0.72, FRONT_Z - 0.04), glass_mat, Vector3(-12, 0, 0))

	# destination sign above the windshield
	var sign_mat: StandardMaterial3D = _emissive_mat(
		Color(0.03, 0.04, 0.05), Color(1.0, 0.66, 0.16), 1.8)
	_sign_material = sign_mat
	_add_box(root, "DestinationSign", Vector3(1.95, 0.30, 0.10),
		Vector3(0.0, 1.44, FRONT_Z - 0.16), sign_mat, Vector3.ZERO)

	var label: Label3D = Label3D.new()
	label.name = "RouteText"
	label.text = "12  CITY CENTRE"
	label.font_size = 64
	label.pixel_size = 0.0038
	label.position = Vector3(0.0, 1.44, FRONT_Z - 0.10)
	label.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	label.modulate = Color(1.0, 0.78, 0.30)
	label.outline_size = 0
	label.double_sided = false
	label.no_depth_test = false
	root.add_child(label)

	# bumper + grille
	_add_box(root, "FrontBumper", Vector3(2.56, 0.52, 0.44),
		Vector3(0.0, -0.72, FRONT_Z - 0.10), trim_mat, Vector3.ZERO)
	_add_box(root, "Grille", Vector3(1.50, 0.26, 0.12),
		Vector3(0.0, -0.28, FRONT_Z - 0.02), trim_mat, Vector3.ZERO)
	_add_box(root, "GrilleChrome", Vector3(1.54, 0.05, 0.14),
		Vector3(0.0, -0.14, FRONT_Z - 0.02), chrome_mat, Vector3.ZERO)

	# headlight clusters
	var xs: Array[float] = [-0.88, 0.88]
	var i: int = 0
	while i < xs.size():
		var x: float = xs[i]
		var side_label: String = "R"
		if x > 0.0:
			side_label = "L"

		var lamp_mat: StandardMaterial3D = _emissive_mat(
			Color(0.92, 0.92, 0.86), Color(1.0, 0.96, 0.86), 0.0)
		_headlight_materials.append(lamp_mat)

		_add_box(root, "HeadlightHousing_" + side_label, Vector3(0.52, 0.26, 0.10),
			Vector3(x, -0.24, FRONT_Z - 0.08), trim_mat, Vector3.ZERO)
		_add_box(root, "Headlight_" + side_label, Vector3(0.46, 0.20, 0.08),
			Vector3(x, -0.24, FRONT_Z - 0.02), lamp_mat, Vector3.ZERO)

		# indicator
		var turn_mat: StandardMaterial3D = _emissive_mat(
			Color(0.5, 0.25, 0.03), Color(1.0, 0.45, 0.05), 1.2)
		_add_box(root, "Indicator_" + side_label, Vector3(0.20, 0.14, 0.08),
			Vector3(x + (0.34 * signf(x)), -0.24, FRONT_Z - 0.02), turn_mat, Vector3.ZERO)

		var omni: OmniLight3D = OmniLight3D.new()
		omni.name = "HeadlightGlow_" + side_label
		omni.position = Vector3(x, -0.24, FRONT_Z + 0.25)
		omni.light_color = Color(1.0, 0.95, 0.85)
		omni.light_energy = 2.2
		omni.omni_range = 6.0
		omni.visible = false
		add_child(omni)
		_headlight_lights.append(omni)

		# SpotLight3D points down its local -Z, so face it forward with yaw 180.
		var spot: SpotLight3D = SpotLight3D.new()
		spot.name = "HeadlightBeam_" + side_label
		spot.position = Vector3(x, -0.18, FRONT_Z + 0.1)
		spot.rotation_degrees = Vector3(-4.0, 180.0, 0.0)
		spot.light_color = Color(1.0, 0.96, 0.88)
		spot.light_energy = 5.0
		spot.spot_range = 45.0
		spot.spot_angle = 34.0
		spot.spot_angle_attenuation = 1.2
		spot.shadow_enabled = false
		spot.visible = false
		add_child(spot)
		_spotlights.append(spot)
		i += 1

	# wipers sit at the base of the windshield
	var wiper_mat: StandardMaterial3D = _mat(Color(0.05, 0.05, 0.06), 0.5, 0.5)
	var wiper_xs: Array[float] = [-0.55, 0.55]
	var w: int = 0
	while w < wiper_xs.size():
		var pivot: Node3D = Node3D.new()
		var wlabel: String = "R"
		if wiper_xs[w] > 0.0:
			wlabel = "L"
		pivot.name = "WiperPivot_" + wlabel
		pivot.position = Vector3(wiper_xs[w], 0.06, FRONT_Z - 0.14)
		root.add_child(pivot)
		_add_box(pivot, "WiperBlade", Vector3(0.05, 0.95, 0.04),
			Vector3(0.0, 0.45, 0.0), wiper_mat, Vector3.ZERO)
		_wiper_nodes.append(pivot)
		w += 1


func _build_rear(root: Node3D, body_mat: StandardMaterial3D, trim_mat: StandardMaterial3D,
		accent_mat: StandardMaterial3D, glass_mat: StandardMaterial3D) -> void:
	_add_box(root, "RearWindow", Vector3(2.20, 0.80, 0.08),
		Vector3(0.0, 0.90, REAR_Z + 0.06), glass_mat, Vector3.ZERO)

	# engine bay louvres
	var l: int = 0
	while l < 4:
		_add_box(root, "Louvre" + str(l), Vector3(1.70, 0.07, 0.10),
			Vector3(0.0, -0.10 + float(l) * 0.14, REAR_Z + 0.04), trim_mat, Vector3.ZERO)
		l += 1

	_add_box(root, "RearBumper", Vector3(2.56, 0.50, 0.42),
		Vector3(0.0, -0.72, REAR_Z + 0.10), trim_mat, Vector3.ZERO)

	# tail light clusters
	var xs: Array[float] = [-0.86, 0.86]
	var i: int = 0
	while i < xs.size():
		var x: float = xs[i]
		var side_label: String = "R"
		if x > 0.0:
			side_label = "L"

		var brake_mat: StandardMaterial3D = _emissive_mat(
			Color(0.40, 0.03, 0.03), Color(1.0, 0.10, 0.05), 1.6)
		_brake_materials.append(brake_mat)

		_add_box(root, "TailHousing_" + side_label, Vector3(0.34, 0.70, 0.08),
			Vector3(x, -0.18, REAR_Z + 0.06), trim_mat, Vector3.ZERO)
		_add_box(root, "TailLight_" + side_label, Vector3(0.28, 0.26, 0.06),
			Vector3(x, -0.05, REAR_Z + 0.02), brake_mat, Vector3.ZERO)

		var turn_mat: StandardMaterial3D = _emissive_mat(
			Color(0.45, 0.22, 0.02), Color(1.0, 0.45, 0.05), 1.0)
		_add_box(root, "RearIndicator_" + side_label, Vector3(0.28, 0.20, 0.06),
			Vector3(x, -0.34, REAR_Z + 0.02), turn_mat, Vector3.ZERO)
		i += 1

	# rear spoiler / roof lip
	_add_box(root, "Spoiler", Vector3(2.40, 0.12, 0.55),
		Vector3(0.0, 1.52, REAR_Z + 0.45), accent_mat, Vector3(-8, 0, 0))


func _build_luggage_bays(root: Node3D, skirt_mat: StandardMaterial3D,
		chrome_mat: StandardMaterial3D) -> void:
	var bay_mat: StandardMaterial3D = _mat(Color(0.13, 0.14, 0.17), 0.5, 0.4)
	var sides: Array[float] = [-1.0, 1.0]
	var zs: Array[float] = [1.35, -1.15]

	var s: int = 0
	while s < sides.size():
		var side: float = sides[s]
		var label: String = "R"
		if side > 0.0:
			label = "L"
		var z: int = 0
		while z < zs.size():
			_add_box(root, "LuggageBay_" + label + str(z), Vector3(0.05, 0.52, 1.9),
				Vector3(side * 1.272, -0.80, zs[z]), bay_mat, Vector3.ZERO)
			_add_box(root, "BayHandle_" + label + str(z), Vector3(0.06, 0.05, 0.35),
				Vector3(side * 1.278, -0.80, zs[z]), chrome_mat, Vector3.ZERO)
			z += 1
		s += 1


func _build_wheel_arches(root: Node3D, skirt_mat: StandardMaterial3D) -> void:
	var arch_mat: StandardMaterial3D = _mat(Color(0.07, 0.07, 0.08), 0.3, 0.7)
	var sides: Array[float] = [-1.0, 1.0]
	var zs: Array[float] = [3.95, -3.25]

	var s: int = 0
	while s < sides.size():
		var side: float = sides[s]
		var label: String = "R"
		if side > 0.0:
			label = "L"
		var z: int = 0
		while z < zs.size():
			_add_box(root, "Arch_" + label + str(z), Vector3(0.10, 0.55, 1.55),
				Vector3(side * 1.255, -0.72, zs[z]), arch_mat, Vector3.ZERO)
			z += 1
		s += 1


func _build_mirrors(root: Node3D, trim_mat: StandardMaterial3D) -> void:
	var mirror_mat: StandardMaterial3D = _mat(Color(0.75, 0.79, 0.85), 1.0, 0.05)
	var sides: Array[float] = [-1.0, 1.0]
	var i: int = 0
	while i < sides.size():
		var side: float = sides[i]
		var label: String = "R"
		if side > 0.0:
			label = "L"

		_add_cylinder(root, "MirrorArm_" + label, 0.035, 0.55,
			Vector3(side * 1.5, 1.15, FRONT_Z - 0.55), trim_mat, Vector3(0, 0, 90), 8)
		_add_box(root, "MirrorHousing_" + label, Vector3(0.10, 0.62, 0.26),
			Vector3(side * 1.76, 0.92, FRONT_Z - 0.55), trim_mat, Vector3.ZERO)
		_add_box(root, "Mirror_" + label, Vector3(0.04, 0.54, 0.20),
			Vector3(side * 1.80, 0.92, FRONT_Z - 0.55), mirror_mat, Vector3.ZERO)
		i += 1


func _build_roof(root: Node3D, body_mat: StandardMaterial3D) -> void:
	var ac_mat: StandardMaterial3D = _mat(Color(0.86, 0.87, 0.89), 0.55, 0.4)
	_add_box(root, "RoofAC", Vector3(1.80, 0.30, 3.0),
		Vector3(0.0, 1.58, -0.6), ac_mat, Vector3.ZERO)
	_add_box(root, "RoofHatchFront", Vector3(0.72, 0.10, 0.72),
		Vector3(0.0, 1.58, 2.6), ac_mat, Vector3.ZERO)
	_add_box(root, "RoofHatchRear", Vector3(0.72, 0.10, 0.72),
		Vector3(0.0, 1.58, -3.4), ac_mat, Vector3.ZERO)


func _build_door(root: Node3D, glass_mat: StandardMaterial3D,
		trim_mat: StandardMaterial3D) -> void:
	# Passenger door on the model RIGHT side (-X), the curb side.
	_add_box(root, "DoorFrame", Vector3(0.09, 2.00, 1.30),
		Vector3(DOOR_X + 0.01, -0.05, DOOR_Z), trim_mat, Vector3.ZERO)

	var leaf: Node3D = Node3D.new()
	leaf.name = "DoorLeaf"
	leaf.position = Vector3(DOOR_X, -0.05, DOOR_Z)
	add_child(leaf)
	_door_node = leaf

	_add_box(leaf, "DoorGlass", Vector3(0.07, 1.80, 1.12),
		Vector3.ZERO, glass_mat, Vector3.ZERO)
	_add_box(leaf, "DoorEdge", Vector3(0.08, 1.88, 0.07),
		Vector3(0.0, 0.0, 0.58), trim_mat, Vector3.ZERO)

	_add_box(root, "DoorStep", Vector3(0.30, 0.10, 1.10),
		Vector3(DOOR_X + 0.10, -1.02, DOOR_Z), trim_mat, Vector3.ZERO)


func _build_interior(root: Node3D) -> void:
	var seat_mat: StandardMaterial3D = _mat(Color(0.14, 0.22, 0.42), 0.0, 0.9)
	var head_mat: StandardMaterial3D = _mat(Color(0.10, 0.16, 0.32), 0.0, 0.9)
	var floor_mat: StandardMaterial3D = _mat(Color(0.18, 0.19, 0.21), 0.0, 0.85)
	var pole_mat: StandardMaterial3D = _mat(Color(0.78, 0.80, 0.84), 0.9, 0.25)
	var dash_mat: StandardMaterial3D = _mat(Color(0.08, 0.08, 0.10), 0.2, 0.75)

	_add_box(root, "InteriorFloor", Vector3(2.30, 0.08, BODY_LENGTH - 0.9),
		Vector3(0.0, -0.94, 0.0), floor_mat, Vector3.ZERO)

	# Seat rows, 2 + 2, facing forward (+Z).
	var row: int = 0
	while row < 8:
		var z: float = 2.35 - float(row) * 1.05
		var xs: Array[float] = [-0.68, 0.68]
		var s: int = 0
		while s < xs.size():
			var x: float = xs[s]
			var label: String = "R"
			if x > 0.0:
				label = "L"
			var tag: String = label + str(row)

			_add_box(root, "SeatBase_" + tag, Vector3(0.80, 0.13, 0.55),
				Vector3(x, -0.58, z), seat_mat, Vector3.ZERO)
			# backrest sits behind the cushion (-Z side)
			_add_box(root, "SeatBack_" + tag, Vector3(0.80, 0.68, 0.13),
				Vector3(x, -0.22, z - 0.26), seat_mat, Vector3.ZERO)
			_add_box(root, "SeatHead_" + tag, Vector3(0.34, 0.18, 0.12),
				Vector3(x, 0.18, z - 0.26), head_mat, Vector3.ZERO)
			s += 1
		row += 1

	# grab poles
	var pole_zs: Array[float] = [2.9, 0.6, -1.7]
	var p: int = 0
	while p < pole_zs.size():
		_add_cylinder(root, "Pole" + str(p), 0.035, 1.9,
			Vector3(-0.55, 0.02, pole_zs[p]), pole_mat, Vector3.ZERO, 8)
		p += 1

	# --- driver area: LEFT side (+X) for right-hand traffic ---
	_add_box(root, "Dashboard", Vector3(2.10, 0.34, 0.72),
		Vector3(0.0, -0.26, FRONT_Z - 0.85), dash_mat, Vector3.ZERO)
	_add_box(root, "DriverSeatBase", Vector3(0.62, 0.15, 0.58),
		Vector3(0.62, -0.56, FRONT_Z - 1.85), seat_mat, Vector3.ZERO)
	_add_box(root, "DriverSeatBack", Vector3(0.62, 0.72, 0.14),
		Vector3(0.62, -0.16, FRONT_Z - 2.12), seat_mat, Vector3.ZERO)

	var wheel_node: MeshInstance3D = MeshInstance3D.new()
	wheel_node.name = "SteeringWheel"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.19
	torus.outer_radius = 0.25
	torus.rings = 16
	torus.ring_segments = 8
	wheel_node.mesh = torus
	wheel_node.position = Vector3(0.62, 0.02, FRONT_Z - 1.28)
	wheel_node.rotation_degrees = Vector3(70.0, 0.0, 0.0)
	wheel_node.set_surface_override_material(0, _mat(Color(0.06, 0.06, 0.07), 0.1, 0.6))
	root.add_child(wheel_node)

	var cabin_light: OmniLight3D = OmniLight3D.new()
	cabin_light.name = "InteriorLight"
	cabin_light.position = Vector3(0.0, 1.05, 0.0)
	cabin_light.light_color = Color(1.0, 0.94, 0.82)
	cabin_light.light_energy = 0.4
	cabin_light.omni_range = 8.0
	cabin_light.shadow_enabled = false
	add_child(cabin_light)
	_interior_light = cabin_light


func _build_lights_only() -> void:
	# Used when a bus.glb loaded: still provide working headlights + door node.
	var xs: Array[float] = [-0.88, 0.88]
	var i: int = 0
	while i < xs.size():
		var x: float = xs[i]
		var label: String = "R"
		if x > 0.0:
			label = "L"
		var spot: SpotLight3D = SpotLight3D.new()
		spot.name = "HeadlightBeam_" + label
		spot.position = Vector3(x, -0.15, FRONT_Z)
		spot.rotation_degrees = Vector3(-4.0, 180.0, 0.0)
		spot.light_color = Color(1.0, 0.96, 0.88)
		spot.light_energy = 5.0
		spot.spot_range = 45.0
		spot.spot_angle = 34.0
		spot.visible = false
		add_child(spot)
		_spotlights.append(spot)
		i += 1

	var door: Node3D = Node3D.new()
	door.name = "DoorPivot"
	door.position = Vector3(DOOR_X, -0.05, DOOR_Z)
	add_child(door)
	_door_node = door


func _build_camera_mounts() -> void:
	var chase: Marker3D = Marker3D.new()
	chase.name = "ChaseAnchor"
	chase.position = Vector3(0.0, 3.6, -10.5)
	add_child(chase)

	# Driver's eye point: left seat (+X), just behind the windshield.
	var interior: Marker3D = Marker3D.new()
	interior.name = "InteriorAnchor"
	interior.position = Vector3(0.62, 0.62, FRONT_Z - 1.75)
	add_child(interior)

	var look: Marker3D = Marker3D.new()
	look.name = "LookTarget"
	look.position = Vector3(0.0, 1.1, FRONT_Z + 2.0)
	add_child(look)


func _make_horn_stream() -> AudioStream:
	# Procedural two-tone air horn so no audio asset download is required.
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
		var wave: float = sin(TAU * 233.0 * t) * 0.5 + sin(TAU * 311.0 * t) * 0.35
		wave += sin(TAU * 466.0 * t) * 0.12
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
