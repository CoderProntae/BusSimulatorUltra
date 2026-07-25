extends Node3D

## Procedurally builds the whole city: ground, asphalt road grid with lane
## lines, raised curbs, zebra crosswalks, shader-textured buildings, street
## lamps, trees, traffic lights, bus stops, traffic cars and the fuel station.
##
## All external resources are loaded through _safe_load(), so a missing
## texture never crashes the game.

const ASPHALT_PATH: String = "res://materials/asphalt.tres"
const CONCRETE_PATH: String = "res://materials/concrete.tres"
const WALL_PATH: String = "res://materials/wall.tres"
const WINDOW_SHADER_PATH: String = "res://shaders/window_grid.gdshader"
const BUS_STOP_SCENE: String = "res://scenes/BusStop.tscn"
const TRAFFIC_SCENE: String = "res://scenes/TrafficCar.tscn"
const LAMP_SCRIPT_PATH: String = "res://scripts/street_lamp.gd"

const BLOCK_SIZE: float = 60.0
const ROAD_WIDTH: float = 14.0
const GRID: int = 4
const LAMP_SPACING: float = 20.0

@export var build_on_ready: bool = true
@export var traffic_count: int = 5

var _asphalt: Material = null
var _concrete: Material = null
var _wall: Material = null
var _window_shader: Shader = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _road_positions_x: Array[float] = []
var _road_positions_z: Array[float] = []
var _city_extent: float = 0.0
var _stop_index: int = 0

const STOP_NAMES: Array[String] = [
	"Central Station",
	"Market Square",
	"Riverside",
	"University",
	"Old Town",
	"Airport Road",
	"Harbour Gate",
	"Green Park",
]


func _ready() -> void:
	_rng.seed = 20260725
	if build_on_ready:
		build_city()


func build_city() -> void:
	_asphalt = _safe_load_material(ASPHALT_PATH, Color(0.32, 0.33, 0.35))
	_concrete = _safe_load_material(CONCRETE_PATH, Color(0.72, 0.71, 0.68))
	_wall = _safe_load_material(WALL_PATH, Color(0.70, 0.45, 0.36))
	_window_shader = _safe_load_shader(WINDOW_SHADER_PATH)

	_compute_grid()
	_build_ground()
	_build_roads()
	_build_curbs()
	_build_crosswalks()
	_build_blocks()
	_build_street_lamps()
	_build_traffic_lights()
	_build_bus_stops()
	_build_fuel_station()
	_build_traffic()


func _compute_grid() -> void:
	_road_positions_x.clear()
	_road_positions_z.clear()
	var half: float = float(GRID - 1) * 0.5
	var i: int = 0
	while i < GRID:
		var offset: float = (float(i) - half) * BLOCK_SIZE
		_road_positions_x.append(offset)
		_road_positions_z.append(offset)
		i += 1
	_city_extent = (float(GRID - 1) * BLOCK_SIZE) * 0.5 + BLOCK_SIZE * 0.5


# ---------------------------------------------------------------------------
# Ground + roads
# ---------------------------------------------------------------------------

func _build_ground() -> void:
	var ground: StaticBody3D = StaticBody3D.new()
	ground.name = "Ground"
	add_child(ground)

	var size: float = _city_extent * 2.6

	var mesh_node: MeshInstance3D = MeshInstance3D.new()
	mesh_node.name = "GroundMesh"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	mesh_node.mesh = plane

	var grass_mat: StandardMaterial3D = StandardMaterial3D.new()
	grass_mat.albedo_color = Color(0.24, 0.32, 0.19)
	grass_mat.roughness = 0.95
	if _concrete is StandardMaterial3D:
		var base: StandardMaterial3D = (_concrete as StandardMaterial3D).duplicate() as StandardMaterial3D
		base.albedo_color = Color(0.34, 0.40, 0.28)
		base.uv1_scale = Vector3(60.0, 60.0, 60.0)
		mesh_node.set_surface_override_material(0, base)
	else:
		mesh_node.set_surface_override_material(0, grass_mat)

	mesh_node.position = Vector3(0.0, -0.06, 0.0)
	ground.add_child(mesh_node)

	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(size, 1.0, size)
	shape.shape = box
	shape.position = Vector3(0.0, -0.56, 0.0)
	ground.add_child(shape)


