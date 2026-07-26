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
const MAX_STEER_ANGLE: float = 0.55
const STEER_SPEED: float = 3.4
const STEER_RETURN_SPEED: float = 4.2
## Engine force PER DRIVEN WHEEL, in newtons.
##
## The bus was painfully slow: 3400 N over only 2 driven wheels on a 10 t body
## is 6800 / 10000 = 0.68 m/s^2, i.e. over 30 s to reach 80 km/h, and the low
## friction slip meant even that was not reaching the road.
##
## Now all four wheels drive: 6000 N x 4 / 10000 kg = 2.4 m/s^2 of raw drive
## force, so roughly 6 s to 50 km/h before drag and rolling resistance. A real
## city bus takes 10-14 s, but that feels sluggish on a phone; this keeps the
## bus unmistakably heavy while still being responsive.
const ENGINE_POWER: float = 6000.0
const BRAKE_POWER: float = 220.0
const HANDBRAKE_POWER: float = 420.0
## Engine braking when the driver lifts off. Small: a heavy bus coasts.
const IDLE_DRAG: float = 4.0
## Air + rolling resistance, scaled by speed^2, so top speed settles instead
## of the bus creeping past MAX_SPEED_KMH.
const DRAG_COEFFICIENT: float = 0.55

## Litres per second. The old rates (0.055 / 0.85) emptied the 300 L tank in
## about 5.5 minutes of hard driving, which the player felt was too slow to
## matter. Roughly tripled: ~4 minutes of city driving, ~9 minutes idling, so
## refuelling is a real part of the route without becoming the whole game.
const FUEL_IDLE_RATE: float = 0.55
const FUEL_DRIVE_RATE: float = 1.35

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
var _door_warning_sent: bool = false
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
# --- cockpit parts animated from _update_cockpit() ---
var _steering_wheel_node: Node3D = null
var _speedo_needle: MeshInstance3D = null
var _tacho_needle: MeshInstance3D = null

@onready var _horn_player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
var _engine_player: AudioStreamPlayer3D = null


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

	_setup_engine_audio()

	if GameState != null:
		GameState.night_factor_changed.connect(_on_night_factor_changed)


func _physics_process(delta: float) -> void:
	speed_kmh = linear_velocity.length() * 3.6

	_update_steering(delta)
	_update_drive(delta)
	_update_fuel(delta)
	_update_door(delta)
	_update_wipers(delta)
	_update_cockpit(delta)
	_update_engine_audio(delta)
	_report_crashes()


func _report_crashes() -> void:
	## The bus is the heavy body with the momentum, so IT tells the traffic it
	## has been hit. A CharacterBody3D (traffic_ai.gd) only sees contacts made
	## by its own move_and_slide(), which meant driving into a stopped car
	## produced no damage, no fire and no explosion at all.
	##
	## contact_monitor / max_contacts_reported are already enabled in _ready().
	var bodies: Array[Node3D] = get_colliding_bodies()
	var i: int = 0
	while i < bodies.size():
		var body: Node3D = bodies[i]
		i += 1
		if body == null or not is_instance_valid(body):
			continue
		if not body.is_in_group("traffic"):
			continue
		if not body.has_method("take_external_hit"):
			continue

		var other_vel: Vector3 = Vector3.ZERO
		if body.has_method("get_velocity"):
			var v: Variant = body.call("get_velocity")
			if v is Vector3:
				other_vel = v as Vector3

		# Closing speed along the line between the two vehicles.
		var to_other: Vector3 = body.global_position - global_position
		to_other.y = 0.0
		if to_other.length() < 0.01:
			continue
		var normal: Vector3 = to_other.normalized()
		var closing: float = (linear_velocity - other_vel).dot(normal)
		if closing <= 0.5:
			continue
		body.call("take_external_hit", closing, -normal)


