extends Node3D
# City Environment Manager
# Creates a realistic city with buildings, roads, traffic lights, bus stops

@export var city_size: int = 200
@export var building_density: float = 0.7
@export var road_grid_size: int = 4

# References
@onready var buildings_node = $Buildings
@onready var roads_node = $Roads
@onready var traffic_lights = $TrafficLights
@onready var bus_stops = $BusStops
@onready var trees_node = $Trees
@onready var traffic_vehicles = $TrafficVehicles

func _ready():
    # Build the city from scratch
    build_roads()
    build_buildings()
    build_traffic_lights()
    build_bus_stops()
    build_trees()
    build_traffic_system()
    build_fuel_station()
    build_parked_cars()
    build_pedestrians()
    
    # Apply PBR settings to all buildings
    apply_pbr_environment()

func build_roads():
    # Main road grid
    for x in range(-city_size, city_size, 30):
        # North-South roads
        var road = MeshInstance3D.new()
        var plane = PlaneMesh.new()
        plane.size = Vector2(12, city_size * 2)
        road.mesh = plane
        
        var asphalt_mat = StandardMaterial3D.new()
        asphalt_mat.albedo_color = Color(0.15, 0.15, 0.18)
        asphalt_mat.metallic = 0.05
        asphalt_mat.roughness = 0.95
        asphalt_mat.roughness_texture = load("res://assets/textures/road_asphalt.jpg")
        road.mesh.surface_set_material(0, asphalt_mat)
        
        road.name = "Road_NS_%d" % x
        roads_node.add_child(road)
        road.global_position = Vector3(x, 0.02, 0)
        
        # Lane markings (white stripes)
        for z in range(-city_size, city_size, 15):
            var stripe = MeshInstance3D.new()
            var stripe_box = BoxMesh.new()
            stripe_box.size = Vector3(0.15, 0.05, 2.0)
            stripe.mesh = stripe_box
            var stripe_mat = StandardMaterial3D.new()
            stripe_mat.albedo_color = Color(0.92, 0.92, 0.95)
            stripe_mat.metallic = 0.0
            stripe_mat.roughness = 1.0
            stripe.mesh.surface_set_material(0, stripe_mat)
            road.add_child(stripe)
            stripe.global_position = Vector3(0, 0.06, z)
    
    for z in range(-city_size, city_size, 30):
        # East-West roads
        var road = MeshInstance3D.new()
        var plane = PlaneMesh.new()
        plane.size = Vector2(city_size * 2, 12)
        road.mesh = plane
        
        var asphalt_mat = StandardMaterial3D.new()
        asphalt_mat.albedo_color = Color(0.15, 0.15, 0.18)
        asphalt_mat.metallic = 0.05
        asphalt_mat.roughness = 0.95
        road.mesh.surface_set_material(0, asphalt_mat)
        
        road.name = "Road_EW_%d" % z
        roads_node.add_child(road)
        road.global_position = Vector3(0, 0.02, z)
        
        # Yellow center line
        for x in range(-city_size, city_size, 15):
            var stripe = MeshInstance3D.new()
            var stripe_box = BoxMesh.new()
            stripe_box.size = Vector3(2.0, 0.05, 0.1)
            stripe.mesh = stripe_box
            var stripe_mat = StandardMaterial3D.new()
            stripe_mat.albedo_color = Color(0.9, 0.8, 0.1)
            stripe_mat.metallic = 0.0
            stripe_mat.roughness = 1.0
            stripe.mesh.surface_set_material(0, stripe_mat)
            road.add_child(stripe)
            stripe.global_position = Vector3(x, 0.06, 0)
            
            # White dashed line
            if x % 30 == 15:
                var dash = MeshInstance3D.new()
                dash.mesh = stripe_box.duplicate()
                dash.mesh.surface_set_material(0, stripe_mat)
                road.add_child(dash)
                dash.global_position = Vector3(x, 0.06, 0)

