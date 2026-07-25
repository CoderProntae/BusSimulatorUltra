class_name CameraSystem
extends Node

var bus: Node3D
var camera: Camera3D
var mode: int = 0

func _ready() -> void:
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true

func cycle() -> void:
	mode = (mode + 1) % 3

func _process(delta: float) -> void:
	if bus == null or camera == null:
		return
	var desired := Vector3.ZERO
	if mode == 0:
		desired = bus.global_position + bus.global_transform.basis * Vector3(0, 4.0, 10.5)
		camera.global_position = camera.global_position.lerp(desired, minf(delta * 5.0, 1.0))
		camera.look_at(bus.global_position + Vector3(0, 1.7, 0), Vector3.UP)
	elif mode == 1:
		camera.global_transform = bus.global_transform
		camera.position = Vector3(-0.65, 2.1, -1.7)
		camera.rotation_degrees = Vector3(-4, 180, 0)
	else:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 45.0
		camera.global_position = bus.global_position + Vector3(0, 35, 0.1)
		camera.look_at(bus.global_position, Vector3.FORWARD)
	if mode != 2:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
