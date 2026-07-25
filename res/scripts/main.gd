extends Node3D

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("5c91bd")
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.light_color = Color("ffe0b0")
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-45, -25, 0)
	add_child(sun)
	var state := GameState.new()
	state.add_to_group("game_state")
	add_child(state)
	var city := CityBuilder.new()
	add_child(city)
	var bus := BusController.new()
	bus.position = Vector3(0, 1.0, -18)
	add_child(bus)
	var passengers := PassengerSystem.new()
	passengers.game_state = state
	passengers.add_to_group("passengers")
	add_child(passengers)
	var fuel := FuelSystem.new()
	fuel.game_state = state
	add_child(fuel)
	var cycle := DayNightCycle.new()
	cycle.sun = sun
	add_child(cycle)
	var cameras := CameraSystem.new()
	cameras.bus = bus
	cameras.add_to_group("camera_system")
	add_child(cameras)
	var hud := UIManager.new()
	hud.game_state = state
	hud.bus = bus
	add_child(hud)
	for index in range(5):
		var car := TrafficAI.new()
		car.route_radius = 28.0 + index * 6.0
		car.phase = index * 1.25
		add_child(car)
