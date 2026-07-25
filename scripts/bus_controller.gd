extends Node3D
# Bus Controller - Realistic heavy bus physics and interaction

signal passenger_delivered(count: int, earnings: int)
signal bus_crashed(damage: float)
signal fuel_changed(new_fuel: float)

@export var bus_mass: float = 15000.0  # kg
@export var top_speed_kmh: float = 80.0
@export var acceleration_rate: float = 0.8  # m/s^2 roughly scaled
@export var deceleration_rate: float = 2.5
@export var steering_angle: float = 25.0  # degrees
@export var turn_radius_factor: float = 2.8  # wide turning

# Internal state
var velocity: Vector3 = Vector3.ZERO
var steering_input: float = 0.0  # -1 to 1
var throttle_input: bool = false
var brake_input: bool = false
var current_steering_angle: float = 0.0
var doors_open: bool = false
var passengers_onboard: int = 0
var passengers_waiting_at_stop: int = 3
var door_timer: float = 0.0

# References to 3D nodes
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var front_wheel_l: MeshInstance3D = $Wheels/FrontLeft
@onready var front_wheel_r: MeshInstance3D = $Wheels/FrontRight
@onready var rear_wheel_l: MeshInstance3D = $Wheels/RearLeft
@onready var rear_wheel_r: MeshInstance3D = $Wheels/RearRight
@onready var windshield: MeshInstance3D = $BodyMesh/Components/Windshield
@onready var headlights: MeshInstance3D = $Lights/Headlights
@onready var tail_lights: MeshInstance3D = $Lights/TailLights
@onready var turn_signals: MeshInstance3D = $Lights/TurnSignals
@onready var mirrors: MeshInstance3D = $Mirrors
@onready var roof_ac: MeshInstance3D = $BodyMesh/Components/RoofAC
@onready var front_bumper: MeshInstance3D = $BodyMesh/Components/FrontBumper
@onready var rear_bumper: MeshInstance3D = $BodyMesh/Components/RearBumper
@onready var wipers: MeshInstance3D = $Wipers
@onready var license_plate: MeshInstance3D = $BodyMesh/Components/LicensePlate
@onready var doors_left: MeshInstance3D = $Doors/LeftDoor
@onready var doors_right: MeshInstance3D = $Doors/RightDoor
@onready var interior_mirror: MeshInstance3D = $Interior/RearViewMirror
@onready var dashboard: MeshInstance3D = $Interior/Dashboard
@onready var steering_wheel: MeshInstance3D = $Interior/Dashboard/SteeringWheel
@onready var passenger_seats: Node3D = $Interior/PassengerSeats

# Game manager reference
var game_manager: Node = null

func _ready():
    # Initialize realistic bus appearance
    setup_bus_materials()
    setup_lights()
    setup_wheels()
    
    # Initialize interior
    setup_interior_lighting()
    
    # Initialize passenger seats
    generate_passenger_seats()

func setup_bus_materials():
    # Create PBR materials for the bus body
    var body_mat = StandardMaterial3D.new()
    body_mat.metallic = 0.9
    body_mat.metallic_specular = 1.0
    body_mat.roughness = 0.15
    body_mat.albedo_color = Color(0.15, 0.35, 0.65)  # Deep blue bus paint
    
    # Apply to body
    if body_mesh:
        body_mesh.material_override = body_mat
    
    # Window glass
    if windshield:
        var glass_mat = StandardMaterial3D.new()
        glass_mat.metallic = 0.2
        glass_mat.metallic_specular = 0.5
        glass_mat.roughness = 0.05
        glass_mat.transmission = 0.6
        glass_mat.transmission_roughness = 0.1
        glass_mat.albedo_color = Color(0.8, 0.9, 1.0, 0.6)
        windshield.material_override = glass_mat

