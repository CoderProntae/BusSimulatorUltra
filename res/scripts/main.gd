extends Node3D

## Boot flow:  MAIN MENU  ->  REAL LOADING  ->  GAME
##
## The loading screen is not a timer. Scenes are streamed on a background
## thread and the city is built in stages across several frames, each stage
## reporting genuine progress, so the bar tracks actual work.

const WORLD_SCENE: String = "res://scenes/World.tscn"
const BUS_SCENE: String = "res://scenes/Bus.tscn"
const HUD_SCENE: String = "res://scenes/HUD.tscn"
const CAMERA_SCRIPT: String = "res://scripts/camera_system.gd"
const MENU_SCRIPT: String = "res://scripts/main_menu.gd"
const LOADING_SCRIPT: String = "res://scripts/loading_screen.gd"
const CITY_SCRIPT_NAME: String = "CityBuilder"

var world: Node3D = null
var bus: VehicleBody3D = null
var camera_rig: Node3D = null
var hud: Control = null

var _probe: ReflectionProbe = null
var _probe_accum: float = 0.0
var _ui_layer: CanvasLayer = null
var _menu: Control = null
var _loader: Control = null
var _game_started: bool = false


func _ready() -> void:
	randomize()
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UILayer"
	_ui_layer.layer = 10
	add_child(_ui_layer)
	_show_menu()


# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------

func _show_menu() -> void:
	var script: Script = _safe_script(MENU_SCRIPT)
	var menu: Control = Control.new()
	if script != null:
		menu.set_script(script)
	menu.name = "MainMenu"
	_ui_layer.add_child(menu)
	_menu = menu
	if menu.has_signal("play_pressed"):
		menu.connect("play_pressed", _on_play_pressed)


func _on_play_pressed() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	_show_loading()


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

func _show_loading() -> void:
	var script: Script = _safe_script(LOADING_SCRIPT)
	var loader: Control = Control.new()
	if script != null:
		loader.set_script(script)
	loader.name = "LoadingScreen"
	_ui_layer.add_child(loader)
	_loader = loader
	if loader.has_signal("loading_finished"):
		loader.connect("loading_finished", _on_loading_finished)
	# Build the world in stages while the loading screen is up.
	_build_game.call_deferred()


func _report(value: float) -> void:
	if _loader != null and is_instance_valid(_loader):
		if _loader.has_method("report_build_progress"):
			_loader.call("report_build_progress", value)


func _build_game() -> void:
	## Each stage yields a frame so the loading screen keeps animating and the
	## progress it shows corresponds to work that has actually completed.
	await get_tree().process_frame
	_spawn_world()
	_report(0.2)

	await get_tree().process_frame
	_spawn_bus()
	_report(0.5)

	await get_tree().process_frame
	_spawn_camera()
	_report(0.65)

	await get_tree().process_frame
	_spawn_hud()
	_report(0.8)

	await get_tree().process_frame
	_spawn_reflection_probe()
	_apply_renderer_safe_graphics()
	if Settings != null:
		Settings.apply_all()
	_report(0.95)

	# Let the physics server settle the freshly spawned bodies for a frame.
	await get_tree().physics_frame
	_report(1.0)


func _on_loading_finished() -> void:
	if _loader != null and is_instance_valid(_loader):
		_loader.queue_free()
		_loader = null
	_game_started = true
	_set_gameplay_visible(true)

	if GameState != null:
		GameState.reset()
		GameState.notify("Welcome! Drive to a stop, open the doors, collect fares.")


func _set_gameplay_visible(value: bool) -> void:
	if hud != null and is_instance_valid(hud):
		hud.visible = value


# ---------------------------------------------------------------------------
# Spawning
# ---------------------------------------------------------------------------

func _spawn_world() -> void:
	var scene: PackedScene = _safe_scene(WORLD_SCENE)
	if scene == null:
		push_warning("World scene missing - building an empty fallback world")
		world = Node3D.new()
		world.name = "World"
		add_child(world)
		return
	var instance: Node = scene.instantiate()
	if instance is Node3D:
		world = instance as Node3D
	else:
		world = Node3D.new()
	world.name = "World"
	add_child(world)


func _spawn_bus() -> void:
	var scene: PackedScene = _safe_scene(BUS_SCENE)
	var node: Node = null
	if scene != null:
		node = scene.instantiate()
	if node == null:
		var script: Script = _safe_script("res://scripts/bus_controller.gd")
		var body: VehicleBody3D = VehicleBody3D.new()
		if script != null:
			body.set_script(script)
		node = body
	if not (node is VehicleBody3D):
		return
	bus = node as VehicleBody3D
	bus.name = "Bus"
	add_child(bus)

	var spawn: Transform3D = Transform3D.IDENTITY
	spawn.origin = Vector3(-86.5, 1.8, -48.0)
	if world != null:
		var city: Node = world.find_child(CITY_SCRIPT_NAME, true, false)
		if city != null and city.has_method("get_spawn_transform"):
			var value: Variant = city.call("get_spawn_transform")
			if value is Transform3D:
				spawn = value as Transform3D
	bus.global_transform = spawn


