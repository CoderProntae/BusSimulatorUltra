extends Area3D

## Fuel station trigger. Refuels the bus while it is stopped inside the
## station area, charging coins per litre. Also builds the visible station
## (canopy, pumps, emissive price sign) if it was not placed in a scene.

signal refuel_started()
signal refuel_finished(litres: float, cost: int)

const LITRES_PER_SECOND: float = 26.0

@export var build_visuals: bool = false

var _bus_inside: Node3D = null
var _refuelling: bool = false
var _session_litres: float = 0.0
var _session_cost_float: float = 0.0
var _charge_remainder: float = 0.0
var _price_material: StandardMaterial3D = null
var _pump_lights: Array[OmniLight3D] = []


func _ready() -> void:
	add_to_group("fuel_station")
	monitoring = true
	monitorable = false

	if get_child_count() == 0 or _needs_shape():
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(16.0, 6.0, 12.0)
		shape.shape = box
		shape.position = Vector3(0.0, 3.0, 0.0)
		add_child(shape)

	if build_visuals:
		_build_station()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if GameState != null:
		GameState.night_factor_changed.connect(_on_night_changed)


func _needs_shape() -> bool:
	var i: int = 0
	var children: Array = get_children()
	while i < children.size():
		if children[i] is CollisionShape3D:
			return false
		i += 1
	return true


func _physics_process(delta: float) -> void:
	if _bus_inside == null or not is_instance_valid(_bus_inside):
		_stop_refuel()
		return
	if GameState == null:
		return

	var stopped: bool = true
	if _bus_inside is VehicleBody3D:
		var bus: VehicleBody3D = _bus_inside as VehicleBody3D
		stopped = bus.linear_velocity.length() * 3.6 < 4.0

	if not stopped:
		_stop_refuel()
		return

	if GameState.fuel >= GameState.FUEL_CAPACITY - 0.01:
		if _refuelling:
			_stop_refuel()
		return

	# Can the driver afford another tick?
	var wanted: float = LITRES_PER_SECOND * delta
	var tick_cost: float = wanted * GameState.FUEL_PRICE_PER_LITRE
	if GameState.money <= 0:
		if _refuelling:
			GameState.notify("Not enough coins to refuel")
			_stop_refuel()
		return

	if not _refuelling:
		_refuelling = true
		_session_litres = 0.0
		_session_cost_float = 0.0
		emit_signal("refuel_started")
		GameState.notify("Refuelling...")

	var added: float = GameState.add_fuel(wanted)
	if added <= 0.0:
		_stop_refuel()
		return

	_session_litres += added
	var cost_float: float = added * GameState.FUEL_PRICE_PER_LITRE
	_session_cost_float += cost_float
	_charge_remainder += cost_float

	# Charge whole coins as they accumulate.
	while _charge_remainder >= 1.0:
		if not GameState.spend_money(1):
			_charge_remainder = 0.0
			GameState.notify("Out of coins - refuelling stopped")
			_stop_refuel()
			return
		_charge_remainder -= 1.0


func _stop_refuel() -> void:
	if not _refuelling:
		return
	_refuelling = false
	var cost: int = int(round(_session_cost_float))
	emit_signal("refuel_finished", _session_litres, cost)
	if GameState != null and _session_litres > 1.0:
		var litres_text: String = str(int(round(_session_litres)))
		var cost_text: String = str(cost)
		GameState.notify("Refuelled " + litres_text + " L for " + cost_text + " coins")
	_session_litres = 0.0
	_session_cost_float = 0.0


func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if body.is_in_group("bus"):
		_bus_inside = body as Node3D
		if GameState != null:
			var price: String = str(GameState.FUEL_PRICE_PER_LITRE)
			GameState.notify("Fuel station - stop to refuel (" + price + " coins/L)")


func _on_body_exited(body: Node) -> void:
	if body == _bus_inside:
		_stop_refuel()
		_bus_inside = null