func _update_steering(delta: float) -> void:
	var target: float = clampf(steer_input, -1.0, 1.0)

	# Steering authority shrinks with speed so the bus feels heavy.
	var speed_factor: float = clampf(1.0 - speed_kmh / 190.0, 0.55, 1.0)
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

	# Taper the throttle as the limiter approaches instead of chopping it to
	# zero, which used to make the bus surge and stall around the top speed.
	if forward_speed >= MAX_SPEED_KMH:
		throttle = 0.0
	elif forward_speed > MAX_SPEED_KMH - 8.0:
		throttle *= clampf((MAX_SPEED_KMH - forward_speed) / 8.0, 0.0, 1.0)

	# Reverse when braking while nearly stopped.
	var drive: float = throttle
	var reversing: bool = false
	if braking > 0.01 and forward_speed < 1.5:
		drive = -braking * 0.55
		reversing = true

	engine_force = drive * ENGINE_POWER

	var brake_amount: float = 0.0
	if braking > 0.01 and forward_speed > 1.5:
		brake_amount = braking * BRAKE_POWER
	if throttle < 0.01 and braking < 0.01:
		brake_amount = IDLE_DRAG
	if handbrake:
		brake_amount = HANDBRAKE_POWER

	# DOOR INTERLOCK.
	#
	# This used to read "if doors_open and speed_kmh > 1.0: brake = 25".
	# 25 units of brake against 6800 N of drive meant the bus could never
	# climb past that 1.0 km/h trigger: the speedometer sat on 1, or on 0,
	# exactly as reported. Worse, nothing told the player why, because the
	# doors default to open and the interlock is invisible.
	#
	# A real bus simply will not pull away with the doors open, so now the
	# throttle is cut outright (clear cause and effect) and the brake is only
	# firm enough to hold the bus still, not to fight the engine forever.
	if doors_open and not reversing:
		engine_force = 0.0
		if speed_kmh > 0.5:
			brake_amount = maxf(brake_amount, BRAKE_POWER * 0.5)
		_warn_doors_open()

	brake = brake_amount

	# Quadratic drag: the dominant resistance at speed, and what actually
	# settles the top speed rather than the hard cut-off above.
	var speed_ms: float = linear_velocity.length()
	if speed_ms > 0.1:
		var drag: Vector3 = -linear_velocity.normalized() * DRAG_COEFFICIENT * speed_ms * speed_ms
		apply_central_force(drag)

	_update_brake_lights(braking)