func _build_roads() -> void:
	var roads: StaticBody3D = StaticBody3D.new()
	roads.name = "Roads"
	add_child(roads)

	var length: float = _city_extent * 2.0

	var i: int = 0
	while i < _road_positions_x.size():
		_add_road_strip(roads, Vector3(_road_positions_x[i], 0.02, 0.0), Vector3(ROAD_WIDTH, 0.12, length), "RoadNS" + str(i))
		i += 1

	i = 0
	while i < _road_positions_z.size():
		_add_road_strip(roads, Vector3(0.0, 0.02, _road_positions_z[i]), Vector3(length, 0.12, ROAD_WIDTH), "RoadEW" + str(i))
		i += 1

	_build_lane_lines()


func _add_road_strip(parent: Node3D, pos: Vector3, size: Vector3, node_name: String) -> void:
	var mesh_node: MeshInstance3D = MeshInstance3D.new()
	mesh_node.name = node_name
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = size
	mesh_node.mesh = box_mesh
	mesh_node.position = pos
	if _asphalt != null:
		mesh_node.set_surface_override_material(0, _asphalt)
	parent.add_child(mesh_node)

	var body_shape: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	body_shape.shape = shape
	body_shape.position = pos
	parent.add_child(body_shape)


func _build_lane_lines() -> void:
	var lines: Node3D = Node3D.new()
	lines.name = "LaneLines"
	add_child(lines)

	var line_mat: StandardMaterial3D = StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.95, 0.95, 0.92)
	line_mat.roughness = 0.6
	line_mat.metallic = 0.0

	var dash_length: float = 3.0
	var gap: float = 3.0
	var step: float = dash_length + gap
	var extent: float = _city_extent

	var i: int = 0
	while i < _road_positions_x.size():
		var x: float = _road_positions_x[i]
		var z: float = -extent
		while z < extent:
			if not _near_intersection(z, _road_positions_z):
				_add_dash(lines, Vector3(x, 0.09, z), Vector3(0.22, 0.02, dash_length))
			z += step
		i += 1

	i = 0
	while i < _road_positions_z.size():
		var z_line: float = _road_positions_z[i]
		var x_pos: float = -extent
		while x_pos < extent:
			if not _near_intersection(x_pos, _road_positions_x):
				_add_dash(lines, Vector3(x_pos, 0.09, z_line), Vector3(dash_length, 0.02, 0.22))
			x_pos += step
		i += 1

	_apply_material_recursive(lines, line_mat)


func _add_dash(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var dash: MeshInstance3D = MeshInstance3D.new()
	dash.name = "Dash"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	dash.mesh = mesh
	dash.position = pos
	dash.visibility_range_end = 130.0
	dash.visibility_range_end_margin = 15.0
	dash.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(dash)


func _near_intersection(value: float, positions: Array[float]) -> bool:
	var i: int = 0
	while i < positions.size():
		if absf(value - positions[i]) < ROAD_WIDTH * 0.75:
			return true
		i += 1
	return false


func _apply_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).set_surface_override_material(0, mat)
	var children: Array = node.get_children()
	var i: int = 0
	while i < children.size():
		_apply_material_recursive(children[i], mat)
		i += 1


func _build_curbs() -> void:
	var curbs: StaticBody3D = StaticBody3D.new()
	curbs.name = "Curbs"
	add_child(curbs)

	var curb_mat: Material = _concrete
	if curb_mat == null:
		var fallback: StandardMaterial3D = StandardMaterial3D.new()
		fallback.albedo_color = Color(0.78, 0.77, 0.74)
		curb_mat = fallback

	var half: float = float(GRID - 1) * 0.5
	var bx: int = 0
	while bx < GRID - 1:
		var bz: int = 0
		while bz < GRID - 1:
			var cx: float = (float(bx) - half + 0.5) * BLOCK_SIZE
			var cz: float = (float(bz) - half + 0.5) * BLOCK_SIZE
			var pad: float = BLOCK_SIZE - ROAD_WIDTH

			var sidewalk: MeshInstance3D = MeshInstance3D.new()
			sidewalk.name = "Sidewalk_" + str(bx) + "_" + str(bz)
			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = Vector3(pad, 0.28, pad)
			sidewalk.mesh = mesh
			sidewalk.position = Vector3(cx, 0.14, cz)
			sidewalk.set_surface_override_material(0, curb_mat)
			curbs.add_child(sidewalk)

			var shape: CollisionShape3D = CollisionShape3D.new()
			var box: BoxShape3D = BoxShape3D.new()
			box.size = Vector3(pad, 0.28, pad)
			shape.shape = box
			shape.position = Vector3(cx, 0.14, cz)
			curbs.add_child(shape)
			bz += 1
		bx += 1