func _on_night_changed(night: float) -> void:
	if _price_material != null:
		_price_material.emission_energy_multiplier = 1.5 + night * 3.0
	var i: int = 0
	while i < _pump_lights.size():
		var light: OmniLight3D = _pump_lights[i]
		if is_instance_valid(light):
			light.light_energy = 0.3 + night * 2.6
		i += 1


func is_refuelling() -> bool:
	return _refuelling


# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------

func _build_station() -> void:
	var concrete: Material = _load_material("res://materials/concrete.tres")

	var pad: MeshInstance3D = MeshInstance3D.new()
	pad.name = "StationPad"
	var pad_mesh: BoxMesh = BoxMesh.new()
	pad_mesh.size = Vector3(18.0, 0.16, 14.0)
	pad.mesh = pad_mesh
	pad.position = Vector3(0.0, 0.08, 0.0)
	if concrete != null:
		pad.set_surface_override_material(0, concrete)
	add_child(pad)

	var canopy_mat: StandardMaterial3D = StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.92, 0.93, 0.95)
	canopy_mat.metallic = 0.5
	canopy_mat.roughness = 0.35

	var canopy: MeshInstance3D = MeshInstance3D.new()
	canopy.name = "Canopy"
	var canopy_mesh: BoxMesh = BoxMesh.new()
	canopy_mesh.size = Vector3(16.0, 0.5, 12.0)
	canopy.mesh = canopy_mesh
	canopy.position = Vector3(0.0, 6.2, 0.0)
	canopy.set_surface_override_material(0, canopy_mat)
	add_child(canopy)

	var band: MeshInstance3D = MeshInstance3D.new()
	band.name = "CanopyBand"
	var band_mesh: BoxMesh = BoxMesh.new()
	band_mesh.size = Vector3(16.2, 0.45, 12.2)
	band.mesh = band_mesh
	band.position = Vector3(0.0, 5.85, 0.0)
	var band_mat: StandardMaterial3D = StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.05, 0.42, 0.22)
	band_mat.emission_enabled = true
	band_mat.emission = Color(0.10, 0.85, 0.42)
	band_mat.emission_energy_multiplier = 1.4
	band_mat.roughness = 0.4
	band.set_surface_override_material(0, band_mat)
	add_child(band)

	var pillar_mat: StandardMaterial3D = StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.78, 0.79, 0.82)
	pillar_mat.metallic = 0.7
	pillar_mat.roughness = 0.3

	var xs: Array[float] = [-7.0, 7.0]
	var zs: Array[float] = [-5.0, 5.0]
	var a: int = 0
	while a < xs.size():
		var b: int = 0
		while b < zs.size():
			var pillar: MeshInstance3D = MeshInstance3D.new()
			pillar.name = "Pillar" + str(a) + str(b)
			var pillar_mesh: CylinderMesh = CylinderMesh.new()
			pillar_mesh.top_radius = 0.24
			pillar_mesh.bottom_radius = 0.28
			pillar_mesh.height = 6.0
			pillar_mesh.radial_segments = 12
			pillar.mesh = pillar_mesh
			pillar.position = Vector3(xs[a], 3.0, zs[b])
			pillar.set_surface_override_material(0, pillar_mat)
			add_child(pillar)
			b += 1
		a += 1

	# pumps
	var pump_xs: Array[float] = [-3.2, 3.2]
	var p: int = 0
	while p < pump_xs.size():
		_build_pump(pump_xs[p], p)
		p += 1

	_build_price_sign()

	# under-canopy lighting
	var light_xs: Array[float] = [-4.5, 4.5]
	var li: int = 0
	while li < light_xs.size():
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.name = "CanopyLight" + str(li)
		lamp.position = Vector3(light_xs[li], 5.6, 0.0)
		lamp.light_color = Color(0.95, 0.98, 1.0)
		lamp.light_energy = 1.2
		lamp.omni_range = 16.0
		lamp.shadow_enabled = false
		add_child(lamp)
		_pump_lights.append(lamp)
		li += 1


