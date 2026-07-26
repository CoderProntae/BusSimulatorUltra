extends Control

## Corner mini-map: shows the city grid, every bus stop, and -- the point of
## the whole thing -- WHERE THE PASSENGERS ONBOARD WANT TO GO.
##
## Drawn with _draw() rather than sprites so it costs one draw pass and needs
## no texture assets.
##
## Colour key:
##   cyan filled + ring   = a stop somebody onboard is travelling to
##   white dot            = an ordinary stop
##   yellow arrow         = the bus (points the way it is facing)
##   cyan line            = bearing to the nearest destination

## World-space radius covered by the map, in metres.
const VIEW_RANGE: float = 190.0
const BG_COLOR: Color = Color(0.05, 0.07, 0.10, 0.78)
const BORDER_COLOR: Color = Color(0.55, 0.68, 0.85, 0.85)
const ROAD_COLOR: Color = Color(0.24, 0.28, 0.34, 0.9)
const STOP_COLOR: Color = Color(0.82, 0.86, 0.92, 0.85)
const TARGET_COLOR: Color = Color(0.20, 0.92, 0.78, 1.0)
const BUS_COLOR: Color = Color(1.0, 0.82, 0.22, 1.0)

var bus: Node3D = null

var _radius: float = 96.0
var _pulse: float = 0.0
## Cached from GameState so _draw() never walks the whole stop list.
var _target_positions: Array[Vector3] = []
var _all_positions: Array[Vector3] = []
var _road_lines: PackedVector2Array = PackedVector2Array()
var _roads_ready: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameState != null:
		GameState.destinations_changed.connect(_refresh_targets)
	_refresh_targets()
	# Stops register themselves deferred, so the list is empty right now.
	# Re-read it periodically instead of assuming one snapshot is correct.
	var timer: Timer = Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_refresh_targets)
	add_child(timer)


func setup(bus_node: Node3D, radius: float) -> void:
	bus = bus_node
	_radius = radius
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	size = custom_minimum_size
	pivot_offset = Vector2(radius, radius)


func _process(delta: float) -> void:
	_pulse += delta
	# main.gd assigns the HUD's bus AFTER the HUD is built, so the reference
	# handed to setup() can legitimately still be null on the first frames.
	if bus == null or not is_instance_valid(bus):
		_find_bus()
	queue_redraw()


func _find_bus() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var buses: Array = tree.get_nodes_in_group("bus")
	if buses.size() > 0 and buses[0] is Node3D:
		bus = buses[0] as Node3D


func _refresh_targets() -> void:
	_target_positions.clear()
	_all_positions.clear()
	if GameState == null:
		return

	var i: int = 0
	while i < GameState.stops.size():
		var entry: Dictionary = GameState.stops[i]
		var pos: Vector3 = entry.get("position", Vector3.ZERO)
		var stop_name: String = String(entry.get("name", ""))
		_all_positions.append(pos)
		if GameState.passengers_for(stop_name) > 0:
			_target_positions.append(pos)
		i += 1


func set_road_grid(xs: Array, zs: Array, extent: float) -> void:
	## Called once by the HUD with the city's road centre lines so the map has
	## a street layout instead of an empty circle.
	_road_lines.clear()
	var i: int = 0
	while i < xs.size():
		var x: float = float(xs[i])
		_road_lines.append(Vector2(x, -extent))
		_road_lines.append(Vector2(x, extent))
		i += 1
	var j: int = 0
	while j < zs.size():
		var z: float = float(zs[j])
		_road_lines.append(Vector2(-extent, z))
		_road_lines.append(Vector2(extent, z))
		j += 1
	_roads_ready = _road_lines.size() > 0