func _build_crosswalks() -> void:
	var zebras: Node3D = Node3D.new()
	zebras.name = "Crosswalks"
	add_child(zebras)

	var stripe_mat: StandardMaterial3D = StandardMaterial3D.new()
	stripe_mat.albedo_color = Color(0.94, 0.94, 0.92)
	stripe_mat.roughness = 0.65

	var i: int = 0
	while i < _road_positions_x.size():
		var j: int = 0
		while j < _road_positions_z.size():
			var x: float = _road_positions_x[i]
			var z: float = _road_positions_z[j]
			_add_zebra(zebras, Vector3(x, 0.1, z - ROAD_WIDTH * 0.62), true, stripe_mat)
			_add_zebra(zebras, Vector3(x, 0.1, z + ROAD_WIDTH * 0.62), true, stripe_mat)
			_add_zebra(zebras, Vector3(x - ROAD_WIDTH * 0.62, 0.1, z), false, stripe_mat)
			_add_zebra(zebras, Vector3(x + ROAD_WIDTH * 0.62, 0.1, z), false, stripe_mat)
			j += 1
		i += 1


func _add_zebra(parent: Node3D, center: Vector3, horizontal: bool, mat: Material) -> void:
	var stripes: int = 7
	var span: float = ROAD_WIDTH * 0.86
	var stripe_w: float = span / float(stripes * 2 - 1)

	var s: int = 0
	while s < stripes:
		var offset: float = -span * 0.5 + float(s) * stripe_w * 2.0 + stripe_w * 0.5
		var stripe: MeshInstance3D = MeshInstance3D.new()
		stripe.name = "Zebra" + str(s)
		var mesh: BoxMesh = BoxMesh.new()
		if horizontal:
			mesh.size = Vector3(stripe_w, 0.02, 2.6)
			stripe.position = center + Vector3(offset, 0.0, 0.0)
		else:
			mesh.size = Vector3(2.6, 0.02, stripe_w)
			stripe.position = center + Vector3(0.0, 0.0, offset)
		stripe.mesh = mesh
		stripe.set_surface_override_material(0, mat)
		stripe.visibility_range_end = 120.0
		stripe.visibility_range_end_margin = 15.0
		stripe.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		parent.add_child(stripe)
		s += 1


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------

func _build_blocks() -> void:
	var blocks: StaticBody3D = StaticBody3D.new()
	blocks.name = "Buildings"
	add_child(blocks)

	var half: float = float(GRID - 1) * 0.5
	var bx: int = 0
	while bx < GRID - 1:
		var bz: int = 0
		while bz < GRID - 1:
			var cx: float = (float(bx) - half + 0.5) * BLOCK_SIZE
			var cz: float = (float(bz) - half + 0.5) * BLOCK_SIZE
			_build_block_buildings(blocks, cx, cz, bx, bz)
			_build_block_props(cx, cz, bx, bz)
			bz += 1
		bx += 1


