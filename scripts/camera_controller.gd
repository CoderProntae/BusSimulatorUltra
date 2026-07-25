extends Camera3D
# Camera Controller - Multiple camera modes for bus simulator

@export var follow_distance: float = 12.0
@export var follow_height: float = 8.0
@export var interior_offset: Vector3 = Vector3(0, 1.6, 0.2)
@export var door_camera_offset: Vector3 = Vector3(0, 2.5, -1.5)
@export var top_down_height: float = 30.0

var current_mode: int = 0  # 0=exterior, 1=interior, 2=door, 3=top
var target_transform: Transform3D
var bus_node: Node3D = null

func _ready():
    # Find bus in scene
    bus_node = get_parent().get_node_or_null("BusScene")
    if bus_node:
        # Set initial exterior position
        var bus_pos = bus_node.global_position
        global_position = bus_pos + Vector3(0, follow_height, follow_distance)
        look_at(bus_pos)

func _process(delta):
    if !bus_node:
        bus_node = get_parent().get_node_or_null("BusScene")
        if !bus_node:
            return
    
    var bus_pos = bus_node.global_position
    var bus_rot = bus_node.global_transform.basis
    
    match current_mode:
        0:  # Exterior chase camera
            var target_pos = bus_pos + bus_rot.z.normalized() * follow_distance + Vector3(0, follow_height, 0)
            # Smooth follow
            global_position = global_position.lerp(target_pos, delta * 3.0)
            # Look at bus
            var look_target = bus_pos + Vector3(0, 2.0, 0)
            look_at_from_position(global_position, look_target, Vector3.UP)
        1:  # Interior camera
            var interior_target = bus_pos + bus_rot * interior_offset
            global_position = interior_target
            # Look forward through windshield
            var look_dir = -bus_rot.z
            look_at(global_position + look_dir * 5.0)
        2:  # Door camera (showing rear door)
            var door_target = bus_pos + bus_rot * door_camera_offset + Vector3(0, 2.0, 0)
            global_position = door_target
            look_at(bus_pos + Vector3(0, 0, 0))
        3:  # Top down
            var top_target = bus_pos + Vector3(0, top_down_height, 0)
            global_position = global_position.lerp(top_target, delta * 5.0)
            look_at_from_position(global_position, bus_pos, Vector3.UP)

func switch_camera():
    current_mode = (current_mode + 1) % 4
    print("Camera mode: %d" % current_mode)