func build_buildings():
    # Random buildings of various heights
    for x in range(-city_size, city_size, 25):
        for z in range(-city_size, city_size, 25):
            # Skip areas that are roads
            if (abs(x) % 30 < 6 or abs(z) % 30 < 6) and abs(x) % 30 > 20 and abs(z) % 30 > 20:
                continue
            
            # Random building
            var building = MeshInstance3D.new()
            var box = BoxMesh.new()
            
            var height = randi() % 12 + 3  # 3-15 floors
            var width = randi() % 8 + 6
            var depth = randi() % 8 + 6
            
            box.size = Vector3(width, height * 3.5, depth)
            building.mesh = box
            
            var building_mat = StandardMaterial3D.new()
            # Random building colors
            var colors = [
                Color(0.6, 0.65, 0.7),  # Light gray
                Color(0.55, 0.6, 0.62),  # Beige
                Color(0.3, 0.35, 0.4),    # Dark gray
                Color(0.8, 0.82, 0.75),  # Cream
                Color(0.5, 0.55, 0.58),  # Steel
                Color(0.85, 0.8, 0.75)   # Tan
            ]
            var color_idx = randi() % colors.size()
            building_mat.albedo_color = colors[color_idx]
            building_mat.metallic = 0.4
            building_mat.roughness = 0.6
            
            # Add window texture effect via roughness variation
            # In full version: texture mapping for windows
            
            building.mesh.surface_set_material(0, building_mat)
            
            building.name = "Building_%d_%d" % [x, z]
            buildings_node.add_child(building)
            building.global_position = Vector3(x + randi() % 10 - 5, height * 1.75, z + randi() % 10 - 5)
            
            # Add windows as small emissive planes for night glow
            var windows_node = MeshInstance3D.new()
            var windows_mesh = BoxMesh.new()
            windows_mesh.size = Vector3(width * 0.85, height * 3.0, depth * 0.9)
            windows_node.mesh = windows_mesh
            
            var window_mat = StandardMaterial3D.new()
            window_mat.albedo_color = Color(0.15, 0.15, 0.12)
            window_mat.metallic = 0.1
            window_mat.roughness = 0.9
            window_mat.emission = Color(0.05, 0.05, 0.08)  # Subtle glow
            window_mat.emission_energy = 0.5
            windows_node.mesh.surface_set_material(0, window_mat)
            
            building.add_child(windows_node)
            windows_node.global_position = Vector3(0, 0.5, 0)

func build_traffic_lights():
    var light_positions = [
        Vector3(30, 3, 30), Vector3(-30, 3, 30),
        Vector3(30, 3, -30), Vector3(-30, 3, -30),
        Vector3(30, 3, 0), Vector3(-30, 3, 0)
    ]
    
    for pos in light_positions:
        var light_pole = MeshInstance3D.new()
        var cylinder = CylinderMesh.new()
        cylinder.height = 6.0
        cylinder.radius = 0.1
        light_pole.mesh = cylinder
        
        var pole_mat = StandardMaterial3D.new()
        pole_mat.albedo_color = Color(0.25, 0.25, 0.3)
        pole_mat.metallic = 0.5
        pole_mat.roughness = 0.3
        light_pole.mesh.surface_set_material(0, pole_mat)
        
        light_pole.name = "TrafficLight_%d_%d" % [int(pos.x), int(pos.z)]
        traffic_lights.add_child(light_pole)
        light_pole.global_position = pos
        
        # Traffic light head
        var head = MeshInstance3D.new()
        var head_box = BoxMesh.new()
        head_box.size = Vector3(0.5, 1.2, 0.3)
        head.mesh = head_box
        
        light_pole.add_child(head)
        head.global_position = Vector3(0, 6.0, 0.5)
        
        # Red, yellow, green lights
        for i in range(3):
            var bulb = OmniLight3D.new()
            bulb.name = "Light_%d" % i
            bulb.light_color = [Color(0.9, 0.1, 0.1), Color(0.9, 0.8, 0.1), Color(0.1, 0.9, 0.1)][i]
            bulb.light_energy = 4.0 if i == 0 else 3.0  # Red brighter for visibility
            bulb.omni_range = 5.0
            light_pole.add_child(bulb)
            bulb.global_position = Vector3(0, 6.0 + i * 0.35, 0.65)