func _spawn_camera() -> void:
	var script: Script = _safe_script(CAMERA_SCRIPT)
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	if script != null:
		camera_rig.set_script(script)
	add_child(camera_rig)
	if bus != null:
		camera_rig.set("target_path", camera_rig.get_path_to(bus))
		camera_rig.set("target", bus)


func _spawn_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "HUDLayer"
	add_child(layer)

	var scene: PackedScene = _safe_scene(HUD_SCENE)
	var node: Node = null
	if scene != null:
		node = scene.instantiate()
	if node == null:
		var script: Script = _safe_script("res://scripts/ui_manager.gd")
		var control: Control = Control.new()
		if script != null:
			control.set_script(script)
		node = control
	if not (node is Control):
		return
	hud = node as Control
	hud.name = "HUD"
	hud.visible = false
	layer.add_child(hud)

	if bus != null:
		hud.set("bus", bus)
	if camera_rig != null:
		hud.set("camera_system", camera_rig)


func _spawn_reflection_probe() -> void:
	if bus == null:
		return
	var enabled: bool = false
	if Settings != null:
		enabled = Settings.reflections_enabled
	if not enabled:
		return

	var probe: ReflectionProbe = ReflectionProbe.new()
	probe.name = "BusReflectionProbe"
	probe.size = Vector3(46.0, 26.0, 46.0)
	probe.intensity = 1.0
	probe.max_distance = 160.0
	# UPDATE_ALWAYS re-renders every frame and is far too costly on mobile.
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.interior = false
	probe.enable_shadows = false
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	add_child(probe)
	_probe = probe
	probe.global_position = bus.global_position + Vector3(0.0, 6.0, 0.0)


func _physics_process(delta: float) -> void:
	# Move the probe with the bus, but only every ~1.5 s and only after a real
	# displacement, so the (expensive) re-bake does not run every frame.
	if _probe == null or not is_instance_valid(_probe):
		return
	if bus == null or not is_instance_valid(bus):
		return
	_probe_accum += delta
	if _probe_accum < 1.5:
		return
	_probe_accum = 0.0
	var target: Vector3 = bus.global_position + Vector3(0.0, 6.0, 0.0)
	if _probe.global_position.distance_to(target) < 12.0:
		return
	_probe.global_position = target


func _apply_renderer_safe_graphics() -> void:
	## Some post-processing effects are NOT supported outside the Forward+
	## renderer. Leaving them on for the Mobile / Compatibility renderers makes
	## phone GPUs sample undefined buffers, which shows up as heavy static
	## crawling over every 3D surface (the sky stays clean because it has no
	## depth). Godot docs, renderer feature comparison:
	##   Volumetric Fog  - Mobile: NO,  Compatibility: NO
	##   SSR             - Mobile: NO,  Compatibility: NO
	##   SSIL            - Mobile: NO,  Compatibility: NO
	##   SSAO            - Mobile: NO,  Compatibility: yes
	if world == null or not is_instance_valid(world):
		return

	var method: String = str(
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")
	)
	if OS.has_feature("mobile") or OS.has_feature("web"):
		method = str(
			ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", method)
		)
	var is_forward_plus: bool = method == "forward_plus"
	if is_forward_plus:
		return

	var env_node: Node = world.find_child("WorldEnvironment", true, false)
	if env_node == null or not (env_node is WorldEnvironment):
		return
	var env: Environment = (env_node as WorldEnvironment).environment
	if env == null:
		return

	env.ssr_enabled = false
	env.ssil_enabled = false
	env.volumetric_fog_enabled = false
	if method != "gl_compatibility":
		env.ssao_enabled = false

	# Depth fog works on every renderer: use it to keep the sense of distance.
	# Height fog stays OFF: fog_height_density increases fog as height
	# DECREASES, so at street level it turns the whole view white.
	env.fog_enabled = true
	env.fog_height_density = 0.0
	env.fog_sky_affect = 0.0

	# The Mobile renderer only supports a low dynamic range (~2.0), so a high
	# tonemap white point plus bloom washes the image out to a white haze.
	env.tonemap_white = minf(env.tonemap_white, 2.0)
	env.glow_bloom = 0.0

	# Tighter shadow range = better depth precision = no shadow acne shimmer.
	var sun: Node = world.find_child("Sun", true, false)
	if sun != null and sun is DirectionalLight3D:
		var light: DirectionalLight3D = sun as DirectionalLight3D
		light.directional_shadow_max_distance = 120.0
		light.shadow_bias = 0.06
		light.shadow_normal_bias = 2.0
		light.light_angular_distance = 0.0

	if _probe != null and is_instance_valid(_probe):
		_probe.intensity = 0.7

	print("Graphics: renderer=" + method + " -> disabled Forward+ only effects")


func _safe_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is PackedScene:
		return res as PackedScene
	return null


func _safe_script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is Script:
		return res as Script
	return null