func _warn_doors_open() -> void:
	## Tell the player once per closed->open cycle why the bus will not move.
	if _door_warning_sent:
		return
	if throttle_input < 0.05:
		return
	_door_warning_sent = true
	if GameState != null:
		GameState.notify("Close the doors before driving off")


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
	# Re-arm the "close the doors" hint for the next time they are opened.
	if not doors_open:
		_door_warning_sent = false
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
	## Side / rear glazing: tinted, seen mostly from outside.
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.14, 0.19, 0.42)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.85
	mat.roughness = 0.06
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _windshield_mat() -> StandardMaterial3D:
	## The windshield needs its own, much clearer material.
	##
	## From the interior camera the old one was effectively opaque, for three
	## reasons stacked on top of each other:
	##   1. alpha 0.62 is a heavy tint to look THROUGH (it is fine to look AT)
	##   2. metallic 0.9 makes the surface mirror the dark cabin back at you
	##   3. the opaque WindshieldFrame box sat 60 mm in front of the glass and
	##      filled the view on its own
	## Now: barely tinted, non-metallic, and the frame is hollowed out below.
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.72, 0.80, 0.10)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.0
	mat.roughness = 0.02
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Do not let the windshield catch shadows: an acne-speckled pane reads as
	# dirt smeared across the driver's view.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
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
	## GROUND CLEARANCE IS PART OF THE HANDLING. Read before editing.
	##
	## Wheel centres sit at y = -0.62 with a 0.52 m radius, so the tyres touch
	## the road at y = -1.14. The body then sags about 0.09 m onto its springs.
	##
	## The box used to be 2.9 m tall centred at y = 0.35, putting its underside
	## at -1.10: only 4 cm above the tyre contact patch, which the static sag
	## alone pushed 5 cm UNDERGROUND. The hull scraped the tarmac, the road
	## carried the bus instead of the wheels, and with no load on the tyres
	## there was no traction: the throttle did nothing and speed stayed at 0.
	##
	## 2.5 m tall centred at 0.55 puts the underside at -0.70, giving 44 cm of
	## clearance -- 35 cm even after sag. The hull mesh is unchanged; this is
	## only the physics proxy.
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2.55, 2.5, BODY_LENGTH)
	shape.shape = box
	shape.position = Vector3(0.0, 0.55, 0.0)
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
		# All four wheels drive. Only the rear axle used to, which halved the
		# available force and let the rears spin up while the fronts dragged,
		# so the bus crawled away from a standstill.
		wheel.use_as_traction = true

		wheel.wheel_radius = 0.52
		wheel.wheel_rest_length = 0.3
		# Friction slip was 4.0 / 3.6, well under Godot's 10.5 default. On a
		# 10 t body that is not enough grip to put the engine force on the
		# road: the tyres slipped instead of accelerating the bus.
		wheel.wheel_friction_slip = 9.0

		# SUSPENSION - THE NUMBERS HERE ARE LOAD-BEARING, DO NOT "TIDY" THEM.
		#
		# The bus weighs 10000 kg * 9.8 = 98000 N, i.e. 24500 N on each wheel
		# just standing still.
		#
		# A previous pass set max_force to 12000 and stiffness to 70 after
		# misreading the docs' "a quarter of the mass" as 2500 (that is the
		# MASS in kg / 4, not the WEIGHT in newtons). The springs could then
		# carry 4 * 12000 = 48000 N, only 49% of the bus. The chassis sank
		# through its own travel, the body dragged on the tarmac and the
		# wheels barely touched the road, so engine force went nowhere and
		# the speedometer read 0 no matter how long the throttle was held.
		#
		# stiffness is N/mm, so static sag = 24500 / (stiffness * 1000):
		#     70 N/mm  -> 35.0 cm sag   (travel is 28 cm: bottomed out)
		#    260 N/mm  ->  9.4 cm sag   (a third of travel: correct)
		wheel.suspension_stiffness = 260.0
		wheel.suspension_travel = 0.28
		# Docs: "should be higher than a quarter of the mass ... good results
		# are often obtained by 3x to 4x this number". A quarter of the weight
		# is 24500 N, so 3.5x that.
		wheel.suspension_max_force = 85000.0
		# Docs: compression ~0.3, relaxation slightly higher. Scaled up for a
		# spring this stiff, or a 10 t body oscillates for a long time.
		wheel.damping_compression = 0.5
		wheel.damping_relaxation = 0.8
		if not is_front:
			# Slightly more grip at the driven rear axle.
			wheel.wheel_friction_slip = 10.5

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

	# --- livery colours ---
	# Deep yellow coach with a black glazing band and skirt, the classic
	# intercity look the player asked for.
	var body_mat: StandardMaterial3D = _mat(Color(0.96, 0.74, 0.06), 0.45, 0.18)
	body_mat.clearcoat_enabled = true
	body_mat.clearcoat = 0.95
	body_mat.clearcoat_roughness = 0.04

	# Dark graphite band that ties the window line together.
	var accent_mat: StandardMaterial3D = _mat(Color(0.07, 0.07, 0.09), 0.55, 0.24)
	accent_mat.clearcoat_enabled = true
	accent_mat.clearcoat = 0.9

	var skirt_mat: StandardMaterial3D = _mat(Color(0.07, 0.07, 0.08), 0.45, 0.45)
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
	#
	# The frame used to be one solid box covering the whole aperture, sitting
	# 60 mm behind the glass -- from the driver's seat you were staring at
	# painted metal, not through a window. It is now four thin edge pieces
	# with a genuine hole in the middle.
	var glass_w: float = 2.30
	var glass_h: float = 1.42
	var frame_t: float = 0.09
	var rake: Vector3 = Vector3(-12, 0, 0)
	var frame_z: float = FRONT_Z - 0.10

	# top and bottom rails
	_add_box(root, "WindshieldRailTop", Vector3(glass_w + 0.14, frame_t, 0.10),
		Vector3(0.0, 0.72 + glass_h * 0.5, frame_z + 0.015), trim_mat, rake)
	_add_box(root, "WindshieldRailBottom", Vector3(glass_w + 0.14, frame_t, 0.10),
		Vector3(0.0, 0.72 - glass_h * 0.5, frame_z - 0.015), trim_mat, rake)
	# left and right posts (A-pillars)
	_add_box(root, "WindshieldPostL", Vector3(frame_t, glass_h + 0.14, 0.10),
		Vector3(glass_w * 0.5, 0.72, frame_z), trim_mat, rake)
	_add_box(root, "WindshieldPostR", Vector3(frame_t, glass_h + 0.14, 0.10),
		Vector3(-glass_w * 0.5, 0.72, frame_z), trim_mat, rake)
	# slim central divider, as on a real two-piece coach screen
	_add_box(root, "WindshieldDivider", Vector3(0.05, glass_h, 0.07),
		Vector3(0.0, 0.72, frame_z + 0.005), trim_mat, rake)

	_add_box(root, "Windshield", Vector3(glass_w, glass_h, 0.04),
		Vector3(0.0, 0.72, FRONT_Z - 0.04), _windshield_mat(), rake)

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
	## Coach mirrors: tall body-coloured housings on arms that reach FORWARD
	## past the windscreen, which is the silhouette people recognise on an
	## intercity bus.
	var mirror_mat: StandardMaterial3D = _mat(Color(0.72, 0.77, 0.84), 1.0, 0.04)
	var arm_mat: StandardMaterial3D = _mat(Color(0.96, 0.74, 0.06), 0.45, 0.20)
	arm_mat.clearcoat_enabled = true
	arm_mat.clearcoat = 0.9

	var sides: Array[float] = [-1.0, 1.0]
	var i: int = 0
	while i < sides.size():
		var side: float = sides[i]
		var label: String = "R"
		if side > 0.0:
			label = "L"

		# horizontal stalk out from the A-pillar
		_add_cylinder(root, "MirrorArm_" + label, 0.038, 0.42,
			Vector3(side * 1.42, 1.28, FRONT_Z - 0.30), arm_mat,
			Vector3(0, 0, 90), 10)
		# vertical riser, angled slightly forward like the real thing
		_add_cylinder(root, "MirrorRiser_" + label, 0.036, 0.46,
			Vector3(side * 1.62, 1.12, FRONT_Z - 0.22), arm_mat,
			Vector3(14, 0, 0), 10)
		# main mirror head
		_add_box(root, "MirrorHousing_" + label, Vector3(0.13, 0.66, 0.24),
			Vector3(side * 1.66, 0.86, FRONT_Z - 0.16), arm_mat, Vector3(0, 6, 0))
		_add_box(root, "Mirror_" + label, Vector3(0.03, 0.58, 0.19),
			Vector3(side * 1.72, 0.86, FRONT_Z - 0.15), mirror_mat, Vector3(0, 6, 0))
		# small wide-angle spotter mirror underneath
		_add_box(root, "MirrorSpotter_" + label, Vector3(0.11, 0.20, 0.17),
			Vector3(side * 1.64, 0.44, FRONT_Z - 0.16), arm_mat, Vector3(0, 6, 0))
		_add_box(root, "MirrorSpotterGlass_" + label, Vector3(0.03, 0.16, 0.13),
			Vector3(side * 1.70, 0.44, FRONT_Z - 0.15), mirror_mat, Vector3(0, 6, 0))
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

	_build_cockpit(root, seat_mat, dash_mat, pole_mat)

	var cabin_light: OmniLight3D = OmniLight3D.new()
	cabin_light.name = "InteriorLight"
	cabin_light.position = Vector3(0.0, 1.05, 0.0)
	cabin_light.light_color = Color(1.0, 0.94, 0.82)
	cabin_light.light_energy = 0.4
	cabin_light.omni_range = 8.0
	cabin_light.shadow_enabled = false
	add_child(cabin_light)
	_interior_light = cabin_light


