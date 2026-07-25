extends Node3D

## Boot script: instantiates the world, spawns the bus at a road spawn point,
## wires the camera + HUD together and keeps a ReflectionProbe near the bus
## for crisp metal and glass reflections.

const WORLD_SCENE: String = "res://scenes/World.tscn"
const BUS_SCENE: String = "res://scenes/Bus.tscn"
const HUD_SCENE: String = "res://scenes/HUD.tscn"
const CAMERA_SCRIPT: String = "res://scripts/camera_system.gd"
const CITY_SCRIPT_NAME: String = "CityBuilder"

var world: Node3D = null
var bus: VehicleBody3D = null
var camera_rig: Node3D = null
var hud: Control = null
var _probe: ReflectionProbe = null


func _ready() -> void:
	randomize()
	_spawn_world()
	_spawn_bus()
	_spawn_camera()
	_spawn_hud()
	_spawn_reflection_probe()

	if GameState != null:
		GameState.reset()
		GameState.notify("Welcome! Drive to a stop, open the doors, collect fares.")


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
	layer.add_child(hud)

	if bus != null:
		hud.set("bus", bus)
	if camera_rig != null:
		hud.set("camera_system", camera_rig)


func _spawn_reflection_probe() -> void:
	if bus == null:
		return
	var probe: ReflectionProbe = ReflectionProbe.new()
	probe.name = "BusReflectionProbe"
	probe.size = Vector3(46.0, 26.0, 46.0)
	probe.origin_offset = Vector3(0.0, 0.0, 0.0)
	probe.intensity = 1.0
	probe.max_distance = 160.0
	probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	probe.interior = false
	probe.enable_shadows = false
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	add_child(probe)
	_probe = probe
	probe.global_position = bus.global_position + Vector3(0.0, 6.0, 0.0)


func _physics_process(_delta: float) -> void:
	if _probe != null and is_instance_valid(_probe) and bus != null and is_instance_valid(bus):
		_probe.global_position = bus.global_position + Vector3(0.0, 6.0, 0.0)


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
