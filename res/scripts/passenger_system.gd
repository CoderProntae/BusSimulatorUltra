extends Area3D

## Bus stop logic with DELIVER-FIRST-THEN-BOARD ordering:
##   1. passengers whose destination is this stop get off (earning coins)
##   2. then waiting passengers board (up to remaining capacity)
##
## The bus must be stopped with its doors open for the exchange to run.

signal passengers_alighted(count: int, earned: int)
signal passengers_boarded(count: int)
signal stop_service_finished()

const EXCHANGE_INTERVAL: float = 0.55

@export var stop_name: String = "City Stop"
@export var waiting_min: int = 1
@export var waiting_max: int = 6
@export var respawn_seconds: float = 26.0

var waiting_passengers: int = 0

var _bus: Node3D = null
var _timer: float = 0.0
var _respawn_timer: float = 0.0
var _phase: int = 0  # 0 = idle, 1 = alighting, 2 = boarding
var _to_alight: int = 0
var _served_this_visit: bool = false
var _queue_markers: Array[Node3D] = []
var _sign_material: StandardMaterial3D = null
var _shelter_light: OmniLight3D = null


func _ready() -> void:
	add_to_group("bus_stop")
	monitoring = true
	monitorable = false

	if _needs_shape():
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(9.0, 5.0, 12.0)
		shape.shape = box
		shape.position = Vector3(0.0, 2.5, 0.0)
		add_child(shape)

	waiting_passengers = randi_range(waiting_min, waiting_max)
	_build_shelter()
	_refresh_queue_visuals()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if GameState != null:
		GameState.night_factor_changed.connect(_on_night_changed)
		# Register on the global map. Deferred so city_builder has finished
		# positioning us: global_position is meaningless before that.
		_register_on_map.call_deferred()


func _register_on_map() -> void:
	if GameState == null:
		return
	GameState.register_stop(stop_name, global_position, self)


func _needs_shape() -> bool:
	var children: Array = get_children()
	var i: int = 0
	while i < children.size():
		if children[i] is CollisionShape3D:
			return false
		i += 1
	return true


func _physics_process(delta: float) -> void:
	# Slowly refill the queue over time so the route never runs dry.
	_respawn_timer += delta
	if _respawn_timer >= respawn_seconds:
		_respawn_timer = 0.0
		if waiting_passengers < waiting_max:
			waiting_passengers += 1
			_refresh_queue_visuals()

	if _bus == null or not is_instance_valid(_bus):
		return
	if GameState == null:
		return

	var stopped: bool = true
	var doors_open: bool = true
	if _bus is VehicleBody3D:
		var bus: VehicleBody3D = _bus as VehicleBody3D
		stopped = bus.linear_velocity.length() * 3.6 < 3.0
	if _bus.has_method("is_stopped"):
		stopped = bool(_bus.call("is_stopped"))
	if "doors_open" in _bus:
		doors_open = bool(_bus.get("doors_open"))

	if not (stopped and doors_open):
		return

	if _phase == 0:
		if _served_this_visit:
			return
		_begin_service()

	_timer += delta
	if _timer < EXCHANGE_INTERVAL:
		return
	_timer = 0.0

	if _phase == 1:
		_do_alight_step()
	elif _phase == 2:
		_do_board_step()


func _begin_service() -> void:
	# How many onboard passengers actually bought a ticket to THIS stop.
	# This used to be a random slice of everyone onboard, which is why the
	# game could never tell the player where to go: nobody had a destination.
	_to_alight = GameState.passengers_for(stop_name)
	_phase = 1
	_timer = 0.0
	GameState.notify("Arrived at " + stop_name)


func _do_alight_step() -> void:
	if _to_alight <= 0:
		_phase = 2
		return
	# Clear the ticket first so the map marker updates as they step off.
	GameState.take_destination(stop_name, 1)
	var earned: int = GameState.alight_passengers(1)
	_to_alight -= 1
	emit_signal("passengers_alighted", 1, earned)
	if earned > 0:
		GameState.notify("Passenger dropped off  +" + str(earned) + " coins")
	if _to_alight <= 0:
		_phase = 2