func setup_lights():
    # Headlights
    var head_light_left = OmniLight3D.new()
    head_light_left.name = "HeadLightLeft"
    head_light_left.light_color = Color(1.0, 0.95, 0.8)
    head_light_left.light_energy = 8.0
    head_light_left.omni_range = 25.0
    head_light_left.omni_shadow_mode = 1
    add_child(head_light_left)
    head_light_left.global_position = Vector3(-1.2, 1.0, 4.0)
    
    var head_light_right = OmniLight3D.new()
    head_light_right.name = "HeadLightRight"
    head_light_right.light_color = Color(1.0, 0.95, 0.8)
    head_light_right.light_energy = 8.0
    head_light_right.omni_range = 25.0
    head_light_right.omni_shadow_mode = 1
    add_child(head_light_right)
    head_light_right.global_position = Vector3(1.2, 1.0, 4.0)
    
    # Tail lights
    var tail_light_left = OmniLight3D.new()
    tail_light_left.name = "TailLightLeft"
    tail_light_left.light_color = Color(0.9, 0.1, 0.1)
    tail_light_left.light_energy = 3.0
    tail_light_left.omni_range = 8.0
    add_child(tail_light_left)
    tail_light_left.global_position = Vector3(-1.5, 1.2, -4.2)
    
    var tail_light_right = OmniLight3D.new()
    tail_light_right.name = "TailLightRight"
    tail_light_right.light_color = Color(0.9, 0.1, 0.1)
    tail_light_right.light_energy = 3.0
    tail_light_right.omni_range = 8.0
    add_child(tail_light_right)
    tail_light_right.global_position = Vector3(1.5, 1.2, -4.2)
    
    # Turn signals
    var turn_left = OmniLight3D.new()
    turn_left.name = "TurnLeft"
    turn_left.light_color = Color(1.0, 0.6, 0.1)
    turn_left.light_energy = 5.0
    turn_left.omni_range = 6.0
    add_child(turn_left)
    turn_left.global_position = Vector3(-1.0, 1.0, 4.2)
    
    var turn_right = OmniLight3D.new()
    turn_right.name = "TurnRight"
    turn_right.light_color = Color(1.0, 0.6, 0.1)
    turn_right.light_energy = 5.0
    turn_right.omni_range = 6.0
    add_child(turn_right)
    turn_right.global_position = Vector3(1.0, 1.0, 4.2)
    
    # Interior ceiling lights
    for i in range(4):
        var interior_light = OmniLight3D.new()
        interior_light.name = "InteriorLight%d" % i
        interior_light.light_color = Color(1.0, 0.95, 0.85)
        interior_light.light_energy = 4.0
        interior_light.omni_range = 10.0
        add_child(interior_light)
        interior_light.global_position = Vector3(0, 2.5, -2.0 + i * 1.5)

func setup_wheels():
    # Create wheel rotation
    # Wheels are MeshInstance3D nodes that we'll rotate in _process
    pass

func generate_passenger_seats():
    # Generate rows of seats in interior
    for row in range(6):
        # Left side seats
        for col in range(2):
            var seat = MeshInstance3D.new()
            seat.name = "Seat_L%d_C%d" % [row, col]
            var box = BoxMesh.new()
            box.size = Vector3(0.45, 0.45, 0.6)
            seat.mesh = box
            
            var seat_mat = StandardMaterial3D.new()
            seat_mat.metallic = 0.1
            seat_mat.roughness = 0.8
            seat_mat.albedo_color = Color(0.25, 0.28, 0.32)  # Dark fabric
            seat.mesh.surface_set_material(0, seat_mat)
            
            if passenger_seats:
                passenger_seats.add_child(seat)
                seat.global_position = Vector3(-0.6 + col * 0.5, 0.35, -1.5 - row * 0.8)
        
        # Right side seats
        for col in range(2):
            var seat = MeshInstance3D.new()
            seat.name = "Seat_R%d_C%d" % [row, col]
            var box = BoxMesh.new()
            box.size = Vector3(0.45, 0.45, 0.6)
            seat.mesh = box
            
            var seat_mat = StandardMaterial3D.new()
            seat_mat.metallic = 0.1
            seat_mat.roughness = 0.8
            seat_mat.albedo_color = Color(0.28, 0.25, 0.28)  # Slightly different
            seat.mesh.surface_set_material(0, seat_mat)
            
            if passenger_seats:
                passenger_seats.add_child(seat)
                seat.global_position = Vector3(0.6 - col * 0.5, 0.35, -1.5 - row * 0.8)