func build_bus_stops():
    var stop_positions = [
        Vector3(30, 0, 20), Vector3(-30, 0, 20),
        Vector3(30, 0, -20), Vector3(-30, 0, -20),
        Vector3(0, 0, 30), Vector3(0, 0, -30)
    ]
    
    for i in range(stop_positions.size()):
        var stop_pos = stop_positions[i]
        
        # Bus shelter
        var shelter = MeshInstance3D.new()
        var shelter_box = BoxMesh.new()
        shelter_box.size = Vector3(3.0, 2.5, 1.5)
        shelter.mesh = shelter_box
        
        var shelter_mat = StandardMaterial3D.new()
        shelter_mat.albedo_color = Color(0.3, 0.35, 0.4)
        shelter_mat.metallic = 0.6
        shelter_mat.roughness = 0.4
        shelter.mesh.surface_set_material(0, shelter_mat)
        
        shelter.name = "BusStop_%d" % i
        bus_stops.add_child(shelter)
        shelter.global_position = stop_pos + Vector3(8, 0, 0)
        
        # Bench
        var bench = MeshInstance3D.new()
        var bench_box = BoxMesh.new()
        bench_box.size = Vector3(1.5, 0.4, 0.3)
        bench.mesh = bench_box
        
        var bench_mat = StandardMaterial3D.new()
        bench_mat.albedo_color = Color(0.4, 0.35, 0.2)
        bench_mat.metallic = 0.2
        bench_mat.roughness = 0.7
        bench.mesh.surface_set_material(0, bench_mat)
        
        shelter.add_child(bench)
        bench.global_position = Vector3(0, 0.3, 0.5)
        
        # Route sign
        var sign = MeshInstance3D.new()
        var sign_box = BoxMesh.new()
        sign_box.size = Vector3(1.0, 1.5, 0.05)
        sign.mesh = sign_box
        
        var sign_mat = StandardMaterial3D.new()
        sign_mat.albedo_color = Color(0.9, 0.85, 0.8)
        sign_mat.metallic = 0.0
        sign_mat.roughness = 1.0
        sign.mesh.surface_set_material(0, sign_mat)
        
        shelter.add_child(sign)
        sign.global_position = Vector3(-0.8, 2.0, 0.6)
        
        # Glowing route sign text (simulated with emissive plane)
        var sign_glow = MeshInstance3D.new()
        var glow_box = BoxMesh.new()
        glow_box.size = Vector3(0.8, 0.9, 0.02)
        sign_glow.mesh = glow_box
        
        var glow_mat = StandardMaterial3D.new()
        glow_mat.albedo_color = Color(0.1, 0.08, 0.05)
        glow_mat.emission = Color(1.0, 0.45, 0.1)  # Orange glow
        glow_mat.emission_energy = 2.0
        sign_glow.mesh.surface_set_material(0, glow_mat)
        
        sign.add_child(sign_glow)
        sign_glow.global_position = Vector3(0, 0, 0.05)
        
        # Waiting passengers
        for j in range(2):
            var passenger = MeshInstance3D.new()
            var person_box = BoxMesh.new()
            person_box.size = Vector3(0.35, 1.6, 0.35)
            passenger.mesh = person_box
            
            var person_mat = StandardMaterial3D.new()
            person_mat.albedo_color = [Color(0.2, 0.4, 0.7), Color(0.7, 0.2, 0.3), Color(0.3, 0.5, 0.2)][j]
            passenger.mesh.surface_set_material(0, person_mat)
            
            shelter.add_child(passenger)
            passenger.global_position = Vector3(0.6 + j * 0.6, 0.8, 2.0)