func _build_block_buildings(parent: Node3D, cx: float, cz: float, bx: int, bz: int) -> void:
	var inner: float = BLOCK_SIZE - ROAD_WIDTH - 8.0
	var count: int = _rng.randi_range(2, 4)

	var i: int = 0
	while i < count:
		var w: float = _rng.randf_range(12.0, 20.0)
		var d: float = _rng.randf_range(12.0, 20.0)
		var h: float = _rng.randf_range(8.0, 40.0)

		var ox: float = _rng.randf_range(-inner * 0.3, inner * 0.3)
		var oz: float = _rng.randf_range(-inner * 0.3, inner * 0.3)
		var pos: Vector3 = Vector3(cx + ox, h * 0.5, cz + oz)

		var building: MeshInstance3D = MeshInstance3D.new()
		building.name = "Building_" + str(bx) + "_" + str(bz) + "_" + str(i)
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(w, h, d)
		building.mesh = mesh
		building.position = pos
		building.add_to_group("building_facade")

		var mat: Material = _make_facade_material(w, h, i + bx * 7 + bz * 13)
		building.set_surface_override_material(0, mat)
		# Cull distant buildings: the single biggest mobile draw-call saving.
		building.visibility_range_end = 320.0
		building.visibility_range_end_margin = 30.0
		building.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		parent.add_child(building)

		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(w, h, d)
		shape.shape = box
		shape.position = pos
		parent.add_child(shape)

		_build_rooftop(parent, pos, w, d, h)
		i += 1


func _make_facade_material(width: float, height: float, seed_index: int) -> Material:
	if _window_shader != null:
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = _window_shader

		var cols: float = maxf(2.0, round(width / 3.2))
		var rows: float = maxf(2.0, round(height / 3.4))
		mat.set_shader_parameter("windows", Vector2(cols, rows))
		mat.set_shader_parameter("seed", float(seed_index) * 3.77 + 1.0)
		mat.set_shader_parameter("lit_ratio", _rng.randf_range(0.35, 0.7))
		mat.set_shader_parameter("night", 0.0)
		mat.set_shader_parameter("grime", _rng.randf_range(0.2, 0.55))

		var tint: float = _rng.randf_range(0.42, 0.62)
		mat.set_shader_parameter("wall_color", Color(tint, tint * 0.98, tint * 0.94))
		mat.set_shader_parameter("wall_color_b", Color(tint * 0.78, tint * 0.77, tint * 0.75))

		# Blend in the downloaded brick/concrete texture when it exists.
		if _wall is StandardMaterial3D:
			var wall_mat: StandardMaterial3D = _wall as StandardMaterial3D
			if wall_mat.albedo_texture != null:
				mat.set_shader_parameter("wall_texture", wall_mat.albedo_texture)
				mat.set_shader_parameter("wall_texture_mix", _rng.randf_range(0.25, 0.6))
				mat.set_shader_parameter("wall_uv_scale", Vector3(cols * 0.5, rows * 0.5, 1.0))
		return mat

	# Fallback: still textured, never a flat color.
	if _wall != null:
		return _wall
	var plain: StandardMaterial3D = StandardMaterial3D.new()
	plain.albedo_color = Color(0.55, 0.54, 0.52)
	plain.roughness = 0.85
	return plain


func _build_rooftop(parent: Node3D, base_pos: Vector3, w: float, d: float, h: float) -> void:
	var roof_mat: StandardMaterial3D = StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.30, 0.30, 0.32)
	roof_mat.roughness = 0.9

	var boxes: int = _rng.randi_range(1, 3)
	var i: int = 0
	while i < boxes:
		var bw: float = _rng.randf_range(2.0, maxf(2.5, w * 0.35))
		var bd: float = _rng.randf_range(2.0, maxf(2.5, d * 0.35))
		var bh: float = _rng.randf_range(1.0, 3.0)
		var ox: float = _rng.randf_range(-w * 0.25, w * 0.25)
		var oz: float = _rng.randf_range(-d * 0.25, d * 0.25)

		var box_node: MeshInstance3D = MeshInstance3D.new()
		box_node.name = "Rooftop" + str(i)
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(bw, bh, bd)
		box_node.mesh = mesh
		box_node.position = Vector3(base_pos.x + ox, h + bh * 0.5, base_pos.z + oz)
		box_node.set_surface_override_material(0, roof_mat)
		box_node.visibility_range_end = 180.0
		box_node.visibility_range_end_margin = 20.0
		box_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		parent.add_child(box_node)
		i += 1

	# roof parapet
	var parapet: MeshInstance3D = MeshInstance3D.new()
	parapet.name = "Parapet"
	var parapet_mesh: BoxMesh = BoxMesh.new()
	parapet_mesh.size = Vector3(w + 0.4, 0.7, d + 0.4)
	parapet.mesh = parapet_mesh
	parapet.position = Vector3(base_pos.x, h + 0.35, base_pos.z)
	parapet.set_surface_override_material(0, roof_mat)
	parent.add_child(parapet)


