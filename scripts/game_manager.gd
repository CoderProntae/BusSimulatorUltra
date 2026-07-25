extends Node3D

# Game Manager - Main controller for Bus Simulator Ultra
# Handles game state, economy, weather, time, and scene coordination

@export var initial_money: int = 500
@export var start_fuel: float = 80.0
@export var max_fuel: float = 100.0
@export var fuel_consumption_rate: float = 0.8  # per second at driving speed

var money: int = initial_money
var fuel: float = start_fuel
var passenger_count: int = 0
var delivered_passengers: int = 0
var current_route_stop: String = "Central Station"
var game_time_hour: int = 8
var game_time_minute: int = 0
var is_day: bool = true
var weather_state: int = 0  # 0=clear, 1=cloudy, 2=rainy
var bus_damage: float = 0.0
var bus_is_driving: bool = false
var speed_kmh: float = 0.0
var current_gear: int = 0  # -1=reverse, 0=neutral, 1=drive

# References
@onready var city_scene: Node3D = $CityScene
@onready var bus_scene: Node3D = $BusScene
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var camera: Camera3D = $Camera3D

# Audio players
var engine_audio: AudioStreamPlayer3D
var rain_audio: AudioStreamPlayer3D
var city_ambient: AudioStreamPlayer3D

func _ready():
    print("Bus Simulator Ultra - Game Manager Initialized")
    setup_audio()
    setup_day_night_cycle()
    setup_weather_system()
    apply_pbr_settings()
    
    # Initialize UI reference
    var ui = $UI/UIOverlay
    if ui:
        ui.game_manager = self
        ui.refresh_ui()
    
    # Connect bus signals
    var bus = $BusScene
    if bus:
        bus.game_manager = self
        bus.connect("passenger_delivered", Callable(self, "_on_passenger_delivered"))
        bus.connect("bus_crashed", Callable(self, "_on_bus_crashed"))
        bus.connect("fuel_changed", Callable(self, "_on_fuel_changed"))
    
    # Start with a small passenger load
    passenger_count = 0
    current_route_stop = "Main Street Stop"

func setup_audio():
    # Create audio nodes for atmosphere
    engine_audio = AudioStreamPlayer3D.new()
    engine_audio.name = "EngineAudio"
    engine_audio.autoplay = false
    engine_audio.max_distance = 80.0
    engine_audio.unit_size = 10.0
    add_child(engine_audio)
    
    # Load or generate engine sound placeholder
    # In production, this would be a real .wav file
    var engine_stream = AudioStreamGenerator.new()
    engine_stream.mix_rate = 44100
    engine_stream.buffer_length = 0.5
    engine_audio.stream = engine_stream
    
    rain_audio = AudioStreamPlayer3D.new()
    rain_audio.name = "RainAudio"
    rain_audio.autoplay = false
    rain_audio.max_distance = 200.0
    rain_audio.unit_size = 100.0
    add_child(rain_audio)
    
    city_ambient = AudioStreamPlayer3D.new()
    city_ambient.name = "CityAmbient"
    city_ambient.autoplay = false
    city_ambient.max_distance = 500.0
    add_child(city_ambient)

func setup_day_night_cycle():
    # Use a Timer to advance time slowly
    var timer = Timer.new()
    timer.wait_time = 3.0  # 3 real seconds = 1 game minute roughly
    timer.autostart = true
    timer.timeout.connect(_advance_time)
    add_child(timer)

func setup_weather_system():
    # Random weather changes every minute
    var weather_timer = Timer.new()
    weather_timer.wait_time = 10.0
    weather_timer.autostart = true
    weather_timer.timeout.connect(_change_weather)
    add_child(weather_timer)

func apply_pbr_settings():
    # Configure viewport for PBR
    var viewport = get_viewport()
    viewport.use_hdr_2d = true
    viewport.use_taa = true
    viewport.screen_space_ambient_occlusion_enabled = true
    viewport.screen_space_reflections_enabled = true
    viewport.screen_space_reflections_roughness_quality = 1

func _advance_time():
    game_time_minute += 5
    if game_time_minute >= 60:
        game_time_minute = 0
        game_time_hour += 1
        if game_time_hour >= 24:
            game_time_hour = 0
    
    is_day = (game_time_hour >= 6 and game_time_hour < 19)
    update_day_night_lighting()
    
    # Update UI
    if $UI/UIOverlay:
        $UI/UIOverlay.refresh_ui()

func update_day_night_lighting():
    if !directional_light:
        return
    
    var hour_factor = float(game_time_hour) / 24.0
    
    # Rotate sun based on time
    var sun_angle = (hour_factor - 0.25) * 2.0 * PI  # Simplified solar arc
    directional_light.rotation_degrees = Vector3((hour_factor * 180.0) - 45.0, 0, 0)
    
    # Adjust sun intensity and color
    if is_day:
        directional_light.light_energy = 1.5
        directional_light.light_color = Color(1.0, 0.95, 0.85)
        directional_light.shadow_enabled = true
    else:
        directional_light.light_energy = 0.05
        directional_light.light_color = Color(0.2, 0.25, 0.4)
        directional_light.shadow_enabled = false
    
    # Night adjustments for world environment
    if world_env:
        if is_day:
            world_env.environment.ambient_light_color = Color(0.5, 0.55, 0.6)
            world_env.environment.ambient_light_energy = 1.0
        else:
            world_env.environment.ambient_light_color = Color(0.05, 0.08, 0.15)
            world_env.environment.ambient_light_energy = 0.3