func _draw() -> void:
	var centre: Vector2 = Vector2(_radius, _radius)

	draw_circle(centre, _radius, BG_COLOR)

	if bus == null or not is_instance_valid(bus):
		draw_arc(centre, _radius - 1.0, 0.0, TAU, 48, BORDER_COLOR, 2.0, true)
		return

	var bus_pos: Vector3 = bus.global_position
	# The bus faces +Z (Vector3.MODEL_FRONT), so that is the heading.
	var forward: Vector3 = bus.global_transform.basis.z
	var heading: float = atan2(forward.x, forward.z)

	# Rotate the world so the bus always points up the screen.
	var cos_h: float = cos(-heading)
	var sin_h: float = sin(-heading)
	var scale: float = _radius / VIEW_RANGE

	# --- roads ---
	if _roads_ready:
		var i: int = 0
		while i < _road_lines.size() - 1:
			var a: Vector2 = _world_to_map(
				_road_lines[i], bus_pos, cos_h, sin_h, scale, centre)
			var b: Vector2 = _world_to_map(
				_road_lines[i + 1], bus_pos, cos_h, sin_h, scale, centre)
			# Cheap reject: skip segments entirely outside the dial.
			if not (_outside(a, centre) and _outside(b, centre)):
				draw_line(a, b, ROAD_COLOR, 2.0)
			i += 2

	# --- ordinary stops ---
	var s: int = 0
	while s < _all_positions.size():
		var p: Vector3 = _all_positions[s]
		var flat: Vector2 = Vector2(p.x, p.z)
		var point: Vector2 = _world_to_map(flat, bus_pos, cos_h, sin_h, scale, centre)
		if not _outside(point, centre):
			draw_circle(point, 2.6, STOP_COLOR)
		s += 1

	# --- destinations the passengers onboard are paying for ---
	var pulse_scale: float = 1.0 + sin(_pulse * 3.4) * 0.22
	var nearest: Vector2 = Vector2.ZERO
	var nearest_dist: float = -1.0
	var has_target: bool = false

	var t: int = 0
	while t < _target_positions.size():
		var p3: Vector3 = _target_positions[t]
		var flat2: Vector2 = Vector2(p3.x, p3.z)
		var point2: Vector2 = _world_to_map(flat2, bus_pos, cos_h, sin_h, scale, centre)

		var world_dist: float = Vector2(bus_pos.x, bus_pos.z).distance_to(flat2)
		if nearest_dist < 0.0 or world_dist < nearest_dist:
			nearest_dist = world_dist
			nearest = point2
			has_target = true

		var clamped: Vector2 = _clamp_to_dial(point2, centre)
		draw_circle(clamped, 5.0 * pulse_scale, TARGET_COLOR)
		draw_arc(clamped, 8.5 * pulse_scale, 0.0, TAU, 20,
			TARGET_COLOR, 1.6, true)
		t += 1

	# --- bearing line to the nearest destination ---
	if has_target:
		var edge: Vector2 = _clamp_to_dial(nearest, centre)
		draw_line(centre, edge, Color(TARGET_COLOR.r, TARGET_COLOR.g,
			TARGET_COLOR.b, 0.42), 2.0)

	# --- the bus itself, always dead centre pointing up ---
	var nose: Vector2 = centre + Vector2(0.0, -9.0)
	var left: Vector2 = centre + Vector2(-6.0, 6.0)
	var right: Vector2 = centre + Vector2(6.0, 6.0)
	draw_colored_polygon(PackedVector2Array([nose, left, right]), BUS_COLOR)

	draw_arc(centre, _radius - 1.0, 0.0, TAU, 48, BORDER_COLOR, 2.0, true)


func _world_to_map(flat: Vector2, bus_pos: Vector3, cos_h: float, sin_h: float,
		scale: float, centre: Vector2) -> Vector2:
	var dx: float = flat.x - bus_pos.x
	var dz: float = flat.y - bus_pos.z
	# Rotate into bus-relative space.
	var rx: float = dx * cos_h - dz * sin_h
	var rz: float = dx * sin_h + dz * cos_h
	# Screen Y grows downward and the bus looks "up", so negate Z.
	return centre + Vector2(rx * scale, -rz * scale)


func _outside(point: Vector2, centre: Vector2) -> bool:
	return point.distance_to(centre) > _radius - 2.0


func _clamp_to_dial(point: Vector2, centre: Vector2) -> Vector2:
	## Keeps off-screen destinations pinned to the rim so the driver always
	## has an arrow to follow, instead of the marker vanishing.
	var offset: Vector2 = point - centre
	var limit: float = _radius - 10.0
	if offset.length() <= limit:
		return point
	return centre + offset.normalized() * limit