func _do_board_step() -> void:
	if waiting_passengers <= 0 or GameState.free_seats() <= 0:
		_finish_service()
		return
	var boarded: int = GameState.board_passengers(1)
	if boarded <= 0:
		if GameState.free_seats() <= 0:
			GameState.notify("Bus is full")
		_finish_service()
		return
	waiting_passengers -= 1
	_refresh_queue_visuals()

	# Give the new passenger a real destination so the map can show it.
	var destination: String = GameState.pick_destination(stop_name)
	if destination != "":
		GameState.add_destination(destination, boarded)
		GameState.notify("Passenger boarding for " + destination)

	emit_signal("passengers_boarded", boarded)
	if waiting_passengers <= 0:
		_finish_service()


func _finish_service() -> void:
	_phase = 0
	_served_this_visit = true
	emit_signal("stop_service_finished")
	GameState.notify("Ready to depart from " + stop_name)


func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if body.is_in_group("bus"):
		_bus = body as Node3D
		_served_this_visit = false
		_phase = 0
		_timer = 0.0
		if GameState != null:
			_announce_arrival()


func _announce_arrival() -> void:
	## Tell the driver both halves of the job at this stop: who wants OFF
	## here (which is what the map marker was pointing at) and who wants ON.
	var dropping: int = GameState.passengers_for(stop_name)
	if dropping > 0:
		GameState.notify(stop_name + ": DROP OFF " + str(dropping)
			+ " here - stop and open doors")
		return
	var count: String = str(waiting_passengers)
	GameState.notify(stop_name + ": " + count + " waiting - stop and open doors")


func _on_body_exited(body: Node) -> void:
	if body == _bus:
		_bus = null
		_phase = 0
		_served_this_visit = false


func _on_night_changed(night: float) -> void:
	if _sign_material != null:
		_sign_material.emission_energy_multiplier = 1.2 + night * 2.6
	if _shelter_light != null and is_instance_valid(_shelter_light):
		_shelter_light.light_energy = night * 2.2
		_shelter_light.visible = night > 0.35


# ---------------------------------------------------------------------------
# Shelter visuals: bench + roof + route sign + waiting passenger figures
# ---------------------------------------------------------------------------