func _build_block_props(cx: float, cz: float, bx: int, bz: int) -> void:
	var trees: int = _rng.randi_range(2, 5)
	var edge: float = (BLOCK_SIZE - ROAD_WIDTH) * 0.5 - 1.6
	var i: int = 0
	while i < trees:
		var side: int = _rng.randi_range(0, 3)
		var along: float = _rng.randf_range(-edge * 0.8, edge * 0.8)
		var pos: Vector3 = Vector3(cx, 0.28, cz)
		if side == 0:
			pos += Vector3(along, 0.0, -edge)
		elif side == 1:
			pos += Vector3(along, 0.0, edge)
		elif side == 2:
			pos += Vector3(-edge, 0.0, along)
		else:
			pos += Vector3(edge, 0.0, along)
		_add_tree(pos, "Tree_" + str(bx) + "_" + str(bz) + "_" + str(i))
		i += 1


func _add_tree(pos: Vector3, node_name: String) -> void:
	var tree: Node3D = Node3D.new()
	tree.name = node_name
	tree.position = pos
	add_child(tree)

	var trunk_mat: StandardMaterial3D = StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.30, 0.21, 0.13)
	trunk_mat.roughness = 0.95

	var leaf_mat: StandardMaterial3D = StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.16, 0.36, 0.14)
	leaf_mat.roughness = 0.9

	var height: float = _rng.randf_range(3.2, 5.6)

	var trunk: MeshInstance3D = MeshInstance3D.new()
	trunk.name = "Trunk"
	var trunk_mesh: CylinderMesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.24
	trunk_mesh.height = height
	trunk_mesh.radial_segments = 8
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0.0, height * 0.5, 0.0)
	trunk.set_surface_override_material(0, trunk_mat)
	tree.add_child(trunk)

	var clusters: int = _rng.randi_range(2, 3)
	var c: int = 0
	while c < clusters:
		var foliage: MeshInstance3D = MeshInstance3D.new()
		foliage.name = "Foliage" + str(c)
		var sphere: SphereMesh = SphereMesh.new()
		var radius: float = _rng.randf_range(1.2, 2.0)
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = 10
		sphere.rings = 6
		foliage.mesh = sphere
		foliage.position = Vector3(
			_rng.randf_range(-0.6, 0.6),
			height + _rng.randf_range(-0.3, 0.9),
			_rng.randf_range(-0.6, 0.6)
		)
		foliage.set_surface_override_material(0, leaf_mat)
		foliage.visibility_range_end = 150.0
		foliage.visibility_range_end_margin = 20.0
		foliage.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		tree.add_child(foliage)
		c += 1


# ---------------------------------------------------------------------------
# Street furniture
# ---------------------------------------------------------------------------

func _build_street_lamps() -> void:
	var lamps: Node3D = Node3D.new()
	lamps.name = "StreetLamps"
	add_child(lamps)

	# Skip street lamps entirely on the low preset.
	if Settings != null:
		if not Settings.street_lamps_enabled:
			return

	var extent: float = _city_extent - 4.0
	var i: int = 0
	while i < _road_positions_x.size():
		var x: float = _road_positions_x[i]
		var z: float = -extent
		while z <= extent:
			if not _near_intersection(z, _road_positions_z):
				_add_lamp(lamps, Vector3(x + ROAD_WIDTH * 0.5 + 0.9, 0.28, z), -90.0)
			z += LAMP_SPACING
		i += 1

	i = 0
	while i < _road_positions_z.size():
		var z_line: float = _road_positions_z[i]
		var x_pos: float = -extent
		while x_pos <= extent:
			if not _near_intersection(x_pos, _road_positions_x):
				_add_lamp(lamps, Vector3(x_pos, 0.28, z_line + ROAD_WIDTH * 0.5 + 0.9), 0.0)
			x_pos += LAMP_SPACING
		i += 1