func _change_weather():
    # Random weather transition
    var new_weather = randi() % 3
    if new_weather != weather_state:
        weather_state = new_weather
        apply_weather()

func apply_weather():
    if world_env:
        if weather_state == 2:  # Rainy
            world_env.environment.fog_density = 0.03
            world_env.environment.fog_height_falloff = 0.15
            world_env.environment.fog_light_color = Color(0.65, 0.7, 0.75)
            if rain_audio:
                rain_audio.play()
        elif weather_state == 1:  # Cloudy
            world_env.environment.fog_density = 0.02
            world_env.environment.fog_height_falloff = 0.1
            world_env.environment.fog_light_color = Color(0.75, 0.78, 0.82)
            if rain_audio:
                rain_audio.stop()
        else:  # Clear
            world_env.environment.fog_density = 0.005
            world_env.environment.fog_height_falloff = 0.02
            world_env.environment.fog_light_color = Color(0.85, 0.88, 0.92)
            if rain_audio:
                rain_audio.stop()
    
    # Update bus wet material in rain
    if $BusScene:
        $BusScene.set_weather_rain(weather_state == 2)
    
    # Notify UI
    if $UI/UIOverlay:
        $UI/UIOverlay.refresh_ui()

func _process(delta):
    # Update game time continuously
    # Real-time adjustments handled by timer
    
    # Update engine audio pitch based on speed
    if engine_audio:
        if bus_is_driving and speed_kmh > 5:
            engine_audio.play()
            var pitch_scale = 0.8 + (speed_kmh / 100.0) * 0.8
            engine_audio.pitch_scale = clamp(pitch_scale, 0.8, 2.0)
        else:
            if engine_audio.playing:
                engine_audio.stop()
    
    # Update fuel continuously
    if bus_is_driving:
        fuel -= fuel_consumption_rate * delta * (abs(speed_kmh) / 10.0)
        fuel = clamp(fuel, 0.0, max_fuel)
        if fuel <= 0:
            fuel = 0
            bus_is_driving = false
        if $UI/UIOverlay:
            $UI/UIOverlay.refresh_ui()

func _on_passenger_delivered(count: int, earnings: int):
    delivered_passengers += count
    money += earnings
    passenger_count = 0
    print("Passengers delivered: %d | Earnings: $%d | Total: $%d" % [count, earnings, money])
    
    # Update route
    if delivered_passengers % 5 == 0:
        current_route_stop = "Next Route Stop"
    
    if $UI/UIOverlay:
        $UI/UIOverlay.refresh_ui()

func _on_bus_crashed(amount: float):
    bus_damage += amount
    money -= int(amount * 150)  # Repair cost
    money = max(money, 0)
    print("Crash! Damage: %.1f | Repair cost: $%d" % [amount, int(amount * 150)])
    if $UI/UIOverlay:
        $UI/UIOverlay.refresh_ui()

func _on_fuel_changed(new_fuel: float):
    fuel = new_fuel
    if $UI/UIOverlay:
        $UI/UIOverlay.refresh_ui()

func refuel(amount: float):
    var cost = amount * 2.5  # $2.50 per unit
    if money >= cost:
        money -= int(cost)
        fuel = clamp(fuel + amount, 0, max_fuel)
        print("Refueled: %.1f | Cost: $%.0f | Remaining: $%d" % [amount, cost, money])
        if $UI/UIOverlay:
            $UI/UIOverlay.refresh_ui()
    else:
        print("Not enough money to refuel!")

func repair_bus():
    if bus_damage > 0:
        var cost = int(bus_damage * 200)
        if money >= cost:
            money -= cost
            bus_damage = 0
            print("Bus repaired! Cost: $%d" % cost)
            if $UI/UIOverlay:
                $UI/UIOverlay.refresh_ui()
        else:
            print("Not enough money for repairs!")

# Mobile touch input helpers (exposed for UI)
func on_steer_input(direction: float):
    # Called from UI buttons
    if $BusScene and $BusScene.has_method("set_steering"):
        $BusScene.set_steering(direction)

func on_throttle_input(active: bool):
    if $BusScene and $BusScene.has_method("set_throttle"):
        $BusScene.set_throttle(active)

func on_brake_input(active: bool):
    if $BusScene and $BusScene.has_method("set_brake"):
        $BusScene.set_brake(active)

func on_gear_change(gear: int):
    current_gear = gear
    if $BusScene and $BusScene.has_method("set_gear"):
        $BusScene.set_gear(gear)

func on_door_toggle():
    if $BusScene and $BusScene.has_method("toggle_doors"):
        $BusScene.toggle_doors()

func on_camera_switch():
    # Cycle through camera modes
    var cameras = ["Exterior", "Interior", "DoorCam", "TopDown"]
    # Implementation in camera script
    if $Camera3D:
        # Simplified: just log for now, real cycling handled by camera controller
        print("Camera switched")

func get_current_speed() -> float:
    return speed_kmh

func get_fuel_percentage() -> float:
    return (fuel / max_fuel) * 100.0

func get_money() -> int:
    return money

func get_passenger_count() -> int:
    return passenger_count

func get_route_stop() -> String:
    return current_route_stop