func build_trees():
    for i in range(30):
        # Random tree placement
        var x = randi() % (city_size * 2) - city_size
        var z = randi() % (city_size * 2) - city_size
        
        # Don't place on roads
        if (abs(x) % 30 < 12) and (abs(z) % 30 < 12):
            continue
        
        # Tree trunk
        var trunk = MeshInstance3D.new()
        var cylinder = CylinderMesh.new()
        cylinder.height = 4.0 + randf() * 3.0
        cylinder.radius = 0.3 + randf() * 0.2
        trunk.mesh = cylinder
        
        var trunk_mat = StandardMaterial3D.new()
        trunk_mat.albedo_color = Color(0.35, 0.25, 0.15)
        trunk_mat.metallic = 0.0
        trunk_mat.roughness = 1.0
        trunk.mesh.surface_set_material(0, trunk_mat)
        
        trunk.name = "Tree_%d" % i
        trees_node.add_child(trunk)
        trunk.global_position = Vector3(x, cylinder.height / 2, z)
        
        # Tree foliage
        var foliage = MeshInstance3D.new()
        var sphere = SphereMesh.new()
        sphere.radius = 1.5 + randf() * 1.0
        sphere.rings = 8
        sphere.radial_segments = 8
        foliage.mesh = sphere
        
        var foliage_mat = StandardMaterial3D.new()
        var green_tones = [Color(0.15, 0.45, 0.15), Color(0.2, 0.5, 0.2), Color(0.1, 0.35, 0.1)]
        foliage_mat.albedo_color = green_tones[randi() % green_tones.size()]
        foliage_mat.metallic = 0.0
        foliage_mat.roughness = 0.9
        foliage.mesh.surface_set_material(0, foliage_mat)
        
        trunk.add_child(foliage)
        foliage.global_position = Vector3(0, cylinder.height - 0.5, 0)

func build_traffic_system():
    # Create moving traffic vehicles
    var car_colors = [
        Color(0.9, 0.1, 0.1), Color(0.1, 0.5, 0.9), Color(0.9, 0.8, 0.1),
        Color(0.2, 0.8, 0.2), Color(0.9, 0.3, 0.7), Color(0.2, 0.7, 0.8),
        Color(0.6, 0.15, 0.15), Color(0.15, 0.2, 0.6)
    ]
    
    for i in range(8):
        var car = MeshInstance3D.new()
        var car_box = BoxMesh.new()
        car_box.size = Vector3(2.5, 1.2, 4.5)
        car.mesh = car_box
        
        var car_mat = StandardMaterial3D.new()
        car_mat.albedo_color = car_colors[i % car_colors.size()]
        car_mat.metallic = 0.8
        car_mat.roughness = 0.2
        car.mesh.surface_set_material(0, car_mat)
        
        car.name = "TrafficCar_%d" % i
        traffic_vehicles.add_child(car)
        car.global_position = Vector3(-60 + i * 15, 0.7, -20 + (i % 2) * 40)
        
        # Headlights for traffic cars
        var head_left = OmniLight3D.new()
        head_left.name = "CarHeadLeft_%d" % i
        head_left.light_color = Color(1.0, 0.95, 0.9)
        head_left.light_energy = 3.0
        head_left.omni_range = 10.0
        car.add_child(head_left)
        head_left.global_position = Vector3(-0.8, 0.6, 2.1)
        
        var head_right = OmniLight3D.new()
        head_right.name = "CarHeadRight_%d" % i
        head_right.light_color = Color(1.0, 0.95, 0.9)
        head_right.light_energy = 3.0
        head_right.omni_range = 10.0
        car.add_child(head_right)
        head_right.global_position = Vector3(0.8, 0.6, 2.1)