func _add_lamp(parent: Node3D, pos: Vector3, y_rotation: float) -> void:
	var lamp: Node3D = Node3D.new()
	lamp.name = "StreetLamp"
	lamp.position = pos
	lamp.rotation_degrees = Vector3(0.0, y_rotation, 0.0)
	var lamp_script: Script = _make_lamp_script()
	if lamp_script != null:
		lamp.set_script(lamp_script)
	lamp.add_to_group("street_lamp")
	parent.add_child(lamp)

	var metal: StandardMaterial3D = StandardMaterial3D.new()
	metal.albedo_color = Color(0.28, 0.29, 0.31)
	metal.metallic = 0.8
	metal.roughness = 0.35

	var pole: MeshInstance3D = MeshInstance3D.new()
	pole.name = "Pole"
	var pole_mesh: CylinderMesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.11
	pole_mesh.bottom_radius = 0.16
	pole_mesh.height = 7.0
	pole_mesh.radial_segments = 10
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, 3.5, 0.0)
	pole.set_surface_override_material(0, metal)
	lamp.add_child(pole)

	var arm: MeshInstance3D = MeshInstance3D.new()
	arm.name = "Arm"
	var arm_mesh: CylinderMesh = CylinderMesh.new()
	arm_mesh.top_radius = 0.08
	arm_mesh.bottom_radius = 0.08
	arm_mesh.height = 1.8
	arm_mesh.radial_segments = 8
	arm.mesh = arm_mesh
	arm.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	arm.position = Vector3(-0.9, 6.9, 0.0)
	arm.set_surface_override_material(0, metal)
	lamp.add_child(arm)

	var bulb_mat: StandardMaterial3D = StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(0.9, 0.88, 0.75)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.85, 0.55)
	bulb_mat.emission_energy_multiplier = 0.0
	bulb_mat.roughness = 0.25

	var bulb: MeshInstance3D = MeshInstance3D.new()
	bulb.name = "Bulb"
	var bulb_mesh: BoxMesh = BoxMesh.new()
	bulb_mesh.size = Vector3(0.75, 0.2, 0.45)
	bulb.mesh = bulb_mesh
	bulb.position = Vector3(-1.7, 6.78, 0.0)
	bulb.set_surface_override_material(0, bulb_mat)
	lamp.add_child(bulb)

	var light: OmniLight3D = OmniLight3D.new()
	light.name = "Light"
	light.distance_fade_enabled = true
	light.distance_fade_begin = 55.0
	light.distance_fade_length = 20.0
	light.position = Vector3(-1.7, 6.5, 0.0)
	light.light_color = Color(1.0, 0.86, 0.62)
	light.light_energy = 0.0
	light.omni_range = 22.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.visible = false
	lamp.add_child(light)


func _make_lamp_script() -> Script:
	# Real script file (never runtime-compiled) so it survives export.
	return _safe_load_script(LAMP_SCRIPT_PATH)


func _build_traffic_lights() -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "TrafficLights"
	add_child(holder)

	var metal: StandardMaterial3D = StandardMaterial3D.new()
	metal.albedo_color = Color(0.18, 0.19, 0.21)
	metal.metallic = 0.7
	metal.roughness = 0.4

	var i: int = 0
	while i < _road_positions_x.size():
		var j: int = 0
		while j < _road_positions_z.size():
			var base: Vector3 = Vector3(
				_road_positions_x[i] + ROAD_WIDTH * 0.55,
				0.28,
				_road_positions_z[j] + ROAD_WIDTH * 0.55
			)
			_add_traffic_light(holder, base, metal, i * 10 + j)
			j += 1
		i += 1


