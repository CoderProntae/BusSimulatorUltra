extends SceneTree

## HEADLESS PHYSICS TEST - runs in CI with the real engine.
##
## Static analysis cannot tell you whether the bus actually MOVES. This does:
## it spawns the real bus on a real floor, holds the throttle, and fails the
## build if the speedometer stays at zero.
##
## This exists because the bus shipped reading 0 km/h with the throttle held.
## The suspension could only carry 49% of its weight and the collision box sat
## below the tyre contact patch, so the hull rested on the tarmac and the
## wheels had no load. Every static check passed; only running it would have
## caught the problem.
##
## Physics is driven by the engine's own loop via _physics_process(); do not
## try to step the space by hand.
##
## Usage:  godot --headless --path res --script ../tools/physics_smoke.gd

const BUS_SCRIPT: String = "res://scripts/bus_controller.gd"
## 60 physics ticks per second.
const SETTLE_STEPS: int = 90
const DRIVE_STEPS: int = 150
const DOOR_STEPS: int = 120

var _bus: VehicleBody3D = null
var _step: int = 0
var _phase: int = 0
var _failures: Array[String] = []
var _drive_speed: float = 0.0
var _start_pos: Vector3 = Vector3.ZERO


func _init() -> void:
	print("=== headless physics smoke test ===")
	var world: Node3D = Node3D.new()
	root.add_child(world)
	_build_floor(world)
	_bus = _build_bus(world)
	if _bus == null:
		_finish()


func _physics_process(_delta: float) -> bool:
	if _bus == null or not is_instance_valid(_bus):
		return true
	_step += 1

	if _phase == 0:
		# Let the bus settle onto its springs.
		if _step >= SETTLE_STEPS:
			_after_settle()
			_phase = 1
			_step = 0
		return false

	if _phase == 1:
		if _step >= DRIVE_STEPS:
			_after_drive()
			_phase = 2
			_step = 0
		return false

	if _step >= DOOR_STEPS:
		_after_doors()
		_finish()
		return true
	return false


func _after_settle() -> void:
	var settled_y: float = _bus.global_position.y
	print("settled y=" + str(snappedf(settled_y, 0.001)))
	_check_wheels_on_ground()

	# The floor top is at y = 0. A bus resting on its wheels keeps its origin
	# well above that; one that has sunk through drops toward or below it.
	if settled_y < 0.4:
		_fail("bus origin settled to y=" + str(snappedf(settled_y, 0.001))
			+ "; the body has sunk into the road")
	else:
		print("OK   bus rides at y=" + str(snappedf(settled_y, 0.001)))

	# Doors must be shut or the interlock (correctly) blocks the throttle.
	_start_pos = _bus.global_position
	_bus.set("doors_open", false)
	_bus.set("throttle_input", 1.0)
	_bus.set("brake_input", 0.0)


func _after_drive() -> void:
	_drive_speed = float(_bus.get("speed_kmh"))
	var here: Vector3 = _bus.global_position
	var travelled: float = Vector2(here.x, here.z).distance_to(
		Vector2(_start_pos.x, _start_pos.z))
	print("after " + str(DRIVE_STEPS) + " ticks: speed="
		+ str(snappedf(_drive_speed, 0.01)) + " km/h  travelled="
		+ str(snappedf(travelled, 0.01)) + " m")

	if _drive_speed < 5.0:
		_fail("bus reached only " + str(snappedf(_drive_speed, 0.01))
			+ " km/h with the throttle held; expected >5")
	else:
		print("OK   bus accelerates: " + str(snappedf(_drive_speed, 0.01)) + " km/h")

	if travelled < 1.0:
		_fail("bus moved only " + str(snappedf(travelled, 0.01)) + " m")
	else:
		print("OK   bus travelled " + str(snappedf(travelled, 0.01)) + " m")

	# The door interlock must still stop it.
	_bus.set("doors_open", true)


func _after_doors() -> void:
	var door_speed: float = float(_bus.get("speed_kmh"))
	print("with doors open: " + str(snappedf(door_speed, 0.01)) + " km/h")
	if door_speed > _drive_speed:
		_fail("opening the doors did not slow the bus")
	else:
		print("OK   door interlock still brakes the bus")


func _build_floor(world: Node3D) -> void:
	var floor_body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(900.0, 2.0, 900.0)
	shape.shape = box
	floor_body.add_child(shape)
	world.add_child(floor_body)
	floor_body.global_position = Vector3(0.0, -1.0, 0.0)


func _build_bus(world: Node3D) -> VehicleBody3D:
	if not ResourceLoader.exists(BUS_SCRIPT):
		_fail("cannot load " + BUS_SCRIPT)
		return null
	var script: Resource = load(BUS_SCRIPT)
	if not (script is Script):
		_fail(BUS_SCRIPT + " is not a Script")
		return null
	var bus: VehicleBody3D = VehicleBody3D.new()
	bus.set_script(script)
	world.add_child(bus)
	bus.global_position = Vector3(0.0, 1.6, 0.0)
	return bus


func _check_wheels_on_ground() -> void:
	var total: int = 0
	var grounded: int = 0
	var children: Array = _bus.get_children()
	var i: int = 0
	while i < children.size():
		var child: Node = children[i]
		i += 1
		if not (child is VehicleWheel3D):
			continue
		total += 1
		if (child as VehicleWheel3D).is_in_contact():
			grounded += 1
	print("wheels touching the road: " + str(grounded) + "/" + str(total))
	if total == 0:
		_fail("the bus has no VehicleWheel3D children")
		return
	if grounded < total:
		_fail(str(total - grounded) + " of " + str(total)
			+ " wheels are off the ground; the hull is carrying the bus")
	else:
		print("OK   every wheel is loaded")


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("PHYSICS FAIL: " + message)


func _finish() -> void:
	print("===================================")
	if _failures.is_empty():
		print("PHYSICS SMOKE TEST PASSED")
		quit(0)
		return
	printerr("PHYSICS SMOKE TEST FAILED (" + str(_failures.size()) + ")")
	quit(1)
