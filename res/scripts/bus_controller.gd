class_name BusController
extends VehicleBody3D

@export var max_speed_kph: float = 80.0
var speed_kph: float = 0.0
var steering_target: float = 0.0
var door_open := false
var headlights := false
var door: Node3D
var headlamps: Array[OmniLight3D] = []

func _ready() -> void:
	mass = 10000.0
	add_to_group("bus")
	_build_fallback_bus()
	_load_optional_model()

func _physics_process(delta: float) -> void:
	speed_kph = linear_velocity.length() * 3.6
	var steering_input := Input.get_axis("steer_right", "steer_left")
	steering_target = move_toward(steering_target, steering_input * 0.42, delta * 1.6)
	var fuel_ok := true
	var state := get_tree().get_first_node_in_group("game_state")
	if state != null:
		fuel_ok = state.fuel > 0.0
	var throttle := Input.get_action_strength("accelerate") if fuel_ok else 0.0
	var brake_input := Input.get_action_strength("brake")
	for wheel in get_children():
		if wheel is VehicleWheel3D:
			if wheel.use_as_steering:
				wheel.steering = steering_target
			if wheel.use_as_traction:
				wheel.engine_force = throttle * 9500.0 if speed_kph < max_speed_kph else 0.0
			wheel.brake = brake_input * 60.0
	if Input.is_action_just_pressed("door"):
		toggle_door()
	if Input.is_action_just_pressed("headlights"):
		set_night_lights(not headlights)
	if door != null:
		var target := 0.9 if door_open else 0.0
		door.position.z = move_toward(door.position.z, target, delta * 1.7)

func toggle_door() -> void:
	door_open = not door_open

func set_night_lights(value: bool) -> void:
	headlights = value
	for lamp in headlamps:
		lamp.visible = value

func _box(parent: Node, pos: Vector3, size: Vector3, color: Color, metallic := 0.0, emission := Color(0, 0, 0)) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.35
	material.emission_enabled = emission.a > 0.0
	material.emission = emission
	item.mesh = mesh
	item.material_override = material
	item.position = pos
	parent.add_child(item)
	return item

func _build_fallback_bus() -> void:
	_box(self, Vector3(0, 1.65, 0), Vector3(2.55, 2.45, 9.6), Color("d9a72b"), 0.45)
	_box(self, Vector3(0, 3.0, -3.15), Vector3(2.5, 0.75, 3.0), Color("e8be43"), 0.35)
	_box(self, Vector3(0, 3.45, 0), Vector3(2.15, 0.18, 6.2), Color("e6e6e0"), 0.25)
	_box(self, Vector3(0, 4.0, 0.2), Vector3(1.25, 0.32, 2.7), Color("d4d4d0"), 0.65)
	var glass := Color(0.04, 0.16, 0.23, 0.72)
	for side in [-1.0, 1.0]:
		for index in range(6):
			_box(self, Vector3(side * 1.29, 2.55, -2.7 + index * 1.05), Vector3(0.06, 0.78, 0.82), glass, 0.75)
	_box(self, Vector3(0, 2.55, -4.82), Vector3(2.1, 0.9, 0.06), glass, 0.65)
	_box(self, Vector3(0, 3.45, -4.86), Vector3(1.55, 0.36, 0.07), Color("161c22"), 0.1, Color(1.0, 0.65, 0.08, 1))
	_box(self, Vector3(0, 0.6, -4.95), Vector3(2.6, 0.25, 0.26), Color("25282b"), 0.7)
	_box(self, Vector3(0, 0.6, 4.95), Vector3(2.6, 0.25, 0.26), Color("25282b"), 0.7)
	door = Node3D.new()
	door.position = Vector3(1.31, 1.55, -1.25)
	add_child(door)
	_box(door, Vector3.ZERO, Vector3(0.08, 1.75, 1.35), glass, 0.65)
	for x in [-1.02, 1.02]:
		_box(self, Vector3(x, 2.25, -4.25), Vector3(0.12, 0.11, 0.8), Color("181818"), 0.75)
	for x in [-0.82, 0.82]:
		_box(self, Vector3(x, 1.05, -4.92), Vector3(0.35, 0.22, 0.08), Color("fff2be"), 0.1, Color(1, 0.8, 0.35, 1))
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.8, 0.45)
		lamp.light_energy = 2.0
		lamp.omni_range = 8.0
		lamp.position = Vector3(x, 1.05, -4.7)
		lamp.visible = false
		add_child(lamp)
		headlamps.append(lamp)
		_box(self, Vector3(x, 1.1, 4.92), Vector3(0.32, 0.2, 0.08), Color("ff2424"), 0.1, Color(1, 0, 0, 1))
	for z in [-3.0, 3.0]:
		for x in [-1.05, 1.05]:
			_make_wheel(Vector3(x, 0.48, z), z < 0.0)
	for z in [-1.4, 1.2]:
		for x in [-0.65, 0.65]:
			_box(self, Vector3(x, 1.3, z), Vector3(0.48, 0.22, 0.72), Color("3d4a51"), 0.15)

func _make_wheel(pos: Vector3, steer: bool) -> void:
	var wheel := VehicleWheel3D.new()
	wheel.position = pos
	wheel.use_as_steering = steer
	wheel.use_as_traction = not steer
	wheel.wheel_radius = 0.48
	wheel.suspension_stiffness = 25.0
	wheel.damping_compression = 3.0
	wheel.damping_rebound = 3.0
	add_child(wheel)
	var tire := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.48
	mesh.bottom_radius = 0.48
	mesh.height = 0.28
	tire.mesh = mesh
	tire.rotation_degrees.z = 90.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("111318")
	material.metallic = 0.25
	tire.material_override = material
	wheel.add_child(tire)

func _load_optional_model() -> void:
	var path := "res://assets/models/bus.glb"
	if ResourceLoader.exists(path):
		var model := load(path)
		if model is PackedScene:
			var visual := model.instantiate()
			visual.scale = Vector3(0.01, 0.01, 0.01)
			add_child(visual)