func setup_interior_lighting():
    # Warm interior ceiling lights
    for light_node in get_children():
        if light_node.name.begins_with("InteriorLight"):
            var light = light_node as OmniLight3D
            if light:
                light.shadow_enabled = false
                light.omni_shadow_mode = 0

func _process(delta):
    # Physics simulation
    apply_steering(delta)
    apply_acceleration(delta)
    apply_braking(delta)
    apply_suspension(delta)
    
    # Update wheel rotation based on speed
    var speed_mps = velocity.length()
    var rotation_speed = (speed_mps / 3.0) * delta  # Simplified wheel rotation
    
    if front_wheel_l:
        front_wheel_l.rotation_degrees.y += rotation_speed * 20.0
    if front_wheel_r:
        front_wheel_r.rotation_degrees.y += rotation_speed * 20.0
    if rear_wheel_l:
        rear_wheel_l.rotation_degrees.y += rotation_speed * 20.0
    if rear_wheel_r:
        rear_wheel_r.rotation_degrees.y += rotation_speed * 20.0
    
    # Update steering wheel visual
    if steering_wheel:
        steering_wheel.rotation_degrees.z = -current_steering_angle * 2.5
    
    # Update wipers (intermittent)
    if wipers:
        wipers.rotation_degrees.y = sin(Time.get_ticks_msec() / 500.0) * 30.0
    
    # Update doors animation
    if doors_open:
        door_timer += delta
        if doors_left:
            doors_left.rotation_degrees.y = -45.0 * clamp(door_timer * 2.0, 0.0, 1.0)
        if doors_right:
            doors_right.rotation_degrees.y = 45.0 * clamp(door_timer * 2.0, 0.0, 1.0)
    else:
        door_timer = 0.0
        if doors_left:
            doors_left.rotation_degrees.y = 0.0
        if doors_right:
            doors_right.rotation_degrees.y = 0.0
    
    # Update position
    global_position += velocity * delta
    
    # Update game manager reference
    if game_manager and is_instance_valid(game_manager):
        game_manager.speed_kmh = velocity.length() * 3.6
        game_manager.bus_is_driving = throttle_input and abs(velocity.length()) > 0.5
        # Apply fuel consumption
        if game_manager.has_method("_process"):
            pass  # Handled by manager

func apply_steering(delta):
    # Realistic bus steering: slow, wide turning radius
    var target_steering = steering_input * steering_angle
    # Gradual steering response (heavy bus)
    current_steering_angle = lerp(current_steering_angle, target_steering, delta * 1.5)
    
    # Apply rotation to bus body based on steering and forward velocity
    if abs(velocity.z) > 0.5:  # Only steer when moving forward
        var turn_rate = (current_steering_angle / 25.0) * velocity.z * 0.015 * delta
        rotation.y += turn_rate
        
        # Body roll when turning
        var roll_amount = current_steering_angle * 0.008
        # Apply to interior only for effect, or use rotation_degrees.z
        # For simplicity, rotate the whole bus slightly
        # rotation.z = roll_amount  # Disabled for stability
    else:
        # When not moving, slowly return wheels to center
        current_steering_angle = lerp(current_steering_angle, 0.0, delta * 2.0)

func apply_acceleration(delta):
    # Realistic heavy bus acceleration
    if throttle_input and current_steering_angle < 45:
        var target_speed = top_speed_kmh / 3.6  # Convert to m/s
        var current_speed = velocity.length()
        
        # Slow acceleration
        var acceleration = acceleration_rate * delta * (1.0 - (current_speed / target_speed))
        
        # Apply force in forward direction (local z axis)
        var forward_dir = -transform.basis.z  # Godot forward is -Z
        velocity += forward_dir * acceleration
        
        # Cap speed
        if velocity.length() > target_speed:
            velocity = velocity.normalized() * target_speed
    else:
        # Gradual deceleration due to drag
        velocity *= 0.98