func _add_traffic_light(parent: Node3D, pos: Vector3, metal: Material, index: int) -> void:
	var light_node: Node3D = Node3D.new()
	light_node.name = "TrafficLight" + str(index)
	light_node.position = pos
	parent.add_child(light_node)

	var pole: MeshInstance3D = MeshInstance3D.new()
	pole.name = "Pole"
	var pole_mesh: CylinderMesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.09
	pole_mesh.bottom_radius = 0.12
	pole_mesh.height = 4.4
	pole_mesh.radial_segments = 8
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, 2.2, 0.0)
	pole.set_surface_override_material(0, metal)
	light_node.add_child(pole)

	var housing: MeshInstance3D = MeshInstance3D.new()
	housing.name = "Housing"
	var housing_mesh: BoxMesh = BoxMesh.new()
	housing_mesh.size = Vector3(0.42, 1.15, 0.32)
	housing.mesh = housing_mesh
	housing.position = Vector3(0.0, 4.6, 0.0)
	housing.set_surface_override_material(0, metal)
	light_node.add_child(housing)

	var colors: Array[Color] = [
		Color(1.0, 0.12, 0.08),
		Color(1.0, 0.72, 0.10),
		Color(0.15, 1.0, 0.25),
	]
	var ys: Array[float] = [4.98, 4.6, 4.22]

	var active: int = index % 3
	var c: int = 0
	while c < colors.size():
		var bulb: MeshInstance3D = MeshInstance3D.new()
		bulb.name = "Bulb" + str(c)
		var bulb_mesh: SphereMesh = SphereMesh.new()
		bulb_mesh.radius = 0.13
		bulb_mesh.height = 0.26
		bulb_mesh.radial_segments = 10
		bulb_mesh.rings = 6
		bulb.mesh = bulb_mesh
		bulb.position = Vector3(0.0, ys[c], 0.18)

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = colors[c] * 0.35
		mat.emission_enabled = true
		mat.emission = colors[c]
		var energy: float = 0.15
		if c == active:
			energy = 3.0
		mat.emission_energy_multiplier = energy
		bulb.set_surface_override_material(0, mat)
		light_node.add_child(bulb)
		c += 1


# ---------------------------------------------------------------------------
# Stops, station, traffic
# ---------------------------------------------------------------------------

func _build_bus_stops() -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "BusStops"
	add_child(holder)

	var scene: PackedScene = _safe_load_scene(BUS_STOP_SCENE)

	var spots: Array[Vector3] = []
	var rotations: Array[float] = []

	## Stops must sit ON THE KERB, never in the roadway.
	##  - offset sideways by half the road plus the pavement, so the shelter is
	##    on the pavement and the bus pulls up alongside it
	##  - placed MID-BLOCK (a road line +/- BLOCK_SIZE * 0.5), because a road
	##    coordinate itself is an intersection
	## The shelter is built on the -X side of the stop's local origin, so the
	## origin is put on the road side of the kerb.
	var kerb: float = ROAD_WIDTH * 0.5 + 2.2

	# Stops beside the north-south roads (bus travels along Z).
	var i: int = 0
	while i < _road_positions_x.size():
		var x: float = _road_positions_x[i]
		var j: int = 0
		while j < _road_positions_z.size() - 1:
			var mid_z: float = (_road_positions_z[j] + _road_positions_z[j + 1]) * 0.5
			# Right-hand kerb for a bus driving +Z is -X.
			spots.append(Vector3(x - kerb, 0.0, mid_z))
			rotations.append(180.0)
			j += 1
		i += 1

	# Stops beside the east-west roads (bus travels along X).
	i = 0
	while i < _road_positions_z.size():
		var z: float = _road_positions_z[i]
		var j2: int = 0
		while j2 < _road_positions_x.size() - 1:
			var mid_x: float = (_road_positions_x[j2] + _road_positions_x[j2 + 1]) * 0.5
			spots.append(Vector3(mid_x, 0.0, z + kerb))
			rotations.append(90.0)
			j2 += 1
		i += 1

	var s: int = 0
	while s < spots.size():
		var stop: Node = null
		if scene != null:
			stop = scene.instantiate()
		if stop == null:
			stop = _make_runtime_stop()

		# Set exported properties BEFORE add_child so _ready() sees them.
		if "stop_name" in stop:
			stop.set("stop_name", STOP_NAMES[_stop_index % STOP_NAMES.size()])
			_stop_index += 1
		if stop is Node3D:
			var stop3d: Node3D = stop as Node3D
			stop3d.position = spots[s]
			stop3d.rotation_degrees = Vector3(0.0, rotations[s], 0.0)

		holder.add_child(stop)
		s += 1