func _build_shelter() -> void:
	var glass_mat: StandardMaterial3D = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.55, 0.68, 0.75, 0.30)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.metallic = 0.8
	glass_mat.roughness = 0.08
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var frame_mat: StandardMaterial3D = StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.16, 0.17, 0.19)
	frame_mat.metallic = 0.8
	frame_mat.roughness = 0.3

	var concrete: Material = _load_material("res://materials/concrete.tres")

	# platform
	var platform: MeshInstance3D = MeshInstance3D.new()
	platform.name = "Platform"
	var platform_mesh: BoxMesh = BoxMesh.new()
	platform_mesh.size = Vector3(4.2, 0.22, 9.0)
	platform.mesh = platform_mesh
	platform.position = Vector3(-2.6, 0.14, 0.0)
	if concrete != null:
		platform.set_surface_override_material(0, concrete)
	add_child(platform)

	# roof
	var roof: MeshInstance3D = MeshInstance3D.new()
	roof.name = "ShelterRoof"
	var roof_mesh: BoxMesh = BoxMesh.new()
	roof_mesh.size = Vector3(3.4, 0.14, 6.4)
	roof.mesh = roof_mesh
	roof.position = Vector3(-3.0, 3.05, 0.0)
	var roof_mat: StandardMaterial3D = StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.20, 0.42, 0.58)
	roof_mat.metallic = 0.6
	roof_mat.roughness = 0.3
	roof.set_surface_override_material(0, roof_mat)
	add_child(roof)

	# back glass wall
	var back: MeshInstance3D = MeshInstance3D.new()
	back.name = "ShelterGlass"
	var back_mesh: BoxMesh = BoxMesh.new()
	back_mesh.size = Vector3(0.1, 2.4, 6.2)
	back.mesh = back_mesh
	back.position = Vector3(-4.5, 1.8, 0.0)
	back.set_surface_override_material(0, glass_mat)
	add_child(back)

	# side glass panels
	var side_zs: Array[float] = [-3.1, 3.1]
	var si: int = 0
	while si < side_zs.size():
		var side_glass: MeshInstance3D = MeshInstance3D.new()
		side_glass.name = "ShelterSide" + str(si)
		var side_mesh: BoxMesh = BoxMesh.new()
		side_mesh.size = Vector3(3.2, 2.4, 0.1)
		side_glass.mesh = side_mesh
		side_glass.position = Vector3(-3.0, 1.8, side_zs[si])
		side_glass.set_surface_override_material(0, glass_mat)
		add_child(side_glass)
		si += 1

	# corner posts
	var post_zs: Array[float] = [-3.1, 3.1]
	var pi_index: int = 0
	while pi_index < post_zs.size():
		var post: MeshInstance3D = MeshInstance3D.new()
		post.name = "Post" + str(pi_index)
		var post_mesh: CylinderMesh = CylinderMesh.new()
		post_mesh.top_radius = 0.07
		post_mesh.bottom_radius = 0.07
		post_mesh.height = 3.0
		post_mesh.radial_segments = 8
		post.mesh = post_mesh
		post.position = Vector3(-1.5, 1.5, post_zs[pi_index])
		post.set_surface_override_material(0, frame_mat)
		add_child(post)
		pi_index += 1

	# bench
	var bench: MeshInstance3D = MeshInstance3D.new()
	bench.name = "Bench"
	var bench_mesh: BoxMesh = BoxMesh.new()
	bench_mesh.size = Vector3(0.7, 0.12, 4.4)
	bench.mesh = bench_mesh
	bench.position = Vector3(-4.0, 0.75, 0.0)
	var bench_mat: StandardMaterial3D = StandardMaterial3D.new()
	bench_mat.albedo_color = Color(0.42, 0.28, 0.16)
	bench_mat.roughness = 0.85
	bench.set_surface_override_material(0, bench_mat)
	add_child(bench)

	var bench_legs: Array[float] = [-1.8, 1.8]
	var bl: int = 0
	while bl < bench_legs.size():
		var leg: MeshInstance3D = MeshInstance3D.new()
		leg.name = "BenchLeg" + str(bl)
		var leg_mesh: BoxMesh = BoxMesh.new()
		leg_mesh.size = Vector3(0.6, 0.65, 0.1)
		leg.mesh = leg_mesh
		leg.position = Vector3(-4.0, 0.42, bench_legs[bl])
		leg.set_surface_override_material(0, frame_mat)
		add_child(leg)
		bl += 1

	# route sign (emissive at night)
	var sign_pole: MeshInstance3D = MeshInstance3D.new()
	sign_pole.name = "SignPole"
	var sign_pole_mesh: CylinderMesh = CylinderMesh.new()
	sign_pole_mesh.top_radius = 0.06
	sign_pole_mesh.bottom_radius = 0.06
	sign_pole_mesh.height = 3.2
	sign_pole_mesh.radial_segments = 8
	sign_pole.mesh = sign_pole_mesh
	sign_pole.position = Vector3(-1.1, 1.6, 3.8)
	sign_pole.set_surface_override_material(0, frame_mat)
	add_child(sign_pole)

	var sign_panel: MeshInstance3D = MeshInstance3D.new()
	sign_panel.name = "RouteSign"
	var sign_mesh: BoxMesh = BoxMesh.new()
	sign_mesh.size = Vector3(0.12, 0.9, 1.3)
	sign_panel.mesh = sign_mesh
	sign_panel.position = Vector3(-1.1, 3.0, 3.8)
	var sign_mat: StandardMaterial3D = StandardMaterial3D.new()
	sign_mat.albedo_color = Color(0.08, 0.28, 0.55)
	sign_mat.emission_enabled = true
	sign_mat.emission = Color(0.35, 0.75, 1.0)
	sign_mat.emission_energy_multiplier = 1.4
	sign_mat.roughness = 0.4
	sign_panel.set_surface_override_material(0, sign_mat)
	add_child(sign_panel)
	_sign_material = sign_mat

	var label: Label3D = Label3D.new()
	label.name = "StopLabel"
	label.text = stop_name
	label.font_size = 64
	label.pixel_size = 0.006
	label.position = Vector3(-0.98, 3.0, 3.8)
	label.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	label.modulate = Color(1.0, 1.0, 1.0)
	label.outline_size = 10
	label.double_sided = true
	add_child(label)

	var shelter_lamp: OmniLight3D = OmniLight3D.new()
	shelter_lamp.name = "ShelterLight"
	shelter_lamp.position = Vector3(-3.0, 2.8, 0.0)
	shelter_lamp.light_color = Color(0.95, 0.95, 0.85)
	shelter_lamp.light_energy = 0.0
	shelter_lamp.omni_range = 9.0
	shelter_lamp.shadow_enabled = false
	shelter_lamp.visible = false
	add_child(shelter_lamp)
	_shelter_light = shelter_lamp

	_build_queue_figures()