func _build_cockpit(root: Node3D, seat_mat: StandardMaterial3D,
		dash_mat: StandardMaterial3D, pole_mat: StandardMaterial3D) -> void:
	## Detailed driver's cockpit, built to be looked at from the INTERIOR
	## camera. Everything here sits in front of / around the driver's eye
	## point (see _build_camera_mounts), so proportions are chosen for how
	## they read from the seat, not from outside the bus.
	##
	## Driver is on the LEFT of the bus, which is +X (the bus faces +Z).
	var dx: float = 0.66

	var plastic: StandardMaterial3D = _mat(Color(0.07, 0.075, 0.09), 0.15, 0.72)
	var soft: StandardMaterial3D = _mat(Color(0.11, 0.115, 0.13), 0.05, 0.88)
	var chrome: StandardMaterial3D = _mat(Color(0.80, 0.83, 0.88), 1.0, 0.14)
	var rubber: StandardMaterial3D = _mat(Color(0.05, 0.05, 0.055), 0.0, 0.94)
	var screen_mat: StandardMaterial3D = _emissive_mat(
		Color(0.02, 0.04, 0.05), Color(0.16, 0.78, 0.62), 1.5)

	# ---- dashboard shell: a wrap-around binnacle, not a flat slab ----
	var dash_z: float = FRONT_Z - 0.92
	_add_box(root, "DashMain", Vector3(2.24, 0.40, 0.66),
		Vector3(0.0, -0.30, dash_z), dash_mat, Vector3.ZERO)
	# top cowl, angled so it catches the light like a real moulding
	_add_box(root, "DashCowl", Vector3(2.24, 0.10, 0.44),
		Vector3(0.0, -0.09, dash_z + 0.10), plastic, Vector3(-24, 0, 0))
	# lower knee bolster, tucked under and back
	_add_box(root, "DashLower", Vector3(2.10, 0.34, 0.34),
		Vector3(0.0, -0.62, dash_z - 0.12), plastic, Vector3(12, 0, 0))
	# kick panel down to the floor
	_add_box(root, "DashKick", Vector3(2.10, 0.30, 0.10),
		Vector3(0.0, -0.86, dash_z - 0.26), soft, Vector3.ZERO)

	# ---- instrument binnacle right in front of the driver ----
	var pod_z: float = dash_z + 0.06
	_add_box(root, "InstrumentPod", Vector3(0.76, 0.30, 0.30),
		Vector3(dx, -0.13, pod_z), plastic, Vector3(-30, 0, 0))
	# hood over the dials to stop sun glare
	_add_box(root, "InstrumentHood", Vector3(0.82, 0.05, 0.26),
		Vector3(dx, 0.03, pod_z + 0.03), plastic, Vector3(-42, 0, 0))

	# The two main dials. Kept as thin cylinders facing the driver.
	var dial_face: StandardMaterial3D = _emissive_mat(
		Color(0.03, 0.035, 0.045), Color(0.35, 0.62, 0.95), 0.9)
	_add_cylinder(root, "DialSpeedo", 0.115, 0.02,
		Vector3(dx - 0.16, -0.11, pod_z + 0.15), dial_face, Vector3(60, 0, 0), 20)
	_add_cylinder(root, "DialTacho", 0.095, 0.02,
		Vector3(dx + 0.15, -0.12, pod_z + 0.14), dial_face, Vector3(60, 0, 0), 20)
	_add_cylinder(root, "DialRimSpeedo", 0.125, 0.016,
		Vector3(dx - 0.16, -0.112, pod_z + 0.146), chrome, Vector3(60, 0, 0), 20)
	_add_cylinder(root, "DialRimTacho", 0.105, 0.016,
		Vector3(dx + 0.15, -0.122, pod_z + 0.136), chrome, Vector3(60, 0, 0), 20)

	# Live needles. Stored so _update_cockpit() can animate them.
	_speedo_needle = _add_box(root, "NeedleSpeedo", Vector3(0.012, 0.10, 0.006),
		Vector3(dx - 0.16, -0.11, pod_z + 0.163), _emissive_mat(
			Color(0.9, 0.15, 0.12), Color(1.0, 0.22, 0.16), 3.0), Vector3(60, 0, 0))
	_tacho_needle = _add_box(root, "NeedleTacho", Vector3(0.012, 0.084, 0.006),
		Vector3(dx + 0.15, -0.12, pod_z + 0.153), _emissive_mat(
			Color(0.95, 0.72, 0.15), Color(1.0, 0.78, 0.2), 3.0), Vector3(60, 0, 0))
	# Pivot the needles about the dial centre rather than their own middle.
	_pivot_needle(_speedo_needle, 0.05)
	_pivot_needle(_tacho_needle, 0.042)

	# small multi-function display beside the dials
	_add_box(root, "DashScreen", Vector3(0.26, 0.13, 0.012),
		Vector3(dx + 0.02, -0.30, dash_z + 0.34), screen_mat, Vector3(-18, 0, 0))

	# ---- steering column and wheel ----
	_add_cylinder(root, "SteeringColumn", 0.055, 0.46,
		Vector3(dx, -0.30, dash_z + 0.30), plastic, Vector3(66, 0, 0), 12)

	# The wheel is a child of a pivot so it can actually rotate with steering.
	var wheel_pivot: Node3D = Node3D.new()
	wheel_pivot.name = "SteeringWheelPivot"
	wheel_pivot.position = Vector3(dx, -0.10, dash_z + 0.52)
	# 66 deg of rake: near-horizontal like a bus, not vertical like a car.
	wheel_pivot.rotation_degrees = Vector3(66.0, 0.0, 0.0)
	root.add_child(wheel_pivot)
	_steering_wheel_node = wheel_pivot

	var rim: MeshInstance3D = MeshInstance3D.new()
	rim.name = "WheelRim"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.215
	torus.outer_radius = 0.255
	torus.rings = 28
	torus.ring_segments = 12
	rim.mesh = torus
	# TorusMesh lies in the XZ plane; the pivot already applies the rake.
	rim.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	rim.set_surface_override_material(0, rubber)
	wheel_pivot.add_child(rim)

	# three spokes, 120 deg apart
	var spoke_angles: Array[float] = [90.0, 210.0, 330.0]
	var sp: int = 0
	while sp < spoke_angles.size():
		var ang: float = deg_to_rad(spoke_angles[sp])
		var spoke: MeshInstance3D = MeshInstance3D.new()
		spoke.name = "WheelSpoke" + str(sp)
		var sbox: BoxMesh = BoxMesh.new()
		sbox.size = Vector3(0.185, 0.022, 0.05)
		spoke.mesh = sbox
		spoke.position = Vector3(cos(ang) * 0.105, 0.0, sin(ang) * 0.105)
		spoke.rotation_degrees = Vector3(0.0, -spoke_angles[sp], 0.0)
		spoke.set_surface_override_material(0, plastic)
		wheel_pivot.add_child(spoke)
		sp += 1

	# centre boss with a horn pad
	var boss: MeshInstance3D = MeshInstance3D.new()
	boss.name = "WheelBoss"
	var bcyl: CylinderMesh = CylinderMesh.new()
	bcyl.top_radius = 0.072
	bcyl.bottom_radius = 0.072
	bcyl.height = 0.045
	bcyl.radial_segments = 16
	boss.mesh = bcyl
	boss.set_surface_override_material(0, plastic)
	wheel_pivot.add_child(boss)

	# ---- stalks on the column ----
	_add_box(root, "StalkLeft", Vector3(0.16, 0.018, 0.018),
		Vector3(dx - 0.17, -0.20, dash_z + 0.40), plastic, Vector3(0, 0, -8))
	_add_box(root, "StalkRight", Vector3(0.16, 0.018, 0.018),
		Vector3(dx + 0.17, -0.20, dash_z + 0.40), plastic, Vector3(0, 0, 8))

	# ---- pedals ----
	_add_box(root, "PedalThrottle", Vector3(0.09, 0.020, 0.20),
		Vector3(dx - 0.10, -0.86, dash_z + 0.16), rubber, Vector3(-16, 0, 0))
	_add_box(root, "PedalBrake", Vector3(0.11, 0.020, 0.17),
		Vector3(dx + 0.12, -0.86, dash_z + 0.14), rubber, Vector3(-16, 0, 0))

	# ---- gear selector / handbrake console beside the seat ----
	_add_box(root, "Console", Vector3(0.28, 0.16, 0.52),
		Vector3(dx - 0.44, -0.64, dash_z - 0.62), plastic, Vector3.ZERO)
	_add_cylinder(root, "GearStick", 0.020, 0.24,
		Vector3(dx - 0.44, -0.46, dash_z - 0.52), chrome, Vector3(-10, 0, 0), 10)
	_add_cylinder(root, "GearKnob", 0.043, 0.05,
		Vector3(dx - 0.44, -0.35, dash_z - 0.54), plastic, Vector3.ZERO, 14)
	_add_box(root, "HandbrakeLever", Vector3(0.035, 0.035, 0.26),
		Vector3(dx - 0.44, -0.50, dash_z - 0.78), chrome, Vector3(28, 0, 0))

	# ---- driver's seat, properly shaped ----
	var seat_z: float = FRONT_Z - 2.00
	_add_box(root, "DriverSeatBase", Vector3(0.60, 0.16, 0.58),
		Vector3(dx, -0.62, seat_z), seat_mat, Vector3.ZERO)
	_add_box(root, "DriverSeatBack", Vector3(0.60, 0.78, 0.15),
		Vector3(dx, -0.18, seat_z - 0.28), seat_mat, Vector3(6, 0, 0))
	_add_box(root, "DriverSeatHead", Vector3(0.30, 0.20, 0.13),
		Vector3(dx, 0.28, seat_z - 0.30), seat_mat, Vector3.ZERO)
	# side bolsters
	_add_box(root, "DriverSeatBolsterL", Vector3(0.08, 0.20, 0.52),
		Vector3(dx + 0.27, -0.54, seat_z), seat_mat, Vector3.ZERO)
	_add_box(root, "DriverSeatBolsterR", Vector3(0.08, 0.20, 0.52),
		Vector3(dx - 0.27, -0.54, seat_z), seat_mat, Vector3.ZERO)
	# air-suspended pedestal
	_add_cylinder(root, "SeatPedestal", 0.10, 0.30,
		Vector3(dx, -0.84, seat_z - 0.05), plastic, Vector3.ZERO, 10)

	# ---- cab furniture ----
	# driver's side window pillar trim, gives the cabin a sense of enclosure
	_add_box(root, "CabDivider", Vector3(0.06, 1.30, 0.06),
		Vector3(-0.62, -0.20, FRONT_Z - 1.55), plastic, Vector3.ZERO)
	# fare tray / ticket machine to the driver's right
	_add_box(root, "FareTray", Vector3(0.30, 0.10, 0.28),
		Vector3(dx - 0.62, -0.30, dash_z - 0.18), plastic, Vector3.ZERO)
	# grab handle above the door
	_add_cylinder(root, "CabGrabHandle", 0.022, 0.44,
		Vector3(-0.70, 0.46, FRONT_Z - 1.30), pole_mat, Vector3(0, 0, 90), 8)

	# interior mirror, angled back down the aisle
	_add_box(root, "InteriorMirror", Vector3(0.34, 0.10, 0.02),
		Vector3(0.10, 0.62, FRONT_Z - 1.10), chrome, Vector3(18, 0, 0))

	# sun visor over the driver
	_add_box(root, "SunVisor", Vector3(0.74, 0.02, 0.22),
		Vector3(dx, 0.68, FRONT_Z - 0.72), soft, Vector3(-34, 0, 0))


