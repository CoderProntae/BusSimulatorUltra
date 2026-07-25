extends Control
# UI Controller - Mobile HUD and touch controls

# References
var game_manager: Node = null

@onready var speedometer: Label = $HUD/Speedometer
@onready var fuel_bar: ProgressBar = $HUD/FuelGauge
@onready var money_label: Label = $HUD/MoneyLabel
@onready var passenger_label: Label = $HUD/PassengerLabel
@onready var route_label: Label = $HUD/RouteName
@onready var clock_label: Label = $HUD/GameClock
@onready var gear_indicator: Label = $HUD/GearIndicator
@onready var minimap_display: TextureRect = $HUD/Minimap

# Touch controls
@onready var steer_left_btn: Button = $Controls/Steering/SteerLeft
@onready var steer_right_btn: Button = $Controls/Steering/SteerRight
@onready var throttle_btn: Button = $Controls/Pedals/Throttle
@onready var brake_btn: Button = $Controls/Pedals/Brake
@onready var horn_btn: Button = $Controls/HornButton
@onready var door_btn: Button = $Controls/DoorButton
@onready var camera_btn: Button = $Controls/CameraButton
@onready var headlight_btn: Button = $Controls/HeadlightButton

var steering_active_left: bool = false
var steering_active_right: bool = false
var throttle_active: bool = false
var brake_active: bool = false

func _ready():
    # Find game manager in parent scene
    var parent = get_parent()
    while parent != null:
        if parent.has_method("get_current_speed"):
            game_manager = parent
            break
        parent = parent.get_parent()
    
    # Configure mobile-friendly button sizes
    for button in [steer_left_btn, steer_right_btn, throttle_btn, brake_btn, horn_btn, door_btn, camera_btn, headlight_btn]:
        if button:
            button.modulate = Color(1, 1, 1, 0.7)  # Semi-transparent
            button.custom_minimum_size = Vector2(80, 80)
            
            # Add touch signals
            button.pressed.connect(Callable(self, "_on_button_pressed").bind(button.name))
            button.released.connect(Callable(self, "_on_button_released").bind(button.name))
    
    # Set initial UI values
    refresh_ui()

func refresh_ui():
    if game_manager:
        # Speedometer
        if speedometer:
            var speed = game_manager.get_current_speed() if game_manager.has_method("get_current_speed") else 0
            speedometer.text = "%.0f km/h" % speed
        
        # Fuel gauge
        if fuel_bar:
            var fuel_pct = game_manager.get_fuel_percentage() if game_manager.has_method("get_fuel_percentage") else 50.0
            fuel_bar.value = fuel_pct
            fuel_bar.modulate = Color(1, 1, 1) if fuel_pct > 20 else Color(1, 0.3, 0.3)
        
        # Money
        if money_label:
            var money = game_manager.get_money() if game_manager.has_method("get_money") else 0
            money_label.text = "Money: $%d" % money
        
        # Passengers
        if passenger_label:
            var passengers = game_manager.get_passenger_count() if game_manager.has_method("get_passenger_count") else 0
            passenger_label.text = "Passengers: %d" % passengers
        
        # Route
        if route_label:
            var route = game_manager.get_route_stop() if game_manager.has_method("get_route_stop") else "Unknown"
            route_label.text = "Next Stop:\n%s" % route
        
        # Clock
        if clock_label:
            var hour = game_manager.game_time_hour if game_manager.has_property("game_time_hour") else 8
            var minute = game_manager.game_time_minute if game_manager.has_property("game_time_minute") else 0
            clock_label.text = "%02d:%02d" % [hour, minute]
        
        # Gear
        if gear_indicator:
            var gear = game_manager.current_gear if game_manager.has_property("current_gear") else 1
            if gear == 1:
                gear_indicator.text = "D"
            elif gear == -1:
                gear_indicator.text = "R"
            else:
                gear_indicator.text = "N"

func _process(delta):
    # Update steering based on active buttons
    var steer_input = 0.0
    if steering_active_left:
        steer_input -= 1.0
    if steering_active_right:
        steer_input += 1.0
    
    if game_manager and game_manager.has_method("on_steer_input"):
        game_manager.on_steer_input(steer_input)
    
    # Update throttle/brake
    if game_manager:
        if throttle_active and game_manager.has_method("on_throttle_input"):
            game_manager.on_throttle_input(true)
        elif throttle_btn and !throttle_btn.button_pressed and throttle_active:
            throttle_active = false
            if game_manager.has_method("on_throttle_input"):
                game_manager.on_throttle_input(false)
        
        if brake_active and game_manager.has_method("on_brake_input"):
            game_manager.on_brake_input(true)
        elif brake_btn and !brake_btn.button_pressed and brake_active:
            brake_active = false
            if game_manager.has_method("on_brake_input"):
                game_manager.on_brake_input(false)

func _on_button_pressed(button_name: String):
    match button_name:
        "SteerLeft":
            steering_active_left = true
        "SteerRight":
            steering_active_right = true
        "Throttle":
            throttle_active = true
            if game_manager and game_manager.has_method("on_throttle_input"):
                game_manager.on_throttle_input(true)
        "Brake":
            brake_active = true
            if game_manager and game_manager.has_method("on_brake_input"):
                game_manager.on_brake_input(true)
        "HornButton":
            # Play horn sound (placeholder)
            print("Horn!")
        "DoorButton":
            if game_manager and game_manager.has_method("on_door_toggle"):
                game_manager.on_door_toggle()
        "CameraButton":
            if game_manager and game_manager.has_method("on_camera_switch"):
                game_manager.on_camera_switch()
        "HeadlightButton":
            # Toggle headlights
            print("Headlights toggled")

func _on_button_released(button_name: String):
    match button_name:
        "SteerLeft":
            steering_active_left = false
        "SteerRight":
            steering_active_right = false
        "Throttle":
            throttle_active = false
            if game_manager and game_manager.has_method("on_throttle_input"):
                game_manager.on_throttle_input(false)
        "Brake":
            brake_active = false
            if game_manager and game_manager.has_method("on_brake_input"):
                game_manager.on_brake_input(false)