func build_fuel_station():
    # Fuel station with canopy and pumps
    var station_pos = Vector3(50, 0, 15)
    
    # Canopy
    var canopy = MeshInstance3D.new()
    var canopy_box = BoxMesh.new()
    canopy_box.size = Vector3(8.0, 0.3, 6.0)
    canopy.mesh = canopy_box
    
    var canopy_mat = StandardMaterial3D.new()
    canopy_mat.albedo_color = Color(0.1, 0.1, 0.15)
    canopy_mat.metallic = 0.7
    canopy_mat.roughness = 0.4
    canopy.mesh.surface_set_material(0, canopy_mat)
    
    canopy.name = "FuelCanopy"
    add_child(canopy)
    canopy.global_position = station_pos + Vector3(0, 3.5, 0)
    
    # Fuel pumps
    for i in range(2):
        var pump = MeshInstance3D.new()
        var pump_box = BoxMesh.new()
        pump_box.size = Vector3(0.8, 1.5, 0.8)
        pump.mesh = pump_box
        
        var pump_mat = StandardMaterial3D.new()
        pump_mat.albedo_color = Color(0.8, 0.15, 0.1)
        pump_mat.metallic = 0.6
        pump_mat.roughness = 0.3
        pump.mesh.surface_set_material(0, pump_mat)
        
        pump.name = "FuelPump_%d" % i
        canopy.add_child(pump)
        pump.global_position = Vector3(-1.5 + i * 3.0, -0.5, 0)
        
        # Glowing price sign
        var price_sign = MeshInstance3D.new()
        var sign_box = BoxMesh.new()
        sign_box.size = Vector3(1.5, 0.6, 0.05)
        price_sign.mesh = sign_box
        
        var sign_mat = StandardMaterial3D.new()
        sign_mat.albedo_color = Color(0.05, 0.05, 0.05)
        sign_mat.emission = Color(0.0, 0.8, 0.4)
        sign_mat.emission_energy = 3.0
        price_sign.mesh.surface_set_material(0, sign_mat)
        
        pump.add_child(price_sign)
        price_sign.global_position = Vector3(0, 0.6, 0.45)

func build_parked_cars():
    for i in range(4):
        var car = MeshInstance3D.new()
        var car_box = BoxMesh.new()
        car_box.size = Vector3(2.0, 1.0, 4.0)
        car.mesh = car_box
        
        var car_mat = StandardMaterial3D.new()
        car_mat.albedo_color = Color(0.3 + randf() * 0.5, 0.3 + randf() * 0.3, 0.3 + randf() * 0.3)
        car_mat.metallic = 0.7
        car_mat.roughness = 0.3
        car.mesh.surface_set_material(0, car_mat)
        
        car.name = "ParkedCar_%d" % i
        add_child(car)
        car.global_position = Vector3(25 + i * 3, 0.5, 45 + (i % 2) * 4)
        car.rotation_degrees.y = 90

func build_pedestrians():
    for i in range(6):
        var pedestrian = MeshInstance3D.new()
        var body = BoxMesh.new()
        body.size = Vector3(0.35, 1.7, 0.35)
        pedestrian.mesh = body
        
        var ped_mat = StandardMaterial3D.new()
        ped_mat.albedo_color = [Color(0.2, 0.4, 0.7), Color(0.6, 0.3, 0.2), Color(0.8, 0.75, 0.6)][randi() % 3]
        ped_mat.metallic = 0.0
        ped_mat.roughness = 0.9
        pedestrian.mesh.surface_set_material(0, ped_mat)
        
        pedestrian.name = "Pedestrian_%d" % i
        add_child(pedestrian)
        pedestrian.global_position = Vector3(-40 + i * 8, 0.85, 35 + (i % 2) * 10)

func apply_pbr_environment():
    # This environment uses Godot's built-in PBR
    pass

func _process(delta):
    # Animate traffic vehicles
    for child in traffic_vehicles.get_children():
        if child is MeshInstance3D:
            # Simple linear movement along roads
            child.global_position.x += delta * 2.0 + (randi() % 3 - 1) * 0.3
            if child.global_position.x > 70:
                child.global_position.x = -70
    
    # Animate pedestrians slightly
    for child in get_children():
        if child.name.begins_with("Pedestrian_"):
            child.global_position.x += sin(Time.get_ticks_msec() / 1000.0 + float(child.name)) * delta * 0.3
            child.rotation_degrees.y = sin(Time.get_ticks_msec() / 800.0) * 15.0