func _pivot_needle(needle: MeshInstance3D, offset: float) -> void:
	## A BoxMesh rotates about its centre. Sliding the mesh up inside a plain
	## Node3D pivot makes the needle sweep from the dial hub like a real one.
	if needle == null:
		return
	var parent: Node = needle.get_parent()
	if parent == null:
		return
	var pivot: Node3D = Node3D.new()
	pivot.name = needle.name + "Pivot"
	pivot.transform = needle.transform
	parent.add_child(pivot)
	parent.remove_child(needle)
	pivot.add_child(needle)
	needle.transform = Transform3D.IDENTITY
	needle.position = Vector3(0.0, offset, 0.0)


func _update_cockpit(delta: float) -> void:
	## Animates the parts of the cab the driver can see moving.
	if _steering_wheel_node != null and is_instance_valid(_steering_wheel_node):
		# Wheel turns ~2.2 turns lock to lock; _steer_current is -1..1.
		var wheel_angle: float = -_steer_current * 3.9
		_steering_wheel_node.rotation.y = lerpf(
			_steering_wheel_node.rotation.y, wheel_angle, clampf(delta * 12.0, 0.0, 1.0))

	if _speedo_needle != null and is_instance_valid(_speedo_needle):
		var ratio: float = clampf(speed_kmh / 120.0, 0.0, 1.0)
		# Sweep 240 degrees, starting at the 7-o'clock mark.
		var angle: float = deg_to_rad(-120.0 + ratio * 240.0)
		var pivot: Node = _speedo_needle.get_parent()
		if pivot != null and pivot is Node3D:
			(pivot as Node3D).rotation.y = angle

	if _tacho_needle != null and is_instance_valid(_tacho_needle):
		var rpm_ratio: float = clampf(_engine_rpm_ratio(), 0.0, 1.0)
		var tangle: float = deg_to_rad(-120.0 + rpm_ratio * 240.0)
		var tpivot: Node = _tacho_needle.get_parent()
		if tpivot != null and tpivot is Node3D:
			(tpivot as Node3D).rotation.y = tangle