func _build_queue_figures() -> void:
	# Simple stylised people standing in the queue.
	var i: int = 0
	while i < waiting_max:
		var person: Node3D = Node3D.new()
		person.name = "Passenger" + str(i)
		person.position = Vector3(-1.9, 0.25, -2.4 + float(i) * 1.0)
		add_child(person)

		var hue: float = fmod(0.13 * float(i) + 0.42, 1.0)
		var body_mat: StandardMaterial3D = StandardMaterial3D.new()
		body_mat.albedo_color = Color.from_hsv(hue, 0.55, 0.72)
		body_mat.roughness = 0.85

		var skin_mat: StandardMaterial3D = StandardMaterial3D.new()
		skin_mat.albedo_color = Color(0.82, 0.66, 0.52)
		skin_mat.roughness = 0.8

		var torso: MeshInstance3D = MeshInstance3D.new()
		torso.name = "Torso"
		var torso_mesh: CapsuleMesh = CapsuleMesh.new()
		torso_mesh.radius = 0.19
		torso_mesh.height = 1.15
		torso_mesh.radial_segments = 10
		torso_mesh.rings = 4
		torso.mesh = torso_mesh
		torso.position = Vector3(0.0, 0.75, 0.0)
		torso.set_surface_override_material(0, body_mat)
		person.add_child(torso)

		var head: MeshInstance3D = MeshInstance3D.new()
		head.name = "Head"
		var head_mesh: SphereMesh = SphereMesh.new()
		head_mesh.radius = 0.15
		head_mesh.height = 0.3
		head_mesh.radial_segments = 12
		head_mesh.rings = 8
		head.mesh = head_mesh
		head.position = Vector3(0.0, 1.5, 0.0)
		head.set_surface_override_material(0, skin_mat)
		person.add_child(head)

		var legs: MeshInstance3D = MeshInstance3D.new()
		legs.name = "Legs"
		var legs_mesh: BoxMesh = BoxMesh.new()
		legs_mesh.size = Vector3(0.28, 0.62, 0.22)
		legs.mesh = legs_mesh
		legs.position = Vector3(0.0, 0.31, 0.0)
		var leg_mat: StandardMaterial3D = StandardMaterial3D.new()
		leg_mat.albedo_color = Color(0.14, 0.16, 0.24)
		leg_mat.roughness = 0.9
		legs.set_surface_override_material(0, leg_mat)
		person.add_child(legs)

		_queue_markers.append(person)
		i += 1


func _refresh_queue_visuals() -> void:
	var i: int = 0
	while i < _queue_markers.size():
		var node: Node3D = _queue_markers[i]
		if is_instance_valid(node):
			node.visible = i < waiting_passengers
		i += 1


func _load_material(path: String) -> Material:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is Material:
		return res as Material
	return null
