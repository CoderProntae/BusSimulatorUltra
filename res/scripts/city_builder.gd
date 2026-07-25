class_name CityBuilder
extends Node3D

var building_shader: Shader

func _ready() -> void:
	building_shader = load("res://shaders/window_grid.gdshader")
	_make_roads()
	_make_blocks()
	_make_street_furniture()

func _material(color: Color, roughness := 0.75) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _cube(pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	add_child(node)
	return node

func _make_roads() -> void:
	var road_material := _material(Color("25292d"), 0.9)
	_cube(Vector3(0, -0.12, 0), Vector3(120, 0.2, 14), road_material)
	_cube(Vector3(0, -0.11, 0), Vector3(14, 0.2, 120), road_material)
	var stripe := _material(Color("f4ebcd"), 0.35)
	for x in range(-52, 53, 8):
		_cube(Vector3(x, 0.01, 0), Vector3(4, 0.03, 0.24), stripe)
	for z in range(-52, 53, 8):
		_cube(Vector3(0, 0.01, z), Vector3(0.24, 0.03, 4), stripe)
	var curb := _material(Color("9c9b92"), 0.82)
	for side in [-1.0, 1.0]:
		_cube(Vector3(0, 0.22, side * 7.2), Vector3(120, 0.38, 0.5), curb)
		_cube(Vector3(side * 7.2, 0.22, 0), Vector3(0.5, 0.38, 120), curb)

func _make_blocks() -> void:
	var positions := [Vector3(-25, 0, -25), Vector3(25, 0, -25), Vector3(-25, 0, 25), Vector3(25, 0, 25), Vector3(-45, 0, 30), Vector3(43, 0, -34)]
	for index in positions.size():
		var base := positions[index]
		var height := 10.0 + float((index * 7) % 30)
		var shader_material := ShaderMaterial.new()
		shader_material.shader = building_shader
		_cube(base + Vector3(0, height * 0.5, 0), Vector3(12 + (index % 2) * 5, height, 12), shader_material)
		_cube(base + Vector3(0, height + 1.0, 0), Vector3(4, 2, 4), _material(Color("424950"), 0.65))

func _make_street_furniture() -> void:
	for point in [Vector3(-20, 0, 9), Vector3(20, 0, 9), Vector3(-20, 0, -9), Vector3(20, 0, -9), Vector3(9, 0, 32), Vector3(-9, 0, -32)]:
		_make_lamp(point)
	for point in [Vector3(-15, 0, 13), Vector3(15, 0, -13), Vector3(-35, 0, 10), Vector3(35, 0, -10)]:
		_make_tree(point)
	_make_station(Vector3(-32, 0, 10))

func _make_lamp(pos: Vector3) -> void:
	_cube(pos + Vector3(0, 3, 0), Vector3(0.16, 6, 0.16), _material(Color("333940"), 0.4))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.64, 0.32)
	light.light_energy = 3.0
	light.omni_range = 13.0
	light.position = pos + Vector3(0, 5.8, 0)
	light.add_to_group("street_lamp")
	add_child(light)
	_cube(pos + Vector3(0, 5.8, 0), Vector3(0.45, 0.22, 0.45), _material(Color("ffe2a4"), 0.2))

func _make_tree(pos: Vector3) -> void:
	_cube(pos + Vector3(0, 1.5, 0), Vector3(0.5, 3, 0.5), _material(Color("4f3420"), 0.9))
	var leaves := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2.0
	sphere.height = 4.0
	leaves.mesh = sphere
	leaves.material_override = _material(Color("28523b"), 0.85)
	leaves.position = pos + Vector3(0, 4.2, 0)
	add_child(leaves)

func _make_station(pos: Vector3) -> void:
	var white := _material(Color("e8e7dd"), 0.55)
	_cube(pos + Vector3(0, 3.8, 0), Vector3(12, 0.45, 6), white)
	for x in [-5.0, 5.0]:
		_cube(pos + Vector3(x, 1.9, 0), Vector3(0.45, 3.8, 0.45), white)
	for x in [-2.0, 2.0]:
		_cube(pos + Vector3(x, 0.8, 1.0), Vector3(0.8, 1.6, 0.75), _material(Color("c9252d"), 0.35))
	_cube(pos + Vector3(0, 2.4, -2.8), Vector3(2.4, 1.1, 0.1), _material(Color("45ff8a"), 0.2))