func _engine_rpm_ratio() -> float:
	## Rough rev model: idle plus road speed, nudged by throttle.
	var base: float = 0.16
	var from_speed: float = clampf(speed_kmh / MAX_SPEED_KMH, 0.0, 1.0) * 0.62
	var from_throttle: float = clampf(throttle_input, 0.0, 1.0) * 0.22
	return clampf(base + from_speed + from_throttle, 0.0, 1.0)


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
	#
	# Y is eye height above the bus origin, not seat height: sat at 0.62 the
	# camera was level with the dashboard top and the cowl filled the frame.
	# Z sits the driver behind the wheel (which is at FRONT_Z - 0.40) so the
	# rim and dials are visible in the lower part of the view, the way they
	# are from a real driving seat.
	var interior: Marker3D = Marker3D.new()
	interior.name = "InteriorAnchor"
	interior.position = Vector3(0.66, 0.30, FRONT_Z - 1.62)
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


func _setup_engine_audio() -> void:
	## Looping diesel drone, generated procedurally so no audio file is needed.
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.name = "EngineAudio"
	player.stream = _make_engine_stream()
	player.unit_size = 14.0
	player.max_db = -6.0
	player.volume_db = -18.0
	add_child(player)
	_engine_player = player
	player.play()


func _update_engine_audio(_delta: float) -> void:
	if _engine_player == null or not is_instance_valid(_engine_player):
		return
	var load_factor: float = clampf(throttle_input, 0.0, 1.0)
	var speed_factor: float = clampf(speed_kmh / MAX_SPEED_KMH, 0.0, 1.0)

	# Pitch rises with road speed and, a little, with throttle.
	var pitch: float = 0.72 + speed_factor * 0.95 + load_factor * 0.18
	_engine_player.pitch_scale = clampf(pitch, 0.6, 2.0)

	var volume: float = -24.0 + load_factor * 12.0 + speed_factor * 8.0
	if not engine_running:
		volume = -60.0
	_engine_player.volume_db = clampf(volume, -60.0, -4.0)


func _make_engine_stream() -> AudioStream:
	var sample_rate: int = 22050
	# One second of seamless diesel rumble (harmonics of a low idle).
	var frames: int = sample_rate
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)

	var i: int = 0
	while i < frames:
		var t: float = float(i) / float(sample_rate)
		# Integer harmonics keep the loop seamless.
		var wave: float = sin(TAU * 32.0 * t) * 0.55
		wave += sin(TAU * 64.0 * t) * 0.28
		wave += sin(TAU * 96.0 * t) * 0.16
		wave += sin(TAU * 160.0 * t) * 0.07
		# Slight roughness so it sounds mechanical rather than a pure tone.
		wave += sin(TAU * 224.0 * t) * 0.05 * sin(TAU * 8.0 * t)
		var value: float = clampf(wave * 0.42, -1.0, 1.0)
		var sample: int = int(value * 30000.0)
		if sample < 0:
			sample += 65536
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
		i += 1

	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	stream.data = data
	return stream
