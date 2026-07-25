class_name TrafficAI
extends Node3D

@export var route_radius: float = 44.0
@export var speed: float = 8.0
var phase: float = 0.0

func _ready() -> void:
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.8, 0.7, 3.8)
	body.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12 + fmod(route_radius, 3.0) * 0.12, 0.22, 0.48, 1)
	material.metallic = 0.55
	material.roughness = 0.28
	body.material_override = material
	body.position.y = 0.6
	add_child(body)

func _process(delta: float) -> void:
	phase += delta * speed / route_radius
	global_position = Vector3(cos(phase) * route_radius, 0.7, sin(phase) * route_radius)
	rotation.y = -phase - PI * 0.5