func apply_braking(delta):
    if brake_input or !throttle_input:
        # Long braking distance
        var brake_force = deceleration_rate * delta
        if brake_input:
            brake_force *= 2.5  # Harder brake
        
        # Reduce velocity
        if velocity.length() > 0.1:
            velocity = velocity.normalized() * max(0, velocity.length() - brake_force)
        else:
            velocity = Vector3.ZERO

func apply_suspension(delta):
    # Subtle bounce over bumps (simulated with slight vertical oscillation)
    var bounce = sin(Time.get_ticks_msec() / 300.0) * 0.02
    # Apply very subtle bounce
    # In a full simulation, this would detect terrain bumps
    # For this demo, apply a gentle oscillation

func set_steering(direction: float):
    steering_input = clamp(direction, -1.0, 1.0)

func set_throttle(active: bool):
    throttle_input = active

func set_brake(active: bool):
    brake_input = active

func set_gear(gear: int):
    # 1=Drive, 0=Neutral, -1=Reverse
    if gear == -1:
        # Reverse: swap velocity direction
        velocity = velocity.normalized() * max(0, velocity.length() - 0.5)
        # Allow reverse acceleration
        throttle_input = true  # For reverse, throttle pushes backward
    else:
        if gear == 0:
            throttle_input = false
        else:
            throttle_input = throttle_input  # Maintain

func toggle_doors():
    doors_open = !doors_open
    door_timer = 0.0
    
    # Passenger boarding logic
    if doors_open:
        # After 2 seconds, passengers board
        if passenger_seats and passengers_waiting_at_stop > 0:
            # Board passengers
            passengers_onboard += min(passengers_waiting_at_stop, 8)
            passengers_waiting_at_stop = max(0, passengers_waiting_at_stop - 8)
            print("Passengers boarded: %d | Onboard: %d" % [min(passengers_waiting_at_stop + 8, 8), passengers_onboard])
            
            # Play door sound
            # In production: AudioStreamPlayer3D.play()
    else:
        # Deliver passengers
        if passengers_onboard > 0:
            var earnings = passengers_onboard * 15  # $15 per passenger
            emit_signal("passenger_delivered", passengers_onboard, earnings)
            passengers_onboard = 0
            passengers_waiting_at_stop = randi() % 6 + 2  # New passengers at next stop
            print("Passengers delivered. New waiting: %d" % passengers_waiting_at_stop)

func set_weather_rain(is_raining: bool):
    # When raining, adjust bus body roughness for wet look
    if body_mesh and body_mesh.material_override:
        var mat = body_mesh.material_override
        if is_raining:
            mat.metallic = 0.95
            mat.roughness = 0.05  # Very wet and reflective
        else:
            mat.metallic = 0.9
            mat.roughness = 0.15

func _input(event):
    # Keyboard controls for desktop testing
    if event is InputEventKey:
        if event.pressed:
            if event.keycode == KEY_D:
                set_steering(1.0)
            elif event.keycode == KEY_A:
                set_steering(-1.0)
            elif event.keycode == KEY_W:
                set_throttle(true)
            elif event.keycode == KEY_S:
                set_brake(true)
            elif event.keycode == KEY_E:
                toggle_doors()
            elif event.keycode == KEY_R:
                set_gear(-1)  # Reverse
            elif event.keycode == KEY_SPACE:
                toggle_doors()
        else:
            if event.keycode == KEY_D or event.keycode == KEY_A:
                set_steering(0.0)
            elif event.keycode == KEY_W:
                set_throttle(false)
            elif event.keycode == KEY_S:
                set_brake(false)
            elif event.keycode == KEY_R:
                set_gear(1)  # Drive
