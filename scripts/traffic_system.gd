extends Node3D
# Traffic System - Moving vehicles and traffic light control

@export var traffic_speed: float = 5.0  # m/s base speed

var traffic_state: int = 0  # 0=green, 1=yellow, 2=red
var traffic_timer: float = 0.0
var light_cycle_time: float = 15.0  # Seconds per cycle

func _ready():
    # Initialize traffic vehicles
    pass

func _process(delta):
    # Update traffic light cycle
    traffic_timer += delta
    if traffic_timer >= light_cycle_time:
        traffic_timer = 0.0
        traffic_state = (traffic_state + 1) % 3
        update_traffic_lights()
    
    # Move traffic vehicles
    for child in get_children():
        if child.name.begins_with("TrafficCar_"):
            var car = child as MeshInstance3D
            if car:
                # Check distance to nearest traffic light
                # Simplified: move along local X, reset when far
                car.global_position.x += traffic_speed * delta * (1.0 if traffic_state == 0 else 0.3)
                if car.global_position.x > 80:
                    car.global_position.x = -80
                
                # Rotate car slightly based on position
                car.rotation_degrees.y = sin(Time.get_ticks_msec() / 2000.0 + float(child.name.hash())) * 5.0

func update_traffic_lights():
    # Find all traffic light nodes in parent
    var parent = get_parent()
    if !parent:
        return
    
    for node in parent.get_children():
        if node.name.begins_with("TrafficLight_"):
            # Change light colors based on state
            for light_child in node.get_children():
                if light_child.name.begins_with("Light_"):
                    var omni = light_child as OmniLight3D
                    if omni:
                        var light_idx = int(light_child.name.split("_")[1])
                        # Red=0 always on, others change
                        if light_idx == 0:
                            omni.light_energy = 4.0  # Red
                        elif light_idx == 1 and traffic_state == 1:
                            omni.light_energy = 4.0  # Yellow
                        elif light_idx == 1:
                            omni.light_energy = 0.0
                        elif light_idx == 2 and traffic_state == 0:
                            omni.light_energy = 4.0  # Green
                        elif light_idx == 2:
                            omni.light_energy = 0.0