func _make_runtime_stop() -> Node:
	var area: Area3D = Area3D.new()
	area.name = "BusStop"
	var script: Script = _safe_load_script("res://scripts/passenger_system.gd")
	if script != null:
		area.set_script(script)
	return area


func _build_fuel_station() -> void:
	var script: Script = _safe_load_script("res://scripts/fuel_system.gd")
	var station: Area3D = Area3D.new()
	station.name = "FuelStation"
	if script != null:
		station.set_script(script)
		station.set("build_visuals", true)
	station.position = Vector3(BLOCK_SIZE * 0.5 + 12.0, 0.0, BLOCK_SIZE * 1.5 - 6.0)
	# build_visuals is already set, so _ready() constructs the canopy/pumps.
	add_child(station)


func _build_traffic() -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "Traffic"
	add_child(holder)

	var scene: PackedScene = _safe_load_scene(TRAFFIC_SCENE)
	var script: Script = _safe_load_script("res://scripts/traffic_ai.gd")

	var loop: PackedVector3Array = _make_traffic_loop()
	if loop.size() < 2:
		return

	# Let the graphics settings decide how much traffic to simulate.
	var count: int = traffic_count
	if Settings != null:
		count = maxi(1, Settings.traffic_count)

	var i: int = 0
	while i < count:
		var car: Node = null
		if scene != null:
			car = scene.instantiate()
		if car == null:
			var body: CharacterBody3D = CharacterBody3D.new()
			if script != null:
				body.set_script(script)
			car = body
		car.name = "TrafficCar" + str(i)

		# Set exported properties BEFORE add_child so _ready() builds the
		# car body with the right paint colour and speed.
		if "body_hue" in car:
			car.set("body_hue", fmod(0.17 * float(i) + 0.03, 1.0))
		if "speed" in car:
			car.set("speed", _rng.randf_range(8.0, 14.0))

		holder.add_child(car)

		var start_index: int = int(float(i) * float(loop.size()) / float(count))
		if car.has_method("setup_route"):
			car.call("setup_route", loop, start_index)
		elif car is Node3D:
			(car as Node3D).position = loop[start_index]
		i += 1


func _make_traffic_loop() -> PackedVector3Array:
	# A rectangular loop that follows the right-hand lane of the outer roads.
	var points: PackedVector3Array = PackedVector3Array()
	if _road_positions_x.size() < 2 or _road_positions_z.size() < 2:
		return points

	var lane: float = ROAD_WIDTH * 0.25
	var x_min: float = _road_positions_x[0]
	var x_max: float = _road_positions_x[_road_positions_x.size() - 1]
	var z_min: float = _road_positions_z[0]
	var z_max: float = _road_positions_z[_road_positions_z.size() - 1]

	var step: float = 20.0
	var y: float = 0.55

	var x: float = x_min + lane
	while x < x_max:
		points.append(Vector3(x, y, z_min + lane))
		x += step
	var z: float = z_min + lane
	while z < z_max:
		points.append(Vector3(x_max + lane, y, z))
		z += step
	x = x_max + lane
	while x > x_min:
		points.append(Vector3(x, y, z_max + lane))
		x -= step
	z = z_max + lane
	while z > z_min:
		points.append(Vector3(x_min + lane, y, z))
		z -= step

	return points


# ---------------------------------------------------------------------------
# Safe loading helpers
# ---------------------------------------------------------------------------

func _safe_load_material(path: String, fallback_color: Color) -> Material:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Material:
			return res as Material
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = fallback_color
	mat.roughness = 0.9
	return mat


func _safe_load_shader(path: String) -> Shader:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is Shader:
		return res as Shader
	return null


func _safe_load_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is PackedScene:
		return res as PackedScene
	return null


func _safe_load_script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is Script:
		return res as Script
	return null


func get_spawn_transform() -> Transform3D:
	var x: float = 0.0
	if _road_positions_x.size() > 0:
		x = _road_positions_x[0] + ROAD_WIDTH * 0.25
	var t: Transform3D = Transform3D.IDENTITY
	t.origin = Vector3(x, 1.6, -BLOCK_SIZE * 0.8)
	# Identity basis already points the bus along +Z, which is the
	# VehicleBody3D forward direction, so it drives up the road on spawn.
	return t
