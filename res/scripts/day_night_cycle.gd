extends Node3D

## 5-minute day/night cycle. Rotates the sun, retints the light, drives the
## WorldEnvironment ambient/fog and publishes a night factor that street lamps,
## building windows and the bus headlights react to.

signal night_started()
signal day_started()

const CYCLE_SECONDS: float = 300.0

@export var sun_path: NodePath
@export var environment_path: NodePath
@export var start_hour: float = 8.0
@export var paused: bool = false

var _sun: DirectionalLight3D = null
var _world_env: WorldEnvironment = null
var _time_norm: float = 0.0
var _is_night: bool = false
var _lamp_nodes: Array = []
var _window_materials: Array = []
var _refresh_accum: float = 0.0

const DAY_SUN_COLOR: Color = Color(1.0, 0.96, 0.88)
const SUNSET_COLOR: Color = Color(1.0, 0.62, 0.35)
const NIGHT_COLOR: Color = Color(0.42, 0.52, 0.78)


func _ready() -> void:
	if sun_path != NodePath("") and has_node(sun_path):
		_sun = get_node(sun_path) as DirectionalLight3D
	if environment_path != NodePath("") and has_node(environment_path):
		_world_env = get_node(environment_path) as WorldEnvironment

	if _sun == null:
		_sun = _find_first_sun(get_tree().get_root())
	if _world_env == null:
		_world_env = _find_first_env(get_tree().get_root())

	_time_norm = fposmod(start_hour, 24.0) / 24.0
	_refresh_registries()
	_apply(0.0)


func _find_first_sun(node: Node) -> DirectionalLight3D:
	if node is DirectionalLight3D:
		return node as DirectionalLight3D
	var i: int = 0
	var children: Array = node.get_children()
	while i < children.size():
		var found: DirectionalLight3D = _find_first_sun(children[i])
		if found != null:
			return found
		i += 1
	return null


func _find_first_env(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	var i: int = 0
	var children: Array = node.get_children()
	while i < children.size():
		var found: WorldEnvironment = _find_first_env(children[i])
		if found != null:
			return found
		i += 1
	return null


func _process(delta: float) -> void:
	if paused:
		return
	_time_norm = fposmod(_time_norm + delta / CYCLE_SECONDS, 1.0)
	_refresh_accum += delta
	if _refresh_accum > 6.0:
		_refresh_accum = 0.0
		_refresh_registries()
	_apply(delta)


func _apply(delta: float) -> void:
	var hours: float = _time_norm * 24.0
	if GameState != null:
		GameState.set_clock(hours)

	# Sun elevation: peaks at noon, below horizon at night.
	var sun_angle: float = (_time_norm * 360.0) - 90.0
	if _sun != null and is_instance_valid(_sun):
		_sun.rotation_degrees = Vector3(-sun_angle, -32.0, 0.0)

	var elevation: float = sin((_time_norm - 0.25) * TAU)
	var day_amount: float = clampf(elevation * 1.6 + 0.35, 0.0, 1.0)
	var night: float = clampf(1.0 - day_amount * 1.25, 0.0, 1.0)

	if GameState != null:
		GameState.set_night_factor(night)

	if _sun != null and is_instance_valid(_sun):
		var energy: float = lerpf(0.04, 1.3, day_amount)
		_sun.light_energy = energy
		var horizon_mix: float = clampf(1.0 - absf(elevation) * 2.4, 0.0, 1.0)
		var col: Color = DAY_SUN_COLOR.lerp(SUNSET_COLOR, horizon_mix)
		col = col.lerp(NIGHT_COLOR, night * 0.7)
		_sun.light_color = col
		_sun.visible = day_amount > 0.005
		_sun.shadow_enabled = true

	_apply_environment(night, day_amount)
	_apply_lamps(night)
	_apply_windows(night)

	var now_night: bool = night > 0.55
	if now_night != _is_night:
		_is_night = now_night
		if _is_night:
			emit_signal("night_started")
			if GameState != null:
				GameState.notify("Night falling - headlights recommended")
		else:
			emit_signal("day_started")
			if GameState != null:
				GameState.notify("Sunrise - good morning driver")


func _apply_environment(night: float, day_amount: float) -> void:
	if _world_env == null or not is_instance_valid(_world_env):
		return
	var env: Environment = _world_env.environment
	if env == null:
		return

	env.ambient_light_energy = lerpf(0.12, 0.85, day_amount)
	env.ambient_light_color = Color(0.42, 0.52, 0.72).lerp(Color(0.85, 0.90, 1.0), day_amount)

	if env.sky != null:
		var sky_mat: Material = env.sky.sky_material
		if sky_mat is PanoramaSkyMaterial:
			var pano: PanoramaSkyMaterial = sky_mat as PanoramaSkyMaterial
			pano.energy_multiplier = lerpf(0.06, 1.0, day_amount)

	env.fog_light_color = Color(0.10, 0.14, 0.24).lerp(Color(0.72, 0.80, 0.92), day_amount)

	# Keep this in sync with World.tscn. These values are deliberately tiny:
	# fog_density is per-metre, so 0.0012 still covers ~45% at 500 m while
	# leaving the near field (the bus, the next junction) perfectly clear.
	# Do NOT re-enable height fog here - fog_height_density increases fog as
	# height DECREASES, which whites out the whole street at ground level.
	env.fog_density = lerpf(0.0018, 0.0012, day_amount)
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = lerpf(0.028, 0.018, day_amount)
	env.glow_intensity = lerpf(0.7, 0.45, day_amount)


func _apply_lamps(night: float) -> void:
	var on: bool = night > 0.42
	var energy: float = clampf((night - 0.35) / 0.4, 0.0, 1.0)
	var i: int = 0
	while i < _lamp_nodes.size():
		var lamp: Node = _lamp_nodes[i]
		if is_instance_valid(lamp):
			if lamp.has_method("set_night_energy"):
				lamp.call("set_night_energy", energy, on)
		i += 1


func _apply_windows(night: float) -> void:
	var i: int = 0
	while i < _window_materials.size():
		var mat: Variant = _window_materials[i]
		if mat is ShaderMaterial:
			var shader_mat: ShaderMaterial = mat as ShaderMaterial
			shader_mat.set_shader_parameter("night", night)
		i += 1


func _refresh_registries() -> void:
	_lamp_nodes = get_tree().get_nodes_in_group("street_lamp")

	_window_materials.clear()
	var buildings: Array = get_tree().get_nodes_in_group("building_facade")
	var i: int = 0
	while i < buildings.size():
		var node: Node = buildings[i]
		if node is MeshInstance3D:
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			var mat: Material = mesh_node.get_surface_override_material(0)
			if mat == null and mesh_node.mesh != null:
				mat = mesh_node.mesh.surface_get_material(0)
			if mat is ShaderMaterial:
				_window_materials.append(mat)
		i += 1


func get_night_factor() -> float:
	if GameState != null:
		return GameState.night_factor
	return 0.0


func set_time_of_day(hours: float) -> void:
	_time_norm = fposmod(hours, 24.0) / 24.0
	_apply(0.0)