func _build_pump(x: float, index: int) -> void:
	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.88, 0.88, 0.90)
	body_mat.metallic = 0.55
	body_mat.roughness = 0.35

	var base: MeshInstance3D = MeshInstance3D.new()
	base.name = "PumpBase" + str(index)
	var base_mesh: BoxMesh = BoxMesh.new()
	base_mesh.size = Vector3(1.3, 0.35, 1.0)
	base.mesh = base_mesh
	base.position = Vector3(x, 0.28, 0.0)
	base.set_surface_override_material(0, body_mat)
	add_child(base)

	var column: MeshInstance3D = MeshInstance3D.new()
	column.name = "Pump" + str(index)
	var column_mesh: BoxMesh = BoxMesh.new()
	column_mesh.size = Vector3(1.1, 2.0, 0.75)
	column.mesh = column_mesh
	column.position = Vector3(x, 1.4, 0.0)
	column.set_surface_override_material(0, body_mat)
	add_child(column)

	var screen: MeshInstance3D = MeshInstance3D.new()
	screen.name = "PumpScreen" + str(index)
	var screen_mesh: BoxMesh = BoxMesh.new()
	screen_mesh.size = Vector3(0.8, 0.5, 0.06)
	screen.mesh = screen_mesh
	screen.position = Vector3(x, 1.85, 0.42)
	var screen_mat: StandardMaterial3D = StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0.03, 0.05, 0.04)
	screen_mat.emission_enabled = true
	screen_mat.emission = Color(0.25, 1.0, 0.45)
	screen_mat.emission_energy_multiplier = 2.0
	screen.set_surface_override_material(0, screen_mat)
	add_child(screen)

	var hose: MeshInstance3D = MeshInstance3D.new()
	hose.name = "PumpHose" + str(index)
	var hose_mesh: TorusMesh = TorusMesh.new()
	hose_mesh.inner_radius = 0.22
	hose_mesh.outer_radius = 0.3
	hose.mesh = hose_mesh
	hose.position = Vector3(x + 0.62, 1.1, 0.0)
	hose.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	var hose_mat: StandardMaterial3D = StandardMaterial3D.new()
	hose_mat.albedo_color = Color(0.06, 0.06, 0.07)
	hose_mat.roughness = 0.9
	hose.set_surface_override_material(0, hose_mat)
	add_child(hose)


func _build_price_sign() -> void:
	var pole: MeshInstance3D = MeshInstance3D.new()
	pole.name = "SignPole"
	var pole_mesh: CylinderMesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.18
	pole_mesh.bottom_radius = 0.22
	pole_mesh.height = 7.0
	pole_mesh.radial_segments = 10
	pole.mesh = pole_mesh
	pole.position = Vector3(-10.0, 3.5, -5.0)
	var pole_mat: StandardMaterial3D = StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.55, 0.56, 0.58)
	pole_mat.metallic = 0.75
	pole_mat.roughness = 0.35
	pole.set_surface_override_material(0, pole_mat)
	add_child(pole)

	var panel: MeshInstance3D = MeshInstance3D.new()
	panel.name = "PriceSign"
	var panel_mesh: BoxMesh = BoxMesh.new()
	panel_mesh.size = Vector3(3.4, 2.2, 0.25)
	panel.mesh = panel_mesh
	panel.position = Vector3(-10.0, 7.6, -5.0)
	var panel_mat: StandardMaterial3D = StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.85, 0.12, 0.10)
	panel_mat.emission_enabled = true
	panel_mat.emission = Color(1.0, 0.28, 0.12)
	panel_mat.emission_energy_multiplier = 1.8
	panel_mat.roughness = 0.4
	panel.set_surface_override_material(0, panel_mat)
	add_child(panel)
	_price_material = panel_mat

	var price_text: Label3D = Label3D.new()
	price_text.name = "PriceLabel"
	price_text.text = "FUEL\n1.4"
	price_text.font_size = 96
	price_text.position = Vector3(-10.0, 7.6, -4.84)
	price_text.modulate = Color(1.0, 0.98, 0.85)
	price_text.outline_size = 12
	price_text.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	price_text.double_sided = true
	price_text.pixel_size = 0.012
	add_child(price_text)


func _load_material(path: String) -> Material:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is Material:
		return res as Material
	return null
